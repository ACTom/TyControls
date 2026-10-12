unit tyControls.AdvChart.Aria;
{$mode objfpc}{$H+}
{ THE CHART'S DESCRIPTION [Batch 131]: the sentence ECharts writes into the
  chart's `aria-label` -- what a screen reader says for a chart that is
  otherwise a picture.

  A PORT OF setLabel in src/visual/aria.ts: the title or not
  (general.withTitle / withoutTitle), the series count prefix
  (series.single / multiple.prefix), one phrase per series the legend kept
  (withName / withoutName, its index, its type's name from the locale's
  series.typeNames), then its data -- all of it or the first maxCount
  (data.allData / partialData), each row as withName / withoutName with
  its values joined by the data separator -- joined by the series
  separators. Placeholders are replaced the way aria.ts replaces them: one
  global RegExp per key -- the key in braces, blanks allowed inside them --
  in the order seriesId, seriesName, seriesType, so a series name that
  holds the seriesType placeholder has it replaced too; and the value is a
  REPLACEMENT STRING, whose dollar-ampersand, two dollars, dollar-backtick
  and dollar-quote mean what String.replace makes them mean.

  The words are the port's resourcestrings (tyControls.StrConsts), whose
  English is ECharts' EN locale (langEN.ts aria and series.typeNames) and
  whose Chinese is its ZH locale; the author's aria.label templates are
  read over them. This unit is handed the FACTS -- the series, their names,
  their rows already printed -- and only assembles the sentence; the
  control gathers them.

  PURE: SysUtils, fpjson and the AdvChart units. }
interface

uses
  SysUtils, fpjson,
  tyControls.AdvChart.Types;

type
  { The templates: the locale's (TyAriaDefaultLocale), with the author's
    read over them (TyAriaLocaleOf). }
  TTyAriaLocale = record
    WithTitle, WithoutTitle: string;
    SinglePrefix, SingleWithName, SingleWithoutName: string;
    MultiPrefix, MultiWithName, MultiWithoutName: string;
    SeriesMiddle, SeriesEnd: string;
    AllData, PartialData, DataWithName, DataWithoutName: string;
    DataMiddle, DataEnd: string;
  end;

  TTyAriaRow = record
    Name: string;
    { every dimension's value, as String(value) prints it }
    Values: TTyStringArray;
  end;

  TTyAriaSeries = record
    { the series' index among the models, holes counted }
    Index: Integer;
    TypeName: string;
    { `seriesModel.get('name')` truthy, and String() of it }
    HasName: Boolean;
    Name: string;
    Rows: array of TTyAriaRow;
  end;

  TTyAriaFacts = record
    { getSeriesCount(): every series model, filtered or not }
    SeriesCount: Integer;
    HasTitle: Boolean;
    Title: string;
    { the series eachSeries meets -- the legend's filtered ones left out }
    Series: array of TTyAriaSeries;
    { data.maxCount || 10, and how it prints into partialData }
    MaxData: Double;
    MaxDataText: string;
    { series.maxCount || 10 }
    MaxSeries: Double;
  end;

{ The locale's templates. }
function TyAriaDefaultLocale: TTyAriaLocale;

{ series.typeNames[subType] || typeNames.chart }
function TyAriaTypeName(const ASubType: string): string;

{ The author's aria templates over ALocale: aria.label's keys -- where the
  option wrote general, series or data at aria's top level (the
  preprocessor's legacy placement) those REPLACE label's -- each one a
  string, or String() of what was written. }
function TyAriaLocaleOf(AAria: TJSONObject; const ALocale: TTyAriaLocale): TTyAriaLocale;

{ aria.label's key at APath (top-level placement first), nil where none }
function TyAriaLabelKey(AAria: TJSONObject; const APath: array of string): TJSONData;

{ For each key in turn: every match of the key in braces (blanks allowed
  inside them) replaced by the value, as aria.ts' replace does it with a
  global RegExp and a replacement string. }
function TyAriaReplace(const AStr: string; const AKeys, AValues: array of string): string;

{ setLabel's sentence; '' when the chart has no series }
function TyAriaLabel(const ALocale: TTyAriaLocale; const AFacts: TTyAriaFacts): string;

implementation

uses tyControls.StrConsts, tyControls.AdvChart.Convert;

const
  { both locales' series.single.prefix and data.withoutName: the same in
    every language, and an empty string is no resourcestring }
  cSinglePrefix = '';
  cDataWithoutName = '{value}';

function TyAriaDefaultLocale: TTyAriaLocale;
var
  seps: TStringArray;
begin
  Result := Default(TTyAriaLocale);
  Result.WithTitle := rsTyChartAriaWithTitle;
  Result.WithoutTitle := rsTyChartAriaWithoutTitle;
  Result.SinglePrefix := cSinglePrefix;
  Result.SingleWithName := rsTyChartAriaSingleWithName;
  Result.SingleWithoutName := rsTyChartAriaSingleWithoutName;
  Result.MultiPrefix := rsTyChartAriaMultiplePrefix;
  Result.MultiWithName := rsTyChartAriaMultipleWithName;
  Result.MultiWithoutName := rsTyChartAriaMultipleWithoutName;
  Result.AllData := rsTyChartAriaAllData;
  Result.PartialData := rsTyChartAriaPartialData;
  Result.DataWithName := rsTyChartAriaDataWithName;
  Result.DataWithoutName := cDataWithoutName;
  { THE FOUR SEPARATORS IN ONE STRING, '|' between them: series middle,
    series end, data middle, data end. Some are empty in one language and
    not in the other (EN joins series with nothing, ZH with a semicolon),
    and an empty resourcestring never reaches a catalogue. }
  seps := String(rsTyChartAriaSeparators).Split(['|']);
  if Length(seps) > 0 then Result.SeriesMiddle := seps[0];
  if Length(seps) > 1 then Result.SeriesEnd := seps[1];
  if Length(seps) > 2 then Result.DataMiddle := seps[2];
  if Length(seps) > 3 then Result.DataEnd := seps[3];
end;

function TyAriaTypeName(const ASubType: string): string;
begin
  case ASubType of
    'pie': Result := rsTyChartTypePie;
    'bar': Result := rsTyChartTypeBar;
    'line': Result := rsTyChartTypeLine;
    'scatter': Result := rsTyChartTypeScatter;
    'effectScatter': Result := rsTyChartTypeEffectScatter;
    'radar': Result := rsTyChartTypeRadar;
    'tree': Result := rsTyChartTypeTree;
    'treemap': Result := rsTyChartTypeTreemap;
    'boxplot': Result := rsTyChartTypeBoxplot;
    'candlestick': Result := rsTyChartTypeCandlestick;
    'k': Result := rsTyChartTypeK;
    'heatmap': Result := rsTyChartTypeHeatmap;
    'map': Result := rsTyChartTypeMap;
    'parallel': Result := rsTyChartTypeParallel;
    'lines': Result := rsTyChartTypeLines;
    'graph': Result := rsTyChartTypeGraph;
    'sankey': Result := rsTyChartTypeSankey;
    'funnel': Result := rsTyChartTypeFunnel;
    'gauge': Result := rsTyChartTypeGauge;
    'pictorialBar': Result := rsTyChartTypePictorialBar;
    'themeRiver': Result := rsTyChartTypeThemeRiver;
    'sunburst': Result := rsTyChartTypeSunburst;
    'custom': Result := rsTyChartTypeCustom;
  else
    Result := rsTyChartTypeChart;
  end;
end;

function TyAriaLabelKey(AAria: TJSONObject; const APath: array of string): TJSONData;
var
  d: TJSONData;
  i: Integer;
begin
  Result := nil;
  if (AAria = nil) or (Length(APath) = 0) then Exit;
  { the preprocessor moves description, general, series and data from
    aria's top level under aria.label, replacing what was there }
  d := AAria.Find(APath[0]);
  if (d = nil) or (d.JSONType = jtNull) then
  begin
    d := AAria.Find('label');
    if not (d is TJSONObject) then Exit;
    d := TJSONObject(d).Find(APath[0]);
  end;
  for i := 1 to High(APath) do
  begin
    if not (d is TJSONObject) then Exit(nil);
    d := TJSONObject(d).Find(APath[i]);
  end;
  Result := d;
end;

function TyAriaLocaleOf(AAria: TJSONObject; const ALocale: TTyAriaLocale): TTyAriaLocale;

  { the author's string at APath, or ADefault; a key written as something
    else is what String() makes of it -- `+=` concatenates whatever it is }
  procedure Take(var AField: string; const APath: array of string);
  var d: TJSONData;
  begin
    d := TyAriaLabelKey(AAria, APath);
    if d <> nil then AField := TyJsonJsString(d);
  end;

begin
  Result := ALocale;
  if AAria = nil then Exit;
  Take(Result.WithTitle, ['general', 'withTitle']);
  Take(Result.WithoutTitle, ['general', 'withoutTitle']);
  Take(Result.SinglePrefix, ['series', 'single', 'prefix']);
  Take(Result.SingleWithName, ['series', 'single', 'withName']);
  Take(Result.SingleWithoutName, ['series', 'single', 'withoutName']);
  Take(Result.MultiPrefix, ['series', 'multiple', 'prefix']);
  Take(Result.MultiWithName, ['series', 'multiple', 'withName']);
  Take(Result.MultiWithoutName, ['series', 'multiple', 'withoutName']);
  Take(Result.SeriesMiddle, ['series', 'multiple', 'separator', 'middle']);
  Take(Result.SeriesEnd, ['series', 'multiple', 'separator', 'end']);
  Take(Result.AllData, ['data', 'allData']);
  Take(Result.PartialData, ['data', 'partialData']);
  Take(Result.DataWithName, ['data', 'withName']);
  Take(Result.DataWithoutName, ['data', 'withoutName']);
  Take(Result.DataMiddle, ['data', 'separator', 'middle']);
  Take(Result.DataEnd, ['data', 'separator', 'end']);
end;

{ JavaScript's \s, as far as a template is likely to hold it }
function IsJsSpace(C: Char): Boolean;
begin
  Result := C in [#9, #10, #11, #12, #13, ' '];
end;

{ GetSubstitution with no capture groups: $$, $&, $` and $' -- anything
  else after a $ is itself }
function Substitute(const AValue, AStr, AMatched: string; APos, AEnd: Integer): string;
var i: Integer;
begin
  Result := '';
  i := 1;
  while i <= Length(AValue) do
  begin
    if (AValue[i] = '$') and (i < Length(AValue)) then
      case AValue[i + 1] of
        '$': begin Result := Result + '$'; Inc(i, 2); Continue; end;
        '&': begin Result := Result + AMatched; Inc(i, 2); Continue; end;
        '`': begin Result := Result + Copy(AStr, 1, APos - 1); Inc(i, 2); Continue; end;
        '''': begin Result := Result + Copy(AStr, AEnd, MaxInt); Inc(i, 2); Continue; end;
      end;
    Result := Result + AValue[i];
    Inc(i);
  end;
end;

{ one key, every match, left to right over the string as it stood }
function ReplaceKey(const AStr, AKey, AValue: string): string;
var
  i, j, start: Integer;
begin
  Result := '';
  i := 1;
  start := 1;
  while i <= Length(AStr) do
  begin
    if AStr[i] = '{' then
    begin
      j := i + 1;
      while (j <= Length(AStr)) and IsJsSpace(AStr[j]) do Inc(j);
      if Copy(AStr, j, Length(AKey)) = AKey then
      begin
        j := j + Length(AKey);
        while (j <= Length(AStr)) and IsJsSpace(AStr[j]) do Inc(j);
        if (j <= Length(AStr)) and (AStr[j] = '}') then
        begin
          Result := Result + Copy(AStr, start, i - start)
            + Substitute(AValue, AStr, Copy(AStr, i, j - i + 1), i, j + 1);
          i := j + 1;
          start := i;
          Continue;
        end;
      end;
    end;
    Inc(i);
  end;
  Result := Result + Copy(AStr, start, MaxInt);
end;

function TyAriaReplace(const AStr: string; const AKeys, AValues: array of string): string;
var k: Integer;
begin
  Result := AStr;
  for k := 0 to High(AKeys) do
    if k <= High(AValues) then Result := ReplaceKey(Result, AKeys[k], AValues[k]);
end;

function TyAriaLabel(const ALocale: TTyAriaLocale; const AFacts: TTyAriaFacts): string;
var
  s, t, rowText, v: string;
  labels: TTyStringArray;
  i, j, k, cnt: Integer;
  disp: Double;
begin
  Result := '';
  if AFacts.SeriesCount < 1 then Exit;
  if AFacts.HasTitle then
    s := TyAriaReplace(ALocale.WithTitle, ['title'], [AFacts.Title])
  else
    s := ALocale.WithoutTitle;
  if AFacts.SeriesCount > 1 then
    s := s + TyAriaReplace(ALocale.MultiPrefix, ['seriesCount'], [IntToStr(AFacts.SeriesCount)])
  else
    s := s + TyAriaReplace(ALocale.SinglePrefix, ['seriesCount'], [IntToStr(AFacts.SeriesCount)]);
  { Math.min(seriesCnt, maxSeriesCnt) }
  disp := AFacts.MaxSeries;
  if AFacts.SeriesCount < disp then disp := AFacts.SeriesCount;
  labels := nil;
  for i := 0 to High(AFacts.Series) do
  begin
    if not (AFacts.Series[i].Index < disp) then Continue;
    if AFacts.SeriesCount > 1 then
    begin
      if AFacts.Series[i].HasName then t := ALocale.MultiWithName
      else t := ALocale.MultiWithoutName;
    end
    else if AFacts.Series[i].HasName then t := ALocale.SingleWithName
    else t := ALocale.SingleWithoutName;
    t := TyAriaReplace(t, ['seriesId', 'seriesName', 'seriesType'],
      [IntToStr(AFacts.Series[i].Index), AFacts.Series[i].Name,
       AFacts.Series[i].TypeName]);
    cnt := Length(AFacts.Series[i].Rows);
    if cnt > AFacts.MaxData then
      t := t + TyAriaReplace(ALocale.PartialData, ['displayCnt'], [AFacts.MaxDataText])
    else
      t := t + ALocale.AllData;
    rowText := '';
    k := 0;
    for j := 0 to cnt - 1 do
    begin
      if not (j < AFacts.MaxData) then Continue;
      v := String.Join(ALocale.DataMiddle, AFacts.Series[i].Rows[j].Values);
      if k > 0 then rowText := rowText + ALocale.DataMiddle;
      if AFacts.Series[i].Rows[j].Name <> '' then
        rowText := rowText + TyAriaReplace(ALocale.DataWithName, ['name', 'value'],
          [AFacts.Series[i].Rows[j].Name, v])
      else
        rowText := rowText + TyAriaReplace(ALocale.DataWithoutName, ['name', 'value'],
          [AFacts.Series[i].Rows[j].Name, v]);
      Inc(k);
    end;
    t := t + rowText + ALocale.DataEnd;
    SetLength(labels, Length(labels) + 1);
    labels[High(labels)] := t;
  end;
  Result := s + String.Join(ALocale.SeriesMiddle, labels) + ALocale.SeriesEnd;
end;

end.
