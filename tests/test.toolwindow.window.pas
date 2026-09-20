unit test.toolwindow.window;
{$mode objfpc}{$H+}

{ TTyToolWindow 本体：标题行与正文的切分、换主题 / 换 DPI 后重新排版、
  以及绘制与绘制缓存。几何纯函数在 test.toolwindow.geometry。 }

interface

uses
  Classes, SysUtils, Types, TypInfo, Controls, Forms, Graphics, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Base, tyControls.Controller, tyControls.ToolWindows;

type
  { 探针:数对齐引擎被请了几次。「换主题只重画」和「换主题真重排」在别的断言下
    读数一模一样,差别只在这里看得见。计数是真实调用路径上的,不另开一条。 }
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
  end;

implementation

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
    栏把 controller 推给窗口要到 Task 5，所以这里两个都自己接。 }
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
    FWin.RenderTo(bmp.Canvas, Rect(0, 0, W, H), FWin.Font.PixelsPerInch);
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
  AssertTrue('客户区内缩量变了就得重排,不能只重画', FWin.AlignCount > 0);
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
  { 守的是「标题行高是**设备**像素」:token 不按 PPI 放大,这里两次就一样大。
    键里那个 PPI 反而守不住 —— 改 Font.PixelsPerInch 会发 Changed、走到 Invalidate,
    而 Invalidate 无条件把 token 缓存清掉,键少一项照样绿(实测过)。 }
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
    FWin.RenderTo(bmp.Canvas, Rect(0, 0, W, H), 96);
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
  { 切页就是开关 Visible(Task 10),所以这对事件的触发边是 CM_VISIBLECHANGED。 }
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
begin
  { spec §6.6:设计期切 Visible 是设计器在摆控件 / 点页签,不是用户眼里的显示隐藏。 }
  FWin.OnShow := @HandleShow;
  FWin.OnHide := @HandleHide;
  FShows := 0;
  FHides := 0;
  FWin.MarkDesigning(True);
  FWin.Visible := True;
  FWin.Visible := False;
  AssertEquals('设计期不发 OnShow', 0, FShows);
  AssertEquals('设计期不发 OnHide', 0, FHides);
  FWin.MarkDesigning(False);
  FWin.Visible := True;
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
  AssertEquals('主题没动的重画不许整控件重排', 0, FWin.AlignCount);
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
    FWin.RenderTo(bmp.Canvas, Rect(0, 0, W, H), FWin.Font.PixelsPerInch);
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

initialization
  RegisterClasses([TTyToolWindowBar, TTyToolWindow, TTyToolWindowActions]);
  RegisterTest(TTyToolWindowTests);
end.
