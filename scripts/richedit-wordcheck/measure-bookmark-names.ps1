#     pwsh scripts/richedit-wordcheck/measure-bookmark-names.ps1 -OutDir <folder>
#     (then read <folder>/out4/bookmark.rtf: \bkmkstart, \bkmkend, the HYPERLINK instruction)
# 
# How does Word write a bookmark with a Chinese name, and a link to it, in RTF?
# Our own invisible Word, a new document of our own, saved only into the scratch folder,
# NO Word setting written.
param([Parameter(Mandatory)][string]$OutDir)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$S = (Resolve-Path $OutDir).Path
. "$PSScriptRoot\wordlib.ps1"
New-Item -ItemType Directory -Force -Path "$S\out4" | Out-Null
try {
  $word = Start-OurWord -HeartFile "$S\heart.txt"
  "our Word pid $($script:WordPid), version $($word.Version)"
  $doc = $word.Documents.Add()
  $doc.Content.Text = "第一段`r第二节的标题`r链接到："
  $p = $doc.Paragraphs.Item(2).Range
  [void]$doc.Bookmarks.Add('第二节', $doc.Range($p.Start, $p.End - 1))
  $p = $doc.Paragraphs.Item(1).Range
  [void]$doc.Bookmarks.Add('Mark_A1', $doc.Range($p.Start, $p.Start))
  $p = $doc.Paragraphs.Item(3).Range
  $r = $doc.Range($p.End - 1, $p.End - 1)
  [void]$doc.Hyperlinks.Add($r, '', '第二节', [Type]::Missing, '去第二节')
  $names = @(); foreach ($b in $doc.Bookmarks) { $names += $b.Name }
  "bookmarks: $($names -join ', ')"
  $path = "$S\out4\bookmark.rtf"
  $doc.SaveAs2([ref]$path, [ref]6)
  $doc.Close([ref]0)
  "saved"
} catch {
  "FATAL $($_.Exception.Message) at $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
} finally {
  Stop-OurWord
}
