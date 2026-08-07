{ 真机验收探针 —— TTyScrollBox / TTyScrollPanel。

  照 gridverify 的路子:真实窗体 + 真实句柄 + 真实绘制路径,断言 + 存 PNG。
  无头单元测试(tests/test.scrollbox.pas)里**每一个**用例都手动调了
  UpdateScrollRange,所以"控件自己什么时候该重算"这条线一次都没被测过 ——
  用户报的正是这一层。

  用法:scrollverify.exe [输出目录]    退出码 0 = 全部通过。 }
program scrollverify;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  {$IFDEF LCLWin32}Windows,{$ENDIF}
  Interfaces, Forms, Graphics, Controls, Classes, SysUtils, Types,
  StrUtils, LCLType, LMessages,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.Panel, tyControls.Button, tyControls.ScrollBar, tyControls.ScrollBox,
  uscroll;

var
  OutDir: string;
  Failures: Integer = 0;
  Checks: Integer = 0;
  LogF: TextFile;
  LogOpen: Boolean = False;

procedure Say(const AMsg: string);
begin
  WriteLn(AMsg);
  Flush(Output);
  if LogOpen then
  begin
    WriteLn(LogF, AMsg);
    Flush(LogF);
  end;
end;

procedure Check(const AWhat: string; ACond: Boolean; const ADetail: string = '');
begin
  Inc(Checks);
  if ACond then
    Say('  PASS  ' + AWhat)
  else
  begin
    Inc(Failures);
    Say('  FAIL  ' + AWhat + IfThen(ADetail <> '', '  <- ' + ADetail, ''));
  end;
end;

procedure Shot(AControl: TWinControl; const AName: string);
var
  bmp: TBitmap;
  png: TPortableNetworkGraphic;
begin
  Application.ProcessMessages;
  bmp := TBitmap.Create;
  png := TPortableNetworkGraphic.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(AControl.Width, AControl.Height);
    bmp.Canvas.Brush.Color := clFuchsia;      { 没画到的地方一眼看得出 }
    bmp.Canvas.FillRect(0, 0, bmp.Width, bmp.Height);
    AControl.PaintTo(bmp.Canvas, 0, 0);
    png.Assign(bmp);
    png.SaveToFile(IncludeTrailingPathDelimiter(OutDir) + AName + '.png');
    Say('  shot  ' + AName + '.png');
  finally
    png.Free;
    bmp.Free;
  end;
end;

{ 两条内嵌条不是 published 的,从子控件表里认出来 —— 这也正是用户/主题作者
  能看到的那一面。 }
type
  { protected 的布局钩子够不着,开个访问缝 —— 量的就是 LCL 摆放子控件时真正用的那个矩形
    (AlignControl: ARect := GetLogicalClientRect; AlignControls -> AdjustClientRect(ARect))。 }
  TBoxAccess = class(TTyScrollBox)
  public
    function ChildArea: TRect;
    { 主题边框宽度(设备 px)。cef6109 之后视口要让出这一圈:两条停在框**里面**、
      布局区两边各内缩它、滚动到底时内容末端对齐的也是内缩后的视口下缘。
      这个探针原来把它当成 0,于是修好之后反而红了 8 条 —— 陈旧的期望值,不是回归。 }
    function Frame: Integer;
  end;

function TBoxAccess.ChildArea: TRect;
begin
  Result := GetLogicalClientRect;
  AdjustClientRect(Result);
end;

function TBoxAccess.Frame: Integer;
begin
  Result := FrameInset;
end;

{ 相邻 alTop 兄弟必须首尾相接:返回最坏的一处间隙(0 = 都接上了,负 = 有重叠)。
  只溢出一行时 LCL 的钳制恰好落在正确位置,所以这个检查要有足够多的溢出行才有意义。 }
function WorstGap(ABox: TTyScrollBox; out ADetail: string): Integer;
var
  i, prevBottom, gap: Integer;
  c: TControl;
begin
  Result := 0;
  ADetail := '';
  prevBottom := MaxInt;
  for i := 0 to ABox.ControlCount - 1 do
  begin
    c := ABox.Controls[i];
    if (c is TTyScrollBar) or (c.Align <> alTop) then Continue;
    if prevBottom <> MaxInt then
    begin
      gap := c.Top - prevBottom;
      if Abs(gap) > Abs(Result) then
      begin
        Result := gap;
        ADetail := Format('%s 与上一行间隙 %d(应为 0)', [c.Name, gap]);
      end;
    end;
    prevBottom := c.Top + c.Height;
  end;
end;

function BarOf(ABox: TTyScrollBox; AKind: TTyScrollBarKind): TTyScrollBar;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to ABox.ControlCount - 1 do
    if (ABox.Controls[i] is TTyScrollBar)
       and (TTyScrollBar(ABox.Controls[i]).Kind = AKind) then
      Exit(TTyScrollBar(ABox.Controls[i]));
end;

function BarCount(ABox: TTyScrollBox): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to ABox.ControlCount - 1 do
    if ABox.Controls[i] is TTyScrollBar then Inc(Result);
end;

function Thick: Integer;
begin
  Result := TyDefaultController.Metric('--scrollbar-size', TyScrollbarSize);
  if Result < 1 then Result := 1;
end;

function R2S(const R: TRect): string;
begin
  Result := Format('(%d,%d %dx%d)', [R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top]);
end;

function VisS(ABar: TTyScrollBar): string;
begin
  if ABar = nil then Exit('<nil>');
  Result := Format('visible=%s %s max=%d page=%d pos=%d',
    [BoolToStr(ABar.Visible, True), R2S(ABar.BoundsRect), ABar.Max, ABar.PageSize, ABar.Position]);
end;

{ ---------------------------------------------------------------- 场景 --- }

var
  SForm: TScrollForm;

{ [1] 设计器摆好、运行 —— 内容明明溢出,条该不该出来?
      这是用户最普通的路径:.lfm 流式化的子控件在 Width/Height 触发的那次
      Resize **之后**才进来,之后再没有任何东西触发重算。 }
procedure Case_StreamedChildrenShowBars;
var
  V, H: TTyScrollBar;
  bw: Integer;
begin
  Say('[1] .lfm 流进来的子控件 —— 溢出了就该有条(不用手动调 UpdateScrollRange)');
  Say(Format('     Box %dx%d,内容包围盒应为 432x322,--scrollbar-size=%d',
    [SForm.Box.Width, SForm.Box.Height, Thick]));

  Check('只建了一对条,没有重复', BarCount(SForm.Box) = 2,
    Format('实际 %d 条', [BarCount(SForm.Box)]));

  Check('ContentWidth = 432(12+420)', SForm.Box.ContentWidth = 432,
    Format('实际 %d', [SForm.Box.ContentWidth]));
  Check('ContentHeight = 322(290+32)', SForm.Box.ContentHeight = 322,
    Format('实际 %d', [SForm.Box.ContentHeight]));

  V := BarOf(SForm.Box, sbVertical);
  H := BarOf(SForm.Box, sbHorizontal);
  Say('     vbar: ' + VisS(V));
  Say('     hbar: ' + VisS(H));

  Check('垂直条可见(内容 322 > 视口 200)', (V <> nil) and V.Visible, VisS(V));
  Check('水平条可见(内容 432 > 视口 300)', (H <> nil) and H.Visible, VisS(H));

  bw := TBoxAccess(SForm.Box).Frame;
  if (V <> nil) and V.Visible then
    Check('垂直条贴右缘、停在框里面、让开水平条',
      (V.Left = SForm.Box.Width - Thick - bw) and (V.Top = bw)
      and (V.Width = Thick) and (V.Height = SForm.Box.Height - Thick - 2 * bw),
      R2S(V.BoundsRect));
  if (H <> nil) and H.Visible then
    Check('水平条贴下缘、停在框里面、让开垂直条',
      (H.Left = bw) and (H.Top = SForm.Box.Height - Thick - bw)
      and (H.Height = Thick) and (H.Width = SForm.Box.Width - Thick - 2 * bw),
      R2S(H.BoundsRect));

  Shot(SForm.Box, '1-streamed-box');
end;

{ [2] alClient 的滚动框 —— 宿主一定给它 Resize,所以条会出来;
      这一条是对照组,用来把"没触发重算"和"算错了"分开。 }
procedure Case_AlClientBox;
var
  V, H: TTyScrollBar;
begin
  Say('[2] alClient 的滚动框(宿主必然触发 Resize)');
  V := BarOf(SForm.ClientBox, sbVertical);
  H := BarOf(SForm.ClientBox, sbHorizontal);
  Say(Format('     ClientBox %dx%d  content=%dx%d',
    [SForm.ClientBox.Width, SForm.ClientBox.Height,
     SForm.ClientBox.ContentWidth, SForm.ClientBox.ContentHeight]));
  Say('     vbar: ' + VisS(V));
  Say('     hbar: ' + VisS(H));
  Check('alClient 框也认出了溢出', (V <> nil) and V.Visible and (H <> nil) and H.Visible,
    VisS(V) + ' / ' + VisS(H));
  Shot(SForm.ClientBox, '2-alclient-box');
end;

{ [3] 运行期用代码加子控件 —— 文档说要手动调 UpdateScrollRange,
      但 LCL 的容器(TScrollBox / TPanel)没有一个要求宿主这么做。 }
var
  CodeBox: TTyScrollBox;
  CodeChild: TTyPanel;

procedure Case_RuntimeChildAdded;
var
  V: TTyScrollBar;
begin
  Say('[3] 运行期 Create 一个超高子控件 —— 条该自己出来');
  CodeBox := TTyScrollBox.Create(SForm);
  CodeBox.Parent := SForm;
  CodeBox.SetBounds(20, 240, 300, 200);

  CodeChild := TTyPanel.Create(CodeBox);
  CodeChild.Parent := CodeBox;
  CodeChild.SetBounds(0, 0, 100, 600);
  Application.ProcessMessages;

  V := BarOf(CodeBox, sbVertical);
  Say('     vbar: ' + VisS(V));
  Check('加完子控件后垂直条自己出来了', (V <> nil) and V.Visible, VisS(V));
  Check('ContentHeight 跟上了', CodeBox.ContentHeight = 600,
    Format('实际 %d', [CodeBox.ContentHeight]));
end;

{ [4] 子控件自己变高/变矮 —— 范围要跟着走。 }
procedure Case_ChildResized;
var
  V: TTyScrollBar;
begin
  Say('[4] 子控件改尺寸 —— 范围跟着走');
  CodeChild.Height := 60;                 { 现在放得下了 }
  Application.ProcessMessages;
  V := BarOf(CodeBox, sbVertical);
  Check('内容放得下之后条自己收起来', (V = nil) or (not V.Visible), VisS(V));

  CodeChild.Height := 900;                { 又溢出了 }
  Application.ProcessMessages;
  V := BarOf(CodeBox, sbVertical);
  Check('内容又溢出之后条自己回来', (V <> nil) and V.Visible, VisS(V));
  Check('ContentHeight = 900', CodeBox.ContentHeight = 900,
    Format('实际 %d', [CodeBox.ContentHeight]));
end;

{ [14] 删掉子控件 —— 范围也要跟着回落,同样不该要求宿主手动调。 }
procedure Case_ChildRemoved;
var
  extra: TTyPanel;
  V: TTyScrollBar;
begin
  Say('[14] 删掉撑高的子控件 —— 条自己收起来');
  CodeChild.Height := 60;                 { 本身放得下 }
  extra := TTyPanel.Create(CodeBox);
  extra.Parent := CodeBox;
  extra.SetBounds(0, 0, 100, 900);        { 由它撑出溢出 }
  Application.ProcessMessages;
  V := BarOf(CodeBox, sbVertical);
  Check('加进来之后条出来了', (V <> nil) and V.Visible, VisS(V));

  extra.Free;                             { 不调 UpdateScrollRange }
  Application.ProcessMessages;
  V := BarOf(CodeBox, sbVertical);
  Say(Format('     删除后 ContentHeight=%d', [CodeBox.ContentHeight]));
  Check('删掉之后条自己收起来', (V = nil) or (not V.Visible), VisS(V));
  Check('ContentHeight 回落到剩下的内容', CodeBox.ContentHeight = 60,
    Format('实际 %d', [CodeBox.ContentHeight]));
end;

{ [5] 拖到底 —— 最后一个子控件的下缘要正好落在视口下缘(不能少一截也不能多)。 }
procedure Case_ScrollToEnd;
var
  V: TTyScrollBar;
  viewH, bottom: Integer;
begin
  Say('[5] 拖到最底 —— 内容末端正好对齐视口下缘');
  CodeChild.Height := 600;
  CodeBox.UpdateScrollRange;
  Application.ProcessMessages;
  V := BarOf(CodeBox, sbVertical);
  if V = nil then
  begin
    Check('有垂直条', False, '没有条,后面跳过');
    Exit;
  end;
  V.Position := V.Max;
  Application.ProcessMessages;
  { 视口 = 全高减去上下两道主题边框(只有垂直条,横轴不占高)。 }
  viewH := CodeBox.Height - 2 * TBoxAccess(CodeBox).Frame;
  bottom := CodeChild.Top + CodeChild.Height;   { 客户坐标下的内容末端 }
  Say(Format('     ScrollY=%d  max=%d  child.Top=%d  末端=%d  视口高=%d',
    [CodeBox.ScrollY, V.Max, CodeChild.Top, bottom, viewH]));
  Check('拖到底之后内容末端 = 视口下缘', bottom = viewH,
    Format('末端 %d vs 视口 %d', [bottom, viewH]));
  Check('偏移 = 条的 Max', CodeBox.ScrollY = V.Max,
    Format('%d vs %d', [CodeBox.ScrollY, V.Max]));
  Shot(CodeBox, '5-scrolled-to-end');
end;

{ [6] 滚到底之后把框放大 —— 内容要退回原位,条要收起来,不能留下"内容飘在上面"。 }
procedure Case_GrowWhileScrolled;
var
  V: TTyScrollBar;
begin
  Say('[6] 滚到底之后放大框 —— 内容归位');
  CodeBox.SetBounds(20, 240, 300, 700);
  Application.ProcessMessages;
  V := BarOf(CodeBox, sbVertical);
  Say(Format('     ScrollY=%d  child.Top=%d', [CodeBox.ScrollY, CodeChild.Top]));
  Check('偏移归零', CodeBox.ScrollY = 0, Format('实际 %d', [CodeBox.ScrollY]));
  Check('子控件回到逻辑原位 Top=0', CodeChild.Top = 0,
    Format('实际 %d', [CodeChild.Top]));
  Check('条收起来了', (V = nil) or (not V.Visible), VisS(V));
  CodeBox.SetBounds(20, 240, 300, 200);
  Application.ProcessMessages;
end;

{ [7] 滚动中途改框宽度 —— 条不能留在旧位置。 }
procedure Case_BarsFollowResize;
var
  V, H: TTyScrollBar;
  bw: Integer;
begin
  Say('[7] 滚动中途改尺寸 —— 两条要跟着新边缘走');
  CodeChild.SetBounds(0, 0, 800, 600);
  CodeBox.UpdateScrollRange;
  Application.ProcessMessages;
  V := BarOf(CodeBox, sbVertical);
  H := BarOf(CodeBox, sbHorizontal);
  if (V <> nil) and V.Visible then V.Position := V.Max div 2;
  Application.ProcessMessages;

  CodeBox.SetBounds(20, 240, 420, 260);
  Application.ProcessMessages;
  Say('     vbar: ' + VisS(V));
  Say('     hbar: ' + VisS(H));
  bw := TBoxAccess(CodeBox).Frame;
  if (V <> nil) and V.Visible then
    Check('垂直条跟到了新的右缘',
      (V.Left = CodeBox.Width - Thick - bw) and (V.Top = bw)
      and (V.Height = CodeBox.Height - Thick - 2 * bw), R2S(V.BoundsRect));
  if (H <> nil) and H.Visible then
    Check('水平条跟到了新的下缘',
      (H.Top = CodeBox.Height - Thick - bw) and (H.Left = bw)
      and (H.Width = CodeBox.Width - Thick - 2 * bw), R2S(H.BoundsRect));
  Shot(CodeBox, '7-after-resize');
end;

{ [8] 滚轮:落在滚动框自己身上时必须能滚(信息项:落在子控件上由 LCL 的
      冒泡决定,这里只记录事实,不判定)。 }
procedure Case_Wheel;
var
  before, afterChild, afterBox: Integer;
  msg: TLMMouseEvent;

  procedure Wheel(ATarget: TControl);
  begin
    FillChar(msg{%H-}, SizeOf(msg), 0);
    msg.Msg := LM_MOUSEWHEEL;
    msg.WheelDelta := -120;      { 向下滚 }
    ATarget.Dispatch(msg);
    Application.ProcessMessages;
  end;

begin
  Say('[8] 滚轮');
  CodeBox.SetBounds(20, 240, 300, 200);
  CodeChild.SetBounds(0, 0, 100, 600);
  CodeBox.UpdateScrollRange;
  Application.ProcessMessages;
  before := CodeBox.ScrollY;

  Wheel(CodeChild);              { 指针停在子控件上 —— LCL 投给鼠标下的控件 }
  afterChild := CodeBox.ScrollY;
  Say(Format('     滚轮投给子控件:ScrollY %d -> %d(信息项)', [before, afterChild]));

  Wheel(CodeBox);                { 指针停在滚动框空白处 }
  afterBox := CodeBox.ScrollY;
  Say(Format('     滚轮投给滚动框:ScrollY %d -> %d', [afterChild, afterBox]));
  Check('滚轮在滚动框自己身上能滚', afterBox > afterChild,
    Format('%d -> %d', [afterChild, afterBox]));
end;

{ [10] 容器契约:客户区必须扣掉两条的槽。LCL 的容器(TScrollBox/TPanel/TGroupBox)
       都用 AdjustClientRect 把"子控件可用的区域"讲清楚;不讲的话,alClient /
       alRight / alBottom 的子控件会直接盖住滚动条,用户看到的就是"条时有时无"。 }
procedure Case_ClientRectExcludesBars;
var
  V, H: TTyScrollBar;
  area: TRect;
  bw: Integer;
begin
  Say('[10] 容器契约 —— 子控件布局区的大小与原点');
  { 注意:量的是 AdjustClientRect(LCL 摆放子控件用的那个矩形),不是 ClientRect。
    ClientRect 保持整框大小 —— 主题框(TTyPanel.Paint)要照着它画满,而且
    TTyMemo / TTyListBox 这些内嵌滚动条的控件在本库里都是这个约定。 }
  CodeBox.SetBounds(20, 240, 300, 200);
  { 上一个场景把偏移留在了非零处。测量把子控件的 Left/Top 当成"已滚动"坐标
    (逻辑位置 = 当前位置 + 偏移),所以要先显式滚回原点再摆场景。 }
  V := BarOf(CodeBox, sbVertical);
  if (V <> nil) and V.Visible then V.Position := 0;
  H := BarOf(CodeBox, sbHorizontal);
  if (H <> nil) and H.Visible then H.Position := 0;
  Application.ProcessMessages;
  CodeChild.SetBounds(0, 0, 800, 600);          { 两轴都溢出 }
  Application.ProcessMessages;
  V := BarOf(CodeBox, sbVertical);
  H := BarOf(CodeBox, sbHorizontal);

  area := TBoxAccess(CodeBox).ChildArea;
  Say(Format('     ClientRect=%s  子控件布局区=%s  两条可见=%s/%s',
    [R2S(CodeBox.ClientRect), R2S(area),
     BoolToStr((V <> nil) and V.Visible, True),
     BoolToStr((H <> nil) and H.Visible, True)]));
  { 内容 800x600 比视口大 -> 布局区扩到内容(对齐的行才有地方堆),原点未滚动时为 0。 }
  Check('布局区扩展到了内容宽', area.Right - area.Left = 800,
    Format('%d,期望 800', [area.Right - area.Left]));
  Check('布局区扩展到了内容高', area.Bottom - area.Top = 600,
    Format('%d,期望 600', [area.Bottom - area.Top]));

  V := BarOf(CodeBox, sbVertical);
  if (V <> nil) and V.Visible then V.Position := 60;
  area := TBoxAccess(CodeBox).ChildArea;
  Say(Format('     滚动 %d 后布局区=%s', [CodeBox.ScrollY, R2S(area)]));
  { 未滚动时原点是框**里面**(边框宽),所以滚动之后是 bw - ScrollY。 }
  bw := TBoxAccess(CodeBox).Frame;
  Check('布局原点跟着滚动偏移走', area.Top = bw - CodeBox.ScrollY,
    Format('%d,期望 %d', [area.Top, bw - CodeBox.ScrollY]));

  CodeChild.SetBounds(0, 0, 100, 80);      { 两轴都放得下 -> 两条都收起 }
  Application.ProcessMessages;
  area := TBoxAccess(CodeBox).ChildArea;
  Say(Format('     内容缩回后布局区=%s', [R2S(area)]));
  Check('没有条时布局区就是整框减去主题边框',
    (area.Right - area.Left = CodeBox.Width - 2 * bw)
    and (area.Bottom - area.Top = CodeBox.Height - 2 * bw), R2S(area));
end;

{ [11] 对齐的子控件 —— 容器最基本的用法:往滚动框里丢一排 alTop。
       LCL 会把它们对齐到"客户区";客户区没扣掉条的话,它们会盖住条。
       并且 alTop 的子控件在每次 realign 时都会被拉回去 —— 滚不动。 }
procedure Case_AlignedChildren;
var
  V: TTyScrollBar;
  covered: Boolean;
  topBefore, gap: Integer;
  detail: string;
begin
  Say('[11] alTop 子控件(8 x 40 = 320 > 视口 200,溢出 3 行)');
  Application.ProcessMessages;
  V := BarOf(SForm.AlignBox, sbVertical);
  Say(Format('     AlignBox %dx%d  content=%dx%d',
    [SForm.AlignBox.Width, SForm.AlignBox.Height,
     SForm.AlignBox.ContentWidth, SForm.AlignBox.ContentHeight]));
  Say('     vbar: ' + VisS(V));
  Say(Format('     AlTop1 %s  AlTop8 %s',
    [R2S(SForm.AlTop1.BoundsRect), R2S(SForm.AlTop6.BoundsRect)]));

  Check('alTop 内容溢出时垂直条出现', (V <> nil) and V.Visible, VisS(V));

  { 只溢出一行时 LCL 的钳制恰好落在正确位置,查不出问题;这里溢出 3 行,
    没有足够的布局空间就会看到后几行叠在一起。 }
  gap := WorstGap(SForm.AlignBox, detail);
  Check('每一行首尾相接,没有重叠', gap = 0, detail);
  { 首行从框**里面**起排(布局原点内缩了一个边框宽),所以包围盒是 bw + 8x40。 }
  Check('内容高 = 边框 + 8 行 x 40',
    SForm.AlignBox.ContentHeight = TBoxAccess(SForm.AlignBox).Frame + 320,
    Format('实际 %d,期望 %d',
      [SForm.AlignBox.ContentHeight, TBoxAccess(SForm.AlignBox).Frame + 320]));

  if (V <> nil) and V.Visible then
  begin
    covered := SForm.AlTop1.Left + SForm.AlTop1.Width > V.Left;
    Check('对齐子控件没有盖住垂直条', not covered,
      Format('AlTop1 右缘 %d,条左缘 %d',
        [SForm.AlTop1.Left + SForm.AlTop1.Width, V.Left]));

    topBefore := SForm.AlTop1.Top;
    V.Position := V.Max;
    Application.ProcessMessages;
    Say(Format('     拖到底后 ScrollY=%d  AlTop1.Top %d -> %d  AlTop8=%s',
      [SForm.AlignBox.ScrollY, topBefore, SForm.AlTop1.Top,
       R2S(SForm.AlTop8.BoundsRect)]));
    Check('对齐子控件真的被滚动了', SForm.AlTop1.Top < topBefore,
      Format('%d -> %d', [topBefore, SForm.AlTop1.Top]));
    Check('滚到底时最后一个 alTop 子控件进入了视口',
      SForm.AlTop8.Top + SForm.AlTop8.Height <= SForm.AlignBox.Height,
      Format('末端 %d,框高 %d',
        [SForm.AlTop8.Top + SForm.AlTop8.Height, SForm.AlignBox.Height]));
    gap := WorstGap(SForm.AlignBox, detail);
    Check('滚动之后每行依然首尾相接', gap = 0, detail);
  end;
  Shot(SForm.AlignBox, '11-aligned-children');
end;

{ [12] 真实 Z 序:两条是不是压在内容之上?PaintTo 走的是 WM_PRINT,
       未必等于屏幕上的层次 —— 直接问 Win32 要兄弟窗口的顺序。 }
procedure Case_ZOrder;
{$IFDEF LCLWin32}
var
  h: HWND;
  depth, vDepth, hDepth, worstContent, i: Integer;
  c: TControl;
{$ENDIF}
begin
  Say('[12] 两条与内容的真实 Z 序');
  {$IFDEF LCLWin32}
  { 从最顶层往下走一遍兄弟链,记下每个句柄的"深度";深度小 = 更靠上。 }
  vDepth := -1; hDepth := -1; worstContent := -1;
  h := GetWindow(CodeBox.Handle, GW_CHILD);      { 最顶层的子窗口 }
  depth := 0;
  while h <> 0 do
  begin
    for i := 0 to CodeBox.ControlCount - 1 do
    begin
      c := CodeBox.Controls[i];
      if (c is TWinControl) and TWinControl(c).HandleAllocated
         and (TWinControl(c).Handle = h) then
      begin
        if c is TTyScrollBar then
        begin
          if TTyScrollBar(c).Kind = sbVertical then vDepth := depth
          else hDepth := depth;
        end
        else if depth > worstContent then
          worstContent := depth;
      end;
    end;
    h := GetWindow(h, GW_HWNDNEXT);
    Inc(depth);
  end;
  Say(Format('     vbar 深度=%d  hbar 深度=%d  最靠下的内容深度=%d(小 = 更靠上)',
    [vDepth, hDepth, worstContent]));
  Check('垂直条在所有内容之上', (vDepth >= 0) and (vDepth < worstContent),
    Format('vbar=%d content=%d', [vDepth, worstContent]));
  Check('水平条在所有内容之上', (hDepth >= 0) and (hDepth < worstContent),
    Format('hbar=%d content=%d', [hDepth, worstContent]));
  {$ELSE}
  Say('     非 Win32,跳过');
  {$ENDIF}
end;

{ [13] 锚定到右/下的子控件 —— ScrollBy 会 SetBounds 它们,
       LCL 的锚定基线会不会被搅乱? }
procedure Case_AnchoredChild;
var
  anch: TTyPanel;
  V: TTyScrollBar;
  wBefore, wAfter: Integer;
begin
  { 连滚多次 —— 这个坏法是**累积**的:ClientRect 与布局区差一个条厚时,每滚一次
    锚定基线就把差额记进去一次,子控件被一格格吃掉(实测 88→76→64→52→40)。
    只滚一次也看得见,但连滚才说明它不会停。 }
  Say('[13] akRight 锚定的子控件连滚多次后宽度不变');
  CodeBox.SetBounds(20, 240, 300, 200);
  V := BarOf(CodeBox, sbVertical);              { 先滚回原点 }
  if (V <> nil) and V.Visible then V.Position := 0;
  Application.ProcessMessages;
  CodeChild.SetBounds(0, 0, 100, 600);
  anch := TTyPanel.Create(CodeBox);
  anch.Parent := CodeBox;
  anch.SetBounds(120, 0, 100, 40);
  anch.Anchors := [akTop, akLeft, akRight];
  CodeBox.UpdateScrollRange;
  Application.ProcessMessages;
  wBefore := anch.Width;
  Say('     滚动前:布局区=' + R2S(TBoxAccess(CodeBox).ChildArea)
    + '  anch=' + R2S(anch.BoundsRect)
    + '  vbar=' + VisS(BarOf(CodeBox, sbVertical))
    + '  hbar=' + VisS(BarOf(CodeBox, sbHorizontal)));

  V := BarOf(CodeBox, sbVertical);
  if V <> nil then
  begin
    V.Position := 100;  Application.ProcessMessages;
    Say(Format('     滚1次后 anch.W=%d  布局区=%s', [anch.Width, R2S(TBoxAccess(CodeBox).ChildArea)]));
    V.Position := 150;  Application.ProcessMessages;
    Say(Format('     滚2次后 anch.W=%d', [anch.Width]));
    V.Position := 200;  Application.ProcessMessages;
    Say(Format('     滚3次后 anch.W=%d', [anch.Width]));
    V.Position := 250;  Application.ProcessMessages;
    Say(Format('     滚4次后 anch.W=%d', [anch.Width]));
  end;
  wAfter := anch.Width;
  Say(Format('     滚动前后宽度 %d -> %d,右缘 %d(视口右缘应为 %d)',
    [wBefore, wAfter, anch.Left + anch.Width, CodeBox.Width - Thick]));
  Check('滚动没有改变 akRight 子控件的宽度', wBefore = wAfter,
    Format('%d -> %d', [wBefore, wAfter]));
  anch.Free;
  CodeBox.UpdateScrollRange;
end;

{ [9] 主题框:滚动框自己画了边框,条压在边框上还是让开? }
procedure Case_FrameVsBars;
var
  S: TTyStyleSet;
begin
  Say('[9] 主题边框与条的关系(信息项,不判定)');
  S := TyDefaultController.Model.ResolveStyle('TyScrollBox', '', []);
  Say(Format('     TyScrollBox border-width=%d radius=%d padding=%d,%d,%d,%d',
    [S.BorderWidth, S.BorderRadius, S.Padding.Left, S.Padding.Top,
     S.Padding.Right, S.Padding.Bottom]));
end;

begin
  OutDir := ExtractFilePath(ParamStr(0));
  if ParamCount >= 1 then OutDir := ParamStr(1);
  ForceDirectories(OutDir);

  Application.Initialize;
  Application.CreateForm(TScrollForm, SForm);
  SForm.Left := -3000;              { 挪到屏幕外,别打扰正在用电脑的人 }
  SForm.Top := 100;
  SForm.Show;
  Application.ProcessMessages;

  AssignFile(LogF, IncludeTrailingPathDelimiter(OutDir) + 'verify.log');
  Rewrite(LogF);
  LogOpen := True;
  Say('=== scrollverify ===');
  Say('输出目录: ' + OutDir);
  Say('');
  try
    Case_StreamedChildrenShowBars; Say('');
    Case_AlClientBox;              Say('');
    Case_RuntimeChildAdded;        Say('');
    Case_ChildResized;             Say('');
    Case_ChildRemoved;             Say('');
    Case_ScrollToEnd;              Say('');
    Case_GrowWhileScrolled;        Say('');
    Case_BarsFollowResize;         Say('');
    Case_Wheel;                    Say('');
    Case_ClientRectExcludesBars;   Say('');
    Case_AlignedChildren;          Say('');
    Case_ZOrder;                   Say('');
    Case_AnchoredChild;            Say('');
    Case_FrameVsBars;              Say('');
  except
    on E: Exception do
    begin
      Inc(Failures);
      Say('  EXCEPTION  ' + E.ClassName + ': ' + E.Message);
    end;
  end;

  Say(Format('=== %d 项检查,%d 项失败 ===', [Checks, Failures]));
  if LogOpen then CloseFile(LogF);
  SForm.Hide;
  if Failures > 0 then Halt(1);
end.
