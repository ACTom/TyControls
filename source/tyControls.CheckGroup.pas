unit tyControls.CheckGroup;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, LCLType, LMessages, ExtCtrls,
  tyControls.Controller, tyControls.GroupBox, tyControls.CheckBox;
type
  { Fired when a hosted checkbox toggles; AIndex is that item's index. }
  TCheckGroupItemEvent = procedure(Sender: TObject; AIndex: Integer) of object;

  { LCL spells the same event TCheckGroupClicked (extctrls.pp:852) with an identical
    parameter list, and hangs it on OnItemClick. The alias lets a ported handler
    declaration compile unchanged; OnItemClick below is the property it binds to. }
  TCheckGroupClicked = TCheckGroupItemEvent;

  { TTyCheckGroup — a titled frame (subclasses TTyGroupBox) that auto-populates one
    TTyCheckBox per Items entry, laid out in a column grid inside the group's client
    rect (which TTyGroupBox already insets below the caption band). Unlike a radio
    group, the checkboxes are INDEPENDENT — no mutual exclusion. The child controls
    are internal helpers (owned by Self, csNoDesignVisible) so they never leak into
    the IDE designer; they are rebuilt whenever Items changes, preserving the checked
    state by index where the item still exists. }
  TTyCheckGroup = class(TTyGroupBox)
  private
    FItems: TStrings;
    FColumns: Integer;
    FColumnLayout: TColumnLayout;
    FCheckBoxes: array of TTyCheckBox;
    FOnItemChange: TCheckGroupItemEvent;
    FOnItemClick: TCheckGroupClicked;
    FRebuilding: Boolean;
    procedure SetItems(AValue: TStrings);
    procedure ItemsChanged(Sender: TObject);
    procedure SetColumns(AValue: Integer);
    procedure SetColumnLayout(AValue: TColumnLayout);
    function GetChecked(AIndex: Integer): Boolean;
    procedure SetChecked(AIndex: Integer; AValue: Boolean);
    function GetButton(AIndex: Integer): TTyCheckBox;
    function GetCheckEnabled(AIndex: Integer): Boolean;
    procedure SetCheckEnabled(AIndex: Integer; AValue: Boolean);
    procedure ClearCheckBoxes;
    procedure RebuildCheckBoxes;
    procedure LayoutCheckBoxes;
    procedure ChildChanged(Sender: TObject);   // wired to each child's OnChange
    { Re-raise a hosted item's key events ON THE GROUP. The group never holds focus --
      every pixel of it is covered by its children -- so without these its OnKeyDown /
      OnKeyUp / OnKeyPress / OnUTF8KeyPress could be assigned and could never fire, which
      is the silent-no-op this pass exists to remove. LCL wires the identical four
      (include/customcheckgroup.inc:238-241, handlers :147-171). }
    procedure ItemKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ItemKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ItemKeyPress(Sender: TObject; var Key: char);
    procedure ItemUTF8KeyPress(Sender: TObject; var UTF8Key: TUTF8Char);
    { Names the class, the offending index and the largest valid one -- a form with six
      groups on it needs all three to be actionable. Same shape as LCL's
      rsIndexOutOfBounds ('%s Index %d out of bounds 0 .. %d',
      C:/lazarus/lcl/lclstrconsts.pas:268, raised by
      include/customcheckgroup.inc:173-177). }
    procedure RaiseIndexOutOfBounds(AIndex: Integer);
  protected
    { The AIndex-th hosted checkbox, or nil when out of range. Protected: the group owns
      its children's lifetime and layout, so handing them out publicly would invite code
      that reparents or frees one. A descendant (and a test probe) legitimately needs to
      reach the child to simulate what a real click does.
      Deliberately NOT raising the way Checked[] now does: this is an internal probe with
      no LCL counterpart, and "is there a child here?" is a question a descendant may
      legitimately ask about an index it has not validated. nil IS the answer. }
    function CheckBoxAt(AIndex: Integer): TTyCheckBox;
    procedure SetParent(AParent: TWinControl); override;
    procedure Resize; override;
    procedure SetController(AValue: TTyStyleController); override;
    { See TTyRadioGroup.CMBiDiModeChanged: LCL's own handling invalidates and calls
      AdjustSize, neither of which re-runs a layout this control did with SetBounds -- so
      without this the indicators would flip and the columns would not. }
    procedure CMBiDiModeChanged(var Message: TLMessage); message CM_BIDIMODECHANGED;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Number of hosted checkboxes (= Items.Count). }
    function Count: Integer;
    { How many items are currently checked. }
    function CheckedCount: Integer;
    { AIndex-th checkbox's Checked state (indexed property). An out-of-range index on
      EITHER side RAISES EListError naming the class, the index and the maximum -- as
      LCL's TCustomCheckGroup does (include/customcheckgroup.inc:313-338). It used to
      answer False for a read and drop a write, which is exactly how a populate-order
      or off-by-one bug hides: an item that does not exist is indistinguishable from
      one the user simply left unticked, and a lost write looks like the user unticking
      it again. Note CheckedCount and Count are the safe ways to ask about the range. }
    property Checked[AIndex: Integer]: Boolean read GetChecked write SetChecked;
    { The hosted checkbox itself, so a host can reach anything the group does not
      re-expose -- one item's Hint, PopupMenu, Font or an extra event hook. LCL hands out
      the same thing under the same name (extctrls.pp:901, public) and raises out of range
      (include/customcheckgroup.inc:321-326), so this does too.
      The group still OWNS the child: reparenting or freeing one through this handle
      corrupts the group's array. That is exactly the risk CheckBoxAt was protected to
      avoid, and it is why the two coexist -- CheckBoxAt answers "is there a child here?"
      for internal code that has not validated its index, Buttons[] is the app-facing
      accessor that blames a bad index. }
    property Buttons[AIndex: Integer]: TTyCheckBox read GetButton;
    { Enable/disable ONE item while the rest stay live -- the standard "this option is not
      available in your edition" greying. Out of range raises on either side, as
      Checked[] does. LCL: extctrls.pp:904, include/customcheckgroup.inc:288-301.
      Survives an Items edit the same way Checked[] does: RebuildCheckBoxes restores the
      flag onto the item with the SAME CAPTION, not onto whatever slides into that slot. }
    property CheckEnabled[AIndex: Integer]: Boolean read GetCheckEnabled write SetCheckEnabled;
  published
    property Items: TStrings read FItems write SetItems;
    property Columns: Integer read FColumns write SetColumns default 1;
    { Which way the item grid FILLS. clHorizontalThenVertical (the default, and LCL's --
      extctrls.pp:906) runs across each row first, so 6 items in 2 columns read
      1 2 / 3 4 / 5 6; clVerticalThenHorizontal fills down each column first and they read
      1 4 / 2 5 / 3 6.
      BREAKING: this control used to be hard-wired column-major with no way to say
      otherwise, so a multi-column group silently disagreed with the same .lfm loaded in
      Lazarus. Single-column groups (the default) are unaffected; a multi-column group that
      wants the old order says ColumnLayout := clVerticalThenHorizontal. }
    property ColumnLayout: TColumnLayout read FColumnLayout write SetColumnLayout
      default clHorizontalThenVertical;
    property OnItemChange: TCheckGroupItemEvent read FOnItemChange write FOnItemChange;
    { LCL's name for the very same notification (extctrls.pp:907, published on TCheckGroup
      at :955). Both fire, OnItemChange first, so an existing handler keeps working and a
      ported one binds without being renamed -- the alternative was to rename ours and
      break every form already built on it. }
    property OnItemClick: TCheckGroupClicked read FOnItemClick write FOnItemClick;
    { Caption / Alignment inherited from TTyGroupBox; the frame + caption band. }
  end;

{ The device-px cell rect of item AIndex within a client area AClientRect, given
  ACount items laid out in AColumns columns with each row ARowH device px tall.

  ALayout picks the FILL ORDER, exactly as TCustomCheckGroup.ColumnLayout does:
    clHorizontalThenVertical (the default) — across each row first: 4 items / 2 columns
                                             sit 0 1 / 2 3.
    clVerticalThenHorizontal                — down each column first: 0 2 / 1 3.

  Columns divide the client width evenly; the last column absorbs the width remainder so
  cells tile flush. Rows stack from the top; a partially-filled last row/column simply has
  fewer cells. An out-of-range AIndex, ACount <= 0, AColumns <= 0 or ARowH <= 0 yields an
  empty rect. PURE — no control state; unit-tested directly.

  ARightToLeft reverses the COLUMN order: item 0 starts in the rightmost column and the
  fill order runs leftwards. Rows are untouched (top-to-bottom is not a reading direction
  this library mirrors). Implemented as a reflection of the finished cell about AClientRect
  rather than as `col := cols - 1 - col`, so the flush tiling — which the remainder-absorbing
  last column exists to guarantee — is preserved by construction instead of by argument. }
function TyCheckGroupCellRect(const AClientRect: TRect;
  ACount, AColumns, AIndex, ARowH: Integer;
  ALayout: TColumnLayout = clHorizontalThenVertical;
  ARightToLeft: Boolean = False): TRect;

implementation

function TyCheckGroupCellRect(const AClientRect: TRect;
  ACount, AColumns, AIndex, ARowH: Integer;
  ALayout: TColumnLayout = clHorizontalThenVertical;
  ARightToLeft: Boolean = False): TRect;
var
  cols, rowsPerCol, col, row, colW, l, r, cw: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if (ACount <= 0) or (AColumns <= 0) or (AIndex < 0) or (AIndex >= ACount) then Exit;
  if ARowH <= 0 then Exit;

  cols := AColumns;
  if cols > ACount then cols := ACount;   // never more columns than items
  // Ceil-divide items across columns; the same row count serves both fill orders.
  rowsPerCol := (ACount + cols - 1) div cols;
  if rowsPerCol < 1 then rowsPerCol := 1;

  if ALayout = clVerticalThenHorizontal then
  begin
    col := AIndex div rowsPerCol;   // column 0 fills top-to-bottom first
    row := AIndex mod rowsPerCol;
  end
  else
  begin
    col := AIndex mod cols;         // row 0 fills left-to-right first
    row := AIndex div cols;
  end;
  if col > cols - 1 then col := cols - 1;  // clamp (defensive; the maths keeps it in range)

  cw := AClientRect.Right - AClientRect.Left;
  colW := cw div cols;
  l := AClientRect.Left + col * colW;
  if col = cols - 1 then
    r := AClientRect.Right          // last column absorbs the width remainder
  else
    r := AClientRect.Left + (col + 1) * colW;

  Result := Rect(l,
                 AClientRect.Top + row * ARowH,
                 r,
                 AClientRect.Top + row * ARowH + ARowH);
  { Reflect the finished cell about AClientRect's vertical centre — LCL's own five-liner
    (controls.pp:2966), because a reflection of a gapless tiling is gapless and a
    hand-written index flip is where the seam would come from. }
  if ARightToLeft then
    Result := BidiFlipRect(Result, AClientRect, True);
end;

{ TTyCheckGroup }

constructor TTyCheckGroup.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TStringList.Create;
  TStringList(FItems).OnChange := @ItemsChanged;
  FColumns := 1;
  FColumnLayout := clHorizontalThenVertical;   // LCL's default fill order
  FRebuilding := False;
  Width := 185;
  Height := 130;
end;

destructor TTyCheckGroup.Destroy;
begin
  // Children are owned by Self and freed by the inherited destructor, but clear our
  // array first so any late Notification/OnChange can't touch a stale reference.
  ClearCheckBoxes;
  FItems.Free;
  inherited Destroy;
end;

function TTyCheckGroup.Count: Integer;
begin
  Result := FItems.Count;
end;

function TTyCheckGroup.CheckedCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(FCheckBoxes) do
    if (FCheckBoxes[i] <> nil) and FCheckBoxes[i].Checked then Inc(Result);
end;

procedure TTyCheckGroup.SetItems(AValue: TStrings);
begin
  FItems.Assign(AValue);   // fires ItemsChanged -> rebuild + relayout
end;

procedure TTyCheckGroup.ItemsChanged(Sender: TObject);
begin
  RebuildCheckBoxes;
end;

procedure TTyCheckGroup.SetColumns(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  if FColumns = AValue then Exit;
  FColumns := AValue;
  LayoutCheckBoxes;
  Invalidate;
end;

procedure TTyCheckGroup.SetColumnLayout(AValue: TColumnLayout);
begin
  if FColumnLayout = AValue then Exit;
  FColumnLayout := AValue;
  LayoutCheckBoxes;   // the fill order IS the layout; re-place, do not just repaint
  Invalidate;
end;

procedure TTyCheckGroup.ClearCheckBoxes;
var
  i: Integer;
begin
  for i := 0 to High(FCheckBoxes) do
    FreeAndNil(FCheckBoxes[i]);
  SetLength(FCheckBoxes, 0);
end;

procedure TTyCheckGroup.RebuildCheckBoxes;
var
  i, n, idx: Integer;
  oldChecked, oldDisabled: TStringList;
  cb: TTyCheckBox;
begin
  if FRebuilding then Exit;   // guard against re-entrancy (child churn shouldn't recurse)
  FRebuilding := True;
  oldChecked := TStringList.Create;
  oldDisabled := TStringList.Create;
  try
    // Snapshot the CHECKED items BY IDENTITY (caption), not by raw slot index — so a mid-list
    // edit (delete/insert), not just an append, preserves each user check on its OWN item
    // instead of migrating it onto whatever slides into that index. Duplicate captions are
    // consumed one-for-one (Delete below) so N checked "A"s restore onto the first N "A"s.
    oldChecked.CaseSensitive := True;
    // CheckEnabled rides along on the same identity rule: a per-item greying that survived
    // only until the next Items edit would be a knob that works in the demo and not in the
    // app. The DISABLED ones are what is recorded, because enabled is the resting state.
    oldDisabled.CaseSensitive := True;
    for i := 0 to High(FCheckBoxes) do
      if FCheckBoxes[i] <> nil then
      begin
        if FCheckBoxes[i].Checked then oldChecked.Add(FCheckBoxes[i].Caption);
        if not FCheckBoxes[i].Enabled then oldDisabled.Add(FCheckBoxes[i].Caption);
      end;

    ClearCheckBoxes;

    n := FItems.Count;
    SetLength(FCheckBoxes, n);
    for i := 0 to n - 1 do
    begin
      cb := TTyCheckBox.Create(Self);      // owned by Self; freed on our Destroy/Clear
      // Internal helper control: never a designable child in the IDE.
      cb.ControlStyle := cb.ControlStyle + [csNoDesignVisible];
      cb.Parent := Self;
      cb.Caption := FItems[i];
      cb.Controller := Controller;         // follow the group's controller (nil-safe)
      idx := oldChecked.IndexOf(FItems[i]);
      if idx >= 0 then
      begin
        cb.Checked := True;
        oldChecked.Delete(idx);            // consume so duplicate captions match one-for-one
      end;
      idx := oldDisabled.IndexOf(FItems[i]);
      if idx >= 0 then
      begin
        cb.Enabled := False;
        oldDisabled.Delete(idx);
      end;
      cb.OnChange := @ChildChanged;        // wired AFTER the initial Checked set above,
                                           // so restoring state does not fire OnItemChange
      { Focus lives on the child, never on the group, so the group's own key events can
        only ever fire through these. See ItemKeyDown. }
      cb.OnKeyDown := @ItemKeyDown;
      cb.OnKeyUp := @ItemKeyUp;
      cb.OnKeyPress := @ItemKeyPress;
      cb.OnUTF8KeyPress := @ItemUTF8KeyPress;
      FCheckBoxes[i] := cb;
    end;

    LayoutCheckBoxes;
  finally
    oldDisabled.Free;
    oldChecked.Free;
    FRebuilding := False;
  end;
  Invalidate;
end;

procedure TTyCheckGroup.LayoutCheckBoxes;
var
  cr: TRect;
  n, rowH, i: Integer;
  cell: TRect;
begin
  n := Length(FCheckBoxes);
  if n = 0 then Exit;
  cr := ClientRect;
  AdjustClientRect(cr);             // TTyGroupBox insets Top below the caption band
  rowH := 24;                       // logical row pitch; each checkbox is 22 high
  if Font.PixelsPerInch <> 96 then
    rowH := MulDiv(rowH, Font.PixelsPerInch, 96);
  for i := 0 to n - 1 do
  begin
    if FCheckBoxes[i] = nil then Continue;
    { MIRRORING: the columns reverse here; each hosted TTyCheckBox flips its OWN indicator,
      because BiDiMode propagates parent-to-child through LCL (CMParentBiDiModeChanged,
      include/control.inc:5993) and every child has ParentBiDiMode on by default. Nothing to
      keep a hit test in step with: the children are real controls that answer their own
      clicks, so there is no index-to-position arithmetic on the input side at all. }
    cell := TyCheckGroupCellRect(cr, n, FColumns, i, rowH, FColumnLayout, IsRightToLeft);
    FCheckBoxes[i].SetBounds(cell.Left, cell.Top,
      cell.Right - cell.Left, cell.Bottom - cell.Top);
  end;
end;

procedure TTyCheckGroup.ChildChanged(Sender: TObject);
var
  i: Integer;
begin
  if FRebuilding then Exit;         // state restore during a rebuild is not a user toggle
  if not (Assigned(FOnItemChange) or Assigned(FOnItemClick)) then Exit;
  for i := 0 to High(FCheckBoxes) do
    if FCheckBoxes[i] = Sender then
    begin
      // Two names, one notification (see OnItemClick). Ours first, so the ordering is
      // stated rather than left to whichever field happens to be declared first.
      if Assigned(FOnItemChange) then FOnItemChange(Self, i);
      if Assigned(FOnItemClick) then FOnItemClick(Self, i);
      Exit;
    end;
end;

{ The four child-key relays. Sender is the child; the event is re-raised on the GROUP so
  `CG.OnKeyDown := @H` sees keys typed while focus is on any item -- which is the only way
  it can ever fire, the group itself never being focusable. Key stays `var` all the way
  through, so a handler that swallows a key really swallows it. }
procedure TTyCheckGroup.ItemKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;

procedure TTyCheckGroup.ItemKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  KeyUp(Key, Shift);
end;

procedure TTyCheckGroup.ItemKeyPress(Sender: TObject; var Key: char);
begin
  KeyPress(Key);
end;

procedure TTyCheckGroup.ItemUTF8KeyPress(Sender: TObject; var UTF8Key: TUTF8Char);
begin
  UTF8KeyPress(UTF8Key);
end;

procedure TTyCheckGroup.RaiseIndexOutOfBounds(AIndex: Integer);
begin
  raise EListError.CreateFmt('%s Index %d out of bounds 0 .. %d',
    [ClassName, AIndex, Length(FCheckBoxes) - 1]);
end;

function TTyCheckGroup.GetChecked(AIndex: Integer): Boolean;
begin
  if (AIndex < 0) or (AIndex > High(FCheckBoxes)) then
    RaiseIndexOutOfBounds(AIndex);
  { A nil slot is not a caller error -- it can only exist mid-rebuild -- so it keeps the
    old quiet answer rather than blaming the index, which is in range. }
  if FCheckBoxes[AIndex] = nil then Exit(False);
  Result := FCheckBoxes[AIndex].Checked;
end;

procedure TTyCheckGroup.SetChecked(AIndex: Integer; AValue: Boolean);
var
  cb: TTyCheckBox;
  saved: TNotifyEvent;
begin
  if (AIndex < 0) or (AIndex > High(FCheckBoxes)) then
    RaiseIndexOutOfBounds(AIndex);
  if FCheckBoxes[AIndex] = nil then Exit;   // mid-rebuild slot; see GetChecked
  cb := FCheckBoxes[AIndex];
  { OnItemChange reports what the USER did. Firing it for a programmatic write makes
    the two indistinguishable, so a handler that writes back (the common "uncheck the
    others" shape) re-enters itself. LCL suppresses the same way -- nil the child's
    event, assign, restore (include/customcheckgroup.inc). }
  saved := cb.OnChange;
  cb.OnChange := nil;
  try
    cb.Checked := AValue;
  finally
    cb.OnChange := saved;
  end;
end;

function TTyCheckGroup.CheckBoxAt(AIndex: Integer): TTyCheckBox;
begin
  if (AIndex < 0) or (AIndex > High(FCheckBoxes)) then Exit(nil);
  Result := FCheckBoxes[AIndex];
end;

function TTyCheckGroup.GetButton(AIndex: Integer): TTyCheckBox;
begin
  if (AIndex < 0) or (AIndex > High(FCheckBoxes)) then
    RaiseIndexOutOfBounds(AIndex);
  Result := FCheckBoxes[AIndex];
end;

function TTyCheckGroup.GetCheckEnabled(AIndex: Integer): Boolean;
begin
  if (AIndex < 0) or (AIndex > High(FCheckBoxes)) then
    RaiseIndexOutOfBounds(AIndex);
  // A nil slot can only exist mid-rebuild; see GetChecked. "Not usable" is the honest
  // answer for a child that does not exist yet, and it is what the caller would observe.
  if FCheckBoxes[AIndex] = nil then Exit(False);
  Result := FCheckBoxes[AIndex].Enabled;
end;

procedure TTyCheckGroup.SetCheckEnabled(AIndex: Integer; AValue: Boolean);
begin
  if (AIndex < 0) or (AIndex > High(FCheckBoxes)) then
    RaiseIndexOutOfBounds(AIndex);
  if FCheckBoxes[AIndex] = nil then Exit;   // mid-rebuild slot; see SetChecked
  FCheckBoxes[AIndex].Enabled := AValue;
end;

procedure TTyCheckGroup.SetParent(AParent: TWinControl);
begin
  inherited SetParent(AParent);
  LayoutCheckBoxes;                 // client rect may resolve differently once parented
end;

procedure TTyCheckGroup.Resize;
begin
  inherited Resize;
  LayoutCheckBoxes;                 // reflow on resize (columns share the new width)
end;

procedure TTyCheckGroup.CMBiDiModeChanged(var Message: TLMessage);
begin
  inherited;
  LayoutCheckBoxes;                 // the columns have to actually change sides
end;

procedure TTyCheckGroup.SetController(AValue: TTyStyleController);
var
  i: Integer;
begin
  inherited SetController(AValue);
  // Keep the internal children on the same controller so they theme consistently.
  for i := 0 to High(FCheckBoxes) do
    if FCheckBoxes[i] <> nil then
      FCheckBoxes[i].Controller := AValue;
end;

end.
