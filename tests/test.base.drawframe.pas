unit test.base.drawframe;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Controls, Forms, BGRABitmap, BGRABitmapTypes,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Base, tyControls.Painter,
  tyControls.Form, tyControls.Button, tyControls.GlyphButtons, tyControls.Panel,
  tyControls.Controller;
type
  TDrawFrameProbe = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
  public
    procedure RunDrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
  end;

  { RenderTo is protected on both, and these guards need to shoot a parent and a child
    into separate bitmaps and compare them pixel for pixel. }
  TGradPanelAccess = class(TTyPanel)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TGradChildAccess = class(TTySpeedButton)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TDrawFrameTest = class(TTestCase)
  published
    procedure TestSolidBackgroundCenterPixel;
    procedure TestOpacityDimsControl;
    procedure TestApplyStyleOpacityDimsSelfDrawn;
    procedure TestBorderStyleNoneSuppressesBorder;
    procedure TestPerCornerBackgroundViaDrawFrame;
    procedure TestFocusRingDrawnWhenOutlinePresent;
    procedure TestFormChildResolvesThemedParentBg;
    procedure TestPartlyTransparentParentBgIsCompositedOpaque;
    procedure TestGradientParentBackdropFollowsChildDownTheAxis;
    procedure TestGradientParentBackdropFollowsChildAcrossTheAxis;
    procedure TestGradientParentBackdropCarriesAMultiStopParent;
    procedure TestGradientParentBgResolvesAtTheChildsCentre;
  end;
implementation

function TDrawFrameProbe.GetStyleTypeKey: string;
begin
  Result := 'TyPanel';
end;

procedure TGradPanelAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin inherited RenderTo(ACanvas, ARect, APPI); end;

procedure TGradChildAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin inherited RenderTo(ACanvas, ARect, APPI); end;

procedure TDrawFrameProbe.RunDrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
begin
  DrawFrame(APainter, ARect, AStyle);
end;

procedure TDrawFrameTest.TestSolidBackgroundCenterPixel;
var
  probe: TDrawFrameProbe;
  painter: TTyPainter;
  bmp: TBitmap;
  style: TTyStyleSet;
  r: TRect;
  px: TBGRAPixel;
  reread: TBGRABitmap;
begin
  bmp := TBitmap.Create;
  probe := TDrawFrameProbe.Create(nil);
  painter := TTyPainter.Create;
  try
    bmp.SetSize(40, 40);
    r := Rect(0, 0, 40, 40);
    style := EmptyStyleSet;
    style.Background.Kind := tfkSolid;
    style.Background.Color := TyRGB($20, $C0, $40);
    Include(style.Present, tpBackground);

    painter.BeginPaint(bmp.Canvas, r, 96);
    probe.RunDrawFrame(painter, r, style);
    painter.EndPaint;

    reread := TBGRABitmap.Create(bmp);
    try
      px := reread.GetPixel(20, 20);
      AssertEquals('red channel', $20, px.red);
      AssertEquals('green channel', $C0, px.green);
      AssertEquals('blue channel', $40, px.blue);
    finally
      reread.Free;
    end;
  finally
    painter.Free;
    probe.Free;
    bmp.Free;
  end;
end;

procedure TDrawFrameTest.TestOpacityDimsControl;
{ Fix 3 regression: a style with Opacity=0.5 over an opaque white backdrop
  should produce a blended pixel — neither fully white nor fully the fill
  colour. We paint white first (backdrop), then apply a 50%-opacity red fill
  via DrawFrame + EndPaint.  The resulting pixel should have a red channel
  that is neither 0 (pure white) nor 255 (pure red) — i.e. it is blended. }
var
  probe: TDrawFrameProbe;
  painter: TTyPainter;
  bmp: TBitmap;
  style: TTyStyleSet;
  r: TRect;
  px: TBGRAPixel;
  reread: TBGRABitmap;
begin
  bmp := TBitmap.Create;
  probe := TDrawFrameProbe.Create(nil);
  painter := TTyPainter.Create;
  try
    bmp.SetSize(40, 40);
    r := Rect(0, 0, 40, 40);

    { Draw opaque white backdrop directly onto the bitmap canvas }
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(r);

    { Build a style: solid red fill, opacity 0.5 }
    style := EmptyStyleSet;
    style.Background.Kind := tfkSolid;
    style.Background.Color := TyRGBA($FF, $00, $00, $FF); { opaque red }
    Include(style.Present, tpBackground);
    style.Opacity := 0.5;
    Include(style.Present, tpOpacity);

    { Render via DrawFrame + EndPaint: EndPaint applies opacity then blits }
    painter.BeginPaint(bmp.Canvas, r, 96);
    probe.RunDrawFrame(painter, r, style);
    painter.EndPaint;

    reread := TBGRABitmap.Create(bmp);
    try
      px := reread.GetPixel(20, 20);
      { The fill is pure red (R=255, G=0, B=0). At 50% opacity composited
        over white (R=255, G=255, B=255):
          G_result = 0.5*0 + 0.5*255 = ~128, B_result similarly ~128.
        If opacity were NOT applied (fully opaque red over white), G would be 0.
        So G > 50 proves dimming happened. }
      AssertTrue('opacity dims: green channel > 50 (white bleeds through)', px.green > 50);
      AssertTrue('opacity dims: blue channel > 50 (white bleeds through)', px.blue > 50);
    finally
      reread.Free;
    end;
  finally
    painter.Free;
    probe.Free;
    bmp.Free;
  end;
end;

procedure TDrawFrameTest.TestApplyStyleOpacityDimsSelfDrawn;
{ #12: the self-drawing instruments (Dial / Meter / Rating / clocks / colour pickers) have
  no DrawFrame, so :disabled { opacity } was dead on them. They now call the shared seam
  TyApplyStyleOpacity directly. Prove that path dims WITHOUT DrawFrame: push a 50% opacity
  through the helper, then hand-paint a red fill the way an instrument paints its face, and
  check EndPaint blended it toward the white backdrop. Drop the helper call and the fill
  stays fully opaque (green channel 0) — the exact regression this guards. }
var
  probe: TDrawFrameProbe;
  painter: TTyPainter;
  bmp: TBitmap;
  style: TTyStyleSet;
  r: TRect;
  px: TBGRAPixel;
  reread: TBGRABitmap;
  f: TTyFill;
begin
  bmp := TBitmap.Create;
  probe := TDrawFrameProbe.Create(nil);
  painter := TTyPainter.Create;
  try
    bmp.SetSize(40, 40);
    r := Rect(0, 0, 40, 40);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(r);

    style := EmptyStyleSet;
    style.Opacity := 0.5;
    Include(style.Present, tpOpacity);

    painter.BeginPaint(bmp.Canvas, r, 96);
    TyApplyStyleOpacity(probe, painter, style);   // the instrument seam, NOT DrawFrame
    f := Default(TTyFill);
    f.Kind := tfkSolid;
    f.Color := TyRGBA($FF, $00, $00, $FF);         // opaque red, self-drawn
    painter.FillBackground(r, f, 0);
    painter.EndPaint;

    reread := TBGRABitmap.Create(bmp);
    try
      px := reread.GetPixel(20, 20);
      AssertTrue('helper dims a self-drawn fill: green > 50 (white bleeds through)', px.green > 50);
      AssertTrue('helper dims a self-drawn fill: blue > 50 (white bleeds through)', px.blue > 50);
    finally
      reread.Free;
    end;
  finally
    painter.Free;
    probe.Free;
    bmp.Free;
  end;
end;

procedure TDrawFrameTest.TestBorderStyleNoneSuppressesBorder;
{ border-style: none must suppress the border even when border-width>0.
  We render a 4px red border into a white-backed 40x40 bitmap and probe a
  pixel that sits ON the border line (2,20). With BorderStyle=tbsNone and
  tpBorderStyle present, the border is suppressed -> the white backdrop
  bleeds through, so the probe's GREEN channel stays high (> 128).
  The contrast case omits tpBorderStyle -> the red border is drawn over the
  probe, so its green channel drops low (< 128) while red stays high.
  Discriminating on green (not red) is required because pure white also has
  red=255; the red border (R=255,G=0,B=0) is distinguished from white
  (R=255,G=255,B=255) only by its green/blue channels. This proves the
  suppression is conditional on tpBorderStyle being present with tbsNone. }
var
  probe: TDrawFrameProbe;
  painter: TTyPainter;
  bmp: TBitmap;
  style: TTyStyleSet;
  r: TRect;
  px: TBGRAPixel;
  reread: TBGRABitmap;
begin
  // --- suppression case: border-style: none ---
  bmp := TBitmap.Create;
  probe := TDrawFrameProbe.Create(nil);
  painter := TTyPainter.Create;
  try
    bmp.SetSize(40, 40);
    r := Rect(0, 0, 40, 40);

    { white backdrop so a missing border leaves white }
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(r);

    style := EmptyStyleSet;
    style.BorderColor := TyRGB($FF, $00, $00);
    style.BorderWidth := 4;
    style.BorderStyle := tbsNone;
    style.Present := [tpBorderColor, tpBorderWidth, tpBorderStyle];

    painter.BeginPaint(bmp.Canvas, r, 96);
    probe.RunDrawFrame(painter, r, style);
    painter.EndPaint;

    reread := TBGRABitmap.Create(bmp);
    try
      px := reread.GetPixel(2, 20);
      AssertTrue('border suppressed: white bleeds through (green > 128)', px.green > 128);
    finally
      reread.Free;
    end;
  finally
    painter.Free;
    probe.Free;
    bmp.Free;
  end;

  // --- contrast case: no border-style -> border IS drawn ---
  bmp := TBitmap.Create;
  probe := TDrawFrameProbe.Create(nil);
  painter := TTyPainter.Create;
  try
    bmp.SetSize(40, 40);
    r := Rect(0, 0, 40, 40);

    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(r);

    style := EmptyStyleSet;
    style.BorderColor := TyRGB($FF, $00, $00);
    style.BorderWidth := 4;
    style.Present := [tpBorderColor, tpBorderWidth]; { no tpBorderStyle }

    painter.BeginPaint(bmp.Canvas, r, 96);
    probe.RunDrawFrame(painter, r, style);
    painter.EndPaint;

    reread := TBGRABitmap.Create(bmp);
    try
      px := reread.GetPixel(2, 20);
      AssertTrue('border drawn: probe is red (red > 128)', px.red > 128);
      AssertTrue('border drawn: probe is red (green < 128)', px.green < 128);
    finally
      reread.Free;
    end;
  finally
    painter.Free;
    probe.Free;
    bmp.Free;
  end;
end;

procedure TDrawFrameTest.TestPerCornerBackgroundViaDrawFrame;
{ Radius TL=6, TR=6, BR=0, BL=0 on a 40x40 bitmap with white backdrop.
  Probe (0,0): outside the TL arc (distance ~8.5 from arc center at (6,6)) -> white.
  Probe (1,38): outside the hypothetical BL r=6 arc (center (6,33), distance ~7.07 > 6).
    If BL were wrongly rounded, (1,38) would be outside the arc -> white backdrop (red=255).
    Since BL=0 (square), (1,38) is inside the filled rect -> green (red=$20 < 128).
    This point truly discriminates square vs rounded; 1px inside both straight edges avoids AA. }
var
  probe: TDrawFrameProbe; painter: TTyPainter; bmp: TBitmap;
  style: TTyStyleSet; r: TRect; pxTL, pxBL: TBGRAPixel; reread: TBGRABitmap;
begin
  bmp := TBitmap.Create; probe := TDrawFrameProbe.Create(nil); painter := TTyPainter.Create;
  try
    bmp.SetSize(40, 40);
    r := Rect(0, 0, 40, 40);
    bmp.Canvas.Brush.Color := clWhite; bmp.Canvas.FillRect(r);
    style := EmptyStyleSet;
    style.Background.Kind := tfkSolid;
    style.Background.Color := TyRGB($20, $C0, $40);   // green, red=$20
    Include(style.Present, tpBackground);
    style.Radius := TyCorners(6, 6, 0, 0);
    Include(style.Present, tpBorderRadius);
    painter.BeginPaint(bmp.Canvas, r, 96);
    probe.RunDrawFrame(painter, r, style);
    painter.EndPaint;
    reread := TBGRABitmap.Create(bmp);
    try
      pxTL := reread.GetPixel(0, 0);    // top-left rounded -> white backdrop
      pxBL := reread.GetPixel(1, 38);   // bottom-left: (1,38) is outside r=6 arc centered at (6,33), green only when corner is truly square
      AssertTrue('DrawFrame top-left rounded (white): red>200', pxTL.red > 200);
      AssertTrue('DrawFrame bottom-left square (green): red<128', pxBL.red < 128);
      AssertTrue('DrawFrame bottom-left square (green): green>128', pxBL.green > 128);
    finally reread.Free; end;
  finally painter.Free; probe.Free; bmp.Free; end;
end;

procedure TDrawFrameTest.TestFocusRingDrawnWhenOutlinePresent;
{ Outline present -> StrokeBorder draws a red ring.
  With OutlineOffset=0 and OutlineWidth=2, StrokeBorder is called with ARect=(0,0,40,40).
  StrokeBorder centers a width-2 stroke: left edge center at x=1.
  Probe (1,20) = center of left stroke -> red ring (green<128).
  Absent case: white backdrop at same point -> green>128. }
var
  probe: TDrawFrameProbe; painter: TTyPainter; bmp: TBitmap;
  style: TTyStyleSet; r: TRect; px: TBGRAPixel; reread: TBGRABitmap;
begin
  // ring present
  bmp := TBitmap.Create; probe := TDrawFrameProbe.Create(nil); painter := TTyPainter.Create;
  try
    bmp.SetSize(40, 40); r := Rect(0, 0, 40, 40);
    bmp.Canvas.Brush.Color := clWhite; bmp.Canvas.FillRect(r);
    style := EmptyStyleSet;
    style.OutlineColor := TyRGB($FF, $00, $00);
    style.OutlineWidth := 2;
    style.OutlineOffset := 0;
    Include(style.Present, tpOutline);
    painter.BeginPaint(bmp.Canvas, r, 96);
    probe.RunDrawFrame(painter, r, style);
    painter.EndPaint;
    reread := TBGRABitmap.Create(bmp);
    try
      px := reread.GetPixel(1, 20);
      AssertTrue('focus ring drawn: green<128 (red ring)', px.green < 128);
    finally reread.Free; end;
  finally painter.Free; probe.Free; bmp.Free; end;

  // ring absent
  bmp := TBitmap.Create; probe := TDrawFrameProbe.Create(nil); painter := TTyPainter.Create;
  try
    bmp.SetSize(40, 40); r := Rect(0, 0, 40, 40);
    bmp.Canvas.Brush.Color := clWhite; bmp.Canvas.FillRect(r);
    style := EmptyStyleSet;   // no tpOutline
    painter.BeginPaint(bmp.Canvas, r, 96);
    probe.RunDrawFrame(painter, r, style);
    painter.EndPaint;
    reread := TBGRABitmap.Create(bmp);
    try
      px := reread.GetPixel(1, 20);
      AssertTrue('no ring: green>128 (white)', px.green > 128);
    finally reread.Free; end;
  finally painter.Free; probe.Free; bmp.Free; end;
end;

procedure TDrawFrameTest.TestFormChildResolvesThemedParentBg;
{ A control parented to a TTyForm must resolve its parent background from the form's
  THEMED TyForm bg (works at design time too, via the built-in default theme), NOT from
  the raw LCL form.Color (which is only themed by ApplyChromeTheme at runtime). Without
  this, designer/un-themed forms paint dark corner-gaps behind every child. }
var
  form: TTyForm;
  btn: TTyButton;
  c: TTyColor;
  ok: Boolean;
begin
  form := TTyForm.CreateNew(nil);
  try
    form.Color := clRed;          // a distinct raw Color, different from any themed bg
    btn := TTyButton.Create(form);
    btn.Parent := form;
    c := 0;
    ok := TyResolveParentBg(btn, c);
    AssertTrue('resolved a parent bg', ok);
    // Built-in default TyForm bg is a light grey (form-bg=surface-hover); its green is high.
    // The raw clRed would give green=0, so this discriminates themed vs raw form.Color.
    AssertTrue('themed light parent bg (green high), not raw clRed', TyGreenOf(c) > 200);
    AssertTrue('not the raw red form.Color', TyRedOf(c) < 250);
  finally
    form.Free;
  end;
end;

procedure TDrawFrameTest.TestPartlyTransparentParentBgIsCompositedOpaque;
{ TyResolveParentBg promises the OPAQUE background behind a child. A container whose own
  background is PARTLY transparent shows the backdrop through itself, so the honest answer is
  that container composited over what is behind it -- not its raw half-transparent value.

  Why it matters beyond tidiness: a child that fills with a non-opaque "background" produces a
  non-opaque bitmap, and on a widgetset that never clears a damaged region (GTK3 clears
  nothing at all) every repaint then composites onto the previous one instead of replacing it.
  That is the smearing seen on exactly the controls that DO fill their parent background.

  Fixture: a panel at 50% black over a white form. The composite must be mid-grey and fully
  opaque -- not black (alpha thrown away) and not half-transparent (raw value). }
var
  form: TTyForm;
  panel: TTyPanel;
  btn: TTyButton;
  c: TTyColor;
begin
  form := TTyForm.CreateNew(nil);
  try
    { The user layer is SHARED, so it must be put back -- a TyPanel rule left behind here
      re-coloured the panel suite's fixture and broke an unrelated assertion. }
    TyDefaultController.LoadThemeCss(
      'TyForm { background: #FFFFFF; }' +
      'TyPanel { background: rgba(0, 0, 0, 0.5); }');
    panel := TTyPanel.Create(form);
    panel.Parent := form;
    btn := TTyButton.Create(panel);
    btn.Parent := panel;
    c := 0;
    AssertTrue('resolved a parent bg', TyResolveParentBg(btn, c));
    AssertEquals('fully opaque', 255, TyAlphaOf(c));
    AssertTrue(Format('composited toward mid-grey, not black (got %d)', [TyRedOf(c)]),
      (TyRedOf(c) > 100) and (TyRedOf(c) < 155));
  finally
    form.Free;
    TyDefaultController.LoadThemeCss('');   // drop the user layer; back to the base theme
  end;
end;

{ ---------------------------------------------------------------------------
  A windowed child cannot see through to what its parent painted, so it rebuilds the
  parent's backdrop itself (TyFillParentBg). These three pin that the rebuild follows a
  GRADIENT parent instead of collapsing it to one representative colour -- which drew a
  flat rectangular patch, a hole punched in the panel's sweep whose error at the far end
  was the entire parent spread.

  90deg is the VERTICAL axis for this painter and 0deg the horizontal one: the angle is a
  plain math angle in screen space, dx = cos / dy = sin (TTyPainter.GradientEndpoints,
  tyControls.Painter.pas:571). 180deg would therefore be HORIZONTAL, not vertical, and a
  fixture that assumed the CSS reading would sample a constant and measure nothing.
  --------------------------------------------------------------------------- }

{ A gradient panel and a transparent windowed child on it, each rendered into its own
  bitmap so the two can be compared where they overlap. The child's own background is
  fully transparent and its border zero, so everything in its bitmap IS the reconstruction
  under test. }
procedure GradientFixture(const ACss: string; ABX, ABY, ABW, ABH: Integer;
  out ACtl: TTyStyleController; out AForm: TForm;
  out APanelShot, AChildShot: TBGRABitmap);
const
  cPanelSide = 120;
var
  panel: TGradPanelAccess;
  child: TGradChildAccess;
  pb, cb: TBitmap;
begin
  ACtl := TTyStyleController.Create(nil);
  ACtl.LoadThemeCss(ACss);
  AForm := TForm.CreateNew(nil);
  pb := TBitmap.Create;
  cb := TBitmap.Create;
  try
    panel := TGradPanelAccess.Create(AForm);
    panel.Parent := AForm;
    panel.Controller := ACtl;
    panel.Caption := '';
    panel.SetBounds(0, 0, cPanelSide, cPanelSide);

    child := TGradChildAccess.Create(panel);
    child.Parent := panel;
    child.Controller := ACtl;
    child.Caption := '';
    child.SetBounds(ABX, ABY, ABW, ABH);

    pb.PixelFormat := pf32bit;
    pb.SetSize(cPanelSide, cPanelSide);
    panel.RenderTo(pb.Canvas, Rect(0, 0, cPanelSide, cPanelSide), 96);

    cb.PixelFormat := pf32bit;
    cb.SetSize(ABW, ABH);
    child.RenderTo(cb.Canvas, Rect(0, 0, ABW, ABH), 96);

    APanelShot := TBGRABitmap.Create(pb);
    AChildShot := TBGRABitmap.Create(cb);
  finally
    cb.Free;
    pb.Free;
  end;
end;

function GreenAt(ABmp: TBGRABitmap; AX, AY: Integer): Integer;
begin
  Result := ABmp.GetPixel(AX, AY).green;
end;

procedure TDrawFrameTest.TestGradientParentBackdropFollowsChildDownTheAxis;
{ THE guard the defect was measured with, tightened in the one way that matters: the child
  is deliberately OFF-ORIGIN and SHORTER than its parent. A child that covered the panel
  exactly would still pass with the offset ignored, because its slice would happen to be the
  whole sweep. This one owns rows 60..99 of a 120px ramp, so only a reconstruction that knows
  both WHERE the child sits and HOW FAR it runs can match.

  Spread alone is not enough either -- a reversed axis has the same spread -- so both ends
  are compared against the parent's own pixels by value. }
var
  ctl: TTyStyleController;
  form: TForm;
  ps, cs: TBGRABitmap;
  pTop, pBot, cTop, cBot, parentSpread, childSpread: Integer;
begin
  GradientFixture(
    'TyPanel { background: linear-gradient(90deg, #000000, #FFFFFF); border-width: 0px; ' +
    'padding: 0px; }' +
    'TySpeedButton { background: rgba(0,0,0,0); border-width: 0px; padding: 0px; }',
    0, 60, 120, 40, ctl, form, ps, cs);
  try
    pTop := GreenAt(ps, 60, 60);
    pBot := GreenAt(ps, 60, 99);
    cTop := GreenAt(cs, 60, 0);
    cBot := GreenAt(cs, 60, 39);
    parentSpread := Abs(pBot - pTop);
    childSpread := Abs(cBot - cTop);

    AssertTrue(Format('the parent really varies over the child''s rows (spread=%d)',
      [parentSpread]), parentSpread > 25);
    AssertTrue(Format('top edge matches the parent at y=60 (parent=%d child=%d)',
      [pTop, cTop]), Abs(cTop - pTop) <= 4);
    AssertTrue(Format('bottom edge matches the parent at y=99 (parent=%d child=%d)',
      [pBot, cBot]), Abs(cBot - pBot) <= 4);
    AssertTrue(Format('and it sweeps as far as the parent does (parent=%d child=%d)',
      [parentSpread, childSpread]), Abs(childSpread - parentSpread) <= 4);
  finally
    cs.Free;
    ps.Free;
    form.Free;
    ctl.Free;
  end;
end;

procedure TDrawFrameTest.TestGradientParentBackdropFollowsChildAcrossTheAxis;
{ The same on the OTHER axis, at 0deg. It pins the painter's angle convention from the
  outside: read as CSS, 0deg would be "to top" and this fixture would be constant across
  the child, so a reconstruction that guessed the convention cannot pass both this and the
  90deg guard above. }
var
  ctl: TTyStyleController;
  form: TForm;
  ps, cs: TBGRABitmap;
  pLeft, pRight, cLeft, cRight, parentSpread, childSpread: Integer;
begin
  GradientFixture(
    'TyPanel { background: linear-gradient(0deg, #000000, #FFFFFF); border-width: 0px; ' +
    'padding: 0px; }' +
    'TySpeedButton { background: rgba(0,0,0,0); border-width: 0px; padding: 0px; }',
    60, 0, 40, 120, ctl, form, ps, cs);
  try
    pLeft := GreenAt(ps, 60, 60);
    pRight := GreenAt(ps, 99, 60);
    cLeft := GreenAt(cs, 0, 60);
    cRight := GreenAt(cs, 39, 60);
    parentSpread := Abs(pRight - pLeft);
    childSpread := Abs(cRight - cLeft);

    AssertTrue(Format('0deg really is the horizontal axis (spread=%d)',
      [parentSpread]), parentSpread > 25);
    AssertTrue(Format('left edge matches the parent at x=60 (parent=%d child=%d)',
      [pLeft, cLeft]), Abs(cLeft - pLeft) <= 4);
    AssertTrue(Format('right edge matches the parent at x=99 (parent=%d child=%d)',
      [pRight, cRight]), Abs(cRight - pRight) <= 4);
    AssertTrue(Format('and it sweeps as far as the parent does (parent=%d child=%d)',
      [parentSpread, childSpread]), Abs(childSpread - parentSpread) <= 4);
  finally
    cs.Free;
    ps.Free;
    form.Free;
    ctl.Free;
  end;
end;

procedure TDrawFrameTest.TestGradientParentBackdropCarriesAMultiStopParent;
{ The painter draws >2 stops through a multi-gradient built with gamma correction OFF, and
  2 stops through a scanner whose gamma correction defaults ON. A reconstruction that
  reduces a multi-stop parent to two endpoint colours therefore lands on the other curve,
  and the ends still match while the MIDDLE drifts — a soft bar across the control that a
  two-point check would never see.

  So the child here deliberately spans the parent's SECOND segment only (rows 60..119 of a
  ramp whose interior stop sits at row 60): no parent stop falls strictly inside it, which
  is the case where the count would collapse to two. Row 89, halfway along, is the assertion
  that matters. }
var
  ctl: TTyStyleController;
  form: TForm;
  ps, cs: TBGRABitmap;
  y: Integer;
begin
  GradientFixture(
    'TyPanel { background: linear-gradient(90deg, #000000, #FF0000 50%, #FFFFFF); ' +
    'border-width: 0px; padding: 0px; }' +
    'TySpeedButton { background: rgba(0,0,0,0); border-width: 0px; padding: 0px; }',
    0, 60, 120, 60, ctl, form, ps, cs);
  try
    AssertTrue(Format('the middle stop really bends the ramp (y=60 green=%d, y=119 green=%d)',
      [GreenAt(ps, 60, 60), GreenAt(ps, 60, 119)]),
      (GreenAt(ps, 60, 60) < 40) and (GreenAt(ps, 60, 119) > 200));
    for y := 0 to 59 do
      AssertTrue(Format('row %d matches the parent at y=%d (parent=%d child=%d)',
        [y, y + 60, GreenAt(ps, 60, y + 60), GreenAt(cs, 60, y)]),
        Abs(GreenAt(cs, 60, y) - GreenAt(ps, 60, y + 60)) <= 4);
  finally
    cs.Free;
    ps.Free;
    form.Free;
    ctl.Free;
  end;
end;

procedure TDrawFrameTest.TestGradientParentBgResolvesAtTheChildsCentre;
{ Callers that can only take ONE colour -- the window erase brush, the corner gaps outside a
  rounded silhouette, the opacity floor -- still get a single TTyColor. This pins WHICH one:
  the value at the child's own CENTRE, the minimax point, where the worst distance to any
  pixel of the control is half the sweep instead of all of it.

  Three identical 20px children at the top, middle and bottom of the same ramp must resolve
  three DIFFERENT colours -- the old behaviour returned the gradient's last stop for all
  three, white, at the top of a ramp that is black there. And each must equal the parent's
  own pixel at that child's CENTRE row, not merely fall somewhere in order: "in order" is
  also true of an edge sample, and an edge sample is what puts the whole error on the far
  side of the control. }
var
  ctl: TTyStyleController;
  form: TForm;
  panel: TGradPanelAccess;
  pb: TBitmap;
  ps: TBGRABitmap;
  top, mid, bot: TTySpeedButton;
  cTop, cMid, cBot: TTyColor;

  function Kid(AY: Integer): TTySpeedButton;
  begin
    Result := TTySpeedButton.Create(panel);
    Result.Parent := panel;
    Result.Controller := ctl;
    Result.SetBounds(0, AY, 120, 20);
  end;

  { The row the assertion expects is read back from the control, never assumed: a 20px-tall
    button comes out 24 tall once anything in the process has pumped the LCL's size queue,
    so a hard-coded centre row silently measures the wrong pixel -- and only in a full run,
    which is the worst way to find out. The contract is "the centre of whatever this control
    IS", so the test states it that way. }
  function CentreRow(AKid: TTySpeedButton): Integer;
  begin
    Result := AKid.Top + AKid.ClientHeight div 2;
  end;

begin
  ctl := TTyStyleController.Create(nil);
  ctl.LoadThemeCss(
    'TyPanel { background: linear-gradient(90deg, #000000, #FFFFFF); border-width: 0px; ' +
    'padding: 0px; }');
  form := TForm.CreateNew(nil);
  pb := TBitmap.Create;
  ps := nil;
  try
    panel := TGradPanelAccess.Create(form);
    panel.Parent := form;
    panel.Controller := ctl;
    panel.Caption := '';
    panel.SetBounds(0, 0, 120, 120);
    top := Kid(0);
    mid := Kid(50);
    bot := Kid(100);

    pb.PixelFormat := pf32bit;
    pb.SetSize(120, 120);
    panel.RenderTo(pb.Canvas, Rect(0, 0, 120, 120), 96);
    ps := TBGRABitmap.Create(pb);

    cTop := 0; cMid := 0; cBot := 0;
    AssertTrue('resolved for the top child', TyResolveParentBg(top, cTop));
    AssertTrue('resolved for the middle child', TyResolveParentBg(mid, cMid));
    AssertTrue('resolved for the bottom child', TyResolveParentBg(bot, cBot));

    AssertTrue(Format('the top child sits in the DARK end, not the last stop (green=%d)',
      [TyGreenOf(cTop)]), TyGreenOf(cTop) < 128);
    AssertTrue(Format('the bottom child sits in the light end (green=%d)',
      [TyGreenOf(cBot)]), TyGreenOf(cBot) > 200);
    { The centre, precisely: the parent's own pixel at each child's middle row. The tolerance
      carries a half-row, since an odd client height puts the sampled centre between two
      pixel rows -- worth a couple of levels on this ramp, nowhere near the tens of levels
      an edge sample or a collapsed gradient is out by. }
    AssertTrue(Format('top child == parent at its centre row %d (parent=%d resolved=%d)',
      [CentreRow(top), GreenAt(ps, 60, CentreRow(top)), TyGreenOf(cTop)]),
      Abs(TyGreenOf(cTop) - GreenAt(ps, 60, CentreRow(top))) <= 6);
    AssertTrue(Format('middle child == parent at its centre row %d (parent=%d resolved=%d)',
      [CentreRow(mid), GreenAt(ps, 60, CentreRow(mid)), TyGreenOf(cMid)]),
      Abs(TyGreenOf(cMid) - GreenAt(ps, 60, CentreRow(mid))) <= 6);
    AssertTrue(Format('bottom child == parent at its centre row %d (parent=%d resolved=%d)',
      [CentreRow(bot), GreenAt(ps, 60, CentreRow(bot)), TyGreenOf(cBot)]),
      Abs(TyGreenOf(cBot) - GreenAt(ps, 60, CentreRow(bot))) <= 6);
    AssertEquals('and every answer is opaque', 255, TyAlphaOf(cMid));
  finally
    ps.Free;
    pb.Free;
    form.Free;
    ctl.Free;
  end;
end;

initialization
  RegisterTest(TDrawFrameTest);
end.
