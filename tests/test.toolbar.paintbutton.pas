unit test.toolbar.paintbutton;
{$mode objfpc}{$H+}
{ Guards TTyToolBar.OnPaintButton — LCL's per-button owner draw, whole-replacement flavour:
  while the BAR's handler is assigned, every tool button's Paint is the handler and nothing
  else, for all six styles (LCL calls it and exits before the themed draw, separators
  included); clearing it restores the themed default byte for byte.

  The assertions are pixel assertions driven through the REAL windowed funnel
  (TCustomControl.PaintWindow), the same way test.parity.onpaint drives OnPaint — driving
  RenderTo would prove nothing, because the hook deliberately sits in Paint.

  The load-bearing test is the stale-DC one. The dispatch brackets the callback in
  Canvas.SaveHandleState / RestoreHandleState, NOT raw SaveDC/RestoreDC: RestoreDC swaps the
  DC's pen/font back while the LCL canvas goes on believing its own objects are selected, so
  the SECOND callback on the same bound canvas that assigns the SAME Pen.Color gets a silent
  no-op and strokes with whatever the restore put back. The second callback is REACHABLE:
  TCustomControl.PaintWindow only rebinds the canvas when the DC actually changed, so
  successive paints against one DC share one binding. The guard is built the only way that
  catches it — Pen + LineTo + TextOut probing the button's CORNERS, with a GetTextColor
  read-back per call. Brush + FillRect is deliberately NOT used: LCL hands FillRect the brush
  handle explicitly, so it is the one primitive this defect cannot bite, and a guard written
  around it was fake-green for two months once already (see tests/test.parity.combo.pas). }
interface
uses
  Classes, SysUtils, Types, Graphics, Controls, Forms, LCLType, LCLIntf,
  BGRABitmap, BGRABitmapTypes, fpcunit, testregistry,
  tyControls.GlyphButtons, tyControls.ToolBar;

type
  { PaintWindow is TWinControl-protected; the hover/pressed fields are TTyCustomControl-
    protected. A descendant declared here reaches both without a window handle. }
  TPaintButton = class(TTyToolButton)
  public
    procedure DrivePaint(ADC: HDC);
    procedure SetLiveState(AHover, APressed: Boolean);
  end;

  TToolBarPaintButtonTest = class(TTestCase)
  private
    FForm: TForm;
    FBar: TTyToolBar;
    FBtn: TPaintButton;
    FCalls: Integer;
    FStaleInk: Integer;          // callbacks whose DC ink was NOT the one the handler asked for
    FLastState: Integer;
    FLastSender: TObject;
    procedure HandleSilent(Sender: TTyToolButton; AState: Integer);
    procedure HandleMarker(Sender: TTyToolButton; AState: Integer);
    procedure HandleCorners(Sender: TTyToolButton; AState: Integer);
    procedure HandleOverflowing(Sender: TTyToolButton; AState: Integer);
    { One paint through the real funnel into a FRESH pre-filled target. Caller frees. }
    function PaintInto(AW, AH: Integer): TBGRABitmap;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { The state table, pure — LCL's GetButtonDrawDetail numbers. }
    procedure TestStateIntegersAreLcls;
    { Wiring. }
    procedure TestHandlerReplacesEverythingAndCarriesTheButton;
    procedure TestSeparatorRoutesThroughTheHandlerToo;
    procedure TestClearingTheHandlerRestoresTheThemedDefault;
    procedure TestLiveStateReachesTheHandler;
    procedure TestFlatDoesNotDistortTheState;
    procedure TestTheDesignerFiresItToo;
    { The two safety rails. }
    procedure TestHandlerIsClippedToItsButton;
    procedure TestSecondCallbackOnOneBindingStillInksItsOwnColour;
  end;

implementation

const
  { A colour no theme in the pack produces, so a pixel carrying it can only be the handler's. }
  MarkR = 255; MarkG = 0; MarkB = 255;
  { And a different one under everything, so "nothing painted here" is checkable. }
  UnderR = 0; UnderG = 255; UnderB = 255;
  BtnW = 60; BtnH = 24;
  Probe = TColor($00C800);     // GREEN, identical on every callback
  SeedRed = TColor($0000C8);   // what the DC holds when the callback begins

procedure TPaintButton.DrivePaint(ADC: HDC);
begin
  PaintWindow(ADC);
end;

procedure TPaintButton.SetLiveState(AHover, APressed: Boolean);
begin
  FHover := AHover;
  FPressed := APressed;
end;

function IsMark(const P: TBGRAPixel): Boolean;
begin
  Result := (P.red = MarkR) and (P.green = MarkG) and (P.blue = MarkB);
end;

function IsUnder(const P: TBGRAPixel): Boolean;
begin
  Result := (P.red = UnderR) and (P.green = UnderG) and (P.blue = UnderB);
end;

function NewTarget(AW, AH: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf32bit;
  Result.SetSize(AW, AH);
  Result.Canvas.Brush.Style := bsSolid;
  Result.Canvas.Brush.Color := RGBToColor(UnderR, UnderG, UnderB);
  Result.Canvas.FillRect(0, 0, AW, AH);
end;

procedure TToolBarPaintButtonTest.SetUp;
begin
  FCalls := 0;
  FStaleInk := 0;
  FLastState := -1;
  FLastSender := nil;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 200);
  FBar := TTyToolBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.Align := alNone;
  FBar.SetBounds(0, 0, 300, 30);
  FBtn := TPaintButton.Create(FForm);
  FBtn.Parent := FBar;
  FBtn.SetBounds(0, 0, BtnW, BtnH);
end;

procedure TToolBarPaintButtonTest.TearDown;
begin
  FreeAndNil(FForm);   // owns the bar and the button
end;

procedure TToolBarPaintButtonTest.HandleSilent(Sender: TTyToolButton; AState: Integer);
begin
  { Records and paints NOTHING. With this assigned, the button must render as if nobody
    painted at all — that is the whole-replacement half of the contract. }
  Inc(FCalls);
  FLastState := AState;
  FLastSender := Sender;
end;

procedure TToolBarPaintButtonTest.HandleMarker(Sender: TTyToolButton; AState: Integer);
var
  c: TCanvas;
begin
  Inc(FCalls);
  FLastState := AState;
  FLastSender := Sender;
  c := Sender.Canvas;   // the contract: Sender.Canvas IS the surface (LCL identical)
  c.Brush.Style := bsSolid;
  c.Brush.Color := RGBToColor(MarkR, MarkG, MarkB);
  c.FillRect(Sender.ClientRect);
end;

{ The shape that catches a canvas whose cached state no longer describes its DC: the SAME
  pen colour and the SAME ink on EVERY call. LineTo stops one short, so the two strokes
  cover exactly the four corners of the button. }
procedure TToolBarPaintButtonTest.HandleCorners(Sender: TTyToolButton; AState: Integer);
var
  c: TCanvas;
  r: TRect;
begin
  Inc(FCalls);
  c := Sender.Canvas;
  r := Sender.ClientRect;
  c.Pen.Color := Probe;
  c.Brush.Style := bsClear;
  c.Font.Color := Probe;
  c.MoveTo(r.Left, r.Top);
  c.LineTo(r.Right, r.Top);
  c.MoveTo(r.Left, r.Bottom - 1);
  c.LineTo(r.Right, r.Bottom - 1);
  { The TEXT path too: LCL sets the DC's text colour inside the FONT selection, so a font
    the canvas still believes is selected means SetTextColor is never reached. }
  c.TextOut(r.Left + 2, r.Top + 2, 'x');
  if LCLIntf.GetTextColor(c.Handle) <> Probe then Inc(FStaleInk);
end;

{ Strokes WELL OUTSIDE its own button. Everything beyond the client rect must be clipped. }
procedure TToolBarPaintButtonTest.HandleOverflowing(Sender: TTyToolButton; AState: Integer);
var
  c: TCanvas;
begin
  Inc(FCalls);
  c := Sender.Canvas;
  c.Brush.Style := bsSolid;
  c.Brush.Color := RGBToColor(MarkR, MarkG, MarkB);
  c.FillRect(-40, -40, Sender.Width + 200, Sender.Height + 200);
end;

function TToolBarPaintButtonTest.PaintInto(AW, AH: Integer): TBGRABitmap;
var
  bmp: TBitmap;
begin
  bmp := NewTarget(AW, AH);
  try
    FBtn.DrivePaint(bmp.Canvas.Handle);
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
  end;
end;

{ ---- the state table ------------------------------------------------------- }

procedure TToolBarPaintButtonTest.TestStateIntegersAreLcls;
begin
  { LCL's GetButtonDrawDetail collapsed to its TThemedElementDetails.State numbers:
    1 normal / 2 hot / 3 pressed / 4 disabled / 5 checked / 6 checked-hot. }
  AssertEquals('resting',              1, TyToolButtonPaintState(True,  False, False, False));
  AssertEquals('hot',                  2, TyToolButtonPaintState(True,  False, False, True));
  AssertEquals('pressed',              3, TyToolButtonPaintState(True,  False, True,  True));
  AssertEquals('pressed while down',   3, TyToolButtonPaintState(True,  True,  True,  True));
  AssertEquals('checked',              5, TyToolButtonPaintState(True,  True,  False, False));
  AssertEquals('checked-hot',          6, TyToolButtonPaintState(True,  True,  False, True));
  { Two of LCL's less obvious rows, both mirrored: a press whose pointer has LEFT the button
    is not pressed (LCL requires tbfPressed AND FMouseInControl)... }
  AssertEquals('press dragged off, up',   1, TyToolButtonPaintState(True, False, True, False));
  AssertEquals('press dragged off, down', 5, TyToolButtonPaintState(True, True,  True, False));
  { ...and disabled WINS over checked — LCL tests Enabled first. }
  AssertEquals('disabled',             4, TyToolButtonPaintState(False, False, False, False));
  AssertEquals('disabled beats down',  4, TyToolButtonPaintState(False, True,  False, False));
  AssertEquals('disabled beats hover', 4, TyToolButtonPaintState(False, False, False, True));
end;

{ ---- wiring ----------------------------------------------------------------- }

procedure TToolBarPaintButtonTest.TestHandlerReplacesEverythingAndCarriesTheButton;
var
  img: TBGRABitmap;
  x, y: Integer;
begin
  { The silent handler proves REPLACEMENT: with it assigned, not one themed pixel may land —
    the whole client stays the under-colour, which no themed button render leaves alone. }
  FBar.OnPaintButton := @HandleSilent;
  img := PaintInto(BtnW, BtnH);
  try
    for y := 0 to BtnH - 1 do
      for x := 0 to BtnW - 1 do
        AssertTrue(Format('(%d,%d) must still be the under-colour — the themed draw ran', [x, y]),
          IsUnder(img.GetPixel(x, y)));
  finally
    img.Free;
  end;
  AssertEquals('one paint, one callback', 1, FCalls);
  AssertTrue('Sender is the button that painted', FLastSender = FBtn);
  AssertEquals('a resting enabled button reports state 1', 1, FLastState);
end;

procedure TToolBarPaintButtonTest.TestSeparatorRoutesThroughTheHandlerToo;
var
  img: TBGRABitmap;
begin
  { LCL parity: its Paint calls the handler and exits BEFORE the style dispatch, so
    separators and dividers are the handler's too — all six styles, not four. }
  FBtn.Style := tbsSeparator;
  FBar.OnPaintButton := @HandleMarker;
  img := PaintInto(BtnW, BtnH);
  try
    AssertEquals('the separator paint was the handler', 1, FCalls);
    AssertTrue('and its ink landed', IsMark(img.GetPixel(2, 2)));
  finally
    img.Free;
  end;
end;

procedure TToolBarPaintButtonTest.TestClearingTheHandlerRestoresTheThemedDefault;
var
  before, marked, after: TBGRABitmap;
  x, y: Integer;
  same: Boolean;
begin
  before := PaintInto(BtnW, BtnH);                 // themed default
  FBar.OnPaintButton := @HandleMarker;
  marked := PaintInto(BtnW, BtnH);                 // the handler's ink
  FBar.OnPaintButton := nil;
  after := PaintInto(BtnW, BtnH);                  // themed default again
  try
    AssertTrue('the handler really painted', IsMark(marked.GetPixel(BtnW div 2, BtnH div 2)));
    same := True;
    for y := 0 to BtnH - 1 do
      for x := 0 to BtnW - 1 do
        if before.GetPixel(x, y) <> after.GetPixel(x, y) then same := False;
    AssertTrue('clearing the handler restores the themed default byte for byte', same);
  finally
    before.Free; marked.Free; after.Free;
  end;
end;

procedure TToolBarPaintButtonTest.TestLiveStateReachesTheHandler;
var
  img: TBGRABitmap;
begin
  FBar.OnPaintButton := @HandleSilent;
  FBtn.Style := tbsCheck;
  FBtn.Down := True;
  img := PaintInto(BtnW, BtnH); img.Free;
  AssertEquals('a down check button reports checked', 5, FLastState);
  FBtn.SetLiveState(True, False);
  img := PaintInto(BtnW, BtnH); img.Free;
  AssertEquals('...and checked-hot with the pointer over it', 6, FLastState);
  FBtn.SetLiveState(False, False);
  FBtn.Enabled := False;
  img := PaintInto(BtnW, BtnH); img.Free;
  AssertEquals('disabled wins over checked', 4, FLastState);
end;

procedure TToolBarPaintButtonTest.TestFlatDoesNotDistortTheState;
var
  img: TBGRABitmap;
begin
  { DIVERGENCE, pinned: LCL reports states 1 and 4 as 2 ("hot") when Flat=False — a Win32
    always-raised rendering kludge that tells the handler a disabled button is hot. Here
    AState is the true state whatever Flat says; Flat keeps to the ghost StyleClass. }
  FBar.Flat := False;
  FBar.OnPaintButton := @HandleSilent;
  FBtn.Enabled := False;
  img := PaintInto(BtnW, BtnH); img.Free;
  AssertEquals('a disabled button on a non-flat bar still reports 4', 4, FLastState);
end;

procedure TToolBarPaintButtonTest.TestTheDesignerFiresItToo;
var
  img: TBGRABitmap;
begin
  { LCL has no csDesigning gate in this path, and neither may we: the handler is how a
    designed bar previews its owner-drawn look. }
  FBtn.SetDesigning(True);
  FBar.OnPaintButton := @HandleMarker;
  img := PaintInto(BtnW, BtnH);
  try
    AssertEquals('fired under csDesigning', 1, FCalls);
    AssertTrue('and its ink landed', IsMark(img.GetPixel(2, 2)));
  finally
    img.Free;
  end;
end;

{ ---- the safety rails ------------------------------------------------------- }

procedure TToolBarPaintButtonTest.TestHandlerIsClippedToItsButton;
var
  img: TBGRABitmap;
begin
  { The button sits at (0,0,BtnW,BtnH) of a much larger shared surface — the parent-DC
    situation. Everything the handler strokes beyond its client rect must be clipped away,
    or one owner-drawn button could paint over its neighbours. }
  FBar.OnPaintButton := @HandleOverflowing;
  img := PaintInto(BtnW * 2, BtnH * 2);
  try
    AssertTrue('inside its own rect the ink lands', IsMark(img.GetPixel(BtnW div 2, BtnH div 2)));
    AssertTrue('nothing to the right of the button', IsUnder(img.GetPixel(BtnW + 4, BtnH div 2)));
    AssertTrue('nothing below the button', IsUnder(img.GetPixel(BtnW div 2, BtnH + 4)));
    AssertTrue('nothing past the far corner', IsUnder(img.GetPixel(BtnW + 4, BtnH + 4)));
  finally
    img.Free;
  end;
end;

procedure TToolBarPaintButtonTest.TestSecondCallbackOnOneBindingStillInksItsOwnColour;
var
  bmp: TBitmap;
  img: TBGRABitmap;

  procedure AssertGreenAt(const AWhere: string; x, y: Integer);
  var
    P: TBGRAPixel;
  begin
    P := img.GetPixel(x, y);
    AssertTrue(Format('%s at (%d,%d) drew with the DC''s ink, not the handler''s ' +
      '(got R%d G%d B%d, seeded red)', [AWhere, x, y, P.red, P.green, P.blue]),
      (P.green > 160) and (P.red < 96) and (P.blue < 96));
  end;

begin
  { TWO paints against ONE canvas binding — TCustomControl.PaintWindow shares the binding
    when the DC has not changed, so this is the real sequence, not a synthetic one. The
    handler asks for the SAME green on every call; the DC is seeded RED first, so a callback
    that skips the re-select (the SaveDC/RestoreDC defect) strokes red on the second paint
    and its GetTextColor read-back sees red. }
  FBar.OnPaintButton := @HandleCorners;
  bmp := NewTarget(BtnW, BtnH);
  try
    FBtn.Canvas.Handle := bmp.Canvas.Handle;   // pre-bind: both paints share this binding
    try
      // Seed the canvas's PEN and INK red and drive both into the DC, off-surface, so
      // "whatever the DC is holding" is a colour the handler never asks for.
      FBtn.Canvas.Pen.Color := SeedRed;
      FBtn.Canvas.Font.Color := SeedRed;
      FBtn.Canvas.MoveTo(-8, -8);
      FBtn.Canvas.LineTo(-4, -8);
      FBtn.Canvas.TextOut(-40, -40, 'x');
      FBtn.DrivePaint(bmp.Canvas.Handle);
      FBtn.DrivePaint(bmp.Canvas.Handle);
    finally
      FBtn.Canvas.Handle := 0;
    end;
    AssertEquals('two paints, two callbacks', 2, FCalls);
    img := TBGRABitmap.Create(bmp);
    try
      { The second paint stroked the SAME corners; a stale-DC stroke leaves them red. }
      AssertGreenAt('top-left', 0, 0);
      AssertGreenAt('top-right', BtnW - 1, 0);
      AssertGreenAt('bottom-left', 0, BtnH - 1);
      AssertGreenAt('bottom-right', BtnW - 1, BtnH - 1);
      AssertEquals('every callback inked with the colour it asked for', 0, FStaleInk);
    finally
      img.Free;
    end;
  finally
    bmp.Free;
  end;
end;

initialization
  RegisterTest(TToolBarPaintButtonTest);
end.
