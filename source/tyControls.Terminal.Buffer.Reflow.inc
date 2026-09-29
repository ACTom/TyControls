{ Part of tyControls.Terminal.Buffer (included, not a unit): the reflow on a new
  column count. Ported from xterm.js 6.0.0 (commit c58ea3637f39),
  src/common/buffer/BufferReflow.ts and src/common/buffer/Buffer.ts:310-537; the
  copyright and the licence are in the unit header. Line numbers below are those
  files'.

  The lines are reference counted where upstream's are held by JavaScript arrays:
  every line a layout moves is pinned (AddRef) before the ring is laid out again and
  released after it, and the blank lines a narrower reflow makes are released by
  their maker once the ring holds them (a new line nobody placed goes with it). }

{ ---- BufferReflow.ts ------------------------------------------------------------------ }

{ Math.min / Math.max on integers (the unit does not use Math) }
function IMin(A, B: Integer): Integer; inline;
begin
  if A < B then Result := A else Result := B;
end;

function IMax(A, B: Integer): Integer; inline;
begin
  if A > B then Result := A else Result := B;
end;

function TyTermGetWrappedLineTrimmedLength(const ALines: TTyTermLineArray; AIndex, ACols: Integer): Integer;
var
  endsInNull, followingLineStartsWithWide: Boolean;
begin                                                                        { :215-229 }
  { the last row of the run: its real trimmed length }
  if AIndex = High(ALines) then
    Exit(ALines[AIndex].GetTrimmedLength);
  { the end of this row empty and the next starting with a wide character: that
    empty cell is the one an early wrap left, not part of the text }
  endsInNull := (not ALines[AIndex].HasContent(ACols - 1)) and (ALines[AIndex].GetWidth(ACols - 1) = 1);
  followingLineStartsWithWide := ALines[AIndex + 1].GetWidth(0) = 2;
  if endsInNull and followingLineStartsWithWide then
    Result := ACols - 1
  else
    Result := ACols;
end;

procedure PushInt(var A: TIntegerDynArray; var ACount: Integer; AValue: Integer);
begin
  if ACount = System.Length(A) then
    SetLength(A, ACount * 2 + 8);
  A[ACount] := AValue;
  Inc(ACount);
end;

function TyTermReflowLargerGetLinesToRemove(ALines: TTyTerminalLineList; AOldCols, ANewCols,
  ABufferAbsoluteY: Integer; const ANullCell: TTyTerminalCellData; AReflowCursorLine: Boolean): TIntegerDynArray;
var
  y, i, n, count, destLineIndex, destCol, srcLineIndex, srcCol, srcTrimmedLength,
    srcRemainingCells, destRemainingCells, cellsToCopy, countToRemove, k: Integer;
  nextLine: TTyTerminalLine;
  wrapped: TTyTermLineArray;
begin                                                                        { :25-110 }
  Result := nil;
  count := 0;
  wrapped := nil;
  { for (y = 0; y < lines.length - 1; y++): every Continue lands on the Inc }
  y := -1;
  while True do
  begin
    Inc(y);
    if y >= ALines.Length - 1 then
      Break;
    { is this row wrapped? }
    i := y + 1;
    nextLine := ALines.Get(i);
    if not nextLine.IsWrapped then
      Continue;
    { how many rows it is wrapped over }
    n := 1;
    if System.Length(wrapped) < 8 then
      SetLength(wrapped, 8);
    wrapped[0] := ALines.Get(y);
    while (i < ALines.Length) and nextLine.IsWrapped do
    begin
      if n = System.Length(wrapped) then
        SetLength(wrapped, n * 2);
      wrapped[n] := nextLine;
      Inc(n);
      Inc(i);
      nextLine := ALines.Get(i);           { read past the end as upstream: not used }
    end;
    SetLength(wrapped, n);
    { the run holding the cursor is left to the program }
    if not AReflowCursorLine then
      if (ABufferAbsoluteY >= y) and (ABufferAbsoluteY < i) then
      begin
        Inc(y, n - 1);
        Continue;
      end;
    { copy the cells to their new places }
    destLineIndex := 0;
    destCol := TyTermGetWrappedLineTrimmedLength(wrapped, destLineIndex, AOldCols);
    srcLineIndex := 1;
    srcCol := 0;
    while srcLineIndex < n do
    begin
      srcTrimmedLength := TyTermGetWrappedLineTrimmedLength(wrapped, srcLineIndex, AOldCols);
      srcRemainingCells := srcTrimmedLength - srcCol;
      destRemainingCells := ANewCols - destCol;
      cellsToCopy := IMin(srcRemainingCells, destRemainingCells);
      wrapped[destLineIndex].CopyCellsFrom(wrapped[srcLineIndex], srcCol, destCol, cellsToCopy, False);
      Inc(destCol, cellsToCopy);
      if destCol = ANewCols then
      begin
        Inc(destLineIndex);
        destCol := 0;
      end;
      Inc(srcCol, cellsToCopy);
      if srcCol = srcTrimmedLength then
      begin
        Inc(srcLineIndex);
        srcCol := 0;
      end;
      { the last cell must not be the first half of a wide character: move it down }
      if (destCol = 0) and (destLineIndex <> 0) then
        if wrapped[destLineIndex - 1].GetWidth(ANewCols - 1) = 2 then
        begin
          wrapped[destLineIndex].CopyCellsFrom(wrapped[destLineIndex - 1], ANewCols - 1, destCol, 1, False);
          Inc(destCol);
          wrapped[destLineIndex - 1].SetCell(ANewCols - 1, ANullCell);
        end;
    end;
    { clear what is left, or fragments stay }
    wrapped[destLineIndex].ReplaceCells(destCol, ANewCols, ANullCell);
    { from the end, the rows now holding nothing }
    countToRemove := 0;
    for k := n - 1 downto 1 do
      if (k > destLineIndex) or (wrapped[k].GetTrimmedLength = 0) then
        Inc(countToRemove)
      else
        Break;
    if countToRemove > 0 then
    begin
      PushInt(Result, count, y + n - countToRemove);
      PushInt(Result, count, countToRemove);
    end;
    Inc(y, n - 1);
  end;
  SetLength(Result, count);
end;

function TyTermReflowLargerCreateNewLayout(ALines: TTyTerminalLineList;
  const AToRemove: TIntegerDynArray): TTyTermReflowLayout;
var
  i, n, nextToRemoveIndex, nextToRemoveStart, countRemovedSoFar, countToRemove: Integer;

  { toRemove[k], -1 past the end (upstream's undefined, never equal to an index) }
  function At(K: Integer): Integer;
  begin
    if (K >= 0) and (K <= High(AToRemove)) then Result := AToRemove[K] else Result := -1;
  end;

begin                                                                        { :116-145 }
  Result.Layout := nil;
  SetLength(Result.Layout, ALines.Length);
  n := 0;
  nextToRemoveIndex := 0;
  nextToRemoveStart := At(nextToRemoveIndex);
  countRemovedSoFar := 0;
  i := 0;
  while i < ALines.Length do
  begin
    if nextToRemoveStart = i then
    begin
      Inc(nextToRemoveIndex);
      countToRemove := At(nextToRemoveIndex);
      { markers learn of the deletion, forward, the index less what went before }
      ALines.NotifyDelete(i - countRemovedSoFar, countToRemove);
      Inc(i, countToRemove - 1);
      Inc(countRemovedSoFar, countToRemove);
      Inc(nextToRemoveIndex);
      nextToRemoveStart := At(nextToRemoveIndex);
    end
    else
    begin
      Result.Layout[n] := i;
      Inc(n);
    end;
    Inc(i);
  end;
  SetLength(Result.Layout, n);
  Result.CountRemoved := countRemovedSoFar;
end;

procedure TyTermReflowLargerApplyNewLayout(ALines: TTyTerminalLineList; const ALayout: TIntegerDynArray);
var
  newLayoutLines: TTyTermLineArray;
  i: Integer;
begin                                                                        { :151-163 }
  { the lines, pinned: the list's slots are overwritten below }
  newLayoutLines := nil;
  SetLength(newLayoutLines, System.Length(ALayout));
  for i := 0 to High(ALayout) do
  begin
    newLayoutLines[i] := ALines.Get(ALayout[i]);
    if newLayoutLines[i] <> nil then
      newLayoutLines[i].AddRef;
  end;
  try
    for i := 0 to High(newLayoutLines) do
      ALines.SetItem(i, newLayoutLines[i]);
    ALines.Length := System.Length(ALayout);
  finally
    for i := 0 to High(newLayoutLines) do
      if newLayoutLines[i] <> nil then
        newLayoutLines[i].Release;
  end;
end;

function TyTermReflowSmallerGetNewLineLengths(const AWrapped: TTyTermLineArray;
  AOldCols, ANewCols: Integer): TIntegerDynArray;
var
  i, count, cellsNeeded, srcCol, srcLine, cellsAvailable, oldTrimmedLength, lineLength: Integer;
  endsWithWide: Boolean;
begin                                                                        { :179-213 }
  Result := nil;
  count := 0;
  cellsNeeded := 0;
  for i := 0 to High(AWrapped) do
    Inc(cellsNeeded, TyTermGetWrappedLineTrimmedLength(AWrapped, i, AOldCols));
  { srcCol and srcLine find the new wrapping points }
  srcCol := 0;
  srcLine := 0;
  cellsAvailable := 0;
  while cellsAvailable < cellsNeeded do
  begin
    if cellsNeeded - cellsAvailable < ANewCols then
    begin
      { the last line }
      PushInt(Result, count, cellsNeeded - cellsAvailable);
      Break;
    end;
    Inc(srcCol, ANewCols);
    oldTrimmedLength := TyTermGetWrappedLineTrimmedLength(AWrapped, srcLine, AOldCols);
    if srcCol > oldTrimmedLength then
    begin
      Dec(srcCol, oldTrimmedLength);
      Inc(srcLine);
    end;
    if srcLine > High(AWrapped) then
      raise EArgumentOutOfRangeException.Create('reflow: past the wrapped lines');
    endsWithWide := AWrapped[srcLine].GetWidth(srcCol - 1) = 2;
    if endsWithWide then
      Dec(srcCol);
    if endsWithWide then
      lineLength := ANewCols - 1
    else
      lineLength := ANewCols;
    { a line of no cells: one column and a wide character here -- upstream loops for
      ever from this point (:175-177) }
    if lineLength <= 0 then
      raise EArgumentOutOfRangeException.Create('reflow: a wide character does not fit in one column');
    PushInt(Result, count, lineLength);
    Inc(cellsAvailable, lineLength);
  end;
  SetLength(Result, count);
end;

{ ---- Buffer.ts: _reflow* ---------------------------------------------------------------- }

procedure TTyTerminalBuffer.Reflow(ANewCols, ANewRows: Integer);
begin                                                                        { :318-329 }
  if FCols = ANewCols then
    Exit;
  if ANewCols > FCols then
    ReflowLarger(ANewCols, ANewRows)
  else
    ReflowSmaller(ANewCols, ANewRows);
end;

procedure TTyTerminalBuffer.ReflowLarger(ANewCols, ANewRows: Integer);
var
  toRemove: TIntegerDynArray;
  layout: TTyTermReflowLayout;
begin                                                                        { :331-339 }
  toRemove := TyTermReflowLargerGetLinesToRemove(FLines, FCols, ANewCols, FYBase + FY,
    GetNullCell(TyTermDefaultAttr), FOptions.ReflowCursorLine);
  if System.Length(toRemove) > 0 then
  begin
    layout := TyTermReflowLargerCreateNewLayout(FLines, toRemove);
    TyTermReflowLargerApplyNewLayout(FLines, layout.Layout);
    ReflowLargerAdjustViewport(ANewCols, ANewRows, layout.CountRemoved);
  end;
end;

procedure TTyTerminalBuffer.ReflowLargerAdjustViewport(ANewCols, ANewRows, ACountRemoved: Integer);
var
  nullCell: TTyTerminalCellData;
  viewportAdjustments: Integer;
begin                                                                        { :341-362 }
  nullCell := GetNullCell(TyTermDefaultAttr);
  viewportAdjustments := ACountRemoved;
  while viewportAdjustments > 0 do
  begin
    Dec(viewportAdjustments);
    if FYBase = 0 then
    begin
      if FY > 0 then
        Dec(FY);
      if FLines.Length < ANewRows then
        { an extra row at the bottom of the viewport }
        FLines.PushOwned(TTyTerminalLine.Create(ANewCols, nullCell, False));
    end
    else
    begin
      if FYDisp = FYBase then
        Dec(FYDisp);
      Dec(FYBase);
    end;
  end;
  if SavedY - ACountRemoved > 0 then
    SavedY := SavedY - ACountRemoved
  else
    SavedY := 0;
end;

procedure TTyTerminalBuffer.ReflowSmaller(ANewCols, ANewRows: Integer);
type
  TToInsert = record
    Start: Integer;
    NewLines: TTyTermLineArray;
  end;
  TInsertEvent = record
    Index, Amount: Integer;
  end;
var
  reflowCursorLine: Boolean;
  nullCell: TTyTerminalCellData;
  toInsert: array of TToInsert;
  insertCount, countToInsert, y, n, i, k, absoluteY, lastLineLength, linesToAdd, trimmedLines,
    destLineIndex, destCol, srcLineIndex, srcCol, cellsToCopy, viewportAdjustments,
    originalLinesLength, originalLineIndex, nextToInsertIndex, countInsertedSoFar, nextI,
    insertCountEmitted, amountToTrim, eventCount, createdCount: Integer;
  nextLine: TTyTerminalLine;
  wrapped, newLines, created, originalLines: TTyTermLineArray;
  destLineLengths: TIntegerDynArray;
  insertEvents: array of TInsertEvent;

  { destLineLengths[K], -1 outside (upstream's undefined: never 0, never below newCols
    in a comparison that matters -- see the loop) }
  function LengthAt(K: Integer): Integer;
  begin
    if (K >= 0) and (K <= High(destLineLengths)) then Result := destLineLengths[K] else Result := -1;
  end;

begin                                                                        { :364-537 }
  reflowCursorLine := FOptions.ReflowCursorLine;
  nullCell := GetNullCell(TyTermDefaultAttr);
  { the new lines to put in, gathered so the ring is laid out once, at the end }
  toInsert := nil;
  insertCount := 0;
  countToInsert := 0;
  created := nil;
  createdCount := 0;
  try
    { backwards: lines may be trimmed off the top as we go. The start is taken once;
      every Continue lands on the Dec (for y-- upstream). }
    y := FLines.Length;
    while True do
    begin
      Dec(y);
      if y < 0 then
        Break;
      nextLine := FLines.Get(y);
      if (nextLine = nil) or ((not nextLine.IsWrapped) and (nextLine.GetTrimmedLength <= ANewCols)) then
        Continue;
      { the run, y moved to its first row }
      n := 1;
      SetLength(wrapped, 8);
      wrapped[0] := nextLine;
      while nextLine.IsWrapped and (y > 0) do
      begin
        Dec(y);
        nextLine := FLines.Get(y);
        if n = System.Length(wrapped) then
          SetLength(wrapped, n * 2);
        wrapped[n] := nextLine;
        Inc(n);
      end;
      SetLength(wrapped, n);
      for i := 0 to n div 2 - 1 do
      begin
        nextLine := wrapped[i];
        wrapped[i] := wrapped[n - 1 - i];
        wrapped[n - 1 - i] := nextLine;
      end;
      { the run holding the cursor is left to the program }
      if not reflowCursorLine then
      begin
        absoluteY := FYBase + FY;
        if (absoluteY >= y) and (absoluteY < y + n) then
          Continue;
      end;
      lastLineLength := wrapped[n - 1].GetTrimmedLength;
      destLineLengths := TyTermReflowSmallerGetNewLineLengths(wrapped, FCols, ANewCols);
      linesToAdd := System.Length(destLineLengths) - n;
      if (FYBase = 0) and (FY <> FLines.Length - 1) then
        { the top of the buffer is not filled yet }
        trimmedLines := IMax(0, FY - FLines.MaxLength + linesToAdd)
      else
        trimmedLines := IMax(0, FLines.Length - FLines.MaxLength + linesToAdd);
      { the new lines }
      newLines := nil;
      if linesToAdd > 0 then
      begin
        SetLength(newLines, linesToAdd);
        for i := 0 to linesToAdd - 1 do
        begin
          newLines[i] := GetBlankLine(TyTermDefaultAttr, True);
          if createdCount = System.Length(created) then
            SetLength(created, createdCount * 2 + 8);
          created[createdCount] := newLines[i];
          Inc(createdCount);
        end;
        { the index counts the lines inserted after this run already: the list is
          walked forwards at the end }
        if insertCount = System.Length(toInsert) then
          SetLength(toInsert, insertCount * 2 + 4);
        toInsert[insertCount].Start := y + n + countToInsert;
        toInsert[insertCount].NewLines := newLines;
        Inc(insertCount);
        Inc(countToInsert, linesToAdd);
        SetLength(wrapped, n + linesToAdd);
        for i := 0 to linesToAdd - 1 do
          wrapped[n + i] := newLines[i];
      end;
      { copy the cells to their new places, backwards to do it in place }
      destLineIndex := System.Length(destLineLengths) - 1;
      destCol := LengthAt(destLineIndex);
      if destCol = 0 then
      begin
        Dec(destLineIndex);
        destCol := LengthAt(destLineIndex);
      end;
      srcLineIndex := System.Length(wrapped) - linesToAdd - 1;
      { fewer lines than the run: upstream would read past its array and throw }
      if srcLineIndex > High(wrapped) then
        raise EArgumentOutOfRangeException.Create('reflow: the run would lose lines');
      srcCol := lastLineLength;
      while srcLineIndex >= 0 do
      begin
        cellsToCopy := IMin(srcCol, destCol);
        { upstream's check that the line exists ("known to fail for an unknown reason") }
        if (destLineIndex < 0) or (destLineIndex > High(wrapped)) then
          Break;
        wrapped[destLineIndex].CopyCellsFrom(wrapped[srcLineIndex], srcCol - cellsToCopy, destCol - cellsToCopy,
          cellsToCopy, True);
        Dec(destCol, cellsToCopy);
        if destCol = 0 then
        begin
          Dec(destLineIndex);
          destCol := LengthAt(destLineIndex);
        end;
        Dec(srcCol, cellsToCopy);
        if srcCol = 0 then
        begin
          Dec(srcLineIndex);
          srcCol := TyTermGetWrappedLineTrimmedLength(wrapped, IMax(srcLineIndex, 0), FCols);
        end;
      end;
      { an empty cell ends a row a wide character wrapped away from }
      for i := 0 to High(wrapped) do
        if (i <= High(destLineLengths)) and (destLineLengths[i] < ANewCols) then
          wrapped[i].SetCell(destLineLengths[i], nullCell);
      { the viewport, run by run (a pop here changes what is left to walk) }
      viewportAdjustments := linesToAdd - trimmedLines;
      while viewportAdjustments > 0 do
      begin
        Dec(viewportAdjustments);
        if FYBase = 0 then
        begin
          if FY < ANewRows - 1 then
          begin
            Inc(FY);
            FLines.Pop;
          end
          else
          begin
            Inc(FYBase);
            Inc(FYDisp);
          end;
        end
        else
        begin
          { ybase stays within its maximum }
          if FYBase < IMin(FLines.MaxLength, FLines.Length + countToInsert) - ANewRows then
          begin
            if FYBase = FYDisp then
              Inc(FYDisp);
            Inc(FYBase);
          end;
        end;
      end;
      SavedY := IMin(SavedY + linesToAdd, FYBase + ANewRows - 1);
    end;

    { the ring laid out again in one pass, the insert events played back backwards so
      their indexes come out right, then the trim }
    if insertCount > 0 then
    begin
      originalLinesLength := FLines.Length;
      originalLines := nil;
      SetLength(originalLines, originalLinesLength);
      for i := 0 to originalLinesLength - 1 do
      begin
        originalLines[i] := FLines.Get(i);
        if originalLines[i] <> nil then
          originalLines[i].AddRef;
      end;
      try
        insertEvents := nil;
        SetLength(insertEvents, insertCount);
        eventCount := 0;
        originalLineIndex := originalLinesLength - 1;
        nextToInsertIndex := 0;
        FLines.Length := IMin(FLines.MaxLength, FLines.Length + countToInsert);
        countInsertedSoFar := 0;
        i := IMin(FLines.MaxLength - 1, originalLinesLength + countToInsert - 1);
        while i >= 0 do
        begin
          if (nextToInsertIndex < insertCount)
            and (toInsert[nextToInsertIndex].Start > originalLineIndex + countInsertedSoFar) then
          begin
            newLines := toInsert[nextToInsertIndex].NewLines;
            for nextI := High(newLines) downto 0 do
            begin
              FLines.SetItem(i, newLines[nextI]);
              Dec(i);
            end;
            Inc(i);
            insertEvents[eventCount].Index := originalLineIndex + 1;
            insertEvents[eventCount].Amount := System.Length(newLines);
            Inc(eventCount);
            Inc(countInsertedSoFar, System.Length(newLines));
            Inc(nextToInsertIndex);
          end
          else
          begin
            if originalLineIndex >= 0 then
              FLines.SetItem(i, originalLines[originalLineIndex])
            else
              FLines.SetItem(i, nil);
            Dec(originalLineIndex);
          end;
          Dec(i);
        end;
        insertCountEmitted := 0;
        for k := eventCount - 1 downto 0 do
        begin
          Inc(insertEvents[k].Index, insertCountEmitted);
          FLines.NotifyInsert(insertEvents[k].Index, insertEvents[k].Amount);
          Inc(insertCountEmitted, insertEvents[k].Amount);
        end;
        amountToTrim := IMax(0, originalLinesLength + countToInsert - FLines.MaxLength);
        if amountToTrim > 0 then
          FLines.NotifyTrim(amountToTrim);
      finally
        for i := 0 to High(originalLines) do
          if originalLines[i] <> nil then
            originalLines[i].Release;
      end;
    end;
  finally
    { the maker's reference: the ring holds the lines it took }
    for i := 0 to createdCount - 1 do
      created[i].Release;
  end;
end;
