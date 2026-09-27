unit tyControls.ToolWindows.DesignRules;
{$mode objfpc}{$H+}

{ 设计器里工具窗口的组件编辑器(designtime/tyControls.Design.CompEditors)的判定和模型那一半
  (spec §11)。放在运行时包里:设计期包不进测试构建,判定写在那边就一条都测不到。组件编辑器
  只做 IDE 那一半 —— 起名、Hook.PersistentAdded、AddUndoAction、Modified、选中 —— 不自己再判。 }

interface

uses
  Classes, Controls,
  tyControls.ToolWindows, tyControls.ToolWindows.Manager;

type
  TTyToolWindowBarArray = array of TTyToolWindowBar;

{ AComponent 在 frame 实例里 —— IDE 的 TComponentEditor.IsInInlined 就是这一句
  (componenteditors.pas:698-701)。往 frame 实例里加组件不行(:178-183),继承来的控件也不能换父
  (customformeditor.pp:1667-1669)。 }
function TyToolWindowInInlined(AComponent: TComponent): Boolean;

{ 「新建工具窗口」:栏在、不在 frame 实例里、不在加载 / 释放中。子孙窗体里往继承来的栏加窗口
  可以(spec §11)。 }
function TyToolWindowDesignCanAddWindow(ABar: TTyToolWindowBar): Boolean;

{ 「添加操作区」:窗口还没有操作区(Actions = nil)、不在 frame 实例里、不在加载 / 释放中
  (同 CanAddWindow)。继承来的窗口可以加。 }
function TyToolWindowDesignCanAddActions(AWindow: TTyToolWindow): Boolean;

{ 「移到另一侧栏」的目标:窗口在侧栏里、不是继承来的(csAncestor)、不在 frame 实例里,所在栏
  有 manager,manager 下另一侧(左 ↔ 右)有可用栏(UsableBar)、那条栏也不在 frame 实例里,
  且 CanMoveWindow 答 True(它管本栏冲突、同一窗体、加载 / 释放中);否则 nil。 }
function TyToolWindowDesignOtherSide(AWindow: TTyToolWindow): TTyToolWindowBar;

{ 执行「移到另一侧栏」:目标为 nil、manager 不是 TTyToolWindowManager 答 False;否则
  MoveWindow(设计期同步、不问 OnCanMoveWindow、不发事件、自己通知设计器,spec §9.9)。
  Bar.Manager 是基类类型,这里转型(spec §2)。 }
function TyToolWindowDesignMoveToOtherSide(AWindow: TTyToolWindow): Boolean;

{ 「移回栏里 ▸」的候选:只有孤儿(Parent 不是栏)才有;窗口不是继承来的、不在 frame 实例里、
  有 Owner;候选 = AWindow.Owner 拥有的每一条栏(按 Owner.Components 顺序),去掉在加载 /
  释放中的。frame 实例里的栏归 frame 实例拥有,本来就不在候选里。侧栏、底栏都算:孤儿没有
  「原来那一类」。 }
function TyToolWindowDesignReturnTargets(AWindow: TTyToolWindow): TTyToolWindowBarArray;

{ 执行「移回栏里」:ABar 必须在候选里,否则答 False、什么都不改。Parent := ABar —— 设计期
  直接改 Parent 不走 CommitCrossMove(BooksDirectMove 排除设计期),注册即成为当前页。
  设计器由调用方通知(Modified)。 }
function TyToolWindowDesignReturnToBar(AWindow: TTyToolWindow; ABar: TTyToolWindowBar): Boolean;

implementation

const
  Busy = [csLoading, csDestroying];

function TyToolWindowInInlined(AComponent: TComponent): Boolean;
begin
  Result := (AComponent <> nil) and (AComponent.Owner <> nil)
    and (csInline in AComponent.Owner.ComponentState);
end;

function TyToolWindowDesignCanAddWindow(ABar: TTyToolWindowBar): Boolean;
begin
  Result := (ABar <> nil) and not TyToolWindowInInlined(ABar)
    and (Busy * ABar.ComponentState = []);
end;

function TyToolWindowDesignCanAddActions(AWindow: TTyToolWindow): Boolean;
begin
  Result := (AWindow <> nil) and (AWindow.Actions = nil)
    and not TyToolWindowInInlined(AWindow)
    and (Busy * AWindow.ComponentState = []);
end;

function TyToolWindowDesignOtherSide(AWindow: TTyToolWindow): TTyToolWindowBar;
var
  src: TTyToolWindowBar;
  side: TTyToolWindowPlacement;
begin
  Result := nil;
  if (AWindow = nil) or (csAncestor in AWindow.ComponentState)
     or TyToolWindowInInlined(AWindow) then Exit;
  src := AWindow.Bar;
  if (src = nil) or (src.Manager = nil) then Exit;
  case src.Placement of
    twpLeft: side := twpRight;
    twpRight: side := twpLeft;
  else
    Exit;                          { 底栏窗口不跨栏 }
  end;
  Result := src.Manager.UsableBar(side);
  { 目标栏在 frame 实例里(它挂在窗体的 manager 上):往 frame 实例里放组件不行
    (componenteditors.pas:178-183),CanMoveWindow 看不出这一条。 }
  if (Result <> nil) and TyToolWindowInInlined(Result) then Exit(nil);
  { 本栏冲突、不在同一窗体、加载 / 释放中:CanMoveWindow 一处答。设计期它不问事件。 }
  if (Result <> nil) and not src.Manager.CanMoveWindow(AWindow, Result) then Result := nil;
end;

function TyToolWindowDesignMoveToOtherSide(AWindow: TTyToolWindow): Boolean;
var
  target: TTyToolWindowBar;
begin
  Result := False;
  target := TyToolWindowDesignOtherSide(AWindow);
  if target = nil then Exit;
  if not (AWindow.Bar.Manager is TTyToolWindowManager) then Exit;
  Result := TTyToolWindowManager(AWindow.Bar.Manager).MoveWindow(AWindow, target);
end;

function TyToolWindowDesignReturnTargets(AWindow: TTyToolWindow): TTyToolWindowBarArray;
var
  own: TComponent;
  c: TComponent;
  i: Integer;
begin
  Result := nil;
  if (AWindow = nil) or (AWindow.Bar <> nil) then Exit;       { 只有孤儿 }
  if (csAncestor in AWindow.ComponentState) or TyToolWindowInInlined(AWindow) then Exit;
  own := AWindow.Owner;
  if own = nil then Exit;
  for i := 0 to own.ComponentCount - 1 do
  begin
    c := own.Components[i];
    if not (c is TTyToolWindowBar) then Continue;
    { frame 实例里的栏不用另外排除:它们归 frame 实例拥有,不在 own.Components 里;own 本身是
      frame 实例时孤儿自己就在里面,上面已经返回。 }
    if Busy * c.ComponentState <> [] then Continue;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := TTyToolWindowBar(c);
  end;
end;

function TyToolWindowDesignReturnToBar(AWindow: TTyToolWindow; ABar: TTyToolWindowBar): Boolean;
var
  targets: TTyToolWindowBarArray;
  i: Integer;
begin
  Result := False;
  if ABar = nil then Exit;
  targets := TyToolWindowDesignReturnTargets(AWindow);
  for i := 0 to High(targets) do
    if targets[i] = ABar then
    begin
      AWindow.Parent := ABar;
      Exit(True);
    end;
end;

end.
