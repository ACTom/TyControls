# Launch every built example and confirm it puts a real, visible top-level window on screen.
#
# WHY THIS EXISTS
# ---------------
# `lazbuild` proves an example COMPILES. It proves nothing about whether its .lfm
# STREAMS, because a .lfm is a resource: a property that no longer exists -- or whose
# TYPE or MEANING changed -- is not a compile error, it is an EReadError inside
# CreateForm at startup. That is how 46/46 examples built green for several rounds
# while one of them could not open its main form.
#
# scripts/check-lfm-props.py catches the renamed and un-published case by NAME.
# It cannot see a value whose meaning changed (a mask written in an older dialect,
# an enum value that moved, a default that flipped). Only running the thing catches
# those, and this is the cheapest way to run all of them.
#
# It also catches the failure mode that looks exactly like "the app is just slow":
# a process that is alive with no window is usually sitting behind a MODAL error box
# it opened before Show. An empty .po entry (msgid and msgstr both blank) does that.
#
# WHAT IT DOES NOT CATCH
# ----------------------
# Anything past the first paint. A window that opens and is wrong is a pass here.
#
# USAGE
#   powershell -File scripts/smoke-launch-examples.ps1
#   powershell -File scripts/smoke-launch-examples.ps1 -TimeoutSec 30   # slow machine
#
# Exit code 1 and one line per suspect if anything failed to show a window.
#
# NOTE: processes are killed BY PID, never by image name. `taskkill /im` is
# machine-wide and will kill other people's (and other agents') runs.
param([int]$TimeoutSec = 20)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class TySmokeWin {
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
}
"@

$root = Split-Path -Parent $PSScriptRoot
$exes = Get-ChildItem -Path (Join-Path $root 'examples') -Recurse -Filter *.exe |
        Sort-Object FullName

if ($exes.Count -eq 0) {
  Write-Output "No example executables found. Build them first:"
  Write-Output '  for /d %d in (examples\*) do lazbuild -B --quiet %d\*.lpi'
  exit 1
}

$bad = @()
$ok  = 0

foreach ($e in $exes) {
  $p = $null
  try {
    $p = Start-Process -FilePath $e.FullName -WorkingDirectory $e.DirectoryName -PassThru
  } catch {
    $bad += "$($e.Name): could not start -- $($_.Exception.Message)"
    continue
  }

  # Poll rather than sleep a fixed amount: the heaviest examples (antdesign, demo,
  # grid) take about five seconds to first paint on a warm machine, and a fixed wait
  # tuned to them would make the whole sweep several minutes longer for no gain.
  $shown = $false
  foreach ($s in 1..$TimeoutSec) {
    Start-Sleep -Milliseconds 1000
    $p.Refresh()
    if ($p.HasExited) {
      $bad += "$($e.Name): exited on its own after ${s}s with code $($p.ExitCode)"
      $shown = $true
      break
    }
    $h = $p.MainWindowHandle
    if ($h -ne [IntPtr]::Zero -and [TySmokeWin]::IsWindowVisible($h)) {
      $ok++
      $shown = $true
      break
    }
  }
  if (-not $shown) {
    $bad += "$($e.Name): alive but no visible window after ${TimeoutSec}s -- take a screenshot before assuming it is slow; a modal error box opened before Show looks exactly like this"
  }
  try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch {}
}

Write-Output "smoke: $ok of $($exes.Count) examples opened a visible window"
if ($bad.Count -gt 0) {
  foreach ($b in $bad) { Write-Output "  $b" }
  Write-Output ""
  Write-Output "$($bad.Count) suspect(s). Each one is an example a user cannot open."
  exit 1
}
exit 0
