unit tyControls.AdvChart.Handlers;
{$mode objfpc}{$H+}
{ Named handlers and template strings -- what a function-valued ECharts option
  becomes when the host cannot run JavaScript.

  THE PROBLEM. Roughly 1,212 nodes in the option schema accept a function, and
  `formatter` alone is 539 of them. A closure cannot live in serialised option
  text, so an option tree needs another answer, and there are three:

    a TEMPLATE STRING   formatter: '{b}: {c} ({d}%)'
        ECharts' own syntax, and it alone covers the great majority of the 539
        formatters. Nothing has to be registered and nothing has to be compiled.

    a NAMED HANDLER     formatter: '@SalesFormatter'
        Resolved through the registry below to a Pascal method. Streamable,
        visible at design time, and the same shape ECharts 6 chose for
        registerCustomSeries -- a NAME plus a payload rather than an inline
        closure.

    a real EVENT        for the handful of cases that belong on the control
        rather than in the option text.

  A literal `function(...)` pasted from a JS example is REJECTED by the option
  reader with a message naming these two, rather than silently ignored: a
  formatter that quietly does nothing is a chart that quietly lies.

  THE PARAMETER RECORD IS v6.1's, NOT v5's. ECharts 6.1 changed
  tooltip.valueFormatter's second parameter from the dataZoom-FILTERED index to
  the index into the original input data (changelog v6.1.0: "changed from
  dataIndex ... to rawDataIndex"). Both are carried here from day one. Adopting
  it now costs nothing; migrating it once handlers exist in user code is the
  most expensive kind of change to absorb.

  LCL-free: SysUtils, Classes, Math and the AdvChart units. }
interface
uses
  SysUtils, Classes, Math,
  tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
  tyControls.AdvChart.Data;

type
  { What a handler is given, and what a template expands from. Modelled on
    ECharts' formatter params (en/option/partial/formatter.md). }
  TTyChartCallbackParams = record
    ComponentType: string;      // 'series' for everything a series draws
    SeriesType: string;         // 'bar', 'line', ...
    { '' for every datum but a graph's, where it is 'node' or 'edge' --
      upstream's params.dataType, which is how a formatter tells a link from
      the node that shares its row number. }
    DataType: string;
    SeriesIndex: Integer;
    SeriesName: string;         // the a placeholder
    Name: string;               // data or category name -- the b placeholder
    { The index into the data currently being SHOWN, after dataZoom filtering. }
    DataIndex: Integer;
    { The index into the ORIGINAL input data. See the unit header: v6.1 made
      this the one a value formatter receives, and carrying both means a handler
      can ask for whichever it actually means. }
    RawDataIndex: Integer;
    { The datum's dimensions. One entry for a plain value; more for a scatter,
      a candlestick or a dataset row. }
    Values: TTyDoubleArray;
    { Parallel to Values when the data came from a dataset, so a template can
      say @price instead of counting columns. Empty otherwise. }
    DimensionNames: TTyStringArray;
    { THE ITEM AS WRITTEN, when the store kept it (rshNone otherwise): the
      template's c prints this, not Values. RawCells and RawTypes run parallel
      to Values -- each value's own cell and its dimension's type -- for the
      tooltip's value cell. Empty when there is no raw item. }
    Raw: TTyRawItem;
    RawCells: TTyDataValueArray;
    RawTypes: array of TTyDimType;
    { The d placeholder. HasPercent separates "zero per cent" from "this series
      has no percentage", which is most of them. }
    Percent: Double;
    HasPercent: Boolean;
    Color: TTyChartColor;
    { The e placeholder. ECharts documents it as existing but never says what it
      is per series type, so it is a slot the caller fills rather than something
      invented here. }
    Extra: string;
    { 'normal' for a label drawn in its resting state -- upstream's
      params.status. }
    Status: string;
    { An axis-pointer label's axis: 'x', 'y', 'radius', 'angle', 'single' and
      the axis's index among its kind. }
    AxisDimension: string;
    AxisIndex: Integer;
    { A time axis label's level (upstream's extra.level); HasLevel False is
      the null every other axis passes. }
    Level: Integer;
    HasLevel: Boolean;
    { THE VALUE AS JavaScript's String() PRINTS IT -- an array joined by
      commas, 'undefined', 'null' -- which is what `{c}` and every upstream
      function formatter that concatenates params.value would show. }
    ValueText: string;
    { What the chart would have printed had there been no formatter -- the
      axis label's own text, a dataZoom label's valueStr. '' where upstream
      has no such thing. }
    DefaultText: string;
  end;
  TTyChartParams = array of TTyChartCallbackParams;

  { A named formatter. `of object` rather than a plain procedure or a reference:
    method pointers are streamable and visible at design time, which is what a
    registry addressed by name from serialised text needs. }
  TTyChartFormatter = function(const AParams: TTyChartParams): string of object;

{ ---- the registry ---- }
{ Registering the same name twice REPLACES, so a form reopened at design time
  does not accumulate stale handlers. }
procedure TyChartRegisterFormatter(const AName: string; AHandler: TTyChartFormatter);
procedure TyChartUnregisterFormatter(const AName: string);
function TyChartFindFormatter(const AName: string; out AHandler: TTyChartFormatter): Boolean;
{ The registered names, for a design-time editor to offer. }
procedure TyChartFormatterNames(AList: TStrings);
procedure TyChartClearFormatters;

{ ---- template strings ---- }
{ String.prototype.replace(pattern, replacement) with a STRING pattern: the
  first occurrence only, and the replacement read the way JavaScript reads
  it -- '$$' is a dollar, '$&' the matched text, '$`' what came before it and
  "$'" what comes after. There are no groups, so '$1' stays as written. }
function TyJsReplaceFirst(const ASubject, APattern, AReplacement: string): string;

{ upstream's formatTpl. AVars[s] holds series s's texts in the order of the
  template letters a, b, c (and d when AVarCount is 4). First every bare
  letter token -- its first occurrence -- becomes the series-0 form, `{a}` to
  `{a0}`; then, for each series in turn, the first `{a0}`, `{b0}` ... of that
  series is replaced. Everything else stays as written: a second `{c}`, an
  `{e}`, an index past the series count, a `{d}` where there is no
  percentage. }
function TyJsFormatTpl(const ATemplate: string; AVarCount: Integer;
  const AVars: array of TTyStringArray): string;

{ A tooltip formatter template: formatTpl over one entry per series. The
  letters are a (series name), b (name), c (the value -- several joined with
  ',' as JavaScript prints an array) and, for a series that has one, d (the
  percentage). @dimension forms are NOT expanded here; upstream only expands
  them in labels. }
function TyChartFormatTemplate(const ATemplate: string;
  const AParams: TTyChartParams): string;

{ ---- resolving an option value ---- }
{ ASpec is whatever the option tree holds: '@Name' for a registered handler,
  anything else as a template. Returns False only when a named handler was asked
  for and is not registered -- in which case AText carries a message saying so,
  because a formatter that silently does nothing is worse than a visible error. }
function TyChartResolveText(const ASpec: string; const AParams: TTyChartParams;
  out AText: string): Boolean;

{ True when ASpec names a handler rather than being a template. }
function TyChartIsHandlerRef(const ASpec: string): Boolean;

{ Runs the handler ASpec names ('@Name') on AParams -- for every formatter site
  whose template language is not the tooltip's. A name nobody registered
  answers the message saying so, never an empty text. }
function TyChartRunHandler(const ASpec: string;
  const AParams: TTyChartParams): string;

{ One params record, the shape a formatter of a single datum is given. }
function TyChartOneParams(const AParams: TTyChartCallbackParams): TTyChartParams;

{ A record with every index at -1 and nothing else set -- the start of every
  params a site builds. }
function TyChartBlankParams: TTyChartCallbackParams;

{ A number as a template or a label prints a raw value: JavaScript's String(),
  exact -- 0.30000000000000004, 1e-7, 1e+21 -- and never grouped. A missing
  value (not-a-number) is ''. }
function TyChartValueText(AValue: Double): string;

{ The OLD rounding format, six decimals and no exponent below 1e17. Only the
  radar's ring labels still use it: their values are not rounded the way
  upstream rounds an axis', and full precision would print the noise. }
function TyChartNumToStr(AValue: Double): string;

implementation

uses
  tyControls.AdvChart.Scale,
  { Only for the diagnostic resourcestrings; kept out of the interface uses so
    the dependency stays one-way and invisible to hosts. }
  tyControls.StrConsts;

type
  TFormatterEntry = record
    Name: string;
    Handler: TTyChartFormatter;
  end;

var
  GFormatters: array of TFormatterEntry;

function IndexOfFormatter(const AName: string): Integer;
var i: Integer;
begin
  for i := 0 to High(GFormatters) do
    if SameText(GFormatters[i].Name, AName) then
      Exit(i);
  Result := -1;
end;

procedure TyChartRegisterFormatter(const AName: string; AHandler: TTyChartFormatter);
var i: Integer;
begin
  if AName = '' then Exit;
  i := IndexOfFormatter(AName);
  if i < 0 then
  begin
    i := Length(GFormatters);
    SetLength(GFormatters, i + 1);
    GFormatters[i].Name := AName;
  end;
  GFormatters[i].Handler := AHandler;
end;

procedure TyChartUnregisterFormatter(const AName: string);
var i, j: Integer;
begin
  i := IndexOfFormatter(AName);
  if i < 0 then Exit;
  for j := i to High(GFormatters) - 1 do
    GFormatters[j] := GFormatters[j + 1];
  SetLength(GFormatters, Length(GFormatters) - 1);
end;

function TyChartFindFormatter(const AName: string; out AHandler: TTyChartFormatter): Boolean;
var i: Integer;
begin
  AHandler := nil;
  i := IndexOfFormatter(AName);
  Result := i >= 0;
  if Result then
    AHandler := GFormatters[i].Handler;
end;

procedure TyChartFormatterNames(AList: TStrings);
var i: Integer;
begin
  if AList = nil then Exit;
  AList.Clear;
  for i := 0 to High(GFormatters) do
    AList.Add(GFormatters[i].Name);
end;

procedure TyChartClearFormatters;
begin
  GFormatters := nil;
end;

function TyChartNumToStr(AValue: Double): string;
var
  fs: TFormatSettings;
begin
  if IsNan(AValue) then Exit('');
  if IsInfinite(AValue) then Exit('');
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  fs.ThousandSeparator := #0;
  Result := FormatFloat('0.######', AValue, fs);
end;

function TyChartValueText(AValue: Double): string;
begin
  if IsNan(AValue) then Exit('');
  Result := TyJsNumberToString(AValue);
end;

function TyJsReplaceFirst(const ASubject, APattern, AReplacement: string): string;
var
  p, i: Integer;
  repl: string;
begin
  Result := ASubject;
  p := Pos(APattern, ASubject);
  if (APattern = '') or (p <= 0) then Exit;
  repl := '';
  i := 1;
  while i <= Length(AReplacement) do
  begin
    if (AReplacement[i] = '$') and (i < Length(AReplacement)) then
      case AReplacement[i + 1] of
        '$':
          begin
            repl := repl + '$';
            Inc(i, 2);
            Continue;
          end;
        '&':
          begin
            repl := repl + APattern;
            Inc(i, 2);
            Continue;
          end;
        '`':
          begin
            repl := repl + Copy(ASubject, 1, p - 1);
            Inc(i, 2);
            Continue;
          end;
        '''':
          begin
            repl := repl + Copy(ASubject, p + Length(APattern), MaxInt);
            Inc(i, 2);
            Continue;
          end;
      end;
    repl := repl + AReplacement[i];
    Inc(i);
  end;
  Result := Copy(ASubject, 1, p - 1) + repl
    + Copy(ASubject, p + Length(APattern), MaxInt);
end;

function TyJsFormatTpl(const ATemplate: string; AVarCount: Integer;
  const AVars: array of TTyStringArray): string;
const
  cAlias: array[0..6] of Char = ('a', 'b', 'c', 'd', 'e', 'f', 'g');
var
  s, k: Integer;
begin
  Result := ATemplate;
  { no series, no text -- formatTpl's own first answer }
  if Length(AVars) = 0 then Exit('');
  if AVarCount > Length(cAlias) then AVarCount := Length(cAlias);
  for k := 0 to AVarCount - 1 do
    Result := TyJsReplaceFirst(Result, '{' + cAlias[k] + '}',
      '{' + cAlias[k] + '0}');
  for s := 0 to High(AVars) do
    for k := 0 to AVarCount - 1 do
      if k <= High(AVars[s]) then
        Result := TyJsReplaceFirst(Result,
          '{' + cAlias[k] + IntToStr(s) + '}', AVars[s][k]);
end;

function TyChartIsHandlerRef(const ASpec: string): Boolean;
begin
  Result := (Length(ASpec) > 1) and (ASpec[1] = '@') and (ASpec[2] <> '[');
end;

{ The c text: the value as JavaScript prints it, several joined with ',' as
  an array prints -- a missing one as nothing, as join leaves a null. }
function ValueTextOf(const P: TTyChartCallbackParams): string;
var i: Integer;
begin
  { THE RAW VALUE, String()-ed -- except a null or a missing one, which the
    tooltip's formatTpl prints as nothing rather than `null`. }
  if P.Raw.Shape <> rshNone then
  begin
    if P.Raw.Shape in [rshNull, rshAbsent] then Exit('');
    Exit(TyRawItemText(P.Raw));
  end;
  Result := '';
  for i := 0 to High(P.Values) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + TyChartValueText(P.Values[i]);
  end;
end;

function TyChartFormatTemplate(const ATemplate: string;
  const AParams: TTyChartParams): string;
var
  vars: array of TTyStringArray;
  i, n: Integer;
begin
  vars := nil;
  SetLength(vars, Length(AParams));
  { d is one of the letters only where the series HAS a percentage -- a pie,
    a funnel -- and the first series decides, as upstream's $vars come from
    the first entry. }
  if (Length(AParams) > 0) and AParams[0].HasPercent then n := 4 else n := 3;
  for i := 0 to High(AParams) do
  begin
    SetLength(vars[i], n);
    vars[i][0] := AParams[i].SeriesName;
    vars[i][1] := AParams[i].Name;
    vars[i][2] := ValueTextOf(AParams[i]);
    if n = 4 then
    begin
      if AParams[i].HasPercent then
        vars[i][3] := TyJsNumberToString(AParams[i].Percent)
      else
        vars[i][3] := '';
    end;
  end;
  Result := TyJsFormatTpl(ATemplate, n, vars);
end;

function TyChartResolveText(const ASpec: string; const AParams: TTyChartParams;
  out AText: string): Boolean;
var
  h: TTyChartFormatter;
  name: string;
begin
  AText := '';
  if not TyChartIsHandlerRef(ASpec) then
  begin
    AText := TyChartFormatTemplate(ASpec, AParams);
    Exit(True);
  end;
  name := Copy(ASpec, 2, MaxInt);
  if not TyChartFindFormatter(name, h) then
  begin
    AText := Format(rsTyChartNoSuchHandler, [name]);
    Exit(False);
  end;
  if h = nil then
  begin
    AText := Format(rsTyChartNoSuchHandler, [name]);
    Exit(False);
  end;
  AText := h(AParams);
  Result := True;
end;

function TyChartRunHandler(const ASpec: string;
  const AParams: TTyChartParams): string;
begin
  TyChartResolveText(ASpec, AParams, Result);
end;

function TyChartOneParams(const AParams: TTyChartCallbackParams): TTyChartParams;
begin
  Result := nil;
  SetLength(Result, 1);
  Result[0] := AParams;
end;

function TyChartBlankParams: TTyChartCallbackParams;
begin
  Result := Default(TTyChartCallbackParams);
  Result.SeriesIndex := -1;
  Result.DataIndex := -1;
  Result.RawDataIndex := -1;
  Result.AxisIndex := -1;
end;

finalization
  TyChartClearFormatters;

end.
