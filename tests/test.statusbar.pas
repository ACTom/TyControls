unit test.statusbar;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, Graphics, Forms, LCLType,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.StatusBar;
type
  TStatusBarGeomTest = class(TTestCase)
  published
    procedure TestPanelRectsFixed;
    procedure TestPanelRectsFillPanel;
    procedure TestPanelRectsPadding;
    procedure TestPanelRectsFillFirstOnly;
    procedure TestPanelRectsOverflowAndEmpty;
  end;

  { Access subclass that re-exposes protected RenderTo as public }
  TTyStatusBarPixAccess = class(TTyStatusBar)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TStatusBarPixelTest = class(TTestCase)
  published
    procedure TestBodyPixelIsDark;
  end;
implementation
procedure TStatusBarGeomTest.TestPanelRectsFixed;
var r: TTyRectArray;
begin
  r := TyStatusPanelRects([50, 80], 200, 0);
  AssertEquals('count', 2, Length(r));
  AssertEquals('p0.left', 0, r[0].Left);   AssertEquals('p0.right', 50, r[0].Right);
  AssertEquals('p1.left', 50, r[1].Left);  AssertEquals('p1.right', 130, r[1].Right);
  AssertEquals('p0.top sentinel', 0, r[0].Top); AssertEquals('p0.bottom sentinel', 0, r[0].Bottom);
end;
procedure TStatusBarGeomTest.TestPanelRectsFillPanel;
var r: TTyRectArray;
begin
  // a panel with Width<=0 fills the remaining width (first such panel only)
  r := TyStatusPanelRects([50, 0, 40], 200, 0);
  AssertEquals('fill panel right', 160, r[1].Right);   // 50 + (200-50-40)=110 -> 50..160
  AssertEquals('p2 left', 160, r[2].Left);             AssertEquals('p2 right', 200, r[2].Right);
end;
procedure TStatusBarGeomTest.TestPanelRectsPadding;
var r: TTyRectArray;
begin
  r := TyStatusPanelRects([50, 80], 200, 10);
  AssertEquals('p0.left', 10, r[0].Left);   AssertEquals('p0.right', 60, r[0].Right);
  AssertEquals('p1.left', 60, r[1].Left);   AssertEquals('p1.right', 140, r[1].Right);
end;
procedure TStatusBarGeomTest.TestPanelRectsFillFirstOnly;
var r: TTyRectArray;
begin
  // two <=0 panels: only the FIRST fills; the second gets zero width
  r := TyStatusPanelRects([0, 0, 40], 200, 0);
  AssertEquals('fill panel right', 160, r[0].Right);          // 200-40
  AssertEquals('second <=0 zero width', r[1].Left, r[1].Right);
  AssertEquals('p2 left', 160, r[2].Left);                   AssertEquals('p2 right', 200, r[2].Right);
end;
procedure TStatusBarGeomTest.TestPanelRectsOverflowAndEmpty;
var r: TTyRectArray;
begin
  // fixed widths exceed total + a fill panel -> fill clamps to 0
  r := TyStatusPanelRects([150, 0, 120], 200, 0);
  AssertEquals('overflow fill collapses', r[1].Left, r[1].Right);
  // empty input -> empty result
  r := TyStatusPanelRects([], 200, 0);
  AssertEquals('empty', 0, Length(r));
end;
{ TTyStatusBarPixAccess }

procedure TTyStatusBarPixAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

{ TStatusBarPixelTest }

procedure TStatusBarPixelTest.TestBodyPixelIsDark;
{ Theme: background: #202020 (32,32,32), color: #FFFFFF, border-color: #404040.
  Control: 200x22 statusbar with one panel Text='Hi'.
  The body background #202020 should appear throughout most of the bar.
  Assert a body pixel (x=10, y=11 — well inside, away from hairlines and text)
  has all channels < 60. The top hairline (y=0) should be slightly lighter
  (#404040 = 64 each); assert its red channel >= 40.
}
var
  Ctl: TTyStyleController;
  Form: TForm;
  Bar: TTyStatusBarPixAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  PxBody, PxHairline: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyStatusBar { background: #202020; color: #FFFFFF; border-color: #404040; }');

    Bar := TTyStatusBarPixAccess.Create(Form);
    Bar.Parent := Form;
    Bar.Controller := Ctl;
    Bar.SetBounds(0, 0, 200, 22);
    Bar.Font.PixelsPerInch := 96;
    Bar.SizeGrip := False;
    Bar.Panels.Add.Text := 'Hi';

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 22);
    // Pre-fill white so background rendering is unambiguous (canvas default is undefined)
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 200, 22);
    Bar.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 22), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Mid-body pixel at x=150, y=11 — far from text (panel width=50, text in x=8..50),
      // far from top hairline (y=0), and size grip is disabled.
      PxBody := Reread.GetPixel(150, 11);
      // Top hairline (y=0): #404040 = 64 per channel
      PxHairline := Reread.GetPixel(150, 0);
      AssertTrue(
        Format('body pixel should be dark (r=%d g=%d b=%d alpha=%d at x=150,y=11, expected < 60; hairline r=%d)',
          [PxBody.red, PxBody.green, PxBody.blue, PxBody.alpha, PxHairline.red]),
        (PxBody.red < 60) and (PxBody.green < 60) and (PxBody.blue < 60));

      // Top hairline (y=0): #404040 = 64 per channel — lighter than body (#202020 = 32)
      AssertTrue(
        Format('hairline rendered (hairline.red=%d, expected >=55)',
          [PxHairline.red]),
        PxHairline.red >= 55);

      AssertTrue(
        Format('top hairline should be lighter than body (hairline.red=%d > body.red=%d)',
          [PxHairline.red, PxBody.red]),
        PxHairline.red > PxBody.red);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TStatusBarGeomTest);
  RegisterTest(TStatusBarPixelTest);
end.
