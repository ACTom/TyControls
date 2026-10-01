unit test.themebuilder.scan;
{ The theme builder's forgiving scan (phase 2): where every :root, @mode :root and rule is,
  where each declaration's value starts and ends, where each selector starts -- in bytes,
  the way the edits that change one value or add one rule need them. Checked against the
  library's parser on every theme in the repository. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, fpcunit, testregistry, tbcssscan;

type
  TTbCssScanTests = class(TTestCase)
  private
    function Scan(const AText: string): TTbCssScan;
  published
    procedure TestOneRootBlock;
    procedure TestAModeBlock;
    procedure TestACommentedOutDeclaration;
    procedure TestATrailingCommentIsNotTheValue;
    procedure TestAFunctionValue;
    procedure TestASemicolonInAString;
    procedure TestSelectors;
    procedure TestImports;
    procedure TestAnUnclosedBlock;
    procedure TestAnUnknownAtRuleIsSkippedWhole;
    procedure TestRepeatedDeclarationsInOrder;
    procedure TestOffsetsToPoints;
    procedure TestTheRepositoryThemesAgreeWithTheParser;
    procedure TestApplyingEdits;
  end;

  { the rule for a typeKey and variant: found, or added empty at the end (tbrules) }
  TTbRulesTests = class(TTestCase)
  private
    function Points(const AText, ATypeKey, AVariant: string): string;
    procedure CheckNew(const ATag, AText, ATypeKey, AVariant, AWant: string; AX, AY: Integer);
  published
    procedure TestTheStateIsNotTheRule;
    procedure TestTheCaseDoesNotMatter;
    procedure TestACommentedRuleIsNotFound;
    procedure TestModeBlocksHaveNoRules;
    procedure TestAddingAtTheEnd;
    procedure TestAddingWithoutAFinalBreak;
    procedure TestAddingToAnEmptyText;
  end;

implementation

uses
  FileUtil, tyControls.Css.Parser, tbrules, test.themebuilder.golden;

function TTbCssScanTests.Scan(const AText: string): TTbCssScan;
begin
  Result := TbScanCss(AText);
end;

procedure TTbCssScanTests.TestOneRootBlock;
var
  s: TTbCssScan;
  b: TTbBlock;
begin
  s := Scan(':root { --a: #111; --b: 2px; }');
  try
    AssertEquals('C1: one block', 1, s.Count);
    b := s.Block(0);
    AssertEquals('C1: :root', Ord(tbkRoot), Ord(b.Kind));
    AssertEquals('C1: head', 1, b.HeadStart);
    AssertEquals('C1: open', 7, b.OpenBrace);
    AssertEquals('C1: close', 30, b.CloseBrace);
    AssertEquals('C1: two', 2, Length(b.Decls));
    AssertEquals('C1: --a name', 9, b.Decls[0].NameStart);
    AssertEquals('C1: --a value start', 14, b.Decls[0].ValueStart);
    AssertEquals('C1: --a value end', 18, b.Decls[0].ValueEnd);
    AssertEquals('C1: --a stop', 18, b.Decls[0].StopAt);
    AssertEquals('C1: --b name', 20, b.Decls[1].NameStart);
    AssertEquals('C1: --b value start', 25, b.Decls[1].ValueStart);
    AssertEquals('C1: --b value end', 28, b.Decls[1].ValueEnd);
    AssertEquals('C1: --b stop', 28, b.Decls[1].StopAt);
    AssertEquals('C1: the name', '--a', b.Decls[0].Name);
    AssertEquals('C1: the value', '2px', s.DeclValue(0, 1));
  finally
    s.Free;
  end;
end;

procedure TTbCssScanTests.TestAModeBlock;
const
  cT = '@mode light {'#10'  :root {'#10'  /* ── SEED ── */'#10'  --accent: #3B82F6; --surface: #FFFFFF;'#10'  }'#10'}';
var
  s: TTbCssScan;
  b: TTbBlock;
begin
  s := Scan(cT);
  try
    AssertEquals('C2: one block', 1, s.Count);
    b := s.Block(0);
    AssertEquals('C2: a mode :root', Ord(tbkModeRoot), Ord(b.Kind));
    AssertEquals('C2: the mode', 'light', b.Mode);
    AssertEquals('C2: the @', 1, b.ModeStart);
    AssertEquals('C2: the outer brace', Length(cT), b.OuterClose);
    AssertEquals('C2: the inner brace', Length(cT) - 2, b.CloseBrace);
    AssertEquals('C2: two', 2, Length(b.Decls));
    AssertEquals('C2: accent', '#3B82F6', s.DeclValue(0, 0));
    AssertEquals('C2: surface', '#FFFFFF', s.DeclValue(0, 1));
    AssertTrue('C2: has modes', s.HasModes);
  finally
    s.Free;
  end;
end;

procedure TTbCssScanTests.TestACommentedOutDeclaration;
var
  s: TTbCssScan;
begin
  s := Scan(':root { /* --accent: red; */ --accent: #222; }');
  try
    AssertEquals('C3: one declaration', 1, Length(s.Block(0).Decls));
    AssertEquals('C3: the real one', '#222', s.DeclValue(0, 0));
  finally
    s.Free;
  end;
end;

procedure TTbCssScanTests.TestATrailingCommentIsNotTheValue;
var
  s: TTbCssScan;
begin
  s := Scan(':root { --accent: #333 /* c */ ; }');
  try
    AssertEquals('C4: the value only', '#333', s.DeclValue(0, 0));
  finally
    s.Free;
  end;
end;

procedure TTbCssScanTests.TestAFunctionValue;
var
  s: TTbCssScan;
begin
  s := Scan(':root { --surface: darken(var(--x), 4%); }');
  try
    AssertEquals('C5', 'darken(var(--x), 4%)', s.DeclValue(0, 0));
  finally
    s.Free;
  end;
end;

procedure TTbCssScanTests.TestASemicolonInAString;
var
  s: TTbCssScan;
begin
  s := Scan('TyLabel { font-family: "A;B"; }');
  try
    AssertEquals('C6: one declaration', 1, Length(s.Block(0).Decls));
    AssertEquals('C6: the string whole', '"A;B"', s.DeclValue(0, 0));
  finally
    s.Free;
  end;
end;

procedure TTbCssScanTests.TestSelectors;
var
  s: TTbCssScan;
  b: TTbBlock;
begin
  s := Scan('TyButton.primary:hover, TyEdit { color: red; }');
  try
    AssertEquals('C7: one block', 1, s.Count);
    b := s.Block(0);
    AssertEquals('C7: a rule', Ord(tbkRule), Ord(b.Kind));
    AssertEquals('C7: two selectors', 2, Length(b.Selectors));
    AssertEquals('C7: type', 'TyButton', b.Selectors[0].TypeName);
    AssertEquals('C7: variant', 'primary', b.Selectors[0].Variant);
    AssertEquals('C7: state', 'hover', b.Selectors[0].State);
    AssertEquals('C7: start', 1, b.Selectors[0].Start);
    AssertEquals('C7: second type', 'TyEdit', b.Selectors[1].TypeName);
    AssertEquals('C7: no variant', '', b.Selectors[1].Variant);
    AssertEquals('C7: no state', '', b.Selectors[1].State);
    AssertEquals('C7: second start', 25, b.Selectors[1].Start);
    AssertEquals('C7: head', 1, b.HeadStart);
  finally
    s.Free;
  end;
end;

procedure TTbCssScanTests.TestImports;
var
  s: TTbCssScan;
begin
  s := Scan('@import "a.tycss";'#10':root { --a: 1px; }');
  try
    AssertEquals('C8: after the import', 19, s.ImportEnd);
    AssertEquals('C8: one block', 1, s.Count);
  finally
    s.Free;
  end;
end;

procedure TTbCssScanTests.TestAnUnclosedBlock;
var
  s: TTbCssScan;
begin
  s := Scan(':root { --a: #111;');
  try
    AssertEquals('C9: a block', 1, s.Count);
    AssertEquals('C9: never closed', 0, s.Block(0).CloseBrace);
    AssertEquals('C9: one declaration', 1, Length(s.Block(0).Decls));
    AssertEquals('C9: its value', '#111', s.DeclValue(0, 0));
  finally
    s.Free;
  end;
  s := Scan('TyButton { color: red');
  try
    AssertEquals('C9: a rule', 1, s.Count);
    AssertEquals('C9: one declaration', 1, Length(s.Block(0).Decls));
    AssertEquals('C9: its value', 'red', s.DeclValue(0, 0));
    AssertEquals('C9: no semicolon', 0, s.Block(0).Decls[0].StopAt);
    AssertEquals('C9: never closed', 0, s.Block(0).CloseBrace);
  finally
    s.Free;
  end;
end;

procedure TTbCssScanTests.TestAnUnknownAtRuleIsSkippedWhole;
var
  s: TTbCssScan;
begin
  s := Scan('@media x { TyButton { color: red; } }'#10':root { --a: 1px; }');
  try
    AssertEquals('C10: only the :root', 1, s.Count);
    AssertEquals('C10: and it is', Ord(tbkRoot), Ord(s.Block(0).Kind));
  finally
    s.Free;
  end;
end;

procedure TTbCssScanTests.TestRepeatedDeclarationsInOrder;
var
  s: TTbCssScan;
begin
  s := Scan(':root { --a: #111; --a: #222; }');
  try
    AssertEquals('C11: both', 2, Length(s.Block(0).Decls));
    AssertEquals('C11: first', '#111', s.DeclValue(0, 0));
    AssertEquals('C11: second', '#222', s.DeclValue(0, 1));
  finally
    s.Free;
  end;
end;

procedure TTbCssScanTests.TestOffsetsToPoints;
const
  cT = 'ab'#13#10'c'#$E4#$B8#$AD'd'#13'e'#10'f';

  procedure Check(AOffset, AX, AY: Integer);
  var
    p: TPoint;
  begin
    p := TbOffsetToPoint(cT, AOffset);
    AssertEquals('C12: x of ' + IntToStr(AOffset), AX, p.X);
    AssertEquals('C12: y of ' + IntToStr(AOffset), AY, p.Y);
  end;

begin
  Check(5, 1, 2);
  Check(9, 5, 2);
  Check(11, 1, 3);
  Check(13, 1, 4);
  Check(14, 2, 4);
  AssertEquals('the line start', 5, TbLineStart(cT, 9));
  AssertEquals('the indent', '  ', TbLineIndent('a'#10'  b', 5));
end;

{ the value with every blank and comment gone and ' read as " -- the parser rebuilds a
  value from its tokens, the scan keeps it as written }
function Norm(const S: string): string;
var
  i, j: Integer;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    if (S[i] = '/') and (i < Length(S)) and (S[i + 1] = '*') then
    begin
      j := Pos('*/', Copy(S, i + 2, MaxInt));
      if j = 0 then Break;
      i := i + 2 + j + 1;
      Continue;
    end;
    if not (S[i] in [' ', #9, #10, #13]) then
    begin
      if S[i] = '''' then
        Result := Result + '"'
      else
        Result := Result + S[i];
    end;
    Inc(i);
  end;
end;

procedure TTbCssScanTests.TestTheRepositoryThemesAgreeWithTheParser;
var
  files: TStringList;
  sl: TStringList;
  f, k, b, d, m, ruleCount, checked: Integer;
  text, name, want, have: string;
  p: TTyCssParser;
  sheet: TTyCssStylesheet;
  s: TTbCssScan;
  mb: TTyCssModeBlock;
  rule: TTyCssRule;

  { the last declaration of AName in the blocks of AKind (and AMode) }
  function LastIn(AKind: TTbBlockKind; const AMode, AName: string; out AValue: string): Boolean;
  var
    bi, di: Integer;
    blk: TTbBlock;
  begin
    Result := False;
    AValue := '';
    for bi := 0 to s.Count - 1 do
    begin
      blk := s.Block(bi);
      if blk.Kind <> AKind then Continue;
      if (AKind = tbkModeRoot) and not SameText(blk.Mode, AMode) then Continue;
      for di := 0 to High(blk.Decls) do
        if blk.Decls[di].Name = '--' + AName then
        begin
          AValue := s.DeclValue(bi, di);
          Result := True;
        end;
    end;
  end;

begin
  files := FindAllFiles(TbThemesDir, '*.tycss', True);
  sl := TStringList.Create;
  checked := 0;
  try
    AssertTrue('there are themes', files.Count > 20);
    for f := 0 to files.Count - 1 do
    begin
      sl.LoadFromFile(files[f]);
      text := sl.Text;
      p := TTyCssParser.Create(text);
      try
        try
          sheet := p.Parse;
        except
          Continue;   { not the scan's business }
        end;
      finally
        p.Free;
      end;
      s := TbScanCss(text);
      try
        for k := 0 to sheet.RootVars.Count - 1 do
        begin
          name := sheet.RootVars.Names[k];
          want := sheet.RootVars.ValueFromIndex[k];
          AssertTrue('C13: ' + files[f] + ' has --' + name,
            LastIn(tbkRoot, '', name, have));
          AssertEquals('C13: ' + files[f] + ' --' + name, Norm(want), Norm(have));
          Inc(checked);
        end;
        for m := 0 to sheet.ModeBlocks.Count - 1 do
        begin
          mb := TTyCssModeBlock(sheet.ModeBlocks[m]);
          for k := 0 to mb.Vars.Count - 1 do
          begin
            name := mb.Vars.Names[k];
            AssertTrue('C13: ' + files[f] + ' @mode ' + mb.Mode + ' has --' + name,
              LastIn(tbkModeRoot, LowerCase(mb.Mode), name, have));
            { a later block of the same mode may set it again: compare with the last }
            want := mb.Vars.ValueFromIndex[k];
            for b := m + 1 to sheet.ModeBlocks.Count - 1 do
              if SameText(TTyCssModeBlock(sheet.ModeBlocks[b]).Mode, mb.Mode)
                 and (TTyCssModeBlock(sheet.ModeBlocks[b]).Vars.IndexOfName(name) >= 0) then
                want := TTyCssModeBlock(sheet.ModeBlocks[b]).Vars.Values[name];
            AssertEquals('C13: ' + files[f] + ' @mode ' + mb.Mode + ' --' + name,
              Norm(want), Norm(have));
            Inc(checked);
          end;
        end;
        ruleCount := 0;
        for b := 0 to s.Count - 1 do
          if s.Block(b).Kind = tbkRule then
          begin
            if ruleCount < sheet.Rules.Count then
            begin
              rule := TTyCssRule(sheet.Rules[ruleCount]);
              AssertEquals('C13: ' + files[f] + ' rule ' + IntToStr(ruleCount),
                rule.Selectors[0].TypeName, s.Block(b).Selectors[0].TypeName);
              d := Length(rule.Declarations);
              AssertEquals('C13: ' + files[f] + ' rule ' + IntToStr(ruleCount) + ' declarations',
                d, Length(s.Block(b).Decls));
            end;
            Inc(ruleCount);
          end;
        AssertEquals('C13: ' + files[f] + ' rules', sheet.Rules.Count, ruleCount);
      finally
        s.Free;
        sheet.Free;
      end;
    end;
    AssertTrue('C13: values were compared', checked > 500);
  finally
    sl.Free;
    files.Free;
  end;
end;

procedure TTbCssScanTests.TestApplyingEdits;
var
  e: TTbTextEdits;
begin
  SetLength(e, 2);
  { the first edit changes the length: applied front to back, the second would land two
    bytes early }
  e[0] := TbEdit(2, 4, 'WXYZ');
  e[1] := TbEdit(6, 6, '!');
  AssertEquals('C14: back to front', 'aWXYZde!f', TbApplyEdits('abcdef', e));
  e[1] := TbEdit(3, 3, '!');
  AssertEquals('C14: overlapping edits leave the text', 'abcdef', TbApplyEdits('abcdef', e));
  AssertEquals('C14: CRLF end', 2, TbEndInsertPos('a'#13#10));
  AssertEquals('C14: LF end', 2, TbEndInsertPos('a'#10));
  AssertEquals('C14: no break', 2, TbEndInsertPos('a'));
  AssertEquals('C14: empty', 1, TbEndInsertPos(''));
  AssertEquals('the first break', #13#10, TbDetectEol('a'#13#10'b'#10));
  AssertEquals('a lone CR', #13, TbDetectEol('a'#13'b'));
end;

{ ---- rules ---- }

const
  cRulesDoc = 'TyButton { }'#10'TyButton.primary { }'#10'TyButton.primary:hover { }'#10'TyEdit, TyButton.primary { }';

{ '(x,y) (x,y)' of what TbFindRuleSelectors finds }
function TTbRulesTests.Points(const AText, ATypeKey, AVariant: string): string;
var
  s: TTbCssScan;
  hits: TTbOffsets;
  i: Integer;
  p: TPoint;
begin
  Result := '';
  s := TbScanCss(AText);
  try
    hits := TbFindRuleSelectors(s, ATypeKey, AVariant);
    for i := 0 to High(hits) do
    begin
      p := TbOffsetToPoint(AText, hits[i]);
      if Result <> '' then Result := Result + ' ';
      Result := Result + Format('(%d,%d)', [p.X, p.Y]);
    end;
  finally
    s.Free;
  end;
end;

procedure TTbRulesTests.CheckNew(const ATag, AText, ATypeKey, AVariant, AWant: string;
  AX, AY: Integer);
var
  s: TTbCssScan;
  e: TTbTextEdits;
  caret: Integer;
  after: string;
  p: TPoint;
begin
  s := TbScanCss(AText);
  try
    e := TbNewRuleEdits(s, #10, ATypeKey, AVariant, caret);
    after := TbApplyEdits(AText, e);
  finally
    s.Free;
  end;
  AssertEquals(ATag + ': the text', AWant, after);
  p := TbOffsetToPoint(after, caret);
  AssertEquals(ATag + ': caret x', AX, p.X);
  AssertEquals(ATag + ': caret y', AY, p.Y);
end;

procedure TTbRulesTests.TestTheStateIsNotTheRule;
begin
  AssertEquals('R1', '(1,2) (9,4)', Points(cRulesDoc, 'TyButton', 'primary'));
  AssertEquals('the selector text', 'TyButton.primary', TbSelectorText('TyButton', 'primary'));
  AssertEquals('without a variant', 'TyButton', TbSelectorText('TyButton', ''));
end;

procedure TTbRulesTests.TestTheCaseDoesNotMatter;
begin
  AssertEquals('R2: the plain one', '(1,1)', Points(cRulesDoc, 'TyButton', ''));
  AssertEquals('R2: any case', '(1,2) (9,4)', Points(cRulesDoc, 'tybutton', 'PRIMARY'));
end;

procedure TTbRulesTests.TestACommentedRuleIsNotFound;
begin
  AssertEquals('R3', '(1,2)', Points('/* TyButton.primary { } */'#10'TyButton.primary { }',
    'TyButton', 'primary'));
end;

procedure TTbRulesTests.TestModeBlocksHaveNoRules;
const
  cT = '@mode dark { :root { --a: #111; } }'#10'TyEdit { }';
begin
  AssertEquals('R4: found', '(1,2)', Points(cT, 'TyEdit', ''));
  AssertEquals('R4: none', '', Points(cT, 'TyButton', ''));
end;

procedure TTbRulesTests.TestAddingAtTheEnd;
begin
  CheckNew('R5', 'TyEdit { }'#10, 'TyButton', 'primary',
    'TyEdit { }'#10#10'TyButton.primary {'#10'  '#10'}'#10, 3, 4);
end;

procedure TTbRulesTests.TestAddingWithoutAFinalBreak;
begin
  CheckNew('R6', 'TyEdit { }', 'TyButton', 'primary',
    'TyEdit { }'#10#10'TyButton.primary {'#10'  '#10'}', 3, 4);
end;

procedure TTbRulesTests.TestAddingToAnEmptyText;
begin
  CheckNew('R7', '', 'TyButton', '', 'TyButton {'#10'  '#10'}'#10, 3, 2);
end;

initialization
  RegisterTest(TTbCssScanTests);
  RegisterTest(TTbRulesTests);
end.
