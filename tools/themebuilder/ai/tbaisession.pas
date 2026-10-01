unit tbaisession;
{ One AI generation (spec §7.2, §7.3), on the main thread: the prompt, the conversation, the
  streamed answer, the code block taken out of it, the checks, and up to two rounds of
  feedback.

  The prompt. The system prompt is the answering rules plus the short reference
  (tbreference), in English. Each request then carries the current file in full and the
  description; earlier descriptions of this conversation are listed (each saying whether its
  result was accepted or not used) but earlier ANSWERS are never sent again -- the cost of
  a request does not grow with the conversation. Optionally the editor's problem list.

  The checks (TbCheckCandidate): the problem list the editor itself would show for the
  candidate (parse errors, unknown properties, undefined variables -- less the variables
  the base defines -- and low contrast as a hint), then, when it parses, a load into a
  fresh style model and a probe in every mode (TbProbeDocument): a file that parses and
  lints clean can still be refused by the preview (a variable only one mode defines, a seed
  the base rules cannot take). Errors go back to the model, at most TbAiMaxFeedback times;
  hints never do. What is left after that goes to the user with the candidate.

  The backend (TTbChatBackend) does one request at a time and calls back on the MAIN
  thread. TTbClientBackend runs TTbAiClient on a worker thread: the pieces of text are
  gathered under a lock and handed over with TThread.Queue at most every 100 ms; the
  result follows the last of them. The tests put a scripted backend in its place.

  Everything here except the worker stays on the main thread: the parser, the lint and the
  style model keep process-wide state. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, SyncObjs, tbaiformat, tbaiclient, tbproblems;

resourcestring
  rsTbAiNoBlock = 'The reply has no tycss code block; its text is shown below.';
  rsTbAiRetrying = 'Found %d problems; asking the model to fix them (%d of %d)...';
  rsTbAiNoChange = 'The model returned the file unchanged.';
  rsTbAiDoneIssues = 'Done, with %d problems left.';
  rsTbAiDoneClean = 'Done.';
  rsTbAiModeProbe = 'In %s mode: %s';
  rsTbAiSending = 'Sending to %s...';
  rsTbAiThinking = 'The model is thinking...';
  rsTbAiReceiving = 'Receiving: %d lines so far.';
  rsTbAiChecking = 'Checking the result...';
  rsTbAiOutsideRef = 'The AI added a reference outside the document''s folder: %s. It was not read.';

type
  TTbAiIssue = record
    Line, Col: Integer;           { in the candidate; 0 = no position }
    IsError: Boolean;
    Text: string;                 { for the user }
    { for the model: never a piece of a file the candidate imports (an issue on an @import
      line says only that the imported file has a problem) }
    FeedText: string;
  end;
  TTbAiIssues = array of TTbAiIssue;

  TTbAiStage = (tasIdle, tasSending, tasThinking, tasReceiving, tasChecking, tasRetrying,
    tasDone, tasFailed, tasStopped);

  TTbAiOutcome = record
    HasCandidate: Boolean;
    BaseText, Candidate, Raw: string;   { Raw: the last answer as it came }
    Issues: TTbAiIssues;          { what is left: errors and hints }
    Requests: Integer;            { 1..1 + TbAiMaxFeedback }
    Sentence: string;             { the one sentence for the status line }
  end;

  TTbAiDoneEvent = procedure(Sender: TObject; const AResult: TTbAiResult) of object;

  { one request at a time; OnDelta / OnDone on the MAIN thread }
  TTbChatBackend = class
  private
    FOnDelta: TTbAiDeltaEvent;
    FOnDone: TTbAiDoneEvent;
  protected
    FProfile: TTbAiProfile;
  public
    procedure Start(const ASystem: string; const AMessages: TTbChatMessages); virtual; abstract;
    procedure Cancel; virtual; abstract;
    property Profile: TTbAiProfile read FProfile write FProfile;   { for the sentences }
    property OnDelta: TTbAiDeltaEvent read FOnDelta write FOnDelta;
    property OnDone: TTbAiDoneEvent read FOnDone write FOnDone;
  end;

  TTbClientBackend = class;

  TTbAiWorker = class(TThread)
  private
    FOwner: TTbClientBackend;
    FClient: TTbAiClient;
    FSystem: string;
    FMessages: TTbChatMessages;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TTbClientBackend; AClient: TTbAiClient; const ASystem: string;
      const AMessages: TTbChatMessages);
  end;

  { TTbAiClient on a worker thread }
  TTbClientBackend = class(TTbChatBackend)
  private
    FKey: string;
    FLock: TCriticalSection;
    FWorker: TTbAiWorker;
    FClient: TTbAiClient;
    FPending: string;
    FPendingThinking: Boolean;
    FQueued: Boolean;
    FLastQueued: QWord;
    FResult: TTbAiResult;
    procedure WorkerDelta(Sender: TObject; APiece: TTbStreamPiece; const AText: string);
    procedure WorkerDone(const AResult: TTbAiResult);
    procedure FlushOnMain;
    procedure DoneOnMain;
    procedure DropWorker;
  public
    constructor Create(const AProfile: TTbAiProfile; const AKey: string);
    destructor Destroy; override;
    procedure Start(const ASystem: string; const AMessages: TTbChatMessages); override;
    procedure Cancel; override;
    function Running: Boolean;
  end;

  TTbAiDocument = record
    Text, BaseDir: string;
    Untitled: Boolean;
    Problems: TTbProblems;
  end;

const
  TbAiMaxFeedback = 2;

function TbSystemPrompt: string;                 { the rules + TbReferenceText }
{ the code block of AReply: the first tagged tycss, else the first css, else the only
  untagged one, else the longest; False when there is none, or (ATruncated) when one opens
  and never closes }
function TbExtractCodeBlock(const AReply: string; out ABlock: string;
  out ATruncated: Boolean): Boolean;
{ ABaseText: the document the request was made from -- a reference it already had is the
  user's own; one the answer adds that leaves the document's folder is an error and is
  not resolved, and then nothing else is checked (it would be read) }
function TbCheckCandidate(const AText, ABaseDir: string; AUntitled: Boolean;
  ABaseVars: TStrings; const ABaseText: string = ''): TTbAiIssues;
{ the @import / url() paths AText has and ABaseText has not that leave the folder ABaseDir
  (with no folder -- an untitled document -- every new @import) }
function TbOutsideReferences(const AText, ABaseText, ABaseDir: string): TStringArray;
function TbIssueErrorCount(const AIssues: TTbAiIssues): Integer;
function TbAiIssueCaption(const AIssue: TTbAiIssue): string;   { '12:5  text' / '—  text' }
function TbFeedbackMessage(const AIssues: TTbAiIssues): string;

type
  TTbAiSession = class
  private
    FBackend: TTbChatBackend;
    FBaseVars: TStrings;
    FHistory: TStringList;
    FDoc: TTbAiDocument;
    FMessages: TTbChatMessages;
    FRound: Integer;
    FStreamed: string;
    FOutcome: TTbAiOutcome;
    FStage: TTbAiStage;
    FBusy: Boolean;
    FStopping: Boolean;
    FOnStage: TNotifyEvent;
    FOnStreamed: TNotifyEvent;
    FOnFinished: TNotifyEvent;
    procedure SetBackend(AValue: TTbChatBackend);
    procedure SetStage(AStage: TTbAiStage);
    procedure BackendDelta(Sender: TObject; APiece: TTbStreamPiece; const AText: string);
    procedure BackendDone(Sender: TObject; const AResult: TTbAiResult);
    procedure Finish(AStage: TTbAiStage; const ASentence: string);
  public
    constructor Create;
    destructor Destroy; override;
    { False: busy, no backend or an empty description }
    function Generate(const ADescription: string; const ADoc: TTbAiDocument;
      AWithProblems: Boolean): Boolean;
    procedure Stop;
    procedure ResetConversation;
    procedure MarkLast(AAccepted: Boolean);
    { the user message for a request now (the earlier descriptions, not this one) }
    function UserMessage(const ADescription: string; const ADoc: TTbAiDocument;
      AWithProblems: Boolean): string;
    property Backend: TTbChatBackend read FBackend write SetBackend;   { owned }
    property BaseVars: TStrings read FBaseVars write FBaseVars;        { not owned }
    property History: TStringList read FHistory;     { descriptions; Objects: 0 open, 1 accepted, 2 not used }
    property Stage: TTbAiStage read FStage;
    property Outcome: TTbAiOutcome read FOutcome;
    property Streamed: string read FStreamed;     { the current answer so far }
    property Busy: Boolean read FBusy;
    property Round: Integer read FRound;          { 1, then 2 and 3 for the feedback rounds }
    property LastMessages: TTbChatMessages read FMessages;   { FOR THE TESTS }
    property OnStage: TNotifyEvent read FOnStage write FOnStage;
    property OnStreamed: TNotifyEvent read FOnStreamed write FOnStreamed;
    property OnFinished: TNotifyEvent read FOnFinished write FOnFinished;
  end;

implementation

uses
  tyControls.ThemeLint, tyControls.StyleModel, tbthemesource, tbpreview, tbdiff, tbreference,
  tbexport;

{ What the model is told -- English, never translated (they are not the user's words). }
const
  cRules =
    'You edit themes for TyControls, a control library for Lazarus and Free Pascal. ' +
    'A theme is a .tycss file, a small CSS dialect described in the reference below. ' +
    'The user''s file sits on top of the library''s built-in base theme, so a file that ' +
    'only sets the six seed variables is already a complete theme.'#10#10 +
    'How to answer:'#10 +
    '1. Output the whole new file in exactly one fenced code block that starts with ```tycss. ' +
    'You may write one short sentence before it, in the user''s language. Write nothing after it.'#10 +
    '2. Keep the file''s structure. If it has @mode light and @mode dark blocks, keep both and ' +
    'change both consistently. If it has none, do not add them unless asked.'#10 +
    '3. Use only the properties, functions, states and TypeKeys listed in the reference.'#10 +
    '4. Prefer changing the seed variables and the derived variables over writing rules.'#10 +
    '5. A plain rule for a TypeKey (no .variant, no :state) replaces all of the base theme''s ' +
    'rules for that TypeKey: if you write one, restate everything that control needs, in every ' +
    'state and variant. A rule with a variant or a state replaces nothing and is applied on top ' +
    'of the base, so it can stay small (TyEdit:focus { border-color: ...; }).'#10 +
    '6. Keep text readable: enough contrast against its background, in both modes.'#10 +
    '7. Keep everything the user did not ask to change, comments included.'#10#10;
  cEarlier = 'Earlier requests in this conversation, oldest first:';
  cAccepted = ' (accepted: the current file includes it)';
  cNotUsed = ' (not used)';
  cProblems = 'Problems the editor reports in the current file:';
  cCurrent = 'Current file:';
  cRequest = 'Request: ';
  cFeedbackHead = 'The theme engine found problems in your file:';
  cFeedbackTail = 'Fix them and output the whole corrected file again in one ```tycss block. ' +
    'Change nothing else.';
  cOutsideRefFeed = 'reference outside the document''s folder: %s. Only files in the ' +
    'document''s folder may be referenced; remove it.';
  cImportedProblem = 'the file imported on this line has a problem (its content is not ' +
    'shown here).';

function TbSystemPrompt: string;
begin
  Result := cRules + TbReferenceText;
end;

function Lf(const S: string): string;
begin
  Result := StringReplace(S, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
end;

{ ---- the code block ---- }

function TbExtractCodeBlock(const AReply: string; out ABlock: string;
  out ATruncated: Boolean): Boolean;
var
  lines: TStringList;
  tags, bodies: TStringList;
  i, pick, k: Integer;
  t, tag: string;
  inBlock: Boolean;
  body: string;

  function TrimBlankLines(const S: string): string;
  var
    a, b: Integer;
  begin
    Result := S;
    { leading blank lines }
    a := 1;
    while True do
    begin
      b := Pos(#10, Copy(Result, a, MaxInt));
      if (b = 0) or (Trim(Copy(Result, a, b - 1)) <> '') then Break;
      Inc(a, b);
    end;
    Result := Copy(Result, a, MaxInt);
    { trailing blank lines }
    while (Result <> '') and (Result[Length(Result)] in [#10, ' ', #9]) do
    begin
      b := Length(Result);
      while (b > 0) and (Result[b] in [' ', #9]) do Dec(b);
      if (b > 0) and (Result[b] = #10) then
        SetLength(Result, b - 1)
      else
        Break;
    end;
  end;

begin
  ABlock := '';
  ATruncated := False;
  Result := False;
  lines := TStringList.Create;
  tags := TStringList.Create;
  bodies := TStringList.Create;
  try
    TbSplitLines(AReply, lines);
    inBlock := False;
    tag := '';
    body := '';
    for i := 0 to lines.Count - 1 do
    begin
      t := TrimLeft(lines[i]);
      if Copy(t, 1, 3) = '```' then
      begin
        if not inBlock then
        begin
          inBlock := True;
          tag := LowerCase(Trim(Copy(t, 4, MaxInt)));
          body := '';
        end
        else
        begin
          inBlock := False;
          tags.Add(tag);
          bodies.Add(TrimBlankLines(body));
        end;
      end
      else if inBlock then
        body := body + lines[i] + #10;
    end;
    if inBlock and (bodies.Count = 0) then
    begin
      ATruncated := True;   { the reply ended inside its code block }
      Exit;
    end;
    if bodies.Count = 0 then Exit;
    pick := tags.IndexOf('tycss');
    if pick < 0 then
      pick := tags.IndexOf('css');
    if pick < 0 then
    begin
      k := 0;
      for i := 0 to tags.Count - 1 do
        if tags[i] = '' then
        begin
          Inc(k);
          pick := i;
        end;
      if k <> 1 then
        pick := -1;
    end;
    if pick < 0 then
    begin
      pick := 0;
      for i := 1 to bodies.Count - 1 do
        if Length(bodies[i]) > Length(bodies[pick]) then
          pick := i;
    end;
    ABlock := bodies[pick];
    Result := True;
  finally
    lines.Free;
    tags.Free;
    bodies.Free;
  end;
end;

{ ---- the checks ---- }

function Issue(ALine, ACol: Integer; AIsError: Boolean; const AText: string;
  const AFeedText: string = ''): TTbAiIssue;
begin
  Result.Line := ALine;
  Result.Col := ACol;
  Result.IsError := AIsError;
  Result.Text := AText;
  if AFeedText <> '' then
    Result.FeedText := AFeedText
  else
    Result.FeedText := AText;
end;

function TbOutsideReferences(const AText, ABaseText, ABaseDir: string): TStringArray;
var
  mine, base, imports: TStringArray;
  i, k: Integer;
  known, leaves: Boolean;
begin
  Result := nil;
  mine := TbAllReferences(AText);
  base := TbAllReferences(ABaseText);
  imports := TbImportReferences(AText);
  for i := 0 to High(mine) do
  begin
    leaves := TbReferenceLeavesFolder(mine[i]);
    { an untitled document has no folder: an @import would be read from wherever the
      process happens to stand }
    if (not leaves) and (ABaseDir = '') then
      for k := 0 to High(imports) do
        if imports[k] = mine[i] then
          leaves := True;
    if not leaves then Continue;
    known := False;
    for k := 0 to High(base) do
      if Trim(base[k]) = Trim(mine[i]) then
        known := True;
    if not known then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := mine[i];
    end;
  end;
end;

{ the 1-based lines of AText that hold an @import }
function ImportLines(const AText: string): TStringList;
var
  i: Integer;
begin
  Result := TStringList.Create;
  TbSplitLines(AText, Result);
  for i := 0 to Result.Count - 1 do
    if Pos('@import', LowerCase(Result[i])) > 0 then
      Result.Objects[i] := TObject(PtrInt(1));
end;

{ a message that may quote an imported file: every "quoted" piece left out }
function WithoutQuotes(const S: string): string;
var
  i: Integer;
  inQuote: Boolean;
begin
  Result := '';
  inQuote := False;
  for i := 1 to Length(S) do
    if S[i] = '"' then
    begin
      if not inQuote then
        Result := Result + '"...';
      inQuote := not inQuote;
      if not inQuote then
        Result := Result + '"';
    end
    else if not inQuote then
      Result := Result + S[i];
end;

procedure AddIssue(var AList: TTbAiIssues; const AIssue: TTbAiIssue);
begin
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := AIssue;
end;

function ModeCaption(const AMode: string): string;
begin
  if SameText(AMode, 'light') then
    Result := rsTbModeLight
  else if SameText(AMode, 'dark') then
    Result := rsTbModeDark
  else
    Result := AMode;
end;

function TbCheckCandidate(const AText, ABaseDir: string; AUntitled: Boolean;
  ABaseVars: TStrings; const ABaseText: string): TTbAiIssues;
var
  probs: TTbProblems;
  i: Integer;
  model: TTyStyleModel;
  modes, outside: TStringArray;
  err, feed: string;
  imports: TStringList;
  hasImports: Boolean;

  { a message with no position may come out of an imported file: its quotes stay home }
  function Unplaced(const AMsg: string): string;
  begin
    if hasImports then
      Result := WithoutQuotes(AMsg)
    else
      Result := AMsg;
  end;

begin
  Result := nil;
  { a reference the answer added that leaves the document's folder is not followed at all:
    the checks below would read it, and their messages go back to the model }
  outside := TbOutsideReferences(AText, ABaseText, ABaseDir);
  if Length(outside) > 0 then
  begin
    for i := 0 to High(outside) do
      AddIssue(Result, Issue(0, 0, True, Format(rsTbAiOutsideRef, [outside[i]]),
        Format(cOutsideRefFeed, [outside[i]])));
    Exit;
  end;
  imports := ImportLines(AText);
  try
    hasImports := False;
    for i := 0 to imports.Count - 1 do
      if imports.Objects[i] <> nil then
        hasImports := True;
    probs := TbCollectProblems(AText, ABaseDir, AUntitled, ABaseVars);
    for i := 0 to High(probs) do
    begin
      { lint puts an imported file's problems on the @import that brought it in }
      feed := probs[i].Text;
      if (probs[i].Line > 0) and (probs[i].Line <= imports.Count) and
         (imports.Objects[probs[i].Line - 1] <> nil) then
        feed := cImportedProblem
      else if probs[i].Line = 0 then
        feed := Unplaced(feed);
      AddIssue(Result, Issue(probs[i].Line, probs[i].Col, probs[i].Severity = tlsError,
        probs[i].Text, feed));
    end;
  finally
    imports.Free;
  end;
  if TbHasParseError(probs) then
    Exit;
  { what the preview would do with it: load, then resolve in every mode }
  model := TTyStyleModel.Create;
  try
    try
      model.LoadFromSource(TTbTextThemeSource.Create(AText, ABaseDir));
    except
      on E: Exception do
      begin
        AddIssue(Result, Issue(0, 0, True, E.Message, Unplaced(E.Message)));
        Exit;
      end;
    end;
    modes := model.ModeNames;
    if Length(modes) = 0 then
    begin
      model.SetMode('');
      if not TbProbeDocument(model, AText, False, err) then
        AddIssue(Result, Issue(0, 0, True, err, Unplaced(err)));
    end
    else
      for i := 0 to High(modes) do
      begin
        model.SetMode(modes[i]);
        if not TbProbeDocument(model, AText, False, err) then
        begin
          err := Format(rsTbAiModeProbe, [ModeCaption(modes[i]), err]);
          AddIssue(Result, Issue(0, 0, True, err, Unplaced(err)));
        end;
      end;
  finally
    model.Free;
  end;
end;

function TbIssueErrorCount(const AIssues: TTbAiIssues): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(AIssues) do
    if AIssues[i].IsError then
      Inc(Result);
end;

function TbAiIssueCaption(const AIssue: TTbAiIssue): string;
begin
  if AIssue.Line > 0 then
    Result := Format('%d:%d  %s', [AIssue.Line, AIssue.Col, AIssue.Text])
  else
    Result := #$E2#$80#$94'  ' + AIssue.Text;   { an em dash: no position }
end;

function TbFeedbackMessage(const AIssues: TTbAiIssues): string;
var
  i: Integer;
begin
  Result := cFeedbackHead + #10;
  for i := 0 to High(AIssues) do
    if AIssues[i].IsError then
      if AIssues[i].Line > 0 then
        Result := Result + Format('- line %d, col %d: %s', [AIssues[i].Line, AIssues[i].Col,
          AIssues[i].FeedText]) + #10
      else
        Result := Result + '- ' + AIssues[i].FeedText + #10;
  Result := Result + cFeedbackTail;
end;

{ ---- TTbAiWorker / TTbClientBackend ---- }

constructor TTbAiWorker.Create(AOwner: TTbClientBackend; AClient: TTbAiClient;
  const ASystem: string; const AMessages: TTbChatMessages);
begin
  FOwner := AOwner;
  FClient := AClient;
  FSystem := ASystem;
  FMessages := Copy(AMessages);
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TTbAiWorker.Execute;
var
  r: TTbAiResult;
begin
  try
    r := FClient.Run(FSystem, FMessages, @FOwner.WorkerDelta);
  except
    on E: Exception do
    begin
      { Run catches what it can; this is the last line, scrubbed the same way }
      r := Default(TTbAiResult);
      r.Kind := aekOther;
      r.Detail := TbScrubSecret(E.Message, FOwner.FKey);
    end;
  end;
  FOwner.WorkerDone(r);
end;

constructor TTbClientBackend.Create(const AProfile: TTbAiProfile; const AKey: string);
begin
  inherited Create;
  FProfile := AProfile;
  FKey := AKey;
  FLock := TCriticalSection.Create;
end;

destructor TTbClientBackend.Destroy;
begin
  { cancel, wait for the thread, then make sure nothing it queued reaches a freed object;
    waiting on the main thread may run what it queued, so nobody is listening any more }
  OnDelta := nil;
  OnDone := nil;
  Cancel;
  DropWorker;
  TThread.RemoveQueuedEvents(@FlushOnMain);
  TThread.RemoveQueuedEvents(@DoneOnMain);
  FLock.Free;
  inherited Destroy;
end;

procedure TTbClientBackend.DropWorker;
begin
  if FWorker <> nil then
  begin
    FWorker.WaitFor;
    FreeAndNil(FWorker);
  end;
  FLock.Enter;
  try
    FreeAndNil(FClient);
  finally
    FLock.Leave;
  end;
end;

function TTbClientBackend.Running: Boolean;
begin
  Result := (FWorker <> nil) and not FWorker.Finished;
end;

procedure TTbClientBackend.Start(const ASystem: string; const AMessages: TTbChatMessages);
var
  client: TTbAiClient;
begin
  DropWorker;          { the last request's thread has queued its result and is gone }
  FLock.Enter;
  try
    FPending := '';
    FPendingThinking := False;
    FQueued := False;
    FLastQueued := 0;
    client := TTbAiClient.Create(FProfile, FKey);
    FClient := client;
  finally
    FLock.Leave;
  end;
  FWorker := TTbAiWorker.Create(Self, client, ASystem, AMessages);
end;

procedure TTbClientBackend.Cancel;
begin
  FLock.Enter;
  try
    if FClient <> nil then
      FClient.Cancel;
  finally
    FLock.Leave;
  end;
end;

{ worker thread }
procedure TTbClientBackend.WorkerDelta(Sender: TObject; APiece: TTbStreamPiece; const AText: string);
var
  post: Boolean;
  t: QWord;
begin
  FLock.Enter;
  try
    if APiece = tspText then
      FPending := FPending + AText
    else if APiece = tspThinking then
      FPendingThinking := True;
    t := GetTickCount64;
    post := (not FQueued) and ((FLastQueued = 0) or (t - FLastQueued >= 100));
    if post then
    begin
      FQueued := True;
      FLastQueued := t;
    end;
  finally
    FLock.Leave;
  end;
  if post then
    TThread.Queue(nil, @FlushOnMain);
end;

{ worker thread }
procedure TTbClientBackend.WorkerDone(const AResult: TTbAiResult);
begin
  FLock.Enter;
  try
    FResult := AResult;
  finally
    FLock.Leave;
  end;
  TThread.Queue(nil, @DoneOnMain);
end;

{ main thread }
procedure TTbClientBackend.FlushOnMain;
var
  text: string;
  thinking: Boolean;
begin
  FLock.Enter;
  try
    text := FPending;
    thinking := FPendingThinking;
    FPending := '';
    FPendingThinking := False;
    FQueued := False;
  finally
    FLock.Leave;
  end;
  if thinking and Assigned(OnDelta) then
    OnDelta(Self, tspThinking, '');
  if (text <> '') and Assigned(OnDelta) then
    OnDelta(Self, tspText, text);
end;

{ main thread }
procedure TTbClientBackend.DoneOnMain;
var
  r: TTbAiResult;
begin
  FlushOnMain;
  FLock.Enter;
  try
    r := FResult;
  finally
    FLock.Leave;
  end;
  if Assigned(OnDone) then
    OnDone(Self, r);
end;

{ ---- TTbAiSession ---- }

constructor TTbAiSession.Create;
begin
  inherited Create;
  FHistory := TStringList.Create;
  FHistory.OwnsObjects := False;
end;

destructor TTbAiSession.Destroy;
begin
  FOnStage := nil;
  FOnStreamed := nil;
  FOnFinished := nil;
  FreeAndNil(FBackend);   { cancels, waits for its thread, drops what it queued }
  FHistory.Free;
  inherited Destroy;
end;

procedure TTbAiSession.SetBackend(AValue: TTbChatBackend);
var
  wasBusy: Boolean;
begin
  if AValue = FBackend then Exit;
  wasBusy := FBusy;
  if FBackend <> nil then
  begin
    FBackend.OnDelta := nil;
    FBackend.OnDone := nil;
    FBackend.Cancel;
    FreeAndNil(FBackend);
  end;
  FBackend := AValue;
  if FBackend <> nil then
  begin
    FBackend.OnDelta := @BackendDelta;
    FBackend.OnDone := @BackendDone;
  end;
  { the request went with its backend and will not call back: it ends here as stopped,
    the way a Stop ends -- the page hears it (OnStage, OnFinished) and goes idle. A
    candidate an earlier round of it produced is kept, to be looked at }
  if wasBusy then
    Finish(tasStopped, rsTbAiCancelled);
end;

procedure TTbAiSession.SetStage(AStage: TTbAiStage);
begin
  FStage := AStage;
  if Assigned(FOnStage) then
    FOnStage(Self);
end;

function TTbAiSession.UserMessage(const ADescription: string; const ADoc: TTbAiDocument;
  AWithProblems: Boolean): string;
var
  i, n: Integer;
  s: string;
begin
  s := '';
  if FHistory.Count > 0 then
  begin
    s := s + cEarlier + #10;
    for i := 0 to FHistory.Count - 1 do
    begin
      s := s + IntToStr(i + 1) + '. ' + Lf(FHistory[i]);
      case PtrInt(FHistory.Objects[i]) of
        1: s := s + cAccepted;
        2: s := s + cNotUsed;
      end;
      s := s + #10;
    end;
    s := s + #10;
  end;
  n := Length(ADoc.Problems);
  if AWithProblems and (n > 0) then
  begin
    s := s + cProblems + #10;
    for i := 0 to n - 1 do
      if ADoc.Problems[i].Line > 0 then
        s := s + Format('- line %d, col %d: %s', [ADoc.Problems[i].Line, ADoc.Problems[i].Col,
          ADoc.Problems[i].Text]) + #10
      else
        s := s + '- ' + ADoc.Problems[i].Text + #10;
    s := s + #10;
  end;
  s := s + cCurrent + #10 + '```tycss' + #10 + Lf(ADoc.Text);
  if (s <> '') and (s[Length(s)] <> #10) then
    s := s + #10;
  s := s + '```' + #10#10 + cRequest + Lf(ADescription);
  Result := s;
end;

function TTbAiSession.Generate(const ADescription: string; const ADoc: TTbAiDocument;
  AWithProblems: Boolean): Boolean;
var
  last: Integer;
begin
  Result := False;
  if FBusy or (FBackend = nil) or (Trim(ADescription) = '') then Exit;
  { the last request was never accepted: it was not used }
  last := FHistory.Count - 1;
  if (last >= 0) and (PtrInt(FHistory.Objects[last]) = 0) then
    FHistory.Objects[last] := TObject(PtrInt(2));
  FDoc := ADoc;
  SetLength(FMessages, 1);
  FMessages[0] := TbChatMessage(tcrUser, UserMessage(ADescription, ADoc, AWithProblems));
  FHistory.AddObject(ADescription, TObject(PtrInt(0)));
  FRound := 1;
  FStreamed := '';
  FOutcome := Default(TTbAiOutcome);
  FOutcome.BaseText := ADoc.Text;
  FOutcome.Sentence := Format(rsTbAiSending, [TbHostOf(FBackend.Profile.BaseUrl)]);
  FBusy := True;
  FStopping := False;
  SetStage(tasSending);
  { a backend may answer inside Start (the tests' scripted one does): everything is set }
  FBackend.Start(TbSystemPrompt, FMessages);
  Result := True;
end;

procedure TTbAiSession.Stop;
begin
  if not FBusy then Exit;
  FStopping := True;
  if FBackend <> nil then
    FBackend.Cancel;
end;

procedure TTbAiSession.ResetConversation;
begin
  if FBusy then
    Stop;
  FHistory.Clear;
  FOutcome := Default(TTbAiOutcome);
  FStreamed := '';
end;

procedure TTbAiSession.MarkLast(AAccepted: Boolean);
begin
  if FHistory.Count = 0 then Exit;
  if AAccepted then
    FHistory.Objects[FHistory.Count - 1] := TObject(PtrInt(1))
  else
    FHistory.Objects[FHistory.Count - 1] := TObject(PtrInt(2));
end;

procedure TTbAiSession.BackendDelta(Sender: TObject; APiece: TTbStreamPiece; const AText: string);
begin
  if not FBusy then Exit;
  case APiece of
    tspThinking:
      if FStage <> tasThinking then
      begin
        FOutcome.Sentence := rsTbAiThinking;
        SetStage(tasThinking);
      end;
    tspText:
      begin
        FStreamed := FStreamed + AText;
        if FStage <> tasReceiving then
          SetStage(tasReceiving);
        if Assigned(FOnStreamed) then
          FOnStreamed(Self);
      end;
  end;
end;

procedure TTbAiSession.Finish(AStage: TTbAiStage; const ASentence: string);
begin
  FOutcome.Sentence := ASentence;
  FBusy := False;
  FStopping := False;
  SetStage(AStage);
  if Assigned(FOnFinished) then
    FOnFinished(Self);
end;

procedure TTbAiSession.BackendDone(Sender: TObject; const AResult: TTbAiResult);
var
  block: string;
  truncated: Boolean;
  issues: TTbAiIssues;
  errors, n: Integer;
begin
  if not FBusy then Exit;
  FOutcome.Raw := AResult.Text;
  FOutcome.Requests := FRound;
  if (AResult.Kind = aekCancelled) or FStopping then
  begin
    FOutcome.HasCandidate := False;
    Finish(tasStopped, rsTbAiCancelled);
    Exit;
  end;
  if AResult.Kind <> aekNone then
  begin
    { a cut-off reply is not trusted, whatever code block it holds; a candidate from an
      earlier round (with its problems) is still offered }
    Finish(tasFailed, TbAiErrorSentence(AResult, FBackend.Profile));
    Exit;
  end;
  if not TbExtractCodeBlock(AResult.Text, block, truncated) then
  begin
    if truncated then
      Finish(tasFailed, rsTbAiTruncated)
    else
      Finish(tasFailed, rsTbAiNoBlock);
    Exit;
  end;
  SetStage(tasChecking);
  issues := TbCheckCandidate(block, FDoc.BaseDir, FDoc.Untitled, FBaseVars, FDoc.Text);
  FOutcome.Candidate := block;
  FOutcome.Issues := issues;
  FOutcome.HasCandidate := True;
  errors := TbIssueErrorCount(issues);
  if (errors > 0) and (FRound <= TbAiMaxFeedback) then
  begin
    n := Length(FMessages);
    SetLength(FMessages, n + 2);
    FMessages[n] := TbChatMessage(tcrAssistant, AResult.Text);
    FMessages[n + 1] := TbChatMessage(tcrUser, TbFeedbackMessage(issues));
    Inc(FRound);
    FStreamed := '';
    FOutcome.Sentence := Format(rsTbAiRetrying, [errors, FRound - 1, TbAiMaxFeedback]);
    SetStage(tasRetrying);
    FBackend.Start(TbSystemPrompt, FMessages);
    Exit;
  end;
  if TbNormalizeEol(block) = TbNormalizeEol(FDoc.Text) then
  begin
    FOutcome.HasCandidate := False;
    Finish(tasDone, rsTbAiNoChange);
  end
  else if errors > 0 then
    Finish(tasDone, Format(rsTbAiDoneIssues, [errors]))
  else
    Finish(tasDone, rsTbAiDoneClean);
end;

end.
