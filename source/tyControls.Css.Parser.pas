unit tyControls.Css.Parser;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, tyControls.Types, tyControls.Css.Tokens, tyControls.Css.Lexer,
  tyControls.StrConsts;

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

  { One '@mode IDENT ( :root ( … ) )' conditional token block (P3, D7); braces shown as
    parens in this comment. Carries the mode name and the --vars its inner :root declares
    (name=value, no leading --). The parser only COLLECTS these; StyleModel copies the
    active mode's vars into model-owned storage at load and overlays them on top of the
    user :root in RebuildMergedVars. }
  TTyCssModeBlock = class
    Mode: string;
    Vars: TStringList;
    constructor Create;
    destructor Destroy; override;
  end;

  TTyCssStylesheet = class
    Rules: TFPList;
    RootVars: TStringList;
    Imports: array of string;   // raw @import paths, source order (parser does NO file I/O)
    ModeBlocks: TFPList;        // owns TTyCssModeBlock (P3 @mode blocks, source order)
    constructor Create;
    destructor Destroy; override;
  end;

  { Line / Col: where the parser stopped, 1-based, the column counted in bytes (what
    SynEdit calls the logical column), in the text that parser was given: for a parse
    error inside an @import-ed file the style model lets the child parser's error through,
    so they are that FILE's line and column, not the entry document's. 0 for the errors the
    style model raises itself (an @import it cannot find, a cycle, too deep, an empty path,
    a nil source). }
  ETyCssError = class(Exception)
  private
    FLine, FCol: Integer;
  public
    property Line: Integer read FLine write FLine;
    property Col: Integer read FCol write FCol;
  end;

  TTyCssParser = class
  private
    FLexer: TTyCssLexer;
    FSawRule: Boolean;   // set once a rule/:root has parsed; @import after it is an error
    function Expect(AKind: TTyCssTokenKind): TTyCssToken;
    procedure Error(const AMsg: string; const ATok: TTyCssToken);
    function PseudoToState(const AName: string; const ATok: TTyCssToken): TTyState;
    function ParseSelector: TTyCssSelector;
    function ReadRawValue: string;
    procedure ParseRootInto(AVars: TStringList);
    procedure ParseRootBlock(ASheet: TTyCssStylesheet);
    procedure ParseRule(ASheet: TTyCssStylesheet);
    procedure ParseAtRule(ASheet: TTyCssStylesheet; const ATok: TTyCssToken);
    procedure ParseImport(ASheet: TTyCssStylesheet; const ATok: TTyCssToken);
    procedure ParseModeBlock(ASheet: TTyCssStylesheet; const ATok: TTyCssToken);
  public
    constructor Create(const ASource: string);
    destructor Destroy; override;
    function Parse: TTyCssStylesheet;
  end;

  TTyCssDeclarationArray = array of TTyCssDeclaration;

{ Parse a BARE declaration block (no selector) — the per-instance StyleOverride (A9)
  fragment, e.g. 'background:#f00; border-color: var(--accent);'. Wraps the fragment as
  a synthetic _ovr rule (selector plus a brace-wrapped body), runs the existing parser,
  and lifts Rules[0]'s raw declarations (the selector is discarded). Returns False on
  ANY parse error (with an
  empty ADecls) so a malformed override never crashes painting (the model treats it as
  empty). An empty/blank fragment yields True with zero declarations. }
function TyParseOverride(const ASource: string; out ADecls: TTyCssDeclarationArray): Boolean;

{ #226. AOverride -- a StyleOverride fragment -- with ONE declaration changed, and the rest
  handed back as it was written: every other declaration, its spacing, its comments and its
  line breaks, byte for byte. For a property that is a view of a token in the control's own
  StyleOverride (TTyTabCloseButton): the form's author may have typed the rest by hand.

    AValue <> ''   the declaration of AName gets that value where it stands (the LAST one,
                   which is the one the engine reads; a value it already has changes nothing).
                   With none, 'AName: AValue;' is added after the last declaration -- on a line
                   of its own when the override is written over several lines.
    AValue = ''    every declaration of AName is taken out, with its semicolon. A comment in
                   front of it stays.

  AName is the whole name, '--' included, and is matched without case, as the engine matches
  it; a declaration keeps the spelling its author gave it. A ';' inside a string, inside
  parentheses or inside a comment separates nothing. AValue is written as given: it is the
  caller's to keep free of ';'. The text is scanned, not parsed -- an override the parser
  refuses is rewritten the same way and stays refused. }
function TyOverrideWith(const AOverride, AName, AValue: string): string;
{ #226. The value AOverride declares for AName, as written (trimmed; of several, the last).
  False, and '', when it declares none. Not resolved: 'var(--x)' comes back as that. }
function TyOverrideDeclared(const AOverride, AName: string; out AValue: string): Boolean;

const
  { The pseudo-class names a selector may carry -- an enumerable mirror of PseudoToState (this
    unit). Unknown pseudo-classes raise, so this is what an editor should offer for the ':' part
    of a selector. 'checked' is an alias of 'selected' (both -> tysSelected). test.css.catalog
    pins it: each parses in a selector, an unknown one fails. }
  TyKnownPseudoStates: array[0..5] of string =
    ('hover', 'active', 'focus', 'disabled', 'selected', 'checked');

implementation

constructor TTyCssModeBlock.Create;
begin
  inherited Create;
  Vars := TStringList.Create;
end;

destructor TTyCssModeBlock.Destroy;
begin
  Vars.Free;
  inherited Destroy;
end;

constructor TTyCssStylesheet.Create;
begin
  inherited Create;
  Rules := TFPList.Create;
  RootVars := TStringList.Create;
  ModeBlocks := TFPList.Create;
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
  if Assigned(ModeBlocks) then
  begin
    for i := 0 to ModeBlocks.Count - 1 do
      TTyCssModeBlock(ModeBlocks[i]).Free;
    ModeBlocks.Free;
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
var
  e: ETyCssError;
begin
  e := ETyCssError.CreateFmt(rsCssErrorFrame,
    [AMsg, ATok.Line, ATok.Col, ATok.Text]);
  e.Line := ATok.Line;
  e.Col := ATok.Col;
  raise e;
end;

function TTyCssParser.Expect(AKind: TTyCssTokenKind): TTyCssToken;
begin
  Result := FLexer.Next;
  if Result.Kind <> AKind then
    Error(rsCssUnexpectedToken, Result);
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
  else if (n = 'selected') or (n = 'checked') then
    Result := tysSelected
  else
  begin
    Error(Format(rsCssUnknownPseudoClass, [AName]), ATok);
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

procedure TTyCssParser.ParseRootInto(AVars: TStringList);
{ Parse the body of a ':root' block (the brace-delimited declaration list), writing each
  '--name: value;' into AVars (name without leading --). ':root' is already consumed by the
  caller; the opening brace is expected here. Shared by the top-level :root and the
  @mode-block inner :root. }
var
  tok, nameTok: TTyCssToken;
  raw: string;
begin
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
      Error(rsCssUnterminatedRootBlock, tok);
    // expect identifier of form --name (lexer yields ctkIdent '--name')
    nameTok := Expect(ctkIdent);
    if Copy(nameTok.Text, 1, 2) <> '--' then
      Error(rsCssExpectedVariableName, nameTok);
    Expect(ctkColon);
    raw := ReadRawValue;
    Expect(ctkSemicolon);
    AVars.Values[Copy(nameTok.Text, 3, Length(nameTok.Text) - 2)] := raw;
  end;
end;

procedure TTyCssParser.ParseRootBlock(ASheet: TTyCssStylesheet);
begin
  // ':root' ident already consumed by caller; expect '{'
  FSawRule := True;   // @import must precede :root/rules
  ParseRootInto(ASheet.RootVars);
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
        Error(rsCssUnterminatedRuleBlock, tok);
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
    Error(rsCssImportMustPrecedeRules, ATok);
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
      Error(rsCssExpectedPathInUrl, inner);
    Expect(ctkRParen);
  end
  else
    Error(rsCssExpectedPathAfterImport, next);
  Expect(ctkSemicolon);
  SetLength(ASheet.Imports, Length(ASheet.Imports) + 1);
  ASheet.Imports[High(ASheet.Imports)] := pathStr;
end;

procedure TTyCssParser.ParseModeBlock(ASheet: TTyCssStylesheet; const ATok: TTyCssToken);
{ Grammar (braces shown as parens in this comment): '@mode IDENT ( :root ( --x: v; … ) )'
  (P3, D7). Reads the mode identifier, the wrapping brace, then one (or more) inner ':root'
  blocks whose vars are collected into a fresh TTyCssModeBlock on ASheet.ModeBlocks. Mode
  blocks may appear after rules (they carry tokens, not @import file refs), so there is no
  FSawRule guard here — but a mode block does NOT set FSawRule (only :root/rules close the
  @import window). }
var
  nameTok, tok, innerTok: TTyCssToken;
  block: TTyCssModeBlock;
begin
  nameTok := FLexer.Peek;
  if nameTok.Kind <> ctkIdent then
    Error(rsCssExpectedModeName, nameTok);
  FLexer.Next;   // consume the mode ident
  block := TTyCssModeBlock.Create;
  try
    block.Mode := nameTok.Text;
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
        Error(rsCssUnterminatedModeBlock, tok);
      // inner ':root' block — the only construct allowed inside @mode (v1)
      if tok.Kind = ctkColon then
      begin
        FLexer.Next; // consume ':'
        innerTok := Expect(ctkIdent);
        if LowerCase(innerTok.Text) <> 'root' then
          Error(rsCssExpectedRootInMode, innerTok);
        ParseRootInto(block.Vars);
      end
      else
        Error(rsCssOnlyRootInMode, tok);
    end;
    ASheet.ModeBlocks.Add(block);
    block := nil;
  finally
    block.Free;
  end;
end;

procedure TTyCssParser.ParseAtRule(ASheet: TTyCssStylesheet; const ATok: TTyCssToken);
{ ATok is the ctkAtKeyword already consumed by the caller. Dispatch on the (lower-cased)
  at-keyword name. '@import' (A8) collects a file ref; '@mode' (P3, D7) collects a
  conditional :root token block. Unknown at-rules are a hard error. }
var
  name: string;
begin
  name := LowerCase(ATok.Text);
  if name = 'import' then
    ParseImport(ASheet, ATok)
  else if name = 'mode' then
    ParseModeBlock(ASheet, ATok)
  else if name = '' then
    Error(rsCssExpectedAtRuleName, ATok)
  else
    Error(Format(rsCssUnknownAtRule, [ATok.Text]), ATok);
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
          Error(rsCssExpectedRootAfterColon, tok);
        ParseRootBlock(Result);
      end
      else if tok.Kind = ctkIdent then
        ParseRule(Result)
      else
        Error(rsCssExpectedSelectorOrRoot, tok);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TyParseOverride(const ASource: string; out ADecls: TTyCssDeclarationArray): Boolean;
var
  parser: TTyCssParser;
  sheet: TTyCssStylesheet;
  rule: TTyCssRule;
  i: Integer;
  body: string;
begin
  Result := False;
  SetLength(ADecls, 0);
  body := Trim(ASource);
  if body = '' then
  begin
    Result := True;   // empty override: valid, contributes nothing
    Exit;
  end;
  // The grammar requires a ';' after EVERY declaration; a bare fragment commonly omits
  // the trailing one (CSS makes the last semicolon optional). Normalize: drop a trailing
  // ';' then append exactly one, so both 'a:1' and 'a:1;' parse and 'a:1;;' is avoided.
  while (body <> '') and (body[Length(body)] = ';') do
    body := TrimRight(Copy(body, 1, Length(body) - 1));
  try
    // Wrap as a synthetic rule so the existing selector{...} grammar parses the block;
    // '_ovr' is a throwaway ident — only the declarations are kept.
    parser := TTyCssParser.Create('_ovr{' + body + ';}');
    try
      sheet := parser.Parse;
      try
        if (sheet.Rules <> nil) and (sheet.Rules.Count > 0) then
        begin
          rule := TTyCssRule(sheet.Rules[0]);
          SetLength(ADecls, Length(rule.Declarations));
          for i := 0 to High(rule.Declarations) do
            ADecls[i] := rule.Declarations[i];
        end;
        Result := True;
      finally
        sheet.Free;
      end;
    finally
      parser.Free;
    end;
  except
    on E: Exception do
    begin
      SetLength(ADecls, 0);
      Result := False;   // malformed fragment -> empty override, never propagate
    end;
  end;
end;

{ ---- #226: one declaration of an override, rewritten in place ---- }

type
  { One stretch of an override between two top-level semicolons. Its text is
    Copy(S, Start, Stop - Start); Stop is where its ';' stands (Closed) or one past the end.
    NameAt = 0 when it declares nothing (blank, or a comment alone). ValueAt is the first
    character after the ':'. }
  TTyOvrSeg = record
    Start, Stop: Integer;
    Closed: Boolean;
    NameAt, NameLen, ValueAt: Integer;
  end;
  TTyOvrSegArray = array of TTyOvrSeg;

const
  TyOvrBlank = [' ', #9, #10, #13];

{ Past the blanks and the comments that start at APos, never beyond AStop. }
function TyOvrSkipBlank(const S: string; APos, AStop: Integer): Integer;
begin
  Result := APos;
  while Result < AStop do
    if S[Result] in TyOvrBlank then
      Inc(Result)
    else if (S[Result] = '/') and (Result + 1 < AStop) and (S[Result + 1] = '*') then
    begin
      Inc(Result, 2);
      while (Result < AStop) and not ((S[Result] = '*') and (Result + 1 < AStop)
                                      and (S[Result + 1] = '/')) do
        Inc(Result);
      Inc(Result, 2);
      if Result > AStop then Result := AStop;
    end
    else
      Break;
end;

procedure TyOvrScan(const S: string; out ASegs: TTyOvrSegArray);
var
  i, n, depth, start, count: Integer;
  quote: Char;

  procedure Add(AStop: Integer; AClosed: Boolean);
  var
    p: Integer;
  begin
    if count = Length(ASegs) then SetLength(ASegs, count * 2 + 8);
    ASegs[count].Start := start;
    ASegs[count].Stop := AStop;
    ASegs[count].Closed := AClosed;
    ASegs[count].NameAt := 0;
    ASegs[count].NameLen := 0;
    ASegs[count].ValueAt := 0;
    p := TyOvrSkipBlank(S, start, AStop);
    ASegs[count].NameAt := p;
    while (p < AStop) and (S[p] in ['a'..'z', 'A'..'Z', '0'..'9', '_', '-']) do Inc(p);
    ASegs[count].NameLen := p - ASegs[count].NameAt;
    p := TyOvrSkipBlank(S, p, AStop);
    if (ASegs[count].NameLen > 0) and (p < AStop) and (S[p] = ':') then
      ASegs[count].ValueAt := p + 1
    else
    begin
      ASegs[count].NameAt := 0;
      ASegs[count].NameLen := 0;
    end;
    Inc(count);
  end;

begin
  SetLength(ASegs, 0);
  count := 0;
  n := Length(S);
  start := 1;
  depth := 0;
  i := 1;
  while i <= n do
  begin
    case S[i] of
      '/':
        if (i < n) and (S[i + 1] = '*') then
        begin
          Inc(i, 2);
          while (i <= n) and not ((S[i] = '*') and (i < n) and (S[i + 1] = '/')) do Inc(i);
          Inc(i);   // onto the '/', or past the end of a comment that never closes
        end;
      '"', '''':
        begin
          quote := S[i];
          Inc(i);
          while (i <= n) and (S[i] <> quote) do Inc(i);
        end;
      '(': Inc(depth);
      ')': if depth > 0 then Dec(depth);
      ';':
        if depth = 0 then
        begin
          Add(i, True);
          start := i + 1;
        end;
    end;
    Inc(i);
  end;
  if start <= n then Add(n + 1, False);
  SetLength(ASegs, count);
end;

function TyOvrDeclares(const S: string; const ASeg: TTyOvrSeg; const AName: string): Boolean;
begin
  Result := (ASeg.NameAt > 0) and (ASeg.NameLen = Length(AName))
    and SameText(Copy(S, ASeg.NameAt, ASeg.NameLen), AName);
end;

function TyOvrIsBlank(const S: string): Boolean;
var
  i: Integer;
begin
  for i := 1 to Length(S) do
    if not (S[i] in TyOvrBlank) then Exit(False);
  Result := True;
end;

function TyOverrideDeclared(const AOverride, AName: string; out AValue: string): Boolean;
var
  segs: TTyOvrSegArray;
  i: Integer;
begin
  AValue := '';
  Result := False;
  TyOvrScan(AOverride, segs);
  for i := High(segs) downto 0 do
    if TyOvrDeclares(AOverride, segs[i], AName) then
    begin
      AValue := Trim(Copy(AOverride, segs[i].ValueAt, segs[i].Stop - segs[i].ValueAt));
      Exit(True);
    end;
end;

function TyOverrideWith(const AOverride, AName, AValue: string): string;
var
  segs: TTyOvrSegArray;
  i, last: Integer;
  body, lead, nl, tail: string;
begin
  TyOvrScan(AOverride, segs);
  last := -1;
  for i := 0 to High(segs) do
    if TyOvrDeclares(AOverride, segs[i], AName) then last := i;

  if AValue = '' then
  begin
    if last < 0 then Exit(AOverride);
    Result := '';
    for i := 0 to High(segs) do
      if TyOvrDeclares(AOverride, segs[i], AName) then
      begin
        { The declaration goes with the blanks before it and its ';'. What stands before
          it and is not blank -- a comment -- stays. }
        lead := Copy(AOverride, segs[i].Start, segs[i].NameAt - segs[i].Start);
        if not TyOvrIsBlank(lead) then Result := Result + TrimRight(lead);
      end
      else
      begin
        Result := Result + Copy(AOverride, segs[i].Start, segs[i].Stop - segs[i].Start);
        if segs[i].Closed then Result := Result + ';';
      end;
    { What followed the first declaration now comes first: without the blank that parted
      them. Blanks the override began with before another declaration are its author's. }
    if TyOvrDeclares(AOverride, segs[0], AName)
       and TyOvrIsBlank(Copy(AOverride, segs[0].Start, segs[0].NameAt - segs[0].Start)) then
      Result := TrimLeft(Result);
    Exit;
  end;

  if last >= 0 then
  begin
    if Trim(Copy(AOverride, segs[last].ValueAt, segs[last].Stop - segs[last].ValueAt)) = AValue then
      Exit(AOverride);
    Exit(Copy(AOverride, 1, segs[last].NameAt + segs[last].NameLen - 1) + ': ' + AValue
         + Copy(AOverride, segs[last].Stop, MaxInt));
  end;

  body := TrimRight(AOverride);
  if body = '' then Exit(AName + ': ' + AValue + ';');
  if Pos(#13#10, AOverride) > 0 then nl := #13#10
  else if Pos(#10, AOverride) > 0 then nl := #10
  else nl := '';
  tail := '';
  if (nl <> '') and (Pos(#10, Copy(AOverride, Length(body) + 1, MaxInt)) > 0) then tail := nl;
  { An open last declaration is closed first. Asked of the scan, not of the last character:
    a ';' that ends a comment or a string closes nothing -- and a comment standing alone
    after the last ';' is nothing to close: a ';' put after it would be an empty declaration,
    which the parser refuses, and the whole override with it. }
  if (Length(segs) > 0) and not segs[High(segs)].Closed
     and (TyOvrSkipBlank(AOverride, segs[High(segs)].Start, segs[High(segs)].Stop)
          < segs[High(segs)].Stop) then
    body := body + ';';
  if nl = '' then
    Result := body + ' ' + AName + ': ' + AValue + ';'
  else
    Result := body + nl + AName + ': ' + AValue + ';' + tail;
end;

end.
