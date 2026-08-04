unit test.parity.grid.members;
{ LCL parity, second pass: members TTyCustomGrid / TTyStringGrid / TTyGridColumn /
  TTyColumns did not have at all, plus three properties that WERE there but that
  nothing ever read.

  The three dead ones are the reason this file is not just a list of new API:

    TTyHeader.Images     published on the grid's own Header, and the grid resolved
                         column icons against its private Images list instead. A user
                         who assigned it in the Object Inspector got nothing, silently.
    hoHotTrack           published in Header.Options, and the grid never read it --
                         even though themes/light.tycss has carried a
                         `TyGridHeaderSection:hover` rule the whole time.
    ToggleCellChecked    always wrote '1' / '', whatever vocabulary the column's data
                         used. Clicking a checkbox in a 'Y'/'N' column REPLACED the
                         host's value, and OnCellEdited passes ANewText as const so a
                         host could not even correct it on the way through.

  Everything else here is an absent member: the guard's "red" before the fix was a
  compile error, so each one is backed by a mutation instead -- break the
  implementation, watch the assertion below go red. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, StdCtrls, TypInfo, LMessages,
  fpcunit, testregistry, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.ImageCollection,
  tyControls.Columns, tyControls.Grid;

type
  { Promotes the render entry point and the protected helpers a paint-level guard
    needs. Everything a HOST is supposed to reach is asserted through a bare
    TTyStringGrid variable instead -- see NewGrid. }
  TMemberGridAccess = class(TTyStringGrid)
  public
    property ScrollX;
    property ScrollY;
    function  HeaderImages: TTyVirtualImageList;
    function  RenderToBitmap: TBGRABitmap;
    procedure Hover(X, Y: Integer);
    procedure LeaveControl;
    { A real Ctrl+click, not a call to CommitActiveSelection: the multi-select
      guards have to cross the same MouseDown path the user does, or the gate
      that RangeSelectMode sits on is never exercised. }
    procedure CtrlClick(X, Y: Integer);
  end;

  TGridMemberFixture = class(TTestCase)
  protected
    FForm: TForm;
    FCtl: TTyStyleController;
    { Deliberately the BARE class: every member below has to be reachable from a
      plain TTyStringGrid, i.e. from a host. A promoting subclass would let one slip
      back into protected and still test green. }
    function NewGrid: TTyStringGrid;
    function NewAccessGrid: TMemberGridAccess;
    procedure SetUp; override;
    procedure TearDown; override;
    { Fails unless AName is a PUBLISHED property of the grid -- the only thing that
      makes it settable from a .lfm or visible in the Object Inspector. }
    procedure AssertPublished(const AName: string);
  end;

  { ColWidths / DefaultColWidth / GridWidth / GridHeight / VisibleColCount:
    the column-axis twins of members the row axis already had. }
  TGridColumnAxisTest = class(TGridMemberFixture)
  published
    procedure TestColWidthsReadsAndWritesTheColumnWidth;
    procedure TestColWidthsHonoursTheGridWideClamps;
    procedure TestColWidthsIgnoresOutOfRangeColumns;
    procedure TestDefaultColWidthAppliesToNewColumns;
    procedure TestDefaultColWidthDoesNotDisturbExistingColumns;
    procedure TestGridWidthAndHeightAreReachableFromAHost;
    procedure TestVisibleColCountIsBoundedByTheViewport;
  end;

  { LeftCol / TopRow / OnTopLeftChanged. }
  TGridViewportPositionTest = class(TGridMemberFixture)
  private
    FTopLeftHits: Integer;
    procedure CountTopLeft(Sender: TObject);
  published
    procedure TestTopRowFollowsTheVerticalScroll;
    procedure TestWritingTopRowScrollsWithoutMovingTheCursor;
    procedure TestLeftColFollowsTheHorizontalScroll;
    procedure TestWritingLeftColScrollsWithoutMovingTheCursor;
    procedure TestTopLeftChangedFiresWhenTheFirstVisibleRowChanges;
    procedure TestTopLeftChangedStaysSilentWithinTheSameRow;
  end;

  { Clear / Modified / HideSortArrow. }
  TGridStructureTest = class(TGridMemberFixture)
  published
    procedure TestClearDropsRowsAndColumnsTogether;
    procedure TestModifiedStartsFalseAndFollowsAnEdit;
    procedure TestModifiedIgnoresARewriteOfTheSameValue;
    procedure TestModifiedFollowsARowCountChange;
    procedure TestLoadingResetsModified;
    procedure TestHideSortArrowKeepsTheRowOrder;
    procedure TestSortingBringsTheArrowBack;
  end;

  { ClearSelections / SelectedRange[] / SelectedRangeCount / HasMultiSelection /
    RangeSelectMode. }
  TGridSelectionApiTest = class(TGridMemberFixture)
  published
    procedure TestSelectedRangeCountIsOneForASingleBlock;
    procedure TestEveryCtrlClickedBlockIsEnumerable;
    procedure TestHasMultiSelectionOnlyOnceThereIsMoreThanOneBlock;
    procedure TestSingleRangeModeRefusesToAccumulate;
    procedure TestClearSelectionsDropsTheExtraBlocks;
  end;

  { EditorMode / InplaceEditor / SelectedColumn. }
  TGridEditorApiTest = class(TGridMemberFixture)
  published
    procedure TestEditorModeOpensAndCommits;
    procedure TestInplaceEditorIsNilUntilEditingStarts;
    procedure TestSelectedColumnFollowsTheCursor;
  end;

  { Properties that existed but only in `public`, so no designer could touch them,
    plus the LCL-named aliases. }
  TGridDesignerSurfaceTest = class(TGridMemberFixture)
  published
    procedure TestScrollBarModesAreDesignerVisible;
    procedure TestScrollBarsMapsOntoTheTwoModes;
    procedure TestScrollBarsReadsBackWhatItWrote;
    procedure TestFocusRectVisibleAliasesShowFocusCell;
    procedure TestFadeUnfocusedSelectionAliasesHideSelectionWhenInactive;
  end;

  { TTyColumn / TTyColumns / TTyGridColumn members. }
  TGridColumnMemberTest = class(TGridMemberFixture)
  published
    procedure TestColumnVisibleMirrorsTheOptionFlag;
    procedure TestHidingViaVisibleTakesTheWidthOutOfTheTotal;
    procedure TestMinSizeAndMaxSizeAliasTheWidthBounds;
    procedure TestItemsIsTypedAndIsTheDefaultArray;
    procedure TestAddIsTyped;
    procedure TestColumnByTitleFindsTheColumn;
    procedure TestColumnByTitleAnswersNilWhenAbsent;
    procedure TestColumnColourReachesTheCell;
    procedure TestColumnLayoutReachesTheCell;
  end;

  { Per-column checkbox vocabulary. }
  TGridCheckVocabularyTest = class(TGridMemberFixture)
  private
    FReportedChecked: Boolean;
    procedure NoteCheckChange(Sender: TObject; ACol, ARow: Integer;
      AChecked: Boolean);
  published
    procedure TestTogglingWritesTheColumnsOwnWords;
    procedure TestTogglingBackWritesTheUncheckedWord;
    procedure TestTheColumnsWordsAreRecognisedOnRead;
    procedure TestChangeEventReportsTheRealState;
    procedure TestDefaultVocabularyIsUnchanged;
  end;

  { AutoFillColumns + SizePriority. }
  TGridAutoFillTest = class(TGridMemberFixture)
  published
    procedure TestFillingSpreadsSpareWidthOverEveryColumn;
    procedure TestSizePriorityWeightsTheShare;
    procedure TestZeroPriorityColumnKeepsItsWidth;
    procedure TestMaxWidthLeftoverGoesToTheOthers;
  end;

  { CSV knobs. }
  TGridCsvOptionTest = class(TGridMemberFixture)
  published
    procedure TestExportCanSkipHiddenColumns;
    procedure TestExportKeepsHiddenColumnsByDefault;
    procedure TestImportCanSkipBlankLines;
    procedure TestImportKeepsBlankLinesByDefault;
  end;

  { SaveToFile / LoadFromFile. }
  TGridFilePersistenceTest = class(TGridMemberFixture)
  published
    procedure TestFileRoundTripsTheWholeGrid;
  end;

  { The two properties that were live in the Object Inspector and did nothing. }
  TGridDeadPropertyTest = class(TGridMemberFixture)
  published
    procedure TestHeaderImagesOverridesTheGridsOwnList;
    procedure TestHeaderImagesFallsBackToTheGridsOwnList;
    procedure TestHotTrackHighlightsTheHoveredHeaderSection;
    procedure TestWithoutHotTrackTheHeaderDoesNotReact;
    procedure TestLeavingTheControlDropsTheHeaderHighlight;
  end;

implementation

{ TMemberGridAccess }

function TMemberGridAccess.HeaderImages: TTyVirtualImageList;
begin
  Result := HeaderImageList;
end;

function TMemberGridAccess.RenderToBitmap: TBGRABitmap;
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(Width, Height);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, bmp.Width, bmp.Height);
    RenderTo(bmp.Canvas, Rect(0, 0, Width, Height), 96);
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
  end;
end;

procedure TMemberGridAccess.Hover(X, Y: Integer);
begin
  MouseMove([], X, Y);
end;

procedure TMemberGridAccess.CtrlClick(X, Y: Integer);
begin
  MouseDown(mbLeft, [ssCtrl], X, Y);
end;

procedure TMemberGridAccess.LeaveControl;
var
  msg: TLMessage;
begin
  msg := Default(TLMessage);
  CMMouseLeave(msg);
end;

{ Number of pixels differing between two frames inside R. Colour-agnostic, so it
  answers "did this area change at all" without assuming what the theme paints. }
function DiffPixels(A, B: TBGRABitmap; const R: TRect): Integer;
var
  x, y: Integer;
  pa, pb: TBGRAPixel;
begin
  Result := 0;
  for y := R.Top to R.Bottom - 1 do
    for x := R.Left to R.Right - 1 do
    begin
      if (x < 0) or (y < 0) or (x >= A.Width) or (y >= A.Height) then Continue;
      pa := A.GetPixel(x, y);
      pb := B.GetPixel(x, y);
      if (pa.red <> pb.red) or (pa.green <> pb.green) or (pa.blue <> pb.blue) then
        Inc(Result);
    end;
end;

{ TGridMemberFixture }

procedure TGridMemberFixture.SetUp;
begin
  inherited SetUp;
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 600, 400);
end;

procedure TGridMemberFixture.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

function TGridMemberFixture.NewAccessGrid: TMemberGridAccess;
var
  i: Integer;
  c: TTyColumn;
begin
  Result := TMemberGridAccess.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 300);
  for i := 0 to 3 do
  begin
    c := Result.Header.Columns.Add;
    c.Width := 80;
    c.Text := 'C' + IntToStr(i);
  end;
  Result.DefaultRowHeight := 20;
  Result.RowCount := 10;
end;

function TGridMemberFixture.NewGrid: TTyStringGrid;
begin
  Result := NewAccessGrid;
  { The header band is off for the maths-only guards; the paint guards turn it
    back on themselves. }
  Result.Header.Options := Result.Header.Options - [hoVisible];
end;

procedure TGridMemberFixture.AssertPublished(const AName: string);
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  AssertTrue(AName + ' must be a PUBLISHED property -- in `public` it cannot be '
    + 'set in the Object Inspector nor streamed from a .lfm',
    GetPropInfo(G, AName) <> nil);
end;

{ ------------------------------------------------------------------ }
{ TGridColumnAxisTest }

procedure TGridColumnAxisTest.TestColWidthsReadsAndWritesTheColumnWidth;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  AssertEquals('reads the fixture width', 80, G.ColWidths[2]);
  G.ColWidths[2] := 140;
  AssertEquals('writes through to the column', 140, G.ColWidths[2]);
  AssertEquals('and the column agrees', 140, G.Header.Columns.Items[2].Width);
end;

{ The write path has to clamp exactly like dragging the divider does, or the same
  grid answers two different minimum widths depending on how you got there. }
procedure TGridColumnAxisTest.TestColWidthsHonoursTheGridWideClamps;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.MinColWidth := 50;
  G.MaxColWidth := 120;
  G.ColWidths[1] := 10;
  AssertEquals('clamped up to MinColWidth', 50, G.ColWidths[1]);
  G.ColWidths[1] := 999;
  AssertEquals('clamped down to MaxColWidth', 120, G.ColWidths[1]);
end;

procedure TGridColumnAxisTest.TestColWidthsIgnoresOutOfRangeColumns;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  AssertEquals('out of range reads 0', 0, G.ColWidths[99]);
  G.ColWidths[99] := 40;      { must not raise }
  G.ColWidths[-1] := 40;
  AssertEquals('real columns untouched', 80, G.ColWidths[0]);
end;

procedure TGridColumnAxisTest.TestDefaultColWidthAppliesToNewColumns;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.DefaultColWidth := 55;
  G.InsertColumn(G.Header.Columns.Count);
  AssertEquals('the new column starts at DefaultColWidth',
    55, G.ColWidths[G.Header.Columns.Count - 1]);
end;

{ LCL's SetDefColWidth retro-fits columns that were never sized; ours deliberately
  does not, because we have no "was this width explicit" bit to consult and
  guessing would wipe widths the user dragged. }
procedure TGridColumnAxisTest.TestDefaultColWidthDoesNotDisturbExistingColumns;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.DefaultColWidth := 55;
  AssertEquals('existing column keeps its width', 80, G.ColWidths[0]);
end;

procedure TGridColumnAxisTest.TestGridWidthAndHeightAreReachableFromAHost;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  { 4 columns x 80, no indicator. }
  AssertEquals('GridWidth is the summed column width', 320, G.GridWidth);
  AssertEquals('GridHeight is the summed row height', 200, G.GridHeight);
  G.ColWidths[0] := 100;
  AssertEquals('and it follows a width change', 340, G.GridWidth);
end;

procedure TGridColumnAxisTest.TestVisibleColCountIsBoundedByTheViewport;
var
  G: TTyStringGrid;
  i: Integer;
begin
  G := NewGrid;
  for i := 1 to 20 do G.Header.Columns.Add.Width := 80;
  { 400px of viewport at 80px a column holds five, not twenty-four. }
  AssertTrue('a viewport metric cannot exceed what the viewport holds: got '
    + IntToStr(G.VisibleColCount), G.VisibleColCount <= 6);
  AssertTrue('and it must count more than nothing', G.VisibleColCount >= 4);
end;

{ ------------------------------------------------------------------ }
{ TGridViewportPositionTest }

procedure TGridViewportPositionTest.CountTopLeft(Sender: TObject);
begin
  Inc(FTopLeftHits);
end;

procedure TGridViewportPositionTest.TestTopRowFollowsTheVerticalScroll;
var
  G: TMemberGridAccess;
begin
  G := NewAccessGrid;
  G.Header.Options := G.Header.Options - [hoVisible];
  G.RowCount := 100;
  AssertEquals('unscrolled the first visible row is 0', 0, G.TopRow);
  G.ScrollY := 100;            { 5 rows of 20px }
  AssertEquals('scrolled 5 rows down', 5, G.TopRow);
end;

procedure TGridViewportPositionTest.TestWritingTopRowScrollsWithoutMovingTheCursor;
var
  G: TMemberGridAccess;
begin
  G := NewAccessGrid;
  G.Header.Options := G.Header.Options - [hoVisible];
  G.RowCount := 100;
  G.Row := 3;
  G.TopRow := 20;
  AssertEquals('the viewport moved', 20, G.TopRow);
  AssertEquals('the scroll offset moved with it', 400, G.ScrollY);
  AssertEquals('the cursor did NOT move -- that is the whole point of TopRow',
    3, G.Row);
end;

procedure TGridViewportPositionTest.TestLeftColFollowsTheHorizontalScroll;
var
  G: TMemberGridAccess;
  i: Integer;
begin
  G := NewAccessGrid;
  G.Header.Options := G.Header.Options - [hoVisible];
  for i := 1 to 20 do G.Header.Columns.Add.Width := 80;
  AssertEquals('unscrolled the first visible column is 0', 0, G.LeftCol);
  G.ScrollX := 160;            { two columns }
  AssertEquals('scrolled two columns right', 2, G.LeftCol);
end;

procedure TGridViewportPositionTest.TestWritingLeftColScrollsWithoutMovingTheCursor;
var
  G: TMemberGridAccess;
  i: Integer;
begin
  G := NewAccessGrid;
  G.Header.Options := G.Header.Options - [hoVisible];
  for i := 1 to 20 do G.Header.Columns.Add.Width := 80;
  G.Col := 1;
  G.LeftCol := 6;
  AssertEquals('the viewport moved', 6, G.LeftCol);
  AssertEquals('the scroll offset moved with it', 480, G.ScrollX);
  AssertEquals('the cursor did NOT move', 1, G.Col);
end;

procedure TGridViewportPositionTest.TestTopLeftChangedFiresWhenTheFirstVisibleRowChanges;
var
  G: TMemberGridAccess;
  i: Integer;
begin
  G := NewAccessGrid;
  G.Header.Options := G.Header.Options - [hoVisible];
  G.RowCount := 100;
  { Enough columns that the horizontal axis actually HAS somewhere to scroll --
    with the fixture's four the offset clamps to 0 and no event is due. }
  for i := 1 to 20 do G.Header.Columns.Add.Width := 80;
  G.OnTopLeftChanged := @CountTopLeft;
  FTopLeftHits := 0;
  G.ScrollY := 100;
  AssertEquals('a vertical scroll past a row boundary must notify', 1, FTopLeftHits);
  G.ScrollX := 160;
  AssertEquals('and so must a horizontal one', 2, FTopLeftHits);
end;

{ Ours scrolls by pixels, LCL by whole cells. The event is named after the CELL,
  so a three-pixel nudge that leaves the same row on top is not a change. }
procedure TGridViewportPositionTest.TestTopLeftChangedStaysSilentWithinTheSameRow;
var
  G: TMemberGridAccess;
begin
  G := NewAccessGrid;
  G.Header.Options := G.Header.Options - [hoVisible];
  G.RowCount := 100;
  G.ScrollY := 100;
  G.OnTopLeftChanged := @CountTopLeft;
  FTopLeftHits := 0;
  G.ScrollY := 103;
  AssertEquals('still row 5 on top: no notification', 0, FTopLeftHits);
  G.ScrollY := 120;
  AssertEquals('row 6 now: one notification', 1, FTopLeftHits);
end;

{ ------------------------------------------------------------------ }
{ TGridStructureTest }

procedure TGridStructureTest.TestClearDropsRowsAndColumnsTogether;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.Cells[0, 0] := 'x';
  G.Clear;
  AssertEquals('no rows left', 0, G.RowCount);
  AssertEquals('no columns left -- mapping Clear onto ClearCells left them standing',
    0, G.Header.Columns.Count);
end;

procedure TGridStructureTest.TestModifiedStartsFalseAndFollowsAnEdit;
var
  G: TTyStringGrid;
begin
  { A virgin grid, not the fixture: the fixture sets RowCount, and a row-count
    change is itself a modification (see TestModifiedFollowsARowCountChange). }
  G := TTyStringGrid.Create(FForm);
  G.Parent := FForm;
  G.Controller := FCtl;
  AssertFalse('a freshly constructed grid is not modified', G.Modified);
  G.Header.Columns.Add;
  G.Header.Columns.Add;
  G.RowCount := 4;
  G.Modified := False;
  G.Cells[1, 1] := 'v';
  AssertTrue('writing a cell modifies it', G.Modified);
  G.Modified := False;
  AssertFalse('and the host can reset it after saving', G.Modified);
end;

procedure TGridStructureTest.TestModifiedIgnoresARewriteOfTheSameValue;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.Cells[1, 1] := 'v';
  G.Modified := False;
  G.Cells[1, 1] := 'v';
  AssertFalse('rewriting the same value is not a change', G.Modified);
end;

{ Inserting a row into an empty grid moves no cells, so the SetCells choke point
  cannot see it -- but the grid is not the same grid afterwards. }
procedure TGridStructureTest.TestModifiedFollowsARowCountChange;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.Modified := False;
  G.RowCount := 12;
  AssertTrue('a structural change modifies it too', G.Modified);
end;

procedure TGridStructureTest.TestLoadingResetsModified;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.Cells[0, 0] := 'dirty';
  G.LoadFromCSVText('A,B'#10'1,2'#10);
  AssertFalse('a grid that was just loaded has not been edited', G.Modified);
end;

procedure TGridStructureTest.TestHideSortArrowKeepsTheRowOrder;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.RowCount := 3;
  G.Cells[0, 0] := 'c';
  G.Cells[0, 1] := 'a';
  G.Cells[0, 2] := 'b';
  G.SortByColumn(0, sdAscending);
  AssertEquals('sorted: display row 0 is the data row holding "a"',
    1, G.DisplayToData(0));
  G.HideSortArrow;
  AssertEquals('the indicator is off', NoColumn, G.Header.SortColumn);
  AssertEquals('but the ORDER is untouched -- that is what separates this from '
    + 'ClearSortColumns', 1, G.DisplayToData(0));
end;

procedure TGridStructureTest.TestSortingBringsTheArrowBack;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.RowCount := 3;
  G.SortByColumn(0, sdAscending);
  G.HideSortArrow;
  G.SortByColumn(1, sdAscending);
  AssertEquals('a fresh sort shows its own indicator again', 1, G.Header.SortColumn);
end;

{ ------------------------------------------------------------------ }
{ TGridSelectionApiTest }

procedure TGridSelectionApiTest.TestSelectedRangeCountIsOneForASingleBlock;
var
  G: TMemberGridAccess;
begin
  G := NewAccessGrid;
  G.SelectRange(0, 0, 1, 1);
  AssertEquals('one block', 1, G.SelectedRangeCount);
  AssertEquals('and it is the active rect', 0, G.SelectedRange[0].Left);
  AssertEquals('', 1, G.SelectedRange[0].Right);
end;

{ The defect this pins: a host iterating "the selection" saw only the LAST block,
  so the first two of three Ctrl-clicked blocks vanished without a word. }
procedure TGridSelectionApiTest.TestEveryCtrlClickedBlockIsEnumerable;
var
  G: TMemberGridAccess;
  seen: string;
  i: Integer;
begin
  G := NewAccessGrid;
  G.SelectRange(0, 0, 0, 0);
  { The header band is on in this fixture, so y=45 lands in row 1 and y=85 in row 3. }
  G.CtrlClick(5, 45);
  G.CtrlClick(5, 85);
  AssertEquals('three blocks', 3, G.SelectedRangeCount);
  seen := '';
  for i := 0 to G.SelectedRangeCount - 1 do
    seen := seen + IntToStr(G.SelectedRange[i].Top) + ';';
  { Index 0 is the ACTIVE block (anchor to cursor, so row 3), then the committed
    ones in the order the user made them. Before this property existed a host
    could see only the first of those three. }
  AssertEquals('every block is reachable', '3;0;1;', seen);
end;

procedure TGridSelectionApiTest.TestHasMultiSelectionOnlyOnceThereIsMoreThanOneBlock;
var
  G: TMemberGridAccess;
begin
  G := NewAccessGrid;
  G.SelectRange(0, 0, 1, 1);
  AssertFalse('one block is not a multi-selection', G.HasMultiSelection);
  G.CtrlClick(5, 45);
  AssertTrue('two blocks is', G.HasMultiSelection);
end;

procedure TGridSelectionApiTest.TestSingleRangeModeRefusesToAccumulate;
var
  G: TMemberGridAccess;
begin
  G := NewAccessGrid;
  G.RangeSelectMode := rsmSingle;
  G.SelectRange(0, 0, 1, 1);
  G.CtrlClick(5, 45);
  AssertEquals('rsmSingle keeps exactly one block', 1, G.SelectedRangeCount);
  AssertFalse('and never reports a multi-selection', G.HasMultiSelection);
end;

procedure TGridSelectionApiTest.TestClearSelectionsDropsTheExtraBlocks;
var
  G: TMemberGridAccess;
begin
  G := NewAccessGrid;
  G.SelectRange(0, 0, 1, 1);
  G.CtrlClick(5, 45);
  G.ClearSelections;
  AssertEquals('back to the single active block', 1, G.SelectedRangeCount);
end;

{ ------------------------------------------------------------------ }
{ TGridEditorApiTest }

procedure TGridEditorApiTest.TestEditorModeOpensAndCommits;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  AssertFalse('not editing to begin with', G.EditorMode);
  G.EditorMode := True;
  AssertTrue('setting it opens the editor', G.EditorMode);
  AssertTrue('and Editing agrees', G.Editing);
  G.Editor.Text := 'typed';
  G.EditorMode := False;
  AssertFalse('clearing it closes the editor', G.EditorMode);
  AssertEquals('False COMMITS, as in LCL -- it is not a cancel', 'typed',
    G.Cells[0, 0]);
end;

procedure TGridEditorApiTest.TestInplaceEditorIsNilUntilEditingStarts;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  AssertTrue('nothing is being edited', G.InplaceEditor = nil);
  G.BeginEdit;
  AssertTrue('the active editor is reachable under LCL''s name',
    G.InplaceEditor <> nil);
  AssertSame('and it is the same control EditorControl reports',
    G.EditorControl, G.InplaceEditor);
end;

procedure TGridEditorApiTest.TestSelectedColumnFollowsTheCursor;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.Col := 2;
  AssertTrue('there is a column under the cursor', G.SelectedColumn <> nil);
  AssertEquals('and it is column 2', 'C2', G.SelectedColumn.Text);
  G.Col := 0;
  AssertEquals('it follows', 'C0', G.SelectedColumn.Text);
end;

{ ------------------------------------------------------------------ }
{ TGridDesignerSurfaceTest }

procedure TGridDesignerSurfaceTest.TestScrollBarModesAreDesignerVisible;
begin
  AssertPublished('VertScrollBarMode');
  AssertPublished('HorzScrollBarMode');
  AssertPublished('ScrollBars');
end;

procedure TGridDesignerSurfaceTest.TestScrollBarsMapsOntoTheTwoModes;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.ScrollBars := ssNone;
  AssertTrue('vertical off', G.VertScrollBarMode = gsbNever);
  AssertTrue('horizontal off', G.HorzScrollBarMode = gsbNever);
  G.ScrollBars := ssVertical;
  AssertTrue('vertical always on', G.VertScrollBarMode = gsbAlways);
  AssertTrue('horizontal still off', G.HorzScrollBarMode = gsbNever);
end;

procedure TGridDesignerSurfaceTest.TestScrollBarsReadsBackWhatItWrote;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  AssertTrue('the default is ssAutoBoth, as in LCL', G.ScrollBars = ssAutoBoth);
  { ssNone explicitly: it is the value a designer reaches for ("no scrollbars on
    this grid") and the only one the getter answers from a two-Never combination.
    A version of this guard that skipped it left a broken getter alive. }
  G.ScrollBars := ssNone;
  AssertTrue('round-trips', G.ScrollBars = ssNone);
  G.ScrollBars := ssHorizontal;
  AssertTrue('round-trips', G.ScrollBars = ssHorizontal);
  G.ScrollBars := ssAutoVertical;
  AssertTrue('round-trips', G.ScrollBars = ssAutoVertical);
  G.ScrollBars := ssBoth;
  AssertTrue('round-trips', G.ScrollBars = ssBoth);
end;

procedure TGridDesignerSurfaceTest.TestFocusRectVisibleAliasesShowFocusCell;
var
  G: TTyStringGrid;
begin
  AssertPublished('ShowFocusCell');
  AssertPublished('FocusRectVisible');
  G := NewGrid;
  G.FocusRectVisible := False;
  AssertFalse('one storage, two names', G.ShowFocusCell);
  G.ShowFocusCell := True;
  AssertTrue('and back the other way', G.FocusRectVisible);
end;

procedure TGridDesignerSurfaceTest.TestFadeUnfocusedSelectionAliasesHideSelectionWhenInactive;
var
  G: TTyStringGrid;
begin
  AssertPublished('HideSelectionWhenInactive');
  AssertPublished('FadeUnfocusedSelection');
  G := NewGrid;
  G.FadeUnfocusedSelection := True;
  AssertTrue('one storage, two names', G.HideSelectionWhenInactive);
end;

{ ------------------------------------------------------------------ }
{ TGridColumnMemberTest }

procedure TGridColumnMemberTest.TestColumnVisibleMirrorsTheOptionFlag;
var
  G: TTyStringGrid;
  c: TTyColumn;
begin
  G := NewGrid;
  c := G.Header.Columns.Items[1];
  AssertTrue('columns start visible', c.Visible);
  c.Visible := False;
  AssertFalse('the flag followed', coVisible in c.Options);
  c.Options := c.Options + [coVisible];
  AssertTrue('and the property follows the flag -- one storage, not two',
    c.Visible);
end;

{ Not just a mirror: the setter has to go through SetOptions so the position map
  and the header notification run. Writing FOptions directly would leave the
  hidden column occupying its width. }
procedure TGridColumnMemberTest.TestHidingViaVisibleTakesTheWidthOutOfTheTotal;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  AssertEquals('four columns of 80', 320, G.Header.Columns.TotalWidth);
  G.Header.Columns.Items[1].Visible := False;
  AssertEquals('a hidden column takes no width', 240,
    G.Header.Columns.TotalWidth);
end;

procedure TGridColumnMemberTest.TestMinSizeAndMaxSizeAliasTheWidthBounds;
var
  G: TTyStringGrid;
  c: TTyColumn;
begin
  G := NewGrid;
  c := G.Header.Columns.Items[0];
  c.MinSize := 60;
  AssertEquals('MinSize is MinWidth', 60, c.MinWidth);
  c.MaxSize := 200;
  AssertEquals('MaxSize is MaxWidth', 200, c.MaxWidth);
  c.Width := 10;
  AssertEquals('and the bound still bites', 60, c.Width);
end;

procedure TGridColumnMemberTest.TestItemsIsTypedAndIsTheDefaultArray;
var
  G: TTyStringGrid;
  c: TTyColumn;
begin
  G := NewGrid;
  { Both forms have to compile without a cast -- that is the whole claim. }
  c := G.Header.Columns.Items[2];
  AssertEquals('Items[] is typed', 'C2', c.Text);
  G.Header.Columns[3].Width := 42;
  AssertEquals('and Columns[i] is the default array form', 42, G.ColWidths[3]);
end;

procedure TGridColumnMemberTest.TestAddIsTyped;
var
  G: TTyStringGrid;
  c: TTyColumn;
begin
  G := NewGrid;
  c := G.Header.Columns.Add;
  c.Text := 'added';
  AssertEquals('Add returns a TTyColumn, not a TCollectionItem',
    'added', G.Header.Columns.Items[G.Header.Columns.Count - 1].Text);
  AssertTrue('and the grid still gets ITS column class',
    c is TTyGridColumn);
end;

procedure TGridColumnMemberTest.TestColumnByTitleFindsTheColumn;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  AssertTrue('found', G.Header.Columns.ColumnByTitle('C2') <> nil);
  AssertEquals('the right one', 2, G.Header.Columns.ColumnByTitle('C2').Index);
  AssertEquals('case-insensitive: a caption is display text',
    2, G.Header.Columns.ColumnByTitle('c2').Index);
end;

procedure TGridColumnMemberTest.TestColumnByTitleAnswersNilWhenAbsent;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  AssertTrue('no such caption', G.Header.Columns.ColumnByTitle('nope') = nil);
end;

{ Design-time column colour. Asserted through the painted frame rather than a
  getter, because "the property exists" was never the gap -- OnGetCellStyle
  could already do it at RUNTIME. }
procedure TGridColumnMemberTest.TestColumnColourReachesTheCell;
var
  G: TMemberGridAccess;
  before, after: TBGRABitmap;
  cellR: TRect;
begin
  G := NewAccessGrid;
  G.Header.Options := G.Header.Options - [hoVisible];
  before := nil;
  after := nil;
  try
    before := G.RenderToBitmap;
    (G.Header.Columns.Items[1] as TTyGridColumn).Color := TyRGB(255, 0, 0);
    after := G.RenderToBitmap;
    cellR := Rect(85, 5, 155, 35);
    AssertTrue('column 1 repainted in the column colour: '
      + IntToStr(DiffPixels(before, after, cellR)) + ' px changed',
      DiffPixels(before, after, cellR) > 500);
    AssertEquals('column 0 untouched -- the colour is per COLUMN', 0,
      DiffPixels(before, after, Rect(5, 5, 75, 35)));
  finally
    before.Free;
    after.Free;
  end;
end;

procedure TGridColumnMemberTest.TestColumnLayoutReachesTheCell;
var
  G: TMemberGridAccess;
  before, after: TBGRABitmap;
  cellR: TRect;
begin
  G := NewAccessGrid;
  G.Header.Options := G.Header.Options - [hoVisible];
  G.DefaultRowHeight := 40;
  G.Cells[1, 0] := 'text';
  before := nil;
  after := nil;
  try
    before := G.RenderToBitmap;
    (G.Header.Columns.Items[1] as TTyGridColumn).Layout := tlTop;
    after := G.RenderToBitmap;
    cellR := Rect(81, 0, 160, 40);
    AssertTrue('top-aligning the column moved the glyphs: '
      + IntToStr(DiffPixels(before, after, cellR)) + ' px changed',
      DiffPixels(before, after, cellR) > 20);
  finally
    before.Free;
    after.Free;
  end;
end;

{ ------------------------------------------------------------------ }
{ TGridCheckVocabularyTest }

{ The defect in one assertion: with 'Y'/'N' in the column, one click on the
  checkbox turned the host's 'N' into '1'. }
procedure TGridCheckVocabularyTest.TestTogglingWritesTheColumnsOwnWords;
var
  G: TTyStringGrid;
  c: TTyGridColumn;
begin
  G := NewGrid;
  c := G.Header.Columns.Items[0] as TTyGridColumn;
  c.ValueChecked := 'Y';
  c.ValueUnchecked := 'N';
  G.Cells[0, 0] := 'N';
  G.ToggleCellChecked(0, 0);
  AssertEquals('the grid speaks the column''s vocabulary', 'Y', G.Cells[0, 0]);
end;

procedure TGridCheckVocabularyTest.TestTogglingBackWritesTheUncheckedWord;
var
  G: TTyStringGrid;
  c: TTyGridColumn;
begin
  G := NewGrid;
  c := G.Header.Columns.Items[0] as TTyGridColumn;
  c.ValueChecked := 'Y';
  c.ValueUnchecked := 'N';
  G.Cells[0, 0] := 'Y';
  G.ToggleCellChecked(0, 0);
  AssertEquals('unchecking writes the unchecked WORD, not an empty string',
    'N', G.Cells[0, 0]);
end;

procedure TGridCheckVocabularyTest.TestTheColumnsWordsAreRecognisedOnRead;
var
  G: TTyStringGrid;
  c: TTyGridColumn;
begin
  G := NewGrid;
  c := G.Header.Columns.Items[0] as TTyGridColumn;
  c.ValueChecked := 'oui';
  c.ValueUnchecked := 'non';
  G.Cells[0, 0] := 'oui';
  G.Cells[0, 1] := 'non';
  AssertTrue('a word the built-in table never heard of', G.CellChecked(0, 0));
  AssertFalse('and its opposite', G.CellChecked(0, 1));
end;

{ A vocabulary whose unchecked word is not the empty string used to make the
  notification lie: 'N' <> '' so it reported Checked=True. }
procedure TGridCheckVocabularyTest.NoteCheckChange(Sender: TObject;
  ACol, ARow: Integer; AChecked: Boolean);
begin
  FReportedChecked := AChecked;
end;

procedure TGridCheckVocabularyTest.TestChangeEventReportsTheRealState;
var
  G: TTyStringGrid;
  c: TTyGridColumn;
begin
  G := NewGrid;
  c := G.Header.Columns.Items[0] as TTyGridColumn;
  c.ValueChecked := 'Y';
  c.ValueUnchecked := 'N';
  G.Cells[0, 0] := 'Y';
  FReportedChecked := True;
  G.OnCheckBoxChange := @NoteCheckChange;
  G.ToggleCellChecked(0, 0);
  AssertFalse('unchecking must report unchecked, whatever word it wrote',
    FReportedChecked);
end;

procedure TGridCheckVocabularyTest.TestDefaultVocabularyIsUnchanged;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.Cells[0, 0] := '';
  G.ToggleCellChecked(0, 0);
  AssertEquals('no column vocabulary: still "1"', '1', G.Cells[0, 0]);
  G.ToggleCellChecked(0, 0);
  AssertEquals('and still the empty string', '', G.Cells[0, 0]);
end;

{ ------------------------------------------------------------------ }
{ TGridAutoFillTest }

{ hoAutoResize can only fatten ONE column. This is the multi-column job the
  library already had an algorithm for and no way to reach. }
procedure TGridAutoFillTest.TestFillingSpreadsSpareWidthOverEveryColumn;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.AutoFillColumns := True;
  AssertEquals('every column grew, not just one', 100, G.ColWidths[0]);
  AssertEquals('', 100, G.ColWidths[1]);
  AssertEquals('', 100, G.ColWidths[2]);
  AssertEquals('', 100, G.ColWidths[3]);
  AssertEquals('and together they fill the viewport exactly',
    400, G.Header.Columns.TotalWidth);
end;

procedure TGridAutoFillTest.TestSizePriorityWeightsTheShare;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.Header.Columns.Items[0].SizePriority := 4;
  G.AutoFillColumns := True;
  AssertEquals('4 of 7 shares', 228, G.ColWidths[0]);
  AssertEquals('1 of 7', 57, G.ColWidths[1]);
  AssertEquals('the last one absorbs the rounding so the sum is exact',
    400, G.Header.Columns.TotalWidth);
end;

procedure TGridAutoFillTest.TestZeroPriorityColumnKeepsItsWidth;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.Header.Columns.Items[0].SizePriority := 0;
  G.AutoFillColumns := True;
  AssertEquals('priority 0 means "never auto-size me"', 80, G.ColWidths[0]);
  AssertEquals('the rest still fill the row', 400,
    G.Header.Columns.TotalWidth);
end;

{ Without the redistribution pass a column that hits MaxWidth silently swallows
  the slack it cannot use and the row comes up short.

  TWO columns are clamped on purpose, and the second one only exceeds its own
  maximum AFTER the first one's leftover has been handed round. A single clamp
  round therefore is not enough -- and a one-clamp version of this guard stayed
  GREEN under exactly that mutation, which is why it looks like this now. }
procedure TGridAutoFillTest.TestMaxWidthLeftoverGoesToTheOthers;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.Header.Columns.Items[0].MaxWidth := 60;
  G.Header.Columns.Items[1].MaxWidth := 110;
  G.AutoFillColumns := True;
  AssertEquals('first clamp holds', 60, G.ColWidths[0]);
  AssertEquals('second clamp holds -- 340/3 = 113 is under 110 only once the '
    + 'first leftover has been redistributed', 110, G.ColWidths[1]);
  AssertEquals('the two free columns split what is left, evenly',
    G.ColWidths[2], G.ColWidths[3]);
  AssertEquals('and nothing evaporated', 400, G.Header.Columns.TotalWidth);
end;

{ ------------------------------------------------------------------ }
{ TGridCsvOptionTest }

{ The FIRST column is one of the hidden ones on purpose. Skipping a column in the
  middle leaves the delimiter placement looking right whichever way it is written;
  only a hidden column 0 shows whether the separator follows "have I written a
  column yet" or the raw index. A version of this guard that hid column 1 let a
  leading-comma mutant live. }
procedure TGridCsvOptionTest.TestExportCanSkipHiddenColumns;
var
  G: TTyStringGrid;
  lines: TStringList;
begin
  G := NewGrid;
  G.RowCount := 1;
  G.Cells[0, 0] := 'secret';
  G.Cells[1, 0] := 'b';
  G.Cells[2, 0] := 'alsosecret';
  G.Cells[3, 0] := 'd';
  G.HideColumn(0);
  G.HideColumn(2);
  lines := TStringList.Create;
  try
    lines.Text := G.SaveToCSVText(',', -1, -1, -1, -1, True, True);
    AssertEquals('the title row carries only the visible captions',
      'C1,C3', lines[0]);
    AssertEquals('and the data row lines up with it, with no leading separator',
      'b,d', lines[1]);
  finally
    lines.Free;
  end;
end;

procedure TGridCsvOptionTest.TestExportKeepsHiddenColumnsByDefault;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.RowCount := 1;
  G.Cells[1, 0] := 'secret';
  G.HideColumn(1);
  AssertTrue('default is off -- adding a parameter cannot change existing calls',
    Pos('secret', G.SaveToCSVText) > 0);
end;

procedure TGridCsvOptionTest.TestImportCanSkipBlankLines;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.LoadFromCSVText('A,B'#10'1,2'#10#10'3,4'#10, ',', False, -1, 0, True, True);
  AssertEquals('the blank separator did not import as a phantom row',
    2, G.RowCount);
  AssertEquals('and nothing shifted', '3', G.Cells[0, 1]);
end;

procedure TGridCsvOptionTest.TestImportKeepsBlankLinesByDefault;
var
  G: TTyStringGrid;
begin
  G := NewGrid;
  G.LoadFromCSVText('A,B'#10'1,2'#10#10'3,4'#10);
  AssertEquals('default is off -- the old behaviour is untouched', 3, G.RowCount);
end;

{ ------------------------------------------------------------------ }
{ TGridFilePersistenceTest }

procedure TGridFilePersistenceTest.TestFileRoundTripsTheWholeGrid;
var
  G, H: TTyStringGrid;
  fn: string;
begin
  G := NewGrid;
  G.RowCount := 3;
  G.Cells[0, 0] := 'alpha';
  G.ColWidths[1] := 133;
  fn := GetTempFileName('', 'tygrid');
  try
    G.SaveToFile(fn);
    H := NewGrid;
    H.LoadFromFile(fn);
    AssertEquals('content came back', 'alpha', H.Cells[0, 0]);
    AssertEquals('row count came back', 3, H.RowCount);
    AssertEquals('and so did the layout', 133, H.ColWidths[1]);
  finally
    if FileExists(fn) then DeleteFile(fn);
  end;
end;

{ ------------------------------------------------------------------ }
{ TGridDeadPropertyTest }

procedure TGridDeadPropertyTest.TestHeaderImagesOverridesTheGridsOwnList;
var
  G: TMemberGridAccess;
  own, hdr: TTyVirtualImageList;
begin
  G := NewAccessGrid;
  own := TTyVirtualImageList.Create(FForm);
  hdr := TTyVirtualImageList.Create(FForm);
  G.Images := own;
  AssertSame('with no header list the grid''s own is used', own, G.HeaderImages);
  G.Header.Images := hdr;
  AssertSame('Header.Images is published on the grid -- assigning it has to DO '
    + 'something', hdr, G.HeaderImages);
end;

procedure TGridDeadPropertyTest.TestHeaderImagesFallsBackToTheGridsOwnList;
var
  G: TMemberGridAccess;
  own: TTyVirtualImageList;
begin
  G := NewAccessGrid;
  own := TTyVirtualImageList.Create(FForm);
  G.Images := own;
  G.Header.Images := nil;
  AssertSame('clearing the override falls back, it does not blank the icons',
    own, G.HeaderImages);
end;

{ themes/light.tycss has carried `TyGridHeaderSection:hover` all along; the grid
  never asked for it, so hoHotTrack was a switch wired to nothing. }
procedure TGridDeadPropertyTest.TestHotTrackHighlightsTheHoveredHeaderSection;
var
  G: TMemberGridAccess;
  cold, hot: TBGRABitmap;
  band: TRect;
begin
  G := NewAccessGrid;
  G.Header.Options := G.Header.Options + [hoVisible, hoHotTrack];
  G.Header.Height := 24;
  cold := nil;
  hot := nil;
  try
    cold := G.RenderToBitmap;
    G.Hover(100, 10);                    { inside column 1's header section }
    hot := G.RenderToBitmap;
    band := Rect(81, 1, 159, 23);
    AssertTrue('the hovered section must repaint: '
      + IntToStr(DiffPixels(cold, hot, band)) + ' px changed',
      DiffPixels(cold, hot, band) > 200);
    AssertEquals('and only that section -- hot track is per SECTION', 0,
      DiffPixels(cold, hot, Rect(2, 1, 78, 23)));
  finally
    cold.Free;
    hot.Free;
  end;
end;

procedure TGridDeadPropertyTest.TestWithoutHotTrackTheHeaderDoesNotReact;
var
  G: TMemberGridAccess;
  cold, hot: TBGRABitmap;
begin
  G := NewAccessGrid;
  G.Header.Options := G.Header.Options + [hoVisible] - [hoHotTrack];
  G.Header.Height := 24;
  cold := nil;
  hot := nil;
  try
    cold := G.RenderToBitmap;
    G.Hover(100, 10);
    hot := G.RenderToBitmap;
    AssertEquals('the flag is a real gate, not decoration', 0,
      DiffPixels(cold, hot, Rect(0, 0, 320, 23)));
  finally
    cold.Free;
    hot.Free;
  end;
end;

procedure TGridDeadPropertyTest.TestLeavingTheControlDropsTheHeaderHighlight;
var
  G: TMemberGridAccess;
  cold, back: TBGRABitmap;
begin
  G := NewAccessGrid;
  G.Header.Options := G.Header.Options + [hoVisible, hoHotTrack];
  G.Header.Height := 24;
  cold := nil;
  back := nil;
  try
    cold := G.RenderToBitmap;
    G.Hover(100, 10);
    G.LeaveControl;
    back := G.RenderToBitmap;
    AssertEquals('a highlight left burning after the mouse leaves is the classic '
      + 'hot-track bug', 0, DiffPixels(cold, back, Rect(0, 0, 320, 23)));
  finally
    cold.Free;
    back.Free;
  end;
end;

initialization
  RegisterTest(TGridColumnAxisTest);
  RegisterTest(TGridViewportPositionTest);
  RegisterTest(TGridStructureTest);
  RegisterTest(TGridSelectionApiTest);
  RegisterTest(TGridEditorApiTest);
  RegisterTest(TGridDesignerSurfaceTest);
  RegisterTest(TGridColumnMemberTest);
  RegisterTest(TGridCheckVocabularyTest);
  RegisterTest(TGridAutoFillTest);
  RegisterTest(TGridCsvOptionTest);
  RegisterTest(TGridFilePersistenceTest);
  RegisterTest(TGridDeadPropertyTest);
end.
