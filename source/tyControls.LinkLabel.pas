unit tyControls.LinkLabel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base;

{ Underline rect for a caption of measured pixel width AWidthPx, horizontally
  aligned per AAlign inside AContentRect and dropped AUnderlineDrop px above the
  content bottom. Clamps the width to the content width so the line never spills.
  Pure geometry -> unit-tested. }
function TyLinkUnderlineRect(const AContentRect: TRect; AWidthPx, AUnderlineDrop: Integer;
  AAlign: TAlignment): TRect;

type
  { A themed hyperlink label. Leaf TTyGraphicControl: the caption is drawn in the
    theme ACCENT colour (reused from the 'TyGaugeFill' style so no new .tycss rule
    is needed) and underlined with a 1px accent hairline spanning the measured text
    width (like the About-dialog homepage link). On hover the accent is brightened
    slightly. Clicking opens URL via OpenURL when AutoOpen and URL <> ''. Text
    colour/font come from CurrentStyle (typeKey 'TyLabel'), never hard-coded. }
  TTyLinkLabel = class(TTyGraphicControl)
  private
    FAlignment: TAlignment;
    FLayout: TTextLayout;
    FURL: string;
    FAutoOpen: Boolean;
    FRefitting: Boolean;   // guards the AutoSize re-fit in Invalidate against re-entry
    procedure SetAlignment(AValue: TAlignment);
    procedure SetLayout(AValue: TTextLayout);
    procedure SetURL(const AValue: string);
    { Effective font size: theme font-size, then control Font.Size, then a default. }
    function ResolveFontSize(const AStyle: TTyStyleSet): Integer;
    { The accent (link) colour, brightened when hovered. }
    function LinkColor: TTyColor;
  protected
    function GetStyleTypeKey: string; override;   // 'TyLabel' (reuse label theming)
    { The width the caption really needs: the measured text plus the theme's padding.
      Without it the link keeps whatever width the .lfm gave it, and a caption that outgrows
      that width -- a longer translation, a denser scale, a skin with a bigger font -- is
      clipped, taking the accent underline (which clamps to the content width) with it. A
      skin legitimately changes font and padding, which is exactly why a hand-set width
      cannot survive a skin switch. }
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    { The caption's drawn size in DEVICE px at APPI. The '&' is deliberately NOT stripped:
      RenderTo hands Caption to DrawText verbatim (this label does no mnemonic parsing -- a
      hyperlink has no Alt+key path), so an ampersand is a real glyph here and measuring it
      away would under-reserve. }
    procedure MeasureCaption(APPI: Integer; out AWidth, AHeight: Integer);
    { Caption changes at runtime route here (CM_TEXTCHANGED); with AutoSize the link must
      re-measure to the new text. }
    procedure TextChanged; override;
    { A theme switch reaches every control as a bare Invalidate, and the new theme brings a
      different font and padding -- so the width the caption needs changed too and an
      AutoSize link has to re-fit here, not merely repaint. }
    procedure Invalidate; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure Click; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    { Off by default (a designed link keeps the width the .lfm gave it). Switch it on and the
      link WIDENS to hug its caption plus the theme's padding, so a caption that grows
      lengthens the control -- and with it the accent underline -- instead of being clipped.
      Height is left alone (see CalculatePreferredSize): it belongs to whoever lays out the row. }
    property AutoSize;
    property Caption;
    property Enabled;
    property Font;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property OnClick;
    property URL: string read FURL write SetURL;
    property AutoOpen: Boolean read FAutoOpen write FAutoOpen default True;
    property Alignment: TAlignment read FAlignment write SetAlignment default taLeftJustify;
    property Layout: TTextLayout read FLayout write SetLayout default tlCenter;
  end;

implementation

uses
  LCLIntf,                       // OpenURL
  tyControls.StyleModel,         // ActiveController.Model.ResolveStyle
  tyControls.Css.Values;         // TyLighten

function TyLinkUnderlineRect(const AContentRect: TRect; AWidthPx, AUnderlineDrop: Integer;
  AAlign: TAlignment): TRect;
var
  contentW, tw, lx, uy: Integer;
begin
  contentW := AContentRect.Right - AContentRect.Left;
  tw := AWidthPx;
  if tw < 0 then tw := 0;
  if tw > contentW then tw := contentW;
  case AAlign of
    taRightJustify: lx := AContentRect.Right - tw;
    taCenter:       lx := (AContentRect.Left + AContentRect.Right - tw) div 2;
  else
    lx := AContentRect.Left;    // taLeftJustify
  end;
  uy := AContentRect.Bottom - AUnderlineDrop;
  Result := Rect(lx, uy, lx + tw, uy + 1);
end;

{ TTyLinkLabel }

constructor TTyLinkLabel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAlignment := taLeftJustify;
  FLayout := tlCenter;
  FAutoOpen := True;
  Cursor := crHandPoint;
end;

function TTyLinkLabel.GetStyleTypeKey: string;
begin
  { Own key rather than the borrowed 'TyLabel': an always-on accent underline is a mark a plain label never draws.
    Added to 'TyLabel's rule block as an extra selector, so every resolved value is
    unchanged — this opens a hook, it does not restyle anything. }
  Result := 'TyLinkLabel';
end;

function TTyLinkLabel.ResolveFontSize(const AStyle: TTyStyleSet): Integer;
begin
  Result := TyResolveFontSize(AStyle, ParentFont, Font.Size, ActiveController);
end;

function TTyLinkLabel.LinkColor: TTyColor;
var
  accentS: TTyStyleSet;
begin
  { Hyperlink ink has its own key. It used to borrow 'TyGaugeFill' to avoid adding a rule —
    which meant recolouring a gauge's fill silently recoloured every hyperlink in the app,
    and the link colour itself could not be themed at all. Same resolved value (both are
    var(--accent)), read off `color` because this is text ink, not a fill. }
  accentS := ActiveController.Model.ResolveStyle('TyLinkLabelLink', StyleClass, []);
  Result := accentS.TextColor;
  if FHover then
    Result := TyLighten(Result, 15);   // brighten slightly on hover
end;

procedure TTyLinkLabel.SetAlignment(AValue: TAlignment);
begin
  if FAlignment = AValue then Exit;
  FAlignment := AValue;
  Invalidate;
end;

procedure TTyLinkLabel.SetLayout(AValue: TTextLayout);
begin
  if FLayout = AValue then Exit;
  FLayout := AValue;
  Invalidate;
end;

procedure TTyLinkLabel.SetURL(const AValue: string);
begin
  if FURL = AValue then Exit;
  FURL := AValue;
end;

procedure TTyLinkLabel.Click;
begin
  inherited Click;   // fire OnClick first
  if FAutoOpen and (FURL <> '') then
    OpenURL(FURL);
end;

procedure TTyLinkLabel.MeasureCaption(APPI: Integer; out AWidth, AHeight: Integer);
var
  S: TTyStyleSet;
  Meas: TBitmap;
  weight: Integer;
begin
  // The same style RenderTo paints with, so what AutoSize reserves and what gets drawn
  // cannot drift when a skin changes the font family, size or weight.
  S := CurrentStyle;
  // RenderTo's own normalisation: an unset weight paints as regular, so measure it as one.
  weight := S.FontWeight;
  if weight <= 0 then weight := 400;
  Meas := TBitmap.Create;
  try
    Meas.SetSize(1, 1);
    Meas.Canvas.Font.Name := TyEffectiveFontName(S.FontName);
    Meas.Canvas.Font.Size := MulDiv(ResolveFontSize(S), APPI, 96);
    // TyConfigureTextFont (which the paint path goes through) bolds at weight >= 600.
    if weight >= 600 then
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

procedure TTyLinkLabel.CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
  WithThemeSpace: Boolean);
var
  S: TTyStyleSet;
  ppi, tw, th: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  MeasureCaption(ppi, tw, th);
  { The underline needs no slot of its own: TyLinkUnderlineRect spans the MEASURED caption
    width and clamps it to the content width, so a box that fits the text fits the hairline
    exactly. Reserving the caption width is therefore also what keeps the link's mark
    full-length -- clip the text and the underline shortens with it.
    The theme padding is added even though RenderTo lays the caption out in the FULL client
    rect (this control applies no padding inset): that can only leave slack, never cut the
    caption short, and a skin that pads TyLinkLabel still gets the roomier box it asked for. }
  PreferredWidth := tw + MulDiv(S.Padding.Left + S.Padding.Right, ppi, 96);
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

procedure TTyLinkLabel.TextChanged;
begin
  inherited TextChanged;
  // The new caption needs a different width, so an auto-sized link must re-fit.
  if AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
  Invalidate;
end;

procedure TTyLinkLabel.Invalidate;
begin
  inherited Invalidate;
  { A theme switch reaches every control as a bare Invalidate (TTyStyleController broadcasts
    one to each registered control), and the new theme brings a different font and padding --
    so the width an AutoSize link needs changed too. Without re-fitting here the link keeps
    the old skin's width and the caption is clipped, which is exactly what a hand-set width
    does under the 'xp' skin.
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

procedure TTyLinkLabel.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  ContentRect, UnderR: TRect;
  fontSize, weight, tw: Integer;
  col: TTyColor;
  fill: TTyFill;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    if tpOpacity in S.Present then
      P.Opacity := S.Opacity;   // honor :disabled { opacity: ... }
    fontSize := ResolveFontSize(S);
    weight := S.FontWeight;
    if weight <= 0 then weight := 400;
    col := LinkColor;
    ContentRect := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);

    P.DrawText(ContentRect, Caption, S.FontName, fontSize, weight, col,
      FAlignment, FLayout, False);

    // 1px accent underline spanning the measured caption width.
    if Caption <> '' then
    begin
      tw := P.MeasureText(Caption, S.FontName, fontSize, weight).cx;
      UnderR := TyLinkUnderlineRect(ContentRect, tw, P.Scale(3), FAlignment);
      if (UnderR.Right > UnderR.Left) then
      begin
        fill := Default(TTyFill);
        fill.Kind := tfkSolid;
        fill.Color := col;
        P.FillBackground(UnderR, fill, TyUniformCorners(0));
      end;
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyLinkLabel.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
