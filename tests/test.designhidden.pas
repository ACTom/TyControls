unit test.designhidden;
{ #130: the published properties that can never act on the control that publishes them are
  hidden from the designer -- they stay published, a form saved with one has to load --
  and where a descendant does use one, it is offered again there. Read off the registration
  source, as tests/test.designeditors.pas does; that unit checks each registration names a
  property the class really publishes. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, fpcunit, testregistry, test.designregistry,
  tyControls.Columns, tyControls.Grid;

type
  TDesignHiddenTest = class(TTestCase)
  private
    function EditorFor(const ABase, AProp: string): string;
  published
    procedure TestNumericEditsHideCharCase;
    procedure TestPickOnlyCombosHideTheTextProperties;
    procedure TestPickOnlyCombosListOnlyPickOnlyStyles;
    procedure TestTheDrawGridHidesWhatOnlyTheStringGridUses;
    procedure TestAGridsHeaderHidesMainColumn;
  end;

implementation

function Squeeze(const S: string): string;
var i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    if S[i] > ' ' then Result := Result + S[i];
end;

{ The editor registered for exactly (ABase, AProp), or '' when there is none. }
function TDesignHiddenTest.EditorFor(const ABase, AProp: string): string;
var
  regs: TStringList;
  i: Integer;
  ty, base, prop, ed: string;
begin
  Result := '';
  regs := TStringList.Create;
  try
    CollectPropertyEditorRegistrations(regs);
    for i := 0 to regs.Count - 1 do
      if SplitEditorRegistration(regs[i], ty, base, prop, ed)
         and SameText(Squeeze(base), ABase) and SameText(Squeeze(prop), AProp) then
        Exit(Squeeze(ed));
  finally
    regs.Free;
  end;
end;

procedure TDesignHiddenTest.TestNumericEditsHideCharCase;
begin
  AssertEquals('TTyCustomNumericEdit.CharCase', 'THiddenPropertyEditor',
    EditorFor('TTyCustomNumericEdit', 'CharCase'));
end;

procedure TDesignHiddenTest.TestPickOnlyCombosHideTheTextProperties;
const
  CLS: array[0..5] of string = ('TTyCustomAdvancedComboBox', 'TTyCustomCheckComboBox', 'TTyCustomColorBox',
    'TTyCustomFilterComboBox', 'TTyCustomOfficeComboBox', 'TTyCustomShellComboBox');
  PROPS: array[0..2] of string = ('MaxLength', 'CharCase', 'ReadOnly');
var
  c, p: Integer;
begin
  for c := 0 to High(CLS) do
    for p := 0 to High(PROPS) do
      AssertEquals(CLS[c] + '.' + PROPS[p], 'THiddenPropertyEditor', EditorFor(CLS[c], PROPS[p]));
end;

procedure TDesignHiddenTest.TestPickOnlyCombosListOnlyPickOnlyStyles;
const
  CLS: array[0..4] of string = ('TTyCustomAdvancedComboBox', 'TTyCustomCheckComboBox',
    'TTyCustomFilterComboBox', 'TTyCustomOfficeComboBox', 'TTyCustomShellComboBox');
var
  c: Integer;
begin
  for c := 0 to High(CLS) do
    AssertEquals(CLS[c] + '.Style', 'TTyPickOnlyComboStyleEditor', EditorFor(CLS[c], 'Style'));
end;

procedure TDesignHiddenTest.TestTheDrawGridHidesWhatOnlyTheStringGridUses;
begin
  AssertEquals('TTyCustomDrawGrid.HideSelectionWhenInactive', 'THiddenPropertyEditor',
    EditorFor('TTyCustomDrawGrid', 'HideSelectionWhenInactive'));
  AssertEquals('TTyCustomDrawGrid.FadeUnfocusedSelection', 'THiddenPropertyEditor',
    EditorFor('TTyCustomDrawGrid', 'FadeUnfocusedSelection'));
  AssertEquals('TTyCustomDrawGrid.MinEditorWidth', 'THiddenPropertyEditor',
    EditorFor('TTyCustomDrawGrid', 'MinEditorWidth'));
  AssertEquals('offered again on TTyStringGrid', 'TBoolPropertyEditor',
    EditorFor('TTyCustomStringGrid', 'HideSelectionWhenInactive'));
  AssertEquals('', 'TBoolPropertyEditor', EditorFor('TTyCustomStringGrid', 'FadeUnfocusedSelection'));
  AssertEquals('', 'TIntegerPropertyEditor', EditorFor('TTyCustomStringGrid', 'MinEditorWidth'));
end;

procedure TDesignHiddenTest.TestAGridsHeaderHidesMainColumn;
var
  g: TTyStringGrid;
begin
  AssertEquals('TTyGridHeader.MainColumn', 'THiddenPropertyEditor',
    EditorFor('TTyGridHeader', 'MainColumn'));
  g := TTyStringGrid.Create(nil);
  try
    AssertTrue('and the grid''s header is one', g.Header is TTyGridHeader);
  finally
    g.Free;
  end;
end;

initialization
  RegisterTest(TDesignHiddenTest);
end.
