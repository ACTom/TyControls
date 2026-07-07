unit tyControls.LColorPicker;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType,
  BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.ColorMath;

type
  { A VERTICAL HSV brightness (Value/"lightness") picker: a bar filled with a
    top-to-bottom V gradient at a FIXED Hue+Sat (top = V=1 bright, bottom = V=0
    dark), plus a draggable marker. Picks a scalar Position in [0..1] (= V) and
    exposes the resulting colour as SelectedColor. A windowed graphic control
    (own HWND) painted the canonical TTyPainter way; reuses the 'TyGauge' theming
    (body/border/text) so it needs no extra .tycss rule. }
  TTyLColorPicker = class(TTyCustomControl)
  private
    FHue: Single;         // 0..360
    FSat: Single;         // 0..1
    FPosition: Single;    // 0..1 (= V)
    FDragging: Boolean;
    FOnChange: TNotifyEvent;
    procedure SetHue(const AValue: Single);
    procedure SetSat(const AValue: Single);
    procedure SetPosition(const AValue: Single);
    function GetSelectedColor: TTyColor;
    { Bar geometry, shared by Paint and UpdateFromY, so the marker and the hit-test
      agree. barTop is the top of the gradient band; barH is its pixel height. }
    procedure BarMetrics(out ABarLeft, ABarTop, ABarWidth, ABarH: Integer);
    procedure UpdateFromY(AY: Integer);
  protected
    function GetStyleTypeKey: string; override;   // 'TyGauge'
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    { The colour under the current Hue/Sat/Position (opaque). }
    property SelectedColor: TTyColor read GetSelectedColor;
  published
    property Hue: Single read FHue write SetHue;
    property Sat: Single read FSat write SetSat;
    property Position: Single read FPosition write SetPosition;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

const
  BarMargin = 3;   // logical-px inset of the gradient bar from the control edge

constructor TTyLColorPicker.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHue := 0;
  FSat := 1;
  FPosition := 1;
  FDragging := False;
  Width := 28;
  Height := 160;
end;

function TTyLColorPicker.GetStyleTypeKey: string;
begin
  Result := 'TyGauge';
end;

function TTyLColorPicker.GetSelectedColor: TTyColor;
begin
  Result := TyHSVToRGB(FHue, FSat, FPosition, 255);
end;

procedure TTyLColorPicker.SetHue(const AValue: Single);
begin
  if FHue = AValue then Exit;
  FHue := AValue;
  Invalidate;
end;

procedure TTyLColorPicker.SetSat(const AValue: Single);
begin
  if FSat = AValue then Exit;
  FSat := AValue;
  Invalidate;
end;

procedure TTyLColorPicker.SetPosition(const AValue: Single);
var
  v: Single;
begin
  v := AValue;
  if v < 0 then v := 0 else if v > 1 then v := 1;   // clamp to [0,1]
  if FPosition = v then Exit;
  FPosition := v;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyLColorPicker.BarMetrics(out ABarLeft, ABarTop, ABarWidth, ABarH: Integer);
var
  m: Integer;
begin
  m := MulDiv(BarMargin, Font.PixelsPerInch, 96);
  if m < 1 then m := 1;
  ABarLeft := m;
  ABarTop := m;
  ABarWidth := ClientWidth - 2 * m;
  ABarH := ClientHeight - 2 * m;
  if ABarWidth < 1 then ABarWidth := 1;
  if ABarH < 1 then ABarH := 1;
end;

procedure TTyLColorPicker.UpdateFromY(AY: Integer);
var
  barLeft, barTop, barWidth, barH: Integer;
begin
  BarMetrics(barLeft, barTop, barWidth, barH);
  if barH <= 1 then
  begin
    Position := 1;   // degenerate bar: top value
    Exit;
  end;
  // Top (AY = barTop) = V=1; bottom (AY = barTop + barH-1) = V=0. Position setter clamps.
  Position := 1 - (AY - barTop) / (barH - 1);
end;

procedure TTyLColorPicker.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDragging := True;
    UpdateFromY(Y);
  end;
end;

procedure TTyLColorPicker.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  if not Enabled then Exit;
  inherited MouseMove(Shift, X, Y);
  if FDragging then UpdateFromY(Y);
end;

procedure TTyLColorPicker.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then FDragging := False;
end;

procedure TTyLColorPicker.Paint;
var
  P: TTyPainter;
  bodyS: TTyStyleSet;
  R: TRect;
  ctx: TBGRACanvas2D;
  barLeft, barTop, barWidth, barH, yy, my: Integer;
  v: Single;
  c: TTyColor;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ClientWidth, ClientHeight);
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    bodyS := CurrentStyle;                         // TyGauge body/border/text
    // Windowed control: fill the full rect with the parent/form background first,
    // so the margin around the bar shows the form (or image-theme photo).
    TyFillParentBg(Self, P, R, bodyS);

    BarMetrics(barLeft, barTop, barWidth, barH);
    ctx := P.Bitmap.Canvas2D;

    // Gradient: one 1px scanline per bar row, top (V=1) to bottom (V=0).
    if barH = 1 then
    begin
      c := TyHSVToRGB(FHue, FSat, 1, 255);
      ctx.fillStyle(TyColorToBGRA(c));
      ctx.fillRect(barLeft, barTop, barWidth, 1);
    end
    else
      for yy := 0 to barH - 1 do
      begin
        v := 1 - (yy / (barH - 1));
        c := TyHSVToRGB(FHue, FSat, v, 255);
        ctx.fillStyle(TyColorToBGRA(c));
        ctx.fillRect(barLeft, barTop + yy, barWidth, 1);
      end;

    // Bar border in the theme border colour.
    if (tpBorderColor in bodyS.Present) and (bodyS.BorderWidth > 0) then
      P.StrokeBorder(Rect(barLeft, barTop, barLeft + barWidth, barTop + barH),
        0, bodyS.BorderWidth, bodyS.BorderColor);

    // Marker: a thin horizontal line at the current Position, in the text colour.
    if barH >= 2 then
      my := barTop + Round((1 - FPosition) * (barH - 1))
    else
      my := barTop;
    ctx.fillStyle(TyColorToBGRA(bodyS.TextColor));
    ctx.fillRect(barLeft, my, barWidth, Math.Max(1, P.Scale(2)));

    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
