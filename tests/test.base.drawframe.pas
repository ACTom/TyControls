unit test.base.drawframe;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, BGRABitmap, BGRABitmapTypes,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Base, tyControls.Painter;
type
  TDrawFrameProbe = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
  public
    procedure RunDrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
  end;

  TDrawFrameTest = class(TTestCase)
  published
    procedure TestSolidBackgroundCenterPixel;
    procedure TestOpacityDimsControl;
    procedure TestBorderStyleNoneSuppressesBorder;
    procedure TestPerCornerBackgroundViaDrawFrame;
    procedure TestFocusRingDrawnWhenOutlinePresent;
  end;
implementation

function TDrawFrameProbe.GetStyleTypeKey: string;
begin
  Result := 'TyPanel';
end;

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

initialization
  RegisterTest(TDrawFrameTest);
end.
