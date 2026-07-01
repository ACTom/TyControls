# Form Chrome P1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `TTyForm`'s caption buttons follow standard `BorderIcons`, lock the form to `bsNone`, gate maximize via `Resizable`, give `TTyTitleBar` per-button switches, and guard TitleBar association to the owning form.

**Architecture:** A pure function `TyResolveCaptionButtons(BorderIcons, Resizable)` decides which of min/max/close show. `TTyTitleBar` exposes `ShowMinimize/ShowMaximize/ShowClose` that proxy the button `Visible`. `TTyForm.SyncCaptionButtons` pushes the resolved set onto its associated bar whenever `BorderIcons`/`Resizable`/association changes. `BorderStyle` is coerced to `bsNone` and hidden from the Object Inspector.

**Tech Stack:** Lazarus/FPC, LCL, `source/tyControls.Form.pas`, `designtime/tyControls.Design.pas`, headless fpcunit (`tests/test.form.pas`).

**Branch:** `feat/form-chrome` (already checked out). **Spec:** `docs/superpowers/specs/2026-07-01-form-chrome-p1-design.md`.

**Build/test commands (run from repo root, git-bash):**
- Lib: `lazbuild tycontrols.lpk 2>&1 | grep -iE "error|fatal"; echo exit ${PIPESTATUS[0]}`
- DT: `lazbuild tycontrols_dt.lpk 2>&1 | grep -iE "error|fatal"; echo exit ${PIPESTATUS[0]}`
- Tests: `lazbuild tests/tytests.lpi >/dev/null 2>&1 && ./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of (run|failures|errors)"`
- Baseline before starting: **1532 run / 0 failures / 11 errors** (the 11 errors are pre-existing and unrelated; keep failures at 0 and errors at 11).

---

### Task 1: `TyResolveCaptionButtons` pure function + tests

**Files:**
- Modify: `source/tyControls.Form.pas` — add type + function near `TyResizeHitFor` (interface ~line 244–248; implementation).
- Test: `tests/test.form.pas` — new `TCaptionButtonsTest`.

- [ ] **Step 1: Write the failing test.** In `tests/test.form.pas`, add to the `type` section (after the existing test classes, before the `implementation`):

```pascal
  { Pure caption-button resolution: close<=biSystemMenu, min<=biMinimize,
    max<=(biMaximize and Resizable). }
  TCaptionButtonsTest = class(TTestCase)
  published
    procedure TestAllIconsResizable;
    procedure TestMaximizeNeedsResizable;
    procedure TestEmptyIconsNoButtons;
    procedure TestCloseOnly;
    procedure TestMinCloseNoMaxIcon;
  end;
```

In the `implementation` section add:

```pascal
procedure TCaptionButtonsTest.TestAllIconsResizable;
begin
  AssertTrue('all three when all icons + resizable',
    TyResolveCaptionButtons([biSystemMenu, biMinimize, biMaximize], True)
      = [cbfMinimize, cbfMaximize, cbfClose]);
end;

procedure TCaptionButtonsTest.TestMaximizeNeedsResizable;
begin
  AssertTrue('no max when not resizable, even with biMaximize',
    TyResolveCaptionButtons([biSystemMenu, biMinimize, biMaximize], False)
      = [cbfMinimize, cbfClose]);
end;

procedure TCaptionButtonsTest.TestEmptyIconsNoButtons;
begin
  AssertTrue('empty icons -> no buttons',
    TyResolveCaptionButtons([], True) = []);
end;

procedure TCaptionButtonsTest.TestCloseOnly;
begin
  AssertTrue('systemmenu only -> close only',
    TyResolveCaptionButtons([biSystemMenu], True) = [cbfClose]);
end;

procedure TCaptionButtonsTest.TestMinCloseNoMaxIcon;
begin
  AssertTrue('min+close, no maximize icon -> no max even if resizable',
    TyResolveCaptionButtons([biSystemMenu, biMinimize], True)
      = [cbfMinimize, cbfClose]);
end;
```

At the bottom `initialization` block of `tests/test.form.pas`, add `RegisterTest(TCaptionButtonsTest);`.

- [ ] **Step 2: Run tests, verify this fails to compile** (`TyResolveCaptionButtons` / `cbfMinimize` undefined).

Run: `lazbuild tests/tytests.lpi 2>&1 | grep -iE "error|identifier not found"`
Expected: FAIL — `Identifier not found "TyResolveCaptionButtons"`.

- [ ] **Step 3: Implement.** In `source/tyControls.Form.pas`, in the `type` section near line 20 (after `TTyCaptionButtonKind`), add:

```pascal
  TTyCaptionButtonFlag  = (cbfMinimize, cbfMaximize, cbfClose);
  TTyCaptionButtonFlags = set of TTyCaptionButtonFlag;
```

In the `interface` after `TyResizeHitFor` (line ~248) add the forward declaration:

```pascal
{ Which caption buttons a form's chrome shows, from the standard BorderIcons plus the
  Resizable flag: close<=biSystemMenu, minimize<=biMinimize, maximize<=(biMaximize and
  AResizable) — a fixed-size window shows no maximize. Pure (no window handle) so it is
  unit-tested directly. }
function TyResolveCaptionButtons(ABorderIcons: TBorderIcons; AResizable: Boolean): TTyCaptionButtonFlags;
```

In the `implementation` (right after the `TyResizeHitFor` body) add:

```pascal
function TyResolveCaptionButtons(ABorderIcons: TBorderIcons; AResizable: Boolean): TTyCaptionButtonFlags;
begin
  Result := [];
  if biSystemMenu in ABorderIcons then Include(Result, cbfClose);
  if biMinimize in ABorderIcons then Include(Result, cbfMinimize);
  if (biMaximize in ABorderIcons) and AResizable then Include(Result, cbfMaximize);
end;
```

- [ ] **Step 4: Run tests, verify pass.**

Run: `lazbuild tests/tytests.lpi >/dev/null 2>&1 && ./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of (run|failures|errors)"`
Expected: failures 0, errors 11, run count increased by 5.

- [ ] **Step 5: Commit.**

```bash
git add source/tyControls.Form.pas tests/test.form.pas
git commit -m "feat(form): TyResolveCaptionButtons pure fn (BorderIcons+Resizable -> button set)"
```

---

### Task 2: `TTyTitleBar.ShowMinimize/ShowMaximize/ShowClose` switches + test

**Files:**
- Modify: `source/tyControls.Form.pas` — `TTyTitleBar` (decl ~45–88; impl ~570–593).
- Test: `tests/test.form.pas` — new `TTitleBarSwitchesTest`.

- [ ] **Step 1: Write the failing test.** Add to `type` in `tests/test.form.pas`:

```pascal
  { A standalone TitleBar (no owning form): the three Show* switches toggle the
    matching caption button Visible. }
  TTitleBarSwitchesTest = class(TTestCase)
  published
    procedure TestDefaultsAllVisible;
    procedure TestHideMinimize;
    procedure TestHideMaximize;
    procedure TestHideClose;
  end;
```

Add to `implementation`:

```pascal
procedure TTitleBarSwitchesTest.TestDefaultsAllVisible;
var bar: TTyTitleBar;
begin
  bar := TTyTitleBar.Create(nil);
  try
    AssertTrue('min default', bar.ShowMinimize);
    AssertTrue('max default', bar.ShowMaximize);
    AssertTrue('close default', bar.ShowClose);
  finally bar.Free; end;
end;

procedure TTitleBarSwitchesTest.TestHideMinimize;
var bar: TTyTitleBar;
begin
  bar := TTyTitleBar.Create(nil);
  try
    bar.ShowMinimize := False;
    AssertFalse('min hidden', bar.MinButton.Visible);
    AssertTrue('max still', bar.MaxButton.Visible);
  finally bar.Free; end;
end;

procedure TTitleBarSwitchesTest.TestHideMaximize;
var bar: TTyTitleBar;
begin
  bar := TTyTitleBar.Create(nil);
  try
    bar.ShowMaximize := False;
    AssertFalse('max hidden', bar.MaxButton.Visible);
  finally bar.Free; end;
end;

procedure TTitleBarSwitchesTest.TestHideClose;
var bar: TTyTitleBar;
begin
  bar := TTyTitleBar.Create(nil);
  try
    bar.ShowClose := False;
    AssertFalse('close hidden', bar.CloseButton.Visible);
  finally bar.Free; end;
end;
```

Add `RegisterTest(TTitleBarSwitchesTest);` to the `initialization` block.

- [ ] **Step 2: Run, verify fails** (`ShowMinimize` not a member of `TTyTitleBar`).

Run: `lazbuild tests/tytests.lpi 2>&1 | grep -iE "error|identifier"`
Expected: FAIL — member `ShowMinimize` not found.

- [ ] **Step 3: Implement.** In `source/tyControls.Form.pas`, `TTyTitleBar` `private` section (after `function LeftInsetPx: Integer;`, line ~58) add:

```pascal
    function GetShowMinimize: Boolean;
    function GetShowMaximize: Boolean;
    function GetShowClose: Boolean;
    procedure SetShowMinimize(AValue: Boolean);
    procedure SetShowMaximize(AValue: Boolean);
    procedure SetShowClose(AValue: Boolean);
```

In the `published` section of `TTyTitleBar` (after `ButtonWidth`, line ~87) add:

```pascal
    { Per-button visibility for a STANDALONE title bar (not associated with a TTyForm).
      When associated, the owning form drives these from its BorderIcons + Resizable. }
    property ShowMinimize: Boolean read GetShowMinimize write SetShowMinimize default True;
    property ShowMaximize: Boolean read GetShowMaximize write SetShowMaximize default True;
    property ShowClose: Boolean read GetShowClose write SetShowClose default True;
```

In the implementation (after `SetTitleAlignment`, line ~593) add:

```pascal
function TTyTitleBar.GetShowMinimize: Boolean;
begin Result := (FMinButton = nil) or FMinButton.Visible; end;

function TTyTitleBar.GetShowMaximize: Boolean;
begin Result := (FMaxButton = nil) or FMaxButton.Visible; end;

function TTyTitleBar.GetShowClose: Boolean;
begin Result := (FCloseButton = nil) or FCloseButton.Visible; end;

procedure TTyTitleBar.SetShowMinimize(AValue: Boolean);
begin
  if FMinButton = nil then Exit;
  if FMinButton.Visible = AValue then Exit;
  FMinButton.Visible := AValue;
  LayoutButtons;
end;

procedure TTyTitleBar.SetShowMaximize(AValue: Boolean);
begin
  if FMaxButton = nil then Exit;
  if FMaxButton.Visible = AValue then Exit;
  FMaxButton.Visible := AValue;
  LayoutButtons;
end;

procedure TTyTitleBar.SetShowClose(AValue: Boolean);
begin
  if FCloseButton = nil then Exit;
  if FCloseButton.Visible = AValue then Exit;
  FCloseButton.Visible := AValue;
  LayoutButtons;
end;
```

- [ ] **Step 4: Run, verify pass.** (failures 0, errors 11, run +4.)

- [ ] **Step 5: Commit.**

```bash
git add source/tyControls.Form.pas tests/test.form.pas
git commit -m "feat(titlebar): ShowMinimize/ShowMaximize/ShowClose switches for standalone use"
```

---

### Task 3: `TTyForm.BorderStyle` locked to `bsNone` + test

**Files:**
- Modify: `source/tyControls.Form.pas` — `TTyForm` (decl ~139–242; impl).
- Test: `tests/test.form.pas` — new `TFormBorderStyleTest`.

- [ ] **Step 1: Write the failing test.** Add to `type`:

```pascal
  { TTyForm is always bsNone: assigning any other border style is coerced back. }
  TFormBorderStyleTest = class(TTestCase)
  published
    procedure TestDefaultIsNone;
    procedure TestAssignSizeableCoercedToNone;
  end;
```

Add to `implementation`:

```pascal
procedure TFormBorderStyleTest.TestDefaultIsNone;
var f: TTyForm;
begin
  f := TTyForm.CreateNew(nil);
  try AssertTrue('default bsNone', f.BorderStyle = bsNone);
  finally f.Free; end;
end;

procedure TFormBorderStyleTest.TestAssignSizeableCoercedToNone;
var f: TTyForm;
begin
  f := TTyForm.CreateNew(nil);
  try
    f.BorderStyle := bsSizeable;
    AssertTrue('coerced back to bsNone', f.BorderStyle = bsNone);
  finally f.Free; end;
end;
```

Add `RegisterTest(TFormBorderStyleTest);` to `initialization`.

- [ ] **Step 2: Run, verify fails** (the assign takes effect, so `TestAssignSizeableCoercedToNone` FAILS with `bsNone expected`).

- [ ] **Step 3: Implement.** In `TTyForm` `private` (after `SetResizable`, line ~172) add:

```pascal
    function GetBorderStyleTy: TFormBorderStyle;
    procedure SetBorderStyleTy(AValue: TFormBorderStyle);
```

In `TTyForm` `published` (after `Resizable`, line ~241) add:

```pascal
    { Locked: a TTyForm is a borderless custom-chrome window. Any assignment is coerced
      to bsNone; hidden from the Object Inspector via a design-time property editor. }
    property BorderStyle: TFormBorderStyle read GetBorderStyleTy write SetBorderStyleTy default bsNone;
```

In the implementation add:

```pascal
function TTyForm.GetBorderStyleTy: TFormBorderStyle;
begin Result := inherited BorderStyle; end;

procedure TTyForm.SetBorderStyleTy(AValue: TFormBorderStyle);
begin
  if inherited BorderStyle <> bsNone then inherited BorderStyle := bsNone;
end;
```

- [ ] **Step 4: Run, verify pass.** (failures 0, errors 11, run +2.)

- [ ] **Step 5: Commit.**

```bash
git add source/tyControls.Form.pas tests/test.form.pas
git commit -m "feat(form): lock BorderStyle to bsNone (coercing setter)"
```

---

### Task 4: Remove `TTyForm.ShowMinimize/ShowMaximize` + fix references + demo/comment

**Files:**
- Modify: `source/tyControls.Form.pas` — remove fields/decls/setters/props/ctor-init; fix `ApplyResizeStrategy` line ~1263.
- Modify: `examples/demo/mainform.lfm` — replace `ShowMaximize = False`.
- Modify: `designtime/tyControls.Design.pas` — the comment at line ~536.

- [ ] **Step 1: Remove from `TTyForm`.** In `source/tyControls.Form.pas`:
  - Delete fields (lines ~143–144): `FShowMinimize: Boolean;` and `FShowMaximize: Boolean;`.
  - Delete private setter decls (lines ~170–171): `procedure SetShowMinimize(AValue: Boolean);` and `procedure SetShowMaximize(AValue: Boolean);`.
  - Delete published props (lines ~233–234): the `ShowMinimize` and `ShowMaximize` property lines.
  - Delete setter bodies `SetShowMinimize` (lines ~1215–1223) and `SetShowMaximize` (lines ~1225–1233).
  - In `SetupChrome` (lines ~931–939) delete `FShowMinimize := True;` and `FShowMaximize := True;` (keep `BorderStyle := bsNone;` and `FResizable := True;`).

- [ ] **Step 2: Fix the one remaining reference.** In `ApplyResizeStrategy`, line ~1263, change:

```pascal
      FResizable and FShowMaximize);             // allow native maximize (WS_MAXIMIZEBOX)
```
to:
```pascal
      FResizable and (biMaximize in BorderIcons));   // allow native maximize (WS_MAXIMIZEBOX)
```

- [ ] **Step 3: Build the lib, verify it compiles clean.**

Run: `lazbuild tycontrols.lpk 2>&1 | grep -iE "error|fatal"; echo exit ${PIPESTATUS[0]}`
Expected: no error lines, exit 0. (If `FShowMaximize`/`FShowMinimize` still referenced anywhere, the compiler names the line — fix it.)

- [ ] **Step 4: Update the demo `.lfm`.** In `examples/demo/mainform.lfm`, line ~14, the `DemoMainForm` had `ShowMaximize = False`. Remove that line and, if the form object does not already list `BorderIcons`, add on its own line within the form object's properties:

```
  BorderIcons = [biSystemMenu, biMinimize]
```

(This reproduces "no maximize" via the new model. Do NOT touch any other demo control — per project rule, demo edits stay in the `.lfm`.)

- [ ] **Step 5: Update the stale comment.** In `designtime/tyControls.Design.pas`, line ~536, change the parenthetical `(TitleBar / TitleHeight / ShowMinimize / ShowMaximize)` to `(TitleBar / TitleHeight / BorderIcons / Resizable)`.

- [ ] **Step 6: Build lib + dt + demo + tests.**

Run:
```bash
lazbuild tycontrols.lpk 2>&1 | grep -iE "error|fatal"; echo lib ${PIPESTATUS[0]}
lazbuild tycontrols_dt.lpk 2>&1 | grep -iE "error|fatal"; echo dt ${PIPESTATUS[0]}
lazbuild examples/demo/demo.lpi 2>&1 | grep -iE "error|fatal|Linking"; echo demo ${PIPESTATUS[0]}
lazbuild tests/tytests.lpi >/dev/null 2>&1 && ./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of (run|failures|errors)"
```
Expected: all exit 0, demo links, failures 0 / errors 11.

- [ ] **Step 7: Commit.**

```bash
git add source/tyControls.Form.pas examples/demo/mainform.lfm designtime/tyControls.Design.pas
git commit -m "refactor(form): remove ShowMinimize/ShowMaximize (BorderIcons is the source of truth)"
```

---

### Task 5: `SyncCaptionButtons` — BorderIcons/Resizable drive the associated bar + tests

**Files:**
- Modify: `source/tyControls.Form.pas` — add `SyncCaptionButtons`; redeclare `BorderIcons`; wire into `SetResizable`, `WireTitleBarButtons`, `SetTitleBar`, `Loaded`.
- Test: `tests/test.form.pas` — new `TFormDrivesBarTest`.

- [ ] **Step 1: Write the failing test.** Add to `type`:

```pascal
  { An associated form drives its bar's buttons from BorderIcons + Resizable.
    Design-mode is used so SetTitleBar does not arm the runtime chrome engine. }
  TFormDrivesBarTest = class(TTestCase)
  private
    function MakeFormWithBar: TTyForm;
  published
    procedure TestBorderIconsHideMinimize;
    procedure TestCloseOnly;
    procedure TestResizableFalseHidesMaximize;
  end;
```

Add to `implementation`:

```pascal
function TFormDrivesBarTest.MakeFormWithBar: TTyForm;
var bar: TTyTitleBar;
begin
  Result := TTyForm.CreateNew(nil);
  Result.SetDesigning(True, False);       // avoid arming the runtime engine (no Monitor/handle)
  bar := TTyTitleBar.Create(Result);      // Owner = the form
  bar.Parent := Result;
  Result.TitleBar := bar;
end;

procedure TFormDrivesBarTest.TestBorderIconsHideMinimize;
var f: TTyForm;
begin
  f := MakeFormWithBar;
  try
    f.BorderIcons := [biSystemMenu, biMaximize];   // no biMinimize
    AssertFalse('min hidden', f.TitleBar.MinButton.Visible);
    AssertTrue('max shown', f.TitleBar.MaxButton.Visible);
    AssertTrue('close shown', f.TitleBar.CloseButton.Visible);
  finally f.Free; end;
end;

procedure TFormDrivesBarTest.TestCloseOnly;
var f: TTyForm;
begin
  f := MakeFormWithBar;
  try
    f.BorderIcons := [biSystemMenu];
    AssertTrue('close', f.TitleBar.CloseButton.Visible);
    AssertFalse('no min', f.TitleBar.MinButton.Visible);
    AssertFalse('no max', f.TitleBar.MaxButton.Visible);
  finally f.Free; end;
end;

procedure TFormDrivesBarTest.TestResizableFalseHidesMaximize;
var f: TTyForm;
begin
  f := MakeFormWithBar;
  try
    f.BorderIcons := [biSystemMenu, biMinimize, biMaximize];
    f.Resizable := False;
    AssertFalse('max hidden when not resizable', f.TitleBar.MaxButton.Visible);
    AssertTrue('min still', f.TitleBar.MinButton.Visible);
  finally f.Free; end;
end;
```

Add `RegisterTest(TFormDrivesBarTest);` to `initialization`.

- [ ] **Step 2: Run, verify fails.** Without the sync, setting `BorderIcons` leaves all buttons visible, so `TestBorderIconsHideMinimize` FAILS (`min hidden` expected False got True).

- [ ] **Step 3: Implement `SyncCaptionButtons` + BorderIcons redeclare.** In `TTyForm` `private` (after the border-style accessors from Task 3) add:

```pascal
    function GetBorderIconsTy: TBorderIcons;
    procedure SetBorderIconsTy(AValue: TBorderIcons);
    procedure SyncCaptionButtons;   // push TyResolveCaptionButtons(BorderIcons,Resizable) onto the bar
```

In `TTyForm` `published` (after the `BorderStyle` line from Task 3) add:

```pascal
    { Standard border icons drive the caption buttons: biSystemMenu->close,
      biMinimize->minimize, biMaximize->maximize (only when Resizable). }
    property BorderIcons: TBorderIcons read GetBorderIconsTy write SetBorderIconsTy
      default [biSystemMenu, biMinimize, biMaximize];
```

Implementation:

```pascal
function TTyForm.GetBorderIconsTy: TBorderIcons;
begin Result := inherited BorderIcons; end;

procedure TTyForm.SetBorderIconsTy(AValue: TBorderIcons);
begin
  inherited BorderIcons := AValue;
  SyncCaptionButtons;
end;

procedure TTyForm.SyncCaptionButtons;
var flags: TTyCaptionButtonFlags;
begin
  if FTitleBar = nil then Exit;
  flags := TyResolveCaptionButtons(BorderIcons, FResizable);
  FTitleBar.ShowMinimize := cbfMinimize in flags;
  FTitleBar.ShowMaximize := cbfMaximize in flags;
  FTitleBar.ShowClose    := cbfClose in flags;
end;
```

- [ ] **Step 4: Wire the sync into the four trigger points.**

  a. `SetResizable` (lines ~1235–1244): replace the max-button-enable block

```pascal
  if (FTitleBar <> nil) and (FTitleBar.MaxButton <> nil) then
    FTitleBar.MaxButton.Enabled := AValue;
```
  with
```pascal
  SyncCaptionButtons;   // Resizable gates the maximize button (hide, not just disable)
```

  b. `WireTitleBarButtons` (lines ~1102–1108): make it sync visibility (design + runtime) before the runtime-only click wiring:

```pascal
procedure TTyForm.WireTitleBarButtons;
begin
  if FTitleBar = nil then Exit;
  SyncCaptionButtons;                               // visibility: design-time too
  if csDesigning in ComponentState then Exit;       // click handlers: runtime only
  if FTitleBar.MinButton <> nil then FTitleBar.MinButton.OnClick := @DoMinimizeClick;
  if FTitleBar.MaxButton <> nil then FTitleBar.MaxButton.OnClick := @DoMaxRestoreClick;
  if FTitleBar.CloseButton <> nil then FTitleBar.CloseButton.OnClick := @DoCloseClick;
end;
```

  c. `SetTitleBar` (lines ~984–994): inside `if AValue <> nil then begin ... end;`, after `AValue.FreeNotification(Self);`, add `SyncCaptionButtons;` (so an association immediately reflects the current BorderIcons; safe if buttons are still nil — the Show* setters guard nil, and the bar ctor tail re-syncs via WireTitleBarButtons once the buttons exist).

  d. `Loaded` (find `procedure TTyForm.Loaded;`): add `SyncCaptionButtons;` as the last statement before its final `end;` (so a streamed BorderIcons + streamed bar sync after load).

- [ ] **Step 5: Run, verify pass.** (failures 0, errors 11, run +3.)

- [ ] **Step 6: Commit.**

```bash
git add source/tyControls.Form.pas tests/test.form.pas
git commit -m "feat(form): SyncCaptionButtons — BorderIcons+Resizable drive the associated title bar"
```

---

### Task 6: Own-form association guard + test

**Files:**
- Modify: `source/tyControls.Form.pas` — `SetTitleBar` (line ~968).
- Test: `tests/test.form.pas` — new `TTitleBarGuardTest`.

- [ ] **Step 1: Write the failing test.** Add to `type`:

```pascal
  { A TitleBar belonging to another form cannot be associated. }
  TTitleBarGuardTest = class(TTestCase)
  published
    procedure TestForeignBarRaises;
    procedure TestOwnBarSucceeds;
  end;
```

Add to `implementation` (needs `SysUtils` in uses — already present):

```pascal
procedure TTitleBarGuardTest.TestForeignBarRaises;
var f1, f2: TTyForm; bar: TTyTitleBar; raised: Boolean;
begin
  f1 := TTyForm.CreateNew(nil); f2 := TTyForm.CreateNew(nil);
  f1.SetDesigning(True, False); f2.SetDesigning(True, False);
  bar := TTyTitleBar.Create(f2); bar.Parent := f2;   // belongs to f2
  raised := False;
  try
    f1.TitleBar := bar;
  except
    on E: EInvalidOperation do raised := True;
  end;
  try AssertTrue('foreign bar rejected', raised);
  finally f1.Free; f2.Free; end;
end;

procedure TTitleBarGuardTest.TestOwnBarSucceeds;
var f: TTyForm; bar: TTyTitleBar;
begin
  f := TTyForm.CreateNew(nil); f.SetDesigning(True, False);
  bar := TTyTitleBar.Create(f); bar.Parent := f;
  try
    f.TitleBar := bar;
    AssertTrue('own bar associated', f.TitleBar = bar);
  finally f.Free; end;
end;
```

Add `RegisterTest(TTitleBarGuardTest);` to `initialization`.

- [ ] **Step 2: Run, verify fails** (`TestForeignBarRaises` FAILS — no exception raised, `raised` stays False).

- [ ] **Step 3: Implement.** In `SetTitleBar`, immediately after `if AValue = FTitleBar then Exit;` (line ~970) add:

```pascal
  if (AValue <> nil) and (AValue.Owner <> Self) and (GetParentForm(AValue) <> Self) then
    raise EInvalidOperation.Create('TTyTitleBar can only be associated with the form it belongs to');
```

(`EInvalidOperation` is in `SysUtils`; `GetParentForm` is in `Forms` — both already used by `tyControls.Form.pas`.)

- [ ] **Step 4: Run, verify pass.** (failures 0, errors 11, run +2.)

- [ ] **Step 5: Commit.**

```bash
git add source/tyControls.Form.pas tests/test.form.pas
git commit -m "feat(form): SetTitleBar guards against a cross-form title bar (EInvalidOperation)"
```

---

### Task 7: Hide `BorderStyle` from the Object Inspector (design-time)

**Files:**
- Modify: `designtime/tyControls.Design.pas` — `Register` (line ~526+); ensure `PropEdits` in uses.

- [ ] **Step 1: Confirm `PropEdits` is in the `uses` clause** of `designtime/tyControls.Design.pas` (it uses `RegisterPropertyEditor`, so it is). `THiddenPropertyEditor` lives there.

- [ ] **Step 2: Register the hidden editor.** In `Register`, after the existing `RegisterPropertyEditor(... TTyForm, 'About', ...)` line (~561), add:

```pascal
  // BorderStyle is locked to bsNone (TTyForm is a borderless custom-chrome window) —
  // hide it from the Object Inspector so it is neither shown nor editable.
  RegisterPropertyEditor(TypeInfo(TFormBorderStyle), TTyForm, 'BorderStyle', THiddenPropertyEditor);
```

- [ ] **Step 3: Build the dt package.**

Run: `lazbuild tycontrols_dt.lpk 2>&1 | grep -iE "error|fatal"; echo exit ${PIPESTATUS[0]}`
Expected: exit 0. (If `THiddenPropertyEditor` is unknown, add `PropEdits` to the `uses` clause.)

- [ ] **Step 4: Commit.**

```bash
git add designtime/tyControls.Design.pas
git commit -m "feat(design): hide TTyForm.BorderStyle from the Object Inspector"
```

---

### Task 8: Docs cleanup + full verification

**Files:**
- Modify: `docs/controls/ttyform.md`, `docs/controls/titlebar.md`, `docs/controls/formchrome.md`.

- [ ] **Step 1: Update the control docs.**
  - `docs/controls/ttyform.md` (lines ~62–63): remove the `ShowMinimize` / `ShowMaximize` rows; add a `BorderIcons` row (`biSystemMenu`→close, `biMinimize`→minimize, `biMaximize`→maximize when `Resizable`) and note `BorderStyle` is locked to `bsNone`.
  - `docs/controls/titlebar.md` (lines ~67, ~134): describe `ShowMinimize`/`ShowMaximize`/`ShowClose` as the standalone switches (drop the implication they live on the form); fix the code sample at ~134.
  - `docs/controls/formchrome.md` (lines ~19, ~49): replace the `Chrome.ShowMinimize/ShowMaximize` mapping and the comment with the `BorderIcons` model.

- [ ] **Step 2: Full build + test sweep.**

Run:
```bash
lazbuild tycontrols.lpk 2>&1 | grep -iE "error|fatal"; echo lib ${PIPESTATUS[0]}
lazbuild tycontrols_dt.lpk 2>&1 | grep -iE "error|fatal"; echo dt ${PIPESTATUS[0]}
lazbuild examples/demo/demo.lpi 2>&1 | grep -iE "error|fatal|Linking"; echo demo ${PIPESTATUS[0]}
lazbuild tests/tytests.lpi >/dev/null 2>&1 && ./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of (run|failures|errors)"
```
Expected: lib/dt/demo exit 0; failures 0; errors 11; run count = baseline + 16 (5+4+2+3+2 from Tasks 1,2,3,5,6).

- [ ] **Step 3: Commit.**

```bash
git add docs/controls/ttyform.md docs/controls/titlebar.md docs/controls/formchrome.md
git commit -m "docs: form chrome — BorderIcons-driven buttons, ShowClose, locked BorderStyle"
```

- [ ] **Step 4: Finish the branch.** Use superpowers:finishing-a-development-branch (verify tests, then present merge/PR options).

---

## Notes for the implementer

- **Do not run a real GUI.** All tests are headless fpcunit; the two form/bar integration tests use `SetDesigning(True, False)` so `SetTitleBar` never arms the runtime chrome engine (which would touch `Monitor`/the window handle).
- **Redeclaring inherited published properties** (`BorderStyle`, `BorderIcons`) in `TTyForm` is intentional and legal in FPC — the descendant declaration wins for RTTI/streaming; the getters/setters call `inherited` to reach the base storage.
- **Order matters:** Task 2 (bar switches) must land before Task 5 (the form calls `FTitleBar.ShowMinimize`). Task 4 (removal) before Task 5.
- **Baseline test numbers:** start 1532/0/11; after Task 8, expect ~1548/0/11.
