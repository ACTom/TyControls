# TTyNativeStyler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `TTyNativeStyler` component that harmonizes standard-LCL / third-party controls with the active TyControls theme — generic by default (third-party supported), gracefully skipping OS-drawn controls.

**Architecture:** Non-visual `TComponent`. On theme change it walks its `Root` subtree and, for each non-Ty control, resolves the closest Ty token (`TEdit→TyEdit`, …, else `TyPanel`) via the existing `Controller.Model.ResolveStyle`, then sets `Font.Color` (broad) and background `Color` (RTTI-detected, skipped for a small curated deny-list of OS-drawn classes). Lives on a new lightweight Controller change-listener.

**Tech Stack:** FPC RTTI (`TypInfo`: `IsPublishedProp`/`GetObjectProp`/`SetOrdProp`), LCL `TControl`/`TWinControl`/`TFont`, the existing `tyControls.StyleModel.ResolveStyle` + `TyColorToLCL`, `TMethodList` (Classes).

**Spec:** `docs/superpowers/specs/2026-06-26-native-styler-design.md`

**DEVIATION from spec (deliberate, lower-risk):** the spec proposed a new `TyNative` theme token for the generic fallback. Each theme file is fully self-contained (6 files × 104 rules), so a new token is disproportionate. Instead the styler falls back to the existing **`TyPanel`** token (present in every theme) — still 100% theme-driven, **zero theme-data / generator / golden-test changes**. A dedicated `TyNative` token remains a future option if theme authors want to style natives separately from panels.

**Baseline:** branch `feat/native-styler`. Suite 952 run / 0 failures / 11 known headless win32-1407 errors. Build: `lazbuild tycontrols.lpk`, `lazbuild tycontrols_dt.lpk`, `lazbuild tests/tytests.lpi`; run `./tests/tytests.exe -a --format=plain`.

**Key existing facts:**
- `TTyStyleController = class(TComponent)` (Controller.pas), public `Model: TTyStyleModel`, `Changed` at `:418` (loops `FControls`, invalidates). `Model.ResolveStyle(const ATypeKey, AStyleClass: string; AStates: TTyStateSet): TTyStyleSet`.
- `TTyStyleSet` (Types.pas): `Present: TTyPropSet`; `Background: TTyFill` (`Kind: TTyFillKind`, `Color: TTyColor`); `TextColor: TTyColor`; `FontName: string`; `FontSize: Integer`. `TyProp` members include `tpBackground`, `tpTextColor`, `tpFontName`, `tpFontSize`. `tfkSolid` is a `TTyFillKind`. `function TyColorToLCL(c: TTyColor): TColor`.
- Base control classes: `TTyGraphicControl` / `TTyCustomControl` (Base.pas) — used to skip self-theming TyControls.

---

## Task 1: Controller change-listener facility

A non-control observer (the styler) must re-run when the theme changes. Add a small multicast hook.

**Files:** Modify `source/tyControls.Controller.pas`; Test `tests/test.controller.changelistener.pas` (new) + `tests/tytests.lpr`

- [ ] **Step 1: Write the failing test.** Create `tests/test.controller.changelistener.pas`:

```pascal
unit test.controller.changelistener;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.Controller;
type
  TChangeListenerTest = class(TTestCase)
  private
    FHits: Integer;
    procedure OnCtlChanged(Sender: TObject);
  published
    procedure TestListenerFiresOnChanged;
    procedure TestRemovedListenerDoesNotFire;
  end;

implementation

procedure TChangeListenerTest.OnCtlChanged(Sender: TObject);
begin
  Inc(FHits);
end;

procedure TChangeListenerTest.TestListenerFiresOnChanged;
var Ctl: TTyStyleController;
begin
  FHits := 0;
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.AddChangeListener(@OnCtlChanged);
    Ctl.Changed;
    Ctl.Changed;
    AssertEquals('listener fired once per Changed', 2, FHits);
  finally
    Ctl.Free;
  end;
end;

procedure TChangeListenerTest.TestRemovedListenerDoesNotFire;
var Ctl: TTyStyleController;
begin
  FHits := 0;
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.AddChangeListener(@OnCtlChanged);
    Ctl.RemoveChangeListener(@OnCtlChanged);
    Ctl.Changed;
    AssertEquals('removed listener never fires', 0, FHits);
  finally
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TChangeListenerTest);
end.
```

- [ ] **Step 2: Register the test.** In `tests/tytests.lpr`, append `test.controller.changelistener` to the `uses` clause (after the current last entry `test.i18n`, with a comma before it and `;` after).

- [ ] **Step 3: Run to verify it fails.**
Run: `cd /d/Projects/ty-controls && lazbuild tests/tytests.lpi 2>&1 | grep -iE "error|fatal"`
Expected: a compile error — `AddChangeListener`/`RemoveChangeListener` not found (methods don't exist yet).

- [ ] **Step 4: Implement.** In `source/tyControls.Controller.pas`:
  (a) Ensure `Classes` is in the interface uses (it is — `TMethodList` lives there).
  (b) In the `private` section add a field: `FChangeListeners: TMethodList;`
  (c) In the `public` section add: `procedure AddChangeListener(AListener: TNotifyEvent); procedure RemoveChangeListener(AListener: TNotifyEvent);`
  (d) In the constructor (after `FControls := TFPList.Create;`) add: `FChangeListeners := TMethodList.Create;`
  (e) In the destructor (near `FControls.Free;`) add: `FChangeListeners.Free;`
  (f) Add the two methods (anywhere in the implementation):
```pascal
procedure TTyStyleController.AddChangeListener(AListener: TNotifyEvent);
begin
  FChangeListeners.Add(TMethod(AListener));
end;

procedure TTyStyleController.RemoveChangeListener(AListener: TNotifyEvent);
begin
  FChangeListeners.Remove(TMethod(AListener));
end;
```
  (g) In `Changed` (currently lines ~418-424), after the existing invalidate loop, add:
```pascal
  FChangeListeners.CallNotifyEvents(Self);   // notify non-control observers (e.g. TTyNativeStyler)
```
So `Changed` becomes:
```pascal
procedure TTyStyleController.Changed;
var
  i: Integer;
begin
  for i := FControls.Count - 1 downto 0 do
    TControl(FControls[i]).Invalidate;
  FChangeListeners.CallNotifyEvents(Self);
end;
```

- [ ] **Step 5: Run to verify it passes + no regression.**
Run: `cd /d/Projects/ty-controls && lazbuild tycontrols.lpk 2>&1 | grep -iE "error|fatal"; lazbuild tests/tytests.lpi 2>&1 | grep -iE "error|fatal"; ./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of (run|failures|errors)|TestListenerFiresOnChanged"`
Expected: builds exit 0; 954 run / 0 failures / 11 errors; the two new tests pass.

- [ ] **Step 6: Commit**

```bash
git add source/tyControls.Controller.pas tests/test.controller.changelistener.pas tests/tytests.lpr
git commit -m "feat(controller): change-listener facility (multicast TNotifyEvent fired in Changed)"
```

---

## Task 2: The `TTyNativeStyler` unit

**Files:** Create `source/tyControls.NativeStyler.pas`; Modify `tycontrols.lpk`

- [ ] **Step 1: Create the unit** with exactly this content:

```pascal
unit tyControls.NativeStyler;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, tyControls.Controller;

type
  { Fired for each candidate control before styling. Set AHandled := True to skip it (opt-out) or
    after applying your own custom styling (override). }
  TTyStyleControlEvent = procedure(Sender: TObject; AControl: TControl; var AHandled: Boolean) of object;

  { Non-visual: drop on a form, point Controller at the theme. On theme change it re-styles every
    eligible NON-Ty control under Root, borrowing the closest Ty token (TEdit->TyEdit, ..., else
    TyPanel). RTTI-generic: any control exposing a published Color/Font is themed (third-party
    included); OS-drawn classes in the deny-list keep their font but skip the background. Never
    runs at design time (would bake theme colors into the .lfm). }
  TTyNativeStyler = class(TComponent)
  private
    FController: TTyStyleController;
    FRoot: TWinControl;
    FEnabled: Boolean;
    FApplyFontName: Boolean;
    FApplyFontSize: Boolean;
    FOnStyleControl: TTyStyleControlEvent;
    procedure SetController(AValue: TTyStyleController);
    procedure ControllerChanged(Sender: TObject);
    function EffectiveRoot: TWinControl;
    procedure WalkAndStyle(AParent: TWinControl);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { (Re)style the whole Root subtree now. Idempotent. No-op at design time / disabled / no controller. }
    procedure Apply;
    { Apply the theme to ONE control per the rules (resolve token, RTTI set font/background). Public
      so a host can style a control it just created at runtime, and for testing. }
    procedure StyleControl(AControl: TControl);
    { Add a class whose BACKGROUND must never be set (OS-draws it). Affects all stylers. }
    class procedure RegisterDeny(AClass: TControlClass);
    class function IsDenied(AControl: TControl): Boolean;
  published
    property Controller: TTyStyleController read FController write SetController;
    property Root: TWinControl read FRoot write FRoot;
    property Enabled: Boolean read FEnabled write FEnabled default True;
    property ApplyFontName: Boolean read FApplyFontName write FApplyFontName default False;
    property ApplyFontSize: Boolean read FApplyFontSize write FApplyFontSize default False;
    property OnStyleControl: TTyStyleControlEvent read FOnStyleControl write FOnStyleControl;
  end;

implementation

uses
  Graphics, TypInfo, StdCtrls, ExtCtrls, Buttons,
  tyControls.Types, tyControls.Base, tyControls.StyleModel;

var
  GDeny: array of TControlClass;   // background-deny classes (OS-drawn): set up in initialization

class procedure TTyNativeStyler.RegisterDeny(AClass: TControlClass);
begin
  SetLength(GDeny, Length(GDeny) + 1);
  GDeny[High(GDeny)] := AClass;
end;

class function TTyNativeStyler.IsDenied(AControl: TControl): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(GDeny) do
    if AControl.InheritsFrom(GDeny[i]) then Exit(True);
end;

{ Map a native control to the closest Ty token; unmapped -> 'TyPanel' (a neutral surface present in
  every theme). Memo/combo/listbox are checked before edit in case of shared ancestry; the map is a
  refinement only — an unmatched control still gets TyPanel, so it is always themed. }
function NativeTypeKey(AControl: TControl): string;
begin
  if AControl is TCustomMemo then Result := 'TyMemo'
  else if AControl is TCustomComboBox then Result := 'TyComboBox'
  else if AControl is TCustomListBox then Result := 'TyListBox'
  else if AControl is TCustomEdit then Result := 'TyEdit'
  else if AControl is TRadioButton then Result := 'TyRadioButton'
  else if AControl is TCustomCheckBox then Result := 'TyCheckBox'
  else if AControl is TCustomButton then Result := 'TyButton'      // font only (denied bg)
  else if AControl is TCustomGroupBox then Result := 'TyGroupBox'
  else if (AControl is TCustomLabel) or (AControl is TCustomStaticText) then Result := 'TyLabel'
  else if AControl is TCustomPanel then Result := 'TyPanel'
  else Result := 'TyPanel';
end;

constructor TTyNativeStyler.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEnabled := True;
end;

destructor TTyNativeStyler.Destroy;
begin
  if FController <> nil then FController.RemoveChangeListener(@ControllerChanged);
  inherited Destroy;
end;

procedure TTyNativeStyler.SetController(AValue: TTyStyleController);
begin
  if FController = AValue then Exit;
  if FController <> nil then
  begin
    FController.RemoveChangeListener(@ControllerChanged);
    RemoveFreeNotification(FController);
  end;
  FController := AValue;
  if AValue <> nil then
  begin
    FreeNotification(AValue);
    AValue.AddChangeListener(@ControllerChanged);
  end;
  if not (csLoading in ComponentState) then Apply;
end;

procedure TTyNativeStyler.ControllerChanged(Sender: TObject);
begin
  Apply;
end;

procedure TTyNativeStyler.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) then
  begin
    if AComponent = FController then FController := nil
    else if AComponent = FRoot then FRoot := nil;
  end;
end;

procedure TTyNativeStyler.Loaded;
begin
  inherited Loaded;
  Apply;   // streamed Controller/Root now resolved; style once
end;

function TTyNativeStyler.EffectiveRoot: TWinControl;
begin
  if FRoot <> nil then Result := FRoot
  else if Owner is TWinControl then Result := TWinControl(Owner)
  else Result := nil;
end;

procedure TTyNativeStyler.Apply;
begin
  if (csDesigning in ComponentState) then Exit;   // never bake theme colors into the .lfm
  if (not FEnabled) or (FController = nil) then Exit;
  if EffectiveRoot <> nil then WalkAndStyle(EffectiveRoot);
end;

procedure TTyNativeStyler.WalkAndStyle(AParent: TWinControl);
var
  i: Integer;
  c: TControl;
begin
  for i := 0 to AParent.ControlCount - 1 do
  begin
    c := AParent.Controls[i];
    StyleControl(c);
    if c is TWinControl then WalkAndStyle(TWinControl(c));
  end;
end;

procedure TTyNativeStyler.StyleControl(AControl: TControl);
var
  style: TTyStyleSet;
  fnt: TFont;
  handled: Boolean;
begin
  if AControl = nil then Exit;
  if (AControl is TTyGraphicControl) or (AControl is TTyCustomControl) then Exit;  // self-theming
  if FController = nil then Exit;
  handled := False;
  if Assigned(FOnStyleControl) then FOnStyleControl(Self, AControl, handled);
  if handled then Exit;

  style := FController.Model.ResolveStyle(NativeTypeKey(AControl), '', []);

  // Font (low-risk, broad): text colour always; family/size opt-in.
  if IsPublishedProp(AControl, 'Font') then
  begin
    fnt := TFont(GetObjectProp(AControl, 'Font'));
    if fnt <> nil then
    begin
      if tpTextColor in style.Present then fnt.Color := TyColorToLCL(style.TextColor);
      if FApplyFontName and (tpFontName in style.Present) and (style.FontName <> '') then
        fnt.Name := style.FontName;
      if FApplyFontSize and (tpFontSize in style.Present) and (style.FontSize > 0) then
        fnt.Size := style.FontSize;
      if IsPublishedProp(AControl, 'ParentFont') then SetOrdProp(AControl, 'ParentFont', Ord(False));
    end;
  end;

  // Background (risky): only a solid bg, and only if the class is not a known OS-drawn type.
  if IsPublishedProp(AControl, 'Color') and (tpBackground in style.Present)
     and (style.Background.Kind = tfkSolid) and (not IsDenied(AControl)) then
  begin
    SetOrdProp(AControl, 'Color', TyColorToLCL(style.Background.Color));
    if IsPublishedProp(AControl, 'ParentColor') then SetOrdProp(AControl, 'ParentColor', Ord(False));
  end;
end;

initialization
  // OS-drawn controls: setting their background is ineffective/ugly -> deny the bg (font still applies).
  TTyNativeStyler.RegisterDeny(TCustomButton);   // TButton, TBitBtn, ...
  TTyNativeStyler.RegisterDeny(TSpeedButton);
  TTyNativeStyler.RegisterDeny(TCustomCheckBox); // TCheckBox + TRadioButton (TRadioButton descends from it)
end.
```

- [ ] **Step 2: Add the unit to `tycontrols.lpk`** `<Files>` (insert after the `tyControls.StrConsts` item, mirroring its shape):

```xml
      <Item>
        <Filename Value="source/tyControls.NativeStyler.pas"/>
        <UnitName Value="tyControls.NativeStyler"/>
      </Item>
```

- [ ] **Step 3: Build to verify it compiles.**
Run: `cd /d/Projects/ty-controls && lazbuild tycontrols.lpk 2>&1 | grep -iE "error|fatal"; echo "exit ${PIPESTATUS[0]}"`
Expected: exit 0. (If `TCustomStaticText` is not found, add `; StdCtrls already provides it` — it is in StdCtrls. If `GetObjectProp` ambiguity, it is `TypInfo.GetObjectProp(TObject; string): TObject`.)

- [ ] **Step 4: Commit**

```bash
git add source/tyControls.NativeStyler.pas tycontrols.lpk
git commit -m "feat(native-styler): TTyNativeStyler — RTTI-generic theming of native controls"
```

---

## Task 3: Headless tests for the styler

The styling logic is pure property-setting (no handle needed), so it is fully headless-testable.

**Files:** Create `tests/test.nativestyler.pas`; Modify `tests/tytests.lpr`

- [ ] **Step 1: Write the failing test.** Create `tests/test.nativestyler.pas`:

```pascal
unit test.nativestyler;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Graphics, Controls, StdCtrls, ExtCtrls, fpcunit, testregistry,
  tyControls.Controller, tyControls.NativeStyler;
type
  TNativeStylerTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FStyler: TTyNativeStyler;
    FSkipName: string;
    procedure SkipByName(Sender: TObject; AControl: TControl; var AHandled: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEditGetsBackgroundAndFont;
    procedure TestButtonGetsFontButNotBackground;
    procedure TestOnStyleControlCanSkip;
    procedure TestRegisterDenyBlocksBackground;
    procedure TestUnmappedFallsBackToPanel;
  end;

implementation

const
  // distinct colours per token so assertions are unambiguous
  CSS =
    'TyEdit  { background: #112233; color: #445566; }' + LineEnding +
    'TyButton{ background: #102030; color: #405060; }' + LineEnding +
    'TyPanel { background: #778899; color: #AABBCC; }' + LineEnding;

procedure TNativeStylerTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(CSS);
  FStyler := TTyNativeStyler.Create(nil);
  FStyler.Controller := FCtl;
end;

procedure TNativeStylerTest.TearDown;
begin
  FStyler.Free;
  FCtl.Free;
end;

procedure TNativeStylerTest.SkipByName(Sender: TObject; AControl: TControl; var AHandled: Boolean);
begin
  if AControl.Name = FSkipName then AHandled := True;
end;

procedure TNativeStylerTest.TestEditGetsBackgroundAndFont;
var e: TEdit;
begin
  e := TEdit.Create(nil);
  try
    FStyler.StyleControl(e);
    AssertEquals('edit background = TyEdit bg', Integer(RGBToColor($11, $22, $33)), Integer(e.Color));
    AssertEquals('edit font = TyEdit color', Integer(RGBToColor($44, $55, $66)), Integer(e.Font.Color));
    AssertFalse('ParentColor cleared', e.ParentColor);
    AssertFalse('ParentFont cleared', e.ParentFont);
  finally
    e.Free;
  end;
end;

procedure TNativeStylerTest.TestButtonGetsFontButNotBackground;
var b: TButton;
begin
  b := TButton.Create(nil);
  try
    b.Color := clBtnFace;                       // a sentinel we expect to remain
    FStyler.StyleControl(b);
    AssertEquals('button font = TyButton color', Integer(RGBToColor($40, $50, $60)), Integer(b.Font.Color));
    AssertEquals('button background untouched (OS-drawn -> denied)', Integer(clBtnFace), Integer(b.Color));
  finally
    b.Free;
  end;
end;

procedure TNativeStylerTest.TestOnStyleControlCanSkip;
var e: TEdit;
begin
  e := TEdit.Create(nil);
  try
    e.Name := 'SkipMe';
    e.Color := clWindow;                        // sentinel
    FSkipName := 'SkipMe';
    FStyler.OnStyleControl := @SkipByName;
    FStyler.StyleControl(e);
    AssertEquals('opted-out control untouched', Integer(clWindow), Integer(e.Color));
  finally
    e.Free;
  end;
end;

procedure TNativeStylerTest.TestRegisterDenyBlocksBackground;
var p: TPanel;
begin
  // TPanel maps to TyPanel and is NOT denied by default -> it normally gets a bg. Deny its class.
  TTyNativeStyler.RegisterDeny(TPanel);
  p := TPanel.Create(nil);
  try
    p.Color := clBtnFace;                       // sentinel
    FStyler.StyleControl(p);
    AssertEquals('font still applied', Integer(RGBToColor($AA, $BB, $CC)), Integer(p.Font.Color));
    AssertEquals('background blocked by RegisterDeny', Integer(clBtnFace), Integer(p.Color));
  finally
    p.Free;
  end;
end;

procedure TNativeStylerTest.TestUnmappedFallsBackToPanel;
var sb: TScrollBox;   // no Ty analog in the map -> TyPanel
begin
  sb := TScrollBox.Create(nil);
  try
    FStyler.StyleControl(sb);
    AssertEquals('unmapped control borrows TyPanel bg', Integer(RGBToColor($77, $88, $99)), Integer(sb.Color));
  finally
    sb.Free;
  end;
end;

initialization
  RegisterTest(TNativeStylerTest);
end.
```

- [ ] **Step 2: Register the test.** In `tests/tytests.lpr`, append `test.nativestyler` to the `uses` clause (after `test.controller.changelistener` from Task 1).

- [ ] **Step 3: Run; verify pass + no regression.**
Run: `cd /d/Projects/ty-controls && lazbuild tests/tytests.lpi 2>&1 | grep -iE "error|fatal"; ./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of (run|failures|errors)"`
Expected: 959 run / 0 failures / 11 errors (Task 1 added 2, this adds 5). If `TestButtonGetsFontButNotBackground` fails on the background assertion, confirm `TCustomButton`/`TCustomCheckBox` are registered in the unit's `initialization`. If the `TScrollBox` test fails, `TScrollBox` is in `Forms` — add `Forms` to the test's uses.

- [ ] **Step 4: Commit**

```bash
git add tests/test.nativestyler.pas tests/tytests.lpr
git commit -m "test(native-styler): font/background rules, opt-out, deny-list, TyPanel fallback"
```

---

## Task 4: Register in the design-time palette

**Files:** Modify `designtime/tyControls.Design.pas`

- [ ] **Step 1: Add the unit to the uses clause.** In `designtime/tyControls.Design.pas`, add `tyControls.NativeStyler` to the `uses` (the line listing the `tyControls.*` units, near `tyControls.Menu`).

- [ ] **Step 2: Register the component on the palette.** In `Register`, add `TTyNativeStyler` to the `RegisterComponents('TyControls', [...])` array (append it after `TTyPopupMenu`).

- [ ] **Step 3: Register the About editor for it** (consistency with the other non-visual components). After the existing `RegisterPropertyEditor(..., TTyStyleController, 'About', TTyAboutEditor);` line, the styler has no `About` property, so **skip** this — no editor needed. (No action; this step is a deliberate no-op note so the implementer doesn't invent one.)

- [ ] **Step 4: Build the design-time package + run the suite.**
Run: `cd /d/Projects/ty-controls && lazbuild tycontrols_dt.lpk 2>&1 | grep -iE "error|fatal"; echo "dt ${PIPESTATUS[0]}"; ./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of (run|failures|errors)"`
Expected: dt exit 0; 959 / 0 / 11.

- [ ] **Step 5: Commit**

```bash
git add designtime/tyControls.Design.pas
git commit -m "feat(designtime): register TTyNativeStyler on the TyControls palette"
```

> **Manual verification (real IDE / GUI, not automatable here):** drop a `TTyNativeStyler` + a couple of native controls (`TEdit`, `TButton`, `TListBox`) on a themed TyForm, point its `Controller` at the form's controller, run, and switch themes — the edit/listbox should pick up the theme background+text, the button should pick up the text colour only, and a theme switch should re-style them live.

---

## Phasing & integration
- Tasks land in order (1 → 4); each leaves the build green + the suite passing (954 after T1, 959 after T3).
- Branch `feat/native-styler` is off main. After implementation: push to gitee for the user's real-IDE/GUI verification, then merge per the usual flow.
- Out of scope (YAGNI, per spec): a dedicated `TyNative` token (using `TyPanel`), `.tycss native()` selectors, native border-colour theming, design-time preview (deliberately disabled — would bake colours into the `.lfm`).

## Self-review (done)
- **Spec coverage:** styler component + opt-out/override (`OnStyleControl`) + deny-list (`RegisterDeny`) + RTTI-generic apply + class→token map + `TyPanel` fallback → Task 2; live re-apply via the Controller change-listener → Task 1 + the `SetController`/`ControllerChanged` wiring in Task 2; palette registration → Task 4; headless tests → Tasks 1 & 3. The spec's `TyNative` token is consciously replaced by `TyPanel` (documented deviation, flagged at top).
- **No placeholders:** every code step is complete; the one "no-op" step (4.3) is explicitly a non-action with the reason.
- **Identifier consistency:** `AddChangeListener`/`RemoveChangeListener`/`CallNotifyEvents` (T1) match the styler's `SetController`/`Destroy` usage (T2); `StyleControl`/`Apply`/`RegisterDeny`/`IsDenied`/`NativeTypeKey` are used consistently across the unit and tests; `TTyStyleSet.Present`/`Background.Kind`/`tfkSolid`/`tpTextColor`/`tpBackground` match Types.pas.
