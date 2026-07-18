unit tyControls.Breadcrumb;
{$mode objfpc}{$H+}
{ TTyBreadcrumb — a breadcrumb trail: the path you took to get here, drawn as a row of
  clickable ancestors separated by a themed mark, ending at where you are now.

  The gap it fills: the Shell controls (TTyShellTreeView / TTyShellListView) navigate a
  path but had nothing to SHOW one with. A hand-built row of TTyLinkLabel + TTyLabel is
  the workaround, and it has neither the "last crumb is not a link" grammar nor any
  answer for a path too long for its bar — the two things that make a breadcrumb a
  breadcrumb rather than a row of links.

  A GRAPHIC control (no handle), like its batch siblings TTyTag and TTyAlert. The case
  for a handle would be focus, and a breadcrumb does not want one: it is a SECONDARY
  affordance for a path the primary control (a tree, a list) already owns and already
  puts in the tab order, so putting the same destinations in the tab order twice makes
  the form worse, not better. It hosts no children and takes no keys. Painting straight
  onto the parent then gets the gaps outside any rounded crumb chip — the parent surface,
  or an image theme's photo — for free, with none of the corner-gap repair a windowed
  control needs, and a trail of crumbs costs zero HWNDs.

  Two typeKeys:
    'TyBreadcrumb'     — the bar. Its `color` is ALSO the separator's ink (the mark is
                         chrome, not a crumb — see RenderTo).
    'TyBreadcrumbItem' — one crumb, with :hover on the links and :selected on the current
                         one. That key's :selected rule is the whole visual grammar. }
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.Controller, tyControls.StyleModel;

const
  { Built-in logical-px defaults (96-PPI baseline) for this control's two metrics. A skin
    retunes each through its named theme metric below (the v3/C convention); these are only
    what a theme that sets neither falls back to. Every call site scales them to device px.
    The slot matches TyTagCloseSize (and through it TyTabCloseSize) so the separator reads
    as the same weight of glyph as a tag's x and a tab's x — the painter insets its own
    glyph padding inside the slot, so a 14px slot draws a ~6px chevron at 96 PPI. }
  TyBreadcrumbSepSize = 14;   // separator glyph slot, square
  TyBreadcrumbSepGap  = 2;    // gap on EACH side of the separator slot

  { The metric token each constant backs. Named constants rather than inline literals
    because three call sites (SlotsWith, CalculatePreferredSize, the tests) must agree on
    the spelling — a typo in one would silently strand it on the default and the geometry
    would drift from the measurement. }
  TyBreadcrumbSepSizeVar = '--breadcrumb-separator-size';
  TyBreadcrumbSepGapVar  = '--breadcrumb-separator-gap';

  { The collapsed-run crumb's text. A SYMBOL, not prose — the house precedent is
    TTyValueListEditor's own '…' affordance, which is likewise a bare literal: there is no
    language in which the horizontal ellipsis is spelled differently, so this earns no
    resourcestring. }
  TyBreadcrumbEllipsisText = '…';

  { The Items index the '…' crumb reports. It is not a destination: it stands for the run
    the overflow rule dropped, so it hit-tests as "nothing", never hovers and never fires
    OnCrumbClick. }
  TyBreadcrumbEllipsisIndex = -1;

type
  { Each crumb's FULL width (its text plus its own themed horizontal padding), device px,
    indexed like Items. Full widths rather than "content width + one shared padding pair"
    because every crumb resolves its OWN style: the current crumb is a different theme rule
    from a link and may well be padded — or weighted — differently. }
  TTyBreadcrumbWidths = array of Integer;

  { What the trail shows, left to right: Items indices, with TyBreadcrumbEllipsisIndex
    marking the '…' that stands for a dropped run. Always ends at the last crumb. }
  TTyBreadcrumbPlan = array of Integer;

  { One laid-out crumb, in DEVICE pixels relative to the control rect's top-left.
      ItemIndex — the Items index, or TyBreadcrumbEllipsisIndex for the '…' crumb.
      ItemRect  — the crumb's own rect: what a chip fills and what the hit-test measures.
                  Empty when the crumb did not fit at all.
      SepRect   — the separator slot AFTER this crumb. Empty on the last one, and on any
                  crumb whose separator ran off the band. }
  TTyBreadcrumbSlot = record
    ItemIndex: Integer;
    ItemRect: TRect;
    SepRect: TRect;
  end;
  TTyBreadcrumbSlots = array of TTyBreadcrumbSlot;

{ --- Pure rules / geometry (headless-testable; no control, no handle, no theme) -------- }

{ True when crumb AIndex is a LINK — somewhere you can navigate TO. The LAST crumb is where
  you already ARE: it is the current location, not a link, so it never hovers and never
  fires OnCrumbClick. That is the whole visual grammar of a breadcrumb, and it lives here
  as one rule so the paint, the hover and the click can never disagree about it.
  The '…' crumb (TyBreadcrumbEllipsisIndex) is not a link either — it is a mark, not a
  place. }
function TyBreadcrumbIsLink(AIndex, ACount: Integer): Boolean;

{ The state set crumb AIndex rests in — what 'TyBreadcrumbItem' is resolved with.
  The CURRENT crumb (the last one) carries tysSelected: the same resting state
  TTyButton.Down injects and TTySegmented's chosen segment carries, so one ':selected'
  theme rule styles all three. A DISABLED trail keeps :selected — greyed out, the trail
  must still say where you are, and it takes no hover.
  The '…' crumb (AIndex = TyBreadcrumbEllipsisIndex) comes out :normal, like a link: it
  stands for crumbs that were dropped, not for where you are, and dressing it as the
  current location would be a lie. }
function TyBreadcrumbItemStates(AIndex, ACount: Integer;
  AHovered, AEnabled: Boolean): TTyStateSet;

{ One crumb's full width: its text extent plus its own themed horizontal padding. What the
  control folds into every AWidths entry below. Device px. }
function TyBreadcrumbCrumbWidth(ATextWidth, APadLeft, APadRight: Integer): Integer;

{ How much horizontal room one separator costs, slot plus its air on BOTH sides. Device px.
  Exported because it is the trail's rhythm: every function here counts in these units. }
function TyBreadcrumbSepAdvance(ASepSize, ASepGap: Integer): Integer;

{ The room the WHOLE trail needs, band-local (i.e. NOT counting the bar's own padding):
  every crumb plus a separator between each adjacent pair. Device px. }
function TyBreadcrumbTrailWidth(const AWidths: array of Integer;
  ASepSize, ASepGap: Integer): Integer;

{ THE OVERFLOW RULE. Which crumbs a band AAvailWidth px wide shows, left to right.

  The rule is ELIDE THE MIDDLE, not clip and not scroll:
    * the LAST crumb is always kept — it is where you are, and a path bar that has lost
      that has said nothing at all;
    * the FIRST crumb is kept when it fits, because the root ('C:\', 'Home') is what says
      WHICH tree this path is in;
    * the ancestors nearest the end are added back while they fit — the near ones are the
      ones you actually navigate to;
    * whatever run that dropped collapses into a single '…' crumb, which is only ever
      emitted when it genuinely hides something.
  Right-aligning the tail instead was the alternative: it keeps the same crumbs visible but
  silently loses the root and leaves a ragged left edge that reads as a rendering bug rather
  than as "there is more path above".
  Degenerate ends: an empty Items gives an empty plan; a band too narrow even for '… › Here'
  gives just the last crumb, which the paint then ellipsises. Never an empty plan for a
  non-empty trail.

    AAvailWidth    — the band (the bar inset by its own padding), device px.
    AWidths        — each crumb's full width, device px.
    AEllipsisWidth — the '…' crumb's full width, device px.
    ASepSize/ASepGap — the separator slot and its air. }
function TyBreadcrumbVisiblePlan(AAvailWidth: Integer; const AWidths: array of Integer;
  AEllipsisWidth, ASepSize, ASepGap: Integer): TTyBreadcrumbPlan;

{ Lay APlan out in a control AClientWidth x AClientHeight px. One slot per plan entry —
  Length(Result) = Length(APlan) ALWAYS, so the paint can walk the two together — with an
  empty (never inverted) rect wherever the thing did not fit.
  The trail is LEFT-aligned in the band and every crumb spans the band's full height (the
  chip is the whole crumb, which is also its hit target); the separator slot is square and
  centred vertically in the band. Padding that eats the whole bar, or a zero size, leaves
  every rect empty. }
function TyBreadcrumbLayout(AClientWidth, AClientHeight: Integer;
  const APlan: TTyBreadcrumbPlan; const AWidths: array of Integer; AEllipsisWidth: Integer;
  APadLeft, APadTop, APadRight, APadBottom, ASepSize, ASepGap: Integer): TTyBreadcrumbSlots;

{ The Items index at device-px (X, Y), or -1 for none. The exact INVERSE of
  TyBreadcrumbLayout (it scans that function's own rects), so the crumb the user clicks is
  always the crumb that was painted there. The separators and the air between crumbs belong
  to no crumb; so does the '…', whose ItemIndex IS -1 — one rule gives "the gutter and the
  mark are not destinations" for free. }
function TyBreadcrumbIndexAt(const ASlots: TTyBreadcrumbSlots; X, Y: Integer): Integer;

{ The bar width that shows the whole trail — the inverse of the overflow rule: feed the
  result back in (minus the bar's padding, which is how SlotsWith derives the band) and
  TyBreadcrumbVisiblePlan returns every crumb. Device px; this is what AutoSize measures
  the width to. }
function TyBreadcrumbPreferredWidth(const AWidths: array of Integer;
  APadLeft, APadRight, ASepSize, ASepGap: Integer): Integer;

{ The bar height that shows a crumb whole: the bar's vertical padding around a band that
  clears BOTH a padded text line (AItemHeight) and a separator slot — the mark is centred
  in the band, so a band shorter than the slot would squash the glyph. Device px. }
function TyBreadcrumbPreferredHeight(APadTop, APadBottom, AItemHeight,
  ASepSize: Integer): Integer;

type
  { Fired when the user activates a crumb: press AND release both on the same LINK. AIndex
    is its Items index. Never fires for the last crumb (you are already there), for the '…'
    (it is a mark, not a place), or for the air between crumbs. }
  TTyBreadcrumbClickEvent = procedure(Sender: TObject; AIndex: Integer) of object;

  { The path you took, as a row of clickable ancestors ending at where you are.

    Colour/size variants are plain StyleClass ('TyBreadcrumb.compact', …) — the control
    declares no variant enum of its own, so a theme may define as many as it likes without a
    code change, and the crumbs' own key is resolved with the SAME StyleClass so
    'TyBreadcrumbItem.compact' follows the bar. }
  TTyBreadcrumb = class(TTyGraphicControl)
  private
    FItems: TStrings;
    FHoverIndex: Integer;   // the LINK under the pointer; -1 = none
    FPressIndex: Integer;   // the LINK this press started on; -1 = none
    FOnCrumbClick: TTyBreadcrumbClickEvent;
    procedure SetItems(AValue: TStrings);
    procedure ItemsChanged(Sender: TObject);
    { TTyGraphicControl has no ResolveFontSize helper (that lives on TTyCustomControl);
      mirror TTyLabel/TTyTag/TTyAlert and resolve it locally. }
    function ResolveFontSize(const AStyle: TTyStyleSet): Integer;
    { True when the pointer is on THIS crumb. The `>= 0` guard is not decoration: the '…'
      crumb's ItemIndex is -1 and so is "no hover", so a bare equality test would light the
      mark up whenever the pointer was nowhere near it. }
    function SlotHovered(AItemIndex: Integer): Boolean;
    { The link at device-px (X, Y), or -1 — the click/hover gate. The current crumb and the
      '…' answer -1 here even though the pointer IS on them. }
    function LinkAt(X, Y: Integer): Integer;
    { The text a plan entry draws: an Items line, or the '…' mark. }
    function SlotText(AItemIndex: Integer): string;
    { The tallest padded text line any crumb style asks for, accrued across the crumbs (they
      may resolve different rules). Device px at APainter's PPI. }
    procedure AccrueItemHeight(APainter: TTyPainter; const AStyle: TTyStyleSet;
      var AHeight: Integer);
    { Every crumb's full width, the '…' crumb's, and the band height they all need. Device
      px at APainter's PPI. }
    procedure MeasureWidths(APainter: TTyPainter; out AWidths: TTyBreadcrumbWidths;
      out AEllipsisWidth, AItemHeight: Integer);
    { The trail laid out in an AWidth x AHeight rect, fed from the resolved theme. }
    function SlotsWith(APainter: TTyPainter; const ABarStyle: TTyStyleSet;
      AWidth, AHeight: Integer): TTyBreadcrumbSlots;
    { The tokens a crumb draws its LABEL with: its own where TyBreadcrumbItem defines them,
      the BAR's otherwise. Background/border are deliberately NOT inherited this way (see
      RenderTo): a crumb with no background of its own must draw no chip. }
    function ItemTextStyle(const ABar, ACrumb: TTyStyleSet): TTyStyleSet;
  protected
    function GetStyleTypeKey: string; override;
    { The resolved 'TyBreadcrumbItem' style for one crumb: the BAR's StyleClass (so a
      variant reaches both keys) and the state of THAT crumb. }
    function SlotStyle(AItemIndex: Integer; AHovered: Boolean): TTyStyleSet;
    { SlotsWith on a canvas-less painter. AWidth/AHeight are device px (RenderTo passes its
      own rect; the hit-test passes the client size), so nothing here reads Width behind the
      caller's back. }
    function SlotsFor(AWidth, AHeight, APPI: Integer): TTyBreadcrumbSlots;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { How many crumbs the trail holds (elided ones included — Items is the PATH, the plan is
      only what currently fits). }
    function Count: Integer;
    { The trail as it is currently laid out, DEVICE px and (0,0)-local: the exact rects the
      paint filled and the hit-test measures against. Exposed for tests. }
    function TyCrumbSlots: TTyBreadcrumbSlots;
    { What the trail currently SHOWS: Items indices left to right, TyBreadcrumbEllipsisIndex
      for the '…'. This is the overflow rule's live answer for the bar's current width. }
    function TyVisiblePlan: TTyBreadcrumbPlan;
    { Crumb AIndex's rect in DEVICE px, (0,0)-local; empty when it is out of range or the
      overflow rule elided it away. }
    function TyCrumbRect(AIndex: Integer): TRect;
    { The Items index at client device (X, Y), or -1 (separators, air and the '…' included). }
    function TyCrumbAt(X, Y: Integer): Integer;
  published
    { The trail, root first and CURRENT LOCATION LAST — one crumb per line. Drawn with the
      resolved TyBreadcrumbItem style (NOT the LCL Font.*) and ellipsised when a crumb is
      clipped; never wrapped. No mnemonic parsing — a crumb has no Alt+key path, so an '&'
      is literal text. }
    property Items: TStrings read FItems write SetItems;
    { Fires when the user activates a crumb — see TTyBreadcrumbClickEvent. This is the
      navigation event: OnClick below fires for ANY click on the bar, this one only for a
      committed click on a place you can actually go. }
    property OnCrumbClick: TTyBreadcrumbClickEvent read FOnCrumbClick write FOnCrumbClick;
    { With AutoSize the bar hugs the whole trail (so the overflow rule never fires) and one
      padded text line; off, it keeps the bounds it was given and the overflow rule elides
      the middle to fit. An alTop/alClient bar therefore keeps its host's width and only
      hugs the height, which is the usual way to place one. }
    property AutoSize;
    property Align;
    property Anchors;
    property Enabled;
    property Font;
    property StyleClass;
    property StyleOverride;
    property Controller;
    { Any click anywhere on the bar, the current crumb and the gutter included. OnCrumbClick
      is the one that says a DESTINATION was chosen. }
    property OnClick;
  end;

implementation

{ --- pure rules / geometry ------------------------------------------------------------ }

function TyBreadcrumbIsLink(AIndex, ACount: Integer): Boolean;
begin
  Result := (ACount > 0) and (AIndex >= 0) and (AIndex < ACount - 1);
end;

function TyBreadcrumbItemStates(AIndex, ACount: Integer;
  AHovered, AEnabled: Boolean): TTyStateSet;
begin
  Result := [];
  // Where you ARE. The `ACount > 0` guard also keeps TyBreadcrumbEllipsisIndex (-1) out of
  // this branch when the trail is empty (-1 = 0-1 would otherwise match).
  if (ACount > 0) and (AIndex = ACount - 1) then Include(Result, tysSelected);
  if not AEnabled then
  begin
    { Disabled KEEPS :selected — unlike TTyButton.Down, which drops it. A greyed-out trail
      must still show WHERE you are: losing the current-crumb plate would make it read as
      "this path is nowhere" rather than "you cannot navigate from here". The cascade does
      the rest — ResolveLayer applies :selected first as the resting layer and :disabled
      LAST at the highest precedence, so the plate survives while the disabled ink wins over
      it. Hover is deliberately absent: a disabled control takes none. }
    Include(Result, tysDisabled);
    Exit;
  end;
  if AHovered then Include(Result, tysHover);
  if Result = [] then Include(Result, tysNormal);
end;

function TyBreadcrumbCrumbWidth(ATextWidth, APadLeft, APadRight: Integer): Integer;
begin
  if ATextWidth < 0 then ATextWidth := 0;
  if APadLeft < 0 then APadLeft := 0;
  if APadRight < 0 then APadRight := 0;
  Result := APadLeft + ATextWidth + APadRight;
end;

function TyBreadcrumbSepAdvance(ASepSize, ASepGap: Integer): Integer;
begin
  if ASepSize < 0 then ASepSize := 0;
  if ASepGap < 0 then ASepGap := 0;
  // Air on BOTH sides of the slot: the mark sits in its own space, so a theme tunes the
  // trail's rhythm with one token instead of re-padding every crumb.
  Result := ASepGap + ASepSize + ASepGap;
end;

function TyBreadcrumbTrailWidth(const AWidths: array of Integer;
  ASepSize, ASepGap: Integer): Integer;
var
  i: Integer;
begin
  Result := 0;
  if Length(AWidths) = 0 then Exit;
  for i := 0 to High(AWidths) do
    if AWidths[i] > 0 then Inc(Result, AWidths[i]);
  // One separator BETWEEN each adjacent pair: n crumbs, n-1 marks.
  Inc(Result, High(AWidths) * TyBreadcrumbSepAdvance(ASepSize, ASepGap));
end;

function TyBreadcrumbVisiblePlan(AAvailWidth: Integer; const AWidths: array of Integer;
  AEllipsisWidth, ASepSize, ASepGap: Integer): TTyBreadcrumbPlan;
var
  w: TTyBreadcrumbWidths;
  n, i, k, sepAdv, ellipW, headW, used, tailStart, lo: Integer;
  withRoot: Boolean;
begin
  Result := nil;
  n := Length(AWidths);
  if n = 0 then Exit;
  // Clamp every negative input once, here, so the arithmetic below reads straight.
  SetLength(w, n);
  for i := 0 to n - 1 do
  begin
    w[i] := AWidths[i];
    if w[i] < 0 then w[i] := 0;
  end;
  ellipW := AEllipsisWidth;
  if ellipW < 0 then ellipW := 0;
  sepAdv := TyBreadcrumbSepAdvance(ASepSize, ASepGap);

  if TyBreadcrumbTrailWidth(w, ASepSize, ASepGap) <= AAvailWidth then
  begin
    // It all fits: no mark, no decisions, the whole path.
    SetLength(Result, n);
    for i := 0 to n - 1 do Result[i] := i;
    Exit;
  end;

  // It does not fit, so the trail must be elided. Decide the HEAD first.
  // With the root: '[0] › … › … › [n-1]'. Only worth considering from 3 crumbs up — with 2
  // there is nothing between the root and the end for a '…' to stand for.
  withRoot := False;
  headW := 0;
  if n >= 3 then
  begin
    headW := w[0] + sepAdv + ellipW + sepAdv;
    withRoot := headW + w[n - 1] <= AAvailWidth;
  end;
  if not withRoot then
  begin
    // Without it: '… › … › [n-1]'. The root itself is now part of what the mark hides.
    headW := ellipW + sepAdv;
    if headW + w[n - 1] > AAvailWidth then
    begin
      // The floor: not even '… › Here' fits. Show where you ARE and let the paint ellipsise
      // it — a bar showing only '…' would have said nothing at all.
      SetLength(Result, 1);
      Result[0] := n - 1;
      Exit;
    end;
  end;

  { Grow the tail back from the last-but-one while each ancestor still fits: the NEAR
    ancestors are the ones you actually navigate to, so they are the ones worth the room.
    `lo` is where the loop must stop for the '…' to stay honest — it has to hide at least
    crumb 1 when the root is shown, at least crumb 0 when it is not. Reaching `lo` is in
    fact unreachable arithmetic (a tail that long, PLUS the mark, is wider than the whole
    trail, which we already know does not fit) — the bound is what makes that a property of
    the code rather than of a proof. }
  used := headW + w[n - 1];
  tailStart := n - 1;
  if withRoot then lo := 2 else lo := 1;
  for i := n - 2 downto lo do
  begin
    if used + w[i] + sepAdv > AAvailWidth then Break;
    Inc(used, w[i] + sepAdv);
    tailStart := i;
  end;

  k := n - tailStart + 1;               // the tail, plus the '…'
  if withRoot then Inc(k);
  SetLength(Result, k);
  k := 0;
  if withRoot then
  begin
    Result[0] := 0;
    k := 1;
  end;
  Result[k] := TyBreadcrumbEllipsisIndex;
  Inc(k);
  for i := tailStart to n - 1 do
  begin
    Result[k] := i;
    Inc(k);
  end;
end;

{ The width the crumb a plan entry stands for asks for. TyBreadcrumbEllipsisIndex — and any
  index a caller made up — is the '…' crumb: the plan is our own function's output, so this
  is a floor under a malformed one rather than a branch anybody takes. }
function PlanEntryWidth(AIndex: Integer; const AWidths: array of Integer;
  AEllipsisWidth: Integer): Integer;
begin
  if (AIndex >= 0) and (AIndex <= High(AWidths)) then
    Result := AWidths[AIndex]
  else
    Result := AEllipsisWidth;
  if Result < 0 then Result := 0;
end;

function TyBreadcrumbLayout(AClientWidth, AClientHeight: Integer;
  const APlan: TTyBreadcrumbPlan; const AWidths: array of Integer; AEllipsisWidth: Integer;
  APadLeft, APadTop, APadRight, APadBottom, ASepSize, ASepGap: Integer): TTyBreadcrumbSlots;
var
  bandL, bandR, bandT, bandB: Integer;
  i, x, cw, crumbR, sepL, sepR, sepT, sepB: Integer;
begin
  // One slot per plan entry, ALWAYS — the paint walks the two together, and a slot whose
  // thing did not fit says so with an empty rect rather than by not being there.
  Result := nil;   // FPC 3.2 does not count SetLength as initialising a managed result
  SetLength(Result, Length(APlan));
  for i := 0 to High(Result) do
  begin
    Result[i].ItemIndex := APlan[i];
    Result[i].ItemRect := Rect(0, 0, 0, 0);
    Result[i].SepRect := Rect(0, 0, 0, 0);
  end;
  if Length(APlan) = 0 then Exit;
  if (AClientWidth <= 0) or (AClientHeight <= 0) then Exit;
  if APadLeft < 0 then APadLeft := 0;
  if APadTop < 0 then APadTop := 0;
  if APadRight < 0 then APadRight := 0;
  if APadBottom < 0 then APadBottom := 0;
  if ASepSize < 0 then ASepSize := 0;
  if ASepGap < 0 then ASepGap := 0;

  // The band: the bar inset by its themed padding on all four sides. Padding that eats the
  // whole bar leaves nothing to lay out (every rect stays empty, never inverted).
  bandL := APadLeft;
  bandR := AClientWidth - APadRight;
  bandT := APadTop;
  bandB := AClientHeight - APadBottom;
  if (bandR <= bandL) or (bandB <= bandT) then Exit;

  // The separator's vertical band: square, centred in the padded band, floored at the top
  // and squashed at the bottom rather than overflowing (TyTagLayout's rule for its own
  // slot). It is the same for every mark, so it is computed once.
  sepT := bandT + (bandB - bandT - ASepSize) div 2;
  if sepT < bandT then sepT := bandT;
  sepB := sepT + ASepSize;
  if sepB > bandB then sepB := bandB;

  x := bandL;   // the trail is LEFT-aligned: the root is where the eye starts
  for i := 0 to High(APlan) do
  begin
    cw := PlanEntryWidth(APlan[i], AWidths, AEllipsisWidth);
    if x < bandR then
    begin
      crumbR := x + cw;
      if crumbR > bandR then crumbR := bandR;   // the band clips it; DrawText ellipsises
      // A crumb spans the band's FULL height: the chip IS the whole crumb, and so is its
      // hit target — a trail whose links were only as tall as their glyphs would be a row
      // of pixel-hunting.
      Result[i].ItemRect := Rect(x, bandT, crumbR, bandB);
    end;
    Inc(x, cw);
    if i = High(APlan) then Break;   // no mark after the last crumb

    sepL := x + ASepGap;
    sepR := sepL + ASepSize;
    if (sepL < bandR) and (sepB > sepT) then
    begin
      if sepR > bandR then sepR := bandR;
      Result[i].SepRect := Rect(sepL, sepT, sepR, sepB);
    end;
    x := sepL + ASepSize + ASepGap;   // NOT sepR: a clamped mark must not shorten the pitch
  end;
end;

function TyBreadcrumbIndexAt(const ASlots: TTyBreadcrumbSlots; X, Y: Integer): Integer;
var
  i: Integer;
  R: TRect;
begin
  Result := -1;
  for i := 0 to High(ASlots) do
  begin
    R := ASlots[i].ItemRect;
    if (R.Right > R.Left) and (R.Bottom > R.Top) and (X >= R.Left) and (X < R.Right)
       and (Y >= R.Top) and (Y < R.Bottom) then
      // The '…' slot's own ItemIndex is -1, so it answers "nothing" through this one line.
      Exit(ASlots[i].ItemIndex);
  end;
end;

function TyBreadcrumbPreferredWidth(const AWidths: array of Integer;
  APadLeft, APadRight, ASepSize, ASepGap: Integer): Integer;
begin
  if APadLeft < 0 then APadLeft := 0;
  if APadRight < 0 then APadRight := 0;
  // Deliberately NOT floored at 1: the exact inverse is the contract (subtract the padding
  // again and TyBreadcrumbVisiblePlan returns every crumb). The control floors its own
  // CalculatePreferredSize, where the LCL needs it.
  Result := APadLeft + TyBreadcrumbTrailWidth(AWidths, ASepSize, ASepGap) + APadRight;
end;

function TyBreadcrumbPreferredHeight(APadTop, APadBottom, AItemHeight,
  ASepSize: Integer): Integer;
var
  bandH: Integer;
begin
  if APadTop < 0 then APadTop := 0;
  if APadBottom < 0 then APadBottom := 0;
  bandH := AItemHeight;
  if bandH < 0 then bandH := 0;
  // The mark is centred in the BAND, so a band shorter than its slot would have
  // TyBreadcrumbLayout squash the glyph. Clear the bare slot, exactly as TTyTag floors its
  // own height against its x.
  if ASepSize > bandH then bandH := ASepSize;
  Result := APadTop + bandH + APadBottom;
end;

{ --- TTyBreadcrumb -------------------------------------------------------------------- }

constructor TTyBreadcrumb.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TStringList.Create;
  TStringList(FItems).OnChange := @ItemsChanged;
  FHoverIndex := -1;
  FPressIndex := -1;
  // A drop size for the designer: wide enough for a few crumbs, one line tall.
  Width := 300;
  Height := 24;
end;

destructor TTyBreadcrumb.Destroy;
begin
  // Drop the change hook before freeing: the list fires OnChange as it clears.
  TStringList(FItems).OnChange := nil;
  FItems.Free;
  inherited Destroy;
end;

function TTyBreadcrumb.GetStyleTypeKey: string;
begin
  Result := 'TyBreadcrumb';
end;

function TTyBreadcrumb.ResolveFontSize(const AStyle: TTyStyleSet): Integer;
begin
  Result := TyResolveFontSize(AStyle, ParentFont, Font.Size, ActiveController);
end;

function TTyBreadcrumb.Count: Integer;
begin
  Result := FItems.Count;
end;

{ --- items ---------------------------------------------------------------------------- }

procedure TTyBreadcrumb.SetItems(AValue: TStrings);
begin
  FItems.Assign(AValue);   // fires ItemsChanged
end;

procedure TTyBreadcrumb.ItemsChanged(Sender: TObject);
begin
  // A list edit can strand the live mouse state on a crumb that is gone — or, worse, on one
  // that is now the LAST crumb and therefore no longer a link, which would leave the current
  // location lit like a link and fire a navigation to where you already are on release.
  if not TyBreadcrumbIsLink(FHoverIndex, FItems.Count) then FHoverIndex := -1;
  if not TyBreadcrumbIsLink(FPressIndex, FItems.Count) then FPressIndex := -1;
  // A crumb more or fewer changes the width an auto-sized bar needs.
  if AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
  if not (csLoading in ComponentState) then Invalidate;
end;

{ --- style ---------------------------------------------------------------------------- }

function TTyBreadcrumb.SlotStyle(AItemIndex: Integer; AHovered: Boolean): TTyStyleSet;
begin
  Result := ActiveController.Model.ResolveStyle('TyBreadcrumbItem', StyleClass,
    TyBreadcrumbItemStates(AItemIndex, FItems.Count, AHovered, Enabled));
end;

function TTyBreadcrumb.SlotHovered(AItemIndex: Integer): Boolean;
begin
  Result := (FHoverIndex >= 0) and (AItemIndex = FHoverIndex);
end;

function TTyBreadcrumb.SlotText(AItemIndex: Integer): string;
begin
  if (AItemIndex >= 0) and (AItemIndex < FItems.Count) then
    Result := FItems[AItemIndex]
  else
    Result := TyBreadcrumbEllipsisText;
end;

function TTyBreadcrumb.ItemTextStyle(const ABar, ACrumb: TTyStyleSet): TTyStyleSet;
{ The label's ink and font: the crumb's own where the theme sets them, the bar's otherwise.
  This is the house degradation rule (no colour => inherit the parent's ink) extended to the
  font by the same logic — a theme that styles only TyBreadcrumb must still get legible,
  correctly-sized crumbs, and NEVER a hard-coded colour. }
begin
  Result := ACrumb;
  if not (tpTextColor in ACrumb.Present) then
  begin
    Result.TextColor := ABar.TextColor;
    if tpTextColor in ABar.Present then Include(Result.Present, tpTextColor);
  end;
  if not (tpFontName in ACrumb.Present) then
  begin
    Result.FontName := ABar.FontName;
    if tpFontName in ABar.Present then Include(Result.Present, tpFontName);
  end;
  if not (tpFontSize in ACrumb.Present) then
  begin
    Result.FontSize := ABar.FontSize;
    if tpFontSize in ABar.Present then Include(Result.Present, tpFontSize);
  end;
  if not (tpFontWeight in ACrumb.Present) then
  begin
    Result.FontWeight := ABar.FontWeight;
    if tpFontWeight in ABar.Present then Include(Result.Present, tpFontWeight);
  end;
end;

{ --- measurement ---------------------------------------------------------------------- }

procedure TTyBreadcrumb.AccrueItemHeight(APainter: TTyPainter; const AStyle: TTyStyleSet;
  var AHeight: Integer);
var
  h: Integer;
begin
  // A stable reference glyph: a blank crumb still sizes the bar to a line.
  h := APainter.MeasureText('Ag', AStyle.FontName, ResolveFontSize(AStyle),
    AStyle.FontWeight).cy;
  if h < 1 then h := 1;
  Inc(h, APainter.Scale(AStyle.Padding.Top) + APainter.Scale(AStyle.Padding.Bottom));
  if h > AHeight then AHeight := h;
end;

procedure TTyBreadcrumb.MeasureWidths(APainter: TTyPainter;
  out AWidths: TTyBreadcrumbWidths; out AEllipsisWidth, AItemHeight: Integer);
{ Measured with the PAINTER, not an LCL canvas: the crumbs are drawn with BGRA text metrics,
  and only the same measurer reproduces the extent those glyphs actually render at.
  Each crumb is measured in ITS OWN resting style — the current crumb is a different theme
  rule from a link, and a theme that bolds it would have it clipped by a width measured in
  the link's font. HOVER is excluded on purpose: a crumb that grew under the pointer would
  shove the whole trail sideways, and the overflow rule would flap as the mouse moved. }
var
  crumbS: TTyStyleSet;   // not 'itemS'/'itemStyle': Pascal is case-insensitive, so those
                         // would collide with the Items property.
  i: Integer;
begin
  SetLength(AWidths, FItems.Count);
  AItemHeight := 0;
  for i := 0 to FItems.Count - 1 do
  begin
    crumbS := SlotStyle(i, False);
    AWidths[i] := TyBreadcrumbCrumbWidth(
      APainter.MeasureText(FItems[i], crumbS.FontName, ResolveFontSize(crumbS),
        crumbS.FontWeight).cx,
      APainter.Scale(crumbS.Padding.Left), APainter.Scale(crumbS.Padding.Right));
    AccrueItemHeight(APainter, crumbS, AItemHeight);
  end;
  // The '…' is measured even when the whole trail fits: the overflow rule has to know what
  // the mark would COST before it can decide whether using it is worth the room.
  crumbS := SlotStyle(TyBreadcrumbEllipsisIndex, False);
  AEllipsisWidth := TyBreadcrumbCrumbWidth(
    APainter.MeasureText(TyBreadcrumbEllipsisText, crumbS.FontName, ResolveFontSize(crumbS),
      crumbS.FontWeight).cx,
    APainter.Scale(crumbS.Padding.Left), APainter.Scale(crumbS.Padding.Right));
  AccrueItemHeight(APainter, crumbS, AItemHeight);
end;

function TTyBreadcrumb.SlotsWith(APainter: TTyPainter; const ABarStyle: TTyStyleSet;
  AWidth, AHeight: Integer): TTyBreadcrumbSlots;
var
  widths: TTyBreadcrumbWidths;
  plan: TTyBreadcrumbPlan;
  ellipW, itemH, sepSz, sepGp, padL, padT, padR, padB: Integer;
begin
  MeasureWidths(APainter, widths, ellipW, itemH);
  // APainter.Scale is the same logical->device conversion the painter applies to every
  // themed value it draws, so the rects the hit-test measures are the rects the paint drew.
  sepSz := APainter.Scale(ActiveController.Metric(TyBreadcrumbSepSizeVar, TyBreadcrumbSepSize));
  sepGp := APainter.Scale(ActiveController.Metric(TyBreadcrumbSepGapVar, TyBreadcrumbSepGap));
  padL := APainter.Scale(ABarStyle.Padding.Left);
  padT := APainter.Scale(ABarStyle.Padding.Top);
  padR := APainter.Scale(ABarStyle.Padding.Right);
  padB := APainter.Scale(ABarStyle.Padding.Bottom);
  // The band the overflow rule gets to spend is the bar minus its OWN padding — the same
  // band TyBreadcrumbLayout then lays the answer out in.
  plan := TyBreadcrumbVisiblePlan(AWidth - padL - padR, widths, ellipW, sepSz, sepGp);
  Result := TyBreadcrumbLayout(AWidth, AHeight, plan, widths, ellipW,
    padL, padT, padR, padB, sepSz, sepGp);
end;

function TTyBreadcrumb.SlotsFor(AWidth, AHeight, APPI: Integer): TTyBreadcrumbSlots;
{ A CANVAS-LESS painter — the TTyBadge / TTyAlert idiom: BeginPaint(nil, ...) builds only the
  painter's internal bitmap and EndPaint frees it WITHOUT blitting, so this is safe outside a
  paint cycle and leaks nothing. }
var
  P: TTyPainter;
begin
  if APPI <= 0 then APPI := 96;
  P := TTyPainter.Create;
  try
    P.BeginPaint(nil, Rect(0, 0, 1, 1), APPI);   // 1x1: nothing is drawn, only measured
    Result := SlotsWith(P, CurrentStyle, AWidth, AHeight);
    P.EndPaint;   // nil canvas -> no blit, just frees the measure bitmap
  finally
    P.Free;
  end;
end;

function TTyBreadcrumb.TyCrumbSlots: TTyBreadcrumbSlots;
begin
  Result := SlotsFor(ClientWidth, ClientHeight, Font.PixelsPerInch);
end;

function TTyBreadcrumb.TyVisiblePlan: TTyBreadcrumbPlan;
var
  slots: TTyBreadcrumbSlots;
  i: Integer;
begin
  // Read back off the slots rather than re-deciding: TyBreadcrumbLayout keeps one slot per
  // plan entry, so this IS the plan and the two can never drift.
  Result := nil;   // FPC 3.2 does not count SetLength as initialising a managed result
  slots := TyCrumbSlots;
  SetLength(Result, Length(slots));
  for i := 0 to High(slots) do
    Result[i] := slots[i].ItemIndex;
end;

function TTyBreadcrumb.TyCrumbRect(AIndex: Integer): TRect;
var
  slots: TTyBreadcrumbSlots;
  i: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if AIndex < 0 then Exit;   // the '…' is a mark, not an Items crumb
  slots := TyCrumbSlots;
  for i := 0 to High(slots) do
    if slots[i].ItemIndex = AIndex then
      Exit(slots[i].ItemRect);
  // Not in the plan: the overflow rule elided it. An empty rect, not an exception — an
  // elided crumb genuinely has nowhere to be.
end;

function TTyBreadcrumb.TyCrumbAt(X, Y: Integer): Integer;
begin
  Result := TyBreadcrumbIndexAt(TyCrumbSlots, X, Y);
end;

function TTyBreadcrumb.LinkAt(X, Y: Integer): Integer;
begin
  Result := -1;
  // Match the paint exactly: a background-less bar draws NOTHING (RenderTo exits early on the
  // same test), so there is nothing to click. Without this gate a click fired OnCrumbClick for a
  // crumb the user could not see — paint and input disagreeing about whether the control exists.
  if not (tpBackground in CurrentStyle.Present) then Exit;
  Result := TyCrumbAt(X, Y);
  if not TyBreadcrumbIsLink(Result, FItems.Count) then Result := -1;
end;

procedure TTyBreadcrumb.CalculatePreferredSize(var PreferredWidth,
  PreferredHeight: Integer; WithThemeSpace: Boolean);
var
  barS: TTyStyleSet;
  P: TTyPainter;
  widths: TTyBreadcrumbWidths;
  ppi, ellipW, itemH: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  barS := CurrentStyle;
  P := TTyPainter.Create;
  try
    P.BeginPaint(nil, Rect(0, 0, 1, 1), ppi);
    MeasureWidths(P, widths, ellipW, itemH);
    P.EndPaint;
  finally
    P.Free;
  end;
  PreferredWidth := TyBreadcrumbPreferredWidth(widths,
    MulDiv(barS.Padding.Left, ppi, 96), MulDiv(barS.Padding.Right, ppi, 96),
    MulDiv(ActiveController.Metric(TyBreadcrumbSepSizeVar, TyBreadcrumbSepSize), ppi, 96),
    MulDiv(ActiveController.Metric(TyBreadcrumbSepGapVar, TyBreadcrumbSepGap), ppi, 96));
  PreferredHeight := TyBreadcrumbPreferredHeight(
    MulDiv(barS.Padding.Top, ppi, 96), MulDiv(barS.Padding.Bottom, ppi, 96), itemH,
    MulDiv(ActiveController.Metric(TyBreadcrumbSepSizeVar, TyBreadcrumbSepSize), ppi, 96));
  if PreferredWidth < 1 then PreferredWidth := 1;
  if PreferredHeight < 1 then PreferredHeight := 1;
end;

{ --- input ---------------------------------------------------------------------------- }

procedure TTyBreadcrumb.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  // Remember WHICH link the gesture started on, not merely that it started: releasing on a
  // different crumb must not navigate to that one (see MouseUp).
  FPressIndex := LinkAt(X, Y);
end;

procedure TTyBreadcrumb.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  wasIdx: Integer;
begin
  wasIdx := FPressIndex;
  FPressIndex := -1;
  inherited MouseUp(Button, Shift, X, Y);
  // Press AND release both on the SAME link commit the navigation; dragging off it (onto
  // another crumb, onto the current one, or off the bar) cancels the whole gesture like any
  // push button. OnClick is NOT suppressed for this — unlike a tag's x, a crumb is not a
  // second widget hiding inside the first, it IS the bar, so "the user clicked the bar" is
  // simply also true.
  if (Button = mbLeft) and (wasIdx >= 0) and (LinkAt(X, Y) = wasIdx)
     and Assigned(FOnCrumbClick) then
    FOnCrumbClick(Self, wasIdx);
end;

procedure TTyBreadcrumb.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  h: Integer;
begin
  if not Enabled then Exit;
  inherited MouseMove(Shift, X, Y);
  // Only LINKS light up. The current crumb is where you are — a hover chip on it would
  // promise a navigation that cannot happen — and the '…' is a mark, not a place.
  h := LinkAt(X, Y);
  if h <> FHoverIndex then
  begin
    FHoverIndex := h;
    Invalidate;
  end;
end;

procedure TTyBreadcrumb.MouseLeave;
begin
  inherited MouseLeave;   // clears the bar's own hover
  if FHoverIndex <> -1 then
  begin
    FHoverIndex := -1;
    Invalidate;
  end;
end;

{ --- painting ------------------------------------------------------------------------- }

procedure TTyBreadcrumb.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, crumbS, txtS: TTyStyleSet;
  R, txtR: TRect;
  slots: TTyBreadcrumbSlots;
  i: Integer;
begin
  P := TTyPainter.Create;
  try
    // A (0,0)-local rect: the painter builds a (W x H) bitmap and blits it at
    // ARect.Left/Top, so a non-zero ARect origin would shift the whole trail.
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    // The bar: background + border + shadow + opacity, all from the resolved TyBreadcrumb
    // style. A breadcrumb usually wants no fill of its own — that is `background:
    // transparent`, which IS a defined background, not an absent one.
    DrawFrame(P, R, S);
    if not (tpBackground in S.Present) then
    begin
      // No TyBreadcrumb rule at all -> draw nothing. Degrade rather than invent a look.
      P.EndPaint;
      Exit;
    end;

    slots := SlotsWith(P, S, R.Right - R.Left, R.Bottom - R.Top);
    for i := 0 to High(slots) do
    begin
      if slots[i].ItemRect.Right > slots[i].ItemRect.Left then
      begin
        crumbS := SlotStyle(slots[i].ItemIndex, SlotHovered(slots[i].ItemIndex));

        // The chip. An undefined TyBreadcrumbItem key leaves no background -> no chips, and
        // the labels below still draw: a theme that fills only :hover gets the classic
        // "the link under the pointer lights up" for free, with no code branch of its own,
        // and one that fills only :selected gets the current-location plate the same way.
        if tpBackground in crumbS.Present then
          P.FillBackground(slots[i].ItemRect, crumbS.Background, TyEffectiveCorners(crumbS));
        if TyBorderVisible(crumbS) then
          P.StrokeBorder(slots[i].ItemRect, TyEffectiveCorners(crumbS), crumbS.BorderWidth,
            crumbS.BorderColor);

        txtS := ItemTextStyle(S, crumbS);
        txtR := Rect(slots[i].ItemRect.Left + P.Scale(crumbS.Padding.Left),
                     slots[i].ItemRect.Top + P.Scale(crumbS.Padding.Top),
                     slots[i].ItemRect.Right - P.Scale(crumbS.Padding.Right),
                     slots[i].ItemRect.Bottom - P.Scale(crumbS.Padding.Bottom));
        // LEFT-aligned, not centred: the crumb's rect is its exact measured width, so the
        // two agree everywhere EXCEPT on a crumb the band clipped — and there, left is what
        // shows 'Docume…' rather than the middle of the word. Ellipsised, never sheared at
        // the clip edge. No mnemonic parsing (see the Items property).
        if (txtR.Right > txtR.Left) and (txtR.Bottom > txtR.Top) then
          P.DrawText(txtR, SlotText(slots[i].ItemIndex), txtS.FontName,
            ResolveFontSize(txtS), txtS.FontWeight, txtS.TextColor,
            taLeftJustify, tlCenter, True);
      end;

      // The separator takes the BAR's ink, and that is why it needs no typeKey of its own:
      // the mark is the bar's chrome, not a crumb, so `TyBreadcrumb { color: var(--muted) }`
      // tints every separator while `TyBreadcrumbItem { color: var(--accent) }` colours the
      // links — two keys already say everything a third one could. A bar with no `color`
      // therefore draws no marks and no labels: the same degradation, one rule.
      // v3/C5: the mark is theme-overridable with an icon-font codepoint
      // (--glyph-chevron-right), so a skin can swap the chevron for a '/' without code.
      if slots[i].SepRect.Right > slots[i].SepRect.Left then
        TyDrawGlyph(P, ActiveController, slots[i].SepRect, tgChevronRight, S.TextColor, 1);
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyBreadcrumb.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
