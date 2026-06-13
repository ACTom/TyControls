unit test.spinedit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.SpinEdit;
type
  { Probe subclass: exposes protected RenderTo and input handlers }
  TTySpinEditProbe = class(TTySpinEdit)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure SimulateKeyDown(var Key: Word);
    procedure SimulateMouseDown(X, Y: Integer);
    function SimulateWheel(WheelDelta: Integer): Boolean;
  end;

  TChangeCounter = class
  public
    Count: Integer;
    procedure Handle(Sender: TObject);
  end;

  TTySpinEditGeometryTest = class(TTestCase)
  published
    procedure TestUpButtonRectAtPPI96;
    procedure TestDownButtonRect;
    procedure TestButtonsDoNotOverlapAndCoverColumn;
  end;

  TTySpinEditControlTest = class(TTestCase)
  private
    FForm: TForm;
    FSpin: TTySpinEditProbe;
    FCounter: TChangeCounter;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestVKUpIncrements;
    procedure TestVKDownDecrements;
    procedure TestVKUpClampsAtMax;
    procedure TestVKDownClampsAtMin;
    procedure TestWheelUpIncrements;
    procedure TestWheelDownDecrements;
    procedure TestMouseDownUpButton;
    procedure TestMouseDownDownButton;
    procedure TestMouseDownTextAreaNoChange;
    procedure TestOnChangeOnlyOnRealChange;
    procedure TestIncrementUsed;
    procedure TestDisabledKeyIgnored;
    procedure TestDisabledMouseIgnored;
    procedure TestDisabledWheelIgnored;
    procedure TestMinClampReclampsValue;
    procedure TestIncrementClampMinOne;
  end;

  TTySpinEditPixelTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    procedure LoadThemeCss;
  published
    procedure TestUpArrowGlyphRendered;
  end;

implementation

procedure TChangeCounter.Handle(Sender: TObject);
begin
  Inc(Count);
end;

{ TTySpinEditProbe }

procedure TTySpinEditProbe.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TTySpinEditProbe.SimulateKeyDown(var Key: Word);
var
  Shift: TShiftState;
begin
  Shift := [];
  KeyDown(Key, Shift);
end;

procedure TTySpinEditProbe.SimulateMouseDown(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
end;

function TTySpinEditProbe.SimulateWheel(WheelDelta: Integer): Boolean;
begin
  Result := DoMouseWheel([], WheelDelta, Point(0, 0));
end;

{ TTySpinEditGeometryTest }

procedure TTySpinEditGeometryTest.TestUpButtonRectAtPPI96;
{ Bounds 120x28 @96ppi. BtnW = Scale(18) = 18. X0 = 120-18 = 102.
  HalfY = 0 + 28 div 2 = 14. Up = Rect(102, 0, 120, 14). }
var
  R: TRect;
begin
  R := TySpinUpButtonRect(Rect(0, 0, 120, 28), 96);
  AssertEquals('Up Left = 102', 102, R.Left);
  AssertEquals('Up Right = 120', 120, R.Right);
  AssertEquals('Up Top = 0', 0, R.Top);
  AssertEquals('Up Bottom = 14', 14, R.Bottom);
end;

procedure TTySpinEditGeometryTest.TestDownButtonRect;
{ Down = Rect(102, 14, 120, 28). }
var
  R: TRect;
begin
  R := TySpinDownButtonRect(Rect(0, 0, 120, 28), 96);
  AssertEquals('Down Left = 102', 102, R.Left);
  AssertEquals('Down Top = 14', 14, R.Top);
  AssertEquals('Down Bottom = 28', 28, R.Bottom);
end;

procedure TTySpinEditGeometryTest.TestButtonsDoNotOverlapAndCoverColumn;
var
  U, D: TRect;
begin
  U := TySpinUpButtonRect(Rect(0, 0, 120, 28), 96);
  D := TySpinDownButtonRect(Rect(0, 0, 120, 28), 96);
  AssertEquals('Up.Bottom = Down.Top (no overlap, contiguous)', U.Bottom, D.Top);
  AssertEquals('same column Left', U.Left, D.Left);
  AssertEquals('same column Right', U.Right, D.Right);
end;

{ TTySpinEditControlTest }

procedure TTySpinEditControlTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 300, 100);
  FSpin := TTySpinEditProbe.Create(FForm);
  FSpin.Parent := FForm;
  FSpin.SetBounds(0, 0, 120, 28);
  FSpin.Font.PixelsPerInch := 96;
  FSpin.MinValue := 0;
  FSpin.MaxValue := 100;
  FSpin.Value := 50;
  FCounter := TChangeCounter.Create;
  FSpin.OnChange := @FCounter.Handle;
end;

procedure TTySpinEditControlTest.TearDown;
begin
  FCounter.Free;
  FForm.Free;
end;

procedure TTySpinEditControlTest.TestTypeKey;
begin
  AssertEquals('TySpinEdit', (FSpin as ITyStyleable).GetStyleTypeKey);
end;

procedure TTySpinEditControlTest.TestVKUpIncrements;
var
  Key: Word;
begin
  Key := VK_UP;
  FSpin.SimulateKeyDown(Key);
  AssertEquals('VK_UP increments by 1', 51, FSpin.Value);
  AssertEquals('VK_UP key consumed (Key=0)', 0, Integer(Key));
end;

procedure TTySpinEditControlTest.TestVKDownDecrements;
var
  Key: Word;
begin
  Key := VK_DOWN;
  FSpin.SimulateKeyDown(Key);
  AssertEquals('VK_DOWN decrements by 1', 49, FSpin.Value);
  AssertEquals('VK_DOWN key consumed (Key=0)', 0, Integer(Key));
end;

procedure TTySpinEditControlTest.TestVKUpClampsAtMax;
var
  Key: Word;
begin
  FSpin.Value := 100;
  Key := VK_UP;
  FSpin.SimulateKeyDown(Key);
  AssertEquals('VK_UP at Max stays at Max', 100, FSpin.Value);
end;

procedure TTySpinEditControlTest.TestVKDownClampsAtMin;
var
  Key: Word;
begin
  FSpin.Value := 0;
  Key := VK_DOWN;
  FSpin.SimulateKeyDown(Key);
  AssertEquals('VK_DOWN at Min stays at Min', 0, FSpin.Value);
end;

procedure TTySpinEditControlTest.TestWheelUpIncrements;
var
  R: Boolean;
begin
  R := FSpin.SimulateWheel(120);
  AssertEquals('wheel up increments by 1', 51, FSpin.Value);
  AssertTrue('wheel consumed (Result True)', R);
end;

procedure TTySpinEditControlTest.TestWheelDownDecrements;
begin
  FSpin.SimulateWheel(-120);
  AssertEquals('wheel down decrements by 1', 49, FSpin.Value);
end;

procedure TTySpinEditControlTest.TestMouseDownUpButton;
begin
  { (110,4) is inside up half (col 102..120, top 0..14) }
  FSpin.SimulateMouseDown(110, 4);
  AssertEquals('mousedown up button increments', 51, FSpin.Value);
end;

procedure TTySpinEditControlTest.TestMouseDownDownButton;
begin
  { (110,24) is inside down half (col 102..120, 14..28) }
  FSpin.SimulateMouseDown(110, 24);
  AssertEquals('mousedown down button decrements', 49, FSpin.Value);
end;

procedure TTySpinEditControlTest.TestMouseDownTextAreaNoChange;
begin
  { (10,14) is in the text area, not the button column }
  FSpin.SimulateMouseDown(10, 14);
  AssertEquals('mousedown text area no change', 50, FSpin.Value);
end;

procedure TTySpinEditControlTest.TestOnChangeOnlyOnRealChange;
begin
  FCounter.Count := 0;
  FSpin.Value := 60;
  AssertEquals('First set fires OnChange once', 1, FCounter.Count);
  FSpin.Value := 60;
  AssertEquals('Second set to same value does not fire OnChange', 1, FCounter.Count);
end;

procedure TTySpinEditControlTest.TestIncrementUsed;
var
  Key: Word;
begin
  FSpin.Increment := 5;
  Key := VK_UP;
  FSpin.SimulateKeyDown(Key);
  AssertEquals('VK_UP uses Increment=5', 55, FSpin.Value);
end;

procedure TTySpinEditControlTest.TestDisabledKeyIgnored;
var
  Key: Word;
begin
  FSpin.Enabled := False;
  Key := VK_UP;
  FSpin.SimulateKeyDown(Key);
  AssertEquals('disabled key ignored: value unchanged', 50, FSpin.Value);
  AssertEquals('disabled key NOT consumed (still VK_UP)', Integer(VK_UP), Integer(Key));
end;

procedure TTySpinEditControlTest.TestDisabledMouseIgnored;
begin
  FSpin.Enabled := False;
  FSpin.SimulateMouseDown(110, 4);
  AssertEquals('disabled mouse ignored: value unchanged', 50, FSpin.Value);
end;

procedure TTySpinEditControlTest.TestDisabledWheelIgnored;
var
  R: Boolean;
begin
  FSpin.Enabled := False;
  R := FSpin.SimulateWheel(120);
  AssertFalse('disabled wheel returns False', R);
  AssertEquals('disabled wheel ignored: value unchanged', 50, FSpin.Value);
end;

procedure TTySpinEditControlTest.TestMinClampReclampsValue;
begin
  FSpin.Value := 50;
  FCounter.Count := 0;
  FSpin.MinValue := 60;
  AssertEquals('MinValue raise reclamps Value to 60', 60, FSpin.Value);
  AssertEquals('reclamp via MinValue fires NO OnChange', 0, FCounter.Count);
end;

procedure TTySpinEditControlTest.TestIncrementClampMinOne;
begin
  FSpin.Increment := 0;
  AssertEquals('Increment < 1 clamps to 1', 1, FSpin.Increment);
end;

{ TTySpinEditPixelTest }

procedure TTySpinEditPixelTest.LoadThemeCss;
begin
  FCtl.LoadThemeCss(
    'TySpinEdit { background: #101010; color: #F0F0F0; border-width: 0px; border-radius: 0px; }');
end;

procedure TTySpinEditPixelTest.TestUpArrowGlyphRendered;
{ 120x28 bitmap @96ppi. Background #101010 (dark), text/glyph #F0F0F0 (light).
  The up-button column is x=102..120, top half y=0..14. Assert that a
  non-background (light) pixel exists in that column → the arrow glyph drew. }
var
  Form: TForm;
  Spin: TTySpinEditProbe;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  X, Y: Integer;
  FoundLight: Boolean;
begin
  FCtl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    LoadThemeCss;
    Spin := TTySpinEditProbe.Create(Form);
    Spin.Parent := Form;
    Spin.Controller := FCtl;
    Spin.SetBounds(0, 0, 120, 28);
    Spin.Font.PixelsPerInch := 96;
    Spin.MinValue := 0;
    Spin.MaxValue := 100;
    Spin.Value := 50;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 28);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 120, 28);
    Spin.RenderTo(Bmp.Canvas, Rect(0, 0, 120, 28), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      FoundLight := False;
      { scan the up-button column top half for any light (glyph) pixel }
      for Y := 1 to 13 do
        for X := 102 to 119 do
        begin
          Px := Reread.GetPixel(X, Y);
          if (Px.red > 100) and (Px.green > 100) and (Px.blue > 100) then
          begin
            FoundLight := True;
            Break;
          end;
        end;
      AssertTrue('up-arrow glyph drew a light pixel in the up-button column', FoundLight);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    FCtl.Free;
  end;
end;

initialization
  RegisterTest(TTySpinEditGeometryTest);
  RegisterTest(TTySpinEditControlTest);
  RegisterTest(TTySpinEditPixelTest);
end.
