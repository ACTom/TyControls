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
    * RESIZED — grab that gripper and drag HORIZONTALLY to widen/narrow the band, honouring
                a per-band minimum / maximum width.

    The pointer's direction picks between the two (TyCoolDragMode), as it does in Delphi's and
    Lazarus's TCoolBar.

    NOT implemented: reordering bands WITHIN a row. That needs a child-index primitive and the
    LCL exposes only SetZOrder(TopMost), so a control cannot be placed at an arbitrary position
    in its parent's list. Row membership is the whole of the model for now.

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
    FVisible: Boolean;
    procedure SetControl(AValue: TControl);
    procedure SetText(const AValue: string);
    procedure SetBreak(AValue: Boolean);
    procedure SetWidth(AValue: Integer);
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
    property MinWidth: Integer read FMinWidth write FMinWidth default 0;
    property MaxWidth: Integer read FMaxWidth write FMaxWidth default 0;
    { Refuses a gripper RESIZE; the band can still be moved between rows. }
    property FixedSize: Boolean read FFixedSize write FFixedSize default False;
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
    FDragCtl: TControl;                // the band being resized
    FDragStartX: Integer;             // mouse X (device px) at grab
    FDragStartW: Integer;             // the band's logical width at grab
    function BandTextWidth(const AText: string; const AStyle: TTyStyleSet): Integer;
    procedure SetShowText(AValue: Boolean);
    procedure SetVertical(AValue: Boolean);
    procedure Changed;
    function EnsureBand(ACtl: TControl): TTyCoolBand;   // find, or create, this child's band
    procedure SetBands(AValue: TTyCoolBands);
    procedure BandsChanged;
    function BandAtPoint(AX, AY: Integer): TControl;   // the band whose gripper is under (X,Y)
  protected
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
begin
  if AValue < 0 then AValue := 0;
  if FWidth = AValue then Exit;
  FWidth := AValue;
  { A given width IS the hosted control's width -- the packer measures children, so the two
    must not drift apart. }
  if (FControl <> nil) and (AValue > 0) then FControl.Width := AValue;
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

function TTyCoolBar.BandMaxWidth(ACtl: TControl): Integer;
var b: TTyCoolBand;
begin
  b := FBandList.FindBand(ACtl);
  if b <> nil then Result := b.MaxWidth else Result := 0;
end;

function TTyCoolBar.BandRectFor(ACtl: TControl): TRect;
var
  gw: Integer;
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
  if FVertical then
  begin
    { Above the band on either reading -- up is not a reading direction, so a mirrored
      vertical rebar reverses which COLUMN a band is in and nothing about its gripper. }
    Result.Bottom := Result.Top;
    Dec(Result.Top, gw);
    if Result.Top < 0 then Result.Top := 0;
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
    if Result.Right > ClientWidth then Result.Right := ClientWidth;
  end
  else
  begin
    Result.Right := Result.Left;
    Dec(Result.Left, gw);
    if Result.Left < 0 then Result.Left := 0;
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
      COLUMN order, which is the axis AAvail is no longer describing. }
    Result := TyCoolBarPackVertical(ASizes, brks, leads, Height, ABandHeight, AGripperW, ASpacing,
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
  // Begin a gripper drag: remember the band + the starting width so MouseMove can apply
  // the clamped resize. (Reorder-vs-resize disambiguation by drag direction is a
  // real-machine refinement; the resize math is what we test.)
  FDragging := True;
  FDragCtl := hit;
  FDragStartX := X;
  FDragStartY := Y;
  FDragMode := cdNone;   // undecided until the pointer commits to an axis
  if GetBandWidth(hit) > 0 then
    FDragStartW := GetBandWidth(hit)
  else
    FDragStartW := hit.Width;
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
  end;

  case FDragMode of
    cdResize:
      begin
        if BandFixedSize(FDragCtl) then Exit;   // fixed: the drag simply does nothing
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
        minW := BandMinWidth(FDragCtl);
        maxW := BandMaxWidth(FDragCtl);
        newW := TyCoolBandResize(FDragStartW, dxLogical, minW, maxW);
        if newW <> GetBandWidth(FDragCtl) then
          SetBandWidth(FDragCtl, newW);
      end;
    cdMove:
      begin
        { Which row the pointer is over, versus which row the band is on. Moving DOWN gives the
          band a row of its own (Break); moving back UP returns it to the row above. That is the
          whole of the row model -- a band either starts a row or continues one.

          Reordering WITHIN a row is deliberately not attempted: it needs a child-index
          primitive, and the LCL exposes only SetZOrder(TopMost), so there is no way to place a
          control at an arbitrary position in its parent's list. }
        step := MulDiv(BandHeight, ppi, 96) + MulDiv(BandSpacing, ppi, 96);
        if step <= 0 then Exit;
        if FVertical then
        begin
          { Columns, not rows -- and mirrored they are counted from the right edge, matching
            the order TyCoolBarPackVertical laid them out in. Measured from the band's far
            side (Left + Width) so the two counts agree on which column a band occupies. }
          if IsRightToLeft then
          begin
            curRow := (ClientWidth - FDragCtl.Left - FDragCtl.Width) div step;
            wantRow := (ClientWidth - X) div step;
          end
          else
          begin
            curRow := FDragCtl.Left div step;
            wantRow := X div step;
          end;
        end
        else
        begin
          curRow := FDragCtl.Top div step;
          wantRow := Y div step;
        end;
        if wantRow < 0 then wantRow := 0;
        if wantRow > curRow then SetBandBreak(FDragCtl, True)
        else if wantRow < curRow then SetBandBreak(FDragCtl, False);
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
    if FDragCtl = AComponent then
    begin
      FDragging := False;
      FDragCtl := nil;
    end;
  end;
end;

initialization
  RegisterClass(TTyCoolBar);
end.
