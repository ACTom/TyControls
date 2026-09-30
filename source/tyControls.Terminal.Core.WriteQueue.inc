{ Part of tyControls.Terminal.Core (included, not a unit): the write queue
  (WriteBuffer.ts) and the handling of calls made from events while the core is busy.
  Moved out of the unit only to keep it readable; the port, its sources and its
  licence are in the unit header. }

{ ==== the write queue: WriteBuffer.ts without the promise / lastTime branches =========== }

{ spec 3.5: every entry point of the queue refuses other threads before touching it }
procedure TTyTerminalCore.CheckThread(const AMethod: string);
begin
  if GetCurrentThreadId <> MainThreadID then
    raise EInvalidOperation.Create('TTyTerminalCore.' + AMethod + ' must be called from the main thread');
end;

function TTyTerminalCore.NowMs: Double;
begin
  if Assigned(FClock) then
    Result := FClock()
  else
    Result := TyTermDefaultClock;
end;

{ at most one request outstanding (upstream's cancelAndSet keeps one timer) }
procedure TTyTerminalCore.RequestProcess;
begin
  if FProcessRequested then
    Exit;
  FProcessRequested := True;
  if Assigned(FOnProcessRequest) then
    FOnProcessRequest(Self);
end;

procedure TTyTerminalCore.Enqueue(const AData: RawByteString; AOnDone: TTyTerminalWriteDone; ATag: PtrInt);
begin
  if FQueueCount = Length(FQueue) then
    SetLength(FQueue, FQueueCount * 2 + 8);
  FQueue[FQueueCount].Data := AData;
  FQueue[FQueueCount].OnDone := AOnDone;
  FQueue[FQueueCount].Tag := ATag;
  Inc(FQueueCount);
  Inc(FPendingData, Length(AData));
end;

procedure TTyTerminalCore.ClearQueue;
var
  i: Integer;
begin
  for i := 0 to FQueueCount - 1 do
    FQueue[i].Data := '';
  FQueueCount := 0;
  FBufferOffset := 0;
  FPendingData := 0;
  { a half-parsed head goes with the rest, without its callback }
  FChunkPos := 0;
  { and what a stream claim handed back (spec 19.5: DiscardPending drops it too) }
  FFront := '';
  FFrontPos := 0;
  FFrontBypass := False;
  Inc(FQueueGen);
end;

{ write, :152-182. Ours on top: an empty write without a callback is nothing, and
  the number of chunks waiting is bounded like their bytes (spec 3.1). }
procedure TTyTerminalCore.Write(const AData: RawByteString; AOnDone: TTyTerminalWriteDone; ATag: PtrInt);
var
  more: Boolean;
begin
  CheckThread('Write');
  if (AData = '') and not Assigned(AOnDone) then
    Exit;
  if FPendingData > TyTermDiscardWatermark then
    raise ETyTerminalWriteOverflow.Create('write data discarded, use flow control to avoid losing data');
  if FQueueCount - FBufferOffset >= TyTermMaxPendingChunks then
    raise ETyTerminalWriteOverflow.Create('write discarded: too many chunks waiting, use flow control');
  if FQueueCount = 0 then
  begin
    FBufferOffset := 0;
    { the first write after user input is parsed at once: echo latency -- not while
      the core is busy (an event's own Write), which would parse inside a parse }
    if FDidUserInput and (FBusy = 0) and not FIsSyncWriting then
    begin
      FDidUserInput := False;
      Enqueue(AData, AOnDone, ATag);
      InnerWrite(TyTermWriteTimeoutMs, more);
      if more then
        RequestProcess;                  { _innerWrite schedules the rest itself }
      Exit;
    end;
    RequestProcess;
  end;
  Enqueue(AData, AOnDone, ATag);
end;

procedure TTyTerminalCore.Write(const ABuf; ACount: Integer; AOnDone: TTyTerminalWriteDone; ATag: PtrInt);
var
  s: RawByteString;
begin
  CheckThread('Write');
  s := '';
  SetLength(s, ACount);
  if ACount > 0 then
    Move(ABuf, s[1], ACount);
  Write(s, AOnDone, ATag);
end;

{ The next piece of the head chunk: at most APieceBytes from where the last piece
  stopped (unit header: TyTermSlicePieceBytes in a slice, TyTermMaxParseBuffer in a
  flush). The position and the byte count move BEFORE the
  piece is parsed, so neither an exception nor a nested flush can parse it twice. The
  last piece takes the chunk off the queue first (the queue lets go of its data), then
  its callback -- also when a handler raised, a host counting callbacks for flow
  control must not lose one -- then what an event asked for while the chunk was
  parsed. A handler raising in an earlier piece: the rest of the chunk counts as
  parsed, the same way. }
procedure TTyTerminalCore.ProcessOneChunk(APieceBytes: Integer);
var
  item: TTyTermQueueItem;
  data: RawByteString;
  head, start, n: Integer;
  gen: Cardinal;
  last, ok: Boolean;

  procedure TakeHead;
  begin
    item := FQueue[head];
    FQueue[head].Data := '';
    FQueue[head].OnDone := nil;
    Inc(FBufferOffset);
    FChunkPos := 0;
  end;

begin
  { spec 19.4: the bytes a stream claim handed back go before the queue }
  if FFront <> '' then
  begin
    ProcessFrontPiece(APieceBytes);
    Exit;
  end;
  head := FBufferOffset;
  data := FQueue[head].Data;             { our own reference: a nested clear lets go of the slot's }
  item := Default(TTyTermQueueItem);
  start := FChunkPos;
  n := Min(APieceBytes, Length(data) - start);
  Inc(FChunkPos, n);
  Dec(FPendingData, n);
  last := FChunkPos >= Length(data);
  if last then
    TakeHead;
  gen := FQueueGen;
  ok := False;
  try
    { the stream hooks' fast path (spec 19.4): no handler, no claim, nothing handed back }
    if (FStreamCount = 0) and (FClaim = nil) and (FFront = '') then
      ParseRange(data, start + 1, n)
    else
      StreamPiece(data, start + 1, n);
    ok := True;
  finally
    { a handler raised in an earlier piece: the rest counts as parsed -- unless the
      queue was cleared under the piece (DiscardPending from an event) }
    if (not last) and (not ok) and (gen = FQueueGen) and (FBufferOffset = head) and (head < FQueueCount) then
    begin
      Dec(FPendingData, Length(data) - FChunkPos);
      TakeHead;
      last := True;
    end;
    if last and Assigned(item.OnDone) then
      item.OnDone(Self, item.Tag);
  end;
  if last then
    RunDeferred;
end;

{ _innerWrite, :219-315: pieces of chunks until the budget is spent -- checked between
  pieces, so one big chunk is cut too (unit header; upstream checks between chunks
  only). An exception from a handler or a callback leaves the rest queued and asks
  for another slice (upstream's timer would simply be gone). }
procedure TTyTerminalCore.InnerWrite(ABudgetMs: Integer; out AMore: Boolean);
var
  start: Double;
  i, n: Integer;
  ok: Boolean;
begin
  AMore := False;
  ok := False;
  start := NowMs;
  try
    while (FFront <> '') or (FQueueCount > FBufferOffset) do
    begin
      ProcessOneChunk(TyTermSlicePieceBytes);
      if NowMs - start >= ABudgetMs then
        Break;
    end;
    ok := True;
  finally
    if (FFront <> '') or (FQueueCount > FBufferOffset) then
    begin
      { drop the processed chunks once there are many of them }
      if FBufferOffset > TyTermWriteBufferLengthThreshold then
      begin
        n := FQueueCount - FBufferOffset;
        for i := 0 to n - 1 do
          FQueue[i] := FQueue[FBufferOffset + i];
        for i := n to FQueueCount - 1 do
        begin
          FQueue[i].Data := '';
          FQueue[i].OnDone := nil;
        end;
        FQueueCount := n;
        FBufferOffset := 0;
      end;
      AMore := True;
      if not ok then
        RequestProcess;
    end
    else
      ClearQueue;
    if not ok and (FDeferredCount > 0) then
      RequestProcess;
    AfterDrive;
  end;
end;

function TTyTerminalCore.ProcessPending(ABudgetMs: Integer): Boolean;
begin
  CheckThread('ProcessPending');
  FProcessRequested := False;
  if (FBusy > 0) or FIsSyncWriting then
  begin
    { from inside a parse or a flush (an event, a modal loop in a handler): the
      running loop is not entered twice; the core asks again when it is done }
    FRerequest := True;
    Exit(False);
  end;
  RunDeferred;
  InnerWrite(ABudgetMs, Result);
  { the caller schedules the next slice: no OnProcessRequest from here }
end;

procedure TTyTerminalCore.DiscardPending;
begin
  CheckThread('DiscardPending');
  { a slice or a flush running further up the stack sees an empty queue and stops }
  ClearQueue;
end;

{ writeSync, :106-150 (maxSubsequentCalls not ported). Upstream shifts from index 0,
  which parses again the chunks a slice already did when a slice stopped midway; here
  it starts at the first unprocessed chunk (a deliberate difference). An empty
  AData only flushes. From an event while the core is busy: noted, run after the
  chunk (unit header). }
procedure TTyTerminalCore.WriteSync(const AData: RawByteString);
begin
  CheckThread('WriteSync');
  if FBusy > 0 then
  begin
    Defer(tdkWriteSync, 0, 0, AData);
    Exit;
  end;
  if AData <> '' then
    Enqueue(AData, nil, 0);
  if FIsSyncWriting then
    Exit;                                { a callback's own WriteSync: the loop below takes it }
  FlushSync;
end;

{ flushSync, :71-101, from the first unprocessed chunk (see WriteSync); Resize runs
  it so pending output is parsed at the old size. After an exception what is left
  stays queued for the next slice (upstream would stay "sync writing" for good). }
procedure TTyTerminalCore.FlushSync;
var
  ok: Boolean;
begin
  if (FBusy > 0) or FIsSyncWriting then
    Exit;
  FIsSyncWriting := True;
  ok := False;
  try
    while (FFront <> '') or (FBufferOffset < FQueueCount) do
      ProcessOneChunk(TyTermMaxParseBuffer);
    ok := True;
  finally
    FIsSyncWriting := False;
    if (FFront = '') and (FBufferOffset >= FQueueCount) then
      ClearQueue
    else
      RequestProcess;
    if not ok and (FDeferredCount > 0) then
      RequestProcess;
    AfterDrive;
  end;
end;

{ ---- re-entry: calls from events while the core is busy (unit header) ---- }

procedure TTyTerminalCore.Defer(AKind: TTyTermDeferredKind; ACols, ARows: Integer; const AData: RawByteString);
var
  i, k: Integer;
begin
  { only the last Resize counts, at the place of its call }
  if AKind = tdkResize then
  begin
    k := 0;
    for i := 0 to FDeferredCount - 1 do
      if FDeferred[i].Kind <> tdkResize then
      begin
        FDeferred[k] := FDeferred[i];
        Inc(k);
      end;
    for i := k to FDeferredCount - 1 do
      FDeferred[i].Data := '';
    FDeferredCount := k;
  end;
  if FDeferredCount = Length(FDeferred) then
    SetLength(FDeferred, FDeferredCount * 2 + 4);
  FDeferred[FDeferredCount].Kind := AKind;
  FDeferred[FDeferredCount].Cols := ACols;
  FDeferred[FDeferredCount].Rows := ARows;
  FDeferred[FDeferredCount].Data := AData;
  Inc(FDeferredCount);
end;

{ In call order, each through its public method (the core is idle again). One that
  raises leaves the rest for later. }
procedure TTyTerminalCore.RunDeferred;
var
  d: TTyTermDeferred;
  i: Integer;
begin
  { half a chunk parsed: what its events asked for waits for its last piece }
  if FChunkPos > 0 then
    Exit;
  while (FBusy = 0) and (FDeferredCount > 0) do
  begin
    d := FDeferred[0];
    for i := 0 to FDeferredCount - 2 do
      FDeferred[i] := FDeferred[i + 1];
    Dec(FDeferredCount);
    FDeferred[FDeferredCount].Data := '';
    case d.Kind of
      tdkResize: Resize(d.Cols, d.Rows);
      tdkReset: Reset;
      tdkWriteSync: WriteSync(d.Data);
    end;
  end;
end;

{ ProcessPending came while the core was busy: ask again now that it is not }
procedure TTyTerminalCore.AfterDrive;
begin
  if FRerequest and (FBusy = 0) and not FIsSyncWriting then
  begin
    FRerequest := False;
    if (FFront <> '') or (FQueueCount > FBufferOffset) or (FDeferredCount > 0) then
      RequestProcess;
  end;
end;
