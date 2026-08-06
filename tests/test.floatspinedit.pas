unit test.floatspinedit;
{$mode objfpc}{$H+}
{ Guards for TTyFloatSpinEdit — the decimal counterpart of LCL's TFloatSpinEdit.

  The finding this control closes: the library had a Double field (TTyNumericEdit) and a
  stepper field (TTySpinEdit) and no control that was both, so any form wanting a price, a
  percentage or a scale factor with spin buttons had to give one of the two up.

  Two shapes were considered and REJECTED, and the tests below are what keeps them rejected:

  * shadowing `Value: Double` over TTySpinEdit's published `Value: Integer` — the Integer
    engine would still do the stepping, so 1.5 would truncate SILENTLY. ValueKeepsItsFraction
    and AFractionalIncrementIsNotTruncated are the two that would go red.
  * a `DecimalPlaces` MODE on TTySpinEdit — that needs a second value property, and one of
    the two always lies. Nothing to test: the shape does not exist here, and Decimals (the
    library's name for LCL's DecimalPlaces) is inherited from TTyNumericEdit.

  The button geometry is asserted at the EDGES of the two halves, never at their centres: a
  centre probe survives every off-by-one and every half-split drift this repo has shipped. }
interface
uses
  Classes, SysUtils, Types, Graphics, Controls, LCLType, TypInfo,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel,
  tyControls.FloatSpinEdit;

type
  { Reaches the protected input dispatch, the trailing-zone geometry and RenderTo. Declared
    here, so everything protected on the whole TTyEdit ancestry is in reach of this unit. }
  TFloatSpinProbe = class(TTyFloatSpinEdit)
  public
    FZoneSeen: TRect;
    FZoneCalls: Integer;
    procedure PaintTrailing(APainter: TTyPainter; const AZone: TRect;
      const AStyle: TTyStyleSet); override;
    function Reserve(APPI: Integer): Integer;
    function ButtonMetric: Integer;
    function Zone(APPI: Integer): TRect;
    procedure ClickAt(X, Y: Integer);
    procedure DoKey(K: Word; S: TShiftState);
    procedure TypeChar(const C: TUTF8Char);
    procedure Paste(const S: string);
    function Wheel(ADelta: Integer): Boolean;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure SetKeyDownHandler(const H: TKeyEvent);
  end;

  TFloatSpinEditTest = class(TTestCase)
  private
    FVetoed: Integer;
    procedure VetoEveryKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure RemapUpToDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    // A probe sized and laid out the same way every geometry test needs it.
    function NewProbe: TFloatSpinProbe;
  published
    { --- the reason the control exists --- }
    procedure ValueKeepsItsFraction;
    procedure AFractionalIncrementIsNotTruncated;
    procedure SteppingDoesNotAccumulateBinaryDrift;
    { --- the two recorded traps --- }
    procedure UseThousandsIsOffAndItsDECLAREDDefaultAgrees;
    procedure IncrementDefaultsToOneAndOnlyStreamsWhenItIsNot;
    { --- geometry --- }
    procedure TheButtonColumnIsTheFieldButtonMetric;
    procedure TheTwoHalvesTileTheTrailingZoneExactly;
    procedure TheGlyphBoxIsTheLargestCentredSquare;
    procedure WhatIsPaintedIsWhatIsClickable;
    { --- stepping --- }
    procedure ClickingTheUpHalfStepsUpAtEveryEdge;
    procedure ClickingTheDownHalfStepsDownAtEveryEdge;
    procedure ClickingOffTheHalvesDoesNotStep;
    procedure ArrowKeysStep;
    procedure AnOnKeyDownHandlerCanVetoTheStep;
    procedure AnOnKeyDownHandlerCanRemapTheStep;
    procedure TheWheelSteps;
    procedure StepsClampToTheRange;
    procedure SteppingMarksTheFieldModified;
    procedure ReadOnlyBlocksEveryStepPath;
    procedure TheWheelIsReportedUnhandledWhenReadOnly;
    { --- EditorEnabled: the keyboard lock that leaves the arrows alone --- }
    procedure EditorEnabledFalseBlocksTyping;
    procedure EditorEnabledFalseBlocksBackspaceAndDelete;
    procedure EditorEnabledFalseBlocksTheClipboardAndUndoKeys;
    procedure EditorEnabledFalseBlocksABulkInsert;
    procedure EditorEnabledFalseStillLetsEveryStepPathRun;
    procedure ReadOnlyAndEditorEnabledAreTwoDifferentLocks;
  end;

implementation

const
  EPS = 1e-9;

{ TFloatSpinProbe }

procedure TFloatSpinProbe.PaintTrailing(APainter: TTyPainter; const AZone: TRect;
  const AStyle: TTyStyleSet);
begin
  FZoneSeen := AZone;
  Inc(FZoneCalls);
  inherited PaintTrailing(APainter, AZone, AStyle);
end;

function TFloatSpinProbe.Reserve(APPI: Integer): Integer;
begin
  Result := RightReserve(APPI);
end;

function TFloatSpinProbe.ButtonMetric: Integer;
begin
  Result := ActiveController.Metric('--field-button-width', TyFieldButtonWidth);
end;

function TFloatSpinProbe.Zone(APPI: Integer): TRect;
begin
  Result := TrailingZone(APPI);
end;

procedure TFloatSpinProbe.ClickAt(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
end;

procedure TFloatSpinProbe.DoKey(K: Word; S: TShiftState);
var
  w: Word;
begin
  w := K;
  KeyDown(w, S);
end;

procedure TFloatSpinProbe.TypeChar(const C: TUTF8Char);
var
  k: TUTF8Char;
begin
  k := C;
  UTF8KeyPress(k);
end;

procedure TFloatSpinProbe.Paste(const S: string);
begin
  InjectStringAt(S);   // the bulk-insert chokepoint paste and an IME commit both funnel through
end;

function TFloatSpinProbe.Wheel(ADelta: Integer): Boolean;
begin
  Result := DoMouseWheel([], ADelta, Point(0, 0));
end;

procedure TFloatSpinProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TFloatSpinProbe.SetKeyDownHandler(const H: TKeyEvent);
begin
  OnKeyDown := H;
end;

{ TFloatSpinEditTest }

procedure TFloatSpinEditTest.VetoEveryKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  Inc(FVetoed);
  Key := 0;      // "handled" — the application consumed it
end;

procedure TFloatSpinEditTest.RemapUpToDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_UP then Key := VK_DOWN;   // an inverted-axis field: up is to mean down here
end;

function TFloatSpinEditTest.NewProbe: TFloatSpinProbe;
begin
  Result := TFloatSpinProbe.Create(nil);
  Result.SetBounds(0, 0, 140, 28);
end;

{ ------------------------------------------------------------------ the point ---- }

procedure TFloatSpinEditTest.ValueKeepsItsFraction;
{ The whole gap in one assertion. A shadowed Double over the integer spin edit's engine would
  read back 1 or 2 here, with nothing said. }
var
  f: TTyFloatSpinEdit;
begin
  f := TTyFloatSpinEdit.Create(nil);
  try
    f.Value := 1.5;
    AssertEquals('the fraction survives the round trip through the display', 1.5, f.Value, EPS);
    AssertEquals('and the display is the decimal form', '1.50', f.Text);
    f.Decimals := 3;
    f.Value := -0.125;
    AssertEquals('negatives too', -0.125, f.Value, EPS);
    AssertEquals('at three places', '-0.125', f.Text);
  finally
    f.Free;
  end;
end;

procedure TFloatSpinEditTest.AFractionalIncrementIsNotTruncated;
{ Increment is a Double and the stepping arithmetic is done in Double. Floor it at 1 (the
  integer sibling's rule) or route it through an Integer engine and this goes red. }
var
  p: TFloatSpinProbe;
begin
  p := NewProbe;
  try
    p.Value := 0;
    p.Increment := 0.25;
    p.DoKey(VK_UP, []);
    AssertEquals('one quarter step', 0.25, p.Value, EPS);
    p.DoKey(VK_UP, []);
    p.DoKey(VK_UP, []);
    AssertEquals('three of them', 0.75, p.Value, EPS);
    p.DoKey(VK_DOWN, []);
    AssertEquals('and back down by the same amount', 0.5, p.Value, EPS);
  finally
    p.Free;
  end;
end;

procedure TFloatSpinEditTest.SteppingDoesNotAccumulateBinaryDrift;
{ 0.1 is not representable in binary, so ten naive additions land on 0.9999999999999999. The
  value is re-derived from the DISPLAYED text after every write, which re-quantises it to
  Decimals places — so the tenth step has to be exactly 1, not almost. }
var
  p: TFloatSpinProbe;
  i: Integer;
begin
  p := NewProbe;
  try
    p.Value := 0;
    p.Increment := 0.1;
    for i := 1 to 10 do p.DoKey(VK_UP, []);
    AssertEquals('ten tenths are one', '1.00', p.Text);
    AssertEquals('exactly', 1.0, p.Value, 0.0);
  finally
    p.Free;
  end;
end;

{ ------------------------------------------------------- the two recorded traps ---- }

procedure TFloatSpinEditTest.UseThousandsIsOffAndItsDECLAREDDefaultAgrees;
{ TRAP 1. LCL's float spin edit does not group thousands — ValueToStr is a plain
  FloatToStrF(..., ffFixed, 20, DecimalPlaces), include/spinedit.inc:237 — while the inherited
  TTyNumericEdit groups by default. Both halves are checked: the runtime value AND the RTTI
  `default`, because a redeclaration that sets only the constructor leaves the inherited
  `default True` in the RTTI, and then a designer's UseThousands := False never reaches the
  .lfm and the control comes back grouped. }
var
  f: TTyFloatSpinEdit;
  pi: PPropInfo;
begin
  f := TTyFloatSpinEdit.Create(nil);
  try
    AssertFalse('a fresh float spin edit does not group', f.UseThousands);
    f.Value := 1234567.5;
    AssertEquals('and its display does not either', '1234567.50', f.Text);
  finally
    f.Free;
  end;
  pi := GetPropInfo(TTyFloatSpinEdit, 'UseThousands');
  AssertTrue('UseThousands is still published', pi <> nil);
  AssertEquals('the DECLARED default has to be False too, or the opt-in never streams',
    Ord(False), pi^.Default);
end;

procedure TFloatSpinEditTest.IncrementDefaultsToOneAndOnlyStreamsWhenItIsNot;
{ LCL spin.pp:80 stores Increment only when it is not 1; matched here so a .lfm does not carry
  a line for the default. A Double cannot declare `default`, so `stored` is the only mechanism
  — and if IncrementStored ever answers True for 1, every form file grows a redundant line. }
var
  f: TTyFloatSpinEdit;
begin
  f := TTyFloatSpinEdit.Create(nil);
  try
    AssertEquals('LCL DefIncrement', 1.0, f.Increment, EPS);
    AssertFalse('the default is not written to the .lfm', IsStoredProp(f, 'Increment'));
    f.Increment := 0.25;
    AssertTrue('a real step is', IsStoredProp(f, 'Increment'));
    f.Increment := 1;
    AssertFalse('and setting it back stops storing it again', IsStoredProp(f, 'Increment'));
  finally
    f.Free;
  end;
end;

{ ----------------------------------------------------------------- geometry ---- }

procedure TFloatSpinEditTest.TheButtonColumnIsTheFieldButtonMetric;
{ The width has to come from the SAME token the combo box, the combo edit and the integer spin
  edit read, or a skin that widens the field buttons leaves this one control behind. }
var
  p: TFloatSpinProbe;
  expected: Integer;
begin
  p := NewProbe;
  try
    expected := p.ButtonMetric;
    AssertTrue('precondition: the metric resolves to something', expected > 0);
    AssertEquals('at 96 DPI the column is the metric itself', expected, p.Reserve(96));
    AssertEquals('and it scales with the DPI', MulDiv(expected, 192, 96), p.Reserve(192));
  finally
    p.Free;
  end;
end;

procedure TFloatSpinEditTest.TheTwoHalvesTileTheTrailingZoneExactly;
{ Edges, not centres. A half-split that drifts by one pixel leaves either a dead stripe between
  the buttons or an overlap where the up button eats the down button's top row; a centre probe
  is blind to both. }
var
  p: TFloatSpinProbe;
  z, u, d: TRect;
begin
  p := NewProbe;
  try
    z := p.Zone(96);
    u := p.UpButtonRect(96);
    d := p.DownButtonRect(96);
    AssertTrue('precondition: the zone is real', (z.Right > z.Left) and (z.Bottom > z.Top));
    AssertEquals('the zone is exactly the reserved column wide', p.Reserve(96), z.Right - z.Left);
    AssertEquals('up starts at the zone left', z.Left, u.Left);
    AssertEquals('down starts at the zone left', z.Left, d.Left);
    AssertEquals('up ends at the zone right', z.Right, u.Right);
    AssertEquals('down ends at the zone right', z.Right, d.Right);
    AssertEquals('up starts at the zone top', z.Top, u.Top);
    AssertEquals('down ends at the zone bottom', z.Bottom, d.Bottom);
    AssertEquals('and they meet with no gap and no overlap', u.Bottom, d.Top);
    { The same must hold at the DPI the control actually runs at, which is not necessarily 96
      — and it is the one MouseDown uses, so every click test below asks for the rects at
      Font.PixelsPerInch rather than at a literal. Asking at the wrong DPI was the first
      spelling of those tests and it put the whole column several pixels off. }
    z := p.Zone(p.Font.PixelsPerInch);
    u := p.UpButtonRect(p.Font.PixelsPerInch);
    d := p.DownButtonRect(p.Font.PixelsPerInch);
    AssertEquals('at the live DPI too: up starts at the zone left', z.Left, u.Left);
    AssertEquals('at the live DPI too: down ends at the zone bottom', z.Bottom, d.Bottom);
    AssertEquals('at the live DPI too: they still meet exactly', u.Bottom, d.Top);
  finally
    p.Free;
  end;
end;

procedure TFloatSpinEditTest.TheGlyphBoxIsTheLargestCentredSquare;
{ The arrow's box. TTyPainter.DrawGlyph insets 4 logical px per side, so in a raw 18x10 half
  the arrow would come out one pixel tall — the glyph-slot floor this library has hit before.
  Squaring first is what stops it, and the square has to be CENTRED or the two arrows sit off
  to one side of the column. }
var
  r: TRect;
begin
  r := TyFloatSpinGlyphBox(Rect(100, 50, 118, 60));    // 18 x 10 — the real shape at 96 DPI
  AssertEquals('side = min(w, h)', 10, r.Right - r.Left);
  AssertEquals('square', r.Right - r.Left, r.Bottom - r.Top);
  AssertEquals('centred horizontally: (18-10) div 2', 104, r.Left);
  AssertEquals('and vertically there is no slack to take', 50, r.Top);

  r := TyFloatSpinGlyphBox(Rect(0, 0, 8, 20));         // taller than wide: the other branch
  AssertEquals('side = min again', 8, r.Bottom - r.Top);
  AssertEquals('centred vertically: (20-8) div 2', 6, r.Top);
  AssertEquals('and flush horizontally', 0, r.Left);

  r := TyFloatSpinGlyphBox(Rect(5, 5, 5, 20));         // degenerate: no width at all
  AssertTrue('a zero-width half yields an empty box, not a negative one',
    (r.Right - r.Left <= 0) and (r.Bottom - r.Top <= 0));
end;

procedure TFloatSpinEditTest.WhatIsPaintedIsWhatIsClickable;
{ The one guard that binds the two halves of the control together. The paint gets its zone
  from TTyEdit's RenderTo; the hit test computes its own from TrailingZone. They are supposed
  to be the same rectangle, and if they ever stop being it, the buttons move out from under
  the pointer with nothing else failing. }
var
  p: TFloatSpinProbe;
  bmp: TBitmap;
  ppi: Integer;
  hit: TRect;
begin
  p := NewProbe;
  bmp := TBitmap.Create;
  try
    { At the DPI the control really paints at (TTyEdit.Paint passes Font.PixelsPerInch), so
      this compares the two answers the RUNNING control gives, not two answers at a literal
      neither of them uses. }
    ppi := p.Font.PixelsPerInch;
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(p.Width, p.Height);
    p.FZoneCalls := 0;
    p.Render(bmp.Canvas, Rect(0, 0, p.Width, p.Height), ppi);
    AssertEquals('the trailing widget was painted exactly once', 1, p.FZoneCalls);
    hit := p.Zone(ppi);
    AssertEquals('painted left = clickable left',     hit.Left,   p.FZoneSeen.Left);
    AssertEquals('painted top = clickable top',       hit.Top,    p.FZoneSeen.Top);
    AssertEquals('painted right = clickable right',   hit.Right,  p.FZoneSeen.Right);
    AssertEquals('painted bottom = clickable bottom', hit.Bottom, p.FZoneSeen.Bottom);
  finally
    bmp.Free;
    p.Free;
  end;
end;

{ ----------------------------------------------------------------- stepping ---- }

procedure TFloatSpinEditTest.ClickingTheUpHalfStepsUpAtEveryEdge;
{ The rects are asked for at Font.PixelsPerInch because that is what MouseDown hit-tests with.
  A literal 96 here is not a simplification, it is a different control: the headless runner's
  font does not report 96, and the whole button column lands several pixels off. }
var
  p: TFloatSpinProbe;
  u: TRect;
begin
  p := NewProbe;
  try
    u := p.UpButtonRect(p.Font.PixelsPerInch);
    p.Increment := 0.5;
    p.Value := 0;
    p.ClickAt(u.Left, u.Top);                       // top-left corner
    AssertEquals('the first pixel of the half counts', 0.5, p.Value, EPS);
    p.ClickAt(u.Right - 1, u.Bottom - 1);           // bottom-right corner, still inside
    AssertEquals('and so does the last', 1.0, p.Value, EPS);
  finally
    p.Free;
  end;
end;

procedure TFloatSpinEditTest.ClickingTheDownHalfStepsDownAtEveryEdge;
var
  p: TFloatSpinProbe;
  d: TRect;
begin
  p := NewProbe;
  try
    d := p.DownButtonRect(p.Font.PixelsPerInch);
    p.Increment := 0.5;
    p.Value := 10;
    p.ClickAt(d.Left, d.Top);                       // the row immediately under the up half
    AssertEquals('the boundary row belongs to DOWN', 9.5, p.Value, EPS);
    p.ClickAt(d.Right - 1, d.Bottom - 1);
    AssertEquals('and the last pixel of the zone still steps', 9.0, p.Value, EPS);
  finally
    p.Free;
  end;
end;

procedure TFloatSpinEditTest.ClickingOffTheHalvesDoesNotStep;
{ The negative half of the same edges — a zone that has quietly grown is invisible without it. }
var
  p: TFloatSpinProbe;
  z: TRect;
begin
  p := NewProbe;
  try
    z := p.Zone(p.Font.PixelsPerInch);
    p.Increment := 0.5;
    p.Value := 4;
    p.ClickAt(z.Left - 1, z.Top);          // one pixel left of the column: that is the text area
    AssertEquals('a click in the text does not step', 4.0, p.Value, EPS);
    p.ClickAt(z.Right, z.Top);             // one past the right edge: the field's right padding
    AssertEquals('nor does one past the right edge', 4.0, p.Value, EPS);
    p.ClickAt(z.Left, z.Top - 1);          // above the zone: the field's top padding
    AssertEquals('nor one above it', 4.0, p.Value, EPS);
    p.ClickAt(z.Left, z.Bottom);           // below the zone
    AssertEquals('nor one below it', 4.0, p.Value, EPS);
  finally
    p.Free;
  end;
end;

procedure TFloatSpinEditTest.ArrowKeysStep;
var
  p: TFloatSpinProbe;
begin
  p := NewProbe;
  try
    p.Increment := 2.5;
    p.Value := 0;
    p.DoKey(VK_UP, []);
    AssertEquals('up', 2.5, p.Value, EPS);
    p.DoKey(VK_DOWN, []);
    p.DoKey(VK_DOWN, []);
    AssertEquals('down twice', -2.5, p.Value, EPS);
  finally
    p.Free;
  end;
end;

procedure TFloatSpinEditTest.AnOnKeyDownHandlerCanVetoTheStep;
{ The application's OnKeyDown runs first (it is raised from inside the inherited handler) and a
  handler that zeroes Key has consumed the keystroke. Stepping anyway would make the veto a lie —
  which is what the integer sibling does, because it steps BEFORE inherited and so never gives
  the handler a turn. }
var
  p: TFloatSpinProbe;
begin
  p := NewProbe;
  try
    p.Increment := 1;
    p.Value := 7;
    FVetoed := 0;
    p.SetKeyDownHandler(@VetoEveryKey);
    p.DoKey(VK_UP, []);
    AssertEquals('the handler saw the key', 1, FVetoed);
    AssertEquals('and consuming it stopped the step', 7.0, p.Value, EPS);
    p.SetKeyDownHandler(nil);
    p.DoKey(VK_UP, []);
    AssertEquals('with no handler in the way it steps again', 8.0, p.Value, EPS);
  finally
    p.Free;
  end;
end;

procedure TFloatSpinEditTest.AnOnKeyDownHandlerCanRemapTheStep;
{ The other half of "read Key AFTER inherited, not a copy from before it". A handler that
  rewrites VK_UP into VK_DOWN has redirected the gesture, and the control must obey the key it
  was left with. This is what a saved-copy guard silently broke: it kept the pre-handler key,
  saw it differ, and simply refused to step at all. }
var
  p: TFloatSpinProbe;
begin
  p := NewProbe;
  try
    p.Increment := 1;
    p.Value := 7;
    p.SetKeyDownHandler(@RemapUpToDown);
    p.DoKey(VK_UP, []);
    AssertEquals('the handler''s key is the one that acts', 6.0, p.Value, EPS);
  finally
    p.Free;
  end;
end;

procedure TFloatSpinEditTest.TheWheelSteps;
var
  p: TFloatSpinProbe;
begin
  p := NewProbe;
  try
    p.Increment := 0.5;
    p.Value := 0;
    AssertTrue('the notch is reported handled', p.Wheel(120));
    AssertEquals('wheel up steps up', 0.5, p.Value, EPS);
    AssertTrue('and so is the other direction', p.Wheel(-120));
    AssertEquals('wheel down steps down', 0.0, p.Value, EPS);
  finally
    p.Free;
  end;
end;

procedure TFloatSpinEditTest.StepsClampToTheRange;
{ MaxValue > MinValue is what turns clamping ON (inherited from TTyNumericEdit, and LCL's own
  rule); an empty range means "no limit", so both are checked. }
var
  p: TFloatSpinProbe;
begin
  p := NewProbe;
  try
    p.MinValue := 0;
    p.MaxValue := 1;
    p.Increment := 0.75;
    p.Value := 0.5;
    p.DoKey(VK_UP, []);
    AssertEquals('stopped at the ceiling', 1.0, p.Value, EPS);
    p.DoKey(VK_DOWN, []);
    p.DoKey(VK_DOWN, []);
    AssertEquals('and at the floor', 0.0, p.Value, EPS);
  finally
    p.Free;
  end;

  p := NewProbe;
  try
    p.MinValue := 0;
    p.MaxValue := 0;                  // empty range == unbounded
    p.Increment := 1000;
    p.Value := 0;
    p.DoKey(VK_UP, []);
    AssertEquals('an empty range does not clamp', 1000.0, p.Value, EPS);
  finally
    p.Free;
  end;
end;

procedure TFloatSpinEditTest.SteppingMarksTheFieldModified;
{ The arrows ARE the user editing. The step writes through the published Text setter, whose
  contract is to CLEAR Modified — so without the restore, clicking up would clean a field the
  user had just changed, which is exactly what an enable-Save handler reads. }
var
  p: TFloatSpinProbe;
  u: TRect;
begin
  p := NewProbe;
  try
    u := p.UpButtonRect(p.Font.PixelsPerInch);
    p.Value := 1;                          // programmatic: clean
    AssertFalse('a programmatic write is not the user editing', p.Modified);
    p.ClickAt(u.Left, u.Top);
    AssertTrue('clicking the up button is', p.Modified);

    p.Value := 1;                          // programmatic again: clean once more
    AssertFalse('and the code writing it cleans the flag', p.Modified);
    p.DoKey(VK_DOWN, []);
    AssertTrue('an arrow key dirties it too', p.Modified);

    p.Value := 1;
    p.Wheel(120);
    AssertTrue('and so does the wheel', p.Modified);
  finally
    p.Free;
  end;
end;

procedure TFloatSpinEditTest.ReadOnlyBlocksEveryStepPath;
{ ReadOnly locks the VALUE, arrows included — LCL guards its widgetset step the same way, and
  so does the integer sibling. All four routes, because each one calls StepValue separately. }
var
  p: TFloatSpinProbe;
  u, d: TRect;
begin
  p := NewProbe;
  try
    u := p.UpButtonRect(p.Font.PixelsPerInch);
    d := p.DownButtonRect(p.Font.PixelsPerInch);
    p.Increment := 1;
    p.Value := 5;
    p.ReadOnly := True;
    p.ClickAt(u.Left, u.Top);
    AssertEquals('the up button does not step', 5.0, p.Value, EPS);
    p.ClickAt(d.Right - 1, d.Bottom - 1);
    AssertEquals('nor the down button', 5.0, p.Value, EPS);
    p.DoKey(VK_UP, []);
    AssertEquals('nor an arrow key', 5.0, p.Value, EPS);
    p.Wheel(120);
    AssertEquals('nor the wheel', 5.0, p.Value, EPS);
    AssertFalse('and nothing marked the field edited', p.Modified);
    p.ReadOnly := False;
    p.DoKey(VK_UP, []);
    AssertEquals('unlocking restores every one of them', 6.0, p.Value, EPS);
  finally
    p.Free;
  end;
end;

procedure TFloatSpinEditTest.TheWheelIsReportedUnhandledWhenReadOnly;
{ Returning True over a field that cannot use the notch swallows the wheel: the scroll box the
  field sits in stops scrolling, and the user has no idea why. }
var
  p: TFloatSpinProbe;
begin
  p := NewProbe;
  try
    p.ReadOnly := True;
    AssertFalse('a read-only field passes the notch on', p.Wheel(120));
    p.ReadOnly := False;
    AssertTrue('an editable one consumes it', p.Wheel(120));
  finally
    p.Free;
  end;
end;

{ -------------------------------------------------------------- EditorEnabled ---- }

procedure TFloatSpinEditTest.EditorEnabledFalseBlocksTyping;
var
  p: TFloatSpinProbe;
begin
  p := NewProbe;
  try
    p.Text := '1';
    p.EditorEnabled := False;
    p.TypeChar('2');
    p.TypeChar('3');
    AssertEquals('a locked editor accepts no characters', '1', p.Text);
    p.EditorEnabled := True;
    p.TypeChar('2');
    AssertEquals('and unlocking lets them through again', '12', p.Text);
  finally
    p.Free;
  end;

  { The half that says WHERE the key has to be refused. FilterInsert also returns '' while the
    editor is locked, so a keystroke with no selection is refused either way — but InjectKey
    DELETES THE SELECTION BEFORE it consults the filter (Edit.pas:1858-1869). Refuse the key only
    in the filter and a locked field quietly loses whatever the user had selected every time they
    hit a digit. Without the live selection here the two spellings are indistinguishable, and the
    mutation run proved it: removing the UTF8KeyPress guard changed no result. }
  p := NewProbe;
  try
    p.Text := '1234';
    p.SelStart := 1;
    p.SelLength := 2;                     // '23' selected
    p.EditorEnabled := False;
    p.TypeChar('9');
    AssertEquals('a locked editor must not eat the selection either', '1234', p.Text);
    AssertEquals('and the selection itself is still there', 2, p.SelLength);
  finally
    p.Free;
  end;
end;

procedure TFloatSpinEditTest.EditorEnabledFalseBlocksBackspaceAndDelete;
var
  p: TFloatSpinProbe;
begin
  p := NewProbe;
  try
    p.Text := '4567';
    p.CaretPos := 2;
    p.EditorEnabled := False;
    p.DoKey(VK_BACK, []);
    AssertEquals('backspace is refused', '4567', p.Text);
    p.DoKey(VK_DELETE, []);
    AssertEquals('and so is delete', '4567', p.Text);
    p.DoKey(VK_BACK, [ssCtrl]);
    AssertEquals('including the word-wise forms', '4567', p.Text);
    p.EditorEnabled := True;
    p.DoKey(VK_BACK, []);
    AssertEquals('unlocking restores them', '467', p.Text);
  finally
    p.Free;
  end;
end;

procedure TFloatSpinEditTest.EditorEnabledFalseBlocksTheClipboardAndUndoKeys;
{ Cut, paste, undo and redo all rewrite the text from the keyboard, so a keyboard lock has to
  stop them too. Undo is the sharp one: it is the only route that can put back text the field
  no longer holds, without any insertion filter ever being consulted. }
var
  p: TFloatSpinProbe;
begin
  p := NewProbe;
  try
    p.Text := '';
    p.TypeChar('7');
    p.TypeChar('8');
    AssertEquals('precondition: there is something to undo', '78', p.Text);
    p.SelStart := 0;
    p.SelLength := 2;
    p.EditorEnabled := False;
    p.DoKey(VK_X, [ssCtrl]);
    AssertEquals('cut is refused', '78', p.Text);
    p.DoKey(VK_V, [ssCtrl]);
    AssertEquals('paste is refused', '78', p.Text);
    p.DoKey(VK_Z, [ssCtrl]);
    AssertEquals('undo is refused', '78', p.Text);
    p.DoKey(VK_Y, [ssCtrl]);
    AssertEquals('redo is refused', '78', p.Text);
    p.EditorEnabled := True;
    p.DoKey(VK_Z, [ssCtrl]);
    AssertTrue('and unlocking makes undo reachable again', p.Text <> '78');
  finally
    p.Free;
  end;
end;

procedure TFloatSpinEditTest.EditorEnabledFalseBlocksABulkInsert;
{ The other chokepoint: an IME commit and a programmatic paste both arrive as one string at
  InjectStringAt, which never goes near UTF8KeyPress. Without the FilterInsert guard a locked
  field would still take a whole CJK/IME commit. }
var
  p: TFloatSpinProbe;
begin
  p := NewProbe;
  try
    p.Text := '9';
    p.EditorEnabled := False;
    p.Paste('123');
    AssertEquals('a bulk insert is refused too', '9', p.Text);
    p.EditorEnabled := True;
    p.Paste('123');
    AssertEquals('and accepted once the editor is open', '9123', p.Text);
  finally
    p.Free;
  end;
end;

procedure TFloatSpinEditTest.EditorEnabledFalseStillLetsEveryStepPathRun;
{ The whole point of the property: "choose with the arrows, do not type" — a field pinned to a
  legal grid. If the lock reached the steppers as well, EditorEnabled would just be a second,
  worse ReadOnly. }
var
  p: TFloatSpinProbe;
  u: TRect;
begin
  p := NewProbe;
  try
    u := p.UpButtonRect(p.Font.PixelsPerInch);
    p.Increment := 0.5;
    p.Value := 0;
    p.EditorEnabled := False;
    p.ClickAt(u.Left, u.Top);
    AssertEquals('the button still steps', 0.5, p.Value, EPS);
    p.DoKey(VK_UP, []);
    AssertEquals('the arrow key still steps', 1.0, p.Value, EPS);
    p.Wheel(120);
    AssertEquals('the wheel still steps', 1.5, p.Value, EPS);
  finally
    p.Free;
  end;
end;

procedure TFloatSpinEditTest.ReadOnlyAndEditorEnabledAreTwoDifferentLocks;
{ Orthogonal, exactly as LCL keeps them (spin.pp:79 next to ReadOnly). Asserted as a matrix so
  neither can quietly start implying the other. }
var
  p: TFloatSpinProbe;
begin
  p := NewProbe;
  try
    p.Increment := 1;
    p.Value := 0;
    p.ReadOnly := True;                 // value locked, editor still nominally open
    AssertTrue('EditorEnabled is untouched by ReadOnly', p.EditorEnabled);
    p.DoKey(VK_UP, []);
    AssertEquals('ReadOnly stops the step', 0.0, p.Value, EPS);

    p.ReadOnly := False;
    p.EditorEnabled := False;           // keyboard locked, value still steppable
    AssertFalse('ReadOnly is untouched by EditorEnabled', p.ReadOnly);
    p.DoKey(VK_UP, []);
    AssertEquals('EditorEnabled does not stop the step', 1.0, p.Value, EPS);
    p.Text := '';
    p.TypeChar('5');
    AssertEquals('but it does stop the typing', '', p.Text);
  finally
    p.Free;
  end;
end;

initialization
  RegisterTest(TFloatSpinEditTest);
end.
