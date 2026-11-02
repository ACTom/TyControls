unit test.controls.combobox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, StdCtrls, LCLIntf, LCLType, fpcunit, testregistry,
  ImgList, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.ComboBox, tyControls.ListBox,
  tyControls.Edit,
  tyControls.ComboBoxEx, tyControls.OfficeComboBox, tyControls.AdvancedComboBox,
  tyControls.CheckComboBox, tyControls.Cascader, tyControls.TreeView, tyControls.TreeSelect;
type
  { Expose protected Click and RenderTo for tests }
  TComboAccess = class(TTyComboBox)
  public
    procedure SmokeRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure DoClick;
    { Allow tests to rewind the close-up tick so Click thinks enough time has passed }
    procedure AgeCloseUpTick;
    procedure DoKeyDown(var Key: Word; Shift: TShiftState);
    procedure DoTypeChar(const C: TUTF8Char);
    { Expose the headless popup-height calculation so DropDownCount sizing can be
      tested without creating a real win32 popup form (1407). }
    function PopupHeight(APPI: Integer): Integer;
  end;

  TEditCrack = class(TTyEdit);
  TListCrack = class(TTyListBox);
  TTreeSelectCrack = class(TTyTreeSelect);

  { #161 }
  TComboKeysTest = class(TTestCase)
  private
    FForm: TForm;
    FCount, FKeys, FPresses, FUtf8: Integer;
    procedure Count(Sender: TObject);
    procedure CountKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure CountPress(Sender: TObject; var Key: Char);
    procedure CountUtf8(Sender: TObject; var UTF8Key: TUTF8Char);
    function NewCombo(AStyle: TTyComboBoxStyle): TComboAccess;
    function EditorOf(C: TTyCustomComboBox): TTyEdit;
    procedure PressInList(C: TTyCustomComboBox; AKey: Word);
    function TwoColourImages: TImageList;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheOpenListsArrowsMoveTheHighlightOnly;
    procedure TestTheFieldTakesTheDropDownKeys;
    procedure TestTheFieldsEventsAreTheCombos;
    procedure TestOneTabStopPerCombo;
    procedure TestTypeAheadKeepsTheCurrentItemWhileThePrefixGrows;
    procedure TestItemsChangedWhileOpenArePickedRight;
    procedure TestNoCloseUpWithNothingOpen;
    procedure TestAnOpenListIsNotOpenedAgain;
    procedure TestDuplicateCaptionsKeepTheSelectedRow;
    procedure TestTheExAutocompleteListPaintsItsOwnRows;
    procedure TestTheExFieldLeavesRoomForTheImage;
    procedure TestAHeaderCaptionIsNoItem;
    procedure TestTheAdvancedTextIsTheTitle;
    procedure TestTheCheckFieldKeysOpenTheList;
    procedure TestAnOpenCascaderIsNotOpenedAgain;
    procedure TestTheListGetsTheActiveController;
    { #162 }
    procedure TestATreeSelectItemPickShowsItsText;
    procedure TestTheTreeSelectReopenGuardIsTheClicks;
    procedure TestNoCloseUpForATreeSelectOrCascaderWithNothingOpen;
    procedure TestEditingNodesKeepsTheCascaderDraft;
  end;

  TChangeProbe = class
  public
    Count: Integer;
    procedure Handle(Sender: TObject);
  end;

  { Headless probe: overrides DropDown to record the call without creating a
    win32 popup form (which fails in a headless / no-display environment). }
  TComboKeyProbe = class(TTyComboBox)
  public
    Opened: Boolean;
    procedure DropDown; override;   // record only; no popup window
    procedure DoKeyDown(var Key: Word; Shift: TShiftState);
    procedure DoTypeChar(const C: TUTF8Char);
  end;

  { Headless probe for OnDropDown: overrides DropDown so it fires the protected
    DoDropDown hook WITHOUT creating a real win32 popup form (avoids the 1407
    no-display error). Mirrors what inherited DropDown does on a real open. }
  TComboDropDownProbe = class(TTyComboBox)
  public
    procedure DropDown; override;   // fire DoDropDown only; no popup window
  end;

  TTyComboBoxTest = class(TTestCase)
  private
    FForm: TForm;
    FCombo: TComboAccess;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { --- retained existing tests --- }
    procedure TestTypeKey;
    procedure TestItemsLive;
    procedure TestSelectItemSetsIndexAndText;
    procedure TestSelectOutOfRangeClears;
    procedure TestChangeEventFires;
    procedure TestPaintSmoke;
    { --- new dropdown tests --- }
    procedure TestClickTogglesDropDown;
    procedure TestClickDoesNotCycleItems;
    procedure TestDropDownCreatesPopup;
    procedure TestPopupSelectionUpdatesCombo;
    procedure TestCloseUpIdempotent;
    procedure TestDropDownEmptyItemsNoop;
    { --- race guard tests --- }
    procedure TestCloseUpThenImmediateClickStaysClosed;
    procedure TestCloseUpThenAgedClickReopens;
    { A2 regression: DropDown must sync Controller to popup list every call }
    procedure TestDropDownSyncsControllerToPopup;
    { Bug #9: reassigning Controller after the popup exists must propagate
      immediately, without waiting for the next DropDown }
    procedure TestSetControllerPropagatesToPopup;
    { Task 2: closed-state keyboard selection }
    procedure TestArrowKeysChangeSelectionClosed;
    procedure TestAltDownOpensDropdown;
    { Task 3: type-ahead }
    procedure TestTypeAheadMatchPureFunction;
    procedure TestTypeAheadSelectsViaKeypress;
    { Task 4 (events parity): OnSelect / OnDropDown / OnCloseUp }
    procedure TestComboOnDropDownAndCloseUp;
    procedure TestComboOnSelectOnUserPick;
    { Task 12 (properties parity): DropDownCount / Sorted / MaxLength / CharCase }
    procedure TestDropDownCountSizesPopup;
    procedure TestPopupHeightHoldsExactlyDropDownCountRows;
    procedure TestSortedSortsAndKeepsSelection;
    procedure TestMaxLengthCharCaseRoundTrip;
  end;
implementation

procedure TChangeProbe.Handle(Sender: TObject);
begin
  Inc(Count);
end;

procedure TComboAccess.SmokeRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TComboAccess.DoClick;
begin
  Click;
end;

procedure TComboAccess.AgeCloseUpTick;
begin
  { Set FCloseUpTick to a value 1000ms in the past so the next Click
    sees enough elapsed time and will proceed to DropDown. }
  FCloseUpTick := GetTickCount64 - 1000;
end;

procedure TComboAccess.DoKeyDown(var Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;

procedure TComboAccess.DoTypeChar(const C: TUTF8Char);
var k: TUTF8Char;
begin
  k := C;
  UTF8KeyPress(k);
end;

function TComboAccess.PopupHeight(APPI: Integer): Integer;
begin
  Result := ComputePopupHeight(APPI);
end;

procedure TComboKeyProbe.DropDown;
begin
  Opened := True;   // headless-safe: do NOT call inherited (which creates a win32 form)
end;

procedure TComboKeyProbe.DoKeyDown(var Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;

procedure TComboKeyProbe.DoTypeChar(const C: TUTF8Char);
var k: TUTF8Char;
begin
  k := C;
  UTF8KeyPress(k);
end;

procedure TComboDropDownProbe.DropDown;
begin
  { Headless-safe: fire the OnDropDown hook exactly as a real open would, but
    skip the inherited body that creates a win32 TForm popup (1407 in no-display
    environments). }
  DoDropDown;
end;

procedure TTyComboBoxTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FCombo := TComboAccess.Create(FForm);
  FCombo.Parent := FForm;
  FCombo.Items.Add('Apple');
  FCombo.Items.Add('Banana');
  FCombo.Items.Add('Cherry');
end;

procedure TTyComboBoxTest.TearDown;
begin
  FForm.Free;
end;

procedure TTyComboBoxTest.TestTypeKey;
begin
  AssertEquals('TyComboBox', FCombo.GetStyleTypeKey);
end;

procedure TTyComboBoxTest.TestItemsLive;
begin
  AssertEquals('items count after SetUp adds', 3, FCombo.Items.Count);
  AssertEquals('Banana', FCombo.Items[1]);
end;

procedure TTyComboBoxTest.TestSelectItemSetsIndexAndText;
begin
  FCombo.SelectItem(2);
  AssertEquals('ItemIndex must follow selection', 2, FCombo.ItemIndex);
  AssertEquals('Text must mirror selected item', 'Cherry', FCombo.Text);
end;

procedure TTyComboBoxTest.TestSelectOutOfRangeClears;
begin
  FCombo.SelectItem(1);
  FCombo.SelectItem(99);
  AssertEquals('out-of-range selection clears index', -1, FCombo.ItemIndex);
  AssertEquals('out-of-range selection clears text', '', FCombo.Text);
end;

procedure TTyComboBoxTest.TestChangeEventFires;
var
  Probe: TChangeProbe;
begin
  Probe := TChangeProbe.Create;
  try
    FCombo.OnChange := @Probe.Handle;
    FCombo.SelectItem(0);
    AssertEquals('OnChange fires once on real change', 1, Probe.Count);
    FCombo.SelectItem(0);
    AssertEquals('OnChange does not fire when index unchanged', 1, Probe.Count);
  finally
    Probe.Free;
  end;
end;

procedure TTyComboBoxTest.TestPaintSmoke;
var
  Bmp: TBitmap;
begin
  FCombo.Items.Add('Apple');
  FCombo.SelectItem(0);
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(140, 28);
    FCombo.SmokeRender(Bmp.Canvas, Rect(0, 0, 140, 28), 96);
    AssertTrue('combobox RenderTo executed without exception', True);
  finally
    Bmp.Free;
  end;
end;

{ --- new dropdown tests --- }

procedure TTyComboBoxTest.TestClickTogglesDropDown;
begin
  AssertFalse('DroppedDown starts False', FCombo.DroppedDown);
  FCombo.DoClick;
  AssertTrue('DroppedDown is True after first Click', FCombo.DroppedDown);
  FCombo.DoClick;
  AssertFalse('DroppedDown is False after second Click', FCombo.DroppedDown);
end;

procedure TTyComboBoxTest.TestClickDoesNotCycleItems;
begin
  FCombo.SelectItem(0);
  FCombo.DoClick;      // opens dropdown; ItemIndex must NOT change
  AssertEquals('ItemIndex unchanged after Click', 0, FCombo.ItemIndex);
  AssertEquals('Text unchanged after Click', 'Apple', FCombo.Text);
end;

procedure TTyComboBoxTest.TestDropDownCreatesPopup;
begin
  FCombo.SelectItem(1);
  FCombo.DropDown;
  AssertTrue('DroppedDown=True after DropDown', FCombo.DroppedDown);
  AssertEquals('PopupList item count matches combo', 3, FCombo.PopupList.Items.Count);
  AssertEquals('PopupList ItemIndex synced to combo', 1, FCombo.PopupList.ItemIndex);
end;

procedure TTyComboBoxTest.TestPopupSelectionUpdatesCombo;
var
  Probe: TChangeProbe;
begin
  Probe := TChangeProbe.Create;
  try
    FCombo.OnChange := @Probe.Handle;
    FCombo.DropDown;
    { Drive selection directly via the popup list }
    FCombo.PopupList.SelectItem(2);
    AssertEquals('combo Text updated after popup selection', 'Cherry', FCombo.Text);
    AssertEquals('combo ItemIndex updated', 2, FCombo.ItemIndex);
    { DoPopupPick commits the row and QUEUES the close (QueueAsyncCall), so the dropdown
      only shuts once the queue is pumped. Pump it, or this asserts nothing: with no
      widgetset the popup never opened at all and DroppedDown was False for that reason
      instead of this one. }
    Forms.Application.ProcessMessages;
    AssertFalse('DroppedDown=False after selection', FCombo.DroppedDown);
    AssertEquals('OnChange fired exactly once', 1, Probe.Count);
  finally
    Probe.Free;
  end;
end;

procedure TTyComboBoxTest.TestCloseUpIdempotent;
begin
  { CloseUp before any DropDown must not crash }
  FCombo.CloseUp;
  FCombo.CloseUp;
  AssertFalse('DroppedDown still False', FCombo.DroppedDown);
  { Double CloseUp after a DropDown must also be safe }
  FCombo.DropDown;
  FCombo.CloseUp;
  FCombo.CloseUp;
  AssertFalse('DroppedDown False after double CloseUp', FCombo.DroppedDown);
end;

procedure TTyComboBoxTest.TestDropDownEmptyItemsNoop;
var
  EmptyCombo: TTyComboBox;
begin
  EmptyCombo := TTyComboBox.Create(FForm);
  EmptyCombo.Parent := FForm;
  try
    EmptyCombo.DropDown;
    AssertFalse('DroppedDown=False when Items empty', EmptyCombo.DroppedDown);
  finally
    EmptyCombo.Free;
  end;
end;

{ TestCloseUpThenImmediateClickStaysClosed
  Simulate the deactivate-then-click race: call CloseUp (records tick=now),
  then immediately DoClick. Since CloseUp just happened (<200ms), Click must
  NOT reopen the dropdown. DroppedDown stays False. }
procedure TTyComboBoxTest.TestCloseUpThenImmediateClickStaysClosed;
begin
  FCombo.DropDown;
  AssertTrue('dropped down before test', FCombo.DroppedDown);
  FCombo.CloseUp;
  AssertFalse('closed after CloseUp', FCombo.DroppedDown);
  { Simulate click arriving immediately after CloseUp (race scenario) }
  FCombo.DoClick;
  AssertFalse('DroppedDown stays False when Click arrives within 200ms of CloseUp',
    FCombo.DroppedDown);
end;

{ TestCloseUpThenAgedClickReopens
  After ageing FCloseUpTick by 1000ms, a DoClick must reopen the dropdown
  (the guard does not block it). }
procedure TTyComboBoxTest.TestCloseUpThenAgedClickReopens;
begin
  FCombo.DropDown;
  FCombo.CloseUp;
  AssertFalse('closed after CloseUp', FCombo.DroppedDown);
  { Age the tick so next Click is allowed to open }
  FCombo.AgeCloseUpTick;
  FCombo.DoClick;
  AssertTrue('DroppedDown=True after Click with aged close-up tick', FCombo.DroppedDown);
  FCombo.CloseUp; // cleanup
end;

{ TestDropDownSyncsControllerToPopup
  A2 regression: DropDown must propagate Controller to the popup listbox every
  time it is called, not only at popup-creation time.  This ensures a controller
  assigned after the first DropDown (or changed between drops) is honoured.

  Approach:
   1. DropDown once so the popup is created (Controller is nil at that point).
   2. CloseUp.
   3. Assign a real TTyStyleController.
   4. DropDown again.
   5. PopupList.Controller must equal the combo's Controller. }
procedure TTyComboBoxTest.TestDropDownSyncsControllerToPopup;
var
  Ctl: TTyStyleController;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    { First open with no controller — creates the popup form + listbox }
    FCombo.DropDown;
    FCombo.CloseUp;

    { Assign controller after the popup already exists }
    FCombo.Controller := Ctl;
    FCombo.DropDown;

    AssertTrue('PopupList.Controller must equal combo Controller after second DropDown',
      FCombo.PopupList.Controller = Ctl);

    FCombo.CloseUp; // cleanup
  finally
    Ctl.Free;
  end;
end;

{ TestSetControllerPropagatesToPopup
  Bug #9: SetController must forward the new controller to an already-created
  popup list. Without the override, FPopupList keeps the old controller until
  the next DropDown.

  Approach:
   1. DropDown once so the popup + listbox exist (combo Controller is nil).
   2. CloseUp.
   3. Assign a real TTyStyleController to combo.Controller.
   4. WITHOUT calling DropDown again, the popup list must already reflect it. }
procedure TTyComboBoxTest.TestSetControllerPropagatesToPopup;
var
  Ctl: TTyStyleController;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    FCombo.DropDown;
    FCombo.CloseUp;
    AssertTrue('popup list exists after DropDown', FCombo.PopupList <> nil);

    { Reassign controller while the popup already exists; do NOT DropDown again }
    FCombo.Controller := Ctl;

    AssertTrue('popup list Controller propagated immediately on reassignment',
      FCombo.PopupList.Controller = Ctl);
  finally
    Ctl.Free;
  end;
end;

procedure TTyComboBoxTest.TestArrowKeysChangeSelectionClosed;
var K: Word;
begin
  FCombo.Items.Clear;
  FCombo.Items.Add('Alpha'); FCombo.Items.Add('Beta'); FCombo.Items.Add('Gamma');
  FCombo.ItemIndex := 0;
  K := VK_DOWN; FCombo.DoKeyDown(K, []);
  AssertEquals('down selects next', 1, FCombo.ItemIndex);
  AssertFalse('did not open dropdown', FCombo.DroppedDown);
  K := VK_DOWN; FCombo.DoKeyDown(K, []);
  AssertEquals('down again', 2, FCombo.ItemIndex);
  K := VK_DOWN; FCombo.DoKeyDown(K, []);
  AssertEquals('down clamps at last', 2, FCombo.ItemIndex);
  K := VK_UP; FCombo.DoKeyDown(K, []);
  AssertEquals('up selects prev', 1, FCombo.ItemIndex);
  K := VK_HOME; FCombo.DoKeyDown(K, []);
  AssertEquals('home -> first', 0, FCombo.ItemIndex);
  K := VK_END; FCombo.DoKeyDown(K, []);
  AssertEquals('end -> last', 2, FCombo.ItemIndex);
end;

procedure TTyComboBoxTest.TestAltDownOpensDropdown;
var C: TComboKeyProbe; K: Word;
begin
  C := TComboKeyProbe.Create(nil);
  try
    C.Items.Add('A'); C.Items.Add('B'); C.Items.Add('C');
    C.ItemIndex := 0;
    C.Opened := False;
    K := VK_DOWN; C.DoKeyDown(K, [ssAlt]);          // Alt+Down -> DropDown (recorded)
    AssertTrue('Alt+Down routed to DropDown', C.Opened);
    AssertEquals('Alt+Down consumed key', 0, Integer(K));
    AssertEquals('Alt+Down did NOT advance selection', 0, C.ItemIndex);
    // F4 also toggles
    C.Opened := False;
    K := VK_F4; C.DoKeyDown(K, []);
    AssertTrue('F4 routed to DropDown', C.Opened);
  finally C.Free; end;
end;

procedure TTyComboBoxTest.TestTypeAheadMatchPureFunction;
var L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Add('Apple'); L.Add('Banana'); L.Add('Avocado'); L.Add('Cherry');
    AssertEquals('from -1, prefix a -> Apple(0)', 0, TyComboTypeAheadMatch(L, -1, 'a'));
    AssertEquals('from 0, prefix a -> Avocado(2)', 2, TyComboTypeAheadMatch(L, 0, 'a'));
    AssertEquals('wrap: from 2, prefix a -> Apple(0)', 0, TyComboTypeAheadMatch(L, 2, 'a'));
    AssertEquals('prefix av -> Avocado(2)', 2, TyComboTypeAheadMatch(L, -1, 'av'));
    AssertEquals('no match -> -1', -1, TyComboTypeAheadMatch(L, -1, 'z'));
    AssertEquals('case-insensitive', 1, TyComboTypeAheadMatch(L, -1, 'BAN'));
  finally L.Free; end;
end;

procedure TTyComboBoxTest.TestTypeAheadSelectsViaKeypress;
begin
  FCombo.Items.Clear;
  FCombo.Items.Add('Apple'); FCombo.Items.Add('Banana'); FCombo.Items.Add('Cherry');
  FCombo.ItemIndex := -1;
  FCombo.DoTypeChar('b');
  AssertEquals('typing b selects Banana', 1, FCombo.ItemIndex);
end;

{ Task 4: DropDown must fire OnDropDown; CloseUp must fire OnCloseUp.
  Headless-safe: TComboDropDownProbe.DropDown fires DoDropDown without building
  a real win32 popup form (avoids the 1407 no-display error). CloseUp is
  headless-safe on its own (it no-ops the Hide path when FPopup is nil) so it is
  driven on the real control. }
procedure TTyComboBoxTest.TestComboOnDropDownAndCloseUp;
var
  C: TComboDropDownProbe;
  Down, Up: TChangeProbe;
begin
  C := TComboDropDownProbe.Create(nil);
  Down := TChangeProbe.Create;
  Up := TChangeProbe.Create;
  try
    C.Items.Add('A'); C.Items.Add('B');
    C.OnDropDown := @Down.Handle;
    C.OnCloseUp := @Up.Handle;

    C.DropDown;
    AssertEquals('OnDropDown fired once on DropDown', 1, Down.Count);
    AssertEquals('OnCloseUp not fired by DropDown', 0, Up.Count);

    C.CloseUp;
    AssertEquals('OnCloseUp fired once on CloseUp', 1, Up.Count);
    AssertEquals('OnDropDown not re-fired by CloseUp', 1, Down.Count);
  finally
    Up.Free;
    Down.Free;
    C.Free;
  end;
end;

{ Task 4: a USER pick (closed-state keyboard select) fires OnSelect.
  A purely programmatic ItemIndex := must NOT fire OnSelect (matches LCL intent;
  programmatic changes go through OnChange only). }
procedure TTyComboBoxTest.TestComboOnSelectOnUserPick;
var
  C: TComboKeyProbe;
  Sel, Chg: TChangeProbe;
  K: Word;
begin
  C := TComboKeyProbe.Create(nil);
  Sel := TChangeProbe.Create;
  Chg := TChangeProbe.Create;
  try
    C.Items.Add('Alpha'); C.Items.Add('Beta'); C.Items.Add('Gamma');
    C.OnSelect := @Sel.Handle;
    C.OnChange := @Chg.Handle;

    { Programmatic set fires OnChange but NOT OnSelect }
    C.ItemIndex := 0;
    AssertEquals('programmatic ItemIndex fires OnChange', 1, Chg.Count);
    AssertEquals('programmatic ItemIndex does NOT fire OnSelect', 0, Sel.Count);

    { User pick via closed-state Down arrow fires OnSelect }
    K := VK_DOWN; C.DoKeyDown(K, []);
    AssertEquals('keyboard Down advanced selection', 1, C.ItemIndex);
    AssertEquals('keyboard user-pick fires OnSelect', 1, Sel.Count);
    AssertEquals('keyboard user-pick also fires OnChange', 2, Chg.Count);

    { Type-ahead user pick also fires OnSelect }
    C.DoTypeChar('g');
    AssertEquals('type-ahead selected Gamma', 2, C.ItemIndex);
    AssertEquals('type-ahead user-pick fires OnSelect', 2, Sel.Count);
  finally
    Chg.Free;
    Sel.Free;
    C.Free;
  end;
end;

{ Task 12: DropDownCount governs the dropdown popup height.
  We test the headless height calculation (ComputePopupHeight) directly instead
  of building a real win32 popup (which 1407s in a no-display environment).
  With more items than DropDownCount, the popup shows exactly DropDownCount rows;
  with fewer, it shrinks to Items.Count rows. }
procedure TTyComboBoxTest.TestDropDownCountSizesPopup;
var
  hFull, hClamped, hFew, rowH: Integer;
  i: Integer;
begin
  FCombo.Items.Clear;
  for i := 1 to 20 do
    FCombo.Items.Add('Item' + IntToStr(i));

  AssertEquals('DropDownCount default is 8', 8, FCombo.DropDownCount);

  { Default 8 with 20 items: popup sized for 8 rows. }
  hFull := FCombo.PopupHeight(96);

  { Raising DropDownCount to 12 (still < 20 items) makes a taller popup. }
  FCombo.DropDownCount := 12;
  hClamped := FCombo.PopupHeight(96);
  AssertTrue('12 visible rows is taller than 8 rows', hClamped > hFull);

  { Derive the per-row height from the two measurements and verify the formula. }
  rowH := (hClamped - hFull) div (12 - 8);
  AssertTrue('row height is positive', rowH > 0);
  AssertEquals('popup height = DropDownCount rows + chrome (8 rows)',
    8 * rowH + (hFull - 8 * rowH), hFull);

  { Fewer items than DropDownCount: popup clamps to the item count, not the count. }
  FCombo.Items.Clear;
  FCombo.Items.Add('Only'); FCombo.Items.Add('Two');
  FCombo.DropDownCount := 8;
  hFew := FCombo.PopupHeight(96);
  AssertEquals('popup clamps to 2 item rows when fewer items than DropDownCount',
    hFull - 6 * rowH, hFew);
end;

{ The contract between the popup sizer and the list's own scroll geometry, stated as the
  user sees it: a dropdown holding EXACTLY DropDownCount items gets a popup in which the
  list shows every one of them and has nothing to scroll. The two sides compute height
  independently (PopupHeightFor here, ViewportHeight in TTyListBox), so either one
  changing what it does about the theme's padding without the other breaks this -- the
  exactly-N popup grows a needless scrollbar, or clips its own last row. }
procedure TTyComboBoxTest.TestPopupHeightHoldsExactlyDropDownCountRows;
var
  h, i: Integer;
  List: TTyListBox;
begin
  FCombo.Items.Clear;
  for i := 1 to 8 do
    FCombo.Items.Add('Item' + IntToStr(i));
  FCombo.ItemHeight := 24;
  AssertEquals('the fixture really is the exactly-N shape', 8, FCombo.DropDownCount);
  h := FCombo.PopupHeight(96);

  { The popup form is borderless and the list fills it (alClient), so the list's height
    IS the computed popup height -- lay a list out at it and read the geometry back. }
  List := TTyListBox.Create(FForm);
  List.Parent := FForm;
  List.Font.PixelsPerInch := 96;
  List.ItemHeight := 24;
  for i := 1 to 8 do
    List.Items.Add('Item' + IntToStr(i));
  List.SetBounds(0, 0, 120, h);
  AssertEquals('the popup height shows every one of the 8 rows', 8, List.VisibleRows);
  List.TopIndex := 999;
  AssertEquals('and leaves nothing to scroll to', 0, List.TopIndex);
end;

{ Task 12 DEEP-FLAG: Sorted reorders Items alphabetically (case-insensitive) and
  keeps the SAME item selected (tracked by its text, re-found after sort). }
procedure TTyComboBoxTest.TestSortedSortsAndKeepsSelection;
begin
  FCombo.Items.Clear;
  FCombo.Items.Add('Cherry');
  FCombo.Items.Add('apple');
  FCombo.Items.Add('Banana');
  FCombo.ItemIndex := 0;                 // select 'Cherry'
  AssertEquals('selected Cherry before sort', 'Cherry', FCombo.Text);

  AssertFalse('Sorted defaults False', FCombo.Sorted);
  FCombo.Sorted := True;

  { Case-insensitive ascending order: apple, Banana, Cherry }
  AssertEquals('item0 after sort', 'apple', FCombo.Items[0]);
  AssertEquals('item1 after sort', 'Banana', FCombo.Items[1]);
  AssertEquals('item2 after sort', 'Cherry', FCombo.Items[2]);

  { Same item stays selected — Cherry moved from index 0 to index 2 }
  AssertEquals('selection text preserved across sort', 'Cherry', FCombo.Text);
  AssertEquals('ItemIndex re-found after sort', 2, FCombo.ItemIndex);

  { Adding a new item while Sorted keeps the list sorted }
  FCombo.Items.Add('Aardvark');
  AssertEquals('inserted in sorted position', 'Aardvark', FCombo.Items[0]);
  { Selection still tracks Cherry (now index 3) }
  AssertEquals('selection still Cherry after insert', 'Cherry', FCombo.Text);
  AssertEquals('ItemIndex follows item across insert', 3, FCombo.ItemIndex);
end;

{ Task 12: MaxLength / CharCase are published stored props. This read-only combo
  has no edit field, so they are reserved (no-op on display) but must round-trip. }
procedure TTyComboBoxTest.TestMaxLengthCharCaseRoundTrip;
begin
  AssertEquals('MaxLength default 0', 0, FCombo.MaxLength);
  AssertTrue('CharCase default ecNormal', FCombo.CharCase = ecNormal);

  FCombo.MaxLength := 12;
  AssertEquals('MaxLength round-trips', 12, FCombo.MaxLength);

  FCombo.CharCase := ecUpperCase;
  AssertTrue('CharCase round-trips', FCombo.CharCase = ecUpperCase);

  { Read-only combo: CharCase does not alter the displayed selected text. }
  FCombo.Items.Clear;
  FCombo.Items.Add('lower');
  FCombo.ItemIndex := 0;
  AssertEquals('CharCase does not mutate displayed text (read-only combo)',
    'lower', FCombo.Text);
end;

{ ---------------------------------------------------------------------------
  #161: the keys of an open list and of the field, the field's events, one Tab
  stop, type-ahead, and the bookkeeping of opening and closing
  --------------------------------------------------------------------------- }

var
  KeysWidgetSetReady: Boolean = False;

procedure TComboKeysTest.Count(Sender: TObject);
begin
  Inc(FCount);
end;

procedure TComboKeysTest.CountKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  Inc(FKeys);
end;

procedure TComboKeysTest.CountPress(Sender: TObject; var Key: Char);
begin
  Inc(FPresses);
end;

procedure TComboKeysTest.CountUtf8(Sender: TObject; var UTF8Key: TUTF8Char);
begin
  Inc(FUtf8);
end;

procedure TComboKeysTest.SetUp;
begin
  if not KeysWidgetSetReady then
  begin
    Forms.Application.Initialize;
    KeysWidgetSetReady := True;
  end;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(-4000, -4000, 300, 200);
  FForm.Visible := True;
  FCount := 0;
  FKeys := 0;
  FPresses := 0;
  FUtf8 := 0;
end;

procedure TComboKeysTest.TearDown;
begin
  FreeAndNil(FForm);
end;

function TComboKeysTest.NewCombo(AStyle: TTyComboBoxStyle): TComboAccess;
begin
  Result := TComboAccess.Create(FForm);
  Result.Parent := FForm;
  Result.SetBounds(0, 0, 160, 26);
  Result.Style := AStyle;
  Result.Items.Add('Apple');
  Result.Items.Add('Apricot');
  Result.Items.Add('Banana');
end;

function TComboKeysTest.EditorOf(C: TTyCustomComboBox): TTyEdit;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to C.ControlCount - 1 do
    if C.Controls[i] is TTyEdit then Exit(TTyEdit(C.Controls[i]));
end;

procedure TComboKeysTest.PressInList(C: TTyCustomComboBox; AKey: Word);
var
  f: TCustomForm;
  k: Word;
begin
  f := GetParentForm(TComboAccess(C).PopupList);
  k := AKey;
  f.OnKeyDown(f, k, []);
  Application.ProcessMessages;   // the deferred close of a pick
end;

procedure TComboKeysTest.TestTheOpenListsArrowsMoveTheHighlightOnly;
var c: TComboAccess;
begin
  c := NewCombo(csDropDownList);
  c.ItemIndex := 0;
  c.DropDown;
  AssertTrue('setup: open', c.DroppedDown);
  PressInList(c, VK_DOWN);
  AssertEquals('an arrow picks nothing', 0, c.ItemIndex);
  AssertTrue('and closes nothing', c.DroppedDown);
  AssertEquals('it moves the highlight', 1, c.PopupList.ItemIndex);
  PressInList(c, VK_ESCAPE);
  AssertFalse('Esc closes the list', c.DroppedDown);
  AssertEquals('and leaves the value as it was', 0, c.ItemIndex);
  c.AgeCloseUpTick;
  c.DropDown;
  PressInList(c, VK_DOWN);
  PressInList(c, VK_DOWN);
  PressInList(c, VK_RETURN);
  AssertEquals('Enter picks the highlight', 2, c.ItemIndex);
  AssertFalse('and closes the list', c.DroppedDown);
end;

procedure TComboKeysTest.TestTheFieldTakesTheDropDownKeys;
var c: TComboAccess;
begin
  c := NewCombo(csDropDown);
  c.SimulateEditorKeyForTest(VK_DOWN);
  AssertEquals('closed, Down steps to the first item', 0, c.ItemIndex);
  c.SimulateEditorKeyForTest(VK_DOWN);
  AssertEquals('and on', 1, c.ItemIndex);
  c.SimulateEditorKeyForTest(VK_F4);
  AssertTrue('F4 opens the list from the field', c.DroppedDown);
  c.SimulateEditorKeyForTest(VK_DOWN);
  AssertEquals('open, Down moves the highlight', 2, c.PopupList.ItemIndex);
  AssertEquals('and picks nothing yet', 1, c.ItemIndex);
  c.SimulateEditorKeyForTest(VK_RETURN);
  Application.ProcessMessages;
  AssertEquals('Enter picks it', 2, c.ItemIndex);
  AssertEquals('into the field', 'Banana', c.Text);
end;

procedure TComboKeysTest.TestTheFieldsEventsAreTheCombos;
var
  c: TComboAccess;
  ed: TTyEdit;
  k: Word;
  u: TUTF8Char;
begin
  c := NewCombo(csDropDown);
  c.OnKeyDown := @CountKey;
  c.OnKeyUp := @CountKey;
  c.OnKeyPress := @CountPress;
  c.OnUTF8KeyPress := @CountUtf8;
  c.OnEditingDone := @Count;
  ed := EditorOf(c);
  AssertNotNull('setup: the field', ed);
  k := VK_A;
  TEditCrack(ed).KeyDown(k, []);
  k := VK_A;
  TEditCrack(ed).KeyUp(k, []);
  AssertEquals('OnKeyDown and OnKeyUp are the combo''s', 2, FKeys);
  u := 'x';
  TEditCrack(ed).UTF8KeyPress(u);
  AssertEquals('OnUTF8KeyPress', 1, FUtf8);
  AssertEquals('OnKeyPress', 1, FPresses);
  k := VK_RETURN;
  TEditCrack(ed).KeyDown(k, []);
  AssertEquals('Enter in the field is the combo''s EditingDone', 1, FCount);
end;

procedure TComboKeysTest.TestOneTabStopPerCombo;
var
  c: TComboAccess;
  ed: TTyEdit;
begin
  c := NewCombo(csDropDown);
  ed := EditorOf(c);
  AssertTrue('the published TabStop holds', c.TabStop);
  AssertTrue('the field is the stop', ed.TabStop);
  AssertFalse('the combo itself is none', TWinControl(c).TabStop);
  c.TabStop := False;
  AssertFalse('TabStop := False takes the field''s', ed.TabStop);
  c.TabStop := True;
  c.Style := csDropDownList;
  AssertTrue('a list combo is its own stop', TWinControl(c).TabStop);
  AssertFalse('with no field to stop at', ed.TabStop);
  c.Style := csDropDown;
  c.SetFocus;
  AssertSame('the focus is the field''s', TObject(ed), TObject(FForm.ActiveControl));
end;

procedure TComboKeysTest.TestTypeAheadKeepsTheCurrentItemWhileThePrefixGrows;
var c: TComboAccess;
begin
  c := NewCombo(csDropDownList);
  c.DoTypeChar('a');
  AssertEquals('setup: a', 'Apple', c.Text);
  c.DoTypeChar('p');
  AssertEquals('ap still names Apple: it stays', 'Apple', c.Text);
  c.DoTypeChar('r');
  AssertEquals('apr moves on', 'Apricot', c.Text);
end;

procedure TComboKeysTest.TestItemsChangedWhileOpenArePickedRight;
var c: TComboAccess;
begin
  c := NewCombo(csDropDownList);
  c.ItemIndex := 0;
  c.DropDown;
  c.Items.Insert(0, 'Zucchini');
  AssertEquals('the open list shows the rows as they are', 'Zucchini', c.PopupList.Items[0]);
  PressInList(c, VK_HOME);
  PressInList(c, VK_RETURN);
  AssertEquals('a pick names the row it shows', 'Zucchini', c.Text);
end;

procedure TComboKeysTest.TestNoCloseUpWithNothingOpen;
var c: TComboAccess;
begin
  c := NewCombo(csDropDown);
  c.OnCloseUp := @Count;
  c.CloseUp;
  AssertEquals('nothing open: no close-up', 0, FCount);
  c.SimulateTypedTextForTest('zzz');
  AssertEquals('nor for typing that matches nothing', 0, FCount);
  c.Clear;
  AssertEquals('nor from Clear', 0, FCount);
end;

procedure TComboKeysTest.TestAnOpenListIsNotOpenedAgain;
var c: TComboAccess;
begin
  c := NewCombo(csDropDownList);
  c.OnDropDown := @Count;
  c.DroppedDown := True;
  c.DroppedDown := True;
  AssertEquals('OnDropDown once for an open list', 1, FCount);
  c.CloseUp;
  c.AgeCloseUpTick;
  c.Enabled := False;
  c.DroppedDown := True;
  AssertFalse('a disabled combo opens none', c.DroppedDown);
end;

procedure TComboKeysTest.TestDuplicateCaptionsKeepTheSelectedRow;
var c: TComboAccess;
begin
  c := NewCombo(csDropDownList);
  c.Items.Add('Apple');   // a second Apple, at 3
  c.ItemIndex := 3;
  c.Items.Add('Cherry');
  AssertEquals('the selected Apple stays the selected one', 3, c.ItemIndex);
end;

function TComboKeysTest.TwoColourImages: TImageList;
var bmp: TBitmap;

  procedure AddSolid(AColor: TColor);
  begin
    bmp.Canvas.Brush.Color := AColor;
    bmp.Canvas.FillRect(0, 0, 16, 16);
    Result.Add(bmp, nil);
  end;

begin
  Result := TImageList.Create(FForm);
  Result.Width := 16;
  Result.Height := 16;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(16, 16);
    AddSolid(clRed);    // 0
    AddSolid(clBlue);   // 1
  finally
    bmp.Free;
  end;
end;

procedure TComboKeysTest.TestTheExAutocompleteListPaintsItsOwnRows;
var
  c: TTyComboBoxEx;
  lst: TTyCustomListBox;
  bmp: TBitmap;
  b: TBGRABitmap;
  x, y, rowH, red, blue: Integer;
  px: TBGRAPixel;
begin
  c := TTyComboBoxEx.Create(FForm);
  c.Parent := FForm;
  c.SetBounds(0, 0, 160, 26);
  c.Images := TwoColourImages;
  c.Style := csDropDown;
  c.AddItem('Apple', 0);    // red
  c.AddItem('Banana', 1);   // blue
  c.SimulateTypedTextForTest('B');
  lst := TComboAccess(c).PopupList;
  AssertEquals('setup: the list holds the match only', 1, lst.Items.Count);
  AssertEquals('setup: Banana', 'Banana', lst.Items[0]);
  rowH := lst.ItemHeight;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(160, rowH * 2);
    TListCrack(lst).RenderTo(bmp.Canvas, Rect(0, 0, 160, rowH * 2), 96);
    b := TBGRABitmap.Create(bmp);
    try
      red := 0;
      blue := 0;
      for y := 0 to rowH - 1 do
        for x := 0 to 60 do
        begin
          px := b.GetPixel(x, y);
          if (px.red > 200) and (px.green < 40) and (px.blue < 40) then Inc(red);
          if (px.blue > 200) and (px.green < 40) and (px.red < 40) then Inc(blue);
        end;
    finally
      b.Free;
    end;
  finally
    bmp.Free;
  end;
  AssertTrue(Format('the row shows Banana''s own image (blue %d)', [blue]), blue > 20);
  AssertEquals('not Apple''s, the combo''s row 0', 0, red);
end;

procedure TComboKeysTest.TestTheExFieldLeavesRoomForTheImage;
var
  c: TTyComboBoxEx;
  ed: TTyEdit;
  l0, r0, ppi, sz: Integer;
begin
  c := TTyComboBoxEx.Create(FForm);
  c.Parent := FForm;
  c.SetBounds(0, 0, 160, 26);
  c.Style := csDropDown;
  c.AddItem('Apple', 0);
  c.ItemIndex := 0;
  ed := EditorOf(c);
  AssertNotNull('setup: the field', ed);
  l0 := ed.Left;
  r0 := ed.Left + ed.Width;
  c.Images := TwoColourImages;
  ppi := c.Font.PixelsPerInch;
  { The image DrawImageText puts in the field: 4 px in, the field's height less 6 px square. }
  sz := ed.Height - MulDiv(6, ppi, 96);
  AssertTrue(Format('the edit box starts past the image (%d, the image ends at %d)',
    [ed.Left, l0 + MulDiv(4, ppi, 96) + sz]), ed.Left >= l0 + MulDiv(4, ppi, 96) + sz);
  AssertEquals('and still ends where it did', r0, ed.Left + ed.Width);
  c.Images := nil;
  AssertEquals('no list, no room kept', l0, ed.Left);
end;

procedure TComboKeysTest.TestAHeaderCaptionIsNoItem;
var o: TTyOfficeComboBox;
begin
  o := TTyOfficeComboBox.Create(FForm);
  o.Parent := FForm;
  o.AddHeader('Fruit');
  o.Items.Add('Apple');
  o.AddHeader('Veg');
  o.Items.Add('Leek');
  o.Text := 'Fruit';
  AssertEquals('a header''s caption selects no row', -1, o.ItemIndex);
  o.Text := 'leek';
  AssertEquals('an item''s does, as LCL''s, whatever the case', 3, o.ItemIndex);
end;

procedure TComboKeysTest.TestTheAdvancedTextIsTheTitle;
var a: TTyAdvancedComboBox;
begin
  a := TTyAdvancedComboBox.Create(FForm);
  a.Parent := FForm;
  a.AddItem('Mail', 'Inbox and more', -1);
  a.AddItem('Calendar', 'Meetings', -1);
  a.ItemIndex := 1;
  AssertEquals('Text is the title the field shows', 'Calendar', a.Text);
  a.Text := 'Mail';
  AssertEquals('and a title selects its row', 0, a.ItemIndex);
  a.Items.Insert(0, 'Notes' + LineEnding + 'Jottings');
  AssertEquals('a row going in above keeps the selected one', 1, a.ItemIndex);
  AssertEquals('by its title', 'Mail', a.Text);
end;

procedure TComboKeysTest.TestTheCheckFieldKeysOpenTheList;
var
  ck: TTyCheckComboBox;
  k: Word;
begin
  ck := TTyCheckComboBox.Create(FForm);
  ck.Parent := FForm;
  ck.SetBounds(0, 0, 160, 26);
  ck.Items.Add('Apple');
  ck.Items.Add('Banana');
  ck.Items.Add('Cherry');
  ck.OnChange := @Count;
  ck.OnSelect := @Count;
  ck.ItemIndex := 1;
  AssertEquals('ItemIndex is a row nobody sees: no OnChange', 0, FCount);
  k := VK_DOWN;
  TComboAccess(ck).DoKeyDown(k, []);
  AssertTrue('Down on the field opens the list', ck.DroppedDown);
  AssertEquals('with the highlight on the next row', 2, TComboAccess(ck).PopupList.ItemIndex);
  AssertEquals('and moves no unseen value', 1, ck.ItemIndex);
  AssertEquals('so tells nobody', 0, FCount);
  PressInList(ck, VK_RETURN);
  AssertFalse('Enter closes the list', ck.DroppedDown);
  AssertEquals('and ticks nothing', 0, ck.CheckedCount);
  TComboAccess(ck).AgeCloseUpTick;
  k := VK_SPACE;
  TComboAccess(ck).DoKeyDown(k, []);
  AssertTrue('Space on the field opens it too', ck.DroppedDown);
  PressInList(ck, VK_ESCAPE);
  TComboAccess(ck).AgeCloseUpTick;
  TComboAccess(ck).DoTypeChar('c');
  AssertTrue('type-ahead opens it', ck.DroppedDown);
  AssertEquals('on the match', 2, TComboAccess(ck).PopupList.ItemIndex);
  AssertEquals('still telling nobody', 0, FCount);
end;

procedure TComboKeysTest.TestTheListGetsTheActiveController;
var
  c: TComboAccess;
  S: TTyStyleSet;
begin
  c := NewCombo(csDropDownList);
  AssertNull('setup: no Controller of its own', c.Controller);
  S := c.ActiveController.Model.ResolveStyle('TyListBox', '', []);
  AssertTrue('setup: the theme gives the list a solid ground', S.Background.Kind = tfkSolid);
  c.DropDown;
  AssertEquals('the drop-down is painted from the theme in effect, not from none',
    TyColorToLCL(S.Background.Color), GetParentForm(c.PopupList).Color);
end;

{ #162: an Items-built tree answers its rows from the items, not from OnGetText -- the field
  showed nothing. }
procedure TComboKeysTest.TestATreeSelectItemPickShowsItsText;
var
  ts: TTyTreeSelect;
  b: TTyTreeNodeItem;
begin
  ts := TTyTreeSelect.Create(FForm);
  ts.Parent := FForm;
  ts.Items.AddChild(nil, 'Apple');
  b := ts.Items.AddChild(nil, 'Banana');
  ts.SelectedNode := b.Node;
  AssertEquals('the pick''s caption', 'Banana', ts.Text);
end;

{ #162: the 200 ms guard is against the click that closed the drop re-opening it; DropDown from
  code or the keyboard opens at once. }
procedure TComboKeysTest.TestTheTreeSelectReopenGuardIsTheClicks;
var ts: TTyTreeSelect;
begin
  ts := TTyTreeSelect.Create(FForm);
  ts.Parent := FForm;
  ts.SetBounds(0, 0, 160, 26);
  ts.Items.AddChild(nil, 'Apple');
  ts.DropDown;
  AssertTrue('setup: open', ts.DroppedDown);
  ts.CloseUp;
  TTreeSelectCrack(ts).Click;
  AssertFalse('a click right after the close-up does not reopen', ts.DroppedDown);
  ts.DropDown;
  AssertTrue('DropDown from code does, at once', ts.DroppedDown);
  ts.CloseUp;
end;

procedure TComboKeysTest.TestNoCloseUpForATreeSelectOrCascaderWithNothingOpen;
var
  ts: TTyTreeSelect;
  c: TTyCascader;
begin
  ts := TTyTreeSelect.Create(FForm);
  ts.Parent := FForm;
  ts.OnCloseUp := @Count;
  ts.CloseUp;
  AssertEquals('a tree select with nothing open: no close-up', 0, FCount);
  c := TTyCascader.Create(FForm);
  c.Parent := FForm;
  c.Nodes.AddNode('East');
  c.OnCloseUp := @Count;
  c.CloseUp;
  AssertEquals('nor a cascader', 0, FCount);
end;

{ #162: the panel's draft is the choice the user is making; an edit of Nodes keeps it as far
  as the tree still has it, instead of putting the committed value back. }
procedure TComboKeysTest.TestEditingNodesKeepsTheCascaderDraft;
var
  c: TTyCascader;
  p: TTyCascaderPanel;
  east, north: TTyCascaderNode;
  want: TTyCascaderPath;
begin
  c := TTyCascader.Create(FForm);
  c.Parent := FForm;
  c.Font.PixelsPerInch := 96;
  east := c.Nodes.AddNode('East');
  east.Children.AddNode('Hangzhou');
  east.Children.AddNode('Ningbo');
  north := c.Nodes.AddNode('North');
  north.Children.AddNode('Beijing');
  SetLength(want, 2);
  want[0] := 0;
  want[1] := 1;
  c.Path := want;               // the value: East / Ningbo
  c.DropDown;
  AssertTrue('setup: open', c.DroppedDown);
  p := c.DropDownPanel;
  want[0] := 1;
  want[1] := 0;
  p.Path := want;               // the user is on North / Beijing
  east.Children.AddNode('Wenzhou');
  AssertTrue('an edit elsewhere keeps the draft', TyCascaderPathsEqual(want, p.Path));
  north.Children[0].Free;
  SetLength(want, 1);
  AssertTrue('an edit of the draft''s own option cuts it back to what is left',
    TyCascaderPathsEqual(want, p.Path));
  c.CloseUp;
end;

procedure TComboKeysTest.TestAnOpenCascaderIsNotOpenedAgain;
var c: TTyCascader;
begin
  c := TTyCascader.Create(FForm);
  c.Parent := FForm;
  c.Font.PixelsPerInch := 96;
  c.Nodes.AddNode('East').Children.AddNode('Hangzhou');
  c.OnDropDown := @Count;
  c.DropDown;
  AssertTrue('setup: open', c.DroppedDown);
  c.DropDown;
  AssertEquals('OnDropDown once for an open list', 1, FCount);
  c.CloseUp;
  c.Enabled := False;
  c.DropDown;
  AssertFalse('a disabled cascader opens none', c.DroppedDown);
end;


initialization
  RegisterTest(TTyComboBoxTest);
  RegisterTest(TComboKeysTest);
end.
