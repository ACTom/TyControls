unit test.accessible;
{$mode objfpc}{$H+}
{ tyControls.Accessible, tested on a bare host control -- no chart. The cases
  come from test.advchart.keyboard (the ordered children, the MSAA tree, the
  nodes that outlive nothing, the window that answers WM_GETOBJECT), which
  drove them through a chart; the asserted values are kept, the tree under
  test is a few hand-built TLazAccessibleObjects. The MSAA half is Windows
  only, as the unit is. }
interface
uses Classes, SysUtils, Types, Controls, Forms, LCLType, fpcunit, testregistry,
  {$IFDEF WINDOWS} Windows, {$ENDIF}
  tyControls.Accessible;
type
  TAccHost = class(TWinControl, ITyAccessibleHost)
  public
    SyncCount: Integer;
    FocusedObj: TLazAccessibleObject;
    SelectedObj: TLazAccessibleObject;
    Link: TTyAccessibleLink;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure AccessibleSync;
    function AccessibleFocusedChild: TLazAccessibleObject;
    function AccessibleSelected(AObj: TLazAccessibleObject): Boolean;
    function AccessibleTakeFocus(AObj: TLazAccessibleObject): Boolean;
  end;

  TAccessibleTreeTest = class(TTestCase)
  private
    FHost: TAccHost;
    FRoot: TLazAccessibleObject;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheOrderedChildren;
    procedure TestNoObjectNoChildren;
    procedure TestPreorderWalksDepthFirst;
    procedure TestPreorderRefusesWhatIsNotUnderTheRoot;
    procedure TestTheLinkIsInertUntilAnAssistiveClientAsks;
    procedure TestTheLinkSurvivesAnUnhandledControl;
  end;

{$IFDEF WINDOWS}
  TAccessibleMsaaTest = class(TTestCase)
  private
    FForm: TForm;
    FHost: TAccHost;
    FSeries: TTyAccObjectArray;
    FRows: array[0..1] of TTyAccObjectArray;
    procedure Build;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheRolesAreMsaasOwn;
    procedure TestTheVariantHelpers;
    procedure TestTheMsaaTree;
    procedure TestAnIdIsAPreorderNumber;
    procedure TestNavigationStaysInTheSiblings;
    procedure TestStateIsTheHostsToSay;
    procedure TestACheckBoxIsCheckedNotSelected;
    procedure TestAnInvisibleControlSaysSo;
    procedure TestAccSelectAsksTheHostForTheFocus;
    procedure TestTheFocusIsWhatTheHostHolds;
    procedure TestHitTestFindsTheLastLeaf;
    procedure TestTheTreeIsSyncedBeforeItIsRead;
    procedure TestTheMsaaNodesOutliveNothing;
    procedure TestTheWindowAnswersGetObject;
  end;
{$ENDIF}

implementation

constructor TAccHost.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Link := TTyAccessibleLink.Create(Self);
end;

destructor TAccHost.Destroy;
begin
  Link.Free;
  inherited Destroy;
end;

procedure TAccHost.AccessibleSync;
begin
  Inc(SyncCount);
end;

function TAccHost.AccessibleFocusedChild: TLazAccessibleObject;
begin
  Result := FocusedObj;
end;

function TAccHost.AccessibleSelected(AObj: TLazAccessibleObject): Boolean;
begin
  Result := (AObj <> nil) and (AObj = SelectedObj);
end;

function TAccHost.AccessibleTakeFocus(AObj: TLazAccessibleObject): Boolean;
begin
  { the root is no item; an item takes it }
  Result := (AObj <> nil) and (AObj <> GetAccessibleObject);
  if Result then FocusedObj := AObj;
end;

{ ==================== the tree helpers ==================== }

procedure TAccessibleTreeTest.SetUp;
begin
  inherited SetUp;
  FHost := TAccHost.Create(nil);
  FRoot := TLazAccessibleObject.Create(FHost);
end;

procedure TAccessibleTreeTest.TearDown;
begin
  FRoot.Free;
  FHost.Free;
  inherited TearDown;
end;

procedure TAccessibleTreeTest.TestTheOrderedChildren;
var
  kids, back: TTyAccObjectArray;
  i: Integer;
begin
  kids := TyAccAddChildren(FRoot, 40);
  for i := 0 to High(kids) do kids[i].AccessibleName := IntToStr(i);
  back := TyAccChildren(FRoot);
  AssertEquals(40, Length(back));
  for i := 0 to High(back) do
    AssertEquals('LCL lists them in the order they were filled', IntToStr(i), back[i].AccessibleName);
  { LCL's own indexed walk agrees, read in order }
  for i := 0 to 39 do
    AssertEquals(IntToStr(i), FRoot.GetChildAccessibleObject(i).AccessibleName);
  AssertEquals('pre-order', 7, TyAccPreorderIndex(FRoot, kids[7]));
  AssertTrue(TyAccByPreorder(FRoot, 7) = kids[7]);
  AssertTrue(TyAccByPreorder(FRoot, 40) = nil);
  AssertEquals(-1, TyAccPreorderIndex(FRoot, FRoot));
end;

procedure TAccessibleTreeTest.TestNoObjectNoChildren;
begin
  AssertEquals(0, Length(TyAccChildren(nil)));
  AssertEquals('a leaf', 0, Length(TyAccChildren(FRoot)));
  AssertEquals('nobody to add to', 0, Length(TyAccAddChildren(nil, 3)));
  AssertEquals('none asked for', 0, Length(TyAccAddChildren(FRoot, 0)));
  AssertEquals('a negative count', 0, Length(TyAccAddChildren(FRoot, -2)));
  AssertEquals('and nothing was added', 0, FRoot.GetChildAccessibleObjectsCount);
  AssertTrue(TyAccByPreorder(nil, 0) = nil);
  AssertTrue('a negative index', TyAccByPreorder(FRoot, -1) = nil);
  AssertEquals(-1, TyAccPreorderIndex(nil, FRoot));
  AssertEquals(-1, TyAccPreorderIndex(FRoot, nil));
end;

procedure TAccessibleTreeTest.TestPreorderWalksDepthFirst;
var
  s, r0, r1: TTyAccObjectArray;
  i: Integer;
begin
  { root > s0 (3 rows), s1 (2 rows): s0 is 0, its rows 1..3, s1 4, its rows 5..6 }
  s := TyAccAddChildren(FRoot, 2);
  r0 := TyAccAddChildren(s[0], 3);
  r1 := TyAccAddChildren(s[1], 2);
  AssertEquals('s0', 0, TyAccPreorderIndex(FRoot, s[0]));
  AssertEquals('s0 row 0', 1, TyAccPreorderIndex(FRoot, r0[0]));
  AssertEquals('s0 row 2', 3, TyAccPreorderIndex(FRoot, r0[2]));
  AssertEquals('s1 follows all of s0''s rows', 4, TyAccPreorderIndex(FRoot, s[1]));
  AssertEquals('s1 row 1', 6, TyAccPreorderIndex(FRoot, r1[1]));
  for i := 0 to 6 do
    AssertEquals('the index and the object agree', i,
      TyAccPreorderIndex(FRoot, TyAccByPreorder(FRoot, i)));
  AssertTrue(TyAccByPreorder(FRoot, 4) = s[1]);
  AssertTrue('past the last', TyAccByPreorder(FRoot, 7) = nil);
  AssertEquals('counted from a subtree, its first child is 0', 2,
    TyAccPreorderIndex(s[0], r0[2]));
end;

procedure TAccessibleTreeTest.TestPreorderRefusesWhatIsNotUnderTheRoot;
var
  s, other: TTyAccObjectArray;
  stranger: TLazAccessibleObject;
begin
  s := TyAccAddChildren(FRoot, 2);
  other := TyAccAddChildren(s[1], 1);
  AssertEquals('a sibling subtree is not under s0', -1, TyAccPreorderIndex(s[0], other[0]));
  AssertEquals('nor an ancestor', -1, TyAccPreorderIndex(s[0], FRoot));
  stranger := TLazAccessibleObject.Create(FHost);
  try
    AssertEquals('an object of another tree', -1, TyAccPreorderIndex(FRoot, stranger));
  finally
    stranger.Free;
  end;
end;

procedure TAccessibleTreeTest.TestTheLinkIsInertUntilAnAssistiveClientAsks;
var l: TTyAccessibleLink;
begin
  l := FHost.Link;
  AssertFalse('nobody has asked', l.InUse);
  { nothing to announce to: none of these may raise, and none starts a client }
  l.NotifyFocus(nil);
  l.NotifyFocus(FRoot);
  l.NotifyReorder;
  AssertFalse(l.InUse);
  {$IFDEF WINDOWS}
  AssertTrue('on Windows the root is an IAccessible', l.Root <> nil);
  {$ELSE}
  AssertTrue('elsewhere there is nothing to hand out', l.Root = nil);
  {$ENDIF}
end;

procedure TAccessibleTreeTest.TestTheLinkSurvivesAnUnhandledControl;
begin
  AssertFalse(FHost.HandleAllocated);
  FHost.Link.Attach;
  AssertFalse('no window, nothing hooked', FHost.Link.InUse);
  FHost.Link.Detach;
  FHost.Link.Detach;
  AssertFalse(FHost.Link.InUse);
end;

{$IFDEF WINDOWS}

{ ==================== the MSAA server ==================== }

function NameOf(const A: IAccessible; AChild: LongInt): string;
var p: PWideChar;
begin
  p := nil;
  A.get_accName(TyAccChild(AChild), @p);
  Result := TyAccTakeBstr(p);
end;

function ChildOf(const A: IAccessible; AChild: LongInt): IAccessible;
var
  p: Pointer;
  d: IDispatch;
begin
  Result := nil;
  p := nil;
  if A.get_accChild(TyAccChild(AChild), @p) <> S_OK then Exit;
  Pointer(d) := p;
  Result := d as IAccessible;
end;

function VarDispatch(var V: TTyAccVariant): IAccessible;
var d: IDispatch;
begin
  Result := nil;
  if V.VType <> TyAccVtDispatch then Exit;
  Pointer(d) := V.PVal;
  V := Default(TTyAccVariant);
  Result := d as IAccessible;
end;

function RootOf(AHost: TAccHost): IAccessible;
begin
  Result := AHost.Link.Root as IAccessible;
end;

{ the tree: Host (chart) > series 0 (list, rows a..d), series 1 (list, rows a..c).
  Row names are 'row <series><letter>'. }
procedure TAccessibleMsaaTest.Build;
var
  i: Integer;
begin
  FHost.AccessibleName := 'Chart';
  FHost.AccessibleDescription := 'a chart of two series';
  FHost.AccessibleRole := larChart;
  FSeries := TyAccAddChildren(FHost.GetAccessibleObject, 2);
  for i := 0 to 1 do
  begin
    FSeries[i].AccessibleRole := larListBox;
    FSeries[i].AccessibleName := 'The ' + IntToStr(i) + ' series.';
  end;
  FRows[0] := TyAccAddChildren(FSeries[0], 4);
  FRows[1] := TyAccAddChildren(FSeries[1], 3);
  for i := 0 to 3 do
  begin
    FRows[0][i].AccessibleRole := larListItem;
    FRows[0][i].AccessibleName := 'row 0' + Chr(Ord('a') + i);
    FRows[0][i].Position := Types.Point(10 + 20 * i, 30);
    FRows[0][i].Size := Types.Size(15, 40 + i);
  end;
  for i := 0 to 2 do
  begin
    FRows[1][i].AccessibleRole := larListItem;
    FRows[1][i].AccessibleName := 'row 1' + Chr(Ord('a') + i);
  end;
end;

procedure TAccessibleMsaaTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FHost := TAccHost.Create(FForm);
  FHost.Parent := FForm;
  FHost.SetBounds(5, 6, 200, 100);
  Build;
end;

procedure TAccessibleMsaaTest.TearDown;
begin
  FForm.Free;
  inherited TearDown;
end;

procedure TAccessibleMsaaTest.TestTheRolesAreMsaasOwn;
begin
  { oleacc.h ROLE_SYSTEM_*, written out. larColorPicker is left out: the
    source files it under $38, which oleacc.h names BUTTONDROPDOWN, where its
    own comment says DROPLIST ($2F) }
  AssertEquals('window', $09, TyAccMsaaRole(larWindow));
  AssertEquals('client, the fallback', $0A, TyAccMsaaRole(larUnknown));
  AssertEquals('chart', $11, TyAccMsaaRole(larChart));
  AssertEquals('list', $21, TyAccMsaaRole(larListBox));
  AssertEquals('list item', $22, TyAccMsaaRole(larListItem));
  AssertEquals('outline', $23, TyAccMsaaRole(larTreeView));
  AssertEquals('outline item', $24, TyAccMsaaRole(larTreeItem));
  AssertEquals('push button', $2B, TyAccMsaaRole(larButton));
  AssertEquals('a tool bar button is a push button', $2B, TyAccMsaaRole(larToolBarButton));
  AssertEquals('check button', $2C, TyAccMsaaRole(larCheckBox));
  AssertEquals('radio button', $2D, TyAccMsaaRole(larRadioButton));
  AssertEquals('combo box', $2E, TyAccMsaaRole(larComboBox));
  AssertEquals('text, single line', $2A, TyAccMsaaRole(larTextEditorSingleline));
  AssertEquals('text, multi line', $2A, TyAccMsaaRole(larTextEditorMultiline));
  AssertEquals('static text: label', $29, TyAccMsaaRole(larLabel));
  AssertEquals('static text: text', $29, TyAccMsaaRole(larText));
  AssertEquals('grouping', $14, TyAccMsaaRole(larGroup));
  AssertEquals('tool bar', $16, TyAccMsaaRole(larToolBar));
  AssertEquals('table', $18, TyAccMsaaRole(larGrid));
  AssertEquals('row', $1C, TyAccMsaaRole(larRow));
  AssertEquals('column', $1B, TyAccMsaaRole(larColumn));
  AssertEquals('cell', $1D, TyAccMsaaRole(larCell));
  AssertEquals('scroll bar', $03, TyAccMsaaRole(larScrollBar));
  AssertEquals('grip', $04, TyAccMsaaRole(larResizeGrip));
  AssertEquals('slider', $33, TyAccMsaaRole(larTrackBar));
  AssertEquals('progress bar', $30, TyAccMsaaRole(larProgressIndicator));
  AssertEquals('spin button', $34, TyAccMsaaRole(larSpinner));
  AssertEquals('page tab list', $3C, TyAccMsaaRole(larTabControl));
  AssertEquals('menu bar', $02, TyAccMsaaRole(larMenuBar));
  AssertEquals('menu item', $0C, TyAccMsaaRole(larMenuItem));
  AssertEquals('graphic', $28, TyAccMsaaRole(larImage));
  AssertEquals('animation', $36, TyAccMsaaRole(larAnimation));
  AssertEquals('clock', $3D, TyAccMsaaRole(larClock));
  AssertEquals('a date field is text', $2A, TyAccMsaaRole(larDateField));
end;

procedure TAccessibleMsaaTest.TestTheVariantHelpers;
var v: TTyAccVariant;
begin
  AssertEquals('a VARIANT''s size', 8 + 2 * SizeOf(Pointer), SizeOf(TTyAccVariant));
  v := TyAccChild(5);
  AssertEquals('VT_I4', 3, v.VType);
  AssertEquals(5, v.LVal);
  AssertEquals('0 names the object itself', 0, TyAccChild(TyAccChildSelf).LVal);
  AssertEquals('no BSTR, no text', '', TyAccTakeBstr(nil));
  TyAccClearVariant(v);
  AssertEquals('cleared', TyAccVtEmpty, v.VType);
  AssertEquals(0, v.LVal);
  v := Default(TTyAccVariant);
  v.VType := TyAccVtDispatch;
  v.PVal := nil;
  TyAccClearVariant(v);
  AssertEquals('an empty dispatch clears too', TyAccVtEmpty, v.VType);
end;

procedure TAccessibleMsaaTest.TestTheMsaaTree;
var
  root, s0, it: IAccessible;
  n, x, y, w, h, rx, ry, rw, rh: LongInt;
  v: TTyAccVariant;
  p: PWideChar;
  o: TPoint;
begin
  root := RootOf(FHost);
  AssertEquals(S_OK, root.get_accChildCount(@n));
  AssertEquals('two series', 2, n);
  AssertEquals('Chart', NameOf(root, TyAccChildSelf));
  v := Default(TTyAccVariant);
  AssertEquals(S_OK, root.get_accRole(TyAccChild(TyAccChildSelf), @v));
  AssertEquals('ROLE_SYSTEM_CHART', $11, v.LVal);
  p := nil;
  root.get_accDescription(TyAccChild(TyAccChildSelf), @p);
  AssertEquals('the description', FHost.GetAccessibleObject.AccessibleDescription, TyAccTakeBstr(p));
  AssertEquals('a child by id', 'The 0 series.', NameOf(root, 1));
  s0 := ChildOf(root, 1);
  AssertTrue(s0 <> nil);
  AssertEquals(S_OK, s0.get_accChildCount(@n));
  AssertEquals(4, n);
  s0.get_accRole(TyAccChild(TyAccChildSelf), @v);
  AssertEquals('ROLE_SYSTEM_LIST', $21, v.LVal);
  it := ChildOf(s0, 2);
  AssertEquals('row 0b', NameOf(it, TyAccChildSelf));
  it.get_accRole(TyAccChild(TyAccChildSelf), @v);
  AssertEquals('ROLE_SYSTEM_LISTITEM', $22, v.LVal);
  { a value, when the object has one, and S_FALSE when it has not }
  p := nil;
  AssertEquals('no value', S_FALSE, it.get_accValue(TyAccChild(TyAccChildSelf), @p));
  AssertTrue(p = nil);
  FRows[0][1].AccessibleValue := '42';
  AssertEquals(S_OK, it.get_accValue(TyAccChild(TyAccChildSelf), @p));
  AssertEquals('42', TyAccTakeBstr(p));
  { where it is: the item's place in the control, on the screen }
  o := FHost.ClientOrigin;
  AssertEquals(S_OK, root.accLocation(@rx, @ry, @rw, @rh, TyAccChild(TyAccChildSelf)));
  AssertEquals(S_OK, it.accLocation(@x, @y, @w, @h, TyAccChild(TyAccChildSelf)));
  AssertEquals('the root starts at the client origin', o.X, rx);
  AssertEquals(o.Y, ry);
  AssertEquals(30, x - rx);
  AssertEquals(30, y - ry);
  AssertEquals(15, w);
  AssertEquals(41, h);
  AssertEquals('the root is the client area', FHost.ClientWidth, rw);
  AssertEquals(FHost.ClientHeight, rh);
  AssertEquals('a bad child id', E_INVALIDARG, root.get_accName(TyAccChild(9), @p));
  AssertEquals('the first past the last', E_INVALIDARG, root.get_accName(TyAccChild(3), @p));
  AssertEquals('a child of the root can not be asked for itself', E_INVALIDARG,
    root.get_accChild(TyAccChild(TyAccChildSelf), @p));
end;

procedure TAccessibleMsaaTest.TestAnIdIsAPreorderNumber;
var
  root: IAccessible;
  p: PWideChar;
begin
  root := RootOf(FHost);
  p := nil;
  { -(1 + the pre-order index): series 0 is -1, its rows -2..-5, series 1 -6 }
  AssertEquals('series 0', 'The 0 series.', NameOf(root, -1));
  AssertEquals('series 0, row b', 'row 0b', NameOf(root, -3));
  AssertEquals('series 1', 'The 1 series.', NameOf(root, -6));
  AssertEquals('series 1, row a', 'row 1a', NameOf(root, -7));
  AssertEquals('series 1, row c', 'row 1c', NameOf(root, -9));
  AssertEquals('past the last', E_INVALIDARG, root.get_accName(TyAccChild(-10), @p));
  { only the root answers a negative id }
  AssertEquals('a series does not', E_INVALIDARG,
    ChildOf(root, 1).get_accName(TyAccChild(-1), @p));
end;

procedure TAccessibleMsaaTest.TestNavigationStaysInTheSiblings;
var
  root, s0, it: IAccessible;
  v: TTyAccVariant;
begin
  root := RootOf(FHost);
  s0 := ChildOf(root, 1);
  it := ChildOf(s0, 2);
  v := Default(TTyAccVariant);
  AssertEquals(S_OK, it.accNavigate(TyAccNavNext, TyAccChild(TyAccChildSelf), @v));
  AssertEquals('the next row', 'row 0c', NameOf(VarDispatch(v), TyAccChildSelf));
  AssertEquals(S_OK, it.accNavigate(TyAccNavPrevious, TyAccChild(TyAccChildSelf), @v));
  AssertEquals('the one before', 'row 0a', NameOf(VarDispatch(v), TyAccChildSelf));
  AssertEquals('down is next', S_OK, it.accNavigate(TyAccNavDown, TyAccChild(TyAccChildSelf), @v));
  AssertEquals('row 0c', NameOf(VarDispatch(v), TyAccChildSelf));
  AssertEquals('no sibling past the last', S_FALSE,
    ChildOf(s0, 4).accNavigate(TyAccNavNext, TyAccChild(TyAccChildSelf), @v));
  AssertEquals('none before the first', S_FALSE,
    ChildOf(s0, 1).accNavigate(TyAccNavPrevious, TyAccChild(TyAccChildSelf), @v));
  AssertEquals(S_OK, s0.accNavigate(TyAccNavFirstChild, TyAccChild(TyAccChildSelf), @v));
  AssertEquals('row 0a', NameOf(VarDispatch(v), TyAccChildSelf));
  AssertEquals(S_OK, s0.accNavigate(TyAccNavLastChild, TyAccChild(TyAccChildSelf), @v));
  AssertEquals('row 0d', NameOf(VarDispatch(v), TyAccChildSelf));
  AssertEquals('a leaf has no first child', S_FALSE,
    it.accNavigate(TyAccNavFirstChild, TyAccChild(TyAccChildSelf), @v));
  AssertEquals('the root has no sibling', S_FALSE,
    root.accNavigate(TyAccNavNext, TyAccChild(TyAccChildSelf), @v));
  AssertEquals('a direction MSAA does not have', E_INVALIDARG,
    root.accNavigate(99, TyAccChild(TyAccChildSelf), @v));
end;

procedure TAccessibleMsaaTest.TestStateIsTheHostsToSay;
var
  root, it: IAccessible;
  v: TTyAccVariant;
begin
  root := RootOf(FHost);
  it := ChildOf(ChildOf(root, 1), 2);
  v := Default(TTyAccVariant);
  it.get_accState(TyAccChild(TyAccChildSelf), @v);
  AssertTrue('selectable', (v.LVal and TyAccStateSelectable) <> 0);
  AssertTrue('focusable: an item takes the keyboard', (v.LVal and TyAccStateFocusable) <> 0);
  AssertTrue('not selected', (v.LVal and TyAccStateSelected) = 0);
  FHost.SelectedObj := FRows[0][1];
  it.get_accState(TyAccChild(TyAccChildSelf), @v);
  AssertTrue('selected', (v.LVal and TyAccStateSelected) <> 0);
  AssertTrue('and not checked: it is no check box', (v.LVal and TyAccStateChecked) = 0);
  root.get_accState(TyAccChild(TyAccChildSelf), @v);
  AssertTrue('no tab stop: not focusable', (v.LVal and TyAccStateFocusable) = 0);
  FHost.TabStop := True;
  root.get_accState(TyAccChild(TyAccChildSelf), @v);
  AssertTrue('a tab stop: focusable', (v.LVal and TyAccStateFocusable) <> 0);
  AssertTrue('the root is not selectable', (v.LVal and TyAccStateSelectable) = 0);
  ChildOf(root, 1).get_accState(TyAccChild(TyAccChildSelf), @v);
  AssertTrue('a node with children is not selectable', (v.LVal and TyAccStateSelectable) = 0);
end;

procedure TAccessibleMsaaTest.TestACheckBoxIsCheckedNotSelected;
var
  it: IAccessible;
  v: TTyAccVariant;
begin
  FRows[0][2].AccessibleRole := larCheckBox;
  FHost.SelectedObj := FRows[0][2];
  it := ChildOf(ChildOf(RootOf(FHost), 1), 3);
  v := Default(TTyAccVariant);
  it.get_accState(TyAccChild(TyAccChildSelf), @v);
  AssertTrue('checked', (v.LVal and TyAccStateChecked) <> 0);
  AssertTrue('not selected', (v.LVal and TyAccStateSelected) = 0);
end;

procedure TAccessibleMsaaTest.TestAnInvisibleControlSaysSo;
var
  root: IAccessible;
  v: TTyAccVariant;
begin
  root := RootOf(FHost);
  FHost.TabStop := True;
  FHost.Visible := False;
  v := Default(TTyAccVariant);
  root.get_accState(TyAccChild(TyAccChildSelf), @v);
  AssertTrue('invisible', (v.LVal and TyAccStateInvisible) <> 0);
  AssertTrue('and so not focusable', (v.LVal and TyAccStateFocusable) = 0);
end;

procedure TAccessibleMsaaTest.TestAccSelectAsksTheHostForTheFocus;
var
  root, it: IAccessible;
begin
  root := RootOf(FHost);
  it := ChildOf(ChildOf(root, 1), 2);
  AssertEquals(S_OK, it.accSelect(TyAccSelTakeFocus, TyAccChild(TyAccChildSelf)));
  AssertTrue('accSelect moved the keyboard', FHost.FocusedObj = FRows[0][1]);
  FHost.FocusedObj := nil;
  AssertEquals('the root is no item: the host refuses', S_FALSE,
    root.accSelect(TyAccSelTakeFocus, TyAccChild(TyAccChildSelf)));
  AssertTrue('and the focus stays where it was', FHost.FocusedObj = nil);
  AssertEquals('anything but a focus request is not understood', HResult($80020003),
    it.accSelect(0, TyAccChild(TyAccChildSelf)));
  AssertEquals('a descendant by the events'' id', S_OK,
    root.accSelect(TyAccSelTakeFocus, TyAccChild(-3)));
  AssertTrue(FHost.FocusedObj = FRows[0][1]);
end;

procedure TAccessibleMsaaTest.TestTheFocusIsWhatTheHostHolds;
var
  root: IAccessible;
  v: TTyAccVariant;
begin
  root := RootOf(FHost);
  v := Default(TTyAccVariant);
  { a control that does not hold the keyboard focus has none to report }
  AssertEquals(S_FALSE, root.get_accFocus(@v));
  AssertEquals(TyAccVtEmpty, v.VType);
end;

procedure TAccessibleMsaaTest.TestHitTestFindsTheLastLeaf;
var
  root: IAccessible;
  o: TPoint;
  v: TTyAccVariant;
begin
  root := RootOf(FHost);
  o := FHost.ClientOrigin;
  v := Default(TTyAccVariant);
  { row b: x 30..45, y 30..71 in the client }
  AssertEquals(S_OK, root.accHitTest(o.X + 35, o.Y + 35, @v));
  AssertEquals('row 0b', NameOf(VarDispatch(v), TyAccChildSelf));
  { on the control, on no row: the control itself }
  AssertEquals(S_OK, root.accHitTest(o.X + 2, o.Y + 2, @v));
  AssertEquals(TyAccVtI4, v.VType);
  AssertEquals(TyAccChildSelf, v.LVal);
  { off the control }
  v := Default(TTyAccVariant);
  AssertEquals(S_FALSE, root.accHitTest(o.X - 50, o.Y - 50, @v));
end;

procedure TAccessibleMsaaTest.TestTheTreeIsSyncedBeforeItIsRead;
var
  root: IAccessible;
  n: LongInt;
  before: Integer;
begin
  root := RootOf(FHost);
  before := FHost.SyncCount;
  root.get_accChildCount(@n);
  AssertEquals('the host brings the tree up to date first', before + 1, FHost.SyncCount);
  NameOf(root, 1);
  AssertEquals(before + 2, FHost.SyncCount);
end;

procedure TAccessibleMsaaTest.TestTheMsaaNodesOutliveNothing;
var
  root, row: IAccessible;
  n: LongInt;
  kids: TTyAccObjectArray;
  h: TAccHost;
begin
  h := TAccHost.Create(FForm);
  h.Parent := FForm;
  h.AccessibleName := 'Second';
  kids := TyAccAddChildren(h.GetAccessibleObject, 3);
  TyAccAddChildren(kids[2], 2);
  root := RootOf(h);
  row := ChildOf(ChildOf(root, 3), 1);
  AssertTrue(row <> nil);
  AssertEquals(S_OK, row.get_accChildCount(@n));
  { the tree is rebuilt: a node is a path, read against the new one }
  h.GetAccessibleObject.ClearChildAccessibleObjects;
  TyAccAddChildren(h.GetAccessibleObject, 1);
  AssertEquals('the object it named is gone', TyAccDisconnected, row.get_accChildCount(@n));
  AssertEquals(S_OK, root.get_accChildCount(@n));
  AssertEquals(1, n);
  { the control is gone: every node a client holds says so }
  h.Free;
  AssertEquals('disconnected', TyAccDisconnected, root.get_accChildCount(@n));
  AssertEquals('every node', TyAccDisconnected, row.get_accChildCount(@n));
  root := nil;
  row := nil;
end;

type
  TObjectFromLresult = function(lResult: LRESULT; riid: PGUID; wParam: WPARAM;
    ppvObject: PPointer): HResult; stdcall;

var
  GFocusWnd: HWND;
  GFocusChild: LongInt;
  GFocusCount: Integer;
  GReorderCount: Integer;

procedure AccEventProc(AHook: THandle; AEvent: DWORD; AWnd: HWND;
  AObject, AChild: LongInt; AThread, ATime: DWORD); stdcall;
begin
  if (AWnd = GFocusWnd) and (AObject = TyAccObjIdClient) then
  begin
    if AEvent = TyAccEventFocus then
    begin
      GFocusChild := AChild;
      Inc(GFocusCount);
    end
    else if AEvent = TyAccEventReorder then Inc(GReorderCount);
  end;
end;

function TySetWinEventHook(AMin, AMax: DWORD; AMod: HMODULE; AProc: Pointer;
  AProcess, AThread, AFlags: DWORD): THandle; stdcall;
  external 'user32.dll' name 'SetWinEventHook';
function TyUnhookWinEvent(AHook: THandle): BOOL; stdcall;
  external 'user32.dll' name 'UnhookWinEvent';

procedure TAccessibleMsaaTest.TestTheWindowAnswersGetObject;
const
  IID_IAccessible: TGUID = '{618736E0-3C3D-11CF-810C-00AA00389B71}';
var
  lib: HMODULE;
  fromLresult: TObjectFromLresult;
  lres: LRESULT;
  p: Pointer;
  acc: IAccessible;
  hook: THandle;
begin
  { A WINDOW NEEDS THE WIDGETSET, and initialising it here would move every
    later suite's text onto the real fonts: this runs when something before
    it initialised the widgetset, or when TY_KEYBOARD_WINDOW=1 asks for it
    in a run of its own }
  if not (AppInitialized in Application.Flags) then
  begin
    if SysUtils.GetEnvironmentVariable('TY_KEYBOARD_WINDOW') = '1' then Application.Initialize
    else Ignore('needs an initialised widgetset (TY_KEYBOARD_WINDOW=1)');
  end;
  FForm.HandleNeeded;
  FHost.HandleNeeded;
  AssertTrue('a handle', FHost.HandleAllocated);
  FHost.Link.Attach;
  AssertFalse('nobody has asked yet', FHost.Link.InUse);
  lres := SendMessage(FHost.Handle, $003D, 0, LPARAM(LongInt(TyAccObjIdClient)));
  AssertTrue('WM_GETOBJECT answered', lres > 0);
  AssertTrue('a client asked', FHost.Link.InUse);
  lib := LoadLibrary('oleacc.dll');
  AssertTrue(lib <> 0);
  Pointer(fromLresult) := GetProcAddress(lib, 'ObjectFromLresult');
  p := nil;
  AssertEquals(S_OK, fromLresult(lres, @IID_IAccessible, 0, @p));
  Pointer(acc) := p;
  AssertEquals('Chart', NameOf(acc, TyAccChildSelf));
  AssertEquals('the second series', 'The 1 series.', NameOf(acc, 2));
  { A FOCUS MOVE IS ANNOUNCED: EVENT_OBJECT_FOCUS on the client object, the
    child a descendant's id -(1 + its pre-order index), which the root's own
    get_accName answers }
  GFocusWnd := FHost.Handle;
  GFocusChild := 0;
  GFocusCount := 0;
  GReorderCount := 0;
  hook := TySetWinEventHook(TyAccEventReorder, TyAccEventFocus, 0, @AccEventProc,
    GetCurrentProcessId, 0, 0);
  AssertTrue('a WinEvent hook', hook <> 0);
  try
    FHost.Link.NotifyFocus(FRows[0][0]);
    FHost.Link.NotifyReorder;
    Application.ProcessMessages;
  finally
    TyUnhookWinEvent(hook);
  end;
  AssertTrue('the focus was announced', GFocusCount > 0);
  AssertEquals('as the first row: -(1 + 1)', -2, GFocusChild);
  AssertEquals('the root names that descendant', 'row 0a', NameOf(acc, GFocusChild));
  AssertTrue('and the tree reordering', GReorderCount > 0);
  acc := nil;
  FHost.Link.Detach;
  AssertFalse('unhooked', FHost.Link.InUse);
end;

{$ENDIF}

initialization
  RegisterTest(TAccessibleTreeTest);
  {$IFDEF WINDOWS}
  RegisterTest(TAccessibleMsaaTest);
  {$ENDIF}
end.
