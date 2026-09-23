unit test.toolwindow.bar;
{$mode objfpc}{$H+}

{ TTyToolWindowBar 的状态模型(spec §5 / §6.1 / §6.6):尺寸推导、Placement、注册与当前页、
  收起 / 展开、事件、推送链。流式往返在 test.toolwindow.window;需要真句柄的焦点那一半
  在 Task 10。

  无头跑的时候窗体没有句柄,LCL 自己一次都不对齐 —— 这里断言的是栏自己推导出来的尺寸
  和它答出来的客户区,不是对齐引擎摆出来的位置。 }

interface

uses
  Classes, SysUtils, Types, TypInfo, Controls, Forms, Graphics, LCLType, LCLProc, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.ToolWindows,
  tyControls.Icons.Lucide, test.toolwindow.window;

type
  { 探针:受保护的那几个入口开出来。AlignCount 数的是真实调用路径上「对齐引擎被请了
    几次」(同 TProbeWindow),不另开一条。 }
  TBarAccess = class(TTyToolWindowBar)
  public
    AlignCount: Integer;
    procedure AdjustSize; override;
    procedure SetHover(AOn: Boolean);
    { 模拟流式加载:Loading 置 csLoading,Loaded 清掉并应用读进来的值。 }
    procedure BeginLoad;
    procedure EndLoad;
    procedure CallAdjustClientRect(var ARect: TRect);
    procedure CallSetChildOrder(AChild: TComponent; AOrder: Integer);
    procedure CallBeginSilent;
    procedure CallEndSilent;
    function CallDerivedAxisPx: Integer;
    procedure CallRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { 悬停格由 Task 7 的追踪来写;这里只要「给定悬停格就画得出来」。 }
    procedure SetStripHover(AIndex: Integer);
  public
    { 窗口刚从 Controls 里摘下、还没从本栏注销的那个空档里调一次(SetParent 的继承部分
      还没返回)。 }
    OnControlRemoved: TNotifyEvent;
    procedure RemoveControl(AControl: TControl); override;
  end;

  { 设计器放下控件时,csDesigning 是在构造里(InsertComponent)从 Owner 传下来的 ——
    用一个标成设计期的 Owner 建栏,走的就是这条真实路径,不用事后补标志。 }
  TDesignOwner = class(TComponent)
  public
    procedure MarkDesigning;
  end;

  TTyToolWindowBarTests = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FBar: TBarAccess;
    FDesignOwner: TDesignOwner;
    FGapCalls: Integer;
    FChanges, FCollapses, FExpands, FShows, FHides: Integer;
    { OnChange 那一刻栏的 Width。 }
    FWidthAtChange: Integer;
    { OnShow / OnHide 的发生顺序,「show 名字;」「hide 名字;」连起来。 }
    FOrder: string;
    procedure HandleChange(ASender: TObject);
    procedure HandleChangeWidth(ASender: TObject);
    procedure HandleCollapse(ASender: TObject);
    procedure HandleExpand(ASender: TObject);
    procedure HandleShow(ASender: TObject);
    procedure HandleHide(ASender: TObject);
    function NewWindow: TProbeWindow;
    function NewWindowIn(ABar: TTyToolWindowBar; AOwner: TComponent): TProbeWindow;
    function NewDesignBar: TBarAccess;
    procedure Watch(AWin: TTyToolWindow);
    procedure ResetCounts;
    procedure HandleShowOrder(ASender: TObject);
    { 静默批次在窗口离开的空档里结束(TBarAccess.OnControlRemoved)。 }
    procedure HandleEndSilentInGap(ASender: TObject);
    procedure HandleHideOrder(ASender: TObject);
    { 栏的图标列表,里面只有 'house'。 }
    function NewHouseList: TTyLucideImageList;
    { 图标条第 AIndex 格(FBar.StripItemRect)画出来数一遍:底漆铺 AWipe,数法同 TallyPixels。
      AGround 由调用方用主题钉住(图标条的底色),这里只负责数。 }
    procedure TallyStripCell(AIndex: Integer; AGround, AWipe: TColor;
      out ANotGround, AWipeLeft: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestConstructionPinsTheStyleAndThePublishedDefaults;
    procedure TestSideWidthIsStripPlusChromePlusEdgePlusContent;
    procedure TestEmptyBarKeepsTheStripAtRunTimeAndExpandsAtDesignTime;
    procedure TestBottomHeightIsChromePlusEdgePlusContentAndZeroWhenCollapsed;
    procedure TestTheDerivedSideStaysOutOfTheLfm;
    procedure TestExpandedSizeClampsAndIsLogical;
    procedure TestThemeTokensReachTheWidthAndTheClientRect;
    procedure TestABorderedSkinCountsTwoChromes;
    procedure TestChromeComesFromTheRestingStyleNotTheHoverOne;
    procedure TestTheBarsOwnStyleOverrideReachesTheChrome;
    procedure TestARepaintWithNothingChangedDoesNotRelayout;
    procedure TestClientRectFollowsThePlacement;
    procedure TestConstrainedResizeFloorsTheSizeWithoutTouchingConstraints;
    procedure TestDesignerResizeMapsBackToExpandedSize;
    procedure TestTheBarsOwnDerivationNeverWritesBack;
    procedure TestDpiChangeRederivesWithoutWritingBack;
    procedure TestPlacementDrivesAlignAndMovesToTheOuterEdge;
    procedure TestSideToBottomIsIgnoredAtRunTimeWhileTheBarHoldsWindows;
    procedure TestHeaderModeFollowsThePlacement;
    procedure TestBarRejectsNonWindowChildren;
    procedure TestAStrayChildIsNotCountedInAnyIndex;
    procedure TestSetChildOrderMovesByWindowPositionAndActiveIndexFollows;
    procedure TestADirectZOrderChangeIsAReorderToo;
    procedure TestFirstWindowBecomesActiveAndRemovalFallsBack;
    procedure TestAReparentedActiveWindowFallsBackWithoutBeingHidden;
    procedure TestTheFirstWindowLeavingHandsOverToTheSecond;
    procedure TestRemovingAnotherWindowKeepsTheActiveOne;
    procedure TestAWindowFreedWithoutAnOwnerLeavesNoDanglingEntry;
    procedure TestRegisteringTwiceKeepsOneEntry;
    procedure TestAWindowAddedAtRunTimeBecomesActive;
    procedure TestActivatingIgnoresWindowsFromElsewhere;
    procedure TestDesignVisibleFlagIsSetBeforeVisible;
    procedure TestUserSwitchesFireChangeShowAndHide;
    procedure TestNothingFiresAtDesignTime;
    procedure TestLoadedActivatesTheStreamedIndexSilently;
    procedure TestLoadedFallsBackToTheFirstWindow;
    procedure TestCollapseHidesTheActiveWindowAndExpandShowsIt;
    procedure TestCollapsedIsAppliedAtRunTimeOnly;
    procedure TestShowControlActivatesAndExpands;
    procedure TestControllerReachesEveryWindowAndEveryActionsArea;
    procedure TestAPpiChangeReachesTheContentEvenWhenTheTokensRoundTheSame;
    procedure TestACollapsedBarsFallbackDoesNotShowTheNewActiveWindow;
    procedure TestFreeingTheActiveWindowFiresOnChange;
    procedure TestDesignerResizeSkipsLoadingAndClampsTheWriteBack;
    procedure TestChangingTheControllerOrTheStyleClassRederivesTheSize;
    procedure TestADesignTimeEmptyBottomBarIsLaidOutExpanded;
    procedure TestABottomBarFloorsItsHeight;
    procedure TestTheNewPageShowsBeforeTheOldOneHides;
    procedure TestNoBarEventFiresWhileLoading;
    procedure TestDesignTimeSwitchTellsTheDesignerButLoadedDoesNot;
    procedure TestRightAndBottomBarsGoOutsideTheirSiblings;
    procedure TestAVisibleWindowJoiningACollapsedBarIsHidden;
    procedure TestAVisibleStrayIsHiddenByTheNextSwitch;
    procedure TestASilentBatchCoversSwitchCollapseExpandAndArrivals;
    procedure TestAnExceptionInsideASilentBatchLeavesEventsAlive;
    procedure TestABatchEndingWhileAWindowIsHalfwayOutReleasesIt;
    procedure TestLoadedHidesAShownPageSilently;
    procedure TestActivatingByWindowWhileLoadingFollowsTheWindow;
    procedure TestAContentMinOnlyThemeChangeRelayouts;
    procedure TestExpandedSizeBelowTheFloorKeepsWidthOnTheDerivation;
    procedure TestOnChangeFromANewWindowSeesTheNewWidth;
    procedure TestDesignerResizeDoesNotWriteBackUnderAForeignAlign;
    { Task 6b:栏的绘制。 }
    procedure TestStripPaintsAndTheActiveItemDiffers;
    procedure TestTheIndicatorSitsOnTheContentSideOfTheActiveCellOnly;
    procedure TestAnUnresolvedNameDrawsNoIcon;
    procedure TestAHoveredCellPaintsItsHoverState;
    procedure TestAShortStripShowsTheOverflowAfterTheLastIcon;
    procedure TestTheEdgeFillsItsBandAndGoesAwayWhenCollapsed;
    procedure TestDesignTimeEmptyBarPaintsANote;
    procedure TestAStrayChildIsHiddenAtRunTime;
    procedure TestAStrayChildGetsANoteLineAtDesignTime;
    procedure TestIsActiveFollowsTheBarsCurrentPage;
  end;

implementation

const
  { 基础主题(light.tycss)里栏的类型键没有边框,chrome 为 0。 }
  StripPx = TyToolWindowStripSizeDef;
  EdgePx = TyToolWindowEdgeSizeDef;
  ContentMinPx = TyToolWindowContentMinDef;

var
  { OwnerFormDesignerModified / TyDesignerRefreshValuesProc 是进程级钩子,只能数到全局上
    (同 test.tabset)。 }
  DesignerPings: Integer;
  RefreshPings: Integer;

procedure CountDesignerModified(AComponent: TComponent);
begin
  Inc(DesignerPings);
end;

procedure CountRefresh;
begin
  Inc(RefreshPings);
end;

procedure TBarAccess.AdjustSize;
begin
  Inc(AlignCount);
  inherited AdjustSize;
end;

procedure TBarAccess.SetHover(AOn: Boolean);
begin
  FHover := AOn;
end;

procedure TBarAccess.BeginLoad;
begin
  Loading;
end;

procedure TBarAccess.EndLoad;
begin
  Loaded;
end;

procedure TBarAccess.CallAdjustClientRect(var ARect: TRect);
begin
  AdjustClientRect(ARect);
end;

procedure TBarAccess.CallSetChildOrder(AChild: TComponent; AOrder: Integer);
begin
  SetChildOrder(AChild, AOrder);
end;

procedure TBarAccess.CallBeginSilent;
begin
  BeginSilent;
end;

procedure TBarAccess.CallEndSilent;
begin
  EndSilent;
end;

procedure TBarAccess.RemoveControl(AControl: TControl);
begin
  inherited RemoveControl(AControl);
  if Assigned(OnControlRemoved) then OnControlRemoved(Self);
end;

function TBarAccess.CallDerivedAxisPx: Integer;
begin
  Result := DerivedAxisPx;
end;

procedure TBarAccess.CallRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TBarAccess.SetStripHover(AIndex: Integer);
begin
  FStripHover := AIndex;
end;

{ 把 ABar 按 AW×AH 的尺寸画出来,只留 ARegion 那一块(栏坐标):位图就是那一块的大小,
  整条栏往左上平移 ARegion 的原点再画 —— 画笔的位图落在 ARect 的左上,伸出去的部分被
  画布裁掉。先铺 AWipe 当底漆,数得出「压根没画到」的像素。调用方释放。 }
function RenderRegion(ABar: TBarAccess; AW, AH: Integer; const ARegion: TRect;
  AWipe: TColor): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf32bit;
  Result.SetSize(ARegion.Right - ARegion.Left, ARegion.Bottom - ARegion.Top);
  Result.Canvas.Brush.Color := AWipe;
  Result.Canvas.FillRect(0, 0, Result.Width, Result.Height);
  ABar.CallRenderTo(Result.Canvas,
    Rect(-ARegion.Left, -ARegion.Top, AW - ARegion.Left, AH - ARegion.Top), 96);
end;

{ 有多少像素落在「AGround 上盖一层半透明 AInk」那条混合线上(含实心的 AInk,不含纯底色)。
  着色过的图标边缘是抗锯齿的,只数和 AInk 一模一样的像素会漏掉大半 —— 细线图标在 16px
  下可能一个实心像素都没有。只比 RGB(同 TallyPixels)。 }
function CountInk(ABmp: TBitmap; AGround, AInk: TColor): Integer;
var
  re: TBGRABitmap;
  g, k, px: TBGRAPixel;
  x, y, c, best: Integer;
  gv, kv, pv: array[0..2] of Integer;
  a: Double;
  ok: Boolean;
begin
  Result := 0;
  g := ColorToBGRA(ColorToRGB(AGround));
  k := ColorToBGRA(ColorToRGB(AInk));
  gv[0] := g.red; gv[1] := g.green; gv[2] := g.blue;
  kv[0] := k.red; kv[1] := k.green; kv[2] := k.blue;
  best := 0;
  for c := 1 to 2 do
    if Abs(kv[c] - gv[c]) > Abs(kv[best] - gv[best]) then best := c;
  if kv[best] = gv[best] then Exit;
  re := TBGRABitmap.Create(ABmp);
  try
    for y := 0 to ABmp.Height - 1 do
      for x := 0 to ABmp.Width - 1 do
      begin
        px := re.GetPixel(x, y);
        pv[0] := px.red; pv[1] := px.green; pv[2] := px.blue;
        a := (pv[best] - gv[best]) / (kv[best] - gv[best]);
        if (a <= 0.01) or (a > 1.02) then Continue;
        ok := True;
        for c := 0 to 2 do
          if Abs(gv[c] + a * (kv[c] - gv[c]) - pv[c]) > 3 then ok := False;
        if ok then Inc(Result);
      end;
  finally
    re.Free;
  end;
end;

{ 颜色恰好是 AColor 的像素数。 }
function CountExact(ABmp: TBitmap; AColor: TColor): Integer;
var
  re: TBGRABitmap;
  k, px: TBGRAPixel;
  x, y: Integer;
begin
  Result := 0;
  k := ColorToBGRA(ColorToRGB(AColor));
  re := TBGRABitmap.Create(ABmp);
  try
    for y := 0 to ABmp.Height - 1 do
      for x := 0 to ABmp.Width - 1 do
      begin
        px := re.GetPixel(x, y);
        if (px.red = k.red) and (px.green = k.green) and (px.blue = k.blue) then Inc(Result);
      end;
  finally
    re.Free;
  end;
end;

function PixelIs(ABmp: TBitmap; X, Y: Integer; AColor: TColor): Boolean;
var
  re: TBGRABitmap;
  k, px: TBGRAPixel;
begin
  k := ColorToBGRA(ColorToRGB(AColor));
  re := TBGRABitmap.Create(ABmp);
  try
    px := re.GetPixel(X, Y);
    Result := (px.red = k.red) and (px.green = k.green) and (px.blue = k.blue);
  finally
    re.Free;
  end;
end;

procedure TDesignOwner.MarkDesigning;
begin
  SetDesigning(True);
end;

procedure TTyToolWindowBarTests.SetUp;
begin
  { 控件必须有父控件并自带 controller,否则读的是进程级主题:单跑绿、全量红。
    这里的数全跟着 PPI 走,无头默认不是 96 —— 窗体和栏都钉死。 }
  FForm := TForm.CreateNew(nil);
  FForm.Font.PixelsPerInch := 96;
  FForm.SetBounds(0, 0, 800, 600);
  FCtl := TTyStyleController.Create(FForm);
  FBar := TBarAccess.Create(FForm);
  FBar.Parent := FForm;
  FBar.Controller := FCtl;
  FBar.Font.PixelsPerInch := 96;
  FBar.Height := 400;
  ResetCounts;
end;

procedure TTyToolWindowBarTests.TearDown;
begin
  { 设计期的栏由它的 Owner 释放;先放它,它才从窗体的子控件里摘下来。 }
  FreeAndNil(FDesignOwner);
  FreeAndNil(FForm);
end;

procedure TTyToolWindowBarTests.HandleChange(ASender: TObject);
begin
  Inc(FChanges);
end;

procedure TTyToolWindowBarTests.HandleChangeWidth(ASender: TObject);
begin
  Inc(FChanges);
  FWidthAtChange := FBar.Width;
end;

procedure TTyToolWindowBarTests.HandleCollapse(ASender: TObject);
begin
  Inc(FCollapses);
end;

procedure TTyToolWindowBarTests.HandleExpand(ASender: TObject);
begin
  Inc(FExpands);
end;

procedure TTyToolWindowBarTests.HandleShow(ASender: TObject);
begin
  Inc(FShows);
end;

procedure TTyToolWindowBarTests.HandleHide(ASender: TObject);
begin
  Inc(FHides);
end;

procedure TTyToolWindowBarTests.ResetCounts;
begin
  FChanges := 0;
  FCollapses := 0;
  FExpands := 0;
  FShows := 0;
  FHides := 0;
end;

procedure TTyToolWindowBarTests.Watch(AWin: TTyToolWindow);
begin
  AWin.OnShow := @HandleShow;
  AWin.OnHide := @HandleHide;
end;

function TTyToolWindowBarTests.NewWindowIn(ABar: TTyToolWindowBar;
  AOwner: TComponent): TProbeWindow;
begin
  Result := TProbeWindow.Create(AOwner);
  Result.Parent := ABar;
end;

function TTyToolWindowBarTests.NewWindow: TProbeWindow;
begin
  Result := NewWindowIn(FBar, FForm);
end;

function TTyToolWindowBarTests.NewDesignBar: TBarAccess;
begin
  if FDesignOwner = nil then
  begin
    FDesignOwner := TDesignOwner.Create(nil);
    FDesignOwner.MarkDesigning;
  end;
  Result := TBarAccess.Create(FDesignOwner);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.Height := 400;
end;

procedure TTyToolWindowBarTests.TestConstructionPinsTheStyleAndThePublishedDefaults;
var
  b: TTyToolWindowBar;

  procedure CheckDefault(const AProp: string; AConstructed: Int64);
  begin
    { published default 必须等于构造值,否则 .lfm 省略的那个值加载后变成另一个数。 }
    AssertEquals(AProp + ' 的 default 等于构造值', AConstructed,
      GetPropInfo(b, AProp)^.Default);
  end;

begin
  b := TTyToolWindowBar.Create(nil);
  try
    AssertTrue('要能装窗口', csAcceptsControls in b.ControlStyle);
    AssertTrue('三击要数得到', csTripleClicks in b.ControlStyle);
    AssertTrue('四击要数得到', csQuadClicks in b.ControlStyle);
    AssertEquals('出厂展开尺寸', TyToolWindowDefaultExpandedSize, b.ExpandedSize);
    CheckDefault('ExpandedSize', b.ExpandedSize);
    CheckDefault('Placement', Ord(b.Placement));
    CheckDefault('Collapsed', Ord(b.Collapsed));
    CheckDefault('ActiveIndex', b.ActiveIndex);
    CheckDefault('Align', Ord(b.Align));
    AssertEquals('Placement 默认左', Ord(twpLeft), Ord(b.Placement));
    AssertEquals('Align 跟着 Placement', Ord(alLeft), Ord(b.Align));
  finally
    b.Free;
  end;
end;

procedure TTyToolWindowBarTests.TestSideWidthIsStripPlusChromePlusEdgePlusContent;
begin
  FBar.ExpandedSize := 200;
  NewWindow;                        { 有窗口才按展开算 }
  AssertEquals('宽 = 图标条 + 2×chrome + 边缘区 + 内容',
    StripPx + 2 * FBar.ChromeInsetPx + EdgePx + 200, FBar.Width);
  FBar.Collapsed := True;
  AssertEquals('收起 = 图标条 + 2×chrome', StripPx + 2 * FBar.ChromeInsetPx, FBar.Width);
  AssertEquals('收起不动展开尺寸', 200, FBar.ExpandedSize);
  FBar.Collapsed := False;
  AssertEquals('展开回到原宽', StripPx + 2 * FBar.ChromeInsetPx + EdgePx + 200, FBar.Width);
end;

procedure TTyToolWindowBarTests.TestEmptyBarKeepsTheStripAtRunTimeAndExpandsAtDesignTime;
var
  d: TBarAccess;
begin
  FBar.ExpandedSize := 200;
  AssertEquals('运行时没有窗口 = 只剩图标条', StripPx, FBar.Width);
  { 设计器放下的空栏:零宽 / 只剩图标条的话,既画不出提示也难点中(spec §5.4)。 }
  d := NewDesignBar;
  AssertEquals('设计期没有窗口也按展开算',
    StripPx + EdgePx + TyToolWindowDefaultExpandedSize, d.Width);
end;

procedure TTyToolWindowBarTests.TestBottomHeightIsChromePlusEdgePlusContentAndZeroWhenCollapsed;
begin
  FBar.Placement := twpBottom;         { 空栏,运行时也改得动 }
  FBar.ExpandedSize := 150;
  AssertEquals('运行时空底栏高 0', 0, FBar.Height);
  NewWindow;
  AssertEquals('高 = 2×chrome + 边缘区 + 内容(底栏没有图标条)',
    2 * FBar.ChromeInsetPx + EdgePx + 150, FBar.Height);
  FBar.Collapsed := True;
  AssertEquals('收起的底栏高 0(栏自己的 Visible 不动)', 0, FBar.Height);
  AssertTrue('Visible 是用户的属性', FBar.Visible);
end;

procedure TTyToolWindowBarTests.TestTheDerivedSideStaysOutOfTheLfm;
begin
  { IsStoredProp 是流式化真正问的那一问。 }
  AssertFalse('侧栏的宽是推出来的,不进 .lfm', IsStoredProp(FBar, 'Width'));
  AssertTrue('侧栏的高照常存', IsStoredProp(FBar, 'Height'));
  FBar.Placement := twpBottom;
  AssertTrue('底栏的宽照常存', IsStoredProp(FBar, 'Width'));
  AssertFalse('底栏的高是推出来的,不进 .lfm', IsStoredProp(FBar, 'Height'));
end;

procedure TTyToolWindowBarTests.TestExpandedSizeClampsAndIsLogical;
begin
  FBar.ExpandedSize := -5;
  AssertEquals('钳到 0', 0, FBar.ExpandedSize);
  FBar.ExpandedSize := 100000;
  AssertEquals('钳到 99999(布局串的 1-5 位)', 99999, FBar.ExpandedSize);
  FBar.ExpandedSize := 200;
  NewWindow;
  AssertEquals('96 PPI', StripPx + EdgePx + 200, FBar.Width);
  { 换字体密度只带来一次 Invalidate(FontChanged)—— 栏得在那里自己重推。 }
  FBar.Font.PixelsPerInch := 192;
  AssertEquals('展开尺寸是逻辑像素,不跟着 PPI 变', 200, FBar.ExpandedSize);
  AssertEquals('宽按 PPI 缩放', 2 * (StripPx + EdgePx + 200), FBar.Width);
end;

procedure TTyToolWindowBarTests.TestThemeTokensReachTheWidthAndTheClientRect;
var
  r: TRect;
begin
  NewWindow;
  FBar.ExpandedSize := 200;
  { 换主题只广播一次裸 Invalidate;没人调 Realign,也没人替栏重推宽度。 }
  FBar.AlignCount := 0;
  FCtl.StyleOverride := ':root { --toolwindow-strip-size: 50px; --toolwindow-edge-size: 10px; }';
  AssertEquals('宽跟着新 token', 50 + 10 + 200, FBar.Width);
  AssertTrue('内缩量变了就得请对齐引擎', FBar.AlignCount > 0);
  r := Rect(0, 0, FBar.Width, FBar.Height);
  FBar.CallAdjustClientRect(r);
  AssertEquals('内容区从图标条右边开始', 50, r.Left);
  AssertEquals('内容区到边缘区为止', FBar.Width - 10, r.Right);
end;

procedure TTyToolWindowBarTests.TestABorderedSkinCountsTwoChromes;
begin
  NewWindow;
  FBar.ExpandedSize := 200;
  FCtl.StyleOverride := 'TyToolWindowBar { border-width: 2px; }';
  { 2px 边框 + 1px 抗锯齿留量(TyChromeInsetLogical)。 }
  AssertEquals('chrome 按皮肤的边框算', 3, FBar.ChromeInsetPx);
  AssertEquals('宽里有两圈 chrome', StripPx + 2 * 3 + EdgePx + 200, FBar.Width);
  FBar.Collapsed := True;
  AssertEquals('收起也留两圈 chrome', StripPx + 2 * 3, FBar.Width);
end;

procedure TTyToolWindowBarTests.TestChromeComesFromTheRestingStyleNotTheHoverOne;
var
  rest: Integer;
begin
  NewWindow;
  FBar.ExpandedSize := 200;
  FCtl.StyleOverride := 'TyToolWindowBar { border-width: 2px; }' +
    'TyToolWindowBar:hover { border-width: 8px; }';
  rest := FBar.ChromeInsetPx;
  AssertEquals('前提:静止态有一圈 chrome', 3, rest);
  FBar.SetHover(True);
  { 悬停期间主题又变了一次:缓存键里的版本号跳了,chrome 必然重算 —— 按当前状态
    (CurrentStyle)算的实现在这里拿到的是悬停那一圈。 }
  FCtl.StyleOverride := FCtl.StyleOverride + ' :root { --toolwindow-glyph-size: 17px; }';
  AssertEquals('悬停不改内缩量', rest, FBar.ChromeInsetPx);
  AssertEquals('宽也不跟着悬停抖', StripPx + 2 * rest + EdgePx + 200, FBar.Width);
end;

procedure TTyToolWindowBarTests.TestTheBarsOwnStyleOverrideReachesTheChrome;
begin
  NewWindow;
  FBar.ExpandedSize := 200;
  AssertEquals('前提:基础主题没有 chrome', 0, FBar.ChromeInsetPx);
  { 改本控件的 StyleOverride 只带来一次裸 Invalidate,主题版本号不动。 }
  FBar.StyleOverride := 'border-width: 4px;';
  AssertEquals('chrome 叠上本控件的 StyleOverride', 5, FBar.ChromeInsetPx);
  AssertEquals('宽跟着重推', StripPx + 2 * 5 + EdgePx + 200, FBar.Width);
end;

procedure TTyToolWindowBarTests.TestARepaintWithNothingChangedDoesNotRelayout;
begin
  NewWindow;
  FBar.Invalidate;
  FBar.AlignCount := 0;
  FBar.Invalidate;
  FBar.Invalidate;
  AssertEquals('主题没动的重画一次都不许请对齐引擎', 0, FBar.AlignCount);
end;

procedure TTyToolWindowBarTests.TestClientRectFollowsThePlacement;
const
  W = 300;
  H = 200;
var
  r: TRect;
  c: Integer;
begin
  FCtl.StyleOverride := 'TyToolWindowBar { border-width: 2px; }';
  c := FBar.ChromeInsetPx;
  AssertTrue('前提:有 chrome', c > 0);
  r := Rect(0, 0, W, H);
  FBar.CallAdjustClientRect(r);
  AssertEquals('左栏:图标条在外侧(左)', c + StripPx, r.Left);
  AssertEquals('左栏:边缘区在靠编辑区一侧(右)', W - c - EdgePx, r.Right);
  AssertEquals('左栏:上 chrome', c, r.Top);
  AssertEquals('左栏:下 chrome', H - c, r.Bottom);
  FBar.Placement := twpRight;
  r := Rect(0, 0, W, H);
  FBar.CallAdjustClientRect(r);
  AssertEquals('右栏:边缘区在左', c + EdgePx, r.Left);
  AssertEquals('右栏:图标条在右', W - c - StripPx, r.Right);
  { 图标条贴哪边只看 Placement:Align 被用户改成别的也不跟着变。 }
  FBar.Align := alClient;
  r := Rect(0, 0, W, H);
  FBar.CallAdjustClientRect(r);
  AssertEquals('Align 改了,图标条还在右', W - c - StripPx, r.Right);
  FBar.Placement := twpBottom;
  r := Rect(0, 0, W, H);
  FBar.CallAdjustClientRect(r);
  AssertEquals('底栏:边缘区在顶边', c + EdgePx, r.Top);
  AssertEquals('底栏:没有图标条', c, r.Left);
  AssertEquals('底栏:右 chrome', W - c, r.Right);
  AssertEquals('底栏:下 chrome', H - c, r.Bottom);
end;

procedure TTyToolWindowBarTests.TestConstrainedResizeFloorsTheSizeWithoutTouchingConstraints;
var
  d: TBarAccess;
begin
  NewWindow;
  FBar.ExpandedSize := 200;
  FBar.SetBounds(FBar.Left, FBar.Top, 10, FBar.Height);
  AssertEquals('展开时不低于 图标条 + 边缘区 + content-min',
    StripPx + EdgePx + ContentMinPx, FBar.Width);
  AssertEquals('运行时的 SetBounds 不写回', 200, FBar.ExpandedSize);
  AssertEquals('用户的 Constraints 不碰', 0, FBar.Constraints.MinWidth);
  FBar.Collapsed := True;
  FBar.SetBounds(FBar.Left, FBar.Top, 5, FBar.Height);
  AssertEquals('收起时下限只有图标条', StripPx, FBar.Width);
  { 设计期不算收起:下限按展开的算。 }
  d := NewDesignBar;
  d.Collapsed := True;
  d.SetBounds(d.Left, d.Top, 10, d.Height);
  AssertEquals('设计期的下限按展开算', StripPx + EdgePx + ContentMinPx, d.Width);
  AssertEquals('设计期也不碰用户的 Constraints', 0, d.Constraints.MinWidth);
end;

procedure TTyToolWindowBarTests.TestDesignerResizeMapsBackToExpandedSize;
var
  d: TBarAccess;
begin
  d := NewDesignBar;
  d.SetBounds(d.Left, d.Top, StripPx + EdgePx + 300, d.Height);
  AssertEquals('设计器拖边写回 ExpandedSize(去掉图标条、边缘区、chrome)', 300, d.ExpandedSize);
  AssertEquals('宽就是推导值', StripPx + EdgePx + 300, d.Width);
  d.Placement := twpBottom;
  d.SetBounds(d.Left, d.Top, d.Width, EdgePx + 90);
  AssertEquals('底栏按高写回', 90, d.ExpandedSize);
  { 运行时的 SetBounds(对齐、代码)一律不写回。 }
  NewWindow;
  FBar.ExpandedSize := 200;
  FBar.SetBounds(FBar.Left, FBar.Top, StripPx + EdgePx + 300, FBar.Height);
  AssertEquals('运行时不写回', 200, FBar.ExpandedSize);
end;

procedure TTyToolWindowBarTests.TestTheBarsOwnDerivationNeverWritesBack;
var
  d: TBarAccess;
begin
  { 72 PPI 下 202 → 151.5 → 152px,反算回去是 202.67 → 203。推导自己的 SetBounds 要是
    也写回,改一次 ExpandedSize 就会漂一格。 }
  d := NewDesignBar;
  d.Font.PixelsPerInch := 72;
  d.ExpandedSize := 202;
  AssertEquals('推导出来的宽不许反算回 ExpandedSize', 202, d.ExpandedSize);
  AssertEquals('宽按 72 PPI 推', MulDiv(StripPx, 72, 96) + MulDiv(EdgePx, 72, 96)
    + MulDiv(202, 72, 96), d.Width);
end;

procedure TTyToolWindowBarTests.TestDpiChangeRederivesWithoutWritingBack;
var
  d: TBarAccess;
begin
  d := NewDesignBar;
  { 自己的字体:继承那一遍把它缩放到新 PPI。ParentFont 为真时 LCL 在收尾把父控件的字体
    抄回来(父控件那时还没缩放),真机上是整窗体一起缩放、父字体的通知再推一次。 }
  d.ParentFont := False;
  d.Font.PixelsPerInch := 96;
  { 203:按比例缩放是 Round(243 × 1.5) = 364(银行家舍入),按新 PPI 推是
    54 + 6 + 305 = 365 —— 缩放之后不重推,差的就是这一个像素。 }
  d.ExpandedSize := 203;
  d.AutoAdjustLayout(lapAutoAdjustForDPI, 96, 144, 0, 0);
  AssertEquals('前提:字体跟着换了密度', 144, d.Font.PixelsPerInch);
  AssertEquals('换 DPI 不写回(否则二次缩放)', 203, d.ExpandedSize);
  AssertEquals('按新 PPI 重新推', MulDiv(StripPx, 144, 96) + MulDiv(EdgePx, 144, 96)
    + MulDiv(203, 144, 96), d.Width);
end;

procedure TTyToolWindowBarTests.TestPlacementDrivesAlignAndMovesToTheOuterEdge;
var
  pnl: TBodyChild;
begin
  pnl := TBodyChild.Create(FForm);
  pnl.Parent := FForm;
  pnl.Align := alLeft;
  pnl.SetBounds(0, 0, 50, 400);
  FBar.Placement := twpRight;
  AssertEquals('右栏 → alRight', Ord(alRight), Ord(FBar.Align));
  AssertTrue('贴到父控件右边的最外边', FBar.Left + FBar.Width >= FForm.ClientWidth);
  FBar.Placement := twpLeft;
  AssertEquals('左栏 → alLeft', Ord(alLeft), Ord(FBar.Align));
  { LCL 按 Left 严格比较定同向对齐的顺序,相等时不可预测 —— 必须比兄弟更靠外。 }
  AssertTrue('排在同向对齐兄弟的外侧', FBar.Left < pnl.Left);
  FBar.Placement := twpBottom;
  AssertEquals('底栏 → alBottom', Ord(alBottom), Ord(FBar.Align));
  AssertTrue('贴到父控件底边的最外边', FBar.Top + FBar.Height >= FForm.ClientHeight);
  { 流式加载时 Align 自己也在流里,Placement 不替它改。 }
  FBar.BeginLoad;
  FBar.Placement := twpRight;
  AssertEquals('加载中不改 Align', Ord(alBottom), Ord(FBar.Align));
  FBar.EndLoad;
  AssertEquals('Placement 照样生效', Ord(twpRight), Ord(FBar.Placement));
end;

procedure TTyToolWindowBarTests.TestSideToBottomIsIgnoredAtRunTimeWhileTheBarHoldsWindows;
var
  d: TBarAccess;
begin
  NewWindow;
  FBar.Placement := twpBottom;
  AssertEquals('运行时有窗口:侧 → 底被忽略', Ord(twpLeft), Ord(FBar.Placement));
  AssertEquals('Align 也没动', Ord(alLeft), Ord(FBar.Align));
  FBar.Placement := twpRight;
  AssertEquals('侧 → 侧照改', Ord(twpRight), Ord(FBar.Placement));
  d := NewDesignBar;
  NewWindowIn(d, FDesignOwner);
  d.Placement := twpBottom;
  AssertEquals('设计期照改', Ord(twpBottom), Ord(d.Placement));
end;

procedure TTyToolWindowBarTests.TestHeaderModeFollowsThePlacement;
var
  w: TProbeWindow;
begin
  w := NewWindow;
  AssertEquals('左栏里是侧栏模式', Ord(twhSide), Ord(w.HeaderMode));
  FBar.Placement := twpRight;
  AssertEquals('右栏里也是侧栏模式', Ord(twhSide), Ord(w.HeaderMode));
  w.Parent := FForm;
  AssertEquals('不在栏里就没有标题行', Ord(twhNone), Ord(w.HeaderMode));
  FBar.Placement := twpBottom;        { 空了,运行时改得动 }
  w.Parent := FBar;
  AssertEquals('底栏里是底栏模式', Ord(twhBottom), Ord(w.HeaderMode));
end;

procedure TTyToolWindowBarTests.TestBarRejectsNonWindowChildren;
var
  stray: TBodyChild;
  raised: Boolean;
begin
  AssertFalse('栏只收工具窗口', FBar.CheckChildClassAllowed(TBodyChild, False));
  AssertFalse('操作区也不收', FBar.CheckChildClassAllowed(TTyToolWindowActions, False));
  AssertTrue('工具窗口当然收', FBar.CheckChildClassAllowed(TTyToolWindow, False));
  AssertTrue('派生的窗口类照收', FBar.CheckChildClassAllowed(TProbeWindow, False));
  stray := TBodyChild.Create(FForm);
  raised := False;
  try
    stray.Parent := FBar;
  except
    on EInvalidOperation do raised := True;
  end;
  AssertTrue('运行时硬塞进去要被 LCL 拦下', raised);
end;

procedure TTyToolWindowBarTests.TestAStrayChildIsNotCountedInAnyIndex;
var
  stray: TBodyChild;
  a, b: TProbeWindow;
begin
  { 粘贴等途径不经过 ChildClassAllowed;直接 InsertControl 就是那条路。 }
  stray := TBodyChild.Create(FForm);
  FBar.InsertControl(stray);
  a := NewWindow;
  b := NewWindow;
  AssertSame('前提:漏进来的排在 Controls 第一个', stray, FBar.Controls[0]);
  AssertEquals('不计入窗口数', 2, FBar.WindowCount);
  AssertSame('窗口序号不算它', a, FBar.Windows[0]);
  AssertEquals('当前页序号不算它', 1, FBar.ActiveIndex);
  FBar.ActiveIndex := 0;
  AssertSame('按窗口序号设当前页', a, FBar.ActiveWindow);
  AssertSame('b 是第二个', b, FBar.Windows[1]);
end;

procedure TTyToolWindowBarTests.TestSetChildOrderMovesByWindowPositionAndActiveIndexFollows;
var
  stray: TBodyChild;
  a, b, c: TProbeWindow;
begin
  stray := TBodyChild.Create(FForm);
  FBar.InsertControl(stray);
  a := NewWindow;
  b := NewWindow;
  c := NewWindow;
  FBar.ActiveWindow := b;
  FBar.OnChange := @HandleChange;
  ResetCounts;
  { ffChildPos 的 Order 是窗口序号,调 SetControlIndex 前换算成 Controls 下标(spec §2)。 }
  FBar.CallSetChildOrder(c, 0);
  AssertSame('c 到了第一个', c, FBar.Windows[0]);
  AssertSame('a 第二', a, FBar.Windows[1]);
  AssertSame('b 第三', b, FBar.Windows[2]);
  AssertSame('非窗口子控件原地不动', stray, FBar.Controls[0]);
  AssertSame('窗口顺序就是 Controls 顺序', c, FBar.Controls[1]);
  AssertSame('当前页还是 b', b, FBar.ActiveWindow);
  AssertEquals('ActiveIndex 跟着窗口身份走', 2, FBar.ActiveIndex);
  AssertEquals('只调顺序不发 OnChange', 0, FChanges);
  FBar.CallSetChildOrder(c, 5);
  AssertSame('越界放到最后', c, FBar.Windows[2]);
  AssertSame('a 回到第一个', a, FBar.Windows[0]);
  AssertEquals('ActiveIndex 又跟着变', 1, FBar.ActiveIndex);
end;

procedure TTyToolWindowBarTests.TestADirectZOrderChangeIsAReorderToo;
var
  a, b, c: TProbeWindow;
begin
  { 设计器的「移到最前 / 最后」走 SetControlIndex —— 不是虚方法,栏插不进去。
    窗口顺序就是 Controls 顺序,所以序号必须每次从 Controls 现取:缓存一份的话,
    .lfm 按 Controls 顺序写窗口、却按缓存写 ActiveIndex,读回来当前页就换了一个。 }
  a := NewWindow;
  b := NewWindow;
  c := NewWindow;
  FBar.ActiveWindow := b;
  FBar.SetControlIndex(c, 0);
  AssertSame('c 到了第一个', c, FBar.Windows[0]);
  AssertSame('a 第二', a, FBar.Windows[1]);
  AssertEquals('ActiveIndex 跟着 Controls 走', 2, FBar.ActiveIndex);
  AssertEquals('序号查询也跟着走', 0, FBar.IndexOfWindow(c));
  { 离开时回落看的也是此刻的顺序:b 在最后,没有下一个,回落到上一个 a。 }
  b.Free;
  AssertSame('按此刻的顺序回落', a, FBar.ActiveWindow);
end;

procedure TTyToolWindowBarTests.TestFirstWindowBecomesActiveAndRemovalFallsBack;
var
  a, b, c: TProbeWindow;
begin
  a := NewWindow;
  AssertSame('第一个注册进来的成为当前页', a, FBar.ActiveWindow);
  b := NewWindow;
  c := NewWindow;
  FBar.ActivateWindow(b);
  b.Free;
  AssertSame('当前页离开 → 原位置的下一个接班', c, FBar.ActiveWindow);
  AssertTrue('接班的显示出来', c.Visible);
  c.Free;
  AssertSame('没有下一个就上一个', a, FBar.ActiveWindow);
  AssertTrue('接班的显示出来', a.Visible);
  a.Free;
  AssertNull('都没了就是 nil', FBar.ActiveWindow);
  AssertEquals('空栏的 ActiveIndex 是 -1', -1, FBar.ActiveIndex);
  AssertEquals('运行时空栏只剩图标条', StripPx, FBar.Width);
end;

procedure TTyToolWindowBarTests.TestAReparentedActiveWindowFallsBackWithoutBeingHidden;
var
  a, b, c: TProbeWindow;
begin
  a := NewWindow;
  b := NewWindow;
  c := NewWindow;
  FBar.ActivateWindow(b);
  FBar.OnChange := @HandleChange;
  ResetCounts;
  b.Parent := FForm;
  AssertSame('改 Parent 离开 → 下一个接班', c, FBar.ActiveWindow);
  AssertEquals('窗口数少一个', 2, FBar.WindowCount);
  AssertEquals('当前页离开本栏发 OnChange', 1, FChanges);
  { 先置 nil 再回落:回落的切换不去碰已经离开的窗口。 }
  AssertTrue('离开的窗口不被栏藏起来', b.Visible);
  c.Parent := FForm;
  AssertSame('没有下一个就上一个', a, FBar.ActiveWindow);
end;

procedure TTyToolWindowBarTests.TestTheFirstWindowLeavingHandsOverToTheSecond;
var
  a, b, c, d: TProbeWindow;
begin
  { 「原位置上的下一个」要的是**离开前**的位置。离开的窗口这时已经不在 Controls 里了,
    位置得在它被摘下之前记住 —— 记不住就只能退成「最后一个」,那是 d 不是 b。 }
  a := NewWindow;
  b := NewWindow;
  c := NewWindow;
  d := NewWindow;
  FBar.ActivateWindow(a);
  a.Free;
  AssertSame('第一个离开 → 第二个接班(释放)', b, FBar.ActiveWindow);
  b.Parent := FForm;
  AssertSame('第一个离开 → 第二个接班(改 Parent)', c, FBar.ActiveWindow);
  AssertSame('d 还在最后', d, FBar.Windows[1]);
end;

procedure TTyToolWindowBarTests.TestRemovingAnotherWindowKeepsTheActiveOne;
var
  a, b, c: TProbeWindow;
begin
  a := NewWindow;
  b := NewWindow;
  c := NewWindow;
  FBar.ActivateWindow(c);
  FBar.OnChange := @HandleChange;
  ResetCounts;
  a.Free;
  AssertSame('当前页不变', c, FBar.ActiveWindow);
  AssertEquals('序号跟着身份走', 1, FBar.ActiveIndex);
  AssertEquals('当前页没换,不发 OnChange', 0, FChanges);
  AssertFalse('别的窗口没被显示出来', b.Visible);
end;

procedure TTyToolWindowBarTests.TestAWindowFreedWithoutAnOwnerLeavesNoDanglingEntry;
var
  w: TTyToolWindow;
begin
  { 没有 Owner 的窗口被释放,Owner 的广播到不了栏;SetParent(nil) 那时它已经
    csDestroying,注销也跳过了。靠的是注册时要的 FreeNotification。 }
  w := TTyToolWindow.Create(nil);
  w.Parent := FBar;
  AssertEquals('前提:注册上了', 1, FBar.WindowCount);
  w.Free;
  AssertEquals('释放之后表里没有它', 0, FBar.WindowCount);
  AssertNull('当前页也不再指着它', FBar.ActiveWindow);
end;

procedure TTyToolWindowBarTests.TestRegisteringTwiceKeepsOneEntry;
var
  w: TProbeWindow;
begin
  w := NewWindow;
  FBar.RegisterWindow(w);
  w.Parent := FBar;
  AssertEquals('幂等', 1, FBar.WindowCount);
  FBar.RegisterWindow(TProbeWindow.Create(FForm));
  AssertEquals('不是自己子控件的不注册', 1, FBar.WindowCount);
end;

procedure TTyToolWindowBarTests.TestAWindowAddedAtRunTimeBecomesActive;
var
  a, b: TProbeWindow;
begin
  a := NewWindow;
  FBar.OnChange := @HandleChange;
  ResetCounts;
  b := NewWindow;
  AssertSame('不在加载中注册进来的成为当前页', b, FBar.ActiveWindow);
  AssertTrue('它显示出来', b.Visible);
  AssertFalse('原来那页藏起来', a.Visible);
  AssertEquals('换了当前页发 OnChange', 1, FChanges);
end;

procedure TTyToolWindowBarTests.TestActivatingIgnoresWindowsFromElsewhere;
var
  a, other: TProbeWindow;
begin
  a := NewWindow;
  other := TProbeWindow.Create(FForm);
  other.Parent := FForm;
  FBar.ActiveWindow := other;
  AssertSame('不在本栏里的窗口被忽略', a, FBar.ActiveWindow);
  FBar.ActiveWindow := nil;
  AssertSame('nil 也被忽略', a, FBar.ActiveWindow);
  FBar.ActiveIndex := 7;
  AssertSame('越界的序号被忽略', a, FBar.ActiveWindow);
  FBar.ActiveIndex := -1;
  AssertSame('-1 也被忽略', a, FBar.ActiveWindow);
end;

procedure TTyToolWindowBarTests.TestDesignVisibleFlagIsSetBeforeVisible;
var
  a, b: TProbeWindow;
begin
  a := NewWindow;
  b := NewWindow;
  FBar.ActivateWindow(a);
  FBar.ActivateWindow(b);
  AssertFalse('新当前页写 Visible 时,csNoDesignVisible 必须已经摘掉',
    b.NoDesignVisibleAtLastShow);
  AssertTrue('旧页写 Visible 时,csNoDesignVisible 必须已经加上',
    a.NoDesignVisibleAtLastShow);
  AssertFalse('当前页最后没有这个标志', csNoDesignVisible in b.ControlStyle);
  AssertTrue('旧页最后带着这个标志', csNoDesignVisible in a.ControlStyle);
end;

procedure TTyToolWindowBarTests.TestUserSwitchesFireChangeShowAndHide;
var
  a, b: TProbeWindow;
begin
  a := NewWindow;
  b := NewWindow;
  FBar.ActivateWindow(a);
  FBar.OnChange := @HandleChange;
  Watch(a);
  Watch(b);
  ResetCounts;
  FBar.ActiveWindow := b;
  AssertEquals('换了窗口发一次 OnChange', 1, FChanges);
  AssertEquals('新页发 OnShow', 1, FShows);
  AssertEquals('旧页发 OnHide', 1, FHides);
  FBar.ActiveWindow := b;
  FBar.ActiveIndex := 1;
  AssertEquals('同一个窗口不再发', 1, FChanges);
  FBar.ActiveIndex := 0;
  AssertEquals('按序号换也发', 2, FChanges);
  AssertSame('换到了 a', a, FBar.ActiveWindow);
end;

procedure TTyToolWindowBarTests.TestNothingFiresAtDesignTime;
var
  d: TBarAccess;
  a, b: TProbeWindow;
begin
  d := NewDesignBar;
  a := NewWindowIn(d, FDesignOwner);
  b := NewWindowIn(d, FDesignOwner);
  AssertSame('设计期新建的也成为当前页', b, d.ActiveWindow);
  d.OnChange := @HandleChange;
  d.OnCollapse := @HandleCollapse;
  d.OnExpand := @HandleExpand;
  ResetCounts;
  d.ActiveWindow := a;
  AssertSame('设计期照样切', a, d.ActiveWindow);
  AssertTrue('设计期切过去的那页显示出来', a.Visible);
  AssertFalse('设计期切走的那页藏起来', b.Visible);
  d.Collapsed := True;
  d.Collapsed := False;
  AssertEquals('设计期不发 OnChange', 0, FChanges);
  AssertEquals('设计期不发 OnCollapse', 0, FCollapses);
  AssertEquals('设计期不发 OnExpand', 0, FExpands);
end;

procedure TTyToolWindowBarTests.TestLoadedActivatesTheStreamedIndexSilently;
var
  a, b, c: TProbeWindow;
begin
  FBar.BeginLoad;
  a := NewWindow;
  b := NewWindow;
  c := NewWindow;
  FBar.ActiveIndex := 1;
  FBar.OnChange := @HandleChange;
  Watch(a);
  Watch(b);
  Watch(c);
  ResetCounts;
  AssertEquals('加载中答读进来的那个数', 1, FBar.ActiveIndex);
  AssertNull('加载中还没有当前页 —— Loaded 才挑', FBar.ActiveWindow);
  AssertFalse('加载中一页都不显示', a.Visible or b.Visible or c.Visible);
  FBar.EndLoad;
  AssertSame('Loaded 应用读进来的序号', b, FBar.ActiveWindow);
  AssertTrue('当前页显示出来', b.Visible);
  AssertFalse('别的页藏着', a.Visible or c.Visible);
  AssertFalse('设计期标志也摘了', csNoDesignVisible in b.ControlStyle);
  { spec §5.1 / §6.6:csLoading 已清,但窗体的 OnCreate 还没跑。 }
  AssertEquals('Loaded 里的激活不发 OnChange', 0, FChanges);
  AssertEquals('Loaded 里的激活不发 OnShow', 0, FShows);
  AssertEquals('Loaded 里的激活不发 OnHide', 0, FHides);
  { 静默口是配平的:之后用户切页照发。 }
  FBar.ActiveWindow := c;
  AssertEquals('之后切页照发 OnChange', 1, FChanges);
  AssertEquals('之后切页照发 OnShow', 1, FShows);
  AssertEquals('之后切页照发 OnHide', 1, FHides);
end;

procedure TTyToolWindowBarTests.TestLoadedFallsBackToTheFirstWindow;
var
  a: TProbeWindow;
begin
  FBar.BeginLoad;
  a := NewWindow;
  NewWindow;
  FBar.ActiveIndex := 5;
  FBar.EndLoad;
  AssertSame('越界 → 第一个', a, FBar.ActiveWindow);
  AssertTrue('第一个显示出来', a.Visible);
  FBar.BeginLoad;
  FBar.ActiveIndex := -1;
  FBar.EndLoad;
  AssertSame('-1 → 第一个', a, FBar.ActiveWindow);
  { 空栏的 Loaded 什么都不做,也不出错。 }
  FBar.Free;
  FBar := TBarAccess.Create(FForm);
  FBar.Parent := FForm;
  FBar.BeginLoad;
  FBar.ActiveIndex := 2;
  FBar.EndLoad;
  AssertNull('空栏没有当前页', FBar.ActiveWindow);
  AssertEquals('空栏的 ActiveIndex 是 -1', -1, FBar.ActiveIndex);
end;

procedure TTyToolWindowBarTests.TestCollapseHidesTheActiveWindowAndExpandShowsIt;
var
  a, b: TProbeWindow;
begin
  a := NewWindow;
  b := NewWindow;
  FBar.OnChange := @HandleChange;
  FBar.OnCollapse := @HandleCollapse;
  FBar.OnExpand := @HandleExpand;
  Watch(a);
  Watch(b);
  ResetCounts;
  FBar.Collapsed := True;
  AssertFalse('收起藏起当前页', b.Visible);
  AssertSame('当前页保留', b, FBar.ActiveWindow);
  AssertEquals('收起发 OnHide', 1, FHides);
  AssertEquals('发一次 OnCollapse', 1, FCollapses);
  FBar.Collapsed := True;
  AssertEquals('没变就不发', 1, FCollapses);
  { 收起时 ActivateWindow 只换 FActive(spec §5.3)。 }
  FBar.ActiveWindow := a;
  AssertSame('换了当前页', a, FBar.ActiveWindow);
  AssertFalse('但不显示', a.Visible);
  AssertTrue('也不展开', FBar.Collapsed);
  AssertEquals('当前页换了窗口照发 OnChange', 1, FChanges);
  AssertEquals('没有显示就没有 OnShow', 0, FShows);
  FBar.Collapsed := False;
  AssertTrue('展开显示当前页', a.Visible);
  AssertFalse('旧页还藏着', b.Visible);
  AssertEquals('展开发 OnShow', 1, FShows);
  AssertEquals('发一次 OnExpand', 1, FExpands);
end;

procedure TTyToolWindowBarTests.TestCollapsedIsAppliedAtRunTimeOnly;
var
  d: TBarAccess;
  w, a: TProbeWindow;
begin
  { 设计期永远按展开显示:对象查看器里勾上 Collapsed,窗口照样看得见、宽照样是展开的。 }
  d := NewDesignBar;
  w := NewWindowIn(d, FDesignOwner);
  d.ExpandedSize := 200;
  d.Collapsed := True;
  AssertTrue('值照存(流式)', d.Collapsed);
  AssertTrue('设计期不藏当前页', w.Visible);
  AssertEquals('设计期按展开算宽', StripPx + EdgePx + 200, d.Width);
  { 运行时读进来的 Collapsed:加载结束时生效,一页都不显示。 }
  FBar.BeginLoad;
  FBar.Collapsed := True;
  FBar.ExpandedSize := 200;
  a := NewWindow;
  FBar.EndLoad;
  AssertSame('当前页照样有', a, FBar.ActiveWindow);
  AssertFalse('收起着不显示', a.Visible);
  AssertEquals('收起的宽', StripPx, FBar.Width);
end;

procedure TTyToolWindowBarTests.TestShowControlActivatesAndExpands;
var
  a, b: TProbeWindow;
  d: TBarAccess;
  da, db: TProbeWindow;
begin
  { TControl.Show 先问父控件 ShowControl —— 这就是它的真实入口。 }
  a := NewWindow;
  b := NewWindow;
  FBar.ActivateWindow(a);
  FBar.Collapsed := True;
  b.Show;
  AssertSame('运行时:激活', b, FBar.ActiveWindow);
  AssertFalse('并且展开', FBar.Collapsed);
  AssertTrue('显示出来', b.Visible);
  AssertFalse('旧页藏着', a.Visible);
  d := NewDesignBar;
  da := NewWindowIn(d, FDesignOwner);
  db := NewWindowIn(d, FDesignOwner);
  d.ActiveWindow := da;
  d.Collapsed := True;
  db.Show;
  AssertSame('设计期:只激活', db, d.ActiveWindow);
  AssertTrue('设计期不写 Collapsed', d.Collapsed);
end;

procedure TTyToolWindowBarTests.TestControllerReachesEveryWindowAndEveryActionsArea;
var
  w, w2: TTyToolWindow;
  a1, a2, a3: TTyToolWindowActions;
  c2: TTyStyleController;
begin
  w := NewWindow;
  AssertSame('注册时栏推给窗口', FCtl, w.Controller);
  a1 := TTyToolWindowActions.Create(FForm);
  a1.Parent := w;
  a2 := TTyToolWindowActions.Create(FForm);
  a2.Parent := w;
  AssertSame('插进来时窗口推给它', FCtl, a1.Controller);
  AssertSame('多出来的那个也推(设计期要按它画提示)', FCtl, a2.Controller);
  c2 := TTyStyleController.Create(FForm);
  FBar.Controller := c2;
  AssertSame('栏换 Controller → 窗口', c2, w.Controller);
  AssertSame('→ 第一个操作区', c2, a1.Controller);
  AssertSame('→ 每一个操作区,不只第一个', c2, a2.Controller);
  a3 := TTyToolWindowActions.Create(FForm);
  a3.Controller := FCtl;
  a3.Parent := w;
  AssertSame('后插进来、带着别的控制器的也被盖掉', c2, a3.Controller);
  w2 := TTyToolWindow.Create(FForm);
  w2.Parent := FBar;
  AssertSame('新注册的窗口拿到栏的', c2, w2.Controller);
end;

procedure TTyToolWindowBarTests.HandleShowOrder(ASender: TObject);
begin
  FOrder := FOrder + 'show ' + TComponent(ASender).Name + ';';
end;

procedure TTyToolWindowBarTests.HandleHideOrder(ASender: TObject);
begin
  FOrder := FOrder + 'hide ' + TComponent(ASender).Name + ';';
end;

procedure TTyToolWindowBarTests.TestAPpiChangeReachesTheContentEvenWhenTheTokensRoundTheSame;
begin
  { 默认 token 的底栏:没有图标条,chrome 为 0,边缘区 4px 在 100 PPI 下取整还是 4 ——
    三项主题尺寸一个都没动,而内容项 MulDiv(240, 100, 96) 从 240 变成 250。 }
  FBar.Placement := twpBottom;
  NewWindow;
  AssertEquals('前提:96 PPI 下是 边缘区 + 240', EdgePx + TyToolWindowDefaultExpandedSize, FBar.Height);
  FBar.Font.PixelsPerInch := 100;
  AssertEquals('前提:边缘区取整之后没变', EdgePx, FBar.EdgeSizePx);
  AssertEquals('内容项按新 PPI 重推', EdgePx + MulDiv(TyToolWindowDefaultExpandedSize, 100, 96),
    FBar.Height);
end;

procedure TTyToolWindowBarTests.TestACollapsedBarsFallbackDoesNotShowTheNewActiveWindow;
var
  a, b, c: TProbeWindow;
begin
  a := NewWindow;
  b := NewWindow;
  c := NewWindow;
  FBar.ActivateWindow(b);
  FBar.Collapsed := True;
  b.Free;
  AssertSame('收起着也回落到下一个', c, FBar.ActiveWindow);
  AssertFalse('栏收起着,接班的那页不显示', c.Visible);
  AssertFalse('别的页也不显示', a.Visible);
  AssertTrue('回落不展开栏', FBar.Collapsed);
  FBar.Collapsed := False;
  AssertTrue('展开时显示的是接班的那页', c.Visible);
end;

procedure TTyToolWindowBarTests.TestFreeingTheActiveWindowFiresOnChange;
var
  a, b: TProbeWindow;
begin
  a := NewWindow;
  b := NewWindow;
  FBar.OnChange := @HandleChange;
  ResetCounts;
  b.Free;
  AssertEquals('当前页被释放、有人接班:发 OnChange', 1, FChanges);
  AssertSame('接班的是 a', a, FBar.ActiveWindow);
  a.Free;
  AssertEquals('最后一页被释放、没人接班:也发', 2, FChanges);
  AssertNull('当前页是 nil', FBar.ActiveWindow);
end;

procedure TTyToolWindowBarTests.TestDesignerResizeSkipsLoadingAndClampsTheWriteBack;
var
  d: TBarAccess;
begin
  d := NewDesignBar;
  { 流式加载时读进来的边界不是用户拖出来的。 }
  d.BeginLoad;
  d.SetBounds(d.Left, d.Top, StripPx + EdgePx + 300, d.Height);
  AssertEquals('加载中的 SetBounds 不写回', TyToolWindowDefaultExpandedSize, d.ExpandedSize);
  d.EndLoad;
  AssertEquals('加载完还是原值', TyToolWindowDefaultExpandedSize, d.ExpandedSize);
  d.SetBounds(d.Left, d.Top, 10, d.Height);
  AssertEquals('写回钳到 0', 0, d.ExpandedSize);
  { 上限 99999 在 96 PPI 下是 10 万像素宽 —— LCL 设计期不许 Width >= 10000
    (control.inc:4315)。压到 8 PPI:拖到 9000px 反算是 107964,钳到 99999,
    推回来是 3 + 8333 = 8336px,摆得下。 }
  d.Font.PixelsPerInch := 8;
  d.SetBounds(d.Left, d.Top, 9000, d.Height);
  AssertEquals('写回钳到 99999(布局串的 1-5 位)', 99999, d.ExpandedSize);
  AssertEquals('宽按钳过的值推', MulDiv(StripPx, 8, 96) + MulDiv(EdgePx, 8, 96)
    + MulDiv(99999, 8, 96), d.Width);
end;

procedure TTyToolWindowBarTests.TestChangingTheControllerOrTheStyleClassRederivesTheSize;
var
  c2: TTyStyleController;
begin
  NewWindow;
  FBar.ExpandedSize := 200;
  c2 := TTyStyleController.Create(FForm);
  { 两个 model 各自数版本号 —— 让它们撞上,键里只有版本号的话缓存就把 FCtl 的值端给 c2。 }
  FCtl.StyleOverride := ':root { --toolwindow-glyph-size: 17px; }';
  c2.StyleOverride := ':root { --toolwindow-strip-size: 50px; }' +
    'TyToolWindowBar.wide { border-width: 3px; }';
  AssertEquals('前提:两个 model 的主题版本号一样', FCtl.Model.ThemeVersion, c2.Model.ThemeVersion);
  FBar.Controller := c2;
  AssertEquals('换 Controller 按新 model 重推', 50 + EdgePx + 200, FBar.Width);
  { 换 StyleClass 只带来一次裸 Invalidate,主题版本号不动。 }
  FBar.StyleClass := 'wide';
  AssertEquals('前提:新样式类给了一圈 chrome', 4, FBar.ChromeInsetPx);
  AssertEquals('换 StyleClass 重推', 50 + 2 * 4 + EdgePx + 200, FBar.Width);
end;

procedure TTyToolWindowBarTests.TestADesignTimeEmptyBottomBarIsLaidOutExpanded;
var
  d: TBarAccess;
begin
  { 零高的栏在设计器里点不中(spec §5.4)。 }
  d := NewDesignBar;
  d.Placement := twpBottom;
  AssertEquals('设计期没有窗口的底栏也按展开算',
    EdgePx + TyToolWindowDefaultExpandedSize, d.Height);
end;

procedure TTyToolWindowBarTests.TestABottomBarFloorsItsHeight;
begin
  FBar.Placement := twpBottom;
  NewWindow;
  FBar.SetBounds(FBar.Left, FBar.Top, FBar.Width, 10);
  AssertEquals('展开时不低于 边缘区 + content-min', EdgePx + ContentMinPx, FBar.Height);
  AssertEquals('用户的 Constraints 不碰', 0, FBar.Constraints.MinHeight);
  FBar.Collapsed := True;
  FBar.SetBounds(FBar.Left, FBar.Top, FBar.Width, 5);
  AssertEquals('收起的底栏没有下限', 5, FBar.Height);
end;

procedure TTyToolWindowBarTests.TestTheNewPageShowsBeforeTheOldOneHides;
var
  a, b: TProbeWindow;
begin
  { spec §5.1 第 2 步在第 3 步之前:先藏旧页的话,焦点在旧页里时 LCL 会把它交给窗体本身。 }
  a := NewWindow;
  a.Name := 'WA';
  b := NewWindow;
  b.Name := 'WB';
  FBar.ActivateWindow(a);
  a.OnShow := @HandleShowOrder;
  a.OnHide := @HandleHideOrder;
  b.OnShow := @HandleShowOrder;
  b.OnHide := @HandleHideOrder;
  FOrder := '';
  FBar.ActiveWindow := b;
  AssertEquals('先显示新页、再藏旧页', 'show WB;hide WA;', FOrder);
end;

procedure TTyToolWindowBarTests.TestNoBarEventFiresWhileLoading;
var
  a, b: TProbeWindow;
begin
  a := NewWindow;
  b := NewWindow;
  FBar.OnChange := @HandleChange;
  FBar.OnCollapse := @HandleCollapse;
  FBar.OnExpand := @HandleExpand;
  ResetCounts;
  FBar.BeginLoad;
  b.Parent := FForm;                  { 当前页在加载中离开:不回落,留给 Loaded 挑 }
  FBar.Collapsed := True;
  FBar.Collapsed := False;
  AssertNull('前提:当前页确实变了(b → 无)', FBar.ActiveWindow);
  AssertEquals('加载中不发 OnChange', 0, FChanges);
  AssertEquals('加载中不发 OnCollapse', 0, FCollapses);
  AssertEquals('加载中不发 OnExpand', 0, FExpands);
  FBar.EndLoad;
  AssertSame('Loaded 挑了剩下的那一页', a, FBar.ActiveWindow);
  AssertEquals('Loaded 也不补发', 0, FChanges);
end;

procedure TTyToolWindowBarTests.TestDesignTimeSwitchTellsTheDesignerButLoadedDoesNot;
var
  d: TBarAccess;
  a, b, ra: TProbeWindow;
  saved: TOwnerFormDesignerModifiedProc;
  savedRefresh: procedure;
begin
  { 设计期切页改了一个 published 值(ActiveIndex):两声都要 —— 一声标脏,一声让对象查看器
    重读(同 test.tabset 的 TestDesignTimeSwitchTellsTheDesigner)。打开窗体时 Loaded 的
    那一批不是修改。 }
  d := NewDesignBar;
  a := NewWindowIn(d, FDesignOwner);
  b := NewWindowIn(d, FDesignOwner);
  ra := NewWindow;
  NewWindow;                          { 运行时的第二页:它成为当前页,切到 ra 才是一次切换 }
  saved := OwnerFormDesignerModifiedProc;
  savedRefresh := TyDesignerRefreshValuesProc;
  OwnerFormDesignerModifiedProc := @CountDesignerModified;
  TyDesignerRefreshValuesProc := @CountRefresh;
  DesignerPings := 0;
  RefreshPings := 0;
  try
    d.ActiveWindow := a;
    AssertEquals('设计期切页标脏', 1, DesignerPings);
    AssertEquals('并让对象查看器重读', 1, RefreshPings);
    d.ActiveWindow := a;
    AssertEquals('同一页不再响', 1, DesignerPings);
    FBar.ActiveWindow := ra;
    AssertEquals('运行时切页不响', 1, DesignerPings);
    AssertEquals('对象查看器也不响', 1, RefreshPings);
    DesignerPings := 0;
    RefreshPings := 0;
    d.BeginLoad;
    d.ActiveIndex := 1;
    d.EndLoad;
    AssertSame('前提:Loaded 真的切了页', b, d.ActiveWindow);
    AssertEquals('Loaded 的静默批次不标脏', 0, DesignerPings);
    AssertEquals('也不让对象查看器重读', 0, RefreshPings);
  finally
    OwnerFormDesignerModifiedProc := saved;
    TyDesignerRefreshValuesProc := savedRefresh;
  end;
end;

procedure TTyToolWindowBarTests.TestRightAndBottomBarsGoOutsideTheirSiblings;
var
  pr, pb: TBodyChild;
begin
  { 同 TestPlacementDrivesAlignAndMovesToTheOuterEdge 的左栏:兄弟已经贴在边上时,
    LCL 的严格比较分不出先后,栏必须再往外一格。 }
  pr := TBodyChild.Create(FForm);
  pr.Parent := FForm;
  pr.Align := alRight;
  pr.SetBounds(FForm.ClientWidth - 50, 0, 50, 400);
  FBar.Placement := twpRight;
  AssertTrue('右栏排在同向对齐兄弟的外侧', FBar.Left + FBar.Width > pr.Left + pr.Width);
  pb := TBodyChild.Create(FForm);
  pb.Parent := FForm;
  pb.Align := alBottom;
  pb.SetBounds(0, FForm.ClientHeight - 30, 300, 30);
  FBar.Placement := twpBottom;        { 空栏,运行时改得动 }
  AssertTrue('底栏排在同向对齐兄弟的外侧', FBar.Top + FBar.Height > pb.Top + pb.Height);
end;

procedure TTyToolWindowBarTests.TestAVisibleWindowJoiningACollapsedBarIsHidden;
var
  a, w, x: TProbeWindow;
  b2: TBarAccess;
begin
  { 收起着的栏不显示任何一页(spec §5.3)。进来的窗口成为当前页,但它是带着
    Visible = True 进来的 —— 只按 (新, 旧) 成对开关的话,它就一直杵在零宽的内容区里。 }
  a := NewWindow;
  FBar.Collapsed := True;
  w := TProbeWindow.Create(FForm);
  w.Visible := True;                  { 代码里先 Visible 再 Parent }
  w.Parent := FBar;
  AssertSame('进来的成为当前页', w, FBar.ActiveWindow);
  AssertFalse('栏收起着,带着 Visible 进来的那页也得藏起来', w.Visible);
  AssertFalse('原来那页照样藏着', a.Visible);
  AssertTrue('进来不展开栏', FBar.Collapsed);
  { 把另一条展开的栏的当前页挪进收起的栏:同一个缺口的真实入口。 }
  b2 := TBarAccess.Create(FForm);
  b2.Parent := FForm;
  b2.Controller := FCtl;
  b2.Font.PixelsPerInch := 96;
  x := NewWindowIn(b2, FForm);
  AssertTrue('前提:它在原栏里显示着', x.Visible);
  x.Parent := FBar;
  AssertSame('挪进来的成为当前页', x, FBar.ActiveWindow);
  AssertFalse('挪进收起的栏:藏起来', x.Visible);
  FBar.Collapsed := False;
  AssertTrue('展开时显示的是它', x.Visible);
  AssertFalse('别的都藏着', a.Visible or w.Visible);
end;

procedure TTyToolWindowBarTests.TestAVisibleStrayIsHiddenByTheNextSwitch;
var
  a, b, c: TProbeWindow;
begin
  { 栏里除了当前页还有一页显示着(C 期应用布局挪窗口、Task 10 之前的 Visible 写入):
    下一次切页之后只剩新的当前页显示。 }
  a := NewWindow;
  b := NewWindow;
  c := NewWindow;
  a.Visible := True;
  AssertTrue('前提:两页同时显示着', a.Visible and c.Visible);
  FBar.ActiveWindow := b;
  AssertTrue('新当前页显示', b.Visible);
  AssertFalse('上一页藏起来', c.Visible);
  AssertFalse('多出来的那一页也藏起来', a.Visible);
  AssertTrue('多出来的那一页也带上设计期标志', csNoDesignVisible in a.ControlStyle);
end;

procedure TTyToolWindowBarTests.TestASilentBatchCoversSwitchCollapseExpandAndArrivals;
var
  a, b, c: TProbeWindow;
  before: Integer;
begin
  { 一个静默批次(C 期的布局应用就是这样一批)里切页、收起、展开、窗口进出,
    一个用户事件都不发;批次结束后照常发。 }
  a := NewWindow;
  b := NewWindow;
  FBar.OnChange := @HandleChange;
  FBar.OnCollapse := @HandleCollapse;
  FBar.OnExpand := @HandleExpand;
  Watch(a);
  Watch(b);
  c := TProbeWindow.Create(FForm);
  Watch(c);
  ResetCounts;
  FBar.CallBeginSilent;
  try
    FBar.ActiveWindow := a;
    FBar.Collapsed := True;
    FBar.Collapsed := False;
    c.Parent := FBar;                 { 批次中途进来:它是这一批的一部分 }
    b.Parent := FForm;                { 批次中途离开 }
  finally
    FBar.CallEndSilent;
  end;
  AssertSame('前提:批次里的切换都生效了', c, FBar.ActiveWindow);
  AssertTrue('前提:进来的那页显示着', c.Visible);
  AssertFalse('前提:a 藏起来了', a.Visible);
  AssertEquals('批次里不发 OnChange', 0, FChanges);
  AssertEquals('批次里不发 OnCollapse', 0, FCollapses);
  AssertEquals('批次里不发 OnExpand', 0, FExpands);
  AssertEquals('批次里不发 OnShow(含中途进来的)', 0, FShows);
  AssertEquals('批次里不发 OnHide', 0, FHides);
  { 解除是配平的:栏、留下的窗口、中途进来的窗口、中途离开的窗口都回到照常发。 }
  FBar.ActiveWindow := a;
  AssertEquals('之后切页照发 OnChange', 1, FChanges);
  AssertEquals('之后切页照发 OnShow', 1, FShows);
  AssertEquals('中途进来的那页之后照发 OnHide', 1, FHides);
  FBar.Collapsed := True;
  AssertEquals('之后收起照发', 1, FCollapses);
  before := FShows + FHides;
  b.Visible := not b.Visible;
  AssertEquals('中途离开的那页不再带着静默', before + 1, FShows + FHides);
end;

procedure TTyToolWindowBarTests.TestAnExceptionInsideASilentBatchLeavesEventsAlive;
var
  a, b: TProbeWindow;
  raised: Boolean;
begin
  a := NewWindow;
  b := NewWindow;
  FBar.OnChange := @HandleChange;
  Watch(a);
  Watch(b);
  ResetCounts;
  raised := False;
  try
    FBar.CallBeginSilent;
    try
      FBar.ActiveWindow := a;
      raise Exception.Create('批次中途出错');
    finally
      FBar.CallEndSilent;
    end;
  except
    on Exception do raised := True;
  end;
  AssertTrue('前提:批次里抛了异常', raised);
  AssertEquals('前提:批次里没发', 0, FChanges + FShows + FHides);
  FBar.ActiveWindow := b;
  AssertEquals('之后切页照发 OnChange', 1, FChanges);
  AssertEquals('之后切页照发 OnShow', 1, FShows);
  AssertEquals('之后切页照发 OnHide', 1, FHides);
end;

procedure TTyToolWindowBarTests.HandleEndSilentInGap(ASender: TObject);
begin
  Inc(FGapCalls);
  FBar.CallEndSilent;
end;

procedure TTyToolWindowBarTests.TestABatchEndingWhileAWindowIsHalfwayOutReleasesIt;
var
  a, b: TProbeWindow;
begin
  { 窗口离开栏分两步:先从 Controls 里摘下(RemoveControl),SetParent 返回前 / 释放路上
    Notification 到来时才注销。批次恰好在这个空档里结束,也得把它那一层还掉 —— 按
    Controls 找窗口的话找不到它,注销时批次已经结束、也不再还,它就带着一层静默去了别处,
    OnShow / OnHide 从此不响。 }
  a := NewWindow;
  b := NewWindow;
  Watch(b);
  FBar.CallBeginSilent;
  try
    FGapCalls := 0;
    FBar.OnControlRemoved := @HandleEndSilentInGap;
    try
      b.Parent := FForm;
    finally
      FBar.OnControlRemoved := nil;
    end;
  finally
    FBar.CallEndSilent;               { 空档里已经结束了的话是空操作(钳住 0) }
  end;
  AssertEquals('前提:批次在空档里结束', 1, FGapCalls);
  AssertSame('前提:a 还在栏里', FBar, a.Parent);
  ResetCounts;
  b.Visible := not b.Visible;
  AssertEquals('离开的那页不带着静默', 1, FShows + FHides);
end;

procedure TTyToolWindowBarTests.TestLoadedHidesAShownPageSilently;
var
  a, b, c: TProbeWindow;
begin
  { 窗口在加载**之前**就建好、显示着:继承窗体的第二遍加载、C 期的布局应用走的是这条路。
    Loaded 把显示着的那一页藏起来,这一下也不许发 OnHide。 }
  a := NewWindow;
  b := NewWindow;
  c := NewWindow;
  FBar.OnChange := @HandleChange;
  Watch(a);
  Watch(b);
  Watch(c);
  ResetCounts;
  AssertTrue('前提:c 是显示着的当前页', c.Visible);
  FBar.BeginLoad;
  FBar.ActiveIndex := 1;
  FBar.EndLoad;
  AssertSame('Loaded 应用读进来的序号', b, FBar.ActiveWindow);
  AssertTrue('当前页显示出来', b.Visible);
  AssertFalse('原来显示着的那页藏起来', c.Visible);
  AssertEquals('不发 OnShow', 0, FShows);
  AssertEquals('藏起原来那页也不发 OnHide', 0, FHides);
  AssertEquals('不发 OnChange', 0, FChanges);
end;

procedure TTyToolWindowBarTests.TestActivatingByWindowWhileLoadingFollowsTheWindow;
var
  a, c: TProbeWindow;
begin
  { 加载中按窗口激活:记的是窗口,不是序号 —— 之后调顺序、有窗口离开,指的还是它。 }
  FBar.BeginLoad;
  a := NewWindow;
  NewWindow;
  c := NewWindow;
  FBar.ActiveWindow := c;
  AssertNull('加载中还没有当前页', FBar.ActiveWindow);
  AssertEquals('ActiveIndex 答它此刻的序号', 2, FBar.ActiveIndex);
  FBar.SetControlIndex(c, 0);
  AssertEquals('调顺序后跟着窗口走', 0, FBar.ActiveIndex);
  a.Free;
  AssertEquals('别的窗口离开也跟着窗口走', 0, FBar.ActiveIndex);
  FBar.EndLoad;
  AssertSame('Loaded 应用的是那个窗口', c, FBar.ActiveWindow);
  AssertTrue('它显示出来', c.Visible);
end;

procedure TTyToolWindowBarTests.TestAContentMinOnlyThemeChangeRelayouts;
begin
  NewWindow;
  FBar.ExpandedSize := 200;
  FBar.AlignCount := 0;
  { 只动 content-min:另外三项主题尺寸一个没变,比较里没有它的话这一下看不出来。 }
  FCtl.StyleOverride := ':root { --toolwindow-content-min: 300px; }';
  AssertEquals('前提:新下限读到了', 300, FBar.ContentMinPx);
  AssertEquals('宽按新下限重推', StripPx + EdgePx + 300, FBar.Width);
  AssertTrue('并且请了对齐引擎', FBar.AlignCount > 0);
end;

procedure TTyToolWindowBarTests.TestExpandedSizeBelowTheFloorKeepsWidthOnTheDerivation;
begin
  NewWindow;
  FBar.ExpandedSize := 50;
  AssertEquals('ExpandedSize 照存,不被下限改写', 50, FBar.ExpandedSize);
  AssertEquals('推导值按 content-min 钳内容项', StripPx + EdgePx + ContentMinPx,
    FBar.CallDerivedAxisPx);
  AssertEquals('Width 就是推导值', FBar.CallDerivedAxisPx, FBar.Width);
  FBar.Placement := twpRight;
  AssertEquals('换一边也一样', FBar.CallDerivedAxisPx, FBar.Width);
end;

procedure TTyToolWindowBarTests.TestOnChangeFromANewWindowSeesTheNewWidth;
begin
  FBar.ExpandedSize := 200;
  AssertEquals('前提:运行时空栏只剩图标条', StripPx, FBar.Width);
  FBar.OnChange := @HandleChangeWidth;
  FWidthAtChange := -1;
  NewWindow;
  AssertEquals('前提:第一个窗口进来发了 OnChange', 1, FChanges);
  AssertEquals('OnChange 里读到的已经是展开后的宽', StripPx + EdgePx + 200, FWidthAtChange);
end;

procedure TTyToolWindowBarTests.TestDesignerResizeDoesNotWriteBackUnderAForeignAlign;
var
  d: TBarAccess;
begin
  { 用户把 Align 改成 alClient:宽是对齐引擎按父控件摆的,父控件一变就是一次 SetBounds。
    无头时 LCL 不对齐,这里直接调对齐引擎会调的那一句。 }
  d := NewDesignBar;
  d.ExpandedSize := 200;
  d.Align := alClient;
  d.SetBounds(0, 0, 700, 500);
  AssertEquals('Align 不是 Placement 要的那个:父控件变了不写回', 200, d.ExpandedSize);
  d.SetBounds(0, 0, 650, 450);
  AssertEquals('再变一次也不写回', 200, d.ExpandedSize);
  d.Align := alLeft;
  d.SetBounds(d.Left, d.Top, StripPx + EdgePx + 300, d.Height);
  AssertEquals('回到 Placement 要的 Align:拖边照常写回', 300, d.ExpandedSize);
end;

{ --- Task 6b:栏的绘制 ------------------------------------------------------- }

const
  { 品红:绝不能用白 —— 白就是 light 主题的表面色。 }
  Ground = TColor($FF00FF);
  Wipe   = TColor($00FF00);
  { TColor 是 $BBGGRR:CSS 的 #0000FF(蓝)写成 $FF0000,#FFFF00(黄)写成 $00FFFF。
    两种墨色跟品红底的混合线互不相交(蓝那条 G 恒为 0、黄那条 R 恒为 255),抗锯齿的边缘
    也分得清是哪一种。 }
  RestInk = TColor($FF0000);
  SelInk  = TColor($00FFFF);
  { 图标条钉成品红底、静止墨蓝、选中墨黄、指示条黑。 }
  StripTheme = ':root { --toolwindow-strip-bg: #FF00FF; --toolwindow-strip-ink: #0000FF;' +
    ' --toolwindow-strip-ink-selected: #FFFF00; --toolwindow-strip-indicator-color: #000000; }';

function TTyToolWindowBarTests.NewHouseList: TTyLucideImageList;
begin
  Result := TTyLucideImageList.Create(FForm);
  Result.Names.Text := 'house';
end;

procedure TTyToolWindowBarTests.TallyStripCell(AIndex: Integer; AGround, AWipe: TColor;
  out ANotGround, AWipeLeft: Integer);
var
  cell: TRect;
  bmp: TBitmap;
begin
  cell := FBar.StripItemRect(AIndex);
  AssertTrue(Format('前提:第 %d 格排上了图标条', [AIndex]),
    (cell.Right > cell.Left) and (cell.Bottom > cell.Top));
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, cell, AWipe);
  try
    TallyPixels(bmp, AGround, AWipe, ANotGround, AWipeLeft);
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowBarTests.TestStripPaintsAndTheActiveItemDiffers;
var
  a, b: TProbeWindow;
  restPix, activePix, wipeLeft: Integer;
  bmp: TBitmap;
begin
  FCtl.StyleOverride := StripTheme;
  FBar.Images := NewHouseList;
  a := NewWindow;
  a.ImageName := 'house';
  b := NewWindow;
  b.ImageName := 'house';
  FBar.ActiveWindow := a;
  { 两个窗口,当前页是第一个。分别数图标条第 1 格和第 2 格里的非底色像素。 }
  TallyStripCell(0, Ground, Wipe, activePix, wipeLeft);
  AssertEquals('整块都画到,不许留底漆', 0, wipeLeft);
  TallyStripCell(1, Ground, Wipe, restPix, wipeLeft);
  AssertEquals('静止格也整块画到', 0, wipeLeft);
  AssertTrue('图标条画了东西', restPix > 0);
  AssertTrue('当前页那一格和静止格不一样', activePix <> restPix);
  { 像素数只说明「画了不一样多的东西」(指示条就占掉这个差)—— 图标着的是哪种墨色得看颜色。 }
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, FBar.StripItemRect(0), Wipe);
  try
    AssertTrue('当前格的图标着成 :selected 的墨色', CountInk(bmp, Ground, SelInk) > 0);
    AssertEquals('当前格里没有静止态的墨色', 0, CountInk(bmp, Ground, RestInk));
  finally
    bmp.Free;
  end;
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, FBar.StripItemRect(1), Wipe);
  try
    AssertTrue('静止格的图标着成静止态的墨色', CountInk(bmp, Ground, RestInk) > 0);
    AssertEquals('静止格里没有选中墨色', 0, CountInk(bmp, Ground, SelInk));
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowBarTests.TestTheIndicatorSitsOnTheContentSideOfTheActiveCellOnly;
var
  a: TProbeWindow;
  cell: TRect;
  bmp: TBitmap;
  w, h: Integer;

  function Cell0: TBitmap;
  begin
    cell := FBar.StripItemRect(0);
    w := cell.Right - cell.Left;
    h := cell.Bottom - cell.Top;
    Result := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, cell, Wipe);
  end;

begin
  FCtl.StyleOverride := StripTheme;
  a := NewWindow;
  NewWindow;
  FBar.ActiveWindow := a;
  bmp := Cell0;
  try
    AssertEquals('指示条 = 粗细 × 格高', TyToolWindowStripIndicatorSizeDef * h,
      CountExact(bmp, clBlack));
    AssertTrue('左栏:贴在靠内容区的那一侧(右)', PixelIs(bmp, w - 1, h div 2, clBlack));
    AssertFalse('外侧没有', PixelIs(bmp, 0, h div 2, clBlack));
  finally
    bmp.Free;
  end;
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, FBar.StripItemRect(1), Wipe);
  try
    AssertEquals('静止格没有指示条', 0, CountExact(bmp, clBlack));
  finally
    bmp.Free;
  end;
  FBar.Placement := twpRight;
  bmp := Cell0;
  try
    AssertTrue('右栏:内容区在左,指示条跟着到左', PixelIs(bmp, 0, h div 2, clBlack));
    AssertFalse('右栏的外侧(右)没有', PixelIs(bmp, w - 1, h div 2, clBlack));
  finally
    bmp.Free;
  end;
  FBar.Placement := twpLeft;
  FBar.Collapsed := True;
  bmp := Cell0;
  try
    AssertEquals('收起时当前图标不画 :selected,指示条也不画(spec §5.3)', 0,
      CountExact(bmp, clBlack));
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowBarTests.TestAnUnresolvedNameDrawsNoIcon;
var
  a, b, c: TProbeWindow;
  pix, housePix, wipeLeft: Integer;
begin
  FCtl.StyleOverride := StripTheme;
  FBar.Images := NewHouseList;
  a := NewWindow;
  a.ImageName := 'house';
  b := NewWindow;
  b.ImageIndex := 0;
  AssertEquals('前提:序号当场换成了名字', 'house', b.ImageName);
  b.ImageName := 'no-such-glyph';
  AssertEquals('前提:ImageIndex 这个视图回落到写过的序号', 0, b.ImageIndex);
  AssertEquals('前提:图标条要的那一格是 -1', -1, FBar.ResolvedImageIndex(b));
  c := NewWindow;
  c.ImageName := 'house';
  FBar.ActiveWindow := a;
  TallyStripCell(2, Ground, Wipe, housePix, wipeLeft);
  AssertTrue('对照:静止格里名字找得到就画得出图标', housePix > 0);
  { 静止格没有底色、没有指示条,非底色像素只能是图标。拿窗口的 ImageIndex 画的话,这里
    画的是那个退回来的序号 —— spec §8「找不到 → -1,不许乱画一个」。 }
  TallyStripCell(1, Ground, Wipe, pix, wipeLeft);
  AssertEquals('整块都画到', 0, wipeLeft);
  AssertEquals('名字找不到:那一格一个图标像素都没有', 0, pix);
end;

procedure TTyToolWindowBarTests.TestAHoveredCellPaintsItsHoverState;
const
  Cyan = TColor($FFFF00);   { CSS #00FFFF }
var
  a: TProbeWindow;
  cell: TRect;
  bmp: TBitmap;
begin
  FCtl.StyleOverride := ':root { --toolwindow-strip-bg: #FF00FF;' +
    ' --toolwindow-overlay-hover: #00FFFF; }';
  a := NewWindow;
  NewWindow;
  FBar.ActiveWindow := a;
  cell := FBar.StripItemRect(1);
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, cell, Wipe);
  try
    AssertEquals('前提:没悬停时没有悬停底色', 0, CountExact(bmp, Cyan));
  finally
    bmp.Free;
  end;
  FBar.SetStripHover(1);
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, cell, Wipe);
  try
    AssertEquals('悬停格整格铺 :hover 的底色',
      (cell.Right - cell.Left) * (cell.Bottom - cell.Top), CountExact(bmp, Cyan));
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowBarTests.TestAShortStripShowsTheOverflowAfterTheLastIcon;
const
  ItemPx = TyToolWindowStripItemSizeDef;
var
  i: Integer;
  L: TTyToolWindowBarLayout;
  bmp: TBitmap;
begin
  FCtl.StyleOverride := ':root { --toolwindow-strip-bg: #FF00FF; --toolwindow-tab-ink: #0000FF; }';
  for i := 1 to 4 do NewWindow;         { 最后一个是当前页 }
  L := FBar.BarLayout;
  AssertEquals('前提:放得下时四个都在条上', 4, Length(L.Slots));
  AssertTrue('放得下就没有溢出按钮', L.Overflow.Bottom <= L.Overflow.Top);
  FBar.Height := 3 * ItemPx + ItemPx div 2;
  L := FBar.BarLayout;
  AssertEquals('放不下:扣掉溢出按钮后只剩两格', 2, Length(L.Slots));
  AssertEquals('当前页被留在条上', 3, L.Slots[1].ItemIndex);
  AssertTrue('有溢出按钮', L.Overflow.Bottom > L.Overflow.Top);
  AssertEquals('溢出按钮紧跟在最后一个图标后面', L.Slots[1].ItemRect.Bottom, L.Overflow.Top);
  AssertEquals('跟图标一样大', ItemPx, L.Overflow.Bottom - L.Overflow.Top);
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, L.Overflow, Wipe);
  try
    AssertTrue('溢出按钮画出了它的字形', CountInk(bmp, Ground, RestInk) > 0);
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowBarTests.TestTheEdgeFillsItsBandAndGoesAwayWhenCollapsed;
const
  Navy = TColor($800000);   { CSS #000080 }
var
  L: TTyToolWindowBarLayout;
  bmp: TBitmap;
begin
  FCtl.StyleOverride := ':root { --toolwindow-edge-color: #000080; }';
  AssertTrue('运行时空栏:边缘区不起作用', IsRectEmpty(FBar.BarLayout.Edge));
  NewWindow;
  L := FBar.BarLayout;
  AssertEquals('边缘区宽 = token', EdgePx, L.Edge.Right - L.Edge.Left);
  AssertEquals('左栏的边缘区贴右边(靠编辑区)', FBar.ClientWidth, L.Edge.Right);
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, L.Edge, Wipe);
  try
    AssertEquals('整条铺边缘区的底色', (L.Edge.Right - L.Edge.Left) * (L.Edge.Bottom - L.Edge.Top),
      CountExact(bmp, Navy));
  finally
    bmp.Free;
  end;
  FBar.Collapsed := True;
  AssertTrue('收起:边缘区不起作用,也不画', IsRectEmpty(FBar.BarLayout.Edge));
end;

procedure TTyToolWindowBarTests.TestDesignTimeEmptyBarPaintsANote;
var
  d: TBarAccess;
  L: TTyToolWindowBarLayout;
  bmp: TBitmap;
  pix, wipeLeft: Integer;
begin
  FCtl.StyleOverride := 'TyToolWindowBar { background: #FF00FF; }';
  d := NewDesignBar;
  L := d.BarLayout;
  AssertFalse('设计期空栏有提示框', IsRectEmpty(L.EmptyNote));
  bmp := RenderRegion(d, d.ClientWidth, d.ClientHeight, L.EmptyNote, Wipe);
  try
    TallyPixels(bmp, Ground, Wipe, pix, wipeLeft);
  finally
    bmp.Free;
  end;
  AssertEquals('整块都画到', 0, wipeLeft);
  AssertTrue('设计期没有窗口:画出提示文字', pix > 0);
  { 运行时同一个位置(按设计期那么大画)一个字都没有。 }
  AssertTrue('运行时没有提示框', IsRectEmpty(FBar.BarLayout.EmptyNote));
  bmp := RenderRegion(FBar, d.ClientWidth, d.ClientHeight, L.EmptyNote, Wipe);
  try
    TallyPixels(bmp, Ground, Wipe, pix, wipeLeft);
  finally
    bmp.Free;
  end;
  AssertEquals('运行时也整块画到', 0, wipeLeft);
  AssertEquals('运行时不画提示', 0, pix);
end;

procedure TTyToolWindowBarTests.TestAStrayChildIsHiddenAtRunTime;
var
  stray: TBodyChild;
  r: TRect;
  bottom: Integer;
begin
  NewWindow;
  r := FBar.ClientRect;
  FBar.CallAdjustClientRect(r);
  bottom := r.Bottom;
  stray := TBodyChild.Create(FForm);
  AssertTrue('前提:新建的控件是可见的', stray.Visible);
  { 粘贴等途径不经过 ChildClassAllowed;直接 InsertControl 就是那条路。 }
  FBar.InsertControl(stray);
  AssertFalse('运行时漏进来的非窗口子控件藏起来(spec §6.1)', stray.Visible);
  AssertTrue('运行时不让提示行', IsRectEmpty(FBar.BarLayout.StrayNote));
  r := FBar.ClientRect;
  FBar.CallAdjustClientRect(r);
  AssertEquals('窗口的内容区不变', bottom, r.Bottom);
end;

procedure TTyToolWindowBarTests.TestAStrayChildGetsANoteLineAtDesignTime;
var
  d: TBarAccess;
  stray: TBodyChild;
  full, r: TRect;
  L: TTyToolWindowBarLayout;
  bmp: TBitmap;
  pix, wipeLeft: Integer;
begin
  FCtl.StyleOverride := 'TyToolWindowBar { background: #FF00FF; }';
  d := NewDesignBar;
  NewWindowIn(d, FDesignOwner);
  full := d.ClientRect;
  d.CallAdjustClientRect(full);
  AssertTrue('前提:没有漏进来的就不让提示行', IsRectEmpty(d.BarLayout.StrayNote));
  stray := TBodyChild.Create(FDesignOwner);
  d.InsertControl(stray);
  AssertTrue('设计期不藏:用户得看得见它、删得掉它', stray.Visible);
  L := d.BarLayout;
  AssertFalse('设计期让出一行提示', IsRectEmpty(L.StrayNote));
  AssertEquals('提示行贴在原来内容区的底边', full.Bottom, L.StrayNote.Bottom);
  { 不让出来的话当前页(alClient)整个盖在内容区上,提示一个像素都露不出来。 }
  r := d.ClientRect;
  d.CallAdjustClientRect(r);
  AssertEquals('窗口的内容区停在提示行上面', L.StrayNote.Top, r.Bottom);
  bmp := RenderRegion(d, d.ClientWidth, d.ClientHeight, L.StrayNote, Wipe);
  try
    TallyPixels(bmp, Ground, Wipe, pix, wipeLeft);
  finally
    bmp.Free;
  end;
  AssertEquals('整块都画到', 0, wipeLeft);
  AssertTrue('提示行里画了字', pix > 0);
  stray.Free;
  AssertTrue('它走了,提示行也走', IsRectEmpty(d.BarLayout.StrayNote));
  r := d.ClientRect;
  d.CallAdjustClientRect(r);
  AssertEquals('内容区还给窗口', full.Bottom, r.Bottom);
end;

procedure TTyToolWindowBarTests.TestIsActiveFollowsTheBarsCurrentPage;
var
  a, b, orphan: TProbeWindow;
begin
  a := NewWindow;
  b := NewWindow;
  AssertTrue('后进来的是当前页', b.IsActive);
  AssertFalse('另一页不是', a.IsActive);
  FBar.ActiveWindow := a;
  AssertTrue('切页之后跟着换', a.IsActive);
  AssertFalse('换下来的不再是', b.IsActive);
  FBar.Collapsed := True;
  AssertTrue('收起着,栏认的当前页还是它', a.IsActive);
  orphan := TProbeWindow.Create(FForm);
  AssertFalse('不在栏里的窗口不是任何栏的当前页', orphan.IsActive);
end;

initialization
  RegisterTest(TTyToolWindowBarTests);
end.
