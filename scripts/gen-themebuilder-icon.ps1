# Renders the theme builder's application icon (tools/themebuilder/icon/genicon.lpr):
#
#   tools/themebuilder/themebuilder.ico        Windows -- beside the .lpi and named after the
#                                              project, which is the only place Lazarus looks
#                                              (<Icon Value="0"/> in themebuilder.lpi)
#   tools/themebuilder/icon/themebuilder-256.png  Linux / macOS (desktop entry, app bundle)
#
# Commit both, then rebuild the theme builder: lazbuild links the .ico into its resource.

$ErrorActionPreference = 'Stop'
$root   = Split-Path $PSScriptRoot -Parent
$genLpi = Join-Path $root 'tools/themebuilder/icon/genicon.lpi'
$genExe = Join-Path $root 'tools/themebuilder/icon/genicon.exe'
$ico    = Join-Path $root 'tools/themebuilder/themebuilder.ico'
$png    = Join-Path $root 'tools/themebuilder/icon/themebuilder-256.png'

Write-Host '== building genicon =='
& lazbuild -B $genLpi
if ($LASTEXITCODE -ne 0) { throw 'genicon build failed' }

Write-Host '== rendering the icon =='
& $genExe $ico $png
if ($LASTEXITCODE -ne 0) { throw 'genicon run failed' }
