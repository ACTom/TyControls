# Picker Dialogs (Dialogs Program · S3) — Design

**Goal:** Two custom-drawn, themed picker dialogs on the S1/S2 `TTyDialog` foundation — a full
**Color** picker (`TySelectColor` + `TTyColorDialog`) and a **Font** dialog (`TyFontDialog` +
`TTyFontDialog`), each in its own unit — plus the reusable pure color-math the color picker needs.

**Architecture:** Extend the established pattern (construct-only builder + `Ty`-prefixed globals + a
non-visual `TComponent`; headless-testable pure logic, GUI paint/mouse eyeballed on a real machine —
the S2 SelectPath precedent). The Color dialog is a **single-model, multi-view** editor: one
`FColor: TTyColor` truth, with the HSV square + hue bar + hex + RGB + CMYK + Alpha all bound to it via
a re-entrancy-guarded sync. New pure color conversions (RGB↔HSV, RGB↔CMYK, hex) go in a dedicated
testable unit. The Font dialog reuses the color picker for its font-color field.

**Tech Stack:** Lazarus/FPC, LCL (`TColor`, `TFont`/`TFontStyles`, `Screen.Fonts`), BGRABitmap; builds
on `tyControls.Dialogs` (S1/S2), `tyControls.Painter` (per-pixel `Bitmap` + gradient fills +
`TyConfigureTextFont`/`DrawText`), `tyControls.Types` (`TTyColor`, `TyRGB`, `TyColorToLCL`),
`tyControls.Css.Values` (`TyParseColor`), and the input widgets `TTyEdit`/`TTySpinEdit`/`TTyCheckBox`/
`TTyListBox`/`TTyButton`/`TTyLabel`. Headless fpcunit.

**Roadmap context:** S3 of the P2–P4 dialogs sub-program (P1 chrome, S1 foundation, S2 input family all
DONE + merged). S4 (Find/Replace non-modal, Progress) follows. Naming: `Ty`-prefixed globals; native
`TTyColor` is the primary color type, with LCL `TColor` interop overloads.

---

## Current state (from S1/S2 + code map)
- `tyControls.Dialogs.pas`: `TTyDialog(TTyForm)` — `ContentRect`, `AddButton`, `AutoSizeToContent`,
  protected virtual `LayoutContent` + `Resize` reflow, `TyDialogButtonCount`/`TyDialogButton` (test
  introspection), exported layout consts `TyDlgPad`/`TyDlgEditW`/`TyDlgEditH`, `TyPlacePrompt`. The
  builder→`RunDialogModal`→globals + `TComponent` pattern is the template; resizable dialogs (S2 Text,
  SelectPath) set `Resizable:=True` + override `LayoutContent`. Palette group "TyControls Dialogs".
- **Color:** `TTyColor = type Cardinal` ($AARRGGBB, `tyControls.Types.pas:11`); `TyRGB(r,g,b)`,
  `TyRGBA`, `TyAlphaOf`/`TyRedOf`/`TyGreenOf`/`TyBlueOf`, `TyColorToLCL(c): TColor` (drops alpha, via
  `RGBToColor`). `TyParseColor(s): TTyColor` (`tyControls.Css.Values.pas`, parses `#rgb`/`#rrggbb`/
  `#rrggbbaa`). **No HSV/HSL or CMYK conversions exist, no `TColor`→`TTyColor`, no color→hex string.**
- **Painter:** `TTyPainter.Bitmap: TBGRABitmap` is exposed between `BeginPaint(Canvas,Rect,PPI)` and
  `EndPaint` → arbitrary per-pixel writes supported (HSV square). `FillBackground` supports a 2-stop
  `tfkLinearGradient` (`GradFrom`/`GradTo`/`GradAngleDeg`) → hue bar. `DrawText`/`MeasureText` +
  `TyConfigureTextFont(bmp,name,sizeLogical,weight,ppi)` render text exactly as controls do.
- **Font:** `Screen.Fonts: TStrings` lists families (LCL `Forms`). `TTyStyleSet` carries
  `FontName`/`FontSize`(pt)/`FontWeight`(≥600=bold). Controls paint via `DrawText(...,name,size,weight,...)`.
  `TyFallbackFontName` guards the empty-name gotcha. BGRA bold small-text uses the `ASmallCrisp` path.

## Design

### A. Pure color math — new unit `source/tyControls.ColorMath.pas`
A dependency-light unit (`uses tyControls.Types` only) holding the reusable, fully-unit-tested color
conversions the picker needs (kept out of the theme-internal `Css.Values` and out of the dialog unit
so they're reusable + independently testable):
```pascal
procedure TyRGBToHSV(AColor: TTyColor; out H, S, V: Single);   // H 0..360, S/V 0..1 (alpha ignored)
function  TyHSVToRGB(H, S, V: Single; AAlpha: Byte = 255): TTyColor;
procedure TyRGBToCMYK(AColor: TTyColor; out C, M, Y, K: Single); // each 0..1 (naive, no ICC)
function  TyCMYKToRGB(C, M, Y, K: Single; AAlpha: Byte = 255): TTyColor;
function  TyColorToHex(AColor: TTyColor; AIncludeAlpha: Boolean = True): string;  // '#RRGGBB[AA]'
function  TyColorFromLCL(AColor: TColor; AAlpha: Byte = 255): TTyColor;           // TColor -> TTyColor
```
- **HSV** via the standard hexagonal algorithm, using `Round()` (NOT `Trunc`) on the byte cast. The six
  hue anchors + gray/white/black round-trip **byte-exact**; a general spread of colors round-trips
  **within ±1 per channel** (float ×255/÷255 — the standard HSV tolerance). Tests assert accordingly.
- **CMYK naive**: `K := 1 - max(r,g,b)/255; C := (1-r/255-K)/(1-K)` (etc.; `K=1` ⇒ C=M=Y=0). No color
  management — the accepted, documented behavior of a UI picker. Round-trips within ±1.
- `TyColorToHex` is the counterpart to `TyParseColor` and MUST emit **RGBA order** (`#RRGGBB` or
  `#RRGGBBAA`, alpha **LAST** — matching `TyParseColor`'s `#rrggbbaa` parse, NOT the internal
  `$AARRGGBB` word order). `TyColorFromLCL` MUST resolve system colors first —
  `RedGreenBlue(ColorToRGB(AColor), r, g, b); Result := TyRGBA(r, g, b, AAlpha)` — because LCL
  `Red/Green/Blue` alone don't resolve `clWindowText`/`clDefault` (the `TFont.Color` default);
  `ColorToRGB` mirrors what `TyColorToLCL` does with `RGBToColor`.

### B. `TyColorDialog` — `source/tyControls.Dialogs.Color.pas`
A single-model, multi-view color editor built on `TTyDialog`.
- **The model:** `TTyColorForm = class(TTyDialog)` holds `FColor: TTyColor` (the one truth, incl.
  alpha) + `FUpdating: Boolean` (re-entrancy guard). A private `SyncViewsFromColor` refreshes EVERY
  editor + the preview from `FColor` (guarded); each editor's change handler parses its own value into
  a candidate `FColor` then calls `SyncViewsFromColor`. The guard makes programmatic refresh not
  re-trigger the handlers, so no feedback loop.
- **Editors (all bound to `FColor`):**
  - **HSV square** + **hue bar** are two dedicated windowed child controls (`TTyCustomControl`
    descendants, private to the unit), each with its own `Paint` + `MouseDown/Move/Up` + `FDragging`,
    **modeled on `TTyTrackBar`** (`tyControls.TrackBar.pas`: MouseDown sets `FDragging` + tracks,
    MouseUp clears). Each uses its OWN LCL mouse-capture (correct continuous drag), keeps picker logic
    OFF the form's chrome-loaded `MouseDown/Move/Up`, has no child z-order ambiguity, and is
    independently paintable/testable — NOT form-region paint + form-level hit-testing.
    - Square: S = x 0..1, V = y 1..0, painted per-pixel via `Painter.Bitmap` for the current hue; ring
      indicator at (S,V); mouse → (S,V) via pure `TyHSVAreaToSV(APoint, ARect): TPointF` (X=S, Y=V).
    - Hue bar (vertical, H 0..360): painted **per-pixel** (each device row =
      `TyHSVToRGB(TyHueBarToH(y, rect), 1, 1)` — reuses the pure fns; `FillBackground`'s gradient is
      2-stop only, so no single-gradient hue ramp); mouse → H via pure `TyHueBarToH(AY, ARect): Single`.
      Changing H repaints the square.
  - **Hex** `TTyEdit` (`#RRGGBB` or `#RRGGBBAA`) — `TyParseColor` in, `TyColorToHex` out.
  - **RGB** 3× `TTySpinEdit` (0..255).
  - **CMYK** 4× `TTySpinEdit` (0..100, shown as %).
  - **Alpha** 1× `TTySpinEdit` (0..255) — because the component exposes `Alpha`, the UI must edit it.
  - **Preview** swatch showing `FColor` over a checkerboard (so alpha reads visually).
- Painting + mouse in those two child controls are GUI (real-machine eyeball); the point↔value maps
  (`TyHSVAreaToSV`/`TyHueBarToH`, using `TPointF`/`Single` from the RTL `Types` unit) + all color
  conversions are pure + unit-tested. A reusable standalone `TTyColorPicker` could be extracted later.
- **Globals (two overloads, one shared builder):**
```pascal
function TySelectColor(const ACaption: string; var AColor: TTyColor): Boolean; overload;
function TySelectColor(const ACaption: string; var AColor: TColor; var AAlpha: Byte): Boolean; overload;
```
  Both build a `TTyColorForm` seeded from the input, `ShowModal` (try/finally free), and on `mrOK`
  write the result back: overload 1 ← `FColor`; overload 2 ← `AColor := TyColorToLCL(FColor)`,
  `AAlpha := TyAlphaOf(FColor)`.
- **Component `TTyColorDialog = class(TComponent)`** — published, all views of one `FColor` field:
  - `Color: TTyColor` (master, incl. alpha).
  - `LCLColor: TColor` — read `TyColorToLCL(FColor)`; write sets RGB from the `TColor`, **preserves the
    current `Alpha`**. Two-way with `Color` (both are `FColor`).
  - `Alpha: Byte` — read/write the alpha byte of `FColor`. Two-way with `Color`.
  - `Caption: string`; `function Execute: Boolean` (delegates to `TySelectColor` overload 1 on `FColor`).
  - *Design-time note:* a published `TTyColor` (`type Cardinal`) streams fine (verified) but the Object
    Inspector shows it as a raw signed integer (no color-swatch editor), and the `.lfm` stores a signed
    decimal. So the OI-friendly entry points are the `LCLColor` view (OI renders a real `TColor` swatch)
    + `Alpha`, plus a design-time Execute verb — `Color` remains the programmatic master.

### C. `TyFontDialog` — `source/tyControls.Dialogs.Font.pas` (RESIZABLE)
- **`TTyFontForm = class(TTyDialog)`** with: a `TTyListBox` family list (populated from `Screen.Fonts`,
  sorted, initial family selected), a `TTySpinEdit` size (points), four `TTyCheckBox` (Bold / Italic /
  Underline / Strikeout), a **font-color** swatch button (`TTyButton`) that opens `TySelectColor`
  (overload 2, `TColor`+alpha) and repaints the swatch, and a **preview** area rendering sample text in
  the chosen family/size/style/color. **Preview rendering (verified constraint):** `TTyPainter.DrawText`
  applies only bold (via weight) and `TyConfigureTextFont` hard-resets the bitmap `FontStyle`, so
  italic/underline/strikeout CANNOT go through `DrawText`. The preview instead calls
  `TyConfigureTextFont(Painter.Bitmap, name, size, weight, ppi)`, then adds the extra members to
  `Painter.Bitmap.FontStyle` (`+ [fsItalic, fsUnderline, fsStrikeOut]` as chosen), then draws via
  `Painter.Bitmap.TextRect(...)` directly (a font preview, not a control repaint — it intentionally
  exceeds what the control `DrawText` path renders).
  Resizable: `Resizable:=True` + `LayoutContent` stretches the family list + preview.
- **Result type = LCL `TFont`** (parity with `TFontDialog.Font`): the dialog reads
  `AFont.Name/Size/Style/Color` to seed and writes them back on OK.
- **Pure mappings (tested):**
  `function TyFontStyleToChecks(AStyle: TFontStyles): TTyFontChecks;` and
  `function TyChecksToFontStyle(const AChecks: TTyFontChecks): TFontStyles;`
  where `TTyFontChecks = record Bold, Italic, Underline, Strikeout: Boolean; end;` — round-trip stable
  over all 16 combinations. (The LCL enum member is `fsStrikeOut` — capital O; the record field/UI
  label stay `Strikeout`.)
- **Global + component:**
```pascal
function TyFontDialog(AFont: TFont): Boolean;   // mutates AFont on OK; True if OK
```
  `TTyFontDialog = class(TComponent)` — published `Font: TFont` (owns its TFont; setter Assigns);
  `Caption: string`; `function Execute: Boolean` (delegates to `TyFontDialog(FFont)`).
- **Font color** stored as the LCL `TColor` of `AFont.Color` (+ full opacity); the swatch button's
  `TySelectColor` overload-2 round-trips it.

### D. IDE integration + i18n
- Register `TTyColorDialog` + `TTyFontDialog` in the existing `RegisterComponents('TyControls Dialogs', …)`
  call (`designtime/tyControls.Design.pas`); add the two new units to its `uses` + the dt package if
  needed. Default palette glyphs (custom icons deferred, per S1/S2).
- New built-in text → `tyControls.StrConsts` resourcestrings + zh_CN: color labels ("Hue"/"Sat"/"Val"
  or the R/G/B/C/M/Y/K/A single-letters need none; "Hex"/"Preview"/"Alpha"), font labels
  ("Family"/"Size"/"Bold"/"Italic"/"Underline"/"Strikeout"/"Color"/"Preview"), and the preview sample
  text ("AaBbYyZz 0123"). (Single-letter channel captions R/G/B/C/M/Y/K/A stay literal.)

### E. Theming
Both dialogs reuse `TyForm` + `TyButton` + the embedded controls' tokens. The HSV square / hue bar /
preview render true color content (not theme tokens) — that's their purpose. The indicator ring +
checkerboard use neutral fixed colors (documented, like S1 semantic icon colors). No new required token.

## Error handling
- Cancel / Esc / title-bar X → returns False, leaves the caller's `var` args untouched (S2 contract).
- Color: an invalid hex string in the hex field → ignored (keep the last valid `FColor`); out-of-range
  RGB/CMYK/Alpha spins are clamped by `TTySpinEdit` Min/Max. Every editor edit routes through the guard,
  so a bad partial entry can't corrupt the model or loop.
- Font: empty `Screen.Fonts` (headless / no fonts) → the list is empty but the dialog still builds and
  the preview falls back to `TyFallbackFontName`; a family not present is tolerated (preview uses the
  effective font). Size clamped to a sane range (e.g. 1..999).
- No main form → `poScreenCenter` (inherited).

## Testing (headless fpcunit)
`tests/test.colormath.pas` (new) + `tests/test.dialogs.color.pas` (new) + `tests/test.dialogs.font.pas`
(new), all registered in `tests/tytests.lpr`:
1. **Color math (pure):** RGB↔HSV round-trip — **byte-exact** on the six hue anchors + gray/white/black,
   **within ±1 per channel** over a general spread; RGB↔CMYK round-trip (±1) + `K=1` (black) edge;
   `TyColorToHex` (with/without alpha, **RGBA order**) is the exact inverse of `TyParseColor`;
   `TyColorFromLCL`(after `ColorToRGB`)↔`TyColorToLCL` round-trip incl. a system-color seed
   (`clWindowText`). Coordinate maps `TyHSVAreaToSV`/`TyHueBarToH` → `TPointF`/`Single` (corners/edges/mid).
2. **Color dialog (construct-only + sync logic):** `TyBuildColorDialog(seed)` builds a `TTyColorForm`
   with the editors present, seeded to `seed`; a headless-drivable sync check — set the hex editor's
   text then invoke the apply path (a public `SetColor`/`ApplyHex` seam, NOT ShowModal) and assert the
   RGB/CMYK/Alpha spin values + `FColor` all updated consistently; and the reverse (set RGB spins →
   hex + `FColor` update). Assert the two `TySelectColor` overloads' seed/writeback mapping via the
   builder + a result-extraction helper (no modal). `TTyColorDialog` `LCLColor`/`Alpha` two-way: set
   `Color`, read `LCLColor`+`Alpha`; set `LCLColor`, assert `Color` RGB changed + alpha preserved; set
   `Alpha`, assert `Color` alpha changed.
3. **Font dialog:** `TyFontStyleToChecks`/`TyChecksToFontStyle` round-trip over all 16 combos;
   `TyBuildFontDialog(afont)` (construct-only) builds with the list/size/checks/preview present and the
   checks seeded from `AFont.Style`; the family list populates from a provided `TStrings` (inject, don't
   depend on `Screen.Fonts` headless) and selects the seed family; result write-back logic (checks →
   `TFontStyles`, size, name) via a helper without a modal.
- **Do NOT** `ShowModal`/`SetDesigning`. GUI (square drag, hue bar, live preview render, font-color
  launch) = real-machine eyeball. **Baseline after S2 merge: 1580 run / 0 failures / 11 errors.**

## Non-goals (S3)
- A reusable standalone `TTyColorPicker`/`TTyColorSwatch` control (picker stays dialog-internal).
- Color management / ICC profiles (CMYK is naive); named-color palettes / recent-colors / eyedropper.
- HSL editing (HSV only for the square); multi-stop gradients.
- Font: per-glyph preview, script/charset selection, font substitution UI.
- Custom palette icons for the two components (default glyph).

## Files
- **Create** `source/tyControls.ColorMath.pas` — the pure conversions (A). Add to `tycontrols.lpk`.
- **Create** `source/tyControls.Dialogs.Color.pas` — `TTyColorForm` + `TyBuildColorDialog` +
  `TySelectColor` (×2) + `TTyColorDialog` + the coordinate maps. Add to `tycontrols.lpk`.
- **Create** `source/tyControls.Dialogs.Font.pas` — `TTyFontForm` + `TyBuildFontDialog` + `TyFontDialog`
  + `TTyFontDialog` + the style maps. Add to `tycontrols.lpk`.
- **Modify** `source/tyControls.StrConsts.pas` — new resourcestrings (+ zh_CN in the pre-merge step).
- **Modify** `designtime/tyControls.Design.pas` — register the 2 components + `uses` the 2 dialog units.
- **Create** `tests/test.colormath.pas`, `tests/test.dialogs.color.pas`, `tests/test.dialogs.font.pas`;
  register in `tests/tytests.lpr`.
- **Modify** `docs/controls/dialogs.md` (§9 pickers) + README (extend the Dialogs bullet); regenerate
  `.pot` + zh_CN `.po` in the pre-merge step.
