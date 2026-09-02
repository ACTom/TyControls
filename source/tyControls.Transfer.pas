unit tyControls.Transfer;
{$mode objfpc}{$H+}
{ TTyTransfer — a two-list transfer (shuttle) box: a SOURCE pane on the left, a TARGET
  pane on the right, and a rail of arrow buttons between them that moves rows across.

  The gap it fills: this is a CLASSIC desktop control (group membership, column pickers,
  permission assignment, playlist building) that this library simply never had. Two
  TTyListBoxes plus a hand-built button column is what every host has been writing, each
  with its own move rules, its own off-by-one on the index shift, and its own idea of when
  the arrows should grey out.

  === Composition: real child controls, deliberately ===================================
  WINDOWED (TTyCustomControl), because it HOSTS controls — a graphic control has no handle
  to parent them to (TTyCard's reason).

  The panes are real TTyListBox children. That is the whole point: scrolling, the scrollbar,
  MultiSelect with ctrl/shift ranges, keyboard navigation, hover, Sorted, themed rows — all
  of it already exists, is already tested, and is already dressed by every skin in the repo.
  Re-drawing two lists here would be a second, worse listbox.

  The move buttons are real TTyButton children too (TTyTransferArrowButton below), for the
  same reason: hover/press/disabled/focus states, the background fade, keyboard activation
  and the ':disabled' look all come free, and — because the descendant does NOT change the
  typeKey — they resolve the plain 'TyButton' rule that every theme already ships. The only
  thing the descendant adds is WHAT it draws in the content rect: an arrow instead of a
  caption (TTyButton has no glyph vocabulary; TTyGlyphButton takes an ImageList, not a
  TTyGlyphKind, and captioning the buttons '->' would make the rail's look depend on the
  system font).

  Consequence, and it is the good kind: TTyTransfer introduces exactly ONE new typeKey
  beyond its own frame.

    'TyTransfer'       — the frame: background/border/radius/shadow/padding. The padding is
                         the outer inset the whole layout is computed inside.
    'TyTransferTitle'  — the title band above each pane: background = the band tint,
                         border-color/border-width = the hairline separator under it,
                         color/font-* = the title text. It needs its own key for the same
                         reason TyCardHeader does — a header strip is a tinted band with a
                         separator and its own ink, and the frame's single background/colour
                         pair cannot express one.

  Everything else the control shows is another control's key, already themed:
  'TyListBox'/'TyListItem' for the panes, 'TyButton' for the rail.

  === Data model ======================================================================
  Two TStrings, and they are the CHILD LISTBOXES' OWN LISTS — not copies:

    Items    IS the left (source) pane's item list.
    Selected IS the right (target) pane's item list.

  There is no third copy, so nothing can drift out of sync, and a host that reaches through
  LeftPane/RightPane sees the same objects. Moving is by INDEX: the moved strings are
  removed from the source and APPENDED to the target in source order. Duplicates are not
  policed — the two lists are plain string lists and the control never rejects a string. }
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.Controller, tyControls.StyleModel,
  tyControls.Button, tyControls.ListBox;

const
  { Built-in logical-px defaults (96-PPI baseline) for this control's seven metrics. A skin
    retunes each through the named theme metric beside it (the v3/C convention); these are
    only what a theme that sets none falls back to. Every call site scales them to device px.

    The rail is a COLUMN (rail-width) inside which a button of button-width is centred, so
    the air between a pane and an arrow is `(rail-width - button-width) / 2` — one subtraction
    rather than a third "gutter" token nobody would tune independently. The button height
    matches a compact TTyButton; the title band matches it too, so a titled transfer reads as
    a rectangle of even bands. }
  TyTransferRailWidth    = 56;   // the column reserved between the two panes
  TyTransferButtonWidth  = 32;   // one move button's width, centred in the rail
  TyTransferButtonHeight = 26;   // one move button's height
  TyTransferButtonGap    = 6;    // vertical gap between two move buttons
  TyTransferTitleHeight  = 26;   // the title band above each pane
  TyTransferArrowSize    = 12;   // one arrow glyph's square slot
  TyTransferArrowGap     = 1;    // gap between the two arrows of a "move all" button
  TyTransferArrowMargin  = 3;    // icon inset from the button's OWN edges (NOT the text padding)

  { The metric token each constant backs. Named constants rather than inline literals because
    several call sites (the layout, the arrow paint, the tests) must agree on the spelling —
    a typo in one would silently fall back to the default and the geometry would drift from
    what was painted. }
  TyTransferRailWidthVar    = '--transfer-rail-width';
  TyTransferButtonWidthVar  = '--transfer-button-width';
  TyTransferButtonHeightVar = '--transfer-button-height';
  TyTransferButtonGapVar    = '--transfer-button-gap';
  TyTransferTitleHeightVar  = '--transfer-title-height';
  TyTransferArrowSizeVar    = '--transfer-arrow-size';
  TyTransferArrowGapVar     = '--transfer-arrow-gap';
  TyTransferArrowMarginVar  = '--transfer-arrow-margin';

type
  { The four moves the rail offers, in the order they are stacked top-to-bottom. The classic
    shuttle order: the two rightward moves above the two leftward ones, and the "selected"
    move above its "all" partner in each pair. }
  TTyTransferMove = (tmMoveRight, tmMoveAllRight, tmMoveLeft, tmMoveAllLeft);

  { An ascending, deduped, in-range list of source rows — what every move rule below speaks. }
  TTyTransferIndices = array of Integer;

  { The bands of a transfer box, in DEVICE pixels, in the SAME coordinate space as the
    (already padded) client rect handed in:
      LeftTitleRect / RightTitleRect — the title bands (empty when titles are off / no room)
      LeftPaneRect  / RightPaneRect  — where the two listboxes live
      RailRect                       — the move-button column between them
    The three columns TILE the client exactly (LeftPane.Right = Rail.Left and Rail.Right =
    RightPane.Left), so no strip of frame is left unaccounted for between them. }
  TTyTransferLayout = record
    LeftTitleRect: TRect;
    LeftPaneRect: TRect;
    RailRect: TRect;
    RightTitleRect: TRect;
    RightPaneRect: TRect;
  end;

{ --- Pure rules / geometry (headless-testable; no control, no handle, no theme) -------- }

{ True when AMove sends rows from the left pane to the right one. }
function TyTransferMoveIsRightward(AMove: TTyTransferMove): Boolean;
{ True when AMove ignores the highlight and takes the whole source pane. }
function TyTransferMoveIsAll(AMove: TTyTransferMove): Boolean;

{ Pure band geometry for a transfer box. All inputs/outputs are DEVICE px.
    AClient      — the frame's client rect, ALREADY inset by the themed padding.
    ARailWidth   — the move-button column's width; the caller has already scaled it.
    ATitleHeight — the title band's height; pass 0 for "no titles".
  Horizontal: the rail is served FIRST (it is the control's only affordance — TyTagLayout's
  rule for its close slot) and the two panes split what is left, EVENLY: a transfer box whose
  panes are different widths reads as broken, so the rail — not a pane — absorbs the odd
  pixel of an uneven split. A rail wider than the client leaves both panes empty rather than
  inverted.
  Vertical: the title band takes the top of each column and the pane takes the rest,
  collapsing to empty rather than inverting when the band is taller than the client. }
function TyTransferLayout(const AClient: TRect; ARailWidth,
  ATitleHeight: Integer): TTyTransferLayout;

{ The rect of move button AIndex of ACount, stacked vertically and centred in ARail. All
  device px. Buttons are AButtonWidth x AButtonHeight with AButtonGap between them; the whole
  stack is centred in the rail both ways, and pins to the rail's top when it is taller than
  the rail (so the first buttons stay reachable rather than half of them going off both ends).
  A button that would overflow the rail's bottom is clipped to it, and comes back EMPTY —
  never inverted — when nothing is left. }
function TyTransferButtonRect(const ARail: TRect; ACount, AIndex, AButtonWidth,
  AButtonHeight, AButtonGap: Integer): TRect;

{ The cell of arrow AIndex of ACount inside a move button's ALREADY-PADDED content rect. All
  device px. ACount is 1 (a plain move) or 2 (the doubled "all" arrow). The row of ACount
  ASize-square cells separated by AGap is centred both ways in AContent, and — unlike every
  other geometry here — it SHRINKS to fit rather than collapsing: the arrow is the button's
  entire content, so a theme with generous TyButton padding must get a smaller arrow, never
  an empty button. Empty only when even a 1px arrow will not fit. }
function TyTransferArrowRect(const AContent: TRect; ACount, AIndex, ASize,
  AGap: Integer): TRect;

{ AIndices made ascending, deduped and clipped to [0, ACount) — the contract every rule below
  expects. Exposed (and tested) on its own because it is what makes TyTransferApplyMove total:
  a caller that hands over indices in click order, or with a stale one past the end, still
  gets exactly the rows that exist, exactly once, in list order. }
function TyTransferNormalizeIndices(const AIndices: array of Integer;
  ACount: Integer): TTyTransferIndices;

{ The source rows a move takes, ascending. AHighlighted[i] tells whether row i is highlighted
  in the source pane; AAll ignores the highlight and takes every row.
  A plain move with NOTHING highlighted takes nothing — it is emphatically not "then move
  everything", which is what the second button is for. }
function TyTransferMoveIndices(const AHighlighted: array of Boolean;
  AAll: Boolean): TTyTransferIndices;

{ Whether a move has anything to do — the rule that greys the rail out.
  An empty source pane can never give (both kinds are off); otherwise an "all" move is always
  live and a plain move needs at least one highlighted row. }
function TyTransferCanMove(AHighlightedCount, ASourceCount: Integer; AAll: Boolean): Boolean;

{ Apply a move: take AIndices out of ASource and APPEND them to ATarget, in SOURCE order.
  Returns how many rows actually moved (0 = nothing happened, which is what makes the
  control's "a move of nothing is silent" rule expressible).
  AIndices is normalised here, so it may arrive in any order, with duplicates, or with
  out-of-range entries. The removal runs BACK-TO-FRONT — a forward removal would shift every
  later index by one and quietly delete the wrong rows, which is the single bug every
  hand-rolled transfer box has.
  Not a control, not a handle, not a theme: the tests drive it on two bare TStringLists. }
function TyTransferApplyMove(ASource, ATarget: TStrings;
  const AIndices: array of Integer): Integer;

type
  { The rail's move affordance: an ordinary TTyButton that draws an ARROW instead of a
    caption. It deliberately keeps TTyButton's 'TyButton' typeKey — these ARE buttons, with
    a button's states and a button's weight, and every theme in the repo already dresses
    that key, so the rail is right in all of them with no theme work and no key that a skin
    could forget (a forgotten key would make the rail vanish).
    A theme that wants the rail different targets TyButton.<StyleClass>; the transfer sets no
    StyleClass of its own, so the host owns that channel through the MoveButton property. }
  TTyTransferArrowButton = class(TTyButton)
  private
    FMove: TTyTransferMove;
  protected
    { The one thing this class exists for. AContentRect is already inset by the theme's
      TyButton padding (TTyButton.RenderTo does that), which is exactly why
      TyTransferArrowRect shrinks instead of collapsing. }
    procedure DrawContent(APainter: TTyPainter; const AContentRect: TRect;
      const AStyle: TTyStyleSet); override;
  public
    { Which move this button performs — it picks the arrow's direction and how many are
      drawn. Set once by the transfer that owns it. }
    property Move: TTyTransferMove read FMove write FMove;
  end;

  TTyTransfer = class(TTyCustomControl)
  private
    FLeftList: TTyListBox;
    FRightList: TTyListBox;
    FButtons: array[TTyTransferMove] of TTyTransferArrowButton;
    FLeftTitle: string;
    FRightTitle: string;
    FTitleAlignment: TAlignment;
    FShowTitles: Boolean;
    FShowMoveAll: Boolean;
    FOnChange: TNotifyEvent;
    { The listboxes' OWN Items.OnChange hooks, captured at construction so ours can CHAIN to
      them rather than steal them.
      TTyListBox hooks its own Items.OnChange to keep its selection bit-array, ItemIndex and
      TopIndex in step with the list; a TStrings has room for exactly ONE handler, so the only
      honest way for us to also learn about an edit — and we must, because the rail's "all"
      arrows depend on the COUNT, which no selection event reports — is to capture the
      listbox's handler and call it first. A nil inner is harmless: this then degrades to a
      plain hook, exactly as if the listbox had never used one. }
    FLeftInnerChange: TNotifyEvent;
    FRightInnerChange: TNotifyEvent;
    { Set while we are driving a move ourselves: every list edit and selection clear inside
      it fires the hooks below, and re-deriving the rail's Enabled from half-applied state
      would be noise. UpdateMoveButtons runs once when the move is whole. }
    FMoving: Boolean;
    { Set for the length of the constructor. Parenting a child makes LCL re-lay the parent
      out, so SetBounds -> LayoutChildren can fire while only SOME of the children exist. }
    FBuilding: Boolean;
    function GetItems: TStrings;
    procedure SetItems(AValue: TStrings);
    function GetSelectedList: TStrings;
    procedure SetSelectedList(AValue: TStrings);
    function GetMoveButton(AMove: TTyTransferMove): TTyButton;
    procedure SetLeftTitle(const AValue: string);
    procedure SetRightTitle(const AValue: string);
    procedure SetTitleAlignment(AValue: TAlignment);
    procedure SetShowTitles(AValue: Boolean);
    procedure SetShowMoveAll(AValue: Boolean);
    procedure LeftItemsChanged(Sender: TObject);
    procedure RightItemsChanged(Sender: TObject);
    procedure PaneSelectionChanged(Sender: TObject);
    procedure MoveButtonClick(Sender: TObject);
    { The pane a move reads from, and the one it writes to. }
    function SourcePane(AMove: TTyTransferMove): TTyListBox;
    function TargetPane(AMove: TTyTransferMove): TTyListBox;
    { A pane's per-row highlight, as the plain Boolean array the pure rules take. }
    function HighlightOf(APane: TTyListBox): TBooleanDynArray;
    { A theme metric in DEVICE px at APPI. }
    function MetricPx(const AName: string; ADefault, APPI: Integer): Integer;
    { How many buttons the rail currently shows (4, or 2 with ShowMoveAll off). }
    function VisibleMoveCount: Integer;
    { Position of AMove within the CURRENTLY VISIBLE stack, or -1 when it is hidden. }
    function MoveSlot(AMove: TTyTransferMove): Integer;
    procedure LayoutChildren;
    procedure UpdateMoveButtons;
    procedure PaintTitleBand(APainter: TTyPainter; const ABand: TRect; const AText: string;
      const AFrameStyle, ATitleStyle: TTyStyleSet);
  protected
    function GetStyleTypeKey: string; override;
    { The layout for the control's CURRENT size, at its current PPI. Every consumer — the
      children's bounds, the painted bands, the public rect accessors — goes through this one
      function, so what is painted and where the panes actually sit cannot drift. }
    function CurrentLayout: TTyTransferLayout;
    function LayoutAtPPI(const AClient: TRect; APPI: Integer): TTyTransferLayout;
    { Keep the panes and the rail on our controller, so a controller assigned AFTER the
      children exist still themes them (TTyRadioGroup.SetController's rule). }
    procedure SetController(AValue: TTyStyleController); override;
    procedure Loaded; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { NOT DoOnResize: LCL suppresses Resize entirely while the parent form has no handle
      (AutoSizeDelayed), which is every headless test AND every moment the designer streams a
      form. SetBounds is the one seam that always runs, so it is where the panes and the rail
      follow the frame. (Public, matching TWinControl — a protected override would narrow it.) }
    procedure SetBounds(ALeft, ATop, AWidth, AHeight: Integer); override;
    { Perform AMove: take the rows its rule selects out of the source pane and append them to
      the target. Silent and inert when the rule selects nothing. Public so a host can drive
      the rail from a menu, a shortcut or a double-click. }
    procedure DoMove(AMove: TTyTransferMove);
    { The four moves by name, for readable host code. }
    procedure MoveRight;
    procedure MoveAllRight;
    procedure MoveLeft;
    procedure MoveAllLeft;
    { Whether AMove has anything to move right now — the same rule that drives the rail's
      Enabled. }
    function CanMove(AMove: TTyTransferMove): Boolean;
    { The painted title bands, in the frame's own coordinates; empty when ShowTitles is off. }
    function LeftTitleRect: TRect;
    function RightTitleRect: TRect;
    { The move-button column between the panes, in the frame's own coordinates. }
    function RailRect: TRect;
    { The two panes. Real TTyListBoxes owned by the transfer — reach through them for the
      listbox's own knobs (ItemHeight, Sorted, TopIndex, the row styling). Do NOT free or
      re-parent them, and note that their OnChange belongs to the transfer (it is what keeps
      the rail's Enabled honest); use TTyTransfer.OnChange instead. }
    property LeftPane: TTyListBox read FLeftList;
    property RightPane: TTyListBox read FRightList;
    { The rail's buttons, keyed by the move they perform. Owned by the transfer. Exposed so a
      host can give them Hints (an arrow says the direction, not the meaning) or a StyleClass.
      Their Enabled is derived from the selection and WILL be overwritten. }
    property MoveButton[AMove: TTyTransferMove]: TTyButton read GetMoveButton;
  published
    { The SOURCE pool — the left pane's list, live and not a copy. Editing it directly is
      fine; the rail re-derives its Enabled from every edit. }
    property Items: TStrings read GetItems write SetItems;
    { The TARGET list — the right pane's list, live and not a copy. Rows moved rightward are
      appended here in source order; seeding it before the form shows is how a transfer box
      starts out half-filled. }
    property Selected: TStrings read GetSelectedList write SetSelectedList;
    { Fires whenever a move actually moved something — from the rail, or from the DoMove /
      MoveXxx methods (a code-driven move is the same event as a clicked one, TTySegmented's
      rule). A move that moved nothing is not a change and stays silent, and so is a host's
      own edit of Items/Selected: the host caused that one and does not need telling. }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    { The pane titles. Drawn with the resolved TyTransferTitle style (NOT the LCL Font.*),
      ellipsised when they do not fit, never wrapped, and not mnemonic-parsed (a title
      activates nothing, so '&' is literal). }
    property LeftTitle: string read FLeftTitle write SetLeftTitle;
    property RightTitle: string read FRightTitle write SetRightTitle;
    property TitleAlignment: TAlignment read FTitleAlignment write SetTitleAlignment
      default taLeftJustify;
    { Whether the title bands are drawn AND reserved above the panes. The FLAG is
      authoritative, not the title text: an empty LeftTitle still reserves its band, so
      clearing a title never makes the panes jump (TTyCard.ShowHeader's rule). }
    property ShowTitles: Boolean read FShowTitles write SetShowTitles default True;
    { Whether the rail offers the two doubled "move everything" arrows. Off leaves the two
      plain arrows, re-centred in the rail. }
    property ShowMoveAll: Boolean read FShowMoveAll write SetShowMoveAll default True;
    property Align;
    property Anchors;
    property StyleClass;
    property StyleOverride;
    property Controller;
  end;

implementation

{ --- pure rules / geometry ------------------------------------------------------------ }

function TyTransferMoveIsRightward(AMove: TTyTransferMove): Boolean;
begin
  Result := AMove in [tmMoveRight, tmMoveAllRight];
end;

function TyTransferMoveIsAll(AMove: TTyTransferMove): Boolean;
begin
  Result := AMove in [tmMoveAllRight, tmMoveAllLeft];
end;

function TyTransferLayout(const AClient: TRect; ARailWidth,
  ATitleHeight: Integer): TTyTransferLayout;
var
  clientW, clientH, railW, titleH, paneW, railL, railR: Integer;
begin
  Result.LeftTitleRect := Rect(0, 0, 0, 0);
  Result.LeftPaneRect := Rect(0, 0, 0, 0);
  Result.RailRect := Rect(0, 0, 0, 0);
  Result.RightTitleRect := Rect(0, 0, 0, 0);
  Result.RightPaneRect := Rect(0, 0, 0, 0);
  clientW := AClient.Right - AClient.Left;
  clientH := AClient.Bottom - AClient.Top;
  if (clientW <= 0) or (clientH <= 0) then Exit;

  railW := ARailWidth;
  if railW < 0 then railW := 0;
  if railW > clientW then railW := clientW;   // the rail is served first; the panes lose
  titleH := ATitleHeight;
  if titleH < 0 then titleH := 0;
  if titleH > clientH then titleH := clientH; // a band taller than the box eats the pane

  // Both panes take the SAME width — an uneven split's odd pixel goes to the rail, which is
  // symmetric about the centre and where nobody can see it.
  paneW := (clientW - railW) div 2;
  railL := AClient.Left + paneW;
  railR := AClient.Right - paneW;

  Result.RailRect := Rect(railL, AClient.Top, railR, AClient.Bottom);
  if paneW <= 0 then Exit;   // rail-only: the panes collapse rather than invert

  Result.LeftTitleRect := Rect(AClient.Left, AClient.Top, railL, AClient.Top + titleH);
  Result.LeftPaneRect := Rect(AClient.Left, AClient.Top + titleH, railL, AClient.Bottom);
  Result.RightTitleRect := Rect(railR, AClient.Top, AClient.Right, AClient.Top + titleH);
  Result.RightPaneRect := Rect(railR, AClient.Top + titleH, AClient.Right, AClient.Bottom);
  // titleH = 0 leaves the bands as zero-height (empty) rects, which is exactly "no titles".
  if titleH >= clientH then
  begin
    // The band ate the column: keep the band, drop the pane (empty, never inverted).
    Result.LeftPaneRect := Rect(0, 0, 0, 0);
    Result.RightPaneRect := Rect(0, 0, 0, 0);
  end;
end;

function TyTransferButtonRect(const ARail: TRect; ACount, AIndex, AButtonWidth,
  AButtonHeight, AButtonGap: Integer): TRect;
var
  railW, railH, stackH, top_, bottom_, left_: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if (ACount <= 0) or (AIndex < 0) or (AIndex >= ACount) then Exit;
  railW := ARail.Right - ARail.Left;
  railH := ARail.Bottom - ARail.Top;
  if (railW <= 0) or (railH <= 0) then Exit;
  if AButtonWidth <= 0 then Exit;
  if AButtonHeight <= 0 then Exit;
  if AButtonGap < 0 then AButtonGap := 0;
  if AButtonWidth > railW then AButtonWidth := railW;   // a narrow rail squeezes, never spills

  stackH := ACount * AButtonHeight + (ACount - 1) * AButtonGap;
  if stackH < railH then
    top_ := ARail.Top + (railH - stackH) div 2
  else
    top_ := ARail.Top;   // taller than the rail: pin to the top, so the first arrows survive
  Inc(top_, AIndex * (AButtonHeight + AButtonGap));
  if top_ >= ARail.Bottom then Exit;   // this one is entirely past the rail
  bottom_ := top_ + AButtonHeight;
  if bottom_ > ARail.Bottom then bottom_ := ARail.Bottom;
  if bottom_ <= top_ then Exit;

  left_ := ARail.Left + (railW - AButtonWidth) div 2;   // centred in the column
  Result := Rect(left_, top_, left_ + AButtonWidth, bottom_);
end;

function TyTransferArrowRect(const AContent: TRect; ACount, AIndex, ASize,
  AGap: Integer): TRect;
var
  contentW, contentH, avail, size_, rowW, left_, top_: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if (ACount <= 0) or (AIndex < 0) or (AIndex >= ACount) then Exit;
  contentW := AContent.Right - AContent.Left;
  contentH := AContent.Bottom - AContent.Top;
  if (contentW <= 0) or (contentH <= 0) then Exit;
  if ASize <= 0 then Exit;
  if AGap < 0 then AGap := 0;

  // Shrink to fit rather than vanish: the arrow IS the button's content, and the content rect
  // is whatever the theme's TyButton padding left of a rail-width-wide button. The gaps are
  // kept whole and the glyphs give way — two touching arrows still read as "all", two
  // missing ones read as a broken button.
  size_ := ASize;
  avail := contentW - (ACount - 1) * AGap;
  if avail div ACount < size_ then size_ := avail div ACount;
  if contentH < size_ then size_ := contentH;
  if size_ < 1 then Exit;

  rowW := ACount * size_ + (ACount - 1) * AGap;
  left_ := AContent.Left + (contentW - rowW) div 2 + AIndex * (size_ + AGap);
  top_ := AContent.Top + (contentH - size_) div 2;
  Result := Rect(left_, top_, left_ + size_, top_ + size_);
end;

function TyTransferNormalizeIndices(const AIndices: array of Integer;
  ACount: Integer): TTyTransferIndices;
var
  seen: array of Boolean;
  i, n, idx: Integer;
begin
  Result := nil;
  if ACount <= 0 then Exit;
  // A seen-bitmap rather than a sort: the domain is [0, ACount), so one pass to mark and one
  // to emit gives ascending + deduped in O(n), and cannot mis-order equal keys.
  SetLength(seen, ACount);
  for i := 0 to High(AIndices) do
  begin
    idx := AIndices[i];
    if (idx >= 0) and (idx < ACount) then seen[idx] := True;
  end;
  SetLength(Result, ACount);
  n := 0;
  for i := 0 to ACount - 1 do
    if seen[i] then
    begin
      Result[n] := i;
      Inc(n);
    end;
  SetLength(Result, n);
end;

function TyTransferMoveIndices(const AHighlighted: array of Boolean;
  AAll: Boolean): TTyTransferIndices;
var
  i, n: Integer;
begin
  Result := nil;
  if Length(AHighlighted) = 0 then Exit;
  SetLength(Result, Length(AHighlighted));
  n := 0;
  for i := 0 to High(AHighlighted) do
    // AAll takes the row whatever its highlight says; a plain move takes only the marked
    // rows, and takes NOTHING when none are marked (that is the other button's job).
    if AAll or AHighlighted[i] then
    begin
      Result[n] := i;
      Inc(n);
    end;
  SetLength(Result, n);
end;

function TyTransferCanMove(AHighlightedCount, ASourceCount: Integer; AAll: Boolean): Boolean;
begin
  if ASourceCount <= 0 then Exit(False);   // an empty pane has nothing to give, either way
  if AAll then
    Result := True
  else
    Result := AHighlightedCount > 0;
end;

function TyTransferApplyMove(ASource, ATarget: TStrings;
  const AIndices: array of Integer): Integer;
var
  idx: TTyTransferIndices;
  moved: TStringList;
  i: Integer;
begin
  Result := 0;
  if (ASource = nil) or (ATarget = nil) then Exit;
  idx := TyTransferNormalizeIndices(AIndices, ASource.Count);
  if Length(idx) = 0 then Exit;

  moved := TStringList.Create;
  try
    // Collect FORWARD, so the target receives the rows in source order...
    for i := 0 to High(idx) do
      moved.Add(ASource[idx[i]]);
    // ...but delete BACKWARD, so an earlier removal never shifts a later index onto the
    // wrong row. (Normalisation is what makes "backward" well-defined here.)
    for i := High(idx) downto 0 do
      ASource.Delete(idx[i]);
    ATarget.AddStrings(moved);
    Result := moved.Count;
  finally
    moved.Free;
  end;
end;

{ --- TTyTransferArrowButton ------------------------------------------------------------ }

procedure TTyTransferArrowButton.DrawContent(APainter: TTyPainter;
  const AContentRect: TRect; const AStyle: TTyStyleSet);
var
  kind: TTyGlyphKind;
  cell, iconArea: TRect;
  arrows, i, sizePx, gapPx, marginPx: Integer;
begin
  if TyTransferMoveIsRightward(FMove) then kind := tgChevronRight else kind := tgChevronLeft;
  // CHEVRONS, not arrows. The idiom this rail is drawing is the shuttle box's '>' / '>>', and
  // a chevron IS that mark; an arrow is a chevron plus a shaft. The shaft is what went wrong:
  // in a 12px slot two of them sit 1px apart and the shafts run together into one bar, so
  // "move all" read as a smear rather than as two marks. It also matches what this control is
  // modelled on -- Ant Design's Transfer uses chevron icons -- and the library's own rule that
  // a glyph's SHAPE follows its ROLE (a stepper gets a solid triangle, a disclosure gets a V).
  //
  // Arrows were chosen originally for one reason, recorded here as "the painter has no
  // chevron-LEFT". It has had one since; the pair is what the calendar's month nav, the grid
  // and the sider collapse all draw with. Nothing but this call site was left behind.
  //
  // "All" is still TWO of the same mark rather than a glyph of its own: it keeps the leftward
  // and rightward buttons one shape, and needs no vocabulary the library does not own.
  if TyTransferMoveIsAll(FMove) then arrows := 2 else arrows := 1;
  sizePx := APainter.Scale(ActiveController.Metric(TyTransferArrowSizeVar, TyTransferArrowSize));
  gapPx := APainter.Scale(ActiveController.Metric(TyTransferArrowGapVar, TyTransferArrowGap));
  // Draw into the button's OWN area, not AContentRect. AContentRect is inset by the TyButton
  // TEXT padding (e.g. antdesign's 10px per side), which is meant for a caption — on a 32px
  // icon button it leaves ~12px, and TWO "move all" arrows then shrink to ~5px each and lose
  // their heads, rendering as '--'. Recover the full button rect (AContentRect + that padding)
  // and inset it by a small ICON margin instead, so both arrows keep a readable size.
  marginPx := APainter.Scale(ActiveController.Metric(TyTransferArrowMarginVar, TyTransferArrowMargin));
  iconArea := Rect(
    AContentRect.Left   - APainter.Scale(AStyle.Padding.Left)   + marginPx,
    AContentRect.Top    - APainter.Scale(AStyle.Padding.Top)    + marginPx,
    AContentRect.Right  + APainter.Scale(AStyle.Padding.Right)  - marginPx,
    AContentRect.Bottom + APainter.Scale(AStyle.Padding.Bottom) - marginPx);
  for i := 0 to arrows - 1 do
  begin
    cell := TyTransferArrowRect(iconArea, arrows, i, sizePx, gapPx);
    if cell.Right <= cell.Left then Continue;
    // The button's own resolved ink — so ':disabled { opacity }' and a TyButton.primary
    // rail tint the arrow with the button, and no colour is ever invented here. v3/C5: the
    // arrow is theme-overridable with an icon-font codepoint (--glyph-arrowright/-left).
    // Pad 1, not TyDrawGlyph's default 4: this rect is a slot ALREADY measured from a
    // size token, so the token must mean the MARK's size. The default pad would eat 9
    // logical px and leave a 3px smudge nobody can read a direction off.
    TyDrawGlyph(APainter, ActiveController, cell, kind, AStyle.TextColor, 1, 1);
  end;
end;

{ --- TTyTransfer ----------------------------------------------------------------------- }

constructor TTyTransfer.Create(AOwner: TComponent);

  function NewPane: TTyListBox;
  begin
    Result := TTyListBox.Create(Self);   // owned by Self: freed with the transfer
    // INTERNAL helper: never a designable child in the IDE object tree. Set BEFORE anything
    // touches Visible — the design-time shown-state is re-evaluated on the Visible change.
    Result.ControlStyle := Result.ControlStyle + [csNoDesignVisible];
    Result.Parent := Self;
    // A transfer box is inherently multi-select: moving one row at a time is what makes a
    // hand-rolled one unbearable. It also makes SelCount/Selected[] the pane's selection
    // truth (in single mode the listbox derives them from ItemIndex instead).
    Result.MultiSelect := True;
    Result.Controller := Controller;
  end;

var
  m: TTyTransferMove;
  btn: TTyTransferArrowButton;
begin
  inherited Create(AOwner);
  FBuilding := True;
  try
    // NOT csAcceptsControls: the panes and the rail fill the whole frame, so letting the
    // designer drop a control "into" a transfer box would only drop it onto a listbox.
    FTitleAlignment := taLeftJustify;
    FShowTitles := True;
    FShowMoveAll := True;

    FLeftList := NewPane;
    FRightList := NewPane;
    // Chain, do not steal — see the FLeftInnerChange declaration.
    FLeftInnerChange := FLeftList.ItemsList.OnChange;
    FLeftList.ItemsList.OnChange := @LeftItemsChanged;
    FLeftList.OnChange := @PaneSelectionChanged;
    FRightInnerChange := FRightList.ItemsList.OnChange;
    FRightList.ItemsList.OnChange := @RightItemsChanged;
    FRightList.OnChange := @PaneSelectionChanged;

    for m := Low(TTyTransferMove) to High(TTyTransferMove) do
    begin
      btn := TTyTransferArrowButton.Create(Self);
      btn.ControlStyle := btn.ControlStyle + [csNoDesignVisible];
      btn.Parent := Self;
      // The button carries the move it performs, so ONE handler serves all four.
      btn.Move := m;
      btn.OnClick := @MoveButtonClick;
      btn.Controller := Controller;
      // The rail is not a tab stop: a transfer box is driven from its panes, and four arrows
      // between two lists would make Tab crawl through the middle of the widget. A click
      // still focuses a button, so it keeps its focus ring.
      btn.TabStop := False;
      FButtons[m] := btn;
    end;

    Width := 480;
    Height := 220;
  finally
    FBuilding := False;
  end;
  LayoutChildren;
  UpdateMoveButtons;
end;

destructor TTyTransfer.Destroy;
begin
  // Give each pane its OWN Items hook back before the teardown: a string list fires OnChange
  // as it clears, and our handler reads fields (and sibling children) that the inherited
  // destructor is in the middle of dismantling. Restoring rather than nil-ing keeps the
  // listbox's own bookkeeping exactly as it is when nobody chained onto it.
  if FLeftList <> nil then
  begin
    FLeftList.ItemsList.OnChange := FLeftInnerChange;
    FLeftList.OnChange := nil;
  end;
  if FRightList <> nil then
  begin
    FRightList.ItemsList.OnChange := FRightInnerChange;
    FRightList.OnChange := nil;
  end;
  inherited Destroy;
end;

function TTyTransfer.GetStyleTypeKey: string;
begin
  Result := 'TyTransfer';
end;

{ --- panes: hooks + data --------------------------------------------------------------- }

procedure TTyTransfer.LeftItemsChanged(Sender: TObject);
begin
  if Assigned(FLeftInnerChange) then FLeftInnerChange(Sender);   // the pane's own bookkeeping first
  if FMoving then Exit;
  UpdateMoveButtons;
end;

procedure TTyTransfer.RightItemsChanged(Sender: TObject);
begin
  if Assigned(FRightInnerChange) then FRightInnerChange(Sender);
  if FMoving then Exit;
  UpdateMoveButtons;
end;

procedure TTyTransfer.PaneSelectionChanged(Sender: TObject);
begin
  // A pane's highlight moved: the two plain arrows live or die by it.
  if FMoving then Exit;
  UpdateMoveButtons;
end;

procedure TTyTransfer.MoveButtonClick(Sender: TObject);
begin
  if Sender is TTyTransferArrowButton then
    DoMove(TTyTransferArrowButton(Sender).Move);
end;

function TTyTransfer.GetItems: TStrings;
begin
  Result := FLeftList.Items;
end;

procedure TTyTransfer.SetItems(AValue: TStrings);
begin
  // Assign the LIST, not the listbox's Items property: the property setter suppresses the
  // pane's own change hook while it copies and then does its bookkeeping by hand, which would
  // route our chained hook past a half-applied state.
  FLeftList.Items.Assign(AValue);
  UpdateMoveButtons;
end;

function TTyTransfer.GetSelectedList: TStrings;
begin
  Result := FRightList.Items;
end;

procedure TTyTransfer.SetSelectedList(AValue: TStrings);
begin
  FRightList.Items.Assign(AValue);
  UpdateMoveButtons;
end;

function TTyTransfer.GetMoveButton(AMove: TTyTransferMove): TTyButton;
begin
  Result := FButtons[AMove];
end;

function TTyTransfer.SourcePane(AMove: TTyTransferMove): TTyListBox;
begin
  if TyTransferMoveIsRightward(AMove) then Result := FLeftList else Result := FRightList;
end;

function TTyTransfer.TargetPane(AMove: TTyTransferMove): TTyListBox;
begin
  if TyTransferMoveIsRightward(AMove) then Result := FRightList else Result := FLeftList;
end;

function TTyTransfer.HighlightOf(APane: TTyListBox): TBooleanDynArray;
var
  i: Integer;
begin
  Result := nil;
  SetLength(Result, APane.Items.Count);
  for i := 0 to APane.Items.Count - 1 do
    Result[i] := APane.Selected[i];
end;

{ --- property setters ------------------------------------------------------------------ }

procedure TTyTransfer.SetLeftTitle(const AValue: string);
begin
  if FLeftTitle = AValue then Exit;
  FLeftTitle := AValue;
  Invalidate;   // the band is reserved by ShowTitles, not by the text: no relayout
end;

procedure TTyTransfer.SetRightTitle(const AValue: string);
begin
  if FRightTitle = AValue then Exit;
  FRightTitle := AValue;
  Invalidate;
end;

procedure TTyTransfer.SetTitleAlignment(AValue: TAlignment);
begin
  if FTitleAlignment = AValue then Exit;
  FTitleAlignment := AValue;
  Invalidate;
end;

procedure TTyTransfer.SetShowTitles(AValue: Boolean);
begin
  if FShowTitles = AValue then Exit;
  FShowTitles := AValue;
  LayoutChildren;   // the panes just grew/shrank by a band
  Invalidate;
end;

procedure TTyTransfer.SetShowMoveAll(AValue: Boolean);
begin
  if FShowMoveAll = AValue then Exit;
  FShowMoveAll := AValue;
  LayoutChildren;   // the stack lost/gained two buttons and re-centres
  Invalidate;
end;

procedure TTyTransfer.SetController(AValue: TTyStyleController);
var
  m: TTyTransferMove;
begin
  inherited SetController(AValue);
  if FLeftList <> nil then FLeftList.Controller := AValue;
  if FRightList <> nil then FRightList.Controller := AValue;
  for m := Low(TTyTransferMove) to High(TTyTransferMove) do
    if FButtons[m] <> nil then FButtons[m].Controller := AValue;
end;

{ --- geometry -------------------------------------------------------------------------- }

function TTyTransfer.MetricPx(const AName: string; ADefault, APPI: Integer): Integer;
begin
  if APPI <= 0 then APPI := 96;
  Result := ActiveController.Metric(AName, ADefault);
  if Result < 0 then Result := 0;
  // MulDiv(..., APPI, 96) is the same logical->device conversion TTyPainter.Scale applies, so
  // the bands the paint fills are the bands the children are placed in.
  Result := MulDiv(Result, APPI, 96);
end;

function TTyTransfer.LayoutAtPPI(const AClient: TRect; APPI: Integer): TTyTransferLayout;
var
  S: TTyStyleSet;
  inner: TRect;
  titleH: Integer;
begin
  if APPI <= 0 then APPI := 96;
  S := CurrentStyle;
  // The frame's themed padding is the outer inset everything is laid out inside — so the
  // panes clear the frame's border and keep the surface's breathing room, and a skin that
  // wants a tighter box says so in CSS rather than in this code.
  inner := AClient;
  Inc(inner.Left, MulDiv(S.Padding.Left, APPI, 96));
  Inc(inner.Top, MulDiv(S.Padding.Top, APPI, 96));
  Dec(inner.Right, MulDiv(S.Padding.Right, APPI, 96));
  Dec(inner.Bottom, MulDiv(S.Padding.Bottom, APPI, 96));
  if FShowTitles then
    titleH := MetricPx(TyTransferTitleHeightVar, TyTransferTitleHeight, APPI)
  else
    titleH := 0;
  Result := TyTransferLayout(inner,
    MetricPx(TyTransferRailWidthVar, TyTransferRailWidth, APPI), titleH);
end;

function TTyTransfer.CurrentLayout: TTyTransferLayout;
begin
  // Width/Height, not ClientRect: LCL's client rect lags behind SetBounds while the control
  // has no handle (every headless test), and for this borderless custom control the two are
  // identical at runtime. TTyListBox.VisibleRows takes the same escape for the same reason.
  Result := LayoutAtPPI(Rect(0, 0, Width, Height), Font.PixelsPerInch);
end;

function TTyTransfer.LeftTitleRect: TRect;
begin
  Result := CurrentLayout.LeftTitleRect;
end;

function TTyTransfer.RightTitleRect: TRect;
begin
  Result := CurrentLayout.RightTitleRect;
end;

function TTyTransfer.RailRect: TRect;
begin
  Result := CurrentLayout.RailRect;
end;

function TTyTransfer.VisibleMoveCount: Integer;
begin
  if FShowMoveAll then Result := 4 else Result := 2;
end;

function TTyTransfer.MoveSlot(AMove: TTyTransferMove): Integer;
var
  m: TTyTransferMove;
begin
  Result := -1;
  if TyTransferMoveIsAll(AMove) and (not FShowMoveAll) then Exit;
  Result := 0;
  // Count the visible buttons that stack ABOVE this one — the enum's own order IS the rail's
  // order, so a hidden "all" pair simply closes the gap.
  for m := Low(TTyTransferMove) to High(TTyTransferMove) do
  begin
    if m = AMove then Exit;
    if TyTransferMoveIsAll(m) and (not FShowMoveAll) then Continue;
    Inc(Result);
  end;
end;

procedure TTyTransfer.LayoutChildren;
var
  lay: TTyTransferLayout;
  m: TTyTransferMove;
  r: TRect;
  ppi, slot, bw, bh, gap: Integer;

  procedure Place(AControl: TControl; const ARect: TRect);
  begin
    AControl.SetBounds(ARect.Left, ARect.Top, ARect.Right - ARect.Left,
      ARect.Bottom - ARect.Top);
  end;

begin
  // Parenting a child re-lays the parent out, so this can fire mid-construction with only
  // some of the children built; and the teardown must not re-place controls it is freeing.
  if FBuilding or (csDestroying in ComponentState) then Exit;
  if (FLeftList = nil) or (FRightList = nil) then Exit;
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  lay := CurrentLayout;
  Place(FLeftList, lay.LeftPaneRect);
  Place(FRightList, lay.RightPaneRect);

  bw := MetricPx(TyTransferButtonWidthVar, TyTransferButtonWidth, ppi);
  bh := MetricPx(TyTransferButtonHeightVar, TyTransferButtonHeight, ppi);
  gap := MetricPx(TyTransferButtonGapVar, TyTransferButtonGap, ppi);
  for m := Low(TTyTransferMove) to High(TTyTransferMove) do
  begin
    if FButtons[m] = nil then Continue;
    slot := MoveSlot(m);
    if slot < 0 then
    begin
      FButtons[m].Visible := False;   // csNoDesignVisible is already set, so it stays hidden
      Continue;                        // in the designer too
    end;
    FButtons[m].Visible := True;
    r := TyTransferButtonRect(lay.RailRect, VisibleMoveCount, slot, bw, bh, gap);
    Place(FButtons[m], r);
  end;
end;

procedure TTyTransfer.SetBounds(ALeft, ATop, AWidth, AHeight: Integer);
begin
  inherited SetBounds(ALeft, ATop, AWidth, AHeight);
  LayoutChildren;
end;

procedure TTyTransfer.Loaded;
begin
  inherited Loaded;
  // The .lfm has just finished streaming Items/Selected/ShowTitles/ShowMoveAll: only now is
  // there a list to size the panes against and a count to grey the rail from.
  LayoutChildren;
  UpdateMoveButtons;
end;

{ --- moves ----------------------------------------------------------------------------- }

function TTyTransfer.CanMove(AMove: TTyTransferMove): Boolean;
var
  pane: TTyListBox;
begin
  pane := SourcePane(AMove);
  Result := TyTransferCanMove(pane.SelCount, pane.Items.Count, TyTransferMoveIsAll(AMove));
end;

procedure TTyTransfer.UpdateMoveButtons;
var
  m: TTyTransferMove;
begin
  if FBuilding or (csDestroying in ComponentState) then Exit;
  if (FLeftList = nil) or (FRightList = nil) then Exit;
  for m := Low(TTyTransferMove) to High(TTyTransferMove) do
    if FButtons[m] <> nil then
      // The rail's Enabled says exactly one thing: "this move has something to move". It is
      // NOT gated on the transfer's own Enabled — a disabled parent window already refuses
      // its children input, and no other container here greys its children by hand.
      FButtons[m].Enabled := CanMove(m);
end;

procedure TTyTransfer.DoMove(AMove: TTyTransferMove);
var
  src, dst: TTyListBox;
  idx: TTyTransferIndices;
  n: Integer;
begin
  src := SourcePane(AMove);
  dst := TargetPane(AMove);
  idx := TyTransferMoveIndices(HighlightOf(src), TyTransferMoveIsAll(AMove));
  if Length(idx) = 0 then Exit;   // nothing to do: silent and inert

  FMoving := True;
  try
    { Clear the SOURCE's highlight BEFORE the rows leave, and clear only that one.
      Before: the pane's selection bit-array is index-keyed, so deleting row 1 of three
      slides row 2's bit onto the row that took its place — a stale highlight on an item the
      user never picked.
      Only the source: the target's rows are APPENDED, so nothing it already had moved, and
      a selection the user made over there for the return trip must survive this one. }
    src.ClearSelection;
    n := TyTransferApplyMove(src.Items, dst.Items, idx);
  finally
    FMoving := False;
  end;
  UpdateMoveButtons;
  if (n > 0) and Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyTransfer.MoveRight;
begin
  DoMove(tmMoveRight);
end;

procedure TTyTransfer.MoveAllRight;
begin
  DoMove(tmMoveAllRight);
end;

procedure TTyTransfer.MoveLeft;
begin
  DoMove(tmMoveLeft);
end;

procedure TTyTransfer.MoveAllLeft;
begin
  DoMove(tmMoveAllLeft);
end;

{ --- painting -------------------------------------------------------------------------- }

procedure TTyTransfer.PaintTitleBand(APainter: TTyPainter; const ABand: TRect;
  const AText: string; const AFrameStyle, ATitleStyle: TTyStyleSet);
var
  sepT: Integer;
  sepRect, textRect: TRect;
  f: TTyFill;
  ink: TTyColor;
  pad: TRect;
begin
  if (ABand.Right <= ABand.Left) or (ABand.Bottom <= ABand.Top) then Exit;

  // No TyTransferTitle background -> no band tint. The title still draws on the frame: the
  // house rule is "no background => no band", not "no band => no text".
  if tpBackground in ATitleStyle.Present then
    APainter.FillBackground(ABand, ATitleStyle.Background, TyEffectiveCorners(ATitleStyle));

  // The hairline separator under the band — a filled strip, not a border: it is ONE edge, and
  // squaring it keeps it crisp at any radius (TTyCard's PaintStrip does the same).
  sepT := 0;
  if TyBorderVisible(ATitleStyle) then
  begin
    sepT := APainter.Scale(ATitleStyle.BorderWidth);
    if sepT < 1 then sepT := 1;
    sepRect := Rect(ABand.Left, ABand.Bottom - sepT, ABand.Right, ABand.Bottom);
    if sepRect.Bottom > sepRect.Top then
    begin
      f := Default(TTyFill);
      f.Kind := tfkSolid;
      f.Color := ATitleStyle.BorderColor;
      APainter.FillBackground(sepRect, f, 0);
    end;
  end;

  if AText = '' then Exit;
  // A skin that styles TyTransfer but forgets TyTransferTitle resolves an EMPTY style set,
  // whose colour is $00000000 — a fully TRANSPARENT (invisible) title. Fall back to the
  // frame's own ink so a partial skin degrades to a readable box rather than a blank band,
  // and never to a colour invented here. (TTyCard's header carries the identical rule.)
  if tpTextColor in ATitleStyle.Present then
    ink := ATitleStyle.TextColor
  else
    ink := AFrameStyle.TextColor;
  // Horizontal air: the band's own padding when the theme set one, else the frame's — so by
  // default a title lines up with the pane below it.
  if tpPadding in ATitleStyle.Present then pad := ATitleStyle.Padding else pad := AFrameStyle.Padding;
  textRect := Rect(ABand.Left + APainter.Scale(pad.Left), ABand.Top,
                   ABand.Right - APainter.Scale(pad.Right), ABand.Bottom - sepT);
  if (textRect.Right > textRect.Left) and (textRect.Bottom > textRect.Top) then
    // Ellipsised: a band narrower than its title shows 'Availab…', not a glyph sheared at the
    // clip edge. No mnemonic parsing — a title activates nothing (see the property).
    APainter.DrawText(textRect, AText, ATitleStyle.FontName, ResolveFontSize(ATitleStyle),
      ATitleStyle.FontWeight, ink, FTitleAlignment, tlCenter, True);
end;

procedure TTyTransfer.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, titleS: TTyStyleSet;
  R: TRect;
  lay: TTyTransferLayout;
begin
  P := TTyPainter.Create;
  try
    // A (0,0)-local rect: the painter builds a (W x H) bitmap and blits it at ARect.Left/Top,
    // so a non-zero ARect origin would shift the whole frame.
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    // The frame: background + border + shadow + opacity, all from the resolved TyTransfer
    // style. DrawFrame fills the parent's opaque surface first, which a WINDOWED control needs
    // whatever the theme says (its own window shows through the corner gaps otherwise) —
    // everything of OURS below is gated on the theme having defined the key.
    DrawFrame(P, R, S);
    if not (tpBackground in S.Present) then
    begin
      // No TyTransfer rule -> no frame and no bands. The panes and the rail are separate
      // controls with their own keys and are unaffected: degrade, never invent a look.
      P.EndPaint;
      Exit;
    end;
    if FShowTitles then
    begin
      lay := LayoutAtPPI(R, APPI);
      // One resolve for both bands: they are the same key, the same class and the same state
      // (a title band has no state of its own — it is a label, not an affordance).
      titleS := ActiveController.Model.ResolveStyle('TyTransferTitle', StyleClass, CurrentStates);
      PaintTitleBand(P, lay.LeftTitleRect, FLeftTitle, S, titleS);
      PaintTitleBand(P, lay.RightTitleRect, FRightTitle, S, titleS);
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyTransfer.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
