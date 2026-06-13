unit test.controls.combobox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLIntf, fpcunit, testregistry,
  tyControls.Base, tyControls.Controller, tyControls.ComboBox, tyControls.ListBox;
type
  { Expose protected Click and RenderTo for tests }
  TComboAccess = class(TTyComboBox)
  public
    procedure SmokeRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure DoClick;
    { Allow tests to rewind the close-up tick so Click thinks enough time has passed }
    procedure AgeCloseUpTick;
  end;

  TChangeProbe = class
  public
    Count: Integer;
    procedure Handle(Sender: TObject);
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

initialization
  RegisterTest(TTyComboBoxTest);
end.
