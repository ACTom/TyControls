unit test.toolwindow.bar;
{$mode objfpc}{$H+}

{ TTyToolWindowBar 的状态模型(spec §5 / §6.1 / §6.6):尺寸推导、Placement、注册与当前页、
  收起 / 展开、事件、推送链。流式往返在 test.toolwindow.window;需要真句柄的焦点那一半
  在 Task 10。

  无头跑的时候窗体没有句柄,LCL 自己一次都不对齐 —— 这里断言的是栏自己推导出来的尺寸
  和它答出来的客户区,不是对齐引擎摆出来的位置。 }

interface

uses
  Classes, SysUtils, Types, TypInfo, Controls, Forms, LCLType, LCLProc, fpcunit, testregistry,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.ToolWindows,
  test.toolwindow.window;

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
    FChanges, FCollapses, FExpands, FShows, FHides: Integer;
    { OnShow / OnHide 的发生顺序,「show 名字;」「hide 名字;」连起来。 }
    FOrder: string;
    procedure HandleChange(ASender: TObject);
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
    procedure HandleHideOrder(ASender: TObject);
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
  b.Parent := FForm;                  { 当前页在加载中离开:只换 FActive }
  FBar.Collapsed := True;
  FBar.Collapsed := False;
  AssertSame('前提:当前页确实换了', a, FBar.ActiveWindow);
  AssertEquals('加载中不发 OnChange', 0, FChanges);
  AssertEquals('加载中不发 OnCollapse', 0, FCollapses);
  AssertEquals('加载中不发 OnExpand', 0, FExpands);
  FBar.EndLoad;
  AssertEquals('Loaded 也不补发', 0, FChanges);
end;

procedure TTyToolWindowBarTests.TestDesignTimeSwitchTellsTheDesignerButLoadedDoesNot;
var
  d: TBarAccess;
  a, b, ra, rb: TProbeWindow;
  saved: TOwnerFormDesignerModifiedProc;
begin
  { 设计期切页改了一个 published 值(ActiveIndex):两声都要 —— 一声标脏,一声让对象查看器
    重读(同 test.tabset 的 TestDesignTimeSwitchTellsTheDesigner)。打开窗体时 Loaded 的
    那一批不是修改。 }
  d := NewDesignBar;
  a := NewWindowIn(d, FDesignOwner);
  b := NewWindowIn(d, FDesignOwner);
  ra := NewWindow;
  rb := NewWindow;
  saved := OwnerFormDesignerModifiedProc;
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
    TyDesignerRefreshValuesProc := nil;
  end;
  AssertTrue('rb 只是凑一个运行时的第二页', rb <> nil);
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

initialization
  RegisterTest(TTyToolWindowBarTests);
end.
