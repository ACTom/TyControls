unit test.toolwindow.window;
{$mode objfpc}{$H+}

{ TTyToolWindow 本体：标题行与正文的切分、换主题 / 换 DPI 后重新排版、
  以及绘制与绘制缓存。几何纯函数在 test.toolwindow.geometry。 }

interface

uses
  Classes, SysUtils, Types, TypInfo, Controls, Forms, Graphics, LCLType, LMessages,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Base, tyControls.Controller, tyControls.ToolWindows,
  tyControls.ToolWindows.Layout;

type
  { 探针:数「对齐引擎被请了几次」。「换主题只重画」和「换主题真重排」在别的断言下
    读数一模一样,差别只在这里看得见。计数是真实调用路径上的,不另开一条。
    注意这个数只说明 Realign 被**请**过:无头跑的时候窗体没有句柄,AdjustSize 在
    IsControlVisible 为假时直接返回,子控件一个都不会被真正摆一遍(见
    test.pagecontrol.pas:344)。真的排一遍要自己调 CallAlignControls。 }
  TProbeWindow = class(TTyToolWindow)
  public
    AlignCount: Integer;
    procedure AdjustSize; override;
    { 绘制缓存是 protected 的,测试要能问它「下一帧要重渲染吗」——
      一个从不失效的缓存(冻在第一帧上的控件)在别的测试下全绿。 }
    function CacheWouldRender(AW, AH: Integer): Boolean;
    procedure PrimeCache(AW, AH: Integer);
    { AdjustClientRect 是 protected 的,而正文区归它管:对齐引擎排子控件时问的
      就是这一个。 }
    procedure CallAdjustClientRect(var ARect: TRect);
    { 设计期标志与抑制口都是 protected 的,而 spec §6.6 要求的正是「这两种情形下
      不发事件」—— 不开出来就只能测到发事件的那一半。 }
    procedure MarkDesigning(AOn: Boolean);
    procedure BeginSilent;
    procedure EndSilent;
    { 对齐引擎本身无头能跑 —— 自己按 LCL 的顺序(GetClientRect → AdjustClientRect →
      AlignControls)请一遍,拿到的就是真机同值。 }
    procedure CallAlignControls;
    { RenderTo 是 protected 的(画自己不是给外面用的接口)。 }
    procedure CallRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  public
    { LCL 自动拖动那一道闸放行了几次(StartLclAutoDrag 被调几次;不真的起拖)。 }
    AutoDragStarts: Integer;
    { 指针位置:无头没有句柄,PointerInClient 恒答 False。设了 FakePointer 就答 FakePoint。 }
    FakePointer: Boolean;
    FakePoint: TPoint;
    { 底栏标签行的输入(protected 的真实入口,只转发,不另算)。 }
    procedure CallMouseDown(X, Y: Integer; AShift: TShiftState = [ssLeft];
      AButton: TMouseButton = mbLeft);
    procedure CallMouseMove(X, Y: Integer; AShift: TShiftState = []);
    procedure CallMouseUp(X, Y: Integer; AButton: TMouseButton = mbLeft);
    procedure CallMouseLeave;
    procedure CallClick;
    procedure CallDblClick;
    procedure CallDoContextPopup(const APos: TPoint; var AHandled: Boolean);
    function CallDoMouseWheel(const APos: TPoint): Boolean;
    procedure CallBeginAutoDrag;
    function CallInTabRowRegion(X, Y: Integer): Boolean;
    { 真实的按下消息:Perform(LM_LBUTTONDOWN) 走 WndProc → LCL 的 WMLButtonDown → MouseDown
      整条路,「这一次按在哪」由真实代码记下。用它的测试别再另调 CallMouseDown。 }
    procedure SimulatePress(X, Y: Integer);
  protected
    procedure StartLclAutoDrag; override;
    function PointerInClient(out APoint: TPoint): Boolean; override;
  end;

  { 一个最普通的 alClient 子控件。别拿 TTyToolWindowActions 充数:Task 4 要让它变成
    「那个操作区」—— 被 GetActions 扫出来、摆进标题行、首选高喂进行高 —— 到时候用它
    当正文子控件的测试不是红就是得改写。GetStyleTypeKey 在 TTyCustomControl 上是
    abstract,不覆写就是「一解析样式就抛 EAbstractError」。 }
  TBodyChild = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
  end;

  TTyToolWindowTests = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FBar: TTyToolWindowBar;
    FWin: TProbeWindow;
    FShows, FHides: Integer;
    FLastSender: TObject;
    procedure HandleShow(ASender: TObject);
    procedure HandleHide(ASender: TObject);
    { 把标题行那一条画出来,数左右两半各有多少「墨」(非底色像素)。 }
    procedure TallyHeaderInk(out AInkLeft, AInkRight: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestBodyStartsBelowTheHeaderRow;
    procedure TestThemeChangeRelayoutsTheBody;
    procedure TestHeaderHeightFollowsThePixelDensity;
    procedure TestHeaderPaintsItsOwnSurfaceNotTheGround;
    procedure TestInvalidateDropsThePaintCache;
    procedure TestRightToLeftMovesTheCaptionToTheTrailingSide;
    procedure TestRightToLeftReachesTheHeaderLayout;
    procedure TestVisibilityFiresShowAndHideOnce;
    procedure TestDesignTimeVisibilityFiresNothing;
    procedure TestSilentVisibilitySuppressesTheEventsAndNests;
    procedure TestAnUnbalancedEndCannotBreakTheSuppression;
    procedure TestARepaintWithNothingMovedDoesNotRelayout;
    procedure TestHeaderInputScalesEverySizeWithTheGivenPpi;
    procedure TestHeaderRowPaintsItsOwnKeyNotTheWindowKey;
    procedure TestConstructionPinsTheControlStyleAndBounds;
    procedure TestBarOwnedPropertiesStayOutOfTheLfm;
    procedure TestRelayoutHeaderDropsThePaintCacheItself;
    procedure TestHeaderGeomClampsTheRowIntoTheControl;
    procedure TestANegativeHeaderTokenDoesNotWedgeTheRelayout;
    procedure TestAnAlClientChildLandsBelowTheHeaderRow;
    procedure TestAWindowThatLeftTheBarStopsRelayouting;
    procedure TestChildClassAllowedRejectsWindowsAndBars;
    { spec §3.5 / §4 / §12:标题行可选底线。 }
    procedure TestAHeaderBorderPaintsABottomRuleTheActionsStayAbove;
    procedure TestTheBaseThemeHasNoHeaderRule;
    procedure TestAThemeThatAddsOnlyTheRuleRelayouts;
  end;

{ 数一张画好的位图:非底色像素、残留底漆(见实现处)。栏的像素测试(test.toolwindow.bar)也用它。 }
procedure TallyPixels(ABmp: TBitmap; AGround, AWipe: TColor;
  out ANotGround, AWipeLeft: Integer);

type
  { .lfm 读写走的就是这一条路:栏 + 窗口 + 操作区 + 正文,读回来的样子得跟写出去的一样。 }
  TTyToolWindowStreamingTests = class(TTestCase)
  published
    procedure TestRoundTripKeepsWindowsOrderActiveAndSizes;
    procedure TestExpandedSizeStreamsOnBothSidesOfTheDefault;
    procedure TestAnInheritedFormKeepsTheWindowOrder;
  end;

implementation

function TBodyChild.GetStyleTypeKey: string;
begin
  Result := 'TyTestBodyChild';
end;

procedure TProbeWindow.AdjustSize;
begin
  Inc(AlignCount);
  inherited AdjustSize;
end;

function TProbeWindow.CacheWouldRender(AW, AH: Integer): Boolean;
begin
  Result := (FPaintCache = nil) or FPaintCache.NeedsRender(AW, AH);
end;

procedure TProbeWindow.PrimeCache(AW, AH: Integer);
begin
  if FPaintCache = nil then FPaintCache := TTyPaintCache.Create;
  FPaintCache.NeedsRender(AW, AH);   { 假装往里渲染过一帧 }
end;

procedure TProbeWindow.CallAdjustClientRect(var ARect: TRect);
begin
  AdjustClientRect(ARect);
end;

procedure TProbeWindow.MarkDesigning(AOn: Boolean);
begin
  SetDesigning(AOn, False);
end;

procedure TProbeWindow.BeginSilent;
begin
  BeginSilentVisibility;
end;

procedure TProbeWindow.EndSilent;
begin
  EndSilentVisibility;
end;

procedure TProbeWindow.CallAlignControls;
var
  r: TRect;
begin
  { 传**没扣过**的客户区:AlignControls 自己第一句就调 AdjustClientRect
    (wincontrol.inc:3259)。先扣一遍再传进去的话标题行高会扣两次,而这个错在
    「子控件在标题行下面」这句断言下看起来只是数值大了一点。 }
  r := ClientRect;
  AlignControls(nil, r);
end;

procedure TProbeWindow.CallMouseDown(X, Y: Integer; AShift: TShiftState; AButton: TMouseButton);
begin
  MouseDown(AButton, AShift, X, Y);
end;

procedure TProbeWindow.CallMouseMove(X, Y: Integer; AShift: TShiftState);
begin
  MouseMove(AShift, X, Y);
end;

procedure TProbeWindow.CallMouseUp(X, Y: Integer; AButton: TMouseButton);
begin
  MouseUp(AButton, [], X, Y);
end;

procedure TProbeWindow.CallMouseLeave;
begin
  MouseLeave;
end;

procedure TProbeWindow.CallClick;
begin
  Click;
end;

procedure TProbeWindow.CallDblClick;
begin
  DblClick;
end;

procedure TProbeWindow.CallDoContextPopup(const APos: TPoint; var AHandled: Boolean);
begin
  DoContextPopup(APos, AHandled);
end;

function TProbeWindow.CallDoMouseWheel(const APos: TPoint): Boolean;
begin
  Result := DoMouseWheel([], -120, APos);
end;

procedure TProbeWindow.CallBeginAutoDrag;
begin
  BeginAutoDrag;
end;

function TProbeWindow.CallInTabRowRegion(X, Y: Integer): Boolean;
begin
  Result := InTabRowRegion(X, Y);
end;

procedure TProbeWindow.SimulatePress(X, Y: Integer);
begin
  Perform(LM_LBUTTONDOWN, MK_LBUTTON, PtrInt((Y shl 16) or (X and $FFFF)));
end;

procedure TProbeWindow.StartLclAutoDrag;
begin
  Inc(AutoDragStarts);
end;

function TProbeWindow.PointerInClient(out APoint: TPoint): Boolean;
begin
  if FakePointer then
  begin
    APoint := FakePoint;
    Exit(True);
  end;
  Result := inherited PointerInClient(APoint);
end;

procedure TProbeWindow.CallRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

{ 把画出来的位图数两件事:
    ANotGround —— 有多少像素**不是**底色。底色就是父控件的背景,也就是工具窗口
                  自己一笔不画时会看到的那个颜色;
    AWipeLeft  —— 有多少像素还留着底漆,也就是渲染压根没碰到的地方。
  第二个数不是凑数的:没有它,「一个非底色像素都没有」这句在一张根本没画过的
  位图上也成立。只比 RGB —— pf32bit 的 GDI 位图读回来 alpha 不可信。 }
procedure TallyPixels(ABmp: TBitmap; AGround, AWipe: TColor;
  out ANotGround, AWipeLeft: Integer);
var
  re: TBGRABitmap;
  gnd, wip, px: TBGRAPixel;
  x, y: Integer;
begin
  ANotGround := 0;
  AWipeLeft := 0;
  gnd := ColorToBGRA(ColorToRGB(AGround));
  wip := ColorToBGRA(ColorToRGB(AWipe));
  re := TBGRABitmap.Create(ABmp);
  try
    for y := 0 to ABmp.Height - 1 do
      for x := 0 to ABmp.Width - 1 do
      begin
        px := re.GetPixel(x, y);
        if (px.red <> gnd.red) or (px.green <> gnd.green) or (px.blue <> gnd.blue) then
          Inc(ANotGround);
        if (px.red = wip.red) and (px.green = wip.green) and (px.blue = wip.blue) then
          Inc(AWipeLeft);
      end;
  finally
    re.Free;
  end;
end;

procedure TTyToolWindowTests.SetUp;
begin
  { 控件必须有父控件并自带 controller，否则读的是进程级主题：单跑绿、全量红。
    栏也会把 controller 推给窗口,这里两个都自己接,不靠推送链。 }
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(FForm);
  FBar := TTyToolWindowBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.Controller := FCtl;
  FBar.SetBounds(0, 0, 240, 400);
  FWin := TProbeWindow.Create(FForm);
  FWin.Parent := FBar;
  FWin.Controller := FCtl;
end;

procedure TTyToolWindowTests.TearDown;
begin
  FreeAndNil(FForm);
end;

procedure TTyToolWindowTests.HandleShow(ASender: TObject);
begin
  Inc(FShows);
  FLastSender := ASender;
end;

procedure TTyToolWindowTests.HandleHide(ASender: TObject);
begin
  Inc(FHides);
  FLastSender := ASender;
end;

procedure TTyToolWindowTests.TallyHeaderInk(out AInkLeft, AInkRight: Integer);
const
  W = 160;
  H = 60;
var
  bmp: TBitmap;
  re: TBGRABitmap;
  px: TBGRAPixel;
  x, y, hdrH, mid: Integer;
begin
  AInkLeft := 0;
  AInkRight := 0;
  hdrH := FWin.HeaderHeightPx;
  mid := W div 2;
  FWin.SetBounds(0, 0, W, H);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(W, H);
    { 按自己字体的密度渲染 —— 换成别的 PPI 的话画出来的那一条比 HeaderHeightPx 高,
      下面这个扫描框就只盖住它的上半截。 }
    FWin.CallRenderTo(bmp.Canvas, Rect(0, 0, W, H), FWin.Font.PixelsPerInch);
    re := TBGRABitmap.Create(bmp);
    try
      { 底色由上面的 StyleOverride 钉成纯白,所以标题行里任何非白像素都是字。 }
      for y := 0 to hdrH - 1 do
        for x := 0 to W - 1 do
        begin
          px := re.GetPixel(x, y);
          if (px.red = 255) and (px.green = 255) and (px.blue = 255) then Continue;
          if x < mid then Inc(AInkLeft) else Inc(AInkRight);
        end;
    finally
      re.Free;
    end;
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowTests.TestBodyStartsBelowTheHeaderRow;
var
  body: TRect;
  hdr: Integer;
begin
  FWin.SetBounds(0, 0, 200, 300);
  hdr := FWin.HeaderHeightPx;
  AssertTrue('标题行要有高度', hdr > 0);
  body := FWin.ClientRect;
  FWin.CallAdjustClientRect(body);
  AssertEquals('正文从标题行下面开始', hdr, body.Top);
  AssertEquals('标题行矩形就是上面那一条', hdr, FWin.HeaderRowRect.Bottom);
end;

procedure TTyToolWindowTests.TestThemeChangeRelayoutsTheBody;
var
  before, after: Integer;
  body: TRect;
begin
  FWin.SetBounds(0, 0, 200, 300);
  before := FWin.HeaderHeightPx;
  FWin.AlignCount := 0;
  FCtl.StyleOverride := ':root { --toolwindow-header-height: 48px; }';
  after := FWin.HeaderHeightPx;
  AssertTrue('换主题后标题行必须变高', after > before);
  body := FWin.ClientRect;
  FWin.CallAdjustClientRect(body);
  AssertEquals('正文顶跟着走', after, body.Top);
  { 换主题广播过来的只有一个裸 Invalidate(Controller.Changed)。只重画的话,
    alClient 的子控件会原地把新的标题行盖住 —— 而上面两条在「只重画」下照样绿,
    差别只在对齐引擎有没有被请过。 }
  AssertTrue('客户区内缩量变了就得请对齐引擎,不能只重画(无头跑不到真的摆一遍)',
    FWin.AlignCount > 0);
end;

procedure TTyToolWindowTests.TestHeaderHeightFollowsThePixelDensity;
var
  at96, at192: Integer;
  body: TRect;
begin
  FWin.SetBounds(0, 0, 200, 300);
  FWin.Font.PixelsPerInch := 96;
  at96 := FWin.HeaderHeightPx;
  FWin.Font.PixelsPerInch := 192;
  at192 := FWin.HeaderHeightPx;
  { 守两件事。一是「标题行高是**设备**像素」:token 不按 PPI 放大的话两次一样大。
    二是缓存键里的 PPI 那一项:Invalidate 不再手动作废缓存(608c33fc)之后,改完
    Font.PixelsPerInch 能重算全靠键里有它 —— 从键里删掉这一项,这条就红(实测过)。
    别照着早先的说法去删:那时候它确实是白写的,Invalidate 每次都顺手把缓存清掉。 }
  AssertEquals('标题行高按像素密度缩放', at96 * 2, at192);
  body := FWin.ClientRect;
  FWin.CallAdjustClientRect(body);
  AssertEquals('正文顶跟着走', at192, body.Top);
end;

procedure TTyToolWindowTests.TestHeaderPaintsItsOwnSurfaceNotTheGround;
const
  Ground = TColor($FF00FF);   { 品红。绝不能用白 —— 白就是 light 主题的表面色 }
  Wipe   = TColor($00FF00);
  W = 120;
  H = 80;
var
  bmp: TBitmap;
  notGround, wipeLeft: Integer;
begin
  { 底色是**父控件**的背景:工具窗口自己一笔不画时,看到的正是它。 }
  FCtl.StyleOverride := 'TyToolWindowBar { background: #FF00FF; }';
  FWin.SetBounds(0, 0, W, H);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(W, H);
    bmp.Canvas.Brush.Color := Wipe;
    bmp.Canvas.FillRect(0, 0, W, H);
    FWin.CallRenderTo(bmp.Canvas, Rect(0, 0, W, H), 96);
    TallyPixels(bmp, Ground, Wipe, notGround, wipeLeft);
  finally
    bmp.Free;
  end;
  AssertEquals('整块都要画到,不许留底漆', 0, wipeLeft);
  { 数「有几个」而不是「有没有」:只铺父背景、标题行那一条自己画的实现,
    「不是底色的像素 > 0」照样成立(标题行就有 W×标题行高 那么多)。 }
  AssertEquals('一个像素都不许漏出父背景', W * H, notGround);
end;

procedure TTyToolWindowTests.TestInvalidateDropsThePaintCache;
begin
  FWin.SetBounds(0, 0, 120, 80);
  FWin.PrimeCache(120, 80);
  AssertFalse('刚渲染过的缓存不用再渲染一遍', FWin.CacheWouldRender(120, 80));
  FWin.Invalidate;
  AssertTrue('自己的样子变了就得重渲染', FWin.CacheWouldRender(120, 80));
end;

procedure TTyToolWindowTests.TestRightToLeftMovesTheCaptionToTheTrailingSide;
var
  ltrL, ltrR, rtlL, rtlR: Integer;
begin
  { 钉死 96:标题行高跟着 PPI 走,机器 DPI 一高那一条就比 TallyHeaderInk 的位图还高。 }
  FWin.Font.PixelsPerInch := 96;
  FCtl.StyleOverride := 'TyToolWindow { background: #FFFFFF; }' +
    'TyToolWindowHeader { background: #FFFFFF; color: #000000; }';
  FWin.Caption := 'ABCD';
  TallyHeaderInk(ltrL, ltrR);
  AssertTrue('从左往右读:标题贴前导边,也就是左边', ltrL > ltrR);
  FWin.BiDiMode := bdRightToLeft;
  TallyHeaderInk(rtlL, rtlR);
  { 标题行的排布和画笔都要知道方向:不告诉它们,这一行就跟左右无关地停在左边。 }
  AssertTrue('从右往左读:标题换到另一边去', rtlR > rtlL);
end;

procedure TTyToolWindowTests.TestRightToLeftReachesTheHeaderLayout;
begin
  { 接线断言,不是行为断言 —— 而且是故意的:A 期标题占的是对称的那一整条,
    镜像前后同一个矩形,一个像素都证伪不了。守的是「方向确实传进了排布」,
    Task 4 的操作区一进来,镜像就是看得见的位置差。 }
  AssertFalse('默认从左往右', FWin.HeaderInput(96, 200).RightToLeft);
  FWin.BiDiMode := bdRightToLeft;
  AssertTrue('方向要传到排布那一层', FWin.HeaderInput(96, 200).RightToLeft);
end;

procedure TTyToolWindowTests.TestVisibilityFiresShowAndHideOnce;
begin
  { 切页就是开关 Visible(Task 10),所以这对事件的触发边是 CM_VISIBLECHANGED。
    栏里唯一的窗口一注册就是当前页、已经显示着(Task 5),先藏起来再挂事件。 }
  FWin.Visible := False;
  FWin.OnShow := @HandleShow;
  FWin.OnHide := @HandleHide;
  FShows := 0;
  FHides := 0;
  FLastSender := nil;
  FWin.Visible := True;
  AssertEquals('显示发一次 OnShow', 1, FShows);
  AssertEquals('显示不发 OnHide', 0, FHides);
  AssertSame('Sender 是发生这件事的那个窗口', FWin, FLastSender);
  FLastSender := nil;
  FWin.Visible := False;
  AssertEquals('隐藏发一次 OnHide', 1, FHides);
  AssertEquals('隐藏不再发 OnShow', 1, FShows);
  AssertSame('Sender 是发生这件事的那个窗口', FWin, FLastSender);
end;

procedure TTyToolWindowTests.TestDesignTimeVisibilityFiresNothing;
var
  w2: TProbeWindow;
begin
  { spec §6.6:设计期切 Visible 是设计器在点页签,不是用户眼里的显示隐藏。
    外部写 Visible 经栏路由(Task 10):设计期设 True 只激活、设 False 忽略,本身就不动
    Visible —— 所以这里让**栏**来切(它在 FBarSwitching 下真的开关 Visible),守的是
    CM_VISIBLECHANGED 里那道设计期闸。 }
  w2 := TProbeWindow.Create(FForm);
  w2.Parent := FBar;
  w2.Controller := FCtl;
  AssertFalse('前提:第二个窗口进来,FWin 藏起来了', FWin.Visible);
  FWin.OnShow := @HandleShow;
  FWin.OnHide := @HandleHide;
  FShows := 0;
  FHides := 0;
  FWin.MarkDesigning(True);
  FBar.ActiveWindow := FWin;
  AssertTrue('前提:栏真的把它显示出来了', FWin.Visible);
  FBar.ActiveWindow := w2;
  AssertFalse('前提:又藏起来了', FWin.Visible);
  AssertEquals('设计期不发 OnShow', 0, FShows);
  AssertEquals('设计期不发 OnHide', 0, FHides);
  FWin.MarkDesigning(False);
  FBar.ActiveWindow := FWin;
  AssertEquals('回到运行期照发', 1, FShows);
end;

procedure TTyToolWindowTests.TestSilentVisibilitySuppressesTheEventsAndNests;
begin
  { 栏换当前页的那一批 Visible 切换不发事件(spec §6.6);那时 csLoading 早清了,
    所以必须有一个自己的抑制口。 }
  FWin.OnShow := @HandleShow;
  FWin.OnHide := @HandleHide;
  FShows := 0;
  FHides := 0;
  FWin.BeginSilent;
  FWin.Visible := True;
  FWin.Visible := False;
  AssertEquals('抑制期间不发 OnShow', 0, FShows);
  AssertEquals('抑制期间不发 OnHide', 0, FHides);
  FWin.EndSilent;
  FWin.Visible := True;
  AssertEquals('退出抑制后照发', 1, FShows);
  { 嵌套:C 期的布局应用会套着调 Task 5 的 ActivateWindow,里层收工不许解外层的抑制。 }
  FWin.BeginSilent;
  FWin.BeginSilent;
  FWin.EndSilent;
  FWin.Visible := False;
  AssertEquals('里层收工不解外层的抑制', 0, FHides);
  FWin.EndSilent;
  FWin.Visible := True;
  AssertEquals('外层也收工了才恢复', 2, FShows);
end;

procedure TTyToolWindowTests.TestAnUnbalancedEndCannotBreakTheSuppression;
begin
  FWin.OnHide := @HandleHide;
  FHides := 0;
  FWin.Visible := True;
  { 没配对的 End 一旦把计数压到负数,后面每个 Begin 都只是从负数往回爬 ——
    抑制口再也关不上,而那时事件照发,没有一条断言会指向这里。 }
  FWin.EndSilent;
  FWin.EndSilent;
  FWin.BeginSilent;
  FWin.Visible := False;
  AssertEquals('多余的 End 不许把抑制口弄坏', 0, FHides);
  FWin.EndSilent;
  FWin.Visible := True;
  FWin.Visible := False;
  AssertEquals('配平之后照发', 1, FHides);
end;

procedure TTyToolWindowTests.TestARepaintWithNothingMovedDoesNotRelayout;
begin
  { token 为 0 时 HeaderHeightPx 钳到 1 —— 拿这个最终值跟 token 缓存比的话,两者
    永远不等,于是每一次重画(悬停、焦点、主题广播)都整控件重排一遍。 }
  FWin.SetBounds(0, 0, 200, 300);
  FCtl.StyleOverride := ':root { --toolwindow-header-height: 0px; }';
  AssertEquals('token 为 0 时标题行高钳到 1', 1, FWin.HeaderHeightPx);
  FWin.Invalidate;
  FWin.AlignCount := 0;
  FWin.Invalidate;
  AssertEquals('主题没动的重画一次都不许请对齐引擎', 0, FWin.AlignCount);
end;

procedure TTyToolWindowTests.TestHeaderInputScalesEverySizeWithTheGivenPpi;
var
  at96, at192: TTyToolWindowHeaderInput;
begin
  { 一条记录一套尺度。行高按 Font.PixelsPerInch、内距按入参 APPI 的话,真实路径上
    两者相等看不出来,而 RenderTo 收到别的 PPI 时标题行就跟内距脱节。 }
  FWin.Font.PixelsPerInch := 96;
  at96 := FWin.HeaderInput(96, 200);
  at192 := FWin.HeaderInput(192, 200);
  AssertTrue('先得真有内距,否则下面三条乘 2 都是 0 = 0', at96.Pad > 0);
  AssertTrue('先得真有行高', at96.RowHeight > 0);
  AssertEquals('内距按入参 PPI', at96.Pad * 2, at192.Pad);
  AssertEquals('间距按入参 PPI', at96.Gap * 2, at192.Gap);
  AssertEquals('行高也按入参 PPI', at96.RowHeight * 2, at192.RowHeight);
end;

procedure TTyToolWindowTests.TestHeaderRowPaintsItsOwnKeyNotTheWindowKey;
const
  W = 120;
  H = 80;
var
  bmp: TBitmap;
  re: TBGRABitmap;
  hdrPx, bodyPx: TBGRAPixel;
  hdrH: Integer;
begin
  { 两个键给**两个**底色。给同一个的话,删掉标题行那一句 FillBackground 照样绿:
    整块本来就已经是那个颜色了。 }
  { 钉死 96:标题行高跟着 PPI 走,机器 DPI 一高标题行就吃掉整张位图、取不到正文那一片。 }
  FWin.Font.PixelsPerInch := 96;
  FCtl.StyleOverride := 'TyToolWindow { background: #0000FF; }' +
    'TyToolWindowHeader { background: #FF0000; }';
  FWin.SetBounds(0, 0, W, H);
  hdrH := FWin.HeaderHeightPx;
  AssertTrue('标题行要有高度', hdrH >= 2);
  AssertTrue('底下还要留得出正文', hdrH + 2 < H);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(W, H);
    FWin.CallRenderTo(bmp.Canvas, Rect(0, 0, W, H), FWin.Font.PixelsPerInch);
    re := TBGRABitmap.Create(bmp);
    try
      { 取行正中 —— 边上有边框、圆角和抗锯齿。只比 RGB,pf32bit 读回来的 alpha 不可信。 }
      hdrPx := re.GetPixel(W div 2, hdrH div 2);
      bodyPx := re.GetPixel(W div 2, hdrH + (H - hdrH) div 2);
    finally
      re.Free;
    end;
  finally
    bmp.Free;
  end;
  AssertEquals('标题行那一条画的是 TyToolWindowHeader 的底', 255, hdrPx.red);
  AssertEquals('标题行那一条不是窗口的底', 0, hdrPx.blue);
  AssertEquals('正文那一片画的是 TyToolWindow 的底', 255, bodyPx.blue);
  AssertEquals('正文那一片不是标题行的底', 0, bodyPx.red);
end;

procedure TTyToolWindowTests.TestConstructionPinsTheControlStyleAndBounds;
var
  w: TTyToolWindow;
begin
  { 这几项掉了今天全量照样绿:设计器里摆不中、点不中,三击四击被还原成普通点击。 }
  w := TTyToolWindow.Create(FForm);
  try
    AssertTrue('要能装子控件', csAcceptsControls in w.ControlStyle);
    AssertTrue('设计器里不许拖动改尺寸 —— 位置归栏管', csDesignFixedBounds in w.ControlStyle);
    AssertTrue('不进设计器的可见控件列表', csNoDesignVisible in w.ControlStyle);
    AssertTrue('自己不抢焦点', csNoFocus in w.ControlStyle);
    AssertTrue('三击要数得到', csTripleClicks in w.ControlStyle);
    AssertTrue('四击要数得到', csQuadClicks in w.ControlStyle);
    AssertEquals('出生就铺满栏', Ord(alClient), Ord(w.Align));
    AssertFalse('出生是藏着的 —— 哪一页露头由栏说了算', w.Visible);
    AssertEquals('出生没有图标', -1, w.ImageIndex);
  finally
    w.Free;
  end;
end;

procedure TTyToolWindowTests.TestBarOwnedPropertiesStayOutOfTheLfm;
const
  BarOwned: array[0..6] of string =
    ('Left', 'Top', 'Width', 'Height', 'TabOrder', 'Visible', 'Controller');
var
  w: TTyToolWindow;
  i: Integer;
begin
  { 这七个由栏在运行期算出来;进了 .lfm 就会跟栏算的那一份漂开,而 IsStoredProp
    是流式化真正问的那一问 —— 少一个 stored False 编译器不会吭声。 }
  w := TTyToolWindow.Create(FForm);
  try
    w.Parent := FBar;
    for i := Low(BarOwned) to High(BarOwned) do
      AssertFalse(BarOwned[i] + ' 由栏说了算,不许进 .lfm', IsStoredProp(w, BarOwned[i]));
    { ImageIndex 有条件:名字是持久键,序号只在名字给不出答案时才进流。 }
    AssertFalse('没名字也没序号,不用存', IsStoredProp(w, 'ImageIndex'));
    w.ImageIndex := 3;
    AssertTrue('只有序号,存序号', IsStoredProp(w, 'ImageIndex'));
    w.ImageName := 'house';
    AssertFalse('有名字就不存序号', IsStoredProp(w, 'ImageIndex'));
  finally
    w.Free;
  end;
end;

procedure TTyToolWindowTests.TestRelayoutHeaderDropsThePaintCacheItself;
begin
  { 直接调这里的人拿不到 Invalidate 顺带丢缓存那一下 —— AutoAdjustLayout 就是这么调的。
    DPI 变了而控件尺寸没变(宽度固定的栏)时 NeedsRender 为假,运行时 Paint 会 blit 出
    旧密度的那一帧,而设计期不走缓存、看着一切正常。 }
  FWin.SetBounds(0, 0, 120, 80);
  FWin.PrimeCache(120, 80);
  AssertFalse('刚渲染过的缓存不用再渲染一遍', FWin.CacheWouldRender(120, 80));
  FWin.RelayoutHeader;
  AssertTrue('重排过就得重渲染,尺寸一个像素没动也一样', FWin.CacheWouldRender(120, 80));
end;

procedure TTyToolWindowTests.TestHeaderGeomClampsTheRowIntoTheControl;
var
  tall, squashed: TTyToolWindowHeaderGeom;
  hdr: Integer;
begin
  { 控件比标题行还矮(栏拖到很窄、或者正在动画)时行高必须钳进客户区 —— 不钳的话
    Task 4 的 CustomAlignPosition 会照着一个比控件还高的矩形把操作区摆到控件外面。 }
  FWin.Font.PixelsPerInch := 96;
  FWin.SetBounds(0, 0, 200, 300);
  hdr := FWin.HeaderHeightPx;
  AssertTrue('标题行要有高度', hdr > 4);
  { 标题占满整条行高(Caption = Rect(pad, 0, x, RowHeight)),所以 Caption.Bottom
    就是钳过的行高本身。 }
  tall := FWin.HeaderGeomAt(Rect(0, 0, 200, 300), 96);
  AssertEquals('装得下的时候就是整条', hdr, tall.Caption.Bottom);
  squashed := FWin.HeaderGeomAt(Rect(0, 0, 200, hdr - 3), 96);
  AssertEquals('装不下就钳进客户区,一个像素都不许伸出去', hdr - 3, squashed.Caption.Bottom);
  { 客户区零高是合法的(动画收到底),不许翻出负矩形。 }
  AssertEquals('零高客户区不许翻出负矩形', 0,
    FWin.HeaderGeomAt(Rect(0, 0, 200, 0), 96).Caption.Bottom);
end;

procedure TTyToolWindowTests.TestANegativeHeaderTokenDoesNotWedgeTheRelayout;
begin
  { -1px 是合法的度量值(TyEvalLength 不钳),拿 -1 当「没缓存」的哨兵就会跟它撞上:
    缓存从此永远命中不了,而且「上一次有值吗」恒假 —— 之后任何一次换主题都不再重排,
    alClient 子控件会盖住新的标题行,而这正是 RelayoutHeader 存在的理由。 }
  FWin.Font.PixelsPerInch := 96;   { 不钉死的话 48px 的 token 会按机器密度缩过再回答 }
  FWin.SetBounds(0, 0, 200, 300);
  FCtl.StyleOverride := ':root { --toolwindow-header-height: -1px; }';
  FWin.HeaderHeightPx;
  FWin.AlignCount := 0;
  FCtl.StyleOverride := ':root { --toolwindow-header-height: 48px; }';
  AssertEquals('换主题后标题行高要跟上', 48, FWin.HeaderHeightPx);
  AssertTrue('-1px 之后换主题照样要请对齐引擎', FWin.AlignCount > 0);
end;

procedure TTyToolWindowTests.TestAnAlClientChildLandsBelowTheHeaderRow;
var
  child: TBodyChild;
  hdr: Integer;
begin
  { 整条重排路径(RelayoutHeader → Realign)存在的理由就是这一条断言。对齐引擎本身
    无头能跑:按 LCL 的顺序自己请一遍就是真机同值;指望 LCL 自己排的话,窗体没有句柄、
    整棵树根本不对齐。 }
  FWin.Font.PixelsPerInch := 96;
  FWin.SetBounds(0, 0, 200, 300);
  hdr := FWin.HeaderHeightPx;
  AssertTrue('标题行要有高度', hdr > 0);
  child := TBodyChild.Create(FForm);
  child.Parent := FWin;
  child.Align := alClient;
  FWin.CallAlignControls;
  AssertEquals('alClient 子控件从标题行下面开始,不许盖住它', hdr, child.Top);
  AssertEquals('剩下的高度全归它', 300 - hdr, child.Height);
  AssertEquals('宽度整条占满', 200, child.Width);
end;

procedure TTyToolWindowTests.TestAWindowThatLeftTheBarStopsRelayouting;
begin
  { 在栏里算过一次(缓存 26、有效)之后离开栏:twhNone 若在查键之前就答 0,缓存和
    mode 键都停在 26 / twhSide,之后每次 Invalidate 都看见 0 <> 26,每次都整控件
    重排。C 期应用布局时窗口暂时脱离栏、跨栏移动的中间态都会走到。 }
  FWin.SetBounds(0, 0, 200, 300);
  AssertTrue('在栏里有标题行', FWin.HeaderHeightPx > 0);
  FWin.Parent := FForm;
  AssertEquals('离开栏就没有标题行', 0, FWin.HeaderHeightPx);
  FWin.Invalidate;           { 这一次该请:内缩量真的从一整行变成了 0 }
  FWin.AlignCount := 0;
  FWin.Invalidate;
  AssertEquals('离开过栏之后,什么都没动的重画一次都不许请对齐引擎', 0, FWin.AlignCount);
end;

procedure TTyToolWindowTests.TestChildClassAllowedRejectsWindowsAndBars;
var
  inner: TTyToolWindow;
  raised: Boolean;
begin
  { spec §3.2:防止窗口套窗口。用子类问:拿 = 比类的实现会放过 TProbeWindow 这样的派生类。 }
  AssertFalse('窗口里不许套窗口', FWin.CheckChildClassAllowed(TProbeWindow, False));
  AssertFalse('窗口里不许放栏', FWin.CheckChildClassAllowed(TTyToolWindowBar, False));
  AssertTrue('操作区照收', FWin.CheckChildClassAllowed(TTyToolWindowActions, False));
  AssertTrue('正文控件照收', FWin.CheckChildClassAllowed(TBodyChild, False));
  inner := TTyToolWindow.Create(FForm);
  raised := False;
  try
    inner.Parent := FWin;
  except
    on EInvalidOperation do raised := True;
  end;
  AssertTrue('运行时硬塞进去要被 LCL 拦下', raised);
  AssertTrue('拦下之后它不在里面', inner.Parent <> TWinControl(FWin));
end;

type
  { 流式化的根:它拥有整棵设计树(同 test.pagecontrol.streaming 的 THostForm)。 }
  TToolWindowHostForm = class(TForm)
  end;

function NewHost: TForm;
begin
  Result := TToolWindowHostForm.CreateNew(nil);
  Result.Name := 'HostForm1';
end;

function AddWindow(AHost: TComponent; ABar: TTyToolWindowBar; const AName: string): TTyToolWindow;
begin
  Result := TTyToolWindow.Create(AHost);
  Result.Name := AName;
  Result.Parent := ABar;
end;

function NewBar(AHost: TForm): TTyToolWindowBar;
begin
  Result := TTyToolWindowBar.Create(AHost);
  Result.Name := 'Bar';
  Result.Parent := AHost;
end;

function StreamText(AStream: TMemoryStream): string;
var
  txt: TStringStream;
begin
  txt := TStringStream.Create('');
  try
    AStream.Position := 0;
    ObjectBinaryToText(AStream, txt);
    Result := txt.DataString;
  finally
    txt.Free;
  end;
end;

function CountOf(const ASub, AText: string): Integer;
var
  rest: string;
  p: Integer;
begin
  Result := 0;
  rest := AText;
  p := Pos(ASub, rest);
  while p > 0 do
  begin
    Inc(Result);
    Delete(rest, 1, p + Length(ASub) - 1);
    p := Pos(ASub, rest);
  end;
end;

procedure TTyToolWindowStreamingTests.TestRoundTripKeepsWindowsOrderActiveAndSizes;
var
  src, dst: TForm;
  ms: TMemoryStream;
  ctl: TTyStyleController;
  bar, dbar: TTyToolWindowBar;
  w2: TTyToolWindow;
  act: TTyToolWindowActions;
  btn, body: TBodyChild;
  txt: string;
begin
  src := NewHost;
  dst := TToolWindowHostForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  try
    ctl := TTyStyleController.Create(src);
    ctl.Name := 'Ctl1';
    bar := NewBar(src);
    bar.Controller := ctl;
    AddWindow(src, bar, 'W1');
    w2 := AddWindow(src, bar, 'W2');
    AddWindow(src, bar, 'W3');
    act := w2.EnsureActions;
    act.Name := 'Act2';
    btn := TBodyChild.Create(src);
    btn.Name := 'ActBtn';
    btn.Parent := act;
    body := TBodyChild.Create(src);
    body.Name := 'Body2';
    body.Parent := w2;
    body.Align := alClient;
    bar.ExpandedSize := 200;
    bar.ActiveIndex := 1;
    bar.Collapsed := True;
    ms.WriteComponent(src);
    txt := StreamText(ms);
    ms.Position := 0;
    ms.ReadComponent(dst);
    dbar := dst.FindComponent('Bar') as TTyToolWindowBar;
    AssertNotNull('栏读回来了', dbar);
    AssertEquals('窗口数', 3, dbar.WindowCount);
    AssertEquals('顺序 1', 'W1', dbar.Windows[0].Name);
    AssertEquals('顺序 2', 'W2', dbar.Windows[1].Name);
    AssertEquals('顺序 3', 'W3', dbar.Windows[2].Name);
    AssertEquals('当前页序号', 1, dbar.ActiveIndex);
    AssertEquals('展开尺寸', 200, dbar.ExpandedSize);
    AssertTrue('收起标志', dbar.Collapsed);
    AssertFalse('收起着读回来,当前页也不显示', dbar.Windows[1].Visible);
    AssertNotNull('操作区跟着窗口一起流', dbar.Windows[1].Actions);
    AssertEquals('操作区里的子控件也在', 'ActBtn', dbar.Windows[1].Actions.Controls[0].Name);
    AssertTrue('正文子控件回到窗口里',
      TControl(dst.FindComponent('Body2')).Parent = TWinControl(dbar.Windows[1]));
    { Controller 不进 .lfm:读进来的时机在注册之后,两边会漂开;由栏在 fixup 时推过去。 }
    AssertEquals('Controller 只写了栏的那一个', 1, CountOf('Controller = ', txt));
    AssertSame('窗口拿到的是栏推过去的', dst.FindComponent('Ctl1'), dbar.Windows[1].Controller);
    AssertSame('操作区也是', dst.FindComponent('Ctl1'), dbar.Windows[1].Actions.Controller);
  finally
    ms.Free;
    dst.Free;
    src.Free;
  end;
end;

procedure TTyToolWindowStreamingTests.TestExpandedSizeStreamsOnBothSidesOfTheDefault;

  procedure Check(APlacement: TTyToolWindowPlacement; AValue: Integer);
  var
    src, dst: TForm;
    ms: TMemoryStream;
    bar, dbar: TTyToolWindowBar;
    tag: string;
  begin
    tag := Format('Placement %d, ExpandedSize %d: ', [Ord(APlacement), AValue]);
    src := NewHost;
    { 窗体得放得下:默认 320 × 240 的窗体里,240 的底栏连同边缘区放不下,按 spec §6.2 收窄。
      客户区尺寸随窗体流过去,读回来的那一个同样够大。 }
    src.SetBounds(0, 0, 1000, 800);
    dst := TToolWindowHostForm.CreateNew(nil);
    ms := TMemoryStream.Create;
    try
      bar := NewBar(src);
      bar.Placement := APlacement;
      AddWindow(src, bar, 'W1');
      bar.ExpandedSize := AValue;
      ms.WriteComponent(src);
      ms.Position := 0;
      ms.ReadComponent(dst);
      dbar := dst.FindComponent('Bar') as TTyToolWindowBar;
      { 等于 default 的值不写出去,读回来的是构造值 —— 两者不一致就在这里变成另一个数。 }
      AssertEquals(tag + '展开尺寸原样读回', AValue, dbar.ExpandedSize);
      AssertEquals(tag + 'Placement 原样读回', Ord(APlacement), Ord(dbar.Placement));
      { 推出来的那一边不进 .lfm,Loaded 按读回来的值重推。 }
      if APlacement = twpBottom then
        AssertEquals(tag + '高按读回来的值推', 2 * dbar.ChromeInsetPx + dbar.EdgeSizePx
          + MulDiv(AValue, dbar.Font.PixelsPerInch, 96), dbar.Height)
      else
        AssertEquals(tag + '宽按读回来的值推', dbar.StripSizePx + 2 * dbar.ChromeInsetPx
          + dbar.EdgeSizePx + MulDiv(AValue, dbar.Font.PixelsPerInch, 96), dbar.Width);
    finally
      ms.Free;
      dst.Free;
      src.Free;
    end;
  end;

begin
  Check(twpLeft, TyToolWindowDefaultExpandedSize);
  Check(twpLeft, 260);
  Check(twpBottom, TyToolWindowDefaultExpandedSize);
  Check(twpBottom, 260);
end;

procedure TTyToolWindowStreamingTests.TestAnInheritedFormKeepsTheWindowOrder;
var
  anc, desc, e: TForm;
  ancMS, descMS: TMemoryStream;
  bar, dbar, ebar: TTyToolWindowBar;
begin
  { 子孙窗体里调了继承来的窗口的顺序,写出来的是 ffChildPos;读的时候 FPC 调父控件的
    SetChildOrder(compon.inc:389)—— TWinControl 不重写它,不接的话顺序被静默丢掉。 }
  anc := NewHost;
  desc := TToolWindowHostForm.CreateNew(nil);
  e := TToolWindowHostForm.CreateNew(nil);
  ancMS := TMemoryStream.Create;
  descMS := TMemoryStream.Create;
  try
    bar := NewBar(anc);
    AddWindow(anc, bar, 'W1');
    AddWindow(anc, bar, 'W2');
    AddWindow(anc, bar, 'W3');
    ancMS.WriteComponent(anc);
    { 子孙:先按祖先读出来,再在上面把 W3 挪到最前(设计器的「移到最前」就是这一句)。 }
    ancMS.Position := 0;
    ancMS.ReadComponent(desc);
    dbar := desc.FindComponent('Bar') as TTyToolWindowBar;
    dbar.SetControlIndex(desc.FindComponent('W3') as TControl, 0);
    descMS.WriteDescendent(desc, anc);
    AssertTrue('前提:子孙流里写了子控件位置', Pos('[0]', StreamText(descMS)) > 0);
    { 加载子孙窗体 = 先读祖先那一份,再在同一个实例上读子孙那一份。 }
    ancMS.Position := 0;
    ancMS.ReadComponent(e);
    descMS.Position := 0;
    descMS.ReadComponent(e);
    ebar := e.FindComponent('Bar') as TTyToolWindowBar;
    AssertEquals('窗口数不变', 3, ebar.WindowCount);
    AssertEquals('W3 在最前', 'W3', ebar.Windows[0].Name);
    AssertEquals('W1 第二', 'W1', ebar.Windows[1].Name);
    AssertEquals('W2 第三', 'W2', ebar.Windows[2].Name);
  finally
    descMS.Free;
    ancMS.Free;
    e.Free;
    desc.Free;
    anc.Free;
  end;
end;

{ --- 标题行底线 --------------------------------------------------------------------- }

procedure TTyToolWindowTests.TestAHeaderBorderPaintsABottomRuleTheActionsStayAbove;
const
  W = 160;
  H = 120;
var
  act: TTyToolWindowActions;
  kid: TBodyChild;
  g: TTyToolWindowHeaderGeom;
  bmp: TBitmap;
  re: TBGRABitmap;
  hdrH, y, redRows: Integer;
  px: TBGRAPixel;
begin
  FWin.Font.PixelsPerInch := 96;
  FCtl.StyleOverride := 'TyToolWindowHeader { background: #0000FF; border-color: #FF0000;' +
    ' border-width: 2px; }';
  FWin.SetBounds(0, 0, W, H);
  act := FWin.EnsureActions;
  kid := TBodyChild.Create(FForm);
  kid.SetBounds(0, 0, 20, TyToolWindowHeaderHeightDef);   { 跟 token 一样高 }
  kid.Parent := act;
  hdrH := FWin.HeaderHeightPx;
  AssertEquals('行高连底线一起够操作区:token 高的控件 + 2 条带 + 底线 2',
    TyToolWindowHeaderHeightDef + 2 * TyToolWindowHeaderPadDef + 2, hdrH);
  g := FWin.HeaderGeomAt(Rect(0, 0, W, H), 96);
  AssertEquals('操作区排在底线上面:底边 = 行高 - 底线', hdrH - 2, g.Actions.Bottom);
  AssertEquals('标题同样', hdrH - 2, g.Caption.Bottom);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(W, H);
    FWin.CallRenderTo(bmp.Canvas, Rect(0, 0, W, H), 96);
    re := TBGRABitmap.Create(bmp);
    try
      redRows := 0;
      for y := 0 to hdrH - 1 do
      begin
        px := re.GetPixel(W div 4, y);
        if (px.red = 255) and (px.blue = 0) then Inc(redRows);
      end;
      AssertEquals('底线恰好 2 行', 2, redRows);
      px := re.GetPixel(W div 4, hdrH - 1);
      AssertEquals('底线在标题行最下面', 255, px.red);
      px := re.GetPixel(W div 4, hdrH - 3);
      AssertEquals('底线上面还是标题行的底', 255, px.blue);
    finally
      re.Free;
    end;
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowTests.TestTheBaseThemeHasNoHeaderRule;
var
  g: TTyToolWindowHeaderGeom;
begin
  { spec §12:底线是可选的,light 不设 —— 标题和操作区占满整条行高。 }
  FWin.Font.PixelsPerInch := 96;
  FWin.SetBounds(0, 0, 160, 120);
  g := FWin.HeaderGeomAt(Rect(0, 0, 160, 120), 96);
  AssertEquals('没有底线:标题占满行高', FWin.HeaderHeightPx, g.Caption.Bottom);
  AssertEquals('没有底线:HeaderInput 的 BottomRule 是 0', 0, FWin.HeaderInput(96, 160).BottomRule);
end;

procedure TTyToolWindowTests.TestAThemeThatAddsOnlyTheRuleRelayouts;
var
  act: TTyToolWindowActions;
  kid: TBodyChild;
  before: Integer;
begin
  FWin.Font.PixelsPerInch := 96;
  FWin.SetBounds(0, 0, 160, 120);
  act := FWin.EnsureActions;
  kid := TBodyChild.Create(FForm);
  kid.SetBounds(0, 0, 20, TyToolWindowHeaderHeightDef);
  kid.Parent := act;
  AssertEquals('前提:没有底线时行高 = 操作区 raw 高', TyToolWindowHeaderHeightDef
    + 2 * TyToolWindowHeaderPadDef, FWin.HeaderHeightPx);   { 顺带让缓存键就位 }
  before := FWin.AlignCount;
  { 只加底线、token 不变:行高因为操作区那一项变了(+2),正文得重排 —— 换主题只带来
    一次裸 Invalidate,缓存键里没有底线的话它看不出来。 }
  FCtl.StyleOverride := 'TyToolWindowHeader { border-color: #FF0000; border-width: 2px; }';
  AssertTrue('只加了底线的主题也要重排', FWin.AlignCount > before);
end;

initialization
  { 流式测试读回来时按类名实例化:工具窗口四个类在 tyControls.ToolWindows 自己的
    initialization 里注册,测试用的正文控件和控制器在这里补上。 }
  RegisterClasses([TBodyChild, TTyStyleController]);
  RegisterTest(TTyToolWindowTests);
  RegisterTest(TTyToolWindowStreamingTests);
end.
