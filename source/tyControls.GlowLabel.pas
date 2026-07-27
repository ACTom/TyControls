unit tyControls.GlowLabel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType,
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
    FRefitting: Boolean;   // guards the AutoSize re-fit in Invalidate against re-entry
    procedure SetAlignment(AValue: TAlignment);
    procedure SetLayout(AValue: TTextLayout);
    procedure SetGlowColor(AValue: TTyColor);
    procedure SetGlowRadius(AValue: Integer);
    { Effective font size: theme, then control Font, then a default (mirrors the
      TTyLabel idiom; TTyGraphicControl has no ResolveFontSize helper). }
    function ResolveFontSize(const AStyle: TTyStyleSet): Integer;
  protected
    function GetStyleTypeKey: string; override;   // 'TyLabel' (reuse label theming)
    { The width the caption really needs: the measured text, the theme's padding and one
      glow radius on EACH side. Without it the label keeps whatever width the .lfm gave it,
      and a caption that outgrows that width -- a longer translation, a denser scale, a skin
      with a bigger font -- is clipped. A skin legitimately changes font and padding, which
      is exactly why a hand-set width cannot survive a skin switch. }
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    { The caption's drawn size in DEVICE px at APPI, mnemonic markers removed -- RenderTo
      draws the TyParseMnemonic'd text, so the '&' is an underline, not a glyph, and must
      not be measured as one. }
    procedure MeasureCaption(APPI: Integer; out AWidth, AHeight: Integer);
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure TextChanged; override;
    { A theme switch reaches every control as a bare Invalidate, and the new theme brings a
      different font and padding -- so the width the caption needs changed too and an
      AutoSize label has to re-fit here, not merely repaint. }
    procedure Invalidate; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    { Off by default (a designed label keeps the width the .lfm gave it). Switch it on and the
      label WIDENS to hug its caption plus the theme's padding and the halo's spread, so a
      caption that grows lengthens the label instead of being clipped. Height is left alone
      (see CalculatePreferredSize): it belongs to whoever lays out the row. }
    property AutoSize;
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

procedure TTyGlowLabel.MeasureCaption(APPI: Integer; out AWidth, AHeight: Integer);
var
  S: TTyStyleSet;
  Meas: TBitmap;
  disp: string;
  mp: Integer;
begin
  // The same style RenderTo paints with, so what AutoSize reserves and what gets drawn
  // cannot drift when a skin changes the font family, size or weight.
  S := CurrentStyle;
  // The '&' markers are drawn as an underline, not as characters, so they are not measured.
  TyParseMnemonic(Caption, disp, mp);
  Meas := TBitmap.Create;
  try
    Meas.SetSize(1, 1);
    Meas.Canvas.Font.Name := TyEffectiveFontName(S.FontName);
    Meas.Canvas.Font.Size := MulDiv(ResolveFontSize(S), APPI, 96);
    // TyConfigureTextFont (which both paint passes go through) bolds at weight >= 600.
    if S.FontWeight >= 600 then
      Meas.Canvas.Font.Style := [fsBold]
    else
      Meas.Canvas.Font.Style := [];
    AWidth := Meas.Canvas.TextWidth(disp);
    // A stable reference glyph: an empty caption still measures as one line.
    AHeight := Meas.Canvas.TextHeight('Ag');
    if AWidth < 0 then AWidth := 0;
    if AHeight < 1 then AHeight := 1;
  finally
    Meas.Free;
  end;
end;

procedure TTyGlowLabel.CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
  WithThemeSpace: Boolean);
var
  S: TTyStyleSet;
  ppi, tw, th, glowRun: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  MeasureCaption(ppi, tw, th);
  { The halo is this control's own "slot", the way a close glyph is TTyTag's. The glow layer
    is the same text blurred by P.Scale(GlowRadius) -- and P.Scale is MulDiv(x, ppi, 96), so
    this is the identical arithmetic -- which bleeds one radius OUTWARD from the glyphs in
    every direction. The blur happens on a layer the size of the control's own bitmap, so
    whatever spills past the edges is simply clipped away: a box that fits only the crisp
    text shows a halo with its outer edge shaved off. Reserve one radius per side. }
  glowRun := MulDiv(TyGlowClampRadius(FGlowRadius), ppi, 96);
  { The theme padding is added even though RenderTo lays the caption out in the FULL client
    rect (this control applies no padding inset): that can only leave slack, never cut the
    caption short, and a skin that pads TyGlowLabel still gets the roomier box it asked for. }
  PreferredWidth := tw + MulDiv(S.Padding.Left + S.Padding.Right, ppi, 96) + 2 * glowRun;
  if PreferredWidth < 1 then PreferredWidth := 1;
  { WIDTH ONLY -- 0 is LCL's "no preference on this axis", so the label keeps its height.
    A caption-driven control grows sideways for a longer caption; its height is a LAYOUT
    decision, owned by whoever arranges the row. Proposing a height as well makes the control
    fight any container that pins one: TTyToolBar sizes every child to its ButtonHeight, so a
    child asking for a different one bounced between the two until LCL aborted with
    "TControl.ChangeBounds loop detected". Callers who want the caption's natural height can
    read it from MeasureCaption plus the style's vertical padding. }
  PreferredHeight := 0;
end;

procedure TTyGlowLabel.TextChanged;
begin
  inherited TextChanged;
  // The new caption needs a different width, so an auto-sized label must re-fit.
  if AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
  Invalidate;
end;

procedure TTyGlowLabel.Invalidate;
begin
  inherited Invalidate;
  { A theme switch reaches every control as a bare Invalidate (TTyStyleController broadcasts
    one to each registered control), and the new theme brings a different font and padding --
    so the width an AutoSize label needs changed too. Without re-fitting here the label keeps
    the old skin's width and the caption is clipped, which is exactly what a hand-set width
    does under the 'xp' skin. Setting GlowRadius also lands here (its setter invalidates),
    which is how a widened halo re-reserves its room.
    FRefitting guards the re-entry: AdjustSize -> SetBounds -> Invalidate would recurse. }
  if AutoSize and not FRefitting and not (csDestroying in ComponentState) then
  begin
    FRefitting := True;
    try
      InvalidatePreferredSize;
      AdjustSize;
    finally
      FRefitting := False;
    end;
  end;
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
