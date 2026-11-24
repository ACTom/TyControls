#     pwsh scripts/richedit-wordcheck/measure-page-colour.ps1 -OutDir <folder>
#     (then read <folder>/out3/pagecolor.rtf: the background group, \cbpat, \sl \slmult)
# 
# How does Word write a page (document) background colour and a paragraph's shading in RTF?
# Our own invisible Word, a new document of our own, saved only into the scratch folder,
# NO Word setting written (only properties of our own document).
param([Parameter(Mandatory)][string]$OutDir)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$S = (Resolve-Path $OutDir).Path
. "$PSScriptRoot\wordlib.ps1"
New-Item -ItemType Directory -Force -Path "$S\out3" | Out-Null
try {
  $word = Start-OurWord -HeartFile "$S\heart.txt"
  "our Word pid $($script:WordPid), version $($word.Version)"
  $doc = $word.Documents.Add()
  $doc.Content.Text = "页面有背景色`r这一段有底色 shaded`r这一段 3 倍行距`r这一段 1.08 倍行距`r末尾"
  $doc.Background.Fill.Visible = -1
  $doc.Background.Fill.ForeColor.RGB = 0x00C0FFC0      # BGR: light green (R=C0 G=FF B=C0)
  $doc.Background.Fill.Solid()
  $doc.Paragraphs.Item(2).Shading.BackgroundPatternColor = 0x0000FFFF   # yellow
  $doc.Paragraphs.Item(3).Format.LineSpacingRule = 5; $doc.Paragraphs.Item(3).Format.LineSpacing = 36
  $doc.Paragraphs.Item(4).Format.LineSpacingRule = 5; $doc.Paragraphs.Item(4).Format.LineSpacing = 12.96
  $path = "$S\out3\pagecolor.rtf"
  $doc.SaveAs2([ref]$path, [ref]6)
  $doc.Close([ref]0)
  "saved"
} catch {
  "FATAL $($_.Exception.Message) at $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
} finally {
  Stop-OurWord
}
