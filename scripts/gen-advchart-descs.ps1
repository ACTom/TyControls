# Pack the option catalog's EN/ZH descriptions into a design-time resource.
#
# WHY THEY ARE NOT IN THE GENERATED .pas. tyControls.AdvChart.Catalog.pas is a
# RUNTIME unit, and the descriptions are 194 KB of mostly-CJK prose that nothing
# at runtime reads -- only the design-time editor shows them. Compiling them into
# the runtime package would put a fifth of a megabyte of documentation into every
# application that draws a chart.
#
# WHY NOT READ tools/advchart/catalog.json AT DESIGN TIME. scripts/make-release.ps1
# excludes tools/ from the archive, so an installed copy of the package would find
# no file there and the editor would silently show no descriptions. A resource
# compiled into the design-time package travels with it.
#
# Regenerate after tools/advchart/catalog.json changes:
#     powershell -ExecutionPolicy Bypass -File scripts/gen-advchart-descs.ps1
# Commit designtime/advchart-descs.json and designtime/tycontrols_advchart_desc.lrs.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$catalog = Join-Path $root 'tools\advchart\catalog.json'
$poolJson = Join-Path $root 'designtime\advchart-descs.json'
$lrs = Join-Path $root 'designtime\tycontrols_advchart_desc.lrs'
$lazres = 'C:\lazarus\tools\lazres.exe'

if (-not (Test-Path $catalog)) { throw "missing $catalog" }
if (-not (Test-Path $lazres)) { throw "missing $lazres" }

Write-Output '== reading the catalog =='
$json = Get-Content -Raw -Encoding UTF8 $catalog | ConvertFrom-Json
$descs = $json.descs
Write-Output ("  {0} descriptions" -f $descs.Count)

# The POOL ONLY. The per-node indices into it are already in the generated .pas
# as DescEn / DescZh, so shipping them twice would be shipping the same thing
# twice. JSON rather than a hand-rolled framing because a description can hold
# any character, newlines included, and fpjson is already linked design-time.
Write-Output '== writing the pool =='
$out = ConvertTo-Json -InputObject $descs -Compress -Depth 3
# NOTE: Windows PowerShell 5.1 does NOT escape CJK here -- the file carries raw
# UTF-8 (83,823 non-ASCII bytes of 208,750), and lazres writes each of those as a
# decimal escape. That is where the .lrs 500 KB comes from.
[System.IO.File]::WriteAllText($poolJson, $out, [System.Text.UTF8Encoding]::new($false))
$size = (Get-Item $poolJson).Length
Write-Output ("  {0} -> {1:N0} bytes" -f (Split-Path -Leaf $poolJson), $size)

Write-Output '== packing the .lrs =='
Push-Location (Split-Path $poolJson)
try {
  & $lazres $lrs 'advchart-descs.json=TyAdvChartDescs'
  if ($LASTEXITCODE -ne 0) { throw 'lazres failed' }
} finally {
  Pop-Location
}
$lrsSize = (Get-Item $lrs).Length
Write-Output ("  {0} -> {1:N0} bytes of Pascal" -f (Split-Path -Leaf $lrs), $lrsSize)
