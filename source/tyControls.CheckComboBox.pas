unit tyControls.CheckComboBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.ListBox, tyControls.ComboBox, tyControls.CheckListBox;

type
  { Per-item state hung off the combo's own Items.Objects[i]. Same shape LCL uses
    (comboex.pas:262 TCheckComboItemState): the check state AND a Data field that hands
    the application back its per-row slot. Riding inside Objects[] is what glues the state
    to its string through Sorted / Insert / Delete -- a parallel array would desync on the
    first sort -- while Data is what stops the two owners from overwriting each other.
    Instances are owned by the combo's state pool, never by Items. }
  TTyCheckComboItemState = class
  public
    Checked: Boolean;
    Data: TObject;            // the APPLICATION's object for this row
    Live: Boolean;            // sweep mark; see TTyCheckComboBox.SweepStates
  end;

  { A combo box whose drop-down is a CHECK list: the user ticks any number of items and the
    popup STAYS OPEN (multi-select) instead of closing on a pick; the field shows a summary
    (the checked item texts joined by Separator, or EmptyText when none). Each item's state
    lives in a TTyCheckComboItemState in THIS combo's Items.Objects[i] -- the persistent
    truth -- so it survives open/close and Sorted (no parallel array). The application's own
    per-row object goes in Objects[i] (this control's property, not Items.Objects[]), which
    is LCL's split too. Locked to csDropDownList (an editable prefix-filtered field is
    meaningless for a multi-check). Build with Items.Add + Checked[]. }
  TTyCheckComboBox = class(TTyComboBox)
  private
    FSeparator: string;
    FEmptyText: string;
    function EnsureState(AIndex: Integer): TTyCheckComboItemState;
    procedure SweepStates;
    function GetChecked(AIndex: Integer): Boolean;
    procedure SetChecked(AIndex: Integer; AValue: Boolean);
    function GetItemObject(AIndex: Integer): TObject;
    procedure SetItemObject(AIndex: Integer; AValue: TObject);
    procedure SetEmptyText(const AValue: string);
    procedure PopupCheckClick(Sender: TObject);
  protected
    { Owns every state object ever created, so nothing leaks when the app deletes or clears
      Items behind our back -- LCL's model leaks exactly there (it only frees what is still
      reachable from Items, in Destroy/DeleteItem/Clear). Protected so a test can watch the
      pool stay bounded. }
    FStates: TList;
    { The popup checklist keeps its own check flags as raw 0/1 in ITS Items.Objects[], and
      the base class fills it with a plain Items.Assign -- which would hand it our state
      POINTERS, every one of which reads as non-zero, i.e. "checked". So the two
      representations get translated at the boundary, in both directions. }
    procedure PushChecksToList(AList: TTyCheckListBox);
    procedure PullChecksFromList(AList: TTyCheckListBox);
    function CreatePopupList: TTyListBox; override;
    procedure PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet); override;
    { A row pick must NOT commit/close — checking is a toggle, and the popup stays open. The
      checkbox toggle + field sync happen in the checklist / PopupCheckClick, so this is a no-op. }
    procedure DoPopupPick(AIndex: Integer); override;
    procedure SetStyle(AValue: TTyComboBoxStyle); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure DropDown; override;
    // Number of checked items.
    function CheckedCount: Integer;
    // The field summary (checked item texts joined by Separator, or EmptyText when none).
    function CheckedText: string;
    property Checked[AIndex: Integer]: Boolean read GetChecked write SetChecked;
    { The application's per-item slot -- LCL's TCustomCheckCombo.Objects[] (comboex.pas:327),
      which reads and writes TCheckComboItemState.Data. Items.Objects[] belongs to the
      control: writing app data straight into it is what used to destroy the check states,
      and what the check states used to destroy. An object attached the idiomatic way
      (Items.AddObject) is adopted into Data on first use, so either order works. }
    property Objects[AIndex: Integer]: TObject read GetItemObject write SetItemObject;
  published
    // Joins the checked item texts in the field summary (default ', ').
    property Separator: string read FSeparator write FSeparator;
    // Shown in the field when nothing is checked (default '').
    property EmptyText: string read FEmptyText write SetEmptyText;
  end;

implementation

{ Items.Objects[] may hold nil, one of our state objects, or the application's own object.
  The class test must never run on the popup checklist's raw 0/1 flags: TObject(1) has no
  VMT, so `is` would dereference address 1 and take the process down. Nothing inside the
  first page is a pointer on any platform we target, so that is the sentinel guard. }
function TyCheckComboStateOf(AObj: TObject): TTyCheckComboItemState;
begin
  Result := nil;
  if PtrUInt(AObj) < 4096 then Exit;
  if AObj is TTyCheckComboItemState then Result := TTyCheckComboItemState(AObj);
end;

constructor TTyCheckComboBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSeparator := ', ';
  FEmptyText := '';
  FStates := TList.Create;
end;

destructor TTyCheckComboBox.Destroy;
var
  i: Integer;
begin
  for i := 0 to FStates.Count - 1 do
    TTyCheckComboItemState(FStates[i]).Free;
  FStates.Free;
  inherited Destroy;
end;

function TTyCheckComboBox.EnsureState(AIndex: Integer): TTyCheckComboItemState;
var
  raw: TObject;
begin
  raw := Items.Objects[AIndex];
  Result := TyCheckComboStateOf(raw);
  if Result <> nil then Exit;
  { Anything already in the slot is the application's -- Items.AddObject(s, Data) is the
    idiomatic way to attach it -- so adopt it as Data instead of dropping it on the floor. }
  Result := TTyCheckComboItemState.Create;
  Result.Checked := False;
  Result.Data := raw;
  { Only ever grows on a WRITE (a check, or an Objects[] set): reading must not mutate
    Items, or every repaint would fire the base class's ItemsChanged. }
  if FStates.Count > 2 * Items.Count + 8 then SweepStates;
  FStates.Add(Result);
  Items.Objects[AIndex] := Result;
end;

procedure TTyCheckComboBox.SweepStates;
{ Mark and sweep: Items.Delete / Items.Clear / Items.Assign drop our pointers without
  telling us, so states that are no longer reachable from any row are collected here.
  Called from EnsureState only once the pool has outgrown the list, so a list that is
  merely being filled never pays for it. }
var
  i: Integer;
  st: TTyCheckComboItemState;
begin
  for i := 0 to FStates.Count - 1 do
    TTyCheckComboItemState(FStates[i]).Live := False;
  for i := 0 to Items.Count - 1 do
  begin
    st := TyCheckComboStateOf(Items.Objects[i]);
    if st <> nil then st.Live := True;
  end;
  for i := FStates.Count - 1 downto 0 do
  begin
    st := TTyCheckComboItemState(FStates[i]);
    if not st.Live then
    begin
      FStates.Delete(i);
      st.Free;
    end;
  end;
end;

function TTyCheckComboBox.GetChecked(AIndex: Integer): Boolean;
var
  st: TTyCheckComboItemState;
begin
  Result := False;
  if (AIndex < 0) or (AIndex >= Items.Count) then Exit;
  { A read never materialises a state: an item that has none is simply unchecked, and an
    item carrying only the app's object is unchecked too (that used to read as CHECKED). }
  st := TyCheckComboStateOf(Items.Objects[AIndex]);
  Result := (st <> nil) and st.Checked;
end;

procedure TTyCheckComboBox.SetChecked(AIndex: Integer; AValue: Boolean);
var
  lst: TTyListBox;   // PopupList (nil when the dropdown is closed — no side effect)
begin
  if (AIndex < 0) or (AIndex >= Items.Count) then Exit;
  if GetChecked(AIndex) = AValue then Exit;
  EnsureState(AIndex).Checked := AValue;
  { Keep a live popup in sync (programmatic set while the dropdown is open). }
  lst := PopupList;
  if (lst is TTyCheckListBox) and (AIndex < lst.Items.Count) then
    TTyCheckListBox(lst).Checked[AIndex] := AValue;
  Invalidate;
end;

function TTyCheckComboBox.GetItemObject(AIndex: Integer): TObject;
var
  st: TTyCheckComboItemState;
begin
  Result := nil;
  if (AIndex < 0) or (AIndex >= Items.Count) then Exit;
  st := TyCheckComboStateOf(Items.Objects[AIndex]);
  { No state yet == nothing has been checked here, so the raw slot still holds exactly what
    Items.AddObject put there. Reading it back costs no allocation. }
  if st <> nil then Result := st.Data else Result := Items.Objects[AIndex];
end;

procedure TTyCheckComboBox.SetItemObject(AIndex: Integer; AValue: TObject);
begin
  if (AIndex < 0) or (AIndex >= Items.Count) then Exit;
  EnsureState(AIndex).Data := AValue;
end;

procedure TTyCheckComboBox.SetEmptyText(const AValue: string);
begin
  if FEmptyText = AValue then Exit;
  FEmptyText := AValue;
  Invalidate;
end;

function TTyCheckComboBox.CheckedCount: Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to Items.Count - 1 do
    if GetChecked(i) then Inc(Result);
end;

function TTyCheckComboBox.CheckedText: string;
var i: Integer;
begin
  Result := '';
  for i := 0 to Items.Count - 1 do
    if GetChecked(i) then
    begin
      if Result <> '' then Result := Result + FSeparator;
      Result := Result + Items[i];
    end;
  if Result = '' then Result := FEmptyText;
end;

procedure TTyCheckComboBox.PushChecksToList(AList: TTyCheckListBox);
var i: Integer;
begin
  if AList = nil then Exit;
  for i := 0 to AList.Items.Count - 1 do
  begin
    { Clear first, unconditionally: a checklist slot still holding one of our state
      pointers already reads as checked there, so `Checked[i] := True` would short-circuit
      and leave the pointer sitting in the popup's list. }
    AList.Checked[i] := False;
    if (i < Items.Count) and GetChecked(i) then AList.Checked[i] := True;
  end;
end;

procedure TTyCheckComboBox.PullChecksFromList(AList: TTyCheckListBox);
var i: Integer; v: Boolean;
begin
  if AList = nil then Exit;
  for i := 0 to Items.Count - 1 do
    if i < AList.Items.Count then
    begin
      v := AList.Checked[i];
      { Only a real flip touches the state, so an untouched unchecked row never allocates. }
      if GetChecked(i) <> v then EnsureState(i).Checked := v;
    end;
end;

procedure TTyCheckComboBox.PopupCheckClick(Sender: TObject);
begin
  { A checkbox was toggled in the popup: pull the states back out of the popup COPY (same
    order — csDropDownList never filters), repaint the field summary, and notify. The popup
    stays open. }
  if not (PopupList is TTyCheckListBox) then Exit;
  PullChecksFromList(TTyCheckListBox(PopupList));
  Invalidate;
  if Assigned(OnChange) then OnChange(Self);
end;

procedure TTyCheckComboBox.DropDown;
begin
  { The base fills the popup list with Items.Assign, which copies our state POINTERS into a
    control that reads that slot as a raw 0/1 flag — every row would come up ticked. }
  inherited DropDown;
  if PopupList is TTyCheckListBox then
    PushChecksToList(TTyCheckListBox(PopupList));
end;

function TTyCheckComboBox.CreatePopupList: TTyListBox;
var lst: TTyCheckListBox;
begin
  lst := TTyCheckListBox.Create(Self);
  lst.OnClickCheck := @PopupCheckClick;
  Result := lst;
end;

procedure TTyCheckComboBox.PaintFieldContent(P: TTyPainter; const ATextRect: TRect;
  const AStyle: TTyStyleSet);
begin
  P.DrawText(ATextRect, CheckedText, AStyle.FontName, ResolveFontSize(AStyle),
    AStyle.FontWeight, AStyle.TextColor, taLeftJustify, tlCenter, True);
end;

procedure TTyCheckComboBox.DoPopupPick(AIndex: Integer);
begin
  // Intentionally empty: no single-item commit, no close (see class header).
end;

procedure TTyCheckComboBox.SetStyle(AValue: TTyComboBoxStyle);
begin
  inherited SetStyle(csDropDownList);   // multi-check is pick-only; ignore editable mode
end;

end.
