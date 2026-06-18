unit test.Css.Tokens;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, tyControls.Css.Tokens;

type
  TTestCssTokens = class(TTestCase)
  published
    procedure TestKindOrdinals;
    procedure TestTokenRecord;
  end;

implementation

procedure TTestCssTokens.TestKindOrdinals;
begin
  AssertEquals('ident first', 0, Ord(ctkIdent));
  AssertEquals('eof last', 16, Ord(ctkEOF));   // +1 since ctkAtKeyword was added for @import (A8)
  AssertTrue('function before delim', Ord(ctkFunction) < Ord(ctkDelim));
  AssertTrue('at-keyword before delim', Ord(ctkAtKeyword) < Ord(ctkDelim));
end;

procedure TTestCssTokens.TestTokenRecord;
var
  t: TTyCssToken;
begin
  t.Kind := ctkHash;
  t.Text := '3B82F6';
  t.Line := 4;
  t.Col := 12;
  AssertTrue('kind', t.Kind = ctkHash);
  AssertEquals('text', '3B82F6', t.Text);
  AssertEquals('line', 4, t.Line);
  AssertEquals('col', 12, t.Col);
end;

initialization
  RegisterTest(TTestCssTokens);
end.
