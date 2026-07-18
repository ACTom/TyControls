# Regenerate source/tyControls.DefaultTheme.pas from themes/light.tycss.
#
# The built-in default theme (TyBuiltinThemeCss) must equal light.tycss byte-for-byte
# (enforced by test.defaulttheme's sync test). This makes light.tycss the SINGLE
# SOURCE: edit light.tycss, then re-run this script — DefaultTheme.pas is generated,
# never hand-maintained. Run from the repo root: powershell -File gen-defaulttheme.ps1
#
# The unit also exports TyBuiltinBaseModeCss, which is NOT derived from light.tycss (a
# single-mode theme has no @mode blocks). It is carried verbatim below, because this
# script OVERWRITES the whole unit: leaving it out of the template does not "preserve"
# it, it deletes it — and the unit then fails to compile (StyleModel calls it).
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
[void]$sb.Append("function TyBuiltinThemeCss: string;`r`n")
# --- carried verbatim: the hand-authored per-mode base tokens (see header note) -------
[void]$sb.Append("{ Per-mode contrast tokens for the seeded base " + [char]0x2014 + " NOT part of the light theme (which is`r`n")
[void]$sb.Append("  single-mode and byte-synced to light.tycss). The model layers these UNDER a dual-mode user`r`n")
[void]$sb.Append("  theme so a skin that overrides the surface but omits the ink inherits a readable per-mode`r`n")
[void]$sb.Append("  value for the controls it does not restyle (menu/tree/tabset/" + [char]0x2026 + "). Values match auto.tycss, so`r`n")
[void]$sb.Append("  the default theme is unchanged; a single-mode theme keeps the light :root defaults. Derived`r`n")
[void]$sb.Append("  tokens (--muted etc.) re-derive from these. Hand-written (not generated). }`r`n")
[void]$sb.Append("function TyBuiltinBaseModeCss: string;`r`n`r`n")
[void]$sb.Append("implementation`r`n`r`n")
[void]$sb.Append("function TyBuiltinBaseModeCss: string;`r`nbegin`r`n  Result :=`r`n")
[void]$sb.Append("    '@mode light { :root { --on-surface: #1F2937; --surface: #FFFFFF; --border: #D1D5DB; } }' + LineEnding +`r`n")
[void]$sb.Append("    '@mode dark  { :root { --on-surface: #E5E7EB; --surface: #1E1E1E; --border: #3F3F46; } }' + LineEnding;`r`n")
[void]$sb.Append("end;`r`n`r`n")
# --- generated from light.tycss -------------------------------------------------------
[void]$sb.Append("function TyBuiltinThemeCss: string;`r`nbegin`r`n  Result :=`r`n")
for ($i = 0; $i -lt $lines.Count; $i++) {
  $escd = $lines[$i] -replace "'", "''"
  if ($i -lt $lines.Count - 1) { $term = ' +' } else { $term = ';' }
  [void]$sb.Append("    '" + $escd + "' + LineEnding" + $term + "`r`n")
}
[void]$sb.Append("end;`r`n`r`nend.`r`n")

[IO.File]::WriteAllText('source\tyControls.DefaultTheme.pas', $sb.ToString(), $enc)
Write-Output ("Regenerated DefaultTheme.pas from light.tycss (" + $lines.Count + " content lines)")
