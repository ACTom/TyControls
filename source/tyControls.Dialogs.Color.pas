unit tyControls.Dialogs.Color;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Math, Graphics, Controls, Forms, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Painter, tyControls.ColorMath,
  tyControls.Dialogs, tyControls.Edit, tyControls.SpinEdit, tyControls.TyLabel,
  tyControls.StrConsts;
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

  { TTyColorForm — a single-model (FColor) dialog driving many synced views:
    an HSV square + hue bar picker, Hex edit, R/G/B spins, C/M/Y/K spins, an
    Alpha spin, and a preview swatch. Any view change flows through ApplyColor
    (FColor := c; SyncViewsFromColor), which re-seeds every OTHER view under the
    FUpdating guard so the programmatic OnChange fired by each editor is ignored
    (no infinite cascade). }
  TTyColorForm = class(TTyDialog)
  private
    FColor: TTyColor;
    FUpdating: Boolean;
    FPreviewRect: TRect;
    FSquare: TTyHSVSquare; FHueBar: TTyHueBar;
    FHex: TTyEdit; FR, FG, FB, FA: TTySpinEdit; FC, FM, FY, FK: TTySpinEdit;
    procedure SyncViewsFromColor;
    procedure PickerChanged(Sender: TObject);
    procedure RGBChanged(Sender: TObject);
    procedure CMYKChanged(Sender: TObject);
    procedure AlphaChanged(Sender: TObject);
    procedure HexChanged(Sender: TObject);
    procedure ApplyColor(AColor: TTyColor);   // set FColor + resync (guarded)
  protected
    procedure Paint; override;                 // draws the preview swatch (GUI)
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    function CurrentColor: TTyColor;
    function HexText: string;
    procedure SetColorValue(AColor: TTyColor);   // public seam
    procedure ApplyHexText(const AHex: string);  // public seam
  end;

function TyBuildColorDialog(const ACaption: string; ASeed: TTyColor): TTyColorForm;
function TySelectColor(const ACaption: string; var AColor: TTyColor): Boolean; overload;
function TySelectColor(const ACaption: string; var AColor: TColor; var AAlpha: Byte): Boolean; overload;

type
  TTyColorDialog = class(TComponent)
  private
    FColor: TTyColor; FCaption: string;
    function GetLCL: TColor; procedure SetLCL(v: TColor);
    function GetAlpha: Byte; procedure SetAlpha(v: Byte);
  public
    constructor Create(AOwner: TComponent); override;
    function Execute: Boolean;
    property LCLColor: TColor read GetLCL write SetLCL;
  published
    property Caption: string read FCaption write FCaption;
    property Color: TTyColor read FColor write FColor default $FF000000;
    property Alpha: Byte read GetAlpha write SetAlpha default $FF;
  end;

implementation

uses tyControls.Css.Values;   // TyParseColor

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

{ TTyColorForm }

constructor TTyColorForm.CreateNew(AOwner: TComponent; Num: Integer);
var
  r: TRect;
  x0, y0, colX, spinW, spinH, rowH, labelW: Integer;

  function MkLabel(const ACaption: string; ALeft, ATop, AWidth: Integer): TTyLabel;
  begin
    Result := TTyLabel.Create(Self);
    Result.Parent := Self;
    Result.Caption := ACaption;
    Result.SetBounds(ALeft, ATop, AWidth, 20);
  end;

  function MkSpin(AMin, AMax, ALeft, ATop, AWidth, AHeight: Integer): TTySpinEdit;
  begin
    Result := TTySpinEdit.Create(Self);
    Result.Parent := Self;
    Result.MinValue := AMin;
    Result.MaxValue := AMax;
    Result.SetBounds(ALeft, ATop, AWidth, AHeight);
  end;

begin
  inherited CreateNew(AOwner, Num);
  FColor := $FF000000;
  r := ContentRect;
  x0 := r.Left + TyDlgPad;
  y0 := r.Top + TyDlgPad;
  spinW := 56; spinH := TyDlgEditH; rowH := spinH + 8; labelW := 16;

  // Picker: HSV square + hue bar at the top.
  FSquare := TTyHSVSquare.Create(Self);
  FSquare.Parent := Self;
  FSquare.SetBounds(x0, y0, 180, 180);
  FHueBar := TTyHueBar.Create(Self);
  FHueBar.Parent := Self;
  FHueBar.SetBounds(x0 + 180 + 10, y0, 18, 180);

  // Right column: Hex + channel editors.
  colX := x0 + 180 + 10 + 18 + 16;

  MkLabel(rsDlgHex, colX, y0, 40);
  FHex := TTyEdit.Create(Self);
  FHex.Parent := Self;
  FHex.SetBounds(colX + 44, y0 - 4, 120, TyDlgEditH);

  // RGB row.
  MkLabel('R', colX, y0 + rowH, labelW);
  FR := MkSpin(0, 255, colX + 18, y0 + rowH - 4, spinW, spinH);
  MkLabel('G', colX + 18 + spinW + 8, y0 + rowH, labelW);
  FG := MkSpin(0, 255, colX + 18 + spinW + 8 + 18, y0 + rowH - 4, spinW, spinH);
  MkLabel('B', colX + 2*(18 + spinW + 8), y0 + rowH, labelW);
  FB := MkSpin(0, 255, colX + 2*(18 + spinW + 8) + 18, y0 + rowH - 4, spinW, spinH);

  // CMYK row.
  MkLabel('C', colX, y0 + 2*rowH, labelW);
  FC := MkSpin(0, 100, colX + 18, y0 + 2*rowH - 4, spinW, spinH);
  MkLabel('M', colX + 18 + spinW + 8, y0 + 2*rowH, labelW);
  FM := MkSpin(0, 100, colX + 18 + spinW + 8 + 18, y0 + 2*rowH - 4, spinW, spinH);
  MkLabel('Y', colX + 2*(18 + spinW + 8), y0 + 2*rowH, labelW);
  FY := MkSpin(0, 100, colX + 2*(18 + spinW + 8) + 18, y0 + 2*rowH - 4, spinW, spinH);
  MkLabel('K', colX + 3*(18 + spinW + 8), y0 + 2*rowH, labelW);
  FK := MkSpin(0, 100, colX + 3*(18 + spinW + 8) + 18, y0 + 2*rowH - 4, spinW, spinH);

  // Alpha + preview row.
  MkLabel(rsDlgAlpha, colX, y0 + 3*rowH, 44);
  FA := MkSpin(0, 255, colX + 44, y0 + 3*rowH - 4, spinW, spinH);
  MkLabel(rsDlgPreview, x0, y0 + 180 + 8, 60);
  FPreviewRect := Rect(x0, y0 + 180 + 30, x0 + 180, y0 + 180 + 30 + 40);

  // Wire change handlers AFTER creation so no premature fires occur.
  FSquare.OnChange := @PickerChanged;
  FHueBar.OnChange := @PickerChanged;
  FHex.OnChange := @HexChanged;
  FR.OnChange := @RGBChanged;
  FG.OnChange := @RGBChanged;
  FB.OnChange := @RGBChanged;
  FC.OnChange := @CMYKChanged;
  FM.OnChange := @CMYKChanged;
  FY.OnChange := @CMYKChanged;
  FK.OnChange := @CMYKChanged;
  FA.OnChange := @AlphaChanged;

  AddButton(rsMsgBtnOK, mrOK, True, False);
  AddButton(rsMsgBtnCancel, mrCancel, False, True);
  // content spans the picker column + the right editor column, down to the preview.
  AutoSizeToContent(colX + 4*(18 + spinW + 8) + TyDlgPad - (r.Left + TyDlgPad),
    (y0 + 180 + 30 + 40 + TyDlgPad) - r.Top);
  SetColorValue(FColor);   // seed all views from the model
end;

procedure TTyColorForm.SetColorValue(AColor: TTyColor);
begin FColor := AColor; SyncViewsFromColor; end;

procedure TTyColorForm.ApplyColor(AColor: TTyColor);
begin FColor := AColor; SyncViewsFromColor; end;

function TTyColorForm.CurrentColor: TTyColor;
begin Result := FColor; end;

function TTyColorForm.HexText: string;
begin Result := TyColorToHex(FColor, False); end;   // RGB-only (no alpha)

procedure TTyColorForm.ApplyHexText(const AHex: string);
begin FHex.Text := AHex; HexChanged(FHex); end;

procedure TTyColorForm.SyncViewsFromColor;
var cc, mm, yy, kk, h, s, v: Single;
begin
  FUpdating := True;
  try
    FR.Value := TyRedOf(FColor);
    FG.Value := TyGreenOf(FColor);
    FB.Value := TyBlueOf(FColor);
    FA.Value := TyAlphaOf(FColor);
    TyRGBToCMYK(FColor, cc, mm, yy, kk);
    FC.Value := Round(cc * 100);
    FM.Value := Round(mm * 100);
    FY.Value := Round(yy * 100);
    FK.Value := Round(kk * 100);
    FHex.Text := TyColorToHex(FColor, True);
    TyRGBToHSV(FColor, h, s, v);
    FSquare.SetHSV(h, s, v);
    FHueBar.Hue := h;
    Invalidate;   // repaint the preview swatch
  finally
    FUpdating := False;
  end;
end;

procedure TTyColorForm.PickerChanged(Sender: TObject);
begin
  if FUpdating then Exit;
  ApplyColor(TyHSVToRGB(FHueBar.Hue, FSquare.Sat, FSquare.Val, FA.Value));
end;

procedure TTyColorForm.RGBChanged(Sender: TObject);
begin
  if FUpdating then Exit;
  ApplyColor(TyRGBA(FR.Value, FG.Value, FB.Value, FA.Value));
end;

procedure TTyColorForm.CMYKChanged(Sender: TObject);
begin
  if FUpdating then Exit;
  ApplyColor(TyCMYKToRGB(FC.Value / 100, FM.Value / 100, FY.Value / 100,
    FK.Value / 100, FA.Value));
end;

procedure TTyColorForm.AlphaChanged(Sender: TObject);
begin
  if FUpdating then Exit;
  ApplyColor(TyRGBA(TyRedOf(FColor), TyGreenOf(FColor), TyBlueOf(FColor), FA.Value));
end;

procedure TTyColorForm.HexChanged(Sender: TObject);
var t: string;
begin
  if FUpdating then Exit;
  t := Trim(FHex.Text);
  // only apply a syntactically complete #rgb / #rrggbb / #rrggbbaa; ignore partial input.
  if (Length(t) >= 1) and (t[1] = '#') and
     ((Length(t) = 4) or (Length(t) = 7) or (Length(t) = 9)) then
    try
      ApplyColor(TyParseColor(t));
    except
      // invalid hex (bad digit) — keep the last valid FColor
    end;
end;

procedure TTyColorForm.Paint;
var P: TTyPainter; fill: TTyFill; i, j, cell: Integer;
begin
  inherited Paint;
  if (Canvas = nil) or (not HandleAllocated) then Exit;   // crash-safe: GUI-only
  if (FPreviewRect.Right <= FPreviewRect.Left) then Exit;
  P := TTyPainter.Create;
  try
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    // checkerboard behind the swatch so alpha reads as transparency.
    cell := 8;
    fill := Default(TTyFill); fill.Kind := tfkSolid;
    i := FPreviewRect.Top;
    while i < FPreviewRect.Bottom do
    begin
      j := FPreviewRect.Left;
      while j < FPreviewRect.Right do
      begin
        if (((i - FPreviewRect.Top) div cell) + ((j - FPreviewRect.Left) div cell)) and 1 = 0 then
          fill.Color := TyRGB(255, 255, 255)
        else
          fill.Color := TyRGB(204, 204, 204);
        P.FillBackground(Rect(j, i, Min(j + cell, FPreviewRect.Right),
          Min(i + cell, FPreviewRect.Bottom)), fill, TyUniformCorners(0));
        Inc(j, cell);
      end;
      Inc(i, cell);
    end;
    // the current colour (alpha-composited over the checkerboard) on top.
    fill.Color := FColor;
    P.FillBackground(FPreviewRect, fill, TyUniformCorners(0));
    P.EndPaint;
  finally P.Free; end;
end;

{ Color-dialog globals }

function TyBuildColorDialog(const ACaption: string; ASeed: TTyColor): TTyColorForm;
begin
  Result := TTyColorForm.CreateNew(Application);
  Result.Caption := ACaption;
  Result.SetColorValue(ASeed);
end;

function TySelectColor(const ACaption: string; var AColor: TTyColor): Boolean;
var d: TTyColorForm;
begin
  d := TyBuildColorDialog(ACaption, AColor);
  try
    Result := (d.ShowModal = mrOK);
    if Result then AColor := d.CurrentColor;
  finally d.Free; end;
end;

function TySelectColor(const ACaption: string; var AColor: TColor; var AAlpha: Byte): Boolean;
var d: TTyColorForm;
begin
  d := TyBuildColorDialog(ACaption, TyColorFromLCL(AColor, AAlpha));
  try
    Result := (d.ShowModal = mrOK);
    if Result then
    begin
      AColor := TyColorToLCL(d.CurrentColor);
      AAlpha := TyAlphaOf(d.CurrentColor);
    end;
  finally d.Free; end;
end;

{ TTyColorDialog }

constructor TTyColorDialog.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColor := $FF000000;
end;

function TTyColorDialog.GetLCL: TColor;
begin Result := TyColorToLCL(FColor); end;

procedure TTyColorDialog.SetLCL(v: TColor);
begin FColor := TyColorFromLCL(v, TyAlphaOf(FColor)); end;   // preserve alpha

function TTyColorDialog.GetAlpha: Byte;
begin Result := TyAlphaOf(FColor); end;

procedure TTyColorDialog.SetAlpha(v: Byte);
begin FColor := TyRGBA(TyRedOf(FColor), TyGreenOf(FColor), TyBlueOf(FColor), v); end;

function TTyColorDialog.Execute: Boolean;
begin Result := TySelectColor(FCaption, FColor); end;

end.
