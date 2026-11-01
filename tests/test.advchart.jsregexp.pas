unit test.advchart.jsregexp;
{$mode objfpc}{$H+}
{ `new RegExp(source).test(text)`, held to V8's own answers [spec 242].

  tools/advchart-oracle/js-regexp.js records what node answers for a curated
  set of patterns -- one or more per rule of the grammar and the matchers
  that tyControls.AdvanceChart.JsRegExp follows -- and for four thousand
  patterns strung from a seeded generator, each against eight texts. Every
  answer must be the same: true, false, or the SyntaxError the constructor
  throws (ETyJsRegExpError here). }
interface
uses Classes, SysUtils, fpcunit, testregistry, fpjson, jsonparser,
     tyControls.AdvanceChart.JsRegExp;
type
  TAdvChartJsRegExpTest = class(TTestCase)
  private
    FRoot: TJSONData;
    function Check(AFrom, ATo: Integer; out AReport: string): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheCuratedPatternsAnswerAsV8;
    procedure TestTheGeneratedPatternsAnswerAsV8;
    procedure TestABacktrackingBombStopsWithAnError;
  end;

implementation

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-js-regexp.json';
end;

procedure TAdvChartJsRegExpTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
end;

procedure TAdvChartJsRegExpTest.TearDown;
begin
  FreeAndNil(FRoot);
  inherited TearDown;
end;

function TAdvChartJsRegExpTest.Check(AFrom, ATo: Integer; out AReport: string): Integer;
var
  rows, r: TJSONArray;
  i: Integer;
  re: TTyJsRegExp;
  want, got: string;
begin
  Result := 0;
  AReport := '';
  rows := TJSONObject(FRoot).Arrays['rows'];
  for i := AFrom to ATo - 1 do
  begin
    r := rows.Arrays[i];
    if r.Items[2].JSONType = jtString then want := 'SyntaxError'
    else if r.Items[2].AsBoolean then want := 'true'
    else want := 'false';
    try
      re := TyJsRegExpCreate(r.Strings[0]);
      try
        if TyJsRegExpTest(re, r.Strings[1]) then got := 'true' else got := 'false';
      finally
        re.Free;
      end;
    except
      on E: ETyJsRegExpError do got := 'SyntaxError';
    end;
    if got <> want then
    begin
      Inc(Result);
      if Result <= 15 then
        AReport := AReport + LineEnding + Format('  /%s/ on %s: %s, V8 %s',
          [r.Strings[0], r.Items[1].AsJSON, got, want]);
    end;
  end;
end;

procedure TAdvChartJsRegExpTest.TestTheCuratedPatternsAnswerAsV8;
var
  n, bad: Integer;
  report: string;
begin
  n := TJSONObject(FRoot).Integers['curated'];
  AssertTrue('enough curated rows', n >= 300);
  bad := Check(0, n, report);
  AssertEquals(IntToStr(bad) + ' of ' + IntToStr(n) + ' differ:' + report, 0, bad);
end;

procedure TAdvChartJsRegExpTest.TestTheGeneratedPatternsAnswerAsV8;
var
  n, m, bad: Integer;
  report: string;
begin
  n := TJSONObject(FRoot).Integers['curated'];
  m := TJSONObject(FRoot).Arrays['rows'].Count;
  AssertTrue('enough generated rows', m - n >= 10000);
  bad := Check(n, m, report);
  AssertEquals(IntToStr(bad) + ' of ' + IntToStr(m - n) + ' differ:' + report, 0, bad);
end;

procedure TAdvChartJsRegExpTest.TestABacktrackingBombStopsWithAnError;
var
  re: TTyJsRegExp;
  raised: Boolean;
begin
  re := TyJsRegExpCreate('^(a+)+b$');
  try
    AssertTrue('a short text still answers', not TyJsRegExpTest(re, 'aaaa'));
    raised := False;
    try
      TyJsRegExpTest(re, StringOfChar('a', 60));
    except
      on E: ETyJsRegExpError do raised := True;
    end;
    AssertTrue('sixty a''s give up instead of running for ever', raised);
  finally
    re.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartJsRegExpTest);
end.
