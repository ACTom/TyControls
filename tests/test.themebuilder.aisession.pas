unit test.themebuilder.aisession;
{ One AI generation (phase 3): the prompt, the conversation, the code block, the checks and
  the two rounds of feedback, against a scripted model (tbaitesthelp) -- and once against
  the real client on its thread, through the local server. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, tbaisession, tbaitesthelp;

type
  TTbAiSessionTests = class(TTestCase)
  private
    FBase: TStringList;
    FSession: TTbAiSession;
    FBackend: TScriptedBackend;
    FStreamedCalls, FFinished: Integer;
    FStreamedOffMain: Boolean;
    procedure Streamed(Sender: TObject);
    procedure Finished(Sender: TObject);
    function Doc(const AText: string): TTbAiDocument;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRightFirstTime;            { S1 }
    procedure TestOneRoundOfFeedback;        { S2 }
    procedure TestTwoRoundsThenTheUser;      { S3 }
    procedure TestNoCodeBlock;               { S4 }
    procedure TestHintsAreNotFedBack;        { S5 }
    procedure TestBaseVariablesAreFine;      { S6 }
    procedure TestAModeThatDoesNotResolve;   { S7 }
    procedure TestEarlierAnswersAreNotSent;  { S8 }
    procedure TestAnAcceptedRequestSaysSo;   { S9 }
    procedure TestANewConversation;          { S10 }
    procedure TestTheProblemList;            { S11 }
    procedure TestStop;                      { S12 }
    procedure TestBusy;                      { S13 }
    procedure TestAFailureInOneSentence;     { S14 }
    procedure TestUnchanged;                 { S15 }
    procedure TestTheCodeBlock;              { S16 }
    procedure TestTheRealBackend;            { S17 }
    procedure TestTheSystemPrompt;           { S18 }
  end;

implementation

uses
  fpjson, tyControls.ThemeLint, tbaiformat, tbaiclient, tbproblems, tbtemplates, tbreference,
  tbfakehttp;

const
  cMarker = '/* MARK-ONE */';

var
  GBase: TStringList = nil;

function BlueTemplate: string;
begin
  Result := StringReplace(TbMinimalTemplate, '--accent: #3B82F6;', '--accent: #ABCDEF;', []);
end;

procedure TTbAiSessionTests.SetUp;
begin
  if GBase = nil then
  begin
    GBase := TStringList.Create;
    TbBaseVarNames(GBase);
  end;
  FBase := GBase;
  FStreamedCalls := 0;
  FFinished := 0;
  FStreamedOffMain := False;
  FSession := TTbAiSession.Create;
  FSession.BaseVars := FBase;
  FBackend := TScriptedBackend.Create;
  FSession.Backend := FBackend;
  FSession.OnStreamed := @Streamed;
  FSession.OnFinished := @Finished;
end;

procedure TTbAiSessionTests.TearDown;
begin
  FreeAndNil(FSession);   { and the backend with it }
  FBackend := nil;
end;

procedure TTbAiSessionTests.Streamed(Sender: TObject);
begin
  Inc(FStreamedCalls);
  if GetCurrentThreadId <> MainThreadID then
    FStreamedOffMain := True;
end;

procedure TTbAiSessionTests.Finished(Sender: TObject);
begin
  Inc(FFinished);
end;

function TTbAiSessionTests.Doc(const AText: string): TTbAiDocument;
begin
  Result := Default(TTbAiDocument);
  Result.Text := AText;
  Result.BaseDir := '';
  Result.Untitled := True;
end;

procedure TTbAiSessionTests.TestRightFirstTime;
var
  o: TTbAiOutcome;
begin
  FBackend.Add(TbAnswerWith(BlueTemplate), aekNone, 200, 3);
  AssertTrue('S1: started', FSession.Generate('make it blue', Doc(TbMinimalTemplate), False));
  o := FSession.Outcome;
  AssertEquals('S1: one request', 1, o.Requests);
  AssertTrue('S1: done', FSession.Stage = tasDone);
  AssertTrue('S1: a candidate', o.HasCandidate);
  AssertEquals('S1: the block', TrimRight(BlueTemplate), TrimRight(StringReplace(o.Candidate, #10, LineEnding, [rfReplaceAll])));
  AssertEquals('S1: no errors', 0, TbIssueErrorCount(o.Issues));
  AssertEquals('S1: the sentence', rsTbAiDoneClean, o.Sentence);
  AssertTrue('S1: streamed', FStreamedCalls >= 1);
  AssertEquals('S1: finished once', 1, FFinished);
end;

procedure TTbAiSessionTests.TestOneRoundOfFeedback;
var
  second: string;
begin
  FBackend.Add(TbAnswerWith('TyButton { frobnicate: 1px; }'));
  FBackend.Add(TbAnswerWith(BlueTemplate));
  FSession.Generate('make it blue', Doc(TbMinimalTemplate), False);
  AssertEquals('S2: two requests', 2, FSession.Outcome.Requests);
  AssertEquals('S2: two starts', 2, FBackend.Starts);
  AssertEquals('S2: the second request has three messages', 3, Length(FBackend.Sent[1]));
  AssertTrue('S2: user first', FBackend.Sent[1][0].Role = tcrUser);
  AssertTrue('S2: then the answer', FBackend.Sent[1][1].Role = tcrAssistant);
  AssertEquals('S2: the answer as it came', TbAnswerWith('TyButton { frobnicate: 1px; }'),
    FBackend.Sent[1][1].Text);
  second := FBackend.Sent[1][2].Text;
  AssertTrue('S2: then the feedback', FBackend.Sent[1][2].Role = tcrUser);
  AssertTrue('S2: the position: ' + second, Pos('- line 1, col 12:', second) > 0);
  AssertTrue('S2: the property', Pos('frobnicate', second) > 0);
  AssertTrue('S2: ends asking for the whole file', Copy(second, Length(second) - 19, 20) = 'Change nothing else.');
  AssertEquals('S2: no errors at the end', 0, TbIssueErrorCount(FSession.Outcome.Issues));
  AssertTrue('S2: done', FSession.Stage = tasDone);
end;

procedure TTbAiSessionTests.TestTwoRoundsThenTheUser;
var
  o: TTbAiOutcome;
begin
  FBackend.Add(TbAnswerWith('TyButton { frobnicate: 1px; }'));
  FSession.Generate('make it blue', Doc(TbMinimalTemplate), False);
  o := FSession.Outcome;
  AssertEquals('S3: three requests, not four', 3, o.Requests);
  AssertEquals('S3: three starts', 3, FBackend.Starts);
  AssertTrue('S3: done', FSession.Stage = tasDone);
  AssertTrue('S3: the candidate is offered', o.HasCandidate);
  AssertEquals('S3: the error is left', 1, TbIssueErrorCount(o.Issues));
  AssertEquals('S3: the sentence', Format(rsTbAiDoneIssues, [1]), o.Sentence);
end;

procedure TTbAiSessionTests.TestNoCodeBlock;
begin
  FBackend.Add('I would rather not.');
  FSession.Generate('make it blue', Doc(TbMinimalTemplate), False);
  AssertTrue('S4: failed', FSession.Stage = tasFailed);
  AssertEquals('S4: one request', 1, FSession.Outcome.Requests);
  AssertEquals('S4: the sentence', rsTbAiNoBlock, FSession.Outcome.Sentence);
  AssertEquals('S4: the answer is kept', 'I would rather not.', FSession.Outcome.Raw);
  AssertFalse('S4: no candidate', FSession.Outcome.HasCandidate);
end;

procedure TTbAiSessionTests.TestHintsAreNotFedBack;
var
  o: TTbAiOutcome;
  i: Integer;
  hint: Boolean;
begin
  FBackend.Add(TbAnswerWith(':root { --c: #112233; }'#10'TyButton { background: #111111; color: #131313; }'));
  FSession.Generate('dark buttons', Doc(TbMinimalTemplate), False);
  o := FSession.Outcome;
  AssertEquals('S5: one request', 1, o.Requests);
  hint := False;
  for i := 0 to High(o.Issues) do
    if not o.Issues[i].IsError then hint := True;
  AssertTrue('S5: a hint is listed', hint);
  AssertEquals('S5: no error', 0, TbIssueErrorCount(o.Issues));
end;

procedure TTbAiSessionTests.TestBaseVariablesAreFine;
begin
  FBackend.Add(TbAnswerWith('TyButton { background: var(--surface-hover); }'));
  FSession.Generate('x', Doc(TbMinimalTemplate), False);
  AssertEquals('S6: one request', 1, FSession.Outcome.Requests);
  AssertEquals('S6: no error', 0, TbIssueErrorCount(FSession.Outcome.Issues));
end;

procedure TTbAiSessionTests.TestAModeThatDoesNotResolve;
var
  first: TTbAiIssues;
  i: Integer;
  found: Boolean;
begin
  first := TbCheckCandidate('@mode light { :root { --only-light: #123456; } }'#10 +
    '@mode dark { :root { --x: #000000; } }'#10 +
    'TyButton:disabled { color: var(--only-light); }', '', True, FBase);
  found := False;
  for i := 0 to High(first) do
    if first[i].IsError and (first[i].Line = 0) and (Pos('In dark mode:', first[i].Text) = 1) then
      found := True;
  AssertTrue('S7: dark mode does not resolve', found);
  FBackend.Add(TbAnswerWith('@mode light { :root { --only-light: #123456; } }'#10 +
    '@mode dark { :root { --x: #000000; } }'#10 +
    'TyButton:disabled { color: var(--only-light); }'));
  FBackend.Add(TbAnswerWith(BlueTemplate));
  FSession.Generate('x', Doc(TbMinimalTemplate), False);
  AssertEquals('S7: it was fed back', 2, FSession.Outcome.Requests);
  AssertTrue('S7: the feedback names the mode', Pos('In dark mode:', FBackend.Sent[1][2].Text) > 0);
end;

procedure TTbAiSessionTests.TestEarlierAnswersAreNotSent;
var
  all, user: string;
begin
  FBackend.Add(TbAnswerWith(cMarker + #10 + BlueTemplate));
  FBackend.Add(TbAnswerWith(BlueTemplate));
  FSession.Generate('make it blue', Doc(TbMinimalTemplate), False);
  AssertTrue('the first answer had the marker', Pos(cMarker, FSession.Outcome.Candidate) > 0);
  FSession.MarkLast(False);
  FSession.Generate('darker', Doc(TbMinimalTemplate), False);
  all := FBackend.AllSent(High(FBackend.Sent));
  AssertTrue('S8: the old answer is not sent', Pos('MARK-ONE', all) = 0);
  user := FBackend.Sent[High(FBackend.Sent)][0].Text;
  AssertTrue('S8: the old request, not used: ' + user, Pos('1. make it blue (not used)', user) > 0);
  AssertTrue('S8: the request', Pos('Request: darker', user) > 0);
  AssertTrue('S8: the current file', Pos('--accent: #3B82F6;', user) > 0);
end;

procedure TTbAiSessionTests.TestAnAcceptedRequestSaysSo;
var
  user, doc2: string;
begin
  FBackend.Add(TbAnswerWith(cMarker + #10 + BlueTemplate));
  FSession.Generate('make it blue', Doc(TbMinimalTemplate), False);
  FSession.MarkLast(True);
  doc2 := cMarker + LineEnding + BlueTemplate;
  FSession.Generate('darker', Doc(doc2), False);
  user := FBackend.Sent[High(FBackend.Sent)][0].Text;
  AssertTrue('S9: says accepted', Pos('1. make it blue (accepted: ', user) > 0);
  AssertEquals('S9: the marker once, in the current file', 1,
    Length(user) - Length(StringReplace(user, 'MARK-ONE', 'MARK-ON', [rfReplaceAll])));
end;

procedure TTbAiSessionTests.TestANewConversation;
begin
  FBackend.Add(TbAnswerWith(BlueTemplate));
  FSession.Generate('make it blue', Doc(TbMinimalTemplate), False);
  FSession.ResetConversation;
  AssertEquals('S10: forgotten', 0, FSession.History.Count);
  FSession.Generate('again', Doc(TbMinimalTemplate), False);
  AssertTrue('S10: no earlier requests',
    Pos('Earlier requests', FBackend.Sent[High(FBackend.Sent)][0].Text) = 0);
end;

procedure TTbAiSessionTests.TestTheProblemList;
var
  d: TTbAiDocument;
  msg: string;
begin
  d := Doc(TbMinimalTemplate);
  TbAddProblem(d.Problems, 3, 5, tlsError, tpoLint, 'something is wrong');
  msg := FSession.UserMessage('fix it', d, True);
  AssertTrue('S11: the problem with its place', Pos('- line 3, col 5: something is wrong', msg) > 0);
  msg := FSession.UserMessage('fix it', d, False);
  AssertTrue('S11: not asked for, not sent', Pos('Problems the editor reports', msg) = 0);
end;

procedure TTbAiSessionTests.TestStop;
begin
  FBackend.Hold := True;
  AssertTrue('started', FSession.Generate('x', Doc(TbMinimalTemplate), False));
  AssertTrue('busy', FSession.Busy);
  FSession.Stop;
  AssertEquals('S12: the backend was told', 1, FBackend.Cancels);
  FBackend.ReleaseWith(aekCancelled);
  AssertTrue('S12: stopped', FSession.Stage = tasStopped);
  AssertEquals('S12: the sentence', rsTbAiCancelled, FSession.Outcome.Sentence);
  AssertFalse('S12: not busy', FSession.Busy);
  AssertTrue('S12: can go again', FSession.Generate('y', Doc(TbMinimalTemplate), False));
end;

procedure TTbAiSessionTests.TestBusy;
begin
  FBackend.Hold := True;
  AssertTrue('started', FSession.Generate('x', Doc(TbMinimalTemplate), False));
  AssertFalse('S13: refused while busy', FSession.Generate('y', Doc(TbMinimalTemplate), False));
  AssertEquals('S13: one start', 1, FBackend.Starts);
  FBackend.ReleaseWith(aekCancelled);
end;

procedure TTbAiSessionTests.TestAFailureInOneSentence;
begin
  FBackend.Add('', aekAuth, 401);
  FSession.Generate('x', Doc(TbMinimalTemplate), False);
  AssertTrue('S14: failed', FSession.Stage = tasFailed);
  AssertTrue('S14: the sentence: ' + FSession.Outcome.Sentence,
    Pos(Format(rsTbAiAuth, [401]), FSession.Outcome.Sentence) = 1);
end;

procedure TTbAiSessionTests.TestUnchanged;
var
  crlf: string;
begin
  crlf := StringReplace(StringReplace(TbMinimalTemplate, #13#10, #10, [rfReplaceAll]), #10, #13#10,
    [rfReplaceAll]);
  FBackend.Add(TbAnswerWith(StringReplace(crlf, #13#10, #10, [rfReplaceAll])));
  FSession.Generate('x', Doc(crlf), False);
  AssertFalse('S15: nothing to compare', FSession.Outcome.HasCandidate);
  AssertEquals('S15: the sentence', rsTbAiNoChange, FSession.Outcome.Sentence);
end;

procedure TTbAiSessionTests.TestTheCodeBlock;
var
  b: string;
  t: Boolean;
begin
  AssertTrue('S16: tycss', TbExtractCodeBlock('x'#10'```tycss'#10'a'#10'```', b, t));
  AssertEquals('S16: its text', 'a', b);
  AssertTrue('S16: css', TbExtractCodeBlock('```css'#10'b'#10'```', b, t));
  AssertEquals('S16: css text', 'b', b);
  AssertTrue('S16: two', TbExtractCodeBlock('```css'#10'c'#10'```'#10'```tycss'#10'd'#10'```', b, t));
  AssertEquals('S16: the tycss one', 'd', b);
  AssertTrue('S16: one untagged', TbExtractCodeBlock('```'#10'e'#10'```', b, t));
  AssertEquals('S16: it', 'e', b);
  AssertTrue('S16: two untagged', TbExtractCodeBlock('```'#10'f'#10'```'#10'```'#10'ggg'#10'```', b, t));
  AssertEquals('S16: the longer', 'ggg', b);
  AssertFalse('S16: not closed', TbExtractCodeBlock('```tycss'#10'a', b, t));
  AssertTrue('S16: says cut off', t);
  AssertTrue('S16: CRLF', TbExtractCodeBlock('x'#13#10'```tycss'#13#10'a'#13#10'```', b, t));
  AssertEquals('S16: CRLF text', 'a', b);
  AssertFalse('S16: none', TbExtractCodeBlock('no code here', b, t));
  AssertFalse('S16: none is not cut off', t);
  AssertTrue('S16: blank lines go', TbExtractCodeBlock('```tycss'#10#10'a'#10'b'#10#10'```', b, t));
  AssertEquals('S16: inner kept', 'a'#10'b', b);
end;

{ an OpenAI stream answering ATEXT in a few events }
function OpenAIStream(const AText: string): RawByteString;

  function Chunk(const AContent: string; const AFinish: string): string;
  var
    o, c, d: TJSONObject;
    arr: TJSONArray;
  begin
    o := TJSONObject.Create;
    try
      o.Add('id', 'chatcmpl-s17');
      o.Add('object', 'chat.completion.chunk');
      arr := TJSONArray.Create;
      c := TJSONObject.Create;
      c.Add('index', 0);
      d := TJSONObject.Create;
      if AContent <> '' then
        d.Add('content', AContent);
      c.Add('delta', d);
      if AFinish <> '' then
        c.Add('finish_reason', AFinish)
      else
        c.Add('finish_reason', TJSONNull.Create);
      arr.Add(c);
      o.Add('choices', arr);
      Result := 'data: ' + o.AsJSON + #10#10;
    finally
      o.Free;
    end;
  end;

var
  i, size: Integer;
begin
  Result := '';
  size := Length(AText) div 4 + 1;
  i := 1;
  while i <= Length(AText) do
  begin
    Result := Result + Chunk(Copy(AText, i, size), '');
    Inc(i, size);
  end;
  Result := Result + Chunk('', 'stop') + 'data: [DONE]'#10#10;
end;

procedure TTbAiSessionTests.TestTheRealBackend;
var
  srv: TTbFakeHttpServer;
  prof: TTbAiProfile;
  data: RawByteString;
  t0: QWord;
  half: Integer;
begin
  srv := TTbFakeHttpServer.Create;
  try
    data := OpenAIStream(TbAnswerWith(BlueTemplate));
    half := Length(data) div 2;
    srv.Script([FakeSend(FakeHead(200, 'text/event-stream', True)),
      FakeSend(FakeChunk(Copy(data, 1, half))), FakeSleep(100),
      FakeSend(FakeChunk(Copy(data, half + 1, MaxInt))), FakeSend(FakeLastChunk)]);
    prof := Default(TTbAiProfile);
    prof.Format := tafOpenAI;
    prof.BaseUrl := srv.Url('/v1');
    prof.Model := 'm';
    prof.TimeoutSec := 10;
    FSession.Backend := TTbClientBackend.Create(prof, '');
    FBackend := nil;
    AssertTrue('started', FSession.Generate('make it blue', Doc(TbMinimalTemplate), False));
    t0 := GetTickCount64;
    while (FFinished = 0) and (GetTickCount64 - t0 < 10000) do
      CheckSynchronize(10);
    AssertEquals('S17: finished within 10 s (stage ' + IntToStr(Ord(FSession.Stage)) + ')', 1, FFinished);
    AssertTrue('S17: done: ' + FSession.Outcome.Sentence, FSession.Stage = tasDone);
    AssertEquals('S17: one request', 1, FSession.Outcome.Requests);
    AssertTrue('S17: streamed', FStreamedCalls > 0);
    AssertFalse('S17: on the main thread', FStreamedOffMain);
    FreeAndNil(FSession);
    CheckSynchronize(50);
  finally
    srv.Free;
  end;
end;

procedure TTbAiSessionTests.TestTheSystemPrompt;
var
  s: string;
begin
  s := TbSystemPrompt;
  AssertTrue('S18: the rules first', Pos('You edit themes for TyControls', s) = 1);
  AssertTrue('S18: the reference', Pos(TbReferenceText, s) > 0);
  AssertTrue('S18: one tycss block', Pos('```tycss', s) > 0);
end;

initialization
  RegisterTest(TTbAiSessionTests);
finalization
  FreeAndNil(GBase);
end.
