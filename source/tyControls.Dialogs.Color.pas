unit tyControls.Dialogs.Color;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Math, Graphics, Controls, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Painter, tyControls.ColorMath;
type
  TTyHSVSquare = class(TTyCustomControl)
  private
    FHue, FSat, FVal: Single;
    FOnChange: TNotifyEvent;
    FDragging: Boolean;
    procedure DoChange;
    procedure ApplyXY(X, Y: Integer);
  protected
    function GetStyleTypeKey: string; override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetHSV(H, S, V: Single);
    // driven by the parent (hue bar) which Invalidates the square; bare field write is intentional
    property Hue: Single read FHue write FHue;
    property Sat: Single read FSat;
    property Val: Single read FVal;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;
  TTyHueBar = class(TTyCustomControl)
  private
    FHue: Single;
    FOnChange: TNotifyEvent;
    FDragging: Boolean;
    procedure SetHue(AValue: Single);
    procedure DoChange;
    procedure ApplyY(Y: Integer);
  protected
    function GetStyleTypeKey: string; override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    property Hue: Single read FHue write SetHue;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;
implementation

{ TyColorToBGRA lives in tyControls.Painter (public, imported above) — no local copy. }

{ TTyHSVSquare }

constructor TTyHSVSquare.Create(AOwner: TComponent);
begin inherited Create(AOwner); Width := 180; Height := 180; FHue := 0; FSat := 1; FVal := 1; end;

function TTyHSVSquare.GetStyleTypeKey: string; begin Result := 'TyColorArea'; end;

procedure TTyHSVSquare.DoChange; begin if Assigned(FOnChange) then FOnChange(Self); end;

procedure TTyHSVSquare.SetHSV(H, S, V: Single); begin FHue := H; FSat := S; FVal := V; Invalidate; end;

procedure TTyHSVSquare.ApplyXY(X, Y: Integer);
var sv: TPointF;
begin sv := TyHSVAreaToSV(Point(X, Y), ClientRect); FSat := sv.X; FVal := sv.Y; Invalidate; DoChange; end;

// TODO(perf): the SV gradient only depends on FHue — cache the per-hue bitmap and redraw
// just the ring on S/V change if a larger/resizable square is ever exposed. Fine at the
// fixed 180px size for now.
procedure TTyHSVSquare.Paint;
var P: TTyPainter; bmp: TBGRABitmap; xx, yy, w, h, ix, iy: Integer; s, v: Single;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    bmp := P.Bitmap; w := bmp.Width; h := bmp.Height;
    if (w > 0) and (h > 0) then
    begin
      for yy := 0 to h - 1 do
        for xx := 0 to w - 1 do
        begin
          s := xx / Max(1, w - 1); v := 1 - yy / Max(1, h - 1);
          bmp.SetPixel(xx, yy, TyColorToBGRA(TyHSVToRGB(FHue, s, v)));
        end;
      ix := Round(FSat * Max(1, w - 1)); iy := Round((1 - FVal) * Max(1, h - 1));
      P.StrokeBorder(Rect(ix - 5, iy - 5, ix + 6, iy + 6), 6, 2, TyRGB(255, 255, 255));
    end;
    P.EndPaint;
  finally P.Free; end;
end;

procedure TTyHSVSquare.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin inherited MouseDown(Button, Shift, X, Y); if Button = mbLeft then begin FDragging := True; ApplyXY(X, Y); end; end;

procedure TTyHSVSquare.MouseMove(Shift: TShiftState; X, Y: Integer);
begin inherited MouseMove(Shift, X, Y); if FDragging then ApplyXY(X, Y); end;

procedure TTyHSVSquare.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin inherited MouseUp(Button, Shift, X, Y); if Button = mbLeft then FDragging := False; end;

{ TTyHueBar }

constructor TTyHueBar.Create(AOwner: TComponent);
begin inherited Create(AOwner); Width := 18; Height := 180; FHue := 0; end;

function TTyHueBar.GetStyleTypeKey: string; begin Result := 'TyColorArea'; end;

procedure TTyHueBar.DoChange; begin if Assigned(FOnChange) then FOnChange(Self); end;

procedure TTyHueBar.SetHue(AValue: Single); begin if FHue <> AValue then begin FHue := AValue; Invalidate; DoChange; end; end;

procedure TTyHueBar.ApplyY(Y: Integer); begin SetHue(TyHueBarToH(Y, ClientRect)); end;

procedure TTyHueBar.Paint;
var P: TTyPainter; bmp: TBGRABitmap; xx, yy, w, h, iy: Integer; px: TBGRAPixel;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    bmp := P.Bitmap; w := bmp.Width; h := bmp.Height;
    if (w > 0) and (h > 0) then
    begin
      for yy := 0 to h - 1 do
      begin
        px := TyColorToBGRA(TyHSVToRGB(TyHueBarToH(yy, Rect(0, 0, w, h)), 1, 1));
        for xx := 0 to w - 1 do
          bmp.SetPixel(xx, yy, px);
      end;
      iy := Round(FHue / 360 * Max(1, h - 1));
      P.StrokeBorder(Rect(0, iy - 1, w, iy + 2), 0, 2, TyRGB(255, 255, 255));
    end;
    P.EndPaint;
  finally P.Free; end;
end;

procedure TTyHueBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin inherited MouseDown(Button, Shift, X, Y); if Button = mbLeft then begin FDragging := True; ApplyY(Y); end; end;

procedure TTyHueBar.MouseMove(Shift: TShiftState; X, Y: Integer);
begin inherited MouseMove(Shift, X, Y); if FDragging then ApplyY(Y); end;

procedure TTyHueBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin inherited MouseUp(Button, Shift, X, Y); if Button = mbLeft then FDragging := False; end;

end.
