#     pwsh scripts/richedit-wordcheck/check-grid.ps1 -Dir <folder> -Names <file names without .rtf> [-Table <n>]
# Opens the given RTF files READ-ONLY in our own invisible Word and writes, per file, the grid
# of each table as Word's own XML says it (<name>.wordgrid.txt): the grid's column widths in
# twips, then one line per row with each cell as
#     gridSpan / vMerge (restart = a vertical merge begins, cont = continues, - = none) / width twips / text
# Where a <name>.grid.txt in that form stands beside the file (the model's listing), the lines
# that differ are printed; widths may differ by two twips (Word rounds its own way). -Table
# picks one table of the document (1-based); 0, the default, takes them all in order.
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
    # the outermost table of the range only (a nested table is another table's business)
    $tbl = $x.SelectSingleNode('//w:body/w:tbl', $ns)
    if ($tbl -eq $null) { $L.Add('no table'); return $L }
    $cols = @(); foreach ($g in $tbl.SelectNodes('w:tblGrid/w:gridCol', $ns)) { $cols += $g.GetAttribute('w', $ns.LookupNamespace('w')) }
    $L.Add('grid ' + ($cols -join ' '))
    foreach ($tr in $tbl.SelectNodes('w:tr', $ns)) {
        $cells = @()
        foreach ($tc in $tr.SelectNodes('w:tc', $ns)) {
            $span = 1; $n = $tc.SelectSingleNode('w:tcPr/w:gridSpan', $ns)
            if ($n -ne $null) { $span = [int]$n.GetAttribute('val', $ns.LookupNamespace('w')) }
            $vm = '-'; $n = $tc.SelectSingleNode('w:tcPr/w:vMerge', $ns)
            if ($n -ne $null) { $v = $n.GetAttribute('val', $ns.LookupNamespace('w')); if ($v -eq 'restart') { $vm = 'restart' } else { $vm = 'cont' } }
            $w = ''; $n = $tc.SelectSingleNode('w:tcPr/w:tcW', $ns)
            if ($n -ne $null) { $w = $n.GetAttribute('w', $ns.LookupNamespace('w')) }
            $t = ''; foreach ($tn in $tc.SelectNodes('w:p//w:t', $ns)) { $t += $tn.InnerText }
            $cells += "$span/$vm/$w/$t"
        }
        $L.Add('row ' + ($cells -join '  '))
    }
    return $L
}

function Same-Line([string]$a, [string]$b) {
    if ($a -ceq $b) { return $true }
    $pa = $a -split '\s+'; $pb = $b -split '\s+'
    if ($pa.Count -ne $pb.Count -or $pa[0] -cne $pb[0]) { return $false }
    for ($i = 1; $i -lt $pa.Count; $i++) {
        if ($pa[$i] -ceq $pb[$i]) { continue }
        if ($pa[0] -eq 'grid') {
            if ([Math]::Abs([int]$pa[$i] - [int]$pb[$i]) -gt 2) { return $false }
        } else {
            $ca = $pa[$i] -split '/', 4; $cb = $pb[$i] -split '/', 4
            if ($ca.Count -ne 4 -or $cb.Count -ne 4) { return $false }
            if ($ca[0] -cne $cb[0] -or $ca[1] -cne $cb[1] -or $ca[3] -cne $cb[3]) { return $false }
            if ([Math]::Abs([int]$ca[2] - [int]$cb[2]) -gt 2) { return $false }
        }
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
            $n = [Math]::Max($want.Count, $got.Count); $bad = 0
            for ($i = 0; $i -lt $n; $i++) {
                $a = if ($i -lt $want.Count) { $want[$i].TrimEnd() } else { '<none>' }
                $b = if ($i -lt $got.Count) { $got[$i].TrimEnd() } else { '<none>' }
                if (-not (Same-Line $a $b)) { $bad++; "  model: $a"; "  word : $b" }
            }
            "== $name : $n lines, $bad differ"
        } catch {
            "== $name : FATAL $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
        }
    }
} catch {
    "FATAL $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
} finally {
    Stop-OurWord
}
