unit tbcssscan;
{ A forgiving walk over a .tycss text that knows WHERE things are: every :root block, every
  :root inside an @mode block, every rule, with the byte span of each declaration's value
  and the start of each selector.

  Why it exists: the seeds panel and Ctrl+click in the preview must find "the value of this
  declaration" or "the selector of this rule" in the text and change only that span -- the
  rest of the file, its comments and its alignment, stay byte for byte. The parser keeps no
  positions, and the lint's position walk is private to the library.

  How: the library's own TTyCssLexer does the reading, so comments and strings are seen
  exactly as the parser sees them; its tokens carry a line and a byte column, turned into a
  1-based byte offset through a table of line starts built with the lexer's own line-break
  rule (LF; a lone CR; CR+LF once).

  It never raises: a text written badly is scanned as far as it goes. A block whose closing
  brace never comes has CloseBrace = 0; an at-rule it does not know is skipped whole. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types;

type
  TTbBlockKind = (tbkRoot, tbkModeRoot, tbkRule);

  TTbDecl = record
    Name: string;                 { as written: '--accent', 'background' }
    NameStart: Integer;           { 1-based byte offset of the name }
    ValueStart, ValueEnd: Integer;{ the value is Text[ValueStart .. ValueEnd-1]; blanks and
                                    comments before the ';' are not part of it }
    StopAt: Integer;              { the ';' that ends it; 0 when a closing brace or the end did }
  end;

  TTbSelectorRef = record
    TypeName, Variant, State: string;   { State lower case, '' = none }
    Start: Integer;                     { offset of the type name }
  end;

  TTbBlock = class
  public
    Kind: TTbBlockKind;
    Mode: string;          { tbkModeRoot: the @mode name, lower case }
    ModeStart: Integer;    { tbkModeRoot: the '@' of its @mode; 0 otherwise }
    OuterClose: Integer;   { tbkModeRoot: the @mode block's own closing brace; 0 when missing }
    HeadStart: Integer;    { ':' of :root, or the first selector's first byte }
    OpenBrace: Integer;
    CloseBrace: Integer;   { 0: the text ends first }
    Selectors: array of TTbSelectorRef;  { tbkRule }
    Decls: array of TTbDecl;
  end;

  TTbCssScan = class
  private
    FBlocks: TFPList;
  public
    Text: string;
    ImportEnd: Integer;    { one past the last top-level @import's ';' (0: none) }
    Imports: array of string;   { the top-level @import paths as written (unquoted), text order }
    constructor Create;
    destructor Destroy; override;
    procedure Add(ABlock: TTbBlock);
    function Count: Integer;
    function Block(AIndex: Integer): TTbBlock;
    function HasModes: Boolean;                        { some tbkModeRoot block }
    function DeclValue(ABlock, ADecl: Integer): string;
  end;

  TTbTextEdit = record
    Start, Stop: Integer;  { replace Text[Start .. Stop-1]; Start = Stop inserts }
    Text: string;
  end;
  TTbTextEdits = array of TTbTextEdit;   { ascending, never overlapping }
  TTbOffsets = array of Integer;
  TTbCssScans = array of TTbCssScan;

{ a forgiving walk: never raises, whatever the text }
function TbScanCss(const AText: string): TTbCssScan;
{ The files AText (the entry, in ABaseDir) @imports, followed down the way the style model
  does (StyleModel.ExpandSheet): a path as written if that file is there, else from the
  folder of the file that imports it; each file once; a cycle, a file that is not there or
  cannot be read is passed over (the model raises -- the problem list says so). Their scans
  in the order the model adds them: an imported file before the one that imports it, so a
  later one wins. The caller frees them (TbFreeScans). }
function TbScanImports(const AText, ABaseDir: string): TTbCssScans;
procedure TbFreeScans(var AScans: TTbCssScans);
{ AOffset (1-based, may be Length+1) -> Point(byte column, line), lines broken as the tycss
  lexer breaks them (LF, CRLF, a lone CR) -- SynEdit's logical caret }
function TbOffsetToPoint(const AText: string; AOffset: Integer): TPoint;
function TbLineStart(const AText: string; AOffset: Integer): Integer;
function TbLineIndent(const AText: string; AOffset: Integer): string;
{ where "append at the end" goes: before a final line break, else Length+1 }
function TbEndInsertPos(const AText: string): Integer;
function TbDetectEol(const AText: string): string;    { the first break as written; LineEnding when none }
function TbEdit(AStart, AStop: Integer; const AText: string): TTbTextEdit;
{ the edits applied back to front; edits that are not ascending and apart (or out of the
  text) leave AText as it is }
function TbApplyEdits(const AText: string; const AEdits: TTbTextEdits): string;
{ True when AText holds nothing but blanks and line breaks }
function TbIsBlank(const AText: string): Boolean;

implementation

uses
  Math, tyControls.Css.Tokens, tyControls.Css.Lexer;

{ ---- TTbCssScan ---- }

constructor TTbCssScan.Create;
begin
  inherited Create;
  FBlocks := TFPList.Create;
end;

destructor TTbCssScan.Destroy;
var
  i: Integer;
begin
  for i := 0 to FBlocks.Count - 1 do
    TTbBlock(FBlocks[i]).Free;
  FBlocks.Free;
  inherited Destroy;
end;

procedure TTbCssScan.Add(ABlock: TTbBlock);
begin
  FBlocks.Add(ABlock);
end;

function TTbCssScan.Count: Integer;
begin
  Result := FBlocks.Count;
end;

function TTbCssScan.Block(AIndex: Integer): TTbBlock;
begin
  Result := TTbBlock(FBlocks[AIndex]);
end;

function TTbCssScan.HasModes: Boolean;
var
  i: Integer;
begin
  for i := 0 to FBlocks.Count - 1 do
    if TTbBlock(FBlocks[i]).Kind = tbkModeRoot then
      Exit(True);
  Result := False;
end;

function TTbCssScan.DeclValue(ABlock, ADecl: Integer): string;
var
  d: TTbDecl;
begin
  d := Block(ABlock).Decls[ADecl];
  Result := Copy(Text, d.ValueStart, d.ValueEnd - d.ValueStart);
end;

{ ---- offsets and lines ---- }

{ where each line starts, broken exactly as TTyCssLexer.Advance breaks them: LF; a lone CR;
  CR+LF once. Index = line number (1-based); starts[1] = 1. }
function LineStarts(const AText: string): TTbOffsets;
var
  i, n: Integer;
begin
  SetLength(Result, 64);
  Result[0] := 0;
  Result[1] := 1;
  n := 1;
  for i := 1 to Length(AText) do
    if (AText[i] = #10) or ((AText[i] = #13) and ((i = Length(AText)) or (AText[i + 1] <> #10))) then
    begin
      Inc(n);
      if n >= Length(Result) then
        SetLength(Result, Length(Result) * 2);
      Result[n] := i + 1;
    end;
  SetLength(Result, n + 1);
end;

function LineOf(const AStarts: TTbOffsets; AOffset: Integer): Integer;
var
  lo, hi, mid: Integer;
begin
  { the last line whose start is at or before AOffset }
  lo := 1;
  hi := High(AStarts);
  while lo < hi do
  begin
    mid := (lo + hi + 1) div 2;
    if AStarts[mid] <= AOffset then
      lo := mid
    else
      hi := mid - 1;
  end;
  Result := lo;
end;

function ClampOffset(const AText: string; AOffset: Integer): Integer;
begin
  Result := AOffset;
  if Result < 1 then Result := 1;
  if Result > Length(AText) + 1 then Result := Length(AText) + 1;
end;

function TbOffsetToPoint(const AText: string; AOffset: Integer): TPoint;
var
  starts: TTbOffsets;
  y: Integer;
begin
  starts := LineStarts(AText);
  AOffset := ClampOffset(AText, AOffset);
  y := LineOf(starts, AOffset);
  Result := Point(AOffset - starts[y] + 1, y);
end;

function TbLineStart(const AText: string; AOffset: Integer): Integer;
var
  starts: TTbOffsets;
begin
  starts := LineStarts(AText);
  Result := starts[LineOf(starts, ClampOffset(AText, AOffset))];
end;

function TbLineIndent(const AText: string; AOffset: Integer): string;
var
  p, q: Integer;
begin
  p := TbLineStart(AText, AOffset);
  q := p;
  while (q <= Length(AText)) and (AText[q] in [' ', #9]) do
    Inc(q);
  Result := Copy(AText, p, q - p);
end;

function TbEndInsertPos(const AText: string): Integer;
var
  n: Integer;
begin
  n := Length(AText);
  if (n >= 2) and (AText[n - 1] = #13) and (AText[n] = #10) then
    Result := n - 1
  else if (n >= 1) and (AText[n] in [#10, #13]) then
    Result := n
  else
    Result := n + 1;
end;

function TbDetectEol(const AText: string): string;
var
  i: Integer;
begin
  for i := 1 to Length(AText) do
    if AText[i] = #10 then
      Exit(#10)
    else if AText[i] = #13 then
    begin
      if (i < Length(AText)) and (AText[i + 1] = #10) then
        Exit(#13#10);
      Exit(#13);
    end;
  Result := LineEnding;
end;

function TbEdit(AStart, AStop: Integer; const AText: string): TTbTextEdit;
begin
  Result.Start := AStart;
  Result.Stop := AStop;
  Result.Text := AText;
end;

function TbApplyEdits(const AText: string; const AEdits: TTbTextEdits): string;
var
  i: Integer;
begin
  Result := AText;
  for i := 0 to High(AEdits) do
  begin
    if (AEdits[i].Start < 1) or (AEdits[i].Stop < AEdits[i].Start)
       or (AEdits[i].Stop > Length(AText) + 1) then
      Exit;
    if (i > 0) and (AEdits[i].Start < AEdits[i - 1].Stop) then
      Exit;
  end;
  { back to front: an edit never moves the offsets of the ones before it }
  for i := High(AEdits) downto 0 do
    Result := Copy(Result, 1, AEdits[i].Start - 1) + AEdits[i].Text
      + Copy(Result, AEdits[i].Stop, MaxInt);
end;

function TbIsBlank(const AText: string): Boolean;
var
  i: Integer;
begin
  for i := 1 to Length(AText) do
    if not (AText[i] in [' ', #9, #10, #13]) then
      Exit(False);
  Result := True;
end;

{ ---- the walk ---- }

{ one past the value's last byte, walking back from the token that ended it over blanks and
  trailing comments -- never before AStart }
function ValueEndBefore(const AText: string; AStart, AStop: Integer): Integer;
var
  p, q: Integer;
begin
  p := AStop;
  while True do
  begin
    while (p > AStart) and (AText[p - 1] in [' ', #9, #10, #13]) do
      Dec(p);
    if (p - 2 >= AStart) and (AText[p - 1] = '/') and (AText[p - 2] = '*') then
    begin
      q := p - 3;
      while (q >= AStart) and not ((AText[q] = '/') and (AText[q + 1] = '*')) do
        Dec(q);
      if q < AStart then Break;
      p := q;
    end
    else
      Break;
  end;
  Result := p;
end;

type
  TScanner = class
  private
    FText: string;
    FStarts: TTbOffsets;
    FLex: TTyCssLexer;
    FScan: TTbCssScan;
    function Off(const ATok: TTyCssToken): Integer;
    procedure SkipBlockBody;
    procedure SkipStatementOrBlock;
    procedure ReadDecls(ABlock: TTbBlock; AOpen: Integer);
    procedure ReadMode(const AAt: TTyCssToken);
    procedure ReadRule(const AFirst: TTyCssToken);
  public
    constructor Create(const AText: string; AScan: TTbCssScan);
    destructor Destroy; override;
    procedure Run;
  end;

constructor TScanner.Create(const AText: string; AScan: TTbCssScan);
begin
  inherited Create;
  FText := AText;
  FStarts := LineStarts(AText);
  FLex := TTyCssLexer.Create(AText);
  FScan := AScan;
end;

destructor TScanner.Destroy;
begin
  FLex.Free;
  inherited Destroy;
end;

function TScanner.Off(const ATok: TTyCssToken): Integer;
begin
  if (ATok.Line < 1) or (ATok.Line > High(FStarts)) then
    Exit(Length(FText) + 1);
  Result := FStarts[ATok.Line] + ATok.Col - 1;
  if Result > Length(FText) + 1 then
    Result := Length(FText) + 1;
end;

{ the opening brace is taken: everything up to and with its matching closing brace (or the
  end) }
procedure TScanner.SkipBlockBody;
var
  depth: Integer;
  t: TTyCssToken;
begin
  depth := 1;
  repeat
    t := FLex.Next;
    case t.Kind of
      ctkLBrace: Inc(depth);
      ctkRBrace: Dec(depth);
      ctkEOF: Exit;
    end;
  until depth = 0;
end;

{ up to and with a ';' at this level, or a whole braced block, or a stray closing brace }
procedure TScanner.SkipStatementOrBlock;
var
  t: TTyCssToken;
begin
  while True do
  begin
    t := FLex.Next;
    case t.Kind of
      ctkSemicolon, ctkRBrace, ctkEOF: Exit;
      ctkLBrace:
        begin
          SkipBlockBody;
          Exit;
        end;
    end;
  end;
end;

procedure TScanner.ReadDecls(ABlock: TTbBlock; AOpen: Integer);
var
  t, stop: TTyCssToken;
  d: TTbDecl;
  n: Integer;
begin
  ABlock.OpenBrace := AOpen;
  while True do
  begin
    t := FLex.Peek;
    case t.Kind of
      ctkRBrace:
        begin
          ABlock.CloseBrace := Off(t);
          FLex.Next;
          Exit;
        end;
      ctkEOF:
        begin
          ABlock.CloseBrace := 0;
          Exit;
        end;
      ctkIdent:
        begin
          FLex.Next;
          if FLex.Peek.Kind <> ctkColon then
            Continue;
          FLex.Next;
          d := Default(TTbDecl);
          d.Name := t.Text;
          d.NameStart := Off(t);
          d.ValueStart := Off(FLex.Peek);
          while not (FLex.Peek.Kind in [ctkSemicolon, ctkRBrace, ctkEOF]) do
            FLex.Next;
          stop := FLex.Peek;
          d.ValueEnd := Max(d.ValueStart, ValueEndBefore(FText, d.ValueStart, Off(stop)));
          if stop.Kind = ctkSemicolon then
          begin
            d.StopAt := Off(stop);
            FLex.Next;
          end
          else
            d.StopAt := 0;
          n := Length(ABlock.Decls);
          SetLength(ABlock.Decls, n + 1);
          ABlock.Decls[n] := d;
        end;
    else
      FLex.Next;
    end;
  end;
end;

procedure TScanner.ReadMode(const AAt: TTyCssToken);
var
  t, colon, lb: TTyCssToken;
  mode: string;
  first, outer, i: Integer;
  blk: TTbBlock;
begin
  if FLex.Peek.Kind <> ctkIdent then
  begin
    SkipStatementOrBlock;
    Exit;
  end;
  mode := LowerCase(FLex.Next.Text);
  if FLex.Peek.Kind <> ctkLBrace then
  begin
    SkipStatementOrBlock;
    Exit;
  end;
  FLex.Next;
  first := FScan.Count;
  outer := 0;
  while True do
  begin
    t := FLex.Peek;
    case t.Kind of
      ctkRBrace:
        begin
          outer := Off(t);
          FLex.Next;
          Break;
        end;
      ctkEOF:
        begin
          outer := 0;
          Break;
        end;
      ctkColon:
        begin
          colon := FLex.Next;
          if (FLex.Peek.Kind = ctkIdent) and SameText(FLex.Peek.Text, 'root') then
          begin
            FLex.Next;
            if FLex.Peek.Kind = ctkLBrace then
            begin
              lb := FLex.Next;
              blk := TTbBlock.Create;
              blk.Kind := tbkModeRoot;
              blk.Mode := mode;
              blk.ModeStart := Off(AAt);
              blk.HeadStart := Off(colon);
              FScan.Add(blk);
              ReadDecls(blk, Off(lb));
            end;
          end;
        end;
      ctkLBrace:
        begin
          FLex.Next;
          SkipBlockBody;
        end;
    else
      FLex.Next;
    end;
  end;
  for i := first to FScan.Count - 1 do
    FScan.Block(i).OuterClose := outer;
end;

procedure TScanner.ReadRule(const AFirst: TTyCssToken);
var
  sels: array of TTbSelectorRef;
  sel: TTbSelectorRef;
  t, lb: TTyCssToken;
  blk: TTbBlock;
  broken: Boolean;
begin
  sels := nil;
  t := AFirst;
  broken := False;
  while True do
  begin
    sel := Default(TTbSelectorRef);
    sel.TypeName := t.Text;
    sel.Start := Off(t);
    if FLex.Peek.Kind = ctkDot then
    begin
      FLex.Next;
      if FLex.Peek.Kind = ctkIdent then
        sel.Variant := FLex.Next.Text
      else
        broken := True;
    end;
    if (not broken) and (FLex.Peek.Kind = ctkColon) then
    begin
      FLex.Next;
      if FLex.Peek.Kind = ctkIdent then
        sel.State := LowerCase(FLex.Next.Text)
      else
        broken := True;
    end;
    SetLength(sels, Length(sels) + 1);
    sels[High(sels)] := sel;
    if broken then Break;
    if FLex.Peek.Kind <> ctkComma then Break;
    FLex.Next;
    if FLex.Peek.Kind <> ctkIdent then
    begin
      broken := True;
      Break;
    end;
    t := FLex.Next;
  end;
  if (not broken) and (FLex.Peek.Kind = ctkLBrace) then
  begin
    lb := FLex.Next;
    blk := TTbBlock.Create;
    blk.Kind := tbkRule;
    blk.HeadStart := sels[0].Start;
    blk.Selectors := sels;
    FScan.Add(blk);
    ReadDecls(blk, Off(lb));
  end
  else
    SkipStatementOrBlock;
end;

procedure TScanner.Run;
var
  t, colon, lb: TTyCssToken;
  blk: TTbBlock;
  name, path: string;
begin
  while True do
  begin
    t := FLex.Next;
    case t.Kind of
      ctkEOF:
        Exit;
      ctkAtKeyword:
        begin
          name := LowerCase(t.Text);
          if name = 'import' then
          begin
            { the path: a string, or url(...) -- a string inside, or the bare path in pieces }
            path := '';
            t := FLex.Next;
            if t.Kind = ctkString then
              path := t.Text
            else if (t.Kind = ctkFunction) and SameText(t.Text, 'url') then
            begin
              t := FLex.Next;
              while not (t.Kind in [ctkRParen, ctkSemicolon, ctkEOF]) do
              begin
                if t.Kind = ctkHash then
                  path := path + '#' + t.Text
                else
                  path := path + t.Text;
                t := FLex.Next;
              end;
            end;
            while not (t.Kind in [ctkSemicolon, ctkEOF]) do
              t := FLex.Next;
            if t.Kind = ctkSemicolon then
              FScan.ImportEnd := Off(t) + 1;
            if Trim(path) <> '' then
            begin
              SetLength(FScan.Imports, Length(FScan.Imports) + 1);
              FScan.Imports[High(FScan.Imports)] := Trim(path);
            end;
          end
          else if name = 'mode' then
            ReadMode(t)
          else
            SkipStatementOrBlock;
        end;
      ctkColon:
        begin
          colon := t;
          if (FLex.Peek.Kind = ctkIdent) and SameText(FLex.Peek.Text, 'root') then
          begin
            FLex.Next;
            if FLex.Peek.Kind = ctkLBrace then
            begin
              lb := FLex.Next;
              blk := TTbBlock.Create;
              blk.Kind := tbkRoot;
              blk.HeadStart := Off(colon);
              FScan.Add(blk);
              ReadDecls(blk, Off(lb));
            end;
          end;
        end;
      ctkIdent:
        ReadRule(t);
    end;
    // anything else (a stray closing brace, a lone ';') is passed over
  end;
end;

function TbScanCss(const AText: string): TTbCssScan;
var
  s: TScanner;
begin
  Result := TTbCssScan.Create;
  Result.Text := AText;
  try
    s := TScanner.Create(AText, Result);
    try
      s.Run;
    finally
      s.Free;
    end;
  except
    { forgiving: what was scanned so far stands }
  end;
end;

function TbScanImports(const AText, ABaseDir: string): TTbCssScans;
var
  active, done: TStringList;

  procedure Follow(AScan: TTbCssScan; const ADir: string; ADepth: Integer);
  var
    i: Integer;
    raw, resolved, canon: string;
    sl: TStringList;
    child: TTbCssScan;
  begin
    if ADepth > 16 then Exit;
    for i := 0 to High(AScan.Imports) do
    begin
      raw := AScan.Imports[i];
      { as ExpandSheet: the path as written when that file is there, else from ADir }
      resolved := raw;
      if (ADir <> '') and not FileExists(resolved) and FileExists(ADir + raw) then
        resolved := ADir + raw;
      if not FileExists(resolved) then Continue;
      canon := LowerCase(ExpandFileName(resolved));
      if (active.IndexOf(canon) >= 0) or (done.IndexOf(canon) >= 0) then Continue;
      child := nil;
      sl := TStringList.Create;
      try
        try
          sl.LoadFromFile(resolved);
          child := TbScanCss(sl.Text);
        except
          child := nil;
        end;
      finally
        sl.Free;
      end;
      if child = nil then Continue;
      active.Add(canon);
      done.Add(canon);
      try
        Follow(child, ExtractFilePath(ExpandFileName(resolved)), ADepth + 1);
      finally
        active.Delete(active.IndexOf(canon));
      end;
      { after what it imports: the model adds a file on top of its own imports }
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := child;
    end;
  end;

var
  root: TTbCssScan;
  dir: string;
begin
  Result := nil;
  if ABaseDir <> '' then
    dir := ExtractFilePath(ExpandFileName(IncludeTrailingPathDelimiter(ABaseDir)))
  else
    dir := '';
  root := TbScanCss(AText);
  active := TStringList.Create;
  done := TStringList.Create;
  try
    Follow(root, dir, 0);
  finally
    active.Free;
    done.Free;
    root.Free;
  end;
end;

procedure TbFreeScans(var AScans: TTbCssScans);
var
  i: Integer;
begin
  for i := 0 to High(AScans) do
    AScans[i].Free;
  AScans := nil;
end;

end.
