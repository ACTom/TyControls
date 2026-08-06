unit tyControls.CheckComboBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, StdCtrls,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.Controller, tyControls.ListBox, tyControls.ComboBox, tyControls.CheckListBox;

type
  { Fired for the row that changed, on user toggles AND on programmatic writes. LCL spells
    it TCheckItemChange (comboex.pas:52); TTyCheckGroup already carries the same shape. }
  TTyCheckItemChangeEvent = procedure(Sender: TObject; AIndex: Integer) of object;

  { Per-item state hung off the combo's own Items.Objects[i]. Same shape LCL uses
    (comboex.pas:263 TCheckComboItemState): the check STATE (tri-state, not a boolean),
    a per-row Enabled flag, AND a Data field that hands the application back its per-row
    slot. Riding inside Objects[] is what glues the state to its string through Sorted /
    Insert / Delete -- a parallel array would desync on the first sort -- while Data is
    what stops the two owners from overwriting each other. Instances are owned by the
    combo's state pool, never by Items. }
  TTyCheckComboItemState = class
  public
    State: TCheckBoxState;    // cbUnchecked / cbChecked / cbGrayed
    Enabled: Boolean;         // False = drawn dimmed, and the user's click is refused
    Data: TObject;            // the APPLICATION's object for this row
    Live: Boolean;            // sweep mark; see TTyCheckComboBox.SweepStates
  end;

  { The check combo's own drop-down list. TTyCheckListBox only knows two states and no
    per-row enabled flag, so this paints the row itself from the OWNER's state objects --
    the same "ask the owner" shape TTyComboBoxExPopupList uses. }
  TTyCheckComboPopupList = class(TTyCheckListBox)
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
    { The owner-draw dispatch TTyComboPopupList carries for every OTHER list in this family.
      Copied rather than inherited because this one descends from TTyCheckListBox, and a
      class cannot have two ancestors -- the reason the protocol is three free functions
      instead of a shim class. }
    procedure Paint; override;
  public
    { The twin of TTyComboPopupList.RenderWithOwnerDraw: canvas-taking, so a headless test
      can drive the whole post-composite dispatch into a bitmap. Paint needs a window. }
    procedure RenderWithOwnerDraw(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  { A combo box whose drop-down is a CHECK list: the user ticks any number of items and the
    popup STAYS OPEN (multi-select) instead of closing on a pick; the field shows a summary
    (the checked item texts joined by Separator, or EmptyText when none). Each item's state
    lives in a TTyCheckComboItemState in THIS combo's Items.Objects[i] -- the persistent
    truth -- so it survives open/close and Sorted (no parallel array). That state is
    TRI-state (State[] / AllowGrayed) plus a per-row ItemEnabled flag; Checked[] is the
    two-state view of it. The application's own per-row object goes in Objects[i] (this
    control's property, not Items.Objects[]), which is LCL's split too. Locked to
    csDropDownList (an editable prefix-filtered field is meaningless for a multi-check).
    Build with AddItem(text, state) -- or Items.Add + Checked[] as before. }
  TTyCheckComboBox = class(TTyComboBox)
  private
    FSeparator: string;
    FEmptyText: string;
    FAllowGrayed: Boolean;
    FOnItemChange: TTyCheckItemChangeEvent;
    function EnsureState(AIndex: Integer): TTyCheckComboItemState;
    procedure SweepStates;
    function GetChecked(AIndex: Integer): Boolean;
    procedure SetChecked(AIndex: Integer; AValue: Boolean);
    function GetState(AIndex: Integer): TCheckBoxState;
    procedure SetState(AIndex: Integer; AValue: TCheckBoxState);
    function GetItemEnabled(AIndex: Integer): Boolean;
    procedure SetItemEnabled(AIndex: Integer; AValue: Boolean);
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
    { Read-only view of a row's state for the popup list, which paints tri-state and
      disabled rows the base checklist cannot express. Out-of-range answers the
      harmless default rather than raising, because paint code runs mid-resize. }
    function RowState(AIndex: Integer): TCheckBoxState;
    function RowEnabled(AIndex: Integer): Boolean;
    procedure DoItemChange(AIndex: Integer); virtual;
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
    { Append a row with its state (and enabled flag) in ONE call, instead of Items.Add
      followed by Checked[Items.Count-1] -- an index the caller has to get right, and gets
      wrong onto the previous row. Overloads the inherited AddItem(text, TObject) rather
      than hiding it. }
    procedure AddItem(const AItem: string; AState: TCheckBoxState;
      AEnabled: Boolean = True); overload;
    { Replace every row from AItems, dropping all previous states. }
    procedure AssignItems(AItems: TStrings);
    { Remove one row (and release its state). }
    procedure DeleteItem(AIndex: Integer);
    { Bulk-set every row. AAllowGrayed=False skips rows currently grayed, AAllowDisabled=
      False skips disabled rows -- so "check everything the user may actually change" is
      one call and not a loop the caller has to get the exclusions right in. }
    procedure CheckAll(AState: TCheckBoxState; AAllowGrayed: Boolean = True;
      AAllowDisabled: Boolean = True);
    { Advance one row through the cycle a click would take it: unchecked -> checked with
      AllowGrayed off, unchecked -> grayed -> checked with it on (LCL's order). }
    procedure Toggle(AIndex: Integer);
    property Checked[AIndex: Integer]: Boolean read GetChecked write SetChecked;
    { The full tri-state. Checked[] is the two-state view of the same slot; cbGrayed reads
      as NOT checked, which is what "partially selected" has to mean for a summary. }
    property State[AIndex: Integer]: TCheckBoxState read GetState write SetState;
    { A disabled row still shows and is still settable from code, but the user's click and
      Space are refused -- the "unavailable on your licence" row, without deleting it. }
    property ItemEnabled[AIndex: Integer]: Boolean read GetItemEnabled write SetItemEnabled;
    { Test seam: run the popup -> combo state transfer against a list built by hand, so
      the disabled-row veto can be exercised without a real popup window. }
    procedure PullChecksForTest(AList: TTyCheckListBox);
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
    { Lets the user's toggle pass through cbGrayed. Off (LCL's default) the click cycle is
      the plain two-state one; Checked[] and CheckAll are unaffected either way. }
    property AllowGrayed: Boolean read FAllowGrayed write FAllowGrayed default False;
    { Says WHICH row changed. The inherited OnChange fires too, but index-less, so a
      handler had to diff the whole list -- and a programmatic Checked[i] := True used to
      fire nothing at all, silently staling any view bound to the combo. }
    property OnItemChange: TTyCheckItemChangeEvent read FOnItemChange write FOnItemChange;
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

{ TTyCheckComboPopupList }

procedure TTyCheckComboPopupList.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
var
  cs: TTyStyleSet;
  combo: TTyCheckComboBox;
  st: TCheckBoxState;
  rowEnabled: Boolean;
  pad, sz, boxTop: Integer;
  boxR, textR: TRect;
  states: TTyStateSet;
  ink: TTyColor;
begin
  { Owner-draw first: this override replaces the whole row, so leaving it to an inherited
    call would be too late. True only when the combo has an owner-draw Style AND a handler;
    the themed row background is already down and the handler runs after EndPaint, from the
    Paint override below. Note what this costs the caller: the CHECK BOX goes with the rest
    of the default content, because the host asked to paint the row. Toggling still works --
    the hit test is not part of the paint. }
  if TyComboCollectRowOwnerDraw(Self, ARowRect, AIndex) then Exit;
  { The Owner is the combo (Create(Self) in CreatePopupList); it holds the only tri-state
    truth. Without an owner we are a plain two-state checklist -- fall back rather than
    guess. }
  if not (Owner is TTyCheckComboBox) then
  begin
    inherited PaintItemContent(P, ARowRect, AIndex, AStyle);
    Exit;
  end;
  combo := TTyCheckComboBox(Owner);
  st := combo.RowState(AIndex);
  rowEnabled := combo.RowEnabled(AIndex);

  pad := P.Scale(4);
  sz := (ARowRect.Bottom - ARowRect.Top) - 2 * pad;
  if sz < 6 then sz := 6;
  boxTop := ARowRect.Top + ((ARowRect.Bottom - ARowRect.Top) - sz) div 2;
  boxR := Rect(ARowRect.Left + pad, boxTop, ARowRect.Left + pad + sz, boxTop + sz);

  { Box chrome from the shared 'TyCheckBox' token, exactly as TTyCheckListBox resolves it
    -- ticked AND grayed are both "engaged", so both take :active; a disabled row asks the
    theme for :disabled instead of dimming a hardcoded colour here. }
  states := [];
  if st in [cbChecked, cbGrayed] then Include(states, tysActive);
  if not rowEnabled then Include(states, tysDisabled);
  if states = [] then states := [tysNormal];
  cs := ActiveController.Model.ResolveStyle('TyCheckBox', '', states);
  if tpBackground in cs.Present then
    P.FillBackground(boxR, cs.Background, cs.BorderRadius);
  if (tpBorderColor in cs.Present) and (cs.BorderWidth > 0) then
    P.StrokeBorder(boxR, cs.BorderRadius, cs.BorderWidth, cs.BorderColor);
  { v3/C5 glyph override, same call shape TTyCheckBox uses for its own three states. }
  case st of
    cbChecked: TyDrawGlyph(P, ActiveController, boxR, '--glyph-check', tgCheck, cs.TextColor, 2);
    cbGrayed:  TyDrawGlyph(P, ActiveController, boxR, '--glyph-check-indeterminate',
                 tgCheckIndeterminate, cs.TextColor, 2);
  end;

  { Row text: a disabled row takes the list's own :disabled ink so it reads as
    unavailable without the caller having to grey the string itself. }
  ink := AStyle.TextColor;
  if not rowEnabled then
    ink := ActiveController.Model.ResolveStyle(GetStyleTypeKey, '', [tysDisabled]).TextColor;
  textR := Rect(boxR.Right + pad, ARowRect.Top,
    ARowRect.Right - P.Scale(AStyle.Padding.Right), ARowRect.Bottom);
  P.DrawText(textR, Items[AIndex], AStyle.FontName, ResolveFontSize(AStyle),
    AStyle.FontWeight, ink, taLeftJustify, tlCenter, True);
end;

procedure TTyCheckComboPopupList.RenderWithOwnerDraw(ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer);
begin
  TyComboBeginRowOwnerDraw(Self);
  RenderTo(ACanvas, ARect, APPI);   // collects during the row loop; ends with EndPaint
  TyComboDispatchRowOwnerDraw(Self, ACanvas, ARect);
end;

procedure TTyCheckComboPopupList.Paint;
begin
  RenderWithOwnerDraw(Canvas, ClientRect, Font.PixelsPerInch);
end;

{ TTyCheckComboBox }

constructor TTyCheckComboBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSeparator := ', ';
  FEmptyText := '';
  FAllowGrayed := False;
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
  Result.State := cbUnchecked;
  Result.Enabled := True;
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

function TTyCheckComboBox.GetState(AIndex: Integer): TCheckBoxState;
var
  st: TTyCheckComboItemState;
begin
  Result := cbUnchecked;
  if (AIndex < 0) or (AIndex >= Items.Count) then Exit;
  { A read never materialises a state: an item that has none is simply unchecked, and an
    item carrying only the app's object is unchecked too (that used to read as CHECKED). }
  st := TyCheckComboStateOf(Items.Objects[AIndex]);
  if st <> nil then Result := st.State;
end;

procedure TTyCheckComboBox.SetState(AIndex: Integer; AValue: TCheckBoxState);
var
  lst: TTyListBox;   // PopupList (nil when the dropdown is closed — no side effect)
begin
  if (AIndex < 0) or (AIndex >= Items.Count) then Exit;
  if GetState(AIndex) = AValue then Exit;
  EnsureState(AIndex).State := AValue;
  { Keep a live popup in sync (programmatic set while the dropdown is open). The popup
    keeps raw 0/1 flags, so cbGrayed lands there as NOT ticked — its own painter reads the
    tri-state back off us, so the flag is only the fallback path's opinion. }
  lst := PopupList;
  if (lst is TTyCheckListBox) and (AIndex < lst.Items.Count) then
    TTyCheckListBox(lst).Checked[AIndex] := (AValue = cbChecked);
  Invalidate;
  DoItemChange(AIndex);
end;

function TTyCheckComboBox.GetChecked(AIndex: Integer): Boolean;
begin
  { Two-state view of the same slot. cbGrayed is deliberately NOT checked: a partially
    selected row must not join the field summary or CheckedCount. }
  Result := GetState(AIndex) = cbChecked;
end;

procedure TTyCheckComboBox.SetChecked(AIndex: Integer; AValue: Boolean);
begin
  if AValue then SetState(AIndex, cbChecked) else SetState(AIndex, cbUnchecked);
end;

function TTyCheckComboBox.GetItemEnabled(AIndex: Integer): Boolean;
var
  st: TTyCheckComboItemState;
begin
  Result := True;             // no state yet == never disabled
  if (AIndex < 0) or (AIndex >= Items.Count) then Exit;
  st := TyCheckComboStateOf(Items.Objects[AIndex]);
  if st <> nil then Result := st.Enabled;
end;

procedure TTyCheckComboBox.SetItemEnabled(AIndex: Integer; AValue: Boolean);
begin
  if (AIndex < 0) or (AIndex >= Items.Count) then Exit;
  if GetItemEnabled(AIndex) = AValue then Exit;
  EnsureState(AIndex).Enabled := AValue;
  Invalidate;
  { No OnItemChange: LCL fires that for STATE changes only, and an app watching for
    "the user ticked something" must not be woken by a row merely being greyed. }
end;

function TTyCheckComboBox.RowState(AIndex: Integer): TCheckBoxState;
begin
  Result := GetState(AIndex);
end;

function TTyCheckComboBox.RowEnabled(AIndex: Integer): Boolean;
begin
  Result := GetItemEnabled(AIndex);
end;

procedure TTyCheckComboBox.DoItemChange(AIndex: Integer);
begin
  if Assigned(FOnItemChange) then FOnItemChange(Self, AIndex);
end;

procedure TTyCheckComboBox.AddItem(const AItem: string; AState: TCheckBoxState;
  AEnabled: Boolean);
var
  st: TTyCheckComboItemState;
begin
  { Build the state up front and hand it to Items.AddObject, so the row is never briefly
    in the list without one — EnsureState would otherwise adopt the nil slot on first
    touch, which is the same result by a longer road. }
  st := TTyCheckComboItemState.Create;
  st.State := AState;
  st.Enabled := AEnabled;
  st.Data := nil;
  FStates.Add(st);
  Items.AddObject(AItem, st);
  Invalidate;
end;

procedure TTyCheckComboBox.AssignItems(AItems: TStrings);
begin
  { Every old state becomes unreachable in one step; the pool's sweep is what actually
    frees them, so nothing leaks and nothing dangles. }
  Items.Assign(AItems);
  SweepStates;
  Invalidate;
end;

procedure TTyCheckComboBox.DeleteItem(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= Items.Count) then Exit;
  Items.Delete(AIndex);      // the state it referenced is collected by the pool sweep
  Invalidate;
end;

procedure TTyCheckComboBox.CheckAll(AState: TCheckBoxState; AAllowGrayed: Boolean;
  AAllowDisabled: Boolean);
var i: Integer;
begin
  for i := 0 to Items.Count - 1 do
    if (AAllowGrayed or (GetState(i) <> cbGrayed))
    and (AAllowDisabled or GetItemEnabled(i)) then
      SetState(i, AState);
end;

procedure TTyCheckComboBox.Toggle(AIndex: Integer);
const
  { LCL's cycle (comboex.inc:842). Note the grayed path is unchecked -> GRAYED -> checked,
    not checked -> grayed: this matches TCustomCheckCombo, not TTyCheckBox. }
  NextState: array [TCheckBoxState, Boolean] of TCheckBoxState =
    { AllowGrayed:      False         True     }
    ((cbChecked,   cbGrayed),      { cbUnchecked }
     (cbUnchecked, cbUnchecked),   { cbChecked   }
     (cbChecked,   cbChecked));    { cbGrayed    }
begin
  if (AIndex < 0) or (AIndex >= Items.Count) then Exit;
  SetState(AIndex, NextState[GetState(AIndex), FAllowGrayed]);
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
      if GetChecked(i) = v then Continue;   // untouched rows never allocate a state
      { A disabled row refuses the USER's flip and is pushed back to what it was, which is
        where the veto has to live: the popup checklist toggles on any row it is clicked
        on, and its toggle logic is private to that class. Code writing Checked[]/State[]
        goes through the setters and is deliberately NOT vetoed. }
      if not GetItemEnabled(i) then
      begin
        AList.Checked[i] := GetChecked(i);
        Continue;
      end;
      { Toggle, not SetChecked(i, v): the popup only ever knows a raw 0/1, so it cannot
        express "and now show grayed". Routing the user's click through the same cycle the
        keyboard would use is what makes AllowGrayed reachable by mouse at all. }
      Toggle(i);                            // fires OnItemChange with the row index
      AList.Checked[i] := GetChecked(i);    // the cycle may not have landed where the click aimed
    end;
end;

procedure TTyCheckComboBox.PullChecksForTest(AList: TTyCheckListBox);
begin
  PullChecksFromList(AList);
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
var lst: TTyCheckComboPopupList;
begin
  lst := TTyCheckComboPopupList.Create(Self);
  lst.OnClickCheck := @PopupCheckClick;
  Result := lst;
end;

procedure TTyCheckComboBox.PaintFieldContent(P: TTyPainter; const ATextRect: TRect;
  const AStyle: TTyStyleSet);
var summary: string;
begin
  summary := CheckedText;
  { Nothing ticked and no EmptyText: fall back to the inherited placeholder rather than
    painting an empty field. EmptyText stays the more specific answer when it is set. }
  if summary = '' then
  begin
    PaintTextHint(P, ATextRect, AStyle);
    Exit;
  end;
  P.DrawText(ATextRect, summary, AStyle.FontName, ResolveFontSize(AStyle),
    AStyle.FontWeight, AStyle.TextColor, taLeftJustify, tlCenter, True);
end;

procedure TTyCheckComboBox.DoPopupPick(AIndex: Integer);
begin
  // Intentionally empty: no single-item commit, no close (see class header).
end;

procedure TTyCheckComboBox.SetStyle(AValue: TTyComboBoxStyle);
begin
  { Multi-check is pick-only: an editable, prefix-FILTERED field cannot express a set of
    ticks. Take the EDIT BOX off the requested style rather than replacing the style whole
    -- LCL spells that TComboBoxStyleHelper.SetEditBox(False). The distinction is the whole
    point now that owner-draw exists: it is orthogonal to editability, so csOwnerDrawFixed
    must reach the base intact instead of being flattened to csDropDownList along with it. }
  inherited SetStyle(TyComboStylePickOnly(AValue));
end;

end.
