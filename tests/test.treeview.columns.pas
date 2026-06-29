unit test.treeview.columns;
{ Phase A — pure column model tests (A1–A4).
  Phase B — TTyTreeHeader + Header/Columns wired into TTyTreeView.
  A-tests: headless, no TTyTreeView.
  B-tests: use TTyTreeView headlessly (Create(nil), no windowing). }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, LCLType, fpcunit, testregistry,
  tyControls.TreeView.Columns,
  tyControls.TreeView;

type
  { -----------------------------------------------------------------------
    A1: column types + position<->index model
    ----------------------------------------------------------------------- }
  TColumnA1Test = class(TTestCase)
  private
    FCols: TTyTreeColumns;
    FA, FB, FC: TTyTreeColumn;
  protected
    procedure Setup; override;
    procedure TearDown; override;
  published
    { Default Position values after Add are 0,1,2 }
    procedure TestDefaultPositions;
    { ColumnByPosition(1) returns B }
    procedure TestColumnByPosition;
    { Width setter clamps below MinWidth }
    procedure TestWidthClampBelowMin;
    { Width setter clamps above MaxWidth }
    procedure TestWidthClampAboveMax;
    { Width at exactly MinWidth is accepted }
    procedure TestWidthAtMin;
    { Width at exactly MaxWidth is accepted }
    procedure TestWidthAtMax;
    { After deleting B, A.Position=0 C.Position=1 }
    procedure TestDeleteMiddleUpdatesPositions;
    { FPositionToIndex length matches Count after delete }
    procedure TestPositionToIndexConsistentAfterDelete;
    { ColumnByPosition(0) still returns A after delete of B }
    procedure TestColumnByPositionAfterDelete;
    { Default property values }
    procedure TestColumnDefaults;
    { Options default is [coVisible,coResizable,coAllowClick,coDraggable] }
    procedure TestOptionsDefault;
  end;

  { -----------------------------------------------------------------------
    A2: UpdatePositions / TotalWidth / AdjustPosition (reorder)
    ----------------------------------------------------------------------- }
  TColumnA2Test = class(TTestCase)
  private
    FCols: TTyTreeColumns;
    FA, FB, FC: TTyTreeColumn;
  protected
    procedure Setup; override;
    procedure TearDown; override;
  published
    { A=100,B=50,C=80: FLeft = 0,100,150; TotalWidth=230 }
    procedure TestUpdatePositionsThreeColumns;
    { Hiding B: A.FLeft=0, C.FLeft=100, TotalWidth=180 }
    procedure TestHideColumnUpdatesLayout;
    { Re-showing B restores TotalWidth=230 }
    procedure TestShowColumnRestoresLayout;
    { AdjustPosition C->0 gives visual order C,A,B }
    procedure TestAdjustPositionMoveToFront;
    { AdjustPosition A->2 gives visual order B,C,A }
    procedure TestAdjustPositionMoveToBack;
    { AdjustPosition with same pos is a no-op }
    procedure TestAdjustPositionSamePosNoOp;
    { AdjustPosition C->0 recomputes FLeft correctly }
    procedure TestAdjustPositionFLeftAfterReorder;
  end;

  { -----------------------------------------------------------------------
    A3: ColumnFromPosition + DetermineSplitterIndex
    ----------------------------------------------------------------------- }
  TColumnA3Test = class(TTestCase)
  private
    FCols: TTyTreeColumns;
    FA, FB, FC: TTyTreeColumn;
  protected
    procedure Setup; override;
    procedure TearDown; override;
  published
    { X=120, scroll=0 -> B's index (spans 100..149) }
    procedure TestColumnFromPositionInB;
    { X=0, scroll=0 -> A's index }
    procedure TestColumnFromPositionInA;
    { X=229, scroll=0 -> C's index (last pixel) }
    procedure TestColumnFromPositionLastPixelC;
    { X=230, scroll=0 -> NoColumn (past all columns) }
    procedure TestColumnFromPositionPastEnd;
    { X=70, scroll=40 -> B's index (B spans 100-150, shifted left by 40 -> 60-110) }
    procedure TestColumnFromPositionWithScroll;
    { X=300, scroll=0 -> NoColumn }
    procedure TestColumnFromPositionFarRight;
    { X=101, scroll=0 -> A's splitter (right edge 100, tol [97..105]) }
    procedure TestDetermineSplitterIndexA;
    { X=125, scroll=0 -> NoColumn (not near any edge) }
    procedure TestDetermineSplitterIndexNoHit;
    { X=150, scroll=0 -> B's splitter (right edge 150) }
    procedure TestDetermineSplitterIndexB;
    { Reverse iteration: X at exact right of A (=100) -> A, not B }
    procedure TestDetermineSplitterIndexRightEdgeA;
    { Non-resizable column not returned as splitter }
    procedure TestDetermineSplitterIndexNonResizable;
    { Splitter works with scroll offset }
    procedure TestDetermineSplitterIndexWithScroll;
  end;

  { -----------------------------------------------------------------------
    A4: ApplyAutoSize + DistributeSpring
    ----------------------------------------------------------------------- }
  TColumnA4Test = class(TTestCase)
  private
    FCols: TTyTreeColumns;
    FA, FB, FC: TTyTreeColumn;
  protected
    procedure Setup; override;
    procedure TearDown; override;
  published
    { A=100,B=50,C=80, client=300, autosize=B -> B=120, TotalWidth=300 }
    procedure TestApplyAutoSizeBasic;
    { TotalWidth=300 after ApplyAutoSize }
    procedure TestApplyAutoSizeTotalWidth;
    { If needed<MinWidth, clamp to MinWidth }
    procedure TestApplyAutoSizeClampToMin;
    { If needed>MaxWidth, clamp to MaxWidth }
    procedure TestApplyAutoSizeClampToMax;
    { Spring: A,C have coAutoSpring; delta=-30 -> each shrinks by ~15, sum exact }
    procedure TestDistributeSpringNegativeDelta;
    { Spring: A,C have coAutoSpring; delta=+20 -> widths increase, sum exact }
    procedure TestDistributeSpringPositiveDelta;
    { Spring with one column: absorbs full delta }
    procedure TestDistributeSpringOneColumn;
    { Spring with no spring columns: no-op }
    procedure TestDistributeSpringNoSpringColumns;
    { Spring delta=0 is a no-op }
    procedure TestDistributeSpringZeroDelta;
    { Integral: repeated spring calls don't accumulate fractional drift }
    procedure TestDistributeSpringIntegralNoFractionalDrift;
  end;

  { -----------------------------------------------------------------------
    B1: TTyTreeHeader + published Header/Columns wired to TTyTreeView
    ----------------------------------------------------------------------- }
  TColumnB1Test = class(TTestCase)
  private
    FTree: TTyTreeView;
    FHeaderChangedCount: Integer;
  protected
    procedure Setup; override;
    procedure TearDown; override;
  published
    { Tree has a Header property with empty Columns by default }
    procedure TestHeaderExists;
    { Adding 3 columns via Header.Columns.Add gives Count=3 }
    procedure TestAddThreeColumns;
    { Header.MainColumn clamped to Columns.Count-1 when set too high }
    procedure TestMainColumnClamped;
    { Header.MainColumn = NoColumn(-1) when columns are empty }
    procedure TestMainColumnNoColumnWhenEmpty;
    { Mutating a column Width triggers FRangeX to equal TotalWidth }
    procedure TestColumnWidthChangeFiresHeaderChanged;
    { Mutating Header.Height triggers FRangeX to equal TotalWidth }
    procedure TestHeaderHeightChangeFiresHeaderChanged;
    { Header.Options default contains hoVisible, hoColumnResize, etc. }
    procedure TestHeaderOptionsDefault;
    { Header.Height default is 22 }
    procedure TestHeaderHeightDefault;
    { Header.SortColumn default is NoColumn(-1) }
    procedure TestHeaderSortColumnDefault;
  end;

  { -----------------------------------------------------------------------
    B2: ContentRect header inset + FRangeX from column total (0-col == ③a)
    ----------------------------------------------------------------------- }
  TColumnB2Test = class(TTestCase)
  private
    FTree: TTyTreeView;
  protected
    procedure Setup; override;
    procedure TearDown; override;
  published
    { With 0 columns, ContentRect.Top = padding only (③a, no header inset) }
    procedure TestContentRectTopNoPadZeroColumns;
    { Adding columns + hoVisible insets ContentRect.Top by Header.Height }
    procedure TestContentRectTopInsetWithColumns;
    { Removing hoVisible removes the top inset even with columns }
    procedure TestContentRectTopNoInsetWhenNotVisible;
    { FRangeX = TotalWidth when columns exist (driven by column model) }
    procedure TestRangeXEqualsTotalWidthWithColumns;
    { FRangeX = 0 after InvalidateTreeLayout with 0 columns (③a path) }
    procedure TestRangeXZeroWithNoColumns;
    { FRangeX updates when a column Width changes }
    procedure TestRangeXUpdatesOnColumnWidthChange;
  end;

  { -----------------------------------------------------------------------
    B3: MainColumn auto-defaults to the first added column (NoColumn footgun)
    Regression guard: assigning MainColumn before any column exists used to
    silently clamp to NoColumn(-1), leaving the tree with no main column so
    RenderTo never drew tree chrome/images. The first-column add hook now
    restores MainColumn := 0 when it is still NoColumn.
    ----------------------------------------------------------------------- }
  TColumnB3Test = class(TTestCase)
  private
    FHeader: TTyTreeHeader;
  protected
    procedure Setup; override;
    procedure TearDown; override;
  published
    { #1 Auto-default: add 3 columns, never touch MainColumn -> MainColumn=0 }
    procedure TestMainColumnAutoDefaultsToZero;
    { #2 Footgun order now safe: set MainColumn:=0 (clamps to -1) BEFORE any
      column, then add a column -> MainColumn restored to 0 }
    procedure TestMainColumnRestoredAfterPreSetThenAdd;
    { #3 Explicit non-zero respected: auto->0, set :=2, add 4th -> stays 2 }
    procedure TestExplicitNonZeroMainColumnRespectedOnLaterAdd;
    { #4 Opt-out respected: 3 columns (auto->0), set :=NoColumn -> stays -1 }
    procedure TestMainColumnOptOutToNoColumnRespected;
  end;

  { -----------------------------------------------------------------------
    F3: design-time streaming — TTyTreeHeader.Assign deep-copies columns
    ----------------------------------------------------------------------- }
  TColumnF3Test = class(TTestCase)
  published
    { Assign deep-copies 3 columns with their Width/Text into a fresh header }
    procedure TestHeaderAssignDeepCopiesColumns;
    { Assigned columns are independent (changing src does not affect dst) }
    procedure TestHeaderAssignIsDeepNotShallow;
    { RegisterClass registered TTyTreeColumn, TTyTreeColumns, TTyTreeHeader }
    procedure TestRegisterClassForStreaming;
  end;

implementation

{ ===========================================================================
  A1 setup helpers
  =========================================================================== }

procedure TColumnA1Test.Setup;
begin
  FCols := TTyTreeColumns.Create;
  FA := FCols.Add as TTyTreeColumn;  FA.Text := 'A';
  FB := FCols.Add as TTyTreeColumn;  FB.Text := 'B';
  FC := FCols.Add as TTyTreeColumn;  FC.Text := 'C';
  FCols.UpdatePositions;
end;

procedure TColumnA1Test.TearDown;
begin
  FCols.Free;
end;

{ --- A1 tests --- }

procedure TColumnA1Test.TestDefaultPositions;
begin
  AssertEquals('A.Position', 0, Integer(FA.Position));
  AssertEquals('B.Position', 1, Integer(FB.Position));
  AssertEquals('C.Position', 2, Integer(FC.Position));
end;

procedure TColumnA1Test.TestColumnByPosition;
var
  col: TTyTreeColumn;
begin
  col := FCols.ColumnByPosition(1);
  AssertTrue('ColumnByPosition(1) is B', col = FB);
end;

procedure TColumnA1Test.TestWidthClampBelowMin;
begin
  FA.MinWidth := 20;
  FA.Width := 5;    { below MinWidth=20 }
  AssertEquals('Width clamped to MinWidth', 20, FA.Width);
end;

procedure TColumnA1Test.TestWidthClampAboveMax;
begin
  FA.MaxWidth := 200;
  FA.Width := 500;  { above MaxWidth=200 }
  AssertEquals('Width clamped to MaxWidth', 200, FA.Width);
end;

procedure TColumnA1Test.TestWidthAtMin;
begin
  FA.MinWidth := 10;
  FA.Width := 10;
  AssertEquals('Width=MinWidth accepted', 10, FA.Width);
end;

procedure TColumnA1Test.TestWidthAtMax;
begin
  FA.MaxWidth := 1000;
  FA.Width := 1000;
  AssertEquals('Width=MaxWidth accepted', 1000, FA.Width);
end;

procedure TColumnA1Test.TestDeleteMiddleUpdatesPositions;
begin
  FCols.Delete(FB.Index);
  { Now only A and C remain }
  AssertEquals('A.Position still 0', 0, Integer(FA.Position));
  AssertEquals('C.Position now 1', 1, Integer(FC.Position));
end;

procedure TColumnA1Test.TestPositionToIndexConsistentAfterDelete;
begin
  FCols.Delete(FB.Index);
  FCols.UpdatePositions;  { force rebuild }
  AssertEquals('Count=2 after delete', 2, FCols.Count);
  { ColumnByPosition must be able to return both remaining columns }
  AssertTrue('Position 0 is A', FCols.ColumnByPosition(0) = FA);
  AssertTrue('Position 1 is C', FCols.ColumnByPosition(1) = FC);
end;

procedure TColumnA1Test.TestColumnByPositionAfterDelete;
begin
  FCols.Delete(FB.Index);
  AssertTrue('ColumnByPosition(0) = A after delete', FCols.ColumnByPosition(0) = FA);
end;

procedure TColumnA1Test.TestColumnDefaults;
var
  col: TTyTreeColumn;
begin
  { Use a fresh column to check defaults }
  col := FCols.Add as TTyTreeColumn;
  AssertEquals('Default Width', 100, col.Width);
  AssertEquals('Default MinWidth', 10, col.MinWidth);
  AssertEquals('Default MaxWidth', 10000, col.MaxWidth);
  AssertEquals('Default ImageIndex', -1, col.ImageIndex);
  AssertEquals('Default Tag', 0, col.Tag);
  AssertEquals('Default Alignment', Ord(taLeftJustify), Ord(col.Alignment));
  AssertEquals('Default CaptionAlignment', Ord(taLeftJustify), Ord(col.CaptionAlignment));
end;

procedure TColumnA1Test.TestOptionsDefault;
var
  expected: TTyTreeColumnOptions;
begin
  expected := [coVisible, coResizable, coAllowClick, coDraggable];
  AssertTrue('Default Options', FA.Options = expected);
end;

{ ===========================================================================
  A2 setup helpers
  =========================================================================== }

procedure TColumnA2Test.Setup;
begin
  FCols := TTyTreeColumns.Create;
  FA := FCols.Add as TTyTreeColumn;  FA.Text := 'A';  FA.Width := 100;
  FB := FCols.Add as TTyTreeColumn;  FB.Text := 'B';  FB.Width := 50;
  FC := FCols.Add as TTyTreeColumn;  FC.Text := 'C';  FC.Width := 80;
  FCols.UpdatePositions;
end;

procedure TColumnA2Test.TearDown;
begin
  FCols.Free;
end;

{ --- A2 tests --- }

procedure TColumnA2Test.TestUpdatePositionsThreeColumns;
begin
  AssertEquals('A.FLeft = 0',   0,   FA.Left);
  AssertEquals('B.FLeft = 100', 100, FB.Left);
  AssertEquals('C.FLeft = 150', 150, FC.Left);
end;

procedure TColumnA2Test.TestHideColumnUpdatesLayout;
begin
  FB.Options := FB.Options - [coVisible];
  { UpdatePositions is called by SetOptions }
  AssertEquals('A.FLeft = 0 after hide B',   0,   FA.Left);
  AssertEquals('C.FLeft = 100 after hide B', 100, FC.Left);
  AssertEquals('TotalWidth = 180 after hide B', 180, FCols.TotalWidth);
end;

procedure TColumnA2Test.TestShowColumnRestoresLayout;
begin
  FB.Options := FB.Options - [coVisible];
  FB.Options := FB.Options + [coVisible];
  AssertEquals('TotalWidth restored to 230', 230, FCols.TotalWidth);
end;

procedure TColumnA2Test.TestAdjustPositionMoveToFront;
{ AdjustPosition(C, 0) -> visual order C, A, B }
begin
  FCols.AdjustPosition(FC, 0);
  AssertTrue('Position 0 is C', FCols.ColumnByPosition(0) = FC);
  AssertTrue('Position 1 is A', FCols.ColumnByPosition(1) = FA);
  AssertTrue('Position 2 is B', FCols.ColumnByPosition(2) = FB);
end;

procedure TColumnA2Test.TestAdjustPositionMoveToBack;
{ AdjustPosition(A, 2) -> visual order B, C, A }
begin
  FCols.AdjustPosition(FA, 2);
  AssertTrue('Position 0 is B', FCols.ColumnByPosition(0) = FB);
  AssertTrue('Position 1 is C', FCols.ColumnByPosition(1) = FC);
  AssertTrue('Position 2 is A', FCols.ColumnByPosition(2) = FA);
end;

procedure TColumnA2Test.TestAdjustPositionSamePosNoOp;
{ AdjustPosition(A, 0) -> order unchanged }
begin
  FCols.AdjustPosition(FA, 0);
  AssertTrue('Position 0 still A', FCols.ColumnByPosition(0) = FA);
  AssertTrue('Position 1 still B', FCols.ColumnByPosition(1) = FB);
  AssertTrue('Position 2 still C', FCols.ColumnByPosition(2) = FC);
end;

procedure TColumnA2Test.TestAdjustPositionFLeftAfterReorder;
{ After C->0: C.FLeft=0, A.FLeft=80, B.FLeft=180 }
begin
  FCols.AdjustPosition(FC, 0);
  AssertEquals('C.FLeft = 0', 0,   FC.Left);
  AssertEquals('A.FLeft = 80', 80,  FA.Left);
  AssertEquals('B.FLeft = 180', 180, FB.Left);
end;

{ ===========================================================================
  A3 setup helpers (A=100, B=50, C=80, total=230)
  =========================================================================== }

procedure TColumnA3Test.Setup;
begin
  FCols := TTyTreeColumns.Create;
  FA := FCols.Add as TTyTreeColumn;  FA.Text := 'A';  FA.Width := 100;
  FB := FCols.Add as TTyTreeColumn;  FB.Text := 'B';  FB.Width := 50;
  FC := FCols.Add as TTyTreeColumn;  FC.Text := 'C';  FC.Width := 80;
  FCols.UpdatePositions;
  { FLeft: A=0, B=100, C=150 }
end;

procedure TColumnA3Test.TearDown;
begin
  FCols.Free;
end;

{ --- A3 tests --- }

procedure TColumnA3Test.TestColumnFromPositionInB;
{ X=120, scroll=0: B spans [100,150) -> B's index }
begin
  AssertEquals('X=120 -> B index', FB.Index,
    FCols.ColumnFromPosition(120, 0));
end;

procedure TColumnA3Test.TestColumnFromPositionInA;
{ X=0, scroll=0: A spans [0,100) }
begin
  AssertEquals('X=0 -> A index', FA.Index,
    FCols.ColumnFromPosition(0, 0));
end;

procedure TColumnA3Test.TestColumnFromPositionLastPixelC;
{ X=229, scroll=0: C spans [150,230) -> C's index }
begin
  AssertEquals('X=229 -> C index', FC.Index,
    FCols.ColumnFromPosition(229, 0));
end;

procedure TColumnA3Test.TestColumnFromPositionPastEnd;
{ X=230, scroll=0: no column }
begin
  AssertEquals('X=230 -> NoColumn', NoColumn,
    FCols.ColumnFromPosition(230, 0));
end;

procedure TColumnA3Test.TestColumnFromPositionWithScroll;
{ scroll=40: columns shift left by 40
  A spans [-40, 60), B spans [60,110), C spans [110,190)
  X=70 -> B }
begin
  AssertEquals('X=70 scroll=40 -> B index', FB.Index,
    FCols.ColumnFromPosition(70, 40));
end;

procedure TColumnA3Test.TestColumnFromPositionFarRight;
begin
  AssertEquals('X=300 -> NoColumn', NoColumn,
    FCols.ColumnFromPosition(300, 0));
end;

procedure TColumnA3Test.TestDetermineSplitterIndexA;
{ A.right=100; zone=[97,105]; X=101 -> A }
begin
  AssertEquals('X=101 -> A splitter', FA.Index,
    FCols.DetermineSplitterIndex(101, 0));
end;

procedure TColumnA3Test.TestDetermineSplitterIndexNoHit;
{ X=125 not near any edge (A.right=100, B.right=150, C.right=230) }
begin
  AssertEquals('X=125 -> NoColumn', NoColumn,
    FCols.DetermineSplitterIndex(125, 0));
end;

procedure TColumnA3Test.TestDetermineSplitterIndexB;
{ B.right=150; zone=[147,155]; X=150 -> B }
begin
  AssertEquals('X=150 -> B splitter', FB.Index,
    FCols.DetermineSplitterIndex(150, 0));
end;

procedure TColumnA3Test.TestDetermineSplitterIndexRightEdgeA;
{ X=100 is the exact right edge of A; A.zone=[97,105]; returns A (not B) }
begin
  AssertEquals('X=100 -> A splitter (not B)', FA.Index,
    FCols.DetermineSplitterIndex(100, 0));
end;

procedure TColumnA3Test.TestDetermineSplitterIndexNonResizable;
{ Remove coResizable from A; X=100 now hits nothing (only B/C are resizable) }
begin
  FA.Options := FA.Options - [coResizable];
  { B.right=150 zone [147,155], C.right=230 zone [227,235].  X=100 -> NoColumn }
  AssertEquals('X=100 non-resizable A -> NoColumn', NoColumn,
    FCols.DetermineSplitterIndex(100, 0));
end;

procedure TColumnA3Test.TestDetermineSplitterIndexWithScroll;
{ scroll=10: A.right = 100-10=90; zone=[87,95]; X=90 -> A }
begin
  AssertEquals('X=90 scroll=10 -> A splitter', FA.Index,
    FCols.DetermineSplitterIndex(90, 10));
end;

{ ===========================================================================
  A4 setup helpers (A=100, B=50, C=80, total=230)
  =========================================================================== }

procedure TColumnA4Test.Setup;
begin
  FCols := TTyTreeColumns.Create;
  FA := FCols.Add as TTyTreeColumn;  FA.Text := 'A';  FA.Width := 100;
  FB := FCols.Add as TTyTreeColumn;  FB.Text := 'B';  FB.Width := 50;
  FC := FCols.Add as TTyTreeColumn;  FC.Text := 'C';  FC.Width := 80;
  FCols.UpdatePositions;
end;

procedure TColumnA4Test.TearDown;
begin
  FCols.Free;
end;

{ --- A4 tests --- }

procedure TColumnA4Test.TestApplyAutoSizeBasic;
{ A=100,B=50,C=80, client=300, autosize=B(index 1) -> B=120 }
begin
  FCols.ApplyAutoSize(300, FB.Index);
  AssertEquals('B.Width after AutoSize', 120, FB.Width);
end;

procedure TColumnA4Test.TestApplyAutoSizeTotalWidth;
begin
  FCols.ApplyAutoSize(300, FB.Index);
  AssertEquals('TotalWidth=300 after AutoSize', 300, FCols.TotalWidth);
end;

procedure TColumnA4Test.TestApplyAutoSizeClampToMin;
{ client=150 -> needed = 150-100-80 = -30, clamp to MinWidth=10 }
begin
  FB.MinWidth := 10;
  FCols.ApplyAutoSize(150, FB.Index);
  AssertEquals('B clamped to MinWidth', 10, FB.Width);
end;

procedure TColumnA4Test.TestApplyAutoSizeClampToMax;
{ client=50000 -> needed huge, clamp to MaxWidth=10000 }
begin
  FCols.ApplyAutoSize(50000, FB.Index);
  AssertEquals('B clamped to MaxWidth', 10000, FB.Width);
end;

procedure TColumnA4Test.TestDistributeSpringNegativeDelta;
{ A and C have coAutoSpring; delta=-30.
  Proportional: A=100,C=80 total=180.
  A gets: -30*100/180 = -16.67 -> -16 (floor) or -17
  C gets: -30*80/180  = -13.33 -> -13 or -14
  Sum must be exactly -30. }
var
  oldA, oldC, newA, newC, sumDelta: Integer;
begin
  FA.Options := FA.Options + [coAutoSpring];
  FC.Options := FC.Options + [coAutoSpring];
  oldA := FA.Width;
  oldC := FC.Width;
  FCols.DistributeSpring(-30);
  newA := FA.Width;
  newC := FC.Width;
  sumDelta := (newA - oldA) + (newC - oldC);
  AssertEquals('Sum of spring deltas = -30', -30, sumDelta);
  { B must be unchanged }
  AssertEquals('B.Width unchanged', 50, FB.Width);
end;

procedure TColumnA4Test.TestDistributeSpringPositiveDelta;
var
  oldA, oldC, newA, newC, sumDelta: Integer;
begin
  FA.Options := FA.Options + [coAutoSpring];
  FC.Options := FC.Options + [coAutoSpring];
  oldA := FA.Width;
  oldC := FC.Width;
  FCols.DistributeSpring(+20);
  newA := FA.Width;
  newC := FC.Width;
  sumDelta := (newA - oldA) + (newC - oldC);
  AssertEquals('Sum of spring deltas = +20', 20, sumDelta);
end;

procedure TColumnA4Test.TestDistributeSpringOneColumn;
{ Only A has coAutoSpring; delta=-30 -> A absorbs all }
var
  oldA: Integer;
begin
  FA.Options := FA.Options + [coAutoSpring];
  oldA := FA.Width;
  FCols.DistributeSpring(-30);
  AssertEquals('A absorbs all delta', oldA - 30, FA.Width);
  AssertEquals('B unchanged',  50, FB.Width);
  AssertEquals('C unchanged',  80, FC.Width);
end;

procedure TColumnA4Test.TestDistributeSpringNoSpringColumns;
{ No spring columns -> no-op }
begin
  FCols.DistributeSpring(-30);
  AssertEquals('A unchanged', 100, FA.Width);
  AssertEquals('B unchanged',  50, FB.Width);
  AssertEquals('C unchanged',  80, FC.Width);
end;

procedure TColumnA4Test.TestDistributeSpringZeroDelta;
begin
  FA.Options := FA.Options + [coAutoSpring];
  FC.Options := FC.Options + [coAutoSpring];
  FCols.DistributeSpring(0);
  AssertEquals('A unchanged', 100, FA.Width);
  AssertEquals('C unchanged',  80, FC.Width);
end;

procedure TColumnA4Test.TestDistributeSpringIntegralNoFractionalDrift;
{ Apply delta=1 ten times with two spring columns (widths 100, 80 total=180).
  Each call: total must increase by 1 (or 0 if both columns clamp).
  Crucial: no fractional accumulation. }
var
  i, totalBefore, totalAfter: Integer;
begin
  FA.Options := FA.Options + [coAutoSpring];
  FC.Options := FC.Options + [coAutoSpring];
  for i := 1 to 10 do
  begin
    totalBefore := FA.Width + FC.Width;
    FCols.DistributeSpring(1);
    totalAfter := FA.Width + FC.Width;
    { Each call adds exactly 1 pixel to the pair total }
    AssertEquals(
      Format('Iteration %d: pair total increased by 1', [i]),
      totalBefore + 1, totalAfter);
  end;
end;

{ ===========================================================================
  B1 setup helpers
  =========================================================================== }

procedure TColumnB1Test.Setup;
begin
  FTree := TTyTreeView.Create(nil);
  FTree.Font.PixelsPerInch := 96;  { FRangeX is device-px now; pin 96 so it equals logical TotalWidth }
  FHeaderChangedCount := 0;
end;

procedure TColumnB1Test.TearDown;
begin
  FTree.Free;
end;

{ --- B1 tests --- }

procedure TColumnB1Test.TestHeaderExists;
begin
  AssertNotNull('Header is not nil', FTree.Header);
  AssertNotNull('Header.Columns is not nil', FTree.Header.Columns);
end;

procedure TColumnB1Test.TestAddThreeColumns;
begin
  FTree.Header.Columns.Add;
  FTree.Header.Columns.Add;
  FTree.Header.Columns.Add;
  AssertEquals('Header.Columns.Count = 3', 3, FTree.Header.Columns.Count);
end;

procedure TColumnB1Test.TestMainColumnClamped;
begin
  FTree.Header.Columns.Add;
  FTree.Header.Columns.Add;
  FTree.Header.Columns.Add;
  { 3 columns: valid range = [0, 2]; 5 must be clamped to 2 }
  FTree.Header.MainColumn := 5;
  AssertEquals('MainColumn clamped to 2', 2, FTree.Header.MainColumn);
end;

procedure TColumnB1Test.TestMainColumnNoColumnWhenEmpty;
begin
  { No columns: MainColumn must be NoColumn(-1) }
  FTree.Header.MainColumn := 0;   { try to set it — must clamp to NoColumn }
  AssertEquals('MainColumn = NoColumn when no columns', NoColumn, FTree.Header.MainColumn);
end;

procedure TColumnB1Test.TestColumnWidthChangeFiresHeaderChanged;
var
  colA, colB: TTyTreeColumn;
begin
  colA := FTree.Header.Columns.Add as TTyTreeColumn;  colA.Width := 100;
  colB := FTree.Header.Columns.Add as TTyTreeColumn;  colB.Width := 50;
  { After adding columns, FRangeX = TotalWidth (150) }
  AssertEquals('FRangeX = TotalWidth after add', 150, FTree.RangeX);
  { Change colA.Width -> TotalWidth becomes 200 }
  colA.Width := 150;
  AssertEquals('FRangeX updated after column width change', 200, FTree.RangeX);
end;

procedure TColumnB1Test.TestHeaderHeightChangeFiresHeaderChanged;
var
  colA: TTyTreeColumn;
begin
  colA := FTree.Header.Columns.Add as TTyTreeColumn;  colA.Width := 80;
  { Changing Header.Height fires HeaderChanged -> FRangeX still = TotalWidth }
  FTree.Header.Height := 30;
  AssertEquals('FRangeX = TotalWidth after Height change', 80, FTree.RangeX);
end;

procedure TColumnB1Test.TestHeaderOptionsDefault;
var
  defaultOpts: TTyTreeHeaderOptions;
begin
  defaultOpts := [hoVisible, hoColumnResize, hoShowSortGlyphs,
                  hoHeaderClickAutoSort, hoDrag];
  AssertTrue('Header.Options default',
    FTree.Header.Options = defaultOpts);
end;

procedure TColumnB1Test.TestHeaderHeightDefault;
begin
  AssertEquals('Header.Height default = 22', 22, FTree.Header.Height);
end;

procedure TColumnB1Test.TestHeaderSortColumnDefault;
begin
  AssertEquals('Header.SortColumn default = NoColumn', NoColumn, FTree.Header.SortColumn);
end;

{ ===========================================================================
  B2 setup helpers
  =========================================================================== }

procedure TColumnB2Test.Setup;
begin
  FTree := TTyTreeView.Create(nil);
  FTree.Font.PixelsPerInch := 96;  { FRangeX is device-px now; pin 96 so it equals logical TotalWidth }
end;

procedure TColumnB2Test.TearDown;
begin
  FTree.Free;
end;

{ --- B2 tests --- }

procedure TColumnB2Test.TestContentRectTopNoPadZeroColumns;
var
  CR0, CR1: TRect;
  colA: TTyTreeColumn;
begin
  { 0 columns: record the ③a baseline top.
    Then add columns + hoVisible to check the inset is ON TOP of that baseline.
    The key invariant: 0-column ContentRect.Top equals the value with columns
    MINUS the header inset. }
  CR0 := FTree.ContentRect;   { ③a baseline (includes any theme padding) }

  colA := FTree.Header.Columns.Add as TTyTreeColumn;
  colA.Width := 100;
  AssertTrue('hoVisible active', hoVisible in FTree.Header.Options);
  CR1 := FTree.ContentRect;   { with columns + hoVisible }

  { With columns, the top must be larger than the 0-column top. }
  AssertTrue('ContentRect.Top inset is greater with columns',
    CR1.Top > CR0.Top);

  { Remove columns and verify we return to the ③a baseline. }
  FTree.Header.Columns.Delete(colA.Index);
  AssertEquals('ContentRect.Top restored to ③a baseline after removing columns',
    CR0.Top, FTree.ContentRect.Top);
end;

procedure TColumnB2Test.TestContentRectTopInsetWithColumns;
var
  CRBase, CRWithCols: TRect;
  PPI, headerInset: Integer;
begin
  { Record ③a baseline first (0 columns). }
  CRBase := FTree.ContentRect;

  FTree.Header.Columns.Add;
  FTree.Header.Columns.Add;
  AssertTrue('hoVisible in Options', hoVisible in FTree.Header.Options);

  CRWithCols := FTree.ContentRect;
  PPI        := FTree.Font.PixelsPerInch;
  headerInset := MulDiv(FTree.Header.Height, PPI, 96);

  AssertEquals('ContentRect.Top = baseline + Header.Height device-px',
    CRBase.Top + headerInset, CRWithCols.Top);
end;

procedure TColumnB2Test.TestContentRectTopNoInsetWhenNotVisible;
var
  CRBase, CRNoVis: TRect;
begin
  { Capture ③a baseline (0 columns). }
  CRBase := FTree.ContentRect;

  FTree.Header.Columns.Add;
  FTree.Header.Columns.Add;
  { Remove hoVisible — should produce no top inset }
  FTree.Header.Options := FTree.Header.Options - [hoVisible];
  CRNoVis := FTree.ContentRect;

  AssertEquals('ContentRect.Top = ③a baseline when hoVisible removed',
    CRBase.Top, CRNoVis.Top);
end;

procedure TColumnB2Test.TestRangeXEqualsTotalWidthWithColumns;
var
  colA, colB: TTyTreeColumn;
begin
  colA := FTree.Header.Columns.Add as TTyTreeColumn;  colA.Width := 100;
  colB := FTree.Header.Columns.Add as TTyTreeColumn;  colB.Width := 80;
  AssertEquals('FRangeX = TotalWidth = 180',
    FTree.Header.Columns.TotalWidth, FTree.RangeX);
end;

procedure TColumnB2Test.TestRangeXZeroWithNoColumns;
begin
  { 0 columns: InvalidateTreeLayout resets FRangeX to 0 (③a path) }
  FTree.RootNodeCount := 3;
  { RootNodeCount setter calls InvalidateTreeLayout implicitly }
  AssertEquals('FRangeX = 0 with no columns', 0, FTree.RangeX);
end;

procedure TColumnB2Test.TestRangeXUpdatesOnColumnWidthChange;
var
  colA: TTyTreeColumn;
begin
  colA := FTree.Header.Columns.Add as TTyTreeColumn;
  colA.Width := 100;
  AssertEquals('RangeX = 100 initially', 100, FTree.RangeX);
  colA.Width := 200;
  AssertEquals('RangeX = 200 after Width change', 200, FTree.RangeX);
end;

{ ===========================================================================
  B3: MainColumn auto-default / footgun-guard tests
  =========================================================================== }

procedure TColumnB3Test.Setup;
begin
  FHeader := TTyTreeHeader.Create;
end;

procedure TColumnB3Test.TearDown;
begin
  FHeader.Free;
end;

procedure TColumnB3Test.TestMainColumnAutoDefaultsToZero;
{ #1: add 3 columns, never touch MainColumn -> MainColumn = 0 }
begin
  FHeader.Columns.Add;
  FHeader.Columns.Add;
  FHeader.Columns.Add;
  AssertEquals('MainColumn auto-defaults to first column', 0, FHeader.MainColumn);
end;

procedure TColumnB3Test.TestMainColumnRestoredAfterPreSetThenAdd;
{ #2: the footgun order — set MainColumn:=0 with no columns (clamps to
  NoColumn), THEN add a column. The first-column hook must restore it to 0. }
begin
  FHeader.MainColumn := 0;   { no columns yet -> setter clamps to NoColumn }
  AssertEquals('precondition: MainColumn clamped to NoColumn pre-add',
    NoColumn, FHeader.MainColumn);
  FHeader.Columns.Add;       { first add -> hook restores MainColumn := 0 }
  AssertEquals('MainColumn restored to 0 by first-column add', 0, FHeader.MainColumn);
end;

procedure TColumnB3Test.TestExplicitNonZeroMainColumnRespectedOnLaterAdd;
{ #3: add 3 columns (auto -> 0), set MainColumn := 2, then add a 4th column.
  The hook only fires for the FIRST column (Count=1), so a later add must NOT
  reset the app's explicit choice. }
begin
  FHeader.Columns.Add;
  FHeader.Columns.Add;
  FHeader.Columns.Add;
  AssertEquals('precondition: auto-default 0', 0, FHeader.MainColumn);
  FHeader.MainColumn := 2;
  AssertEquals('explicit MainColumn = 2', 2, FHeader.MainColumn);
  FHeader.Columns.Add;       { Count now 4 -> hook does not fire }
  AssertEquals('MainColumn stays 2 after a later add', 2, FHeader.MainColumn);
end;

procedure TColumnB3Test.TestMainColumnOptOutToNoColumnRespected;
{ #4: add 3 columns (auto -> 0), then opt out with MainColumn := NoColumn.
  With no further adds the hook never re-fires, so the -1 must stick. }
begin
  FHeader.Columns.Add;
  FHeader.Columns.Add;
  FHeader.Columns.Add;
  AssertEquals('precondition: auto-default 0', 0, FHeader.MainColumn);
  FHeader.MainColumn := NoColumn;
  AssertEquals('opt-out MainColumn = NoColumn is respected',
    NoColumn, FHeader.MainColumn);
end;

{ ===========================================================================
  F3: TTyTreeHeader.Assign deep-copy tests
  =========================================================================== }

procedure TColumnF3Test.TestHeaderAssignDeepCopiesColumns;
var
  src, dst: TTyTreeHeader;
  colA, colB, colC: TTyTreeColumn;
begin
  src := TTyTreeHeader.Create;
  dst := TTyTreeHeader.Create;
  try
    colA := src.Columns.Add as TTyTreeColumn;  colA.Width := 120;  colA.Text := 'Name';
    colB := src.Columns.Add as TTyTreeColumn;  colB.Width := 80;   colB.Text := 'Size';
    colC := src.Columns.Add as TTyTreeColumn;  colC.Width := 100;  colC.Text := 'Modified';

    dst.Assign(src);

    AssertEquals('Assign: Columns.Count = 3', 3, dst.Columns.Count);
    AssertEquals('Assign: col0.Width = 120', 120, (dst.Columns.Items[0] as TTyTreeColumn).Width);
    AssertEquals('Assign: col0.Text = Name', 'Name', (dst.Columns.Items[0] as TTyTreeColumn).Text);
    AssertEquals('Assign: col1.Width = 80', 80, (dst.Columns.Items[1] as TTyTreeColumn).Width);
    AssertEquals('Assign: col1.Text = Size', 'Size', (dst.Columns.Items[1] as TTyTreeColumn).Text);
    AssertEquals('Assign: col2.Width = 100', 100, (dst.Columns.Items[2] as TTyTreeColumn).Width);
    AssertEquals('Assign: col2.Text = Modified', 'Modified', (dst.Columns.Items[2] as TTyTreeColumn).Text);
  finally
    src.Free;
    dst.Free;
  end;
end;

procedure TColumnF3Test.TestHeaderAssignIsDeepNotShallow;
var
  src, dst: TTyTreeHeader;
  colA: TTyTreeColumn;
begin
  src := TTyTreeHeader.Create;
  dst := TTyTreeHeader.Create;
  try
    colA := src.Columns.Add as TTyTreeColumn;  colA.Width := 200;  colA.Text := 'Alpha';

    dst.Assign(src);

    { Mutate src column after assign — dst must not be affected }
    (src.Columns.Items[0] as TTyTreeColumn).Width := 999;
    (src.Columns.Items[0] as TTyTreeColumn).Text  := 'Changed';

    AssertEquals('Deep copy: dst Width unchanged', 200, (dst.Columns.Items[0] as TTyTreeColumn).Width);
    AssertEquals('Deep copy: dst Text unchanged', 'Alpha', (dst.Columns.Items[0] as TTyTreeColumn).Text);
  finally
    src.Free;
    dst.Free;
  end;
end;

procedure TColumnF3Test.TestRegisterClassForStreaming;
begin
  { RegisterClass was called in initialization of tyControls.TreeView.Columns.
    FindClass raises EClassNotFound if the class was not registered.
    These are the three classes needed for LFM round-trip of Header/Columns. }
  AssertNotNull('TTyTreeColumn registered', FindClass('TTyTreeColumn'));
  AssertNotNull('TTyTreeColumns registered', FindClass('TTyTreeColumns'));
  AssertNotNull('TTyTreeHeader registered', FindClass('TTyTreeHeader'));
end;

initialization
  RegisterTest(TColumnA1Test);
  RegisterTest(TColumnA2Test);
  RegisterTest(TColumnA3Test);
  RegisterTest(TColumnA4Test);
  RegisterTest(TColumnB1Test);
  RegisterTest(TColumnB2Test);
  RegisterTest(TColumnB3Test);
  RegisterTest(TColumnF3Test);
end.
