unit test.toolwindow.window;
{$mode objfpc}{$H+}

{ TTyToolWindow 本体：标题行与正文的切分、换主题 / 换 DPI 后重新排版、
  以及绘制与绘制缓存。几何纯函数在 test.toolwindow.geometry。 }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, fpcunit, testregistry,
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
    FWin.RenderTo(bmp.Canvas, Rect(0, 0, W, H), 96);
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

initialization
  RegisterClasses([TTyToolWindowBar, TTyToolWindow, TTyToolWindowActions]);
  RegisterTest(TTyToolWindowTests);
end.
