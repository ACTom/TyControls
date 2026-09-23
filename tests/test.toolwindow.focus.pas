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
  Classes, SysUtils, Controls, Forms, fpcunit, testregistry,
  tyControls.Controller, tyControls.Edit, tyControls.ToolWindows;

type
  TTyToolWindowFocusTests = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FBar: TTyToolWindowBar;
    FWin, FWin2: TTyToolWindow;
    FEdit, FEdit2, FOutside: TTyEdit;
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
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCollapsingMovesFocusOutOfTheWindow;
    procedure TestSwitchingMovesFocusOnlyIfItWasInside;
    procedure TestExternalVisibleTrueActivatesThroughTheBar;
    procedure TestHidingTheActivePageByVisibleMovesFocusOutToo;
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
  AssertSame('焦点原来在旧页里:落到新页第一个可聚焦控件', FEdit2, FForm.ActiveControl);
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

initialization
  RegisterTest(TTyToolWindowFocusTests);
end.
