unit test.richedit.findctl;

{ TTyRichEdit's find and replace: Delphi's FindText and RichMemo's Search, the user's
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
  tyControls.Controller, tyControls.StrConsts, tyControls.Painter,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite, tyControls.RichEdit.Attrs,
  tyControls.RichEdit.Find, tyControls.RichEdit, tyControls.RichEdit.TextIO,
  test.richedit.control, test.richedit.edit,
  test.danglingrefs;                 // BeginPoison / EndPoison

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
    FDonePos, FDoneLen: TTyRichPos;
    FDoneProgress: Int64;           // the last progress before the done-event
    FProgressLast: Int64;
    FProgressTask: TTyRichFindTask;
    FReplaceResult: TTyRichReplaceResult;
    FRestartFrom: Integer;          // 1: the progress handler starts FRestartWith, 2: the done one
    FRestartWith: string;
    FEditInHandler, FEditInChange: Boolean;
    FFreeIn: Integer;               // 1: the progress handler frees the control, 2: the done one
    FCancelInProgress: Boolean;     // the progress handler calls CancelFind, once
    FSeenInHandler: string;         // what that call raised into the handler ('': nothing)
    FHandlerWentOn: Boolean;        // ... and the handler ran on after it
    procedure Changed(Sender: TObject);
    procedure SelChanged(Sender: TObject);
    procedure ChangedEdit(Sender: TObject);
    procedure Progress(Sender: TObject; ATask: TTyRichFindTask; ADone, ATotal: Int64;
      var ACancel: Boolean);
    procedure FindDone(Sender: TObject; AEnd: TTyRichFindEnd; APos, ALen: TTyRichPos);
    procedure ReplaceDone(Sender: TObject; const AResult: TTyRichReplaceResult);
    procedure ResetEvents;
    procedure SetText(const S: string);
    procedure LoadBytes(const B: TBytes; AFinish: Boolean = True);
    function Text: string;
    function TurnUntilDone(AMax: Integer = 100000): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
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
    procedure TestABackgroundReplaceTrimsALazyFile;
    procedure TestTheWindowMadeAgainDoesNotStopIt;
    procedure TestANewContentTellsTheFindItEnded;
    procedure TestFindNextNeverStandsStill;
    procedure TestAFindStartedFromItsHandler;
    procedure TestWrapReadsOnceAndIntegersCompile;
    procedure TestTheProgressEndsAtItsTotal;
    procedure TestTheEventsArePublished;
    procedure TestALongNeedleWithAParagraphEndEnds;
    procedure TestAReplaceGoesOnWhereItStopped;
    procedure TestTheWordBoundaryIsTheLineBreakers;
    procedure TestAHandlerMayFreeTheControl;
    procedure TestAReplaceOfAnIncompleteDocumentCountsInPieces;
    procedure TestAStoppedReplaceKeepsOnlyItsRecord;
    procedure TestAReplaceUndoneTellsItsStart;
    procedure TestAReplaceLetGoBetweenTwoTurnsIsNotDone;
    procedure TestTheHistoryLetsGoOfARunningReplacesStep;
    procedure TestAReplaceGoesOnBetweenTouchingWholeWords;
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

procedure TTyRichEditFindTest.ChangedEdit(Sender: TObject);
begin
  Inc(FChanges);
  if not FEditInChange then Exit;
  FEditInChange := False;
  FRich.Document.Execute(TTyRichInsertText.Create(0, 'Q'));
end;

procedure TTyRichEditFindTest.Progress(Sender: TObject; ATask: TTyRichFindTask; ADone,
  ATotal: Int64; var ACancel: Boolean);
begin
  if FFreeIn = 1 then
  begin
    FFreeIn := 0;
    SetLength(FDone, Length(FDone) + 1);
    FDone[High(FDone)] := 'freed';
    FreeAndNil(FRich);
    Exit;
  end;
  if FCancelInProgress then
  begin
    { A public call of the control made from a handler; the done-event it raises frees the
      control (FFreeIn = 2). The call returns to this handler - no exception of the control's
      comes through here. }
    FCancelInProgress := False;
    try
      FRich.CancelFind;
    except
      on E: Exception do FSeenInHandler := E.ClassName + ': ' + E.Message;
    end;
    FHandlerWentOn := True;
    Exit;
  end;
  FProgressTask := ATask;
  SetLength(FProgress, Length(FProgress) + 1);
  FProgress[High(FProgress)] := ADone;
  FProgressTotal := ATotal;
  FProgressLast := ADone;
  if FRestartFrom = 1 then
  begin
    FRestartFrom := 0;
    if FRestartWith = '' then FRich.ReplaceAllAsync('beta', 'BETA')
    else FRich.FindNextAsync(FRestartWith, []);
  end;
  if (FCancelAt > 0) and (Length(FProgress) >= FCancelAt) then ACancel := True;
  if FEditInHandler then
  begin
    FEditInHandler := False;
    FRich.Document.Execute(TTyRichInsertText.Create(0, 'x'));
  end;
end;

procedure TTyRichEditFindTest.FindDone(Sender: TObject; AEnd: TTyRichFindEnd; APos, ALen: TTyRichPos);
begin
  if FFreeIn = 2 then
  begin
    FFreeIn := 0;
    SetLength(FDone, Length(FDone) + 1);
    FDone[High(FDone)] := 'freed';
    FreeAndNil(FRich);
    Exit;
  end;
  SetLength(FDone, Length(FDone) + 1);
  case AEnd of
    rfeFound: FDone[High(FDone)] := 'find found ended';
    rfeNotFound: FDone[High(FDone)] := 'find none ended';
    rfeCancelled: FDone[High(FDone)] := 'find none cancelled';
  else
    FDone[High(FDone)] := 'find ?';
  end;
  FDonePos := APos;
  FDoneLen := ALen;
  FDoneProgress := FProgressLast;
  if FRestartFrom = 2 then
  begin
    FRestartFrom := 0;
    FRich.FindNextAsync(FRestartWith, []);
  end;
end;

procedure TTyRichEditFindTest.ReplaceDone(Sender: TObject; const AResult: TTyRichReplaceResult);
var
  s: string;
begin
  if FFreeIn = 2 then
  begin
    FFreeIn := 0;
    SetLength(FDone, Length(FDone) + 1);
    FDone[High(FDone)] := 'freed';
    FreeAndNil(FRich);
    Exit;
  end;
  case AResult.Ending of
    rreDone: s := 'ended';
    rreCancelled: s := 'cancelled';
    rreLimit: s := 'limit';
    rreFailed: s := 'failed';
  else
    s := '?';
  end;
  FReplaceResult := AResult;
  SetLength(FDone, Length(FDone) + 1);
  FDone[High(FDone)] := Format('replace %d %d %s', [AResult.Replaced, AResult.Skipped, s]);
  FDoneProgress := FProgressLast;
end;

procedure TTyRichEditFindTest.ResetEvents;
begin
  FChanges := 0;
  FSelChanges := 0;
  FProgress := nil;
  FProgressTotal := 0;
  FCancelAt := 0;
  FDone := nil;
  FDonePos := -2;
  FDoneLen := -2;
  FDoneProgress := -1;
  FEditInChange := False;
  FProgressLast := -1;
  FRestartFrom := 0;
  FRestartWith := '';
  FEditInHandler := False;
  FFreeIn := 0;
  FCancelInProgress := False;
  FSeenInHandler := '';
  FHandlerWentOn := False;
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
  TFindAccess(FRich).FindSlice := 1024;
  turns := 0;
  // through the find, and some parts in
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
  { RichMemo's facts (its win32 back end): backward the search begins at Start and goes
    toward the text's beginning over Len characters - [Start - Len, Start], a Len below 0 down
    to 0 - the match nearest Start, whole inside. }
  AssertEquals('backward from the end', 8, FRich.Search('one', 15, -1, [soBackward]));
  AssertEquals('backward from 0: nothing before it', -1, FRich.Search('one', 0, -1, [soBackward]));
  AssertEquals('backward from 8: the one before', 0, FRich.Search('one', 8, -1, [soBackward]));
  AssertEquals('backward over 4 from 11: the one at 8', 8, FRich.Search('one', 11, 4, [soBackward]));
  AssertEquals('backward over 4 from 10: none whole inside', -1, FRich.Search('one', 10, 4, [soBackward]));
  AssertEquals('backward over 20 from 15: not below 0', 8, FRich.Search('one', 15, 20, [soBackward]));
  AssertEquals('match case, backward', 0, FRich.Search('one', 15, -1, [soBackward, soMatchCase]));
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
  AssertEquals('the caret at its end', 3, FRich.CaretIndex);
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
  // across cells (the table-edge rule)
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
    // (and the end's progress, at its total)
    AssertTrue('at most the cap of pieces a turn', Length(FProgress) - before <= CRichIdleMaxSteps + 1);
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
  // (its second piece's, then the end's: at its total)
  AssertEquals('...at its second piece', 3, Length(FProgress));
  AssertEquals('...the last at its total', FProgressTotal, FProgress[2]);
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
  // a new content: told, by the call that replaced the content
  ResetEvents;
  FRich.FindNextAsync('needle');
  FRich.Turn;
  FRich.Lines.Text := 'other';
  AssertFalse('a new content stops it', FRich.FindRunning);
  AssertEquals('...told, once', 1, Length(FDone));
  AssertEquals('...cancelled', 'find none cancelled', FDone[0]);
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
  TFindAccess(FRich).FindSlice := 1024;
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
  { A break of the run from code between two parts does not touch the step (it merges
    with nothing): the replace goes on, one step, nothing on the redo side. }
  ResetEvents;
  FRich.ReplaceAllAsync('cat', 'dog');
  TFindAccess(FRich).FindSlice := 1024;
  turns := 0;
  while FRich.FindRunning and (Pos('dog', Text) = 0) and (turns < 10000) do
  begin
    FRich.Turn;
    Inc(turns);
  end;
  FRich.Document.BreakMerge;
  TurnUntilDone;
  AssertEquals('BreakMerge: it went on', 'replace 1000 0 ended', FDone[0]);
  AssertEquals('still one step', 1, FRich.Document.UndoDepth);
  AssertFalse('nothing to redo', FRich.CanRedo);
  FRich.Undo;
  AssertEquals('undone at once', before, Text);
  // a saved point between two parts ends it: nothing of the next part is anywhere
  ResetEvents;
  FRich.ReplaceAllAsync('cat', 'dog');
  TFindAccess(FRich).FindSlice := 1024;
  turns := 0;
  while FRich.FindRunning and (Pos('dog', Text) = 0) and (turns < 10000) do
  begin
    FRich.Turn;
    Inc(turns);
  end;
  turns := Length(Text);
  FRich.Modified := False;
  TurnUntilDone;
  AssertTrue('a saved point: cancelled - ' + FDone[0], Pos('cancelled', FDone[0]) > 0);
  AssertEquals('...one step', 1, FRich.Document.UndoDepth);
  AssertFalse('...nothing to redo', FRich.CanRedo);
  AssertFalse('...the content saved', FRich.Modified);
  AssertEquals('...nothing more replaced', turns, Length(Text));
end;

procedure TTyRichEditFindTest.TestABackgroundReplaceStopsAtAnEditAndASave;
var
  m: TMemoryStream;
  turns: Integer;
begin
  { The turns by a clock of the test's (a millisecond a reading): the parts' sizes are the same
    every run, whatever the machine is doing. }
  FRich.FakeClock := True;
  FRich.ClockStep := 1;
  try
  // (more text than a part of the largest size takes: every stop below is mid-way)
  SetText(Lines(20000, 'a cat sat here '));
  // an edit
  ResetEvents;
  FRich.ReplaceAllAsync('cat', 'dog');
  TFindAccess(FRich).FindSlice := 1024;
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
  // an edit made in the change handler of one of its batches: it stops, the edit stays
  ResetEvents;
  FRich.ReplaceAllAsync('sat', 'sits');
  turns := 0;
  while FRich.FindRunning and (Pos('sits', Text) = 0) and (turns < 10000) do
  begin
    FRich.Turn;
    Inc(turns);
  end;
  FRich.OnChange := @ChangedEdit;
  FEditInChange := True;
  // (the turns until a part is replaced: its change is heard)
  turns := 0;
  while FRich.FindRunning and FEditInChange and (turns < 10000) do
  begin
    FRich.Turn;
    Inc(turns);
  end;
  FRich.OnChange := @Changed;
  AssertFalse('an edit in its change handler stops it', FRich.FindRunning);
  AssertTrue('told', Pos('cancelled', FDone[0]) > 0);
  AssertEquals('the edit stays', 'Q', Copy(Text, 1, 1));
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
  FRich.ReplaceAllAsync('here', 'HERE');
  FRich.Document.BeginUpdate;
  try
    turns := 0;
    while FRich.FindRunning and (turns < 2000) do
    begin
      FRich.Turn;
      Inc(turns);
    end;
    if Length(FDone) > 0 then Fail('it ended: ' + FDone[0]);
    AssertTrue('waits while the document holds its changes back', FRich.FindRunning);
    AssertTrue('nothing replaced meanwhile', Pos('HERE', Text) = 0);
    // and asks for no turn while it waits
    AssertFalse('no work while it waits', TFindAccess(FRich).HasBackgroundWork);
  finally
    FRich.Document.EndUpdate;
  end;
  TurnUntilDone;
  AssertTrue('then it went on', Pos('HERE', Text) > 0);
  finally
    FRich.FakeClock := False;
  end;
end;

{ A background replace over a lazily read RTF parses what it changes, and between its batches
  lets the parsed intervals go back to the loader's bound; undone, the file saves as it was. }
procedure TTyRichEditFindTest.TestABackgroundReplaceTrimsALazyFile;
var
  s: RawByteString;
  b, saved: TBytes;
  k, parsed0, most: Integer;
  load: TTyRtfLoad;
  m: TBytesStream;
begin
  s := Rtf('{|rtf1|ansi|deff0{|fonttbl{|f0 Arial;}}|pard ');
  for k := 0 to 149999 do
    if k mod 100 = 0 then s := s + 'line ' + IntToStr(k) + Rtf(' with a {|b word}|par') + #13#10
    else s := s + 'line ' + IntToStr(k) + Rtf(' of filler|par') + #13#10;
  s := s + '}';
  b := BytesOf(s);
  LoadBytes(b);
  load := TyRichRtfLoadOf(FRich.Document);
  AssertTrue('more intervals than stay parsed', load.IntervalCount > 2 * load.MaxResidentIntervals);
  parsed0 := load.ParseCount;
  FRich.ReplaceAllAsync('word', 'term');
  most := 0;
  while FRich.FindRunning do
  begin
    FRich.Turn;
    if load.ResidentIntervals > most then most := load.ResidentIntervals;
  end;
  // (the loader's bound for what is only read is twice its bound and one: the find's half)
  AssertTrue(Format('between its turns no more than the bound stays parsed (%d of %d)',
    [most, load.MaxResidentIntervals]), most <= 2 * load.MaxResidentIntervals + 1);
  AssertEquals('done', 'replace 1500 0 ended', FDone[0]);
  AssertTrue('parsed what it changed', load.ParseCount - parsed0 >= load.IntervalCount div 2);
  AssertTrue(Format('the parsed intervals back to the bound (%d of %d)',
    [load.ResidentIntervals, load.MaxResidentIntervals]),
    load.ResidentIntervals <= load.MaxResidentIntervals + 1);
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

{ The window made again (what RecreateWnd does for a border style, a parent, BiDi) does
  not end a background find: it waits for the window, as the load does, and goes on. }
procedure TTyRichEditFindTest.TestTheWindowMadeAgainDoesNotStopIt;
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
    SetText(Lines(5000, 'filler words ') + 'the needle');
    FRich.SelStart := 0;
    ResetEvents;
    FRich.FindNextAsync('needle');
    AssertTrue('the driver is on', FRich.IdleOn or FRich.TurnQueued or (FRich.TimerOf <> nil));
    FRich.DropHandle;
    AssertTrue('the window going does not stop it', FRich.FindRunning);
    AssertEquals('...no event', 0, Length(FDone));
    FRich.HandleNeeded;
    AssertTrue('the driver on again', FRich.IdleOn or FRich.TurnQueued or (FRich.TimerOf <> nil));
    TurnUntilDone;
    AssertEquals('found, once', 1, Length(FDone));
    AssertEquals('found', 'find found ended', FDone[0]);
  finally
    FRich.Parent := nil;
    F.Free;
  end;
end;

{ Every content replacement ends a running find or replace with its done-event
  (cancelled), raised from the public call that replaced the content, before it returns -
  Lines.Text, Clear, LoadFromStream; one started from that event's handler is told too; the
  destructor raises none. }
procedure TTyRichEditFindTest.TestANewContentTellsTheFindItEnded;
var
  st: TBytesStream;
begin
  SetText(Lines(5000, 'filler words '));
  FRich.FindNextAsync('needle');
  FRich.Turn;
  FRich.Clear;
  AssertEquals('Clear: told once', 1, Length(FDone));
  AssertEquals('...cancelled', 'find none cancelled', FDone[0]);
  SetText(Lines(5000, 'a cat here '));
  FRich.ReplaceAllAsync('cat', 'dog');
  FRich.Turn;
  st := TBytesStream.Create(BytesOf(Rtf('{|rtf1|ansi a cat|par}')));
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  AssertEquals('a load: told once', 1, Length(FDone));
  AssertTrue('...cancelled: ' + FDone[0], Pos('cancelled', FDone[0]) > 0);
  // a find started from that event's handler ends with the content - and is told too
  SetText(Lines(5000, 'filler words '));
  FRich.FindNextAsync('needle');
  FRestartFrom := 2;
  FRestartWith := 'words';
  FRich.Lines.Text := 'other words';
  AssertFalse('nothing runs', FRich.FindRunning);
  AssertEquals('both told, before the call returned', 2, Length(FDone));
  // the destructor: none
  ResetEvents;
  FRich.FindNextAsync('needle');
  FreeAndNil(FRich);
  AssertEquals('the end: no event', 0, Length(FDone));
  FRich := TEditProbe.Create(nil);
  FRich.Controller := FCtl;
end;

{ A match inside a cluster (e of e with a combining mark; a thumbs-up of one with a skin
  tone) is selected with its whole cluster, never as nothing, and the next call goes on after
  it: a while loop of FindNext ends - forward, backward, with wrapping it goes round. }
procedure TTyRichEditFindTest.TestFindNextNeverStandsStill;
const
  E = #$65;
var
  n, last: Integer;
  thumbs, mod5: string;
begin
  SetText('x' + E + #$CC#$81 + ' y' + E + #$CC#$81 + ' z' + E);
  FRich.SelStart := 0;
  n := 0;
  while FRich.FindNext('e', []) and (n < 20) do
  begin
    AssertTrue('never empty', FRich.SelLength > 0);
    Inc(n);
  end;
  AssertEquals('three, and the loop ends', 3, n);
  AssertEquals('FindText: the match''s own place', 1, FRich.FindText('e', 0, -1, []));
  // backward
  FRich.SelStart := FRich.Document.Text.Length;
  n := 0;
  while FRich.FindNext('e', [rfoBackward]) and (n < 20) do
  begin
    AssertTrue('backward: never empty', FRich.SelLength > 0);
    Inc(n);
  end;
  AssertEquals('backward: three, the loop ends', 3, n);
  // with wrapping it goes round, never standing still
  FRich.SelStart := 0;
  last := -1;
  for n := 1 to 7 do
  begin
    AssertTrue(FRich.FindNext('e', [rfoWrap]));
    AssertTrue('it moved', FRich.SelStart <> last);
    last := FRich.SelStart;
  end;
  // a thumbs-up with a skin tone
  thumbs := #$F0#$9F#$91#$8D;
  mod5 := #$F0#$9F#$8F#$BD;
  SetText('a ' + thumbs + mod5 + ' b ' + thumbs + mod5 + ' c');
  FRich.SelStart := 0;
  n := 0;
  while FRich.FindNext(thumbs, []) and (n < 20) do Inc(n);
  AssertEquals('two thumbs, and the loop ends', 2, n);
  // in the background: the same
  FRich.SelStart := 0;
  ResetEvents;
  FRich.FindNextAsync(thumbs, []);
  TurnUntilDone;
  AssertEquals('found', 'find found ended', FDone[0]);
  AssertEquals('the event: the match''s own place', 2, FDonePos);
  AssertEquals('...its own length', 1, FDoneLen);
  AssertEquals('the selection: the whole cluster', 2, FRich.SelLength);
  FRich.FindNextAsync(thumbs, []);
  TurnUntilDone;
  AssertEquals('the next one', 7, FDonePos);
end;

{ A find or a replace started from a handler of the one running (its progress, its end)
  is that one, not the old: it finds what it looks for, where it is. }
procedure TTyRichEditFindTest.TestAFindStartedFromItsHandler;
begin
  SetText('alpha beta gamma delta');
  FRich.SelStart := 0;
  ResetEvents;
  FRestartFrom := 1;
  FRestartWith := 'delta';
  FRich.FindNextAsync('beta', []);
  TurnUntilDone;
  AssertEquals('the first told, cancelled', 'find none cancelled', FDone[0]);
  AssertEquals('the second found', 'find found ended', FDone[High(FDone)]);
  AssertEquals('...delta, where it is', 17, FRich.SelStart);
  AssertEquals(5, FRich.SelLength);
  // from the done handler
  FRich.SelStart := 0;
  ResetEvents;
  FRestartFrom := 2;
  FRestartWith := 'gamma';
  FRich.FindNextAsync('absent', []);
  TurnUntilDone;
  AssertEquals('two events', 2, Length(FDone));
  AssertEquals('the first: not found', 'find none ended', FDone[0]);
  AssertEquals('the second: found', 'find found ended', FDone[1]);
  AssertEquals('...gamma', 11, FRich.SelStart);
  // a replace started from a find's progress handler is a replace of its own
  FRich.SelStart := 0;
  ResetEvents;
  FRestartFrom := 1;
  FRestartWith := '';
  FRich.FindNextAsync('delta', []);
  TurnUntilDone;
  AssertEquals('the find cancelled, the replace done', 'replace 1 0 ended', FDone[High(FDone)]);
  AssertEquals('alpha BETA gamma delta', Text);
end;

{ A wrapped search that finds nothing reads the text once (the second leg ends where the
  first began, a needle's length into it). RichMemo's and Delphi's calls with Integer
  variables compile and run. }
procedure TTyRichEditFindTest.TestWrapReadsOnceAndIntegersCompile;
var
  len: Int64;
  i, s, n: Integer;
  ok: Boolean;
begin
  SetText(Lines(5000, 'filler words '));
  len := FRich.Document.Text.Length;
  FRich.SelStart := len div 2;
  TFindAccess(FRich).FindBytesRead := 0;
  AssertFalse(FRich.FindNext('absent', [rfoWrap]));
  AssertTrue(Format('read once (%d of %d)', [TFindAccess(FRich).FindBytesRead, len]),
    TFindAccess(FRich).FindBytesRead <= len + 64);
  // Integer variables, as RichMemo and Delphi code has them
  i := FRich.FindText('words 10', 0, -1, []);
  AssertTrue('Delphi''s FindText into an Integer', i > 0);
  s := -1;
  n := -1;
  ok := FRich.Search('words 10', 0, -1, [], s, n);
  AssertTrue('RichMemo''s second Search with Integer variables', ok);
  AssertEquals(i, s);
  AssertEquals(8, n);
  i := FRich.Search('words 10', 0, -1, []);
  AssertEquals(s, i);
end;

{ The progress always ends at its total, before the done-event - also for a find that
  found nothing, one cancelled, a replace with no match, one at the limit; the replace at the
  limit says so (the synchronous one in its result too). }
procedure TTyRichEditFindTest.TestTheProgressEndsAtItsTotal;
var
  n: Integer;
  res: TTyRichReplaceResult;
begin
  SetText(Lines(3000, 'filler words '));
  FRich.SelStart := 0;
  ResetEvents;
  FRich.FindNextAsync('absent', []);
  TurnUntilDone;
  AssertEquals('not found', 'find none ended', FDone[0]);
  AssertEquals('...at its total', FProgressTotal, FDoneProgress);
  ResetEvents;
  FCancelAt := 1;
  FRich.FindNextAsync('absent', []);
  TurnUntilDone;
  AssertEquals('cancelled', 'find none cancelled', FDone[0]);
  AssertEquals('...at its total', FProgressTotal, FDoneProgress);
  ResetEvents;
  FRich.ReplaceAllAsync('absent', 'x');
  TurnUntilDone;
  AssertEquals('no match', 'replace 0 0 ended', FDone[0]);
  AssertEquals('...at its total', FProgressTotal, FDoneProgress);
  // the limit
  FRich.Document.MaxUndoBytes := 4096;
  ResetEvents;
  FRich.ReplaceAllAsync('filler', 'f');
  TurnUntilDone;
  AssertTrue('at the limit: ' + FDone[0], Pos(' limit', FDone[0]) > 0);
  AssertEquals('...at its total', FProgressTotal, FDoneProgress);
  AssertEquals('one step', 1, FRich.Document.UndoDepth);
  ResetEvents;
  n := FRich.ReplaceAll('filler', 'f', [], 0, -1, res);
  AssertTrue('the synchronous one: some', n > 0);
  AssertEquals('...at the limit', Ord(rreLimit), Ord(res.Ending));
  AssertEquals('...one change', 1, FChanges);
  FRich.Document.MaxUndoBytes := 0;
  n := FRich.ReplaceAll('filler', 'f', [], res.ResumeAt, res.ResumeLength, res);
  AssertEquals('...and the rest', Ord(rreDone), Ord(res.Ending));
  AssertEquals('none left', 0, Pos('filler', Text));
end;

{ The events as published: each says what ran (the progress: a find or a replace), how it
  ended (an enumeration of its own per done-event), what was done, and where to go on. }
procedure TTyRichEditFindTest.TestTheEventsArePublished;

  procedure Has(const AName, AType: string);
  var
    pi: PPropInfo;
  begin
    pi := GetPropInfo(TTyRichEdit, AName);
    AssertTrue(AName + ': published', pi <> nil);
    AssertEquals(AName + ': its type', AType, pi^.PropType^.Name);
  end;

begin
  Has('OnFindProgress', 'TTyRichFindProgressEvent');
  Has('OnFindDone', 'TTyRichFindDoneEvent');
  Has('OnReplaceDone', 'TTyRichReplaceDoneEvent');
  // the progress says which runs
  SetText(Lines(500, 'one two '));
  ResetEvents;
  FRich.FindNextAsync('absent', []);
  TurnUntilDone;
  AssertEquals('a find''s progress', Ord(rftFind), Ord(FProgressTask));
  ResetEvents;
  FRich.ReplaceAllAsync('two', 'TWO');
  TurnUntilDone;
  AssertEquals('a replace''s progress', Ord(rftReplace), Ord(FProgressTask));
  AssertEquals('...done', Ord(rreDone), Ord(FReplaceResult.Ending));
  AssertEquals('...nothing to go on from', -1, FReplaceResult.ResumeAt);
end;

{ Text with LF for every paragraph end, and none after the last. }
function Plain(const S: string): string;
begin
  Result := StringReplace(S, #13#10, #10, [rfReplaceAll]);
  while (Result <> '') and (Result[Length(Result)] = #10) do SetLength(Result, Length(Result) - 1);
end;

{ "Replace All" with a needle of several long paragraphs - longer than the range a part reads:
  it ends, in the background and synchronously (it went round for ever, the application
  frozen). }
procedure TTyRichEditFindTest.TestALongNeedleWithAParagraphEndEnds;
var
  needle: string;
  res: TTyRichReplaceResult;
  n: Integer;
begin
  needle := StringOfChar('a', 10000) + #10 + StringOfChar('b', 10000);
  SetText('x' + #10 + needle + #10 + 'y');
  ResetEvents;
  FRich.ReplaceAllAsync(needle, 'z');
  TurnUntilDone(10000);
  AssertEquals('in the background', 'replace 1 0 ended', FDone[0]);
  AssertEquals('...the text', 'x' + #10 + 'z' + #10 + 'y', Plain(Text));
  needle := StringOfChar('a', 40000) + #10 + StringOfChar('b', 40000);
  SetText('x' + #10 + needle + #10 + 'y');
  n := FRich.ReplaceAll(needle, 'z', [], 0, -1, res);
  AssertEquals('synchronously', 1, n);
  AssertEquals('...done', Ord(rreDone), Ord(res.Ending));
  AssertEquals('...the text', 'x' + #10 + 'z' + #10 + 'y', Plain(Text));
end;

{ Where a replace stopped (the limit, a cancel) is told, in the text as it is then, and a new
  replace from there for the rest of the range replaces every match once - with a replacement
  that holds the needle, where a run again from the start replaced the first part again and
  again. A background replace cancelled by an edit before that place tells it moved by the
  edit. }
procedure TTyRichEditFindTest.TestAReplaceGoesOnWhereItStopped;
var
  src, want: string;
  res: TTyRichReplaceResult;
  runs, total, turns: Integer;
  at: TTyRichPos;
begin
  // "MrMrMr...": a place one character off replaces a match twice or misses one
  // the limit, synchronously (more text than one range of the synchronous call)
  src := Lines(12000, 'MrMrMrMrMr ');
  want := Plain(StringReplace(src, 'Mr', 'Mr.', [rfReplaceAll]));
  SetText(src);
  FRich.Document.MaxUndoBytes := 4096;
  res.ResumeAt := 0;
  res.ResumeLength := -1;
  runs := 0;
  total := 0;
  repeat
    Inc(runs);
    Inc(total, FRich.ReplaceAll('Mr', 'Mr.', [], res.ResumeAt, res.ResumeLength, res));
  until (res.Ending <> rreLimit) or (runs > 300);
  AssertEquals('the limit: through', Ord(rreDone), Ord(res.Ending));
  AssertTrue(Format('...in several runs (%d)', [runs]), runs > 2);
  AssertEquals('...each once', 12000 * 5, total);
  AssertEquals('...the text', want, Plain(Text));
  FRich.Document.MaxUndoBytes := 0;
  // cancelled in the background, started again from where it stopped (the turns by a clock
  // of the test's: the same pieces every time)
  src := Lines(1500, 'MrMrMrMrMr ');
  want := Plain(StringReplace(src, 'Mr', 'Mr.', [rfReplaceAll]));
  FRich.FakeClock := True;
  FRich.ClockStep := 1;
  try
  SetText(src);
  FReplaceResult.ResumeAt := 0;
  FReplaceResult.ResumeLength := -1;
  runs := 0;
  total := 0;
  at := 0;
  repeat
    Inc(runs);
    ResetEvents;
    FCancelAt := 4;
    FRich.ReplaceAllAsync('Mr', 'Mr.', [], FReplaceResult.ResumeAt, FReplaceResult.ResumeLength);
    TFindAccess(FRich).FindSlice := 512;
    TurnUntilDone;
    Inc(total, FReplaceResult.Replaced);
    if FReplaceResult.Ending = rreCancelled then
    begin
      AssertTrue('on from no earlier', FReplaceResult.ResumeAt >= at);
      at := FReplaceResult.ResumeAt;
    end;
  until (FReplaceResult.Ending <> rreCancelled) or (runs > 2000);
  AssertEquals('cancelled: through', Ord(rreDone), Ord(FReplaceResult.Ending));
  AssertTrue(Format('...in several runs (%d)', [runs]), runs > 2);
  AssertEquals('...each once', 1500 * 5, total);
  AssertEquals('...the text', want, Plain(Text));
  // an edit before the place: the place moves with it
  SetText(src);
  ResetEvents;
  FRich.ReplaceAllAsync('Mr', 'Mr.');
  TFindAccess(FRich).FindSlice := 512;
  turns := 0;
  while FRich.FindRunning and (Pos('Mr.', Text) = 0) and (turns < 10000) do
  begin
    FRich.Turn;
    Inc(turns);
  end;
  AssertTrue('a part went in', Pos('Mr.', Text) > 0);
  FRich.Document.Execute(TTyRichInsertText.Create(0, 'xyz'));
  FRich.Turn;
  AssertFalse('the edit stopped it', FRich.FindRunning);
  AssertEquals('...told', Ord(rreCancelled), Ord(FReplaceResult.Ending));
  AssertTrue('...some replaced', FReplaceResult.Replaced > 0);
  total := FReplaceResult.Replaced;
  Inc(total, FRich.ReplaceAll('Mr', 'Mr.', [], FReplaceResult.ResumeAt,
    FReplaceResult.ResumeLength, res));
  AssertEquals('...the rest from the place told', Ord(rreDone), Ord(res.Ending));
  AssertEquals('...each once', 1500 * 5, total);
  AssertEquals('...the text', 'xyz' + want, Plain(Text));
  finally
    FRich.FakeClock := False;
  end;
end;

{ The engine's set of scripts written without spaces (whole word: a word ends on both sides
  of such a character) is the line breaker's, code point by code point - kept in the model so
  that the finder needs no unit of the controls. }
procedure TTyRichEditFindTest.TestTheWordBoundaryIsTheLineBreakers;
var
  c: Cardinal;
begin
  for c := 0 to $10FFFF do
    if TyRichNoSpaceScript(c) <> TyIsCJKCodepoint(c) then
      Fail(Format('U+%.4X: the finder and the line breaker differ', [c]));
end;

{ A handler of OnFindProgress, OnFindDone or OnReplaceDone may free the control: the turn
  that raised it touches nothing of it any more and ends quietly (the turns of a find and of a
  replace); a public call that raised it returns as if nothing had been found or replaced, and
  no exception of any class leaves it - also a public call made from inside a handler, which
  returns to that handler (the turn under the handler ends when the handler has returned), and
  the calls that hold another of the control's calls (a file's load and save, the end of a
  Lines update). Nothing reaches the application's exception handler. }
procedure TTyRichEditFindTest.TestAHandlerMayFreeTheControl;

  procedure Fresh;
  begin
    FRich := TEditProbe.Create(nil);
    FRich.Controller := FCtl;
    FRich.SetBounds(0, 0, 400, 300);
    FRich.OnFindProgress := @Progress;
    FRich.OnFindDone := @FindDone;
    FRich.OnReplaceDone := @ReplaceDone;
    SetText(Lines(2000, 'one two three '));
    FDone := nil;
  end;

  procedure TurnsUntilFreed(const AWhat: string);
  var
    turns: Integer;
    p: TEditProbe;
  begin
    turns := 0;
    while (FRich <> nil) and (turns < 10000) do
    begin
      p := FRich;
      try
        p.Turn;
      except
        on E: Exception do Fail(AWhat + ': the turn raised ' + E.ClassName);
      end;
      Inc(turns);
    end;
    AssertTrue(AWhat + ': freed', FRich = nil);
    AssertEquals(AWhat + ': told once', 1, Length(FDone));
  end;

var
  raised, what, dir, name: string;
  call, kind: Integer;
  m: TMemoryStream;
  res: TTyRichReplaceResult;
  sr: TSearchRec;
  fs: TFileStream;
  g: TGUID;
  p: TEditProbe;
begin
  FreeAndNil(FRich);
  // a find: its done-event frees it, then its progress
  Fresh;
  FRich.FindNextAsync('absent', []);
  FFreeIn := 2;
  TurnsUntilFreed('find, done');
  Fresh;
  FRich.FindNextAsync('absent', []);
  FFreeIn := 1;
  TurnsUntilFreed('find, progress');
  // a replace
  Fresh;
  FRich.ReplaceAllAsync('two', 'TWO');
  FFreeIn := 2;
  TurnsUntilFreed('replace, done');
  Fresh;
  FRich.ReplaceAllAsync('two', 'TWO');
  FFreeIn := 1;
  TurnsUntilFreed('replace, progress');
  { A public call made from a handler - the progress handler calls CancelFind -, in which the
    done-event frees the control: the call returns to the handler, which sees no exception and
    runs on; the turn that raised the progress ends quietly. }
  for kind := 0 to 1 do
  begin
    Fresh;
    if kind = 0 then FRich.FindNextAsync('absent', []) else FRich.ReplaceAllAsync('two', 'TWO');
    FFreeIn := 2;
    FCancelInProgress := True;
    FSeenInHandler := '';
    FHandlerWentOn := False;
    what := Format('a call from a handler, a %s running', [BoolToStr(kind = 0, 'find', 'replace')]);
    raised := '';
    p := FRich;
    try
      while (FRich <> nil) and FCancelInProgress do p.Turn;
    except
      on E: Exception do raised := E.ClassName + ': ' + E.Message;
    end;
    AssertEquals(what + ': the turn raised nothing', '', raised);
    AssertTrue(what + ': freed', FRich = nil);
    AssertEquals(what + ': the handler saw no exception', '', FSeenInHandler);
    AssertTrue(what + ': the call returned to the handler', FHandlerWentOn);
    AssertEquals(what + ': told once', 1, Length(FDone));
  end;
  // the calls that hold another call of the control: a file's load and save, a Lines update
  CreateGUID(g);
  dir := IncludeTrailingPathDelimiter(GetTempDir(False));
  name := 'tyrichfind-' + Copy(GUIDToString(g), 2, 36);
  try
    fs := TFileStream.Create(dir + name + '.txt', fmCreate);
    try
      fs.WriteBuffer(PChar('new text')^, 8);
    finally
      fs.Free;
    end;
    for call := 0 to 2 do
    begin
      Fresh;
      FRich.ReplaceAllAsync('two', 'TWO');
      FFreeIn := 2;
      what := Format('holding call %d', [call]);
      raised := '';
      try
        case call of
          0: FRich.LoadFromFile(dir + name + '.txt');
          1: FRich.SaveToFile(dir + name + '.out.txt');
        else
          FRich.Lines.BeginUpdate;
          FRich.Lines.Text := 'new';
          FRich.Lines.EndUpdate;
        end;
      except
        on E: Exception do raised := E.ClassName + ': ' + E.Message;
      end;
      AssertEquals(what + ': nothing raised', '', raised);
      AssertTrue(what + ': freed', FRich = nil);
      AssertEquals(what + ': told once', 1, Length(FDone));
    end;
    AssertFalse('the save wrote no file', FileExists(dir + name + '.out.txt'));
    if FindFirst(dir + '.' + name + '*', faAnyFile, sr) = 0 then
    begin
      FindClose(sr);
      Fail('the save left its temporary file: ' + sr.Name);
    end;
  finally
    SysUtils.DeleteFile(dir + name + '.txt');
    SysUtils.DeleteFile(dir + name + '.out.txt');
  end;
  // the public calls that end one: each returns (no exception), its answer "nothing"
  for call := 0 to 11 do
    for kind := 0 to 1 do
    begin
      Fresh;
      if kind = 0 then FRich.FindNextAsync('absent', []) else FRich.ReplaceAllAsync('two', 'TWO');
      FFreeIn := 2;
      what := Format('call %d, a %s running', [call, BoolToStr(kind = 0, 'find', 'replace')]);
      raised := '';
      try
        case call of
          0: FRich.CancelFind;
          1: AssertFalse(what + ': FindNext answers False', FRich.FindNext('one'));
          2: FRich.FindNextAsync('one');
          3:
            begin
              AssertEquals(what + ': ReplaceAll answers 0', 0, FRich.ReplaceAll('one', 'ONE', [], 0, -1, res));
              AssertEquals(what + ': ...cancelled', Ord(rreCancelled), Ord(res.Ending));
            end;
          4: FRich.ReplaceAllAsync('one', 'ONE');
          5: FRich.Lines.Text := 'new';
          6: FRich.Clear;
          7:
            begin
              m := TMemoryStream.Create;
              try
                FRich.SaveToStream(m, rfText);
              finally
                m.Free;
              end;
            end;
          8:
            begin
              m := TMemoryStream.Create;
              try
                m.WriteBuffer(PChar('new text')^, 8);
                m.Position := 0;
                FRich.LoadFromStream(m, rfText);
              finally
                m.Free;
              end;
            end;
          9: AssertEquals(what + ': ReplaceAll answers 0', 0, FRich.ReplaceAll('one', 'ONE'));
          11: FRich.ClearUndo;
        else
          begin
            m := TMemoryStream.Create;
            try
              m.WriteBuffer(PChar('new text')^, 8);
              m.Position := 0;
              FRich.Lines.LoadFromStream(m);
            finally
              m.Free;
            end;
          end;
        end;
      except
        on E: Exception do raised := E.ClassName + ': ' + E.Message;
      end;
      if ((call = 7) or (call = 11)) and (kind = 0) then
      begin
        // (a save and ClearUndo end a running replace, not a find: nothing freed it)
        AssertEquals(what + ': nothing raised', '', raised);
        FreeAndNil(FRich);
        Continue;
      end;
      AssertEquals(what + ': nothing raised', '', raised);
      AssertTrue(what + ': freed', FRich = nil);
    end;
  // (TearDown frees a new one)
  Fresh;
end;

function CountMatchesOf(const ANeedle, AText: string): Integer;
var
  p: Integer;
begin
  Result := 0;
  p := Pos(ANeedle, AText);
  while p > 0 do
  begin
    Inc(Result);
    p := Pos(ANeedle, AText, p + Length(ANeedle));
  end;
end;

{ A background replace of a document whose load was cancelled replaces nothing and counts every
  match as left - a piece a turn, as a find reads, not the whole text in one turn. }
procedure TTyRichEditFindTest.TestAReplaceOfAnIncompleteDocumentCountsInPieces;
var
  sb: TStringBuilder;
  i, turns: Integer;
  b: TBytes;
begin
  sb := TStringBuilder.Create;
  try
    sb.Append('{' + BS + 'rtf1' + BS + 'ansi' + BS + 'deff0{' + BS + 'fonttbl{' + BS + 'f0 Arial;}}');
    for i := 0 to 59999 do
    begin
      sb.Append(BS + 'pard one cat ');
      sb.Append(IntToStr(i));
      sb.Append(BS + 'par' + #13#10);
    end;
    sb.Append('}');
    b := BytesOf(sb.ToString);
  finally
    sb.Free;
  end;
  TFindAccess(FRich).FirstSliceBytes := 512 * 1024;
  LoadBytes(b, False);
  FRich.CancelLoad;
  AssertTrue('incomplete', FRich.Incomplete);
  ResetEvents;
  FRich.ReplaceAllAsync('cat', 'dog');
  TFindAccess(FRich).FindSlice := 4096;
  turns := TurnUntilDone;
  AssertTrue(Format('in several turns (%d)', [turns]), turns > 3);
  AssertEquals('nothing replaced', 0, Pos('dog', Text));
  AssertTrue('every match counted: ' + FDone[0], Pos('replace 0 ', FDone[0]) = 1);
  AssertEquals('...as many as there are', CountMatchesOf('cat', Text), FReplaceResult.Skipped);
  // the progress on the way, of its own total, never back, at its total before the end
  AssertTrue(Format('progress on the way (%d for %d turns)', [Length(FProgress), turns]),
    Length(FProgress) >= turns - 1);
  AssertEquals('...its own total: the text', FRich.Document.Text.Length, FProgressTotal);
  for i := 1 to High(FProgress) do
    AssertTrue('...never back', FProgress[i] >= FProgress[i - 1]);
  AssertEquals('...at its total before the end', FProgressTotal, FDoneProgress);
  // and its handler may stop it
  ResetEvents;
  FCancelAt := 2;
  FRich.ReplaceAllAsync('cat', 'dog');
  TFindAccess(FRich).FindSlice := 4096;
  TurnUntilDone;
  AssertTrue('cancelled from the progress: ' + FDone[0], Pos(' cancelled', FDone[0]) > 0);
end;

{ A background replace stopped before its end - cancelled, a key, a save, cancelled again, on
  one line of matches - leaves in the history its undo record only: its finder and the copy of
  the paragraph it stood in go with every ending. While it runs the history counts for its
  step what the step keeps, part by part; stopped, no more than that. }
procedure TTyRichEditFindTest.TestAStoppedReplaceKeepsOnlyItsRecord;
var
  sb: TStringBuilder;
  i, way, turns, depth: Integer;
  cmd: TTyRichReplaceAllCommand;
  m: TMemoryStream;
  mem, hist: Int64;
begin
  sb := TStringBuilder.Create;
  try
    for i := 0 to 299999 do sb.Append('a,');
    SetText(sb.ToString);
  finally
    sb.Free;
  end;
  FRich.FakeClock := True;
  FRich.ClockStep := 1;
  try
    FReplaceResult.ResumeAt := 0;
    FReplaceResult.ResumeLength := -1;
    for way := 0 to 3 do
    begin
      ResetEvents;
      FRich.ReplaceAllAsync(',', ';', [], FReplaceResult.ResumeAt, FReplaceResult.ResumeLength);
      TFindAccess(FRich).FindSlice := 4096;
      turns := 0;
      depth := FRich.Document.UndoDepth;
      while FRich.FindRunning and (FRich.Document.UndoDepth = depth) do
      begin
        FRich.Turn;
        Inc(turns);
        AssertTrue('runaway', turns < 10000);
      end;
      AssertTrue(Format('%d: a part went in', [way]), FRich.FindRunning);
      cmd := FRich.Document.UndoStep as TTyRichReplaceAllCommand;
      AssertTrue(Format('%d: while it runs, it keeps the line', [way]), cmd.HeldBytes > 0);
      // more parts: what the history counts for the step grows by what the step keeps more
      mem := cmd.MemSize;
      hist := FRich.Document.HistoryBytes;
      for i := 1 to 8 do FRich.Turn;
      AssertTrue(Format('%d: still running', [way]), FRich.FindRunning and
        (FRich.Document.UndoStep = cmd));
      AssertTrue(Format('%d: its record grew with its parts', [way]), cmd.MemSize > mem);
      AssertEquals(Format('%d: the history counts what the step keeps, part by part', [way]),
        cmd.MemSize - mem, FRich.Document.HistoryBytes - hist);
      hist := FRich.Document.HistoryBytes;
      case way of
        0, 3: FRich.CancelFind;
        1:
          begin
            FRich.Key8('q');
            FRich.Turn;
          end;
      else
        m := TMemoryStream.Create;
        try
          FRich.SaveToStream(m, rfText);
        finally
          m.Free;
        end;
      end;
      AssertFalse(Format('%d: stopped', [way]), FRich.FindRunning);
      AssertEquals(Format('%d: told cancelled', [way]), Ord(rreCancelled), Ord(FReplaceResult.Ending));
      AssertTrue(Format('%d: some replaced', [way]), FReplaceResult.Replaced > 0);
      if way = 1 then
        // (the typed key is the step now; the replace's is the one below it)
        FRich.Document.Undo;
      cmd := FRich.Document.UndoStep as TTyRichReplaceAllCommand;
      AssertEquals(Format('%d: nothing but its record', [way]), 0, cmd.HeldBytes);
      // (but where the typed key's step is in the history too)
      if way <> 1 then
        AssertTrue(Format('%d: stopped, the history counts no more for it than while it ran', [way]),
          FRich.Document.HistoryBytes <= hist);
      if way = 1 then FRich.Document.Redo;
    end;
  finally
    FRich.FakeClock := False;
  end;
end;

{ A background replace stopped by the undo of its own step: nothing of it is left, and it says
  so - none replaced, the range's start as the place to go on from; a replace from there
  replaces all. }
procedure TTyRichEditFindTest.TestAReplaceUndoneTellsItsStart;
var
  src: string;
  res: TTyRichReplaceResult;
  turns, n: Integer;
begin
  src := Lines(6000, 'MrMrMrMrMr ');
  SetText(src);
  FRich.FakeClock := True;
  FRich.ClockStep := 1;
  try
    ResetEvents;
    FRich.ReplaceAllAsync('Mr', 'Mr.');
    TFindAccess(FRich).FindSlice := 2048;
    turns := 0;
    while FRich.FindRunning and (Pos('Mr.', Text) = 0) and (turns < 10000) do
    begin
      FRich.Turn;
      Inc(turns);
    end;
    AssertTrue('a part went in', FRich.FindRunning and (Pos('Mr.', Text) > 0));
    FRich.Document.Undo;
    FRich.Turn;
    AssertFalse('the undo stopped it', FRich.FindRunning);
    AssertEquals('...told cancelled', Ord(rreCancelled), Ord(FReplaceResult.Ending));
    AssertEquals('...nothing of it left', 0, FReplaceResult.Replaced);
    AssertEquals('...on from the start', 0, FReplaceResult.ResumeAt);
    AssertEquals('...to the end', -1, FReplaceResult.ResumeLength);
  finally
    FRich.FakeClock := False;
  end;
  n := FRich.ReplaceAll('Mr', 'Mr.', [], FReplaceResult.ResumeAt, FReplaceResult.ResumeLength, res);
  AssertEquals('from there: all', 6000 * 5, n);
end;

{ A background replace whose step is covered and uncovered again between two of its turns - an
  edit and its undo: set as the selection's text, run on the document, typed - or undone and
  redone: the content is the one its last part left, so its next turn sees no change, and still
  it is not through its range. It ends as cancelled, with what is replaced in the text as it
  is and the place to go on from; a replace from there replaces the rest and nothing twice
  (the replacement holds the needle): the text is what one replace of the whole makes it. }
procedure TTyRichEditFindTest.TestAReplaceLetGoBetweenTwoTurnsIsNotDone;
var
  src, want: string;
  res: TTyRichReplaceResult;
  way, turns, n, total: Integer;
  state: Int64;
begin
  src := Lines(6000, 'MrMrMrMrMr ');
  SetText(src);
  total := FRich.ReplaceAll('Mr', 'Mr.');
  AssertEquals('one replace of the whole', 6000 * 5, total);
  want := Text;
  FRich.FakeClock := True;
  FRich.ClockStep := 1;
  try
    for way := 0 to 3 do
    begin
      SetText(src);
      FRich.ReplaceAllAsync('Mr', 'Mr.');
      TFindAccess(FRich).FindSlice := 2048;
      turns := 0;
      while FRich.FindRunning and (Length(FProgress) < 6) and (turns < 10000) do
      begin
        FRich.Turn;
        Inc(turns);
      end;
      AssertTrue(Format('%d: parts went in, more to come', [way]),
        FRich.FindRunning and (Pos('Mr.', Text) > 0));
      state := FRich.Document.ContentState;
      case way of
        0:
          begin
            FRich.SelStart := FRich.Document.Text.Length;
            FRich.SelLength := 0;
            FRich.SelText := 'q';
            FRich.Undo;
          end;
        1:
          begin
            FRich.Document.Execute(TTyRichInsertText.Create(0, 'q'));
            FRich.Document.Undo;
          end;
        2:
          begin
            FRich.SelStart := FRich.Document.Text.Length;
            FRich.SelLength := 0;
            FRich.Key8('q');
            FRich.Undo;
          end;
      else
        // its own step, undone and put back
        FRich.Undo;
        FRich.Redo;
      end;
      AssertEquals(Format('%d: the content its last part left is there again', [way]), state,
        FRich.Document.ContentState);
      AssertTrue(Format('%d: not noticed before its turn', [way]), FRich.FindRunning);
      TurnUntilDone;
      AssertEquals(Format('%d: told once', [way]), 1, Length(FDone));
      AssertEquals(Format('%d: told cancelled, not done', [way]), Ord(rreCancelled),
        Ord(FReplaceResult.Ending));
      n := CountMatchesOf('Mr.', Text);
      AssertTrue(Format('%d: a part of them is replaced (%d)', [way, n]), (n > 0) and (n < total));
      AssertEquals(Format('%d: it tells what is replaced in the text', [way]), n, FReplaceResult.Replaced);
      AssertTrue(Format('%d: a place to go on from', [way]), FReplaceResult.ResumeAt > 0);
      n := FRich.ReplaceAll('Mr', 'Mr.', [], FReplaceResult.ResumeAt, FReplaceResult.ResumeLength, res);
      AssertEquals(Format('%d: from there: through', [way]), Ord(rreDone), Ord(res.Ending));
      AssertEquals(Format('%d: the rest, none twice', [way]), total, FReplaceResult.Replaced + n);
      AssertTrue(Format('%d: the text one replace of the whole makes', [way]), Text = want);
    end;
  finally
    FRich.FakeClock := False;
  end;
end;

{ Whole word, one line of matches that touch, a replacement that ends in a letter: a replace
  that stops between two of them - at its undo limit, or cancelled - and is started again from
  where it said replaces the second too, as one walk does: the control remembers, with the
  place and the content then, how the walk saw the character before the place, and the replace
  started exactly there with the content unchanged is told. The parts stay bounded (the limit
  ends each call after one). An edit between the stop and the new start - anywhere - and the
  match at the place is judged by the text as it is: behind a letter now, no whole word. }
procedure TTyRichEditFindTest.TestAReplaceGoesOnBetweenTouchingWholeWords;
const
  CCount = 17000;
var
  sb: TStringBuilder;
  src, want: string;
  res: TTyRichReplaceResult;
  i, calls, total, turns, depth: Integer;

  function LineFeeds(const S: string): string;
  begin
    Result := StringReplace(S, #13#10, #10, [rfReplaceAll]);
  end;

begin
  sb := TStringBuilder.Create;
  try
    for i := 1 to CCount do sb.Append('a-');
    src := sb.ToString;
    sb.Clear;
    for i := 1 to CCount do sb.Append(#10 + 'z');
    want := sb.ToString;
  finally
    sb.Free;
  end;
  // the documented loop: again from where it said while the limit ended it
  SetText(src);
  FRich.Document.MaxUndoBytes := 64 * 1024;
  total := FRich.ReplaceAll('a-', #10 + 'z', [rfoWholeWord], 0, -1, res);
  AssertEquals('the limit ended the first call', Ord(rreLimit), Ord(res.Ending));
  AssertEquals('...after one part of them', CRichReplacePartMatches, total);
  calls := 1;
  while (res.Ending = rreLimit) and (calls < 100) do
  begin
    Inc(total, FRich.ReplaceAll('a-', #10 + 'z', [rfoWholeWord], res.ResumeAt, res.ResumeLength, res));
    Inc(calls);
  end;
  AssertEquals('through in the end', Ord(rreDone), Ord(res.Ending));
  AssertEquals('every one, also the ones right behind a stop', CCount, total);
  AssertTrue('the text one walk makes', LineFeeds(Text) = want);
  // in the background, cancelled after a part, started again from where it said
  SetText(src);
  FRich.Document.MaxUndoBytes := 0;
  FRich.FakeClock := True;
  FRich.ClockStep := 1;
  try
    total := 0;
    calls := 0;
    FReplaceResult.ResumeAt := 0;
    FReplaceResult.ResumeLength := -1;
    repeat
      ResetEvents;
      FRich.ReplaceAllAsync('a-', #10 + 'z', [rfoWholeWord], FReplaceResult.ResumeAt,
        FReplaceResult.ResumeLength);
      turns := 0;
      depth := FRich.Document.UndoDepth;
      while FRich.FindRunning and (FRich.Document.UndoDepth = depth) and (turns < 10000) do
      begin
        FRich.Turn;
        Inc(turns);
      end;
      // (a part went in - or it ended, nothing left)
      if FRich.FindRunning then FRich.CancelFind;
      AssertEquals('told', 1, Length(FDone));
      AssertTrue('a part takes at most its share', FReplaceResult.Replaced <= CRichReplacePartMatches);
      Inc(total, FReplaceResult.Replaced);
      Inc(calls);
    until (FReplaceResult.Ending = rreDone) or (calls > 100);
    AssertTrue(Format('in several starts (%d)', [calls]), calls >= 3);
    AssertEquals('in the background: every one', CCount, total);
    AssertTrue('in the background: the text one walk makes', LineFeeds(Text) = want);
  finally
    FRich.FakeClock := False;
  end;
  // an edit between the stop and the new start: judged by the text as it is
  SetText(src);
  FRich.Document.MaxUndoBytes := 64 * 1024;
  total := FRich.ReplaceAll('a-', #10 + 'z', [rfoWholeWord], 0, -1, res);
  AssertEquals('again: the limit', Ord(rreLimit), Ord(res.Ending));
  FRich.Document.MaxUndoBytes := 0;
  AssertTrue(FRich.Document.Execute(TTyRichInsertText.Create(FRich.Document.Text.Length, 'q')));
  Inc(total, FRich.ReplaceAll('a-', #10 + 'z', [rfoWholeWord], res.ResumeAt, res.ResumeLength, res));
  AssertEquals('after an edit: through', Ord(rreDone), Ord(res.Ending));
  AssertEquals('...but for the one behind the stop', CCount - 1, total);
  AssertEquals('...which stands as it was', 1, CountMatchesOf('a-', Text));
  FRich.Document.MaxUndoBytes := 0;
end;

type
  // the application's queue of asynchronous calls, run without pumping any message
  TFindAppQueue = class(TApplication)
  end;

{ Every way the history lets go of the step of a replace that runs in the background: the
  control's ClearUndo; the document's, behind the control; its oldest steps trimmed for the
  byte limit (a key typed on top of the replace's step); the redo side dropped by a new step
  (its step undone, then a key); a new content put into the document behind the control; the
  control's Clear and a load; the control freed. Freed memory is poisoned meanwhile, so that a
  use of the freed command faults instead of reading what happens to be there still.

  The replace ends before its command is gone: the control refers to no command any more, the
  replace is told once, cancelled, with what is replaced in the text and - where the text is
  still there - the place from which a replace replaces the rest and nothing twice. }
procedure TTyRichEditFindTest.TestTheHistoryLetsGoOfARunningReplacesStep;
const
  CWays: array[0..6] of string = ('the control''s ClearUndo', 'the document''s ClearUndo',
    'the byte limit', 'the redo side dropped', 'a new content behind the control', 'Clear',
    'a load');
var
  src, want, what, raised: string;
  res: TTyRichReplaceResult;
  way, turns, n, total, k: Integer;
  st: TBytesStream;
  poisoned: Boolean;
  cmd: TTyRichReplaceAllCommand;
begin
  src := Lines(6000, 'MrMrMrMrMr ');
  SetText(src);
  total := FRich.ReplaceAll('Mr', 'Mr.');
  AssertEquals('one replace of the whole', 6000 * 5, total);
  want := Text;
  FRich.FakeClock := True;
  FRich.ClockStep := 1;
  for way := 0 to High(CWays) do
  begin
    what := CWays[way];
    SetText(src);
    FRich.ClearUndo;
    FRich.Document.MaxUndoBytes := 0;
    FRich.ReplaceAllAsync('Mr', 'Mr.');
    TFindAccess(FRich).FindSlice := 2048;
    turns := 0;
    while FRich.FindRunning and (Length(FProgress) < 6) and (turns < 10000) do
    begin
      FRich.Turn;
      Inc(turns);
    end;
    AssertTrue(what + ': parts went in, more to come', FRich.FindRunning and (Pos('Mr.', Text) > 0));
    AssertTrue(what + ': the control refers to its command',
      TFindAccess(FRich).ReplaceCommand = FRich.Document.UndoStep);
    raised := '';
    poisoned := True;
    BeginPoison;
    try
      try
        case way of
          0:
            begin
              FRich.ClearUndo;
              AssertEquals(what + ': told before it returned', 1, Length(FDone));
            end;
          1: FRich.Document.ClearUndo;
          2:
            begin
              // (the typed key's step stays, the replace's below it goes for the limit)
              FRich.Document.MaxUndoBytes := 64;
              FRich.SelStart := FRich.Document.Text.Length;
              FRich.SelLength := 0;
              FRich.Key8('q');
              AssertEquals(what + ': the replace''s step went', 1, FRich.Document.UndoDepth);
            end;
          3:
            begin
              FRich.Undo;
              FRich.SelStart := FRich.Document.Text.Length;
              FRich.SelLength := 0;
              FRich.Key8('q');
              AssertFalse(what + ': nothing to redo', FRich.Document.CanRedo);
            end;
          4:
            begin
              st := TBytesStream.Create(BytesOf('other text'));
              try
                TyRichLoadText(FRich.Document, st, teUtf8, 0);
              finally
                st.Free;
              end;
            end;
          5: FRich.Clear;
        else
          st := TBytesStream.Create(BytesOf(Rtf('{|rtf1|ansi a Mr|par}')));
          try
            FRich.LoadFromStream(st);
          finally
            st.Free;
          end;
        end;
        AssertTrue(what + ': the control refers to no command', TFindAccess(FRich).ReplaceCommand = nil);
        AssertFalse(what + ': nothing runs', FRich.FindRunning);
        // (what the loop does between two turns, and the turns: nothing of the freed step is used)
        TFindAppQueue(Application).ProcessAsyncCallQueue;
        for k := 1 to 3 do FRich.Turn;
      except
        on E: EAssertionFailedError do
        begin
          EndPoison;
          poisoned := False;
          raise;
        end;
        on E: Exception do raised := E.ClassName + ': ' + E.Message;
      end;
    finally
      if poisoned then EndPoison;
    end;
    AssertEquals(what + ': nothing raised', '', raised);
    AssertEquals(what + ': told once', 1, Length(FDone));
    AssertEquals(what + ': told cancelled', Ord(rreCancelled), Ord(FReplaceResult.Ending));
    if way >= 4 then
    begin
      // the text it ran on is gone (told before it went, or after)
      if way = 4 then AssertEquals(what + ': nothing to go on from', -1, FReplaceResult.ResumeAt);
      AssertTrue(what + ': it tells that it replaced', FReplaceResult.Replaced > 0);
      Continue;
    end;
    n := CountMatchesOf('Mr.', Text);
    AssertEquals(what + ': it tells what is replaced in the text', n, FReplaceResult.Replaced);
    if way = 3 then AssertEquals(what + ': its step was undone: none', 0, n)
    else AssertTrue(what + Format(': a part of them (%d)', [n]), (n > 0) and (n < total));
    AssertTrue(what + ': a place to go on from', FReplaceResult.ResumeAt >= 0);
    FRich.Document.MaxUndoBytes := 0;
    n := FRich.ReplaceAll('Mr', 'Mr.', [], FReplaceResult.ResumeAt, FReplaceResult.ResumeLength, res);
    AssertEquals(what + ': from there: through', Ord(rreDone), Ord(res.Ending));
    AssertEquals(what + ': the rest, none twice', total, FReplaceResult.Replaced + n);
    if way < 2 then AssertTrue(what + ': the text one replace of the whole makes', Text = want)
    else AssertEquals(what + ': every one replaced once', total, CountMatchesOf('Mr.', Text) -
      CountMatchesOf('Mr..', Text));
  end;
  // the control freed while its replace runs: its step goes with the document, no event
  SetText(src);
  FRich.ReplaceAllAsync('Mr', 'Mr.');
  TFindAccess(FRich).FindSlice := 2048;
  turns := 0;
  while FRich.FindRunning and (Length(FProgress) < 6) and (turns < 10000) do
  begin
    FRich.Turn;
    Inc(turns);
  end;
  AssertTrue('freed: parts went in, more to come', FRich.FindRunning);
  raised := '';
  BeginPoison;
  try
    try
      FreeAndNil(FRich);
      TFindAppQueue(Application).ProcessAsyncCallQueue;
    except
      on E: Exception do raised := E.ClassName + ': ' + E.Message;
    end;
  finally
    EndPoison;
  end;
  AssertEquals('freed: nothing raised', '', raised);
  AssertEquals('freed: no event', 0, Length(FDone));
  FRich := TEditProbe.Create(nil);
  FRich.Controller := FCtl;
  FRich.Font.PixelsPerInch := 96;
  FRich.SetBounds(0, 0, 400, 300);
  FRich.OnFindProgress := @Progress;
  FRich.OnReplaceDone := @ReplaceDone;
  { A synchronous replace: when it has returned, its command - the history's step - tells the
    call nothing any more (its tally was on the call's stack) and says nothing when it goes. }
  SetText(src);
  AssertEquals('synchronous: all of them', total, FRich.ReplaceAll('Mr', 'Mr.', [], 0, -1, res));
  cmd := FRich.Document.UndoStep as TTyRichReplaceAllCommand;
  AssertTrue('synchronous: the step tells no tally', cmd.Tally = nil);
  AssertFalse('synchronous: nor that it is freed', Assigned(cmd.OnFreed));
  BeginPoison;
  try
    FRich.ClearUndo;
    for k := 1 to 3 do FRich.Turn;
  finally
    EndPoison;
  end;
end;

initialization
  RegisterTest(TTyRichEditFindTest);
end.
