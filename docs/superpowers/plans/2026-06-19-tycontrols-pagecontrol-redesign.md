# TyControls PageControl Redesign (SP1) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `TTyTabControl` with a `TPageControl`-faithful designer container: a shared `TTyCustomTabStrip` base, `TTyTabSheet` pages (form-owned, `GetChildren`-streamed), and `TTyPageControl` with a component editor — so controls can be dropped onto pages in the IDE and persist.

**Architecture:** Extract the old control's page-agnostic header engine into `TTyCustomTabStrip` (abstract on tab data, virtual hooks for select/reorder/remove). `TTyPageControl` descends from it and supplies tab data from its `TTyTabSheet` children. Pages are created `Owner = the form`, `Parent = the control`; streaming uses the default `GetChildren` (`Owner = Root`); pages self-register via `SetParent`; design-time switching is via a component editor. The old `TTyTabControl` unit and its `Tabs` collection are deleted.

**Tech Stack:** Free Pascal / Lazarus (LCL), BGRABitmap, fpcunit. Reference: Lazarus `comctrls`/`custompage.inc`/`customnotebook.inc`, `componenteditors.pas`.

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `source/tyControls.TabStrip.pas` | **create** | `TTyCustomTabStrip` — header engine, abstract tab data, hooks |
| `source/tyControls.TabSheet.pas` | **create** | `TTyTabSheet` — one page (themed surface, `Caption`, design flags) |
| `source/tyControls.PageControl.pas` | **create** | `TTyPageControl` — container + designer integration |
| `source/tyControls.TabControl.pas` | **delete** | old control (after the three above exist) |
| `designtime/tyControls.Design.pas` | modify | registration, component editor, palette icons |
| `tools/genicons/genicons.lpr` | modify | Glyphs[]: −`TTyTabControl` +`TTyPageControl` +`TTyTabSheet` |
| `scripts/gen-icons.ps1` | modify | `$classes`: same swap |
| `tests/test.paletteicons.pas` | modify | `CClasses`: same swap |
| `tyControls.lpk`, `tycontrols_dt.lpk` | modify | unit list: −TabControl +3 new units |
| `examples/demo/mainform.lfm` + `.pas` | modify | migrate `TabCtrl1` to `TTyPageControl` |
| `tests/test.tabstrip.pas` | **create** | strip-engine tests (geometry/scroll/drag/close/anim/keyboard) |
| `tests/test.pagecontrol.pas` | **create** | page mgmt + ownership + ActivePage + designer flags |
| `tests/test.tabsheet.pas` | **create** | TTyTabSheet flags + Caption + SetParent register |
| `tests/test.pagecontrol.streaming.pas` | **create** | TWriter/TReader round-trip regression guard |
| `tests/test.tabcontrol*.pas` | **delete** | old (collection/streaming/scroll/reorder/closehover) |
| `tests/tytests.lpr` | modify | drop old test units, add the four new |
| `docs/controls/tabcontrol.md` | rename→`pagecontrol.md` + rewrite | doc the new control |

---

## Class interfaces (the contract)

### `TTyCustomTabStrip` (tyControls.TabStrip.pas)

```pascal
unit tyControls.TabStrip;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, ExtCtrls,
  tyControls.Types, tyControls.Controller, tyControls.Painter, tyControls.Base,
  tyControls.Animation;
type
  TTyTabCloseEvent = procedure(Sender: TObject; AIndex: Integer; var AllowClose: Boolean) of object;
  TTyTabChangingEvent = procedure(Sender: TObject; ANewIndex: Integer; var AllowChange: Boolean) of object;
  TTyTabReorderEvent = procedure(Sender: TObject; AFromIndex, AToIndex: Integer) of object;

  TTyCustomTabStrip = class(TTyCustomControl)
  private
    FTabIndex, FPendingTabIndex, FTabHeight, FHoverTab, FHoverClose: Integer;
    FTabsClosable: Boolean;
    FOnChange: TNotifyEvent;
    FOnChanging: TTyTabChangingEvent;
    FOnReorder: TTyTabReorderEvent;
    FOnTabClose: TTyTabCloseEvent;
    FHeaderRects, FCloseRects: array of TRect;
    FDragTab, FDragStartX, FDragOrigin: Integer;
    FDragging: Boolean;
    FTabFade: TTyAnimator;
    FAnimationsEnabled: Boolean;
    FTimer: TTimer;
    procedure EnsureTimer;
    procedure HandleTimer(Sender: TObject);
    procedure SetTabIndex(AValue: Integer);
    procedure SetTabHeight(AValue: Integer);
    procedure SetTabsClosable(AValue: Boolean);
    procedure RebuildLayout(APPI: Integer);
    procedure DoCloseClick(AIndex: Integer);     // was DoCloseTab: OnTabClose veto -> RemoveTabData
    function  TabHPx(APPI: Integer): Integer;
    function  TabCaptionWidth(const ACaption: string; const AStyle: TTyStyleSet; APPI: Integer): Integer;
  protected
    FHeaderScroll: Integer;
    FShowScrollAffordance: Boolean;
    FScrollLeftRect, FScrollRightRect: TRect;
    { Tab data — the ONLY thing a subclass must supply. }
    function GetTabCount: Integer; virtual; abstract;
    function GetTabCaption(AIndex: Integer): string; virtual; abstract;
    function GetTabClosableAt(AIndex: Integer): Boolean; virtual;   // default: FTabsClosable
    { Strip events the subclass reacts to (all default no-op). }
    procedure DoSelectTab(AIndex: Integer); virtual;
    procedure DoReorderTabs(AFromIndex, AToIndex: Integer); virtual;
    procedure RemoveTabData(AIndex: Integer); virtual;
    procedure SetController(AValue: TTyStyleController); override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure AdjustClientRect(var ARect: TRect); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    function  DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function  AdvanceAnimation(AMs: Integer): Boolean;
    procedure ArmTabFade;
    function  GetTabFadeEased: Single;
    { Re-layout + repaint after the subclass's tab set changes. }
    procedure TabsChanged;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function TabCount: Integer;
    function TabCaption(AIndex: Integer): string;
    function TyTabHeaderRect(AIndex: Integer): TRect;
    function TyTabCloseRect(AIndex: Integer): TRect;
    function TyHeaderStripWidth: Integer;
    function TyMaxHeaderScroll: Integer;
    function TyTabScrollLeftRect: TRect;
    function TyTabScrollRightRect: TRect;
    function HeaderRectShifted(AIndex: Integer): TRect;
    procedure SetHeaderScroll(AValue: Integer);
    procedure ScrollTabIntoView(AIndex: Integer);
    function TyDragThresholdPx(APPI: Integer): Integer;
    function TyDropIndexAt(X, APPI: Integer): Integer;
    property TyTabHoverClose: Integer read FHoverClose;
    property AnimationsEnabled: Boolean read FAnimationsEnabled write FAnimationsEnabled default True;
    { Selection is PUBLIC here (not published) so each subclass publishes it under its own
      name — TTyPageControl as `ActivePageIndex`, TTyTabSet (SP2) as `TabIndex` — avoiding a
      duplicate streamed property. }
    property TabIndex: Integer read FTabIndex write SetTabIndex;
  published
    property TabHeight: Integer read FTabHeight write SetTabHeight default 28;
    property TabsClosable: Boolean read FTabsClosable write SetTabsClosable default False;
    property OnTabClose: TTyTabCloseEvent read FOnTabClose write FOnTabClose;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnChanging: TTyTabChangingEvent read FOnChanging write FOnChanging;
    property OnReorder: TTyTabReorderEvent read FOnReorder write FOnReorder;
    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;
implementation
...
end.
```

`GetStyleTypeKey` is NOT defined here (abstract from `TTyCustomControl`); each subclass supplies it. The header sub-parts keep their existing theme selectors (`TyTab`, `TyTabClose`) in `RenderTo`; only the control-level typeKey differs per subclass.

### `TTyTabSheet` (tyControls.TabSheet.pas)

```pascal
unit tyControls.TabSheet;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, Graphics,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTyTabSheet = class(TTyCustomControl)
  private
    FCaption: string;
    procedure SetCaption(const AValue: string);
  protected
    procedure SetParent(AParent: TWinControl); override;  // register with TTyPageControl
    function GetStyleTypeKey: string; override;            // 'TyTabSheet'
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Caption: string read FCaption write SetCaption;   // the TAB label (not drawn on body)
    property StyleClass;
    property Controller;
  end;
implementation
end.
```

### `TTyPageControl` (tyControls.PageControl.pas)

```pascal
unit tyControls.PageControl;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.TabStrip, tyControls.TabSheet;
type
  TTyPageControl = class(TTyCustomTabStrip)
  private
    FPages: array of TTyTabSheet;
    FDestroying: Boolean;
    function GetPage(AIndex: Integer): TTyTabSheet;
    function GetActivePage: TTyTabSheet;
    procedure SetActivePage(AValue: TTyTabSheet);
    procedure ShowOnlyPage(AIndex: Integer);          // Visible + csNoDesignVisible per page
  protected
    function  GetTabCount: Integer; override;
    function  GetTabCaption(AIndex: Integer): string; override;
    procedure DoSelectTab(AIndex: Integer); override;        // -> ShowOnlyPage
    procedure DoReorderTabs(AFromIndex, AToIndex: Integer); override;  // reorder FPages
    procedure RemoveTabData(AIndex: Integer); override;      // -> RemovePage(AIndex, free)
    function  GetStyleTypeKey: string; override;             // 'TyPageControl'
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override;
    { internal page registration, called by TTyTabSheet.SetParent and AddPage }
    procedure RegisterPage(APage: TTyTabSheet);
    procedure UnregisterPage(APage: TTyTabSheet; AFree: Boolean);
  public
    destructor Destroy; override;
    function AddPage(const ACaption: string): TTyTabSheet;
    function AddTab(const ACaption: string): TTyTabSheet;     // alias of AddPage (API parity)
    procedure RemovePage(AIndex: Integer);
    function PageCount: Integer;
    property Pages[AIndex: Integer]: TTyTabSheet read GetPage;
    property ActivePage: TTyTabSheet read GetActivePage write SetActivePage;
  published
    property ActivePageIndex: Integer read FTabIndex write SetTabIndex default -1;  // = base TabIndex
  end;
implementation
end.
```

> Note: `ActivePageIndex` reads `FTabIndex` (the base's selection) and writes via the base `SetTabIndex`. The base's `TabIndex` published property is hidden by not re-publishing it here under that name (we publish `ActivePageIndex` instead — both map to the same field/setter; the base keeps `TabIndex` for `TTyTabSet`). `RegisterPage` registers the page with `TTyPageControl`; `TTyTabSheet.SetParent` calls it. `TabStrip` exposes the protected helper the sheet needs.

---

## Task 1: `TTyCustomTabStrip` base (extract the header engine)

**Files:** Create `source/tyControls.TabStrip.pas`. Reference (move-from): `source/tyControls.TabControl.pas`.

- [ ] **Step 1: Create the unit with the interface above** exactly as written.

- [ ] **Step 2: Move the header-engine method bodies** from `tyControls.TabControl.pas` into the implementation, applying these adaptations (the methods are otherwise verbatim):
  - Move: `EnsureTimer`, `HandleTimer`, `AdvanceAnimation`, `ArmTabFade`, `GetTabFadeEased`, `SetController`, `TabHPx`, `TabCaptionWidth`, `SetTabsClosable`, `RebuildLayout`, `TyTabHeaderRect`, `TyTabCloseRect`, `TyHeaderStripWidth`, `TyMaxHeaderScroll`, `TyTabScrollLeftRect`, `TyTabScrollRightRect`, `HeaderRectShifted`, `SetHeaderScroll`, `ScrollTabIntoView`, `TyDragThresholdPx`, `TyDropIndexAt`, `AdjustClientRect`, `SetTabIndex`, `SetTabHeight`, `RenderTo`, `Paint`, `MouseDown`, `MouseMove`, `MouseUp`, `MouseLeave`, `DoMouseWheel`, `KeyDown`, `TabCount`, `TabCaption`.
  - **Adaptation A — tab data:** replace every `FCaptions.Count` → `GetTabCount`; every `FCaptions[i]` / `FCaptions.Strings[i]` → `GetTabCaption(i)`; `TabCount` body → `Result := GetTabCount`; `TabCaption` body → bounds-checked `GetTabCaption`.
  - **Adaptation B — select:** in `SetTabIndex`, replace the `ShowOnlyPage(FTabIndex)` call (old line 743) with `DoSelectTab(FTabIndex)`. Remove the `FCaptions`-based clamp's dependency by using `GetTabCount`.
  - **Adaptation C — close:** rename `DoCloseTab` → `DoCloseClick`; its body fires `OnTabClose` (veto) then calls `RemoveTabData(AIndex)` instead of `RemoveTab`. Update the `MouseDown`/`MouseUp` call sites that invoked `DoCloseTab`.
  - **Adaptation D — reorder:** in `MouseMove`/`MouseUp` where the old code reseated `FPages`/`FCaptions` during a drag and fired `OnReorder`, replace the array reseating with a call to `DoReorderTabs(AFrom, ATo)`; keep the `OnReorder` firing in the base (it's strip-level). The base tracks `FDragTab`/`FDragOrigin` purely as indices.
  - **Adaptation E — closable:** in `RebuildLayout`/`RenderTo`, replace `FTabsClosable` reads used per-tab with `GetTabClosableAt(i)` (default returns `FTabsClosable`, so behaviour is identical).
  - Add `GetTabClosableAt` (default `Result := FTabsClosable`), `DoSelectTab`/`DoReorderTabs`/`RemoveTabData` (empty `begin end;`), and `TabsChanged` (`if not (csLoading in ComponentState) then begin Invalidate; end;`).
  - `Create`: set `FTabIndex := -1; FPendingTabIndex := -1; FTabHeight := 28; FHoverTab := -1; FHoverClose := -1; FDragTab := -1; FDragOrigin := -1; FAnimationsEnabled := True; TabStop := True;` + animator init (move from old `Create`). `Destroy`: `FreeAndNil(FTimer);` then inherited.

- [ ] **Step 3: Build** `lazbuild tyControls.lpk` after temporarily adding the unit (see Task 7); for now compile-check by adding it to the test project in Task 8. Expected: compiles (abstract methods unimplemented is fine — it's abstract).

- [ ] **Step 4: Commit**
```bash
git add source/tyControls.TabStrip.pas
git commit -m "feat(tycontrols): TTyCustomTabStrip — extract page-agnostic tab-header engine"
```

## Task 2: `TTyTabSheet` page

**Files:** Create `source/tyControls.TabSheet.pas`. Test: `tests/test.tabsheet.pas`.

- [ ] **Step 1: Write the failing test** `tests/test.tabsheet.pas`:
```pascal
unit test.tabsheet;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Controls, Forms, fpcunit, testregistry,
  tyControls.TabSheet;
type
  TTabSheetTest = class(TTestCase)
  published
    procedure TestDesignControlStyleFlags;
    procedure TestCaptionPublished;
  end;
implementation
uses TypInfo;
procedure TTabSheetTest.TestDesignControlStyleFlags;
var S: TTyTabSheet;
begin
  S := TTyTabSheet.Create(nil);
  try
    AssertTrue('csAcceptsControls',   csAcceptsControls   in S.ControlStyle);
    AssertTrue('csDesignFixedBounds', csDesignFixedBounds in S.ControlStyle);
    AssertTrue('csNoDesignVisible',   csNoDesignVisible   in S.ControlStyle);
    AssertTrue('csNoFocus',           csNoFocus           in S.ControlStyle);
    AssertEquals('alClient', Ord(alClient), Ord(S.Align));
  finally S.Free; end;
end;
procedure TTabSheetTest.TestCaptionPublished;
var S: TTyTabSheet;
begin
  S := TTyTabSheet.Create(nil);
  try
    AssertTrue('Caption is published', IsPublishedProp(S, 'Caption'));
    S.Caption := 'Page X';
    AssertEquals('Page X', S.Caption);
  finally S.Free; end;
end;
initialization
  RegisterTest(TTabSheetTest);
end.
```

- [ ] **Step 2: Implement `TTyTabSheet`:**
```pascal
constructor TTyTabSheet.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls, csDesignFixedBounds, csNoDesignVisible, csNoFocus];
  Align := alClient;
  Visible := False;
  FCaption := '';
end;

function TTyTabSheet.GetStyleTypeKey: string;
begin
  Result := 'TyTabSheet';
end;

procedure TTyTabSheet.SetCaption(const AValue: string);
begin
  if FCaption = AValue then Exit;
  FCaption := AValue;
  if Parent <> nil then Parent.Invalidate;   // re-lay the host header
end;

procedure TTyTabSheet.SetParent(AParent: TWinControl);
begin
  inherited SetParent(AParent);
  if (AParent <> nil) and (AParent is TTyPageControl) then
    TTyPageControl(AParent).RegisterPage(Self);
end;

procedure TTyTabSheet.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var P: TTyPainter; S: TTyStyleSet; R: TRect;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    DrawFrame(P, R, S);   // themed background only — no caption text on the body
    P.EndPaint;
  finally P.Free; end;
end;

procedure TTyTabSheet.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;
```
Add `tyControls.PageControl` to the `uses` of the implementation section (for the `TTyPageControl` reference in `SetParent`). NB: `TabSheet` interface must NOT use `PageControl` (would be circular); use it in the implementation `uses` only.

- [ ] **Step 3: Add `test.tabsheet` to `tytests.lpr` uses, build + run, verify green.**
Run: `lazbuild tests/tytests.lpi && ./tests/tytests.exe --suite=TTabSheetTest --format=plain`
Expected: 0 failures.

- [ ] **Step 4: Commit**
```bash
git add source/tyControls.TabSheet.pas tests/test.tabsheet.pas tests/tytests.lpr
git commit -m "feat(tycontrols): TTyTabSheet — designer page (design flags + Caption)"
```

## Task 3: `TTyPageControl`

**Files:** Create `source/tyControls.PageControl.pas`. Test: `tests/test.pagecontrol.pas`.

- [ ] **Step 1: Write the failing test** `tests/test.pagecontrol.pas`:
```pascal
unit test.pagecontrol;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Controls, Forms, fpcunit, testregistry,
  tyControls.TabSheet, tyControls.PageControl;
type
  TPageControlTest = class(TTestCase)
  private
    FForm: TForm;
    FPC: TTyPageControl;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAddPageParentedAndOwnedByForm;
    procedure TestFirstPageAutoSelected;
    procedure TestActivePageSwitchTogglesVisibility;
    procedure TestActivePageTogglesDesignVisibleFlag;
    procedure TestRemovePageCompactsAndReselects;
    procedure TestCaptionFeedsTabLabel;
  end;
implementation
procedure TPageControlTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 320, 240);
  FPC := TTyPageControl.Create(FForm);
  FPC.Parent := FForm;
  FPC.SetBounds(0, 0, 300, 200);
  FPC.Font.PixelsPerInch := 96;
end;
procedure TPageControlTest.TearDown;
begin
  FForm.Free;
end;
procedure TPageControlTest.TestAddPageParentedAndOwnedByForm;
var P: TTyTabSheet;
begin
  P := FPC.AddPage('Alpha');
  AssertSame('page parent is the page control', FPC, P.Parent);
  AssertSame('page owner is the form (LookupRoot)', FForm, P.Owner);
  AssertEquals('page count', 1, FPC.PageCount);
end;
procedure TPageControlTest.TestFirstPageAutoSelected;
begin
  FPC.AddPage('Alpha');
  AssertEquals('first page auto-selected', 0, FPC.ActivePageIndex);
end;
procedure TPageControlTest.TestActivePageSwitchTogglesVisibility;
var A, B: TTyTabSheet;
begin
  A := FPC.AddPage('A'); B := FPC.AddPage('B');
  FPC.ActivePageIndex := 1;
  AssertFalse('A hidden', A.Visible);
  AssertTrue('B visible', B.Visible);
end;
procedure TPageControlTest.TestActivePageTogglesDesignVisibleFlag;
var A, B: TTyTabSheet;
begin
  A := FPC.AddPage('A'); B := FPC.AddPage('B');
  FPC.ActivePageIndex := 0;
  AssertFalse('active page A: csNoDesignVisible cleared', csNoDesignVisible in A.ControlStyle);
  AssertTrue('inactive page B: csNoDesignVisible set', csNoDesignVisible in B.ControlStyle);
end;
procedure TPageControlTest.TestRemovePageCompactsAndReselects;
begin
  FPC.AddPage('A'); FPC.AddPage('B'); FPC.AddPage('C');
  FPC.ActivePageIndex := 2;
  FPC.RemovePage(2);
  AssertEquals('count after remove', 2, FPC.PageCount);
  AssertEquals('active clamped to last', 1, FPC.ActivePageIndex);
end;
procedure TPageControlTest.TestCaptionFeedsTabLabel;
var P: TTyTabSheet;
begin
  P := FPC.AddPage('Hello');
  AssertEquals('tab caption comes from the page', 'Hello', FPC.TabCaption(0));
  P.Caption := 'World';
  AssertEquals('tab caption tracks the page Caption', 'World', FPC.TabCaption(0));
end;
initialization
  RegisterTest(TPageControlTest);
end.
```

- [ ] **Step 2: Implement `TTyPageControl`** (complete):
```pascal
function TTyPageControl.GetStyleTypeKey: string;
begin
  Result := 'TyPageControl';
end;

function TTyPageControl.PageCount: Integer;
begin
  Result := Length(FPages);
end;

function TTyPageControl.GetTabCount: Integer;
begin
  Result := Length(FPages);
end;

function TTyPageControl.GetTabCaption(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < Length(FPages)) then
    Result := FPages[AIndex].Caption
  else
    Result := '';
end;

function TTyPageControl.GetPage(AIndex: Integer): TTyTabSheet;
begin
  if (AIndex >= 0) and (AIndex < Length(FPages)) then
    Result := FPages[AIndex]
  else
    Result := nil;
end;

function TTyPageControl.GetActivePage: TTyTabSheet;
begin
  Result := GetPage(ActivePageIndex);
end;

procedure TTyPageControl.SetActivePage(AValue: TTyTabSheet);
var I: Integer;
begin
  for I := 0 to High(FPages) do
    if FPages[I] = AValue then begin ActivePageIndex := I; Exit; end;
end;

procedure TTyPageControl.ShowOnlyPage(AIndex: Integer);
var I: Integer;
begin
  for I := 0 to High(FPages) do
  begin
    FPages[I].Visible := (I = AIndex);
    if I = AIndex then
      FPages[I].ControlStyle := FPages[I].ControlStyle - [csNoDesignVisible]
    else
      FPages[I].ControlStyle := FPages[I].ControlStyle + [csNoDesignVisible];
  end;
end;

procedure TTyPageControl.DoSelectTab(AIndex: Integer);
begin
  ShowOnlyPage(AIndex);
end;

procedure TTyPageControl.DoReorderTabs(AFromIndex, AToIndex: Integer);
var Moved: TTyTabSheet; I: Integer;
begin
  if (AFromIndex < 0) or (AFromIndex > High(FPages)) then Exit;
  if (AToIndex < 0) or (AToIndex > High(FPages)) then Exit;
  Moved := FPages[AFromIndex];
  if AFromIndex < AToIndex then
    for I := AFromIndex to AToIndex - 1 do FPages[I] := FPages[I + 1]
  else
    for I := AFromIndex downto AToIndex + 1 do FPages[I] := FPages[I - 1];
  FPages[AToIndex] := Moved;
end;

procedure TTyPageControl.RegisterPage(APage: TTyTabSheet);
var I: Integer;
begin
  for I := 0 to High(FPages) do
    if FPages[I] = APage then Exit;   // already registered
  SetLength(FPages, Length(FPages) + 1);
  FPages[High(FPages)] := APage;
  APage.Controller := Self.Controller;
  if Length(FPages) = 1 then          // auto-select first
  begin
    FTabIndex := 0;
    ShowOnlyPage(0);
  end
  else
    APage.Visible := (High(FPages) = FTabIndex);
  TabsChanged;
end;

procedure TTyPageControl.UnregisterPage(APage: TTyTabSheet; AFree: Boolean);
var Idx, J: Integer; OldActive: TTyTabSheet;
begin
  Idx := -1;
  for J := 0 to High(FPages) do if FPages[J] = APage then begin Idx := J; Break; end;
  if Idx < 0 then Exit;
  OldActive := GetActivePage;
  for J := Idx to High(FPages) - 1 do FPages[J] := FPages[J + 1];
  SetLength(FPages, Length(FPages) - 1);
  if Length(FPages) = 0 then FTabIndex := -1
  else if Idx < FTabIndex then Dec(FTabIndex)
  else if (Idx = FTabIndex) and (FTabIndex > High(FPages)) then FTabIndex := High(FPages);
  if AFree then APage.Free;
  ShowOnlyPage(FTabIndex);
  TabsChanged;
  if (GetActivePage <> OldActive) and Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyPageControl.RemoveTabData(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < Length(FPages)) then
    UnregisterPage(FPages[AIndex], True);
end;

procedure TTyPageControl.RemovePage(AIndex: Integer);
begin
  RemoveTabData(AIndex);
end;

function TTyPageControl.AddPage(const ACaption: string): TTyTabSheet;
var PageOwner: TComponent;
begin
  if Owner <> nil then PageOwner := Owner else PageOwner := Self;
  Result := TTyTabSheet.Create(PageOwner);
  Result.Caption := ACaption;
  Result.Parent := Self;     // SetParent -> RegisterPage
end;

function TTyPageControl.AddTab(const ACaption: string): TTyTabSheet;
begin
  Result := AddPage(ACaption);
end;

procedure TTyPageControl.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if FDestroying then Exit;
  if (Operation = opRemove) and (AComponent is TTyTabSheet) then
    UnregisterPage(TTyTabSheet(AComponent), False);   // LCL already freeing it
end;

procedure TTyPageControl.Loaded;
begin
  inherited Loaded;
  { Pages self-registered via SetParent during streaming, so FPages is already
    populated in child order. Apply a streamed ActivePageIndex (captured by the
    base SetTabIndex into FPendingTabIndex during csLoading). }
  if FPendingTabIndex <> -1 then
  begin
    SetTabIndex(FPendingTabIndex);
    FPendingTabIndex := -1;
  end
  else if (FTabIndex = -1) and (Length(FPages) > 0) then
    FTabIndex := 0;
  if Length(FPages) = 0 then FTabIndex := -1;
  ShowOnlyPage(FTabIndex);
  Invalidate;
end;

destructor TTyPageControl.Destroy;
begin
  FDestroying := True;
  inherited Destroy;   // pages are owned by the form/Self and freed normally
end;
```
`FPendingTabIndex`/`FTabIndex` are in the base `private`/visible region — make them `protected` in `TTyCustomTabStrip` so `TTyPageControl` can read/write them in `Loaded`/`ShowOnlyPage`/`UnregisterPage` (move `FTabIndex` and `FPendingTabIndex` to the base's `protected` section).

- [ ] **Step 3: Build + run, verify green.**
Run: `lazbuild tests/tytests.lpi && ./tests/tytests.exe --suite=TPageControlTest --format=plain`
Expected: 0 failures.

- [ ] **Step 4: Commit**
```bash
git add source/tyControls.PageControl.pas tests/test.pagecontrol.pas tests/tytests.lpr
git commit -m "feat(tycontrols): TTyPageControl — TPageControl-faithful container on TTyCustomTabStrip"
```

## Task 4: Streaming round-trip regression guard

**Files:** Create `tests/test.pagecontrol.streaming.pas`.

- [ ] **Step 1: Write the test** — build a form with a page control, 2 pages, a button on page 2, stream out and back, assert structure survives:
```pascal
unit test.pagecontrol.streaming;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Controls, Forms, fpcunit, testregistry,
  tyControls.Button, tyControls.TabSheet, tyControls.PageControl;
type
  TPageControlStreamingTest = class(TTestCase)
  published
    procedure TestRoundTripPreservesPagesAndChildren;
  end;
implementation
type
  THostForm = class(TForm)   // a streamable root
  published
    PC: TTyPageControl;
  end;

procedure TPageControlStreamingTest.TestRoundTripPreservesPagesAndChildren;
var
  Src, Dst: THostForm;
  Pg2: TTyTabSheet;
  Btn: TTyButton;
  MS: TMemoryStream;
  I, BtnCount: Integer;
  DstPC: TTyPageControl;
  Ctrl: TControl;
begin
  Src := THostForm.CreateNew(nil);
  MS := TMemoryStream.Create;
  try
    Src.Name := 'HostForm1';
    Src.PC := TTyPageControl.Create(Src);
    Src.PC.Name := 'PC';
    Src.PC.Parent := Src;
    Src.PC.AddPage('One');
    Pg2 := Src.PC.AddPage('Two');
    Pg2.Name := 'PgTwo';
    Src.PC.ActivePageIndex := 1;
    Btn := TTyButton.Create(Src);
    Btn.Name := 'Btn1';
    Btn.Parent := Pg2;                 // dropped on page 2
    MS.WriteComponent(Src);

    MS.Position := 0;
    Dst := THostForm(MS.ReadComponent(nil));
    try
      DstPC := Dst.FindComponent('PC') as TTyPageControl;
      AssertNotNull('page control survived', DstPC);
      AssertEquals('page count survived', 2, DstPC.PageCount);
      AssertEquals('captions survived', 'Two', DstPC.TabCaption(1));
      AssertEquals('active index survived', 1, DstPC.ActivePageIndex);
      // the button must have round-tripped as a child of page 2
      BtnCount := 0;
      for I := 0 to DstPC.Pages[1].ControlCount - 1 do
      begin
        Ctrl := DstPC.Pages[1].Controls[I];
        if Ctrl is TTyButton then Inc(BtnCount);
      end;
      AssertEquals('button persisted on page 2', 1, BtnCount);
    finally
      Dst.Free;
    end;
  finally
    MS.Free;
    Src.Free;
  end;
end;
initialization
  RegisterTest(TPageControlStreamingTest);
end.
```

- [ ] **Step 2: Add to `tytests.lpr`, build + run, verify green** (this proves the whole designer-persistence fix headlessly).
Run: `lazbuild tests/tytests.lpi && ./tests/tytests.exe --suite=TPageControlStreamingTest --format=plain`
Expected: 0 failures. If the button does not survive, the page's `Owner` is wrong — confirm `AddPage` owns pages by `Owner` (the form) and that controls placed on a page are owned by the same root.

- [ ] **Step 3: Commit**
```bash
git add tests/test.pagecontrol.streaming.pas tests/tytests.lpr
git commit -m "test(tycontrols): PageControl streaming round-trip (pages + dropped children persist)"
```

## Task 5: Design-time registration + component editor

**Files:** Modify `designtime/tyControls.Design.pas`.

- [ ] **Step 1: Add the component editor class** to the `type` section:
```pascal
  { Add / Delete / Show Next / Show Previous Page verbs for TTyPageControl. }
  TTyPageControlEditor = class(TDefaultComponentEditor)
  private
    function PC: TTyPageControl;
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;
```

- [ ] **Step 2: Implement it:**
```pascal
function TTyPageControlEditor.PC: TTyPageControl;
begin
  Result := Component as TTyPageControl;
end;

function TTyPageControlEditor.GetVerbCount: Integer;
begin
  Result := 4;
end;

function TTyPageControlEditor.GetVerb(Index: Integer): string;
begin
  case Index of
    0: Result := 'Add Page';
    1: Result := 'Delete Page';
    2: Result := 'Show Next Page';
    3: Result := 'Show Previous Page';
  else Result := '';
  end;
end;

procedure TTyPageControlEditor.ExecuteVerb(Index: Integer);
var
  Hook: TPropertyEditorHook;
  NewPage: TTyTabSheet;
  Designer: TIDesigner;
begin
  case Index of
    0: begin
         Hook := nil; GetHook(Hook);
         NewPage := TTyTabSheet.Create(PC.Owner);
         NewPage.Parent := PC;                  // SetParent -> RegisterPage
         if Hook <> nil then
           NewPage.Name := Hook.CreateUniqueComponentName(NewPage.ClassName, PC.Owner);
         NewPage.Caption := NewPage.Name;
         PC.ActivePage := NewPage;
         Designer := FindRootDesigner(PC);
         if Designer <> nil then Designer.Modified;
       end;
    1: if PC.ActivePageIndex >= 0 then
       begin
         Hook := nil; GetHook(Hook);
         if Hook <> nil then Hook.DeletePersistent(TPersistent(PC.ActivePage))
         else PC.RemovePage(PC.ActivePageIndex);
       end;
    2: if PC.PageCount > 0 then
         PC.ActivePageIndex := (PC.ActivePageIndex + 1) mod PC.PageCount;
    3: if PC.PageCount > 0 then
         PC.ActivePageIndex := (PC.ActivePageIndex + PC.PageCount - 1) mod PC.PageCount;
  end;
end;
```
(`GetHook`, `CreateUniqueComponentName`, `DeletePersistent`, `FindRootDesigner`, `TIDesigner` come from `PropEdits`/`ComponentEditors`/`LCLIntf`/`Forms`, already used or add to `uses`.)

- [ ] **Step 3: Swap the registration** in `Register`:
  - In `uses`: remove `tyControls.TabControl`; add `tyControls.PageControl, tyControls.TabSheet`.
  - In `RegisterComponents('TyControls', [...])`: replace `TTyTabControl` with `TTyPageControl, TTyTabSheet`.
  - Remove the `TTyTabControlEditor` class + its `RegisterComponentEditor(TTyTabControl, ...)` and the `RegisterPropertyEditor(TypeInfo(TTyTabCollection), ...)` line.
  - Add `RegisterComponentEditor(TTyPageControl, TTyPageControlEditor);`.

- [ ] **Step 4: Build the dt package.**
Run: `lazbuild tycontrols_dt.lpk`
Expected: compiles (after Task 7 swaps the package unit list; if it errors on the missing TabControl unit, do Task 7 first).

- [ ] **Step 5: Commit**
```bash
git add designtime/tyControls.Design.pas
git commit -m "feat(designtime): register TTyPageControl/TTyTabSheet + page component editor"
```

## Task 6: Palette icons — swap the class set

**Files:** `tools/genicons/genicons.lpr`, `scripts/gen-icons.ps1`, `tests/test.paletteicons.pas`.

- [ ] **Step 1: Update the three class lists** — remove `TTyTabControl`, add `TTyPageControl` and `TTyTabSheet`:
  - `genicons.lpr` `Glyphs[]`: replace the `TTyTabControl`→`@GTabControl` entry with two entries: `TTyPageControl`→`@GTabControl` (reuse the tabbed-body glyph), `TTyTabSheet`→`@GTabSheet` (new). Bump the array bound `array[0..20]` (21 classes now). Add a new glyph routine:
```pascal
procedure GTabSheet(b: TBGRABitmap); begin RRect(b,3,4,21,20,2,Ink); Line(b,3,9,21,9,Acc,2); end;
```
  (a single page: a framed rect with one accent tab edge at top.)
  - `gen-icons.ps1` `$classes`: same swap.
  - `test.paletteicons.pas` `CClasses` (size `array[0..20]`): same swap.

- [ ] **Step 2: Regenerate + verify.**
Run: `pwsh -File scripts/gen-icons.ps1` (the drift-guard checks the set == RegisterComponents, which Task 5 already updated)
Expected: `OK: 21 registered components all have icons`; 63 resources packed.

- [ ] **Step 3: Build + run the palette test.**
Run: `lazbuild tests/tytests.lpi && ./tests/tytests.exe --suite=TPaletteIconTest --format=plain`
Expected: 0 failures (21 classes × 3 sizes).

- [ ] **Step 4: Commit**
```bash
git add tools/genicons/genicons.lpr scripts/gen-icons.ps1 tests/test.paletteicons.pas designtime/icons/ designtime/tycontrols_icons.lrs
git commit -m "feat(designtime): palette icons — swap TabControl for PageControl + TabSheet"
```

## Task 7: Package unit lists

**Files:** `tyControls.lpk`, `tycontrols_dt.lpk`.

- [ ] **Step 1: Edit both `.lpk`** — in the `<Files>` list, remove the `tyControls.TabControl.pas` `<Item>` and add three `<Item>` entries for `tyControls.TabStrip.pas`, `tyControls.TabSheet.pas`, `tyControls.PageControl.pas` (copy the shape of an existing `<Item>`; bump `<Files Count="N">`). The runtime package (`tyControls.lpk`) gets all three source units; the dt package references them transitively via the runtime package (no change needed there beyond what Task 5 added to `Design.pas`).

- [ ] **Step 2: Build both packages.**
Run: `lazbuild tyControls.lpk && lazbuild tycontrols_dt.lpk`
Expected: both compile.

- [ ] **Step 3: Commit**
```bash
git add tyControls.lpk tycontrols_dt.lpk tycontrols.pas tycontrols_dt.pas
git commit -m "build(tycontrols): swap TabControl unit for TabStrip/TabSheet/PageControl in packages"
```

## Task 8: Remove the old `TTyTabControl`

**Files:** delete `source/tyControls.TabControl.pas`, `tests/test.tabcontrol.pas`, `tests/test.tabcontrol.collection.pas`, `tests/test.tabcontrol.streaming.pas`, `tests/test.tabcontrol.scroll.pas`, `tests/test.tabcontrol.reorder.pas`, `tests/test.tabcontrol.closehover.pas`. Modify `tests/tytests.lpr`.

- [ ] **Step 1: Re-home the strip-engine tests first.** Create `tests/test.tabstrip.pas`: copy the still-relevant geometry/scroll/drag/close-hover/animation tests from the old `test.tabcontrol*.pas`, retargeting them onto a `TTyCustomTabStrip` access subclass that supplies fixed tab data:
```pascal
type
  TStripAccess = class(TTyCustomTabStrip)
  private
    FCaps: array of string;
  protected
    function GetTabCount: Integer; override;
    function GetTabCaption(AIndex: Integer): string; override;
  public
    procedure AddCap(const S: string);
    procedure CallMouseDown(Button: TMouseButton; X, Y: Integer);
    // ... expose the protected seams the old tests used ...
  end;
```
Port the assertions for `TyTabHeaderRect`, `TyTabCloseRect`, `TyHeaderStripWidth`/`TyMaxHeaderScroll`/`ScrollTabIntoView`, `TyDropIndexAt`/`TyDragThresholdPx`, `TyTabHoverClose`, and the cross-fade animation seams (`AdvanceAnimation`/`ArmTabFade`/`GetTabFadeEased`) onto `TStripAccess`. (The PageControl-specific behaviours — auto-select, page visibility, streaming — live in `test.pagecontrol*.pas` from Tasks 3-4.)

- [ ] **Step 2: Delete the old unit + old tests; update `tytests.lpr`** — remove the six `test.tabcontrol*` units from `uses`, add `test.tabstrip`.
```bash
git rm source/tyControls.TabControl.pas tests/test.tabcontrol.pas tests/test.tabcontrol.collection.pas tests/test.tabcontrol.streaming.pas tests/test.tabcontrol.scroll.pas tests/test.tabcontrol.reorder.pas tests/test.tabcontrol.closehover.pas
```

- [ ] **Step 3: Build + full suite, verify green.**
Run: `lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain`
Expected: 0 failures (11 pre-existing headless errors unchanged).

- [ ] **Step 4: Commit**
```bash
git add -A
git commit -m "refactor(tycontrols): remove TTyTabControl; re-home strip-engine tests to TTyCustomTabStrip"
```

## Task 9: Migrate the demo

**Files:** `examples/demo/mainform.lfm`, `examples/demo/mainform.pas`.

- [ ] **Step 1: Edit `mainform.lfm`** — change `object TabCtrl1: TTyTabControl` to `object TabCtrl1: TTyPageControl`; remove the `Tabs = <...>` collection; replace `TabIndex = 1` with `ActivePageIndex = 1`; add three nested page objects:
```
object TabCtrl1: TTyPageControl
  ...
  ActivePageIndex = 1
  object TyTabSheet1: TTyTabSheet
    Caption = 'Tab 1'
  end
  object TyTabSheet2: TTyTabSheet
    Caption = 'Tab 2'
  end
  object TyTabSheet3: TTyTabSheet
    Caption = 'Tab 3'
  end
end
```
(Preserve `TabCtrl1`'s `Left/Top/Width/Height/Align` etc. as they are.)

- [ ] **Step 2: Check `mainform.pas`** for any `TabCtrl1.Tabs` / `.AddTab` / `.TabIndex` usage; if `TabCtrl1` is only a published field with no such calls, no code change is needed. If `tyControls.TabControl` is in its `uses`, replace with `tyControls.PageControl, tyControls.TabSheet`.

- [ ] **Step 3: Build the demo.**
Run: `lazbuild examples/demo/demo.lpi`
Expected: compiles.

- [ ] **Step 4: Commit**
```bash
git add examples/demo/mainform.lfm examples/demo/mainform.pas
git commit -m "chore(examples): migrate demo TabControl -> TTyPageControl"
```

## Task 10: Docs + final verification

**Files:** rename `docs/controls/tabcontrol.md` → `docs/controls/pagecontrol.md` and rewrite for the new control.

- [ ] **Step 1: Rewrite the doc** — `git mv docs/controls/tabcontrol.md docs/controls/pagecontrol.md`, retitle to `TTyPageControl`, describe: the `TTyTabSheet` page model, `ActivePage`/`ActivePageIndex`/`Pages[]`/`AddPage`/`RemovePage`, design-time use (drop the control, use the component-editor **Add Page** verb, drop controls on the visible page, switch via the editor verbs / Object Inspector), and that there is no header click-switch (custom-drawn control + designer limitation). Note `TTyTabSet` is coming in SP2.

- [ ] **Step 2: Full build + suite.**
Run: `lazbuild tyControls.lpk && lazbuild tycontrols_dt.lpk && lazbuild examples/demo/demo.lpi && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain`
Expected: all compile; 0 failures (11 pre-existing headless errors).

- [ ] **Step 3: Commit**
```bash
git add docs/controls/pagecontrol.md
git commit -m "docs(controls): document TTyPageControl (replaces tabcontrol.md)"
```

---

## Self-review checklist (run after implementation)

- Spec coverage: base extraction (T1), TabSheet (T2), PageControl + designer integration (T3), streaming guard (T4), component editor + registration (T5), icons (T6), packages (T7), removal (T8), demo (T9), docs (T10). All spec sections mapped.
- The header click-switch is intentionally absent (per spec).
- `ActivePageIndex`/`FTabIndex`/`FPendingTabIndex` are the same field viewed two ways — confirm `FTabIndex`/`FPendingTabIndex` are `protected` in the base so the PageControl can touch them.

## Manual verification (IDE — cannot be headless)

Rebuild `tycontrols_dt.lpk`, restart Lazarus, drop a `TTyPageControl`, right-click → **Add Page**, drop a button on the visible page, switch pages via the verbs, save + reload the form, confirm the button persists on its page.
