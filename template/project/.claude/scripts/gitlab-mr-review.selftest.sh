#!/usr/bin/env bash
# gitlab-mr-review.selftest.sh
#
# Deterministic self-test harness for gitlab-mr-review.sh. It exercises the
# entrypoint WITHOUT a live GitLab MR:
#
#   - unit tests for the pure validation/parsing helpers (URL parsing, ref and
#     repo-path validation, safe names, remote URL parsing, review-root
#     containment, snapshot path hashing);
#   - an end-to-end prepare/cleanup run against a scratch git repository and a
#     stub `glab` on PATH, asserting the manifest schema, materialized diff and
#     snapshot files, and the safe cleanup guard.
#
# The end-to-end part runs only when git and python3 are available; otherwise
# it is skipped with a clear message. No network access, no real glab auth and
# no real GitLab project are required.
#
# Usage:
#   bash .claude/scripts/gitlab-mr-review.selftest.sh

set -uo pipefail

SELFTEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT="${SELFTEST_DIR}/gitlab-mr-review.sh"

PASS=0
FAIL=0

pass() {
  PASS=$((PASS + 1))
  printf 'ok   - %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL - %s\n' "$1" >&2
}

# Assert that a function call echoes the expected value.
expect_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$desc"
  else
    fail "$desc (expected [$expected], got [$actual])"
  fi
}

# Assert that running a snippet exits non-zero (i.e. die was reached).
expect_fail() {
  local desc="$1"
  shift
  if ( "$@" ) >/dev/null 2>&1; then
    fail "$desc (expected failure, but it succeeded)"
  else
    pass "$desc"
  fi
}

# Assert that running a snippet exits zero.
expect_ok() {
  local desc="$1"
  shift
  if ( "$@" ) >/dev/null 2>&1; then
    pass "$desc"
  else
    fail "$desc (expected success, but it failed)"
  fi
}

# ---------------------------------------------------------------------------
# Source the entrypoint so its functions are available without running main.
# The trailing `if [[ BASH_SOURCE == 0 ]]` guard keeps main from executing.
# ---------------------------------------------------------------------------
# Point the review root at a scratch dir so containment tests are deterministic.
export HOME="$(mktemp -d)"
export AI_REVIEW_ROOT="${HOME}/review-root"
# shellcheck source=/dev/null
source "$TARGET_SCRIPT"

# ---------------------------------------------------------------------------
# Unit tests: pure helpers
# ---------------------------------------------------------------------------

# parse_mr_url
parse_mr_url "https://gitlab.example.com/group/sub/project/-/merge_requests/123"
expect_eq "parse_mr_url host" "gitlab.example.com" "$PARSED_HOST"
expect_eq "parse_mr_url nested project" "group/sub/project" "$PARSED_PROJECT"
expect_eq "parse_mr_url iid" "123" "$PARSED_IID"

parse_mr_url "https://gl.example.com/a/b/-/merge_requests/7/diffs"
expect_eq "parse_mr_url trailing /diffs iid" "7" "$PARSED_IID"
expect_eq "parse_mr_url trailing /diffs project" "a/b" "$PARSED_PROJECT"

parse_mr_url "https://gl.example.com/gr%2Fenc/proj/-/merge_requests/9?tab=x"
expect_eq "parse_mr_url percent-decoded project" "gr/enc/proj" "$PARSED_PROJECT"

expect_fail "parse_mr_url rejects non-MR url" \
  parse_mr_url "https://gitlab.example.com/group/project/-/issues/1"
expect_fail "parse_mr_url rejects ftp scheme" \
  parse_mr_url "ftp://gitlab.example.com/a/b/-/merge_requests/1"

# assert_safe_ref
expect_ok   "assert_safe_ref accepts sha"        assert_safe_ref "abcdef1234567890"
expect_ok   "assert_safe_ref accepts branch ref" assert_safe_ref "feature/my-branch"
expect_fail "assert_safe_ref rejects .."         assert_safe_ref "a..b"
expect_fail "assert_safe_ref rejects @{"         assert_safe_ref "HEAD@{1}"
expect_fail "assert_safe_ref rejects leading /"  assert_safe_ref "/abc"
expect_fail "assert_safe_ref rejects trailing /" assert_safe_ref "abc/"
expect_fail "assert_safe_ref rejects backslash"  assert_safe_ref 'a\b'
expect_fail "assert_safe_ref rejects semicolon"  assert_safe_ref 'a;rm'
expect_fail "assert_safe_ref rejects empty"      assert_safe_ref ""

# normalize_repo_path
expect_eq   "normalize_repo_path collapses backslashes" \
  "src/cf/Module.bsl" "$(normalize_repo_path 'src\cf\Module.bsl')"
expect_eq   "normalize_repo_path trims trailing slash" \
  "a/b" "$(normalize_repo_path 'a/b/')"
expect_eq   "normalize_repo_path allow-empty -> ." \
  "." "$(normalize_repo_path '' allow-empty)"
expect_fail "normalize_repo_path rejects rooted" normalize_repo_path "/etc/passwd"
expect_fail "normalize_repo_path rejects parent" normalize_repo_path "a/../b"
expect_fail "normalize_repo_path rejects colon"  normalize_repo_path "C:/x"
expect_fail "normalize_repo_path rejects empty"  normalize_repo_path ""

# to_safe_name
expect_eq "to_safe_name sanitizes"      "my-proj_1.x" "$(to_safe_name 'my-proj_1.x')"
expect_eq "to_safe_name replaces spaces" "a-b" "$(to_safe_name 'a b')"
expect_eq "to_safe_name trims dashes"   "abc" "$(to_safe_name '--abc--')"
expect_eq "to_safe_name empty -> repo"  "repo" "$(to_safe_name '///')"

# convert_remote_url
convert_remote_url "https://gitlab.example.com/group/project.git"
expect_eq "convert_remote_url https host"    "gitlab.example.com" "$REMOTE_HOST"
expect_eq "convert_remote_url https project" "group/project"      "$REMOTE_PROJECT"
convert_remote_url "git@gitlab.example.com:group/project.git"
expect_eq "convert_remote_url scp host"      "gitlab.example.com" "$REMOTE_HOST"
expect_eq "convert_remote_url scp project"   "group/project"      "$REMOTE_PROJECT"
convert_remote_url "ssh://git@gitlab.example.com/group/sub/project.git"
expect_eq "convert_remote_url ssh host"      "gitlab.example.com" "$REMOTE_HOST"
expect_eq "convert_remote_url ssh project"   "group/sub/project"  "$REMOTE_PROJECT"
expect_fail "convert_remote_url rejects junk" convert_remote_url "not-a-url"

# test_is_inside_directory (review-root containment)
mkdir -p "$AI_REVIEW_ROOT/child"
expect_ok   "containment accepts child" \
  test_is_inside_directory "$AI_REVIEW_ROOT/child" "$AI_REVIEW_ROOT"
expect_fail "containment rejects sibling" \
  test_is_inside_directory "$HOME/other" "$AI_REVIEW_ROOT"
expect_fail "containment rejects traversal" \
  test_is_inside_directory "$AI_REVIEW_ROOT/../escape" "$AI_REVIEW_ROOT"
expect_fail "containment rejects the root itself" \
  test_is_inside_directory "$AI_REVIEW_ROOT" "$AI_REVIEW_ROOT"

# is_text_review_path
expect_ok   "is_text_review_path accepts .bsl" is_text_review_path "src/Module.bsl"
expect_ok   "is_text_review_path accepts .MDO uppercase" is_text_review_path "src/A.MDO"
expect_fail "is_text_review_path rejects .bin" is_text_review_path "src/data.bin"
expect_fail "is_text_review_path rejects no ext" is_text_review_path "Makefile"

# join_snapshot_path is deterministic and well-formed
snap_a="$(join_snapshot_path "/root/base" 1 "src/cf/Module.bsl")"
snap_b="$(join_snapshot_path "/root/base" 1 "src/cf/Module.bsl")"
expect_eq "join_snapshot_path deterministic" "$snap_a" "$snap_b"
if [[ "$snap_a" =~ ^/root/base/0001-[0-9a-f]{16}\.txt$ ]]; then
  pass "join_snapshot_path shape 0001-<hash16>.txt"
else
  fail "join_snapshot_path shape (got $snap_a)"
fi

# ---------------------------------------------------------------------------
# End-to-end: prepare + cleanup against a scratch repo and a stub glab
# ---------------------------------------------------------------------------

e2e() {
  if ! command -v git >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    printf 'SKIP - end-to-end prepare/cleanup (need git and python3)\n'
    return 0
  fi

  local work base_sha head_sha
  work="$(mktemp -d)"

  # A working repo whose origin matches the target project path returned by the
  # stub glab.
  git init -q "$work/repo"
  git -C "$work/repo" config user.email t@example.com
  git -C "$work/repo" config user.name Tester
  git -C "$work/repo" remote add origin "https://gitlab.example.com/group/project.git"
  git -C "$work/repo" checkout -q -b main

  printf 'line1\nline2\n' >"$work/repo/file.bsl"
  printf 'binary\n' >"$work/repo/image.bin"
  git -C "$work/repo" add file.bsl image.bin
  git -C "$work/repo" commit -q -m base

  printf 'line1\nline2 changed\nline3\n' >"$work/repo/file.bsl"
  printf 'Процедура Тест()\nКонецПроцедуры\n' >"$work/repo/добавлен.bsl"
  git -C "$work/repo" add file.bsl добавлен.bsl
  git -C "$work/repo" commit -q -m head

  base_sha="$(git -C "$work/repo" rev-parse HEAD~1)"
  head_sha="$(git -C "$work/repo" rev-parse HEAD)"

  # Both commits already exist locally, so the review worktree, diff and
  # snapshots are fully materializable offline. The origin keeps a real,
  # matchable https URL so remote-project matching is genuinely exercised; the
  # only network boundary (git fetch) is neutralized by a thin git wrapper
  # below rather than by rewriting the remote URL (which would defeat matching).
  local real_git
  real_git="$(command -v git)"

  local stub_dir="$work/bin"
  mkdir -p "$stub_dir"

  # git wrapper: pass everything through to the real git except `fetch`, which
  # becomes a no-op success (the fetched objects are already present locally).
  cat >"$stub_dir/git" <<STUB
#!/usr/bin/env bash
sub=""
idx=1
for tok in "\$@"; do
  case "\$tok" in
    -C|-c) skip_next=1 ;;
    *)
      if [[ "\${skip_next:-0}" == "1" ]]; then skip_next=0; continue; fi
      case "\$tok" in -*) ;; *) sub="\$tok"; break ;; esac
      ;;
  esac
done
if [[ "\$sub" == "fetch" ]]; then exit 0; fi
exec "$real_git" "\$@"
STUB
  chmod +x "$stub_dir/git"

  # Stub glab: answers `auth status` and `api <endpoint>` from fixtures.
  cat >"$stub_dir/glab" <<STUB
#!/usr/bin/env bash
set -euo pipefail
cmd="\${1:-}"
if [[ "\$cmd" == "auth" ]]; then
  exit 0
fi
if [[ "\$cmd" == "api" ]]; then
  endpoint="\${!#}"
  case "\$endpoint" in
    projects/*/merge_requests/*)
      cat <<JSON
{
  "iid": 42,
  "title": "Тестовый MR",
  "description": "Описание",
  "state": "opened",
  "web_url": "https://gitlab.example.com/group/project/-/merge_requests/42",
  "project_id": 100,
  "target_project_id": 100,
  "source_project_id": 100,
  "target_branch": "main",
  "source_branch": "feature",
  "diff_refs": { "base_sha": "${base_sha}", "head_sha": "${head_sha}" }
}
JSON
      ;;
    projects/100)
      cat <<JSON
{ "id": 100, "path_with_namespace": "group/project" }
JSON
      ;;
    *)
      echo "unexpected endpoint: \$endpoint" >&2
      exit 1
      ;;
  esac
  exit 0
fi
echo "unexpected glab call: \$*" >&2
exit 1
STUB
  chmod +x "$stub_dir/glab"

  # Run prepare with the stub glab first on PATH, and the script resolving the
  # target repo from its own location by copying it next to the repo's .git.
  mkdir -p "$work/repo/.claude/scripts"
  cp "$TARGET_SCRIPT" "$work/repo/.claude/scripts/gitlab-mr-review.sh"

  local manifest
  if ! manifest="$(PATH="$stub_dir:$PATH" AI_REVIEW_ROOT="$work/review-root" \
      bash "$work/repo/.claude/scripts/gitlab-mr-review.sh" prepare \
      -MrUrl "https://gitlab.example.com/group/project/-/merge_requests/42" 2>"$work/prepare.err")"; then
    fail "e2e prepare exited non-zero"
    sed 's/^/       prepare-stderr: /' "$work/prepare.err" >&2
    return 0
  fi
  pass "e2e prepare exits zero and prints a manifest"

  # Validate the manifest with python (schema + key invariants). The manifest
  # is passed as a file argument because the here-doc already occupies stdin.
  printf '%s' "$manifest" >"$work/manifest.out.json"
  local wt
  wt="$(python3 - "$work/manifest.out.json" <<'PY'
import sys, json, os
m = json.load(open(sys.argv[1], encoding="utf-8"))
assert m["schema"] == "gitlab-mr-review.v1", m.get("schema")
assert m["title"] == "Тестовый MR", m["title"]
assert m["target_project_path"] == "group/project", m["target_project_path"]
assert m["target_project_id"] == 100, m["target_project_id"]
assert m["remote"] == "origin", m["remote"]
assert m["source_branch"] == "feature"
assert m["target_branch"] == "main"
assert len(m["base_sha"]) == 40 and len(m["head_sha"]) == 40
assert os.path.isfile(m["manifest_path"]), m["manifest_path"]
assert os.path.isfile(m["diff_patch_path"]), m["diff_patch_path"]
assert os.path.isfile(m["diff_name_status_path"])
assert os.path.isfile(m["changed_files_path"])
# changed-files: file.bsl modified (text snapshots), добавлен.bsl added,
# image.bin present but not snapshotted.
cf = json.load(open(m["changed_files_path"], encoding="utf-8"))
by = {r["path"]: r for r in cf}
assert "file.bsl" in by, list(by)
assert by["file.bsl"]["is_text_snapshot"] is True
assert by["file.bsl"]["base_snapshot_path"] and os.path.isfile(by["file.bsl"]["base_snapshot_path"])
assert by["file.bsl"]["head_snapshot_path"] and os.path.isfile(by["file.bsl"]["head_snapshot_path"])
assert "добавлен.bsl" in by, list(by)
assert by["добавлен.bsl"]["status"].startswith("A")
assert by["добавлен.bsl"]["base_snapshot_path"] is None
sys.stdout.write(m["worktree_path"])
PY
  )" || { fail "e2e manifest schema/invariants"; return 0; }
  pass "e2e manifest schema and materialized files are valid"

  # Worktree exists, is detached at head_sha, and the user branch is untouched.
  if [[ -d "$wt" ]] && git -C "$wt" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    pass "e2e review worktree exists and is a git worktree"
  else
    fail "e2e review worktree missing"
  fi
  local user_branch
  user_branch="$(git -C "$work/repo" rev-parse --abbrev-ref HEAD)"
  expect_eq "e2e user branch unchanged" "main" "$user_branch"

  # cleanup refuses a path outside the review root...
  if PATH="$stub_dir:$PATH" AI_REVIEW_ROOT="$work/review-root" \
      bash "$work/repo/.claude/scripts/gitlab-mr-review.sh" cleanup \
      -WorktreePath "$work/repo" >/dev/null 2>&1; then
    fail "e2e cleanup should refuse a path outside the review root"
  else
    pass "e2e cleanup refuses a path outside the review root"
  fi

  # ...and removes a managed worktree.
  if PATH="$stub_dir:$PATH" AI_REVIEW_ROOT="$work/review-root" \
      bash "$work/repo/.claude/scripts/gitlab-mr-review.sh" cleanup \
      -WorktreePath "$wt" >/dev/null 2>&1 && [[ ! -d "$wt" ]]; then
    pass "e2e cleanup removes the managed worktree"
  else
    fail "e2e cleanup did not remove the managed worktree"
  fi
}

e2e

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
