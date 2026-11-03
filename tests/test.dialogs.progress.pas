unit test.dialogs.progress;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, fpcunit, testregistry,
  tyControls.ProgressBar, tyControls.Button, tyControls.StrConsts, tyControls.Dialogs.Progress;

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
    procedure TestCloseKeepsCancelled;
    { #179 }
    procedure TestThePropertiesReachAnOpenWindow;
    procedure TestTheTitleBarCloseIsACancel;
    procedure TestCancelableChangedAfterTheFirstShow;
    procedure TestFillRectGeometry;
  end;

  { LCL-parity events forward onto the modeless progress form via BuildForm (NO Show). }
  TProgressEventForwardTest = class(TTestCase)
  private
    FSender: TObject;
    procedure HandleShow(Sender: TObject);
    procedure HandleClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure HandleCanClose(Sender: TObject; var CanClose: Boolean);
  published
    procedure TestProgressForwardsEvents;
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

procedure TProgressLogicTest.TestCloseKeepsCancelled;
var dlg: TTyProgressDialog;
begin
  dlg := TTyProgressDialog.Create(nil);
  try
    { #179: the loop that ends with Close reads Cancelled afterwards; Show starts afresh. }
    dlg.DoCancel;
    AssertTrue('cancelled', dlg.Cancelled);
    dlg.BuildForm;
    dlg.Close;
    AssertTrue('Close keeps it', dlg.Cancelled);
  finally dlg.Free; end;
end;

procedure TProgressLogicTest.TestThePropertiesReachAnOpenWindow;
var
  dlg: TTyProgressDialog;
  frm: TTyProgressForm;
begin
  dlg := TTyProgressDialog.Create(nil);
  try
    frm := dlg.BuildForm;
    dlg.Caption := 'Copying';
    AssertEquals('Caption', 'Copying', frm.Caption);
    dlg.Text := 'file.txt';
    AssertEquals('Text', 'file.txt', frm.StatusLabel.Caption);
    dlg.Max := 200;
    AssertEquals('Max', 200, frm.Bar.Max);
    dlg.Position := 150;
    AssertEquals('Position', 150, frm.Bar.Position);
    dlg.Position := 999;
    AssertEquals('Position is clamped to Max', 200, dlg.Position);
    AssertEquals('on the bar too', 200, frm.Bar.Position);
    dlg.Min := 160;
    dlg.Max := 180;
    AssertEquals('a narrower range clamps it', 180, dlg.Position);
    AssertEquals('Min', 160, frm.Bar.Min);
  finally dlg.Free; end;
end;

procedure TProgressLogicTest.TestTheTitleBarCloseIsACancel;
var
  dlg: TTyProgressDialog;
  frm: TTyProgressForm;
begin
  dlg := TTyProgressDialog.Create(nil);
  try
    dlg.Cancelable := True;
    dlg.OnCancel := @HandleCancel;
    frm := dlg.BuildForm;
    FCancelFired := False;
    frm.Close;   // what the title bar's X does
    AssertTrue('the X cancels', dlg.Cancelled);
    AssertTrue('and fires OnCancel', FCancelFired);
    AssertFalse('the window waits for the application to close it', frm.CloseQuery);
  finally dlg.Free; end;
end;

procedure TProgressLogicTest.TestCancelableChangedAfterTheFirstShow;
var
  dlg: TTyProgressDialog;
  frm: TTyProgressForm;
  btn: TTyButton;
  i: Integer;
begin
  dlg := TTyProgressDialog.Create(nil);
  try
    frm := dlg.BuildForm;
    btn := nil;
    for i := 0 to frm.ButtonCount - 1 do
      if frm.Buttons[i].Caption = rsMsgBtnCancel then btn := frm.Buttons[i];
    AssertTrue('not cancelable: no Cancel button', (btn = nil) or not btn.Visible);
    AssertTrue('and no X', not (biSystemMenu in frm.BorderIcons));
    dlg.Cancelable := True;
    btn := nil;
    for i := 0 to frm.ButtonCount - 1 do
      if frm.Buttons[i].Caption = rsMsgBtnCancel then btn := frm.Buttons[i];
    AssertTrue('made cancelable later: the Cancel button shows', (btn <> nil) and btn.Visible);
    AssertTrue('and so does the X', biSystemMenu in frm.BorderIcons);
    dlg.Cancelable := False;
    AssertFalse('and both go again', btn.Visible or (biSystemMenu in frm.BorderIcons));
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

{ TProgressEventForwardTest }

procedure TProgressEventForwardTest.HandleShow(Sender: TObject);
begin
  FSender := Sender;
end;

procedure TProgressEventForwardTest.HandleClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  FSender := Sender;
end;

procedure TProgressEventForwardTest.HandleCanClose(Sender: TObject; var CanClose: Boolean);
begin
  FSender := Sender;
end;

procedure TProgressEventForwardTest.TestProgressForwardsEvents;
var dlg: TTyProgressDialog; frm: TTyProgressForm;
begin
  dlg := TTyProgressDialog.Create(nil);
  try
    dlg.OnShow := @HandleShow;
    dlg.OnClose := @HandleClose;
    dlg.OnCanClose := @HandleCanClose;
    frm := dlg.BuildForm;   // build + forward, NO Show
    { #179: the handlers get the dialog as Sender, not the form inside it; and the dialog's
      own Close reaches OnCanClose and OnClose. }
    FSender := nil;
    frm.OnShow(frm);
    AssertSame('OnShow reaches the handler with the dialog', TObject(dlg), FSender);
    FSender := nil;
    dlg.Close;
    AssertSame('Close reaches OnCanClose and OnClose, with the dialog', TObject(dlg), FSender);
  finally dlg.Free; end;
end;

initialization
  RegisterTest(TProgressLogicTest);
  RegisterTest(TProgressEventForwardTest);
end.
