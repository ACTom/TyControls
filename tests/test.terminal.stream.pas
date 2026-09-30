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
    { Task 2 }
    procedure TestHandedBackBytesComeBeforeTheQueue;         { H7 }
    procedure TestHandedBackBytesAreOfferedAgain;            { H8 }
    procedure TestAClaimThatAteNothingDoesNotLoop;           { H9 }
    procedure TestAReleaseOutsideFeedWaitsForASlice;         { H10 }
    procedure TestShowTextHasADecoderOfItsOwn;               { H11 }
    procedure TestShowTextFromItsOwnEventWaits;              { H12 }
    procedure TestCallbacksComeWhileClaimed;                 { H13 }
    procedure TestSendRawGoesStraightOut;                    { H14 }
    procedure TestAReleaseInClaimedHandsTheRestBack;
    { Task 3 }
    procedure TestTheUsersInputGoesToOnClaimedInput;         { H15 }
    procedure TestTheCoresOwnReportsAreDropped;              { H16 }
    procedure TestNoMouseReportWhileClaimed;                 { H17 }
    procedure TestCallsFromFeedWaitForTheChunk;              { H18 }
    procedure TestWriteSyncWhileClaimed;                     { H19 }
    procedure TestDiscardPendingKeepsTheClaim;               { H20 }
    procedure TestResetEndsTheClaim;                         { H21 }
    procedure TestResizeKeepsTheClaim;                       { H22 }
    { the phase 7 review's fixes }
    procedure TestAWinnerRemovedBeforeItsMarkerDoesNotClaim;
    procedure TestADeferredResetWaitsForTheBytesHandedBack;
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
    Resizes: Integer;
    DataHook: TThreadMethod;             { called from OnData, after the bytes are noted }
    constructor Create(ACols: Integer = 40; ARows: Integer = 5);
    destructor Destroy; override;
    function Clock: Double;
    procedure OnResizeEv(Sender: TObject; ACols, ARows: Integer);
    procedure OnColor(Sender: TObject; AIndex: Integer; out ARgb: Cardinal);
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
  Core.OnResize := @OnResizeEv;
end;

procedure TStreamRig.OnResizeEv(Sender: TObject; ACols, ARows: Integer);
begin
  Inc(Resizes);
  Log.Add('resize');
end;

{ a dark theme: white on black }
procedure TStreamRig.OnColor(Sender: TObject; AIndex: Integer; out ARgb: Cardinal);
begin
  if AIndex = 257 then
    ARgb := $000000
  else
    ARgb := $FFFFFF;
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
  if Assigned(DataHook) then
    DataHook();
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

{ ---- Task 2: the session -------------------------------------------------------------- }

{ H7. Mutation: the handed-back bytes appended after the queue. }
procedure TTyTerminalStreamTests.TestHandedBackBytesComeBeforeTheQueue;
var
  r: TStreamRig;
  p: TFakeProtocol;
begin
  r := TStreamRig.Create;
  p := nil;
  try
    p := r.Proto;
    r.Core.Write('<<GO>>x<<END>>tail');
    r.Core.Write('more');
    r.Drain;
    AssertFalse('released', r.Core.StreamClaimed);
    AssertEquals('handed back first, then the queue', 'tailmore', r.Line);
    AssertTrue('fed up to the end marker and what followed in the piece', p.Fed = '<<GO>>x<<END>>tail');
    AssertEquals('pending', 0, r.Core.PendingBytes);
  finally
    r.Free;
    p.Free;
  end;
end;

{ H8 (sz a; sz b). Mutation: the handed-back bytes parsed without Detect. }
procedure TTyTerminalStreamTests.TestHandedBackBytesAreOfferedAgain;
var
  r: TStreamRig;
  p: TFakeProtocol;
begin
  r := TStreamRig.Create;
  p := nil;
  try
    p := r.Proto;
    r.Core.WriteSync('<<GO>>a<<END>>b<<GO>>c');
    AssertEquals('two claims', 2, CountOf(r.Log, 'Claimed'));
    AssertEquals('b between them', 'b', r.Line);
    AssertTrue('the second claim is fed its part', p.ClaimBuf = '<<GO>>c');
    AssertTrue('still claimed', r.Core.StreamClaimed);
  finally
    r.Free;
    p.Free;
  end;
end;

{ H9. Mutation: FFrontBypass dropped (Detect would claim the same byte for ever; the
  fake raises at 1000 calls). }
procedure TTyTerminalStreamTests.TestAClaimThatAteNothingDoesNotLoop;
var
  r: TStreamRig;
  p: TFakeProtocol;
  t0: QWord;
begin
  r := TStreamRig.Create;
  p := nil;
  try
    p := r.Proto;
    p.ReleaseAllOnFirstFeed := True;
    t0 := GetTickCount64;
    r.Core.WriteSync('<<GO>>x');
    AssertTrue('returns at once', GetTickCount64 - t0 < 1000);
    AssertTrue('asked a few times only', p.DetectCalls < 20);
    AssertEquals('everything shown', '<<GO>>x', r.Line);
    AssertFalse('no claim left', r.Core.StreamClaimed);
  finally
    r.Free;
    p.Free;
  end;
end;

{ H10. Mutation: a Release outside Feed parsed on the spot. }
procedure TTyTerminalStreamTests.TestAReleaseOutsideFeedWaitsForASlice;
var
  r: TStreamRig;
  p: TFakeProtocol;
begin
  r := TStreamRig.Create;
  p := nil;
  try
    p := r.Proto;
    r.Core.WriteSync('ab<<GO>>');
    AssertTrue('claimed', r.Core.StreamClaimed);
    r.Requests := 0;
    p.Session.Release('xyz');
    AssertFalse('released', r.Core.StreamClaimed);
    AssertEquals('not parsed yet', 'ab', r.Line);
    AssertEquals('asked for a slice once', 1, r.Requests);
    AssertEquals('not pending bytes (counted off already)', 0, r.Core.PendingBytes);
    AssertFalse('one slice does it', r.Core.ProcessPending);
    AssertEquals('parsed in the slice', 'abxyz', r.Line);
  finally
    r.Free;
    p.Free;
  end;
end;

type
  TShowOnce = class
  public
    Text: string;
    Shown: Boolean;
    procedure Hook(AProto: TFakeProtocol);
  end;

procedure TShowOnce.Hook(AProto: TFakeProtocol);
begin
  if Shown then
    Exit;
  Shown := True;
  AProto.Session.ShowText(Text);
end;

{ H11. Mutation: ShowText parsed with the program's decoder. The program's half
  character (E4 B8 of U+4E2D) waits in its decoder across the claim. }
procedure TTyTerminalStreamTests.TestShowTextHasADecoderOfItsOwn;
var
  r: TStreamRig;
  p: TFakeProtocol;
  show: TShowOnce;
begin
  r := TStreamRig.Create;
  p := nil;
  show := TShowOnce.Create;
  try
    p := r.Proto;
    show.Text := #$C3#$A9;               { U+00E9 }
    p.OnFeed := @show.Hook;
    r.Core.WriteSync(#$E4#$B8'<<GO>>');
    AssertTrue('shown in Feed', show.Shown);
    AssertEquals('on screen at once', #$C3#$A9, r.Line);
    r.Core.WriteSync('<<END>>'#$AD);
    AssertEquals('the program''s character is whole', #$C3#$A9#$E4#$B8#$AD, r.Line);
  finally
    r.Free;
    p.Free;
    show.Free;
  end;
end;

type
  TBellShow = class
  public
    Session: TTyTerminalStreamSession;
    Bells: Integer;
    procedure OnBell(Sender: TObject);
  end;

procedure TBellShow.OnBell(Sender: TObject);
begin
  Inc(Bells);
  if Bells = 1 then
    Session.ShowText('2');
end;

{ H12. Mutation: ShowText parsing at once even while a parse runs (the parser entered
  twice: the bell's '2' would land between '1' and '3', or worse). }
procedure TTyTerminalStreamTests.TestShowTextFromItsOwnEventWaits;
var
  r: TStreamRig;
  p: TFakeProtocol;
  show: TShowOnce;
  bell: TBellShow;
begin
  r := TStreamRig.Create;
  p := nil;
  show := TShowOnce.Create;
  bell := TBellShow.Create;
  try
    p := r.Proto;
    show.Text := '1'#7'3';
    p.OnFeed := @show.Hook;
    bell.Session := r.Core.StreamSession;
    r.Core.OnBell := @bell.OnBell;
    r.Core.WriteSync('<<GO>>');
    AssertEquals('one bell', 1, bell.Bells);
    AssertEquals('the event''s text after its parse', '132', r.Line);
    AssertTrue('the parser is back in ground', r.Core.Parser.CurrentState = tpsGround);
  finally
    r.Free;
    p.Free;
    show.Free;
    bell.Free;
  end;
end;

{ H13. Mutation: a claimed chunk skipping its callback. }
procedure TTyTerminalStreamTests.TestCallbacksComeWhileClaimed;
var
  r: TStreamRig;
  p: TFakeProtocol;
  i, before: Integer;
begin
  r := TStreamRig.Create;
  p := nil;
  try
    p := r.Proto;
    r.Core.WriteSync('<<GO>>');
    before := Length(p.Fed);
    for i := 1 to 5 do
      r.Core.Write(StringOfChar(AnsiChar(Ord('a') + i), 10240), @r.OnDone, i);
    r.Drain;
    AssertEquals('every callback, in order', '1,2,3,4,5', r.Done.CommaText);
    AssertEquals('nothing pending', 0, r.Core.PendingBytes);
    AssertEquals('all fed', 5 * 10240, Length(p.Fed) - before);
    AssertTrue('still claimed', r.Core.StreamClaimed);
  finally
    r.Free;
    p.Free;
  end;
end;

{ H14. Mutations: SendRaw through TriggerDataEvent(.., True); ReadOnly not checked. }
procedure TTyTerminalStreamTests.TestSendRawGoesStraightOut;
var
  r: TStreamRig;
  p: TFakeProtocol;
  i, ydisp: Integer;
begin
  r := TStreamRig.Create;
  p := nil;
  try
    for i := 1 to 20 do
      r.Core.WriteSync('line ' + IntToStr(i) + #13#10);
    p := r.Proto;
    r.Core.WriteSync('<<GO>>');
    r.Core.ScrollLines(-3);
    ydisp := r.Core.Buffer.YDisp;
    AssertTrue('scrolled up', ydisp < r.Core.Buffer.YBase);
    AssertTrue('sent', p.Session.SendRaw(#0#$FF#$18));
    AssertTrue('byte for byte', r.Sent = #0#$FF#$18);
    AssertEquals('the viewport stays', ydisp, r.Core.Buffer.YDisp);
    AssertEquals('no OnUserInput', 0, r.UserInputs);
    AssertEquals('not claimed input either', 0, r.ClaimedCount);
    { not "the user just typed": the next write is queued, not parsed at once }
    r.Core.Write('a');
    AssertEquals('queued', 1, r.Core.PendingBytes);
    AssertTrue('not fed yet', Copy(p.Fed, Length(p.Fed), 1) <> 'a');
    r.Drain;
    r.Core.ReadOnly := True;
    AssertFalse('ReadOnly refuses', p.Session.SendRaw('x'));
    AssertEquals('nothing more sent', 1, r.SentCount);
  finally
    r.Free;
    p.Free;
  end;
end;

{ A Release in Claimed, before anything was fed: the rest of the piece was never the
  handler's; it goes back in front and its first byte to the parser (no loop). }
procedure TTyTerminalStreamTests.TestAReleaseInClaimedHandsTheRestBack;
var
  r: TStreamRig;
  p: TFakeProtocol;
begin
  r := TStreamRig.Create;
  p := nil;
  try
    p := r.Proto;
    p.ReleaseInClaimed := True;
    r.Core.WriteSync('abc<<GO>>xyz');
    AssertEquals('claimed once', 1, p.Claims);
    AssertTrue('fed nothing', p.Fed = '');
    AssertEquals('nothing lost', 'abc<<GO>>xyz', r.Line);
    AssertFalse('not claimed', r.Core.StreamClaimed);
  finally
    r.Free;
    p.Free;
  end;
end;

{ ---- Task 3: the rest of the core while claimed ------------------------------------------- }

procedure ScrollBackSome(r: TStreamRig);
var
  i: Integer;
begin
  for i := 1 to 20 do
    r.Core.WriteSync('line ' + IntToStr(i) + #13#10);
end;

{ H15. Mutations: no redirection; the redirection after the scroll to the bottom. }
procedure TTyTerminalStreamTests.TestTheUsersInputGoesToOnClaimedInput;
var
  r: TStreamRig;
  p: TFakeProtocol;
  ydisp: Integer;
begin
  r := TStreamRig.Create;
  p := nil;
  try
    ScrollBackSome(r);
    AssertTrue('scrolls to the bottom on input', r.Core.ScrollOnUserInput);
    { not claimed: the same input goes out, announced, and scrolls down }
    r.Core.ScrollLines(-3);
    r.Core.Input('x', True);
    AssertTrue('sent', r.Sent = 'x');
    AssertEquals('announced', 1, r.UserInputs);
    AssertEquals('scrolled to the bottom', r.Core.Buffer.YBase, r.Core.Buffer.YDisp);
    p := r.Proto;
    r.Core.WriteSync('<<GO>>');
    r.Core.ScrollLines(-3);
    ydisp := r.Core.Buffer.YDisp;
    r.Core.Input('x', True);
    AssertTrue('to OnClaimedInput', r.ClaimedInput = 'x');
    AssertEquals('not to OnData', 1, r.SentCount);
    AssertEquals('not announced', 1, r.UserInputs);
    AssertEquals('the viewport stays', ydisp, r.Core.Buffer.YDisp);
    { released: back to OnData }
    p.Session.Release('');
    r.Core.Input('y', True);
    AssertTrue('sent again', r.Sent = 'xy');
    AssertEquals('claimed input unchanged', 1, r.ClaimedCount);
    { ReadOnly: nothing, not even OnClaimedInput }
    r.Core.WriteSync('<<GO>>');
    r.Core.ReadOnly := True;
    r.Core.Input('z', True);
    AssertEquals('ReadOnly: no claimed input', 1, r.ClaimedCount);
    AssertEquals('ReadOnly: nothing sent', 2, r.SentCount);
  finally
    r.Free;
    p.Free;
  end;
end;

{ H16. Mutation: the claimed branch passing on (or redirecting) AWasUserInput = False. }
procedure TTyTerminalStreamTests.TestTheCoresOwnReportsAreDropped;
var
  r: TStreamRig;
  p: TFakeProtocol;
  n: Integer;
begin
  r := TStreamRig.Create;
  p := nil;
  try
    r.Core.OnQueryBaseColor := @r.OnColor;
    r.Core.WriteSync(#27'[?1004h'#27'[?2031h');
    AssertTrue('1004 on', r.Core.Modes.SendFocus);
    AssertTrue('2031 on', r.Core.Modes.ColorSchemeUpdates);
    { not claimed: each of them sends }
    n := r.SentCount;
    r.Core.ReportFocus(False);
    AssertEquals('a focus report', n + 1, r.SentCount);
    r.Core.NotifyColorSchemeChanged;
    AssertEquals('a colour-scheme report', n + 2, r.SentCount);
    r.Core.Input('r', False);
    AssertEquals('the core''s own input', n + 3, r.SentCount);
    p := r.Proto;
    r.Core.WriteSync('<<GO>>');
    n := r.SentCount;
    r.Core.ReportFocus(True);
    r.Core.ReportFocus(False);
    r.Core.NotifyColorSchemeChanged;
    r.Core.Input('r', False);
    AssertEquals('none sent while claimed', n, r.SentCount);
    AssertEquals('none redirected either', 0, r.ClaimedCount);
  finally
    r.Free;
    p.Free;
  end;
end;

function MouseAt(ACol, ARow: Integer; AButton: TTyTerminalMouseButton; AAction: TTyTerminalMouseAction): TTyTerminalMouseEvent;
begin
  Result := Default(TTyTerminalMouseEvent);
  Result.Col := ACol;
  Result.Row := ARow;
  Result.X := ACol * 8;
  Result.Y := ARow * 16;
  Result.Button := AButton;
  Result.Action := AAction;
end;

{ H17. Mutation: TriggerMouseEvent not looking at the claim. Default encoding: the
  report is binary (TriggerBinaryEvent). }
procedure TTyTerminalStreamTests.TestNoMouseReportWhileClaimed;
var
  r: TStreamRig;
  p: TFakeProtocol;
  n: Integer;
begin
  r := TStreamRig.Create;
  p := nil;
  try
    r.Core.WriteSync(#27'[?1000h');
    n := r.SentCount;
    AssertTrue('passes', r.Core.TriggerMouseEvent(MouseAt(1, 1, tmbLeft, tmaDown)));
    AssertEquals('reported', n + 1, r.SentCount);
    AssertTrue('the default encoding', Copy(r.Sent, Length(r.Sent) - 5, 3) = #27'[M');
    p := r.Proto;
    r.Core.WriteSync('<<GO>>');
    n := r.SentCount;
    AssertFalse('refused while claimed', r.Core.TriggerMouseEvent(MouseAt(2, 1, tmbLeft, tmaUp)));
    AssertFalse('refused while claimed', r.Core.TriggerMouseEvent(MouseAt(3, 2, tmbLeft, tmaDown)));
    AssertEquals('nothing sent', n, r.SentCount);
    AssertEquals('nothing redirected', 0, r.ClaimedCount);
    { SGR: the report would be user input -- still nothing }
    r.Core.Reset;
    r.Core.WriteSync(#27'[?1000h'#27'[?1006h<<GO>>');
    n := r.SentCount;
    AssertFalse('SGR refused too', r.Core.TriggerMouseEvent(MouseAt(1, 1, tmbLeft, tmaDown)));
    AssertEquals('nothing sent', n, r.SentCount);
    AssertEquals('nothing redirected', 0, r.ClaimedCount);
  finally
    r.Free;
    p.Free;
  end;
end;

type
  TFeedCaller = class
  public
    Rig: TStreamRig;
    Pinged: Boolean;
    InData: Boolean;
    procedure Hook(AProto: TFakeProtocol);
    procedure Data;
  end;

procedure TFeedCaller.Hook(AProto: TFakeProtocol);
begin
  if Pinged then
    Exit;
  Pinged := True;
  InData := True;
  try
    AProto.Session.SendRaw('ping');
  finally
    InData := False;
  end;
end;

procedure TFeedCaller.Data;
begin
  if not InData then
    Exit;
  Rig.Core.Resize(30, 5);
  Rig.Core.WriteSync('w');
  Rig.Core.Reset;
  Rig.Log.Add('calls made');
end;

{ H18. Mutation: OfferPiece / DoFeed without Inc(FBusy) (the Resize would flush and
  the WriteSync feed inside Feed). }
procedure TTyTerminalStreamTests.TestCallsFromFeedWaitForTheChunk;
var
  r: TStreamRig;
  p: TFakeProtocol;
  c: TFeedCaller;
  iFeed, iCalls, iDone, iResize, iW, iEnd: Integer;
begin
  r := TStreamRig.Create;
  p := nil;
  c := TFeedCaller.Create;
  try
    c.Rig := r;
    r.DataHook := @c.Data;
    p := r.Proto;
    p.OnFeed := @c.Hook;
    r.Core.Write('<<GO>>', @r.OnDone, 1);
    r.Drain;
    iFeed := r.Log.IndexOf('Feed:<<GO>>');
    iCalls := r.Log.IndexOf('calls made');
    iDone := r.Log.IndexOf('done1');
    iResize := r.Log.IndexOf('resize');
    iW := r.Log.IndexOf('Feed:w');
    iEnd := r.Log.IndexOf('ClaimEnded:reset');
    AssertTrue('the calls were made in Feed: ' + r.Log.CommaText, (iFeed >= 0) and (iCalls > iFeed));
    AssertTrue('the callback after Feed: ' + r.Log.CommaText, iDone > iCalls);
    AssertTrue('the Resize after the callback: ' + r.Log.CommaText, iResize > iDone);
    AssertTrue('then w reaches the claim: ' + r.Log.CommaText, iW > iResize);
    AssertTrue('then the Reset ends it: ' + r.Log.CommaText, iEnd > iW);
    AssertEquals('Feed never nested', 1, p.MaxFeedDepth);
    AssertEquals('resized', 30, r.Core.Cols);
    AssertFalse('the claim ended', r.Core.StreamClaimed);
  finally
    r.Free;
    p.Free;
    c.Free;
  end;
end;

{ H19. Mutation: the hook only on the slicing path. }
procedure TTyTerminalStreamTests.TestWriteSyncWhileClaimed;
var
  r: TStreamRig;
  p: TFakeProtocol;
begin
  r := TStreamRig.Create;
  p := nil;
  try
    p := r.Proto;
    r.Core.WriteSync('ab<<GO>>');
    r.Core.WriteSync('abc');
    AssertTrue('fed', Copy(p.Fed, Length(p.Fed) - 2, 3) = 'abc');
    AssertEquals('the screen stays', 'ab', r.Line);
  finally
    r.Free;
    p.Free;
  end;
end;

{ H20. Mutation: ClearQueue leaving the handed-back bytes. }
procedure TTyTerminalStreamTests.TestDiscardPendingKeepsTheClaim;
var
  r: TStreamRig;
  p: TFakeProtocol;
  fed: RawByteString;
begin
  r := TStreamRig.Create;
  p := nil;
  try
    p := r.Proto;
    r.Core.WriteSync('<<GO>>');
    fed := p.Fed;
    r.Core.Write('one', @r.OnDone, 1);
    r.Core.Write('two', @r.OnDone, 2);
    r.Core.Write('three', @r.OnDone, 3);
    r.Core.DiscardPending;
    r.Drain;
    AssertEquals('no callback', 0, r.Done.Count);
    AssertTrue('nothing fed', p.Fed = fed);
    AssertTrue('still claimed', r.Core.StreamClaimed);
    { handed back outside Feed, not parsed yet: dropped with the queue }
    p.Session.Release('xyz');
    r.Core.DiscardPending;
    r.Drain;
    AssertEquals('dropped', '', r.Line);
    r.Core.WriteSync('q');
    AssertEquals('parsed as usual', 'q', r.Line);
  finally
    r.Free;
    p.Free;
  end;
end;

{ H21. Mutation: Reset leaving the claim. }
procedure TTyTerminalStreamTests.TestResetEndsTheClaim;
var
  r: TStreamRig;
  p: TFakeProtocol;
  n: Integer;
begin
  r := TStreamRig.Create;
  p := nil;
  try
    p := r.Proto;
    r.Core.Reset;
    AssertEquals('not claimed: Reset calls no handler', 0, CountOf(r.Log, 'ClaimEnded:reset'));
    r.Core.WriteSync('<<GO>>');
    n := r.Log.Count;
    r.Core.Reset;
    AssertEquals('ClaimEnded once', 1, CountOf(r.Log, 'ClaimEnded:reset'));
    AssertEquals('and nothing else', n + 1, r.Log.Count);
    AssertFalse('no claim', r.Core.StreamClaimed);
    r.Core.WriteSync('<<GO>>');
    AssertEquals('detected again', 2, p.Claims);
  finally
    r.Free;
    p.Free;
  end;
end;

{ H22. Mutation: Resize ending the claim. }
procedure TTyTerminalStreamTests.TestResizeKeepsTheClaim;
var
  r: TStreamRig;
  p: TFakeProtocol;
begin
  r := TStreamRig.Create;
  p := nil;
  try
    p := r.Proto;
    r.Core.WriteSync('<<GO>>');
    r.Core.Resize(30, 5);
    AssertTrue('still claimed', r.Core.StreamClaimed);
    AssertEquals('resized', 30, r.Core.Cols);
    AssertEquals('OnResize', 1, r.Resizes);
    AssertEquals('no ClaimEnded', 0, CountOf(r.Log, 'ClaimEnded:removed') + CountOf(r.Log, 'ClaimEnded:reset'));
  finally
    r.Free;
    p.Free;
  end;
end;

{ ---- the phase 7 review's fixes ------------------------------------------------------------ }

type
  { an OSC 1337 handler (the public parser hook) that takes a stream handler off }
  TOscRemover = class
  public
    Core: TTyTerminalCore;
    Victim: TTyTerminalStreamHandler;
    Calls: Integer;
    function Osc(const AData: string): Boolean;
  end;

function TOscRemover.Osc(const AData: string): Boolean;
begin
  Inc(Calls);
  Core.RemoveStreamHandler(Victim);
  Result := True;
end;

{ The winner of a piece is taken off by an event of the bytes before its marker (parsed
  first, spec 19.4): it does not claim -- the rest of the piece goes to the parser, as
  when nobody claims (the other handlers saw this piece already; it is not offered
  twice) -- and it can be freed at once. Mutation: no second look at the list after the
  prefix is parsed (the removed handler claims; the next write feeds a freed object). }
procedure TTyTerminalStreamTests.TestAWinnerRemovedBeforeItsMarkerDoesNotClaim;
var
  r: TStreamRig;
  p: TFakeProtocol;
  rm: TOscRemover;
begin
  r := TStreamRig.Create;
  p := nil;
  rm := TOscRemover.Create;
  try
    p := r.Proto;
    rm.Core := r.Core;
    rm.Victim := p;
    r.Core.RegisterOscHandler(1337, @rm.Osc);
    r.Core.WriteSync('ab'#27']1337;x'#7'cd<<GO>>rest');
    AssertEquals('the OSC ran', 1, rm.Calls);
    AssertEquals('taken off', 0, r.Core.StreamHandlerCount);
    AssertFalse('not claimed', r.Core.StreamClaimed);
    AssertEquals('no Claimed', 0, p.Claims);
    AssertTrue('nothing fed', p.Fed = '');
    AssertEquals('the rest of the piece on the screen', 'abcd<<GO>>rest', r.Line);
    FreeAndNil(p);
    r.Core.WriteSync(' more');
    AssertEquals('and what follows', 'abcd<<GO>>rest more', r.Line);
  finally
    r.Free;
    p.Free;
    rm.Free;
  end;
end;

type
  TResetOnce = class
  public
    Done: Boolean;
    procedure Hook(AProto: TFakeProtocol);
  end;

procedure TResetOnce.Hook(AProto: TFakeProtocol);
begin
  if Done then
    Exit;
  Done := True;
  AProto.Core.Reset;                     { busy: deferred }
end;

{ A Reset asked for in a chunk's Feed runs after the bytes that Feed handed back, as it
  does after a chunk (spec 19.5) -- the handed-back bytes were the chunk's own output.
  Here they claim again (a second '<<GO>>'), so the Reset must end that claim. Mutation:
  the chunk's last piece running what was deferred while handed-back bytes wait (the
  Reset comes first; the second claim outlives it). }
procedure TTyTerminalStreamTests.TestADeferredResetWaitsForTheBytesHandedBack;
var
  r: TStreamRig;
  p: TFakeProtocol;
  once: TResetOnce;
begin
  r := TStreamRig.Create;
  p := nil;
  once := TResetOnce.Create;
  try
    p := r.Proto;
    p.OnFeed := @once.Hook;
    r.Core.WriteSync('a<<GO>>b<<END>>x<<GO>>y');
    AssertTrue('the Reset was asked for in Feed', once.Done);
    AssertEquals('claimed twice', 2, p.Claims);
    AssertEquals('the Reset ended the second claim: ' + r.Log.CommaText, 1, CountOf(r.Log, 'ClaimEnded:reset'));
    AssertFalse('nothing claimed after the Reset', r.Core.StreamClaimed);
  finally
    r.Free;
    p.Free;
    once.Free;
  end;
  { the same in slices whose budget runs out after every piece: the next slice starts
    with what was deferred -- it too waits for the bytes handed back }
  r := TStreamRig.Create;
  p := nil;
  once := TResetOnce.Create;
  try
    p := r.Proto;
    p.OnFeed := @once.Hook;
    r.Step := 100;
    r.Core.Write('a<<GO>>b<<END>>x<<GO>>y');
    r.Drain;
    AssertTrue('slices: the Reset was asked for in Feed', once.Done);
    AssertEquals('slices: claimed twice', 2, p.Claims);
    AssertEquals('slices: the Reset ended the second claim: ' + r.Log.CommaText, 1,
      CountOf(r.Log, 'ClaimEnded:reset'));
    AssertFalse('slices: nothing claimed after the Reset', r.Core.StreamClaimed);
  finally
    r.Free;
    p.Free;
    once.Free;
  end;
end;

initialization
  RegisterTest(TTyTerminalStreamTests);
end.
