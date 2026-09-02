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
  tyControls.AdvChart.Types, tyControls.AdvChart.Paint;

type
  { What a handler is given, and what a template expands from. Modelled on
    ECharts' formatter params (en/option/partial/formatter.md). }
  TTyChartCallbackParams = record
    ComponentType: string;      // 'series' for everything a series draws
    SeriesType: string;         // 'bar', 'line', ...
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
    { The d placeholder. HasPercent separates "zero per cent" from "this series
      has no percentage", which is most of them. }
    Percent: Double;
    HasPercent: Boolean;
    Color: TTyChartColor;
    { The e placeholder. ECharts documents it as existing but never says what it
      is per series type, so it is a slot the caller fills rather than something
      invented here. }
    Extra: string;
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
{ Expand ECharts' template syntax:

    a  series name        b  data or category name     c  data value
    d  percentage         e  a series-specific extra

  each optionally suffixed with a series index -- a0, b1 -- which is how an
  axis-triggered tooltip names one of several series at the same category.
  Without a suffix the first entry is used.

  Also the dataset forms: @name is the value of the dimension called `name`,
  and @[n] the value of the dimension at index n.

  A placeholder that is none of these is left VERBATIM. Deleting it would make a
  typo invisible, and a user's own literal text is more likely than a silent
  mistake being what they wanted. }
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

{ How a number reaches a template. Locale-INDEPENDENT on purpose: '.' always,
  matching ECharts, so the same option text produces the same chart whatever the
  machine's regional settings say. Trailing zeros are dropped. }
function TyChartNumToStr(AValue: Double): string;

resourcestring
  rsTyChartNoSuchHandler = 'No formatter named ''%s'' is registered.';

implementation

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

function TyChartIsHandlerRef(const ASpec: string): Boolean;
begin
  Result := (Length(ASpec) > 1) and (ASpec[1] = '@') and (ASpec[2] <> '[');
end;

{ The value a c placeholder shows: one dimension formatted, or all of them
  joined when the datum carries several (a scatter's x and y, a candlestick's
  four). }
function ValueTextOf(const P: TTyChartCallbackParams): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to High(P.Values) do
  begin
    if i > 0 then Result := Result + ', ';
    Result := Result + TyChartNumToStr(P.Values[i]);
  end;
end;

function DimensionValue(const P: TTyChartCallbackParams; const AName: string;
  out AText: string): Boolean;
var
  i, idx: Integer;
begin
  AText := '';
  Result := False;
  if (Length(AName) > 2) and (AName[1] = '[') and (AName[Length(AName)] = ']') then
  begin
    idx := StrToIntDef(Copy(AName, 2, Length(AName) - 2), -1);
    if (idx < 0) or (idx > High(P.Values)) then Exit;
    AText := TyChartNumToStr(P.Values[idx]);
    Exit(True);
  end;
  for i := 0 to High(P.DimensionNames) do
    if SameText(P.DimensionNames[i], AName) then
    begin
      if i > High(P.Values) then Exit;
      AText := TyChartNumToStr(P.Values[i]);
      Exit(True);
    end;
end;

{ Resolve one placeholder body, without its braces. Returns False when it is not
  a placeholder this understands, so the caller can leave it verbatim. }
function ExpandOne(const ABody: string; const AParams: TTyChartParams;
  out AText: string): Boolean;
var
  letter: Char;
  idxText: string;
  which, i: Integer;
begin
  AText := '';
  Result := False;
  if ABody = '' then Exit;

  if ABody[1] = '@' then
    Exit(DimensionValue(AParams[0], Copy(ABody, 2, MaxInt), AText));

  letter := ABody[1];
  if not (letter in ['a', 'b', 'c', 'd', 'e']) then Exit;
  idxText := Copy(ABody, 2, MaxInt);
  which := 0;
  if idxText <> '' then
  begin
    for i := 1 to Length(idxText) do
      if not (idxText[i] in ['0'..'9']) then Exit;
    which := StrToIntDef(idxText, -1);
    if which < 0 then Exit;
  end;
  { An index past the end is not an error in the template -- it is an axis
    tooltip whose series list is shorter than the author expected. Expanding to
    nothing keeps the rest of the line readable. }
  if which > High(AParams) then
  begin
    AText := '';
    Exit(True);
  end;

  case letter of
    'a': AText := AParams[which].SeriesName;
    'b': AText := AParams[which].Name;
    'c': AText := ValueTextOf(AParams[which]);
    'd': if AParams[which].HasPercent then
           AText := TyChartNumToStr(AParams[which].Percent);
    'e': AText := AParams[which].Extra;
  end;
  Result := True;
end;

function TyChartFormatTemplate(const ATemplate: string;
  const AParams: TTyChartParams): string;
var
  i, n, close_: Integer;
  body, expanded: string;
begin
  Result := '';
  n := Length(ATemplate);
  if Length(AParams) = 0 then
    Exit(ATemplate);
  i := 1;
  while i <= n do
  begin
    if ATemplate[i] <> '{' then
    begin
      Result := Result + ATemplate[i];
      Inc(i);
      Continue;
    end;
    close_ := i + 1;
    while (close_ <= n) and (ATemplate[close_] <> '}') do Inc(close_);
    if close_ > n then
    begin
      { An unclosed brace is literal text, not a broken placeholder. }
      Result := Result + Copy(ATemplate, i, MaxInt);
      Break;
    end;
    body := Copy(ATemplate, i + 1, close_ - i - 1);
    if ExpandOne(body, AParams, expanded) then
      Result := Result + expanded
    else
      Result := Result + Copy(ATemplate, i, close_ - i + 1);
    i := close_ + 1;
  end;
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

finalization
  TyChartClearFormatters;

end.
