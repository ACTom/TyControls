# Palette icon generator

Draws the 20 TyControls component-palette icons (line-glyph + `#3B82F6` accent) and packs
them into `designtime/tycontrols_icons.lrs`, which `tyControls.Design.pas` includes via
`{$I}` before `RegisterComponents`. The IDE shows each by class name.

Each icon is rendered at **three native sizes** for HiDPI: `<Class>` = 24px (100%),
`<Class>_150` = 36px (150%), `<Class>_200` = 48px (200%). The IDE picks the variant
matching the display scaling, so palette icons stay crisp instead of upscaling 24px.
Geometry is authored in a 24-unit space and scaled per size — every variant is drawn at
native resolution, never resampled.

## Regenerate

    pwsh -File scripts/gen-icons.ps1

This rebuilds `genicons`, renders `designtime/icons/<ClassName>.png`, and repacks the
`.lrs` (via `C:\lazarus\tools\lazres.exe`). Commit the changed `designtime/icons/*.png`
and `designtime/tycontrols_icons.lrs`.

## Edit a glyph

Edit its `G<Name>` routine in `genicons.lpr` (geometry is plain BGRA primitives in a
24-unit space), then regenerate. After changing icons, rebuild `tycontrols_dt.lpk` and
restart Lazarus to see them in the palette.
