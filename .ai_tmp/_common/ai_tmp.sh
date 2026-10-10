#!/usr/bin/env sh
# ai_tmp.sh -- helper for the throwaway AI working area under .ai_tmp/.
#
# Why: every AI conversation gets its own self-contained directory, and stale
# ones are swept into an archive instead of being deleted by hand. The raw
# paste-log for a session lands in a single fixed inbox file, so you never have
# to invent a path mid-conversation: paste, run `ingest <topic>`, done.
#
# Layout (everything under .ai_tmp/ is gitignored except _common/; see the root
# .gitignore):
#   .ai_tmp/_common/.log.txt   shared inbox: paste a session's notes/log here
#   .ai_tmp/_common/ai_tmp.sh  this script (the only tracked part of .ai_tmp)
#   .ai_tmp/<topic>/           one directory per conversation
#   .ai_tmp/_archive/          expired conversations moved here
#
# This header is the documentation on purpose -- there is no separate doc file.
#
# Usage:
#   sh .ai_tmp/_common/ai_tmp.sh ingest <topic>
#       Move the current _common/.log.txt into .ai_tmp/<topic>/<topic>.log.txt,
#       then recreate an empty _common/.log.txt for the next session.
#       <topic> is a lowercase slug matching [a-z0-9_-]+ and must not exist yet.
#
#   sh .ai_tmp/_common/ai_tmp.sh archive [--days N] [--dry-run]
#       Move every session directory whose newest file has not changed within
#       the last N days (default 5) into .ai_tmp/_archive/. Empty directories
#       count as expired. --dry-run only prints what would move.
#
#   sh .ai_tmp/_common/ai_tmp.sh help
#
# Runs from any directory (resolves the repo root like scripts/*.sh).

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
base="$root/.ai_tmp"
common="$base/_common"
inbox="$common/.log.txt"
archive="$base/_archive"
default_days=5

usage() {
  cat <<'EOF'
Usage:
  ai_tmp.sh ingest <topic>
  ai_tmp.sh archive [--days N] [--dry-run]
  ai_tmp.sh help

Layout (everything under .ai_tmp/ is gitignored except _common/):
  .ai_tmp/_common/.log.txt   shared inbox: paste notes here, then ingest
  .ai_tmp/<topic>/           one directory per conversation (<topic>.log.txt)
  .ai_tmp/_archive/          expired conversations
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

cmd_ingest() {
  topic=${1:-}
  [ -n "$topic" ] || { usage >&2; die "missing <topic>"; }

  case $topic in
    *[!a-z0-9_-]*) die "<topic> must match [a-z0-9_-]+ (got: $topic)" ;;
  esac

  [ -f "$inbox" ] || die "missing inbox: $inbox"
  [ -s "$inbox" ] || die "inbox is empty, nothing to ingest: $inbox"

  dest="$base/$topic"
  [ ! -e "$dest" ] || die "session already exists: $dest"

  mkdir -p "$dest"
  mv "$inbox" "$dest/$topic.log.txt"
  : > "$inbox"

  echo "ingested -> ${dest#"$root"/}/$topic.log.txt"
  echo "inbox reset: ${inbox#"$root"/}"
}

cmd_archive() {
  days=$default_days
  dry=0

  while [ $# -gt 0 ]; do
    case $1 in
      --days)
        [ $# -ge 2 ] || die "--days needs a value"
        days=$2
        shift 2
        ;;
      --dry-run)
        dry=1
        shift
        ;;
      *)
        usage >&2
        die "unknown option: $1"
        ;;
    esac
  done

  case $days in
    ''|*[!0-9]*) die "--days must be a positive integer (got: $days)" ;;
  esac
  [ "$days" -ge 1 ] || die "--days must be >= 1 (got: $days)"

  if [ ! -d "$base" ]; then
    echo "nothing to archive: $base does not exist"
    return 0
  fi

  moved=0
  for dir in "$base"/*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    case $name in
      _common|_archive) continue ;;
    esac

    # Expired when no file inside changed within the last $days days. An empty
    # session directory yields no matches and is therefore expired too.
    if [ -n "$(find "$dir" -type f -mtime -"$days" -print -quit 2>/dev/null)" ]; then
      continue
    fi

    dest="$archive/$name"
    [ ! -e "$dest" ] || dest="$archive/$name-$(date +%Y%m%d%H%M%S)"

    if [ "$dry" -eq 1 ]; then
      echo "would archive: $name -> ${dest#"$root"/}"
    else
      mkdir -p "$archive"
      mv "$dir" "$dest"
      echo "archived: $name -> ${dest#"$root"/}"
    fi
    moved=$((moved + 1))
  done

  [ "$moved" -gt 0 ] || echo "nothing to archive (threshold: ${days}d)"
}

cmd=${1:-help}
if [ $# -gt 0 ]; then
  shift
fi

case $cmd in
  ingest) cmd_ingest "$@" ;;
  archive) cmd_archive "$@" ;;
  help|-h|--help) usage ;;
  *)
    usage >&2
    die "unknown command: $cmd"
    ;;
esac
