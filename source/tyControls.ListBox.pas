unit tyControls.ListBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.ScrollBar;
type
  TTyListBox = class(TTyCustomControl)
  private
    FItems: TStringList;
    FItemIndex: Integer;
    FItemHeight: Integer;
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
    procedure SetItems(const AValue: TStringList);
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
    procedure SetItemHeight(const AValue: Integer);
    procedure SetTopIndex(const AValue: Integer);
    function ScaledItemHeight: Integer;
    function MaxTopIndex: Integer;
    procedure EnsureSelectionVisible;
    procedure ScrollBarChange(Sender: TObject);
    procedure EnsureSelectedLen;
    function GetSelected(AIndex: Integer): Boolean;
    procedure SetSelected(AIndex: Integer; AValue: Boolean);
    procedure SetMultiSelect(AValue: Boolean);
    procedure DoChangeSel;
    procedure ClearAllBits;
    function FSelAnchorOr(ADefault: Integer): Integer;
    procedure ApplyRangeSelection(ALo, AHi: Integer);
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
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
    procedure SelectItem(AIndex: Integer);
    function VisibleRows: Integer;
    // Public helper for headless keyboard tests
    procedure SimulateKeyDown(AKey: Word);
    function SelCount: Integer;
    procedure ClearSelection;
    procedure SelectAll;
    property Selected[AIndex: Integer]: Boolean read GetSelected write SetSelected;
  published
    property Items: TStringList read FItems write SetItems;
    property ItemIndex: Integer read FItemIndex write SetItemIndex default -1;
    property MultiSelect: Boolean read FMultiSelect write SetMultiSelect default False;
    { When True, Items are kept in ascending (case-insensitive) order. The
      previously-selected item(s) stay selected, tracked by their text and
      re-pinned to their new indices after each reorder. }
    property Sorted: Boolean read FSorted write SetSorted default False;
    property ItemHeight: Integer read FItemHeight write SetItemHeight default 24;
    property TopIndex: Integer read FTopIndex write SetTopIndex default 0;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
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
  FItemHeight := 24;
  FTopIndex := 0;
  FHoverRow := -1;
  FScrollBar := nil;
  FSyncingScroll := False;
  FSelAnchor := -1;
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

procedure TTyListBox.SetItems(const AValue: TStringList);
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
    if Assigned(FOnChange) then
      FOnChange(Self);
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

procedure TTyListBox.SetItemHeight(const AValue: Integer);
begin
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
  Result := MulDiv(FItemHeight, Font.PixelsPerInch, 96);
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
  if Assigned(FOnChange) then
    FOnChange(Self);
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
    if Assigned(FOnChange) then FOnChange(Self);
  end
  else if AValue then
    SelectItem(AIndex);   // single mode: setting True selects it
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
  if not FMultiSelect then Exit;
  EnsureSelectedLen;
  AnyChanged := False;
  for i := 0 to High(FSelected) do
    if FSelected[i] then begin FSelected[i] := False; AnyChanged := True; end;
  if AnyChanged then
  begin
    Invalidate;
    if Assigned(FOnChange) then FOnChange(Self);
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
    if Assigned(FOnChange) then FOnChange(Self);
  end;
end;

procedure TTyListBox.DoChangeSel;
begin
  if Assigned(FOnChange) then FOnChange(Self);
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
      FScrollBar.Align := alRight;
      FScrollBar.OnChange := @ScrollBarChange;
      // Embedded scrollbar drives content scrolling: keep it instant (no thumb
      // glide) so scrolling never lags behind the wheel/keyboard.
      FScrollBar.AnimationsEnabled := False;
    end;
    // Update DPI-dependent width and controller every call so DPI changes take effect
    FScrollBar.Width := MulDiv(TyScrollbarSize, Font.PixelsPerInch, 96);
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
var Count, NewFocus, VR: Integer; Extend: Boolean;
  procedure MoveFocus(ATarget: Integer);
  begin
    if ATarget < 0 then ATarget := 0;
    if ATarget > Count - 1 then ATarget := Count - 1;
    NewFocus := ATarget;
  end;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  Count := FItems.Count;
  if Count = 0 then Exit;
  VR := VisibleRows;
  Extend := (ssShift in Shift) and FMultiSelect;
  NewFocus := FItemIndex;

  case Key of
    VK_UP:    MoveFocus(IfThenIdx(FItemIndex <= 0, 0, FItemIndex - 1));
    VK_DOWN:  MoveFocus(IfThenIdx(FItemIndex < 0, 0, FItemIndex + 1));
    VK_PRIOR: MoveFocus(IfThenIdx(FItemIndex < 0, 0, FItemIndex - VR));   // PageUp
    VK_NEXT:  MoveFocus(IfThenIdx(FItemIndex < 0, 0, FItemIndex + VR));   // PageDown
    VK_HOME:  MoveFocus(0);
    VK_END:   MoveFocus(Count - 1);
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
    Row := FTopIndex + (Y div SH);
    if (Row >= 0) and (Row < FItems.Count) then
    begin
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
        else
        begin
          ClearAllBits;
          FSelected[Row] := True;
          FItemIndex := Row; FSelAnchor := Row;
          Invalidate; DoChangeSel;
        end;
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
  NewRow := FTopIndex + (Y div SH);
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
  R, ContentRect, RowRect, RowFillRect: TRect;
  SBWidth, SH, i, LastRow: Integer;
  ItemStates: TTyStateSet;
  bw, ir, fillTop, fillBottom: Integer;
  rowCorners: TTyCorners;
begin
  // Keep scrollbar in sync (cheap; catches external Items.Add calls)
  UpdateScrollBar;

  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    BoxStyle := CurrentStyle;
    DrawFrame(P, R, BoxStyle);

    // Content area = full rect inset by the LISTBOX style's Padding
    ContentRect := Rect(
      R.Left   + P.Scale(BoxStyle.Padding.Left),
      R.Top    + P.Scale(BoxStyle.Padding.Top),
      R.Right  - P.Scale(BoxStyle.Padding.Right),
      R.Bottom - P.Scale(BoxStyle.Padding.Bottom)
    );

    // Subtract scrollbar width when visible
    SBWidth := 0;
    if (FScrollBar <> nil) and FScrollBar.Visible then
      SBWidth := MulDiv(TyScrollbarSize, APPI, 96);

    SH := MulDiv(FItemHeight, APPI, 96);
    if SH < 1 then SH := 1;
    LastRow := FTopIndex + VisibleRows - 1;
    if LastRow >= FItems.Count - 1 then
      LastRow := FItems.Count - 1;

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

      // Resolve TyListItem style for this row
      RowStyle := ActiveController.Model.ResolveStyle('TyListItem', '', ItemStates);

      // Row rect: full content width minus scrollbar, height = scaledItemHeight
      RowRect := Rect(
        ContentRect.Left,
        ContentRect.Top + (i - FTopIndex) * SH,
        ContentRect.Right - SBWidth,
        ContentRect.Top + (i - FTopIndex + 1) * SH
      );

      // Fill row background if the style has one. The highlight spans the listbox
      // INTERIOR edge-to-edge (flush to the inner border, minus the scrollbar) — no
      // side gap. The list is capped to the rounded container: the first item rounds
      // its TOP corners and the last item its BOTTOM corners to the container's inner
      // radius (so a square highlight never pokes past the rounded border), and those
      // end rows extend to the inner border so the round nests; middle rows are square.
      if tpBackground in RowStyle.Present then
      begin
        bw := P.Scale(BoxStyle.BorderWidth);
        ir := BoxStyle.BorderRadius - BoxStyle.BorderWidth;
        if ir < 0 then ir := 0;
        fillTop := RowRect.Top;
        fillBottom := RowRect.Bottom;
        rowCorners := TyCorners(0, 0, 0, 0);
        if i = 0 then
        begin
          fillTop := R.Top + bw;
          rowCorners.TL := ir; rowCorners.TR := ir;
        end;
        if i = FItems.Count - 1 then
        begin
          fillBottom := R.Bottom - bw;
          rowCorners.BR := ir; rowCorners.BL := ir;
        end;
        RowFillRect := Rect(R.Left + bw, fillTop, R.Right - bw - SBWidth, fillBottom);
        P.FillBackground(RowFillRect, RowStyle.Background, rowCorners);
      end;

      // Draw item text, inset by item padding
      P.DrawText(
        Rect(RowRect.Left + P.Scale(RowStyle.Padding.Left),
             RowRect.Top,
             RowRect.Right - P.Scale(RowStyle.Padding.Right),
             RowRect.Bottom),
        FItems[i],
        RowStyle.FontName, ResolveFontSize(RowStyle), RowStyle.FontWeight,
        RowStyle.TextColor,
        taLeftJustify, tlCenter, True
      );
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
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
