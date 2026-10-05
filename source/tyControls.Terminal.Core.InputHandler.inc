{ Part of tyControls.Terminal.Core (included, not a unit): InputHandler.ts -- parse,
  print and every control sequence handler. Moved out of the unit only to keep it
  readable; the port, its sources and its licence are in the unit header. }

{ ==== InputHandler: parse, print, controls, cursor, erase, scroll ================================== }

{ parse, InputHandler.ts:430-485, without the async resume. The input is cut every
  131072 BYTES (MAX_PARSEBUFFER_LENGTH counts input units, and a byte is the unit
  here); the decoder and precedingJoinState carry across the cuts. The core is busy
  throughout, the closing events included, so a handler cannot parse, resize or
  reset under it (unit header); the closing events fire even when a handler raised,
  so the rows it changed are still reported. }
procedure TTyTerminalCore.Parse(const AData: RawByteString);
begin
  ParseRange(AData, 1, Length(AData));
end;

{ The write queue hands a chunk over one piece at a time (unit header): each piece is
  one call here, the decoder's half sequence carried to the next. }
procedure TTyTerminalCore.ParseRange(const AData: RawByteString; AStart, ACount: Integer);
begin
  ParseDecoded(FDecoder, AData, AStart, ACount);
end;

{ ParseRange with the decoder given: the program's (FDecoder), or the stream session's
  own for ShowText (spec 19.3), so neither cuts into the other's half sequence. Text
  shown while a parse runs (from one of its events) waits in FShowPending and is
  parsed once the outermost parse has returned. }
procedure TTyTerminalCore.ParseDecoded(ADecoder: TTyUtf8Decoder; const AData: RawByteString;
  AStart, ACount: Integer);
var
  buf: TTyTerminalBuffer;
  cursorStartX, cursorStartY, total, i, chunk, len, viewportStart, viewportEnd: Integer;
begin
  Inc(FBusy);
  Inc(FParsing);
  try
    buf := Buffer;
    cursorStartX := buf.X;
    cursorStartY := buf.Y;
    total := ACount;
    chunk := Min(total, TyTermMaxParseBuffer);
    if Length(FParseBuffer) < chunk then
      SetLength(FParseBuffer, chunk);
    { which rows the parse changes }
    ClearRange;
    try
      i := 0;
      while i < total do
      begin
        chunk := Min(TyTermMaxParseBuffer, total - i);
        len := ADecoder.Decode(AData[AStart + i], chunk, FParseBuffer);
        FParser.Parse(FParseBuffer, len);
        Inc(i, chunk);
      end;
    finally
      buf := Buffer;
      if (buf.X <> cursorStartX) or (buf.Y <> cursorStartY) then
        if Assigned(FOnCursorMove) then
          FOnCursorMove(Self);
      { the rows that changed, relative to the viewport (ydisp), not to ybase }
      viewportEnd := FDirtyEnd + (buf.YBase - buf.YDisp);
      viewportStart := FDirtyStart + (buf.YBase - buf.YDisp);
      if viewportStart < Rows then
        if Assigned(FOnRefreshRows) then
          FOnRefreshRows(Self, Min(viewportStart, Rows - 1), Min(viewportEnd, Rows - 1));
    end;
  finally
    Dec(FParsing);
    Dec(FBusy);
  end;
  if (FParsing = 0) and (FShowPending <> '') and not FShowFlushing then
    FlushShowPending;
end;

procedure TTyTerminalCore.PrintHandler(const AData: array of Cardinal; AStart, AEnd: Integer);
begin
  DoPrint(AData, AStart, AEnd, 1);
end;

{ print, InputHandler.ts:517-661. ARepeat runs the same text that many times in ONE
  call, which is what REP's single print of the repeated text is upstream -- without
  building the repeated array. The current row, and the old row across a wrap, are
  pinned: a scroll can drop them from the ring while print still writes to them, as
  upstream keeps writing to a detached line.

  REP's fast-forward (unit header). At the end of each repetition the state that
  decides the rest is the cursor (x, y) and the join state: the text is the same
  every time, so equal keys at two repetitions r1 < r2 repeat forever with period
  p = r2 - r1 (Brent's search: a snapshot at r = 2, 4, 8 ...). Two cases:
  - the p repetitions scrolled (sp > 0 scrolls): y is the bottom margin throughout
    and every wrap scrolls a fresh line in. After 2 x ring + rows more scrolls every
    line the ring holds, ybase and ydisp are what the last repetitions made them, so
    whole periods past that are skipped; the ring's start index is advanced by the
    skipped scrolls, as the push / recycle / splice they stand for would have.
  - none scrolled: only the cursor's line was written. When it also equals its
    snapshot, the state itself repeats and the remaining repetitions are reduced
    modulo p. When it keeps changing (code points piling onto one cell) the
    repetitions stop after TyTermRepeatLimit code points on that line. }
procedure TTyTerminalCore.DoPrint(const AData: array of Cardinal; AStart, AEnd: Integer; ARepeat: Int64);
var
  buf: TTyTerminalBuffer;
  bufferRow, oldRow, ln, snapLine: TTyTerminalLine;
  charset: TTyTermCharsetId;
  ncols, pos, chWidth, oldWidth, oldCol, offset, delta, yBefore, snapX, snapY: Integer;
  code, m: Cardinal;
  wraparound, insert, shouldJoin, hasText, tracking, haveSnap, ffDone: Boolean;
  precedingJoinState, currentInfo, snapJoin: TTyUnicodeCharProps;
  linkId: Int64;
  r, reps, scrolls, stall, snapRep, snapScrolls, snapLimit, p, sp, need, target, periods, skipped: Int64;
begin
  charset := FCharset;
  ncols := Cols;
  wraparound := FWraparound;
  insert := FInsertMode;
  buf := Buffer;
  bufferRow := buf.Lines.Get(buf.YBase + buf.Y);
  if bufferRow = nil then
    Exit;
  bufferRow.AddRef;
  oldRow := nil;
  snapLine := nil;
  try
    MarkDirty(buf.Y);
    hasText := (AEnd > AStart) and (ARepeat > 0);
    reps := ARepeat;
    if not hasText then
      reps := 0;
    tracking := reps > 1;
    scrolls := 0;
    stall := 0;
    skipped := 0;
    haveSnap := False;
    ffDone := False;
    snapRep := 0;
    snapScrolls := 0;
    snapLimit := 1;
    snapX := 0;
    snapY := 0;
    snapJoin := 0;
    { overwriting the second cell of a wide character: reset the first }
    if (buf.X <> 0) and hasText and (bufferRow.GetWidth(buf.X - 1) = 2) then
      bufferRow.SetCellFromCodepoint(buf.X - 1, 0, 1, FCurAttr);
    precedingJoinState := FParser.PrecedingJoinState;
    r := 0;
    while r < reps do
    begin
      Inc(r);
      for pos := AStart to AEnd - 1 do
      begin
        Inc(stall);
        code := AData[pos];
        { soft hyphen: a zero-width layout hint, ignored (:546-548) }
        if code = $AD then
          Continue;
        { charset replacement, ASCII only }
        if (code < 127) and (charset <> 0) and (code >= $20) then
        begin
          m := TyTermCharsetMap[charset, code];
          if m <> 0 then
            code := m;
        end;
        currentInfo := TyUnicodeCharProperties(code, precedingJoinState, FUnicodeVersion, FAmbiguousWide);
        chWidth := TyUnicodePropsWidth(currentInfo);
        shouldJoin := TyUnicodePropsShouldJoin(currentInfo);
        if shouldJoin then
          oldWidth := TyUnicodePropsWidth(precedingJoinState)
        else
          oldWidth := 0;
        precedingJoinState := currentInfo;
        linkId := FCurAttr.Extended.UrlId;
        if linkId <> 0 then
          FLinks.AddLineToLink(linkId, buf.YBase + buf.Y);

        { the character does not fit: wrap (DECAWM) or stay in the last cell }
        if buf.X + chWidth - oldWidth > ncols then
        begin
          if wraparound then
          begin
            oldRow := bufferRow;             { the pin moves with it }
            bufferRow := nil;
            oldCol := buf.X - oldWidth;
            buf.X := oldWidth;
            yBefore := buf.Y;
            buf.Y := buf.Y + 1;
            if buf.Y = buf.ScrollBottom + 1 then
            begin
              buf.Y := buf.Y - 1;
              FBufferService.Scroll(EraseAttrData, True);
              Inc(scrolls);
              stall := 0;
            end
            else
            begin
              if buf.Y >= Rows then
                buf.Y := Rows - 1;
              if buf.Y <> yBefore then
                stall := 0;
              { an existing line (the initial viewport): mark it wrapped }
              ln := buf.Lines.Get(buf.YBase + buf.Y);
              if ln <> nil then
                ln.IsWrapped := True;
            end;
            bufferRow := buf.Lines.Get(buf.YBase + buf.Y);
            if bufferRow = nil then
              Exit;
            bufferRow.AddRef;
            { a combining character widened the last one: move it to the new line }
            if oldWidth > 0 then
              bufferRow.CopyCellsFrom(oldRow, oldCol, 0, oldWidth, False);
            { clear what is left to the right }
            while oldCol < ncols do
            begin
              oldRow.SetCellFromCodepoint(oldCol, 0, 1, FCurAttr);
              Inc(oldCol);
            end;
            oldRow.Release;
            oldRow := nil;
          end
          else
          begin
            buf.X := ncols - 1;
            { a wide character that does not fit the last cell is dropped }
            if chWidth = 2 then
              Continue;
          end;
        end;

        { a joining character goes onto the previous cell }
        if shouldJoin and (buf.X <> 0) then
        begin
          { after a wide character the empty stub sits in between }
          if bufferRow.GetWidth(buf.X - 1) <> 0 then
            offset := 1
          else
            offset := 2;
          bufferRow.AddCodepointToCell(buf.X - offset, code, chWidth);
          delta := chWidth - oldWidth;
          while delta > 0 do
          begin
            bufferRow.SetCellFromCodepoint(buf.X, 0, 0, FCurAttr);
            buf.X := buf.X + 1;
            Dec(delta);
          end;
          Continue;
        end;

        { insert mode: shift right; a wide character pushed into the last cell is lost }
        if insert then
        begin
          bufferRow.InsertCells(buf.X, chWidth - oldWidth, buf.GetNullCell(FCurAttr));
          if bufferRow.GetWidth(ncols - 1) = 2 then
            bufferRow.SetCellFromCodepoint(ncols - 1, TyTermNullCellCode, TyTermNullCellWidth, FCurAttr);
        end;

        bufferRow.SetCellFromCodepoint(buf.X, code, chWidth, FCurAttr);
        buf.X := buf.X + 1;
        { the cells after a wide character: empty stubs of width 0 }
        if chWidth > 0 then
        begin
          Dec(chWidth);
          while chWidth > 0 do
          begin
            bufferRow.SetCellFromCodepoint(buf.X, 0, 0, FCurAttr);
            buf.X := buf.X + 1;
            Dec(chWidth);
          end;
        end;
      end;

      { ---- the end of one repetition: the REP fast-forward (above) ---- }
      if tracking and (r < reps) then
      begin
        if stall > TyTermRepeatLimit then
          reps := r                        { piling onto one line: stop here }
        else if (r >= 2) and not ffDone then
        begin
          if haveSnap and (buf.X = snapX) and (buf.Y = snapY) and (precedingJoinState = snapJoin) then
          begin
            p := r - snapRep;
            sp := scrolls - snapScrolls;
            if sp > 0 then
            begin
              { at least 2 x ring + rows more scrolls are printed for real }
              need := 2 * Int64(buf.Lines.MaxLength) + Rows + 2;
              target := r + ((need + sp - 1) div sp) * p;
              if target < reps then
              begin
                periods := (reps - target) div p;
                reps := reps - periods * p;
                skipped := periods * sp;
              end;
              ffDone := True;
            end
            else if bufferRow.SameCells(snapLine) then
            begin
              reps := r + (reps - r) mod p;
              ffDone := True;
            end;
          end;
          if not ffDone and (not haveSnap or (r - snapRep >= snapLimit)) then
          begin
            if haveSnap then
              snapLimit := snapLimit * 2;
            haveSnap := True;
            snapRep := r;
            snapScrolls := scrolls;
            snapX := buf.X;
            snapY := buf.Y;
            snapJoin := precedingJoinState;
            if snapLine <> nil then
              snapLine.Release;
            snapLine := nil;
            snapLine := bufferRow.Clone;
          end;
        end;
      end;
    end;
    { the skipped scrolls' effect on the ring's start index: push / recycle reduce
      it modulo the length (top margin 0, bottom margin the last row), a splice below
      a lower margin does not, a shift inside a top margin leaves it }
    if (skipped > 0) and (buf.ScrollTop = 0) then
      buf.Lines.AdvanceStart(skipped, buf.ScrollBottom = Rows - 1);
    FParser.PrecedingJoinState := precedingJoinState;
    { a lone second half of a wide character right of the cursor: reset it }
    if (buf.X < ncols) and hasText and (bufferRow.GetWidth(buf.X) = 0)
      and not bufferRow.HasContent(buf.X) then
      bufferRow.SetCellFromCodepoint(buf.X, 0, 1, FCurAttr);
    MarkDirty(buf.Y);
  finally
    if bufferRow <> nil then
      bufferRow.Release;
    if oldRow <> nil then
      oldRow.Release;
    if snapLine <> nil then
      snapLine.Release;
  end;
end;

{ _eraseAttrData, :3441-3445: only the background colour of the current attributes }
function TTyTerminalCore.EraseAttrData: TTyTerminalAttrData;
begin
  FEraseAttr.Bg := FEraseAttr.Bg and not Cardinal(TyTermAttrCmMask or $FFFFFF);
  FEraseAttr.Bg := FEraseAttr.Bg or (FCurAttr.Bg and not Cardinal($FC000000));
  Result := FEraseAttr;
end;

{ _restrictCursor, :889-895 }
procedure TTyTerminalCore.RestrictCursor(AMaxCol: Integer);
var
  buf: TTyTerminalBuffer;
begin
  buf := Buffer;
  if AMaxCol = -1 then
    AMaxCol := Cols - 1;
  buf.X := Min(AMaxCol, Max(0, buf.X));
  if FOrigin then
    buf.Y := Min(buf.ScrollBottom, Max(buf.ScrollTop, buf.Y))
  else
    buf.Y := Min(Rows - 1, Max(0, buf.Y));
  MarkDirty(buf.Y);
end;

{ _setCursor, :900-911, the sums in Int64 (a parameter can be 2^31 - 1) }
procedure TTyTerminalCore.SetCursor(AX, AY: Int64);
var
  buf: TTyTerminalBuffer;
begin
  buf := Buffer;
  MarkDirty(buf.Y);
  if FOrigin then
  begin
    buf.X := ClampInt(AX);
    buf.Y := ClampInt(buf.ScrollTop + AY);
  end
  else
  begin
    buf.X := ClampInt(AX);
    buf.Y := ClampInt(AY);
  end;
  RestrictCursor;
  MarkDirty(buf.Y);
end;

{ _moveCursor, :916-921 }
procedure TTyTerminalCore.MoveCursor(AX, AY: Int64);
begin
  RestrictCursor;
  SetCursor(Buffer.X + AX, Buffer.Y + AY);
end;

function P0or1(AParams: TTyTerminalParams): Integer; inline;
begin
  Result := AParams[0];
  if Result = 0 then
    Result := 1;
end;

function TTyTerminalCore.Bell: Boolean;                                      { :727-730 }
begin
  if Assigned(FOnBell) then
    FOnBell(Self);
  Result := True;
end;

function TTyTerminalCore.LineFeed: Boolean;                                  { :742-771 }
var
  buf: TTyTerminalBuffer;
  line: TTyTerminalLine;
begin
  buf := Buffer;
  MarkDirty(buf.Y);
  if FOptions.ConvertEol then
    buf.X := 0;
  buf.Y := buf.Y + 1;
  if buf.Y = buf.ScrollBottom + 1 then
  begin
    buf.Y := buf.Y - 1;
    FBufferService.Scroll(EraseAttrData);
  end
  else if buf.Y >= Rows then
    buf.Y := Rows - 1
  else
  begin
    { an explicit line feed: this line is not a wrapped continuation }
    line := buf.Lines.Get(buf.YBase + buf.Y);
    if line <> nil then
      line.IsWrapped := False;
  end;
  { at the end of the line, do not wrap on to the next one }
  if buf.X >= Cols then
    buf.X := buf.X - 1;
  MarkDirty(buf.Y);
  { onLineFeed: the Windows heuristic listens first (CoreTerminal.ts:293) }
  if FWindowsHeuristics then
    UpdateWindowsModeWrappedState;
  if Assigned(FOnLineFeed) then
    FOnLineFeed(Self);
  Result := True;
end;

function TTyTerminalCore.CarriageReturn: Boolean;                            { :777-780 }
begin
  Buffer.X := 0;
  Result := True;
end;

function TTyTerminalCore.Backspace: Boolean;                                 { :793-845 }
var
  buf: TTyTerminalBuffer;
  line: TTyTerminalLine;
begin
  buf := Buffer;
  if not FReverseWraparound then
  begin
    RestrictCursor;
    if buf.X > 0 then
      buf.X := buf.X - 1;
    Exit(True);
  end;
  { reverse wrap-around: x may be cols here to reach the last cell }
  RestrictCursor(Cols);
  if buf.X > 0 then
    buf.X := buf.X - 1
  else
  begin
    { only a soft wrap is undone, within the margins, never into the scrollback }
    line := buf.Lines.Get(buf.YBase + buf.Y);
    if (buf.X = 0) and (buf.Y > buf.ScrollTop) and (buf.Y <= buf.ScrollBottom)
      and (line <> nil) and line.IsWrapped then
    begin
      line.IsWrapped := False;
      buf.Y := buf.Y - 1;
      buf.X := Cols - 1;
      { an empty cell left by a wide character that wrapped early: one more back }
      line := buf.Lines.Get(buf.YBase + buf.Y);
      if (line <> nil) and line.HasWidth(buf.X) and not line.HasContent(buf.X) then
        buf.X := buf.X - 1;
    end;
  end;
  RestrictCursor;
  Result := True;
end;

function TTyTerminalCore.Tab: Boolean;                                       { :850-860 }
begin
  if Buffer.X >= Cols then
    Exit(True);
  Buffer.X := Buffer.NextStop;
  Result := True;
end;

function TTyTerminalCore.ShiftOut: Boolean;
begin
  SetGLevel(1);
  Result := True;
end;

function TTyTerminalCore.ShiftIn: Boolean;
begin
  SetGLevel(0);
  Result := True;
end;

function TTyTerminalCore.CursorUp(AParams: TTyTerminalParams): Boolean;     { :930-940 }
var
  diffToTop: Integer;
begin
  diffToTop := Buffer.Y - Buffer.ScrollTop;
  if diffToTop >= 0 then
    MoveCursor(0, -Min(Int64(diffToTop), P0or1(AParams)))
  else
    MoveCursor(0, -Int64(P0or1(AParams)));
  Result := True;
end;

function TTyTerminalCore.CursorDown(AParams: TTyTerminalParams): Boolean;   { :948-958 }
var
  diffToBottom: Integer;
begin
  diffToBottom := Buffer.ScrollBottom - Buffer.Y;
  if diffToBottom >= 0 then
    MoveCursor(0, Min(Int64(diffToBottom), P0or1(AParams)))
  else
    MoveCursor(0, P0or1(AParams));
  Result := True;
end;

function TTyTerminalCore.CursorForward(AParams: TTyTerminalParams): Boolean;
begin
  MoveCursor(P0or1(AParams), 0);
  Result := True;
end;

function TTyTerminalCore.CursorBackward(AParams: TTyTerminalParams): Boolean;
begin
  MoveCursor(-Int64(P0or1(AParams)), 0);
  Result := True;
end;

function TTyTerminalCore.CursorNextLine(AParams: TTyTerminalParams): Boolean;
begin
  CursorDown(AParams);
  Buffer.X := 0;
  Result := True;
end;

function TTyTerminalCore.CursorPrecedingLine(AParams: TTyTerminalParams): Boolean;
begin
  CursorUp(AParams);
  Buffer.X := 0;
  Result := True;
end;

function TTyTerminalCore.CursorCharAbsolute(AParams: TTyTerminalParams): Boolean;
begin
  SetCursor(Int64(P0or1(AParams)) - 1, Buffer.Y);
  Result := True;
end;

function TTyTerminalCore.CursorPosition(AParams: TTyTerminalParams): Boolean;  { :1036-1045 }
var
  col: Int64;
begin
  if AParams.Length >= 2 then
  begin
    col := AParams[1];
    if col = 0 then col := 1;
    col := col - 1;
  end
  else
    col := 0;
  SetCursor(col, Int64(P0or1(AParams)) - 1);
  Result := True;
end;

function TTyTerminalCore.CharPosAbsolute(AParams: TTyTerminalParams): Boolean;
begin
  SetCursor(Int64(P0or1(AParams)) - 1, Buffer.Y);
  Result := True;
end;

function TTyTerminalCore.HPositionRelative(AParams: TTyTerminalParams): Boolean;
begin
  MoveCursor(P0or1(AParams), 0);
  Result := True;
end;

function TTyTerminalCore.LinePosAbsolute(AParams: TTyTerminalParams): Boolean;
begin
  SetCursor(Buffer.X, Int64(P0or1(AParams)) - 1);
  Result := True;
end;

function TTyTerminalCore.VPositionRelative(AParams: TTyTerminalParams): Boolean;
begin
  MoveCursor(0, P0or1(AParams));
  Result := True;
end;

function TTyTerminalCore.HVPosition(AParams: TTyTerminalParams): Boolean;
begin
  CursorPosition(AParams);
  Result := True;
end;

function TTyTerminalCore.TabClear(AParams: TTyTerminalParams): Boolean;     { :1109-1119 }
begin
  case AParams[0] of
    0: Buffer.SetTab(Buffer.X, False);
    3: Buffer.ClearAllTabs;
  end;
  Result := True;
end;

{ CHT / CBT, :1125-1150. Each pass that can still move moves at least one column
  (NextStop / PrevStop stop at the last / first column), so the count is clamped to
  the columns right of the cursor (CHT) or left of it (CBT); later passes stay put
  (unit header). }
function TTyTerminalCore.CursorForwardTab(AParams: TTyTerminalParams): Boolean;
var
  p: Integer;
begin
  if Buffer.X >= Cols then
    Exit(True);
  p := Min(P0or1(AParams), Cols - 1 - Buffer.X);
  while p > 0 do
  begin
    Buffer.X := Buffer.NextStop;
    Dec(p);
  end;
  Result := True;
end;

function TTyTerminalCore.CursorBackwardTab(AParams: TTyTerminalParams): Boolean;
var
  p: Integer;
begin
  if Buffer.X >= Cols then
    Exit(True);
  p := Min(P0or1(AParams), Buffer.X);
  while p > 0 do
  begin
    Buffer.X := Buffer.PrevStop;
    Dec(p);
  end;
  Result := True;
end;

function TTyTerminalCore.SelectProtected(AParams: TTyTerminalParams): Boolean;   { :1158-1163 }
var
  p: Integer;
begin
  p := AParams[0];
  if p = 1 then
    FCurAttr.Bg := FCurAttr.Bg or TyTermBgProtected;
  if (p = 2) or (p = 0) then
    FCurAttr.Bg := FCurAttr.Bg and not Cardinal(TyTermBgProtected);
  Result := True;
end;

procedure TTyTerminalCore.EraseInBufferLine(AY, AStart: Integer; AEnd: Int64; AClearWrap: Boolean;
  ARespectProtect: Boolean);
var
  line: TTyTerminalLine;
begin                                                                        { :1175-1190 }
  line := Buffer.Lines.Get(Buffer.YBase + AY);
  if line = nil then
    Exit;
  line.ReplaceCells(AStart, AEnd, Buffer.GetNullCell(EraseAttrData), ARespectProtect);
  if AClearWrap then
    line.IsWrapped := False;
end;

procedure TTyTerminalCore.ResetBufferLine(AY: Integer; ARespectProtect: Boolean);
var
  line: TTyTerminalLine;
begin                                                                        { :1196-1203 }
  line := Buffer.Lines.Get(Buffer.YBase + AY);
  if line <> nil then
  begin
    line.Fill(Buffer.GetNullCell(EraseAttrData), ARespectProtect);
    FBufferService.Buffer.ClearMarkers(Buffer.YBase + AY);
    line.IsWrapped := False;
  end;
end;

function TTyTerminalCore.EraseInDisplay(AParams: TTyTerminalParams; ARespectProtect: Boolean): Boolean;
var
  buf: TTyTerminalBuffer;
  j, scrollBackSize: Integer;
  found: Boolean;
  line: TTyTerminalLine;
begin                                                                        { :1229-1305 }
  buf := Buffer;
  RestrictCursor(Cols);
  case AParams[0] of
    0:
      begin
        j := buf.Y;
        MarkDirty(j);
        EraseInBufferLine(j, buf.X, Cols, buf.X = 0, ARespectProtect);
        Inc(j);
        while j < Rows do
        begin
          ResetBufferLine(j, ARespectProtect);
          Inc(j);
        end;
        MarkDirty(j);
      end;
    1:
      begin
        j := buf.Y;
        MarkDirty(j);
        { the front of the line and everything above: this line is not wrapped now }
        EraseInBufferLine(j, 0, Int64(buf.X) + 1, True, ARespectProtect);
        if buf.X + 1 >= Cols then
        begin
          { the whole line went: the next one cannot be a continuation. Upstream
            indexes lines.get(j + 1) without ybase; kept as it is. }
          line := buf.Lines.Get(j + 1);
          if line <> nil then
            line.IsWrapped := False;
        end;
        while j > 0 do
        begin
          Dec(j);
          ResetBufferLine(j, ARespectProtect);
        end;
        MarkDirty(0);
      end;
    2:
      if FOptions.ScrollOnEraseInDisplay then
      begin
        { push the screen, down to its last non-empty row, into the scrollback }
        j := Rows;
        MarkRangeDirty(0, j - 1);
        found := False;
        while j > 0 do
        begin
          Dec(j);
          line := buf.Lines.Get(buf.YBase + j);
          if (line <> nil) and (line.GetTrimmedLength <> 0) then
          begin
            found := True;
            Break;
          end;
        end;
        if not found then
          j := -1;
        while j >= 0 do
        begin
          FBufferService.Scroll(EraseAttrData);
          Dec(j);
        end;
      end
      else
      begin
        j := Rows;
        MarkDirty(j - 1);
        while j > 0 do
        begin
          Dec(j);
          ResetBufferLine(j, ARespectProtect);
        end;
        MarkDirty(0);
      end;
    3:
      begin
        { the scrollback: everything above the viewport }
        scrollBackSize := buf.Lines.Length - Rows;
        if scrollBackSize > 0 then
        begin
          buf.Lines.TrimStart(scrollBackSize);
          buf.YBase := Max(buf.YBase - scrollBackSize, 0);
          buf.YDisp := Max(buf.YDisp - scrollBackSize, 0);
          { isUserScrolling belongs to the normal buffer's viewport }
          if buf = Buffers.Normal then
            FBufferService.IsUserScrolling := False;
          { upstream then fires InputHandler.onScroll(0), which nothing listens to
            outside the browser: no OnScroll here. The host learns it from
            OnScrollbackCleared (ours). }
          if Assigned(FOnScrollbackCleared) then
            FOnScrollbackCleared(Self);
        end;
      end;
  end;
  Result := True;
end;

function TTyTerminalCore.EraseInDisplayCsi(AParams: TTyTerminalParams): Boolean;
begin
  Result := EraseInDisplay(AParams, False);
end;

function TTyTerminalCore.EraseInDisplayProtected(AParams: TTyTerminalParams): Boolean;
begin
  Result := EraseInDisplay(AParams, True);
end;

function TTyTerminalCore.EraseInLine(AParams: TTyTerminalParams; ARespectProtect: Boolean): Boolean;
var
  buf: TTyTerminalBuffer;
begin                                                                        { :1324-1340 }
  buf := Buffer;
  RestrictCursor(Cols);
  case AParams[0] of
    0: EraseInBufferLine(buf.Y, buf.X, Cols, buf.X = 0, ARespectProtect);
    1: EraseInBufferLine(buf.Y, 0, Int64(buf.X) + 1, False, ARespectProtect);
    2: EraseInBufferLine(buf.Y, 0, Cols, True, ARespectProtect);
  end;
  MarkDirty(buf.Y);
  Result := True;
end;

function TTyTerminalCore.EraseInLineCsi(AParams: TTyTerminalParams): Boolean;
begin
  Result := EraseInLine(AParams, False);
end;

function TTyTerminalCore.EraseInLineProtected(AParams: TTyTerminalParams): Boolean;
begin
  Result := EraseInLine(AParams, True);
end;

{ IL, :1350-1373. The count is clamped to the lines from the cursor to the bottom
  margin: by then the region is blank and later passes change nothing. }
function TTyTerminalCore.InsertLines(AParams: TTyTerminalParams): Boolean;
var
  buf: TTyTerminalBuffer;
  p, row, scrollBottomRowsOffset, scrollBottomAbsolute: Integer;
begin
  buf := Buffer;
  RestrictCursor;
  p := P0or1(AParams);
  if (buf.Y > buf.ScrollBottom) or (buf.Y < buf.ScrollTop) then
    Exit(True);
  row := buf.YBase + buf.Y;
  scrollBottomRowsOffset := Rows - 1 - buf.ScrollBottom;
  scrollBottomAbsolute := Rows - 1 + buf.YBase - scrollBottomRowsOffset + 1;
  p := Min(p, buf.ScrollBottom - buf.Y + 1);
  while p > 0 do
  begin
    { blankLine(true): xterm and linux blank with the erase attributes }
    buf.Lines.Splice(scrollBottomAbsolute - 1, 1, []);
    buf.Lines.SpliceOwned(row, 0, buf.GetBlankLine(EraseAttrData));
    Dec(p);
  end;
  MarkRangeDirty(buf.Y, buf.ScrollBottom);
  buf.X := 0;
  Result := True;
end;

{ DL, :1383-1405, clamped as IL }
function TTyTerminalCore.DeleteLines(AParams: TTyTerminalParams): Boolean;
var
  buf: TTyTerminalBuffer;
  p, row, j: Integer;
begin
  buf := Buffer;
  RestrictCursor;
  p := P0or1(AParams);
  if (buf.Y > buf.ScrollBottom) or (buf.Y < buf.ScrollTop) then
    Exit(True);
  row := buf.YBase + buf.Y;
  j := Rows - 1 - buf.ScrollBottom;
  j := Rows - 1 + buf.YBase - j;
  p := Min(p, buf.ScrollBottom - buf.Y + 1);
  while p > 0 do
  begin
    buf.Lines.Splice(row, 1, []);
    buf.Lines.SpliceOwned(j, 0, buf.GetBlankLine(EraseAttrData));
    Dec(p);
  end;
  MarkRangeDirty(buf.Y, buf.ScrollBottom);
  buf.X := 0;
  Result := True;
end;

function TTyTerminalCore.InsertChars(AParams: TTyTerminalParams): Boolean;   { :1412-1425 }
var
  line: TTyTerminalLine;
begin
  RestrictCursor;
  line := Buffer.Lines.Get(Buffer.YBase + Buffer.Y);
  if line <> nil then
  begin
    line.InsertCells(Buffer.X, P0or1(AParams), Buffer.GetNullCell(EraseAttrData));
    MarkDirty(Buffer.Y);
  end;
  Result := True;
end;

function TTyTerminalCore.DeleteChars(AParams: TTyTerminalParams): Boolean;   { :1432-1445 }
var
  line: TTyTerminalLine;
begin
  RestrictCursor;
  line := Buffer.Lines.Get(Buffer.YBase + Buffer.Y);
  if line <> nil then
  begin
    line.DeleteCells(Buffer.X, P0or1(AParams), Buffer.GetNullCell(EraseAttrData));
    MarkDirty(Buffer.Y);
  end;
  Result := True;
end;

{ SU, :1464-1474, clamped to the region height (unit header) }
function TTyTerminalCore.ScrollUp(AParams: TTyTerminalParams): Boolean;
var
  buf: TTyTerminalBuffer;
  p: Integer;
begin
  buf := Buffer;
  p := Min(P0or1(AParams), Max(buf.ScrollBottom - buf.ScrollTop + 1, 0));
  while p > 0 do
  begin
    buf.Lines.Splice(buf.YBase + buf.ScrollTop, 1, []);
    buf.Lines.SpliceOwned(buf.YBase + buf.ScrollBottom, 0, buf.GetBlankLine(EraseAttrData));
    Dec(p);
  end;
  MarkRangeDirty(buf.ScrollTop, buf.ScrollBottom);
  Result := True;
end;

{ SD, :1480-1490: the new lines take the DEFAULT attributes, not the erase ones }
function TTyTerminalCore.ScrollDown(AParams: TTyTerminalParams): Boolean;
var
  buf: TTyTerminalBuffer;
  p: Integer;
begin
  buf := Buffer;
  p := Min(P0or1(AParams), Max(buf.ScrollBottom - buf.ScrollTop + 1, 0));
  while p > 0 do
  begin
    buf.Lines.Splice(buf.YBase + buf.ScrollBottom, 1, []);
    buf.Lines.SpliceOwned(buf.YBase + buf.ScrollTop, 0, buf.GetBlankLine(TyTermDefaultAttr));
    Dec(p);
  end;
  MarkRangeDirty(buf.ScrollTop, buf.ScrollBottom);
  Result := True;
end;

function TTyTerminalCore.ScrollLeft(AParams: TTyTerminalParams): Boolean;   { :1510-1523 }
var
  buf: TTyTerminalBuffer;
  p, y: Integer;
  line: TTyTerminalLine;
begin
  buf := Buffer;
  if (buf.Y > buf.ScrollBottom) or (buf.Y < buf.ScrollTop) then
    Exit(True);
  p := P0or1(AParams);
  for y := buf.ScrollTop to buf.ScrollBottom do
  begin
    line := buf.Lines.Get(buf.YBase + y);
    if line = nil then Continue;
    line.DeleteCells(0, p, buf.GetNullCell(EraseAttrData));
    line.IsWrapped := False;
  end;
  MarkRangeDirty(buf.ScrollTop, buf.ScrollBottom);
  Result := True;
end;

function TTyTerminalCore.ScrollRight(AParams: TTyTerminalParams): Boolean;  { :1543-1556 }
var
  buf: TTyTerminalBuffer;
  p, y: Integer;
  line: TTyTerminalLine;
begin
  buf := Buffer;
  if (buf.Y > buf.ScrollBottom) or (buf.Y < buf.ScrollTop) then
    Exit(True);
  p := P0or1(AParams);
  for y := buf.ScrollTop to buf.ScrollBottom do
  begin
    line := buf.Lines.Get(buf.YBase + y);
    if line = nil then Continue;
    line.InsertCells(0, p, buf.GetNullCell(EraseAttrData));
    line.IsWrapped := False;
  end;
  MarkRangeDirty(buf.ScrollTop, buf.ScrollBottom);
  Result := True;
end;

function TTyTerminalCore.InsertColumns(AParams: TTyTerminalParams): Boolean;   { :1564-1577 }
var
  buf: TTyTerminalBuffer;
  p, y: Integer;
  line: TTyTerminalLine;
begin
  buf := Buffer;
  if (buf.Y > buf.ScrollBottom) or (buf.Y < buf.ScrollTop) then
    Exit(True);
  p := P0or1(AParams);
  for y := buf.ScrollTop to buf.ScrollBottom do
  begin
    line := buf.Lines.Get(buf.YBase + y);
    if line = nil then Continue;
    line.InsertCells(buf.X, p, buf.GetNullCell(EraseAttrData));
    line.IsWrapped := False;
  end;
  MarkRangeDirty(buf.ScrollTop, buf.ScrollBottom);
  Result := True;
end;

function TTyTerminalCore.DeleteColumns(AParams: TTyTerminalParams): Boolean;   { :1585-1598 }
var
  buf: TTyTerminalBuffer;
  p, y: Integer;
  line: TTyTerminalLine;
begin
  buf := Buffer;
  if (buf.Y > buf.ScrollBottom) or (buf.Y < buf.ScrollTop) then
    Exit(True);
  p := P0or1(AParams);
  for y := buf.ScrollTop to buf.ScrollBottom do
  begin
    line := buf.Lines.Get(buf.YBase + y);
    if line = nil then Continue;
    line.DeleteCells(buf.X, p, buf.GetNullCell(EraseAttrData));
    line.IsWrapped := False;
  end;
  MarkRangeDirty(buf.ScrollTop, buf.ScrollBottom);
  Result := True;
end;

{ ECH, :1614-1626: x + n in Int64, so a 20-digit count erases to the end }
function TTyTerminalCore.EraseChars(AParams: TTyTerminalParams): Boolean;
var
  line: TTyTerminalLine;
begin
  RestrictCursor;
  line := Buffer.Lines.Get(Buffer.YBase + Buffer.Y);
  if line <> nil then
  begin
    line.ReplaceCells(Buffer.X, Int64(Buffer.X) + P0or1(AParams), Buffer.GetNullCell(EraseAttrData));
    MarkDirty(Buffer.Y);
  end;
  Result := True;
end;

{ REP, :1654-1678: the text of the cell before the cursor, printed again. Upstream
  builds text x count code points and prints them in one call; this prints the text
  count times in one call (DoPrint), fast-forwarded (unit header). }
function TTyTerminalCore.RepeatPrecedingCharacter(AParams: TTyTerminalParams): Boolean;
var
  joinState: TTyUnicodeCharProps;
  count, chWidth, x, i: Integer;
  row: TTyTerminalLine;
  text: string;
  cps: TIntegerDynArray;
  data: array of Cardinal;
begin
  joinState := FParser.PrecedingJoinState;
  if joinState = 0 then
    Exit(True);
  count := P0or1(AParams);
  chWidth := TyUnicodePropsWidth(joinState);
  x := Buffer.X - chWidth;
  row := Buffer.Lines.Get(Buffer.YBase + Buffer.Y);
  if row = nil then
    Exit(True);
  { no reference to the cell's text stays behind: appending to that same cell
    while printing then grows it in place }
  text := row.GetChars(x);
  cps := TyTermUtf8Codepoints(text);
  text := '';
  data := nil;
  SetLength(data, Length(cps));
  for i := 0 to High(cps) do
    data[i] := Cardinal(cps[i]);
  DoPrint(data, 0, Length(data), count);
  Result := True;
end;

{ DECALN, :3470-3494 }
function TTyTerminalCore.ScreenAlignmentPattern: Boolean;
var
  cell: TTyTerminalCellData;
  yOffset: Integer;
  line: TTyTerminalLine;
begin
  cell.Content := (Cardinal(1) shl TyTermContentWidthShift) or Ord('E');
  cell.Fg := FCurAttr.Fg;
  cell.Bg := FCurAttr.Bg;
  cell.Ext.RawExt := 0;                  { a new CellData's own, empty, extended attributes }
  cell.Ext.UrlId := 0;
  cell.Combined := '';
  SetCursor(0, 0);
  for yOffset := 0 to Rows - 1 do
  begin
    line := Buffer.Lines.Get(Buffer.YBase + Buffer.Y + yOffset);
    if line <> nil then
    begin
      line.Fill(cell);
      line.IsWrapped := False;
    end;
  end;
  MarkAllDirty;
  SetCursor(0, 0);
  Result := True;
end;

{ IND, :3366-3378 }
function TTyTerminalCore.Index: Boolean;
var
  buf: TTyTerminalBuffer;
begin
  buf := Buffer;
  RestrictCursor;
  buf.Y := buf.Y + 1;
  if buf.Y = buf.ScrollBottom + 1 then
  begin
    buf.Y := buf.Y - 1;
    FBufferService.Scroll(EraseAttrData);
  end
  else if buf.Y >= Rows then
    buf.Y := Rows - 1;
  RestrictCursor;
  Result := True;
end;

function TTyTerminalCore.NextLine: Boolean;                                  { :3287-3291 }
begin
  Buffer.X := 0;
  Index;
  Result := True;
end;

function TTyTerminalCore.TabSet: Boolean;                                    { :3389-3392 }
begin
  Buffer.SetTab(Buffer.X, True);
  Result := True;
end;

{ RI, :3400-3419 }
function TTyTerminalCore.ReverseIndex: Boolean;
var
  buf: TTyTerminalBuffer;
  h: Integer;
begin
  buf := Buffer;
  RestrictCursor;
  if buf.Y = buf.ScrollTop then
  begin
    { at the top margin: the region moves down, a blank line comes in on top }
    h := buf.ScrollBottom - buf.ScrollTop;
    buf.Lines.ShiftElements(buf.YBase + buf.Y, h, 1);
    buf.Lines.SetItemOwned(buf.YBase + buf.Y, buf.GetBlankLine(EraseAttrData));
    MarkRangeDirty(buf.ScrollTop, buf.ScrollBottom);
  end
  else
  begin
    buf.Y := buf.Y - 1;
    RestrictCursor;
  end;
  Result := True;
end;

{ ==== InputHandler: modes, SGR, replies, cursor store, charsets, OSC, resets ======================= }

{ SM, :1797-1810 (20 = LNM changes the convertEol option) }
function TTyTerminalCore.SetModeCsi(AParams: TTyTerminalParams): Boolean;
var
  before: TTyTerminalModes;
  i: Integer;
begin
  before := GetModes;
  for i := 0 to AParams.Length - 1 do
    case AParams[i] of
      4: FInsertMode := True;
      20: FOptions.ConvertEol := True;
    end;
  ModesChangedSince(before);
  Result := True;
end;

{ RM, :2083-2096 }
function TTyTerminalCore.ResetModeCsi(AParams: TTyTerminalParams): Boolean;
var
  before: TTyTerminalModes;
  i: Integer;
begin
  before := GetModes;
  for i := 0 to AParams.Length - 1 do
    case AParams[i] of
      4: FInsertMode := False;
      20: FOptions.ConvertEol := False;
    end;
  ModesChangedSince(before);
  Result := True;
end;

{ DECSET, :1932-2071 }
function TTyTerminalCore.SetModePrivate(AParams: TTyTerminalParams): Boolean;
var
  before: TTyTerminalModes;
  i, p: Integer;
begin
  before := GetModes;
  for i := 0 to AParams.Length - 1 do
  begin
    p := AParams[i];
    case p of
      1: FApplicationCursorKeys := True;
      2:
        begin
          { set VT100 mode: every G back to the default }
          SetGCharset(0, 0);
          SetGCharset(1, 0);
          SetGCharset(2, 0);
          SetGCharset(3, 0);
        end;
      3:
        if twoSetWinLines in FWindowOptions then
        begin
          FBufferService.Resize(132, Rows);   { fires OnResize }
          DoReset;                       { onRequestReset -> headless reset }
        end;
      6:
        begin
          FOrigin := True;
          SetCursor(0, 0);
        end;
      7: FWraparound := True;
      12:
        if FOptions.AllowSetCursorBlink then
          FOptions.CursorBlink := True;
      45: FReverseWraparound := True;
      66: FApplicationKeypad := True;
      9: SetMouseProtocol(tmpX10);       { no release, no motion, no wheel, no modifiers }
      1000: SetMouseProtocol(tmpVT200);  { no motion }
      1002: SetMouseProtocol(tmpDrag);
      1003: SetMouseProtocol(tmpAny);
      1004:
        begin
          FSendFocus := True;
          ReportFocusNow;                { onRequestSendFocus: the browser reports at once }
        end;
      1005: ;                            { utf8 mouse, removed upstream (#2507) }
      1006: FMouseEncoding := tmeSgr;
      1015: ;                            { urxvt mouse, removed upstream (#2507) }
      1016: FMouseEncoding := tmeSgrPixels;
      25: FIsCursorHidden := False;
      1048: SaveCursor;
      47, 1047, 1049:
        begin
          if p = 1049 then
            SaveCursor;
          { kitty: save the main screen's flags, take the alt screen's }
          if tveKittyKeyboard in FVtExtensions then
          begin
            FKittyMainFlags := FKittyFlags;
            FKittyFlags := FKittyAltFlags;
          end;
          Buffers.ActivateAltBuffer(EraseAttrData);
          FIsCursorInitialized := True;
          RefreshAll;
        end;
      2004: FBracketedPasteMode := True;
      2026: FSynchronizedOutput := True;
      2031:
        if tveColorSchemeQuery in FVtExtensions then
          FColorSchemeUpdates := True;
      9001:
        if tveWin32InputMode in FVtExtensions then
          FWin32InputMode := True;
    end;
  end;
  ModesChangedSince(before);
  Result := True;
end;

{ DECRST, :2198-2317 }
function TTyTerminalCore.ResetModePrivate(AParams: TTyTerminalParams): Boolean;
var
  before: TTyTerminalModes;
  i, p: Integer;
begin
  before := GetModes;
  for i := 0 to AParams.Length - 1 do
  begin
    p := AParams[i];
    case p of
      1: FApplicationCursorKeys := False;
      3:
        if twoSetWinLines in FWindowOptions then
        begin
          FBufferService.Resize(80, Rows);    { fires OnResize }
          DoReset;
        end;
      6:
        begin
          FOrigin := False;
          SetCursor(0, 0);
        end;
      7: FWraparound := False;
      12:
        if FOptions.AllowSetCursorBlink then
          FOptions.CursorBlink := False;
      45: FReverseWraparound := False;
      66: FApplicationKeypad := False;
      9, 1000, 1002, 1003: SetMouseProtocol(tmpNone);
      1004: FSendFocus := False;
      1005: ;
      1006: FMouseEncoding := tmeDefault;
      1015: ;
      1016: FMouseEncoding := tmeDefault;
      25: FIsCursorHidden := True;
      1048: RestoreCursor;
      47, 1047, 1049:
        begin
          { kitty: save the alt screen's flags, take the main screen's }
          if tveKittyKeyboard in FVtExtensions then
          begin
            FKittyAltFlags := FKittyFlags;
            FKittyFlags := FKittyMainFlags;
          end;
          Buffers.ActivateNormalBuffer;
          if p = 1049 then
            RestoreCursor;
          FIsCursorInitialized := True;
          RefreshAll;
        end;
      2004: FBracketedPasteMode := False;
      2026:
        begin
          FSynchronizedOutput := False;
          RefreshAll;
        end;
      2031:
        if tveColorSchemeQuery in FVtExtensions then
          FColorSchemeUpdates := False;
      9001:
        if tveWin32InputMode in FVtExtensions then
          FWin32InputMode := False;
    end;
  end;
  ModesChangedSince(before);
  Result := True;
end;

{ DECRQM, :2336-2396; the reply is DECRPM }
function TTyTerminalCore.RequestMode(AParams: TTyTerminalParams; AAnsi: Boolean): Boolean;
const
  NotRecognized = 0;
  VSet = 1;
  VReset = 2;
  PermanentlySet = 3;
  PermanentlyReset = 4;
var
  p, v: Integer;

  function B2V(AValue: Boolean): Integer;
  begin
    if AValue then Result := VSet else Result := VReset;
  end;

begin
  p := AParams[0];
  if AAnsi then
    case p of
      2: v := PermanentlyReset;
      4: v := B2V(FInsertMode);
      12: v := PermanentlySet;
      20: v := B2V(FOptions.ConvertEol);
    else
      v := NotRecognized;
    end
  else
    case p of
      1: v := B2V(FApplicationCursorKeys);
      3:
        if twoSetWinLines in FWindowOptions then
        begin
          if Cols = 80 then v := VReset
          else if Cols = 132 then v := VSet
          else v := NotRecognized;
        end
        else
          v := NotRecognized;
      6: v := B2V(FOrigin);
      7: v := B2V(FWraparound);
      8: v := PermanentlySet;
      9: v := B2V(FMouseProtocol = tmpX10);
      12: v := B2V(FOptions.CursorBlink);
      25: v := B2V(not FIsCursorHidden);
      45: v := B2V(FReverseWraparound);
      66: v := B2V(FApplicationKeypad);
      67: v := PermanentlyReset;
      1000: v := B2V(FMouseProtocol = tmpVT200);
      1002: v := B2V(FMouseProtocol = tmpDrag);
      1003: v := B2V(FMouseProtocol = tmpAny);
      1004: v := B2V(FSendFocus);
      1005: v := PermanentlyReset;
      1006: v := B2V(FMouseEncoding = tmeSgr);
      1015: v := PermanentlyReset;
      1016: v := B2V(FMouseEncoding = tmeSgrPixels);
      1048: v := VSet;                    { xterm always answers SET }
      47, 1047, 1049: v := B2V(Buffers.IsAlt);
      2004: v := B2V(FBracketedPasteMode);
      2026: v := B2V(FSynchronizedOutput);
      9001:
        if tveWin32InputMode in FVtExtensions then
          v := B2V(FWin32InputMode)
        else
          v := NotRecognized;
    else
      v := NotRecognized;
    end;
  if AAnsi then
    TriggerDataEvent(#27'[' + IntToStr(p) + ';' + IntToStr(v) + '$y')
  else
    TriggerDataEvent(#27'[?' + IntToStr(p) + ';' + IntToStr(v) + '$y');
  Result := True;
end;

function TTyTerminalCore.RequestModeAnsi(AParams: TTyTerminalParams): Boolean;
begin
  Result := RequestMode(AParams, True);
end;

function TTyTerminalCore.RequestModePrivate(AParams: TTyTerminalParams): Boolean;
begin
  Result := RequestMode(AParams, False);
end;

{ _updateAttrColor, :2401-2411 }
function TTyTerminalCore.UpdateAttrColor(AColor: Cardinal; AMode, AC1, AC2, AC3: Integer): Cardinal;
begin
  if AMode = 2 then
  begin
    AColor := AColor or TyTermAttrCmRgb;
    AColor := AColor and not Cardinal(TyTermAttrRgbMask);
    AColor := AColor or ((Cardinal(AC1 and 255) shl 16) or (Cardinal(AC2 and 255) shl 8) or Cardinal(AC3 and 255));
  end
  else if AMode = 5 then
  begin
    AColor := AColor and not Cardinal(TyTermAttrCmMask or TyTermAttrRgbMask);
    AColor := AColor or TyTermAttrCmP256 or Cardinal(AC1 and $FF);
  end;
  Result := AColor;
end;

{ _extractColor, :2416-2475, statement for statement. accu is
    [target, CM, colour space, v1, v2, v3]  (RGB: r g b; 256: v1 only)
  and may grow by one slot the way a JavaScript array does when a sub-parameter
  lands one past its end. Returns how many params were used after the first. }
function TTyTerminalCore.ExtractColor(AParams: TTyTerminalParams; APos: Integer;
  var AAttr: TTyTerminalAttrData): Integer;
var
  accu: array[0..7] of Integer;
  accuLen, cSpace, advance, i, subCount: Integer;

  procedure Put(AIdx, AValue: Integer);
  begin
    if AIdx >= accuLen then
      accuLen := AIdx + 1;
    accu[AIdx] := AValue;
  end;

begin
  accu[0] := 0; accu[1] := 0; accu[2] := -1; accu[3] := 0; accu[4] := 0; accu[5] := 0;
  accu[6] := 0; accu[7] := 0;
  accuLen := 6;
  cSpace := 0;                           { alignment for the missing colour-space slot }
  advance := 0;
  repeat
    Put(advance + cSpace, AParams[APos + advance]);
    if AParams.HasSubParams(APos + advance) then
    begin
      subCount := AParams.SubParamCount(APos + advance);
      i := 0;
      repeat
        if accu[1] = 5 then
          cSpace := 1;
        Put(advance + i + 1 + cSpace, AParams.SubParam(APos + advance, i));
        Inc(i);
      until not ((i < subCount) and (i + advance + 1 + cSpace < accuLen));
      Break;
    end;
    { semicolons: stop as soon as the colour mode is decided }
    if ((accu[1] = 5) and (advance + cSpace >= 2)) or ((accu[1] = 2) and (advance + cSpace >= 5)) then
      Break;
    { semicolon mode has no colour-space slot }
    if accu[1] <> 0 then
      cSpace := 1;
    Inc(advance);
  until not ((advance + APos < AParams.Length) and (advance + cSpace < accuLen));
  for i := 2 to accuLen - 1 do
    if accu[i] = -1 then
      accu[i] := 0;
  case accu[0] of
    38: AAttr.Fg := UpdateAttrColor(AAttr.Fg, accu[1], accu[3], accu[4], accu[5]);
    48: AAttr.Bg := UpdateAttrColor(AAttr.Bg, accu[1], accu[3], accu[4], accu[5]);
    58: AAttr.Extended.SetUnderlineColor(Integer(UpdateAttrColor(AAttr.Extended.UnderlineColor,
          accu[1], accu[3], accu[4], accu[5])));
  end;
  Result := advance;
end;

{ _processUnderline, :2485-2500 (upstream clones the extended attributes first; they
  are a value here) }
procedure TTyTerminalCore.ProcessUnderline(AStyle: Integer; var AAttr: TTyTerminalAttrData);
begin
  if (AStyle = -1) or (AStyle > 5) then
    AStyle := 1;                         { default: single }
  AAttr.Extended.SetUnderlineStyle(AStyle);
  AAttr.Fg := AAttr.Fg or TyTermFgUnderline;
  if AStyle = 0 then
    AAttr.Fg := AAttr.Fg and not Cardinal(TyTermFgUnderline);
  AAttr.UpdateExtended;
end;

{ _processSGR0, :2502-2511: the link (urlId) survives }
procedure TTyTerminalCore.ProcessSGR0(var AAttr: TTyTerminalAttrData);
begin
  AAttr.Fg := TyTermDefaultAttr.Fg;
  AAttr.Bg := TyTermDefaultAttr.Bg;
  AAttr.Extended.SetUnderlineStyle(Ord(tusNone));
  AAttr.Extended.SetUnderlineColor(Integer(AAttr.Extended.UnderlineColor
    and not Cardinal(TyTermAttrCmMask or TyTermAttrRgbMask)));
  AAttr.UpdateExtended;
end;

{ SGR, :2600-2725 }
function TTyTerminalCore.CharAttributes(AParams: TTyTerminalParams): Boolean;
var
  i, l, p: Integer;
begin
  { a single SGR 0, the common case }
  if (AParams.Length = 1) and (AParams[0] = 0) then
  begin
    ProcessSGR0(FCurAttr);
    Exit(True);
  end;
  l := AParams.Length;
  i := 0;
  while i < l do
  begin
    p := AParams[i];
    if (p >= 30) and (p <= 37) then
    begin
      FCurAttr.Fg := FCurAttr.Fg and not Cardinal(TyTermAttrCmMask or TyTermAttrRgbMask);
      FCurAttr.Fg := FCurAttr.Fg or TyTermAttrCmP16 or Cardinal(p - 30);
    end
    else if (p >= 40) and (p <= 47) then
    begin
      FCurAttr.Bg := FCurAttr.Bg and not Cardinal(TyTermAttrCmMask or TyTermAttrRgbMask);
      FCurAttr.Bg := FCurAttr.Bg or TyTermAttrCmP16 or Cardinal(p - 40);
    end
    else if (p >= 90) and (p <= 97) then
    begin
      FCurAttr.Fg := FCurAttr.Fg and not Cardinal(TyTermAttrCmMask or TyTermAttrRgbMask);
      FCurAttr.Fg := FCurAttr.Fg or TyTermAttrCmP16 or Cardinal(p - 90) or 8;
    end
    else if (p >= 100) and (p <= 107) then
    begin
      FCurAttr.Bg := FCurAttr.Bg and not Cardinal(TyTermAttrCmMask or TyTermAttrRgbMask);
      FCurAttr.Bg := FCurAttr.Bg or TyTermAttrCmP16 or Cardinal(p - 100) or 8;
    end
    else if p = 0 then
      ProcessSGR0(FCurAttr)
    else if p = 1 then
      FCurAttr.Fg := FCurAttr.Fg or TyTermFgBold
    else if p = 3 then
      FCurAttr.Bg := FCurAttr.Bg or TyTermBgItalic
    else if p = 4 then
    begin
      FCurAttr.Fg := FCurAttr.Fg or TyTermFgUnderline;
      if AParams.HasSubParams(i) then
        ProcessUnderline(AParams.SubParam(i, 0), FCurAttr)
      else
        ProcessUnderline(Ord(tusSingle), FCurAttr);
    end
    else if p = 5 then
      FCurAttr.Fg := FCurAttr.Fg or TyTermFgBlink
    else if p = 7 then
      FCurAttr.Fg := FCurAttr.Fg or TyTermFgInverse
    else if p = 8 then
      FCurAttr.Fg := FCurAttr.Fg or TyTermFgInvisible
    else if p = 9 then
      FCurAttr.Fg := FCurAttr.Fg or TyTermFgStrikethrough
    else if p = 2 then
      FCurAttr.Bg := FCurAttr.Bg or TyTermBgDim
    else if p = 21 then
      ProcessUnderline(Ord(tusDouble), FCurAttr)
    else if p = 22 then
    begin
      FCurAttr.Fg := FCurAttr.Fg and not Cardinal(TyTermFgBold);
      FCurAttr.Bg := FCurAttr.Bg and not Cardinal(TyTermBgDim);
    end
    else if p = 23 then
      FCurAttr.Bg := FCurAttr.Bg and not Cardinal(TyTermBgItalic)
    else if p = 24 then
    begin
      FCurAttr.Fg := FCurAttr.Fg and not Cardinal(TyTermFgUnderline);
      ProcessUnderline(Ord(tusNone), FCurAttr);
    end
    else if p = 25 then
      FCurAttr.Fg := FCurAttr.Fg and not Cardinal(TyTermFgBlink)
    else if p = 27 then
      FCurAttr.Fg := FCurAttr.Fg and not Cardinal(TyTermFgInverse)
    else if p = 28 then
      FCurAttr.Fg := FCurAttr.Fg and not Cardinal(TyTermFgInvisible)
    else if p = 29 then
      FCurAttr.Fg := FCurAttr.Fg and not Cardinal(TyTermFgStrikethrough)
    else if p = 39 then
    begin
      FCurAttr.Fg := FCurAttr.Fg and not Cardinal(TyTermAttrCmMask or TyTermAttrRgbMask);
      FCurAttr.Fg := FCurAttr.Fg or (TyTermDefaultAttr.Fg and TyTermAttrRgbMask);
    end
    else if p = 49 then
    begin
      FCurAttr.Bg := FCurAttr.Bg and not Cardinal(TyTermAttrCmMask or TyTermAttrRgbMask);
      FCurAttr.Bg := FCurAttr.Bg or (TyTermDefaultAttr.Bg and TyTermAttrRgbMask);
    end
    else if (p = 38) or (p = 48) or (p = 58) then
      Inc(i, ExtractColor(AParams, i, FCurAttr))
    else if p = 53 then
      FCurAttr.Bg := FCurAttr.Bg or TyTermBgOverline
    else if p = 55 then
      FCurAttr.Bg := FCurAttr.Bg and not Cardinal(TyTermBgOverline)
    else if (p = 221) and (tveKittySgrBoldFaint in FVtExtensions) then
      FCurAttr.Fg := FCurAttr.Fg and not Cardinal(TyTermFgBold)       { not bold (kitty) }
    else if (p = 222) and (tveKittySgrBoldFaint in FVtExtensions) then
      FCurAttr.Bg := FCurAttr.Bg and not Cardinal(TyTermBgDim)        { not faint (kitty) }
    else if p = 59 then
    begin
      { the colour becomes -1 & 0x3FFFFFF, not "default" (upstream's answer) }
      FCurAttr.Extended.SetUnderlineColor(-1);
      FCurAttr.UpdateExtended;
    end;
    Inc(i);
  end;
  Result := True;
end;

{ DA1, :1706-1717; termName is always 'xterm' here, so the rxvt / linux / screen
  branches of _is() cannot be reached and are not ported }
function TTyTerminalCore.SendDeviceAttributesPrimary(AParams: TTyTerminalParams): Boolean;
begin
  if AParams[0] > 0 then
    Exit(True);
  TriggerDataEvent(#27'[?1;2c');
  Result := True;
end;

{ DA2, :1742-1762 (termName 'xterm') }
function TTyTerminalCore.SendDeviceAttributesSecondary(AParams: TTyTerminalParams): Boolean;
begin
  if AParams[0] > 0 then
    Exit(True);
  TriggerDataEvent(#27'[>0;276;0c');
  Result := True;
end;

{ XTVERSION, :1771-1777: we report ourselves, not xterm.js (spec 17.2 #11) }
function TTyTerminalCore.SendXtVersion(AParams: TTyTerminalParams): Boolean;
begin
  if AParams[0] > 0 then
    Exit(True);
  TriggerDataEvent(#27'P>|TyControls(' + TyTermLibraryVersion + ')'#27'\');
  Result := True;
end;

{ DSR, :2743-2757 }
function TTyTerminalCore.DeviceStatus(AParams: TTyTerminalParams): Boolean;
begin
  case AParams[0] of
    5: TriggerDataEvent(#27'[0n');
    6: TriggerDataEvent(#27'[' + IntToStr(Buffer.Y + 1) + ';' + IntToStr(Buffer.X + 1) + 'R');
  end;
  Result := True;
end;

{ DECDSR, :2760-2795 }
function TTyTerminalCore.DeviceStatusPrivate(AParams: TTyTerminalParams): Boolean;
begin
  case AParams[0] of
    6: TriggerDataEvent(#27'[?' + IntToStr(Buffer.Y + 1) + ';' + IntToStr(Buffer.X + 1) + 'R');
    996:
      if tveColorSchemeQuery in FVtExtensions then
        ReportColorScheme;               { onRequestColorSchemeQuery }
  end;
  Result := True;
end;

{ DECSTR, :2816-2835 }
function TTyTerminalCore.SoftReset(AParams: TTyTerminalParams): Boolean;
var
  before: TTyTerminalModes;
  buf: TTyTerminalBuffer;
begin
  before := GetModes;
  buf := Buffer;
  FIsCursorHidden := False;
  buf.ScrollTop := 0;
  buf.ScrollBottom := Rows - 1;
  FCurAttr := TyTermDefaultAttr;
  CoreServiceReset;
  CharsetReset;
  { reset DECSC data -- savedY becomes ybase, as upstream writes it }
  buf.SavedX := 0;
  buf.SavedY := buf.YBase;
  buf.SavedAttr.Fg := FCurAttr.Fg;
  buf.SavedAttr.Bg := FCurAttr.Bg;
  buf.SavedCharset := FCharset;
  FOrigin := False;
  ModesChangedSince(before);
  Result := True;
end;

{ DECSCUSR, :2840-2863 }
function TTyTerminalCore.SetCursorStyleCsi(AParams: TTyTerminalParams): Boolean;
var
  before: TTyTerminalModes;
  param: Integer;
begin
  before := GetModes;
  if AParams.Length = 0 then
    param := 1
  else
    param := AParams[0];
  if param = 0 then
  begin
    FCursorStyleRequest := tcrDefault;
    FCursorBlinkRequest := tbrDefault;
  end
  else
  begin
    case param of
      1, 2: FCursorStyleRequest := tcrBlock;
      3, 4: FCursorStyleRequest := tcrUnderline;
      5, 6: FCursorStyleRequest := tcrBar;
    end;
    if param mod 2 = 1 then
      FCursorBlinkRequest := tbrOn
    else
      FCursorBlinkRequest := tbrOff;
  end;
  ModesChangedSince(before);
  Result := True;
end;

{ DECSTBM, :2890-2905 }
function TTyTerminalCore.SetScrollRegion(AParams: TTyTerminalParams): Boolean;
var
  top, bottom: Integer;
begin
  top := P0or1(AParams);
  if AParams.Length < 2 then
    bottom := Rows
  else
  begin
    bottom := AParams[1];
    if (bottom > Rows) or (bottom = 0) then
      bottom := Rows;
  end;
  if bottom > top then
  begin
    Buffer.ScrollTop := top - 1;
    Buffer.ScrollBottom := bottom - 1;
    SetCursor(0, 0);
  end;
  Result := True;
end;

{ paramToWindowOption, :52-80 }
function ParamToWindowOption(n: Integer; const AOpts: TTyTerminalWindowOptions): Boolean;
begin
  if n > 24 then
    Exit(twoSetWinLines in AOpts);
  case n of
    1: Result := twoRestoreWin in AOpts;
    2: Result := twoMinimizeWin in AOpts;
    3: Result := twoSetWinPosition in AOpts;
    4: Result := twoSetWinSizePixels in AOpts;
    5: Result := twoRaiseWin in AOpts;
    6: Result := twoLowerWin in AOpts;
    7: Result := twoRefreshWin in AOpts;
    8: Result := twoSetWinSizeChars in AOpts;
    9: Result := twoMaximizeWin in AOpts;
    10: Result := twoFullscreenWin in AOpts;
    11: Result := twoGetWinState in AOpts;
    13: Result := twoGetWinPosition in AOpts;
    14: Result := twoGetWinSizePixels in AOpts;
    15: Result := twoGetScreenSizePixels in AOpts;
    16: Result := twoGetCellSizePixels in AOpts;
    18: Result := twoGetWinSizeChars in AOpts;
    19: Result := twoGetScreenSizeChars in AOpts;
    20: Result := twoGetIconTitle in AOpts;
    21: Result := twoGetWinTitle in AOpts;
    22: Result := twoPushTitle in AOpts;
    23: Result := twoPopTitle in AOpts;
    24: Result := twoSetWinLines in AOpts;
  else
    Result := False;
  end;
end;

procedure PushLimited(var AStack: TStringDynArray; const AValue: string);
var
  i: Integer;
begin
  SetLength(AStack, Length(AStack) + 1);
  AStack[High(AStack)] := AValue;
  if Length(AStack) > TyTermStackLimit then
  begin
    for i := 0 to High(AStack) - 1 do
      AStack[i] := AStack[i + 1];
    SetLength(AStack, Length(AStack) - 1);
  end;
end;

function PopString(var AStack: TStringDynArray): string;
begin
  Result := AStack[High(AStack)];
  SetLength(AStack, Length(AStack) - 1);
end;

{ XTWINOPS, :2936-2983 -- all off by default; 14 and 16 need pixels, which the
  control answers through OnWindowOptionsReport }
function TTyTerminalCore.WindowOptionsCsi(AParams: TTyTerminalParams): Boolean;
var
  second: Integer;
begin
  if not ParamToWindowOption(AParams[0], FWindowOptions) then
    Exit(True);
  if AParams.Length > 1 then
    second := AParams[1]
  else
    second := 0;
  case AParams[0] of
    14:
      if (second <> 2) and Assigned(FOnWindowOptionsReport) then
        FOnWindowOptionsReport(Self, twrWinSizePixels);
    16:
      if Assigned(FOnWindowOptionsReport) then
        FOnWindowOptionsReport(Self, twrCellSizePixels);
    18: TriggerDataEvent(#27'[8;' + IntToStr(Rows) + ';' + IntToStr(Cols) + 't');
    22:
      begin
        if (second = 0) or (second = 2) then
          PushLimited(FWindowTitleStack, FWindowTitle);
        if (second = 0) or (second = 1) then
          PushLimited(FIconNameStack, FIconName);
      end;
    23:
      begin
        if ((second = 0) or (second = 2)) and (Length(FWindowTitleStack) > 0) then
          SetTitle(PopString(FWindowTitleStack));
        if ((second = 0) or (second = 1)) and (Length(FIconNameStack) > 0) then
          SetIconName(PopString(FIconNameStack));
      end;
  end;
  Result := True;
end;

{ DECSC, :2994-3005 }
function TTyTerminalCore.SaveCursor: Boolean;
var
  buf: TTyTerminalBuffer;
begin
  buf := Buffer;
  buf.SavedX := buf.X;
  buf.SavedY := buf.YBase + buf.Y;
  buf.SavedAttr.Fg := FCurAttr.Fg;
  buf.SavedAttr.Bg := FCurAttr.Bg;
  buf.SavedCharset := FCharset;
  buf.SavedCharsets := Copy(FCharsets);
  buf.SavedGLevel := FGLevel;
  buf.SavedOriginMode := FOrigin;
  buf.SavedWraparoundMode := FWraparound;
  Result := True;
end;

function TTyTerminalCore.SaveCursorCsi(AParams: TTyTerminalParams): Boolean;
begin
  Result := SaveCursor;
end;

{ DECRC, :3015-3029 }
function TTyTerminalCore.RestoreCursor: Boolean;
var
  buf: TTyTerminalBuffer;
  before: TTyTerminalModes;
  i: Integer;
begin
  before := GetModes;
  buf := Buffer;
  buf.X := buf.SavedX;
  buf.Y := Max(buf.SavedY - buf.YBase, 0);
  FCurAttr.Fg := buf.SavedAttr.Fg;
  FCurAttr.Bg := buf.SavedAttr.Bg;
  for i := 0 to High(buf.SavedCharsets) do
    SetGCharset(i, buf.SavedCharsets[i]);
  SetGLevel(buf.SavedGLevel);
  FOrigin := buf.SavedOriginMode;
  FWraparound := buf.SavedWraparoundMode;
  RestrictCursor;
  ModesChangedSince(before);
  Result := True;
end;

function TTyTerminalCore.RestoreCursorCsi(AParams: TTyTerminalParams): Boolean;
begin
  Result := RestoreCursor;
end;

function TTyTerminalCore.KeypadApplicationMode: Boolean;                     { :3301-3305 }
var
  before: TTyTerminalModes;
begin
  before := GetModes;
  FApplicationKeypad := True;
  ModesChangedSince(before);
  Result := True;
end;

function TTyTerminalCore.KeypadNumericMode: Boolean;                         { :3310-3315 }
var
  before: TTyTerminalModes;
begin
  before := GetModes;
  FApplicationKeypad := False;
  ModesChangedSince(before);
  Result := True;
end;

function TTyTerminalCore.SelectDefaultCharset: Boolean;                      { :3323-3327 }
begin
  SetGLevel(0);
  SetGCharset(0, 0);                     { US (default) }
  Result := True;
end;

{ SCS, :3344-3354: ( ) * + - . pick G0..G2/G3; / is accepted and does nothing }
function TTyTerminalCore.SelectCharset(const ACollectAndFlag: string): Boolean;
var
  g, k: Integer;
  cs: TTyTermCharsetId;
begin
  if Length(ACollectAndFlag) <> 2 then
  begin
    SelectDefaultCharset;
    Exit(True);
  end;
  if ACollectAndFlag[1] = '/' then
    Exit(True);
  g := -1;
  for k := 0 to High(GLevelOf) do
    if GLevelOf[k].C = ACollectAndFlag[1] then
      g := GLevelOf[k].G;
  cs := 0;                               { unknown key: DEFAULT_CHARSET }
  for k := 0 to TyTermCharsetKeyCount - 1 do
    if TyTermCharsetKeys[k] = ACollectAndFlag[2] then
    begin
      cs := TyTermCharsetOfKey[k];
      Break;
    end;
  SetGCharset(g, cs);
  Result := True;
end;

function TTyTerminalCore.SetGLevel1: Boolean;
begin
  SetGLevel(1);
  Result := True;
end;

function TTyTerminalCore.SetGLevel2: Boolean;
begin
  SetGLevel(2);
  Result := True;
end;

function TTyTerminalCore.SetGLevel3: Boolean;
begin
  SetGLevel(3);
  Result := True;
end;

{ RIS, :3427-3431: the parser, then the headless reset (still partial) }
function TTyTerminalCore.FullReset: Boolean;
begin
  FParser.Reset;
  DoReset;                               { inside the parse: not the deferring Reset }
  Result := True;
end;

procedure TTyTerminalCore.InputHandlerReset;                                 { :3433-3436 }
begin
  FCurAttr := TyTermDefaultAttr;
  FEraseAttr := TyTermDefaultAttr;
end;

{ DECRQSS, :3519-3537 }
function TTyTerminalCore.RequestStatusString(const AData: string; AParams: TTyTerminalParams): Boolean;

  procedure F(const S: string);
  begin
    TriggerDataEvent(#27 + S + #27'\');
  end;

const
  Styles: array[TTyTermCursorStyleOption] of Integer = (2, 4, 6);   { block underline bar }
var
  b: Integer;
begin
  Result := True;
  if AData = '"q' then
  begin
    if FCurAttr.IsProtected then b := 1 else b := 0;
    F('P1$r' + IntToStr(b) + '"q');
  end
  else if AData = '"p' then
    F('P1$r61;1"p')
  else if AData = 'r' then
    F('P1$r' + IntToStr(Buffer.ScrollTop + 1) + ';' + IntToStr(Buffer.ScrollBottom + 1) + 'r')
  else if AData = 'm' then
    F('P1$r0m')                          { upstream: real SGR settings not reported }
  else if AData = ' q' then
  begin
    { the OPTIONS, not DECSCUSR's request }
    b := Styles[FOptions.CursorStyle];
    if FOptions.CursorBlink then
      Dec(b);
    F('P1$r' + IntToStr(b) + ' q');
  end
  else
    F('P0$r');
end;

procedure TTyTerminalCore.SetTitle(const AData: string);                     { :3042-3046 }
begin
  FWindowTitle := AData;
  if Assigned(FOnTitleChange) then
    FOnTitleChange(Self, AData);
end;

{ :3052-3055 -- upstream only stores it; the event is ours (spec 7.6) }
procedure TTyTerminalCore.SetIconName(const AData: string);
begin
  FIconName := AData;
  if Assigned(FOnIconNameChange) then
    FOnIconNameChange(Self, AData);
end;

function TTyTerminalCore.OscTitleAndIcon(const AData: string): Boolean;
begin
  SetTitle(AData);
  SetIconName(AData);
  Result := True;
end;

function TTyTerminalCore.OscIconName(const AData: string): Boolean;
begin
  SetIconName(AData);
  Result := True;
end;

function TTyTerminalCore.OscTitle(const AData: string): Boolean;
begin
  SetTitle(AData);
  Result := True;
end;

{ String.prototype.split(';'): empty pieces kept, '' gives one empty piece }
function SplitOn(const S: string; ASep: Char): TStringDynArray;
var
  i, start, n: Integer;
begin
  Result := nil;
  n := 1;
  for i := 1 to Length(S) do
    if S[i] = ASep then
      Inc(n);
  SetLength(Result, n);
  n := 0;
  start := 1;
  for i := 1 to Length(S) do
    if S[i] = ASep then
    begin
      Result[n] := Copy(S, start, i - start);
      Inc(n);
      start := i + 1;
    end;
  Result[n] := Copy(S, start, MaxInt);
end;

{ /^\d+$/ then parseInt(.., 10) and 0 <= v < 256; the value saturates, so a
  hundred digits cannot overflow into a valid index }
function ColorIndexOf(const S: string; out AIndex: Integer): Boolean;
var
  i: Integer;
  v: Int64;
begin
  AIndex := -1;
  if S = '' then
    Exit(False);
  v := 0;
  for i := 1 to Length(S) do
  begin
    if not (S[i] in ['0'..'9']) then
      Exit(False);
    v := v * 10 + (Ord(S[i]) - Ord('0'));
    if v > 1000 then
      v := 1000;
  end;
  Result := v < 256;
  if Result then
    AIndex := Integer(v);
end;

function RgbOf(const ASpec: string; out ARgb: Cardinal): Boolean;
var
  r, g, b: Integer;
begin
  Result := TyTermParseXColor(ASpec, r, g, b);
  ARgb := (Cardinal(r and 255) shl 16) or (Cardinal(g and 255) shl 8) or Cardinal(b and 255);
end;

{ OSC 4, :3066-3090: index;spec pairs, each a query (?) or a set }
function TTyTerminalCore.OscIndexedColor(const AData: string): Boolean;
var
  slots: TStringDynArray;
  k, idx: Integer;
  rgb: Cardinal;
begin
  slots := SplitOn(AData, ';');
  k := 0;
  while Length(slots) - k > 1 do
  begin
    if ColorIndexOf(slots[k], idx) then
    begin
      if slots[k + 1] = '?' then
        ReportColor(idx)
      else if RgbOf(slots[k + 1], rgb) then
        SetColor(idx, rgb);
    end;
    Inc(k, 2);
  end;
  Result := True;
end;

{ JavaScript's trim(): its whitespace, not FPC's "everything below a space" }
function JsTrim(const S: string): string;
var
  p, e: Integer;
  c: Cardinal;
  b: Byte;
  cps: TIntegerDynArray;
begin
  Result := TyTermJsTrimEnd(S);
  p := 1;
  while p <= Length(Result) do
  begin
    b := Ord(Result[p]);
    if b < $80 then e := 1
    else if b and $E0 = $C0 then e := 2
    else if b and $F0 = $E0 then e := 3
    else e := 4;
    cps := TyTermUtf8Codepoints(Copy(Result, p, e));
    if Length(cps) = 0 then Break;
    c := Cardinal(cps[0]);
    if not TyTermIsJsWhitespace(c) then Break;
    Inc(p, e);
  end;
  Result := Copy(Result, p, MaxInt);
end;

{ OSC 8, :3109-3150. Arguments are split at the first ';' only, so a URI may hold
  more of them (#4944). }
function TTyTerminalCore.OscHyperlink(const AData: string): Boolean;
var
  idx: Integer;
  id, uri: string;
begin
  idx := Pos(';', AData);
  if idx = 0 then
    Exit(True);                          { malformed: handled, nothing done }
  id := JsTrim(Copy(AData, 1, idx - 1));
  uri := Copy(AData, idx + 1, MaxInt);
  if uri <> '' then
    Exit(CreateHyperlink(id, uri));
  if JsTrim(id) <> '' then
    Exit(False);
  Result := FinishHyperlink;
end;

function TTyTerminalCore.CreateHyperlink(const AParams, AUri: string): Boolean;
var
  parts: TStringDynArray;
  k: Integer;
  data: TTyTerminalLinkData;
begin
  { a new link may open without closing the previous one }
  if FCurAttr.Extended.UrlId <> 0 then
    FinishHyperlink;
  parts := SplitOn(AParams, ':');
  data.HasId := False;
  data.Id := '';
  for k := 0 to High(parts) do
    if Copy(parts[k], 1, 3) = 'id=' then
    begin
      data.Id := Copy(parts[k], 4, MaxInt);
      data.HasId := data.Id <> '';       { "id=" alone counts as no id }
      Break;
    end;
  data.Uri := AUri;
  FCurAttr.Extended.UrlId := FLinks.RegisterLink(data);
  FCurAttr.UpdateExtended;
  Result := True;
end;

function TTyTerminalCore.FinishHyperlink: Boolean;
begin
  FCurAttr.Extended.UrlId := 0;
  FCurAttr.UpdateExtended;
  Result := True;
end;

{ OSC 10 / 11 / 12, :3159-3200: a list starting at the given special colour }
procedure TTyTerminalCore.SetOrReportSpecialColor(const AData: string; AOffset: Integer);
var
  slots: TStringDynArray;
  i: Integer;
  rgb: Cardinal;
begin
  slots := SplitOn(AData, ';');
  for i := 0 to High(slots) do
  begin
    if AOffset >= 3 then
      Break;
    if slots[i] = '?' then
      ReportColor(ColorFg + AOffset)
    else if RgbOf(slots[i], rgb) then
      SetColor(ColorFg + AOffset, rgb);
    Inc(AOffset);
  end;
end;

function TTyTerminalCore.OscFgColor(const AData: string): Boolean;
begin
  SetOrReportSpecialColor(AData, 0);
  Result := True;
end;

function TTyTerminalCore.OscBgColor(const AData: string): Boolean;
begin
  SetOrReportSpecialColor(AData, 1);
  Result := True;
end;

function TTyTerminalCore.OscCursorColor(const AData: string): Boolean;
begin
  SetOrReportSpecialColor(AData, 2);
  Result := True;
end;

{ OSC 104, :3212-3236: no data restores the whole palette }
function TTyTerminalCore.OscRestoreIndexedColor(const AData: string): Boolean;
var
  slots: TStringDynArray;
  i, idx: Integer;
begin
  if AData = '' then
  begin
    RestoreColor(-1);
    Exit(True);
  end;
  slots := SplitOn(AData, ';');
  for i := 0 to High(slots) do
    if ColorIndexOf(slots[i], idx) then
      RestoreColor(idx);
  Result := True;
end;

function TTyTerminalCore.OscRestoreFgColor(const AData: string): Boolean;
begin
  RestoreColor(ColorFg);
  Result := True;
end;

function TTyTerminalCore.OscRestoreBgColor(const AData: string): Boolean;
begin
  RestoreColor(ColorBg);
  Result := True;
end;

function TTyTerminalCore.OscRestoreCursorColor(const AData: string): Boolean;
begin
  RestoreColor(ColorCursor);
  Result := True;
end;

{ An OSC no handler took (spec 7.4): the payload is collected with the same limit
  as a string handler and handed to OnOsc when it ends well -- only when OnOsc was
  assigned as the OSC started, so nobody listening costs nothing. Numbers past
  High(Integer), and the -1 of an OSC without a number, never reach the host. The
  core has no default action for these: OnOsc is all there is. }
procedure TTyTerminalCore.OscFallback(AIdent: Int64; AAction: TTyTermSubAction; const APayload: string;
  ASuccess: Boolean);
var
  cps: TIntegerDynArray;
  data: array of Cardinal;
  i: Integer;
begin
  case AAction of
    tsaStart:
      begin
        FOscData.Reset;
        FOscDataHitLimit := False;
        FOscCollecting := Assigned(FOnOsc);
      end;
    tsaPut:
      if FOscCollecting and not FOscDataHitLimit then
      begin
        cps := TyTermUtf8Codepoints(APayload);
        data := nil;
        SetLength(data, Length(cps));
        for i := 0 to High(cps) do
          data[i] := Cardinal(cps[i]);
        if FOscData.Append(data, 0, Length(data)) then
          FOscDataHitLimit := True;
      end;
    tsaEnd:
      begin
        if FOscCollecting and ASuccess and not FOscDataHitLimit and (AIdent >= 0)
          and (AIdent <= High(Integer)) and Assigned(FOnOsc) then
          FOnOsc(Self, Integer(AIdent), FOscData.Text);
        FOscData.Reset;
        FOscDataHitLimit := False;
        FOscCollecting := False;
      end;
  end;
end;

{ ---- kitty keyboard, :3552-3651 (off unless vtExtensions.kittyKeyboard) ---- }

function TTyTerminalCore.KittyKeyboardSet(AParams: TTyTerminalParams): Boolean;
var
  flags, mode: Integer;
begin
  if not (tveKittyKeyboard in FVtExtensions) then
    Exit(True);
  flags := AParams[0];
  if AParams.Length > 1 then
  begin
    mode := AParams[1];
    if mode = 0 then mode := 1;
  end
  else
    mode := 1;
  case mode of
    1: FKittyFlags := flags;                          { set all }
    2: FKittyFlags := FKittyFlags or flags;           { set the given }
    3: FKittyFlags := FKittyFlags and not flags;      { reset the given }
  end;
  Result := True;
end;

function TTyTerminalCore.KittyKeyboardQuery(AParams: TTyTerminalParams): Boolean;
begin
  if not (tveKittyKeyboard in FVtExtensions) then
    Exit(True);
  TriggerDataEvent(#27'[?' + IntToStr(FKittyFlags) + 'u');
  Result := True;
end;

function TTyTerminalCore.KittyKeyboardPush(AParams: TTyTerminalParams): Boolean;

  procedure Push(var AStack: TIntegerDynArray);
  var
    i: Integer;
  begin
    { a full stack drops its oldest entry (limit 16) }
    if Length(AStack) >= 16 then
    begin
      for i := 0 to High(AStack) - 1 do
        AStack[i] := AStack[i + 1];
      SetLength(AStack, Length(AStack) - 1);
    end;
    SetLength(AStack, Length(AStack) + 1);
    AStack[High(AStack)] := FKittyFlags;
  end;

begin
  if not (tveKittyKeyboard in FVtExtensions) then
    Exit(True);
  if Buffer = Buffers.Alt then
    Push(FKittyAltStack)
  else
    Push(FKittyMainStack);
  FKittyFlags := AParams[0];
  Result := True;
end;

function TTyTerminalCore.KittyKeyboardPop(AParams: TTyTerminalParams): Boolean;

  procedure Pop(var AStack: TIntegerDynArray; ACount: Integer);
  var
    i: Integer;
  begin
    i := 0;
    while (i < ACount) and (Length(AStack) > 0) do
    begin
      FKittyFlags := AStack[High(AStack)];
      SetLength(AStack, Length(AStack) - 1);
      Inc(i);
    end;
    { an emptied stack leaves the flags at 0 }
    if (Length(AStack) = 0) and (ACount > 0) then
      FKittyFlags := 0;
  end;

var
  count: Integer;
begin
  if not (tveKittyKeyboard in FVtExtensions) then
    Exit(True);
  count := Max(1, P0or1(AParams));
  if Buffer = Buffers.Alt then
    Pop(FKittyAltStack, count)
  else
    Pop(FKittyMainStack, count);
  Result := True;
end;
