#     pwsh scripts/richedit-wordcheck/check-lists.ps1 -Dir <folder> -Names <file names without .rtf>
# Opens the given RTF files READ-ONLY in our own invisible Word and compares, per list item,
# the marker Word shows with the marker the control draws (<name>.markers.txt beside each
# file: text TAB marker). ASCII only. No Word setting is written; nothing is saved.
param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][string[]]$Names)
$Dir = (Resolve-Path $Dir).Path
. "$PSScriptRoot\wordlib.ps1"
$utf8 = New-Object Text.UTF8Encoding($false)
function Codes([string]$s) { if ($s -eq $null) { return '' }; return (($s.ToCharArray() | ForEach-Object { 'U+' + ([int]$_).ToString('X4') }) -join ' ') }
try {
    $word = Start-OurWord -HeartFile "$Dir\heart.txt"
    [IO.File]::WriteAllText("$Dir\wordpid.txt", [string]$script:WordPid)
    "our Word pid $($script:WordPid), version $($word.Version)"
    foreach ($name in $Names) {
        $path = "$Dir\$name.rtf"
        try {
            $want = @{}
            foreach ($l in [IO.File]::ReadAllLines("$Dir\$name.markers.txt", $utf8)) { $p = $l.Split("`t"); if ($p.Count -ge 2) { $want[$p[0].Trim()] = $p[1].Trim() } }
            $doc = $word.Documents.Open([ref]$path, [ref]$false, [ref]$true, [ref]$false)
            $seen = 0; $bad = 0; $out = New-Object Collections.Generic.List[string]
            foreach ($p in $doc.Paragraphs) {
                $t = ($p.Range.Text -replace "[`r`a]", '').Trim()
                if (-not $want.ContainsKey($t)) { continue }
                $seen++
                $lf = $p.Range.ListFormat
                $got = [string]$lf.ListString
                $w = $want[$t]
                $same = ($got -ceq $w)
                # a bullet: Word gives the glyph of its font (Symbol's U+F0B7 for the round bullet)
                if (-not $same -and $w.Length -eq 1 -and $got.Length -eq 1 -and $lf.ListType -ne 0 -and -not ($w -match '[0-9a-zA-Z]')) { $same = 'glyph' }
                $line = "$t | control '$w' ($(Codes $w)) | word '$got' ($(Codes $got)) level $($lf.ListLevelNumber) type $($lf.ListType) font $($p.Range.ListFormat.ListTemplate.ListLevels.Item($lf.ListLevelNumber).Font.Name)"
                if ($same -eq $true) { $out.Add("ok    $line") } elseif ($same -eq 'glyph') { $out.Add("glyph $line") } else { $out.Add("DIFF  $line"); $bad++ }
            }
            $doc.Close([ref]0)
            [IO.File]::WriteAllLines("$Dir\$name.word.txt", $out, $utf8)
            $out | Where-Object { $_ -notlike 'ok *' }
            "== $name : $($want.Count) items listed, $seen found, $bad differ"
        } catch {
            "== $name : FATAL $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
        }
    }
} catch {
    "FATAL $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
} finally {
    Stop-OurWord
}
