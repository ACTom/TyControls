unit test.spinedit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, LazUTF8, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.DefaultTheme, tyControls.SpinEdit;
type
  { Probe subclass: exposes protected RenderTo and input handlers }
  TTySpinEditProbe = class(TTySpinEdit)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure SimulateKeyDown(var Key: Word);
    procedure SimulateMouseDown(X, Y: Integer);
    function SimulateWheel(WheelDelta: Integer): Boolean;
  end;

  { Access subclass for the inline edit model: exposes edit buffer + handlers }
  TTySpinAccess = class(TTySpinEdit)
  public
    procedure DoKey(Key: Word; Shift: TShiftState);   // calls KeyDown
    procedure TypeChar(const C: TUTF8Char);            // calls UTF8KeyPress
    function EditTextForTest: string;
    function CaretForTest: Integer;
    procedure CommitForTest;
    procedure FocusBufferForTest;
    procedure SetEditTextForTest(const S: string);
    procedure RenderToForTest(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function CaretXForTest(AIdx: Integer): Integer;
    function ResolvedFontSizeForTest: Integer;
  end;

  TChangeCounter = class
  public
    Count: Integer;
    procedure Handle(Sender: TObject);
  end;

  TTySpinEditCursorTest = class(TTestCase)
  published
    procedure TestSpinEditUsesIBeam;
  end;

  TTySpinEditEditModelTest = class(TTestCase)
  published
    procedure TestSpinTypeDigitsIntoBuffer;
    procedure TestSpinCommitParsesAndClamps;
    procedure TestSpinEscRevertsBuffer;
    procedure TestSpinEnterCommits;
    procedure TestSpinArrowStepsAndResyncsBuffer;
    procedure TestSpinInvalidCommitFallsBack;
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

  TTySpinEditRenderTest = class(TTestCase)
  published
    procedure TestSpinRendersBufferNotValue;
    procedure TestSpinCaretXMonotonic;
  end;

  TTySpinEditFontSizeTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
  published
    procedure TestResolvedFontSizeMatchesTheme;
    procedure TestTextRenderedAtResolvedSizeNotOrphan12;
  end;

implementation

procedure TChangeCounter.Handle(Sender: TObject);
begin
  Inc(Count);
end;

{ TTySpinAccess }

procedure TTySpinAccess.DoKey(Key: Word; Shift: TShiftState); begin KeyDown(Key, Shift); end;
procedure TTySpinAccess.TypeChar(const C: TUTF8Char); var k: TUTF8Char; begin k := C; UTF8KeyPress(k); end;
function TTySpinAccess.EditTextForTest: string; begin Result := FEditText; end;
function TTySpinAccess.CaretForTest: Integer; begin Result := FCaret; end;
procedure TTySpinAccess.CommitForTest; begin CommitEdit; end;
procedure TTySpinAccess.FocusBufferForTest; begin SyncBufferToValue; end;
procedure TTySpinAccess.SetEditTextForTest(const S: string); begin FEditText := S; FCaret := UTF8Length(S); end;
procedure TTySpinAccess.RenderToForTest(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin RenderTo(ACanvas, ARect, APPI); end;
function TTySpinAccess.CaretXForTest(AIdx: Integer): Integer;
begin Result := CaretPixelX(AIdx, 96); end;
function TTySpinAccess.ResolvedFontSizeForTest: Integer;
begin Result := ResolveFontSize(CurrentStyle); end;

{ TTySpinEditEditModelTest }

procedure TTySpinEditEditModelTest.TestSpinTypeDigitsIntoBuffer;
var S: TTySpinAccess;
begin
  S := TTySpinAccess.Create(nil);
  try
    S.MinValue := 0; S.MaxValue := 1000; S.Value := 0;
    S.FocusBufferForTest;
    S.TypeChar('4'); S.TypeChar('2');
    AssertTrue('digits in buffer', Pos('42', S.EditTextForTest) > 0);
  finally S.Free; end;
end;

procedure TTySpinEditEditModelTest.TestSpinCommitParsesAndClamps;
var S: TTySpinAccess;
begin
  S := TTySpinAccess.Create(nil);
  try
    S.MinValue := 0; S.MaxValue := 50; S.Value := 0;
    S.FocusBufferForTest; S.SetEditTextForTest('999');
    S.CommitForTest;
    AssertEquals('clamped to max', 50, S.Value);
    AssertEquals('buffer resynced', '50', S.EditTextForTest);
  finally S.Free; end;
end;

procedure TTySpinEditEditModelTest.TestSpinEscRevertsBuffer;
var S: TTySpinAccess;
begin
  S := TTySpinAccess.Create(nil);
  try
    S.MinValue := 0; S.MaxValue := 100; S.Value := 7;
    S.FocusBufferForTest; S.SetEditTextForTest('99');
    S.DoKey(VK_ESCAPE, []);
    AssertEquals('value unchanged after Esc', 7, S.Value);
    AssertEquals('buffer reverted', '7', S.EditTextForTest);
  finally S.Free; end;
end;

procedure TTySpinEditEditModelTest.TestSpinEnterCommits;
var S: TTySpinAccess;
begin
  S := TTySpinAccess.Create(nil);
  try
    S.MinValue := 0; S.MaxValue := 100; S.Value := 0;
    S.FocusBufferForTest; S.SetEditTextForTest('33');
    S.DoKey(VK_RETURN, []);
    AssertEquals('enter committed', 33, S.Value);
  finally S.Free; end;
end;

procedure TTySpinEditEditModelTest.TestSpinArrowStepsAndResyncsBuffer;
var S: TTySpinAccess;
begin
  S := TTySpinAccess.Create(nil);
  try
    S.MinValue := 0; S.MaxValue := 100; S.Value := 5; S.Increment := 2;
    S.FocusBufferForTest;
    S.DoKey(VK_UP, []);
    AssertEquals('value stepped', 7, S.Value);
    AssertEquals('buffer resynced to value', '7', S.EditTextForTest);
  finally S.Free; end;
end;

procedure TTySpinEditEditModelTest.TestSpinInvalidCommitFallsBack;
var S: TTySpinAccess;
begin
  S := TTySpinAccess.Create(nil);
  try
    S.MinValue := 0; S.MaxValue := 100; S.Value := 9;
    S.FocusBufferForTest; S.SetEditTextForTest('-');
    S.CommitForTest;
    AssertEquals('invalid falls back to current value', 9, S.Value);
    AssertEquals('buffer resynced', '9', S.EditTextForTest);
  finally S.Free; end;
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

{ TTySpinEditRenderTest }

procedure TTySpinEditRenderTest.TestSpinRendersBufferNotValue;
  function InkCount(S: TTySpinAccess): Integer;
  var bmp: TBitmap; reread: TBGRABitmap; x,y: Integer; px: TBGRAPixel;
  begin
    Result := 0;
    bmp := TBitmap.Create;
    try
      bmp.PixelFormat := pf32bit; bmp.SetSize(120,28);
      bmp.Canvas.Brush.Color := clWhite; bmp.Canvas.FillRect(0,0,120,28);
      S.RenderToForTest(bmp.Canvas, Rect(0,0,120,28), 96);
      reread := TBGRABitmap.Create(bmp);
      try
        for x := 2 to 80 do for y := 4 to 24 do
        begin px := reread.GetPixel(x,y);
          if (px.red < 160) and (px.green < 160) and (px.blue < 160) then Inc(Result); end;
      finally reread.Free; end;
    finally bmp.Free; end;
  end;
var S: TTySpinAccess; ink789, ink0: Integer;
begin
  S := TTySpinAccess.Create(nil);
  try
    S.MinValue:=0; S.MaxValue:=1000; S.Value:=0; S.Font.PixelsPerInch:=96;
    S.SetEditTextForTest('789');
    ink789 := InkCount(S);
    S.SetEditTextForTest('0');
    ink0 := InkCount(S);
    AssertTrue('some ink for buffer', ink789 > 0);
    AssertTrue('3-digit buffer renders more ink than 1-digit (buffer is drawn, not value)', ink789 > ink0);
  finally S.Free; end;
end;

procedure TTySpinEditRenderTest.TestSpinCaretXMonotonic;
var S: TTySpinAccess;
begin
  S := TTySpinAccess.Create(nil);
  try
    S.MinValue:=0; S.MaxValue:=100000; S.Font.PixelsPerInch:=96;
    S.FocusBufferForTest; S.SetEditTextForTest('12345');
    AssertTrue('caret x grows with index', S.CaretXForTest(1) < S.CaretXForTest(4));
  finally S.Free; end;
end;

{ TTySpinEditFontSizeTest }

{ Measures the vertical extent (top..bottom span) of the digit ink that the
  SpinEdit draws for its edit buffer, so a smaller font => a shorter span. }
function SpinInkHeight(S: TTySpinAccess): Integer;
var
  bmp: TBitmap; reread: TBGRABitmap; x, y: Integer; px: TBGRAPixel;
  minY, maxY: Integer;
begin
  minY := 9999; maxY := -1;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit; bmp.SetSize(120, 28);
    bmp.Canvas.Brush.Color := clWhite; bmp.Canvas.FillRect(0, 0, 120, 28);
    S.RenderToForTest(bmp.Canvas, Rect(0, 0, 120, 28), 96);
    reread := TBGRABitmap.Create(bmp);
    try
      { scan the text column only (left of the spin buttons at x>=102) }
      for x := 2 to 80 do
        for y := 0 to 27 do
        begin
          px := reread.GetPixel(x, y);
          if (px.red < 160) and (px.green < 160) and (px.blue < 160) then
          begin
            if y < minY then minY := y;
            if y > maxY then maxY := y;
          end;
        end;
    finally reread.Free; end;
  finally bmp.Free; end;
  if maxY < 0 then Result := 0 else Result := maxY - minY + 1;
end;

procedure TTySpinEditFontSizeTest.TestResolvedFontSizeMatchesTheme;
{ Under the built-in theme (TySpinEdit font-size:9px), SpinEdit must route its
  text size through ResolveFontSize and get 9 — NOT the orphan literal 12. }
var
  Form: TForm; S: TTySpinAccess;
begin
  FCtl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  try
    FCtl.LoadThemeCss(TyBuiltinThemeCss);
    S := TTySpinAccess.Create(Form);
    S.Parent := Form;
    S.Controller := FCtl;
    S.Font.PixelsPerInch := 96;
    AssertEquals('SpinEdit resolves theme font-size 9 (not orphan 12)',
      9, S.ResolvedFontSizeForTest);
  finally
    Form.Free;
    FCtl.Free;
  end;
end;

procedure TTySpinEditFontSizeTest.TestTextRenderedAtResolvedSizeNotOrphan12;
{ With NO theme font-size and Font.Size=0, the old code fell back to the orphan
  literal 12; the fix routes through ResolveFontSize -> default 9. A 9pt digit's
  ink span must be shorter than the same digit measured at 12pt, proving the
  rendered text (and the shared caret/measure path) now honor the resolved size. }
var
  Form: TForm; Ctl9, Ctl12: TTyStyleController; S9, S12: TTySpinAccess;
  h9, h12: Integer;
begin
  Form := TForm.CreateNew(nil);
  Ctl9 := TTyStyleController.Create(nil);
  Ctl12 := TTyStyleController.Create(nil);
  try
    { themes carry no font-size => render must lean on ResolveFontSize (->9) }
    Ctl9.LoadThemeCss(
      'TySpinEdit { background: #FFFFFF; color: #000000; border-width: 0px; padding: 2px; }');
    { an explicit 12px theme gives the reference extent for "the old orphan size" }
    Ctl12.LoadThemeCss(
      'TySpinEdit { background: #FFFFFF; color: #000000; border-width: 0px; padding: 2px; font-size: 12px; }');

    S9 := TTySpinAccess.Create(Form);
    S9.Parent := Form; S9.Controller := Ctl9; S9.Font.PixelsPerInch := 96;
    S9.SetEditTextForTest('88');
    h9 := SpinInkHeight(S9);

    S12 := TTySpinAccess.Create(Form);
    S12.Parent := Form; S12.Controller := Ctl12; S12.Font.PixelsPerInch := 96;
    S12.SetEditTextForTest('88');
    h12 := SpinInkHeight(S12);

    AssertTrue('9px digit ink renders (some ink)', h9 > 0);
    AssertTrue('9px digit ink span is shorter than 12px (text honors resolved size, not orphan 12)',
      h9 < h12);
  finally
    Form.Free;
    Ctl9.Free;
    Ctl12.Free;
  end;
end;

procedure TTySpinEditCursorTest.TestSpinEditUsesIBeam;
var
  S: TTySpinEdit;
begin
  S := TTySpinEdit.Create(nil);
  try
    AssertEquals(crIBeam, S.Cursor);
  finally
    S.Free;
  end;
end;

initialization
  RegisterTest(TTySpinEditGeometryTest);
  RegisterTest(TTySpinEditControlTest);
  RegisterTest(TTySpinEditPixelTest);
  RegisterTest(TTySpinEditEditModelTest);
  RegisterTest(TTySpinEditRenderTest);
  RegisterTest(TTySpinEditFontSizeTest);
  RegisterTest(TTySpinEditCursorTest);
end.
