unit tyControls.RibbonGallery;
{$mode objfpc}{$H+}

{ TTyRibbonGallery — the ribbon GALLERY control.

  An inline horizontal row of selectable thumbnail cells (each a caption, and,
  when an icon font supplies one, a glyph), plus a drop-down arrow on the right
  that pops a TALLER grid of ALL items. A ribbon signature control.

  Design mirrors TTyListBox: a windowed surface that hit-tests cells, tracks a
  hovered / selected cell, and paints each cell as a 'TyListItem'-styled tile
  with a per-cell state — the gallery is just a list-of-cells laid out in a row
  (inline) or a grid (popup), so it REUSES the 'TyListBox' typeKey for its own
  surface and 'TyListItem' for each cell (NO new .tycss rule).

  The expanded grid is hosted by a shared TTyDropdownPopup; its content is a
  lightweight private inner control (TTyGalleryGrid) that draws every item in a
  grid and routes a cell click back to the gallery (set ItemIndex, fire OnSelect,
  close the popup). The inner control is created on demand and owned/freed by the
  gallery; it is INTERNAL (never registered on the component palette).

  Three module-level PURE geometry helpers do the layout math and are unit-tested
  headlessly (no GUI, no handle). The GUI popup is only ever shown from a real
  mouse click on a realized control, so headless paint + hit-test never touch it. }

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.Popup, tyControls.IconFont;

type
  TTyRibbonGallery = class;

  { ----------------------------------------------------------------------------
    TTyGalleryGrid — INTERNAL popup-content control (NOT registered on the
    palette). Draws ALL of the owning gallery's items in an AGrid of columns and
    routes a cell click back to the gallery. Reuses the same 'TyListBox' surface
    + 'TyListItem' cell tokens as the inline row, so the popup matches the inline
    look. Owned + managed by the gallery (created on demand, freed in Destroy).
    ---------------------------------------------------------------------------- }
  TTyGalleryGrid = class(TTyCustomControl)
  private
    FGallery: TTyRibbonGallery;
    FHoverIndex: Integer;    // -1 = none
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  protected
    function GetStyleTypeKey: string; override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
  public
    constructor CreateForGallery(AGallery: TTyRibbonGallery);
  end;

  { ----------------------------------------------------------------------------
    TTyRibbonGallery
    ---------------------------------------------------------------------------- }
  TTyRibbonGallery = class(TTyCustomControl)
  private
    FItems: TStringList;
    FGlyphNames: TStringList;
    FIconFont: TTyIconFont;
    FItemIndex: Integer;
    FVisibleColumns: Integer;
    FHoverCell: Integer;     // -1 = none (inline row)
    FOnSelect: TNotifyEvent;
    FPopup: TTyDropdownPopup;   // created on demand; freed in Destroy
    FGrid: TTyGalleryGrid;      // popup content; owned by Self, freed in Destroy
    function GetItemsProp: TStrings;
    function GetGlyphNamesProp: TStrings;
    procedure SetItems(const AValue: TStrings);
    procedure SetGlyphNames(const AValue: TStrings);
    procedure SetIconFont(const AValue: TTyIconFont);
    procedure SetItemIndex(const AValue: Integer);
    procedure SetVisibleColumns(const AValue: Integer);
    procedure ItemsChanged(Sender: TObject);
    function CellWidth: Integer;
    function ArrowWidth: Integer;
    procedure PopupClosed(Sender: TObject);
  protected
    function GetStyleTypeKey: string; override;
    { Core selection seam: set ItemIndex to AIndex (clamped to a valid item or -1)
      and fire OnSelect exactly once when it actually changes. Headless-testable —
      no GUI, no handle. The inline/popup click paths and SetItemIndex all funnel
      through here so selection + the event fire in ONE place. }
    procedure SelectAt(AIndex: Integer);
    { The index of the inline cell (or the arrow zone) under a client point, using
      the SAME geometry the inline paint uses. Returns -1 for no cell, or the
      sentinel ArrowHit for the drop-down arrow zone. }
    function InlineCellAt(AX, AY: Integer): Integer;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    { Glyph name parallel to Items for the visible index AItem, or '' if none. }
    function GlyphNameFor(AItem: Integer): string;
    { Draw one gallery cell (fill for its state + optional glyph + caption) into
      ACellRect. Shared by the inline row and the popup grid so both look identical.
      AIndex indexes Items; AState is the resolved cell state. Glyph rendering is
      gated on a real handle so it is a no-op (safe) headlessly. }
    procedure PaintCell(APainter: TTyPainter; const ACellRect: TRect; AIndex: Integer;
      AStates: TTyStateSet);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Open the expanded grid popup below the control (GUI). No-op with no handle
      or no items, so it is never reached from a headless test. }
    procedure DropDown;
    { Close the popup if open. }
    procedure CloseUp;
    { True while the expanded grid popup is open. }
    function IsDroppedDown: Boolean;
  published
    property Items: TStrings read GetItemsProp write SetItems;
    property GlyphNames: TStrings read GetGlyphNamesProp write SetGlyphNames;
    property IconFont: TTyIconFont read FIconFont write SetIconFont;
    property ItemIndex: Integer read FItemIndex write SetItemIndex default -1;
    property VisibleColumns: Integer read FVisibleColumns write SetVisibleColumns default 3;
    property OnSelect: TNotifyEvent read FOnSelect write FOnSelect;
    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

{ Sentinel returned by InlineCellAt when the point falls in the drop-down arrow
  zone (distinct from -1 = no cell and >=0 = a cell index). }
const
  ArrowHit = -2;

{ Default logical metrics (logical px; scaled by TTyPainter.Scale at paint time). }
const
  TyGalleryCellW    = 56;   // one inline/grid cell width
  TyGalleryArrowW   = 18;   // reserved drop-down arrow zone on the right of the row
  TyGalleryGridCellH = 44;  // one popup-grid cell height
  TyGalleryGlyphPad = 4;    // glyph inset within a cell

{ ----------------------------------------------------------------------------
  Pure geometry helpers — module-level, UNIT-TESTED headlessly. All take/return
  DEVICE-pixel integers so the tests can assert concrete numbers; the control
  scales its logical metrics before calling them.
  ---------------------------------------------------------------------------- }

{ Rect of inline cell AIndex in a left->right row of ACellW-wide cells, AHeightPx
  tall, with an AArrowW-wide drop-down zone RESERVED on the right (cells start at
  x=0). Purely positional — it does not clamp to a visible-column count or a
  control width; the caller decides how many cells to draw. }
function TyGalleryInlineCellRect(AIndex, ACellW, AHeightPx, AArrowW: Integer): TRect;

{ Rect of popup-grid cell AIndex in an ACols-wide grid of ACellW x ACellH cells,
  filled row-major (left->right, top->bottom). ACols < 1 is treated as 1. }
function TyGalleryGridRect(AIndex, ACols, ACellW, ACellH: Integer): TRect;

{ Which item index a click at (AX,AY) falls on in an ACols-wide grid of
  ACellW x ACellH cells holding ACount items (row-major). Returns -1 when the
  point is outside the grid, in a gap, or past the last item. }
function TyGalleryCellAt(AX, AY, ACols, ACellW, ACellH, ACount: Integer): Integer;

implementation

// ---------------------------------------------------------------------------
// Pure geometry helpers
// ---------------------------------------------------------------------------

function TyGalleryInlineCellRect(AIndex, ACellW, AHeightPx, AArrowW{%H-}: Integer): TRect;
begin
  // AArrowW documents the drop-down zone reserved on the RIGHT of the row: cells
  // begin at x=0 and the caller clamps a cell that would spill into
  // [rowRight-AArrowW, rowRight]. Kept in the signature for a self-describing API;
  // this positional helper itself does not clamp (the row width is the caller's).
  if AIndex < 0 then AIndex := 0;
  Result.Left   := AIndex * ACellW;
  Result.Top    := 0;
  Result.Right  := Result.Left + ACellW;
  Result.Bottom := AHeightPx;
end;

function TyGalleryGridRect(AIndex, ACols, ACellW, ACellH: Integer): TRect;
var
  col, row: Integer;
begin
  if ACols < 1 then ACols := 1;
  if AIndex < 0 then AIndex := 0;
  col := AIndex mod ACols;
  row := AIndex div ACols;
  Result.Left   := col * ACellW;
  Result.Top    := row * ACellH;
  Result.Right  := Result.Left + ACellW;
  Result.Bottom := Result.Top + ACellH;
end;

function TyGalleryCellAt(AX, AY, ACols, ACellW, ACellH, ACount: Integer): Integer;
var
  col, row, idx: Integer;
begin
  Result := -1;
  if ACols < 1 then ACols := 1;
  if (ACellW <= 0) or (ACellH <= 0) or (ACount <= 0) then Exit;
  if (AX < 0) or (AY < 0) then Exit;
  col := AX div ACellW;
  row := AY div ACellH;
  if col >= ACols then Exit;               // to the right of the last column
  idx := row * ACols + col;
  if (idx < 0) or (idx >= ACount) then Exit;
  Result := idx;
end;

// ---------------------------------------------------------------------------
// TTyGalleryGrid (internal popup content)
// ---------------------------------------------------------------------------

constructor TTyGalleryGrid.CreateForGallery(AGallery: TTyRibbonGallery);
begin
  inherited Create(AGallery);   // owned by the gallery
  FGallery := AGallery;
  FHoverIndex := -1;
  TabStop := False;
  // Never a designable child of anything — it only lives inside the popup form.
  ControlStyle := ControlStyle + [csNoDesignVisible];
end;

function TTyGalleryGrid.GetStyleTypeKey: string;
begin
  Result := 'TyListBox';   // same surface as the gallery / listbox
end;

procedure TTyGalleryGrid.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  BoxStyle: TTyStyleSet;
  R, CellR: TRect;
  cols, cellW, cellH, i, cnt: Integer;
  states: TTyStateSet;
begin
  if FGallery = nil then Exit;
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    BoxStyle := CurrentStyle;
    DrawFrame(P, R, BoxStyle);

    cnt := FGallery.FItems.Count;
    cols := FGallery.FVisibleColumns;
    if cols < 1 then cols := 1;
    cellW := MulDiv(TyGalleryCellW, APPI, 96);
    cellH := MulDiv(TyGalleryGridCellH, APPI, 96);

    for i := 0 to cnt - 1 do
    begin
      CellR := TyGalleryGridRect(i, cols, cellW, cellH);
      states := [];
      if i = FGallery.FItemIndex then Include(states, tysSelected)
      else if i = FHoverIndex then Include(states, tysHover)
      else Include(states, tysNormal);
      FGallery.PaintCell(P, CellR, i, states);
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyGalleryGrid.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTyGalleryGrid.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  cols, cellW, cellH, idx: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (Button <> mbLeft) or (FGallery = nil) then Exit;
  cols := FGallery.FVisibleColumns;
  if cols < 1 then cols := 1;
  cellW := MulDiv(TyGalleryCellW, Font.PixelsPerInch, 96);
  cellH := MulDiv(TyGalleryGridCellH, Font.PixelsPerInch, 96);
  idx := TyGalleryCellAt(X, Y, cols, cellW, cellH, FGallery.FItems.Count);
  if idx >= 0 then
  begin
    FGallery.SelectAt(idx);
    FGallery.CloseUp;   // route the choice back to the gallery + dismiss the popup
  end;
end;

procedure TTyGalleryGrid.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  cols, cellW, cellH, idx: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if FGallery = nil then Exit;
  cols := FGallery.FVisibleColumns;
  if cols < 1 then cols := 1;
  cellW := MulDiv(TyGalleryCellW, Font.PixelsPerInch, 96);
  cellH := MulDiv(TyGalleryGridCellH, Font.PixelsPerInch, 96);
  idx := TyGalleryCellAt(X, Y, cols, cellW, cellH, FGallery.FItems.Count);
  if idx <> FHoverIndex then
  begin
    FHoverIndex := idx;
    Invalidate;
  end;
end;

procedure TTyGalleryGrid.MouseLeave;
begin
  inherited MouseLeave;
  if FHoverIndex <> -1 then
  begin
    FHoverIndex := -1;
    Invalidate;
  end;
end;

// ---------------------------------------------------------------------------
// TTyRibbonGallery
// ---------------------------------------------------------------------------

constructor TTyRibbonGallery.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TStringList.Create;
  FItems.OnChange := @ItemsChanged;
  FGlyphNames := TStringList.Create;
  FIconFont := nil;
  FItemIndex := -1;
  FVisibleColumns := 3;
  FHoverCell := -1;
  FPopup := nil;    // created on first DropDown
  FGrid := nil;     // created on first DropDown
  TabStop := True;
  Width := 200;
  Height := 40;
end;

destructor TTyRibbonGallery.Destroy;
begin
  // Popup first (it references the grid); the grid is owned by Self so TComponent
  // would free it anyway, but free it explicitly here to keep ordering obvious.
  FPopup.Free;   // Free is nil-safe
  FItems.Free;
  FGlyphNames.Free;
  inherited Destroy;
end;

function TTyRibbonGallery.GetStyleTypeKey: string;
begin
  Result := 'TyListBox';   // REUSE — the gallery is a list-of-cells surface
end;

function TTyRibbonGallery.GetItemsProp: TStrings;
begin
  Result := FItems;
end;

function TTyRibbonGallery.GetGlyphNamesProp: TStrings;
begin
  Result := FGlyphNames;
end;

procedure TTyRibbonGallery.SetItems(const AValue: TStrings);
begin
  FItems.Assign(AValue);   // OnChange -> ItemsChanged recalcs + invalidates
end;

procedure TTyRibbonGallery.SetGlyphNames(const AValue: TStrings);
begin
  FGlyphNames.Assign(AValue);
  Invalidate;
end;

procedure TTyRibbonGallery.SetIconFont(const AValue: TTyIconFont);
begin
  if FIconFont = AValue then Exit;
  if FIconFont <> nil then
    FIconFont.RemoveFreeNotification(Self);
  FIconFont := AValue;
  if FIconFont <> nil then
    FIconFont.FreeNotification(Self);
  Invalidate;
end;

procedure TTyRibbonGallery.SetItemIndex(const AValue: Integer);
begin
  SelectAt(AValue);   // funnel through the one selection seam
end;

procedure TTyRibbonGallery.SetVisibleColumns(const AValue: Integer);
var
  v: Integer;
begin
  v := AValue;
  if v < 1 then v := 1;
  if FVisibleColumns = v then Exit;
  FVisibleColumns := v;
  Invalidate;
end;

procedure TTyRibbonGallery.ItemsChanged(Sender: TObject);
begin
  // Clamp a stale selection if the list shrank; fire OnSelect only if it changed.
  if FItemIndex >= FItems.Count then
    SelectAt(-1);
  Invalidate;
end;

procedure TTyRibbonGallery.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FIconFont) then
    FIconFont := nil;
end;

procedure TTyRibbonGallery.SelectAt(AIndex: Integer);
var
  NewIndex: Integer;
begin
  if (AIndex >= 0) and (AIndex < FItems.Count) then
    NewIndex := AIndex
  else
    NewIndex := -1;
  if NewIndex = FItemIndex then Exit;   // no-op: do NOT fire OnSelect
  FItemIndex := NewIndex;
  Invalidate;
  if Assigned(FOnSelect) then
    FOnSelect(Self);
end;

function TTyRibbonGallery.CellWidth: Integer;
begin
  Result := MulDiv(TyGalleryCellW, Font.PixelsPerInch, 96);
  if Result < 1 then Result := 1;
end;

function TTyRibbonGallery.ArrowWidth: Integer;
begin
  Result := MulDiv(TyGalleryArrowW, Font.PixelsPerInch, 96);
  if Result < 1 then Result := 1;
end;

function TTyRibbonGallery.GlyphNameFor(AItem: Integer): string;
begin
  if (AItem >= 0) and (AItem < FGlyphNames.Count) then
    Result := FGlyphNames[AItem]
  else
    Result := '';
end;

function TTyRibbonGallery.InlineCellAt(AX, AY: Integer): Integer;
var
  cellW, arrowW, rowRight, visN, i: Integer;
  cellR: TRect;
begin
  Result := -1;
  cellW := CellWidth;
  arrowW := ArrowWidth;
  rowRight := Width;
  // Arrow zone occupies the rightmost arrowW of the row.
  if (AX >= rowRight - arrowW) and (AX < rowRight) and (AY >= 0) and (AY < Height) then
    Exit(ArrowHit);
  visN := FVisibleColumns;
  if visN > FItems.Count then visN := FItems.Count;
  for i := 0 to visN - 1 do
  begin
    cellR := TyGalleryInlineCellRect(i, cellW, Height, arrowW);
    // Don't let a cell spill into the arrow zone.
    if cellR.Right > rowRight - arrowW then cellR.Right := rowRight - arrowW;
    if (AX >= cellR.Left) and (AX < cellR.Right)
       and (AY >= cellR.Top) and (AY < cellR.Bottom) then
      Exit(i);
  end;
end;

procedure TTyRibbonGallery.PaintCell(APainter: TTyPainter; const ACellRect: TRect;
  AIndex: Integer; AStates: TTyStateSet);
var
  cellStyle: TTyStyleSet;
  gname: string;
  glyph: TBGRABitmap;
  glyphPx, gx, gy, textLeft, pad: Integer;
  capRect: TRect;
begin
  if (AIndex < 0) or (AIndex >= FItems.Count) then Exit;
  cellStyle := ActiveController.Model.ResolveStyle('TyListItem', '', AStates);

  // Cell fill for its state (selected/hover/normal). Square cells (tiles).
  if tpBackground in cellStyle.Present then
    APainter.FillBackground(ACellRect, cellStyle.Background, 0);

  pad := APainter.Scale(TyGalleryGlyphPad);
  textLeft := ACellRect.Left + APainter.Scale(cellStyle.Padding.Left);

  // Optional glyph thumbnail (left of the caption). Gated on a real handle so it
  // is a safe no-op headlessly (RenderGlyph needs a font + machine anyway).
  gname := GlyphNameFor(AIndex);
  if HandleAllocated and (FIconFont <> nil) and (gname <> '')
     and FIconFont.HasGlyph(gname) then
  begin
    glyphPx := (ACellRect.Bottom - ACellRect.Top) - 2 * pad;
    if glyphPx > (ACellRect.Right - ACellRect.Left) - 2 * pad then
      glyphPx := (ACellRect.Right - ACellRect.Left) - 2 * pad;
    if glyphPx < 1 then glyphPx := 1;
    glyph := FIconFont.RenderGlyph(gname, glyphPx, cellStyle.TextColor);
    try
      gx := ACellRect.Left + pad;
      gy := ACellRect.Top + ((ACellRect.Bottom - ACellRect.Top) - glyph.Height) div 2;
      APainter.Bitmap.PutImage(gx, gy, glyph, dmDrawWithTransparency);
      textLeft := gx + glyph.Width + pad;
    finally
      glyph.Free;
    end;
  end;

  // Caption (fills the rest of the cell).
  capRect := Rect(textLeft, ACellRect.Top,
    ACellRect.Right - APainter.Scale(cellStyle.Padding.Right), ACellRect.Bottom);
  APainter.DrawText(capRect, FItems[AIndex],
    cellStyle.FontName, ResolveFontSize(cellStyle), cellStyle.FontWeight,
    cellStyle.TextColor, taLeftJustify, tlCenter, True);
end;

procedure TTyRibbonGallery.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  BoxStyle: TTyStyleSet;
  R, cellR, arrowR: TRect;
  cellW, arrowW, visN, i, rowRight: Integer;
  states: TTyStateSet;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    BoxStyle := CurrentStyle;
    DrawFrame(P, R, BoxStyle);

    cellW := MulDiv(TyGalleryCellW, APPI, 96);
    arrowW := MulDiv(TyGalleryArrowW, APPI, 96);
    rowRight := R.Right;

    // Inline cells: up to VisibleColumns, left->right, in the space left of the arrow.
    visN := FVisibleColumns;
    if visN > FItems.Count then visN := FItems.Count;
    for i := 0 to visN - 1 do
    begin
      cellR := TyGalleryInlineCellRect(i, cellW, R.Bottom - R.Top, arrowW);
      if cellR.Right > rowRight - arrowW then cellR.Right := rowRight - arrowW;
      if cellR.Left >= cellR.Right then Break;   // no room left before the arrow

      states := [];
      if i = FItemIndex then Include(states, tysSelected)
      else if i = FHoverCell then Include(states, tysHover)
      else Include(states, tysNormal);
      PaintCell(P, cellR, i, states);
    end;

    // Drop-down arrow affordance on the right.
    arrowR := Rect(rowRight - arrowW, R.Top, rowRight, R.Bottom);
    P.DrawGlyph(arrowR, tgChevronDown, BoxStyle.TextColor, 0);

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyRibbonGallery.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTyRibbonGallery.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  hit: Integer;
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  hit := InlineCellAt(X, Y);
  if hit = ArrowHit then
    DropDown
  else if hit >= 0 then
    SelectAt(hit);
  try
    if CanFocus then SetFocus;
  except
    // ignore focus errors in headless/test environments
  end;
end;

procedure TTyRibbonGallery.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  hit, newHover: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  hit := InlineCellAt(X, Y);
  if hit >= 0 then newHover := hit else newHover := -1;   // arrow/none -> no cell hover
  if newHover <> FHoverCell then
  begin
    FHoverCell := newHover;
    Invalidate;
  end;
end;

procedure TTyRibbonGallery.MouseLeave;
begin
  inherited MouseLeave;
  if FHoverCell <> -1 then
  begin
    FHoverCell := -1;
    Invalidate;
  end;
end;

procedure TTyRibbonGallery.PopupClosed(Sender: TObject);
begin
  Invalidate;   // repaint the inline row (selection may have changed)
end;

procedure TTyRibbonGallery.DropDown;
var
  cols, rows, contentW, contentH: Integer;
begin
  // GUI only — never reached headlessly (no handle / no items short-circuits).
  if not HandleAllocated then Exit;
  if FItems.Count = 0 then Exit;

  if FGrid = nil then
    FGrid := TTyGalleryGrid.CreateForGallery(Self);
  // ActiveController (nil-safe: falls back to TyDefaultController). A gallery themed
  // via the global default has Controller=nil; passing that raw would leave the grid
  // + popup unthemed. See the "ActiveController, not raw Controller" gotcha.
  FGrid.Controller := ActiveController;

  if FPopup = nil then
  begin
    FPopup := TTyDropdownPopup.Create;
    FPopup.OnClose := @PopupClosed;
    FPopup.SetContent(FGrid);   // parents the grid into the popup form (once)
  end;
  FPopup.Controller := ActiveController;

  cols := FVisibleColumns;
  if cols < 1 then cols := 1;
  rows := (FItems.Count + cols - 1) div cols;
  contentW := cols * MulDiv(TyGalleryCellW, Font.PixelsPerInch, 96);
  contentH := rows * MulDiv(TyGalleryGridCellH, Font.PixelsPerInch, 96);

  FPopup.Popup(Self, contentW, contentH);
end;

procedure TTyRibbonGallery.CloseUp;
begin
  if FPopup <> nil then
    FPopup.Close;
end;

function TTyRibbonGallery.IsDroppedDown: Boolean;
begin
  Result := (FPopup <> nil) and FPopup.IsOpen;
end;

end.
