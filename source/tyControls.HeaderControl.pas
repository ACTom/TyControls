unit tyControls.HeaderControl;
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller;

const
  // Logical (96ppi) default section width, control height and the resize-grip
  // half-width (px on either side of a boundary that grabs it for a drag-resize).
  TyHeaderDefaultSectionWidth = 100;
  TyHeaderDefaultHeight       = 26;
  TyHeaderResizeGrip          = 4;
  TyHeaderMinSectionWidth     = 16;   // a section can never be dragged narrower than this

type
  { A per-section sort indicator: none, ascending (▲) or descending (▼). }
  TTyHeaderSortDirection = (hsdNone, hsdAscending, hsdDescending);

  { Three points of the sort-indicator triangle (device pixels). }
  TTyHeaderTriangle = array[0..2] of TPoint;

  { A list of section rectangles, returned by the pure tiling function. }
  TTyHeaderRectArray = array of TRect;

  { One header section's model. Alignment is the caption alignment inside the cell. }
  TTyHeaderSection = record
    Text: string;
    Width: Integer;                 // logical px
    Alignment: TAlignment;
    SortDirection: TTyHeaderSortDirection;
  end;
  TTyHeaderSectionArray = array of TTyHeaderSection;

  { Fired when a section body is clicked (not a resize). AIndex is the section. }
  TTyHeaderSectionEvent = procedure(Sender: TObject; AIndex: Integer) of object;
  { Fired continuously while a boundary is dragged and once when released.
    AIndex is the section being resized; AWidth is its new logical width. }
  TTyHeaderResizeEvent = procedure(Sender: TObject; AIndex, AWidth: Integer) of object;

  { TTyHeaderControl — a standalone column-header strip.

    An ordered list of SECTIONS, each with a caption, a logical width, a caption
    alignment and a sort state. The strip draws each section (caption + a right
    divider + a sort-indicator triangle when sorted) and hover-highlights the
    section under the mouse.

    Interaction:
      * click a section body  -> toggles its sort (none->asc->desc->asc...) and
        fires OnSectionClick;
      * drag a section BOUNDARY (within the resize grip) -> resizes the section to
        its left, using MouseCapture; fires OnSectionResize live and SectionResized
        emits it once on release.

    Reuses the 'TyTreeHeader' typeKey for the strip background/border (inherited
    GetStyleTypeKey); each section is drawn with the 'TyTreeHeaderSection' resolved
    style (+ :hover / :selected states) — NO new .tycss. All colours are theme-driven. }

  TTyHeaderControl = class(TTyCustomControl)
  private
    FSections: TTyHeaderSectionArray;
    FHotIndex: Integer;             // section under the mouse (-1 none)
    FResizing: Boolean;
    FResizeIndex: Integer;          // section whose right edge is being dragged
    FResizeStartX: Integer;         // device X where the drag began
    FResizeStartW: Integer;         // logical width of FResizeIndex at drag start
    FOnSectionClick: TTyHeaderSectionEvent;
    FOnSectionResize: TTyHeaderResizeEvent;
    function GetSectionCount: Integer;
    function GetSection(AIndex: Integer): TTyHeaderSection;
    procedure SetSection(AIndex: Integer; const AValue: TTyHeaderSection);
    function GetSectionText(AIndex: Integer): string;
    procedure SetSectionText(AIndex: Integer; const AValue: string);
    function GetSectionWidth(AIndex: Integer): Integer;
    procedure SetSectionWidth(AIndex: Integer; AValue: Integer);
    function GetSortDirection(AIndex: Integer): TTyHeaderSortDirection;
    procedure SetSortDirection(AIndex: Integer; AValue: TTyHeaderSortDirection);
    { Device-px widths (scaled) — what the pure geometry actually tiles. }
    function DeviceWidths: TIntegerDynArray;
  protected
    function GetStyleTypeKey: string; override;   // reuse 'TyTreeHeader'
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    { Append a section; returns its index. }
    function AddSection(const AText: string; AWidth: Integer = TyHeaderDefaultSectionWidth): Integer;
    procedure DeleteSection(AIndex: Integer);
    procedure ClearSections;
    { Cycle a section's sort: none -> asc -> desc -> asc. Clears every OTHER
      section's sort (single-sort strip). Fires nothing; call from your handler. }
    procedure ToggleSort(AIndex: Integer);
    { The device grip half-width at the control's PPI, for tests/hit visualisation. }
    function ScaledGrip: Integer;
    property SectionCount: Integer read GetSectionCount;
    { The full section record. }
    property Sections[AIndex: Integer]: TTyHeaderSection read GetSection write SetSection;
    { Per-facet accessors (also drive Invalidate). }
    property SectionText[AIndex: Integer]: string read GetSectionText write SetSectionText;
    property SectionWidth[AIndex: Integer]: Integer read GetSectionWidth write SetSectionWidth;
    property Sort[AIndex: Integer]: TTyHeaderSortDirection read GetSortDirection write SetSortDirection;
  published
    property OnSectionClick: TTyHeaderSectionEvent read FOnSectionClick write FOnSectionClick;
    property OnSectionResize: TTyHeaderResizeEvent read FOnSectionResize write FOnSectionResize;
    property Align;
  end;

{ ── PURE, headless-tested geometry (all in DEVICE pixels) ──────────────────── }

{ Tile AWidths left-to-right across AClient, each section AWidths[i] wide. The LAST
  section absorbs the remainder when the widths under-fill AClient (so the strip
  always spans the full client), but keeps its OWN width when the widths already
  meet or overrun it. Every returned rect has the client's top/bottom. }
function TyHeaderSectionRects(const AWidths: array of Integer; const AClient: TRect): TTyHeaderRectArray;

{ Index of the section whose horizontal span contains device X (client-relative), or
  -1 when X is left of the first / right of the last section. Boundaries belong to the
  section on their LEFT (so x == a section's right edge is still that section). }
function TyHeaderSectionAtX(const AWidths: array of Integer; const AClient: TRect; X: Integer): Integer;

{ Index of the section boundary being grabbed when the mouse is within AGrip device
  px of an INTERIOR boundary (the right edge of sections 0..n-2 — the final right edge
  is the control edge, not resizable). Returns the LEFT section's index, or -1 when no
  boundary is within the grip. The nearest boundary wins on overlap. }
function TyHeaderResizeEdgeAtX(const AWidths: array of Integer; const AClient: TRect; X, AGrip: Integer): Integer;

{ The three points of the sort-indicator triangle, centered in a small square zone at
  the RIGHT of ACellRect ( before the divider). Up for ascending, down for descending.
  ASizeDev is the triangle's width in device px. Device pixels. }
function TyHeaderSortTriangle(const ACellRect: TRect; ADir: TTyHeaderSortDirection; ASizeDev: Integer): TTyHeaderTriangle;

implementation

{ ---- pure geometry ---- }

function TyHeaderSectionRects(const AWidths: array of Integer; const AClient: TRect): TTyHeaderRectArray;
var
  i, n, x, w, sum, clientW: Integer;
begin
  n := Length(AWidths);
  SetLength(Result, n);
  if n = 0 then Exit;
  clientW := AClient.Right - AClient.Left;
  sum := 0;
  for i := 0 to n - 1 do
  begin
    w := AWidths[i];
    if w < 0 then w := 0;
    Inc(sum, w);
  end;
  x := AClient.Left;
  for i := 0 to n - 1 do
  begin
    w := AWidths[i];
    if w < 0 then w := 0;
    // The last section absorbs any remainder so the strip always fills the client,
    // but never SHRINKS below its own width (a wider-than-client set just overruns).
    if (i = n - 1) and (sum < clientW) then
      w := clientW - (x - AClient.Left);
    Result[i] := Rect(x, AClient.Top, x + w, AClient.Bottom);
    Inc(x, w);
  end;
end;

function TyHeaderSectionAtX(const AWidths: array of Integer; const AClient: TRect; X: Integer): Integer;
var
  rects: TTyHeaderRectArray;
  i: Integer;
begin
  Result := -1;
  rects := TyHeaderSectionRects(AWidths, AClient);
  for i := 0 to High(rects) do
    // Half-open [Left, Right) so a boundary belongs to the section on its left ONLY
    // at its own right edge via the <= on the final section handled below.
    if (X >= rects[i].Left) and (X < rects[i].Right) then
      Exit(i);
  // Exact right edge of the last section still counts as that section.
  if (Length(rects) > 0) and (X = rects[High(rects)].Right) then
    Result := High(rects);
end;

function TyHeaderResizeEdgeAtX(const AWidths: array of Integer; const AClient: TRect; X, AGrip: Integer): Integer;
var
  rects: TTyHeaderRectArray;
  i, edge, dist, best, bestDist: Integer;
begin
  Result := -1;
  if AGrip < 0 then AGrip := 0;
  rects := TyHeaderSectionRects(AWidths, AClient);
  best := -1;
  bestDist := MaxInt;
  // Interior boundaries only: the right edge of sections 0..n-2. The final section's
  // right edge is the control edge and is not a resizable boundary.
  for i := 0 to High(rects) - 1 do
  begin
    edge := rects[i].Right;
    dist := Abs(X - edge);
    if (dist <= AGrip) and (dist < bestDist) then
    begin
      bestDist := dist;
      best := i;
    end;
  end;
  Result := best;
end;

function TyHeaderSortTriangle(const ACellRect: TRect; ADir: TTyHeaderSortDirection; ASizeDev: Integer): TTyHeaderTriangle;
var
  zone, half, cx, cy, margin: Integer;
begin
  zone := ASizeDev;
  if zone < 4 then zone := 4;
  if Odd(zone) then Dec(zone);       // even -> the apex lands on a pixel
  half := zone div 2;
  // Centre the glyph in a right-hand gutter, one glyph-width in from the right edge,
  // vertically centred in the cell.
  margin := zone;
  cx := ACellRect.Right - margin;
  cy := (ACellRect.Top + ACellRect.Bottom) div 2;
  if ADir = hsdDescending then
  begin
    // Down-pointing: base across the top, apex at bottom-centre.
    Result[0] := Point(cx - half, cy - half div 2);
    Result[1] := Point(cx + half, cy - half div 2);
    Result[2] := Point(cx,        cy + half div 2 + half);
  end
  else
  begin
    // Up-pointing (ascending, and the fallback for hsdNone though callers gate on it).
    Result[0] := Point(cx - half, cy + half div 2 + half);
    Result[1] := Point(cx + half, cy + half div 2 + half);
    Result[2] := Point(cx,        cy - half div 2);
  end;
end;

{ ---- TTyHeaderControl ---- }

constructor TTyHeaderControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHotIndex := -1;
  FResizeIndex := -1;
  Width := 300;
  Height := TyDensityHeight(ActiveController, TyHeaderDefaultHeight);
  TabStop := False;
end;

function TTyHeaderControl.GetStyleTypeKey: string;
begin
  Result := 'TyTreeHeader';   // REUSE — the strip bg/border comes from this token
end;

function TTyHeaderControl.GetSectionCount: Integer;
begin
  Result := Length(FSections);
end;

function TTyHeaderControl.GetSection(AIndex: Integer): TTyHeaderSection;
begin
  if (AIndex >= 0) and (AIndex < Length(FSections)) then
    Result := FSections[AIndex]
  else
    Result := Default(TTyHeaderSection);
end;

procedure TTyHeaderControl.SetSection(AIndex: Integer; const AValue: TTyHeaderSection);
begin
  if (AIndex < 0) or (AIndex >= Length(FSections)) then Exit;
  FSections[AIndex] := AValue;
  if FSections[AIndex].Width < TyHeaderMinSectionWidth then
    FSections[AIndex].Width := TyHeaderMinSectionWidth;
  Invalidate;
end;

function TTyHeaderControl.GetSectionText(AIndex: Integer): string;
begin
  Result := GetSection(AIndex).Text;
end;

procedure TTyHeaderControl.SetSectionText(AIndex: Integer; const AValue: string);
begin
  if (AIndex < 0) or (AIndex >= Length(FSections)) then Exit;
  if FSections[AIndex].Text = AValue then Exit;
  FSections[AIndex].Text := AValue;
  Invalidate;
end;

function TTyHeaderControl.GetSectionWidth(AIndex: Integer): Integer;
begin
  Result := GetSection(AIndex).Width;
end;

procedure TTyHeaderControl.SetSectionWidth(AIndex: Integer; AValue: Integer);
begin
  if (AIndex < 0) or (AIndex >= Length(FSections)) then Exit;
  if AValue < TyHeaderMinSectionWidth then AValue := TyHeaderMinSectionWidth;
  if FSections[AIndex].Width = AValue then Exit;
  FSections[AIndex].Width := AValue;
  Invalidate;
end;

function TTyHeaderControl.GetSortDirection(AIndex: Integer): TTyHeaderSortDirection;
begin
  Result := GetSection(AIndex).SortDirection;
end;

procedure TTyHeaderControl.SetSortDirection(AIndex: Integer; AValue: TTyHeaderSortDirection);
begin
  if (AIndex < 0) or (AIndex >= Length(FSections)) then Exit;
  if FSections[AIndex].SortDirection = AValue then Exit;
  FSections[AIndex].SortDirection := AValue;
  Invalidate;
end;

function TTyHeaderControl.DeviceWidths: TIntegerDynArray;
var
  i: Integer;
begin
  SetLength(Result, Length(FSections));
  for i := 0 to High(FSections) do
    Result[i] := MulDiv(FSections[i].Width, Font.PixelsPerInch, 96);
end;

function TTyHeaderControl.ScaledGrip: Integer;
begin
  Result := MulDiv(TyHeaderResizeGrip, Font.PixelsPerInch, 96);
  if Result < 1 then Result := 1;
end;

function TTyHeaderControl.AddSection(const AText: string; AWidth: Integer): Integer;
begin
  if AWidth < TyHeaderMinSectionWidth then AWidth := TyHeaderMinSectionWidth;
  Result := Length(FSections);
  SetLength(FSections, Result + 1);
  FSections[Result].Text := AText;
  FSections[Result].Width := AWidth;
  FSections[Result].Alignment := taLeftJustify;
  FSections[Result].SortDirection := hsdNone;
  Invalidate;
end;

procedure TTyHeaderControl.DeleteSection(AIndex: Integer);
var
  i: Integer;
begin
  if (AIndex < 0) or (AIndex >= Length(FSections)) then Exit;
  for i := AIndex to High(FSections) - 1 do
    FSections[i] := FSections[i + 1];
  SetLength(FSections, Length(FSections) - 1);
  if FHotIndex >= Length(FSections) then FHotIndex := -1;
  Invalidate;
end;

procedure TTyHeaderControl.ClearSections;
begin
  SetLength(FSections, 0);
  FHotIndex := -1;
  Invalidate;
end;

procedure TTyHeaderControl.ToggleSort(AIndex: Integer);
var
  i: Integer;
  cur: TTyHeaderSortDirection;
begin
  if (AIndex < 0) or (AIndex >= Length(FSections)) then Exit;
  cur := FSections[AIndex].SortDirection;
  // Single-sort strip: clear every other section first.
  for i := 0 to High(FSections) do
    if i <> AIndex then FSections[i].SortDirection := hsdNone;
  case cur of
    hsdNone:       FSections[AIndex].SortDirection := hsdAscending;
    hsdAscending:  FSections[AIndex].SortDirection := hsdDescending;
    hsdDescending: FSections[AIndex].SortDirection := hsdAscending;
  end;
  Invalidate;
end;

procedure TTyHeaderControl.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, secStyle, hotStyle: TTyStyleSet;
  R, cellRect, textRect, clipR: TRect;
  rects: TTyHeaderRectArray;
  widths: TIntegerDynArray;
  i, padL, padR, sortSize, gutter: Integer;
  tri: TTyHeaderTriangle;
  ctx: TBGRACanvas2D;
  txtColor, dividerColor: TTyColor;
  useSecColor: Boolean;
  fontName: string;
  fontSize, fontWeight: Integer;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    // Strip background + border from 'TyTreeHeader'.
    DrawFrame(P, R, S);

    // Section styles (base + hover). :selected is available too but the strip uses
    // hover for the pointer; a sorted section is signalled by the triangle, not fill.
    secStyle := ActiveController.Model.ResolveStyle('TyTreeHeaderSection', '', []);
    hotStyle := ActiveController.Model.ResolveStyle('TyTreeHeaderSection', '', [tysHover]);

    // Device-px widths -> tiled rects. Pure math == hit-test geometry.
    widths := DeviceWidths;
    rects := TyHeaderSectionRects(widths, R);

    padL := P.Scale(6);
    padR := P.Scale(6);
    sortSize := P.Scale(9);
    dividerColor := S.BorderColor;

    for i := 0 to High(rects) do
    begin
      cellRect := rects[i];
      if cellRect.Right <= cellRect.Left then Continue;

      // Hover fill for the hot section.
      if (i = FHotIndex) and (tpBackground in hotStyle.Present) then
        P.FillBackground(cellRect, hotStyle.Background, 0)
      else if tpBackground in secStyle.Present then
        P.FillBackground(cellRect, secStyle.Background, 0);

      // Resolve text facets — section style if present, else the strip style.
      useSecColor := tpTextColor in secStyle.Present;
      if useSecColor then
      begin
        txtColor := secStyle.TextColor;
        fontName := secStyle.FontName;
        fontSize := ResolveFontSize(secStyle);
        fontWeight := secStyle.FontWeight;
      end
      else
      begin
        txtColor := S.TextColor;
        fontName := S.FontName;
        fontSize := ResolveFontSize(S);
        fontWeight := S.FontWeight;
      end;

      // A sorted section reserves a right gutter for the triangle.
      gutter := 0;
      if FSections[i].SortDirection <> hsdNone then
        gutter := sortSize * 2;

      textRect := Rect(cellRect.Left + padL, cellRect.Top,
        cellRect.Right - padR - gutter, cellRect.Bottom);
      // Clip the caption so it never bleeds past the strip's right edge.
      clipR := textRect;
      if clipR.Right > R.Right then clipR.Right := R.Right;
      if (FSections[i].Text <> '') and (clipR.Left < clipR.Right) then
        P.DrawText(clipR, FSections[i].Text, fontName, fontSize, fontWeight,
          txtColor, FSections[i].Alignment, tlCenter, True);

      // Sort-indicator triangle.
      if FSections[i].SortDirection <> hsdNone then
      begin
        tri := TyHeaderSortTriangle(cellRect, FSections[i].SortDirection, sortSize);
        ctx := P.Bitmap.Canvas2D;
        ctx.beginPath;
        ctx.moveTo(tri[0].X + 0.5, tri[0].Y + 0.5);
        ctx.lineTo(tri[1].X + 0.5, tri[1].Y + 0.5);
        ctx.lineTo(tri[2].X + 0.5, tri[2].Y + 0.5);
        ctx.closePath;
        ctx.fillStyle(TyColorToBGRA(txtColor));
        ctx.fill;
      end;

      // Right divider (not after the last section).
      if i < High(rects) then
        P.Bitmap.DrawLine(cellRect.Right - 1, cellRect.Top,
          cellRect.Right - 1, cellRect.Bottom, TyColorToBGRA(dividerColor), False);
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyHeaderControl.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTyHeaderControl.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  widths: TIntegerDynArray;
  edge: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (Button <> mbLeft) or not Enabled then Exit;
  widths := DeviceWidths;
  // A boundary within the grip starts a resize; otherwise a plain section press.
  edge := TyHeaderResizeEdgeAtX(widths, ClientRect, X, ScaledGrip);
  if edge >= 0 then
  begin
    FResizing := True;
    FResizeIndex := edge;
    FResizeStartX := X;
    FResizeStartW := FSections[edge].Width;
    if HandleAllocated then MouseCapture := True;
  end;
end;

procedure TTyHeaderControl.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  widths: TIntegerDynArray;
  deltaLogical, newW, edge, hit: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if FResizing and (FResizeIndex >= 0) and (FResizeIndex < Length(FSections)) then
  begin
    // Convert the device-px drag delta to logical px and apply to the start width.
    deltaLogical := MulDiv(X - FResizeStartX, 96, Font.PixelsPerInch);
    newW := FResizeStartW + deltaLogical;
    if newW < TyHeaderMinSectionWidth then newW := TyHeaderMinSectionWidth;
    if FSections[FResizeIndex].Width <> newW then
    begin
      FSections[FResizeIndex].Width := newW;
      if Assigned(FOnSectionResize) then FOnSectionResize(Self, FResizeIndex, newW);
      Invalidate;
    end;
    Exit;
  end;
  // Not resizing: hover-track. A boundary within the grip switches the cursor to a
  // horizontal resize; otherwise track the hot section for the highlight.
  widths := DeviceWidths;
  edge := TyHeaderResizeEdgeAtX(widths, ClientRect, X, ScaledGrip);
  if edge >= 0 then
    Cursor := crHSplit
  else
    Cursor := crDefault;
  hit := TyHeaderSectionAtX(widths, ClientRect, X);
  if hit <> FHotIndex then
  begin
    FHotIndex := hit;
    Invalidate;
  end;
end;

procedure TTyHeaderControl.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  widths: TIntegerDynArray;
  hit, movedX: Integer;
begin
  // Tear down a resize on ANY button-up (not just left): the control holds MouseCapture during the
  // drag, so a right/middle button-up is delivered here too — gating on mbLeft would leave the
  // resize armed and the mouse captured, sticking the strip in resize mode.
  if FResizing then
  begin
    FResizing := False;
    if HandleAllocated and (MouseCapture) then MouseCapture := False;
    // Fire the final resize once on release.
    if (FResizeIndex >= 0) and (FResizeIndex < Length(FSections))
       and Assigned(FOnSectionResize) then
      FOnSectionResize(Self, FResizeIndex, FSections[FResizeIndex].Width);
    FResizeIndex := -1;
    inherited MouseUp(Button, Shift, X, Y);
    Exit;
  end;
  inherited MouseUp(Button, Shift, X, Y);
  if (Button <> mbLeft) or not Enabled then Exit;
  // A plain click (no drag) on a section body toggles its sort and fires the event.
  widths := DeviceWidths;
  movedX := TyHeaderResizeEdgeAtX(widths, ClientRect, X, ScaledGrip);
  if movedX >= 0 then Exit;   // released on a boundary, not a body click
  hit := TyHeaderSectionAtX(widths, ClientRect, X);
  if hit >= 0 then
  begin
    ToggleSort(hit);
    if Assigned(FOnSectionClick) then FOnSectionClick(Self, hit);
  end;
end;

procedure TTyHeaderControl.MouseLeave;
begin
  inherited MouseLeave;
  if FHotIndex <> -1 then
  begin
    FHotIndex := -1;
    Invalidate;
  end;
  Cursor := crDefault;
end;

end.
