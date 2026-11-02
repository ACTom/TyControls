unit test.loadevents;

{$mode objfpc}{$H+}

{ #145: no change events while a form is read or torn down, and none for what a control does
  to itself -- the palette a colour box rebuilds, the items a filter or shell combo box makes,
  a mask's placeholder. Those ran before FormCreate, on a half-destroyed form, or on every
  write of a property the documentation says fires nothing. }

interface

uses
  Classes, SysUtils, Controls, Forms, Graphics, LCLType, fpcunit, testregistry,
  tyControls.ComboBox, tyControls.ColorBox, tyControls.ComboBoxEx, tyControls.FilterComboBox,
  tyControls.ShellComboBox, tyControls.Edit, tyControls.MaskEdit, tyControls.CurrencyEdit,
  tyControls.SpinEdit, tyControls.UpDown;

type
  TLoadEventsTest = class(TTestCase)
  private
    FForm: TForm;
    FChanges, FOther: Integer;
    procedure Changed(Sender: TObject);
    procedure Other(Sender: TObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAComboBoxReadsItsItemIndexQuietly;
    procedure TestAColorBoxRebuildsQuietly;
    procedure TestAComboBoxExAppliesItsSavedItemIndexQuietly;
    procedure TestFilterWritesAreQuiet;
    procedure TestDirectoryWritesAreQuiet;
    procedure TestASpaceCharIsNotAnEdit;
    procedure TestADyingEditDoesNotReformat;
    procedure TestADyingSpinEditCommitsNothing;
    procedure TestAnUpDownAssociatedWhileReadIsQuiet;
  end;

implementation

type
  TCrack = class(TWinControl);
  TCompCrack = class(TComponent);

var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

procedure TLoadEventsTest.SetUp;
begin
  NeedWidgetSet;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 300);
  FChanges := 0;
  FOther := 0;
end;

procedure TLoadEventsTest.TearDown;
begin
  FreeAndNil(FForm);
end;

procedure TLoadEventsTest.Changed(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TLoadEventsTest.Other(Sender: TObject);
begin
  Inc(FOther);
end;

procedure TLoadEventsTest.TestAComboBoxReadsItsItemIndexQuietly;
var
  c: TTyComboBox;
begin
  c := TTyComboBox.Create(FForm);
  c.Parent := FForm;
  c.OnChange := @Changed;
  TCompCrack(c).Loading;
  c.Items.Add('a');
  c.Items.Add('b');
  c.ItemIndex := 1;   // the form file's
  TCompCrack(c).Loaded;
  AssertEquals('read', 1, c.ItemIndex);
  AssertEquals('no OnChange while the form is read', 0, FChanges);
end;

procedure TLoadEventsTest.TestAColorBoxRebuildsQuietly;
var
  b: TTyColorBox;
begin
  b := TTyColorBox.Create(FForm);
  b.Parent := FForm;
  b.Selected := clRed;
  b.OnChange := @Changed;
  b.Style := b.Style + [cbExtendedColors];
  AssertEquals('setup: still red', clRed, b.Selected);
  AssertEquals('a new palette that keeps the colour: no OnChange', 0, FChanges);
  b.Style := [cbSystemColors];
  AssertTrue('setup: red is gone', b.Selected <> clRed);
  AssertEquals('one that loses it: one OnChange', 1, FChanges);

  FChanges := 0;
  b := TTyColorBox.Create(FForm);
  b.Parent := FForm;
  b.OnChange := @Changed;
  TCompCrack(b).Loading;
  b.Selected := clBlue;
  b.Style := b.Style + [cbExtendedColors];
  TCompCrack(b).Loaded;
  AssertEquals('read', clBlue, b.Selected);
  AssertEquals('no OnChange while the form is read', 0, FChanges);
end;

procedure TLoadEventsTest.TestAComboBoxExAppliesItsSavedItemIndexQuietly;
var
  c: TTyComboBoxEx;
begin
  c := TTyComboBoxEx.Create(FForm);
  c.Parent := FForm;
  c.OnChange := @Changed;
  TCompCrack(c).Loading;
  c.ItemIndex := 1;   // streamed before ItemsEx, as the reader does it
  c.AddItem('a', -1);
  c.AddItem('b', -1);
  TCompCrack(c).Loaded;
  AssertEquals('the saved selection', 1, c.ItemIndex);
  AssertEquals('applied with no OnChange', 0, FChanges);
end;

procedure TLoadEventsTest.TestFilterWritesAreQuiet;
var
  f: TTyFilterComboBox;
begin
  f := TTyFilterComboBox.Create(FForm);
  f.Parent := FForm;
  f.OnChange := @Changed;
  f.OnFilterChange := @Other;
  f.Filter := 'Text|*.txt|All|*.*';
  AssertEquals('writing Filter: no OnChange', 0, FChanges);

  f := TTyFilterComboBox.Create(FForm);
  f.Parent := FForm;
  f.OnChange := @Changed;
  f.OnFilterChange := @Other;
  TCompCrack(f).Loading;
  f.Filter := 'Text|*.txt|All|*.*';
  f.FilterIndex := 2;
  TCompCrack(f).Loaded;
  AssertEquals('read', 2, f.FilterIndex);
  AssertEquals('no OnChange while the form is read', 0, FChanges);
  AssertEquals('nor OnFilterChange', 0, FOther);
  f.FilterIndex := 1;
  AssertEquals('a FilterIndex the program writes still reports', 1, FOther);
end;

procedure TLoadEventsTest.TestDirectoryWritesAreQuiet;
var
  s: TTyShellComboBox;
begin
  s := TTyShellComboBox.Create(FForm);
  s.Parent := FForm;
  s.OnChange := @Changed;
  s.Directory := GetTempDir;
  AssertTrue('setup: the places are listed', s.Items.Count > 0);
  AssertEquals('writing Directory: no OnChange', 0, FChanges);
end;

procedure TLoadEventsTest.TestASpaceCharIsNotAnEdit;
var
  m: TTyMaskEdit;
begin
  m := TTyMaskEdit.Create(FForm);
  m.Parent := FForm;
  m.Mask := '000-000';
  m.Modified := False;
  m.SpaceChar := '*';
  AssertFalse('a placeholder the program sets is not the user''s edit', m.Modified);

  m := TTyMaskEdit.Create(FForm);
  m.Parent := FForm;
  m.OnChange := @Changed;
  TCompCrack(m).Loading;
  m.Mask := '000-000';
  m.SpaceChar := '*';
  TCompCrack(m).Loaded;
  AssertEquals('no OnChange while the form is read', 0, FChanges);
  AssertFalse('nor Modified', m.Modified);
end;

procedure TLoadEventsTest.TestADyingEditDoesNotReformat;
var
  c: TTyCurrencyEdit;
begin
  c := TTyCurrencyEdit.Create(FForm);
  c.Parent := FForm;
  c.MaxValue := 10;
  c.Value := 5;
  c.OnChange := @Changed;
  TCrack(c).DoEnter;
  c.Text := '50';
  FChanges := 0;
  TCrack(c).DoExit;
  { A blur that only regroups is no change (#159); one that clamps the number is. }
  AssertTrue('setup: the blur clamps, with an OnChange', FChanges > 0);
  TCrack(c).DoEnter;
  c.Text := '50';
  FChanges := 0;
  TCompCrack(c).Destroying;
  TCrack(c).DoExit;
  AssertEquals('the blur its destruction causes: no OnChange', 0, FChanges);
end;

procedure TLoadEventsTest.TestADyingSpinEditCommitsNothing;
var
  s: TTySpinEdit;
  k: TUTF8Char;
begin
  s := TTySpinEdit.Create(FForm);
  s.Parent := FForm;
  s.MaxValue := 100;
  s.Value := 5;
  s.OnChange := @Changed;
  s.OnValueChange := @Other;
  k := '7';
  TCrack(s).UTF8KeyPress(k);
  FChanges := 0;
  TCompCrack(s).Destroying;
  TCrack(s).DoExit;
  AssertEquals('no OnChange on a dying form', 0, FChanges);
  AssertEquals('nor OnValueChange', 0, FOther);

  FChanges := 0;
  FOther := 0;
  s := TTySpinEdit.Create(FForm);
  s.Parent := FForm;
  s.OnChange := @Changed;
  s.OnValueChange := @Other;
  TCompCrack(s).Loading;
  s.MaxValue := 100;
  s.Value := 5;
  TCompCrack(s).Loaded;
  AssertEquals('read', 5, s.Value);
  AssertEquals('no OnChange while the form is read', 0, FChanges);
  AssertEquals('nor OnValueChange', 0, FOther);
end;

procedure TLoadEventsTest.TestAnUpDownAssociatedWhileReadIsQuiet;
var
  e: TTyEdit;
  u: TTyUpDown;
begin
  e := TTyEdit.Create(FForm);
  e.Parent := FForm;
  e.OnChange := @Changed;
  u := TTyUpDown.Create(FForm);
  u.Parent := FForm;
  TCompCrack(e).Loading;
  TCompCrack(u).Loading;
  u.Max := 100;
  u.Position := 5;
  u.Associate := e;   // the reader's fix-up
  TCompCrack(u).Loaded;
  TCompCrack(e).Loaded;
  AssertEquals('the field shows the position', '5', e.Text);
  AssertEquals('with no OnChange while the form is read', 0, FChanges);
end;

initialization
  RegisterTest(TLoadEventsTest);
end.
