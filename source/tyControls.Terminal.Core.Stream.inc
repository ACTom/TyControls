{ Part of tyControls.Terminal.Core (included, not a unit): the stream hooks (in-band
  protocols such as ZModem) and the parser hooks the core hands out. Written for this
  library, NOT ported: xterm.js has no stream hook (its zmodem add-on, long removed,
  filtered the data before write), and the parser hooks are a thin layer over the
  parser's own chains, after ParserApi.ts. Design: spec 19; the rules are in the unit
  header ("Stream hooks"). }

{ ==== TTyTerminalStreamHandler ============================================================= }

procedure TTyTerminalStreamHandler.Claimed(ASession: TTyTerminalStreamSession);
begin
end;

procedure TTyTerminalStreamHandler.ClaimEnded(AHow: TTyTerminalClaimEnd);
begin
end;

{ ==== TTyTerminalStreamSession ============================================================= }

constructor TTyTerminalStreamSession.Create(ACore: TTyTerminalCore);
begin
  inherited Create;
  FCore := ACore;
end;

{ straight to OnData, not through TriggerDataEvent: no scroll to the bottom, no
  OnUserInput, no "the user just typed" (spec 19.3). ReadOnly sends nothing (spec 3.3). }
function TTyTerminalStreamSession.SendRaw(const AData: RawByteString): Boolean;
begin
  FCore.CheckThread('StreamSession.SendRaw');
  if not FActive or FCore.FOptions.DisableStdin or not Assigned(FCore.FOnData) then
    Exit(False);
  FCore.FOnData(FCore, AData);
  Result := True;
end;

procedure TTyTerminalStreamSession.Release(const ALeftover: RawByteString);
begin
  FCore.CheckThread('StreamSession.Release');
  if not FActive or FEnding then
    Exit;
  FCore.ReleaseClaim(ALeftover);
end;

procedure TTyTerminalStreamSession.ShowText(const AText: string);
begin
  FCore.CheckThread('StreamSession.ShowText');
  if not FActive or (AText = '') then
    Exit;
  FCore.ShowLocal(AText);
end;

{ ==== the core's side ======================================================================= }

function TTyTerminalCore.GetStreamHandlerCount: Integer;
begin
  Result := FStreamCount;
end;

function TTyTerminalCore.GetStreamClaimed: Boolean;
begin
  Result := FClaim <> nil;
end;

function TTyTerminalCore.GetClaimingHandler: TTyTerminalStreamHandler;
begin
  Result := FClaim;
end;

procedure TTyTerminalCore.AddStreamHandler(AHandler: TTyTerminalStreamHandler);
var
  i: Integer;
begin
  CheckThread('AddStreamHandler');
  if AHandler = nil then
    raise EArgumentNilException.Create('TTyTerminalCore.AddStreamHandler: the handler is nil');
  for i := 0 to High(FStreamHandlers) do
    if FStreamHandlers[i] = AHandler then
      Exit;
  { appended: asked last in a piece, so it wins a tie (spec 19.4); added while the
    handlers are asked (from a Detect), it is asked from the next piece on }
  SetLength(FStreamHandlers, Length(FStreamHandlers) + 1);
  FStreamHandlers[High(FStreamHandlers)] := AHandler;
  Inc(FStreamCount);
end;

procedure TTyTerminalCore.RemoveStreamHandler(AHandler: TTyTerminalStreamHandler);
var
  i, at: Integer;
begin
  CheckThread('RemoveStreamHandler');
  if AHandler = nil then
    Exit;
  at := -1;
  for i := 0 to High(FStreamHandlers) do
    if FStreamHandlers[i] = AHandler then
    begin
      at := i;
      Break;
    end;
  if at < 0 then
    Exit;
  { off the list first: what ClaimEnded does next cannot reach it through a Detect }
  FStreamHandlers[at] := nil;
  Dec(FStreamCount);
  if FStreamLoop = 0 then
    CompactStreamHandlers;               { else the loop compacts when it is done }
  if FClaim = AHandler then
    EndClaim(tceRemoved, True);
end;

procedure TTyTerminalCore.CompactStreamHandlers;
var
  i, k: Integer;
begin
  k := 0;
  for i := 0 to High(FStreamHandlers) do
    if FStreamHandlers[i] <> nil then
    begin
      FStreamHandlers[k] := FStreamHandlers[i];
      Inc(k);
    end;
  SetLength(FStreamHandlers, k);
end;

{ The slow path of ProcessOneChunk (spec 19.4): a claim takes the piece whole; else
  every handler is asked }
procedure TTyTerminalCore.StreamPiece(const AData: RawByteString; AFrom, ACount: Integer);
begin
  Inc(FStreamPiecesOffered);
  if ACount <= 0 then
    Exit;
  if FClaim <> nil then
    DoFeed(AData, AFrom, ACount)
  else
    OfferPiece(AData, AFrom, ACount);
end;

{ Every handler's Detect (the core busy: what they cause waits for the chunk); the
  earliest AClaimAt wins, the one added later on a tie. The bytes before it are parsed
  with the program's decoder BEFORE Claimed, then the claim gets the rest. }
procedure TTyTerminalCore.OfferPiece(const AData: RawByteString; AFrom, ACount: Integer);
var
  i, n, at, best: Integer;
  winner, h: TTyTerminalStreamHandler;
begin
  winner := nil;
  best := 0;
  Inc(FBusy);
  Inc(FStreamLoop);
  try
    n := Length(FStreamHandlers);        { added in a Detect: asked from the next piece }
    for i := 0 to n - 1 do
    begin
      h := FStreamHandlers[i];           { nil: removed in an earlier Detect }
      if h = nil then
        Continue;
      Inc(FStreamDetectCalls);
      at := 0;
      if h.Detect(@AData[AFrom], ACount, at) then
      begin
        if (at < 0) or (at > ACount) then
          raise EArgumentOutOfRangeException.CreateFmt(
            'TTyTerminalStreamHandler.Detect: AClaimAt %d is outside 0..%d', [at, ACount]);
        { <=: the later one wins a tie }
        if (winner = nil) or (at <= best) then
        begin
          winner := h;
          best := at;
        end;
      end;
    end;
  finally
    Dec(FStreamLoop);
    Dec(FBusy);
    if (FStreamLoop = 0) and (Length(FStreamHandlers) <> FStreamCount) then
      CompactStreamHandlers;
  end;
  { a winner removed by a later Detect does not claim }
  if winner <> nil then
  begin
    h := winner;
    winner := nil;
    for i := 0 to High(FStreamHandlers) do
      if FStreamHandlers[i] = h then
        winner := h;
  end;
  if winner = nil then
  begin
    ParseRange(AData, AFrom, ACount);
    Exit;
  end;
  if best > 0 then
    ParseRange(AData, AFrom, best);
  BeginClaim(winner);
  if best < ACount then
    if FClaim = winner then
      DoFeed(AData, AFrom + best, ACount - best)
    else
    begin
      { the claim ended in Claimed (a Release, a RemoveStreamHandler) before it was fed
        anything: the rest of the piece was never the handler's, so it goes back in
        front, after what the Release handed back. A claim that took nothing and gave
        nothing back would be found again at the same byte: that byte goes to the
        parser (spec 19.4, the loop guard). }
      SpliceFront(Copy(AData, AFrom + best, ACount - best), FClaimReturned);
      if FClaimReturned = 0 then
        FFrontBypass := True;
    end;
end;

procedure TTyTerminalCore.DoFeed(const AData: RawByteString; AFrom, ACount: Integer);
var
  h: TTyTerminalStreamHandler;
begin
  h := FClaim;
  Inc(FClaimFed, ACount);
  Inc(FBusy);
  try
    h.Feed(@AData[AFrom], ACount);
  finally
    Dec(FBusy);
  end;
  { released, removed or reset in there: the core does not touch h again }
end;

procedure TTyTerminalCore.BeginClaim(AHandler: TTyTerminalStreamHandler);
begin
  FClaim := AHandler;
  FClaimFed := 0;
  FClaimReturned := 0;
  FStreamSession.FHandler := AHandler;
  FStreamSession.FActive := True;
  Inc(FBusy);
  try
    AHandler.Claimed(FStreamSession);
  finally
    Dec(FBusy);
  end;
end;

{ ANotify: the host ended it (Reset, RemoveStreamHandler) -- ClaimEnded, with the
  session still sending (the handler tells the program to stop) and Release a no-op }
procedure TTyTerminalCore.EndClaim(AHow: TTyTerminalClaimEnd; ANotify: Boolean);
var
  h: TTyTerminalStreamHandler;
begin
  h := FClaim;
  if h = nil then
    Exit;
  FClaim := nil;
  if ANotify then
  begin
    FStreamSession.FEnding := True;
    try
      h.ClaimEnded(AHow);
    finally
      FStreamSession.FEnding := False;
      FStreamSession.FActive := False;
      FStreamSession.FHandler := nil;
    end;
  end
  else
  begin
    FStreamSession.FActive := False;
    FStreamSession.FHandler := nil;
  end;
end;

{ Session.Release (spec 19.4): the claim ends; ALeftover goes in front of everything not
  parsed yet -- in Feed the outer loop takes it next; elsewhere (a Cancel from the
  host, the program quiet) it waits for the next slice, like a Write. Not counted in
  PendingBytes: those bytes were counted off when they were handed over. }
procedure TTyTerminalCore.ReleaseClaim(const ALeftover: RawByteString);
var
  zeroProgress: Boolean;
begin
  { the loop guard: a claim that handed back exactly what it was fed ate nothing }
  zeroProgress := (FClaimFed > 0) and (Length(ALeftover) = FClaimFed);
  EndClaim(tceRemoved, False);
  FClaimReturned := Length(ALeftover);
  if ALeftover = '' then
    Exit;
  SpliceFront(ALeftover, 0);
  FFrontBypass := zeroProgress;
  RequestProcess;
end;

procedure TTyTerminalCore.SpliceFront(const AData: RawByteString; AOffset: Integer);
begin
  if AData = '' then
    Exit;
  FFront := Copy(FFront, FFrontPos + 1, AOffset) + AData + Copy(FFront, FFrontPos + 1 + AOffset, MaxInt);
  FFrontPos := 0;
end;

{ one piece of the handed-back bytes, the way a queued piece goes (spec 19.4); the
  position moves before the piece is handled, like the queue's }
procedure TTyTerminalCore.ProcessFrontPiece(APieceBytes: Integer);
var
  data: RawByteString;
  start, n: Integer;
begin
  data := FFront;                        { our own reference: a Release in there rebuilds FFront }
  start := FFrontPos;
  n := Min(APieceBytes, Length(data) - start);
  Inc(FFrontPos, n);
  if FFrontPos >= Length(FFront) then
  begin
    FFront := '';
    FFrontPos := 0;
  end;
  if FFrontBypass and (n > 0) then
  begin
    { the loop guard (ReleaseClaim, OfferPiece): the first byte straight to the parser }
    FFrontBypass := False;
    ParseRange(data, start + 1, 1);
    Inc(start);
    Dec(n);
  end;
  if n > 0 then
    StreamPiece(data, start + 1, n);
  { a handed-back piece ends no chunk: what its events asked for runs once the bytes
    handed back are through and no chunk is half parsed }
  if FFront = '' then
    RunDeferred;
end;

{ Session.ShowText: parsed now with the session's own decoder; from an event of a
  running parse it waits for that parse to return (ParseDecoded flushes it) -- the
  parser is never entered twice }
procedure TTyTerminalCore.ShowLocal(const AText: string);
begin
  FShowPending := FShowPending + AText;
  if FParsing > 0 then
    Exit;                                { a parse runs further up: it flushes when done }
  FlushShowPending;
end;

{ from ShowLocal, and from ParseDecoded once the outermost parse is done (unless a
  flush further up the stack is already looping) }
procedure TTyTerminalCore.FlushShowPending;
var
  s: RawByteString;
begin
  FShowFlushing := True;
  try
    while FShowPending <> '' do
    begin
      s := FShowPending;
      FShowPending := '';
      ParseDecoded(FShowDecoder, s, 1, Length(s));
    end;
  finally
    FShowFlushing := False;
  end;
end;

procedure TTyTerminalCore.NoteUserHandle(AHandle: Integer);
begin
end;
