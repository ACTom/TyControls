unit test.filtercombobox;
{ Phase 7 batch 4 -- headless state/model/event tests for TTyFilterComboBox.

  Written FROM THE PLAN/SPEC CONTRACT ONLY
  (docs/superpowers/plans/2026-07-11-phase7-shellcombos.md +
   docs/superpowers/specs/2026-07-11-phase7-shell-filedialogs-design.md). The
  implementation (source/tyControls.FilterComboBox.pas) is being written
  independently by another agent and is deliberately NOT consulted here, so
  nothing in this file can ratify an implementation bug.

  No windowing: the combo is Create(nil), never parented, never painted, never
  given a Handle. A user pick from the (unbuilt) dropdown is simulated exactly the
  way the real dropdown funnels it -- set ItemIndex, then invoke the protected
  DoSelect -- reached through the TTyFilterComboBoxAccess subclass declared here. }

{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils,
  fpcunit, testregistry,
  tyControls.FileSystem,      { TyFsFilterPatterns -- the cross-check oracle }
  tyControls.ComboBox,        { TTyComboBoxStyle, csDropDownList }
  tyControls.FilterComboBox;  { the unit under test }

type
  { A user pick lands on DoSelect after ItemIndex is set: that is precisely what a
    dropdown row click funnels through. Expose it so a headless test can drive the
    same seam without a real popup window. }
  TTyFilterComboBoxAccess = class(TTyFilterComboBox)
  public
    procedure PickRow(AIndex: Integer);   { set ItemIndex := AIndex; DoSelect }
  end;

  TFilterComboBoxTest = class(TTestCase)
  private
    FChanges: Integer;                    { OnFilterChange fire counter }
    procedure OnFilterChanged(Sender: TObject);
    function MakeTwo: TTyFilterComboBoxAccess;   { 'Text (*.txt)|*.txt|All|*.*' }
  published
    procedure TestFilterParsesTwoRowsDefaultIndexAndMask;
    procedure TestSetFilterIndexUpdatesMaskAndFiresOnce;
    procedure TestUserPickRowZeroSelectsFirstFilterAndFires;
    procedure TestSetFilterDoesNotFireOnFilterChange;
    procedure TestEmptyAndMalformedFilterAreSafe;
    procedure TestMaskAlwaysEqualsFsFilterPatterns;
  end;

implementation

const
  { The task's canonical filter string: caption/pattern pairs 'Text'/'*.txt' + 'All'/'*.*'. }
  FILTER_TWO = 'Text (*.txt)|*.txt|All|*.*';

{ TTyFilterComboBoxAccess }

procedure TTyFilterComboBoxAccess.PickRow(AIndex: Integer);
begin
  ItemIndex := AIndex;   { public setter -> SelectItem (fires OnChange, NOT OnFilterChange) }
  DoSelect;              { the protected user-pick seam (reads Objects[ItemIndex]) }
end;

{ TFilterComboBoxTest }

procedure TFilterComboBoxTest.OnFilterChanged(Sender: TObject);
begin
  Inc(FChanges);
end;

function TFilterComboBoxTest.MakeTwo: TTyFilterComboBoxAccess;
begin
  Result := TTyFilterComboBoxAccess.Create(nil);
  Result.Filter := FILTER_TWO;
end;

procedure TFilterComboBoxTest.TestFilterParsesTwoRowsDefaultIndexAndMask;
var c: TTyFilterComboBoxAccess;
begin
  { Filter := 'Text (*.txt)|*.txt|All|*.*' -> 2 rows; Items[0]='Text (*.txt)';
    default FilterIndex=1; Mask='*.txt'. }
  c := MakeTwo;
  try
    AssertEquals('two filter rows', 2, c.Items.Count);
    AssertEquals('row 0 caption', 'Text (*.txt)', c.Items[0]);
    AssertEquals('row 1 caption', 'All', c.Items[1]);
    AssertEquals('default FilterIndex is 1', 1, c.FilterIndex);
    AssertEquals('mask of the first segment', '*.txt', c.Mask);
    { The 1-based FilterIndex maps to the 0-based selected row. }
    AssertEquals('selected row for FilterIndex 1', 0, c.ItemIndex);
    { Each row carries its model index in Objects[] (the ColorBox anti-desync rule). }
    AssertEquals('row 0 model index payload', 0, PtrInt(c.Items.Objects[0]));
    AssertEquals('row 1 model index payload', 1, PtrInt(c.Items.Objects[1]));
  finally c.Free; end;
end;

procedure TFilterComboBoxTest.TestSetFilterIndexUpdatesMaskAndFiresOnce;
var c: TTyFilterComboBoxAccess;
begin
  { FilterIndex := 2 -> Mask='*.*' AND OnFilterChange fires exactly once. }
  c := MakeTwo;
  try
    FChanges := 0;
    c.OnFilterChange := @OnFilterChanged;
    c.FilterIndex := 2;
    AssertEquals('FilterIndex advanced', 2, c.FilterIndex);
    AssertEquals('mask of the second segment', '*.*', c.Mask);
    AssertEquals('OnFilterChange fired exactly once', 1, FChanges);
  finally c.Free; end;
end;

procedure TFilterComboBoxTest.TestUserPickRowZeroSelectsFirstFilterAndFires;
var c: TTyFilterComboBoxAccess;
begin
  { From FilterIndex=2, simulate a user pick of row 0 (ItemIndex:=0; DoSelect) ->
    FilterIndex=1, Mask='*.txt', OnFilterChange fired. }
  c := MakeTwo;
  try
    c.FilterIndex := 2;                 { move off row 0 so the pick is a real change }
    FChanges := 0;
    c.OnFilterChange := @OnFilterChanged;
    c.PickRow(0);                       { the dropdown-click funnel }
    AssertEquals('picked row 0 -> FilterIndex 1', 1, c.FilterIndex);
    AssertEquals('mask back to first segment', '*.txt', c.Mask);
    AssertEquals('OnFilterChange fired on the pick', 1, FChanges);
  finally c.Free; end;
end;

procedure TFilterComboBoxTest.TestSetFilterDoesNotFireOnFilterChange;
var c: TTyFilterComboBoxAccess;
begin
  { SetFilter is an init/rebuild -- it must NOT fire OnFilterChange (host reads Mask
    directly afterwards). Counter stays 0 across a Filter := ... assignment. }
  c := TTyFilterComboBoxAccess.Create(nil);
  try
    FChanges := 0;
    c.OnFilterChange := @OnFilterChanged;
    c.Filter := FILTER_TWO;             { rebuilds Items + sets ItemIndex under FUpdating }
    AssertEquals('rows built', 2, c.Items.Count);
    AssertEquals('SetFilter is silent', 0, FChanges);
    { A second, different filter is still silent. }
    c.Filter := 'Only (*.dat)|*.dat';
    AssertEquals('re-filter still silent', 0, FChanges);
  finally c.Free; end;
end;

procedure TFilterComboBoxTest.TestEmptyAndMalformedFilterAreSafe;
var c: TTyFilterComboBoxAccess;
begin
  c := TTyFilterComboBoxAccess.Create(nil);
  try
    { Empty filter -> no rows, Mask=''. }
    c.Filter := '';
    AssertEquals('no rows for empty filter', 0, c.Items.Count);
    AssertEquals('empty filter mask', '', c.Mask);
    { A caption with no pipe -> exactly one spec whose Patterns is '' (matches
      TyFsParseFilter's odd-trailing-caption rule); no crash. }
    c.Filter := 'Caption with no pipe';
    AssertEquals('one spec from a pipeless caption', 1, c.Items.Count);
    AssertEquals('pipeless caption text', 'Caption with no pipe', c.Items[0]);
    AssertEquals('pipeless caption has empty mask', '', c.Mask);
  finally c.Free; end;
end;

procedure TFilterComboBoxTest.TestMaskAlwaysEqualsFsFilterPatterns;
var c: TTyFilterComboBoxAccess; k: Integer;
begin
  { Mask must always equal TyFsFilterPatterns(Filter, FilterIndex) -- cross-check the
    control's field against the pure oracle for every valid index. }
  c := MakeTwo;
  try
    for k := 1 to c.Items.Count do
    begin
      c.FilterIndex := k;
      AssertEquals('mask == TyFsFilterPatterns at index ' + IntToStr(k),
        TyFsFilterPatterns(c.Filter, c.FilterIndex), c.Mask);
    end;
  finally c.Free; end;
end;

initialization
  RegisterTest(TFilterComboBoxTest);
end.
