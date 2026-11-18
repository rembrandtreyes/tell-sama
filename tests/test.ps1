# Tests for tell-sama.ps1. Get-CimInstance and Start-Process are replaced with
# fakes, so these run in Windows PowerShell 5.1 and in PowerShell 7 on any
# system, and nothing is opened or posted.
#
#   pwsh ./tests/test.ps1
#   powershell -ExecutionPolicy Bypass -File .\tests\test.ps1

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$tellSama = [IO.Path]::Combine($PSScriptRoot, '..', 'tell-sama.ps1')

$script:passes = 0
$script:failures = 0

function Check([string]$Name, [bool]$Condition, [string]$Detail = '') {
  if ($Condition) {
    $script:passes++
    Write-Host "ok   $Name"
  } else {
    $script:failures++
    Write-Host "FAIL $Name"
    foreach ($line in ($Detail -split "`n")) { Write-Host "     | $line" }
  }
}

# ---- fakes ------------------------------------------------------------------
# Functions win over cmdlets of the same name, and tell-sama.ps1 runs in a
# child scope of this one, so it calls these instead of the real ones.

$global:FakeFree = 1572864     # KB: 1.50 GB
$global:FakeTotal = 16303428   # KB: 16 GB
$global:Opened = New-Object 'System.Collections.Generic.List[string]'
$global:OpenFails = $false

function Get-CimInstance {
  param([string]$ClassName)
  [pscustomobject]@{
    FreePhysicalMemory     = [uint64]$global:FakeFree
    TotalVisibleMemorySize = [uint64]$global:FakeTotal
  }
}

function Start-Process {
  param([string]$FilePath)
  if ($global:OpenFails) { throw 'no browser' }
  $global:Opened.Add($FilePath)
}

# Runs tell-sama.ps1 with the given parameters and returns its output lines.
function Invoke-TellSama([hashtable]$Params = @{}) {
  $global:Opened.Clear()
  $lines = & $tellSama @Params
  return , @($lines)
}

# The expected text, percent-encoded independently (Python's
# urllib.parse.quote with safe="").
$enc = 'hey%20%40sama%2C%20my%20PC%20has%201.50%20GB%20of%20unused%20memory%20right%20now%20%28out%20of%2016%20GB%29.%20if%20you%20need%20it%20for%20the%20next%20data%20center%2C%20it%27s%20yours.'
$enc480 = 'hey%20%40sama%2C%20my%20PC%20has%20480%20MB%20of%20unused%20memory%20right%20now%20%28out%20of%208%20GB%29.%20if%20you%20need%20it%20for%20the%20next%20data%20center%2C%20it%27s%20yours.'
$x = 'https://x.com/intent/post?text='
$th = 'https://www.threads.com/intent/post?text='

# ---- Windows (faked) ----------------------------------------------------------

Write-Host '# Windows'

$out = Invoke-TellSama -Params @{ DryRun = $true }
$text = $out -join "`n"
$expected = @(
  'Unused memory: 1.50 GB of 16 GB'
  ''
  'Message (124 chars):'
  "  hey @sama, my PC has 1.50 GB of unused memory right now (out of 16 GB). if you need it for the next data center, it's yours."
  ''
  "X:       $x$enc"
  "Threads: $th$enc"
  ''
  '(dry run: nothing opened)'
) -join "`n"
Check 'dry run prints the exact message and links' ($text -ceq $expected) $text
Check 'dry run opens nothing' ($global:Opened.Count -eq 0)

$out = Invoke-TellSama
$text = $out -join "`n"
$seen = $global:Opened -join "`n"
Check 'opens X, then Threads' ($seen -ceq "$x$enc`n$th$enc") $seen
Check 'says nothing about failing' (-not $text.Contains("Couldn't") -and -not $text.Contains('dry run')) $text

$out = Invoke-TellSama -Params @{ Target = 'x' }
$seen = $global:Opened -join "`n"
Check "'x' opens only X" (($seen -ceq "$x$enc") -and -not ($out -join "`n").Contains('Threads:')) $seen

$out = Invoke-TellSama -Params @{ Target = 'threads' }
$seen = $global:Opened -join "`n"
Check "'threads' opens only Threads" (($seen -ceq "$th$enc") -and -not ($out -join "`n").Contains('X: ')) $seen

$global:FakeFree = 491520      # KB: 480 MB
$global:FakeTotal = 8388608    # KB: 8 GB
$out = Invoke-TellSama -Params @{ DryRun = $true }
$text = $out -join "`n"
Check 'under 1 GB is shown in MB' ($out[0] -ceq 'Unused memory: 480 MB of 8 GB') $text
Check 'the link carries the MB figure' ($text.Contains("X:       $x$enc480")) $text
$global:FakeFree = 1572864
$global:FakeTotal = 16303428

$global:OpenFails = $true
$out = Invoke-TellSama
$text = $out -join "`n"
Check 'no browser: says to paste the link' ($out[-1] -ceq "Couldn't open a browser here, so paste the link above into one.") $text
$global:OpenFails = $false

# ---- arguments ----------------------------------------------------------------

Write-Host '# Arguments'

$err = ''
try { $null = Invoke-TellSama -Params @{ Target = 'bogus' } } catch { $err = $_.Exception.Message }
Check 'an unknown target is rejected' ($err -match 'bogus') $err

$out = Invoke-TellSama -Params @{ n = $true }
Check '-n is short for -DryRun' (($out[-1] -ceq '(dry run: nothing opened)') -and $global:Opened.Count -eq 0) ($out -join "`n")

# ---- URL encoding -------------------------------------------------------------

Write-Host '# URL encoding'

# Dot-source the script inside a script block to get at its functions.
$tricky = 'a b&c=d/' + [char]0xE9 + [char]::ConvertFromUtf32(0x1F642) + "'!()*~._-"
$got = & { $null = . $tellSama -DryRun; ConvertTo-UrlComponent $tricky }
Check 'encodes reserved characters, UTF-8 and emoji' ($got -ceq 'a%20b%26c%3Dd%2F%C3%A9%F0%9F%99%82%27%21%28%29%2A~._-') $got

# ---- this machine -------------------------------------------------------------

Remove-Item Function:\Get-CimInstance, Function:\Start-Process
Remove-Variable -Scope Global -Name FakeFree, FakeTotal, Opened, OpenFails

Write-Host '# This machine'

if ([Environment]::OSVersion.Platform -eq 'Win32NT') {
  $out = @(& $tellSama -DryRun)
  $text = $out -join "`n"
  $ok = ($out[0] -match '^Unused memory: [0-9.]+ (MB|GB) of [0-9]+ (MB|GB)$') -and $text.Contains('my PC has')
  Check 'reads real memory from Windows' $ok $text
} else {
  $err = ''
  try { $null = & $tellSama -DryRun } catch { $err = $_.Exception.Message }
  Check 'off Windows, points to tell-sama.sh' ($err -match 'tell-sama\.sh') $err
}

Write-Host ''
if ($script:failures) {
  Write-Host "$($script:failures) failed, $($script:passes) passed"
  exit 1
}
Write-Host "all $($script:passes) passed"
