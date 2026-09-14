unit tyControls.AdvChart.LabelOpt;
{$mode objfpc}{$H+}
{ Reading `series.label` off an option, and turning a formatter into words.

  SPLIT FROM AdvChart.Labels ON PURPOSE. That unit is the geometry and it knows
  nothing about JSON; this one is the option surface. Keeping the two apart is
  what lets the placement table be tested with hand-built specs rather than
  through a parser.

  PORTED FROM echarts/src/label/labelStyle.ts (createTextConfig) and
  echarts/src/util/format.ts (formatTpl), 6.1.0.

  THREE THINGS THE OPTION CATALOG IN THIS REPOSITORY GETS WRONG about labels,
  all found by reading the source beside it:

    - it gives `label.color` a default of '#fff' for both bar and pie. Nothing
      is '#fff' by default. An unset colour is resolved from the mark's own
      fill, and seeding white would draw white text on a light bar.
    - it applies the normal state's `position: 'inside'` and `distance: 5` to
      the emphasis, blur and select states as well. Upstream makes both
      conditional on the normal state, so a hovered label inherits whatever the
      normal one resolved instead of being pinned inside.
    - it puts a -90..90 range on `rotate`. Nothing in the source clamps it.

  PURE: SysUtils, Math, fpjson and the AdvChart units. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Data, tyControls.AdvChart.Paint,
  tyControls.AdvChart.Labels;


{ The label block of the series in slot ASlot.

  AFonts and the colours arrive resolved from the theme -- this layer never asks
  what anything looks like. ADefaultPosition is the series type's own, since
  only `line` declares one and the rest fall to `inside`. }
function TyLabelSpecOf(AOption: TTyChartOption; ASlot: Integer;
  const ABase: TTyLabelSpec): TTyLabelSpec;

{ The words for one datum.

  THE LETTER TOKENS ARE REPLACED ONCE EACH, not globally: upstream hands
  String.prototype.replace a plain string rather than a regex, so a second
  `{c}` in the same formatter is emitted literally. `{@dim}` is the other way
  round -- its pattern IS a global regex. Two rules in one function because
  upstream has two.

  An empty AFormatter answers the default text for the series type. }
function TyLabelText(const AFormatter: string; ADefault: TTyLabelDefaultText;
  AStore: TTyDataStore; ARow: Integer; const ASeriesName: string;
  AValueDim: Integer; APercent: Double; AHasPercent: Boolean): string;

{ A number the way a chart writes one: no trailing zeroes, no exponent for the
  sizes a chart deals in. Exposed because the label text and a tooltip have to
  agree about what 1/3 looks like. }
function TyLabelNumToStr(AValue: Double): string;

{ Replace the FIRST occurrence of AToken only -- JavaScript's String#replace
  takes a plain string, so a repeated token is emitted literally and every
  formatter in ECharts that is not a regular expression behaves this way.

  Exported because three callers now want it and the fourth was about to be
  written inline. }
function TyReplaceFirst(const AText, AToken, AWith: string): string;

implementation

uses tyControls.AdvChart.Handlers;

function TyLabelNumToStr(AValue: Double): string;
begin
  Result := TyChartNumToStr(AValue);
end;

function ObjOf(AData: TJSONData): TJSONObject;
begin
  if (AData <> nil) and (AData is TJSONObject) then
    Result := TJSONObject(AData)
  else
    Result := nil;
end;

function NumIn(ANode: TJSONObject; const AKey: string; ADefault: Double): Double;
var d: TJSONData;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d = nil) or (d.JSONType <> jtNumber) then Exit;
  Result := d.AsFloat;
end;

function StrIn(ANode: TJSONObject; const AKey: string): string;
var d: TJSONData;
begin
  Result := '';
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d = nil) or (d.JSONType <> jtString) then Exit;
  Result := d.AsString;
end;

{ A percentage against a base, or a plain number as px. The array form of
  `position` is two of these, against the host's own width and height. }
function PercentOf(AData: TJSONData; ABase: Double; out AValue: Double): Boolean;
var
  s: string;
  v: Double;
  fs: TFormatSettings;
begin
  AValue := 0;
  Result := False;
  if AData = nil then Exit;
  if AData.JSONType = jtNumber then
  begin
    AValue := AData.AsFloat;
    Exit(True);
  end;
  if AData.JSONType <> jtString then Exit;
  s := Trim(AData.AsString);
  if s = '' then Exit;
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if s[Length(s)] = '%' then
  begin
    if not TryStrToFloat(Copy(s, 1, Length(s) - 1), v, fs) then Exit;
    AValue := v / 100 * ABase;
    Exit(True);
  end;
  if not TryStrToFloat(s, v, fs) then Exit;
  AValue := v;
  Result := True;
end;

function TyLabelSpecOf(AOption: TTyChartOption; ASlot: Integer;
  const ABase: TTyLabelSpec): TTyLabelSpec;
var
  series, node: TJSONObject;
  d: TJSONData;
  arr: TJSONArray;
  known: Boolean;
  pos: TTyLabelPosition;
  s: string;
begin
  Result := ABase;
  if AOption = nil then Exit;
  series := ObjOf(AOption.ComponentAt('series', ASlot));
  if series = nil then Exit;
  node := ObjOf(series.Find('label'));
  if node = nil then Exit;

  d := node.Find('show');
  if (d <> nil) and (d.JSONType = jtBoolean) then Result.Show := d.AsBoolean;

  d := node.Find('position');
  if d <> nil then
  begin
    if d is TJSONArray then
    begin
      { THE ARRAY FORM IS RESOLVED LATER, against the host's own box -- which
        this layer has not seen. The percentages are kept as they were written
        and the geometry pass is handed the base. Storing px here would mean
        guessing a box. }
      arr := TJSONArray(d);
      Result.Position := tlpAt;
      Result.AtX := 0;
      Result.AtY := 0;
      if arr.Count > 0 then PercentOf(arr.Items[0], 1, Result.AtX);
      if arr.Count > 1 then PercentOf(arr.Items[1], 1, Result.AtY);
    end
    else if d.JSONType = jtString then
    begin
      s := d.AsString;
      { `outside` IS NOT A POSITION, it is a request for one. Upstream maps it
        to the series' own default outside position -- 'top' for a vertical
        bar -- because zrender has no such name. A port that passed it through
        would land every `outside` label at the host's top-left corner, which
        is where an unrecognised name goes. }
      if s = 'outside' then s := 'top';
      pos := TyLabelPositionOf(s, known);
      if known then Result.Position := pos;
      { An unknown name is left at the base position rather than adopted as
        tlpNone: tlpNone means "draw nothing", and upstream draws something. }
    end;
  end;

  Result.DistanceLogical := NumIn(node, 'distance', Result.DistanceLogical);

  d := node.Find('offset');
  if (d <> nil) and (d is TJSONArray) then
  begin
    arr := TJSONArray(d);
    if arr.Count > 0 then PercentOf(arr.Items[0], 0, Result.OffsetXLogical);
    if arr.Count > 1 then PercentOf(arr.Items[1], 0, Result.OffsetYLogical);
  end;

  { DEGREES IN THE OPTION, radians here. And NOT clamped: the catalog puts a
    -90..90 range on it and nothing in the source enforces one. }
  d := node.Find('rotate');
  if (d <> nil) and (d.JSONType = jtNumber) then
    { CLAMPED BEFORE THE MULTIPLY. `rotate` is typed `number` upstream with
      no bound, and 1e308 times Pi is not a large angle -- it is a floating
      point OVERFLOW, raised out of the paint. A turn is periodic anyway, so
      nothing outside a full circle either way says anything a value inside
      one does not. }
    Result.RotationRad :=
      Max(Double(-360), Min(Double(360), d.AsFloat)) * Pi / 180;

  s := StrIn(node, 'overflow');
  if s = 'truncate' then Result.Overflow := tloTruncate
  else if s = 'none' then Result.Overflow := tloNone;

  { A COLOUR OF `inherit` IS NOT A COLOUR, it is the mark's own fill -- so it
    is recorded as a REQUEST and the expansion pass substitutes, because this
    layer never learns what anything looks like.

    A LITERAL COLOUR IS NOT READ AT ALL YET, and that is a gap rather than a
    decision in disguise: nothing below AdvChart.Measure can parse '#ff0000',
    and a CSS colour parser is its own piece of work. An option naming one
    therefore keeps the automatic ink. }
  s := StrIn(node, 'color');
  if s = 'inherit' then
  begin
    Result.AutoColour := False;
    Result.InheritColour := True;
  end;

  Result.Formatter := StrIn(node, 'formatter');

  Result.FontSizeLogical := TyRoundOpt(NumIn(node, 'fontSize',
    Result.FontSizeLogical));
  s := StrIn(node, 'fontWeight');
  if (s = 'bold') or (s = 'bolder') then Result.FontWeight := 700
  else if s = 'normal' then Result.FontWeight := 400
  else
    Result.FontWeight := TyRoundOpt(NumIn(node, 'fontWeight', Result.FontWeight),
      Result.FontWeight);
end;

{ ==================== the formatter ==================== }

function TyReplaceFirst(const AText, AToken, AWith: string): string;
var p: Integer;
begin
  Result := AText;
  p := Pos(AToken, Result);
  if p <= 0 then Exit;
  Result := Copy(Result, 1, p - 1) + AWith
    + Copy(Result, p + Length(AToken), Length(Result));
end;

function TyLabelText(const AFormatter: string; ADefault: TTyLabelDefaultText;
  AStore: TTyDataStore; ARow: Integer; const ASeriesName: string;
  AValueDim: Integer; APercent: Double; AHasPercent: Boolean): string;
var
  nameText, valueText: string;
  i, dim, openAt: Integer;
  v: Double;
  key: string;
begin
  nameText := '';
  valueText := '';
  if AStore <> nil then
  begin
    nameText := AStore.GetName(ARow);
    if (AValueDim >= 0) and (AValueDim < AStore.DimCount) then
    begin
      v := AStore.Get(AValueDim, ARow);
      if not IsNan(v) then valueText := TyLabelNumToStr(v);
    end;
  end;

  if AFormatter = '' then
  begin
    if ADefault = tldName then Exit(nameText);
    Exit(valueText);
  end;

  Result := AFormatter;
  { a = series name, b = datum name, c = value, d = percent. The corpus uses
    exactly these four and no indexed form, which is why the indexed rewrite
    upstream does first is not reproduced -- it would be a table nothing
    reads. }
  Result := TyReplaceFirst(Result, '{a}', ASeriesName);
  Result := TyReplaceFirst(Result, '{b}', nameText);
  Result := TyReplaceFirst(Result, '{c}', valueText);
  if AHasPercent then
    Result := TyReplaceFirst(Result, '{d}', TyLabelNumToStr(APercent));

  { `{@dim}` IS GLOBAL, because upstream's pattern for it is a regex with the
    g flag while the letters above are plain strings. Two rules, and they are
    upstream's two rules rather than an inconsistency introduced here. }
  if AStore = nil then Exit;
  i := 1;
  while i <= Length(Result) - 2 do
  begin
    if (Result[i] = '{') and (Result[i + 1] = '@') then
    begin
      openAt := i;
      i := i + 2;
      key := '';
      while (i <= Length(Result)) and (Result[i] <> '}') do
      begin
        key := key + Result[i];
        Inc(i);
      end;
      if (i <= Length(Result)) and (key <> '') then
      begin
        dim := AStore.DimIndexOf(key);
        valueText := '';
        if dim >= 0 then
        begin
          v := AStore.Get(dim, ARow);
          if not IsNan(v) then valueText := TyLabelNumToStr(v);
        end;
        Result := Copy(Result, 1, openAt - 1) + valueText
          + Copy(Result, i + 1, Length(Result));
        i := openAt + Length(valueText);
        Continue;
      end;
      i := openAt + 1;
      Continue;
    end;
    Inc(i);
  end;
end;

end.
