unit test.dialogs.find;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Dialogs, Forms, fpcunit, testregistry,
  tyControls.CheckBox, tyControls.Button, tyControls.Dialogs.Find;

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

  { The twelve TFindOptions 3.0 accepted and ignored (#28): LCL's SetFormValues /
    GetFormValues, gate for gate. }
  TFindOptionsTest = class(TTestCase)
  private
    FHelpSender: TObject;
    procedure HandleHelp(Sender: TObject);
    procedure CheckHide(AOption: TFindOption; AReplace: Boolean; const AWhat: string);
    function BoxOf(AForm: TTyFindForm; AIndex: Integer): TTyCheckBox;
  published
    procedure TestEachHideOptionHidesItsBoxAndClosesTheGap;
    procedure TestEachDisableOptionGreysOnlyItsBox;
    procedure TestEntireScopeGoesInAndComesBack;
    procedure TestPromptOnReplaceGoesInAndComesBack;
    procedure TestFindFormHasNoPromptOnReplace;
    procedure TestReplaceHidesPromptOnReplaceByDefault;
    procedure TestEntireScopeShowsByDefault;
    procedure TestShowHelpShowsHelpAndForwardsTheClick;
    procedure TestOptionsWrittenWhileOpenUpdateTheWindow;
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

{ TFindOptionsTest }

procedure TFindOptionsTest.HandleHelp(Sender: TObject);
begin
  FHelpSender := Sender;
end;

{ The boxes in their stacking order: match case, whole word, search up, entire scope, prompt. }
function TFindOptionsTest.BoxOf(AForm: TTyFindForm; AIndex: Integer): TTyCheckBox;
begin
  case AIndex of
    0: Result := AForm.MatchCaseCheck;
    1: Result := AForm.WholeWordCheck;
    2: Result := AForm.SearchUpCheck;
    3: Result := AForm.EntireScopeCheck;
  else
    Result := AForm.PromptOnReplaceCheck;
  end;
end;

{ Hiding one box takes it out of the stack: every box below moves up into its place. }
procedure TFindOptionsTest.CheckHide(AOption: TFindOption; AReplace: Boolean;
  const AWhat: string);
var
  dlg: TTyFindDialog;
  frm: TTyFindForm;
  tops: array[0..4] of Integer;
  hidden, i, last: Integer;
begin
  if AReplace then dlg := TTyReplaceDialog.Create(nil) else dlg := TTyFindDialog.Create(nil);
  try
    if AReplace then dlg.Options := [frDown, frReplace, frReplaceAll]   // prompt box showing
    else dlg.Options := [frDown];
    frm := dlg.BuildForm;
    if AReplace then last := 4 else last := 3;
    for i := 0 to last do tops[i] := BoxOf(frm, i).Top;
    case AOption of
      frHideMatchCase: hidden := 0;
      frHideWholeWord: hidden := 1;
      frHideUpDown: hidden := 2;
      frHideEntireScope: hidden := 3;
    else
      hidden := 4;
    end;
    dlg.Options := dlg.Options + [AOption];
    frm := dlg.BuildForm;
    for i := 0 to last do
      if i = hidden then
        AssertFalse(AWhat + ': its box is hidden', BoxOf(frm, i).Visible)
      else
        AssertTrue(AWhat + ': box ' + IntToStr(i) + ' still shows', BoxOf(frm, i).Visible);
    for i := hidden + 1 to last do
      AssertEquals(AWhat + ': box ' + IntToStr(i) + ' moved up one place',
        tops[i - 1], BoxOf(frm, i).Top);
  finally dlg.Free; end;
end;

procedure TFindOptionsTest.TestEachHideOptionHidesItsBoxAndClosesTheGap;
begin
  CheckHide(frHideMatchCase, False, 'frHideMatchCase');
  CheckHide(frHideWholeWord, False, 'frHideWholeWord');
  CheckHide(frHideUpDown, False, 'frHideUpDown');
  CheckHide(frHideEntireScope, False, 'frHideEntireScope');
  CheckHide(frHideMatchCase, True, 'frHideMatchCase (replace)');
  CheckHide(frHidePromptOnReplace, True, 'frHidePromptOnReplace');
end;

procedure TFindOptionsTest.TestEachDisableOptionGreysOnlyItsBox;
const
  Gates: array[0..2] of TFindOption = (frDisableMatchCase, frDisableWholeWord, frDisableUpDown);
var
  dlg: TTyFindDialog;
  frm: TTyFindForm;
  g, i: Integer;
begin
  for g := 0 to 2 do
  begin
    dlg := TTyFindDialog.Create(nil);
    try
      dlg.Options := [frDown, Gates[g]];
      frm := dlg.BuildForm;
      for i := 0 to 2 do
      begin
        AssertEquals('gate ' + IntToStr(g) + ', box ' + IntToStr(i) + ' enabled',
          i <> g, BoxOf(frm, i).Enabled);
        AssertTrue('gate ' + IntToStr(g) + ', box ' + IntToStr(i) + ' still shows',
          BoxOf(frm, i).Visible);
      end;
      AssertTrue('entire scope is never disabled', frm.EntireScopeCheck.Enabled);
    finally dlg.Free; end;
  end;
end;

procedure TFindOptionsTest.TestEntireScopeGoesInAndComesBack;
var dlg: TTyFindDialog; frm: TTyFindForm;
begin
  dlg := TTyFindDialog.Create(nil);
  try
    dlg.Options := [frDown, frEntireScope];
    frm := dlg.BuildForm;
    AssertTrue('frEntireScope checks the box', frm.EntireScopeCheck.Checked);
    frm.EntireScopeCheck.Checked := False;
    frm.DoFindNext;
    AssertFalse('unchecked -> frEntireScope cleared', frEntireScope in dlg.Options);
    frm.EntireScopeCheck.Checked := True;
    frm.DoFindNext;
    AssertTrue('checked -> frEntireScope set', frEntireScope in dlg.Options);
  finally dlg.Free; end;
end;

procedure TFindOptionsTest.TestPromptOnReplaceGoesInAndComesBack;
var dlg: TTyReplaceDialog; frm: TTyFindForm;
begin
  dlg := TTyReplaceDialog.Create(nil);
  try
    dlg.Options := [frDown, frReplace, frPromptOnReplace];
    frm := dlg.BuildForm;
    AssertTrue('frPromptOnReplace checks the box', frm.PromptOnReplaceCheck.Checked);
    AssertTrue('and the box shows (no frHidePromptOnReplace)', frm.PromptOnReplaceCheck.Visible);
    frm.PromptOnReplaceCheck.Checked := False;
    frm.DoReplace;
    AssertFalse('unchecked -> frPromptOnReplace cleared', frPromptOnReplace in dlg.Options);
    frm.PromptOnReplaceCheck.Checked := True;
    frm.DoReplaceAll;
    AssertTrue('checked -> frPromptOnReplace set', frPromptOnReplace in dlg.Options);
  finally dlg.Free; end;
end;

procedure TFindOptionsTest.TestFindFormHasNoPromptOnReplace;
var dlg: TTyFindDialog; frm: TTyFindForm;
begin
  dlg := TTyFindDialog.Create(nil);
  try
    dlg.Options := [frDown, frPromptOnReplace];
    frm := dlg.BuildForm;
    AssertTrue('a find-only form has no prompt-on-replace box', frm.PromptOnReplaceCheck = nil);
    frm.DoFindNext;
    AssertTrue('and leaves the flag as the program set it', frPromptOnReplace in dlg.Options);
  finally dlg.Free; end;
end;

procedure TFindOptionsTest.TestReplaceHidesPromptOnReplaceByDefault;
var dlg: TTyReplaceDialog; frm: TTyFindForm;
begin
  dlg := TTyReplaceDialog.Create(nil);
  try
    AssertTrue('LCL''s TReplaceDialog default', frHidePromptOnReplace in dlg.Options);
    frm := dlg.BuildForm;
    AssertFalse('so a new replace dialog shows no prompt box', frm.PromptOnReplaceCheck.Visible);
  finally dlg.Free; end;
end;

procedure TFindOptionsTest.TestEntireScopeShowsByDefault;
var dlg: TTyFindDialog; frm: TTyFindForm;
begin
  dlg := TTyFindDialog.Create(nil);
  try
    frm := dlg.BuildForm;
    AssertTrue('as in LCL, shown unless frHideEntireScope', frm.EntireScopeCheck.Visible);
    AssertFalse('and unchecked unless frEntireScope', frm.EntireScopeCheck.Checked);
    AssertFalse('no Help button without frShowHelp', frm.HelpButton.Visible);
  finally dlg.Free; end;
end;

procedure TFindOptionsTest.TestShowHelpShowsHelpAndForwardsTheClick;
var dlg: TTyFindDialog; frm: TTyFindForm;
begin
  FHelpSender := nil;
  dlg := TTyFindDialog.Create(nil);
  try
    dlg.OnHelpClicked := @HandleHelp;
    dlg.Options := [frDown, frShowHelp];
    frm := dlg.BuildForm;
    AssertTrue('frShowHelp shows Help', frm.HelpButton.Visible);
    frm.HelpButton.Click;
    AssertTrue('the click reaches OnHelpClicked, Sender = the component', FHelpSender = dlg);
  finally dlg.Free; end;
end;

procedure TFindOptionsTest.TestOptionsWrittenWhileOpenUpdateTheWindow;
var dlg: TTyFindDialog; frm: TTyFindForm;
begin
  dlg := TTyFindDialog.Create(nil);
  try
    frm := dlg.BuildForm;
    frm.FindEdit.Text := 'typed, not yet written back';
    dlg.Options := dlg.Options + [frHideWholeWord, frMatchCase];
    AssertFalse('the open window hides the box at once', frm.WholeWordCheck.Visible);
    AssertTrue('and checks match case', frm.MatchCaseCheck.Checked);
    AssertEquals('but keeps what the user typed', 'typed, not yet written back',
      frm.FindEdit.Text);
  finally dlg.Free; end;
end;

initialization
  RegisterTest(TFindOptionsTest);
  RegisterTest(TFindMapTest);
  RegisterTest(TFindWiringTest);
  RegisterTest(TReplaceWiringTest);
  RegisterTest(TFindEventForwardTest);
end.
