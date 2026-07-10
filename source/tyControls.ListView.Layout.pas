unit tyControls.ListView.Layout;
{$mode objfpc}{$H+}
{ Pure, headless layout / hit-test / navigation math for TTyListView.

  This unit knows nothing about windows, painters, handles or the LCL. The control
  converts logical sizes to DEVICE pixels (via Painter.Scale), fills a TTyListMetrics
  record and calls these free functions to get geometry and indices back. Everything
  here is deterministic and therefore fully unit-testable without a GUI.

  Two coordinate spaces appear throughout; every function's doc comment states which
  one it uses:
    - client coords : pixels relative to the control's client area top-left. The item
                      region starts at y = HeaderH (report mode) or y = 0 (all other
                      modes, which must pass HeaderH = 0). Scroll offset is already
                      folded in by the geometry functions.
    - content coords: the un-scrolled, header-relative virtual grid. Never returned to
                      callers directly; used internally to invert geometry.
    - display position: 0-based slot in the (possibly sorted) visual order. This is what
                      every geometry / hit / navigation function takes and returns. The
                      control maps display position <-> stable item index via its FOrder.
    - item index    : stable index into the underlying data. Only TyListPrefixMatch and
                      TyListCompareCells operate on it (via callbacks / raw text).

  A note on the sentinel: functions that answer "which item?" return -1 to mean
  "no item here" — this covers a point in the header band, a point in the inter-cell
  gap, and a point past the populated cells. It is never a clamp; callers get -1, not
  the nearest item. }
interface

uses
  Classes, SysUtils, Math, Types, LazUTF8, tyControls.Columns;

type
  { The five view styles. Flow direction is derived from the style, see the table
    in TyListItemRect. }
  TTyListViewStyle = (lvsIcon, lvsSmallIcon, lvsList, lvsReport, lvsTile);

  { Keyboard navigation intents fed to TyListNavigate. }
  TTyListNavKey = (lnLeft, lnRight, lnUp, lnDown, lnHome, lnEnd, lnPageUp, lnPageDown);

  { Comparison mode for a report cell, used by TyListCompareCells. }
  TTyListSortKind = (lskText, lskNumber, lskDateTime);

  { What part of an item a client point landed on. Not consumed by this unit's
    functions (the control classifies within a cell); declared here so the control
    and its tests share one enumeration. }
  TTyListHitPart = (lhpNowhere, lhpIcon, lhpLabel, lhpCheck, lhpHeader, lhpDivider);

  { A function cannot return an anonymous "array of Integer" in FPC, so the named
    type is declared once and used as every array-returning result. }
  TTyIntArray = array of Integer;

  { Text accessor the control hands to TyListPrefixMatch so the whole first-letter
    search loop is headless-testable. AIndex is a stable item index. }
  TTyItemTextFn = function(AIndex: Integer): string of object;

  { All fields are DEVICE pixels. The control fills this once per layout pass.

    CellW/CellH are the cell's drawable box, excluding the gap that follows it;
    a cell occupies [x, x+CellW] x [y, y+CellH] and the gap is the strip after it.
    Pitch is CellW+HGap horizontally and CellH+VGap vertically. }
  TTyListMetrics = record
    ViewStyle:   TTyListViewStyle;
    ViewportW:   Integer;   { client width, visible scrollbar already subtracted }
    ViewportH:   Integer;   { client height, visible scrollbar subtracted, includes HeaderH }
    CellW:       Integer;   { cell width  (without HGap) }
    CellH:       Integer;   { cell height (without VGap) }
    HGap:        Integer;
    VGap:        Integer;
    RowH:        Integer;   { row height for lvsReport }
    HeaderH:     Integer;   { non-zero only for lvsReport; every other mode passes 0 }
    ReportWidth: Integer;   { lvsReport content width = Columns.TotalWidth }
    IconPx:      Integer;   { icon edge length, input to TyListCellSize }
    LabelH:      Integer;   { label line height, input to TyListCellSize }
    Pad:         Integer;   { cell inner padding, input to TyListCellSize }
  end;

{ Cell dimensions derived from IconPx/LabelH/Pad (or ReportWidth/RowH for report),
  which the control writes back into M.CellW/M.CellH before calling anything else. }
function TyListCellSize(const M: TTyListMetrics): TSize;

{ How many cells fit along one track (a row in row-major, a column in column-major).
  Always >= 1, even if the viewport is narrower/shorter than a single cell, and even
  if a pitch is <= 0 (division guarded). Report mode is always 1. }
function TyListTracks(const M: TTyListMetrics): Integer;

{ Scrollable content size of the ITEM region only (header excluded), for feeding the
  scrollbars. ACount = 0 yields (0,0). }
function TyListContentExtent(ACount: Integer; const M: TTyListMetrics): TSize;

{ THE single geometry source: both painting and hit-testing go through it, so the two
  can never drift. Returns the cell rect in CLIENT coords (scroll subtracted, HeaderH
  added). ADisplayPos outside [0, ACount-1] returns Rect(0,0,0,0). }
function TyListItemRect(ADisplayPos, ACount: Integer; const M: TTyListMetrics;
  AScrollX, AScrollY: Integer): TRect;

{ Inverse of TyListItemRect. Takes a CLIENT-coord point, returns the display position
  under it, or -1. -1 means: inside the header band, inside an inter-cell gap, or past
  the last populated cell. It computes a candidate position then VERIFIES it by calling
  TyListItemRect + PtInRect — the mechanical guarantee against paint/hit drift. }
function TyListItemAt(const APt: TPoint; ACount: Integer; const M: TTyListMetrics;
  AScrollX, AScrollY: Integer): Integer;

{ O(1) closed-form virtualization window. Returns the CLOSED display-position interval
  [AFirst, ALast] of every cell that intersects the viewport (partly visible counts).
  ACount = 0 -> False with both out params -1. Also False (no reset) when the clamped
  interval is empty. AFirst is clamped to >= 0, ALast to <= ACount-1. }
function TyListVisibleRange(ACount: Integer; const M: TTyListMetrics;
  AScrollX, AScrollY: Integer; out AFirst, ALast: Integer): Boolean;

{ 2-D grid navigation. Takes and returns a display position.
  - ACount = 0 -> -1.
  - ACurrent < 0 is treated as "no selection": any arrow/page key lands on 0.
  - Home -> 0, End -> ACount-1 (always move).
  - Arrow keys that would leave the grid do NOT move (return ACurrent), no clamp.
  - PageUp/PageDown move by one viewport of cells and DO clamp to [0, ACount-1]. }
function TyListNavigate(ACurrent, ACount: Integer; AKey: TTyListNavKey;
  const M: TTyListMetrics): Integer;

{ Ordered bounds of a shift-range. Either argument < 0 -> False, out params -1.
  Otherwise ALo = Min, AHi = Max, True. Operates on plain positions/indices. }
function TyListRangeBounds(AAnchor, ATarget: Integer; out ALo, AHi: Integer): Boolean;

{ Marquee (rubber-band) selection. Returns every display position whose cell rect
  INTERSECTS ABox (touching an edge counts), in ASCENDING order. In icon flow a box
  over a 2x2 block yields 4 non-adjacent positions, which is why the result is an
  array, not an interval. ABox is in client coords and may be given in any corner
  order (normalized internally). No hit -> length-0 array. Never iterates ACount:
  the row/column span is derived from ABox and only those cells are enumerated. }
function TyListMarqueeHits(const ABox: TRect; ACount: Integer; const M: TTyListMetrics;
  AScrollX, AScrollY: Integer): TTyIntArray;

{ First-letter (type-ahead) search over item indices. Loops itself (does not rely on
  the caller looping) so the whole search is testable. Scans ACount items starting at
  AStartAfter+1, wrapping once. Case-insensitive UTF-8 prefix compare. Returns the
  matching item index, or -1. Empty prefix or ACount <= 0 -> -1. AStartAfter may be -1
  to start at index 0. }
function TyListPrefixMatch(AGetText: TTyItemTextFn; ACount, AStartAfter: Integer;
  const APrefix: string): Integer;

{ Three-way comparison of two report cell strings.
  - lskText: case-insensitive UTF-8 compare.
  - lskNumber: both parse as float (locale-independent '.') -> numeric compare; only
    one parses -> the parseable one sorts first; neither -> fall back to text.
  - lskDateTime: same rule with TryStrToDateTime; unparseable sorts after parseable.
  - sdDescending negates the whole result.
  Equal -> 0 (the caller breaks ties by stable item index). }
function TyListCompareCells(const A, B: string; AKind: TTyListSortKind;
  ADir: TTySortDirection): Integer;

{ Report-mode row hit on a raw Y (client coord). AY < AHeaderH -> -1. ARowH <= 0 -> -1.
  Otherwise (AY - AHeaderH + AScrollY) div ARowH, or -1 if outside [0, ARowCount-1]. }
function TyReportRowAt(AY, AScrollY, AHeaderH, ARowH, ARowCount: Integer): Integer;

implementation

{ ---------------------------------------------------------------------------
  Flow classification
  --------------------------------------------------------------------------- }

{ Row-major: cells flow left-to-right and wrap to the next row (icon/smallicon/tile). }
function FlowIsRowMajor(AStyle: TTyListViewStyle): Boolean; inline;
begin
  Result := AStyle in [lvsIcon, lvsSmallIcon, lvsTile];
end;

{ Column-major: cells flow top-to-bottom and wrap to the next column (list). }
function FlowIsColMajor(AStyle: TTyListViewStyle): Boolean; inline;
begin
  Result := AStyle = lvsList;
end;

{ Inclusive intersection test — two rects "touch" if they share so much as an edge. }
function RectsTouch(const A, B: TRect): Boolean; inline;
begin
  Result := (A.Left <= B.Right) and (A.Right >= B.Left) and
            (A.Top  <= B.Bottom) and (A.Bottom >= B.Top);
end;

{ ---------------------------------------------------------------------------
  TyListCellSize
  --------------------------------------------------------------------------- }

function TyListCellSize(const M: TTyListMetrics): TSize;
begin
  case M.ViewStyle of
    lvsIcon:
      begin
        { icon on top, label below }
        Result.cx := M.IconPx + 4 * M.Pad;
        Result.cy := M.IconPx + M.LabelH + 3 * M.Pad;
      end;
    lvsSmallIcon, lvsList:
      begin
        { icon at left, single label at right }
        Result.cx := M.IconPx + 12 * M.Pad;
        Result.cy := Max(M.IconPx, M.LabelH) + 2 * M.Pad;
      end;
    lvsTile:
      begin
        { icon at left, two text lines at right }
        Result.cx := M.IconPx + 20 * M.Pad;
        Result.cy := Max(M.IconPx, 2 * M.LabelH) + 2 * M.Pad;
      end;
  else
    { lvsReport: a full-width row }
    Result.cx := M.ReportWidth;
    Result.cy := M.RowH;
  end;
end;

{ ---------------------------------------------------------------------------
  TyListTracks
  --------------------------------------------------------------------------- }

function TyListTracks(const M: TTyListMetrics): Integer;
var
  PitchX, PitchY: Integer;
begin
  if M.ViewStyle = lvsReport then
    Exit(1);

  if FlowIsColMajor(M.ViewStyle) then
  begin
    { column-major: how many cells stack vertically in the item region }
    PitchY := M.CellH + M.VGap;
    if PitchY <= 0 then
      Result := 1
    else
      Result := Max(1, ((M.ViewportH - M.HeaderH) + M.VGap) div PitchY);
  end
  else
  begin
    { row-major: how many cells fit horizontally }
    PitchX := M.CellW + M.HGap;
    if PitchX <= 0 then
      Result := 1
    else
      Result := Max(1, (M.ViewportW + M.HGap) div PitchX);
  end;
end;

{ ---------------------------------------------------------------------------
  TyListContentExtent
  --------------------------------------------------------------------------- }

function TyListContentExtent(ACount: Integer; const M: TTyListMetrics): TSize;
var
  Tracks, Lines, PitchX, PitchY: Integer;
begin
  Result.cx := 0;
  Result.cy := 0;
  if ACount <= 0 then
    Exit;

  if M.ViewStyle = lvsReport then
  begin
    Result.cx := M.ReportWidth;
    Result.cy := ACount * M.RowH;
    Exit;
  end;

  Tracks := TyListTracks(M);   { >= 1, safe divisor }
  if FlowIsColMajor(M.ViewStyle) then
  begin
    { column-major: columns grow to the right }
    PitchX := M.CellW + M.HGap;
    Lines := (ACount + Tracks - 1) div Tracks;   { Ceil(ACount / Tracks) }
    Result.cx := Max(0, Lines * PitchX - M.HGap);
    Result.cy := M.ViewportH - M.HeaderH;
  end
  else
  begin
    { row-major: rows grow downward }
    PitchY := M.CellH + M.VGap;
    Lines := (ACount + Tracks - 1) div Tracks;   { Ceil(ACount / Tracks) }
    Result.cx := M.ViewportW;
    Result.cy := Max(0, Lines * PitchY - M.VGap);
  end;
end;

{ ---------------------------------------------------------------------------
  TyListItemRect
  --------------------------------------------------------------------------- }

function TyListItemRect(ADisplayPos, ACount: Integer; const M: TTyListMetrics;
  AScrollX, AScrollY: Integer): TRect;
var
  Tracks, col, row, PitchX, PitchY: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if (ADisplayPos < 0) or (ADisplayPos >= ACount) then
    Exit;

  if M.ViewStyle = lvsReport then
  begin
    Result.Left   := -AScrollX;
    Result.Top    := M.HeaderH + ADisplayPos * M.RowH - AScrollY;
    Result.Right  := Result.Left + M.ReportWidth;
    Result.Bottom := Result.Top + M.RowH;
    Exit;
  end;

  Tracks := TyListTracks(M);
  PitchX := M.CellW + M.HGap;
  PitchY := M.CellH + M.VGap;

  if FlowIsColMajor(M.ViewStyle) then
  begin
    row := ADisplayPos mod Tracks;
    col := ADisplayPos div Tracks;
  end
  else
  begin
    col := ADisplayPos mod Tracks;
    row := ADisplayPos div Tracks;
  end;

  Result.Left   := col * PitchX - AScrollX;
  Result.Top    := M.HeaderH + row * PitchY - AScrollY;
  Result.Right  := Result.Left + M.CellW;
  Result.Bottom := Result.Top + M.CellH;
end;

{ ---------------------------------------------------------------------------
  TyListItemAt
  --------------------------------------------------------------------------- }

function TyListItemAt(const APt: TPoint; ACount: Integer; const M: TTyListMetrics;
  AScrollX, AScrollY: Integer): Integer;
var
  Tracks, col, row, cand, PitchX, PitchY: Integer;
  cell: TRect;
begin
  Result := -1;
  if ACount <= 0 then
    Exit;
  { Nothing above the ITEM AREA is an item, and the item area starts at HeaderH (which is 0
    for every style but lvsReport). One rule covers both cases: in report mode it refuses the
    header band, elsewhere it refuses points above the client.

    Note this deliberately wins over the PtInRect verify below. Under a vertical scroll a
    report row's rect slides up UNDER the header -- row 3 at ScrollY=95 spans Y=-1..23 -- so
    a click at Y=0 is inside both the header and that row. The header must win; a row hidden
    beneath it is not clickable. That is also why the paint/hit-test inverse below only holds
    for a probe point clamped into the item area. }
  if APt.Y < M.HeaderH then
    Exit;

  if M.ViewStyle = lvsReport then
  begin
    if M.RowH <= 0 then
      Exit;
    cand := (APt.Y - M.HeaderH + AScrollY) div M.RowH;
  end
  else
  begin
    Tracks := TyListTracks(M);
    PitchX := M.CellW + M.HGap;
    PitchY := M.CellH + M.VGap;
    if (PitchX <= 0) or (PitchY <= 0) then
      Exit;   { degenerate cells: nothing is hittable }
    col := (APt.X + AScrollX) div PitchX;
    row := (APt.Y - M.HeaderH + AScrollY) div PitchY;
    if FlowIsColMajor(M.ViewStyle) then
      cand := col * Tracks + row
    else
      cand := row * Tracks + col;
  end;

  if (cand < 0) or (cand >= ACount) then
    Exit;

  { Verify the candidate against the SAME geometry the painter uses. This rejects
    inter-cell gaps, points beyond ReportWidth, and any candidate that arithmetic
    produced but whose real cell does not contain the point. }
  cell := TyListItemRect(cand, ACount, M, AScrollX, AScrollY);
  if PtInRect(cell, APt) then
    Result := cand;
end;

{ ---------------------------------------------------------------------------
  TyListVisibleRange
  --------------------------------------------------------------------------- }

function TyListVisibleRange(ACount: Integer; const M: TTyListMetrics;
  AScrollX, AScrollY: Integer; out AFirst, ALast: Integer): Boolean;
var
  Tracks, PitchX, PitchY, firstLine, lastLine, vh: Integer;
begin
  AFirst := -1;
  ALast := -1;
  Result := False;
  if ACount <= 0 then
    Exit;

  if M.ViewStyle = lvsReport then
  begin
    if M.RowH <= 0 then
    begin
      AFirst := 0;
      ALast := ACount - 1;
    end
    else
    begin
      vh := M.ViewportH - M.HeaderH;
      AFirst := AScrollY div M.RowH;
      ALast := (AScrollY + vh - 1) div M.RowH;
    end;
  end
  else if FlowIsColMajor(M.ViewStyle) then
  begin
    Tracks := TyListTracks(M);
    PitchX := M.CellW + M.HGap;
    if PitchX <= 0 then
    begin
      firstLine := 0;
      lastLine := 0;
    end
    else
    begin
      firstLine := AScrollX div PitchX;
      lastLine := (AScrollX + M.ViewportW - 1) div PitchX;
    end;
    AFirst := firstLine * Tracks;
    ALast := (lastLine + 1) * Tracks - 1;
  end
  else
  begin
    Tracks := TyListTracks(M);
    PitchY := M.CellH + M.VGap;
    if PitchY <= 0 then
    begin
      firstLine := 0;
      lastLine := 0;
    end
    else
    begin
      firstLine := AScrollY div PitchY;
      lastLine := (AScrollY + (M.ViewportH - M.HeaderH) - 1) div PitchY;
    end;
    AFirst := firstLine * Tracks;
    ALast := (lastLine + 1) * Tracks - 1;
  end;

  if AFirst < 0 then
    AFirst := 0;
  if ALast > ACount - 1 then
    ALast := ACount - 1;

  Result := AFirst <= ALast;
  if not Result then
  begin
    { One rule for every False path (empty list, or scrolled clean past the content):
      the out-params are -1. A caller that ignores Result then cannot loop over stale
      indices. }
    AFirst := -1;
    ALast := -1;
  end;
end;

{ ---------------------------------------------------------------------------
  TyListNavigate
  --------------------------------------------------------------------------- }

{ Page step (a viewport's worth of cells), guarded against zero divisors. }
function PageStep(const M: TTyListMetrics): Integer;
var
  Tracks, PitchX, PitchY, rows, cols: Integer;
begin
  if M.ViewStyle = lvsReport then
  begin
    if M.RowH <= 0 then
      Result := 1
    else
      Result := Max(1, (M.ViewportH - M.HeaderH) div M.RowH);
  end
  else if FlowIsColMajor(M.ViewStyle) then
  begin
    Tracks := TyListTracks(M);
    PitchX := M.CellW + M.HGap;
    if PitchX <= 0 then
      cols := 1
    else
      cols := Max(1, M.ViewportW div PitchX);
    Result := cols * Tracks;
  end
  else
  begin
    Tracks := TyListTracks(M);
    PitchY := M.CellH + M.VGap;
    if PitchY <= 0 then
      rows := 1
    else
      rows := Max(1, (M.ViewportH - M.HeaderH) div PitchY);
    Result := rows * Tracks;
  end;
end;

function TyListNavigate(ACurrent, ACount: Integer; AKey: TTyListNavKey;
  const M: TTyListMetrics): Integer;
var
  cur, Tracks, delta, target, step: Integer;
begin
  if ACount <= 0 then
    Exit(-1);

  { Absolute keys ignore the current position entirely. }
  if AKey = lnHome then
    Exit(0);
  if AKey = lnEnd then
    Exit(ACount - 1);

  cur := ACurrent;
  if cur < 0 then
    { No current item: the first arrow/page press lands on item 0. }
    Exit(0);

  { Paging moves by a viewport and clamps. }
  if AKey = lnPageUp then
  begin
    step := PageStep(M);
    target := cur - step;
    if target < 0 then target := 0;
    Exit(target);
  end;
  if AKey = lnPageDown then
  begin
    step := PageStep(M);
    target := cur + step;
    if target > ACount - 1 then target := ACount - 1;
    Exit(target);
  end;

  { Arrow keys: compute a signed delta by flow direction. A delta of 0 (e.g. Left/Right
    in report mode) naturally returns the unchanged current position below. }
  Tracks := TyListTracks(M);
  delta := 0;
  if M.ViewStyle = lvsReport then
  begin
    case AKey of
      lnUp:   delta := -1;
      lnDown: delta := 1;
      { lnLeft / lnRight: no move }
    end;
  end
  else if FlowIsColMajor(M.ViewStyle) then
  begin
    case AKey of
      lnUp:    delta := -1;
      lnDown:  delta := 1;
      lnLeft:  delta := -Tracks;
      lnRight: delta := Tracks;
    end;
  end
  else
  begin
    { row-major }
    case AKey of
      lnLeft:  delta := -1;
      lnRight: delta := 1;
      lnUp:    delta := -Tracks;
      lnDown:  delta := Tracks;
    end;
  end;

  target := cur + delta;
  { Out of range -> do not move (no clamp). }
  if (target < 0) or (target >= ACount) then
    Result := cur
  else
    Result := target;
end;

{ ---------------------------------------------------------------------------
  TyListRangeBounds
  --------------------------------------------------------------------------- }

function TyListRangeBounds(AAnchor, ATarget: Integer; out ALo, AHi: Integer): Boolean;
begin
  if (AAnchor < 0) or (ATarget < 0) then
  begin
    ALo := -1;
    AHi := -1;
    Exit(False);
  end;
  ALo := Min(AAnchor, ATarget);
  AHi := Max(AAnchor, ATarget);
  Result := True;
end;

{ ---------------------------------------------------------------------------
  TyListMarqueeHits
  --------------------------------------------------------------------------- }

function TyListMarqueeHits(const ABox: TRect; ACount: Integer; const M: TTyListMetrics;
  AScrollX, AScrollY: Integer): TTyIntArray;
var
  box: TRect;
  swap, n: Integer;
  Tracks, PitchX, PitchY: Integer;
  r0, r1, c0, c1, row, col, pos, maxLine: Integer;
  cell: TRect;

  procedure Append(APos: Integer);
  begin
    SetLength(Result, n + 1);
    Result[n] := APos;
    Inc(n);
  end;

begin
  Result := nil;
  n := 0;
  if ACount <= 0 then
    Exit;

  { Normalize: allow any corner order. }
  box := ABox;
  if box.Left > box.Right then
  begin
    swap := box.Left; box.Left := box.Right; box.Right := swap;
  end;
  if box.Top > box.Bottom then
  begin
    swap := box.Top; box.Top := box.Bottom; box.Bottom := swap;
  end;

  if M.ViewStyle = lvsReport then
  begin
    if M.RowH <= 0 then
      Exit;
    { Derive the row span from the box (+/-1 pad absorbs truncation of negatives). }
    r0 := (box.Top    - M.HeaderH + AScrollY) div M.RowH - 1;
    r1 := (box.Bottom - M.HeaderH + AScrollY) div M.RowH + 1;
    if r0 < 0 then r0 := 0;
    if r1 > ACount - 1 then r1 := ACount - 1;
    for row := r0 to r1 do
    begin
      cell := TyListItemRect(row, ACount, M, AScrollX, AScrollY);
      if RectsTouch(cell, box) then
        Append(row);
    end;
    Exit;
  end;

  Tracks := TyListTracks(M);
  PitchX := M.CellW + M.HGap;
  PitchY := M.CellH + M.VGap;
  if (PitchX <= 0) or (PitchY <= 0) then
    Exit;

  if FlowIsColMajor(M.ViewStyle) then
  begin
    { column-major: outer loop over columns, inner over rows -> ascending positions
      because pos = col*Tracks + row and row is bounded by Tracks-1. }
    c0 := (box.Left  + AScrollX) div PitchX - 1;
    c1 := (box.Right + AScrollX) div PitchX + 1;
    if c0 < 0 then c0 := 0;
    maxLine := (ACount - 1) div Tracks;   { last column index }
    if c1 > maxLine then c1 := maxLine;
    r0 := (box.Top    - M.HeaderH + AScrollY) div PitchY - 1;
    r1 := (box.Bottom - M.HeaderH + AScrollY) div PitchY + 1;
    if r0 < 0 then r0 := 0;
    if r1 > Tracks - 1 then r1 := Tracks - 1;
    for col := c0 to c1 do
      for row := r0 to r1 do
      begin
        pos := col * Tracks + row;
        if (pos >= 0) and (pos < ACount) then
        begin
          cell := TyListItemRect(pos, ACount, M, AScrollX, AScrollY);
          if RectsTouch(cell, box) then
            Append(pos);
        end;
      end;
  end
  else
  begin
    { row-major: outer loop over rows, inner over columns -> ascending positions
      because pos = row*Tracks + col and col is bounded by Tracks-1. }
    c0 := (box.Left  + AScrollX) div PitchX - 1;
    c1 := (box.Right + AScrollX) div PitchX + 1;
    if c0 < 0 then c0 := 0;
    if c1 > Tracks - 1 then c1 := Tracks - 1;
    r0 := (box.Top    - M.HeaderH + AScrollY) div PitchY - 1;
    r1 := (box.Bottom - M.HeaderH + AScrollY) div PitchY + 1;
    if r0 < 0 then r0 := 0;
    maxLine := (ACount - 1) div Tracks;   { last row index }
    if r1 > maxLine then r1 := maxLine;
    for row := r0 to r1 do
      for col := c0 to c1 do
      begin
        pos := row * Tracks + col;
        if (pos >= 0) and (pos < ACount) then
        begin
          cell := TyListItemRect(pos, ACount, M, AScrollX, AScrollY);
          if RectsTouch(cell, box) then
            Append(pos);
        end;
      end;
  end;
end;

{ ---------------------------------------------------------------------------
  TyListPrefixMatch
  --------------------------------------------------------------------------- }

{ Case-insensitive UTF-8 "S starts with Prefix": slice S to Prefix's character
  length and compare case-insensitively. }
function StartsWithCI(const S, APrefix: string): Boolean;
var
  slice: string;
begin
  slice := UTF8Copy(S, 1, UTF8Length(APrefix));
  Result := UTF8CompareText(slice, APrefix) = 0;
end;

function TyListPrefixMatch(AGetText: TTyItemTextFn; ACount, AStartAfter: Integer;
  const APrefix: string): Integer;
var
  k, i, start: Integer;
begin
  Result := -1;
  if (APrefix = '') or (ACount <= 0) then
    Exit;

  start := AStartAfter + 1;
  for k := 0 to ACount - 1 do
  begin
    i := (start + k) mod ACount;
    if i < 0 then
      Inc(i, ACount);   { guard a very negative AStartAfter }
    if StartsWithCI(AGetText(i), APrefix) then
      Exit(i);
  end;
end;

{ ---------------------------------------------------------------------------
  TyListCompareCells
  --------------------------------------------------------------------------- }

function TyListCompareCells(const A, B: string; AKind: TTyListSortKind;
  ADir: TTySortDirection): Integer;
var
  fs: TFormatSettings;
  fA, fB: Double;
  dA, dB: TDateTime;
  okA, okB: Boolean;
begin
  { Locale-independent parsing. lskDateTime accepts ISO-8601-ish text ('2026-07-10',
    '2026-07-10 08:30'); anything else does not parse and sorts last. A column whose text
    is localised or otherwise exotic should sort through OnCompare, not through here. }
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  fs.ThousandSeparator := #0;
  fs.DateSeparator    := '-';
  fs.ShortDateFormat  := 'yyyy-mm-dd';
  fs.TimeSeparator    := ':';
  fs.ShortTimeFormat  := 'hh:nn';
  fs.LongTimeFormat   := 'hh:nn:ss';

  okA := True;
  okB := True;
  case AKind of
    lskNumber:
      begin
        okA := TryStrToFloat(A, fA, fs);
        okB := TryStrToFloat(B, fB, fs);
        if okA and okB then
        begin
          if fA < fB then Result := -1
          else if fA > fB then Result := 1
          else Result := 0;
        end
        else
          Result := UTF8CompareText(A, B);   { both unparseable -> compare as text }
      end;
    lskDateTime:
      begin
        okA := TryStrToDateTime(A, dA, fs);
        okB := TryStrToDateTime(B, dB, fs);
        if okA and okB then
        begin
          if dA < dB then Result := -1
          else if dA > dB then Result := 1
          else Result := 0;
        end
        else
          Result := UTF8CompareText(A, B);
      end;
  else
    { lskText }
    Result := UTF8CompareText(A, B);
  end;

  { Direction flips the comparison BETWEEN COMPARABLE VALUES. It must not flip the
    placement of unparseable ones: sorting a Size column descending should put the
    biggest files on top, not a pile of blanks. Same reasoning as SQL's NULLS LAST
    being orthogonal to ASC/DESC. }
  if okA <> okB then
  begin
    if okA then Result := -1 else Result := 1;   { the parseable one always sorts first }
    Exit;
  end;

  if ADir = sdDescending then
    Result := -Result;
end;

{ ---------------------------------------------------------------------------
  TyReportRowAt
  --------------------------------------------------------------------------- }

function TyReportRowAt(AY, AScrollY, AHeaderH, ARowH, ARowCount: Integer): Integer;
var
  row: Integer;
begin
  Result := -1;
  if ARowH <= 0 then
    Exit;
  if AY < AHeaderH then
    Exit;
  row := (AY - AHeaderH + AScrollY) div ARowH;
  if (row < 0) or (row >= ARowCount) then
    Exit;
  Result := row;
end;

end.
