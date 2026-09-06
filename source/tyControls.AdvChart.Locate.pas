unit tyControls.AdvChart.Locate;
{$mode objfpc}{$H+}
{ Where in the TEXT does an option path live?

  The dual of TyOptContextAt next door. That one scans BACKWARD from a caret to
  answer "what may be typed here"; this one scans FORWARD over the whole
  document to answer "where is series[0].itemStyle.color", so a diagnostic that
  knows only a path can be turned into a place to put the caret.

  WHY A SECOND SCANNER RATHER THAN ONE SHARED ONE. The two genuinely differ:

  - Direction. The backward scan stops at the caret and treats the last token as
    half-typed; this one runs to the end and every token is complete.
  - INDICES. The backward scan deliberately does not count array elements --
    its comment says so, and it is right, because which options are legal inside
    series[3] is the same question as inside series[0]. A runtime path is the
    opposite: the index IS the answer.

  What they must agree on is the LEXER -- which quote styles close a string,
  what a backslash escapes, where a comment ends. Those rules are duplicated
  below rather than shared, and that is a deliberate cost: nineteen tests pin
  the backward scanner and unifying them would reopen it. The escape rule in
  particular was found by mutation once, so it is mutation-tested here too.

  THE PATH SPELLING IS NOT A CHOICE. It must match, character for character,
  what TyOptValidate puts in a TTyOptIssue -- root is the empty string, the
  first key carries no leading dot, and an array subscript is appended with no
  dot before it:

      series[0].itemStyle.color

  A spelling that differs anywhere is not a bug that shows up as a wrong answer;
  it shows up as a lookup that silently never matches.

  LCL-free: SysUtils and Classes only. }
interface
uses SysUtils, Classes;

type
  { One key token in the document, and where it is. }
  TTyOptKeyPos = record
    { The RUNTIME path of the key, as TTyOptIssue spells it. }
    Path: string;
    { 1-based, counting LF, CRLF and lone CR each as one break. }
    Line: Integer;
    { 1-based BYTE column of the key's first NAME character -- inside the quotes
      when it is quoted, because what an editor wants to select is the name. }
    Col: Integer;
    { The name's length, so a caller can select exactly it. }
    Len: Integer;
  end;
  TTyOptKeyPosArray = array of TTyOptKeyPos;

{ Every key in the text, in document order.

  Tolerant by construction: unclosed braces, unterminated strings and half-typed
  text are the normal state in an editor, and every key BEFORE the damage still
  gets a position. It never raises. }
function TyOptKeyPositions(const AText: string): TTyOptKeyPosArray;

{ The position of exactly this path. }
function TyOptFindKey(const APositions: TTyOptKeyPosArray; const APath: string;
  out APos: TTyOptKeyPos): Boolean;

{ The position of this path, or -- failing that -- of the longest prefix of it
  that IS in the text.

  A diagnostic can name something that is not a key at all: a leaf that was
  deleted, or a path the build derived rather than read. Jumping to series[0] is
  useful; refusing to jump because series[0].data.3 is not a key is not. }
function TyOptFindNearestKey(const APositions: TTyOptKeyPosArray;
  const APath: string; out APos: TTyOptKeyPos): Boolean;

{ The first option path mentioned in a diagnostic's prose, or ''.

  The build's diagnostics are sentences, not structured data -- 'series[2]:
  xAxis[0] and yAxis[1] are not on one grid'. A path is recognised by carrying a
  subscript: that is what separates 'series[2]' from the ordinary English words
  around it, and it is why a message with no subscript yields nothing rather
  than a guess. When a message names several, the FIRST is the subject. }
function TyOptPathInMessage(const AMessage: string): string;

implementation

type
  TFrame = record
    IsArray: Boolean;
    ExpectKey: Boolean;
    { The name most recently read at a key position, waiting for its colon. }
    HeldName: string;
    HeldLine, HeldCol, HeldLen: Integer;
    { This container's own runtime path. '' for the synthetic root. }
    Path: string;
    { The path of the key most recently read in this object -- which is the path
      the NEXT open-brace or open-bracket belongs to. }
    PendingPath: string;
    { Which element of an array we are in. Meaningless for an object. }
    Index: Integer;
  end;

{ WHAT COUNTS AS A BARE NAME. fcl-json is the arbiter here, not the backward
  scanner's looser IsIdentChar: only a key this parser accepts can ever end up
  in a TTyOptIssue, so a name this scanner invents is a path nothing can look
  up. jsonscanner.pp starts an identifier on a letter or '_' and continues on
  letters, digits and '_'.

  '.' is deliberately NOT a name character. With it, `a.b: 1` emitted the single
  path 'a.b', which collides with the spelling for nesting and which no issue
  can ever carry -- fcl-json cannot parse it unquoted anyway. }
function IsNameChar(C: Char): Boolean;
begin
  Result := (C in ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

function IsNameStart(C: Char): Boolean;
begin
  Result := (C in ['A'..'Z', 'a'..'z', '_']);
end;

function TyOptKeyPositions(const AText: string): TTyOptKeyPosArray;
var
  frames: array of TFrame;
  depth, i, n, count, line, lineStart, tokStart, tokLine, tokCol: Integer;
  c, quote: Char;
  tok, keyPath: string;

  procedure Push(AIsArray: Boolean);
  var p: string;
  begin
    p := '';
    if depth > 0 then
    begin
      if frames[depth - 1].IsArray then
        p := frames[depth - 1].Path + '[' + IntToStr(frames[depth - 1].Index) + ']'
      else
        p := frames[depth - 1].PendingPath;
    end;
    if depth = Length(frames) then SetLength(frames, 8 + depth * 2);
    frames[depth].IsArray := AIsArray;
    frames[depth].ExpectKey := not AIsArray;
    frames[depth].Path := p;
    frames[depth].PendingPath := '';
    frames[depth].HeldName := '';
    frames[depth].Index := 0;
    Inc(depth);
  end;

  procedure Pop;
  begin
    if depth > 1 then Dec(depth);   { never pop the synthetic root }
  end;

  { A token that MIGHT be a key. Held, not emitted: what makes a name a key is
    the colon after it, and until one arrives `a` in `{ a b: 1 }` is not a key
    at all. Emitting on the token instead produced a phantom entry for every
    such stray word, with a path nothing could ever look up. }
  procedure Hold(const AName: string; ALine, ACol, ALen: Integer);
  begin
    if depth = 0 then Exit;
    if frames[depth - 1].IsArray then Exit;
    if not frames[depth - 1].ExpectKey then Exit;
    frames[depth - 1].HeldName := AName;
    frames[depth - 1].HeldLine := ALine;
    frames[depth - 1].HeldCol := ACol;
    frames[depth - 1].HeldLen := ALen;
  end;

  { The colon arrived: the held name was a key after all. }
  procedure EmitHeld;
  begin
    if depth = 0 then Exit;
    if frames[depth - 1].IsArray then Exit;
    if frames[depth - 1].HeldName = '' then Exit;
    if frames[depth - 1].Path = '' then keyPath := frames[depth - 1].HeldName
    else keyPath := frames[depth - 1].Path + '.' + frames[depth - 1].HeldName;
    frames[depth - 1].PendingPath := keyPath;
    if count = Length(Result) then SetLength(Result, 16 + count * 2);
    Result[count].Path := keyPath;
    Result[count].Line := frames[depth - 1].HeldLine;
    Result[count].Col := frames[depth - 1].HeldCol;
    Result[count].Len := frames[depth - 1].HeldLen;
    Inc(count);
    frames[depth - 1].HeldName := '';
  end;

  procedure CountBreak(AAt: Integer);
  begin
    Inc(line);
    lineStart := AAt + 1;
  end;

begin
  Result := nil;
  count := 0;
  SetLength(frames, 16);
  depth := 0;
  { A synthetic root object, so text with no outer brace still yields paths
    against the option root rather than against nothing. }
  Push(False);

  n := Length(AText);
  i := 1;
  line := 1;
  lineStart := 1;
  while i <= n do
  begin
    c := AText[i];

    { line breaks -- CRLF is ONE break, and a lone CR is one too }
    if c = #13 then
    begin
      if (i < n) and (AText[i + 1] = #10) then Inc(i);
      CountBreak(i);
      Inc(i);
      Continue;
    end;
    if c = #10 then
    begin
      CountBreak(i);
      Inc(i);
      Continue;
    end;

    { comments -- a quote inside one is not a string }
    if (c = '/') and (i < n) and (AText[i + 1] = '/') then
    begin
      while (i <= n) and not (AText[i] in [#10, #13]) do Inc(i);
      Continue;
    end;
    if (c = '/') and (i < n) and (AText[i + 1] = '*') then
    begin
      Inc(i, 2);
      while (i < n) and not ((AText[i] = '*') and (AText[i + 1] = '/')) do
      begin
        if AText[i] = #13 then
        begin
          if (i < n) and (AText[i + 1] = #10) then Inc(i);
          CountBreak(i);
        end
        else if AText[i] = #10 then
          CountBreak(i);
        Inc(i);
      end;
      Inc(i, 2);
      Continue;
    end;

    { strings -- both quote styles, backslash escapes the next character }
    if (c = '''') or (c = '"') then
    begin
      quote := c;
      tokStart := i + 1;
      tokLine := line;
      tokCol := tokStart - lineStart + 1;
      Inc(i);
      while (i <= n) and (AText[i] <> quote) do
      begin
        if (AText[i] = '\') and (i < n) then
        begin
          { The escaped character is skipped, but if it is a LINE BREAK it must
            still be COUNTED. Otherwise every key after this string sits a line
            too high and its column is measured from the wrong line start --
            and the editor then jumps confidently to the wrong place, which is
            worse than not finding the key at all. }
          Inc(i);
          if AText[i] = #13 then
          begin
            if (i < n) and (AText[i + 1] = #10) then Inc(i);
            CountBreak(i);
          end
          else if AText[i] = #10 then
            CountBreak(i);
        end
        else if AText[i] = #13 then
        begin
          if (i < n) and (AText[i + 1] = #10) then Inc(i);
          CountBreak(i);
        end
        else if AText[i] = #10 then
          CountBreak(i);
        Inc(i);
      end;
      tok := Copy(AText, tokStart, i - tokStart);
      { An unterminated string is the end of anything we can say. Every key
        before it still stands. }
      if i > n then Break;
      Hold(tok, tokLine, tokCol, Length(tok));
      Inc(i);
      Continue;
    end;

    { bare identifiers -- fcl-json accepts an unquoted key and so must this }
    if IsNameStart(c) then
    begin
      tokStart := i;
      tokLine := line;
      tokCol := tokStart - lineStart + 1;
      while (i <= n) and IsNameChar(AText[i]) do Inc(i);
      tok := Copy(AText, tokStart, i - tokStart);
      Hold(tok, tokLine, tokCol, Length(tok));
      Continue;
    end;

    { A token that does NOT start with a name character is consumed WHOLE.
      Without this the scan entered `5x` and `-foo` mid-token: the leading
      character fell through the case below and a name then started at `x` /
      `foo`, reported at that offset -- a key nobody wrote, a few columns off.
      fcl-json rejects both as names anyway, so the right answer is that
      neither is one. }
    if c in ['0'..'9', '-', '+', '.'] then
    begin
      while (i <= n) and (AText[i] in ['0'..'9', 'A'..'Z', 'a'..'z',
        '_', '-', '+', '.']) do Inc(i);
      Continue;
    end;

    case c of
      '{': Push(False);
      '[': Push(True);
      '}', ']': Pop;
      ':': if not frames[depth - 1].IsArray then
           begin
             EmitHeld;
             frames[depth - 1].ExpectKey := False;
           end;
      ',':
        if frames[depth - 1].IsArray then
          { THE index. This increment is the whole reason this scanner exists
            separately from the backward one, which deliberately ignores it. }
          Inc(frames[depth - 1].Index)
        else
        begin
          frames[depth - 1].ExpectKey := True;
          frames[depth - 1].PendingPath := '';
          frames[depth - 1].HeldName := '';
        end;
    end;
    Inc(i);
  end;

  SetLength(Result, count);
end;

function TyOptFindKey(const APositions: TTyOptKeyPosArray; const APath: string;
  out APos: TTyOptKeyPos): Boolean;
var i: Integer;
begin
  Result := False;
  APos := Default(TTyOptKeyPos);
  if APath = '' then Exit;
  for i := 0 to High(APositions) do
    if APositions[i].Path = APath then
    begin
      APos := APositions[i];
      Exit(True);
    end;
end;

{ Drop the last segment of a runtime path: a trailing '[n]' first, then a
  trailing '.name'. '' when there is nothing left to drop. }
function ParentPath(const APath: string): string;
var i: Integer;
begin
  Result := '';
  if APath = '' then Exit;
  if APath[Length(APath)] = ']' then
  begin
    i := Length(APath);
    while (i > 1) and (APath[i] <> '[') do Dec(i);
    if APath[i] = '[' then Exit(Copy(APath, 1, i - 1));
    Exit('');
  end;
  for i := Length(APath) downto 1 do
    if APath[i] = '.' then Exit(Copy(APath, 1, i - 1));
end;

{ Drop every '[0]' from a path.

  TWO PRODUCERS NORMALISE THE SAME TEXT DIFFERENTLY, and this is that seam.
  `xAxis: { type: 'wat' }` is a bare object; the builder loops over
  ComponentCount, which reports 1 for a bare object, so its diagnostic says
  'xAxis[0].type'. TyOptValidate walks the tree as written and says
  'xAxis.type'. The text itself contains neither subscript.

  Without this the walk degrades two whole steps -- straight past the key that
  IS in the text -- and lands on the container. Only '[0]' is dropped: a path
  naming element 3 is talking about a real array. }
function DropZeroIndexes(const APath: string): string;
var i: Integer;
begin
  Result := APath;
  repeat
    i := Pos('[0]', Result);
    if i = 0 then Break;
    Delete(Result, i, 3);
  until False;
end;

function TyOptFindNearestKey(const APositions: TTyOptKeyPosArray;
  const APath: string; out APos: TTyOptKeyPos): Boolean;
var p, bare: string;
begin
  p := APath;
  while p <> '' do
  begin
    if TyOptFindKey(APositions, p, APos) then Exit(True);
    bare := DropZeroIndexes(p);
    if (bare <> p) and TyOptFindKey(APositions, bare, APos) then Exit(True);
    p := ParentPath(p);
  end;
  APos := Default(TTyOptKeyPos);
  Result := False;
end;

function TyOptPathInMessage(const AMessage: string): string;
var
  i, j, segStart: Integer;
  seg: string;
  sawIndex: Boolean;
begin
  Result := '';
  i := 1;
  while i <= Length(AMessage) do
  begin
    if not IsNameStart(AMessage[i]) then
    begin
      Inc(i);
      Continue;
    end;
    segStart := i;
    sawIndex := False;
    { name ( '[' digits ']' )? ( '.' name ( '[' digits ']' )? )* }
    while i <= Length(AMessage) do
    begin
      j := i;
      while (i <= Length(AMessage)) and IsNameStart(AMessage[i]) do
      begin
        Inc(i);
        while (i <= Length(AMessage))
          and (AMessage[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(i);
      end;
      if i = j then Break;
      if (i <= Length(AMessage)) and (AMessage[i] = '[') then
      begin
        j := i + 1;
        while (j <= Length(AMessage)) and (AMessage[j] in ['0'..'9']) do Inc(j);
        if (j > i + 1) and (j <= Length(AMessage)) and (AMessage[j] = ']') then
        begin
          sawIndex := True;
          i := j + 1;
        end;
      end;
      if (i <= Length(AMessage)) and (AMessage[i] = '.')
        and (i < Length(AMessage)) and IsNameStart(AMessage[i + 1]) then
        Inc(i)
      else
        Break;
    end;
    seg := Copy(AMessage, segStart, i - segStart);
    { A subscript is what makes it a path rather than an English word. Without
      that test every sentence would yield its first noun. }
    if sawIndex then Exit(seg);
  end;
end;

end.
