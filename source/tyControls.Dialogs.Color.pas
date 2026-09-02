unit tyControls.Dialogs.Color;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Math, Graphics, Controls, Forms, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Painter, tyControls.ColorMath,
  tyControls.Controller, tyControls.Dialogs, tyControls.Edit, tyControls.SpinEdit,
  tyControls.TyLabel, tyControls.ColorGrid, tyControls.Component, tyControls.StrConsts;
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
    an HSV square + hue bar picker, a quick-pick swatch grid, Hex edit, R/G/B spins,
    C/M/Y/K spins, an Alpha spin, and a preview swatch. Any view change flows through
    ApplyColor (FColor := c; SyncViewsFromColor), which re-seeds every OTHER view under
    the FUpdating guard so the programmatic OnChange fired by each editor is ignored
    (no infinite cascade).

    The one thing FColor is NOT the sole owner of is hue and saturation: RGB cannot carry
    them at the edges (black and every grey have no hue), so the square + hue bar keep
    their own H/S and are only re-seeded from a colour that came from OUTSIDE the picker.
    See SyncViewsFromColor. }
  TTyColorForm = class(TTyDialog)
  private
    FColor: TTyColor;
    FUpdating: Boolean;
    FPreviewRect: TRect;
    FSquare: TTyHSVSquare; FHueBar: TTyHueBar;
    FSwatches: TTyColorGrid;
    FHex: TTyEdit; FR, FG, FB, FA: TTySpinEdit; FC, FM, FY, FK: TTySpinEdit;
    procedure SyncViewsFromColor(AFromPicker: Boolean = False);
    procedure PickerChanged(Sender: TObject);
    procedure SwatchChanged(Sender: TObject);
    procedure RGBChanged(Sender: TObject);
    procedure CMYKChanged(Sender: TObject);
    procedure AlphaChanged(Sender: TObject);
    procedure HexChanged(Sender: TObject);
    // set FColor + resync (guarded). AFromPicker = the square/hue bar is the source, so
    // its H/S is authoritative and must not be written back from the RGB round trip.
    procedure ApplyColor(AColor: TTyColor; AFromPicker: Boolean = False);
  protected
    procedure Paint; override;                 // draws the preview swatch (GUI)
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    function CurrentColor: TTyColor;
    function HexText: string;
    procedure SetColorValue(AColor: TTyColor);   // public seam
    procedure ApplyHexText(const AHex: string);  // public seam
    { Drive the picker as a drag would: both commit through ApplyColor, so every other
      view follows. Public seams (a host can pre-position the picker; tests can pick
      without a window). }
    procedure SetPickerHue(AHue: Single);
    procedure SetPickerSV(ASat, AVal: Single);
    function PickerHue: Single;
    function PickerSat: Single;
    function PickerVal: Single;
    { The quick-pick grid, so a host can extend the palette (AddColor). }
    property Swatches: TTyColorGrid read FSwatches;
  end;

function TyBuildColorDialog(const ACaption: string; ASeed: TTyColor): TTyColorForm;
function TySelectColor(const ACaption: string; var AColor: TTyColor): Boolean; overload;
function TySelectColor(const ACaption: string; var AColor: TColor; var AAlpha: Byte): Boolean; overload;

type
  TTyColorDialog = class(TTyComponent)
  private
    FColor: TTyColor; FCaption: TCaption;
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
    property Caption: TCaption read FCaption write FCaption;
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

{ TabStop: these two are the dialog's primary pickers, not decoration — a click has to move
  focus onto them (TTyCustomControl.MouseDown gates that on TabStop) so the Hex/RGB editor
  the user came from gets its OnExit and commits, instead of keeping the caret while the
  square underneath it changes the colour. Their public twins (TTyHSColorPicker /
  TTyLColorPicker) are focusable for the same reason. }
constructor TTyHSVSquare.Create(AOwner: TComponent);
begin inherited Create(AOwner); TabStop := True; Width := 180; Height := 180; FHue := 0; FSat := 1; FVal := 1; end;

function TTyHSVSquare.GetStyleTypeKey: string; begin Result := 'TyColorArea'; end;

procedure TTyHSVSquare.DoChange; begin if Assigned(FOnChange) then FOnChange(Self); end;

procedure TTyHSVSquare.SetHSV(H, S, V: Single); begin FHue := H; FSat := S; FVal := V; Invalidate; end;

procedure TTyHSVSquare.ApplyXY(X, Y: Integer);
var sv: TPointF;
begin sv := TyHSVAreaToSV(Point(X, Y), ClientRect); FSat := sv.X; FVal := sv.Y; Invalidate; DoChange; end;

// Perf note, deliberate non-cache: the SV gradient depends only on FHue, so a per-hue
// cached bitmap (redrawing just the ring on S/V changes) becomes worthwhile only if this
// square is ever made larger or resizable. At the fixed 180px a full repaint is cheap.
{ The chromatic field itself is DATA — every pixel is the colour it stands for, so it is
  computed, never themed. The two things drawn ON TOP of it are chrome and must come from
  the theme: the marker ring and the field's border. They used to be a hardcoded white
  literal, which broke the library's own rule that no visual value lives in control code,
  and left 'TyColorArea' as a key a skin could set with no effect whatsoever. The two
  REGISTERED pickers (TTyHSColorPicker / TTyLColorPicker) already do this correctly with
  the same two properties, so this reads the same way they do. }
procedure TTyHSVSquare.Paint;
var
  P: TTyPainter; bmp: TBGRABitmap; xx, yy, w, h, ix, iy, mw: Integer; s, v: Single;
  bodyS: TTyStyleSet;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    bodyS := CurrentStyle;
    bmp := P.Bitmap; w := bmp.Width; h := bmp.Height;
    if (w > 0) and (h > 0) then
    begin
      for yy := 0 to h - 1 do
        for xx := 0 to w - 1 do
        begin
          s := xx / Max(1, w - 1); v := 1 - yy / Max(1, h - 1);
          bmp.SetPixel(xx, yy, TyColorToBGRA(TyHSVToRGB(FHue, s, v)));
        end;
      { Field border, when the theme asks for one. }
      if (tpBorderColor in bodyS.Present) and (bodyS.BorderWidth > 0) then
        P.StrokeBorder(Rect(0, 0, w, h), 0, bodyS.BorderWidth, bodyS.BorderColor);
      ix := Round(FSat * Max(1, w - 1)); iy := Round((1 - FVal) * Max(1, h - 1));
      mw := Max(1, P.Scale(2));
      P.StrokeBorder(Rect(ix - 5, iy - 5, ix + 6, iy + 6), 6, mw, bodyS.TextColor);
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
begin inherited Create(AOwner); TabStop := True; Width := 18; Height := 180; FHue := 0; end;

function TTyHueBar.GetStyleTypeKey: string; begin Result := 'TyColorArea'; end;

procedure TTyHueBar.DoChange; begin if Assigned(FOnChange) then FOnChange(Self); end;

procedure TTyHueBar.SetHue(AValue: Single); begin if FHue <> AValue then begin FHue := AValue; Invalidate; DoChange; end; end;

procedure TTyHueBar.ApplyY(Y: Integer); begin SetHue(TyHueBarToH(Y, ClientRect)); end;

procedure TTyHueBar.Paint;
var
  P: TTyPainter; bmp: TBGRABitmap; xx, yy, w, h, iy: Integer; px: TBGRAPixel;
  bodyS: TTyStyleSet;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    bodyS := CurrentStyle;
    bmp := P.Bitmap; w := bmp.Width; h := bmp.Height;
    if (w > 0) and (h > 0) then
    begin
      for yy := 0 to h - 1 do
      begin
        px := TyColorToBGRA(TyHSVToRGB(TyHueBarToH(yy, Rect(0, 0, w, h)), 1, 1));
        for xx := 0 to w - 1 do
          bmp.SetPixel(xx, yy, px);
      end;
      { Same reasoning as TTyHSVSquare.Paint: the hue ramp is data, the cursor and the
        border are chrome and come from the theme. }
      if (tpBorderColor in bodyS.Present) and (bodyS.BorderWidth > 0) then
        P.StrokeBorder(Rect(0, 0, w, h), 0, bodyS.BorderWidth, bodyS.BorderColor);
      iy := Round(FHue / 360 * Max(1, h - 1));
      P.StrokeBorder(Rect(0, iy - 1, w, iy + 2), 0, Max(1, P.Scale(2)), bodyS.TextColor);
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

{ The quick-pick grid's second row. TTyColorGrid seeds itself with the classic 16-colour
  VGA palette; the everyday tints it has no name for (orange, brown, pink) and a grey ramp
  are exactly what a quick-pick grid is for, so a second row of 16 completes the matrix.
  These literals are DATA, not chrome — a swatch IS the colour it stands for, the same
  distinction the HSV square's pixels are drawn under — so they are spelled out here
  instead of coming from a theme token. }
procedure AddQuickPickColors(AGrid: TTyColorGrid);
var i: Integer; g: Byte;
begin
  AGrid.AddColor(RGBToColor(255, 128,   0));   // orange
  AGrid.AddColor(RGBToColor(255, 192,   0));   // gold
  AGrid.AddColor(RGBToColor(128,  64,   0));   // brown
  AGrid.AddColor(RGBToColor(255, 128, 192));   // pink
  AGrid.AddColor(RGBToColor(128,   0, 255));   // violet
  AGrid.AddColor(RGBToColor( 64, 160, 255));   // sky
  AGrid.AddColor(RGBToColor(  0, 160, 128));   // sea
  AGrid.AddColor(RGBToColor(128, 160,   0));   // moss
  // An even grey ramp; black and white are already in the VGA row, so it runs strictly
  // between them (28..224).
  for i := 1 to 8 do
  begin
    g := i * 28;
    AGrid.AddColor(RGBToColor(g, g, g));
  end;
end;

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
  SecGap    = 12;    // gap above each stacked section (swatch grid, preview)
  SecLblH   = 24;    // a section label (20px tall) plus its gap to the content below
  SecLblW   = 160;   // section-label width — room for a translated caption
  SwCols    = 16;    // quick-pick swatch columns; the palette fills whole rows
  SwCellH   = 24;    // quick-pick swatch cell height (the width follows the content width)
  PrevH     = 44;    // preview swatch height
var
  r: TRect;
  x0, y0, colX, spinW, spinH, rowH, labelW: Integer;
  labelTop, cellW, colRight, contentRight, pickerBottom, previewTop: Integer;
  swTop, swBottom, swCellW, swRows: Integer;
  swLbl: TTyLabel;
  hexLbl: TTyLabel;
  hexLblW, hexLblH: Integer;

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
  var
  cx: Integer;
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
  // Spin/edit height follows the density axis: classic 30 (= TyDlgEditH), modern --control-height.
  spinW := 56; spinH := TyDensityHeight(nil, TyDlgEditH); rowH := spinH + RowGap; labelW := 14;
  // labels are 20px tall; nudge them so their text baseline centres against the (density) spin.
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

  { Hex row: label + a wide edit spanning three cells.
    The label CANNOT reuse labelW. That is 14px, sized for the single letters R/G/B/C/M/Y/K,
    and 'Hex' does not fit in it even in English -- translated it is worse: zh_CN renders
    十六进制 and the box clipped it to a single 十. So this one label sizes itself, and the
    edit starts after whatever width it actually took. }
  hexLbl := MkLabel(rsDlgHex, colX, y0 + labelTop, labelW);
  { MEASURE, do not switch AutoSize on and read Width: this runs while the dialog is being
    constructed, so the form has no handle yet and LCL's AutoSizeDelayed suppresses the
    re-fit -- Width would still be the 14 it was created with, which is how the label first
    came out clipped to a single 十. }
  hexLbl.MeasureCaption(Font.PixelsPerInch, 0, hexLblW, hexLblH);
  hexLblW := Max(labelW, hexLblW + 2);
  hexLbl.Width := hexLblW;
  FHex := TTyEdit.Create(Self);
  FHex.Parent := Self;
  FHex.SetBounds(colX + hexLblW + LblGap, y0,
    3 * cellW + 2 * CellGap - hexLblW - LblGap, spinH);

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
  // Bottom of the top band: the taller of the fixed-size picker and the four editor rows
  // (a modern --control-height can push the Alpha row past the square).
  pickerBottom := Max(y0 + SquareSz, y0 + 3*rowH + spinH);

  // Quick-pick swatches: a full-width labelled grid of common colours beneath the picker.
  // TTyColorGrid divides its client rect into cells (ClientWidth div Columns by
  // ClientHeight div rows), so size it to exact multiples of both — a leftover strip
  // would be dead space that still swallows clicks.
  { swTop is read back off the section label, floored at the designed SecLblH: a theme that
    gives TyLabel padding (or a bigger font) makes the label taller than SecLblH, and a
    literal stride would drop the swatch grid on top of it. }
  swLbl := MkLabel(rsDlgBasicColors, x0, pickerBottom + SecGap, SecLblW);
  swTop := pickerBottom + SecGap + SecLblH;
  if swLbl.Top + swLbl.Height > swTop then swTop := swLbl.Top + swLbl.Height;
  FSwatches := TTyColorGrid.Create(Self);
  FSwatches.Parent := Self;
  FSwatches.Columns := SwCols;
  AddQuickPickColors(FSwatches);
  swRows := (FSwatches.ColorCount + SwCols - 1) div SwCols;
  swCellW := (contentRight - x0) div SwCols;
  FSwatches.SetBounds(x0, swTop, swCellW * SwCols, SwCellH * swRows);
  swBottom := swTop + SwCellH * swRows;

  // Preview: a full-width labelled swatch band beneath the quick-pick grid.
  MkLabel(rsDlgPreview, x0, swBottom + SecGap, SecLblW);
  previewTop := swBottom + SecGap + SecLblH;
  FPreviewRect := Rect(x0, previewTop, contentRight, previewTop + PrevH);

  // Wire change handlers AFTER creation so no premature fires occur.
  FSquare.OnChange := @PickerChanged;
  FHueBar.OnChange := @PickerChanged;
  FSwatches.OnChange := @SwatchChanged;
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

procedure TTyColorForm.ApplyColor(AColor: TTyColor; AFromPicker: Boolean);
begin FColor := AColor; SyncViewsFromColor(AFromPicker); end;

function TTyColorForm.CurrentColor: TTyColor;
begin Result := FColor; end;

function TTyColorForm.HexText: string;
begin Result := TyColorToHex(FColor, False); end;   // RGB-only (no alpha)

procedure TTyColorForm.ApplyHexText(const AHex: string);
begin FHex.Text := AHex; HexChanged(FHex); end;

procedure TTyColorForm.SetPickerHue(AHue: Single);
begin FHueBar.Hue := AHue; end;   // the bar's setter fires OnChange -> PickerChanged

procedure TTyColorForm.SetPickerSV(ASat, AVal: Single);
begin
  // Mirrors a drag inside the square: it writes S/V, invalidates, then fires OnChange.
  FSquare.SetHSV(FSquare.Hue, ASat, AVal);
  PickerChanged(FSquare);
end;

function TTyColorForm.PickerHue: Single;
begin Result := FHueBar.Hue; end;

function TTyColorForm.PickerSat: Single;
begin Result := FSquare.Sat; end;

function TTyColorForm.PickerVal: Single;
begin Result := FSquare.Val; end;

{ Re-seed every view from FColor.

  AFromPicker says the change came FROM the HSV square / hue bar. Those two then own the
  authoritative hue and saturation and must not be written back, because RGB cannot carry
  them: RGB->HSV is not injective at the edges. Black is (any hue, any sat, 0) and every
  grey is (any hue, 0, v), and TyRGBToHSV — like every other implementation — reports the
  conventional hue 0 (red) there. Taking that literally is what used to make the hue bar
  snap back to red the instant the colour went black: click the bar, recompute red-ish
  black, derive hue 0, jump. It also lost the hue on the way down and back up through
  value, so a colour never came back the same.

  When the colour DID arrive from outside the picker (hex, RGB, CMYK, alpha, a swatch, or
  Execute seeding a value) the H/S/V is re-derived, but only the parts that mean anything:
  a derived hue is trusted only when the colour actually has one (v and s both non-zero),
  and a derived saturation only when the colour has a value at all. The rest is kept from
  where the user last left the picker. }
procedure TTyColorForm.SyncViewsFromColor(AFromPicker: Boolean);
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
    if not AFromPicker then
    begin
      TyRGBToHSV(FColor, h, s, v);
      if v <= 0 then
      begin
        h := FHueBar.Hue;       // black: neither hue nor saturation survived the trip
        s := FSquare.Sat;
      end
      else if s <= 0 then
        h := FHueBar.Hue;       // grey / white: the saturation is real, the hue is not
      FSquare.SetHSV(h, s, v);
      FHueBar.Hue := h;
    end;
    // Rings the matching swatch, or clears the ring when the colour is not in the palette.
    FSwatches.Selected := TyColorToLCL(FColor);
    Invalidate;   // repaint the preview swatch
  finally
    FUpdating := False;
  end;
end;

procedure TTyColorForm.PickerChanged(Sender: TObject);
begin
  if FUpdating then Exit;
  // The hue bar owns hue; hand it to the square so its gradient follows. (The square's
  // Hue setter is a bare field write by design — the writer invalidates.)
  if FSquare.Hue <> FHueBar.Hue then
  begin
    FSquare.Hue := FHueBar.Hue;
    FSquare.Invalidate;
  end;
  ApplyColor(TyHSVToRGB(FHueBar.Hue, FSquare.Sat, FSquare.Val, FA.Value), True);
end;

procedure TTyColorForm.SwatchChanged(Sender: TObject);
begin
  if FUpdating then Exit;
  if FSwatches.Selected = clNone then Exit;   // no cell rung (empty grid / cleared)
  // A swatch is an outside source exactly like the hex box: it commits through the same
  // ApplyColor path, so the hex text, the spinners and the preview all follow. The palette
  // carries no alpha, so the dialog's current alpha is kept.
  ApplyColor(TyColorFromLCL(FSwatches.Selected, FA.Value));
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
