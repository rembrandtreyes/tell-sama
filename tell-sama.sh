#!/usr/bin/env bash
# tell-sama.sh: let Sam Altman know how much unused memory your computer has.
#
# Usage:
#   ./tell-sama.sh              open prefilled posts on X and Threads
#   ./tell-sama.sh x            X only
#   ./tell-sama.sh threads      Threads only
#   ./tell-sama.sh --dry-run    print the message and links, open nothing
#
# Runs on macOS, Linux, WSL and Git Bash. In Windows PowerShell, use
# tell-sama.ps1 instead.
#
# Nothing is posted automatically. The script opens each site's compose
# window in your browser with the text filled in, and you press Post.

HANDLE="sama"   # @sama on both X and Threads

# The tests fake the machine with TELL_SAMA_OS (macos, linux, wsl or gitbash),
# TELL_SAMA_MEMINFO, TELL_SAMA_VM_STAT and TELL_SAMA_MEMSIZE.

usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

detect_os() {
  if [[ -n "${TELL_SAMA_OS:-}" ]]; then echo "$TELL_SAMA_OS"; return; fi
  case "$(uname -s)" in
    Darwin) echo macos ;;
    Linux)
      if [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
        echo wsl
      else
        echo linux
      fi ;;
    MINGW*|MSYS*|CYGWIN*) echo gitbash ;;
    *) uname -s ;;
  esac
}

# ---- memory -----------------------------------------------------------------
# Each mem_* function prints "<unused bytes> <total bytes>".

# macOS: free + speculative pages, the same figure `top` shows as "unused".
mem_macos() {
  local vm total
  if [[ -n "${TELL_SAMA_VM_STAT:-}" ]]; then vm=$(cat "$TELL_SAMA_VM_STAT"); else vm=$(vm_stat); fi
  total=${TELL_SAMA_MEMSIZE:-$(sysctl -n hw.memsize)}
  printf '%s\n' "$vm" | awk -v total="$total" '
    NR == 1               { match($0, /[0-9]+ bytes/); ps = substr($0, RSTART, RLENGTH) + 0 }
    /^Pages free:/        { gsub(/\./, "", $3); f = $3 }
    /^Pages speculative:/ { gsub(/\./, "", $3); s = $3 }
    END                   { printf "%.0f %.0f\n", (f + s) * ps, total }'
}

# Linux: MemFree, the "free" column in `free`. Page cache doesn't count.
mem_linux() {
  awk '/^MemFree:/ { f = $2 } /^MemTotal:/ { t = $2 }
       END { printf "%.0f %.0f\n", f * 1024, t * 1024 }' "${TELL_SAMA_MEMINFO:-/proc/meminfo}"
}

# WSL and Git Bash: ask Windows, because /proc/meminfo there describes the
# WSL VM (or an emulation of it), not the PC.
mem_windows() {
  local out="" free total re='^[0-9]+ [0-9]+$'
  if command -v powershell.exe >/dev/null 2>&1; then
    out=$(powershell.exe -NoProfile -NonInteractive -Command \
      '$o = Get-CimInstance Win32_OperatingSystem; "$($o.FreePhysicalMemory) $($o.TotalVisibleMemorySize)"' \
      2>/dev/null | tr -d '\r') || out=""
  fi
  if [[ "$out" =~ $re ]]; then
    read -r free total <<< "$out"
    awk -v f="$free" -v t="$total" 'BEGIN { printf "%.0f %.0f\n", f * 1024, t * 1024 }'
  else
    echo "note: couldn't ask Windows for its memory, so this comes from /proc/meminfo instead." >&2
    mem_linux
  fi
}

# human 1610612736 2  ->  "1.50 GB"      human 502497280 2  ->  "479 MB"
human() {
  LC_ALL=C awk -v b="$1" -v d="$2" 'BEGIN {
    if (b >= 1073741824) { fmt = "%." d "f GB"; printf fmt, b / 1073741824 }
    else                   printf "%.0f MB", b / 1048576
  }'
}

# ---- posting ----------------------------------------------------------------

# Percent-encode everything except A-Z a-z 0-9 - . _ ~ (RFC 3986), byte by byte.
urlencode() {
  local hex ch out=""
  for hex in $(printf '%s' "$1" | od -An -v -tx1); do
    case "$hex" in
      2d|2e|5f|7e|3[0-9]|4[1-9a-f]|5[0-9a]|6[1-9a-f]|7[0-9a]) printf -v ch "\\x$hex" ;;
      *) printf -v ch '%%%02X' "0x$hex" ;;
    esac
    out+="$ch"
  done
  printf '%s' "$out"
}

open_url() {  # open_url <os> <url>
  case "$1" in
    macos) open "$2" ;;
    linux)
      # No desktop session (SSH, containers): don't let xdg-open start a
      # terminal browser behind our back.
      [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] || return 1
      xdg-open "$2" ;;
    wsl|gitbash) powershell.exe -NoProfile -NonInteractive -Command "Start-Process '$2'" ;;
    *) return 1 ;;
  esac
}

main() {
  set -euo pipefail

  local want_x=0 want_threads=0 dry_run=0 arg
  for arg in "$@"; do
    case "$arg" in
      x|X|twitter)  want_x=1 ;;
      threads)      want_threads=1 ;;
      -n|--dry-run) dry_run=1 ;;
      -h|--help)    usage; return 0 ;;
      *) echo "Unknown option: $arg" >&2; usage >&2; return 1 ;;
    esac
  done
  if (( !want_x && !want_threads )); then want_x=1; want_threads=1; fi

  local os machine reader
  os=$(detect_os)
  case "$os" in
    macos)       machine="Mac";       reader=mem_macos ;;
    linux)       machine="Linux box"; reader=mem_linux ;;
    wsl|gitbash) machine="PC";        reader=mem_windows ;;
    *) echo "Sorry, tell-sama.sh doesn't know how to read memory on ${os}." >&2; return 1 ;;
  esac

  # ---- unused memory ----
  local mem unused_bytes total_bytes re='^[0-9]+ [1-9][0-9]*$'
  mem=$("$reader") || mem=""
  if ! [[ "$mem" =~ $re ]]; then
    echo "Couldn't read this machine's memory." >&2
    return 1
  fi
  read -r unused_bytes total_bytes <<< "$mem"

  local unused total
  unused=$(human "$unused_bytes" 2)
  total=$(human "$total_bytes" 0)

  # ---- message (edit freely) ----
  local MESSAGE="hey @${HANDLE}, my ${machine} has ${unused} of unused memory right now (out of ${total}). if you need it for the next data center, it's yours."

  # ---- post ----
  local text x_url threads_url
  text=$(urlencode "$MESSAGE")
  x_url="https://x.com/intent/post?text=${text}"
  threads_url="https://www.threads.com/intent/post?text=${text}"

  echo "Unused memory: ${unused} of ${total}"
  echo
  echo "Message (${#MESSAGE} chars):"
  echo "  ${MESSAGE}"
  echo

  local failed=0
  if (( want_x )); then
    echo "X:       ${x_url}"
    if (( !dry_run )); then open_url "$os" "$x_url" >/dev/null 2>&1 || failed=1; fi
  fi
  if (( want_threads )); then
    echo "Threads: ${threads_url}"
    if (( !dry_run )); then open_url "$os" "$threads_url" >/dev/null 2>&1 || failed=1; fi
  fi

  if (( dry_run )); then
    echo
    echo "(dry run: nothing opened)"
  elif (( failed )); then
    echo
    echo "Couldn't open a browser here, so paste the link above into one."
  fi
}

# Run main unless the file is being sourced (the tests source it).
if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
  main "$@"
fi
