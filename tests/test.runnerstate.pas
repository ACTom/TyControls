unit test.runnerstate;

{ The state every test process starts in. tytests.lpr sets it up before the first test runs, so
  that a suite run on its own sees the same process a suite run in the middle of the full run
  sees: the widgetset is initialised, the screen is the 96-PPI desktop the expectations are
  written for, and the machine's system-font fallback and first day of the week are pinned.

  A suite that only passed because an earlier suite had initialised the widgetset (a handle
  created in a process nobody initialised fails with "Failed to create win32 control", 1407)
  is a suite whose result depends on where it runs. These two tests are the contract: if the
  runner stops setting any of it up, they go red here instead of somewhere far away. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Forms, fpcunit, testregistry,
  tyControls.Controller, tyControls.Painter, tyControls.Calendar;

type
  TRunnerStateTest = class(TTestCase)
  published
    procedure TestAHandleCanBeCreatedWithoutAnyoneInitialising;
    procedure TestTheFixedStateHolds;
  end;

implementation

{ Deliberately no NeedWidgetSet here: the point is that nothing in the test asks for it. }
procedure TRunnerStateTest.TestAHandleCanBeCreatedWithoutAnyoneInitialising;
var
  f: TForm;
begin
  f := TForm.CreateNew(nil);
  try
    f.HandleNeeded;
    AssertTrue('a form gets a handle in a process no test initialised', f.HandleAllocated);
  finally
    f.Free;
  end;
end;

procedure TRunnerStateTest.TestTheFixedStateHolds;
begin
  AssertEquals('ScreenInfo.PixelsPerInchX', 96, ScreenInfo.PixelsPerInchX);
  AssertEquals('ScreenInfo.PixelsPerInchY', 96, ScreenInfo.PixelsPerInchY);
  AssertFalse('TyAutoSystemFontFallback', TyAutoSystemFontFallback);
  AssertEquals('TyFallbackFontName', '', TyFallbackFontName);
  AssertTrue('TyLocaleFirstDayOfWeek is wdSunday', TyLocaleFirstDayOfWeek = wdSunday);
end;

initialization
  RegisterTest(TRunnerStateTest);

end.
