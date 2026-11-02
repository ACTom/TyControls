unit test.retiredprops;

{$mode objfpc}{$H+}

{ #130 (4.0): the properties 3.x published and 4.0 does not -- CharCase on the numeric edits;
  MaxLength, CharCase and ReadOnly on the pick-only combo boxes; HideSelectionWhenInactive,
  FadeUnfocusedSelection and MinEditorWidth on TTyDrawGrid; MainColumn on a grid's header.
  A form saved by 3.x holds them; it opens, the values are dropped, and what follows each of
  them in the form file is still read. Saved again, the form no longer holds them.
  #192 (4.0): the shell views' list and tree models, a lookup list box's MultiSelect and
  ExtendedSelect, and ChildSizing on the text inputs, the multi-thumb track bars and the
  terminal -- the last one saved as sub-properties, which only a reader hook reads past. }

interface

uses
  Classes, SysUtils, TypInfo, Controls, Forms, StdCtrls, fpcunit, testregistry,
  tyControls.NumericEdit, tyControls.CalcEdit, tyControls.ComboBox, tyControls.ColorBox,
  tyControls.ShellComboBox, tyControls.Grid, tyControls.Edit, tyControls.MaskEdit,
  tyControls.Memo, tyControls.SpinEdit, tyControls.DateTimePicker, tyControls.MultiTrackBar,
  tyControls.Terminal, tyControls.ShellListView, tyControls.ShellTreeView, tyControls.Panel,
  tyControls.ListView, tyControls.DB.Edits, tyControls.DB.Lists;

type
  TRetiredPropertiesTest = class(TTestCase)
  private
    FForm: TForm;
    FNotFound: string;
    procedure NotFound(Reader: TReader; Instance: TPersistent; var PropName: string;
      IsPath: Boolean; var Handled, Skip: Boolean);
    function FromText(const AText: string): TForm;
    function FormText(AHost: TForm): string;
  protected
    procedure TearDown; override;
  published
    procedure TestANumericEditDropsCharCase;
    procedure TestAPickOnlyComboBoxDropsItsEditProperties;
    procedure TestADrawGridDropsItsSelectionAndEditorProperties;
    procedure TestAGridHeaderDropsMainColumn;
    procedure TestTheControlsThatStillPublishThemReadThem;
    procedure TestTheShellViewsDropTheirModels;
    procedure TestALookupListBoxDropsMultiSelect;
    procedure TestTheControlsWithNoChildrenDropChildSizing;
    procedure TestTheReadersOwnHandlerStillHearsTheRest;
  end;

implementation

const
  Head = 'object Form1: TForm' + LineEnding + '  Left = 0' + LineEnding;
  Tail = 'end' + LineEnding;

function TRetiredPropertiesTest.FromText(const AText: string): TForm;
var
  ts: TStringStream;
  bs: TMemoryStream;
begin
  Result := TForm.CreateNew(nil);
  ts := TStringStream.Create(AText);
  bs := TMemoryStream.Create;
  try
    ObjectTextToBinary(ts, bs);
    bs.Position := 0;
    bs.ReadComponent(Result);   // a property it does not know raises EReadError here
  finally
    bs.Free;
    ts.Free;
  end;
end;

function TRetiredPropertiesTest.FormText(AHost: TForm): string;
var
  ms: TMemoryStream;
  ts: TStringStream;
begin
  ms := TMemoryStream.Create;
  ts := TStringStream.Create('');
  try
    ms.WriteComponent(AHost);
    ms.Position := 0;
    ObjectBinaryToText(ms, ts);
    Result := ts.DataString;
  finally
    ts.Free;
    ms.Free;
  end;
end;

procedure TRetiredPropertiesTest.NotFound(Reader: TReader; Instance: TPersistent;
  var PropName: string; IsPath: Boolean; var Handled, Skip: Boolean);
begin
  FNotFound := FNotFound + PropName + ';';
  Handled := True;
  Skip := True;
end;

procedure TRetiredPropertiesTest.TearDown;
begin
  FreeAndNil(FForm);
end;

procedure TRetiredPropertiesTest.TestANumericEditDropsCharCase;
var
  n: TTyNumericEdit;
  c: TTyCalcEdit;
begin
  FForm := FromText(Head +
    '  object N1: TTyNumericEdit' + LineEnding +
    '    CharCase = ecUppercase' + LineEnding +
    '    Width = 120' + LineEnding +
    '  end' + LineEnding +
    '  object C1: TTyCalcEdit' + LineEnding +
    '    CharCase = ecLowerCase' + LineEnding +
    '    Width = 130' + LineEnding +
    '  end' + LineEnding + Tail);
  n := FForm.FindComponent('N1') as TTyNumericEdit;
  c := FForm.FindComponent('C1') as TTyCalcEdit;
  AssertEquals('what follows CharCase is read', 120, n.Width);
  AssertTrue('the value is dropped', n.CharCase = ecNormal);
  AssertEquals('a descendant too', 130, c.Width);
  AssertEquals('and saved again, the form holds no CharCase', 0, Pos('CharCase', FormText(FForm)));
end;

procedure TRetiredPropertiesTest.TestAPickOnlyComboBoxDropsItsEditProperties;
var
  b: TTyColorBox;
  s: TTyShellComboBox;
  txt: string;
begin
  FForm := FromText(Head +
    '  object B1: TTyColorBox' + LineEnding +
    '    MaxLength = 5' + LineEnding +
    '    CharCase = ecLowerCase' + LineEnding +
    '    ReadOnly = True' + LineEnding +
    '    Width = 140' + LineEnding +
    '  end' + LineEnding +
    '  object S1: TTyShellComboBox' + LineEnding +
    '    ReadOnly = True' + LineEnding +
    '    Width = 150' + LineEnding +
    '  end' + LineEnding + Tail);
  b := FForm.FindComponent('B1') as TTyColorBox;
  s := FForm.FindComponent('S1') as TTyShellComboBox;
  AssertEquals('what follows them is read', 140, b.Width);
  AssertEquals('on another pick-only box too', 150, s.Width);
  txt := FormText(FForm);
  AssertEquals('saved again: no MaxLength', 0, Pos('MaxLength', txt));
  AssertEquals('no CharCase', 0, Pos('CharCase', txt));
  AssertEquals('no ReadOnly', 0, Pos('ReadOnly', txt));
end;

procedure TRetiredPropertiesTest.TestADrawGridDropsItsSelectionAndEditorProperties;
var
  g: TTyDrawGrid;
  txt: string;
begin
  FForm := FromText(Head +
    '  object G1: TTyDrawGrid' + LineEnding +
    '    HideSelectionWhenInactive = True' + LineEnding +
    '    FadeUnfocusedSelection = False' + LineEnding +
    '    MinEditorWidth = 40' + LineEnding +
    '    Width = 160' + LineEnding +
    '  end' + LineEnding + Tail);
  g := FForm.FindComponent('G1') as TTyDrawGrid;
  AssertEquals('what follows them is read', 160, g.Width);
  txt := FormText(FForm);
  AssertEquals('saved again: no HideSelectionWhenInactive', 0, Pos('HideSelectionWhenInactive', txt));
  AssertEquals('no FadeUnfocusedSelection', 0, Pos('FadeUnfocusedSelection', txt));
  AssertEquals('no MinEditorWidth', 0, Pos('MinEditorWidth', txt));
end;

procedure TRetiredPropertiesTest.TestAGridHeaderDropsMainColumn;
var
  g: TTyDrawGrid;
begin
  FForm := FromText(Head +
    '  object G1: TTyDrawGrid' + LineEnding +
    '    Header.MainColumn = 1' + LineEnding +
    '    Header.Height = 31' + LineEnding +
    '    Width = 170' + LineEnding +
    '  end' + LineEnding + Tail);
  g := FForm.FindComponent('G1') as TTyDrawGrid;
  AssertEquals('what follows it in the header is read', 31, g.Header.Height);
  AssertEquals('and after the header', 170, g.Width);
  AssertEquals('saved again: no MainColumn', 0, Pos('MainColumn', FormText(FForm)));
end;

{ A published property is read before DefineProperties is asked: the controls that still
  publish one take its value. }
procedure TRetiredPropertiesTest.TestTheControlsThatStillPublishThemReadThem;
var
  cb: TTyComboBox;
  sg: TTyStringGrid;
begin
  FForm := FromText(Head +
    '  object B1: TTyComboBox' + LineEnding +
    '    MaxLength = 5' + LineEnding +
    '    ReadOnly = True' + LineEnding +
    '  end' + LineEnding +
    '  object G1: TTyStringGrid' + LineEnding +
    '    MinEditorWidth = 40' + LineEnding +
    '  end' + LineEnding + Tail);
  cb := FForm.FindComponent('B1') as TTyComboBox;
  sg := FForm.FindComponent('G1') as TTyStringGrid;
  AssertEquals('the editable combo box reads MaxLength', 5, cb.MaxLength);
  AssertTrue('and ReadOnly', cb.ReadOnly);
  AssertEquals('the string grid reads MinEditorWidth', 40, sg.MinEditorWidth);
  FreeAndNil(FForm);
  FForm := FromText(Head +
    '  object P1: TTyPanel' + LineEnding +
    '    ChildSizing.LeftRightSpacing = 6' + LineEnding +
    '  end' + LineEnding +
    '  object L1: TTyListView' + LineEnding +
    '    OwnerData = True' + LineEnding +
    '  end' + LineEnding +
    '  object D1: TTyDBListBox' + LineEnding +
    '    MultiSelect = True' + LineEnding +
    '  end' + LineEnding + Tail);
  AssertEquals('a container reads ChildSizing', 6,
    (FForm.FindComponent('P1') as TTyPanel).ChildSizing.LeftRightSpacing);
  AssertTrue('the list view reads OwnerData', (FForm.FindComponent('L1') as TTyListView).OwnerData);
  AssertTrue('the data-aware list box reads MultiSelect',
    (FForm.FindComponent('D1') as TTyDBListBox).MultiSelect);
end;

procedure TRetiredPropertiesTest.TestTheShellViewsDropTheirModels;
const
  ListProps: array[0..5] of string = ('OwnerData', 'ItemCount', 'Items', 'OnGetItemText',
    'OnGetItemImage', 'OnGetItemGroup');
  TreeProps: array[0..3] of string = ('Items', 'NodeDataSize', 'RootNodeCount', 'OnInitChildren');
var
  l: TTyShellListView;
  t: TTyShellTreeView;
  p, txt: string;
begin
  for p in ListProps do
    AssertNull('TTyShellListView does not publish ' + p, GetPropInfo(TTyShellListView, p));
  for p in TreeProps do
    AssertNull('TTyShellTreeView does not publish ' + p, GetPropInfo(TTyShellTreeView, p));
  FForm := FromText(Head +
    '  object L1: TTyShellListView' + LineEnding +
    '    OwnerData = False' + LineEnding +
    '    ItemCount = 3' + LineEnding +
    '    Items = <>' + LineEnding +
    '    OnGetItemText = L1GetItemText' + LineEnding +
    '    OnGetItemImage = L1GetItemImage' + LineEnding +
    '    OnGetItemGroup = L1GetItemGroup' + LineEnding +
    '    Width = 180' + LineEnding +
    '  end' + LineEnding +
    '  object T1: TTyShellTreeView' + LineEnding +
    '    Items = <>' + LineEnding +
    '    NodeDataSize = 8' + LineEnding +
    '    RootNodeCount = 2' + LineEnding +
    '    OnInitChildren = T1InitChildren' + LineEnding +
    '    Width = 190' + LineEnding +
    '  end' + LineEnding + Tail);
  l := FForm.FindComponent('L1') as TTyShellListView;
  t := FForm.FindComponent('T1') as TTyShellTreeView;
  AssertEquals('what follows them is read', 180, l.Width);
  AssertTrue('the view keeps its own model', l.OwnerData);
  AssertEquals('on the tree too', 190, t.Width);
  txt := FormText(FForm);
  for p in ListProps do
    AssertEquals('saved again: no ' + p, 0, Pos(' ' + p + ' =', txt));
  for p in TreeProps do
    AssertEquals('saved again: no ' + p, 0, Pos(' ' + p + ' =', txt));
end;

procedure TRetiredPropertiesTest.TestALookupListBoxDropsMultiSelect;
var
  b: TTyDBLookupListBox;
  txt: string;
begin
  AssertNull('not published: MultiSelect', GetPropInfo(TTyDBLookupListBox, 'MultiSelect'));
  AssertNull('nor ExtendedSelect', GetPropInfo(TTyDBLookupListBox, 'ExtendedSelect'));
  FForm := FromText(Head +
    '  object B1: TTyDBLookupListBox' + LineEnding +
    '    MultiSelect = True' + LineEnding +
    '    ExtendedSelect = False' + LineEnding +
    '    Width = 150' + LineEnding +
    '  end' + LineEnding + Tail);
  b := FForm.FindComponent('B1') as TTyDBLookupListBox;
  AssertEquals('what follows them is read', 150, b.Width);
  AssertFalse('one row, as a lookup list holds one key', b.MultiSelect);
  txt := FormText(FForm);
  AssertEquals('saved again: no MultiSelect', 0, Pos('MultiSelect', txt));
  AssertEquals('no ExtendedSelect', 0, Pos('ExtendedSelect', txt));
end;

{ LCL saves ChildSizing as sub-properties ('ChildSizing.LeftRightSpacing = 6'), which the reader
  resolves name by name: DefineProperties is never asked about the first one. }
procedure TRetiredPropertiesTest.TestTheControlsWithNoChildrenDropChildSizing;
const
  Kinds: array[0..8] of string = ('TTyEdit', 'TTyMaskEdit', 'TTyDBEdit', 'TTyMemo',
    'TTySpinEdit', 'TTyDateTimePicker', 'TTyMultiTrackBar', 'TTyGradientTrackBar',
    'TTyTerminalView');
var
  i: Integer;
  src: string;
  c: TWinControl;
begin
  src := Head;
  for i := 0 to High(Kinds) do
  begin
    AssertNull(Kinds[i] + ' does not publish ChildSizing',
      GetPropInfo(GetClass(Kinds[i]), 'ChildSizing'));
    src := src +
      '  object C' + IntToStr(i) + ': ' + Kinds[i] + LineEnding +
      '    ChildSizing.LeftRightSpacing = 6' + LineEnding +
      '    ChildSizing.Layout = cclLeftToRightThenTopToBottom' + LineEnding +
      '    Width = ' + IntToStr(100 + i) + LineEnding +
      '  end' + LineEnding;
  end;
  FForm := FromText(src + Tail);
  for i := 0 to High(Kinds) do
  begin
    c := FForm.FindComponent('C' + IntToStr(i)) as TWinControl;
    AssertEquals(Kinds[i] + ': what follows ChildSizing is read', 100 + i, c.Width);
    AssertEquals(Kinds[i] + ': the value is dropped', 0, c.ChildSizing.LeftRightSpacing);
    AssertTrue(Kinds[i] + ': the layout too', c.ChildSizing.Layout = cclNone);
  end;
  AssertEquals('saved again, the form holds no ChildSizing', 0, Pos('ChildSizing', FormText(FForm)));
end;

{ The IDE reads a form with a handler of its own for the properties it does not know, and asks
  the user about each. The ones the control drops never reach it; every other one does, on the
  control and off it, and the handler is the reader's again when the control is read. }
procedure TRetiredPropertiesTest.TestTheReadersOwnHandlerStillHearsTheRest;
var
  ts: TStringStream;
  bs: TMemoryStream;
  r: TReader;
  h: TPropertyNotFoundEvent;
begin
  FForm := TForm.CreateNew(nil);
  ts := TStringStream.Create(Head +
    '  Bogus = 2' + LineEnding +
    '  object E1: TTyEdit' + LineEnding +
    '    ChildSizing.LeftRightSpacing = 6' + LineEnding +
    '    Font.ChildSizing.Gap = 1' + LineEnding +   // not the control's own: the handler's
    '    Stray.Value = 1' + LineEnding +
    '    Width = 120' + LineEnding +
    '  end' + LineEnding +
    '  object E2: TTyEdit' + LineEnding +
    '    Lost = 3' + LineEnding +
    '  end' + LineEnding + Tail);
  bs := TMemoryStream.Create;
  try
    ObjectTextToBinary(ts, bs);
    bs.Position := 0;
    r := TReader.Create(bs, 4096);
    try
      r.OnPropertyNotFound := @NotFound;
      r.ReadRootComponent(FForm);
      AssertEquals('the handler heard the others, not the edit''s ChildSizing',
        'Bogus;ChildSizing;Stray;Lost;', FNotFound);
      h := r.OnPropertyNotFound;
      AssertTrue('and it is the reader''s again', TMethod(h).Data = Pointer(Self));
    finally
      r.Free;
    end;
  finally
    bs.Free;
    ts.Free;
  end;
  AssertEquals('what follows them is read', 120, (FForm.FindComponent('E1') as TTyEdit).Width);
end;

initialization
  RegisterClasses([TTyNumericEdit, TTyCalcEdit, TTyColorBox, TTyShellComboBox, TTyComboBox,
    TTyDrawGrid, TTyStringGrid, TTyEdit, TTyMaskEdit, TTyDBEdit, TTyMemo, TTySpinEdit,
    TTyDateTimePicker, TTyMultiTrackBar, TTyGradientTrackBar, TTyTerminalView, TTyShellListView,
    TTyShellTreeView, TTyPanel, TTyListView, TTyDBListBox, TTyDBLookupListBox]);
  RegisterTest(TRetiredPropertiesTest);
end.
