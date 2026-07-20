#!/usr/bin/env bash
# gitlab-mr-review.sh
#
# Cross-platform (Linux/WSL) POSIX entrypoint for the shared AIDD GitLab MR
# review tooling. It is the Linux counterpart of gitlab-mr-review.cmd /
# gitlab-mr-review.ps1 and keeps exactly the same safe, read-only semantics:
#
#   - parse and validate the MR URL;
#   - read GitLab metadata only through `glab auth` for the MR URL host;
#   - ensure the current repo remote matches the MR target project;
#   - fetch the target branch and the MR head ref without switching the user
#     branch;
#   - create or reuse a detached worktree outside the repo under a safe Linux
#     review root;
#   - materialize manifest.json, mr.json, diff files, changed-files.json and
#     text snapshots that match the manifest schema of the Windows entrypoint;
#   - clean up only worktrees located under the managed review root.
#
# This entrypoint intentionally never publishes comments, approves, merges,
# checks out the user branch, uses curl, reads a token directly, or falls back
# to a git credential manager. Reading and answering MR threads lives in
# gitlab-tools, so this read-only entrypoint keeps its blanket permission
# without granting GitLab write access.
#
# Runtime dependencies: bash, git, glab (for `prepare` metadata) and python3
# (used only by `prepare`/`cleanup` as a JSON codec for glab responses and the
# manifest). The review root defaults to a per-user cache directory outside the
# repo and can be overridden with the AI_REVIEW_ROOT environment variable.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REVIEW_ROOT="${AI_REVIEW_ROOT:-${HOME}/.cache/ai-review-wt}"

# Scratch directory for prepare; removed on exit. Kept as a guarded global so
# the EXIT trap (which runs in global scope) never trips `set -u`.
PREPARE_TMP_DIR=""
cleanup_prepare_tmp() {
  if [[ -n "$PREPARE_TMP_DIR" ]]; then
    rm -rf "$PREPARE_TMP_DIR"
  fi
  return 0
}
trap cleanup_prepare_tmp EXIT

TEXT_EXTENSIONS=(
  ".bsl" ".mdo" ".form" ".xml" ".json" ".txt" ".md" ".yml"
  ".yaml" ".dcss" ".css" ".html" ".htm" ".sql" ".os" ".properties"
)

die() {
  printf '%s\n' "gitlab-mr-review: $*" >&2
  exit 2
}

show_help() {
  cat <<'USAGE'
Usage:
  gitlab-mr-review.sh help
  gitlab-mr-review.sh prepare -MrUrl <gitlab-merge-request-url>
  gitlab-mr-review.sh cleanup -WorktreePath <worktree-path>
  gitlab-mr-review.sh show-file -WorktreePath <worktree-path> -Ref <sha-or-ref> -RepoPath <repo-relative-path>
  gitlab-mr-review.sh grep-file -WorktreePath <worktree-path> -Ref <sha-or-ref> -RepoPath <repo-relative-path> -Pattern <regex> [-First <count>]
  gitlab-mr-review.sh list-files -WorktreePath <worktree-path> -Ref <sha-or-ref> -RepoPath <repo-relative-prefix>
  gitlab-mr-review.sh grep-tree -WorktreePath <worktree-path> -Ref <sha-or-ref> -Pattern <regex> [-RepoPath <repo-relative-prefix>] [-First <count>]

Implementation:
  gitlab-mr-review.sh is the Linux/WSL external entrypoint. On Windows use
  gitlab-mr-review.cmd instead. Both share the same manifest schema and the
  same read-only restrictions.

prepare:
  - parses the MR URL;
  - reads GitLab metadata through the GitLab API (glab auth only);
  - fetches target branch and MR head ref without switching the current branch;
  - creates or reuses a detached worktree under the review root
    (AI_REVIEW_ROOT, default ${HOME}/.cache/ai-review-wt);
  - writes manifest.json, mr.json, diff-stat.txt, diff-name-status.txt,
    diff.patch, changed-files.json and text snapshots for changed files;
  - prints manifest JSON to stdout.

cleanup:
  - removes only worktrees located under the review root;
  - runs git worktree prune.

read-only context:
  - show-file prints one file from a ref;
  - grep-file prints matching lines from one file as <line>:<text>;
  - list-files lists files under a repo-relative prefix at a ref;
  - grep-tree searches text through a ref and prints git-grep style matches;
  - grep-file and grep-tree support -First <count> instead of shell pipes;
  - all read-only commands require WorktreePath under the review root and
    reject rooted paths, parent traversal, shell metachar refs and ad-hoc
    shell pipelines.

Authentication:
  Uses only glab auth for GitLab API calls. Tokens from environment variables
  or a git credential manager are intentionally not used.
USAGE
}

# ---------------------------------------------------------------------------
# Pure helpers (no glab / python; safe to unit test in isolation)
# ---------------------------------------------------------------------------

get_full_path() {
  # Normalize without requiring the path to exist and drop any trailing slash.
  local resolved
  resolved="$(realpath -m -- "$1")"
  printf '%s' "$resolved"
}

to_safe_name() {
  local value="$1"
  local safe
  safe="$(printf '%s' "$value" | LC_ALL=C tr -c 'A-Za-z0-9._-' '-')"
  safe="${safe#"${safe%%[!-]*}"}"
  safe="${safe%"${safe##*[!-]}"}"
  if [[ -z "$safe" ]]; then
    safe="repo"
  fi
  printf '%s' "$safe"
}

test_is_inside_directory() {
  # Return 0 when Path ($1) is strictly inside Root ($2).
  local full_path full_root
  full_path="$(get_full_path "$1")"
  full_root="$(get_full_path "$2")"
  [[ "$full_path" == "$full_root"/* ]]
}

assert_safe_ref() {
  local value="$1"
  [[ -n "$value" ]] || die "Ref is required"
  if [[ ! "$value" =~ ^[A-Za-z0-9._/-]+$ ]] ||
    [[ "$value" == *".."* ]] ||
    [[ "$value" == *"@{"* ]] ||
    [[ "$value" == /* ]] ||
    [[ "$value" == */ ]] ||
    [[ "$value" == *"\\"* ]]; then
    die "Unsupported ref syntax: $value"
  fi
}

# Normalizes a repo-relative path and echoes it. Second arg "allow-empty"
# returns "." for an empty path instead of failing.
normalize_repo_path() {
  local path="$1"
  local allow_empty="${2:-}"
  if [[ -z "$path" ]]; then
    [[ "$allow_empty" == "allow-empty" ]] && { printf '.'; return 0; }
    die "RepoPath is required"
  fi
  if [[ "$path" == /* ]]; then
    die "RepoPath must be relative to the repository: $path"
  fi
  local normalized="${path//\\//}"
  # Trim leading and trailing slashes.
  while [[ "$normalized" == /* ]]; do normalized="${normalized#/}"; done
  while [[ "$normalized" == */ ]]; do normalized="${normalized%/}"; done
  if [[ -z "$normalized" ]]; then
    [[ "$allow_empty" == "allow-empty" ]] && { printf '.'; return 0; }
    die "RepoPath is required"
  fi
  if [[ "$normalized" == *":"* ]]; then
    die "RepoPath must not contain ':': $path"
  fi
  local IFS='/'
  local part
  for part in $normalized; do
    if [[ -z "$part" || "$part" == "." || "$part" == ".." ]]; then
      die "RepoPath must not contain empty, current, or parent segments: $path"
    fi
  done
  printf '%s' "$normalized"
}

assert_regex_pattern() {
  local value="$1"
  [[ -n "$value" ]] || die "Pattern is required"
  # grep exits 1 on "no match" (valid regex) and 2 on a bad regex.
  printf '' | grep -E -- "$value" >/dev/null 2>&1 || true
  if [[ "${PIPESTATUS[1]:-2}" -ge 2 ]]; then
    die "Pattern is not a valid extended regular expression: $value"
  fi
}

assert_first_count() {
  local value="$1"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    die "First must be a non-negative integer"
  fi
}

# Percent-decode a string (for the project path of an MR URL).
url_decode() {
  local s="${1//+/ }"
  printf '%b' "${s//%/\\x}"
}

# Parse an MR URL into PARSED_HOST / PARSED_PROJECT / PARSED_IID.
PARSED_HOST=""
PARSED_PROJECT=""
PARSED_IID=""
parse_mr_url() {
  local url="$1"
  local re='^https?://([^/]+)/(.+)/-/merge_requests/([0-9]+)([/?#].*)?$'
  if [[ ! "$url" =~ $re ]]; then
    die "Unsupported GitLab MR URL: $url"
  fi
  PARSED_HOST="${BASH_REMATCH[1]}"
  PARSED_PROJECT="$(url_decode "${BASH_REMATCH[2]}")"
  PARSED_PROJECT="${PARSED_PROJECT#/}"
  PARSED_PROJECT="${PARSED_PROJECT%/}"
  PARSED_IID="${BASH_REMATCH[3]}"
}

# Parse a git remote URL into REMOTE_HOST / REMOTE_PROJECT. Returns 1 when the
# URL is not a recognized http(s)/ssh/scp GitLab remote.
REMOTE_HOST=""
REMOTE_PROJECT=""
convert_remote_url() {
  local url="$1"
  REMOTE_HOST=""
  REMOTE_PROJECT=""
  local host="" path=""
  if [[ "$url" =~ ^https?://([^/]+)/(.+)$ ]]; then
    host="${BASH_REMATCH[1]}"
    path="${BASH_REMATCH[2]}"
  elif [[ "$url" =~ ^ssh://([^@/]+@)?([^/]+)/(.+)$ ]]; then
    host="${BASH_REMATCH[2]}"
    path="${BASH_REMATCH[3]}"
  elif [[ "$url" =~ ^([^@]+@)?([^:/]+):(.+)$ ]]; then
    host="${BASH_REMATCH[2]}"
    path="${BASH_REMATCH[3]}"
  else
    return 1
  fi
  [[ -n "$host" && -n "$path" ]] || return 1
  path="${path%/}"
  path="${path%.git}"
  path="${path#/}"
  path="${path%/}"
  REMOTE_HOST="$host"
  REMOTE_PROJECT="$path"
  return 0
}

sha256_hex() {
  local value="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$value" | sha256sum | cut -d' ' -f1
  else
    printf '%s' "$value" | shasum -a 256 | cut -d' ' -f1
  fi
}

join_snapshot_path() {
  # Args: root index repo_path -> "root/NNNN-<hash16>.txt"
  local root="$1" index="$2" repo_path="$3"
  local normalized hash
  normalized="$(normalize_repo_path "$repo_path")"
  hash="$(sha256_hex "$normalized")"
  hash="${hash:0:16}"
  printf '%s/%04d-%s.txt' "$root" "$index" "$hash"
}

is_text_review_path() {
  local repo_path="$1"
  [[ "$repo_path" == *.* ]] || return 1
  local lower ext
  lower="$(printf '%s' "$repo_path" | LC_ALL=C tr 'A-Z' 'a-z')"
  ext=".${lower##*.}"
  local candidate
  for candidate in "${TEXT_EXTENSIONS[@]}"; do
    [[ "$ext" == "$candidate" ]] && return 0
  done
  return 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Command is not available in PATH: $1"
}

# ---------------------------------------------------------------------------
# git / glab / python integration
# ---------------------------------------------------------------------------

project_root() {
  local root
  root="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)" ||
    die "gitlab-mr-review.sh must live inside the target git repository"
  printf '%s' "$root"
}

git_repo() {
  # Run git against the target repository root with portable options.
  git -C "$(project_root)" -c core.quotePath=false "$@"
}

git_wt() {
  # Run git against a worktree path (first argument) with portable options.
  local worktree="$1"
  shift
  git -C "$worktree" -c core.quotePath=false "$@"
}

run_py() {
  python3 - "$@" <<'PY'
import sys, os, json

mode = sys.argv[1]

def to_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return value

if mode == "urlencode":
    import urllib.parse
    sys.stdout.write(urllib.parse.quote(sys.argv[2], safe=""))

elif mode == "field":
    with open(sys.argv[2], encoding="utf-8") as handle:
        data = json.load(handle)
    cur = data
    for key in sys.argv[3].split("."):
        cur = cur.get(key) if isinstance(cur, dict) else None
        if cur is None:
            break
    if cur is None:
        sys.stdout.write("")
    elif isinstance(cur, bool):
        sys.stdout.write("true" if cur else "false")
    else:
        sys.stdout.write(str(cur))

elif mode == "manifest":
    with open(sys.argv[2], encoding="utf-8") as handle:
        mr = json.load(handle)
    env = os.environ

    def flag(name):
        return env.get(name) == "true"

    manifest = {
        "schema": "gitlab-mr-review.v1",
        "mr_url": mr.get("web_url"),
        "title": mr.get("title"),
        "description": mr.get("description"),
        "state": mr.get("state"),
        "source_branch": env["SOURCE_BRANCH"],
        "target_branch": env["TARGET_BRANCH"],
        "source_project_id": mr.get("source_project_id"),
        "target_project_id": to_int(env["TARGET_PROJECT_ID"]),
        "target_project_path": env["TARGET_PROJECT_PATH"],
        "base_sha": env["BASE_SHA"],
        "head_sha": env["HEAD_SHA"],
        "remote": env["REMOTE"],
        "mr_head_ref_fetched": flag("MR_HEAD_REF_FETCHED"),
        "worktree_path": env["WORKTREE_PATH"],
        "worktree_reused": flag("WORKTREE_REUSED"),
        "manifest_path": env["MANIFEST_PATH"],
        "mr_json_path": env["MR_JSON_PATH"],
        "diff_stat_path": env["DIFF_STAT_PATH"],
        "diff_name_status_path": env["DIFF_NAME_STATUS_PATH"],
        "diff_patch_path": env["DIFF_PATCH_PATH"],
        "changed_files_path": env["CHANGED_FILES_PATH"],
        "snapshot_root": env["SNAPSHOT_ROOT"],
        "base_snapshot_root": env["BASE_SNAPSHOT_ROOT"],
        "head_snapshot_root": env["HEAD_SNAPSHOT_ROOT"],
        "cleanup_command": env["CLEANUP_COMMAND"],
    }
    text = json.dumps(manifest, ensure_ascii=False, indent=2)
    with open(env["MANIFEST_PATH"], "w", encoding="utf-8") as handle:
        handle.write(text + "\n")
    sys.stdout.write(text + "\n")

elif mode == "changed":
    with open(sys.argv[2], "rb") as handle:
        tokens = handle.read().split(b"\0")
    if tokens and tokens[-1] == b"":
        tokens.pop()
    records = []
    for start in range(0, len(tokens), 6):
        chunk = tokens[start:start + 6]
        if len(chunk) < 6:
            break
        status, path, old_path, is_text, base_snap, head_snap = (
            token.decode("utf-8") for token in chunk
        )
        records.append({
            "status": status,
            "path": path,
            "old_path": old_path or None,
            "is_text_snapshot": is_text == "true",
            "base_snapshot_path": base_snap or None,
            "head_snapshot_path": head_snap or None,
        })
    text = json.dumps(records, ensure_ascii=False, indent=2)
    with open(sys.argv[3], "w", encoding="utf-8") as handle:
        handle.write(text + "\n")

elif mode == "cleanup":
    print(json.dumps({
        "schema": "gitlab-mr-review-cleanup.v1",
        "worktree_path": sys.argv[2],
        "removed": sys.argv[3] == "true",
    }, ensure_ascii=False, indent=2))

else:
    sys.stderr.write("unknown python helper mode: %s\n" % mode)
    sys.exit(2)
PY
}

glab_api_get() {
  # Args: hostname endpoint -> raw JSON on stdout.
  local hostname="$1" endpoint="$2"
  require_command glab
  if ! glab auth status --hostname "$hostname" >/dev/null 2>&1; then
    die "glab is not authenticated for $hostname. Run 'glab auth login --hostname $hostname' outside Claude Code."
  fi
  local output
  if ! output="$(glab api --hostname "$hostname" "$endpoint" 2>&1)"; then
    die "glab API request failed for $hostname/$endpoint. Check glab auth token scopes and project access. $output"
  fi
  if [[ -z "${output//[[:space:]]/}" ]]; then
    die "glab API returned an empty response for $hostname/$endpoint"
  fi
  printf '%s' "$output"
}

get_matching_remote() {
  # Args: hostname project_path. Echoes the remote name on success, else fails.
  local hostname="$1" project_path="$2"
  local name url
  while read -r name url _; do
    [[ -n "$name" && -n "$url" ]] || continue
    if convert_remote_url "$url"; then
      if [[ "${REMOTE_HOST,,}" == "${hostname,,}" &&
        "${REMOTE_PROJECT,,}" == "${project_path,,}" ]]; then
        printf '%s' "$name"
        return 0
      fi
    fi
  done < <(git_repo remote -v | grep '(fetch)$')
  return 1
}

resolve_review_worktree() {
  # Validate that a read-only worktree path is a managed review worktree.
  local path="$1"
  local resolved
  resolved="$(get_full_path "$path")"
  if ! test_is_inside_directory "$resolved" "$REVIEW_ROOT"; then
    die "Refusing to read a path that is not a child worktree under $REVIEW_ROOT: $resolved"
  fi
  if [[ ! -d "$resolved" ]]; then
    die "Review worktree does not exist: $resolved"
  fi
  local is_wt
  is_wt="$(git -C "$resolved" rev-parse --is-inside-work-tree 2>/dev/null)" ||
    die "Path is not a git worktree: $resolved"
  [[ "$is_wt" == "true" ]] || die "Path is not a git worktree: $resolved"
  printf '%s' "$resolved"
}

new_unique_worktree_path() {
  local base="$1"
  if [[ ! -e "$base" ]]; then
    printf '%s' "$base"
    return 0
  fi
  local index candidate
  for index in $(seq 1 99); do
    candidate="${base}-${index}"
    if [[ ! -e "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  die "Cannot find a free worktree path near: $base"
}

save_git_object_text() {
  # Args: worktree ref repo_path output_path
  local worktree="$1" ref="$2" repo_path="$3" output_path="$4"
  local normalized content parent
  normalized="$(normalize_repo_path "$repo_path")"
  content="$(git_wt "$worktree" show "${ref}:${normalized}")"
  parent="$(dirname -- "$output_path")"
  mkdir -p "$parent"
  printf '%s\n' "$content" >"$output_path"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_prepare() {
  local mr_url="$1"
  [[ -n "$mr_url" ]] || die "prepare requires -MrUrl"
  require_command git
  require_command glab
  require_command python3

  parse_mr_url "$mr_url"
  local host="$PARSED_HOST" project="$PARSED_PROJECT" iid="$PARSED_IID"

  local encoded_project mr_endpoint mr_file
  encoded_project="$(run_py urlencode "$project")"
  mr_endpoint="projects/${encoded_project}/merge_requests/${iid}"

  PREPARE_TMP_DIR="$(mktemp -d)"
  local tmp_dir="$PREPARE_TMP_DIR"
  mr_file="${tmp_dir}/mr.json"
  glab_api_get "$host" "$mr_endpoint" >"$mr_file"

  local target_project_id
  target_project_id="$(run_py field "$mr_file" target_project_id)"
  if [[ -z "$target_project_id" ]]; then
    target_project_id="$(run_py field "$mr_file" project_id)"
  fi
  [[ -n "$target_project_id" ]] || die "MR metadata does not contain target project id"

  local target_project_file target_project_path
  target_project_file="${tmp_dir}/target-project.json"
  glab_api_get "$host" "projects/${target_project_id}" >"$target_project_file"
  target_project_path="$(run_py field "$target_project_file" path_with_namespace)"
  [[ -n "$target_project_path" ]] || die "Target project metadata does not contain path_with_namespace"

  local remote
  remote="$(get_matching_remote "$host" "$target_project_path")" ||
    die "Current repository remote does not match GitLab target project ${host}/${target_project_path}"

  local base_sha head_sha
  base_sha="$(run_py field "$mr_file" diff_refs.base_sha)"
  head_sha="$(run_py field "$mr_file" diff_refs.head_sha)"
  if [[ -z "$base_sha" || -z "$head_sha" ]]; then
    die "MR diff_refs are not ready yet. Repeat later after GitLab prepares the MR diff."
  fi

  local target_branch source_branch source_project_id
  target_branch="$(run_py field "$mr_file" target_branch)"
  source_branch="$(run_py field "$mr_file" source_branch)"
  source_project_id="$(run_py field "$mr_file" source_project_id)"
  if [[ -z "$target_branch" || -z "$source_branch" ]]; then
    die "MR metadata does not contain source_branch or target_branch"
  fi

  git_repo fetch "$remote" "$target_branch" >/dev/null

  local mr_head_ref mr_head_fetched="true"
  mr_head_ref="refs/merge-requests/${iid}/head:refs/remotes/${remote}/mr/${iid}/head"
  if ! git_repo fetch "$remote" "$mr_head_ref" >/dev/null 2>&1; then
    mr_head_fetched="false"
    if [[ "$source_project_id" != "$target_project_id" ]]; then
      die "Cannot fetch MR head ref and MR source project differs from target project. Add a source remote or make the MR head ref available."
    fi
    git_repo fetch "$remote" "$source_branch" >/dev/null
  fi

  git_repo cat-file -e "${base_sha}^{commit}" ||
    die "base_sha is not available locally after fetch"
  git_repo cat-file -e "${head_sha}^{commit}" ||
    die "head_sha is not available locally after fetch"

  mkdir -p "$REVIEW_ROOT"

  local repo_name short_sha base_worktree resolved_worktree reused="false"
  repo_name="$(to_safe_name "${target_project_path##*/}")"
  short_sha="${head_sha:0:8}"
  base_worktree="${REVIEW_ROOT}/${repo_name}-review-mr-${iid}-${short_sha}"
  resolved_worktree="$(get_full_path "$base_worktree")"

  if [[ -d "$resolved_worktree" ]]; then
    local existing_head
    existing_head="$(git -C "$resolved_worktree" rev-parse HEAD 2>/dev/null || true)"
    if [[ "$existing_head" == "$head_sha" ]]; then
      reused="true"
    else
      resolved_worktree="$(new_unique_worktree_path "$resolved_worktree")"
    fi
  fi

  if [[ "$reused" != "true" ]]; then
    git_repo worktree add --detach "$resolved_worktree" "$head_sha" >/dev/null
  fi

  local manifest_root manifest_dir
  manifest_root="${REVIEW_ROOT}/_manifests"
  manifest_dir="${manifest_root}/${repo_name}-mr-${iid}-${short_sha}"
  mkdir -p "$manifest_dir"

  local mr_json_path stat_path name_status_path diff_path changed_files_path
  local snapshot_root manifest_path
  mr_json_path="${manifest_dir}/mr.json"
  stat_path="${manifest_dir}/diff-stat.txt"
  name_status_path="${manifest_dir}/diff-name-status.txt"
  diff_path="${manifest_dir}/diff.patch"
  changed_files_path="${manifest_dir}/changed-files.json"
  snapshot_root="${manifest_dir}/files"
  manifest_path="${manifest_dir}/manifest.json"

  [[ -d "$snapshot_root" ]] && rm -rf "$snapshot_root"

  cp -f "$mr_file" "$mr_json_path"
  git_wt "$resolved_worktree" diff "${base_sha}...${head_sha}" --stat >"$stat_path"
  git_wt "$resolved_worktree" diff "${base_sha}...${head_sha}" --name-status --find-renames >"$name_status_path"
  git_wt "$resolved_worktree" diff "${base_sha}...${head_sha}" --find-renames >"$diff_path"

  local base_root head_root records_file
  base_root="${snapshot_root}/base"
  head_root="${snapshot_root}/head"
  mkdir -p "$base_root" "$head_root"
  records_file="${tmp_dir}/records.nul"
  : >"$records_file"

  local index=0
  local c1 c2 c3 status path old_path base_repo_path is_text base_snap head_snap
  while IFS=$'\t' read -r c1 c2 c3; do
    [[ -n "$c1" ]] || continue
    status="$c1"
    if [[ "$status" == R* || "$status" == C* ]]; then
      [[ -n "$c3" ]] || continue
      old_path="$(normalize_repo_path "$c2")"
      path="$(normalize_repo_path "$c3")"
    else
      old_path=""
      path="$(normalize_repo_path "$c2")"
    fi

    index=$((index + 1))
    base_repo_path="${old_path:-$path}"
    is_text="false"
    if is_text_review_path "$path"; then
      is_text="true"
    elif [[ -n "$old_path" ]] && is_text_review_path "$old_path"; then
      is_text="true"
    fi

    base_snap=""
    head_snap=""
    if [[ "$is_text" == "true" && "$status" != A* ]]; then
      base_snap="$(join_snapshot_path "$base_root" "$index" "$base_repo_path")"
      save_git_object_text "$resolved_worktree" "$base_sha" "$base_repo_path" "$base_snap"
    fi
    if [[ "$is_text" == "true" && "$status" != D* ]]; then
      head_snap="$(join_snapshot_path "$head_root" "$index" "$path")"
      save_git_object_text "$resolved_worktree" "$head_sha" "$path" "$head_snap"
    fi

    printf '%s\0%s\0%s\0%s\0%s\0%s\0' \
      "$status" "$path" "$old_path" "$is_text" "$base_snap" "$head_snap" \
      >>"$records_file"
  done < <(git_wt "$resolved_worktree" diff "${base_sha}...${head_sha}" --name-status --find-renames)

  run_py changed "$records_file" "$changed_files_path"

  local cleanup_command
  cleanup_command=".claude/scripts/gitlab-mr-review.sh cleanup -WorktreePath \"${resolved_worktree}\""

  SOURCE_BRANCH="$source_branch" \
  TARGET_BRANCH="$target_branch" \
  TARGET_PROJECT_ID="$target_project_id" \
  TARGET_PROJECT_PATH="$target_project_path" \
  BASE_SHA="$base_sha" \
  HEAD_SHA="$head_sha" \
  REMOTE="$remote" \
  MR_HEAD_REF_FETCHED="$mr_head_fetched" \
  WORKTREE_PATH="$resolved_worktree" \
  WORKTREE_REUSED="$reused" \
  MANIFEST_PATH="$manifest_path" \
  MR_JSON_PATH="$mr_json_path" \
  DIFF_STAT_PATH="$stat_path" \
  DIFF_NAME_STATUS_PATH="$name_status_path" \
  DIFF_PATCH_PATH="$diff_path" \
  CHANGED_FILES_PATH="$changed_files_path" \
  SNAPSHOT_ROOT="$snapshot_root" \
  BASE_SNAPSHOT_ROOT="$base_root" \
  HEAD_SNAPSHOT_ROOT="$head_root" \
  CLEANUP_COMMAND="$cleanup_command" \
    run_py manifest "$mr_json_path"
}

cmd_cleanup() {
  local worktree_path="$1"
  [[ -n "$worktree_path" ]] || die "cleanup requires -WorktreePath"
  require_command git
  require_command python3

  local resolved removed="false"
  resolved="$(get_full_path "$worktree_path")"
  if ! test_is_inside_directory "$resolved" "$REVIEW_ROOT"; then
    die "Refusing to remove a path that is not a child worktree under $REVIEW_ROOT: $resolved"
  fi

  if [[ -d "$resolved" ]]; then
    git_repo worktree remove --force "$resolved" >/dev/null
    removed="true"
  fi
  git_repo worktree prune >/dev/null

  run_py cleanup "$resolved" "$removed"
}

cmd_show_file() {
  local worktree_path="$1" ref="$2" repo_path="$3"
  [[ -n "$worktree_path" ]] || die "show-file requires -WorktreePath"
  assert_safe_ref "$ref"
  local resolved normalized
  resolved="$(resolve_review_worktree "$worktree_path")"
  normalized="$(normalize_repo_path "$repo_path")"
  git_wt "$resolved" show "${ref}:${normalized}"
}

cmd_grep_file() {
  local worktree_path="$1" ref="$2" repo_path="$3" pattern="$4" first="$5"
  [[ -n "$worktree_path" ]] || die "grep-file requires -WorktreePath"
  assert_safe_ref "$ref"
  assert_regex_pattern "$pattern"
  assert_first_count "$first"
  local resolved normalized
  resolved="$(resolve_review_worktree "$worktree_path")"
  normalized="$(normalize_repo_path "$repo_path")"
  local matches
  matches="$(git_wt "$resolved" show "${ref}:${normalized}" | grep -nE -- "$pattern" || true)"
  [[ -n "$matches" ]] || return 0
  if [[ "$first" -gt 0 ]]; then
    printf '%s\n' "$matches" | head -n "$first"
  else
    printf '%s\n' "$matches"
  fi
}

cmd_list_files() {
  local worktree_path="$1" ref="$2" repo_path="$3"
  [[ -n "$worktree_path" ]] || die "list-files requires -WorktreePath"
  assert_safe_ref "$ref"
  local resolved normalized
  resolved="$(resolve_review_worktree "$worktree_path")"
  normalized="$(normalize_repo_path "$repo_path" allow-empty)"
  if [[ "$normalized" == "." ]]; then
    git_wt "$resolved" ls-tree -r --name-only "$ref"
  else
    git_wt "$resolved" ls-tree -r --name-only "$ref" -- "$normalized"
  fi
}

cmd_grep_tree() {
  local worktree_path="$1" ref="$2" pattern="$3" repo_path="$4" first="$5"
  [[ -n "$worktree_path" ]] || die "grep-tree requires -WorktreePath"
  assert_safe_ref "$ref"
  assert_regex_pattern "$pattern"
  assert_first_count "$first"
  local resolved
  resolved="$(resolve_review_worktree "$worktree_path")"

  local -a args=(grep -n -E --no-color -e "$pattern" "$ref")
  if [[ -n "$repo_path" ]]; then
    local normalized
    normalized="$(normalize_repo_path "$repo_path" allow-empty)"
    if [[ "$normalized" != "." ]]; then
      args+=(-- "$normalized")
    fi
  fi

  local output status
  output="$(git_wt "$resolved" "${args[@]}")" && status=0 || status=$?
  if [[ "$status" -eq 1 ]]; then
    return 0
  fi
  if [[ "$status" -ne 0 ]]; then
    die "git grep failed: ${output:-exit code $status}"
  fi
  [[ -n "$output" ]] || return 0
  if [[ "$first" -gt 0 ]]; then
    printf '%s\n' "$output" | head -n "$first"
  else
    printf '%s\n' "$output"
  fi
}

# ---------------------------------------------------------------------------
# Argument parsing / dispatch
# ---------------------------------------------------------------------------

main() {
  local command="${1:-}"
  [[ -n "$command" ]] || { show_help >&2; exit 2; }
  shift || true

  local mr_url="" worktree_path="" ref="" repo_path="" pattern="" first="0"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -MrUrl) [[ $# -ge 2 ]] || die "-MrUrl requires a value"; mr_url="$2"; shift 2 ;;
      -WorktreePath) [[ $# -ge 2 ]] || die "-WorktreePath requires a value"; worktree_path="$2"; shift 2 ;;
      -Ref) [[ $# -ge 2 ]] || die "-Ref requires a value"; ref="$2"; shift 2 ;;
      -RepoPath) [[ $# -ge 2 ]] || die "-RepoPath requires a value"; repo_path="$2"; shift 2 ;;
      -Pattern) [[ $# -ge 2 ]] || die "-Pattern requires a value"; pattern="$2"; shift 2 ;;
      -First) [[ $# -ge 2 ]] || die "-First requires a value"; first="$2"; shift 2 ;;
      *) die "Unsupported argument: $1" ;;
    esac
  done

  case "$command" in
    help | -h | --help) show_help ;;
    prepare) cmd_prepare "$mr_url" ;;
    cleanup) cmd_cleanup "$worktree_path" ;;
    show-file) cmd_show_file "$worktree_path" "$ref" "$repo_path" ;;
    grep-file) cmd_grep_file "$worktree_path" "$ref" "$repo_path" "$pattern" "$first" ;;
    list-files) cmd_list_files "$worktree_path" "$ref" "$repo_path" ;;
    grep-tree) cmd_grep_tree "$worktree_path" "$ref" "$pattern" "$repo_path" "$first" ;;
    *) show_help >&2; die "Unknown command: $command" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
