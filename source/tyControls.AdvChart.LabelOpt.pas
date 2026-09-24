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
  tyControls.AdvChart.Labels, tyControls.AdvChart.Color;


{ The label block of the series in slot ASlot.

  AFonts and the colours arrive resolved from the theme -- this layer never asks
  what anything looks like. ADefaultPosition is the series type's own, since
  only `line` declares one and the rest fall to `inside`. }
function TyLabelSpecOf(AOption: TTyChartOption; ASlot: Integer;
  const ABase: TTyLabelSpec): TTyLabelSpec;

{ THE INK HALF OF A LABEL BLOCK, shared by every series that reads one:
  `color` (a literal or `inherit`), `textBorderColor`, `textBorderWidth`,
  whether a `backgroundColor` was written, and the `emphasis.label` overrides
  -- ASeries is the series node, whose `emphasis.label` is read. }
procedure TyLabelReadInk(ALabel, ASeries: TJSONObject; var ASpec: TTyLabelSpec);

{ The words for one datum: upstream's getFormattedLabel.

  THE LETTER TOKENS go through formatTpl -- the first bare `{a}` becomes
  `{a0}`, then the first `{a0}` is replaced, and a second `{c}` is emitted as
  written; `{d}` is a letter only where the series has a percentage (a pie, a
  funnel). `{@dim}` is the other way round -- its pattern IS a global regex.
  Two rules in one function because upstream has two.

  No formatter (AHasFormatter False) answers the default text for the series
  type; an empty one is an empty label. }
function TyLabelText(const AFormatter: string; AHasFormatter: Boolean;
  ADefault: TTyLabelDefaultText; AStore: TTyDataStore; ARow: Integer;
  const ASeriesName: string; AValueDim: Integer; APercent: Double;
  AHasPercent: Boolean): string;

{ A value the way a label prints a raw one: JavaScript's String(), exact and
  never grouped -- 0.30000000000000004, 1e-7, 1e+21. A missing value is ''. }
function TyLabelNumToStr(AValue: Double): string;

{ Replace the FIRST occurrence of AToken only -- JavaScript's String#replace
  takes a plain string, so a repeated token is emitted literally and every
  formatter in ECharts that is not a regular expression behaves this way.

  Exported because three callers now want it and the fourth was about to be
  written inline. }
function TyReplaceFirst(const AText, AToken, AWith: string): string;

implementation

uses tyControls.AdvChart.Handlers, tyControls.AdvChart.Scale;

function TyLabelNumToStr(AValue: Double): string;
begin
  Result := TyChartValueText(AValue);
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
      if known then
      begin
        Result.Position := pos;
        { remembered, so a bar can say which side its outside is }
        Result.Outside := d.AsString = 'outside';
      end;
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
    layer never learns what anything looks like. A literal one is read.
    [Revised in batch 47: a literal colour was not read at all.] }
  TyLabelReadInk(node, series, Result);

  { A STRING is a template, the empty one included; null is none, and falls
    back to the default text; anything else is not one this can use. }
  d := node.Find('formatter');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    Result.Formatter := d.AsString;
    Result.HasFormatter := True;
  end
  else if (d <> nil) and (d.JSONType = jtNull) then
  begin
    Result.Formatter := '';
    Result.HasFormatter := False;
  end;

  Result.FontSizeLogical := TyRoundOpt(NumIn(node, 'fontSize',
    Result.FontSizeLogical));
  s := StrIn(node, 'fontWeight');
  if (s = 'bold') or (s = 'bolder') then Result.FontWeight := 700
  else if s = 'normal' then Result.FontWeight := 400
  else
    Result.FontWeight := TyRoundOpt(NumIn(node, 'fontWeight', Result.FontWeight),
      Result.FontWeight);
end;

procedure TyLabelReadInk(ALabel, ASeries: TJSONObject; var ASpec: TTyLabelSpec);
var
  s: string;
  c: TTyChartColor;
  d: TJSONData;
  emph: TJSONObject;
begin
  if ALabel <> nil then
  begin
    s := StrIn(ALabel, 'color');
    if s = 'inherit' then
    begin
      ASpec.AutoColour := False;
      ASpec.InheritColour := True;
    end
    else if (s <> '') and (s <> 'auto') and TyTryParseChartColor(s, c) then
    begin
      ASpec.AutoColour := False;
      ASpec.InheritColour := False;
      ASpec.Colour := c;
    end;

    s := StrIn(ALabel, 'textBorderColor');
    if s <> '' then
    begin
      ASpec.HasBorderColour := True;
      if (s = 'none') or (s = 'transparent') then ASpec.BorderColourNone := True
      else if s = 'inherit' then ASpec.BorderColourInherit := True
      else if TyTryParseChartColor(s, c) then ASpec.BorderColour := c
      else ASpec.BorderColourNone := True;
    end;
    d := ALabel.Find('textBorderWidth');
    if (d <> nil) and (d.JSONType = jtNumber) then
    begin
      ASpec.HasBorderWidth := True;
      ASpec.BorderWidthLogical := d.AsFloat;
      if IsNan(ASpec.BorderWidthLogical) or IsInfinite(ASpec.BorderWidthLogical)
        or (ASpec.BorderWidthLogical < 0) then ASpec.BorderWidthLogical := 0;
    end;
    d := ALabel.Find('backgroundColor');
    ASpec.HasBackground := (d <> nil) and (d.JSONType = jtString)
      and (d.AsString <> '') and (d.AsString <> 'none')
      and (d.AsString <> 'transparent');
  end;

  { `emphasis.label` on the series, and the host's emphasis colour. }
  if ASeries = nil then Exit;
  emph := ObjOf(ASeries.Find('emphasis'));
  if emph = nil then Exit;
  d := ObjOf(emph.Find('itemStyle'));
  if d <> nil then
  begin
    s := StrIn(TJSONObject(d), 'color');
    if (s <> '') and (s <> 'inherit') and (s <> 'auto')
      and TyTryParseChartColor(s, c) then
    begin
      ASpec.EmphHostHasColour := True;
      ASpec.EmphHostColour := c;
    end;
  end;
  emph := ObjOf(emph.Find('label'));
  if emph = nil then Exit;
  s := StrIn(emph, 'color');
  if (s <> '') and (s <> 'inherit') and (s <> 'auto')
    and TyTryParseChartColor(s, c) then
  begin
    ASpec.EmphHasColour := True;
    ASpec.EmphColour := c;
  end;
  d := emph.Find('textBorderWidth');
  if (d <> nil) and (d.JSONType = jtNumber) and (d.AsFloat >= 0) then
  begin
    ASpec.EmphHasBorderWidth := True;
    ASpec.EmphBorderWidthLogical := d.AsFloat;
  end;
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

function TyLabelText(const AFormatter: string; AHasFormatter: Boolean;
  ADefault: TTyLabelDefaultText; AStore: TTyDataStore; ARow: Integer;
  const ASeriesName: string; AValueDim: Integer; APercent: Double;
  AHasPercent: Boolean): string;
var
  nameText, valueText: string;
  i, dim, openAt, n: Integer;
  v: Double;
  key: string;
  vars: array of TTyStringArray;
  it: TTyRawItem;
  hasRaw: Boolean;
  cell: TTyDataValue;
begin
  nameText := '';
  valueText := '';
  it := Default(TTyRawItem);
  if AStore <> nil then it := AStore.RawItem(ARow);
  { THE ITEM AS WRITTEN, when the store kept it: every text below prints
    that and not the parsed number -- '12.50' stays '12.50', true stays
    true. A store with no raw side answers rshNone and the Double speaks. }
  hasRaw := it.Shape <> rshNone;
  if AStore <> nil then
  begin
    { THE b PLACEHOLDER IS getName, which falls back to the category when the item has no
      name of its own -- a bare number on a category axis is labelled with
      its category, not with nothing. }
    nameText := AStore.GetItemName(ARow);
    if (AValueDim >= 0) and (AValueDim < AStore.DimCount) then
    begin
      if hasRaw then
      begin
        { getDefaultLabel: the cell at the label dimension's position, a
          scalar for any position, nothing for a gap. }
        if TTyDataStore.RawCell(it, AStore.RawDimPos(AValueDim), cell) then
          valueText := TyJsValueText(cell, '');
      end
      else
      begin
        v := AStore.Get(AValueDim, ARow);
        if not IsNan(v) then valueText := TyLabelNumToStr(v);
      end;
    end;
  end;

  if not AHasFormatter then
  begin
    if ADefault = tldName then Exit(nameText);
    Exit(valueText);
  end;

  { formatTpl over the one series: a = series name, b = datum name,
    c = value, and d = percent where there is one. The indexed forms work
    too -- `{a0}|{b0}|{c0}` is upstream's own spelling of the same three --
    and a '$' in a name is read as String.replace reads it. }
  if AHasPercent then n := 4 else n := 3;
  vars := nil;
  SetLength(vars, 1);
  SetLength(vars[0], n);
  vars[0][0] := ASeriesName;
  vars[0][1] := nameText;
  { `{c}` IS THE WHOLE RAW VALUE, String()-ed: an array joined by commas,
    `null`, `undefined`, `[object Object]` -- not the label dimension. }
  if hasRaw then vars[0][2] := TyRawItemText(it)
  else vars[0][2] := valueText;
  { the percentage as String() prints it -- 'NaN' included, which is what a
    funnel's missing value shows }
  if n = 4 then vars[0][3] := TyJsNumberToString(APercent);
  Result := TyJsFormatTpl(AFormatter, n, vars);

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
        valueText := '';
        if hasRaw then
        begin
          { getDimensionIndex against upstream's names -- `[n]`, a declared
            name, a numeric-looking key -- and the raw cell there. }
          if TTyDataStore.RawCell(it, AStore.RawPosOf(key), cell) then
            valueText := TyJsValueText(cell, '');
        end
        else
        begin
          dim := AStore.DimIndexOf(key);
          if dim >= 0 then
          begin
            v := AStore.Get(dim, ARow);
            if not IsNan(v) then valueText := TyLabelNumToStr(v);
          end;
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
