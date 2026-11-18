#!/usr/bin/env bash
# Tests for tell-sama.sh. Memory readings and browsers are faked, so these run
# on any machine with bash and nothing is opened or posted.
#
#   ./tests/test.sh

set -u

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script="$here/../tell-sama.sh"
fixtures="$here/fixtures"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

passed=0
failed=0
out=""
status=0
opened=""

# check <name> <bash condition>
check() {
  if eval "$2"; then
    passed=$((passed + 1))
    echo "ok   $1"
  else
    failed=$((failed + 1))
    echo "FAIL $1"
    echo "     expected: $2"
    printf '%s\n' "$out" | sed 's/^/     | /'
  fi
}

# ---- fakes ------------------------------------------------------------------

# Stub openers record what they were asked to open.
OPENED_LOG="$tmp/opened"
mkdir "$tmp/bin"
cat > "$tmp/bin/open" <<'EOF'
#!/bin/sh
echo "open $1" >> "$OPENED_LOG"
EOF
cat > "$tmp/bin/xdg-open" <<'EOF'
#!/bin/sh
echo "xdg-open $1" >> "$OPENED_LOG"
EOF
# Fake Windows PowerShell: answers the memory query (in KB, with the CRLF that
# the real one prints) and records Start-Process calls.
cat > "$tmp/bin/powershell.exe" <<'EOF'
#!/bin/sh
for a in "$@"; do last=$a; done
case "$last" in
  *Get-CimInstance*) printf '1572864 16303428\r\n' ;;
  *Start-Process*)   echo "powershell.exe $last" >> "$OPENED_LOG" ;;
  *)                 exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/open" "$tmp/bin/xdg-open" "$tmp/bin/powershell.exe"

# A PATH with only the tools tell-sama.sh needs: no browser opener, no
# powershell.exe. (A real WSL or desktop Linux machine has both.)
mkdir "$tmp/min"
for c in bash awk od tr cat sed grep uname; do
  if p=$(command -v "$c"); then ln -s "$p" "$tmp/min/$c"; fi
done

# run [VAR=value ...] -- [args ...]
# Runs tell-sama.sh with the given environment and arguments. Sets $out
# (stdout and stderr), $status, and $opened (one line per URL it opened).
run() {
  local envs=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do envs+=("$1"); shift; done
  if [[ $# -gt 0 ]]; then shift; fi
  : > "$OPENED_LOG"
  out=$(env -u DISPLAY -u WAYLAND_DISPLAY -u WSL_DISTRO_NAME \
            OPENED_LOG="$OPENED_LOG" PATH="$tmp/bin:$PATH" \
            ${envs[@]+"${envs[@]}"} "$script" "$@" 2>&1)
  status=$?
  opened=$(cat "$OPENED_LOG")
}

nl=$'\n'
q="'"
linux=(TELL_SAMA_OS=linux "TELL_SAMA_MEMINFO=$fixtures/meminfo")
mac=(TELL_SAMA_OS=macos "TELL_SAMA_VM_STAT=$fixtures/vm_stat" TELL_SAMA_MEMSIZE=38654705664)
missing="$tmp/no-such-file"

# The expected text, percent-encoded independently (Python's urllib.parse.quote
# with safe="").
enc_linux='hey%20%40sama%2C%20my%20Linux%20box%20has%201.50%20GB%20of%20unused%20memory%20right%20now%20%28out%20of%2016%20GB%29.%20if%20you%20need%20it%20for%20the%20next%20data%20center%2C%20it%27s%20yours.'
enc_mac='hey%20%40sama%2C%20my%20Mac%20has%20479%20MB%20of%20unused%20memory%20right%20now%20%28out%20of%2036%20GB%29.%20if%20you%20need%20it%20for%20the%20next%20data%20center%2C%20it%27s%20yours.'
enc_pc='hey%20%40sama%2C%20my%20PC%20has%201.50%20GB%20of%20unused%20memory%20right%20now%20%28out%20of%2016%20GB%29.%20if%20you%20need%20it%20for%20the%20next%20data%20center%2C%20it%27s%20yours.'
x="https://x.com/intent/post?text="
th="https://www.threads.com/intent/post?text="

# ---- Linux --------------------------------------------------------------------

echo "# Linux"

run "${linux[@]}" -- --dry-run
expected="Unused memory: 1.50 GB of 16 GB

Message (131 chars):
  hey @sama, my Linux box has 1.50 GB of unused memory right now (out of 16 GB). if you need it for the next data center, it's yours.

X:       $x$enc_linux
Threads: $th$enc_linux

(dry run: nothing opened)"
check "dry run prints the exact message and links" '[[ $out == "$expected" ]]'
check "dry run exits 0" '[[ $status -eq 0 ]]'
check "dry run opens nothing" '[[ -z $opened ]]'

run "${linux[@]}" DISPLAY=:0 --
check "opens X and Threads with xdg-open" '[[ $opened == "xdg-open $x$enc_linux${nl}xdg-open $th$enc_linux" ]]'
check "says nothing about failing" '[[ $out != *"Couldn${q}t"* && $out != *"dry run"* ]]'
check "exits 0" '[[ $status -eq 0 ]]'

run "${linux[@]}" DISPLAY=:0 -- x
check "'x' opens only X" '[[ $opened == "xdg-open $x$enc_linux" && $out != *Threads:* ]]'

run "${linux[@]}" DISPLAY=:0 -- threads
check "'threads' opens only Threads" '[[ $opened == "xdg-open $th$enc_linux" && $out != *"X:  "* ]]'

run "${linux[@]}" WAYLAND_DISPLAY=wayland-0 --
check "a Wayland session counts as a desktop" '[[ $opened == "xdg-open $x$enc_linux${nl}xdg-open $th$enc_linux" ]]'

run "${linux[@]}" --
check "no desktop (SSH, container): opens nothing" '[[ -z $opened && $status -eq 0 ]]'
check "no desktop: says to paste the link" '[[ $out == *"Couldn${q}t open a browser here"* ]]'

run "${linux[@]}" DISPLAY=:0 "PATH=$tmp/min" --
check "no xdg-open: says to paste the link" '[[ $out == *"Couldn${q}t open a browser here"* && $status -eq 0 ]]'

run TELL_SAMA_OS=linux "TELL_SAMA_MEMINFO=$missing" -- --dry-run
check "unreadable /proc/meminfo: exits 1" '[[ $status -eq 1 ]]'
check "unreadable /proc/meminfo: says so" '[[ $out == *"Couldn${q}t read this machine${q}s memory."* ]]'

# ---- macOS --------------------------------------------------------------------

echo "# macOS"

run "${mac[@]}" --
check "reads free + speculative pages from vm_stat" '[[ ${out%%$nl*} == "Unused memory: 479 MB of 36 GB" ]]'
check "calls it a Mac" '[[ $out == *"Message (124 chars):${nl}  hey @sama, my Mac has 479 MB of"* ]]'
check "opens both with open" '[[ $opened == "open $x$enc_mac${nl}open $th$enc_mac" ]]'

# ---- WSL and Git Bash ---------------------------------------------------------

echo "# WSL and Git Bash"

# TELL_SAMA_MEMINFO points nowhere, so these pass only if the numbers came
# from (fake) Windows.
run TELL_SAMA_OS=wsl "TELL_SAMA_MEMINFO=$missing" --
check "WSL: reads memory from Windows" '[[ $out == *"my PC has 1.50 GB of unused memory right now (out of 16 GB)"* && $out != *note:* ]]'
check "WSL: opens both with Start-Process" '[[ $opened == "powershell.exe Start-Process ${q}$x$enc_pc${q}${nl}powershell.exe Start-Process ${q}$th$enc_pc${q}" ]]'
check "WSL: exits 0" '[[ $status -eq 0 ]]'

run TELL_SAMA_OS=gitbash "TELL_SAMA_MEMINFO=$missing" -- --dry-run
check "Git Bash: reads memory from Windows" '[[ $out == *"my PC has 1.50 GB of unused memory"* && $out != *note:* && $status -eq 0 ]]'

run TELL_SAMA_OS=wsl "TELL_SAMA_MEMINFO=$fixtures/meminfo" "PATH=$tmp/min" --
check "WSL without powershell.exe: falls back to /proc/meminfo" '[[ $out == *"note: couldn${q}t ask Windows"* && $out == *"my PC has 1.50 GB"* ]]'
check "WSL without powershell.exe: says to paste the link" '[[ $out == *"Couldn${q}t open a browser here"* && -z $opened && $status -eq 0 ]]'

# ---- arguments ----------------------------------------------------------------

echo "# Arguments"

run "${linux[@]}" -- --bogus
check "unknown option: exits 1 and shows usage" '[[ $status -eq 1 && $out == *"Unknown option: --bogus"* && $out == *Usage:* ]]'

run "${linux[@]}" -- --help
check "--help: shows usage only" '[[ $status -eq 0 && $out == *Usage:* && $out != *"Unused memory"* && $out != *HANDLE=* ]]'

run "${linux[@]}" -- -n
check "-n is short for --dry-run" '[[ $out == *"(dry run: nothing opened)"* && -z $opened ]]'

run TELL_SAMA_OS=plan9 -- --dry-run
check "unknown OS: exits 1 and names it" '[[ $status -eq 1 && $out == *"doesn${q}t know how to read memory on plan9"* ]]'

# ---- URL encoding -------------------------------------------------------------

echo "# URL encoding"

got=$(source "$script"; urlencode $'a b&c=d/\xc3\xa9\xf0\x9f\x99\x82\'!()*~._-')
out=$got
check "encodes reserved characters, UTF-8 and emoji" '[[ $got == "a%20b%26c%3Dd%2F%C3%A9%F0%9F%99%82%27%21%28%29%2A~._-" ]]'

# ---- this machine -------------------------------------------------------------

echo "# This machine"

out=$("$script" --dry-run 2>&1)
status=$?
re='^Unused memory: [0-9.]+ (MB|GB) of [0-9]+ (MB|GB)$'
check "reads real memory on $(uname -s)" '[[ $status -eq 0 && ${out%%$nl*} =~ $re ]]'

echo
if (( failed )); then
  echo "$failed failed, $passed passed"
  exit 1
fi
echo "all $passed passed"
