unit test.keypressfilter;

{$mode objfpc}{$H+}

{ #150: OnKeyPress runs before a typed character goes in, so it can stop it (Key := #0) or
  change it, as on a native edit -- the character was already in. A form's key preview sees
  it first, as LCL's DoKeyPress asks; each character is asked once. TTyMemo raises
  OnUTF8KeyPress while ReadOnly too. }

interface

uses
  Classes, SysUtils, Controls, Forms, LCLType, fpcunit, testregistry,
  tyControls.Edit, tyControls.Memo, tyControls.SpinEdit, tyControls.DateTimePicker;

type
  TKeyPressFilterTest = class(TTestCase)
  private
    FForm: TForm;
    FPresses, FPreviews, FUtf8: Integer;
    procedure Filter(Sender: TObject; var Key: Char);
    procedure DigitFilter(Sender: TObject; var Key: Char);
    procedure StopAll(Sender: TObject; var Key: Char);
    procedure Preview(Sender: TObject; var Key: Char);
    procedure Utf8(Sender: TObject; var UTF8Key: TUTF8Char);
    procedure TypeIn(C: TWinControl; const AChars: string);
    { A character the control took: UTF8Key comes back '', so LCL asks no KeyPress again. }
    procedure CheckTaken(C: TWinControl; const AChar: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAnEdit;
    procedure TestAMemo;
    procedure TestASpinEdit;
    procedure TestADateTimePicker;
    procedure TestTheFormsKeyPreviewComesFirst;
    procedure TestAReadOnlyMemoRaisesOnUTF8KeyPress;
  end;

implementation

type
  TCrack = class(TWinControl);

var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

procedure TKeyPressFilterTest.SetUp;
begin
  NeedWidgetSet;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 300);
  FPresses := 0;
  FPreviews := 0;
  FUtf8 := 0;
end;

procedure TKeyPressFilterTest.TearDown;
begin
  FreeAndNil(FForm);
end;

{ Stops 'x', turns 'a' into 'b'. }
procedure TKeyPressFilterTest.Filter(Sender: TObject; var Key: Char);
begin
  Inc(FPresses);
  if Key = 'x' then Key := #0
  else if Key = 'a' then Key := 'b';
end;

{ Turns '1' into '9', stops '2'. }
procedure TKeyPressFilterTest.DigitFilter(Sender: TObject; var Key: Char);
begin
  Inc(FPresses);
  if Key = '1' then Key := '9'
  else if Key = '2' then Key := #0;
end;

procedure TKeyPressFilterTest.StopAll(Sender: TObject; var Key: Char);
begin
  Inc(FPresses);
  Key := #0;
end;

{ The form's preview stops 'q'. }
procedure TKeyPressFilterTest.Preview(Sender: TObject; var Key: Char);
begin
  Inc(FPreviews);
  if Key = 'q' then Key := #0;
end;

procedure TKeyPressFilterTest.Utf8(Sender: TObject; var UTF8Key: TUTF8Char);
begin
  Inc(FUtf8);
end;

procedure TKeyPressFilterTest.TypeIn(C: TWinControl; const AChars: string);
var
  i: Integer;
  k: TUTF8Char;
begin
  for i := 1 to Length(AChars) do
  begin
    k := AChars[i];
    TCrack(C).UTF8KeyPress(k);
  end;
end;

procedure TKeyPressFilterTest.CheckTaken(C: TWinControl; const AChar: string);
var
  k: TUTF8Char;
begin
  k := AChar;
  TCrack(C).UTF8KeyPress(k);
  AssertEquals(C.ClassName + ': taken, so LCL does not ask KeyPress again', '', string(k));
end;

procedure TKeyPressFilterTest.TestAnEdit;
var
  e: TTyEdit;
begin
  e := TTyEdit.Create(FForm);
  e.Parent := FForm;
  TCrack(e).OnKeyPress := @Filter;
  TypeIn(e, 'axc');
  AssertEquals('x stopped, a changed into b', 'bc', e.Text);
  AssertEquals('each character asked once', 3, FPresses);
  CheckTaken(e, 'd');
end;

procedure TKeyPressFilterTest.TestAMemo;
var
  m: TTyMemo;
begin
  m := TTyMemo.Create(FForm);
  m.Parent := FForm;
  TCrack(m).OnKeyPress := @Filter;
  TypeIn(m, 'axc');
  AssertEquals('x stopped, a changed into b', 'bc', m.Text);
  AssertEquals('each character asked once', 3, FPresses);
  CheckTaken(m, 'd');
end;

procedure TKeyPressFilterTest.TestASpinEdit;
var
  s: TTySpinEdit;
begin
  s := TTySpinEdit.Create(FForm);
  s.Parent := FForm;
  s.MaxValue := 1000;
  s.Value := 0;
  TCrack(s).OnKeyPress := @DigitFilter;
  TypeIn(s, '123');
  AssertTrue('1 changed into 9', Pos('9', s.Text) > 0);
  AssertEquals('2 stopped', 0, Pos('2', s.Text));
  AssertTrue('3 typed', Pos('3', s.Text) > 0);
  AssertEquals('each character asked once', 3, FPresses);
  CheckTaken(s, '4');
end;

procedure TKeyPressFilterTest.TestADateTimePicker;
var
  d: TTyDateTimePicker;
  was: TDateTime;
begin
  d := TTyDateTimePicker.Create(FForm);
  d.Parent := FForm;
  d.DateTime := EncodeDate(2026, 5, 17);
  was := d.DateTime;
  TCrack(d).OnKeyPress := @StopAll;
  TypeIn(d, '12');
  AssertEquals('both digits stopped: the date as it was', was, d.DateTime, 0);
  AssertEquals('each asked once', 2, FPresses);
  TCrack(d).OnKeyPress := nil;
  CheckTaken(d, '3');
end;

procedure TKeyPressFilterTest.TestTheFormsKeyPreviewComesFirst;
var
  e: TTyEdit;
begin
  FForm.KeyPreview := True;
  FForm.OnKeyPress := @Preview;
  e := TTyEdit.Create(FForm);
  e.Parent := FForm;
  TCrack(e).OnKeyPress := @Filter;
  TypeIn(e, 'qc');
  AssertEquals('the preview stopped q', 'c', e.Text);
  AssertEquals('the preview saw both', 2, FPreviews);
  AssertEquals('the edit saw what got past it', 1, FPresses);
end;

procedure TKeyPressFilterTest.TestAReadOnlyMemoRaisesOnUTF8KeyPress;
var
  m: TTyMemo;
begin
  m := TTyMemo.Create(FForm);
  m.Parent := FForm;
  m.ReadOnly := True;
  TCrack(m).OnUTF8KeyPress := @Utf8;
  TCrack(m).OnKeyPress := @Filter;
  TypeIn(m, 'c');
  AssertEquals('OnUTF8KeyPress raised', 1, FUtf8);
  AssertEquals('and OnKeyPress', 1, FPresses);
  AssertEquals('nothing typed in', '', m.Text);
end;

initialization
  RegisterTest(TKeyPressFilterTest);
end.
