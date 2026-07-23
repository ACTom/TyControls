unit tyControls.GlowLabel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Accel;

{ Clamp a logical glow radius to a sane range (0..64). A negative radius means
  "no glow"; 0 also disables the halo. Pure, so it is unit-tested. }
function TyGlowClampRadius(ARadius: Integer): Integer;

type
  { A theme-driven static label that draws a soft Vista-style glow (halo) behind
    the text. The crisp text is painted in the resolved theme colour
    (CurrentStyle.TextColor); the halo is the SAME text rasterised in GlowColor,
    Gaussian-blurred by GlowRadius (logical px, PPI-scaled), and stamped a few
    times to build up intensity. Reuses the 'TyLabel' theming — no new .tycss. }
  TTyGlowLabel = class(TTyGraphicControl)
  private
    FAlignment: TAlignment;
    FLayout: TTextLayout;
    FGlowColor: TTyColor;
    FGlowRadius: Integer;
    procedure SetAlignment(AValue: TAlignment);
    procedure SetLayout(AValue: TTextLayout);
    procedure SetGlowColor(AValue: TTyColor);
    procedure SetGlowRadius(AValue: Integer);
    { Effective font size: theme, then control Font, then a default (mirrors the
      TTyLabel idiom; TTyGraphicControl has no ResolveFontSize helper). }
    function ResolveFontSize(const AStyle: TTyStyleSet): Integer;
  protected
    function GetStyleTypeKey: string; override;   // 'TyLabel' (reuse label theming)
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure TextChanged; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Caption;
    property Enabled;
    property Font;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property OnClick;
    property Alignment: TAlignment read FAlignment write SetAlignment default taLeftJustify;
    property Layout: TTextLayout read FLayout write SetLayout default tlCenter;
    { Halo colour. Default is a warm translucent white glow (Vista aero-ish). }
    property GlowColor: TTyColor read FGlowColor write SetGlowColor;
    { Gaussian blur radius of the halo, in logical px (PPI-scaled at paint). }
    property GlowRadius: Integer read FGlowRadius write SetGlowRadius default 4;
  end;

implementation

function TyGlowClampRadius(ARadius: Integer): Integer;
begin
  if ARadius < 0 then
    Result := 0
  else if ARadius > 64 then
    Result := 64
  else
    Result := ARadius;
end;

{ TTyGlowLabel }

constructor TTyGlowLabel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TyAccelRegister(Self);
  FAlignment := taLeftJustify;
  FLayout := tlCenter;
  // Default glow: soft translucent white halo (classic Vista "glow text").
  FGlowColor := TyRGBA(255, 255, 255, 200);
  FGlowRadius := 4;
end;

destructor TTyGlowLabel.Destroy;
begin
  TyAccelUnregister(Self);
  inherited Destroy;
end;

function TTyGlowLabel.GetStyleTypeKey: string;
begin
  { Own key rather than the borrowed 'TyLabel': the blurred glow layer is a mark a plain label never draws.
    Added to 'TyLabel's rule block as an extra selector, so every resolved value is
    unchanged — this opens a hook, it does not restyle anything. }
  Result := 'TyGlowLabel';
end;

function TTyGlowLabel.ResolveFontSize(const AStyle: TTyStyleSet): Integer;
begin
  Result := TyResolveFontSize(AStyle, ParentFont, Font.Size, ActiveController);
end;

procedure TTyGlowLabel.SetAlignment(AValue: TAlignment);
begin
  if FAlignment = AValue then Exit;
  FAlignment := AValue;
  Invalidate;
end;

procedure TTyGlowLabel.SetLayout(AValue: TTextLayout);
begin
  if FLayout = AValue then Exit;
  FLayout := AValue;
  Invalidate;
end;

procedure TTyGlowLabel.SetGlowColor(AValue: TTyColor);
begin
  if FGlowColor = AValue then Exit;
  FGlowColor := AValue;
  Invalidate;
end;

procedure TTyGlowLabel.SetGlowRadius(AValue: Integer);
begin
  AValue := TyGlowClampRadius(AValue);
  if FGlowRadius = AValue then Exit;
  FGlowRadius := AValue;
  Invalidate;
end;

procedure TTyGlowLabel.TextChanged;
begin
  inherited TextChanged;
  Invalidate;
end;

procedure TTyGlowLabel.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  ContentRect: TRect;
  fontSize, mp, blurDev, i, stamps: Integer;
  dispCap: string;
  glowLayer, blurred: TBGRABitmap;
  glowPx: TBGRAPixel;
  style: TTextStyle;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    fontSize := ResolveFontSize(S);
    TyParseMnemonic(Caption, dispCap, mp);
    // Honor the style opacity (e.g. :disabled { opacity: 0.5 }) like the label does;
    // the control is transparent (no background fill) so the glow reads over the parent.
    if tpOpacity in S.Present then
      P.Opacity := S.Opacity;

    ContentRect := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);

    if dispCap <> '' then
    begin
      // --- Glow halo: rasterise the text in GlowColor onto a transparent layer,
      //     Gaussian-blur it, then stamp it under the crisp text. Drawing onto a
      //     SEPARATE layer keeps the blur off the (transparent) background. ---
      glowLayer := TBGRABitmap.Create(P.Bitmap.Width, P.Bitmap.Height, BGRAPixelTransparent);
      try
        glowPx := TyColorToBGRA(FGlowColor);
        TyConfigureTextFont(glowLayer, S.FontName, fontSize, S.FontWeight, APPI);
        style := Default(TTextStyle);
        style.Alignment := FAlignment;
        style.Layout := FLayout;
        style.SingleLine := True;
        style.Clipping := True;
        glowLayer.TextRect(ContentRect, ContentRect.Left, ContentRect.Top,
          dispCap, style, glowPx);

        blurDev := P.Scale(FGlowRadius);
        if blurDev > 0 then
        begin
          blurred := glowLayer.FilterBlurRadial(blurDev, rbFast) as TBGRABitmap;
          try
            // Stamp the blurred halo a few times to intensify the glow (radial blur
            // spreads the alpha thin). More stamps for a bigger radius; crash-safe
            // and headless-safe (all in-memory BGRA ops).
            stamps := 1 + Min(3, blurDev div 4);
            for i := 1 to stamps do
              P.Bitmap.PutImage(0, 0, blurred, dmDrawWithTransparency);
          finally
            blurred.Free;
          end;
        end
        else
          // Radius 0 -> no blur; draw the (crisp) glow layer straight under the text
          // so GlowColor still contributes a subtle backing.
          P.Bitmap.PutImage(0, 0, glowLayer, dmDrawWithTransparency);
      finally
        glowLayer.Free;
      end;
    end;

    // --- Crisp text on top, in the resolved theme colour (never hard-coded). ---
    P.DrawText(ContentRect, dispCap, S.FontName, fontSize, S.FontWeight,
      S.TextColor, FAlignment, FLayout, False, TyAccelGatePos(mp));

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyGlowLabel.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
