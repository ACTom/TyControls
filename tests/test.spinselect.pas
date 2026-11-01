unit test.spinselect;

{$mode objfpc}{$H+}

{ #189: the focus coming to a TTySpinEdit from the keyboard selects its value, as LCL's
  AutoSelect does: the first digit typed replaces it, Backspace clears it, moving the caret
  lets it go. A click in the field puts the caret there instead. }

interface

uses
  Classes, SysUtils, Controls, Forms, Graphics, LCLType, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.SpinEdit;

type
  TSpinSelectTest = class(TTestCase)
  private
    FForm: TForm;
    function NewSpin: TTySpinEdit;
    procedure TypeIn(S: TTySpinEdit; const AText: string);
    procedure Press(S: TTySpinEdit; AKey: Word);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypingOverTheSelectedValueReplacesIt;
    procedure TestBackspaceClearsTheSelectedValue;
    procedure TestAClickInTheFieldKeepsTheValue;
    procedure TestMovingTheCaretLetsTheSelectionGo;
    procedure TestAKeyTheFieldRefusesLeavesTheSelection;
    procedure TestTheSelectedValueIsDrawnSelected;
  end;

implementation

type
  TSpinCrack = class(TTySpinEdit);

var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

procedure TSpinSelectTest.SetUp;
begin
  NeedWidgetSet;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 300, 200);
end;

procedure TSpinSelectTest.TearDown;
begin
  FreeAndNil(FForm);
end;

function TSpinSelectTest.NewSpin: TTySpinEdit;
begin
  Result := TTySpinEdit.Create(FForm);
  Result.Parent := FForm;
  Result.SetBounds(0, 0, 120, 26);
  Result.MaxValue := 1000;
  Result.Value := 42;
end;

procedure TSpinSelectTest.TypeIn(S: TTySpinEdit; const AText: string);
var
  i: Integer;
  k: TUTF8Char;
begin
  for i := 1 to Length(AText) do
  begin
    k := AText[i];
    TSpinCrack(S).UTF8KeyPress(k);
  end;
end;

procedure TSpinSelectTest.Press(S: TTySpinEdit; AKey: Word);
var
  k: Word;
begin
  k := AKey;
  TSpinCrack(S).KeyDown(k, []);
end;

procedure TSpinSelectTest.TestTypingOverTheSelectedValueReplacesIt;
var
  s: TTySpinEdit;
begin
  s := NewSpin;
  TSpinCrack(s).DoEnter;   // the focus from Tab
  TypeIn(s, '7');
  AssertEquals('the first digit replaces the value', '7', TSpinCrack(s).FEditText);
  TypeIn(s, '5');
  AssertEquals('the next one goes after it', '75', TSpinCrack(s).FEditText);
  s.Value := 42;
  TSpinCrack(s).DoEnter;
  TypeIn(s, '-');
  AssertEquals('a sign replaces it too', '-', TSpinCrack(s).FEditText);
end;

procedure TSpinSelectTest.TestBackspaceClearsTheSelectedValue;
var
  s: TTySpinEdit;
begin
  s := NewSpin;
  TSpinCrack(s).DoEnter;
  Press(s, VK_BACK);
  AssertEquals('Backspace clears it', '', TSpinCrack(s).FEditText);
  s.Value := 42;
  TSpinCrack(s).DoEnter;
  Press(s, VK_DELETE);
  AssertEquals('and so does Delete', '', TSpinCrack(s).FEditText);
end;

procedure TSpinSelectTest.TestAClickInTheFieldKeepsTheValue;
var
  s: TTySpinEdit;
begin
  s := NewSpin;
  s.ControlState := s.ControlState + [csLButtonDown];   // the focus from a click
  TSpinCrack(s).DoEnter;
  s.ControlState := s.ControlState - [csLButtonDown];
  TypeIn(s, '7');
  AssertEquals('typed where the caret is', '427', TSpinCrack(s).FEditText);
end;

procedure TSpinSelectTest.TestMovingTheCaretLetsTheSelectionGo;
var
  s: TTySpinEdit;
begin
  s := NewSpin;
  TSpinCrack(s).DoEnter;
  Press(s, VK_LEFT);
  TypeIn(s, '1');
  AssertEquals('Left from the selection: to the start', '142', TSpinCrack(s).FEditText);
  s.Value := 42;
  TSpinCrack(s).DoEnter;
  Press(s, VK_RIGHT);
  TypeIn(s, '1');
  AssertEquals('Right: to the end', '421', TSpinCrack(s).FEditText);
  s.Value := 42;
  TSpinCrack(s).DoEnter;
  Press(s, VK_HOME);
  Press(s, VK_BACK);
  AssertEquals('Home lets it go: Backspace at the start deletes nothing', '42',
    TSpinCrack(s).FEditText);
end;

procedure TSpinSelectTest.TestAKeyTheFieldRefusesLeavesTheSelection;
var
  s: TTySpinEdit;
begin
  s := NewSpin;
  TSpinCrack(s).DoEnter;
  TypeIn(s, 'x');
  AssertEquals('a letter is refused, and the value stays', '42', TSpinCrack(s).FEditText);
  TypeIn(s, '9');
  AssertEquals('still selected: the digit replaces it', '9', TSpinCrack(s).FEditText);
end;

{ Green ink anywhere in a render of S. }
function GreenIn(S: TTySpinEdit): Boolean;
var
  host: TBitmap;
  shot: TBGRABitmap;
  x, y: Integer;
  p: TBGRAPixel;
begin
  Result := False;
  host := TBitmap.Create;
  try
    host.PixelFormat := pf32bit;
    host.SetSize(120, 26);
    host.Canvas.Brush.Color := clWhite;
    host.Canvas.FillRect(0, 0, 120, 26);
    TSpinCrack(S).RenderTo(host.Canvas, Rect(0, 0, 120, 26), 96);
    shot := TBGRABitmap.Create(host);
    try
      for y := 0 to 25 do
        for x := 0 to 119 do
        begin
          p := shot.GetPixel(x, y);
          if (p.green > 150) and (p.red < 110) and (p.blue < 110) then Exit(True);
        end;
    finally
      shot.Free;
    end;
  finally
    host.Free;
  end;
end;

procedure TSpinSelectTest.TestTheSelectedValueIsDrawnSelected;
var
  s: TTySpinEdit;
  c: TTyStyleController;
begin
  { shown, off screen: the band is drawn only for the field that has the focus }
  FForm.SetBounds(-4000, -4000, 300, 200);
  FForm.Visible := True;
  c := TTyStyleController.Create(nil);
  try
    c.LoadThemeCss('TySpinEdit { background: #FFFFFF; color: #000000; border-width: 0px; ' +
      'padding: 0px 4px; } TyTextSelection { background: #00FF00; }');
    s := NewSpin;
    s.Controller := c;
    s.Font.PixelsPerInch := 96;
    s.SetFocus;
    Forms.Application.ProcessMessages;
    AssertTrue('setup: it has the focus', s.Focused);
    AssertTrue('the selected value has the selection band', GreenIn(s));
    Press(s, VK_END);
    AssertFalse('let go, it has none', GreenIn(s));
  finally
    s.Free;
    c.Free;
  end;
end;

initialization
  RegisterTest(TSpinSelectTest);
end.
