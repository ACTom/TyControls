#     pwsh scripts/richedit-wordcheck/check-content.ps1 -Dir <folder of make-content> [-Names built,edited,...]
# Opens each produced file READ-ONLY in our own invisible Word, writes what Word reads
# (<name>.dump.txt) and checks the lines of <name>.expect.txt against it. ASCII only.
# No Word setting is written: only documents we produced are opened, nothing is saved.
param([Parameter(Mandatory)][string]$Dir, [string[]]$Names = @('built', 'edited', 'letters', 'wordtoc-edited'))
. "$PSScriptRoot\wordlib.ps1"
$Out = (Resolve-Path $Dir).Path
$utf8 = New-Object Text.UTF8Encoding($false)

function N([double]$v) { return ([Math]::Round($v, 2)).ToString([Globalization.CultureInfo]::InvariantCulture) }
function Clean([string]$s) {
    if ($s -eq $null) { return '' }
    $sb = New-Object Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) { if ([int]$ch -ge 32) { [void]$sb.Append($ch) } elseif ([int]$ch -eq 9) { [void]$sb.Append("`t") } }
    return $sb.ToString()
}

function Dump-Doc($doc) {
    $L = New-Object Collections.Generic.List[string]
    $ps = $doc.PageSetup
    $L.Add("page=$(N $ps.PageWidth)|$(N $ps.LeftMargin)|$(N $ps.RightMargin)")
    try {
        if ($doc.Background.Fill.Visible -ne 0) { $L.Add("background=$($doc.Background.Fill.ForeColor.RGB)") } else { $L.Add('background=none') }
    } catch { $L.Add("background=error $($_.Exception.Message)") }

    $L.Add("links=$($doc.Hyperlinks.Count)")
    foreach ($h in $doc.Hyperlinks) {
        $t = ''; try { $t = $h.TextToDisplay } catch { $t = '<no text>' }
        $L.Add("link=$($h.Address)|$($h.SubAddress)|$(Clean $t)")
        try { $L.Add("linkfont=$(Clean $t)|color=$($h.Range.Font.Color)|underline=$($h.Range.Font.Underline)") } catch {}
    }
    $doc.Bookmarks.ShowHidden = $false
    $L.Add("bookmarks=$($doc.Bookmarks.Count)")
    foreach ($b in $doc.Bookmarks) { $L.Add("bookmark[$($b.Name)]=$(Clean $b.Range.Text)") }
    $doc.Bookmarks.ShowHidden = $true
    $L.Add("bookmarks_with_hidden=$($doc.Bookmarks.Count)")
    $doc.Bookmarks.ShowHidden = $false

    $i = 0
    foreach ($p in $doc.Paragraphs) {
        $i++
        if ($i -gt 400) { $L.Add('paragraphs cut at 400'); break }
        $r = $p.Range
        $t = Clean $r.Text
        if ($t.Length -gt 60) { $t = $t.Substring(0, 60) }
        $f = $p.Format
        $shade = $p.Shading.BackgroundPatternColor
        if ($shade -eq -16777216) { $shade = 'auto' }
        $size = $r.Font.Size; if ($size -gt 9000) { $size = 'mixed' } else { $size = N $size }
        $bold = $r.Font.Bold; if ($bold -eq -1) { $bold = 1 } elseif ($bold -ne 0) { $bold = 'mixed' }
        $L.Add("para=$t|rule=$($f.LineSpacingRule)|ls=$(N $f.LineSpacing)|before=$(N $f.SpaceBefore)|after=$(N $f.SpaceAfter)|shade=$shade|align=$($f.Alignment)|size=$size|bold=$bold|font=$($r.Font.Name)|intable=$($r.Information(12))")
        if ($f.LeftIndent -ne 0 -or $f.FirstLineIndent -ne 0 -or $f.RightIndent -ne 0) {
            $L.Add("indent=$t|$(N $f.LeftIndent)|$(N $f.FirstLineIndent)|$(N $f.RightIndent)")
        }
        $lf = $r.ListFormat
        if ($lf.ListType -ne 0) {
            $L.Add("list=$t|level=$($lf.ListLevelNumber)|string=$(Clean $lf.ListString)|type=$($lf.ListType)")
        }
        if ($f.TabStops.Count -gt 0) {
            $ts = @(); foreach ($s in $f.TabStops) { if ($s.CustomTab) { $ts += "$(N $s.Position):$($s.Alignment):$($s.Leader)" } }
            if ($ts.Count -gt 0) {
                $head = $t; $k = $head.IndexOf("`t"); if ($k -ge 0) { $head = $head.Substring(0, $k) }
                $L.Add("tabs=$head|$($ts -join ',')")
            }
        }
        if ($t -like 'red *') {
            foreach ($w in $r.Words) {
                $wf = $w.Font
                $L.Add("run=$(Clean $w.Text)|$($wf.Color)|hl=$($w.HighlightColorIndex)|super=$($wf.Superscript)|sub=$($wf.Subscript)|strike=$($wf.StrikeThrough)")
            }
        }
    }
    $ti = 0
    foreach ($tb in $doc.Tables) {
        $ti++
        $ws = @(); foreach ($c in $tb.Rows.Item(1).Cells) { $ws += (N $c.Width) }
        $L.Add("table=$ti|rows=$($tb.Rows.Count)|cols=$($tb.Columns.Count)|w=$($ws -join ',')")
        foreach ($c in $tb.Range.Cells) { $L.Add("cell=$($c.RowIndex),$($c.ColumnIndex)|$(Clean $c.Range.Text)") }
    }
    return $L
}

function Check([string]$name, $dump) {
    $res = New-Object Collections.Generic.List[string]
    $exp = [IO.File]::ReadAllLines("$Out\$name.expect.txt", $utf8)
    $bad = 0
    foreach ($e in $exp) {
        if ($e.Trim() -eq '') { continue }
        $ok = $false
        if ($e.StartsWith('nobookmark=')) {
            $n = $e.Substring(11); $ok = -not ($dump | Where-Object { $_.StartsWith("bookmark[$n]") })
        } elseif ($e.StartsWith('nolink=')) {
            $n = $e.Substring(7); $ok = -not ($dump | Where-Object { $_.StartsWith("link=$n|") })
        } elseif ($e -match '^(links|bookmarks)=\d+$') {
            $ok = [bool]($dump | Where-Object { $_ -ceq $e })
        } else {
            $ok = [bool]($dump | Where-Object { $_.StartsWith($e, [StringComparison]::Ordinal) })
        }
        if ($ok) { $res.Add("PASS $e") } else { $res.Add("FAIL $e"); $bad++ }
    }
    $res.Insert(0, "== $name : $($exp.Count) expectations, $bad failed")
    return $res
}

$all = New-Object Collections.Generic.List[string]
try {
    $word = Start-OurWord -HeartFile "$Out\heart.txt"
    [IO.File]::WriteAllText("$Out\wordpid.txt", [string]$script:WordPid)
    "our Word pid $($script:WordPid), version $($word.Version)"
    foreach ($name in $Names) {
        $path = "$Out\$name.rtf"
        try {
            $doc = $word.Documents.Open([ref]$path, [ref]$false, [ref]$true, [ref]$false)
            $dump = Dump-Doc $doc
            $doc.Close([ref]0)
            [IO.File]::WriteAllLines("$Out\$name.dump.txt", $dump, $utf8)
            if (Test-Path "$Out\$name.expect.txt") { $all.AddRange([string[]](Check $name $dump)) } else { $all.Add("== $name : dumped") }
        } catch {
            $all.Add("== $name : FATAL $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)")
        }
    }
} catch {
    $all.Add("FATAL $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)")
} finally {
    Stop-OurWord
}
[IO.File]::WriteAllLines("$Out\results.txt", $all, $utf8)
$all | Where-Object { $_ -notlike 'PASS *' }
