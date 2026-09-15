unit test.scrollbar.hostframe;
{$mode objfpc}{$H+}
{ 内嵌滚动条压在宿主自己的边框上。

  真机报的是「列表右侧 scrollbar 那一条，列表的边框没了，变成了白色」。根因不在自动
  隐藏里，在**几何**：宿主的 DrawFrame 把边框画在 Rect(0,0,W,H) 的最外一圈，而内嵌
  的竖条被摆在 alRight / SetBounds(Width-thick, 0, ...) 上，正好盖住那一圈。条是窗口
  化控件，它那块矩形上宿主再也画不进去。

  条完全可见时盖住边框的是条自己（看着像「条贴着边」，没人报）；自动隐藏把条淡没之后，
  RenderTo 那一格铺的是 TyFillParentBg —— **父控件的背景**，也就是列表的表面色，于是
  那一段边框变成一条白。TyFillParentBg 只铺背景，不会把父控件的边框重画一遍。

  所以这一组守的不是「淡出对不对」，是「条那块矩形**不许**落在宿主的边框上」。判据
  取两张图的差：先只画宿主，再把条按它自己的 BoundsRect 叠上去（窗口化子控件在屏幕上
  就是这么盖的），边框那两列/两行的像素必须**一个字节都不变**。不写死颜色——写死颜色
  的断言换个主题就得跟着改，而且证明不了「和旁边那段一样」。

  无头能跑到真正的对齐引擎：LCL 只是在没 Show 的窗体上跳过 AutoSize/Realign，直接调
  protected 的 AlignControls 就能把 Align=alRight 的条摆到真实位置（实测与真机同值）。
  Grid/ListView/TreeView 根本不用对齐引擎——它们自己 SetBounds。

  TTyMemo 那一条是**绿的**，而且必须是绿的：它早就为这件事把两条内嵌条往里缩了 2px
  （见 tyControls.Memo.pas 里 fw 的注释）。它在这里的作用是证明这套判据能过——一条永远
  过不了的断言和一条真守着什么的断言，全红的时候长得一模一样。

  没覆盖 TTyScrollBox：它的条也早就按 FrameInset 缩进了（tyControls.ScrollBox.pas 的
  LayoutBars），但要塞进内容子控件才会出条，那套夹具与这里的五个宿主完全不同。

  **修复落地之前这一组是红的**：ListBox 两条、TreeView/Grid/ListView 各一条，共 5 条；
  Memo 那条是绿的。全量 7100 条里 0 errors / 5 failures，红的全部在这里。

  修好之后:五个宿主共用 tyControls.Base 的 TyChromeInsetLogical 让开那一圈 —— ListBox/Memo
  把它交给对齐引擎(BorderSpacing),Grid/ListView/TreeView 自己 SetBounds 就直接减。两条一起
  缩,缩的是同一个数:只缩一条,角上那块会多出或少掉一截。

  判据从「右边 + 上边那两条带」扩成**整整一圈**:条只可能改它自己那块矩形里的像素,所以
  「一圈里一个像素没变」等价于「条的矩形一寸都没压到那一圈」,而且左边与底边一起替 RTL 的
  竖条和底下的横条守着,不必每个方向各写一遍。ListBox 那条双向的用例把横条也放出来,底边
  这一带才真的被一条横条压过。 }
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, StdCtrls,
  fpcunit, testregistry, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.ScrollBar,
  tyControls.ListBox, tyControls.Memo, tyControls.TreeView,
  tyControls.Grid, tyControls.ListView;

type
  { 宿主的 RenderTo 都是 protected，签名又完全一样，所以每个宿主开一个口子，
    再用同一个回调类型喂给底下那个比较器。 }
  TRenderProc = procedure(ACanvas: TCanvas; const ARect: TRect; APPI: Integer) of object;

  TFrameListBox = class(TTyListBox)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure CallUpdateScrollBar;
    procedure ForceAlign;
    function VBar: TTyScrollBar;
    function HBar: TTyScrollBar;
  end;

  TFrameMemo = class(TTyMemo)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure CallUpdateScrollBar;
    procedure ForceAlign;
    function VBar: TTyScrollBar;
  end;

  TFrameTree = class(TTyTreeView)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function VBar: TTyScrollBar;
  end;

  TFrameGrid = class(TTyStringGrid)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function VBar: TTyScrollBar;
  end;

  TFrameListView = class(TTyListView)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function VBar: TTyScrollBar;
  end;

  { 条的 RenderTo 同样是 protected。宿主建的是**普通** TTyScrollBar，所以这个口子
    是拿来硬转型用的（不碰任何派生字段，只是借它调 inherited 的 protected 方法）。 }
  TFrameBar = class(TTyScrollBar)
  public
    procedure RenderInto(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TScrollBarHostFrameTests = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    procedure CheckFrameSurvives(const AWhat: string; ARender: TRenderProc;
      const ABars: array of TTyScrollBar);
    { 宿主的 UpdateScrollBar(s) 是私有的，但每个宿主的 RenderTo 头上都会调它——
      屏幕上也正是这样:第一次 Paint 才把条建出来并摆好。所以先空画一张。 }
    procedure Prime(ARender: TRenderProc);
    procedure FadeOut(ABar: TTyScrollBar);
    function MakeListBox(AWide: Boolean = False): TFrameListBox;
    function MakeMemo: TFrameMemo;
    function MakeTree: TFrameTree;
    function MakeGrid: TFrameGrid;
    function MakeListView: TFrameListView;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ListBoxKeepsItsFrameUnderAVisibleBar;
    procedure ListBoxKeepsItsFrameUnderAHiddenBar;
    procedure ListBoxKeepsItsFrameUnderBothBars;
    procedure MemoKeepsItsFrameUnderAHiddenBar;
    procedure TreeViewKeepsItsFrameUnderAHiddenBar;
    procedure GridKeepsItsFrameUnderAHiddenBar;
    procedure ListViewKeepsItsFrameUnderAHiddenBar;
  end;

implementation

const
  HostW = 160;
  HostH = 120;
  Wipe  = TColor($00FF00);   { 哨兵底漆：渲染没盖到的地方会原样留着，数得出来 }
  { 宿主全部用这份 css：1px 的红边框、白表面、没有圆角/内距，条是不透明的灰。
    边框颜色与表面色差得越远，「这一段没了」越藏不住。 }
  FrameCss =
    ':root { --scrollbar-size: 12; --scrollbar-auto-hide: 1000; }' +
    'TyListBox, TyMemo, TyTreeView, TyGrid, TyListView {' +
    '  background: #FFFFFF; color: #000000; border-color: #FF0000;' +
    '  border-width: 1px; border-radius: 0px; padding: 0px; }' +
    'TyScrollBar { background: #808080; border-width: 0px; border-radius: 0px; }' +
    'TyScrollThumb { background: #202020; }';

procedure TFrameListBox.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin RenderTo(ACanvas, ARect, APPI); end;
procedure TFrameListBox.CallUpdateScrollBar;
begin UpdateScrollBar; end;
procedure TFrameListBox.ForceAlign;
var r: TRect;
begin
  { LCL 在没 Show 的窗体上跳过 AutoSize/Realign，但对齐引擎本身照样能跑：
    喂它宿主自己的客户区，Align=alRight 的条就落到真实位置上。 }
  r := Rect(0, 0, Width, Height);
  AdjustClientRect(r);
  AlignControls(nil, r);
end;
function TFrameListBox.VBar: TTyScrollBar;
var i: Integer;
begin
  Result := nil;
  for i := 0 to ComponentCount - 1 do
    if (Components[i] is TTyScrollBar)
       and (TTyScrollBar(Components[i]).Kind = sbVertical) then
      Exit(TTyScrollBar(Components[i]));
end;
function TFrameListBox.HBar: TTyScrollBar;
var i: Integer;
begin
  Result := nil;
  for i := 0 to ComponentCount - 1 do
    if (Components[i] is TTyScrollBar)
       and (TTyScrollBar(Components[i]).Kind = sbHorizontal) then
      Exit(TTyScrollBar(Components[i]));
end;

procedure TFrameMemo.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin RenderTo(ACanvas, ARect, APPI); end;
procedure TFrameMemo.CallUpdateScrollBar;
begin UpdateScrollBar; end;
procedure TFrameMemo.ForceAlign;
var r: TRect;
begin
  r := Rect(0, 0, Width, Height);
  AdjustClientRect(r);
  AlignControls(nil, r);
end;
function TFrameMemo.VBar: TTyScrollBar;
var i: Integer;
begin
  Result := nil;
  for i := 0 to ComponentCount - 1 do
    if (Components[i] is TTyScrollBar)
       and (TTyScrollBar(Components[i]).Kind = sbVertical) then
      Exit(TTyScrollBar(Components[i]));
end;

procedure TFrameTree.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin RenderTo(ACanvas, ARect, APPI); end;
function TFrameTree.VBar: TTyScrollBar;
var i: Integer;
begin
  Result := nil;
  for i := 0 to ComponentCount - 1 do
    if (Components[i] is TTyScrollBar)
       and (TTyScrollBar(Components[i]).Kind = sbVertical) then
      Exit(TTyScrollBar(Components[i]));
end;

procedure TFrameGrid.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin RenderTo(ACanvas, ARect, APPI); end;
function TFrameGrid.VBar: TTyScrollBar;
var i: Integer;
begin
  Result := nil;
  for i := 0 to ComponentCount - 1 do
    if (Components[i] is TTyScrollBar)
       and (TTyScrollBar(Components[i]).Kind = sbVertical) then
      Exit(TTyScrollBar(Components[i]));
end;

procedure TFrameListView.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin RenderTo(ACanvas, ARect, APPI); end;
function TFrameListView.VBar: TTyScrollBar;
var i: Integer;
begin
  Result := nil;
  for i := 0 to ComponentCount - 1 do
    if (Components[i] is TTyScrollBar)
       and (TTyScrollBar(Components[i]).Kind = sbVertical) then
      Exit(TTyScrollBar(Components[i]));
end;

procedure TFrameBar.RenderInto(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin RenderTo(ACanvas, ARect, APPI); end;

{ 画一张「屏幕上真正会长的样子」：先画宿主，再把窗口化的条按它自己的 BoundsRect
  盖上去。ADrawBars=False 就是宿主自己那张对照图。 }
function Shoot(ARender: TRenderProc; const ABars: array of TTyScrollBar;
  ADrawBars: Boolean): TBGRABitmap;
var
  bmp: TBitmap;
  i: Integer;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(HostW, HostH);
    bmp.Canvas.Brush.Color := Wipe;
    bmp.Canvas.FillRect(0, 0, HostW, HostH);
    if Assigned(ARender) then ARender(bmp.Canvas, Rect(0, 0, HostW, HostH), 96);
    if ADrawBars then
      for i := 0 to High(ABars) do
        if ABars[i] <> nil then
          TFrameBar(ABars[i]).RenderInto(bmp.Canvas, ABars[i].BoundsRect, 96);
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

procedure TScrollBarHostFrameTests.CheckFrameSurvives(const AWhat: string;
  ARender: TRenderProc; const ABars: array of TTyScrollBar);
var
  bare, over, barOnly: TBGRABitmap;
  one: array of TTyScrollBar;
  i, x, y, unpainted, wipeLeft: Integer;
  bad: string;

  { 一条边带：bare 与 over 在这一块里必须一个字节都不差。只记第一处，报出来的是坐标
    加两边的颜色，不是一句「不相等」。 }
  procedure Band(const AEdge: string; AX0, AY0, AX1, AY1: Integer);
  var px, py: Integer;
  begin
    for py := AY0 to AY1 do
      for px := AX0 to AX1 do
        if (bad = '') and not Same(bare.GetPixel(px, py), over.GetPixel(px, py)) then
          bad := Format('%s (%d,%d)：宿主画的是 %.2x%.2x%.2x，条盖完变成 %.2x%.2x%.2x',
            [AEdge, px, py,
             bare.GetPixel(px, py).red, bare.GetPixel(px, py).green, bare.GetPixel(px, py).blue,
             over.GetPixel(px, py).red, over.GetPixel(px, py).green, over.GetPixel(px, py).blue]);
  end;

begin
  AssertTrue(AWhat + '：前置条件——至少得有一条内嵌条', Length(ABars) > 0);
  for i := 0 to High(ABars) do
  begin
    AssertNotNull(AWhat + '：前置条件——宿主必须真的有这一条', ABars[i]);
    AssertTrue(AWhat + '：前置条件——这一条必须是可见的', ABars[i].Visible);
    { 没跑布局的话条还堆在 (0,0)：那时候「边框没被盖住」是白捡的。 }
    if ABars[i].Kind = sbVertical then
      AssertTrue(AWhat + '：前置条件——竖条必须已经被摆到右边（没跑布局就摆不过去）',
        ABars[i].Left > HostW div 2)
    else
      AssertTrue(AWhat + '：前置条件——横条必须已经被摆到底边（没跑布局就摆不过去）',
        ABars[i].Top > HostH div 2);
  end;

  bare := nil;
  over := nil;
  try
    bare := Shoot(ARender, ABars, False);
    over := Shoot(ARender, ABars, True);

    { 底漆一个都不该剩：剩了就说明这一趟压根没画满，下面「像素没变」谁都能过。 }
    wipeLeft := 0;
    for y := 0 to HostH - 1 do
      for x := 0 to HostW - 1 do
        if Same(over.GetPixel(x, y), ColorToBGRA(ColorToRGB(Wipe))) then Inc(wipeLeft);
    AssertEquals(AWhat + '：渲染要盖满整块，还留着底漆说明这张图不作数', 0, wipeLeft);

    { 条确实把它那块矩形**盖满**了——这一步不能拿 bare/over 的差来证明:条淡没之后
      铺的就是父控件的背景，跟宿主自己在那儿画的白一模一样，差出来是 0 个像素，可
      那块矩形照样归它管(窗口化子控件,宿主再也画不进去)。所以单独把条画到底漆上数。 }
    one := nil;
    SetLength(one, 1);
    for i := 0 to High(ABars) do
    begin
      one[0] := ABars[i];
      barOnly := Shoot(nil, one, True);
      try
        unpainted := 0;
        for y := ABars[i].Top to ABars[i].Top + ABars[i].Height - 1 do
          for x := ABars[i].Left to ABars[i].Left + ABars[i].Width - 1 do
            if Same(barOnly.GetPixel(x, y), ColorToBGRA(ColorToRGB(Wipe))) then Inc(unpainted);
        AssertEquals(AWhat + '：前置条件——条必须把它那块矩形盖满（它是窗口化控件）',
          0, unpainted);
      finally
        barOnly.Free;
      end;
    end;

    { 判据本身：整整一圈边框（1px 边 + 它的抗锯齿，共 2 列 / 2 行）在叠上条之后必须一个
      像素不变。条只可能改它自己那块矩形里的像素，所以这等价于「条的矩形一寸都没压到那
      一圈」——左边和底边一起替 RTL 的竖条、底下的横条守着，不必每个方向各写一遍。 }
    bad := '';
    Band('上边框', 0, 0, HostW - 1, 1);
    Band('下边框', 0, HostH - 2, HostW - 1, HostH - 1);
    Band('左边框', 0, 0, 1, HostH - 1);
    Band('右边框', HostW - 2, 0, HostW - 1, HostH - 1);
    AssertEquals(AWhat + '：内嵌条不许落在宿主的边框上', '', bad);
  finally
    bare.Free;
    over.Free;
  end;
end;

procedure TScrollBarHostFrameTests.Prime(ARender: TRenderProc);
var shot: TBGRABitmap; none: array of TTyScrollBar;
begin
  none := nil;   { 条还没被建出来——这一趟正是把它建出来的那一趟 }
  shot := Shoot(ARender, none, False);
  shot.Free;
end;

procedure TScrollBarHostFrameTests.FadeOut(ABar: TTyScrollBar);
begin
  ABar.NoteActivity;
  ABar.AutoHideTick(2000);                     { 闲过了延时 -> 装上膛 }
  ABar.AutoHideTick(TyScrollBarFadeOutMs);     { 这一拍推到底 }
  AssertEquals('前置条件：条确实淡到底了', 0.0, ABar.FadeLevel, 0.001);
end;

procedure TScrollBarHostFrameTests.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(FForm);
  FCtl.LoadThemeCss(FrameCss);
end;

procedure TScrollBarHostFrameTests.TearDown;
begin
  FreeAndNil(FForm);
end;

function TScrollBarHostFrameTests.MakeListBox(AWide: Boolean = False): TFrameListBox;
var i: Integer;
begin
  Result := TFrameListBox.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.ItemHeight := 20;
  Result.SetBounds(0, 0, HostW, HostH);
  for i := 1 to 60 do Result.Items.Add('row ' + IntToStr(i));
  { ScrollWidth 是横条唯一的开关（行内容宽度，逻辑 px）：比 160 宽就出横条。 }
  if AWide then Result.ScrollWidth := 400;
  Result.CallUpdateScrollBar;
  Prime(@Result.Render);
  Result.ForceAlign;
end;

function TScrollBarHostFrameTests.MakeMemo: TFrameMemo;
var i: Integer;
begin
  Result := TFrameMemo.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, HostW, HostH);
  Result.ScrollBars := ssAutoVertical;
  for i := 1 to 200 do Result.Lines.Add('line ' + IntToStr(i));
  Result.CallUpdateScrollBar;
  Prime(@Result.Render);
  Result.ForceAlign;
end;

function TScrollBarHostFrameTests.MakeTree: TFrameTree;
var i: Integer;
begin
  Result := TFrameTree.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, HostW, HostH);
  for i := 1 to 200 do Result.Items.Add(nil, 'node ' + IntToStr(i));
  Prime(@Result.Render);
end;

function TScrollBarHostFrameTests.MakeGrid: TFrameGrid;
begin
  Result := TFrameGrid.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, HostW, HostH);
  Result.RowCount := 200;
  Prime(@Result.Render);
end;

function TScrollBarHostFrameTests.MakeListView: TFrameListView;
var i: Integer;
begin
  Result := TFrameListView.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, HostW, HostH);
  Result.Columns.Add;
  for i := 1 to 200 do Result.Items.Add.Caption := 'item ' + IntToStr(i);
  Prime(@Result.Render);
end;

procedure TScrollBarHostFrameTests.ListBoxKeepsItsFrameUnderAVisibleBar;
var lb: TFrameListBox;
begin
  { 自动隐藏之前就已经是这样了：完全可见的条照样把那一段边框换成条身的颜色。
    自动隐藏只是把盖上去的颜色从「灰条」换成了「白表面」，于是藏不住了。 }
  lb := MakeListBox;
  lb.VBar.NoteActivity;
  AssertEquals('前置条件：条是完全可见的', 1.0, lb.VBar.FadeLevel, 0.001);
  CheckFrameSurvives('TTyListBox / 条完全可见', @lb.Render, [lb.VBar]);
end;

procedure TScrollBarHostFrameTests.ListBoxKeepsItsFrameUnderAHiddenBar;
var lb: TFrameListBox;
begin
  lb := MakeListBox;
  FadeOut(lb.VBar);
  CheckFrameSurvives('TTyListBox / 条已淡没', @lb.Render, [lb.VBar]);
end;

procedure TScrollBarHostFrameTests.ListBoxKeepsItsFrameUnderBothBars;
var lb: TFrameListBox;
begin
  { 两条一起出来。**底边**那一带只有在这里才真的被一条横条压过——上面那几条用例根本没有
    横条（内容不溢出），下边框那两行谁都不碰，断言等于白给。
    它同时守住角上的算术：只把竖条缩进去而不缩横条（或反过来），角上那块就会多出或少掉
    chrome 个像素，而差出来的那一块正落在底边 / 右边这两条带上。 }
  lb := MakeListBox(True);
  AssertNotNull('前置条件：宽内容必须逼出一条横条', lb.HBar);
  FadeOut(lb.VBar);
  FadeOut(lb.HBar);
  CheckFrameSurvives('TTyListBox / 两条都淡没', @lb.Render, [lb.VBar, lb.HBar]);
end;

procedure TScrollBarHostFrameTests.MemoKeepsItsFrameUnderAHiddenBar;
var mm: TFrameMemo;
begin
  { 这一条应当是绿的：TTyMemo 早就把内嵌条往里缩了 2px。它证明上面那套判据能过。 }
  mm := MakeMemo;
  FadeOut(mm.VBar);
  CheckFrameSurvives('TTyMemo / 条已淡没', @mm.Render, [mm.VBar]);
end;

procedure TScrollBarHostFrameTests.TreeViewKeepsItsFrameUnderAHiddenBar;
var tv: TFrameTree;
begin
  tv := MakeTree;
  FadeOut(tv.VBar);
  CheckFrameSurvives('TTyTreeView / 条已淡没', @tv.Render, [tv.VBar]);
end;

procedure TScrollBarHostFrameTests.GridKeepsItsFrameUnderAHiddenBar;
var gr: TFrameGrid;
begin
  gr := MakeGrid;
  FadeOut(gr.VBar);
  CheckFrameSurvives('TTyStringGrid / 条已淡没', @gr.Render, [gr.VBar]);
end;

procedure TScrollBarHostFrameTests.ListViewKeepsItsFrameUnderAHiddenBar;
var lv: TFrameListView;
begin
  lv := MakeListView;
  FadeOut(lv.VBar);
  CheckFrameSurvives('TTyListView / 条已淡没', @lv.Render, [lv.VBar]);
end;

initialization
  RegisterTest(TScrollBarHostFrameTests);
end.
