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
    LabelW:      Integer;   { label column width, input to TyListCellSize. The label needs a
                              width of its OWN: deriving the cell width from the icon size
                              leaves room for about four characters. }
    Pad:         Integer;   { cell inner padding, input to TyListCellSize }
    { Which way this layout pass reads. The whole of mirroring in this unit is a
      REFLECTION of the finished tiling about [0, ViewportW) -- see TyListItemRect -- so
      every width, gap, pitch and track count stays exactly what it was and only the
      x of a finished cell moves. Default False leaves every existing caller (and every
      existing test, which builds these records through FillChar) byte-identical. }
    RightToLeft: Boolean;
  end;

  { --- Grouped view (SP2b) -------------------------------------------------
    Grouping partitions the items into vertical bands. Within a group the grid is
    still uniform, so group-local geometry stays closed-form; only the global Y of a
    group is data-dependent, so a per-layout PREFIX SUM (TyListGroupMap.Tops) turns
    "viewport Y -> group" into an O(log G) binary search plus a closed-form solve.

    Two things stay flat and are NOT re-derived here:
      - lvsList (column-major) does not support grouping; the control falls back to the
        flat SP1 path there. These functions assume row-major (icon/smallicon/tile) or
        lvsReport layout inside every group.
      - Grouping never touches lvsList's flow classification; group bodies are always
        laid out row-major (or one row per item in report). }

  { One group's data-level facts. Count may be 0 (an empty group still shows a header). }
  TTyListGroupInfo = record
    Count:     Integer;   { items in the group; 0 is allowed }
    Collapsed: Boolean;   { collapsed groups show only their header, contribute no body
                            and no display positions }
    HasHeader: Boolean;   { False = the implicit bucket that holds items with no valid
                            group; it draws no header band and occupies no header height }
  end;
  TTyListGroupInfoArray = array of TTyListGroupInfo;

  { The vertical map built once per layout pass. O(G) to build.

    Tops and FirstVisible are both length G+1 (a leading 0 plus one running total per
    group), so Tops[g]/FirstVisible[g] is group g's start and Tops[g+1]/FirstVisible[g+1]
    is its end.

    Content Y origin is the ITEM region top, i.e. it excludes the report column-header
    band (M.HeaderH). Every function that returns CLIENT coords adds M.HeaderH back and
    subtracts the scroll offset, exactly like TyListItemRect. }
  TTyListGroupMap = record
    Groups:       TTyListGroupInfoArray;
    Tops:         TTyIntArray;   { length G+1. Tops[g] = content Y of group g's top (its
                                   header band top). Tops[G] = total content height.
                                   Non-decreasing (a zero-height group repeats a value). }
    FirstVisible: TTyIntArray;   { length G+1. FirstVisible[g] = display position of
                                   group g's first item, accumulating EXPANDED groups only.
                                   FirstVisible[G] = total visible item count. A collapsed
                                   group contributes 0 (FirstVisible[g+1] = FirstVisible[g]). }
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

{ The checkbox rect inside a cell (DEVICE px, CLIENT coords). Both painting and
  hit-testing MUST call it; like TyListItemRect it is the single geometry source for
  the box, so the two can never drift.
    - ACell: in report mode this is the MAIN COLUMN's sub-rect; in every other mode it
      is the whole cell. (This unit knows nothing about the column model, so the control
      computes the column geometry and passes the sub-rect in.)
    - lvsIcon: pinned to the READING-START top corner, inset by APad.
    - every other style: at the READING START, VERTICALLY CENTERED, inset by APad.
    - ACheckPx <= 0, or a cell too small to hold the box (width OR height less than
      ACheckPx + APad) -> Rect(0,0,0,0).
    - ARightToLeft puts the box against the cell's right edge instead of its left. }
function TyListCheckRect(const ACell: TRect; AStyle: TTyListViewStyle;
  ACheckPx, APad: Integer; ARightToLeft: Boolean = False): TRect;

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

{ ---------------------------------------------------------------------------
  Grouped view (SP2b). Everything below operates on a TTyListGroupMap.
  --------------------------------------------------------------------------- }

{ Build the vertical map. O(G). AHeaderH is the GROUP header-band height in DEVICE
  pixels (distinct from M.HeaderH, the report column header). A HasHeader=False group
  contributes 0 header height.
    group height = header + body; a collapsed group has body 0.
    body (row-major): rows := Ceil(Count/Tracks); body := Max(0, rows*PitchY - VGap).
    body (lvsReport): body := Count * RowH.
    Count = 0 -> body = 0.
  Tops[0] = 0; Tops[g+1] = Tops[g] + header + body; Tops[G] = total content height.
  FirstVisible accumulates Count for expanded groups only. }
function TyListBuildGroupMap(const AGroups: TTyListGroupInfoArray;
  const M: TTyListMetrics; AHeaderH: Integer): TTyListGroupMap;

{ Total scrollable content height of the item region = Tops[G]. Empty map -> 0. }
function TyListGroupContentHeight(const AMap: TTyListGroupMap): Integer;

{ Group g's header band in CLIENT coords. HasHeader=False or g out of range ->
  Rect(0,0,0,0). It spans the full width [0, ViewportW] and does NOT move with AScrollX
  (headers never scroll horizontally); only AScrollY and M.HeaderH shift it vertically. }
function TyListGroupHeaderRect(const AMap: TTyListGroupMap; AGroup: Integer;
  const M: TTyListMetrics; AHeaderH, AScrollY: Integer): TRect;

{ Group g, item i's cell in CLIENT coords. THE single geometry source for a grouped
  item, so paint and hit-test can never drift. g/i out of range, or a collapsed group,
  -> Rect(0,0,0,0). }
function TyListGroupItemRect(const AMap: TTyListGroupMap; AGroup, AIndexInGroup: Integer;
  const M: TTyListMetrics; AHeaderH, AScrollX, AScrollY: Integer): TRect;

{ CLOSED group-index interval [AFirst, ALast] of every group whose band intersects the
  viewport. Binary-searches Tops (never a linear group walk). Empty map or no
  intersection -> False with both out params -1. }
function TyListGroupVisibleRange(const AMap: TTyListGroupMap; const M: TTyListMetrics;
  AScrollY: Integer; out AFirst, ALast: Integer): Boolean;

{ Hit-test a CLIENT-coord point.
    - on an item  -> True, AGroup/AIndexInGroup valid;
    - on a header band -> True, AIndexInGroup = -1;
    - a miss (inter-cell gap, a collapsed group's body area, the report column-header
      band, viewport blank space) -> False with both out params -1.
  Same discipline as TyListItemAt: it computes a candidate then VERIFIES it through
  TyListGroupItemRect + PtInRect, so hit geometry cannot drift from paint geometry. }
function TyListGroupHitTest(const AMap: TTyListGroupMap; const APt: TPoint;
  const M: TTyListMetrics; AHeaderH, AScrollX, AScrollY: Integer;
  out AGroup, AIndexInGroup: Integer): Boolean;

{ display position <-> (group, index-in-group). Both cover VISIBLE items only (items in
  collapsed groups have no display position). Out of range -> False / -1. Binary-searches
  FirstVisible. }
function TyListGroupOfDisplayPos(const AMap: TTyListGroupMap; APos: Integer;
  out AGroup, AIndexInGroup: Integer): Boolean;
function TyListGroupDisplayPos(const AMap: TTyListGroupMap;
  AGroup, AIndexInGroup: Integer): Integer;

{ 2-D grid navigation across groups. Takes and returns a DISPLAY POSITION (visible order).
    - lnLeft/lnRight are flat display position -1/+1; out of range does not move.
    - lnHome -> 0, lnEnd -> VisibleCount-1 (always move; empty -> -1).
    - lnPageUp/lnPageDown move one viewport of cells and CLAMP to [0, VisibleCount-1].
    - row-major lnUp/lnDown move within the group by Tracks; when that leaves the group,
      lnDown lands on the NEXT expanded non-empty group's first row and lnUp on the
      PREVIOUS one's last row, KEEPING the column (clamped to that row's last item);
      collapsed and empty groups are skipped; no such group -> does not move.
    - lvsReport lnUp/lnDown are flat -1/+1 (headers hold no display position). }
function TyListGroupNavigate(const AMap: TTyListGroupMap; ACurrent: Integer;
  AKey: TTyListNavKey; const M: TTyListMetrics): Integer;

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
        { icon centred on top, label below: the cell is as wide as the label wants, but
          never narrower than the icon plus its padding }
        Result.cx := Max(M.IconPx + 4 * M.Pad, M.LabelW);
        Result.cy := M.IconPx + M.LabelH + 3 * M.Pad;
      end;
    lvsSmallIcon, lvsList:
      begin
        { icon at left, single label at right }
        Result.cx := M.IconPx + 3 * M.Pad + M.LabelW;
        Result.cy := Max(M.IconPx, M.LabelH) + 2 * M.Pad;
      end;
    lvsTile:
      begin
        { icon at left, two text lines at right }
        Result.cx := M.IconPx + 3 * M.Pad + M.LabelW;
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

{ Reflect a finished cell about the viewport. ONE function, called at the end of both
  geometry producers (flat and grouped) and inverted by TyListReadingX for both hit tests
  -- so "which way does this list read" is answered in one place and cannot be answered
  differently by the two halves. LTR is the identity, to the byte. }
function TyListMirror(const M: TTyListMetrics; const ARect: TRect): TRect;
begin
  Result := ARect;
  if not M.RightToLeft then Exit;
  Result.Left  := M.ViewportW - ARect.Right;
  Result.Right := M.ViewportW - ARect.Left;
end;

function TyListReadingX(const M: TTyListMetrics; AX: Integer): Integer;
begin
  { The exact inverse of the reflection above, on a PIXEL rather than a boundary: the two
    have to be the same predicate, and a hand-written one that is half a pixel out is
    precisely the "painted here, answers there" defect. }
  Result := AX;
  if not M.RightToLeft then Exit;
  Result := M.ViewportW - 1 - AX;
end;

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
    Result := TyListMirror(M, Result);
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
  { The index arithmetic above is left ALONE and the finished cell is reflected instead.
    Re-tiling backwards (col := Tracks - 1 - col) would have been a second copy of the
    row/column decomposition, and it also answers wrongly on the last, partly-filled
    track -- reflecting the cell does not care how many cells the track holds. }
  Result := TyListMirror(M, Result);
end;

{ ---------------------------------------------------------------------------
  TyListCheckRect
  --------------------------------------------------------------------------- }

function TyListCheckRect(const ACell: TRect; AStyle: TTyListViewStyle;
  ACheckPx, APad: Integer; ARightToLeft: Boolean): TRect;
var
  cw, ch, l, t: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if ACheckPx <= 0 then
    Exit;
  cw := ACell.Right - ACell.Left;
  ch := ACell.Bottom - ACell.Top;
  { The box needs its own edge length plus one inset; a cell that cannot spare that on
    either axis shows no box at all. Direction-free: mirroring changes which edge the
    box hugs, never whether it fits. }
  if (cw < ACheckPx + APad) or (ch < ACheckPx + APad) then
    Exit;
  if ARightToLeft then l := ACell.Right - APad - ACheckPx
  else l := ACell.Left + APad;
  if AStyle = lvsIcon then
    t := ACell.Top + APad                    { icon flow: the reading-start top corner }
  else
    t := ACell.Top + (ch - ACheckPx) div 2;  { else: reading-start edge, vertically centred }
  Result := Rect(l, t, l + ACheckPx, t + ACheckPx);
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
    { Back into READING space before the `div PitchX` -- so the arithmetic that names a
      track is the same arithmetic in both directions, and only one line knows about the
      mirror. The verify below then runs against the MIRRORED rect and the ORIGINAL
      point, which is what makes the two halves provably inverse. }
    col := (TyListReadingX(M, APt.X) + AScrollX) div PitchX;
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
    in report mode) naturally returns the unchanged current position below.

    MIRRORING: ←/→ move the SELECTED ITEM between cells, not a caret between characters,
    so by the criterion in §6.3 item 4 of plans/2026-08-04-rtl-mirroring-scope.md they are
    layout direction and they flip -- the item to the physical right of the current one is
    the EARLIER one. Done by swapping the two keys once, here, rather than by negating
    each delta: the two flows disagree about what ← means (one item in row-major, one
    whole track in column-major) and negating in two places is how one of them gets
    missed. Home/End/PageUp/PageDown are LOGICAL ends and are handled above, untouched. }
  if M.RightToLeft then
  begin
    if AKey = lnLeft then AKey := lnRight
    else if AKey = lnRight then AKey := lnLeft;
  end;
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
  rl, rr: Integer;   { box.Left/Right in READING space -- see below }

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

  { The candidate TRACK range below is derived with `div PitchX`, so it is computed in
    READING space like both hit tests; reflection reverses the order, so the two ends
    swap. `box` itself stays in SCREEN space -- every candidate is verified against the
    mirrored cell rect with RectsTouch(cell, box), and reflecting the box as well would
    reflect the comparison twice. Getting the range wrong misplaces nothing (the verify
    still governs); it silently drops cells from the band, which is the harder failure
    to see. }
  rl := TyListReadingX(M, box.Left);
  rr := TyListReadingX(M, box.Right);
  if rl > rr then begin swap := rl; rl := rr; rr := swap; end;

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
    c0 := (rl + AScrollX) div PitchX - 1;
    c1 := (rr + AScrollX) div PitchX + 1;
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
    c0 := (rl + AScrollX) div PitchX - 1;
    c1 := (rr + AScrollX) div PitchX + 1;
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

{ ---------------------------------------------------------------------------
  Grouped view (SP2b)
  --------------------------------------------------------------------------- }

{ Which group owns content Y = ACy, i.e. the g with Tops[g] <= ACy < Tops[g+1], or -1
  when ACy is above the first group or at/beyond total height. upper_bound skips any
  zero-height group naturally (it never "contains" a coordinate). }
function GroupAtContentY(const AMap: TTyListGroupMap; ACy: Integer): Integer;
var
  G, lo, hi, mid: Integer;
begin
  Result := -1;
  G := Length(AMap.Groups);
  if G = 0 then
    Exit;
  if (ACy < AMap.Tops[0]) or (ACy >= AMap.Tops[G]) then
    Exit;
  { first index p in [0, G] with Tops[p] > ACy; the owning group is p-1 }
  lo := 0;
  hi := G + 1;
  while lo < hi do
  begin
    mid := (lo + hi) div 2;
    if AMap.Tops[mid] > ACy then hi := mid else lo := mid + 1;
  end;
  Result := lo - 1;
  if (Result < 0) or (Result >= G) then
    Result := -1;
end;

{ ---------------------------------------------------------------------------
  TyListBuildGroupMap
  --------------------------------------------------------------------------- }

function TyListBuildGroupMap(const AGroups: TTyListGroupInfoArray;
  const M: TTyListMetrics; AHeaderH: Integer): TTyListGroupMap;
var
  GCount, gi, Tracks, PitchY, rows, body, hh, acc, vacc: Integer;
begin
  { Managed Result: explicit array init, then deep-copy the group facts. }
  Result.Groups := nil;
  Result.Tops := nil;
  Result.FirstVisible := nil;
  GCount := Length(AGroups);
  SetLength(Result.Groups, GCount);
  if GCount > 0 then
    Move(AGroups[0], Result.Groups[0], GCount * SizeOf(TTyListGroupInfo));
  SetLength(Result.Tops, GCount + 1);
  SetLength(Result.FirstVisible, GCount + 1);
  Result.Tops[0] := 0;
  Result.FirstVisible[0] := 0;
  if GCount = 0 then
    Exit;

  Tracks := TyListTracks(M);   { >= 1, safe divisor }
  PitchY := M.CellH + M.VGap;
  acc := 0;
  vacc := 0;
  for gi := 0 to GCount - 1 do
  begin
    if AGroups[gi].HasHeader then hh := AHeaderH else hh := 0;
    body := 0;
    if not AGroups[gi].Collapsed then
    begin
      if AGroups[gi].Count > 0 then
      begin
        if M.ViewStyle = lvsReport then
          body := AGroups[gi].Count * M.RowH
        else
        begin
          rows := (AGroups[gi].Count + Tracks - 1) div Tracks;   { Ceil(Count/Tracks) }
          body := Max(0, rows * PitchY - M.VGap);
        end;
      end;
      Inc(vacc, AGroups[gi].Count);   { expanded groups contribute display positions }
    end;
    Inc(acc, hh + body);
    Result.Tops[gi + 1] := acc;
    Result.FirstVisible[gi + 1] := vacc;
  end;
end;

{ ---------------------------------------------------------------------------
  TyListGroupContentHeight
  --------------------------------------------------------------------------- }

function TyListGroupContentHeight(const AMap: TTyListGroupMap): Integer;
begin
  if Length(AMap.Tops) = 0 then
    Result := 0
  else
    Result := AMap.Tops[High(AMap.Tops)];
end;

{ ---------------------------------------------------------------------------
  TyListGroupHeaderRect
  --------------------------------------------------------------------------- }

function TyListGroupHeaderRect(const AMap: TTyListGroupMap; AGroup: Integer;
  const M: TTyListMetrics; AHeaderH, AScrollY: Integer): TRect;
var
  G, top: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  G := Length(AMap.Groups);
  if (AGroup < 0) or (AGroup >= G) then
    Exit;
  if not AMap.Groups[AGroup].HasHeader then
    Exit;
  { content Y -> client Y: add the report column header, subtract the vertical scroll }
  top := M.HeaderH + AMap.Tops[AGroup] - AScrollY;
  Result := Rect(0, top, M.ViewportW, top + AHeaderH);
end;

{ ---------------------------------------------------------------------------
  TyListGroupItemRect
  --------------------------------------------------------------------------- }

function TyListGroupItemRect(const AMap: TTyListGroupMap; AGroup, AIndexInGroup: Integer;
  const M: TTyListMetrics; AHeaderH, AScrollX, AScrollY: Integer): TRect;
var
  G, hh, bodyTopCy, Tracks, col, row, PitchX, PitchY: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  G := Length(AMap.Groups);
  if (AGroup < 0) or (AGroup >= G) then
    Exit;
  if AMap.Groups[AGroup].Collapsed then
    Exit;
  if (AIndexInGroup < 0) or (AIndexInGroup >= AMap.Groups[AGroup].Count) then
    Exit;

  if AMap.Groups[AGroup].HasHeader then hh := AHeaderH else hh := 0;
  bodyTopCy := AMap.Tops[AGroup] + hh;   { content Y of this group's body top }

  if M.ViewStyle = lvsReport then
  begin
    Result.Left   := -AScrollX;
    Result.Top    := M.HeaderH + bodyTopCy + AIndexInGroup * M.RowH - AScrollY;
    Result.Right  := Result.Left + M.ReportWidth;
    Result.Bottom := Result.Top + M.RowH;
    Result := TyListMirror(M, Result);
    Exit;
  end;

  { row-major grid inside the group body }
  Tracks := TyListTracks(M);
  PitchX := M.CellW + M.HGap;
  PitchY := M.CellH + M.VGap;
  col := AIndexInGroup mod Tracks;
  row := AIndexInGroup div Tracks;
  Result.Left   := col * PitchX - AScrollX;
  Result.Top    := M.HeaderH + bodyTopCy + row * PitchY - AScrollY;
  Result.Right  := Result.Left + M.CellW;
  Result.Bottom := Result.Top + M.CellH;
  { The grouped path is the SECOND copy of the same arithmetic, so it gets the same one
    reflection at the same point -- mirroring one and not the other would leave a grouped
    list correct until someone switched grouping on. }
  Result := TyListMirror(M, Result);
end;

{ ---------------------------------------------------------------------------
  TyListGroupVisibleRange
  --------------------------------------------------------------------------- }

function TyListGroupVisibleRange(const AMap: TTyListGroupMap; const M: TTyListMetrics;
  AScrollY: Integer; out AFirst, ALast: Integer): Boolean;
var
  G, visTop, visBottom, lo, hi, mid, firstG, lastG: Integer;
begin
  AFirst := -1;
  ALast := -1;
  Result := False;
  G := Length(AMap.Groups);
  if G = 0 then
    Exit;

  { Visible content-Y window is half-open [visTop, visBottom). A group's band
    [Tops[g], Tops[g+1]) is visible iff Tops[g+1] > visTop and Tops[g] < visBottom. }
  visTop := AScrollY;
  visBottom := AScrollY + (M.ViewportH - M.HeaderH);

  { firstG = leftmost g in [0, G-1] with Tops[g+1] > visTop (Tops[g+1] is non-decreasing
    in g). No such g -> firstG = G (nothing visible). Binary search, not a linear walk. }
  lo := 0;
  hi := G;
  while lo < hi do
  begin
    mid := (lo + hi) div 2;
    if AMap.Tops[mid + 1] > visTop then hi := mid else lo := mid + 1;
  end;
  firstG := lo;

  { lastG = rightmost g with Tops[g] < visBottom = (first p in [0, G] with
    Tops[p] >= visBottom) - 1. }
  lo := 0;
  hi := G + 1;
  while lo < hi do
  begin
    mid := (lo + hi) div 2;
    if AMap.Tops[mid] >= visBottom then hi := mid else lo := mid + 1;
  end;
  lastG := lo - 1;
  if lastG > G - 1 then
    lastG := G - 1;

  if (firstG <= lastG) and (firstG <= G - 1) and (lastG >= 0) then
  begin
    AFirst := firstG;
    ALast := lastG;
    Result := True;
  end;
end;

{ ---------------------------------------------------------------------------
  TyListGroupHitTest
  --------------------------------------------------------------------------- }

function TyListGroupHitTest(const AMap: TTyListGroupMap; const APt: TPoint;
  const M: TTyListMetrics; AHeaderH, AScrollX, AScrollY: Integer;
  out AGroup, AIndexInGroup: Integer): Boolean;
var
  GCount, cy, gi, hh, bodyTopCy, cnt, localY, Tracks, PitchX, PitchY, col, row, cand: Integer;
  cell, hdr: TRect;
begin
  AGroup := -1;
  AIndexInGroup := -1;
  Result := False;
  GCount := Length(AMap.Groups);
  if GCount = 0 then
    Exit;

  { The report column-header band wins, exactly as in TyListItemAt: a point above the
    item area is never an item, even if a scrolled row rect slides up under it. }
  if APt.Y < M.HeaderH then
    Exit;

  cy := APt.Y - M.HeaderH + AScrollY;   { client Y -> content Y }
  gi := GroupAtContentY(AMap, cy);
  if gi < 0 then
    Exit;

  if AMap.Groups[gi].HasHeader then hh := AHeaderH else hh := 0;
  bodyTopCy := AMap.Tops[gi] + hh;

  { Header band: verify against the same header rect the painter uses. }
  if (hh > 0) and (cy < bodyTopCy) then
  begin
    hdr := TyListGroupHeaderRect(AMap, gi, M, AHeaderH, AScrollY);
    if PtInRect(hdr, APt) then
    begin
      AGroup := gi;
      AIndexInGroup := -1;
      Result := True;
    end;
    Exit;
  end;

  { Below the header: only an expanded, non-empty group has a body. }
  if AMap.Groups[gi].Collapsed then
    Exit;
  cnt := AMap.Groups[gi].Count;
  if cnt <= 0 then
    Exit;

  localY := cy - bodyTopCy;   { content Y within the group body, >= 0 }
  if M.ViewStyle = lvsReport then
  begin
    if M.RowH <= 0 then
      Exit;
    cand := localY div M.RowH;
  end
  else
  begin
    Tracks := TyListTracks(M);
    PitchX := M.CellW + M.HGap;
    PitchY := M.CellH + M.VGap;
    if (PitchX <= 0) or (PitchY <= 0) then
      Exit;   { degenerate cells: nothing hittable }
    col := (TyListReadingX(M, APt.X) + AScrollX) div PitchX;   { see TyListItemAt }
    row := localY div PitchY;
    cand := row * Tracks + col;
  end;

  if (cand < 0) or (cand >= cnt) then
    Exit;

  { Verify against the single geometry source: rejects inter-cell gaps, points past
    ReportWidth, and any candidate whose real cell does not contain the point. }
  cell := TyListGroupItemRect(AMap, gi, cand, M, AHeaderH, AScrollX, AScrollY);
  if PtInRect(cell, APt) then
  begin
    AGroup := gi;
    AIndexInGroup := cand;
    Result := True;
  end;
end;

{ ---------------------------------------------------------------------------
  TyListGroupOfDisplayPos / TyListGroupDisplayPos
  --------------------------------------------------------------------------- }

function TyListGroupOfDisplayPos(const AMap: TTyListGroupMap; APos: Integer;
  out AGroup, AIndexInGroup: Integer): Boolean;
var
  G, vc, lo, hi, mid: Integer;
begin
  AGroup := -1;
  AIndexInGroup := -1;
  Result := False;
  G := Length(AMap.Groups);
  if G = 0 then
    Exit;
  vc := AMap.FirstVisible[G];
  if (APos < 0) or (APos >= vc) then
    Exit;

  { first index p in [0, G] with FirstVisible[p] > APos; the owning group is p-1.
    Collapsed groups (FirstVisible[g] = FirstVisible[g+1]) are skipped naturally. }
  lo := 0;
  hi := G + 1;
  while lo < hi do
  begin
    mid := (lo + hi) div 2;
    if AMap.FirstVisible[mid] > APos then hi := mid else lo := mid + 1;
  end;
  AGroup := lo - 1;
  if (AGroup < 0) or (AGroup >= G) then
  begin
    AGroup := -1;
    Exit;
  end;
  AIndexInGroup := APos - AMap.FirstVisible[AGroup];
  Result := True;
end;

function TyListGroupDisplayPos(const AMap: TTyListGroupMap;
  AGroup, AIndexInGroup: Integer): Integer;
var
  G: Integer;
begin
  Result := -1;
  G := Length(AMap.Groups);
  if (AGroup < 0) or (AGroup >= G) then
    Exit;
  if AMap.Groups[AGroup].Collapsed then
    Exit;   { items in a collapsed group have no display position }
  if (AIndexInGroup < 0) or (AIndexInGroup >= AMap.Groups[AGroup].Count) then
    Exit;
  Result := AMap.FirstVisible[AGroup] + AIndexInGroup;
end;

{ ---------------------------------------------------------------------------
  TyListGroupNavigate
  --------------------------------------------------------------------------- }

function TyListGroupNavigate(const AMap: TTyListGroupMap; ACurrent: Integer;
  AKey: TTyListNavKey; const M: TTyListMetrics): Integer;
var
  GCount, vc, cur, gi, i, Tracks, col, row, cand, g2, lastRow, step: Integer;

  function ClampPos(x: Integer): Integer;
  begin
    if x < 0 then x := 0;
    if x > vc - 1 then x := vc - 1;
    Result := x;
  end;

  { Flat step: move to x, or stay put when x leaves the visible range (no clamp). }
  function MoveFlat(x: Integer): Integer;
  begin
    if (x < 0) or (x >= vc) then Result := cur else Result := x;
  end;

  { First expanded, non-empty group after AFrom, or -1. }
  function NextItemGroup(AFrom: Integer): Integer;
  var
    k: Integer;
  begin
    Result := -1;
    for k := AFrom + 1 to GCount - 1 do
      if (not AMap.Groups[k].Collapsed) and (AMap.Groups[k].Count > 0) then
        Exit(k);
  end;

  { Last expanded, non-empty group before AFrom, or -1. }
  function PrevItemGroup(AFrom: Integer): Integer;
  var
    k: Integer;
  begin
    Result := -1;
    for k := AFrom - 1 downto 0 do
      if (not AMap.Groups[k].Collapsed) and (AMap.Groups[k].Count > 0) then
        Exit(k);
  end;

begin
  GCount := Length(AMap.Groups);
  vc := 0;
  if GCount > 0 then
    vc := AMap.FirstVisible[GCount];
  if vc <= 0 then
    Exit(-1);

  { Absolute keys ignore the current position. }
  if AKey = lnHome then
    Exit(0);
  if AKey = lnEnd then
    Exit(vc - 1);

  cur := ACurrent;
  if cur < 0 then
    { No current item: the first arrow/page press lands on 0. }
    Exit(0);

  { ←/→ are layout direction here too, and for the same reason as in TyListNavigate: a
    grouped list still steps the SELECTION between cells. Swapped once, before the case,
    so the flat step below reads identically in both directions. }
  if M.RightToLeft then
  begin
    if AKey = lnLeft then AKey := lnRight
    else if AKey = lnRight then AKey := lnLeft;
  end;

  { Flat and paging keys are independent of grouping. }
  case AKey of
    lnLeft:     Exit(MoveFlat(cur - 1));
    lnRight:    Exit(MoveFlat(cur + 1));
    lnPageUp:   begin step := PageStep(M); Exit(ClampPos(cur - step)); end;
    lnPageDown: begin step := PageStep(M); Exit(ClampPos(cur + step)); end;
  end;

  { lnUp / lnDown. Report holds no display position for headers, so it is flat +/-1. }
  if M.ViewStyle = lvsReport then
  begin
    if AKey = lnUp then
      Exit(MoveFlat(cur - 1));
    if AKey = lnDown then
      Exit(MoveFlat(cur + 1));
    Exit(cur);
  end;

  { Row-major grid, crossing group boundaries. }
  if not TyListGroupOfDisplayPos(AMap, cur, gi, i) then
    Exit(cur);
  Tracks := TyListTracks(M);
  col := i mod Tracks;
  row := i div Tracks;

  if AKey = lnDown then
  begin
    lastRow := (AMap.Groups[gi].Count - 1) div Tracks;
    if row < lastRow then
    begin
      { A row below still exists inside this group. The cell directly beneath may not --
        with Count=6, Tracks=4 nothing sits under column 2 -- so clamp to the group's last
        item. Testing `i + Tracks < Count` instead would call a partial last row "off the
        bottom" and jump to the next group, skipping the items that ARE on that row. }
      cand := i + Tracks;
      if cand > AMap.Groups[gi].Count - 1 then
        cand := AMap.Groups[gi].Count - 1;
      Exit(AMap.FirstVisible[gi] + cand);
    end;
    { Off the bottom: first row of the next expanded non-empty group, keeping the
      column (clamped to that row's last item). }
    g2 := NextItemGroup(gi);
    if g2 < 0 then
      Exit(cur);
    cand := col;
    if cand > AMap.Groups[g2].Count - 1 then
      cand := AMap.Groups[g2].Count - 1;
    Exit(AMap.FirstVisible[g2] + cand);
  end;

  if AKey = lnUp then
  begin
    cand := i - Tracks;   { same column, previous row within the group }
    if cand >= 0 then
      Exit(AMap.FirstVisible[gi] + cand);
    { Off the top: last row of the previous expanded non-empty group, keeping the
      column (clamped to that group's last item). }
    g2 := PrevItemGroup(gi);
    if g2 < 0 then
      Exit(cur);
    lastRow := (AMap.Groups[g2].Count - 1) div Tracks;
    cand := lastRow * Tracks + col;
    if cand > AMap.Groups[g2].Count - 1 then
      cand := AMap.Groups[g2].Count - 1;
    Exit(AMap.FirstVisible[g2] + cand);
  end;

  Result := cur;
end;

end.
