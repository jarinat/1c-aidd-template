#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  bash .claude/scripts/commit-block.sh "<subject>" \
    --add-path <path> [--add-path <path>] \
    --body-line "<line>" [--body-line "<line>"] \
    [--allow-existing-staged]

This template does not define universal default staged paths.
Pass every path that belongs to the current change block through --add-path,
or adapt this project script to define safe project-specific defaults.
USAGE
}

die() {
  echo "commit-block: $*" >&2
  exit 1
}

subject=""
body_lines=()
paths=()
allow_existing_staged=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --body-line)
      [[ $# -ge 2 ]] || die "--body-line requires a value"
      body_lines+=("$2")
      shift 2
      ;;
    --add-path)
      [[ $# -ge 2 ]] || die "--add-path requires a value"
      paths+=("$2")
      shift 2
      ;;
    --allow-existing-staged)
      allow_existing_staged=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      die "unknown option: $1"
      ;;
    *)
      if [[ -n "$subject" ]]; then
        die "subject is already set; unexpected argument: $1"
      fi
      subject="$1"
      shift
      ;;
  esac
done

[[ -n "$subject" ]] || die "commit subject is required"
[[ ${#body_lines[@]} -gt 0 ]] || die "at least one --body-line is required"
[[ ${#paths[@]} -gt 0 ]] || die "at least one --add-path is required by the template script"

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
cd "$repo_root"

if [[ "$allow_existing_staged" -ne 1 ]] && ! git diff --cached --quiet --; then
  die "staged changes already exist; review/commit or unstage them before running this script"
fi

git add -- "${paths[@]}"

if git diff --cached --quiet --; then
  die "no staged changes after adding paths: ${paths[*]}"
fi

body=""
for line in "${body_lines[@]}"; do
  body+="${line}"$'\n'
done

git commit -m "$subject" -m "$body"
