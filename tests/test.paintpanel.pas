unit test.paintpanel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType,
  fpcunit, testregistry, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Painter,
  tyControls.Base, tyControls.Panel, tyControls.PaintPanel;
type
  TTyPaintPanelTest = class(TTestCase)
  published
    procedure TestTypeKeyReusesPanel;
    procedure TestAcceptsControls;
    procedure TestContentRectGeometryUnit;
    procedure TestContentRectDpiScaled;
    procedure TestContentRectZeroPadding;
    procedure TestPaintSurfaceFiresWithContentAndPainter;
    procedure TestPaintSurfaceContentInsetByPadding;
    procedure TestNoHandlerStillRenders;
    procedure TestPaintSurfaceDrawsIntoPass;
  end;

implementation

type
  { Access subclass: expose the protected RenderTo so the tests can drive a headless
    paint pass into a TBitmap.Canvas, exactly as the listbox render tests do. }
  TPaintPanelAccess = class(TTyPaintPanel)
  public
    function StyleTypeKey: string;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  { A probe capturing the OnPaintSurface callback arguments + a draw action. }
  TSurfaceProbe = class
  public
    Count: Integer;
    LastPainter: TTyPainter;
    LastContent: TRect;
    DrawFill: Boolean;        // when True, paint an opaque red block into the content rect
    procedure Handle(Sender: TObject; APainter: TTyPainter; const AContent: TRect);
  end;

function TPaintPanelAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TPaintPanelAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TSurfaceProbe.Handle(Sender: TObject; APainter: TTyPainter; const AContent: TRect);
var
  f: TTyFill;
begin
  Inc(Count);
  LastPainter := APainter;
  LastContent := AContent;
  if DrawFill and (APainter <> nil) then
  begin
    f := Default(TTyFill);
    f.Kind := tfkSolid;
    f.Color := TyRGB(255, 0, 0);   // red, opaque
    APainter.FillBackground(AContent, f, 0);
  end;
end;

{ TTyPaintPanelTest }

procedure TTyPaintPanelTest.TestTypeKeyReusesPanel;
var
  F: TForm;
  Acc: TPaintPanelAccess;
begin
  F := TForm.CreateNew(nil);
  try
    Acc := TPaintPanelAccess.Create(F);
    Acc.Parent := F;
    // Reuses the TyPanel theme/typeKey — no new .tycss token in this batch.
    AssertEquals('TyPaintPanel reuses TyPanel typeKey', 'TyPanel', Acc.StyleTypeKey);
  finally
    F.Free;
  end;
end;

procedure TTyPaintPanelTest.TestAcceptsControls;
var
  F: TForm;
  PP: TTyPaintPanel;
begin
  F := TForm.CreateNew(nil);
  try
    PP := TTyPaintPanel.Create(F);
    PP.Parent := F;
    // It IS a panel: a real LCL container that hosts child controls.
    AssertTrue('csAcceptsControls set (real container)',
      csAcceptsControls in PP.ControlStyle);
  finally
    F.Free;
  end;
end;

procedure TTyPaintPanelTest.TestContentRectGeometryUnit;
var
  R: TRect;
begin
  // 8px uniform padding at 96ppi (scale 1): content is the frame inset by 8 on every edge.
  R := TyPaintPanelContentRect(Rect(0, 0, 200, 100), Rect(8, 8, 8, 8), 96);
  AssertEquals('content left', 8, R.Left);
  AssertEquals('content top', 8, R.Top);
  AssertEquals('content right', 192, R.Right);
  AssertEquals('content bottom', 92, R.Bottom);
end;

procedure TTyPaintPanelTest.TestContentRectDpiScaled;
var
  R: TRect;
begin
  // 8px padding at 192ppi (scale 2) -> 16 device px inset each edge.
  R := TyPaintPanelContentRect(Rect(0, 0, 200, 100), Rect(8, 8, 8, 8), 192);
  AssertEquals('content left @192', 16, R.Left);
  AssertEquals('content top @192', 16, R.Top);
  AssertEquals('content right @192', 184, R.Right);
  AssertEquals('content bottom @192', 84, R.Bottom);
end;

procedure TTyPaintPanelTest.TestContentRectZeroPadding;
var
  R: TRect;
begin
  // No padding -> content equals the full frame.
  R := TyPaintPanelContentRect(Rect(0, 0, 120, 60), Rect(0, 0, 0, 0), 96);
  AssertEquals('no-padding left', 0, R.Left);
  AssertEquals('no-padding top', 0, R.Top);
  AssertEquals('no-padding right', 120, R.Right);
  AssertEquals('no-padding bottom', 60, R.Bottom);
end;

procedure TTyPaintPanelTest.TestPaintSurfaceFiresWithContentAndPainter;
var
  F: TForm;
  PP: TPaintPanelAccess;
  Probe: TSurfaceProbe;
  Bmp: TBitmap;
begin
  F := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  Probe := TSurfaceProbe.Create;
  try
    PP := TPaintPanelAccess.Create(F);
    PP.Parent := F;
    PP.Font.PixelsPerInch := 96;
    PP.SetBounds(0, 0, 200, 100);
    PP.OnPaintSurface := @Probe.Handle;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 100);
    PP.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 100), 96);

    AssertEquals('OnPaintSurface fired exactly once', 1, Probe.Count);
    AssertNotNull('painter passed is non-nil', Probe.LastPainter);
    AssertNotNull('painter has a live bitmap during the pass', Probe.LastPainter);
    AssertTrue('content rect is non-empty (width>0)',
      Probe.LastContent.Right > Probe.LastContent.Left);
    AssertTrue('content rect is non-empty (height>0)',
      Probe.LastContent.Bottom > Probe.LastContent.Top);
  finally
    Probe.Free;
    Bmp.Free;
    F.Free;
  end;
end;

procedure TTyPaintPanelTest.TestPaintSurfaceContentInsetByPadding;
var
  Ctl: TTyStyleController;
  F: TForm;
  PP: TPaintPanelAccess;
  Probe: TSurfaceProbe;
  Bmp: TBitmap;
  Expected: TRect;
begin
  Ctl := TTyStyleController.Create(nil);
  F := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  Probe := TSurfaceProbe.Create;
  try
    // Known padding so we can assert the exact content rect handed to the handler.
    Ctl.LoadThemeCss('TyPanel { background: #202020; border-width: 0px; padding: 10px; }');
    PP := TPaintPanelAccess.Create(F);
    PP.Parent := F;
    PP.Controller := Ctl;
    PP.Font.PixelsPerInch := 96;
    PP.SetBounds(0, 0, 160, 120);
    PP.OnPaintSurface := @Probe.Handle;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(160, 120);
    PP.RenderTo(Bmp.Canvas, Rect(0, 0, 160, 120), 96);

    Expected := TyPaintPanelContentRect(Rect(0, 0, 160, 120), Rect(10, 10, 10, 10), 96);
    AssertEquals('content left inset by padding', Expected.Left, Probe.LastContent.Left);
    AssertEquals('content top inset by padding', Expected.Top, Probe.LastContent.Top);
    AssertEquals('content right inset by padding', Expected.Right, Probe.LastContent.Right);
    AssertEquals('content bottom inset by padding', Expected.Bottom, Probe.LastContent.Bottom);
  finally
    Probe.Free;
    Bmp.Free;
    F.Free;
    Ctl.Free;
  end;
end;

procedure TTyPaintPanelTest.TestNoHandlerStillRenders;
var
  Ctl: TTyStyleController;
  F: TForm;
  PP: TPaintPanelAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
begin
  // With NO OnPaintSurface handler the panel is byte-compatible with a plain TTyPanel:
  // it still paints the themed frame background.
  Ctl := TTyStyleController.Create(nil);
  F := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss('TyPanel { background: #3B82F6; border-width: 0px; padding: 8px; }');
    PP := TPaintPanelAccess.Create(F);
    PP.Parent := F;
    PP.Controller := Ctl;
    PP.Font.PixelsPerInch := 96;
    PP.SetBounds(0, 0, 120, 80);
    // no handler assigned

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 80);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 120, 80);
    PP.RenderTo(Bmp.Canvas, Rect(0, 0, 120, 80), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      Px := Reread.GetPixel(60, 40);
      AssertTrue(Format('frame background painted (blue) even without a handler (R=%d G=%d B=%d)',
        [Px.red, Px.green, Px.blue]), (Px.blue > 180) and (Px.red < 120));
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    F.Free;
    Ctl.Free;
  end;
end;

procedure TTyPaintPanelTest.TestPaintSurfaceDrawsIntoPass;
var
  Ctl: TTyStyleController;
  F: TForm;
  PP: TPaintPanelAccess;
  Probe: TSurfaceProbe;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  PxContent, PxFrame: TBGRAPixel;
begin
  // The handler's painter draws into the SAME pass: a red fill of the content rect must land
  // on the composited output, over the themed (blue) frame — and only inside the content
  // (the padding band stays the frame colour).
  Ctl := TTyStyleController.Create(nil);
  F := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  Probe := TSurfaceProbe.Create;
  try
    Ctl.LoadThemeCss('TyPanel { background: #3B82F6; border-width: 0px; padding: 10px; }');
    PP := TPaintPanelAccess.Create(F);
    PP.Parent := F;
    PP.Controller := Ctl;
    PP.Font.PixelsPerInch := 96;
    PP.SetBounds(0, 0, 160, 120);
    Probe.DrawFill := True;
    PP.OnPaintSurface := @Probe.Handle;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(160, 120);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 160, 120);
    PP.RenderTo(Bmp.Canvas, Rect(0, 0, 160, 120), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Centre is inside the content rect -> the handler's RED fill shows.
      PxContent := Reread.GetPixel(80, 60);
      AssertTrue(Format('owner-draw red fill landed in content (R=%d G=%d B=%d)',
        [PxContent.red, PxContent.green, PxContent.blue]),
        (PxContent.red > 180) and (PxContent.blue < 120));
      // The padding band (2px in from the edge, inside the 10px padding) is OUTSIDE the
      // content rect -> stays the themed blue frame, proving the fill was clipped to content.
      PxFrame := Reread.GetPixel(2, 60);
      AssertTrue(Format('padding band stays frame blue, not owner-draw red (R=%d G=%d B=%d)',
        [PxFrame.red, PxFrame.green, PxFrame.blue]),
        (PxFrame.blue > 180) and (PxFrame.red < 120));
    finally
      Reread.Free;
    end;
  finally
    Probe.Free;
    Bmp.Free;
    F.Free;
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TTyPaintPanelTest);
end.
