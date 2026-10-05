unit tbformat;
{ "Edit > Format document" and "Format selection": a tidy of .tycss text that keeps every
  meaning and every comment.

  Why not the library's TyCssFormat / TyCssFormatLine (tyControls.Css.Complete): they are made
  for a StyleOverride declaration block, and on a whole theme file they change what they must
  not -- the colon of a pseudo-class gets a space ("TyButton: hover"), a comment's line breaks
  are collapsed (a file's header comment becomes one long line), and a colon inside a quoted
  url ("C:/x.png") gets a space too. This one reads the text as tokens -- comments and strings
  are copied as they are -- and only then lays it out:

    - a rule's head (selector, @mode ...): its runs of white space one space, then a space
      and the opening brace;
    - a declaration: one per line, "name: value;" -- the space after the FIRST colon outside
      brackets and strings, none before it or before the ";", runs of white space one space;
      a last declaration without ";" before the closing brace gets one;
    - a closing brace on a line of its own; two spaces of indent per level;
    - a comment on a line of its own stays on its own line (indented; a long comment keeps its
      inner lines as they were), one that followed code on the same line stays after it, one
      inside a declaration stays inside it;
    - one empty line where the text had one or more between two things, none added, none at
      the start or the end.

  Formatting what this produced changes nothing. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils;

{ AText laid out as above, starting at brace depth ADepth (a fragment inside a rule), its lines
  joined with AEol, no line break after the last line. '' for a text with nothing in it. }
function TbFormatCss(const AText: string; ADepth: Integer; const AEol: string): string;

{ The whole lines AFirstLine .. ALastLine (1-based) of AText, formatted at the brace depth they
  start at: the range grows to take in a comment that starts above it or runs on below it.
  AStart / AStop are byte offsets into AText (replace AText[AStart .. AStop-1], the last line's
  break left alone), ANew what goes there. False when there is nothing to change. }
function TbFormatLines(const AText: string; AFirstLine, ALastLine: Integer; const AEol: string;
  out AStart, AStop: Integer; out ANew: string): Boolean;

implementation

uses
  StrUtils;

type
  TOut = class
  private
    FLines: TStringList;
    FEol: string;
  public
    constructor Create(const AEol: string);
    destructor Destroy; override;
    { a line of its own at ADepth, after an empty one when ABlankBefore (and not first) }
    procedure Line(ADepth: Integer; const AText: string; ABlankBefore: Boolean);
    { onto the end of the last line }
    procedure Append(const AText: string);
    function Count: Integer;
    function Text: string;
  end;

constructor TOut.Create(const AEol: string);
begin
  inherited Create;
  FLines := TStringList.Create;
  FEol := AEol;
end;

destructor TOut.Destroy;
begin
  FLines.Free;
  inherited Destroy;
end;

procedure TOut.Line(ADepth: Integer; const AText: string; ABlankBefore: Boolean);
begin
  if ABlankBefore and (FLines.Count > 0) and (FLines[FLines.Count - 1] <> '') then
    FLines.Add('');
  FLines.Add(StringOfChar(' ', 2 * ADepth) + AText);
end;

procedure TOut.Append(const AText: string);
begin
  FLines[FLines.Count - 1] := FLines[FLines.Count - 1] + AText;
end;

function TOut.Count: Integer;
begin
  Result := FLines.Count;
end;

function TOut.Text: string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to FLines.Count - 1 do
  begin
    if i > 0 then
      Result := Result + FEol;
    Result := Result + FLines[i];
  end;
end;

{ every line break in S (CRLF, LF, CR) as AEol }
function WithEol(const S, AEol: string): string;
var
  i: Integer;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    if S[i] = #13 then
    begin
      Result := Result + AEol;
      if (i < Length(S)) and (S[i + 1] = #10) then
        Inc(i);
    end
    else if S[i] = #10 then
      Result := Result + AEol
    else
      Result := Result + S[i];
    Inc(i);
  end;
end;

{ the end of the comment that starts at AFrom ('/*'): the index just past '*/', or past the
  text when it never closes }
function CommentEnd(const S: string; AFrom: Integer): Integer;
begin
  Result := PosEx('*/', S, AFrom + 2);
  if Result = 0 then
    Result := Length(S) + 1
  else
    Inc(Result, 2);
end;

{ the end of the string that starts at AFrom (a quote): just past the closing quote, a
  backslash escaping the next character; a string stops at a line break or the end }
function StringEnd(const S: string; AFrom: Integer): Integer;
var
  q: Char;
begin
  q := S[AFrom];
  Result := AFrom + 1;
  while Result <= Length(S) do
  begin
    if S[Result] = '\' then
      Inc(Result, 2)
    else if S[Result] = q then
      Exit(Result + 1)
    else if S[Result] in [#10, #13] then
      Exit(Result)
    else
      Inc(Result);
  end;
  Result := Length(S) + 1;
end;

function TbFormatCss(const AText: string; ADepth: Integer; const AEol: string): string;
var
  o: TOut;
  i, j, n, depth, breaks, itemBreaks, paren, colon: Integer;
  item, piece: string;
  space, lineHasCode: Boolean;

  procedure Add(const APiece: string; AIsCode: Boolean);
  begin
    if item = '' then
      itemBreaks := breaks
    else if space then
      item := item + ' ';
    space := False;
    if AIsCode then
    begin
      { the first colon outside brackets: where a declaration's name ends }
      if (colon = 0) and (APiece = ':') and (paren = 0) then
        colon := Length(item) + 1;
      if APiece = '(' then Inc(paren)
      else if (APiece = ')') and (paren > 0) then Dec(paren);
    end;
    item := item + APiece;
  end;

  function Declaration: string;
  var
    name, value: string;
  begin
    if colon = 0 then
      Exit(item);
    name := TrimRight(Copy(item, 1, colon - 1));
    value := TrimLeft(Copy(item, colon + 1, MaxInt));
    if value = '' then
      Result := name + ':'
    else
      Result := name + ': ' + value;
  end;

  procedure Emit(const ALine: string);
  begin
    o.Line(depth, ALine, itemBreaks >= 2);
    lineHasCode := True;
    breaks := 0;
  end;

  procedure ResetItem;
  begin
    item := '';
    space := False;
    colon := 0;
    paren := 0;
  end;

begin
  o := TOut.Create(AEol);
  try
    depth := ADepth;
    if depth < 0 then depth := 0;
    breaks := 0;
    itemBreaks := 0;
    lineHasCode := False;
    ResetItem;
    n := Length(AText);
    i := 1;
    while i <= n do
    begin
      case AText[i] of
        #13, #10:
          begin
            Inc(breaks);
            lineHasCode := False;
            if (AText[i] = #13) and (i < n) and (AText[i + 1] = #10) then
              Inc(i);
            space := item <> '';
            Inc(i);
          end;
        ' ', #9, #12:
          begin
            space := item <> '';
            Inc(i);
          end;
        '"', '''':
          begin
            j := StringEnd(AText, i);
            Add(Copy(AText, i, j - i), False);
            i := j;
          end;
        '/':
          if (i < n) and (AText[i + 1] = '*') then
          begin
            j := CommentEnd(AText, i);
            piece := WithEol(Copy(AText, i, j - i), AEol);
            if item <> '' then
              Add(piece, False)                     { inside a declaration or a head }
            else if (breaks = 0) and lineHasCode and (o.Count > 0) then
              o.Append(' ' + piece)                 { after code on the same line }
            else
            begin
              itemBreaks := breaks;
              o.Line(depth, piece, itemBreaks >= 2);
              lineHasCode := True;
              breaks := 0;
            end;
            i := j;
          end
          else
          begin
            Add('/', True);
            Inc(i);
          end;
        '{':
          begin
            if item = '' then
            begin
              itemBreaks := breaks;
              Emit('{');
            end
            else
              Emit(item + ' {');
            Inc(depth);
            ResetItem;
            Inc(i);
          end;
        ';':
          begin
            if item = '' then
            begin
              { a stray ';' -- kept, on the line before it }
              if (o.Count > 0) and lineHasCode then
                o.Append(';')
              else
              begin
                itemBreaks := breaks;
                Emit(';');
              end;
            end
            else if depth > 0 then
              Emit(Declaration + ';')
            else
              Emit(item + ';');                     { @import "x"; at the top }
            ResetItem;
            Inc(i);
          end;
        '}':
          begin
            if item <> '' then
            begin
              if depth > 0 then
                Emit(Declaration + ';')
              else
                Emit(item);
            end;
            if depth > 0 then
              Dec(depth);
            itemBreaks := 0;                        { no empty line before a closing brace }
            Emit('}');
            ResetItem;
            Inc(i);
          end;
      else
        begin
          Add(AText[i], True);
          Inc(i);
        end;
      end;
    end;
    if item <> '' then
      Emit(item);
    Result := o.Text;
  finally
    o.Free;
  end;
end;

type
  TLineState = record
    Start: Integer;          { byte offset of the line's first character }
    Depth: Integer;          { brace depth at the line's start }
    InComment: Boolean;      { the line starts inside a comment }
  end;
  TLineStates = array of TLineState;

{ the state at the start of every line, and one more entry for the end of the text }
function ScanLines(const S: string): TLineStates;
var
  i, j, n, depth, k: Integer;

  procedure NewLine(AStart: Integer; AInComment: Boolean);
  begin
    SetLength(Result, k + 1);
    Result[k].Start := AStart;
    Result[k].Depth := depth;
    Result[k].InComment := AInComment;
    Inc(k);
  end;

  { the line breaks inside S[AFrom .. ATo-1]: every one starts a line still in the comment }
  procedure BreaksIn(AFrom, ATo: Integer);
  var
    p: Integer;
  begin
    p := AFrom;
    while p < ATo do
    begin
      if S[p] = #13 then
      begin
        if (p + 1 < ATo) and (S[p + 1] = #10) then
          Inc(p);
        NewLine(p + 1, True);
      end
      else if S[p] = #10 then
        NewLine(p + 1, True);
      Inc(p);
    end;
  end;

begin
  Result := nil;
  k := 0;
  depth := 0;
  n := Length(S);
  NewLine(1, False);
  i := 1;
  while i <= n do
  begin
    case S[i] of
      #13:
        begin
          if (i < n) and (S[i + 1] = #10) then
            Inc(i);
          Inc(i);
          NewLine(i, False);
        end;
      #10:
        begin
          Inc(i);
          NewLine(i, False);
        end;
      '"', '''':
        i := StringEnd(S, i);
      '/':
        if (i < n) and (S[i + 1] = '*') then
        begin
          j := CommentEnd(S, i);
          BreaksIn(i, j);
          i := j;
        end
        else
          Inc(i);
      '{':
        begin
          Inc(depth);
          Inc(i);
        end;
      '}':
        begin
          if depth > 0 then
            Dec(depth);
          Inc(i);
        end;
    else
      Inc(i);
    end;
  end;
  { the end of the text, as one more "line start": the last line ends here }
  if Result[k - 1].Start <> n + 1 then
    NewLine(n + 1, False)
  else
    Result[k - 1].InComment := False;
end;

function TbFormatLines(const AText: string; AFirstLine, ALastLine: Integer; const AEol: string;
  out AStart, AStop: Integer; out ANew: string): Boolean;
var
  st: TLineStates;
  lines, first, last: Integer;
  old: string;
begin
  Result := False;
  AStart := 1;
  AStop := 1;
  ANew := '';
  st := ScanLines(AText);
  lines := Length(st) - 1;                     { the last entry is the end of the text }
  if lines < 1 then Exit;
  first := AFirstLine;
  last := ALastLine;
  if first < 1 then first := 1;
  if last > lines then last := lines;
  if first > last then Exit;
  { a comment that starts above the first line or runs on past the last one comes in whole }
  while (first > 1) and st[first - 1].InComment do
    Dec(first);
  while (last < lines) and st[last].InComment do
    Inc(last);
  AStart := st[first - 1].Start;
  AStop := st[last].Start;
  { the last line's own break stays where it is }
  if (AStop > AStart) and (AStop - 1 >= 1) and (AText[AStop - 1] = #10) then
    Dec(AStop);
  if (AStop > AStart) and (AStop - 1 >= 1) and (AText[AStop - 1] = #13) then
    Dec(AStop);
  old := Copy(AText, AStart, AStop - AStart);
  ANew := TbFormatCss(old, st[first - 1].Depth, AEol);
  Result := ANew <> old;
end;

end.
