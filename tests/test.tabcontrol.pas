unit test.tabcontrol;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, StdCtrls, LCLType,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller,
  tyControls.Base, tyControls.Panel, tyControls.TabControl;

type
  { Subclass that exposes protected/private helpers for white-box tests }
  TTyTabControlAccess = class(TTyTabControl)
  public
    function StyleTypeKey: string;
    procedure CallAdjustClientRect(var ARect: TRect);
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure CallMouseDown(Button: TMouseButton; X, Y: Integer);
    procedure CallMouseMove(X, Y: Integer);
    procedure CallMouseLeave;
    procedure SimulateKeyDown(AKey: Word);
  end;

  { Change-count probe }
  TTabChangeProbe = class
  public
    Count: Integer;
    procedure Handle(Sender: TObject);
  end;

  TTyTabControlTest = class(TTestCase)
  private
    FForm: TForm;
    FTab: TTyTabControl;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestAddTabReturnsPageAndAutoSelectsFirst;
    procedure TestTabIndexSwitchesPageVisibility;
    procedure TestTabIndexClamps;
    procedure TestKeyboardSwitchesTabs;
    procedure TestHeaderRectsLayout;
    procedure TestAdjustClientRectInset;
    procedure TestMouseDownSelectsTab;
    procedure TestActiveTabRendersActiveStyle;
    procedure TestPagesHostChildren;
    // TAB.C: Controller propagation to pages
    procedure TestControllerPropagatedOnSetAfterAddTab;
    procedure TestControllerPropagatedOnAddTabAfterSet;
    procedure TestRemoveTabCompactsAndAdjustsIndex;
    procedure TestRemoveActiveTabSelectsNeighborFiresOnChange;
    procedure TestRemoveTabBeforeActiveKeepsActivePageNoOnChange;
    procedure TestRemoveTabOutOfRangeNoOp;
    procedure TestExternalFreePageHardensArrays;
    procedure TestNonClosableGeometryUnchanged;
    procedure TestClosableWidensHeaderAndCloseRectInside;
    procedure TestClickCloseFiresEventAndRemoves;
    procedure TestClickCloseCanceledKeepsTab;
    procedure TestClickHeaderBodyStillSelectsWhenClosable;
    procedure TestTabHeaderTopCornerRoundedFromTheme;
  end;

implementation

type
  TTabCloseProbe = class
  public
    LastIndex: Integer;
    Count: Integer;
    Cancel: Boolean;
    constructor Create;
    procedure Handle(Sender: TObject; AIndex: Integer; var AllowClose: Boolean);
  end;

constructor TTabCloseProbe.Create;
begin
  inherited Create;
  LastIndex := -99;
  Count := 0;
  Cancel := False;
end;

procedure TTabCloseProbe.Handle(Sender: TObject; AIndex: Integer; var AllowClose: Boolean);
begin
  Inc(Count);
  LastIndex := AIndex;
  if Cancel then AllowClose := False;
end;

{ TTabChangeProbe }

procedure TTabChangeProbe.Handle(Sender: TObject);
begin
  Inc(Count);
end;

{ TTyTabControlAccess }

function TTyTabControlAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TTyTabControlAccess.CallAdjustClientRect(var ARect: TRect);
begin
  AdjustClientRect(ARect);
end;

procedure TTyTabControlAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyTabControlAccess.CallMouseDown(Button: TMouseButton; X, Y: Integer);
begin
  MouseDown(Button, [], X, Y);
end;

procedure TTyTabControlAccess.CallMouseMove(X, Y: Integer);
begin
  MouseMove([], X, Y);
end;

procedure TTyTabControlAccess.CallMouseLeave;
begin
  MouseLeave;
end;

procedure TTyTabControlAccess.SimulateKeyDown(AKey: Word);
begin
  KeyDown(AKey, []);
end;

{ TTyTabControlTest }

procedure TTyTabControlTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 300);
  FTab := TTyTabControl.Create(FForm);
  FTab.Parent := FForm;
  FTab.SetBounds(0, 0, 300, 200);
  FTab.Font.PixelsPerInch := 96;
end;

procedure TTyTabControlTest.TearDown;
begin
  FForm.Free;
end;

{ TestTypeKey: GetStyleTypeKey returns 'TyTabControl' }
procedure TTyTabControlTest.TestTypeKey;
var
  Acc: TTyTabControlAccess;
begin
  Acc := TTyTabControlAccess.Create(FForm);
  Acc.Parent := FForm;
  try
    AssertEquals('TyTabControl', Acc.StyleTypeKey);
  finally
    Acc.Free;
  end;
end;

{ TestAddTabReturnsPageAndAutoSelectsFirst:
  AddTab x2 -> TabCount=2; first add sets TabIndex=0; Pages[0].Visible=True; Pages[1].Visible=False }
procedure TTyTabControlTest.TestAddTabReturnsPageAndAutoSelectsFirst;
var
  P0, P1: TTyPanel;
begin
  P0 := FTab.AddTab('First');
  P1 := FTab.AddTab('Second');
  AssertEquals('TabCount = 2', 2, FTab.TabCount);
  AssertEquals('TabIndex = 0 after first add', 0, FTab.TabIndex);
  AssertNotNull('Pages[0] not nil', FTab.Pages[0]);
  AssertNotNull('Pages[1] not nil', FTab.Pages[1]);
  AssertSame('AddTab returns same panel as Pages[0]', FTab.Pages[0], P0);
  AssertSame('AddTab returns same panel as Pages[1]', FTab.Pages[1], P1);
  AssertTrue('Pages[0] visible (active)', FTab.Pages[0].Visible);
  AssertFalse('Pages[1] hidden (inactive)', FTab.Pages[1].Visible);
end;

{ TestTabIndexSwitchesPageVisibility:
  TabIndex:=1 -> Pages[1] visible, Pages[0] hidden; OnChange fired once;
  setting same index again -> no extra fire. }
procedure TTyTabControlTest.TestTabIndexSwitchesPageVisibility;
var
  Probe: TTabChangeProbe;
begin
  FTab.AddTab('A');
  FTab.AddTab('B');
  Probe := TTabChangeProbe.Create;
  try
    FTab.OnChange := @Probe.Handle;
    FTab.TabIndex := 1;
    AssertTrue('Pages[1] visible after TabIndex:=1', FTab.Pages[1].Visible);
    AssertFalse('Pages[0] hidden after TabIndex:=1', FTab.Pages[0].Visible);
    AssertEquals('OnChange fired once', 1, Probe.Count);
    FTab.TabIndex := 1;
    AssertEquals('OnChange not fired again for same index', 1, Probe.Count);
  finally
    Probe.Free;
  end;
end;

{ TestTabIndexClamps:
  TabIndex:=99 -> 1 (last); TabIndex:=-1 -> allowed, no page visible }
procedure TTyTabControlTest.TestTabIndexClamps;
begin
  FTab.AddTab('A');
  FTab.AddTab('B');
  FTab.TabIndex := 99;
  AssertEquals('99 clamps to 1 (last)', 1, FTab.TabIndex);
  AssertTrue('Pages[1] visible after clamped 99', FTab.Pages[1].Visible);

  FTab.TabIndex := -1;
  AssertEquals('-1 allowed', -1, FTab.TabIndex);
  AssertFalse('Pages[0] not visible when TabIndex=-1', FTab.Pages[0].Visible);
  AssertFalse('Pages[1] not visible when TabIndex=-1', FTab.Pages[1].Visible);
end;

{ TestKeyboardSwitchesTabs:
  VK_RIGHT/VK_LEFT via SimulateKeyDown; clamping at ends }
procedure TTyTabControlTest.TestKeyboardSwitchesTabs;
var
  Acc: TTyTabControlAccess;
begin
  Acc := TTyTabControlAccess.Create(FForm);
  Acc.Parent := FForm;
  Acc.Font.PixelsPerInch := 96;
  Acc.SetBounds(0, 0, 300, 200);
  try
    Acc.AddTab('A');
    Acc.AddTab('B');
    Acc.AddTab('C');
    AssertEquals('initial TabIndex = 0', 0, Acc.TabIndex);

    Acc.SimulateKeyDown(VK_RIGHT);
    AssertEquals('RIGHT: 0 -> 1', 1, Acc.TabIndex);

    Acc.SimulateKeyDown(VK_RIGHT);
    AssertEquals('RIGHT: 1 -> 2', 2, Acc.TabIndex);

    Acc.SimulateKeyDown(VK_RIGHT);
    AssertEquals('RIGHT clamps at last (2)', 2, Acc.TabIndex);

    Acc.SimulateKeyDown(VK_LEFT);
    AssertEquals('LEFT: 2 -> 1', 1, Acc.TabIndex);

    Acc.SimulateKeyDown(VK_LEFT);
    AssertEquals('LEFT: 1 -> 0', 0, Acc.TabIndex);

    Acc.SimulateKeyDown(VK_LEFT);
    AssertEquals('LEFT clamps at 0', 0, Acc.TabIndex);
  finally
    Acc.Free;
  end;
end;

{ TestHeaderRectsLayout:
  Two tabs 'AB' and 'CD' @96ppi.
  rect(0).Left=0; rect(1).Left=rect(0).Right; both heights=28; widths >= 48 }
procedure TTyTabControlTest.TestHeaderRectsLayout;
var
  R0, R1: TRect;
begin
  FTab.AddTab('AB');
  FTab.AddTab('CD');
  R0 := FTab.TyTabHeaderRect(0);
  R1 := FTab.TyTabHeaderRect(1);

  AssertEquals('rect(0).Left = 0', 0, R0.Left);
  AssertEquals('rect(0).Top = 0', 0, R0.Top);
  AssertEquals('rect(0).Bottom = 28 (TabHeight@96ppi)', 28, R0.Bottom);
  AssertEquals('rect(1).Left = rect(0).Right', R0.Right, R1.Left);
  AssertEquals('rect(1).Bottom = 28', 28, R1.Bottom);
  AssertTrue('rect(0).Width >= 48', (R0.Right - R0.Left) >= 48);
  AssertTrue('rect(1).Width >= 48', (R1.Right - R1.Left) >= 48);
end;

{ TestAdjustClientRectInset:
  Direct call; @96ppi TabHeight=28 -> ARect.Top increases by 28 }
procedure TTyTabControlTest.TestAdjustClientRectInset;
var
  Acc: TTyTabControlAccess;
  ARect: TRect;
begin
  Acc := TTyTabControlAccess.Create(FForm);
  Acc.Parent := FForm;
  Acc.Font.PixelsPerInch := 96;
  Acc.SetBounds(0, 0, 300, 200);
  try
    ARect := Rect(0, 0, 300, 200);
    Acc.CallAdjustClientRect(ARect);
    AssertEquals('ARect.Top inset by 28 (TabHeight 28 @96ppi)', 28, ARect.Top);
  finally
    Acc.Free;
  end;
end;

{ TestMouseDownSelectsTab:
  Simulate MouseDown at a point inside rect(1) -> TabIndex=1 }
procedure TTyTabControlTest.TestMouseDownSelectsTab;
var
  Acc: TTyTabControlAccess;
  R1: TRect;
  MidX, MidY: Integer;
begin
  Acc := TTyTabControlAccess.Create(FForm);
  Acc.Parent := FForm;
  Acc.Font.PixelsPerInch := 96;
  Acc.SetBounds(0, 0, 300, 200);
  try
    Acc.AddTab('Alpha');
    Acc.AddTab('Beta');
    R1 := Acc.TyTabHeaderRect(1);
    MidX := (R1.Left + R1.Right) div 2;
    MidY := (R1.Top + R1.Bottom) div 2;
    Acc.CallMouseDown(mbLeft, MidX, MidY);
    AssertEquals('MouseDown in header 1 -> TabIndex=1', 1, Acc.TabIndex);
  finally
    Acc.Free;
  end;
end;

{ TestActiveTabRendersActiveStyle:
  CSS: TyTabControl dark bg; TyTab transparent; TyTab:active blue.
  2 tabs, TabIndex=0 -> probe inside header 0 -> blue-dominant; header 1 -> not. }
procedure TTyTabControlTest.TestActiveTabRendersActiveStyle;
var
  Ctl: TTyStyleController;
  Acc: TTyTabControlAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  R0, R1: TRect;
  ProbeX0, ProbeY0, ProbeX1, ProbeY1: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  Acc := TTyTabControlAccess.Create(FForm);
  Acc.Parent := FForm;
  try
    Ctl.LoadThemeCss(
      'TyTabControl { background: #181818; border-width: 0px; } ' +
      'TyTab { background: alpha(#000000,0); color: #AAAAAA; } ' +
      'TyTab:active { background: #3B82F6; color: #FFFFFF; }');
    Acc.Controller := Ctl;
    Acc.Font.PixelsPerInch := 96;
    Acc.SetBounds(0, 0, 300, 200);
    Acc.AddTab('Left');
    Acc.AddTab('Right');
    { TabIndex = 0 (already set by AddTab first) }
    AssertEquals('TabIndex=0 before render', 0, Acc.TabIndex);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(300, 200);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 300, 200);

    Acc.RenderTo(Bmp.Canvas, Rect(0, 0, 300, 200), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      R0 := Acc.TyTabHeaderRect(0);
      R1 := Acc.TyTabHeaderRect(1);
      { Probe well inside each header, away from text area }
      ProbeX0 := R0.Left + (R0.Right - R0.Left) * 3 div 4;
      ProbeY0 := (R0.Top + R0.Bottom) div 2;
      ProbeX1 := R1.Left + (R1.Right - R1.Left) * 3 div 4;
      ProbeY1 := (R1.Top + R1.Bottom) div 2;

      Px := Reread.GetPixel(ProbeX0, ProbeY0);
      AssertTrue(Format('active tab0 blue dominant: B > 180 (R=%d G=%d B=%d)',
        [Px.red, Px.green, Px.blue]), Px.blue > 180);
      AssertTrue(Format('active tab0: R < 120 (R=%d G=%d B=%d)',
        [Px.red, Px.green, Px.blue]), Px.red < 120);

      Px := Reread.GetPixel(ProbeX1, ProbeY1);
      AssertTrue(Format('inactive tab1 not blue-dominant: B <= 180 or B <= R+50 (R=%d G=%d B=%d)',
        [Px.red, Px.green, Px.blue]),
        (Px.blue <= 180) or (Px.blue <= Px.red + 50));
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ TestPagesHostChildren:
  A TButton parented to Pages[0] -> Pages[0].ControlCount = 1 }
procedure TTyTabControlTest.TestPagesHostChildren;
var
  Btn: TButton;
begin
  FTab.AddTab('Tab1');
  FTab.AddTab('Tab2');
  Btn := TButton.Create(FTab.Pages[0]);
  Btn.Parent := FTab.Pages[0];
  AssertEquals('Pages[0].ControlCount = 1', 1, FTab.Pages[0].ControlCount);
end;

{ TestControllerPropagatedOnSetAfterAddTab:
  Add 2 tabs first, then set Controller -> both existing pages get the controller. }
procedure TTyTabControlTest.TestControllerPropagatedOnSetAfterAddTab;
var
  Ctl: TTyStyleController;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    FTab.AddTab('One');
    FTab.AddTab('Two');
    FTab.Controller := Ctl;
    AssertSame('Pages[0].Controller = Ctl after set', Ctl, FTab.Pages[0].Controller);
    AssertSame('Pages[1].Controller = Ctl after set', Ctl, FTab.Pages[1].Controller);
  finally
    Ctl.Free;
  end;
end;

{ TestControllerPropagatedOnAddTabAfterSet:
  Set Controller first, then AddTab -> new page gets the controller. }
procedure TTyTabControlTest.TestControllerPropagatedOnAddTabAfterSet;
var
  Ctl: TTyStyleController;
  Page: TTyPanel;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    FTab.Controller := Ctl;
    Page := FTab.AddTab('New');
    AssertSame('New page gets Controller when AddTab called after set',
      Ctl, Page.Controller);
  finally
    Ctl.Free;
  end;
end;

procedure TTyTabControlTest.TestRemoveTabCompactsAndAdjustsIndex;
begin
  FTab.AddTab('A');
  FTab.AddTab('B');
  FTab.AddTab('C');
  AssertEquals('3 tabs', 3, FTab.TabCount);
  FTab.RemoveTab(1);
  AssertEquals('2 tabs after remove', 2, FTab.TabCount);
  AssertEquals('caption[0] still A', 'A', FTab.TabCaption(0));
  AssertEquals('caption[1] now C', 'C', FTab.TabCaption(1));
end;

procedure TTyTabControlTest.TestRemoveActiveTabSelectsNeighborFiresOnChange;
var Probe: TTabChangeProbe;
begin
  FTab.AddTab('A'); FTab.AddTab('B'); FTab.AddTab('C');
  FTab.TabIndex := 2;
  Probe := TTabChangeProbe.Create;
  try
    FTab.OnChange := @Probe.Handle;
    FTab.RemoveTab(2);
    AssertEquals('TabIndex falls back to new last (1)', 1, FTab.TabIndex);
    AssertTrue('new active page visible', FTab.Pages[1].Visible);
    AssertEquals('OnChange fired once (active page changed)', 1, Probe.Count);
  finally
    Probe.Free;
  end;
end;

procedure TTyTabControlTest.TestRemoveTabBeforeActiveKeepsActivePageNoOnChange;
var Probe: TTabChangeProbe; ActivePageBefore: TTyPanel;
begin
  FTab.AddTab('A'); FTab.AddTab('B'); FTab.AddTab('C');
  FTab.TabIndex := 2;
  ActivePageBefore := FTab.Pages[2];
  Probe := TTabChangeProbe.Create;
  try
    FTab.OnChange := @Probe.Handle;
    FTab.RemoveTab(0);
    AssertEquals('index shifts 2 -> 1', 1, FTab.TabIndex);
    AssertSame('same page object still active', ActivePageBefore, FTab.Pages[1]);
    AssertTrue('still visible', FTab.Pages[1].Visible);
    AssertEquals('OnChange NOT fired (same page active)', 0, Probe.Count);
  finally
    Probe.Free;
  end;
end;

procedure TTyTabControlTest.TestRemoveTabOutOfRangeNoOp;
begin
  FTab.AddTab('A');
  FTab.RemoveTab(5);
  FTab.RemoveTab(-1);
  AssertEquals('still 1 tab', 1, FTab.TabCount);
end;

procedure TTyTabControlTest.TestExternalFreePageHardensArrays;
var PageB: TTyPanel;
begin
  FTab.AddTab('A');
  PageB := FTab.AddTab('B');
  FTab.AddTab('C');
  AssertEquals('3 tabs', 3, FTab.TabCount);
  PageB.Free;
  AssertEquals('2 tabs after external free', 2, FTab.TabCount);
  AssertEquals('caption[0] A', 'A', FTab.TabCaption(0));
  AssertEquals('caption[1] C (B detached)', 'C', FTab.TabCaption(1));
  FTab.Invalidate;
end;

procedure TTyTabControlTest.TestNonClosableGeometryUnchanged;
var R0, R1, C0: TRect;
begin
  FTab.AddTab('AB');
  FTab.AddTab('CD');
  AssertFalse('default not closable', FTab.TabsClosable);
  R0 := FTab.TyTabHeaderRect(0);
  R1 := FTab.TyTabHeaderRect(1);
  AssertEquals('rect(0).Left=0', 0, R0.Left);
  AssertEquals('rect(0).Bottom=28', 28, R0.Bottom);
  AssertEquals('rect(1).Left = rect(0).Right', R0.Right, R1.Left);
  AssertTrue('width >= 48', (R0.Right - R0.Left) >= 48);
  C0 := FTab.TyTabCloseRect(0);
  AssertTrue('close rect empty when not closable', (C0.Right - C0.Left) = 0);
end;

procedure TTyTabControlTest.TestClosableWidensHeaderAndCloseRectInside;
var WNarrow, WClosable: Integer; R0, C0: TRect;
begin
  FTab.AddTab('AB');
  WNarrow := FTab.TyTabHeaderRect(0).Right - FTab.TyTabHeaderRect(0).Left;
  FTab.TabsClosable := True;
  R0 := FTab.TyTabHeaderRect(0);
  WClosable := R0.Right - R0.Left;
  AssertTrue('closable header wider', WClosable > WNarrow);
  C0 := FTab.TyTabCloseRect(0);
  AssertTrue('close rect non-empty', (C0.Right - C0.Left) > 0);
  AssertTrue('close left >= header left', C0.Left >= R0.Left);
  AssertTrue('close right <= header right', C0.Right <= R0.Right);
  AssertTrue('close within header vertically', (C0.Top >= R0.Top) and (C0.Bottom <= R0.Bottom));
end;

procedure TTyTabControlTest.TestClickCloseFiresEventAndRemoves;
var Acc: TTyTabControlAccess; Probe: TTabCloseProbe; C1: TRect;
begin
  Acc := TTyTabControlAccess.Create(FForm);
  Acc.Parent := FForm; Acc.Font.PixelsPerInch := 96; Acc.SetBounds(0,0,300,200);
  Probe := TTabCloseProbe.Create;
  try
    Acc.TabsClosable := True;
    Acc.OnTabClose := @Probe.Handle;
    Acc.AddTab('A'); Acc.AddTab('B'); Acc.AddTab('C');
    C1 := Acc.TyTabCloseRect(1);
    Acc.CallMouseDown(mbLeft, (C1.Left+C1.Right) div 2, (C1.Top+C1.Bottom) div 2);
    AssertEquals('OnTabClose fired once', 1, Probe.Count);
    AssertEquals('event index = 1', 1, Probe.LastIndex);
    AssertEquals('tab removed -> 2 tabs', 2, Acc.TabCount);
    AssertEquals('caption[1] now C', 'C', Acc.TabCaption(1));
  finally
    Probe.Free; Acc.Free;
  end;
end;

procedure TTyTabControlTest.TestClickCloseCanceledKeepsTab;
var Acc: TTyTabControlAccess; Probe: TTabCloseProbe; C0: TRect;
begin
  Acc := TTyTabControlAccess.Create(FForm);
  Acc.Parent := FForm; Acc.Font.PixelsPerInch := 96; Acc.SetBounds(0,0,300,200);
  Probe := TTabCloseProbe.Create;
  try
    Acc.TabsClosable := True;
    Probe.Cancel := True;
    Acc.OnTabClose := @Probe.Handle;
    Acc.AddTab('A'); Acc.AddTab('B');
    C0 := Acc.TyTabCloseRect(0);
    Acc.CallMouseDown(mbLeft, (C0.Left+C0.Right) div 2, (C0.Top+C0.Bottom) div 2);
    AssertEquals('event fired', 1, Probe.Count);
    AssertEquals('canceled -> still 2 tabs', 2, Acc.TabCount);
  finally
    Probe.Free; Acc.Free;
  end;
end;

procedure TTyTabControlTest.TestClickHeaderBodyStillSelectsWhenClosable;
var Acc: TTyTabControlAccess; R1, C1: TRect; BodyX: Integer;
begin
  Acc := TTyTabControlAccess.Create(FForm);
  Acc.Parent := FForm; Acc.Font.PixelsPerInch := 96; Acc.SetBounds(0,0,300,200);
  try
    Acc.TabsClosable := True;
    Acc.AddTab('Alpha'); Acc.AddTab('Beta');
    R1 := Acc.TyTabHeaderRect(1);
    C1 := Acc.TyTabCloseRect(1);
    BodyX := R1.Left + 4;
    AssertTrue('body x left of close rect', BodyX < C1.Left);
    Acc.CallMouseDown(mbLeft, BodyX, (R1.Top+R1.Bottom) div 2);
    AssertEquals('header body click selects tab 1', 1, Acc.TabIndex);
    AssertEquals('no tab removed', 2, Acc.TabCount);
  finally
    Acc.Free;
  end;
end;

{ TestTabHeaderTopCornerRoundedFromTheme:
  CSS gives TyTab a border-radius:8px 8px 0 0 (top rounded, bottom square) with
  pure BLUE fill (#0000FF) so the fill is unambiguous.  After the fix the
  painter calls FillBackground(..., TyEffectiveCorners(TabStyle)) instead of
  FillBackground(..., 0), so the top-left corner pixel is rounded away and shows
  the white backdrop (red=255, green=255), while the interior of the header
  remains solidly blue (red=0, green=0, blue=255).

  Discrimination:
    - corner pixel:   red > 128  (white=255; blue-fill=0  -> FAILS when radius=0)
    - body pixel:     blue > 128 AND red < 128  (blue=255 red=0; white blue=255 red=255)
}
procedure TTyTabControlTest.TestTabHeaderTopCornerRoundedFromTheme;
var
  Ctl: TTyStyleController;
  Acc: TTyTabControlAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  CornerPx, BodyPx: TBGRAPixel;
  R0: TRect;
  BodyX, BodyY: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  Acc := TTyTabControlAccess.Create(FForm);
  Acc.Parent := FForm;
  try
    Ctl.LoadThemeCss(
      'TyTabControl { background:#FFFFFF; border-color:#000000; border-width:1px; }' +
      'TyTab { background:#0000FF; color:#000000; padding:4px; border-radius:8px 8px 0 0; }');
    Acc.Controller := Ctl;
    Acc.Font.PixelsPerInch := 96;
    Acc.SetBounds(0, 0, 200, 120);
    Acc.AddTab('AAAA');
    Acc.AddTab('BBBB');

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 120);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 200, 120);

    Acc.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 120), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      { First tab header rect: Left=0, Top=0, Bottom=28 at 96ppi (TabHeight=28).
        Corner probe: (0,0) — the extreme top-left pixel of the first header.
        With r=8, the arc clips this corner -> white backdrop (red=255).
        With r=0 (old code), this corner is solid blue (red=0) -> assertion FAILS.  }
      CornerPx := Reread.GetPixel(0, 0);
      AssertTrue(
        Format('tab top-left corner rounded away (red>128): R=%d G=%d B=%d',
          [CornerPx.red, CornerPx.green, CornerPx.blue]),
        CornerPx.red > 128);

      { Body probe: inside the first header, left of centre, below any corner arc.
        At y=TabH/2 (vertical mid) and x=4, we are past the r=8 top-left arc
        (arc only clips the top-left 8x8 box) and clear of the centred caption,
        so this pixel should be solid blue fill.
        R0 is rebuilt by TyTabHeaderRect at the correct ppi. }
      R0 := Acc.TyTabHeaderRect(0);
      BodyX := R0.Left + 4;           // left edge + 4 px: past arc, before text
      BodyY := (R0.Top + R0.Bottom) div 2;  // vertical midpoint: y=14 at 96ppi
      BodyPx := Reread.GetPixel(BodyX, BodyY);
      { Blue fill #0000FF: blue=255, red=0.  White would be red=255.
        No caption text at (4, 14) so blue should be full. }
      AssertTrue(
        Format('tab body is blue fill (blue>128): R=%d G=%d B=%d',
          [BodyPx.red, BodyPx.green, BodyPx.blue]),
        BodyPx.blue > 128);
      AssertTrue(
        Format('tab body not white (red<128): R=%d G=%d B=%d',
          [BodyPx.red, BodyPx.green, BodyPx.blue]),
        BodyPx.red < 128);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TTyTabControlTest);
end.
