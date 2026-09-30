unit test.themebuilder.lint;
{ TyLintCssEx (theme builder, phase 1): every lint issue with where it is (line, byte
  column), how bad and what kind. Positions come from a second walk of the lexer over a
  document the parser accepted (BuildPositions); a problem inside an imported file lands on
  the @import that brought it in. tlkBadValue exists only here: TyLintCss is TyLintCssEx
  minus that kind, message for message, in the same order (and test.themebuilder.golden
  holds TyLintCss to what it said before the change). }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, tyControls.ThemeLint;

type
  TTbLintExTests = class(TTestCase)
  private
    function J(const ALines: array of string): string;
    procedure CheckIssue(const ALabel: string; const AIssue: TTyLintIssue; ALine, ACol: Integer;
      AKind: TTyLintKind; ASeverity: TTyLintSeverity; const ASubject: string);
    function Dump(const AIssues: TTyLintIssues): string;
  published
    procedure TestPropertyAndVariableInARule;
    procedure TestAVariableIsPlacedOnItsLastDefinition;
    procedure TestAModeVariable;
    procedure TestLowContrastIsOnTheSelector;
    procedure TestMissingAsset;
    procedure TestMissingImport;
    procedure TestAnImportedProblemIsOnTheImport;
    procedure TestParseErrorTakesTheParserPosition;
    procedure TestBadValueOnlyInEx;
    procedure TestUndefinedVariableIsNotAlsoABadValue;
    procedure TestTheSameVariableInTwoRules;
    procedure TestTheOldOutputIsTheExMinusBadValues;
    procedure TestEveryIssueInAutoHasAPosition;
  end;

implementation

uses
  test.themebuilder.golden, tyControls.StrConsts, tyControls.Css.Parser;

function TTbLintExTests.J(const ALines: array of string): string;
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

function TTbLintExTests.Dump(const AIssues: TTyLintIssues): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(AIssues) do
    Result := Result + Format(' [(%d,%d) %d %s: %s]', [AIssues[i].Line, AIssues[i].Col,
      Ord(AIssues[i].Kind), AIssues[i].Subject, AIssues[i].Message]);
end;

procedure TTbLintExTests.CheckIssue(const ALabel: string; const AIssue: TTyLintIssue;
  ALine, ACol: Integer; AKind: TTyLintKind; ASeverity: TTyLintSeverity; const ASubject: string);
begin
  AssertEquals(ALabel + ': kind', Ord(AKind), Ord(AIssue.Kind));
  AssertEquals(ALabel + ': line', ALine, AIssue.Line);
  AssertEquals(ALabel + ': col', ACol, AIssue.Col);
  AssertEquals(ALabel + ': severity', Ord(ASeverity), Ord(AIssue.Severity));
  AssertEquals(ALabel + ': subject', ASubject, AIssue.Subject);
end;

procedure TTbLintExTests.TestPropertyAndVariableInARule;
var
  r: TTyLintIssues;
begin
  r := TyLintCssEx(J(['TyButton {', '  frobnicate: 1px;', '  color: var(--ghost);', '}']));
  AssertEquals('L1: two issues' + Dump(r), 2, Length(r));
  CheckIssue('L1 property', r[0], 2, 3, tlkUnknownProperty, tlsError, 'frobnicate');
  CheckIssue('L1 variable', r[1], 3, 3, tlkUndefinedVar, tlsError, 'ghost');
end;

procedure TTbLintExTests.TestAVariableIsPlacedOnItsLastDefinition;
var
  r: TTyLintIssues;
begin
  r := TyLintCssEx(J([':root {', '  --a: #111;', '  --a: var(--nope);', '}']));
  AssertEquals('L2: one issue' + Dump(r), 1, Length(r));
  CheckIssue('L2', r[0], 3, 3, tlkUndefinedVar, tlsError, 'nope');
end;

procedure TTbLintExTests.TestAModeVariable;
var
  r: TTyLintIssues;
begin
  { a :root with the same name first, so looking the mode variable up in the root table
    gives a different (wrong) place }
  r := TyLintCssEx(J([':root { --x: #000; }', '@mode dark {', '  :root {',
    '    --x: var(--missing);', '  }', '}']));
  AssertEquals('L3: one issue' + Dump(r), 1, Length(r));
  CheckIssue('L3', r[0], 4, 5, tlkUndefinedVar, tlsError, 'missing');
end;

procedure TTbLintExTests.TestLowContrastIsOnTheSelector;
var
  r: TTyLintIssues;
begin
  r := TyLintCssEx(J(['/* c */',
    'TyButton.primary:hover { background: #111111; color: #131313; }']));
  AssertEquals('L4: one issue' + Dump(r), 1, Length(r));
  CheckIssue('L4', r[0], 2, 1, tlkLowContrast, tlsWarning, 'TyButton.primary:hover');
end;

procedure TTbLintExTests.TestMissingAsset;
var
  r: TTyLintIssues;
begin
  r := TyLintCssEx(J(['TyPanel {', '  background-image: url(nope.png) slice(4 4 4 4);', '}']),
    GetTempDir(False));
  AssertEquals('L5: one issue' + Dump(r), 1, Length(r));
  CheckIssue('L5', r[0], 2, 3, tlkMissingAsset, tlsWarning, 'nope.png');
end;

procedure TTbLintExTests.TestMissingImport;
var
  r: TTyLintIssues;
begin
  r := TyLintCssEx(J(['/* x */', '@import "nope.tycss";']));
  AssertEquals('L6: one issue' + Dump(r), 1, Length(r));
  CheckIssue('L6', r[0], 2, 1, tlkMissingImport, tlsError, 'nope.tycss');
end;

procedure TTbLintExTests.TestAnImportedProblemIsOnTheImport;
var
  r: TTyLintIssues;
begin
  AssertTrue('the fixture is there', FileExists(TbFixtureDir + 'import-child.tycss'));
  r := TyLintCssEx(J(['/* x */', '@import "import-child.tycss";']), TbFixtureDir);
  AssertEquals('L7: one issue' + Dump(r), 1, Length(r));
  CheckIssue('L7', r[0], 2, 1, tlkUnknownProperty, tlsError, 'frobnicate');
end;

procedure TTbLintExTests.TestParseErrorTakesTheParserPosition;
var
  r: TTyLintIssues;
  src, msg: string;
  parser: TTyCssParser;
begin
  src := 'TyButton {'#10'  color red;'#10'}';
  msg := '';
  parser := TTyCssParser.Create(src);
  try
    try
      parser.Parse.Free;
    except
      on E: Exception do msg := E.Message;
    end;
  finally
    parser.Free;
  end;
  AssertTrue('the parser rejects it', msg <> '');
  r := TyLintCssEx(src);
  AssertEquals('L8: one issue' + Dump(r), 1, Length(r));
  CheckIssue('L8', r[0], 2, 9, tlkParseError, tlsError, '');
  AssertEquals('L8: message', Format(rsLintParseError, [msg]), r[0].Message);
end;

procedure TTbLintExTests.TestBadValueOnlyInEx;
var
  r: TTyLintIssues;
  old: TTyLintResult;
  src: string;
begin
  src := J(['TyButton {', '  border-radius: 1px 2px 3px;', '}']);
  r := TyLintCssEx(src);
  AssertEquals('L9: one issue' + Dump(r), 1, Length(r));
  CheckIssue('L9', r[0], 2, 3, tlkBadValue, tlsError, 'border-radius');
  AssertEquals('L9: message starts with the property', 1, Pos('border-radius: ', r[0].Message));
  AssertTrue('L9: and says more than that', Length(r[0].Message) > Length('border-radius: '));
  old := TyLintCss(src);
  AssertEquals('L9: TyLintCss says nothing', 0, Length(old));
end;

procedure TTbLintExTests.TestUndefinedVariableIsNotAlsoABadValue;
var
  r: TTyLintIssues;
begin
  r := TyLintCssEx('TyButton { padding: var(--undefined-pad); }');
  AssertEquals('L10: one issue' + Dump(r), 1, Length(r));
  AssertEquals('L10: the undefined variable', Ord(tlkUndefinedVar), Ord(r[0].Kind));
  { through a variable the sheet defines, to one it does not: still not a bad value }
  r := TyLintCssEx(':root { --pad: var(--from-the-base); }'#10'TyButton { padding: var(--pad); }');
  AssertEquals('L10b: one issue' + Dump(r), 1, Length(r));
  AssertEquals('L10b: the undefined variable', Ord(tlkUndefinedVar), Ord(r[0].Kind));
end;

procedure TTbLintExTests.TestTheSameVariableInTwoRules;
var
  r: TTyLintIssues;
begin
  r := TyLintCssEx('TyButton { color: var(--g); }'#10'TyEdit { color: var(--g); }');
  AssertEquals('L11: two issues' + Dump(r), 2, Length(r));
  CheckIssue('L11 first', r[0], 1, 12, tlkUndefinedVar, tlsError, 'g');
  CheckIssue('L11 second', r[1], 2, 10, tlkUndefinedVar, tlsError, 'g');
end;

procedure TTbLintExTests.TestTheOldOutputIsTheExMinusBadValues;
var
  names, texts, dirs: TStringList;
  i, m, k: Integer;
  old: TTyLintResult;
  ex: TTyLintIssues;
begin
  names := TStringList.Create;
  texts := TStringList.Create;
  dirs := TStringList.Create;
  try
    TbGoldenCorpus(names, texts, dirs);
    for i := 0 to names.Count - 1 do
    begin
      old := TyLintCss(texts[i], dirs[i]);
      ex := TyLintCssEx(texts[i], dirs[i]);
      k := 0;
      for m := 0 to High(ex) do
      begin
        { every shipped theme loads in the engine: none of its values is bad }
        if Copy(names[i], 1, 7) = 'themes/' then
          AssertTrue('L12: no bad value in ' + names[i] + ':' + Dump(ex),
            ex[m].Kind <> tlkBadValue);
        if ex[m].Kind = tlkBadValue then
          Continue;
        AssertTrue('L12: ' + names[i] + ' has more Ex issues than old ones', k <= High(old));
        AssertEquals('L12: ' + names[i] + ' #' + IntToStr(k), old[k], ex[m].Message);
        Inc(k);
      end;
      AssertEquals('L12: ' + names[i] + ' count', Length(old), k);
    end;
  finally
    names.Free;
    texts.Free;
    dirs.Free;
  end;
end;

procedure TTbLintExTests.TestEveryIssueInAutoHasAPosition;
var
  sl: TStringList;
  ex: TTyLintIssues;
  i: Integer;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(TbThemesDir + 'auto.tycss');
    ex := TyLintCssEx(sl.Text, TbThemesDir);
    AssertTrue('L13: auto.tycss has issues to place', Length(ex) > 0);
    for i := 0 to High(ex) do
    begin
      AssertTrue(Format('L13: issue %d (%s) has a line', [i, ex[i].Message]), ex[i].Line >= 1);
      AssertTrue(Format('L13: issue %d (%s) is inside the file', [i, ex[i].Message]),
        ex[i].Line <= sl.Count);
    end;
  finally
    sl.Free;
  end;
end;

initialization
  RegisterTest(TTbLintExTests);
end.
