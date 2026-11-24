#     pwsh scripts/richedit-wordcheck/check-tables.ps1 -Dir <folder> -Names <file names without .rtf>
# Opens the given RTF files READ-ONLY in our own invisible Word and lists, per table, what
# Word reads of its alignment, rows and cells, in the form of the model's own listing
# (<name>.txt beside each file), then says which lines differ. ASCII only. No Word setting is
# written; nothing is saved.
param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][string[]]$Names)
$Dir = (Resolve-Path $Dir).Path
. "$PSScriptRoot\wordlib.ps1"
$utf8 = New-Object Text.UTF8Encoding($false)

function Tw([double]$pt) { return [int][Math]::Round($pt * 20) }
function Rgb([int]$c) {
    if ($c -eq -16777216) { return 'automatic' }
    return "RGB($($c -band 255),$(($c -shr 8) -band 255),$(($c -shr 16) -band 255))"
}
function Style([int]$s) {
    switch ($s) { 0 { 'none' } 1 { 'single' } 2 { 'dotted' } 3 { 'dashed' } 4 { 'dashed-large' } 7 { 'double' } default { "style$s" } }
}
function Side($b) {
    if ($b.LineStyle -eq 0) { return 'none' }
    return "$(Style $b.LineStyle) $($b.LineWidth)/8 pt $(Rgb $b.Color)"
}

function List-Doc($doc) {
    $L = New-Object Collections.Generic.List[string]
    $ti = 0
    foreach ($t in $doc.Tables) {
        $ti++
        $al = switch ($t.Rows.Alignment) { 0 { 'left' } 1 { 'center' } 2 { 'right' } default { "align$($t.Rows.Alignment)" } }
        $L.Add("table ${ti}: alignment $al, indent $(Tw $t.Rows.LeftIndent) twips")
        $ri = 0
        foreach ($r in $t.Rows) {
            $h = switch ($r.HeightRule) { 0 { 'automatic' } 1 { "at least $(Tw $r.Height) twips" } 2 { "exactly $(Tw $r.Height) twips" } }
            $L.Add("  row ${ri}: height $h")
            $ci = 0
            foreach ($c in $r.Cells) {
                $sh = $c.Shading.BackgroundPatternColor
                if ($sh -eq -16777216) { $sh = 'none' } else { $sh = Rgb $sh }
                $va = switch ($c.VerticalAlignment) { 0 { 'top' } 1 { 'center' } 3 { 'bottom' } default { "v$($c.VerticalAlignment)" } }
                $L.Add("    cell $ri,${ci}: width $(Tw $c.Width) twips; shading $sh; vertical alignment $va")
                $L.Add("      borders: left $(Side $c.Borders.Item(-2)); top $(Side $c.Borders.Item(-1)); right $(Side $c.Borders.Item(-4)); bottom $(Side $c.Borders.Item(-3));")
                $L.Add("      padding (twips): left $(Tw $c.LeftPadding), top $(Tw $c.TopPadding), right $(Tw $c.RightPadding), bottom $(Tw $c.BottomPadding)")
                $ci++
            }
            $ri++
        }
    }
    return $L
}

try {
    $word = Start-OurWord -HeartFile "$Dir\heart.txt"
    [IO.File]::WriteAllText("$Dir\wordpid.txt", [string]$script:WordPid)
    "our Word pid $($script:WordPid), version $($word.Version)"
    foreach ($name in $Names) {
        $path = "$Dir\$name.rtf"
        try {
            $doc = $word.Documents.Open([ref]$path, [ref]$false, [ref]$true, [ref]$false)
            $got = List-Doc $doc
            $doc.Close([ref]0)
            [IO.File]::WriteAllLines("$Dir\$name.word.txt", $got, $utf8)
            if (-not (Test-Path "$Dir\$name.txt")) { "== $name : listed, $($got.Count) lines"; continue }
            $want = [IO.File]::ReadAllLines("$Dir\$name.txt", $utf8)
            $n = [Math]::Max($want.Count, $got.Count); $bad = 0
            for ($i = 0; $i -lt $n; $i++) {
                $a = if ($i -lt $want.Count) { $want[$i].TrimEnd() } else { '<none>' }
                $b = if ($i -lt $got.Count) { $got[$i].TrimEnd() } else { '<none>' }
                if ($a -cne $b) { $bad++; "  model: $a"; "  word : $b" }
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
