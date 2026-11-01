unit test.keyrepeat;

{$mode objfpc}{$H+}

{ #151: TTyButton, TTyCheckBox, TTyRadioButton and TTyToggleSwitch act once per key press, on
  the key-up -- held down, the key's auto-repeat clicked again and again. A quick second click
  is a click too (OnDblClick still fires); it became a double click and was lost. }

interface

uses
  Classes, SysUtils, Controls, Forms, LCLType, LMessages, fpcunit, testregistry,
  tyControls.Button, tyControls.CheckBox, tyControls.ToggleSwitch;

type
  TKeyRepeatTest = class(TTestCase)
  private
    FForm: TForm;
    FClicks, FDblClicks: Integer;
    procedure Clicked(Sender: TObject);
    procedure DblClicked(Sender: TObject);
    procedure Down(C: TWinControl; AKey: Word);
    procedure Up(C: TWinControl; AKey: Word);
    procedure DoubleClick(C: TWinControl);
    procedure CheckHeldSpace(C: TWinControl);
    procedure CheckQuickSecondClick(C: TWinControl);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestButton;
    procedure TestButtonEnter;
    procedure TestCheckBox;
    procedure TestRadioButton;
    procedure TestToggleSwitch;
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

procedure TKeyRepeatTest.SetUp;
begin
  NeedWidgetSet;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 300, 200);
  FForm.Show;
  FClicks := 0;
  FDblClicks := 0;
end;

procedure TKeyRepeatTest.TearDown;
begin
  FreeAndNil(FForm);
end;

procedure TKeyRepeatTest.Clicked(Sender: TObject);
begin
  Inc(FClicks);
end;

procedure TKeyRepeatTest.DblClicked(Sender: TObject);
begin
  Inc(FDblClicks);
end;

procedure TKeyRepeatTest.Down(C: TWinControl; AKey: Word);
var
  k: Word;
begin
  k := AKey;
  TCrack(C).KeyDown(k, []);
end;

procedure TKeyRepeatTest.Up(C: TWinControl; AKey: Word);
var
  k: Word;
begin
  k := AKey;
  TCrack(C).KeyUp(k, []);
end;

procedure TKeyRepeatTest.DoubleClick(C: TWinControl);
const
  At = 10 or (10 shl 16);   // (10, 10)
begin
  C.Perform(LM_LBUTTONDOWN, MK_LBUTTON, At);
  C.Perform(LM_LBUTTONUP, 0, At);
  C.Perform(LM_LBUTTONDBLCLK, MK_LBUTTON, At);
  C.Perform(LM_LBUTTONUP, 0, At);
end;

procedure TKeyRepeatTest.CheckHeldSpace(C: TWinControl);
var
  n: string;
begin
  n := C.ClassName + ': ';
  C.Parent := FForm;
  C.SetBounds(10, 10, 120, 30);
  TCrack(C).OnClick := @Clicked;
  Down(C, VK_SPACE);
  Down(C, VK_SPACE);   // the key's auto-repeat
  Down(C, VK_SPACE);
  AssertEquals(n + 'held down, Space has not clicked', 0, FClicks);
  Up(C, VK_SPACE);
  AssertEquals(n + 'let go, it clicks once', 1, FClicks);
  Up(C, VK_SPACE);
  AssertEquals(n + 'a key-up with no key-down clicks nothing', 1, FClicks);
  Down(C, VK_SPACE);
  TCrack(C).DoExit;
  Up(C, VK_SPACE);
  AssertEquals(n + 'the focus gone with the key down: no click', 1, FClicks);
end;

procedure TKeyRepeatTest.CheckQuickSecondClick(C: TWinControl);
var
  n: string;
begin
  n := C.ClassName + ': ';
  FClicks := 0;
  TCrack(C).OnDblClick := @DblClicked;
  DoubleClick(C);
  AssertEquals(n + 'two quick clicks are two clicks', 2, FClicks);
  AssertEquals(n + 'and a double click', 1, FDblClicks);
end;

procedure TKeyRepeatTest.TestButton;
var
  b: TTyButton;
begin
  b := TTyButton.Create(FForm);
  CheckHeldSpace(b);
  CheckQuickSecondClick(b);
end;

procedure TKeyRepeatTest.TestButtonEnter;
var
  b: TTyButton;
  k: Word;
begin
  b := TTyButton.Create(FForm);
  b.Parent := FForm;
  b.OnClick := @Clicked;
  k := VK_RETURN;
  TCrack(b).KeyDown(k, []);
  AssertEquals('Enter is the focused button''s', 0, k);
  Down(b, VK_RETURN);
  AssertEquals('held down, Enter has not clicked', 0, FClicks);
  Up(b, VK_RETURN);
  AssertEquals('let go, it clicks once', 1, FClicks);
end;

procedure TKeyRepeatTest.TestCheckBox;
var
  c: TTyCheckBox;
begin
  c := TTyCheckBox.Create(FForm);
  CheckHeldSpace(c);
  AssertTrue('the one click checked it', c.Checked);
  CheckQuickSecondClick(c);
  AssertTrue('two more clicks, back where it was', c.Checked);
end;

procedure TKeyRepeatTest.TestRadioButton;
var
  r: TTyRadioButton;
begin
  r := TTyRadioButton.Create(FForm);
  CheckHeldSpace(r);
  AssertTrue('checked', r.Checked);
  { #188: a click on a radio button that is already checked fires nothing, as in LCL. Of two
    quick clicks the first checks it and clicks; the second reaches it and changes nothing. }
  r.Checked := False;
  FClicks := 0;
  TCrack(r).OnDblClick := @DblClicked;
  DoubleClick(r);
  AssertTrue('the first click checked it', r.Checked);
  AssertEquals('one OnClick: the second click found it checked', 1, FClicks);
  AssertEquals('and a double click', 1, FDblClicks);
end;

procedure TKeyRepeatTest.TestToggleSwitch;
var
  t: TTyToggleSwitch;
begin
  t := TTyToggleSwitch.Create(FForm);
  CheckHeldSpace(t);
  AssertTrue('the one key press switched it on', t.Checked);
  CheckQuickSecondClick(t);
  AssertTrue('two more clicks, back where it was', t.Checked);
end;

initialization
  RegisterTest(TKeyRepeatTest);
end.
