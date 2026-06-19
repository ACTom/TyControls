# Regenerate source/tyControls.BuiltinThemeData.pas from themes/auto.tycss + themes/system.tycss.
# These two CSS strings are compiled into the binary (the dual-mode base for the curated
# theme pack + the OS-accent 'system' theme). Sync-tested byte-identical (test.builtinthemes).
# Run from the repo root:  powershell -File gen-builtinthemes.ps1
$ErrorActionPreference = 'Stop'
$enc = New-Object System.Text.UTF8Encoding($false)   # UTF-8, no BOM

function Emit-Func($name, $file) {
  $src = [IO.File]::ReadAllText($file, $enc)
  $lines = $src -split "`r`n|`n"
  if ($lines.Count -gt 0 -and $lines[-1] -eq '') { $lines = $lines[0..($lines.Count - 2)] }  # drop trailing empty
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append("function $name`: string;`r`nbegin`r`n  Result :=`r`n")
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $escd = $lines[$i] -replace "'", "''"
    if ($i -lt $lines.Count - 1) { $term = ' +' } else { $term = ';' }
    [void]$sb.Append("    '" + $escd + "' + LineEnding" + $term + "`r`n")
  }
  [void]$sb.Append("end;`r`n")
  return $sb.ToString()
}

$u = New-Object System.Text.StringBuilder
[void]$u.Append("unit tyControls.BuiltinThemeData;`r`n`r`n")
[void]$u.Append("{ GENERATED from themes/auto.tycss + themes/system.tycss by gen-builtinthemes.ps1 - do NOT`r`n")
[void]$u.Append("  edit by hand; edit the .tycss files and re-run the generator. Sync-tested byte-identical`r`n")
[void]$u.Append("  to those files (test.builtinthemes). }`r`n`r`n")
[void]$u.Append("{`$mode objfpc}{`$H+}`r`n`r`ninterface`r`n`r`n")
[void]$u.Append("function TyBuiltinDualBaseCss: string;`r`nfunction TyBuiltinSystemCss: string;`r`n`r`nimplementation`r`n`r`n")
[void]$u.Append((Emit-Func 'TyBuiltinDualBaseCss' 'themes\auto.tycss'))
[void]$u.Append("`r`n")
[void]$u.Append((Emit-Func 'TyBuiltinSystemCss' 'themes\system.tycss'))
[void]$u.Append("`r`nend.`r`n")
[IO.File]::WriteAllText('source\tyControls.BuiltinThemeData.pas', $u.ToString(), $enc)
Write-Output "Regenerated BuiltinThemeData.pas from auto.tycss + system.tycss"
