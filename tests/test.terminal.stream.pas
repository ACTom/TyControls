unit test.terminal.stream;
{$mode objfpc}{$H+}
{ The core's stream hooks (spec 19.3-19.5; ours, no upstream oracle): a fake in-band
  protocol, TFakeProtocol, claims the program's output at '<<GO>>' and hands back what
  follows '<<END>>'. Each test is one criterion of the phase 7 plan (H1-H28) and names
  the mutation it must go red under. TFakeProtocol is exported for the control's
  tests (test.terminal.view.stream). }

interface

uses
  Classes, SysUtils, fpcunit, testregistry, tyControls.Terminal.Parser, tyControls.Terminal.Core;

type
  TFakeProtocol = class;
  TFakeHook = procedure(AProto: TFakeProtocol) of object;

  { How Detect answers: at the marker '<<GO>>' (remembering a prefix cut at the end of
    a piece), at a fixed place, at the end of the piece, or one past it. }
  TFakeClaimMode = (fcmMarker, fcmFixed, fcmEnd, fcmBeyond);

  TFakeProtocol = class(TTyTerminalStreamHandler)
  public
    Name: string;
    Log: TStrings;                       { not owned; nil = no log }
    Core: TTyTerminalCore;
    Session: TTyTerminalStreamSession;
    Mode: TFakeClaimMode;
    FixedAt: Integer;
    Carry: RawByteString;
    Fed: RawByteString;                  { everything fed, all claims }
    ClaimBuf: RawByteString;             { fed during this claim }
    LastDetect: RawByteString;
    LastClaimAt: Integer;
    DetectCalls, Claims, FeedDepth, MaxFeedDepth: Integer;
    LineAtClaimed: string;               { line 0 as Claimed saw it }
    SessionsSeen: array of TTyTerminalStreamSession;
    ReleaseInClaimed: Boolean;           { Release('') at once }
    ReleaseAllOnFirstFeed: Boolean;      { hand back everything it got (H9) }
    RaiseInDetect, RaiseInClaimed, RaiseInFeed: Boolean;
    OnFeed: TFakeHook;                   { after the bytes are taken, before '<<END>>' is looked for }
    OnClaimedHook: TFakeHook;
    constructor Create(const AName: string; ALog: TStrings; ACore: TTyTerminalCore);
    procedure Note(const S: string);
    function Detect(AData: PByte; ACount: Integer; out AClaimAt: Integer): Boolean; override;
    procedure Claimed(ASession: TTyTerminalStreamSession); override;
    procedure Feed(AData: PByte; ACount: Integer); override;
    procedure ClaimEnded(AHow: TTyTerminalClaimEnd); override;
  end;

  TTyTerminalStreamTests = class(TTestCase)
  published
    { Task 1 }
    procedure TestNoHandlerTakesTheFastPath;                 { H1 }
    procedure TestDetectSeesRawBytes;                        { H2 }
    procedure TestTheBytesBeforeTheMarkerAreParsedFirst;     { H3 }
    procedure TestEveryPieceIsOffered;                       { H4 }
    procedure TestAMarkerCutBetweenTwoPieces;                { H5 }
    procedure TestAClaimAtTheEndOfAPiece;                    { H6 }
    procedure TestRemovingTheClaimingHandler;                { H23 }
    procedure TestTheEarliestClaimWins;                      { H24 }
    procedure TestExceptionsFromTheHandler;                  { H25 }
    procedure TestOtherThreadsAreRefused;                    { H26 }
    procedure TestTheDestructorCallsNoHandler;               { H27 }
    procedure TestOneSessionForEveryClaim;                   { H28 }
  end;

{ the text of line AY of the active buffer (from ybase), trailing blanks cut }
function StreamLine(ACore: TTyTerminalCore; AY: Integer): string;
function CountOf(AList: TStrings; const S: string): Integer;

implementation

const
  GoMarker = '<<GO>>';
  EndMarker = '<<END>>';

function StreamLine(ACore: TTyTerminalCore; AY: Integer): string;
begin
  Result := ACore.Buffer.Lines.Get(ACore.Buffer.YBase + AY).TranslateToString(True, 0, ACore.Cols);
end;

function CountOf(AList: TStrings; const S: string): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to AList.Count - 1 do
    if AList[i] = S then
      Inc(Result);
end;

function BytesOf(AData: PByte; ACount: Integer): RawByteString;
begin
  Result := '';
  SetLength(Result, ACount);
  if ACount > 0 then
    Move(AData^, Result[1], ACount);
end;

{ ---- TFakeProtocol ------------------------------------------------------------------- }

constructor TFakeProtocol.Create(const AName: string; ALog: TStrings; ACore: TTyTerminalCore);
begin
  inherited Create;
  Name := AName;
  Log := ALog;
  Core := ACore;
  LastClaimAt := -1;
end;

procedure TFakeProtocol.Note(const S: string);
begin
  if Log = nil then
    Exit;
  if Name <> '' then
    Log.Add(Name + '.' + S)
  else
    Log.Add(S);
end;

function TFakeProtocol.Detect(AData: PByte; ACount: Integer; out AClaimAt: Integer): Boolean;
var
  s: RawByteString;
  p, k: Integer;
begin
  Inc(DetectCalls);
  if DetectCalls > 1000 then
    raise Exception.Create('Detect called 1000 times: the core loops');
  LastDetect := BytesOf(AData, ACount);
  Note('Detect@' + IntToStr(ACount));
  if RaiseInDetect then
    raise Exception.Create('fake Detect raised');
  AClaimAt := 0;
  Result := False;
  case Mode of
    fcmFixed:
      begin
        AClaimAt := FixedAt;
        Result := FixedAt <= ACount;
      end;
    fcmEnd:
      begin
        AClaimAt := ACount;
        Result := True;
      end;
    fcmBeyond:
      begin
        AClaimAt := ACount + 1;
        Result := True;
      end;
  else
    begin
      s := Carry + LastDetect;
      p := Pos(GoMarker, s);
      if p > 0 then
      begin
        AClaimAt := p - 1 - Length(Carry);
        if AClaimAt < 0 then
          AClaimAt := 0;
        Carry := '';
        Result := True;
      end
      else
      begin
        { the longest end of s that begins the marker }
        Carry := '';
        for k := Length(GoMarker) - 1 downto 1 do
          if (Length(s) >= k) and (Copy(s, Length(s) - k + 1, k) = Copy(GoMarker, 1, k)) then
          begin
            Carry := Copy(s, Length(s) - k + 1, k);
            Break;
          end;
      end;
    end;
  end;
  if Result then
    LastClaimAt := AClaimAt;
end;

procedure TFakeProtocol.Claimed(ASession: TTyTerminalStreamSession);
begin
  Inc(Claims);
  Session := ASession;
  SetLength(SessionsSeen, Length(SessionsSeen) + 1);
  SessionsSeen[High(SessionsSeen)] := ASession;
  ClaimBuf := '';
  if Core <> nil then
    LineAtClaimed := StreamLine(Core, 0);
  Note('Claimed');
  if RaiseInClaimed then
    raise Exception.Create('fake Claimed raised');
  if Assigned(OnClaimedHook) then
    OnClaimedHook(Self);
  if ReleaseInClaimed then
    ASession.Release('');
end;

procedure TFakeProtocol.Feed(AData: PByte; ACount: Integer);
var
  got: RawByteString;
  p: Integer;
begin
  Inc(FeedDepth);
  try
    if FeedDepth > MaxFeedDepth then
      MaxFeedDepth := FeedDepth;
    got := BytesOf(AData, ACount);
    Fed := Fed + got;
    ClaimBuf := ClaimBuf + got;
    Note('Feed:' + got);
    if RaiseInFeed then
      raise Exception.Create('fake Feed raised');
    if Assigned(OnFeed) then
      OnFeed(Self);
    if (Session = nil) or not Session.Active or (Session.Handler <> Self) then
      Exit;
    if ReleaseAllOnFirstFeed then
    begin
      Session.Release(ClaimBuf);
      Exit;
    end;
    p := Pos(EndMarker, ClaimBuf);
    if p > 0 then
      Session.Release(Copy(ClaimBuf, p + Length(EndMarker), MaxInt));
  finally
    Dec(FeedDepth);
  end;
end;

procedure TFakeProtocol.ClaimEnded(AHow: TTyTerminalClaimEnd);
begin
  if AHow = tceReset then
    Note('ClaimEnded:reset')
  else
    Note('ClaimEnded:removed');
end;

{ ---- the rig ----------------------------------------------------------------------------- }

type
  TStreamRig = class
  public
    Core: TTyTerminalCore;
    Log: TStringList;
    Now_, Step: Double;
    Sent: RawByteString;                 { OnData }
    SentCount, UserInputs, Requests: Integer;
    ClaimedInput: RawByteString;
    ClaimedCount: Integer;
    Done: TStringList;
    constructor Create(ACols: Integer = 40; ARows: Integer = 5);
    destructor Destroy; override;
    function Clock: Double;
    procedure OnData(Sender: TObject; const AData: RawByteString);
    procedure OnUserInput(Sender: TObject);
    procedure OnClaimedIn(Sender: TObject; const AData: RawByteString);
    procedure OnRequest(Sender: TObject);
    procedure OnDone(Sender: TObject; ATag: PtrInt);
    function Line(AY: Integer = 0): string;
    function Proto(const AName: string = ''): TFakeProtocol;   { created and added }
    procedure Drain;
  end;

constructor TStreamRig.Create(ACols, ARows: Integer);
begin
  inherited Create;
  Log := TStringList.Create;
  Done := TStringList.Create;
  Core := TTyTerminalCore.Create(ACols, ARows);
  Core.Clock := @Clock;
  Core.OnData := @OnData;
  Core.OnUserInput := @OnUserInput;
  Core.OnClaimedInput := @OnClaimedIn;
  Core.OnProcessRequest := @OnRequest;
end;

destructor TStreamRig.Destroy;
begin
  Core.Free;
  Log.Free;
  Done.Free;
  inherited Destroy;
end;

function TStreamRig.Clock: Double;
begin
  Now_ := Now_ + Step;
  Result := Now_;
end;

procedure TStreamRig.OnData(Sender: TObject; const AData: RawByteString);
begin
  Sent := Sent + AData;
  Inc(SentCount);
end;

procedure TStreamRig.OnUserInput(Sender: TObject);
begin
  Inc(UserInputs);
end;

procedure TStreamRig.OnClaimedIn(Sender: TObject; const AData: RawByteString);
begin
  ClaimedInput := ClaimedInput + AData;
  Inc(ClaimedCount);
end;

procedure TStreamRig.OnRequest(Sender: TObject);
begin
  Inc(Requests);
end;

procedure TStreamRig.OnDone(Sender: TObject; ATag: PtrInt);
begin
  Done.Add(IntToStr(ATag));
  Log.Add('done' + IntToStr(ATag));
end;

function TStreamRig.Line(AY: Integer): string;
begin
  Result := StreamLine(Core, AY);
end;

function TStreamRig.Proto(const AName: string): TFakeProtocol;
begin
  Result := TFakeProtocol.Create(AName, Log, Core);
  Core.AddStreamHandler(Result);
end;

procedure TStreamRig.Drain;
var
  guard: Integer;
begin
  guard := 0;
  while Core.ProcessPending do
  begin
    Inc(guard);
    if guard > 100000 then
      raise Exception.Create('ProcessPending never ends');
  end;
end;

{ ---- Task 1: detection and the claim ------------------------------------------------------- }

{ H1. Mutation: the fast path's "FStreamCount = 0" dropped (every piece slow). }
procedure TTyTerminalStreamTests.TestNoHandlerTakesTheFastPath;
var
  r: TStreamRig;
  p: TFakeProtocol;
  mb: RawByteString;
begin
  r := TStreamRig.Create;
  p := nil;
  try
    mb := StringOfChar('.', 1024 * 1024);
    r.Core.WriteSync(mb);
    AssertEquals('no handler: nothing offered', 0, r.Core.StreamPiecesOffered);
    p := r.Proto;
    r.Core.WriteSync('x');
    { the same writes do take the slow path while a handler is there }
    AssertEquals('with a handler: offered', 1, r.Core.StreamPiecesOffered);
    r.Core.RemoveStreamHandler(p);
    AssertEquals('removed', 0, r.Core.StreamHandlerCount);
    r.Core.WriteSync(mb);
    AssertEquals('removed: the fast path again', 1, r.Core.StreamPiecesOffered);
  finally
    r.Free;
    p.Free;
  end;
end;

{ H2. Mutation: StreamPiece handing over the decoded text re-encoded. }
procedure TTyTerminalStreamTests.TestDetectSeesRawBytes;
var
  r: TStreamRig;
  p: TFakeProtocol;
  raw: RawByteString;
begin
  r := TStreamRig.Create;
  p := nil;
  try
    p := r.Proto;
    raw := 'a'#$E4#$B8'b'#$FF;
    r.Core.WriteSync(raw);
    AssertEquals('one Detect', 1, p.DetectCalls);
    AssertTrue('byte for byte, not decoded', p.LastDetect = raw);
  finally
    r.Free;
    p.Free;
  end;
end;

{ H3. Mutations: Claimed before the prefix is parsed; the whole piece parsed. }
procedure TTyTerminalStreamTests.TestTheBytesBeforeTheMarkerAreParsedFirst;
var
  r: TStreamRig;
  p: TFakeProtocol;
begin
  r := TStreamRig.Create;
  p := nil;
  try
    p := r.Proto;
    r.Core.WriteSync('abc<<GO>>xyz');
    AssertEquals('claimed', 1, p.Claims);
    AssertEquals('the prefix was on screen when Claimed ran', 'abc', p.LineAtClaimed);
    AssertTrue('fed from the marker on', p.Fed = '<<GO>>xyz');
    AssertEquals('the screen never shows the claimed bytes', 'abc', r.Line);
    AssertTrue('claimed', r.Core.StreamClaimed);
    AssertTrue('the claiming handler', r.Core.ClaimingHandler = p);
  finally
    r.Free;
    p.Free;
  end;
end;

{ H4. Mutation: only a chunk's first piece is offered. 100 KB: pieces of 32 KB, the
  marker at 70000 is in the third. }
procedure TTyTerminalStreamTests.TestEveryPieceIsOffered;
var
  r: TStreamRig;
  p: TFakeProtocol;
  data: RawByteString;
  slices: Integer;
begin
  r := TStreamRig.Create;
  p := nil;
  try
    p := r.Proto;
    data := StringOfChar('.', 102400);
    Move(PChar(GoMarker)^, data[70001], Length(GoMarker));
    r.Step := 100;                       { one piece a slice }
    r.Core.Write(data);
    slices := 1;
    while r.Core.ProcessPending do
      Inc(slices);
    AssertEquals('four pieces, four slices', 4, slices);
    AssertEquals('asked for the three pieces before the claim', 3, p.DetectCalls);
    AssertEquals('claimed where the marker is', 70000 - 2 * 32768, p.LastClaimAt);
    AssertTrue('the first byte fed is the marker''s', (p.Fed <> '') and (p.Fed[1] = '<'));
    AssertEquals('everything from the marker on', 102400 - 70000, Length(p.Fed));
    AssertEquals('pending', 0, r.Core.PendingBytes);
  finally
    r.Free;
    p.Free;
  end;
end;

{ H5. Mutation: a piece is not offered when the last one found nothing. }
procedure TTyTerminalStreamTests.TestAMarkerCutBetweenTwoPieces;
var
  r: TStreamRig;
  p: TFakeProtocol;
begin
  r := TStreamRig.Create;
  p := nil;
  try
    p := r.Proto;
    r.Core.Write('ab<<G');
    r.Core.Write('O>>zz');
    r.Drain;
    AssertEquals('the first half is already on screen', 'ab<<G', r.Line);
    AssertEquals('asked twice', 2, p.DetectCalls);
    AssertEquals('claimed at the start of the second piece', 0, p.LastClaimAt);
    AssertTrue('fed', p.Fed = 'O>>zz');
  finally
    r.Free;
    p.Free;
  end;
end;

{ H6. Mutation: "at < ACount" written "<=" (an empty Feed). }
procedure TTyTerminalStreamTests.TestAClaimAtTheEndOfAPiece;
var
  r: TStreamRig;
  p: TFakeProtocol;
begin
  r := TStreamRig.Create;
  p := nil;
  try
    p := r.Proto;
    p.Mode := fcmEnd;
    r.Core.WriteSync('abc');
    AssertEquals('the whole piece parsed', 'abc', r.Line);
    AssertTrue('claimed', r.Core.StreamClaimed);
    AssertEquals('no Feed: Detect@3, Claimed', 'Detect@3,Claimed', r.Log.CommaText);
    r.Core.WriteSync('xyz');
    AssertTrue('the next piece is fed whole', p.Fed = 'xyz');
    AssertEquals('the screen stays', 'abc', r.Line);
    AssertEquals('asked once only', 1, p.DetectCalls);
  finally
    r.Free;
    p.Free;
  end;
end;

type
  TRemoveInFeed = class
  public
    Core: TTyTerminalCore;
    procedure Hook(AProto: TFakeProtocol);
  end;

procedure TRemoveInFeed.Hook(AProto: TFakeProtocol);
begin
  Core.RemoveStreamHandler(AProto);
end;

{ H23. Mutation: RemoveStreamHandler not ending the claim. }
procedure TTyTerminalStreamTests.TestRemovingTheClaimingHandler;
var
  r: TStreamRig;
  p: TFakeProtocol;
  rm: TRemoveInFeed;
begin
  r := TStreamRig.Create;
  p := nil;
  rm := TRemoveInFeed.Create;
  try
    p := r.Proto;
    r.Core.WriteSync('<<GO>>');
    AssertTrue('claimed', r.Core.StreamClaimed);
    r.Core.RemoveStreamHandler(p);
    AssertEquals('ClaimEnded once', 1, CountOf(r.Log, 'ClaimEnded:removed'));
    AssertFalse('no claim', r.Core.StreamClaimed);
    AssertFalse('the session is done', r.Core.StreamSession.Active);
    r.Core.WriteSync('q');
    AssertEquals('parsed again', 'q', r.Line);
    FreeAndNil(p);

    { from its own Feed }
    r.Core.Reset;
    r.Log.Clear;
    p := r.Proto;
    rm.Core := r.Core;
    p.OnFeed := @rm.Hook;
    r.Core.WriteSync('<<GO>>abc');
    AssertEquals('ClaimEnded once', 1, CountOf(r.Log, 'ClaimEnded:removed'));
    AssertEquals('nothing after it', 'ClaimEnded:removed', r.Log[r.Log.Count - 1]);
    AssertEquals('no handler', 0, r.Core.StreamHandlerCount);
    r.Core.WriteSync('q');
    AssertEquals('parsed again', 'q', r.Line);
    AssertEquals('and not offered to it', 1, p.DetectCalls);
  finally
    r.Free;
    p.Free;
    rm.Free;
  end;
end;

{ H24. Mutation: the first handler answering True wins. }
procedure TTyTerminalStreamTests.TestTheEarliestClaimWins;
var
  r: TStreamRig;
  a, b: TFakeProtocol;
begin
  r := TStreamRig.Create;
  a := nil;
  b := nil;
  try
    a := r.Proto('A');
    a.Mode := fcmFixed;
    a.FixedAt := 10;
    b := r.Proto('B');
    b.Mode := fcmFixed;
    b.FixedAt := 5;
    r.Core.WriteSync('abcdefghijklmnopqrst');
    AssertEquals('B, the earlier place, claims', 1, b.Claims);
    AssertEquals('A gets nothing', 0, a.Claims);
    AssertEquals('A was asked', 1, a.DetectCalls);
    AssertEquals('parsed up to B''s place', 'abcde', r.Line);
    AssertTrue('B is fed from there', b.Fed = 'fghijklmnopqrst');
    r.Core.RemoveStreamHandler(b);
    r.Core.RemoveStreamHandler(a);
    FreeAndNil(a);
    FreeAndNil(b);

    { a tie: the one added later }
    r.Core.Reset;
    a := r.Proto('A');
    a.Mode := fcmFixed;
    a.FixedAt := 5;
    b := r.Proto('B');
    b.Mode := fcmFixed;
    b.FixedAt := 5;
    r.Core.WriteSync('abcdefghij');
    AssertEquals('the later one wins the tie', 1, b.Claims);
    AssertEquals('the earlier one does not', 0, a.Claims);
    AssertEquals('A.Claimed never logged', 0, CountOf(r.Log, 'A.Claimed'));
  finally
    r.Free;
    a.Free;
    b.Free;
  end;
end;

{ H25. Mutation: the range check on AClaimAt dropped. }
procedure TTyTerminalStreamTests.TestExceptionsFromTheHandler;
var
  r: TStreamRig;
  p: TFakeProtocol;
  cls: string;
begin
  r := TStreamRig.Create;
  p := nil;
  try
    p := r.Proto;
    { Detect raises: the flush raises, the chunk's callback still comes, no claim }
    p.RaiseInDetect := True;
    r.Core.Write('abc', @r.OnDone, 1);
    cls := '';
    try
      r.Core.WriteSync('');
    except
      on E: Exception do cls := E.ClassName;
    end;
    AssertEquals('raised', 'Exception', cls);
    AssertEquals('the callback came', '1', r.Done.CommaText);
    AssertFalse('no claim', r.Core.StreamClaimed);
    p.RaiseInDetect := False;
    r.Core.WriteSync('ok');
    AssertEquals('the next chunk as usual', 'ok', r.Line);

    { AClaimAt past the piece }
    p.Mode := fcmBeyond;
    r.Done.Clear;
    r.Core.Write('zz', @r.OnDone, 2);
    cls := '';
    try
      r.Core.WriteSync('');
    except
      on E: Exception do cls := E.ClassName;
    end;
    AssertEquals('out of range', 'EArgumentOutOfRangeException', cls);
    AssertEquals('the callback came', '2', r.Done.CommaText);
    AssertFalse('no claim', r.Core.StreamClaimed);

    { Feed raises: the claim stays and the next chunk is fed }
    p.Mode := fcmMarker;
    r.Core.WriteSync('<<GO>>');
    AssertTrue('claimed', r.Core.StreamClaimed);
    p.RaiseInFeed := True;
    cls := '';
    try
      r.Core.WriteSync('boom');
    except
      on E: Exception do cls := E.ClassName;
    end;
    AssertEquals('Feed raised', 'Exception', cls);
    AssertTrue('still claimed', r.Core.StreamClaimed);
    p.RaiseInFeed := False;
    r.Core.WriteSync('next');
    AssertTrue('fed', Copy(p.Fed, Length(p.Fed) - 3, 4) = 'next');
  finally
    r.Free;
    p.Free;
  end;
end;

type
  TAddThread = class(TThread)
  public
    Core: TTyTerminalCore;
    Proto: TFakeProtocol;
    Outcome: string;
    procedure Execute; override;
  end;

procedure TAddThread.Execute;
begin
  Outcome := '(none)';
  try
    Core.AddStreamHandler(Proto);
  except
    on E: Exception do Outcome := E.ClassName;
  end;
end;

{ H26. Mutation: CheckThread dropped from AddStreamHandler. }
procedure TTyTerminalStreamTests.TestOtherThreadsAreRefused;
var
  r: TStreamRig;
  p: TFakeProtocol;
  t: TAddThread;
begin
  r := TStreamRig.Create;
  p := TFakeProtocol.Create('', nil, r.Core);
  t := TAddThread.Create(True);
  try
    t.Core := r.Core;
    t.Proto := p;
    t.FreeOnTerminate := False;
    t.Start;
    t.WaitFor;
    AssertEquals('refused', 'EInvalidOperation', t.Outcome);
    AssertEquals('not added', 0, r.Core.StreamHandlerCount);
  finally
    t.Free;
    r.Free;
    p.Free;
  end;
end;

{ H27. Mutation: the destructor ending the claim. }
procedure TTyTerminalStreamTests.TestTheDestructorCallsNoHandler;
var
  r: TStreamRig;
  p: TFakeProtocol;
begin
  r := TStreamRig.Create;
  p := r.Proto;
  try
    r.Core.WriteSync('<<GO>>');
    AssertTrue('claimed', r.Core.StreamClaimed);
    FreeAndNil(r.Core);
    AssertEquals('no ClaimEnded', 0, CountOf(r.Log, 'ClaimEnded:reset') + CountOf(r.Log, 'ClaimEnded:removed'));
  finally
    r.Free;
    p.Free;
  end;
end;

{ H28. Mutation: EndClaim leaving the session Active. }
procedure TTyTerminalStreamTests.TestOneSessionForEveryClaim;
var
  r: TStreamRig;
  p: TFakeProtocol;
  first: TTyTerminalStreamSession;
begin
  r := TStreamRig.Create;
  p := r.Proto;
  try
    r.Core.WriteSync('<<GO>>');
    first := p.Session;
    AssertTrue('active while claimed', first.Active);
    AssertTrue('the handler', first.Handler = p);
    AssertTrue('the core', first.Core = r.Core);
    r.Core.RemoveStreamHandler(p);
    AssertFalse('not active afterwards', first.Active);
    AssertTrue('no handler afterwards', first.Handler = nil);
    AssertFalse('SendRaw refused', first.SendRaw('x'));
    AssertEquals('nothing sent', 0, r.SentCount);
    r.Core.AddStreamHandler(p);
    r.Core.WriteSync('<<GO>>');
    AssertEquals('two claims', 2, Length(p.SessionsSeen));
    AssertTrue('the same session object', p.SessionsSeen[0] = p.SessionsSeen[1]);
  finally
    r.Free;
    p.Free;
  end;
end;

initialization
  RegisterTest(TTyTerminalStreamTests);
end.
