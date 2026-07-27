unit tyControls.Steps;
{$mode objfpc}{$H+}
{ TTySteps — a wizard step bar: a row (or a vertical rail) of numbered markers joined by
  connector lines, one per step, saying which steps are done, which one you are on, and
  which are still ahead.

  The gap it fills. An install/config wizard cannot be built without one, and today it is
  hand-rolled: a TTyLabel per step plus a hand-tinted TTyPanel for the line, i.e. a
  hard-coded colour per site and a re-layout by hand every time a step is added. Nothing
  in the library carries "progress through a sequence of named stages": TTyProgressBar is
  a continuous fraction with no names, and TTyTabSet / TTyPageControl are page chrome the
  user drives, not a state the HOST drives.

  A WINDOWED control (TTyCustomControl), like its batch sibling TTySegmented and unlike
  TTyTag/TTyAlert: with Clickable set it takes focus and the arrow keys walk the rail, and
  a graphic control can do neither (no handle => no focus, no key messages). That is the
  whole reason for the base class; a rail left at its Clickable=False default is an inert
  status display that never takes a tab stop.

  PER-STEP STATUS IS DERIVED, NOT STORED (TyStepStatus): steps before StepIndex are done,
  StepIndex is the current one, the rest are waiting. The host moves ONE integer and the
  whole bar re-reads — there is no per-step state to keep in sync.

  THREE typeKeys:
    'TySteps'          — the strip (its background/border/padding, and the ink+font every
                         step inherits when the step key defines none).
    'TyStepsItem'      — one step. :selected = the current step, :disabled = a waiting one,
                         and the resting layer = a DONE one. Those three are the whole
                         vocabulary; none of them is invented (see TyStepStates).
    'TyStepsConnector' — the line between two markers. It earns its own key because its
                         colour cannot be derived from any of the marker's: on the standard
                         look a done marker is a pale chip with an accent RING and an accent
                         check, while the line leaving it is solid accent — that colour is
                         neither the chip's `background`, nor the check's `color`, nor the
                         ring's `border-color`. See ConnectorStyle for the state it takes. }
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.Controller, tyControls.StyleModel;

const
  { Built-in logical-px defaults (96-PPI baseline) for this control's five metrics. A skin
    retunes each through its named theme metric below (the v3/C convention); these are only
    what a theme that sets none falls back to. Every call site scales them to device px.
    The marker matches nothing else on purpose — it is the one big round chip in the
    library — but the gap matches TyCheckBoxGap so a step's marker-to-title rhythm reads
    like a checkbox's box-to-caption rhythm.
    The connector is 1px because a rail's line is a HAIRLINE at 96 PPI; its LENGTH is the
    natural run AutoSize leaves for it, not a limit — a strip wider than its preferred size
    simply spreads, and the lines take the slack. }
  TyStepsMarkerSize      = 24;   // the numbered/checked marker slot, square
  TyStepsGap             = 8;    // gap between the marker and its title
  TyStepsConnectorGap    = 8;    // gap between a marker and each end of its connector
  TyStepsConnectorSize   = 1;    // connector thickness
  TyStepsConnectorLength = 32;   // the connector run AutoSize fits (see TyStepsPreferredSize)

  { The metric token each constant backs. Named constants rather than inline literals
    because three call sites (RenderTo, CalculatePreferredSize, the tests) must agree on
    the spelling — a typo in one would silently strand that site on the default and the
    painted geometry would drift from the measured one. }
  TyStepsMarkerSizeVar      = '--steps-marker-size';
  TyStepsGapVar             = '--steps-gap';
  TyStepsConnectorGapVar    = '--steps-connector-gap';
  TyStepsConnectorSizeVar   = '--steps-connector-size';
  TyStepsConnectorLengthVar = '--steps-connector-length';

  { The style VARIANT a failed step resolves with, so a theme writes a `TyStepsItem.error`
    rule — the shape `TyTag.danger` / `TyAlert.warning` already have. A named constant for
    the same reason as the metric tokens: the control and its tests must not disagree. }
  TyStepsErrorVariant = 'error';

type
  { Which way the rail runs. Ant has both and they are genuinely different controls in
    use: horizontal is a wizard's header (marker, title UNDER it, line running right),
    vertical is an installer's left rail (marker, title BESIDE it, line dropping down). }
  TTyStepsOrientation = (soHorizontal, soVertical);

  { A step's status. Derived from StepIndex (+ ErrorIndex) — never stored per step. }
  TTyStepStatus = (sstWait, sstProcess, sstFinish, sstError);

  { The geometry of ONE step, in DEVICE px, in the same space as the cell it was laid out
    in (RenderTo works in a (0,0)-local control rect, so these are control-local too).
    Every rect is empty when the thing it holds does not fit:
      MarkerRect    — the square marker slot (the number, the check, or the error mark)
      TitleRect     — the title's line band (the painter centres the text in it)
      ConnectorRect — the line to the NEXT step (always empty on the last step) }
  TTyStepsLayout = record
    MarkerRect: TRect;
    TitleRect: TRect;
    ConnectorRect: TRect;
  end;

{ --- Pure rules / geometry (headless-testable; no control, no handle, no theme) -------- }

{ Step AIndex's status, out of ACount steps, with the wizard sitting on AStepIndex and
  AErrorIndex having failed (-1 = none). THE status rule, and the reason no per-step state
  is stored anywhere.
    AIndex < AStepIndex  -> sstFinish   (walked past it)
    AIndex = AStepIndex  -> sstProcess  (you are here)
    AIndex > AStepIndex  -> sstWait     (not yet)
  AIndex = AErrorIndex wins over all three, wherever it sits: a step that failed reads as
  failed whether it is the one you are on or one you already walked past (Ant's rule).
  AStepIndex is deliberately NOT clamped to [0, ACount): -1 means "not started" (every step
  waits) and ACount means "finished" (every step is done). Both are real wizard states —
  ACount is exactly what the last Next click produces — so clamping the way TTyListBox
  clamps ItemIndex would destroy them. StepIndex is a PROGRESS CURSOR, not a selection: it
  points BETWEEN steps as legitimately as at one.
  An index outside [0, ACount) is not a step at all and answers sstWait. }
function TyStepStatus(AIndex, AStepIndex, AErrorIndex, ACount: Integer): TTyStepStatus;

{ The theme states step AIndex resolves with. The whole status->state vocabulary, and it
  invents nothing — every value is an EXISTING TTyState:
    done (sstFinish)     -> [tysNormal]     the resting layer. A finished step is an
                                            ordinary, enabled step; that IS the base rule,
                                            so a theme that writes only a bare TyStepsItem
                                            rule already renders done steps correctly.
    current (sstProcess) -> [tysSelected]   the same resting-selection state TTyButton.Down
                                            and TTySegmented's chosen segment carry, so one
                                            ':selected' rule styles all three.
    waiting (sstWait)    -> [tysDisabled]   greyed-out: not reachable yet.
  ERROR IS NOT IN HERE, deliberately. It is a VARIANT ('error'), not a state — the state
  set has no error member and inventing one would collide with every other control's
  vocabulary. So a failed step keeps the state of its POSITION (a failed current step is
  still :selected) and gains `TyStepsItem.error` on top; the two axes compose instead of
  fighting. That is also why this takes no AErrorIndex.
  Never returns the empty set. }
function TyStepStates(AIndex, AStepIndex, ACount: Integer): TTyStateSet;

{ Step AIndex's CELL — its share of the strip — in DEVICE px relative to the control rect's
  top-left. The cells TILE the padded band exactly along the main axis (AVertical => down,
  else across): cell i's far edge IS cell i+1's near edge, so there is no seam a click can
  fall into. Split by integer division, so an uneven band differs by a single px between
  cells rather than dumping the remainder on one. That tiling is also why the hit-test is
  written as this function's inverse rather than as its own arithmetic: the two cannot drift.
  A zero-extent (never inverted) rect for a degenerate request: no steps, an index out of
  range, a zero-area control, or padding that eats the whole strip. }
function TyStepsCellRect(AClientWidth, AClientHeight, ACount, AIndex: Integer;
  AVertical: Boolean; APadLeft, APadTop, APadRight, APadBottom: Integer): TRect;

{ The step at device-px (X, Y), or -1 for none. The exact INVERSE of TyStepsCellRect (it
  scans that function's own rects), so the step the user clicks is the step painted there.
  The WHOLE cell is the hit zone, not just the marker: a rail whose titles were dead would
  be a poor click target. The strip's padding gutter belongs to no step and answers -1. }
function TyStepsIndexAt(AClientWidth, AClientHeight, ACount: Integer;
  AVertical: Boolean; APadLeft, APadTop, APadRight, APadBottom, X, Y: Integer): Integer;

{ The marker / title / connector rects inside one step's cell. All inputs/outputs DEVICE px.
    ACell        — the cell from TyStepsCellRect.
    AVertical    — which of the two layouts to build (see below).
    AIsLast      — the last step draws no connector (there is nothing to join it to).
    AMarkerSize  — the square marker's edge.
    AGap         — marker-to-title gap.
    ATitleHeight — the title's measured line height.
    AConnectorGap/AConnectorSize — the line's clearance from the marker, and its thickness.

  Both layouts anchor the marker to the cell's LEADING edge rather than centring it, and
  that is the trick that keeps this function pure: the next cell's marker is its own
  leading edge, which IS this cell's far edge, so a connector that runs to the cell's far
  edge meets the next marker exactly — without this function ever needing to know about
  cell i+1. Centred markers would have forced cross-cell arithmetic in here.

    horizontal:  the marker sits at the cell's left with the title UNDER it (both left
                 aligned, so a title never drifts from its own marker), the pair centred in
                 the cell's height; the connector runs right from the marker at the MARKER's
                 centre height — above the title, so the two can never overlap.
    vertical:    the marker sits at the cell's top-left with the title BESIDE it, centred
                 on the marker's centre line; the connector drops from under the marker,
                 down the marker's centre axis.

  A cell too small for a thing yields an empty rect for it rather than an inverted or an
  overflowing one; slots are squashed into the cell, never past it. }
function TyStepsItemLayout(const ACell: TRect; AVertical, AIsLast: Boolean;
  AMarkerSize, AGap, ATitleHeight, AConnectorGap, AConnectorSize: Integer): TTyStepsLayout;

{ The strip size that shows ACount steps whole — the inverse of TyStepsCellRect +
  TyStepsItemLayout: feed the results back in as the client size (same arguments) and every
  cell comes out one natural cell, with exactly AConnectorLength of line in it. Device px.
  This is what AutoSize measures to.
    AWidestTitle/ATitleHeight — the widest title's extent and one line's height.
  The MAIN axis is ACount natural cells; a natural cell is the marker plus its connector
  run (gap + length + gap), or the widest title if that is longer — every cell takes the
  same extent, because a rail whose steps were different sizes reads as broken. The CROSS
  axis is the marker + gap + title block (horizontal) or the marker + gap + widest title
  (vertical), and does NOT depend on ACount.
  The last cell keeps its connector run as trailing space even though it draws no line:
  cells must tile evenly (see TyStepsCellRect), and a short last cell would misalign that
  step's marker with all the others — the one thing a rail must never do. }
procedure TyStepsPreferredSize(ACount, AWidestTitle, ATitleHeight, AMarkerSize, AGap,
  AConnectorGap, AConnectorLength, APadLeft, APadTop, APadRight, APadBottom: Integer;
  AVertical: Boolean; out AWidth, AHeight: Integer);

{ Where an arrow-key press moves the cursor: ACurrent + ADelta, CLAMPED onto a real step
  (no wrap — a rail is a short sequence the user can see all of, so running off the end
  should stop, not teleport back to the start; TTySegmented's rule). This always lands ON a
  step, so the keyboard cannot park the cursor in the "not started" (-1) or "finished"
  (ACount) positions: those are states the HOST sets, not ones a user arrows into.
  -1 when there are no steps at all. }
function TyStepsStepIndex(ACurrent, ACount, ADelta: Integer): Integer;

type
  TTySteps = class(TTyCustomControl)
  private
    FItems: TStrings;
    FStepIndex: Integer;
    FErrorIndex: Integer;
    FOrientation: TTyStepsOrientation;
    FClickable: Boolean;
    FHoverIndex: Integer;      // step under the pointer; -1 = none (only while Clickable)
    FOnChange: TNotifyEvent;
    procedure SetItems(AValue: TStrings);
    procedure ItemsChanged(Sender: TObject);
    procedure SetStepIndex(AValue: Integer);
    procedure SetErrorIndex(AValue: Integer);
    procedure SetOrientation(AValue: TTyStepsOrientation);
    procedure SetClickable(AValue: Boolean);
    { True when the rail runs top-to-bottom — the one place the enum is read. }
    function IsVertical: Boolean;
    { A metric token in DEVICE px at APPI. }
    function MetricPx(const AName: string; ADefault, APPI: Integer): Integer;
    { The strip's own style resolved at REST. Used for measuring and for the cell tiling:
      the rail's geometry must not move because the control took focus or the pointer
      entered it, and CurrentStyle carries tysFocused/tysHover. }
    function RestStrip: TTyStyleSet;
    { The variant tokens step AIndex resolves with: 'error' first (when it failed) and the
      strip's StyleClass after it — see StepVariant's body. }
    function StepVariant(AIndex: Integer): string;
    { The MARKER's style: 'TyStepsItem' with the step's variant and the step's own states. }
    function ItemStyle(AIndex: Integer): TTyStyleSet;
    { The TITLE's style: the same key resolved WITHOUT tysSelected — see the body. }
    function TitleStyle(AIndex: Integer): TTyStyleSet;
    { The state set of step AIndex — the heart of how this control reads. }
    function ItemStates(AIndex: Integer): TTyStateSet;
    { The connector AFTER step AIndex — see the body for the state it takes. }
    function ConnectorStyle(AIndex: Integer): TTyStyleSet;
    { The tokens a step draws its TEXT with: its own where TyStepsItem defines them, the
      STRIP's otherwise. Background/border are deliberately NOT inherited this way (see
      RenderTo): a step with no background of its own must draw no chip. }
    function InheritText(const AStrip, AStep: TTyStyleSet): TTyStyleSet;
    { One text line's height in DEVICE px, from a stable reference glyph ('Ag') so an empty
      title still sizes to a line and two steps' bands cannot disagree. Measured with the
      PAINTER: the titles are drawn with BGRA metrics, and only the same measurer
      reproduces the height those glyphs render at. }
    function LineHeightWith(APainter: TTyPainter; const AStyle: TTyStyleSet): Integer;
    { Widest title + line height, both device px at APPI, in the RESTING title style. }
    procedure MeasureTitles(APPI: Integer; out AWidestPx, ALineHeightPx: Integer);
    { AutoSize re-fit + repaint, for every change that can move the measured size. }
    procedure Refit;
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Re-establish the Clickable -> TabStop coupling that SetClickable has to skip while the
      .lfm is streaming. See the body: a form that says `Clickable = True` and nothing about
      TabStop used to load an unfocusable rail — no click focus, no arrow keys. }
    procedure Loaded; override;
    { How many steps the rail holds. }
    function Count: Integer;
    { Step AIndex's status — the derived rule, for a host that wants to ask rather than
      re-derive it (an installer painting its own summary, say). }
    function StepStatus(AIndex: Integer): TTyStepStatus;
    { Step AIndex's cell in DEVICE px, (0,0)-local — the exact rect the paint laid out in
      and the hit-test measures against; empty when AIndex is out of range. }
    function TyStepRect(AIndex: Integer): TRect;
    { Step AIndex's marker/title/connector rects in DEVICE px, (0,0)-local — the exact rects
      the paint filled. Empty rects throughout when AIndex is out of range. }
    function TyStepLayout(AIndex: Integer): TTyStepsLayout;
    { The step at client device (X, Y), or -1 (the strip's padding gutter included). }
    function TyStepAt(X, Y: Integer): Integer;
  published
    { The steps, one TITLE per line. Title-only, deliberately: Ant's per-step `description`
      would need a second string per item, and the only way to carry one on a TStrings is
      the Objects[] pointer — which would make the host own a heap object per line, leak it
      on any edit it did not hand-clean, and quietly break the moment someone assigned a
      plain TStringList in. A published Descriptions: TStrings kept in lockstep with this
      one is the honest way to add it later, and it is not needed yet.
      Editing the list re-fits an auto-sized rail. StepIndex is NOT re-validated (see it). }
    property Items: TStrings read FItems write SetItems;
    { Which step the wizard is ON: everything before it is done, everything after waits.
      NOT clamped to the list — -1 means "not started" and Count means "finished", both of
      which are real states a wizard passes through (see TyStepStatus). Fires OnChange. }
    property StepIndex: Integer read FStepIndex write SetStepIndex default -1;
    { The step that FAILED, or -1 for none. One index rather than a status per step: a
      wizard has one thing go wrong at a time, and the alternative (a per-item status list
      parallel to Items) is exactly the bookkeeping this control exists to remove.
      The failed step resolves `TyStepsItem.error` on top of its position's state and draws
      the error mark instead of its number — so a theme with no `.error` rule degrades to a
      normal-looking step, never to a hard-coded red. }
    property ErrorIndex: Integer read FErrorIndex write SetErrorIndex default -1;
    { Which way the rail runs; changing it re-fits an auto-sized rail (the two layouts have
      completely different natural sizes). }
    property Orientation: TTyStepsOrientation read FOrientation write SetOrientation
      default soHorizontal;
    { Let the USER move the cursor by clicking a step or arrowing onto it (Ant's onChange
      Steps). OFF by default: a wizard drives its own StepIndex from Next/Back, and a bar
      that silently let the user skip to step 5 would be a bug in most of them.
      Turning it on also makes the rail focusable (it sets TabStop), because the arrow keys
      are half the point. Any step is reachable, including waiting ones — the control does
      not know which jumps the host allows; a host that wants to refuse one sets StepIndex
      back inside OnChange. }
    property Clickable: Boolean read FClickable write SetClickable default False;
    { Fires whenever StepIndex actually changes — by click, by key, or from code. Setting
      the same index again is not a change and stays silent. Not fired while the .lfm is
      streaming: loading a form is not a step change. }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    { With AutoSize the rail hugs its natural size in BOTH axes: the main axis is one
      natural cell per step, the cross axis the marker + title block. }
    property AutoSize;
    property Align;
    property Anchors;
    property StyleClass;
    property StyleOverride;
    property Controller;
  end;

implementation

{ --- pure rules / geometry ------------------------------------------------------------ }

function TyStepStatus(AIndex, AStepIndex, AErrorIndex, ACount: Integer): TTyStepStatus;
begin
  Result := sstWait;
  // Not a step at all: no status to have. (Guards every caller's loop bound in one place.)
  if (ACount <= 0) or (AIndex < 0) or (AIndex >= ACount) then Exit;
  // Error wins wherever it sits, including on the current step. AErrorIndex = -1 can never
  // match here because AIndex is already known to be >= 0.
  if AIndex = AErrorIndex then Exit(sstError);
  if AIndex < AStepIndex then
    Result := sstFinish
  else if AIndex = AStepIndex then
    Result := sstProcess;
  // else: sstWait, as initialised. AStepIndex = -1 leaves every step here ("not started");
  // AStepIndex >= ACount makes every step sstFinish above ("done").
end;

function TyStepStates(AIndex, AStepIndex, ACount: Integer): TTyStateSet;
begin
  // AErrorIndex = -1: error is a variant, not a state (see the declaration).
  case TyStepStatus(AIndex, AStepIndex, -1, ACount) of
    sstFinish:  Result := [tysNormal];
    sstProcess: Result := [tysSelected];
  else
    // sstWait, and the out-of-range case (which is not painted anyway). sstError is
    // unreachable: -1 was passed for it.
    Result := [tysDisabled];
  end;
end;

function TyStepsCellRect(AClientWidth, AClientHeight, ACount, AIndex: Integer;
  AVertical: Boolean; APadLeft, APadTop, APadRight, APadBottom: Integer): TRect;
var
  bandL, bandT, bandR, bandB, span: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if (ACount <= 0) or (AIndex < 0) or (AIndex >= ACount) then Exit;
  if (AClientWidth <= 0) or (AClientHeight <= 0) then Exit;
  if APadLeft < 0 then APadLeft := 0;
  if APadTop < 0 then APadTop := 0;
  if APadRight < 0 then APadRight := 0;
  if APadBottom < 0 then APadBottom := 0;

  // The band: the strip inset by its themed padding on all four sides. Padding that eats
  // the whole strip leaves nothing to lay out (an empty rect, never an inverted one).
  bandL := APadLeft;
  bandR := AClientWidth - APadRight;
  bandT := APadTop;
  bandB := AClientHeight - APadBottom;
  if (bandR <= bandL) or (bandB <= bandT) then Exit;

  // Plain integer division rather than MulDiv: the tiling only holds if cell i's far edge
  // is computed by the SAME expression as cell i+1's near edge, and truncation makes that
  // exact (and free of MulDiv's rounding, which differs by platform).
  if AVertical then
  begin
    span := bandB - bandT;
    Result := Rect(bandL, bandT + (span * AIndex) div ACount,
                   bandR, bandT + (span * (AIndex + 1)) div ACount);
  end
  else
  begin
    span := bandR - bandL;
    Result := Rect(bandL + (span * AIndex) div ACount, bandT,
                   bandL + (span * (AIndex + 1)) div ACount, bandB);
  end;
end;

function TyStepsIndexAt(AClientWidth, AClientHeight, ACount: Integer;
  AVertical: Boolean; APadLeft, APadTop, APadRight, APadBottom, X, Y: Integer): Integer;
var
  i: Integer;
  R: TRect;
begin
  Result := -1;
  for i := 0 to ACount - 1 do
  begin
    R := TyStepsCellRect(AClientWidth, AClientHeight, ACount, i, AVertical,
      APadLeft, APadTop, APadRight, APadBottom);
    if (R.Right > R.Left) and (R.Bottom > R.Top)
       and (X >= R.Left) and (X < R.Right) and (Y >= R.Top) and (Y < R.Bottom) then
      Exit(i);
  end;
end;

{ The band an ASize-long slot occupies when centred on ACentre and clamped into [ALo, AHi]:
  floored at the near edge and squashed at the far one rather than overflowing (TyTagLayout's
  rule for its own close slot). False = no band left at all. }
function StepsBand(ACentre, ASize, ALo, AHi: Integer; out ABandLo, ABandHi: Integer): Boolean;
begin
  ABandLo := ACentre - ASize div 2;
  if ABandLo < ALo then ABandLo := ALo;
  if ABandLo > AHi then ABandLo := AHi;
  ABandHi := ABandLo + ASize;
  if ABandHi > AHi then ABandHi := AHi;
  Result := ABandHi > ABandLo;
end;

function TyStepsItemLayout(const ACell: TRect; AVertical, AIsLast: Boolean;
  AMarkerSize, AGap, ATitleHeight, AConnectorGap, AConnectorSize: Integer): TTyStepsLayout;
var
  cellW, cellH, blockH, blockT, centreY, centreX: Integer;
  markEnd, markBottom, runLo, runHi, bandLo, bandHi: Integer;
begin
  Result.MarkerRect := Rect(0, 0, 0, 0);
  Result.TitleRect := Rect(0, 0, 0, 0);
  Result.ConnectorRect := Rect(0, 0, 0, 0);
  cellW := ACell.Right - ACell.Left;
  cellH := ACell.Bottom - ACell.Top;
  if (cellW <= 0) or (cellH <= 0) then Exit;
  // Clamp every negative input once, here, so the arithmetic below can be read straight.
  if AMarkerSize < 0 then AMarkerSize := 0;
  if AGap < 0 then AGap := 0;
  if ATitleHeight < 0 then ATitleHeight := 0;
  if AConnectorGap < 0 then AConnectorGap := 0;
  if AConnectorSize < 0 then AConnectorSize := 0;

  if AVertical then
  begin
    // --- the marker: the cell's top-left corner ---------------------------------
    markEnd := ACell.Left + AMarkerSize;
    if markEnd > ACell.Right then markEnd := ACell.Right;    // squashed, never overflowing
    markBottom := ACell.Top + AMarkerSize;
    if markBottom > ACell.Bottom then markBottom := ACell.Bottom;
    if (markEnd > ACell.Left) and (markBottom > ACell.Top) then
      Result.MarkerRect := Rect(ACell.Left, ACell.Top, markEnd, markBottom);
    // The marker's centre lines, computed from the UNCLAMPED size so a squashed marker
    // still hangs its title and its connector where a whole one would have.
    centreY := ACell.Top + AMarkerSize div 2;
    centreX := ACell.Left + AMarkerSize div 2;

    // --- the title: beside the marker, its line centred on the marker's centre ---
    runLo := ACell.Left + AMarkerSize + AGap;
    if (runLo < ACell.Right)
       and StepsBand(centreY, ATitleHeight, ACell.Top, ACell.Bottom, bandLo, bandHi) then
      Result.TitleRect := Rect(runLo, bandLo, ACell.Right, bandHi);

    // --- the connector: straight down the marker's axis to the next cell's top ---
    if (not AIsLast) and (AConnectorSize > 0) then
    begin
      runLo := ACell.Top + AMarkerSize + AConnectorGap;
      runHi := ACell.Bottom - AConnectorGap;
      if (runHi > runLo)
         and StepsBand(centreX, AConnectorSize, ACell.Left, ACell.Right, bandLo, bandHi) then
        Result.ConnectorRect := Rect(bandLo, runLo, bandHi, runHi);
    end;
  end
  else
  begin
    // --- the marker + title block, centred in the cell's height ------------------
    blockH := AMarkerSize + AGap + ATitleHeight;
    blockT := ACell.Top + (cellH - blockH) div 2;
    if blockT < ACell.Top then blockT := ACell.Top;   // a block taller than its cell starts at the top
    markEnd := ACell.Left + AMarkerSize;
    if markEnd > ACell.Right then markEnd := ACell.Right;
    markBottom := blockT + AMarkerSize;
    if markBottom > ACell.Bottom then markBottom := ACell.Bottom;
    if (markEnd > ACell.Left) and (markBottom > blockT) then
      Result.MarkerRect := Rect(ACell.Left, blockT, markEnd, markBottom);
    centreY := blockT + AMarkerSize div 2;

    // --- the title: under the marker, spanning the cell so it ellipsises at the
    //     next step's marker rather than running into it ---------------------------
    if ATitleHeight > 0 then
    begin
      runLo := blockT + AMarkerSize + AGap;
      runHi := runLo + ATitleHeight;
      if runHi > ACell.Bottom then runHi := ACell.Bottom;
      if (runHi > runLo) and (runLo < ACell.Bottom) then
        Result.TitleRect := Rect(ACell.Left, runLo, ACell.Right, runHi);
    end;

    // --- the connector: right from the marker, at the MARKER's centre height, so it
    //     passes above the title instead of through it ----------------------------
    if (not AIsLast) and (AConnectorSize > 0) then
    begin
      runLo := ACell.Left + AMarkerSize + AConnectorGap;
      runHi := ACell.Right - AConnectorGap;
      if (runHi > runLo)
         and StepsBand(centreY, AConnectorSize, ACell.Top, ACell.Bottom, bandLo, bandHi) then
        Result.ConnectorRect := Rect(runLo, bandLo, runHi, bandHi);
    end;
  end;
end;

procedure TyStepsPreferredSize(ACount, AWidestTitle, ATitleHeight, AMarkerSize, AGap,
  AConnectorGap, AConnectorLength, APadLeft, APadTop, APadRight, APadBottom: Integer;
  AVertical: Boolean; out AWidth, AHeight: Integer);
var
  cellMain: Integer;
begin
  if ACount < 0 then ACount := 0;
  if AWidestTitle < 0 then AWidestTitle := 0;
  if ATitleHeight < 0 then ATitleHeight := 0;
  if AMarkerSize < 0 then AMarkerSize := 0;
  if AGap < 0 then AGap := 0;
  if AConnectorGap < 0 then AConnectorGap := 0;
  if AConnectorLength < 0 then AConnectorLength := 0;
  if APadLeft < 0 then APadLeft := 0;
  if APadTop < 0 then APadTop := 0;
  if APadRight < 0 then APadRight := 0;
  if APadBottom < 0 then APadBottom := 0;

  // A natural cell along the MAIN axis: the marker, then its connector run (a gap either
  // side of AConnectorLength of line). Feed the total back into TyStepsCellRect and
  // TyStepsItemLayout hands exactly AConnectorLength of connector back.
  cellMain := AMarkerSize + AConnectorGap + AConnectorLength + AConnectorGap;
  if AVertical then
  begin
    // The title sits BESIDE the marker, so a title line taller than the whole run still
    // has to fit the row.
    if ATitleHeight > cellMain then cellMain := ATitleHeight;
    AHeight := APadTop + ACount * cellMain + APadBottom;
    AWidth := APadLeft + AMarkerSize + AGap + AWidestTitle + APadRight;
  end
  else
  begin
    // The title sits UNDER the marker, so a title wider than the run widens the cell.
    if AWidestTitle > cellMain then cellMain := AWidestTitle;
    AWidth := APadLeft + ACount * cellMain + APadRight;
    AHeight := APadTop + AMarkerSize + AGap + ATitleHeight + APadBottom;
  end;
  if AWidth < 1 then AWidth := 1;
  if AHeight < 1 then AHeight := 1;
end;

function TyStepsStepIndex(ACurrent, ACount, ADelta: Integer): Integer;
begin
  if ACount <= 0 then Exit(-1);
  Result := ACurrent + ADelta;
  // Clamped onto a real step: this also drags the "not started" (-1) and "finished"
  // (ACount) cursors back onto the rail, which is what an arrow key should do from either.
  if Result < 0 then Result := 0;
  if Result > ACount - 1 then Result := ACount - 1;
end;

{ --- TTySteps ------------------------------------------------------------------------- }

constructor TTySteps.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TStringList.Create;
  TStringList(FItems).OnChange := @ItemsChanged;
  FStepIndex := -1;
  FErrorIndex := -1;
  FOrientation := soHorizontal;
  FClickable := False;
  FHoverIndex := -1;
  // Not a tab stop: the default rail is an inert status display (see Clickable).
  TabStop := False;
  // A drop size for the designer: a wizard header wide enough for three or four steps.
  Width := 360;
  Height := 56;
end;

destructor TTySteps.Destroy;
begin
  // Drop the change hook before freeing: the list fires OnChange as it clears.
  TStringList(FItems).OnChange := nil;
  FItems.Free;
  inherited Destroy;
end;

procedure TTySteps.Loaded;
begin
  inherited Loaded;
  { SetClickable skips the TabStop coupling while csLoading is set, on the theory that the
    .lfm already carries the TabStop the designer saved. It does not, and cannot: TabStop's
    DECLARED default is False (TWinControl's), so a designer that turned Clickable on writes
    `TabStop = True` only because the setter had already flipped it — and a HAND-WRITTEN
    .lfm (every example in this repo is one) simply says `Clickable = True` and stops there.
    The rail then streamed in with TabStop=False: unreachable by Tab, and unfocusable by
    click too (TTyCustomControl.MouseDown gates click-to-focus on TabStop), so the arrow
    keys — the half of Clickable that is not the mouse — never got a key to handle.
    Re-assert the invariant here, once, with every streamed value in. A host that wants a
    clickable-but-unfocusable rail still gets it by assigning TabStop after load, which is
    the same escape hatch it had before. }
  if FClickable then TabStop := True;
end;

function TTySteps.GetStyleTypeKey: string;
begin
  Result := 'TySteps';
end;

function TTySteps.Count: Integer;
begin
  Result := FItems.Count;
end;

function TTySteps.IsVertical: Boolean;
begin
  Result := FOrientation = soVertical;
end;

{ --- items / cursor ------------------------------------------------------------------- }

procedure TTySteps.Refit;
begin
  // Every visual value here is theme-derived, so a change that can move the measured size
  // (a step more, the other orientation) must re-fit an auto-sized rail, not just repaint.
  if AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
  if not (csLoading in ComponentState) then Invalidate;
end;

procedure TTySteps.SetItems(AValue: TStrings);
begin
  FItems.Assign(AValue);   // fires ItemsChanged
end;

procedure TTySteps.ItemsChanged(Sender: TObject);
begin
  { StepIndex is deliberately NOT re-validated here (TTySegmented re-validates its
    ItemIndex at exactly this point). A cursor of 3 on a 3-step rail means "finished", and
    it stays meaningful when a 4th step is appended — it then means "on the last one".
    There is no value to clamp to that would be more right than the one the host set. }
  Refit;
end;

procedure TTySteps.SetStepIndex(AValue: Integer);
begin
  if FStepIndex = AValue then Exit;
  FStepIndex := AValue;
  if csLoading in ComponentState then Exit;
  Invalidate;   // a pure repaint: the cursor moves no geometry, only which style each step resolves
  // Not fired while streaming (the Exit above): the .lfm's own OnChange handler is wired
  // by then, and firing it would hand the host a "the step changed" event before the form
  // is even shown.
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTySteps.SetErrorIndex(AValue: Integer);
begin
  if FErrorIndex = AValue then Exit;
  FErrorIndex := AValue;
  // No OnChange: the wizard did not move, one step just went red. And no re-fit — a theme
  // COULD pad `.error` differently, but the cells tile evenly regardless of any one step's
  // style, so nothing about the rail's size can depend on which step failed.
  if not (csLoading in ComponentState) then Invalidate;
end;

procedure TTySteps.SetOrientation(AValue: TTyStepsOrientation);
begin
  if FOrientation = AValue then Exit;
  FOrientation := AValue;
  // A hover from the old layout means nothing in the new one.
  FHoverIndex := -1;
  Refit;   // the two layouts have completely different natural sizes
end;

procedure TTySteps.SetClickable(AValue: Boolean);
begin
  if FClickable = AValue then Exit;
  FClickable := AValue;
  // An inert rail keeps no hover — it never lights one, and a stale one would outlive the
  // property change.
  if not FClickable then FHoverIndex := -1;
  if not (csLoading in ComponentState) then
  begin
    // Focusability follows clickability: a status display must not eat a tab stop, and a
    // navigable rail must take one (the arrow keys are half of what Clickable buys).
    // Skipped while streaming so this setter cannot fight the .lfm's own property order
    // (TabStop, declared by the base, is read BEFORE Clickable). Loaded re-asserts the
    // coupling once every streamed value is in — do NOT rely on the .lfm carrying TabStop
    // itself; it usually does not. See TTySteps.Loaded.
    TabStop := AValue;
    Invalidate;
  end;
end;

{ --- theme metrics -------------------------------------------------------------------- }

function TTySteps.MetricPx(const AName: string; ADefault, APPI: Integer): Integer;
begin
  if APPI <= 0 then APPI := 96;
  Result := ActiveController.Metric(AName, ADefault);
  if Result < 0 then Result := 0;
  // MulDiv(...,APPI,96) is the same logical->device conversion TTyPainter.Scale applies, so
  // the rects the hit-test measures are the rects the paint drew.
  Result := MulDiv(Result, APPI, 96);
end;

function TTySteps.RestStrip: TTyStyleSet;
begin
  // [tysNormal], not CurrentStates: the rail's cell tiling and its measured size must not
  // move because the control took focus or the pointer entered it. (TTySegmented dodges
  // this by taking its track inset from a metric; ours is the strip's own `padding`, which
  // a :focus rule could otherwise re-tune under our feet.)
  Result := ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass, [tysNormal]);
end;

{ --- state / style -------------------------------------------------------------------- }

function TTySteps.StepStatus(AIndex: Integer): TTyStepStatus;
begin
  Result := TyStepStatus(AIndex, FStepIndex, FErrorIndex, FItems.Count);
end;

function TTySteps.ItemStates(AIndex: Integer): TTyStateSet;
begin
  Result := TyStepStates(AIndex, FStepIndex, FItems.Count);
  if not Enabled then
  begin
    { A disabled rail KEEPS :selected on its current step — losing it would make the bar
      read as "no step is current" rather than "you cannot change this", and which step you
      are on is the only thing this control says. The cascade does the rest: ResolveLayer
      applies :selected as the resting layer and :disabled LAST at the highest precedence,
      so the current step's chip survives while the disabled ink wins over it.
      Hover is deliberately absent: a disabled control takes none. }
    Include(Result, tysDisabled);
    Exit;
  end;
  { A WAITING step is already :disabled, and it can still hover — Clickable makes every step
    reachable, so the future ones are exactly the targets the user aims at, and a dead
    pointer there would read as broken. The pair is not a contradiction the theme has to
    resolve: :disabled is applied last, so it wins on any property both rules set, and a
    theme that wants a tint under the pointer writes `TyStepsItem:disabled:hover`. }
  if FClickable and (AIndex = FHoverIndex) then Include(Result, tysHover);
  { No tysFocused per step, deliberately: focus belongs to the WHOLE rail. That needs no
    code — the base's CurrentStates already hands tysFocused to the STRIP's own style, so a
    plain 'TySteps:focus' outline rule rings the control through DrawFrame like every other
    focusable control here. }
end;

function TTySteps.StepVariant(AIndex: Integer): string;
begin
  // The 'error' token goes FIRST and the user's StyleClass after it, so ResolveLayer (which
  // applies variant tokens in textual order, later token winning per property) lets an
  // explicit class layer OVER the error look per-property rather than replacing it. That is
  // TTyAlert.StyleVariant's rule, and it keeps `Steps.StyleClass := 'compact'` a padding
  // tweak that leaves the failed step red.
  Result := Trim(StyleClass);
  if StepStatus(AIndex) <> sstError then Exit;
  if Result = '' then
    Result := TyStepsErrorVariant
  else
    Result := TyStepsErrorVariant + ' ' + Result;
end;

function TTySteps.ItemStyle(AIndex: Integer): TTyStyleSet;
begin
  Result := ActiveController.Model.ResolveStyle('TyStepsItem', StepVariant(AIndex),
    ItemStates(AIndex));
end;

function TTySteps.TitleStyle(AIndex: Integer): TTyStyleSet;
var
  st: TTyStateSet;
begin
  { The two-ink problem, solved the way TTyCheckBox already solves it (it resolves its
    CAPTION with `CurrentStates - [tysActive]` so the :active accent fill + white glyph stay
    box-only). Here the current step's marker is a filled accent chip with on-accent ink —
    and if the title took that same ink it would be on-accent text on the STRIP's surface,
    i.e. invisible. So the title resolves the SAME key WITHOUT tysSelected: it lands on the
    resting layer and keeps the strip's ordinary text colour, while :selected stays a
    marker-only rule.
    :disabled deliberately SURVIVES, which is what makes a waiting step's title grey out —
    the one per-status title distinction that matters. Done and current titles read alike,
    exactly as a checkbox's caption reads alike checked or not. }
  st := ItemStates(AIndex) - [tysSelected];
  if st = [] then Include(st, tysNormal);   // the current step, with nothing else on it
  Result := ActiveController.Model.ResolveStyle('TyStepsItem', StepVariant(AIndex), st);
end;

function TTySteps.ConnectorStyle(AIndex: Integer): TTyStyleSet;
begin
  { The connector after step AIndex takes the states of the step it LEADS TO, not of the one
    it leaves. That single choice is what makes the trail light up exactly as far as the
    user has walked, with no code branch and no third status rule:
      into a done step    -> [tysNormal]   the resting rule  -> travelled
      into the current one-> [tysSelected] inherits the resting rule unless the theme says
                                           otherwise -> travelled (you walked here)
      into a waiting step -> [tysDisabled] -> not yet
    So a theme needs exactly two rules — the base line colour and a `:disabled` one — and
    gets Ant's behaviour. Taking the LEAVING step's states instead would have forced the
    resting rule to mean "travelled" while `:selected` meant "not travelled", which is the
    same picture written backwards.
    The strip's StyleClass only, no error variant: a step failing does not recolour the path
    that led to it (Ant leaves it alone), and the connector has no error look to define. }
  Result := ActiveController.Model.ResolveStyle('TyStepsConnector', StyleClass,
    ItemStates(AIndex + 1));
end;

function TTySteps.InheritText(const AStrip, AStep: TTyStyleSet): TTyStyleSet;
{ A step's ink and font: its own where TyStepsItem sets them, the STRIP's otherwise. This is
  the house degradation rule (no colour => inherit the parent's ink) extended to the font by
  the same logic — a theme that styles only TySteps must still get legible, correctly-sized
  titles and numbers, and NEVER a hard-coded colour. (TTySegmented.ItemTextStyle's shape.) }
begin
  Result := AStep;
  if not (tpTextColor in AStep.Present) then
  begin
    Result.TextColor := AStrip.TextColor;
    if tpTextColor in AStrip.Present then Include(Result.Present, tpTextColor);
  end;
  if not (tpFontName in AStep.Present) then
  begin
    Result.FontName := AStrip.FontName;
    if tpFontName in AStrip.Present then Include(Result.Present, tpFontName);
  end;
  if not (tpFontSize in AStep.Present) then
  begin
    Result.FontSize := AStrip.FontSize;
    if tpFontSize in AStrip.Present then Include(Result.Present, tpFontSize);
  end;
  if not (tpFontWeight in AStep.Present) then
  begin
    Result.FontWeight := AStrip.FontWeight;
    if tpFontWeight in AStrip.Present then Include(Result.Present, tpFontWeight);
  end;
end;

{ --- measurement ---------------------------------------------------------------------- }

function TTySteps.LineHeightWith(APainter: TTyPainter; const AStyle: TTyStyleSet): Integer;
begin
  // A stable reference glyph: an empty title still sizes its band to a line.
  Result := APainter.MeasureText('Ag', AStyle.FontName, ResolveFontSize(AStyle),
    AStyle.FontWeight).cy;
  if Result < 1 then Result := 1;
end;

procedure TTySteps.MeasureTitles(APPI: Integer; out AWidestPx, ALineHeightPx: Integer);
{ Measures with a CANVAS-LESS painter — the TTyBadge / TTyAlert idiom: BeginPaint(nil, ...)
  builds only the painter's internal bitmap and EndPaint frees it WITHOUT blitting, so this
  is safe outside a paint cycle and leaks nothing. It has to be the painter and not an LCL
  canvas: the titles are drawn with BGRA text metrics, and only the same measurer reproduces
  the extent those glyphs actually render at. }
var
  P: TTyPainter;
  txtS: TTyStyleSet;
  sz: TSize;
  i, fs: Integer;
begin
  AWidestPx := 0;
  ALineHeightPx := 0;
  // The RESTING title style: a theme that bolds the current step must not make the rail's
  // size depend on which step the wizard happens to be on.
  txtS := InheritText(RestStrip,
    ActiveController.Model.ResolveStyle('TyStepsItem', StyleClass, [tysNormal]));
  P := TTyPainter.Create;
  try
    P.BeginPaint(nil, Rect(0, 0, 1, 1), APPI);   // 1x1: nothing is drawn, only measured
    fs := ResolveFontSize(txtS);
    sz := P.MeasureText('Ag', txtS.FontName, fs, txtS.FontWeight);
    ALineHeightPx := sz.cy;
    for i := 0 to FItems.Count - 1 do
    begin
      sz := P.MeasureText(FItems[i], txtS.FontName, fs, txtS.FontWeight);
      if sz.cx > AWidestPx then AWidestPx := sz.cx;
    end;
    P.EndPaint;   // nil canvas -> no blit, just frees the measure bitmap
  finally
    P.Free;
  end;
  if AWidestPx < 0 then AWidestPx := 0;
  if ALineHeightPx < 1 then ALineHeightPx := 1;
end;

procedure TTySteps.CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
  WithThemeSpace: Boolean);
var
  stripS: TTyStyleSet;
  ppi, widest, lineH: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  stripS := RestStrip;
  MeasureTitles(ppi, widest, lineH);
  TyStepsPreferredSize(FItems.Count, widest, lineH,
    MetricPx(TyStepsMarkerSizeVar, TyStepsMarkerSize, ppi),
    MetricPx(TyStepsGapVar, TyStepsGap, ppi),
    MetricPx(TyStepsConnectorGapVar, TyStepsConnectorGap, ppi),
    MetricPx(TyStepsConnectorLengthVar, TyStepsConnectorLength, ppi),
    MulDiv(stripS.Padding.Left, ppi, 96), MulDiv(stripS.Padding.Top, ppi, 96),
    MulDiv(stripS.Padding.Right, ppi, 96), MulDiv(stripS.Padding.Bottom, ppi, 96),
    IsVertical, PreferredWidth, PreferredHeight);
end;

{ --- geometry ------------------------------------------------------------------------- }

function TTySteps.TyStepRect(AIndex: Integer): TRect;
var
  stripS: TTyStyleSet;
  ppi: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  stripS := RestStrip;
  Result := TyStepsCellRect(ClientWidth, ClientHeight, FItems.Count, AIndex, IsVertical,
    MulDiv(stripS.Padding.Left, ppi, 96), MulDiv(stripS.Padding.Top, ppi, 96),
    MulDiv(stripS.Padding.Right, ppi, 96), MulDiv(stripS.Padding.Bottom, ppi, 96));
end;

function TTySteps.TyStepLayout(AIndex: Integer): TTyStepsLayout;
var
  P: TTyPainter;
  ppi, lineH: Integer;
  cellR: TRect;
begin
  Result.MarkerRect := Rect(0, 0, 0, 0);
  Result.TitleRect := Rect(0, 0, 0, 0);
  Result.ConnectorRect := Rect(0, 0, 0, 0);
  cellR := TyStepRect(AIndex);
  if (cellR.Right <= cellR.Left) or (cellR.Bottom <= cellR.Top) then Exit;
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  P := TTyPainter.Create;
  try
    P.BeginPaint(nil, Rect(0, 0, 1, 1), ppi);
    lineH := LineHeightWith(P, InheritText(RestStrip,
      ActiveController.Model.ResolveStyle('TyStepsItem', StyleClass, [tysNormal])));
    P.EndPaint;
  finally
    P.Free;
  end;
  Result := TyStepsItemLayout(cellR, IsVertical, AIndex = FItems.Count - 1,
    MetricPx(TyStepsMarkerSizeVar, TyStepsMarkerSize, ppi),
    MetricPx(TyStepsGapVar, TyStepsGap, ppi), lineH,
    MetricPx(TyStepsConnectorGapVar, TyStepsConnectorGap, ppi),
    MetricPx(TyStepsConnectorSizeVar, TyStepsConnectorSize, ppi));
end;

function TTySteps.TyStepAt(X, Y: Integer): Integer;
var
  stripS: TTyStyleSet;
  ppi: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  stripS := RestStrip;
  Result := TyStepsIndexAt(ClientWidth, ClientHeight, FItems.Count, IsVertical,
    MulDiv(stripS.Padding.Left, ppi, 96), MulDiv(stripS.Padding.Top, ppi, 96),
    MulDiv(stripS.Padding.Right, ppi, 96), MulDiv(stripS.Padding.Bottom, ppi, 96), X, Y);
end;

{ --- input ---------------------------------------------------------------------------- }

procedure TTySteps.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  hit: Integer;
begin
  if not Enabled then Exit;
  // The base sets FPressed and moves focus here (TabStop + CanFocus), so a click behaves
  // like a Tab and the arrow keys work straight after it.
  inherited MouseDown(Button, Shift, X, Y);
  if (Button <> mbLeft) or (not FClickable) then Exit;
  // Move on PRESS, not on release: the rail is a switch, and the house tab strip switches
  // on press too. A press in the strip's padding gutter answers -1 and is inert — it must
  // not reset a cursor the user can see.
  hit := TyStepAt(X, Y);
  if hit >= 0 then StepIndex := hit;
end;

procedure TTySteps.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  hit: Integer;
begin
  if not Enabled then Exit;
  inherited MouseMove(Shift, X, Y);
  // An inert rail lights nothing: no Clickable, no hover, and no per-move hit-test either.
  if not FClickable then Exit;
  hit := TyStepAt(X, Y);
  if hit <> FHoverIndex then
  begin
    FHoverIndex := hit;
    Invalidate;
  end;
end;

procedure TTySteps.MouseLeave;
begin
  inherited MouseLeave;   // clears the strip's own hover
  if FHoverIndex <> -1 then
  begin
    FHoverIndex := -1;
    Invalidate;
  end;
end;

procedure TTySteps.KeyDown(var Key: Word; Shift: TShiftState);
var
  back, fwd: Word;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  if (not FClickable) or (FItems.Count = 0) then Exit;
  { The arrow keys walk the rail — the reason this control is windowed at all. They follow
    the ORIENTATION (Left/Right across a header, Up/Down down a rail) so the key that moves
    the cursor is the one that points along it; the cross-axis pair is left alone for the
    form to use. Every handled key is consumed (Key := 0) so it never also reaches the form.
    Home/End jump to the ends, matching TTyCustomTabStrip's keyboard. }
  if IsVertical then
  begin
    back := VK_UP;
    fwd := VK_DOWN;
  end
  else
  begin
    back := VK_LEFT;
    fwd := VK_RIGHT;
  end;
  if Key = back then
  begin
    StepIndex := TyStepsStepIndex(FStepIndex, FItems.Count, -1);
    Key := 0;
  end
  else if Key = fwd then
  begin
    StepIndex := TyStepsStepIndex(FStepIndex, FItems.Count, 1);
    Key := 0;
  end
  else if Key = VK_HOME then
  begin
    StepIndex := 0;
    Key := 0;
  end
  else if Key = VK_END then
  begin
    StepIndex := FItems.Count - 1;
    Key := 0;
  end;
end;

{ --- painting ------------------------------------------------------------------------- }

procedure TTySteps.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, markS, markTxtS, titleS, connS: TTyStyleSet;
  R, cellR: TRect;
  lay: TTyStepsLayout;
  i, lineH, markerPx, gapPx, connGapPx, connSizePx: Integer;
  padL, padT, padR, padB: Integer;
  vert, isLast: Boolean;
begin
  P := TTyPainter.Create;
  try
    // A (0,0)-local rect: the painter builds a (W x H) bitmap and blits it at
    // ARect.Left/Top, so a non-zero ARect origin would shift the whole control.
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    // The strip: background + border + shadow + opacity + focus outline, all from the
    // resolved TySteps style. DrawFrame fills the parent's opaque surface first, which a
    // WINDOWED control needs whatever the theme says (its own window shows through the
    // corner gaps otherwise) — everything of OURS below is gated on the key being defined.
    DrawFrame(P, R, S);
    if not (tpBackground in S.Present) then
    begin
      // No TySteps rule -> draw nothing at all; degrade rather than invent a look.
      P.EndPaint;
      Exit;
    end;

    vert := IsVertical;
    markerPx := P.Scale(ActiveController.Metric(TyStepsMarkerSizeVar, TyStepsMarkerSize));
    gapPx := P.Scale(ActiveController.Metric(TyStepsGapVar, TyStepsGap));
    connGapPx := P.Scale(ActiveController.Metric(TyStepsConnectorGapVar, TyStepsConnectorGap));
    connSizePx := P.Scale(ActiveController.Metric(TyStepsConnectorSizeVar, TyStepsConnectorSize));
    // The padding of the RESTING strip, not of S: the cells must tile identically whether
    // or not the rail happens to be focused (RestStrip's comment).
    padL := P.Scale(RestStrip.Padding.Left);
    padT := P.Scale(RestStrip.Padding.Top);
    padR := P.Scale(RestStrip.Padding.Right);
    padB := P.Scale(RestStrip.Padding.Bottom);
    // ONE line height for every step, measured in the resting title style: a theme that
    // sizes the current step's font differently must not push that step's marker to a
    // different height from its neighbours'. It is also exactly what AutoSize measured.
    // RestStrip, NOT S(=CurrentStyle): the block line-height must not depend on whether the rail
    // happens to be focused/hovered, or the painted marker/title Y drifts away from what
    // TyStepLayout reports and AutoSize measured (both use RestStrip). Same reason the padding
    // just above uses RestStrip. A theme setting a font on TySteps:focus was the trigger.
    lineH := LineHeightWith(P, InheritText(RestStrip,
      ActiveController.Model.ResolveStyle('TyStepsItem', StyleClass, [tysNormal])));

    for i := 0 to FItems.Count - 1 do
    begin
      cellR := TyStepsCellRect(R.Right, R.Bottom, FItems.Count, i, vert,
        padL, padT, padR, padB);
      if (cellR.Right <= cellR.Left) or (cellR.Bottom <= cellR.Top) then Continue;
      isLast := i = FItems.Count - 1;
      lay := TyStepsItemLayout(cellR, vert, isLast, markerPx, gapPx, lineH,
        connGapPx, connSizePx);

      // The connector FIRST, so a marker chip overdraws the line's end rather than the
      // line cutting across the chip.
      if lay.ConnectorRect.Right > lay.ConnectorRect.Left then
      begin
        connS := ConnectorStyle(i);
        // An undefined TyStepsConnector key leaves no background -> no line, and the
        // markers still draw. Never a hard-coded colour.
        if tpBackground in connS.Present then
          P.FillBackground(lay.ConnectorRect, connS.Background, TyEffectiveCorners(connS));
      end;

      markS := ItemStyle(i);
      markTxtS := InheritText(S, markS);
      if lay.MarkerRect.Right > lay.MarkerRect.Left then
      begin
        // The chip. An undefined TyStepsItem key leaves no background -> no chip, and the
        // marks below still draw: a theme that fills only :selected gets the classic "only
        // the step you are on has a solid disc" for free, with no code branch of its own.
        if tpBackground in markS.Present then
          P.FillBackground(lay.MarkerRect, markS.Background, TyEffectiveCorners(markS));
        if TyBorderVisible(markS) then
          P.StrokeBorder(lay.MarkerRect, TyEffectiveCorners(markS), markS.BorderWidth,
            markS.BorderColor);
        // What the marker SAYS. Both glyphs are the painter's own marks, each with a
        // '--glyph-check' / '--glyph-close' icon-font override token, so a theme can swap
        // them for its icon font without a code change (v3/C5).
        case StepStatus(i) of
          sstFinish:
            TyDrawGlyph(P, ActiveController, lay.MarkerRect, tgCheck, markTxtS.TextColor, 2);
          sstError:
            // tgClose, not a mark of our own: an x IS the error mark on a step marker, and
            // inventing a TTyGlyphKind for it would collide with every other unit's.
            TyDrawGlyph(P, ActiveController, lay.MarkerRect, tgClose, markTxtS.TextColor, 2);
        else
          // sstProcess / sstWait: the step's 1-based number. Not ellipsised — a marker is a
          // fixed square and '1…' would say less than a clipped digit does.
          P.DrawText(lay.MarkerRect, IntToStr(i + 1), markTxtS.FontName,
            ResolveFontSize(markTxtS), markTxtS.FontWeight, markTxtS.TextColor,
            taCenter, tlCenter, False);
        end;
      end;

      // The title: left aligned under/beside its own marker and ellipsised, so a step
      // narrower than its title shows 'Config…' rather than a glyph sheared at the cell
      // edge or bleeding into the next step. No mnemonic parsing — a rail activates
      // nothing, so an '&' is literal text.
      if lay.TitleRect.Right > lay.TitleRect.Left then
      begin
        titleS := InheritText(S, TitleStyle(i));
        P.DrawText(lay.TitleRect, FItems[i], titleS.FontName, ResolveFontSize(titleS),
          titleS.FontWeight, titleS.TextColor, taLeftJustify, tlCenter, True);
      end;
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTySteps.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
