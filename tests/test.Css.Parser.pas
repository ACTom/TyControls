unit test.Css.Parser;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.Css.Parser;

type
  TTestCssParser = class(TTestCase)
  private
    function RuleAt(ASheet: TTyCssStylesheet; AIndex: Integer): TTyCssRule;
  published
    procedure TestRootVars;
    procedure TestTypeSelectorAndDeclarations;
    procedure TestVariantAndStateSelector;
    procedure TestCommaSelectorList;
    procedure TestFullStylesheet;
    procedure TestErrorMissingBrace;
    procedure TestErrorMissingSemicolon;
    procedure TestRawValueRoundTrips;
    procedure TestImportCollectedInSourceOrder;
    procedure TestImportUrlForm;
    procedure TestImportAfterRuleRaises;
    procedure TestUnknownAtRuleRaises;
    procedure TestModeBlockParses;
    procedure TestModeBlockAfterRuleParses;
    procedure TestModeBlockNonRootRaises;
  end;

implementation

function TTestCssParser.RuleAt(ASheet: TTyCssStylesheet; AIndex: Integer): TTyCssRule;
begin
  Result := TTyCssRule(ASheet.Rules[AIndex]);
end;

procedure TTestCssParser.TestRootVars;
var
  p: TTyCssParser;
  sheet: TTyCssStylesheet;
begin
  p := TTyCssParser.Create(':root { --accent: #3B82F6; --radius: 6px; }');
  try
    sheet := p.Parse;
    try
      AssertEquals('no rules', 0, sheet.Rules.Count);
      AssertEquals('accent var', '#3B82F6', sheet.RootVars.Values['accent']);
      AssertEquals('radius var', '6px', sheet.RootVars.Values['radius']);
    finally
      sheet.Free;
    end;
  finally
    p.Free;
  end;
end;

procedure TTestCssParser.TestTypeSelectorAndDeclarations;
var
  p: TTyCssParser;
  sheet: TTyCssStylesheet;
  r: TTyCssRule;
begin
  p := TTyCssParser.Create('TyButton { background: var(--surface); color: #FFFFFF; }');
  try
    sheet := p.Parse;
    try
      AssertEquals('one rule', 1, sheet.Rules.Count);
      r := RuleAt(sheet, 0);
      AssertEquals('one selector', 1, Length(r.Selectors));
      AssertEquals('typename', 'TyButton', r.Selectors[0].TypeName);
      AssertEquals('no variant', '', r.Selectors[0].Variant);
      AssertFalse('no state', r.Selectors[0].HasState);
      AssertEquals('two decls', 2, Length(r.Declarations));
      AssertEquals('prop1', 'background', r.Declarations[0].Prop);
      AssertEquals('raw1', 'var(--surface)', r.Declarations[0].RawValue);
      AssertEquals('prop2', 'color', r.Declarations[1].Prop);
      AssertEquals('raw2', '#FFFFFF', r.Declarations[1].RawValue);
    finally
      sheet.Free;
    end;
  finally
    p.Free;
  end;
end;

procedure TTestCssParser.TestVariantAndStateSelector;
var
  p: TTyCssParser;
  sheet: TTyCssStylesheet;
  r: TTyCssRule;
begin
  p := TTyCssParser.Create('TyButton.primary:hover { opacity: 0.5; }');
  try
    sheet := p.Parse;
    try
      r := RuleAt(sheet, 0);
      AssertEquals('typename', 'TyButton', r.Selectors[0].TypeName);
      AssertEquals('variant', 'primary', r.Selectors[0].Variant);
      AssertTrue('has state', r.Selectors[0].HasState);
      AssertTrue('state hover', r.Selectors[0].State = tysHover);
    finally
      sheet.Free;
    end;
  finally
    p.Free;
  end;
end;

procedure TTestCssParser.TestCommaSelectorList;
var
  p: TTyCssParser;
  sheet: TTyCssStylesheet;
  r: TTyCssRule;
begin
  p := TTyCssParser.Create('TyButton:active, TyEdit:disabled { color: #000000; }');
  try
    sheet := p.Parse;
    try
      r := RuleAt(sheet, 0);
      AssertEquals('two selectors', 2, Length(r.Selectors));
      AssertEquals('sel0 type', 'TyButton', r.Selectors[0].TypeName);
      AssertTrue('sel0 active', r.Selectors[0].State = tysActive);
      AssertEquals('sel1 type', 'TyEdit', r.Selectors[1].TypeName);
      AssertTrue('sel1 disabled', r.Selectors[1].State = tysDisabled);
    finally
      sheet.Free;
    end;
  finally
    p.Free;
  end;
end;

procedure TTestCssParser.TestFullStylesheet;
var
  p: TTyCssParser;
  sheet: TTyCssStylesheet;
begin
  p := TTyCssParser.Create(
    ':root { --accent: #3B82F6; }' + LineEnding +
    'TyButton { background: var(--accent); }' + LineEnding +
    'TyButton.primary { background: #FF0000; }' + LineEnding +
    'TyButton:focus { border-width: 2px; }');
  try
    sheet := p.Parse;
    try
      AssertEquals('accent var', '#3B82F6', sheet.RootVars.Values['accent']);
      AssertEquals('three rules', 3, sheet.Rules.Count);
      AssertEquals('rule0 type', 'TyButton', RuleAt(sheet, 0).Selectors[0].TypeName);
      AssertEquals('rule1 variant', 'primary', RuleAt(sheet, 1).Selectors[0].Variant);
      AssertTrue('rule2 focus', RuleAt(sheet, 2).Selectors[0].State = tysFocused);
    finally
      sheet.Free;
    end;
  finally
    p.Free;
  end;
end;

procedure TTestCssParser.TestErrorMissingBrace;
var
  p: TTyCssParser;
  raised: Boolean;
begin
  p := TTyCssParser.Create('TyButton background: #fff; }');
  raised := False;
  try
    try
      p.Parse.Free;
    except
      on E: ETyCssError do
        raised := True;
    end;
    AssertTrue('missing open brace raises ETyCssError', raised);
  finally
    p.Free;
  end;
end;

procedure TTestCssParser.TestErrorMissingSemicolon;
var
  p: TTyCssParser;
  raised: Boolean;
begin
  p := TTyCssParser.Create('TyButton { color: #fff border-width: 2px; }');
  raised := False;
  try
    try
      p.Parse.Free;
    except
      on E: ETyCssError do
        raised := True;
    end;
    AssertTrue('missing semicolon raises ETyCssError', raised);
  finally
    p.Free;
  end;
end;

procedure TTestCssParser.TestRawValueRoundTrips;

  function ParseRaw(const AValue: string): string;
  var
    p: TTyCssParser;
    sheet: TTyCssStylesheet;
  begin
    p := TTyCssParser.Create('T { p: ' + AValue + '; }');
    try
      sheet := p.Parse;
      try
        Result := TTyCssRule(sheet.Rules[0]).Declarations[0].RawValue;
      finally
        sheet.Free;
      end;
    finally
      p.Free;
    end;
  end;

begin
  AssertEquals('6px round-trips',                  '6px',                     ParseRaw('6px'));
  AssertEquals('6.5px round-trips',                '6.5px',                   ParseRaw('6.5px'));
  AssertEquals('0 auto round-trips',               '0 auto',                  ParseRaw('0 auto'));
  AssertEquals('0 8px round-trips',                '0 8px',                   ParseRaw('0 8px'));
  AssertEquals('8px 12px round-trips',             '8px 12px',                ParseRaw('8px 12px'));
  AssertEquals('lighten(var(--accent), 8%) round-trips',
                                                   'lighten(var(--accent), 8%)',
                                                   ParseRaw('lighten(var(--accent), 8%)'));
  AssertEquals('var(--surface) round-trips',       'var(--surface)',           ParseRaw('var(--surface)'));
  // separator before hash/function/string tokens
  AssertEquals('px then hash: space inserted',
                                                   '2px 4px 8px #00000080',
                                                   ParseRaw('2px 4px 8px #00000080'));
  AssertEquals('px then var(): space inserted',
                                                   '4px var(--gap)',
                                                   ParseRaw('4px var(--gap)'));
  AssertEquals('multi-px then var(): space inserted',
                                                   '2px 4px 8px var(--c)',
                                                   ParseRaw('2px 4px 8px var(--c)'));
end;

procedure TTestCssParser.TestImportCollectedInSourceOrder;
var
  p: TTyCssParser;
  sheet: TTyCssStylesheet;
begin
  // @import is collected as raw paths in source order; the parser does NO file I/O.
  p := TTyCssParser.Create('@import "base"; @import "more"; TyButton { color: #111111; }');
  try
    sheet := p.Parse;
    try
      AssertEquals('two imports collected', 2, Length(sheet.Imports));
      AssertEquals('import 0', 'base', sheet.Imports[0]);
      AssertEquals('import 1', 'more', sheet.Imports[1]);
      AssertEquals('rule still parsed', 1, sheet.Rules.Count);
    finally
      sheet.Free;
    end;
  finally
    p.Free;
  end;
end;

procedure TTestCssParser.TestImportUrlForm;
var
  p: TTyCssParser;
  sheet: TTyCssStylesheet;
begin
  // url("...") form yields the same raw path as the bare-string form.
  p := TTyCssParser.Create('@import url("theme/base.tycss");');
  try
    sheet := p.Parse;
    try
      AssertEquals('one import', 1, Length(sheet.Imports));
      AssertEquals('url() path', 'theme/base.tycss', sheet.Imports[0]);
    finally
      sheet.Free;
    end;
  finally
    p.Free;
  end;
end;

procedure TTestCssParser.TestImportAfterRuleRaises;
var
  p: TTyCssParser;
  raised: Boolean;
begin
  // CSS requires @import to precede all rules; an @import after a rule is an error.
  p := TTyCssParser.Create('TyButton { color: #111111; } @import "late";');
  raised := False;
  try
    try
      p.Parse.Free;
    except
      on E: ETyCssError do
        raised := True;
    end;
    AssertTrue('@import after a rule raises ETyCssError', raised);
  finally
    p.Free;
  end;
end;

procedure TTestCssParser.TestUnknownAtRuleRaises;
var
  p: TTyCssParser;
  raised: Boolean;
begin
  p := TTyCssParser.Create('@bogus "x";');
  raised := False;
  try
    try
      p.Parse.Free;
    except
      on E: ETyCssError do
        raised := True;
    end;
    AssertTrue('unknown at-rule raises ETyCssError', raised);
  finally
    p.Free;
  end;
end;

procedure TTestCssParser.TestModeBlockParses;
var
  p: TTyCssParser;
  sheet: TTyCssStylesheet;
  mb: TTyCssModeBlock;
begin
  // '@mode <ident> { :root { … } }' collects a TTyCssModeBlock with the mode name and
  // its inner :root vars; the parser does no resolution.
  p := TTyCssParser.Create(
    ':root { --accent: #111111; }' + LineEnding +
    '@mode light { :root { --surface: #FFFFFF; --on-surface: #000000; } }' + LineEnding +
    '@mode dark  { :root { --surface: #1E1E1E; } }');
  try
    sheet := p.Parse;
    try
      AssertEquals('top-level root var', '#111111', sheet.RootVars.Values['accent']);
      AssertEquals('two mode blocks', 2, sheet.ModeBlocks.Count);
      mb := TTyCssModeBlock(sheet.ModeBlocks[0]);
      AssertEquals('mode 0 name', 'light', mb.Mode);
      AssertEquals('mode 0 surface', '#FFFFFF', mb.Vars.Values['surface']);
      AssertEquals('mode 0 on-surface', '#000000', mb.Vars.Values['on-surface']);
      mb := TTyCssModeBlock(sheet.ModeBlocks[1]);
      AssertEquals('mode 1 name', 'dark', mb.Mode);
      AssertEquals('mode 1 surface', '#1E1E1E', mb.Vars.Values['surface']);
    finally
      sheet.Free;
    end;
  finally
    p.Free;
  end;
end;

procedure TTestCssParser.TestModeBlockAfterRuleParses;
var
  p: TTyCssParser;
  sheet: TTyCssStylesheet;
begin
  // Unlike @import, a @mode block carries tokens (not a file ref) and may appear AFTER
  // rules — it must not trip the @import-must-precede-rules guard.
  p := TTyCssParser.Create(
    'TyButton { color: #111111; }' + LineEnding +
    '@mode dark { :root { --accent: #60A5FA; } }');
  try
    sheet := p.Parse;
    try
      AssertEquals('rule still parsed', 1, sheet.Rules.Count);
      AssertEquals('one mode block', 1, sheet.ModeBlocks.Count);
      AssertEquals('mode name', 'dark', TTyCssModeBlock(sheet.ModeBlocks[0]).Mode);
    finally
      sheet.Free;
    end;
  finally
    p.Free;
  end;
end;

procedure TTestCssParser.TestModeBlockNonRootRaises;
var
  p: TTyCssParser;
  raised: Boolean;
begin
  // Only :root blocks are allowed inside @mode (v1); a plain selector inside raises.
  p := TTyCssParser.Create('@mode light { TyButton { color: #fff; } }');
  raised := False;
  try
    try
      p.Parse.Free;
    except
      on E: ETyCssError do
        raised := True;
    end;
    AssertTrue('non-:root inside @mode raises ETyCssError', raised);
  finally
    p.Free;
  end;
end;

initialization
  RegisterTest(TTestCssParser);
end.
