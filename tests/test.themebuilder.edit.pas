unit test.themebuilder.edit;
{ The theme builder's Edit menu (acceptance feedback): the formatter it uses (tbformat), the
  menu's items between File and View, which of them are enabled for what has the focus and
  what the editor has, formatting as one undo step, and the find bar -- next / previous round
  the ends, match case, whole word, "Not found", replace and replace all (one undo step),
  Esc. The main window is built for real and never shown, as in test.themebuilder.main. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Controls, Dialogs, tbmain;

type
  TTbFormatTests = class(TTestCase)
  published
    procedure TestATheme;                       { E1 }
    procedure TestFormattingTwiceChangesNothing;  { E2 }
    procedure TestSelectorsCommentsAndStringsKeep;  { E3 }
    procedure TestTheLinesOfASelection;         { E4 }
  end;

  TTbEditMenuTests = class(TTestCase)
  private
    FDir: string;
    FForm: TTbMainForm;
    FThemeName, FMode: string;
    procedure SetText(const AText: string);
    procedure Select(AX1, AY1, AX2, AY2: Integer);
    procedure Caret(AX, AY: Integer);
    procedure AssertSel(const AMsg: string; AX1, AY1, AX2, AY2: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheMenuIsBetweenFileAndView;  { E5 }
    procedure TestItsItemsAreWired;             { E6 }
    procedure TestWhatIsEnabled;                { E7 }
    procedure TestATextBoxWithTheFocus;         { E8 }
    procedure TestFormattingIsOneUndoStep;      { E9 }
    procedure TestFindNextAndPrevious;          { E10 }
    procedure TestMatchCaseAndWholeWord;        { E11 }
    procedure TestReplaceAndReplaceAll;         { E12 }
    procedure TestTheFindBarOpensAndCloses;     { E13 }
  end;

implementation

uses
  Forms, FileUtil, Menus, LCLType, Clipbrd, Types, SynEdit, tyControls.Controller, tbformat,
  tbfindbar, tbcssscan;

const
  cMessy =
    '/* Theme'#10 +
    '   by me */'#10 +
    ':root{--accent:#3B82F6;--radius : 6px}'#10 +
    'TyButton:hover{background:var(--accent);  border-width:1px}'#10 +
    #10#10 +
    'TyEdit.ghost { color :red; /* why */'#10 +
    'background: url("C:/a b.png");}'#10 +
    '@mode dark{'#10 +
    ':root{--accent:#60A5FA;}'#10 +
    '}'#10;
  cTidy =
    '/* Theme'#10 +
    '   by me */'#10 +
    ':root {'#10 +
    '  --accent: #3B82F6;'#10 +
    '  --radius: 6px;'#10 +
    '}'#10 +
    'TyButton:hover {'#10 +
    '  background: var(--accent);'#10 +
    '  border-width: 1px;'#10 +
    '}'#10 +
    #10 +
    'TyEdit.ghost {'#10 +
    '  color: red; /* why */'#10 +
    '  background: url("C:/a b.png");'#10 +
    '}'#10 +
    '@mode dark {'#10 +
    '  :root {'#10 +
    '    --accent: #60A5FA;'#10 +
    '  }'#10 +
    '}';

{ ---- TTbFormatTests ---- }

{ E1: a theme written every which way comes out one declaration a line, "name: value;",
  two spaces a level, closing braces on their own lines, one empty line where there were
  several }
procedure TTbFormatTests.TestATheme;
begin
  AssertEquals('E1', cTidy, TbFormatCss(cMessy, 0, #10));
  AssertEquals('E1: nothing in, nothing out', '', TbFormatCss('  '#10#10, 0, #10));
  AssertEquals('E1: an @import at the top', '@import "a.tycss";'#10 + 'TyButton {'#10 + '}',
    TbFormatCss('@import   "a.tycss" ;TyButton{}', 0, #10));
  AssertEquals('E1: line breaks as asked', ':root {'#13#10'  --a: 1;'#13#10'}',
    TbFormatCss(':root{--a:1}', 0, #13#10));
end;

{ E2: what the formatter produced is already formatted }
procedure TTbFormatTests.TestFormattingTwiceChangesNothing;
var
  once: string;
begin
  once := TbFormatCss(cMessy, 0, #10);
  AssertEquals('E2', once, TbFormatCss(once, 0, #10));
end;

{ E3: what the library's TyCssFormat breaks on a theme file stays: the colon of a pseudo-class,
  a comment's line breaks, a colon inside a quoted url; a comment inside a declaration stays
  inside it }
procedure TTbFormatTests.TestSelectorsCommentsAndStringsKeep;
var
  t: string;
begin
  t := TbFormatCss('TyButton.primary:hover{color:red}', 0, #10);
  AssertTrue('E3: the pseudo-class', Pos('TyButton.primary:hover {', t) = 1);
  t := TbFormatCss('/* one'#10'   two */'#10'TyX{}', 0, #10);
  AssertTrue('E3: the comment''s lines', Pos('/* one'#10'   two */', t) = 1);
  t := TbFormatCss('TyX{background:url(''C:/x y.png'')}', 0, #10);
  AssertTrue('E3: the string', Pos('background: url(''C:/x y.png'');', t) > 0);
  t := TbFormatCss('TyX{color: /* c */ red}', 0, #10);
  AssertTrue('E3: a comment in a declaration', Pos('  color: /* c */ red;', t) > 0);
  t := TbFormatCss('TyX{color:red;}/* after */', 0, #10);
  AssertTrue('E3: a comment after a brace on the same line', Pos('} /* after */', t) > 0);
end;

{ E4: the lines a selection touches, at the depth they start at; a comment that starts above
  them comes in whole; the last line's break stays }
procedure TTbFormatTests.TestTheLinesOfASelection;
const
  cText = 'TyButton {'#10'  color:red;'#10'    background :blue;'#10'}'#10;
  cComment = '/* a'#10'b */'#10'TyX{color:red}'#10;
var
  start, stop: Integer;
  tidy: string;
begin
  AssertTrue('E4: changed', TbFormatLines(cText, 2, 3, #10, start, stop, tidy));
  AssertEquals('E4: the lines inside the rule', 'TyButton {'#10'  color: red;'#10 +
    '  background: blue;'#10'}'#10, TbApplyEdits(cText, [TbEdit(start, stop, tidy)]));
  AssertTrue('E4: changed', TbFormatLines(cComment, 2, 3, #10, start, stop, tidy));
  AssertEquals('E4: from the comment''s start', 1, start);
  AssertEquals('E4: the comment whole', '/* a'#10'b */'#10'TyX {'#10'  color: red;'#10'}'#10,
    TbApplyEdits(cComment, [TbEdit(start, stop, tidy)]));
  AssertFalse('E4: tidy already', TbFormatLines('TyX {'#10'  color: red;'#10'}'#10, 1, 3, #10,
    start, stop, tidy));
end;

{ ---- TTbEditMenuTests ---- }

var
  GSeq: Integer = 0;
  GWidgetSetReady: Boolean = False;

procedure TTbEditMenuTests.SetUp;
begin
  if not GWidgetSetReady then
  begin
    Forms.Application.Initialize;
    GWidgetSetReady := True;
  end;
  Inc(GSeq);
  FDir := IncludeTrailingPathDelimiter(GetTempDir(False)) +
    Format('tb-edit-%d-%d', [GetProcessID, GSeq]) + PathDelim;
  ForceDirectories(FDir);
  FThemeName := TyDefaultController.ThemeName;
  FMode := TyDefaultController.Mode;
  TTbMainForm.SettingsFileForTest := FDir + 'themebuilder.ini';
  TTbMainForm.PromptAnswerForTest := mrNo;
  TTbMainForm.SaveAsNameForTest := '';
  TTbMainForm.ShowModalForTest := nil;
  FForm := TTbMainForm.Create(nil);
end;

procedure TTbEditMenuTests.TearDown;
begin
  FreeAndNil(FForm);
  TTbMainForm.PromptAnswerForTest := mrNone;
  TTbMainForm.SettingsFileForTest := '';
  if TyDefaultController.ThemeName <> FThemeName then
    TyDefaultController.ThemeName := FThemeName;
  if TyDefaultController.Mode <> FMode then
    TyDefaultController.Mode := FMode;
  if DirectoryExists(FDir) then
    DeleteDirectory(ExcludeTrailingPathDelimiter(FDir), False);
end;

{ a text with nothing to undo, the caret at the start }
procedure TTbEditMenuTests.SetText(const AText: string);
begin
  FForm.Editor.Lines.Text := AText;
  FForm.Editor.ClearUndo;
  FForm.Editor.LogicalCaretXY := Point(1, 1);
  FForm.RefreshNow;
end;

procedure TTbEditMenuTests.Select(AX1, AY1, AX2, AY2: Integer);
begin
  FForm.Editor.LogicalCaretXY := Point(AX2, AY2);
  FForm.Editor.BlockBegin := Point(AX1, AY1);
  FForm.Editor.BlockEnd := Point(AX2, AY2);
end;

{ the caret at AX, AY and nothing selected }
procedure TTbEditMenuTests.Caret(AX, AY: Integer);
begin
  Select(AX, AY, AX, AY);
  FForm.Editor.LogicalCaretXY := Point(AX, AY);
end;

procedure TTbEditMenuTests.AssertSel(const AMsg: string; AX1, AY1, AX2, AY2: Integer);
begin
  AssertTrue(AMsg + ': a selection', FForm.Editor.SelAvail);
  AssertEquals(AMsg + ': from x', AX1, FForm.Editor.BlockBegin.X);
  AssertEquals(AMsg + ': from y', AY1, FForm.Editor.BlockBegin.Y);
  AssertEquals(AMsg + ': to x', AX2, FForm.Editor.BlockEnd.X);
  AssertEquals(AMsg + ': to y', AY2, FForm.Editor.BlockEnd.Y);
end;

{ E5: "Edit" sits between "File" and "View", with its items and the usual keys -- none of
  them one SynEdit gives another meaning to }
procedure TTbEditMenuTests.TestTheMenuIsBetweenFileAndView;
var
  m: TMainMenu;
begin
  m := FForm.MainMenu1;
  AssertTrue('E5: File first', m.Items[0] = FForm.MnuFile);
  AssertTrue('E5: Edit second', m.Items[1] = FForm.MnuEdit);
  AssertTrue('E5: View third', m.Items[2] = FForm.MnuView);
  AssertEquals('E5: Undo', ShortCut(VK_Z, [ssCtrl]), FForm.MnuUndo.ShortCut);
  AssertEquals('E5: Redo, as SynEdit has it', ShortCut(VK_Z, [ssCtrl, ssShift]), FForm.MnuRedo.ShortCut);
  AssertEquals('E5: Cut', ShortCut(VK_X, [ssCtrl]), FForm.MnuCut.ShortCut);
  AssertEquals('E5: Copy', ShortCut(VK_C, [ssCtrl]), FForm.MnuCopy.ShortCut);
  AssertEquals('E5: Paste', ShortCut(VK_V, [ssCtrl]), FForm.MnuPaste.ShortCut);
  AssertEquals('E5: Delete', ShortCut(VK_DELETE, []), FForm.MnuDelete.ShortCut);
  AssertEquals('E5: Select all', ShortCut(VK_A, [ssCtrl]), FForm.MnuSelectAll.ShortCut);
  AssertEquals('E5: Format document', ShortCut(VK_F, [ssCtrl, ssShift]), FForm.MnuFormatDoc.ShortCut);
  AssertEquals('E5: Find', ShortCut(VK_F, [ssCtrl]), FForm.MnuFind.ShortCut);
  AssertEquals('E5: Find next', ShortCut(VK_F3, []), FForm.MnuFindNext.ShortCut);
  AssertEquals('E5: Find previous', ShortCut(VK_F3, [ssShift]), FForm.MnuFindPrev.ShortCut);
  AssertEquals('E5: Replace', ShortCut(VK_H, [ssCtrl]), FForm.MnuReplace.ShortCut);
  { Ctrl+Y is SynEdit's "delete line": Redo does not take it }
  AssertTrue('E5: no Ctrl+Y', m.FindItem(ShortCut(VK_Y, [ssCtrl]), fkShortCut) = nil);
end;

{ E6: each item does its thing on the editor -- clicked as the menu clicks it }
procedure TTbEditMenuTests.TestItsItemsAreWired;
var
  e: TSynEdit;
begin
  e := FForm.Editor;
  SetText('alpha beta');
  e.LogicalCaretXY := Point(6, 1);
  e.InsertTextAtCaret('X');
  FForm.UpdateEditMenu(False);
  FForm.MnuUndo.Click;
  AssertEquals('E6: Undo', 'alpha beta', e.Lines[0]);
  FForm.UpdateEditMenu(False);
  FForm.MnuRedo.Click;
  AssertEquals('E6: Redo', 'alphaX beta', e.Lines[0]);
  SetText('alpha beta');
  Select(1, 1, 6, 1);
  FForm.UpdateEditMenu(False);
  FForm.MnuCopy.Click;
  AssertEquals('E6: Copy', 'alpha', Clipboard.AsText);
  FForm.MnuCut.Click;
  AssertEquals('E6: Cut', ' beta', e.Lines[0]);
  e.LogicalCaretXY := Point(6, 1);
  FForm.UpdateEditMenu(False);
  FForm.MnuPaste.Click;
  AssertEquals('E6: Paste', ' betaalpha', e.Lines[0]);
  Select(1, 1, 2, 1);
  FForm.UpdateEditMenu(False);
  FForm.MnuDelete.Click;
  AssertEquals('E6: Delete', 'betaalpha', e.Lines[0]);
  FForm.UpdateEditMenu(False);
  FForm.MnuSelectAll.Click;
  AssertEquals('E6: Select all', 'betaalpha', e.SelText);
  SetText('TyX{color:red}');
  FForm.UpdateEditMenu(False);
  FForm.MnuFormatDoc.Click;
  AssertEquals('E6: Format document', 'TyX {', e.Lines[0]);
  SetText('TyX {'#10'color:red;'#10'}');
  Select(1, 2, 3, 2);
  FForm.UpdateEditMenu(False);
  FForm.MnuFormatSel.Click;
  AssertEquals('E6: Format selection', '  color: red;', e.Lines[1]);
end;

{ E7: what is enabled follows the editor -- nothing selected: no Cut, Copy, Delete; nothing
  done: no Undo; nothing undone: no Redo; read-only: nothing that changes the text }
procedure TTbEditMenuTests.TestWhatIsEnabled;
var
  e: TSynEdit;
begin
  e := FForm.Editor;
  SetText('alpha beta');
  FForm.UpdateEditMenu(False);
  AssertTrue('E7: the editor', FForm.EditTarget = etEditor);
  AssertFalse('E7: nothing to undo', FForm.MnuUndo.Enabled);
  AssertFalse('E7: nothing to redo', FForm.MnuRedo.Enabled);
  AssertFalse('E7: no selection, no Cut', FForm.MnuCut.Enabled);
  AssertFalse('E7: no selection, no Copy', FForm.MnuCopy.Enabled);
  AssertFalse('E7: no selection, no Delete', FForm.MnuDelete.Enabled);
  AssertFalse('E7: no selection, no Format selection', FForm.MnuFormatSel.Enabled);
  AssertTrue('E7: Paste', FForm.MnuPaste.Enabled);
  AssertTrue('E7: Select all', FForm.MnuSelectAll.Enabled);
  AssertTrue('E7: Format document', FForm.MnuFormatDoc.Enabled);
  AssertTrue('E7: Find', FForm.MnuFind.Enabled);
  AssertFalse('E7: nothing to find again', FForm.MnuFindNext.Enabled);
  AssertFalse('E7: nor back', FForm.MnuFindPrev.Enabled);
  Select(1, 1, 6, 1);
  FForm.UpdateEditMenu(False);
  AssertTrue('E7: a selection, Cut', FForm.MnuCut.Enabled);
  AssertTrue('E7: Copy', FForm.MnuCopy.Enabled);
  AssertTrue('E7: Delete', FForm.MnuDelete.Enabled);
  AssertTrue('E7: Format selection', FForm.MnuFormatSel.Enabled);
  FForm.MnuDelete.Click;
  FForm.UpdateEditMenu(False);
  AssertTrue('E7: something to undo', FForm.MnuUndo.Enabled);
  FForm.MnuUndo.Click;
  FForm.UpdateEditMenu(False);
  AssertTrue('E7: something to redo', FForm.MnuRedo.Enabled);
  FForm.FindBar.EdtFind.Text := 'beta';
  FForm.UpdateEditMenu(False);
  AssertTrue('E7: something to find again', FForm.MnuFindNext.Enabled);
  AssertTrue('E7: and back', FForm.MnuFindPrev.Enabled);
  Select(1, 1, 6, 1);
  e.ReadOnly := True;
  try
    FForm.UpdateEditMenu(False);
    AssertFalse('E7: read-only, no Cut', FForm.MnuCut.Enabled);
    AssertTrue('E7: read-only, Copy', FForm.MnuCopy.Enabled);
    AssertFalse('E7: read-only, no Paste', FForm.MnuPaste.Enabled);
    AssertFalse('E7: read-only, no Delete', FForm.MnuDelete.Enabled);
    AssertFalse('E7: read-only, no Undo', FForm.MnuUndo.Enabled);
    AssertFalse('E7: read-only, no Format', FForm.MnuFormatDoc.Enabled);
    AssertFalse('E7: read-only, no Replace', FForm.MnuReplace.Enabled);
  finally
    e.ReadOnly := False;
  end;
end;

{ E8: a Ty text box with the focus (the find box) is what Copy and Select all act on -- the
  editor's selection is left alone; Delete has nothing to do there. A shortcut with the
  focus on a list acts on nothing: the items are off and the key goes to the list. Opened
  with the mouse, the same menu means the editor. }
procedure TTbEditMenuTests.TestATextBoxWithTheFocus;
var
  box: TWinControl;
begin
  SetText('alpha beta');
  Select(1, 1, 6, 1);
  box := FForm.FindBar.EdtFind;
  FForm.FindBar.EdtFind.Text := 'hello';
  FForm.FocusForTest := box;
  try
    FForm.UpdateEditMenu(True);
    AssertTrue('E8: the text box', FForm.EditTarget = etText);
    AssertFalse('E8: no Delete', FForm.MnuDelete.Enabled);
    AssertTrue('E8: Select all', FForm.MnuSelectAll.Enabled);
    FForm.MnuSelectAll.Click;
    FForm.UpdateEditMenu(True);
    AssertTrue('E8: its text selected: Copy', FForm.MnuCopy.Enabled);
    FForm.MnuCopy.Click;
    AssertEquals('E8: the box''s text copied', 'hello', Clipboard.AsText);
    AssertEquals('E8: the editor''s selection as it was', 'alpha', FForm.Editor.SelText);

    FForm.FocusForTest := FForm.ProblemsList;
    FForm.UpdateEditMenu(True);
    AssertTrue('E8: a shortcut over a list: nothing', FForm.EditTarget = etNone);
    AssertFalse('E8: no Undo', FForm.MnuUndo.Enabled);
    AssertFalse('E8: no Copy', FForm.MnuCopy.Enabled);
    AssertFalse('E8: no Paste', FForm.MnuPaste.Enabled);
    AssertFalse('E8: no Select all', FForm.MnuSelectAll.Enabled);
    AssertTrue('E8: Find still', FForm.MnuFind.Enabled);
    FForm.UpdateEditMenu(False);
    AssertTrue('E8: with the mouse: the editor', FForm.EditTarget = etEditor);
    AssertTrue('E8: its Copy', FForm.MnuCopy.Enabled);
  finally
    FForm.FocusForTest := nil;
  end;
end;

{ E9: Format document and Format selection are one undo step each }
procedure TTbEditMenuTests.TestFormattingIsOneUndoStep;
var
  e: TSynEdit;
  before: string;
begin
  e := FForm.Editor;
  SetText(cMessy);
  before := e.Lines.Text;
  AssertTrue('E9: formatted', FForm.FormatDocument);
  AssertEquals('E9: the tidy text', TbFormatCss(cMessy, 0, LineEnding) + LineEnding, e.Lines.Text);
  AssertTrue('E9: modified', e.Modified);
  AssertFalse('E9: a second time, nothing', FForm.FormatDocument);
  e.Undo;
  AssertEquals('E9: one Undo, all of it', before, e.Lines.Text);
  AssertFalse('E9: and nothing more to undo', e.CanUndo);

  SetText('TyX {'#10'color:red;'#10'  background :blue;'#10'}'#10'TyY{a:b}');
  before := e.Lines.Text;
  Select(1, 2, 1, 4);           { ends at the start of line 4: lines 2 and 3 }
  AssertTrue('E9: the selection formatted', FForm.FormatSelection);
  AssertEquals('E9: line 2', '  color: red;', e.Lines[1]);
  AssertEquals('E9: line 3', '  background: blue;', e.Lines[2]);
  AssertEquals('E9: the rest left as it was', 'TyY{a:b}', e.Lines[4]);
  e.Undo;
  AssertEquals('E9: one Undo', before, e.Lines.Text);
  AssertFalse('E9: nothing more', e.CanUndo);
end;

{ E10: next and previous from the selection on, round the ends; "Not found" when there is
  nothing; F3 / Shift+F3 are the menu's }
procedure TTbEditMenuTests.TestFindNextAndPrevious;
var
  bar: TTbFindBar;
begin
  SetText('a foo b Foo'#10'foobar foo');
  bar := FForm.FindBar;
  bar.EdtFind.Text := 'foo';
  AssertTrue('E10: found', bar.FindNext);
  AssertSel('E10: the first', 3, 1, 6, 1);
  bar.FindNext;
  AssertSel('E10: any case', 9, 1, 12, 1);
  FForm.UpdateEditMenu(False);
  FForm.MnuFindNext.Click;
  AssertSel('E10: F3, inside a word', 1, 2, 4, 2);
  bar.FindNext;
  AssertSel('E10: the last', 8, 2, 11, 2);
  bar.FindNext;
  AssertSel('E10: round to the first', 3, 1, 6, 1);
  AssertEquals('E10: no message', '', bar.LblInfo.Caption);
  FForm.MnuFindPrev.Click;
  AssertSel('E10: Shift+F3, round to the last', 8, 2, 11, 2);
  bar.FindPrevious;
  AssertSel('E10: the one before', 1, 2, 4, 2);
  bar.EdtFind.Text := 'zzz';
  AssertFalse('E10: nothing', bar.FindNext);
  AssertEquals('E10: says so', rsTbFindNotFound, bar.LblInfo.Caption);
end;

{ E11: match case leaves Foo alone; whole word leaves foobar alone }
procedure TTbEditMenuTests.TestMatchCaseAndWholeWord;
var
  bar: TTbFindBar;
begin
  SetText('a foo b Foo'#10'foobar foo');
  bar := FForm.FindBar;
  bar.EdtFind.Text := 'foo';
  bar.ChkCase.Checked := True;
  bar.FindNext;
  AssertSel('E11: case: the first', 3, 1, 6, 1);
  bar.FindNext;
  AssertSel('E11: case: not Foo', 1, 2, 4, 2);
  bar.ChkCase.Checked := False;
  bar.ChkWord.Checked := True;
  Caret(1, 1);
  bar.FindNext;
  AssertSel('E11: word: the first', 3, 1, 6, 1);
  bar.FindNext;
  AssertSel('E11: word: Foo', 9, 1, 12, 1);
  bar.FindNext;
  AssertSel('E11: word: not foobar', 8, 2, 11, 2);
end;

{ E12: Replace changes the match that is selected and finds the next; Replace all is one
  undo step and honours match case }
procedure TTbEditMenuTests.TestReplaceAndReplaceAll;
var
  bar: TTbFindBar;
  e: TSynEdit;
  before: string;
begin
  e := FForm.Editor;
  SetText('a foo b Foo'#10'foobar foo');
  before := e.Lines.Text;
  bar := FForm.FindBar;
  bar.EdtFind.Text := 'foo';
  bar.EdtReplace.Text := 'qux';
  AssertEquals('E12: all, any case', 4, bar.ReplaceAll);
  AssertEquals('E12: line 1', 'a qux b qux', e.Lines[0]);
  AssertEquals('E12: line 2', 'quxbar qux', e.Lines[1]);
  AssertEquals('E12: says how many', Format(rsTbFindReplaced, [4]), bar.LblInfo.Caption);
  e.Undo;
  AssertEquals('E12: one Undo, all of it', before, e.Lines.Text);
  AssertFalse('E12: nothing more', e.CanUndo);
  bar.ChkCase.Checked := True;
  bar.EdtFind.Text := 'Foo';
  AssertEquals('E12: match case', 1, bar.ReplaceAll);
  AssertEquals('E12: only Foo', 'a foo b qux', e.Lines[0]);
  e.Undo;
  bar.ChkCase.Checked := False;
  bar.EdtFind.Text := 'foo';
  Caret(1, 1);
  bar.FindNext;
  AssertSel('E12: found', 3, 1, 6, 1);
  AssertTrue('E12: replaced', bar.ReplaceNext);
  AssertEquals('E12: that one', 'a qux b Foo', e.Lines[0]);
  AssertSel('E12: and on to the next', 9, 1, 12, 1);
end;

{ E13: Find opens the bar (the selection goes into the box), Replace with its second row; Esc
  closes it; Enter finds the next }
procedure TTbEditMenuTests.TestTheFindBarOpensAndCloses;
var
  bar: TTbFindBar;
begin
  SetText('alpha beta alpha');
  bar := FForm.FindBar;
  AssertFalse('E13: hidden at first', bar.Visible);
  Select(7, 1, 11, 1);
  FForm.MnuFind.Click;
  AssertTrue('E13: Find opens it', bar.Visible);
  AssertFalse('E13: without the replace row', bar.ReplaceRow.Visible);
  AssertEquals('E13: the selection in the box', 'beta', bar.EdtFind.Text);
  AssertTrue('E13: over the editor', bar.Parent = FForm.Editor.Parent);
  bar.KeyForTest(VK_ESCAPE, []);
  AssertFalse('E13: Esc closes it', bar.Visible);
  FForm.MnuReplace.Click;
  AssertTrue('E13: Replace opens it', bar.Visible);
  AssertTrue('E13: with the replace row', bar.ReplaceRow.Visible);
  bar.EdtFind.Text := 'alpha';
  Caret(1, 1);
  bar.KeyForTest(VK_RETURN, []);
  AssertSel('E13: Enter finds', 1, 1, 6, 1);
  bar.KeyForTest(VK_RETURN, []);
  AssertSel('E13: and the next', 12, 1, 17, 1);
  bar.KeyForTest(VK_RETURN, [ssShift]);
  AssertSel('E13: Shift+Enter, the one before', 1, 1, 6, 1);
end;

initialization
  RegisterTest(TTbFormatTests);
  RegisterTest(TTbEditMenuTests);
end.
