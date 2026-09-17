unit test.scrollbar.hostframe;
{$mode objfpc}{$H+}
{ 内嵌滚动条与宿主的**框**(边框 + 焦点环 + 圆角)怎么分像素。

  底层事实:内嵌条是**窗口化**子控件,它那块矩形上宿主一个像素都画不进去。

  走过的两条弯路(都在 git 历史里):
    · 3cb76fb7 把条按边框/焦点环那一圈(TyChromeInsetLogical)内缩 —— 直边上对;
    · 470fa0ca 发现圆角上弧往里弯,又把条的两端各截掉几像素(TyBarCornerInsetPx)。
  两次的前提一样:「把条的窗口缩小去躲边框」。真机的结论是「条飘着的,感觉不够紧凑」,而
  只要是这个前提,圆角上就一定得截短条,调常数调不出来。

  **现在的前提**:条贴边摆、占满整条边,由条自己把宿主在这几个像素上的样子画出来 ——
  底下宿主背后的背景和宿主的底色,中间条身(按可见度合成),最上面宿主的边框和焦点环
  (永远不透明)。宿主通过 ITyScrollBarFrameHost 交出它此刻画框用的样式。

  **判据没变,成立的理由变了**:「叠上条之后,宿主框上的像素一个都不变」。从前它成立是因为
  条躲开了框;现在成立是因为条把框画了回去。所以这一组现在必须在**每个可见度**(完全可见、
  淡出途中、淡没)、**圆角**(不止一个半径)下都跑 —— 完全可见和淡出途中正是条身压在框下面
  的时候,从前那一版只在「淡没」上跑,那时候条身根本不在。

  **哪些像素算「框」**:夹具里只有框用得上这几种颜色 ——
    · 边框 #FF0000(红):「红比绿多」;
    · 宿主背后的父背景 #0000C0(蓝):「蓝比红绿都多」,圆角弧**外面**那几块就是它;
    · 焦点环 #00B000(绿):「绿比红蓝都多」—— 红和蓝怎么混绿都最低,所以环不会被认错;
    · 其余一切(白表面、灰条身 #808080、深灰滑块和箭头、黑字)红绿蓝相等,一个都不沾。
  所以「在宿主单画的那张图上带这几种颜色」的像素就是框,而条如果没把框画回去,那个位置
  上叠出来的只会是灰/白 —— 颜色对不上,测试就红。这一条是故意这么挑的:这个特性已经出过
  五条「怎么都红不了」的测试,其中就有「夹具的边框色碰巧等于栈里别的什么」这一种。
  只看框所在的那一圈(边带 + 四个角的方块),宿主内部也会用 border-color 画东西(列表视图
  表头那条横线),那不是框。

  **无头能跑到真正的对齐引擎**:LCL 只是在没 Show 的窗体上跳过 AutoSize/Realign,直接调
  AlignControls 就能把 Align=alRight 的条摆到真实位置(实测与真机同值)。Grid/ListView/
  TreeView/ScrollBox 自己 SetBounds。焦点那两条要真焦点,自己把 widgetset 起起来(见
  NeedWidgetSet),单跑也不会因为全量里别人先起过而假绿。 }
interface
uses
  Classes, SysUtils, Types, Math, LCLType, LCLIntf, LMessages, Graphics, Forms, Controls, StdCtrls,
  fpcunit, testregistry, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.ScrollBar,
  tyControls.ListBox, tyControls.Memo, tyControls.TreeView,
  tyControls.Grid, tyControls.ListView, tyControls.Panel, tyControls.ScrollBox,
  tyControls.Button, tyControls.Columns;

const
  { 夹具尺寸。摆在 interface 里是因为几个辅助过程拿它当缺省参数(缺省值必须先于声明可见)。 }
  HostW = 160;
  HostH = 120;

type
  { 宿主的 RenderTo 都是 protected，签名又完全一样，所以每个宿主开一个口子，
    再用同一个回调类型喂给底下那个比较器。 }
  TRenderProc = procedure(ACanvas: TCanvas; const ARect: TRect; APPI: Integer) of object;

  TBarFade = (bfVisible, bfMid, bfHidden);

  TFrameListBox = class(TTyListBox)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure CallUpdateScrollBar;
  end;

  TFrameMemo = class(TTyMemo)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure CallUpdateScrollBar;
  end;

  TFrameTree = class(TTyTreeView)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TFrameGrid = class(TTyStringGrid)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TFrameListView = class(TTyListView)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TFrameScrollBox = class(TTyScrollBox)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  { 条的 RenderTo 同样是 protected。宿主建的是**普通** TTyScrollBar，所以这个口子
    是拿来硬转型用的（不碰任何派生字段，只是借它调 inherited 的 protected 方法、读
    TTyScrollBar 自己声明的 protected 字段）。 }
  TFrameBar = class(TTyScrollBar)
  public
    procedure RenderInto(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function Invalidations: Cardinal;
  end;

  TScrollBarHostFrameTests = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    { 判据本身。ABand = 直边上框占的那一圈有多宽(设备像素,宁宽勿窄),ACornerBox = 四个
      角上要看的方块边长。见实现处。 }
    procedure CheckFrameIntact(const AWhat: string; ARender: TRenderProc;
      const ABars: array of TTyScrollBar; ABand, ACornerBox: Integer;
      AW: Integer = HostW; AH: Integer = HostH; APPI: Integer = 96);
    { 宿主的 UpdateScrollBar(s) 是私有的，但每个宿主的 RenderTo 头上都会调它——
      屏幕上也正是这样:第一次 Paint 才把条建出来并摆好。所以先空画一张。 }
    procedure Prime(ARender: TRenderProc; AW: Integer = HostW; AH: Integer = HostH;
      APPI: Integer = 96);
    procedure SetFade(ABar: TTyScrollBar; AFade: TBarFade);
    function MakeListBox(AWide: Boolean = False; AW: Integer = HostW;
      AH: Integer = HostH; APPI: Integer = 96; ARtl: Boolean = False;
      AOwner: TWinControl = nil): TFrameListBox;
    function MakeMemo(ABoth: Boolean = False; AOwner: TWinControl = nil): TFrameMemo;
    function MakeTree(AOwner: TWinControl = nil): TFrameTree;
    function MakeGrid(AWide: Boolean = False; AOwner: TWinControl = nil): TFrameGrid;
    function MakeListView(AWide: Boolean = False; AOwner: TWinControl = nil): TFrameListView;
    function MakeScrollBox(AOwner: TWinControl = nil): TFrameScrollBox;
  private
    { ---- 点击那几条用:真显示出来的屏幕外窗体 ----
      CanFocus 要求一路 Visible 到顶,只建句柄不 Show 的窗体上「点了拿不拿焦点」一律答不拿,
      每一条都会空转地绿。FPark 是焦点的停靠位,每次点击前先把焦点放在它上面。 }
    FWin: TForm;
    FPark: TTyButton;
    FTrapped: string;
    FPrevOnException: TExceptionEvent;
    FTrapInstalled: Boolean;
    { 焦点切换时 WM_KILLFOCUS/WM_SETFOCUS 是 widgetset 同步发的,那里面抛出的异常到不了测试,
      LCL 会弹模态框 —— 控制台跑测试没人去关,整个套件卡死。记下来,断言时再报。 }
    procedure TrapException(Sender: TObject; E: Exception);
    procedure OpenWindow;
    procedure ParkFocus;
    { 走真实消息路径的一次点击(按下 + 抬起),坐标是条自己的客户区坐标。 }
    procedure ClickBar(ABar: TTyScrollBar; AX, AY: Integer);
    procedure AssertNothingRaised(const AWhere: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ListBoxKeepsItsFrameUnderItsBarAtEveryRadiusAndFade;
    procedure ListBoxKeepsItsFrameUnderBothBarsAtEveryRadiusAndFade;
    procedure MirroredListBoxKeepsItsLeftFrameAtEveryRadiusAndFade;
    procedure MemoKeepsItsFrameUnderItsBarsAtEveryRadiusAndFade;
    procedure TreeViewKeepsItsFrameUnderItsBarAtEveryRadiusAndFade;
    procedure GridKeepsItsFrameUnderItsBarsAtEveryRadiusAndFade;
    procedure ListViewKeepsItsFrameUnderItsBarsAtEveryRadiusAndFade;
    procedure ScrollBoxKeepsItsFrameUnderItsBarsAtEveryRadiusAndFade;
    procedure TheFrameSurvivesAtEveryRadiusBorderAndDpi;
    procedure EveryHostDocksItsBarsFlushToItsEdges;
    procedure TheFocusRingIsWholeUnderAVisibleBar;
    procedure FocusingTheHostRepaintsItsBars;
    procedure EveryHostRepaintsItsBarsWhenItInvalidates;
    procedure AStandaloneBarIsNotRepaintedByItsParent;
    procedure MidFadeOverAGradientHostShowsTheGradient;
    procedure AnEmbeddedBarIsSymmetricAcrossTheWidthTheFrameLeavesIt;
    procedure AnEmbeddedTrackIsSquareAndRunsIntoTheFrame;
    procedure AnEmbeddedTrackFollowsTheEmbeddedRadiusToken;
    procedure ClickingAnEmbeddedBarFocusesItsHostAndTheKeysGoThere;
    procedure ClickingAStandaloneBarStillFocusesTheBar;
    procedure ABarDroppedIntoAScrollBoxIsNotEmbedded;
    procedure ClickingAnEmbeddedBarLeavesFocusAloneWhenTheHostTakesNone;
    procedure ClickingAGridBarWhileEditingKeepsTheEditor;
    procedure DraggingAnEmbeddedThumbWorksWhileTheHostHasFocus;
  end;

implementation

const
  Wipe   = TColor($00FF00);   { 哨兵底漆(亮绿):渲染没盖到的地方会原样留着,数得出来 }
  Ground = TColor($C00000);   { 父窗体底色 #0000C0(TColor 是 BGR):圆角弧外面那几块 }

var
  HostFrameWidgetSet: Boolean = False;

{ 控制台跑测试的时候 widgetset 还没起来,建句柄会失败(1407)。与 test.focus.tabstop 同一个
  惰性自举:全量里别人起过也好、单跑也好,需要真焦点的两条都自己保证。 }
procedure NeedWidgetSet;
begin
  if HostFrameWidgetSet then Exit;
  Forms.Application.Initialize;
  HostFrameWidgetSet := True;
end;

function FindBar(AHost: TWinControl; AKind: TTyScrollBarKind): TTyScrollBar;
var i: Integer;
begin
  { 内嵌条是宿主的真子控件(建的时候 Parent := Self),遍历得到,不必为测试开公开口子。 }
  Result := nil;
  for i := 0 to AHost.ControlCount - 1 do
    if (AHost.Controls[i] is TTyScrollBar)
       and (TTyScrollBar(AHost.Controls[i]).Kind = AKind) then
      Exit(TTyScrollBar(AHost.Controls[i]));
end;

type
  TWinAccess = class(TWinControl);

{ LCL 在没 Show 的窗体上跳过 AutoSize/Realign，但对齐引擎本身照样能跑：喂它宿主自己的客户区，
  Align=alRight 的条就落到真实位置上。 }
procedure ForceAlign(AHost: TWinControl);
var r: TRect;
begin
  r := Rect(0, 0, AHost.Width, AHost.Height);
  TWinAccess(AHost).AdjustClientRect(r);
  TWinAccess(AHost).AlignControls(nil, r);
end;

{ 圆角夹具。半径、边框宽度是参数;AExtra 追加规则(焦点环、渐变底色)。 }
function FrameCss(ARadius, ABorder: Integer; const AExtra: string = ''): string;
begin
  Result :=
    ':root { --scrollbar-size: 12; --scrollbar-auto-hide: 1000; }' +
    'TyListBox, TyMemo, TyTreeView, TyGrid, TyListView, TyScrollBox {' +
    '  background: #FFFFFF; color: #000000; border-color: #FF0000;' +
    '  border-width: ' + IntToStr(ABorder) + 'px;' +
    '  border-radius: ' + IntToStr(ARadius) + 'px; padding: 0px; }' +
    'TyScrollBar { background: #808080; color: #404040; border-width: 0px; border-radius: 0px; }' +
    'TyScrollThumb { background: #202020; }' +
    { 备忘录的字从内距的内沿起画,不避开边框。内距 0 的话第一列字的抗锯齿就压在左边框的
      抗锯齿列上 —— 那是宿主的**内容**碰了自己的框,条底下那一截本来就看不见,但它会被
      「框像素」的判据当成框来比。内置主题给备忘录的内距是 4-6。 }
    'TyMemo { padding: 6px; }' + AExtra;
end;

procedure TFrameListBox.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin RenderTo(ACanvas, ARect, APPI); end;
procedure TFrameListBox.CallUpdateScrollBar;
begin UpdateScrollBar; end;

procedure TFrameMemo.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin RenderTo(ACanvas, ARect, APPI); end;
procedure TFrameMemo.CallUpdateScrollBar;
begin UpdateScrollBar; end;

procedure TFrameTree.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin RenderTo(ACanvas, ARect, APPI); end;

procedure TFrameGrid.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin RenderTo(ACanvas, ARect, APPI); end;

procedure TFrameListView.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin RenderTo(ACanvas, ARect, APPI); end;

procedure TFrameScrollBox.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin RenderTo(ACanvas, ARect, APPI); end;

procedure TFrameBar.RenderInto(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin RenderTo(ACanvas, ARect, APPI); end;
function TFrameBar.Invalidations: Cardinal;
begin Result := FInvalidations; end;

{ 画一张「屏幕上真正会长的样子」：先画宿主，再把窗口化的条按它自己的 BoundsRect
  盖上去。ADrawBars=False 就是宿主自己那张对照图。 }
function Shoot(ARender: TRenderProc; const ABars: array of TTyScrollBar;
  ADrawBars: Boolean; AW: Integer = HostW; AH: Integer = HostH;
  APPI: Integer = 96): TBGRABitmap;
var
  bmp: TBitmap;
  i: Integer;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(AW, AH);
    bmp.Canvas.Brush.Color := Wipe;
    bmp.Canvas.FillRect(0, 0, AW, AH);
    if Assigned(ARender) then ARender(bmp.Canvas, Rect(0, 0, AW, AH), APPI);
    if ADrawBars then
      for i := 0 to High(ABars) do
        if ABars[i] <> nil then
          TFrameBar(ABars[i]).RenderInto(bmp.Canvas, ABars[i].BoundsRect, APPI);
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
  end;
end;

function Same(const A, B: TBGRAPixel): Boolean;
begin
  { 只比 RGB：pf32bit 的 GDI 位图读回来 alpha 不可信（全图会被校正）。 }
  Result := (A.red = B.red) and (A.green = B.green) and (A.blue = B.blue);
end;

{ 这一点有多「像框」:红边框(红比绿多)、弧外的蓝父背景(蓝比红绿都多)、绿焦点环(绿比
  红蓝都多)。白、灰、黑三个通道相等,一律是 0。 }
function FrameStrength(const P: TBGRAPixel): Integer;
var red, blue, green: Integer;
begin
  red := P.red - P.green;
  if red < 0 then red := 0;
  blue := P.blue - Max(P.red, P.green);
  if blue < 0 then blue := 0;
  green := P.green - Max(P.red, P.blue);
  if green < 0 then green := 0;
  Result := Max(red, Max(blue, green));
end;

{ 焦点环单独有多浓。**环必须是绿的**,这一条是变异测试逼出来的:第一版用的品红,而最外那
  一圈像素是「红边框的抗锯齿 + 蓝父背景 + 白底色」三者混出来的 D77196 —— 红蓝都高、绿低,
  正好就是「品红」。于是焦点环整个没画的时候,这里照样数出 138 个「环」像素,两条断言都绿。
  绿在这张图里只可能来自环:红和蓝怎么混绿都是最低的那个。 }
function RingStrength(const P: TBGRAPixel): Integer;
begin
  Result := P.green - Max(P.red, P.blue);
  if Result < 0 then Result := 0;
end;

{ 条替宿主画框,用的是**平移过**的坐标(宿主的矩形在条的坐标系里从 -Left 起)。同一个圆角
  平移几百像素再光栅化,抗锯齿覆盖率会在个别像素上差 1/255(实测 r=8/2px/144DPI 有一个
  像素 A4 对 A5)—— 浮点坐标的舍入,不是画错。所以逐通道放 2 个色阶。
  这个容差咬不掉判据:条没把框画回去的时候,那个位置上是灰条身或白底,与红框差的是几十上百
  个色阶。 }
function Near(const A, B: TBGRAPixel): Boolean;
begin
  Result := (Abs(A.red - B.red) <= 2) and (Abs(A.green - B.green) <= 2)
    and (Abs(A.blue - B.blue) <= 2);
end;

function PixelHex(const P: TBGRAPixel): string;
begin
  Result := Format('%.2x%.2x%.2x', [P.red, P.green, P.blue]);
end;

procedure TScrollBarHostFrameTests.CheckFrameIntact(const AWhat: string;
  ARender: TRenderProc; const ABars: array of TTyScrollBar; ABand, ACornerBox: Integer;
  AW: Integer; AH: Integer; APPI: Integer);
var
  bare, over, barOnly: TBGRABitmap;
  one: array of TTyScrollBar;
  i, x, y, unpainted, wipeLeft, checked, need: Integer;
  r: TRect;
  bad: string;

  { 框所在的那一圈:四条边带,加四个角上的方块(弧往里弯,角上的框离外沿更远)。 }
  function InZone(AX, AY: Integer): Boolean;
  begin
    Result := (AX < ABand) or (AX >= AW - ABand) or (AY < ABand) or (AY >= AH - ABand)
      or (((AX < ACornerBox) or (AX >= AW - ACornerBox))
          and ((AY < ACornerBox) or (AY >= AH - ACornerBox)));
  end;

begin
  AssertTrue(AWhat + ':前置条件——至少得有一条内嵌条', Length(ABars) > 0);
  for i := 0 to High(ABars) do
  begin
    AssertNotNull(AWhat + ':前置条件——宿主必须真的有这一条', ABars[i]);
    AssertTrue(AWhat + ':前置条件——这一条必须是可见的', ABars[i].Visible);
  end;

  bare := nil;
  over := nil;
  try
    bare := Shoot(ARender, ABars, False, AW, AH, APPI);
    over := Shoot(ARender, ABars, True, AW, AH, APPI);

    { 底漆一个都不该剩：剩了就说明这一趟压根没画满，下面「像素没变」谁都能过。 }
    wipeLeft := 0;
    for y := 0 to AH - 1 do
      for x := 0 to AW - 1 do
        if Same(over.GetPixel(x, y), ColorToBGRA(ColorToRGB(Wipe))) then Inc(wipeLeft);
    AssertEquals(AWhat + ':渲染要盖满整块，还留着底漆说明这张图不作数', 0, wipeLeft);

    one := nil;
    SetLength(one, 1);
    bad := '';
    for i := 0 to High(ABars) do
    begin
      r := ABars[i].BoundsRect;

      { 条确实把它那块矩形**盖满**了 —— 「条盖住的像素宿主画不进去」才成立,下面比的才是
        屏幕上真正看得见的东西。单独把条画到底漆上数。 }
      one[0] := ABars[i];
      barOnly := Shoot(nil, one, True, AW, AH, APPI);
      try
        unpainted := 0;
        for y := r.Top to r.Bottom - 1 do
          for x := r.Left to r.Right - 1 do
            if Same(barOnly.GetPixel(x, y), ColorToBGRA(ColorToRGB(Wipe))) then Inc(unpainted);
        AssertEquals(AWhat + ':前置条件——条必须把它那块矩形盖满(它是窗口化控件)', 0, unpainted);
      finally
        barOnly.Free;
      end;

      { 判据本身:条那块矩形里,宿主单画时是「框」的每一个像素,叠上条之后一个字节不差。 }
      checked := 0;
      for y := Max(r.Top, 0) to Min(r.Bottom, AH) - 1 do
        for x := Max(r.Left, 0) to Min(r.Right, AW) - 1 do
        begin
          if not InZone(x, y) then Continue;
          if FrameStrength(bare.GetPixel(x, y)) = 0 then Continue;
          Inc(checked);
          if (bad = '') and not Near(bare.GetPixel(x, y), over.GetPixel(x, y)) then
            bad := Format('%s 条[%d] (%d,%d):宿主画的是 %s,叠上条变成 %s',
              [AWhat, i, x, y, PixelHex(bare.GetPixel(x, y)), PixelHex(over.GetPixel(x, y))]);
        end;
      { **非空前置条件**:条的整条长度上每一行(列)至少压着一个框像素 —— 条贴边,边框就在它
        底下。数不够说明条没贴边,或者这张图里压根没有框,上面「没变」是白捡的。 }
      if ABars[i].Kind = sbVertical then need := r.Bottom - r.Top else need := r.Right - r.Left;
      AssertTrue(Format('%s 条[%d]:前置条件——条底下必须真的压着框(看了 %d 个框像素,条长 %d)',
        [AWhat, i, checked, need]), checked >= need);
    end;
    AssertEquals(AWhat + ':条把宿主的框画错了', '', bad);
  finally
    bare.Free;
    over.Free;
  end;
end;

procedure TScrollBarHostFrameTests.Prime(ARender: TRenderProc; AW: Integer;
  AH: Integer; APPI: Integer);
var shot: TBGRABitmap; none: array of TTyScrollBar;
begin
  none := nil;   { 条还没被建出来——这一趟正是把它建出来的那一趟 }
  shot := Shoot(ARender, none, False, AW, AH, APPI);
  shot.Free;
end;

procedure TScrollBarHostFrameTests.SetFade(ABar: TTyScrollBar; AFade: TBarFade);
begin
  AssertNotNull('前置条件:条存在', ABar);
  ABar.NoteActivity;
  case AFade of
    bfVisible:
      AssertEquals('前置条件:条完全可见', 1.0, ABar.FadeLevel, 0.001);
    bfMid:
      begin
        ABar.AutoHideTick(2000);                         { 闲过了延时 -> 装上膛 }
        ABar.AutoHideTick(TyScrollBarFadeOutMs div 3);   { 推一截,不推到底 }
        AssertTrue('前置条件:条卡在淡出途中',
          (ABar.FadeLevel > 0.01) and (ABar.FadeLevel < 0.99));
      end;
    bfHidden:
      begin
        ABar.AutoHideTick(2000);
        ABar.AutoHideTick(TyScrollBarFadeOutMs);
        AssertEquals('前置条件:条确实淡到底了', 0.0, ABar.FadeLevel, 0.001);
      end;
  end;
end;

procedure TScrollBarHostFrameTests.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Color := Ground;
  FCtl := TTyStyleController.Create(FForm);
  FCtl.LoadThemeCss(FrameCss(0, 1));
end;

procedure TScrollBarHostFrameTests.TearDown;
begin
  { 显示出来的窗体先走:它上面的控件的 Controller 是 FForm 拥有的 FCtl。 }
  FreeAndNil(FWin);
  FPark := nil;
  if FTrapInstalled then
  begin
    Forms.Application.OnException := FPrevOnException;
    FTrapInstalled := False;
  end;
  FreeAndNil(FForm);
end;

function TScrollBarHostFrameTests.MakeListBox(AWide: Boolean; AW: Integer;
  AH: Integer; APPI: Integer; ARtl: Boolean; AOwner: TWinControl): TFrameListBox;
var i: Integer;
begin
  if AOwner = nil then AOwner := FForm;
  Result := TFrameListBox.Create(AOwner);
  Result.Parent := AOwner;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := APPI;
  Result.ItemHeight := 20;
  Result.SetBounds(0, 0, AW, AH);
  if ARtl then Result.BiDiMode := bdRightToLeft;
  for i := 1 to 60 do Result.Items.Add('row ' + IntToStr(i));
  { ScrollWidth 是横条唯一的开关（行内容宽度，逻辑 px）：比宿主宽就出横条。 }
  if AWide then Result.ScrollWidth := 400;
  Result.CallUpdateScrollBar;
  Prime(@Result.Render, AW, AH, APPI);
  ForceAlign(Result);
end;

function TScrollBarHostFrameTests.MakeMemo(ABoth: Boolean; AOwner: TWinControl): TFrameMemo;
var i: Integer;
begin
  if AOwner = nil then AOwner := FForm;
  Result := TFrameMemo.Create(AOwner);
  Result.Parent := AOwner;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, HostW, HostH);
  if ABoth then
  begin
    Result.WordWrap := False;
    Result.ScrollBars := ssBoth;
  end
  else
    Result.ScrollBars := ssAutoVertical;
  for i := 1 to 40 do
    Result.Lines.Add('line ' + IntToStr(i) + ' with enough text to run past the right edge');
  Result.CallUpdateScrollBar;
  Prime(@Result.Render);
  ForceAlign(Result);
end;

function TScrollBarHostFrameTests.MakeTree(AOwner: TWinControl): TFrameTree;
var i: Integer;
begin
  if AOwner = nil then AOwner := FForm;
  Result := TFrameTree.Create(AOwner);
  Result.Parent := AOwner;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, HostW, HostH);
  for i := 1 to 200 do Result.Items.Add(nil, 'node ' + IntToStr(i));
  Prime(@Result.Render);
end;

function TScrollBarHostFrameTests.MakeGrid(AWide: Boolean; AOwner: TWinControl): TFrameGrid;
var i: Integer;
begin
  if AOwner = nil then AOwner := FForm;
  Result := TFrameGrid.Create(AOwner);
  Result.Parent := AOwner;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, HostW, HostH);
  Result.RowCount := 200;
  if AWide then
    for i := 1 to 6 do (Result.Header.Columns.Add as TTyColumn).Width := 100;
  Prime(@Result.Render);
end;

function TScrollBarHostFrameTests.MakeListView(AWide: Boolean; AOwner: TWinControl): TFrameListView;
var i: Integer;
begin
  if AOwner = nil then AOwner := FForm;
  Result := TFrameListView.Create(AOwner);
  Result.Parent := AOwner;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, HostW, HostH);
  Result.Columns.Add;
  if AWide then Result.Columns[0].Width := 600;
  for i := 1 to 200 do Result.Items.Add.Caption := 'item ' + IntToStr(i);
  Prime(@Result.Render);
end;

function TScrollBarHostFrameTests.MakeScrollBox(AOwner: TWinControl): TFrameScrollBox;
var c: TTyPanel;
begin
  if AOwner = nil then AOwner := FForm;
  Result := TFrameScrollBox.Create(AOwner);
  Result.Parent := AOwner;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, HostW, HostH);
  c := TTyPanel.Create(Result);
  c.Parent := Result;
  c.SetBounds(0, 0, 600, 900);   { 两个方向都溢出 -> 两条条都出来 }
  Result.UpdateScrollRange;
end;

{ ---- 每个宿主 × 半径 × 可见度 ------------------------------------------------ }

const
  Radii: array[0..2] of Integer = (0, 6, 10);

procedure TScrollBarHostFrameTests.ListBoxKeepsItsFrameUnderItsBarAtEveryRadiusAndFade;
var k: Integer; f: TBarFade; lb: TFrameListBox; tag: string;
begin
  for k := 0 to High(Radii) do
    for f := Low(TBarFade) to High(TBarFade) do
    begin
      FCtl.LoadThemeCss(FrameCss(Radii[k], 1));
      lb := MakeListBox;
      try
        tag := Format('TTyListBox r=%d fade=%d', [Radii[k], Ord(f)]);
        SetFade(FindBar(lb, sbVertical), f);
        CheckFrameIntact(tag, @lb.Render, [FindBar(lb, sbVertical)], 3, Radii[k] + 5);
      finally
        lb.Free;
      end;
    end;
end;

procedure TScrollBarHostFrameTests.ListBoxKeepsItsFrameUnderBothBarsAtEveryRadiusAndFade;
var k: Integer; f: TBarFade; lb: TFrameListBox; tag: string;
begin
  { 两条一起出来,边框 2px(showcase 那一档)。**底边**那一带只有横条压得到;右下角那一格两条
    都不占,是宿主自己画的 —— 两条相接处的算术只要有一头算错,角上就会被条压住或者豁开。 }
  for k := 0 to High(Radii) do
    for f := Low(TBarFade) to High(TBarFade) do
    begin
      FCtl.LoadThemeCss(FrameCss(Radii[k], 2));
      lb := MakeListBox(True);
      try
        tag := Format('TTyListBox 两条 r=%d/2px fade=%d', [Radii[k], Ord(f)]);
        AssertNotNull(tag + ':前置条件——宽内容必须逼出一条横条', FindBar(lb, sbHorizontal));
        SetFade(FindBar(lb, sbVertical), f);
        SetFade(FindBar(lb, sbHorizontal), f);
        CheckFrameIntact(tag, @lb.Render,
          [FindBar(lb, sbVertical), FindBar(lb, sbHorizontal)], 4, Radii[k] + 6);
      finally
        lb.Free;
      end;
    end;
end;

procedure TScrollBarHostFrameTests.MirroredListBoxKeepsItsLeftFrameAtEveryRadiusAndFade;
var k: Integer; f: TBarFade; lb: TFrameListBox; tag: string;
begin
  { 镜像之后竖条停在**左**边,它压着的是宿主的左边框和左边两个角。条按自己的 Left 算出宿主
    在它坐标系里的位置,算错了(比如照旧当成停在右边)画出来的就是右边框 —— 落在左边这一列
    上全是错的颜色。 }
  for k := 1 to High(Radii) do
    for f := Low(TBarFade) to High(TBarFade) do
    begin
      FCtl.LoadThemeCss(FrameCss(Radii[k], 1));
      lb := MakeListBox(False, HostW, HostH, 96, True);
      try
        tag := Format('TTyListBox RTL r=%d fade=%d', [Radii[k], Ord(f)]);
        AssertEquals(tag + ':前置条件——竖条停在左边', 0, FindBar(lb, sbVertical).Left);
        SetFade(FindBar(lb, sbVertical), f);
        CheckFrameIntact(tag, @lb.Render, [FindBar(lb, sbVertical)], 3, Radii[k] + 5);
      finally
        lb.Free;
      end;
    end;
end;

procedure TScrollBarHostFrameTests.MemoKeepsItsFrameUnderItsBarsAtEveryRadiusAndFade;
var k: Integer; f: TBarFade; mm: TFrameMemo; tag: string;
begin
  { 备忘录的竖条占着右下角(横条 alNone,停在竖条左边),所以右下角的弧整个压在竖条下面。 }
  for k := 0 to High(Radii) do
    for f := Low(TBarFade) to High(TBarFade) do
    begin
      FCtl.LoadThemeCss(FrameCss(Radii[k], 1));
      mm := MakeMemo(True);
      try
        tag := Format('TTyMemo r=%d fade=%d', [Radii[k], Ord(f)]);
        AssertNotNull(tag + ':前置条件——ssBoth 必须给出横条', FindBar(mm, sbHorizontal));
        SetFade(FindBar(mm, sbVertical), f);
        SetFade(FindBar(mm, sbHorizontal), f);
        CheckFrameIntact(tag, @mm.Render,
          [FindBar(mm, sbVertical), FindBar(mm, sbHorizontal)], 3, Radii[k] + 5);
      finally
        mm.Free;
      end;
    end;
end;

procedure TScrollBarHostFrameTests.TreeViewKeepsItsFrameUnderItsBarAtEveryRadiusAndFade;
var k: Integer; f: TBarFade; tv: TFrameTree; tag: string;
begin
  for k := 0 to High(Radii) do
    for f := Low(TBarFade) to High(TBarFade) do
    begin
      FCtl.LoadThemeCss(FrameCss(Radii[k], 1));
      tv := MakeTree;
      try
        tag := Format('TTyTreeView r=%d fade=%d', [Radii[k], Ord(f)]);
        SetFade(FindBar(tv, sbVertical), f);
        CheckFrameIntact(tag, @tv.Render, [FindBar(tv, sbVertical)], 3, Radii[k] + 5);
      finally
        tv.Free;
      end;
    end;
end;

procedure TScrollBarHostFrameTests.GridKeepsItsFrameUnderItsBarsAtEveryRadiusAndFade;
var k: Integer; f: TBarFade; gr: TFrameGrid; tag: string;
begin
  for k := 0 to High(Radii) do
    for f := Low(TBarFade) to High(TBarFade) do
    begin
      FCtl.LoadThemeCss(FrameCss(Radii[k], 1));
      gr := MakeGrid(True);
      try
        tag := Format('TTyStringGrid r=%d fade=%d', [Radii[k], Ord(f)]);
        AssertNotNull(tag + ':前置条件——30 列必须逼出一条横条', FindBar(gr, sbHorizontal));
        SetFade(FindBar(gr, sbVertical), f);
        SetFade(FindBar(gr, sbHorizontal), f);
        CheckFrameIntact(tag, @gr.Render,
          [FindBar(gr, sbVertical), FindBar(gr, sbHorizontal)], 3, Radii[k] + 5);
      finally
        gr.Free;
      end;
    end;
end;

procedure TScrollBarHostFrameTests.ListViewKeepsItsFrameUnderItsBarsAtEveryRadiusAndFade;
var k: Integer; f: TBarFade; lv: TFrameListView; tag: string;
begin
  for k := 0 to High(Radii) do
    for f := Low(TBarFade) to High(TBarFade) do
    begin
      FCtl.LoadThemeCss(FrameCss(Radii[k], 1));
      lv := MakeListView(True);
      try
        tag := Format('TTyListView r=%d fade=%d', [Radii[k], Ord(f)]);
        AssertNotNull(tag + ':前置条件——600 宽的列必须逼出一条横条', FindBar(lv, sbHorizontal));
        SetFade(FindBar(lv, sbVertical), f);
        SetFade(FindBar(lv, sbHorizontal), f);
        CheckFrameIntact(tag, @lv.Render,
          [FindBar(lv, sbVertical), FindBar(lv, sbHorizontal)], 3, Radii[k] + 5);
      finally
        lv.Free;
      end;
    end;
end;

procedure TScrollBarHostFrameTests.ScrollBoxKeepsItsFrameUnderItsBarsAtEveryRadiusAndFade;
var k: Integer; f: TBarFade; sb: TFrameScrollBox; tag: string;
begin
  { 滚动框的条从前按 FrameInset(只有边框宽,没有抗锯齿那一列)内缩,圆角上照样压着弧。
    它的**视口**仍按 FrameInset 内缩,只有条挪到了边上。 }
  for k := 0 to High(Radii) do
    for f := Low(TBarFade) to High(TBarFade) do
    begin
      FCtl.LoadThemeCss(FrameCss(Radii[k], 1));
      sb := MakeScrollBox;
      try
        tag := Format('TTyScrollBox r=%d fade=%d', [Radii[k], Ord(f)]);
        AssertTrue(tag + ':前置条件——两条都出来了',
          FindBar(sb, sbVertical).Visible and FindBar(sb, sbHorizontal).Visible);
        SetFade(FindBar(sb, sbVertical), f);
        SetFade(FindBar(sb, sbHorizontal), f);
        CheckFrameIntact(tag, @sb.Render,
          [FindBar(sb, sbVertical), FindBar(sb, sbHorizontal)], 3, Radii[k] + 5);
      finally
        sb.Free;
      end;
    end;
end;

procedure TScrollBarHostFrameTests.TheFrameSurvivesAtEveryRadiusBorderAndDpi;
var
  bw, rad, dpi, w, h, band: Integer;
  f: TBarFade;
  lb: TFrameListBox;
  tag: string;
begin
  { 从前这一格钉的是 TyBarCornerInsetPx 那个数(r=0..12 × 1/2px × 三个 DPI 共 78 组)。那个函数
    没了,扫的范围留着,问的换成现在真正要成立的那件事:**每个半径、每种边框、每个 DPI**,条贴着
    边,框一个像素不差。条替宿主画框走的是平移过的矩形、裁掉大半的圆角,抗锯齿在不同半径/缩放
    下落点不同 —— 这正是容易在某一格上差一个像素的地方(实测 r=8/2px/144DPI 就差过 1/255)。
    可见度只扫两头:完全可见走「条身 + 框线像素整个换回宿主的」,淡没走「底层上直接描框线」,
    是两条不同的代码;淡出途中与完全可见同一条,只是合成系数不同,上面每个宿主的用例都跑过。 }
  for dpi := 1 to 3 do
    for bw := 1 to 2 do
      for rad := 0 to 12 do
        for f := Low(TBarFade) to High(TBarFade) do
        begin
          if f = bfMid then Continue;
          FCtl.LoadThemeCss(FrameCss(rad, bw));
          w := MulDiv(HostW, 48 * (dpi + 1), 96);
          h := MulDiv(HostH, 48 * (dpi + 1), 96);
          lb := MakeListBox(False, w, h, 48 * (dpi + 1));
          try
            tag := Format('r=%d/%dpx/%dDPI fade=%d', [rad, bw, 48 * (dpi + 1), Ord(f)]);
            SetFade(FindBar(lb, sbVertical), f);
            band := MulDiv(bw + 1, 48 * (dpi + 1), 96) + 1;
            CheckFrameIntact(tag, @lb.Render, [FindBar(lb, sbVertical)],
              band, MulDiv(rad, 48 * (dpi + 1), 96) + band + 2, w, h, 48 * (dpi + 1));
          finally
            lb.Free;
          end;
        end;
end;

{ ---- 贴边 ----------------------------------------------------------------- }

procedure TScrollBarHostFrameTests.EveryHostDocksItsBarsFlushToItsEdges;
var
  lb, rtl: TFrameListBox;
  mm: TFrameMemo;
  gr: TFrameGrid;
  lv: TFrameListView;
  tv: TFrameTree;
  sb: TFrameScrollBox;
  v, hb: TTyScrollBar;
  bad: string;

  { 不在第一处就停:六个宿主各摆各的条,一次跑完把每一处不贴边的都列出来。 }
  procedure Expect(const AWhat: string; AExpected, AActual: Integer);
  begin
    if AExpected <> AActual then
      bad := bad + Format('%s:应为 %d,实为 %d; ', [AWhat, AExpected, AActual]);
  end;

  procedure CheckPair(const AWhat: string; AV, AH: TTyScrollBar; ACW, ACH: Integer;
    AVOwnsCorner: Boolean);
  begin
    AssertNotNull(AWhat + ':前置条件——竖条', AV);
    AssertTrue(AWhat + ':前置条件——竖条可见', AV.Visible);
    Expect(AWhat + ' 竖条右沿贴着宿主右边', ACW, AV.Left + AV.Width);
    Expect(AWhat + ' 竖条上沿贴着宿主上边', 0, AV.Top);
    if AH = nil then
      Expect(AWhat + ' 竖条下沿贴着宿主下边', ACH, AV.Top + AV.Height)
    else
    begin
      AssertTrue(AWhat + ':前置条件——横条可见', AH.Visible);
      Expect(AWhat + ' 横条左沿贴着宿主左边', 0, AH.Left);
      Expect(AWhat + ' 横条下沿贴着宿主下边', ACH, AH.Top + AH.Height);
      if AVOwnsCorner then
      begin
        Expect(AWhat + ' 竖条占着右下角,一直到宿主下边', ACH, AV.Top + AV.Height);
        Expect(AWhat + ' 横条停在竖条左沿', AV.Left, AH.Left + AH.Width);
      end
      else
      begin
        Expect(AWhat + ' 竖条下沿正好抵住横条上沿', AH.Top, AV.Top + AV.Height);
        Expect(AWhat + ' 横条右沿正好抵住竖条左沿', AV.Left, AH.Left + AH.Width);
      end;
    end;
  end;

begin
  { r=10 / 2px:从前让得最多的那一档(每端 10 像素)。现在一个像素都不让。 }
  FCtl.LoadThemeCss(FrameCss(10, 2));
  bad := '';

  lb := MakeListBox(True);
  { 列表框的横条是 alBottom,LCL 先摆它 —— 它占满整宽,竖条停在它上面。 }
  v := FindBar(lb, sbVertical);
  hb := FindBar(lb, sbHorizontal);
  AssertNotNull('TTyListBox:前置条件——横条', hb);
  Expect('TTyListBox 竖条右沿贴边', lb.ClientWidth, v.Left + v.Width);
  Expect('TTyListBox 竖条上沿贴边', 0, v.Top);
  Expect('TTyListBox 竖条下沿抵住横条', hb.Top, v.Top + v.Height);
  Expect('TTyListBox 横条左沿贴边', 0, hb.Left);
  Expect('TTyListBox 横条右沿贴边', lb.ClientWidth, hb.Left + hb.Width);
  Expect('TTyListBox 横条下沿贴边', lb.ClientHeight, hb.Top + hb.Height);

  rtl := MakeListBox(False, HostW, HostH, 96, True);
  v := FindBar(rtl, sbVertical);
  Expect('TTyListBox RTL 竖条左沿贴边', 0, v.Left);
  Expect('TTyListBox RTL 竖条上沿贴边', 0, v.Top);
  Expect('TTyListBox RTL 竖条下沿贴边', rtl.ClientHeight, v.Top + v.Height);

  mm := MakeMemo(True);
  CheckPair('TTyMemo', FindBar(mm, sbVertical), FindBar(mm, sbHorizontal),
    mm.ClientWidth, mm.ClientHeight, True);

  gr := MakeGrid(True);
  CheckPair('TTyStringGrid', FindBar(gr, sbVertical), FindBar(gr, sbHorizontal),
    gr.ClientWidth, gr.ClientHeight, False);

  lv := MakeListView(True);
  CheckPair('TTyListView', FindBar(lv, sbVertical), FindBar(lv, sbHorizontal),
    lv.ClientWidth, lv.ClientHeight, False);

  tv := MakeTree;
  CheckPair('TTyTreeView', FindBar(tv, sbVertical), nil, tv.Width, tv.Height, False);

  { 滚动框的 ClientWidth 已经扣掉了条的槽,贴的是控件本身的宽高。 }
  sb := MakeScrollBox;
  CheckPair('TTyScrollBox', FindBar(sb, sbVertical), FindBar(sb, sbHorizontal),
    sb.Width, sb.Height, False);

  AssertEquals('内嵌条必须贴边摆', '', bad);
end;

{ ---- 焦点环与重画 ----------------------------------------------------------- }

procedure TScrollBarHostFrameTests.TheFocusRingIsWholeUnderAVisibleBar;
var
  win: TForm;
  park: TTyButton;
  lb: TFrameListBox;
  mm: TFrameMemo;
  bare, over: TBGRABitmap;

  procedure CheckRing(const AWhat: string; AHost: TWinControl; ARender: TRenderProc;
    const ABars: array of TTyScrollBar);
  var
    i, x, y, onBar, need: Integer;
    r: TRect;
  begin
    park.SetFocus;
    Forms.Application.ProcessMessages;
    AssertFalse(AWhat + ':前置条件——焦点先停在别处', AHost.Focused);
    AHost.SetFocus;
    Forms.Application.ProcessMessages;
    AssertTrue(AWhat + ':前置条件——宿主真的拿到了焦点', AHost.Focused);
    for i := 0 to High(ABars) do SetFade(ABars[i], bfVisible);

    { 焦点环真的画在宿主上,而且压在条底下的那一截里也有。 }
    bare := Shoot(ARender, ABars, False);
    over := Shoot(ARender, ABars, True);
    try
      for i := 0 to High(ABars) do
      begin
        r := ABars[i].BoundsRect;
        if ABars[i].Kind = sbVertical then need := r.Bottom - r.Top else need := r.Right - r.Left;
        onBar := 0;
        for y := r.Top to r.Bottom - 1 do
          for x := r.Left to r.Right - 1 do
            if RingStrength(bare.GetPixel(x, y)) > 0 then Inc(onBar);
        AssertTrue(Format('%s 条[%d]:前置条件——宿主有焦点时,条那一段底下有焦点环(%d < %d)',
          [AWhat, i, onBar, need]), onBar >= need);
        { 条叠上去之后焦点环还在条上。从前完全可见的条会把焦点环截断在条那一段(备忘录当初
          内缩就是为了这个)。 }
        onBar := 0;
        for y := r.Top to r.Bottom - 1 do
          for x := r.Left to r.Right - 1 do
            if RingStrength(over.GetPixel(x, y)) > 0 then Inc(onBar);
        AssertTrue(Format('%s 条[%d]:完全可见的条上看不到焦点环(%d < %d)',
          [AWhat, i, onBar, need]), onBar >= need);
      end;
    finally
      FreeAndNil(bare);
      FreeAndNil(over);
    end;
    { 而且逐像素与宿主自己画的那一圈一致。 }
    CheckFrameIntact(AWhat, ARender, ABars, 4, 6 + 6);
  end;

begin
  NeedWidgetSet;
  FCtl.LoadThemeCss(FrameCss(6, 1,
    'TyListBox:focus, TyMemo:focus { border-color: #FF0000; outline: 2px #00B000; }'));
  win := TForm.CreateNew(nil);
  try
    win.Color := Ground;
    { 屏幕外,但真的显示出来:CanFocus 要求一路 Visible 到顶。 }
    win.SetBounds(-4000, -4000, 480, 360);
    win.Visible := True;
    win.HandleNeeded;
    park := TTyButton.Create(win);
    park.Parent := win;
    park.Controller := FCtl;
    park.SetBounds(300, 300, 80, 26);
    park.HandleNeeded;

    lb := MakeListBox(False, HostW, HostH, 96, False, win);
    lb.HandleNeeded;
    CheckRing('TTyListBox', lb, @lb.Render, [FindBar(lb, sbVertical)]);

    lb.Visible := False;
    mm := MakeMemo(True, win);
    mm.HandleNeeded;
    CheckRing('TTyMemo', mm, @mm.Render, [FindBar(mm, sbVertical), FindBar(mm, sbHorizontal)]);
  finally
    win.Free;
  end;
end;

procedure TScrollBarHostFrameTests.FocusingTheHostRepaintsItsBars;
var
  win: TForm;
  park: TTyButton;
  lb: TFrameListBox;
  v, hb: TTyScrollBar;
  v0, h0: Cardinal;
begin
  { 条画的是宿主的框,宿主一拿到焦点,条那一段就得跟着把焦点环画出来。条是窗口化子控件,
    宿主的重画够不着它那块矩形 —— 不让条自己重画,屏幕上条那一段就一直是没焦点时的框。
    无头看不见窗口重画,能看见的是条的 Invalidate 有没有被叫到;计数在真正的 Invalidate
    里,不是旁路。**两次读数之间不跑消息循环**:否则宿主那一帧重画里的杂事也可能碰到条,
    这条就分不清是谁叫的。 }
  NeedWidgetSet;
  FCtl.LoadThemeCss(FrameCss(6, 1, 'TyListBox:focus { outline: 2px #00B000; }'));
  win := TForm.CreateNew(nil);
  try
    win.SetBounds(-4000, -4000, 480, 360);
    win.Visible := True;
    win.HandleNeeded;
    park := TTyButton.Create(win);
    park.Parent := win;
    park.Controller := FCtl;
    park.SetBounds(300, 300, 80, 26);
    park.HandleNeeded;
    lb := MakeListBox(True, HostW, HostH, 96, False, win);
    lb.HandleNeeded;
    Forms.Application.ProcessMessages;
    park.SetFocus;
    Forms.Application.ProcessMessages;
    AssertFalse('前置条件:焦点先停在别处', lb.Focused);

    v := FindBar(lb, sbVertical);
    hb := FindBar(lb, sbHorizontal);
    AssertNotNull('前置条件:两条都在', hb);
    v0 := TFrameBar(v).Invalidations;
    h0 := TFrameBar(hb).Invalidations;
    lb.SetFocus;
    AssertTrue('前置条件:宿主真的拿到了焦点', lb.Focused);
    AssertTrue(Format('宿主获得焦点,竖条必须跟着重画(%d -> %d)',
      [v0, TFrameBar(v).Invalidations]), TFrameBar(v).Invalidations > v0);
    AssertTrue(Format('宿主获得焦点,横条必须跟着重画(%d -> %d)',
      [h0, TFrameBar(hb).Invalidations]), TFrameBar(hb).Invalidations > h0);

    v0 := TFrameBar(v).Invalidations;
    park.SetFocus;
    AssertFalse('前置条件:焦点离开了宿主', lb.Focused);
    AssertTrue('宿主失去焦点,竖条也必须跟着重画', TFrameBar(v).Invalidations > v0);
  finally
    win.Free;
  end;
end;

procedure TScrollBarHostFrameTests.EveryHostRepaintsItsBarsWhenItInvalidates;
var
  hosts: array[0..5] of TWinControl;
  names: array[0..5] of string;
  i, k: Integer;
  bars: array[0..1] of TTyScrollBar;
  before: array[0..1] of Cardinal;
begin
  { 框会变的理由一长串(焦点、悬停、按下、禁用、StyleClass、StyleOverride、换 controller),
    全部以宿主的一句 Invalidate 收尾。挂钩在那一句上,六个宿主一个都不能漏:哪个宿主没实现
    ITyScrollBarFrameHost,它的条就不会跟着重画。 }
  hosts[0] := MakeListBox(True);  names[0] := 'TTyListBox';
  hosts[1] := MakeMemo(True);     names[1] := 'TTyMemo';
  hosts[2] := MakeGrid(True);     names[2] := 'TTyStringGrid';
  hosts[3] := MakeListView(True); names[3] := 'TTyListView';
  hosts[4] := MakeTree;           names[4] := 'TTyTreeView';
  hosts[5] := MakeScrollBox;      names[5] := 'TTyScrollBox';
  for i := 0 to High(hosts) do
  begin
    bars[0] := FindBar(hosts[i], sbVertical);
    bars[1] := FindBar(hosts[i], sbHorizontal);
    AssertTrue(names[i] + ':前置条件——竖条可见', (bars[0] <> nil) and bars[0].Visible);
    for k := 0 to 1 do
      if bars[k] <> nil then before[k] := TFrameBar(bars[k]).Invalidations;
    hosts[i].Invalidate;
    for k := 0 to 1 do
      if (bars[k] <> nil) and bars[k].Visible then
        AssertTrue(Format('%s:宿主 Invalidate,条[%d]必须跟着重画', [names[i], k]),
          TFrameBar(bars[k]).Invalidations > before[k]);
  end;
end;

procedure TScrollBarHostFrameTests.AStandaloneBarIsNotRepaintedByItsParent;
var
  panel: TTyPanel;
  bar: TTyScrollBar;
  n: Cardinal;
begin
  { 反方向:随手摆在面板上的条没替面板画框,面板重画不该拖着它重画。否则上面那条挂钩
    只要写成「所有子控件都重画」就绿了,而每个装满控件的容器每次重画都会多出一整排重画。 }
  panel := TTyPanel.Create(FForm);
  panel.Parent := FForm;
  panel.Controller := FCtl;
  panel.SetBounds(0, 0, 200, 200);
  bar := TTyScrollBar.Create(FForm);
  bar.Parent := panel;
  bar.Controller := FCtl;
  bar.SetBounds(0, 0, 16, 160);
  n := TFrameBar(bar).Invalidations;
  panel.Invalidate;
  AssertEquals('独立摆放的条不替父控件画框,父控件重画不该叫它', n, TFrameBar(bar).Invalidations);
end;

{ ---- 淡出途中合成到真实的背景上 ------------------------------------------------ }

procedure TScrollBarHostFrameTests.MidFadeOverAGradientHostShowsTheGradient;
var
  lb: TFrameListBox;
  bar: TTyScrollBar;
  bare, over: TBGRABitmap;
  x, yA, yB, bareSpread, overSpread: Integer;
begin
  { 宿主的底色是自上而下的渐变。从前淡出走画笔的 opacity:EndPaint 先铺一块从正中间取样的
    **一个颜色**,再按 opacity 盖上去 —— 条那一列上下两头一模一样(实测上下差 0,真背景差
    221)。现在条身合成到真实的底层上,条那一列必须跟着渐变走。 }
  FCtl.LoadThemeCss(FrameCss(6, 1,
    'TyListBox { background: linear-gradient(90deg, #000000, #FFFFFF); }'));
  lb := MakeListBox;
  bar := FindBar(lb, sbVertical);
  SetFade(bar, bfMid);
  x := bar.Left + bar.Width div 2;
  yA := 40;                     { 滑道里:滑块在顶上(Position=0,12..24 行),两头是箭头 }
  yB := HostH - 20;
  bare := Shoot(@lb.Render, [bar], False);
  over := Shoot(@lb.Render, [bar], True);
  try
    bareSpread := Abs(bare.GetPixel(x, yB).green - bare.GetPixel(x, yA).green);
    overSpread := Abs(over.GetPixel(x, yB).green - over.GetPixel(x, yA).green);
    AssertTrue(Format('前置条件:宿主的底色在这两行之间真的在变(差 %d)', [bareSpread]),
      bareSpread > 50);
    AssertTrue(Format('前置条件:条身确实合成上去了(%s 对 %s)',
      [PixelHex(over.GetPixel(x, yA)), PixelHex(bare.GetPixel(x, yA))]),
      not Same(over.GetPixel(x, yA), bare.GetPixel(x, yA)));
    { 可见度 ~0.3 的条身盖在上面,透出来的渐变应当剩七成左右;平板是 0。取一半做门槛。 }
    AssertTrue(Format('淡出途中条那一列要透出渐变,不是一块平板(条上差 %d,背景差 %d)',
      [overSpread, bareSpread]), overSpread * 2 >= bareSpread);
  finally
    bare.Free;
    over.Free;
    lb.Free;
  end;
end;

{ ---- 条的两条长边:贴边那侧与内容那侧 ------------------------------------------------

  真机报的是「滚动条左右的渲染好奇怪」。从前条身(滑道、滑块、箭头、条自己的圆角和焦点环)按
  **整条**矩形排,而贴边那一侧最外两三列随后被整列换成宿主的框 —— 于是凡是左右对称画的东西
  都在内容侧完整、在贴边侧被削掉一截:滑块内侧有抗锯齿的圆边、贴边侧齐刷刷截断;条自己的焦点环
  内侧一整条腿、贴边侧只剩半条;箭头偏向边框一个像素;条自己的 4px 圆角在内容侧两端各露出一个
  宿主底色的缺口;滑道内沿是半透明的一列(圆角矩形的抗锯齿边,与宿主白底混成浅色细线)。

  判据按**看得见的那一截**说话:条的哪条边贴着宿主外沿,那条边让开宿主框此刻占掉的那一圈
  (夹具 1px 边框 -> 2 列;宿主带 2px 焦点环 -> 3 列)。剩下那一截里条身必须左右(横条上下)
  镜像对称,而且滑道是方的、一直铺到框的内沿。

  颜色:滑道 #C8C800(红=绿、蓝 0)、滑块 #2020A0、条自己的焦点环 #00B000 —— 宿主白底、红框、
  蓝父背景怎么混都混不出这三种,所以「内沿那一列正好是滑道色」不会被别的层碰巧满足。 }

function EdgeCss(ARadius: Integer; const AExtra: string = ''): string;
begin
  Result :=
    ':root { --scrollbar-size: 12; --scrollbar-auto-hide: 1000; }' +
    'TyListBox { background: #FFFFFF; color: #000000; border-color: #FF0000;' +
    '  border-width: 1px; border-radius: ' + IntToStr(ARadius) + 'px; padding: 0px; }' +
    { 条自己的圆角是**真主题的值**(--radius-scroll: 4px),不是 0:内容侧两端的缺口就是它露出来的。 }
    'TyScrollBar { background: #C8C800; color: #404040; border-width: 0px; border-radius: 4px; }' +
    'TyScrollThumb { background: #2020A0; border-radius: 4px; }' + AExtra;
end;

{ 条那块矩形里宿主的框没占掉的那一截:条的哪条边贴着宿主外沿,那条边就让开 ABand。 }
function VisibleSpan(AHost: TControl; ABar: TTyScrollBar; ABand: Integer): TRect;
begin
  Result := ABar.BoundsRect;
  if Result.Left <= 0 then Inc(Result.Left, ABand);
  if Result.Top <= 0 then Inc(Result.Top, ABand);
  if Result.Right >= AHost.Width then Dec(Result.Right, ABand);
  if Result.Bottom >= AHost.Height then Dec(Result.Bottom, ABand);
end;

{ 横跨条的第 AU 列(从**内容侧**数起,0 = 可见那一截的内沿;数到可见宽度以外就进了宿主的框),
  沿条方向的坐标 AV(宿主坐标)。竖条停在左边(RTL)时内容侧在右。 }
function AcrossPixel(ABmp: TBGRABitmap; ABar: TTyScrollBar; const ASpan: TRect;
  AU, AV: Integer): TBGRAPixel;
begin
  if ABar.Kind = sbHorizontal then
    Result := ABmp.GetPixel(AV, ASpan.Top + AU)
  else if ABar.Left <= 0 then
    Result := ABmp.GetPixel(ASpan.Right - 1 - AU, AV)
  else
    Result := ABmp.GetPixel(ASpan.Left + AU, AV);
end;

function SpanWidth(ABar: TTyScrollBar; const ASpan: TRect): Integer;
begin
  if ABar.Kind = sbVertical then Result := ASpan.Right - ASpan.Left
  else Result := ASpan.Bottom - ASpan.Top;
end;

procedure TScrollBarHostFrameTests.AnEmbeddedBarIsSymmetricAcrossTheWidthTheFrameLeavesIt;
const
  Track: TBGRAPixel = (blue: $00; green: $C8; red: $C8; alpha: $FF);
var
  pass, rad: Integer;
  lb: TFrameListBox;
  f: TBarFade;

  procedure CheckBar(const AWhat: string; ABar: TTyScrollBar; ABand: Integer; ARing: Boolean);
  var
    over: TBGRABitmap;
    span: TRect;
    n, u, v, lo, hi, thumbHits, ringIn, ringOut: Integer;
    pa, pb: TBGRAPixel;
    bad: string;
  begin
    AssertNotNull(AWhat + ':前置条件——条存在', ABar);
    SetFade(ABar, f);
    over := Shoot(@lb.Render, [ABar], True);
    try
      span := VisibleSpan(lb, ABar, ABand);
      n := SpanWidth(ABar, span);
      AssertTrue(Format('%s:前置条件——条贴边,可见那一截比整条窄(%d / 12)', [AWhat, n]),
        (n >= 6) and (n < 12));
      if ABar.Kind = sbVertical then
      begin
        lo := span.Top; hi := span.Bottom;
      end
      else
      begin
        lo := span.Left; hi := span.Right;
      end;
      { 沿条方向避开宿主圆角那几行:弧只弯在贴边那一侧,那几行本来就不对称。 }
      if rad > 0 then
      begin
        Inc(lo, rad + 2);
        Dec(hi, rad + 2);
      end;
      bad := '';
      thumbHits := 0; ringIn := 0; ringOut := 0;
      for v := lo to hi - 1 do
        for u := 0 to n div 2 - 1 do
        begin
          pa := AcrossPixel(over, ABar, span, u, v);
          pb := AcrossPixel(over, ABar, span, n - 1 - u, v);
          { 滑块 #2020A0 是这张图里唯一蓝比红绿都高的东西(父背景的蓝只在圆角外,那几行避开了);
            淡出途中它与白底混,蓝照样领先。 }
          if (pa.blue > pa.red + 20) and (pa.blue > pa.green + 20) then Inc(thumbHits);
          if RingStrength(pa) > 20 then Inc(ringIn);
          if RingStrength(pb) > 20 then Inc(ringOut);
          if (bad = '') and not ((Abs(pa.red - pb.red) <= 3) and (Abs(pa.green - pb.green) <= 3)
            and (Abs(pa.blue - pb.blue) <= 3)) then
            bad := Format('%s:沿条 %d 处,内容侧第 %d 列是 %s,贴边侧对应那一列是 %s',
              [AWhat, v, u, PixelHex(pa), PixelHex(pb)]);
        end;
      { 非空:看的这一截里真有滑块;带焦点环的那一轮两条腿都得真有环。 }
      AssertTrue(AWhat + ':前置条件——看的那一截里有滑块', thumbHits > 0);
      if ARing then
        AssertTrue(Format('%s:前置条件——条自己的焦点环两条腿都在(内侧 %d,贴边侧 %d)',
          [AWhat, ringIn, ringOut]), (ringIn > 0) and (ringOut > 0));
      { 滑道色确实出现在内沿上(完全可见时):对称的「全是宿主白底」也是对称,不算数。 }
      if (f = bfVisible) and not ARing then
      begin
        pa := AcrossPixel(over, ABar, span, n div 2, lo + (hi - lo) * 3 div 4);
        AssertTrue(Format('%s:前置条件——内沿是滑道,不是别的什么(%s)', [AWhat, PixelHex(pa)]),
          Near(pa, Track));
      end;
      AssertEquals(AWhat + ':条身在可见那一截里必须镜像对称', '', bad);
    finally
      over.Free;
    end;
  end;

begin
  { pass 0:宿主静止(框 = 1px 边,让 2 列)。pass 1:条自己带焦点环(夹具直接写在 base 上,
    不必真给焦点 —— 判的是它画在哪)。pass 2:宿主带 2px 焦点环(让 3 列)。 }
  for pass := 0 to 2 do
    for rad := 0 to 1 do
      for f := bfVisible to bfMid do
      begin
        case pass of
          0: FCtl.LoadThemeCss(EdgeCss(rad * 6));
          1: FCtl.LoadThemeCss(EdgeCss(rad * 6, 'TyScrollBar { outline: 2px #00B000; }'));
          2: FCtl.LoadThemeCss(EdgeCss(rad * 6, 'TyListBox { outline: 2px #00B000; }'));
        end;
        lb := MakeListBox;
        try
          CheckBar(Format('竖条 pass=%d r=%d fade=%d', [pass, rad * 6, Ord(f)]),
            FindBar(lb, sbVertical), 2 + Ord(pass = 2), pass = 1);
        finally
          lb.Free;
        end;
        lb := MakeListBox(False, HostW, HostH, 96, True);
        try
          CheckBar(Format('RTL 竖条 pass=%d r=%d fade=%d', [pass, rad * 6, Ord(f)]),
            FindBar(lb, sbVertical), 2 + Ord(pass = 2), pass = 1);
        finally
          lb.Free;
        end;
        lb := MakeListBox(True);
        try
          CheckBar(Format('横条 pass=%d r=%d fade=%d', [pass, rad * 6, Ord(f)]),
            FindBar(lb, sbHorizontal), 2 + Ord(pass = 2), pass = 1);
        finally
          lb.Free;
        end;
      end;
end;

procedure TScrollBarHostFrameTests.AnEmbeddedTrackIsSquareAndRunsIntoTheFrame;
const
  Track: TBGRAPixel = (blue: $00; green: $C8; red: $C8; alpha: $FF);
var
  rad, which: Integer;
  lb: TFrameListBox;
  bar: TTyScrollBar;
  over, bare: TBGRABitmap;
  span: TRect;
  n, u, mid, lo, hi, bw: Integer;
  what: string;

  procedure ExpectTrack(const AWhere: string; AU, AV: Integer);
  var p: TBGRAPixel;
  begin
    p := AcrossPixel(over, bar, span, AU, AV);
    AssertTrue(Format('%s:%s 应是滑道色 C8C800,实为 %s', [what, AWhere, PixelHex(p)]),
      Near(p, Track));
  end;

begin
  for rad := 0 to 1 do
    for which := 0 to 2 do
    begin
      FCtl.LoadThemeCss(EdgeCss(rad * 6));
      case which of
        0: lb := MakeListBox;
        1: lb := MakeListBox(False, HostW, HostH, 96, True);
      else
        lb := MakeListBox(True);
      end;
      over := nil;
      bare := nil;
      try
        if which = 2 then bar := FindBar(lb, sbHorizontal) else bar := FindBar(lb, sbVertical);
        case which of
          0: what := '竖条';
          1: what := 'RTL 竖条';
        else
          what := '横条';
        end;
        what := Format('%s r=%d', [what, rad * 6]);
        SetFade(bar, bfVisible);
        over := Shoot(@lb.Render, [bar], True);
        bare := Shoot(@lb.Render, [bar], False);
        span := VisibleSpan(lb, bar, 2);
        n := SpanWidth(bar, span);
        if bar.Kind = sbVertical then
        begin
          lo := span.Top; hi := span.Bottom; bw := bar.Width;
        end
        else
        begin
          lo := span.Left; hi := span.Right; bw := bar.Height;
        end;
        { 滑块在最前头(Position = 0),四分之三处是空滑道,离箭头也远。 }
        mid := lo + (hi - lo) * 3 div 4;

        { 内容侧:内沿那一列就是滑道色 —— 不是滑道与宿主底色各一半的浅线。 }
        ExpectTrack('内容侧内沿那一列', 0, mid);
        { 内容侧两端:条自己的圆角不许在这里切出宿主底色的缺口。条贴着宿主一整条边,它的形状
          归宿主(贴边侧的圆角由宿主底色的形状裁),不归它自己的 border-radius。 }
        ExpectTrack('内容侧起头那一角', 0, lo);
        ExpectTrack('内容侧末尾那一角', 0, hi - 1);
        { 贴边侧:滑道一直铺到框的内沿,中间不夹宿主底色的细缝;框那几列与宿主单画时一致。 }
        ExpectTrack('贴边侧紧挨框的那一列', n - 1, mid);
        for u := n to bw - 1 do
        begin
          AssertTrue(Format('%s:贴边侧第 %d 列应是宿主的框(%s)', [what, u,
            PixelHex(AcrossPixel(bare, bar, span, u, mid))]),
            FrameStrength(AcrossPixel(bare, bar, span, u, mid)) > 0);
          AssertTrue(Format('%s:贴边侧第 %d 列,宿主画 %s,叠上条变成 %s', [what, u,
            PixelHex(AcrossPixel(bare, bar, span, u, mid)),
            PixelHex(AcrossPixel(over, bar, span, u, mid))]),
            Near(AcrossPixel(bare, bar, span, u, mid), AcrossPixel(over, bar, span, u, mid)));
        end;
      finally
        over.Free;
        bare.Free;
        lb.Free;
      end;
    end;
end;

procedure TScrollBarHostFrameTests.AnEmbeddedTrackFollowsTheEmbeddedRadiusToken;
const
  Track: TBGRAPixel = (blue: $00; green: $C8; red: $C8; alpha: $FF);
var
  tok, which: Integer;
  lb: TFrameListBox;
  bar: TTyScrollBar;
  over: TBGRABitmap;
  span: TRect;
  lo, hi, mid: Integer;
  what: string;

  function At(AU, AV: Integer): TBGRAPixel;
  begin
    Result := AcrossPixel(over, bar, span, AU, AV);
  end;

begin
  { 内嵌滑道的方角是主题给的(--radius-scroll-embedded),不是代码里写死的 0。
    令牌 0 -> 内容侧两端那一角是滑道色;令牌 6 -> 那一角被滑道自己的圆角切掉,露出宿主的白底。
    宿主方角(r=0),免得宿主自己的弧也来切这一角,「切掉了」就分不清是谁切的。
    条自己的 border-radius 留着夹具的 4px(真主题的 --radius-scroll):读错成它的话令牌 0 那一轮
    是圆的,红;写死 0 的话令牌 6 那一轮是方的,红。 }
  for tok := 0 to 1 do
    for which := 0 to 2 do
    begin
      FCtl.LoadThemeCss(EdgeCss(0,
        ':root { --radius-scroll-embedded: ' + IntToStr(tok * 6) + 'px; }'));
      AssertEquals('前置条件:令牌解出来就是夹具写的值', tok * 6,
        FCtl.Metric('--radius-scroll-embedded', -1));
      case which of
        0: lb := MakeListBox;
        1: lb := MakeListBox(False, HostW, HostH, 96, True);
      else
        lb := MakeListBox(True);
      end;
      over := nil;
      try
        if which = 2 then bar := FindBar(lb, sbHorizontal) else bar := FindBar(lb, sbVertical);
        case which of
          0: what := '竖条';
          1: what := 'RTL 竖条';
        else
          what := '横条';
        end;
        what := Format('%s 令牌=%d', [what, tok * 6]);
        SetFade(bar, bfVisible);
        over := Shoot(@lb.Render, [bar], True);
        span := VisibleSpan(lb, bar, 2);
        if bar.Kind = sbVertical then
        begin
          lo := span.Top; hi := span.Bottom;
        end
        else
        begin
          lo := span.Left; hi := span.Right;
        end;
        mid := lo + (hi - lo) * 3 div 4;
        { 前置条件:条身真画上去了。看内沿往里一列 —— 令牌非零时滑道是圆角矩形,它的直边内沿
          那一列本来就是抗锯齿的半透明(与宿主白底混成浅色),那是皮肤选圆角的代价,不是这里要判的。 }
        AssertTrue(Format('%s:前置条件——内容侧往里一列中段是滑道色,实为 %s',
          [what, PixelHex(At(1, mid))]), Near(At(1, mid), Track));
        if tok = 0 then
        begin
          AssertTrue(Format('%s:内容侧起头那一角应是方的(滑道色),实为 %s',
            [what, PixelHex(At(0, lo))]), Near(At(0, lo), Track));
          if which <> 2 then
            AssertTrue(Format('%s:内容侧末尾那一角应是方的(滑道色),实为 %s',
              [what, PixelHex(At(0, hi - 1))]), Near(At(0, hi - 1), Track));
        end
        else
        begin
          { 滑道色蓝 = 0,宿主白底蓝 = 255:这一角绝大部分是白底才算被圆角切掉。 }
          AssertTrue(Format('%s:内容侧起头那一角应被令牌的圆角切掉(露出宿主白底),实为 %s',
            [what, PixelHex(At(0, lo))]), At(0, lo).blue >= 160);
          { 横条的末尾挨着竖条留下的角格,不在宿主边上,只看竖条的。 }
          if which <> 2 then
            AssertTrue(Format('%s:内容侧末尾那一角应被令牌的圆角切掉,实为 %s',
              [what, PixelHex(At(0, hi - 1))]), At(0, hi - 1).blue >= 160);
        end;
      finally
        over.Free;
        lb.Free;
      end;
    end;
end;

{ ---- 点内嵌条:焦点归宿主 ----------------------------------------------------------

  六个宿主建内嵌条时一律 TabStop := False,理由也都写着:拖条不能把焦点从列表抢走,否则列表
  丢了焦点环、滚到一半键盘导航也没了。设计文档(2026-09-14-scrollbar-auto-hide-design.md §4)
  写着内嵌条拿不到焦点。而 TTyScrollBar.MouseDown 里从前是一句无条件的
  if CanFocus then SetFocus —— 一点就把焦点给了条:条画起自己的焦点环(真机上一圈蓝框套着
  12px 的细条,挨着宿主的灰边框,读起来是两道边),方向键滚的是条不是列表。

  这几条走真实消息路径:显示出来的屏幕外窗体、焦点先停在别处、Perform(LM_LBUTTONDOWN) 直进
  条自己的 WindowProc(与 test.focus.tabstop 的 TTyClickFocusTest 同一个入口)。只建句柄不
  Show 的窗体上 CanFocus 恒假,每一条都会空转地绿。 }

procedure TScrollBarHostFrameTests.TrapException(Sender: TObject; E: Exception);
begin
  if FTrapped = '' then
    FTrapped := E.ClassName + ': ' + E.Message;
end;

procedure TScrollBarHostFrameTests.AssertNothingRaised(const AWhere: string);
var
  s: string;
begin
  if FTrapped = '' then Exit;
  s := FTrapped;
  FTrapped := '';
  Fail(AWhere + ':焦点/点击的消息路径上抛了异常(没有陷阱的话 LCL 会弹模态框卡死整个套件):' + s);
end;

procedure TScrollBarHostFrameTests.OpenWindow;
begin
  NeedWidgetSet;
  FTrapped := '';
  FPrevOnException := Forms.Application.OnException;
  Forms.Application.OnException := @TrapException;
  FTrapInstalled := True;
  FWin := TForm.CreateNew(nil);
  FWin.Color := Ground;
  FWin.SetBounds(-4000, -4000, 480, 360);
  FWin.Visible := True;
  FWin.HandleNeeded;
  FPark := TTyButton.Create(FWin);
  FPark.Parent := FWin;
  FPark.Controller := FCtl;
  FPark.SetBounds(360, 300, 80, 26);
  FPark.HandleNeeded;
end;

procedure TScrollBarHostFrameTests.ParkFocus;
begin
  FPark.SetFocus;
  Forms.Application.ProcessMessages;
  AssertSame('前置条件:焦点先停在停靠按钮上', TWinControl(FPark), FindOwnerControl(GetFocus));
end;

{ widgetset 把点击坐标打包进 lParam 的方式。 }
function ClickPos(X, Y: Integer): PtrInt;
begin
  Result := PtrInt((Y shl 16) or (X and $FFFF));
end;

procedure TScrollBarHostFrameTests.ClickBar(ABar: TTyScrollBar; AX, AY: Integer);
begin
  ABar.Perform(LM_LBUTTONDOWN, MK_LBUTTON, ClickPos(AX, AY));
  Forms.Application.ProcessMessages;
  ABar.Perform(LM_LBUTTONUP, 0, ClickPos(AX, AY));
  Forms.Application.ProcessMessages;
end;

{ 滑块中心,条自己的客户区坐标。与 MouseDown 的命中测试同一套几何。 }
function ThumbCenter(ABar: TTyScrollBar): TPoint;
var
  r, t: TRect;
begin
  r := Rect(0, 0, ABar.Width, ABar.Height);
  t := TyScrollTrackRect(r, ABar.Kind, TyScrollButtonSize(r, ABar.Kind));
  t := TyScrollThumbRect(t, ABar.Kind, ABar.Min, ABar.Max, ABar.Position, ABar.PageSize);
  Result := Point((t.Left + t.Right) div 2, (t.Top + t.Bottom) div 2);
end;

procedure TScrollBarHostFrameTests.ClickingAnEmbeddedBarFocusesItsHostAndTheKeysGoThere;
var
  i: Integer;
  host, focused: TWinControl;
  hname: string;
  bar: TTyScrollBar;
begin
  { 五个参与焦点的宿主(滚动框默认不参与,见下一条)。点在竖条滑道的下半段:滑块在顶上
    (Position = 0),这一下翻一页 —— Position 变了就证明点击真的落到了条上。 }
  OpenWindow;
  for i := 0 to 4 do
  begin
    case i of
      0: begin host := MakeListBox(False, HostW, HostH, 96, False, FWin); hname := 'TTyListBox'; end;
      1: begin host := MakeMemo(False, FWin);     hname := 'TTyMemo'; end;
      2: begin host := MakeGrid(False, FWin);     hname := 'TTyStringGrid'; end;
      3: begin host := MakeListView(False, FWin); hname := 'TTyListView'; end;
    else
      begin host := MakeTree(FWin); hname := 'TTyTreeView'; end;
    end;
    host.HandleNeeded;
    bar := FindBar(host, sbVertical);
    AssertTrue(hname + ':前置条件——竖条在、看得见', (bar <> nil) and bar.Visible);
    AssertTrue(hname + ':前置条件——宿主参与焦点', host.TabStop and host.CanFocus);
    AssertTrue(hname + ':前置条件——这是宿主自己的内嵌条', bar.IsEmbedded);
    bar.HandleNeeded;
    ParkFocus;

    ClickBar(bar, bar.Width div 2, bar.Height - bar.Width - 4);
    AssertNothingRaised(hname);
    AssertTrue(hname + ':前置条件——点中了滑道,翻了一页', bar.Position > 0);
    focused := FindOwnerControl(GetFocus);
    AssertFalse(hname + ':点内嵌条,焦点不许落在条上', bar.Focused);
    AssertSame(hname + ':点内嵌条,焦点归宿主', host, focused);

    if i = 0 then
    begin
      { 方向键落在宿主上 —— 这才是把焦点交给宿主的意义。按 widgetset 投递按键的方式:
        CN_KEYDOWN 发给**此刻有焦点的那个控件**(不是直接发给列表,那样证明不了键去了哪儿)。
        焦点若还在条上,这一下滚的是条,选中项不会动。 }
      TFrameListBox(host).ItemIndex := 5;
      Forms.Application.ProcessMessages;
      focused := FindOwnerControl(GetFocus);
      focused.Perform(CN_KEYDOWN, VK_DOWN, 0);
      Forms.Application.ProcessMessages;
      AssertNothingRaised(hname + ' 方向键');
      AssertEquals(hname + ':点过条之后按下方向键,移动的是列表的选中项', 6,
        TFrameListBox(host).ItemIndex);

      { 条若被代码 SetFocus 过(树把 VScroll 公开着),它也在宿主「里面」,但那不算焦点已经
        在宿主里:点一下照样挪给宿主。 }
      bar.SetFocus;
      Forms.Application.ProcessMessages;
      AssertSame(hname + ':前置条件——代码把焦点给了条', TWinControl(bar), FindOwnerControl(GetFocus));
      ClickBar(bar, bar.Width div 2, bar.Height - bar.Width - 4);
      AssertNothingRaised(hname + ' 条自己有焦点时点它');
      AssertSame(hname + ':条自己有焦点时点它,焦点也归宿主', host, FindOwnerControl(GetFocus));
    end;
    host.Visible := False;
  end;
end;

procedure TScrollBarHostFrameTests.ClickingAStandaloneBarStillFocusesTheBar;
var
  pass: Integer;
  bar: TTyScrollBar;
begin
  { 反方向:摆在窗体上的独立条,点它照样拿焦点 —— 它有完整的键盘操作,焦点也是自动隐藏
    「按住不放」的信号。第二轮关掉 TabStop:那只是「不进 Tab 顺序」,点它仍该拿到焦点。
    所以「内嵌」不能拿 TabStop 来判:拿它判的话第二轮红。 }
  OpenWindow;
  for pass := 0 to 1 do
  begin
    bar := TTyScrollBar.Create(FWin);
    bar.Parent := FWin;
    bar.Controller := FCtl;
    bar.SetBounds(200 + pass * 40, 20, 12, 160);
    bar.TabStop := pass = 0;
    bar.HandleNeeded;
    AssertFalse('前置条件:摆在窗体上的条不是内嵌条', bar.IsEmbedded);
    ParkFocus;
    ClickBar(bar, 6, 160 - 12 - 4);
    AssertNothingRaised('独立条');
    AssertTrue('前置条件:点中了滑道,翻了一页', bar.Position > 0);
    AssertSame(Format('TabStop=%s 的独立条,点它必须拿到焦点', [BoolToStr(bar.TabStop, True)]),
      TWinControl(bar), FindOwnerControl(GetFocus));
  end;
end;

procedure TScrollBarHostFrameTests.ABarDroppedIntoAScrollBoxIsNotEmbedded;
var
  box: TFrameScrollBox;
  own, user: TTyScrollBar;
  n: Cardinal;
  shot: TBitmap;
  re: TBGRABitmap;
begin
  { 滚动框是容器,用户完全可以往里拖一根自己的条。它的 Parent 同样实现
    ITyScrollBarFrameHost —— 只按「父控件实现了接口」判内嵌的话,它会被当成滚动框的内嵌条:
    不画自己的框、跟着滚动框重画、点它焦点被转走(TabStop=False 的滚动框还转不走,焦点原地
    不动)。「内嵌」得由宿主亲口说是它自己建的那几根。 }
  OpenWindow;
  box := MakeScrollBox(FWin);
  box.HandleNeeded;
  own := FindBar(box, sbVertical);
  AssertTrue('前置条件:滚动框自己的竖条在', own <> nil);
  AssertTrue('滚动框自己建的条是内嵌条', own.IsEmbedded);

  user := TTyScrollBar.Create(FWin);
  user.Parent := box;
  user.Controller := FCtl;
  user.SetBounds(20, 20, 12, 80);
  user.TabStop := False;   { 顺带排除「拿 TabStop 判」 }
  user.HandleNeeded;
  AssertSame('前置条件:用户那根条的父控件就是滚动框', TWinControl(box), user.Parent);

  { 三处读「内嵌」的地方(重画挂钩、绘制分支、点击后的焦点)各验一遍行为,最后才问 IsEmbedded
    本身 —— 只验那个查询的话,哪一处绕开它自己去问「父控件实现了接口没有」都照样绿。 }

  { 1. 不替滚动框画框,滚动框重画不拖着它重画。 }
  n := TFrameBar(user).Invalidations;
  box.Invalidate;
  AssertEquals('拖进滚动框的条不替滚动框画框,滚动框重画不该叫它', n, TFrameBar(user).Invalidations);

  { 2. 画的是自己的药丸:左上角被它自己 4px 的圆角切掉。当成内嵌条的话走宿主那条路,滑道方角
    (令牌 0),那一角就是滑道色。 }
  FCtl.LoadThemeCss(EdgeCss(0) + 'TyScrollBox { background: #FFFFFF; border-width: 0px; padding: 0px; }');
  shot := TBitmap.Create;
  re := nil;
  try
    shot.PixelFormat := pf32bit;
    shot.SetSize(12, 80);
    shot.Canvas.Brush.Color := Wipe;
    shot.Canvas.FillRect(0, 0, 12, 80);
    TFrameBar(user).RenderInto(shot.Canvas, Rect(0, 0, 12, 80), 96);
    re := TBGRABitmap.Create(shot);
    AssertTrue(Format('前置条件:条身真画上去了(中段 %s)', [PixelHex(re.GetPixel(6, 60))]),
      Near(re.GetPixel(6, 60), TBGRAPixel(BGRA($C8, $C8, $00))));
    AssertFalse(Format('拖进滚动框的条画自己的圆角,左上角不该是滑道色(%s)',
      [PixelHex(re.GetPixel(0, 0))]), Near(re.GetPixel(0, 0), TBGRAPixel(BGRA($C8, $C8, $00))));
  finally
    re.Free;
    shot.Free;
  end;

  { 3. 点它拿焦点。 }
  ParkFocus;
  ClickBar(user, 6, 80 - 12 - 4);
  AssertNothingRaised('滚动框里的独立条');
  AssertTrue('前置条件:点中了滑道,翻了一页', user.Position > 0);
  AssertSame('拖进滚动框的独立条,点它必须拿到焦点', TWinControl(user), FindOwnerControl(GetFocus));

  AssertFalse('拖进滚动框的条不是内嵌条', user.IsEmbedded);
end;

procedure TScrollBarHostFrameTests.ClickingAnEmbeddedBarLeavesFocusAloneWhenTheHostTakesNone;
var
  box: TFrameScrollBox;
  bar: TTyScrollBar;
begin
  { 宿主自己不参与焦点(滚动框默认 TabStop=False,点它的空白也不拿焦点)。点它的条:条不拿,
    也不去硬塞给宿主 —— 焦点原地不动,与点滚动框本身一致。 }
  OpenWindow;
  box := MakeScrollBox(FWin);
  box.HandleNeeded;
  bar := FindBar(box, sbVertical);
  AssertTrue('前置条件:竖条在、看得见', (bar <> nil) and bar.Visible);
  AssertFalse('前置条件:滚动框默认不参与焦点', box.TabStop);
  AssertTrue('前置条件:但它此刻是 CanFocus 的 —— 不看 TabStop 就会把焦点塞给它', box.CanFocus);
  bar.HandleNeeded;
  ParkFocus;
  ClickBar(bar, bar.Width div 2, bar.Height - bar.Width - 4);
  AssertNothingRaised('滚动框');
  AssertTrue('前置条件:点中了滑道,翻了一页', bar.Position > 0);
  AssertSame('宿主不参与焦点:点它的条,焦点原地不动', TWinControl(FPark), FindOwnerControl(GetFocus));
end;

procedure TScrollBarHostFrameTests.ClickingAGridBarWhileEditingKeepsTheEditor;
var
  g: TFrameGrid;
  bar: TTyScrollBar;
  ed: TWinControl;
  c: TPoint;
begin
  { 焦点已经在宿主**里面**(网格的行内编辑器)。把焦点挪回网格本身,编辑器一失焦就提交并收起
    (TTyStringGrid.EditorExit)—— 滚一下就把正在改的格子结束掉,这不是滚动条该做的事。
    点的是滑块、原地松开:位置不动,只剩焦点这一件事,「翻页会不会收起编辑器」不混进来。 }
  OpenWindow;
  g := MakeGrid(True, FWin);
  g.HandleNeeded;
  bar := FindBar(g, sbVertical);
  AssertTrue('前置条件:竖条在、看得见', (bar <> nil) and bar.Visible);
  bar.HandleNeeded;
  ParkFocus;
  g.SetFocus;
  Forms.Application.ProcessMessages;
  AssertTrue('前置条件:进入编辑', g.BeginEdit(0, 1));
  Forms.Application.ProcessMessages;
  ed := g.InplaceEditor;
  AssertNotNull('前置条件:有行内编辑器', ed);
  AssertSame('前置条件:编辑器拿到了焦点', ed, FindOwnerControl(GetFocus));

  c := ThumbCenter(bar);
  ClickBar(bar, c.X, c.Y);
  AssertNothingRaised('网格编辑中');
  AssertEquals('前置条件:原地松开,位置没动', 0, bar.Position);
  AssertFalse('条不拿焦点', bar.Focused);
  AssertSame('焦点已经在宿主里面(编辑器),点条不许把它挪走', ed, FindOwnerControl(GetFocus));
  AssertTrue('编辑没有被结束', g.Editing);
end;

procedure TScrollBarHostFrameTests.DraggingAnEmbeddedThumbWorksWhileTheHostHasFocus;
var
  lb: TFrameListBox;
  bar: TTyScrollBar;
  c: TPoint;
  endPos: Integer;
begin
  { 按下滑块时焦点交给宿主 —— 这发生在 MouseDown 里、鼠标捕获之后。拖动整条链不能因此断:
    捕获还在条上、FDragging 还是真、移动推得动 Position 和宿主的滚动、松手收尾(EndThumbDrag
    提交、释放捕获)。自动隐藏在拖动途中靠 FDragging 按住,不指望条有焦点;松手之后照常淡出。 }
  OpenWindow;
  lb := MakeListBox(False, HostW, HostH, 96, False, FWin);
  lb.HandleNeeded;
  bar := FindBar(lb, sbVertical);
  AssertTrue('前置条件:竖条在、看得见', (bar <> nil) and bar.Visible);
  bar.HandleNeeded;
  ParkFocus;

  c := ThumbCenter(bar);
  bar.Perform(LM_LBUTTONDOWN, MK_LBUTTON, ClickPos(c.X, c.Y));
  Forms.Application.ProcessMessages;
  AssertNothingRaised('按下滑块');
  AssertSame('按下滑块:焦点归宿主', TWinControl(lb), FindOwnerControl(GetFocus));
  AssertTrue('按下滑块:进入拖动', bar.Dragging);
  AssertSame('按下滑块:鼠标捕获在条上(焦点挪走没有把它弄丢)', TControl(bar), GetCaptureControl);

  bar.Perform(LM_MOUSEMOVE, MK_LBUTTON, ClickPos(c.X, c.Y + 40));
  Forms.Application.ProcessMessages;
  AssertNothingRaised('拖动');
  AssertTrue('拖动:还在拖', bar.Dragging);
  AssertSame('拖动:捕获还在条上', TControl(bar), GetCaptureControl);
  AssertTrue(Format('拖动:位置跟着走(%d)', [bar.Position]), bar.Position > 0);
  AssertTrue(Format('拖动:宿主跟着滚(TopIndex=%d)', [lb.TopIndex]), lb.TopIndex > 0);
  { 按住:闲过好几个延时也不淡。夹具的 --scrollbar-auto-hide 是 1000。 }
  bar.AutoHideTick(5000);
  bar.AutoHideTick(5000);
  AssertEquals('拖动途中条被按住,不淡出', 1.0, bar.FadeLevel, 0.001);
  endPos := bar.Position;

  bar.Perform(LM_LBUTTONUP, 0, ClickPos(c.X, c.Y + 40));
  Forms.Application.ProcessMessages;
  AssertNothingRaised('松手');
  AssertFalse('松手:拖动结束', bar.Dragging);
  AssertFalse('松手:捕获释放', GetCaptureControl = TControl(bar));
  AssertEquals('松手:位置停在松手处', endPos, bar.Position);
  AssertSame('松手:焦点还在宿主上', TWinControl(lb), FindOwnerControl(GetFocus));
  AssertFalse('松手:条从头到尾没拿过焦点', bar.Focused);

  { 指针离开条(拖动途中的 LM_MOUSEMOVE 让 LCL 把条记成了「指针在上面」,那本身也是按住)。
    剩下能按住它的只有焦点 —— 而条没有焦点,所以照常淡出。 }
  bar.Perform(CM_MOUSELEAVE, 0, 0);
  bar.AutoHideTick(2000);
  bar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals('松手、指针离开之后不再按住,照常淡出', 0.0, bar.FadeLevel, 0.001);
end;

initialization
  RegisterTest(TScrollBarHostFrameTests);
end.
