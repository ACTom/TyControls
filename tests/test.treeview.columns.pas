unit test.treeview.columns;
{ Phase A — pure column model tests (A1–A4).
  All tests are headless: no TTyTreeView, no windowing, no paint.
  A bare TTyTreeColumns.Create is sufficient. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.TreeView.Columns;

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

initialization
  RegisterTest(TColumnA1Test);
  RegisterTest(TColumnA2Test);
  RegisterTest(TColumnA3Test);
  RegisterTest(TColumnA4Test);
end.
