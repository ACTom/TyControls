# Palette icon generator

Draws the 20 TyControls component-palette icons (24x24 RGBA, line-glyph + `#3B82F6` accent)
and packs them into `designtime/tycontrols_icons.lrs`, which `tyControls.Design.pas`
includes via `{$I}` before `RegisterComponents`. The IDE shows each by class name.

## Regenerate

    pwsh -File scripts/gen-icons.ps1

This rebuilds `genicons`, renders `designtime/icons/<ClassName>.png`, and repacks the
`.lrs` (via `C:\lazarus\tools\lazres.exe`). Commit the changed `designtime/icons/*.png`
and `designtime/tycontrols_icons.lrs`.

## Edit a glyph

Edit its `G<Name>` routine in `genicons.lpr` (geometry is plain BGRA primitives in a
24-unit space), then regenerate. After changing icons, rebuild `tycontrols_dt.lpk` and
restart Lazarus to see them in the palette.
