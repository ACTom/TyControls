unit tyControls.ShadowLabel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base;

type
  { A themed static-text label that draws its caption with a drop shadow.
    Leaf TTyGraphicControl. Reuses the label theming (typeKey 'TyLabel', so no
    extra .tycss rules): text colour / font family / weight / size all come from
    the resolved style (CurrentStyle). The caption is painted twice via
    TTyPainter.DrawText -- first offset by (ShadowOffsetX, ShadowOffsetY) logical
    px in ShadowColor, then the main text at the normal position in the theme's
    TextColor. Offsets are PPI-scaled through P.Scale. }
  TTyShadowLabel = class(TTyGraphicControl)
  private
    FAlignment: TAlignment;
    FLayout: TTextLayout;
    FShadowColor: TTyColor;
    FShadowOffsetX: Integer;
    FShadowOffsetY: Integer;
    FRefitting: Boolean;   // guards the AutoSize re-fit in Invalidate against re-entry
    procedure SetAlignment(AValue: TAlignment);
    procedure SetLayout(AValue: TTextLayout);
    procedure SetShadowColor(AValue: TTyColor);
    procedure SetShadowOffsetX(AValue: Integer);
    procedure SetShadowOffsetY(AValue: Integer);
    { Resolve the effective font size (theme, then control Font, then a default).
      Mirrors TTyLabel.ResolveFontSize (TTyGraphicControl has no such helper). }
    function ResolveFontSize(const AStyle: TTyStyleSet): Integer;
  protected
    function GetStyleTypeKey: string; override;   // 'TyLabel' -- reuse label theming
    { The width the caption really needs: the measured text, the THEME's padding (the very
      inset RenderTo applies before both text passes) and the shadow's horizontal throw.
      Without it the label keeps whatever width the .lfm gave it, and a caption that outgrows
      that width -- a longer translation, a denser scale, a skin with a bigger font or roomier
      padding -- is clipped. A skin legitimately changes font and padding, which is exactly
      why a hand-set width cannot survive a skin switch. }
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    { The caption's drawn size in DEVICE px at APPI. The '&' is deliberately NOT stripped:
      RenderTo hands Caption to DrawText verbatim (this label does no mnemonic parsing), so
      an ampersand is a real glyph here and measuring it away would under-reserve. }
    procedure MeasureCaption(APPI: Integer; out AWidth, AHeight: Integer);
    { Caption changes at runtime route here (CM_TEXTCHANGED); with AutoSize the label must
      re-measure to the new text. }
    procedure TextChanged; override;
    { A theme switch reaches every control as a bare Invalidate, and the new theme brings a
      different font and padding -- so the width the caption needs changed too and an
      AutoSize label has to re-fit here, not merely repaint. }
    procedure Invalidate; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    { Off by default (a designed label keeps the width the .lfm gave it). Switch it on and the
      label WIDENS to hug its caption plus the theme's padding and the shadow's throw, so a
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
    property ShadowColor: TTyColor read FShadowColor write SetShadowColor;
    property ShadowOffsetX: Integer read FShadowOffsetX write SetShadowOffsetX default 1;
    property ShadowOffsetY: Integer read FShadowOffsetY write SetShadowOffsetY default 1;
  end;

implementation

constructor TTyShadowLabel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAlignment := taLeftJustify;
  FLayout := tlCenter;
  FShadowColor := TyRGBA(0, 0, 0, 120);   // semi-transparent black
  FShadowOffsetX := 1;
  FShadowOffsetY := 1;
end;

function TTyShadowLabel.GetStyleTypeKey: string;
begin
  { Own key rather than the borrowed 'TyLabel': it draws the caption twice, and the shadow pass is chrome a plain label has no notion of.
    Added to 'TyLabel's rule block as an extra selector, so every resolved value is
    unchanged — this opens a hook, it does not restyle anything. }
  Result := 'TyShadowLabel';
end;

function TTyShadowLabel.ResolveFontSize(const AStyle: TTyStyleSet): Integer;
begin
  Result := TyResolveFontSize(AStyle, ParentFont, Font.Size, ActiveController);
end;

procedure TTyShadowLabel.SetAlignment(AValue: TAlignment);
begin
  if FAlignment = AValue then Exit;
  FAlignment := AValue;
  Invalidate;
end;

procedure TTyShadowLabel.SetLayout(AValue: TTextLayout);
begin
  if FLayout = AValue then Exit;
  FLayout := AValue;
  Invalidate;
end;

procedure TTyShadowLabel.SetShadowColor(AValue: TTyColor);
begin
  if FShadowColor = AValue then Exit;
  FShadowColor := AValue;
  Invalidate;
end;

procedure TTyShadowLabel.SetShadowOffsetX(AValue: Integer);
begin
  if FShadowOffsetX = AValue then Exit;
  FShadowOffsetX := AValue;
  Invalidate;
end;

procedure TTyShadowLabel.SetShadowOffsetY(AValue: Integer);
begin
  if FShadowOffsetY = AValue then Exit;
  FShadowOffsetY := AValue;
  Invalidate;
end;

procedure TTyShadowLabel.MeasureCaption(APPI: Integer; out AWidth, AHeight: Integer);
var
  S: TTyStyleSet;
  Meas: TBitmap;
begin
  // The same style RenderTo paints with, so what AutoSize reserves and what gets drawn
  // cannot drift when a skin changes the font family, size or weight.
  S := CurrentStyle;
  Meas := TBitmap.Create;
  try
    Meas.SetSize(1, 1);
    Meas.Canvas.Font.Name := TyEffectiveFontName(S.FontName);
    Meas.Canvas.Font.Size := MulDiv(ResolveFontSize(S), APPI, 96);
    // TyConfigureTextFont (which the paint path goes through) bolds at weight >= 600.
    if S.FontWeight >= 600 then
      Meas.Canvas.Font.Style := [fsBold]
    else
      Meas.Canvas.Font.Style := [];
    // Caption verbatim -- RenderTo never calls TyParseMnemonic, so an '&' is a drawn glyph.
    AWidth := Meas.Canvas.TextWidth(Caption);
    // A stable reference glyph: an empty caption still measures as one line.
    AHeight := Meas.Canvas.TextHeight('Ag');
    if AWidth < 0 then AWidth := 0;
    if AHeight < 1 then AHeight := 1;
  finally
    Meas.Free;
  end;
end;

procedure TTyShadowLabel.CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
  WithThemeSpace: Boolean);
var
  S: TTyStyleSet;
  ppi, tw, th, shadowRun: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  MeasureCaption(ppi, tw, th);
  { The shadow pass is the SAME caption drawn at ContentRect shifted sideways by
    P.Scale(ShadowOffsetX) -- and P.Scale is MulDiv(x, ppi, 96), so this is the identical
    arithmetic. It therefore runs that far past the crisp glyphs on one side, and a box that
    only fits the crisp text has the drop shadow shaved off by the clip. Abs(): a negative
    offset throws the shadow the other way and needs exactly as much room. }
  shadowRun := MulDiv(Abs(FShadowOffsetX), ppi, 96);
  // The SAME padding RenderTo insets ContentRect by before either text pass.
  PreferredWidth := tw + MulDiv(S.Padding.Left + S.Padding.Right, ppi, 96) + shadowRun;
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

procedure TTyShadowLabel.TextChanged;
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

procedure TTyShadowLabel.Invalidate;
begin
  inherited Invalidate;
  { A theme switch reaches every control as a bare Invalidate (TTyStyleController broadcasts
    one to each registered control), and the new theme brings a different font and padding --
    so the width an AutoSize label needs changed too. Without re-fitting here the label keeps
    the old skin's width and the caption is clipped, which is exactly what a hand-set width
    does under the 'xp' skin. Setting ShadowOffsetX also lands here (its setter invalidates),
    which is how a changed shadow throw re-reserves its room.
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

procedure TTyShadowLabel.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  ContentRect, ShadowRect: TRect;
  fontSize, dx, dy: Integer;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    fontSize := ResolveFontSize(S);
    // Honor the style opacity (e.g. :disabled { opacity: 0.5 }) like the label does;
    // background stays transparent (no DrawFrame fill).
    if tpOpacity in S.Present then
      P.Opacity := S.Opacity;

    ContentRect := Rect(
      P.Scale(S.Padding.Left),
      P.Scale(S.Padding.Top),
      (ARect.Right - ARect.Left) - P.Scale(S.Padding.Right),
      (ARect.Bottom - ARect.Top) - P.Scale(S.Padding.Bottom)
    );

    // 1) shadow pass: same text, offset by the (scaled) shadow offset, in ShadowColor.
    dx := P.Scale(FShadowOffsetX);
    dy := P.Scale(FShadowOffsetY);
    ShadowRect := Rect(ContentRect.Left + dx, ContentRect.Top + dy,
      ContentRect.Right + dx, ContentRect.Bottom + dy);
    P.DrawText(ShadowRect, Caption, S.FontName, fontSize, S.FontWeight,
      FShadowColor, FAlignment, FLayout, False);

    // 2) main pass: caption at the normal position, in the theme text colour.
    P.DrawText(ContentRect, Caption, S.FontName, fontSize, S.FontWeight,
      S.TextColor, FAlignment, FLayout, False);

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyShadowLabel.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
