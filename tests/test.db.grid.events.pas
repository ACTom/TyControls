unit test.db.grid.events;
{$mode objfpc}{$H+}

{ The data-aware grid, part four (issue #34 phase 2, plan Task 5): the indicator, the
  multiselect, the title click and LCL's events -- and three things the earlier parts left.

  * the indicator: rendered on a sentinel ground, the current record's mark follows the
    dataset -- a triangle browsing (more ink on the side it points away from), an I-beam
    editing (as much ink either side), the same bar in the insert colour inserting -- and a
    selected row carries a dot; right-to-left, the band moves to the right and the triangle
    turns round;
  * dgMultiselect: a plain click selects the record alone, Ctrl+click toggles it, Shift+Down /
    Shift+Up extend and shrink the run one record at a time, dgPersistentMultiSelect keeps the
    selection; SelectedRows deletes, refreshes, answers IndexOf; a selected row is drawn as a
    selected cell; closing the dataset empties the list;
  * a title click is OnTitleClick and never a sort; a divider drag is not a title click but
    OnColumnSized; a column drag is OnColumnMoved;
  * every D9 event at its moment, the dataset on the event's record while it runs;
  * Tab past the window's last field goes on to the next record (appending at the end),
    Shift+Tab back; a check box the dataset will not edit fires no OnCheckBoxChange; one wheel
    notch fires OnMouseWheel once, with and without a dataset (the base grid's fix will make
    a second fire visible here).

  The records are read off the dataset, never through the grid. }

interface

uses
  Classes, SysUtils, Types, Math, Controls, Forms, Graphics, StdCtrls, LCLType, DB, BufDataset,
  Grids, DBGrids, fpcunit, testregistry, BGRABitmap, BGRABitmapTypes,
  dbfixtures, tyControls.Types, tyControls.Painter, tyControls.Grid, tyControls.DB.Grid,
  test.db.grid.nav;

type
  { A table whose BookmarkValid can be told one record is gone (TBufDataset's never says
    so). }
  TStaleDataSet = class(TBufDataset)
  public
    Stale: TBookmark;
    function BookmarkValid(ABookmark: TBookmark): Boolean; override;
  end;

  TDBGridEventProbe = class(TDBGridProbe)
  public
    function Snapshot: TBGRABitmap;
    procedure IndicatorSlot(out ALeft, ARight: Integer);
    function IndicatorInk: TBGRAPixel;
    function InsertInk: TBGRAPixel;
    function SelectedBackground: TBGRAPixel;
    procedure ClickCellWith(ACol, ARow: Integer; AShift: TShiftState);
    function TitlePoint(ACol: Integer): TPoint;
    function DividerPoint(ACol: Integer): TPoint;
    procedure Press(const APt: TPoint);
    procedure DragTo(const APt: TPoint);
    procedure Release(const APt: TPoint);
    procedure Hover(ACol, ARow: Integer);
  end;

  { What a row's indicator cell holds, against a row that shows nothing. }
  TInk = record
    Count, Left, Right, Accent: Integer;
  end;

  TDBGridEventsTest = class(TTestCase)
  private
    FForm: TForm;
    FRows: TDbRowsFixture;
    FGrid: TDBGridEventProbe;
    FLog: TStringList;
    FCount: Integer;
    FEditor: TEdit;
    function DS: TDataSet;
    function ID: Integer;
    function ColOf(const AFieldName: string): Integer;
    function SelectedIDs: string;
    { The log, comma separated, as written. }
    function Logged: string;
    function RowInk(B: TBGRABitmap; ARow, AEmptyRow: Integer): TInk;
    procedure Multiselect;
    { event handlers }
    procedure LogCellClick(Column: TTyDBGridColumn);
    procedure LogTitleClick(Column: TTyDBGridColumn);
    procedure LogColEnter(Sender: TObject);
    procedure LogColExit(Sender: TObject);
    procedure LogColumnMoved(Sender: TObject; FromIndex, ToIndex: Integer);
    procedure LogColumnSized(Sender: TObject);
    procedure LogDrawCell(Sender: TObject; const Rect: TRect; DataCol: Integer;
      Column: TTyDBGridColumn; State: TGridDrawState; APainter: TTyPainter;
      var AHandled: Boolean);
    procedure TakeNameCell(Sender: TObject; const Rect: TRect; DataCol: Integer;
      Column: TTyDBGridColumn; State: TGridDrawState; APainter: TTyPainter;
      var AHandled: Boolean);
    procedure LogDrawTitle(Sender: TObject; const Rect: TRect; DataCol: Integer;
      Column: TTyDBGridColumn; State: TGridDrawState; APainter: TTyPainter);
    procedure PaintRowThreeRed(Sender: TObject; DataCol: Integer; Column: TTyDBGridColumn;
      AState: TGridDrawState; var AStyle: TTyGridCellAppearance);
    procedure HintTheName(Sender: TObject; Column: TTyDBGridColumn; var AText: string);
    procedure PickTheEdit(Sender: TObject; Column: TTyDBGridColumn; var Editor: TWinControl);
    procedure GrayEveryBox(Sender: TObject; Column: TTyDBGridColumn;
      var AState: TCheckBoxState);
    procedure CountNotify(Sender: TObject);
    procedure CountCheck(Sender: TObject; ACol, ARow: Integer; AChecked: Boolean);
    procedure CountWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint; var Handled: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { the indicator }
    procedure TestIndicatorFollowsTheDataSetState;
    procedure TestIndicatorMirrorsRightToLeft;
    { multiselect }
    procedure TestPlainClickSelectsTheRecordAlone;
    procedure TestCtrlClickToggles;
    procedure TestShiftArrowsExtendAndShrinkTheRun;
    procedure TestPersistentMultiSelectKeepsTheSelection;
    procedure TestSelectedRowsDeleteAndIndexOf;
    procedure TestSelectedRowsRefreshDropsStaleBookmarks;
    procedure TestSelectedRowsAreDrawnSelectedWithADot;
    procedure TestClosingEmptiesTheSelection;
    { titles and headers }
    procedure TestTitleClickFiresAndDoesNotSort;
    procedure TestDividerDragIsSizedNotATitleClick;
    procedure TestColumnDragFiresColumnMoved;
    { D9 }
    procedure TestCellClickOnTheClickedRecord;
    procedure TestColExitThenColEnter;
    procedure TestDrawColumnCellSeesEachRowsRecord;
    procedure TestDrawColumnCellCanTakeTheText;
    procedure TestDrawColumnTitleForEachTitle;
    procedure TestPrepareCanvasStylesTheCell;
    procedure TestGetCellHintOnTheHoveredRecord;
    procedure TestSelectEditorPutsTheControlOnTheCell;
    procedure TestEditButtonClick;
    procedure TestUserCheckboxState;
    { the three left over from parts two and three }
    procedure TestTabWrapsToTheNextRecord;
    procedure TestTabOnTheLastRecordAppends;
    procedure TestShiftTabWrapsBack;
    procedure TestRefusedEditFiresNoCheckBoxChange;
    procedure TestOneNotchFiresTheEventOnce;
  end;

implementation

uses
  tyControls.StyleModel, test.db.edits;

const
  CInk = 90;   // the colour distance from the empty row's pixel that counts as ink

function Dist(const A, B: TBGRAPixel): Integer;
begin
  Result := Abs(A.red - B.red) + Abs(A.green - B.green) + Abs(A.blue - B.blue);
end;

{ How closely the way APixel departs from AGround points the way AInk does (the cosine of the
  two colour differences): a mark anti-aliased, or in a translucent ink, onto the ground lies
  on the line from the ground to its ink, whatever its coverage. }
function Toward(const APixel, AGround, AInk: TBGRAPixel): Double;
var
  pr, pg, pb, ir, ig, ib, n: Double;
begin
  pr := APixel.red - AGround.red;
  pg := APixel.green - AGround.green;
  pb := APixel.blue - AGround.blue;
  ir := AInk.red - AGround.red;
  ig := AInk.green - AGround.green;
  ib := AInk.blue - AGround.blue;
  n := Sqrt(pr * pr + pg * pg + pb * pb) * Sqrt(ir * ir + ig * ig + ib * ib);
  if n = 0 then Exit(0);
  Result := (pr * ir + pg * ig + pb * ib) / n;
end;

{ ==================================================================== TStaleDataSet ===== }

function TStaleDataSet.BookmarkValid(ABookmark: TBookmark): Boolean;
begin
  Result := inherited BookmarkValid(ABookmark);
  if Result and (Stale <> nil) and (CompareBookmarks(ABookmark, Stale) = 0) then
    Result := False;
end;

{ ================================================================ TDBGridEventProbe ===== }

function TDBGridEventProbe.Snapshot: TBGRABitmap;
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(Width, Height);
    bmp.Canvas.Brush.Color := clFuchsia;   // the sentinel: no theme paints it
    bmp.Canvas.FillRect(0, 0, Width, Height);
    RenderTo(bmp.Canvas, Rect(0, 0, Width, Height), 96);
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
  end;
end;

procedure TDBGridEventProbe.IndicatorSlot(out ALeft, ARight: Integer);
begin
  if not IndicatorBandX(ALeft, ARight) then
  begin
    ALeft := 0;
    ARight := 0;
  end;
end;

function TDBGridEventProbe.IndicatorInk: TBGRAPixel;
var
  s: TTyStyleSet;
begin
  s := ActiveController.Model.ResolveStyle('TyGridIndicator', StyleClass, []);
  Result := TyColorToBGRA(s.TextColor);
end;

function TDBGridEventProbe.InsertInk: TBGRAPixel;
var
  s: TTyStyleSet;
begin
  s := ActiveController.Model.ResolveStyle('TyGridCell', StyleClass, [tysSelected]);
  Result := TyColorToBGRA(s.Background.Color);
end;

function TDBGridEventProbe.SelectedBackground: TBGRAPixel;
begin
  Result := InsertInk;
end;

procedure TDBGridEventProbe.ClickCellWith(ACol, ARow: Integer; AShift: TShiftState);
var
  r: TRect;
begin
  r := CellRect(ACol, ARow);
  ClickAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2, AShift);
end;

function TDBGridEventProbe.TitlePoint(ACol: Integer): TPoint;
var
  r: TRect;
begin
  r := CellRect(ACol, 0);
  Result := Point((r.Left + r.Right) div 2, HeaderHeightPx div 2);
end;

function TDBGridEventProbe.DividerPoint(ACol: Integer): TPoint;
begin
  Result := Point(ColumnResizeEdgeX(ACol), HeaderHeightPx div 2);
end;

procedure TDBGridEventProbe.Press(const APt: TPoint);
begin
  MouseDown(mbLeft, [], APt.X, APt.Y);
end;

procedure TDBGridEventProbe.DragTo(const APt: TPoint);
begin
  MouseMove([ssLeft], APt.X, APt.Y);
end;

procedure TDBGridEventProbe.Release(const APt: TPoint);
begin
  MouseUp(mbLeft, [], APt.X, APt.Y);
end;

procedure TDBGridEventProbe.Hover(ACol, ARow: Integer);
var
  r: TRect;
begin
  r := CellRect(ACol, ARow);
  MouseMove([], (r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
end;

{ ================================================================ TDBGridEventsTest ===== }

procedure TDBGridEventsTest.SetUp;
begin
  NeedDBWidgetSet;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 640, 500);
  FRows := NewRowsFixture(nil);
  FLog := TStringList.Create;
  FGrid := TDBGridEventProbe.Create(FForm);
  FGrid.Font.PixelsPerInch := 96;
  FGrid.Parent := FForm;
  FGrid.SetBounds(0, 0, 600, 260);
  FGrid.DataSource := FRows.Src;
end;

procedure TDBGridEventsTest.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FRows);
  FreeAndNil(FLog);
  FGrid := nil;
  FEditor := nil;
end;

function TDBGridEventsTest.DS: TDataSet;
begin
  Result := FGrid.DataLink.DataSet;
end;

function TDBGridEventsTest.ID: Integer;
begin
  Result := DS.FieldByName('ID').AsInteger;
end;

function TDBGridEventsTest.ColOf(const AFieldName: string): Integer;
var
  i: Integer;
begin
  for i := 0 to FGrid.Columns.Count - 1 do
    if SameText(FGrid.Columns[i].FieldName, AFieldName) then Exit(i);
  Fail('no column for ' + AFieldName);
  Result := -1;
end;

function TDBGridEventsTest.Logged: string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to FLog.Count - 1 do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + FLog[i];
  end;
end;

{ The IDs SelectedRows marks, ascending, comma separated; the table is put back. }
function TDBGridEventsTest.SelectedIDs: string;
var
  bm: TBookmark;
  ids: TStringList;
  i: Integer;
begin
  ids := TStringList.Create;
  bm := FRows.DS.GetBookmark;
  try
    for i := 0 to FGrid.SelectedRows.Count - 1 do
    begin
      FRows.DS.GotoBookmark(FGrid.SelectedRows[i]);
      ids.Add(Format('%.3d', [ID]));
    end;
    FRows.DS.GotoBookmark(bm);
    ids.Sort;
    for i := 0 to ids.Count - 1 do ids[i] := IntToStr(StrToInt(ids[i]));
    Result := ids.CommaText;
  finally
    FRows.DS.FreeBookmark(bm);
    ids.Free;
  end;
end;

{ Row ARow's indicator cell against row AEmptyRow's (which shows no mark): the pixels that
  differ, split into the two halves of the band, and those that lean towards the insert
  colour more than towards the indicator ink. }
function TDBGridEventsTest.RowInk(B: TBGRABitmap; ARow, AEmptyRow: Integer): TInk;
var
  i0, i1, x, y, h: Integer;
  r, e: TRect;
  p, q, ink, acc: TBGRAPixel;
  centre2: Integer;
begin
  Result := Default(TInk);
  FGrid.IndicatorSlot(i0, i1);
  AssertTrue('an indicator band', i1 > i0);
  r := FGrid.CellRect(0, ARow);
  e := FGrid.CellRect(0, AEmptyRow);
  h := Min(r.Bottom - r.Top, e.Bottom - e.Top);
  ink := FGrid.IndicatorInk;
  acc := FGrid.InsertInk;
  centre2 := i0 + i1 - 1;   // twice the band's centre
  for y := 0 to h - 1 do
    for x := i0 to i1 - 1 do
    begin
      p := B.GetPixel(x, r.Top + y);
      q := B.GetPixel(x, e.Top + y);
      if Dist(p, q) <= CInk then Continue;
      Inc(Result.Count);
      if 2 * x < centre2 then Inc(Result.Left)
      else if 2 * x > centre2 then Inc(Result.Right);
      if Toward(p, q, acc) > Toward(p, q, ink) then Inc(Result.Accent);
    end;
end;

procedure TDBGridEventsTest.Multiselect;
begin
  FGrid.Options := FGrid.Options + [dgMultiselect];
end;

{ ------------------------------------------------------------------- handlers ------ }

procedure TDBGridEventsTest.LogCellClick(Column: TTyDBGridColumn);
begin
  FLog.Add(Format('click %s on %d', [Column.FieldName, ID]));
end;

procedure TDBGridEventsTest.LogTitleClick(Column: TTyDBGridColumn);
begin
  FLog.Add('title ' + Column.FieldName);
end;

procedure TDBGridEventsTest.LogColEnter(Sender: TObject);
begin
  FLog.Add('enter ' + IntToStr(FGrid.Col));
end;

procedure TDBGridEventsTest.LogColExit(Sender: TObject);
begin
  FLog.Add('exit ' + IntToStr(FGrid.Col));
end;

procedure TDBGridEventsTest.LogColumnMoved(Sender: TObject; FromIndex, ToIndex: Integer);
begin
  FLog.Add(Format('moved %d %d', [FromIndex, ToIndex]));
end;

procedure TDBGridEventsTest.LogColumnSized(Sender: TObject);
begin
  FLog.Add('sized');
end;

procedure TDBGridEventsTest.LogDrawCell(Sender: TObject; const Rect: TRect;
  DataCol: Integer; Column: TTyDBGridColumn; State: TGridDrawState; APainter: TTyPainter;
  var AHandled: Boolean);
var
  focus: string;
begin
  AssertNotNull('a painter', APainter);
  AssertSame('the column of DataCol', FGrid.Columns[DataCol], Column);
  if gdFocused in State then focus := ' focused' else focus := '';
  if Column.FieldName = 'Name' then
    FLog.Add(Format('%d=%s', [Rect.Top, Column.Field.AsString]))
  else if focus <> '' then
    FLog.Add(Format('%s%s', [Column.FieldName, focus]));
end;

procedure TDBGridEventsTest.TakeNameCell(Sender: TObject; const Rect: TRect;
  DataCol: Integer; Column: TTyDBGridColumn; State: TGridDrawState; APainter: TTyPainter;
  var AHandled: Boolean);
begin
  AHandled := Column.FieldName = 'Name';
end;

procedure TDBGridEventsTest.LogDrawTitle(Sender: TObject; const Rect: TRect;
  DataCol: Integer; Column: TTyDBGridColumn; State: TGridDrawState; APainter: TTyPainter);
begin
  AssertTrue('a title is fixed', gdFixed in State);
  AssertNotNull('a painter', APainter);
  FLog.Add(Format('%s %d %d', [Column.FieldName, Rect.Left, Rect.Top]));
end;

procedure TDBGridEventsTest.PaintRowThreeRed(Sender: TObject; DataCol: Integer;
  Column: TTyDBGridColumn; AState: TGridDrawState; var AStyle: TTyGridCellAppearance);
begin
  if (Column.FieldName = 'Name') and (Column.Field.DataSet.FieldByName('ID').AsInteger = 3) then
  begin
    AStyle.Background := Default(TTyFill);
    AStyle.Background.Kind := tfkSolid;
    AStyle.Background.Color := TyRGB(255, 0, 0);
  end;
end;

procedure TDBGridEventsTest.HintTheName(Sender: TObject; Column: TTyDBGridColumn;
  var AText: string);
begin
  Inc(FCount);
  AText := Column.FieldName + ': ' + Column.Field.AsString;
end;

procedure TDBGridEventsTest.PickTheEdit(Sender: TObject; Column: TTyDBGridColumn;
  var Editor: TWinControl);
begin
  FLog.Add('select ' + Column.FieldName);
  AssertNull('the grid''s own editor comes as nil', Editor);
  if Column.FieldName = 'Name' then Editor := FEditor;
end;

procedure TDBGridEventsTest.GrayEveryBox(Sender: TObject; Column: TTyDBGridColumn;
  var AState: TCheckBoxState);
begin
  FLog.Add(Format('%s %d', [Column.FieldName, Ord(AState)]));
  AState := cbGrayed;
end;

procedure TDBGridEventsTest.CountNotify(Sender: TObject);
begin
  Inc(FCount);
end;

procedure TDBGridEventsTest.CountCheck(Sender: TObject; ACol, ARow: Integer;
  AChecked: Boolean);
begin
  Inc(FCount);
end;

procedure TDBGridEventsTest.CountWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  Inc(FCount);
end;

{ ------------------------------------------------------------- the indicator ------ }

{ M: the mark not following dsEdit / dsInsert. }
procedure TDBGridEventsTest.TestIndicatorFollowsTheDataSetState;
var
  b: TBGRABitmap;
  k, none: TInk;
begin
  DS.MoveBy(2);                        // the current row is 2; row 5 shows nothing
  b := FGrid.Snapshot;
  try
    none := RowInk(b, 4, 5);
    AssertEquals('no mark on a row that is not current', 0, none.Count);
    k := RowInk(b, 2, 5);
  finally
    b.Free;
  end;
  AssertTrue('browsing: a mark', k.Count > 0);
  AssertTrue(Format('browsing: a triangle, its base on the left (%d / %d)', [k.Left, k.Right]),
    k.Left > (k.Right * 3) div 2);
  AssertEquals('browsing: in the indicator ink', 0, k.Accent);

  DS.Edit;
  b := FGrid.Snapshot;
  try
    k := RowInk(b, 2, 5);
  finally
    b.Free;
  end;
  AssertTrue('editing: a mark', k.Count > 0);
  AssertTrue(Format('editing: a bar, as much ink on either side (%d / %d)', [k.Left, k.Right]),
    Abs(k.Left - k.Right) <= (k.Left + k.Right) div 5);
  AssertEquals('editing: in the indicator ink', 0, k.Accent);
  DS.Cancel;

  DS.Insert;
  b := FGrid.Snapshot;
  try
    k := RowInk(b, FGrid.Row, 5);
  finally
    b.Free;
  end;
  AssertTrue('inserting: a mark', k.Count > 0);
  AssertTrue(Format('inserting: a bar (%d / %d)', [k.Left, k.Right]),
    Abs(k.Left - k.Right) <= (k.Left + k.Right) div 5);
  AssertTrue(Format('inserting: in the insert colour (%d of %d)', [k.Accent, k.Count]),
    k.Accent * 2 > k.Count);
  DS.Cancel;
end;

{ M: no mirror. }
procedure TDBGridEventsTest.TestIndicatorMirrorsRightToLeft;
var
  b: TBGRABitmap;
  k: TInk;
  i0, i1: Integer;
begin
  DS.MoveBy(2);
  FForm.BiDiMode := bdRightToLeft;
  AssertTrue('the grid reads right to left', FGrid.IsRightToLeft);
  FGrid.IndicatorSlot(i0, i1);
  AssertTrue('the band on the right', i0 > FGrid.Width div 2);
  b := FGrid.Snapshot;
  try
    k := RowInk(b, 2, 5);
  finally
    b.Free;
  end;
  AssertTrue('a mark', k.Count > 0);
  AssertTrue(Format('the triangle turned round, its base on the right (%d / %d)',
    [k.Left, k.Right]), k.Right > (k.Left * 3) div 2);
end;

{ ---------------------------------------------------------------- multiselect ------ }

procedure TDBGridEventsTest.TestPlainClickSelectsTheRecordAlone;
begin
  Multiselect;
  AssertEquals('nothing selected yet', 0, FGrid.SelectedRows.Count);
  FGrid.ClickCellWith(ColOf('Name'), 2, []);
  AssertEquals('the clicked record', '3', SelectedIDs);
  AssertTrue('it is the current one', FGrid.SelectedRows.CurrentRowSelected);
  FGrid.ClickCellWith(ColOf('Name'), 4, []);
  AssertEquals('a plain click: that one alone', '5', SelectedIDs);
  FGrid.Options := FGrid.Options - [dgMultiselect];
  AssertEquals('dgMultiselect off: nothing', 0, FGrid.SelectedRows.Count);
  FGrid.ClickCellWith(ColOf('Name'), 2, []);
  AssertEquals('nor by a click', 0, FGrid.SelectedRows.Count);
end;

{ M: Ctrl+click not toggling. }
procedure TDBGridEventsTest.TestCtrlClickToggles;
begin
  Multiselect;
  FGrid.ClickCellWith(ColOf('Name'), 1, []);
  FGrid.ClickCellWith(ColOf('Name'), 3, [ssCtrl]);
  AssertEquals('Ctrl+click adds', '2,4', SelectedIDs);
  AssertEquals('and moves there', 4, ID);
  FGrid.ClickCellWith(ColOf('Name'), 5, [ssCtrl]);
  AssertEquals('another', '2,4,6', SelectedIDs);
  FGrid.ClickCellWith(ColOf('Name'), 3, [ssCtrl]);
  AssertEquals('Ctrl+click on a selected one drops it', '2,6', SelectedIDs);
  AssertFalse('it is not selected', FGrid.SelectedRows.CurrentRowSelected);
  FGrid.PressKey(VK_MULTIPLY, [ssCtrl]);
  AssertEquals('Ctrl+* toggles it back', '2,4,6', SelectedIDs);
end;

{ M: Shift extension skipping a row; shrinking not dropping the row left. }
procedure TDBGridEventsTest.TestShiftArrowsExtendAndShrinkTheRun;
begin
  Multiselect;
  FGrid.ClickCellWith(ColOf('Name'), 2, []);
  FGrid.PressKey(VK_DOWN, [ssShift]);
  AssertEquals('Shift+Down: the next record too', '3,4', SelectedIDs);
  FGrid.PressKey(VK_DOWN, [ssShift]);
  AssertEquals('and the next', '3,4,5', SelectedIDs);
  AssertEquals('on the last of them', 5, ID);
  FGrid.PressKey(VK_UP, [ssShift]);
  AssertEquals('Shift+Up shrinks the run', '3,4', SelectedIDs);
  FGrid.PressKey(VK_UP, [ssShift]);
  FGrid.PressKey(VK_UP, [ssShift]);
  AssertEquals('past its start it grows upwards', '2,3', SelectedIDs);
  FGrid.PressKey(VK_DOWN);
  AssertEquals('a plain arrow: the record moved to alone', '3', SelectedIDs);
  FGrid.PressKey(VK_NEXT);
  AssertEquals('a page too', IntToStr(ID), SelectedIDs);
end;

procedure TDBGridEventsTest.TestPersistentMultiSelectKeepsTheSelection;
begin
  FGrid.Options := FGrid.Options + [dgMultiselect, dgPersistentMultiSelect];
  FGrid.ClickCellWith(ColOf('Name'), 1, [ssCtrl]);
  FGrid.ClickCellWith(ColOf('Name'), 3, [ssCtrl]);
  AssertEquals('Ctrl+clicks select', '2,4', SelectedIDs);
  FGrid.ClickCellWith(ColOf('Name'), 5, []);
  AssertEquals('a plain click keeps them', '2,4', SelectedIDs);
  FGrid.PressKey(VK_DOWN, [ssShift]);
  FGrid.PressKey(VK_DOWN);
  AssertEquals('the arrows keep them and add nothing', '2,4', SelectedIDs);
end;

procedure TDBGridEventsTest.TestSelectedRowsDeleteAndIndexOf;
var
  bm: TBookmark;
begin
  Multiselect;
  FGrid.ClickCellWith(ColOf('Name'), 1, []);
  FGrid.ClickCellWith(ColOf('Name'), 3, [ssCtrl]);
  FGrid.ClickCellWith(ColOf('Name'), 5, [ssCtrl]);
  bm := DS.GetBookmark;                  // record 6, selected last
  try
    AssertTrue('IndexOf finds it', FGrid.SelectedRows.IndexOf(bm) >= 0);
    DS.First;
    DS.FreeBookmark(bm);
    bm := DS.GetBookmark;                // record 1, not selected
    AssertEquals('IndexOf: not there', -1, FGrid.SelectedRows.IndexOf(bm));
  finally
    DS.FreeBookmark(bm);
  end;
  FGrid.SelectedRows.Delete;
  AssertEquals('three records deleted', CFixRowCount - 3, FRows.DS.RecordCount);
  AssertEquals('the list emptied', 0, FGrid.SelectedRows.Count);
  AssertFalse('2 gone', FRows.DS.Locate('ID', 2, []));
  AssertFalse('4 gone', FRows.DS.Locate('ID', 4, []));
  AssertFalse('6 gone', FRows.DS.Locate('ID', 6, []));
  AssertTrue('3 stays', FRows.DS.Locate('ID', 3, []));
end;

procedure TDBGridEventsTest.TestSelectedRowsRefreshDropsStaleBookmarks;
var
  stale: TStaleDataSet;
  src: TDataSource;
begin
  stale := TStaleDataSet.Create(nil);
  src := TDataSource.Create(nil);
  try
    FillRowsTable(stale);
    src.DataSet := stale;
    FGrid.DataSource := src;
    Multiselect;
    FGrid.ClickCellWith(ColOf('Name'), 1, []);
    FGrid.ClickCellWith(ColOf('Name'), 3, [ssCtrl]);
    AssertEquals('two selected', 2, FGrid.SelectedRows.Count);
    AssertFalse('nothing stale: nothing dropped', FGrid.SelectedRows.Refresh);
    stale.Stale := stale.GetBookmark;    // record 4 is "gone"
    AssertTrue('Refresh drops it', FGrid.SelectedRows.Refresh);
    AssertEquals('one left', 1, FGrid.SelectedRows.Count);
    stale.First;
    stale.Next;
    AssertTrue('the other one', FGrid.SelectedRows.CurrentRowSelected);
  finally
    FGrid.DataSource := nil;
    src.Free;
    stale.Free;
  end;
end;

procedure TDBGridEventsTest.TestSelectedRowsAreDrawnSelectedWithADot;
var
  b: TBGRABitmap;
  k: TInk;
  r: TRect;
  sel: TBGRAPixel;
begin
  Multiselect;
  FGrid.ClickCellWith(ColOf('Name'), 1, []);
  FGrid.ClickCellWith(ColOf('Name'), 3, [ssCtrl]);
  FGrid.ClickCellWith(ColOf('Name'), 5, []);        // only 6 now
  FGrid.ClickCellWith(ColOf('Name'), 1, [ssCtrl]);  // 2 and 6, on 2
  AssertEquals('two selected', '2,6', SelectedIDs);
  b := FGrid.Snapshot;
  try
    k := RowInk(b, 5, 3);
    AssertTrue('a selected row that is not current: a mark', k.Count > 0);
    AssertTrue(Format('a dot, round (%d / %d)', [k.Left, k.Right]),
      Abs(k.Left - k.Right) <= (k.Left + k.Right) div 4 + 1);
    AssertEquals('an unselected row: none', 0, RowInk(b, 4, 3).Count);
    sel := FGrid.SelectedBackground;
    r := FGrid.CellRect(ColOf('Name'), 5);
    AssertTrue('the selected row''s cell has the selected background',
      Dist(b.GetPixel(r.Right - 4, r.Top + 3), sel) < 40);
    r := FGrid.CellRect(ColOf('Name'), 4);
    AssertTrue('an unselected row''s has not',
      Dist(b.GetPixel(r.Right - 4, r.Top + 3), sel) >= 40);
  finally
    b.Free;
  end;
end;

procedure TDBGridEventsTest.TestClosingEmptiesTheSelection;
begin
  Multiselect;
  FGrid.ClickCellWith(ColOf('Name'), 1, []);
  FGrid.ClickCellWith(ColOf('Name'), 2, [ssCtrl]);
  AssertEquals('two', 2, FGrid.SelectedRows.Count);
  FRows.DS.Close;
  AssertEquals('closed: none', 0, FGrid.SelectedRows.Count);
end;

{ ---------------------------------------------------------- titles and headers ----- }

{ M: OnTitleClick not fired; the string grid's client sort back on a title click. }
procedure TDBGridEventsTest.TestTitleClickFiresAndDoesNotSort;
var
  sortCol: Integer;
  pt: TPoint;
begin
  FGrid.OnTitleClick := @LogTitleClick;
  sortCol := FGrid.SortColumn;
  pt := FGrid.TitlePoint(ColOf('Name'));
  FGrid.Press(pt);
  AssertEquals('not on the press', 0, FLog.Count);
  FGrid.Release(pt);
  AssertEquals('the click', 'title Name', Logged);
  AssertEquals('no sort in the grid', sortCol, FGrid.SortColumn);
  AssertEquals('the records where they were', FixRowName(1),
    FGrid.Cell(ColOf('Name'), 0));
  FLog.Clear;
  FGrid.Press(FGrid.TitlePoint(ColOf('Name')));
  FGrid.Release(FGrid.TitlePoint(ColOf('Amount')));
  AssertEquals('released on another title: no click', 0, FLog.Count);
end;

procedure TDBGridEventsTest.TestDividerDragIsSizedNotATitleClick;
var
  pt: TPoint;
  w: Integer;
begin
  FGrid.OnTitleClick := @LogTitleClick;
  FGrid.OnColumnSized := @LogColumnSized;
  w := FGrid.Columns[ColOf('Name')].Width;
  pt := FGrid.DividerPoint(ColOf('Name'));
  FGrid.Press(pt);
  FGrid.DragTo(Point(pt.X + 20, pt.Y));
  AssertEquals('nothing while dragging', 0, FLog.Count);
  FGrid.Release(Point(pt.X + 20, pt.Y));
  AssertEquals('wider', w + 20, FGrid.Columns[ColOf('Name')].Width);
  AssertEquals('sized once, no title click', 'sized', Logged);
end;

procedure TDBGridEventsTest.TestColumnDragFiresColumnMoved;
var
  a, b: TPoint;
begin
  FGrid.OnColumnMoved := @LogColumnMoved;
  FGrid.OnTitleClick := @LogTitleClick;
  a := FGrid.TitlePoint(1);
  b := FGrid.TitlePoint(3);
  FGrid.Press(a);
  FGrid.DragTo(b);
  FGrid.Release(b);
  AssertEquals('moved from position 1 to 3, no title click', 'moved 1 3',
    Logged);
end;

{ ------------------------------------------------------------------------ D9 ------ }

procedure TDBGridEventsTest.TestCellClickOnTheClickedRecord;
begin
  FGrid.OnCellClick := @LogCellClick;
  FGrid.ClickCellWith(ColOf('Name'), 3, []);
  AssertEquals('once, the record moved there first', 'click Name on 4',
    Logged);
  FGrid.ClickCellWith(ColOf('Amount'), 3, []);
  AssertEquals('again on the same record', 2, FLog.Count);
  AssertEquals('click Amount on 4', FLog[1]);
end;

procedure TDBGridEventsTest.TestColExitThenColEnter;
begin
  FGrid.OnColEnter := @LogColEnter;
  FGrid.OnColExit := @LogColExit;
  FGrid.Col := 0;
  FLog.Clear;
  FGrid.PressKey(VK_RIGHT);
  AssertEquals('exit on the old column, then enter on the new', 'exit 0,enter 1',
    Logged);
  FLog.Clear;
  FGrid.PressKey(VK_DOWN);
  AssertEquals('another record, the same column: neither', 0, FLog.Count);
  FGrid.ClickCellWith(3, 4, []);
  AssertEquals('a click on another column of another record', 'exit 1,enter 3',
    Logged);
end;

procedure TDBGridEventsTest.TestDrawColumnCellSeesEachRowsRecord;
var
  b: TBGRABitmap;
  r, nameCol: Integer;
begin
  FGrid.OnDrawColumnCell := @LogDrawCell;
  nameCol := ColOf('Name');
  b := FGrid.Snapshot;
  b.Free;
  for r := 0 to FGrid.RowCount - 1 do
    AssertTrue('row ' + IntToStr(r) + ' drawn with its own record',
      FLog.IndexOf(Format('%d=%s', [FGrid.CellRect(nameCol, r).Top, FixRowName(r + 1)])) >= 0);
  AssertTrue('the current cell is focused', FLog.IndexOf('ID focused') >= 0);
  AssertEquals('the dataset is where it was', 1, ID);
end;

procedure TDBGridEventsTest.TestDrawColumnCellCanTakeTheText;

  function DarkIn(B: TBGRABitmap; const R: TRect): Integer;
  var
    x, y: Integer;
    p: TBGRAPixel;
  begin
    Result := 0;
    for y := R.Top + 2 to R.Bottom - 3 do
      for x := R.Left + 2 to R.Right - 3 do
      begin
        p := B.GetPixel(x, y);
        if p.red + p.green + p.blue < 300 then Inc(Result);
      end;
  end;

var
  b: TBGRABitmap;
  r: TRect;
  before, after: Integer;
begin
  r := FGrid.CellRect(ColOf('Name'), 2);
  b := FGrid.Snapshot;
  try
    before := DarkIn(b, r);
  finally
    b.Free;
  end;
  AssertTrue('the name is drawn', before > 0);
  FGrid.OnDrawColumnCell := @TakeNameCell;
  b := FGrid.Snapshot;
  try
    after := DarkIn(b, r);
  finally
    b.Free;
  end;
  AssertEquals('handled: no text of the grid''s', 0, after);
end;

procedure TDBGridEventsTest.TestDrawColumnTitleForEachTitle;
var
  b: TBGRABitmap;
  i: Integer;
begin
  FGrid.OnDrawColumnTitle := @LogDrawTitle;
  b := FGrid.Snapshot;
  b.Free;
  for i := 0 to FGrid.Columns.Count - 1 do
    if FGrid.Columns[i].Visible and (FGrid.CellRect(i, 0).Left < FGrid.Width) then
      AssertTrue('the title of ' + FGrid.Columns[i].FieldName,
        FLog.IndexOf(Format('%s %d 0', [FGrid.Columns[i].FieldName,
          FGrid.CellRect(i, 0).Left])) >= 0);
end;

procedure TDBGridEventsTest.TestPrepareCanvasStylesTheCell;
var
  b: TBGRABitmap;
  r: TRect;
begin
  FGrid.OnPrepareCanvas := @PaintRowThreeRed;
  b := FGrid.Snapshot;
  try
    r := FGrid.CellRect(ColOf('Name'), 2);
    AssertTrue('record 3''s cell red',
      Dist(b.GetPixel(r.Right - 4, r.Top + 3), BGRA(255, 0, 0)) < 30);
    r := FGrid.CellRect(ColOf('Name'), 1);
    AssertTrue('record 2''s not',
      Dist(b.GetPixel(r.Right - 4, r.Top + 3), BGRA(255, 0, 0)) >= 30);
    r := FGrid.CellRect(ColOf('Amount'), 2);
    AssertTrue('nor another column',
      Dist(b.GetPixel(r.Left + 4, r.Top + 3), BGRA(255, 0, 0)) >= 30);
  finally
    b.Free;
  end;
end;

procedure TDBGridEventsTest.TestGetCellHintOnTheHoveredRecord;
begin
  FGrid.Options := FGrid.Options + [dgCellHints];   // LCL's switch for cell hints
  FGrid.Hint := 'mine';
  FGrid.Hover(ColOf('Name'), 2);
  AssertEquals('no handler: the grid''s hint is left alone', 'mine', FGrid.Hint);
  FGrid.OnGetCellHint := @HintTheName;
  FGrid.Hover(ColOf('Amount'), 4);
  FGrid.Hover(ColOf('Name'), 3);
  AssertEquals('the hovered record''s value', 'Name: ' + FixRowName(4), FGrid.Hint);
  AssertTrue('asked', FCount > 0);
  AssertEquals('the dataset stays put', 1, ID);
end;

procedure TDBGridEventsTest.TestSelectEditorPutsTheControlOnTheCell;
begin
  FEditor := TEdit.Create(FForm);
  FEditor.Parent := FForm;
  FEditor.Visible := False;
  FGrid.OnSelectEditor := @PickTheEdit;
  FGrid.Col := ColOf('Amount');
  FGrid.PressKey(VK_F2);
  AssertEquals('asked for Amount', 'select Amount', Logged);
  AssertFalse('not given: the grid''s own editor', FEditor.Visible);
  FGrid.EndEdit(False);
  FGrid.Col := ColOf('Name');
  FGrid.PressKey(VK_F2);
  AssertTrue('the control is the editor', FEditor.Visible);
  AssertSame('on the grid', TWinControl(FGrid), FEditor.Parent);
  AssertEquals('with the field''s text', FixRowName(1), FEditor.Text);
  FEditor.Text := 'Picked';
  FGrid.EndEdit(True);
  AssertEquals('read back into the field', 'Picked', DS.FieldByName('Name').AsString);
  AssertFalse('hidden again', FEditor.Visible);
end;

procedure TDBGridEventsTest.TestEditButtonClick;
var
  r: TRect;
  c: Integer;
begin
  c := ColOf('Name');
  FGrid.Columns[c].EditorKind := gekEllipsis;
  FGrid.OnEditButtonClick := @CountNotify;
  r := FGrid.EllipsisRect(c, 2);
  AssertFalse('an ellipsis button', IsRectEmpty(r));
  FGrid.ClickAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  AssertEquals('pressed once', 1, FCount);
  AssertEquals('on its record', 3, ID);
  FGrid.ClickCellWith(ColOf('Amount'), 2, []);
  AssertEquals('another cell: not', 1, FCount);
end;

procedure TDBGridEventsTest.TestUserCheckboxState;
var
  c: Integer;
begin
  c := ColOf('Flag');
  AssertTrue('record 1 flagged', FGrid.CellCheckState(c, 0) = cbChecked);
  FGrid.OnUserCheckboxState := @GrayEveryBox;
  AssertTrue('the handler''s state', FGrid.CellCheckState(c, 0) = cbGrayed);
  AssertTrue('every row', FGrid.CellCheckState(c, 1) = cbGrayed);
  AssertTrue('given the field''s state: checked', FLog.IndexOf('Flag 1') >= 0);
  AssertTrue('and unchecked', FLog.IndexOf('Flag 0') >= 0);
end;

{ ----------------------------------------------------------------- left over ------ }

{ M: Tab not wrapping. }
procedure TDBGridEventsTest.TestTabWrapsToTheNextRecord;
var
  n: Integer;
begin
  n := FGrid.RowCount;
  DS.MoveBy(n - 1);
  AssertEquals('on the window''s last row', n - 1, FGrid.Row);
  FGrid.Col := FGrid.LastVisibleCol;
  AssertEquals('Tab consumed', 0, FGrid.PressKey(VK_TAB));
  AssertEquals('the next record', n + 1, ID);
  AssertEquals('its first field', FGrid.FirstVisibleCol, FGrid.Col);
  AssertEquals('the window scrolled', n - 1, FGrid.Row);
  FGrid.Col := 1;
  FGrid.PressKey(VK_TAB);
  AssertEquals('inside the row: the next field', 2, FGrid.Col);
  AssertEquals('the same record', n + 1, ID);
end;

procedure TDBGridEventsTest.TestTabOnTheLastRecordAppends;
begin
  DS.Last;
  FGrid.Col := FGrid.LastVisibleCol;
  FGrid.PressKey(VK_TAB);
  AssertTrue('a new record', DS.State = dsInsert);
  AssertEquals('its first field', FGrid.FirstVisibleCol, FGrid.Col);
  DS.Cancel;
  FGrid.Options := FGrid.Options + [dgDisableInsert];
  DS.Last;
  FGrid.Col := FGrid.LastVisibleCol;
  FGrid.PressKey(VK_TAB);
  AssertTrue('dgDisableInsert: none', DS.State = dsBrowse);
  AssertEquals('still the last record', CFixRowCount, ID);
end;

procedure TDBGridEventsTest.TestShiftTabWrapsBack;
var
  first: Integer;
begin
  DS.Last;
  DS.MoveBy(-(FGrid.RowCount - 1));
  AssertEquals('on the window''s first row', 0, FGrid.Row);
  first := ID;
  AssertTrue('records above the window', first > 1);
  FGrid.Col := FGrid.FirstVisibleCol;
  AssertEquals('Shift+Tab consumed', 0, FGrid.PressKey(VK_TAB, [ssShift]));
  AssertEquals('the record before', first - 1, ID);
  AssertEquals('its last field', FGrid.LastVisibleCol, FGrid.Col);
  DS.First;
  FGrid.Col := FGrid.FirstVisibleCol;
  FGrid.PressKey(VK_TAB, [ssShift]);
  AssertEquals('on the first record it goes nowhere', 1, ID);
end;

{ M: OnCheckBoxChange after a refused Edit. }
procedure TDBGridEventsTest.TestRefusedEditFiresNoCheckBoxChange;
var
  c: Integer;
begin
  c := ColOf('Flag');
  FGrid.OnCheckBoxChange := @CountCheck;
  FRows.Src.AutoEdit := False;
  FGrid.Col := c;
  FGrid.PressKey(VK_SPACE);
  FGrid.ClickCheckBox(c, 0);
  AssertEquals('refused: no change reported', 0, FCount);
  AssertTrue('nothing changed', DS.FieldByName('Flag').AsBoolean);
  AssertTrue('still browsing', DS.State = dsBrowse);
  FRows.Src.AutoEdit := True;
  FGrid.PressKey(VK_SPACE);
  AssertEquals('allowed: reported', 1, FCount);
  AssertFalse('and changed', DS.FieldByName('Flag').AsBoolean);
end;

{ The base grid's DoMouseWheel fires none of the wheel events today; the DB grid fires them
  itself (FireWheelEvents). When the base fix lands, a second fire shows here. }
procedure TDBGridEventsTest.TestOneNotchFiresTheEventOnce;
begin
  FGrid.OnMouseWheel := @CountWheel;
  WheelTick(FGrid, -120);
  AssertEquals('with a dataset: once', 1, FCount);
  AssertEquals('and the record moved', 2, ID);
  FGrid.DataSource := nil;
  FCount := 0;
  WheelTick(FGrid, -120);
  AssertEquals('without one: once', 1, FCount);
end;

initialization
  RegisterTest(TDBGridEventsTest);
end.
