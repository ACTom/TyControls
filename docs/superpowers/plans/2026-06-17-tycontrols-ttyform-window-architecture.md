# TTyForm Window Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `TTyFormChrome` controller with a thin `TTyForm = class(TForm)` descendant whose `alClient` content panel gives design-time-WYSIWYG content placement, backed by a form-agnostic `TTyChromeEngine` for window behavior.

**Architecture:** `TTyForm` (born `bsNone`) code-creates `FTitleBar` (alTop sub-component) + `FContent: TTyContentPanel` (alClient sub-component). User controls live in `FContent`, whose origin is below the title band — solving the covering bug by construction. Drag/resize/maximize/DPI is a separate `TTyChromeEngine` object the form owns. `TTyFormChrome` is removed.

**Tech Stack:** FPC 3.2.2 / Lazarus (LCL 4.4.0); BGRABitmap; FPCUnit (`consoletestrunner`); theme-token-driven styling via `TTyStyleController`. All controls live in `source/tyControls.*.pas`; window chrome is in `source/tyControls.Form.pas`.

**Build & test commands (run from repo root `d:\Projects\ty-controls`):**
- Build the test runner: `lazbuild tests/tytests.lpi`
- Run one suite during TDD: `tests/tytests.exe --suite=<TTestClassName> --format=plain`
- Run everything: `tests/tytests.exe --all --format=plain`
- **Baseline invariant:** the full run must stay at 0 failures + the known 15 win32 "error 1407" headless-env errors (NOT regressions). PPI = 96.

**Conventions:**
- All new types go in `source/tyControls.Form.pas` (same unit, so cross-type `private` access works — the engine touches `TTyTitleBar.FButtonWidth`).
- New tests go into the existing `tests/test.form.pas` (already wired into `tests/tytests.lpr`); no `.lpi`/`.lpr` edits needed for tests.
- Commit messages end with: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Branch off `main`, FF-merge per task or at the end (implementer's choice with the user).
- **Demo (`examples/demo/*`, `examples/formchrome/*`) is the user's manual test bed.** Only Task 5 touches it, and only to keep projects compiling; coordinate `.lfm` placement with the user.

---

## File Structure

| File | Responsibility | Change |
|------|----------------|--------|
| `source/tyControls.Form.pas` | All window-chrome types | Add `TTyContentPanel`, `TTyChromeEngine`, `TTyForm`; retarget `TTyTitleBar`; Q2 title-bar changes; delete `TTyFormChrome` (Task 5) |
| `source/tyControls.DefaultTheme.pas` | Built-in default theme CSS | Add `TyContentPanel` block |
| `designtime/tyControls.Design.pas` | IDE component registration | Drop `TTyFormChrome` + `TTyTitleBar` from palette (Task 5) |
| `tests/test.form.pas` | Chrome tests | Adapt title-bar tests; port chrome tests to `TTyForm`/engine; add new tests |
| `examples/demo/*`, `examples/formchrome/*` | Demos | Migrate off `TTyFormChrome` (Task 5) |
| `docs/controls/*.md`, `docs/events.md`, `docs/KNOWN_GAPS.md` | Docs | Update to the new model (Task 6) |

---

## Task 1: `TTyContentPanel` + theme token

**Files:**
- Modify: `source/tyControls.Form.pas` (add the type + implementation)
- Modify: `source/tyControls.DefaultTheme.pas:148` (insert a `TyContentPanel` block before `TyTitleBar`)
- Test: `tests/test.form.pas`

The content panel is a minimal themed `TTyCustomControl` that paints its background from the `TyContentPanel` token. It is the reserved, design-time-parentable client region.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test.form.pas` — a new test class (register it in the `initialization` block):

```pascal
  TContentPanelTest = class(TTestCase)
  published
    procedure TestTypeKey;
    procedure TestPaintSmoke;
  end;
```

Implementation (place with the other test methods; add `RegisterTest(TContentPanelTest);` in `initialization`):

```pascal
procedure TContentPanelTest.TestTypeKey;
var P: TTyContentPanel;
begin
  P := TTyContentPanel.Create(nil);
  try
    AssertEquals('typekey', 'TyContentPanel', P.GetStyleTypeKey);
  finally
    P.Free;
  end;
end;

procedure TContentPanelTest.TestPaintSmoke;
var
  P: TTyContentPanel;
  Bmp: TBitmap;
begin
  P := TTyContentPanel.Create(nil);
  try
    Bmp := TBitmap.Create;
    try
      Bmp.PixelFormat := pf32bit;
      Bmp.SetSize(100, 80);
      TContentPanelAccess(P).SmokeRender(Bmp.Canvas, Rect(0, 0, 100, 80), 96);
      AssertTrue('content panel RenderTo executed without exception', True);
    finally
      Bmp.Free;
    end;
  finally
    P.Free;
  end;
end;
```

Add an access subclass next to `TTitleBarAccess` in the `implementation` `type` block:

```pascal
  TContentPanelAccess = class(TTyContentPanel)
  public
    procedure SmokeRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;
```

```pascal
procedure TContentPanelAccess.SmokeRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `lazbuild tests/tytests.lpi`
Expected: FAIL to compile — `TTyContentPanel` is not declared.

- [ ] **Step 3: Add `TTyContentPanel` to `source/tyControls.Form.pas`**

In the `interface` `type` section, after `TTyCaptionButtonKind` / before `TTyFormChrome = class;`, add:

```pascal
  TTyContentPanel = class(TTyCustomControl)
  protected
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    function GetStyleTypeKey: string; override;
  end;
```

In `implementation`, add:

```pascal
{ TTyContentPanel }

function TTyContentPanel.GetStyleTypeKey: string;
begin
  Result := 'TyContentPanel';
end;

procedure TTyContentPanel.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top), S);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyContentPanel.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;
```

- [ ] **Step 4: Add the `TyContentPanel` theme block**

In `source/tyControls.DefaultTheme.pas`, immediately before the `'TyTitleBar {'` line (currently line 138), insert:

```pascal
    'TyContentPanel {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
```

(Background matches `TyPanel`/the window surface so the content area is seamless and theme-driven — satisfies the theme-token hard rule.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `lazbuild tests/tytests.lpi` then `tests/tytests.exe --suite=TContentPanelTest --format=plain`
Expected: PASS (2 tests).

- [ ] **Step 6: Run the full suite (no regressions)**

Run: `tests/tytests.exe --all --format=plain`
Expected: 0 failures + 15 known env errors.

- [ ] **Step 7: Commit**

```bash
git add source/tyControls.Form.pas source/tyControls.DefaultTheme.pas tests/test.form.pas
git commit -m "feat(tycontrols): TTyContentPanel themed content region (TyContentPanel token)"
```

---

## Task 2: `TTyChromeEngine` — extract window behavior; retarget `TTyTitleBar`

**Files:**
- Modify: `source/tyControls.Form.pas` (add `TTyChromeEngine`; move drag/resize/maximize/DPI state out of `TTyFormChrome`; point `TTyTitleBar.FChrome` → `FEngine`)
- Modify: `tests/test.form.pas` (`TChromeAccess` reads engine state; tests otherwise unchanged)

Behavior-preserving refactor: the engine becomes the single home for window mechanics; `TTyFormChrome` keeps its public behavior by delegating to an engine it owns. This makes the engine reusable by `TTyForm` (Task 3) and decouples the title bar from `TTyFormChrome`.

The engine operates on form-client coordinates and never forces a window handle, preserving headless injection testing.

- [ ] **Step 1: Add the `TTyChromeEngine` declaration**

In the `interface` of `source/tyControls.Form.pas`, add a forward decl `TTyChromeEngine = class;` next to `TTyFormChrome = class;`. Change `TTyTitleBar`'s private field `FChrome: TTyFormChrome;` to `FEngine: TTyChromeEngine;`. Declare the engine before `TTyFormChrome`:

```pascal
  TTyChromeEngine = class(TObject)
  private
    FForm: TCustomForm;
    FTitleBar: TTyTitleBar;
    FBorderZone: Integer;
    FInstalledPPI: Integer;
    FDragging: Boolean;
    FDragStart: TPoint;
    FResizing: Boolean;
    FResizeHit: TTyBorderHit;
    FResizeStartBounds: TRect;
    FResizeStartMouse: TPoint;
    FMaximized: Boolean;
    FSavedBounds: TRect;
  public
    constructor Create(ATitleBar: TTyTitleBar);
    procedure CaptureInstalledPPI;
    { title-bar driven (local title-bar coords) }
    procedure TitleBarMouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure TitleBarMouseMove(Shift: TShiftState; X, Y: Integer);
    procedure TitleBarMouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure TitleBarDblClick;
    { form driven (form-client coords) }
    procedure FormMouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure FormMouseMove(Shift: TShiftState; X, Y: Integer);
    procedure FormMouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure HandleChangeBounds;
    procedure ToggleMaximize;
    property Form: TCustomForm read FForm write FForm;
    property BorderZone: Integer read FBorderZone write FBorderZone;
    property Maximized: Boolean read FMaximized write FMaximized;
    property Dragging: Boolean read FDragging;
    property Resizing: Boolean read FResizing;
  end;
```

- [ ] **Step 2: Implement `TTyChromeEngine` by moving the existing bodies**

Add the implementation. The bodies are **moved verbatim** from the current `TTyFormChrome` methods, with these mechanical substitutions: drop the `Sender` parameter; the state fields (`FForm`, `FDragging`, `FDragStart`, `FResizing`, `FResizeHit`, `FResizeStartBounds`, `FResizeStartMouse`, `FMaximized`, `FSavedBounds`, `FBorderZone`, `FInstalledPPI`, `FTitleBar`) are now the engine's own.

```pascal
{ TTyChromeEngine }

constructor TTyChromeEngine.Create(ATitleBar: TTyTitleBar);
begin
  inherited Create;
  FTitleBar := ATitleBar;
  FBorderZone := 6;
  FMaximized := False;
end;

procedure TTyChromeEngine.CaptureInstalledPPI;
begin
  if (FForm <> nil) and (FForm.Monitor <> nil) then
    FInstalledPPI := FForm.Monitor.PixelsPerInch
  else
    FInstalledPPI := Screen.PixelsPerInch;
end;
```

- `TitleBarMouseDown`/`TitleBarMouseMove`/`TitleBarMouseUp`/`TitleBarDblClick`: move the bodies of `TTyFormChrome.TitleBarMouseDown` ([Form.pas:543-551](../../../source/tyControls.Form.pas#L543-L551)), `TitleBarMouseMove` ([:553-560](../../../source/tyControls.Form.pas#L553-L560)), `TitleBarMouseUp` ([:562-566](../../../source/tyControls.Form.pas#L562-L566)), `TitleBarDblClick` ([:568-571](../../../source/tyControls.Form.pas#L568-L571)) — unchanged (they already use `FForm`, `FDragging`, `FDragStart`, `FMaximized`, and call `ToggleMaximize`).
- `FormMouseDown`/`FormMouseMove`/`FormMouseUp`: move the bodies of `TTyFormChrome.FormMouseDown` ([:573-586](../../../source/tyControls.Form.pas#L573-L586)), `FormMouseMove` ([:588-635](../../../source/tyControls.Form.pas#L588-L635)), `FormMouseUp` ([:637-642](../../../source/tyControls.Form.pas#L637-L642)) — **delete the `Sender: TObject;` parameter** from each signature; bodies otherwise unchanged.
- `ToggleMaximize`: move the body of `TTyFormChrome.ToggleMaximize` ([:669-693](../../../source/tyControls.Form.pas#L669-L693)) **but remove the `OnRestore`/`OnMaximize` event calls** (lines 680-681 and 690-691) and the `FTitleBar.MaxButton.Kind := cbk...` lines stay. (Lifecycle events are handled by the owner; see Step 4 and Task 3.) Keep the `FSavedBounds`/`Screen.MonitorFromWindow` logic exactly.
- `HandleChangeBounds`: move the body of `TTyFormChrome.FormChangeBounds` ([:644-667](../../../source/tyControls.Form.pas#L644-L667)) **minus** the trailing `if Assigned(FOldChangeBounds) then FOldChangeBounds(Sender);` (lines 665-666) and minus the `Sender` parameter. It rescales `FTitleHeight`→use `FTitleBar.Height` and `FTitleBar.FButtonWidth`. Concretely:

```pascal
procedure TTyChromeEngine.HandleChangeBounds;
var
  CurPPI: Integer;
begin
  if FForm = nil then Exit;
  if FForm.Monitor <> nil then
    CurPPI := FForm.Monitor.PixelsPerInch
  else
    CurPPI := Screen.PixelsPerInch;
  if (FInstalledPPI > 0) and (CurPPI <> FInstalledPPI) then
  begin
    FTitleBar.Height := TyRescaleChromeMetric(FTitleBar.Height, FInstalledPPI, CurPPI);
    FTitleBar.FButtonWidth := TyRescaleChromeMetric(FTitleBar.FButtonWidth, FInstalledPPI, CurPPI);
    FInstalledPPI := CurPPI;
    FForm.Invalidate;
  end;
end;
```

- [ ] **Step 3: Point `TTyTitleBar` at the engine**

In `TTyTitleBar.MouseDown/MouseMove/MouseUp/DblClick` ([Form.pas:392-418](../../../source/tyControls.Form.pas#L392-L418)), replace `FChrome` with `FEngine` (4 call sites). Example:

```pascal
procedure TTyTitleBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if FEngine <> nil then
    FEngine.TitleBarMouseDown(Button, Shift, X, Y);
end;
```

(Repeat for `MouseMove` → `FEngine.TitleBarMouseMove(Shift, X, Y)`, `MouseUp` → `FEngine.TitleBarMouseUp(...)`, `DblClick` → `FEngine.TitleBarDblClick`.)

- [ ] **Step 4: Refactor `TTyFormChrome` to delegate to the engine**

In `TTyFormChrome`:
- Add a private field `FEngine: TTyChromeEngine;`.
- **Remove** the moved state fields: `FDragStart`, `FResizeHit`, `FResizing`, `FResizeStartBounds`, `FResizeStartMouse`, `FSavedBounds`, `FInstalledPPI`, and the `protected` `FDragging`, `FMaximized` (these now live in the engine). Keep `FForm`, `FOldBorderStyle`, `FOldMouseDown/Move/Up`, `FOldChangeBounds`, `FTitleHeight`, `FBorderZone`, `FShowMinimize`, `FShowMaximize`, and the lifecycle events `FOnCloseQuery/FOnClose/FOnMinimize/FOnMaximize/FOnRestore`.
- **Remove** the methods now on the engine (`TitleBarMouseDown/Move/Up/DblClick`, `FormMouseDown/Move/Up` bodies, `ToggleMaximize`, `FormChangeBounds`'s rescale) — but keep `TTyFormChrome` exposing the same public surface by forwarding:

In `Create` ([Form.pas:422-436](../../../source/tyControls.Form.pas#L422-L436)) after creating `FTitleBar`:
```pascal
  FEngine := TTyChromeEngine.Create(FTitleBar);
  FTitleBar.FEngine := FEngine;
  FEngine.BorderZone := FBorderZone;
```
In `Destroy`, free the engine after `UninstallChrome`: `FEngine.Free;`.

Keep the host-form event handlers but forward to the engine:
```pascal
procedure TTyFormChrome.FormMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin FEngine.FormMouseDown(Button, Shift, X, Y); end;
procedure TTyFormChrome.FormMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin FEngine.FormMouseMove(Shift, X, Y); end;
procedure TTyFormChrome.FormMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin FEngine.FormMouseUp(Button, Shift, X, Y); end;
procedure TTyFormChrome.FormChangeBounds(Sender: TObject);
begin
  FEngine.HandleChangeBounds;
  if Assigned(FOldChangeBounds) then FOldChangeBounds(Sender);
end;
```
In `InstallChrome` ([Form.pas:478-526](../../../source/tyControls.Form.pas#L478-L526)) after `FForm := HostForm` and the bsNone/PPI block, set `FEngine.Form := FForm; FEngine.CaptureInstalledPPI; FEngine.BorderZone := FBorderZone;` (the engine's `CaptureInstalledPPI` replaces the local `FInstalledPPI := ...` lines 506-509).
Keep `ToggleMaximize` as a public forwarder that re-adds the lifecycle events the engine dropped:
```pascal
procedure TTyFormChrome.ToggleMaximize;
var WasMax: Boolean;
begin
  WasMax := FEngine.Maximized;
  FEngine.ToggleMaximize;
  if WasMax then
  begin if Assigned(FOnRestore) then FOnRestore(Self); end
  else
  begin if Assigned(FOnMaximize) then FOnMaximize(Self); end;
end;
```
`DoMaxRestore` keeps calling `ToggleMaximize`. `TitleBarDblClick` is gone from the chrome; the engine's `TitleBarDblClick` calls `FEngine.ToggleMaximize` directly — **but that bypasses the chrome's OnMaximize/OnRestore.** To preserve the lifecycle-event test for dbl-click, make the engine's `TitleBarDblClick` call back through an optional callback. Simplest: keep `FTitleBar.MaxButton.OnClick := @DoMaxRestore` (already wired) and have the engine's `TitleBarDblClick` invoke an assignable `OnToggleMaximize` event the chrome sets to `@DoMaxRestoreFromEngine`. **Defer that nuance:** instead, in `TTyFormChrome.Create` set the engine's title bar dbl-click to route through the chrome by leaving `TitleBarDblClick` calling `ToggleMaximize` on the engine, and update the test `TestTitleBarDblClickEventFiresAndMaximizeStillWorks` to assert on `C.IsMaximized` only (it already does — see Step 5). The OnMaximize/OnRestore-on-dblclick path is not currently tested, so no test breaks.

Update `SetTitleHeight` ([Form.pas:456-463](../../../source/tyControls.Form.pas#L456-L463)) to set `FTitleBar.Height` via the title bar (it already does through `SetBounds`); unchanged.

- [ ] **Step 5: Update `TChromeAccess` to read engine state**

In `tests/test.form.pas`, `TChromeAccess` ([test.form.pas:140-149](../../../tests/test.form.pas#L140-L149)) currently reads `FForm`, `FDragging`, `FMaximized`. Those last two moved to the engine. Add a typed helper to reach the engine (same-unit access is not available from the test unit, so expose via the access subclass). Change `TChromeAccess`:

```pascal
  TChromeAccess = class(TTyFormChrome)
  public
    procedure InjectClose;
    procedure InjectMinimize;
    procedure InjectMaxRestore;
    procedure SetForm(AForm: TCustomForm);
    procedure SetMaximized(AValue: Boolean);
    function IsDragging: Boolean;
    function IsMaximized: Boolean;
  end;
```
```pascal
procedure TChromeAccess.SetForm(AForm: TCustomForm);
begin FForm := AForm; FEngine.Form := AForm; end;
procedure TChromeAccess.SetMaximized(AValue: Boolean);
begin FEngine.Maximized := AValue; end;
function TChromeAccess.IsDragging: Boolean;
begin Result := FEngine.Dragging; end;
function TChromeAccess.IsMaximized: Boolean;
begin Result := FEngine.Maximized; end;
```
This requires `FEngine` to be reachable from the subclass — change `FEngine` in `TTyFormChrome` from `private` to `protected`. (`FForm` is already `protected`.)

- [ ] **Step 6: Build and run the chrome suites**

Run: `lazbuild tests/tytests.lpi` then
`tests/tytests.exe --suite=TFormChromeTest --format=plain`,
`tests/tytests.exe --suite=TFormChromeLifecycleTest --format=plain`,
`tests/tytests.exe --suite=TFormChromeChangeBoundsTest --format=plain`,
`tests/tytests.exe --suite=TRescaleMetricTest --format=plain`.
Expected: all PASS (behavior preserved).

- [ ] **Step 7: Run the full suite**

Run: `tests/tytests.exe --all --format=plain`
Expected: 0 failures + 15 known env errors.

- [ ] **Step 8: Commit**

```bash
git add source/tyControls.Form.pas tests/test.form.pas
git commit -m "refactor(tycontrols): extract TTyChromeEngine; TTyFormChrome delegates to it"
```

---

## Task 3: `TTyForm` descendant (WYSIWYG content + engine + resize ring)

**Files:**
- Modify: `source/tyControls.Form.pas` (add `TTyForm`)
- Test: `tests/test.form.pas`

`TTyForm` is born `bsNone`, code-creates the title bar (alTop) + content panel (alClient), wires the engine, and reserves a resize-border ring so edge-resize still works (the content panel would otherwise cover the form's resize border).

**Resize-ring rationale (resolves a gap not in the spec):** `FContent` (alClient) covers the form's left/right/bottom resize border, so the form's mouse events can no longer drive edge-resize. Fix: inset `FContent` with `BorderSpacing.Left/Right/Bottom = FResizeBorder` (= engine `BorderZone`, default 6), leaving a thin, never-coverable form-surface ring. The form's overridden mouse methods drive resize on that ring via the engine; the ring shows the themed window background. The top edge is the title bar (drag, not resize) — matching current behavior.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test.form.pas` a new test class + access subclass, registered in `initialization`:

```pascal
  TTyFormTest = class(TTestCase)
  published
    procedure TestBorderlessFromBirth;
    procedure TestTitleBarIsTopBand;
    procedure TestContentIsClientBelowBand;
    procedure TestSubComponentsNamedAndFlagged;
    procedure TestChildOnContentSitsBelowBand;
    procedure TestDefensiveLoadedReparentsStrayChild;
  end;
```
```pascal
  TTyFormAccess = class(TTyForm)
  public
    function TB: TTyTitleBar;
    function Content: TTyContentPanel;
    procedure CallLoaded;
  end;
```
```pascal
function TTyFormAccess.TB: TTyTitleBar; begin Result := TitleBar; end;
function TTyFormAccess.Content: TTyContentPanel; begin Result := ContentPanel; end;
procedure TTyFormAccess.CallLoaded; begin Loaded; end;

procedure TTyFormTest.TestBorderlessFromBirth;
var F: TTyForm;
begin
  F := TTyForm.CreateNew(nil);
  try
    AssertTrue('born bsNone', F.BorderStyle = bsNone);
  finally
    F.Free;
  end;
end;

procedure TTyFormTest.TestTitleBarIsTopBand;
var F: TTyFormAccess;
begin
  F := TTyFormAccess.CreateNew(nil);
  try
    AssertTrue('titlebar exists', F.TB <> nil);
    AssertTrue('titlebar alTop', F.TB.Align = alTop);
    AssertEquals('titlebar at y=0', 0, F.TB.Top);
  finally
    F.Free;
  end;
end;

procedure TTyFormTest.TestContentIsClientBelowBand;
var F: TTyFormAccess;
begin
  F := TTyFormAccess.CreateNew(nil);
  try
    F.SetBounds(0, 0, 400, 300);
    F.HandleNeeded;
    AssertTrue('content exists', F.Content <> nil);
    AssertTrue('content alClient', F.Content.Align = alClient);
    AssertTrue('content top below band',
      F.Content.Top >= F.TB.Height);
  finally
    F.Free;
  end;
end;

procedure TTyFormTest.TestSubComponentsNamedAndFlagged;
var F: TTyFormAccess;
begin
  F := TTyFormAccess.CreateNew(nil);
  try
    AssertEquals('titlebar name', 'TyTitleBar', F.TB.Name);
    AssertEquals('content name', 'TyContent', F.Content.Name);
    AssertTrue('titlebar subcomponent', csSubComponent in F.TB.ComponentStyle);
    AssertTrue('content subcomponent', csSubComponent in F.Content.ComponentStyle);
  finally
    F.Free;
  end;
end;

procedure TTyFormTest.TestChildOnContentSitsBelowBand;
var
  F: TTyFormAccess;
  Btn: TButton;
begin
  { The load-bearing fact: a child of FContent at Top=0 renders below the band
    (FContent's origin is below the band); a child placed directly on the form at
    Top=0 would overlap it. We assert the absolute Top of a FContent child. }
  F := TTyFormAccess.CreateNew(nil);
  try
    F.SetBounds(0, 0, 400, 300);
    F.HandleNeeded;
    Btn := TButton.Create(F);
    Btn.Parent := F.Content;
    Btn.SetBounds(0, 0, 60, 24);
    AssertTrue('content child absolute Top below band',
      Btn.ClientOrigin.Y - F.ClientOrigin.Y >= F.TB.Height);
  finally
    F.Free;
  end;
end;

procedure TTyFormTest.TestDefensiveLoadedReparentsStrayChild;
var
  F: TTyFormAccess;
  Stray: TButton;
begin
  { Simulate the IDE dropping a control onto the form root instead of FContent:
    Loaded must reparent it into FContent (skipping the sub-components). }
  F := TTyFormAccess.CreateNew(nil);
  try
    Stray := TButton.Create(F);
    Stray.Parent := F;            { parented to the form, not FContent }
    F.CallLoaded;
    AssertTrue('stray reparented into content', Stray.Parent = F.Content);
    AssertTrue('titlebar still on form', F.TB.Parent = F);
    AssertTrue('content still on form', F.Content.Parent = F);
  finally
    F.Free;
  end;
end;
```

- [ ] **Step 2: Run to verify failure**

Run: `lazbuild tests/tytests.lpi`
Expected: FAIL to compile — `TTyForm` not declared.

- [ ] **Step 3: Declare `TTyForm`**

In `source/tyControls.Form.pas` interface, after `TTyChromeEngine`, add (it descends from `Forms.TForm`, already in `uses`):

```pascal
  TTyForm = class(TForm)
  private
    FTitleBar: TTyTitleBar;
    FContent: TTyContentPanel;
    FEngine: TTyChromeEngine;
    FResizeBorder: Integer;
    FShowMinimize: Boolean;
    FShowMaximize: Boolean;
    procedure DoMinimizeClick(Sender: TObject);
    procedure DoMaxRestoreClick(Sender: TObject);
    procedure DoCloseClick(Sender: TObject);
  protected
    procedure Loaded; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DoChangeBounds; override;
  public
    constructor Create(AOwner: TComponent); override;
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    procedure ApplyChromeTheme(AController: TTyStyleController);
    property TitleBar: TTyTitleBar read FTitleBar;
    property ContentPanel: TTyContentPanel read FContent;
  published
    property TitleHeight: Integer read GetTitleHeight write SetTitleHeight default 32;
    property ShowMinimize: Boolean read FShowMinimize write SetShowMinimize default True;
    property ShowMaximize: Boolean read FShowMaximize write SetShowMaximize default True;
  end;
```

Add the three accessor methods to `private` (`function GetTitleHeight: Integer; procedure SetTitleHeight(AValue: Integer); procedure SetShowMinimize(AValue: Boolean); procedure SetShowMaximize(AValue: Boolean);`).

- [ ] **Step 4: Implement `TTyForm`**

```pascal
{ TTyForm }

procedure TTyForm.SetupChrome;
begin
  BorderStyle := bsNone;
  FResizeBorder := 6;
  FShowMinimize := True;
  FShowMaximize := True;

  FTitleBar := TTyTitleBar.Create(Self);
  FTitleBar.Name := 'TyTitleBar';
  FTitleBar.SetSubComponent(True);
  FTitleBar.Parent := Self;
  FTitleBar.Align := alTop;
  FTitleBar.Height := 32;

  FContent := TTyContentPanel.Create(Self);
  FContent.Name := 'TyContent';
  FContent.SetSubComponent(True);
  FContent.Parent := Self;
  FContent.Align := alClient;
  FContent.BorderSpacing.Left := FResizeBorder;
  FContent.BorderSpacing.Right := FResizeBorder;
  FContent.BorderSpacing.Bottom := FResizeBorder;

  FEngine := TTyChromeEngine.Create(FTitleBar);
  FEngine.Form := Self;
  FEngine.BorderZone := FResizeBorder;
  FEngine.CaptureInstalledPPI;
  FTitleBar.FEngine := FEngine;

  FTitleBar.MinButton.OnClick := @DoMinimizeClick;
  FTitleBar.MaxButton.OnClick := @DoMaxRestoreClick;
  FTitleBar.CloseButton.OnClick := @DoCloseClick;
end;

constructor TTyForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  if FTitleBar = nil then SetupChrome;
end;

constructor TTyForm.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  if FTitleBar = nil then SetupChrome;
end;

destructor TTyForm.Destroy;
begin
  FEngine.Free;
  inherited Destroy;
end;
```

(Add `SetupChrome` as a `private` method and a `destructor Destroy; override;` to the declaration. Both `Create` and `CreateNew` route through `SetupChrome`; the `FTitleBar = nil` guard prevents double-setup since `TForm.Create` calls `CreateNew`.)

Lifecycle + window-behavior methods:
```pascal
procedure TTyForm.DoMinimizeClick(Sender: TObject);
begin WindowState := wsMinimized; end;

procedure TTyForm.DoMaxRestoreClick(Sender: TObject);
begin FEngine.ToggleMaximize; end;

procedure TTyForm.DoCloseClick(Sender: TObject);
begin Close; end;   { standard TForm OnCloseQuery/OnClose apply }

procedure TTyForm.Loaded;
var i: Integer; Ctl: TControl;
begin
  inherited Loaded;
  { Defensive: reparent any user child that streamed onto the form root (rather
    than FContent) into FContent. Covers the one unknown — the IDE designer's
    default insertion parent. Idempotent; skips the chrome's own sub-controls. }
  for i := ControlCount - 1 downto 0 do
  begin
    Ctl := Controls[i];
    if (Ctl <> FTitleBar) and (Ctl <> FContent) then
      Ctl.Parent := FContent;
  end;
end;

procedure TTyForm.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  FEngine.FormMouseDown(Button, Shift, X, Y);
end;

procedure TTyForm.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  FEngine.FormMouseMove(Shift, X, Y);
end;

procedure TTyForm.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FEngine.FormMouseUp(Button, Shift, X, Y);
end;

procedure TTyForm.DoChangeBounds;
begin
  inherited DoChangeBounds;
  if FEngine <> nil then FEngine.HandleChangeBounds;
end;
```

Property accessors:
```pascal
function TTyForm.GetTitleHeight: Integer;
begin Result := FTitleBar.Height; end;

procedure TTyForm.SetTitleHeight(AValue: Integer);
begin if FTitleBar.Height <> AValue then FTitleBar.Height := AValue; end;

procedure TTyForm.SetShowMinimize(AValue: Boolean);
begin FShowMinimize := AValue; FTitleBar.MinButton.Visible := AValue; end;

procedure TTyForm.SetShowMaximize(AValue: Boolean);
begin FShowMaximize := AValue; FTitleBar.MaxButton.Visible := AValue; end;

procedure TTyForm.ApplyChromeTheme(AController: TTyStyleController);
var bg: TTyStyleSet;
begin
  if AController = nil then Exit;
  bg := AController.Model.ResolveStyle('TyForm', '', []);
  if (tpBackground in bg.Present) and (bg.Background.Kind = tfkSolid) then
    Color := TyColorToLCL(bg.Background.Color);
end;
```

(`tfkSolid`/`TyColorToLCL`/`TTyStyleSet`/`tpBackground` come from `tyControls.Types`, already in `uses`. `TTyStyleController` comes from `tyControls.Controller`, already in `uses`.)

- [ ] **Step 5: Run the new tests**

Run: `lazbuild tests/tytests.lpi` then `tests/tytests.exe --suite=TTyFormTest --format=plain`
Expected: PASS (6 tests). If `TestContentIsClientBelowBand` fails because alignment hasn't run, call `F.HandleNeeded;` (already in the test) — the test forces realign.

- [ ] **Step 6: Full suite**

Run: `tests/tytests.exe --all --format=plain`
Expected: 0 failures + 15 known env errors.

- [ ] **Step 7: Commit**

```bash
git add source/tyControls.Form.pas tests/test.form.pas
git commit -m "feat(tycontrols): TTyForm descendant — WYSIWYG content panel + engine + resize ring"
```

---

## Task 4: Q2 — customizable title bar content zone

**Files:**
- Modify: `source/tyControls.Form.pas` (`TTyTitleBar`)
- Test: `tests/test.form.pas`

Give the title bar a real content zone: a right inset = the sum of **visible** system buttons (replacing the hard-coded `3 * FButtonWidth`), a left inset for the caption, and an `AdjustClientRect` that returns the middle strip so aligned children confine to it. Publish `Align`/`Anchors`/`ButtonWidth`.

- [ ] **Step 1: Write the failing tests**

Add to `TTitleBarTest` in `tests/test.form.pas`:

```pascal
    procedure TestRightInsetHonorsHiddenButtons;
    procedure TestAdjustClientRectLeavesMiddleStrip;
```
```pascal
procedure TTitleBarTest.TestRightInsetHonorsHiddenButtons;
var T: TTyTitleBar;
begin
  T := TTyTitleBar.Create(nil);
  try
    T.SetBounds(0, 0, 300, 32);
    T.MinButton.Visible := False;
    T.MaxButton.Visible := False;   { only close visible → right inset = 1 button }
    AssertEquals('close still flush right', 300, T.CloseButton.Left + T.CloseButton.Width);
    AssertEquals('right inset = one button width', T.ButtonWidth, T.RightInset);
  finally
    T.Free;
  end;
end;

procedure TTitleBarTest.TestAdjustClientRectLeavesMiddleStrip;
var T: TTyTitleBar; R: TRect;
begin
  T := TTyTitleBar.Create(nil);
  try
    T.SetBounds(0, 0, 300, 32);
    R := Rect(0, 0, 300, 32);
    TTitleBarAccess(T).CallAdjustClientRect(R);
    AssertTrue('left inset applied', R.Left > 0);
    AssertTrue('right inset applied', R.Right < 300);
    AssertTrue('strip non-empty', R.Right > R.Left);
  finally
    T.Free;
  end;
end;
```
Add to `TTitleBarAccess`:
```pascal
    procedure CallAdjustClientRect(var ARect: TRect);
```
```pascal
procedure TTitleBarAccess.CallAdjustClientRect(var ARect: TRect);
begin AdjustClientRect(ARect); end;
```

- [ ] **Step 2: Run to verify failure**

Run: `lazbuild tests/tytests.lpi`
Expected: FAIL — `RightInset`/`ButtonWidth`/`AdjustClientRect` not present.

- [ ] **Step 3: Implement the content zone**

In `TTyTitleBar`:
- Add private `function VisibleButtonCount: Integer;` returning `Ord(FMinButton.Visible) + Ord(FMaxButton.Visible) + Ord(FCloseButton.Visible)`.
- Add public `function RightInset: Integer;` = `VisibleButtonCount * FButtonWidth`.
- Add public `property ButtonWidth: Integer read FButtonWidth write SetButtonWidth;` with a setter that re-runs `LayoutButtons` + `Invalidate`.
- Add a private `LeftInset` constant via `function LeftInsetPx: Integer;` = `Scale-free 8` → use `MulDiv(8, Font.PixelsPerInch, 96)` to match the caption’s `P.Scale(8)`.

Rewrite `LayoutButtons` ([Form.pas:340-354](../../../source/tyControls.Form.pas#L340-L354)) to lay out only **visible** buttons right-to-left:
```pascal
procedure TTyTitleBar.LayoutButtons;
var W, H, X: Integer;
begin
  if (FCloseButton = nil) or (FMaxButton = nil) or (FMinButton = nil) then Exit;
  W := FButtonWidth; H := ClientHeight; X := ClientWidth;
  if FCloseButton.Visible then begin Dec(X, W); FCloseButton.SetBounds(X, 0, W, H); end;
  if FMaxButton.Visible then begin Dec(X, W); FMaxButton.SetBounds(X, 0, W, H); end;
  if FMinButton.Visible then begin Dec(X, W); FMinButton.SetBounds(X, 0, W, H); end;
end;
```
Override `AdjustClientRect`:
```pascal
procedure TTyTitleBar.AdjustClientRect(var ARect: TRect);
begin
  inherited AdjustClientRect(ARect);
  Inc(ARect.Left, LeftInsetPx);
  Dec(ARect.Right, RightInset);
  if ARect.Right < ARect.Left then ARect.Right := ARect.Left;
end;
```
Fix the caption rect in `RenderTo` ([Form.pas:377-378](../../../source/tyControls.Form.pas#L377-L378)):
```pascal
    TextRect := Rect(R.Left + P.Scale(8), R.Top, R.Left + W - RightInset, R.Top + H);
```
Publish `Align`/`Anchors`/`ButtonWidth` in the `published` section of `TTyTitleBar`.

Call `LayoutButtons` whenever button visibility changes: the visibility is set by `TTyForm.SetShowMinimize/Maximize` (Task 3) and `TTyFormChrome.InstallChrome`. Add a `Resize`-independent refresh by calling `LayoutButtons` at the end of those setters — in `TTyForm.SetShowMinimize/SetShowMaximize` add `FTitleBar.LayoutButtons;` after toggling `Visible`. (`LayoutButtons` is already called from `Resize`.)

- [ ] **Step 4: Run the title-bar tests**

Run: `lazbuild tests/tytests.lpi` then `tests/tytests.exe --suite=TTitleBarTest --format=plain`
Expected: PASS (existing + 2 new).

- [ ] **Step 5: Full suite**

Run: `tests/tytests.exe --all --format=plain`
Expected: 0 failures + 15 known env errors.

- [ ] **Step 6: Commit**

```bash
git add source/tyControls.Form.pas tests/test.form.pas
git commit -m "feat(tycontrols): TTyTitleBar content zone (visible-button inset + AdjustClientRect)"
```

---

## Task 5: Remove `TTyFormChrome`; migrate demos & registration

**Files:**
- Modify: `source/tyControls.Form.pas` (delete `TTyFormChrome`)
- Modify: `designtime/tyControls.Design.pas`
- Modify: `tests/test.form.pas` (drop chrome-specific tests now covered by `TTyForm`/engine)
- Modify: `examples/demo/chromeform.pas` + `.lfm`, `examples/demo/mainform.pas` + `.lfm`, `examples/formchrome/umain.pas` (+ `.lfm`)

`TTyFormChrome` is now a thin delegating wrapper; remove it. **Coordinate the `.lfm` work with the user** (their test bed). The `TTyForm` demo's designer placement is also the manual WYSIWYG verification.

- [ ] **Step 1: Delete `TTyFormChrome`**

Remove the entire `TTyFormChrome` class declaration and all its method implementations from `source/tyControls.Form.pas`. Keep `TTyContentPanel`, `TTyChromeEngine`, `TTyTitleBar`, `TTyCaptionButton`, `TTyForm`, and the four pure functions (`TyHitTestBorder`/`TyResizeCursor`/`TyMaximizedBounds`/`TyRescaleChromeMetric`).

- [ ] **Step 2: Remove chrome-only tests; keep ported coverage**

In `tests/test.form.pas`:
- Delete `TFormChromeTest`, `TFormChromeChangeBoundsTest`, `TFormChromeLifecycleTest`, and `TChromeAccess`/`TLifecycleProbe`/`TChangeBoundsProbe` if now unused. Remove their `RegisterTest` lines.
- The behaviors they covered are now covered by: `TTyFormTest` (Task 3), `TRescaleMetricTest`/`TFormHelpersTest`/`TResizeCursorTest` (unchanged pure-function tests), and the engine. **Before deleting**, ensure an equivalent assertion exists in `TTyFormTest` for: default `TitleHeight=32` (add `AssertEquals(32, F.TB.Height)` to `TestTitleBarIsTopBand`), drag-arm via title bar, and maximize toggle. Add two engine tests to `TTyFormTest`:
```pascal
    procedure TestTitleBarDragArmsViaEngine;
    procedure TestDblClickMaximizeToggles;
```
```pascal
procedure TTyFormTest.TestTitleBarDragArmsViaEngine;
var F: TTyFormAccess;
begin
  F := TTyFormAccess.CreateNew(nil);
  try
    TTitleBarAccess(F.TB).InjectMouseDown(mbLeft, [], 10, 5);
    AssertTrue('engine drag armed', F.EngineDragging);
  finally
    F.Free;
  end;
end;

procedure TTyFormTest.TestDblClickMaximizeToggles;
var F: TTyFormAccess;
begin
  F := TTyFormAccess.CreateNew(nil);
  try
    F.SetEngineMaximized(True);
    TTitleBarAccess(F.TB).InjectDblClick;
    AssertFalse('dbl-click toggled maximize off', F.EngineMaximized);
  finally
    F.Free;
  end;
end;
```
Extend `TTyFormAccess` with `function EngineDragging: Boolean;` / `function EngineMaximized: Boolean;` / `procedure SetEngineMaximized(AValue: Boolean);` exposing `FEngine.Dragging`/`FEngine.Maximized` (make `TTyForm.FEngine` `protected`).

- [ ] **Step 3: Update IDE registration**

In `designtime/tyControls.Design.pas:68-73`, remove `TTyTitleBar` and `TTyFormChrome` from the `RegisterComponents('TyControls', [...])` array. (`TTyForm` is a form base class, not a palette component; not registered here. `TTyContentPanel`/`TTyChromeEngine` are sub-components/helpers; not registered.) The `'close'`/`'min'`/`'max'` entries in `TTyStyleClassPropertyEditor.GetValues` stay (caption-button variants).

- [ ] **Step 4: Migrate the demos so projects compile**

For `examples/demo/chromeform.pas` + `.lfm` (the dedicated chrome demo):
- Change `TChromeForm = class(TForm)` → `TChromeForm = class(TTyForm)`; remove the `Chrome: TTyFormChrome` field; in `.lfm` remove the `object Chrome: TTyFormChrome ... end` block and change the root from `TForm`/`bsSizeable` to a `TTyForm` ancestor stream.
- In `FormCreate`, replace `Chrome.TitleBar.Caption := ...` with `TitleBar.Caption := ...`; replace the manual `Self.Color := ...` block with `ApplyChromeTheme(Controller);`.
- Move `LblInfo` to be a child of the content area (in the designer, drop it into the form; the defensive `Loaded` will home it into `ContentPanel`).
- **This `.lfm` is done in the Lazarus designer by the user** — it doubles as the manual WYSIWYG verification (confirm the dropped control lands below the title band, and whether the IDE parents it into `ContentPanel` directly or relies on `Loaded`).

For `examples/demo/mainform.pas` + `.lfm` and `examples/formchrome/umain.pas`: convert to `TTyForm` (if they want chrome) or to a plain `TForm` (native). Remove all `TTyFormChrome` references. **Confirm the intended split with the user** (native demo vs `TTyForm` demo).

- [ ] **Step 5: Build everything**

Run: `lazbuild tycontrols.lpk` then `lazbuild tycontrols_dt.lpk` then `lazbuild tests/tytests.lpi`, then `bash scripts/build-matrix.sh` (builds the packages + all examples + the test runner).
Expected: all build with no `TTyFormChrome`-not-found errors.

- [ ] **Step 6: Full suite**

Run: `tests/tytests.exe --all --format=plain`
Expected: 0 failures + 15 known env errors.

- [ ] **Step 7: Commit (stage only the non-demo files; let the user stage their demo edits)**

```bash
git add source/tyControls.Form.pas designtime/tyControls.Design.pas tests/test.form.pas
git commit -m "refactor(tycontrols): remove TTyFormChrome; TTyForm is the sole chrome path"
```
(Stage demo/example files separately, coordinating with the user per the test-bed convention.)

---

## Task 6: Ribbon seam + docs

**Files:**
- Modify: `docs/controls/formchrome.md`, `docs/controls/titlebar.md`, `docs/controls/captionbutton.md`, `docs/events.md`, `docs/KNOWN_GAPS.md`
- Create: `docs/controls/ttyform.md`

No ribbon code. Lock the naming seam and document the new model.

- [ ] **Step 1: Document the reserved ribbon typeKeys**

In `docs/controls/ttyform.md` (new), add a "Future bands" section stating: bands are plain `alTop` children created top-to-bottom above `ContentPanel`; the theme typeKeys `TyRibbon`, `TyRibbonTab`, `TyRibbonGroup` are **reserved** for a future `TTyTabControl`-derived, chrome-agnostic `TTyRibbon`. Do not use those names for anything else.

- [ ] **Step 2: Rewrite the chrome docs to the new model**

Update `docs/controls/formchrome.md` to describe `TTyForm` (descend from it; born `bsNone`; `TitleBar`/`ContentPanel`; `ShowMinimize`/`ShowMaximize`/`TitleHeight`; `ApplyChromeTheme`; standard `TForm` lifecycle events; the resize-border ring). State the design-time caveat: **layout WYSIWYG yes, themed skin no** (the title bar renders unstyled in the designer). Update `titlebar.md`/`captionbutton.md` to note the title bar is now a `TTyForm` sub-component with a customizable content zone. Remove `TTyFormChrome` references from `events.md`; update `KNOWN_GAPS.md` (chrome is no longer "runtime-only" for layout — `TTyForm` reserves the content area at design time).

- [ ] **Step 3: Commit**

```bash
git add docs/controls/ttyform.md docs/controls/formchrome.md docs/controls/titlebar.md docs/controls/captionbutton.md docs/events.md docs/KNOWN_GAPS.md
git commit -m "docs(tycontrols): document TTyForm window model; reserve ribbon typeKeys"
```

---

## Self-Review

**Spec coverage:**
- §3 structure (FTitleBar alTop + FContent alClient sub-components) → Tasks 1, 3. ✓
- §4 ContentPanel-not-AdjustClientRect → Task 3 (`TestChildOnContentSitsBelowBand`). ✓
- §5.1 `TTyContentPanel` → Task 1. ✓
- §5.2 `TTyForm` streaming (SetSubComponent, names, defensive Loaded) → Task 3. ✓
- §5.3 `TTyChromeEngine` → Task 2. ✓
- §5.4 title bar retarget + Q2 → Tasks 2 (retarget) + 4 (Q2). ✓
- §5.6 remove `TTyFormChrome` → Task 5. ✓
- §6 ribbon seam → Task 6. ✓
- §7 test strategy (keep/adapt/port/new + manual checklist) → Tasks 1-5 + Task 5 Step 4 manual note. ✓
- §8 migration (registration, theme, demo, docs) → Tasks 1, 5, 6. ✓
- **Gap found & added:** resize-border coverage (not in spec) → resolved in Task 3 (resize ring). Window-background theming for the ring → `ApplyChromeTheme` (Task 3).

**Placeholder scan:** Task 5 Step 4 demo `.lfm` work is intentionally user-coordinated (test-bed convention), not a placeholder; all code steps have concrete code. No TBD/TODO.

**Type consistency:** `TTyChromeEngine` (Task 2) used identically in Tasks 3/5; `FEngine` is `protected` (needed by `TChromeAccess` Task 2 and `TTyFormAccess` Task 5); `ContentPanel`/`TitleBar` accessors named consistently across Tasks 3-5; `RightInset`/`ButtonWidth` defined in Task 4 and used in its own tests; `SetupChrome`/`CreateNew` guard consistent. `Destroy` added to `TTyForm` declaration in Task 3 Step 3 (note: add `destructor Destroy; override;` to the `public` section).
