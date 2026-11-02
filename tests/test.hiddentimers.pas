unit test.hiddentimers;

{$mode objfpc}{$H+}

{ #149: the animated controls run their timer only while they can be seen, and never in the
  form designer. Hidden, in a hidden panel, taken off their parent or designed, the next
  tick stops the timer; shown again, they are painted, and the paint starts it again.
  TTyAnalogClock.Time is saved only for a stopped clock. }

interface

uses
  Classes, SysUtils, Controls, Forms, ExtCtrls, fpcunit, testregistry,
  tyControls.ActivityIndicator, tyControls.GearActivityIndicator, tyControls.AnalogClock,
  tyControls.ActivityBar;

type
  THiddenTimersTest = class(TTestCase)
  private
    FForm: TForm;
    FPanel: TPanel;
    function TimerOf(C: TControl): TTimer;
    procedure Tick(C: TControl);
    procedure ShowAndPaint(C: TControl);
    procedure CheckStopsAndStarts(C: TControl);
    function FormText: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestActivityIndicator;
    procedure TestGearActivityIndicator;
    procedure TestAnalogClock;
    procedure TestActivityBar;
    procedure TestARunningClockSavesNoTime;
  end;

implementation

type
  TCrack = class(TControl);

var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

procedure THiddenTimersTest.SetUp;
begin
  NeedWidgetSet;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 300, 300);
  FPanel := TPanel.Create(FForm);
  FPanel.Name := 'Panel1';
  FPanel.Parent := FForm;
  FPanel.SetBounds(0, 0, 200, 200);
  FForm.Show;
end;

procedure THiddenTimersTest.TearDown;
begin
  FreeAndNil(FForm);
end;

function THiddenTimersTest.TimerOf(C: TControl): TTimer;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to C.ComponentCount - 1 do
    if C.Components[i] is TTimer then Exit(TTimer(C.Components[i]));
end;

procedure THiddenTimersTest.Tick(C: TControl);
begin
  TimerOf(C).OnTimer(TimerOf(C));
end;

procedure THiddenTimersTest.ShowAndPaint(C: TControl);
begin
  C.Repaint;
  Application.ProcessMessages;
end;

procedure THiddenTimersTest.CheckStopsAndStarts(C: TControl);
var
  n: string;
begin
  n := C.ClassName + ': ';
  C.Parent := FPanel;
  C.SetBounds(10, 10, 60, 60);
  ShowAndPaint(C);
  AssertNotNull(n + 'setup: painted, it has a timer', TimerOf(C));
  AssertTrue(n + 'setup: and it runs', TimerOf(C).Enabled);

  FPanel.Visible := False;
  Tick(C);
  AssertFalse(n + 'in a hidden panel the tick stops it', TimerOf(C).Enabled);
  FPanel.Visible := True;
  ShowAndPaint(C);
  AssertTrue(n + 'shown again, painting starts it', TimerOf(C).Enabled);

  C.Visible := False;
  Tick(C);
  AssertFalse(n + 'hidden itself, the tick stops it', TimerOf(C).Enabled);
  C.Visible := True;
  ShowAndPaint(C);
  AssertTrue(n + 'and shown, it runs again', TimerOf(C).Enabled);

  C.Parent := nil;
  Tick(C);
  AssertFalse(n + 'off its parent, the tick stops it', TimerOf(C).Enabled);

  C.Parent := FPanel;
  ShowAndPaint(C);
  AssertTrue(n + 'back on its parent, it runs', TimerOf(C).Enabled);
  TCrack(C).SetDesigning(True);
  Tick(C);
  AssertFalse(n + 'in the designer, the tick stops it', TimerOf(C).Enabled);
  ShowAndPaint(C);
  AssertFalse(n + 'and painting there does not start it', TimerOf(C).Enabled);
end;

procedure THiddenTimersTest.TestActivityIndicator;
begin
  CheckStopsAndStarts(TTyActivityIndicator.Create(FForm));
end;

procedure THiddenTimersTest.TestGearActivityIndicator;
begin
  CheckStopsAndStarts(TTyGearActivityIndicator.Create(FForm));
end;

procedure THiddenTimersTest.TestAnalogClock;
begin
  CheckStopsAndStarts(TTyAnalogClock.Create(FForm));
end;

procedure THiddenTimersTest.TestActivityBar;
begin
  CheckStopsAndStarts(TTyActivityBar.Create(FForm));
end;

function THiddenTimersTest.FormText: string;
var
  ms: TMemoryStream;
  ts: TStringStream;
begin
  ms := TMemoryStream.Create;
  ts := TStringStream.Create('');
  try
    ms.WriteComponent(FForm);
    ms.Position := 0;
    ObjectBinaryToText(ms, ts);
    Result := ts.DataString;
  finally
    ts.Free;
    ms.Free;
  end;
end;

procedure THiddenTimersTest.TestARunningClockSavesNoTime;
var
  c: TTyAnalogClock;
begin
  c := TTyAnalogClock.Create(FForm);
  c.Name := 'Clock1';
  c.Parent := FForm;
  AssertEquals('a running clock: no Time in the form', 0, Pos('Time =', FormText));
  c.Running := False;
  c.Time := EncodeTime(10, 9, 0, 0);
  AssertTrue('a stopped clock keeps the time it shows', Pos('Time =', FormText) > 0);
end;

initialization
  RegisterTest(THiddenTimersTest);
end.
