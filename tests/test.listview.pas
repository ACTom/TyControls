unit test.listview;
{ Headless state-machine tests for TTyListView, written FROM THE CONTRACT
  (docs/superpowers/plans/2026-07-10-listview-sp1.md, "任务 2 契约") and NOT from
  the implementation. No windowing: controls are Create(nil), never parented to a
  shown form, never painted, no Handle touched. Everything asserted here is the
  control's data / sort / selection / virtual-staleness state machine.

  The four data accessors (GetItemCount/GetItemText/GetItemImageIndex/GetItemState)
  are protected; they are reached through a TTyListViewAccess subclass declared in
  this unit, exactly as the rest of the repo reaches protected members. The same
  subclass exposes OrderAt(), which calls the protected DisplayToItem seam: the public
  API deliberately hides display order, so the sort's permutation can only be observed
  from a descendant — which is also how TTyShellListView will read it. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Types, LCLType, Controls, fpcunit, testregistry,
  tyControls.Columns,          { TTySortDirection, sdAscending, sdDescending }
  tyControls.ListView.Layout,  { TTyListViewStyle, TTyListSortKind }
  tyControls.ScrollBar,        { TTyScrollBar (the embedded bars) }
  tyControls.Edit,             { TTyEdit (the inline rename editor) }
  tyControls.ListView;         { TTyListView + item / state types + events }

type
  { Reaches the protected data accessors and the internal display order. }
  TTyListViewAccess = class(TTyListView)
  public
    function XGetItemCount: Integer;
    function XGetItemText(AIndex, AColumn: Integer): string;
    function XGetItemImageIndex(AIndex, AColumn: Integer): Integer;
    function XGetItemState(AIndex: Integer): TTyListItemStates;
    { Display position -> stable item index. Goes through the control's protected
      DisplayToItem seam rather than reaching into FOrder: the arrays stay private (a
      descendant has no business reshuffling the display order) and this is the same
      seam TTyShellListView will read. }
    function OrderAt(ADisplayPos: Integer): Integer;
    { Type-ahead is driven through the protected UTF8KeyPress. }
    procedure XType(const AKey: string);
    { The scrollbars and the layout pass that configures them. }
    procedure XUpdateScrollBars;
    function XVBar: TTyScrollBar;
    function XHBar: TTyScrollBar;
    function XContentHeight: Integer;
    { Mouse hover, for the header-divider cursor. }
    procedure XMouseMove(X, Y: Integer);
    { A left press, optionally the second click of a double-click. }
    procedure XMouseDown(X, Y: Integer; ADouble: Boolean = False);
    procedure XDblClick;
    { A key press, for the F2 / Space / Ctrl+Space wiring. }
    procedure XKeyDown(AKey: Word; AShift: TShiftState = []);
    { The inline rename editor (protected InlineEditor seam), so a headless test can
      set the text that EndEdit(True) will commit. }
    function XEditor: TTyEdit;
  end;

  { -----------------------------------------------------------------------
    DATA ACCESS — collection mode + OwnerData fan-out through the four accessors
    ----------------------------------------------------------------------- }
  TListViewDataTest = class(TTestCase)
  private
    FLV: TTyListViewAccess;
    procedure HGetText(Sender: TObject; AIndex, AColumn: Integer; var AText: string);
    procedure HGetImage(Sender: TObject; AIndex, AColumn: Integer; var AImageIndex: Integer);
    procedure HGetState(Sender: TObject; AIndex: Integer; var AStates: TTyListItemStates);
    procedure AddRow(const ACaption, ASub1, ASub2: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { Collection: column 0 is Caption }
    procedure TestCollectionColumn0IsCaption;
    { Collection: column N>0 is SubItems[N-1] }
    procedure TestCollectionColumnNIsSubItem;
    { Collection: an out-of-range column returns '' }
    procedure TestCollectionOutOfRangeColumnEmpty;
    { Collection: GetItemCount tracks Items.Count }
    procedure TestCollectionItemCountTracksItems;
    { OwnerData: GetItemCount is the published ItemCount }
    procedure TestOwnerDataItemCount;
    { OwnerData: OnGetItemText fans out with the right (index, column) }
    procedure TestOwnerDataTextFanOut;
    { OwnerData: OnGetItemImage fans out with the right (index, column) }
    procedure TestOwnerDataImageFanOut;
    { OwnerData: OnGetItemState fans out with the right index }
    procedure TestOwnerDataStateFanOut;
    { OwnerData with NO handlers: '' / -1 / [] rather than a crash }
    procedure TestOwnerDataNoHandlerDefaults;
    { Toggling OwnerData does not corrupt the state arrays / does not crash }
    procedure TestSwitchingOwnerDataKeepsArraysSane;
  end;

  { -----------------------------------------------------------------------
    SORT — FOrder permutation, Items untouched, stability, direction, OnCompare,
    and the headline: selection survives a re-sort and a view-style switch
    ----------------------------------------------------------------------- }
  TListViewSortTest = class(TTestCase)
  private
    FLV: TTyListViewAccess;
    FCompareCalls: Integer;
    FCompareBadCol: Boolean;
    FCompareBadIdx: Boolean;
    procedure HCompareByIndexDesc(Sender: TObject; AIndex1, AIndex2, AColumn: Integer;
      var ACompare: Integer);
    procedure PopulateCaptions(const ACaps: array of string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { SortColumn = -1 restores the identity display order }
    procedure TestSortColumnMinusOneRestoresIdentity;
    { A sort permutes display order but leaves Items[k].Caption untouched }
    procedure TestSortLeavesItemsUntouched;
    { Equal captions keep their relative item order (ties broken by item index) }
    procedure TestSortIsStableOnTies;
    { sdDescending reverses comparable values }
    procedure TestSortDescendingReversesOrder;
    { OnCompare wins over the built-in comparator and gets ITEM indices + SortColumn }
    procedure TestOnCompareWinsAndGetsItemIndices;
    { THE key test: selection + ItemIndex survive a re-sort in both directions }
    procedure TestSelectionSurvivesReSort;
    { Selection + ItemIndex survive a ViewStyle switch }
    procedure TestSelectionSurvivesViewStyleSwitch;
  end;

  { -----------------------------------------------------------------------
    SELECTION — multiselect collapse, SelectAll/ClearSelection/SelCount,
    GetNextSelected walk, out-of-range safety
    ----------------------------------------------------------------------- }
  TListViewSelectionTest = class(TTestCase)
  private
    FLV: TTyListViewAccess;
    procedure Populate(ACount: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { MultiSelect := False collapses the selection to ItemIndex alone }
    procedure TestMultiSelectFalseCollapsesToItemIndex;
    procedure TestCollapseWithNoFocusAdoptsFirstSelected;
    procedure TestCollapseWithNothingSelectedStaysEmpty;
    procedure TestItemIndexIsFocusSelects;
    { SelectAll selects every item }
    procedure TestSelectAll;
    { ClearSelection empties the selection }
    procedure TestClearSelection;
    { SelCount reflects the number of set bits }
    procedure TestSelCount;
    { GetNextSelected(var i) from -1 walks every selected item index ascending }
    procedure TestGetNextSelectedWalk;
    { Selected[] with an out-of-range index neither crashes nor changes SelCount }
    procedure TestSelectedOutOfRangeIsSafe;
  end;

  { -----------------------------------------------------------------------
    VIRTUAL-MODE STALENESS — shrink/grow ItemCount + ItemsChanged clamping
    ----------------------------------------------------------------------- }
  TListViewVirtualTest = class(TTestCase)
  private
    FLV: TTyListViewAccess;
    procedure SetVirtual(ACount: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { Shrinking ItemCount + ItemsChanged clamps ItemIndex and drops stale selection }
    procedure TestShrinkClampsIndexAndSelection;
    { A surviving in-range selection is still counted after a shrink }
    procedure TestShrinkKeepsSurvivingSelection;
    { Growing ItemCount + ItemsChanged leaves the new items unselected }
    procedure TestGrowLeavesNewItemsUnselected;
    { ItemIndex assigned out of range is clamped, never raises }
    procedure TestItemIndexAssignedOutOfRangeIsClamped;
  end;

  { -----------------------------------------------------------------------
    SCROLLBARS — Max is the maximum POSITION, not the content size
    ----------------------------------------------------------------------- }
  TListViewScrollTest = class(TTestCase)
  private
    FLV: TTyListViewAccess;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestVerticalMaxIsContentMinusOnePage;
    procedure TestThumbReachesTheEndWhenScrolledToTheEnd;
    procedure TestBarHiddenWhenContentFits;
  end;

  { -----------------------------------------------------------------------
    HEADER DIVIDER — hit part and the resize cursor
    ----------------------------------------------------------------------- }
  TListViewHeaderTest = class(TTestCase)
  private
    FLV: TTyListViewAccess;
    FActivated: Integer;
    function Col(AIndex: Integer): TTyColumn;
    procedure HActivate(Sender: TObject; AIndex: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestHitPartIsDividerOnTheColumnEdge;
    procedure TestHitPartIsHeaderInTheMiddleOfASection;
    procedure TestHitPartIsNowhereWhenResizeDisabled;
    procedure TestCursorBecomesSplitOverTheDivider;
    procedure TestCursorIsRestoredWhenLeavingTheDivider;
    procedure TestCursorRestoresTheAppsOwnCursorNotCrDefault;
    { double-click the divider -> fit the column to its content }
    procedure TestAutoFitWidensANarrowColumnToItsContent;
    procedure TestAutoFitShrinksAnOverWideColumn;
    procedure TestAutoFitRespectsMinAndMaxWidth;
    procedure TestAutoFitIgnoresANonResizableColumn;
    procedure TestDoubleClickOnDividerAutoFitsAndDoesNotStartAResize;
    procedure TestDoubleClickInTheHeaderDoesNotActivateAnItem;
    procedure TestDoubleClickOnAnItemDoesActivateIt;
  end;

  { -----------------------------------------------------------------------
    TYPE-AHEAD — a fresh key cycles, a refining key may stay put
    ----------------------------------------------------------------------- }
  TListViewTypeAheadTest = class(TTestCase)
  private
    FLV: TTyListViewAccess;
    procedure Add(const ACaption: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestFirstKeyFindsFirstMatch;
    procedure TestRepeatedKeyCyclesThroughMatches;
    procedure TestRefiningKeyKeepsTheCurrentMatch;
    procedure TestRefiningKeyAdvancesWhenCurrentNoLongerMatches;
    procedure TestUnmatchedRefinementFallsBackToCyclingOnTheLastKey;
    procedure TestTypeAheadFollowsDisplayOrderNotItemOrder;
  end;

  { -----------------------------------------------------------------------
    CHECKBOXES (SP2a) — Checked[] is a DATA property keyed by ITEM index; the
    control caches no check state, reading only through GetItemState in both modes.
    Written from docs/superpowers/plans/2026-07-10-listview-sp2a.md, section 一.
    ----------------------------------------------------------------------- }
  TListViewCheckboxTest = class(TTestCase)
  private
    FLV: TTyListViewAccess;
    FCheckedEvents: Integer;
    FLastCheckedIndex: Integer;
    FStore: array of Boolean;        { the app's own store, for OwnerData mode }
    procedure Populate(const ACaps: array of string);
    procedure HGetStateFromStore(Sender: TObject; AIndex: Integer; var AStates: TTyListItemStates);
    procedure HItemChecked(Sender: TObject; AIndex: Integer);
    procedure HItemCheckedMutatesStore(Sender: TObject; AIndex: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { Checked[i] = lisChecked in GetItemState(i) — collection mode }
    procedure TestCheckedReadsItemStateInCollectionMode;
    { SetChecked writes Items[i].States and fires OnItemChecked with the ITEM index }
    procedure TestSetCheckedCollectionWritesStatesAndFiresWithItemIndex;
    { Checked[i] = lisChecked in GetItemState(i) — OwnerData mode }
    procedure TestCheckedReadsItemStateInOwnerDataMode;
    { OwnerData: SetChecked caches nothing; Checked[] follows the app store }
    procedure TestSetCheckedOwnerDataDoesNotCacheReliesOnAppStore;
    { Checked[] out of range neither crashes nor fires the event }
    procedure TestCheckedOutOfRangeNeitherCrashesNorFires;
    { Check state is keyed by item index, so it survives a re-sort both ways }
    procedure TestCheckStateKeyedByItemIndexSurvivesReSort;
    { Checking an item does not select or focus it }
    procedure TestCheckingDoesNotSelectOrFocus;
    { Selecting an item does not check it }
    procedure TestSelectingDoesNotCheck;
  end;

  { -----------------------------------------------------------------------
    INLINE RENAME (SP2a) — one test per editor-lifetime rule, named after the rule.
    Written from docs/superpowers/plans/2026-07-10-listview-sp2a.md, section 二.
    ----------------------------------------------------------------------- }
  { -----------------------------------------------------------------------
    INTERACTION WIRING — the gestures the contract describes, driven for real.
    The checkbox and rename suites exercise Checked[] / BeginEdit directly; nothing
    proved that a CLICK on the box, the SPACE key or F2 actually reach them.
    ----------------------------------------------------------------------- }
  TListViewInteractionTest = class(TTestCase)
  private
    FLV: TTyListViewAccess;
    { The box's location is found by asking GetHitPart, not by reproducing the control's
      geometry: the test then pins the gesture a user can actually perform. }
    function BoxPointOfFirstRow(out P: TPoint): Boolean;
    function LabelPointOfFirstRow: TPoint;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestClickOnTheBoxTogglesCheckWithoutSelecting;
    procedure TestClickOnTheBoxAgainUnchecks;
    procedure TestClickOnTheLabelSelectsAndDoesNotCheck;
    procedure TestSpaceTogglesTheFocusedItemsCheck;
    procedure TestCtrlSpaceStillTogglesTheSelection;
    procedure TestSpaceTogglesSelectionWhenCheckboxesAreOff;
    procedure TestF2StartsRenamingTheFocusedItem;
    procedure TestF2DoesNothingWhenReadOnly;
  end;

  TListViewRenameTest = class(TTestCase)
  private
    FLV: TTyListViewAccess;
    FEditingEvents: Integer;
    FEditedEvents: Integer;
    FLastEditedIndex: Integer;
    FLastEditedText: string;
    FVetoEditing: Boolean;
    FUseRewrite: Boolean;
    FRewriteTo: string;
    procedure Populate(const ACaps: array of string);
    procedure HEditing(Sender: TObject; AIndex: Integer; var AAllow: Boolean);
    procedure HEdited(Sender: TObject; AIndex: Integer; var AText: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestReadOnlyDefaultMakesBeginEditNoOp;
    procedure TestOnEditingVetoKeepsEditingFalse;
    procedure TestEndEditTrueCommitsCollectionCaption;
    procedure TestOnEditedFiresWithItemIndexAndCanRewriteText;
    procedure TestOwnerDataEndEditDoesNotWriteOnlyFires;
    procedure TestEndEditFalseCancelsCaptionUntouched;
    procedure TestCommitIsByItemIndexNotDisplayPosition;
    procedure TestItemsClearCancelsEdit;
    procedure TestShrinkItemCountPastEditedRowCancelsEdit;
    procedure TestSortWhileEditingCommitsFirst;
    procedure TestChangingViewStyleWhileEditingCommitsFirst;
    procedure TestBeginEditOutOfRangeIsNoOp;
    procedure TestDestroyingControlMidEditDoesNotCommitOrCrash;
    procedure TestOnEditedBlankingTextAbandonsCommit;
    procedure TestUserClearedFieldAlsoAbandonsCommit;
  end;

implementation

{ ===========================================================================
  TTyListViewAccess
  =========================================================================== }

function TTyListViewAccess.XGetItemCount: Integer;
begin
  Result := GetItemCount;
end;

function TTyListViewAccess.XGetItemText(AIndex, AColumn: Integer): string;
begin
  Result := GetItemText(AIndex, AColumn);
end;

function TTyListViewAccess.XGetItemImageIndex(AIndex, AColumn: Integer): Integer;
begin
  Result := GetItemImageIndex(AIndex, AColumn);
end;

function TTyListViewAccess.XGetItemState(AIndex: Integer): TTyListItemStates;
begin
  Result := GetItemState(AIndex);
end;

function TTyListViewAccess.OrderAt(ADisplayPos: Integer): Integer;
begin
  Result := DisplayToItem(ADisplayPos);
end;

procedure TTyListViewAccess.XType(const AKey: string);
var
  k: TUTF8Char;
begin
  k := AKey;
  UTF8KeyPress(k);
end;

procedure TTyListViewAccess.XUpdateScrollBars;
begin
  UpdateScrollBars;
end;

function TTyListViewAccess.XVBar: TTyScrollBar;
begin
  Result := VScrollBar;
end;

function TTyListViewAccess.XHBar: TTyScrollBar;
begin
  Result := HScrollBar;
end;

{ Content height of the item region, straight from the pure layout unit -- the same value
  UpdateScrollBars feeds the bar. }
function TTyListViewAccess.XContentHeight: Integer;
var
  m: TTyListMetrics;
begin
  m := CurrentMetrics;
  Result := TyListContentExtent(GetItemCount, m).cy;
end;

procedure TTyListViewAccess.XMouseMove(X, Y: Integer);
begin
  MouseMove([], X, Y);
end;

procedure TTyListViewAccess.XMouseDown(X, Y: Integer; ADouble: Boolean);
var
  sh: TShiftState;
begin
  { LCL's WMLButtonDblClk calls DoMouseDown with [ssDouble] -- see lcl/include/control.inc. }
  sh := [ssLeft];
  if ADouble then Include(sh, ssDouble);
  MouseDown(mbLeft, sh, X, Y);
end;

procedure TTyListViewAccess.XDblClick;
begin
  DblClick;
end;

procedure TTyListViewAccess.XKeyDown(AKey: Word; AShift: TShiftState);
var
  k: Word;
begin
  k := AKey;
  KeyDown(k, AShift);
end;

function TTyListViewAccess.XEditor: TTyEdit;
begin
  Result := InlineEditor;
end;

{ ===========================================================================
  DATA ACCESS
  =========================================================================== }

procedure TListViewDataTest.SetUp;
begin
  FLV := TTyListViewAccess.Create(nil);
  FLV.Font.PixelsPerInch := 96;
end;

procedure TListViewDataTest.TearDown;
begin
  FLV.Free;
end;

procedure TListViewDataTest.AddRow(const ACaption, ASub1, ASub2: string);
var
  it: TTyListItem;
begin
  it := FLV.Items.Add;
  it.Caption := ACaption;
  it.SubItems.Add(ASub1);
  it.SubItems.Add(ASub2);
end;

procedure TListViewDataTest.HGetText(Sender: TObject; AIndex, AColumn: Integer;
  var AText: string);
begin
  { Encode both coordinates so the test can prove the right pair arrived. }
  AText := Format('r%dc%d', [AIndex, AColumn]);
end;

procedure TListViewDataTest.HGetImage(Sender: TObject; AIndex, AColumn: Integer;
  var AImageIndex: Integer);
begin
  AImageIndex := AIndex * 100 + AColumn;
end;

procedure TListViewDataTest.HGetState(Sender: TObject; AIndex: Integer;
  var AStates: TTyListItemStates);
begin
  if AIndex mod 2 = 0 then
    AStates := [lisChecked]
  else
    AStates := [];
end;

procedure TListViewDataTest.TestCollectionColumn0IsCaption;
begin
  AddRow('Alpha', 'one', 'two');
  AddRow('Beta',  'three', 'four');
  FLV.ItemsChanged;
  AssertEquals('col 0 row 0 = Caption', 'Alpha', FLV.XGetItemText(0, 0));
  AssertEquals('col 0 row 1 = Caption', 'Beta',  FLV.XGetItemText(1, 0));
end;

procedure TListViewDataTest.TestCollectionColumnNIsSubItem;
begin
  AddRow('Alpha', 'one', 'two');
  FLV.ItemsChanged;
  AssertEquals('col 1 = SubItems[0]', 'one', FLV.XGetItemText(0, 1));
  AssertEquals('col 2 = SubItems[1]', 'two', FLV.XGetItemText(0, 2));
end;

procedure TListViewDataTest.TestCollectionOutOfRangeColumnEmpty;
begin
  AddRow('Alpha', 'one', 'two');
  FLV.ItemsChanged;
  { Only columns 0..2 have data; column 3 is past SubItems -> '' }
  AssertEquals('out-of-range column is empty', '', FLV.XGetItemText(0, 3));
end;

procedure TListViewDataTest.TestCollectionItemCountTracksItems;
begin
  AssertEquals('empty count = 0', 0, FLV.XGetItemCount);
  AddRow('A', '', '');
  AddRow('B', '', '');
  AddRow('C', '', '');
  FLV.ItemsChanged;
  AssertEquals('count tracks Items.Count', FLV.Items.Count, FLV.XGetItemCount);
  AssertEquals('count = 3', 3, FLV.XGetItemCount);
end;

procedure TListViewDataTest.TestOwnerDataItemCount;
begin
  FLV.OwnerData := True;
  FLV.ItemCount := 42;
  FLV.ItemsChanged;
  AssertEquals('OwnerData count = published ItemCount', 42, FLV.XGetItemCount);
end;

procedure TListViewDataTest.TestOwnerDataTextFanOut;
begin
  FLV.OwnerData := True;
  FLV.ItemCount := 10;
  FLV.OnGetItemText := @HGetText;
  FLV.ItemsChanged;
  AssertEquals('(7,2) fanned out', 'r7c2', FLV.XGetItemText(7, 2));
  AssertEquals('(0,0) fanned out', 'r0c0', FLV.XGetItemText(0, 0));
end;

procedure TListViewDataTest.TestOwnerDataImageFanOut;
begin
  FLV.OwnerData := True;
  FLV.ItemCount := 10;
  FLV.OnGetItemImage := @HGetImage;
  FLV.ItemsChanged;
  AssertEquals('(3,1) image fanned out', 301, FLV.XGetItemImageIndex(3, 1));
end;

procedure TListViewDataTest.TestOwnerDataStateFanOut;
begin
  FLV.OwnerData := True;
  FLV.ItemCount := 10;
  FLV.OnGetItemState := @HGetState;
  FLV.ItemsChanged;
  AssertTrue('even index -> [lisChecked]', FLV.XGetItemState(4) = [lisChecked]);
  AssertTrue('odd index -> []',            FLV.XGetItemState(3) = []);
end;

procedure TListViewDataTest.TestOwnerDataNoHandlerDefaults;
begin
  FLV.OwnerData := True;
  FLV.ItemCount := 5;
  FLV.ItemsChanged;
  { No handlers assigned: defensive defaults, never a crash. }
  AssertEquals('text default = empty', '', FLV.XGetItemText(0, 0));
  AssertEquals('image default = -1', -1, FLV.XGetItemImageIndex(0, 0));
  AssertTrue('state default = []', FLV.XGetItemState(0) = []);
end;

procedure TListViewDataTest.TestSwitchingOwnerDataKeepsArraysSane;
var
  probe: Integer;
begin
  { Populate a collection, select an item, then flip modes back and forth. The
    invariant: no crash, SelCount stays within [0, count], the accessors and
    GetNextSelected keep working. }
  AddRow('A', '', ''); AddRow('B', '', ''); AddRow('C', '', '');
  AddRow('D', '', ''); AddRow('E', '', '');
  FLV.ItemsChanged;
  FLV.MultiSelect := True;
  FLV.Selected[2] := True;

  FLV.OwnerData := True;
  FLV.ItemCount := 3;
  FLV.ItemsChanged;
  AssertTrue('SelCount within range after -> OwnerData',
    (FLV.SelCount >= 0) and (FLV.SelCount <= FLV.XGetItemCount));

  FLV.OwnerData := False;
  FLV.ItemsChanged;
  AssertEquals('collection count restored', 5, FLV.XGetItemCount);
  AssertTrue('SelCount within range after -> collection',
    (FLV.SelCount >= 0) and (FLV.SelCount <= 5));

  { GetNextSelected must terminate (bounded walk), never spin. }
  probe := -1;
  while FLV.GetNextSelected(probe) do
    if probe > 5 then
      Break;
  AssertTrue('GetNextSelected terminated in range', probe <= 5);
end;

{ ===========================================================================
  SORT
  =========================================================================== }

procedure TListViewSortTest.SetUp;
begin
  FLV := TTyListViewAccess.Create(nil);
  FLV.Font.PixelsPerInch := 96;
  FCompareCalls := 0;
  FCompareBadCol := False;
  FCompareBadIdx := False;
end;

procedure TListViewSortTest.TearDown;
begin
  FLV.Free;
end;

procedure TListViewSortTest.PopulateCaptions(const ACaps: array of string);
var
  i: Integer;
  it: TTyListItem;
begin
  for i := Low(ACaps) to High(ACaps) do
  begin
    it := FLV.Items.Add;
    it.Caption := ACaps[i];
  end;
  FLV.ItemsChanged;
end;

procedure TListViewSortTest.HCompareByIndexDesc(Sender: TObject;
  AIndex1, AIndex2, AColumn: Integer; var ACompare: Integer);
begin
  Inc(FCompareCalls);
  if AColumn <> FLV.SortColumn then
    FCompareBadCol := True;
  if (AIndex1 < 0) or (AIndex1 >= FLV.XGetItemCount) or
     (AIndex2 < 0) or (AIndex2 >= FLV.XGetItemCount) then
    FCompareBadIdx := True;
  { Descending by item index: the larger item index sorts first. }
  ACompare := AIndex2 - AIndex1;
end;

procedure TListViewSortTest.TestSortColumnMinusOneRestoresIdentity;
var
  k: Integer;
begin
  PopulateCaptions(['d', 'c', 'b', 'a']);
  FLV.SortKind := lskText;
  FLV.SortColumn := 0;
  FLV.SortDirection := sdAscending;
  FLV.Sort;
  { Now scramble is in place; -1 must give the identity map back. }
  FLV.SortColumn := -1;
  FLV.Sort;
  for k := 0 to FLV.XGetItemCount - 1 do
    AssertEquals(Format('identity at display %d', [k]), k, FLV.OrderAt(k));
end;

procedure TListViewSortTest.TestSortLeavesItemsUntouched;
begin
  PopulateCaptions(['e', 'd', 'c', 'b', 'a']);
  FLV.SortKind := lskText;
  FLV.SortColumn := 0;
  FLV.SortDirection := sdAscending;
  FLV.Sort;
  { Items must NOT be reordered — a design that sorts the collection fails here. }
  AssertEquals('Items[0] still e', 'e', FLV.Items[0].Caption);
  AssertEquals('Items[1] still d', 'd', FLV.Items[1].Caption);
  AssertEquals('Items[2] still c', 'c', FLV.Items[2].Caption);
  AssertEquals('Items[3] still b', 'b', FLV.Items[3].Caption);
  AssertEquals('Items[4] still a', 'a', FLV.Items[4].Caption);
end;

procedure TListViewSortTest.TestSortIsStableOnTies;
begin
  { Items 0..3 = b, a, a, c. Ascending text order with ties broken by item index:
    a(item1), a(item2), b(item0), c(item3) -> FOrder = [1,2,0,3]. }
  PopulateCaptions(['b', 'a', 'a', 'c']);
  FLV.SortKind := lskText;
  FLV.SortColumn := 0;
  FLV.SortDirection := sdAscending;
  FLV.Sort;
  AssertEquals('display 0 = item 1 (first a)',  1, FLV.OrderAt(0));
  AssertEquals('display 1 = item 2 (second a)', 2, FLV.OrderAt(1));
  AssertEquals('display 2 = item 0 (b)',        0, FLV.OrderAt(2));
  AssertEquals('display 3 = item 3 (c)',        3, FLV.OrderAt(3));
end;

procedure TListViewSortTest.TestSortDescendingReversesOrder;
begin
  PopulateCaptions(['a', 'b', 'c']);
  FLV.SortKind := lskText;
  FLV.SortColumn := 0;

  FLV.SortDirection := sdAscending;
  FLV.Sort;
  AssertEquals('asc display 0 = item 0', 0, FLV.OrderAt(0));
  AssertEquals('asc display 2 = item 2', 2, FLV.OrderAt(2));

  FLV.SortDirection := sdDescending;
  FLV.Sort;
  AssertEquals('desc display 0 = item 2', 2, FLV.OrderAt(0));
  AssertEquals('desc display 1 = item 1', 1, FLV.OrderAt(1));
  AssertEquals('desc display 2 = item 0', 0, FLV.OrderAt(2));
end;

procedure TListViewSortTest.TestOnCompareWinsAndGetsItemIndices;
begin
  { Built-in text sort of a,b,c,d,e ascending would give identity. OnCompare sorts
    by item index descending, so the result proves the handler was used. }
  PopulateCaptions(['a', 'b', 'c', 'd', 'e']);
  FLV.SortKind := lskText;
  FLV.SortColumn := 0;
  FLV.SortDirection := sdAscending;
  FLV.OnCompare := @HCompareByIndexDesc;
  FLV.Sort;

  AssertTrue('OnCompare was actually called', FCompareCalls > 0);
  AssertTrue('OnCompare AColumn was always SortColumn', not FCompareBadCol);
  AssertTrue('OnCompare got valid ITEM indices', not FCompareBadIdx);
  AssertEquals('display 0 = item 4', 4, FLV.OrderAt(0));
  AssertEquals('display 1 = item 3', 3, FLV.OrderAt(1));
  AssertEquals('display 4 = item 0', 0, FLV.OrderAt(4));
end;

procedure TListViewSortTest.TestSelectionSurvivesReSort;
begin
  { Item indices are stable across a sort; only the display position moves. }
  PopulateCaptions(['e', 'd', 'c', 'b', 'a']);
  FLV.SortKind := lskText;
  FLV.SortColumn := 0;
  FLV.ItemIndex := 3;
  FLV.Selected[3] := True;
  AssertTrue('precondition: item 3 selected', FLV.Selected[3]);

  FLV.SortDirection := sdAscending;
  FLV.Sort;
  AssertTrue('after asc sort: item 3 still selected', FLV.Selected[3]);
  AssertEquals('after asc sort: ItemIndex still 3', 3, FLV.ItemIndex);

  FLV.SortDirection := sdDescending;
  FLV.Sort;
  AssertTrue('after desc sort: item 3 still selected', FLV.Selected[3]);
  AssertEquals('after desc sort: ItemIndex still 3', 3, FLV.ItemIndex);
end;

procedure TListViewSortTest.TestSelectionSurvivesViewStyleSwitch;
begin
  PopulateCaptions(['e', 'd', 'c', 'b', 'a']);
  FLV.ItemIndex := 3;
  FLV.Selected[3] := True;

  FLV.ViewStyle := lvsIcon;
  AssertTrue('after view switch: item 3 still selected', FLV.Selected[3]);
  AssertEquals('after view switch: ItemIndex still 3', 3, FLV.ItemIndex);
end;

{ ===========================================================================
  SELECTION
  =========================================================================== }

procedure TListViewSelectionTest.SetUp;
begin
  FLV := TTyListViewAccess.Create(nil);
  FLV.Font.PixelsPerInch := 96;
end;

procedure TListViewSelectionTest.TearDown;
begin
  FLV.Free;
end;

procedure TListViewSelectionTest.Populate(ACount: Integer);
var
  i: Integer;
  it: TTyListItem;
begin
  for i := 0 to ACount - 1 do
  begin
    it := FLV.Items.Add;
    it.Caption := 'item' + IntToStr(i);
  end;
  FLV.ItemsChanged;
end;

procedure TListViewSelectionTest.TestMultiSelectFalseCollapsesToItemIndex;
{ The focused item wins the collapse. Note the setup order: `ItemIndex := 2` is
  focus-SELECTS (it exclusively selects 2, same rule as TTyTreeView.SetFocusedNode), so
  the extra bits have to be added afterwards. }
begin
  Populate(6);
  FLV.MultiSelect := True;
  FLV.ItemIndex := 2;              { focus + exclusive select }
  FLV.Selected[1] := True;         { add, without moving the focus }
  FLV.Selected[3] := True;
  AssertEquals('precondition: 3 selected', 3, FLV.SelCount);
  AssertEquals('precondition: focus still 2', 2, FLV.ItemIndex);

  FLV.MultiSelect := False;
  AssertEquals('collapsed to a single selection', 1, FLV.SelCount);
  AssertEquals('the survivor is the focused item', 2, FLV.ItemIndex);
  AssertTrue('and it is selected', FLV.Selected[2]);
end;

procedure TListViewSelectionTest.TestItemIndexIsFocusSelects;
{ Pins the coupling the collapse test depends on: assigning ItemIndex exclusively selects
  that item, while Selected[] adds without moving the focus. }
begin
  Populate(6);
  FLV.MultiSelect := True;
  FLV.Selected[1] := True;
  FLV.Selected[3] := True;
  AssertEquals('Selected[] leaves focus alone', -1, FLV.ItemIndex);

  FLV.ItemIndex := 4;
  AssertEquals('ItemIndex assignment selects exclusively', 1, FLV.SelCount);
  AssertTrue('and it is item 4', FLV.Selected[4]);
  AssertFalse('the old bits are gone', FLV.Selected[1]);
end;

procedure TListViewSelectionTest.TestCollapseWithNoFocusAdoptsFirstSelected;
{ `Selected[i] := True` is "select", not "focus" -- it must not move ItemIndex. So a
  multi-selection can exist with ItemIndex still -1. Collapsing then has no focused item
  to keep; discarding the whole selection would be the surprising answer, so the first
  selected item is adopted as the focus. }
begin
  Populate(6);
  FLV.MultiSelect := True;
  FLV.Selected[4] := True;
  FLV.Selected[2] := True;
  AssertEquals('Selected[] does not move the focus', -1, FLV.ItemIndex);
  AssertEquals('precondition: 2 selected', 2, FLV.SelCount);

  FLV.MultiSelect := False;
  AssertEquals('first selected item adopted as focus', 2, FLV.ItemIndex);
  AssertEquals('exactly one survivor', 1, FLV.SelCount);
  AssertTrue('and it is selected', FLV.Selected[2]);
end;

procedure TListViewSelectionTest.TestCollapseWithNothingSelectedStaysEmpty;
begin
  Populate(6);
  FLV.MultiSelect := True;
  AssertEquals('precondition: nothing selected', 0, FLV.SelCount);
  FLV.MultiSelect := False;
  AssertEquals('still no focus', -1, FLV.ItemIndex);
  AssertEquals('still nothing selected', 0, FLV.SelCount);
end;

procedure TListViewSelectionTest.TestSelectAll;
begin
  Populate(5);
  FLV.MultiSelect := True;
  FLV.SelectAll;
  AssertEquals('SelectAll selects all', 5, FLV.SelCount);
  AssertTrue('first selected', FLV.Selected[0]);
  AssertTrue('last selected',  FLV.Selected[4]);
end;

procedure TListViewSelectionTest.TestClearSelection;
begin
  Populate(5);
  FLV.MultiSelect := True;
  FLV.SelectAll;
  FLV.ClearSelection;
  AssertEquals('ClearSelection empties', 0, FLV.SelCount);
  AssertTrue('nothing selected', not FLV.Selected[0]);
end;

procedure TListViewSelectionTest.TestSelCount;
begin
  Populate(8);
  FLV.MultiSelect := True;
  FLV.Selected[0] := True;
  FLV.Selected[4] := True;
  FLV.Selected[7] := True;
  AssertEquals('SelCount counts set bits', 3, FLV.SelCount);
  FLV.Selected[4] := False;
  AssertEquals('SelCount after deselect', 2, FLV.SelCount);
end;

procedure TListViewSelectionTest.TestGetNextSelectedWalk;
var
  i: Integer;
begin
  Populate(6);
  FLV.MultiSelect := True;
  FLV.Selected[1] := True;
  FLV.Selected[3] := True;
  FLV.Selected[4] := True;

  i := -1;
  AssertTrue('first step', FLV.GetNextSelected(i));
  AssertEquals('first selected = 1', 1, i);
  AssertTrue('second step', FLV.GetNextSelected(i));
  AssertEquals('second selected = 3', 3, i);
  AssertTrue('third step', FLV.GetNextSelected(i));
  AssertEquals('third selected = 4', 4, i);
  AssertTrue('walk ends', not FLV.GetNextSelected(i));
end;

procedure TListViewSelectionTest.TestSelectedOutOfRangeIsSafe;
begin
  Populate(5);
  FLV.MultiSelect := True;
  { Reads of out-of-range indices are False, not a crash. }
  AssertTrue('read past end = False', not FLV.Selected[9999]);
  AssertTrue('read negative = False', not FLV.Selected[-1]);
  { Writes to out-of-range indices are ignored, not a crash. }
  FLV.Selected[9999] := True;
  FLV.Selected[-1] := True;
  AssertEquals('out-of-range writes changed nothing', 0, FLV.SelCount);
end;

{ ===========================================================================
  VIRTUAL-MODE STALENESS
  =========================================================================== }

procedure TListViewVirtualTest.SetUp;
begin
  FLV := TTyListViewAccess.Create(nil);
  FLV.Font.PixelsPerInch := 96;
  FLV.OwnerData := True;
  FLV.MultiSelect := True;
end;

procedure TListViewVirtualTest.TearDown;
begin
  FLV.Free;
end;

procedure TListViewVirtualTest.SetVirtual(ACount: Integer);
begin
  FLV.ItemCount := ACount;
  FLV.ItemsChanged;
end;

procedure TListViewVirtualTest.TestShrinkClampsIndexAndSelection;
begin
  SetVirtual(100);
  FLV.Selected[3] := True;
  FLV.Selected[50] := True;
  FLV.Selected[99] := True;
  FLV.ItemIndex := 99;

  { App shrinks its own store to 5 and tells the control. }
  FLV.ItemCount := 5;
  FLV.ItemsChanged;

  { ItemIndex clamped into [-1, ItemCount-1]. }
  AssertTrue('ItemIndex clamped in range',
    (FLV.ItemIndex >= -1) and (FLV.ItemIndex <= 4));
  { Nothing out of range survives; SelCount counts only survivors. }
  AssertTrue('SelCount only survivors', FLV.SelCount <= 5);
  AssertTrue('SelCount is a valid count', FLV.SelCount >= 0);
  { The stale bit at 50/99 must not be reachable / counted. Reading it is safe. }
  AssertTrue('stale index read safe', not FLV.Selected[50]);
  AssertTrue('stale index read safe (99)', not FLV.Selected[99]);
end;

procedure TListViewVirtualTest.TestShrinkKeepsSurvivingSelection;
begin
  SetVirtual(100);
  FLV.Selected[3] := True;    { survives the shrink }
  FLV.Selected[50] := True;   { dropped by the shrink }

  FLV.ItemCount := 5;
  FLV.ItemsChanged;

  AssertTrue('in-range selection survived', FLV.Selected[3]);
  AssertEquals('only the survivor is counted', 1, FLV.SelCount);
end;

procedure TListViewVirtualTest.TestGrowLeavesNewItemsUnselected;
begin
  SetVirtual(5);
  FLV.Selected[2] := True;

  FLV.ItemCount := 20;
  FLV.ItemsChanged;

  AssertTrue('old selection intact', FLV.Selected[2]);
  AssertTrue('new item 10 unselected', not FLV.Selected[10]);
  AssertTrue('new item 19 unselected', not FLV.Selected[19]);
  AssertEquals('still exactly one selected', 1, FLV.SelCount);
end;

procedure TListViewVirtualTest.TestItemIndexAssignedOutOfRangeIsClamped;
begin
  SetVirtual(20);
  { Out of range in EITHER direction means "no focus", not "focus the nearest row":
    assigning an index that does not exist must never silently focus a different item.
    (The old assertion only checked the range [-1,19], which -1 satisfies -- it would
    have passed against a clamp-to-last implementation too.) }
  FLV.ItemIndex := 99999;
  AssertEquals('too-large ItemIndex resets to -1', -1, FLV.ItemIndex);
  FLV.ItemIndex := -50;
  AssertEquals('negative ItemIndex resets to -1', -1, FLV.ItemIndex);
  { A valid index still sticks. }
  FLV.ItemIndex := 19;
  AssertEquals('last valid index sticks', 19, FLV.ItemIndex);
end;

{ ===========================================================================
  SCROLLBARS
  =========================================================================== }

procedure TListViewScrollTest.SetUp;
var
  i: Integer;
  c: TTyColumn;
begin
  FLV := TTyListViewAccess.Create(nil);
  FLV.SetBounds(0, 0, 400, 220);
  FLV.ViewStyle := lvsReport;
  FLV.RowHeight := 20;
  c := FLV.Header.Columns.Add as TTyColumn;
  c.Text := 'name';
  c.Width := 200;
  FLV.Header.Options := FLV.Header.Options + [hoVisible];
  for i := 0 to 99 do
    FLV.Items.Add.Caption := 'row' + IntToStr(i);
  FLV.ItemsChanged;
  FLV.XUpdateScrollBars;
end;

procedure TListViewScrollTest.TearDown;
begin
  FreeAndNil(FLV);
end;

procedure TListViewScrollTest.TestVerticalMaxIsContentMinusOnePage;
{ TTyScrollBar.Max is the maximum POSITION. TyScrollThumbRect sizes the thumb as
  PageSize / ((Max - Min) + PageSize) and only reaches the track end at Position = Max, so
  feeding it the CONTENT height undersizes the thumb and leaves a permanent gap below it.
  Max must be content - one page, exactly as TTyListBox does. }
var
  page: Integer;
begin
  AssertTrue('the bar is needed', FLV.XVBar.Visible);
  page := FLV.XVBar.PageSize;
  AssertTrue('page size is a real viewport', page > 0);
  AssertEquals('Max = content - page', FLV.XContentHeight - page, FLV.XVBar.Max);
end;

procedure TListViewScrollTest.TestThumbReachesTheEndWhenScrolledToTheEnd;
{ The user-visible symptom: the last row is on screen but the thumb sits mid-track. }
begin
  FLV.ScrollIntoView(99);
  FLV.XUpdateScrollBars;
  AssertEquals('scrolled fully down -> Position = Max', FLV.XVBar.Max, FLV.XVBar.Position);
end;

procedure TListViewScrollTest.TestBarHiddenWhenContentFits;
begin
  FLV.Items.Clear;
  FLV.Items.Add.Caption := 'only row';
  FLV.ItemsChanged;
  FLV.XUpdateScrollBars;
  AssertFalse('one row needs no vertical bar', FLV.XVBar.Visible);
end;

{ ===========================================================================
  HEADER DIVIDER
  =========================================================================== }

procedure TListViewHeaderTest.SetUp;
var
  c: TTyColumn;
begin
  FLV := TTyListViewAccess.Create(nil);
  { The console runner has no screen, so a TFont reports 72 PPI and the control's
    device<->logical scaling stops being the identity: a divider at logical x=120 would
    sit at device x=90. Pin 96 so the coordinates below mean what they say. }
  FLV.Font.PixelsPerInch := 96;
  FLV.SetBounds(0, 0, 400, 200);
  FLV.ViewStyle := lvsReport;
  c := FLV.Header.Columns.Add as TTyColumn; c.Text := 'a'; c.Width := 120;
  c := FLV.Header.Columns.Add as TTyColumn; c.Text := 'b'; c.Width := 120;
  FLV.Header.Options := FLV.Header.Options + [hoVisible, hoColumnResize];
  FLV.Items.Add.Caption := 'row';
  FLV.ItemsChanged;
  FActivated := 0;
  FLV.OnItemActivate := @HActivate;
end;

procedure TListViewHeaderTest.TearDown;
begin
  FreeAndNil(FLV);
end;

function TListViewHeaderTest.Col(AIndex: Integer): TTyColumn;
begin
  Result := FLV.Header.Columns.Items[AIndex] as TTyColumn;
end;

procedure TListViewHeaderTest.HActivate(Sender: TObject; AIndex: Integer);
begin
  Inc(FActivated);
end;

{ The header band is Header.Height tall; column 'a' ends at x = 120. }

procedure TListViewHeaderTest.TestHitPartIsDividerOnTheColumnEdge;
begin
  AssertEquals('hit part at the edge', Ord(lhpDivider), Ord(FLV.GetHitPart(120, 5)));
end;

procedure TListViewHeaderTest.TestHitPartIsHeaderInTheMiddleOfASection;
begin
  AssertTrue('mid-section', FLV.GetHitPart(60, 5) = lhpHeader);
end;

procedure TListViewHeaderTest.TestHitPartIsNowhereWhenResizeDisabled;
begin
  FLV.Header.Options := FLV.Header.Options - [hoColumnResize];
  AssertTrue('no resize -> plain header, not a divider',
    FLV.GetHitPart(120, 5) = lhpHeader);
end;

procedure TListViewHeaderTest.TestCursorBecomesSplitOverTheDivider;
begin
  FLV.XMouseMove(120, 5);
  AssertTrue('crHSplit over the divider', FLV.Cursor = crHSplit);
end;

procedure TListViewHeaderTest.TestCursorIsRestoredWhenLeavingTheDivider;
begin
  FLV.XMouseMove(120, 5);
  AssertTrue('precondition', FLV.Cursor = crHSplit);
  FLV.XMouseMove(60, 5);
  AssertTrue('back to default off the divider', FLV.Cursor = crDefault);
end;

procedure TListViewHeaderTest.TestCursorRestoresTheAppsOwnCursorNotCrDefault;
{ TTyTreeView writes `Cursor := crDefault` here, which quietly destroys a Cursor the app
  set on the control. Save what was there and put it back instead. }
begin
  FLV.Cursor := crHandPoint;
  FLV.XMouseMove(120, 5);
  AssertTrue('overridden while over the divider', FLV.Cursor = crHSplit);
  FLV.XMouseMove(60, 5);
  AssertTrue('the app''s own cursor comes back', FLV.Cursor = crHandPoint);
end;

procedure TListViewHeaderTest.TestAutoFitWidensANarrowColumnToItsContent;
begin
  FLV.Items.Add.Caption := 'a distinctly long file name indeed.txt';
  FLV.ItemsChanged;
  Col(0).Width := 20;
  FLV.AutoFitColumn(0);
  AssertTrue('narrow column grew to fit its widest cell', Col(0).Width > 20);
end;

procedure TListViewHeaderTest.TestAutoFitShrinksAnOverWideColumn;
var
  wide: Integer;
begin
  Col(0).Width := 400;
  wide := Col(0).Width;
  FLV.AutoFitColumn(0);
  AssertTrue('over-wide column shrank to its content', Col(0).Width < wide);
  AssertTrue('but not below its minimum', Col(0).Width >= Col(0).MinWidth);
end;

procedure TListViewHeaderTest.TestAutoFitRespectsMinAndMaxWidth;
begin
  FLV.Items.Add.Caption := 'a distinctly long file name indeed.txt';
  FLV.ItemsChanged;
  Col(0).MaxWidth := 40;
  Col(0).Width := 20;
  FLV.AutoFitColumn(0);
  AssertEquals('clamped by MaxWidth', 40, Col(0).Width);

  Col(0).MinWidth := 200;
  Col(0).MaxWidth := 10000;
  FLV.Items.Clear;
  FLV.Items.Add.Caption := 'x';
  FLV.ItemsChanged;
  FLV.AutoFitColumn(0);
  AssertEquals('clamped by MinWidth', 200, Col(0).Width);
end;

procedure TListViewHeaderTest.TestAutoFitIgnoresANonResizableColumn;
begin
  FLV.Items.Add.Caption := 'a distinctly long file name indeed.txt';
  FLV.ItemsChanged;
  Col(0).Options := Col(0).Options - [coResizable];
  Col(0).Width := 20;
  FLV.AutoFitColumn(0);
  AssertEquals('a column the user cannot resize is not auto-fitted', 20, Col(0).Width);
end;

procedure TListViewHeaderTest.TestDoubleClickOnDividerAutoFitsAndDoesNotStartAResize;
var
  fitted: Integer;
begin
  FLV.Items.Add.Caption := 'a distinctly long file name indeed.txt';
  FLV.ItemsChanged;
  Col(0).Width := 20;
  { The divider of column 0 sits at its right edge, x = 20 after the shrink above. }
  FLV.XMouseDown(20, 5, True);
  fitted := Col(0).Width;
  AssertTrue('the double-click fitted the column', fitted > 20);

  { A resize drag must NOT have started: moving the mouse now would otherwise keep
    rewriting the width. }
  FLV.XMouseMove(300, 5);
  AssertEquals('no resize drag is in progress', fitted, Col(0).Width);
end;

procedure TListViewHeaderTest.TestDoubleClickInTheHeaderDoesNotActivateAnItem;
{ DblClick carries no coordinates. Without a guard, double-clicking the header -- including
  the auto-fit gesture itself -- activates whatever item happens to be focused. }
begin
  FLV.ItemIndex := 0;
  FLV.XMouseDown(60, 5, True);   { middle of a header section, not a divider }
  FLV.XDblClick;
  AssertEquals('header double-click activates nothing', 0, FActivated);
end;

procedure TListViewHeaderTest.TestDoubleClickOnAnItemDoesActivateIt;
begin
  FLV.XMouseDown(50, 30, True);  { below the 22px header band = row 0 }
  FLV.XDblClick;
  AssertEquals('item double-click activates it', 1, FActivated);
  AssertEquals('and it is the row that was clicked', 0, FLV.ItemIndex);
end;

{ ===========================================================================
  TYPE-AHEAD
  =========================================================================== }

procedure TListViewTypeAheadTest.SetUp;
begin
  FLV := TTyListViewAccess.Create(nil);
end;

procedure TListViewTypeAheadTest.TearDown;
begin
  FreeAndNil(FLV);
end;

procedure TListViewTypeAheadTest.Add(const ACaption: string);
begin
  FLV.Items.Add.Caption := ACaption;
  FLV.ItemsChanged;
end;

procedure TListViewTypeAheadTest.TestFirstKeyFindsFirstMatch;
begin
  Add('Alpha'); Add('Report'); Add('Resume'); Add('Zulu');
  FLV.XType('r');
  AssertEquals('first r-match', 1, FLV.ItemIndex);
end;

procedure TListViewTypeAheadTest.TestRepeatedKeyCyclesThroughMatches;
{ A FRESH single key scans from the row AFTER the focused one, so pressing the same letter
  again advances. That exclusive origin is what makes cycling work. }
begin
  Add('Alpha'); Add('Report'); Add('Resume'); Add('Rocket');
  FLV.XType('r');
  AssertEquals('1st r', 1, FLV.ItemIndex);
  FLV.XType('r');
  AssertEquals('2nd r cycles', 2, FLV.ItemIndex);
  FLV.XType('r');
  AssertEquals('3rd r cycles', 3, FLV.ItemIndex);
  FLV.XType('r');
  AssertEquals('4th r wraps', 1, FLV.ItemIndex);
end;

procedure TListViewTypeAheadTest.TestRefiningKeyKeepsTheCurrentMatch;
{ The bug this test was written for: 'r' lands on "Report"; 're' must KEEP "Report" rather
  than skip past it to "Resume". A refining keystroke scans INCLUSIVE of the focused row. }
begin
  Add('Alpha'); Add('Report'); Add('Resume');
  FLV.XType('r');
  AssertEquals('r -> Report', 1, FLV.ItemIndex);
  FLV.XType('e');
  AssertEquals('re -> still Report', 1, FLV.ItemIndex);
  FLV.XType('p');
  AssertEquals('rep -> still Report', 1, FLV.ItemIndex);
end;

procedure TListViewTypeAheadTest.TestRefiningKeyAdvancesWhenCurrentNoLongerMatches;
{ Inclusive does not mean sticky: once the buffer stops matching the focused row, the search
  moves on. }
begin
  Add('Alpha'); Add('Report'); Add('Resume');
  FLV.XType('r');
  AssertEquals('r -> Report', 1, FLV.ItemIndex);
  FLV.XType('e');
  FLV.XType('s');
  AssertEquals('res -> Resume', 2, FLV.ItemIndex);
end;

procedure TListViewTypeAheadTest.TestUnmatchedRefinementFallsBackToCyclingOnTheLastKey;
{ 'r' then 'r' makes the buffer 'rr', which matches nothing; the search falls back to the
  last key alone and cycles. }
begin
  Add('Alpha'); Add('Report'); Add('Resume');
  FLV.XType('r');
  AssertEquals('r -> Report', 1, FLV.ItemIndex);
  FLV.XType('r');
  AssertEquals('rr matches nothing -> cycle on r', 2, FLV.ItemIndex);
end;

procedure TListViewTypeAheadTest.TestTypeAheadFollowsDisplayOrderNotItemOrder;
{ The search walks what the user SEES. After a descending sort the item indices are shuffled,
  but typing 'r' must land on the first r-row on screen -- and ItemIndex reports that row's
  stable ITEM index. }
var
  firstOnScreen: Integer;
begin
  Add('Resume'); Add('Alpha'); Add('Report'); Add('Zulu');
  FLV.SortColumn := 0;
  FLV.SortDirection := sdDescending;
  FLV.Sort;
  { display order is now Zulu(3), Resume(0), Report(2), Alpha(1) -- the first r-row on
    screen is Resume, item index 0. }
  FLV.XType('r');
  firstOnScreen := FLV.ItemIndex;
  AssertEquals('lands on the first r-row in DISPLAY order', 0, firstOnScreen);
  FLV.XType('r');
  AssertEquals('cycles to the next r-row in display order', 2, FLV.ItemIndex);
end;

{ ===========================================================================
  CHECKBOXES
  =========================================================================== }

procedure TListViewCheckboxTest.SetUp;
begin
  FLV := TTyListViewAccess.Create(nil);
  FLV.Font.PixelsPerInch := 96;
  { Checkboxes on: a defensive implementation might gate SetChecked on this, and the
    check data path is what these tests exercise. (See the returned notes: whether
    SetChecked is gated on Checkboxes is a contract looseness.) }
  FLV.Checkboxes := True;
  FCheckedEvents := 0;
  FLastCheckedIndex := -999;
  SetLength(FStore, 0);
end;

procedure TListViewCheckboxTest.TearDown;
begin
  FreeAndNil(FLV);
end;

procedure TListViewCheckboxTest.Populate(const ACaps: array of string);
var
  i: Integer;
begin
  for i := Low(ACaps) to High(ACaps) do
    FLV.Items.Add.Caption := ACaps[i];
  FLV.ItemsChanged;
end;

procedure TListViewCheckboxTest.HGetStateFromStore(Sender: TObject; AIndex: Integer;
  var AStates: TTyListItemStates);
begin
  AStates := [];
  if (AIndex >= 0) and (AIndex <= High(FStore)) and FStore[AIndex] then
    AStates := [lisChecked];
end;

procedure TListViewCheckboxTest.HItemChecked(Sender: TObject; AIndex: Integer);
begin
  Inc(FCheckedEvents);
  FLastCheckedIndex := AIndex;
end;

procedure TListViewCheckboxTest.HItemCheckedMutatesStore(Sender: TObject; AIndex: Integer);
begin
  Inc(FCheckedEvents);
  FLastCheckedIndex := AIndex;
  { The app updates its OWN store; the control cached nothing. }
  if (AIndex >= 0) and (AIndex <= High(FStore)) then
    FStore[AIndex] := True;
end;

procedure TListViewCheckboxTest.TestCheckedReadsItemStateInCollectionMode;
begin
  Populate(['A', 'B', 'C']);
  FLV.Items[1].States := [lisChecked];
  AssertTrue('item 1 reads checked from its state', FLV.Checked[1]);
  AssertFalse('item 0 unchecked', FLV.Checked[0]);
  AssertFalse('item 2 unchecked', FLV.Checked[2]);
end;

procedure TListViewCheckboxTest.TestSetCheckedCollectionWritesStatesAndFiresWithItemIndex;
begin
  Populate(['A', 'B', 'C']);
  FLV.OnItemChecked := @HItemChecked;
  FLV.Checked[1] := True;
  AssertTrue('lisChecked written into Items[1].States', lisChecked in FLV.Items[1].States);
  AssertTrue('and Checked[1] reads back True', FLV.Checked[1]);
  AssertEquals('OnItemChecked fired once', 1, FCheckedEvents);
  AssertEquals('event carried the ITEM index', 1, FLastCheckedIndex);
end;

procedure TListViewCheckboxTest.TestCheckedReadsItemStateInOwnerDataMode;
begin
  FLV.OwnerData := True;
  FLV.ItemCount := 6;
  SetLength(FStore, 6);
  FStore[4] := True;
  FStore[2] := True;
  FLV.OnGetItemState := @HGetStateFromStore;
  FLV.ItemsChanged;
  AssertTrue('item 4 checked per the app store', FLV.Checked[4]);
  AssertTrue('item 2 checked per the app store', FLV.Checked[2]);
  AssertFalse('item 3 unchecked per the app store', FLV.Checked[3]);
end;

procedure TListViewCheckboxTest.TestSetCheckedOwnerDataDoesNotCacheReliesOnAppStore;
begin
  FLV.OwnerData := True;
  FLV.ItemCount := 6;
  SetLength(FStore, 6);           { all False }
  FLV.OnGetItemState := @HGetStateFromStore;
  FLV.OnItemChecked := @HItemChecked;   { records the event but does NOT touch the store }
  FLV.ItemsChanged;

  FLV.Checked[2] := True;
  AssertEquals('OnItemChecked fired', 1, FCheckedEvents);
  AssertEquals('with the ITEM index', 2, FLastCheckedIndex);
  { The control kept NO cache: the store still says unchecked, so Checked[] must too. }
  AssertFalse('SetChecked cached nothing; store unchanged -> still unchecked', FLV.Checked[2]);

  { A handler that DOES update the store makes Checked[] follow it. }
  FLV.OnItemChecked := @HItemCheckedMutatesStore;
  FLV.Checked[3] := True;
  AssertTrue('Checked[] reflects the app store after the handler updates it', FLV.Checked[3]);
end;

procedure TListViewCheckboxTest.TestCheckedOutOfRangeNeitherCrashesNorFires;
begin
  Populate(['A', 'B', 'C']);
  FLV.OnItemChecked := @HItemChecked;
  AssertFalse('read past end = False', FLV.Checked[9999]);
  AssertFalse('read negative = False', FLV.Checked[-1]);
  FLV.Checked[9999] := True;
  FLV.Checked[-1] := True;
  AssertEquals('no event for out-of-range writes', 0, FCheckedEvents);
end;

procedure TListViewCheckboxTest.TestCheckStateKeyedByItemIndexSurvivesReSort;
begin
  Populate(['e', 'd', 'c', 'b', 'a']);
  FLV.Checked[3] := True;
  AssertTrue('precondition: item 3 checked', FLV.Checked[3]);

  FLV.SortColumn := 0;
  FLV.SortDirection := sdAscending;
  FLV.Sort;
  AssertTrue('after asc sort: item 3 still checked', FLV.Checked[3]);

  FLV.SortDirection := sdDescending;
  FLV.Sort;
  AssertTrue('after desc sort: item 3 still checked', FLV.Checked[3]);
end;

procedure TListViewCheckboxTest.TestCheckingDoesNotSelectOrFocus;
begin
  Populate(['A', 'B', 'C', 'D']);
  FLV.Checked[2] := True;
  AssertEquals('checking did not move the focus', -1, FLV.ItemIndex);
  AssertFalse('checking did not select', FLV.Selected[2]);
  AssertEquals('nothing is selected', 0, FLV.SelCount);
  AssertTrue('but the item is checked', FLV.Checked[2]);
end;

procedure TListViewCheckboxTest.TestSelectingDoesNotCheck;
begin
  Populate(['A', 'B', 'C', 'D']);
  FLV.ItemIndex := 2;               { focus-selects item 2 }
  AssertTrue('precondition: item 2 selected', FLV.Selected[2]);
  AssertFalse('focus/select did not check it', FLV.Checked[2]);

  FLV.MultiSelect := True;
  FLV.Selected[3] := True;
  AssertFalse('selecting item 3 did not check it', FLV.Checked[3]);
end;

{ ===========================================================================
  INLINE RENAME
  =========================================================================== }

procedure TListViewRenameTest.SetUp;
var
  c: TTyColumn;
begin
  FLV := TTyListViewAccess.Create(nil);
  FLV.Font.PixelsPerInch := 96;
  FLV.SetBounds(0, 0, 400, 200);
  FLV.ViewStyle := lvsReport;
  c := FLV.Header.Columns.Add as TTyColumn;
  c.Text := 'Name';
  c.Width := 200;
  FLV.OnEditing := @HEditing;
  FLV.OnEdited := @HEdited;
  FEditingEvents := 0;
  FEditedEvents := 0;
  FLastEditedIndex := -999;
  FLastEditedText := #1;            { a sentinel no real edit produces }
  FVetoEditing := False;
  FUseRewrite := False;
  FRewriteTo := '';
end;

procedure TListViewRenameTest.TearDown;
begin
  FreeAndNil(FLV);
end;

procedure TListViewRenameTest.Populate(const ACaps: array of string);
var
  i: Integer;
begin
  for i := Low(ACaps) to High(ACaps) do
    FLV.Items.Add.Caption := ACaps[i];
  FLV.ItemsChanged;
end;

procedure TListViewRenameTest.HEditing(Sender: TObject; AIndex: Integer; var AAllow: Boolean);
begin
  Inc(FEditingEvents);
  if FVetoEditing then
    AAllow := False;
end;

procedure TListViewRenameTest.HEdited(Sender: TObject; AIndex: Integer; var AText: string);
begin
  Inc(FEditedEvents);
  FLastEditedIndex := AIndex;
  FLastEditedText := AText;          { the text as handed in, BEFORE any rewrite }
  if FUseRewrite then
    AText := FRewriteTo;
end;

procedure TListViewRenameTest.TestReadOnlyDefaultMakesBeginEditNoOp;
{ ReadOnly defaults to True (opt-in editing, unlike LCL), so BeginEdit is a silent no-op. }
begin
  Populate(['Alpha', 'Beta', 'Gamma']);
  AssertTrue('precondition: ReadOnly defaults True', FLV.ReadOnly);
  FLV.BeginEdit(1);
  AssertFalse('BeginEdit did nothing while ReadOnly', FLV.Editing);
end;

procedure TListViewRenameTest.TestOnEditingVetoKeepsEditingFalse;
{ OnEditing returning AAllow := False vetoes the edit; Editing stays False. }
begin
  Populate(['Alpha', 'Beta', 'Gamma']);
  FLV.ReadOnly := False;
  FVetoEditing := True;
  FLV.BeginEdit(1);
  AssertTrue('OnEditing was consulted', FEditingEvents > 0);
  AssertFalse('a veto kept editing off', FLV.Editing);
end;

procedure TListViewRenameTest.TestEndEditTrueCommitsCollectionCaption;
{ EndEdit(True) writes the editor text into Items[i].Caption (collection mode). }
begin
  Populate(['Alpha', 'Beta', 'Gamma']);
  FLV.ReadOnly := False;
  FLV.BeginEdit(1);
  AssertTrue('editing started', FLV.Editing);
  FLV.XEditor.Text := 'Renamed';
  FLV.EndEdit(True);
  AssertEquals('caption committed', 'Renamed', FLV.Items[1].Caption);
  AssertFalse('editing is over', FLV.Editing);
  AssertEquals('OnEdited fired once', 1, FEditedEvents);
  AssertEquals('OnEdited got the ITEM index', 1, FLastEditedIndex);
end;

procedure TListViewRenameTest.TestOnEditedFiresWithItemIndexAndCanRewriteText;
{ OnEdited fires with the item index and may rewrite the text through its var param;
  the rewritten text is what gets committed. }
begin
  Populate(['Alpha', 'Beta', 'Gamma']);
  FLV.ReadOnly := False;
  FLV.BeginEdit(0);
  FLV.XEditor.Text := 'Typed';
  FUseRewrite := True;
  FRewriteTo := 'Final';
  FLV.EndEdit(True);
  AssertEquals('OnEdited saw the ITEM index', 0, FLastEditedIndex);
  AssertEquals('OnEdited was handed the typed text', 'Typed', FLastEditedText);
  AssertEquals('the rewritten text is what committed', 'Final', FLV.Items[0].Caption);
end;

procedure TListViewRenameTest.TestOwnerDataEndEditDoesNotWriteOnlyFires;
{ OwnerData mode: EndEdit(True) writes nothing itself (the control owns no data);
  it only fires OnEdited so the app can update its own store. }
begin
  FLV.OwnerData := True;
  FLV.ItemCount := 5;
  FLV.ItemsChanged;
  FLV.ReadOnly := False;
  FLV.BeginEdit(3);
  AssertTrue('editing started in OwnerData mode', FLV.Editing);
  FLV.XEditor.Text := 'NewName';
  FLV.EndEdit(True);
  AssertEquals('OnEdited fired once', 1, FEditedEvents);
  AssertEquals('with the ITEM index', 3, FLastEditedIndex);
  AssertEquals('carrying the edited text', 'NewName', FLastEditedText);
  AssertEquals('the built-in collection was NOT written to', 0, FLV.Items.Count);
  AssertFalse('editing is over', FLV.Editing);
end;

procedure TListViewRenameTest.TestEndEditFalseCancelsCaptionUntouched;
{ EndEdit(False) cancels: the caption is left untouched and OnEdited never fires. }
begin
  Populate(['Alpha', 'Beta']);
  FLV.ReadOnly := False;
  FLV.BeginEdit(1);
  FLV.XEditor.Text := 'ZZZ';
  FLV.EndEdit(False);
  AssertEquals('caption untouched by a cancel', 'Beta', FLV.Items[1].Caption);
  AssertEquals('cancel does not commit', 0, FEditedEvents);
  AssertFalse('editing is over', FLV.Editing);
end;

procedure TListViewRenameTest.TestCommitIsByItemIndexNotDisplayPosition;
{ The edit target is an ITEM index, not a display position. Sort first so item 3
  sits at a DIFFERENT display position (1), then edit item 3 and commit: item 3 --
  not the item now at display position 3 -- must receive the text. }
begin
  Populate(['e', 'd', 'c', 'b', 'a']);
  FLV.ReadOnly := False;
  FLV.SortColumn := 0;
  FLV.SortDirection := sdAscending;
  FLV.Sort;
  { display order now a(item4) b(item3) c(item2) d(item1) e(item0):
    item 3 is at display pos 1; display pos 3 holds item 1. }
  AssertEquals('precondition: item 3 is at display pos 1', 3, FLV.OrderAt(1));
  AssertEquals('precondition: display pos 3 is item 1', 1, FLV.OrderAt(3));

  FLV.BeginEdit(3);
  FLV.XEditor.Text := 'RENAMED';
  FLV.EndEdit(True);

  AssertEquals('the ITEM at index 3 received the text', 'RENAMED', FLV.Items[3].Caption);
  AssertEquals('the item at display pos 3 (item 1) was NOT touched', 'd', FLV.Items[1].Caption);
  AssertEquals('OnEdited reported the ITEM index', 3, FLastEditedIndex);
end;

procedure TListViewRenameTest.TestItemsClearCancelsEdit;
{ Clearing the collection out from under an open edit CANCELS it (no commit into a
  row that no longer exists). }
begin
  Populate(['a', 'b', 'c']);
  FLV.ReadOnly := False;
  FLV.BeginEdit(1);
  AssertTrue('editing started', FLV.Editing);
  FLV.Items.Clear;
  AssertFalse('the edit was cancelled', FLV.Editing);
  AssertEquals('nothing was committed', 0, FEditedEvents);
end;

procedure TListViewRenameTest.TestShrinkItemCountPastEditedRowCancelsEdit;
{ OwnerData: shrinking ItemCount below the edited row + ItemsChanged CANCELS the edit. }
begin
  FLV.OwnerData := True;
  FLV.ItemCount := 10;
  FLV.ItemsChanged;
  FLV.ReadOnly := False;
  FLV.BeginEdit(7);
  AssertTrue('editing started', FLV.Editing);
  FLV.XEditor.Text := 'X';
  FLV.ItemCount := 5;
  FLV.ItemsChanged;
  AssertFalse('row 7 is gone -> edit cancelled', FLV.Editing);
  AssertEquals('nothing was committed', 0, FEditedEvents);
end;

procedure TListViewRenameTest.TestSortWhileEditingCommitsFirst;
{ Sorting while editing COMMITS first (the cell is about to move). }
begin
  Populate(['e', 'd', 'c', 'b', 'a']);
  FLV.ReadOnly := False;
  FLV.SortColumn := 0;
  FLV.BeginEdit(2);
  AssertTrue('editing started', FLV.Editing);
  FLV.XEditor.Text := 'CC';
  FLV.Sort;
  AssertFalse('the sort committed and closed the edit', FLV.Editing);
  AssertEquals('the edit was committed to item 2 first', 'CC', FLV.Items[2].Caption);
  AssertEquals('OnEdited fired for item 2', 2, FLastEditedIndex);
end;

procedure TListViewRenameTest.TestChangingViewStyleWhileEditingCommitsFirst;
{ Switching ViewStyle while editing COMMITS first. }
begin
  Populate(['e', 'd', 'c', 'b', 'a']);
  FLV.ReadOnly := False;
  FLV.BeginEdit(2);
  AssertTrue('editing started', FLV.Editing);
  FLV.XEditor.Text := 'VV';
  FLV.ViewStyle := lvsIcon;
  AssertFalse('the view switch committed and closed the edit', FLV.Editing);
  AssertEquals('the edit was committed to item 2 first', 'VV', FLV.Items[2].Caption);
end;

procedure TListViewRenameTest.TestBeginEditOutOfRangeIsNoOp;
{ BeginEdit on an out-of-range index is a no-op (Editing stays False, no crash). }
begin
  Populate(['a', 'b']);
  FLV.ReadOnly := False;
  FLV.BeginEdit(9999);
  AssertFalse('too-large index did nothing', FLV.Editing);
  FLV.BeginEdit(-1);
  AssertFalse('negative index did nothing', FLV.Editing);
end;

procedure TListViewRenameTest.TestDestroyingControlMidEditDoesNotCommitOrCrash;
{ Destroying the control mid-edit must not commit (the csDestroying guard) and must
  not crash. Freeing FLV here; TearDown's FreeAndNil then sees nil. }
begin
  Populate(['a', 'b', 'c']);
  FLV.ReadOnly := False;
  FLV.BeginEdit(0);
  FLV.XEditor.Text := 'Typed';
  FreeAndNil(FLV);
  AssertEquals('destroy did not commit', 0, FEditedEvents);
end;

procedure TListViewRenameTest.TestOnEditedBlankingTextAbandonsCommit;
{ Per the OnEdited contract ("var AText; setting '' is treated as abandon"), a handler
  that blanks the text abandons the commit: the caption is left untouched. }
begin
  Populate(['a', 'b', 'c']);
  FLV.ReadOnly := False;
  FLV.BeginEdit(1);
  FLV.XEditor.Text := 'typed';
  FUseRewrite := True;
  FRewriteTo := '';
  FLV.EndEdit(True);
  AssertTrue('OnEdited still fired', FEditedEvents = 1);
  AssertEquals('a blanked text abandons -> caption untouched', 'b', FLV.Items[1].Caption);
  AssertFalse('editing is over', FLV.Editing);
end;

procedure TListViewRenameTest.TestUserClearedFieldAlsoAbandonsCommit;
{ The contract only pins "the HANDLER setting AText := '' means abandon". The implementation
  is broader: any empty text after the handler runs abandons, including a field the user
  cleared themselves. That is LCL's rename semantics -- an empty name is a cancel, not a
  rename to nothing -- so pin it rather than leave it to chance. }
begin
  Populate(['a', 'b', 'c']);
  FLV.ReadOnly := False;
  FLV.BeginEdit(1);
  FLV.XEditor.Text := '';          { the user cleared it; no handler rewrite }
  FLV.EndEdit(True);
  AssertTrue('OnEdited still fired', FEditedEvents = 1);
  AssertEquals('an empty name is a cancel, not a rename to nothing', 'b', FLV.Items[1].Caption);
  AssertFalse('editing is over', FLV.Editing);
end;

{ ===========================================================================
  INTERACTION WIRING
  =========================================================================== }

procedure TListViewInteractionTest.SetUp;
var
  c: TTyColumn;
  i: Integer;
begin
  FLV := TTyListViewAccess.Create(nil);
  FLV.Font.PixelsPerInch := 96;   { the runner reports 72; see the header suite }
  FLV.SetBounds(0, 0, 400, 300);
  FLV.ViewStyle := lvsReport;
  c := FLV.Header.Columns.Add as TTyColumn; c.Text := 'name'; c.Width := 300;
  FLV.Header.Options := FLV.Header.Options + [hoVisible];
  FLV.Header.MainColumn := 0;   { must be set AFTER the column exists }
  FLV.Checkboxes := True;
  for i := 0 to 4 do
    FLV.Items.Add.Caption := 'item' + IntToStr(i);
  FLV.ItemsChanged;
end;

procedure TListViewInteractionTest.TearDown;
begin
  FreeAndNil(FLV);
end;

{ Row 0 sits just below the header band; walk x until GetHitPart says we are on the box. }
function TListViewInteractionTest.BoxPointOfFirstRow(out P: TPoint): Boolean;
var
  x, y: Integer;
begin
  Result := False;
  y := FLV.Header.Height + FLV.RowHeight div 2;
  for x := 0 to 60 do
    if FLV.GetHitPart(x, y) = lhpCheck then
    begin
      P := Point(x + 1, y);
      Exit(True);
    end;
end;

function TListViewInteractionTest.LabelPointOfFirstRow: TPoint;
begin
  Result := Point(200, FLV.Header.Height + FLV.RowHeight div 2);
end;

procedure TListViewInteractionTest.TestClickOnTheBoxTogglesCheckWithoutSelecting;
var
  p: TPoint;
begin
  AssertTrue('the box is hit-testable', BoxPointOfFirstRow(p));
  AssertTrue('label point is not the box', FLV.GetHitPart(200, p.Y) <> lhpCheck);

  FLV.XMouseDown(p.X, p.Y);
  AssertTrue('the click checked item 0', FLV.Checked[0]);
  AssertEquals('and selected nothing', 0, FLV.SelCount);
  AssertEquals('and moved no focus', -1, FLV.ItemIndex);
end;

procedure TListViewInteractionTest.TestClickOnTheBoxAgainUnchecks;
var
  p: TPoint;
begin
  AssertTrue(BoxPointOfFirstRow(p));
  FLV.XMouseDown(p.X, p.Y);
  FLV.XMouseDown(p.X, p.Y);
  AssertFalse('a second click unchecks', FLV.Checked[0]);
end;

procedure TListViewInteractionTest.TestClickOnTheLabelSelectsAndDoesNotCheck;
var
  p: TPoint;
begin
  p := LabelPointOfFirstRow;
  AssertTrue('precondition: that point is the label', FLV.GetHitPart(p.X, p.Y) = lhpLabel);
  FLV.XMouseDown(p.X, p.Y);
  AssertEquals('the label click focused item 0', 0, FLV.ItemIndex);
  AssertFalse('and did not check it', FLV.Checked[0]);
end;

procedure TListViewInteractionTest.TestSpaceTogglesTheFocusedItemsCheck;
begin
  FLV.ItemIndex := 2;
  FLV.XKeyDown(VK_SPACE);
  AssertTrue('Space checked the focused item', FLV.Checked[2]);
  FLV.XKeyDown(VK_SPACE);
  AssertFalse('Space unchecked it again', FLV.Checked[2]);
end;

procedure TListViewInteractionTest.TestCtrlSpaceStillTogglesTheSelection;
begin
  FLV.MultiSelect := True;
  FLV.ItemIndex := 2;          { focus-selects }
  FLV.XKeyDown(VK_SPACE, [ssCtrl]);
  AssertFalse('Ctrl+Space did not touch the check', FLV.Checked[2]);
  AssertEquals('it toggled the selection off', 0, FLV.SelCount);
end;

procedure TListViewInteractionTest.TestSpaceTogglesSelectionWhenCheckboxesAreOff;
begin
  FLV.Checkboxes := False;
  FLV.MultiSelect := True;
  FLV.ItemIndex := 2;
  FLV.XKeyDown(VK_SPACE);
  AssertEquals('with no checkboxes, Space is the old selection toggle', 0, FLV.SelCount);
  AssertFalse('and still no check state', FLV.Checked[2]);
end;

procedure TListViewInteractionTest.TestF2StartsRenamingTheFocusedItem;
begin
  FLV.ReadOnly := False;
  FLV.ItemIndex := 1;
  FLV.XKeyDown(VK_F2);
  AssertTrue('F2 entered rename', FLV.Editing);
  FLV.EndEdit(False);
end;

procedure TListViewInteractionTest.TestF2DoesNothingWhenReadOnly;
begin
  AssertTrue('precondition: ReadOnly is the default', FLV.ReadOnly);
  FLV.ItemIndex := 1;
  FLV.XKeyDown(VK_F2);
  AssertFalse('F2 on a read-only list does nothing', FLV.Editing);
end;

initialization
  RegisterTest(TListViewDataTest);
  RegisterTest(TListViewSortTest);
  RegisterTest(TListViewSelectionTest);
  RegisterTest(TListViewVirtualTest);
  RegisterTest(TListViewScrollTest);
  RegisterTest(TListViewHeaderTest);
  RegisterTest(TListViewTypeAheadTest);
  RegisterTest(TListViewCheckboxTest);
  RegisterTest(TListViewRenameTest);
  RegisterTest(TListViewInteractionTest);
end.
