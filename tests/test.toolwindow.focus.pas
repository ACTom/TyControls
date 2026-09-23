unit test.toolwindow.focus;
{$mode objfpc}{$H+}

{ 工具窗口栏的可见性与焦点(spec §3.3 / §5.1 第 5 步 / §5.3),要**真句柄**:CanFocus 要求
  整条父链 Visible,SetFocus 要句柄。夹具照 test.focus.tabstop 的 TTyClickFocusTest:

  - 本单元**自带**一个 widgetset 惰性初始化开关(别共用别人的:共用会让单跑和全量给出
    不同的结果 —— 单跑时那个开关从没被别人打开过);
  - 窗体摆到 (-4000, -4000) 再 Visible := True + HandleNeeded;
  - 装一个 Application.OnException 陷阱:消息里抛出的异常没有本测试的帧可退,不接住的话
    LCL 弹模态错误框,console runner 永远卡在那里。 }

interface

uses
  Classes, SysUtils, Types, LCLType, LMessages, Controls, Forms, fpcunit, testregistry,
  tyControls.Controller, tyControls.Edit, tyControls.Button, tyControls.ToolWindows,
  tyControls.ToolWindows.Layout, test.toolwindow.window;

type
  TTyToolWindowFocusTests = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FBar: TTyToolWindowBar;
    FWin, FWin2: TTyToolWindow;
    FEdit, FEdit2, FOutside: TTyEdit;
    FButton2: TTyButton;
    { Tab 顺序在栏**前面**的一个编辑框。没有它,「焦点去了哪」分不出是栏的 SelectNext
      挪的还是平台自己挪的:Win32 上藏掉焦点所在的窗口,LCL 把 ActiveControl 置 nil
      (customform.inc:901-910)之后,焦点并不停在窗体本身,而是落到窗体里 Tab 顺序第一个
      可聚焦的控件 —— 只有一个栏外控件时,两条路落在同一个控件上,SelectNext 删掉也绿。 }
    FBefore: TTyEdit;
    FPrevOnException: TExceptionEvent;
    FTrapped: string;
    procedure TrapException(Sender: TObject; E: Exception);
    procedure AssertNothingRaised(const AWhere: string);
    function NewEditIn(AParent: TWinControl; ATop: Integer): TTyEdit;
    { 按住第一个图标拖过阈值,捕获是真的抓着的。 }
    procedure StartCapturedDrag;
    { 抽 200 ms 消息:窗体的 OnResize 处理器是排队发的。 }
    procedure Pump;
    { 窗体上再放一条底栏,两个探针窗口(Problems、Output),当前页是后一个;抽过消息,
      对齐引擎真的摆过。 }
    function NewBottomBar(out AFirst, AActive: TProbeWindow;
      AParent: TWinControl = nil): TTyToolWindowBar;
    { 当前页上窗口 AIndex 的标签中心(当前页客户区坐标)。 }
    function BottomTabCentre(AActive: TProbeWindow; AIndex: Integer): TPoint;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCollapsingMovesFocusOutOfTheWindow;
    procedure TestSwitchingMovesFocusOnlyIfItWasInside;
    procedure TestExternalVisibleTrueActivatesThroughTheBar;
    procedure TestHidingTheActivePageByVisibleMovesFocusOutToo;
    { 拖动期间的捕获计时器(spec §9.2 / §9.7)与真实的指针查询,都要真句柄。 }
    procedure TestTheCaptureTimerCancelsWhenCaptureIsLost;
    procedure TestASecondPressFreesTheCaptureTimer;
    procedure TestPointerInClientAnswersWithAHandle;
    { spec §6.2:窗体缩窄后跟着收窄、放宽后回来,ExpandedSize 不变。窗体的 OnResize 处理器
      是 QueueAsyncCall 推迟发的,而无头时 AutoSizeDelayed 连 Resize 都不走 —— 要真句柄。 }
    procedure TestNarrowingFollowsTheFormAndNeverWritesBack;
    { 底栏标签行(spec §3.6):真实的按下消息走 WndProc → WMLButtonDown(抓捕获要句柄)。 }
    procedure TestTheBottomTabRowNeverStartsAnLclDrag;
    { spec §6.4:最大化的底栏跟着窗体变高(窗体的 OnResize 排队发,要真句柄)。 }
    procedure TestAMaximizedBottomBarFollowsTheForm;
  end;

implementation

var
  ToolWindowWidgetSetReady: Boolean = False;

procedure NeedToolWindowWidgetSet;
begin
  if ToolWindowWidgetSetReady then Exit;
  Forms.Application.Initialize;
  ToolWindowWidgetSetReady := True;
end;

procedure TTyToolWindowFocusTests.TrapException(Sender: TObject; E: Exception);
begin
  if FTrapped = '' then
    FTrapped := E.ClassName + ': ' + E.Message;
end;

procedure TTyToolWindowFocusTests.AssertNothingRaised(const AWhere: string);
var
  s: string;
begin
  if FTrapped = '' then Exit;
  s := FTrapped;
  FTrapped := '';
  Fail(AWhere + ' raised on the real message path: ' + s);
end;

function TTyToolWindowFocusTests.NewEditIn(AParent: TWinControl; ATop: Integer): TTyEdit;
begin
  Result := TTyEdit.Create(FForm);
  Result.Parent := AParent;
  Result.SetBounds(8, ATop, 120, 26);
end;

procedure TTyToolWindowFocusTests.SetUp;
begin
  NeedToolWindowWidgetSet;
  FTrapped := '';
  FPrevOnException := Forms.Application.OnException;
  Forms.Application.OnException := @TrapException;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(-4000, -4000, 800, 500);
  FCtl := TTyStyleController.Create(FForm);
  FBefore := NewEditIn(FForm, 8);
  FBefore.Left := 300;
  FBar := TTyToolWindowBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.Controller := FCtl;
  FWin := TTyToolWindow.Create(FForm);
  FWin.Parent := FBar;
  FEdit := NewEditIn(FWin, 40);
  FWin2 := TTyToolWindow.Create(FForm);
  FWin2.Parent := FBar;
  FEdit2 := NewEditIn(FWin2, 40);
  { 第二页带一个操作区,里面一个按钮:TabOrder 0,Tab 顺序在正文前面。切页带焦点进来时
    要落在正文里,不是它上面(spec §5.1 第 5 步)。 }
  FButton2 := TTyButton.Create(FForm);
  FButton2.Parent := FWin2.EnsureActions;
  { 栏外面、Tab 顺序在栏**后面**的可聚焦控件:收起时 SelectNext(栏) 的去处。 }
  FOutside := NewEditIn(FForm, 8);
  FOutside.Left := 500;
  FBar.ActiveWindow := FWin;
  FForm.Visible := True;
  FForm.HandleNeeded;
  AssertTrue('前提:当前页里的编辑框聚焦得上', FEdit.CanFocus);
end;

procedure TTyToolWindowFocusTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  Forms.Application.OnException := FPrevOnException;
end;

procedure TTyToolWindowFocusTests.TestCollapsingMovesFocusOutOfTheWindow;
begin
  FEdit.SetFocus;
  AssertSame('先确认焦点真的在里面', FEdit, FForm.ActiveControl);
  FBar.Collapsed := True;
  AssertNothingRaised('Collapsed := True');
  AssertTrue('焦点不许掉到窗体本身,那样快捷键全失灵',
    (FForm.ActiveControl <> nil) and (FForm.ActiveControl <> FForm));
  AssertFalse('焦点不许留在被藏起来的窗口里', FWin.ContainsControl(FForm.ActiveControl));
  AssertSame('焦点交给 Tab 顺序里栏后面的那一个(SelectNext(栏)),不是平台随手挑的第一个',
    FOutside, FForm.ActiveControl);
end;

procedure TTyToolWindowFocusTests.TestSwitchingMovesFocusOnlyIfItWasInside;
begin
  FEdit.SetFocus;
  AssertSame('前提:焦点在旧页里', FEdit, FForm.ActiveControl);
  FBar.ActiveWindow := FWin2;
  AssertNothingRaised('切页');
  { 删掉 FocusFirst 的话,旧页藏起来之后焦点落到 FBefore(平台挑的第一个)。 }
  AssertTrue('前提:标题行的按钮聚焦得上', FButton2.CanFocus);
  AssertSame('焦点原来在旧页里:落到新页正文里第一个可聚焦控件,不是标题行的按钮',
    FEdit2, FForm.ActiveControl);
  FOutside.SetFocus;
  AssertSame('前提:焦点在栏外', FOutside, FForm.ActiveControl);
  FBar.ActiveWindow := FWin;
  AssertSame('焦点在栏外:切页后一动不动', FOutside, FForm.ActiveControl);
end;

procedure TTyToolWindowFocusTests.TestExternalVisibleTrueActivatesThroughTheBar;
begin
  FBar.Windows[1].Visible := True;
  AssertSame('外部把非当前页设成可见 = 激活它', FBar.Windows[1], FBar.ActiveWindow);
  AssertFalse('并且展开栏', FBar.Collapsed);
  AssertFalse('每条栏同时只显示一页', FBar.Windows[0].Visible);
  FBar.ActiveWindow.Visible := False;
  AssertTrue('把当前页设成不可见 = 收起栏', FBar.Collapsed);
  AssertSame('当前页不变', FBar.Windows[1], FBar.ActiveWindow);
  FBar.ActiveWindow.Visible := True;
  AssertFalse('对收起栏的当前页设 True = 展开', FBar.Collapsed);
  AssertTrue('它显示出来', FBar.ActiveWindow.Visible);
  FBar.Collapsed := True;
  FBar.Windows[0].Visible := True;
  AssertSame('收起着时对别的页设 True:激活它', FBar.Windows[0], FBar.ActiveWindow);
  AssertFalse('并且展开', FBar.Collapsed);
  AssertTrue('显示的是它', FBar.Windows[0].Visible);
  AssertFalse('上一页藏着', FBar.Windows[1].Visible);
end;

procedure TTyToolWindowFocusTests.TestHidingTheActivePageByVisibleMovesFocusOutToo;
begin
  FEdit.SetFocus;
  AssertSame('前提:焦点在当前页里', FEdit, FForm.ActiveControl);
  FWin.Visible := False;
  AssertNothingRaised('Visible := False');
  AssertTrue('对当前页设 False 就是收起', FBar.Collapsed);
  AssertTrue('焦点不许掉到窗体本身', (FForm.ActiveControl <> nil) and
    (FForm.ActiveControl <> FForm));
  AssertFalse('焦点不留在藏起来的窗口里', FWin.ContainsControl(FForm.ActiveControl));
  AssertSame('同一条收起的路:交给栏后面的那一个', FOutside, FForm.ActiveControl);
end;

{ --- 捕获计时器、真实指针 --------------------------------------------------------- }

type
  { 受保护的鼠标入口开出来(本单元的栏是 TTyToolWindowBar 本身,没有探针子类)。 }
  TBarCrack = class(TTyToolWindowBar);

procedure TTyToolWindowFocusTests.StartCapturedDrag;
var
  p: TPoint;
  t0: QWord;
begin
  { 先把窗体显示出来之后排着的激活 / 失活消息抽干:否则下面等计时器时,抽到的是 Application
    的失活(它也取消拖动),分不出是哪条路取消的。 }
  t0 := GetTickCount64;
  while GetTickCount64 - t0 < 300 do
  begin
    Application.ProcessMessages;
    Sleep(10);
  end;
  p := FBar.StripItemRect(0).CenterPoint;
  { 真实的按下由 WMLButtonDown 抓捕获;这里直接调 MouseDown,捕获自己抓。 }
  TBarCrack(FBar).MouseCapture := True;
  TBarCrack(FBar).MouseDown(mbLeft, [ssLeft], p.X, p.Y);
  TBarCrack(FBar).MouseMove([ssLeft], p.X, p.Y + 60);
  AssertTrue('前提:拖起来了', FBar.IsDraggingForTest);
  AssertTrue('前提:捕获确认过,计时器在', FBar.HasCaptureTimerForTest);
end;

procedure TTyToolWindowFocusTests.TestTheCaptureTimerCancelsWhenCaptureIsLost;
var
  t0: QWord;
begin
  StartCapturedDrag;
  { 弹出菜单直接 ReleaseCapture 抢走捕获 —— 只有轮询抓得到。 }
  TBarCrack(FBar).MouseCapture := False;
  AssertTrue('放掉捕获这一下本身不取消(CaptureChanged 从不取消)', FBar.IsDraggingForTest);
  t0 := GetTickCount64;
  while FBar.IsDraggingForTest and (GetTickCount64 - t0 < 3000) do
  begin
    Application.ProcessMessages;
    Sleep(10);
  end;
  AssertNothingRaised('捕获计时器');
  AssertEquals('计时器发现捕获丢了:取消', Ord(twgsCancelled), Ord(FBar.GestureStateForTest));
  AssertFalse('计时器在自己的 OnTimer 里放掉了', FBar.HasCaptureTimerForTest);
end;

procedure TTyToolWindowFocusTests.TestASecondPressFreesTheCaptureTimer;
var
  before: TCursor;
  p: TPoint;
begin
  before := Screen.RealCursor;
  StartCapturedDrag;
  p := FBar.StripItemRect(1).CenterPoint;
  TBarCrack(FBar).MouseDown(mbLeft, [ssLeft], p.X, p.Y);
  AssertFalse('松开丢了,下一次按下:计时器放掉', FBar.HasCaptureTimerForTest);
  AssertEquals('临时光标弹回', Ord(before), Ord(Screen.RealCursor));
  AssertEquals('新记录武装着', Ord(twgsArmed), Ord(FBar.GestureStateForTest));
  TBarCrack(FBar).MouseUp(mbLeft, [], p.X, p.Y);
  TBarCrack(FBar).MouseCapture := False;
end;

procedure TTyToolWindowFocusTests.TestPointerInClientAnswersWithAHandle;
var
  p, q: TPoint;
begin
  AssertTrue('前提:有句柄', FBar.HandleAllocated);
  AssertTrue('有句柄:真实实现答 True', TBarCrack(FBar).PointerInClient(p));
  q := FBar.ScreenToClient(Mouse.CursorPos);
  { 真实指针可能在两次读之间动一下;只要求落在同一个量级上(同一套坐标系)。 }
  AssertTrue('答的是本控件客户区坐标', (Abs(p.X - q.X) < 200) and (Abs(p.Y - q.Y) < 200));
end;

procedure TTyToolWindowFocusTests.Pump;
var
  t0: QWord;
begin
  t0 := GetTickCount64;
  while GetTickCount64 - t0 < 200 do
  begin
    Application.ProcessMessages;
    Sleep(5);
  end;
end;

procedure TTyToolWindowFocusTests.TestNarrowingFollowsTheFormAndNeverWritesBack;
var
  fixed, wide: Integer;
begin
  FBar.ExpandedSize := 400;
  Pump;
  fixed := FBar.StripSizePx + FBar.EdgeSizePx + 2 * FBar.ChromeInsetPx;
  wide := FBar.Width;
  AssertEquals('前提:放得下,按展开尺寸推', fixed + MulDiv(400, FBar.Font.PixelsPerInch, 96), wide);
  FForm.Width := 300;
  Pump;
  AssertNothingRaised('窗体缩窄');
  AssertTrue('前提:窗体客户区比展开尺寸窄、比下限宽', (FForm.ClientWidth < wide)
    and (FForm.ClientWidth - fixed > FBar.ContentMinPx));
  AssertEquals('窗体缩窄:内容收窄到窗体客户区里', FForm.ClientWidth, FBar.Width);
  AssertEquals('收窄不写回', 400, FBar.ExpandedSize);
  FForm.Width := 1400;
  Pump;
  AssertEquals('窗体放宽:回到展开尺寸', wide, FBar.Width);
end;

function TTyToolWindowFocusTests.NewBottomBar(out AFirst, AActive: TProbeWindow;
  AParent: TWinControl): TTyToolWindowBar;
begin
  if AParent = nil then AParent := FForm;
  Result := TTyToolWindowBar.Create(FForm);
  { 先设 Placement 再加窗口:运行时有窗口时侧 ↔ 底被忽略。 }
  Result.Placement := twpBottom;
  Result.Parent := AParent;
  Result.Controller := FCtl;
  Result.ExpandedSize := 220;
  AFirst := TProbeWindow.Create(FForm);
  AFirst.Caption := 'Problems';
  AFirst.Parent := Result;
  AActive := TProbeWindow.Create(FForm);
  AActive.Caption := 'Output';
  AActive.Parent := Result;
  Pump;
  AssertSame('前提:后加的是当前页', AActive, Result.ActiveWindow);
  AssertTrue('前提:当前页有句柄', AActive.HandleAllocated);
end;

function TTyToolWindowFocusTests.BottomTabCentre(AActive: TProbeWindow; AIndex: Integer): TPoint;
var
  g: TTyToolWindowHeaderGeom;
  i: Integer;
begin
  g := AActive.HeaderGeomAt(Rect(0, 0, AActive.ClientWidth, AActive.ClientHeight),
    AActive.Font.PixelsPerInch);
  for i := 0 to High(g.Tabs) do
    if g.Tabs[i].ItemIndex = AIndex then Exit(g.Tabs[i].ItemRect.CenterPoint);
  Fail(Format('窗口 %d 的标签没排上', [AIndex]));
  Result := Point(-1, -1);
end;

procedure TTyToolWindowFocusTests.TestTheBottomTabRowNeverStartsAnLclDrag;
var
  first, w: TProbeWindow;
  c, body: TPoint;

  function Coords(const P: TPoint): PtrInt;
  begin
    Result := PtrInt((P.Y shl 16) or (P.X and $FFFF));
  end;

begin
  NewBottomBar(first, w);
  w.DragMode := dmAutomatic;
  c := BottomTabCentre(w, 1);
  body := Point(100, w.BodyRect.Top + 40);
  AssertTrue('前提:正文那一点在窗口里', body.Y < w.ClientHeight);
  { 指针在正文里:只问指针的话,按在标签行也会起拖。 }
  w.FakePointer := True;
  w.FakePoint := body;
  { 真实的按下消息:LCL 在 WndProc 里、MouseDown 之前调 BeginAutoDrag(control.inc:2284)。 }
  w.SimulatePress(c.X, c.Y);
  w.Perform(LM_LBUTTONUP, 0, Coords(c));
  AssertNothingRaised('标签行上的按下');
  AssertEquals('标签行上按下不起 LCL 拖动', 0, w.AutoDragStarts);
  w.SimulatePress(body.X, body.Y);
  w.Perform(LM_LBUTTONUP, 0, Coords(body));
  AssertNothingRaised('正文里的按下');
  AssertEquals('正文里照常起', 1, w.AutoDragStarts);
end;

procedure TTyToolWindowFocusTests.TestAMaximizedBottomBarFollowsTheForm;
var
  b: TTyToolWindowBar;
  first, w: TProbeWindow;
  host: TBodyChild;
  h: Integer;
begin
  { 底栏单独放在一个 alClient 的宿主里:和夹具的侧栏同在窗体上的话,侧栏的 ParentResized
    会顺手重推同一父控件里的每一条栏(DeriveSiblings),底栏自己跟没跟上就看不出来了。 }
  host := TBodyChild.Create(FForm);
  host.Parent := FForm;
  host.Align := alClient;
  b := NewBottomBar(first, w, host);
  b.Maximized := True;
  Pump;
  AssertNothingRaised('最大化');
  h := b.Height;
  AssertTrue('前提:最大化的高比展开尺寸大', h > 220 + b.EdgeSizePx);
  FForm.Height := FForm.Height + 100;
  Pump;
  AssertNothingRaised('窗体拉高');
  AssertEquals('窗体高 100,最大化的底栏也高 100', h + 100, b.Height);
  AssertEquals('ExpandedSize 不变', 220, b.ExpandedSize);
end;

initialization
  RegisterTest(TTyToolWindowFocusTests);
end.
