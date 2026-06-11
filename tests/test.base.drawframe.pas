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

initialization
  RegisterTest(TDrawFrameTest);
end.
