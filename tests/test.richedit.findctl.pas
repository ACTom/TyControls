unit test.richedit.findctl;

{ TTyRichEdit's find and replace (Task 11b): Delphi's FindText and RichMemo's Search, the user's
  Find Next, ReplaceAll, and the find and the replace in the background - driven turn by turn
  through the control's seams as the load's driver is tested: the pieces a turn runs, their size
  by the clock, the progress, cancelling, a new start, every way it is stopped; the replace is
  one undo step, also cancelled midway, and its refusals are counted.

  Headless on the edit suite's probe (the clipboard double, the counters), but for one test that
  needs a window (a form never shown). No dialog, no clipboard, no input method. Every bound
  is a count, never a time. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, TypInfo, Forms, Graphics, fpcunit, testregistry,
  tyControls.Controller, tyControls.StrConsts,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite, tyControls.RichEdit.Attrs,
  tyControls.RichEdit.Find, tyControls.RichEdit,
  test.richedit.control, test.richedit.edit;

type
  TTyRichEditFindTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TEditProbe;
    FChanges, FSelChanges: Integer;
    FProgress: array of Int64;
    FProgressTotal: Int64;
    FCancelAt: Integer;
    FDone: array of string;
    FEditInHandler: Boolean;
    procedure Changed(Sender: TObject);
    procedure SelChanged(Sender: TObject);
    procedure Progress(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    procedure FindDone(Sender: TObject; AFound, ACancelled: Boolean);
    procedure ReplaceDone(Sender: TObject; AReplaced, ASkipped: Integer; ACancelled: Boolean);
    procedure ResetEvents;
    procedure SetText(const S: string);
    procedure LoadBytes(const B: TBytes; AFinish: Boolean = True);
    function Text: string;
    function TurnUntilDone(AMax: Integer = 100000): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // the brief's
    procedure TestReplaceAllIsOneUndoStepAndCancels;
    // the synchronous calls
    procedure TestFindTextIsDelphis;
    procedure TestSearchIsRichMemos;
    procedure TestTheSynchronousCallsWaitOverTheThreshold;
    procedure TestFindNextSelectsAndWraps;
    procedure TestFindNextIntoTheHiddenTail;
    procedure TestReplaceAllIsOneStepThatPutsTheSelectionBack;
    procedure TestReplaceAllTakesTheFirstFormatAndNeverOverlaps;
    procedure TestReplaceAllSkipsWhatTheDocumentRefuses;
    procedure TestReplaceAllUndoneSavesTheFile;
    // in the background
    procedure TestABackgroundFindRunsInTheTurns;
    procedure TestTheClockSizesTheFindsPieces;
    procedure TestEveryWayABackgroundFindStops;
    procedure TestABackgroundFindWhileLoading;
    procedure TestABackgroundReplaceIsOneStepThroughTheUsersMoves;
    procedure TestABackgroundReplaceStopsAtAnEditAndASave;
    procedure TestTheWindowGoingStopsIt;
    procedure TestTheEventsArePublished;
  end;

  // the control's protected seams (the find's piece and batch, the first slice)
  TFindAccess = class(TTyCustomRichEdit)
  end;

implementation

const
  BS = #92;

var
  GWidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if GWidgetSetReady then Exit;
  Forms.Application.Initialize;
  GWidgetSetReady := True;
end;

function FileBytes(const APath: string): TBytes;
var
  f: TFileStream;
begin
  Result := nil;
  f := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, f.Size);
    if f.Size > 0 then f.ReadBuffer(Result[0], f.Size);
  finally
    f.Free;
  end;
end;

function FixtureFile(const AName: string): TBytes;
begin
  Result := FileBytes(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim +
    'fixtures' + PathDelim + 'rtf' + PathDelim + AName);
end;

function BytesOf(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[0], Length(S));
end;

{ RTF written with '|' for the backslash. }
function Rtf(const S: RawByteString): RawByteString;
var
  i: Integer;
begin
  Result := S;
  for i := 1 to Length(Result) do
    if Result[i] = '|' then Result[i] := BS;
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

{ ---- set up ---- }

procedure TTyRichEditFindTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FRich := TEditProbe.Create(nil);
  FRich.Controller := FCtl;
  FRich.Font.PixelsPerInch := 96;
  FRich.SetBounds(0, 0, 400, 300);
  FRich.OnChange := @Changed;
  FRich.OnSelectionChange := @SelChanged;
  FRich.OnFindProgress := @Progress;
  FRich.OnFindDone := @FindDone;
  FRich.OnReplaceDone := @ReplaceDone;
  FRich.ResetCounts;
  ResetEvents;
end;

procedure TTyRichEditFindTest.TearDown;
begin
  FreeAndNil(FRich);
  FreeAndNil(FCtl);
end;

procedure TTyRichEditFindTest.Changed(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TTyRichEditFindTest.SelChanged(Sender: TObject);
begin
  Inc(FSelChanges);
end;

procedure TTyRichEditFindTest.Progress(Sender: TObject; ADone, ATotal: Int64;
  var ACancel: Boolean);
begin
  SetLength(FProgress, Length(FProgress) + 1);
  FProgress[High(FProgress)] := ADone;
  FProgressTotal := ATotal;
  if (FCancelAt > 0) and (Length(FProgress) >= FCancelAt) then ACancel := True;
  if FEditInHandler then
  begin
    FEditInHandler := False;
    FRich.Document.Execute(TTyRichInsertText.Create(0, 'x'));
  end;
end;

procedure TTyRichEditFindTest.FindDone(Sender: TObject; AFound, ACancelled: Boolean);
begin
  SetLength(FDone, Length(FDone) + 1);
  FDone[High(FDone)] := Format('find %s %s', [BoolToStr(AFound, 'found', 'none'),
    BoolToStr(ACancelled, 'cancelled', 'ended')]);
end;

procedure TTyRichEditFindTest.ReplaceDone(Sender: TObject; AReplaced, ASkipped: Integer;
  ACancelled: Boolean);
begin
  SetLength(FDone, Length(FDone) + 1);
  FDone[High(FDone)] := Format('replace %d %d %s', [AReplaced, ASkipped,
    BoolToStr(ACancelled, 'cancelled', 'ended')]);
end;

procedure TTyRichEditFindTest.ResetEvents;
begin
  FChanges := 0;
  FSelChanges := 0;
  FProgress := nil;
  FProgressTotal := 0;
  FCancelAt := 0;
  FDone := nil;
  FEditInHandler := False;
  FRich.ResetCounts;
  FRich.Waits := 0;
  FRich.WaitEnds := 0;
end;

procedure TTyRichEditFindTest.SetText(const S: string);
begin
  FRich.Lines.Text := S;
  FRich.UpdateView;
  ResetEvents;
end;

procedure TTyRichEditFindTest.LoadBytes(const B: TBytes; AFinish: Boolean);
var
  st: TBytesStream;
begin
  st := TBytesStream.Create(B);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  if AFinish then FRich.FinishLoading;
  FRich.UpdateView;
  ResetEvents;
end;

function TTyRichEditFindTest.Text: string;
begin
  Result := FRich.Document.Text.GetText(0, FRich.Document.Text.Length);
end;

{ Turns by hand until the background find or replace has ended; the turns it took. }
function TTyRichEditFindTest.TurnUntilDone(AMax: Integer): Integer;
begin
  Result := 0;
  while FRich.FindRunning and (Result < AMax) do
  begin
    FRich.Turn;
    Inc(Result);
  end;
  AssertFalse('it ended', FRich.FindRunning);
end;

function Lines(ACount: Integer; const ALine: string): string;
var
  i: Integer;
  sb: TStringBuilder;
begin
  sb := TStringBuilder.Create;
  try
    for i := 0 to ACount - 1 do
    begin
      sb.Append(ALine);
      sb.Append(IntToStr(i));
      sb.Append(#10);
    end;
    Result := sb.ToString;
  finally
    sb.Free;
  end;
end;

{ ---- the brief's ---- }

{ A replace in the background cancelled midway: what it replaced so far stays, as ONE undo step
  - which takes it all back, and puts the selection back. }
procedure TTyRichEditFindTest.TestReplaceAllIsOneUndoStepAndCancels;
var
  before: string;
  turns: Integer;
begin
  SetText(Lines(2000, 'a cat sat here '));
  before := Text;
  FRich.SelStart := 5;
  FRich.SelLength := 3;
  ResetEvents;
  FRich.ReplaceAllAsync('cat', 'dog');
  TFindAccess(FRich).ReplaceBatch := 100;
  turns := 0;
  // through the find, and some batches in
  while FRich.FindRunning and (Pos('dog', Text) = 0) and (turns < 10000) do
  begin
    FRich.Turn;
    Inc(turns);
  end;
  FRich.Turn;
  AssertTrue('still running', FRich.FindRunning);
  AssertTrue('some replaced', Pos('dog', Text) > 0);
  AssertTrue('not all', Pos('cat', Text) > 0);
  FRich.CancelFind;
  AssertFalse('stopped', FRich.FindRunning);
  AssertEquals('one event', 1, Length(FDone));
  AssertTrue('cancelled, with what it replaced: ' + FDone[0],
    (Pos('replace ', FDone[0]) = 1) and (Pos(' 0 cancelled', FDone[0]) > 0) and
    (Pos('replace 0 ', FDone[0]) = 0));
  AssertEquals('one undo step', 1, FRich.Document.UndoDepth);
  AssertEquals('named', rsRichUndoReplace, FRich.Document.UndoDescription);
  FRich.Undo;
  AssertEquals('undone at once', before, Text);
  AssertEquals('the selection back: start', 5, FRich.SelStart);
  AssertEquals('the selection back: length', 3, FRich.SelLength);
  AssertEquals('nothing more to undo', 0, FRich.Document.UndoDepth);
  // and not cancelled: all of them, one step
  ResetEvents;
  FRich.ReplaceAllAsync('cat', 'dog');
  TurnUntilDone;
  AssertEquals('done', 'replace 2000 0 ended', FDone[0]);
  AssertEquals('no cat left', 0, Pos('cat', Text));
  AssertEquals('one step again', 1, FRich.Document.UndoDepth);
  FRich.Undo;
  AssertEquals('undone again', before, Text);
end;

{ ---- the synchronous calls ---- }

procedure TTyRichEditFindTest.TestFindTextIsDelphis;
begin
  SetText('Cat cat CAT concat cat.');
  FRich.SelStart := 2;
  ResetEvents;
  AssertEquals('none', 0, FRich.FindText('cat', 0, -1, []));
  AssertEquals('match case', 4, FRich.FindText('cat', 0, -1, [stMatchCase]));
  AssertEquals('whole word from 9', 19, FRich.FindText('cat', 9, -1, [stWholeWord]));
  AssertEquals('both from 5', 19, FRich.FindText('cat', 5, -1, [stMatchCase, stWholeWord]));
  AssertEquals('inside a range', 8, FRich.FindText('cat', 5, 6, []));
  AssertEquals('the whole match inside', -1, FRich.FindText('cat', 5, 5, []));
  AssertEquals('a range past the end: to the end', 19, FRich.FindText('cat', 17, 1000, []));
  AssertEquals('not there', -1, FRich.FindText('dog', 0, -1, []));
  AssertEquals('a start past the end', -1, FRich.FindText('cat', 100, -1, []));
  AssertEquals('it selects nothing', 2, FRich.SelStart);
  AssertEquals('...and nothing is selected', 0, FRich.SelLength);
  AssertEquals('no selection report', 0, FSelChanges);
  AssertEquals('no change', 0, FChanges);
end;

procedure TTyRichEditFindTest.TestSearchIsRichMemos;
var
  s, n: TTyRichPos;
begin
  SetText('one two' + #10 + 'One two');
  AssertEquals('forward', 0, FRich.Search('one', 0, -1, []));
  AssertEquals('backward: the last', 8, FRich.Search('one', 0, -1, [soBackward]));
  AssertEquals('backward in a range', 0, FRich.Search('one', 0, 8, [soBackward]));
  AssertEquals('match case, backward', 0, FRich.Search('one', 0, -1, [soBackward, soMatchCase]));
  AssertEquals('whole word', -1, FRich.Search('on', 0, -1, [soWholeWord]));
  AssertEquals('across the paragraph end', 4, FRich.Search('two' + #13#10 + 'One', 0, -1, []));
  s := -1;
  n := -1;
  AssertTrue('the second form', FRich.Search('two' + #10 + 'one', 0, -1, [], s, n));
  AssertEquals('its start', 4, s);
  AssertEquals('its length: a paragraph end is one', 7, n);
  AssertFalse('none', FRich.Search('three', 0, -1, [], s, n));
  AssertEquals('left as it was', 4, s);
end;

procedure TTyRichEditFindTest.TestTheSynchronousCallsWaitOverTheThreshold;
begin
  SetText(Lines(100, 'abc '));
  FRich.SetCopyWait(100);
  ResetEvents;
  FRich.FindText('zzz', 0, 50, []);
  AssertEquals('a short range: no wait', 0, FRich.Waits);
  FRich.FindText('zzz', 0, -1, []);
  AssertEquals('a long one: the wait cursor', 1, FRich.Waits);
  AssertEquals('...put back', 1, FRich.WaitEnds);
  FRich.Search('zzz', 0, -1, []);
  AssertEquals('RichMemo''s too', 2, FRich.Waits);
  FRich.FindNext('abc 5');
  AssertEquals('Find Next over a long document', 3, FRich.Waits);
  FRich.ReplaceAll('abc', 'abd');
  AssertEquals('ReplaceAll: one wait', 4, FRich.Waits);
  AssertEquals('every one put back', FRich.Waits, FRich.WaitEnds);
  FRich.SetCopyWait(1000000);
  FRich.ReplaceAll('abd', 'abc');
  AssertEquals('under the threshold: none', 4, FRich.Waits);
end;

procedure TTyRichEditFindTest.TestFindNextSelectsAndWraps;
begin
  SetText('red green red blue red');
  FRich.ReadOnly := True;
  FRich.SelStart := 0;
  ResetEvents;
  AssertTrue('found', FRich.FindNext('red'));
  AssertEquals('the next after the caret', 0, FRich.SelStart);
  AssertEquals('selected', 3, FRich.SelLength);
  AssertEquals('one selection report', 1, FSelChanges);
  AssertEquals('the caret at its end', 3, FRich.CaretPos);
  AssertTrue('again', FRich.FindNext('red'));
  AssertEquals('after the selection', 10, FRich.SelStart);
  AssertTrue(FRich.FindNext('red'));
  AssertEquals('the last', 19, FRich.SelStart);
  AssertTrue('wraps', FRich.FindNext('red'));
  AssertEquals('from the start', 0, FRich.SelStart);
  FRich.SelStart := 20;
  AssertFalse('not wrapping: none after', FRich.FindNext('red', []));
  AssertEquals('the selection stays', 20, FRich.SelStart);
  AssertTrue('backward', FRich.FindNext('red', [rfoBackward]));
  AssertEquals('the one before the selection', 10, FRich.SelStart);
  AssertTrue(FRich.FindNext('red', [rfoBackward]));
  AssertEquals(0, FRich.SelStart);
  AssertFalse('backward, not wrapping', FRich.FindNext('red', [rfoBackward]));
  AssertTrue('backward, wrapping: the last', FRich.FindNext('red', [rfoBackward, rfoWrap]));
  AssertEquals(19, FRich.SelStart);
  AssertTrue('match case', not FRich.FindNext('RED', [rfoMatchCase, rfoWrap]));
  AssertTrue('whole word', FRich.FindNext('green', [rfoWholeWord, rfoWrap]));
  AssertEquals(4, FRich.SelStart);
  AssertEquals('nothing changed', 0, FRich.Document.UndoDepth);
end;

procedure TTyRichEditFindTest.TestFindNextIntoTheHiddenTail;
var
  s: string;
begin
  // one paragraph longer than the layout shows (CRichMaxParaLayoutChars): its tail is text
  s := StringOfChar('a', 100050) + ' needle';
  SetText(s);
  FRich.SelStart := 0;
  ResetEvents;
  AssertTrue('found in the hidden tail', FRich.FindNext('needle'));
  AssertEquals('selected where it is', 100051, FRich.SelStart);
  AssertEquals('...all of it', 6, FRich.SelLength);
  AssertEquals('FindText too', 100051, FRich.FindText('needle', 0, -1, []));
end;

procedure TTyRichEditFindTest.TestReplaceAllIsOneStepThatPutsTheSelectionBack;
var
  skipped: Integer;
begin
  SetText('one cat' + #10 + 'two cats' + #10 + 'cat');
  FRich.SelStart := 1;
  // typing before it: never merged with it
  FRich.Key8('x');
  FRich.ReadOnly := True;
  FRich.SelStart := 1;
  FRich.SelLength := 2;
  ResetEvents;
  AssertEquals('three', 3, FRich.ReplaceAll('cat', 'dog', [], skipped));
  AssertEquals('none skipped', 0, skipped);
  AssertEquals('replaced, ReadOnly or not (the document API)', 'oxne dog' + #10 +
    'two dogs' + #10 + 'dog', StringReplace(Text, #13#10, #10, [rfReplaceAll]));
  AssertEquals('one change', 1, FChanges);
  AssertEquals('two steps: the typing and the replace', 2, FRich.Document.UndoDepth);
  FRich.ReadOnly := False;
  FRich.Undo;
  AssertTrue('the replace undone alone', Pos('cat', Text) > 0);
  AssertTrue('the typing stays', Pos('oxne', Text) = 1);
  AssertEquals('the selection back', 1, FRich.SelStart);
  AssertEquals('...its length', 2, FRich.SelLength);
  // nothing found: nothing done
  ResetEvents;
  AssertEquals('none', 0, FRich.ReplaceAll('zebra', 'x'));
  AssertEquals('no change', 0, FChanges);
end;

procedure TTyRichEditFindTest.TestReplaceAllTakesTheFirstFormatAndNeverOverlaps;
var
  runs: TTyRunArray;
  r: Integer;
begin
  LoadBytes(BytesOf(Rtf('{|rtf1|ansi|deff0{|fonttbl{|f0 Arial;}}|pard one {|b cat} two {|i cAt}|par}')));
  AssertEquals('two', 2, FRich.ReplaceAll('cat', 'tiger'));
  runs := FRich.Document.RunsOf(0);
  r := High(runs);
  while runs[r].Start > 4 do Dec(r);
  AssertTrue('the bold one bold', fsBold in FRich.Document.Formats.CharFormat(runs[r].Format).Style);
  r := High(runs);
  while runs[r].Start > 14 do Dec(r);
  AssertTrue('the italic one italic', fsItalic in FRich.Document.Formats.CharFormat(runs[r].Format).Style);
  // a replacement is never matched again; overlapping matches: the leftmost, then after it
  SetText('a b aa');
  AssertEquals('each "a" once', 3, FRich.ReplaceAll('a', 'aa'));
  AssertEquals('aa b aaaa', Text);
  SetText('aaaaa');
  AssertEquals('leftmost, not overlapping', 2, FRich.ReplaceAll('aa', 'b'));
  AssertEquals('bba', Text);
  SetText('cat Cat CAT');
  AssertEquals('match case', 1, FRich.ReplaceAll('Cat', 'x', [rfoMatchCase]));
  AssertEquals('cat x CAT', Text);
  AssertEquals('whole word', 0, FRich.ReplaceAll('ca', 'x', [rfoWholeWord]));
end;

procedure TTyRichEditFindTest.TestReplaceAllSkipsWhatTheDocumentRefuses;
var
  d: TTyRichDocument;
  k, nested, all, skipped, done: Integer;
  c: TTyRichCell;
  f: TTyRichFinder;
  needle: string;
  b: TBytes;
  s: RawByteString;
begin
  // a row that holds a nested table: a character of its text, wherever it is
  LoadBytes(FixtureFile('word-table-merged.rtf'));
  d := FRich.Document;
  needle := '';
  d.BeginRead;
  try
    for k := 0 to d.Text.ParaCount - 1 do
    begin
      c := d.CellAt(k);
      if (c <> nil) and c.Row.HoldsNestedTable and (d.Text.ParaLength(k) > 0) then
      begin
        needle := d.Text.GetText(d.Text.ParaStart(k), 1);
        Break;
      end;
    end;
  finally
    d.EndRead;
  end;
  AssertTrue('the fixture has text in a nested row', needle <> '');
  f := TTyRichFinder.Create(d, needle, [rfoMatchCase]);
  try
    f.Collect := True;
    f.Run;
    all := f.MatchCount;
    nested := 0;
    d.BeginRead;
    try
      for k := 0 to f.MatchCount - 1 do
      begin
        c := d.CellAt(d.Text.ParaOfPos(f.Match(k)));
        if (c <> nil) and c.Row.HoldsNestedTable then Inc(nested);
      end;
    finally
      d.EndRead;
    end;
  finally
    f.Free;
  end;
  AssertTrue('matches in nested rows', nested > 0);
  done := FRich.ReplaceAll(needle, 'E', [rfoMatchCase], skipped);
  AssertEquals('those skipped', nested, skipped);
  AssertEquals('the others replaced', all - nested, done);
  AssertEquals('one step, or none when nothing went in', Ord(done > 0), d.UndoDepth);
  // the same in a document whose nested row shares its words with other paragraphs
  b := BytesOf(Rtf('{|rtf1|ansi|deff0{|fonttbl{|f0 Arial;}}|pard word one|par' +
    '|trowd|cellx2000|cellx4000|pard|intbl word two|cell' +
    '|pard|intbl|itap2 word nested|nestcell{|*|nesttableprops|trowd|cellx1000|nestrow}{|nonesttables|par}' +
    '|pard|intbl|cell|row|pard word three|par}'));
  LoadBytes(b);
  d := FRich.Document;
  nested := 0;
  d.BeginRead;
  try
    for k := 0 to d.Text.ParaCount - 1 do
    begin
      c := d.CellAt(k);
      if (c <> nil) and c.Row.HoldsNestedTable and
        (Pos('word', d.Text.GetText(d.Text.ParaStart(k), d.Text.ParaLength(k))) > 0) then
        Inc(nested);
    end;
  finally
    d.EndRead;
  end;
  AssertTrue('a nested row with the word', nested > 0);
  done := FRich.ReplaceAll('word', 'w', [], skipped);
  AssertEquals('the nested row''s skipped', nested, skipped);
  AssertTrue('the others replaced', done >= 2);
  AssertEquals('one step', 1, d.UndoDepth);
  // across cells (R57)
  LoadBytes(FixtureFile('re-zh-table.rtf'));
  d := FRich.Document;
  k := 0;
  while (k < d.Text.ParaCount - 1) and not ((d.CellAt(k) <> nil) and (d.CellAt(k + 1) <> nil) and
    (d.Text.ParaLength(k) > 0) and (d.Text.ParaLength(k + 1) > 0)) do
    Inc(k);
  needle := d.Text.GetText(d.Text.ParaStart(k), d.Text.ParaLength(k)) + #10 +
    d.Text.GetText(d.Text.ParaStart(k + 1), d.Text.ParaLength(k + 1));
  AssertEquals('found across the cells', d.Text.ParaStart(k), FRich.FindText(needle, 0, -1, []));
  AssertEquals('not replaced', 0, FRich.ReplaceAll(needle, 'x', [], skipped));
  AssertEquals('skipped', 1, skipped);
  AssertEquals('no step', 0, d.UndoDepth);
  // a document still loading: every match left, counted
  s := Rtf('{|rtf1|ansi|deff0{|fonttbl{|f0 Arial;}}|pard ');
  for k := 0 to 3999 do s := s + 'a line with a word ' + IntToStr(k) + Rtf('|par ');
  s := s + '}';
  b := BytesOf(s);
  TFindAccess(FRich).FirstSliceBytes := 16 * 1024;
  LoadBytes(b, False);
  AssertTrue('loading', FRich.Loading);
  all := FRich.Document.Text.ParaCount - 1;
  AssertEquals('nothing replaced', 0, FRich.ReplaceAll('word', 'x', [], skipped));
  AssertTrue('the matches loaded so far skipped', skipped >= all - 1);
  AssertEquals('no change', 0, FChanges);
  FRich.FinishLoading;
end;

procedure TTyRichEditFindTest.TestReplaceAllUndoneSavesTheFile;
var
  b, saved: TBytes;
  m: TBytesStream;
begin
  b := FixtureFile('hand-word-zh.rtf');
  LoadBytes(b);
  AssertTrue('replaced', FRich.ReplaceAll('e', 'EE') > 0);
  FRich.Undo;
  m := TBytesStream.Create;
  try
    FRich.SaveToStream(m, rfRtf);
    saved := Copy(m.Bytes, 0, m.Size);
  finally
    m.Free;
  end;
  AssertTrue('undone and saved: the file', SameBytes(b, saved));
end;

{ ---- in the background ---- }

procedure TTyRichEditFindTest.TestABackgroundFindRunsInTheTurns;
var
  turns, i, before: Integer;
  steps: Int64;
begin
  SetText(Lines(20000, 'filler words ') + 'the needle');
  FRich.SelStart := 0;
  ResetEvents;
  FRich.FindNextAsync('needle');
  AssertEquals('a find starts small', CRichFindMinStepChars, TFindAccess(FRich).FindSlice);
  TFindAccess(FRich).FindSlice := 4096;
  AssertTrue('running', FRich.FindRunning);
  AssertEquals('nothing selected yet', 0, FRich.SelLength);
  turns := 0;
  steps := 0;
  while FRich.FindRunning and (turns < 100000) do
  begin
    before := Length(FProgress);
    FRich.Turn;
    Inc(turns);
    AssertTrue('at most the cap of pieces a turn', Length(FProgress) - before <= CRichIdleMaxSteps);
    Inc(steps, Length(FProgress) - before);
  end;
  AssertTrue(Format('in several turns (%d)', [turns]), turns > 3);
  AssertEquals('found', 'find found ended', FDone[0]);
  AssertEquals('selected', FRich.Document.Text.Length - 6, FRich.SelStart);
  AssertEquals(6, FRich.SelLength);
  for i := 1 to High(FProgress) do
    AssertTrue('progress never goes back', FProgress[i] >= FProgress[i - 1]);
  AssertTrue('within its total', FProgress[High(FProgress)] <= FProgressTotal);
  AssertFalse('no background work left', TFindAccess(FRich).HasBackgroundWork);
  // not found, wrapping: two legs, then the end
  ResetEvents;
  FRich.SelStart := 10;
  FRich.FindNextAsync('zebra');
  TurnUntilDone;
  AssertEquals('not found', 'find none ended', FDone[0]);
  AssertEquals('the selection stays', 10, FRich.SelStart);
  // backward
  ResetEvents;
  FRich.SelStart := 30;
  FRich.FindNextAsync('filler', [rfoBackward]);
  TurnUntilDone;
  AssertEquals('found backward', 'find found ended', FDone[0]);
  AssertTrue('the one before', FRich.SelStart < 30);
  AssertEquals(FRich.FindText('filler', 14, -1, []), FRich.SelStart);
end;

procedure TTyRichEditFindTest.TestTheClockSizesTheFindsPieces;
var
  before, i: Integer;
  s0: Int64;
begin
  SetText(Lines(100000, 'filler words ') + 'the needle');
  FRich.SelStart := 0;
  ResetEvents;
  FRich.OnFindProgress := nil;
  // a clock that moves 10 ms a reading: one piece a turn, and the pieces halve to the least
  FRich.FakeClock := True;
  FRich.ClockStep := 10;
  FRich.FindNextAsync('needle');
  TFindAccess(FRich).FindSlice := 256 * 1024;
  s0 := TFindAccess(FRich).FindSlice;
  FRich.Turn;
  AssertEquals('halved after a slow turn', s0 div 2, TFindAccess(FRich).FindSlice);
  for i := 0 to 20 do FRich.Turn;
  AssertEquals('down to the least', CRichFindMinStepChars, TFindAccess(FRich).FindSlice);
  // a clock that stands: the cap of pieces a turn, and the pieces double to the most
  FRich.ClockStep := 0;
  FRich.OnFindProgress := @Progress;
  before := Length(FProgress);
  FRich.Turn;
  if FRich.FindRunning then
    AssertEquals('the cap of pieces', CRichIdleMaxSteps, Length(FProgress) - before);
  AssertTrue('doubled after a fast turn', TFindAccess(FRich).FindSlice > CRichFindMinStepChars);
  FRich.FakeClock := False;
  FRich.CancelFind;
end;

procedure TTyRichEditFindTest.TestEveryWayABackgroundFindStops;
begin
  SetText(Lines(20000, 'filler words ') + 'the needle');
  // CancelFind
  ResetEvents;
  FRich.FindNextAsync('needle');
  FRich.Turn;
  FRich.CancelFind;
  AssertFalse('CancelFind', FRich.FindRunning);
  AssertEquals('...told', 'find none cancelled', FDone[0]);
  AssertFalse('...no work left', TFindAccess(FRich).HasBackgroundWork);
  FRich.CancelFind;
  AssertEquals('...once', 1, Length(FDone));
  // the progress handler
  ResetEvents;
  FCancelAt := 2;
  FRich.FindNextAsync('needle');
  TurnUntilDone;
  AssertEquals('ACancel', 'find none cancelled', FDone[0]);
  AssertEquals('...at its second piece', 2, Length(FProgress));
  // a second start stops the first
  ResetEvents;
  FRich.FindNextAsync('needle');
  FRich.Turn;
  FRich.FindNextAsync('filler');
  AssertEquals('the first told', 'find none cancelled', FDone[0]);
  AssertTrue('the second runs', FRich.FindRunning);
  TurnUntilDone;
  AssertEquals('the second found', 'find found ended', FDone[1]);
  // an edit: noticed at the next piece
  ResetEvents;
  FRich.SelStart := 0;
  FRich.FindNextAsync('needle');
  FRich.Turn;
  FRich.Document.Execute(TTyRichInsertText.Create(0, 'x'));
  AssertTrue('still running until its next piece', FRich.FindRunning);
  FRich.Turn;
  AssertFalse('an edit stops it', FRich.FindRunning);
  AssertEquals('...told', 'find none cancelled', FDone[0]);
  // an undo too
  ResetEvents;
  FRich.FindNextAsync('needle');
  FRich.Turn;
  FRich.Undo;
  FRich.Turn;
  AssertFalse('an undo stops it', FRich.FindRunning);
  // an edit made in its own progress handler
  ResetEvents;
  FEditInHandler := True;
  FRich.FindNextAsync('needle');
  FRich.Turn;
  FRich.Turn;
  AssertFalse('an edit in the handler stops it', FRich.FindRunning);
  // a new content: quietly
  ResetEvents;
  FRich.FindNextAsync('needle');
  FRich.Turn;
  FRich.Lines.Text := 'other';
  AssertFalse('a new content stops it', FRich.FindRunning);
  AssertEquals('...quietly', 0, Length(FDone));
  // the control's end: quietly, nothing left
  SetText(Lines(2000, 'filler words '));
  FRich.FindNextAsync('needle');
  FRich.Turn;
  FreeAndNil(FRich);
  AssertEquals('the end: no event', 0, Length(FDone));
  FRich := TEditProbe.Create(nil);
  FRich.Controller := FCtl;
end;

procedure TTyRichEditFindTest.TestABackgroundFindWhileLoading;
var
  s: RawByteString;
  k, loadTurns: Integer;
  waited: Boolean;
begin
  s := Rtf('{|rtf1|ansi|deff0{|fonttbl{|f0 Arial;}}|pard ');
  for k := 0 to 9999 do s := s + 'a filler line ' + IntToStr(k) + Rtf('|par ');
  s := s + Rtf('the needle|par}');
  TFindAccess(FRich).FirstSliceBytes := 16 * 1024;
  TFindAccess(FRich).StepBytes := 16 * 1024;
  LoadBytes(BytesOf(s), False);
  AssertTrue('loading', FRich.Loading);
  AssertEquals('FindText: not in what is loaded yet', -1, FRich.FindText('needle', 0, -1, []));
  FRich.SelStart := 0;
  ResetEvents;
  FRich.FindNextAsync('needle', []);
  loadTurns := 0;
  waited := False;
  while FRich.FindRunning and (loadTurns < 100000) do
  begin
    if (TFindAccess(FRich).Finder <> nil) and TFindAccess(FRich).Finder.Waiting then waited := True;
    FRich.Turn;
    Inc(loadTurns);
  end;
  AssertTrue('it waited for the load', waited);
  AssertFalse('the load ended', FRich.Loading);
  AssertEquals('found as the load went on', 'find found ended', FDone[0]);
  AssertEquals('selected', FRich.FindText('needle', 0, -1, []), FRich.SelStart);
end;

procedure TTyRichEditFindTest.TestABackgroundReplaceIsOneStepThroughTheUsersMoves;
var
  before: string;
  turns: Integer;
begin
  SetText(Lines(1000, 'a cat sat here '));
  before := Text;
  ResetEvents;
  FRich.ReplaceAllAsync('cat', 'dog');
  TFindAccess(FRich).ReplaceBatch := 50;
  turns := 0;
  while FRich.FindRunning and (Pos('dog', Text) = 0) and (turns < 10000) do
  begin
    FRich.Turn;
    Inc(turns);
  end;
  // the user moves the caret and the focus leaves while it replaces: still one step
  FRich.SelStart := 3;
  FRich.Leave;
  FRich.SelStart := 7;
  TurnUntilDone;
  AssertEquals('done', 'replace 1000 0 ended', FDone[0]);
  AssertEquals('one step', 1, FRich.Document.UndoDepth);
  // and the typing after it is a step of its own, which does not merge into it
  FRich.Key8('z');
  AssertEquals('typing: a step of its own', 2, FRich.Document.UndoDepth);
  FRich.Undo;
  FRich.Undo;
  AssertEquals('both undone', before, Text);
  // a break of the run from code between two batches: that batch goes back out, it ends
  ResetEvents;
  FRich.ReplaceAllAsync('cat', 'dog');
  turns := 0;
  while FRich.FindRunning and (Pos('dog', Text) = 0) and (turns < 10000) do
  begin
    FRich.Turn;
    Inc(turns);
  end;
  TFindAccess(FRich).ReplaceBatch := 50;
  FRich.Document.BreakMerge;
  FRich.Turn;
  AssertFalse('it ended', FRich.FindRunning);
  AssertTrue('cancelled', Pos('cancelled', FDone[0]) > 0);
  AssertEquals('still one step', 1, FRich.Document.UndoDepth);
  FRich.Undo;
  AssertEquals('undone at once', before, Text);
end;

procedure TTyRichEditFindTest.TestABackgroundReplaceStopsAtAnEditAndASave;
var
  m: TMemoryStream;
  turns: Integer;
begin
  SetText(Lines(1000, 'a cat sat here '));
  // an edit
  ResetEvents;
  FRich.ReplaceAllAsync('cat', 'dog');
  TFindAccess(FRich).ReplaceBatch := 50;
  turns := 0;
  while FRich.FindRunning and (Pos('dog', Text) = 0) and (turns < 10000) do
  begin
    FRich.Turn;
    Inc(turns);
  end;
  FRich.Key8('q');
  FRich.Turn;
  AssertFalse('an edit stops it', FRich.FindRunning);
  AssertTrue('told: ' + FDone[0], Pos('cancelled', FDone[0]) > 0);
  AssertEquals('the replace and the typing', 2, FRich.Document.UndoDepth);
  // a save
  ResetEvents;
  FRich.ReplaceAllAsync('cat', 'dog');
  FRich.Turn;
  m := TMemoryStream.Create;
  try
    FRich.SaveToStream(m, rfText);
  finally
    m.Free;
  end;
  AssertFalse('a save stops it', FRich.FindRunning);
  AssertTrue('told', Pos('cancelled', FDone[0]) > 0);
  // the composition: no batch goes in while it composes (the seam: CommitComposition's
  // counterpart is a test of the IME suite; here the document's update holds it)
  ResetEvents;
  FRich.ReplaceAllAsync('sat', 'stood');
  FRich.Document.BeginUpdate;
  try
    turns := 0;
    while FRich.FindRunning and (turns < 2000) do
    begin
      FRich.Turn;
      Inc(turns);
    end;
    AssertTrue('waits while the document holds its changes back', FRich.FindRunning);
    AssertTrue('nothing replaced meanwhile', Pos('stood', Text) = 0);
  finally
    FRich.Document.EndUpdate;
  end;
  TurnUntilDone;
  AssertTrue('then it went on', Pos('stood', Text) > 0);
end;

procedure TTyRichEditFindTest.TestTheWindowGoingStopsIt;
var
  F: TForm;
begin
  NeedWidgetSet;
  F := TForm.CreateNew(nil);
  try
    FRich.Parent := F;
    F.HandleNeeded;
    FRich.HandleNeeded;
    AssertTrue('a handle', FRich.HandleAllocated);
    SetText(Lines(5000, 'filler words '));
    FRich.FindNextAsync('needle');
    AssertTrue('the driver is on', FRich.IdleOn or FRich.TurnQueued or (FRich.TimerOf <> nil));
    FRich.DropHandle;
    AssertFalse('the window going stops it', FRich.FindRunning);
    AssertEquals('...quietly', 0, Length(FDone));
    AssertFalse('and its driver', FRich.IdleOn);
  finally
    FRich.Parent := nil;
    F.Free;
  end;
end;

procedure TTyRichEditFindTest.TestTheEventsArePublished;
begin
  AssertTrue('OnFindProgress', IsPublishedProp(TTyRichEdit, 'OnFindProgress'));
  AssertTrue('OnFindDone', IsPublishedProp(TTyRichEdit, 'OnFindDone'));
  AssertTrue('OnReplaceDone', IsPublishedProp(TTyRichEdit, 'OnReplaceDone'));
end;

initialization
  RegisterTest(TTyRichEditFindTest);
end.
