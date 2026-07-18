unit tyControls.Pagination;
{$mode objfpc}{$H+}
{ TTyPagination -- a page selector: an optional prev/next pair around a run of page-number
  cells with '...' where a run of pages is elided ('< 1 ... 97 98 99 ... 195 >').

  The gap it fills. Nothing in this library says "which page of the results am I on".
  TTySegmented picks a VALUE out of a short row the user can see all of; a pagination
  addresses a run of hundreds and must therefore ELIDE, which is a rule, not a layout.
  It drives NOTHING itself: it owns no list, no query and no Grid -- it reports a page and
  the host re-fills its TTyListView / TTyListBox / custom list from OnChange. That is the
  whole reason it is not a Grid part.

  A WINDOWED control (TTyCustomControl), like its kin TTySegmented and unlike TTyTag: it
  is focusable and the Left/Right keys move the page, and a graphic control can do neither
  (no handle => no focus, no key messages). That is the whole reason for the base class.

  typeKey 'TyPagination' is the STRIP (the frame the cells sit in); each cell resolves
  'TyPaginationItem' separately, and it is that key's :selected / :hover / :disabled states
  that make the control read at all. The current page's cell carries tysSelected exactly as
  TTyButton.Down does, so one ':selected' rule styles both. A cell also resolves with a
  variant token naming its KIND ('prev' / 'page' / 'ellipsis' / 'next') -- the TTyAlert
  precedent -- so a rule for the selector `TyPaginationItem.ellipsis` can drop the border a
  page cell carries, without this unit growing a third typeKey.

  PAGES ARE 0-BASED. PageIndex is an index like every other index in this library
  (ItemIndex / TabIndex / TPageControl.PageIndex), and only the LABEL is 1-based:
  page 0 is drawn '1'. See TyPaginationItemLabel. }
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.Controller, tyControls.StyleModel;

const
  { Built-in logical-px defaults (96-PPI baseline) for this control's three metrics. A skin
    retunes them through the named theme metrics below (the v3/C convention); these are only
    what a theme that sets none falls back to. Every call site scales them to device px.
    The strip's own inset is NOT among them: that is the TyPagination style's ordinary CSS
    `padding`, and a cell's horizontal padding is TyPaginationItem's -- both are already
    themed properties, so inventing metrics for them would be a second way to say the same
    thing. }
  TyPaginationGap          = 4;    // gap between two cells
  TyPaginationMinCellWidth = 32;   // floor for a cell's width
  TyPaginationGlyphSize    = 12;   // prev/next arrow slot, square, centred in its cell

  { The metric tokens those fallbacks back. Named constants rather than inline literals
    because several call sites (the geometry, the measurement, the tests) must agree on the
    spelling -- a typo in one would silently strand it on the default and the geometry would
    drift from the measurement. (The tyControls.Types convention.) }
  TyPaginationGapVar          = '--pagination-gap';
  TyPaginationMinCellWidthVar = '--pagination-min-cell-width';
  TyPaginationGlyphSizeVar    = '--pagination-glyph-size';

  { The mark an elided run of pages is drawn with. Three ASCII dots, not U+2026: it is the
    exact mark TTyPainter.DrawText appends when it truncates a label, so an elided RUN and a
    truncated LABEL read as the same thing in the same strip -- and it keeps this unit ASCII
    like every other source file here. It is punctuation rather than prose, so it is a
    constant and not a resourcestring: there is nothing in it to translate. }
  TyPaginationEllipsis = '...';

type
  { What one cell of the strip is.
      pikPrev / pikNext -- the step arrows (drawn as glyphs, never as text)
      pikPage           -- a page number
      pikEllipsis       -- '...', standing for a run of pages that did not fit the window }
  TTyPaginationItemKind = (pikPrev, pikPage, pikEllipsis, pikNext);

  { One cell of the strip.
      Kind -- what it is (above).
      Page -- the 0-BASED page a click on it goes to, or < 0 when the cell is INERT.
              Inert is not a second flag but the absence of a target, and it covers every
              case in one rule: an ellipsis stands for pages it does not name, and a prev at
              page 0 / a next at the last page have nowhere to go. The paint, the hit-test
              and the state machine all read `Page < 0` and need to know nothing else. }
  TTyPaginationItem = record
    Kind: TTyPaginationItemKind;
    Page: Integer;
  end;

  TTyPaginationItems = array of TTyPaginationItem;
  TTyPaginationRects = array of TRect;
  TTyPaginationWidths = array of Integer;

{ --- Pure rules / geometry (headless-testable; no control, no handle, no theme) -------- }

{ The page a PageIndex of ACurrent becomes when it is applied to a run of ACount pages.
    ACount <= 0 -- there is nothing to paginate: -1, "no page".
    otherwise   -- ACurrent CLAMPED into 0..ACount-1.
  A deliberate deviation from TTySegmentedValidIndex (and the house ItemIndex rule), which
  answers -1 for an out-of-range index: a segmented control genuinely can have nothing
  selected, but a list is always SHOWING some page, so "which page am I on" is never "none"
  while pages exist. A host that asks for page 500 of 195 has an off-by-something, and
  answering -1 would leave the strip with no current page at all -- clamping shows it the
  last page, which is what its data can actually give. }
function TyPaginationValidIndex(ACurrent, ACount: Integer): Integer;

{ Where a Left/Right key press (or a prev/next click) moves the page: ACurrent + ADelta,
  CLAMPED at both ends -- no wrap, because running off the end of a result set should stop
  rather than teleport the user from page 195 back to page 1. Always a valid page, or -1
  when there are none. }
function TyPaginationStepIndex(ACurrent, ACount, ADelta: Integer): Integer;

{ THE ELLIPSIS RULE -- the heart of this control. The cells a strip shows for a run of
  APageCount pages with APageIndex (0-based) current.
    ASiblingCount  -- how many pages to keep on EACH side of the current one.
    ABoundaryCount -- how many pages to keep at EACH end of the run. Clamped to >= 1: below
                      that the first and last page would vanish behind an ellipsis with no
                      way to reach them, which is the one thing a pagination must always
                      offer.
    AShowPrevNext  -- bracket the run with the two step arrows.
  The rule: always the first ABoundaryCount pages, always the last ABoundaryCount, always a
  window of ASiblingCount pages either side of the current one, and '...' wherever a run
  between those blocks is elided. Two properties make it read as a stable control rather
  than a jumping one:

  * THE ITEM COUNT IS CONSTANT as the user pages. The window is not merely `current +/- s`:
    near either end it is pushed inwards to keep its full width, so page 1 of 195 shows
    `< 1 2 3 4 5 ... 195 >` rather than a short `< 1 2 ... 195 >` that grows as you move in.
    (Without this the strip changes length under the pointer at exactly the moment the user
    is aiming at it.)
  * AN ELLIPSIS NEVER HIDES A SINGLE PAGE. Where the elided run is exactly one page long,
    that page is drawn instead of the '...' that would replace it -- same width, one more
    page reachable, and no '...' that lies about how much it is hiding.

  APageCount <= 0 -> an EMPTY list, not even the arrows: there is nothing to paginate, and a
  strip of two dead arrows would claim there is.
  Headless-safe: plain integers in, a list out -- no control, no handle, no theme. }
function TyPaginationItems(APageCount, APageIndex, ASiblingCount, ABoundaryCount: Integer;
  AShowPrevNext: Boolean): TTyPaginationItems;

{ The style VARIANT name a cell kind resolves as -- so a theme writes a
  `TyPaginationItem.ellipsis` rule, exactly the shape `TyAlert.warning` already has, and
  this unit needs no third typeKey to let the four kinds look different. }
function TyPaginationItemVariant(AKind: TTyPaginationItemKind): string;

{ The text a cell is drawn with: the 1-BASED page number for a page cell, the ellipsis mark
  for an ellipsis, and '' for the arrows (which are glyphs, not text). This one line is the
  whole 0-based/1-based contract: PageIndex 0 is labelled '1'. }
function TyPaginationItemLabel(const AItem: TTyPaginationItem): string;

{ The cells' rects, in DEVICE px relative to the control rect's top-left, one per entry of
  AContentWidths (so the result's indices are the item list's indices).
    AClientWidth/AClientHeight     -- the control size.
    APadLeft/Top/Right/Bottom      -- the STRIP's themed padding (the band's insets).
    AGap                           -- gap between two cells.
    AMinCellWidth                  -- floor for one cell's width.
    AContentWidths                 -- each cell's NATURAL width (its measured content plus
                                      its own padding). Passed in rather than measured here
                                      because that is the only part that needs a font: the
                                      cells are deliberately NOT equal-width ('195' and
                                      '...' are wider than '1'), so the widths are an input.
  The cells are laid left to right from the band's left edge, AGap apart. A cell that does
  not fit WHOLE is left EMPTY (and so is every cell after it -- the cursor only moves right):
  a strip too narrow drops the cells it cannot show rather than painting a sliver that can be
  neither read nor aimed at, and an empty rect is not hit-testable, so the two agree. A cell
  of no width at all takes neither room nor a gap.
  Empty rects (never inverted ones) for a degenerate request: a zero-area control, or padding
  that eats the whole strip. }
function TyPaginationItemRects(AClientWidth, AClientHeight: Integer;
  APadLeft, APadTop, APadRight, APadBottom, AGap, AMinCellWidth: Integer;
  const AContentWidths: array of Integer): TTyPaginationRects;

{ The cell at device-px (X, Y), or -1 for none. The exact INVERSE of TyPaginationItemRects:
  it scans that function's own output, so the cell the user clicks is always the cell that
  was painted there, and the two can never drift. The GAPS between cells belong to no cell
  (unlike TTySegmented, whose segments tile their band, this strip has real gutters): a click
  in one answers -1 and is inert. }
function TyPaginationIndexAt(const ARects: TTyPaginationRects; X, Y: Integer): Integer;

{ The strip width that shows every cell whole -- the inverse of TyPaginationItemRects: feed
  the result back in as AClientWidth (same other arguments) and every cell comes out exactly
  its natural width, with the last one's right edge on the padding. Device px throughout;
  this is what AutoSize measures to. An empty strip is just its own padding. }
function TyPaginationPreferredWidth(APadLeft, APadRight, AGap, AMinCellWidth: Integer;
  const AContentWidths: array of Integer): Integer;

{ The strip height that shows a cell whole: the strip's padding around a cell band tall
  enough for one line of text in its own padding -- and never shorter than the arrow slot,
  which is centred in the CELL and would otherwise be squashed (TTyTag's rule for its close
  slot). Device px; this is what AutoSize measures to. }
function TyPaginationPreferredHeight(AStripPadTop, AStripPadBottom, ALineHeight,
  ACellPadTop, ACellPadBottom, AGlyphSize: Integer): Integer;

{ The square arrow slot inside a prev/next cell: ASize on a side, centred, and clamped into
  the cell rather than allowed to overflow it. Empty when there is no room or no size. }
function TyPaginationGlyphRect(const ACell: TRect; ASize: Integer): TRect;

type
  { A page selector: prev/next arrows around a run of page cells, with '...' where pages are
    elided. PageCount is how many pages the host has, PageIndex which one it is showing
    (0-BASED), and OnChange fires whenever that changes -- by click, by key, or from code.

    Colour/size variants are plain StyleClass ('TyPagination.small', ...) -- the control
    declares no variant enum of its own, so a theme may define as many as it likes without a
    code change, and the cells' own key is resolved with the SAME StyleClass appended to the
    cell's kind, so 'TyPaginationItem.page.small' can follow the strip. }
  TTyPagination = class(TTyCustomControl)
  private
    FPageCount: Integer;
    FPageIndex: Integer;       // 0-based; -1 only while PageCount = 0
    FSiblingCount: Integer;
    FBoundaryCount: Integer;
    FShowPrevNext: Boolean;
    FHoverIndex: Integer;      // cell under the pointer; -1 = none
    FOnChange: TNotifyEvent;
    { A streamed PageIndex parked by the setter because the .lfm's PageCount may not have
      arrived yet (nothing is valid against a run of no pages). Applied in Loaded. }
    FPendingPageIndex: Integer;
    FHasPendingIndex: Boolean;
    procedure SetPageCount(AValue: Integer);
    procedure SetPageIndex(AValue: Integer);
    procedure SetSiblingCount(AValue: Integer);
    procedure SetBoundaryCount(AValue: Integer);
    procedure SetShowPrevNext(AValue: Boolean);
    { The cell's variant tokens: its KIND first, then the user's StyleClass. ResolveLayer
      applies variant tokens in textual order, so the kind's look is always applied and an
      explicit class layers over it per-property -- the engine's ordinary multi-token
      cascade (later token wins), exactly as TTyAlert.StyleVariant does it. }
    function CellVariant(AKind: TTyPaginationItemKind): string;
    { The state set of one cell -- the heart of how this control reads. }
    function CellStates(const AItem: TTyPaginationItem; AIndex: Integer): TTyStateSet;
    { The resolved style for one cell: 'TyPaginationItem' with that cell's variants and
      that cell's state. }
    function CellStyle(const AItem: TTyPaginationItem; AIndex: Integer): TTyStyleSet;
    { The tokens a cell draws its LABEL/ARROW with: its own where TyPaginationItem defines
      them, the STRIP's otherwise. Background/border are deliberately NOT inherited this way
      (see RenderTo): a cell with no background of its own must draw no chip. }
    function CellTextStyle(const AStrip, ACell: TTyStyleSet): TTyStyleSet;
    { Each cell's natural width in DEVICE px: its measured content plus its OWN themed
      padding. The painter is the measurer (not an LCL canvas) because the labels are drawn
      with BGRA text metrics, and only the same measurer reproduces the extent those glyphs
      actually render at -- the rects the hit-test measures are the rects the paint drew. }
    function ContentWidthsWith(APainter: TTyPainter;
      const AList: TTyPaginationItems): TTyPaginationWidths;
    function CellRectsWith(APainter: TTyPainter; const AStrip: TTyStyleSet;
      const AList: TTyPaginationItems; AWidth, AHeight: Integer): TTyPaginationRects;
    { CellRectsWith on a CANVAS-LESS painter -- the TTyAlert / TTyBadge idiom: BeginPaint(nil,
      ...) builds only the painter's internal bitmap and EndPaint frees it WITHOUT blitting,
      so this is safe outside a paint cycle and leaks nothing. }
    function CellRectsFor(AWidth, AHeight, APPI: Integer): TTyPaginationRects;
    { AutoSize re-fit + repaint, for every change that can move the item list. }
    procedure Refit;
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure Loaded; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    { The cells the current PageCount / PageIndex / SiblingCount / BoundaryCount /
      ShowPrevNext produce -- the very list the paint and the hit-test work from. Cheap
      (a handful of records) and recomputed rather than cached: it is a pure function of
      five properties, so a cache here could only ever go stale. }
    function TyPaginationItemList: TTyPaginationItems;
    { How many cells the strip currently holds. }
    function ItemCount: Integer;
    { Cell AIndex's rect in DEVICE px, (0,0)-local -- the exact rect the paint filled and the
      hit-test measures against; empty when AIndex is out of range or the cell did not fit. }
    function TyPaginationCellRect(AIndex: Integer): TRect;
    { The cell at client device (X, Y), or -1 (the gutters between cells included). }
    function TyPaginationCellAt(X, Y: Integer): Integer;
  published
    { How many pages the host has. 0 means "nothing to paginate" and the strip draws no
      cells at all (not even dead arrows). Shortening the run re-clamps PageIndex SILENTLY:
      setting PageCount is the host's own action, so announcing it back through OnChange
      would fire an event the host caused and did not ask about. }
    property PageCount: Integer read FPageCount write SetPageCount default 1;
    { The page the host is showing, 0-BASED -- page 0 is the cell labelled '1'. Out of range
      is CLAMPED into the run, not reset to -1 (see TyPaginationValidIndex); it is -1 only
      while PageCount is 0. }
    property PageIndex: Integer read FPageIndex write SetPageIndex default 0;
    { How many pages stay visible on EACH side of the current one. This and BoundaryCount are
      the ellipsis rule's only two parameters -- the numbers Ant hard-codes. They are
      published because the window size is what fits the strip to its host: a narrow footer
      wants 0, a wide one 2. Leaving them out would hard-code a window, which is the same sin
      as hard-coding a colour. They are properties and not theme metrics because they change
      WHAT the strip says, not how it looks. }
    property SiblingCount: Integer read FSiblingCount write SetSiblingCount default 1;
    { How many pages stay visible at EACH end of the run. Clamped to >= 1: the first and last
      page must always be reachable. }
    property BoundaryCount: Integer read FBoundaryCount write SetBoundaryCount default 1;
    { Bracket the run with the two step arrows. Off leaves a bare number strip. }
    property ShowPrevNext: Boolean read FShowPrevNext write SetShowPrevNext default True;
    { Fires whenever PageIndex actually changes -- by click, by key, or from code. Setting
      the same page again is not a change and stays silent. This is where the host re-fills
      its list. }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    { With AutoSize the strip hugs its current cells; off, it keeps the bounds it was given
      and lays the cells out from its left padding (a strip aligns itself through
      Align/Anchors, as every other control here does). Note that the cells are not
      equal-width, so an auto-sized strip re-fits by a few px as the user pages between
      '1 2 3' and '1 ... 97' -- the item COUNT is constant (see TyPaginationItems), the
      widths are not. }
    property AutoSize;
    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property StyleOverride;
    property Controller;
    property OnClick;
  end;

implementation

{ --- pure rules ----------------------------------------------------------------------- }

function TyPaginationValidIndex(ACurrent, ACount: Integer): Integer;
begin
  if ACount <= 0 then Exit(-1);
  if ACurrent < 0 then Exit(0);
  if ACurrent > ACount - 1 then Exit(ACount - 1);
  Result := ACurrent;
end;

function TyPaginationStepIndex(ACurrent, ACount, ADelta: Integer): Integer;
begin
  if ACount <= 0 then Exit(-1);
  // Clamp BEFORE stepping as well as after: a stranded ACurrent must step from where the
  // strip is actually showing, not from a page that does not exist.
  Result := TyPaginationValidIndex(TyPaginationValidIndex(ACurrent, ACount) + ADelta, ACount);
end;

function TyPaginationItems(APageCount, APageIndex, ASiblingCount, ABoundaryCount: Integer;
  AShowPrevNext: Boolean): TTyPaginationItems;
{ Worked in 1-BASED page numbers throughout -- the arithmetic below is the classic rule as
  it is always written, and one translation at the two edges (cur, and AddPage) is far
  easier to check than the same rule with a -1 sprinkled through every term. }
var
  used: Integer;
  cnt, cur, sib, bnd: Integer;
  endFirst, sibStart, sibEnd, i: Integer;

  procedure Add(AKind: TTyPaginationItemKind; APage: Integer);
  begin
    if used >= Length(Result) then SetLength(Result, used + 8);
    Result[used].Kind := AKind;
    Result[used].Page := APage;
    Inc(used);
  end;

  procedure AddPage(APage1: Integer);   // takes a 1-based page, stores the 0-based index
  begin
    Add(pikPage, APage1 - 1);
  end;

begin
  Result := nil;
  used := 0;
  cnt := APageCount;
  // Nothing to paginate: no cells at all. A strip of two dead arrows would claim otherwise.
  if cnt <= 0 then Exit;

  cur := TyPaginationValidIndex(APageIndex, cnt) + 1;
  sib := ASiblingCount;
  if sib < 0 then sib := 0;
  bnd := ABoundaryCount;
  if bnd < 1 then bnd := 1;   // the first/last page must stay reachable

  if AShowPrevNext then
  begin
    if cur > 1 then Add(pikPrev, cur - 2) else Add(pikPrev, -1);
  end;

  // The head block: pages 1..bnd, always shown.
  for i := 1 to Min(bnd, cnt) do AddPage(i);

  // The tail block starts here (past cnt => there is no tail: the head already reached the
  // end of a short run, and the two must never name the same page twice).
  endFirst := Max(cnt - bnd + 1, bnd + 1);

  // The window around the current page. The inner Min/Max are what keep the item count
  // constant: near an end the window is pushed inwards (Min) to keep its full width, and
  // it is never allowed to overlap the head block (the outer Max) or the tail block.
  sibStart := Max(Min(cur - sib, cnt - bnd - sib * 2 - 1), bnd + 2);
  if endFirst <= cnt then
    sibEnd := Min(Max(cur + sib, bnd + sib * 2 + 2), endFirst - 2)
  else
    sibEnd := Min(Max(cur + sib, bnd + sib * 2 + 2), cnt - 1);

  // The gap between the head block and the window. When it is exactly one page wide, that
  // page is drawn instead of an ellipsis that would hide it (the second guard keeps that
  // page from duplicating one the tail block already names).
  if sibStart > bnd + 2 then
    Add(pikEllipsis, -1)
  else if bnd + 1 < cnt - bnd then
    AddPage(bnd + 1);

  for i := sibStart to sibEnd do AddPage(i);

  // The gap between the window and the tail block -- the same rule mirrored.
  if sibEnd < cnt - bnd - 1 then
    Add(pikEllipsis, -1)
  else if cnt - bnd > bnd then
    AddPage(cnt - bnd);

  for i := endFirst to cnt do AddPage(i);

  if AShowPrevNext then
  begin
    if cur < cnt then Add(pikNext, cur) else Add(pikNext, -1);
  end;

  SetLength(Result, used);
end;

function TyPaginationItemVariant(AKind: TTyPaginationItemKind): string;
begin
  case AKind of
    pikPrev:     Result := 'prev';
    pikEllipsis: Result := 'ellipsis';
    pikNext:     Result := 'next';
  else
    // pikPage, and any value a future enum extension forgets: a page cell is the baseline.
    Result := 'page';
  end;
end;

function TyPaginationItemLabel(const AItem: TTyPaginationItem): string;
begin
  case AItem.Kind of
    // The 0-based index becomes a 1-based label, and this is the ONLY place it happens.
    pikPage:     Result := IntToStr(AItem.Page + 1);
    pikEllipsis: Result := TyPaginationEllipsis;
  else
    Result := '';   // prev/next are glyphs, not text
  end;
end;

{ --- pure geometry -------------------------------------------------------------------- }

function TyPaginationItemRects(AClientWidth, AClientHeight: Integer;
  APadLeft, APadTop, APadRight, APadBottom, AGap, AMinCellWidth: Integer;
  const AContentWidths: array of Integer): TTyPaginationRects;
var
  bandL, bandR, bandT, bandB, x, w, i: Integer;
begin
  // One rect per cell whatever happens, so the result's indices are the item list's indices
  // even when nothing fits.
  Result := nil;
  SetLength(Result, Length(AContentWidths));
  for i := 0 to High(Result) do Result[i] := Rect(0, 0, 0, 0);
  if (AClientWidth <= 0) or (AClientHeight <= 0) then Exit;
  // Clamp every negative input once, here, so the arithmetic below can be read straight.
  if APadLeft < 0 then APadLeft := 0;
  if APadTop < 0 then APadTop := 0;
  if APadRight < 0 then APadRight := 0;
  if APadBottom < 0 then APadBottom := 0;
  if AGap < 0 then AGap := 0;
  if AMinCellWidth < 0 then AMinCellWidth := 0;

  // The band: the strip inset by its themed padding on all four sides. Padding that eats
  // the whole strip leaves nothing to lay out (empty rects, never inverted ones).
  bandL := APadLeft;
  bandR := AClientWidth - APadRight;
  bandT := APadTop;
  bandB := AClientHeight - APadBottom;
  if (bandR <= bandL) or (bandB <= bandT) then Exit;

  x := bandL;
  for i := 0 to High(AContentWidths) do
  begin
    w := AContentWidths[i];
    if w < AMinCellWidth then w := AMinCellWidth;
    // A cell of no width is not a cell: it takes neither room nor a gap.
    if w <= 0 then Continue;
    // Does not fit WHOLE -> this cell is empty, and so is every cell after it: x only ever
    // moves right, so nothing further along can fit either.
    if x + w > bandR then Break;
    Result[i] := Rect(x, bandT, x + w, bandB);
    Inc(x, w + AGap);
  end;
end;

function TyPaginationIndexAt(const ARects: TTyPaginationRects; X, Y: Integer): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(ARects) do
    if (ARects[i].Right > ARects[i].Left) and (X >= ARects[i].Left) and (X < ARects[i].Right)
       and (Y >= ARects[i].Top) and (Y < ARects[i].Bottom) then
      Exit(i);
end;

function TyPaginationPreferredWidth(APadLeft, APadRight, AGap, AMinCellWidth: Integer;
  const AContentWidths: array of Integer): Integer;
var
  i, w, laid: Integer;
begin
  if APadLeft < 0 then APadLeft := 0;
  if APadRight < 0 then APadRight := 0;
  if AGap < 0 then AGap := 0;
  if AMinCellWidth < 0 then AMinCellWidth := 0;
  Result := APadLeft + APadRight;   // an empty strip is just its own padding
  laid := 0;
  for i := 0 to High(AContentWidths) do
  begin
    w := AContentWidths[i];
    if w < AMinCellWidth then w := AMinCellWidth;
    if w <= 0 then Continue;                // TyPaginationItemRects' rule: no width, no gap
    if laid > 0 then Inc(Result, AGap);     // a gap BETWEEN cells, never around the run
    Inc(Result, w);
    Inc(laid);
  end;
end;

function TyPaginationPreferredHeight(AStripPadTop, AStripPadBottom, ALineHeight,
  ACellPadTop, ACellPadBottom, AGlyphSize: Integer): Integer;
var
  cellH: Integer;
begin
  if AStripPadTop < 0 then AStripPadTop := 0;
  if AStripPadBottom < 0 then AStripPadBottom := 0;
  if ALineHeight < 0 then ALineHeight := 0;
  if ACellPadTop < 0 then ACellPadTop := 0;
  if ACellPadBottom < 0 then ACellPadBottom := 0;
  if AGlyphSize < 0 then AGlyphSize := 0;
  cellH := ALineHeight + ACellPadTop + ACellPadBottom;
  // The arrow slot is centred in the CELL, so a cell shorter than the slot would have
  // TyPaginationGlyphRect squash the arrow (TTyTag's rule for its own close slot).
  if AGlyphSize > cellH then cellH := AGlyphSize;
  Result := AStripPadTop + cellH + AStripPadBottom;
  if Result < 1 then Result := 1;
end;

function TyPaginationGlyphRect(const ACell: TRect; ASize: Integer): TRect;
var
  cx, cy, half: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if ASize <= 0 then Exit;
  if (ACell.Right <= ACell.Left) or (ACell.Bottom <= ACell.Top) then Exit;
  cx := (ACell.Left + ACell.Right) div 2;
  cy := (ACell.Top + ACell.Bottom) div 2;
  half := ASize div 2;
  Result := Rect(cx - half, cy - half, cx - half + ASize, cy - half + ASize);
  // A slot bigger than its cell is squashed into it, never allowed to overflow.
  if Result.Left < ACell.Left then Result.Left := ACell.Left;
  if Result.Top < ACell.Top then Result.Top := ACell.Top;
  if Result.Right > ACell.Right then Result.Right := ACell.Right;
  if Result.Bottom > ACell.Bottom then Result.Bottom := ACell.Bottom;
end;

{ --- TTyPagination -------------------------------------------------------------------- }

constructor TTyPagination.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // One page, showing it: the resting state of a host that has data but only a screenful.
  FPageCount := 1;
  FPageIndex := 0;
  FSiblingCount := 1;
  FBoundaryCount := 1;
  FShowPrevNext := True;
  FHoverIndex := -1;
  FPendingPageIndex := 0;
  FHasPendingIndex := False;
  TabStop := True;   // the point of the windowed base class: it takes focus and arrow keys
  // A drop size that holds a fully-elided run at the default knobs without dropping a cell:
  // prev + 1 + ... + 97 + 98 + 99 + ... + 195 + next = 9 cells of the 32px floor, 8 gaps of 4.
  Width := 320;
  Height := 32;
end;

function TTyPagination.GetStyleTypeKey: string;
begin
  Result := 'TyPagination';
end;

{ --- the item list -------------------------------------------------------------------- }

function TTyPagination.TyPaginationItemList: TTyPaginationItems;
begin
  Result := TyPaginationItems(FPageCount, FPageIndex, FSiblingCount, FBoundaryCount,
    FShowPrevNext);
end;

function TTyPagination.ItemCount: Integer;
begin
  Result := Length(TyPaginationItemList);
end;

{ --- properties ----------------------------------------------------------------------- }

procedure TTyPagination.Refit;
begin
  // Every one of these properties changes the ITEM LIST, and the cells are not equal-width,
  // so an auto-sized strip must re-fit rather than merely repaint.
  if AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
  if not (csLoading in ComponentState) then Invalidate;
end;

procedure TTyPagination.SetPageCount(AValue: Integer);
var
  valid: Integer;
begin
  if AValue < 0 then AValue := 0;
  if FPageCount = AValue then Exit;
  FPageCount := AValue;
  { During csLoading PageIndex may not have arrived yet; Loaded does the one validation once
    both are whole. Outside it, a shorter run can strand the current page past the end:
    re-clamp SILENTLY, because setting PageCount is the host's own action (it just re-queried
    its data) and it reads PageIndex back itself -- OnChange is for a gesture the host did
    not make. (TTySegmented.ItemsChanged's rule.) }
  if not (csLoading in ComponentState) then
  begin
    valid := TyPaginationValidIndex(FPageIndex, FPageCount);
    if valid <> FPageIndex then FPageIndex := valid;
  end;
  Refit;
end;

procedure TTyPagination.SetPageIndex(AValue: Integer);
var
  valid: Integer;
begin
  { During csLoading the run length may not be known yet, so validating against it would
    silently drop a streamed page. Park it; Loaded applies it once PageCount is whole
    (mirrors TTySegmented.SetItemIndex). }
  if csLoading in ComponentState then
  begin
    FPendingPageIndex := AValue;
    FHasPendingIndex := True;
    Exit;
  end;
  valid := TyPaginationValidIndex(AValue, FPageCount);
  if valid = FPageIndex then Exit;
  FPageIndex := valid;
  Refit;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyPagination.SetSiblingCount(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FSiblingCount = AValue then Exit;
  FSiblingCount := AValue;
  Refit;
end;

procedure TTyPagination.SetBoundaryCount(AValue: Integer);
begin
  // Below 1 the first and last pages would vanish behind an ellipsis with no way to reach
  // them -- the one thing a pagination must always offer.
  if AValue < 1 then AValue := 1;
  if FBoundaryCount = AValue then Exit;
  FBoundaryCount := AValue;
  Refit;
end;

procedure TTyPagination.SetShowPrevNext(AValue: Boolean);
begin
  if FShowPrevNext = AValue then Exit;
  FShowPrevNext := AValue;
  if not FShowPrevNext then
    // The arrows are gone: a hover index pointing at one of them would now light an
    // unrelated cell.
    FHoverIndex := -1;
  Refit;
end;

procedure TTyPagination.Loaded;
var
  pending: Integer;
begin
  inherited Loaded;
  if FHasPendingIndex then
  begin
    pending := FPendingPageIndex;
    FHasPendingIndex := False;
    FPendingPageIndex := 0;
  end
  else
    pending := FPageIndex;
  // Applied SILENTLY: streaming a form is not a user gesture, and the .lfm's own OnChange
  // handler is already wired by now -- firing it here would hand the host a "the user turned
  // the page" event before the form is even shown.
  FPageIndex := TyPaginationValidIndex(pending, FPageCount);
  Invalidate;
end;

{ --- state / style -------------------------------------------------------------------- }

function TTyPagination.CellVariant(AKind: TTyPaginationItemKind): string;
begin
  Result := TyPaginationItemVariant(AKind);
  if Trim(StyleClass) <> '' then
    Result := Result + ' ' + Trim(StyleClass);
end;

function TTyPagination.CellStates(const AItem: TTyPaginationItem;
  AIndex: Integer): TTyStateSet;
begin
  Result := [];
  // The SAME resting state TTyButton.Down injects, so one ':selected' theme rule styles the
  // pressed button and the current page alike.
  if (AItem.Kind = pikPage) and (AItem.Page = FPageIndex) then Include(Result, tysSelected);
  if not Enabled then
  begin
    { Disabled KEEPS :selected -- TTySegmented's deviation from TTyButton.Down, for the same
      reason: a greyed-out pagination must still show WHICH page is in force. Losing the chip
      would read as "no page", not as "you cannot change this". The cascade does the rest --
      ResolveLayer applies :selected first as the resting layer and :disabled LAST at the
      highest precedence, so the chip survives while the disabled ink wins over it.
      Hover is deliberately absent: a disabled control takes none. }
    Include(Result, tysDisabled);
    Exit;
  end;
  if AItem.Page < 0 then
  begin
    { An item with no target page is INERT: every ellipsis, and a prev at page 0 / a next at
      the last page. Inert reads as :disabled -- that is exactly the state a theme already
      has for "you cannot click this", so the four kinds need no state vocabulary of their
      own, and the paint agrees with MouseDown by construction (both read Page < 0). }
    Include(Result, tysDisabled);
    Exit;
  end;
  { No tysFocused here, deliberately: focus belongs to the WHOLE strip, not to a cell. It
    needs no code -- the base's CurrentStates already hands tysFocused to the STRIP's own
    style, so a plain outline rule on the 'TyPagination:focus' selector rings it through
    DrawFrame like every other focusable control here. }
  if AIndex = FHoverIndex then Include(Result, tysHover);
  if Result = [] then Include(Result, tysNormal);
end;

function TTyPagination.CellStyle(const AItem: TTyPaginationItem;
  AIndex: Integer): TTyStyleSet;
begin
  Result := ActiveController.Model.ResolveStyle('TyPaginationItem', CellVariant(AItem.Kind),
    CellStates(AItem, AIndex));
end;

function TTyPagination.CellTextStyle(const AStrip, ACell: TTyStyleSet): TTyStyleSet;
{ The label's ink and font: the cell's own where the theme sets them, the strip's otherwise.
  This is the house degradation rule (no colour => inherit the parent's ink) extended to the
  font by the same logic -- a theme that styles only TyPagination must still get legible,
  correctly-sized page numbers, and NEVER a hard-coded colour. }
begin
  Result := ACell;
  if not (tpTextColor in ACell.Present) then
  begin
    Result.TextColor := AStrip.TextColor;
    if tpTextColor in AStrip.Present then Include(Result.Present, tpTextColor);
  end;
  if not (tpFontName in ACell.Present) then
  begin
    Result.FontName := AStrip.FontName;
    if tpFontName in AStrip.Present then Include(Result.Present, tpFontName);
  end;
  if not (tpFontSize in ACell.Present) then
  begin
    Result.FontSize := AStrip.FontSize;
    if tpFontSize in AStrip.Present then Include(Result.Present, tpFontSize);
  end;
  if not (tpFontWeight in ACell.Present) then
  begin
    Result.FontWeight := AStrip.FontWeight;
    if tpFontWeight in AStrip.Present then Include(Result.Present, tpFontWeight);
  end;
end;

{ --- measurement + geometry ----------------------------------------------------------- }

function TTyPagination.ContentWidthsWith(APainter: TTyPainter;
  const AList: TTyPaginationItems): TTyPaginationWidths;
var
  cellS, stripS, txtS: TTyStyleSet;
  i, natural, glyphSz: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AList));
  glyphSz := APainter.Scale(ActiveController.Metric(TyPaginationGlyphSizeVar,
    TyPaginationGlyphSize));
  // The RESTING strip style — the same font the paint inherits into a cell via CellTextStyle.
  // MEASURE the label with THAT font, not the cell's un-inherited one, or a theme that sets a
  // font on TyPagination but not TyPaginationItem sizes cells for the default 9px while the
  // paint draws them at the strip's font -> the labels are clipped/ellipsised in cells too
  // narrow. (Resting, not CurrentStyle: width must not depend on hover/focus.)
  stripS := ActiveController.Model.ResolveStyle('TyPagination', StyleClass, [tysNormal]);
  for i := 0 to High(AList) do
  begin
    // The RESTING style of THIS kind: a theme that makes the current page bold must not make
    // the strip's width depend on which page is current, but a per-kind rule
    // (TyPaginationItem.ellipsis { padding: 0px; }) must still be honoured.
    cellS := ActiveController.Model.ResolveStyle('TyPaginationItem',
      CellVariant(AList[i].Kind), [tysNormal]);
    txtS := CellTextStyle(stripS, cellS);   // inherit the strip's font, exactly as the paint does
    if AList[i].Kind in [pikPrev, pikNext] then
      natural := glyphSz   // the arrows are a fixed slot, not text
    else
      natural := APainter.MeasureText(TyPaginationItemLabel(AList[i]), txtS.FontName,
        ResolveFontSize(txtS), txtS.FontWeight).cx;
    if natural < 0 then natural := 0;
    Result[i] := natural + APainter.Scale(cellS.Padding.Left)
      + APainter.Scale(cellS.Padding.Right);
  end;
end;

function TTyPagination.CellRectsWith(APainter: TTyPainter; const AStrip: TTyStyleSet;
  const AList: TTyPaginationItems; AWidth, AHeight: Integer): TTyPaginationRects;
begin
  // APainter.Scale is the same logical->device conversion the painter applies to every themed
  // value it draws, so the rects the hit-test measures are the rects the paint drew.
  Result := TyPaginationItemRects(AWidth, AHeight,
    APainter.Scale(AStrip.Padding.Left), APainter.Scale(AStrip.Padding.Top),
    APainter.Scale(AStrip.Padding.Right), APainter.Scale(AStrip.Padding.Bottom),
    APainter.Scale(ActiveController.Metric(TyPaginationGapVar, TyPaginationGap)),
    APainter.Scale(ActiveController.Metric(TyPaginationMinCellWidthVar,
      TyPaginationMinCellWidth)),
    ContentWidthsWith(APainter, AList));
end;

function TTyPagination.CellRectsFor(AWidth, AHeight, APPI: Integer): TTyPaginationRects;
var
  P: TTyPainter;
begin
  if APPI <= 0 then APPI := 96;
  P := TTyPainter.Create;
  try
    P.BeginPaint(nil, Rect(0, 0, 1, 1), APPI);   // 1x1: nothing is drawn, only measured
    Result := CellRectsWith(P, CurrentStyle, TyPaginationItemList, AWidth, AHeight);
    P.EndPaint;   // nil canvas -> no blit, just frees the measure bitmap
  finally
    P.Free;
  end;
end;

function TTyPagination.TyPaginationCellRect(AIndex: Integer): TRect;
var
  rects: TTyPaginationRects;
begin
  Result := Rect(0, 0, 0, 0);
  rects := CellRectsFor(ClientWidth, ClientHeight, Font.PixelsPerInch);
  if (AIndex >= 0) and (AIndex <= High(rects)) then Result := rects[AIndex];
end;

function TTyPagination.TyPaginationCellAt(X, Y: Integer): Integer;
begin
  Result := TyPaginationIndexAt(
    CellRectsFor(ClientWidth, ClientHeight, Font.PixelsPerInch), X, Y);
end;

procedure TTyPagination.CalculatePreferredSize(var PreferredWidth,
  PreferredHeight: Integer; WithThemeSpace: Boolean);
var
  P: TTyPainter;
  S, refS: TTyStyleSet;
  lst: TTyPaginationItems;
  wds: TTyPaginationWidths;
  ppi, lineH: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  lst := TyPaginationItemList;
  P := TTyPainter.Create;
  try
    P.BeginPaint(nil, Rect(0, 0, 1, 1), ppi);
    wds := ContentWidthsWith(P, lst);
    // The height comes from the PAGE cell's resting style and a stable reference glyph:
    // page numbers are the strip's baseline content, so a run whose window happens to be all
    // ellipses is still exactly as tall as any other.
    refS := ActiveController.Model.ResolveStyle('TyPaginationItem', CellVariant(pikPage),
      [tysNormal]);
    lineH := P.MeasureText('Ag', refS.FontName, ResolveFontSize(refS), refS.FontWeight).cy;
    if lineH < 1 then lineH := 1;
    PreferredWidth := TyPaginationPreferredWidth(
      P.Scale(S.Padding.Left), P.Scale(S.Padding.Right),
      P.Scale(ActiveController.Metric(TyPaginationGapVar, TyPaginationGap)),
      P.Scale(ActiveController.Metric(TyPaginationMinCellWidthVar, TyPaginationMinCellWidth)),
      wds);
    PreferredHeight := TyPaginationPreferredHeight(
      P.Scale(S.Padding.Top), P.Scale(S.Padding.Bottom), lineH,
      P.Scale(refS.Padding.Top), P.Scale(refS.Padding.Bottom),
      P.Scale(ActiveController.Metric(TyPaginationGlyphSizeVar, TyPaginationGlyphSize)));
    P.EndPaint;
  finally
    P.Free;
  end;
  if PreferredWidth < 1 then PreferredWidth := 1;
  if PreferredHeight < 1 then PreferredHeight := 1;
end;

{ --- input ---------------------------------------------------------------------------- }

procedure TTyPagination.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  lst: TTyPaginationItems;
  hit: Integer;
begin
  if not Enabled then Exit;
  // The base sets FPressed and moves focus here (TabStop + CanFocus), so a click behaves like
  // a Tab and the arrow keys work straight after it.
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  hit := TyPaginationCellAt(X, Y);
  if hit < 0 then Exit;   // a gutter between cells belongs to none: inert, not "the nearest"
  lst := TyPaginationItemList;
  if hit > High(lst) then Exit;
  // ONE rule for all four kinds: a click goes to the cell's target page, and a cell with no
  // target (an ellipsis; a prev/next at the end of the run) does nothing. Turning the page on
  // PRESS rather than release is the house rule for a switch (TTySegmented, TTyCustomTabStrip).
  if lst[hit].Page >= 0 then PageIndex := lst[hit].Page;
end;

procedure TTyPagination.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  hit: Integer;
begin
  if not Enabled then Exit;
  inherited MouseMove(Shift, X, Y);
  // The raw cell index, inert cells included: CellStates is what decides that an inert cell
  // does not light up, so the two rules live in one place.
  hit := TyPaginationCellAt(X, Y);
  if hit <> FHoverIndex then
  begin
    FHoverIndex := hit;
    Invalidate;
  end;
end;

procedure TTyPagination.MouseLeave;
begin
  inherited MouseLeave;   // clears the strip's own hover
  if FHoverIndex <> -1 then
  begin
    FHoverIndex := -1;
    Invalidate;
  end;
end;

procedure TTyPagination.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  if FPageCount <= 0 then Exit;
  { Left/Right turn the page -- the reason this control is focusable at all. Every handled key
    is consumed (Key := 0) so it never also reaches the form. Home/End jump to the ends of the
    run, matching TTySegmented's keyboard. }
  case Key of
    VK_LEFT:
      begin
        PageIndex := TyPaginationStepIndex(FPageIndex, FPageCount, -1);
        Key := 0;
      end;
    VK_RIGHT:
      begin
        PageIndex := TyPaginationStepIndex(FPageIndex, FPageCount, 1);
        Key := 0;
      end;
    VK_HOME:
      begin
        PageIndex := 0;
        Key := 0;
      end;
    VK_END:
      begin
        PageIndex := FPageCount - 1;
        Key := 0;
      end;
  end;
end;

{ --- painting ------------------------------------------------------------------------- }

procedure TTyPagination.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, cellS, txtS: TTyStyleSet;
  R, cellR, txtR, glyphR: TRect;
  lst: TTyPaginationItems;
  rects: TTyPaginationRects;
  i, glyphSz: Integer;
begin
  P := TTyPainter.Create;
  try
    // A (0,0)-local rect: the painter builds a (W x H) bitmap and blits it at ARect.Left/Top,
    // so a non-zero ARect origin would shift the whole strip.
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    // The strip: background + border + shadow + opacity, all from the resolved TyPagination
    // style. DrawFrame fills the parent's opaque surface first, which a WINDOWED control needs
    // whatever the theme says (its own window shows through the corner gaps otherwise) --
    // everything of OURS below is gated on the theme having defined the key.
    DrawFrame(P, R, S);
    if not (tpBackground in S.Present) then
    begin
      // No TyPagination rule -> draw nothing at all, degrade rather than invent a look.
      P.EndPaint;
      Exit;
    end;

    lst := TyPaginationItemList;
    rects := CellRectsWith(P, S, lst, R.Right, R.Bottom);
    glyphSz := P.Scale(ActiveController.Metric(TyPaginationGlyphSizeVar,
      TyPaginationGlyphSize));

    for i := 0 to High(rects) do
    begin
      cellR := rects[i];
      // Empty = the cell did not fit; it is not painted and not hit-testable, and those are
      // the same fact (both read this array).
      if (cellR.Right <= cellR.Left) or (cellR.Bottom <= cellR.Top) then Continue;
      cellS := CellStyle(lst[i], i);

      // The chip. An undefined TyPaginationItem key leaves no background -> no chip, and the
      // labels below still draw: a theme that fills only :selected gets the classic "only the
      // current page has a chip" for free, with no code branch of its own.
      if tpBackground in cellS.Present then
        P.FillBackground(cellR, cellS.Background, TyEffectiveCorners(cellS));
      if TyBorderVisible(cellS) then
        P.StrokeBorder(cellR, TyEffectiveCorners(cellS), cellS.BorderWidth, cellS.BorderColor);

      txtS := CellTextStyle(S, cellS);
      case lst[i].Kind of
        pikPrev, pikNext:
          begin
            // tgArrowLeft/tgArrowRight rather than a chevron pair: the painter has
            // tgChevronRight but no tgChevronLeft, and half a chevron pair would read as two
            // different marks. Both are theme-overridable with an icon-font codepoint
            // (--glyph-arrow-left / --glyph-arrow-right), which is where a skin that wants
            // chevrons puts them (v3/C5).
            glyphR := TyPaginationGlyphRect(cellR, glyphSz);
            if glyphR.Right > glyphR.Left then
            begin
              if lst[i].Kind = pikPrev then
                // Pad 1, not the default 4: glyphR is a slot already measured from
                // --pagination-glyph-size, so that token must mean the ARROW's size. The
                // default pad eats 9 logical px and leaves an unreadable 3px smudge.
                TyDrawGlyph(P, ActiveController, glyphR, tgArrowLeft, txtS.TextColor, 1, 1)
              else
                TyDrawGlyph(P, ActiveController, glyphR, tgArrowRight, txtS.TextColor, 1, 1);
            end;
          end;
      else
        // The label, centred in the cell's padded band and ellipsised: a cell narrower than
        // its number shows '1...', not a glyph sheared at the clip edge. No mnemonic parsing
        // -- there is no Alt+key path here, and a page number has no '&' in it anyway.
        txtR := Rect(cellR.Left + P.Scale(cellS.Padding.Left),
                     cellR.Top + P.Scale(cellS.Padding.Top),
                     cellR.Right - P.Scale(cellS.Padding.Right),
                     cellR.Bottom - P.Scale(cellS.Padding.Bottom));
        if (txtR.Right > txtR.Left) and (txtR.Bottom > txtR.Top) then
          P.DrawText(txtR, TyPaginationItemLabel(lst[i]), txtS.FontName,
            ResolveFontSize(txtS), txtS.FontWeight, txtS.TextColor, taCenter, tlCenter, True);
      end;
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyPagination.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
