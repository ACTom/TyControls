unit tyControls.CoolBar;
{$mode objfpc}{$H+}

{ Phase-5 (containers) — TTyCoolBar: a REBAR band container.

  TTyCoolBar SUBCLASSES TTyControlBar (the band-packing base, built the same batch;
  GetStyleTypeKey='TyPanel' — NO new .tycss). TTyControlBar already packs each child
  control onto a horizontal band with a left gripper; TTyCoolBar upgrades every band so
  it can be:

    * MOVED   — grab a band's gripper and drag it DOWN to give the band a row of its own,
                or UP to return it to the row above. Every band has its own gripper, drawn
                immediately to its left, so every band can be grabbed.
    * RESIZED — grab that gripper and drag HORIZONTALLY to move the SEAM it sits on: the band
                BEFORE it on the row grows or shrinks, honouring that band's minimum/maximum.

    The pointer's direction picks between the two (TyCoolDragMode), as it does in Delphi's and
    Lazarus's TCoolBar.

    WHAT A GRIPPER RESIZE MEANS (corrected -- this used to be wrong). A rebar gripper is not a
    handle on its own band; it is the BOUNDARY between that band and its row predecessor.
    Dragging it moves the boundary, so one band grows by what the other gives up. Ours used to
    resize the DRAGGED band in isolation, which is not the reference behaviour and is why the
    gesture read as pointless. Lazarus's TCoolBar assigns to FVisiBands[FDraggedBandIndex-1]
    (lcl/include/coolbar.inc:938) -- the band BEFORE the dragged one. TyCoolBandSeamOwner is
    that rule, and FDragSeam is the band it names.

    A band that OPENS its row has no seam under its gripper. The reference does not leave that
    gesture dead: MouseDown routes it to a MOVE instead (coolbar.inc:899, IsFirstAtRow), and so
    does this unit -- a sideways drag on the leading band reorders it rather than doing nothing.

    WHAT DRAGGING A BAND BACK UP MEANS (the second correction). A band ends up on the next row
    for TWO different reasons: its Break says so (the user dragged it down), or it simply did
    not FIT. The drag-up gesture used to do exactly one thing -- clear Break -- which moves a
    band down by the first route and is completely inert for a band that came down by the
    second: Break was already False, so the packer overflowed it again on the very next pass.
    Widen band 1 until band 2 wraps and band 2 could then never be brought back, which is what
    the user reported. It was made worse by the reorder running first: a passing pointer
    position that crossed a neighbour's midpoint consumed the drag as a SWAP, so the swap was
    the only gesture that appeared to respond at all.

    A rejoin now takes width from the bands already on the target row, down to their MinWidths,
    the same boundary-moving arithmetic the gripper resize performs from a different gesture
    (TyCoolRowMakeRoom / RejoinRow). When the row cannot take the band even with every band at
    its minimum the gesture is REFUSED, and refused means nothing at all changes -- no width, no
    order, no Break, no OnChange. NOTE that Lazarus's TCoolBar is NOT the reference here: it has
    the same dead gesture, because CalculateAndAlign wraps purely on overflow and no path in
    that unit ever reduces another band's Width on a drop. Win32's rebar (which shrinks to each
    band's cxMinChild) is.

    HOW WIDE A BAND MAY GET. Three ceilings, composed in ONE place (BandMaxWidth): the
    hand-entered MaxWidth, a Constraints.MaxWidth on the hosted control, and -- when the band
    opts in with AutoMaxWidth -- what that control declares as its preferred width. 0 means
    "no opinion" and drops out; of what remains the smallest binds, so they cannot fight. The
    content ceiling is what stops a drag once there is no more control area left to reveal,
    which a typed-in number cannot do because it goes stale the moment the content changes.
    The FLOOR is the mirror image and equally single-sourced: BandMinWidth (a band's MinWidth,
    or the bar's DefaultBandMinWidth) is what the gripper resize AND the rejoin squeeze are
    both handed, so neither can squeeze past what the other respects.

    * REORDERED — dragging a band past a neighbour swaps the two; dragging it below the last
                row gives it a row of its own at the end. This unit used to say reordering was
                impossible because "the LCL exposes only SetZOrder(TopMost)". That was simply
                false: TWinControl.SetControlIndex (controls.pp:2400) places a child anywhere
                in its parent's list, and since the packer reads Controls[] in child order,
                moving the child IS the reorder -- pack, gripper paint and hit-test all derive
                from that one list, so there is nothing to keep in sync. TyCoolBandDropIndex is
                the (pure) rule for where a drop lands.

  Per-band metadata (a fixed/min Width the band is given) is stored keyed by the child
  TControl in FBands and dropped when the child is freed (Notification/opRemove) — never
  a parallel array indexed by position, which would desync the moment a band is removed.

  The DRAG ITSELF (mouse capture, live reorder animation) is real-machine; the two bits
  of math it needs are PURE unit-level functions exercised headlessly with no window:

    TyCoolBandResize(AStartW, ADx, AMinW, AMaxW) : Integer    // clamped new band width
    TyCoolGripperHit(ABandRect, AGripperW, APt) : Boolean     // is APt on the gripper?

  IMPORTANT (controller integration): this unit codes against TTyControlBar's PUBLIC
  contract as described — a csAcceptsControls band-packing container with per-band
  grippers and a keyed per-child band assignment. The one protected hook it would like
  the base to expose is the DEVICE-PX RECT of a band (so a gripper hit-test and the
  resize origin can reuse the base's own packing geometry instead of recomputing it).
  Until the base exposes that, TTyCoolBar computes a band rect itself from the child's
  BoundsRect (see BandRectFor) — see the summary note. }

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.ControlBar;

type
  { One band's per-child metadata, keyed by the child control (position-independent). }
  { What a gripper drag means once the pointer commits to an axis. }
  TTyCoolDrag = (cdNone, cdMove, cdResize);

  { The hosted band controls in packing order, parallel to a TTyRectArray of their rects. }
  TTyCoolBandCtls = array of TControl;

  { Band extents along the row's run, in the packer's own units. }
  TTyCoolExtents = array of Integer;

  TTyCoolBar = class;

  { One band. A COLLECTION ITEM rather than the record this used to be, because band metadata
    that only exists at run time cannot be designed: a form could host the controls but not say
    which of them breaks a row, what its caption is, or that it must not be resized. Delphi's
    and Lazarus's TCoolBand are collection items for the same reason, and Control is the same
    link back to the hosted control. }
  TTyCoolBand = class(TCollectionItem)
  private
    FControl: TControl;
    FText: string;
    FBreak: Boolean;
    FWidth: Integer;
    FMinWidth: Integer;
    FMaxWidth: Integer;
    FFixedSize: Boolean;
    FAutoMaxWidth: Boolean;
    FVisible: Boolean;
    procedure SetControl(AValue: TControl);
    procedure SetText(const AValue: string);
    procedure SetBreak(AValue: Boolean);
    procedure SetWidth(AValue: Integer);
    procedure SetAutoMaxWidth(AValue: Boolean);
    procedure SetVisible(AValue: Boolean);
  protected
    function GetDisplayName: string; override;
  public
    constructor Create(ACollection: TCollection); override;
    procedure Assign(ASource: TPersistent); override;
  published
    { The control this band wraps. A band with no control still occupies its place -- that is
      how a caption-only separator band is expressed. }
    property Control: TControl read FControl write SetControl;
    property Text: string read FText write SetText;
    { Start a new row at this band even when it would fit on the current one. }
    property Break: Boolean read FBreak write SetBreak default False;
    { Assigned logical width; 0 = auto, meaning the hosted control's own width. }
    property Width: Integer read FWidth write SetWidth default 0;
    { The floor a resize -- and now a rejoin squeeze -- may never take the band below. 0 falls
      back to the bar's DefaultBandMinWidth. ONE floor for both gestures: TyCoolBandResize and
      TyCoolRowMakeRoom are both handed TTyCoolBar.BandMinWidth and neither carries a constant
      of its own. }
    property MinWidth: Integer read FMinWidth write FMinWidth default 0;
    { A hand-entered ceiling; 0 = unbounded. See AutoMaxWidth for the derived one and
      TTyCoolBar.BandMaxWidth for the single place the two compose. }
    property MaxWidth: Integer read FMaxWidth write FMaxWidth default 0;
    { Refuses a gripper RESIZE; the band can still be moved between rows. }
    property FixedSize: Boolean read FFixedSize write FFixedSize default False;
    { CAP THE BAND AT ITS CONTENT: stop a widening drag once there is no more of the hosted
      control left to reveal, instead of at a number somebody had to type.

      MaxWidth is a fixed figure that has to be maintained by hand and goes stale the moment
      the content changes; this asks the hosted control itself. The source is its RAW preferred
      width (plus any Constraints.MaxWidth it carries) -- see TTyCoolBar.BandContentCap for why
      raw, and for why the control's own Width is the one answer that cannot be used.

      A control that declares no preferred width -- an edit, which is meaningfully any width --
      is left UNCAPPED rather than pinned: this caps bands whose content has an end, and says
      nothing about bands whose content does not. A band with no hosted control never reaches
      this question at all: with no child it is never packed, gripped or resized.

      Default OFF, so no existing form changes behaviour. }
    property AutoMaxWidth: Boolean read FAutoMaxWidth write SetAutoMaxWidth default False;
    property Visible: Boolean read FVisible write SetVisible default True;
  end;

  { The designable band list. Editing it in the Object Inspector re-lays the bar and fires the
    bar's OnChange, so a design-time change behaves exactly like a run-time one. }
  TTyCoolBands = class(TOwnedCollection)
  private
    function GetItem(AIndex: Integer): TTyCoolBand;
    procedure SetItem(AIndex: Integer; AValue: TTyCoolBand);
    function OwnerBar: TTyCoolBar;
  protected
    procedure Update(AItem: TCollectionItem); override;
  public
    constructor Create(AOwner: TPersistent);
    function Add: TTyCoolBand;
    { The band wrapping AControl, or nil. }
    function FindBand(AControl: TControl): TTyCoolBand;
    property Items[AIndex: Integer]: TTyCoolBand read GetItem write SetItem; default;
  end;

  TTyCoolBar = class(TTyControlBar)
  private
    FBandList: TTyCoolBands;           // the designable band list; Control links each to its child
    FDefaultBandMinWidth: Integer;     // fallback min when a band has none of its own
    FDragStartY: Integer;
    FDragMode: TTyCoolDrag;
    FShowText: Boolean;
    FVertical: Boolean;
    FOnChange: TNotifyEvent;
    // --- live drag state (real-machine) ---
    FDragging: Boolean;
    FDragCtl: TControl;                // the band whose gripper was grabbed
    FDragSeam: TControl;               // the band that gripper's SEAM belongs to (its row
                                       // predecessor) -- the one a resize actually moves.
                                       // nil when FDragCtl opens its row: no seam, so the
                                       // gesture is a MOVE (see TyCoolBandSeamOwner).
    FDragStartX: Integer;             // mouse X (device px) at grab
    FDragStartW: Integer;             // the SEAM OWNER's logical width at grab
    function BandTextWidth(const AText: string; const AStyle: TTyStyleSet): Integer;
    procedure SetShowText(AValue: Boolean);
    procedure SetVertical(AValue: Boolean);
    procedure Changed;
    function EnsureBand(ACtl: TControl): TTyCoolBand;   // find, or create, this child's band
    procedure SetBands(AValue: TTyCoolBands);
    procedure BandsChanged;
    function BandAtPoint(AX, AY: Integer): TControl;   // the band whose gripper is under (X,Y)
  protected
    { The laid-out bands, in the order the packer sees them, with their current rects. ONE
      reading of the layout, shared by the seam lookup and anything else that needs to know
      which bands share a row, so none of them can invent a geometry the packer never produced. }
    procedure CollectLaidOutBands(out ACtls: TTyCoolBandCtls; out ARects: TTyRectArray);
    { The band whose trailing edge ACtl's gripper sits against -- the band a gripper drag
      resizes -- or nil when ACtl opens its row and there is no seam. Thin shell over the pure
      TyCoolBandSeamOwner; protected so a test can assert the drag's precondition directly
      instead of inferring it from a width that happened not to change. }
    function SeamOwnerOf(ACtl: TControl): TControl;
    { REORDER the dragged band to wherever the pointer now indicates. True when the band
      actually moved, so the caller can stop and let the fresh layout be re-read on the next
      mouse-move rather than reasoning about rects it has just invalidated.

      The move itself is TWinControl.SetControlIndex: the packer reads Controls[] in child
      order, so changing a child's position in that list IS the reorder -- layout, gripper
      paint and hit-test all follow from the same list with nothing to keep in sync. }
    function ReorderFromPointer(AX, AY: Integer): Boolean;
    { The distance from one row to the next, in device px -- the pitch the packer advances by. }
    function RowStepPx: Integer;
    { Which row (COLUMN, when vertical) a laid-out band sits on, and which one a pointer is
      over. ONE division rule behind both, because the rejoin compares three counts -- the
      dragged band's row, the pointer's row, and the row each candidate band belongs to -- and
      any drift between them takes width from the wrong row. Mirrored, they are counted from
      the reading start, matching the order the packer laid the columns out in. }
    function RowOrdinalOfBand(const ARect: TRect): Integer;
    function RowOrdinalOfPoint(AX, AY: Integer): Integer;
    { What the packer reserves BEFORE a band: its gripper, plus its caption strip when ShowText
      is on. Composed here exactly the way TyCoolBarPack composes AGripperW with ALeadExtra, so
      the rejoin's arithmetic and the packing cannot disagree about how wide a band really is. }
    function BandLeadPx(ACtl: TControl): Integer;
    { The band's content-derived resize ceiling -- what TTyCoolBand.AutoMaxWidth turns on.
      0 = the hosted control declares nothing, so no ceiling. Protected rather than published
      because it is DERIVED: it has no setter and a published read-only property is exactly the
      "Cannot read property" / TWriter.WriteProperty trap. Ask BandMaxWidth for the effective
      ceiling; this is only one of its inputs. }
    function BandContentCap(ACtl: TControl): Integer;
    { A band's extent ALONG THE ROW'S RUN, in the packer's units: its width normally, its height
      when the bar is vertical. Every axis swaps with Vertical, including this one. }
    function BandRunExtent(ACtl: TControl): Integer;
    procedure SetBandRunExtent(ACtl: TControl; AValue: Integer);
    { REJOIN: put the dragged band back onto row ATargetRow, taking extent from the bands
      already there (down to their minimums) to make the room. This is what "drag a band back
      up" means once the band came down by OVERFLOW rather than by Break -- clearing Break, all
      the gesture used to do, cannot move a band that never had it set.

      True when the band was moved. FALSE means REFUSED, and refused means NOTHING changed: no
      width, no child index, no Break, no OnChange. See TyCoolRowMakeRoom for the order the row
      gives its width up in and for why the reference is Win32's rebar rather than the LCL's
      TCoolBar (which has this same dead gesture). }
    function RejoinRow(AX, AY, ATargetRow: Integer): Boolean;
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    { The device-px rect of ACtl's band. Derived from the child's current BoundsRect
      grown left by the gripper strip (so the gripper column is part of the band). If a
      future TTyControlBar exposes a real per-band rect, override/redirect here. }
    function BandRectFor(ACtl: TControl): TRect; virtual;
    function PackBands(const ABands: array of TControl; const ASizes: array of TSize;
      AAvail, ABandHeight, AGripperW, ASpacing: Integer): TTyRectArray; override;
    procedure PaintGrippers(APainter: TTyPainter; const AStyle: TTyStyleSet;
      ABandCount, ABandHeight, AGripperW, ASpacing: Integer); override;
    { The device-px width of the gripper strip at this control's PPI. }
    function GripperWidthPx: Integer;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Assign / query a band's fixed-or-min width (logical px). Setting it re-lays the
      bands (via the inherited container relayout). AWidth <= 0 clears it (auto). The
      value is keyed by the child, so it survives reorders and other bands' removal. }
    procedure SetBandWidth(ACtl: TControl; AWidth: Integer);
    function GetBandWidth(ACtl: TControl): Integer;
    { Per-band resize clamps (logical px). AMax = 0 means unbounded. }
    procedure SetBandMinWidth(ACtl: TControl; AMinWidth: Integer);
    procedure SetBandMaxWidth(ACtl: TControl; AMaxWidth: Integer);
    function BandMinWidth(ACtl: TControl): Integer;
    function BandMaxWidth(ACtl: TControl): Integer;
    { A band with Break starts a new row even when it would fit on the current one -- what
      dragging a band downward sets, and what Delphi's TCoolBand.Break means. Inert on the
      first band: there is no row above it to leave. }
    procedure SetBandBreak(ACtl: TControl; AValue: Boolean);
    function BandBreak(ACtl: TControl): Boolean;
    { The band's own caption. Drawn between the gripper and the child when ShowText is on, and
      the packer reserves room for it there -- a rebar band labels itself rather than relying on
      whatever control happens to be inside it. }
    procedure SetBandText(ACtl: TControl; const AValue: string);
    function BandText(ACtl: TControl): string;
    { A fixed band refuses a gripper RESIZE. It can still be moved between rows: fixing a size
      is not the same as nailing a band down. }
    procedure SetBandFixedSize(ACtl: TControl; AValue: Boolean);
    function BandFixedSize(ACtl: TControl): Boolean;
    { Cap this band's widening at its content instead of at a hand-entered MaxWidth. See
      TTyCoolBand.AutoMaxWidth for what "its content" means and what is left uncapped. }
    procedure SetBandAutoMaxWidth(ACtl: TControl; AValue: Boolean);
    function BandAutoMaxWidth(ACtl: TControl): Boolean;
    { Show or hide one band. The hosted child's own Visible is the single source of truth, so
      the packer, the hit-test and the painter cannot disagree about it. }
    procedure SetBandVisible(ACtl: TControl; AValue: Boolean);
    function BandVisible(ACtl: TControl): Boolean;
  published
    // GripperWidth is INHERITED from TTyControlBar (same field the band packing uses) — do NOT
    // redeclare it here, or the base would pack with one width while our hit-test used another.
    { Fallback resize floor for a band that has no MinWidth of its own (logical px). }
    property DefaultBandMinWidth: Integer read FDefaultBandMinWidth write FDefaultBandMinWidth default 24;
    { Draw each band's own caption between its gripper and its child, reserving room for it. }
    property ShowText: Boolean read FShowText write SetShowText default False;
    { Bands run DOWN a column instead of across a row, with each gripper above its band. Every
      axis swaps with it, including which way a drag means "move" and which means "resize". }
    property Vertical: Boolean read FVertical write SetVertical default False;
    { Fired after the band layout changes -- a band moved to another row, resized, or hidden. }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    { The bands, editable in the designer. Every per-control helper below is a facade over
      this, so code written against either sees the same state. }
    property Bands: TTyCoolBands read FBandList write SetBands;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

{ ------------------------------------------------------------------------------
  PURE, headless-tested band math (no window handle needed)
  ------------------------------------------------------------------------------ }

{ The new band width after dragging its gripper by ADx (device or logical px — the
  caller keeps units consistent) from a starting width AStartW, clamped to
  [AMinW .. AMaxW]. A non-positive AMaxW means "unbounded" (only the floor applies).
  AMinW is floored at 1 so a band never collapses to nothing. }
{ Pack COOLBAR bands: unlike a ControlBar's one-gripper-per-row, every band carries its own
  gripper immediately to its left -- that is what makes a band individually grabbable, and it is
  what Delphi's and Lazarus's TCoolBar draw. A band starts a new row when its Break flag says so,
  or when it would not fit on the current one.

  ABreaks is parallel to AChildSizes; a missing entry reads as False. ALeadExtra is likewise
  parallel and is the width reserved between a band's gripper and its child -- the band's own
  caption when ShowText is on; a missing entry reads as 0. Returns the CHILD rects
  (the band minus its gripper), so the gripper for band i is the AGripperW-wide strip immediately
  left of Result[i]. Pure: no control, no canvas, no PPI -- device px in, device px out.

  ARightToLeft MIRRORS the finished row about AAvail: bands fill from the RIGHT and each
  gripper is the strip immediately RIGHT of its child. The row-overflow rule inverts with it
  for free -- a reflection of "ran off the right end" is "ran off the left end" -- which is
  why this is one reflection at the end rather than a second, decrementing packing loop. }
function TyCoolBarPack(const AChildSizes: array of TSize; const ABreaks: array of Boolean;
  const ALeadExtra: array of Integer;
  AAvail, ABandHeight, AGripperW, ASpacing: Integer;
  ARightToLeft: Boolean = False): TTyRectArray;

{ What a gripper drag MEANS, from the travel so far. A CoolBar grip does two jobs and the
  pointer's direction picks between them -- the same disambiguation Delphi's and Lazarus's
  TCoolBar use. Below the threshold the drag is still undecided, so a twitch does neither.
  Pure so the rule is testable without a mouse. }
function TyCoolDragMode(ADx, ADy, AThreshold: Integer): TTyCoolDrag;

{ The same packing turned on its side: bands run DOWN a column, a column is ABandThick wide,
  and each band's gripper is the AGripperW-tall strip immediately ABOVE it. Break starts a new
  column. A vertical rebar is not a special case of the horizontal one -- every axis swaps --
  so it is its own function rather than a flag threaded through the other.

  ARightToLeft mirrors the COLUMN ORDER: the first column sits at the right edge and later
  columns march leftwards. The grippers do NOT move -- they are above their bands on either
  reading, because up is not a reading direction. It needs ACrossExtent, the bar's WIDTH,
  precisely because this function's AAvail is the OTHER axis (the column run, i.e. the
  height): there is nothing in its own parameters that says how wide the bar is. Left at 0 no
  mirroring is possible and none is done. }
function TyCoolBarPackVertical(const AChildSizes: array of TSize; const ABreaks: array of Boolean;
  const ALeadExtra: array of Integer;
  AAvail, ABandThick, AGripperW, ASpacing: Integer;
  ARightToLeft: Boolean = False; ACrossExtent: Integer = 0): TTyRectArray;

function TyCoolBandResize(AStartW, ADx, AMinW, AMaxW: Integer): Integer;

{ True when APt lies on the gripper strip of ABandRect: the leftmost AGripperW px
  column of the band (device px). AGripperW <= 0 -> no gripper -> always False. The
  test is half-open on the right edge (Left .. Left+AGripperW), inclusive on top,
  exclusive on bottom — matching LCL hit-testing.

  Describes the HORIZONTAL, LEFT-TO-RIGHT case only, and deliberately keeps doing so: the
  control's own hit test does not go through it (BandAtPoint tests plain containment of the
  strip BandRectFor returns, which is already on the correct side and axis), so giving this
  one a direction flag would add a second, unused statement of where the gripper is. }
function TyCoolGripperHit(const ABandRect: TRect; AGripperW: Integer; const APt: TPoint): Boolean;

{ The band whose TRAILING edge the gripper of band AIndex sits against -- the band the
  boundary belongs to, and therefore the band a gripper drag actually resizes.

  A rebar gripper is NOT a handle on its own band. It is the SEAM between that band and the one
  before it on the same row: dragging it moves the seam, so one band grows by exactly what the
  other gives up. That is what Win32's rebar does and what Lazarus's TCoolBar does --
  lcl/include/coolbar.inc:938 assigns to FVisiBands[FDraggedBandIndex-1].Width, i.e. the band
  BEFORE the dragged one, never the dragged one itself.

  Returns -1 when AIndex OPENS its row, because then there is no seam to move. The reference
  turns that gesture into a MOVE rather than a resize (coolbar.inc:899, the IsFirstAtRow branch
  of MouseDown), which is what TTyCoolBar now does too.

  Rows are identified by the packer's own Top (Left when AVertical) -- the same number
  BandRectFor reads -- so pack, paint and hit-test cannot disagree about who shares a row.
  Direction-agnostic on purpose: mirrored, band i-1 sits to the RIGHT of band i, but it is
  still the band the seam belongs to, so the index rule needs no bidi flag. }
function TyCoolBandSeamOwner(const ARects: TTyRectArray; AIndex: Integer;
  AVertical: Boolean = False): Integer;

const
  { TyCoolBandDropIndex: the pointer is past the last row, so the band gets a row of its own at
    the end. A distinct sentinel rather than Length(ARects), which would be indistinguishable
    from the ordinary "insert at the end of the current row" answer. }
  TyCoolDropNewRow = -2;

{ Where a dragged band should sit, from the pointer's position over the CURRENT layout.

  Returns the layout index the band should end up at (already accounting for its own removal,
  so the caller can hand it straight to a list move), ADragIndex when the drop changes nothing,
  or TyCoolDropNewRow to mean "past every row -- give it a row of its own at the end".

  Band reordering IS a real rebar gesture: Win32's rebar and Lazarus's TCoolBar both do it, the
  latter by assigning TCoolBand.Index on drop (lcl/include/coolbar.inc:1043-1079). This unit
  used to claim it was impossible because "the LCL exposes only SetZOrder(TopMost)" -- that is
  simply wrong; TWinControl.SetControlIndex (controls.pp:2400) places a child at any position
  in its parent's list, which is the whole primitive needed.

  The band is picked by MIDPOINT rather than by the reference's trailing edge, because this
  commits LIVE during the drag rather than on mouse-up: once two bands have swapped, the
  pointer sits over the dragged band itself, which returns ADragIndex and settles. A
  trailing-edge rule re-evaluated every mouse-move would oscillate across the boundary.

  AVertical TRANSPOSES the whole question rather than branching inside it: bands then run down a
  COLUMN, so the group a drop lands in is picked by X and the order within it by Y, and "past
  the last row" becomes "right of the last column". Done by swapping the axes of the inputs and
  running the identical rule, because two hand-written copies of this logic is exactly how one
  axis ends up a pixel or a comparison out of step with the other. ARightToLeft is ignored when
  vertical: mirroring a vertical rebar reverses the column ORDER, and within a column top-to-
  bottom is not a reading direction.

  Pure -- rects in, index out, no control and no canvas -- so every rule above is testable
  without a mouse. }
function TyCoolBandDropIndex(const ARects: TTyRectArray; ADragIndex: Integer;
  const APt: TPoint; ARightToLeft: Boolean = False;
  AVertical: Boolean = False): Integer;

{ MAKE ROOM on a row for one more band, by taking extent from the bands already there.

  This is the arithmetic behind "drag a band back up onto a row that is already full". A band
  reaches the next row for TWO different reasons -- its Break says so, or it simply did not fit
  -- and only the first of them can be undone by clearing Break. A band that came down by
  OVERFLOW has Break = False already, so the drag-up gesture used to be silently inert: the
  packer overflowed it again on the very next pass. The row has to give up the width instead.

  AExtents / AMins / ALeads describe the bands ALREADY on the row, in row order, in the
  PACKER's units (device px). ALeads is what the packer reserves before each band: its gripper,
  plus its caption strip when ShowText is on. AInsertAt is where the joining band lands within
  that row (0 .. Length(AExtents)); AJoinLead and AJoinExtent are the joiner's own. AAvail is
  the row's usable run and ASpacing the gap the packer leaves between two bands.

  ORDER OF GIVING. The nearest band BEFORE the insertion point gives first, then the one before
  that, and so on to the head of the row; only once that whole side is at its minimum do the
  bands AFTER the insertion point give, again nearest first. Near-side-first is the SEAM rule
  the gripper already obeys -- the boundary that moves is the one the joining band will own the
  moment it is there, so a rejoin and a gripper drag move the same edge -- and carrying on to
  the far side is what makes a refusal mean "no slack anywhere on this row" instead of the much
  weaker "no slack immediately next door".

  NOT taken from the reference. Lazarus's TCoolBar does NOT redistribute: its CalculateAndAlign
  wraps purely on overflow (RowEndHelper, coolbar.inc:1391) and no path in that unit ever
  reduces another band's Width on a drop, so the same gesture is inert there too. Win32's rebar
  is the reference that does shrink, down to each band's cxMinChild, and BandMinWidth is our
  cxMinChild.

  Returns True and fills ANewExtents when the row can take the joiner -- unchanged extents when
  nothing had to give. Returns False and leaves ANewExtents a copy of AExtents when it cannot
  fit even with every band at its minimum: a refusal must not half-apply, or the user is left
  with a row that shrank for nothing and a band that still did not arrive. }
function TyCoolRowMakeRoom(const AExtents, AMins, ALeads: array of Integer;
  AInsertAt, AJoinLead, AJoinExtent, AAvail, ASpacing: Integer;
  out ANewExtents: TTyCoolExtents): Boolean;

implementation

// -----------------------------------------------------------------------------
// Pure functions
// -----------------------------------------------------------------------------
function TyCoolBarPack(const AChildSizes: array of TSize; const ABreaks: array of Boolean;
  const ALeadExtra: array of Integer;
  AAvail, ABandHeight, AGripperW, ASpacing: Integer;
  ARightToLeft: Boolean = False): TTyRectArray;
var
  n, i, x, y, w, rowStart, lead: Integer;
  brk, firstOnRow: Boolean;
  span: TRect;
begin
  Result := nil;
  n := Length(AChildSizes);
  SetLength(Result, n);
  if n = 0 then Exit;
  if ABandHeight < 0 then ABandHeight := 0;
  if AGripperW < 0 then AGripperW := 0;
  if ASpacing < 0 then ASpacing := 0;

  x := 0;
  y := 0;
  firstOnRow := True;
  for i := 0 to n - 1 do
  begin
    w := AChildSizes[i].cx;
    if w < 0 then w := 0;
    brk := (i < Length(ABreaks)) and ABreaks[i];
    lead := AGripperW;
    if (i < Length(ALeadExtra)) and (ALeadExtra[i] > 0) then Inc(lead, ALeadExtra[i]);
    { A break is honoured even for a band that would have fitted -- that is the whole point of
      dragging a band onto a row of its own. The first band can never break: there is no row
      above it to leave. }
    if (not firstOnRow) and (brk or (x + lead + w > AAvail)) then
    begin
      Inc(y, ABandHeight + ASpacing);
      x := 0;
      firstOnRow := True;
    end;
    rowStart := x + lead;                 // the child begins after its gripper (and caption)
    if rowStart + w > AAvail then         // a band wider than the row is clamped to it
      w := AAvail - rowStart;
    if w < 0 then w := 0;
    Result[i].Left := rowStart;
    Result[i].Top := y;
    Result[i].Right := rowStart + w;
    Result[i].Bottom := y + ABandHeight;
    x := rowStart + w + ASpacing;
    firstOnRow := False;
  end;
  { MIRROR once, at the end, through LCL's BidiFlipRect (controls.pp:2966). Rows are
    untouched: top-to-bottom is not a reading direction. }
  if ARightToLeft then
  begin
    span := Rect(0, 0, AAvail, 0);
    for i := 0 to n - 1 do
      Result[i] := BidiFlipRect(Result[i], span, True);
  end;
end;

function TyCoolDragMode(ADx, ADy, AThreshold: Integer): TTyCoolDrag;
begin
  if AThreshold < 1 then AThreshold := 1;
  { Vertical wins ties-with-intent: a band is MOVED between rows far more often than it is
    resized, and a horizontal wobble during a downward drag must not flip the meaning. }
  if (Abs(ADy) >= AThreshold) and (Abs(ADy) > Abs(ADx)) then
    Result := cdMove
  else if Abs(ADx) >= AThreshold then
    Result := cdResize
  else
    Result := cdNone;
end;

function TyCoolBarPackVertical(const AChildSizes: array of TSize; const ABreaks: array of Boolean;
  const ALeadExtra: array of Integer;
  AAvail, ABandThick, AGripperW, ASpacing: Integer;
  ARightToLeft: Boolean = False; ACrossExtent: Integer = 0): TTyRectArray;
var
  n, i, x, y, h, colStart, lead: Integer;
  brk, firstInCol: Boolean;
  span: TRect;
begin
  Result := nil;
  n := Length(AChildSizes);
  SetLength(Result, n);
  if n = 0 then Exit;
  if ABandThick < 0 then ABandThick := 0;
  if AGripperW < 0 then AGripperW := 0;
  if ASpacing < 0 then ASpacing := 0;

  x := 0;
  y := 0;
  firstInCol := True;
  for i := 0 to n - 1 do
  begin
    h := AChildSizes[i].cy;
    if h < 0 then h := 0;
    brk := (i < Length(ABreaks)) and ABreaks[i];
    lead := AGripperW;
    if (i < Length(ALeadExtra)) and (ALeadExtra[i] > 0) then Inc(lead, ALeadExtra[i]);
    if (not firstInCol) and (brk or (y + lead + h > AAvail)) then
    begin
      Inc(x, ABandThick + ASpacing);
      y := 0;
      firstInCol := True;
    end;
    colStart := y + lead;               // the child begins below its own gripper
    if colStart + h > AAvail then
      h := AAvail - colStart;
    if h < 0 then h := 0;
    Result[i].Left := x;
    Result[i].Top := colStart;
    Result[i].Right := x + ABandThick;
    Result[i].Bottom := colStart + h;
    y := colStart + h + ASpacing;
    firstInCol := False;
  end;
  { MIRROR the column order about the bar's width. The y axis -- where the bands and their
    grippers sit -- is untouched, which is the whole difference from the horizontal case. }
  if ARightToLeft and (ACrossExtent > 0) then
  begin
    span := Rect(0, 0, ACrossExtent, 0);
    for i := 0 to n - 1 do
      Result[i] := BidiFlipRect(Result[i], span, True);
  end;
end;

function TyCoolBandResize(AStartW, ADx, AMinW, AMaxW: Integer): Integer;
begin
  if AMinW < 1 then AMinW := 1;
  Result := AStartW + ADx;
  if Result < AMinW then Result := AMinW;
  // A non-positive ceiling means unbounded; otherwise clamp (and never below the floor).
  if AMaxW > 0 then
  begin
    if AMaxW < AMinW then AMaxW := AMinW;   // an inverted range collapses to the floor
    if Result > AMaxW then Result := AMaxW;
  end;
end;

function TyCoolBandSeamOwner(const ARects: TTyRectArray; AIndex: Integer;
  AVertical: Boolean = False): Integer;
var
  i: Integer;
begin
  Result := -1;
  if (AIndex <= 0) or (AIndex > High(ARects)) then Exit;
  for i := AIndex - 1 downto 0 do
    if (AVertical and (ARects[i].Left = ARects[AIndex].Left))
       or ((not AVertical) and (ARects[i].Top = ARects[AIndex].Top)) then
      Exit(i);
  { Fell off the front without meeting a band on this row -> AIndex opens the row. }
end;

function TyCoolBandDropIndex(const ARects: TTyRectArray; ADragIndex: Integer;
  const APt: TPoint; ARightToLeft: Boolean = False;
  AVertical: Boolean = False): Integer;
var
  n, i, target, insertAt, maxBottom, mid: Integer;
  after: Boolean;
  r: TTyRectArray;
  p: TPoint;
begin
  Result := ADragIndex;
  n := Length(ARects);
  if (n = 0) or (ADragIndex < 0) or (ADragIndex >= n) then Exit;

  { Transpose once, up front, and the rest of this function never mentions the axis again. }
  if AVertical then
  begin
    SetLength(r, n);
    for i := 0 to n - 1 do
      r[i] := Rect(ARects[i].Top, ARects[i].Left, ARects[i].Bottom, ARects[i].Right);
    p := Point(APt.Y, APt.X);
    ARightToLeft := False;   // see the header: not a reading direction once transposed
    Exit(TyCoolBandDropIndex(r, ADragIndex, p, ARightToLeft, False));
  end;

  { Below EVERY band -> a row of its own at the end. This is the gesture the reference spells
    cNewRowBelow (coolbar.inc:976) and it is what "drag the toolbar under the search box"
    means. }
  maxBottom := ARects[0].Bottom;
  for i := 1 to n - 1 do
    if ARects[i].Bottom > maxBottom then maxBottom := ARects[i].Bottom;
  if APt.Y >= maxBottom then Exit(TyCoolDropNewRow);

  { The band the pointer is over, searched WITHIN the pointer's row. Falling back to the last
    band seen on that row is what lets a pointer dragged off the end of a row still land after
    the final band there instead of doing nothing. }
  target := -1;
  for i := 0 to n - 1 do
  begin
    if (APt.Y < ARects[i].Top) or (APt.Y >= ARects[i].Bottom) then Continue;
    target := i;
    if (APt.X >= ARects[i].Left) and (APt.X < ARects[i].Right) then Break;
  end;
  if (target < 0) or (target = ADragIndex) then Exit;

  { Past the target's midpoint -> the dragged band goes after it. Mirrored, "after" is to the
    LEFT, so the comparison flips with the reading direction and nothing else does. }
  mid := ARects[target].Left + (ARects[target].Right - ARects[target].Left) div 2;
  if ARightToLeft then after := APt.X < mid else after := APt.X >= mid;

  if after then insertAt := target + 1 else insertAt := target;
  { The dragged band leaves its own slot first, so every slot after it shifts down one. }
  if insertAt > ADragIndex then Dec(insertAt);
  if insertAt < 0 then insertAt := 0;
  if insertAt > n - 1 then insertAt := n - 1;
  Result := insertAt;
end;

function TyCoolRowMakeRoom(const AExtents, AMins, ALeads: array of Integer;
  AInsertAt, AJoinLead, AJoinExtent, AAvail, ASpacing: Integer;
  out ANewExtents: TTyCoolExtents): Boolean;
var
  n, i, k, need, deficit, give, slack, floorW: Integer;
  order: array of Integer;

  function LeadAt(AIdx: Integer): Integer;
  begin
    if (AIdx < Length(ALeads)) and (ALeads[AIdx] > 0) then Result := ALeads[AIdx] else Result := 0;
  end;

  function MinAt(AIdx: Integer): Integer;
  begin
    { NO FLOOR OF ITS OWN. The number comes from the caller, and the caller is
      TTyCoolBar.BandMinWidth -- the same function the gripper resize is handed -- so a band's
      MinWidth (or the bar's DefaultBandMinWidth when it has none) is the one floor both
      gestures bottom out at, and neither can squeeze past what the other respects.

      The two guards here are not a second source: a SHORT AMins is a caller that named fewer
      minimums than bands, and the `< 1` clamp is the identical "never collapse to nothing"
      backstop TyCoolBandResize applies to its own AMinW. Change one and the other must move. }
    if AIdx < Length(AMins) then Result := AMins[AIdx] else Result := 1;
    if Result < 1 then Result := 1;
  end;

begin
  n := Length(AExtents);
  SetLength(ANewExtents, n);
  for i := 0 to n - 1 do ANewExtents[i] := AExtents[i];
  if ASpacing < 0 then ASpacing := 0;
  if AInsertAt < 0 then AInsertAt := 0;
  if AInsertAt > n then AInsertAt := n;

  { What the row costs with the joiner on it. The packer charges one ASpacing per GAP, so n+1
    bands cost n gaps -- and the total is therefore independent of the order they sit in, which
    is why the insertion point affects only WHO gives, never HOW MUCH. }
  need := AJoinLead + AJoinExtent + n * ASpacing;
  for i := 0 to n - 1 do Inc(need, LeadAt(i) + AExtents[i]);
  deficit := need - AAvail;
  if deficit <= 0 then Exit(True);          // it already fits; nobody has to give anything

  { Nearest band before the insertion point outward, then nearest after it outward. }
  SetLength(order, n);
  k := 0;
  for i := AInsertAt - 1 downto 0 do begin order[k] := i; Inc(k); end;
  for i := AInsertAt to n - 1 do begin order[k] := i; Inc(k); end;

  for k := 0 to n - 1 do
  begin
    i := order[k];
    floorW := MinAt(i);
    slack := ANewExtents[i] - floorW;
    if slack <= 0 then Continue;
    if slack < deficit then give := slack else give := deficit;
    Dec(ANewExtents[i], give);
    Dec(deficit, give);
    if deficit <= 0 then Break;
  end;

  Result := deficit <= 0;
  if not Result then
    { REFUSE WHOLE. Half a shrink is the worst of the three outcomes: the row lost width and the
      band still did not arrive, so the user sees the layout move for no reason. }
    for i := 0 to n - 1 do ANewExtents[i] := AExtents[i];
end;

function TyCoolGripperHit(const ABandRect: TRect; AGripperW: Integer; const APt: TPoint): Boolean;
begin
  if AGripperW <= 0 then Exit(False);
  Result :=
    (APt.X >= ABandRect.Left) and (APt.X < ABandRect.Left + AGripperW) and
    (APt.Y >= ABandRect.Top)  and (APt.Y < ABandRect.Bottom);
end;

// =============================================================================
// TTyCoolBand / TTyCoolBands
// =============================================================================
constructor TTyCoolBand.Create(ACollection: TCollection);
begin
  inherited Create(ACollection);
  FVisible := True;
end;

procedure TTyCoolBand.Assign(ASource: TPersistent);
begin
  if ASource is TTyCoolBand then
  begin
    FControl := TTyCoolBand(ASource).Control;
    FText := TTyCoolBand(ASource).Text;
    FBreak := TTyCoolBand(ASource).Break;
    FWidth := TTyCoolBand(ASource).Width;
    FMinWidth := TTyCoolBand(ASource).MinWidth;
    FMaxWidth := TTyCoolBand(ASource).MaxWidth;
    FFixedSize := TTyCoolBand(ASource).FixedSize;
    FAutoMaxWidth := TTyCoolBand(ASource).AutoMaxWidth;
    FVisible := TTyCoolBand(ASource).Visible;
    Changed(False);
  end
  else
    inherited Assign(ASource);
end;

function TTyCoolBand.GetDisplayName: string;
begin
  { What the Object Inspector's collection editor lists. The caption if there is one, else the
    control's name -- a list of "0,1,2" would make a band collection unusable to design. }
  if FText <> '' then Result := FText
  else if FControl <> nil then Result := FControl.Name
  else Result := inherited GetDisplayName;
end;

procedure TTyCoolBand.SetControl(AValue: TControl);
begin
  if FControl = AValue then Exit;
  FControl := AValue;
  Changed(False);
end;

procedure TTyCoolBand.SetText(const AValue: string);
begin
  if FText = AValue then Exit;
  FText := AValue;
  Changed(False);
end;

procedure TTyCoolBand.SetBreak(AValue: Boolean);
begin
  if FBreak = AValue then Exit;
  FBreak := AValue;
  Changed(False);
end;

procedure TTyCoolBand.SetWidth(AValue: Integer);
var
  bar: TTyCoolBar;
begin
  if AValue < 0 then AValue := 0;
  if FWidth = AValue then Exit;
  FWidth := AValue;
  { A given width IS the hosted control's extent ALONG THE ROW'S RUN -- the packer measures
    children, so the two must not drift apart. Vertically the run is the y axis, so the extent
    to assign is the control's HEIGHT: writing Width there would set the column THICKNESS,
    which TyCoolBarPackVertical takes from the bar's band height and not from the band at all,
    so the assignment landed on an axis nothing reads. }
  if (FControl <> nil) and (AValue > 0) then
  begin
    bar := nil;
    if Collection is TTyCoolBands then bar := TTyCoolBands(Collection).OwnerBar;
    if (bar <> nil) and bar.Vertical then FControl.Height := AValue
    else FControl.Width := AValue;
  end;
  Changed(False);
end;

procedure TTyCoolBand.SetAutoMaxWidth(AValue: Boolean);
begin
  if FAutoMaxWidth = AValue then Exit;
  FAutoMaxWidth := AValue;
  { Turning the cap on does NOT retro-shrink a band that is already wider than its content: the
    cap bounds the GESTURE, and silently resizing bands the moment a design-time checkbox is
    ticked would move a layout the author had already settled. It binds from the next drag. }
  Changed(False);
end;

procedure TTyCoolBand.SetVisible(AValue: Boolean);
begin
  if FVisible = AValue then Exit;
  FVisible := AValue;
  { The hosted control's own Visible is the single source of truth the packer already reads. }
  if FControl <> nil then FControl.Visible := AValue;
  Changed(False);
end;

constructor TTyCoolBands.Create(AOwner: TPersistent);
begin
  inherited Create(AOwner, TTyCoolBand);
end;

function TTyCoolBands.OwnerBar: TTyCoolBar;
begin
  if GetOwner is TTyCoolBar then Result := TTyCoolBar(GetOwner) else Result := nil;
end;

function TTyCoolBands.GetItem(AIndex: Integer): TTyCoolBand;
begin
  Result := TTyCoolBand(inherited Items[AIndex]);
end;

procedure TTyCoolBands.SetItem(AIndex: Integer; AValue: TTyCoolBand);
begin
  inherited Items[AIndex] := AValue;
end;

function TTyCoolBands.Add: TTyCoolBand;
begin
  Result := TTyCoolBand(inherited Add);
end;

function TTyCoolBands.FindBand(AControl: TControl): TTyCoolBand;
var i: Integer;
begin
  Result := nil;
  if AControl = nil then Exit;
  for i := 0 to Count - 1 do
    if Items[i].Control = AControl then Exit(Items[i]);
end;

procedure TTyCoolBands.Update(AItem: TCollectionItem);
var bar: TTyCoolBar;
begin
  inherited Update(AItem);
  { Any edit -- from the designer or from code -- re-lays the bar and reports the change, so a
    band designed in the Object Inspector behaves exactly like one set at run time. }
  bar := OwnerBar;
  if bar <> nil then bar.BandsChanged;
end;

// =============================================================================
// TTyCoolBar
// =============================================================================
constructor TTyCoolBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBandList := TTyCoolBands.Create(Self);
  // The base already sets csAcceptsControls; a rebar hosts arbitrary band content.
  GripperWidth := 10;   // inherited property (the base packs with the same value we hit-test)
  FDefaultBandMinWidth := 24;
  FDragging := False;
  FDragCtl := nil;
end;

function TTyCoolBar.GetStyleTypeKey: string;
begin
  { Own key rather than the borrowed 'TyPanel': same as its TTyControlBar ancestor — band grippers are not panel chrome.
    Added to 'TyPanel's rule block as an extra selector, so every resolved value is
    unchanged — this opens a hook, it does not restyle anything. }
  Result := 'TyCoolBar';
end;

function TTyCoolBar.GripperWidthPx: Integer;
begin
  Result := MulDiv(GripperWidth, Font.PixelsPerInch, 96);   // inherited from TTyControlBar
  if Result < 0 then Result := 0;
end;


function TTyCoolBar.EnsureBand(ACtl: TControl): TTyCoolBand;
begin
  { Band metadata used to spring into existence only when a WIDTH was assigned, so setting any
    other band property on a band nobody had sized yet silently did nothing. Every setter goes
    through here instead. }
  Result := nil;
  if ACtl = nil then Exit;
  Result := FBandList.FindBand(ACtl);
  if Result <> nil then Exit;
  Result := FBandList.Add;
  Result.Control := ACtl;
end;

procedure TTyCoolBar.SetBandWidth(ACtl: TControl; AWidth: Integer);
var b: TTyCoolBand;
begin
  b := EnsureBand(ACtl);
  if b <> nil then b.Width := AWidth;
end;

function TTyCoolBar.GetBandWidth(ACtl: TControl): Integer;
var b: TTyCoolBand;
begin
  b := FBandList.FindBand(ACtl);
  if b <> nil then Result := b.Width else Result := 0;
end;

procedure TTyCoolBar.SetBandMinWidth(ACtl: TControl; AMinWidth: Integer);
var b: TTyCoolBand;
begin
  b := EnsureBand(ACtl);
  if b <> nil then b.MinWidth := AMinWidth;
end;

procedure TTyCoolBar.SetBandMaxWidth(ACtl: TControl; AMaxWidth: Integer);
var b: TTyCoolBand;
begin
  b := EnsureBand(ACtl);
  if b <> nil then b.MaxWidth := AMaxWidth;
end;

function TTyCoolBar.BandMinWidth(ACtl: TControl): Integer;
var b: TTyCoolBand;
begin
  b := FBandList.FindBand(ACtl);
  if (b <> nil) and (b.MinWidth > 0) then
    Result := b.MinWidth
  else
    Result := FDefaultBandMinWidth;
end;

function TTyCoolBar.BandContentCap(ACtl: TControl): Integer;
var
  pw, ph: Integer;
begin
  { HOW WIDE THE CONTENT CAN USEFULLY BE, asked of the hosted control itself. 0 means the
    control declares nothing and there is therefore no ceiling to impose.

    Expressed in the same frame as every other band width in this unit: the CHILD's width, with
    the gripper and caption strip EXCLUDED, because that is the number TTyCoolBand.Width sets
    and TyCoolBandResize clamps. (Lazarus's TCoolBand.Width is the other convention -- its
    CalcPreferredWidth adds CalcControlLeft -- so a cap ported straight across from the
    reference would let the band grow exactly one gripper-plus-caption PAST its content. The
    footprint the user sees is BandLeadPx + this, and that is what lands on the content's last
    pixel.)

    THREE candidate sources, and only two of them survive contact with the problem:

      * Constraints.MaxWidth -- an explicit ceiling the author put on the control. Honoured
        when set. Usually 0.
      * GetPreferredSize RAW -- what the control says it wants to be. Raw matters, and it is
        the whole trick: the non-raw form substitutes the control's CURRENT Width whenever it
        has no preference (lcl/include/control.inc:5635), and a band's current width is the
        very number the drag is changing -- a cap built on it would pin every band wherever it
        happened to be and turn the first outward drag into the dead gesture this pass exists
        to remove.
      * the control's own Width -- rejected for the same reason, and measured to be actively
        misleading: a TTyToolBarEx with three buttons read Width=600 after alignment while
        answering raw 125, its real content. The same probe measured TTyEdit at raw 0 (no
        opinion) with non-raw 140 (merely its own width). Confirmed on a real window during
        development. }
  Result := 0;
  if ACtl = nil then Exit;
  if ACtl.Constraints.MaxWidth > 0 then Result := ACtl.Constraints.MaxWidth;
  pw := 0;
  ph := 0;
  ACtl.GetPreferredSize(pw, ph, True {Raw}, False {WithThemeSpace});
  if (pw > 0) and ((Result <= 0) or (pw < Result)) then Result := pw;
end;

function TTyCoolBar.BandMaxWidth(ACtl: TControl): Integer;
var
  b: TTyCoolBand;
  cap: Integer;
begin
  { THE ONE PLACE the ceilings compose, so no caller has to know there is more than one -- and
    every consumer (the gripper resize, and anything a subclass adds) already asks this.

    Up to three can be in play: the hand-entered MaxWidth, a Constraints.MaxWidth on the hosted
    control, and what that control declares as its preferred width. One rule for all of them:
    0 means "no opinion" and drops out; of whatever remains the SMALLEST binds. So AutoMaxWidth
    never fights MaxWidth -- whichever runs out first stops the drag -- and with AutoMaxWidth
    off the answer is exactly what it always was. }
  Result := 0;
  b := FBandList.FindBand(ACtl);
  if b = nil then Exit;
  Result := b.MaxWidth;
  if not b.AutoMaxWidth then Exit;
  cap := BandContentCap(ACtl);
  if (cap > 0) and ((Result <= 0) or (cap < Result)) then Result := cap;
end;

function TTyCoolBar.BandRectFor(ACtl: TControl): TRect;
var
  gw: Integer;
  content: TRect;
begin
  // The base (TTyControlBar) reserves + draws ONE gripper per band-ROW, at the row's left edge
  // (x = 0..gw). So only the row's FIRST child — the one placed at Left = gw (the content-left
  // after that single gripper) — is a resize target; a child packed further right on the same row
  // shares no gripper and must NOT be grippable (else its hit-zone is a phantom strip with nothing
  // drawn, resizing the wrong band). Return the real row-left gripper rect for a first child, else
  // an empty rect. Device px, control-local.
  if ACtl = nil then Exit(Rect(0, 0, 0, 0));
  gw := GripperWidthPx;
  if gw <= 0 then Exit(Rect(0, 0, 0, 0));
  { EVERY band has its own gripper, immediately to its left -- the packer reserves it there.
    The old rule returned an empty rect for anything that was not the row's first child, which
    is a ControlBar's one-grip-per-row model: band 2 had no handle to grab and none drawn. }
  Result := ACtl.BoundsRect;
  { Clamped to the CONTENT box, not to the raw client rect: a gripper for a band on the first
    row/column would otherwise be allowed to back onto the frame stroke it must stay inside. }
  content := BandContentRect;
  if FVertical then
  begin
    { Above the band on either reading -- up is not a reading direction, so a mirrored
      vertical rebar reverses which COLUMN a band is in and nothing about its gripper. }
    Result.Bottom := Result.Top;
    Dec(Result.Top, gw);
    if Result.Top < content.Top then Result.Top := content.Top;
  end
  else if IsRightToLeft then
  begin
    { The packer put the gripper on the band's LEADING edge, which mirrored is its right.
      Derived here rather than reflected about the bar, because the child this is derived
      FROM has already moved: reflecting a rect built off a mirrored child would mirror it
      twice. This function stays the single source -- PaintGrippers draws what it returns and
      BandAtPoint hit-tests what it returns -- so paint and hit cannot take different sides. }
    Result.Left := Result.Right;
    Inc(Result.Right, gw);
    if Result.Right > content.Right then Result.Right := content.Right;
  end
  else
  begin
    Result.Right := Result.Left;
    Dec(Result.Left, gw);
    if Result.Left < content.Left then Result.Left := content.Left;
  end;
end;

procedure TTyCoolBar.SetBandBreak(ACtl: TControl; AValue: Boolean);
var b: TTyCoolBand;
begin
  b := EnsureBand(ACtl);
  if b <> nil then b.Break := AValue;
end;

function TTyCoolBar.BandBreak(ACtl: TControl): Boolean;
var b: TTyCoolBand;
begin
  b := FBandList.FindBand(ACtl);
  Result := (b <> nil) and b.Break;
end;

procedure TTyCoolBar.SetBandText(ACtl: TControl; const AValue: string);
var b: TTyCoolBand;
begin
  b := EnsureBand(ACtl);
  if b <> nil then b.Text := AValue;
end;

function TTyCoolBar.BandText(ACtl: TControl): string;
var b: TTyCoolBand;
begin
  b := FBandList.FindBand(ACtl);
  if b <> nil then Result := b.Text else Result := '';
end;

procedure TTyCoolBar.SetBandFixedSize(ACtl: TControl; AValue: Boolean);
var b: TTyCoolBand;
begin
  b := EnsureBand(ACtl);
  if b <> nil then b.FixedSize := AValue;
end;

function TTyCoolBar.BandFixedSize(ACtl: TControl): Boolean;
var b: TTyCoolBand;
begin
  b := FBandList.FindBand(ACtl);
  Result := (b <> nil) and b.FixedSize;
end;

procedure TTyCoolBar.SetBandAutoMaxWidth(ACtl: TControl; AValue: Boolean);
var b: TTyCoolBand;
begin
  b := EnsureBand(ACtl);
  if b <> nil then b.AutoMaxWidth := AValue;
end;

function TTyCoolBar.BandAutoMaxWidth(ACtl: TControl): Boolean;
var b: TTyCoolBand;
begin
  b := FBandList.FindBand(ACtl);
  Result := (b <> nil) and b.AutoMaxWidth;
end;

procedure TTyCoolBar.SetBandVisible(ACtl: TControl; AValue: Boolean);
var b: TTyCoolBand;
begin
  b := EnsureBand(ACtl);
  if b <> nil then b.Visible := AValue;
end;

function TTyCoolBar.BandVisible(ACtl: TControl): Boolean;
begin
  Result := (ACtl <> nil) and ACtl.Visible;
end;

{ Measure a band caption on a scratch canvas -- the pattern TTyCustomTabStrip and TTyGroupBox
  use, so CJK and variable-width fonts measure correctly with no window. }
function TTyCoolBar.BandTextWidth(const AText: string; const AStyle: TTyStyleSet): Integer;
var
  bmp: TBitmap;
begin
  Result := 0;
  if (AText = '') or (not FShowText) then Exit;
  bmp := TBitmap.Create;
  try
    bmp.SetSize(1, 1);
    bmp.Canvas.Font.Name := TyEffectiveFontName(AStyle.FontName);
    bmp.Canvas.Font.Size := MulDiv(ResolveFontSize(AStyle), Font.PixelsPerInch, 96);
    Result := bmp.Canvas.TextWidth(AText);
  finally
    bmp.Free;
  end;
  if Result > 0 then Inc(Result, MulDiv(8, Font.PixelsPerInch, 96));   // a gap before the child
end;

destructor TTyCoolBar.Destroy;
begin
  FreeAndNil(FBandList);
  inherited Destroy;
end;

procedure TTyCoolBar.SetBands(AValue: TTyCoolBands);
begin
  FBandList.Assign(AValue);
end;

procedure TTyCoolBar.BandsChanged;
begin
  { One place the collection reports into, so a designer edit and a run-time setter take the
    same path: re-lay, then tell the application. }
  Relayout;
  Changed;
end;

procedure TTyCoolBar.SetVertical(AValue: Boolean);
begin
  if FVertical = AValue then Exit;
  FVertical := AValue;
  Relayout;
  Changed;
end;

procedure TTyCoolBar.SetShowText(AValue: Boolean);
begin
  if FShowText = AValue then Exit;
  FShowText := AValue;
  Relayout;   // the caption strip is packed, so turning it on/off moves every band
end;

procedure TTyCoolBar.Changed;
begin
  if Assigned(FOnChange) then FOnChange(Self);
end;

function TTyCoolBar.PackBands(const ABands: array of TControl; const ASizes: array of TSize;
  AAvail, ABandHeight, AGripperW, ASpacing: Integer): TTyRectArray;
var
  brks: array of Boolean;
  leads: array of Integer;
  S: TTyStyleSet;
  bnd: TTyCoolBand;
  i: Integer;
begin
  { Every band carries its own gripper, and a band may force a row break -- the two things
    that make a CoolBar a CoolBar rather than a ControlBar. }
  SetLength(brks, Length(ABands));
  SetLength(leads, Length(ABands));
  S := CurrentStyle;
  for i := 0 to High(ABands) do
  begin
    bnd := FBandList.FindBand(ABands[i]);
    brks[i] := (bnd <> nil) and bnd.Break;
    if bnd <> nil then leads[i] := BandTextWidth(bnd.Text, S) else leads[i] := 0;
  end;
  if FVertical then
    { AAvail is the run the bands travel along, so vertically it is the bar's HEIGHT, and the
      band's fixed extent is its width. The caller measures the horizontal case, so swap here
      -- and hand the width on separately, because mirroring a vertical rebar reverses the
      COLUMN order, which is the axis AAvail is no longer describing.

      The height comes from BandContentRect, NOT from Height: the caller already handed us the
      content WIDTH as AAvail, so reading the raw Height here would mix a frame-inset axis with
      a raw one and let a vertical rebar's last band run out under the bottom stroke. }
    Result := TyCoolBarPackVertical(ASizes, brks, leads,
      BandContentRect.Bottom - BandContentRect.Top, ABandHeight, AGripperW, ASpacing,
      IsRightToLeft, AAvail)
  else
    Result := TyCoolBarPack(ASizes, brks, leads, AAvail, ABandHeight, AGripperW, ASpacing,
      IsRightToLeft);
end;

procedure TTyCoolBar.PaintGrippers(APainter: TTyPainter; const AStyle: TTyStyleSet;
  ABandCount, ABandHeight, AGripperW, ASpacing: Integer);
var
  i: Integer;
  bnd: TTyCoolBand;
  ctl: TControl;
  r, cap: TRect;
begin
  { One gripper per BAND, drawn immediately left of the child it belongs to -- not one per row.
    Band 2 having no handle at all was this loop inherited unchanged from the base. }
  for i := 0 to ControlCount - 1 do
  begin
    ctl := Controls[i];
    if (ctl = nil) or (not ctl.Visible) then Continue;
    r := BandRectFor(ctl);
    if r.Right > r.Left then DrawGripper(APainter, r, AStyle);
    if FShowText then
    begin
      bnd := FBandList.FindBand(ctl);
      if (bnd <> nil) and (bnd.Text <> '') then
      begin
        { Between the gripper and the child -- the strip PackBands reserved for exactly this.
          Mirrored, the gripper is on the child's right, so the span runs the other way; the
          painter (armed in TTyControlBar.Paint) turns the taLeftJustify into the right side. }
        if IsRightToLeft then
          cap := Rect(ctl.Left + ctl.Width, r.Top, r.Left, r.Bottom)
        else
          cap := Rect(r.Right, r.Top, ctl.Left, r.Bottom);
        APainter.DrawText(cap, bnd.Text,
          AStyle.FontName, ResolveFontSize(AStyle), AStyle.FontWeight, AStyle.TextColor,
          taLeftJustify, tlCenter, True);
      end;
    end;
  end;
end;

procedure TTyCoolBar.CollectLaidOutBands(out ACtls: TTyCoolBandCtls; out ARects: TTyRectArray);
var
  i, n: Integer;
  ctl: TControl;
begin
  { Read straight off the children's BoundsRect -- what the packer last wrote and what
    BandRectFor derives every gripper from. Recomputing a packing here instead would open the
    door to the seam lookup and the paint disagreeing about which bands share a row. }
  SetLength(ACtls, ControlCount);
  SetLength(ARects, ControlCount);
  n := 0;
  for i := 0 to ControlCount - 1 do
  begin
    ctl := Controls[i];
    if (ctl = nil) or (not ctl.Visible) then Continue;   // an invisible band is not on any row
    ACtls[n] := ctl;
    ARects[n] := ctl.BoundsRect;
    Inc(n);
  end;
  SetLength(ACtls, n);
  SetLength(ARects, n);
end;

function TTyCoolBar.SeamOwnerOf(ACtl: TControl): TControl;
var
  ctls: TTyCoolBandCtls;
  rects: TTyRectArray;
  i, idx, seam: Integer;
begin
  Result := nil;
  if ACtl = nil then Exit;
  CollectLaidOutBands(ctls, rects);
  idx := -1;
  for i := 0 to High(ctls) do
    if ctls[i] = ACtl then begin idx := i; Break; end;
  if idx < 0 then Exit;
  seam := TyCoolBandSeamOwner(rects, idx, FVertical);
  if seam >= 0 then Result := ctls[seam];
end;

function TTyCoolBar.RowStepPx: Integer;
var
  ppi: Integer;
begin
  ppi := Font.PixelsPerInch;
  Result := MulDiv(BandHeight, ppi, 96) + MulDiv(BandSpacing, ppi, 96);
end;

function TTyCoolBar.RowOrdinalOfBand(const ARect: TRect): Integer;
var
  step: Integer;
  content: TRect;
begin
  Result := 0;
  step := RowStepPx;
  if step <= 0 then Exit;
  { Counted from the CONTENT origin, which is where the packer starts the first row. Read off
    the raw client rect the counts drift by the frame inset, so a band inside row 0 could read
    as row 1 on a skin with a wide border. }
  content := BandContentRect;
  if FVertical then
  begin
    { Columns, not rows -- and mirrored they are counted from the right edge, matching the order
      TyCoolBarPackVertical laid them out in. Measured from the band's FAR side so a band and a
      pointer sitting on it produce the same count. }
    if IsRightToLeft then
      Result := (content.Right - ARect.Right) div step
    else
      Result := (ARect.Left - content.Left) div step;
  end
  else
    Result := (ARect.Top - content.Top) div step;
  if Result < 0 then Result := 0;
end;

function TTyCoolBar.RowOrdinalOfPoint(AX, AY: Integer): Integer;
var
  step: Integer;
  content: TRect;
begin
  Result := 0;
  step := RowStepPx;
  if step <= 0 then Exit;
  content := BandContentRect;
  if FVertical then
  begin
    if IsRightToLeft then Result := (content.Right - AX) div step
    else Result := (AX - content.Left) div step;
  end
  else
    Result := (AY - content.Top) div step;
  if Result < 0 then Result := 0;
end;

function TTyCoolBar.BandLeadPx(ACtl: TControl): Integer;
var
  bnd: TTyCoolBand;
begin
  Result := GripperWidthPx;
  if ACtl = nil then Exit;
  bnd := FBandList.FindBand(ACtl);
  { BandTextWidth answers 0 when ShowText is off, so this composes exactly what PackBands hands
    the packer: AGripperW always, ALeadExtra only when a caption is actually reserved. }
  if bnd <> nil then Inc(Result, BandTextWidth(bnd.Text, CurrentStyle));
end;

function TTyCoolBar.BandRunExtent(ACtl: TControl): Integer;
begin
  Result := 0;
  if ACtl = nil then Exit;
  if FVertical then Result := ACtl.Height else Result := ACtl.Width;
end;

procedure TTyCoolBar.SetBandRunExtent(ACtl: TControl; AValue: Integer);
begin
  if ACtl = nil then Exit;
  { Routed through the band MODEL, not poked straight into the control: the packer re-measures
    the child on every pass, so a value the model does not hold would be undone by the first
    relayout that touched it. }
  SetBandWidth(ACtl, AValue);
  { ...and then forced onto the control even when the model already held that number. A
    relayout can have CLAMPED the child (TyCoolBarPack narrows a band that would run off the end
    of its row), which leaves model and control disagreeing, and TTyCoolBand.SetWidth
    short-circuits on an unchanged model value -- so without this the clamp would survive. }
  if AValue <= 0 then Exit;
  if FVertical then
  begin
    if ACtl.Height <> AValue then ACtl.Height := AValue;
  end
  else
    if ACtl.Width <> AValue then ACtl.Width := AValue;
end;

function TTyCoolBar.RejoinRow(AX, AY, ATargetRow: Integer): Boolean;
var
  ctls: TTyCoolBandCtls;
  rects: TTyRectArray;
  rowIdx: array of Integer;
  ext, mins, leads: array of Integer;
  newExt: TTyCoolExtents;
  followCtl: TControl;
  content: TRect;
  i, idx, n, drop, insertAt, avail, spacing: Integer;
begin
  Result := False;
  if FDragCtl = nil then Exit;
  { ONE reading of the layout, shared with the seam lookup, the gripper paint and the hit test.
    Recomputing a packing here is how the drawn state and the packed state start disagreeing. }
  CollectLaidOutBands(ctls, rects);
  idx := -1;
  for i := 0 to High(ctls) do
    if ctls[i] = FDragCtl then begin idx := i; Break; end;
  if idx < 0 then Exit;

  { The bands ALREADY on the target row, in list order. }
  SetLength(rowIdx, Length(ctls));
  n := 0;
  for i := 0 to High(ctls) do
    if (i <> idx) and (RowOrdinalOfBand(rects[i]) = ATargetRow) then
    begin
      rowIdx[n] := i;
      Inc(n);
    end;
  SetLength(rowIdx, n);
  if n = 0 then Exit;          // no such row: there is nothing to rejoin

  { WHERE on the row it lands -- the same midpoint rule an in-row reorder uses, so dragging up
    onto a band's leading half puts the band before it and onto its trailing half after it.
    The answer is a LAYOUT index, and ADragIndex back means "the list order is already right",
    which is precisely the overflow case: the band is already the row's successor in the child
    list and the only thing missing is the ROOM. }
  drop := TyCoolBandDropIndex(rects, idx, Point(AX, AY), IsRightToLeft, FVertical);
  if drop = TyCoolDropNewRow then Exit;
  insertAt := 0;
  for i := 0 to n - 1 do
    if rowIdx[i] < drop then Inc(insertAt);

  SetLength(ext, n);
  SetLength(mins, n);
  SetLength(leads, n);
  for i := 0 to n - 1 do
  begin
    ext[i]   := BandRunExtent(ctls[rowIdx[i]]);
    mins[i]  := BandMinWidth(ctls[rowIdx[i]]);
    leads[i] := BandLeadPx(ctls[rowIdx[i]]);
  end;

  spacing := MulDiv(BandSpacing, Font.PixelsPerInch, 96);
  content := BandContentRect;
  { The run AAvail describes swaps with the orientation, exactly as it does in PackBands. }
  if FVertical then avail := content.Bottom - content.Top
  else avail := content.Right - content.Left;

  if not TyCoolRowMakeRoom(ext, mins, leads, insertAt,
       BandLeadPx(FDragCtl), BandRunExtent(FDragCtl), avail, spacing, newExt) then
    Exit;   { REFUSED. Nothing below runs, so no width, no index, no Break and no OnChange
              moves -- the band simply stays where it is. }

  { A band that was OPENING its own row hands the Break to whoever shared that row with it, or
    those bands would be dragged up onto the row above along with it. The reference does this
    unconditionally (lcl/include/coolbar.inc:1050); we ask first whether the next band really is
    on the same row, because pinning a Break onto a band that merely happened to follow would
    freeze a row boundary the user never asked for. Read BEFORE anything moves. }
  followCtl := nil;
  if BandBreak(FDragCtl) and (idx < High(ctls))
     and (RowOrdinalOfBand(rects[idx + 1]) = RowOrdinalOfBand(rects[idx])) then
    followCtl := ctls[idx + 1];

  for i := 0 to n - 1 do
    if newExt[i] <> ext[i] then SetBandRunExtent(ctls[rowIdx[i]], newExt[i]);

  if followCtl <> nil then SetBandBreak(followCtl, True);
  { Clearing Break is still necessary -- it is just no longer SUFFICIENT, which was the whole
    bug: a band that came down by overflow never had it set. }
  SetBandBreak(FDragCtl, False);
  if drop <> idx then SetControlIndex(FDragCtl, GetControlIndex(ctls[drop]));

  Relayout;
  Changed;
  Result := True;
end;

function TTyCoolBar.ReorderFromPointer(AX, AY: Integer): Boolean;
var
  ctls: TTyCoolBandCtls;
  rects: TTyRectArray;
  i, idx, drop: Integer;
begin
  Result := False;
  if FDragCtl = nil then Exit;
  CollectLaidOutBands(ctls, rects);
  idx := -1;
  for i := 0 to High(ctls) do
    if ctls[i] = FDragCtl then begin idx := i; Break; end;
  if idx < 0 then Exit;

  drop := TyCoolBandDropIndex(rects, idx, Point(AX, AY), IsRightToLeft, FVertical);
  if drop = TyCoolDropNewRow then
  begin
    { Past the last row: the band goes to the end of the list AND starts a row of its own.
      Both are needed -- Break alone would leave it breaking the row it is already in the
      middle of, splitting the bands after it onto a third row. }
    if idx <> High(ctls) then
    begin
      SetControlIndex(FDragCtl, ControlCount - 1);
      Result := True;
    end;
    if not BandBreak(FDragCtl) then
    begin
      SetBandBreak(FDragCtl, True);   // relays and fires OnChange through BandsChanged
      Result := True;
    end
    else if Result then
    begin
      { The band moved but its Break was already set, so BandsChanged never ran -- the list
        order changed with nothing to act on it. Relay here or the move is invisible. }
      Relayout;
      Changed;
    end;
    Exit;
  end;
  if drop = idx then Exit;

  { Land the band where ctls[drop] currently sits. TFPList.Move (which SetChildZPosition uses)
    removes then re-inserts, so this one index is correct in BOTH directions: moving later, the
    bands in between shift back and the dragged band lands after ctls[drop]; moving earlier, it
    lands before it. }
  SetControlIndex(FDragCtl, GetControlIndex(ctls[drop]));
  { A reorder inside a row must not leave a stale Break behind: the band that used to open the
    row would otherwise keep breaking it from its new position. }
  if BandBreak(FDragCtl) and (drop > 0) then SetBandBreak(FDragCtl, False);
  Relayout;
  Changed;
  Result := True;
end;

function TTyCoolBar.BandAtPoint(AX, AY: Integer): TControl;
var
  i: Integer;
  ctl: TControl;
  gw: Integer;
  r: TRect;
begin
  Result := nil;
  gw := GripperWidthPx;
  if gw <= 0 then Exit;
  for i := 0 to ControlCount - 1 do
  begin
    ctl := Controls[i];
    if (ctl = nil) or not ctl.Visible then Continue;
    r := BandRectFor(ctl);
    { BandRectFor already returns the grip strip itself, on whichever axis it lives, so plain
      containment is the right test -- TyCoolGripperHit's "leftmost gw px" rule only describes
      the horizontal case. }
    if (r.Right > r.Left) and (r.Bottom > r.Top)
       and (AX >= r.Left) and (AX < r.Right) and (AY >= r.Top) and (AY < r.Bottom) then
      Exit(ctl);
  end;
end;

procedure TTyCoolBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  hit: TControl;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  hit := BandAtPoint(X, Y);
  if hit = nil then Exit;
  { Begin a gripper drag. The gripper is the SEAM between this band and its row predecessor, so
    what a resize moves is the PREDECESSOR's trailing edge -- remember that band and ITS width,
    not the grabbed one's. Grabbing a band that opens its row leaves FDragSeam nil, and the
    gesture becomes a move (see MouseMove). }
  FDragging := True;
  FDragCtl := hit;
  FDragSeam := SeamOwnerOf(hit);
  FDragStartX := X;
  FDragStartY := Y;
  FDragMode := cdNone;   // undecided until the pointer commits to an axis
  if FDragSeam <> nil then
  begin
    if GetBandWidth(FDragSeam) > 0 then
      FDragStartW := GetBandWidth(FDragSeam)
    else
      FDragStartW := FDragSeam.Width;
  end
  else
    FDragStartW := 0;
end;

procedure TTyCoolBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  dxLogical, newW, minW, maxW, ppi, step, curRow, wantRow: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if not (FDragging and (FDragCtl <> nil)) then Exit;
  ppi := Font.PixelsPerInch;
  if FDragMode = cdNone then
  begin
    { Vertically the axes swap meaning with the layout: bands travel DOWN a column, so moving a
      band to another column is a SIDEWAYS drag, and resizing it (its height now) is vertical.
      Passing the deltas in swapped keeps one rule for both orientations. }
    if FVertical then
      FDragMode := TyCoolDragMode(Y - FDragStartY, X - FDragStartX, MulDiv(4, ppi, 96))
    else
      FDragMode := TyCoolDragMode(X - FDragStartX, Y - FDragStartY, MulDiv(4, ppi, 96));
    { A band that OPENS its row has no seam under its gripper, so there is nothing for a
      sideways drag to resize. The reference does not make that a dead gesture -- it makes the
      whole drag a MOVE (lcl/include/coolbar.inc:899). Doing anything else here is what made
      the grip feel pointless on the leading band: it looked draggable and did nothing. }
    if (FDragMode = cdResize) and (FDragSeam = nil) then FDragMode := cdMove;
  end;

  case FDragMode of
    cdResize:
      begin
        { The SEAM OWNER's FixedSize is what refuses the resize -- it is that band's trailing
          edge the drag would move. (coolbar.inc:903 gates on FVisiBands[aBand-1].FFixedSize
          for the same reason.) }
        if (FDragSeam = nil) or BandFixedSize(FDragSeam) then Exit;
        // Device-px delta -> logical (band widths are logical), clamped, then applied; the
        // base re-packs from the child width.
        if FVertical then
          dxLogical := MulDiv(Y - FDragStartY, 96, ppi)
        else
        begin
          dxLogical := MulDiv(X - FDragStartX, 96, ppi);
          { MIRRORING: the band grows AWAY from its gripper, and mirrored the gripper is on
            its right -- so dragging LEFT is what widens it. A sign nobody looks at in review
            and no static render can catch: the screenshot is right and the drag runs
            backwards (plans/2026-08-04-rtl-mirroring-scope.md §5 item 2). }
          if IsRightToLeft then dxLogical := -dxLogical;
        end;
        { Clamps come from the band being resized -- the seam owner -- not from the grabbed one. }
        minW := BandMinWidth(FDragSeam);
        maxW := BandMaxWidth(FDragSeam);
        newW := TyCoolBandResize(FDragStartW, dxLogical, minW, maxW);
        if newW <> GetBandWidth(FDragSeam) then
          SetBandWidth(FDragSeam, newW);
      end;
    cdMove:
      begin
        { A move means one of THREE things, and which row the pointer is over decides between
          them. All three read the SAME laid-out rects the packer wrote and the painter draws
          from (CollectLaidOutBands), so the hit test and the packing cannot disagree about
          where a band is. }
        step := RowStepPx;
        if step <= 0 then Exit;
        curRow := RowOrdinalOfBand(FDragCtl.BoundsRect);
        wantRow := RowOrdinalOfPoint(X, Y);

        { UP -- and answered BEFORE the reorder, deliberately. A band reaches the next row for
          two different reasons (its Break, or plain overflow) and only the first can be undone
          by clearing Break, so the old `SetBandBreak(False)` here was silently inert for every
          band that had merely failed to fit. Worse, the reorder ran first: a passing pointer
          position that happened to cross a neighbour's MIDPOINT consumed the gesture as a swap,
          which is why the user reported the swap as the only thing that still responded. The
          rejoin now owns every upward drag and takes width from the target row to make the
          room; when it refuses, the gesture ends there rather than falling through and doing
          something else with it. }
        if wantRow < curRow then
        begin
          RejoinRow(X, Y, wantRow);
          Exit;
        end;

        { SIDEWAYS or DOWN -- REORDER: dragging a band past a neighbour swaps them, dragging it
          below the last row gives it a row of its own at the end. }
        if ReorderFromPointer(X, Y) then Exit;   // the layout moved; re-read it next mouse-move

        { DOWN onto empty space the reorder had no answer for: give the band its own row. }
        if wantRow > curRow then SetBandBreak(FDragCtl, True);
      end;
  end;
end;

procedure TTyCoolBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDragging := False;
    FDragCtl := nil;
    FDragSeam := nil;
    FDragMode := cdNone;
  end;
end;

procedure TTyCoolBar.Notification(AComponent: TComponent; Operation: TOperation);
var
  bnd: TTyCoolBand;
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent is TControl) then
  begin
    // Drop the freed child's band (found by control, never by position).
    bnd := FBandList.FindBand(TControl(AComponent));
    if bnd <> nil then bnd.Free;
    { A freed band must not survive as EITHER end of the drag -- the seam owner is dereferenced
      on every MouseMove, so leaving it dangling is a use-after-free one mouse move away. }
    if (FDragCtl = AComponent) or (FDragSeam = AComponent) then
    begin
      FDragging := False;
      FDragCtl := nil;
      FDragSeam := nil;
    end;
  end;
end;

initialization
  RegisterClass(TTyCoolBar);
end.
