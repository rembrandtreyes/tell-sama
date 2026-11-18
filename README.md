# tell-sama

Let Sam Altman know how much unused RAM your Mac has, on X or Threads.

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

```bash
git clone https://github.com/rembrandtreyes/tell-sama.git
cd tell-sama
./tell-sama.sh              # open prefilled posts on X and Threads
./tell-sama.sh x            # X only
./tell-sama.sh threads      # Threads only
./tell-sama.sh --dry-run    # print the message and links, open nothing
```

Nothing is posted automatically. The script opens each site's compose window in your browser with the text filled in, and you press Post. You don't need API keys or a developer account.

To change the wording, edit the `MESSAGE` line in the script.

## How it works

- **Memory:** reads `vm_stat` and adds free and speculative pages. That's the same number `top` shows as "unused". Total comes from `sysctl hw.memsize`.
- **Posting:** builds X and Threads web intent URLs and opens them with `open`. The text is URL-encoded with JavaScript for Automation (`osascript`), so it needs nothing outside macOS.

macOS keeps most of your RAM busy as cache, so the unused figure is usually small. That's normal, and it makes for a better post.

## Requirements

macOS. Nothing else.

## Be a good neighbour

One post is a joke. Posting on a timer, or from a fleet of machines, is spam. Run it when you feel like it, press Post yourself, and leave it there.

## Credit

Inspired by [IainKay/ram-altman](https://github.com/IainKay/ram-altman), which does the same thing on Linux by email. This version is for Macs, and it posts.

## License

[MIT](LICENSE)
