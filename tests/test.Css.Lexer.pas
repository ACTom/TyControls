unit test.Css.Lexer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, tyControls.Css.Tokens, tyControls.Css.Lexer;

type
  TTestCssLexer = class(TTestCase)
  published
    procedure TestIdent;
    procedure TestHashColor;
    procedure TestNumberAndPx;
    procedure TestPercent;
    procedure TestPunctuation;
    procedure TestParens;
    procedure TestFunctionToken;
    procedure TestString;
    procedure TestComment;
    procedure TestPeekDoesNotConsume;
    procedure TestLineColTracking;
  end;

implementation

procedure TTestCssLexer.TestIdent;
var
  lex: TTyCssLexer;
  t: TTyCssToken;
begin
  lex := TTyCssLexer.Create('TyButton');
  try
    t := lex.Next;
    AssertTrue('ident kind', t.Kind = ctkIdent);
    AssertEquals('ident text', 'TyButton', t.Text);
    AssertTrue('then eof', lex.Next.Kind = ctkEOF);
  finally
    lex.Free;
  end;
end;

procedure TTestCssLexer.TestHashColor;
var
  lex: TTyCssLexer;
  t: TTyCssToken;
begin
  lex := TTyCssLexer.Create('#3B82F6');
  try
    t := lex.Next;
    AssertTrue('hash kind', t.Kind = ctkHash);
    AssertEquals('hash text excludes #', '3B82F6', t.Text);
  finally
    lex.Free;
  end;
end;

procedure TTestCssLexer.TestNumberAndPx;
var
  lex: TTyCssLexer;
  n, u: TTyCssToken;
begin
  lex := TTyCssLexer.Create('12px');
  try
    n := lex.Next;
    AssertTrue('number kind', n.Kind = ctkNumber);
    AssertEquals('number text', '12', n.Text);
    u := lex.Next;
    AssertTrue('px is ident', u.Kind = ctkIdent);
    AssertEquals('px text', 'px', u.Text);
  finally
    lex.Free;
  end;
end;

procedure TTestCssLexer.TestPercent;
var
  lex: TTyCssLexer;
  n, p: TTyCssToken;
begin
  lex := TTyCssLexer.Create('8%');
  try
    n := lex.Next;
    AssertTrue('number kind', n.Kind = ctkNumber);
    AssertEquals('number text', '8', n.Text);
    p := lex.Next;
    AssertTrue('percent kind', p.Kind = ctkPercent);
  finally
    lex.Free;
  end;
end;

procedure TTestCssLexer.TestPunctuation;
var
  lex: TTyCssLexer;
begin
  lex := TTyCssLexer.Create('.:;{},');
  try
    AssertTrue('dot', lex.Next.Kind = ctkDot);
    AssertTrue('colon', lex.Next.Kind = ctkColon);
    AssertTrue('semicolon', lex.Next.Kind = ctkSemicolon);
    AssertTrue('lbrace', lex.Next.Kind = ctkLBrace);
    AssertTrue('rbrace', lex.Next.Kind = ctkRBrace);
    AssertTrue('comma', lex.Next.Kind = ctkComma);
    AssertTrue('eof', lex.Next.Kind = ctkEOF);
  finally
    lex.Free;
  end;
end;

procedure TTestCssLexer.TestParens;
var
  lex: TTyCssLexer;
begin
  lex := TTyCssLexer.Create('()');
  try
    AssertTrue('lparen', lex.Next.Kind = ctkLParen);
    AssertTrue('rparen', lex.Next.Kind = ctkRParen);
  finally
    lex.Free;
  end;
end;

procedure TTestCssLexer.TestFunctionToken;
var
  lex: TTyCssLexer;
  f: TTyCssToken;
begin
  lex := TTyCssLexer.Create('lighten(');
  try
    f := lex.Next;
    AssertTrue('function kind', f.Kind = ctkFunction);
    AssertEquals('function name no paren', 'lighten', f.Text);
  finally
    lex.Free;
  end;
end;

procedure TTestCssLexer.TestString;
var
  lex: TTyCssLexer;
  s: TTyCssToken;
begin
  lex := TTyCssLexer.Create('"Segoe UI"');
  try
    s := lex.Next;
    AssertTrue('string kind', s.Kind = ctkString);
    AssertEquals('string text no quotes', 'Segoe UI', s.Text);
  finally
    lex.Free;
  end;
end;

procedure TTestCssLexer.TestComment;
var
  lex: TTyCssLexer;
  t: TTyCssToken;
begin
  lex := TTyCssLexer.Create('/* skip me */ accent');
  try
    t := lex.Next;
    AssertTrue('comment skipped', t.Kind = ctkIdent);
    AssertEquals('ident after comment', 'accent', t.Text);
  finally
    lex.Free;
  end;
end;

procedure TTestCssLexer.TestPeekDoesNotConsume;
var
  lex: TTyCssLexer;
begin
  lex := TTyCssLexer.Create('a b');
  try
    AssertEquals('peek a', 'a', lex.Peek.Text);
    AssertEquals('peek again a', 'a', lex.Peek.Text);
    AssertEquals('next a', 'a', lex.Next.Text);
    AssertEquals('next b', 'b', lex.Next.Text);
  finally
    lex.Free;
  end;
end;

procedure TTestCssLexer.TestLineColTracking;
var
  lex: TTyCssLexer;
  t1, t2: TTyCssToken;
begin
  lex := TTyCssLexer.Create('ab' + LineEnding + '  cd');
  try
    t1 := lex.Next;
    AssertEquals('t1 line', 1, t1.Line);
    AssertEquals('t1 col', 1, t1.Col);
    t2 := lex.Next;
    AssertEquals('t2 line', 2, t2.Line);
    AssertEquals('t2 col', 3, t2.Col);
  finally
    lex.Free;
  end;
end;

initialization
  RegisterTest(TTestCssLexer);
end.
