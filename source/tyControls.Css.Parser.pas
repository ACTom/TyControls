unit tyControls.Css.Parser;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, tyControls.Types, tyControls.Css.Tokens, tyControls.Css.Lexer;

type
  TTyCssSelector = record
    TypeName: string;
    Variant: string;
    State: TTyState;
    HasState: Boolean;
  end;

  TTyCssDeclaration = record
    Prop: string;
    RawValue: string;
  end;

  TTyCssRule = class
    Selectors: array of TTyCssSelector;
    Declarations: array of TTyCssDeclaration;
  end;

  TTyCssStylesheet = class
    Rules: TFPList;
    RootVars: TStringList;
    Imports: array of string;   // raw @import paths, source order (parser does NO file I/O)
    constructor Create;
    destructor Destroy; override;
  end;

  ETyCssError = class(Exception);

  TTyCssParser = class
  private
    FLexer: TTyCssLexer;
    FSawRule: Boolean;   // set once a rule/:root has parsed; @import after it is an error
    function Expect(AKind: TTyCssTokenKind): TTyCssToken;
    procedure Error(const AMsg: string; const ATok: TTyCssToken);
    function PseudoToState(const AName: string; const ATok: TTyCssToken): TTyState;
    function ParseSelector: TTyCssSelector;
    function ReadRawValue: string;
    procedure ParseRootBlock(ASheet: TTyCssStylesheet);
    procedure ParseRule(ASheet: TTyCssStylesheet);
    procedure ParseAtRule(ASheet: TTyCssStylesheet; const ATok: TTyCssToken);
    procedure ParseImport(ASheet: TTyCssStylesheet; const ATok: TTyCssToken);
  public
    constructor Create(const ASource: string);
    destructor Destroy; override;
    function Parse: TTyCssStylesheet;
  end;

implementation

constructor TTyCssStylesheet.Create;
begin
  inherited Create;
  Rules := TFPList.Create;
  RootVars := TStringList.Create;
end;

destructor TTyCssStylesheet.Destroy;
var
  i: Integer;
begin
  if Assigned(Rules) then
  begin
    for i := 0 to Rules.Count - 1 do
      TTyCssRule(Rules[i]).Free;
    Rules.Free;
  end;
  RootVars.Free;
  inherited Destroy;
end;

constructor TTyCssParser.Create(const ASource: string);
begin
  inherited Create;
  FLexer := TTyCssLexer.Create(ASource);
end;

destructor TTyCssParser.Destroy;
begin
  FLexer.Free;
  inherited Destroy;
end;

procedure TTyCssParser.Error(const AMsg: string; const ATok: TTyCssToken);
begin
  raise ETyCssError.CreateFmt('%s at line %d, col %d (got "%s")',
    [AMsg, ATok.Line, ATok.Col, ATok.Text]);
end;

function TTyCssParser.Expect(AKind: TTyCssTokenKind): TTyCssToken;
begin
  Result := FLexer.Next;
  if Result.Kind <> AKind then
    Error('Unexpected token', Result);
end;

function TTyCssParser.PseudoToState(const AName: string; const ATok: TTyCssToken): TTyState;
var
  n: string;
begin
  n := LowerCase(AName);
  if n = 'hover' then
    Result := tysHover
  else if n = 'active' then
    Result := tysActive
  else if n = 'focus' then
    Result := tysFocused
  else if n = 'disabled' then
    Result := tysDisabled
  else
  begin
    Error('Unknown pseudo-class "' + AName + '"', ATok);
    Result := tysNormal; // unreachable; silences warning
  end;
end;

function TTyCssParser.ParseSelector: TTyCssSelector;
var
  tok: TTyCssToken;
begin
  Result.TypeName := '';
  Result.Variant := '';
  Result.State := tysNormal;
  Result.HasState := False;

  tok := Expect(ctkIdent);
  Result.TypeName := tok.Text;

  // optional .variant
  if FLexer.Peek.Kind = ctkDot then
  begin
    FLexer.Next; // consume dot
    tok := Expect(ctkIdent);
    Result.Variant := tok.Text;
  end;

  // optional :state
  if FLexer.Peek.Kind = ctkColon then
  begin
    FLexer.Next; // consume colon
    tok := Expect(ctkIdent);
    Result.State := PseudoToState(tok.Text, tok);
    Result.HasState := True;
  end;
end;

function TTyCssParser.ReadRawValue: string;
var
  tok: TTyCssToken;
  sb: string;
  depth: Integer;

  // Insert a separating space when needed: only when sb is non-empty and the
  // last character is neither a space nor an opening paren (so tokens inside
  // function argument lists, and adjacent unit suffixes, are not separated).
  procedure NeedSep;
  begin
    if (sb <> '') and (sb[Length(sb)] <> ' ') and (sb[Length(sb)] <> '(') then
      sb := sb + ' ';
  end;

begin
  sb := '';
  depth := 0;
  while True do
  begin
    tok := FLexer.Peek;
    case tok.Kind of
      ctkSemicolon, ctkRBrace, ctkEOF:
        Break;
      ctkColon:
        begin
          // A colon at depth=0 signals a new property declaration (missing semicolon).
          // Only consume colons inside parentheses (e.g. url(...)).
          if depth = 0 then
            Break;
          FLexer.Next;
          sb := sb + ':';
        end;
      ctkHash:
        begin FLexer.Next; NeedSep; sb := sb + '#' + tok.Text; end;
      ctkPercent:
        begin FLexer.Next; sb := sb + '%'; end;
      ctkFunction:
        begin FLexer.Next; NeedSep; sb := sb + tok.Text + '('; Inc(depth); end;
      ctkString:
        begin FLexer.Next; NeedSep; sb := sb + '"' + tok.Text + '"'; end;
      ctkComma:
        begin FLexer.Next; sb := sb + ', '; end;
      ctkLParen:
        begin FLexer.Next; sb := sb + '('; Inc(depth); end;
      ctkRParen:
        begin
          FLexer.Next;
          sb := sb + ')';
          if depth > 0 then
            Dec(depth);
        end;
      ctkDot:
        begin FLexer.Next; sb := sb + '.'; end;
    else
      begin
        FLexer.Next;
        if sb = '' then
          sb := tok.Text
        else if (tok.Kind = ctkIdent) and (Length(sb) > 0) and
                (sb[Length(sb)] = '(') then
          // glue ident immediately after '(' — e.g. var(--x), url(foo)
          sb := sb + tok.Text
        else if (tok.Kind = ctkIdent) and (Length(sb) > 0) and
                (sb[Length(sb)] in ['0'..'9']) and
                (LowerCase(tok.Text) = 'px') then
          // glue 'px' unit onto a preceding digit — e.g. 6px, 12px
          sb := sb + tok.Text
        else
        begin
          // insert a separating space, but never produce two consecutive spaces
          // and never insert a space directly after '(' or after a space
          NeedSep;
          sb := sb + tok.Text;
        end;
      end;
    end;
  end;
  Result := Trim(sb);
end;

procedure TTyCssParser.ParseRootBlock(ASheet: TTyCssStylesheet);
var
  tok, nameTok: TTyCssToken;
  raw: string;
begin
  // ':root' ident already consumed by caller; expect '{'
  FSawRule := True;   // @import must precede :root/rules
  Expect(ctkLBrace);
  while True do
  begin
    tok := FLexer.Peek;
    if tok.Kind = ctkRBrace then
    begin
      FLexer.Next;
      Break;
    end;
    if tok.Kind = ctkEOF then
      Error('Unterminated :root block', tok);
    // expect identifier of form --name (lexer yields ctkIdent '--name')
    nameTok := Expect(ctkIdent);
    if Copy(nameTok.Text, 1, 2) <> '--' then
      Error('Expected --variable name', nameTok);
    Expect(ctkColon);
    raw := ReadRawValue;
    Expect(ctkSemicolon);
    ASheet.RootVars.Values[Copy(nameTok.Text, 3, Length(nameTok.Text) - 2)] := raw;
  end;
end;

procedure TTyCssParser.ParseRule(ASheet: TTyCssStylesheet);
var
  rule: TTyCssRule;
  sel: TTyCssSelector;
  tok, propTok: TTyCssToken;
  raw: string;
begin
  FSawRule := True;   // @import must precede all style rules
  rule := TTyCssRule.Create;
  try
    // selector list
    SetLength(rule.Selectors, 1);
    rule.Selectors[0] := ParseSelector;
    while FLexer.Peek.Kind = ctkComma do
    begin
      FLexer.Next; // consume comma
      sel := ParseSelector;
      SetLength(rule.Selectors, Length(rule.Selectors) + 1);
      rule.Selectors[High(rule.Selectors)] := sel;
    end;

    Expect(ctkLBrace);

    while True do
    begin
      tok := FLexer.Peek;
      if tok.Kind = ctkRBrace then
      begin
        FLexer.Next;
        Break;
      end;
      if tok.Kind = ctkEOF then
        Error('Unterminated rule block', tok);
      propTok := Expect(ctkIdent);
      Expect(ctkColon);
      raw := ReadRawValue;
      Expect(ctkSemicolon);
      SetLength(rule.Declarations, Length(rule.Declarations) + 1);
      rule.Declarations[High(rule.Declarations)].Prop := propTok.Text;
      rule.Declarations[High(rule.Declarations)].RawValue := raw;
    end;

    ASheet.Rules.Add(rule);
    rule := nil;
  finally
    rule.Free;
  end;
end;

procedure TTyCssParser.ParseImport(ASheet: TTyCssStylesheet; const ATok: TTyCssToken);
{ Grammar: '@import <string|url(<string|ident>)> ;'. The parser only COLLECTS the raw
  path into ASheet.Imports (in source order); StyleModel performs the recursive file
  load + splice. '@import' must precede every :root/rule (FSawRule guard). }
var
  pathStr: string;
  next, inner: TTyCssToken;
begin
  if FSawRule then
    Error('An @import must precede all style rules', ATok);
  next := FLexer.Peek;
  if next.Kind = ctkString then
  begin
    FLexer.Next;
    pathStr := next.Text;
  end
  else if (next.Kind = ctkFunction) and SameText(next.Text, 'url') then
  begin
    FLexer.Next; // consume 'url(' (the lexer already ate the '(')
    inner := FLexer.Next;
    if inner.Kind = ctkString then
      pathStr := inner.Text
    else if inner.Kind = ctkIdent then
      pathStr := inner.Text
    else
      Error('Expected a path inside url() for @import', inner);
    Expect(ctkRParen);
  end
  else
    Error('Expected a quoted path or url() after @import', next);
  Expect(ctkSemicolon);
  SetLength(ASheet.Imports, Length(ASheet.Imports) + 1);
  ASheet.Imports[High(ASheet.Imports)] := pathStr;
end;

procedure TTyCssParser.ParseAtRule(ASheet: TTyCssStylesheet; const ATok: TTyCssToken);
{ ATok is the ctkAtKeyword already consumed by the caller. Dispatch on the (lower-cased)
  at-keyword name. Today only '@import' (A8) is handled; unknown at-rules are a hard error
  (the shared dispatcher is where P3's '@mode' will hook in). }
var
  name: string;
begin
  name := LowerCase(ATok.Text);
  if name = 'import' then
    ParseImport(ASheet, ATok)
  else if name = '' then
    Error('Expected an at-rule name after "@"', ATok)
  else
    Error('Unknown at-rule "@' + ATok.Text + '"', ATok);
end;

function TTyCssParser.Parse: TTyCssStylesheet;
var
  tok: TTyCssToken;
begin
  FSawRule := False;
  Result := TTyCssStylesheet.Create;
  try
    while True do
    begin
      tok := FLexer.Peek;
      if tok.Kind = ctkEOF then
        Break;
      if tok.Kind = ctkAtKeyword then
      begin
        FLexer.Next; // consume the at-keyword
        ParseAtRule(Result, tok);
      end
      else if (tok.Kind = ctkColon) then
      begin
        // ':root'
        FLexer.Next; // consume ':'
        tok := Expect(ctkIdent);
        if LowerCase(tok.Text) <> 'root' then
          Error('Expected "root" after ":"', tok);
        ParseRootBlock(Result);
      end
      else if tok.Kind = ctkIdent then
        ParseRule(Result)
      else
        Error('Expected selector or :root', tok);
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
