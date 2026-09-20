unit test.toolwindow.geometry;
{$mode objfpc}{$H+}
interface
uses
  Classes, fpcunit, testregistry,
  { 只为它的 initialization —— 四个 RegisterClass 就发生在那里,别当成没用的 uses 删掉。 }
  tyControls.ToolWindows;

type
  TTyToolWindowGeometryTests = class(TTestCase)
  published
    procedure TestEveryClassIsRegisteredForStreaming;
  end;

implementation

procedure TTyToolWindowGeometryTests.TestEveryClassIsRegisteredForStreaming;
begin
  { 这一条守的正是本任务交付的东西:漏掉任何一句 RegisterClass,读 .lfm 时按类名
    就找不到类。 }
  AssertNotNull('TTyToolWindow 必须注册', GetClass('TTyToolWindow'));
  AssertNotNull('TTyToolWindowActions 必须注册', GetClass('TTyToolWindowActions'));
  AssertNotNull('TTyToolWindowBar 必须注册', GetClass('TTyToolWindowBar'));
  AssertNotNull('TTyToolWindowManager 必须注册', GetClass('TTyToolWindowManager'));
end;

initialization
  RegisterTest(TTyToolWindowGeometryTests);
end.
