# TTyForm Window Corners + Shadow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the borderless `TTyForm` OS-level rounded corners (Win11 + macOS, anti-aliased) and a native drop shadow (Win Vista+ via DWM, macOS native), **ON by default** and opt-out-able from `.tycss` (`border-radius: 0` / `window-shadow: false`), with no Win10+ floor and a clean widgetset-aware extension point for Linux.

**Architecture:** A new platform-isolated unit `tyControls.WindowEffects` exposes one entry `TyApplyWindowEffects(Form, effect)` that branches by platform/widgetset (Windows = dynamic dwmapi via GetProcAddress; macOS = NSWindow/CALayer; Linux = documented no-op stubs). `TTyForm` reads `border-radius` (already parsed) + a new boolean `window-shadow` token from its resolved style via a pure `TyResolveWindowEffect` helper that applies a **default-on** policy (corners + shadow on unless the theme sets `border-radius: 0` / `window-shadow: false`), and calls the entry after the handle exists and on theme/DPI/maximize changes. The form currently paints a plain rectangular window (no software shadow/rounding), so this is purely additive.

**Tech Stack:** Free Pascal / Lazarus (LCL Win32 + Cocoa), Win32 DWM API (dynamic), Cocoa (CocoaAll), fpcunit.

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `source/tyControls.Types.pas` | modify | add `tpWindowShadow` to `TTyProp`; add `WindowShadow: Boolean` to `TTyStyleSet` |
| `source/tyControls.StyleModel.pas` | modify | parse the `window-shadow` property (mirror `background-under-titlebar`) |
| `source/tyControls.WindowEffects.pas` | **create** | `TyApplyWindowEffects` + `TyRadiusToCornerPref`; all `{$IFDEF}` platform code |
| `source/tyControls.Form.pas` | modify | build the effect record + call the entry on theme/show/DPI/maximize |
| `tycontrols.lpk` | modify | add the new unit |
| `tests/test.windoweffects.pas` | **create** | token parse + `TyRadiusToCornerPref` + no-op-safety (headless) |
| `tests/tytests.lpr` | modify | register the test unit |
| `docs/controls/formchrome.md` | modify | document default-on + the two opt-out tokens + the platform matrix |

---

### Task 1: `window-shadow` CSS token

**Files:** Modify `source/tyControls.Types.pas`, `source/tyControls.StyleModel.pas`. Test: `tests/test.windoweffects.pas` (created here, expanded in Task 2).

- [ ] **Step 1: Write the failing test** — create `tests/test.windoweffects.pas`:
```pascal
unit test.windoweffects;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel;
type
  TWindowEffectsTest = class(TTestCase)
  published
    procedure TestWindowShadowParsesTrue;
    procedure TestWindowShadowAbsentIsNotPresent;
  end;
implementation
procedure TWindowEffectsTest.TestWindowShadowParsesTrue;
var M: TTyStyleModel; S: TTyStyleSet;
begin
  M := TTyStyleModel.Create;
  try
    M.LoadFromCss('TyForm { window-shadow: true; }');
    S := M.ResolveStyle('TyForm', '', []);
    AssertTrue('tpWindowShadow present', tpWindowShadow in S.Present);
    AssertTrue('WindowShadow = true', S.WindowShadow);
  finally M.Free; end;
end;
procedure TWindowEffectsTest.TestWindowShadowAbsentIsNotPresent;
var M: TTyStyleModel; S: TTyStyleSet;
begin
  M := TTyStyleModel.Create;
  try
    M.LoadFromCss('TyForm { background: #FFFFFF; }');
    S := M.ResolveStyle('TyForm', '', []);
    AssertFalse('tpWindowShadow not present', tpWindowShadow in S.Present);
  finally M.Free; end;
end;
initialization
  RegisterTest(TWindowEffectsTest);
end.
```
Add `test.windoweffects,` to `tests/tytests.lpr` uses.

- [ ] **Step 2: Run, verify it fails** (compile error: `tpWindowShadow`/`WindowShadow` undefined).
Run: `lazbuild tests/tytests.lpi` → Expected: FAIL (identifier not found).

- [ ] **Step 3: Add the enum + field.** In `source/tyControls.Types.pas`, the `TTyProp` enum (line 45-47) — append `tpWindowShadow`:
```pascal
  TTyProp = (tpBackground, tpTextColor, tpBorderColor, tpBorderWidth, tpBorderRadius,
             tpPadding, tpFontName, tpFontSize, tpFontWeight, tpOpacity, tpShadow,
             tpBorderStyle, tpOutline, tpGlass, tpBgUnderTitle, tpWindowShadow);
```
In `TTyStyleSet`, after `BackgroundUnderTitlebar: Boolean;` (line 53) add:
```pascal
    WindowShadow: Boolean;              // TyForm only: opt into the OS-native window drop shadow
```

- [ ] **Step 4: Parse it.** In `source/tyControls.StyleModel.pas`, after the `background-under-titlebar` handler (lines 585-589), add a sibling branch:
```pascal
  else if prop = 'window-shadow' then
  begin
    AStyle.WindowShadow := (LowerCase(raw) = 'true');
    Include(AStyle.Present, tpWindowShadow);
  end
```

- [ ] **Step 5: Run, verify green.**
Run: `lazbuild tests/tytests.lpi && ./tests/tytests.exe --suite=TWindowEffectsTest --format=plain` → Expected: 0 failures.

- [ ] **Step 6: Commit**
```bash
git add source/tyControls.Types.pas source/tyControls.StyleModel.pas tests/test.windoweffects.pas tests/tytests.lpr
git commit -m "feat(tycontrols): window-shadow css token (TyForm boolean)"
```

### Task 2: `tyControls.WindowEffects` unit

**Files:** Create `source/tyControls.WindowEffects.pas`. Test: `tests/test.windoweffects.pas` (extend).

- [ ] **Step 1: Write the failing tests** — append to `TWindowEffectsTest` published + impl in `tests/test.windoweffects.pas`:
```pascal
    procedure TestRadiusToCornerPref;
    procedure TestApplyIsNoOpWhenNoHandle;
    procedure TestDefaultsOnWhenTokensAbsent;
    procedure TestBorderRadiusZeroTurnsCornersOff;
    procedure TestWindowShadowFalseTurnsShadowOff;
```
```pascal
procedure TWindowEffectsTest.TestRadiusToCornerPref;
begin
  // 0 -> 0 (DONOTROUND), 1..5 -> 3 (ROUNDSMALL), >5 -> 2 (ROUND)
  AssertEquals('0 -> donotround', 0, TyRadiusToCornerPref(0, False));
  AssertEquals('4 -> roundsmall', 3, TyRadiusToCornerPref(4, False));
  AssertEquals('8 -> round', 2, TyRadiusToCornerPref(8, False));
  AssertEquals('maximized -> donotround', 0, TyRadiusToCornerPref(8, True));
end;
procedure TWindowEffectsTest.TestApplyIsNoOpWhenNoHandle;
var F: TForm; E: TTyWindowEffect;
begin
  F := TForm.CreateNew(nil);   // no Show -> HandleAllocated False (headless)
  try
    E.RadiusPx := 8; E.Shadow := True; E.Maximized := False;
    TyApplyWindowEffects(F, E);   // must NOT raise
    AssertTrue('no-op safe with no handle', True);
  finally F.Free; end;
end;
procedure TWindowEffectsTest.TestDefaultsOnWhenTokensAbsent;
var M: TTyStyleModel; E: TTyWindowEffect;
begin
  M := TTyStyleModel.Create;
  try
    M.LoadFromCss('TyForm { background: #FFFFFF; }');     // no radius, no window-shadow
    E := TyResolveWindowEffect(M.ResolveStyle('TyForm', '', []), False);
    AssertEquals('default radius on', TyDefaultWindowRadiusPx, E.RadiusPx);
    AssertTrue('default shadow on', E.Shadow);
  finally M.Free; end;
end;
procedure TWindowEffectsTest.TestBorderRadiusZeroTurnsCornersOff;
var M: TTyStyleModel; E: TTyWindowEffect;
begin
  M := TTyStyleModel.Create;
  try
    M.LoadFromCss('TyForm { border-radius: 0; }');        // present-with-0 -> opt out
    E := TyResolveWindowEffect(M.ResolveStyle('TyForm', '', []), False);
    AssertEquals('corners off via border-radius:0', 0, E.RadiusPx);
  finally M.Free; end;
end;
procedure TWindowEffectsTest.TestWindowShadowFalseTurnsShadowOff;
var M: TTyStyleModel; E: TTyWindowEffect;
begin
  M := TTyStyleModel.Create;
  try
    M.LoadFromCss('TyForm { window-shadow: false; }');
    E := TyResolveWindowEffect(M.ResolveStyle('TyForm', '', []), False);
    AssertFalse('shadow off via window-shadow:false', E.Shadow);
  finally M.Free; end;
end;
```
Add `Forms, tyControls.WindowEffects` to the test unit's `uses`.

- [ ] **Step 2: Run, verify it fails** (unit/symbols missing).

- [ ] **Step 3: Create `source/tyControls.WindowEffects.pas`:**
```pascal
unit tyControls.WindowEffects;
{$mode objfpc}{$H+}
{$IFDEF LCLCOCOA}{$modeswitch objectivec1}{$ENDIF}
interface
uses Classes, SysUtils, Controls, Forms, tyControls.Types;
type
  { Logical (CSS) px radius, plus flags. RadiusPx is the css border-radius value (points/
    logical px); each platform scales as needed. Maximized -> always square. }
  TTyWindowEffect = record
    RadiusPx:  Integer;
    Shadow:    Boolean;
    Maximized: Boolean;
  end;

const
  TyDefaultWindowRadiusPx = 8;   // corners ON by default; a theme sets border-radius: 0 to turn them off

{ Resolve the effect from a TyForm style under the DEFAULT-ON policy: corners + shadow are ON
  unless the theme opts out (border-radius: 0 / window-shadow: false). Pure -> headless-testable. }
function TyResolveWindowEffect(const AStyle: TTyStyleSet; AMaximized: Boolean): TTyWindowEffect;

{ Pure mapping for the Win11 DWM corner-preference enum:
  0 = DONOTROUND, 2 = ROUND, 3 = ROUNDSMALL. Exposed for headless testing. }
function TyRadiusToCornerPref(ARadiusPx: Integer; AMaximized: Boolean): Integer;

{ Apply rounded corners + native shadow to AForm's window per platform/widgetset.
  Safe to call repeatedly and when AForm has no handle (no-op). Never raises. }
procedure TyApplyWindowEffects(AForm: TCustomForm; const AEffect: TTyWindowEffect);

implementation

{$IFDEF WINDOWS}uses Windows;{$ENDIF}
{$IFDEF LCLCOCOA}uses CocoaAll;{$ENDIF}

function TyRadiusToCornerPref(ARadiusPx: Integer; AMaximized: Boolean): Integer;
begin
  if AMaximized or (ARadiusPx <= 0) then Result := 0          // DWMWCP_DONOTROUND
  else if ARadiusPx <= 5 then Result := 3                     // DWMWCP_ROUNDSMALL
  else Result := 2;                                           // DWMWCP_ROUND
end;

function TyResolveWindowEffect(const AStyle: TTyStyleSet; AMaximized: Boolean): TTyWindowEffect;
begin
  if tpBorderRadius in AStyle.Present then Result.RadiusPx := AStyle.BorderRadius
  else Result.RadiusPx := TyDefaultWindowRadiusPx;            // default-on
  if tpWindowShadow in AStyle.Present then Result.Shadow := AStyle.WindowShadow
  else Result.Shadow := True;                                // default-on
  Result.Maximized := AMaximized;
end;

{$IFDEF WINDOWS}
const
  DWMWA_WINDOW_CORNER_PREFERENCE = 33;
type
  TDwmMargins = record cxLeftWidth, cxRightWidth, cyTopHeight, cyBottomHeight: LongInt; end;
  TDwmSetWindowAttribute = function(h: HWND; a: DWORD; pv: Pointer; cb: DWORD): HRESULT; stdcall;
  TDwmExtendFrame = function(h: HWND; const m: TDwmMargins): HRESULT; stdcall;
  TDwmIsCompEnabled = function(out e: BOOL): HRESULT; stdcall;
var
  GLoaded: Boolean = False;
  GLib: HMODULE = 0;
  FnSetAttr: TDwmSetWindowAttribute = nil;
  FnExtend: TDwmExtendFrame = nil;
  FnCompEnabled: TDwmIsCompEnabled = nil;

procedure LoadDwm;
begin
  if GLoaded then Exit;
  GLoaded := True;
  GLib := LoadLibrary('dwmapi.dll');               // absent on XP -> 0 -> all Fn stay nil
  if GLib = 0 then Exit;
  Pointer(FnSetAttr) := GetProcAddress(GLib, 'DwmSetWindowAttribute');
  Pointer(FnExtend) := GetProcAddress(GLib, 'DwmExtendFrameIntoClientArea');
  Pointer(FnCompEnabled) := GetProcAddress(GLib, 'DwmIsCompositionEnabled');
end;

procedure ApplyWindows(AForm: TCustomForm; const E: TTyWindowEffect);
var h: HWND; pref: DWORD; m: TDwmMargins; comp: BOOL;
begin
  LoadDwm;
  h := AForm.Handle;
  if Assigned(FnSetAttr) then       // Win11: corner preference (no-op error on <Win11)
  begin
    pref := DWORD(TyRadiusToCornerPref(E.RadiusPx, E.Maximized));
    FnSetAttr(h, DWMWA_WINDOW_CORNER_PREFERENCE, @pref, SizeOf(pref));
  end;
  if Assigned(FnExtend) then        // Vista+: native shadow via 1px frame extension
  begin
    comp := False;
    if Assigned(FnCompEnabled) then FnCompEnabled(comp);
    FillChar(m, SizeOf(m), 0);
    if E.Shadow and comp and (not E.Maximized) then
    begin m.cxLeftWidth := 1; m.cxRightWidth := 1; m.cyTopHeight := 1; m.cyBottomHeight := 1; end;
    FnExtend(h, m);
  end;
end;
{$ENDIF}

{$IFDEF LCLCOCOA}
procedure ApplyCocoa(AForm: TCustomForm; const E: TTyWindowEffect);
var v, content: NSView; win: NSWindow; r: CGFloat;
begin
  v := NSView(AForm.Handle);          // LCL-Cocoa: Form.Handle is a TCocoaWindowContent (NSView)
  if v = nil then Exit;
  win := v.window;
  if win = nil then Exit;
  content := win.contentView;
  if content = nil then Exit;
  content.setWantsLayer(True);
  if E.Maximized then r := 0 else r := E.RadiusPx;     // points (logical) == css px
  if content.layer <> nil then
  begin
    content.layer.setCornerRadius(r);
    content.layer.setMasksToBounds(r > 0);
  end;
  win.setHasShadow(E.Shadow);
end;
{$ENDIF}

procedure TyApplyWindowEffects(AForm: TCustomForm; const AEffect: TTyWindowEffect);
begin
  if (AForm = nil) or (not AForm.HandleAllocated) then Exit;
  try
    {$IFDEF WINDOWS}ApplyWindows(AForm, AEffect);{$ENDIF}
    {$IFDEF LCLCOCOA}ApplyCocoa(AForm, AEffect);{$ENDIF}
    { Linux extension point — documented no-ops for now:
      {$IFDEF LCLQT5}/{$IFDEF LCLQT6}: translucent window + AA paint + custom shadow (Qt composites
        lightweight children, so no Win32-HWND blocker) — the promising future path.
      {$IFDEF LCLGTK2}: gdk_window_shape_combine_region gives only jagged corners -> skipped per the
        AA-only rule.  {$IFDEF LCLGTK3}: no window-shape API.  All deferred until a Linux verify rig. }
  except
    // capability/quirk failures must never crash the host app — degrade silently
  end;
end;

finalization
  {$IFDEF WINDOWS}if GLib <> 0 then FreeLibrary(GLib);{$ENDIF}
end.
```
> Note: the macOS path compiles only under the Cocoa widgetset; it is best-effort and **verified on a real mac**. CocoaAll method names (`setWantsLayer`, `setCornerRadius`, `setMasksToBounds`, `setHasShadow`) follow the LCL CocoaAll bridge; if a name differs on the target Lazarus, adjust to the available selector.

- [ ] **Step 4: Build + run, verify green.**
Run: `lazbuild tests/tytests.lpi && ./tests/tytests.exe --suite=TWindowEffectsTest --format=plain` → Expected: 0 failures.

- [ ] **Step 5: Commit**
```bash
git add source/tyControls.WindowEffects.pas tests/test.windoweffects.pas
git commit -m "feat(tycontrols): WindowEffects unit — Win11 DWM corners + DWM/Cocoa native shadow (dynamic, no Win10 floor)"
```

### Task 3: Wire into `TTyForm` + the package

**Files:** Modify `source/tyControls.Form.pas`, `tycontrols.lpk`.

- [ ] **Step 1: Add a helper + call sites in `TTyForm`.** In `source/tyControls.Form.pas`, add `tyControls.WindowEffects` to the implementation `uses` (the main one, not the IFDEF blocks). Add a private method declaration in `TTyForm` (near `ApplyChromeTheme`):
```pascal
    procedure ApplyWindowEffects;
```
Implement it (place near `ApplyChromeTheme`):
```pascal
procedure TTyForm.ApplyWindowEffects;
var E: TTyWindowEffect;
begin
  if (FController = nil) or (not HandleAllocated) then Exit;
  E := TyResolveWindowEffect(                               // default-on; theme opts out via css
         FController.Model.ResolveStyle('TyForm', '', []),
         WindowState = wsMaximized);
  TyApplyWindowEffects(Self, E);
end;
```

- [ ] **Step 2: Call it from the four trigger points.**
  - `ApplyChromeTheme` (line 1042-1064): before the final `Invalidate;` add `ApplyWindowEffects;`.
  - `Loaded` (line 804-810): after `ArmEngine;` add `ApplyWindowEffects;` (handle exists post-load).
  - Override `DoShow` (so first show applies it even when not theme-driven). Add to the class `protected` section `procedure DoShow; override;` and:
```pascal
procedure TTyForm.DoShow;
begin
  inherited DoShow;
  ApplyWindowEffects;
end;
```
  - In `TTyChromeEngine.ToggleMaximize` (line 666): after the maximize/restore state change, re-apply on the owning form. The engine holds `FForm` — at the end of `ToggleMaximize` add: `if FForm is TTyForm then TTyForm(FForm).ApplyWindowEffects;` (make `ApplyWindowEffects` reachable — declare it `public` instead of `private`, or add a thin public `procedure RefreshWindowEffects; begin ApplyWindowEffects; end;` and call that).

- [ ] **Step 3: Add the unit to the runtime package.** In `tycontrols.lpk`, after the `PageControl` `<Item>` (the last file item) add:
```xml
      <Item>
        <Filename Value="source/tyControls.WindowEffects.pas"/>
        <UnitName Value="tyControls.WindowEffects"/>
      </Item>
```
(The current `<Files>` uses unnumbered `<Item>` entries — append one more; no Count attribute to bump in the user-normalized format.)

- [ ] **Step 4: Build packages + full suite (no regressions).**
Run: `lazbuild tyControls.lpk && lazbuild tycontrols_dt.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain`
Expected: all compile; 0 failures (pre-existing ~11 headless errors unchanged).

- [ ] **Step 5: Commit**
```bash
git add source/tyControls.Form.pas tycontrols.lpk
git commit -m "feat(tycontrols): TTyForm applies window corners+shadow on theme/show/maximize"
```

### Task 4: Docs (default-on is automatic — no theme edits needed)

**Files:** `docs/controls/formchrome.md`.

Corners + shadow are ON by default via `TyResolveWindowEffect` (Task 2), so **no theme needs editing to enable them** — the shipped default theme's `TyForm { background: var(--form-bg); }` rule sets no `border-radius`/`window-shadow`, so it gets the code defaults (8px + shadow). Documentation only.

- [ ] **Step 1: Document** — add a section to `docs/controls/formchrome.md` (create it if absent):
````markdown
## Window rounded corners + drop shadow

A `TTyForm` chrome window gets **anti-aliased rounded corners and a native drop shadow on
supported platforms by default** — no theme tokens required.

Customize or opt out from the `TyForm` rule in your `.tycss`:

    TyForm {
      border-radius: 12px;     /* change the corner radius (default 8) */
      border-radius: 0;        /* turn corners OFF (square window)     */
      window-shadow: false;    /* turn the native shadow OFF           */
    }

| Platform         | Corners                        | Shadow                        |
|------------------|--------------------------------|-------------------------------|
| Windows 11       | anti-aliased (DWM)             | native, free with the corners |
| Windows Vista–10 | square (no jagged region)      | native rectangular (DWM)      |
| Windows XP       | square                         | none                          |
| macOS            | anti-aliased (CALayer)         | native (NSWindow)             |
| Linux            | desktop-environment controlled | desktop-environment controlled|

Notes: the radius maps to *round*/*small* on Windows 11 (it cannot honor an exact px there).
There is **no Windows-10-or-newer requirement** — `dwmapi.dll` is loaded dynamically, so the
binary launches on Windows 7/XP and simply degrades.
````

- [ ] **Step 2: Commit**
```bash
git add docs/controls/formchrome.md
git commit -m "docs: TyForm rounded corners + window shadow are on by default; tokens + platform matrix"
```

---

## Manual verification (cannot be headless — the user runs these)

1. **Win 11:** a TyForm with the **default theme** (no corner/shadow tokens) → **anti-aliased rounded** corners + a soft native shadow appear automatically (default-on). Maximize → corners go **square**; restore → rounded again.
2. **Win 10:** square corners + a native (rectangular) DWM shadow. **If no shadow appears** (Risk R1 — pure `WS_POPUP`), note it: we then either add a guarded `WM_NCCALCSIZE` tweak or fall back to no native shadow on pre-Win11.
3. **Win 7 / XP build:** app **launches** (proves dynamic dwmapi, no static-import crash). Win7 = square + shadow (if composition on); XP = square, no shadow.
4. **macOS:** AA rounded corners (content area) + native window shadow.
5. **Opt-out:** load a theme with `TyForm { border-radius: 0; window-shadow: false; }` → square + no shadow, live on switch. (And `border-radius: 16px` → larger radius.)

## Self-review notes
- Spec coverage: token (T1), engine incl. dynamic dwmapi + Cocoa + Linux stubs + px→enum + the default-on `TyResolveWindowEffect` (T2), TTyForm triggers incl. maximize→square (T3), docs (T4). The spec's "disable software shadow" reconcile is a **no-op** — `TTyForm.Paint` draws no software shadow today (verified). R1 is captured in the manual-verification fallback.
- Default-on policy is unit-tested headlessly (T2: `TestDefaultsOnWhenTokensAbsent`, `TestBorderRadiusZeroTurnsCornersOff`, `TestWindowShadowFalseTurnsShadowOff`) rather than hidden behind a window handle.
- Type consistency: `TTyWindowEffect`, `TyApplyWindowEffects`, `TyRadiusToCornerPref`, `TyResolveWindowEffect`, `TyDefaultWindowRadiusPx`, `tpWindowShadow`, `WindowShadow`, `ApplyWindowEffects` consistent across tasks.
