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
end;

initialization
  RegisterTest(TTestCssParser);
end.
