unit tyControls.Image;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, ImgList, Types, Controls, Graphics, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.ImageCollection, tyControls.ImageDraw;

type
  { A themed raster image control. Shows a TPicture (any LCL graphic — PNG/BMP/JPG,
    with alpha), or one entry of a shared TTyVirtualImageList, drawn through TTyPainter
    so it composites cleanly into the themed UI. Leaf TTyGraphicControl. Three placement
    modes mirror LCL TImage:

      * Stretch=False, Proportional=False -> the image is drawn at its native size,
        top-left (Center=False, default) or centered (Center=True).
      * Stretch=True, Proportional=False  -> the image fills the client area exactly.
      * Proportional=True                 -> an OVERSIZED image is scaled down to fit
        inside the client area preserving its aspect ratio (letterboxed); a smaller one
        keeps its native size unless Stretch is also set.

    StretchInEnabled / StretchOutEnabled gate the two scaling directions independently
    (see TyImageFitRect), and KeepOriginXWhenClipped / KeepOriginYWhenClipped bias a
    centred oversized image back to the origin instead of cropping it symmetrically.

    typeKey is 'TyImage'. When Transparent NO background is drawn; when Transparent is
    False (the default, as on TImage) the TyPanel surface is painted first via
    DrawFrame, and the flag is also pushed into Picture.Graphic.Transparent so a
    masked/keyed bitmap behaves as it does under LCL. The style opacity (e.g.
    :disabled opacity 0.5) is honored in both modes so a disabled image dims. }
  TTyImage = class(TTyGraphicControl)
  private
    FPicture: TPicture;
    FStretch: Boolean;
    FProportional: Boolean;
    FCenter: Boolean;
    FTransparent: Boolean;
    FStretchInEnabled: Boolean;
    FStretchOutEnabled: Boolean;
    FKeepOriginXWhenClipped: Boolean;
    FKeepOriginYWhenClipped: Boolean;
    FAntialiasingMode: TAntialiasingMode;
    FImages: TCustomImageList;
    FImageIndex: Integer;
    FImageWidth: Integer;
    FOnPictureChanged: TNotifyEvent;
    procedure SetPicture(AValue: TPicture);
    procedure SetStretch(AValue: Boolean);
    procedure SetProportional(AValue: Boolean);
    procedure SetCenter(AValue: Boolean);
    procedure SetTransparent(AValue: Boolean);
    procedure SetStretchInEnabled(AValue: Boolean);
    procedure SetStretchOutEnabled(AValue: Boolean);
    procedure SetKeepOriginX(AValue: Boolean);
    procedure SetKeepOriginY(AValue: Boolean);
    procedure SetAntialiasingMode(AValue: TAntialiasingMode);
    procedure SetImages(AValue: TCustomImageList);
    procedure SetImageIndex(AValue: Integer);
    procedure SetImageWidth(AValue: Integer);
    procedure ApplyTransparentToGraphic;
    procedure PictureChanged(Sender: TObject);
    function GetHasGraphic: Boolean;
    function GetImageSize: Integer;
  protected
    function GetStyleTypeKey: string; override;   // 'TyImage'
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { True when there is anything at all to draw: a picture, OR a valid entry in the
      assigned image list. LCL's TCustomImage.HasGraphic (extctrls.pp:577) — the query
      a host uses to decide whether to show a placeholder, so it does not have to reach
      into Picture.Graphic and null/Empty-check it by hand. }
    property HasGraphic: Boolean read GetHasGraphic;
    { The EDGE, in pixels, an image-list entry is rendered at: ImageWidth when set,
      otherwise the list's own DefaultSize. LCL reaches the same number through
      Images.SizeForPPI[ImageWidth, PixelsPerInch]; this collection renders one master
      to any size on demand, so the requested edge IS the answer. 0 when no list. }
    property ImageSize: Integer read GetImageSize;
  published
    property Picture: TPicture read FPicture write SetPicture;
    property Stretch: Boolean read FStretch write SetStretch default False;
    property Proportional: Boolean read FProportional write SetProportional default False;
    { LCL default. BREAKING vs 3.0-alpha, which defaulted to True: a .lfm converted from
      TImage carries no Center= line (it equalled TImage's default), so every
      non-stretched picture silently moved to the middle of the control. Forms that WANT
      centring must now say so — which is also what makes them portable back. }
    property Center: Boolean read FCenter write SetCenter default False;
    { LCL default. BREAKING vs 3.0-alpha, which defaulted to True. }
    property Transparent: Boolean read FTransparent write SetTransparent default False;
    { Gate on ENLARGING ("stretch the picture OUT to fill a larger control"). With it
      False a picture smaller than the control is never scaled up, whatever Stretch and
      Proportional say. }
    property StretchOutEnabled: Boolean read FStretchOutEnabled
      write SetStretchOutEnabled default True;
    { Gate on SHRINKING ("stretch the picture IN to fit a smaller control"). With it
      False an oversized picture is drawn 1:1 and clips. Combined with the one above,
      this is how "shrink big photos, never enlarge small ones" is expressed. }
    property StretchInEnabled: Boolean read FStretchInEnabled
      write SetStretchInEnabled default True;
    { When Center is on and the picture is BIGGER than the control, centring pushes the
      origin negative and cuts off the top/left. These pin that axis at 0 instead, so the
      top-left corner of an oversized map / screenshot / scan stays visible. }
    property KeepOriginXWhenClipped: Boolean read FKeepOriginXWhenClipped
      write SetKeepOriginX default False;
    property KeepOriginYWhenClipped: Boolean read FKeepOriginYWhenClipped
      write SetKeepOriginY default False;
    { Scaling quality, as LCL's TCustomImage.AntialiasingMode (which it pushes into
      Canvas.AntialiasingMode before StretchDraw).

      amDontCare (the default) leaves the existing path alone, so no existing form
      changes. amOff states that hard pixel-repeating edges are REQUIRED — pixel art,
      QR codes, sprite sheets. amOn requires an interpolating resample.

      Worth knowing which half of this was actually missing. The audit's premise was
      that our scaled draw always interpolates and so blurred pixel art; measured, that
      is false — BGRA's StretchPutImage repeats and drops whole pixels, and an explicit
      rmSimpleStretch resample was byte-identical to it. So amOff records a guarantee
      the current backend already meets. What genuinely could not be expressed at any
      setting is amOn: a SMOOTHED scale. }
    property AntialiasingMode: TAntialiasingMode read FAntialiasingMode
      write SetAntialiasingMode default amDontCare;
    { A shared image list to draw from instead of Picture. Picture WINS when both are
      set, exactly as in customimage.inc's DestRect/Paint. A FreeNotification nils the
      reference if the list is freed first. }
    property Images: TCustomImageList read FImages write SetImages;
    { Which entry of Images to show. LCL's default is 0; ours is -1 because ours is a
      NAME-keyed list whose Names may legitimately be empty at design time, and -1 is
      already this library's "no icon" sentinel everywhere else (HasGraphic reads it
      the same way LCL's GetHasGraphic does: ImageIndex >= 0). }
    property ImageIndex: Integer read FImageIndex write SetImageIndex default -1;
    { The pixel EDGE to render the list entry at; 0 = the list's DefaultSize. LCL uses
      it to pick which authored resolution to serve; this collection resamples one
      master, so it is simply the requested size. }
    property ImageWidth: Integer read FImageWidth write SetImageWidth default 0;
    { Fires whenever the picture changes — assigned, edited in place, or cleared — so a
      host can re-caption, set a dirty flag or refresh a thumbnail. TPicture.OnChange is
      claimed by the control itself (autosize depends on it), so this was the only
      seam that could exist. }
    property OnPictureChanged: TNotifyEvent read FOnPictureChanged write FOnPictureChanged;
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

  This 7-argument form is the 11-argument one below with LCL's own defaults
  (StretchIn/Out enabled, KeepOrigin off) — kept so every existing caller is untouched.

  Rules:
    * not Stretch and not Proportional -> source size, NOT scaled; centered when
      ACenter, else placed at the top-left (0,0). May overflow if larger than dest.
    * Stretch and not Proportional     -> fills the dest exactly: Rect(0,0,ADstW,ADstH).
    * Proportional                     -> an OVERSIZED source is scaled to fit WITHIN
      the dest preserving aspect (letterbox); a smaller one keeps its native size
      unless AStretch is also set. Centered when ACenter, else top-left.

  Degenerate sizes (<=0) yield an empty rect at the origin. }
function TyImageFitRect(ASrcW, ASrcH, ADstW, ADstH: Integer;
  AStretch, AProportional, ACenter: Boolean): TRect; overload;

{ The full form, mirroring LCL's TCustomImage.DestRect (customimage.inc:186-237).

    AStretchInEnabled   gate on SHRINKING an oversized picture ("stretch it IN to fit")
    AStretchOutEnabled  gate on ENLARGING a small one    ("stretch it OUT to fill")
    AKeepOriginX/Y      when centring would push the origin NEGATIVE (the picture is
                        bigger than the dest on that axis), pin it at 0 instead

  NOTE the direction of the two gates: LCL's DestRect condition is
    (StretchOutEnabled or PicOutsidePartial) and (StretchInEnabled or PicInside)
  and for a SMALL picture (PicOutsidePartial=False) that reduces to StretchOutEnabled,
  while for an OVERSIZED one (PicInside=False) it reduces to StretchInEnabled. In / out
  are named from the PICTURE's point of view, not the control's, and the audit that
  requested these had them the other way round. }
function TyImageFitRect(ASrcW, ASrcH, ADstW, ADstH: Integer;
  AStretch, AProportional, ACenter: Boolean;
  AStretchInEnabled, AStretchOutEnabled,
  AKeepOriginX, AKeepOriginY: Boolean): TRect; overload;

implementation

function TyImageFitRect(ASrcW, ASrcH, ADstW, ADstH: Integer;
  AStretch, AProportional, ACenter: Boolean): TRect;
begin
  Result := TyImageFitRect(ASrcW, ASrcH, ADstW, ADstH, AStretch, AProportional,
    ACenter, True, True, False, False);
end;

function TyImageFitRect(ASrcW, ASrcH, ADstW, ADstH: Integer;
  AStretch, AProportional, ACenter: Boolean;
  AStretchInEnabled, AStretchOutEnabled,
  AKeepOriginX, AKeepOriginY: Boolean): TRect;
var
  w, h, ox, oy: Integer;
  scW, scH, sc: Double;
  PicInside, PicOutsidePartial, DoScale: Boolean;
begin
  if (ASrcW <= 0) or (ASrcH <= 0) or (ADstW <= 0) or (ADstH <= 0) then
    Exit(Rect(0, 0, 0, 0));

  PicInside := (ASrcW < ADstW) and (ASrcH < ADstH);
  PicOutsidePartial := (ASrcW > ADstW) or (ASrcH > ADstH);

  { customimage.inc's two-line condition, kept in its own shape so it can be read
    against the original. Proportional ALONE only ever shrinks: it used to scale up as
    well, so a 16x16 icon dropped on a 200x200 image control was blown up to 200x200 and
    looked like a bug in the icon rather than a property doing what it said. }
  DoScale := (AStretch or (AProportional and PicOutsidePartial))
    and (AStretchOutEnabled or PicOutsidePartial)
    and (AStretchInEnabled or PicInside);

  if not DoScale then
  begin
    // Native (unscaled) source size.
    w := ASrcW;
    h := ASrcH;
  end
  else if AProportional then
  begin
    // Contain: fit within the dest, preserving aspect.
    scW := ADstW / ASrcW;
    scH := ADstH / ASrcH;
    if scW < scH then sc := scW else sc := scH;
    w := Round(ASrcW * sc);
    h := Round(ASrcH * sc);
    if w < 1 then w := 1;
    if h < 1 then h := 1;
  end
  else
  begin
    // Fill the dest exactly.
    w := ADstW;
    h := ADstH;
  end;

  ox := 0;
  oy := 0;
  if ACenter then
  begin
    ox := (ADstW - w) div 2;
    oy := (ADstH - h) div 2;
    // Only a NEGATIVE offset is pinned. A picture that fits stays centred, or the flag
    // would quietly become "top-left align" (customimage.inc:234-235).
    if AKeepOriginX and (ox < 0) then ox := 0;
    if AKeepOriginY and (oy < 0) then oy := 0;
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
  FCenter := False;          // LCL's default; see the property's declaration
  FTransparent := False;     // LCL's default
  FStretchInEnabled := True;
  FStretchOutEnabled := True;
  FKeepOriginXWhenClipped := False;
  FKeepOriginYWhenClipped := False;
  FAntialiasingMode := amDontCare;
  FImageIndex := -1;
  FImageWidth := 0;
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
  ApplyTransparentToGraphic;
  Invalidate;
end;

procedure TTyImage.SetStretchInEnabled(AValue: Boolean);
begin
  if FStretchInEnabled = AValue then Exit;
  FStretchInEnabled := AValue;
  InvalidatePreferredSize;
  Invalidate;
end;

procedure TTyImage.SetStretchOutEnabled(AValue: Boolean);
begin
  if FStretchOutEnabled = AValue then Exit;
  FStretchOutEnabled := AValue;
  InvalidatePreferredSize;
  Invalidate;
end;

procedure TTyImage.SetKeepOriginX(AValue: Boolean);
begin
  if FKeepOriginXWhenClipped = AValue then Exit;
  FKeepOriginXWhenClipped := AValue;
  Invalidate;
end;

procedure TTyImage.SetKeepOriginY(AValue: Boolean);
begin
  if FKeepOriginYWhenClipped = AValue then Exit;
  FKeepOriginYWhenClipped := AValue;
  Invalidate;
end;

procedure TTyImage.SetAntialiasingMode(AValue: TAntialiasingMode);
begin
  if FAntialiasingMode = AValue then Exit;
  FAntialiasingMode := AValue;
  Invalidate;
end;

procedure TTyImage.SetImages(AValue: TCustomImageList);
begin
  if FImages = AValue then Exit;
  // FreeNotification, or a list living on another form (or with Owner = nil) would be
  // freed without a word and leave a dangling reference the next paint dereferences.
  if FImages <> nil then FImages.RemoveFreeNotification(Self);
  FImages := AValue;
  if FImages <> nil then FImages.FreeNotification(Self);
  InvalidatePreferredSize;
  if AutoSize then AdjustSize;
  Invalidate;
end;

procedure TTyImage.SetImageIndex(AValue: Integer);
begin
  if FImageIndex = AValue then Exit;
  FImageIndex := AValue;
  // customimage.inc SetImageIndex repaints: a setter that only stored the field would
  // leave the previous icon on screen until something unrelated invalidated us.
  InvalidatePreferredSize;
  if AutoSize then AdjustSize;
  Invalidate;
end;

procedure TTyImage.SetImageWidth(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FImageWidth = AValue then Exit;
  FImageWidth := AValue;
  InvalidatePreferredSize;
  if AutoSize then AdjustSize;
  Invalidate;
end;

procedure TTyImage.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FImages) then
  begin
    FImages := nil;
    Invalidate;
  end;
end;

function TTyImage.GetImageSize: Integer;
begin
  if FImages = nil then Exit(0);
  if FImageWidth > 0 then
    Result := FImageWidth
  else
    Result := FImages.Width;
  if Result < 1 then Result := 1;
end;

function TTyImage.GetHasGraphic: Boolean;
begin
  // customimage.inc:270-273 — a picture, OR a list plus a usable index. Ours adds the
  // upper bound because the list is name-keyed and an index past Names.Count renders a
  // blank square rather than raising, which would otherwise read as "has a graphic".
  Result := (FPicture.Graphic <> nil) and not FPicture.Graphic.Empty;
  if Result then Exit;
  Result := (FImages <> nil) and (FImageIndex >= 0)
    and (FImageIndex < TyImageCount(FImages));
end;

{ On LCL, Transparent means "honour the GRAPHIC's own mask / transparent colour" and is
  pushed into Picture.Graphic.Transparent. Here it only ever meant "skip the panel surface
  so what is behind shows through", so a bitmap with a real mask was drawn opaque however
  the property was set -- the one thing a reader of the LCL docs would expect it to do.
  It now does both: the surface behaviour it always had, and the graphic's mask. }
procedure TTyImage.ApplyTransparentToGraphic;
begin
  if (FPicture <> nil) and (FPicture.Graphic <> nil) then
    FPicture.Graphic.Transparent := FTransparent;
end;

procedure TTyImage.PictureChanged(Sender: TObject);
begin
  { A new graphic arrives without knowing what Transparent is set to. }
  ApplyTransparentToGraphic;
  if AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
  Invalidate;
  { LAST, and after the control has finished reacting: the handler is app code and may
    well read Width/Height or force a repaint of its own. }
  if Assigned(FOnPictureChanged) then FOnPictureChanged(Self);
end;

procedure TTyImage.CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
  WithThemeSpace: Boolean);
var
  sz: Integer;
begin
  // AutoSize tracks the native picture size (LCL TImage idiom), falling back to the
  // image list's size when there is no picture — customimage.inc:256-260 does the same
  // with Images.SizeForPPI. Nothing to draw -> leave the current bounds (0,0 asks LCL
  // to keep them).
  if (FPicture.Graphic <> nil) and not FPicture.Graphic.Empty then
  begin
    PreferredWidth := FPicture.Width;
    PreferredHeight := FPicture.Height;
    Exit;
  end;
  PreferredWidth := 0;
  PreferredHeight := 0;
  if (FImages <> nil) and (FImageIndex >= 0) and (FImageIndex < TyImageCount(FImages)) then
  begin
    sz := GetImageSize;
    PreferredWidth := sz;
    PreferredHeight := sz;   // the collection renders into a square
  end;
end;

procedure TTyImage.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  ClientR, FitR: TRect;
  src, scaled: TBGRABitmap;
  tmp: TBitmap;
  cw, ch: Integer;
  hasPic: Boolean;
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

    // Nothing to draw — headless-safe (never dereferences a nil graphic, never blits a
    // zero-size bitmap). Picture WINS over the image list, as in customimage.inc's Paint.
    hasPic := (FPicture.Graphic <> nil) and not FPicture.Graphic.Empty
      and (FPicture.Width > 0) and (FPicture.Height > 0);
    if not (hasPic or HasGraphic) then
    begin
      { An empty image control drew NOTHING, which at design time means an invisible
        control: nothing to see, nothing to click, nothing to drag. LCL outlines an empty
        TImage for exactly this reason. Design time only -- at run time an empty image
        must stay invisible, because a placeholder frame in a shipped app is a defect. }
      if csDesigning in ComponentState then
        P.StrokeBorder(ClientR, 0, 1, TyRGBA(128, 128, 128, 160));
      P.EndPaint;
      Exit;
    end;

    cw := ClientR.Right - ClientR.Left;
    ch := ClientR.Bottom - ClientR.Top;

    // Build a BGRA bitmap from the source. For a picture, BGRABitmap has no
    // Create(TGraphic) overload, so bridge through a TBitmap (TBitmap.Assign accepts any
    // raster TGraphic — PNG/BMP/JPG). For the image list, the collection renders the
    // named master to the requested edge and hands back an owned copy.
    src := nil;
    tmp := nil;
    try
      if hasPic then
      begin
        tmp := TBitmap.Create;
        tmp.Assign(FPicture.Graphic);
        src := TBGRABitmap.Create(tmp);
      end
      else
        src := TyRenderImage(FImages, FImageIndex, GetImageSize, APPI, False);
      if (src = nil) or (src.Width <= 0) or (src.Height <= 0) then
      begin
        P.EndPaint;
        Exit;
      end;

      FitR := TyImageFitRect(src.Width, src.Height, cw, ch,
        FStretch, FProportional, FCenter,
        FStretchInEnabled, FStretchOutEnabled,
        FKeepOriginXWhenClipped, FKeepOriginYWhenClipped);
      if (FitR.Right <= FitR.Left) or (FitR.Bottom <= FitR.Top) then
      begin
        P.EndPaint;
        Exit;
      end;

      if ((FitR.Right - FitR.Left) = src.Width)
         and ((FitR.Bottom - FitR.Top) = src.Height) then
        P.Bitmap.PutImage(FitR.Left, FitR.Top, src, dmDrawWithTransparency)
      else if FAntialiasingMode = amOn then
      begin
        { The one mode that needed a second path. rmFineResample runs the source through
          an interpolating filter, which is what a downscaled photo or an enlarged logo
          wants and what nothing here could previously ask for.

          amOff is NOT a branch, deliberately: BGRA's StretchPutImage already repeats and
          drops whole pixels rather than blending them, and a resample through
          rmSimpleStretch was measured byte-for-byte identical to it on this path. Two
          spellings of the same output is a branch no test can tell apart, so amOff
          documents the default's guarantee instead of duplicating it. If a future BGRA
          starts interpolating here, this is where amOff grows its own resample. }
        src.ResampleFilter := rfLinear;
        scaled := src.Resample(FitR.Right - FitR.Left, FitR.Bottom - FitR.Top,
          rmFineResample) as TBGRABitmap;
        try
          P.Bitmap.PutImage(FitR.Left, FitR.Top, scaled, dmDrawWithTransparency);
        finally
          scaled.Free;
        end;
      end
      else
        // amDontCare (the default) and amOff: the path every form has always used, which
        // is already pixel-repeating. See above for why amOff does not fork.
        P.Bitmap.StretchPutImage(FitR, src, dmDrawWithTransparency);
    finally
      src.Free;
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
