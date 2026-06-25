# TTyNativeStyler — Harmonizing Native / Third-Party Controls with the Theme

**Date:** 2026-06-26
**Status:** Approved (brainstorming) → ready for implementation plan

## Goal

Let standard LCL controls and third-party controls visually blend with the themed TyControls, by
applying theme-derived colours/fonts to them — **gracefully**: third-party controls work out of the
box, and controls where forcing a colour would look *worse* (OS-drawn buttons etc.) are left alone.

## Problem

TyControls are custom-drawn + themed via the Controller's `.tycss` model. A native `TEdit` or a
third-party grid sitting next to them keeps its stock white-on-system look and clashes. The naive fix
("set everyone's Color/Font from the theme") backfires: OS-drawn controls (`TButton`, native
`TCheckBox`) ignore `Color` or render it ugly, and you cannot enumerate every third-party class to
build a complete allow-list.

## Key decisions (locked during brainstorming)

1. **Shape:** a non-visual **`TTyNativeStyler`** component (option B), built on the existing
   `Controller.Model.ResolveStyle` + `TyColorToLCL` foundation.
2. **Default-on, opt-out** targeting: it themes all eligible native controls under its root and you
   exclude the odd one — *not* opt-in-per-control.
3. **Generic by default, curated only for exceptions** (this resolves "the safe-table can't be
   complete, so third-party would be unsupported"):
   - **RTTI-generic application:** for each control, use `TypInfo` to see what it actually publishes —
     if it has a published `Font`, set the text colour; if a published `Color`, set the background.
     **Any** control exposing the standard props is themed, third-party included, with no registry
     entry. So third-party is supported *by default*.
   - **Small curated DENY-list:** the known OS-drawn classes where a background is ineffective/ugly —
     `TButton`, `TBitBtn`, `TSpeedButton`, `TToggleBox`, `TCheckBox`, `TRadioButton`. For these the
     *background* is skipped but the *font colour* is still applied. The list is short because the
     "OS-draws-it" set is small; it is built-in + user-extensible.
   - **Per-prop granularity:** font colour is low-risk → applied broadly; background `Color` is the
     risky one → gated by the deny-list. An unknown third-party control thus gets the right text
     colour safely, and a background only if it is not a known OS-drawn type.
4. **Two escape hatches for the long tail:** a per-control **opt-out** and a per-control/class
   **override**, both via one `OnStyleControl` event (below).
5. **Theme-token-driven** (the project's hard rule): every value comes from the theme. Each native
   class borrows the closest Ty token; classes with no analog resolve a new generic **`TyNative`**
   token so theme authors control "what native controls look like" from the `.tycss`.

## Architecture

### New unit `source/tyControls.NativeStyler.pas`

**`TTyNativeStyler = class(TComponent)`** — non-visual; drop on a form, point at a Controller.

Published properties:
- `Controller: TTyStyleController` — the theme source. On assign + on the controller's change
  notification, re-apply. `FreeNotification` to nil it if freed.
- `Root: TWinControl` — the subtree to style (default: the owner form). Walked recursively.
- `Enabled: Boolean` (default True) — master switch.
- `ApplyFontName: Boolean` (default **False**) — also set `Font.Name` from the theme (off by default;
  changing the family is usually safe but opt-in).
- `ApplyFontSize: Boolean` (default **False**) — also set `Font.Size` (off by default; resizing a
  native control's font can break its layout).
- `OnStyleControl: TTyStyleControlEvent` — `procedure(Sender: TObject; AControl: TControl; var AHandled: Boolean)`.
  Fires for every candidate before styling. Set `AHandled := True` to skip it (opt-out) **or** to do
  your own custom styling first (override). The single hook covers both escape hatches.

Public methods:
- `procedure Apply;` — (re)style the whole `Root` subtree now. Idempotent.
- `class procedure RegisterDeny(AClass: TControlClass);` — add a class to the background deny-list
  (e.g. a third-party OS-drawn widget). Class-level, affects all stylers.

### What `Apply` does
Guard at entry: do nothing if `not Enabled`, `Controller = nil`, or `Root = nil`. Then for each
control in `Root` (recursive, depth-first):
1. **Skip** if it is a TyControl (`is TTyGraphicControl` / `is TTyCustomControl` — they self-theme via
   their own Controller). (The non-visual styler itself lives in `Components`, not `Controls`, so the
   walk never encounters it.)
2. Fire `OnStyleControl`; if `AHandled` → skip (the user opted out / handled it).
3. **Resolve the theme to borrow:** map the control's class to the closest Ty `typeKey` via a small
   built-in map — `TEdit→TyEdit`, `TMemo→TyMemo`, `TListBox→TyListBox`, `TComboBox→TyComboBox`,
   `TPanel→TyPanel`, `TGroupBox→TyGroupBox`, `TCheckBox/TRadioButton→TyCheckBox`, `TLabel→TyLabel`,
   `TStaticText→TyLabel` — else fall back to `TyNative`. (The map is an *optional refinement*; an
   unknown class still gets themed via `TyNative`, so it never reintroduces the allow-list gap.)
   `style := Controller.Model.ResolveStyle(typeKey, '', [])`.
4. **Apply props via RTTI** (`TypInfo`):
   - If `IsPublishedProp(ctrl, 'Font')`: set `Font.Color := TyColorToLCL(style.TextColor)`; if
     `ApplyFontName` set `Font.Name`; if `ApplyFontSize` set `Font.Size`. Set `ParentFont := False`
     when the prop exists.
   - If `IsPublishedProp(ctrl, 'Color')` **and** the class is **not** in the deny-list and the style
     has a solid background (`style.Background.Kind = tfkSolid`): set
     `Color := TyColorToLCL(style.Background.Color)`; set `ParentColor := False` when the prop exists.
   - All prop access is guarded (missing prop / wrong type → skip that prop). Never raises.

### Live theme switching — small Controller addition
`TTyStyleController.Changed` currently only invalidates registered TyControls. Add a lightweight
**change-listener** facility so non-control observers (the styler) can react:
- `procedure AddChangeListener(AListener: TNotifyEvent);` / `RemoveChangeListener(...)` — a small list.
- `Changed` fires the listeners (after the existing invalidate loop).
The styler subscribes in its `Controller` setter and calls `Apply` from the callback. (`ApplyChromeTheme`
on a TyForm calls into the controller's normal change path, so a theme switch re-styles natives too.)

### New theme token `TyNative`
A base `typeKey` for "generic native control surface", resolved for classes with no closer Ty analog.
Define a sensible default in the **default/base theme** (`source/tyControls.DefaultTheme.pas`): a
neutral surface background + the theme text colour (reuse the same neutrals the input/panel tokens
use). Built-in themes inherit it through the normal cascade; a theme may override `TyNative { … }` to
tune how natives look. Absent in a theme → resolves the global base neutrals (still reasonable). This
keeps every value theme-driven and needs theme-data work only in the default theme.

## Testing (headless — the logic is testable without a GUI)
The decision logic is pure and runs on plain `TControl` instances (property setting needs no handle):
- A `TEdit` styled → `Color` and `Font.Color` are set from the resolved `TyEdit` style; `ParentColor`
  /`ParentFont` are False.
- A `TButton` styled → `Font.Color` IS set but `Color` is NOT (deny-list); assert `Color` unchanged.
- A control with no published `Color` (e.g. a bare `TGraphicControl` subclass) → `Color` skipped, no
  exception.
- `OnStyleControl` with `AHandled := True` → the control is left untouched.
- `RegisterDeny(TMyClass)` → that class's background is skipped.
- A class with no map entry → resolves `TyNative` (assert it used the `TyNative` style, not crash).
- Recursion: a control nested in a `TPanel` is reached.
Add `tests/test.nativestyler.pas` to the suite (must keep the suite green). Visual blend-in is the
only manual-verify part.

## Phasing
1. **Foundation:** the `TyNative` token (default theme) + the Controller change-listener facility.
2. **Styler core:** `tyControls.NativeStyler.pas` (the class map, deny-list, RTTI apply, `Apply`) +
   the headless tests.
3. **Wiring + polish:** Controller association + live re-apply on change; register the component in
   the design-time package (palette) so it can be dropped on a form. Optional later: design-time
   preview (the styler applying inside the IDE designer).

## Out of scope (YAGNI for v1)
- Option C (`.tycss` `native(TEdit){…}` selectors) — `TyNative` + the class map cover the need; native
  per-class CSS targeting can come later if wanted.
- Border-colour theming of natives — most native controls don't expose a settable border colour (it's
  OS-drawn), so it's not a general lever; a specific third-party control that does can be handled in
  its `OnStyleControl` override.
- Re-theming on dynamically-created controls automatically — `Apply` is called on theme change and can
  be called manually after building controls at runtime.

## Key reference points (existing code)
- `source/tyControls.Controller.pas` — `Model` (`:52`), `RegisterStyleable`/`Changed` (`:403`/`:418`);
  the change-listener facility is added here.
- `source/tyControls.StyleModel.pas` — `ResolveStyle(typeKey, class, states): TTyStyleSet`.
- `source/tyControls.Types.pas` — `TTyStyleSet` (Background/TextColor/FontName/…), `TyColorToLCL`.
- `source/tyControls.DefaultTheme.pas` — where the `TyNative` default rule is added.
- `designtime/tyControls.Design.pas` — `RegisterComponents` (add `TTyNativeStyler` to the palette).
