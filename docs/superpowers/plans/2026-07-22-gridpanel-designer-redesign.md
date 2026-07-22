# TTyGridPanel Designer-Droppable Grid — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild `TTyGridPanel` so that setting `ColumnCount`×`RowCount` in the IDE produces that many droppable `TTyGridCell` containers, each constraining an `alClient` child to its own cell — all authored/streamed in `.lfm`.

**Architecture:** Mirror the working `TTyPageControl`/`TTyTabSheet` pattern: the grid owns an N×M set of form-owned `TTyGridCell` child containers, parented to the grid, self-registering via `SetParent`, streamed by the default `TWinControl.GetChildren`. Track sizes come from published `ColumnSizes`/`RowSizes` strings (default all-star = equal), solved by the existing pure `TyGridTrackSizes`/`TyGridTrackOrigins`/`TyGridCellRect`. No spanning.

**Tech Stack:** Free Pascal / Lazarus LCL, fpcunit tests, the repo's headless render probes. Design spec: `docs/superpowers/specs/2026-07-22-gridpanel-designer-redesign.md`.

**Verification boundary (honest):** headless tests cover track math, cell lifecycle, layout, per-cell padding, `alClient`-constrained-to-cell, published surface, and a `WriteComponent`/`ReadComponent` round-trip. The actual IDE drag-drop feel, design-time grid-line painting, and component-editor verbs must be confirmed by the user in a running Lazarus IDE.

**Reference facts (verified):**
- Solver signatures (`source/tyControls.GridPanel.pas`, keep these functions):
  - `function TyGridTrackSizes(ATotal, ASpacing: Integer; const ATracks: TTyGridTracks): TTyGridIntArray;`
  - `function TyGridTrackOrigins(const ALengths: TTyGridIntArray; ASpacing: Integer): TTyGridIntArray;`
  - `function TyGridCellRect(const AColX, AColW, ARowY, ARowH: TTyGridIntArray; ACol, ARow, AColSpan, ARowSpan: Integer): TRect;`
  - Types: `TTyGridTrackKind = (tgtAbsolute, tgtPercent, tgtStar);` `TTyGridTrack = record Kind: TTyGridTrackKind; Value: Integer; end;` `TTyGridTracks = array of TTyGridTrack;` `TTyGridIntArray = array of Integer;`
- TabSheet self-register idiom: `SetParent` override → `if (AParent is TTyPageControl) then TTyPageControl(AParent).RegisterPage(Self);` + `initialization RegisterClass(...)`.
- `RegisterPage` is idempotent (dup-scan), appends to array, sets Controller; `Notification(opRemove)` → `UnregisterPage(..., AFree:=False)`; `Loaded` runs after children self-registered during streaming.
- Runtime package unit list: `tycontrols.pas:57` (`tyControls.GridPanel`, add `tyControls.GridCell`).
- Designer registration: `designtime/tyControls.Design.pas:702` (Containers group has `TTyGridPanel`).
- Existing tests to touch: `tests/test.gridpanel.pas` (rewrite), `tests/test.grid.layout.pas` (solver, keep), `tests/test.grid.streaming.pas` (published-surface idiom, extend).
- Containers example: `examples/containers/umain.pas:187-191` (SetColumnStyle/SetCell — remove) and `examples/containers/umain.lfm:345` (`object GridForm: TTyGridPanel` ColumnCount=2 RowCount=3).

---

## Task 1: `TTyGridCell` — the transparent cell container

**Files:**
- Create: `source/tyControls.GridCell.pas`
- Test: `tests/test.gridcell.pas`

- [ ] **Step 1: Write the failing test**

Create `tests/test.gridcell.pas`:

```pascal
unit test.gridcell;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, TypInfo, fpcunit, testregistry,
  tyControls.GridCell;
type
  TTyGridCellTest = class(TTestCase)
  published
    procedure TestPublishesDesignerProperties;
    procedure TestPaddingInsetsClientRect;
    procedure TestAlClientChildConstrainedToCell;
  end;
implementation

procedure TTyGridCellTest.TestPublishesDesignerProperties;
const cMust: array[0..6] of string =
  ('Padding', 'Col', 'Row', 'Align', 'Anchors', 'Visible', 'BorderSpacing');
var i: Integer;
begin
  for i := 0 to High(cMust) do
    AssertTrue('TTyGridCell must publish ' + cMust[i],
      GetPropInfo(TTyGridCell, cMust[i]) <> nil);
end;

procedure TTyGridCellTest.TestPaddingInsetsClientRect;
var cell: TTyGridCell; r: TRect;
begin
  cell := TTyGridCell.Create(nil);
  try
    cell.SetBounds(0, 0, 100, 80);
    cell.Padding := 10;
    r := cell.ClientRect;             // AdjustClientRect applied
    AssertEquals('left inset',   10, r.Left);
    AssertEquals('top inset',    10, r.Top);
    AssertEquals('right inset',  90, r.Right);
    AssertEquals('bottom inset', 70, r.Bottom);
  finally
    cell.Free;
  end;
end;

procedure TTyGridCellTest.TestAlClientChildConstrainedToCell;
var cell: TTyGridCell; child: TControl;
begin
  cell := TTyGridCell.Create(nil);
  child := TControl.Create(cell);
  try
    cell.SetBounds(5, 5, 100, 80);
    cell.Padding := 8;
    child.Parent := cell;
    child.Align := alClient;
    cell.HandleNeeded;                // realize alignment
    // child fills the padded client area, never larger than the cell
    AssertEquals('child left',  8, child.Left);
    AssertEquals('child top',   8, child.Top);
    AssertEquals('child width', 100 - 8 - 8, child.Width);
    AssertEquals('child height', 80 - 8 - 8, child.Height);
  finally
    cell.Free;
  end;
end;

initialization
  RegisterTest(TTyGridCellTest);
end.
```

- [ ] **Step 2: Register the new test unit and run it to verify it fails**

Add `test.gridcell` to the test runner's uses clause (find the runner project: `grep -rl "test.gridpanel" tests/*.lpr tests/*.lpi`), then:

Run: `lazbuild -B tests/tytests.lpi`
Expected: FAIL — `Unit not found: tyControls.GridCell` (unit doesn't exist yet).

- [ ] **Step 3: Write `source/tyControls.GridCell.pas`**

```pascal
unit tyControls.GridCell;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls,
  tyControls.Base;
type
  { One cell of a TTyGridPanel. A transparent, windowed container: it paints
    NOTHING (no themed background/border) and only positions + clips + pads its
    dropped children. Col/Row are its grid coordinates (set by the grid, streamed
    so a loaded form re-seats it). Padding insets its content on all sides.
    Mirrors TTyTabSheet's designer-container ControlStyle so the IDE treats it as
    a fixed-bounds, droppable design surface — but stays VISIBLE (all cells show
    at once, unlike a tab page). }
  TTyGridCell = class(TTyCustomControl)
  private
    FPadding: Integer;
    FCol: Integer;
    FRow: Integer;
    procedure SetPadding(AValue: Integer);
  protected
    procedure SetParent(AParent: TWinControl); override;
    function GetStyleTypeKey: string; override;
    procedure AdjustClientRect(var ARect: TRect); override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    { Set by the owning grid; published so a streamed form re-seats the cell. }
    property Col: Integer read FCol write FCol;
    property Row: Integer read FRow write FRow;
  published
    property Padding: Integer read FPadding write SetPadding default 0;
    property Align;
    property Anchors;
    property BorderSpacing;
    property Visible;
    property Constraints;
  end;

implementation

uses
  tyControls.GridPanel;   // for TTyGridPanel in SetParent (one-way: impl only)

constructor TTyGridCell.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls, csDesignFixedBounds, csNoFocus];
  FPadding := 0;
  FCol := -1;
  FRow := -1;
end;

function TTyGridCell.GetStyleTypeKey: string;
begin
  Result := 'TyGridCell';   // has no themed rule today; transparent by design
end;

procedure TTyGridCell.SetPadding(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FPadding = AValue then Exit;
  FPadding := AValue;
  Realign;       // re-lay aligned children into the new padded rect
  Invalidate;
end;

procedure TTyGridCell.AdjustClientRect(var ARect: TRect);
var pad: Integer;
begin
  inherited AdjustClientRect(ARect);
  pad := MulDiv(FPadding, Font.PixelsPerInch, 96);
  Inc(ARect.Left, pad);
  Inc(ARect.Top, pad);
  Dec(ARect.Right, pad);
  Dec(ARect.Bottom, pad);
  if ARect.Right < ARect.Left then ARect.Right := ARect.Left;
  if ARect.Bottom < ARect.Top then ARect.Bottom := ARect.Top;
end;

procedure TTyGridCell.SetParent(AParent: TWinControl);
begin
  inherited SetParent(AParent);
  { Self-register with the hosting grid. Fires for grid-created cells, a designer
    drop, and a streamed load when Parent is applied — so the grid's cell list is
    rebuilt uniformly in all paths. Idempotent on the grid side. }
  if (AParent <> nil) and (AParent is TTyGridPanel) then
    TTyGridPanel(AParent).RegisterCell(Self);
end;

procedure TTyGridCell.Paint;
begin
  // Transparent: draw nothing at runtime. (Design-time grid lines are painted by
  // the parent TTyGridPanel, not per-cell.)
end;

initialization
  RegisterClass(TTyGridCell);
end.
```

> Note: `TTyGridPanel.RegisterCell` does not exist yet (Task 3). This unit will not compile standalone until Task 3 adds it. Implement Task 1's *file* now; the failing test in Step 2 becomes a compile error resolved at the end of Task 3. (Sequencing note — Tasks 1 and 3 are a mutually-referencing pair; commit them together in Task 3's final commit.)

- [ ] **Step 4: Commit the cell unit and its test (red — pending Task 3)**

```bash
git add source/tyControls.GridCell.pas tests/test.gridcell.pas
git commit -m "feat(gridcell): transparent designer cell container (compiles after gridpanel rewrite)"
```

---

## Task 2: Track-size string parsing

**Files:**
- Modify: `source/tyControls.GridPanel.pas` (add `TyParseGridTracks` to interface + implementation)
- Test: `tests/test.grid.layout.pas` (append)

- [ ] **Step 1: Write the failing test** — append to `tests/test.grid.layout.pas` test class:

```pascal
procedure TTyGridLayoutTest.TestParseGridTracks;
var t: TTyGridTracks;
begin
  t := TyParseGridTracks('', 3);          // empty -> N all-star
  AssertEquals('empty count', 3, Length(t));
  AssertTrue('empty all star', t[0].Kind = tgtStar);

  t := TyParseGridTracks('2*, *, 100, 30%', 0);
  AssertEquals('parsed count', 4, Length(t));
  AssertTrue('star2 kind', t[0].Kind = tgtStar);
  AssertEquals('star2 val', 2, t[0].Value);
  AssertTrue('star1 kind', t[1].Kind = tgtStar);
  AssertEquals('star1 val', 1, t[1].Value);
  AssertTrue('abs kind', t[2].Kind = tgtAbsolute);
  AssertEquals('abs val', 100, t[2].Value);
  AssertTrue('pct kind', t[3].Kind = tgtPercent);
  AssertEquals('pct val', 30, t[3].Value);
end;
```

(Add `procedure TestParseGridTracks;` to the published section of the test class.)

- [ ] **Step 2: Run to verify it fails**

Run: `lazbuild -B tests/tytests.lpi`
Expected: FAIL — `Identifier not found "TyParseGridTracks"`.

- [ ] **Step 3: Add `TyParseGridTracks`** — interface declaration near the other `Ty*` grid functions in `source/tyControls.GridPanel.pas`:

```pascal
{ Parse a designer track-template string into tracks. Comma-separated tokens:
  'N*' or '*' = star (N shares, default 1); 'N%' = percent; 'N' = absolute px.
  An EMPTY string yields ADefaultCount all-star tracks (equal distribution). }
function TyParseGridTracks(const ASpec: string; ADefaultCount: Integer): TTyGridTracks;
```

Implementation (in the implementation section):

```pascal
function TyParseGridTracks(const ASpec: string; ADefaultCount: Integer): TTyGridTracks;
var
  parts: TStringList;
  i, v, e: Integer;
  tok: string;
begin
  Result := nil;
  if Trim(ASpec) = '' then
  begin
    if ADefaultCount < 0 then ADefaultCount := 0;
    SetLength(Result, ADefaultCount);
    for i := 0 to ADefaultCount - 1 do
    begin
      Result[i].Kind := tgtStar;
      Result[i].Value := 1;
    end;
    Exit;
  end;
  parts := TStringList.Create;
  try
    parts.Delimiter := ',';
    parts.StrictDelimiter := True;
    parts.DelimitedText := ASpec;
    SetLength(Result, parts.Count);
    for i := 0 to parts.Count - 1 do
    begin
      tok := Trim(parts[i]);
      if (tok <> '') and (tok[Length(tok)] = '*') then
      begin
        Result[i].Kind := tgtStar;
        Val(Copy(tok, 1, Length(tok) - 1), v, e);
        if (e <> 0) or (v < 1) then v := 1;   // '*' alone -> 1 share
        Result[i].Value := v;
      end
      else if (tok <> '') and (tok[Length(tok)] = '%') then
      begin
        Result[i].Kind := tgtPercent;
        Val(Copy(tok, 1, Length(tok) - 1), v, e);
        if e <> 0 then v := 0;
        Result[i].Value := v;
      end
      else
      begin
        Result[i].Kind := tgtAbsolute;
        Val(tok, v, e);
        if e <> 0 then v := 0;
        Result[i].Value := v;
      end;
    end;
  finally
    parts.Free;
  end;
end;
```

- [ ] **Step 4: Run to verify it passes**

Run: `lazbuild -B tests/tytests.lpi && ./tests/tytests.exe --suite=TTyGridLayoutTest --sparse`
Expected: PASS (0 failures).

- [ ] **Step 5: Commit**

```bash
git add source/tyControls.GridPanel.pas tests/test.grid.layout.pas
git commit -m "feat(gridpanel): parse ColumnSizes/RowSizes track-template strings"
```

---

## Task 3: Rewrite `TTyGridPanel` — cell matrix, counts, registration

**Files:**
- Modify (rewrite class): `source/tyControls.GridPanel.pas`
- Test: `tests/test.gridpanel.pas` (rewrite)

- [ ] **Step 1: Write the failing tests** — replace `tests/test.gridpanel.pas` body with:

```pascal
unit test.gridpanel;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, fpcunit, testregistry,
  tyControls.GridPanel, tyControls.GridCell;
type
  TTyGridPanelTest = class(TTestCase)
  published
    procedure TestCountCreatesCells;
    procedure TestCellsAccessorReturnsByColRow;
    procedure TestGrowPreservesInBoundsCells;
    procedure TestShrinkFreesOutOfBoundsCells;
  end;
implementation

procedure TTyGridPanelTest.TestCountCreatesCells;
var g: TTyGridPanel;
begin
  g := TTyGridPanel.Create(nil);
  try
    g.ColumnCount := 3;
    g.RowCount := 2;
    AssertEquals('3x2 -> 6 cells', 6, g.CellCount);
  finally
    g.Free;
  end;
end;

procedure TTyGridPanelTest.TestCellsAccessorReturnsByColRow;
var g: TTyGridPanel; c: TTyGridCell;
begin
  g := TTyGridPanel.Create(nil);
  try
    g.ColumnCount := 3; g.RowCount := 2;
    c := g.Cells[2, 1];
    AssertTrue('cell exists', c <> nil);
    AssertEquals('col', 2, c.Col);
    AssertEquals('row', 1, c.Row);
  finally
    g.Free;
  end;
end;

procedure TTyGridPanelTest.TestGrowPreservesInBoundsCells;
var g: TTyGridPanel; keep: TTyGridCell; marker: TControl;
begin
  g := TTyGridPanel.Create(nil);
  try
    g.ColumnCount := 2; g.RowCount := 2;
    keep := g.Cells[1, 1];
    marker := TControl.Create(g);
    marker.Parent := keep;          // content dropped into cell (1,1)
    g.ColumnCount := 3;             // grow: (1,1) still in bounds
    AssertSame('same cell object kept', keep, g.Cells[1, 1]);
    AssertSame('content preserved', keep, marker.Parent);
  finally
    g.Free;
  end;
end;

procedure TTyGridPanelTest.TestShrinkFreesOutOfBoundsCells;
var g: TTyGridPanel;
begin
  g := TTyGridPanel.Create(nil);
  try
    g.ColumnCount := 3; g.RowCount := 2;   // 6 cells
    g.ColumnCount := 2;                     // -> 4 cells; col 2 dropped
    AssertEquals('shrunk to 4', 4, g.CellCount);
    AssertTrue('no cell at old col 2', g.Cells[2, 0] = nil);
  finally
    g.Free;
  end;
end;

initialization
  RegisterTest(TTyGridPanelTest);
end.
```

- [ ] **Step 2: Run to verify it fails**

Run: `lazbuild -B tests/tytests.lpi`
Expected: FAIL — old `TTyGridPanel` has no cell matrix (compile errors / assertion failures).

- [ ] **Step 3: Rewrite the `TTyGridPanel` class**

Replace the `TTyGridPanel` class declaration in `source/tyControls.GridPanel.pas` (keep the `Ty*` solver functions + `TyParseGridTracks` untouched; the record/enum types stay). New private/protected/public/published:

```pascal
  TTyGridCellArray = array of TObject;   // TTyGridCell; TObject avoids a cyclic uses

  TTyGridPanel = class(TTyPanel)
  private
    FCells: array of TObject;        // flat, one TTyGridCell per (col,row); index = row*Cols+col
    FColumnCount: Integer;
    FRowCount: Integer;
    FColumnSizes: string;
    FRowSizes: string;
    FSpacing: Integer;
    FInLayout: Boolean;
    FDestroying: Boolean;
    procedure SetColumnCount(AValue: Integer);
    procedure SetRowCount(AValue: Integer);
    procedure SetColumnSizes(const AValue: string);
    procedure SetRowSizes(const AValue: string);
    procedure SetSpacing(AValue: Integer);
    function  GetCell(ACol, ARow: Integer): TObject;   // returns TTyGridCell or nil
    function  CellIndex(ACol, ARow: Integer): Integer;
    procedure EnsureCells;           // create/destroy cells to match Count, preserve in-bounds
    procedure Relayout;
  protected
    function  GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Resize; override;
    procedure Loaded; override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Public so TTyGridCell.SetParent (a different unit) can self-register. Idempotent. }
    procedure RegisterCell(ACell: TObject);
    procedure UnregisterCell(ACell: TObject; AFree: Boolean);
    function  CellCount: Integer;
    { Cell at (col,row), or nil. Cast the result to TTyGridCell in cell-aware code. }
    property  Cells[ACol, ARow: Integer]: TObject read GetCell;
  published
    property ColumnCount: Integer read FColumnCount write SetColumnCount default 2;
    property RowCount: Integer read FRowCount write SetRowCount default 2;
    property ColumnSizes: string read FColumnSizes write SetColumnSizes;
    property RowSizes: string read FRowSizes write SetRowSizes;
    property Spacing: Integer read FSpacing write SetSpacing default 4;
  end;
```

> Design note on the `TObject`/`TTyGridCell` typing: `tyControls.GridCell` uses `tyControls.GridPanel` in its *implementation*; to avoid a cyclic *interface* dependency, the grid stores cells as `TObject` in its interface and casts to `TTyGridCell` inside the implementation (which `uses tyControls.GridCell`). This mirrors how the two units already break their cycle (GridCell→GridPanel impl-only).

Implementation — replace the old method bodies. Full new bodies:

```pascal
constructor TTyGridPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColumnCount := 2;
  FRowCount := 2;
  FSpacing := 4;
  Width := 200;
  Height := 150;
  if not (csLoading in ComponentState) then
    EnsureCells;                    // designer/code path builds the 2x2 default
end;

destructor TTyGridPanel.Destroy;
begin
  FDestroying := True;
  inherited Destroy;                // cells owned by the form (or Self) freed normally
end;

function TTyGridPanel.GetStyleTypeKey: string;
begin
  Result := 'TyPanel';              // transparent layout host; reuse the panel key
end;

function TTyGridPanel.CellIndex(ACol, ARow: Integer): Integer;
var i: Integer; c: TTyGridCell;
begin
  Result := -1;
  for i := 0 to High(FCells) do
  begin
    c := TTyGridCell(FCells[i]);
    if (c <> nil) and (c.Col = ACol) and (c.Row = ARow) then Exit(i);
  end;
end;

function TTyGridPanel.GetCell(ACol, ARow: Integer): TObject;
var idx: Integer;
begin
  idx := CellIndex(ACol, ARow);
  if idx >= 0 then Result := FCells[idx] else Result := nil;
end;

function TTyGridPanel.CellCount: Integer;
begin
  Result := Length(FCells);
end;

procedure TTyGridPanel.RegisterCell(ACell: TObject);
var i: Integer;
begin
  for i := 0 to High(FCells) do
    if FCells[i] = ACell then Exit;         // idempotent
  SetLength(FCells, Length(FCells) + 1);
  FCells[High(FCells)] := ACell;
  TTyGridCell(ACell).Controller := Self.Controller;
  if not (csLoading in ComponentState) then Relayout;
end;

procedure TTyGridPanel.UnregisterCell(ACell: TObject; AFree: Boolean);
var idx, j: Integer;
begin
  idx := -1;
  for j := 0 to High(FCells) do
    if FCells[j] = ACell then begin idx := j; Break; end;
  if idx < 0 then Exit;
  for j := idx to High(FCells) - 1 do FCells[j] := FCells[j + 1];
  SetLength(FCells, Length(FCells) - 1);
  if AFree and (ACell <> nil) then TTyGridCell(ACell).Free;
  if not (csDestroying in ComponentState) then Relayout;
end;

procedure TTyGridPanel.EnsureCells;
var
  col, row: Integer;
  cell: TTyGridCell;
  cellOwner: TComponent;
  i: Integer;
  wanted: TTyGridCell;
begin
  if csLoading in ComponentState then Exit;   // Loaded reconciles instead
  if Owner <> nil then cellOwner := Owner else cellOwner := Self;
  // 1) free cells now out of bounds (col>=ColumnCount or row>=RowCount)
  i := 0;
  while i <= High(FCells) do
  begin
    cell := TTyGridCell(FCells[i]);
    if (cell = nil) or (cell.Col >= FColumnCount) or (cell.Row >= FRowCount)
       or (cell.Col < 0) or (cell.Row < 0) then
      UnregisterCell(cell, True)               // shrinks FCells; do not Inc(i)
    else
      Inc(i);
  end;
  // 2) create any missing (col,row) in bounds
  for row := 0 to FRowCount - 1 do
    for col := 0 to FColumnCount - 1 do
    begin
      wanted := TTyGridCell(GetCell(col, row));
      if wanted = nil then
      begin
        cell := TTyGridCell.Create(cellOwner);
        cell.Col := col;
        cell.Row := row;
        cell.Parent := Self;                   // SetParent -> RegisterCell
      end;
    end;
  Relayout;
end;

procedure TTyGridPanel.SetColumnCount(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  if FColumnCount = AValue then Exit;
  FColumnCount := AValue;
  EnsureCells;
end;

procedure TTyGridPanel.SetRowCount(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  if FRowCount = AValue then Exit;
  FRowCount := AValue;
  EnsureCells;
end;

procedure TTyGridPanel.SetColumnSizes(const AValue: string);
begin
  if FColumnSizes = AValue then Exit;
  FColumnSizes := AValue;
  Relayout;
end;

procedure TTyGridPanel.SetRowSizes(const AValue: string);
begin
  if FRowSizes = AValue then Exit;
  FRowSizes := AValue;
  Relayout;
end;

procedure TTyGridPanel.SetSpacing(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FSpacing = AValue then Exit;
  FSpacing := AValue;
  Relayout;
end;

procedure TTyGridPanel.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if FDestroying then Exit;
  if (Operation = opRemove) and (AComponent is TTyGridCell) then
    UnregisterCell(AComponent, False);        // LCL already freeing it
end;

procedure TTyGridPanel.Resize;
begin
  inherited Resize;
  Relayout;
end;

procedure TTyGridPanel.Loaded;
begin
  inherited Loaded;
  { Cells self-registered via SetParent during streaming; FCells is populated.
    Reconcile against ColumnCount/RowCount (a hand-edited .lfm may disagree). }
  EnsureCells;
end;
```

(Delete the old `SetCell`/`RemoveCell`/`GetCell(AControl...)`/`CellCount(old)`/`IndexOfCell`/`DropCell`/`SetColumnStyle`/`SetRowStyle`/`ColumnStyle`/`RowStyle` methods and their private fields `FCellCtl`/`FCellCol`/`FCellRow`/`FCellColSpan`/`FCellRowSpan`/`FCellCount`/`FColumns`/`FRows`.)

Add `tyControls.GridCell` and `tyControls.Controller` to the implementation `uses`.

- [ ] **Step 4: Add `Relayout` and `Paint` (design-time grid lines)** — see Task 4 for `Relayout`; add a minimal `Relayout` stub now so it compiles:

```pascal
procedure TTyGridPanel.Relayout;
begin
  // real body in Task 4
end;

procedure TTyGridPanel.Paint;
begin
  inherited Paint;
  // design-time grid lines added in Task 5
end;
```

- [ ] **Step 5: Run to verify Task 3 tests pass**

Run: `lazbuild -B tests/tytests.lpi && ./tests/tytests.exe --suite=TTyGridPanelTest --sparse`
Expected: PASS. Also run `--suite=TTyGridCellTest` — now compiles and passes (Task 1 unblocked).

- [ ] **Step 6: Commit (Tasks 1 + 3 together — the mutually-referencing pair)**

```bash
git add source/tyControls.GridPanel.pas source/tyControls.GridCell.pas tests/test.gridpanel.pas tests/test.gridcell.pas
git commit -m "feat(gridpanel): cell-matrix model with form-owned TTyGridCell containers"
```

---

## Task 4: Layout — solve tracks, place cells

**Files:**
- Modify: `source/tyControls.GridPanel.pas` (real `Relayout`)
- Test: `tests/test.gridpanel.pas` (append)

- [ ] **Step 1: Write the failing tests** — append test methods:

```pascal
procedure TTyGridPanelTest.TestDefaultEqualDistribution;
var g: TTyGridPanel; a, b: TTyGridCell;
begin
  g := TTyGridPanel.Create(nil);
  try
    g.Spacing := 0;
    g.SetBounds(0, 0, 300, 100);
    g.ColumnCount := 3; g.RowCount := 1;
    g.HandleNeeded;
    a := TTyGridCell(g.Cells[0, 0]);
    b := TTyGridCell(g.Cells[1, 0]);
    AssertEquals('equal col width', 100, a.Width);
    AssertEquals('col1 x', 100, b.Left);
  finally
    g.Free;
  end;
end;

procedure TTyGridPanelTest.TestColumnSizesRespected;
var g: TTyGridPanel; a, b: TTyGridCell;
begin
  g := TTyGridPanel.Create(nil);
  try
    g.Spacing := 0;
    g.SetBounds(0, 0, 300, 100);
    g.ColumnCount := 2; g.RowCount := 1;
    g.ColumnSizes := '2*, *';        // 200 / 100
    g.HandleNeeded;
    a := TTyGridCell(g.Cells[0, 0]);
    b := TTyGridCell(g.Cells[1, 0]);
    AssertEquals('wide col', 200, a.Width);
    AssertEquals('narrow col', 100, b.Width);
  finally
    g.Free;
  end;
end;
```

(Add both to the published section.)

- [ ] **Step 2: Run to verify it fails**

Run: `lazbuild -B tests/tytests.lpi && ./tests/tytests.exe --suite=TTyGridPanelTest --sparse`
Expected: FAIL — cells are at 0-size (stub `Relayout`).

- [ ] **Step 3: Implement `Relayout`**

```pascal
procedure TTyGridPanel.Relayout;
var
  cr: TRect;
  cols, rows: TTyGridTracks;
  colW, rowH, colX, rowY: TTyGridIntArray;
  i: Integer;
  cell: TTyGridCell;
  cellR: TRect;
begin
  if csDestroying in ComponentState then Exit;
  if csLoading in ComponentState then Exit;
  if FInLayout then Exit;
  FInLayout := True;
  try
    cr := ClientRect;
    cols := TyParseGridTracks(FColumnSizes, FColumnCount);
    rows := TyParseGridTracks(FRowSizes, FRowCount);
    colW := TyGridTrackSizes(cr.Right - cr.Left, FSpacing, cols);
    rowH := TyGridTrackSizes(cr.Bottom - cr.Top, FSpacing, rows);
    colX := TyGridTrackOrigins(colW, FSpacing);
    rowY := TyGridTrackOrigins(rowH, FSpacing);
    for i := 0 to High(FCells) do
    begin
      cell := TTyGridCell(FCells[i]);
      if cell = nil then Continue;
      if (cell.Col < 0) or (cell.Col >= Length(colW)) then Continue;
      if (cell.Row < 0) or (cell.Row >= Length(rowH)) then Continue;
      cellR := TyGridCellRect(colX, colW, rowY, rowH, cell.Col, cell.Row, 1, 1);
      OffsetRect(cellR, cr.Left, cr.Top);
      cell.SetBounds(cellR.Left, cellR.Top,
        cellR.Right - cellR.Left, cellR.Bottom - cellR.Top);
    end;
  finally
    FInLayout := False;
  end;
  Invalidate;
end;
```

> Note: cells fill their whole track rect; the **grid's** `Spacing` already produced the gutter (subtracted by `TyGridTrackSizes`). The per-cell inset is the cell's own `Padding`, applied by `TTyGridCell.AdjustClientRect` to its children — NOT here. (This is the two-level model from the spec.)

- [ ] **Step 4: Run to verify it passes**

Run: `lazbuild -B tests/tytests.lpi && ./tests/tytests.exe --suite=TTyGridPanelTest --sparse`
Expected: PASS (all TTyGridPanelTest).

- [ ] **Step 5: Commit**

```bash
git add source/tyControls.GridPanel.pas tests/test.gridpanel.pas
git commit -m "feat(gridpanel): solve tracks and place cells on relayout"
```

---

## Task 5: Design-time grid lines + registration + package membership

**Files:**
- Modify: `source/tyControls.GridPanel.pas` (`Paint` grid lines)
- Modify: `tycontrols.pas:57` (runtime package unit list)
- Modify: `designtime/tyControls.Design.pas` (register `TTyGridCell` via `RegisterNoIcon`)

- [ ] **Step 1: Paint design-time grid lines**

Replace the `Paint` stub:

```pascal
procedure TTyGridPanel.Paint;
var
  cr: TRect;
  cols, rows: TTyGridTracks;
  colW, rowH, colX, rowY: TTyGridIntArray;
  i, x, y: Integer;
begin
  inherited Paint;
  if not (csDesigning in ComponentState) then Exit;   // guides are design-time only
  cr := ClientRect;
  cols := TyParseGridTracks(FColumnSizes, FColumnCount);
  rows := TyParseGridTracks(FRowSizes, FRowCount);
  colW := TyGridTrackSizes(cr.Right - cr.Left, FSpacing, cols);
  rowH := TyGridTrackSizes(cr.Bottom - cr.Top, FSpacing, rows);
  colX := TyGridTrackOrigins(colW, FSpacing);
  rowY := TyGridTrackOrigins(rowH, FSpacing);
  Canvas.Pen.Style := psDot;
  Canvas.Pen.Color := clGray;
  for i := 0 to High(colX) do
  begin
    x := cr.Left + colX[i];
    Canvas.Line(x, cr.Top, x, cr.Bottom);
    Canvas.Line(x + colW[i], cr.Top, x + colW[i], cr.Bottom);
  end;
  for i := 0 to High(rowY) do
  begin
    y := cr.Top + rowY[i];
    Canvas.Line(cr.Left, y, cr.Right, y);
    Canvas.Line(cr.Left, y + rowH[i], cr.Right, y + rowH[i]);
  end;
end;
```

(Add `Graphics` to the interface `uses` if not present — it is, via existing imports; verify.)

- [ ] **Step 2: Add the cell unit to the runtime package**

In `tycontrols.pas`, line ~57, change `tyControls.GridPanel,` to `tyControls.GridPanel, tyControls.GridCell,`.
Also add `tyControls.GridCell` to the `<Units>` list in `tycontrols.lpk` (mirror how `tyControls.GridPanel` appears — copy its `<Item><Filename>/<UnitName>` block).

- [ ] **Step 3: Register `TTyGridCell` for the designer**

In `designtime/tyControls.Design.pas`: add `tyControls.GridCell` to `uses`, and in `Register` (after the `RegisterComponents('TyControls Containers', [...])` call) add:

```pascal
  // Cells are created/owned by the grid, not dragged from the palette — register the
  // class (for streaming + OI selection) without a palette button.
  RegisterNoIcon([TTyGridCell]);
```

- [ ] **Step 4: Build the whole library + design package + tests**

Run: `lazbuild -B tycontrols.lpk && lazbuild -B tycontrols_dt.lpk && lazbuild -B tests/tytests.lpi`
Expected: all compile, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add source/tyControls.GridPanel.pas tycontrols.pas tycontrols.lpk designtime/tyControls.Design.pas
git commit -m "feat(gridpanel): design-time grid guides + register cell class + package"
```

---

## Task 6: Published-surface guard + streaming round-trip

**Files:**
- Test: `tests/test.grid.streaming.pas` (append)

- [ ] **Step 1: Write the failing tests** — append to `TTyGridStreamingTest`:

```pascal
procedure TTyGridStreamingTest.TestGridPanelPublishesDesignerProps;
const cMust: array[0..7] of string =
  ('ColumnCount', 'RowCount', 'ColumnSizes', 'RowSizes', 'Spacing',
   'Align', 'Anchors', 'Visible');
var i: Integer;
begin
  for i := 0 to High(cMust) do
    AssertTrue('TTyGridPanel must publish ' + cMust[i],
      GetPropInfo(TTyGridPanel, cMust[i]) <> nil);
end;

procedure TTyGridStreamingTest.TestCellsSurviveStreamRoundTrip;
var
  host, host2: TComponent;
  g, g2: TTyGridPanel;
  marker: TControl;
  ms: TMemoryStream;
  i: Integer;
  c2: TTyGridPanel;
begin
  host := TComponent.Create(nil);
  ms := TMemoryStream.Create;
  try
    g := TTyGridPanel.Create(host);
    g.Name := 'Grid1';
    g.ColumnCount := 2; g.RowCount := 2;   // 4 cells owned by host, parented to g
    // name the cells so they stream (the designer would; we do it explicitly)
    for i := 0 to g.CellCount - 1 do
      TTyGridCell(g.CellAt(i)).Name := 'Cell' + IntToStr(i);
    marker := TTyGridCell(g.Cells[1, 1]);   // sanity: cell present
    AssertTrue('cell present pre-stream', marker <> nil);

    WriteComponentAsTextToStream(ms, host);
    ms.Position := 0;
    host2 := TComponent.Create(nil);
    try
      ReadComponentFromTextStream(ms, TComponent(host2), nil, host2);
      c2 := host2.FindComponent('Grid1') as TTyGridPanel;
      AssertTrue('grid reloaded', c2 <> nil);
      AssertEquals('4 cells after reload', 4, c2.CellCount);
      AssertTrue('cell (1,1) reseated', c2.Cells[1, 1] <> nil);
    finally
      host2.Free;
    end;
  finally
    ms.Free;
    host.Free;
  end;
end;
```

> The test uses `g.CellAt(i)` (added in Step 3 below) to iterate registered cells and name them, and `WriteComponentAsTextToStream`/`ReadComponentFromTextStream` (unit `LResources`) for the round-trip.

Add `LResources` and `tyControls.GridCell` to this unit's `uses`.

- [ ] **Step 2: Run to verify it fails**

Run: `lazbuild -B tests/tytests.lpi`
Expected: FAIL — `CellAt` not defined / round-trip assertions.

- [ ] **Step 3: Add the `CellAt` accessor** to `TTyGridPanel` public section:

```pascal
    { Test/iteration accessor: the i-th registered cell (registration order). }
    function CellAt(AIndex: Integer): TObject;
```

```pascal
function TTyGridPanel.CellAt(AIndex: Integer): TObject;
begin
  if (AIndex >= 0) and (AIndex <= High(FCells)) then Result := FCells[AIndex]
  else Result := nil;
end;
```

- [ ] **Step 4: Run to verify it passes**

Run: `lazbuild -B tests/tytests.lpi && ./tests/tytests.exe --suite=TTyGridStreamingTest --sparse`
Expected: PASS. If the reload double-creates cells (8 instead of 4), the `Loaded`→`EnsureCells` reconcile is wrong — fix `EnsureCells` to no-op when streamed cells already cover every (col,row).

- [ ] **Step 5: Full test run — classic must stay green**

Run: `./tests/tytests.exe --all --sparse --skiptiming > /tmp/gp.xml 2>&1` then check `NumberOfFailures` = 0 and `NumberOfErrors` = 12 (pre-existing).

- [ ] **Step 6: Commit**

```bash
git add source/tyControls.GridPanel.pas tests/test.grid.streaming.pas
git commit -m "test(gridpanel): published-surface guard + stream round-trip"
```

---

## Task 7: Update the `containers` example to the new model

**Files:**
- Modify: `examples/containers/umain.pas` (remove SetCell/SetColumnStyle usage)
- Modify: `examples/containers/umain.lfm` (cells + child controls in .lfm)

- [ ] **Step 1: Rewrite the `.lfm` `GridForm`** — replace the `object GridForm: TTyGridPanel` block (currently ColumnCount=2 RowCount=3, no cells) so the cells and their child controls are nested. Pattern (2×3 form grid: label column narrow, field column star):

```
object GridForm: TTyGridPanel
  Left = ...   Top = ...   Width = ...   Height = ...
  ColumnCount = 2
  RowCount = 3
  ColumnSizes = '90, *'
  Spacing = 6
  object GridForm_c0: TTyGridCell
    Col = 0  Row = 0  Padding = 2
    object LblUser: TTyLabel
      Align = alClient
      Caption = '用户名'
    end
  end
  object GridForm_c1: TTyGridCell
    Col = 1  Row = 0  Padding = 2
    object EditUser: TTyEdit
      Align = alClient
    end
  end
  { ... c2/c3 for 邮箱 row 1, c4/c5 for 电话 row 2 ... }
end
```

Write all 6 cells (Col/Row 0..1 × 0..2) with the existing LblUser/EditUser/LblMail/EditMail/LblPhone/EditPhone controls moved inside the matching cells, each `Align = alClient`.

- [ ] **Step 2: Remove the code placement** — in `examples/containers/umain.pas`, delete lines placing the grid (the `GridForm.SetColumnStyle(...)` and `GridForm.SetCell(...)` block, ~187-191). Update the unit comment at line ~5 that says grid cells "can't be expressed as .lfm properties" — they now can.

- [ ] **Step 3: Build the example**

Run: `lazbuild -B examples/containers/containers_example.lpi` (find exact lpi name with `ls examples/containers/*.lpi`)
Expected: compiles, 0 errors, 0 "Unknown property" at load.

- [ ] **Step 4: Render-probe the example** (headless) — reuse the repo probe idiom (`MainForm.GetFormImage` → PNG via `TPortableNetworkGraphic`), capture the containers form, and visually confirm the 2×3 form grid lays out (labels left, fields right, equal rows). Save to scratchpad; inspect.

- [ ] **Step 5: Commit**

```bash
git add examples/containers/umain.pas examples/containers/umain.lfm
git commit -m "example(containers): grid form via designer cells in .lfm"
```

---

## Task 8: Migrate the antdesign dashboard to two grids

**Files:**
- Modify: `examples/antdesign/umain.lfm` (dashboard page → GridKPI + GridMain)
- Modify: `examples/antdesign/umain.pas` (drop any dashboard-specific absolute-position code if present; add field decls for the two grids + cells)

- [ ] **Step 1: Restructure `PgDashboard`** in `examples/antdesign/umain.lfm`:
  - Add `GridKPI: TTyGridPanel` (Align=alTop or explicit bounds, Height ~228): `ColumnCount=4 RowCount=1 Spacing=12`; 4 cells; move `CardVisits`/`CardOrders`/`CardCpu`/`CardHealth` each into a cell with `Align=alClient`.
  - Add `GridMain: TTyGridPanel` (below GridKPI, Height ~404): `ColumnCount=2 RowCount=1 ColumnSizes='2*, *' Spacing=12`; 2 cells; move `CardChart` into cell (0,0), `CardStatus` into cell (1,0), each `Align=alClient`.
  - Cards keep their `Title`/content; drop their explicit `Left/Top/Width/Height/Anchors` (the cell drives bounds now).

- [ ] **Step 2: Add field declarations** — in `examples/antdesign/umain.pas` form class, add `GridKPI: TTyGridPanel; GridMain: TTyGridPanel;` and the 6 cell fields (e.g., `KpiCell0..3`, `MainCell0..1`) mirroring how other container children are declared. Add `tyControls.GridPanel, tyControls.GridCell` to `uses`.

- [ ] **Step 3: Rebuild the real example with `-B`**

Run: `lazbuild -B examples/antdesign/antdesign_pro.lpi`
Expected: compiles, 0 "Unknown property".

- [ ] **Step 4: Render-probe the dashboard** — capture page 0 (dashboard) via the repo probe; confirm: 4 equal KPI cards on top, chart(wide)+status(narrow) below, cards keep `--pad-card`, no overlap. Resize the probe form to a wider width and re-render; confirm cards **grow proportionally** (responsiveness the whole migration is for).

- [ ] **Step 5: Commit**

```bash
git add examples/antdesign/umain.lfm examples/antdesign/umain.pas
git commit -m "example(antdesign): dashboard via two responsive grids"
```

---

## Task 9: Final verification sweep

**Files:** none (verification only)

- [ ] **Step 1: Full library + package + tests**

Run: `lazbuild -B tycontrols.lpk && lazbuild -B tycontrols_dt.lpk && lazbuild -B tests/tytests.lpi && ./tests/tytests.exe --all --sparse --skiptiming > /tmp/final.xml 2>&1`
Expected: `NumberOfFailures=0`, `NumberOfErrors=12` (pre-existing headless-only), `NumberOfRunTests` = prior + the new grid tests.

- [ ] **Step 2: Rebuild both real example exes with `-B`**

Run: `lazbuild -B examples/containers/*.lpi && lazbuild -B examples/antdesign/antdesign_pro.lpi`
Expected: 0 errors.

- [ ] **Step 3: Palette-icon drift guard** — the palette icon test (`tests/test.paletteicons.pas`) enforces `RegisterComponents ⇔ $classes`. Since `TTyGridCell` uses `RegisterNoIcon` (no palette button), confirm the test still passes (it should — RegisterNoIcon classes are excluded from the icon list). If it fails, the drift guard needs `TTyGridCell` on an exclusion list — add it there, not to `$classes`.

- [ ] **Step 4: i18n / README pre-merge check** — per the repo's pre-merge checklist, scan whether the new control needs a resourcestring entry or a README mention. TTyGridPanel already existed; only note the API change if the README documents `SetCell`.

- [ ] **Step 5: Hand off for IDE verification** — report to the user the headless-verified results (tests + render probes) AND the explicit list to check in a running Lazarus IDE: (a) drop a control into a grid cell and confirm it's constrained, (b) set ColumnCount/RowCount and see cells appear, (c) design-time grid lines, (d) per-cell Padding in the OI. Do NOT claim these work — they're user-verified.

---

## Self-review notes (addressed)

- **Spec coverage:** cell container (T1), per-cell Padding (T1), track sizes/strings (T2), counts→cells + lifecycle/preserve/shrink (T3), layout/equal-default/Spacing gutter (T4), design-time lines + registration + package (T5), streaming round-trip + published surface (T6), containers example (T7), dashboard migration (T8), verification + IDE handoff (T9). All spec sections mapped.
- **Non-goals honored:** no spanning (cells are 1×1 always; `TyGridCellRect` called with span 1,1).
- **Type consistency:** `TTyGridCell` (Col/Row/Padding), `TTyGridPanel` (ColumnCount/RowCount/ColumnSizes/RowSizes/Spacing/Cells[]/CellCount/CellAt/RegisterCell/UnregisterCell), solver fns unchanged. Cells stored as `TObject` in interface, cast to `TTyGridCell` in impl (cycle-break, consistent across all tasks).
- **Known risk to watch during execution:** the `Loaded`→`EnsureCells` reconcile must NOT double-create cells that streamed in (Task 6 Step 4 checks this); and programmatic cell `Name` assignment for streaming is the one behavior most likely to differ in the real IDE (flagged for user verification in T9).
