unit test.formsurface.cache;

{$mode objfpc}{$H+}

{ The form surface keeps the form's background (TTyFormSurface.PaintFormBackground).

  A windowless control's repaint damages its parent, and for a control placed on a form that
  parent is the surface: a spinner turning on a 1200 x 800 form re-rendered the whole form
  background for every frame. The surface now renders it once and blits it after.

  What these hold: that a second paint does not render (so the cache is there at all); that
  what it blits is the bytes the direct path lays down; that everything the background
  depends on renders it again -- the surface's own Invalidate, its size, and the FORM's
  state, which a change need not announce to the surface; and that a translucent background,
  which a snapshot cannot reproduce, is never kept. Every paint lands on a bitmap first
  filled with a sentinel colour, so a background that failed to cover it, or one composited
  where it should have been copied, shows. }

interface

uses
  Classes, SysUtils, Types, Graphics, Controls, Forms,
  BGRABitmap, BGRABitmapTypes,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.Painter,
  tyControls.Form, tyControls.FormSurface;

type
  TSurfaceProbe = class(TTyFormSurface)
  public
    procedure PaintOn(ACanvas: TCanvas);
    function Renders: Integer;
  end;

  TFormSurfaceCacheTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TTyForm;
    FSurf: TSurfaceProbe;
    procedure MakeFixture(const ACss: string);
    { The surface painted onto a bitmap of its size, first filled with the sentinel. }
    function Shot: TBGRABitmap;
    { What the direct path lays down on the same ground: RenderBackgroundTo. }
    function DirectShot: TBGRABitmap;
    procedure AssertSameBytes(const AMsg: string; A, B: TBGRABitmap);
    procedure AssertShotIsDirect(const AMsg: string);
    function CentreOf(ABmp: TBGRABitmap): TBGRAPixel;
  protected
    procedure TearDown; override;
  published
    procedure TestTheDirectPathIsThePaintersFrame;
    procedure TestASecondPaintBlitsInsteadOfRendering;
    procedure TestTheBlitIsTheBytesTheDirectPathLaysDown;
    procedure TestInvalidateRendersAgain;
    procedure TestResizeRendersAgain;
    procedure TestTheFormsStyleOverrideRendersAgain;
    procedure TestAThemeChangeRendersAgain;
    procedure TestAModelChangeNobodyAnnouncedRendersAgain;
    procedure TestTheFormsPpiRendersAgain;
    procedure TestATranslucentBackgroundIsNeverKept;
  end;

implementation

const
  cW = 300;
  cH = 200;
  cSentinel = clFuchsia;
  { A border makes the form's PPI visible: its width is scaled by it. }
  cSolidCss = 'TyForm { background: #2060A0; border-color: #F0C000; border-width: 3; }';
  cGradientCss = 'TyForm { background: linear-gradient(90deg, #FF0000, #0000FF); }';

procedure TSurfaceProbe.PaintOn(ACanvas: TCanvas);
begin
  PaintFormBackground(GetParentForm(Self), ACanvas);
end;

function TSurfaceProbe.Renders: Integer;
begin
  Result := BgRenders;
end;

procedure TFormSurfaceCacheTest.MakeFixture(const ACss: string);
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(ACss);
  FForm := TTyForm.CreateNew(nil);
  FForm.SetBounds(0, 0, cW, cH);
  FForm.Controller := FCtl;
  FSurf := TSurfaceProbe.Create(FForm);
  FSurf.Parent := FForm;
  FSurf.Controller := FCtl;
  FSurf.SetBounds(0, 0, cW, cH);
end;

procedure TFormSurfaceCacheTest.TearDown;
begin
  { The form owns the surface and references the controller: the form goes first. }
  FreeAndNil(FForm);
  FSurf := nil;
  FreeAndNil(FCtl);
end;

function Ground(AW, AH: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(AW, AH);
  Result.Canvas.Brush.Color := cSentinel;
  Result.Canvas.FillRect(0, 0, AW, AH);
end;

function TFormSurfaceCacheTest.Shot: TBGRABitmap;
var
  host: TBitmap;
begin
  host := Ground(FSurf.ClientWidth, FSurf.ClientHeight);
  try
    FSurf.PaintOn(host.Canvas);
    Result := TBGRABitmap.Create(host);
  finally
    host.Free;
  end;
end;

function TFormSurfaceCacheTest.DirectShot: TBGRABitmap;
var
  host: TBitmap;
begin
  host := Ground(FSurf.ClientWidth, FSurf.ClientHeight);
  try
    FForm.RenderBackgroundTo(host.Canvas, FSurf.ClientRect);
    Result := TBGRABitmap.Create(host);
  finally
    host.Free;
  end;
end;

procedure TFormSurfaceCacheTest.AssertSameBytes(const AMsg: string; A, B: TBGRABitmap);
var
  x, y, diff: Integer;
  pa, pb: TBGRAPixel;
begin
  AssertEquals(AMsg + ': width', B.Width, A.Width);
  AssertEquals(AMsg + ': height', B.Height, A.Height);
  diff := 0;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
    begin
      pa := A.GetPixel(x, y);
      pb := B.GetPixel(x, y);
      if (pa.red <> pb.red) or (pa.green <> pb.green) or (pa.blue <> pb.blue) then
        Inc(diff);
    end;
  AssertEquals(AMsg + ': pixels that differ', 0, diff);
end;

procedure TFormSurfaceCacheTest.AssertShotIsDirect(const AMsg: string);
var
  a, b: TBGRABitmap;
begin
  a := Shot;
  b := DirectShot;
  try
    AssertSameBytes(AMsg, a, b);
  finally
    a.Free;
    b.Free;
  end;
end;

function TFormSurfaceCacheTest.CentreOf(ABmp: TBGRABitmap): TBGRAPixel;
begin
  Result := ABmp.GetPixel(ABmp.Width div 2, ABmp.Height div 2);
end;

{ RenderBackgroundTo now renders into a bitmap and lays it down; it used to open a painter
  on the canvas itself. This is that old frame, written out, against the new path. }
procedure TFormSurfaceCacheTest.TestTheDirectPathIsThePaintersFrame;

  procedure Check(const ACss: string);
  var
    host: TBitmap;
    st: TTyStyleSet;
    P: TTyPainter;
    r: TRect;
    old, cur: TBGRABitmap;
  begin
    MakeFixture(ACss);
    try
      r := FSurf.ClientRect;
      st := FCtl.Model.ResolveStyle('TyForm', '', []);
      host := Ground(r.Right, r.Bottom);
      try
        P := TTyPainter.Create;
        try
          P.BeginPaint(host.Canvas, r, FForm.Font.PixelsPerInch);
          P.FillBackground(r, st.Background, 0);
          if (st.Background.Kind <> tfkImage) and (tpBorderColor in st.Present)
             and (st.BorderWidth > 0) then
            P.StrokeBorder(r, st.BorderRadius, st.BorderWidth, st.BorderColor);
          P.EndPaint;
        finally
          P.Free;
        end;
        old := TBGRABitmap.Create(host);
      finally
        host.Free;
      end;
      cur := DirectShot;
      try
        AssertSameBytes(ACss, cur, old);
      finally
        cur.Free;
        old.Free;
      end;
    finally
      FreeAndNil(FForm);
      FSurf := nil;
      FreeAndNil(FCtl);
    end;
  end;

begin
  Check(cSolidCss);
  Check(cGradientCss);
  Check('TyForm { background: #2060A080; border-color: #F0C00080; border-width: 2; }');
end;

procedure TFormSurfaceCacheTest.TestASecondPaintBlitsInsteadOfRendering;
var
  a: TBGRABitmap;
begin
  MakeFixture(cSolidCss);
  a := Shot;
  a.Free;
  AssertEquals('the first paint renders', 1, FSurf.Renders);
  a := Shot;
  a.Free;
  a := Shot;
  a.Free;
  AssertEquals('an unchanged form is not rendered again', 1, FSurf.Renders);
end;

procedure TFormSurfaceCacheTest.TestTheBlitIsTheBytesTheDirectPathLaysDown;
var
  a: TBGRABitmap;
begin
  MakeFixture(cSolidCss);
  a := Shot;   // renders into the cache
  a.Free;
  AssertShotIsDirect('solid background with a frame, from the cache');
  AssertEquals('precondition: that was a blit', 1, FSurf.Renders);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  MakeFixture(cGradientCss);
  a := Shot;
  a.Free;
  AssertShotIsDirect('gradient background, from the cache');
  AssertEquals('precondition: that was a blit', 1, FSurf.Renders);
end;

procedure TFormSurfaceCacheTest.TestInvalidateRendersAgain;
var
  a: TBGRABitmap;
begin
  MakeFixture(cSolidCss);
  a := Shot;
  a.Free;
  FSurf.Invalidate;
  a := Shot;
  a.Free;
  AssertEquals('the surface''s own Invalidate drops the kept background', 2, FSurf.Renders);
end;

procedure TFormSurfaceCacheTest.TestResizeRendersAgain;
var
  a: TBGRABitmap;
begin
  MakeFixture(cSolidCss);
  a := Shot;
  a.Free;
  FSurf.SetBounds(0, 0, cW + 40, cH);
  AssertShotIsDirect('after a resize');
  AssertEquals('a new size is rendered', 2, FSurf.Renders);
end;

procedure TFormSurfaceCacheTest.TestTheFormsStyleOverrideRendersAgain;
var
  a: TBGRABitmap;
  p: TBGRAPixel;
begin
  MakeFixture(cSolidCss);
  a := Shot;
  a.Free;
  FForm.StyleOverride := 'background: #10C040;';
  a := Shot;
  try
    p := CentreOf(a);
    AssertTrue(Format('the form''s override shows (got #%.2x%.2x%.2x)', [p.red, p.green, p.blue]),
      (p.red = $10) and (p.green = $C0) and (p.blue = $40));
  finally
    a.Free;
  end;
  AssertShotIsDirect('after the override');
end;

procedure TFormSurfaceCacheTest.TestAThemeChangeRendersAgain;
var
  a: TBGRABitmap;
  p: TBGRAPixel;
begin
  MakeFixture(cSolidCss);
  a := Shot;
  a.Free;
  FCtl.LoadThemeCss('TyForm { background: #C02020; }');
  a := Shot;
  try
    p := CentreOf(a);
    AssertTrue(Format('the new theme shows (got #%.2x%.2x%.2x)', [p.red, p.green, p.blue]),
      (p.red = $C0) and (p.green = $20) and (p.blue = $20));
  finally
    a.Free;
  end;
end;

{ The model is public, and a change made on it directly bumps its version without telling
  any control. The direct path showed such a change on the next paint, whatever caused the
  paint; so must the cache -- a paint forced by a child would otherwise lay a patch of the
  old background under it. Only the form's key can notice. }
procedure TFormSurfaceCacheTest.TestAModelChangeNobodyAnnouncedRendersAgain;
var
  a: TBGRABitmap;
  p: TBGRAPixel;
begin
  MakeFixture(':root { --bg: #2060A0; } TyForm { background: var(--bg); }');
  a := Shot;
  a.Free;
  FCtl.Model.SetVarOverride('bg', '#C02020');
  a := Shot;
  try
    p := CentreOf(a);
    AssertTrue(Format('the changed variable shows (got #%.2x%.2x%.2x)', [p.red, p.green, p.blue]),
      (p.red = $C0) and (p.green = $20) and (p.blue = $20));
  finally
    a.Free;
  end;
  AssertEquals('it was rendered again', 2, FSurf.Renders);
end;

procedure TFormSurfaceCacheTest.TestTheFormsPpiRendersAgain;
var
  a: TBGRABitmap;
begin
  MakeFixture(cSolidCss);
  a := Shot;
  a.Free;
  { Nothing tells the surface: only the key can notice. The frame is 3 logical px, so at
    168 PPI it is 5 device px and the picture changes. }
  FForm.Font.PixelsPerInch := 168;
  AssertShotIsDirect('after the form''s PPI changed');
  AssertEquals('the form''s PPI is part of what is kept', 2, FSurf.Renders);
end;

procedure TFormSurfaceCacheTest.TestATranslucentBackgroundIsNeverKept;
var
  a: TBGRABitmap;
begin
  MakeFixture('TyForm { background: #2060A080; }');
  AssertShotIsDirect('a translucent background, first paint');
  AssertShotIsDirect('a translucent background, second paint');
  AssertEquals('every paint renders it: it is composited onto the window, not copied', 2,
    FSurf.Renders);
  a := Shot;
  a.Free;
  AssertEquals('and so does the next', 3, FSurf.Renders);
end;

initialization
  RegisterTest(TFormSurfaceCacheTest);

end.
