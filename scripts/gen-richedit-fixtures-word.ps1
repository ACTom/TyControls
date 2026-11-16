# Makes tests/fixtures/rtf/word-*.rtf: four documents built through Word's object model (Word
# stays invisible) and saved by Word as RTF. Needs Word; the files in the repository were made
# with Word 16.0.17932 (word-zh, word-unknown, word-table-merged on 2026-11-11, word-list on
# 2026-11-16) -- do not rerun it to "refresh" them, the bytes would change (revision ids,
# dates). tests/fixtures/rtf/README.md says what each file is for.
#
#     pwsh scripts/gen-richedit-fixtures-word.ps1 -Out <folder> [-Only zh,unknown,table,list] [-CopyTable]
#
# -Only makes just the files named (all four by default). -CopyTable also leaves a 2 x 3 table
# on the clipboard (it was pasted into WordPad for wp-zh-table.rtf).
param([Parameter(Mandatory)][string]$Out, [switch]$CopyTable,
  [ValidateSet('zh', 'unknown', 'table', 'list')][string[]]$Only = @('zh', 'unknown', 'table', 'list'))
$ErrorActionPreference = 'Stop'
$wdFormatRTF = 6
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
"Word version: $($word.Version) build $($word.Build)"
$userName = $word.UserName
$userInitials = $word.UserInitials
try {
  # ---------------------------------------------------------------- word-zh.rtf
  if ($Only -contains 'zh') {
  $doc = $word.Documents.Add()
  $sel = $word.Selection
  $sel.Font.NameAscii = 'Calibri'; $sel.Font.NameOther = 'Calibri'; $sel.Font.NameFarEast = '宋体'
  $sel.TypeText('TyControls 的富文本控件 4.0，用 Word 保存。'); $sel.TypeParagraph()
  $sel.TypeText('café 和 naïve 里的重音字母，还有全角标点：“引号”、《书名号》。'); $sel.TypeParagraph()
  $sel.Font.NameFarEast = '黑体'
  $sel.TypeText('这一段的中文用黑体，English stays Calibri。'); $sel.TypeParagraph()
  $sel.Font.NameFarEast = '宋体'
  $sel.TypeText('表情 ' + [char]::ConvertFromUtf32(0x1F600) + ' 和生僻字 龘 不一定在代码页里。'); $sel.TypeParagraph()
  $sel.Font.Bold = 1
  $sel.TypeText('粗体的中文 and bold English')
  $sel.Font.Bold = 0
  $sel.TypeText('，后面是普通的。')
  $doc.SaveAs2([ref]"$Out\word-zh.rtf", [ref]$wdFormatRTF)
  $doc.Close([ref]0)
  }

  # ---------------------------------------------------------------- word-unknown.rtf
  if ($Only -contains 'unknown') {
  $doc = $word.Documents.Add()
  $sel = $word.Selection
  $sel.Style = $doc.Styles.Item(-2)            # wdStyleHeading1
  $sel.TypeText('不认识的内容'); $sel.TypeParagraph()
  $sel.TypeText('这里有一个')
  [void]$doc.Hyperlinks.Add($sel.Range, 'https://example.com/', [Type]::Missing, [Type]::Missing, '链接')
  $sel.EndKey(6) | Out-Null                     # wdStory
  $sel.TypeText('。'); $sel.TypeParagraph()
  $sel.TypeText('修订：原来的字。'); $sel.TypeParagraph()
  $sel.TypeText('批注在这几个字上。'); $sel.TypeParagraph()
  $sel.TypeText('脚注在这里。'); $sel.TypeParagraph()
  $sel.TypeText('公式：'); $sel.TypeParagraph()
  $sel.TypeText('书签里的字'); $sel.TypeParagraph()
  $sel.TypeText('最后一段。')
  # tracked changes in paragraph 3: insert two characters, delete two
  $doc.TrackRevisions = $true
  $p = $doc.Paragraphs.Item(3).Range
  $r = $doc.Range($p.Start + 3, $p.Start + 3); $r.InsertAfter('新加的字')
  $p = $doc.Paragraphs.Item(3).Range
  $r = $doc.Range($p.Start + 7, $p.Start + 9); $r.Delete() | Out-Null
  $doc.TrackRevisions = $false
  # a comment on four characters of paragraph 4
  $p = $doc.Paragraphs.Item(4).Range
  [void]$doc.Comments.Add($doc.Range($p.Start + 3, $p.Start + 7), '批注的内容')
  # a footnote after the fifth character of paragraph 5
  $p = $doc.Paragraphs.Item(5).Range
  [void]$doc.Footnotes.Add($doc.Range($p.Start + 5, $p.Start + 5), [Type]::Missing, '脚注的内容')
  # a bookmark around paragraph 7's text (before the formula: a Range object moves with edits)
  $p = $doc.Paragraphs.Item(7).Range
  [void]$doc.Bookmarks.Add('mark1', $doc.Range($p.Start, $p.End - 1))
  # a formula at the end of paragraph 6
  $at = $doc.Paragraphs.Item(6).Range.End - 1
  $doc.Range($at, $at).InsertAfter('E=mc^2')
  $m = $doc.OMaths.Add($doc.Range($at, $at + 6)); $doc.OMaths.BuildUp()
  $doc.SaveAs2([ref]"$Out\word-unknown.rtf", [ref]$wdFormatRTF)
  $doc.Close([ref]0)
  }

  # ---------------------------------------------------------------- word-table-merged.rtf
  if ($Only -contains 'table') {
  $doc = $word.Documents.Add()
  $sel = $word.Selection
  $sel.TypeText('表格前'); $sel.TypeParagraph(); $sel.TypeParagraph()
  $sel.TypeText('表格后')
  $t = $doc.Tables.Add($doc.Paragraphs.Item(2).Range, 3, 3)
  $t.Borders.Enable = 1
  $names = @(@('跨两列', 'B', 'C'), @('跨两行', 'E', 'F'), @('', 'G', ''))
  for ($r = 1; $r -le 3; $r++) { for ($c = 1; $c -le 3; $c++) { $t.Cell($r, $c).Range.Text = $names[$r - 1][$c - 1] } }
  $t.Cell(1, 2).Range.Text = ''
  $t.Cell(1, 1).Merge($t.Cell(1, 2))
  $t.Cell(2, 1).Merge($t.Cell(3, 1))
  $inner = $doc.Tables.Add($t.Cell(3, 3).Range, 1, 2)
  $inner.Borders.Enable = 1
  $inner.Cell(1, 1).Range.Text = '内一'
  $inner.Cell(1, 2).Range.Text = '内二'
  $doc.SaveAs2([ref]"$Out\word-table-merged.rtf", [ref]$wdFormatRTF)
  $doc.Close([ref]0)
  }

  # ---------------------------------------------------------------- word-list.rtf
  # Numbered headings (Heading 1: "1.", Heading 2: "2.1.": one outline-numbered list whose
  # items are interrupted by body paragraphs) and a bulleted list. The text goes in through
  # ranges, not typed, so that Word's typing rules (a line typed like an item becomes a list)
  # play no part. Beside the file: word-list.expected.txt (each paragraph's text) and
  # word-list.markers.txt (the marker Word shows before it, Range.ListFormat.ListString; an
  # empty line for a paragraph with none).
  if ($Only -contains 'list') {
  $doc = $word.Documents.Add()
  $h1 = $doc.Styles.Item(-2)                     # wdStyleHeading1
  $h2 = $doc.Styles.Item(-3)                     # wdStyleHeading2
  $body = $doc.Styles.Item(-1)                   # wdStyleNormal
  # level: 0 none, 1 or 2 the outline list, -1 a bullet
  $paras = @(
    @($h1, 1, '概述 Overview'),
    @($body, 0, '这一段是正文，不是列表项。This body paragraph is no list item.'),
    @($h1, 1, '安装 Installation'),
    @($h2, 2, '下载 Download'),
    @($body, 0, '正文打断了第二级。Body text between two second-level headings.'),
    @($h2, 2, '解压 Unpack'),
    @($h1, 1, '使用 Usage'),
    @($body, 0, '要点如下：'),
    @($body, -1, '苹果 apples'),
    @($body, -1, '橘子 oranges'),
    @($body, 0, '最后一段。The end.'))
  $doc.Content.Text = (($paras | ForEach-Object { $_[2] }) -join "`r")
  $doc.Content.Font.NameAscii = 'Calibri'; $doc.Content.Font.NameOther = 'Calibri'
  $doc.Content.Font.NameFarEast = '宋体'
  $lt = $doc.ListTemplates.Add($true)
  $lv = $lt.ListLevels.Item(1)
  $lv.NumberFormat = '%1.'; $lv.NumberStyle = 0; $lv.StartAt = 1; $lv.TrailingCharacter = 0
  $lv = $lt.ListLevels.Item(2)
  $lv.NumberFormat = '%1.%2.'; $lv.NumberStyle = 0; $lv.StartAt = 1; $lv.TrailingCharacter = 0
  $first = $true
  for ($k = 0; $k -lt $paras.Count; $k++) {
    $pr = $doc.Paragraphs.Item($k + 1).Range
    $pr.Style = $paras[$k][0]
    $level = $paras[$k][1]
    if ($level -gt 0) {
      # wdListApplyToWholeList 0, wdWord10ListBehavior 2; every item after the first continues the list
      $pr.ListFormat.ApplyListTemplateWithLevel($lt, (-not $first), 0, 2, $level)
      $first = $false
    }
  }
  $r = $doc.Range($doc.Paragraphs.Item(9).Range.Start, $doc.Paragraphs.Item(10).Range.End)
  $r.ListFormat.ApplyBulletDefault()
  $texts = @(); $marks = @()
  for ($k = 1; $k -le $doc.Paragraphs.Count; $k++) {
    $pr = $doc.Paragraphs.Item($k).Range
    $texts += $pr.Text.TrimEnd([char]13)
    $marks += [string]$pr.ListFormat.ListString
  }
  $doc.SaveAs2([ref]"$Out\word-list.rtf", [ref]$wdFormatRTF)
  $doc.Close([ref]0)
  $utf8 = New-Object Text.UTF8Encoding $false
  [IO.File]::WriteAllText("$Out\word-list.expected.txt", (($texts | ForEach-Object { "$_`n" }) -join ''), $utf8)
  [IO.File]::WriteAllText("$Out\word-list.markers.txt", (($marks | ForEach-Object { "$_`n" }) -join ''), $utf8)
  }

  if ($CopyTable) {
    # a simple 2 x 3 table left on the clipboard, for WordPad to paste
    $doc = $word.Documents.Add()
    $t = $doc.Tables.Add($doc.Range(0, 0), 2, 3)
    $t.Borders.Enable = 1
    $cells = @(@('品名', '数量', '单价'), @('铅笔 pencil', '12', '1.50'))
    for ($r = 1; $r -le 2; $r++) { for ($c = 1; $c -le 3; $c++) { $t.Cell($r, $c).Range.Text = $cells[$r - 1][$c - 1] } }
    $t.Range.Copy()
    Start-Sleep -Milliseconds 500
    $doc.Close([ref]0)
  }
}
finally {
  $word.Quit([ref]0)
  [void][Runtime.InteropServices.Marshal]::ReleaseComObject($word)
}
# Word writes the name and initials of whoever runs it (Word's own user name) as the author, the
# last editor, the reviser and the comment's author. These files are public: that name becomes
# TyControls / TY, in those places only; no other byte changes.
$latin1 = [Text.Encoding]::GetEncoding(28591)
function Rtf([string]$s) {   # the string as Word writes it: ASCII as it is, the rest as GBK \'xx
  -join ($s.ToCharArray() | ForEach-Object {
    if ([int]$_ -lt 128) { [string]$_ } else { -join ([Text.Encoding]::GetEncoding(936).GetBytes([string]$_) | ForEach-Object { "\'{0:x2}" -f $_ }) } })
}
$n = Rtf $userName; $i = Rtf $userInitials
foreach ($f in Get-ChildItem "$Out\word-*.rtf") {
  $t = $latin1.GetString([IO.File]::ReadAllBytes($f.FullName))
  $before = $t.Length
  $t = $t.Replace("{\author $n}", '{\author TyControls}').Replace("{\operator $n}", '{\operator TyControls}')
  $t = $t.Replace("{\*\revtbl {Unknown;}{$n;}}", '{\*\revtbl {Unknown;}{TyControls;}}')
  $t = $t.Replace("{\*\atnauthor $n}", '{\*\atnauthor TyControls}').Replace("{\*\atnid $i}", '{\*\atnid TY}')
  [IO.File]::WriteAllBytes($f.FullName, $latin1.GetBytes($t))
  '{0,-28} {1,8} bytes ({2:+#;-#;0} from the name)' -f $f.Name, $t.Length, ($t.Length - $before)
}
