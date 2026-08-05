unit tyControls.ListBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LMessages,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller,
  tyControls.ScrollBar;
type
  { Selection-changed notification carrying LCL's User flag: True when the change came from
    the USER (a click, a key), False when code moved the selection. LCL:
    TSelectionChangeEvent, stdctrls.pp:529.

    Why the flag matters: a handler that writes back into the model, and a model that
    writes back into ItemIndex, is the standard two-way binding. Without a way to tell its
    own writes from the user's, such a handler either loops or has to carry a private
    "I am updating" boolean at every call site. }
  TTySelectionChangeEvent = procedure(Sender: TObject; AUser: Boolean) of object;

  TTyListBox = class(TTyCustomControl)
  private
    FItems: TStringList;
    FItemIndex: Integer;
    FItemHeight: Integer;
    FItemHeightExplicit: Boolean;   { True once set; False = follow --item-height (density) }
    FTopIndex: Integer;
    FOnChange: TNotifyEvent;
    FHoverRow: Integer;       // -1 = none; set in MouseMove, cleared in MouseLeave
    FScrollBar: TTyScrollBar; // nil until first needed
    FSyncingScroll: Boolean;  // reentrancy guard
    FMultiSelect: Boolean;
    FSelected: array of Boolean;
    FSelAnchor: Integer;
    FSorted: Boolean;
    FSuppressItemsChanged: Boolean;  // guard while we drive a reorder ourselves
    FExtendedSelect: Boolean;
    FOnSelectionChange: TTySelectionChangeEvent;
    FLockSelectionChange: Integer;   // >0 = report every change as programmatic
    { Nesting depth of a MOUSE/KEY handler. DoSelectionChange derives LCL's User flag from
      it, rather than threading a second argument through SelectItem / SetSelected /
      SelectAll -- SelectItem is public AND virtual, so widening it would break every
      descendant that overrides it (TTyValueListEditor does). }
    FUserAction: Integer;
    function GetItems: TStrings;
    procedure SetItems(const AValue: TStrings);
    procedure SetSorted(const AValue: Boolean);
    { Snapshot the currently-selected strings (single OR multi mode). }
    function SnapshotSelectedTexts: TStringList;
    { After the item list was reordered, re-mark exactly the items whose text
      was selected before the reorder. Keeps the SAME logical selection without
      firing OnChange (only positions shifted, not the selection set). }
    procedure ResyncSelectionFromTexts(ASelTexts: TStringList);
    { Fires when the underlying TStringList mutates (add/insert/delete). When
      Sorted is on, an insert can reorder indices, so re-pin the selection. }
    procedure ItemsChanged(Sender: TObject);
    procedure SetItemIndex(const AValue: Integer);
    function GetItemHeight: Integer;
    procedure SetItemHeight(const AValue: Integer);
    function ScaledItemHeight: Integer;
    function MaxTopIndex: Integer;
    procedure EnsureSelectionVisible;
    procedure ScrollBarChange(Sender: TObject);
    procedure EnsureSelectedLen;
    function GetSelected(AIndex: Integer): Boolean;
    procedure SetSelected(AIndex: Integer; AValue: Boolean);
    procedure SetMultiSelect(AValue: Boolean);
    procedure DoChangeSel;
    { The one place a selection change is announced. Every mutator calls it; it decides the
      User flag from FUserAction and the lock. }
    procedure FireSelectionChanged;
    procedure ClearAllBits;
    function FSelAnchorOr(ADefault: Integer): Integer;
    procedure ApplyRangeSelection(ALo, AHi: Integer);
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    // Per-item content paint (default: the item text). A subclass overrides to draw a
    // swatch / glyph / checkbox before the text. ARowRect is the full row; AStyle the
    // resolved row style (GetItemStyleTypeKey) for the row's current state. Used by
    // TTyColorListBox etc.
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); virtual;
    { The theme typeKey ONE ROW resolves. Virtual because RenderTo -- not the subclass -- owns
      the row loop, so this is the only seam through which a descendant that is NOT a plain
      list of strings can stop rendering its rows as 'TyListItem'. TTyValueListEditor (a
      two-column property inspector) uses it; every subclass that really does draw one line of
      text per row keeps the shared key, which is why they can all be restyled at once. }
    function GetItemStyleTypeKey: string; virtual;
    { The state set ONE ROW resolves, after the base has decided active/hover/normal. The
      row loop lives in RenderTo, so this is the only seam through which a descendant can
      say something about an individual row's condition -- TTyCheckListBox adds tysDisabled
      for a row its ItemEnabled[] turns off, which is what makes such a row look disabled
      instead of merely refusing to toggle. Default: unchanged. }
    function ItemStatesFor(AIndex: Integer; ABaseStates: TTyStateSet): TTyStateSet; virtual;
    { DOES THIS CLASS'S ROW LAYOUT MIRROR? Answered per CLASS, not per instance, and the
      default answer is "whatever the form says" -- IsRightToLeft.

      A descendant OVERRIDES THIS TO FALSE when its own PaintItemContent computes an x
      coordinate that something else recomputes independently. This box has fifteen
      descendants; each slices ARowRect into its own slots, and mirroring the row underneath
      one whose hit test was written against the unmirrored row is precisely the failure this
      pass has spent itself removing (a shape claiming its whole bounding box, a tree reading
      x as a scroll offset, a picker selecting the month you did not click). TTyValueListEditor
      is the one that does: its splitter and expander triangles are hit-tested from
      ContentLeftDp/SplitXDp, a SECOND computation of the geometry PaintItemContent derives
      from ARowRect, and the two cannot both follow this flag until they are one computation.

      Everything else in the family is safe because it has no x-axis hit test at all -- which
      is a property worth re-checking, not assuming, before adding a descendant that does. }
    function RtlRowLayout: Boolean; virtual;
    { THE LEFT AND RIGHT EDGE OF A PAINTED ROW, in device px, client coordinates.

      One definition, because two things need it and they must not disagree: RenderTo draws
      every row between these, and TTyCheckListBox hit-tests its toggle column against them.
      What makes it load-bearing is the scrollbar gutter -- right-to-left it moves to the LEFT
      edge, so the row's LEADING edge is the one that gets inset, and a check box painted from
      one edge while the click was measured from the other lands a full bar's width out.
      ContentTopOffset is this function's y-axis sibling and exists for the same reason.

      AWidth is the width being painted into (RenderTo is handed a rect; the hit tests use
      ClientWidth), APPI the same scale RenderTo's painter uses. }
    procedure RowContentBounds(AWidth, APPI: Integer; out ALeft, ARight: Integer);
    // Row index at client device Y (or -1 if outside any item). For subclasses that
    // hit-test rows, e.g. TTyCheckListBox's checkbox column.
    function RowAtY(AY: Integer): Integer;
    { Device-Y offset where row 0 begins = the listbox padding-top, scaled. Row hit-tests
      (MouseDown/MouseMove/RowAtY) subtract it so clicks agree with the painted row positions
      (RenderTo draws the first row at ContentRect.Top = padding-top, not at Y=0). }
    function ContentTopOffset: Integer;
    { Re-pin the selected index WITHOUT firing OnChange — for a subclass that keeps the same
      logical selection across a structural rebuild (only positions shifted, selection set
      unchanged). Mirrors ResyncSelectionFromTexts' silent contract, but caller-driven. }
    procedure SetItemIndexSilent(const AIndex: Integer);
    { TopIndex setter — protected virtual so a subclass with an inline editor
      (TTyValueListEditor) can commit/close it before the list scrolls (all scroll paths —
      wheel, scrollbar, keyboard auto-scroll — funnel through here). }
    procedure SetTopIndex(const AValue: Integer); virtual;
    { Raise OnChange and OnSelectionChange. AUser is LCL's flag (stdctrls.pp:608
      DoSelectionChange). Virtual so a descendant can observe every selection change
      without claiming the app's event slot. }
    procedure DoSelectionChange(AUser: Boolean); virtual;
    procedure Paint; override;
    { The reading direction changed, so the scrollbar changed SIDES -- and the bar's Align is
      written by UpdateScrollBar, which LCL's own handling never re-runs (it invalidates,
      notifies the children and calls AdjustSize; none of those revisits an Align this control
      set by hand). Without this the bar keeps its old edge while the rows re-inset for the
      new one, i.e. a gutter on one side and a bar on the other. Same defect and same fix as
      TTyRadioGroup.CMBiDiModeChanged. }
    procedure CMBiDiModeChanged(var Message: TLMessage); message CM_BIDIMODECHANGED;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure Resize; override;
    procedure UpdateScrollBar;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SelectItem(AIndex: Integer); virtual;
    function VisibleRows: Integer;
    // Public helper for headless keyboard tests
    procedure SimulateKeyDown(AKey: Word);
    function SelCount: Integer;
    procedure ClearSelection;
    procedure SelectAll;
    { The control-level list surface every LCL list control has and this one did not, so
      list code ported from Lazarus failed to compile on the method name -- `Lb.Clear`,
      `Lb.AddItem(s, obj)`, `Lb.Count`. Going through Items works, but only once you know
      to; and Clear in particular is not the same call, because emptying the list has to
      reset ItemIndex and the multi-select bitmap too. }
    procedure Clear;
    procedure AddItem(const AItem: string; AnObject: TObject);
    function Count: Integer;
    { Row geometry, published as the paint sees it. ItemRect is the device-px rect row
      AIndex is painted in (empty when the row is scrolled out of view), GetIndexAtY the
      inverse. Both route through the same RowAtY/ScaledItemHeight the painter uses, so a
      caller placing an editor or a popup over a row lands where the row actually is. }
    function ItemRect(AIndex: Integer): TRect;
    function GetIndexAtY(AY: Integer): Integer;
    { Delete every selected row (multi-select aware, back-to-front so the indices behind
      the cursor stay valid) and return the number removed. }
    function DeleteSelected: Integer;
    { Select the inclusive range [ALow..AHigh]. No-op when not MultiSelect, because a
      single-select box cannot hold a range and silently selecting only one end would be
      worse than doing nothing. }
    procedure SelectRange(ALow, AHigh: Integer; ASelected: Boolean);
    { The selected rows' text, newline-joined -- what a "copy the selection" command wants. }
    function GetSelectedText: string;
    { Bracket a bulk programmatic update so every OnSelectionChange inside it reports
      AUser = False, however the change was produced. LCL: stdctrls.pp:625/:631, bodies at
      customlistbox.inc:708-716 -- note the lock DEMOTES the flag, it does not suppress the
      event, so a handler that only cares about user edits stays correct while one that
      mirrors the selection still sees every move. Reference-counted; pair them. }
    procedure LockSelectionChange;
    procedure UnlockSelectionChange;
    { The backing store behind Items. Items is typed TStrings, as LCL types it, which is
      what lets `LB.Items := AnyTStrings` compile -- but it also hides the TStringList
      members, and one of them is load-bearing for anyone who wants to be told when the
      list itself mutates: OnChange. Same object as Items; never free it, never swap it. }
    property ItemsList: TStringList read FItems;
    property Selected[AIndex: Integer]: Boolean read GetSelected write SetSelected;
  public
    { When True, the box surface is painted with SQUARE corners (frame radius forced to 0). The
      ComboBox dropdown sets this on Wayland, where the popup window can't be shape-masked, so a
      square paint matches the square window. Default False — embedded listboxes keep their radius. }
    ForceSquareSurface: Boolean;
  published
    { Typed TStrings, as LCL types it (stdctrls.pp:435/:647). It was TStringList, which made
      `LB.Items := Memo.Lines` -- the everyday population idiom -- a compile error, because
      the ABSTRACT base is what every other TStrings source is. The backing store is still a
      TStringList (Sorted rides on it); assigning any TStrings copies into it. }
    property Items: TStrings read GetItems write SetItems;
    property ItemIndex: Integer read FItemIndex write SetItemIndex default -1;
    property MultiSelect: Boolean read FMultiSelect write SetMultiSelect default False;
    { With MultiSelect on, WHICH multi-select discipline the mouse follows. True (LCL's
      default, stdctrls.pp:642) is the extended one: a plain click replaces the selection,
      Ctrl toggles one row, Shift takes a range. False is simple multi-select -- every plain
      click toggles that row and nothing else, no modifier needed, which is the only usable
      discipline on a touch screen or a kiosk. It governs the MOUSE; arrow-key navigation is
      the same in both, as it is on the platforms LCL wraps. }
    property ExtendedSelect: Boolean read FExtendedSelect write FExtendedSelect default True;
    { When True, Items are kept in ascending (case-insensitive) order. The
      previously-selected item(s) stay selected, tracked by their text and
      re-pinned to their new indices after each reorder. }
    property Sorted: Boolean read FSorted write SetSorted default False;
    { Unset it follows --item-height (24 classic / 38 modern); set it pins and is streamed. }
    property ItemHeight: Integer read GetItemHeight write SetItemHeight stored FItemHeightExplicit;
    property TopIndex: Integer read FTopIndex write SetTopIndex default 0;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    { LCL's name and shape for the same notification (stdctrls.pp:668). Fires alongside
      OnChange, never instead of it, so nothing that already listens has to move. }
    property OnSelectionChange: TTySelectionChangeEvent
      read FOnSelectionChange write FOnSelectionChange;
    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

function IfThenIdx(ACond: Boolean; ATrue, AFalse: Integer): Integer;
begin if ACond then Result := ATrue else Result := AFalse; end;

{ TTyListBox }

constructor TTyListBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TStringList.Create;
  FItems.OnChange := @ItemsChanged;
  FSorted := False;
  FSuppressItemsChanged := False;
  FItemIndex := -1;
  FItemHeight := 24;              { fallback; unused while FItemHeightExplicit=False }
  FItemHeightExplicit := False;   { follow --item-height (density-aware) until set }
  FTopIndex := 0;
  FHoverRow := -1;
  FScrollBar := nil;
  FSyncingScroll := False;
  FSelAnchor := -1;
  FExtendedSelect := True;        { LCL's default discipline }
  FLockSelectionChange := 0;
  FUserAction := 0;
  TabStop := True;
  Width := 160;
  Height := 120;
end;

destructor TTyListBox.Destroy;
begin
  FItems.Free;
  // FScrollBar is owned by Self (via Create(Self)) so it is freed by TComponent
  inherited Destroy;
end;

function TTyListBox.GetStyleTypeKey: string;
begin
  Result := 'TyListBox';
end;

function TTyListBox.GetItemStyleTypeKey: string;
begin
  Result := 'TyListItem';
end;

function TTyListBox.ItemStatesFor(AIndex: Integer; ABaseStates: TTyStateSet): TTyStateSet;
begin
  Result := ABaseStates;
end;

function TTyListBox.GetItems: TStrings;
begin
  Result := FItems;
end;

procedure TTyListBox.SetItems(const AValue: TStrings);
begin
  // Drive the assignment ourselves; suppress the per-mutation ItemsChanged hook
  // so we do the clamping/selection bookkeeping exactly once below.
  FSuppressItemsChanged := True;
  try
    FItems.Assign(AValue);
    // TStringList.Assign copies the source's Sorted flag, which would silently
    // drop our Sorted state. Re-apply it so an externally-set list stays sorted.
    if FItems.Sorted <> FSorted then
      FItems.Sorted := FSorted;
  finally
    FSuppressItemsChanged := False;
  end;
  // Clamp TopIndex and ItemIndex in case list shrank
  if FTopIndex > MaxTopIndex then
    FTopIndex := MaxTopIndex;
  if (FItemIndex >= 0) and (FItemIndex >= FItems.Count) then
  begin
    FItemIndex := -1;
    FireSelectionChanged;
  end;
  SetLength(FSelected, FItems.Count);
  UpdateScrollBar;
  Invalidate;
end;

procedure TTyListBox.SetSorted(const AValue: Boolean);
var
  SelTexts: TStringList;
begin
  if FSorted = AValue then Exit;
  FSorted := AValue;
  // Snapshot the selected item text(s) BEFORE the reorder so we can re-pin the
  // SAME logical selection afterwards (indices shift, the selection set does not).
  SelTexts := SnapshotSelectedTexts;
  try
    // TStringList natively supports Sorted: setting it sorts in place (ascending,
    // case-insensitive) and keeps subsequent Adds sorted. Suppress our OnChange
    // hook while we flip it; we re-pin the selection explicitly below.
    FSuppressItemsChanged := True;
    try
      FItems.Sorted := FSorted;
    finally
      FSuppressItemsChanged := False;
    end;
    ResyncSelectionFromTexts(SelTexts);
  finally
    SelTexts.Free;
  end;
  UpdateScrollBar;
  Invalidate;
end;

function TTyListBox.SnapshotSelectedTexts: TStringList;
var
  i: Integer;
begin
  Result := TStringList.Create;
  if FMultiSelect then
  begin
    EnsureSelectedLen;
    for i := 0 to High(FSelected) do
      if FSelected[i] and (i < FItems.Count) then
        Result.Add(FItems[i]);
  end
  else if (FItemIndex >= 0) and (FItemIndex < FItems.Count) then
    Result.Add(FItems[FItemIndex]);
end;

procedure TTyListBox.ResyncSelectionFromTexts(ASelTexts: TStringList);
var
  i, Idx: Integer;
begin
  // Re-mark exactly the items whose text was selected before the reorder. The
  // selection set is logically unchanged (only positions moved) so we do NOT
  // fire OnChange here.
  if FMultiSelect then
  begin
    EnsureSelectedLen;
    for i := 0 to High(FSelected) do FSelected[i] := False;
    for i := 0 to ASelTexts.Count - 1 do
    begin
      Idx := FItems.IndexOf(ASelTexts[i]);
      if (Idx >= 0) and (Idx < Length(FSelected)) then
        FSelected[Idx] := True;
    end;
  end
  else
  begin
    if ASelTexts.Count = 0 then Exit;        // nothing was selected
    Idx := FItems.IndexOf(ASelTexts[0]);
    if Idx >= 0 then
      FItemIndex := Idx
    else
      FItemIndex := -1;                       // selected text no longer present
  end;
end;

procedure TTyListBox.ItemsChanged(Sender: TObject);
var
  SelTexts: TStringList;
begin
  if FSuppressItemsChanged then Exit;
  // Keep the FSelected bit-array length in step with the item count.
  EnsureSelectedLen;
  // When Sorted is on, an Add can land anywhere (reordering indices). Re-pin the
  // existing selection to its text so it survives the shift. We can only do this
  // meaningfully when the selected text(s) still resolve; capturing here would be
  // post-reorder, so this primarily guards direct external mutation. The dominant
  // reorder path (SetSorted) snapshots before flipping and re-pins explicitly.
  if FSorted then
  begin
    SelTexts := SnapshotSelectedTexts;
    try
      ResyncSelectionFromTexts(SelTexts);
    finally
      SelTexts.Free;
    end;
  end;
  // Clamp stale indices if the list shrank.
  if FItemIndex >= FItems.Count then FItemIndex := -1;
  if FTopIndex > MaxTopIndex then FTopIndex := MaxTopIndex;
  Invalidate;
end;

procedure TTyListBox.SetItemIndex(const AValue: Integer);
begin
  SelectItem(AValue);
end;

{ Effective row height: an explicit ItemHeight wins; otherwise follow --item-height,
  which the density pack raises for modern. Resolved live so a density toggle re-heights
  the rows on the next layout. }
function TTyListBox.GetItemHeight: Integer;
begin
  if FItemHeightExplicit then
    Result := FItemHeight
  else
    Result := ActiveController.Metric('--item-height', 24);
end;

procedure TTyListBox.SetItemHeight(const AValue: Integer);
begin
  FItemHeightExplicit := True;   { host pinned it, even at the fallback value }
  if FItemHeight = AValue then Exit;
  FItemHeight := AValue;
  if FItemHeight < 1 then FItemHeight := 1;
  UpdateScrollBar;
  Invalidate;
end;

function TTyListBox.MaxTopIndex: Integer;
begin
  Result := FItems.Count - VisibleRows;
  if Result < 0 then Result := 0;
end;

procedure TTyListBox.SetTopIndex(const AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := AValue;
  if Clamped < 0 then Clamped := 0;
  if Clamped > MaxTopIndex then Clamped := MaxTopIndex;
  if FTopIndex = Clamped then Exit;
  FTopIndex := Clamped;
  // Sync scrollbar position (guard reentrancy)
  if (not FSyncingScroll) and (FScrollBar <> nil) and FScrollBar.Visible then
  begin
    FSyncingScroll := True;
    try
      FScrollBar.Position := FTopIndex;
    finally
      FSyncingScroll := False;
    end;
  end;
  Invalidate;
end;

function TTyListBox.ScaledItemHeight: Integer;
begin
  Result := MulDiv(GetItemHeight, Font.PixelsPerInch, 96);
  if Result < 1 then Result := 1;
end;

function TTyListBox.VisibleRows: Integer;
var
  SH: Integer;
begin
  SH := ScaledItemHeight;
  // Use Height rather than ClientHeight so the result is testable headlessly
  // (in headless LCL without a native handle, ClientHeight can lag behind SetBounds).
  // For this borderless control Height = ClientHeight at runtime.
  Result := Height div SH;
  if Result < 1 then Result := 1;
end;

procedure TTyListBox.EnsureSelectionVisible;
var
  VR: Integer;
begin
  if FItemIndex < 0 then Exit;
  VR := VisibleRows;
  if FItemIndex < FTopIndex then
    FTopIndex := FItemIndex
  else if FItemIndex >= FTopIndex + VR then
    FTopIndex := FItemIndex - VR + 1;
  // Clamp TopIndex to valid range
  if FTopIndex < 0 then FTopIndex := 0;
  if FTopIndex > MaxTopIndex then FTopIndex := MaxTopIndex;
end;

procedure TTyListBox.SelectItem(AIndex: Integer);
var
  NewIndex: Integer;
begin
  if (AIndex >= 0) and (AIndex < FItems.Count) then
    NewIndex := AIndex
  else
    NewIndex := -1;
  if NewIndex = FItemIndex then Exit;
  FItemIndex := NewIndex;
  EnsureSelectionVisible;
  UpdateScrollBar;
  Invalidate;
  FireSelectionChanged;
end;

procedure TTyListBox.ScrollBarChange(Sender: TObject);
begin
  if FSyncingScroll then Exit;
  FSyncingScroll := True;
  try
    SetTopIndex(FScrollBar.Position);
  finally
    FSyncingScroll := False;
  end;
end;

procedure TTyListBox.EnsureSelectedLen;
begin
  if Length(FSelected) <> FItems.Count then
    SetLength(FSelected, FItems.Count);   // new slots default False
end;

function TTyListBox.GetSelected(AIndex: Integer): Boolean;
begin
  if (AIndex < 0) or (AIndex >= FItems.Count) then Exit(False);
  if FMultiSelect then
  begin
    EnsureSelectedLen;
    Result := FSelected[AIndex];
  end
  else
    Result := (AIndex = FItemIndex);
end;

procedure TTyListBox.SetSelected(AIndex: Integer; AValue: Boolean);
begin
  if (AIndex < 0) or (AIndex >= FItems.Count) then Exit;
  if FMultiSelect then
  begin
    EnsureSelectedLen;
    if FSelected[AIndex] = AValue then Exit;
    FSelected[AIndex] := AValue;
    Invalidate;
    FireSelectionChanged;
  end
  else if AValue then
    SelectItem(AIndex)    // single mode: setting True selects it
  else if FItemIndex = AIndex then
    { ...and setting False DEselects it. Exiting here instead (which is what this did)
      made Selected[i] := False a silent no-op in the mode most listboxes run in.
      LCL: customlistbox.inc SetSelected -> else ItemIndex := -1. }
    SelectItem(-1);
end;

procedure TTyListBox.SetMultiSelect(AValue: Boolean);
var i: Integer;
begin
  if FMultiSelect = AValue then Exit;
  FMultiSelect := AValue;
  EnsureSelectedLen;
  // Clean slate on any mode switch so stale multi-select bits never resurface.
  for i := 0 to High(FSelected) do FSelected[i] := False;
  Invalidate;
end;

function TTyListBox.SelCount: Integer;
var i: Integer;
begin
  if FMultiSelect then
  begin
    EnsureSelectedLen;
    Result := 0;
    for i := 0 to High(FSelected) do if FSelected[i] then Inc(Result);
  end
  else if (FItemIndex >= 0) and (FItemIndex < FItems.Count) then Result := 1
  else Result := 0;
end;

procedure TTyListBox.ClearSelection;
var i: Integer; AnyChanged: Boolean;
begin
  if not FMultiSelect then
  begin
    { A single-select listbox has exactly one selection, so "clear the selection"
      is a meaningful request -- it means ItemIndex := -1. Returning early made the
      method do nothing at all unless MultiSelect happened to be on. }
    SelectItem(-1);
    Exit;
  end;
  EnsureSelectedLen;
  AnyChanged := False;
  for i := 0 to High(FSelected) do
    if FSelected[i] then begin FSelected[i] := False; AnyChanged := True; end;
  if AnyChanged then
  begin
    Invalidate;
    FireSelectionChanged;
  end;
end;

procedure TTyListBox.SelectAll;
var i: Integer; AnyChanged: Boolean;
begin
  if not FMultiSelect then Exit;
  EnsureSelectedLen;
  AnyChanged := False;
  for i := 0 to High(FSelected) do
    if not FSelected[i] then begin FSelected[i] := True; AnyChanged := True; end;
  if AnyChanged then
  begin
    Invalidate;
    FireSelectionChanged;
  end;
end;

procedure TTyListBox.DoChangeSel;
begin
  FireSelectionChanged;
end;

{ The User flag LCL carries is derived here, once, rather than plumbed through every
  mutator: FUserAction is non-zero only inside MouseDown/KeyDown, and a held lock demotes
  the flag exactly as customlistbox.inc:360 does. }
procedure TTyListBox.FireSelectionChanged;
begin
  DoSelectionChange((FUserAction > 0) and (FLockSelectionChange = 0));
end;

procedure TTyListBox.DoSelectionChange(AUser: Boolean);
begin
  if Assigned(FOnChange) then FOnChange(Self);
  if Assigned(FOnSelectionChange) then FOnSelectionChange(Self, AUser);
end;

procedure TTyListBox.LockSelectionChange;
begin
  Inc(FLockSelectionChange);
end;

procedure TTyListBox.UnlockSelectionChange;
begin
  if FLockSelectionChange > 0 then Dec(FLockSelectionChange);
end;

procedure TTyListBox.ClearAllBits;
var i: Integer;
begin
  EnsureSelectedLen;
  for i := 0 to High(FSelected) do FSelected[i] := False;
end;

function TTyListBox.FSelAnchorOr(ADefault: Integer): Integer;
begin
  if (FSelAnchor >= 0) and (FSelAnchor < FItems.Count) then Result := FSelAnchor
  else Result := ADefault;
end;

procedure TTyListBox.ApplyRangeSelection(ALo, AHi: Integer);
var i, t: Integer;
begin
  EnsureSelectedLen;
  if ALo > AHi then begin t := ALo; ALo := AHi; AHi := t; end;
  ClearAllBits;
  for i := ALo to AHi do
    if (i >= 0) and (i < FItems.Count) then FSelected[i] := True;
  Invalidate;
  DoChangeSel;
end;

procedure TTyListBox.UpdateScrollBar;
var
  VR, MaxPos, MaxTop: Integer;
begin
  VR := VisibleRows;
  // Clamp FTopIndex in case Items were mutated directly (Clear/Add without SetItems)
  MaxTop := FItems.Count - VR;
  if MaxTop < 0 then MaxTop := 0;
  if FTopIndex > MaxTop then FTopIndex := MaxTop;
  if FItems.Count > VR then
  begin
    // Ensure scrollbar created
    if FScrollBar = nil then
    begin
      FScrollBar := TTyScrollBar.Create(Self);
      FScrollBar.Parent := Self;
      FScrollBar.Kind := sbVertical;
      // A standalone TTyScrollBar is focusable (it has its own arrow/page keys), but an
      // EMBEDDED one must not be: dragging the bar would pull focus off the list box, which
      // would then lose its focus ring and its arrow-key navigation mid-scroll.
      FScrollBar.TabStop := False;
      FScrollBar.OnChange := @ScrollBarChange;
      // Embedded scrollbar drives content scrolling: keep it instant (no thumb
      // glide) so scrolling never lags behind the wheel/keyboard.
      FScrollBar.AnimationsEnabled := False;
      FScrollBar.ControlStyle := FScrollBar.ControlStyle + [csNoDesignVisible];   // internal: never a designable child
    end;
    { WHICH EDGE THE BAR DOCKS TO -- set on EVERY call, not once at creation, because it can
      change after the bar exists (BiDiMode is writable at runtime; CMBiDiModeChanged comes
      straight back here). LCL's alignment engine has no BiDi of its own, so alRight stays
      the right-hand edge on a mirrored form and the side has to be chosen explicitly; this
      is the one place that chooses it, and RowContentBounds insets the rows to match. }
    if RtlRowLayout then
      FScrollBar.Align := alLeft
    else
      FScrollBar.Align := alRight;
    // Update DPI-dependent width and controller every call so DPI changes take effect
    FScrollBar.Width := MulDiv(ActiveController.Metric('--scrollbar-size', TyScrollbarSize), Font.PixelsPerInch, 96);
    FScrollBar.Controller := Self.Controller;
    MaxPos := FItems.Count - VR;
    if MaxPos < 0 then MaxPos := 0;
    FSyncingScroll := True;
    try
      FScrollBar.Min := 0;
      FScrollBar.Max := MaxPos;
      FScrollBar.PageSize := VR;
      FScrollBar.Position := FTopIndex;
    finally
      FSyncingScroll := False;
    end;
    FScrollBar.Visible := True;
  end
  else
  begin
    if FScrollBar <> nil then
      FScrollBar.Visible := False;
  end;
end;

procedure TTyListBox.KeyDown(var Key: Word; Shift: TShiftState);
var RowTotal, NewFocus, VR: Integer; Extend: Boolean;
  procedure MoveFocus(ATarget: Integer);
  begin
    if ATarget < 0 then ATarget := 0;
    if ATarget > RowTotal - 1 then ATarget := RowTotal - 1;
    NewFocus := ATarget;
  end;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  RowTotal := FItems.Count;
  if RowTotal = 0 then Exit;
  { Every selection change from here down is the USER's; the counter is what lets
    OnSelectionChange report it as such without a second parameter on SelectItem. }
  Inc(FUserAction);
  try
  VR := VisibleRows;
  Extend := (ssShift in Shift) and FMultiSelect;
  NewFocus := FItemIndex;

  case Key of
    VK_UP:    MoveFocus(IfThenIdx(FItemIndex <= 0, 0, FItemIndex - 1));
    VK_DOWN:  MoveFocus(IfThenIdx(FItemIndex < 0, 0, FItemIndex + 1));
    VK_PRIOR: MoveFocus(IfThenIdx(FItemIndex < 0, 0, FItemIndex - VR));   // PageUp
    VK_NEXT:  MoveFocus(IfThenIdx(FItemIndex < 0, 0, FItemIndex + VR));   // PageDown
    VK_HOME:  MoveFocus(0);
    VK_END:   MoveFocus(RowTotal - 1);
    VK_SPACE:
      begin
        if FMultiSelect and (FItemIndex >= 0) then
        begin
          EnsureSelectedLen;
          FSelected[FItemIndex] := not FSelected[FItemIndex];
          FSelAnchor := FItemIndex;
          Invalidate; DoChangeSel;
          Key := 0;
        end;
        Exit;   // single-select: do NOT consume Space (parent/form may handle it)
      end;
  else
    Exit;   // key not handled (leave Key unconsumed)
  end;
  Key := 0;

  if not FMultiSelect then
  begin
    SelectItem(NewFocus);   // single mode: existing behavior (clamps, OnChange, scrolls)
    Exit;
  end;

  // Multi mode: move focus; extend range from anchor if Shift, else select-only.
  FItemIndex := NewFocus;
  EnsureSelectedLen;
  if Extend then
    ApplyRangeSelection(FSelAnchorOr(NewFocus), NewFocus)
  else
  begin
    ClearAllBits;
    FSelected[NewFocus] := True;
    FSelAnchor := NewFocus;
    Invalidate; DoChangeSel;
  end;
  EnsureSelectionVisible;
  UpdateScrollBar;
  finally
    Dec(FUserAction);   { every Exit above passes through here }
  end;
end;

procedure TTyListBox.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Row: Integer;
  SH: Integer;
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    SH := ScaledItemHeight;
    Row := FTopIndex + ((Y - ContentTopOffset) div SH);
    if (Row >= 0) and (Row < FItems.Count) then
    begin
      Inc(FUserAction);   { everything below is the USER moving the selection }
      try
        if not FMultiSelect then
          SelectItem(Row)
        else
        begin
          EnsureSelectedLen;
          if ssShift in Shift then
          begin
            ApplyRangeSelection(FSelAnchorOr(Row), Row);
            FItemIndex := Row;
          end
          else if ssCtrl in Shift then
          begin
            FSelected[Row] := not FSelected[Row];
            FItemIndex := Row; FSelAnchor := Row;
            Invalidate; DoChangeSel;
          end
          else if not FExtendedSelect then
          begin
            { Simple multi-select: a plain click toggles THAT row and touches nothing else.
              No modifier is reachable on a touch screen, which is the whole reason LCL
              carries the switch (LBS_MULTIPLESEL vs LBS_EXTENDEDSEL). }
            FSelected[Row] := not FSelected[Row];
            FItemIndex := Row; FSelAnchor := Row;
            Invalidate; DoChangeSel;
          end
          else
          begin
            ClearAllBits;
            FSelected[Row] := True;
            FItemIndex := Row; FSelAnchor := Row;
            Invalidate; DoChangeSel;
          end;
        end;
      finally
        Dec(FUserAction);
      end;
    end;
    try
      if CanFocus then
        SetFocus;
    except
      // Ignore focus errors in headless/test environments
    end;
  end;
end;

procedure TTyListBox.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  SH, NewRow: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  SH := ScaledItemHeight;
  NewRow := FTopIndex + ((Y - ContentTopOffset) div SH);
  if (NewRow < 0) or (NewRow >= FItems.Count) then
    NewRow := -1;
  if NewRow <> FHoverRow then
  begin
    FHoverRow := NewRow;
    Invalidate;
  end;
end;

procedure TTyListBox.MouseLeave;
begin
  inherited MouseLeave;
  if FHoverRow <> -1 then
  begin
    FHoverRow := -1;
    Invalidate;
  end;
end;

function TTyListBox.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  Delta: Integer;
begin
  if not Enabled then Exit(False);
  // Let the user's OnMouseWheel handler run first; if it consumes the event, stop.
  if inherited DoMouseWheel(Shift, WheelDelta, MousePos) then
  begin
    Result := True;
    Exit;
  end;
  // WheelDelta > 0 = scroll up (TopIndex decreases)
  // WheelDelta < 0 = scroll down (TopIndex increases)
  if WheelDelta > 0 then
    Delta := -3
  else
    Delta := 3;
  SetTopIndex(FTopIndex + Delta);
  Result := True;
end;

procedure TTyListBox.Resize;
begin
  inherited Resize;
  UpdateScrollBar;
end;

procedure TTyListBox.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  BoxStyle, RowStyle: TTyStyleSet;
  R, ContentRect, RowRect: TRect;
  SBWidth, SH, i, LastRow: Integer;
  cLeft, cRight, leadSB, trailSB: Integer;
  ItemStates: TTyStateSet;
  capR, fillTop, fillBottom, inset, insetLogical: Integer;
  contentFills: Boolean;
  rowCorners: TTyCorners;
  savedClip: TRect;
begin
  // Keep scrollbar in sync (cheap; catches external Items.Add calls)
  UpdateScrollBar;

  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    BoxStyle := CurrentStyle;
    // Wayland popup: the window can't be shape-masked, so paint square corners to match it. Per-corner
    // Radius wins in TyEffectiveCorners, so zero it AND BorderRadius (row caps key off BorderRadius).
    if ForceSquareSurface then
    begin
      BoxStyle.BorderRadius := 0;
      BoxStyle.Radius := Default(TTyCorners);
    end;
    DrawFrame(P, R, BoxStyle);

    { Content area = full rect inset by the LISTBOX style's Padding, with the x edges coming
      from RowContentBounds -- which also takes the visible bar's gutter off the side the bar
      is docked to. The hit tests read the same function, so "where a row starts" has one
      definition rather than a painted one and a clicked one. }
    RowContentBounds(R.Right - R.Left, APPI, cLeft, cRight);
    ContentRect := Rect(
      cLeft,
      R.Top    + P.Scale(BoxStyle.Padding.Top),
      cRight,
      R.Bottom - P.Scale(BoxStyle.Padding.Bottom)
    );

    // The bar's gutter, and which side of the row FILL it comes off (the fills are measured
    // from the frame, not from the padding, so they need the number separately).
    SBWidth := 0;
    if (FScrollBar <> nil) and FScrollBar.Visible then
      SBWidth := MulDiv(ActiveController.Metric('--scrollbar-size', TyScrollbarSize), APPI, 96);
    if RtlRowLayout then begin leadSB := SBWidth; trailSB := 0; end
    else                 begin leadSB := 0;       trailSB := SBWidth; end;

    SH := MulDiv(GetItemHeight, APPI, 96);
    if SH < 1 then SH := 1;
    LastRow := FTopIndex + VisibleRows - 1;
    if LastRow >= FItems.Count - 1 then
      LastRow := FItems.Count - 1;

    // Inset the rows just PAST the focus chrome (border + focus ring) and HARD-clip them
    // there, so the chrome — drawn once by DrawFrame over the listbox background — keeps a
    // UNIFORM colour: the row fills never touch its anti-aliased inner edge (which otherwise
    // picked up the row colour at a hovered/selected row, tinting the border/ring there).
    // insetLogical = the chrome's inner edge + 1px AA clearance; 0 when there is no chrome.
    // The border and the focus ring (StrokeBorder) are both drawn INSIDE the edge: the border
    // occupies [Left, Left+BorderWidth] and the ring [Left+OutlineOffset, +OutlineWidth]. The
    // chrome's inner edge is therefore the LARGER of those (full widths, not half). Inset the
    // rows one logical px PAST it so a thin background gap sits between the chrome and the fill
    // and the chrome keeps a single uniform colour. No chrome => inset 0 (rows fill fully).
    insetLogical := BoxStyle.BorderWidth;
    if (tpOutline in BoxStyle.Present) and (BoxStyle.OutlineWidth > 0) then
      if BoxStyle.OutlineOffset + BoxStyle.OutlineWidth > insetLogical then
        insetLogical := BoxStyle.OutlineOffset + BoxStyle.OutlineWidth;
    if insetLogical > 0 then Inc(insetLogical);
    inset := P.Scale(insetLogical);
    savedClip := P.Bitmap.ClipRect;
    P.Bitmap.ClipRect := Rect(R.Left + inset, R.Top + inset, R.Right - inset, R.Bottom - inset);

    for i := FTopIndex to LastRow do
    begin
      // Determine item states
      ItemStates := [];
      if (FMultiSelect and GetSelected(i)) or ((not FMultiSelect) and (i = FItemIndex)) then
        Include(ItemStates, tysActive)
      else if i = FHoverRow then
        Include(ItemStates, tysHover)
      else
        Include(ItemStates, tysNormal);
      ItemStates := ItemStatesFor(i, ItemStates);

      // Resolve the row style for this row ('TyListItem', or the descendant's own key)
      RowStyle := ActiveController.Model.ResolveStyle(GetItemStyleTypeKey, '', ItemStates);

      // Row rect: the content width (RowContentBounds already gave up the bar's gutter on
      // whichever side the bar is on), height = scaledItemHeight
      RowRect := Rect(
        ContentRect.Left,
        ContentRect.Top + (i - FTopIndex) * SH,
        ContentRect.Right,
        ContentRect.Top + (i - FTopIndex + 1) * SH
      );

      // Fill row background if the style has one. The highlight spans the full interior
      // width (to the edges, minus the scrollbar). The first/last rows extend to the listbox
      // edge and round their OUTER corners by the listbox radius so the fill reaches the
      // rounded corner exactly (no gap); only when the list actually FILLS the box does the
      // last item cap+extend its bottom (else a short list's last row would bleed into the
      // empty space below). The border is re-stroked ON TOP after the loop, so a highlight
      // reaching the edge never covers it (no overlap). Middle rows are square.
      if tpBackground in RowStyle.Present then
      begin
        // Fill the INTERIOR width (flush to the inner border, minus the scrollbar). The
        // first/last rows extend to the inner border edge and cap their outer corners
        // CONCENTRIC with the rounded border (radius - border width) so they nest exactly;
        // only when the list FILLS the box does the last item cap+extend its bottom (else a
        // short list's last row would bleed into the empty space below). Middle rows square.
        capR := BoxStyle.BorderRadius - insetLogical;
        if capR < 0 then capR := 0;
        contentFills := (FItems.Count * SH) >= (ContentRect.Bottom - ContentRect.Top);
        fillTop := RowRect.Top;
        fillBottom := RowRect.Bottom;
        rowCorners := TyCorners(0, 0, 0, 0);
        if i = 0 then
        begin
          fillTop := R.Top + inset;
          rowCorners.TL := capR; rowCorners.TR := capR;
        end;
        if (i = FItems.Count - 1) and contentFills then
        begin
          fillBottom := R.Bottom - inset;
          rowCorners.BR := capR; rowCorners.BL := capR;
        end;
        P.FillBackground(Rect(R.Left + inset + leadSB, fillTop, R.Right - inset - trailSB, fillBottom),
          RowStyle.Background, rowCorners);
      end;

      // Per-item content (default: the text; a subclass draws a swatch/glyph + text).
      PaintItemContent(P, RowRect, i, RowStyle);
    end;

    P.Bitmap.ClipRect := savedClip;   // restore (rows were clipped to the interior)

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyListBox.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
var
  textR: TRect;
begin
  { Default: the item text, inset by the item padding. BOTH halves have to mirror together --
    the slot AND the alignment inside it. The painter's own flag is not enough here for the
    reason phase 0 recorded: this caller pre-slices its rect, so flipping only the alignment
    would push the text to the far edge of a slot that is still cut for the other direction.
    Padding.Left is the LEADING inset in either mode, so it changes physical sides with the
    text -- a theme that gives a row an asymmetric indent keeps that indent next to the text's
    start, which is what an author writing `padding-left` for a list means. }
  if RtlRowLayout then
    textR := Rect(ARowRect.Left  + P.Scale(AStyle.Padding.Right), ARowRect.Top,
                  ARowRect.Right - P.Scale(AStyle.Padding.Left),  ARowRect.Bottom)
  else
    textR := Rect(ARowRect.Left  + P.Scale(AStyle.Padding.Left),  ARowRect.Top,
                  ARowRect.Right - P.Scale(AStyle.Padding.Right), ARowRect.Bottom);
  P.DrawText(
    textR,
    FItems[AIndex],
    AStyle.FontName, ResolveFontSize(AStyle), AStyle.FontWeight,
    AStyle.TextColor,
    BidiFlipAlignment(taLeftJustify, RtlRowLayout), tlCenter, True
  );
end;

procedure TTyListBox.Clear;
begin
  { A convenience alias, and honestly nothing more: Items.Clear fires ItemsChanged, which
    already resizes the FSelected bitmap, clamps a now-out-of-range ItemIndex to -1 and
    pulls TopIndex back. Re-doing any of that here would be dead code that reads like a
    safeguard. What Clear buys is the NAME -- `Lb.Clear` is what ported code writes.
    No OnChange: LCL's Clear does not report a selection change either, and a caller who
    just emptied the list does not need to be told the selection went with it. }
  FItems.Clear;
  UpdateScrollBar;
end;

procedure TTyListBox.AddItem(const AItem: string; AnObject: TObject);
begin
  FItems.AddObject(AItem, AnObject);
end;

function TTyListBox.Count: Integer;
begin
  Result := FItems.Count;
end;

function TTyListBox.ItemRect(AIndex: Integer): TRect;
var
  SH, rowTop: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if (AIndex < 0) or (AIndex >= FItems.Count) then Exit;
  SH := ScaledItemHeight;
  if SH <= 0 then Exit;
  { The inverse of RowAtY, deliberately -- one formula, so what a caller is told and what
    gets painted cannot drift. }
  rowTop := ContentTopOffset + (AIndex - FTopIndex) * SH;
  Result := Rect(0, rowTop, ClientWidth, rowTop + SH);
end;

function TTyListBox.GetIndexAtY(AY: Integer): Integer;
begin
  Result := RowAtY(AY);
end;

function TTyListBox.DeleteSelected: Integer;
var
  i: Integer;
begin
  Result := 0;
  if FMultiSelect then
  begin
    EnsureSelectedLen;
    { Back to front: deleting row i shifts every row after it, so forward iteration would
      delete the wrong rows the moment it removed the first one. }
    for i := High(FSelected) downto 0 do
      if (i < FItems.Count) and FSelected[i] then
      begin
        FItems.Delete(i);
        Inc(Result);
      end;
    SetLength(FSelected, 0);
    EnsureSelectedLen;
    FItemIndex := -1;
  end
  else if (FItemIndex >= 0) and (FItemIndex < FItems.Count) then
  begin
    FItems.Delete(FItemIndex);
    FItemIndex := -1;
    Result := 1;
  end;
  if Result > 0 then
  begin
    if FTopIndex > FItems.Count - 1 then FTopIndex := 0;
    UpdateScrollBar;
    Invalidate;
    FireSelectionChanged;
  end;
end;

procedure TTyListBox.SelectRange(ALow, AHigh: Integer; ASelected: Boolean);
var
  i, lo, hi: Integer;
  moved: Boolean;
begin
  if not FMultiSelect then Exit;
  lo := ALow; hi := AHigh;
  if lo > hi then begin i := lo; lo := hi; hi := i; end;
  if lo < 0 then lo := 0;
  if hi > FItems.Count - 1 then hi := FItems.Count - 1;
  EnsureSelectedLen;
  moved := False;
  for i := lo to hi do
    if (i <= High(FSelected)) and (FSelected[i] <> ASelected) then
    begin
      FSelected[i] := ASelected;
      moved := True;
    end;
  if moved then
  begin
    Invalidate;
    FireSelectionChanged;
  end;
end;

function TTyListBox.GetSelectedText: string;
var
  i: Integer;
begin
  Result := '';
  if FMultiSelect then
  begin
    EnsureSelectedLen;
    for i := 0 to FItems.Count - 1 do
      if (i <= High(FSelected)) and FSelected[i] then
      begin
        if Result <> '' then Result := Result + LineEnding;
        Result := Result + FItems[i];
      end;
  end
  else if (FItemIndex >= 0) and (FItemIndex < FItems.Count) then
    Result := FItems[FItemIndex];
end;

function TTyListBox.RowAtY(AY: Integer): Integer;
var SH: Integer;
begin
  SH := ScaledItemHeight;
  if SH <= 0 then Exit(-1);
  Result := FTopIndex + ((AY - ContentTopOffset) div SH);
  if (Result < 0) or (Result >= FItems.Count) then Result := -1;
end;

function TTyListBox.ContentTopOffset: Integer;
begin
  { Same scale RenderTo uses (P.Scale = MulDiv(x, APPI, 96)); Font.PixelsPerInch tracks APPI. }
  Result := MulDiv(CurrentStyle.Padding.Top, Font.PixelsPerInch, 96);
end;

function TTyListBox.RtlRowLayout: Boolean;
begin
  Result := IsRightToLeft;
end;

procedure TTyListBox.RowContentBounds(AWidth, APPI: Integer; out ALeft, ARight: Integer);
var
  S: TTyStyleSet;
  sb: Integer;
begin
  S := CurrentStyle;
  ALeft  := MulDiv(S.Padding.Left,  APPI, 96);
  ARight := AWidth - MulDiv(S.Padding.Right, APPI, 96);
  { The gutter a VISIBLE bar owns, taken off the side the bar is actually docked to (see
    UpdateScrollBar, which docks it). Take it off the wrong side and the rows run underneath
    the bar while a strip of empty box sits opposite. }
  sb := 0;
  if (FScrollBar <> nil) and FScrollBar.Visible then
    sb := MulDiv(ActiveController.Metric('--scrollbar-size', TyScrollbarSize), APPI, 96);
  if RtlRowLayout then
    Inc(ALeft, sb)
  else
    Dec(ARight, sb);
  if ARight < ALeft then ARight := ALeft;
end;

procedure TTyListBox.CMBiDiModeChanged(var Message: TLMessage);
begin
  inherited;          // LCL invalidates, tells the children and calls AdjustSize
  UpdateScrollBar;    // and then the bar has to actually change edges
  Invalidate;
end;

procedure TTyListBox.SetItemIndexSilent(const AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < FItems.Count) then
    FItemIndex := AIndex
  else
    FItemIndex := -1;
end;

procedure TTyListBox.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTyListBox.SimulateKeyDown(AKey: Word);
begin
  KeyDown(AKey, []);
end;

end.
