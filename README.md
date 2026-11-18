# tell-sama

[![test](https://github.com/rembrandtreyes/tell-sama/actions/workflows/test.yml/badge.svg)](https://github.com/rembrandtreyes/tell-sama/actions/workflows/test.yml)

Let Sam Altman know how much unused RAM your computer has, on X or Threads. Runs on macOS, Linux and Windows.

Sam Altman called the RAM sitting in home PCs a "quite terrible" use of the world's DRAM supply. If he's going to find it, someone has to tell him where it is.

```
$ ./tell-sama.sh --dry-run
Unused memory: 139 MB of 36 GB

Message (124 chars):
  hey @sama, my Mac has 139 MB of unused memory right now (out of 36 GB). if you need it for the next data center, it's yours.

X:       https://x.com/intent/post?text=hey%20%40sama...
Threads: https://www.threads.com/intent/post?text=hey%20%40sama...

(dry run: nothing opened)
```

## Usage

On macOS, Linux, WSL or Git Bash:

```bash
git clone https://github.com/rembrandtreyes/tell-sama.git
cd tell-sama
./tell-sama.sh              # open prefilled posts on X and Threads
./tell-sama.sh x            # X only
./tell-sama.sh threads      # Threads only
./tell-sama.sh --dry-run    # print the message and links, open nothing
```

On Windows, from PowerShell or Command Prompt:

```powershell
powershell -ExecutionPolicy Bypass -File .\tell-sama.ps1            # X and Threads
powershell -ExecutionPolicy Bypass -File .\tell-sama.ps1 x          # X only
powershell -ExecutionPolicy Bypass -File .\tell-sama.ps1 threads    # Threads only
powershell -ExecutionPolicy Bypass -File .\tell-sama.ps1 -DryRun    # print, open nothing
```

`-ExecutionPolicy Bypass` lets this one run go ahead without changing your settings. Windows blocks unsigned scripts by default.

Nothing is posted automatically. The script opens each site's compose window in your browser with the text filled in, and you press Post. You don't need API keys or a developer account. If there's no browser to open (an SSH session, a container), it prints the links for you to paste.

To change the wording, edit the `MESSAGE` line in `tell-sama.sh` or the `$Message` line in `tell-sama.ps1`.

## What "unused" means

Each system counts it its own way, and the script uses the system's own figure:

| Where you run it | The number it reports |
| --- | --- |
| macOS | Free plus speculative pages from `vm_stat`, the figure `top` calls "unused". Usually small, because macOS keeps RAM busy as cache. |
| Linux | `MemFree` from `/proc/meminfo`, the "free" column in `free`. Page cache doesn't count, so this is usually small too. |
| WSL, Git Bash | Asks Windows through `powershell.exe`, because `/proc/meminfo` there describes the WSL VM, not your PC. |
| Windows PowerShell | `FreePhysicalMemory` from `Win32_OperatingSystem`, which Task Manager shows as "Available". It includes standby cache, so Windows numbers run bigger. |

Small numbers make for a better post.

## How it works

- **Memory:** see the table above. Totals come from `sysctl hw.memsize`, `MemTotal`, or `TotalVisibleMemorySize`.
- **Posting:** builds X and Threads web intent URLs and percent-encodes the text: byte by byte with `od` in bash, and with `[uri]::EscapeDataString` in PowerShell.
- **Opening:** `open` on macOS, `xdg-open` on a Linux desktop, and `Start-Process` on Windows (also from WSL and Git Bash).

## Requirements

- **macOS, Linux, WSL, Git Bash:** bash 3.2 or later, plus `awk` and `od`, which every one of these already has.
- **Windows:** Windows PowerShell 5.1, which comes with Windows 10 and 11, or PowerShell 7.

Nothing to install.

## Tests

```bash
./tests/test.sh          # tell-sama.sh
pwsh ./tests/test.ps1    # tell-sama.ps1
```

The tests fake the memory readings and the browser, so they run on any machine and never open or post anything. Each suite also does one real dry run on the machine it's on.

GitHub Actions runs them on every push and pull request:

- `tell-sama.sh` on Ubuntu, macOS, Debian, Fedora, Alpine and WSL, plus a real dry run in Git Bash.
- `tell-sama.ps1` in Windows PowerShell 5.1, and in PowerShell 7 on Windows, Linux and macOS.

## Be a good neighbour

One post is a joke. Posting on a timer, or from a fleet of machines, is spam. Run it when you feel like it, press Post yourself, and leave it there.

## Credit

Inspired by [IainKay/ram-altman](https://github.com/IainKay/ram-altman), which does the same thing on Linux by email. This version runs on Macs, Linux and Windows, and it posts.

## License

[MIT](LICENSE)
