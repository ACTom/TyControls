unit test.spinbuttons;
{$mode objfpc}{$H+}

{ The spin buttons of TTySpinEdit and TTyFloatSpinEdit, as a pointer sees them (TTySpinButtons).

  Users reported the two buttons too small to hit. Their size is the theme's; what these cover is
  what a native spinner gives a small target, and what the buttons did not do:
  - the arrow cursor over the buttons (it was the I-beam, which says "text"), and the control's
    own cursor back once the pointer leaves them;
  - a hover and a pressed state on the half under the pointer, in TyButton's :hover / :active
    background (they did not react at all);
  - hold to repeat (a press stepped once, so a bigger change took a click per step).

  Both controls are run through every case: they share the behaviour but not an ancestor, so each
  wires it up on its own, and either wiring can be the one that is missing. }

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics, ExtCtrls, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.SpinEdit, tyControls.FloatSpinEdit;

type
  TSpinButtonsTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FSpin: TControl;     // the control under test: a TTySpinEdit or a TTyFloatSpinEdit
    FFloat: Boolean;
    procedure Build(AFloat: Boolean; const ACss: string = '');
    function Buttons: TTySpinButtons;
    function UpRect: TRect;
    function DownRect: TRect;
    function TextPoint: TPoint;
    procedure Move(const APt: TPoint);
    procedure Press(const APt: TPoint);
    procedure Release(const APt: TPoint);
    procedure Leave;
    function NumValue: Double;
    procedure SetReadOnly(AValue: Boolean);
    { The colour at APt in a fresh render. }
    function PixelAt(const APt: TPoint): TBGRAPixel;
    { A point in a half, clear of its arrow: one pixel in from the half's left edge, which the
      centred square glyph box never reaches. }
    function ClearOfTheArrow(const AHalf: TRect): TPoint;
    procedure CheckArrowCursorOverTheButtons;
    procedure CheckOwnCursorComesBack;
    procedure CheckHoverAndPressLightTheHalf;
    procedure CheckReadOnlyButtonsDoNotLight;
    procedure CheckHoldRepeatsUntilRelease;
    procedure CheckLeavingWhileHeldStopsTheRepeat;
    procedure CheckWithoutAWindowAPressStepsOnce;
    procedure CheckFillStaysInsideTheFocusRing;
  protected
    procedure TearDown; override;
  published
    procedure TestSpinEditArrowCursorOverTheButtons;
    procedure TestSpinEditOwnCursorComesBack;
    procedure TestSpinEditHoverAndPressLightTheHalf;
    procedure TestSpinEditReadOnlyButtonsDoNotLight;
    procedure TestSpinEditHoldRepeatsUntilRelease;
    procedure TestSpinEditLeavingWhileHeldStopsTheRepeat;
    procedure TestSpinEditWithoutAWindowAPressStepsOnce;
    procedure TestSpinEditFillStaysInsideTheFocusRing;
    procedure TestFloatSpinEditArrowCursorOverTheButtons;
    procedure TestFloatSpinEditOwnCursorComesBack;
    procedure TestFloatSpinEditHoverAndPressLightTheHalf;
    procedure TestFloatSpinEditReadOnlyButtonsDoNotLight;
    procedure TestFloatSpinEditHoldRepeatsUntilRelease;
    procedure TestFloatSpinEditLeavingWhileHeldStopsTheRepeat;
    procedure TestFloatSpinEditWithoutAWindowAPressStepsOnce;
    procedure TestFloatSpinEditFillStaysInsideTheFocusRing;
  end;

implementation

type
  TSpinX = class(TTySpinEdit)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure DoMove(X, Y: Integer);
    procedure DoPress(X, Y: Integer);
    procedure DoRelease(X, Y: Integer);
    procedure DoLeave;
    function Btns: TTySpinButtons;
  end;

  TFloatX = class(TTyFloatSpinEdit)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure DoMove(X, Y: Integer);
    procedure DoPress(X, Y: Integer);
    procedure DoRelease(X, Y: Integer);
    procedure DoLeave;
    function Btns: TTySpinButtons;
  end;

const
  { Field white with a grey hairline; a hovered button half red, a pressed one blue -- colours no
    other part of the control is drawn in, so a pixel says which state it was painted in. }
  cSpinCss =
    'TySpinEdit { background: #FFFFFF; color: #000000; border-color: #808080; ' +
      'border-width: 1px; border-radius: 0px; padding: 2px 4px; }' +
    'TyEdit { background: #FFFFFF; color: #000000; border-color: #808080; ' +
      'border-width: 1px; border-radius: 0px; padding: 4px 4px; }' +
    'TyButton { background: #00FF00; color: #000000; }' +
    'TyButton:hover { background: #FF0000; color: #000000; }' +
    'TyButton:active { background: #0000FF; color: #FFFFFF; }';

procedure TSpinX.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TSpinX.DoMove(X, Y: Integer);
begin
  MouseMove([], X, Y);
end;

procedure TSpinX.DoPress(X, Y: Integer);
begin
  MouseDown(mbLeft, [ssLeft], X, Y);
end;

procedure TSpinX.DoRelease(X, Y: Integer);
begin
  MouseUp(mbLeft, [], X, Y);
end;

procedure TSpinX.DoLeave;
begin
  MouseLeave;
end;

function TSpinX.Btns: TTySpinButtons;
begin
  Result := SpinButtons;
end;

procedure TFloatX.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TFloatX.DoMove(X, Y: Integer);
begin
  MouseMove([], X, Y);
end;

procedure TFloatX.DoPress(X, Y: Integer);
begin
  MouseDown(mbLeft, [ssLeft], X, Y);
end;

procedure TFloatX.DoRelease(X, Y: Integer);
begin
  MouseUp(mbLeft, [], X, Y);
end;

procedure TFloatX.DoLeave;
begin
  MouseLeave;
end;

function TFloatX.Btns: TTySpinButtons;
begin
  Result := SpinButtons;
end;

{ The repeat cases need a real window (the repeat arms only on one). The console runner never
  calls Application.Initialize, so the widgetset's window classes are unregistered and
  CreateHandle fails with 1407. Lazy + local, the pattern test.base and test.dropbuttons use. }
var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

{ TSpinButtonsTest }

procedure TSpinButtonsTest.Build(AFloat: Boolean; const ACss: string);
begin
  FFloat := AFloat;
  FCtl := TTyStyleController.Create(nil);
  if ACss <> '' then FCtl.LoadThemeCss(ACss) else FCtl.LoadThemeCss(cSpinCss);
  FForm := TForm.CreateNew(nil);
  FForm.Color := clWhite;   // the controls composite onto their parent
  FForm.SetBounds(0, 0, 300, 120);
  if AFloat then
  begin
    FSpin := TFloatX.Create(FForm);
    TFloatX(FSpin).Controller := FCtl;
    TFloatX(FSpin).Font.PixelsPerInch := 96;
    TFloatX(FSpin).Value := 5;
  end
  else
  begin
    FSpin := TSpinX.Create(FForm);
    TSpinX(FSpin).Controller := FCtl;
    TSpinX(FSpin).Font.PixelsPerInch := 96;
    TSpinX(FSpin).Value := 5;
  end;
  FSpin.Parent := FForm;
  FSpin.SetBounds(10, 10, 120, 28);
end;

procedure TSpinButtonsTest.TearDown;
begin
  FreeAndNil(FForm);   // owns the control
  FreeAndNil(FCtl);
  FSpin := nil;
end;

function TSpinButtonsTest.Buttons: TTySpinButtons;
begin
  if FFloat then Result := TFloatX(FSpin).Btns else Result := TSpinX(FSpin).Btns;
end;

function TSpinButtonsTest.UpRect: TRect;
begin
  if FFloat then
    Result := TFloatX(FSpin).UpButtonRect(96)
  else
    Result := TySpinUpButtonRect(Rect(0, 0, FSpin.Width, FSpin.Height), 96);
end;

function TSpinButtonsTest.DownRect: TRect;
begin
  if FFloat then
    Result := TFloatX(FSpin).DownButtonRect(96)
  else
    Result := TySpinDownButtonRect(Rect(0, 0, FSpin.Width, FSpin.Height), 96);
end;

function TSpinButtonsTest.TextPoint: TPoint;
begin
  Result := Point(10, FSpin.Height div 2);
end;

procedure TSpinButtonsTest.Move(const APt: TPoint);
begin
  if FFloat then TFloatX(FSpin).DoMove(APt.X, APt.Y) else TSpinX(FSpin).DoMove(APt.X, APt.Y);
end;

procedure TSpinButtonsTest.Press(const APt: TPoint);
begin
  if FFloat then TFloatX(FSpin).DoPress(APt.X, APt.Y) else TSpinX(FSpin).DoPress(APt.X, APt.Y);
end;

procedure TSpinButtonsTest.Release(const APt: TPoint);
begin
  if FFloat then TFloatX(FSpin).DoRelease(APt.X, APt.Y)
  else TSpinX(FSpin).DoRelease(APt.X, APt.Y);
end;

procedure TSpinButtonsTest.Leave;
begin
  if FFloat then TFloatX(FSpin).DoLeave else TSpinX(FSpin).DoLeave;
end;

function TSpinButtonsTest.NumValue: Double;
begin
  if FFloat then Result := TFloatX(FSpin).Value else Result := TSpinX(FSpin).Value;
end;

procedure TSpinButtonsTest.SetReadOnly(AValue: Boolean);
begin
  if FFloat then TFloatX(FSpin).ReadOnly := AValue else TSpinX(FSpin).ReadOnly := AValue;
end;

function TSpinButtonsTest.PixelAt(const APt: TPoint): TBGRAPixel;
var
  bmp: TBitmap;
  px: TBGRABitmap;
  r: TRect;
begin
  r := Rect(0, 0, FSpin.Width, FSpin.Height);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(r.Right, r.Bottom);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(r);
    if FFloat then TFloatX(FSpin).RenderTo(bmp.Canvas, r, 96)
    else TSpinX(FSpin).RenderTo(bmp.Canvas, r, 96);
    px := TBGRABitmap.Create(bmp);
    try
      Result := px.GetPixel(APt.X, APt.Y);
    finally
      px.Free;
    end;
  finally
    bmp.Free;
  end;
end;

function TSpinButtonsTest.ClearOfTheArrow(const AHalf: TRect): TPoint;
begin
  Result := Point(AHalf.Left + 1, (AHalf.Top + AHalf.Bottom) div 2);
end;

function IsWhite(const C: TBGRAPixel): Boolean;
begin
  Result := (C.red > 240) and (C.green > 240) and (C.blue > 240);
end;

function IsRed(const C: TBGRAPixel): Boolean;
begin
  Result := (C.red > 200) and (C.green < 60) and (C.blue < 60);
end;

function IsBlue(const C: TBGRAPixel): Boolean;
begin
  Result := (C.red < 60) and (C.green < 60) and (C.blue > 200);
end;

function PxStr(const C: TBGRAPixel): string;
begin
  Result := Format('(%d,%d,%d)', [C.red, C.green, C.blue]);
end;

{ ---- the cases, each run for both controls ---- }

procedure TSpinButtonsTest.CheckArrowCursorOverTheButtons;
var
  u, d: TRect;
begin
  u := UpRect;
  d := DownRect;
  AssertEquals('precondition: the field shows the I-beam', Ord(crIBeam), Ord(FSpin.Cursor));
  Move(CenterPoint(u));
  AssertEquals('over the up button: the arrow', Ord(crArrow), Ord(FSpin.Cursor));
  Move(CenterPoint(d));
  AssertEquals('over the down button: the arrow', Ord(crArrow), Ord(FSpin.Cursor));
  Move(TextPoint);
  AssertEquals('back over the text: the I-beam again', Ord(crIBeam), Ord(FSpin.Cursor));
  Move(CenterPoint(u));
  Leave;
  AssertEquals('leaving from a button puts the I-beam back too', Ord(crIBeam), Ord(FSpin.Cursor));
end;

procedure TSpinButtonsTest.CheckOwnCursorComesBack;
begin
  FSpin.Cursor := crHandPoint;
  Move(CenterPoint(UpRect));
  AssertEquals('the arrow over a button', Ord(crArrow), Ord(FSpin.Cursor));
  Move(TextPoint);
  AssertEquals('and the control''s own cursor back after it, not a hard-coded I-beam',
    Ord(crHandPoint), Ord(FSpin.Cursor));
end;

procedure TSpinButtonsTest.CheckHoverAndPressLightTheHalf;
var
  pu, pd: TPoint;
  c: TBGRAPixel;
begin
  pu := ClearOfTheArrow(UpRect);
  pd := ClearOfTheArrow(DownRect);
  c := PixelAt(pu);
  AssertTrue('precondition: an idle up half is the field''s white, got ' + PxStr(c), IsWhite(c));

  Move(CenterPoint(UpRect));
  c := PixelAt(pu);
  AssertTrue('hovered: the up half in TyButton:hover red, got ' + PxStr(c), IsRed(c));
  c := PixelAt(pd);
  AssertTrue('and only that half: the down half stays white, got ' + PxStr(c), IsWhite(c));

  Press(CenterPoint(UpRect));
  c := PixelAt(pu);
  AssertTrue('pressed: the up half in TyButton:active blue, got ' + PxStr(c), IsBlue(c));
  { The middle of the half is on the arrow. TyButton:active's ink is white: the field's black
    arrow on the pressed blue would be the state drawn with the wrong ink. }
  c := PixelAt(CenterPoint(UpRect));
  AssertFalse('and its arrow in TyButton:active''s white ink, not the field''s black, got ' +
    PxStr(c), (c.red < 80) and (c.green < 80) and (c.blue < 80));
  Release(CenterPoint(UpRect));
  c := PixelAt(pu);
  AssertTrue('released under the pointer: hovered again, got ' + PxStr(c), IsRed(c));

  Move(CenterPoint(DownRect));
  c := PixelAt(pd);
  AssertTrue('the down half lights the same way, got ' + PxStr(c), IsRed(c));
  c := PixelAt(pu);
  AssertTrue('and the up half has gone back to white, got ' + PxStr(c), IsWhite(c));

  Leave;
  c := PixelAt(pd);
  AssertTrue('the pointer gone: nothing lit, got ' + PxStr(c), IsWhite(c));
end;

procedure TSpinButtonsTest.CheckReadOnlyButtonsDoNotLight;
var
  c: TBGRAPixel;
  v: Double;
begin
  SetReadOnly(True);
  v := NumValue;
  Move(CenterPoint(UpRect));
  AssertEquals('read-only: the buttons are still not text, so the arrow', Ord(crArrow),
    Ord(FSpin.Cursor));
  c := PixelAt(ClearOfTheArrow(UpRect));
  AssertTrue('but a button that will not step does not light up, got ' + PxStr(c), IsWhite(c));
  Press(CenterPoint(UpRect));
  c := PixelAt(ClearOfTheArrow(UpRect));
  AssertTrue('nor look pressed, got ' + PxStr(c), IsWhite(c));
  AssertEquals('and the value stays', v, NumValue, 0);
  Release(CenterPoint(UpRect));
end;

procedure TSpinButtonsTest.CheckHoldRepeatsUntilRelease;
var
  t: TTimer;
begin
  NeedWidgetSet;
  FForm.HandleNeeded;
  TWinControl(FSpin).HandleNeeded;
  AssertTrue('precondition: the control has a window', TWinControl(FSpin).HandleAllocated);
  Press(CenterPoint(UpRect));
  AssertEquals('the press steps once at once', 6.0, NumValue, 1e-9);
  t := Buttons.RepeatTimer;
  AssertTrue('and arms the repeat', (t <> nil) and t.Enabled);
  AssertEquals('after the initial delay', 400, Integer(t.Interval));
  t.OnTimer(t);
  AssertEquals('the delay over: a step', 7.0, NumValue, 1e-9);
  AssertEquals('and from then on the fast interval', 100, Integer(t.Interval));
  t.OnTimer(t);
  AssertEquals('another step per tick', 8.0, NumValue, 1e-9);
  Release(CenterPoint(UpRect));
  AssertFalse('the release stops it', t.Enabled);
  t.OnTimer(t);
  AssertEquals('and a tick already queued steps nothing', 8.0, NumValue, 1e-9);

  Press(CenterPoint(DownRect));
  AssertEquals('down repeats the same way: the press', 7.0, NumValue, 1e-9);
  AssertEquals('starting from the initial delay again', 400, Integer(t.Interval));
  t.OnTimer(t);
  AssertEquals('then a tick', 6.0, NumValue, 1e-9);
  Release(CenterPoint(DownRect));

  { A tick comes from a timer, after the press was let through: ReadOnly switched on in between
    must still stop it, as it stops every other way of stepping. }
  Press(CenterPoint(UpRect));
  AssertEquals('precondition: held up again', 7.0, NumValue, 1e-9);
  SetReadOnly(True);
  t.OnTimer(t);
  AssertEquals('read-only now: a tick steps nothing', 7.0, NumValue, 1e-9);
  Release(CenterPoint(UpRect));
end;

procedure TSpinButtonsTest.CheckLeavingWhileHeldStopsTheRepeat;
var
  t: TTimer;
begin
  NeedWidgetSet;
  FForm.HandleNeeded;
  TWinControl(FSpin).HandleNeeded;
  Press(CenterPoint(UpRect));
  t := Buttons.RepeatTimer;
  AssertTrue('precondition: held and repeating', (t <> nil) and t.Enabled);
  Leave;
  AssertFalse('the pointer leaving ends the hold', t.Enabled);
  AssertEquals('and nothing is held any more', 0, Buttons.Held);
end;

procedure TSpinButtonsTest.CheckWithoutAWindowAPressStepsOnce;
begin
  AssertFalse('precondition: no window', TWinControl(FSpin).HandleAllocated);
  Press(CenterPoint(UpRect));
  AssertEquals('the press still steps', 6.0, NumValue, 1e-9);
  AssertTrue('but arms no timer that nothing would ever release', Buttons.RepeatTimer = nil);
  Release(CenterPoint(UpRect));
end;

{ The field's focus ring is stroked INSIDE the control, and it can be wider than the border (light:
  2px, macOS: 3px). A hover fill inset by the border alone covered its inner pixels -- the report
  was "the hover hides part of the focus frame". A 3px cyan ring, in the plain rule so no real
  focus is needed: the column just inside the edge must stay cyan with the up half hovered, and
  the fill must still reach the column just inside the ring. }
procedure TSpinButtonsTest.CheckFillStaysInsideTheFocusRing;
var
  u: TRect;
  y: Integer;
  c: TBGRAPixel;
begin
  u := UpRect;
  y := (u.Top + u.Bottom) div 2;
  c := PixelAt(Point(FSpin.Width - 2, y));
  AssertTrue('precondition: the ring is drawn, cyan, at the right edge, got ' + PxStr(c),
    (c.red < 60) and (c.green > 200) and (c.blue > 200));
  Move(CenterPoint(u));
  c := PixelAt(Point(FSpin.Width - 2, y));
  AssertTrue('hovered: the ring is still cyan, not covered by the red fill, got ' + PxStr(c),
    (c.red < 60) and (c.green > 200) and (c.blue > 200));
  c := PixelAt(Point(FSpin.Width - 4, y));
  AssertTrue('and the fill reaches right up to it, got ' + PxStr(c), IsRed(c));
end;

{ ---- published: each case for each control ---- }

procedure TSpinButtonsTest.TestSpinEditArrowCursorOverTheButtons;
begin Build(False); CheckArrowCursorOverTheButtons; end;

procedure TSpinButtonsTest.TestSpinEditOwnCursorComesBack;
begin Build(False); CheckOwnCursorComesBack; end;

procedure TSpinButtonsTest.TestSpinEditHoverAndPressLightTheHalf;
begin Build(False); CheckHoverAndPressLightTheHalf; end;

procedure TSpinButtonsTest.TestSpinEditReadOnlyButtonsDoNotLight;
begin Build(False); CheckReadOnlyButtonsDoNotLight; end;

procedure TSpinButtonsTest.TestSpinEditHoldRepeatsUntilRelease;
begin Build(False); CheckHoldRepeatsUntilRelease; end;

procedure TSpinButtonsTest.TestSpinEditLeavingWhileHeldStopsTheRepeat;
begin Build(False); CheckLeavingWhileHeldStopsTheRepeat; end;

procedure TSpinButtonsTest.TestSpinEditWithoutAWindowAPressStepsOnce;
begin Build(False); CheckWithoutAWindowAPressStepsOnce; end;

procedure TSpinButtonsTest.TestSpinEditFillStaysInsideTheFocusRing;
begin
  Build(False, StringReplace(cSpinCss, 'border-radius: 0px;',
    'border-radius: 0px; outline: 3px #00FFFF;', [rfReplaceAll]));
  CheckFillStaysInsideTheFocusRing;
end;

procedure TSpinButtonsTest.TestFloatSpinEditArrowCursorOverTheButtons;
begin Build(True); CheckArrowCursorOverTheButtons; end;

procedure TSpinButtonsTest.TestFloatSpinEditOwnCursorComesBack;
begin Build(True); CheckOwnCursorComesBack; end;

procedure TSpinButtonsTest.TestFloatSpinEditHoverAndPressLightTheHalf;
begin Build(True); CheckHoverAndPressLightTheHalf; end;

procedure TSpinButtonsTest.TestFloatSpinEditReadOnlyButtonsDoNotLight;
begin Build(True); CheckReadOnlyButtonsDoNotLight; end;

procedure TSpinButtonsTest.TestFloatSpinEditHoldRepeatsUntilRelease;
begin Build(True); CheckHoldRepeatsUntilRelease; end;

procedure TSpinButtonsTest.TestFloatSpinEditLeavingWhileHeldStopsTheRepeat;
begin Build(True); CheckLeavingWhileHeldStopsTheRepeat; end;

procedure TSpinButtonsTest.TestFloatSpinEditWithoutAWindowAPressStepsOnce;
begin Build(True); CheckWithoutAWindowAPressStepsOnce; end;

procedure TSpinButtonsTest.TestFloatSpinEditFillStaysInsideTheFocusRing;
begin
  Build(True, StringReplace(cSpinCss, 'border-radius: 0px;',
    'border-radius: 0px; outline: 3px #00FFFF;', [rfReplaceAll]));
  CheckFillStaysInsideTheFocusRing;
end;

initialization
  RegisterTest(TSpinButtonsTest);
end.
