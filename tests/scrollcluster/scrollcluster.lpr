{ scrollcluster —— 论坛 #12/#15 那一串 TTyScrollBox 报告的真机探针。

  Antek 报了四条,全是"看得见/摸得着"的那一类,单元测试**结构上**够不到:

    A1 滚动条被子面板盖住      —— 需要真窗口的兄弟 Z 序 + 真屏幕像素
    A2 滚轮第一格方向反        —— 需要真 WM_MOUSEWHEEL 走一遍真 WndProc
    A3 拖滑块时闪烁/重绘风暴   —— 需要**数**每次拖动引发多少次真 WM_PAINT
    A4 拖动时内容跳动          —— 需要一串单调的拖动步,看偏移是不是也单调

  所以这里的每一条都必须是"数出来的",不是"看着像"。三件工具:

    * HWND 子类化(SetWindowLongPtrW)真的去数 WM_PAINT —— 控件自己的 Paint
      覆写数不到 LCL 合并/丢弃了多少次,而闪烁正是"真的刷了几次屏"。
    * BitBlt 从**屏幕**取像素,不是 PaintTo。PaintTo 走 WM_PRINT,它按控件树
      自顶向下画,兄弟遮挡在它眼里根本不存在 —— 用它验 A1 会得到假绿。
    * mouse_event 发真滚轮/真拖动。LCL 的滚轮路由(win32callback.inc 的
      DoMsgMouseWheel)会把消息重定向到 WindowFromPoint 的那个窗口,再由
      DefWindowProc 往父窗口冒泡;Dispatch 一条合成消息跳过了整条路由。

  用法:scrollcluster.exe [输出目录]   退出码 0 = 全部通过。
        窗口会真的出现在屏幕上并抢焦点(真输入的代价),跑完自动关。 }
program scrollcluster;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  {$IFDEF LCLWin32}Windows,{$ENDIF}
  Interfaces, Forms, Graphics, Controls, Classes, SysUtils, Types,
  StrUtils, Math, LCLType, LCLIntf, LMessages,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.Panel, tyControls.ScrollBar, tyControls.ScrollBox,
  tyControls.ScrollContent;

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

procedure Note(const AWhat: string);
begin
  Say('  ....  ' + AWhat);
end;

{ ProcessMessages 一轮不等于"屏幕上已经是这样了":WM_PAINT 要真的跑完、
  DWM 还要合成一帧。真机探针里每一处"看屏幕"之前都必须让出时间片,
  否则抓到的是上一帧甚至是空白 —— 那会给出一个假的红。 }
procedure Pump(ATimes: Integer = 3);
var
  i: Integer;
begin
  for i := 1 to ATimes do
  begin
    Application.ProcessMessages;
    Sleep(4);
  end;
end;

procedure Settle(AMs: Integer);
var
  t0: QWord;
begin
  t0 := GetTickCount64;
  repeat
    Application.ProcessMessages;
    Sleep(10);
  until GetTickCount64 - t0 >= QWord(AMs);
end;

{ ================================================================= 计数器 === }
{ 真的数 WM_PAINT。控件覆写 Paint 数不到这个:LCL 会合并无效区、也会在
  没有句柄时直接跳过,而"闪"这件事量的恰恰是屏幕被刷了几遍。 }

{$IFDEF LCLWin32}
const
  MaxHooks = 8;

type
  THookRec = record
    Wnd: HWND;
    OldProc: LONG_PTR;
    Paints: Integer;
    Erases: Integer;
    PosChanges: Integer;
    Name: string;
  end;

var
  Hooks: array[0..MaxHooks - 1] of THookRec;
  HookCount: Integer = 0;

function HookProc(AWnd: HWND; AMsg: UINT; AWParam: WPARAM; ALParam: LPARAM): LRESULT; stdcall;
var
  i: Integer;
  old: LONG_PTR;
begin
  old := 0;
  for i := 0 to HookCount - 1 do
    if Hooks[i].Wnd = AWnd then
    begin
      old := Hooks[i].OldProc;
      case AMsg of
        WM_PAINT:          Inc(Hooks[i].Paints);
        WM_ERASEBKGND:     Inc(Hooks[i].Erases);
        WM_WINDOWPOSCHANGED: Inc(Hooks[i].PosChanges);
      end;
      Break;
    end;
  if old <> 0 then
    Result := CallWindowProcW(Windows.WNDPROC(old), AWnd, AMsg, AWParam, ALParam)
  else
    Result := DefWindowProcW(AWnd, AMsg, AWParam, ALParam);
end;

function InstallHook(AControl: TWinControl; const AName: string): Integer;
begin
  Result := -1;
  if (AControl = nil) or not AControl.HandleAllocated then Exit;
  if HookCount >= MaxHooks then Exit;
  Hooks[HookCount].Wnd := AControl.Handle;
  Hooks[HookCount].Paints := 0;
  Hooks[HookCount].Erases := 0;
  Hooks[HookCount].PosChanges := 0;
  Hooks[HookCount].Name := AName;
  Hooks[HookCount].OldProc :=
    SetWindowLongPtrW(AControl.Handle, GWL_WNDPROC, LONG_PTR(@HookProc));
  Result := HookCount;
  Inc(HookCount);
end;

procedure ResetHooks;
var
  i: Integer;
begin
  for i := 0 to HookCount - 1 do
  begin
    Hooks[i].Paints := 0;
    Hooks[i].Erases := 0;
    Hooks[i].PosChanges := 0;
  end;
end;

function HookPaints(AIdx: Integer): Integer;
begin
  if (AIdx < 0) or (AIdx >= HookCount) then Exit(0);
  Result := Hooks[AIdx].Paints;
end;

function HookReport: string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to HookCount - 1 do
    Result := Result + Format('%s: paint=%d erase=%d poschg=%d  ',
      [Hooks[i].Name, Hooks[i].Paints, Hooks[i].Erases, Hooks[i].PosChanges]);
end;
{$ELSE}
function InstallHook(AControl: TWinControl; const AName: string): Integer;
begin Result := -1; end;
procedure ResetHooks; begin end;
function HookPaints(AIdx: Integer): Integer; begin Result := 0; end;
function HookReport: string; begin Result := '(非 Win32)'; end;
{$ENDIF}

{ ================================================================= 截屏 ==== }

{ 从**屏幕**抓一块。控件的 PaintTo 不行:它按控件树自顶向下画一遍,
  兄弟窗口的遮挡关系在里面根本不存在 —— 而 A1 问的就是遮挡。 }
function GrabScreen(const AScreenRect: TRect): TBitmap;
{$IFDEF LCLWin32}
var
  dc: HDC;
{$ENDIF}
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf32bit;
  Result.SetSize(AScreenRect.Right - AScreenRect.Left,
                 AScreenRect.Bottom - AScreenRect.Top);
  Result.Canvas.Brush.Color := clFuchsia;
  Result.Canvas.FillRect(0, 0, Result.Width, Result.Height);
  {$IFDEF LCLWin32}
  dc := Windows.GetDC(0);
  try
    Windows.BitBlt(Result.Canvas.Handle, 0, 0, Result.Width, Result.Height,
      dc, AScreenRect.Left, AScreenRect.Top, SRCCOPY);
  finally
    Windows.ReleaseDC(0, dc);
  end;
  {$ENDIF}
end;

{$IFDEF LCLWin32}
const
  PW_CLIENTONLY        = $00000001;
  PW_RENDERFULLCONTENT = $00000002;

{ FPC 3.2.2 的 Windows 单元没有导出 PrintWindow,自己声明。 }
function PrintWindow(AWnd: HWND; AHdc: HDC; AFlags: UINT): BOOL;
  stdcall; external 'user32' name 'PrintWindow';

{ 顶层窗口的**合成**内容。GetDC(0)+BitBlt 在一个已断开的会话里只会给出一片
  空白(没有显示驱动在渲染),而 PrintWindow + PW_RENDERFULLCONTENT 取的是
  DWM 的重定向表面 —— 子窗口按真实 Z 序合成在里面。这正是"兄弟遮挡"这件事
  唯一能在无显示会话里被诚实观测到的方式。 }
function GrabComposited(AForm: TCustomForm): TBitmap;
var
  wr: Windows.RECT;
begin
  Windows.GetWindowRect(AForm.Handle, @wr);
  Result := TBitmap.Create;
  Result.PixelFormat := pf32bit;
  Result.SetSize(wr.Right - wr.Left, wr.Bottom - wr.Top);
  Result.Canvas.Brush.Color := clFuchsia;
  Result.Canvas.FillRect(0, 0, Result.Width, Result.Height);
  PrintWindow(AForm.Handle, Result.Canvas.Handle, PW_RENDERFULLCONTENT);
end;
{$ENDIF}

{ 一张抓屏是不是"什么都没抓到"。全图一色 = 窗口没在那儿 / 没画完 / 坐标不对。
  不先判这一条,后面所有像素断言的红都是假的 —— 本探针第一版就在一个已断开的
  会话里拿到了一整块纯白,并据此"证明"了滚动条被盖住。 }
function IsBlank(ABmp: TBitmap): Boolean;
var
  x, y: Integer;
  c0: TColor;
begin
  Result := True;
  if (ABmp.Width < 2) or (ABmp.Height < 2) then Exit;
  c0 := ABmp.Canvas.Pixels[0, 0];
  y := 0;
  while y < ABmp.Height do
  begin
    x := 0;
    while x < ABmp.Width do
    begin
      if ABmp.Canvas.Pixels[x, y] <> c0 then Exit(False);
      Inc(x, 3);
    end;
    Inc(y, 3);
  end;
end;

{ 一个控件在**合成之后**长什么样。先试屏幕(有显示会话时最真),
  抓不到就退到 DWM 的合成表面 —— 两条路都保留真实的兄弟遮挡关系。 }
function GrabControl(AControl: TWinControl): TBitmap;
var
  p: TPoint;
{$IFDEF LCLWin32}
  full: TBitmap;
  wr: Windows.RECT;
{$ENDIF}
begin
  AControl.Invalidate;
  Settle(200);
  p := AControl.ClientToScreen(Point(0, 0));
  Result := GrabScreen(Rect(p.x, p.y, p.x + AControl.Width, p.y + AControl.Height));
  {$IFDEF LCLWin32}
  if not IsBlank(Result) then Exit;
  FreeAndNil(Result);
  full := GrabComposited(GetParentForm(AControl));
  try
    Windows.GetWindowRect(GetParentForm(AControl).Handle, @wr);
    Result := TBitmap.Create;
    Result.PixelFormat := pf32bit;
    Result.SetSize(AControl.Width, AControl.Height);
    Result.Canvas.CopyRect(Rect(0, 0, AControl.Width, AControl.Height), full.Canvas,
      Rect(p.x - wr.Left, p.y - wr.Top,
           p.x - wr.Left + AControl.Width, p.y - wr.Top + AControl.Height));
  finally
    full.Free;
  end;
  {$ENDIF}
end;

procedure SavePng(ABmp: TBitmap; const AName: string);
var
  png: TPortableNetworkGraphic;
begin
  png := TPortableNetworkGraphic.Create;
  try
    png.Assign(ABmp);
    png.SaveToFile(IncludeTrailingPathDelimiter(OutDir) + AName + '.png');
    Say('  shot  ' + AName + '.png');
  finally
    png.Free;
  end;
end;

{ ============================================================== 真输入 ===== }

{$IFDEF LCLWin32}
var
  SavedCursor: TPoint;

procedure SaveCursor;
begin
  Windows.GetCursorPos(@SavedCursor);
end;

procedure RestoreCursor;
begin
  Windows.SetCursorPos(SavedCursor.x, SavedCursor.y);
end;

{ SetForegroundWindow 从一个**非前台**进程里调用会被 Windows 静默拒绝
  (防抢焦点)。经典解法:把自己的输入队列临时挂到当前前台线程上,
  这段时间里 SetForegroundWindow 才被允许。不做这一步,真滚轮和真拖动
  会一条都送不到 —— 而探针会把它读成"功能坏了",一个假的红。 }
function ForceForeground(AWnd: HWND): Boolean;
var
  fg: HWND;
  myTid, fgTid: DWORD;
begin
  Windows.ShowWindow(AWnd, SW_SHOW);
  Windows.SetWindowPos(AWnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE);
  fg := Windows.GetForegroundWindow;
  if fg = AWnd then Exit(True);
  myTid := Windows.GetCurrentThreadId;
  fgTid := Windows.GetWindowThreadProcessId(fg, nil);
  if (fgTid <> 0) and (fgTid <> myTid) then
    Windows.AttachThreadInput(myTid, fgTid, True);
  try
    Windows.BringWindowToTop(AWnd);
    Windows.SetForegroundWindow(AWnd);
    Windows.SetActiveWindow(AWnd);
  finally
    if (fgTid <> 0) and (fgTid <> myTid) then
      Windows.AttachThreadInput(myTid, fgTid, False);
  end;
  Settle(150);
  Result := Windows.GetForegroundWindow = AWnd;
end;

procedure MoveTo(AControl: TControl; AX, AY: Integer);
var
  p: TPoint;
begin
  p := AControl.ClientToScreen(Point(AX, AY));
  Windows.SetCursorPos(p.x, p.y);
  Pump(2);
end;

{ 真输入送到了吗?光标真的落在我们要的控件上,才算送到。 }
function CursorIsOver(AControl: TWinControl): Boolean;
var
  p: TPoint;
begin
  Windows.GetCursorPos(@p);
  Result := Windows.WindowFromPoint(p) = AControl.Handle;
end;

{ 真滚轮 = 一条送进目标窗口 WndProc 的 WM_MOUSEWHEEL,lParam 是**屏幕**坐标。
  Windows 自己做的也正是这件事(它把消息 SendMessage 给焦点窗口),而 LCL 的
  win32callback.inc DoMsgMouseWheel 会照着 lParam 里的点去 WindowFromPoint,
  再决定重定向还是自己吃 —— 所以先把光标摆到位,这条路才和真手一模一样。

  为什么不用 mouse_event:这台机器的会话是**断开**的(qwinsta 显示 Disc),
  没有显示驱动也没有前台窗口,OS 输入队列不会投递。用 mouse_event 会得到
  "什么都没发生",那是环境的红,不是控件的红。 }
procedure WheelAt(AControl: TWinControl; AX, AY, ADelta: Integer);
var
  p: TPoint;
begin
  p := AControl.ClientToScreen(Point(AX, AY));
  Windows.SetCursorPos(p.x, p.y);
  Windows.SendMessage(AControl.Handle, WM_MOUSEWHEEL,
    WPARAM((DWORD(ADelta) shl 16) and $FFFF0000), LPARAM((p.y shl 16) or (p.x and $FFFF)));
  Pump(4);
end;

procedure MouseDownAt(AControl: TWinControl; AX, AY: Integer);
begin
  Windows.SendMessage(AControl.Handle, WM_LBUTTONDOWN, MK_LBUTTON,
    LPARAM((AY shl 16) or (AX and $FFFF)));
  Pump(2);
end;

procedure MouseMoveAt(AControl: TWinControl; AX, AY: Integer);
begin
  Windows.SendMessage(AControl.Handle, WM_MOUSEMOVE, MK_LBUTTON,
    LPARAM((AY shl 16) or (AX and $FFFF)));
  Pump(2);
end;

procedure MouseUpAt(AControl: TWinControl; AX, AY: Integer);
begin
  Windows.SendMessage(AControl.Handle, WM_LBUTTONUP, 0,
    LPARAM((AY shl 16) or (AX and $FFFF)));
  Pump(2);
end;
{$ENDIF}

{ ============================================================== 场景 ======= }

type
  { 数控件自己的重绘 + 对齐轮数。ControlsAligned 是 LCL 每跑完一轮子控件布局
    就调的钩子 —— 也正是 TTyScrollBox 自己重算范围的入口,所以它既是"风暴"的
    计数器,又是风暴的引信。 }
  TCountBox = class(TTyScrollBox)
  private
    FPaints, FAligns: Integer;
  protected
    procedure Paint; override;
    procedure ControlsAligned; override;
  public
    procedure ResetCounts;
    function ChildArea: TRect;
    property Paints: Integer read FPaints;
    property Aligns: Integer read FAligns;
  end;

  TCountPanel = class(TTyPanel)
  private
    FPaints, FMoves: Integer;
  protected
    procedure Paint; override;
  public
    procedure SetBounds(ALeft, ATop, AWidth, AHeight: Integer); override;
    procedure ResetCounts;
    property Paints: Integer read FPaints;
    property Moves: Integer read FMoves;
  end;

procedure TCountBox.Paint;
begin
  Inc(FPaints);
  inherited Paint;
end;

procedure TCountBox.ControlsAligned;
begin
  Inc(FAligns);
  inherited ControlsAligned;
end;

procedure TCountBox.ResetCounts;
begin
  FPaints := 0;
  FAligns := 0;
end;

function TCountBox.ChildArea: TRect;
begin
  Result := GetLogicalClientRect;
  AdjustClientRect(Result);
end;

procedure TCountPanel.Paint;
begin
  Inc(FPaints);
  inherited Paint;
end;

procedure TCountPanel.SetBounds(ALeft, ATop, AWidth, AHeight: Integer);
begin
  if (ALeft <> Left) or (ATop <> Top) or (AWidth <> Width) or (AHeight <> Height) then
    Inc(FMoves);
  inherited SetBounds(ALeft, ATop, AWidth, AHeight);
end;

procedure TCountPanel.ResetCounts;
begin
  FPaints := 0;
  FMoves := 0;
end;

var
  Form: TForm;
  Box: TCountBox;
  Wide: TCountPanel;
  HookBox: Integer = -1;
  HookVBar: Integer = -1;
  HookWide: Integer = -1;
  { 这套 LCL 上"移动一个子控件"的对齐轮数底线,由 AlignFloorPerChildMove 实测。 }
  AlignFloor: Integer = 1;

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

function R2S(const R: TRect): string;
begin
  Result := Format('(%d,%d %dx%d)', [R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top]);
end;

procedure BuildScene;
begin
  Form := TForm.Create(Application);
  Form.Caption := 'scrollcluster';
  Form.SetBounds(80, 80, 560, 420);
  Form.FormStyle := fsStayOnTop;   { 抓屏时别被别的窗口盖住 }

  Box := TCountBox.Create(Form);
  Box.Parent := Form;
  Box.SetBounds(20, 20, 400, 300);

  { 故意比视口宽 —— 它会横跨垂直条那一槽。用户报的正是"我往里丢了个
    TTyPanel,条就被盖住了"。 }
  Wide := TCountPanel.Create(Box);
  Wide.Parent := Box;
  Wide.SetBounds(0, 0, 560, 900);

  Form.Show;
  Settle(300);
  Box.UpdateScrollRange;
  Settle(150);
  {$IFDEF LCLWin32}
  ForceForeground(Form.Handle);
  {$ENDIF}
  Settle(200);
end;

{ 环境自证 —— 抓屏和真输入都依赖它,写进日志才能事后判断一条红是真是假。 }
procedure Case_Env;
{$IFDEF LCLWin32}
var
  wr: Windows.RECT;
  p: TPoint;
  shot: TBitmap;
{$ENDIF}
begin
  Say('[env] 探针环境');
  {$IFDEF LCLWin32}
  Windows.GetWindowRect(Form.Handle, @wr);
  p := Box.ClientToScreen(Point(0, 0));
  Say(Format('     屏幕 %dx%d  窗口 (%d,%d %dx%d)  box 屏幕原点 (%d,%d)  box %dx%d',
    [Windows.GetSystemMetrics(SM_CXSCREEN), Windows.GetSystemMetrics(SM_CYSCREEN),
     wr.Left, wr.Top, wr.Right - wr.Left, wr.Bottom - wr.Top,
     p.x, p.y, Box.Width, Box.Height]));
  if Windows.GetForegroundWindow = Form.Handle then
    Note('探针窗口在前台 —— 屏幕抓取可用')
  else
    Note(Format('无前台窗口(前台句柄=%d)—— 会话已断开,退到 DWM 合成表面抓取',
      [PtrUInt(Windows.GetForegroundWindow)]));
  shot := GrabScreen(Rect(wr.Left, wr.Top, wr.Right, wr.Bottom));
  try
    if IsBlank(shot) then
    begin
      Note('GetDC(0) 抓屏全同色(会话无显示驱动),改用 PrintWindow');
      shot.Free;
      shot := GrabComposited(Form);
    end;
    SavePng(shot, 'env-window');
    Check('拿到了窗口的真实合成图(不是一片空白)', not IsBlank(shot),
      'PrintWindow 也是空白 —— 本次运行的所有像素判定都不可信');
  finally
    shot.Free;
  end;
  {$ELSE}
  Say('     非 Win32,跳过');
  {$ENDIF}
end;

{ ---------------------------------------------------------------- A1 ------ }
{ 滚动条要在**自己那一槽**里赢过任何一种子控件。两个层次:
  (a) 真 Z 序:兄弟窗口链里条必须比内容靠上;
  (b) 真像素:槽的**边缘列**必须是条画出来的,不是子面板画出来的。
      探边缘不探中心 —— 中心对任何"少画一两列"的漂移都免疫。 }
procedure Case_A1_GutterOwnership;
var
  V: TTyScrollBar;
  scr, ref: TBitmap;
  x, y, bad, total: Integer;
  gutterL: Integer;
  cScr, cRef, cBody: TColor;
  diffFromBody: Integer;
{$IFDEF LCLWin32}
  h: HWND;
  depth, vDepth, worstContent, i: Integer;
  c: TControl;
{$ENDIF}
begin
  Say('[A1] 滚动条 vs 窗口化子控件 —— 槽的归属');
  V := BarOf(Box, sbVertical);
  Check('垂直条出现了', (V <> nil) and V.Visible);
  if (V = nil) or not V.Visible then Exit;
  Say(Format('     box=%dx%d  wide=%s  vbar=%s',
    [Box.Width, Box.Height, R2S(Wide.BoundsRect), R2S(V.BoundsRect)]));
  Check('子面板确实横跨了槽(这个用例才有意义)',
    Wide.Left + Wide.Width > V.Left,
    Format('面板右缘 %d,槽左缘 %d', [Wide.Left + Wide.Width, V.Left]));

  {$IFDEF LCLWin32}
  vDepth := -1; worstContent := -1;
  h := GetWindow(Box.Handle, GW_CHILD);
  depth := 0;
  while h <> 0 do
  begin
    for i := 0 to Box.ControlCount - 1 do
    begin
      c := Box.Controls[i];
      if (c is TWinControl) and TWinControl(c).HandleAllocated
         and (TWinControl(c).Handle = h) then
      begin
        if c = V then vDepth := depth
        else if not (c is TTyScrollBar) and (depth > worstContent) then
          worstContent := depth;
      end;
    end;
    h := GetWindow(h, GW_HWNDNEXT);
    Inc(depth);
  end;
  Say(Format('     真 Z 序:vbar 深度=%d  最靠下的内容深度=%d(小 = 更靠上)',
    [vDepth, worstContent]));
  Check('垂直条在窗口化内容之上(真兄弟链)',
    (vDepth >= 0) and (worstContent >= 0) and (vDepth < worstContent),
    Format('vbar=%d content=%d', [vDepth, worstContent]));
  {$ENDIF}

  { 像素层:槽的两条边缘列必须等于"条单独画出来"的样子。 }
  scr := GrabControl(Box);
  ref := TBitmap.Create;
  try
    SavePng(scr, 'a1-box-onscreen');
    if IsBlank(scr) then
    begin
      Check('抓到的是真窗口(不是空白)', False,
        '整块抓屏同色 —— 环境问题,不是控件问题,像素判定作废');
      Exit;
    end;
    ref.PixelFormat := pf32bit;
    ref.SetSize(V.Width, V.Height);
    ref.Canvas.Brush.Color := clFuchsia;
    ref.Canvas.FillRect(0, 0, ref.Width, ref.Height);
    V.PaintTo(ref.Canvas, 0, 0);
    SavePng(ref, 'a1-vbar-reference');

    gutterL := V.Left;
    bad := 0; total := 0; diffFromBody := 0;
    { 只探两条**边缘列**,y 也只取条自己的上下缘内一格 —— 中心列对
      "内容少盖了一两列"完全免疫。 }
    for y := V.Top + 1 to V.Top + V.Height - 2 do
    begin
      for x := gutterL to gutterL + V.Width - 1 do
      begin
        if (x <> gutterL) and (x <> gutterL + V.Width - 1) then Continue;
        if (x >= scr.Width) or (y >= scr.Height) then Continue;
        Inc(total);
        cScr := scr.Canvas.Pixels[x, y];
        cRef := ref.Canvas.Pixels[x - gutterL, y - V.Top];
        if cScr <> cRef then Inc(bad);
        { 与面板体色的差异 —— 条真的赢了的话,槽里的像素不该等于面板体色。 }
        if gutterL >= 8 then
        begin
          cBody := scr.Canvas.Pixels[gutterL - 6, y];
          if cScr <> cBody then Inc(diffFromBody);
        end;
      end;
    end;
    Say(Format('     槽边缘像素:%d 个,与"条单独渲染"不符 %d 个,与面板体色不同 %d 个',
      [total, bad, diffFromBody]));
    Check('槽的边缘列由条画出(与条自身渲染一致)',
      (total > 0) and (bad * 100 <= total * 5),
      Format('%d/%d 不符', [bad, total]));
    Check('槽的边缘列不是面板的体色',
      (total > 0) and (diffFromBody * 100 >= total * 90),
      Format('只有 %d/%d 与面板体色不同', [diffFromBody, total]));
  finally
    ref.Free;
    scr.Free;
  end;
end;

{ ---------------------------------------------------------------- A2 ------ }
{ 滚轮第一格。真 mouse_event,指针停在**子面板**上 —— 用户的手就在那儿,
  而这条路上 LCL 要先把消息重定向给 WindowFromPoint,再由 DefWindowProc
  往父窗口冒泡。合成 Dispatch 跳过整条路由,所以测不出方向。 }
procedure Case_A2_FirstWheelTick;
{$IFDEF LCLWin32}
var
  V: TTyScrollBar;
  y0, y1, y2, y3, y4: Integer;
{$ENDIF}
begin
  Say('[A2] 滚轮第一格的方向');
  {$IFDEF LCLWin32}
  V := BarOf(Box, sbVertical);
  if (V = nil) or not V.Visible then
  begin
    Check('有垂直条', False, '没有条,跳过');
    Exit;
  end;
  Box.ScrollTo(0, 0);
  Settle(120);
  y0 := Box.ScrollY;

  { 落点在**子面板**上 —— 用户的手就在那儿。这是关键:LCL 会先把消息交给
    面板,面板不认,再由 DefWindowProc 往父窗口冒泡。 }
  WheelAt(Wide, 40, 40, -WHEEL_DELTA);   { 第一格:向下 }
  y1 := Box.ScrollY;
  Say(Format('     指针在子面板上:起点 %d,第一格向下 -> %d', [y0, y1]));
  Check('滚轮落在子面板上时,滚动框会滚(第一格)', y1 <> y0,
    Format('%d -> %d(纹丝不动 = 滚轮根本没冒泡到滚动框)', [y0, y1]));
  Check('第一格向下滚:偏移增大(内容向上走)', y1 > y0,
    Format('%d -> %d', [y0, y1]));

  WheelAt(Wide, 40, 40, -WHEEL_DELTA);   { 第二格:同向 }
  y2 := Box.ScrollY;
  Say(Format('     第二格向下 -> %d', [y2]));
  Check('第二格与第一格同向', y2 > y1, Format('%d -> %d', [y1, y2]));
  Check('第一格与第二格步长相同(第一格不是"半步"或"反向再回来")',
    (y1 - y0) = (y2 - y1), Format('第一步 %d,第二步 %d', [y1 - y0, y2 - y1]));

  WheelAt(Wide, 40, 40, WHEEL_DELTA);    { 第一格向上 }
  y3 := Box.ScrollY;
  Say(Format('     第一格向上 -> %d', [y3]));
  Check('向上滚:偏移减小', y3 < y2, Format('%d -> %d', [y2, y3]));

  { 已经在顶端时的第一格向上:不能反向跑掉。 }
  Box.ScrollTo(0, 0);
  Settle(80);
  WheelAt(Wide, 40, 40, WHEEL_DELTA);
  y4 := Box.ScrollY;
  Check('顶端再向上滚不动(不反弹)', y4 = 0, Format('实际 %d', [y4]));

  { 落在滚动框自己的空白处 —— 对照组。子面板铺满了框,所以拿视口右下角
    那块两条之间的角落做落点其实也在面板外。直接给框发一条。 }
  Box.ScrollTo(0, 0);
  Settle(80);
  y0 := Box.ScrollY;
  WheelAt(Box, 4, 4, -WHEEL_DELTA);
  Say(Format('     指针在滚动框自己身上:%d -> %d', [y0, Box.ScrollY]));
  Check('滚轮落在滚动框自己身上时也向下滚', Box.ScrollY > y0,
    Format('%d -> %d', [y0, Box.ScrollY]));
  {$ELSE}
  Say('     非 Win32,跳过');
  {$ENDIF}
end;

{ ------------------------------------------------------- A3 / A4 ---------- }
{ 一次拖动 = 一次落位。数的是真 WM_PAINT、对齐轮数、以及**条自己的边界**
  有没有在一次拖动里被搬来搬去(那是 1px 抖动,肉眼就是"闪")。 }

type
  TDragStat = record
    Steps: Integer;
    BoxPaints, VBarPaints, WidePaints: Integer;
    Aligns: Integer;
    WideMoves: Integer;
    BarBoundsChanges: Integer;
    Backwards: Integer;      { 偏移倒退的次数 —— "跳动"的硬证据 }
    MaxStep, MinStep: Integer;
  end;

{ 用 Perform 走真消息处理链(TControl.WMLButtonDown -> MouseDown 等),
  这样每一步都可复现、可计数;真 mouse_event 那一版在 Case_A3_RealDrag。 }
function CountedDrag(APixelStep, ASteps: Integer; out AStat: TDragStat): Boolean;
var
  V: TTyScrollBar;
  i, py, prevY, dy: Integer;
  b0: TRect;
begin
  Result := False;
  FillChar(AStat, SizeOf(AStat), 0);
  AStat.MinStep := MaxInt;
  V := BarOf(Box, sbVertical);
  if (V = nil) or not V.Visible then Exit;

  Box.ScrollTo(0, 0);
  Pump(4);
  { 抓在拇指中间。 }
  py := V.Height div 8;
  V.BeginThumbDrag(py);
  Pump(2);
  ResetHooks;
  Box.ResetCounts;
  Wide.ResetCounts;
  prevY := Box.ScrollY;
  b0 := V.BoundsRect;

  for i := 1 to ASteps do
  begin
    Inc(py, APixelStep);
    V.DragThumbTo(py);
    Pump(3);
    if not EqualRect(V.BoundsRect, b0) then
    begin
      Inc(AStat.BarBoundsChanges);
      b0 := V.BoundsRect;
    end;
    dy := Box.ScrollY - prevY;
    if dy < 0 then Inc(AStat.Backwards);
    if dy > AStat.MaxStep then AStat.MaxStep := dy;
    if dy < AStat.MinStep then AStat.MinStep := dy;
    prevY := Box.ScrollY;
  end;
  V.EndThumbDrag;
  Pump(3);

  AStat.Steps := ASteps;
  AStat.BoxPaints := HookPaints(HookBox);
  AStat.VBarPaints := HookPaints(HookVBar);
  AStat.WidePaints := HookPaints(HookWide);
  AStat.Aligns := Box.Aligns;
  AStat.WideMoves := Wide.Moves;
  Result := True;
end;

procedure Case_A3_PaintStorm;
var
  st: TDragStat;
begin
  Say('[A3] 拖滑块的重绘代价 —— 一次拖动该是一次落位');
  if not CountedDrag(4, 12, st) then
  begin
    Check('有垂直条可拖', False);
    Exit;
  end;
  Say(Format('     %d 步拖动:box WM_PAINT=%d  vbar WM_PAINT=%d  内容 WM_PAINT=%d',
    [st.Steps, st.BoxPaints, st.VBarPaints, st.WidePaints]));
  Say(Format('     ControlsAligned=%d  内容 SetBounds=%d  条自身边界变化=%d',
    [st.Aligns, st.WideMoves, st.BarBoundsChanges]));

  { 条自己的**边界**在一次纯滚动里根本不该动:它就贴在槽上。动了就是
    两处停靠代码在互相拉扯,肉眼看就是条在 1px 抖 —— 也就是"闪"。 }
  Check('拖动没有搬动滚动条自己的边界', st.BarBoundsChanges = 0,
    Format('%d 步里条被搬动了 %d 次', [st.Steps, st.BarBoundsChanges]));

  { 一步拖动 = 一次落位。判据是**实测**的底线(AlignFloorPerChildMove),不是拍脑袋的 1:
    滚动本身就是"移动子控件",所以它不可能比移动一个子控件更便宜。 }
  Check(Format('每步的对齐轮数没有超过移动一个子控件的底线(%d 轮)', [AlignFloor]),
    st.Aligns <= st.Steps * AlignFloor,
    Format('%d 步引发了 %d 轮对齐,底线是 %d 轮/步', [st.Steps, st.Aligns, AlignFloor]));

  { 内容被 SetBounds 的次数:每步应当正好一次(就是滚动本身那一次)。 }
  Check('每步内容只被移动一次', st.WideMoves <= st.Steps,
    Format('%d 步里内容被移动了 %d 次', [st.Steps, st.WideMoves]));

  { 内容自己的重绘:滚动必然要重画内容,但一步一次就够。 }
  Check('每步内容至多重绘一次', st.WidePaints <= st.Steps,
    Format('%d 步里内容重绘了 %d 次', [st.Steps, st.WidePaints]));
end;

procedure Case_A4_ContentHops;
var
  st: TDragStat;
begin
  Say('[A4] 拖动时内容跳动 —— 单调的拖必须给出单调的偏移');
  if not CountedDrag(3, 20, st) then
  begin
    Check('有垂直条可拖', False);
    Exit;
  end;
  Say(Format('     20 步单向拖动:偏移倒退 %d 次,单步 min=%d max=%d',
    [st.Backwards, st.MinStep, st.MaxStep]));
  Check('单向拖动中偏移从不倒退', st.Backwards = 0,
    Format('倒退 %d 次', [st.Backwards]));
  { 每步 3px 拖动换算成内容偏移应当大体相等;某一步比别的步大一倍以上
    就是"跳"。允许 ±1 的整数除法抖动。 }
  Check('单步位移没有突变(最大步 <= 最小步 + 2)',
    (st.MinStep = MaxInt) or (st.MaxStep <= st.MinStep + 2),
    Format('min=%d max=%d', [st.MinStep, st.MaxStep]));
end;

{ A4 的第二、三个场景。第一个(A4)是一个 alNone 的大子控件 —— 布局引擎
  几乎不参与,所以它测不到"布局把偏移又算了一遍"这一类跳动。真正会跳的是
    (b) 一排 alTop 行:每次 realign 都按 AdjustClientRect 重摆,偏移进了两次账;
    (c) 装在 TTyScrollContent 视口里的对齐子控件:视口自己的布局区**不带**偏移。 }
procedure DragAndReport(ABox: TCountBox; const AWhat: string;
  APixelStep, ASteps: Integer; out ABack, AMinStep, AMaxStep, AAligns: Integer);
var
  V: TTyScrollBar;
  i, py, prevY, dy: Integer;
begin
  ABack := 0; AMinStep := MaxInt; AMaxStep := -MaxInt; AAligns := 0;
  V := BarOf(ABox, sbVertical);
  if (V = nil) or not V.Visible then Exit;
  ABox.ScrollTo(0, 0);
  Pump(3);
  ABox.ResetCounts;
  py := V.Height div 10;
  V.BeginThumbDrag(py);
  prevY := ABox.ScrollY;
  for i := 1 to ASteps do
  begin
    Inc(py, APixelStep);
    V.DragThumbTo(py);
    Pump(2);
    dy := ABox.ScrollY - prevY;
    if dy < 0 then Inc(ABack);
    if dy > AMaxStep then AMaxStep := dy;
    if dy < AMinStep then AMinStep := dy;
    prevY := ABox.ScrollY;
  end;
  V.EndThumbDrag;
  Pump(2);
  AAligns := ABox.Aligns;
end;

{ 相邻 alTop 兄弟必须首尾相接:返回最坏的一处间隙(0 = 都接上了,负 = 重叠)。

  按 **Top 排序**再比,不是按子控件表的顺序:代码里创建的同向对齐兄弟在 LCL 里
  按反创建序显示(memory/lcl-code-created-align-order),照表序两两相减量到的是
  "第 1 个和第 2 个",而它们在屏幕上根本不相邻 —— 这个探针的第一版就是这么
  量出了一个 -60 的假重叠。 }
function WorstGap(AHost: TWinControl): Integer;
var
  i, j, n, gap: Integer;
  c: TControl;
  tops: array of TControl;
  tmp: TControl;
begin
  Result := 0;
  SetLength(tops, 0);
  for i := 0 to AHost.ControlCount - 1 do
  begin
    c := AHost.Controls[i];
    if (c is TTyScrollBar) or (c is TTyScrollContent) or (c.Align <> alTop) then Continue;
    SetLength(tops, Length(tops) + 1);
    tops[High(tops)] := c;
  end;
  n := Length(tops);
  for i := 0 to n - 2 do
    for j := 0 to n - 2 - i do
      if tops[j].Top > tops[j + 1].Top then
      begin
        tmp := tops[j]; tops[j] := tops[j + 1]; tops[j + 1] := tmp;
      end;
  for i := 1 to n - 1 do
  begin
    gap := tops[i].Top - (tops[i - 1].Top + tops[i - 1].Height);
    if Abs(gap) > Abs(Result) then Result := gap;
  end;
end;

{ 在这套 LCL 上,"移动一个子控件"最少要花掉几轮 ControlsAligned?

  没有这个数,A3 的"每步至多一轮"就是凭空定的标准。EnableAutoSizing 收尾时
  LCL 自己会跑 DoAllAutoSize,它是分阶段的 —— 底线不一定是 1。所以先量底线,
  再拿它当 A3 的判据。 }
function AlignFloorPerChildMove: Integer;
var
  b: TCountBox;
  kid: TTyPanel;
  i: Integer;
const
  Moves = 10;
begin
  b := TCountBox.Create(Form);
  b.Parent := Form;
  b.SetBounds(440, 360, 80, 40);
  kid := TTyPanel.Create(b);
  kid.Parent := b;
  kid.SetBounds(0, 0, 20, 20);       { 放得下 —— 一条滚动条都不出来 }
  Pump(6);
  b.UpdateScrollRange;
  Pump(4);
  b.ResetCounts;
  for i := 1 to Moves do
  begin
    b.DisableAutoSizing;
    try
      kid.SetBounds(kid.Left, kid.Top + 1, kid.Width, kid.Height);
    finally
      b.EnableAutoSizing;
    end;
    Pump(2);
  end;
  Result := Round(b.Aligns / Moves);
  b.Free;
end;

procedure Case_A4b_AlignedRows;
var
  b: TCountBox;
  r: TTyPanel;
  i, back, mn, mx, al: Integer;
begin
  Say('[A4b] 一排 alTop 行 —— 布局引擎全程参与时的拖动');
  b := TCountBox.Create(Form);
  b.Parent := Form;
  b.SetBounds(440, 20, 100, 160);
  for i := 1 to 12 do
  begin
    r := TTyPanel.Create(b);
    r.Parent := b;
    r.Align := alTop;
    r.Height := 30;
  end;
  Pump(6);
  b.UpdateScrollRange;
  Pump(4);
  Say(Format('     content=%dx%d  行间最坏间隙=%d',
    [b.ContentWidth, b.ContentHeight, WorstGap(b)]));
  Check('alTop 行也能把条顶出来', BarOf(b, sbVertical) <> nil);

  DragAndReport(b, 'alTop', 2, 20, back, mn, mx, al);
  Say(Format('     20 步拖动:倒退 %d 次,单步 min=%d max=%d,对齐 %d 轮,行间隙=%d',
    [back, mn, mx, al, WorstGap(b)]));
  Check('alTop 行拖动时偏移不倒退', back = 0, Format('倒退 %d 次', [back]));
  Check('alTop 行拖动时单步位移不突变',
    (mn = MaxInt) or (mx <= mn + 2), Format('min=%d max=%d', [mn, mx]));
  Check('拖完之后每行依然首尾相接', WorstGap(b) = 0,
    Format('最坏间隙 %d', [WorstGap(b)]));
  Check('alTop 场景每步的对齐轮数没有超过底线', al <= 20 * AlignFloor,
    Format('20 步 %d 轮,底线 %d 轮/步', [al, AlignFloor]));
end;

procedure Case_A4c_AlignedInViewport;
var
  b: TCountBox;
  vp: TTyScrollContent;
  r: TTyPanel;
  i, back, mn, mx, al, top0: Integer;
  first: TTyPanel;
begin
  Say('[A4c] 视口里的 alTop 行 —— 视口的布局区带不带偏移');
  b := TCountBox.Create(Form);
  b.Parent := Form;
  b.SetBounds(440, 190, 100, 160);
  vp := TTyScrollContent.Create(b);
  vp.Parent := b;
  first := nil;
  for i := 1 to 12 do
  begin
    r := TTyPanel.Create(vp);
    r.Parent := vp;
    r.Align := alTop;
    r.Height := 30;
    if first = nil then first := r;
  end;
  Pump(6);
  b.UpdateScrollRange;
  Pump(4);
  Say(Format('     content=%dx%d  viewport=%s',
    [b.ContentWidth, b.ContentHeight, R2S(vp.BoundsRect)]));
  Check('视口里的 alTop 行也能把条顶出来', BarOf(b, sbVertical) <> nil);
  if BarOf(b, sbVertical) = nil then Exit;

  top0 := first.Top;
  DragAndReport(b, 'viewport-alTop', 2, 20, back, mn, mx, al);
  Say(Format('     20 步拖动:倒退 %d 次,单步 min=%d max=%d,对齐 %d 轮;首行 Top %d -> %d,ScrollY=%d',
    [back, mn, mx, al, top0, first.Top, b.ScrollY]));
  Check('视口里的对齐子控件真的跟着滚了(没有被 realign 拉回原位)',
    first.Top < top0, Format('%d -> %d(ScrollY=%d)', [top0, first.Top, b.ScrollY]));
  Check('视口场景偏移不倒退', back = 0, Format('倒退 %d 次', [back]));
  Check('视口场景单步位移不突变',
    (mn = MaxInt) or (mx <= mn + 2), Format('min=%d max=%d', [mn, mx]));
end;

{ [A6] 视口里 akRight 锚定的子控件,连滚多次之后宽度不能变。

  这是本库已经吃过一次的坏法(见 TTyScrollBox.GetClientRect 的注释):LCL 从
  ClientWidth/ClientHeight 记锚定基线(TControl.UpdateBaseBounds),却按
  GetLogicalClientRect/AdjustClientRect 摆放。两者差一点,每一次滚动(ScrollBy 会
  给每个子控件写 bounds)就把这个差额再记一次,akRight 的子控件一格格被吃掉。

  盒子那一层 tests/scrollverify [13] 已经钉住了;**视口**这一层没有 —— 而视口的
  布局区现在也会跟着偏移走、跟着内容涨,同一个坏法在这里是全新的。锚定基线读的正是
  被缓存的那个 client rect,所以这一条也是 SetScrollOrigin 里 InvalidateClientRectCache
  的唯一守卫:没有它,那一行是个存活的变异体。 }
procedure Case_A6_AnchoredInViewport;
var
  b: TCountBox;
  vp: TTyScrollContent;
  tall, anch: TTyPanel;
  V: TTyScrollBar;
  i, w0: Integer;
  widths: string;
begin
  Say('[A6] 视口里 akRight 锚定的子控件连滚多次后宽度不变');
  b := TCountBox.Create(Form);
  b.Parent := Form;
  b.SetBounds(20, 360, 200, 120);
  vp := TTyScrollContent.Create(b);
  vp.Parent := b;
  tall := TTyPanel.Create(vp);
  tall.Parent := vp;
  tall.SetBounds(0, 0, 60, 600);          { 撑出垂直溢出 }
  anch := TTyPanel.Create(vp);
  anch.Parent := vp;
  anch.SetBounds(70, 0, 100, 30);
  anch.Anchors := [akTop, akLeft, akRight];
  Pump(6);
  b.UpdateScrollRange;
  Pump(4);

  V := BarOf(b, sbVertical);
  Check('前置条件:视口内容溢出,有垂直条', (V <> nil) and V.Visible);
  if (V = nil) or not V.Visible then Exit;

  w0 := anch.Width;
  widths := IntToStr(w0);
  for i := 1 to 6 do
  begin
    V.Position := V.Position + 40;
    Pump(3);
    widths := widths + ' -> ' + IntToStr(anch.Width);
  end;
  Say(Format('     viewport=%s  锚定子控件宽度:%s', [R2S(vp.BoundsRect), widths]));
  Check('连滚 6 次没有改变 akRight 子控件的宽度', anch.Width = w0,
    Format('%d -> %d(每滚一次被吃掉一点 = 锚定基线与布局区不一致)', [w0, anch.Width]));
end;

{ [A7] 视口开了 ChildSizing 表格布局之后仍然能滚。

  这一条存在的唯一理由是变异测试:把 SetScrollOrigin 里的 InvalidateClientRectCache
  换成空操作,A1..A6 全绿 —— 一个存活的变异体。查 LCL 才知道被缓存的那个矩形
  (FAdjustClientRect / wcfAdjustedLogicalClientRectValid)只有两个读者,都在
  ChildSizing 的表格布局路径上(wincontrol.inc:948 与 :6324),而
  ChildSizing.Layout 默认是 cclNone —— 所以默认配置下那行确实观测不到。

  它不是死代码:ChildSizing 是 LCL 容器的正常功能,宿主一开它,缓存就活了,
  而滚动**每一步**都在不改视口自身 bounds 的前提下改变布局原点(那是 LCL 自己
  会失效缓存的唯一时机)。于是这一条把探针开到那条路径上,让那行代码有守卫。 }
procedure Case_A7_ViewportChildSizing;
var
  b: TCountBox;
  vp: TTyScrollContent;
  i, top0: Integer;
  kid, first: TTyPanel;
  V: TTyScrollBar;
begin
  Say('[A7] 视口 + ChildSizing 表格布局 —— 滚动仍然把子控件带走');
  b := TCountBox.Create(Form);
  b.Parent := Form;
  b.SetBounds(230, 360, 180, 100);
  vp := TTyScrollContent.Create(b);
  vp.Parent := b;
  { 打开表格布局 —— 这才让 LCL 去读那个被缓存的 adjusted client rect。 }
  vp.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
  vp.ChildSizing.ControlsPerLine := 1;
  first := nil;
  for i := 1 to 10 do
  begin
    kid := TTyPanel.Create(vp);
    kid.Parent := vp;
    kid.SetBounds(0, 0, 80, 40);
    if first = nil then first := kid;
  end;
  Pump(8);
  b.UpdateScrollRange;
  Pump(4);

  V := BarOf(b, sbVertical);
  Say(Format('     content=%dx%d  viewport=%s  vbar=%s',
    [b.ContentWidth, b.ContentHeight, R2S(vp.BoundsRect),
     IfThen(V = nil, '<nil>', R2S(V.BoundsRect))]));
  Check('前置条件:表格布局的内容也把条顶出来了', (V <> nil) and V.Visible);
  if (V = nil) or not V.Visible then Exit;

  top0 := first.Top;
  V.Position := V.Max div 2;
  Pump(4);
  Say(Format('     ScrollY=%d  首个子控件 Top %d -> %d', [b.ScrollY, top0, first.Top]));
  Check('ChildSizing 布局下滚动照样把子控件带走了', first.Top < top0,
    Format('%d -> %d(没动 = 表格布局读到了陈旧的 client rect)', [top0, first.Top]));
end;

{ 真鼠标那一版:抓屏留证,并再数一遍真 WM_PAINT。 }
procedure Case_A3_RealDrag;
{$IFDEF LCLWin32}
var
  V: TTyScrollBar;
  i, y0: Integer;
  before, after: TBitmap;
  barPaints, boxPaints: Integer;
{$ENDIF}
begin
  Say('[A3r] 真鼠标拖滑块(mouse_event)');
  {$IFDEF LCLWin32}
  V := BarOf(Box, sbVertical);
  if (V = nil) or not V.Visible then
  begin
    Check('有垂直条', False);
    Exit;
  end;
  Box.ScrollTo(0, 0);
  Settle(120);
  before := GrabControl(Box);
  try
    SavePng(before, 'a3-before-drag');
  finally
    before.Free;
  end;

  { 拇指在轨道顶部;抓它、往下拖 10 次、松开 —— 全部经 WM_LBUTTONDOWN /
    WM_MOUSEMOVE / WM_LBUTTONUP 走真 WndProc,和真手的唯一差别是消息由谁投递。 }
  ResetHooks;
  Box.ResetCounts;
  y0 := Box.ScrollY;
  MouseDownAt(V, V.Width div 2, V.Height div 6);
  for i := 1 to 10 do
    MouseMoveAt(V, V.Width div 2, V.Height div 6 + i * 6);
  MouseUpAt(V, V.Width div 2, V.Height div 6 + 10 * 6);
  Settle(120);
  boxPaints := HookPaints(HookBox);
  barPaints := HookPaints(HookVBar);
  Say(Format('     消息级拖动 10 步:ScrollY %d -> %d,box WM_PAINT=%d vbar WM_PAINT=%d 对齐=%d',
    [y0, Box.ScrollY, boxPaints, barPaints, Box.Aligns]));
  Check('走真 WndProc 的拖动确实滚动了内容', Box.ScrollY > y0,
    Format('%d -> %d', [y0, Box.ScrollY]));
  Check('真拖动每步至多两次窗口重绘(条 + 框)',
    boxPaints + barPaints <= 2 * 10 + 4,
    Format('box=%d bar=%d', [boxPaints, barPaints]));
  after := GrabControl(Box);
  try
    SavePng(after, 'a3-after-drag');
  finally
    after.Free;
  end;
  {$ELSE}
  Say('     非 Win32,跳过');
  {$ENDIF}
end;

{ ---------------------------------------------------------------- A5 ------ }
{ TTyScrollContent 今天能不能建、能不能滚(Antek 在某个提交上说它不可用)。 }
procedure Case_A5_ScrollContent;
var
  b: TCountBox;
  vp: TTyScrollContent;
  kid: TTyPanel;
  V: TTyScrollBar;
  y0: Integer;
begin
  Say('[A5] TTyScrollContent 视口:能建、能量、能滚');
  b := TCountBox.Create(Form);
  b.Parent := Form;
  b.SetBounds(20, 330, 300, 70);
  vp := TTyScrollContent.Create(b);
  vp.Parent := b;
  kid := TTyPanel.Create(vp);
  kid.Parent := vp;
  kid.SetBounds(0, 0, 120, 600);
  Pump(6);
  b.UpdateScrollRange;
  Pump(4);

  V := BarOf(b, sbVertical);
  Say(Format('     content=%dx%d  viewport=%s  vbar=%s',
    [b.ContentWidth, b.ContentHeight, R2S(vp.BoundsRect),
     IfThen(V = nil, '<nil>', R2S(V.BoundsRect))]));
  Check('视口里的内容也把条顶出来了', (V <> nil) and V.Visible);
  Check('内容高度从视口的子控件量到', b.ContentHeight >= 600,
    Format('实际 %d', [b.ContentHeight]));
  if (V = nil) or not V.Visible then Exit;

  y0 := kid.Top;
  V.Position := V.Max div 2;
  Pump(4);
  Say(Format('     滚到一半:ScrollY=%d  kid.Top %d -> %d', [b.ScrollY, y0, kid.Top]));
  Check('视口里的内容真的被滚了', kid.Top < y0, Format('%d -> %d', [y0, kid.Top]));
  Check('偏移跟上了条', b.ScrollY = V.Position,
    Format('%d vs %d', [b.ScrollY, V.Position]));
  { 视口存在时,滚动**不该**去搬条 —— 搬的是视口里的子控件。 }
  Check('有视口时条仍贴在原处',
    (V.Left = vp.Left + vp.Width) and (V.Top = vp.Top),
    Format('vbar=%s viewport=%s', [R2S(V.BoundsRect), R2S(vp.BoundsRect)]));
end;

{ ============================================================== main ====== }
begin
  OutDir := ExtractFilePath(ParamStr(0));
  if ParamCount >= 1 then OutDir := ParamStr(1);
  ForceDirectories(OutDir);

  Application.Initialize;
  BuildScene;

  AssignFile(LogF, IncludeTrailingPathDelimiter(OutDir) + 'cluster.log');
  Rewrite(LogF);
  LogOpen := True;
  Say('=== scrollcluster (论坛 #12/#15) ===');
  Say('输出目录: ' + OutDir);
  Say('');

  HookBox := InstallHook(Box, 'box');
  HookWide := InstallHook(Wide, 'wide');
  {$IFDEF LCLWin32}
  SaveCursor;
  {$ENDIF}
  try
    try
      HookVBar := InstallHook(BarOf(Box, sbVertical), 'vbar');
      Case_Env;                 Say('');
      AlignFloor := AlignFloorPerChildMove;
      Say(Format('[floor] 本机 LCL 上移动一个子控件 = %d 轮 ControlsAligned', [AlignFloor]));
      Say('');
      Case_A1_GutterOwnership;  Say('');
      Case_A2_FirstWheelTick;   Say('');
      Case_A3_PaintStorm;       Say('');
      Case_A4_ContentHops;      Say('');
      Case_A4b_AlignedRows;     Say('');
      Case_A4c_AlignedInViewport; Say('');
      Case_A6_AnchoredInViewport; Say('');
      Case_A7_ViewportChildSizing; Say('');
      Case_A3_RealDrag;         Say('');
      Case_A5_ScrollContent;    Say('');
    except
      on E: Exception do
      begin
        Inc(Failures);
        Say('  EXCEPTION  ' + E.ClassName + ': ' + E.Message);
      end;
    end;
  finally
    {$IFDEF LCLWin32}
    RestoreCursor;
    {$ENDIF}
  end;

  Say(Format('=== %d 项检查,%d 项失败 ===', [Checks, Failures]));
  Say(HookReport);
  if LogOpen then CloseFile(LogF);
  Form.Hide;
  if Failures > 0 then Halt(1);
end.
