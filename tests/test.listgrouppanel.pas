unit test.listgrouppanel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller,
  tyControls.Base, tyControls.ListGroupPanel;
type
  { Pure layout/hit-test functions — the headless-tested core (no window handle). }
  TTyListGroupMathTest = class(TTestCase)
  private
    function Shapes(const AExpanded: array of Boolean;
      const AItemCounts: array of Integer): TTyListGroupShapes;
  published
    procedure TestAllCollapsedHeadersOnly;
    procedure TestSomeExpandedContributeItems;
    procedure TestItemRectsOnlyForExpandedGroups;
    procedure TestEmptyGroupHeaderOnly;
    procedure TestContentHeightStacks;
    procedure TestHitHeaderVsItem;
    procedure TestHitMissBelowContent;
    procedure TestFullWidthRects;
  end;

  { The control: model mutation, toggle, selection, events, scroll, hit routing. }
  TTyListGroupPanelTest = class(TTestCase)
  private
    FForm: TForm;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKeyIsPanel;
    procedure TestAddGroupsAndItems;
    procedure TestToggleFiresGroupToggleOnce;
    procedure TestSelectItemFiresItemClick;
    procedure TestSelectItemOutOfRangeClears;
    procedure TestHeaderClickToggles;
    procedure TestItemClickSelects;
    procedure TestCollapsedGroupHasNoItemHits;
    procedure TestWheelScrollsWhenOverflow;
    procedure TestWheelNoScrollWhenFits;
    procedure TestCollapseClampsScrollOffset;
    procedure TestClearResets;
    procedure TestRenderDoesNotCrash;
  end;

implementation

type
  TPanelAccess = class(TTyListGroupPanel)
  public
    function StyleTypeKey: string;
    procedure DoMouseDown(X, Y: Integer);
    procedure CallWheel(WheelDelta: Integer);
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TToggleProbe = class
  public
    Count: Integer;
    LastGroup: Integer;
    procedure Handle(Sender: TObject; AGroupIndex: Integer);
  end;

  TItemProbe = class
  public
    Count: Integer;
    LastGroup, LastItem: Integer;
    procedure Handle(Sender: TObject; AGroupIndex, AItemIndex: Integer);
  end;

function TPanelAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TPanelAccess.DoMouseDown(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
end;

procedure TPanelAccess.CallWheel(WheelDelta: Integer);
begin
  DoMouseWheel([], WheelDelta, Point(0, 0));
end;

procedure TPanelAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TToggleProbe.Handle(Sender: TObject; AGroupIndex: Integer);
begin
  Inc(Count);
  LastGroup := AGroupIndex;
end;

procedure TItemProbe.Handle(Sender: TObject; AGroupIndex, AItemIndex: Integer);
begin
  Inc(Count);
  LastGroup := AGroupIndex;
  LastItem := AItemIndex;
end;

{ TTyListGroupMathTest }

function TTyListGroupMathTest.Shapes(const AExpanded: array of Boolean;
  const AItemCounts: array of Integer): TTyListGroupShapes;
var
  i: Integer;
begin
  SetLength(Result, Length(AExpanded));
  for i := 0 to High(AExpanded) do
  begin
    Result[i].Expanded := AExpanded[i];
    Result[i].ItemCount := AItemCounts[i];
  end;
end;

procedure TTyListGroupMathTest.TestAllCollapsedHeadersOnly;
var
  parts: TTyListGroupParts;
begin
  // 3 groups, all collapsed -> exactly 3 header parts, stacked at header height 26.
  parts := TyListGroupLayout(Shapes([False, False, False], [2, 3, 0]), 26, 24, 200);
  AssertEquals('all-collapsed -> one part per group', 3, Length(parts));
  AssertTrue('part 0 is a header', parts[0].Kind = lgpHeader);
  AssertTrue('part 1 is a header', parts[1].Kind = lgpHeader);
  AssertTrue('part 2 is a header', parts[2].Kind = lgpHeader);
  AssertEquals('header 0 top', 0, parts[0].Rect.Top);
  AssertEquals('header 0 bottom', 26, parts[0].Rect.Bottom);
  AssertEquals('header 1 top follows header 0', 26, parts[1].Rect.Top);
  AssertEquals('header 2 top', 52, parts[2].Rect.Top);
end;

procedure TTyListGroupPanelTest.TestTypeKeyIsPanel;
var
  P: TPanelAccess;
begin
  P := TPanelAccess.Create(FForm);
  P.Parent := FForm;
  P.Font.PixelsPerInch := 96;
  AssertEquals('reuses the TyPanel typeKey', 'TyPanel', P.StyleTypeKey);
end;

procedure TTyListGroupMathTest.TestSomeExpandedContributeItems;
var
  parts: TTyListGroupParts;
begin
  // Group 0 collapsed (2 items hidden), group 1 expanded (3 items shown), group 2 collapsed.
  // Parts: H0, H1, I(1,0), I(1,1), I(1,2), H2 = 6.
  parts := TyListGroupLayout(Shapes([False, True, False], [2, 3, 4]), 26, 24, 200);
  AssertEquals('only expanded group contributes item rects', 6, Length(parts));
  AssertTrue('part 0 header (g0)', (parts[0].Kind = lgpHeader) and (parts[0].GroupIndex = 0));
  AssertTrue('part 1 header (g1)', (parts[1].Kind = lgpHeader) and (parts[1].GroupIndex = 1));
  AssertTrue('part 2 item g1/i0', (parts[2].Kind = lgpItem)
    and (parts[2].GroupIndex = 1) and (parts[2].ItemIndex = 0));
  AssertTrue('part 4 item g1/i2', (parts[4].Kind = lgpItem) and (parts[4].ItemIndex = 2));
  AssertTrue('part 5 header (g2)', (parts[5].Kind = lgpHeader) and (parts[5].GroupIndex = 2));
  // Geometry: H1 at y=26..52; first item at 52..76; last item 100..124; H2 at 124..150.
  AssertEquals('first item top', 52, parts[2].Rect.Top);
  AssertEquals('first item bottom', 76, parts[2].Rect.Bottom);
  AssertEquals('g2 header top after 3 items', 124, parts[5].Rect.Top);
end;

procedure TTyListGroupMathTest.TestItemRectsOnlyForExpandedGroups;
var
  parts: TTyListGroupParts;
  i, itemCount: Integer;
begin
  // Two expanded, two collapsed; only expanded groups' items should appear.
  parts := TyListGroupLayout(Shapes([True, False, True, False], [1, 5, 2, 3]), 26, 24, 200);
  itemCount := 0;
  for i := 0 to High(parts) do
    if parts[i].Kind = lgpItem then
    begin
      Inc(itemCount);
      AssertTrue('item belongs to an expanded group',
        (parts[i].GroupIndex = 0) or (parts[i].GroupIndex = 2));
    end;
  // 1 (g0) + 2 (g2) = 3 items; + 4 headers = 7 parts.
  AssertEquals('only expanded groups contribute items', 3, itemCount);
  AssertEquals('total parts', 7, Length(parts));
end;

procedure TTyListGroupMathTest.TestEmptyGroupHeaderOnly;
var
  parts: TTyListGroupParts;
begin
  // An EXPANDED but EMPTY group contributes only its header (no item rects).
  parts := TyListGroupLayout(Shapes([True], [0]), 26, 24, 200);
  AssertEquals('empty expanded group -> header only', 1, Length(parts));
  AssertTrue('the single part is the header', parts[0].Kind = lgpHeader);
end;

procedure TTyListGroupMathTest.TestContentHeightStacks;
var
  parts: TTyListGroupParts;
begin
  // 2 headers (26 each) + 3 items (24 each) from the expanded group 0.
  parts := TyListGroupLayout(Shapes([True, False], [3, 9]), 26, 24, 200);
  // H0 26 + 3*24 72 + H1 26 = 124.
  AssertEquals('content height = bottom of last part', 124, TyListGroupContentHeight(parts));
  AssertEquals('no groups -> content height 0', 0,
    TyListGroupContentHeight(TyListGroupLayout(Shapes([], []), 26, 24, 200)));
end;

procedure TTyListGroupMathTest.TestHitHeaderVsItem;
var
  parts: TTyListGroupParts;
  h: TTyListGroupHit;
begin
  // g0 expanded with 2 items: H0 0..26, I0 26..50, I1 50..74, then H1 74..100.
  parts := TyListGroupLayout(Shapes([True, False], [2, 4]), 26, 24, 200);
  // Hit inside the header band.
  h := TyListGroupHitTest(parts, Point(40, 10));
  AssertTrue('header hit', h.Hit);
  AssertTrue('header kind', h.Kind = lgpHeader);
  AssertEquals('header group 0', 0, h.GroupIndex);
  AssertEquals('header itemindex -1', -1, h.ItemIndex);
  // Hit inside the first item row (y in 26..50).
  h := TyListGroupHitTest(parts, Point(40, 30));
  AssertTrue('item hit', h.Hit);
  AssertTrue('item kind', h.Kind = lgpItem);
  AssertEquals('item group 0', 0, h.GroupIndex);
  AssertEquals('item index 0', 0, h.ItemIndex);
  // Hit inside the second item row (y in 50..74).
  h := TyListGroupHitTest(parts, Point(40, 60));
  AssertTrue('second item hit', h.Hit);
  AssertEquals('item index 1', 1, h.ItemIndex);
  // Hit the second group's header (y in 74..100).
  h := TyListGroupHitTest(parts, Point(40, 80));
  AssertTrue('g1 header hit', h.Hit and (h.Kind = lgpHeader));
  AssertEquals('g1 header group 1', 1, h.GroupIndex);
end;

procedure TTyListGroupMathTest.TestHitMissBelowContent;
var
  parts: TTyListGroupParts;
  h: TTyListGroupHit;
begin
  parts := TyListGroupLayout(Shapes([False, False], [2, 2]), 26, 24, 200);
  // Content ends at y=52; a point below it misses everything.
  h := TyListGroupHitTest(parts, Point(40, 200));
  AssertFalse('miss below content', h.Hit);
  AssertEquals('miss group -1', -1, h.GroupIndex);
  AssertEquals('miss item -1', -1, h.ItemIndex);
end;

procedure TTyListGroupMathTest.TestFullWidthRects;
var
  parts: TTyListGroupParts;
begin
  parts := TyListGroupLayout(Shapes([True], [1]), 26, 24, 180);
  AssertEquals('header spans full width left', 0, parts[0].Rect.Left);
  AssertEquals('header spans full width right', 180, parts[0].Rect.Right);
  AssertEquals('item spans full width right', 180, parts[1].Rect.Right);
end;

{ TTyListGroupPanelTest }

procedure TTyListGroupPanelTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
end;

procedure TTyListGroupPanelTest.TearDown;
begin
  FForm.Free;
end;

procedure TTyListGroupPanelTest.TestAddGroupsAndItems;
var
  P: TTyListGroupPanel;
  g0, g1: Integer;
begin
  P := TTyListGroupPanel.Create(FForm);
  P.Parent := FForm;
  P.Font.PixelsPerInch := 96;
  g0 := P.AddGroup('Contacts');
  g1 := P.AddGroup('Tasks');
  AssertEquals('first group index 0', 0, g0);
  AssertEquals('second group index 1', 1, g1);
  AssertEquals('group count 2', 2, P.GroupCount);
  AssertEquals('add item returns 0', 0, P.AddItem(g0, 'Alice'));
  AssertEquals('add item returns 1', 1, P.AddItem(g0, 'Bob', 7));
  AssertEquals('g0 item count', 2, P.ItemCount(g0));
  AssertEquals('g1 item count 0', 0, P.ItemCount(g1));
  AssertEquals('item caption', 'Bob', P.ItemCaption(g0, 1));
  AssertEquals('item image index', 7, P.ItemImageIndex(g0, 1));
  AssertEquals('group caption', 'Tasks', P.GroupCaption[g1]);
  // Out-of-range item add is rejected.
  AssertEquals('add to bad group -1', -1, P.AddItem(99, 'x'));
end;

procedure TTyListGroupPanelTest.TestToggleFiresGroupToggleOnce;
var
  P: TTyListGroupPanel;
  Probe: TToggleProbe;
begin
  P := TTyListGroupPanel.Create(FForm);
  P.Parent := FForm;
  P.Font.PixelsPerInch := 96;
  P.AddGroup('G0');
  P.AddGroup('G1');
  Probe := TToggleProbe.Create;
  try
    P.OnGroupToggle := @Probe.Handle;
    AssertFalse('starts collapsed', P.Expanded[0]);
    P.ToggleGroup(0);
    AssertTrue('now expanded', P.Expanded[0]);
    AssertEquals('toggle fired once', 1, Probe.Count);
    AssertEquals('toggle group index', 0, Probe.LastGroup);
    // Setting the same value again should NOT fire.
    P.Expanded[0] := True;
    AssertEquals('no fire when unchanged', 1, Probe.Count);
    P.ToggleGroup(0);
    AssertFalse('collapsed again', P.Expanded[0]);
    AssertEquals('toggle fired twice', 2, Probe.Count);
  finally
    Probe.Free;
  end;
end;

procedure TTyListGroupPanelTest.TestSelectItemFiresItemClick;
var
  P: TTyListGroupPanel;
  Probe: TItemProbe;
begin
  P := TTyListGroupPanel.Create(FForm);
  P.Parent := FForm;
  P.Font.PixelsPerInch := 96;
  P.AddGroup('G0');
  P.AddItem(0, 'a'); P.AddItem(0, 'b');
  Probe := TItemProbe.Create;
  try
    P.OnItemClick := @Probe.Handle;
    P.SelectItem(0, 1);
    AssertEquals('selected group', 0, P.SelectedGroup);
    AssertEquals('selected item', 1, P.SelectedItem);
    AssertEquals('itemclick fired once', 1, Probe.Count);
    AssertEquals('itemclick group', 0, Probe.LastGroup);
    AssertEquals('itemclick item', 1, Probe.LastItem);
    // Re-selecting the same item does not fire.
    P.SelectItem(0, 1);
    AssertEquals('no re-fire on same selection', 1, Probe.Count);
    P.SelectItem(0, 0);
    AssertEquals('fires on a new selection', 2, Probe.Count);
  finally
    Probe.Free;
  end;
end;

procedure TTyListGroupPanelTest.TestSelectItemOutOfRangeClears;
var
  P: TTyListGroupPanel;
begin
  P := TTyListGroupPanel.Create(FForm);
  P.Parent := FForm;
  P.Font.PixelsPerInch := 96;
  P.AddGroup('G0');
  P.AddItem(0, 'a');
  P.SelectItem(0, 0);
  AssertEquals('selected 0', 0, P.SelectedItem);
  P.SelectItem(0, 99);   // bad item -> clears
  AssertEquals('bad item clears group', -1, P.SelectedGroup);
  AssertEquals('bad item clears item', -1, P.SelectedItem);
end;

procedure TTyListGroupPanelTest.TestHeaderClickToggles;
var
  P: TPanelAccess;
begin
  P := TPanelAccess.Create(FForm);
  P.Parent := FForm;
  P.Font.PixelsPerInch := 96;
  P.SetBounds(0, 0, 200, 300);
  P.AddGroup('G0');
  P.AddItem(0, 'x');
  AssertFalse('collapsed initially', P.Expanded[0]);
  // Header band is y in [0..26); click at y=10 toggles it.
  P.DoMouseDown(40, 10);
  AssertTrue('header click expanded the group', P.Expanded[0]);
  P.DoMouseDown(40, 10);
  AssertFalse('second header click collapsed it', P.Expanded[0]);
end;

procedure TTyListGroupPanelTest.TestItemClickSelects;
var
  P: TPanelAccess;
begin
  P := TPanelAccess.Create(FForm);
  P.Parent := FForm;
  P.Font.PixelsPerInch := 96;
  P.SetBounds(0, 0, 200, 300);
  P.AddGroup('G0');
  P.AddItem(0, 'x'); P.AddItem(0, 'y');
  P.Expanded[0] := True;
  // Layout: header 0..26, item0 26..50, item1 50..74. Click item1 at y=60.
  P.DoMouseDown(40, 60);
  AssertEquals('clicked item group', 0, P.SelectedGroup);
  AssertEquals('clicked item index 1', 1, P.SelectedItem);
end;

procedure TTyListGroupPanelTest.TestCollapsedGroupHasNoItemHits;
var
  P: TPanelAccess;
begin
  P := TPanelAccess.Create(FForm);
  P.Parent := FForm;
  P.Font.PixelsPerInch := 96;
  P.SetBounds(0, 0, 200, 300);
  P.AddGroup('G0');
  P.AddItem(0, 'x');
  P.AddGroup('G1');
  // G0 collapsed: only headers exist. H0 0..26, H1 26..52. y=40 hits H1, not an item.
  P.DoMouseDown(40, 40);
  AssertTrue('clicking below a collapsed group hit its neighbour header (toggled G1)',
    P.Expanded[1]);
  AssertEquals('no item got selected', -1, P.SelectedItem);
end;

procedure TTyListGroupPanelTest.TestWheelScrollsWhenOverflow;
var
  P: TPanelAccess;
  i: Integer;
begin
  P := TPanelAccess.Create(FForm);
  P.Parent := FForm;
  P.Font.PixelsPerInch := 96;
  P.SetBounds(0, 0, 200, 100);   // small viewport
  P.AddGroup('G0');
  for i := 0 to 19 do P.AddItem(0, 'item ' + IntToStr(i));
  P.Expanded[0] := True;         // content = 26 + 20*24 = 506 >> 100 -> overflow
  AssertEquals('starts unscrolled', 0, P.ScrollOffset);
  P.CallWheel(-120);             // wheel down -> offset increases
  AssertTrue('wheel down scrolls', P.ScrollOffset > 0);
  P.CallWheel(120);              // wheel back up
  AssertEquals('wheel up returns to top', 0, P.ScrollOffset);
end;

procedure TTyListGroupPanelTest.TestWheelNoScrollWhenFits;
var
  P: TPanelAccess;
begin
  P := TPanelAccess.Create(FForm);
  P.Parent := FForm;
  P.Font.PixelsPerInch := 96;
  P.SetBounds(0, 0, 200, 300);   // tall viewport
  P.AddGroup('G0');
  P.AddItem(0, 'x'); P.AddItem(0, 'y');
  P.Expanded[0] := True;         // content 26 + 2*24 = 74 < 300 -> fits
  P.CallWheel(-120);
  AssertEquals('no scroll when content fits', 0, P.ScrollOffset);
end;

procedure TTyListGroupPanelTest.TestCollapseClampsScrollOffset;
var
  P: TPanelAccess;
  i: Integer;
begin
  P := TPanelAccess.Create(FForm);
  P.Parent := FForm;
  P.Font.PixelsPerInch := 96;
  P.SetBounds(0, 0, 200, 100);
  P.AddGroup('G0');
  for i := 0 to 19 do P.AddItem(0, 'item ' + IntToStr(i));
  P.Expanded[0] := True;
  P.CallWheel(-120);
  P.CallWheel(-120);
  P.CallWheel(-120);
  AssertTrue('scrolled down before collapse', P.ScrollOffset > 0);
  // Collapsing removes all the items -> content now fits -> offset must clamp back to 0.
  P.Expanded[0] := False;
  AssertEquals('collapse re-clamps the scroll offset to 0', 0, P.ScrollOffset);
end;

procedure TTyListGroupPanelTest.TestClearResets;
var
  P: TTyListGroupPanel;
begin
  P := TTyListGroupPanel.Create(FForm);
  P.Parent := FForm;
  P.Font.PixelsPerInch := 96;
  P.AddGroup('G0');
  P.AddItem(0, 'x');
  P.SelectItem(0, 0);
  P.Clear;
  AssertEquals('cleared group count', 0, P.GroupCount);
  AssertEquals('cleared selection group', -1, P.SelectedGroup);
  AssertEquals('cleared selection item', -1, P.SelectedItem);
  AssertEquals('cleared scroll', 0, P.ScrollOffset);
end;

procedure TTyListGroupPanelTest.TestRenderDoesNotCrash;
var
  P: TPanelAccess;
  Bmp: TBitmap;
begin
  // Smoke test: a themed render with an expanded group + a selection must not raise.
  P := TPanelAccess.Create(FForm);
  P.Parent := FForm;
  P.Font.PixelsPerInch := 96;
  P.SetBounds(0, 0, 200, 160);
  P.AddGroup('Contacts');
  P.AddItem(0, 'Alice'); P.AddItem(0, 'Bob');
  P.AddGroup('Tasks');
  P.Expanded[0] := True;
  P.SelectItem(0, 1);
  Bmp := TBitmap.Create;
  try
    Bmp.SetSize(200, 160);
    P.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 160), 96);
    AssertTrue('render produced a bitmap', (Bmp.Width = 200) and (Bmp.Height = 160));
  finally
    Bmp.Free;
  end;
end;

initialization
  RegisterTest(TTyListGroupMathTest);
  RegisterTest(TTyListGroupPanelTest);
end.
