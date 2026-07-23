unit tyControls.ShadowLabel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics,
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
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
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
  Result := 'TyShadowLabel';   // reuse the label theme rules
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
