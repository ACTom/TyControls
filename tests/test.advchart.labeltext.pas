unit test.advchart.labeltext;
{$mode objfpc}{$H+}
{ The TEXT a value or log axis puts on the screen, held to upstream's own.

  tools/advchart-oracle/axis-labels.js runs the real ECharts 6.1 build and
  records, in tests/fixtures/advchart-axis-labels.json:
    ticks     every tick label getViewLabels gives, formatter templates too;
    getLabel  IntervalScale.getLabel at a chosen precision on a real scale;
    pointer   the label an axis pointer draws at a value;
    header    the header of an 'axis' tooltip, captured through its own
              formatter parameters.
  Values travel as IEEE bits, because the JSON reader here misparses an
  integer literal past 2^63 and JSON.stringify writes some Doubles that way.
  Every string is compared exactly, and once more with the machine's decimal
  separator set to a comma: upstream's text does not know about locales. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Scale, tyControls.AdvChart.Coord,
     tyControls.AdvChart.Builder, tyControls.AdvChart.Layout,
     tyControls.AdvChart.Tooltip, tyControls.AdvChart.AxisPointer,
     tyControls.AdvanceChart, test.advchart.axispointer;
type
  TAdvChartLabelTextOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TAxisProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad: Integer;
    FCompared: Integer;
    FReport: string;
    procedure SetUp; override;
    procedure TearDown; override;
    function Section(const AName: string): TJSONArray;
    procedure DrawCase(ACase: TJSONObject);
    function AxisOf(ACase: TJSONObject): TTyAxis;
    procedure Miss(ACase: TJSONObject; const AWhat: string);
    procedure CheckTicks;
    procedure CheckGetLabel;
    procedure CheckPointers;
    procedure CheckHeaders;
    procedure Verdict(AMinimum: Integer);
  published
    procedure TestTickLabels;
    procedure TestGetLabel;
    procedure TestPointerLabels;
    procedure TestTooltipHeaders;
    procedure TestNoneOfItFollowsTheLocale;
  end;

  TAdvChartJsTextTest = class(TTestCase)
  published
    procedure TestNumberToStringIsTheShortestThatReadsBack;
    procedure TestToFixedStringKeepsTheSignAndPads;
    procedure TestAddCommasGroupsOnlyTheIntegerDigits;
    procedure TestAPrecisionIsReadAsNumberReadsIt;
    procedure TestAnyPrecisionIsSafe;
  end;

  TAdvChartLabelTemplateTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TAxisProbe;
    FBmp: TBGRABitmap;
    procedure SetUp; override;
    procedure TearDown; override;
    function Labels(const AOption: string; AOnX: Boolean): string;
  published
    procedure TestACategoryAxisTakesTheTemplateToo;
  end;

implementation

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-axis-labels.json';
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

procedure TAdvChartLabelTextOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TAxisProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartLabelTextOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  FreeAndNil(FBmp);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

function TAdvChartLabelTextOracleTest.Section(const AName: string): TJSONArray;
begin
  Result := TJSONObject(FRoot).Arrays[AName];
end;

procedure TAdvChartLabelTextOracleTest.DrawCase(ACase: TJSONObject);
begin
  FChart.Option := ACase.Objects['option'].AsJSON;
  AssertEquals(ACase.Strings['name'] + ' parses', '', FChart.OptionError);
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
end;

function TAdvChartLabelTextOracleTest.AxisOf(ACase: TJSONObject): TTyAxis;
begin
  if ACase.Strings['axis'] = 'x' then Result := FChart.Build.Grid(0).XAxis(0)
  else Result := FChart.Build.Grid(0).YAxis(0);
end;

procedure TAdvChartLabelTextOracleTest.Miss(ACase: TJSONObject; const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 20 then
    FReport := FReport + LineEnding + '  ' + ACase.Strings['name'] + ': ' + AWhat;
end;

procedure TAdvChartLabelTextOracleTest.Verdict(AMinimum: Integer);
begin
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared >= AMinimum);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
end;

procedure TAdvChartLabelTextOracleTest.CheckTicks;
var
  cases, want, vals: TJSONArray;
  cs: TJSONObject;
  c, i, n: Integer;
  ax: TTyAxis;
  spec: PTyAxisLayoutSpec;
  ticks, all: TTyScaleTickArray;
begin
  cases := Section('ticks');
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    DrawCase(cs);
    ax := AxisOf(cs);
    want := cs.Arrays['labels'];
    vals := cs.Arrays['values'];
    { THE VALUES FIRST, so a miss says which half is wrong: a tick at another
      value is batch 33's business, the text of the right value is this one. }
    all := TyDrawnTicks(ax.Scale);
    ticks := nil;
    for i := 0 to High(all) do
      if all[i].Level = 0 then
      begin
        SetLength(ticks, Length(ticks) + 1);
        ticks[High(ticks)] := all[i];
      end;
    Inc(FCompared);
    if Length(ticks) <> vals.Count then
    begin
      Miss(cs, Format('%d tick values upstream, %d here', [vals.Count, Length(ticks)]));
      Continue;
    end;
    for i := 0 to vals.Count - 1 do
      if ticks[i].Value <> FromHex(vals.Strings[i]) then
      begin
        Miss(cs, Format('tick %d is %s upstream', [i, cs.Arrays['valuesText'].Strings[i]]));
        Break;
      end;
    spec := FChart.Build.Grid(0).SpecFor(ax);
    Inc(FCompared);
    if spec = nil then
    begin
      Miss(cs, 'no layout spec');
      Continue;
    end;
    n := Length(spec^.Labels);
    if n <> want.Count then
    begin
      Miss(cs, Format('%d labels upstream, %d here', [want.Count, n]));
      Continue;
    end;
    for i := 0 to n - 1 do
    begin
      Inc(FCompared);
      if spec^.Labels[i] <> want.Strings[i] then
        Miss(cs, Format('label %d is "%s" upstream, "%s" here',
          [i, want.Strings[i], spec^.Labels[i]]));
    end;
  end;
end;

procedure TAdvChartLabelTextOracleTest.CheckGetLabel;
var
  cases: TJSONArray;
  cs: TJSONObject;
  c: Integer;
  d: TJSONData;
  p: TTyLabelPrecision;
  got: string;
begin
  cases := Section('getLabel');
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    DrawCase(cs);
    d := cs.Find('precision');
    { no option at all is the tick's own precision; anything written is read
      the way the pointer's label.precision is }
    if (d = nil) or (d.JSONType = jtNull) then p := TyLabelPrecision(lpNone)
    else p := TyLabelPrecisionOf(d);
    got := TyScaleValueLabel(AxisOf(cs).Scale, FromHex(cs.Strings['value']), p);
    Inc(FCompared);
    if got <> cs.Strings['text'] then
      Miss(cs, Format('"%s" upstream, "%s" here', [cs.Strings['text'], got]));
  end;
end;

procedure TAdvChartLabelTextOracleTest.CheckPointers;
var
  cases: TJSONArray;
  cs: TJSONObject;
  c: Integer;
  opt: TTyChartOption;
  ax: TTyAxis;
  spec: TTyAxisPointerSpec;
  main, got: string;
  tip: Boolean;
begin
  cases := Section('pointer');
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    DrawCase(cs);
    ax := AxisOf(cs);
    if cs.Strings['axis'] = 'x' then main := 'xAxis' else main := 'yAxis';
    opt := TTyChartOption.Create;
    try
      AssertTrue(cs.Strings['name'] + ': the option parses',
        opt.SetOptionText(cs.Objects['option'].AsJSON));
      { The axis' own pointer -- driven by the tooltip as well when there is an
        'axis' tooltip, which then points at this axis in every case here, and
        whose axisPointer.label is a level of the cascade. }
      tip := (cs.Objects['option'].Find('tooltip') is TJSONObject)
        and (TJSONObject(cs.Objects['option'].Find('tooltip')).Get('trigger', '') = 'axis');
      spec := TyAxisPointerSpecOf(opt, main, 0, ax.Scale is TTyOrdinalScale,
        tip, tip, False);
    finally
      opt.Free;
    end;
    got := FChart.PointerText(ax, FromHex(cs.Strings['value']), spec.LabelSpec);
    Inc(FCompared);
    if got <> cs.Strings['text'] then
      Miss(cs, Format('"%s" upstream, "%s" here', [cs.Strings['text'], got]));
  end;
end;

procedure TAdvChartLabelTextOracleTest.CheckHeaders;
var
  cases: TJSONArray;
  cs: TJSONObject;
  c, i, x, y: Integer;
  ax: TTyAxis;
  r: TTyRectF;
  hits: TTyAxisHitArray;
  block: TTyTooltipBlock;
  sect: TTyTooltipBlock;
begin
  cases := Section('header');
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    DrawCase(cs);
    ax := AxisOf(cs);
    r := FChart.Build.Grid(0).PlotRect;
    { A REAL HOVER, over the row the case snaps to: the header goes through
      the tooltip's own path, pointer spec and all, not through a copy. }
    x := Round(ax.DataToCoord(FromHex(cs.Strings['value'])));
    y := Round((r.Top + r.Bottom) / 2);
    hits := FChart.Pointers(x, y);
    Inc(FCompared);
    block := FChart.AxisContent(hits, TyTooltipSpecDefault);
    try
      if (block = nil) or (block.BlockCount = 0) then
      begin
        Miss(cs, 'no tooltip section');
        Continue;
      end;
      sect := nil;
      for i := 0 to block.BlockCount - 1 do
        if sect = nil then sect := block.Blocks[i];
      if cs.Booleans['noHeader'] then
      begin
        if not sect.NoHeader then
          Miss(cs, Format('no header upstream, "%s" here', [sect.Header]));
      end
      else if sect.NoHeader or (sect.Header <> cs.Strings['text']) then
        Miss(cs, Format('"%s" upstream, "%s" here', [cs.Strings['text'], sect.Header]));
    finally
      block.Free;
    end;
  end;
end;

procedure TAdvChartLabelTextOracleTest.TestTickLabels;
begin
  CheckTicks;
  Verdict(300);
end;

procedure TAdvChartLabelTextOracleTest.TestGetLabel;
begin
  CheckGetLabel;
  Verdict(80);
end;

procedure TAdvChartLabelTextOracleTest.TestPointerLabels;
begin
  CheckPointers;
  Verdict(20);
end;

procedure TAdvChartLabelTextOracleTest.TestTooltipHeaders;
begin
  CheckHeaders;
  Verdict(10);
end;

procedure TAdvChartLabelTextOracleTest.TestNoneOfItFollowsTheLocale;
var saved: TFormatSettings;
begin
  { A comma for the decimal point and a point for the thousands -- the
    machine setting most likely to leak into a number printed through FPC's
    own formatting. Upstream's strings know nothing about it. }
  saved := DefaultFormatSettings;
  try
    DefaultFormatSettings.DecimalSeparator := ',';
    DefaultFormatSettings.ThousandSeparator := '.';
    CheckTicks;
    CheckGetLabel;
    CheckPointers;
    CheckHeaders;
  finally
    DefaultFormatSettings := saved;
  end;
  Verdict(400);
end;

{ ==================== the routines themselves ==================== }

procedure TAdvChartJsTextTest.TestNumberToStringIsTheShortestThatReadsBack;
begin
  AssertEquals('0.1', TyJsNumberToString(0.1));
  AssertEquals('the sum keeps every digit it needs', '0.30000000000000004',
    TyJsNumberToString(0.1 + 0.2));
  AssertEquals('0', TyJsNumberToString(0));
  AssertEquals('negative zero prints as zero', '0', TyJsNumberToString(-0.0));
  AssertEquals('-2.5', TyJsNumberToString(-2.5));
  AssertEquals('positional down to 1e-6', '0.000001', TyJsNumberToString(1e-6));
  AssertEquals('an exponent from 1e-7', '1e-7', TyJsNumberToString(1e-7));
  AssertEquals('1.5e-7', TyJsNumberToString(1.5e-7));
  AssertEquals('positional below 1e21', '100000000000000000000',
    TyJsNumberToString(1e20));
  AssertEquals('an exponent from 1e21', '1e+21', TyJsNumberToString(1e21));
  AssertEquals('3.0000000000000003e+27', TyJsNumberToString(3.0000000000000003e27));
  AssertEquals('the largest Double', '1.7976931348623157e+308',
    TyJsNumberToString(MaxDouble));
  AssertEquals('the smallest denormal', '5e-324', TyJsNumberToString(4.9406564584124654e-324));
  AssertEquals('NaN', TyJsNumberToString(NaN));
  AssertEquals('-Infinity', TyJsNumberToString(NegInfinity));
  { THE DIGITS CARRY INTO A NEW PLACE: the Double nearest 1e23 is just under
    it, so its one-digit decimal rounds up to ten -- which is one digit of
    the next power, not the two digits '10'. }
  AssertEquals('1e+23', TyJsNumberToString(1e23));
  { and its two neighbours, from their bits }
  AssertEquals('9.999999999999997e+22', TyJsNumberToString(FromHex('44b52d02c7e14af5')));
  AssertEquals('1.0000000000000001e+23', TyJsNumberToString(FromHex('44b52d02c7e14af7')));
  { BOTH DECIMALS EITHER SIDE ARE ASKED, not only the nearer: at the bottom
    of a binade the nearer one can fall in the narrower half below and fail
    while the farther one reads back. 2^-1015 took seventeen digits here
    before. Each of these was wrong under one mutation of the rule; node
    gave the strings. }
  AssertEquals('2^-1015', '7.120236347223045e-307', TyJsNumberToString(FromHex('0060000000000000')));
  AssertEquals('2^-1012', '1.1392378155556871e-305', TyJsNumberToString(FromHex('00a0000000000000')));
  AssertEquals('a lower bound that reads back', '46669700299389660', TyJsNumberToString(FromHex('4364b9bb0b83cf5c')));
  AssertEquals('an upper one', '-321394605096429600', TyJsNumberToString(FromHex('c391d74ac315ffa0')));
  AssertEquals('two equally near, the even one', '2.9802322387695312e-8', TyJsNumberToString(FromHex('3e60000000000000')));
  AssertEquals('and again', '1125899906842624.2', TyJsNumberToString(FromHex('4310000000000001')));
  AssertEquals('a denormal', '2.0237e-320', TyJsNumberToString(FromHex('0000000000001000')));
end;

procedure TAdvChartJsTextTest.TestToFixedStringKeepsTheSignAndPads;
begin
  AssertEquals('on the binary value', '1.00', TyJsToFixedStr(1.005, 2));
  AssertEquals('a real half goes away from zero', '3', TyJsToFixedStr(2.5, 0));
  AssertEquals('-3', TyJsToFixedStr(-2.5, 0));
  AssertEquals('a negative that rounds to nothing keeps its sign', '-0.00',
    TyJsToFixedStr(-0.001, 2));
  AssertEquals('negative zero does not', '0.00', TyJsToFixedStr(-0.0, 2));
  AssertEquals('padded', '3.000', TyJsToFixedStr(3, 3));
  AssertEquals('a small value in full', '0.0000001', TyJsToFixedStr(1e-7, 7));
  AssertEquals('clamped at twenty', '1.50000000000000000000', TyJsToFixedStr(1.5, 25));
  AssertEquals('an exact large whole number, not its shortest form',
    '123456789012345683968', TyJsToFixedStr(123456789012345680000.0, 0));
  AssertEquals('from 1e21 it is ToString', '1e+21', TyJsToFixedStr(1e21, 2));
  AssertEquals('NaN', TyJsToFixedStr(NaN, 2));
end;

procedure TAdvChartJsTextTest.TestAddCommasGroupsOnlyTheIntegerDigits;
begin
  AssertEquals('1,234,567', TyJsAddCommas('1234567'));
  AssertEquals('-1,234,567.1234567', TyJsAddCommas('-1234567.1234567'));
  AssertEquals('three digits alone', '123', TyJsAddCommas('123'));
  AssertEquals('an exponent passes through', '1e+21', TyJsAddCommas('1e+21'));
  AssertEquals('NaN', TyJsAddCommas('NaN'));
  AssertEquals('-0.00', TyJsAddCommas('-0.00'));
  AssertEquals('only before the first point', '1,000.1234', TyJsAddCommas('1000.1234'));
end;

procedure TAdvChartJsTextTest.TestAPrecisionIsReadAsNumberReadsIt;

  function Read(const AJson: string): TTyLabelPrecision;
  var d: TJSONData;
  begin
    d := GetJSON(AJson);
    try
      Result := TyLabelPrecisionOf(d);
    finally
      d.Free;
    end;
  end;

  procedure Digits(const AMsg, AJson: string; AWant: Double);
  var p: TTyLabelPrecision;
  begin
    p := Read(AJson);
    AssertTrue(AMsg + ' is a number', p.Kind = lpDigits);
    AssertEquals(AMsg, AWant, p.Digits, 0);
  end;

begin
  AssertTrue('auto', Read('"auto"').Kind = lpAuto);
  Digits('3', '3', 3);
  Digits('a numeric string', '"3"', 3);
  Digits('an empty string is nought', '""', 0);
  Digits('true is one', 'true', 1);
  Digits('false is nought', 'false', 0);
  Digits('an empty array is nought', '[]', 0);
  Digits('a one-number array is that number', '[4]', 4);
  AssertTrue('a word is not a number', Read('"abc"').Kind = lpNotANumber);
  AssertTrue('nor is an object', Read('{}').Kind = lpNotANumber);
  AssertTrue('nor a longer array', Read('[1, 2]').Kind = lpNotANumber);
end;

procedure TAdvChartJsTextTest.TestAnyPrecisionIsSafe;
var s: TTyIntervalScale;
begin
  s := TTyIntervalScale.Create;
  try
    s.SetExtent(TyRange(0, 10));
    s.Niceify(5);
    { clamped before it is truncated: an unclamped 1e300 does not fit an
      Integer, and truncating it raised }
    AssertEquals('a huge precision is twenty', '1.50000000000000000000',
      TyScaleValueLabel(s, 1.5, TyLabelPrecision(lpDigits, 1e300)));
    AssertEquals('a hugely negative one is nought', '2',
      TyScaleValueLabel(s, 1.5, TyLabelPrecision(lpDigits, -1e300)));
    AssertEquals('not a number prints the value''s own ToString', '1.5',
      TyScaleValueLabel(s, 1.5, TyLabelPrecision(lpDigits, NaN)));
    { and where ToString is not the fixed form, it shows }
    AssertEquals('a word for a precision prints 1e-7 as 1e-7', '1e-7',
      TyScaleValueLabel(s, 1e-7, TyLabelPrecision(lpNotANumber)));
    AssertEquals('so does not-a-number digits', '1e-7',
      TyScaleValueLabel(s, 1e-7, TyLabelPrecision(lpDigits, NaN)));
    AssertEquals('a tick of not-a-number', 'NaN',
      TyScaleValueLabel(s, NaN, TyLabelPrecision(lpNone)));
    AssertEquals('an infinite one', 'Infinity',
      TyScaleValueLabel(s, Infinity, TyLabelPrecision(lpNone)));
    AssertEquals('an infinite one under auto', '-Infinity',
      TyScaleValueLabel(s, NegInfinity, TyLabelPrecision(lpAuto)));
  finally
    s.Free;
  end;
end;

{ ==================== the template on every kind of axis ==================== }

procedure TAdvChartLabelTemplateTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TAxisProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
end;

procedure TAdvChartLabelTemplateTest.TearDown;
begin
  FreeAndNil(FBmp);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

function TAdvChartLabelTemplateTest.Labels(const AOption: string;
  AOnX: Boolean): string;
var ax: TTyAxis; spec: PTyAxisLayoutSpec; i: Integer;
begin
  FChart.Option := AOption;
  AssertEquals('the option parses', '', FChart.OptionError);
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  if AOnX then ax := FChart.Build.Grid(0).XAxis(0)
  else ax := FChart.Build.Grid(0).YAxis(0);
  spec := FChart.Build.Grid(0).SpecFor(ax);
  AssertTrue('the axis has a layout spec', spec <> nil);
  Result := '';
  for i := 0 to High(spec^.Labels) do
  begin
    if i > 0 then Result := Result + '|';
    Result := Result + spec^.Labels[i];
  end;
end;

procedure TAdvChartLabelTemplateTest.TestACategoryAxisTakesTheTemplateToo;
begin
  { UPSTREAM'S STRING BRANCH DOES NOT ASK WHAT KIND OF AXIS IT IS: a category
    axis' formatter gets its category where a value axis' gets its number.
    Only a time axis goes elsewhere. }
  AssertEquals('Mon!|Tue!', Labels('{ xAxis: { data: [''Mon'', ''Tue''],'
    + ' axisLabel: { formatter: ''{value}!'' } }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }', True));
  AssertEquals('and without one, the category itself', 'Mon|Tue',
    Labels('{ xAxis: { data: [''Mon'', ''Tue''] }, yAxis: {},'
    + ' series: [{ type: ''bar'', data: [1, 2] }] }', True));
end;

initialization
  RegisterTest(TAdvChartLabelTextOracleTest);
  RegisterTest(TAdvChartJsTextTest);
  RegisterTest(TAdvChartLabelTemplateTest);
end.
