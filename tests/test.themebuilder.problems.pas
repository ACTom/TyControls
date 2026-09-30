unit test.themebuilder.problems;
{ The theme builder's problem list (phase 1): lint issues, minus undefined variables the base
  theme defines (the engine resolves those; the library's lint does not know the base); a
  "save first" hint for url() in an untitled document; rows without a position first, then
  by line and column, and TbAddProblem keeping that order. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry;

type
  TTbProblemsTests = class(TTestCase)
  private
    function J(const ALines: array of string): string;
  published
    procedure TestBaseVariableNames;
    procedure TestBaseVariablesAreNotUndefined;
    procedure TestUnsavedDocumentAssetHint;
    procedure TestOrder;
    procedure TestCaption;
    procedure TestParseErrorAndErrorCount;
  end;

implementation

uses
  tyControls.ThemeLint, tbproblems;

function TTbProblemsTests.J(const ALines: array of string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(ALines) do
  begin
    if i > 0 then Result := Result + #10;
    Result := Result + ALines[i];
  end;
end;

procedure TTbProblemsTests.TestBaseVariableNames;
var
  names: TStringList;
  i: Integer;
begin
  names := TStringList.Create;
  try
    TbBaseVarNames(names);
    AssertTrue('R1: accent', names.IndexOf('accent') >= 0);
    AssertTrue('R1: surface-hover', names.IndexOf('surface-hover') >= 0);
    AssertTrue('R1: muted', names.IndexOf('muted') >= 0);
    for i := 0 to names.Count - 1 do
    begin
      AssertTrue('R1: no leading dashes: ' + names[i], Copy(names[i], 1, 2) <> '--');
      AssertEquals('R1: lower case', LowerCase(names[i]), names[i]);
    end;
  finally
    names.Free;
  end;
end;

procedure TTbProblemsTests.TestBaseVariablesAreNotUndefined;
const
  cSrc = 'TyButton { background: var(--surface-hover); color: var(--nope); }';
var
  names: TStringList;
  r: TTbProblems;
begin
  r := TbCollectProblems(cSrc, '', False, nil);
  AssertEquals('R2: lint alone reports both', 2, Length(r));
  names := TStringList.Create;
  try
    TbBaseVarNames(names);
    r := TbCollectProblems(cSrc, '', False, names);
    AssertEquals('R2: the base variable is not a problem', 1, Length(r));
    AssertEquals('R2: undefined', Ord(tlkUndefinedVar), Ord(r[0].Kind));
    AssertTrue('R2: it is --nope: ' + r[0].Text, Pos('nope', r[0].Text) > 0);
  finally
    names.Free;
  end;
end;

procedure TTbProblemsTests.TestUnsavedDocumentAssetHint;
var
  src: string;
  r: TTbProblems;
  i, n: Integer;
begin
  src := J(['TyPanel {', '  background-image: url(a.png) slice(1 1 1 1);', '}']);
  r := TbCollectProblems(src, '', True, nil);
  n := 0;
  for i := 0 to High(r) do
    if r[i].Origin = tpoDocument then
    begin
      Inc(n);
      AssertEquals('R3: on the url() line', 2, r[i].Line);
      AssertEquals('R3: at url(', Pos('url(', '  background-image: url(a.png) slice(1 1 1 1);'), r[i].Col);
      AssertEquals('R3: a warning', Ord(tlsWarning), Ord(r[i].Severity));
    end;
  AssertEquals('R3: one hint', 1, n);
  r := TbCollectProblems(src, '', False, nil);
  for i := 0 to High(r) do
    AssertTrue('R3: a saved document has no hint', r[i].Origin <> tpoDocument);
  r := TbCollectProblems('/* url(x) */', '', True, nil);
  AssertEquals('R3: a url() in a comment is not a hint', 0, Length(r));
  r := TbCollectProblems(J(['/* a', '  url(x) */', 'TyPanel { }']), '', True, nil);
  AssertEquals('R3: nor in a comment over two lines', 0, Length(r));
end;

procedure TTbProblemsTests.TestOrder;
var
  r: TTbProblems;
  i: Integer;
begin
  r := TbCollectProblems('TyButton {'#10'  color red;'#10'}', '', False, nil);
  AssertEquals('R4: a parse error is one row', 1, Length(r));
  AssertEquals('R4: the parse error', Ord(tlkParseError), Ord(r[0].Kind));

  { the undefined variable (line 3) is reported after the unknown property (line 4) of the
    same rule, and a second rule comes first in the text: lint order is not line order }
  r := TbCollectProblems(J(['TyEdit { color: var(--z1); }', '', 'TyButton {',
    '  color: var(--ghost);', '  frobnicate: 1px;', '}']), '', False, nil);
  AssertEquals('R4: three rows', 3, Length(r));
  for i := 1 to High(r) do
    AssertTrue('R4: by line', r[i - 1].Line <= r[i].Line);

  r := TbCollectProblems(J(['TyButton {', '  frobnicate: 1px;', '  color: var(--ghost);', '}']),
    '', False, nil);
  AssertEquals('two lint rows', 2, Length(r));
  TbAddProblem(r, 0, 0, tlsError, tpoLoad, 'first');
  TbAddProblem(r, 0, 0, tlsError, tpoLoad, 'second');
  AssertEquals('R4: four rows', 4, Length(r));
  AssertEquals('R4: no position first', 'first', r[0].Text);
  AssertEquals('R4: in the order they came', 'second', r[1].Text);
  AssertEquals('R4: then line 2', 2, r[2].Line);
  AssertEquals('R4: then line 3', 3, r[3].Line);
  TbAddProblem(r, 3, 1, tlsWarning, tpoDocument, 'between');
  AssertEquals('R4: an added row goes where its line is', 'between', r[3].Text);
end;

procedure TTbProblemsTests.TestCaption;
var
  p: TTbProblem;
begin
  p := Default(TTbProblem);
  p.Line := 12; p.Col := 5; p.Text := 'x';
  AssertEquals('R5: with a position', '12:5  x', TbProblemCaption(p));
  p.Line := 0; p.Col := 0; p.Text := 'y';
  AssertEquals('R5: without one', #$E2#$80#$94'  y', TbProblemCaption(p));
end;

procedure TTbProblemsTests.TestParseErrorAndErrorCount;
begin
  AssertTrue('R6: a parse error',
    TbHasParseError(TbCollectProblems('TyButton {'#10'  color red;'#10'}', '', False, nil)));
  AssertFalse('R6: lint problems are not a parse error',
    TbHasParseError(TbCollectProblems(J(['TyButton {', '  frobnicate: 1px;',
      '  color: var(--ghost);', '}']), '', False, nil)));
  AssertEquals('R6: low contrast is a warning, not an error', 0,
    TbErrorCount(TbCollectProblems(J(['/* c */',
      'TyButton.primary:hover { background: #111111; color: #131313; }']), '', False, nil)));
end;

initialization
  RegisterTest(TTbProblemsTests);
end.
