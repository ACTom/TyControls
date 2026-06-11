unit tyControls.Css.Lexer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, tyControls.Css.Tokens;

type
  TTyCssLexer = class
  private
    FSource: string;
    FPos: Integer;
    FLine, FCol: Integer;
    FHasPeek: Boolean;
    FPeeked: TTyCssToken;
    function CurChar: Char;
    function PeekChar(AOffset: Integer): Char;
    procedure Advance;
    procedure SkipWhitespaceAndComments;
    function MakeToken(AKind: TTyCssTokenKind; const AText: string;
      ALine, ACol: Integer): TTyCssToken;
    function ReadToken: TTyCssToken;
  public
    constructor Create(const ASource: string);
    function Next: TTyCssToken;
    function Peek: TTyCssToken;
  end;

implementation

constructor TTyCssLexer.Create(const ASource: string);
begin
  inherited Create;
  FSource := ASource;
  FPos := 1;
  FLine := 1;
  FCol := 1;
  FHasPeek := False;
end;

function TTyCssLexer.CurChar: Char;
begin
  if FPos <= Length(FSource) then
    Result := FSource[FPos]
  else
    Result := #0;
end;

function TTyCssLexer.PeekChar(AOffset: Integer): Char;
var
  p: Integer;
begin
  p := FPos + AOffset;
  if (p >= 1) and (p <= Length(FSource)) then
    Result := FSource[p]
  else
    Result := #0;
end;

procedure TTyCssLexer.Advance;
begin
  if FPos > Length(FSource) then
    Exit;
  if FSource[FPos] = #10 then
  begin
    Inc(FLine);
    FCol := 1;
  end
  else if FSource[FPos] = #13 then
  begin
    // treat CR as line break unless followed by LF (LF handles it)
    if PeekChar(1) <> #10 then
    begin
      Inc(FLine);
      FCol := 1;
    end
    else
      Inc(FCol);
  end
  else
    Inc(FCol);
  Inc(FPos);
end;

procedure TTyCssLexer.SkipWhitespaceAndComments;
begin
  while FPos <= Length(FSource) do
  begin
    if CurChar in [' ', #9, #10, #13] then
      Advance
    else if (CurChar = '/') and (PeekChar(1) = '*') then
    begin
      Advance; // '/'
      Advance; // '*'
      while FPos <= Length(FSource) do
      begin
        if (CurChar = '*') and (PeekChar(1) = '/') then
        begin
          Advance; // '*'
          Advance; // '/'
          Break;
        end
        else
          Advance;
      end;
    end
    else
      Break;
  end;
end;

function TTyCssLexer.MakeToken(AKind: TTyCssTokenKind; const AText: string;
  ALine, ACol: Integer): TTyCssToken;
begin
  Result.Kind := AKind;
  Result.Text := AText;
  Result.Line := ALine;
  Result.Col := ACol;
end;

function TTyCssLexer.ReadToken: TTyCssToken;
var
  startLine, startCol: Integer;
  s: string;
  quote: Char;
begin
  SkipWhitespaceAndComments;
  startLine := FLine;
  startCol := FCol;

  if FPos > Length(FSource) then
    Exit(MakeToken(ctkEOF, '', startLine, startCol));

  // Hash color
  if CurChar = '#' then
  begin
    Advance;
    s := '';
    while CurChar in ['0'..'9', 'a'..'f', 'A'..'F'] do
    begin
      s := s + CurChar;
      Advance;
    end;
    Exit(MakeToken(ctkHash, s, startLine, startCol));
  end;

  // Number (no sign, optional fraction)
  if (CurChar in ['0'..'9']) or
     ((CurChar = '.') and (PeekChar(1) in ['0'..'9'])) then
  begin
    s := '';
    while CurChar in ['0'..'9'] do
    begin
      s := s + CurChar;
      Advance;
    end;
    if (CurChar = '.') and (PeekChar(1) in ['0'..'9']) then
    begin
      s := s + CurChar;
      Advance;
      while CurChar in ['0'..'9'] do
      begin
        s := s + CurChar;
        Advance;
      end;
    end;
    Exit(MakeToken(ctkNumber, s, startLine, startCol));
  end;

  // Identifier or function (ident followed immediately by '(')
  if (CurChar in ['a'..'z', 'A'..'Z', '_', '-']) then
  begin
    s := '';
    while CurChar in ['a'..'z', 'A'..'Z', '0'..'9', '_', '-'] do
    begin
      s := s + CurChar;
      Advance;
    end;
    if CurChar = '(' then
    begin
      Advance; // consume '('
      Exit(MakeToken(ctkFunction, s, startLine, startCol));
    end;
    Exit(MakeToken(ctkIdent, s, startLine, startCol));
  end;

  // String
  if (CurChar = '"') or (CurChar = '''') then
  begin
    quote := CurChar;
    Advance;
    s := '';
    while (FPos <= Length(FSource)) and (CurChar <> quote) do
    begin
      s := s + CurChar;
      Advance;
    end;
    if CurChar = quote then
      Advance;
    Exit(MakeToken(ctkString, s, startLine, startCol));
  end;

  // Single-char punctuation
  case CurChar of
    '%': begin Advance; Exit(MakeToken(ctkPercent, '%', startLine, startCol)); end;
    ':': begin Advance; Exit(MakeToken(ctkColon, ':', startLine, startCol)); end;
    ';': begin Advance; Exit(MakeToken(ctkSemicolon, ';', startLine, startCol)); end;
    '{': begin Advance; Exit(MakeToken(ctkLBrace, '{', startLine, startCol)); end;
    '}': begin Advance; Exit(MakeToken(ctkRBrace, '}', startLine, startCol)); end;
    '.': begin Advance; Exit(MakeToken(ctkDot, '.', startLine, startCol)); end;
    ',': begin Advance; Exit(MakeToken(ctkComma, ',', startLine, startCol)); end;
    '(': begin Advance; Exit(MakeToken(ctkLParen, '(', startLine, startCol)); end;
    ')': begin Advance; Exit(MakeToken(ctkRParen, ')', startLine, startCol)); end;
  end;

  // Anything else: delimiter
  s := CurChar;
  Advance;
  Result := MakeToken(ctkDelim, s, startLine, startCol);
end;

function TTyCssLexer.Next: TTyCssToken;
begin
  if FHasPeek then
  begin
    FHasPeek := False;
    Result := FPeeked;
  end
  else
    Result := ReadToken;
end;

function TTyCssLexer.Peek: TTyCssToken;
begin
  if not FHasPeek then
  begin
    FPeeked := ReadToken;
    FHasPeek := True;
  end;
  Result := FPeeked;
end;

end.
