unit tyControls.ColorGrid;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics,
  BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.ColorBox;

type
  { A fixed grid of colour swatches: click a cell to select its colour. The colours live
    in a plain FColors array (a fixed palette — no Sorted, no per-item text — so an array
    is the natural store; there is no Items/Objects here). The grid surface, cell outlines
    and the selection ring are all theme-driven (typeKey 'TyPanel' — reuses the panel
    surface, so no new .tycss rule). Selecting fires OnChange; setting Selected in code
    just repaints (no event). }
  TTyColorGrid = class(TTyCustomControl)
  private
    FColors: array of TColor;
    FColumns: Integer;
    FSelectedIndex: Integer;   // -1 = none; identifies the CELL, not a colour value (a palette
                               // may hold the same colour twice — only the clicked cell rings)
    FOnChange: TNotifyEvent;
    procedure SetColumns(AValue: Integer);
    function GetSelected: TColor;
    procedure SetSelected(const AValue: TColor);
    function RowCount: Integer;
  protected
    function GetStyleTypeKey: string; override;   // 'TyPanel'
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    // Append a colour to the grid and repaint.
    procedure AddColor(AColor: TColor);
    // Number of colours in the grid (test seam).
    function ColorCount: Integer;
    // Cell index at device point (AX, AY), or -1 if the point is outside any cell
    // (empty grid, or the trailing gap on the last, partially-filled row). Test seam.
    function CellAt(AX, AY: Integer): Integer;
  published
    // Number of columns; clamped to >= 1.
    property Columns: Integer read FColumns write SetColumns default 8;
    // The selected colour. Writing stores + repaints (no OnChange); a left-click on a
    // cell sets it AND fires OnChange.
    property Selected: TColor read GetSelected write SetSelected;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    // Declared True to match the constructor, so a host's TabStop=False opt-out streams.
    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

{ TTyColorGrid }

constructor TTyColorGrid.Create(AOwner: TComponent);
var
  sl: TStringList;
  i: Integer;
begin
  inherited Create(AOwner);
  // A picker, not a swatch display: clicking a cell selects a colour, so the click has to
  // move focus onto the grid too (TTyCustomControl.MouseDown gates that on TabStop) and
  // Tab has to be able to reach it.
  TabStop := True;
  FColumns := 8;
  FSelectedIndex := -1;
  // Seed the classic 16-colour VGA palette. Build it through the shared ColorBox helper
  // (populates a TStrings with the colours in Objects[]) then copy the colours out into
  // our flat array — we keep no names, just the swatch colours.
  sl := TStringList.Create;
  try
    TyAddDefaultColorPalette(sl);
    SetLength(FColors, sl.Count);
    for i := 0 to sl.Count - 1 do
      FColors[i] := TyColorOfItem(sl, i);
  finally
    sl.Free;
  end;
  Width := 160;
  Height := 120;
end;

function TTyColorGrid.GetStyleTypeKey: string;
begin
  { Own key rather than the borrowed 'TyPanel': a swatch matrix with a selection ring is not a panel surface.
    Added to 'TyPanel's rule block as an extra selector, so every resolved value is
    unchanged — this opens a hook, it does not restyle anything. }
  Result := 'TyColorGrid';
end;

function TTyColorGrid.ColorCount: Integer;
begin
  Result := Length(FColors);
end;

function TTyColorGrid.RowCount: Integer;
begin
  // Ceil(ColorCount / Columns); FColumns is always >= 1.
  Result := (ColorCount + FColumns - 1) div FColumns;
end;

procedure TTyColorGrid.SetColumns(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  if FColumns = AValue then Exit;
  FColumns := AValue;
  Invalidate;
end;

function TTyColorGrid.GetSelected: TColor;
begin
  if (FSelectedIndex >= 0) and (FSelectedIndex <= High(FColors)) then
    Result := FColors[FSelectedIndex]
  else
    Result := clNone;
end;

procedure TTyColorGrid.SetSelected(const AValue: TColor);
var
  i, idx: Integer;
begin
  // Map the colour to the FIRST cell holding it (clNone / not-present -> deselect).
  idx := -1;
  for i := 0 to High(FColors) do
    if FColors[i] = AValue then
    begin
      idx := i;
      Break;
    end;
  if idx = FSelectedIndex then Exit;
  FSelectedIndex := idx;
  Invalidate;   // programmatic set: repaint only, no OnChange
end;

procedure TTyColorGrid.AddColor(AColor: TColor);
begin
  SetLength(FColors, Length(FColors) + 1);
  FColors[High(FColors)] := AColor;
  Invalidate;
end;

function TTyColorGrid.CellAt(AX, AY: Integer): Integer;
var
  cellW, cellH, rows, col, row, idx: Integer;
begin
  Result := -1;
  if ColorCount = 0 then Exit;
  cellW := ClientWidth div FColumns;
  rows := RowCount;
  if (cellW <= 0) or (rows <= 0) then Exit;
  cellH := ClientHeight div rows;
  if cellH <= 0 then Exit;
  if (AX < 0) or (AY < 0) then Exit;
  col := AX div cellW;
  row := AY div cellH;
  if (col < 0) or (col >= FColumns) or (row < 0) or (row >= rows) then Exit;
  idx := row * FColumns + col;
  if (idx < 0) or (idx >= ColorCount) then Exit;   // trailing gap on the last row
  Result := idx;
end;

procedure TTyColorGrid.Paint;
var
  P: TTyPainter;
  st: TTyStyleSet;
  R, cellR: TRect;
  ctx: TBGRACanvas2D;
  outline: TTyColor;
  cellW, cellH, rows, i, col, row, ringW: Integer;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ClientWidth, ClientHeight);
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    st := CurrentStyle;
    // Cell outline + selection ring colour: the theme border colour, but fall back to the
    // text colour when the theme leaves the border transparent (so light swatches and the
    // ring never vanish). Both are theme tokens — no hard-coded chrome colour.
    outline := st.BorderColor;
    if TyAlphaOf(outline) = 0 then outline := st.TextColor;
    // Windowed control: fill the full rect with the parent/form background first, so the
    // gaps around the grid (and any partial last row) read as the form/image-theme photo.
    TyFillParentBg(Self, P, R, st);

    if ColorCount > 0 then
    begin
      cellW := ClientWidth div FColumns;
      rows := RowCount;
      if (cellW > 0) and (rows > 0) then
      begin
        cellH := ClientHeight div rows;
        if cellH > 0 then
        begin
          ctx := P.Bitmap.Canvas2D;
          ringW := Math.Max(2, P.Scale(2));
          for i := 0 to ColorCount - 1 do
          begin
            col := i mod FColumns;
            row := i div FColumns;
            cellR := Rect(col * cellW, row * cellH,
              (col + 1) * cellW, (row + 1) * cellH);
            // Swatch fill (palette DATA colour — a literal is fine here).
            ctx.fillStyle(TyColorToBGRA(TyTColorToTy(FColors[i])));
            ctx.fillRect(cellR.Left, cellR.Top,
              cellR.Right - cellR.Left, cellR.Bottom - cellR.Top);
            // 1px cell outline in the theme border colour (so light swatches still show).
            P.StrokeBorder(cellR, 0, 1, outline);
            // Selection ring: a thicker inset outline in the same theme colour.
            if i = FSelectedIndex then
              P.StrokeBorder(cellR, 0, ringW, outline);
          end;
        end;
      end;
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyColorGrid.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  idx: Integer;
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    idx := CellAt(X, Y);
    if (idx >= 0) and (idx <> FSelectedIndex) then
    begin
      FSelectedIndex := idx;
      Invalidate;
      if Assigned(FOnChange) then FOnChange(Self);
    end;
  end;
end;

end.
