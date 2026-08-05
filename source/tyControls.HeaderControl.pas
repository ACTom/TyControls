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

  { One header section's model. Alignment is the caption alignment inside the cell.

    Visible is stored INVERTED (FHidden) on purpose. This is a value record, so a section
    springs into existence zero-filled -- by SetLength, by Default(), by a host building one
    to hand to Sections[i] := -- and a plain `Visible: Boolean` field would make every one of
    those born HIDDEN, which is the opposite of THeaderSection.Visible's `default true`
    (comctrls.pp:3996). Inverting the storage makes the zero value mean visible; the property
    is the only thing anyone reads or writes, and it carries the LCL name. }
  TTyHeaderSection = record
  private
    FHidden: Boolean;
    function GetVisible: Boolean;
    procedure SetVisible(AValue: Boolean);
  public
    Text: string;
    Width: Integer;                 // logical px
    Alignment: TAlignment;
    SortDirection: TTyHeaderSortDirection;
    { Per-section resize constraints, logical px, both zero-means-unset so a zero-filled
      record keeps today's behaviour:
        MinWidth = 0  -> the strip-wide floor TyHeaderMinSectionWidth (16) applies;
        MinWidth > 0  -> that value IS the floor, ABOVE OR BELOW 16. Which is the point:
                         a 12px checkbox column is a real column and the shared 16px floor
                         made it inexpressible.
        MaxWidth = 0  -> unbounded (LCL spells this 10000; zero is the value a record
                         gets for free, and "no cap" is what the number means either way). }
    MinWidth: Integer;
    MaxWidth: Integer;
    { Hide a section without deleting it, so a "choose columns" menu can put it back with
      its width and sort state intact. A hidden section keeps its place in the index order
      and tiles zero-wide; it is never hit-tested, never painted, and its boundary cannot
      be grabbed. }
    property Visible: Boolean read GetVisible write SetVisible;
  end;
  TTyHeaderSectionArray = array of TTyHeaderSection;

  TTyHeaderControl = class;   { forward — the events below name the strip, as LCL's do }

  { Which PHASE of a divider drag an OnSectionTrack call is reporting. Values named for
    LCL's TSectionTrackState (comctrls.pp:4021) so a `case AState of tsTrackBegin..`
    lifted out of a THeaderControl handler compiles here unedited. }
  TTyHeaderTrackState = (tsTrackBegin, tsTrackMove, tsTrackEnd);

  { Fired when a section body is clicked (not a resize). AIndex is the section.

    LCL passes the THeaderSection OBJECT (comctrls.pp:4025). We have no such object --
    a section is a value record in a plain array -- and the index is what identifies one:
    every facet the object would expose is one hop away as AHeader.SectionText[AIndex],
    .SectionWidth[AIndex], .Sort[AIndex], .Sections[AIndex]. The first argument IS typed
    though: it used to be a bare TObject, so a handler that wanted the strip had to cast
    the one thing the event was certain about. }
  TTyHeaderSectionEvent = procedure(AHeader: TTyHeaderControl; AIndex: Integer) of object;
  { Fired ONCE, when a divider drag is released. AWidth is the settled logical width.
    LCL: TCustomSectionNotifyEvent (comctrls.pp:4025), whose handler reads Section.Width
    -- AWidth is that same number, handed over directly. }
  TTyHeaderResizeEvent = procedure(AHeader: TTyHeaderControl; AIndex, AWidth: Integer) of object;
  { Fired at EVERY phase of a divider drag. LCL: TCustomSectionTrackEvent
    (comctrls.pp:4022), which carries the phase for the same reason we now do.

    Without AState this event could report the width stream but not its ENDS, so the one
    job a continuous event exists for -- start a live preview when the drag opens, tear it
    down when it closes -- was not expressible: a handler saw a run of identical calls and
    had to guess which was the first and which the last. }
  TTyHeaderTrackEvent = procedure(AHeader: TTyHeaderControl; AIndex, AWidth: Integer;
    AState: TTyHeaderTrackState) of object;

  { TTyHeaderControl — a standalone column-header strip.

    An ordered list of SECTIONS, each with a caption, a logical width, a caption
    alignment and a sort state. The strip draws each section (caption + the divider it
    shares with the next section + a sort-indicator triangle when sorted) and
    hover-highlights the section under the mouse.

    Interaction:
      * click a section body  -> toggles its sort (none->asc->desc->asc...) and
        fires OnSectionClick;
      * drag a section BOUNDARY (within the resize grip) -> resizes the section that
        boundary belongs to, using MouseCapture; OnSectionTrack reports every phase of
        the drag and OnSectionResize fires once, on release.

    MIRRORING: BiDiMode = bdRightToLeft lays the whole strip out right-to-left -- section 0
    against the right edge, captions aligned right, divider and sort triangle on each cell's
    other side, and the drag delta inverted. The HIT TEST mirrors with it, because paint and
    both hit tests read their rects out of the one pure function TyHeaderSectionRects; see
    its comment for why nothing here may compute an x of its own.

    Uses its own 'TyHeaderControl' typeKey for the strip background/border (GetStyleTypeKey
    overrides it); each section is drawn with the 'TyTreeHeaderSection' resolved style
    (+ :hover / :selected states) — NO new .tycss. All colours are theme-driven. }

  TTyHeaderControl = class(TTyCustomControl)
  private
    FSections: TTyHeaderSectionArray;
    FHotIndex: Integer;             // section under the mouse (-1 none)
    FResizing: Boolean;
    FResizeIndex: Integer;          // section whose shared edge is being dragged (its right, or its left when mirrored)
    FResizeStartX: Integer;         // device X where the drag began
    FResizeStartW: Integer;         // logical width of FResizeIndex at drag start
    FOnSectionClick: TTyHeaderSectionEvent;
    FOnSectionResize: TTyHeaderResizeEvent;
    FOnSectionTrack: TTyHeaderTrackEvent;
    { A15: the hover handler used to hard-assign crDefault, which silently threw away
      whatever Cursor the caller had set on the strip. Remember it instead. }
    FSavedCursor: TCursor;
    FCursorOverridden: Boolean;
    procedure SetResizeCursor(AOn: Boolean);
    function GetSectionCount: Integer;
    function GetSection(AIndex: Integer): TTyHeaderSection;
    procedure SetSection(AIndex: Integer; const AValue: TTyHeaderSection);
    function GetSectionText(AIndex: Integer): string;
    procedure SetSectionText(AIndex: Integer; const AValue: string);
    function GetSectionWidth(AIndex: Integer): Integer;
    procedure SetSectionWidth(AIndex: Integer; AValue: Integer);
    function GetSortDirection(AIndex: Integer): TTyHeaderSortDirection;
    procedure SetSortDirection(AIndex: Integer; AValue: TTyHeaderSortDirection);
    function GetSectionVisible(AIndex: Integer): Boolean;
    procedure SetSectionVisible(AIndex: Integer; AValue: Boolean);
    function GetSectionMinWidth(AIndex: Integer): Integer;
    procedure SetSectionMinWidth(AIndex: Integer; AValue: Integer);
    function GetSectionMaxWidth(AIndex: Integer): Integer;
    procedure SetSectionMaxWidth(AIndex: Integer; AValue: Integer);
    { AWidth clamped by section AIndex's own MinWidth/MaxWidth (the strip-wide floor when
      it has no MinWidth of its own). One place, so the setter, the record write, the
      append and the live drag can never disagree about a section's limits. }
    function ClampSectionWidth(AIndex, AWidth: Integer): Integer;
    { Device-px widths (scaled) — what the pure geometry actually tiles. }
    function DeviceWidths: TIntegerDynArray;
    function GetEffectiveSectionWidth(AIndex: Integer): Integer;
  protected
    function GetStyleTypeKey: string; override;   // 'TyHeaderControl' — its own key: a standalone header control is not the tree's header band
    { The three event seams, as protected virtuals — LCL's SectionClick / SectionResize /
      SectionTrack (comctrls.pp:4066-4068). Every fire site in this control goes through
      them, so a descendant can react without stealing the application's event slot (the
      published property stays the app's) and the phase/width bookkeeping lives in exactly
      one place per event instead of at each mouse handler. }
    procedure SectionClick(AIndex: Integer); virtual;
    procedure SectionResize(AIndex: Integer); virtual;
    procedure SectionTrack(AIndex: Integer; AState: TTyHeaderTrackState); virtual;
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
    { Insert a section BEFORE AIndex, shifting the rest right; returns the index it landed
      at. AIndex past the end appends (so InsertSection(SectionCount, ...) == AddSection).
      LCL's THeaderSections has Insert (comctrls.pp:4016) and we had only append, so adding
      a column anywhere but the end meant appending it and then shuffling every caption,
      width and sort state down by hand. }
    function InsertSection(AIndex: Integer; const AText: string;
      AWidth: Integer = TyHeaderDefaultSectionWidth): Integer;
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
    { The width you SET. Note it is not always the width you SEE: the last section
      absorbs any leftover client width so the strip spans the full control (LCL leaves
      the remainder bare instead). That is deliberate, but it used to be invisible --
      you set 100, 250 got painted, and reading it back said 100, so code that laid
      anything out against this value (a grid under the header, a total-width sum) was
      quietly wrong about the last column and only the last column. Read
      EffectiveSectionWidth when you need the painted number. }
    property SectionWidth[AIndex: Integer]: Integer read GetSectionWidth write SetSectionWidth;
    { The width actually PAINTED, in logical px -- equal to SectionWidth for every
      section except the last, which may be wider. Read-only: it is a consequence of
      the layout, not an input to it. }
    property EffectiveSectionWidth[AIndex: Integer]: Integer read GetEffectiveSectionWidth;
    { Per-facet accessors for the three record fields a "choose columns" / pinned-column UI
      actually drives, so the read-modify-write-the-whole-record dance is not the only way. }
    property SectionVisible[AIndex: Integer]: Boolean read GetSectionVisible write SetSectionVisible;
    property SectionMinWidth[AIndex: Integer]: Integer read GetSectionMinWidth write SetSectionMinWidth;
    property SectionMaxWidth[AIndex: Integer]: Integer read GetSectionMaxWidth write SetSectionMaxWidth;
    property Sort[AIndex: Integer]: TTyHeaderSortDirection read GetSortDirection write SetSortDirection;
  published
    property OnSectionClick: TTyHeaderSectionEvent read FOnSectionClick write FOnSectionClick;
    { Fires ONCE, when the drag is released, with the settled width. It used to fire on
      every mouse-move pixel as well, so a handler that did anything real (re-query, relayout
      a grid, save a setting) ran hundreds of times per drag. LCL splits the two the same
      way: OnSectionTrack is the continuous one, OnSectionResize the final one. }
    property OnSectionResize: TTyHeaderResizeEvent read FOnSectionResize write FOnSectionResize;
    { Fires through a whole divider drag -- once at tsTrackBegin when it is grabbed, once
      per width-changing move at tsTrackMove, once at tsTrackEnd when it is released (just
      before OnSectionResize). AState is what makes a live preview possible: set it up on
      Begin, redraw it on Move, tear it down on End. }
    property OnSectionTrack: TTyHeaderTrackEvent read FOnSectionTrack write FOnSectionTrack;
    // Declared True to match the constructor, so a host's TabStop=False opt-out streams.
    property TabStop default True;
    property Align;
    { Every sibling in this family publishes Anchors (TTyTreeView, TTyListView) and the strip
      did not, so the one layout a header strip most obviously wants -- pinned left+right+top
      at a fixed height, over a list that is NOT align-docked -- could be written in code and
      not in the designer, and never streamed to the .lfm. THeaderControl publishes it
      (comctrls.pp:4122). }
    property Anchors;
  end;

{ ── PURE, headless-tested geometry (all in DEVICE pixels) ──────────────────── }

{ ARightToLeft mirrors the section ORDER: index 0 sits against AClient's right edge and the
  strip runs leftward. It is threaded through the two hit-test functions below rather than
  applied by their callers, and that is the whole design: paint, section-at-x, resize-edge-at-x
  and EffectiveSectionWidth all get their x out of THIS function, so a mirrored strip cannot
  answer a click on the side it no longer paints. Anything that computed an x of its own would
  be a second tiling, and a second tiling is the defect (plans/2026-08-04-rtl-mirroring-scope.md
  §5). The flag defaults to False so every existing caller keeps today's geometry exactly. }

{ Tile AWidths left-to-right across AClient, each section AWidths[i] wide. The LAST
  section absorbs the remainder when the widths under-fill AClient (so the strip
  always spans the full client), but keeps its OWN width when the widths already
  meet or overrun it. Every returned rect has the client's top/bottom.
  ARightToLeft reflects the finished tiling about AClient's vertical centre. }
function TyHeaderSectionRects(const AWidths: array of Integer; const AClient: TRect;
  ARightToLeft: Boolean = False): TTyHeaderRectArray;

{ Index of the section whose horizontal span contains device X (client-relative), or -1
  when X falls outside every section. Spans are half-open [Left, Right), so an INTERIOR
  boundary belongs to the section it is the LEFT edge of -- physically the one to its right,
  in either direction (which is the later section reading rightward and the earlier one when
  mirrored). Only the strip's own OUTER edge is special-cased, to the section against it. }
function TyHeaderSectionAtX(const AWidths: array of Integer; const AClient: TRect; X: Integer;
  ARightToLeft: Boolean = False): Integer;

{ Index of the section boundary being grabbed when the mouse is within AGrip device px of an
  INTERIOR boundary — the edge each section shares with its successor, which is its right in
  a left-to-right strip and its left in a mirrored one. The strip's outer edge is the control
  edge and is never a boundary. Returns the resized section's index, or -1 when no boundary is
  within the grip. The nearest boundary wins on overlap. }
function TyHeaderResizeEdgeAtX(const AWidths: array of Integer; const AClient: TRect; X, AGrip: Integer;
  ARightToLeft: Boolean = False): Integer;

{ The three points of the sort-indicator triangle, centered in a small square zone at the
  reading END of ACellRect (before the divider) — the right in a left-to-right strip, the
  left when ARightToLeft. Up for ascending, down for descending.
  ASizeDev is the triangle's width in device px. Device pixels. }
function TyHeaderSortTriangle(const ACellRect: TRect; ADir: TTyHeaderSortDirection; ASizeDev: Integer;
  ARightToLeft: Boolean = False): TTyHeaderTriangle;

implementation

{ ---- pure geometry ---- }

function TyHeaderSectionRects(const AWidths: array of Integer; const AClient: TRect;
  ARightToLeft: Boolean = False): TTyHeaderRectArray;
var
  i, n, x, w, sum, clientW, absorber: Integer;
begin
  n := Length(AWidths);
  SetLength(Result, n);
  if n = 0 then Exit;
  clientW := AClient.Right - AClient.Left;
  sum := 0;
  absorber := -1;
  for i := 0 to n - 1 do
  begin
    w := AWidths[i];
    if w < 0 then w := 0;
    Inc(sum, w);
    { The remainder goes to the last section that HAS a width. A zero-width entry is how a
      hidden section is spelled (see TTyHeaderSection.Visible), and handing the leftover to
      one would have made it the widest thing on the strip -- a section the user just hid,
      reappearing as the full remaining width. }
    if w > 0 then absorber := i;
  end;
  x := AClient.Left;
  for i := 0 to n - 1 do
  begin
    w := AWidths[i];
    if w < 0 then w := 0;
    // The absorbing section takes any remainder so the strip always fills the client,
    // but never SHRINKS below its own width (a wider-than-client set just overruns).
    if (i = absorber) and (sum < clientW) then
      w := clientW - (x - AClient.Left);
    Result[i] := Rect(x, AClient.Top, x + w, AClient.Bottom);
    Inc(x, w);
  end;
  { Mirroring is a REFLECTION of the finished tiling, not a second tiling run backwards from
    AClient.Right. That is deliberate and it is what makes the rest of this unit safe: the
    absorber, the zero-width hidden sections and the overrun case are all decided once, above,
    and reflecting cannot round any of them differently. A reverse accumulation would be a
    second copy of those three rules, and the first time one of them changed only one copy
    would be edited. LCL's own five-liner does the arithmetic (controls.pp:2966) so nobody
    here writes the off-by-one that shows up as a hairline seam and nowhere else. }
  if ARightToLeft then
    for i := 0 to n - 1 do
      Result[i] := BidiFlipRect(Result[i], AClient, True);
end;

function TyHeaderSectionAtX(const AWidths: array of Integer; const AClient: TRect; X: Integer;
  ARightToLeft: Boolean = False): Integer;
var
  rects: TTyHeaderRectArray;
  i, outer: Integer;
begin
  Result := -1;
  { The SAME tiling the paint uses, mirrored the same way. Nothing below computes an x --
    it only reads the rects back -- which is why a mirrored strip cannot answer a click on
    the side it stopped painting. }
  rects := TyHeaderSectionRects(AWidths, AClient, ARightToLeft);
  for i := 0 to High(rects) do
    // Half-open [Left, Right): every interior boundary is claimed by exactly one section,
    // in either direction. The one x this leaves unclaimed is the strip's outer edge, below.
    if (X >= rects[i].Left) and (X < rects[i].Right) then
      Exit(i);
  { The strip's own outer edge still counts as the section against it, so the rightmost
    column is not one pixel short of its border. WHICH index that is follows the tiling
    direction -- the last when sections run rightward, the first when they run leftward --
    and it is chosen here rather than searched for, because with a hidden trailing section
    two rects can share the same edge and "search" would have to break the tie. }
  if Length(rects) > 0 then
  begin
    if ARightToLeft then outer := 0 else outer := High(rects);
    if X = rects[outer].Right then Result := outer;
  end;
end;

function TyHeaderResizeEdgeAtX(const AWidths: array of Integer; const AClient: TRect; X, AGrip: Integer;
  ARightToLeft: Boolean = False): Integer;
var
  rects: TTyHeaderRectArray;
  i, edge, dist, best, bestDist, lastVisible: Integer;
begin
  Result := -1;
  if AGrip < 0 then AGrip := 0;
  rects := TyHeaderSectionRects(AWidths, AClient, ARightToLeft);
  best := -1;
  bestDist := MaxInt;
  { The last section with a width. Everything past it is hidden, so ITS right edge is the
    control edge -- the boundary that is not a boundary. }
  lastVisible := -1;
  for i := 0 to High(AWidths) do
    if AWidths[i] > 0 then lastVisible := i;
  // Interior boundaries only: the edge each of sections 0..n-2 shares with its SUCCESSOR.
  // The last one's outer edge is the control edge and is not a resizable boundary.
  for i := 0 to High(rects) - 1 do
  begin
    { A zero-width (hidden) section has no grabbable edge of its own -- its "boundary" sits
      exactly on its neighbour's, and dragging it would resize something invisible. }
    if (AWidths[i] <= 0) or (i >= lastVisible) then Continue;
    { Which SIDE of the rect that shared edge is on is the whole of the mirroring here: the
      successor sits to the right in a left-to-right strip and to the left in a mirrored one.
      Read off the rect the tiling produced, never recomputed -- so the grip is always on the
      divider the user can see, rather than on a boundary the paint stopped drawing. }
    if ARightToLeft then edge := rects[i].Left
    else edge := rects[i].Right;
    dist := Abs(X - edge);
    if (dist <= AGrip) and (dist < bestDist) then
    begin
      bestDist := dist;
      best := i;
    end;
  end;
  Result := best;
end;

function TyHeaderSortTriangle(const ACellRect: TRect; ADir: TTyHeaderSortDirection; ASizeDev: Integer;
  ARightToLeft: Boolean = False): TTyHeaderTriangle;
var
  zone, half, cx, cy, margin: Integer;
begin
  zone := ASizeDev;
  if zone < 4 then zone := 4;
  if Odd(zone) then Dec(zone);       // even -> the apex lands on a pixel
  half := zone div 2;
  { Centre the glyph in a gutter at the cell's reading END, one glyph-width in from that
    edge, vertically centred. Mirroring reflects the CENTRE and nothing else: the three
    points are symmetric about cx, so a reflected triangle is the same triangle at a
    reflected centre -- same width, same apex parity, and the up/down sense of the sort
    left alone, which is a direction of ORDER and not of reading. }
  margin := zone;
  if ARightToLeft then cx := ACellRect.Left + margin
  else cx := ACellRect.Right - margin;
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

{ ---- TTyHeaderSection ---- }

function TTyHeaderSection.GetVisible: Boolean;
begin
  Result := not FHidden;
end;

procedure TTyHeaderSection.SetVisible(AValue: Boolean);
begin
  FHidden := not AValue;
end;

{ ---- TTyHeaderControl ---- }

constructor TTyHeaderControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHotIndex := -1;
  FResizeIndex := -1;
  Width := 300;
  Height := TyDensityHeight(ActiveController, TyHeaderDefaultHeight);
  { A standalone strip is not chrome — it is the control the user acts on: a click on a
    section cycles its sort and a drag on a boundary resizes it. So the click has to move
    focus here too (TTyCustomControl.MouseDown gates that on TabStop), which is what makes
    the sort the user just triggered show a focus ring and what lets the previously focused
    editor commit. It used to be False, which read as "a header is decoration" — true of the
    header BAND a grid/tree paints inside itself, but that band is not this control (this
    one is never embedded; every user of it drops it on a form). }
  TabStop := True;
end;

{ ---- event seams ---- }

procedure TTyHeaderControl.SectionClick(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= Length(FSections)) then Exit;
  if Assigned(FOnSectionClick) then FOnSectionClick(Self, AIndex);
end;

procedure TTyHeaderControl.SectionResize(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= Length(FSections)) then Exit;
  if Assigned(FOnSectionResize) then
    FOnSectionResize(Self, AIndex, FSections[AIndex].Width);
end;

procedure TTyHeaderControl.SectionTrack(AIndex: Integer; AState: TTyHeaderTrackState);
begin
  if (AIndex < 0) or (AIndex >= Length(FSections)) then Exit;
  { The width is READ here rather than passed in, exactly as LCL reads Section.FWidth
    (headercontrol.inc:167): every phase then reports the section's width AT that phase --
    the width the drag opened at, the live width, the settled width -- and no caller can
    hand over a number that disagrees with the model. }
  if Assigned(FOnSectionTrack) then
    FOnSectionTrack(Self, AIndex, FSections[AIndex].Width, AState);
end;

function TTyHeaderControl.GetStyleTypeKey: string;
begin
  { Own key rather than the borrowed 'TyTreeHeader': a standalone header control was wearing the tree's clothes, so the same tokens meant two different things to two consumers.
    Added to 'TyTreeHeader's rule block as an extra selector, so every resolved value is
    unchanged — this opens a hook, it does not restyle anything. }
  Result := 'TyHeaderControl';
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
  FSections[AIndex].Width := ClampSectionWidth(AIndex, FSections[AIndex].Width);
  Invalidate;
end;

function TTyHeaderControl.ClampSectionWidth(AIndex, AWidth: Integer): Integer;
var
  lo, hi: Integer;
begin
  Result := AWidth;
  if (AIndex < 0) or (AIndex >= Length(FSections)) then Exit;
  lo := FSections[AIndex].MinWidth;
  { No MinWidth of its own -> the strip-wide floor. An explicit MinWidth replaces that floor
    outright rather than being raised to meet it: a 12px checkbox column is the whole reason
    the property exists, and clamping it back up to 16 would make it inexpressible again. }
  if lo <= 0 then lo := TyHeaderMinSectionWidth;
  if lo < 1 then lo := 1;
  hi := FSections[AIndex].MaxWidth;      // 0 = unbounded
  if (hi > 0) and (Result > hi) then Result := hi;
  // Floor last, so a MinWidth above MaxWidth resolves to MinWidth (LCL's CheckConstraints
  // order too) rather than silently pinning the section at a width it declared too small.
  if Result < lo then Result := lo;
end;

function TTyHeaderControl.GetSectionVisible(AIndex: Integer): Boolean;
begin
  Result := GetSection(AIndex).Visible;
end;

procedure TTyHeaderControl.SetSectionVisible(AIndex: Integer; AValue: Boolean);
begin
  if (AIndex < 0) or (AIndex >= Length(FSections)) then Exit;
  if FSections[AIndex].Visible = AValue then Exit;
  FSections[AIndex].Visible := AValue;
  { A hidden section can no longer be the hot one -- otherwise the highlight would sit on a
    cell that is not there, and MouseLeave is the only thing that would ever clear it. }
  if (not AValue) and (FHotIndex = AIndex) then FHotIndex := -1;
  Invalidate;
end;

function TTyHeaderControl.GetSectionMinWidth(AIndex: Integer): Integer;
begin
  Result := GetSection(AIndex).MinWidth;
end;

procedure TTyHeaderControl.SetSectionMinWidth(AIndex: Integer; AValue: Integer);
begin
  if (AIndex < 0) or (AIndex >= Length(FSections)) then Exit;
  if AValue < 0 then AValue := 0;
  if FSections[AIndex].MinWidth = AValue then Exit;
  FSections[AIndex].MinWidth := AValue;
  // Re-apply to the current width: a floor raised past it must take effect now, not at the
  // next drag -- otherwise the section sits below its own declared minimum.
  FSections[AIndex].Width := ClampSectionWidth(AIndex, FSections[AIndex].Width);
  Invalidate;
end;

function TTyHeaderControl.GetSectionMaxWidth(AIndex: Integer): Integer;
begin
  Result := GetSection(AIndex).MaxWidth;
end;

procedure TTyHeaderControl.SetSectionMaxWidth(AIndex: Integer; AValue: Integer);
begin
  if (AIndex < 0) or (AIndex >= Length(FSections)) then Exit;
  if AValue < 0 then AValue := 0;
  if FSections[AIndex].MaxWidth = AValue then Exit;
  FSections[AIndex].MaxWidth := AValue;
  FSections[AIndex].Width := ClampSectionWidth(AIndex, FSections[AIndex].Width);
  Invalidate;
end;

function TTyHeaderControl.GetEffectiveSectionWidth(AIndex: Integer): Integer;
var
  rects: TTyHeaderRectArray;
  ppi: Integer;
begin
  Result := 0;
  if (AIndex < 0) or (AIndex >= Length(FSections)) then Exit;
  { Go through the SAME pure function the paint goes through, so the two can never
    drift: anything else here would be a second implementation of the tiling.
    The direction is passed even though a reflection preserves every width and this
    result could not change: the moment one consumer is allowed to call the tiling with
    different arguments from the others, "they cannot diverge" stops being true by
    construction and becomes something a reader has to re-derive. }
  rects := TyHeaderSectionRects(DeviceWidths, ClientRect, IsRightToLeft);
  if AIndex >= Length(rects) then Exit;
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  Result := MulDiv(rects[AIndex].Right - rects[AIndex].Left, 96, ppi);
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
  AValue := ClampSectionWidth(AIndex, AValue);
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
    { A hidden section tiles at ZERO width rather than being dropped from the array. Dropping
      it would make the rect index stop matching the section index, and every caller here --
      paint, hit-test, resize-edge, EffectiveSectionWidth -- indexes one by the other. Zero
      keeps the two in step and is already the "nothing to draw / nothing to hit" case. }
    if FSections[i].Visible then
      Result[i] := MulDiv(FSections[i].Width, Font.PixelsPerInch, 96)
    else
      Result[i] := 0;
end;

function TTyHeaderControl.ScaledGrip: Integer;
begin
  Result := MulDiv(TyHeaderResizeGrip, Font.PixelsPerInch, 96);
  if Result < 1 then Result := 1;
end;

function TTyHeaderControl.AddSection(const AText: string; AWidth: Integer): Integer;
begin
  Result := InsertSection(Length(FSections), AText, AWidth);
end;

function TTyHeaderControl.InsertSection(AIndex: Integer; const AText: string;
  AWidth: Integer): Integer;
var
  i: Integer;
begin
  if AIndex < 0 then AIndex := 0;
  if AIndex > Length(FSections) then AIndex := Length(FSections);
  Result := AIndex;
  SetLength(FSections, Length(FSections) + 1);

  for i := High(FSections) downto AIndex + 1 do
    FSections[i] := FSections[i - 1];
  FSections[AIndex] := Default(TTyHeaderSection);   // Visible (FHidden=False), no constraints
  FSections[AIndex].Text := AText;
  FSections[AIndex].Alignment := taLeftJustify;
  FSections[AIndex].SortDirection := hsdNone;
  FSections[AIndex].Width := ClampSectionWidth(AIndex, AWidth);
  { Whatever the pointer was over, it is over a different section now. }
  if FHotIndex >= AIndex then FHotIndex := -1;
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
  i, padL, padR, sortSize, gutter, lastVisible, dividerX: Integer;
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
    { Arming the painter is safe here only because the GEOMETRY below mirrors too: each
      caption is drawn into a slot this method has already reflected, so the alignment the
      painter resolves and the slot it resolves it in agree. A strip that armed the painter
      without mirroring its tiling would push captions to the far side of cells that had not
      moved (tyControls.Painter.pas, BeginPaint's ARightToLeft). }
    P.BeginPaint(ACanvas, ARect, APPI, IsRightToLeft);
    S := CurrentStyle;
    // Strip background + border from 'TyHeaderControl' (GetStyleTypeKey).
    DrawFrame(P, R, S);

    // Section styles (base + hover). :selected is available too but the strip uses
    // hover for the pointer; a sorted section is signalled by the triangle, not fill.
    secStyle := ActiveController.Model.ResolveStyle('TyTreeHeaderSection', '', []);
    hotStyle := ActiveController.Model.ResolveStyle('TyTreeHeaderSection', '', [tysHover]);

    // Device-px widths -> tiled rects. Pure math == hit-test geometry.
    widths := DeviceWidths;
    rects := TyHeaderSectionRects(widths, R, IsRightToLeft);
    { The LAST section still on screen -- not necessarily the last index, once a trailing
      section can be hidden. Only it is allowed to skip its divider, because the edge it
      would draw on is the control's own. Deliberately an index in SECTION order, not a
      physical side: mirroring moves that section from the right end of the strip to the
      left, and it is still the one whose shared edge does not exist. }
    lastVisible := -1;
    for i := 0 to High(widths) do
      if widths[i] > 0 then lastVisible := i;

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

      // A sorted section reserves a gutter for the triangle at its reading END; the flip
      // below puts the gutter and the glyph on the same side without computing either twice.
      gutter := 0;
      if FSections[i].SortDirection <> hsdNone then
        gutter := sortSize * 2;

      textRect := Rect(cellRect.Left + padL, cellRect.Top,
        cellRect.Right - padR - gutter, cellRect.Bottom);
      { Reflect the finished slot inside its own cell rather than rebuilding it from the
        other edge: the sort gutter then lands on the same side as the triangle by
        construction, because both are the reflection of the same pair. }
      if IsRightToLeft then
        textRect := BidiFlipRect(textRect, cellRect, True);
      { Clip the caption so it never bleeds past the strip. BOTH edges are clamped because
        which one an overfull strip overruns follows the direction -- the last section runs
        off the right when reading rightward and off the left when mirrored. The clamp that
        cannot fire is a no-op, not a behaviour change. }
      clipR := textRect;
      if clipR.Right > R.Right then clipR.Right := R.Right;
      if clipR.Left < R.Left then clipR.Left := R.Left;
      if (FSections[i].Text <> '') and (clipR.Left < clipR.Right) then
        P.DrawText(clipR, FSections[i].Text, fontName, fontSize, fontWeight,
          txtColor, FSections[i].Alignment, tlCenter, True);

      // Sort-indicator triangle.
      if FSections[i].SortDirection <> hsdNone then
      begin
        tri := TyHeaderSortTriangle(cellRect, FSections[i].SortDirection, sortSize, IsRightToLeft);
        ctx := P.Bitmap.Canvas2D;
        ctx.beginPath;
        ctx.moveTo(tri[0].X + 0.5, tri[0].Y + 0.5);
        ctx.lineTo(tri[1].X + 0.5, tri[1].Y + 0.5);
        ctx.lineTo(tri[2].X + 0.5, tri[2].Y + 0.5);
        ctx.closePath;
        ctx.fillStyle(TyColorToBGRA(txtColor));
        ctx.fill;
      end;

      { The divider on the side this section shares with its successor -- its right when
        reading rightward, its left when mirrored. `i < lastVisible` needs no mirroring of
        its own: the section that skips its divider is still the LAST visible one, whose
        shared edge is the control's own edge in either direction.
        The mirrored column is Left, not Left - 1: reflecting the innermost pixel column of
        a cell (Right - 1) lands on Left, so the rule stays "the last pixel inside me". }
      if i < lastVisible then
      begin
        if IsRightToLeft then dividerX := cellRect.Left
        else dividerX := cellRect.Right - 1;
        P.Bitmap.DrawLine(dividerX, cellRect.Top,
          dividerX, cellRect.Bottom, TyColorToBGRA(dividerColor), False);
      end;
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
  edge := TyHeaderResizeEdgeAtX(widths, ClientRect, X, ScaledGrip, IsRightToLeft);
  if edge >= 0 then
  begin
    FResizing := True;
    FResizeIndex := edge;
    FResizeStartX := X;
    FResizeStartW := FSections[edge].Width;
    if HandleAllocated then MouseCapture := True;
    { Open the drag. LCL does the same on the grab (headercontrol.inc:236), BEFORE any
      movement, which is what lets a handler stand up a live preview at the width the
      section actually starts from -- computing that from the first tsTrackMove would
      already have missed the first frame. }
    SectionTrack(FResizeIndex, tsTrackBegin);
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
    { Convert the device-px drag delta to logical px and apply to the start width. The sign
      follows the tiling: a mirrored section is pinned to the strip's right edge and grows
      LEFTWARD, so the pointer moving toward smaller x is the one that widens it. Without the
      inversion the divider runs away from the pointer at twice the speed -- the strip still
      resizes, so nothing crashes and nothing looks wrong in a screenshot. }
    if IsRightToLeft then
      deltaLogical := MulDiv(FResizeStartX - X, 96, Font.PixelsPerInch)
    else
      deltaLogical := MulDiv(X - FResizeStartX, 96, Font.PixelsPerInch);
    newW := FResizeStartW + deltaLogical;
    { The drag is clamped by the SECTION's own constraints, not by the strip-wide floor
      alone. A MinWidth/MaxWidth that the setter honours and the drag ignores would be no
      constraint at all -- the user drags straight through it. }
    newW := ClampSectionWidth(FResizeIndex, newW);
    if FSections[FResizeIndex].Width <> newW then
    begin
      FSections[FResizeIndex].Width := newW;
      SectionTrack(FResizeIndex, tsTrackMove);
      Invalidate;
    end;
    Exit;
  end;
  // Not resizing: hover-track. A boundary within the grip switches the cursor to a
  // horizontal resize; otherwise track the hot section for the highlight.
  widths := DeviceWidths;
  edge := TyHeaderResizeEdgeAtX(widths, ClientRect, X, ScaledGrip, IsRightToLeft);
  SetResizeCursor(edge >= 0);
  hit := TyHeaderSectionAtX(widths, ClientRect, X, IsRightToLeft);
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
    { Close the drag, THEN report the settled size -- LCL's order (headercontrol.inc:300-301).
      It matters: a preview torn down in the tsTrackEnd handler is gone by the time the
      OnSectionResize handler relayouts, so the relayout never measures a control that is
      still wearing the preview. }
    SectionTrack(FResizeIndex, tsTrackEnd);
    // Fire the final resize once on release.
    SectionResize(FResizeIndex);
    FResizeIndex := -1;
    inherited MouseUp(Button, Shift, X, Y);
    Exit;
  end;
  inherited MouseUp(Button, Shift, X, Y);
  if (Button <> mbLeft) or not Enabled then Exit;
  // A plain click (no drag) on a section body toggles its sort and fires the event.
  widths := DeviceWidths;
  movedX := TyHeaderResizeEdgeAtX(widths, ClientRect, X, ScaledGrip, IsRightToLeft);
  if movedX >= 0 then Exit;   // released on a boundary, not a body click
  hit := TyHeaderSectionAtX(widths, ClientRect, X, IsRightToLeft);
  if hit >= 0 then
  begin
    ToggleSort(hit);
    SectionClick(hit);
  end;
end;

{ Swap in the resize cursor over a divider and put the caller's own cursor back on the
  way out -- mirrors TTyListView.SetDividerCursor. }
procedure TTyHeaderControl.SetResizeCursor(AOn: Boolean);
begin
  if AOn = FCursorOverridden then Exit;
  if AOn then
  begin
    FSavedCursor := Cursor;
    Cursor := crHSplit;
  end
  else
    Cursor := FSavedCursor;
  FCursorOverridden := AOn;
end;

procedure TTyHeaderControl.MouseLeave;
begin
  inherited MouseLeave;
  if FHotIndex <> -1 then
  begin
    FHotIndex := -1;
    Invalidate;
  end;
  SetResizeCursor(False);
end;

end.
