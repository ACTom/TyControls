unit tyControls.RadioGroup;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, LCLType, LMessages, ExtCtrls,
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

    Layout fills across Columns columns in the order ColumnLayout names -- across each row
    first by default, which is what LCL's TRadioGroup does (ColumnLayout
    = clHorizontalThenVertical, extctrls.pp:777). The geometry is a pure unit-level function
    (TyRadioGroupCellRect) so it is headless-testable in isolation; the row PITCH it tiles
    with is a second pure function shared with TTyCheckGroup (TyGroupRowPitch, in
    tyControls.GroupBox) -- see RowPitch below for why the pitch is not simply the token.

    THE RING AND THE DOT ARE ONE GESTURE. Two separate defects used to pull them apart, and
    both are worth knowing about before touching this file:
      * a click moved the DOT but not the RING (only the second click moved it) -- the group
        hands out a single tab stop and TTyCustomControl.MouseDown gates focus-on-click on
        it; see ItemMouseDown;
      * the ring's bottom edge was CLIPPED by the row below it -- the pitch was shorter than
        the children LCL was clamping into it; see RowPitch.
    Neither is visible from the headless suite (no caret on a form that was never shown, and
    the test process measures the caption font short enough that the overlap cannot arise).
    tests/radiofocusverify is the real-window half and is not optional cover. }
  TTyRadioGroup = class(TTyGroupBox)
  private
    FItems: TStrings;
    FColumns: Integer;
    FColumnLayout: TColumnLayout;
    FButtons: array of TTyRadioButton;
    FOnSelectionChanged: TNotifyEvent;
    FOnItemEnter: TNotifyEvent;
    FOnItemExit: TNotifyEvent;
    FRebuilding: Boolean;      // re-entrancy guard for RebuildButtons
    FUpdatingIndex: Boolean;   // re-entrancy guard for the child OnChange router
    procedure SetItems(AValue: TStrings);
    procedure ItemsChanged(Sender: TObject);
    procedure SetColumns(AValue: Integer);
    procedure SetColumnLayout(AValue: TColumnLayout);
    function GetItemIndex: Integer;
    procedure SetItemIndex(AValue: Integer);
    function GetButton(AIndex: Integer): TTyRadioButton;
    procedure RaiseIndexOutOfBounds(AIndex: Integer);
    procedure ClearButtons;
    procedure RebuildButtons;
    procedure LayoutButtons;
    procedure ChildChanged(Sender: TObject);
    procedure NotifySelection;
    procedure UpdateTabStops;
    { The row PITCH the grid tiles with, in device pixels.

      --row-height is the theme's say in it, but it is only the FLOOR-of-taste: the hosted
      radio has its own minimum height (caption line + the themed --pad-control, never less
      than --radio-size; TTyRadioButton.UpdateSizeConstraints), LCL clamps every SetBounds
      up to Constraints.MinHeight, and a pitch shorter than that clamp does not produce
      shorter rows -- it produces OVERLAPPING ones. On the default light theme at 96ppi the
      token says 22 and the radio's own minimum is 25, so consecutive rows used to overlap
      by 3px; the next row is a LATER sibling and therefore higher in the z-order, so it
      painted over the bottom 3px of the row above -- taking the whole bottom edge of the
      2px :focus ring with it. That is the "the ring is cut off along the bottom" report,
      and it is invisible on the LAST row (nothing below it to paint over it), which is why
      only a probe at the row BOUNDARY finds it.
      Both halves stay theme-driven: the token is a token, and the floor is derived from the
      radio's own themed metrics. No pixel constant is introduced here. }
    function RowPitch: Integer;
    { Move the selection one cell in the direction (AHorzDiff, AVertDiff), honouring
      ColumnLayout, skipping items that cannot take it, and focusing the one it lands on.
      See ItemKeyDown for why this is the group's job and not the radio's. }
    procedure MoveSelection(AHorzDiff, AVertDiff: Integer);
    { The four child-key relays. The group never holds focus -- its whole surface is covered
      by its children -- so without these its OnKeyDown/OnKeyUp/OnKeyPress/OnUTF8KeyPress
      could be assigned and could never fire. LCL wires the identical four
      (include/radiogroup.inc:186-191). ItemKeyDown additionally implements arrow
      navigation, the half of the radio-group keyboard contract a single radio cannot
      provide: only the GROUP knows the grid, so only the group can find the neighbour. }
    procedure ItemKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ItemKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ItemKeyPress(Sender: TObject; var Key: char);
    procedure ItemUTF8KeyPress(Sender: TObject; var UTF8Key: TUTF8Char);
    procedure ItemEnter(Sender: TObject);
    procedure ItemExit(Sender: TObject);
    { A left press on one option. The group has to hand the caret over ITSELF because it is
      the group that took the tab stop away from every unchosen option: UpdateTabStops leaves
      TabStop True on the CHECKED item only (LCL does the same -- radiogroup.inc:561), and
      TTyCustomControl.MouseDown gates focus-on-click on `TabStop and CanFocus and not
      Focused` (tyControls.Base.pas). So the one option that could take the caret from a
      click was the one that already had the selection: clicking any OTHER option moved the
      DOT and left the RING behind, and only the second click -- by which time the first had
      handed that option the tab stop -- moved the ring. LCL's own radio group is not exposed
      to this because its children are NATIVE TRadioButtons and Windows focuses a clicked
      control whatever WS_TABSTOP says; a self-drawn child gets no such favour.
      Wired to OnMouseDown, which TControl.MouseDown fires BEFORE that gate is evaluated, so
      by the time the gate runs the option is already focused and the gate is a no-op --
      one SetFocus per press, not two. }
    procedure ItemMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
  protected
    { The ONE place this group asks for the caret -- mouse and keyboard both come through
      here, so "the ring follows the dot" is a single rule with a single implementation
      rather than two that can drift apart.
      Virtual on purpose: the OS half (SetFocus) cannot run on a form that was never shown
      -- CanFocus answers False there -- so a headless test asserting Focused would be
      permanently, falsely green. A test overrides this to watch the REQUEST, and
      tests/radiofocusverify proves on a real window that the request lands. }
    procedure FocusItem(AIndex: Integer); virtual;
    procedure SetParent(AParent: TWinControl); override;
    procedure DoOnResize; override;
    // Keep the internal radio children on the group's controller so a controller assigned
    // AFTER population still themes them (mirrors TTyCheckGroup.SetController).
    procedure SetController(AValue: TTyStyleController); override;
    { Reading direction changed, so the COLUMNS changed sides -- and the children sit where
      SetBounds last put them, which LCL's own handling never revisits (it invalidates and
      calls AdjustSize; neither re-runs a layout done by hand). Without this the columns keep
      their old order and only each indicator flips, which looks like the mirroring half
      worked and the other half silently did not. }
    procedure CMBiDiModeChanged(var Message: TLMessage); message CM_BIDIMODECHANGED;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Number of item rows == number of radio children. }
    function Count: Integer;
    { Which option currently holds the caret (the FOCUS RING), or -1 when the group does not
      have the focus at all. Deliberately separate from ItemIndex, which answers the other
      question -- which option is CHECKED (the dot). The two are the same after any single
      gesture, and a user report that they had come apart is what this accessor exists to
      make sayable: before, nothing in the public surface could even state the symptom. }
    function FocusedIndex: Integer;
    { The hosted radio itself -- the way to reach one option's Hint, Font, PopupMenu or
      Enabled. LCL publishes the same accessor under the same name (extctrls.pp:773) and
      raises out of range (include/radiogroup.inc:534-540), so this does too. The group
      still owns the child's lifetime and bounds: do not reparent or free one. }
    property Buttons[AIndex: Integer]: TTyRadioButton read GetButton;
  published
    property Items: TStrings read FItems write SetItems;
    property Columns: Integer read FColumns write SetColumns default 1;
    { Which way the item grid FILLS -- see TTyCheckGroup.ColumnLayout, which is the same
      property with the same default. clHorizontalThenVertical (the default, and LCL's)
      reads 6 items in 2 columns as 1 2 / 3 4 / 5 6.
      BREAKING: this control used to be hard-wired column-major (1 4 / 2 5 / 3 6) with no
      way to say otherwise, and the unit header used to record that divergence instead of
      fixing it. Single-column groups -- the default -- are unaffected; a multi-column group
      that wants the old order says ColumnLayout := clVerticalThenHorizontal.
      Arrow-key navigation reads this too, so the keys always move to the neighbour the
      user can SEE. }
    property ColumnLayout: TColumnLayout read FColumnLayout write SetColumnLayout
      default clHorizontalThenVertical;
    { -1 = nothing selected. Read = the checked child's index; write = check that child
      (out-of-range clears the selection). Setting it programmatically does NOT fire
      OnSelectionChanged (that is reserved for user clicks); the property setter's own
      change is silent, matching how a code-set value differs from a user gesture. }
    property ItemIndex: Integer read GetItemIndex write SetItemIndex default -1;
    { Fires when ItemIndex changes because the user clicked a radio child. }
    property OnSelectionChanged: TNotifyEvent read FOnSelectionChanged write FOnSelectionChanged;
    { Focus entered / left ONE option, with Sender = that TTyRadioButton -- the hook for
      per-option help text, a status-bar hint, or a preview that follows the keyboard.
      LCL: extctrls.pp:779-780, wired at include/radiogroup.inc:186-187 with the same
      Sender convention (the button, not the group). }
    property OnItemEnter: TNotifyEvent read FOnItemEnter write FOnItemEnter;
    property OnItemExit: TNotifyEvent read FOnItemExit write FOnItemExit;
    property Caption;
    property Alignment;
  end;

{ TyRadioGroupCellRect — PURE layout geometry (no control state), the headless-tested core.

  Given AClient (the ALREADY-INSET client rect, i.e. below the caption band), ACount total
  cells, AColumns columns, and a 0-based AIndex, return that cell's rect.

  rows = ceil(ACount / AColumns) either way; ALayout picks the FILL ORDER:
    clHorizontalThenVertical (the default, and LCL's) — across each row first, so 4 items in
                                                        2 columns sit 0 1 / 2 3.
    clVerticalThenHorizontal                          — down each column first: 0 2 / 1 3.
  Column widths split AClient evenly (the last column absorbs the horizontal rounding
  remainder); each cell is a fixed row height with the whole grid vertically centered in
  AClient so short lists do not hug the top edge.

  Returns an empty rect for a degenerate request (ACount <= 0, AColumns <= 0, AIndex out of
  range, or a zero-area client).

  ARightToLeft reverses the COLUMN order (item 0 in the rightmost column), by reflecting the
  finished cell about AClient — see TyCheckGroupCellRect for why it is a reflection and not
  an index flip. Rows and the vertical centring are unaffected. }
function TyRadioGroupCellRect(const AClient: TRect; ACount, AColumns, AIndex: Integer;
  ARowH: Integer = 0; ALayout: TColumnLayout = clHorizontalThenVertical;
  ARightToLeft: Boolean = False): TRect;

implementation

const
  TyRadioRowH = 22;   // logical row height per radio child (matches the radio default)

function TyRadioGroupCellRect(const AClient: TRect; ACount, AColumns, AIndex: Integer;
  ARowH: Integer = 0; ALayout: TColumnLayout = clHorizontalThenVertical;
  ARightToLeft: Boolean = False): TRect;
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

  if ALayout = clVerticalThenHorizontal then
  begin
    col := AIndex div rows;   // column-major: fill down column 0 first
    row := AIndex mod rows;
  end
  else
  begin
    col := AIndex mod AColumns;   // row-major: fill across row 0 first
    row := AIndex div AColumns;
  end;

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
  // Reflect the finished cell — see TyCheckGroupCellRect, same reason, same one line.
  if ARightToLeft then
    Result := BidiFlipRect(Result, AClient, True);
end;

{ TTyRadioGroup }

constructor TTyRadioGroup.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TStringList.Create;
  TStringList(FItems).OnChange := @ItemsChanged;
  FColumns := 1;
  FColumnLayout := clHorizontalThenVertical;   // LCL's default fill order
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

function TTyRadioGroup.FocusedIndex: Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(FButtons) do
    if (FButtons[i] <> nil) and FButtons[i].Focused then
      Exit(i);
end;

procedure TTyRadioGroup.FocusItem(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FButtons)) then Exit;
  if FButtons[AIndex] = nil then Exit;
  if not FButtons[AIndex].Enabled then Exit;
  { CanFocus alone is not enough -- it answers from Visible/Enabled up the parent chain and
    says True for a control on a form that was never shown, so SetFocus then raises "TForm
    Can not focus"; it would raise in an app too, for a group on a hidden or inactive form.
    A realised handle is the honest test that a caret exists at all. }
  if FButtons[AIndex].HandleAllocated and FButtons[AIndex].CanFocus
     and not FButtons[AIndex].Focused then
    { Swallowed the way TTyCustomControl.MouseDown swallows its own: SetFocus can still
      refuse (a modal form elsewhere owns the caret), and this runs inside a mouse-down
      handler, where letting it out means an exception dialog in the middle of a click.
      Losing the ring is cosmetic; losing the click is not. }
    try FButtons[AIndex].SetFocus except end;
end;

procedure TTyRadioGroup.ItemMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  i: Integer;
begin
  if Button <> mbLeft then Exit;          // a right press opens a menu; it moves nothing
  for i := 0 to High(FButtons) do
    if FButtons[i] = Sender then
    begin
      FocusItem(i);
      Exit;
    end;
end;

function TTyRadioGroup.RowPitch: Integer;
var
  i, itemMin, ppi: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  itemMin := 0;
  for i := 0 to High(FButtons) do
    if (FButtons[i] <> nil) and (FButtons[i].Constraints.MinHeight > itemMin) then
      itemMin := FButtons[i].Constraints.MinHeight;
  { The token is LOGICAL pixels; the cell rects are device pixels of our own client area.
    Without this MulDiv a 150% display laid 22-device-px rows under 37-device-px radios --
    the same overlap TyGroupRowPitch exists to stop, only worse, and only on a HiDPI
    machine where nobody was looking. }
  Result := TyGroupRowPitch(
    MulDiv(ActiveController.Metric('--row-height', TyRadioRowH), ppi, 96), itemMin);
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

procedure TTyRadioGroup.SetColumnLayout(AValue: TColumnLayout);
begin
  if FColumnLayout = AValue then Exit;
  FColumnLayout := AValue;
  LayoutButtons;   // the fill order IS the layout; re-place, do not just repaint
  Invalidate;
end;

procedure TTyRadioGroup.RaiseIndexOutOfBounds(AIndex: Integer);
begin
  { Same message shape as TTyCheckGroup's and as LCL's rsIndexOutOfBounds, so the two read
    alike in a log. Note the range is 0..n-1 here -- unlike ItemIndex, where -1 is a legal
    "nothing chosen" and the message says so. }
  raise EListError.CreateFmt('%s Index %d out of bounds 0 .. %d',
    [ClassName, AIndex, Length(FButtons) - 1]);
end;

function TTyRadioGroup.GetButton(AIndex: Integer): TTyRadioButton;
begin
  if (AIndex < 0) or (AIndex > High(FButtons)) then
    RaiseIndexOutOfBounds(AIndex);
  Result := FButtons[AIndex];
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
      { Focus lives on the child, never on the group, so the group's own key and focus
        events can only ever fire through these relays. ItemKeyDown is also where arrow
        navigation lives -- see there. }
      rb.OnKeyDown := @ItemKeyDown;
      rb.OnKeyUp := @ItemKeyUp;
      rb.OnKeyPress := @ItemKeyPress;
      rb.OnUTF8KeyPress := @ItemUTF8KeyPress;
      rb.OnEnter := @ItemEnter;
      rb.OnExit := @ItemExit;
      rb.OnMouseDown := @ItemMouseDown;     // the ring follows the pointer -- see ItemMouseDown
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
    // MIRRORING: columns reverse; each hosted radio flips its own dot via ParentBiDiMode.
    // See TTyCheckGroup.LayoutCheckBoxes -- there is no hit test on this side either.
    cell := TyRadioGroupCellRect(client, n, FColumns, i,
      RowPitch, FColumnLayout, IsRightToLeft);
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

{ Arrow navigation. Only the GROUP can do this: moving "one to the right" means knowing the
  column count and the fill order, and a lone TTyRadioButton knows neither -- which is why
  arrows did nothing at all before, leaving Tab-to-each-item-plus-Space as the only keyboard
  route, and that route CHANGES THE SELECTION on the way past every option it touches.

  The step is the same arithmetic LCL uses (include/radiogroup.inc:260-297): one cell
  horizontally is +1 in row-major order and +Rows in column-major, and one cell vertically is
  the other way round. Items that cannot take the selection are stepped OVER rather than
  stopped on, so a disabled option does not become a wall. }
procedure TTyRadioGroup.MoveSelection(AHorzDiff, AVertDiff: Integer);
var
  rows, step, i, n: Integer;
begin
  n := Length(FButtons);
  if n = 0 then Exit;
  { MIRRORING, the keyboard half. The columns reversed, so a horizontal step must reverse
    with them or Left walks the selection BACKWARDS relative to what the user sees -- the
    single most reviewer-invisible way a mirrored control goes wrong, since every instance
    of it is just a missing minus sign (plans/2026-08-04-rtl-mirroring-scope.md §5.3).
    This is LAYOUT direction, not text direction: an arrow key inside an edit stays the
    bidi layer's business and is deliberately not touched (§6.3 item 4). }
  if IsRightToLeft then AHorzDiff := -AHorzDiff;
  rows := (n + FColumns - 1) div FColumns;   // ceil, matching TyRadioGroupCellRect
  if rows < 1 then rows := 1;
  if FColumnLayout = clVerticalThenHorizontal then
    step := AHorzDiff * rows + AVertDiff
  else
    step := AHorzDiff + AVertDiff * FColumns;
  if step = 0 then Exit;
  i := GetItemIndex;
  if i < 0 then
    // Nothing chosen yet: the first arrow selects the first usable option rather than
    // walking off the end from a phantom -1.
    i := 0
  else
    Inc(i, step);
  while (i >= 0) and (i < n) do
  begin
    if (FButtons[i] <> nil) and FButtons[i].Enabled and FButtons[i].Visible then
    begin
      { Through the property, not the field: a keyboard move IS a selection change, so it
        must notify exactly as a click does and must re-hand the single tab stop. }
      ItemIndex := i;
      { Follow the selection with the caret. Through FocusItem, the same seam the mouse uses:
        "the ring goes where the dot went" is one rule, so it gets one implementation. }
      FocusItem(i);
      Exit;
    end;
    Inc(i, step);
  end;
end;

{ Re-raise on the GROUP first, so a group-level handler can swallow a key before the
  navigation sees it; then, if the key survived, move the selection. }
procedure TTyRadioGroup.ItemKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
  if Shift * [ssShift, ssAlt, ssCtrl] <> [] then Exit;   // modified arrows are not ours
  case Key of
    VK_LEFT:  begin MoveSelection(-1,  0); Key := 0; end;
    VK_RIGHT: begin MoveSelection( 1,  0); Key := 0; end;
    VK_UP:    begin MoveSelection( 0, -1); Key := 0; end;
    VK_DOWN:  begin MoveSelection( 0,  1); Key := 0; end;
  end;
end;

procedure TTyRadioGroup.ItemKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  KeyUp(Key, Shift);
end;

procedure TTyRadioGroup.ItemKeyPress(Sender: TObject; var Key: char);
begin
  KeyPress(Key);
end;

procedure TTyRadioGroup.ItemUTF8KeyPress(Sender: TObject; var UTF8Key: TUTF8Char);
begin
  UTF8KeyPress(UTF8Key);
end;

{ Sender stays the BUTTON, as LCL's does -- the whole point is to know WHICH option the
  keyboard is on, which a Sender of Self would not tell anyone. }
procedure TTyRadioGroup.ItemEnter(Sender: TObject);
begin
  if Assigned(FOnItemEnter) then FOnItemEnter(Sender);
end;

procedure TTyRadioGroup.ItemExit(Sender: TObject);
begin
  if Assigned(FOnItemExit) then FOnItemExit(Sender);
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

procedure TTyRadioGroup.CMBiDiModeChanged(var Message: TLMessage);
begin
  inherited;       // LCL invalidates, tells the children, and calls AdjustSize
  LayoutButtons;   // and then the columns have to actually change sides
end;

end.
