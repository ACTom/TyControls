unit test.parity.listview;
{ API-PARITY guards for TTyListView's item-change / selection events, written against the
  LCL declarations they mirror:

    C:/lazarus/lcl/comctrls.pp:1286   TItemChange = (ctText, ctImage, ctState)
    C:/lazarus/lcl/comctrls.pp:1292   TLVChangeEvent     (Sender, Item, Change)
    C:/lazarus/lcl/comctrls.pp:1294   TLVChangingEvent   (Sender, Item, Change, var AllowChange)
    C:/lazarus/lcl/comctrls.pp:1323   TLVSelectItemEvent (Sender, Item, Selected)
    C:/lazarus/lcl/include/customlistview.inc:193/208/701
                                      Change / CanChange / DoSelectItem

  Two defects these pin down, both of which shipped for months because NOTHING bound the
  events at all -- there was no red test to rename, there was no test:

    1. OnChange was a bare TNotifyEvent (Sender only): an app was told "something moved"
       and had to re-read the whole control to find out what. There was no OnChanging, so
       a change could not be vetoed either.
    2. OnSelectItem carried no Selected flag and fired only on select, so "row 3 was
       chosen" and "row 3 was abandoned" were indistinguishable -- and the second was
       never reported at all.

  Everything here is headless: controls are Create(nil), never parented, never painted.
  The keyboard seam goes through a TTyListViewParityAccess subclass, exactly as
  test.listview reaches protected members. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Types, LCLType, Controls, fpcunit, testregistry,
  tyControls.ListView;

type
  { Reaches the protected input seam (KeyDown is where the Space selection toggle lives). }
  TTyListViewParityAccess = class(TTyListView)
  public
    procedure XKeyDown(AKey: Word; AShift: TShiftState = []);
  end;

  { One recorded event. Kind keeps the three streams in ONE array, which is what lets a
    test assert order across them (LCL fires Change, then DoSelectItem —
    customlistview.inc:405-406). }
  TParityKind = (pkChanging, pkChange, pkSelect);

  TParityRec = record
    Kind:     TParityKind;
    Index:    Integer;
    Change:   TTyItemChange;
    Selected: Boolean;
  end;

  { Shared logging plumbing for both fixtures. }
  TListViewParityBase = class(TTestCase)
  protected
    FLV:   TTyListViewParityAccess;
    FLog:  array of TParityRec;
    FVeto: Boolean;
    procedure HChange(Sender: TObject; AIndex: Integer; AChange: TTyItemChange);
    procedure HChanging(Sender: TObject; AIndex: Integer; AChange: TTyItemChange;
      var AAllowChange: Boolean);
    procedure HSelect(Sender: TObject; AIndex: Integer; ASelected: Boolean);
    procedure HEdited(Sender: TObject; AIndex: Integer; var AText: string);
    procedure Log(AKind: TParityKind; AIndex: Integer; AChange: TTyItemChange;
      ASelected: Boolean);
    procedure ClearLog;
    { How many entries of one stream. }
    function  Count(AKind: TParityKind): Integer;
    { The AN'th entry of one stream (0-based). }
    function  Nth(AKind: TParityKind; AN: Integer): TParityRec;
    { Position in the WHOLE log of the AN'th entry of one stream, or -1. }
    function  PosOf(AKind: TParityKind; AN: Integer): Integer;
    { First entry of AKind naming item AIndex, or -1. }
    function  Find(AKind: TParityKind; AIndex: Integer): Integer;
    procedure Populate(ACount: Integer);
    procedure SetUp; override;
    procedure TearDown; override;
  end;

  { -----------------------------------------------------------------------
    OnChange / OnChanging — the (item, reason) pair and the veto
    ----------------------------------------------------------------------- }
  TListViewChangeParityTest = class(TListViewParityBase)
  published
    { OnChange names the item that changed and says the change was a STATE change }
    procedure TestChangeCarriesItemIndexAndStateReason;
    { A bulk selection change (Select All) reports index -1: LCL's `iItem < 0 -> Item = nil` }
    procedure TestBulkChangeReportsMinusOneIndex;
    { Committing an inline rename reports ctText, not ctState }
    procedure TestRenameCommitReportsTextChange;
    { Toggling a checkbox is an item STATE change and reports the checked row }
    procedure TestCheckToggleReportsStateChange;
    { OnChanging runs BEFORE OnChange and sees the same (index, reason) }
    procedure TestChangingPrecedesChangeWithSameArguments;
    { OnChanging clearing AAllowChange VETOES the selection: nothing moves, OnChange silent }
    procedure TestChangingVetoBlocksSelection;
    { The veto also blocks a keyboard (Space) selection toggle, and the key stays consumed }
    procedure TestChangingVetoBlocksSpaceToggle;
    { A veto on Select All leaves every bit clear }
    procedure TestChangingVetoBlocksSelectAll;
    { OnChange fires BEFORE OnSelectItem — customlistview.inc:405-406 }
    procedure TestChangeFiresBeforeSelectItem;
  end;

  { -----------------------------------------------------------------------
    OnSelectItem — the Selected flag, and the deselect nobody was told about
    ----------------------------------------------------------------------- }
  TListViewSelectItemParityTest = class(TListViewParityBase)
  published
    { Selecting a row reports it with Selected = True }
    procedure TestSelectReportsSelectedTrue;
    { Moving the selection reports the ABANDONED row with Selected = False — the headline
      defect: before the fix an app was never told a row lost the selection }
    procedure TestMovingSelectionReportsDeselectOfOldRow;
    { ClearSelection reports the abandoned row (it used to report nothing at all) }
    procedure TestClearSelectionReportsDeselect;
    { Programmatic de-selection (Selected[i] := False) reports False for that row }
    procedure TestProgrammaticDeselectReportsFalse;
    { Multi-select: Select All reports every row once, all True }
    procedure TestSelectAllReportsEveryRowTrue;
    { Multi-select: ClearSelection reports every previously selected row once, all False }
    procedure TestClearSelectionReportsEveryRowFalse;
    { A no-op selection (re-selecting the row that is already selected) reports nothing:
      the event is a state DELTA, exactly like LCL's notification-driven one }
    procedure TestReselectingSameRowIsSilent;
    { Collapsing MultiSelect drops every row but the focused one — and says so }
    procedure TestMultiSelectCollapseReportsDroppedRows;
  end;

implementation

{ ---------------------------------------------------------------------------
  TTyListViewParityAccess
  --------------------------------------------------------------------------- }

procedure TTyListViewParityAccess.XKeyDown(AKey: Word; AShift: TShiftState);
var
  k: Word;
begin
  k := AKey;
  KeyDown(k, AShift);
end;

{ ---------------------------------------------------------------------------
  TListViewParityBase
  --------------------------------------------------------------------------- }

procedure TListViewParityBase.Log(AKind: TParityKind; AIndex: Integer;
  AChange: TTyItemChange; ASelected: Boolean);
var
  n: Integer;
begin
  n := Length(FLog);
  SetLength(FLog, n + 1);
  FLog[n].Kind     := AKind;
  FLog[n].Index    := AIndex;
  FLog[n].Change   := AChange;
  FLog[n].Selected := ASelected;
end;

procedure TListViewParityBase.HChange(Sender: TObject; AIndex: Integer;
  AChange: TTyItemChange);
begin
  Log(pkChange, AIndex, AChange, False);
end;

procedure TListViewParityBase.HChanging(Sender: TObject; AIndex: Integer;
  AChange: TTyItemChange; var AAllowChange: Boolean);
begin
  Log(pkChanging, AIndex, AChange, False);
  if FVeto then AAllowChange := False;
end;

procedure TListViewParityBase.HSelect(Sender: TObject; AIndex: Integer;
  ASelected: Boolean);
begin
  Log(pkSelect, AIndex, ctState, ASelected);
end;

procedure TListViewParityBase.HEdited(Sender: TObject; AIndex: Integer;
  var AText: string);
begin
  { Accept whatever EndEdit committed. Bound only so the rename path has a handler;
    leaving AText alone means "commit it". }
end;

procedure TListViewParityBase.ClearLog;
begin
  SetLength(FLog, 0);
end;

function TListViewParityBase.Count(AKind: TParityKind): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(FLog) do
    if FLog[i].Kind = AKind then Inc(Result);
end;

function TListViewParityBase.PosOf(AKind: TParityKind; AN: Integer): Integer;
var
  i, n: Integer;
begin
  n := 0;
  for i := 0 to High(FLog) do
    if FLog[i].Kind = AKind then
    begin
      if n = AN then Exit(i);
      Inc(n);
    end;
  Result := -1;
end;

function TListViewParityBase.Nth(AKind: TParityKind; AN: Integer): TParityRec;
var
  p: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Index := -999;          { a miss must not look like a legitimate -1 }
  p := PosOf(AKind, AN);
  if p >= 0 then Result := FLog[p];
end;

function TListViewParityBase.Find(AKind: TParityKind; AIndex: Integer): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(FLog) do
    if (FLog[i].Kind = AKind) and (FLog[i].Index = AIndex) then Exit(i);
end;

procedure TListViewParityBase.Populate(ACount: Integer);
var
  i: Integer;
begin
  for i := 0 to ACount - 1 do
    FLV.Items.Add.Caption := 'row' + IntToStr(i);
  FLV.ItemsChanged;
end;

procedure TListViewParityBase.SetUp;
begin
  FLV := TTyListViewParityAccess.Create(nil);
  { Item index = display position: the sort is not what these guards are about. }
  FLV.AutoSort := False;
  FVeto := False;
  ClearLog;
end;

procedure TListViewParityBase.TearDown;
begin
  FreeAndNil(FLV);
  ClearLog;
end;

{ ---------------------------------------------------------------------------
  TListViewChangeParityTest
  --------------------------------------------------------------------------- }

procedure TListViewChangeParityTest.TestChangeCarriesItemIndexAndStateReason;
begin
  Populate(4);
  FLV.OnChange := @HChange;
  FLV.ItemIndex := 2;
  AssertEquals('OnChange fired once', 1, Count(pkChange));
  AssertEquals('OnChange names the item that changed', 2, Nth(pkChange, 0).Index);
  AssertTrue('a selection move is a STATE change', Nth(pkChange, 0).Change = ctState);
end;

procedure TListViewChangeParityTest.TestBulkChangeReportsMinusOneIndex;
begin
  Populate(4);
  FLV.MultiSelect := True;
  FLV.ClearSelection;
  FLV.OnChange := @HChange;
  FLV.SelectAll;
  AssertEquals('Select All fires OnChange once', 1, Count(pkChange));
  AssertEquals('a bulk change has no single subject -> -1', -1, Nth(pkChange, 0).Index);
  AssertTrue('still a STATE change', Nth(pkChange, 0).Change = ctState);
end;

procedure TListViewChangeParityTest.TestRenameCommitReportsTextChange;
begin
  Populate(3);
  FLV.ReadOnly := False;
  FLV.OnEdited := @HEdited;
  FLV.BeginEdit(1);
  { Bind AFTER BeginEdit: starting an edit moves the focus, and that selection change is
    not what this guard is about. }
  FLV.OnChange := @HChange;
  FLV.EndEdit(True);
  AssertEquals('committing a rename fires OnChange once', 1, Count(pkChange));
  AssertEquals('and names the renamed item', 1, Nth(pkChange, 0).Index);
  AssertTrue('a rename is a TEXT change, not a state change',
    Nth(pkChange, 0).Change = ctText);
end;

procedure TListViewChangeParityTest.TestCheckToggleReportsStateChange;
begin
  Populate(3);
  FLV.Checkboxes := True;
  FLV.OnChange := @HChange;
  FLV.Checked[2] := True;
  AssertEquals('checking a row fires OnChange once', 1, Count(pkChange));
  AssertEquals('and names the checked item', 2, Nth(pkChange, 0).Index);
  AssertTrue('a check is an item STATE change', Nth(pkChange, 0).Change = ctState);
end;

procedure TListViewChangeParityTest.TestChangingPrecedesChangeWithSameArguments;
begin
  Populate(4);
  FLV.OnChanging := @HChanging;
  FLV.OnChange   := @HChange;
  FLV.ItemIndex  := 3;
  AssertEquals('OnChanging fired once', 1, Count(pkChanging));
  AssertEquals('OnChange fired once', 1, Count(pkChange));
  AssertTrue('OnChanging runs FIRST', PosOf(pkChanging, 0) < PosOf(pkChange, 0));
  AssertEquals('OnChanging sees the same item', 3, Nth(pkChanging, 0).Index);
  AssertTrue('OnChanging sees the same reason', Nth(pkChanging, 0).Change = ctState);
end;

procedure TListViewChangeParityTest.TestChangingVetoBlocksSelection;
begin
  Populate(4);
  FLV.ItemIndex := 1;
  FLV.OnChanging   := @HChanging;
  FLV.OnChange     := @HChange;
  FLV.OnSelectItem := @HSelect;
  FVeto := True;
  ClearLog;
  FLV.ItemIndex := 3;
  AssertEquals('the veto keeps the old focus', 1, FLV.ItemIndex);
  AssertEquals('OnChanging still fired (it is what vetoed)', 1, Count(pkChanging));
  AssertEquals('a vetoed change fires no OnChange', 0, Count(pkChange));
  AssertEquals('a vetoed change fires no OnSelectItem', 0, Count(pkSelect));
end;

procedure TListViewChangeParityTest.TestChangingVetoBlocksSpaceToggle;
begin
  Populate(4);
  FLV.MultiSelect := True;
  FLV.ClearSelection;
  FLV.ItemIndex := 2;               { focus + select row 2 }
  FLV.OnChanging := @HChanging;
  FLV.OnChange   := @HChange;
  FVeto := True;
  ClearLog;
  FLV.XKeyDown(VK_SPACE);           { would toggle row 2 OFF }
  AssertTrue('vetoed Space leaves row 2 selected', FLV.Selected[2]);
  AssertEquals('OnChanging was consulted', 1, Count(pkChanging));
  AssertEquals('no OnChange from a vetoed Space', 0, Count(pkChange));
end;

procedure TListViewChangeParityTest.TestChangingVetoBlocksSelectAll;
var
  i: Integer;
begin
  Populate(4);
  FLV.MultiSelect := True;
  FLV.ClearSelection;
  FLV.OnChanging := @HChanging;
  FLV.OnChange   := @HChange;
  FVeto := True;
  ClearLog;
  FLV.SelectAll;
  for i := 0 to 3 do
    AssertFalse('vetoed Select All leaves row ' + IntToStr(i) + ' unselected',
      FLV.Selected[i]);
  AssertEquals('no OnChange from a vetoed Select All', 0, Count(pkChange));
end;

procedure TListViewChangeParityTest.TestChangeFiresBeforeSelectItem;
begin
  Populate(4);
  FLV.OnChange     := @HChange;
  FLV.OnSelectItem := @HSelect;
  FLV.ItemIndex := 2;
  AssertEquals('OnChange fired', 1, Count(pkChange));
  AssertEquals('OnSelectItem fired', 1, Count(pkSelect));
  AssertTrue('OnChange precedes OnSelectItem, as in LCL',
    PosOf(pkChange, 0) < PosOf(pkSelect, 0));
end;

{ ---------------------------------------------------------------------------
  TListViewSelectItemParityTest
  --------------------------------------------------------------------------- }

procedure TListViewSelectItemParityTest.TestSelectReportsSelectedTrue;
begin
  Populate(4);
  FLV.OnSelectItem := @HSelect;
  FLV.ItemIndex := 2;
  AssertEquals('one row changed selection', 1, Count(pkSelect));
  AssertEquals('and it is the one that was picked', 2, Nth(pkSelect, 0).Index);
  AssertTrue('Selected = True says it was CHOSEN', Nth(pkSelect, 0).Selected);
end;

procedure TListViewSelectItemParityTest.TestMovingSelectionReportsDeselectOfOldRow;
var
  i: Integer;
begin
  Populate(4);
  FLV.ItemIndex := 1;
  FLV.OnSelectItem := @HSelect;
  ClearLog;
  FLV.ItemIndex := 3;
  AssertEquals('both the abandoned and the chosen row are reported', 2, Count(pkSelect));
  i := Find(pkSelect, 1);
  AssertTrue('the abandoned row 1 is reported at all', i >= 0);
  AssertFalse('row 1 is reported as DESELECTED', FLog[i].Selected);
  i := Find(pkSelect, 3);
  AssertTrue('the chosen row 3 is reported', i >= 0);
  AssertTrue('row 3 is reported as selected', FLog[i].Selected);
end;

procedure TListViewSelectItemParityTest.TestClearSelectionReportsDeselect;
begin
  Populate(4);
  FLV.ItemIndex := 2;
  FLV.OnSelectItem := @HSelect;
  ClearLog;
  FLV.ClearSelection;
  AssertEquals('the abandoned row is reported', 1, Count(pkSelect));
  AssertEquals('and it is row 2', 2, Nth(pkSelect, 0).Index);
  AssertFalse('reported as deselected', Nth(pkSelect, 0).Selected);
end;

procedure TListViewSelectItemParityTest.TestProgrammaticDeselectReportsFalse;
begin
  Populate(4);
  FLV.MultiSelect := True;
  FLV.Selected[1] := True;
  FLV.OnSelectItem := @HSelect;
  ClearLog;
  FLV.Selected[1] := False;
  AssertEquals('exactly the dropped row is reported', 1, Count(pkSelect));
  AssertEquals('row 1', 1, Nth(pkSelect, 0).Index);
  AssertFalse('with Selected = False', Nth(pkSelect, 0).Selected);
end;

procedure TListViewSelectItemParityTest.TestSelectAllReportsEveryRowTrue;
var
  i: Integer;
begin
  Populate(4);
  FLV.MultiSelect := True;
  FLV.ClearSelection;
  FLV.OnSelectItem := @HSelect;
  ClearLog;
  FLV.SelectAll;
  AssertEquals('every row is reported once', 4, Count(pkSelect));
  for i := 0 to 3 do
  begin
    AssertEquals('reported in item order', i, Nth(pkSelect, i).Index);
    AssertTrue('as selected', Nth(pkSelect, i).Selected);
  end;
end;

procedure TListViewSelectItemParityTest.TestClearSelectionReportsEveryRowFalse;
var
  i: Integer;
begin
  Populate(4);
  FLV.MultiSelect := True;
  FLV.SelectAll;
  FLV.OnSelectItem := @HSelect;
  ClearLog;
  FLV.ClearSelection;
  AssertEquals('every previously selected row is reported once', 4, Count(pkSelect));
  for i := 0 to 3 do
  begin
    AssertEquals('reported in item order', i, Nth(pkSelect, i).Index);
    AssertFalse('as DESELECTED', Nth(pkSelect, i).Selected);
  end;
end;

procedure TListViewSelectItemParityTest.TestReselectingSameRowIsSilent;
begin
  Populate(4);
  FLV.ItemIndex := 2;
  FLV.OnSelectItem := @HSelect;
  ClearLog;
  { Single-select mode routes Selected[i] := True straight into SetSingleSelection with no
    same-value early-out, so the whole selection machinery -- CanChange, snapshot, delta --
    really runs here. It must still stay silent, because NOTHING changed: the event reports
    a state DELTA, not "a mutator was called". }
  FLV.Selected[2] := True;
  AssertEquals('a no-op selection reports nothing', 0, Count(pkSelect));
end;

procedure TListViewSelectItemParityTest.TestMultiSelectCollapseReportsDroppedRows;
var
  i: Integer;
begin
  Populate(4);
  FLV.MultiSelect := True;
  { Selected[] sets a bit WITHOUT moving the focus (ItemIndex stays -1), which is what lets
    all four rows be selected at once -- ItemIndex := n would collapse to a single row.
    With no focused item the mode switch adopts the FIRST selected row as the survivor. }
  for i := 0 to 3 do
    FLV.Selected[i] := True;
  FLV.OnSelectItem := @HSelect;
  ClearLog;
  FLV.MultiSelect := False;
  { Rows 1, 2 and 3 lose the selection; row 0 becomes the single selection and so is
    unchanged and NOT reported. }
  AssertEquals('three rows dropped out of the selection', 3, Count(pkSelect));
  for i := 0 to Count(pkSelect) - 1 do
  begin
    AssertFalse('every reported row lost the selection', Nth(pkSelect, i).Selected);
    AssertTrue('the surviving row is not reported', Nth(pkSelect, i).Index <> 0);
  end;
end;

initialization
  RegisterTest(TListViewChangeParityTest);
  RegisterTest(TListViewSelectItemParityTest);
end.
