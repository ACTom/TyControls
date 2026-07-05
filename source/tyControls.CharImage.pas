unit tyControls.CharImage;
{$mode objfpc}{$H+}

{ TTyCharImage — a leaf graphic control that displays ONE icon-font glyph (from a
  TTyIconFont) as a centered, colored, scalable image. Think of a single vector
  icon dropped on a form: pick an IconFont, name a glyph, choose a size + color.

  It owns no font of its own — it delegates rasterization to the assigned
  TTyIconFont.RenderGlyph (which returns a caller-owned transparent BGRA bitmap),
  then composites that bitmap centered onto the painter buffer and frees it. When
  no IconFont is assigned, GlyphName is empty, or the glyph is unmapped, it simply
  draws nothing — RenderGlyph returns an empty transparent bitmap either way, so
  the paint path is always headless-safe (no font, no handle, no crash).

  Theming reuses the TyLabel selector (GetStyleTypeKey = 'TyLabel'): background is
  transparent like a label, the glyph color falls back to the resolved TextColor,
  and :disabled opacity dims the glyph exactly as a label's text dims. }

interface

uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.IconFont;

const
  { Sentinel GlyphColor meaning "use the resolved theme TextColor". A fully
    transparent value ($00000000) can never be a meaningful visible glyph color,
    so it doubles as the unambiguous "not set" marker (mirrors the alpha=0 =
    "unset" idiom used elsewhere in the library). }
  TyGlyphColorDefault = tyTransparent;

  { Default logical padding (each side) subtracted from the client box when
    GlyphSize is 0 (auto-fit). Scaled by PPI at paint time. }
  TyCharImagePad = 2;

type
  TTyCharImage = class(TTyGraphicControl)
  private
    FIconFont: TTyIconFont;
    FGlyphName: string;
    FGlyphSize: Integer;
    FGlyphColor: TTyColor;
    procedure SetIconFont(AValue: TTyIconFont);
    procedure SetGlyphName(const AValue: string);
    procedure SetGlyphSize(AValue: Integer);
    procedure SetGlyphColor(AValue: TTyColor);
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property IconFont: TTyIconFont read FIconFont write SetIconFont;
    property GlyphName: string read FGlyphName write SetGlyphName;
    { Glyph edge length in LOGICAL px (scaled by PPI). 0 = auto: fit the smaller
      client dimension minus TyCharImagePad on each side. }
    property GlyphSize: Integer read FGlyphSize write SetGlyphSize default 0;
    { Glyph fill color. TyGlyphColorDefault (the default) = use the theme's
      resolved TextColor; any other value overrides it. }
    property GlyphColor: TTyColor read FGlyphColor write SetGlyphColor default TyGlyphColorDefault;
    property Enabled;
    property Align;
    property Anchors;
    property AutoSize;
    property StyleClass;
    property Controller;
    property OnClick;
  end;

{ Pure helper: the glyph edge length (device px) for a client box of AWidthPx x
  AHeightPx, given the (already PPI-scaled) requested size and padding. When
  AScaledSize > 0 it wins; otherwise auto-fit = smaller side minus 2*APadPx,
  floored at 0. Headless-testable without any font. }
function TyCharImageGlyphPx(AWidthPx, AHeightPx, AScaledSize, APadPx: Integer): Integer;

implementation

function TyCharImageGlyphPx(AWidthPx, AHeightPx, AScaledSize, APadPx: Integer): Integer;
var
  m: Integer;
begin
  if AScaledSize > 0 then
    Exit(AScaledSize);
  // Auto-fit: shrink to the smaller client side, less padding on both edges.
  m := AWidthPx;
  if AHeightPx < m then m := AHeightPx;
  Result := m - 2 * APadPx;
  if Result < 0 then Result := 0;
end;

constructor TTyCharImage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FGlyphSize := 0;
  FGlyphColor := TyGlyphColorDefault;
  SetBounds(0, 0, 32, 32);   // sensible default drop size (mirrors TyForm's ctor)
end;

function TTyCharImage.GetStyleTypeKey: string;
begin
  // Reuse the label token — no new .tycss rule; color/opacity come from TyLabel.
  Result := 'TyLabel';
end;

procedure TTyCharImage.SetIconFont(AValue: TTyIconFont);
begin
  if FIconFont = AValue then Exit;
  if FIconFont <> nil then
    FIconFont.RemoveFreeNotification(Self);
  FIconFont := AValue;
  if FIconFont <> nil then
    FIconFont.FreeNotification(Self);
  Invalidate;
end;

procedure TTyCharImage.SetGlyphName(const AValue: string);
begin
  if FGlyphName = AValue then Exit;
  FGlyphName := AValue;
  Invalidate;
end;

procedure TTyCharImage.SetGlyphSize(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FGlyphSize = AValue then Exit;
  FGlyphSize := AValue;
  if AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
  Invalidate;
end;

procedure TTyCharImage.SetGlyphColor(AValue: TTyColor);
begin
  if FGlyphColor = AValue then Exit;
  FGlyphColor := AValue;
  Invalidate;
end;

procedure TTyCharImage.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FIconFont) then
    FIconFont := nil;
end;

procedure TTyCharImage.CalculatePreferredSize(var PreferredWidth,
  PreferredHeight: Integer; WithThemeSpace: Boolean);
var
  ppi, sz, pad: Integer;
begin
  // AutoSize is only meaningful with an explicit GlyphSize (auto-fit depends on
  // the box, which would be circular). Size to the scaled glyph + padding.
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  if FGlyphSize > 0 then
  begin
    sz := MulDiv(FGlyphSize, ppi, 96);
    pad := MulDiv(TyCharImagePad, ppi, 96);
    PreferredWidth := sz + 2 * pad;
    PreferredHeight := sz + 2 * pad;
  end
  else
    inherited CalculatePreferredSize(PreferredWidth, PreferredHeight, WithThemeSpace);
  if PreferredWidth < 1 then PreferredWidth := 1;
  if PreferredHeight < 1 then PreferredHeight := 1;
end;

procedure TTyCharImage.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  ContentRect: TRect;
  glyphPx, cw, ch, scaledSize, padPx, x, y: Integer;
  glyphCol: TTyColor;
  glyph: TBGRABitmap;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    // Transparent like a label: skip the background fill, but still honor the
    // style opacity so :disabled dims the glyph exactly as a label's text dims.
    if tpOpacity in S.Present then
      P.Opacity := S.Opacity;

    ContentRect := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    cw := ContentRect.Right - ContentRect.Left;
    ch := ContentRect.Bottom - ContentRect.Top;

    if (FIconFont <> nil) and (FGlyphName <> '') and (cw > 0) and (ch > 0) then
    begin
      scaledSize := P.Scale(FGlyphSize);   // 0 stays 0 -> auto-fit
      padPx := P.Scale(TyCharImagePad);
      glyphPx := TyCharImageGlyphPx(cw, ch, scaledSize, padPx);
      if glyphPx > 0 then
      begin
        if FGlyphColor = TyGlyphColorDefault then
          glyphCol := S.TextColor
        else
          glyphCol := FGlyphColor;
        // RenderGlyph never returns nil — an empty transparent bitmap when the
        // glyph is unmapped or the font is unset, still safe to PutImage + free.
        glyph := FIconFont.RenderGlyph(FGlyphName, glyphPx, glyphCol);
        try
          x := ContentRect.Left + (cw - glyph.Width) div 2;
          y := ContentRect.Top + (ch - glyph.Height) div 2;
          P.Bitmap.PutImage(x, y, glyph, dmDrawWithTransparency);
        finally
          glyph.Free;
        end;
      end;
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCharImage.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
