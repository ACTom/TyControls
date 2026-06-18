# Regenerate source/tyControls.DefaultTheme.pas from themes/light.tycss.
#
# The built-in default theme (TyBuiltinThemeCss) must equal light.tycss byte-for-byte
# (enforced by test.defaulttheme's sync test). This makes light.tycss the SINGLE
# SOURCE: edit light.tycss, then re-run this script — DefaultTheme.pas is generated,
# never hand-maintained. Run from the repo root: powershell -File gen-defaulttheme.ps1
$ErrorActionPreference = 'Stop'
$enc = New-Object System.Text.UTF8Encoding($false)   # UTF-8, no BOM (light.tycss has an em-dash)
$src = [IO.File]::ReadAllText('themes\light.tycss', $enc)
$lines = $src -split "`r`n|`n"
if ($lines.Count -gt 0 -and $lines[-1] -eq '') { $lines = $lines[0..($lines.Count - 2)] }  # drop trailing empty

$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("unit tyControls.DefaultTheme;`r`n`r`n")
[void]$sb.Append("{ Built-in default skin compiled into the binary (no runtime file dependency) so`r`n")
[void]$sb.Append("  controls render sensibly with no theme loaded (no Controller, or the Lazarus`r`n")
[void]$sb.Append("  designer). GENERATED from themes/light.tycss by gen-defaulttheme.ps1 - do NOT edit`r`n")
[void]$sb.Append("  by hand; edit light.tycss and re-run the generator. Sync-tested byte-identical to`r`n")
[void]$sb.Append("  light.tycss (test.defaulttheme). }`r`n`r`n")
[void]$sb.Append("{`$mode objfpc}{`$H+}`r`n`r`ninterface`r`n`r`n")
[void]$sb.Append("function TyBuiltinThemeCss: string;`r`n`r`nimplementation`r`n`r`n")
[void]$sb.Append("function TyBuiltinThemeCss: string;`r`nbegin`r`n  Result :=`r`n")
for ($i = 0; $i -lt $lines.Count; $i++) {
  $escd = $lines[$i] -replace "'", "''"
  if ($i -lt $lines.Count - 1) { $term = ' +' } else { $term = ';' }
  [void]$sb.Append("    '" + $escd + "' + LineEnding" + $term + "`r`n")
}
[void]$sb.Append("end;`r`n`r`nend.`r`n")

[IO.File]::WriteAllText('source\tyControls.DefaultTheme.pas', $sb.ToString(), $enc)
Write-Output ("Regenerated DefaultTheme.pas from light.tycss (" + $lines.Count + " content lines)")
