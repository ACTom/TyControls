unit test.onclicklcl;

{$mode objfpc}{$H+}

{ #188: OnClick fires when LCL fires it. A check box clicks on every change of its state, the
  code's too; a radio button when it becomes checked, so a click on one already checked fires
  nothing; a radio group when ItemIndex changes, not for a click on its frame. }

interface

uses
  Classes, SysUtils, Controls, Forms, StdCtrls, fpcunit, testregistry,
  tyControls.CheckBox, tyControls.RadioGroup, tyControls.Grid, tyControls.Popover,
  tyControls.Panel, tyControls.CheckListBox;

type
  TOnClickLclTest = class(TTestCase)
  private
    FForm: TForm;
    FClicks, FChanges: Integer;
    FSeen: TCheckBoxState;
    procedure Clicked(Sender: TObject);
    procedure Changed(Sender: TObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestACheckBoxClicksWhenCodeChangesIt;
    procedure TestAUsersClickOnACheckBoxClicksOnce;
    procedure TestClicksDisabledKeepsOnlyOnChange;
    procedure TestNoClickWhileTheFormIsRead;
    procedure TestARadioButtonClicksWhenItBecomesChecked;
    procedure TestAClickOnACheckedRadioButtonFiresNothing;
    procedure TestARadioGroupClicksOnlyWhenItsChoiceChanges;
    procedure TestTheGridFiltersSelectAllFollowsWithoutClicking;
  end;

implementation

type
  TCheckCrack = class(TTyCheckBox);
  TRadioCrack = class(TTyRadioButton);
  TCompCrack = class(TComponent);
  TGroupCrack = class(TTyRadioGroup);
  TGridCrack = class(TTyStringGrid);

var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

procedure TOnClickLclTest.SetUp;
begin
  NeedWidgetSet;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 300, 300);
  FClicks := 0;
  FChanges := 0;
end;

procedure TOnClickLclTest.TearDown;
begin
  FreeAndNil(FForm);
end;

procedure TOnClickLclTest.Clicked(Sender: TObject);
begin
  Inc(FClicks);
  if Sender is TTyCheckBox then FSeen := TTyCheckBox(Sender).State;
end;

procedure TOnClickLclTest.Changed(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TOnClickLclTest.TestACheckBoxClicksWhenCodeChangesIt;
var
  c: TTyCheckBox;
begin
  c := TTyCheckBox.Create(FForm);
  c.Parent := FForm;
  c.OnClick := @Clicked;
  c.OnChange := @Changed;
  c.Checked := True;
  AssertEquals('Checked set from code: OnClick', 1, FClicks);
  AssertEquals('and OnChange', 1, FChanges);
  AssertTrue('with the new state already in', cbChecked = FSeen);
  c.Checked := True;
  AssertEquals('the same value again: nothing', 1, FClicks);
  c.State := cbGrayed;
  AssertEquals('State set from code clicks too', 2, FClicks);
end;

procedure TOnClickLclTest.TestAUsersClickOnACheckBoxClicksOnce;
var
  c: TTyCheckBox;
begin
  c := TTyCheckBox.Create(FForm);
  c.Parent := FForm;
  c.OnClick := @Clicked;
  TCheckCrack(c).Click;
  AssertTrue('the click checks it', c.Checked);
  AssertEquals('one OnClick, not one for the change and one for the click', 1, FClicks);
  TCheckCrack(c).Click;
  AssertFalse('and unchecks it', c.Checked);
  AssertEquals('again once', 2, FClicks);
end;

procedure TOnClickLclTest.TestClicksDisabledKeepsOnlyOnChange;
var
  c: TTyCheckBox;
  r: TTyRadioButton;
begin
  c := TTyCheckBox.Create(FForm);
  c.Parent := FForm;
  c.OnClick := @Clicked;
  c.OnChange := @Changed;
  TCheckCrack(c).ClicksDisabled := True;
  c.Checked := True;
  AssertEquals('ClicksDisabled: no OnClick', 0, FClicks);
  AssertEquals('but OnChange', 1, FChanges);
  r := TTyRadioButton.Create(FForm);
  r.Parent := FForm;
  r.OnClick := @Clicked;
  TRadioCrack(r).ClicksDisabled := True;
  r.Checked := True;
  AssertEquals('nor for a radio button', 0, FClicks);
end;

procedure TOnClickLclTest.TestNoClickWhileTheFormIsRead;
var
  c: TTyCheckBox;
begin
  c := TTyCheckBox.Create(FForm);
  c.Parent := FForm;
  c.OnClick := @Clicked;
  TCompCrack(c).Loading;
  c.Checked := True;
  TCompCrack(c).Loaded;
  AssertTrue('read', c.Checked);
  AssertEquals('no OnClick while the form is read', 0, FClicks);
end;

procedure TOnClickLclTest.TestARadioButtonClicksWhenItBecomesChecked;
var
  a, b: TTyRadioButton;
  bClicks: Integer;
begin
  a := TTyRadioButton.Create(FForm);
  a.Parent := FForm;
  b := TTyRadioButton.Create(FForm);
  b.Parent := FForm;
  a.Checked := True;
  a.OnClick := @Clicked;
  a.OnChange := @Changed;
  b.Checked := True;   // unchecks a
  AssertFalse('setup: a is unchecked by b', a.Checked);
  AssertEquals('the one unchecked fires no OnClick', 0, FClicks);
  AssertEquals('only OnChange', 1, FChanges);
  a.Checked := True;
  AssertEquals('checked from code: OnClick', 1, FClicks);
  bClicks := FClicks;
  b.OnClick := @Clicked;
  b.Checked := False;
  AssertEquals('unchecked from code: no OnClick', bClicks, FClicks);
end;

procedure TOnClickLclTest.TestAClickOnACheckedRadioButtonFiresNothing;
var
  a: TTyRadioButton;
begin
  a := TTyRadioButton.Create(FForm);
  a.Parent := FForm;
  a.OnClick := @Clicked;
  TRadioCrack(a).Click;
  AssertTrue('the click checks it', a.Checked);
  AssertEquals('one OnClick', 1, FClicks);
  TRadioCrack(a).Click;
  AssertEquals('a click on it now that it is checked: none', 1, FClicks);
end;

procedure TOnClickLclTest.TestARadioGroupClicksOnlyWhenItsChoiceChanges;
var
  g: TTyRadioGroup;
begin
  g := TTyRadioGroup.Create(FForm);
  g.Parent := FForm;
  g.SetBounds(0, 0, 200, 150);
  g.Items.Text := 'a' + LineEnding + 'b';
  g.OnClick := @Clicked;
  TGroupCrack(g).Click;   // a click on the frame, the caption or an empty area
  AssertEquals('a click that chooses nothing: no OnClick', 0, FClicks);
  g.ItemIndex := 1;
  AssertEquals('a new choice: OnClick', 1, FClicks);
  g.ItemIndex := 1;
  AssertEquals('the same one: none', 1, FClicks);
end;

{ The grid's column filter keeps its Select all box in step with the list from code. That
  change is no click of the user's: it used to be no click at all, and now that a change of
  Checked clicks, the box's handler -- check or uncheck every value -- must not run for it. }
procedure TOnClickLclTest.TestTheGridFiltersSelectAllFollowsWithoutClicking;
var
  g: TTyStringGrid;
  i, j, k: Integer;
  pop, panel: TComponent;
  all: TTyCheckBox;
  list: TTyCheckListBox;
begin
  g := TTyStringGrid.Create(FForm);
  g.Parent := FForm;
  g.SetBounds(0, 0, 200, 150);
  g.Header.Columns.Add;
  g.RowCount := 4;
  g.Cells[0, 1] := 'a';
  g.Cells[0, 2] := 'b';
  g.Cells[0, 3] := 'c';
  g.ShowColumnFilterDropDown(0);
  all := nil;
  list := nil;
  for i := 0 to g.ComponentCount - 1 do
    if g.Components[i] is TTyPopover then
    begin
      pop := g.Components[i];
      for j := 0 to pop.ComponentCount - 1 do
        if pop.Components[j] is TTyPanel then
        begin
          panel := pop.Components[j];
          for k := 0 to panel.ComponentCount - 1 do
            if panel.Components[k] is TTyCheckListBox then list := TTyCheckListBox(panel.Components[k])
            else if panel.Components[k] is TTyCheckBox then all := TTyCheckBox(panel.Components[k]);
        end;
    end;
  AssertNotNull('setup: the select-all box', all);
  AssertNotNull('setup: the value list', list);
  AssertTrue('setup: the values, an empty one among them', list.Items.Count >= 3);
  AssertTrue('setup: all ticked', all.Checked);
  list.Checked[1] := False;
  TGridCrack(g).FilterItemChecked(list);   // what a tick in the list runs
  AssertFalse('one value off: Select all follows', all.Checked);
  for i := 0 to list.Items.Count - 1 do
    if i <> 1 then AssertTrue('and the others stay ticked: ' + IntToStr(i), list.Checked[i]);
  TCheckCrack(all).Click;                  // the user ticks Select all
  for i := 0 to list.Items.Count - 1 do
    AssertTrue('the user''s click ticks every value: ' + IntToStr(i), list.Checked[i]);
end;

initialization
  RegisterTest(TOnClickLclTest);
end.
