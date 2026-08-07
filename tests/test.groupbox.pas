unit test.groupbox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, StdCtrls, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.GroupBox;
type
  TTyGroupBoxProbe = class(TTyGroupBox)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure CallAdjustClientRect(var ARect: TRect);
  end;

  TTyGroupBoxTest = class(TTestCase)
  private
    FForm: TForm;
    FBox: TTyGroupBox;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestCaptionSettable;
    procedure TestHostsChild;
    procedure TestPaintSmoke;
    procedure TestCaptionBandErasedBorderNotVisible;
    procedure TestClientRectInsetBelowCaption;
    procedure TestGroupBoxAlignmentMovesCaption;
    procedure TestIsDesignerContainer;
  end;

implementation

procedure TTyGroupBoxProbe.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyGroupBoxProbe.DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyGroupBoxProbe.CallAdjustClientRect(var ARect: TRect);
begin
  AdjustClientRect(ARect);
end;

procedure TTyGroupBoxTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 300, 200);
  FBox := TTyGroupBox.Create(FForm);
  FBox.Parent := FForm;
  FBox.SetBounds(0, 0, 185, 105);
  FBox.Font.PixelsPerInch := 96;
end;

procedure TTyGroupBoxTest.TearDown;
begin
  FForm.Free;
end;

procedure TTyGroupBoxTest.TestTypeKey;
begin
  AssertEquals('TyGroupBox', (FBox as ITyStyleable).GetStyleTypeKey);
end;

procedure TTyGroupBoxTest.TestCaptionSettable;
begin
  FBox.Caption := 'Group';
  AssertEquals('Caption settable and readable', 'Group', FBox.Caption);
end;

procedure TTyGroupBoxTest.TestHostsChild;
var
  Child: TButton;
begin
  Child := TButton.Create(FBox);
  Child.Parent := FBox;
  AssertSame('child parent must be the groupbox', FBox, Child.Parent);
  AssertEquals('groupbox must report one child control', 1, FBox.ControlCount);
end;

procedure TTyGroupBoxTest.TestPaintSmoke;
var
  Probe: TTyGroupBoxProbe;
  Bmp: TBitmap;
begin
  Probe := TTyGroupBoxProbe.Create(FForm);
  Probe.Parent := FForm;
  Probe.Caption := 'Test Group';
  Probe.SetBounds(0, 0, 185, 105);
  Probe.Font.PixelsPerInch := 96;
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(185, 105);
    Probe.RenderTo(Bmp.Canvas, Rect(0, 0, 185, 105), 96);
    AssertTrue('groupbox RenderTo executed without exception', True);
  finally
    Bmp.Free;
  end;
end;

procedure TTyGroupBoxTest.TestCaptionBandErasedBorderNotVisible;
{ With a red border, transparent background, and a single-glyph CJK caption
  rendered over a white bitmap:
  (a) A border pixel on the top edge OUTSIDE the caption band x-range must be
      red-dominant (border visible where no text erasing occurred).
  (b) A pixel INSIDE the band at the border's y (capH div 2 = 8) must NOT be
      red-dominant — the band was erased to the parent background, so the border
      does not show there.

  2026-08-07 recalibration (aero black-corner fix): the band is erased to the RESOLVED
  parent background. This fixture's raw form left Color = clDefault, which the resolver
  used to read via bare ColorToRGB — i.e. BLACK — so the old "red < 100" assertion was
  green only because the band was black (the very defect class the aero fix removed;
  its own comment claimed white showed through, which never held). The form colour is
  now pinned WHITE so the band genuinely erases to white, and the assertion states the
  actual contract: the band pixel is not red-dominant (the border is gone there). }
var
  Ctl: TTyStyleController;
  Form: TForm;
  Probe: TTyGroupBoxProbe;
  Bmp: TBitmap;
  BgBmp: TBGRABitmap;
  Reread: TBGRABitmap;
  PxOutside, PxInside: TBGRAPixel;
  BandX: Integer;
  FoundWhite: Boolean;
  CapY: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGroupBox { border-color: #FF0000; border-width: 2px; border-radius: 0px; ' +
      'background: alpha(#000000,0); color: #000000; font-size: 12px; }');
    Form.Color := clWhite;   // deterministic parent bg: the band must erase to THIS
    Probe := TTyGroupBoxProbe.Create(Form);
    Probe.Parent := Form;
    Probe.Controller := Ctl;
    Probe.Caption := '组';
    Probe.SetBounds(0, 0, 185, 105);
    Probe.Font.PixelsPerInch := 96;

    // Fill canvas white so erased regions show white
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(185, 105);
    BgBmp := TBGRABitmap.Create(185, 105, BGRA(255, 255, 255, 255));
    try
      BgBmp.Draw(Bmp.Canvas, 0, 0, False);
    finally
      BgBmp.Free;
    end;

    Probe.RenderTo(Bmp.Canvas, Rect(0, 0, 185, 105), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // CapH = MulDiv(16, 96, 96) = 16; border is at y = CapH div 2 = 8
      CapY := 8;
      // (a) Far-right pixel at border y — outside the caption band x-range
      PxOutside := Reread.GetPixel(180, CapY);
      AssertTrue('border outside band: red > 100 (border visible)', PxOutside.red > 100);
      AssertTrue('border outside band: red > blue (red-dominant)', PxOutside.red > PxOutside.blue);
      // (b) The band interior at the border's y. A single pixel cannot be pinned here:
      // the caption ink starts at BandLeft+Scale(4) and anti-aliases (a black glyph edge
      // on the white band reads mid-grey — x=20 used to sit ON the ink, invisible only
      // while the band was black), so assert over the band interior x=6..18 instead:
      //   - the RED BORDER shows nowhere in it (no red-dominant pixel), and
      //   - the erased parent WHITE shows somewhere in it (a light, neutral pixel).
      FoundWhite := False;
      for BandX := 6 to 18 do
      begin
        PxInside := Reread.GetPixel(BandX, CapY);
        AssertTrue(Format('inside erased band: no border-red pixel at x=%d ' +
          '(border erased; got %d,%d,%d)',
          [BandX, PxInside.red, PxInside.green, PxInside.blue]),
          PxInside.red <= PxInside.blue + 80);
        if (PxInside.blue > 200) and (PxInside.red <= PxInside.blue + 20) then
          FoundWhite := True;
      end;
      AssertTrue('inside erased band: the white parent bg shows through somewhere ' +
        'in x=6..18 (band erased to the resolved parent colour, not left dark)',
        FoundWhite);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ TestClientRectInsetBelowCaption
  PPI pinned to 96. CapH = MulDiv(16, 96, 96) = 16.
  Start with Rect(0, 0, 185, 105), call AdjustClientRect directly,
  assert ARect.Top = 16 (inset by exactly the caption band height). }
procedure TTyGroupBoxTest.TestClientRectInsetBelowCaption;
var
  Probe: TTyGroupBoxProbe;
  ARect: TRect;
begin
  Probe := TTyGroupBoxProbe.Create(FForm);
  Probe.Parent := FForm;
  Probe.Font.PixelsPerInch := 96;
  Probe.SetBounds(0, 0, 185, 105);
  try
    ARect := Rect(0, 0, 185, 105);
    Probe.CallAdjustClientRect(ARect);
    AssertEquals('AdjustClientRect insets Top by caption band height (16px@96ppi)',
      16, ARect.Top);
  finally
    Probe.Free;
  end;
end;

procedure TTyGroupBoxTest.TestGroupBoxAlignmentMovesCaption;
  function InkCentroidX(A: TAlignment): Double;
  var G: TTyGroupBoxProbe; bmp: TBitmap; reread: TBGRABitmap; x,y,n: Integer; sx: Double; px: TBGRAPixel;
  begin
    G := TTyGroupBoxProbe.Create(nil); bmp := TBitmap.Create;
    try
      G.Caption := 'Hi'; G.Alignment := A; G.Font.PixelsPerInch := 96;
      bmp.PixelFormat := pf32bit; bmp.SetSize(200, 60);
      bmp.Canvas.Brush.Color := clWhite; bmp.Canvas.FillRect(0,0,200,60);
      G.DoRenderTo(bmp.Canvas, Rect(0,0,200,60), 96);
      reread := TBGRABitmap.Create(bmp);
      try
        sx := 0; n := 0;
        for x := 0 to 199 do for y := 0 to 15 do
        begin px := reread.GetPixel(x,y);
          if (px.red<160) and (px.green<160) then begin sx := sx + x; Inc(n); end; end;
        if n = 0 then Result := -1 else Result := sx / n;
      finally reread.Free; end;
    finally bmp.Free; G.Free; end;
  end;
var cl, cr: Double;
begin
  cl := InkCentroidX(taLeftJustify);
  cr := InkCentroidX(taRightJustify);
  AssertTrue('left caption ink present', cl > 0);
  AssertTrue('right-aligned caption further right', cr > cl + 20);
end;

procedure TTyGroupBoxTest.TestIsDesignerContainer;
begin
  // csAcceptsControls makes the IDE designer drop child controls INTO the group box
  // (they lay out below the caption band via AdjustClientRect).
  AssertTrue('group box is a designer container', csAcceptsControls in FBox.ControlStyle);
end;

initialization
  RegisterTest(TTyGroupBoxTest);
end.
