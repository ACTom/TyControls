unit test.dialogs.find;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Dialogs, Forms, fpcunit, testregistry,
  tyControls.CheckBox, tyControls.Dialogs.Find;

type
  TFindMapTest = class(TTestCase)
  published
    procedure TestOptionsToChecks;
    procedure TestChecksToOptionsRoundTrip;
    procedure TestBasePreserved;
    procedure TestExhaustiveRoundTrip;
    procedure TestGateFlagsPreserved;
  end;

  TFindWiringTest = class(TTestCase)
  private
    FFired: Boolean;
    FLastOptions: TFindOptions;
    FLastFindText: string;
    procedure HandleFind(Sender: TObject);
  published
    procedure TestFindNextFiresWithActionFlags;
    procedure TestSyncFromPopulatesWidgets;
    procedure TestFindFormShapeNoReplace;
  end;

  TReplaceWiringTest = class(TTestCase)
  private
    FReplaceFired: Boolean;
    FLastOptions: TFindOptions;
    FLastReplaceText: string;
    procedure HandleReplace(Sender: TObject);
  published
    procedure TestReplaceStampsReplaceFlag;
    procedure TestReplaceAllStampsReplaceAllFlag;
    procedure TestReplaceDefaultsHaveReplaceFlags;
    procedure TestSyncFromPopulatesReplaceEdit;
    procedure TestReplaceFormShapeHasReplace;
    procedure TestReusedFormClearsStaleActionFlag;
  end;

  { LCL-parity events (OnShow/OnClose/OnCanClose) forward onto the modeless form.
    BuildForm returns the form without Show, so assert the handlers landed on it. }
  TFindEventForwardTest = class(TTestCase)
  private
    procedure HandleShow(Sender: TObject);
    procedure HandleClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure HandleCanClose(Sender: TObject; var CanClose: Boolean);
  published
    procedure TestFindForwardsEvents;
    procedure TestReplaceInheritsAndForwardsEvents;
  end;

implementation

procedure TFindMapTest.TestOptionsToChecks;
var ch: TTyFindChecks;
begin
  ch := TyFindOptionsToChecks([frMatchCase, frDown]);
  AssertTrue('matchcase', ch.MatchCase);
  AssertFalse('wholeword', ch.WholeWord);
  AssertFalse('searchup (frDown present)', ch.SearchUp);

  ch := TyFindOptionsToChecks([frWholeWord]);   // no frDown -> searching up
  AssertFalse('matchcase', ch.MatchCase);
  AssertTrue('wholeword', ch.WholeWord);
  AssertTrue('searchup (no frDown)', ch.SearchUp);
end;

procedure TFindMapTest.TestChecksToOptionsRoundTrip;
var ch: TTyFindChecks; opts: TFindOptions;
begin
  ch.MatchCase := True; ch.WholeWord := False; ch.SearchUp := False;
  opts := TyChecksToFindOptions(ch, []);
  AssertTrue('frMatchCase', frMatchCase in opts);
  AssertFalse('frWholeWord', frWholeWord in opts);
  AssertTrue('frDown (searchup false)', frDown in opts);

  ch := TyFindOptionsToChecks(opts);
  AssertTrue('rt matchcase', ch.MatchCase);
  AssertFalse('rt wholeword', ch.WholeWord);
  AssertFalse('rt searchup', ch.SearchUp);
end;

procedure TFindMapTest.TestBasePreserved;
var ch: TTyFindChecks; opts: TFindOptions;
begin
  ch.MatchCase := False; ch.WholeWord := True; ch.SearchUp := True;
  // untouched base flags (frReplace, frEntireScope) must survive
  opts := TyChecksToFindOptions(ch, [frReplace, frReplaceAll, frEntireScope, frDown]);
  AssertTrue('frReplace kept', frReplace in opts);
  AssertTrue('frReplaceAll kept', frReplaceAll in opts);
  AssertTrue('frEntireScope kept', frEntireScope in opts);
  AssertTrue('frWholeWord set', frWholeWord in opts);
  AssertFalse('frDown cleared (searchup true)', frDown in opts);
end;

procedure TFindMapTest.TestExhaustiveRoundTrip;
var i: Integer; ch, ch2: TTyFindChecks; opts: TFindOptions;
begin
  for i := 0 to 7 do
  begin
    ch.MatchCase := (i and 1) <> 0;
    ch.WholeWord := (i and 2) <> 0;
    ch.SearchUp  := (i and 4) <> 0;
    opts := TyChecksToFindOptions(ch, []);
    ch2  := TyFindOptionsToChecks(opts);
    AssertTrue('rt ' + IntToStr(i), (ch.MatchCase = ch2.MatchCase)
      and (ch.WholeWord = ch2.WholeWord) and (ch.SearchUp = ch2.SearchUp));
  end;
end;

procedure TFindWiringTest.HandleFind(Sender: TObject);
begin
  FFired := True;
  FLastOptions := (Sender as TTyFindDialog).Options;
  FLastFindText := (Sender as TTyFindDialog).FindText;
end;

procedure TFindWiringTest.TestFindNextFiresWithActionFlags;
var dlg: TTyFindDialog; frm: TTyFindForm;
begin
  FFired := False;
  dlg := TTyFindDialog.Create(nil);
  try
    dlg.OnFind := @HandleFind;
    frm := dlg.BuildForm;                 // builds the form, does NOT Show it
    frm.FindEdit.Text := 'hello';
    frm.MatchCaseCheck.Checked := True;
    frm.SearchUpCheck.Checked := False;   // -> frDown set
    frm.DoFindNext;
    AssertTrue('OnFind fired', FFired);
    AssertEquals('FindText written back', 'hello', FLastFindText);
    AssertTrue('frFindNext stamped', frFindNext in FLastOptions);
    AssertFalse('frReplace cleared', frReplace in FLastOptions);
    AssertFalse('frReplaceAll cleared', frReplaceAll in FLastOptions);
    AssertTrue('frMatchCase from check', frMatchCase in FLastOptions);
    AssertTrue('frDown (searchup off)', frDown in FLastOptions);
  finally dlg.Free; end;
end;

procedure TReplaceWiringTest.HandleReplace(Sender: TObject);
begin
  FReplaceFired := True;
  FLastOptions := (Sender as TTyReplaceDialog).Options;
  FLastReplaceText := (Sender as TTyReplaceDialog).ReplaceText;
end;

procedure TReplaceWiringTest.TestReplaceStampsReplaceFlag;
var dlg: TTyReplaceDialog; frm: TTyFindForm;
begin
  FReplaceFired := False;
  dlg := TTyReplaceDialog.Create(nil);
  try
    dlg.OnReplace := @HandleReplace;
    frm := dlg.BuildForm;
    frm.FindEdit.Text := 'a';
    frm.ReplaceEdit.Text := 'b';
    frm.DoReplace;
    AssertTrue('OnReplace fired', FReplaceFired);
    AssertEquals('ReplaceText written back', 'b', FLastReplaceText);
    AssertTrue('frReplace set', frReplace in FLastOptions);
    AssertFalse('frReplaceAll clear', frReplaceAll in FLastOptions);
    AssertFalse('frFindNext clear', frFindNext in FLastOptions);
  finally dlg.Free; end;
end;

procedure TReplaceWiringTest.TestReplaceAllStampsReplaceAllFlag;
var dlg: TTyReplaceDialog; frm: TTyFindForm;
begin
  FReplaceFired := False;
  dlg := TTyReplaceDialog.Create(nil);
  try
    dlg.OnReplace := @HandleReplace;
    frm := dlg.BuildForm;
    frm.DoReplaceAll;
    AssertTrue('OnReplace fired', FReplaceFired);
    AssertTrue('frReplaceAll set', frReplaceAll in FLastOptions);
    AssertFalse('frFindNext clear', frFindNext in FLastOptions);
    AssertFalse('frReplace clear', frReplace in FLastOptions);
  finally dlg.Free; end;
end;

procedure TReplaceWiringTest.TestReplaceDefaultsHaveReplaceFlags;
var dlg: TTyReplaceDialog;
begin
  dlg := TTyReplaceDialog.Create(nil);
  try
    AssertTrue('frDown default', frDown in dlg.Options);
    AssertTrue('frReplace default', frReplace in dlg.Options);
    AssertTrue('frReplaceAll default', frReplaceAll in dlg.Options);
  finally dlg.Free; end;
end;

procedure TFindMapTest.TestGateFlagsPreserved;
var ch: TTyFindChecks; opts: TFindOptions;
begin
  ch.MatchCase := True; ch.WholeWord := False; ch.SearchUp := False;
  // frHideUpDown / frDisableMatchCase are UI-gate flags the mapping must NOT touch
  opts := TyChecksToFindOptions(ch, [frHideUpDown, frDisableMatchCase, frDown]);
  AssertTrue('frHideUpDown kept', frHideUpDown in opts);
  AssertTrue('frDisableMatchCase kept', frDisableMatchCase in opts);
  AssertTrue('frMatchCase set', frMatchCase in opts);
  AssertTrue('frDown set (searchup false)', frDown in opts);
end;

procedure TFindWiringTest.TestSyncFromPopulatesWidgets;
var dlg: TTyFindDialog; frm: TTyFindForm;
begin
  dlg := TTyFindDialog.Create(nil);
  try
    dlg.FindText := 'abc';
    dlg.Options := [frMatchCase];   // no frDown => SearchUp true; no frWholeWord
    frm := dlg.BuildForm;
    AssertEquals('find edit seeded from props', 'abc', frm.FindEdit.Text);
    AssertTrue('matchcase checked from props', frm.MatchCaseCheck.Checked);
    AssertFalse('wholeword unchecked', frm.WholeWordCheck.Checked);
    AssertTrue('searchup checked (no frDown)', frm.SearchUpCheck.Checked);
  finally dlg.Free; end;
end;

procedure TFindWiringTest.TestFindFormShapeNoReplace;
var dlg: TTyFindDialog; frm: TTyFindForm;
begin
  dlg := TTyFindDialog.Create(nil);
  try
    frm := dlg.BuildForm;
    AssertFalse('find form is not replace mode', frm.WithReplace);
    AssertTrue('find form has no replace edit', frm.ReplaceEdit = nil);
  finally dlg.Free; end;
end;

procedure TReplaceWiringTest.TestSyncFromPopulatesReplaceEdit;
var dlg: TTyReplaceDialog; frm: TTyFindForm;
begin
  dlg := TTyReplaceDialog.Create(nil);
  try
    dlg.FindText := 'x';
    dlg.ReplaceText := 'y';
    frm := dlg.BuildForm;
    AssertEquals('find seeded', 'x', frm.FindEdit.Text);
    AssertEquals('replace seeded', 'y', frm.ReplaceEdit.Text);
  finally dlg.Free; end;
end;

procedure TReplaceWiringTest.TestReplaceFormShapeHasReplace;
var dlg: TTyReplaceDialog; frm: TTyFindForm;
begin
  dlg := TTyReplaceDialog.Create(nil);
  try
    frm := dlg.BuildForm;
    AssertTrue('replace form is replace mode', frm.WithReplace);
    AssertTrue('replace form has replace edit', frm.ReplaceEdit <> nil);
  finally dlg.Free; end;
end;

procedure TReplaceWiringTest.TestReusedFormClearsStaleActionFlag;
var dlg: TTyReplaceDialog; frm: TTyFindForm;
begin
  dlg := TTyReplaceDialog.Create(nil);
  try
    frm := dlg.BuildForm;
    frm.DoReplaceAll;
    AssertTrue('replaceall set after ReplaceAll', frReplaceAll in dlg.Options);
    frm.DoFindNext;   // reuse the SAME form — subtractive stamping must clear stale flags
    AssertTrue('findnext set', frFindNext in dlg.Options);
    AssertFalse('stale replaceall cleared', frReplaceAll in dlg.Options);
    AssertFalse('stale replace cleared', frReplace in dlg.Options);
  finally dlg.Free; end;
end;

{ TFindEventForwardTest }

procedure TFindEventForwardTest.HandleShow(Sender: TObject);
begin end;

procedure TFindEventForwardTest.HandleClose(Sender: TObject; var CloseAction: TCloseAction);
begin end;

procedure TFindEventForwardTest.HandleCanClose(Sender: TObject; var CanClose: Boolean);
begin end;

procedure TFindEventForwardTest.TestFindForwardsEvents;
var dlg: TTyFindDialog; frm: TTyFindForm;
begin
  dlg := TTyFindDialog.Create(nil);
  try
    dlg.OnShow := @HandleShow;
    dlg.OnClose := @HandleClose;
    dlg.OnCanClose := @HandleCanClose;
    frm := dlg.BuildForm;   // build + forward, NO Show
    AssertTrue('OnShow forwarded to form', frm.OnShow = TNotifyEvent(@HandleShow));
    AssertTrue('OnClose forwarded to form', frm.OnClose = TCloseEvent(@HandleClose));
    AssertTrue('OnCanClose -> form.OnCloseQuery',
      frm.OnCloseQuery = TCloseQueryEvent(@HandleCanClose));
  finally dlg.Free; end;
end;

procedure TFindEventForwardTest.TestReplaceInheritsAndForwardsEvents;
var dlg: TTyReplaceDialog; frm: TTyFindForm;
begin
  // TTyReplaceDialog inherits the three events from TTyFindDialog (no re-declare);
  // confirm they still forward through the inherited BuildForm.
  dlg := TTyReplaceDialog.Create(nil);
  try
    dlg.OnShow := @HandleShow;
    dlg.OnCanClose := @HandleCanClose;
    frm := dlg.BuildForm;
    AssertTrue('inherited OnShow forwarded', frm.OnShow = TNotifyEvent(@HandleShow));
    AssertTrue('inherited OnCanClose -> OnCloseQuery',
      frm.OnCloseQuery = TCloseQueryEvent(@HandleCanClose));
  finally dlg.Free; end;
end;

initialization
  RegisterTest(TFindMapTest);
  RegisterTest(TFindWiringTest);
  RegisterTest(TReplaceWiringTest);
  RegisterTest(TFindEventForwardTest);
end.
