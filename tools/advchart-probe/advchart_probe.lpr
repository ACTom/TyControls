program advchart_probe;
{$mode objfpc}{$H+}

{ A real-machine probe for the chart option editor.

  WHY THIS EXISTS. Everything else in this feature is reachable from tests/, on
  purpose -- the whole design put each judgement in source/ so a test could see
  it. What is left in designtime/ is the part a headless assertion could never
  check anyway: widget layout, the completion popup's wiring against a real
  SynEdit, and caret arithmetic in bytes against a control that thinks in screen
  columns.

  So this drives it. It opens the dialog on a real Windows desktop, types into
  it, and reports what came back. It is not a test in the suite and it does not
  pretend to be one; it is the difference between a checklist a human works
  through and a program that already looked.

  THE SHARPEST CHECK IS THE CJK ONE. TyOptSliceBefore measures bytes and
  SynEdit's CaretXY is a screen column, so a caret read through the wrong
  property lands in the wrong place -- and it does that ONLY once the text above
  it stops being ASCII. In a library whose own demos carry Chinese labels, that
  is a when, not an if, and no amount of ASCII fixtures would ever show it.

  Run:  advchart_probe.exe            report to stdout, exit 1 on any failure
        advchart_probe.exe --show     leave the dialog up for a look }

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, Controls, StdCtrls, ComCtrls, ExtCtrls, Classes, SysUtils,
  Graphics, SynEdit, SynEditTypes,
  tyControls.AdvChart.Complete,
  tyControls.AdvChart.Diagnose,
  tyControls.Design.AdvChart.Editor;

var
  GFails: Integer = 0;
  GChecks: Integer = 0;

procedure Check(const AName: string; AOk: Boolean; const ADetail: string = '');
begin
  Inc(GChecks);
  if AOk then
    WriteLn('  ok    ', AName)
  else
  begin
    Inc(GFails);
    WriteLn('  FAIL  ', AName, '  ', ADetail);
  end;
end;

{ Sleep would be wrong here. The diagnostics run off a 200ms debounce timer, and
  a timer only fires while a message loop is turning -- so a probe that sleeps
  and then pumps once is testing its own guess about WM_TIMER's delivery rules
  rather than the dialog. Pump for the whole wait. }
procedure PumpFor(AMs: Integer);
var t: QWord;
begin
  t := GetTickCount64;
  while GetTickCount64 - t < QWord(AMs) do
  begin
    Application.ProcessMessages;
    Sleep(5);
  end;
  Application.ProcessMessages;
end;

{ Chained, not replaced: the question is whether SynEdit fires OnChange at all
  when Text is assigned, and replacing the dialog's handler would answer a
  different question. }
type
  TSpy = class
    Hits: Integer;
    Inner: TNotifyEvent;
    procedure Fired(Sender: TObject);
  end;

procedure TSpy.Fired(Sender: TObject);
begin
  Inc(Hits);
  if Assigned(Inner) then Inner(Sender);
end;

{ Assigning Text does NOT fire SynEdit's OnChange -- the dialog knows, which is
  why Execute calls its own TimerTick after seeding the editor. So a probe that
  assigned Text and waited would be watching a debounce that was never armed.
  Replacing the selection goes through the editing path, and it is also what the
  user actually does here: the dialog's own comment says the commonest action is
  pasting an ECharts config. }
procedure Paste(AEdit: TSynEdit; const AText: string);
begin
  AEdit.SelectAll;
  AEdit.SelText := AText;
end;

function Row2(ATree: TTreeView): string;
begin
  if ATree.Items.Count > 0 then Result := ATree.Items[0].Text
                           else Result := '<empty>';
end;

function Row(AList: TListBox; AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < AList.Items.Count) then
    Result := AList.Items[AIndex]
  else
    Result := '<no row ' + IntToStr(AIndex) + '>';
end;

procedure Probe;
var
  dlg: TTyChartOptionDialog;
  ed: TSynEdit;
  issues: TListBox;
  tree: TTreeView;
  warn, path: TLabel;
  list: TStringList;
  before, cjk: string;
  spy: TSpy;
  ctl: TControl;
  i: Integer;
begin
  spy := TSpy.Create;
  dlg := TTyChartOptionDialog.CreateFor;
  try
    dlg.Show;
    PumpFor(50);

    ed := dlg.FindComponent('OptionEdit') as TSynEdit;
    tree := dlg.FindComponent('RefTree') as TTreeView;
    issues := dlg.FindComponent('IssueList') as TListBox;
    warn := dlg.FindComponent('WarnLabel') as TLabel;
    path := dlg.FindComponent('PathLabel') as TLabel;

    WriteLn('-- the dialog exists and is assembled --');
    Check('the editor is there', ed <> nil);
    Check('the reference tree is there', tree <> nil);
    Check('the issues list is there', issues <> nil);
    Check('both status labels are there', (warn <> nil) and (path <> nil));
    if (ed = nil) or (tree = nil) or (issues = nil) then Exit;

    WriteLn('-- the reference tree --');
    Check('the root has the option''s top-level keys',
      tree.Items.Count > 20, Format('%d rows', [tree.Items.Count]));

    WriteLn('-- what the bottom of the form actually looks like --');
    for i := 0 to dlg.ControlCount - 1 do
    begin
      ctl := dlg.Controls[i];
      if ctl.Align = alBottom then
        WriteLn(Format('        %-12s %-10s top %4d  h %3d',
          [ctl.Name, ctl.ClassName, ctl.Top, ctl.Height]));
    end;

    WriteLn('-- diagnostics on a good option --');
    spy.Inner := ed.OnChange;
    ed.OnChange := @spy.Fired;
    Paste(ed, '{ xAxis: { data: [''A''] }, yAxis: {},'
      + ' series: [{ type: ''bar'', data: [1] }] }');
    PumpFor(600);
    Check('editing the document arms the debounce', spy.Hits > 0,
      Format('%d hits', [spy.Hits]));
    Check('the debounce fired at all', issues.Items.Count > 0);
    Check('and it is the all-clear, not a complaint',
      (issues.Items.Count = 1) and (Pos('understood', LowerCase(Row(issues, 0))) > 0),
      Format('%d rows, first: %s', [issues.Items.Count,
        Copy(Row(issues, 0), 1, 70)]));

    WriteLn('-- diagnostics on a typo --');
    Paste(ed, '{' + LineEnding + '  xAxis: { axisLabl: {} },' + LineEnding
      + '  yAxis: {},' + LineEnding
      + '  series: [{ type: ''bar'', data: [1] }]' + LineEnding + '}');
    PumpFor(600);
    Check('the typo is reported', Pos('axisLabl', Row(issues, 0)) > 0,
      Copy(Row(issues, 0), 1, 80));
    Check('and it suggests the real name',
      Pos('axisLabel', Row(issues, 0)) > 0, Copy(Row(issues, 0), 1, 80));

    WriteLn('-- completion, plain ASCII --');
    list := TStringList.Create;
    try
      Check('the root offers its options', TyOptCompletionsAt('{ ', list));
      Check('including xAxis', list.IndexOf('xAxis') >= 0,
        Format('%d items', [list.Count]));
    finally
      list.Free;
    end;

    WriteLn('-- completion AFTER CJK, ON THE CARETS OWN LINE --');
    { The caret has to be on the Chinese line. TyOptSliceBefore takes every line
      above the caret whole, so CJK up there is read identically whichever caret
      property you use -- the two only disagree about the caret's OWN line,
      where one counts bytes and the other counts screen columns.

      The fixture ends exactly where the caret belongs and the paste leaves it
      there, so nothing here depends on how SynEdit clamps a column past the end
      of a line or whether it trims a trailing space. }
    cjk := '{' + LineEnding
      + '  title: { text: ''中文标题'' },' + LineEnding
      + '  series: [{ type: ''bar'', name: ''中文系列名称'',';
    Paste(ed, cjk);
    Application.ProcessMessages;

    Check('the caret is on the line the Chinese is on',
      ed.LogicalCaretXY.Y = 3, Format('line %d', [ed.LogicalCaretXY.Y]));
    { THE CANARY. If these two agreed, everything below would pass whichever one
      the dialog read, and the check would be decoration. }
    Check('the byte offset and the screen column genuinely disagree here',
      ed.LogicalCaretXY.X > ed.CaretXY.X,
      Format('logical %d, screen %d', [ed.LogicalCaretXY.X, ed.CaretXY.X]));

    before := TyOptSliceBefore(ed.Text, ed.LogicalCaretXY.Y, ed.LogicalCaretXY.X);
    Check('the slice reaches the caret rather than stopping inside the Chinese',
      (Length(before) >= Length(ed.Lines[2]))
      and (Copy(before, Length(before) - Length(ed.Lines[2]) + 1,
                Length(ed.Lines[2])) = ed.Lines[2]),
      '...[' + Copy(before, Length(before) - 24, 25) + ']');

    list := TStringList.Create;
    try
      { Cut short, the slice ends inside `'中文系列名称'` and the caret looks
        like it is in a string, so this comes back with the wrong answer or no
        answer at all. }
      Check('and completion still knows it is inside a bar series',
        TyOptCompletionsAt(before, list) and (list.IndexOf('itemStyle') >= 0),
        Format('%d items', [list.Count]));
    finally
      list.Free;
    end;

    WriteLn('-- and the same slice read through the WRONG property --');
    before := TyOptSliceBefore(ed.Text, ed.CaretXY.Y, ed.CaretXY.X);
    list := TStringList.Create;
    try
      { Not a requirement, a demonstration: this is what the dialog would be
        doing if TextBeforeCaret used CaretXY, and it is reported so the number
        above is visibly a different number. }
      WriteLn(Format('        screen-column slice ends: ...[%s]',
        [Copy(before, Length(before) - 14, 15)]));
      WriteLn(Format('        and offers %d completions',
        [Ord(TyOptCompletionsAt(before, list)) * list.Count]));
    finally
      list.Free;
    end;

    WriteLn('-- the bottom strip, top to bottom --');
    { Same-align code-created siblings display in REVERSE creation order, so
      this asserts the reversal was accounted for rather than merely commented
      about. }
    if (warn <> nil) and (path <> nil) then
    begin
      Check('issues sit above the warning', issues.Top < warn.Top,
        Format('issues %d, warn %d', [issues.Top, warn.Top]));
      Check('and the warning above the path', warn.Top < path.Top,
        Format('warn %d, path %d', [warn.Top, path.Top]));
    end;

    WriteLn('-- the reference filter --');
    if dlg.FindComponent('RefFilter') <> nil then
    begin
      TEdit(dlg.FindComponent('RefFilter')).Text := 'axisLabel';
      PumpFor(300);
      Check('a filter finds a key buried in a lazy tree',
        (tree.Items.Count > 0)
        and (Pos('axisLabel', tree.Items[0].Text) > 0),
        Format('%d rows, first: %s', [tree.Items.Count,
          Row2(tree)]));

      TEdit(dlg.FindComponent('RefFilter')).Text := 'zzzznotakey';
      PumpFor(300);
      Check('and a miss shows nothing rather than everything',
        tree.Items.Count = 0, Format('%d rows still shown', [tree.Items.Count]));

      TEdit(dlg.FindComponent('RefFilter')).Text := '';
      PumpFor(300);
      Check('clearing it brings the tree back', tree.Items.Count > 20,
        Format('%d rows', [tree.Items.Count]));
    end;

    WriteLn('-- double-clicking a filter result --');
    { Filter hits are captioned with a whole dotted path, and a parentless row
      otherwise means a child of the root -- so this used to insert
      `xAxis.axisLabel: `, and a '.' is not a name character. Every hit below
      the top level added an error to the document the feature exists to help
      write. }
    TEdit(dlg.FindComponent('RefFilter')).Text := 'axisLabel';
    PumpFor(300);
    { A COMPLETE option, so the only thing TyOptDiagnose can complain about is
      what the double-click just wrote. A bare xAxis draws no grid and says so,
      which is a fair complaint about the fixture and not about the insert. }
    Paste(ed, '{' + LineEnding + '  xAxis: { ' + LineEnding + '  },' +
              LineEnding + '  yAxis: {},' + LineEnding +
              '  series: [{ type: ''bar'', data: [1] }]' + LineEnding + '}');
    ed.CaretXY := Point(12, 2);
    Application.ProcessMessages;
    if tree.Items.Count > 0 then
    begin
      tree.Selected := tree.Items[0];
      Application.ProcessMessages;
      before := ed.Text;
      if Assigned(tree.OnDblClick) then tree.OnDblClick(tree);
      Application.ProcessMessages;
      Check('the double-click inserted something',
        ed.Text <> before, 'text unchanged');
      Check('and it is a bare key, not a dotted path',
        Pos('.', Copy(ed.Text, Pos('axisLabel', ed.Text) - 12, 12)) = 0,
        '...[' + Copy(ed.Text, Pos('axisLabel', ed.Text) - 12, 24) + ']');
      { The real question: does what it wrote still parse? }
      list := TStringList.Create;
      try
        { The ALL-CLEAR, not an empty list: TyOptDiagnose always says
          something, and "understood" is how it says there is nothing wrong.
          The old insert produced `xAxis.axisLabel: `, which fcl-json cannot
          read, so this came back as a parse complaint instead. }
        Check('and the document the editor wrote still parses',
          (Length(TyOptDiagnose(ed.Text)) = 1)
          and (Pos('understood', LowerCase(TyOptDiagnose(ed.Text)[0].Text)) > 0),
          'doc = <' + StringReplace(ed.Text, LineEnding, '|', [rfReplaceAll])
          + '> first: ' + TyOptDiagnose(ed.Text)[0].Text);
      finally
        list.Free;
      end;
    end
    else
      Check('there is a filter result to double-click', False);

    WriteLn('-- the doc pane follows the loaded catalogue --');
    { It used to read POSIX LANG, which the Lazarus IDE never sets and Windows
      does not have -- so the Chinese half of the catalogue, 2,252 nodes, was
      unreachable in the one place it is for. This machine runs an untranslated
      IDE, so the assertion is that ENGLISH comes back and comes back
      non-empty; the Chinese path is checked by the sentinel's own value. }
    TEdit(dlg.FindComponent('RefFilter')).Text := '';
    PumpFor(300);
    if tree.Items.Count > 0 then
    begin
      tree.Selected := tree.Items[0];
      if Assigned(tree.OnChange) then tree.OnChange(tree, tree.Items[0]);
      Application.ProcessMessages;
      Check('the doc pane says something about the selected node',
        Trim(TMemo(dlg.FindComponent('RefDoc')).Text) <> '',
        'doc pane empty');
    end;

    if (ParamCount >= 1) and (ParamStr(1) = '--show') then
    begin
      WriteLn;
      WriteLn('showing the dialog; close it to finish.');
      dlg.ShowModal;
    end;
  finally
    dlg.Free;
    spy.Free;
  end;
end;

begin
  Application.Initialize;
  WriteLn('AdvanceChart option editor -- real-machine probe');
  WriteLn;
  try
    Probe;
  except
    on E: Exception do
    begin
      Inc(GFails);
      WriteLn('  FAIL  the probe itself raised: ', E.ClassName, ': ', E.Message);
    end;
  end;
  WriteLn;
  WriteLn(Format('%d checks, %d failed', [GChecks, GFails]));
  if GFails > 0 then Halt(1);
end.
