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
    FOnShow: TNotifyEvent;
    FOnClose: TCloseEvent;
    FOnCanClose: TCloseQueryEvent;
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
    property OnShow: TNotifyEvent read FOnShow write FOnShow;
    property OnClose: TCloseEvent read FOnClose write FOnClose;
    property OnCanClose: TCloseQueryEvent read FOnCanClose write FOnCanClose;
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
const
  SquareSz  = 180;   // HSV square edge
  HueW      = 18;    // hue bar width
  PickGap   = 10;    // square -> hue bar gap
  ColGap    = 20;    // hue bar -> right editor column gap
  CellGap   = 10;    // gap between adjacent channel cells (label+spin)
  RowGap    = 10;    // vertical gap between editor rows
  LblGap    = 6;     // gap between a channel label and its spin
  PrevGap   = 12;    // picker -> preview-section gap
  PrevH     = 44;    // preview swatch height
var
  r: TRect;
  x0, y0, colX, spinW, spinH, rowH, labelW: Integer;
  labelTop, cellW, colRight, contentRight, pickerBottom, previewTop: Integer;

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

  // Place one channel cell (single-char label + spin) at grid column AIndex within the
  // right editor column, at vertical row-top ATop; returns the created spin.
  function MkCell(const ACaption: string; AMin, AMax, AIndex, ATop: Integer): TTySpinEdit;
  var cx: Integer;
  begin
    cx := colX + AIndex * (cellW + CellGap);
    MkLabel(ACaption, cx, ATop + labelTop, labelW);
    Result := MkSpin(AMin, AMax, cx + labelW + LblGap, ATop, spinW, spinH);
  end;

begin
  inherited CreateNew(AOwner, Num);
  Caption := rsDlgColorTitle;   // title bar text (builders may override via ACaption)
  FColor := $FF000000;
  r := ContentRect;
  x0 := r.Left + TyDlgPad;
  y0 := r.Top + TyDlgPad;
  spinW := 56; spinH := TyDlgEditH; rowH := spinH + RowGap; labelW := 14;
  // labels are 20px tall; nudge them so their text baseline centres against the 30px spin.
  labelTop := (spinH - 20) div 2;
  cellW := labelW + LblGap + spinW;                 // full width of one label+spin cell

  // Picker: HSV square + hue bar, top-left.
  FSquare := TTyHSVSquare.Create(Self);
  FSquare.Parent := Self;
  FSquare.SetBounds(x0, y0, SquareSz, SquareSz);
  FHueBar := TTyHueBar.Create(Self);
  FHueBar.Parent := Self;
  FHueBar.SetBounds(x0 + SquareSz + PickGap, y0, HueW, SquareSz);

  // Right editor column starts after the hue bar. Every row shares the same
  // 4-cell grid so Hex / RGB / CMYK / Alpha align on the same left edges.
  colX := x0 + SquareSz + PickGap + HueW + ColGap;

  // Hex row: label + a wide edit spanning three cells.
  MkLabel(rsDlgHex, colX, y0 + labelTop, labelW);
  FHex := TTyEdit.Create(Self);
  FHex.Parent := Self;
  FHex.SetBounds(colX + labelW + LblGap, y0, 3 * cellW + 2 * CellGap - labelW - LblGap, spinH);

  // RGB row.
  FR := MkCell('R', 0, 255, 0, y0 + rowH);
  FG := MkCell('G', 0, 255, 1, y0 + rowH);
  FB := MkCell('B', 0, 255, 2, y0 + rowH);

  // CMYK row.
  FC := MkCell('C', 0, 100, 0, y0 + 2*rowH);
  FM := MkCell('M', 0, 100, 1, y0 + 2*rowH);
  FY := MkCell('Y', 0, 100, 2, y0 + 2*rowH);
  FK := MkCell('K', 0, 100, 3, y0 + 2*rowH);

  // Alpha row: keep the full "Alpha" label (resourcestring), spin aligned to the
  // grid's second cell so it lines up under G / M.
  MkLabel(rsDlgAlpha, colX, y0 + 3*rowH + labelTop, cellW);
  FA := MkSpin(0, 255, colX + (cellW + CellGap), y0 + 3*rowH, spinW, spinH);

  // Right column spans the widest row (the 4-cell CMYK row); overall content width
  // is from the left edge to whichever of the picker / editor column reaches further.
  colRight := colX + 4 * cellW + 3 * CellGap;
  contentRight := Max(x0 + SquareSz + PickGap + HueW, colRight);

  // Preview: a full-width labelled swatch band beneath the picker.
  pickerBottom := y0 + SquareSz;
  MkLabel(rsDlgPreview, x0, pickerBottom + PrevGap, 80);
  previewTop := pickerBottom + PrevGap + 24;
  FPreviewRect := Rect(x0, previewTop, contentRight, previewTop + PrevH);

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
  // content spans left edge -> whichever column reaches furthest right, down to the
  // preview swatch bottom.
  AutoSizeToContent(contentRight - x0, (FPreviewRect.Bottom + TyDlgPad) - r.Top);
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
var d: TTyColorForm;
begin
  // Inline the build/show (rather than call TySelectColor) so the wrapper's
  // OnShow/OnClose/OnCanClose forward onto the form before ShowModal.
  d := TyBuildColorDialog(FCaption, FColor);
  try
    TyForwardDialogEvents(d, FOnShow, FOnClose, FOnCanClose);
    Result := (d.ShowModal = mrOK);
    if Result then FColor := d.CurrentColor;
  finally d.Free; end;
end;

end.
