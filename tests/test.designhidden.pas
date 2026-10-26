unit test.designhidden;
{ #130: the published properties that could never act on the control that publishes them are
  not published from 4.0 on. 3.0 hid them in the designer and kept them so its forms would
  load; 4.0 drops them. Where a control does use one -- TTyStringGrid's selection and editor
  settings, a ListView's or TreeView's MainColumn, a plain edit's CharCase -- it is still
  published there. A pick-only combo box's Style still lists only the pick-only styles, read off
  the registration source as tests/test.designeditors.pas does. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, TypInfo, fpcunit, testregistry, test.designregistry,
  tyControls.Edit, tyControls.NumericEdit, tyControls.CurrencyEdit, tyControls.CalcEdit,
  tyControls.CalcCurrencyEdit, tyControls.FloatSpinEdit, tyControls.TrackEdit,
  tyControls.DB.Edits, tyControls.ComboBox, tyControls.AdvancedComboBox,
  tyControls.CheckComboBox, tyControls.ColorBox, tyControls.ColorComboBox,
  tyControls.FilterComboBox, tyControls.OfficeComboBox, tyControls.ShellComboBox,
  tyControls.Columns, tyControls.Grid;

type
  TDesignHiddenTest = class(TTestCase)
  private
    function EditorFor(const ABase, AProp: string): string;
  published
    procedure TestNumericEditsDoNotPublishCharCase;
    procedure TestPickOnlyCombosDoNotPublishTheTextProperties;
    procedure TestPickOnlyCombosListOnlyPickOnlyStyles;
    procedure TestTheDrawGridDoesNotPublishWhatOnlyTheStringGridUses;
    procedure TestAGridsHeaderPublishesEverythingButMainColumn;
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

procedure TDesignHiddenTest.TestNumericEditsDoNotPublishCharCase;
const
  { Every final class on TTyCustomNumericEdit: a numeric edit takes digits, a sign and a
    separator, so there is no case to change. }
  CLS: array[0..8] of TClass = (TTyNumericEdit, TTyCurrencyEdit, TTyCalcEdit,
    TTyCalcCurrencyEdit, TTyFloatSpinEdit, TTyTrackEdit, TTyDBNumericEdit, TTyDBCurrencyEdit,
    TTyDBFloatSpinEdit);
var
  c: Integer;
begin
  for c := 0 to High(CLS) do
    AssertFalse(CLS[c].ClassName + '.CharCase', IsPublishedProp(CLS[c], 'CharCase'));
  AssertTrue('a plain edit still publishes it', IsPublishedProp(TTyEdit, 'CharCase'));
end;

procedure TDesignHiddenTest.TestPickOnlyCombosDoNotPublishTheTextProperties;
const
  CLS: array[0..6] of TClass = (TTyAdvancedComboBox, TTyCheckComboBox, TTyColorBox,
    TTyColorComboBox, TTyFilterComboBox, TTyOfficeComboBox, TTyShellComboBox);
  PROPS: array[0..2] of string = ('MaxLength', 'CharCase', 'ReadOnly');
var
  c, p: Integer;
begin
  for c := 0 to High(CLS) do
    for p := 0 to High(PROPS) do
      AssertFalse(CLS[c].ClassName + '.' + PROPS[p], IsPublishedProp(CLS[c], PROPS[p]));
  for p := 0 to High(PROPS) do
    AssertTrue('an editable combo box still publishes ' + PROPS[p],
      IsPublishedProp(TTyComboBox, PROPS[p]));
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

procedure TDesignHiddenTest.TestTheDrawGridDoesNotPublishWhatOnlyTheStringGridUses;
const
  PROPS: array[0..2] of string = ('HideSelectionWhenInactive', 'FadeUnfocusedSelection',
    'MinEditorWidth');
var
  p: Integer;
begin
  for p := 0 to High(PROPS) do
  begin
    AssertFalse('TTyDrawGrid.' + PROPS[p], IsPublishedProp(TTyDrawGrid, PROPS[p]));
    AssertTrue('TTyStringGrid still publishes ' + PROPS[p],
      IsPublishedProp(TTyStringGrid, PROPS[p]));
  end;
end;

procedure TDesignHiddenTest.TestAGridsHeaderPublishesEverythingButMainColumn;
var
  list: PPropList;
  n, i: Integer;
  g: TTyStringGrid;
begin
  AssertFalse('TTyGridHeader.MainColumn', IsPublishedProp(TTyGridHeader, 'MainColumn'));
  AssertTrue('the header ListView and TreeView use still publishes it',
    IsPublishedProp(TTyHeader, 'MainColumn'));
  n := GetPropList(TTyHeader, list);
  try
    for i := 0 to n - 1 do
      if list^[i]^.Name <> 'MainColumn' then
        AssertTrue('and the grid''s header publishes the rest: ' + list^[i]^.Name,
          IsPublishedProp(TTyGridHeader, list^[i]^.Name));
  finally
    FreeMem(list);
  end;
  g := TTyStringGrid.Create(nil);
  try
    AssertTrue('the grid''s header is one', g.Header is TTyGridHeader);
  finally
    g.Free;
  end;
end;

initialization
  RegisterTest(TDesignHiddenTest);
end.
