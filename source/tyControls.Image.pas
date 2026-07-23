unit tyControls.Image;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base;

type
  { A themed raster image control. Shows a TPicture (any LCL graphic — PNG/BMP/JPG,
    with alpha) drawn through TTyPainter so it composites cleanly into the themed UI.
    Leaf TTyGraphicControl. Three placement modes mirror LCL TImage:

      * Stretch=False, Proportional=False -> the image is drawn at its native size,
        centered (Center=True, default) or top-left (Center=False).
      * Stretch=True, Proportional=False  -> the image fills the client area exactly.
      * Proportional=True                 -> the image is scaled to fit inside the
        client area preserving its aspect ratio (letterboxed), centered when Center.

    typeKey is 'TyPanel' (REUSED — no new .tycss rule). When Transparent (default)
    NO background is drawn; when Transparent=False the TyPanel surface is painted
    first via DrawFrame. The style opacity (e.g. :disabled opacity 0.5) is
    honored in both modes so a disabled image dims. }
  TTyImage = class(TTyGraphicControl)
  private
    FPicture: TPicture;
    FStretch: Boolean;
    FProportional: Boolean;
    FCenter: Boolean;
    FTransparent: Boolean;
    procedure SetPicture(AValue: TPicture);
    procedure SetStretch(AValue: Boolean);
    procedure SetProportional(AValue: Boolean);
    procedure SetCenter(AValue: Boolean);
    procedure SetTransparent(AValue: Boolean);
    procedure PictureChanged(Sender: TObject);
  protected
    function GetStyleTypeKey: string; override;   // 'TyPanel' -- reuse panel surface
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Picture: TPicture read FPicture write SetPicture;
    property Stretch: Boolean read FStretch write SetStretch default False;
    property Proportional: Boolean read FProportional write SetProportional default False;
    property Center: Boolean read FCenter write SetCenter default True;
    property Transparent: Boolean read FTransparent write SetTransparent default True;
    property Enabled;
    property AutoSize;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property OnClick;
  end;

{ Pure fit-math helper (module-level, unit-tested). Computes where the image is drawn
  inside a destination area, in destination client coordinates.

    ASrcW/ASrcH  source image size (px)
    ADstW/ADstH  destination client size (px)
    AStretch/AProportional/ACenter  placement flags (as the like-named properties)

  Rules:
    * not Stretch and not Proportional -> source size, NOT scaled; centered when
      ACenter, else placed at the top-left (0,0). May overflow if larger than dest.
    * Stretch and not Proportional     -> fills the dest exactly: Rect(0,0,ADstW,ADstH).
    * Proportional (Stretch ignored)   -> scaled to fit WITHIN the dest preserving
      aspect (letterbox); centered when ACenter, else top-left.

  Degenerate sizes (<=0) yield an empty rect at the origin. }
function TyImageFitRect(ASrcW, ASrcH, ADstW, ADstH: Integer;
  AStretch, AProportional, ACenter: Boolean): TRect;

implementation

function TyImageFitRect(ASrcW, ASrcH, ADstW, ADstH: Integer;
  AStretch, AProportional, ACenter: Boolean): TRect;
var
  w, h, ox, oy: Integer;
  scW, scH, sc: Double;
begin
  if (ASrcW <= 0) or (ASrcH <= 0) or (ADstW <= 0) or (ADstH <= 0) then
    Exit(Rect(0, 0, 0, 0));

  if AProportional then
  begin
    // Contain: scale down/up to fit within the dest, preserving aspect.
    scW := ADstW / ASrcW;
    scH := ADstH / ASrcH;
    if scW < scH then sc := scW else sc := scH;
    w := Round(ASrcW * sc);
    h := Round(ASrcH * sc);
    if w < 1 then w := 1;
    if h < 1 then h := 1;
  end
  else if AStretch then
  begin
    // Fill the dest exactly.
    Result := Rect(0, 0, ADstW, ADstH);
    Exit;
  end
  else
  begin
    // Native (unscaled) source size.
    w := ASrcW;
    h := ASrcH;
  end;

  if ACenter then
  begin
    ox := (ADstW - w) div 2;
    oy := (ADstH - h) div 2;
  end
  else
  begin
    ox := 0;
    oy := 0;
  end;
  Result := Rect(ox, oy, ox + w, oy + h);
end;

constructor TTyImage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPicture := TPicture.Create;
  FPicture.OnChange := @PictureChanged;
  FStretch := False;
  FProportional := False;
  FCenter := True;
  FTransparent := True;
  SetBounds(0, 0, 90, 90);   // sensible default drop size (mirrors CharImage's ctor)
end;

destructor TTyImage.Destroy;
begin
  FPicture.OnChange := nil;
  FPicture.Free;
  inherited Destroy;
end;

function TTyImage.GetStyleTypeKey: string;
begin
  { Own key rather than the borrowed 'TyPanel': in its default transparent mode it draws no panel at all, yet a theme could only reach it through TyPanel.
    Added to 'TyPanel's rule block as an extra selector, so every resolved value is
    unchanged — this opens a hook, it does not restyle anything. }
  Result := 'TyImage';
end;

procedure TTyImage.SetPicture(AValue: TPicture);
begin
  FPicture.Assign(AValue);   // triggers OnChange -> PictureChanged
end;

procedure TTyImage.SetStretch(AValue: Boolean);
begin
  if FStretch = AValue then Exit;
  FStretch := AValue;
  Invalidate;
end;

procedure TTyImage.SetProportional(AValue: Boolean);
begin
  if FProportional = AValue then Exit;
  FProportional := AValue;
  Invalidate;
end;

procedure TTyImage.SetCenter(AValue: Boolean);
begin
  if FCenter = AValue then Exit;
  FCenter := AValue;
  Invalidate;
end;

procedure TTyImage.SetTransparent(AValue: Boolean);
begin
  if FTransparent = AValue then Exit;
  FTransparent := AValue;
  Invalidate;
end;

procedure TTyImage.PictureChanged(Sender: TObject);
begin
  if AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
  Invalidate;
end;

procedure TTyImage.CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
  WithThemeSpace: Boolean);
begin
  // AutoSize tracks the native picture size (LCL TImage idiom). No picture -> leave
  // the current bounds (0,0 asks LCL to keep them).
  if (FPicture.Graphic <> nil) and not FPicture.Graphic.Empty then
  begin
    PreferredWidth := FPicture.Width;
    PreferredHeight := FPicture.Height;
  end
  else
  begin
    PreferredWidth := 0;
    PreferredHeight := 0;
  end;
end;

procedure TTyImage.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  ClientR, FitR: TRect;
  src: TBGRABitmap;
  tmp: TBitmap;
  cw, ch: Integer;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    ClientR := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    // When opaque, paint the TyPanel surface (fill + border). When transparent
    // (default), skip the fill so whatever is behind shows through — but still honor
    // the style opacity (e.g. :disabled { opacity: 0.5 }) so a disabled image dims.
    if not FTransparent then
      DrawFrame(P, ClientR, S)
    else if tpOpacity in S.Present then
      P.Opacity := S.Opacity;

    // Nothing to draw for an empty picture — headless-safe (never dereferences a nil
    // graphic, never blits a zero-size bitmap).
    if (FPicture.Graphic = nil) or FPicture.Graphic.Empty
       or (FPicture.Width <= 0) or (FPicture.Height <= 0) then
    begin
      P.EndPaint;
      Exit;
    end;

    cw := ClientR.Right - ClientR.Left;
    ch := ClientR.Bottom - ClientR.Top;
    FitR := TyImageFitRect(FPicture.Width, FPicture.Height, cw, ch,
      FStretch, FProportional, FCenter);
    if (FitR.Right <= FitR.Left) or (FitR.Bottom <= FitR.Top) then
    begin
      P.EndPaint;
      Exit;
    end;

    // Build a BGRA bitmap from the picture's graphic and composite it into the fit
    // rect. BGRABitmap 3.2.2 has no Create(TGraphic) overload, so bridge through a
    // TBitmap (TBitmap.Assign accepts any raster TGraphic — PNG/BMP/JPG). PutImage
    // when the rect is the source's exact size (no scaling), StretchPutImage otherwise.
    tmp := TBitmap.Create;
    try
      tmp.Assign(FPicture.Graphic);
      src := TBGRABitmap.Create(tmp);
      try
        if ((FitR.Right - FitR.Left) = src.Width)
           and ((FitR.Bottom - FitR.Top) = src.Height) then
          P.Bitmap.PutImage(FitR.Left, FitR.Top, src, dmDrawWithTransparency)
        else
          P.Bitmap.StretchPutImage(FitR, src, dmDrawWithTransparency);
      finally
        src.Free;
      end;
    finally
      tmp.Free;
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyImage.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
