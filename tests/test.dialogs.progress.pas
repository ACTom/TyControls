unit test.dialogs.progress;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, fpcunit, testregistry,
  tyControls.ProgressBar, tyControls.Dialogs.Progress;

type
  TProgressLogicTest = class(TTestCase)
  private
    FCancelFired: Boolean;
    procedure HandleCancel(Sender: TObject);
  published
    procedure TestSetProgressClamps;
    procedure TestClampNonZeroMin;
    procedure TestStepAccumulates;
    procedure TestDoCancelSetsFlagAndFires;
    procedure TestCloseResetsCancelled;
    procedure TestFillRectGeometry;
  end;

implementation

procedure TProgressLogicTest.HandleCancel(Sender: TObject);
begin
  FCancelFired := True;
end;

procedure TProgressLogicTest.TestSetProgressClamps;
var dlg: TTyProgressDialog;
begin
  dlg := TTyProgressDialog.Create(nil);
  try
    dlg.Min := 0; dlg.Max := 100;
    dlg.SetProgress(150);
    AssertEquals('clamp high', 100, dlg.Position);
    dlg.SetProgress(-20);
    AssertEquals('clamp low', 0, dlg.Position);
    dlg.SetProgress(42);
    AssertEquals('in range', 42, dlg.Position);
  finally dlg.Free; end;
end;

procedure TProgressLogicTest.TestClampNonZeroMin;
var dlg: TTyProgressDialog;
begin
  dlg := TTyProgressDialog.Create(nil);
  try
    dlg.Min := 50; dlg.Max := 150;
    dlg.SetProgress(10);
    AssertEquals('clamp to non-zero min', 50, dlg.Position);
    dlg.SetProgress(200);
    AssertEquals('clamp to max', 150, dlg.Position);
    dlg.SetProgress(100);
    AssertEquals('in range', 100, dlg.Position);
  finally dlg.Free; end;
end;

procedure TProgressLogicTest.TestStepAccumulates;
var dlg: TTyProgressDialog;
begin
  dlg := TTyProgressDialog.Create(nil);
  try
    dlg.Min := 0; dlg.Max := 100;
    dlg.SetProgress(10);
    dlg.Step;          // +1
    dlg.Step(4);       // +4
    AssertEquals('accumulated', 15, dlg.Position);
  finally dlg.Free; end;
end;

procedure TProgressLogicTest.TestDoCancelSetsFlagAndFires;
var dlg: TTyProgressDialog;
begin
  FCancelFired := False;
  dlg := TTyProgressDialog.Create(nil);
  try
    dlg.OnCancel := @HandleCancel;
    AssertFalse('not cancelled yet', dlg.Cancelled);
    dlg.DoCancel;
    AssertTrue('cancelled flag', dlg.Cancelled);
    AssertTrue('OnCancel fired', FCancelFired);
  finally dlg.Free; end;
end;

procedure TProgressLogicTest.TestCloseResetsCancelled;
var dlg: TTyProgressDialog;
begin
  dlg := TTyProgressDialog.Create(nil);
  try
    dlg.DoCancel;
    AssertTrue('cancelled', dlg.Cancelled);
    dlg.Close;
    AssertFalse('reset by Close', dlg.Cancelled);
  finally dlg.Free; end;
end;

procedure TProgressLogicTest.TestFillRectGeometry;
var track: TRect;
begin
  track := Rect(0, 0, 100, 10);
  AssertEquals('empty at min', 0, TyProgressFillRect(track, 0, 100, 0).Right);
  AssertEquals('full at max', 100, TyProgressFillRect(track, 0, 100, 100).Right);
  AssertEquals('half at mid', 50, TyProgressFillRect(track, 0, 100, 50).Right);
end;

initialization
  RegisterTest(TProgressLogicTest);
end.
