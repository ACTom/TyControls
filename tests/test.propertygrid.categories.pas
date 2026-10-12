unit test.propertygrid.categories;
{$mode objfpc}{$H+}

{ The property grid (#65), phase 2 Task 3: categories (plan D3), the name filter (D4), a
  descendant that builds a type's rows its own way (D6 (c)), and the heading rows they rest on
  (TTyValueRow.Heading, plan V4).

  As in the other parts, everything goes in the way the user does it -- a click, a key, the
  triangle, typing -- and the verdicts are read off what the grid shows (the rows on display,
  painted pixels) and off the inspected objects. }

interface

uses
  Classes, SysUtils, TypInfo, LCLType, Controls, Graphics, Forms, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.BuiltinThemes,
  tyControls.ValueListEditor, tyControls.PropertyGrid, tyControls.Button, tyControls.StrConsts,
  test.propertygrid.fixtures;

type
  TPropertyGridCategoriesTest = class(TTestCase)
  private
    FForm: TForm;
    FGrid: TPGGrid;
    FButton, FButton2: TTyButton;
    FAskedCategory: TStringList;   // 'Name=what it arrived as'
    procedure Recategorize(Sender: TObject; AInstance: TPersistent; const APropName: string;
      var ACategory: string);
    function ChildKeys(ARow: TTyValueRow): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestOffTheListIsAsItWas;
    procedure TestTheTopLevelIsGroupedUnderHeadingsInOrder;
    procedure TestEventsHaveTheirOwnHeading;
    procedure TestAHeadingIsNeverEdited;
    procedure TestAHeadingOpensAndClosesAndIsRemembered;
    procedure TestOnGetPropertyCategoryMovesAndInvents;
    procedure TestASubPropertyStaysWithItsParent;
    procedure TestTheRowsWorkAsBeforeUnderAHeading;
    procedure TestSeveralObjectsAreGroupedToo;
  end;

  TPropertyGridFilterTest = class(TTestCase)
  private
    FForm: TForm;
    FGrid: TPGGrid;
    FObj: TPGBasic;
    FButton: TTyButton;
    FAsked: TStringList;
    procedure HideAlpha(Sender: TObject; AInstance: TPersistent; const APropName: string;
      var AShow: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestOnlyTheMatchingRowsIgnoringCase;
    procedure TestASubPropertyMatchOpensTheRowsAboveIt;
    procedure TestAMatchingRowKeepsItsOwnRows;
    procedure TestClearingPutsTheExpansionBack;
    procedure TestTheEventFiltersFirstThenTheText;
    procedure TestWithCategoriesOnlyTheHeadingsWithAMatch;
    procedure TestAFilteredRowIsEditedAsUsual;
  end;

  { D6 (c): a descendant makes the rows of a type its own way. }
  TPropertyGridBuildRowTest = class(TTestCase)
  private
    FForm: TForm;
    FHolder: TPGHolder;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestADescendantTakesOverATypesRow;
  end;

  { The heading row itself, on a plain value list editor and in every built-in theme. }
  TValueListHeadingTest = class(TTestCase)
  published
    procedure TestAHeadingIsNotEditedOnAPlainEditor;
    procedure TestInEveryThemeAHeadingReadsDifferentlyAndIsNotEdited;
  end;

implementation

type
  { Lines (a TStrings) as one line of comma-separated text, Inner (a TPGInner) as one summary row:
    taken over wholesale -- the editor, the rows below (none), the text both ways. }
  TPGShortGrid = class(TPGGrid)
  protected
    procedure BuildPropertyRow(ANode: TTyPropertyNode); override;
    function GetPropertyText(AInstance: TPersistent; APropInfo: PPropInfo;
      var AText: string): Boolean; override;
    function SetPropertyText(AInstance: TPersistent; APropInfo: PPropInfo;
      const AText: string): Boolean; override;
  public
    Built: TStringList;   // the properties whose rows BuildPropertyRow was asked for
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

  TVLEAccess = class(TTyValueListEditor)
  public
    Dialogs: Integer;
    procedure CountDialog(Sender: TObject; ARow: TTyValueRow);
    procedure ClickValueOf(AFlat: Integer);
    procedure Press(AKey: Word; AShift: TShiftState = []);
  end;

function IsStringsProp(APropInfo: PPropInfo): Boolean;
begin
  Result := (APropInfo^.PropType^.Kind = tkClass)
    and GetTypeData(APropInfo^.PropType)^.ClassType.InheritsFrom(TStrings);
end;

constructor TPGShortGrid.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Built := TStringList.Create;
end;

destructor TPGShortGrid.Destroy;
begin
  inherited Destroy;
  Built.Free;
end;

procedure TPGShortGrid.BuildPropertyRow(ANode: TTyPropertyNode);
begin
  Built.Add(ANode.Path);
  if (ANode.Kind = pnkStrings) then
  begin
    ANode.Row.EditorKind := vekText;
    ANode.Row.ReadOnly := False;
    ANode.Row.Value := PropertyRows.ReadText(ANode);
  end
  else if (ANode.Kind = pnkObject) and (ANode.PropInfo^.Name = 'Inner') then
  begin
    ANode.Row.ReadOnly := True;
    ANode.Row.Value := PropertyRows.ReadText(ANode);   // and no rows below it
  end
  else
    inherited BuildPropertyRow(ANode);
end;

function TPGShortGrid.GetPropertyText(AInstance: TPersistent; APropInfo: PPropInfo;
  var AText: string): Boolean;
begin
  Result := True;
  if IsStringsProp(APropInfo) then
    AText := TStrings(GetObjectProp(AInstance, APropInfo)).CommaText
  else if (AInstance is TPGHolder) and (APropInfo^.Name = 'Inner') then
    AText := 'Level ' + IntToStr(TPGHolder(AInstance).Inner.Level)
  else
    Result := inherited GetPropertyText(AInstance, APropInfo, AText);
end;

function TPGShortGrid.SetPropertyText(AInstance: TPersistent; APropInfo: PPropInfo;
  const AText: string): Boolean;
begin
  Result := IsStringsProp(APropInfo);
  if Result then
    TStrings(GetObjectProp(AInstance, APropInfo)).CommaText := AText   // not through the setter
  else
    Result := inherited SetPropertyText(AInstance, APropInfo, AText);
end;

procedure TVLEAccess.ClickValueOf(AFlat: Integer);
var r: TRect;
begin
  r := ItemRect(AFlat);
  MouseDown(mbLeft, [], ClientWidth - 24, (r.Top + r.Bottom) div 2);
  MouseUp(mbLeft, [], ClientWidth - 24, (r.Top + r.Bottom) div 2);
end;

procedure TVLEAccess.CountDialog(Sender: TObject; ARow: TTyValueRow);
begin
  Inc(Dialogs);
end;

procedure TVLEAccess.Press(AKey: Word; AShift: TShiftState);
var k: Word;
begin
  k := AKey;
  KeyDown(k, AShift);
end;

function InList(const AName: string; const ANames: array of string): Boolean;
var i: Integer;
begin
  for i := 0 to High(ANames) do
    if SameText(ANames[i], AName) then Exit(True);
  Result := False;
end;

{ ================================================================ categories }

procedure TPropertyGridCategoriesTest.SetUp;
begin
  FForm := NewHostForm;
  FGrid := TPGGrid.Create(FForm);
  FGrid.Parent := FForm;
  FGrid.SetBounds(0, 0, 440, 720);
  FButton := TTyButton.Create(FForm);
  FButton.Caption := 'probe';
  FButton2 := TTyButton.Create(FForm);
  FButton2.Caption := 'second';
  FAskedCategory := TStringList.Create;
  FForm.Show;
  FGrid.SelectedObject := FButton;
end;

procedure TPropertyGridCategoriesTest.TearDown;
begin
  FForm.Free;
  FAskedCategory.Free;
end;

procedure TPropertyGridCategoriesTest.Recategorize(Sender: TObject; AInstance: TPersistent;
  const APropName: string; var ACategory: string);
begin
  FAskedCategory.Values[APropName] := ACategory;
  AssertSame('asked about the inspected object', FButton, AInstance);
  if APropName = 'Caption' then ACategory := rsTyPropGridCatBehavior
  else if APropName = 'Tag' then ACategory := 'Data'
  else if APropName = 'Hint' then ACategory := 'Advanced'
  else if APropName = 'Name' then ACategory := '';      // empty: Other
end;

function TPropertyGridCategoriesTest.ChildKeys(ARow: TTyValueRow): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to ARow.ChildCount - 1 do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + ARow.Child[i].Key;
  end;
end;

procedure TPropertyGridCategoriesTest.TestOffTheListIsAsItWas;
var i: Integer;
begin
  AssertFalse('off by default', FGrid.ShowCategories);
  AssertTrue('the first row is a property', FGrid.HasRow('Caption'));
  for i := 0 to FGrid.RowCount - 1 do
    AssertFalse('no heading anywhere: ' + FGrid.Row(i).Key, FGrid.Row(i).Heading);
  FGrid.ShowCategories := True;
  FGrid.ShowCategories := False;
  AssertTrue('and back to properties at the top', FGrid.HasRow('Caption'));
  AssertFalse('no heading left', FGrid.HasRow(rsTyPropGridCatLayout));
end;

procedure TPropertyGridCategoriesTest.TestTheTopLevelIsGroupedUnderHeadingsInOrder;
var
  i, k: Integer;
  r: TTyValueRow;
begin
  FGrid.ShowCategories := True;
  AssertEquals('the headings, in their order; no events by default',
    rsTyPropGridCatLayout + ',' + rsTyPropGridCatAppearance + ',' + rsTyPropGridCatBehavior + ','
    + rsTyPropGridCatOther, FGrid.RootKeys);
  for i := 0 to FGrid.RowCount - 1 do
  begin
    r := FGrid.Row(i);
    AssertTrue(r.Key + ' is a heading', r.Heading);
    AssertEquals(r.Key + ' has no value', '', r.Value);
    AssertEquals(r.Key + '''s path', '@' + r.Key, FGrid.RowPath(r));
    for k := 1 to r.ChildCount - 1 do
      AssertTrue(r.Key + ' keeps PropertyOrder (alphabetical): ' + r.Child[k - 1].Key + ' < '
        + r.Child[k].Key, CompareText(r.Child[k - 1].Key, r.Child[k].Key) < 0);
  end;
  r := FGrid.RowAt(rsTyPropGridCatLayout);
  for k := 0 to r.ChildCount - 1 do
    AssertTrue('Layout holds layout properties: ' + r.Child[k].Key, InList(r.Child[k].Key,
      ['Left', 'Top', 'Width', 'Height', 'Align', 'Anchors', 'AutoSize', 'BorderSpacing',
       'Constraints', 'ChildSizing']));
  AssertTrue('Width', FGrid.HasRow(rsTyPropGridCatLayout + '.Width'));
  AssertTrue('Caption', FGrid.HasRow(rsTyPropGridCatAppearance + '.Caption'));
  AssertTrue('Font', FGrid.HasRow(rsTyPropGridCatAppearance + '.Font'));
  AssertTrue('Enabled', FGrid.HasRow(rsTyPropGridCatBehavior + '.Enabled'));
  AssertTrue('Name', FGrid.HasRow(rsTyPropGridCatOther + '.Name'));
  AssertTrue('Tag', FGrid.HasRow(rsTyPropGridCatOther + '.Tag'));
  AssertTrue('a heading shown for the first time is open',
    FGrid.RowAt(rsTyPropGridCatOther).Expanded);
  FGrid.PropertyOrder := poDeclared;
  AssertEquals('declared order inside a heading: Name is TComponent''s first',
    'Name', FGrid.RowAt(rsTyPropGridCatOther).Child[0].Key);
end;

procedure TPropertyGridCategoriesTest.TestEventsHaveTheirOwnHeading;
var r: TTyValueRow; k: Integer;
begin
  FGrid.ShowCategories := True;
  FGrid.TypeFilter := FGrid.TypeFilter + [tkMethod];
  AssertEquals('Events before Other',
    rsTyPropGridCatLayout + ',' + rsTyPropGridCatAppearance + ',' + rsTyPropGridCatBehavior + ','
    + rsTyPropGridCatEvents + ',' + rsTyPropGridCatOther, FGrid.RootKeys);
  r := FGrid.RowAt(rsTyPropGridCatEvents);
  AssertTrue('OnClick is there', FGrid.HasRow(rsTyPropGridCatEvents + '.OnClick'));
  for k := 0 to r.ChildCount - 1 do
    AssertEquals('only events: ' + r.Child[k].Key, 'On', Copy(r.Child[k].Key, 1, 2));
end;

procedure TPropertyGridCategoriesTest.TestAHeadingIsNeverEdited;
var h: TTyValueRow; f: Integer;
begin
  FGrid.ShowCategories := True;
  h := FGrid.RowAt(rsTyPropGridCatAppearance);
  FGrid.ClickValue(h);
  AssertEquals('a click on its value cell opens nothing', -1, FGrid.EditingRow);
  AssertNull('and drops nothing', FGrid.Dropped);
  FGrid.Select(h);
  FGrid.Press(VK_F2);
  AssertEquals('F2 opens nothing', -1, FGrid.EditingRow);
  FGrid.Press(VK_SPACE);
  AssertEquals('Space writes nothing into it', '', h.Value);
  FGrid.SetRowValue(h, 'typed');
  AssertEquals('nor does code', '', h.Value);
  AssertEquals('the button kept its caption', 'probe', FButton.Caption);
  f := FGrid.FlatOf(h);
  FGrid.InvokeRowDialog(f);
  AssertEquals('no dialog either', 0, FGrid.StringsDialogs + FGrid.FontDialogs);
  AssertTrue('open', h.Expanded);
  FGrid.Select(h);
  FGrid.Press(VK_RETURN);
  AssertFalse('Enter closes it', h.Expanded);
  AssertEquals('instead of editing', -1, FGrid.EditingRow);
  FGrid.Press(VK_RETURN);
  AssertTrue('and opens it', h.Expanded);
end;

procedure TPropertyGridCategoriesTest.TestAHeadingOpensAndClosesAndIsRemembered;
begin
  FGrid.ShowCategories := True;
  AssertTrue('every heading starts open: Layout',
    FGrid.ExpandedProperties.IndexOf('@' + rsTyPropGridCatLayout) >= 0);
  AssertTrue('Other', FGrid.ExpandedProperties.IndexOf('@' + rsTyPropGridCatOther) >= 0);
  FGrid.ClickTriangle(FGrid.RowAt(rsTyPropGridCatLayout));
  AssertFalse('the triangle closes it', FGrid.RowAt(rsTyPropGridCatLayout).Expanded);
  AssertTrue('and the list says so',
    FGrid.ExpandedProperties.IndexOf('@' + rsTyPropGridCatLayout) < 0);
  FGrid.SelectedObject := FButton2;
  AssertFalse('still closed on the next button', FGrid.RowAt(rsTyPropGridCatLayout).Expanded);
  AssertTrue('the others still open', FGrid.RowAt(rsTyPropGridCatAppearance).Expanded);
  FGrid.ShowCategories := False;
  FGrid.ShowCategories := True;
  AssertFalse('and after the headings come back', FGrid.RowAt(rsTyPropGridCatLayout).Expanded);
  FGrid.ExpandedProperties.Add('@' + rsTyPropGridCatLayout);
  AssertTrue('the list opens it', FGrid.RowAt(rsTyPropGridCatLayout).Expanded);
end;

procedure TPropertyGridCategoriesTest.TestOnGetPropertyCategoryMovesAndInvents;
begin
  FGrid.OnGetPropertyCategory := @Recategorize;
  FGrid.ShowCategories := True;
  AssertEquals('Caption arrived as Appearance', rsTyPropGridCatAppearance,
    FAskedCategory.Values['Caption']);
  AssertEquals('Tag as Other', rsTyPropGridCatOther, FAskedCategory.Values['Tag']);
  AssertEquals('the application''s own between the built-in ones and Other, by name',
    rsTyPropGridCatLayout + ',' + rsTyPropGridCatAppearance + ',' + rsTyPropGridCatBehavior + ','
    + 'Advanced,Data,' + rsTyPropGridCatOther, FGrid.RootKeys);
  AssertTrue('Caption moved', FGrid.HasRow(rsTyPropGridCatBehavior + '.Caption'));
  AssertFalse('out of Appearance', FGrid.HasRow(rsTyPropGridCatAppearance + '.Caption'));
  AssertEquals('Data holds Tag', 'Tag', ChildKeys(FGrid.RowAt('Data')));
  AssertEquals('Advanced holds Hint', 'Hint', ChildKeys(FGrid.RowAt('Advanced')));
  AssertTrue('an empty category is Other', FGrid.HasRow(rsTyPropGridCatOther + '.Name'));
  AssertTrue('a heading of its own is a heading', FGrid.RowAt('Data').Heading);
end;

procedure TPropertyGridCategoriesTest.TestASubPropertyStaysWithItsParent;
begin
  FGrid.OnGetPropertyCategory := @Recategorize;
  FGrid.ShowCategories := True;
  AssertEquals('asked about the top level only: not Size', '', FAskedCategory.Values['Size']);
  AssertEquals('nor MinWidth', '', FAskedCategory.Values['MinWidth']);
  AssertTrue('Font.Size under Font', FGrid.HasRow(rsTyPropGridCatAppearance + '.Font.Size'));
  AssertTrue('Constraints.MinWidth under Constraints',
    FGrid.HasRow(rsTyPropGridCatLayout + '.Constraints.MinWidth'));
  AssertFalse('Size is no heading''s child', FGrid.HasRow(rsTyPropGridCatAppearance + '.Size'));
end;

procedure TPropertyGridCategoriesTest.TestTheRowsWorkAsBeforeUnderAHeading;
var inst: TPersistent; nm: string;
begin
  FGrid.ShowCategories := True;
  AssertEquals('the path does not hold the heading', 'Font.Size',
    FGrid.RowPath(FGrid.RowAt(rsTyPropGridCatAppearance + '.Font.Size')));
  AssertTrue('PropertyAt', FGrid.PropertyAt(FGrid.RowAt(rsTyPropGridCatAppearance + '.Caption'),
    inst, nm));
  AssertSame('the button', FButton, inst);
  AssertFalse('a heading is no property', FGrid.PropertyAt(FGrid.RowAt(rsTyPropGridCatLayout),
    inst, nm));
  FGrid.TypeInto(FGrid.RowAt(rsTyPropGridCatAppearance + '.Caption'), 'typed');
  AssertEquals('written', 'typed', FButton.Caption);
  FGrid.ExpandedProperties.Add('Font');
  AssertTrue('a property path still expands', FGrid.RowAt(rsTyPropGridCatAppearance + '.Font').Expanded);
  FGrid.TypeInto(FGrid.RowAt(rsTyPropGridCatAppearance + '.Font.Size'), '13');
  AssertEquals('a sub-property too', 13, FButton.Font.Size);
  FGrid.Select(FGrid.RowAt(rsTyPropGridCatAppearance + '.Caption'));
  FGrid.Refresh;
  FGrid.Rebuild;
  AssertSame('the current row survives a rebuild', FGrid.RowAt(rsTyPropGridCatAppearance + '.Caption'),
    FGrid.CurrentRow);
end;

procedure TPropertyGridCategoriesTest.TestSeveralObjectsAreGroupedToo;
begin
  FGrid.ShowCategories := True;
  FGrid.SelectObjects([FButton, FButton2]);
  AssertEquals('the same headings',
    rsTyPropGridCatLayout + ',' + rsTyPropGridCatAppearance + ',' + rsTyPropGridCatBehavior + ','
    + rsTyPropGridCatOther, FGrid.RootKeys);
  AssertEquals('captions differ: empty', '', FGrid.RowAt(rsTyPropGridCatAppearance + '.Caption').Value);
  FGrid.TypeInto(FGrid.RowAt(rsTyPropGridCatAppearance + '.Caption'), 'both');
  AssertEquals('first', 'both', FButton.Caption);
  AssertEquals('second', 'both', FButton2.Caption);
end;

{ ================================================================ filter }

procedure TPropertyGridFilterTest.SetUp;
begin
  FForm := NewHostForm;
  FGrid := TPGGrid.Create(FForm);
  FGrid.Parent := FForm;
  FGrid.SetBounds(0, 0, 440, 720);
  FObj := TPGBasic.Create;
  FButton := TTyButton.Create(FForm);
  FAsked := TStringList.Create;
  FForm.Show;
  FGrid.SelectedObject := FObj;
end;

procedure TPropertyGridFilterTest.TearDown;
begin
  FForm.Free;
  FObj.Free;
  FAsked.Free;
end;

procedure TPropertyGridFilterTest.HideAlpha(Sender: TObject; AInstance: TPersistent;
  const APropName: string; var AShow: Boolean);
begin
  FAsked.Add(APropName);
  if APropName = 'Alpha' then AShow := False;
end;

procedure TPropertyGridFilterTest.TestOnlyTheMatchingRowsIgnoringCase;
begin
  FGrid.FilterText := 'ALP';
  AssertEquals('Alpha alone', 'Alpha', FGrid.ShownKeys);
  FGrid.FilterText := 'Be';
  AssertEquals('beta (lower case on purpose)', 'beta', FGrid.ShownKeys);
  FGrid.FilterText := 'ti';
  AssertEquals('Ratio, Tint, Title', 'Ratio,Tint,Title', FGrid.ShownKeys);
  FGrid.FilterText := 'nothing like it';
  AssertEquals('no row', '', FGrid.ShownKeys);
  AssertTrue('the rows are kept, only hidden', FGrid.RowCount > 0);
  FGrid.FilterText := '';
  AssertTrue('cleared: every row again', FGrid.DisplayRowCount > 15);
end;

procedure TPropertyGridFilterTest.TestASubPropertyMatchOpensTheRowsAboveIt;
var holder: TPGHolder;
begin
  FGrid.SelectedObject := FButton;
  AssertFalse('Font is closed', FGrid.RowAt('Font').Expanded);
  FGrid.FilterText := 'size';
  AssertTrue('Font is opened for its Size', FGrid.RowAt('Font').Expanded);
  AssertTrue('Size is shown', Pos('Font,Size', FGrid.ShownKeys) > 0);
  AssertTrue('Height (Font''s) is not', FGrid.RowAt('Font.Height').Hidden);
  AssertFalse('Caption is not shown', FGrid.FlatOf(FGrid.RowAt('Caption')) >= 0);
  holder := TPGHolder.Create;
  try
    FGrid.SelectedObject := holder;
    FGrid.FilterText := 'pfb';
    AssertEquals('a set''s element: the sets open for it', 'FixedFlags,pfB,Flags,pfB',
      FGrid.ShownKeys);
    FGrid.FilterText := 'capt';
    AssertEquals('an item''s property: the collection and the item open',
      'Items,[0],Caption,[1],Caption', FGrid.ShownKeys);
    FGrid.SelectedObject := nil;
  finally
    holder.Free;
  end;
end;

procedure TPropertyGridFilterTest.TestAMatchingRowKeepsItsOwnRows;
begin
  FGrid.SelectedObject := FButton;
  FGrid.FilterText := 'font';
  AssertFalse('Font itself matches: nothing below it does, it is not opened',
    FGrid.RowAt('Font').Expanded);
  FGrid.ClickTriangle(FGrid.RowAt('Font'));
  AssertTrue('opened by hand, its rows are there', FGrid.FlatOf(FGrid.RowAt('Font.Height')) >= 0);
end;

procedure TPropertyGridFilterTest.TestClearingPutsTheExpansionBack;
var before: string;
begin
  FGrid.SelectedObject := FButton;
  FGrid.ClickTriangle(FGrid.RowAt('Constraints'));
  before := FGrid.ExpandedProperties.CommaText;
  AssertEquals('Constraints alone is open', 'Constraints', before);
  FGrid.FilterText := 'size';
  AssertTrue('Font opened for the search', FGrid.RowAt('Font').Expanded);
  FGrid.FilterText := 'siz';     // typing on
  FGrid.FilterText := '';
  AssertFalse('Font is closed again', FGrid.RowAt('Font').Expanded);
  AssertTrue('Constraints is still open', FGrid.RowAt('Constraints').Expanded);
  AssertEquals('the list is what it was', before, FGrid.ExpandedProperties.CommaText);
end;

procedure TPropertyGridFilterTest.TestTheEventFiltersFirstThenTheText;
begin
  FGrid.OnFilterProperty := @HideAlpha;
  FGrid.FilterText := 'a';
  AssertTrue('the event was asked about Boom, which the text hides anyway',
    FAsked.IndexOf('Boom') >= 0);
  AssertTrue('Ratio has an a', Pos('Ratio', FGrid.ShownKeys) > 0);
  AssertFalse('Alpha has one too, but the event hid it', FGrid.HasRow('Alpha'));
  AssertTrue('beta: case ignored', Pos('beta', FGrid.ShownKeys) > 0);
  AssertEquals('Zeta has an a: shown', True, Pos('Zeta', FGrid.ShownKeys) > 0);
  AssertEquals('Flag', True, Pos('Flag', FGrid.ShownKeys) > 0);
  AssertEquals('Boom has none', 0, Pos('Boom', FGrid.ShownKeys));
end;

procedure TPropertyGridFilterTest.TestWithCategoriesOnlyTheHeadingsWithAMatch;
begin
  FGrid.SelectedObject := FButton;
  FGrid.ShowCategories := True;
  FGrid.ClickTriangle(FGrid.RowAt(rsTyPropGridCatAppearance));   // closed by hand
  FGrid.FilterText := 'caption';
  AssertEquals('the heading with a match, opened for it, and the match',
    rsTyPropGridCatAppearance + ',Caption', FGrid.ShownKeys);
  FGrid.FilterText := '';
  AssertFalse('closed again once the filter is cleared',
    FGrid.RowAt(rsTyPropGridCatAppearance).Expanded);
  AssertTrue('the others as they were', FGrid.RowAt(rsTyPropGridCatLayout).Expanded);
end;

procedure TPropertyGridFilterTest.TestAFilteredRowIsEditedAsUsual;
begin
  FGrid.FilterText := 'ze';
  FGrid.TypeInto(FGrid.RowAt('Zeta'), '42');
  AssertEquals('written', 42, FObj.Zeta);
  FGrid.Select(FGrid.RowAt('Zeta'));
  AssertSame('the current row is the one on display', FGrid.RowAt('Zeta'), FGrid.SelectedRow);
  FGrid.FilterText := '';
  AssertSame('and it stays current when the filter goes', FGrid.RowAt('Zeta'), FGrid.SelectedRow);
end;

{ ================================================================ D6 (c) }

procedure TPropertyGridBuildRowTest.SetUp;
begin
  FForm := NewHostForm;
  FHolder := TPGHolder.Create;
  FForm.Show;
end;

procedure TPropertyGridBuildRowTest.TearDown;
begin
  FForm.Free;
  FHolder.Free;
end;

procedure TPropertyGridBuildRowTest.TestADescendantTakesOverATypesRow;
var g: TPGShortGrid; r: TTyValueRow;
begin
  g := TPGShortGrid.Create(FForm);
  g.Parent := FForm;
  g.SetBounds(0, 0, 440, 720);
  g.SelectedObject := FHolder;
  AssertTrue('asked for every property row', g.Built.IndexOf('Flags') >= 0);
  AssertTrue('the sub-properties too', g.Built.IndexOf('Items[0].Caption') >= 0);
  r := g.RowAt('Lines');
  AssertTrue('Lines is a text row now', r.EditorKind = vekText);
  AssertEquals('in its own spelling', 'one,two', r.Value);
  AssertEquals('Inner: one row, its own summary', 'Level 5', g.RowAt('Inner').Value);
  AssertEquals('with nothing below it', 0, g.RowAt('Inner').ChildCount);
  AssertTrue('the rest is the grid''s own: Flags has its elements', g.RowAt('Flags').ChildCount > 0);
  g.TypeInto(r, 'a,b,c');
  AssertEquals('written its own way', 3, FHolder.Lines.Count);
  AssertEquals('not through the setter', 0, FHolder.LinesSets);
  AssertEquals('read back its own way', 'a,b,c', g.RowAt('Lines').Value);
  g.TypeInto(g.RowAt('Notes'), 'x,y');
  AssertEquals('a list without a setter, too', 'x,y', FHolder.Notes.CommaText);
  FHolder.Inner.Level := 9;
  r := g.RowAt('Inner');
  g.Refresh;
  AssertEquals('Refresh reads it its own way', 'Level 9', g.RowAt('Inner').Value);
  AssertSame('and does not take the rows it left out for a change: nothing rebuilt', r,
    g.RowAt('Inner'));
  g.SelectedObject := nil;
end;

{ ================================================================ heading rows }

procedure TValueListHeadingTest.TestAHeadingIsNotEditedOnAPlainEditor;
var
  f: TForm;
  v: TVLEAccess;
  h, plain, sub: TTyValueRow;
begin
  f := NewHostForm;
  try
    v := TVLEAccess.Create(f);
    v.Parent := f;
    v.SetBounds(0, 0, 400, 300);
    v.KeyOptions := [keyEdit];
    v.OnEditRow := @v.CountDialog;
    h := v.AddRow('Group', 'stays');
    h.Heading := True;
    h.EditorKind := vekDialog;      // whatever it says, a heading is not edited
    sub := h.AddChild('Inside', '1');
    plain := v.AddRow('Plain', 'x');
    v.UpdateRows;
    f.Show;
    v.ClickValueOf(0);
    AssertEquals('a click on a heading opens nothing', -1, v.EditingRow);
    v.BeginEdit(0);
    AssertEquals('nor does BeginEdit', -1, v.EditingRow);
    v.BeginKeyEdit(0);
    AssertEquals('nor a rename', -1, v.EditingRow);
    v.InvokeRowDialog(0);
    AssertEquals('nor its dialog', 0, v.Dialogs);
    v.ItemIndex := 0;
    v.Press(VK_F2);
    AssertEquals('nor F2', -1, v.EditingRow);
    AssertTrue('open', h.Expanded);
    AssertEquals('its row is shown', 3, v.DisplayRowCount);
    v.Press(VK_RETURN);
    AssertFalse('Enter closes it', h.Expanded);
    AssertEquals('instead of editing', -1, v.EditingRow);
    v.Press(VK_RETURN);
    AssertTrue('and opens it', h.Expanded);
    AssertEquals('the value is untouched', 'stays', h.Value);
    v.ClickValueOf(2);
    AssertTrue('a plain row is edited as ever', v.EditingRow = 2);
    v.EndEdit(False);
    sub.Hidden := True;
    v.UpdateRows;
    AssertEquals('a hidden row leaves the list', 2, v.DisplayRowCount);
    AssertEquals('Plain moves up', 'Plain', v.Items[1]);
    AssertSame('(plain)', plain, v.Row(1));
  finally
    f.Free;
  end;
end;

{ Every built-in theme, light and dark: the heading row has its band at rest (a pixel past its
  text differs from the same pixel of a property row, which shows the list's own ground), no
  column divider (the pixel on the divider's column is the band's), and a click on it opens no
  editor. }
procedure TValueListHeadingTest.TestInEveryThemeAHeadingReadsDifferentlyAndIsNotEdited;
var
  names: TStringArray;
  c: TTyStyleController;
  f: TForm;
  g: TPGGrid;
  obj: TPGBasic;
  bmp: TBitmap;
  px: TBGRABitmap;
  i, m, x, splitX, farX, yHead, yRow, diff, divDiff: Integer;
  head, row: TRect;
  hFar, hSplit, rFar, rSplit: TBGRAPixel;
  bad: TStringList;
  where: string;

  function Distance(A, B: TBGRAPixel): Integer;
  begin
    Result := Abs(A.red - B.red) + Abs(A.green - B.green) + Abs(A.blue - B.blue);
  end;

begin
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  c := TTyStyleController.Create(nil);
  f := NewHostForm;
  obj := TPGBasic.Create;
  bmp := TBitmap.Create;
  bad := TStringList.Create;
  try
    g := TPGGrid.Create(f);
    g.Parent := f;
    g.SetBounds(0, 0, 440, 720);
    g.Controller := c;
    f.Show;
    g.ShowCategories := True;
    g.SelectedObject := obj;     // Layout: Width; then Other
    AssertEquals('Layout first, then its Width', rsTyPropGridCatLayout + ',Width',
      Copy(g.ShownKeys, 1, Length(rsTyPropGridCatLayout) + 6));
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(440, 720);
    for i := 0 to High(names) do
      for m := 0 to 1 do
      begin
        c.ThemeName := names[i];
        if m = 0 then c.Mode := 'light' else c.Mode := 'dark';
        where := names[i] + '/' + c.Mode + ': ';
        g.ItemIndex := -1;
        bmp.Canvas.Brush.Color := clFuchsia;   // the sentinel: nothing left unpainted
        bmp.Canvas.FillRect(0, 0, 440, 720);
        g.PaintInto(bmp.Canvas, Rect(0, 0, 440, 720));
        head := g.ItemRect(0);
        row := g.ItemRect(1);
        farX := head.Right - 6;
        yHead := (head.Top + head.Bottom) div 2;
        yRow := (row.Top + row.Bottom) div 2;
        px := TBGRABitmap.Create(bmp);
        try
          { The divider of the property row: a one-pixel line near KeyColumnWidth, where the
            pixel differs from the ones two to either side, which agree. }
          splitX := -1;
          for x := g.KeyColumnWidth - 10 to g.KeyColumnWidth + 30 do
            if (Distance(px.GetPixel(x, yRow), px.GetPixel(x - 2, yRow)) > 0)
              and (Distance(px.GetPixel(x - 2, yRow), px.GetPixel(x + 2, yRow)) <= 1) then
            begin
              splitX := x;
              Break;
            end;
          if splitX < 0 then splitX := g.KeyColumnWidth;
          hFar := px.GetPixel(farX, yHead);
          hSplit := px.GetPixel(splitX, yHead);
          rFar := px.GetPixel(farX, yRow);
          rSplit := px.GetPixel(splitX, yRow);
        finally
          px.Free;
        end;
        diff := Distance(hFar, rFar);
        divDiff := Distance(rSplit, rFar);
        if diff < 12 then
          bad.Add(Format('%sthe heading''s band (%d,%d,%d) is the row''s ground (%d,%d,%d)',
            [where, hFar.red, hFar.green, hFar.blue, rFar.red, rFar.green, rFar.blue]));
        if Distance(hSplit, hFar) > 3 then
          bad.Add(where + 'a divider on the heading');
        if divDiff = 0 then
          bad.Add(where + '(the probe: the property row shows no divider at ' + IntToStr(splitX) + ')');
        g.ClickValue(g.RowAt(rsTyPropGridCatLayout));
        if g.EditingRow >= 0 then
        begin
          bad.Add(where + 'a click opened the heading');
          g.Editor.PressKey(VK_ESCAPE);
        end;
      end;
    AssertEquals(IntToStr(bad.Count) + ' themes fail:' + LineEnding + bad.Text, 0, bad.Count);
    g.SelectedObject := nil;
  finally
    bad.Free;
    bmp.Free;
    obj.Free;
    f.Free;
    c.Free;
  end;
end;

initialization
  RegisterTest(TPropertyGridCategoriesTest);
  RegisterTest(TPropertyGridFilterTest);
  RegisterTest(TPropertyGridBuildRowTest);
  RegisterTest(TValueListHeadingTest);
end.
