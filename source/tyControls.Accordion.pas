unit tyControls.Accordion;
{$mode objfpc}{$H+}

{ TTyAccordion — a container that stacks collapsible panels (TTyExPanel) as the sections of a
  side bar, the way an editor's Explorer holds "Folders" and "Outline" in one column.

  The children are laid out top to bottom at the container's full width, in creation order
  (Controls[]). A collapsed section takes its header's height; the expanded sections share
  what is left in proportion to their ExpandedHeight, which in a stack is the section's
  weight; a child that is not a TTyExPanel keeps its own height. Between two neighbouring
  expanded sections there is a strip the user drags to move height from one to the other.
  No section is given less than its header and MinBodyHeight; when even that does not fit,
  the stack runs past the bottom and is cut there (there is no scrolling).

  The container owns the heights: a panel in it does not size itself (ITyExPanelHost). When a
  section is toggled the stack moves to its new distribution over that section's
  AnimationDuration. The panels' OnExpand / OnCollapse stay the application's.

  Theming: 'TyAccordion' is the container's frame; 'TyAccordionSplitter' is the drag strip
  (':hover' under the pointer, ':active' while dragged). --accordion-splitter-size is the
  strip's thickness and --accordion-min-body-height the default MinBodyHeight. Whether the
  sections have frames of their own is the sections' business: StyleClass 'embedded' on a
  TTyExPanel takes its frame off. }

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, ExtCtrls,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.StyleModel,
  tyControls.Animation, tyControls.ExPanel;

const
  { Logical px. }
  TyAccordionMinBodyVar  = '--accordion-min-body-height';
  TyAccordionMinBodyDef  = 48;
  TyAccordionSplitterVar = '--accordion-splitter-size';
  TyAccordionSplitterDef = 4;
  TyAccordionSplitterKey = 'TyAccordionSplitter';
  { The saved layout's tag: the format and its version. }
  TyAccordionLayoutTag = 'TYACCORDION/1';
  { The longest layout text that is parsed at all. A stack's layout is a few hundred bytes;
    this keeps out what is not one (the wrong file read, a setting cut into something else). }
  TyAccordionLayoutMaxLength = 65536;
  { A weight is written with at most five digits. }
  TyAccordionMaxWeight = 99999;

type
  TTyAccordionItemKind = (aikFixed, aikCollapsed, aikExpanded);

  { One child of the stack as the distribution sees it, device px. }
  TTyAccordionItem = record
    Kind: TTyAccordionItemKind;
    Size: Integer;      { aikFixed: its own height. A section: its header's height. }
    MinSize: Integer;   { aikExpanded: the least it is given (header and least body). }
    Weight: Integer;    { aikExpanded: its share of the room; below 1 counts as 1. }
  end;
  TTyAccordionItems = array of TTyAccordionItem;

  TTyAccordionSlot = record
    Top, Height: Integer;
  end;
  TTyAccordionSlots = array of TTyAccordionSlot;

  { One section of a saved layout. }
  TTyAccordionLayoutEntry = record
    Name: string;
    Weight: Integer;
    Collapsed: Boolean;
  end;
  TTyAccordionLayoutDoc = array of TTyAccordionLayoutEntry;

  { A drag strip: the two sections it lies between and its box, client coordinates. }
  TTyAccordionSplitter = record
    Upper, Lower: TTyCustomExPanel;
    Bounds: TRect;
  end;
  TTyAccordionSplitters = array of TTyAccordionSplitter;

  TTyAccordionKids = array of TControl;

  TTyAccordionPlaced = record
    Control: TControl;
    Bounds: TRect;
  end;

  TTyCustomAccordion = class(TTyCustomControl, ITyExPanelHost)
  private
    FMinBodyHeight: Integer;
    FMinBodyExplicit: Boolean;      { False: follow --accordion-min-body-height }
    FInLayout: Boolean;
    FApplying: Boolean;             { weights and states are being set by the stack itself }
    { What the last layout gave each child. The designer's changes are told from it. }
    FPlaced: array of TTyAccordionPlaced;
    FAdopted: TTyAccordionPlaced;   { the last designer change taken, so that it is taken once }
    { The move to a new distribution: where each child started from. }
    FAnimating: Boolean;
    FAnimator: TTyAnimator;
    FAnimFrom: array of TTyAccordionPlaced;
    FTimer: TTimer;
    FHoverSplitter, FDragSplitter: Integer;
    FDragUpper, FDragLower: TTyCustomExPanel;
    FDragUpperH, FDragLowerH, FDragStartY: Integer;
    FDragMoved: Boolean;
    FSplitCursor: TTyCursorLoan;
    FOnLayoutChanged: TNotifyEvent;
    function GetMinBodyHeight: Integer;
    procedure SetMinBodyHeight(AValue: Integer);
    function OwnPPI: Integer;
    function StackKids: TTyAccordionKids;
    function ItemOf(AControl: TControl): TTyAccordionItem;
    function IsOpenSection(AControl: TControl): Boolean;
    function FromOf(AControl: TControl; out ABounds: TRect): Boolean;
    function SplitterStates(AIndex: Integer): TTyStateSet;
    procedure SetHoverSplitter(AIndex: Integer);
    procedure BeginSplitterDrag(AIndex, AY: Integer);
    procedure DragSplitterTo(AY: Integer);
    procedure EndSplitterDrag;
    procedure StopAnimation;
    procedure TimerTick(Sender: TObject);
    { In the designer: a section dragged somewhere else in the stack takes that place, and
      one given another height takes it as its weight. }
    procedure AdoptDesignerChange;
    procedure WeighByHeights;
  protected
    function GetStyleTypeKey: string; override;
    procedure AdjustClientRect(var ARect: TRect); override;
    { Not LCL's alignment: the stack places every child, whatever its Align and Anchors. }
    procedure AlignControls(AControl: TControl; var RemainingClientRect: TRect); override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure CaptureChanged; override;
    { ITyExPanelHost: what the sections tell the stack. }
    procedure SectionToggled(ASection: TTyCustomExPanel);
    procedure SectionChanged(ASection: TTyCustomExPanel);
    procedure SectionKeyDown(ASection: TTyCustomExPanel; var Key: Word; Shift: TShiftState);
    { The least height an expanded section is given, device px: its header and
      MinBodyHeight. Override to give some sections another minimum; the distribution and
      the drag both ask here. }
    function SectionMinHeight(ASection: TTyCustomExPanel): Integer; virtual;
    { Whether a redistribution is eased over time. Without a window, and in the designer,
      the stack goes to its new distribution at once. }
    function CanAnimate: Boolean; virtual;
    { One step of a running redistribution, AMs later. The timer calls it. }
    procedure AnimationStep(AMs: Integer);
    { Where Up and Down on a focused header send the focus. }
    procedure FocusSection(ASection: TTyCustomExPanel); virtual;
    { A section was collapsed or expanded, the user finished dragging a boundary, or a saved
      layout was applied: fires OnLayoutChanged. }
    procedure DoLayoutChanged; virtual;
    { Moves to the distribution the sections now ask for, over ADuration ms. }
    procedure StartRedistribution(ADuration: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure RemoveControl(AControl: TControl); override;
    { Gives every child its place now. LCL asks for it whenever the stack or a child
      changes; code that changed something LCL does not see (the order) calls it. }
    procedure LayoutSections;
    { The room the stack is laid out in: the client area inside the frame. }
    function StackRect: TRect;
    { The sections, in stack order, shown or not. }
    function SectionCount: Integer;
    function Section(AIndex: Integer): TTyCustomExPanel;
    { The section of that Name, or nil when there is none or more than one. }
    function FindSection(const AName: string): TTyCustomExPanel;
    { The next (AForward) or previous section in the stack that is shown and enabled. }
    function NeighbourSection(ASection: TTyCustomExPanel; AForward: Boolean): TTyCustomExPanel;
    { Puts AChild at AIndex among the children (Controls[]), which is the stack's order,
      and lays the stack out. }
    procedure MoveSection(AChild: TControl; AIndex: Integer);
    { The drag strips now on screen, top to bottom. }
    function Splitters: TTyAccordionSplitters;
    function SplitterCount: Integer;
    function SplitterRect(AIndex: Integer): TRect;
    function SplitterAt(X, Y: Integer): Integer;
    { Moves the boundary AIndex by ADelta px (down is positive), as a drag does: within
      the two sections' minimums, and both weights are updated. }
    procedure MoveSplitter(AIndex, ADelta: Integer);
    { Whether a redistribution is on its way. }
    function Animating: Boolean;
    { The sections' weights and collapsed states as one line of text, by component Name:
      'TYACCORDION/1|Name=weight,collapsed|...|end'. A section without a Name, or one that
      shares its Name with another, is left out. }
    function SaveLayoutToString: string;
    { Applies a text SaveLayoutToString wrote. False, and nothing changed: the text is not a
      layout of this format and version, or the stack is being designed or destroyed. A
      leading UTF-8 BOM and trailing white space are let through; the rest is read strictly,
      and a bad text never raises. Names the stack does not have are ignored; sections the
      text does not name keep their state. }
    function LoadLayoutFromString(const AText: string): Boolean;
    { The least body height an expanded section is left with, logical px. Unset (or set
      below 0) it follows --accordion-min-body-height. }
    property MinBodyHeight: Integer read GetMinBodyHeight write SetMinBodyHeight
      stored FMinBodyExplicit;
    property OnLayoutChanged: TNotifyEvent read FOnLayoutChanged write FOnLayoutChanged;
  end;

  { TTyAccordion publishes TTyCustomAccordion's properties; everything lives in
    TTyCustomAccordion. }
  TTyAccordion = class(TTyCustomAccordion)
  published
    property Version;
    property Align;
    property Anchors;
    property BorderSpacing;
    property BorderWidth;
    property Constraints;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
    property ParentShowHint;
    property PopupMenu;
    property TabOrder;
    property TabStop;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseWheel;
    property OnContextPopup;
    property OnResize;
    property OnChangeBounds;
    property OnEnter;
    property OnExit;
    property OnPaint;
    property StyleClass;
    property StyleOverride;
    property Controller;
    property MinBodyHeight;
    property OnLayoutChanged;
  end;

{ PURE, headless-tested. Device px. }

{ The heights and tops of the stack in a room AHeight high. Fixed children and collapsed
  sections take their Size. The expanded sections share the rest -- AHeight less those and
  less ASplitter for every pair of expanded neighbours -- in proportion to their weights,
  and the shares add up to exactly that rest. A section whose share would fall below its
  MinSize gets its MinSize, and the others share what is then left. When even the minimums
  do not fit, every expanded section gets its minimum and the stack is taller than AHeight. }
function TyAccordionDistribute(const AItems: array of TTyAccordionItem;
  AHeight, ASplitter: Integer): TTyAccordionSlots;

{ How far a boundary between an upper section AUpper high and a lower one ALower high can be
  moved when ADelta is asked for (down is positive): neither is taken below its minimum,
  and one that is already below it is not taken further. }
function TyAccordionDragDelta(AUpper, ALower, AMinUpper, AMinLower, ADelta: Integer): Integer;

{ True and ADoc filled when AText is a whole layout; False and ADoc empty otherwise.
  The text is 'TYACCORDION/1', segments, 'end', joined by '|'. A segment is key=value. A key
  that is an identifier is a section's Name and its value is weight,collapsed -- one to five
  digits, then 0 or 1; a Name may be there once (names do not tell case apart). A key that is
  not an identifier belongs to a later version and is skipped. Anything else -- another tag,
  no 'end', an empty segment, a value of another shape -- makes the whole text no layout. }
function TyAccordionLayoutParse(const AText: string; out ADoc: TTyAccordionLayoutDoc): Boolean;
function TyAccordionLayoutFormat(const ADoc: TTyAccordionLayoutDoc): string;
{ AText without what storage adds round it: a UTF-8 BOM in front, white space behind. }
function TyAccordionLayoutUnwrap(const AText: string): string;

implementation

{ ---- pure ---- }

function TyAccordionDistribute(const AItems: array of TTyAccordionItem;
  AHeight, ASplitter: Integer): TTyAccordionSlots;
var
  n, i, y, rest, prev, cur: Integer;
  w, acc, total: Int64;
  pinned: array of Boolean;
  again: Boolean;

  function WeightOf(AIndex: Integer): Int64;
  begin
    Result := AItems[AIndex].Weight;
    if Result < 1 then Result := 1;
  end;

  function SplitterAfter(AIndex: Integer): Boolean;
  begin
    Result := (AIndex < n - 1) and (AItems[AIndex].Kind = aikExpanded)
      and (AItems[AIndex + 1].Kind = aikExpanded);
  end;

begin
  n := Length(AItems);
  Result := nil;
  SetLength(Result, n);
  if n = 0 then Exit;
  if ASplitter < 0 then ASplitter := 0;
  // What is not to share: the fixed heights, the collapsed headers, the drag strips.
  rest := AHeight;
  for i := 0 to n - 1 do
  begin
    if AItems[i].Kind <> aikExpanded then
    begin
      Result[i].Height := AItems[i].Size;
      if Result[i].Height < 0 then Result[i].Height := 0;
      Dec(rest, Result[i].Height);
    end;
    if SplitterAfter(i) then Dec(rest, ASplitter);
  end;
  pinned := nil;
  SetLength(pinned, n);
  { A section whose share is under its minimum is pinned at the minimum, which takes room
    from the others -- so the shares are worked out again, until nobody is under. Each round
    pins at least one, so it ends; and when not even the minimums fit, it ends with every
    section pinned at its minimum and the stack taller than the room. }
  repeat
    again := False;
    total := 0;
    for i := 0 to n - 1 do
      if (AItems[i].Kind = aikExpanded) and not pinned[i] then Inc(total, WeightOf(i));
    for i := 0 to n - 1 do
      if (AItems[i].Kind = aikExpanded) and not pinned[i]
         and (rest * WeightOf(i) < Int64(AItems[i].MinSize) * total) then
      begin
        pinned[i] := True;
        Result[i].Height := AItems[i].MinSize;
        again := True;
      end;
    if again then
    begin
      rest := AHeight;
      for i := 0 to n - 1 do
      begin
        if (AItems[i].Kind <> aikExpanded) or pinned[i] then Dec(rest, Result[i].Height);
        if SplitterAfter(i) then Dec(rest, ASplitter);
      end;
    end;
  until not again;
  { The shares, rounded so that they add up to the rest exactly: each boundary is rounded,
    not each height, and a height is the difference of two boundaries. }
  acc := 0;
  prev := 0;
  for i := 0 to n - 1 do
    if (AItems[i].Kind = aikExpanded) and not pinned[i] then
    begin
      w := WeightOf(i);
      Inc(acc, w);
      cur := (Int64(rest) * acc * 2 + total) div (total * 2);
      Result[i].Height := cur - prev;
      prev := cur;
    end;
  y := 0;
  for i := 0 to n - 1 do
  begin
    Result[i].Top := y;
    Inc(y, Result[i].Height);
    if SplitterAfter(i) then Inc(y, ASplitter);
  end;
end;

function TyAccordionDragDelta(AUpper, ALower, AMinUpper, AMinLower, ADelta: Integer): Integer;
var
  lo, hi: Integer;
begin
  lo := AMinUpper - AUpper;   // how far up: until the upper one is at its minimum
  if lo > 0 then lo := 0;
  hi := ALower - AMinLower;   // how far down: until the lower one is at its minimum
  if hi < 0 then hi := 0;
  Result := ADelta;
  if Result < lo then Result := lo;
  if Result > hi then Result := hi;
end;

function TyAccordionLayoutUnwrap(const AText: string): string;
const
  Bom = #$EF#$BB#$BF;
var
  first, last: Integer;
begin
  first := 1;
  if Copy(AText, 1, Length(Bom)) = Bom then first := Length(Bom) + 1;
  last := Length(AText);
  while (last >= first) and (AText[last] in [#9, #10, #13, ' ']) do Dec(last);
  Result := Copy(AText, first, last - first + 1);
end;

{ Split at ASep, empty parts kept. }
function SplitPlain(const S: string; ASep: Char): TStringArray;
var
  i, start, n: Integer;
begin
  n := 1;
  for i := 1 to Length(S) do
    if S[i] = ASep then Inc(n);
  Result := nil;
  SetLength(Result, n);
  n := 0;
  start := 1;
  for i := 1 to Length(S) + 1 do
    if (i > Length(S)) or (S[i] = ASep) then
    begin
      Result[n] := Copy(S, start, i - start);
      Inc(n);
      start := i + 1;
    end;
end;

{ One to five digits and nothing else: no sign, no blank, no '$'. }
function IsWeightDigits(const S: string): Boolean;
var
  i: Integer;
begin
  Result := (Length(S) >= 1) and (Length(S) <= 5);
  if not Result then Exit;
  for i := 1 to Length(S) do
    if not (S[i] in ['0'..'9']) then Exit(False);
end;

function TyAccordionLayoutParse(const AText: string; out ADoc: TTyAccordionLayoutDoc): Boolean;
var
  segs, parts: TStringArray;
  doc: TTyAccordionLayoutDoc;
  i, j, p, n: Integer;
  key, value: string;
begin
  ADoc := nil;
  Result := False;
  if Length(AText) > TyAccordionLayoutMaxLength then Exit;
  segs := SplitPlain(AText, '|');
  if Length(segs) < 2 then Exit;
  if segs[0] <> TyAccordionLayoutTag then Exit;
  // A text cut short does not end in 'end', and 'end' is nowhere but at the end.
  if segs[High(segs)] <> 'end' then Exit;
  doc := nil;
  n := 0;
  SetLength(doc, Length(segs));
  for i := 1 to High(segs) - 1 do
  begin
    if (segs[i] = '') or (segs[i] = 'end') then Exit;
    p := Pos('=', segs[i]);
    if p <= 1 then Exit;
    key := Copy(segs[i], 1, p - 1);
    value := Copy(segs[i], p + 1, MaxInt);
    // Not a component name: a key of a later version. Skipped, whatever its value.
    if not IsValidIdent(key, True, True) then Continue;
    parts := SplitPlain(value, ',');
    if Length(parts) <> 2 then Exit;
    if not IsWeightDigits(parts[0]) then Exit;
    if (parts[1] <> '0') and (parts[1] <> '1') then Exit;
    for j := 0 to n - 1 do
      if CompareText(doc[j].Name, key) = 0 then Exit;
    doc[n].Name := key;
    doc[n].Weight := StrToInt(parts[0]);
    doc[n].Collapsed := parts[1] = '1';
    Inc(n);
  end;
  SetLength(doc, n);
  ADoc := doc;
  Result := True;
end;

function TyAccordionLayoutFormat(const ADoc: TTyAccordionLayoutDoc): string;
var
  i: Integer;
begin
  Result := TyAccordionLayoutTag;
  for i := 0 to High(ADoc) do
    Result := Result + '|' + Format('%s=%d,%d', [ADoc[i].Name, ADoc[i].Weight,
      Ord(ADoc[i].Collapsed)]);
  Result := Result + '|end';
end;

{ ---- TTyCustomAccordion ---- }

constructor TTyCustomAccordion.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls];
  AccessibleRole := larGroup;   // a container, as TTyPanel says of itself
  FMinBodyHeight := TyAccordionMinBodyDef;   { fallback; unused while not explicit }
  FMinBodyExplicit := False;
  FHoverSplitter := -1;
  FDragSplitter := -1;
  FAnimator := TyAnimatorInit(0, teEaseOutCubic);
  FAnimator.SetTargetImmediate(1);
  Width := 200;
  Height := 300;
end;

destructor TTyCustomAccordion.Destroy;
begin
  // The timer first, so that it cannot fire into a stack that is being taken down.
  FreeAndNil(FTimer);
  inherited Destroy;
end;

function TTyCustomAccordion.GetStyleTypeKey: string;
begin
  Result := 'TyAccordion';
end;

function TTyCustomAccordion.OwnPPI: Integer;
begin
  Result := Font.PixelsPerInch;
  if Result <= 0 then Result := 96;
end;

function TTyCustomAccordion.GetMinBodyHeight: Integer;
begin
  if FMinBodyExplicit then
    Result := FMinBodyHeight
  else
    Result := StyleMetric(TyAccordionMinBodyVar, TyAccordionMinBodyDef);
  if Result < 0 then Result := 0;
end;

procedure TTyCustomAccordion.SetMinBodyHeight(AValue: Integer);
var
  was: Integer;
begin
  was := GetMinBodyHeight;
  // Below 0 gives it back to the theme; anything else is the form's own value, and stored.
  FMinBodyExplicit := AValue >= 0;
  if FMinBodyExplicit then FMinBodyHeight := AValue;
  if GetMinBodyHeight <> was then LayoutSections;
end;

function TTyCustomAccordion.SectionMinHeight(ASection: TTyCustomExPanel): Integer;
begin
  Result := ASection.HeaderHeightPx + MulDiv(GetMinBodyHeight, OwnPPI, 96);
end;

procedure TTyCustomAccordion.AdjustClientRect(var ARect: TRect);
var
  S: TTyStyleSet;
  bw: Integer;
begin
  inherited AdjustClientRect(ARect);
  // The sections stay off the frame's border, which is stroked inside the control.
  S := CurrentStyle;
  if TyBorderVisible(S) then bw := MulDiv(S.BorderWidth, OwnPPI, 96) else bw := 0;
  if bw > 0 then InflateRect(ARect, -bw, -bw);
  if ARect.Right < ARect.Left then ARect.Right := ARect.Left;
  if ARect.Bottom < ARect.Top then ARect.Bottom := ARect.Top;
end;

function TTyCustomAccordion.StackRect: TRect;
begin
  Result := ClientRect;
  AdjustClientRect(Result);
end;

function TTyCustomAccordion.StackKids: TTyAccordionKids;
var
  i, n: Integer;
begin
  Result := nil;
  SetLength(Result, ControlCount);
  n := 0;
  for i := 0 to ControlCount - 1 do
    if Controls[i].IsControlVisible then
    begin
      Result[n] := Controls[i];
      Inc(n);
    end;
  SetLength(Result, n);
end;

function TTyCustomAccordion.IsOpenSection(AControl: TControl): Boolean;
begin
  Result := (AControl is TTyCustomExPanel) and not TTyCustomExPanel(AControl).Collapsed;
end;

function TTyCustomAccordion.ItemOf(AControl: TControl): TTyAccordionItem;
var
  sec: TTyCustomExPanel;
begin
  Result := Default(TTyAccordionItem);
  if AControl is TTyCustomExPanel then
  begin
    sec := TTyCustomExPanel(AControl);
    Result.Size := sec.HeaderHeightPx;
    if sec.Collapsed then
      Result.Kind := aikCollapsed
    else
    begin
      Result.Kind := aikExpanded;
      Result.Weight := sec.ExpandedHeight;
      Result.MinSize := SectionMinHeight(sec);
    end;
  end
  else
  begin
    Result.Kind := aikFixed;
    Result.Size := AControl.Height;
  end;
end;

function TTyCustomAccordion.FromOf(AControl: TControl; out ABounds: TRect): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(FAnimFrom) do
    if FAnimFrom[i].Control = AControl then
    begin
      ABounds := FAnimFrom[i].Bounds;
      Exit(True);
    end;
  ABounds := Rect(0, 0, 0, 0);
  Result := False;
end;

procedure TTyCustomAccordion.LayoutSections;
var
  kids: TTyAccordionKids;
  items: TTyAccordionItems;
  slots: TTyAccordionSlots;
  cr, r, from, was: TRect;
  i: Integer;
  t: Single;
  moved: Boolean;
begin
  if FInLayout or ([csDestroying, csLoading] * ComponentState <> []) then Exit;
  FInLayout := True;
  moved := False;
  try
    cr := StackRect;
    kids := StackKids;
    items := nil;
    SetLength(items, Length(kids));
    for i := 0 to High(kids) do items[i] := ItemOf(kids[i]);
    slots := TyAccordionDistribute(items, cr.Bottom - cr.Top,
      MulDiv(StyleMetric(TyAccordionSplitterVar, TyAccordionSplitterDef), OwnPPI, 96));
    SetLength(FPlaced, Length(kids));
    t := FAnimator.Eased;
    for i := 0 to High(kids) do
    begin
      r := Bounds(cr.Left, cr.Top + slots[i].Top, cr.Right - cr.Left, slots[i].Height);
      { On its way to a new distribution each child is between where it started and where
        it is going: its top and its bottom each, so the stack stays whole on the way. }
      if FAnimating and FromOf(kids[i], from) then
      begin
        r.Top := TyLerpI(from.Top, r.Top, t);
        r.Bottom := TyLerpI(from.Bottom, r.Bottom, t);
      end;
      was := kids[i].BoundsRect;
      kids[i].SetBounds(r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top);
      FPlaced[i].Control := kids[i];
      FPlaced[i].Bounds := kids[i].BoundsRect;
      if not EqualRect(was, FPlaced[i].Bounds) then moved := True;
    end;
  finally
    FInLayout := False;
  end;
  if moved then Invalidate;   // the strips between the sections moved with them
end;

procedure TTyCustomAccordion.AlignControls(AControl: TControl; var RemainingClientRect: TRect);
begin
  { Not inherited. Placing a child comes back here (LayoutSections guards itself). }
  if FInLayout then Exit;
  AdoptDesignerChange;
  LayoutSections;
end;

procedure TTyCustomAccordion.AdoptDesignerChange;
var
  i, j, pos, centre, target: Integer;
  moved: TControl;
  was, cur: TRect;
  others: array of TControl;
begin
  if not (csDesigning in ComponentState) or FAnimating
     or ([csLoading, csDestroying] * ComponentState <> []) then Exit;
  { The one child whose bounds are no longer what the stack gave it was changed in the
    designer. One, and once: a child that will not take the place it is given (its own
    Constraints) would otherwise be taken for a new change on every pass. }
  moved := nil;
  for i := 0 to High(FPlaced) do
    if (GetControlIndex(FPlaced[i].Control) >= 0)
       and not EqualRect(FPlaced[i].Control.BoundsRect, FPlaced[i].Bounds) then
    begin
      if moved <> nil then Exit;   // more than one: a layout pass of LCL's, not a gesture
      moved := FPlaced[i].Control;
      was := FPlaced[i].Bounds;
    end;
  if moved = nil then Exit;
  cur := moved.BoundsRect;
  if (FAdopted.Control = moved) and EqualRect(FAdopted.Bounds, cur) then Exit;
  FAdopted.Control := moved;
  FAdopted.Bounds := cur;
  if cur.Top <> was.Top then
  begin
    { Dragged: it goes where its middle now is among the others. }
    centre := (cur.Top + cur.Bottom) div 2;
    others := nil;
    pos := 0;
    for i := 0 to High(FPlaced) do
      if (FPlaced[i].Control <> moved) and (GetControlIndex(FPlaced[i].Control) >= 0) then
      begin
        j := Length(others);
        SetLength(others, j + 1);
        others[j] := FPlaced[i].Control;
        if (FPlaced[i].Bounds.Top + FPlaced[i].Bounds.Bottom) div 2 < centre then pos := j + 1;
      end;
    if Length(others) = 0 then Exit;
    // Before the child that is now at that place, or after the last one.
    if pos < Length(others) then
    begin
      target := GetControlIndex(others[pos]);
      if GetControlIndex(moved) < target then Dec(target);
    end
    else
    begin
      target := GetControlIndex(others[High(others)]);
      if GetControlIndex(moved) > target then Inc(target);
    end;
    SetControlIndex(moved, target);
  end
  else if (cur.Bottom - cur.Top <> was.Bottom - was.Top) and IsOpenSection(moved) then
    // Resized: its new height is its weight, on the scale of the heights the others have.
    WeighByHeights;
end;

procedure TTyCustomAccordion.WeighByHeights;
var
  i: Integer;
  sec: TTyCustomExPanel;
  oldSum, newSum, w: Int64;
begin
  { The weights go onto the scale of the heights on screen: every open section's weight
    becomes its height, and a section that is not sharing now (collapsed, hidden) keeps its
    proportion to those that are. From here a pixel is a unit of weight, and the layout
    gives back exactly these heights -- also where a minimum was holding a section above
    its share. }
  oldSum := 0;
  newSum := 0;
  for i := 0 to ControlCount - 1 do
    if IsOpenSection(Controls[i]) and Controls[i].IsControlVisible then
    begin
      w := TTyCustomExPanel(Controls[i]).ExpandedHeight;
      if w < 1 then w := 1;
      Inc(oldSum, w);
      Inc(newSum, Controls[i].Height);
    end;
  if (oldSum < 1) or (newSum < 1) then Exit;
  FApplying := True;
  try
    for i := 0 to ControlCount - 1 do
      if Controls[i] is TTyCustomExPanel then
      begin
        sec := TTyCustomExPanel(Controls[i]);
        if IsOpenSection(sec) and sec.IsControlVisible then
          w := sec.Height
        else
        begin
          w := sec.ExpandedHeight;
          if w < 1 then w := 1;
          w := (w * newSum + oldSum div 2) div oldSum;
        end;
        if w < 1 then w := 1;
        sec.ExpandedHeight := w;
      end;
  finally
    FApplying := False;
  end;
end;

procedure TTyCustomAccordion.RemoveControl(AControl: TControl);
var
  i, n: Integer;
begin
  { Nothing remembered may outlive the child. What is kept is its address, and the heap hands
    a freed address out again: the next section made would be taken for this one -- found
    "moved" by the designer's check, or eased in from where this one stood. }
  n := 0;
  for i := 0 to High(FPlaced) do
    if FPlaced[i].Control <> AControl then
    begin
      FPlaced[n] := FPlaced[i];
      Inc(n);
    end;
  SetLength(FPlaced, n);
  n := 0;
  for i := 0 to High(FAnimFrom) do
    if FAnimFrom[i].Control <> AControl then
    begin
      FAnimFrom[n] := FAnimFrom[i];
      Inc(n);
    end;
  SetLength(FAnimFrom, n);
  if FAdopted.Control = AControl then FAdopted.Control := nil;
  if (AControl = FDragUpper) or (AControl = FDragLower) then
  begin
    FDragSplitter := -1;
    FDragUpper := nil;
    FDragLower := nil;
  end;
  inherited RemoveControl(AControl);
end;

{ ---- the sections ---- }

function TTyCustomAccordion.SectionCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to ControlCount - 1 do
    if Controls[i] is TTyCustomExPanel then Inc(Result);
end;

function TTyCustomAccordion.Section(AIndex: Integer): TTyCustomExPanel;
var
  i: Integer;
begin
  for i := 0 to ControlCount - 1 do
    if Controls[i] is TTyCustomExPanel then
    begin
      if AIndex = 0 then Exit(TTyCustomExPanel(Controls[i]));
      Dec(AIndex);
    end;
  Result := nil;
end;

function TTyCustomAccordion.FindSection(const AName: string): TTyCustomExPanel;
var
  i: Integer;
begin
  Result := nil;
  if AName = '' then Exit;
  for i := 0 to ControlCount - 1 do
    if (Controls[i] is TTyCustomExPanel) and (CompareText(Controls[i].Name, AName) = 0) then
    begin
      if Result <> nil then Exit(nil);   // two of that name: neither is meant
      Result := TTyCustomExPanel(Controls[i]);
    end;
end;

function TTyCustomAccordion.NeighbourSection(ASection: TTyCustomExPanel;
  AForward: Boolean): TTyCustomExPanel;
var
  kids: TTyAccordionKids;
  i, at, step: Integer;
begin
  Result := nil;
  kids := StackKids;
  at := -1;
  for i := 0 to High(kids) do
    if kids[i] = ASection then at := i;
  if at < 0 then Exit;
  if AForward then step := 1 else step := -1;
  i := at + step;
  while (i >= 0) and (i <= High(kids)) do
  begin
    if (kids[i] is TTyCustomExPanel) and kids[i].Enabled then
      Exit(TTyCustomExPanel(kids[i]));
    Inc(i, step);
  end;
end;

procedure TTyCustomAccordion.MoveSection(AChild: TControl; AIndex: Integer);
begin
  if (AChild = nil) or (AChild.Parent <> Self) then Exit;
  SetControlIndex(AChild, AIndex);
  // LCL moves the child in the list and asks for no layout.
  LayoutSections;
end;

{ ---- what the sections tell the stack (ITyExPanelHost) ---- }

procedure TTyCustomAccordion.SectionToggled(ASection: TTyCustomExPanel);
begin
  if FApplying or (csLoading in ComponentState) then Exit;
  StartRedistribution(ASection.AnimationDuration);
  DoLayoutChanged;
end;

procedure TTyCustomAccordion.SectionChanged(ASection: TTyCustomExPanel);
begin
  if FApplying or (csLoading in ComponentState) then Exit;
  LayoutSections;
end;

procedure TTyCustomAccordion.SectionKeyDown(ASection: TTyCustomExPanel; var Key: Word;
  Shift: TShiftState);
var
  target: TTyCustomExPanel;
begin
  if Shift * [ssShift, ssCtrl, ssAlt, ssMeta] <> [] then Exit;
  case Key of
    VK_UP:   target := NeighbourSection(ASection, False);
    VK_DOWN: target := NeighbourSection(ASection, True);
  else
    Exit;
  end;
  if target <> nil then FocusSection(target);
  { Taken at either end of the stack too: left to LCL, the arrow would move the focus to
    whatever control comes next, out of the headers. }
  Key := 0;
end;

procedure TTyCustomAccordion.FocusSection(ASection: TTyCustomExPanel);
begin
  if ASection.CanSetFocus then ASection.SetFocus;
end;

procedure TTyCustomAccordion.DoLayoutChanged;
begin
  if Assigned(FOnLayoutChanged) then FOnLayoutChanged(Self);
end;

{ ---- the move to a new distribution ---- }

function TTyCustomAccordion.CanAnimate: Boolean;
begin
  Result := HandleAllocated and not (csDesigning in ComponentState);
end;

function TTyCustomAccordion.Animating: Boolean;
begin
  Result := FAnimating;
end;

procedure TTyCustomAccordion.StopAnimation;
begin
  FAnimating := False;
  FAnimFrom := nil;
  FAnimator.SetTargetImmediate(1);
  if FTimer <> nil then FTimer.Enabled := False;
end;

procedure TTyCustomAccordion.StartRedistribution(ADuration: Integer);
var
  kids: TTyAccordionKids;
  i: Integer;
begin
  if (ADuration > 0) and CanAnimate then
  begin
    { From where every child is now -- which, when a move is already on its way, is
      somewhere in between: the new move starts there. }
    kids := StackKids;
    SetLength(FAnimFrom, Length(kids));
    for i := 0 to High(kids) do
    begin
      FAnimFrom[i].Control := kids[i];
      FAnimFrom[i].Bounds := kids[i].BoundsRect;
    end;
    FAnimator := TyAnimatorInit(ADuration, teEaseOutCubic);
    FAnimating := True;
    if FTimer = nil then
    begin
      FTimer := TTimer.Create(Self);
      FTimer.Enabled := False;
      FTimer.Interval := 16;   // ~60fps
      FTimer.OnTimer := @TimerTick;
    end;
    FTimer.Enabled := True;
  end
  else
    StopAnimation;
  LayoutSections;
end;

procedure TTyCustomAccordion.AnimationStep(AMs: Integer);
begin
  if not FAnimating then Exit;
  FAnimator.Advance(AMs);
  if not FAnimator.Running then StopAnimation;
  LayoutSections;
end;

procedure TTyCustomAccordion.TimerTick(Sender: TObject);
begin
  AnimationStep(FTimer.Interval);
end;

{ ---- the drag strips ---- }

function TTyCustomAccordion.Splitters: TTyAccordionSplitters;
var
  kids: TTyAccordionKids;
  cr, r: TRect;
  i, n: Integer;
begin
  Result := nil;
  cr := StackRect;
  kids := StackKids;
  SetLength(Result, Length(kids));
  n := 0;
  // Read off where the children are, so a strip is where it is seen, on the way too.
  for i := 0 to High(kids) - 1 do
    if IsOpenSection(kids[i]) and IsOpenSection(kids[i + 1]) then
    begin
      r := Rect(cr.Left, kids[i].Top + kids[i].Height, cr.Right, kids[i + 1].Top);
      if r.Bottom <= r.Top then Continue;
      Result[n].Upper := TTyCustomExPanel(kids[i]);
      Result[n].Lower := TTyCustomExPanel(kids[i + 1]);
      Result[n].Bounds := r;
      Inc(n);
    end;
  SetLength(Result, n);
end;

function TTyCustomAccordion.SplitterCount: Integer;
begin
  Result := Length(Splitters);
end;

function TTyCustomAccordion.SplitterRect(AIndex: Integer): TRect;
var
  list: TTyAccordionSplitters;
begin
  list := Splitters;
  if (AIndex >= 0) and (AIndex <= High(list)) then Result := list[AIndex].Bounds
  else Result := Rect(0, 0, 0, 0);
end;

function TTyCustomAccordion.SplitterAt(X, Y: Integer): Integer;
var
  list: TTyAccordionSplitters;
  i: Integer;
begin
  list := Splitters;
  for i := 0 to High(list) do
    if PtInRect(list[i].Bounds, Point(X, Y)) then Exit(i);
  Result := -1;
end;

function TTyCustomAccordion.SplitterStates(AIndex: Integer): TTyStateSet;
begin
  if not IsEnabled then Exit([tysDisabled]);
  Result := [];
  if AIndex = FHoverSplitter then Include(Result, tysHover);
  if AIndex = FDragSplitter then Include(Result, tysActive);
  if Result = [] then Result := [tysNormal];
end;

procedure TTyCustomAccordion.SetHoverSplitter(AIndex: Integer);
begin
  if FHoverSplitter = AIndex then Exit;
  FHoverSplitter := AIndex;
  // #154: the size cursor is lent while the pointer is on a strip, the own one given back.
  TyLendCursor(Self, FSplitCursor, AIndex >= 0, crVSplit);
  Invalidate;
end;

procedure TTyCustomAccordion.BeginSplitterDrag(AIndex, AY: Integer);
var
  list: TTyAccordionSplitters;
begin
  StopAnimation;
  LayoutSections;
  list := Splitters;
  if (AIndex < 0) or (AIndex > High(list)) then Exit;
  // A pixel of drag is a unit of weight from here on.
  WeighByHeights;
  FDragSplitter := AIndex;
  FDragUpper := list[AIndex].Upper;
  FDragLower := list[AIndex].Lower;
  FDragUpperH := FDragUpper.Height;
  FDragLowerH := FDragLower.Height;
  FDragStartY := AY;
  FDragMoved := False;
  Invalidate;
end;

procedure TTyCustomAccordion.DragSplitterTo(AY: Integer);
var
  d: Integer;
begin
  if (FDragSplitter < 0) or (FDragUpper = nil) or (FDragLower = nil) then Exit;
  d := TyAccordionDragDelta(FDragUpperH, FDragLowerH, SectionMinHeight(FDragUpper),
    SectionMinHeight(FDragLower), AY - FDragStartY);
  if FDragUpper.ExpandedHeight = FDragUpperH + d then Exit;
  FApplying := True;
  try
    FDragUpper.ExpandedHeight := FDragUpperH + d;
    FDragLower.ExpandedHeight := FDragLowerH - d;
  finally
    FApplying := False;
  end;
  FDragMoved := True;
  LayoutSections;
end;

procedure TTyCustomAccordion.EndSplitterDrag;
var
  moved: Boolean;
begin
  if FDragSplitter < 0 then Exit;
  moved := FDragMoved;
  FDragSplitter := -1;
  FDragUpper := nil;
  FDragLower := nil;
  FDragMoved := False;
  Invalidate;
  if moved then DoLayoutChanged;
end;

procedure TTyCustomAccordion.MoveSplitter(AIndex, ADelta: Integer);
begin
  BeginSplitterDrag(AIndex, 0);
  DragSplitterTo(ADelta);
  EndSplitterDrag;
end;

procedure TTyCustomAccordion.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  i: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (Button = mbLeft) and IsEnabled then
  begin
    i := SplitterAt(X, Y);
    if i >= 0 then BeginSplitterDrag(i, Y);
  end;
end;

procedure TTyCustomAccordion.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FDragSplitter >= 0 then
    DragSplitterTo(Y)
  else if IsEnabled then
    SetHoverSplitter(SplitterAt(X, Y));
end;

procedure TTyCustomAccordion.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    EndSplitterDrag;
    SetHoverSplitter(SplitterAt(X, Y));
  end;
end;

procedure TTyCustomAccordion.MouseLeave;
begin
  inherited MouseLeave;
  if FDragSplitter < 0 then SetHoverSplitter(-1);
end;

procedure TTyCustomAccordion.CaptureChanged;
begin
  inherited CaptureChanged;
  // The mouse was taken away in the middle of a drag (a dialog, Alt+Tab): the drag is over.
  if (FDragSplitter >= 0) and (GetCaptureControl <> Self) then EndSplitterDrag;
end;

{ ---- paint ---- }

procedure TTyCustomAccordion.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, strip: TTyStyleSet;
  list: TTyAccordionSplitters;
  i: Integer;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top), S);
    { The strips: nothing of their own at rest in the built-in theme (the container's
      surface shows), a fill when 'TyAccordionSplitter' resolves one -- under the pointer,
      while dragged. }
    list := Splitters;
    for i := 0 to High(list) do
    begin
      strip := PartStyle(TyAccordionSplitterKey, StyleClass, SplitterStates(i), False);
      if (tpBackground in strip.Present) and (strip.Background.Kind <> tfkNone) then
        P.FillBackground(list[i].Bounds, strip.Background, 0);
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCustomAccordion.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

{ ---- the saved layout ---- }

function TTyCustomAccordion.SaveLayoutToString: string;
var
  doc: TTyAccordionLayoutDoc;
  i, n, w: Integer;
  sec: TTyCustomExPanel;
begin
  doc := nil;
  SetLength(doc, SectionCount);
  n := 0;
  for i := 0 to SectionCount - 1 do
  begin
    sec := Section(i);
    { What is written has to read back: a section with no Name cannot be found again, and
      one that shares its Name with another would make the text a duplicate. }
    if (sec.Name = '') or not IsValidIdent(sec.Name, True, True)
       or (FindSection(sec.Name) <> sec) then Continue;
    w := sec.ExpandedHeight;
    if w < 1 then w := 1;
    if w > TyAccordionMaxWeight then w := TyAccordionMaxWeight;
    doc[n].Name := sec.Name;
    doc[n].Weight := w;
    doc[n].Collapsed := sec.Collapsed;
    Inc(n);
  end;
  SetLength(doc, n);
  Result := TyAccordionLayoutFormat(doc);
end;

function TTyCustomAccordion.LoadLayoutFromString(const AText: string): Boolean;
var
  doc: TTyAccordionLayoutDoc;
  i, w: Integer;
  sec: TTyCustomExPanel;
begin
  Result := False;
  if [csDesigning, csDestroying] * ComponentState <> [] then Exit;
  if not TyAccordionLayoutParse(TyAccordionLayoutUnwrap(AText), doc) then Exit;
  { One layout at the end, not one per section and no easing: the stack opens as it was
    saved. The sections' own OnCollapse / OnExpand fire as their state changes. }
  StopAnimation;
  FApplying := True;
  try
    for i := 0 to High(doc) do
    begin
      sec := FindSection(doc[i].Name);
      if sec = nil then Continue;
      w := doc[i].Weight;
      if w < 1 then w := 1;
      sec.ExpandedHeight := w;
      sec.Collapsed := doc[i].Collapsed;
    end;
  finally
    FApplying := False;
  end;
  LayoutSections;
  DoLayoutChanged;
  Result := True;
end;

end.
