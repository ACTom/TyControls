unit test.dialogs.find;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Dialogs, fpcunit, testregistry,
  tyControls.CheckBox, tyControls.Dialogs.Find;

type
  TFindMapTest = class(TTestCase)
  published
    procedure TestOptionsToChecks;
    procedure TestChecksToOptionsRoundTrip;
    procedure TestBasePreserved;
    procedure TestExhaustiveRoundTrip;
  end;

  TFindWiringTest = class(TTestCase)
  private
    FFired: Boolean;
    FLastOptions: TFindOptions;
    FLastFindText: string;
    procedure HandleFind(Sender: TObject);
  published
    procedure TestFindNextFiresWithActionFlags;
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

initialization
  RegisterTest(TFindMapTest);
  RegisterTest(TFindWiringTest);
  RegisterTest(TReplaceWiringTest);
end.
