#     pwsh scripts/richedit-wordcheck/check-grid.ps1 -Dir <folder> -Names <file names without .rtf> [-Table <n>]
# Opens the given RTF files READ-ONLY in our own invisible Word and writes, per file, the grid
# of each table as Word's own XML says it (<name>.wordgrid.txt): the grid's column widths in
# twips, then one line per row with each cell as
#     gridSpan / vMerge (restart = a vertical merge begins, cont = continues, - = none) / width twips / text
# A cell of an old-style merge across (\clmgf, \clmrg) has "+hfirst" or "+hnext" after its
# vMerge word: Word keeps such a merge as cells of its own and adds grid columns for them.
# Where a <name>.grid.txt in that form stands beside the file (the model's listing), the two
# are compared cell by cell BY THE CELLS' EDGES (left and right in twips from the table's
# left, an old-style merge taken as the one cell it shows), the vertical merge and the text;
# edges may differ by two twips (Word rounds its own way). How either side cuts its grid into
# columns is not compared: only where the cells are. -Table picks one table of the document
# (1-based); 0, the default, takes them all in order.
# ASCII only. No Word setting is written; nothing is saved.
param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][string[]]$Names, [int]$Table = 0)
$Dir = (Resolve-Path $Dir).Path
. "$PSScriptRoot\wordlib.ps1"
$utf8 = New-Object Text.UTF8Encoding($false)

function Grid-Of([string]$xmlText) {
    $L = New-Object Collections.Generic.List[string]
    $x = New-Object Xml.XmlDocument
    $x.LoadXml($xmlText)
    $ns = New-Object Xml.XmlNamespaceManager($x.NameTable)
    $ns.AddNamespace('w', 'http://schemas.openxmlformats.org/wordprocessingml/2006/main')
    $wns = $ns.LookupNamespace('w')
    # the outermost table of the range only (a nested table is another table's business)
    $tbl = $x.SelectSingleNode('//w:body/w:tbl', $ns)
    if ($tbl -eq $null) { $L.Add('no table'); return $L }
    $cols = @(); foreach ($g in $tbl.SelectNodes('w:tblGrid/w:gridCol', $ns)) { $cols += $g.GetAttribute('w', $wns) }
    $L.Add('grid ' + ($cols -join ' '))
    foreach ($tr in $tbl.SelectNodes('w:tr', $ns)) {
        $cells = @()
        foreach ($tc in $tr.SelectNodes('w:tc', $ns)) {
            $span = 1; $n = $tc.SelectSingleNode('w:tcPr/w:gridSpan', $ns)
            if ($n -ne $null) { $span = [int]$n.GetAttribute('val', $wns) }
            $vm = '-'; $n = $tc.SelectSingleNode('w:tcPr/w:vMerge', $ns)
            if ($n -ne $null) { $v = $n.GetAttribute('val', $wns); if ($v -eq 'restart') { $vm = 'restart' } else { $vm = 'cont' } }
            $n = $tc.SelectSingleNode('w:tcPr/w:hMerge', $ns)
            if ($n -ne $null) { $v = $n.GetAttribute('val', $wns); if ($v -eq 'restart') { $vm += '+hfirst' } else { $vm += '+hnext' } }
            $w = ''; $n = $tc.SelectSingleNode('w:tcPr/w:tcW', $ns)
            if ($n -ne $null) { $w = $n.GetAttribute('w', $wns) }
            $t = ''; foreach ($tn in $tc.SelectNodes('w:p//w:t', $ns)) { $t += $tn.InnerText }
            $cells += "$span/$vm/$w/$t"
        }
        $L.Add('row ' + ($cells -join '  '))
    }
    return $L
}

# The listing's rows as cells by their edges: "table" at each grid line, then per row
# "row L-R/vMerge/text ...". An old-style merge across is one cell from its first mark's left
# to its last mark's right.
function Cells-ByEdges($lines) {
    $out = New-Object Collections.Generic.List[string]
    $edges = @(0)
    foreach ($line in $lines) {
        $p = @($line.Trim() -split '\s+')
        if ($p[0] -eq 'grid') {
            $edges = @(0); $x = 0
            for ($i = 1; $i -lt $p.Count; $i++) { $x += [int]$p[$i]; $edges += $x }
            $out.Add('table'); continue
        }
        if ($p[0] -ne 'row') { $out.Add($line); continue }
        $cells = New-Object Collections.Generic.List[object]
        $col = 0
        for ($i = 1; $i -lt $p.Count; $i++) {
            $c = $p[$i] -split '/', 4
            if ($c.Count -ne 4) { $cells.Add(@{ L = -1; R = -1; V = '?'; T = $p[$i] }); continue }
            $span = [int]$c[0]
            $l = if ($col -lt $edges.Count) { $edges[$col] } else { -1 }
            $col += $span
            $r = if ($col -lt $edges.Count) { $edges[$col] } else { -1 }
            $vh = $c[1] -split '\+', 2
            if ($vh.Count -eq 2 -and $vh[1] -eq 'hnext' -and $cells.Count -gt 0) {
                $prev = $cells[$cells.Count - 1]; $prev.R = $r; $prev.T += $c[3]
            } else {
                $cells.Add(@{ L = $l; R = $r; V = $vh[0]; T = $c[3] })
            }
        }
        $out.Add('row ' + (($cells | ForEach-Object { "$($_.L)-$($_.R)/$($_.V)/$($_.T)" }) -join '  '))
    }
    return $out
}

function Same-Line([string]$a, [string]$b) {
    if ($a -ceq $b) { return $true }
    $pa = @($a -split '\s+'); $pb = @($b -split '\s+')
    if ($pa.Count -ne $pb.Count -or $pa[0] -cne $pb[0]) { return $false }
    for ($i = 1; $i -lt $pa.Count; $i++) {
        if ($pa[$i] -ceq $pb[$i]) { continue }
        $ca = $pa[$i] -split '/', 3; $cb = $pb[$i] -split '/', 3
        if ($ca.Count -ne 3 -or $cb.Count -ne 3) { return $false }
        if ($ca[1] -cne $cb[1] -or $ca[2] -cne $cb[2]) { return $false }
        $ea = $ca[0] -split '-'; $eb = $cb[0] -split '-'
        if ($ea.Count -ne 2 -or $eb.Count -ne 2) { return $false }
        if ([Math]::Abs([int]$ea[0] - [int]$eb[0]) -gt 2 -or [Math]::Abs([int]$ea[1] - [int]$eb[1]) -gt 2) { return $false }
    }
    return $true
}

try {
    $word = Start-OurWord -HeartFile "$Dir\heart.txt"
    [IO.File]::WriteAllText("$Dir\wordpid.txt", [string]$script:WordPid)
    "our Word pid $($script:WordPid), version $($word.Version)"
    foreach ($name in $Names) {
        $path = "$Dir\$name.rtf"
        try {
            $doc = $word.Documents.Open([ref]$path, [ref]$false, [ref]$true, [ref]$false)
            $got = New-Object Collections.Generic.List[string]
            $ti = 0
            foreach ($t in $doc.Tables) {
                $ti++
                if ($Table -ne 0 -and $ti -ne $Table) { continue }
                foreach ($l in (Grid-Of $t.Range.WordOpenXML)) { $got.Add($l) }
            }
            $doc.Close([ref]0)
            [IO.File]::WriteAllLines("$Dir\$name.wordgrid.txt", $got, $utf8)
            if (-not (Test-Path "$Dir\$name.grid.txt")) { "== $name : listed, $($got.Count) lines"; continue }
            $want = @([IO.File]::ReadAllLines("$Dir\$name.grid.txt", $utf8) | Where-Object { $_.Trim() -ne '' -and -not $_.StartsWith('#') })
            $wantE = @(Cells-ByEdges $want); $gotE = @(Cells-ByEdges $got)
            $n = [Math]::Max($wantE.Count, $gotE.Count); $bad = 0
            $diff = New-Object Collections.Generic.List[string]
            for ($i = 0; $i -lt $n; $i++) {
                $a = if ($i -lt $wantE.Count) { $wantE[$i].TrimEnd() } else { '<none>' }
                $b = if ($i -lt $gotE.Count) { $gotE[$i].TrimEnd() } else { '<none>' }
                if (-not (Same-Line $a $b)) { $bad++; $diff.Add("  model: $a"); $diff.Add("  word : $b") }
            }
            "== $name : $n lines, $bad differ"
            $diff
        } catch {
            "== $name : FATAL $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
        }
    }
} catch {
    "FATAL $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
} finally {
    Stop-OurWord
}
