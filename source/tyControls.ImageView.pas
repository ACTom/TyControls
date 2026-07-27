unit tyControls.ImageView;
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

// TTyImageView — a themed image viewer: load a raster image, pan + zoom with
// SMOOTH animation, and apply non-destructive BGRA filters (grayscale / blur /
// sharpen / invert / tint). A windowed control (mouse pan + own paint) that
// reuses the 'TyPanel' typeKey for its mailbox surface (zero new .tycss token).
//
// ALL geometry and the filter pipeline live in the module-level PURE functions
// below so they are exercisable head-less (the window/timer/mouse path is not).

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, ExtCtrls, Math,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Animation;

type
  { TTyImageView — image viewer. FSource is the untouched decoded image; FProcessed
    is the (lazily rebuilt) filter output that is actually drawn. The view is defined
    by FZoom (display scale) plus a pan offset (FOffX/FOffY) measured in DEVICE pixels
    from the image's centered rest position. Zoom/pan changes animate over FAnimMs
    milliseconds via a lazy timer (the ExPanel pattern); drag-pan is immediate. }
  TTyImageView = class(TTyCustomControl)
  private
    { The assigned picture, KEPT. FSource is the decoded BGRA the viewer actually draws, but
      a published property must be READABLE: the Lazarus Object Inspector reads every
      published property when a form is opened, so a write-only one ('Cannot read property
      "Picture"') makes the IDE refuse the form outright — while runtime streaming never
      noticed, because it only ever WRITES the properties a .lfm names. Mirrors TTyImage. }
    FPicture:    TPicture;
    FSource:     TBGRABitmap;    // owned; original decoded image (never filtered)
    FProcessed:  TBGRABitmap;    // owned; filter output (rebuilt when FProcDirty); drawn
    FProcDirty:  Boolean;
    { view }
    FZoom:       Double;         // current display scale (interpolated while animating)
    FAutoFit:    Boolean;        // True -> ZoomToFit on load/resize; user zoom/pan clears it
    FZoomMin, FZoomMax: Double;
    FOffX, FOffY: Double;        // pan offset in device px from the centered position
    { smooth animation }
    FAnim:       TTyAnimator;
    FFromZoom, FToZoom: Double;
    FFromOffX, FFromOffY, FToOffX, FToOffY: Double;
    FTimer:      TTimer;         // lazy; only while animating
    FAnimMs:     Integer;        // duration, default 180
    { drag-pan }
    FDragging:   Boolean;
    FDragStartX, FDragStartY: Integer;
    FDragBaseOffX, FDragBaseOffY: Double;
    { filters }
    FGrayscale:  Boolean;
    FBlurRadius: Integer;        // 0 = off
    FSharpen:    Boolean;
    FInvert:     Boolean;
    FTintColor:  TColor;
    FTintAmount: Integer;        // 0..100, 0 = off
    FOnZoomChange: TNotifyEvent;
    procedure SetPicture(AValue: TPicture);
    procedure PictureChanged(Sender: TObject);
    procedure SetAutoFit(AValue: Boolean);
    procedure SetZoomMin(AValue: Double);
    procedure SetZoomMax(AValue: Double);
    procedure SetGrayscale(AValue: Boolean);
    procedure SetBlurRadius(AValue: Integer);
    procedure SetSharpen(AValue: Boolean);
    procedure SetInvert(AValue: Boolean);
    procedure SetTintColor(AValue: TColor);
    procedure SetTintAmount(AValue: Integer);
    function  ViewW: Integer;
    function  ViewH: Integer;
    procedure RebuildProcessed;
    procedure EnsureTimer;
    procedure HandleTimer(Sender: TObject);
    { Start (or restart) an animated move toward the given zoom + pan. With a window
      handle and a positive duration a timer eases; headless / zero-duration snaps. }
    procedure StartAnim(ATargetZoom, ATargetOffX, ATargetOffY: Double);
    procedure DoZoomChange;
  protected
    function GetStyleTypeKey: string; override;   // 'TyImageView' — its own key: the letterbox matte behind a photo is not the app's panel colour
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function  DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure DblClick; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadFromFile(const APath: string);   // BGRA decode; on failure clears (no crash)
    procedure AssignBitmap(ABitmap: TBGRABitmap);   // display a runtime-drawn BGRA directly (no lossy TPicture round-trip)
    procedure Clear;
    procedure ZoomToFit;                            // AutoFit:=True; animate to contain-fit
    procedure ZoomToActual;                         // 100%; animate; AutoFit:=False
    procedure ZoomIn;
    procedure ZoomOut;
    procedure ZoomAt(AFactor: Double; AX, AY: Integer);  // zoom about (AX,AY), animated
    property  Zoom: Double read FZoom;              // read-only; current (maybe animating) scale
  published
    property Picture: TPicture read FPicture write SetPicture;   // assign -> decoded to FSource
    property AutoFit: Boolean read FAutoFit write SetAutoFit default True;
    property ZoomMin: Double read FZoomMin write SetZoomMin;
    property ZoomMax: Double read FZoomMax write SetZoomMax;
    property AnimationDuration: Integer read FAnimMs write FAnimMs default 180;
    property Grayscale: Boolean read FGrayscale write SetGrayscale default False;
    property BlurRadius: Integer read FBlurRadius write SetBlurRadius default 0;
    property Sharpen: Boolean read FSharpen write SetSharpen default False;
    property Invert: Boolean read FInvert write SetInvert default False;
    property TintColor: TColor read FTintColor write SetTintColor default clNone;
    property TintAmount: Integer read FTintAmount write SetTintAmount default 0;
    property OnZoomChange: TNotifyEvent read FOnZoomChange write FOnZoomChange;
    // Declared True to match the constructor, so a host's TabStop=False opt-out streams.
    property TabStop default True;
    property Align;
    property Anchors;
    property Visible;
    property Enabled;
    property StyleClass;
    property Controller;
  end;

{ ============================ PURE, head-less-tested ============================ }

{ Contain-fit zoom: the scale that makes the whole src fit inside the view. Any
  degenerate dimension (<=0) yields 1.0. }
function TyImageViewFitZoom(ASrcW, ASrcH, AViewW, AViewH: Integer): Double;

{ Clamp AValue to [ALo,AHi]. }
function TyImageViewClamp(AValue, ALo, AHi: Double): Double;

{ Device rect the image occupies: the src scaled by AZoom, centered in the view and
  then shifted by the device-pixel pan (AOffX,AOffY). Degenerate src -> empty rect. }
function TyImageViewDestRect(ASrcW, ASrcH, AViewW, AViewH: Integer;
  AZoom, AOffX, AOffY: Double): TRect;

{ Anchor-preserving pan: given the image pixel under (AAnchorX,AAnchorY) at AOldZoom
  and pan (AOldOffX,AOldOffY), return the pan (ANewOffX,ANewOffY) that keeps that same
  image pixel under the anchor at ANewZoom. Offsets are device px from the view center
  (no src size needed — centering is symmetric about the view center). }
procedure TyImageViewAnchorOffset(AOldZoom, ANewZoom: Double;
  AAnchorX, AAnchorY, AViewW, AViewH: Integer;
  AOldOffX, AOldOffY: Double; out ANewOffX, ANewOffY: Double);

{ Clamp the pan so the image never reveals blank past the view edges: when the scaled
  image is smaller than the view on an axis it is centered (offset 0); otherwise the
  offset is limited to +/-(scaled-view)/2 so an image edge never crosses the view edge. }
procedure TyImageViewClampOffset(ASrcW, ASrcH, AViewW, AViewH: Integer;
  AZoom: Double; var AOffX, AOffY: Double);

{ Non-destructive filter pipeline. Returns a NEW caller-owned bitmap; ASource is left
  untouched. Order: grayscale -> blur -> sharpen -> invert -> tint. All filters off ->
  a plain copy of ASource. Every intermediate bitmap is freed. nil source -> nil. }
function TyImageViewApplyFilters(ASource: TBGRABitmap; AGrayscale: Boolean;
  ABlurRadius: Integer; ASharpen, AInvert: Boolean;
  ATintColor: TColor; ATintAmount: Integer): TBGRABitmap;

implementation

{ ---------------------------- pure functions ---------------------------- }

function TyImageViewFitZoom(ASrcW, ASrcH, AViewW, AViewH: Integer): Double;
var
  zx, zy: Double;
begin
  if (ASrcW <= 0) or (ASrcH <= 0) or (AViewW <= 0) or (AViewH <= 0) then
    Exit(1.0);
  zx := AViewW / ASrcW;
  zy := AViewH / ASrcH;
  if zx < zy then Result := zx else Result := zy;
end;

function TyImageViewClamp(AValue, ALo, AHi: Double): Double;
begin
  if AValue < ALo then Result := ALo
  else if AValue > AHi then Result := AHi
  else Result := AValue;
end;

function TyImageViewDestRect(ASrcW, ASrcH, AViewW, AViewH: Integer;
  AZoom, AOffX, AOffY: Double): TRect;
var
  sw, sh, lx, ty: Integer;
begin
  if (ASrcW <= 0) or (ASrcH <= 0) then Exit(Rect(0, 0, 0, 0));
  sw := Round(ASrcW * AZoom);
  sh := Round(ASrcH * AZoom);
  if sw < 1 then sw := 1;
  if sh < 1 then sh := 1;
  lx := Round((AViewW - sw) / 2 + AOffX);
  ty := Round((AViewH - sh) / 2 + AOffY);
  Result := Rect(lx, ty, lx + sw, ty + sh);
end;

procedure TyImageViewAnchorOffset(AOldZoom, ANewZoom: Double;
  AAnchorX, AAnchorY, AViewW, AViewH: Integer;
  AOldOffX, AOldOffY: Double; out ANewOffX, ANewOffY: Double);
var
  cx, cy, ux, uy: Double;
begin
  ANewOffX := AOldOffX;
  ANewOffY := AOldOffY;
  if AOldZoom <= 0 then Exit;
  cx := AViewW / 2;
  cy := AViewH / 2;
  // Image-relative coordinate (in image px, from the image center) under the anchor.
  ux := (AAnchorX - cx - AOldOffX) / AOldZoom;
  uy := (AAnchorY - cy - AOldOffY) / AOldZoom;
  // Solve for the pan that keeps that same coordinate under the anchor at the new zoom.
  ANewOffX := AAnchorX - cx - ux * ANewZoom;
  ANewOffY := AAnchorY - cy - uy * ANewZoom;
end;

procedure TyImageViewClampOffset(ASrcW, ASrcH, AViewW, AViewH: Integer;
  AZoom: Double; var AOffX, AOffY: Double);
var
  sw, sh, lx, ly: Double;
begin
  sw := ASrcW * AZoom;
  sh := ASrcH * AZoom;
  if sw <= AViewW then
    AOffX := 0
  else
  begin
    lx := (sw - AViewW) / 2;
    if AOffX < -lx then AOffX := -lx
    else if AOffX > lx then AOffX := lx;
  end;
  if sh <= AViewH then
    AOffY := 0
  else
  begin
    ly := (sh - AViewH) / 2;
    if AOffY < -ly then AOffY := -ly
    else if AOffY > ly then AOffY := ly;
  end;
end;

function TyImageViewApplyFilters(ASource: TBGRABitmap; AGrayscale: Boolean;
  ABlurRadius: Integer; ASharpen, AInvert: Boolean;
  ATintColor: TColor; ATintAmount: Integer): TBGRABitmap;
var
  cur, nxt: TBGRABitmap;
  amt: Integer;
  tintPix: TBGRAPixel;
begin
  if ASource = nil then Exit(nil);
  // Start from an owned copy — the all-off result and the base for each filter stage.
  cur := ASource.Duplicate(True) as TBGRABitmap;
  if AGrayscale then
  begin
    nxt := cur.FilterGrayscale as TBGRABitmap;   // returns a NEW bitmap
    cur.Free; cur := nxt;
  end;
  if ABlurRadius > 0 then
  begin
    nxt := cur.FilterBlurRadial(ABlurRadius, rbFast) as TBGRABitmap;
    cur.Free; cur := nxt;
  end;
  if ASharpen then
  begin
    nxt := cur.FilterSharpen(1) as TBGRABitmap;
    cur.Free; cur := nxt;
  end;
  if AInvert then
    cur.LinearNegative;   // in-place, straight per-channel complement (255-x), the
                          // expected "invert" -- NOT .Negative (a gamma-aware photographic
                          // negative that inverts in linear light: invert(10) -> 254 not 245)
  amt := ATintAmount;
  if amt < 0 then amt := 0
  else if amt > 100 then amt := 100;
  if amt > 0 then
  begin
    // Overlay the tint colour at an alpha derived from the amount (100 -> fully opaque
    // -> replaces every pixel with the tint colour).
    tintPix := ColorToBGRA(ColorToRGB(ATintColor), Byte(Round(255 * amt / 100)));
    cur.FillRect(0, 0, cur.Width, cur.Height, tintPix, dmDrawWithTransparency);
  end;
  Result := cur;
end;

{ ------------------------------ TTyImageView ------------------------------ }

constructor TTyImageView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FZoom := 1.0;
  FAutoFit := True;
  FZoomMin := 0.05;
  FZoomMax := 20.0;
  FAnimMs := 180;
  FTintColor := clNone;
  FProcDirty := True;
  FPicture := TPicture.Create;
  FPicture.OnChange := @PictureChanged;
  FAnim := TyAnimatorInit(FAnimMs, teEaseOutCubic);
  FAnim.SetTargetImmediate(1);   // settled (not mid-animation)
  // A viewer is operated, not just looked at: drag pans it and the wheel zooms it. The
  // click that starts a pan must therefore move focus here (TTyCustomControl.MouseDown
  // gates that on TabStop) — on Windows the wheel notification goes to the FOCUSED window,
  // so a viewer that can never hold focus is also a viewer the wheel can miss.
  TabStop := True;
  SetBounds(0, 0, 320, 240);
end;

destructor TTyImageView.Destroy;
begin
  FreeAndNil(FTimer);   // free the timer first so its callback can't fire mid-teardown
  FPicture.OnChange := nil;   // ...and detach the hook before it can fire mid-teardown
  FreeAndNil(FPicture);
  FreeAndNil(FSource);
  FreeAndNil(FProcessed);
  inherited Destroy;
end;

function TTyImageView.GetStyleTypeKey: string;
begin
  { Own key rather than the borrowed 'TyPanel': the letterbox matte behind a photo is not the app's panel colour.
    Added to 'TyPanel's rule block as an extra selector, so every resolved value is
    unchanged — this opens a hook, it does not restyle anything. }
  Result := 'TyImageView';
end;

function TTyImageView.ViewW: Integer;
begin
  Result := ClientWidth;
end;

function TTyImageView.ViewH: Integer;
begin
  Result := ClientHeight;
end;

procedure TTyImageView.RebuildProcessed;
begin
  FreeAndNil(FProcessed);
  if FSource <> nil then
    FProcessed := TyImageViewApplyFilters(FSource, FGrayscale, FBlurRadius,
      FSharpen, FInvert, FTintColor, FTintAmount);
  FProcDirty := False;
end;

procedure TTyImageView.EnsureTimer;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(Self);
    FTimer.Enabled := False;
    FTimer.Interval := 16;   // ~60fps
    FTimer.OnTimer := @HandleTimer;
  end;
end;

procedure TTyImageView.HandleTimer(Sender: TObject);
var
  t: Single;
begin
  FAnim.Advance(FTimer.Interval);
  t := FAnim.Eased;
  FZoom := TyLerpF(FFromZoom, FToZoom, t);
  FOffX := TyLerpF(FFromOffX, FToOffX, t);
  FOffY := TyLerpF(FFromOffY, FToOffY, t);
  Invalidate;
  DoZoomChange;
  if not FAnim.Running then
    FTimer.Enabled := False;
end;

procedure TTyImageView.StartAnim(ATargetZoom, ATargetOffX, ATargetOffY: Double);
begin
  FFromZoom := FZoom;
  FToZoom := ATargetZoom;
  FFromOffX := FOffX;
  FFromOffY := FOffY;
  FToOffX := ATargetOffX;
  FToOffY := ATargetOffY;
  FAnim.DurationMs := FAnimMs;
  if HandleAllocated and (FAnimMs > 0)
     and ((FToZoom <> FZoom) or (FToOffX <> FOffX) or (FToOffY <> FOffY)) then
  begin
    FAnim.Progress := 0;
    FAnim.Target := 1;
    EnsureTimer;
    FTimer.Enabled := True;
  end
  else
  begin
    // Headless / zero-duration / no change: snap so the geometry settles immediately.
    FAnim.SetTargetImmediate(1);
    FZoom := ATargetZoom;
    FOffX := ATargetOffX;
    FOffY := ATargetOffY;
    Invalidate;
    DoZoomChange;
  end;
end;

procedure TTyImageView.DoZoomChange;
begin
  if Assigned(FOnZoomChange) then FOnZoomChange(Self);
end;

procedure TTyImageView.SetPicture(AValue: TPicture);
begin
  FPicture.Assign(AValue);   // triggers OnChange -> PictureChanged, which re-decodes
end;

{ The picture changed — either assigned wholesale or edited in place through the property
  (the designer does the latter). Re-decode FSource from it. }
procedure TTyImageView.PictureChanged(Sender: TObject);
var
  tmp: TBitmap;
begin
  FreeAndNil(FSource);
  if (FPicture.Graphic <> nil) and not FPicture.Graphic.Empty then
  begin
    // BGRABitmap 3.2.2 has no Create(TGraphic); bridge through a TBitmap (mirrors TTyImage).
    tmp := TBitmap.Create;
    try
      tmp.Assign(FPicture.Graphic);
      FSource := TBGRABitmap.Create(tmp);
    finally
      tmp.Free;
    end;
  end;
  FProcDirty := True;
  if FAutoFit then
    ZoomToFit
  else
    Invalidate;
end;

procedure TTyImageView.LoadFromFile(const APath: string);
var
  bmp: TBGRABitmap;
begin
  bmp := nil;
  try
    bmp := TBGRABitmap.Create(APath);
  except
    FreeAndNil(bmp);
  end;
  if bmp = nil then
  begin
    Clear;
    Exit;
  end;
  FreeAndNil(FSource);
  FSource := bmp;
  FProcDirty := True;
  if FAutoFit then
    ZoomToFit
  else
    Invalidate;
end;

{ Display a bitmap generated at runtime. Bridging a TBGRABitmap out through
  TPicture/TBitmap (MakeBitmapCopy) can drop an opaque generated image to
  all-black, so a host that DREW its own content hands the BGRA here instead --
  same FSource path LoadFromFile uses, which is known to render. The view keeps
  a private copy; ownership of ABitmap stays with the caller. }
procedure TTyImageView.AssignBitmap(ABitmap: TBGRABitmap);
begin
  FreeAndNil(FSource);
  if (ABitmap <> nil) and (ABitmap.Width > 0) and (ABitmap.Height > 0) then
    FSource := ABitmap.Duplicate(True) as TBGRABitmap;
  FProcDirty := True;
  if FAutoFit then
    ZoomToFit
  else
    Invalidate;
end;

procedure TTyImageView.Clear;
begin
  FreeAndNil(FSource);
  FreeAndNil(FProcessed);
  FProcDirty := True;
  FZoom := 1.0;
  FOffX := 0;
  FOffY := 0;
  if FTimer <> nil then FTimer.Enabled := False;
  Invalidate;
end;

procedure TTyImageView.ZoomToFit;
var
  z: Double;
begin
  FAutoFit := True;
  if FSource = nil then Exit;
  z := TyImageViewFitZoom(FSource.Width, FSource.Height, ViewW, ViewH);
  z := TyImageViewClamp(z, FZoomMin, FZoomMax);
  StartAnim(z, 0, 0);   // fit is centered
end;

procedure TTyImageView.ZoomToActual;
var
  ox, oy: Double;
begin
  FAutoFit := False;
  if FSource = nil then Exit;
  ox := FOffX; oy := FOffY;
  TyImageViewClampOffset(FSource.Width, FSource.Height, ViewW, ViewH, 1.0, ox, oy);
  StartAnim(1.0, ox, oy);
end;

procedure TTyImageView.ZoomIn;
begin
  ZoomAt(1.25, ViewW div 2, ViewH div 2);
end;

procedure TTyImageView.ZoomOut;
begin
  ZoomAt(1.0 / 1.25, ViewW div 2, ViewH div 2);
end;

procedure TTyImageView.ZoomAt(AFactor: Double; AX, AY: Integer);
var
  newZoom, nox, noy: Double;
begin
  FAutoFit := False;
  if FSource = nil then Exit;
  newZoom := TyImageViewClamp(FZoom * AFactor, FZoomMin, FZoomMax);
  TyImageViewAnchorOffset(FZoom, newZoom, AX, AY, ViewW, ViewH, FOffX, FOffY, nox, noy);
  TyImageViewClampOffset(FSource.Width, FSource.Height, ViewW, ViewH, newZoom, nox, noy);
  StartAnim(newZoom, nox, noy);
end;

procedure TTyImageView.SetAutoFit(AValue: Boolean);
begin
  if FAutoFit = AValue then Exit;
  FAutoFit := AValue;
  if FAutoFit then ZoomToFit;
end;

procedure TTyImageView.SetZoomMin(AValue: Double);
begin
  if AValue <= 0 then AValue := 0.01;
  if FZoomMin = AValue then Exit;
  FZoomMin := AValue;
end;

procedure TTyImageView.SetZoomMax(AValue: Double);
begin
  if AValue <= 0 then AValue := 0.01;
  if FZoomMax = AValue then Exit;
  FZoomMax := AValue;
end;

procedure TTyImageView.SetGrayscale(AValue: Boolean);
begin
  if FGrayscale = AValue then Exit;
  FGrayscale := AValue;
  FProcDirty := True;
  Invalidate;
end;

procedure TTyImageView.SetBlurRadius(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FBlurRadius = AValue then Exit;
  FBlurRadius := AValue;
  FProcDirty := True;
  Invalidate;
end;

procedure TTyImageView.SetSharpen(AValue: Boolean);
begin
  if FSharpen = AValue then Exit;
  FSharpen := AValue;
  FProcDirty := True;
  Invalidate;
end;

procedure TTyImageView.SetInvert(AValue: Boolean);
begin
  if FInvert = AValue then Exit;
  FInvert := AValue;
  FProcDirty := True;
  Invalidate;
end;

procedure TTyImageView.SetTintColor(AValue: TColor);
begin
  if FTintColor = AValue then Exit;
  FTintColor := AValue;
  FProcDirty := True;
  Invalidate;
end;

procedure TTyImageView.SetTintAmount(AValue: Integer);
begin
  if AValue < 0 then AValue := 0
  else if AValue > 100 then AValue := 100;
  if FTintAmount = AValue then Exit;
  FTintAmount := AValue;
  FProcDirty := True;
  Invalidate;
end;

procedure TTyImageView.Resize;
begin
  inherited Resize;
  // Track the window while auto-fitting (immediate, not animated).
  if FAutoFit and (FSource <> nil) then
  begin
    if FTimer <> nil then FTimer.Enabled := False;
    FZoom := TyImageViewClamp(
      TyImageViewFitZoom(FSource.Width, FSource.Height, ViewW, ViewH),
      FZoomMin, FZoomMax);
    FOffX := 0;
    FOffY := 0;
    Invalidate;
  end;
end;

procedure TTyImageView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (Button = mbLeft) and Enabled and (FSource <> nil) then
  begin
    FDragging := True;
    FDragStartX := X;
    FDragStartY := Y;
    FDragBaseOffX := FOffX;
    FDragBaseOffY := FOffY;
  end;
end;

procedure TTyImageView.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FDragging and (FSource <> nil) then
  begin
    // Immediate (non-animated) pan following the cursor; stop any in-flight zoom anim.
    if FTimer <> nil then FTimer.Enabled := False;
    FAutoFit := False;
    FOffX := FDragBaseOffX + (X - FDragStartX);
    FOffY := FDragBaseOffY + (Y - FDragStartY);
    TyImageViewClampOffset(FSource.Width, FSource.Height, ViewW, ViewH, FZoom, FOffX, FOffY);
    Invalidate;
  end;
end;

procedure TTyImageView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
    FDragging := False;
end;

function TTyImageView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  p: TPoint;
  factor: Double;
begin
  if FSource <> nil then
  begin
    p := ScreenToClient(MousePos);
    factor := Power(1.15, WheelDelta / 120);
    ZoomAt(factor, p.X, p.Y);
    Result := True;   // handled
  end
  else
    Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
end;

procedure TTyImageView.DblClick;
var
  fitZoom: Double;
begin
  inherited DblClick;
  if FSource = nil then Exit;
  fitZoom := TyImageViewClamp(
    TyImageViewFitZoom(FSource.Width, FSource.Height, ViewW, ViewH),
    FZoomMin, FZoomMax);
  // Toggle between contain-fit and 100%. Treat "at fit" generously so a fit view (or
  // a freshly auto-fitted one) double-clicks to actual size.
  if Abs(FZoom - fitZoom) < 0.01 then
    ZoomToActual
  else
    ZoomToFit;
end;

procedure TTyImageView.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  ClientR, dst: TRect;
  vw, vh: Integer;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    vw := ARect.Right - ARect.Left;
    vh := ARect.Bottom - ARect.Top;
    ClientR := Rect(0, 0, vw, vh);
    // Mailbox surface: the themed TyPanel background fills the whole control.
    DrawFrame(P, ClientR, S);

    if FSource <> nil then
    begin
      if FProcDirty then RebuildProcessed;
      if FProcessed <> nil then
      begin
        dst := TyImageViewDestRect(FSource.Width, FSource.Height, vw, vh,
          FZoom, FOffX, FOffY);
        if (dst.Right > dst.Left) and (dst.Bottom > dst.Top) then
        begin
          // StretchPutImage/PutImage clip to the target bitmap bounds automatically.
          if ((dst.Right - dst.Left) = FProcessed.Width)
             and ((dst.Bottom - dst.Top) = FProcessed.Height) then
            P.Bitmap.PutImage(dst.Left, dst.Top, FProcessed, dmDrawWithTransparency)
          else
            P.Bitmap.StretchPutImage(dst, FProcessed, dmDrawWithTransparency);
        end;
      end;
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyImageView.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

initialization
  RegisterClass(TTyImageView);

end.
