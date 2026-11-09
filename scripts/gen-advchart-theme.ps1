# Regenerate source/tyControls.AdvanceChart.Theme.pas from themes/advchart.tycss.
#
# The chart's own tokens and rules live in themes/advchart.tycss, not in the core's light.tycss.
# The generated unit compiles that file into the binary (TyAdvChartCss, equal to the file
# byte-for-byte: test.advchart.theme checks it) and registers it in its initialization as the
# add-on "advchart" (TyRegisterAddOnCss), so every style model's base layer carries it. Edit
# advchart.tycss, then re-run this script: the unit is generated, never hand-maintained.
#
# Run from anywhere with Windows PowerShell 5.1: powershell -File scripts/gen-advchart-theme.ps1 --
# the paths are the repository this script lives in (see gen-builtinthemes.ps1 for why relative
# ones were not safe: [IO.File] resolves them against the process's directory, not Set-Location's).
# This script OVERWRITES the whole unit: anything not in the template below is gone.
$ErrorActionPreference = 'Stop'
$enc = New-Object System.Text.UTF8Encoding($false)   # UTF-8, no BOM
$root = Split-Path $PSScriptRoot -Parent
$src = [IO.File]::ReadAllText((Join-Path $root 'themes\advchart.tycss'), $enc)
$lines = $src -split "`r`n|`n"
if ($lines.Count -gt 0 -and $lines[-1] -eq '') { $lines = $lines[0..($lines.Count - 2)] }  # drop trailing empty

$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("unit tyControls.AdvanceChart.Theme;`r`n`r`n")
[void]$sb.Append("{ The chart's own tycss (its --advchart-* tokens and its TyAdvChart* rules), compiled into the`r`n")
[void]$sb.Append("  binary and registered in this unit's initialization as the add-on ""advchart"", so every`r`n")
[void]$sb.Append("  style model's base layer carries it after light.tycss. GENERATED from themes/advchart.tycss`r`n")
[void]$sb.Append("  by scripts/gen-advchart-theme.ps1 - do NOT edit by hand; edit advchart.tycss and re-run the`r`n")
[void]$sb.Append("  generator. Sync-tested byte-identical to advchart.tycss (test.advchart.theme). }`r`n`r`n")
[void]$sb.Append("{`$mode objfpc}{`$H+}`r`n`r`ninterface`r`n`r`n")
[void]$sb.Append("function TyAdvChartCss: string;`r`n`r`n")
[void]$sb.Append("implementation`r`n`r`n")
[void]$sb.Append("uses`r`n  tyControls.Css.AddOns;`r`n`r`n")
[void]$sb.Append("function TyAdvChartCss: string;`r`nbegin`r`n  Result :=`r`n")
for ($i = 0; $i -lt $lines.Count; $i++) {
  $escd = $lines[$i] -replace "'", "''"
  if ($i -lt $lines.Count - 1) { $term = ' +' } else { $term = ';' }
  [void]$sb.Append("    '" + $escd + "' + LineEnding" + $term + "`r`n")
}
[void]$sb.Append("end;`r`n`r`n")
[void]$sb.Append("initialization`r`n  TyRegisterAddOnCss('advchart', TyAdvChartCss);`r`n`r`nend.`r`n")

[IO.File]::WriteAllText((Join-Path $root 'source\tyControls.AdvanceChart.Theme.pas'), $sb.ToString(), $enc)
Write-Output ("Regenerated AdvanceChart.Theme.pas from advchart.tycss (" + $lines.Count + " content lines)")
