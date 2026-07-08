unit tyControls.RelativePanel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, LCLType,
  tyControls.Types, tyControls.Base, tyControls.Panel;

type
  { A single relative-layout rule flag. A child's rule set is a SET of these;
    the solver reads them to compute the child's Left/Top from siblings + parent.

      Sibling-relative POSITION (place this child just past that sibling, offset by spacing):
        trRightOf   — this child's LEFT edge = sibling.Right + spacing
        trLeftOf    — this child's RIGHT edge = sibling.Left - spacing (so Left = that - Width)
        trBelow     — this child's TOP edge = sibling.Bottom + spacing
        trAbove     — this child's BOTTOM edge = sibling.Top - spacing (so Top = that - Height)

      Sibling EDGE-ALIGN (share an edge with that sibling, no spacing):
        traAlignLeftOf   — this.Left  = sibling.Left
        traAlignRightOf  — this.Right = sibling.Right (Left = sibling.Right - Width)
        traAlignTopOf    — this.Top   = sibling.Top
        traAlignBottomOf — this.Bottom= sibling.Bottom (Top = sibling.Bottom - Height)

      PARENT-ALIGN (pin to the parent's content edge):
        traAlignParentLeft / Right / Top / Bottom

      CENTERING (in the parent):
        traCenterHorizontal / traCenterVertical / traCenterInParent (= both) }
  TTyRelativeRule = (
    trRightOf, trLeftOf, trBelow, trAbove,
    traAlignLeftOf, traAlignRightOf, traAlignTopOf, traAlignBottomOf,
    traAlignParentLeft, traAlignParentRight, traAlignParentTop, traAlignParentBottom,
    traCenterHorizontal, traCenterVertical, traCenterInParent);
  TTyRelativeRules = set of TTyRelativeRule;

  { The four rules that reference a SIBLING for horizontal position/edge. }
  { The four rules that reference a SIBLING for vertical position/edge. }

  { A resolved rule set for ONE item: its own desired size, the set of rule flags,
    and the sibling it anchors to (a control id; -1 = no sibling / parent-only rules).
    Used both by the control (keyed by TControl) and the pure solver (keyed by an
    integer id so the solver is testable with no controls at all). }
  TTyRelativeItem = record
    Id: Integer;        // this item's own id (>= 0). Unique within the items array.
    W, H: Integer;      // this item's desired width/height (kept as-is by the solver)
    Rules: TTyRelativeRules;
    AnchorId: Integer;  // the sibling this item's sibling-rules reference (-1 = none)
  end;
  TTyRelativeItemArray = array of TTyRelativeItem;

  { The solved position of ONE item (its computed Left/Top; W/H are unchanged). }
  TTyRelativePos = record
    Left, Top: Integer;
  end;
  TTyRelativePosArray = array of TTyRelativePos;

{ --- Pure, headless-tested relative-layout solver -------------------------------- }

{ Solve the relative layout for AItems inside AParent (the content rect: usually the
  padded interior), separating siblings by ASpacing px on the position rules.

  For each item it returns a resolved (Left, Top). Rules are applied in this precedence
  (later wins within an axis, matching Android/WinUI): start at the parent origin, then
  parent-align, then center, then sibling edge-align, then sibling position.

  DETERMINISTIC and CYCLE-SAFE:
    * Items are placed in DEPENDENCY (topological) order: an item that references a
      sibling is solved AFTER that sibling, so the sibling's box is already known.
    * A dependency CYCLE (A anchors B, B anchors A) cannot be ordered — every item still
      in a cycle is placed at the parent origin (its parent-align/center rules still apply;
      only its unresolvable sibling rules are dropped). Never infinite-loops.
    * An AnchorId that matches no item id is treated as NO sibling (the sibling rules for
      that item are ignored; parent/center rules still apply).

  The result array is parallel to AItems (same length, same order). }
function TyRelativeSolve(const AItems: TTyRelativeItemArray; const AParent: TRect;
  ASpacing: Integer): TTyRelativePosArray;

type
  { TTyRelativePanel — an anchor-to-sibling relative-layout container.

    Subclasses TTyPanel (reuses the 'TyPanel' typeKey; NO new .tycss — the themed
    frame/border/radius/padding all come from TyPanel). Hosts arbitrary design/code
    child controls; each child may be given a rule set via SetRules(child, rules[, anchor]).

    On Resize (and after any rule change) it runs the pure TyRelativeSolve over its
    children and SetBounds each — every child keeps its OWN current Width/Height; the
    panel only computes Left/Top from the rules. Children without rules keep their own
    position (they are solved with an empty rule set = parent origin only, which for an
    unruled child would move it to (0,0); to preserve a plain child's designed position,
    an item with NO rules at all is left where it is — see PerformLayout).

    Per-child rule data lives in an internal list keyed by the child TControl; a freed
    child drops its entry via Notification(opRemove). }
  TTyRelativePanel = class(TTyPanel)
  private
    FItems: TFPList;          // of PRelChildRec (owned)
    FSpacing: Integer;        // px between siblings on the position rules
    FInLayout: Boolean;       // reentrancy guard (SetBounds -> Resize -> PerformLayout)
    function FindRec(AControl: TControl): Pointer;   // PRelChildRec or nil
    function RemoveRec(AControl: TControl): Boolean;  // True if one was removed
    procedure SetSpacing(AValue: Integer);
    function ContentRect: TRect;   // interior after theme padding, in client coords
  protected
    procedure Resize; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function GetStyleTypeKey: string; override;

    { Assign (or replace) the rule set for AControl. AAnchor is the SIBLING control the
      sibling-relative rules (RightOf/LeftOf/Above/Below/AlignLeftOf/…) reference; pass
      nil when only parent/center rules are used. AControl must be a child of this panel.
      Re-runs the layout. Passing an empty rule set clears the child's rules (it then
      keeps its own position). }
    procedure SetRules(AControl: TControl; ARules: TTyRelativeRules; AAnchor: TControl = nil);
    { The current rule set for AControl (empty set if it has none). }
    function GetRules(AControl: TControl): TTyRelativeRules;
    { The current anchor sibling for AControl (nil if none / no rules). }
    function GetAnchor(AControl: TControl): TControl;
    { Remove AControl's rules entirely (it then keeps its own position). }
    procedure ClearRules(AControl: TControl);
    { Re-solve and reposition all ruled children. Called automatically on Resize and on
      every rule change; call manually after you move/resize children in code. }
    procedure PerformLayout;
    { Number of children that currently carry a rule set. Exposed for tests. }
    function RuledChildCount: Integer;
  published
    { Gap in px inserted between siblings on the position rules (RightOf/LeftOf/Above/
      Below). Edge-align and parent-align rules are NOT offset by it. }
    property Spacing: Integer read FSpacing write SetSpacing default 8;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

const
  SiblingHRules = [trRightOf, trLeftOf, traAlignLeftOf, traAlignRightOf];
  SiblingVRules = [trBelow, trAbove, traAlignTopOf, traAlignBottomOf];
  AllSiblingRules = SiblingHRules + SiblingVRules;

type
  PRelChildRec = ^TRelChildRec;
  TRelChildRec = record
    Control: TControl;
    Rules: TTyRelativeRules;
    Anchor: TControl;   // sibling reference (nil = none)
  end;

{ --- Pure solver ----------------------------------------------------------------- }

{ Find the array INDEX of the item whose Id = AId, or -1. }
function IndexOfId(const AItems: TTyRelativeItemArray; AId: Integer): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(AItems) do
    if AItems[i].Id = AId then Exit(i);
end;

{ Does this item have any sibling rule whose anchor actually resolves to a real item?
  (An unknown anchor id, or no sibling rules, means it does NOT depend on a sibling.) }
function DependsOnSibling(const AItems: TTyRelativeItemArray; AIdx: Integer): Boolean;
begin
  Result := (AItems[AIdx].Rules * AllSiblingRules <> [])
    and (AItems[AIdx].AnchorId >= 0)
    and (IndexOfId(AItems, AItems[AIdx].AnchorId) >= 0)
    and (AItems[AIdx].AnchorId <> AItems[AIdx].Id);   // self-anchor never depends
end;

function TyRelativeSolve(const AItems: TTyRelativeItemArray; const AParent: TRect;
  ASpacing: Integer): TTyRelativePosArray;
var
  n, i, idx, anchorIdx, guard: Integer;
  placed: array of Boolean;
  inCycle: array of Boolean;   // True for items force-placed (their sibling rule is dropped)
  order: array of Integer;
  orderCount: Integer;
  progressed: Boolean;
  pW, pH: Integer;
  r: TTyRelativeRules;
  aPos: TTyRelativePos;
  aItem: TTyRelativeItem;

  { Is item AI ready to place? (No sibling dependency, or its sibling is already placed.) }
  function Ready(AI: Integer): Boolean;
  var ai2: Integer;
  begin
    if not DependsOnSibling(AItems, AI) then Exit(True);
    ai2 := IndexOfId(AItems, AItems[AI].AnchorId);
    Result := (ai2 >= 0) and placed[ai2];
  end;

begin
  n := Length(AItems);
  SetLength(Result, n);
  if n = 0 then Exit;

  pW := AParent.Right - AParent.Left;
  pH := AParent.Bottom - AParent.Top;

  SetLength(placed, n);
  SetLength(inCycle, n);
  SetLength(order, n);
  orderCount := 0;
  for i := 0 to n - 1 do
  begin
    placed[i] := False;
    inCycle[i] := False;
  end;

  { Topological ordering by repeated ready-sweeps. Each pass places every item whose
    sibling (if any) is already placed. If a full pass places NOTHING but items remain,
    the rest form a cycle (or chain into one) — force-place them at the parent origin in
    array order so the loop always terminates. }
  guard := 0;
  while (orderCount < n) and (guard <= n) do
  begin
    progressed := False;
    for i := 0 to n - 1 do
      if (not placed[i]) and Ready(i) then
      begin
        order[orderCount] := i;
        Inc(orderCount);
        placed[i] := True;
        progressed := True;
      end;
    Inc(guard);
    if not progressed then Break;   // remaining items are in a cycle
  end;
  { Force-place any still-unplaced (cycle) items in array order — their sibling rules are
    dropped (inCycle), but parent-align/center still apply below. }
  for i := 0 to n - 1 do
    if not placed[i] then
    begin
      order[orderCount] := i;
      Inc(orderCount);
      placed[i] := True;
      inCycle[i] := True;
    end;

  { Solve in dependency order. }
  for i := 0 to orderCount - 1 do
  begin
    idx := order[i];
    aItem := AItems[idx];
    r := aItem.Rules;

    { Base: parent content origin. }
    Result[idx].Left := AParent.Left;
    Result[idx].Top := AParent.Top;

    { Parent-align (each edge pins to the parent's corresponding content edge). }
    if traAlignParentLeft in r then
      Result[idx].Left := AParent.Left;
    if traAlignParentTop in r then
      Result[idx].Top := AParent.Top;
    if traAlignParentRight in r then
      Result[idx].Left := AParent.Right - aItem.W;
    if traAlignParentBottom in r then
      Result[idx].Top := AParent.Bottom - aItem.H;

    { Center (in parent). CenterInParent = both axes. }
    if (traCenterHorizontal in r) or (traCenterInParent in r) then
      Result[idx].Left := AParent.Left + (pW - aItem.W) div 2;
    if (traCenterVertical in r) or (traCenterInParent in r) then
      Result[idx].Top := AParent.Top + (pH - aItem.H) div 2;

    { Sibling rules — only when this item was placed in TOPOLOGICAL order (not a dropped
      cycle item) AND the anchor resolves to a REAL, already-placed item that is not this
      item itself. A cycle item's sibling rule is dropped entirely (inCycle) so it stays at
      the parent-origin/parent-align/center fallback and never chains off an unordered peer. }
    anchorIdx := IndexOfId(AItems, aItem.AnchorId);
    if (not inCycle[idx]) and (r * AllSiblingRules <> [])
       and (anchorIdx >= 0) and (anchorIdx <> idx) and placed[anchorIdx] then
    begin
      aPos := Result[anchorIdx];   // the anchor's resolved position
      { Horizontal sibling rules. Edge-align first, then position (position wins). }
      if traAlignLeftOf in r then
        Result[idx].Left := aPos.Left;
      if traAlignRightOf in r then
        Result[idx].Left := (aPos.Left + AItems[anchorIdx].W) - aItem.W;
      if trRightOf in r then
        Result[idx].Left := aPos.Left + AItems[anchorIdx].W + ASpacing;
      if trLeftOf in r then
        Result[idx].Left := aPos.Left - ASpacing - aItem.W;
      { Vertical sibling rules. }
      if traAlignTopOf in r then
        Result[idx].Top := aPos.Top;
      if traAlignBottomOf in r then
        Result[idx].Top := (aPos.Top + AItems[anchorIdx].H) - aItem.H;
      if trBelow in r then
        Result[idx].Top := aPos.Top + AItems[anchorIdx].H + ASpacing;
      if trAbove in r then
        Result[idx].Top := aPos.Top - ASpacing - aItem.H;
    end;
  end;
end;

{ --- TTyRelativePanel ------------------------------------------------------------ }

constructor TTyRelativePanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TFPList.Create;
  FSpacing := 8;
  Width := 240;
  Height := 160;
end;

destructor TTyRelativePanel.Destroy;
var
  i: Integer;
begin
  if FItems <> nil then
  begin
    for i := 0 to FItems.Count - 1 do
      Dispose(PRelChildRec(FItems[i]));
    FItems.Free;
    FItems := nil;
  end;
  inherited Destroy;
end;

function TTyRelativePanel.GetStyleTypeKey: string;
begin
  Result := 'TyPanel';   // reuse the TyPanel theme; NO new .tycss selector
end;

function TTyRelativePanel.FindRec(AControl: TControl): Pointer;
var
  i: Integer;
  rec: PRelChildRec;
begin
  Result := nil;
  if (FItems = nil) or (AControl = nil) then Exit;
  for i := 0 to FItems.Count - 1 do
  begin
    rec := PRelChildRec(FItems[i]);
    if rec^.Control = AControl then Exit(rec);
  end;
end;

function TTyRelativePanel.RemoveRec(AControl: TControl): Boolean;
var
  i: Integer;
  rec: PRelChildRec;
begin
  Result := False;
  if FItems = nil then Exit;
  for i := FItems.Count - 1 downto 0 do
  begin
    rec := PRelChildRec(FItems[i]);
    if rec^.Control = AControl then
    begin
      Dispose(rec);
      FItems.Delete(i);
      Result := True;
    end;
  end;
end;

procedure TTyRelativePanel.SetSpacing(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FSpacing = AValue then Exit;
  FSpacing := AValue;
  PerformLayout;
end;

function TTyRelativePanel.ContentRect: TRect;
var
  S: TTyStyleSet;
  padL, padT, padR, padB, ppi: Integer;
begin
  // The interior after the theme's padding (same inset TTyPanel.RenderTo uses), scaled
  // to the control's DPI exactly like TTyPainter.Scale (MulDiv(logical, ppi, 96)).
  S := CurrentStyle;
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  if tpPadding in S.Present then
  begin
    padL := MulDiv(S.Padding.Left, ppi, 96);
    padT := MulDiv(S.Padding.Top, ppi, 96);
    padR := MulDiv(S.Padding.Right, ppi, 96);
    padB := MulDiv(S.Padding.Bottom, ppi, 96);
  end
  else
  begin
    padL := 0; padT := 0; padR := 0; padB := 0;
  end;
  Result := Rect(padL, padT, Width - padR, Height - padB);
  // Never let padding invert the rect (tiny panel + big padding).
  if Result.Right < Result.Left then Result.Right := Result.Left;
  if Result.Bottom < Result.Top then Result.Bottom := Result.Top;
end;

procedure TTyRelativePanel.SetRules(AControl: TControl; ARules: TTyRelativeRules;
  AAnchor: TControl);
var
  rec: PRelChildRec;
begin
  if AControl = nil then Exit;
  // An empty rule set = clear (a child with no rules keeps its own position).
  if ARules = [] then
  begin
    ClearRules(AControl);
    Exit;
  end;
  rec := PRelChildRec(FindRec(AControl));
  if rec = nil then
  begin
    New(rec);
    rec^.Control := AControl;
    FItems.Add(rec);
    // Track the child (and its anchor) so a Free drops the entry.
    AControl.FreeNotification(Self);
  end;
  rec^.Rules := ARules;
  rec^.Anchor := AAnchor;
  if AAnchor <> nil then
    AAnchor.FreeNotification(Self);
  PerformLayout;
end;

function TTyRelativePanel.GetRules(AControl: TControl): TTyRelativeRules;
var
  rec: PRelChildRec;
begin
  rec := PRelChildRec(FindRec(AControl));
  if rec = nil then Result := []
  else Result := rec^.Rules;
end;

function TTyRelativePanel.GetAnchor(AControl: TControl): TControl;
var
  rec: PRelChildRec;
begin
  rec := PRelChildRec(FindRec(AControl));
  if rec = nil then Result := nil
  else Result := rec^.Anchor;
end;

procedure TTyRelativePanel.ClearRules(AControl: TControl);
begin
  if RemoveRec(AControl) then
    PerformLayout;
end;

function TTyRelativePanel.RuledChildCount: Integer;
begin
  if FItems = nil then Result := 0
  else Result := FItems.Count;
end;

procedure TTyRelativePanel.PerformLayout;
var
  items: TTyRelativeItemArray;
  positions: TTyRelativePosArray;
  cr: TRect;
  i, n: Integer;
  rec: PRelChildRec;
  ctl: TControl;
begin
  if FInLayout then Exit;
  if FItems = nil then Exit;
  n := FItems.Count;
  if n = 0 then Exit;

  // Build the solver input from the ruled children. Each item's id = its index in FItems;
  // the anchor id = the index of the anchor's rec (or -1 when the anchor is nil / not a
  // ruled child of ours — the solver then treats it as no sibling).
  SetLength(items, n);
  for i := 0 to n - 1 do
  begin
    rec := PRelChildRec(FItems[i]);
    ctl := rec^.Control;
    items[i].Id := i;
    items[i].W := ctl.Width;
    items[i].H := ctl.Height;
    items[i].Rules := rec^.Rules;
    if rec^.Anchor <> nil then
      items[i].AnchorId := FItems.IndexOf(FindRec(rec^.Anchor))
    else
      items[i].AnchorId := -1;
    if items[i].AnchorId < 0 then items[i].AnchorId := -1;
  end;

  cr := ContentRect;
  positions := TyRelativeSolve(items, cr, FSpacing);

  FInLayout := True;
  try
    for i := 0 to n - 1 do
    begin
      rec := PRelChildRec(FItems[i]);
      ctl := rec^.Control;
      // Keep each child's own Width/Height; only place its Left/Top.
      ctl.SetBounds(positions[i].Left, positions[i].Top, ctl.Width, ctl.Height);
    end;
  finally
    FInLayout := False;
  end;
end;

procedure TTyRelativePanel.Resize;
begin
  inherited Resize;
  PerformLayout;
end;

procedure TTyRelativePanel.Notification(AComponent: TComponent; Operation: TOperation);
var
  i: Integer;
  rec: PRelChildRec;
  didChange: Boolean;
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent is TControl) then
  begin
    didChange := False;
    // Drop the removed control's own rec.
    if RemoveRec(TControl(AComponent)) then didChange := True;
    // Any rec that anchored to it loses its anchor (its sibling rules then fall back to
    // parent origin in the solver; keep the rec so parent/center rules still apply).
    if FItems <> nil then
      for i := 0 to FItems.Count - 1 do
      begin
        rec := PRelChildRec(FItems[i]);
        if rec^.Anchor = AComponent then
        begin
          rec^.Anchor := nil;
          didChange := True;
        end;
      end;
    if didChange and not (csDestroying in ComponentState) then
      PerformLayout;
  end;
end;

end.
