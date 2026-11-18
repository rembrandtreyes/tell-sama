<#
.SYNOPSIS
Let Sam Altman know how much unused memory your PC has.

.DESCRIPTION
Asks Windows how much physical memory is free, then opens X and Threads
with a post filled in. Nothing is posted automatically: you press Post.

On macOS, Linux, WSL or Git Bash, use tell-sama.sh instead.

.EXAMPLE
.\tell-sama.ps1
Open prefilled posts on X and Threads.

.EXAMPLE
.\tell-sama.ps1 x
X only.

.EXAMPLE
.\tell-sama.ps1 threads
Threads only.

.EXAMPLE
.\tell-sama.ps1 -DryRun
Print the message and links, open nothing.
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet('both', 'x', 'threads')]
  [string]$Target = 'both',

  [Alias('n')]
  [switch]$DryRun
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Handle = 'sama'   # @sama on both X and Threads

# 1610612736 2 -> "1.50 GB"     502497280 2 -> "479 MB"
function Format-Size([double]$Bytes, [int]$Decimals) {
  $inv = [Globalization.CultureInfo]::InvariantCulture
  if ($Bytes -ge 1GB) { return ($Bytes / 1GB).ToString("F$Decimals", $inv) + ' GB' }
  return ($Bytes / 1MB).ToString('F0', $inv) + ' MB'
}

# Percent-encode everything except A-Z a-z 0-9 - . _ ~ (RFC 3986).
# Older .NET leaves ! ' ( ) * alone, so encode those by hand.
function ConvertTo-UrlComponent([string]$Text) {
  $s = [uri]::EscapeDataString($Text)
  foreach ($c in [char[]]"!'()*") {
    $s = $s.Replace([string]$c, ('%{0:X2}' -f [int]$c))
  }
  return $s
}

if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
  throw 'tell-sama.ps1 is for Windows. On macOS or Linux, run tell-sama.sh instead.'
}

# ---- unused memory ----
# FreePhysicalMemory is what Task Manager calls "Available": truly free pages
# plus standby cache that Windows can hand out right away.
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$unused = Format-Size ([double]$os.FreePhysicalMemory * 1KB) 2
$total = Format-Size ([double]$os.TotalVisibleMemorySize * 1KB) 0

# ---- message (edit freely) ----
$Message = "hey @$Handle, my PC has $unused of unused memory right now (out of $total). if you need it for the next data center, it's yours."

# ---- post ----
$text = ConvertTo-UrlComponent $Message
$urls = [ordered]@{}
if ($Target -ne 'threads') { $urls['X'] = "https://x.com/intent/post?text=$text" }
if ($Target -ne 'x') { $urls['Threads'] = "https://www.threads.com/intent/post?text=$text" }

"Unused memory: $unused of $total"
''
"Message ($($Message.Length) chars):"
"  $Message"
''

$failed = $false
foreach ($name in @($urls.Keys)) {
  $url = $urls[$name]
  '{0,-8} {1}' -f "${name}:", $url
  if (-not $DryRun) {
    try { Start-Process $url } catch { $failed = $true }
  }
}

if ($DryRun) {
  ''
  '(dry run: nothing opened)'
} elseif ($failed) {
  ''
  "Couldn't open a browser here, so paste the link above into one."
}
