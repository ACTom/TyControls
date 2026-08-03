unit tyControls.RadioGroup;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls,
  tyControls.Base, tyControls.Controller, tyControls.GroupBox, tyControls.CheckBox;
type
  { TTyRadioGroup — a titled frame (subclass of TTyGroupBox, so it inherits the themed
    caption band + the AdjustClientRect inset) that AUTO-POPULATES one TTyRadioButton
    child per line of Items. The radios all share this control's Parent scope (they are
    parented to Self, GroupIndex 0), so they are mutually exclusive via the base
    TTyRadioButton.UncheckSiblings — no extra grouping is needed.

    The children are INTERNAL helper controls: created owned by Self, flagged
    csNoDesignVisible so they never leak into the IDE object tree, and rebuilt whenever
    Items changes. ItemIndex reads the checked child's index and writes by checking that
    child; OnSelectionChanged fires when the selection changes via a click.

    Layout is COLUMN-MAJOR (fill down column 0, then column 1, …) across Columns columns,
    matching the classic VCL TRadioGroup. NOTE: LCL's own TRadioGroup defaults the other way --
    ColumnLayout = clHorizontalThenVertical (extctrls.pp) -- so a form ported from Lazarus will
    see its items in a different order here. The geometry is a pure unit-level function
    (TyRadioGroupCellRect) so it is headless-testable in isolation. }
  TTyRadioGroup = class(TTyGroupBox)
  private
    FItems: TStrings;
    FColumns: Integer;
    FButtons: array of TTyRadioButton;
    FOnSelectionChanged: TNotifyEvent;
    FRebuilding: Boolean;      // re-entrancy guard for RebuildButtons
    FUpdatingIndex: Boolean;   // re-entrancy guard for the child OnChange router
    procedure SetItems(AValue: TStrings);
    procedure ItemsChanged(Sender: TObject);
    procedure SetColumns(AValue: Integer);
    function GetItemIndex: Integer;
    procedure SetItemIndex(AValue: Integer);
    procedure ClearButtons;
    procedure RebuildButtons;
    procedure LayoutButtons;
    procedure ChildChanged(Sender: TObject);
    procedure NotifySelection;
    procedure UpdateTabStops;
  protected
    procedure SetParent(AParent: TWinControl); override;
    procedure DoOnResize; override;
    // Keep the internal radio children on the group's controller so a controller assigned
    // AFTER population still themes them (mirrors TTyCheckGroup.SetController).
    procedure SetController(AValue: TTyStyleController); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Number of item rows == number of radio children. }
    function Count: Integer;
  published
    property Items: TStrings read FItems write SetItems;
    property Columns: Integer read FColumns write SetColumns default 1;
    { -1 = nothing selected. Read = the checked child's index; write = check that child
      (out-of-range clears the selection). Setting it programmatically does NOT fire
      OnSelectionChanged (that is reserved for user clicks); the property setter's own
      change is silent, matching how a code-set value differs from a user gesture. }
    property ItemIndex: Integer read GetItemIndex write SetItemIndex default -1;
    { Fires when ItemIndex changes because the user clicked a radio child. }
    property OnSelectionChanged: TNotifyEvent read FOnSelectionChanged write FOnSelectionChanged;
    property Caption;
    property Alignment;
  end;

{ TyRadioGroupCellRect — PURE layout geometry (no control state), the headless-tested core.

  Given AClient (the ALREADY-INSET client rect, i.e. below the caption band), ACount total
  cells, AColumns columns, and a 0-based AIndex, return that cell's rect.

  Tiling is COLUMN-MAJOR: rows = ceil(ACount / AColumns); cells fill down column 0 first
  (indices 0..rows-1), then column 1, etc. Column widths split AClient evenly (the last
  column absorbs the horizontal rounding remainder); each cell is a fixed row height with
  the whole grid vertically centered in AClient so short lists do not hug the top edge.

  Returns an empty rect for a degenerate request (ACount <= 0, AColumns <= 0, AIndex out of
  range, or a zero-area client). }
function TyRadioGroupCellRect(const AClient: TRect; ACount, AColumns, AIndex: Integer; ARowH: Integer = 0): TRect;

implementation

const
  TyRadioRowH = 22;   // logical row height per radio child (matches the radio default)

function TyRadioGroupCellRect(const AClient: TRect; ACount, AColumns, AIndex: Integer; ARowH: Integer = 0): TRect;
var
  rows, col, row, cw, l, r, gridH, top, cy: Integer;
  clientW, clientH, rowH: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if ARowH > 0 then rowH := ARowH else rowH := TyRadioRowH;
  if (ACount <= 0) or (AColumns <= 0) then Exit;
  if (AIndex < 0) or (AIndex >= ACount) then Exit;
  clientW := AClient.Right - AClient.Left;
  clientH := AClient.Bottom - AClient.Top;
  if (clientW <= 0) or (clientH <= 0) then Exit;

  rows := (ACount + AColumns - 1) div AColumns;   // ceil
  if rows <= 0 then Exit;

  // Column-major placement: column first, row within column.
  col := AIndex div rows;
  row := AIndex mod rows;

  // Even column split; the last column extends to the client right edge so the tiling
  // covers [Left, Right) with no gap/overlap (integer-division remainder absorbed).
  cw := clientW div AColumns;
  l := AClient.Left + col * cw;
  if col = AColumns - 1 then
    r := AClient.Right
  else
    r := AClient.Left + (col + 1) * cw;

  // Vertically center the grid of `rows` fixed-height rows within the client height so a
  // short list sits centered rather than jammed against the caption band. When the grid
  // is taller than the client (many rows in a small box), pin to the top (top := 0).
  { ARowH>0 = 控件把 --row-height 解析成的行高,单一来源;0(测试)沿用常量。 }
  gridH := rows * rowH;
  if gridH < clientH then
    top := (clientH - gridH) div 2
  else
    top := 0;
  cy := AClient.Top + top + row * rowH;

  Result := Rect(l, cy, r, cy + rowH);
end;

{ TTyRadioGroup }

constructor TTyRadioGroup.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TStringList.Create;
  TStringList(FItems).OnChange := @ItemsChanged;
  FColumns := 1;
  Width := 185;
  Height := 130;
end;

destructor TTyRadioGroup.Destroy;
begin
  // The children are owned by Self and freed by the inherited destructor's component
  // teardown; drop our tracking array + the Items list explicitly.
  SetLength(FButtons, 0);
  FItems.Free;
  inherited Destroy;
end;

function TTyRadioGroup.Count: Integer;
begin
  Result := Length(FButtons);
end;

procedure TTyRadioGroup.SetItems(AValue: TStrings);
begin
  FItems.Assign(AValue);   // fires ItemsChanged -> RebuildButtons + LayoutButtons
end;

procedure TTyRadioGroup.ItemsChanged(Sender: TObject);
begin
  RebuildButtons;
end;

procedure TTyRadioGroup.SetColumns(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  if FColumns = AValue then Exit;
  FColumns := AValue;
  LayoutButtons;
  Invalidate;
end;

procedure TTyRadioGroup.ClearButtons;
var
  i: Integer;
begin
  for i := 0 to High(FButtons) do
    FreeAndNil(FButtons[i]);
  SetLength(FButtons, 0);
end;

procedure TTyRadioGroup.SetController(AValue: TTyStyleController);
var i: Integer;
begin
  inherited SetController(AValue);
  for i := 0 to High(FButtons) do
    if FButtons[i] <> nil then
      FButtons[i].Controller := AValue;
end;

procedure TTyRadioGroup.RebuildButtons;
var
  prevIndex, newIndex, i: Integer;
  prevCaption: string;
  hadSel: Boolean;
  rb: TTyRadioButton;
begin
  if FRebuilding then Exit;
  FRebuilding := True;
  try
    // Remember the selection by IDENTITY (caption), not raw index — so a mid-list Items edit
    // (delete/insert) doesn't migrate the selection onto a different item.
    prevIndex := GetItemIndex;
    hadSel := (prevIndex >= 0) and (prevIndex <= High(FButtons)) and (FButtons[prevIndex] <> nil);
    if hadSel then prevCaption := FButtons[prevIndex].Caption else prevCaption := '';
    ClearButtons;
    SetLength(FButtons, FItems.Count);
    for i := 0 to FItems.Count - 1 do
    begin
      rb := TTyRadioButton.Create(Self);   // owned by Self (freed with the group)
      // INTERNAL helper: never show up in the IDE designer object tree.
      rb.ControlStyle := rb.ControlStyle + [csNoDesignVisible];
      rb.Parent := Self;
      rb.GroupIndex := 0;                   // same parent + group => auto-exclusive
      rb.Caption := FItems[i];
      rb.OnChange := @ChildChanged;         // routes selection back to us
      // Inherit the group's controller so the radios theme with the same style set.
      rb.Controller := Controller;
      FButtons[i] := rb;
    end;
    LayoutButtons;
    // Re-apply the previous selection to the SAME item if it survived the edit.
    if hadSel then
    begin
      newIndex := FItems.IndexOf(prevCaption);
      if (newIndex >= 0) and (newIndex < Length(FButtons)) then
      begin
        FUpdatingIndex := True;   // silent: a rebuild is not a user selection change
        try
          FButtons[newIndex].Checked := True;
        finally
          FUpdatingIndex := False;
        end;
      end;
    end;
  finally
    FRebuilding := False;
  end;
  { A rebuild makes fresh children, each of which starts as a tab stop. Without this the
    group goes back to N tab stops the moment Items changes. }
  UpdateTabStops;
  Invalidate;
end;

procedure TTyRadioGroup.LayoutButtons;
var
  i, n: Integer;
  client, cell: TRect;
begin
  n := Length(FButtons);
  if n = 0 then Exit;
  // GetClientRect returns the RAW client rect — LCL applies AdjustClientRect only to ALIGNED
  // children, and our radios are alNone + placed by SetBounds. Inset it ourselves so they drop
  // below the caption band (else they paint over the group caption).
  client := ClientRect;
  AdjustClientRect(client);             // TTyGroupBox insets Top below the caption band
  for i := 0 to n - 1 do
  begin
    if FButtons[i] = nil then Continue;
    cell := TyRadioGroupCellRect(client, n, FColumns, i,
      ActiveController.Metric('--row-height', TyRadioRowH));
    FButtons[i].SetBounds(cell.Left, cell.Top, cell.Right - cell.Left, cell.Bottom - cell.Top);
  end;
end;

{ The group's selection changed, however it changed. OnClick as well as
  OnSelectionChanged: TCustomRadioGroup redeclares FOnClick and fires it on any selection
  change, so code ported from Lazarus hangs its logic there and would otherwise get
  nothing -- TControl's OnClick only fires when the GROUP BOX itself is clicked, which on
  a control whose whole surface is covered by its children is never. }
procedure TTyRadioGroup.NotifySelection;
begin
  if Assigned(FOnSelectionChanged) then FOnSelectionChanged(Self);
  if Assigned(OnClick) then OnClick(Self);
end;

{ Only the checked radio is a tab stop, so Tab enters the group once, lands on the current
  choice, and leaves. Every child was a tab stop, so tabbing through a form with a
  five-item radio group meant five stops inside one logical control -- and arrow keys, the
  keys that actually move a radio selection, had nothing to do. LCL: UpdateTabStops. }
procedure TTyRadioGroup.UpdateTabStops;
var
  i, sel: Integer;
begin
  sel := GetItemIndex;
  if (sel < 0) and (Length(FButtons) > 0) then sel := 0;   { nothing chosen: the first }
  for i := 0 to High(FButtons) do
    if FButtons[i] <> nil then
      FButtons[i].TabStop := (i = sel);
end;

procedure TTyRadioGroup.ChildChanged(Sender: TObject);
begin
  // A child's Checked flipped. When a radio becomes checked it unchecks its siblings,
  // each of which ALSO fires ChildChanged — the FUpdatingIndex guard collapses that
  // storm into a single OnSelectionChanged for the one real gesture. We only fire on a
  // child turning ON (a sibling turning OFF is part of the same selection change).
  if FUpdatingIndex then Exit;
  if not (Sender is TTyRadioButton) then Exit;
  if not TTyRadioButton(Sender).Checked then Exit;   // ignore the uncheck half
  FUpdatingIndex := True;
  try
    UpdateTabStops;
    NotifySelection;
  finally
    FUpdatingIndex := False;
  end;
end;

function TTyRadioGroup.GetItemIndex: Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(FButtons) do
    if (FButtons[i] <> nil) and FButtons[i].Checked then
      Exit(i);
end;

procedure TTyRadioGroup.SetItemIndex(AValue: Integer);
var
  i: Integer;
begin
  { -1 is legal and means "nothing chosen"; anything else out of range is a caller bug.
    It used to silently CLEAR the selection instead -- so `RG.ItemIndex := 5` on a
    three-item group looked exactly like `RG.ItemIndex := -1`, and an off-by-one in the
    code that computes the index reads as "the user deselected", which is a plausible
    state and therefore never investigated. LCL raises here for the same reason
    (radiogroup.inc:387), and TTyCheckGroup.Checked[] was given the same treatment on this
    branch; the message shape is deliberately identical so the two read alike in a log.
    Streaming is exempt: a .lfm whose ItemIndex precedes its Items would otherwise abort
    ReadComponent and take the whole form down with it. }
  if (AValue < -1) or (AValue >= FItems.Count) then
  begin
    if csLoading in ComponentState then
      AValue := -1
    else
      raise EListError.CreateFmt('%s Index %d out of bounds -1 .. %d',
        [ClassName, AValue, FItems.Count - 1]);
  end;
  if GetItemIndex = AValue then Exit;
  { The guard collapses the child-event storm (checking one radio unchecks its siblings,
    each of which fires) into ONE notification -- it is not there to make a programmatic
    set silent. It used to do both, so `RG.ItemIndex := 2` changed the selection and told
    nobody: a handler that keeps a detail panel in step with the choice worked when the
    user clicked and silently did not when the app restored a saved selection. LCL
    deliberately notifies either way (radiogroup.inc, "to be delphi compat"). }
  FUpdatingIndex := True;
  try
    if (AValue >= 0) and (AValue < Length(FButtons)) then
    begin
      if FButtons[AValue] <> nil then FButtons[AValue].Checked := True;
    end
    else
      // Out of range: clear any current selection.
      for i := 0 to High(FButtons) do
        if FButtons[i] <> nil then FButtons[i].Checked := False;
  finally
    FUpdatingIndex := False;
  end;
  UpdateTabStops;
  Invalidate;
  NotifySelection;
end;

procedure TTyRadioGroup.SetParent(AParent: TWinControl);
begin
  inherited SetParent(AParent);
  // Once we have a parent (and thus a valid ClientRect), re-place the children.
  LayoutButtons;
end;

procedure TTyRadioGroup.DoOnResize;
begin
  inherited DoOnResize;
  LayoutButtons;   // reflow the grid when the box is resized
end;

end.
