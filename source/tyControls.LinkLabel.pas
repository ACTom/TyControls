unit tyControls.LinkLabel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics,
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
    procedure SetAlignment(AValue: TAlignment);
    procedure SetLayout(AValue: TTextLayout);
    procedure SetURL(const AValue: string);
    { Effective font size: theme font-size, then control Font.Size, then a default. }
    function ResolveFontSize(const AStyle: TTyStyleSet): Integer;
    { The accent (link) colour, brightened when hovered. }
    function LinkColor: TTyColor;
  protected
    function GetStyleTypeKey: string; override;   // 'TyLabel' (reuse label theming)
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure Click; override;
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
  Result := 'TyLabel';
end;

function TTyLinkLabel.ResolveFontSize(const AStyle: TTyStyleSet): Integer;
begin
  Result := TyResolveFontSize(AStyle, ParentFont, Font.Size, ActiveController);
end;

function TTyLinkLabel.LinkColor: TTyColor;
var
  accentS: TTyStyleSet;
begin
  // Reuse the gauge fill (accent) colour so no new .tycss rule is introduced.
  accentS := ActiveController.Model.ResolveStyle('TyGaugeFill', StyleClass, []);
  Result := accentS.Background.Color;
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
