unit tyControls.CheckGroup;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, LCLType,
  tyControls.Controller, tyControls.GroupBox, tyControls.CheckBox;
type
  { Fired when a hosted checkbox toggles; AIndex is that item's index. }
  TCheckGroupItemEvent = procedure(Sender: TObject; AIndex: Integer) of object;

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
    FCheckBoxes: array of TTyCheckBox;
    FOnItemChange: TCheckGroupItemEvent;
    FRebuilding: Boolean;
    procedure SetItems(AValue: TStrings);
    procedure ItemsChanged(Sender: TObject);
    procedure SetColumns(AValue: Integer);
    function GetChecked(AIndex: Integer): Boolean;
    procedure SetChecked(AIndex: Integer; AValue: Boolean);
    procedure ClearCheckBoxes;
    procedure RebuildCheckBoxes;
    procedure LayoutCheckBoxes;
    procedure ChildChanged(Sender: TObject);   // wired to each child's OnChange
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
  published
    property Items: TStrings read FItems write SetItems;
    property Columns: Integer read FColumns write SetColumns default 1;
    property OnItemChange: TCheckGroupItemEvent read FOnItemChange write FOnItemChange;
    { Caption / Alignment inherited from TTyGroupBox; the frame + caption band. }
  end;

{ The device-px cell rect of item AIndex within a client area AClientRect, given
  ACount items laid out in AColumns columns (top-to-bottom, then next column) with
  each row ARowH device px tall. Columns divide the client width evenly; the last
  column absorbs the width remainder so cells tile flush. Rows stack from the top;
  a partially-filled last column simply has fewer rows. An out-of-range AIndex,
  ACount <= 0, or AColumns <= 0 yields an empty rect. PURE — no control state;
  unit-tested directly. }
function TyCheckGroupCellRect(const AClientRect: TRect;
  ACount, AColumns, AIndex, ARowH: Integer): TRect;

implementation

function TyCheckGroupCellRect(const AClientRect: TRect;
  ACount, AColumns, AIndex, ARowH: Integer): TRect;
var
  cols, rowsPerCol, col, row, colW, l, r, cw: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if (ACount <= 0) or (AColumns <= 0) or (AIndex < 0) or (AIndex >= ACount) then Exit;
  if ARowH <= 0 then Exit;

  cols := AColumns;
  if cols > ACount then cols := ACount;   // never more columns than items
  // Ceil-divide items across columns so column 0 fills first (top-to-bottom).
  rowsPerCol := (ACount + cols - 1) div cols;
  if rowsPerCol < 1 then rowsPerCol := 1;

  col := AIndex div rowsPerCol;
  row := AIndex mod rowsPerCol;
  if col > cols - 1 then col := cols - 1;  // clamp (defensive; ceil keeps it in range)

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
end;

{ TTyCheckGroup }

constructor TTyCheckGroup.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TStringList.Create;
  TStringList(FItems).OnChange := @ItemsChanged;
  FColumns := 1;
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
  oldChecked: TStringList;
  cb: TTyCheckBox;
begin
  if FRebuilding then Exit;   // guard against re-entrancy (child churn shouldn't recurse)
  FRebuilding := True;
  oldChecked := TStringList.Create;
  try
    // Snapshot the CHECKED items BY IDENTITY (caption), not by raw slot index — so a mid-list
    // edit (delete/insert), not just an append, preserves each user check on its OWN item
    // instead of migrating it onto whatever slides into that index. Duplicate captions are
    // consumed one-for-one (Delete below) so N checked "A"s restore onto the first N "A"s.
    oldChecked.CaseSensitive := True;
    for i := 0 to High(FCheckBoxes) do
      if (FCheckBoxes[i] <> nil) and FCheckBoxes[i].Checked then
        oldChecked.Add(FCheckBoxes[i].Caption);

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
      cb.OnChange := @ChildChanged;        // wired AFTER the initial Checked set above,
                                           // so restoring state does not fire OnItemChange
      FCheckBoxes[i] := cb;
    end;

    LayoutCheckBoxes;
  finally
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
    cell := TyCheckGroupCellRect(cr, n, FColumns, i, rowH);
    FCheckBoxes[i].SetBounds(cell.Left, cell.Top,
      cell.Right - cell.Left, cell.Bottom - cell.Top);
  end;
end;

procedure TTyCheckGroup.ChildChanged(Sender: TObject);
var
  i: Integer;
begin
  if FRebuilding then Exit;         // state restore during a rebuild is not a user toggle
  if not Assigned(FOnItemChange) then Exit;
  for i := 0 to High(FCheckBoxes) do
    if FCheckBoxes[i] = Sender then
    begin
      FOnItemChange(Self, i);
      Exit;
    end;
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
