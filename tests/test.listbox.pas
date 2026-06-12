unit test.listbox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, fpcunit, testregistry,
  tyControls.Base, tyControls.ListBox;
type
  TTyListBoxTest = class(TTestCase)
  private
    FForm: TForm;
    FList: TTyListBox;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestItemsOwnedAndLive;
    procedure TestSelectItemFiresOnChangeOnce;
    procedure TestSelectOutOfRangeClears;
    procedure TestKeyboardMovesSelection;
    procedure TestVisibleRowsMath;
    procedure TestTopIndexFollowsSelection;
    procedure TestTopIndexClamps;
    procedure TestWheelScrolls;
  end;
implementation

type
  TListBoxAccess = class(TTyListBox)
  public
    function StyleTypeKey: string;
    procedure CallDoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint);
  end;

  TChangeProbe = class
  public
    Count: Integer;
    procedure Handle(Sender: TObject);
  end;

procedure TChangeProbe.Handle(Sender: TObject);
begin
  Inc(Count);
end;

function TListBoxAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TListBoxAccess.CallDoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint);
begin
  DoMouseWheel(Shift, WheelDelta, MousePos);
end;

{ TTyListBoxTest }

procedure TTyListBoxTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FList := TTyListBox.Create(FForm);
  FList.Parent := FForm;
  // Pin the PPI: on macOS Font.PixelsPerInch defaults to 72, which would
  // scale ItemHeight 24 -> 18 and change VisibleRows; the geometry tests
  // assume 96ppi (scale factor 1).
  FList.Font.PixelsPerInch := 96;
end;

procedure TTyListBoxTest.TearDown;
begin
  FForm.Free;
end;

procedure TTyListBoxTest.TestTypeKey;
var
  Acc: TListBoxAccess;
begin
  Acc := TListBoxAccess.Create(FForm);
  Acc.Parent := FForm;
  try
    AssertEquals('TyListBox', Acc.StyleTypeKey);
  finally
    Acc.Free;
  end;
end;

procedure TTyListBoxTest.TestItemsOwnedAndLive;
begin
  FList.Items.Add('Alpha');
  FList.Items.Add('Beta');
  FList.Items.Add('Gamma');
  AssertEquals('items count after 3 adds', 3, FList.Items.Count);
  AssertEquals('item 0', 'Alpha', FList.Items[0]);
  AssertEquals('item 1', 'Beta', FList.Items[1]);
  AssertEquals('item 2', 'Gamma', FList.Items[2]);
end;

procedure TTyListBoxTest.TestSelectItemFiresOnChangeOnce;
var
  Probe: TChangeProbe;
begin
  FList.Items.Add('One');
  FList.Items.Add('Two');
  Probe := TChangeProbe.Create;
  try
    FList.OnChange := @Probe.Handle;
    FList.SelectItem(0);
    AssertEquals('OnChange fires once on real change', 1, Probe.Count);
    FList.SelectItem(0);
    AssertEquals('OnChange does not fire when index unchanged', 1, Probe.Count);
    FList.SelectItem(1);
    AssertEquals('OnChange fires on second real change', 2, Probe.Count);
  finally
    Probe.Free;
  end;
end;

procedure TTyListBoxTest.TestSelectOutOfRangeClears;
begin
  FList.Items.Add('One');
  FList.Items.Add('Two');
  FList.SelectItem(0);
  AssertEquals('index 0 selected', 0, FList.ItemIndex);
  FList.SelectItem(99);
  AssertEquals('out-of-range clears to -1', -1, FList.ItemIndex);
  FList.SelectItem(-5);
  AssertEquals('negative index clears to -1', -1, FList.ItemIndex);
end;

procedure TTyListBoxTest.TestKeyboardMovesSelection;
var
  I: Integer;
begin
  for I := 0 to 4 do
    FList.Items.Add(IntToStr(I));
  AssertEquals('initial ItemIndex', -1, FList.ItemIndex);

  // DOWN from -1 selects 0
  FList.SimulateKeyDown(VK_DOWN);
  AssertEquals('DOWN from -1 -> 0', 0, FList.ItemIndex);

  // DOWN again -> 1
  FList.SimulateKeyDown(VK_DOWN);
  AssertEquals('DOWN -> 1', 1, FList.ItemIndex);

  // UP -> 0
  FList.SimulateKeyDown(VK_UP);
  AssertEquals('UP -> 0', 0, FList.ItemIndex);

  // END -> last (4)
  FList.SimulateKeyDown(VK_END);
  AssertEquals('END -> 4', 4, FList.ItemIndex);

  // HOME -> first (0)
  FList.SimulateKeyDown(VK_HOME);
  AssertEquals('HOME -> 0', 0, FList.ItemIndex);

  // UP at 0 stays at 0
  FList.SimulateKeyDown(VK_UP);
  AssertEquals('UP clamps at 0', 0, FList.ItemIndex);

  // DOWN to end, then DOWN again clamps
  FList.SelectItem(4);
  FList.SimulateKeyDown(VK_DOWN);
  AssertEquals('DOWN clamps at last', 4, FList.ItemIndex);
end;

procedure TTyListBoxTest.TestVisibleRowsMath;
var
  LB: TTyListBox;
begin
  // Height = 100, ItemHeight = 24 @96ppi -> 100 div 24 = 4
  // Create without parent to avoid LCL cocoa geometry constraints
  LB := TTyListBox.Create(nil);
  try
    LB.Font.PixelsPerInch := 96;  // pin (macOS defaults to 72)
    LB.ItemHeight := 24;
    LB.Height := 100;
    // VisibleRows uses Height div MulDiv(ItemHeight, PPI, 96)
    // At 96ppi (default on test platform), MulDiv(24, 96, 96) = 24; 100 div 24 = 4
    AssertEquals('VisibleRows = 4 for height 100, itemheight 24@96ppi', 4, LB.VisibleRows);
  finally
    LB.Free;
  end;
end;

procedure TTyListBoxTest.TestTopIndexFollowsSelection;
var
  I: Integer;
begin
  for I := 0 to 9 do
    FList.Items.Add(IntToStr(I));
  FList.ItemHeight := 24;
  FList.Height := 100;
  // VisibleRows = 4; select item 9 -> TopIndex should be 9 - 4 + 1 = 6
  FList.SelectItem(9);
  AssertEquals('TopIndex after select 9 with 4 visible rows', 6, FList.TopIndex);
  // select item 0 -> TopIndex should be 0
  FList.SelectItem(0);
  AssertEquals('TopIndex after select 0', 0, FList.TopIndex);
end;

procedure TTyListBoxTest.TestTopIndexClamps;
var
  I: Integer;
begin
  for I := 0 to 9 do
    FList.Items.Add(IntToStr(I));
  FList.ItemHeight := 24;
  FList.Height := 100;
  // Max TopIndex = Max(0, Items.Count - VisibleRows) = Max(0, 10 - 4) = 6
  FList.TopIndex := 999;
  AssertEquals('TopIndex clamps to max (6)', 6, FList.TopIndex);
  FList.TopIndex := -5;
  AssertEquals('TopIndex clamps to 0', 0, FList.TopIndex);
end;

procedure TTyListBoxTest.TestWheelScrolls;
var
  Acc: TListBoxAccess;
  I: Integer;
  Pt: TPoint;
begin
  // Use access subclass to call DoMouseWheel
  Acc := TListBoxAccess.Create(FForm);
  Acc.Parent := FForm;
  for I := 0 to 9 do
    Acc.Items.Add(IntToStr(I));
  Acc.ItemHeight := 24;
  Acc.Height := 100;
  Acc.TopIndex := 0;
  AssertEquals('TopIndex starts at 0', 0, Acc.TopIndex);
  // Negative WheelDelta = scroll down (content moves up = TopIndex increases)
  Pt := Point(0, 0);
  Acc.CallDoMouseWheel([], -120, Pt);
  AssertEquals('negative delta scrolls down: TopIndex 0 -> 3', 3, Acc.TopIndex);
end;

initialization
  RegisterTest(TTyListBoxTest);
end.
