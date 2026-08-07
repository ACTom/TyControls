unit test.formgradientbg;

{$mode objfpc}{$H+}

{ The aero black-corner defect (2026-08-06, measured on a real machine; fixed 2026-08-07).

  aero is the one built-in theme whose `TyForm` background is a LINEAR GRADIENT while its
  controls carry a drop shadow. A gradient form builds no photo backdrop (that path is
  tfkImage only), so a windowed child reconstructs its parent background through
  TyResolveParentBgFill — and the form branch of that function could only hand back a
  SOLID themed colour (ITyThemedBackground.ThemedBgColor). For a gradient it said no, the
  code fell back to the form's raw LCL Color, and ApplyChromeTheme never themes Color for
  a non-solid background either — so the fallback read clDefault, and
  ColorToRGB(clDefault) = $20000000 and $FFFFFF = pure black. Both the child's base fill
  (TyFillParentBg) and its corner-gap patch (FillCornerGaps) then painted OPAQUE BLACK:
  hard #000000 notches on every corner of every windowed control, on every repaint.

  NOTE the recorded suspicion in plans/2026-08-04-parity-remaining-programs.md — that
  TTyPainter.FillCornerGaps drops the alpha of the #00000014 shadow colour — was WRONG:
  the painter composites alpha correctly (pinned by TestFillCornerGapsPreservesAlpha in
  test.painter.pas); the colour it was HANDED was already opaque black.

  These guards probe CORNER pixels, never centres: a centre probe is covered by the
  control's own opaque background and is immune to every drift that has shipped here.

  The oracle is the painter itself: the form's resolved TyForm fill rendered over the
  form's client rect, sampled at the child's CENTRE point (TyResolveParentBg's contract is
  the one colour at the child's centre — the minimax point). The reconstruction contract
  is "the gradient as laid over the FORM'S CLIENT RECT": a surface/title-bar layout paints
  the same sweep over a rect shortened by the bar, so a vertical ramp's sample can sit a
  bar-height early — bounded by tbH/formH of the sweep (~1 RGB step on aero), accepted. }

interface

uses
  Classes, SysUtils, Types, Graphics, Controls, Forms,
  BGRABitmap, BGRABitmapTypes,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Base, tyControls.Painter, tyControls.Controller,
  tyControls.Form, tyControls.FormSurface, tyControls.Button;

type
  { RenderTo is protected; the corner probes need the child shot into a bitmap. }
  TCornerBtnAccess = class(TTyButton)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TFormGradientBgTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TTyForm;
    { Render the form's own resolved TyForm fill over the form client rect — the ground
      truth a child's reconstruction must match — and sample it at (AX, AY). }
    function OracleAt(AX, AY: Integer): TBGRAPixel;
    procedure MakeFixture(const ACss: string);
  protected
    procedure TearDown; override;
  published
    procedure TestGradientFormBgResolvesForAChildNotTheRawLclColor;
    procedure TestWindowedChildCornerPixelsCarryTheFormGradient;
    procedure TestSurfaceHostedChildCornersFollowTheTranslatedChain;
    procedure TestAlphaGradientFormBgStillResolvesOpaque;
    procedure TestRawFormClDefaultResolvesToTheDefaultBrushNotBlack;
  end;

implementation

const
  { High-contrast vertical sweep (90deg IS the vertical axis for this painter: the angle
    is a plain math angle, dx=cos / dy=sin — see TTyPainter.GradientEndpoints and the
    axis guards in test.base.drawframe). Red at the top, blue at the bottom: any confusion
    with black (the defect), with a flat representative colour, or with a mis-translated
    sample row moves a channel by dozens of steps. }
  cFormCss = 'TyForm { background: linear-gradient(90deg, #FF0000, #0000FF); }';
  { The child mirrors aero's defect ingredients: rounded corners + an alpha drop shadow
    (aero: shadow 0 1 2 #00000014). border-width 0 keeps corner pixels pure. }
  cBtnCss = 'TyButton { background: #FFFFFF; border-radius: 8; border-width: 0; ' +
    'shadow: 0 1 2 #00000014; }';
  cFormW = 480;
  cFormH = 400;
  cTol = 4;   // same pixel tolerance as the drawframe gradient guards (scanner dithering)

procedure TCornerBtnAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TFormGradientBgTest.MakeFixture(const ACss: string);
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(ACss);
  FForm := TTyForm.CreateNew(nil);
  FForm.SetBounds(0, 0, cFormW, cFormH);
  { ApplyChromeTheme runs here. For a gradient TyForm bg it does NOT set the LCL Color —
    which is the point: the resolver must not need it. }
  FForm.Controller := FCtl;
end;

procedure TFormGradientBgTest.TearDown;
begin
  { The form references the controller (FreeNotification), so the form goes first. }
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
end;

function TFormGradientBgTest.OracleAt(AX, AY: Integer): TBGRAPixel;
var
  st: TTyStyleSet;
  p: TTyPainter;
  host: TBitmap;
  shot: TBGRABitmap;
begin
  st := FCtl.Model.ResolveStyle('TyForm', '', []);
  AssertTrue('oracle precondition: the fixture form HAS a background', tpBackground in st.Present);
  host := TBitmap.Create;
  try
    host.PixelFormat := pf32bit;
    host.SetSize(cFormW, cFormH);
    p := TTyPainter.Create;
    try
      p.BeginPaint(host.Canvas, Rect(0, 0, cFormW, cFormH), 96);
      p.FillBackground(Rect(0, 0, cFormW, cFormH), st.Background, 0);
      p.EndPaint;
    finally
      p.Free;
    end;
    shot := TBGRABitmap.Create(host);
    try
      Result := shot.GetPixel(AX, AY);
    finally
      shot.Free;
    end;
  finally
    host.Free;
  end;
end;

procedure TFormGradientBgTest.TestGradientFormBgResolvesForAChildNotTheRawLclColor;
{ The resolver link on its own: a child of a gradient-background TTyForm must resolve an
  OPAQUE colour from the form's THEMED gradient — not the raw LCL form.Color, which
  ApplyChromeTheme leaves untouched for a non-solid background (clDefault -> #000000). }
var
  btn: TTyButton;
  c: TTyColor;
  want: TBGRAPixel;
  cx, cy: Integer;
begin
  MakeFixture(cFormCss + cBtnCss);
  btn := TTyButton.Create(FForm);
  btn.Parent := FForm;
  btn.Controller := FCtl;
  btn.SetBounds(40, 60, 120, 30);
  c := 0;
  AssertTrue('resolved a parent bg at all', TyResolveParentBg(btn, c));
  AssertEquals('the promise is an OPAQUE backdrop', 255, TyAlphaOf(c));
  { The defect colour. Red stays high on the fixture's whole upper half, so black is
    unambiguously the un-themed LCL fallback, not any point of the ramp. }
  AssertFalse('NOT the raw un-themed LCL Color (ColorToRGB(clDefault) = black)',
    (TyRedOf(c) = 0) and (TyGreenOf(c) = 0) and (TyBlueOf(c) = 0));
  { And positively: the value at the child's CENTRE of the form's own rendition. Bounds
    are read back from the control, never assumed (the LCL size queue may restate them). }
  cx := btn.Left + btn.ClientWidth div 2;
  cy := btn.Top + btn.ClientHeight div 2;
  want := OracleAt(cx, cy);
  AssertTrue(Format('resolved colour tracks the form gradient at the child''s centre ' +
    '(want #%.2x%.2x%.2x, got #%.2x%.2x%.2x)',
    [want.red, want.green, want.blue, TyRedOf(c), TyGreenOf(c), TyBlueOf(c)]),
    (Abs(TyRedOf(c) - want.red) <= cTol) and
    (Abs(TyGreenOf(c) - want.green) <= cTol) and
    (Abs(TyBlueOf(c) - want.blue) <= cTol));
end;

procedure TFormGradientBgTest.TestWindowedChildCornerPixelsCarryTheFormGradient;
{ The painted truth, at the four CORNER pixels — where the aero notches actually were.
  With border-radius 8 the (0,0)/(w-1,0)/(0,h-1)/(w-1,h-1) pixels sit fully outside the
  rounded interior: whatever is there came from the parent-bg base fill + the corner-gap
  patch, i.e. from the resolution chain under test. Each must match the form's own
  rendition at the child's centre (the corner patch is that one flat colour by contract). }
var
  btn: TCornerBtnAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  want: TBGRAPixel;
  cx, cy, w, h: Integer;

  procedure CheckCorner(AX, AY: Integer; const AName: string);
  var
    px: TBGRAPixel;
  begin
    px := shot.GetPixel(AX, AY);
    AssertFalse(Format('corner %s must not be the aero defect black (got #%.2x%.2x%.2x)',
      [AName, px.red, px.green, px.blue]),
      (px.red = 0) and (px.green = 0) and (px.blue = 0));
    AssertTrue(Format('corner %s carries the form gradient at the child''s centre ' +
      '(want #%.2x%.2x%.2x, got #%.2x%.2x%.2x)',
      [AName, want.red, want.green, want.blue, px.red, px.green, px.blue]),
      (Abs(px.red - want.red) <= cTol) and
      (Abs(px.green - want.green) <= cTol) and
      (Abs(px.blue - want.blue) <= cTol));
  end;

begin
  MakeFixture(cFormCss + cBtnCss);
  btn := TCornerBtnAccess.Create(FForm);
  btn.Parent := FForm;
  btn.Controller := FCtl;
  btn.SetBounds(40, 60, 120, 30);
  w := btn.ClientWidth;
  h := btn.ClientHeight;
  cx := btn.Left + w div 2;
  cy := btn.Top + h div 2;
  want := OracleAt(cx, cy);
  host := TBitmap.Create;
  try
    host.PixelFormat := pf32bit;
    host.SetSize(w, h);
    btn.RenderTo(host.Canvas, Rect(0, 0, w, h), 96);
    shot := TBGRABitmap.Create(host);
    try
      CheckCorner(0, 0, '(0,0)');
      CheckCorner(w - 1, 0, '(w-1,0)');
      CheckCorner(0, h - 1, '(0,h-1)');
      CheckCorner(w - 1, h - 1, '(w-1,h-1)');
    finally
      shot.Free;
    end;
  finally
    host.Free;
  end;
end;

procedure TFormGradientBgTest.TestSurfaceHostedChildCornersFollowTheTranslatedChain;
{ The real topology: TTyForm -> TTyFormSurface -> control. The surface resolves NO
  background of its own, so the chain recurses through it — and must carry the child's
  rect TRANSLATED by the surface's offset. The surface here is deliberately pushed down
  as a title bar would (top=48): a reconstruction that loses the offset samples the ramp
  48 rows (12% of the sweep, ~30 RGB steps on the red channel) away and goes red. }
var
  surf: TTyFormSurface;
  btn: TCornerBtnAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  want, px: TBGRAPixel;
  cx, cy, w, h: Integer;
begin
  MakeFixture(cFormCss + cBtnCss);
  surf := TTyFormSurface.Create(FForm);
  surf.Parent := FForm;
  surf.Controller := FCtl;
  surf.SetBounds(0, 48, cFormW, cFormH - 48);
  btn := TCornerBtnAccess.Create(FForm);
  btn.Parent := surf;
  btn.Controller := FCtl;
  btn.SetBounds(40, 60, 120, 30);
  w := btn.ClientWidth;
  h := btn.ClientHeight;
  { The child's centre in FORM space: surface offset + child offset + half the child. }
  cx := surf.Left + btn.Left + w div 2;
  cy := surf.Top + btn.Top + h div 2;
  want := OracleAt(cx, cy);
  host := TBitmap.Create;
  try
    host.PixelFormat := pf32bit;
    host.SetSize(w, h);
    btn.RenderTo(host.Canvas, Rect(0, 0, w, h), 96);
    shot := TBGRABitmap.Create(host);
    try
      px := shot.GetPixel(0, 0);
      AssertFalse(Format('surface-hosted corner must not be black (got #%.2x%.2x%.2x)',
        [px.red, px.green, px.blue]),
        (px.red = 0) and (px.green = 0) and (px.blue = 0));
      AssertTrue(Format('surface-hosted corner samples the ramp at the TRANSLATED centre ' +
        '(want #%.2x%.2x%.2x, got #%.2x%.2x%.2x)',
        [want.red, want.green, want.blue, px.red, px.green, px.blue]),
        (Abs(px.red - want.red) <= cTol) and
        (Abs(px.green - want.green) <= cTol) and
        (Abs(px.blue - want.blue) <= cTol));
    finally
      shot.Free;
    end;
  finally
    host.Free;
  end;
end;

procedure TFormGradientBgTest.TestAlphaGradientFormBgStillResolvesOpaque;
{ TyResolveParentBg PROMISES an opaque colour (see the composited-opaque guard in
  test.base.drawframe: a non-opaque answer makes children's bitmaps non-opaque, which
  smears on widgetsets that never clear a damaged region). A gradient form background
  carrying alpha stops must therefore come back FLATTENED, not raw. }
var
  btn: TTyButton;
  c: TTyColor;
begin
  MakeFixture(
    'TyForm { background: linear-gradient(90deg, #00000080, #FFFFFF80); }' + cBtnCss);
  btn := TTyButton.Create(FForm);
  btn.Parent := FForm;
  btn.Controller := FCtl;
  btn.SetBounds(40, 60, 120, 30);
  c := 0;
  AssertTrue('resolved a parent bg at all', TyResolveParentBg(btn, c));
  AssertEquals('an alpha-stop form gradient is flattened to an OPAQUE answer',
    255, TyAlphaOf(c));
end;

procedure TFormGradientBgTest.TestRawFormClDefaultResolvesToTheDefaultBrushNotBlack;
{ The residual LCL-colour fallback (a RAW TForm parent, no theming anywhere). Such a
  form's Color is clDefault, and bare ColorToRGB(clDefault) masks $20000000 to black —
  the same defect class as the aero notches, just on plain-LCL hosts: every TTy control
  on an untouched TForm base-filled and corner-patched BLACK, and two pixel tests
  (group-box caption band, splitter grip) were green only on top of that black. The
  fallback must resolve clDefault the way the LCL itself would paint it
  (GetColorResolvingParent -> GetDefaultColor(dctBrush) -> a light system brush). }
var
  rawForm: TForm;
  btn: TTyButton;
  c: TTyColor;
begin
  rawForm := TForm.CreateNew(nil);
  try
    { Color deliberately NOT set: stays clDefault, the shipping default. }
    btn := TTyButton.Create(rawForm);
    btn.Parent := rawForm;
    btn.SetBounds(10, 10, 80, 24);
    c := 0;
    AssertTrue('resolved a parent bg at all', TyResolveParentBg(btn, c));
    AssertEquals('opaque, as always', 255, TyAlphaOf(c));
    AssertFalse('clDefault must not read as black',
      (TyRedOf(c) = 0) and (TyGreenOf(c) = 0) and (TyBlueOf(c) = 0));
    AssertTrue(Format('clDefault resolves to the light default form brush ' +
      '(got #%.2x%.2x%.2x)', [TyRedOf(c), TyGreenOf(c), TyBlueOf(c)]),
      (TyRedOf(c) > 100) and (TyGreenOf(c) > 100) and (TyBlueOf(c) > 100));
  finally
    rawForm.Free;
  end;
end;

initialization
  RegisterTest(TFormGradientBgTest);
end.
