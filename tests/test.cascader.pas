unit test.cascader;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, fpcunit, testregistry,
  tyControls.Types,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.Cascader;

type
  { Pure-rules tests: the path rules, the keyboard rules and the geometry take only a plain
    option tree and integers, so they run with no window handle, no theme and no control
    instance at all. The tree is the fixture the whole class shares — see SetUp. }
  TTyCascaderRulesTest = class(TTestCase)
  private
    FRoot: TTyCascaderNodes;
    { '0,1,2' for a path — assertions read as the paths they are about. }
    function PathStr(const APath: TTyCascaderPath): string;
    { A path from a comma-less argument list; -1 means "stop here". }
    function P0: TTyCascaderPath;
    function P1(A: Integer): TTyCascaderPath;
    function P2(A, B: Integer): TTyCascaderPath;
    function P3(A, B, C: Integer): TTyCascaderPath;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { --- paths --- }
    procedure TestNodeAtWalksThePath;
    procedure TestNodeAtRejectsAnImpossibleDepth;
    procedure TestChildrenOfALeafIsNil;
    procedure TestValidPathKeepsAWholePath;
    procedure TestValidPathTruncatesAtAMissingOption;
    procedure TestValidPathTruncatesWhereItWalksIntoALeaf;
    procedure TestValidPathStopsAtADisabledOption;
    procedure TestPathsAreValuesNotAliases;
    { --- columns --- }
    procedure TestColumnNodesPerColumn;
    procedure TestColumnCountGrowsWithThePath;
    procedure TestColumnCountStopsAtALeaf;
    procedure TestColumnCountOfAnEmptyTreeIsZero;
    procedure TestSelectedInColumnIsThePathEntry;
    procedure TestMaxColumnRowsIsTheTallestColumn;
    { --- picking --- }
    procedure TestPickPathTruncatesAndExtends;
    procedure TestRePickingALevelDropsWhatIsToItsRight;
    procedure TestPickPathDegenerateLeavesThePathAlone;
    procedure TestPathIsLeafOnlyForAChildlessNode;
    { --- text --- }
    procedure TestPathTextJoinsWithTheSeparator;
    procedure TestPathTextOfABrokenPathJoinsThePrefix;
    procedure TestPathFromTextRoundTripsPathText;
    procedure TestPathFromTextRejectsAnUnknownSegment;
    procedure TestPathFromTextOfEmptyTextIsTheEmptyPath;
    { --- keyboard --- }
    procedure TestStepIndexEntersFromNowhere;
    procedure TestStepIndexClampsAtTheEnds;
    procedure TestStepIndexStepsOverADisabledOption;
    procedure TestStepPathMovesTheDeepestColumn;
    procedure TestEnterDescendsAndLeaveBacksOut;
    { --- geometry: the field --- }
    procedure TestFieldTextBandStopsAtTheChevron;
    procedure TestFieldDegenerateSizesAreEmpty;
    { --- geometry: the panel --- }
    procedure TestColumnsTileFromTheBandLeft;
    procedure TestLastColumnIsClippedToTheBand;
    procedure TestColumnAtIsTheInverseOfColumnRect;
    procedure TestPanelSizeRoundTrips;
    procedure TestVisibleRowsDropsAPartialRow;
    procedure TestRowRectFollowsTheScroll;
    procedure TestRowAtIsTheInverseOfRowRect;
    procedure TestClampFirstRowKeepsTheColumnFull;
    procedure TestScrollToShowMovesTheLeastItCan;
    procedure TestRowLayoutReservesTheChevronOnABranch;
    procedure TestRowLayoutDropsTheChevronBeforeTheCaption;
  end;

  { Headless control behaviour: the two typeKeys, defaults, the draft/commit split, the
    theme-driven geometry, and graceful degradation when a theme leaves a key undefined.
    No popup window is ever shown — DropDownPanel hands out the live, seeded panel. }
  TTyCascaderControlTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FChanged: Integer;   // OnChange fire count
    FColumns: Integer;   // OnColumnsChanged fire count
    procedure HandleChange(Sender: TObject);
    procedure HandleColumnsChanged(Sender: TObject);
    { A cascader on FForm wired to FCtl, holding the standard fixture tree. }
    function MakeCascader: TTyCascader;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKeys;
    procedure TestDefaults;
    procedure TestTextIsTheJoinedPath;
    procedure TestSeparatorDrivesTheText;
    procedure TestSetPathFiresOnChangeOnceAndReassignIsSilent;
    procedure TestSetPathNormalisesABadPath;
    procedure TestEditingNodesRevalidatesTheSelectionSilently;
    procedure TestSelectByTextSelectsAndRejects;
    procedure TestButtonRectFollowsTheThemeMetric;
    procedure TestTextRectStopsAtTheButton;
    procedure TestHoverNeverGreysTheSelectedRow;
    procedure TestBranchPickExpandsButDoesNotCommit;
    procedure TestLeafPickCommitsAndFiresOnChange;
    procedure TestKeyboardBrowsesWithoutCommitting;
    procedure TestDisabledOptionIsNotPickable;
    procedure TestPanelHitTestIsTheInverseOfItsRects;
    procedure TestColumnWidthMetricRetunesThePanelSize;
    procedure TestRevealingAColumnAsksTheHostToGrowThePopup;
    procedure TestPanelSizeIsCappedByDropDownRows;
    procedure TestFieldRendersTheThemeBackground;
    procedure TestSelectedRowTakesTheSelectedStyle;
    procedure TestUndefinedFieldKeyDrawsNothing;
    procedure TestUndefinedPanelKeyDrawsNothing;
    procedure TestUndefinedItemKeyStillDrawsCaptionsInThePanelInk;
  end;

implementation

{ Build the fixture tree used by both classes:

    0 华东          1 华北          2 海南 (leaf)   3 禁区 (DISABLED)
      0 浙江          0 北京 (leaf)                   0 秘境 (leaf)
        0 杭州
        1 宁波
      1 江苏
        0 南京

  It has, on purpose: a three-level branch, a two-level branch, a leaf at the ROOT (so
  "commit from column 0" is reachable), and a disabled branch (so "no path through an
  option you cannot pick" is testable at every rule). }
procedure BuildFixture(ARoot: TTyCascaderNodes);
var
  east, north, banned, zj, js: TTyCascaderNode;
begin
  east := ARoot.AddNode('华东');
  zj := east.Children.AddNode('浙江');
  zj.Children.AddNode('杭州');
  zj.Children.AddNode('宁波');
  js := east.Children.AddNode('江苏');
  js.Children.AddNode('南京');

  north := ARoot.AddNode('华北');
  north.Children.AddNode('北京');

  ARoot.AddNode('海南');                    // a leaf directly at the root

  banned := ARoot.AddNode('禁区');
  banned.Enabled := False;
  banned.Children.AddNode('秘境');
end;

{ TTyCascaderRulesTest }

procedure TTyCascaderRulesTest.SetUp;
begin
  FRoot := TTyCascaderNodes.Create(nil);   // no owner: a bare data tree, no control in sight
  BuildFixture(FRoot);
end;

procedure TTyCascaderRulesTest.TearDown;
begin
  FRoot.Free;
end;

function TTyCascaderRulesTest.PathStr(const APath: TTyCascaderPath): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(APath) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + IntToStr(APath[i]);
  end;
end;

function TTyCascaderRulesTest.P0: TTyCascaderPath;
begin
  SetLength(Result, 0);
end;

function TTyCascaderRulesTest.P1(A: Integer): TTyCascaderPath;
begin
  SetLength(Result, 1);
  Result[0] := A;
end;

function TTyCascaderRulesTest.P2(A, B: Integer): TTyCascaderPath;
begin
  SetLength(Result, 2);
  Result[0] := A;
  Result[1] := B;
end;

function TTyCascaderRulesTest.P3(A, B, C: Integer): TTyCascaderPath;
begin
  SetLength(Result, 3);
  Result[0] := A;
  Result[1] := B;
  Result[2] := C;
end;

{ --- paths --- }

procedure TTyCascaderRulesTest.TestNodeAtWalksThePath;
begin
  AssertEquals('depth 1', '华东', TyCascaderNodeAt(FRoot, P3(0, 0, 1), 1).Caption);
  AssertEquals('depth 2', '浙江', TyCascaderNodeAt(FRoot, P3(0, 0, 1), 2).Caption);
  AssertEquals('depth 3', '宁波', TyCascaderNodeAt(FRoot, P3(0, 0, 1), 3).Caption);
end;

procedure TTyCascaderRulesTest.TestNodeAtRejectsAnImpossibleDepth;
begin
  // Depth 0 selects the root LIST, which is not a node.
  AssertTrue('depth 0 is not a node', TyCascaderNodeAt(FRoot, P1(0), 0) = nil);
  // Past the path's end is clamped TO its end, not an overrun.
  AssertEquals('depth clamps to the path length', '华东',
    TyCascaderNodeAt(FRoot, P1(0), 9).Caption);
  // An index that is not there selects nothing — it is NOT clamped onto a neighbour.
  AssertTrue('out of range', TyCascaderNodeAt(FRoot, P1(99), 1) = nil);
  AssertTrue('negative', TyCascaderNodeAt(FRoot, P1(-1), 1) = nil);
  AssertTrue('nil root', TyCascaderNodeAt(nil, P1(0), 1) = nil);
end;

procedure TTyCascaderRulesTest.TestChildrenOfALeafIsNil;
var
  leaf: TTyCascaderNode;
begin
  // '海南' is a leaf: nil children, which is what makes it commit-able.
  AssertTrue('a leaf has no column',
    TyCascaderChildrenOf(TyCascaderNodeAt(FRoot, P1(2), 1)) = nil);
  AssertTrue('a branch has one',
    TyCascaderChildrenOf(TyCascaderNodeAt(FRoot, P1(0), 1)) <> nil);
  AssertTrue('nil node', TyCascaderChildrenOf(nil) = nil);
  // An EMPTIED child list must read exactly like a leaf, or a branch whose options were all
  // removed would still claim a column and open an empty one.
  leaf := TyCascaderNodeAt(FRoot, P1(1), 1);
  leaf.Children.Clear;
  AssertTrue('an emptied child list is a leaf too', TyCascaderChildrenOf(leaf) = nil);
end;

procedure TTyCascaderRulesTest.TestValidPathKeepsAWholePath;
begin
  AssertEquals('a true path survives whole', '0,0,1',
    PathStr(TyCascaderValidPath(FRoot, P3(0, 0, 1))));
  AssertEquals('the empty path is valid', '', PathStr(TyCascaderValidPath(FRoot, P0)));
end;

procedure TTyCascaderRulesTest.TestValidPathTruncatesAtAMissingOption;
begin
  // 华东 has only two children (0, 1): the path is cut back to the prefix that is true, and
  // is NOT clamped onto 江苏.
  AssertEquals('cut at the bad entry', '0', PathStr(TyCascaderValidPath(FRoot, P2(0, 7))));
  AssertEquals('a bad first entry leaves nothing', '',
    PathStr(TyCascaderValidPath(FRoot, P2(9, 0))));
end;

procedure TTyCascaderRulesTest.TestValidPathTruncatesWhereItWalksIntoALeaf;
begin
  // 海南 (root 2) is a leaf: there is no level under it to index.
  AssertEquals('cut at the leaf', '2', PathStr(TyCascaderValidPath(FRoot, P2(2, 0))));
end;

procedure TTyCascaderRulesTest.TestValidPathStopsAtADisabledOption;
begin
  // 禁区 (root 3) is disabled: neither it nor anything under it is a place a value can be.
  AssertEquals('the disabled option itself is dropped', '',
    PathStr(TyCascaderValidPath(FRoot, P1(3))));
  AssertEquals('and so is its child', '', PathStr(TyCascaderValidPath(FRoot, P2(3, 0))));
end;

procedure TTyCascaderRulesTest.TestPathsAreValuesNotAliases;
var
  src, cp: TTyCascaderPath;
begin
  // FPC dynamic arrays are reference-counted but NOT copy-on-write, so a bare assignment
  // would alias. Everything that hands a path out must copy it.
  src := P2(0, 1);
  cp := TyCascaderCopyPath(src);
  cp[0] := 9;
  AssertEquals('the source is untouched', '0,1', PathStr(src));
  AssertEquals('the copy moved', '9,1', PathStr(cp));
  // Truncate is a copy too, even when it truncates nothing.
  cp := TyCascaderTruncatePath(src, 2);
  cp[1] := 8;
  AssertEquals('truncate copies as well', '0,1', PathStr(src));
  // ...and it clamps both ways rather than raising.
  AssertEquals('a negative length is the empty path', '', PathStr(TyCascaderTruncatePath(src, -3)));
  AssertEquals('past the end is the whole path', '0,1', PathStr(TyCascaderTruncatePath(src, 9)));
end;

{ --- columns --- }

procedure TTyCascaderRulesTest.TestColumnNodesPerColumn;
var
  lvl: TTyCascaderNodes;
begin
  // Column 0 is always the root list...
  lvl := TyCascaderColumnNodes(FRoot, P2(0, 0), 0);
  AssertTrue('column 0 is the root list', lvl = FRoot);
  // ...column k the children of the node the path selects in column k-1.
  lvl := TyCascaderColumnNodes(FRoot, P2(0, 0), 1);
  AssertEquals('column 1 is 华东''s children', '浙江', lvl[0].Caption);
  lvl := TyCascaderColumnNodes(FRoot, P2(0, 0), 2);
  AssertEquals('column 2 is 浙江''s children', '杭州', lvl[0].Caption);
  // A column the path does not open is not there — that is how a caller learns they ran out.
  AssertTrue('no path entry, no column', TyCascaderColumnNodes(FRoot, P2(0, 0), 3) = nil);
  AssertTrue('negative column', TyCascaderColumnNodes(FRoot, P2(0, 0), -1) = nil);
end;

procedure TTyCascaderRulesTest.TestColumnCountGrowsWithThePath;
begin
  AssertEquals('nothing selected: just the root column', 1,
    TyCascaderColumnCount(FRoot, P0));
  AssertEquals('华东 selected: + its children', 2, TyCascaderColumnCount(FRoot, P1(0)));
  AssertEquals('浙江 too: + its children', 3, TyCascaderColumnCount(FRoot, P2(0, 0)));
  AssertEquals('杭州 is a leaf: no fourth column', 3, TyCascaderColumnCount(FRoot, P3(0, 0, 0)));
end;

procedure TTyCascaderRulesTest.TestColumnCountStopsAtALeaf;
begin
  // 海南 is a leaf at the ROOT: picking it opens no second column at all.
  AssertEquals('a root leaf keeps one column', 1, TyCascaderColumnCount(FRoot, P1(2)));
  // A path that is wrong from entry 1 can only ever reveal FEWER columns, never a broken one.
  AssertEquals('a bad entry stops the count', 1, TyCascaderColumnCount(FRoot, P2(9, 0)));
end;

procedure TTyCascaderRulesTest.TestColumnCountOfAnEmptyTreeIsZero;
var
  bare: TTyCascaderNodes;
begin
  bare := TTyCascaderNodes.Create(nil);
  try
    AssertEquals('no options, no columns', 0, TyCascaderColumnCount(bare, P0));
    AssertEquals('nil root', 0, TyCascaderColumnCount(nil, P0));
  finally
    bare.Free;
  end;
end;

procedure TTyCascaderRulesTest.TestSelectedInColumnIsThePathEntry;
begin
  AssertEquals('column 0', 0, TyCascaderSelectedInColumn(P2(0, 1), 0));
  AssertEquals('column 1', 1, TyCascaderSelectedInColumn(P2(0, 1), 1));
  // The freshly-opened column has nothing selected yet — that is the -1 the panel paints as
  // "no chip here" and the keyboard enters from.
  AssertEquals('column 2 is unselected', -1, TyCascaderSelectedInColumn(P2(0, 1), 2));
  AssertEquals('negative', -1, TyCascaderSelectedInColumn(P2(0, 1), -1));
end;

procedure TTyCascaderRulesTest.TestMaxColumnRowsIsTheTallestColumn;
begin
  // Root has 4 options; 华东's children 2 — so the panel is measured against 4.
  AssertEquals('the root column is tallest', 4, TyCascaderMaxColumnRows(FRoot, P1(0)));
  AssertEquals('same with nothing selected', 4, TyCascaderMaxColumnRows(FRoot, P0));
end;

{ --- picking --- }

procedure TTyCascaderRulesTest.TestPickPathTruncatesAndExtends;
begin
  AssertEquals('pick in column 0 from nothing', '1', PathStr(TyCascaderPickPath(P0, 0, 1)));
  AssertEquals('pick deeper extends', '0,1', PathStr(TyCascaderPickPath(P1(0), 1, 1)));
  AssertEquals('and deeper again', '0,1,0', PathStr(TyCascaderPickPath(P2(0, 1), 2, 0)));
  // A column beyond the path's end cannot be shown, so a pick there is clamped to appending
  // rather than leaving a hole in the middle of the path.
  AssertEquals('a column past the end just appends', '0,3',
    PathStr(TyCascaderPickPath(P1(0), 5, 3)));
end;

procedure TTyCascaderRulesTest.TestRePickingALevelDropsWhatIsToItsRight;
begin
  // Re-picking column 0 makes every deeper level meaningless — you changed the 省, so the
  // 市 you had is not part of an answer any more.
  AssertEquals('a different option at level 0', '1', PathStr(TyCascaderPickPath(P3(0, 0, 1), 0, 1)));
  // ...and re-picking the SAME option still drops them: it is a statement about the levels
  // under it, not a no-op.
  AssertEquals('the same option at level 0', '0', PathStr(TyCascaderPickPath(P3(0, 0, 1), 0, 0)));
  AssertEquals('at level 1', '0,1', PathStr(TyCascaderPickPath(P3(0, 0, 1), 1, 1)));
end;

procedure TTyCascaderRulesTest.TestPickPathDegenerateLeavesThePathAlone;
begin
  AssertEquals('no column', '0,1', PathStr(TyCascaderPickPath(P2(0, 1), -1, 0)));
  AssertEquals('no row', '0,1', PathStr(TyCascaderPickPath(P2(0, 1), 1, -1)));
end;

procedure TTyCascaderRulesTest.TestPathIsLeafOnlyForAChildlessNode;
begin
  AssertTrue('杭州 is a complete selection', TyCascaderPathIsLeaf(FRoot, P3(0, 0, 0)));
  AssertTrue('海南 is one straight from the root', TyCascaderPathIsLeaf(FRoot, P1(2)));
  AssertFalse('华东 is a branch', TyCascaderPathIsLeaf(FRoot, P1(0)));
  AssertFalse('浙江 is a branch', TyCascaderPathIsLeaf(FRoot, P2(0, 0)));
  AssertFalse('the empty path is never a leaf', TyCascaderPathIsLeaf(FRoot, P0));
  AssertFalse('nor is a path that selects nothing', TyCascaderPathIsLeaf(FRoot, P1(99)));
end;

{ --- text --- }

procedure TTyCascaderRulesTest.TestPathTextJoinsWithTheSeparator;
begin
  AssertEquals('three levels', '华东 / 浙江 / 杭州',
    TyCascaderPathText(FRoot, P3(0, 0, 0), ' / '));
  AssertEquals('one level', '海南', TyCascaderPathText(FRoot, P1(2), ' / '));
  AssertEquals('nothing selected', '', TyCascaderPathText(FRoot, P0, ' / '));
  AssertEquals('the joiner is the caller''s', '华东>浙江',
    TyCascaderPathText(FRoot, P2(0, 0), '>'));
end;

procedure TTyCascaderRulesTest.TestPathTextOfABrokenPathJoinsThePrefix;
begin
  // Text is drawn every paint: a path gone wrong must never be the thing that takes the form
  // down, so it joins what it got right.
  AssertEquals('joins the prefix', '华东', TyCascaderPathText(FRoot, P2(0, 9), ' / '));
  AssertEquals('nothing right at all', '', TyCascaderPathText(FRoot, P1(9), ' / '));
end;

procedure TTyCascaderRulesTest.TestPathFromTextRoundTripsPathText;
var
  pth: TTyCascaderPath;
begin
  AssertTrue('resolved', TyCascaderPathFromText(FRoot, '华东 / 浙江 / 杭州', ' / ', pth));
  AssertEquals('back to the same indices', '0,0,0', PathStr(pth));
  // The exact string PathText produced must resolve back — that IS the round trip.
  AssertTrue('a partial path resolves too',
    TyCascaderPathFromText(FRoot, TyCascaderPathText(FRoot, P2(0, 1), ' / '), ' / ', pth));
  AssertEquals('to the same partial path', '0,1', PathStr(pth));
end;

procedure TTyCascaderRulesTest.TestPathFromTextRejectsAnUnknownSegment;
var
  pth: TTyCascaderPath;
begin
  AssertFalse('no such 市', TyCascaderPathFromText(FRoot, '华东 / 苏州', ' / ', pth));
  AssertEquals('and answers with no path at all', '', PathStr(pth));
  AssertFalse('deeper than the tree goes', TyCascaderPathFromText(FRoot, '海南 / 三亚', ' / ', pth));
  AssertFalse('an empty joiner cannot be un-joined',
    TyCascaderPathFromText(FRoot, '华东', '', pth));
end;

procedure TTyCascaderRulesTest.TestPathFromTextOfEmptyTextIsTheEmptyPath;
var
  pth: TTyCascaderPath;
begin
  // '' is a legitimate value — "nothing is selected" — not a failure to resolve.
  AssertTrue('empty text resolves', TyCascaderPathFromText(FRoot, '', ' / ', pth));
  AssertEquals('to the empty path', '', PathStr(pth));
end;

{ --- keyboard --- }

procedure TTyCascaderRulesTest.TestStepIndexEntersFromNowhere;
begin
  // From -1 the step lands on the end it came FROM: down at the top, up at the bottom.
  AssertEquals('down enters at the first', 0, TyCascaderStepIndex(FRoot, -1, 1));
  // The root's LAST option (禁区) is disabled, so "up" enters on the last one it can be on.
  AssertEquals('up enters at the last enabled', 2, TyCascaderStepIndex(FRoot, -1, -1));
  AssertEquals('a nil level has nowhere to go', -1, TyCascaderStepIndex(nil, -1, 1));
end;

procedure TTyCascaderRulesTest.TestStepIndexClampsAtTheEnds;
begin
  AssertEquals('one down', 1, TyCascaderStepIndex(FRoot, 0, 1));
  AssertEquals('one up', 0, TyCascaderStepIndex(FRoot, 1, -1));
  // No wrap: running off an end stops there rather than teleporting across the column.
  AssertEquals('up from the first stays', 0, TyCascaderStepIndex(FRoot, 0, -1));
  AssertEquals('down from the last enabled stays', 2, TyCascaderStepIndex(FRoot, 2, 1));
  // Only the SIGN is read — one option per press, however big the delta.
  AssertEquals('a big delta is still one step', 1, TyCascaderStepIndex(FRoot, 0, 50));
end;

procedure TTyCascaderRulesTest.TestStepIndexStepsOverADisabledOption;
var
  lvl: TTyCascaderNodes;
begin
  // Disable the middle option: a step must pass OVER it, not stop on it.
  lvl := TyCascaderNodeAt(FRoot, P1(0), 1).Children;   // 浙江 / 江苏
  lvl.AddNode('福建');
  lvl[1].Enabled := False;                             // 江苏 off
  AssertEquals('skipped on the way down', 2, TyCascaderStepIndex(lvl, 0, 1));
  AssertEquals('and on the way up', 0, TyCascaderStepIndex(lvl, 2, -1));
  // Every option disabled: there is nowhere to land at all.
  lvl[0].Enabled := False;
  lvl[2].Enabled := False;
  AssertEquals('nothing enabled', -1, TyCascaderStepIndex(lvl, -1, 1));
end;

procedure TTyCascaderRulesTest.TestStepPathMovesTheDeepestColumn;
begin
  // With a BRANCH selected the deepest column is the fresh one: the step enters IT, adding a
  // level, rather than moving the branch.
  AssertEquals('enters the newly-opened column', '0,0',
    PathStr(TyCascaderStepPath(FRoot, P1(0), 1)));
  // With a LEAF selected the deepest column is the leaf's own: the step moves within it.
  AssertEquals('moves within the leaf''s column', '0,0,1',
    PathStr(TyCascaderStepPath(FRoot, P3(0, 0, 0), 1)));
  // From nothing at all: enter the root column.
  AssertEquals('enters the root column', '0', PathStr(TyCascaderStepPath(FRoot, P0, 1)));
  // Clamped: a step that cannot move leaves the path exactly as it was.
  AssertEquals('nowhere to go', '0,0,1', PathStr(TyCascaderStepPath(FRoot, P3(0, 0, 1), 1)));
end;

procedure TTyCascaderRulesTest.TestEnterDescendsAndLeaveBacksOut;
begin
  AssertEquals('enter lands on the first child', '0,0',
    PathStr(TyCascaderEnterPath(FRoot, P1(0))));
  AssertEquals('a leaf has nowhere to descend', '0,0,0',
    PathStr(TyCascaderEnterPath(FRoot, P3(0, 0, 0))));
  AssertEquals('nothing selected: nothing to descend into', '',
    PathStr(TyCascaderEnterPath(FRoot, P0)));
  AssertEquals('leave drops a level', '0,0', PathStr(TyCascaderLeavePath(P3(0, 0, 1))));
  AssertEquals('leave from one level', '', PathStr(TyCascaderLeavePath(P1(0))));
  AssertEquals('leave from nothing stays nothing', '', PathStr(TyCascaderLeavePath(P0)));
end;

{ --- geometry: the field --- }

procedure TTyCascaderRulesTest.TestFieldTextBandStopsAtTheChevron;
var
  L: TTyCascaderFieldLayout;
begin
  // 145 wide, pad 6/4/6/4, an 18px chevron zone.
  L := TyCascaderFieldLayout(145, 26, 6, 4, 6, 4, 18);
  AssertEquals('chevron hugs the right of the FULL rect', 127, L.ButtonRect.Left);
  AssertEquals('and runs to the edge', 145, L.ButtonRect.Right);
  AssertEquals('spanning the full height', 0, L.ButtonRect.Top);
  AssertEquals('', 26, L.ButtonRect.Bottom);
  AssertEquals('text starts at the left padding', 6, L.TextRect.Left);
  // The chevron zone IS the field's right inset (TTyComboBox's rule), so the right padding
  // is deliberately not applied again on top of it.
  AssertEquals('text stops AT the chevron zone', 127, L.TextRect.Right);
  AssertEquals('text band is padded vertically', 4, L.TextRect.Top);
  AssertEquals('', 22, L.TextRect.Bottom);
end;

procedure TTyCascaderRulesTest.TestFieldDegenerateSizesAreEmpty;
var
  L: TTyCascaderFieldLayout;
begin
  L := TyCascaderFieldLayout(0, 26, 6, 4, 6, 4, 18);
  AssertEquals('zero width: no text', 0, L.TextRect.Right - L.TextRect.Left);
  AssertEquals('zero width: no chevron', 0, L.ButtonRect.Right - L.ButtonRect.Left);
  L := TyCascaderFieldLayout(145, 0, 6, 4, 6, 4, 18);
  AssertEquals('zero height: no text', 0, L.TextRect.Right - L.TextRect.Left);
  // A field narrower than its own chevron: the text band collapses rather than inverting.
  L := TyCascaderFieldLayout(16, 26, 6, 4, 6, 4, 18);
  AssertEquals('no room for text', 0, L.TextRect.Right - L.TextRect.Left);
  // Padding taller than the field: same rule vertically.
  L := TyCascaderFieldLayout(145, 4, 6, 4, 6, 4, 18);
  AssertEquals('padding ate the height', 0, L.TextRect.Bottom - L.TextRect.Top);
end;

{ --- geometry: the panel --- }

procedure TTyCascaderRulesTest.TestColumnsTileFromTheBandLeft;
var
  R: TRect;
begin
  // 3 columns x 100 wide, pad 4 all round, panel 308 x 204.
  R := TyCascaderColumnRect(308, 204, 3, 100, 4, 4, 4, 4, 0);
  AssertEquals('column 0 starts at the band left', 4, R.Left);
  AssertEquals('and is exactly one column wide', 104, R.Right);
  AssertEquals('spanning the padded band vertically', 4, R.Top);
  AssertEquals('', 200, R.Bottom);
  R := TyCascaderColumnRect(308, 204, 3, 100, 4, 4, 4, 4, 1);
  AssertEquals('column 1 abuts column 0', 104, R.Left);
  AssertEquals('', 204, R.Right);
  R := TyCascaderColumnRect(308, 204, 3, 100, 4, 4, 4, 4, 2);
  AssertEquals('column 2 abuts column 1', 204, R.Left);
  AssertEquals('and lands exactly on the band right', 304, R.Right);
  // Degenerate requests are empty, never inverted.
  AssertEquals('index out of range', 0,
    TyCascaderColumnRect(308, 204, 3, 100, 4, 4, 4, 4, 3).Right);
  AssertEquals('no columns', 0, TyCascaderColumnRect(308, 204, 0, 100, 4, 4, 4, 4, 0).Right);
  AssertEquals('padding ate the panel', 0,
    TyCascaderColumnRect(8, 204, 3, 100, 40, 4, 40, 4, 0).Right);
end;

procedure TTyCascaderRulesTest.TestLastColumnIsClippedToTheBand;
var
  R: TRect;
begin
  // A panel too narrow for its columns: the overhanging one is clipped to the band, never
  // drawn past the panel's own padding.
  R := TyCascaderColumnRect(160, 204, 3, 100, 4, 4, 4, 4, 1);
  AssertEquals('clipped at the band right', 156, R.Right);
  AssertEquals('but still starts where it should', 104, R.Left);
  // A column entirely past the band is not there at all.
  AssertEquals('wholly off the band', 0,
    TyCascaderColumnRect(160, 204, 3, 100, 4, 4, 4, 4, 2).Right);
end;

procedure TTyCascaderRulesTest.TestColumnAtIsTheInverseOfColumnRect;
var
  i, x, y: Integer;
  R: TRect;
begin
  // Every pixel of every column's own rect must answer that column.
  for i := 0 to 2 do
  begin
    R := TyCascaderColumnRect(308, 204, 3, 100, 4, 4, 4, 4, i);
    for x := R.Left to R.Right - 1 do
    begin
      AssertEquals('top edge of column ' + IntToStr(i), i,
        TyCascaderColumnAt(308, 204, 3, 100, 4, 4, 4, 4, x, R.Top));
      AssertEquals('bottom edge of column ' + IntToStr(i), i,
        TyCascaderColumnAt(308, 204, 3, 100, 4, 4, 4, 4, x, R.Bottom - 1));
    end;
  end;
  // The padding gutter belongs to no column: a click there is inert, it does not pick.
  AssertEquals('left gutter', -1, TyCascaderColumnAt(308, 204, 3, 100, 4, 4, 4, 4, 2, 100));
  AssertEquals('right gutter', -1, TyCascaderColumnAt(308, 204, 3, 100, 4, 4, 4, 4, 306, 100));
  AssertEquals('top gutter', -1, TyCascaderColumnAt(308, 204, 3, 100, 4, 4, 4, 4, 50, 2));
  AssertEquals('outside', -1, TyCascaderColumnAt(308, 204, 3, 100, 4, 4, 4, 4, 999, 100));
  y := 100;
  AssertEquals('no columns at all', -1, TyCascaderColumnAt(308, 204, 0, 100, 4, 4, 4, 4, 50, y));
end;

procedure TTyCascaderRulesTest.TestPanelSizeRoundTrips;
var
  sz: TSize;
  R: TRect;
begin
  // The contract: a panel of TyCascaderPanelSize(...) shows every column at exactly
  // AColumnWidth and exactly AVisibleRows rows.
  sz := TyCascaderPanelSize(3, 100, 8, 24, 4, 4, 4, 4);
  AssertEquals('pad + 3 columns + pad', 308, sz.cx);
  AssertEquals('pad + 8 rows + pad', 200, sz.cy);
  R := TyCascaderColumnRect(sz.cx, sz.cy, 3, 100, 4, 4, 4, 4, 2);
  AssertEquals('the last column is not clipped', 100, R.Right - R.Left);
  AssertEquals('and its band holds exactly 8 rows', 8,
    TyCascaderVisibleRows(R.Bottom - R.Top, 24));
  // Even a degenerate theme must leave the popup somewhere to be.
  sz := TyCascaderPanelSize(0, 0, 0, 0, 0, 0, 0, 0);
  AssertEquals('never a zero-width window', 1, sz.cx);
  AssertEquals('never a zero-height window', 1, sz.cy);
end;

procedure TTyCascaderRulesTest.TestVisibleRowsDropsAPartialRow;
begin
  AssertEquals('an exact fit', 8, TyCascaderVisibleRows(192, 24));
  // 200 / 24 = 8.33 — the 9th row is a sliver, and a sliver is not a row.
  AssertEquals('a partial row does not count', 8, TyCascaderVisibleRows(200, 24));
  AssertEquals('shorter than one row', 0, TyCascaderVisibleRows(10, 24));
  AssertEquals('degenerate row height', 0, TyCascaderVisibleRows(200, 0));
end;

procedure TTyCascaderRulesTest.TestRowRectFollowsTheScroll;
var
  col: TRect;
  R: TRect;
begin
  col := Rect(4, 4, 104, 100);   // a 96px band = 4 whole rows of 24
  R := TyCascaderRowRect(col, 24, 0, 0);
  AssertEquals('row 0 at the band top', 4, R.Top);
  AssertEquals('', 28, R.Bottom);
  AssertEquals('spanning the column', 4, R.Left);
  AssertEquals('', 104, R.Right);
  R := TyCascaderRowRect(col, 24, 0, 3);
  AssertEquals('row 3 is the last whole one', 76, R.Top);
  AssertEquals('', 100, R.Bottom);
  // Row 4 would only half fit: the column just ends.
  AssertEquals('no partial rows', 0, TyCascaderRowRect(col, 24, 0, 4).Bottom);
  // Scrolled: row 2 moves to the top, and row 6 becomes the last whole one.
  R := TyCascaderRowRect(col, 24, 2, 2);
  AssertEquals('the scrolled-to row is at the top', 4, R.Top);
  R := TyCascaderRowRect(col, 24, 2, 5);
  AssertEquals('and the band moved with it', 76, R.Top);
  AssertEquals('a row above the scroll is not drawn', 0, TyCascaderRowRect(col, 24, 2, 1).Bottom);
end;

procedure TTyCascaderRulesTest.TestRowAtIsTheInverseOfRowRect;
var
  col, R: TRect;
  i, y: Integer;
begin
  col := Rect(4, 4, 104, 100);
  // Every pixel of every drawn row answers that row.
  for i := 0 to 3 do
  begin
    R := TyCascaderRowRect(col, 24, 0, i);
    for y := R.Top to R.Bottom - 1 do
      AssertEquals('row ' + IntToStr(i) + ' at y=' + IntToStr(y), i,
        TyCascaderRowAt(col, 24, 0, 10, R.Left, y));
  end;
  // The sliver a partial row WOULD have occupied answers nothing: a click there must not
  // pick an option the user cannot see whole. NOTE this needs a column that actually HAS a
  // sliver: `col` is 96 tall for a 24px row, i.e. EXACTLY 4 whole rows and no remainder, so
  // its last pixel (y=99) legitimately belongs to row 3 — the loop above asserts precisely
  // that. Give the rule a column of 100 instead: 4 whole rows plus a 4px tail.
  AssertEquals('the partial-row sliver', -1,
    TyCascaderRowAt(Rect(4, 4, 104, 104), 24, 0, 10, 50, 102));
  AssertEquals('...while the last WHOLE row of that column still answers', 3,
    TyCascaderRowAt(Rect(4, 4, 104, 104), 24, 0, 10, 50, 99));
  // Past the option count, and outside the column.
  AssertEquals('past the last option', -1, TyCascaderRowAt(col, 24, 0, 2, 50, 60));
  AssertEquals('left of the column', -1, TyCascaderRowAt(col, 24, 0, 10, 2, 10));
  AssertEquals('above the column', -1, TyCascaderRowAt(col, 24, 0, 10, 50, 2));
  // Scrolled: the same y now answers the scrolled row.
  AssertEquals('scrolled by 2', 2, TyCascaderRowAt(col, 24, 2, 10, 50, 10));
end;

procedure TTyCascaderRulesTest.TestClampFirstRowKeepsTheColumnFull;
begin
  // 10 options, 4 visible: the deepest top that still fills the band is 6.
  AssertEquals('clamped to the last full page', 6, TyCascaderClampFirstRow(9, 10, 4));
  AssertEquals('in range is left alone', 3, TyCascaderClampFirstRow(3, 10, 4));
  AssertEquals('never negative', 0, TyCascaderClampFirstRow(-5, 10, 4));
  // A column that fits whole can only ever be at 0.
  AssertEquals('a short column cannot scroll', 0, TyCascaderClampFirstRow(3, 3, 4));
  AssertEquals('an empty column', 0, TyCascaderClampFirstRow(3, 0, 4));
end;

procedure TTyCascaderRulesTest.TestScrollToShowMovesTheLeastItCan;
begin
  // Already visible (rows 2..5 shown): do not move.
  AssertEquals('already in view', 2, TyCascaderScrollToShow(2, 4, 10, 4));
  // Below the band: bring it to the BOTTOM, not the top.
  AssertEquals('below: to the bottom row', 3, TyCascaderScrollToShow(2, 6, 10, 4));
  // Above: bring it to the top.
  AssertEquals('above: to the top row', 1, TyCascaderScrollToShow(2, 1, 10, 4));
  // ...and the result is still clamped.
  AssertEquals('clamped at the end', 6, TyCascaderScrollToShow(0, 9, 10, 4));
  AssertEquals('a column that fits cannot scroll', 0, TyCascaderScrollToShow(0, 2, 3, 4));
end;

procedure TTyCascaderRulesTest.TestRowLayoutReservesTheChevronOnABranch;
var
  L: TTyCascaderRowLayout;
begin
  // A 100-wide, 24-tall row at (4,4), pad 6/6, gap 4, a 12px '>'.
  L := TyCascaderRowLayout(Rect(4, 4, 104, 28), True, 6, 6, 4, 12);
  AssertEquals('the mark hugs the padded right', 98, L.ExpandRect.Right);
  AssertEquals('and is its themed size', 12, L.ExpandRect.Right - L.ExpandRect.Left);
  // Vertically centred in the row: (24-12) div 2 = 6.
  AssertEquals('mark centred in the row', 10, L.ExpandRect.Top);
  AssertEquals('', 22, L.ExpandRect.Bottom);
  AssertEquals('caption starts at the left padding', 10, L.CaptionRect.Left);
  AssertEquals('and stops a gap short of the mark', 82, L.CaptionRect.Right);
  // A LEAF has no mark at all — that absence is what says "this one is an answer".
  L := TyCascaderRowLayout(Rect(4, 4, 104, 28), False, 6, 6, 4, 12);
  AssertEquals('a leaf gets no mark', 0, L.ExpandRect.Right - L.ExpandRect.Left);
  AssertEquals('so its caption takes the whole band', 98, L.CaptionRect.Right);
end;

procedure TTyCascaderRulesTest.TestRowLayoutDropsTheChevronBeforeTheCaption;
var
  L: TTyCascaderRowLayout;
begin
  // A row too narrow for both. Unlike a tag's x (its only affordance, which wins), the '>'
  // is decoration on a row that is clickable end to end — so the WORDS keep the room.
  L := TyCascaderRowLayout(Rect(0, 0, 26, 24), True, 6, 6, 4, 12);
  AssertEquals('the mark is dropped', 0, L.ExpandRect.Right - L.ExpandRect.Left);
  AssertEquals('the caption keeps the whole padded band', 6, L.CaptionRect.Left);
  AssertEquals('', 20, L.CaptionRect.Right);
  // Padding that eats the row leaves both rects empty rather than inverted.
  L := TyCascaderRowLayout(Rect(0, 0, 10, 24), True, 6, 6, 4, 12);
  AssertEquals('no caption', 0, L.CaptionRect.Right - L.CaptionRect.Left);
  AssertEquals('no mark', 0, L.ExpandRect.Right - L.ExpandRect.Left);
  // A zero-area row.
  L := TyCascaderRowLayout(Rect(0, 0, 0, 0), True, 6, 6, 4, 12);
  AssertEquals('degenerate row', 0, L.CaptionRect.Right - L.CaptionRect.Left);
  // A row shorter than its own mark: squash it into the height, never past it.
  L := TyCascaderRowLayout(Rect(0, 0, 100, 8), True, 6, 6, 4, 12);
  AssertEquals('mark floored at the row top', 0, L.ExpandRect.Top);
  AssertEquals('and clamped to the row bottom', 8, L.ExpandRect.Bottom);
end;

{ TTyCascaderControlTest }

type
  { Reaches the protected paint seam of both classes. }
  TCascaderAccess = class(TTyCascader)
  public
    function StyleTypeKey: string;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TPanelAccess = class(TTyCascaderPanel)
  public
    function StyleTypeKey: string;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function CallRowStates(AColumn, AIndex: Integer): TTyStateSet;
    procedure CallSetHover(AColumn, AIndex: Integer);
  end;

function TCascaderAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TCascaderAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

function TPanelAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TPanelAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

function TPanelAccess.CallRowStates(AColumn, AIndex: Integer): TTyStateSet;
begin
  Result := RowStates(AColumn, AIndex);
end;

procedure TPanelAccess.CallSetHover(AColumn, AIndex: Integer);
begin
  SetHover(AColumn, AIndex);
end;

{ A path literal, for the control tests. }
function Pth(const AIndices: array of Integer): TTyCascaderPath;
var
  i: Integer;
begin
  SetLength(Result, Length(AIndices));
  for i := 0 to High(AIndices) do Result[i] := AIndices[i];
end;

function PathText(const APath: TTyCascaderPath): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(APath) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + IntToStr(APath[i]);
  end;
end;

{ The panel a cascader drops, bounded and PPI-pinned for a headless hit-test/paint. It is
  alClient in the popup form, which never gets a handle here, so its bounds must be set by
  hand — the geometry is what is under test, not LCL's alignment. }
function BoundPanel(ACas: TTyCascader; AW, AH: Integer): TTyCascaderPanel;
begin
  Result := ACas.DropDownPanel;
  Result.Align := alNone;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, AW, AH);
end;

procedure TTyCascaderControlTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FChanged := 0;
  FColumns := 0;
end;

procedure TTyCascaderControlTest.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

procedure TTyCascaderControlTest.HandleChange(Sender: TObject);
begin
  Inc(FChanged);
end;

procedure TTyCascaderControlTest.HandleColumnsChanged(Sender: TObject);
begin
  Inc(FColumns);
end;

function TTyCascaderControlTest.MakeCascader: TTyCascader;
begin
  Result := TCascaderAccess.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  BuildFixture(Result.Nodes);
end;

procedure TTyCascaderControlTest.TestTypeKeys;
var
  C: TCascaderAccess;
  P: TPanelAccess;
begin
  C := TCascaderAccess.Create(FForm);
  P := TPanelAccess.Create(FForm);
  try
    C.Parent := FForm;
    P.Parent := FForm;
    AssertEquals('the field''s own key', 'TyCascader', C.StyleTypeKey);
    AssertEquals('the panel''s own key', 'TyCascaderPanel', P.StyleTypeKey);
  finally
    P.Free;
    C.Free;
  end;
end;

procedure TTyCascaderControlTest.TestDefaults;
var
  C: TTyCascader;
begin
  C := TTyCascader.Create(FForm);
  try
    AssertEquals('no options', 0, C.Nodes.Count);
    AssertEquals('nothing selected', 0, C.PathDepth);
    AssertEquals('no text', '', C.Text);
    AssertTrue('no selected node', C.SelectedNode = nil);
    AssertEquals('the Ant Design joiner', ' / ', C.Separator);
    AssertEquals('the combo box''s row count', 8, C.DropDownRows);
    AssertFalse('not dropped', C.DroppedDown);
    // The same drop size as TTyComboBox: the two are meant to sit in one column.
    AssertEquals('default width 145', 145, C.Width);
    AssertEquals('default height 26', 26, C.Height);
  finally
    C.Free;
  end;
end;

procedure TTyCascaderControlTest.TestTextIsTheJoinedPath;
var
  C: TTyCascader;
begin
  C := MakeCascader;
  try
    C.Path := Pth([0, 0, 1]);
    AssertEquals('joined with the separator', '华东 / 浙江 / 宁波', C.Text);
    AssertEquals('and the node is reachable', '宁波', C.SelectedNode.Caption);
    AssertEquals('depth', 3, C.PathDepth);
    C.Clear;
    AssertEquals('cleared', '', C.Text);
    AssertTrue('and nothing is selected', C.SelectedNode = nil);
  finally
    C.Free;
  end;
end;

procedure TTyCascaderControlTest.TestSeparatorDrivesTheText;
var
  C: TTyCascader;
begin
  C := MakeCascader;
  try
    C.Path := Pth([0, 0]);
    C.Separator := ' > ';
    AssertEquals('the joiner is the host''s', '华东 > 浙江', C.Text);
    // SelectByText resolves against the CURRENT separator — the two must stay one rule.
    AssertTrue('and it round-trips through SelectByText', C.SelectByText('华东 > 江苏'));
    AssertEquals('', '0,1', PathText(C.Path));
  finally
    C.Free;
  end;
end;

procedure TTyCascaderControlTest.TestSetPathFiresOnChangeOnceAndReassignIsSilent;
var
  C: TTyCascader;
begin
  C := MakeCascader;
  try
    C.OnChange := @HandleChange;
    C.Path := Pth([0, 0]);
    AssertEquals('one change', 1, FChanged);
    C.Path := Pth([0, 0]);
    AssertEquals('re-assigning the same path is silent', 1, FChanged);
    C.Path := Pth([1]);
    AssertEquals('a real change fires again', 2, FChanged);
    C.Clear;
    AssertEquals('clearing a selection is a change', 3, FChanged);
    C.Clear;
    AssertEquals('clearing nothing is silent', 3, FChanged);
  finally
    C.Free;
  end;
end;

procedure TTyCascaderControlTest.TestSetPathNormalisesABadPath;
var
  C: TTyCascader;
begin
  C := MakeCascader;
  try
    // Not clamped onto a neighbouring option, not raised: cut back to the true prefix.
    C.Path := Pth([0, 9, 0]);
    AssertEquals('cut at the bad entry', '0', PathText(C.Path));
    C.Path := Pth([3, 0]);
    AssertEquals('no path through a disabled option', '', PathText(C.Path));
  finally
    C.Free;
  end;
end;

procedure TTyCascaderControlTest.TestEditingNodesRevalidatesTheSelectionSilently;
var
  C: TTyCascader;
begin
  C := MakeCascader;
  try
    C.Path := Pth([0, 0, 1]);
    C.OnChange := @HandleChange;
    // Editing Nodes is the HOST's own action, not a user selection: the selection is
    // re-validated but OnChange must NOT fire — the host reads Path after its own edit.
    C.Nodes[0].Children[0].Children.Delete(1);   // 宁波 gone
    AssertEquals('stranded selection cut back', '0,0', PathText(C.Path));
    AssertEquals('silently', 0, FChanged);
    // Disabling an option on the path strands it too.
    C.Nodes[0].Enabled := False;
    AssertEquals('no path through it any more', '', PathText(C.Path));
    AssertEquals('still silent', 0, FChanged);
  finally
    C.Free;
  end;
end;

procedure TTyCascaderControlTest.TestSelectByTextSelectsAndRejects;
var
  C: TTyCascader;
begin
  C := MakeCascader;
  try
    AssertTrue('resolved', C.SelectByText('华东 / 浙江 / 杭州'));
    AssertEquals('', '0,0,0', PathText(C.Path));
    // A miss must leave the value the host had — losing it silently would be the worst of
    // both worlds.
    AssertFalse('no such option', C.SelectByText('华东 / 苏州'));
    AssertEquals('the selection is untouched', '0,0,0', PathText(C.Path));
    AssertTrue('empty text clears', C.SelectByText(''));
    AssertEquals('', '', PathText(C.Path));
  finally
    C.Free;
  end;
end;

procedure TTyCascaderControlTest.TestButtonRectFollowsTheThemeMetric;
var
  C: TTyCascader;
  R: TRect;
begin
  // --cascader-button-width is a skin-tunable metric: a theme that sets it moves the
  // geometry (and with it the hit-test), proving the zone is not baked into the control.
  FCtl.LoadThemeCss(
    ':root { --cascader-button-width: 30px; }' +
    'TyCascader { background: #FFFFFF; color: #111111; padding: 4px 6px; }');
  C := MakeCascader;
  try
    C.SetBounds(0, 0, 145, 26);
    R := C.TyCascaderButtonRect;
    AssertEquals('the zone takes the themed width', 30, R.Right - R.Left);
    AssertEquals('and still hugs the right edge', 145, R.Right);
    AssertEquals('spanning the full height', 26, R.Bottom - R.Top);
  finally
    C.Free;
  end;
end;

procedure TTyCascaderControlTest.TestTextRectStopsAtTheButton;
var
  C: TTyCascader;
  R: TRect;
begin
  // The text band is driven by the THEME's padding, not a literal, and ends at the chevron.
  FCtl.LoadThemeCss(
    ':root { --cascader-button-width: 18px; }' +
    'TyCascader { background: #FFFFFF; color: #111111; padding: 5px 7px; }');
  C := MakeCascader;
  try
    C.SetBounds(0, 0, 145, 26);
    R := C.TyCascaderTextRect;
    AssertEquals('left = themed left padding', 7, R.Left);
    AssertEquals('right = the chevron zone', 127, R.Right);
    AssertEquals('top = themed top padding', 5, R.Top);
    AssertEquals('bottom = height - themed bottom padding', 21, R.Bottom);
  finally
    C.Free;
  end;
end;

procedure TTyCascaderControlTest.TestHoverNeverGreysTheSelectedRow;
var
  C: TTyCascader;
  P: TTyCascaderPanel;
  st: TTyStateSet;
begin
  { Real-machine report (third sighting of this family -- TTyListBox and TTyTreeView
    were fixed the same way): pointing at the row that IS the selection turned its
    accent chip into the grey hover fill. The rule everywhere: :selected is the
    resting state and hover never stacks on it; hover styles the OTHER rows. }
  FCtl.LoadThemeCss(
    ':root { --cascader-column-width: 100px; --cascader-row-height: 24px; }' +
    'TyCascaderPanel { background: #FFFFFF; color: #111111; padding: 4px; }' +
    'TyCascaderItem { padding: 0px 6px; }');
  C := MakeCascader;
  try
    P := BoundPanel(C, 308, 200);
    P.PickAt(0, 0);                       // select row 0 of column 0 (the draft path)
    TPanelAccess(P).CallSetHover(0, 0);   // and point at that same row
    st := TPanelAccess(P).CallRowStates(0, 0);
    AssertTrue('the selection holds its resting state', tysSelected in st);
    AssertFalse('hover never stacks on the selected row', tysHover in st);
    TPanelAccess(P).CallSetHover(0, 1);   // a NON-selected row hovers normally
    st := TPanelAccess(P).CallRowStates(0, 1);
    AssertTrue('other rows still hover', tysHover in st);
  finally
    C.Free;
  end;
end;

procedure TTyCascaderControlTest.TestBranchPickExpandsButDoesNotCommit;
var
  C: TTyCascader;
  P: TTyCascaderPanel;
begin
  FCtl.LoadThemeCss(
    ':root { --cascader-column-width: 100px; --cascader-row-height: 24px; }' +
    'TyCascaderPanel { background: #FFFFFF; color: #111111; padding: 4px; }' +
    'TyCascaderItem { padding: 0px 6px; }');
  C := MakeCascader;
  try
    C.OnChange := @HandleChange;
    P := BoundPanel(C, 308, 200);
    // 华东 is a BRANCH: the pick opens its column in the DRAFT and the field's value is
    // untouched — dismissing the popup now must not strand the field on '华东'.
    P.PickAt(0, 0);
    AssertEquals('the draft moved', '0', PathText(P.Path));
    AssertEquals('a second column opened', 2, P.ColumnCount);
    AssertEquals('but the value did not', '', PathText(C.Path));
    AssertEquals('and OnChange never fired', 0, FChanged);
    AssertFalse('a branch is not a complete answer', P.DraftIsLeaf);
  finally
    C.Free;
  end;
end;

procedure TTyCascaderControlTest.TestLeafPickCommitsAndFiresOnChange;
var
  C: TTyCascader;
  P: TTyCascaderPanel;
begin
  FCtl.LoadThemeCss(
    ':root { --cascader-column-width: 100px; --cascader-row-height: 24px; }' +
    'TyCascaderPanel { background: #FFFFFF; color: #111111; padding: 4px; }' +
    'TyCascaderItem { padding: 0px 6px; }');
  C := MakeCascader;
  try
    C.OnChange := @HandleChange;
    P := BoundPanel(C, 308, 200);
    P.PickAt(0, 0);     // 华东  (branch)
    P.PickAt(1, 0);     // 浙江  (branch)
    AssertEquals('still nothing committed', 0, FChanged);
    P.PickAt(2, 1);     // 宁波  (LEAF)
    AssertTrue('the draft is a complete answer', P.DraftIsLeaf);
    AssertEquals('committed', '0,0,1', PathText(C.Path));
    AssertEquals('exactly once', 1, FChanged);
    AssertEquals('and the field reads the whole path', '华东 / 浙江 / 宁波', C.Text);
    // A leaf straight from the root column commits just the same.
    P.PickAt(0, 2);     // 海南
    AssertEquals('a root leaf commits too', '2', PathText(C.Path));
    AssertEquals('', 2, FChanged);
  finally
    C.Free;
  end;
end;

procedure TTyCascaderControlTest.TestDisabledOptionIsNotPickable;
var
  C: TTyCascader;
  P: TTyCascaderPanel;
begin
  FCtl.LoadThemeCss(
    ':root { --cascader-column-width: 100px; --cascader-row-height: 24px; }' +
    'TyCascaderPanel { background: #FFFFFF; color: #111111; padding: 4px; }' +
    'TyCascaderItem { padding: 0px 6px; }');
  C := MakeCascader;
  try
    P := BoundPanel(C, 308, 200);
    P.PickAt(0, 3);   // 禁区, disabled
    AssertEquals('the draft did not move', '', PathText(P.Path));
    AssertEquals('and no column opened', 1, P.ColumnCount);
    // The keyboard steps OVER it rather than stopping on it.
    P.StepDraft(-1);
    AssertEquals('up enters on the last option it can be on', '2', PathText(P.Path));
  finally
    C.Free;
  end;
end;

procedure TTyCascaderControlTest.TestPanelHitTestIsTheInverseOfItsRects;
var
  C: TTyCascader;
  P: TTyCascaderPanel;
  R: TRect;
  col, row: Integer;
begin
  FCtl.LoadThemeCss(
    ':root { --cascader-column-width: 100px; --cascader-row-height: 24px; }' +
    'TyCascaderPanel { background: #FFFFFF; color: #111111; padding: 4px; }' +
    'TyCascaderItem { padding: 0px 6px; }');
  C := MakeCascader;
  try
    C.Path := Pth([0]);
    P := BoundPanel(C, 308, 200);
    // The rect the paint used is the rect the hit-test answers for.
    R := P.TyPanelRowRect(1, 1);   // 江苏, in 华东's column
    AssertTrue('the row has a rect', R.Bottom > R.Top);
    AssertTrue('its centre hits', P.TyPanelHitTest((R.Left + R.Right) div 2,
      (R.Top + R.Bottom) div 2, col, row));
    AssertEquals('the right column', 1, col);
    AssertEquals('the right row', 1, row);
    // Below the last option of a column: inside the column band, but no row there.
    AssertFalse('an empty part of a column hits nothing',
      P.TyPanelHitTest((R.Left + R.Right) div 2, 190, col, row));
    // The panel's padding gutter belongs to no column.
    AssertFalse('the gutter hits nothing', P.TyPanelHitTest(1, 1, col, row));
  finally
    C.Free;
  end;
end;

procedure TTyCascaderControlTest.TestColumnWidthMetricRetunesThePanelSize;
var
  C: TTyCascader;
  P: TTyCascaderPanel;
  sz: TSize;
  R: TRect;
begin
  // Every visual value is the theme's: retuning the metrics must move the panel AND the
  // rects, or the geometry is baked into the control.
  FCtl.LoadThemeCss(
    ':root { --cascader-column-width: 90px; --cascader-row-height: 20px; }' +
    'TyCascaderPanel { background: #FFFFFF; color: #111111; padding: 5px; }' +
    'TyCascaderItem { padding: 0px 6px; }');
  C := MakeCascader;
  try
    C.Path := Pth([0]);          // two columns: root (4 rows) + 华东's children
    P := BoundPanel(C, 400, 300);
    sz := P.TyPanelSize(8, 96);
    // 2 columns x 90 + 5 + 5 = 190; rows capped by the tallest column (4) not DropDownRows.
    AssertEquals('width = pad + 2 themed columns + pad', 190, sz.cx);
    AssertEquals('height = pad + 4 themed rows + pad', 90, sz.cy);
    R := P.TyPanelColumnRect(1);
    AssertEquals('and the column rect took the metric', 90, R.Right - R.Left);
    R := P.TyPanelRowRect(0, 1);
    AssertEquals('and the row rect took the metric', 20, R.Bottom - R.Top);
  finally
    C.Free;
  end;
end;

{ TestRevealingAColumnAsksTheHostToGrowThePopup
  The reported bug: in the antdesign example the region cascader dropped, every root option
  showed its '>' branch marker, and picking one did nothing visible -- the second column
  never appeared.

  Nothing was wrong with the pick: PickAt grew the draft and the panel laid out two columns
  exactly as asked. But the POPUP WINDOW is sized once, in DropDown, for the column count at
  that moment -- one. So column 1 was laid out past the window's right edge, where no pixels
  exist. The panel cannot fix that itself (it does not own the window), so the fix is a
  notification the host resizes on, and this test guards the notification.

  Deliberately not a popup test: asserting on a real dropped window needs a widgetset, and
  the defect is entirely "the host is never told". Fire count + the size the host would
  compute is the whole contract. }
procedure TTyCascaderControlTest.TestRevealingAColumnAsksTheHostToGrowThePopup;
var
  C: TTyCascader;
  P: TTyCascaderPanel;
  wasWide, nowWide: Integer;
begin
  FCtl.LoadThemeCss(
    ':root { --cascader-column-width: 100px; --cascader-row-height: 24px; }' +
    'TyCascaderPanel { background: #FFFFFF; color: #111111; padding: 4px; }' +
    'TyCascaderItem { padding: 0px 6px; }');
  C := MakeCascader;
  try
    P := BoundPanel(C, 308, 200);
    P.OnColumnsChanged := @HandleColumnsChanged;
    FColumns := 0;   // BoundPanel/SyncPanel already seeded the draft
    AssertEquals('one column before anything is picked', 1, P.ColumnCount);
    wasWide := P.TyPanelSize(8, 96).cx;

    P.PickAt(0, 0);                       // a BRANCH: reveals its children in column 1
    AssertEquals('two columns now', 2, P.ColumnCount);
    nowWide := P.TyPanelSize(8, 96).cx;
    AssertEquals('and the panel wants one more column of room',
      wasWide + 100, nowWide);
    AssertEquals('the host was told exactly once', 1, FColumns);

    { It must fire when a column goes AWAY too, or the popup keeps the wider window and
      leaves a dead band beside the last column. }
    P.PickAt(0, 2);                       // a LEAF at the root: back to one column
    AssertEquals('back to one column', 1, P.ColumnCount);
    AssertEquals('and the host was told again', 2, FColumns);

    { Keyboard browsing changes the column count without ever firing OnPick -- it has to
      reach the host through this channel as well, or arrowing into a sub-level would hit
      the very same invisible-column wall the mouse did. }
    P.PickAt(0, 0);        // back onto the branch: 2 columns
    P.EnterDraft;          // Right: descend into column 1 -> a THIRD column
    AssertEquals('a keyboard descent opened a third column', 3, P.ColumnCount);
    AssertEquals('and notified too', 4, FColumns);
  finally
    C.Free;
  end;
end;

procedure TTyCascaderControlTest.TestPanelSizeIsCappedByDropDownRows;
var
  C: TTyCascader;
  P: TTyCascaderPanel;
begin
  FCtl.LoadThemeCss(
    ':root { --cascader-column-width: 100px; --cascader-row-height: 24px; }' +
    'TyCascaderPanel { background: #FFFFFF; color: #111111; padding: 4px; }' +
    'TyCascaderItem { padding: 0px 6px; }');
  C := MakeCascader;
  try
    P := BoundPanel(C, 308, 200);
    // The root column has 4 options; a cap of 2 must win, and a cap of 8 must not inflate
    // the panel to 8 empty rows.
    AssertEquals('capped by DropDownRows', 4 + 2 * 24 + 4, P.TyPanelSize(2, 96).cy);
    AssertEquals('but never padded out past the options', 4 + 4 * 24 + 4,
      P.TyPanelSize(8, 96).cy);
    // The clamp: a popup with no rows would show nothing.
    C.DropDownRows := 0;
    AssertEquals('DropDownRows clamps to 1', 1, C.DropDownRows);
  finally
    C.Free;
  end;
end;

{ TestFieldRendersTheThemeBackground
  Theme: a strongly blue TyCascader fill. Probe the field's centre band and assert it is
  the themed fill — i.e. the field paints from the token, not from an LCL colour. }
procedure TTyCascaderControlTest.TestFieldRendersTheThemeBackground;
var
  C: TCascaderAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
begin
  FCtl.LoadThemeCss(
    'TyCascader { background: #3B82F6; color: #FFFFFF; border-radius: 4px; ' +
    'padding: 4px 6px; font-size: 12px; }');
  Bmp := TBitmap.Create;
  C := TCascaderAccess.Create(FForm);
  try
    C.Parent := FForm;
    C.Controller := FCtl;
    C.Font.PixelsPerInch := 96;
    BuildFixture(C.Nodes);
    C.Path := Pth([2]);
    C.SetBounds(0, 0, 145, 26);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(145, 26);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 145, 26);
    C.RenderTo(Bmp.Canvas, Rect(0, 0, 145, 26), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Well inside the field, clear of the rounded corners and of the glyphs.
      Px := Reread.GetPixel(3, 13);
      AssertTrue('field painted in the themed accent fill',
        (Px.blue > 180) and (Px.red < 120));
    finally
      Reread.Free;
    end;
  finally
    C.Free;
    Bmp.Free;
  end;
end;

{ TestSelectedRowTakesTheSelectedStyle
  TyCascaderItem:selected carries its own fill; the row the path selects must take it and
  its neighbour must not — proving the row state drives the resolve. }
procedure TTyCascaderControlTest.TestSelectedRowTakesTheSelectedStyle;
var
  C: TTyCascader;
  P: TPanelAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  sel, other: TRect;
begin
  FCtl.LoadThemeCss(
    ':root { --cascader-column-width: 100px; --cascader-row-height: 24px; }' +
    'TyCascaderPanel { background: #FFFFFF; color: #FFFFFF; padding: 4px; font-size: 12px; }' +
    'TyCascaderItem { padding: 0px 6px; }' +
    'TyCascaderItem:selected { background: #10B981; }');
  Bmp := TBitmap.Create;
  C := MakeCascader;
  try
    C.Path := Pth([1]);   // 华北 selected in column 0
    P := TPanelAccess(BoundPanel(C, 308, 200));
    sel := P.TyPanelRowRect(0, 1);
    other := P.TyPanelRowRect(0, 0);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(308, 200);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 308, 200);
    P.RenderTo(Bmp.Canvas, Rect(0, 0, 308, 200), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      Px := Reread.GetPixel((sel.Left + sel.Right) div 2, (sel.Top + sel.Bottom) div 2);
      AssertTrue('the selected row took the :selected fill',
        (Px.green > 120) and (Px.green > Px.red + 30) and (Px.green > Px.blue + 30));
      Px := Reread.GetPixel((other.Left + other.Right) div 2, (other.Top + other.Bottom) div 2);
      AssertFalse('its neighbour did not',
        (Px.green > 120) and (Px.green > Px.red + 30) and (Px.green > Px.blue + 30));
    finally
      Reread.Free;
    end;
  finally
    C.Free;
    Bmp.Free;
  end;
end;

{ TestUndefinedFieldKeyDrawsNothing
  The TyCascader rule below is deliberately present-but-backgroundless rather than absent:
  the compiled-in base layer (themes/light.tycss) backs every typeKey a theme omits, so
  "leave the rule out" would silently stop testing degradation the moment the base defines
  TyCascader. Any user rule for a typeKey suppresses the whole base layer for it
  (TTyStyleModel.UserHasTypeKey), so this is how you get a genuinely background-less key. }
procedure TTyCascaderControlTest.TestUndefinedFieldKeyDrawsNothing;
var
  C: TCascaderAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  x, y: Integer;
  dirty: Boolean;
begin
  FCtl.LoadThemeCss('TyCascader { color: #FF0000; }');
  Bmp := TBitmap.Create;
  C := TCascaderAccess.Create(FForm);
  try
    C.Parent := FForm;
    C.Controller := FCtl;
    C.Font.PixelsPerInch := 96;
    BuildFixture(C.Nodes);
    C.Path := Pth([2]);
    C.SetBounds(0, 0, 145, 26);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(145, 26);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 145, 26);
    C.RenderTo(Bmp.Canvas, Rect(0, 0, 145, 26), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // No background => no field at all: not the text, not even the chevron, whose ink the
      // theme DID define. Degrade rather than invent a look.
      dirty := False;
      for y := 0 to 25 do
        for x := 0 to 144 do
        begin
          Px := Reread.GetPixel(x, y);
          if (Px.red > 200) and (Px.green < 100) and (Px.blue < 100) then dirty := True;
        end;
      AssertFalse('nothing of ours was drawn', dirty);
    finally
      Reread.Free;
    end;
  finally
    C.Free;
    Bmp.Free;
  end;
end;

{ TestUndefinedPanelKeyDrawsNothing — the same rule for the popup surface. }
procedure TTyCascaderControlTest.TestUndefinedPanelKeyDrawsNothing;
var
  C: TTyCascader;
  P: TPanelAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  x, y: Integer;
  dirty: Boolean;
begin
  // A background-less TyCascaderPanel, but a fully-defined TyCascaderItem: not one row may
  // be drawn either — no surface, no panel.
  FCtl.LoadThemeCss(
    ':root { --cascader-column-width: 100px; --cascader-row-height: 24px; }' +
    'TyCascaderPanel { color: #FF0000; padding: 4px; }' +
    'TyCascaderItem { background: #FF0000; color: #FF0000; padding: 0px 6px; }');
  Bmp := TBitmap.Create;
  C := MakeCascader;
  try
    P := TPanelAccess(BoundPanel(C, 308, 200));
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(308, 200);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 308, 200);
    P.RenderTo(Bmp.Canvas, Rect(0, 0, 308, 200), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      dirty := False;
      for y := 0 to 199 do
        for x := 0 to 307 do
        begin
          Px := Reread.GetPixel(x, y);
          if (Px.red > 200) and (Px.green < 100) and (Px.blue < 100) then dirty := True;
        end;
      AssertFalse('no panel surface => no rows either', dirty);
    finally
      Reread.Free;
    end;
  finally
    C.Free;
    Bmp.Free;
  end;
end;

{ TestUndefinedItemKeyStillDrawsCaptionsInThePanelInk
  The other half of the degradation contract: a theme that styles only the panel still gets
  legible rows. No item background => no chip; no item colour => the PANEL's ink. Never a
  hard-coded colour. }
procedure TTyCascaderControlTest.TestUndefinedItemKeyStillDrawsCaptionsInThePanelInk;
var
  C: TTyCascader;
  P: TPanelAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  R: TRect;
  x, y: Integer;
  inked: Boolean;
begin
  // A white panel with GREEN ink; TyCascaderItem is declared but carries neither a
  // background nor a colour (so the base layer for it is suppressed and it genuinely has
  // none). Any green in a row can only have come from the PANEL's colour.
  FCtl.LoadThemeCss(
    ':root { --cascader-column-width: 100px; --cascader-row-height: 24px; }' +
    'TyCascaderPanel { background: #FFFFFF; color: #10B981; padding: 4px; font-size: 12px; }' +
    'TyCascaderItem { padding: 0px 6px; }');
  Bmp := TBitmap.Create;
  C := MakeCascader;
  try
    P := TPanelAccess(BoundPanel(C, 308, 200));
    R := P.TyPanelRowRect(0, 0);   // 华东's row

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(308, 200);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 308, 200);
    P.RenderTo(Bmp.Canvas, Rect(0, 0, 308, 200), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      inked := False;
      for y := R.Top to R.Bottom - 1 do
        for x := R.Left to R.Right - 1 do
        begin
          Px := Reread.GetPixel(x, y);
          if (Px.green > 120) and (Px.green > Px.red + 30) and (Px.green > Px.blue + 30) then
            inked := True;
        end;
      // The caption AND the branch's '>' both take that inherited ink; either satisfies
      // this — the point is that SOMETHING drew, in the panel's colour and no other.
      AssertTrue('the row drew in the panel''s inherited ink', inked);
    finally
      Reread.Free;
    end;
  finally
    C.Free;
    Bmp.Free;
  end;
end;

{ Adversarial-review finding (CONFIRMED): the arrow keys used to fire the SAME OnPick a mouse
  pick does, so a single Down/Right committed + closed the popup the instant the draft touched a
  leaf — the user could never arrow to a sibling leaf, and browsing fired OnChange (which the
  design says it must not). Keyboard browsing must move the DRAFT only; commit is Enter or mouse. }
procedure TTyCascaderControlTest.TestKeyboardBrowsesWithoutCommitting;
var
  C: TTyCascader;
  P: TTyCascaderPanel;
begin
  FCtl.LoadThemeCss(
    ':root { --cascader-column-width: 100px; --cascader-row-height: 24px; }' +
    'TyCascaderPanel { background: #FFFFFF; color: #111111; padding: 4px; }' +
    'TyCascaderItem { padding: 0px 6px; }');
  C := MakeCascader;
  try
    C.OnChange := @HandleChange;
    P := BoundPanel(C, 308, 200);
    // Browse into 华东 -> 浙江 -> its first leaf, purely with the keyboard entry points.
    P.StepDraft(1);   // draft -> [0] 华东
    P.EnterDraft;     // draft -> [0,0] 浙江
    P.EnterDraft;     // draft -> [0,0,0] 杭州 (a LEAF)
    AssertTrue('the draft did advance onto a leaf', P.DraftIsLeaf);
    AssertEquals('...but NOTHING is committed while browsing', 0, FChanged);
    AssertEquals('the field''s value is untouched', '', PathText(C.Path));
    // And I can keep browsing to the SIBLING leaf — impossible when a landing auto-committed.
    P.StepDraft(1);   // draft -> [0,0,1] 宁波
    AssertEquals('still browsing, still silent', 0, FChanged);
    AssertEquals('the value is still untouched', '', PathText(C.Path));
    // A mouse leaf-pick, by contrast, DOES commit (the other test proves this) — so the two
    // paths are now distinct: keyboard browses, mouse/Enter commit.
  finally
    C.Free;
  end;
end;

initialization
  RegisterTest(TTyCascaderRulesTest);
  RegisterTest(TTyCascaderControlTest);
end.
