# 轻量三件 (TTySplitter / TTyStatusBar / TTyToolBar) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three custom-drawn, fully-themed Ty-native controls — a drag-resize `TTySplitter`, a bottom `TTyStatusBar`, and a `TTyToolBar` that auto-arranges child `TTyButton`s — at LCL-common-API parity.

**Architecture:** All three descend from `TTyCustomControl` (windowed) and custom-draw via `TTyPainter`, inheriting the theme plumbing (`Controller`/`StyleClass`/states/events). Three new theme typeKeys (`TySplitter`/`TyStatusBar`/`TyToolBar`) are added token-based to every `.tycss` theme + the generated `DefaultTheme.pas`; ToolBar buttons reuse the existing `TyButton` token. Pure geometry (resize clamp / panel rects / toolbar layout) is factored into testable functions; controls are verified by headless RenderTo pixel tests.

**Tech Stack:** Free Pascal / Lazarus LCL, BGRABitmap, the ty-controls `.tycss` theme engine, fpcunit.

**Spec:** `docs/superpowers/specs/2026-06-26-tycontrols-lightweight-controls-design.md`. **Branch:** `feat/lightweight-controls` (already created; spec committed at `76993d2`).

---

## Conventions (read once)

- **Build runtime pkg:** `lazbuild tycontrols.lpk` — expect exit 0.
- **Build+run tests:** `lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain` — read `Number of failures: 0`. Baseline is **960 run / 0 failures / 11 errors** (the 11 "errors" are pre-existing env-only, not regressions).
- **A new test unit** is wired by (a) `RegisterTest(...)` in its `initialization`, and (b) adding its unit name to the `uses` clause of `tests/tytests.lpr` (NOT the `.lpi`).
- **`AssertEquals(expected, actual)`** — expected first. Optional leading message arg.
- **PPI is pinned to 96** in pixel tests (`Bar.Font.PixelsPerInch := 96` and `RenderTo(..., 96)`).
- **Commit** after each green task. Commit messages in English, ending with the Co-Authored-By line used across this repo.

### Reference skeleton (verbatim, reuse for all three controls)

A windowed themed control (`tyControls.GroupBox.pas` / `ScrollBar.pas` pattern):

```pascal
unit tyControls.Xxx;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTyXxx = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;
implementation

function TTyXxx.GetStyleTypeKey: string;
begin
  Result := 'TyXxx';
end;

procedure TTyXxx.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;
```

`CurrentStyle` resolves theme+states in one line; `DrawFrame(P, R, S)` paints bg+border+focus; a sub-element resolves its own key via `ActiveController.Model.ResolveStyle('TyXxx', '', states)`. `P.Scale(logicalPx)` → device px. `ResolveFontSize(S)` for `DrawText`'s size arg.

Pixel-test harness (verbatim from `tests/test.trackbar.pas`): an `Access` subclass re-exposes protected `RenderTo`; build the theme with `Ctl.LoadThemeCss('TyXxx { ... }')`; render into a `pf32bit` `TBitmap`; re-wrap as `TBGRABitmap`; assert color channels with tolerance bands.

---

## Task 0: shared `TTyRectArray` type

**Files:** Modify `source/tyControls.Types.pas` (add a public array type the StatusBar + ToolBar layout functions return).

- [ ] **Step 1** — In `tyControls.Types.pas`, in the `type` section near the other array helpers, add:
```pascal
  TTyRectArray = array of TRect;
```
- [ ] **Step 2** — `lazbuild tycontrols.lpk` → exit 0.
- [ ] **Step 3** — Commit: `feat(types): add TTyRectArray for layout helpers`.

---

## Task 1: TTySplitter — pure resize function

**Files:** Create `source/tyControls.Splitter.pas` (interface-level pure fn first); Create `tests/test.splitter.pas`; Modify `tests/tytests.lpr`.

- [ ] **Step 1: failing test** — `tests/test.splitter.pas`:
```pascal
unit test.splitter;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, fpcunit, testregistry, tyControls.Splitter;
type
  TSplitterGeomTest = class(TTestCase)
  published
    procedure TestNewSizeGrowShrink;
    procedure TestNewSizeClamps;
  end;
implementation

procedure TSplitterGeomTest.TestNewSizeGrowShrink;
begin
  // alLeft/alTop: sibling precedes the splitter -> +delta grows it
  AssertEquals('alLeft +20', 120, TySplitterNewSize(alLeft, 100, 20, 30, 1000));
  AssertEquals('alTop  +20', 120, TySplitterNewSize(alTop,  100, 20, 30, 1000));
  // alRight/alBottom: sibling follows the splitter -> +delta shrinks it
  AssertEquals('alRight +20', 80, TySplitterNewSize(alRight,  100, 20, 30, 1000));
  AssertEquals('alBottom +20', 80, TySplitterNewSize(alBottom, 100, 20, 30, 1000));
end;

procedure TSplitterGeomTest.TestNewSizeClamps;
begin
  AssertEquals('floor at MinSize', 30, TySplitterNewSize(alLeft, 100, -500, 30, 1000));
  AssertEquals('ceil at MaxSize',  200, TySplitterNewSize(alLeft, 100, 500, 30, 200));
  // MaxSize < MinSize means "no max" (unknown) -> only the floor applies
  AssertEquals('no max when max<min', 600, TySplitterNewSize(alLeft, 100, 500, 30, -1));
end;

initialization
  RegisterTest(TSplitterGeomTest);
end.
```
- [ ] **Step 2** — Create `source/tyControls.Splitter.pas` with ONLY the pure fn so it compiles:
```pascal
unit tyControls.Splitter;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base;

function TySplitterNewSize(AAlign: TAlign; AStartSize, ADelta, AMinSize, AMaxSize: Integer): Integer;

implementation

function TySplitterNewSize(AAlign: TAlign; AStartSize, ADelta, AMinSize, AMaxSize: Integer): Integer;
begin
  case AAlign of
    alRight, alBottom: Result := AStartSize - ADelta;
  else
    Result := AStartSize + ADelta;
  end;
  if Result < AMinSize then Result := AMinSize;
  if (AMaxSize >= AMinSize) and (Result > AMaxSize) then Result := AMaxSize;
end;

end.
```
- [ ] **Step 3** — Add `source/tyControls.Splitter.pas` to `tycontrols.lpk` (`<Item><Filename Value="source/tyControls.Splitter.pas"/><UnitName Value="tyControls.Splitter"/></Item>`). Add `test.splitter` to the `uses` clause of `tests/tytests.lpr`.
- [ ] **Step 4** — `lazbuild tycontrols.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain` → the 2 new tests pass, failures still 0.
- [ ] **Step 5** — Commit: `feat(splitter): TySplitterNewSize resize-clamp pure function + tests`.

---

## Task 2: TTySplitter — the control

**Files:** Modify `source/tyControls.Splitter.pas`.

- [ ] **Step 1** — Replace the unit with the full control (keeps `TySplitterNewSize`). The control resizes the sibling adjacent on its `Align` side; live (`rsUpdate`) or deferred (`rsLine`):
```pascal
unit tyControls.Splitter;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTySplitterCanResizeEvent = procedure(Sender: TObject; var ANewSize: Integer; var AAccept: Boolean) of object;

  TTySplitter = class(TTyCustomControl)
  private
    FMinSize: Integer;
    FResizeStyle: TResizeStyle;
    FOnCanResize: TTySplitterCanResizeEvent;
    FOnMoved: TNotifyEvent;
    FTarget: TControl;
    FDragging: Boolean;
    FMouseStart: Integer;     // mouse coord (screen-axis) at drag start
    FStartSize: Integer;      // target size at drag start
    FLineOfs: Integer;        // rsLine ghost position (logical, along axis)
    function Vertical: Boolean;     // a left/right splitter resizes horizontally
    function FindResizeTarget: TControl;
    function AxisSize(AControl: TControl): Integer;
    procedure ApplySize(ANewSize: Integer);
    procedure SetMinSize(AValue: Integer);
    procedure UpdateCursor;
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure Loaded; override;     // re-derive the cursor after Align streams in
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property MinSize: Integer read FMinSize write SetMinSize default 30;
    property ResizeStyle: TResizeStyle read FResizeStyle write FResizeStyle default rsUpdate;
    property OnCanResize: TTySplitterCanResizeEvent read FOnCanResize write FOnCanResize;
    property OnMoved: TNotifyEvent read FOnMoved write FOnMoved;
    property Align default alLeft;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

function TySplitterNewSize(AAlign: TAlign; AStartSize, ADelta, AMinSize, AMaxSize: Integer): Integer;

implementation

function TySplitterNewSize(AAlign: TAlign; AStartSize, ADelta, AMinSize, AMaxSize: Integer): Integer;
begin
  case AAlign of
    alRight, alBottom: Result := AStartSize - ADelta;
  else
    Result := AStartSize + ADelta;
  end;
  if Result < AMinSize then Result := AMinSize;
  if (AMaxSize >= AMinSize) and (Result > AMaxSize) then Result := AMaxSize;
end;

constructor TTySplitter.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMinSize := 30;
  FResizeStyle := rsUpdate;
  Align := alLeft;
  Width := 5;
  Height := 100;
  UpdateCursor;
end;

function TTySplitter.GetStyleTypeKey: string;
begin
  Result := 'TySplitter';
end;

function TTySplitter.Vertical: Boolean;
begin
  Result := Align in [alLeft, alRight];   // vertical bar -> resizes width (horizontal drag)
end;

procedure TTySplitter.UpdateCursor;
begin
  if Vertical then Cursor := crHSplit else Cursor := crVSplit;
end;

procedure TTySplitter.Loaded;
begin
  inherited Loaded;
  UpdateCursor;
end;

procedure TTySplitter.SetMinSize(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  FMinSize := AValue;
end;

function TTySplitter.AxisSize(AControl: TControl): Integer;
begin
  if Vertical then Result := AControl.Width else Result := AControl.Height;
end;

// Mirror TCustomSplitter: the resized control is the sibling immediately on the
// anchored side of the splitter (left of an alLeft bar, above an alTop bar, etc.),
// overlapping the perpendicular extent.
function TTySplitter.FindResizeTarget: TControl;
var
  i: Integer;
  c, best: TControl;
  bestEdge: Integer;
begin
  Result := nil; best := nil;
  if Parent = nil then Exit;
  bestEdge := Low(Integer);
  for i := 0 to Parent.ControlCount - 1 do
  begin
    c := Parent.Controls[i];
    if (c = Self) or (not c.Visible) then Continue;
    case Align of
      alLeft:   if (c.Left + c.Width <= Left) and (c.Left + c.Width > bestEdge) then begin best := c; bestEdge := c.Left + c.Width; end;
      alRight:  if (c.Left >= Left + Width) and (-c.Left > bestEdge) then begin best := c; bestEdge := -c.Left; end;
      alTop:    if (c.Top + c.Height <= Top) and (c.Top + c.Height > bestEdge) then begin best := c; bestEdge := c.Top + c.Height; end;
      alBottom: if (c.Top >= Top + Height) and (-c.Top > bestEdge) then begin best := c; bestEdge := -c.Top; end;
    end;
  end;
  Result := best;
end;

procedure TTySplitter.ApplySize(ANewSize: Integer);
var
  maxSize, n: Integer;
  accept: Boolean;
begin
  if FTarget = nil then Exit;
  if Vertical then maxSize := Parent.ClientWidth - Width else maxSize := Parent.ClientHeight - Height;
  n := TySplitterNewSize(Align, FStartSize, ANewSize, FMinSize, maxSize);
  accept := True;
  if Assigned(FOnCanResize) then FOnCanResize(Self, n, accept);
  if not accept then Exit;
  if Vertical then FTarget.Width := n else FTarget.Height := n;
end;

procedure TTySplitter.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  FTarget := FindResizeTarget;
  if FTarget = nil then Exit;
  FDragging := True;
  FStartSize := AxisSize(FTarget);
  if Vertical then FMouseStart := X else FMouseStart := Y;   // X/Y are control-local; constant origin is fine for a delta
  FLineOfs := 0;
end;

procedure TTySplitter.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  delta: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if not FDragging then Exit;
  if Vertical then delta := X - FMouseStart else delta := Y - FMouseStart;
  if FResizeStyle = rsUpdate then
    ApplySize(delta)
  else
  begin
    FLineOfs := delta;       // rsLine: remember, draw ghost, apply on MouseUp
    Invalidate;
  end;
end;

procedure TTySplitter.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  delta: Integer;
begin
  if FDragging then
  begin
    if FResizeStyle = rsLine then
    begin
      if Vertical then delta := X - FMouseStart else delta := Y - FMouseStart;
      ApplySize(delta);
      FLineOfs := 0;
      Invalidate;
    end;
    FDragging := False;
    FTarget := nil;
    if Assigned(FOnMoved) then FOnMoved(Self);
  end;
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TTySplitter.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTySplitter.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  W, H, cx, cy, i, gap, dot: Integer;
  grip: TTyFill;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    W := ARect.Right - ARect.Left;
    H := ARect.Bottom - ARect.Top;
    DrawFrame(P, Rect(0, 0, W, H), S);     // honors a themed background if set (default: none)
    // 3 grip dots centered, in S.TextColor
    grip := Default(TTyFill);
    grip.Kind := tfkSolid;
    grip.Color := S.TextColor;
    dot := P.Scale(2);
    gap := P.Scale(3);
    cx := W div 2; cy := H div 2;
    for i := -1 to 1 do
      if Vertical then
        P.FillBackground(Rect(cx - dot div 2, cy + i*gap - dot div 2, cx - dot div 2 + dot, cy + i*gap - dot div 2 + dot), grip, dot div 2)
      else
        P.FillBackground(Rect(cx + i*gap - dot div 2, cy - dot div 2, cx + i*gap - dot div 2 + dot, cy - dot div 2 + dot), grip, dot div 2);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
```
- [ ] **Step 2** — Behavior test in `tests/test.splitter.pas`: add a `TSplitterControlTest` that builds a parent form with an `alLeft` panel + an `alLeft` splitter, fakes a drag, and asserts the panel resized & clamped. Add:
```pascal
  TSplitterControlTest = class(TTestCase)
  published
    procedure TestDragResizesLeftNeighbor;
  end;
...
procedure TSplitterControlTest.TestDragResizesLeftNeighbor;
var
  Form: TForm; Pan: TPanel; Sp: TTySplitterProbe;
begin
  Form := TForm.CreateNew(nil);
  try
    Form.SetBounds(0, 0, 400, 200);
    Pan := TPanel.Create(Form); Pan.Parent := Form; Pan.Align := alLeft; Pan.Width := 100;
    Sp := TTySplitterProbe.Create(Form); Sp.Parent := Form; Sp.Align := alLeft; Sp.Left := 100; Sp.Width := 5; Sp.Height := 200;
    Sp.MinSize := 40;
    Sp.FakeDrag(0, 130, 0);   // start x=0, move to x=130 -> +130 delta on a 100px panel
    AssertEquals('left panel grew to 200 (clamped under maxSize)', 200, Pan.Width);
    Sp.FakeDrag(0, -500, 0);  // shrink hard -> floor at MinSize 40
    AssertEquals('left panel floored at MinSize', 40, Pan.Width);
  finally
    Form.Free;
  end;
end;
```
Add a `TTySplitterProbe = class(TTySplitter)` exposing a `FakeDrag(startX, endX, dummy)` that calls `MouseDown/MouseMove/MouseUp` with synthetic coords. (`uses` adds `Forms, ExtCtrls, tyControls.Splitter`.) The probe's `FakeDrag` issues `MouseDown(mbLeft,[],startX,YMid)`, `MouseMove([],endX,YMid)`, `MouseUp(mbLeft,[],endX,YMid)`.
- [ ] **Step 3** — `lazbuild tycontrols.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain` → green.
- [ ] **Step 4** — Commit: `feat(splitter): TTySplitter control (drag-resize neighbor, rsLine/rsUpdate, OnCanResize/OnMoved)`.

---

## Task 3: TTyStatusBar — panel-rects function + the control

**Files:** Create `source/tyControls.StatusBar.pas`; Create `tests/test.statusbar.pas`; Modify `tycontrols.lpk`, `tests/tytests.lpr`.

- [ ] **Step 1: failing test** — `tests/test.statusbar.pas` (pure-fn first):
```pascal
unit test.statusbar;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, fpcunit, testregistry, tyControls.Types, tyControls.StatusBar;
type
  TStatusBarGeomTest = class(TTestCase)
  published
    procedure TestPanelRectsFixed;
    procedure TestPanelRectsFillPanel;
  end;
implementation
procedure TStatusBarGeomTest.TestPanelRectsFixed;
var r: TTyRectArray;
begin
  r := TyStatusPanelRects([50, 80], 200, 0);
  AssertEquals('count', 2, Length(r));
  AssertEquals('p0.left', 0, r[0].Left);   AssertEquals('p0.right', 50, r[0].Right);
  AssertEquals('p1.left', 50, r[1].Left);  AssertEquals('p1.right', 130, r[1].Right);
end;
procedure TStatusBarGeomTest.TestPanelRectsFillPanel;
var r: TTyRectArray;
begin
  // a panel with Width<=0 fills the remaining width (first such panel only)
  r := TyStatusPanelRects([50, 0, 40], 200, 0);
  AssertEquals('fill panel right', 160, r[1].Right);   // 50 + (200-50-40)=110 -> 50..160
  AssertEquals('p2 left', 160, r[2].Left);             AssertEquals('p2 right', 200, r[2].Right);
end;
initialization
  RegisterTest(TStatusBarGeomTest);
end.
```
- [ ] **Step 2** — Create `source/tyControls.StatusBar.pas` with the full control + the pure fn. Panels collection, `SimplePanel`/`SimpleText`/`SizeGrip`, `PanelAtPos`. The fill rule: a single `Width<=0` panel absorbs leftover width; later `<=0` panels get 0.
```pascal
unit tyControls.StatusBar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTyStatusPanel = class(TCollectionItem)
  private
    FText: string;
    FWidth: Integer;
    FAlignment: TAlignment;
    procedure SetText(const AValue: string);
    procedure SetWidth(AValue: Integer);
    procedure SetAlignment(AValue: TAlignment);
  public
    constructor Create(ACollection: TCollection); override;
  published
    property Text: string read FText write SetText;
    property Width: Integer read FWidth write SetWidth default 50;
    property Alignment: TAlignment read FAlignment write SetAlignment default taLeftJustify;
  end;

  TTyStatusBar = class;

  TTyStatusPanels = class(TOwnedCollection)
  private
    function GetItem(AIndex: Integer): TTyStatusPanel;
  protected
    procedure Update(Item: TCollectionItem); override;   // repaint owner on any panel change
  public
    function Add: TTyStatusPanel;
    property Items[AIndex: Integer]: TTyStatusPanel read GetItem; default;
  end;

  TTyStatusBar = class(TTyCustomControl)
  private
    FPanels: TTyStatusPanels;
    FSimplePanel: Boolean;
    FSimpleText: string;
    FSizeGrip: Boolean;
    procedure SetPanels(AValue: TTyStatusPanels);
    procedure SetSimplePanel(AValue: Boolean);
    procedure SetSimpleText(const AValue: string);
    procedure SetSizeGrip(AValue: Boolean);
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PanelAtPos(X, Y: Integer): Integer;   // -1 outside any panel / SimplePanel mode
  published
    property Panels: TTyStatusPanels read FPanels write SetPanels;
    property SimplePanel: Boolean read FSimplePanel write SetSimplePanel default False;
    property SimpleText: string read FSimpleText write SetSimpleText;
    property SizeGrip: Boolean read FSizeGrip write SetSizeGrip default True;
    property Align default alBottom;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

function TyStatusPanelRects(const AWidths: array of Integer; ATotalWidth, APadding: Integer): TTyRectArray;

implementation

function TyStatusPanelRects(const AWidths: array of Integer; ATotalWidth, APadding: Integer): TTyRectArray;
var
  i, x, fixed, fillIdx, fillW: Integer;
begin
  SetLength(Result, Length(AWidths));
  // total fixed width + locate the first fill (<=0) panel
  fixed := 0; fillIdx := -1;
  for i := 0 to High(AWidths) do
    if AWidths[i] > 0 then Inc(fixed, AWidths[i])
    else if fillIdx < 0 then fillIdx := i;
  fillW := ATotalWidth - 2*APadding - fixed;
  if fillW < 0 then fillW := 0;
  x := APadding;
  for i := 0 to High(AWidths) do
  begin
    Result[i].Left := x;
    Result[i].Top := 0;
    if AWidths[i] > 0 then Inc(x, AWidths[i])
    else if i = fillIdx then Inc(x, fillW);   // later <=0 panels add 0
    Result[i].Right := x;
    Result[i].Bottom := 0;   // caller sets vertical extent
  end;
end;

{ TTyStatusPanel }
constructor TTyStatusPanel.Create(ACollection: TCollection);
begin
  inherited Create(ACollection);
  FWidth := 50;
  FAlignment := taLeftJustify;
end;
procedure TTyStatusPanel.SetText(const AValue: string);
begin if FText = AValue then Exit; FText := AValue; Changed(False); end;
procedure TTyStatusPanel.SetWidth(AValue: Integer);
begin if FWidth = AValue then Exit; FWidth := AValue; Changed(False); end;
procedure TTyStatusPanel.SetAlignment(AValue: TAlignment);
begin if FAlignment = AValue then Exit; FAlignment := AValue; Changed(False); end;

{ TTyStatusPanels }
function TTyStatusPanels.GetItem(AIndex: Integer): TTyStatusPanel;
begin Result := TTyStatusPanel(inherited Items[AIndex]); end;
function TTyStatusPanels.Add: TTyStatusPanel;
begin Result := TTyStatusPanel(inherited Add); end;

{ TTyStatusBar }
constructor TTyStatusBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPanels := TTyStatusPanels.Create(Self, TTyStatusPanel);
  FSizeGrip := True;
  Align := alBottom;
  Width := 200;
  Height := 22;
end;
destructor TTyStatusBar.Destroy;
begin
  FPanels.Free;
  inherited Destroy;
end;
procedure TTyStatusPanels.Update(Item: TCollectionItem);
begin
  inherited Update(Item);
  if (GetOwner <> nil) and (GetOwner is TControl) then TControl(GetOwner).Invalidate;
end;
procedure TTyStatusBar.SetPanels(AValue: TTyStatusPanels); begin FPanels.Assign(AValue); end;
procedure TTyStatusBar.SetSimplePanel(AValue: Boolean); begin if FSimplePanel = AValue then Exit; FSimplePanel := AValue; Invalidate; end;
procedure TTyStatusBar.SetSimpleText(const AValue: string); begin if FSimpleText = AValue then Exit; FSimpleText := AValue; if FSimplePanel then Invalidate; end;
procedure TTyStatusBar.SetSizeGrip(AValue: Boolean); begin if FSizeGrip = AValue then Exit; FSizeGrip := AValue; Invalidate; end;

function TTyStatusBar.GetStyleTypeKey: string;
begin Result := 'TyStatusBar'; end;

function TTyStatusBar.PanelAtPos(X, Y: Integer): Integer;
var
  rects: TTyRectArray;
  ws: array of Integer;
  i: Integer;
begin
  Result := -1;
  if FSimplePanel or (FPanels.Count = 0) then Exit;
  SetLength(ws, FPanels.Count);
  for i := 0 to FPanels.Count - 1 do ws[i] := FPanels[i].Width;
  rects := TyStatusPanelRects(ws, ClientWidth, 6);   // 6 = logical padding; see RenderTo
  for i := 0 to High(rects) do
    if (X >= rects[i].Left) and (X < rects[i].Right) then Exit(i);
end;

procedure TTyStatusBar.Paint;
begin RenderTo(Canvas, ClientRect, Font.PixelsPerInch); end;

procedure TTyStatusBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  W, H, i, padX, fs, bw, gx, gy, k: Integer;
  bg, grip: TTyFill;
  rects: TTyRectArray;
  ws: array of Integer;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    W := ARect.Right - ARect.Left; H := ARect.Bottom - ARect.Top;
    padX := P.Scale(6);
    fs := ResolveFontSize(S);
    // background fill (whole) + a 1px top border line (status-bar look — not a full frame)
    bg := Default(TTyFill); bg.Kind := tfkSolid; bg.Color := S.Background.Color;
    if tpBackground in S.Present then P.FillBackground(Rect(0, 0, W, H), bg, 0);
    bw := P.Scale(S.BorderWidth); if bw < 1 then bw := 1;
    if tpBorderColor in S.Present then
    begin
      bg.Color := S.BorderColor;
      P.FillBackground(Rect(0, 0, W, bw), bg, 0);   // top hairline
    end;
    if FSimplePanel then
      P.DrawText(Rect(padX, 0, W - padX, H), FSimpleText, S.FontName, fs, S.FontWeight, S.TextColor, taLeftJustify, tlCenter, True)
    else
    begin
      SetLength(ws, FPanels.Count);
      for i := 0 to FPanels.Count - 1 do ws[i] := FPanels[i].Width;
      rects := TyStatusPanelRects(ws, W, padX);
      for i := 0 to High(rects) do
      begin
        if i > 0 then   // separator before each panel after the first
        begin
          bg.Color := S.BorderColor;
          P.FillBackground(Rect(rects[i].Left, P.Scale(3), rects[i].Left + 1, H - P.Scale(3)), bg, 0);
        end;
        P.DrawText(Rect(rects[i].Left + P.Scale(2), 0, rects[i].Right - P.Scale(2), H),
          FPanels[i].Text, S.FontName, fs, S.FontWeight, S.TextColor, FPanels[i].Alignment, tlCenter, True);
      end;
    end;
    if FSizeGrip then    // 3 diagonal dots, bottom-right, in muted text color
    begin
      grip := Default(TTyFill); grip.Kind := tfkSolid; grip.Color := S.TextColor;
      for k := 0 to 2 do
      begin
        gx := W - P.Scale(3) - k*P.Scale(4);
        gy := H - P.Scale(3) - k*P.Scale(4);
        P.FillBackground(Rect(gx, gy, gx + P.Scale(2), gy + P.Scale(2)), grip, P.Scale(1));
      end;
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
```
- [ ] **Step 3** — Add the unit to `tycontrols.lpk`; add `test.statusbar` to `tests/tytests.lpr` uses. `lazbuild tycontrols.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain` → the 2 pure-fn tests pass, failures 0.
- [ ] **Step 4** — Commit: `feat(statusbar): TTyStatusBar (panels + SimplePanel + SizeGrip + PanelAtPos) + panel-rects fn/tests`.

---

## Task 4: TTyToolBar — layout function, separator, control

**Files:** Create `source/tyControls.ToolBar.pas`; Create `tests/test.toolbar.pas`; Modify `tycontrols.lpk`, `tests/tytests.lpr`. **Depends on** `tyControls.Button` (re-style children) — add to `uses`.

- [ ] **Step 1: failing test** — `tests/test.toolbar.pas` (pure layout fn):
```pascal
unit test.toolbar;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, fpcunit, testregistry, tyControls.Types, tyControls.ToolBar;
type
  TToolBarGeomTest = class(TTestCase)
  published
    procedure TestLayoutSingleRow;
    procedure TestLayoutWraps;
  end;
implementation
procedure TToolBarGeomTest.TestLayoutSingleRow;
var r: TTyRectArray; rows: Integer;
begin
  // two 40x20 items, indent 4, spacing 2, buttonHeight 24, bar 200 wide
  r := TyToolbarLayout([Size(40,20), Size(40,20)], 200, 4, 2, 24, True, rows);
  AssertEquals('rows', 1, rows);
  AssertEquals('i0.left', 4, r[0].Left);     AssertEquals('i0.right', 44, r[0].Right);
  AssertEquals('i1.left', 46, r[1].Left);    AssertEquals('i1.right', 86, r[1].Right);
  AssertEquals('i0.height=buttonHeight', 24, r[0].Bottom - r[0].Top);
end;
procedure TToolBarGeomTest.TestLayoutWraps;
var r: TTyRectArray; rows: Integer;
begin
  // bar only 90 wide -> third item wraps to row 2
  r := TyToolbarLayout([Size(40,20), Size(40,20), Size(40,20)], 90, 4, 2, 24, True, rows);
  AssertEquals('rows', 2, rows);
  AssertEquals('i2 wrapped to indent', 4, r[2].Left);
  AssertTrue('i2 on row 2 (top > i0 top)', r[2].Top > r[0].Top);
end;
initialization
  RegisterTest(TToolBarGeomTest);
end.
```
- [ ] **Step 2** — Create `source/tyControls.ToolBar.pas` with the layout fn, the separator control, and the toolbar:
```pascal
unit tyControls.ToolBar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Button;
type
  TTyToolSeparator = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Align;
    property StyleClass;
    property Controller;
  end;

  TTyToolBar = class(TTyCustomControl)
  private
    FButtonHeight: Integer;
    FButtonSpacing: Integer;
    FIndent: Integer;
    FWrapable: Boolean;
    FShowCaptions: Boolean;
    FFlat: Boolean;
    FImages: TImageList;
    procedure SetButtonHeight(AValue: Integer);
    procedure SetButtonSpacing(AValue: Integer);
    procedure SetIndent(AValue: Integer);
    procedure SetWrapable(AValue: Boolean);
    procedure SetShowCaptions(AValue: Boolean);
    procedure SetImages(AValue: TImageList);
    procedure SetFlat(AValue: Boolean);
    procedure Relayout;
    procedure ApplyToButton(B: TTyButton);
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure AlignControls(AControl: TControl; var ARect: TRect); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ButtonHeight: Integer read FButtonHeight write SetButtonHeight default 24;
    property ButtonSpacing: Integer read FButtonSpacing write SetButtonSpacing default 2;
    property Indent: Integer read FIndent write SetIndent default 4;
    property Wrapable: Boolean read FWrapable write SetWrapable default True;
    property ShowCaptions: Boolean read FShowCaptions write SetShowCaptions default False;
    property Flat: Boolean read FFlat write SetFlat default True;
    property Images: TImageList read FImages write SetImages;
    property Align default alTop;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

function TyToolbarLayout(const AItemSizes: array of TSize; ABarWidth, AIndent, ASpacing, AButtonHeight: Integer; AWrapable: Boolean; out ARows: Integer): TTyRectArray;

implementation

function TyToolbarLayout(const AItemSizes: array of TSize; ABarWidth, AIndent, ASpacing, AButtonHeight: Integer; AWrapable: Boolean; out ARows: Integer): TTyRectArray;
var
  i, x, y, rowH: Integer;
begin
  SetLength(Result, Length(AItemSizes));
  ARows := 1;
  x := AIndent; y := AIndent; rowH := AButtonHeight;
  for i := 0 to High(AItemSizes) do
  begin
    if AWrapable and (i > 0) and (x + AItemSizes[i].cx > ABarWidth - AIndent) then
    begin
      x := AIndent; Inc(y, rowH + ASpacing); Inc(ARows);
    end;
    Result[i].Left := x;
    Result[i].Top := y;
    Result[i].Right := x + AItemSizes[i].cx;
    Result[i].Bottom := y + AButtonHeight;
    Inc(x, AItemSizes[i].cx + ASpacing);
  end;
end;

{ TTyToolSeparator }
constructor TTyToolSeparator.Create(AOwner: TComponent);
begin inherited Create(AOwner); Width := 8; Height := 24; end;
function TTyToolSeparator.GetStyleTypeKey: string; begin Result := 'TyToolBar'; end;  // borrows the bar's border color
procedure TTyToolSeparator.Paint; begin RenderTo(Canvas, ClientRect, Font.PixelsPerInch); end;
procedure TTyToolSeparator.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var P: TTyPainter; S: TTyStyleSet; W, H: Integer; line: TTyFill;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    W := ARect.Right - ARect.Left; H := ARect.Bottom - ARect.Top;
    line := Default(TTyFill); line.Kind := tfkSolid; line.Color := S.BorderColor;
    P.FillBackground(Rect(W div 2, P.Scale(3), W div 2 + 1, H - P.Scale(3)), line, 0);
    P.EndPaint;
  finally P.Free; end;
end;

{ TTyToolBar }
constructor TTyToolBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls];   // hosts the tool buttons
  FButtonHeight := 24; FButtonSpacing := 2; FIndent := 4; FWrapable := True; FFlat := True;
  Align := alTop;
  Width := 300; Height := 30;
end;

function TTyToolBar.GetStyleTypeKey: string; begin Result := 'TyToolBar'; end;

procedure TTyToolBar.SetButtonHeight(AValue: Integer); begin if FButtonHeight = AValue then Exit; FButtonHeight := AValue; Relayout; end;
procedure TTyToolBar.SetButtonSpacing(AValue: Integer); begin if FButtonSpacing = AValue then Exit; FButtonSpacing := AValue; Relayout; end;
procedure TTyToolBar.SetIndent(AValue: Integer); begin if FIndent = AValue then Exit; FIndent := AValue; Relayout; end;
procedure TTyToolBar.SetWrapable(AValue: Boolean); begin if FWrapable = AValue then Exit; FWrapable := AValue; Relayout; end;
procedure TTyToolBar.SetShowCaptions(AValue: Boolean); begin if FShowCaptions = AValue then Exit; FShowCaptions := AValue; Relayout; end;
procedure TTyToolBar.SetImages(AValue: TImageList); begin FImages := AValue; Relayout; end;
procedure TTyToolBar.SetFlat(AValue: Boolean); begin if FFlat = AValue then Exit; FFlat := AValue; Relayout; end;

procedure TTyToolBar.ApplyToButton(B: TTyButton);
begin
  // reuse the ghost/flat TTyButton; propagate the bar's button metrics
  if FFlat then B.StyleClass := 'ghost';
  // (Images/ShowCaptions propagation hooks here if/when TTyButton exposes them.)
end;

procedure TTyToolBar.Relayout;
begin
  if csDestroying in ComponentState then Exit;
  Realign;        // re-runs AlignControls over the children
  Invalidate;
end;

procedure TTyToolBar.AlignControls(AControl: TControl; var ARect: TRect);
var
  i, n, rows: Integer;
  sizes: array of TSize;
  rects: TTyRectArray;
  ctl: TControl;
  list: array of TControl;
begin
  // collect visible non-splitter children in child order
  SetLength(list, ControlCount); n := 0;
  for i := 0 to ControlCount - 1 do
  begin
    ctl := Controls[i];
    if ctl.Visible then begin list[n] := ctl; Inc(n); end;
  end;
  SetLength(list, n); SetLength(sizes, n);
  for i := 0 to n - 1 do
  begin
    if list[i] is TTyButton then ApplyToButton(TTyButton(list[i]));
    sizes[i].cx := list[i].Width;
    sizes[i].cy := list[i].Height;
  end;
  rects := TyToolbarLayout(sizes, ClientWidth, FIndent, FButtonSpacing, FButtonHeight, FWrapable, rows);
  for i := 0 to n - 1 do
    list[i].SetBounds(rects[i].Left, rects[i].Top, list[i].Width, FButtonHeight);
  // grow the bar to fit the rows when alTop/alBottom
  if (Align in [alTop, alBottom]) and (rows > 0) then
    Height := FIndent*2 + rows*FButtonHeight + (rows-1)*FButtonSpacing;
end;

procedure TTyToolBar.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FImages) then FImages := nil;
end;

procedure TTyToolBar.Paint; begin RenderTo(Canvas, ClientRect, Font.PixelsPerInch); end;
procedure TTyToolBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var P: TTyPainter; S: TTyStyleSet; W, H, bw: Integer; bg: TTyFill;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    W := ARect.Right - ARect.Left; H := ARect.Bottom - ARect.Top;
    bg := Default(TTyFill); bg.Kind := tfkSolid; bg.Color := S.Background.Color;
    if tpBackground in S.Present then P.FillBackground(Rect(0, 0, W, H), bg, 0);
    bw := P.Scale(S.BorderWidth); if bw < 1 then bw := 1;
    if tpBorderColor in S.Present then
    begin
      bg.Color := S.BorderColor;
      P.FillBackground(Rect(0, H - bw, W, H), bg, 0);   // bottom hairline
    end;
    P.EndPaint;
  finally P.Free; end;
end;

end.
```
- [ ] **Step 3** — Add the unit to `tycontrols.lpk`; add `test.toolbar` to `tests/tytests.lpr` uses. Build + run → the 2 layout tests pass, failures 0.
- [ ] **Step 4** — Add a control test `TToolBarControlTest.TestArrangesButtons`: create a form + toolbar + two `TTyButton` children, force `Relayout`, assert button 2's `Left` ≈ indent + b1.width + spacing. (`uses` adds `Forms, tyControls.Button`.) Build + run → green.
- [ ] **Step 5** — Commit: `feat(toolbar): TTyToolBar (auto-arrange child TTyButtons + wrap) + TTyToolSeparator + layout fn/tests`.

---

## Task 5: theme typeKeys (byte-synced across all themes + goldens)

**Files:** Modify every `themes/*.tycss`; regenerate `source/tyControls.DefaultTheme.pas`; Modify `tests/test.themes.pas` (GGRID); regenerate `tests/golden/*.golden.txt`; Modify `tests/test.defaulttheme.pas`.

The three rule blocks are token-based, so the **same text** drops into every theme:
```css
TySplitter {
  background: none;
  color: var(--muted);
}
TySplitter:hover {
  color: var(--accent);
}

TyStatusBar {
  background: var(--surface-chrome);
  color: var(--on-surface);
  border-color: var(--border);
  border-width: var(--input-border-width);
  font-size: var(--font-size-base);
  font-weight: var(--font-weight-normal);
}

TyToolBar {
  background: var(--surface-chrome);
  border-color: var(--border);
  border-width: var(--input-border-width);
}
```

- [ ] **Step 1** — Append the three blocks (after the last typeKey, e.g. `TyMenuItem`) in **each** shipped theme: `themes/light.tycss`, `dark.tycss`, `showcase.tycss`, `auto.tycss`, `green.tycss`, `system.tycss`. (If `green.tycss` hard-codes values rather than tokens elsewhere, still use the token form here — green defines the same seed/map tokens.)
- [ ] **Step 2** — Regenerate the Pascal mirror of light: `powershell -File gen-defaulttheme.ps1` (writes `source/tyControls.DefaultTheme.pas`). Do NOT hand-edit that file.
- [ ] **Step 3** — Extend the golden grid in `tests/test.themes.pas`: in `GGRID` append `'TySplitter|', 'TyStatusBar|', 'TyToolBar|'` and bump its array bound (`array[0..36]` → `array[0..39]`).
- [ ] **Step 4** — Re-bootstrap goldens: delete `tests/golden/light.golden.txt`, `dark.golden.txt`, `showcase.golden.txt`; run `lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain` once (CheckGolden re-creates them). Run again → all green (now comparing against the regenerated goldens). `git add` the regenerated goldens.
- [ ] **Step 5** — In `tests/test.defaulttheme.pas` `TestBuiltinCoversAllTypeKeys`, add `AssertBg('TyStatusBar', []);` and `AssertBg('TyToolBar', []);` (TySplitter has `background: none`, so assert its `color` is present instead, or skip it — match the helper's existing style). Build + run → green.
- [ ] **Step 6** — Commit: `feat(theme): TySplitter / TyStatusBar / TyToolBar typeKeys across all themes + goldens`.

---

## Task 6: pixel render tests (per theme)

**Files:** Modify `tests/test.splitter.pas`, `tests/test.statusbar.pas`, `tests/test.toolbar.pas` — add a pixel test each.

- [ ] **Step 1** — In each test unit add an `Access` subclass exposing `RenderTo`, then a pixel test using the harness: build an inline theme via `LoadThemeCss`, render onto a `pf32bit` `TBitmap` at PPI 96, re-wrap as `TBGRABitmap`, assert a channel band. Examples:
  - **Splitter:** theme `'TySplitter { color: #3B82F6; }'`; render a 5×100 vertical splitter; assert the center column has a blue-dominant pixel (the grip dot) — `Px.blue > 150`.
  - **StatusBar:** theme `'TyStatusBar { background: #202020; color: #FFFFFF; border-color: #404040; }'`; one panel `Text='Hi'`; assert a background pixel ≈ (32,32,32) and the top hairline row differs.
  - **ToolBar:** theme `'TyToolBar { background: #202020; border-color: #404040; }'`; assert the bottom hairline row is lighter than the body.
- [ ] **Step 2** — Build + run → all green, failures 0.
- [ ] **Step 3** — Commit: `test(lite-trio): per-theme RenderTo pixel tests for splitter/statusbar/toolbar`.

---

## Task 7: published-events RTTI guard (don't omit events)

**Files:** Create `tests/test.litetrio.events.pas`; Modify `tests/tytests.lpr`.

- [ ] **Step 1** — Assert each control publishes a representative subset of the inherited event set + its specific events, via `TypInfo.GetPropInfo`:
```pascal
unit test.litetrio.events;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, TypInfo, fpcunit, testregistry,
  tyControls.Splitter, tyControls.StatusBar, tyControls.ToolBar;
type
  TLiteTrioEventsTest = class(TTestCase)
  private
    procedure AssertPub(AClass: TClass; const AName: string);
  published
    procedure TestSplitterEvents;
    procedure TestStatusBarEvents;
    procedure TestToolBarEvents;
  end;
implementation
procedure TLiteTrioEventsTest.AssertPub(AClass: TClass; const AName: string);
begin
  AssertNotNull(AClass.ClassName + ' must publish ' + AName, GetPropInfo(AClass, AName));
end;
procedure TLiteTrioEventsTest.TestSplitterEvents;
begin
  AssertPub(TTySplitter, 'OnClick'); AssertPub(TTySplitter, 'OnMouseDown');
  AssertPub(TTySplitter, 'OnMouseMove'); AssertPub(TTySplitter, 'OnKeyDown');
  AssertPub(TTySplitter, 'OnCanResize'); AssertPub(TTySplitter, 'OnMoved');
end;
procedure TLiteTrioEventsTest.TestStatusBarEvents;
begin
  AssertPub(TTyStatusBar, 'OnClick'); AssertPub(TTyStatusBar, 'OnDblClick');
  AssertPub(TTyStatusBar, 'OnMouseDown'); AssertPub(TTyStatusBar, 'OnResize');
end;
procedure TLiteTrioEventsTest.TestToolBarEvents;
begin
  AssertPub(TTyToolBar, 'OnClick'); AssertPub(TTyToolBar, 'OnMouseDown');
  AssertPub(TTyToolBar, 'OnContextPopup'); AssertPub(TTyToolBar, 'OnResize');
end;
initialization
  RegisterTest(TLiteTrioEventsTest);
end.
```
- [ ] **Step 2** — Add `test.litetrio.events` to `tests/tytests.lpr` uses. Build + run. If any assert fails, the control didn't inherit/publish that event — fix by ensuring the override calls `inherited` and the base property isn't shadowed. (TTyCustomControl already publishes Tier A/B; the only specific ones are Splitter's.)
- [ ] **Step 3** — Commit: `test(lite-trio): RTTI guard that the three controls publish the event set`.

---

## Task 8: design-time registration + palette icons

**Files:** Modify `designtime/tyControls.Design.pas`; `scripts/gen-icons.ps1`; `tools/genicons/genicons.lpr`; `tests/test.paletteicons.pas`; then regenerate `designtime/tycontrols_icons.lrs` + `designtime/icons/*.png`.

> The icon drift-guard in `gen-icons.ps1` currently also flags the pre-existing `TTyNativeStyler` (registered, no icon). This task adds icons for `TTyNativeStyler` too so the regeneration passes — closing that known gap.

- [ ] **Step 1** — In `tyControls.Design.pas`: add `tyControls.Splitter, tyControls.StatusBar, tyControls.ToolBar` to the `uses` clause, and append `TTySplitter, TTyStatusBar, TTyToolBar, TTyToolSeparator` to the `RegisterComponents('TyControls', [...])` array.
- [ ] **Step 2** — In `tools/genicons/genicons.lpr`: add a `G<Name>` glyph routine for each of `TTyNativeStyler`, `TTySplitter`, `TTyStatusBar`, `TTyToolBar`, `TTyToolSeparator` (simple BGRA primitives in the 24-unit space — e.g. splitter = a vertical line with two arrows; statusbar = a bottom band with cells; toolbar = a top band with 3 dots; separator = a single vertical line), add a `Glyphs[]` entry for each, and bump the `array[0..N]` bound.
- [ ] **Step 3** — In `scripts/gen-icons.ps1`: add those 5 class names to `$classes`. In `tests/test.paletteicons.pas`: add them to `CClasses` and bump its `array[0..N]` bound.
- [ ] **Step 4** — Regenerate: `pwsh -File scripts/gen-icons.ps1` (builds genicons, renders PNGs, packs the `.lrs`; the drift-guard must pass now). 
- [ ] **Step 5** — Build the dt package `lazbuild tycontrols_dt.lpk` → exit 0. Build+run the suite → `test.paletteicons` green (all listed classes have PNG resources).
- [ ] **Step 6** — Commit: `feat(designtime): register splitter/statusbar/toolbar(+separator) on the palette + icons (also fills TTyNativeStyler icon)`.

---

## Task 9: demo placement

**Files:** Modify `examples/demo/mainform.lfm` + `examples/demo/mainform.pas` (field declarations).

- [ ] **Step 1** — In the demo form add (designer/.lfm, per project rule): a `TTyToolBar` (`Align=alTop`) hosting 2–3 `TTyButton`s + a `TTyToolSeparator`; a `TTyStatusBar` (`Align=alBottom`) with 2 panels (`Width=120` + a `Width=0` fill panel showing text); and a `TTySplitter` between two existing panels. Add the matching published fields to `TDemoMainForm` and the three units to the demo `uses`.
- [ ] **Step 2** — `lazbuild examples/demo/demo.lpi` → exit 0, links `demo.exe`.
- [ ] **Step 3** — Commit: `example(demo): showcase TTyToolBar / TTyStatusBar / TTySplitter`.

---

## Task 10: finish

- [ ] **Step 1** — Full verification: `lazbuild tycontrols.lpk && lazbuild tycontrols_dt.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain` → **failures 0**; `lazbuild examples/demo/demo.lpi` → exit 0.
- [ ] **Step 2** — Use **superpowers:finishing-a-development-branch** to merge `feat/lightweight-controls` → `main` (the user's local-merge pattern; do not push unless asked).
- [ ] **Step 3** — Update the `new-controls-program` memory: sub-project ① done/merged; note any deferrals discovered.

---

## Deferred (NOT this plan — confirm none silently dropped)

Splitter `AutoSnap`/`Beveled`/`ResizeAnchor`; StatusBar owner-draw panels (`OnDrawPanel`)/`Style=psOwnerDraw`; ToolBar dropdown buttons/`EdgeBorders`/drag-rearrange/`HotImages`. Folded-in small items (`TTyTabSet`, tri-state CheckBox, editable ComboBox) are separate later specs.
```
