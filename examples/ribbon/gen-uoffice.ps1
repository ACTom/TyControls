$src = 'D:\Projects\ty-controls\themes\office.tycss'
$out = 'D:\Projects\ty-controls\examples\ribbon\uoffice.pas'
$text = [System.IO.File]::ReadAllText($src, [System.Text.Encoding]::UTF8)
$lines = $text -split "`r?`n"
# drop a single trailing empty line from a final newline
if ($lines.Count -gt 0 -and $lines[$lines.Count-1] -eq '') { $lines = $lines[0..($lines.Count-2)] }

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('unit uoffice;')
[void]$sb.AppendLine('{ Office skin compiled INTO the ribbon example, so it can default to Office with no themes/')
[void]$sb.AppendLine('  folder present. GENERATED from themes/office.tycss by gen-uoffice.ps1 -- do not edit by hand. }')
[void]$sb.AppendLine('{$mode objfpc}{$H+}')
[void]$sb.AppendLine('interface')
[void]$sb.AppendLine('function OfficeThemeCss: string;')
[void]$sb.AppendLine('implementation')
[void]$sb.AppendLine('function OfficeThemeCss: string;')
[void]$sb.AppendLine('begin')
[void]$sb.AppendLine('  Result :=')
for ($i = 0; $i -lt $lines.Count; $i++) {
  $ln = $lines[$i].Replace("'", "''")
  if ($i -lt $lines.Count - 1) { $term = ' + LineEnding +' } else { $term = ';' }
  [void]$sb.AppendLine("    '" + $ln + "'" + $term)
}
[void]$sb.AppendLine('end;')
[void]$sb.AppendLine('end.')

$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($out, $sb.ToString(), $enc)
"wrote $out ($($lines.Count) lines)"
