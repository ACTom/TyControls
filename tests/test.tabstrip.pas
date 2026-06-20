unit test.tabstrip;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Forms, LCLType, fpcunit, testregistry,
  tyControls.TabStrip;
type
  { Concrete strip backed by a plain caption list, so the page-agnostic header
    engine (TTyCustomTabStrip) can be exercised without a page control. }
  TStripAccess = class(TTyCustomTabStrip)
  private
    FCaps: TStringList;
    FReorderFrom, FReorderTo: Integer;
  protected
    function GetTabCount: Integer; override;
    function GetTabCaption(AIndex: Integer): string; override;
    function GetStyleTypeKey: string; override;
    procedure DoReorderTabs(AFromIndex, AToIndex: Integer); override;
    procedure RemoveTabData(AIndex: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure AddCap(const S: string);
    procedure CallMouseDown(Btn: TMouseButton; X, Y: Integer; Shift: TShiftState = []);
    procedure CallMouseMove(X, Y: Integer; Shift: TShiftState = []);
    procedure CallMouseUp(Btn: TMouseButton; X, Y: Integer; Shift: TShiftState = []);
    procedure CallMouseLeave;
    procedure CallKeyDown(var Key: Word);
    function  CallDoMouseWheel(WheelDelta, X, Y: Integer): Boolean;
    procedure DoArmFade;
    function  DoAdvance(AMs: Integer): Boolean;
    function  FadeEased: Single;
    { Read-only access to the device-px header-scroll offset, for the scroll
      input tests (the shifted rects are the load-bearing assertion, this is a
      convenience for asserting "scroll moved"). }
    function  HeaderScroll: Integer;
    { Mid-Y of the header band, so drag/hover gestures land inside a header. }
    function  HeaderMidY: Integer;
  end;

  TStripCloseProbe = class
  public
    Count, LastIndex: Integer;
    Veto: Boolean;
    constructor Create;
    procedure Handle(Sender: TObject; AIndex: Integer; var AllowClose: Boolean);
  end;

  { Records OnReorder firings with the reported net from/to indices. }
  TStripReorderProbe = class
  public
    Count, LastFrom, LastTo: Integer;
    constructor Create;
    procedure Handle(Sender: TObject; AFromIndex, AToIndex: Integer);
  end;

  { Pre-switch veto probe (mirrors the old tabcontrol TTabChangingProbe). When
    Veto is set, clears AllowChange so the switch is blocked. }
  TStripChangingProbe = class
  public
    Count, LastNewIndex: Integer;
    Veto: Boolean;
    constructor Create;
    procedure Handle(Sender: TObject; ANewIndex: Integer; var AllowChange: Boolean);
  end;

  { Plain OnChange counter. }
  TStripChangeProbe = class
  public
    Count: Integer;
    procedure Handle(Sender: TObject);
  end;

  TTabStripTest = class(TTestCase)
  private
    FForm: TForm;
    FStrip: TStripAccess;
    procedure Build3(AClosable: Boolean = False);
    procedure BuildOverflow(ACount: Integer = 12; AWidth: Integer = 120);
    function MidOf(AIndex: Integer): Integer;
  protected
    procedure TearDown; override;
  published
    procedure TestHeaderRectsOrderedLeftToRight;
    procedure TestClickSelectsTab;
    procedure TestScrollOverflowAndIntoView;
    procedure TestDropIndexAtMidpoints;
    procedure TestClosableWidensAndCloseRectInside;
    procedure TestClickCloseFiresEventAndRemoves;
    procedure TestCloseVetoKeepsTab;
    procedure TestKeyboardNextPrev;
    procedure TestCrossFadeAnimatesToOne;
    procedure TestAnimationsEnabledDefaultsTrue;
    // (a) DRAG-REORDER gestures (ported from test.tabcontrol.reorder.pas)
    procedure TestDragThresholdIsSmallPositivePxAt96;
    procedure TestDragThresholdScalesWithPPI;
    procedure TestDragPastNeighborMidpointReorders;
    procedure TestDragLeftAdjacentMidpointSwaps;
    procedure TestSubThresholdMoveDoesNotReorder;
    procedure TestPlainPressReleaseSelectsAndDoesNotReorder;
    procedure TestMouseUpClearsDragState;
    procedure TestMouseLeaveClearsDragState;
    procedure TestOnReorderFiresOnceWithNetFromTo;
    // (b) CLOSE-HOVER transitions (ported from test.tabcontrol.closehover.pas)
    procedure TestDefaultHoverCloseIsNone;
    procedure TestNotClosableNeverSetsCloseHover;
    procedure TestMoveOverCloseSetsCloseHover;
    procedure TestMoveOverHeaderTextDoesNotSetCloseHover;
    procedure TestMoveFromCloseToTextClearsCloseHover;
    procedure TestCloseHoverMouseLeaveClears;
    procedure TestCloseHoverTracksDifferentTabs;
    // (c) SCROLL geometry/input (ported from test.tabcontrol.scroll.pas)
    procedure TestOverflowReportsStripWidthAndMaxScroll;
    procedure TestSetHeaderScrollClampsHighAndLow;
    procedure TestAffordanceRectsNonEmptyOnOverflowEmptyWhenFits;
    procedure TestWheelOverHeaderScrolls;
    procedure TestClickArrowsScrollRightThenLeft;
    procedure TestNoOverflowRegressionUnshifted;
    // (d) ONCHANGING veto (ported from test.tabcontrol.pas)
    procedure TestOnChangingVetoBlocksSwitch;
    procedure TestOnChangingAllowsSwitch;
  end;

implementation

constructor TStripAccess.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCaps := TStringList.Create;
  FReorderFrom := -1;
  FReorderTo := -1;
end;

destructor TStripAccess.Destroy;
begin
  FCaps.Free;
  inherited Destroy;
end;

function TStripAccess.GetTabCount: Integer;
begin
  Result := FCaps.Count;
end;

function TStripAccess.GetTabCaption(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FCaps.Count) then
    Result := FCaps[AIndex]
  else
    Result := '';
end;

function TStripAccess.GetStyleTypeKey: string;
begin
  Result := 'TyTabControl';   // a themed selector exists; header parts use TyTab/TyTabClose
end;

procedure TStripAccess.DoReorderTabs(AFromIndex, AToIndex: Integer);
begin
  FReorderFrom := AFromIndex;
  FReorderTo := AToIndex;
  if (AFromIndex >= 0) and (AFromIndex < FCaps.Count) and
     (AToIndex >= 0) and (AToIndex < FCaps.Count) then
    FCaps.Move(AFromIndex, AToIndex);
end;

procedure TStripAccess.RemoveTabData(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < FCaps.Count) then
    FCaps.Delete(AIndex);
  TabsChanged;
end;

procedure TStripAccess.AddCap(const S: string);
begin
  FCaps.Add(S);
  if TabIndex < 0 then TabIndex := 0;
  TabsChanged;
end;

procedure TStripAccess.CallMouseDown(Btn: TMouseButton; X, Y: Integer; Shift: TShiftState);
begin MouseDown(Btn, Shift, X, Y); end;
procedure TStripAccess.CallMouseMove(X, Y: Integer; Shift: TShiftState);
begin MouseMove(Shift, X, Y); end;
procedure TStripAccess.CallMouseUp(Btn: TMouseButton; X, Y: Integer; Shift: TShiftState);
begin MouseUp(Btn, Shift, X, Y); end;
procedure TStripAccess.CallMouseLeave;
begin MouseLeave; end;
procedure TStripAccess.CallKeyDown(var Key: Word);
begin KeyDown(Key, []); end;
function TStripAccess.CallDoMouseWheel(WheelDelta, X, Y: Integer): Boolean;
begin Result := DoMouseWheel([], WheelDelta, Point(X, Y)); end;
procedure TStripAccess.DoArmFade;
begin ArmTabFade; end;
function TStripAccess.DoAdvance(AMs: Integer): Boolean;
begin Result := AdvanceAnimation(AMs); end;
function TStripAccess.FadeEased: Single;
begin Result := GetTabFadeEased; end;
function TStripAccess.HeaderScroll: Integer;
begin Result := FHeaderScroll; end;
function TStripAccess.HeaderMidY: Integer;
var R: TRect;
begin
  R := TyTabHeaderRect(0);
  Result := (R.Top + R.Bottom) div 2;
end;

constructor TStripCloseProbe.Create;
begin
  inherited Create;
  Count := 0; LastIndex := -1; Veto := False;
end;

procedure TStripCloseProbe.Handle(Sender: TObject; AIndex: Integer; var AllowClose: Boolean);
begin
  Inc(Count);
  LastIndex := AIndex;
  if Veto then AllowClose := False;
end;

constructor TStripReorderProbe.Create;
begin
  inherited Create;
  Count := 0; LastFrom := -99; LastTo := -99;
end;

procedure TStripReorderProbe.Handle(Sender: TObject; AFromIndex, AToIndex: Integer);
begin
  Inc(Count);
  LastFrom := AFromIndex;
  LastTo := AToIndex;
end;

constructor TStripChangingProbe.Create;
begin
  inherited Create;
  Count := 0; LastNewIndex := -99; Veto := False;
end;

procedure TStripChangingProbe.Handle(Sender: TObject; ANewIndex: Integer; var AllowChange: Boolean);
begin
  Inc(Count);
  LastNewIndex := ANewIndex;
  if Veto then AllowChange := False;
end;

procedure TStripChangeProbe.Handle(Sender: TObject);
begin
  Inc(Count);
end;

procedure TTabStripTest.Build3(AClosable: Boolean);
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 320, 240);
  FStrip := TStripAccess.Create(FForm);
  FStrip.Parent := FForm;
  FStrip.Font.PixelsPerInch := 96;
  FStrip.SetBounds(0, 0, 300, 200);
  FStrip.TabsClosable := AClosable;
  FStrip.AddCap('Alpha');
  FStrip.AddCap('Beta');
  FStrip.AddCap('Gamma');
end;

procedure TTabStripTest.BuildOverflow(ACount: Integer; AWidth: Integer);
var I: Integer;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 600, 400);
  FStrip := TStripAccess.Create(FForm);
  FStrip.Parent := FForm;
  FStrip.Font.PixelsPerInch := 96;
  FStrip.SetBounds(0, 0, AWidth, 200);
  for I := 1 to ACount do FStrip.AddCap('Tab ' + IntToStr(I));
end;

{ Shifted-header midpoint X for a tab (the same coordinate the drop resolver and
  the drag gesture reason about). }
function TTabStripTest.MidOf(AIndex: Integer): Integer;
var R: TRect;
begin
  R := FStrip.HeaderRectShifted(AIndex);
  Result := (R.Left + R.Right) div 2;
end;

procedure TTabStripTest.TearDown;
begin
  if FForm <> nil then FForm.Free;
  FForm := nil;
end;

procedure TTabStripTest.TestHeaderRectsOrderedLeftToRight;
var R0, R1, R2: TRect;
begin
  Build3;
  R0 := FStrip.TyTabHeaderRect(0);
  R1 := FStrip.TyTabHeaderRect(1);
  R2 := FStrip.TyTabHeaderRect(2);
  AssertTrue('tab0 left of tab1', R0.Left < R1.Left);
  AssertTrue('tab1 left of tab2', R1.Left < R2.Left);
  AssertTrue('tab0 has width', R0.Right > R0.Left);
end;

procedure TTabStripTest.TestClickSelectsTab;
var R1: TRect;
begin
  Build3;
  R1 := FStrip.TyTabHeaderRect(1);
  FStrip.CallMouseDown(mbLeft, (R1.Left + R1.Right) div 2, (R1.Top + R1.Bottom) div 2);
  AssertEquals('click selects tab 1', 1, FStrip.TabIndex);
end;

procedure TTabStripTest.TestScrollOverflowAndIntoView;
var I: Integer;
begin
  FForm := TForm.CreateNew(nil);
  FStrip := TStripAccess.Create(FForm);
  FStrip.Parent := FForm;
  FStrip.Font.PixelsPerInch := 96;
  FStrip.SetBounds(0, 0, 80, 200);   // narrow -> overflow
  for I := 1 to 8 do FStrip.AddCap('Tab ' + IntToStr(I));
  AssertTrue('strip overflows (max scroll > 0)', FStrip.TyMaxHeaderScroll > 0);
  FStrip.ScrollTabIntoView(7);
  AssertTrue('scrolled so last tab is within the visible width',
    FStrip.HeaderRectShifted(7).Right <= FStrip.Width + 1);
end;

procedure TTabStripTest.TestDropIndexAtMidpoints;
var Mid2: Integer;
begin
  Build3;
  Mid2 := (FStrip.TyTabHeaderRect(2).Left + FStrip.TyTabHeaderRect(2).Right) div 2;
  AssertEquals('drop at tab2 midpoint -> index 2', 2, FStrip.TyDropIndexAt(Mid2, 96));
end;

procedure TTabStripTest.TestClosableWidensAndCloseRectInside;
var Hdr, CloseR: TRect;
begin
  Build3(True);
  Hdr := FStrip.TyTabHeaderRect(0);
  CloseR := FStrip.TyTabCloseRect(0);
  AssertTrue('close rect non-empty when closable', CloseR.Right > CloseR.Left);
  AssertTrue('close rect inside its header', (CloseR.Left >= Hdr.Left) and (CloseR.Right <= Hdr.Right));
end;

procedure TTabStripTest.TestClickCloseFiresEventAndRemoves;
var Probe: TStripCloseProbe; C0: TRect;
begin
  Build3(True);
  Probe := TStripCloseProbe.Create;
  try
    FStrip.OnTabClose := @Probe.Handle;
    C0 := FStrip.TyTabCloseRect(0);
    FStrip.CallMouseDown(mbLeft, (C0.Left + C0.Right) div 2, (C0.Top + C0.Bottom) div 2);
    AssertEquals('close fired once', 1, Probe.Count);
    AssertEquals('tab removed', 2, FStrip.TabCount);
  finally
    Probe.Free;
  end;
end;

procedure TTabStripTest.TestCloseVetoKeepsTab;
var Probe: TStripCloseProbe; C0: TRect;
begin
  Build3(True);
  Probe := TStripCloseProbe.Create;
  try
    Probe.Veto := True;
    FStrip.OnTabClose := @Probe.Handle;
    C0 := FStrip.TyTabCloseRect(0);
    FStrip.CallMouseDown(mbLeft, (C0.Left + C0.Right) div 2, (C0.Top + C0.Bottom) div 2);
    AssertEquals('close fired', 1, Probe.Count);
    AssertEquals('vetoed -> tab kept', 3, FStrip.TabCount);
  finally
    Probe.Free;
  end;
end;

procedure TTabStripTest.TestKeyboardNextPrev;
var K: Word;
begin
  Build3;
  FStrip.TabIndex := 0;
  K := VK_RIGHT; FStrip.CallKeyDown(K);
  AssertEquals('VK_RIGHT advances to next tab', 1, FStrip.TabIndex);
  K := VK_LEFT; FStrip.CallKeyDown(K);
  AssertEquals('VK_LEFT goes to previous tab', 0, FStrip.TabIndex);
end;

procedure TTabStripTest.TestCrossFadeAnimatesToOne;
begin
  Build3;
  FStrip.DoArmFade;
  FStrip.DoAdvance(1000);   // large step -> fully eased
  AssertTrue('cross-fade eased toward 1', FStrip.FadeEased > 0.9);
end;

procedure TTabStripTest.TestAnimationsEnabledDefaultsTrue;
begin
  Build3;
  AssertTrue('AnimationsEnabled defaults True', FStrip.AnimationsEnabled);
end;

{ ===== (a) DRAG-REORDER gestures ============================================ }

{ The drag threshold at 96 PPI is a small positive number of device px
  (Scale(6) == MulDiv(6,96,96) == 6). }
procedure TTabStripTest.TestDragThresholdIsSmallPositivePxAt96;
begin
  Build3;
  AssertEquals('drag threshold at 96 ppi', 6, FStrip.TyDragThresholdPx(96));
end;

{ The threshold scales linearly with PPI (192 -> 12, 144 -> 9). }
procedure TTabStripTest.TestDragThresholdScalesWithPPI;
begin
  Build3;
  AssertEquals('drag threshold at 192 ppi', 12, FStrip.TyDragThresholdPx(192));
  AssertEquals('drag threshold at 144 ppi', 9,  FStrip.TyDragThresholdPx(144));
end;

{ Press on header 0, then move past header 1's midpoint with ssLeft held, with
  release. The index-0 tab reseats to the last index:
  [Alpha,Beta,Gamma] -> [Beta,Gamma,Alpha]. }
procedure TTabStripTest.TestDragPastNeighborMidpointReorders;
var
  Cap0, Cap1, Cap2: string;
  Y: Integer;
begin
  Build3;
  Cap0 := FStrip.TabCaption(0); // Alpha
  Cap1 := FStrip.TabCaption(1); // Beta
  Cap2 := FStrip.TabCaption(2); // Gamma
  Y := FStrip.HeaderMidY;

  FStrip.CallMouseDown(mbLeft, MidOf(0), Y, [ssLeft]);
  FStrip.CallMouseMove(MidOf(1) + 1, Y, [ssLeft]);
  FStrip.CallMouseUp(mbLeft, MidOf(1) + 1, Y, [ssLeft]);

  AssertEquals('caption[0] now old caption[1]', Cap1, FStrip.TabCaption(0));
  AssertEquals('caption[1] now old caption[2]', Cap2, FStrip.TabCaption(1));
  AssertEquals('caption[2] now old caption[0]', Cap0, FStrip.TabCaption(2));
end;

{ Dragging the last tab leftward just before header 1's midpoint is a clean
  adjacent move: [Alpha,Beta,Gamma] -> [Alpha,Gamma,Beta]. Tab 0 is untouched. }
procedure TTabStripTest.TestDragLeftAdjacentMidpointSwaps;
var
  Cap0, Cap1, Cap2: string;
  Y: Integer;
begin
  Build3;
  Cap0 := FStrip.TabCaption(0);
  Cap1 := FStrip.TabCaption(1);
  Cap2 := FStrip.TabCaption(2);
  Y := FStrip.HeaderMidY;

  FStrip.CallMouseDown(mbLeft, MidOf(2), Y, [ssLeft]);
  FStrip.CallMouseMove(MidOf(1) - 1, Y, [ssLeft]);
  FStrip.CallMouseUp(mbLeft, MidOf(1) - 1, Y, [ssLeft]);

  AssertEquals('caption[0] unchanged', Cap0, FStrip.TabCaption(0));
  AssertEquals('caption[1] now old caption[2]', Cap2, FStrip.TabCaption(1));
  AssertEquals('caption[2] now old caption[1]', Cap1, FStrip.TabCaption(2));
end;

{ A sub-threshold move (|dx| < TyDragThresholdPx) does NOT reorder. }
procedure TTabStripTest.TestSubThresholdMoveDoesNotReorder;
var
  Cap0, Cap1: string;
  Y, X0: Integer;
begin
  Build3;
  Cap0 := FStrip.TabCaption(0);
  Cap1 := FStrip.TabCaption(1);
  Y := FStrip.HeaderMidY;
  X0 := MidOf(0);

  FStrip.CallMouseDown(mbLeft, X0, Y, [ssLeft]);
  FStrip.CallMouseMove(X0 + (FStrip.TyDragThresholdPx(96) - 1), Y, [ssLeft]);
  FStrip.CallMouseUp(mbLeft, X0 + (FStrip.TyDragThresholdPx(96) - 1), Y, [ssLeft]);

  AssertEquals('caption[0] unchanged', Cap0, FStrip.TabCaption(0));
  AssertEquals('caption[1] unchanged', Cap1, FStrip.TabCaption(1));
end;

{ A plain press + release (no move) still SELECTS the pressed tab and does not
  reorder. }
procedure TTabStripTest.TestPlainPressReleaseSelectsAndDoesNotReorder;
var
  Cap0, Cap1, Cap2: string;
  Y: Integer;
begin
  Build3;
  Cap0 := FStrip.TabCaption(0);
  Cap1 := FStrip.TabCaption(1);
  Cap2 := FStrip.TabCaption(2);
  Y := FStrip.HeaderMidY;

  FStrip.CallMouseDown(mbLeft, MidOf(2), Y, [ssLeft]);
  FStrip.CallMouseUp(mbLeft, MidOf(2), Y, [ssLeft]);

  AssertEquals('plain press selects pressed tab', 2, FStrip.TabIndex);
  AssertEquals('caption[0] unchanged', Cap0, FStrip.TabCaption(0));
  AssertEquals('caption[1] unchanged', Cap1, FStrip.TabCaption(1));
  AssertEquals('caption[2] unchanged', Cap2, FStrip.TabCaption(2));
end;

{ MouseUp clears the drag state: a subsequent ssLeft move (no fresh press) must
  NOT reorder. }
procedure TTabStripTest.TestMouseUpClearsDragState;
var
  Cap0, Cap1: string;
  Y: Integer;
begin
  Build3;
  Y := FStrip.HeaderMidY;

  FStrip.CallMouseDown(mbLeft, MidOf(0), Y, [ssLeft]);
  FStrip.CallMouseUp(mbLeft, MidOf(0), Y, [ssLeft]);

  Cap0 := FStrip.TabCaption(0);
  Cap1 := FStrip.TabCaption(1);
  FStrip.CallMouseMove(MidOf(2), Y, [ssLeft]);

  AssertEquals('caption[0] unchanged after release+move', Cap0, FStrip.TabCaption(0));
  AssertEquals('caption[1] unchanged after release+move', Cap1, FStrip.TabCaption(1));
end;

{ MouseLeave clears the drag state too. }
procedure TTabStripTest.TestMouseLeaveClearsDragState;
var
  Cap0, Cap1: string;
  Y: Integer;
begin
  Build3;
  Y := FStrip.HeaderMidY;

  FStrip.CallMouseDown(mbLeft, MidOf(0), Y, [ssLeft]);
  FStrip.CallMouseLeave;

  Cap0 := FStrip.TabCaption(0);
  Cap1 := FStrip.TabCaption(1);
  FStrip.CallMouseMove(MidOf(2), Y, [ssLeft]);

  AssertEquals('caption[0] unchanged after leave+move', Cap0, FStrip.TabCaption(0));
  AssertEquals('caption[1] unchanged after leave+move', Cap1, FStrip.TabCaption(1));
end;

{ A committed drag-reorder fires OnReorder exactly once with the net from/to.
  Pressing header 0 and dragging past header 1's midpoint reseats tab 0 to the
  last index (2). A plain press+release fires nothing. }
procedure TTabStripTest.TestOnReorderFiresOnceWithNetFromTo;
var
  Probe: TStripReorderProbe;
  Y: Integer;
begin
  Build3;
  Y := FStrip.HeaderMidY;
  Probe := TStripReorderProbe.Create;
  try
    FStrip.OnReorder := @Probe.Handle;

    { Plain press + release on header 2 must not reorder -> no OnReorder. }
    FStrip.CallMouseDown(mbLeft, MidOf(2), Y, [ssLeft]);
    FStrip.CallMouseUp(mbLeft, MidOf(2), Y, [ssLeft]);
    AssertEquals('plain click does not fire OnReorder', 0, Probe.Count);

    { Drag header 0 past header 1's midpoint -> reseats to index 2. }
    FStrip.CallMouseDown(mbLeft, MidOf(0), Y, [ssLeft]);
    FStrip.CallMouseMove(MidOf(1) + 1, Y, [ssLeft]);
    FStrip.CallMouseUp(mbLeft, MidOf(1) + 1, Y, [ssLeft]);

    AssertEquals('OnReorder fired once', 1, Probe.Count);
    AssertEquals('reorder from index 0', 0, Probe.LastFrom);
    AssertEquals('reorder to index 2', 2, Probe.LastTo);
  finally
    Probe.Free;
  end;
end;

{ ===== (b) CLOSE-HOVER transitions ========================================== }

{ A freshly built control reports no close-hover. }
procedure TTabStripTest.TestDefaultHoverCloseIsNone;
begin
  Build3(True);
  AssertEquals('default close-hover is -1', -1, FStrip.TyTabHoverClose);
end;

{ When not closable, hovering where the x would sit never arms close-hover. }
procedure TTabStripTest.TestNotClosableNeverSetsCloseHover;
var
  H: TRect;
  X, Y: Integer;
begin
  Build3(False);
  H := FStrip.TyTabHeaderRect(1);
  X := H.Right - 4;
  Y := (H.Top + H.Bottom) div 2;
  FStrip.CallMouseMove(X, Y);
  AssertEquals('no close-hover when not closable', -1, FStrip.TyTabHoverClose);
end;

{ Moving onto a tab's x arms close-hover for that index. }
procedure TTabStripTest.TestMoveOverCloseSetsCloseHover;
var
  C: TRect;
begin
  Build3(True);
  C := FStrip.TyTabCloseRect(1);
  AssertTrue('close rect exists', C.Right > C.Left);
  FStrip.CallMouseMove((C.Left + C.Right) div 2, (C.Top + C.Bottom) div 2);
  AssertEquals('close-hover armed for tab 1', 1, FStrip.TyTabHoverClose);
end;

{ Moving onto the caption text (left of the x) sets tab hover but NOT close-hover. }
procedure TTabStripTest.TestMoveOverHeaderTextDoesNotSetCloseHover;
var
  H, C: TRect;
  HX, HY: Integer;
begin
  Build3(True);
  H := FStrip.TyTabHeaderRect(1);
  C := FStrip.TyTabCloseRect(1);
  HX := (H.Left + C.Left) div 2;   // midway between header left and close left
  HY := (H.Top + H.Bottom) div 2;
  FStrip.CallMouseMove(HX, HY);
  AssertEquals('no close-hover over caption text', -1, FStrip.TyTabHoverClose);
end;

{ Sliding from the x to the caption text clears the close-hover. }
procedure TTabStripTest.TestMoveFromCloseToTextClearsCloseHover;
var
  H, C: TRect;
begin
  Build3(True);
  C := FStrip.TyTabCloseRect(1);
  FStrip.CallMouseMove((C.Left + C.Right) div 2, (C.Top + C.Bottom) div 2);
  AssertEquals('armed first', 1, FStrip.TyTabHoverClose);
  H := FStrip.TyTabHeaderRect(1);
  FStrip.CallMouseMove((H.Left + C.Left) div 2, (H.Top + H.Bottom) div 2);
  AssertEquals('cleared after sliding to text', -1, FStrip.TyTabHoverClose);
end;

{ Leaving the control clears the close-hover. }
procedure TTabStripTest.TestCloseHoverMouseLeaveClears;
var
  C: TRect;
begin
  Build3(True);
  C := FStrip.TyTabCloseRect(1);
  FStrip.CallMouseMove((C.Left + C.Right) div 2, (C.Top + C.Bottom) div 2);
  AssertEquals('armed first', 1, FStrip.TyTabHoverClose);
  FStrip.CallMouseLeave;
  AssertEquals('cleared on leave', -1, FStrip.TyTabHoverClose);
end;

{ Close-hover follows the pointer between different tabs' close buttons. }
procedure TTabStripTest.TestCloseHoverTracksDifferentTabs;
var
  C0, C2: TRect;
begin
  Build3(True);
  C0 := FStrip.TyTabCloseRect(0);
  C2 := FStrip.TyTabCloseRect(2);
  FStrip.CallMouseMove((C0.Left + C0.Right) div 2, (C0.Top + C0.Bottom) div 2);
  AssertEquals('over tab 0 close', 0, FStrip.TyTabHoverClose);
  FStrip.CallMouseMove((C2.Left + C2.Right) div 2, (C2.Top + C2.Bottom) div 2);
  AssertEquals('over tab 2 close', 2, FStrip.TyTabHoverClose);
end;

{ ===== (c) SCROLL geometry/input =========================================== }

{ Many tabs in a narrow control overflow: strip width exceeds the control width
  and there is a positive maximum scroll. }
procedure TTabStripTest.TestOverflowReportsStripWidthAndMaxScroll;
begin
  BuildOverflow(12, 120);
  AssertTrue('strip wider than control width', FStrip.TyHeaderStripWidth > 120);
  AssertTrue('positive max header scroll', FStrip.TyMaxHeaderScroll > 0);
end;

{ SetHeaderScroll clamps high values to TyMaxHeaderScroll and negatives to 0.
  The clamped value is observable through the shift of header 0. }
procedure TTabStripTest.TestSetHeaderScrollClampsHighAndLow;
var
  MaxScroll, Base0: Integer;
begin
  BuildOverflow(12, 120);
  MaxScroll := FStrip.TyMaxHeaderScroll;
  Base0 := FStrip.TyTabHeaderRect(0).Left; // unshifted

  FStrip.SetHeaderScroll(99999);
  AssertEquals('clamped high to max scroll',
    Base0 - MaxScroll, FStrip.HeaderRectShifted(0).Left);

  FStrip.SetHeaderScroll(-50);
  AssertEquals('clamped low to zero scroll',
    Base0, FStrip.HeaderRectShifted(0).Left);
end;

{ Affordance rects are non-empty when overflowing and (0,0,0,0) when content fits. }
procedure TTabStripTest.TestAffordanceRectsNonEmptyOnOverflowEmptyWhenFits;
var
  LR, RR: TRect;
begin
  BuildOverflow(12, 120);
  LR := FStrip.TyTabScrollLeftRect;
  RR := FStrip.TyTabScrollRightRect;
  AssertTrue('left arrow rect non-empty on overflow',
    (LR.Right > LR.Left) and (LR.Bottom > LR.Top));
  AssertTrue('right arrow rect non-empty on overflow',
    (RR.Right > RR.Left) and (RR.Bottom > RR.Top));

  { Fits: roomy control with few short tabs. }
  FForm.Free;
  FForm := nil;
  BuildOverflow(2, 300);   // 2 short tabs in 300px do not overflow
  LR := FStrip.TyTabScrollLeftRect;
  RR := FStrip.TyTabScrollRightRect;
  AssertTrue('left arrow rect empty when fits',
    (LR.Left = 0) and (LR.Top = 0) and (LR.Right = 0) and (LR.Bottom = 0));
  AssertTrue('right arrow rect empty when fits',
    (RR.Left = 0) and (RR.Top = 0) and (RR.Right = 0) and (RR.Bottom = 0));
end;

{ Mouse-wheel over the header band scrolls the overflowing strip: wheel-down
  increases the offset (and shifts the rects left), wheel-up decreases it; the
  event is consumed both ways. }
procedure TTabStripTest.TestWheelOverHeaderScrolls;
var
  Left0Before, Left0AfterDown: Integer;
  Res: Boolean;
begin
  BuildOverflow(12, 120);
  AssertTrue('precondition: overflow', FStrip.TyMaxHeaderScroll > 0);
  AssertEquals('precondition: scroll starts at 0', 0, FStrip.HeaderScroll);
  Left0Before := FStrip.HeaderRectShifted(0).Left;

  Res := FStrip.CallDoMouseWheel(-120, 10, 5);
  AssertTrue('wheel-down over header consumed', Res);
  AssertTrue('wheel-down increases header scroll', FStrip.HeaderScroll > 0);
  Left0AfterDown := FStrip.HeaderRectShifted(0).Left;
  AssertTrue('wheel-down shifts header 0 left', Left0AfterDown < Left0Before);

  Res := FStrip.CallDoMouseWheel(120, 10, 5);
  AssertTrue('wheel-up over header consumed', Res);
  AssertTrue('wheel-up shifts header 0 back right',
    FStrip.HeaderRectShifted(0).Left > Left0AfterDown);
end;

{ Clicking the right affordance arrow increases the scroll; clicking the left
  arrow afterwards decreases it. }
procedure TTabStripTest.TestClickArrowsScrollRightThenLeft;
var
  RR, LR: TRect;
  AfterRight: Integer;
begin
  BuildOverflow(12, 120);
  AssertTrue('precondition: overflow', FStrip.TyMaxHeaderScroll > 0);

  RR := FStrip.TyTabScrollRightRect;
  FStrip.CallMouseDown(mbLeft, (RR.Left + RR.Right) div 2, (RR.Top + RR.Bottom) div 2);
  AfterRight := FStrip.HeaderScroll;
  AssertTrue('click right arrow increases scroll', AfterRight > 0);

  LR := FStrip.TyTabScrollLeftRect;
  FStrip.CallMouseDown(mbLeft, (LR.Left + LR.Right) div 2, (LR.Top + LR.Bottom) div 2);
  AssertTrue('click left arrow decreases scroll', FStrip.HeaderScroll < AfterRight);
end;

{ REGRESSION: two short tabs in a wide control do not overflow -> zero max
  scroll, no affordance rects, and the shifted rect equals the unshifted rect. }
procedure TTabStripTest.TestNoOverflowRegressionUnshifted;
var
  I: Integer;
  A, B, LR, RR: TRect;
begin
  BuildOverflow(2, 300);
  AssertEquals('no max scroll when content fits', 0, FStrip.TyMaxHeaderScroll);
  LR := FStrip.TyTabScrollLeftRect;
  RR := FStrip.TyTabScrollRightRect;
  AssertTrue('no left affordance when content fits',
    (LR.Right = LR.Left) and (LR.Bottom = LR.Top));
  AssertTrue('no right affordance when content fits',
    (RR.Right = RR.Left) and (RR.Bottom = RR.Top));
  for I := 0 to FStrip.TabCount - 1 do
  begin
    A := FStrip.HeaderRectShifted(I);
    B := FStrip.TyTabHeaderRect(I);
    AssertTrue('shifted rect equals unshifted rect (offset 0) at ' + IntToStr(I),
      (A.Left = B.Left) and (A.Top = B.Top) and
      (A.Right = B.Right) and (A.Bottom = B.Bottom));
  end;
end;

{ ===== (d) ONCHANGING veto ================================================= }

{ A handler that clears AllowChange prevents the switch: TabIndex stays put and
  OnChange does NOT fire. OnChanging is consulted with the proposed (clamped)
  new index. }
procedure TTabStripTest.TestOnChangingVetoBlocksSwitch;
var
  Changing: TStripChangingProbe;
  Changed: TStripChangeProbe;
begin
  Build3;
  FStrip.TabIndex := 0;
  AssertEquals('start on tab 0', 0, FStrip.TabIndex);

  Changing := TStripChangingProbe.Create;
  Changed := TStripChangeProbe.Create;
  try
    Changing.Veto := True;
    FStrip.OnChanging := @Changing.Handle;
    FStrip.OnChange := @Changed.Handle;

    FStrip.TabIndex := 1;

    AssertEquals('OnChanging consulted once', 1, Changing.Count);
    AssertEquals('OnChanging got proposed new index 1', 1, Changing.LastNewIndex);
    AssertEquals('vetoed: TabIndex unchanged', 0, FStrip.TabIndex);
    AssertEquals('vetoed: OnChange NOT fired', 0, Changed.Count);
  finally
    Changed.Free;
    Changing.Free;
  end;
end;

{ When the handler leaves AllowChange True the switch proceeds and OnChange
  fires afterward. }
procedure TTabStripTest.TestOnChangingAllowsSwitch;
var
  Changing: TStripChangingProbe;
  Changed: TStripChangeProbe;
begin
  Build3;
  FStrip.TabIndex := 0;

  Changing := TStripChangingProbe.Create;
  Changed := TStripChangeProbe.Create;
  try
    Changing.Veto := False;
    FStrip.OnChanging := @Changing.Handle;
    FStrip.OnChange := @Changed.Handle;

    FStrip.TabIndex := 1;

    AssertEquals('OnChanging consulted once', 1, Changing.Count);
    AssertEquals('OnChanging got new index 1', 1, Changing.LastNewIndex);
    AssertEquals('allowed: TabIndex switched to 1', 1, FStrip.TabIndex);
    AssertEquals('allowed: OnChange fired once', 1, Changed.Count);
  finally
    Changed.Free;
    Changing.Free;
  end;
end;

initialization
  RegisterTest(TTabStripTest);
end.
