unit test.windowframe;
{ #80: TTyForm's window frame on macOS (spec 2026-10-14) -- a titled window with a transparent,
  full-size title bar instead of a borderless one, so the system draws the corners, the shadow
  and the traffic lights, and owns the edge resize, the move, the zoom and the double-click.

  Everything here runs on Windows. What the platform ANSWERS comes from the PlatformWS test seam
  (TyTestPlatform), set to what macOS answers; what the title bar, the chrome engine and the form
  DO with those answers is their real code. The seam only ever stands in for a platform call. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, ExtCtrls, Menus, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.PlatformWS, tyControls.Form,
  tyControls.WindowEffects;

type
  TFrameFormAccess = class(TTyForm)
  public
    function Engine: TTyChromeEngine;
    procedure InjectResizing(AState: TWindowState);
    procedure InjectDoShow;
    procedure InjectFormMouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure InjectFormMouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
  end;

  TFrameBarAccess = class(TTyTitleBar)
  public
    procedure CallLayoutButtons;
    procedure CallAdjustClientRect(var ARect: TRect);
    procedure InjectDblClick;
  end;

  TFrameButtonAccess = class(TTyCaptionButton)
  public
    procedure InjectClick;
  end;

  { The seam answering the way macOS does; every macOS test starts here. }
  TMacSeamCase = class(TTestCase)
  protected
    procedure SetUp; override;
    procedure TearDown; override;
    { A TTyForm, 800 x 600, with an associated title bar along its top -- armed, as at run time. }
    function NewMacForm: TFrameFormAccess;
  end;

  TPlatformFrameFacadeTest = class(TTestCase)
  protected
    procedure TearDown; override;
  published
    procedure TestWindowsAnswersWithTheSeamOff;
    procedure TestTheSeamAnswersAndRecordsWhileActive;
    procedure TestResetGoesBackToThePlatform;
  end;

  TSystemCaptionLayoutTest = class(TTestCase)
  published
    procedure TestTheGroupSitsOneInsetInAndCentred;
    procedure TestTheContentZoneStartsAfterTheSlot;
    procedure TestAThemeMarginWiderThanTheInsetWins;
    procedure TestRightToLeftMirrorsTheSlot;
    procedure TestABarShorterThanTheButtonsKeepsThemOnIt;
    procedure TestNoSlotLeavesTheLayoutAlone;
    procedure TestTheIconComesAfterTheSlot;
  end;

  TMacTitleBarTest = class(TMacSeamCase)
  published
    procedure TestTheDefaultIsOnAndNotStreamed;
    procedure TestSystemButtonsStandInForOurs;
    procedure TestTheSlotPushesTheContentZone;
    procedure TestSwitchingOffBringsOurButtonsBack;
    procedure TestPlacementIsInFormCoordinates;
    procedure TestRightToLeftPutsTheSlotOnTheRight;
    procedure TestOffMacNothingChanges;
    procedure TestABarWithoutATyFormKeepsItsButtons;
    procedure TestABarTakenOffTheFormGetsItsButtonsBack;
    procedure TestACentredCaptionStaysClearOfTheSlot;
  end;

  { LCL's align pass only runs on a real window, so this one is shown. }
  TMacTitleBarAlignTest = class(TMacSeamCase)
  published
    procedure TestLeftAlignedChildrenStartAfterTheSlot;
  end;

  TMacWindowFrameTest = class(TMacSeamCase)
  published
    procedure TestTheFrameIsAppliedOnShow;
    procedure TestBorderIconsGreyTheSystemButtons;
    procedure TestTheBarsSwitchesGreyThemToo;
    procedure TestAFixedWindowIsNotResizable;
    procedure TestACodeCreatedBarGetsAnEnabledFrame;
    procedure TestARolledUpWindowIsNotResizable;
    procedure TestSwitchingTrafficLightsOffHidesTheSystemButtons;
    procedure TestNoTitleBarNoSystemButtons;
    procedure TestTakingTheBarAwayHidesThem;
    procedure TestFreeingTheBarHidesThem;
    procedure TestTheDesignSurfaceGetsNoFrame;
  end;

  TMacChromeEngineTest = class(TMacSeamCase)
  published
    procedure TestTheEdgesAreTheSystemsToResize;
    procedure TestThePressDoesNotStartTheMove;
    procedure TestADragPastTheThresholdIsHandedToTheSystem;
    procedure TestAMoveThatUnzoomsIsHeardBack;
    procedure TestMaximizeIsTheSystemZoom;
    procedure TestRestoreUnzooms;
    procedure TestDoubleClickFollowsTheSystemSetting;
    procedure TestCaptionActionStillDecides;
    procedure TestOurMinimizeSendsThisWindowToTheDock;
    procedure TestAMaximizedWindowStateIsLeftForTheSystem;
    procedure TestTheWindowMenuGoesToTheSystemToo;
  end;

  TWindowAppearanceTest = class(TTestCase)
  protected
    procedure TearDown; override;
  published
    procedure TestDarkFollowsASolidBackground;
    procedure TestDarkFollowsAGradientsEnds;
    procedure TestAnImageGoesByItsTextColour;
    procedure TestNothingToGoByIsLight;
    procedure TestTheAppearanceReachesThePlatform;
    procedure TestAThemeSwitchFlipsIt;
  end;

implementation

{ Same lazy widgetset bootstrap as test.form's (the console runner registers no window classes,
  so CreateHandle fails with error 1407 until the application is initialised). }
var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

procedure AssertRectEq(const AMsg: string; const AWant, AGot: TRect);
begin
  TAssert.AssertTrue(Format('%s: want (%d,%d,%d,%d) got (%d,%d,%d,%d)',
    [AMsg, AWant.Left, AWant.Top, AWant.Right, AWant.Bottom,
     AGot.Left, AGot.Top, AGot.Right, AGot.Bottom]),
    (AWant.Left = AGot.Left) and (AWant.Top = AGot.Top)
    and (AWant.Right = AGot.Right) and (AWant.Bottom = AGot.Bottom));
end;

{ What the streaming system writes for AComp, as .lfm text. }
function ComponentText(AComp: TComponent): string;
var bin, txt: TMemoryStream;
begin
  bin := TMemoryStream.Create;
  txt := TMemoryStream.Create;
  try
    bin.WriteComponent(AComp);
    bin.Position := 0;
    ObjectBinaryToText(bin, txt);
    SetString(Result, PChar(txt.Memory), txt.Size);
  finally
    bin.Free;
    txt.Free;
  end;
end;

{ TFrameFormAccess }

function TFrameFormAccess.Engine: TTyChromeEngine; begin Result := FEngine; end;
procedure TFrameFormAccess.InjectResizing(AState: TWindowState); begin Resizing(AState); end;
procedure TFrameFormAccess.InjectDoShow; begin DoShow; end;

procedure TFrameFormAccess.InjectFormMouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin MouseDown(Button, Shift, X, Y); end;

procedure TFrameFormAccess.InjectFormMouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin MouseUp(Button, Shift, X, Y); end;

{ TFrameBarAccess }

procedure TFrameBarAccess.CallLayoutButtons; begin LayoutButtons; end;
procedure TFrameBarAccess.CallAdjustClientRect(var ARect: TRect); begin AdjustClientRect(ARect); end;
procedure TFrameBarAccess.InjectDblClick; begin DblClick; end;

{ TFrameButtonAccess }

procedure TFrameButtonAccess.InjectClick; begin Click; end;

{ TMacSeamCase }

const
  MacTraits: TTyFrameTraits = [ftrModalMove, ftrNativeResize, ftrNativeZoom, ftrSystemButtons];

procedure TMacSeamCase.SetUp;
begin
  TyResetTestPlatform;
  TyTestPlatform.Active := True;
  TyTestPlatform.Traits := MacTraits;
  { What macOS 11..15 report: three 14 x 16 pt button frames 6 pt apart, 7 pt in from the edge. }
  TyTestPlatform.ButtonGroup.Size.cx := 54;
  TyTestPlatform.ButtonGroup.Size.cy := 16;
  TyTestPlatform.ButtonGroup.Inset := 7;
  TyTestPlatform.DoubleClick := tdcMaximize;
  TyTestPlatform.SystemMoveStarts := True;
end;

procedure TMacSeamCase.TearDown;
begin
  TyResetTestPlatform;
end;

function TMacSeamCase.NewMacForm: TFrameFormAccess;
var bar: TTyCustomTitleBar;
begin
  Result := TFrameFormAccess.CreateNew(nil);
  Result.SetBounds(0, 0, 800, 600);
  bar := TTyTitleBar.Create(Result);   // owned by the form: its Notification associates and arms it
  bar.Parent := Result;
  bar.SetBounds(0, 0, 800, bar.Height);
end;

{ TPlatformFrameFacadeTest }

procedure TPlatformFrameFacadeTest.TearDown;
begin
  TyResetTestPlatform;
end;

procedure TPlatformFrameFacadeTest.TestWindowsAnswersWithTheSeamOff;
var F: TForm;
begin
  TyResetTestPlatform;
  {$IFDEF LCLWin32}
  { Exactly what the IFDEFs these traits replace used to say: the caption move is a modal loop
    started past a threshold, and WS_THICKFRAME owns the edge resize. }
  AssertTrue('Win32 traits', TyFrameTraits = [ftrModalMove, ftrNativeResize]);
  {$ENDIF}
  AssertEquals('a double-click maximizes', Ord(tdcMaximize), Ord(TyTitleDoubleClickAction));
  F := TForm.CreateNew(nil);
  try
    AssertEquals('no system buttons', 0, TySystemButtonGroup(F).Size.cx);
    AssertFalse('no system zoom', TyIsWindowZoomed(F));
    AssertFalse('no platform minimize', TyMinimizeWindow(F));
    TyApplyWindowFrame(F, Default(TTyWindowFrame));
    TyPlaceSystemButtons(F, Rect(0, 0, 10, 10));
    TySetWindowZoomed(F, True);
    TyApplyWindowAppearance(F, True, True);
    AssertFalse('the inert calls did not create a handle', F.HandleAllocated);
  finally
    F.Free;
  end;
end;

procedure TPlatformFrameFacadeTest.TestTheSeamAnswersAndRecordsWhileActive;
var
  F: TForm;
  fr: TTyWindowFrame;
begin
  TyResetTestPlatform;
  TyTestPlatform.Active := True;
  TyTestPlatform.Traits := [ftrNativeZoom];
  TyTestPlatform.ButtonGroup.Size.cx := 54;
  TyTestPlatform.DoubleClick := tdcNone;
  TyTestPlatform.SystemMoveStarts := True;
  F := TForm.CreateNew(nil);
  try
    AssertTrue('traits', TyFrameTraits = [ftrNativeZoom]);
    AssertEquals('group', 54, TySystemButtonGroup(F).Size.cx);
    AssertEquals('double-click', Ord(tdcNone), Ord(TyTitleDoubleClickAction));
    fr := Default(TTyWindowFrame);
    fr.CanMinimize := True;
    TyApplyWindowFrame(F, fr);
    AssertEquals('frame recorded', 1, TyTestPlatform.FrameApplies);
    AssertTrue('with its flags', TyTestPlatform.LastFrame.CanMinimize);
    AssertTrue('for its form', TyTestPlatform.LastFrameForm = F);
    TyPlaceSystemButtons(F, Rect(7, 12, 61, 28));
    AssertEquals('placement recorded', 1, TyTestPlatform.Placements);
    AssertTrue('for its form', TyTestPlatform.LastPlacementForm = F);
    AssertRectEq('at its rect', Rect(7, 12, 61, 28), TyTestPlatform.LastPlacement);
    TySetWindowZoomed(F, True);
    AssertTrue('zoom recorded and answered', TyIsWindowZoomed(F));
    AssertEquals('one zoom request', 1, TyTestPlatform.ZoomRequests);
    AssertTrue('minimize handled', TyMinimizeWindow(F));
    AssertEquals('one minimize', 1, TyTestPlatform.Minimizes);
    TyApplyWindowAppearance(F, False, True);
    AssertEquals('appearance recorded', 1, TyTestPlatform.AppearanceApplies);
    AssertFalse('shadow', TyTestPlatform.LastShadow);
    AssertTrue('dark', TyTestPlatform.LastDark);
    { Without ftrModalMove the system move is not a modal loop, so the press may start it. }
    AssertTrue('a non-modal move starts on the press', TyStartSystemMove(F, False));
    TyTestPlatform.Traits := [ftrModalMove];
    AssertFalse('a modal one never does', TyStartSystemMove(F, False));
    AssertTrue('only past the threshold', TyStartSystemMove(F, True));
    AssertEquals('two moves started', 2, TyTestPlatform.SystemMoves);
  finally
    F.Free;
  end;
end;

procedure TPlatformFrameFacadeTest.TestResetGoesBackToThePlatform;
begin
  TyTestPlatform.Active := True;
  TyTestPlatform.Traits := [ftrSystemButtons];
  TyTestPlatform.FrameApplies := 3;
  TyResetTestPlatform;
  AssertFalse('inactive', TyTestPlatform.Active);
  AssertEquals('recorders cleared', 0, TyTestPlatform.FrameApplies);
  AssertFalse('the platform answers again', ftrSystemButtons in TyFrameTraits);
end;

{ TSystemCaptionLayoutTest -- an 800 x 40 bar, three 46-px buttons of ours, an 8-px lead pad,
  and a 54 x 16 system group whose own title bar keeps it 7 px in. }

function SlotLay(AMarginX: Integer; ARtl: Boolean; ASysW: Integer = 54; ABarH: Integer = 40): TTyCaptionLayout;
begin
  Result := TySystemCaptionLayoutFor(True, True, True, 800, ABarH, 46, AMarginX, 0, 0, 8,
    ASysW, 16, 7, ARtl);
end;

procedure TSystemCaptionLayoutTest.TestTheGroupSitsOneInsetInAndCentred;
begin
  AssertRectEq('7 in from the edge, centred in 40', Rect(7, 12, 61, 28), SlotLay(0, False).SystemButtons);
end;

procedure TSystemCaptionLayoutTest.TestTheContentZoneStartsAfterTheSlot;
var l: TTyCaptionLayout;
begin
  l := SlotLay(0, False);
  AssertEquals('inset + group + inset + the lead pad', 7 + 54 + 7 + 8, l.Content.Left);
  AssertEquals('the far end is still our cluster''s', 800 - 3 * 46, l.Content.Right);
  AssertRectEq('and the cluster has not moved', Rect(754, 0, 800, 40), l.CloseBtn);
end;

procedure TSystemCaptionLayoutTest.TestAThemeMarginWiderThanTheInsetWins;
var l: TTyCaptionLayout;
begin
  l := SlotLay(10, False);
  AssertEquals('margin 10 beats inset 7', 10, l.SystemButtons.Left);
  AssertEquals('on both sides of the group', 10 + 54 + 10 + 8, l.Content.Left);
  l := SlotLay(3, False);
  AssertEquals('margin 3: the inset is the floor', 7, l.SystemButtons.Left);
  AssertEquals('both sides again', 7 + 54 + 7 + 8, l.Content.Left);
end;

procedure TSystemCaptionLayoutTest.TestRightToLeftMirrorsTheSlot;
var l: TTyCaptionLayout;
begin
  l := SlotLay(0, True);
  AssertRectEq('the group at the right edge', Rect(800 - 61, 12, 800 - 7, 28), l.SystemButtons);
  AssertEquals('the content zone ends before it', 800 - (7 + 54 + 7 + 8), l.Content.Right);
  AssertEquals('and starts after our mirrored cluster', 3 * 46, l.Content.Left);
end;

procedure TSystemCaptionLayoutTest.TestABarShorterThanTheButtonsKeepsThemOnIt;
begin
  AssertEquals('the top clamps to the bar', 0, SlotLay(0, False, 54, 12).SystemButtons.Top);
end;

procedure TSystemCaptionLayoutTest.TestNoSlotLeavesTheLayoutAlone;
var l: TTyCaptionLayout;
begin
  { A zero-wide group ignores the height and the inset that came with it: no slot, and the
    content zone starts at the lead pad as it always has. The bar-level suites (TTitleBarTest,
    TRtl*) pin the rest of the zero-slot layout, which every bar now goes through. }
  l := SlotLay(0, False, 0);
  AssertTrue('no slot', IsRectEmpty(l.SystemButtons));
  AssertEquals('content from the lead pad', 8, l.Content.Left);
  AssertEquals('to our cluster', 800 - 3 * 46, l.Content.Right);
  l := SlotLay(0, True, 0);
  AssertTrue('no slot, mirrored', IsRectEmpty(l.SystemButtons));
  AssertEquals('mirrored content ends at the lead pad', 800 - 8, l.Content.Right);
end;

procedure TSystemCaptionLayoutTest.TestTheIconComesAfterTheSlot;
var l: TTyCaptionLayout;
begin
  { main only (#9's icon): slot, lead pad, icon, gap, then the content zone }
  l := TySystemTitleBarLayoutFor(True, True, True, 800, 40, 46, 0, 0, 0, 8, 16, 4, 54, 16, 7, False);
  AssertRectEq('the slot is unchanged', Rect(7, 12, 61, 28), l.SystemButtons);
  AssertRectEq('the icon after the slot and the lead pad', Rect(76, 12, 92, 28), l.Icon);
  AssertEquals('the content after the icon and its gap', 96, l.Content.Left);
  l := TySystemTitleBarLayoutFor(True, True, True, 800, 40, 46, 0, 0, 0, 8, 16, 4, 54, 16, 7, True);
  AssertRectEq('mirrored: the slot at the right edge', Rect(739, 12, 793, 28), l.SystemButtons);
  AssertRectEq('and the icon just inside it', Rect(708, 12, 724, 28), l.Icon);
end;

{ TMacTitleBarTest }

procedure TMacTitleBarTest.TestTheDefaultIsOnAndNotStreamed;
var bar: TTyCustomTitleBar;
begin
  bar := TTyTitleBar.Create(nil);
  try
    AssertTrue('on by default', bar.MacTrafficLights);
    AssertEquals('the default is not written', 0, Pos('MacTrafficLights', ComponentText(bar)));
    bar.MacTrafficLights := False;
    AssertTrue('False is', Pos('MacTrafficLights = False', ComponentText(bar)) > 0);
  finally
    bar.Free;
  end;
end;

procedure TMacTitleBarTest.TestSystemButtonsStandInForOurs;
var
  F: TFrameFormAccess;
  bar: TTyCustomTitleBar;
  lay: TTyCaptionLayout;
begin
  F := NewMacForm;
  try
    bar := F.TitleBar;
    AssertFalse('our minimize hidden', bar.MinButton.Visible);
    AssertFalse('our maximize hidden', bar.MaxButton.Visible);
    AssertFalse('our close hidden', bar.CloseButton.Visible);
    lay := bar.CaptionLayout;
    AssertEquals('a slot as wide as the system group', 54, lay.SystemButtons.Right - lay.SystemButtons.Left);
    AssertEquals('and as tall', 16, lay.SystemButtons.Bottom - lay.SystemButtons.Top);
    AssertEquals('centred in the bar', (bar.ClientHeight - 16) div 2, lay.SystemButtons.Top);
    AssertTrue('at least the system''s inset in', lay.SystemButtons.Left >= 7);
    AssertEquals('nothing of ours reserved at the far end', bar.ClientWidth, lay.Content.Right);
  finally
    F.Free;
  end;
end;

procedure TMacTitleBarTest.TestTheSlotPushesTheContentZone;
var
  F: TFrameFormAccess;
  bar: TTyCustomTitleBar;
  withSlot, without: TTyCaptionLayout;
  r: TRect;
begin
  F := NewMacForm;
  try
    bar := F.TitleBar;
    withSlot := bar.CaptionLayout;
    bar.MacTrafficLights := False;
    without := bar.CaptionLayout;
    AssertEquals('the slot moves the content zone along by the group and a margin each side',
      without.Content.Left + 2 * withSlot.SystemButtons.Left + 54, withSlot.Content.Left);
    bar.MacTrafficLights := True;
    r := Rect(0, 0, bar.ClientWidth, bar.ClientHeight);
    TFrameBarAccess(bar).CallAdjustClientRect(r);
    AssertEquals('the host''s children are given the same start', withSlot.Content.Left, r.Left);
  finally
    F.Free;
  end;
end;

procedure TMacTitleBarTest.TestSwitchingOffBringsOurButtonsBack;
var
  F: TFrameFormAccess;
  bar: TTyCustomTitleBar;
begin
  F := NewMacForm;
  try
    bar := F.TitleBar;
    bar.MacTrafficLights := False;
    AssertTrue('ours back', bar.MinButton.Visible and bar.MaxButton.Visible and bar.CloseButton.Visible);
    AssertTrue('no slot', IsRectEmpty(bar.CaptionLayout.SystemButtons));
    TyTestPlatform.Placements := 0;
    TFrameBarAccess(bar).CallLayoutButtons;
    AssertEquals('the system''s are not placed', 0, TyTestPlatform.Placements);
    bar.MacTrafficLights := True;
    AssertFalse('and ours go again', bar.MinButton.Visible);
  finally
    F.Free;
  end;
end;

procedure TMacTitleBarTest.TestPlacementIsInFormCoordinates;
var
  F: TFrameFormAccess;
  bar: TTyCustomTitleBar;
  host: TPanel;
  lay: TTyCaptionLayout;
begin
  F := NewMacForm;
  try
    bar := F.TitleBar;
    host := TPanel.Create(F);
    host.Parent := F;
    host.SetBounds(5, 20, 700, 60);
    bar.Parent := host;
    bar.SetBounds(3, 4, 600, bar.Height);
    TyTestPlatform.Placements := 0;
    TFrameBarAccess(bar).CallLayoutButtons;
    lay := bar.CaptionLayout;
    AssertTrue('placed', TyTestPlatform.Placements > 0);
    AssertTrue('on its own window', TyTestPlatform.LastPlacementForm = F);
    AssertRectEq('the slot, in the form''s coordinates (bar 3,4 inside a panel at 5,20)',
      Rect(lay.SystemButtons.Left + 8, lay.SystemButtons.Top + 24,
           lay.SystemButtons.Right + 8, lay.SystemButtons.Bottom + 24),
      TyTestPlatform.LastPlacement);
  finally
    F.Free;
  end;
end;

procedure TMacTitleBarTest.TestRightToLeftPutsTheSlotOnTheRight;
var
  F: TFrameFormAccess;
  bar: TTyCustomTitleBar;
  ltr, rtl: TTyCaptionLayout;
begin
  F := NewMacForm;
  try
    bar := F.TitleBar;
    ltr := bar.CaptionLayout;
    bar.BiDiMode := bdRightToLeft;
    rtl := bar.CaptionLayout;
    AssertEquals('the slot mirrors to the right edge',
      bar.ClientWidth - ltr.SystemButtons.Right, rtl.SystemButtons.Left);
    TyTestPlatform.Placements := 0;
    TFrameBarAccess(bar).CallLayoutButtons;
    AssertEquals('and the buttons are placed there', rtl.SystemButtons.Left, TyTestPlatform.LastPlacement.Left);
  finally
    F.Free;
  end;
end;

procedure TMacTitleBarTest.TestOffMacNothingChanges;
var
  F: TFrameFormAccess;
  bar: TTyCustomTitleBar;
begin
  TyTestPlatform.Traits := [ftrModalMove, ftrNativeResize];   // what Windows answers
  F := NewMacForm;
  try
    bar := F.TitleBar;
    AssertTrue('ours shown', bar.MinButton.Visible and bar.MaxButton.Visible and bar.CloseButton.Visible);
    AssertTrue('no slot', IsRectEmpty(bar.CaptionLayout.SystemButtons));
    TyTestPlatform.Placements := 0;
    TFrameBarAccess(bar).CallLayoutButtons;
    AssertEquals('nothing placed', 0, TyTestPlatform.Placements);
  finally
    F.Free;
  end;
end;

procedure TMacTitleBarTest.TestABarWithoutATyFormKeepsItsButtons;
var
  P: TForm;
  bar: TTyCustomTitleBar;
begin
  P := TForm.CreateNew(nil);
  try
    bar := TTyTitleBar.Create(P);
    bar.Parent := P;
    AssertTrue('ours shown: the system''s belong to a TTyForm''s window', bar.MinButton.Visible);
    AssertTrue('no slot', IsRectEmpty(bar.CaptionLayout.SystemButtons));
  finally
    P.Free;
  end;
end;

procedure TMacTitleBarTest.TestABarTakenOffTheFormGetsItsButtonsBack;
var
  F: TFrameFormAccess;
  bar: TTyCustomTitleBar;
begin
  F := NewMacForm;
  try
    bar := F.TitleBar;
    F.TitleBar := nil;
    AssertTrue('ours back', bar.MinButton.Visible and bar.CloseButton.Visible);
    AssertTrue('slot gone', IsRectEmpty(bar.CaptionLayout.SystemButtons));
  finally
    F.Free;
  end;
end;

procedure TMacTitleBarTest.TestACentredCaptionStaysClearOfTheSlot;
var
  F: TFrameFormAccess;
  bar: TTyCustomTitleBar;
  l, r: Integer;
begin
  { #79 centres a centred caption on the whole bar; with the traffic lights at one end it must
    still stay off them, and still be centred. }
  F := NewMacForm;
  try
    bar := F.TitleBar;
    bar.TitleAlignment := taCenter;
    bar.Caption := 'Title';
    bar.CaptionSpan(bar.ClientWidth, l, r);
    AssertTrue('clear of the slot (' + IntToStr(l) + ')', l >= bar.CaptionLayout.Content.Left);
    AssertEquals('centred on the bar', bar.ClientWidth, l + r);
  finally
    F.Free;
  end;
end;

{ TMacTitleBarAlignTest }

procedure TMacTitleBarAlignTest.TestLeftAlignedChildrenStartAfterTheSlot;
var
  F: TFrameFormAccess;
  bar: TTyCustomTitleBar;
  kid: TPanel;
  withSlot, without: Integer;
begin
  NeedWidgetSet;
  F := NewMacForm;
  try
    bar := F.TitleBar;
    bar.Align := alTop;
    kid := TPanel.Create(F);
    kid.Parent := bar;
    kid.Align := alLeft;
    kid.Width := 40;
    F.Show;
    Application.ProcessMessages;
    withSlot := kid.Left;
    AssertEquals('the child starts where the content zone does', bar.CaptionLayout.Content.Left, withSlot);
    bar.MacTrafficLights := False;
    Application.ProcessMessages;
    without := kid.Left;
    AssertEquals('and follows it back when the slot goes', bar.CaptionLayout.Content.Left, without);
    AssertTrue('which really moved it', withSlot > without);
  finally
    F.Free;
  end;
end;

{ TMacWindowFrameTest }

procedure TMacWindowFrameTest.TestTheFrameIsAppliedOnShow;
var F: TFrameFormAccess;
begin
  NeedWidgetSet;   // DoShow applies the frame only once the window has a handle
  F := NewMacForm;
  try
    F.HandleNeeded;
    TyTestPlatform.FrameApplies := 0;
    F.InjectDoShow;
    AssertTrue('applied', TyTestPlatform.FrameApplies > 0);
    AssertTrue('to this window', TyTestPlatform.LastFrameForm = F);
    AssertTrue('resizable', TyTestPlatform.LastFrame.Resizable);
    AssertTrue('closable', TyTestPlatform.LastFrame.CanClose);
    AssertTrue('minimizable', TyTestPlatform.LastFrame.CanMinimize);
    AssertTrue('zoomable', TyTestPlatform.LastFrame.CanMaximize);
    AssertTrue('with the system''s buttons', TyTestPlatform.LastFrame.SystemButtons);
  finally
    F.Free;
  end;
end;

procedure TMacWindowFrameTest.TestBorderIconsGreyTheSystemButtons;
var F: TFrameFormAccess;
begin
  F := NewMacForm;
  try
    TyTestPlatform.FrameApplies := 0;
    F.BorderIcons := [biSystemMenu];
    AssertTrue('re-applied: LCL-Cocoa rewrites the style mask on this change', TyTestPlatform.FrameApplies > 0);
    AssertTrue('close still offered', TyTestPlatform.LastFrame.CanClose);
    AssertFalse('minimize greyed', TyTestPlatform.LastFrame.CanMinimize);
    AssertFalse('zoom greyed', TyTestPlatform.LastFrame.CanMaximize);
    AssertTrue('greyed, not hidden', TyTestPlatform.LastFrame.SystemButtons);
  finally
    F.Free;
  end;
end;

procedure TMacWindowFrameTest.TestTheBarsSwitchesGreyThemToo;
var F: TFrameFormAccess;
begin
  F := NewMacForm;
  try
    { Each switch both ways: the way back proves the frame was really recomputed, which an
      assertion of False on a record nobody wrote would not. }
    F.TitleBar.ShowMinimize := False;
    AssertFalse('minimize greyed', TyTestPlatform.LastFrame.CanMinimize);
    F.TitleBar.ShowMinimize := True;
    AssertTrue('minimize back', TyTestPlatform.LastFrame.CanMinimize);
    F.TitleBar.ShowClose := False;
    AssertFalse('close greyed', TyTestPlatform.LastFrame.CanClose);
    F.TitleBar.ShowClose := True;
    AssertTrue('close back', TyTestPlatform.LastFrame.CanClose);
    F.TitleBar.ShowMaximize := False;
    AssertFalse('zoom greyed', TyTestPlatform.LastFrame.CanMaximize);
    F.TitleBar.ShowMaximize := True;
    AssertTrue('zoom back', TyTestPlatform.LastFrame.CanMaximize);
  finally
    F.Free;
  end;
end;

procedure TMacWindowFrameTest.TestAFixedWindowIsNotResizable;
var F: TFrameFormAccess;
begin
  F := NewMacForm;
  try
    F.Resizable := False;
    AssertFalse('no edge resize', TyTestPlatform.LastFrame.Resizable);
    AssertFalse('no zoom', TyTestPlatform.LastFrame.CanMaximize);
    F.Resizable := True;
    AssertTrue('edge resize back', TyTestPlatform.LastFrame.Resizable);
    AssertTrue('zoom back', TyTestPlatform.LastFrame.CanMaximize);
  finally
    F.Free;
  end;
end;

procedure TMacWindowFrameTest.TestACodeCreatedBarGetsAnEnabledFrame;
var F: TFrameFormAccess;
begin
  { A bar created in code is associated and armed from the form's Notification, which runs
    before the bar's constructor body -- when its switches are not set yet. The frame applied
    then must not be the last word, or every system button starts greyed. }
  F := NewMacForm;
  try
    AssertTrue('applied', TyTestPlatform.FrameApplies > 0);
    AssertTrue('closable', TyTestPlatform.LastFrame.CanClose);
    AssertTrue('minimizable', TyTestPlatform.LastFrame.CanMinimize);
    AssertTrue('zoomable', TyTestPlatform.LastFrame.CanMaximize);
    AssertTrue('with the system''s buttons', TyTestPlatform.LastFrame.SystemButtons);
  finally
    F.Free;
  end;
end;

procedure TMacWindowFrameTest.TestARolledUpWindowIsNotResizable;
var F: TFrameFormAccess;
begin
  F := NewMacForm;
  try
    F.ToggleRollUp;
    AssertFalse('rolled up: no edge resize', TyTestPlatform.LastFrame.Resizable);
    AssertFalse('and no zoom', TyTestPlatform.LastFrame.CanMaximize);
    F.ToggleRollUp;
    AssertTrue('unrolled: back', TyTestPlatform.LastFrame.Resizable);
  finally
    F.Free;
  end;
end;

procedure TMacWindowFrameTest.TestSwitchingTrafficLightsOffHidesTheSystemButtons;
var F: TFrameFormAccess;
begin
  F := NewMacForm;
  try
    TyTestPlatform.FrameApplies := 0;
    F.TitleBar.MacTrafficLights := False;
    AssertTrue('re-applied', TyTestPlatform.FrameApplies > 0);
    AssertFalse('the system''s hidden', TyTestPlatform.LastFrame.SystemButtons);
    AssertTrue('the window still closes', TyTestPlatform.LastFrame.CanClose);
  finally
    F.Free;
  end;
end;

procedure TMacWindowFrameTest.TestNoTitleBarNoSystemButtons;
var F: TFrameFormAccess;
begin
  NeedWidgetSet;
  F := TFrameFormAccess.CreateNew(nil);
  try
    F.HandleNeeded;
    TyTestPlatform.FrameApplies := 0;
    F.InjectDoShow;
    AssertTrue('the frame still applies: corners and edges need no bar', TyTestPlatform.FrameApplies > 0);
    AssertFalse('no bar, no system buttons', TyTestPlatform.LastFrame.SystemButtons);
  finally
    F.Free;
  end;
end;

procedure TMacWindowFrameTest.TestTakingTheBarAwayHidesThem;
var F: TFrameFormAccess;
begin
  F := NewMacForm;
  try
    TyTestPlatform.FrameApplies := 0;
    F.TitleBar := nil;
    AssertTrue('re-applied', TyTestPlatform.FrameApplies > 0);
    AssertFalse('hidden with the bar gone', TyTestPlatform.LastFrame.SystemButtons);
  finally
    F.Free;
  end;
end;

procedure TMacWindowFrameTest.TestFreeingTheBarHidesThem;
var F: TFrameFormAccess;
begin
  F := NewMacForm;
  try
    TyTestPlatform.FrameApplies := 0;
    F.TitleBar.Free;
    AssertTrue('re-applied', TyTestPlatform.FrameApplies > 0);
    AssertFalse('hidden with the bar gone', TyTestPlatform.LastFrame.SystemButtons);
  finally
    F.Free;
  end;
end;

procedure TMacWindowFrameTest.TestTheDesignSurfaceGetsNoFrame;
var F: TFrameFormAccess;
begin
  F := TFrameFormAccess.CreateNew(nil);
  try
    F.SetDesigning(True, False);
    TTyTitleBar.Create(F);   // associated, never armed on the design surface
    TyTestPlatform.FrameApplies := 0;
    F.Resizable := False;    // through ApplyResizeStrategy
    F.TitleBar := nil;       // straight to ApplyWindowFrame
    AssertEquals('the IDE''s window is never touched', 0, TyTestPlatform.FrameApplies);
  finally
    F.Free;
  end;
end;

{ TMacChromeEngineTest }

procedure TMacChromeEngineTest.TestTheEdgesAreTheSystemsToResize;
var F: TFrameFormAccess;
begin
  F := NewMacForm;
  try
    F.InjectFormMouseDown(mbLeft, [], 799, 300);
    AssertFalse('no resize by hand on the right edge', F.Engine.Resizing);
    F.InjectFormMouseUp(mbLeft, [], 799, 300);
    TyTestPlatform.Traits := [];   // a widgetset with no frame of its own (GTK, Qt)
    F.InjectFormMouseDown(mbLeft, [], 799, 300);
    AssertTrue('there the engine still resizes by hand', F.Engine.Resizing);
    F.InjectFormMouseUp(mbLeft, [], 799, 300);
  finally
    F.Free;
  end;
end;

procedure TMacChromeEngineTest.TestThePressDoesNotStartTheMove;
var F: TFrameFormAccess;
begin
  F := NewMacForm;
  try
    F.Engine.TitleBarDragBegin(Point(300, 10));
    AssertEquals('nothing handed over on the press', 0, TyTestPlatform.SystemMoves);
    AssertTrue('the drag is armed', F.Engine.Dragging);
  finally
    F.Free;
  end;
end;

procedure TMacChromeEngineTest.TestADragPastTheThresholdIsHandedToTheSystem;
var F: TFrameFormAccess;
begin
  F := NewMacForm;
  try
    F.SetBounds(100, 100, 800, 600);
    F.Engine.TitleBarDragBegin(Point(300, 110));
    F.Engine.TitleBarDragUpdate(Point(301, 111));
    AssertEquals('a jiggle hands nothing over', 0, TyTestPlatform.SystemMoves);
    AssertEquals('nor moves the window', 100, F.Left);
    F.Engine.TitleBarDragUpdate(Point(340, 110));
    AssertEquals('past the threshold the system takes the drag', 1, TyTestPlatform.SystemMoves);
    AssertFalse('and the engine lets go', F.Engine.Dragging);
    AssertEquals('nothing moved by hand', 100, F.Left);
  finally
    F.Free;
  end;
end;

procedure TMacChromeEngineTest.TestAMoveThatUnzoomsIsHeardBack;
var F: TFrameFormAccess;
begin
  F := NewMacForm;
  try
    F.InjectResizing(wsMaximized);   // the system zoomed the window
    AssertTrue('precondition: a native maximize', F.Engine.NativeMaximized);
    TyTestPlatform.Zoomed := False;  // what dragging a zoomed window leaves behind on macOS
    F.Engine.TitleBarDragBegin(Point(300, 10));
    F.Engine.TitleBarDragUpdate(Point(340, 10));
    AssertEquals('handed over untouched', 1, TyTestPlatform.SystemMoves);
    AssertFalse('the chrome hears the zoom is gone', F.Engine.Maximized);
    AssertTrue('the glyph offers maximize again', F.TitleBar.MaxButton.Kind = cbkMax);
    F.InjectResizing(wsMaximized);
    TyTestPlatform.Zoomed := True;   // a move that left it zoomed
    F.Engine.TitleBarDragBegin(Point(300, 10));
    F.Engine.TitleBarDragUpdate(Point(340, 10));
    AssertTrue('stays maximized', F.Engine.Maximized);
  finally
    F.Free;
  end;
end;

procedure TMacChromeEngineTest.TestMaximizeIsTheSystemZoom;
var F: TFrameFormAccess;
begin
  F := NewMacForm;
  try
    F.SetBounds(100, 100, 800, 600);
    F.Engine.ToggleMaximize;
    AssertEquals('one zoom request', 1, TyTestPlatform.ZoomRequests);
    AssertTrue('to zoom in', TyTestPlatform.Zoomed);
    AssertEquals('no work-area fill: the bounds are the system''s to change', 800, F.Width);
    AssertFalse('the chrome waits for the system''s report', F.Engine.Maximized);
    F.InjectResizing(wsMaximized);
    AssertTrue('and adopts it', F.Engine.NativeMaximized);
  finally
    F.Free;
  end;
end;

procedure TMacChromeEngineTest.TestRestoreUnzooms;
var F: TFrameFormAccess;
begin
  F := NewMacForm;
  try
    TyTestPlatform.Zoomed := True;
    F.InjectResizing(wsMaximized);
    F.Engine.ToggleMaximize;
    AssertEquals('one zoom request', 1, TyTestPlatform.ZoomRequests);
    AssertFalse('to zoom out', TyTestPlatform.Zoomed);
    AssertFalse('the chrome is back to normal', F.Engine.Maximized);
  finally
    F.Free;
  end;
end;

procedure TMacChromeEngineTest.TestDoubleClickFollowsTheSystemSetting;
var
  F: TFrameFormAccess;
  bar: TFrameBarAccess;
begin
  F := NewMacForm;
  try
    bar := TFrameBarAccess(F.TitleBar);
    TyTestPlatform.DoubleClick := tdcMinimize;
    bar.InjectDblClick;
    AssertEquals('minimized', 1, TyTestPlatform.Minimizes);
    AssertEquals('not zoomed', 0, TyTestPlatform.ZoomRequests);
    TyTestPlatform.DoubleClick := tdcNone;
    bar.InjectDblClick;
    AssertEquals('"do nothing" does nothing', 1, TyTestPlatform.Minimizes);
    AssertEquals('still not zoomed', 0, TyTestPlatform.ZoomRequests);
    TyTestPlatform.DoubleClick := tdcMaximize;
    bar.InjectDblClick;
    AssertEquals('zoomed', 1, TyTestPlatform.ZoomRequests);
  finally
    F.Free;
  end;
end;

procedure TMacChromeEngineTest.TestCaptionActionStillDecides;
var F: TFrameFormAccess;
begin
  F := NewMacForm;
  try
    TyTestPlatform.DoubleClick := tdcMinimize;
    F.CaptionAction := tcaRollUp;
    TFrameBarAccess(F.TitleBar).InjectDblClick;
    AssertTrue('rolled up, as the developer asked', F.RolledUp);
    AssertEquals('the system setting did not run', 0, TyTestPlatform.Minimizes);
    F.CaptionAction := tcaNone;
    TFrameBarAccess(F.TitleBar).InjectDblClick;
    AssertEquals('none means none', 0, TyTestPlatform.Minimizes);
  finally
    F.Free;
  end;
end;

procedure TMacChromeEngineTest.TestOurMinimizeSendsThisWindowToTheDock;
var F: TFrameFormAccess;
begin
  F := NewMacForm;
  try
    F.TitleBar.MacTrafficLights := False;   // our buttons, the system's actions
    TFrameButtonAccess(F.TitleBar.MinButton).InjectClick;
    AssertEquals('this window minimized by the platform', 1, TyTestPlatform.Minimizes);
    AssertTrue('not through a window state', F.WindowState <> wsMinimized);
  finally
    F.Free;
  end;
end;

procedure TMacChromeEngineTest.TestAMaximizedWindowStateIsLeftForTheSystem;
var F: TFrameFormAccess;
begin
  F := NewMacForm;
  try
    F.SetBounds(10, 10, 400, 300);
    F.WindowState := wsMaximized;
    F.InjectDoShow;
    AssertEquals('left for the widgetset, which zooms once the frame is on',
      Ord(wsMaximized), Ord(F.WindowState));
    AssertFalse('no engine maximize', F.Engine.Maximized);
    AssertEquals('no work-area fill', 400, F.Width);
  finally
    F.Free;
  end;
  F := NewMacForm;
  try
    F.Resizable := False;
    F.WindowState := wsMaximized;
    F.InjectDoShow;
    AssertEquals('a fixed window still cannot maximize', Ord(wsNormal), Ord(F.WindowState));
  finally
    F.Free;
  end;
end;

procedure TMacChromeEngineTest.TestTheWindowMenuGoesToTheSystemToo;
var F: TFrameFormAccess;
begin
  { #9's window menu clicks the bar's own buttons -- hidden while the traffic lights stand in
    for them -- so its Minimize and Maximize must reach the system all the same. }
  F := NewMacForm;
  try
    F.TitleBar.DefaultWindowMenu.Items[TyWindowMenuMinimizeIndex].Click;
    AssertEquals('minimized by the platform', 1, TyTestPlatform.Minimizes);
    F.TitleBar.DefaultWindowMenu.Items[TyWindowMenuMaximizeIndex].Click;
    AssertEquals('zoomed by the platform', 1, TyTestPlatform.ZoomRequests);
  finally
    F.Free;
  end;
end;

{ TWindowAppearanceTest }

function StyleWithBg(AKind: TTyFillKind; AFrom, ATo: TTyColor): TTyStyleSet;
begin
  Result := Default(TTyStyleSet);
  Include(Result.Present, tpBackground);
  Result.Background.Kind := AKind;
  Result.Background.Color := AFrom;
  Result.Background.GradFrom := AFrom;
  Result.Background.GradTo := ATo;
end;

procedure TWindowAppearanceTest.TearDown;
begin
  TyResetTestPlatform;
end;

procedure TWindowAppearanceTest.TestDarkFollowsASolidBackground;
begin
  AssertTrue('#1E1E1E is dark',
    TyResolveWindowEffect(StyleWithBg(tfkSolid, TyRGB($1E, $1E, $1E), 0), False).DarkAppearance);
  AssertFalse('#F3F3F3 is light',
    TyResolveWindowEffect(StyleWithBg(tfkSolid, TyRGB($F3, $F3, $F3), 0), False).DarkAppearance);
end;

procedure TWindowAppearanceTest.TestDarkFollowsAGradientsEnds;
begin
  AssertTrue('dark to darker', TyResolveWindowEffect(
    StyleWithBg(tfkLinearGradient, TyRGB(40, 40, 40), TyRGB(10, 10, 10)), False).DarkAppearance);
  AssertFalse('light to lighter', TyResolveWindowEffect(
    StyleWithBg(tfkLinearGradient, TyRGB(220, 220, 220), TyRGB(250, 250, 250)), False).DarkAppearance);
end;

procedure TWindowAppearanceTest.TestAnImageGoesByItsTextColour;
var S: TTyStyleSet;
begin
  S := StyleWithBg(tfkImage, 0, 0);
  Include(S.Present, tpTextColor);
  S.TextColor := TyRGB(255, 255, 255);
  AssertTrue('white text on a picture: a dark picture', TyResolveWindowEffect(S, False).DarkAppearance);
  S.TextColor := TyRGB(0, 0, 0);
  AssertFalse('black text: a light one', TyResolveWindowEffect(S, False).DarkAppearance);
end;

procedure TWindowAppearanceTest.TestNothingToGoByIsLight;
begin
  AssertFalse('no background, no text colour',
    TyResolveWindowEffect(Default(TTyStyleSet), False).DarkAppearance);
end;

procedure TWindowAppearanceTest.TestTheAppearanceReachesThePlatform;
var
  F: TTyForm;
  Ctl: TTyStyleController;
begin
  NeedWidgetSet;
  TyResetTestPlatform;
  TyTestPlatform.Active := True;
  F := TTyForm.CreateNew(nil);
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss('TyForm { background: #202020; window-shadow: false; }');
    F.HandleNeeded;
    F.ApplyChromeTheme(Ctl);
    AssertTrue('applied', TyTestPlatform.AppearanceApplies > 0);
    AssertTrue('dark', TyTestPlatform.LastDark);
    AssertFalse('without a shadow', TyTestPlatform.LastShadow);
  finally
    Ctl.Free;
    F.Free;
  end;
end;

procedure TWindowAppearanceTest.TestAThemeSwitchFlipsIt;
var
  F: TTyForm;
  dark, light: TTyStyleController;
begin
  NeedWidgetSet;
  TyResetTestPlatform;
  TyTestPlatform.Active := True;
  F := TTyForm.CreateNew(nil);
  dark := TTyStyleController.Create(nil);
  light := TTyStyleController.Create(nil);
  try
    dark.LoadThemeCss('TyForm { background: #202020; }');
    light.LoadThemeCss('TyForm { background: #FAFAFA; }');
    F.HandleNeeded;
    F.ApplyChromeTheme(dark);
    AssertTrue('dark first', TyTestPlatform.LastDark);
    F.ApplyChromeTheme(light);
    AssertFalse('then light', TyTestPlatform.LastDark);
    AssertTrue('with the shadow on by default', TyTestPlatform.LastShadow);
  finally
    F.Controller := nil;
    light.Free;
    dark.Free;
    F.Free;
  end;
end;

initialization
  RegisterTest(TPlatformFrameFacadeTest);
  RegisterTest(TSystemCaptionLayoutTest);
  RegisterTest(TMacTitleBarTest);
  RegisterTest(TMacTitleBarAlignTest);
  RegisterTest(TMacWindowFrameTest);
  RegisterTest(TMacChromeEngineTest);
  RegisterTest(TWindowAppearanceTest);

end.
