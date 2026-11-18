#!/usr/bin/env bash
# tell-sama.sh: let Sam Altman know how much unused memory your Mac has.
#
# Usage:
#   ./tell-sama.sh              open prefilled posts on X and Threads
#   ./tell-sama.sh x            X only
#   ./tell-sama.sh threads      Threads only
#   ./tell-sama.sh --dry-run    print the message and links, open nothing
#
# Nothing is posted automatically. The script opens each site's compose
# window in your browser with the text filled in, and you press Post.

set -euo pipefail

HANDLE="sama"   # @sama on both X and Threads

usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; }

[[ "$(uname)" == "Darwin" ]] || { echo "This script reads memory the macOS way (vm_stat)." >&2; exit 1; }

# ---- args -------------------------------------------------------------------
want_x=0; want_threads=0; dry_run=0
for arg in "$@"; do
  case "$arg" in
    x|X|twitter)    want_x=1 ;;
    threads)        want_threads=1 ;;
    -n|--dry-run)   dry_run=1 ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 1 ;;
  esac
done
if (( !want_x && !want_threads )); then want_x=1; want_threads=1; fi

# ---- unused memory ----------------------------------------------------------
# Free + speculative pages: the same figure `top` shows as "unused".
unused_bytes=$(vm_stat | awk '
  NR == 1               { match($0, /[0-9]+ bytes/); ps = substr($0, RSTART, RLENGTH) + 0 }
  /^Pages free:/        { gsub(/\./, "", $3); f = $3 }
  /^Pages speculative:/ { gsub(/\./, "", $3); s = $3 }
  END                   { printf "%.0f", (f + s) * ps }')
total_bytes=$(sysctl -n hw.memsize)

human() {
  awk -v b="$1" 'BEGIN {
    if (b >= 1073741824) printf "%.2f GB", b / 1073741824
    else                 printf "%.0f MB", b / 1048576
  }'
}
unused=$(human "$unused_bytes")
total="$(( total_bytes / 1073741824 )) GB"

# ---- message (edit freely) --------------------------------------------------
MESSAGE="hey @${HANDLE}, my Mac has ${unused} of unused memory right now (out of ${total}). if you need it for the next data center, it's yours."

# ---- post -------------------------------------------------------------------
urlencode() { osascript -l JavaScript -e 'function run(a) { return encodeURIComponent(a[0]) }' "$1"; }
text=$(urlencode "$MESSAGE")

x_url="https://x.com/intent/post?text=${text}"
threads_url="https://www.threads.com/intent/post?text=${text}"

echo "Unused memory: ${unused} of ${total}"
echo
echo "Message (${#MESSAGE} chars):"
echo "  ${MESSAGE}"
echo

if (( want_x ));       then echo "X:       ${x_url}";       (( dry_run )) || open "$x_url"; fi
if (( want_threads )); then echo "Threads: ${threads_url}"; (( dry_run )) || open "$threads_url"; fi

(( dry_run )) && echo && echo "(dry run: nothing opened)"
exit 0
