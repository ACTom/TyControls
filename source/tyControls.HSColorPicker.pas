unit tyControls.HSColorPicker;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType,
  BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.ColorMath;

type
  { A 2D Hue x Saturation square. The X axis is Hue (0..360, left->right) and the
    Y axis is Saturation (top = 1 fully saturated, bottom = 0), drawn at a FIXED
    Value/brightness (so an external TTyLColorPicker can drive the brightness).
    Click or drag anywhere to pick (Hue, Sat); a small crosshair circle marks the
    current point, and the resulting colour is exposed as SelectedColor.

    A windowed graphic control (own HWND) painted the canonical TTyPainter way;
    reuses the 'TyGauge' theming (body/border/marker text colour) so it needs no
    extra .tycss rule. }
  TTyHSColorPicker = class(TTyCustomControl)
  private
    FHue: Single;         // 0..360
    FSat: Single;         // 0..1 (top = 1, bottom = 0)
    FValue: Single;       // 0..1 (fixed brightness the square is drawn at)
    FDragging: Boolean;
    FUpdating: Boolean;   // True while UpdateFromXY sets Hue+Sat together — suppresses the
                          // per-setter OnChange so one drag/click = ONE event with a
                          // consistent (Hue, Sat), matching the LColorPicker sibling.
    FOnChange: TNotifyEvent;
    procedure SetHue(const AValue: Single);
    procedure SetSat(const AValue: Single);
    procedure SetValue(const AValue: Single);
    function GetSelectedColor: TTyColor;
    { Square geometry, shared by Paint and UpdateFromXY so the marker and the
      hit-test agree. }
    procedure SquareMetrics(out ASqLeft, ASqTop, ASqWidth, ASqHeight: Integer);
    procedure UpdateFromXY(AX, AY: Integer);
  protected
    function GetStyleTypeKey: string; override;   // 'TyGauge'
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    { The colour under the current Hue/Sat/Value (opaque). }
    property SelectedColor: TTyColor read GetSelectedColor;
  published
    property Hue: Single read FHue write SetHue;
    property Sat: Single read FSat write SetSat;
    property Value: Single read FValue write SetValue;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

const
  SquareMargin = 3;   // logical-px inset of the gradient square from the control edge

constructor TTyHSColorPicker.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHue := 0;
  FSat := 1;
  FValue := 1;
  FDragging := False;
  Width := 180;
  Height := 140;
end;

function TTyHSColorPicker.GetStyleTypeKey: string;
begin
  Result := 'TyGauge';
end;

function TTyHSColorPicker.GetSelectedColor: TTyColor;
begin
  Result := TyHSVToRGB(FHue, FSat, FValue, 255);
end;

procedure TTyHSColorPicker.SetHue(const AValue: Single);
var
  v: Single;
begin
  v := AValue;
  if v < 0 then v := 0 else if v > 360 then v := 360;   // clamp to [0,360]
  if FHue = v then Exit;
  FHue := v;
  Invalidate;
  if Assigned(FOnChange) and (not FUpdating) then FOnChange(Self);
end;

procedure TTyHSColorPicker.SetSat(const AValue: Single);
var
  v: Single;
begin
  v := AValue;
  if v < 0 then v := 0 else if v > 1 then v := 1;       // clamp to [0,1]
  if FSat = v then Exit;
  FSat := v;
  Invalidate;
  if Assigned(FOnChange) and (not FUpdating) then FOnChange(Self);
end;

procedure TTyHSColorPicker.SetValue(const AValue: Single);
var
  v: Single;
begin
  v := AValue;
  if v < 0 then v := 0 else if v > 1 then v := 1;       // clamp to [0,1]
  if FValue = v then Exit;
  FValue := v;
  Invalidate;                                            // Value just repaints (no OnChange)
end;

procedure TTyHSColorPicker.SquareMetrics(out ASqLeft, ASqTop, ASqWidth, ASqHeight: Integer);
var
  m: Integer;
begin
  m := MulDiv(SquareMargin, Font.PixelsPerInch, 96);
  if m < 1 then m := 1;
  ASqLeft := m;
  ASqTop := m;
  ASqWidth := ClientWidth - 2 * m;
  ASqHeight := ClientHeight - 2 * m;
  if ASqWidth < 1 then ASqWidth := 1;
  if ASqHeight < 1 then ASqHeight := 1;
end;

procedure TTyHSColorPicker.UpdateFromXY(AX, AY: Integer);
var
  sqLeft, sqTop, sqW, sqH: Integer;
  hx, sy, oldH, oldS: Single;
begin
  SquareMetrics(sqLeft, sqTop, sqW, sqH);
  // X (sqLeft .. sqLeft+sqW-1) -> Hue 0..360. Guard degenerate width.
  if sqW <= 1 then
    hx := 0
  else
  begin
    hx := (AX - sqLeft) / (sqW - 1);
    if hx < 0 then hx := 0 else if hx > 1 then hx := 1;
  end;
  // Y (sqTop = Sat 1, bottom = Sat 0). Guard degenerate height.
  if sqH <= 1 then
    sy := 1
  else
  begin
    sy := 1 - (AY - sqTop) / (sqH - 1);
    if sy < 0 then sy := 0 else if sy > 1 then sy := 1;
  end;
  // Set both axes atomically: suppress the per-setter OnChange, then fire ONE event
  // after both are updated so a diagonal click/drag never exposes a transient
  // (newHue, oldSat) colour (and a consumer sees a single event, like LColorPicker).
  oldH := FHue;
  oldS := FSat;
  FUpdating := True;
  try
    Hue := hx * 360;   // setters clamp + Invalidate; OnChange suppressed while FUpdating
    Sat := sy;
  finally
    FUpdating := False;
  end;
  if ((FHue <> oldH) or (FSat <> oldS)) and Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TTyHSColorPicker.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDragging := True;
    UpdateFromXY(X, Y);
  end;
end;

procedure TTyHSColorPicker.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  if not Enabled then Exit;
  inherited MouseMove(Shift, X, Y);
  if FDragging then UpdateFromXY(X, Y);
end;

procedure TTyHSColorPicker.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then FDragging := False;
end;

procedure TTyHSColorPicker.Paint;
var
  P: TTyPainter;
  bodyS: TTyStyleSet;
  R: TRect;
  ctx: TBGRACanvas2D;
  sqLeft, sqTop, sqW, sqH, xx, yy, mx, my, mr: Integer;
  hueDeg, a: Single;
  greyRGB: TTyColor;
  c: TTyColor;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ClientWidth, ClientHeight);
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    bodyS := CurrentStyle;                         // TyGauge body/border/text
    // Windowed control: fill the full rect with the parent/form background first,
    // so the margin around the square shows the form (or image-theme photo).
    TyFillParentBg(Self, P, R, bodyS);

    SquareMetrics(sqLeft, sqTop, sqW, sqH);
    ctx := P.Bitmap.Canvas2D;

    // Pass 1: horizontal HUE gradient across the square, full saturation, fixed
    // Value. One opaque 1px column per x.
    if sqW = 1 then
    begin
      c := TyHSVToRGB(FHue, 1, FValue, 255);
      ctx.fillStyle(TyColorToBGRA(c));
      ctx.fillRect(sqLeft, sqTop, 1, sqH);
    end
    else
      for xx := 0 to sqW - 1 do
      begin
        hueDeg := (xx / (sqW - 1)) * 360;
        c := TyHSVToRGB(hueDeg, 1, FValue, 255);
        ctx.fillStyle(TyColorToBGRA(c));
        ctx.fillRect(sqLeft + xx, sqTop, 1, sqH);
      end;

    // Pass 2: vertical SATURATION fade — one horizontal grey line per y, alpha
    // rising top (transparent, keeps full sat) -> bottom (opaque grey, S=0). The
    // grey is the S=0 colour at the fixed Value (TyHSVToRGB(0,0,FValue)).
    greyRGB := TyHSVToRGB(0, 0, FValue, 255);
    if sqH = 1 then
    begin
      // Single row: sits at the top (S=1) — no overlay needed.
    end
    else
      for yy := 0 to sqH - 1 do
      begin
        a := yy / (sqH - 1);   // 0 at top -> 1 at bottom
        c := TyRGBA(TyRedOf(greyRGB), TyGreenOf(greyRGB), TyBlueOf(greyRGB),
          Round(a * 255));
        ctx.fillStyle(TyColorToBGRA(c));
        ctx.fillRect(sqLeft, sqTop + yy, sqW, 1);
      end;

    // Theme border around the square.
    if (tpBorderColor in bodyS.Present) and (bodyS.BorderWidth > 0) then
      P.StrokeBorder(Rect(sqLeft, sqTop, sqLeft + sqW, sqTop + sqH),
        0, bodyS.BorderWidth, bodyS.BorderColor);

    // Crosshair: a small circle in the text colour at the current (Hue, Sat).
    if sqW >= 2 then
      mx := sqLeft + Round((FHue / 360) * (sqW - 1))
    else
      mx := sqLeft;
    if sqH >= 2 then
      my := sqTop + Round((1 - FSat) * (sqH - 1))
    else
      my := sqTop;
    mr := Math.Max(3, P.Scale(4));
    ctx.lineWidth := Math.Max(1, P.Scale(2));
    ctx.strokeStyle(TyColorToBGRA(bodyS.TextColor));
    ctx.beginPath;
    ctx.arc(mx, my, mr, 0, 2 * Pi, False);
    ctx.stroke;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
