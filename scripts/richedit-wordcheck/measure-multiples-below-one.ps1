#     pwsh scripts/richedit-wordcheck/measure-multiples-below-one.ps1 -OutDir <folder>
#     python scripts/richedit-wordcheck/emf-positions.py <folder>/out5/page.emf
# 
# Where does Word put a line's text for each kind of line spacing and for common fonts?
# Our own invisible Word, a new document of our own, nothing saved outside the scratch folder,
# NO Word setting written (only properties of our own document).
param([Parameter(Mandatory)][string]$OutDir)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$S = (Resolve-Path $OutDir).Path
. "$PSScriptRoot\wordlib.ps1"
New-Item -ItemType Directory -Force -Path "$S\out5" | Out-Null
$long = '长' * 120
try {
  $word = Start-OurWord -HeartFile "$S\heart.txt"
  "our Word pid $($script:WordPid), version $($word.Version)"
  $doc = $word.Documents.Add()
  $doc.PageSetup.LayoutMode = 0
  # font, far-east?, size, rule (0 single 1 one-and-a-half 2 double 3 at least 4 exactly 5 multiple), spacing in points (rules 3-5), text
  $cases = @(
    @('宋体', 1, 12, 0, 0, 'R宋体单倍'),
    @('宋体', 1, 12, 5, 6, 'A宋体0.5倍gy'),
    @('宋体', 1, 12, 5, 9.6, 'B宋体0.8倍gy'),
    @('Arial', 0, 12, 0, 0, 'S Arial single gy'),
    @('Arial', 0, 12, 5, 6, 'C Arial 0.5 gy'),
    @('Arial', 0, 12, 5, 9.6, 'D Arial 0.8 gy'),
    @('宋体', 1, 12, 5, 10.8, 'E宋体0.9倍gy'),
    @('宋体', 1, 12, 5, 6, ('F' + $long))
  )
  $text = ''
  foreach ($c in $cases) { $text += $c[5] + "`r" + 'X' + "`r" }
  $text += '末尾'
  $doc.Content.Text = $text
  Beat
  for ($k = 0; $k -lt $cases.Count; $k++) {
    $c = $cases[$k]
    $p = $doc.Paragraphs.Item($k * 2 + 1)
    $r = $p.Range
    $r.Font.Name = [string]$c[0]
    if ($c[1] -eq 1) { $r.Font.NameFarEast = [string]$c[0] }
    $r.Font.Size = [single]$c[2]
    $p.Format.SpaceBefore = 0; $p.Format.SpaceAfter = 0
    $p.Format.LineSpacingRule = [int]$c[3]
    if ([int]$c[3] -ge 3) { $p.Format.LineSpacing = [single]$c[4] }
    $p.Format.DisableLineHeightGrid = -1
    $x = $doc.Paragraphs.Item($k * 2 + 2)
    $x.Range.Font.Name = '宋体'; $x.Range.Font.NameFarEast = '宋体'; $x.Range.Font.Size = 12
    $x.Format.LineSpacingRule = 0; $x.Format.SpaceBefore = 0; $x.Format.SpaceAfter = 0
    $x.Format.DisableLineHeightGrid = -1
  }
  Beat
  for ($k = $cases.Count - 1; $k -ge 0; $k--) {
    $pr = $doc.Paragraphs.Item($k * 2 + 2).Range
    $pr.Collapse(1)
    $t = $doc.Tables.Add($pr, 1, 1)
    $t.Borders.Enable = 1
    $t.Cell(1, 1).Range.Text = 'T'
    $t.Cell(1, 1).Range.Font.Name = '宋体'; $t.Cell(1, 1).Range.Font.NameFarEast = '宋体'; $t.Cell(1, 1).Range.Font.Size = 12
    $t.Cell(1, 1).Range.ParagraphFormat.SpaceBefore = 0; $t.Cell(1, 1).Range.ParagraphFormat.SpaceAfter = 0
    $t.Cell(1, 1).Range.ParagraphFormat.LineSpacingRule = 0
  }
  Beat
  $doc.Repaginate()
  $rows = @()
  foreach ($p in $doc.Paragraphs) {
    $r = $p.Range; $r.Collapse(1)
    $rows += ("{0}`t{1}`t{2}`t{3}`t{4}" -f $r.Information(6), $r.Information(12), $p.Format.LineSpacingRule, $p.Format.LineSpacing, (($p.Range.Text -replace "[`r`a]", '')).Substring(0, [Math]::Min(12, ($p.Range.Text -replace "[`r`a]", '').Length)))
  }
  [IO.File]::WriteAllLines("$S\out5\positions.txt", $rows, (New-Object Text.UTF8Encoding $false))
  $bits = $doc.Range().EnhMetaFileBits
  [IO.File]::WriteAllBytes("$S\out5\page.emf", [byte[]]$bits)
  "pages $($doc.ComputeStatistics(2)); emf $($bits.Length) bytes"
  $doc.Close([ref]0)
} catch {
  "FATAL $($_.Exception.Message) at $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim()) k=$k"
} finally {
  Stop-OurWord
}
