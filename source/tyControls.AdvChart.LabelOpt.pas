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
  tyControls.AdvChart.Labels, tyControls.AdvChart.Color,
  tyControls.AdvChart.Handlers;


{ The label block of the series in slot ASlot.

  AFonts and the colours arrive resolved from the theme -- this layer never asks
  what anything looks like. ADefaultPosition is the series type's own, since
  only `line` declares one and the rest fall to `inside`. }
function TyLabelSpecOf(AOption: TTyChartOption; ASlot: Integer;
  const ABase: TTyLabelSpec): TTyLabelSpec;
{ The same reading of ONE label object over ABase -- a data item's own
  `label` over its series' spec. ASeries is the series node (for its
  emphasis). [Batch 68] }
function TyLabelSpecOfNode(ANode, ASeries: TJSONObject;
  const ABase: TTyLabelSpec): TTyLabelSpec;

{ THE INK HALF OF A LABEL BLOCK, shared by every series that reads one:
  `color` (a literal or `inherit`), `textBorderColor`, `textBorderWidth`,
  whether a `backgroundColor` was written, and the `emphasis.label` overrides
  -- ASeries is the series node, whose `emphasis.label` is read. }
procedure TyLabelReadInk(ALabel, ASeries: TJSONObject; var ASpec: TTyLabelSpec);

{ THE TEXT BLOCK OF A LABEL A SERIES PLACES ITSELF (a pie's, a funnel's):
  ALabel's styles into ASpec.Rt, with the root option's side. [Batch 86] }
procedure TyLabelReadBlock(ALabel: TJSONObject; ARoot: TJSONData;
  var ASpec: TTyLabelSpec);

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
  AHasPercent: Boolean; ASeriesIndex: Integer = -1;
  const ASeriesType: string = ''; AColor: TTyChartColor = 0;
  const ADataType: string = ''; AHasValueText: Boolean = False;
  const AValueText: string = ''): string;

{ THE WORDS FOR AN INTERPOLATED VALUE, with #1 where the value goes: what
  labelStyle's getLabelText answers once animateLabelValue has set
  params.value -- with no formatter the value itself
  (getDefaultInterpolatedLabel: `value + ''`), with a template the template
  with its c placeholder standing for the value and the rest as TyLabelText fills it. A
  named handler answers '' (no template: the label does not count).
  [Batch 92] }
function TyLabelValueTemplate(const AFormatter: string; AHasFormatter: Boolean;
  ADefault: TTyLabelDefaultText; AStore: TTyDataStore; ARow: Integer;
  const ASeriesName: string; AValueDim: Integer; ASeriesIndex: Integer = -1;
  const ASeriesType: string = ''; AColor: TTyChartColor = 0): string;

{ What a named label handler ('@Name') is given for row ARow: upstream's
  getDataParams -- the series, the item's name, its value as written, both
  indices (upstream's own params.dataIndex is the RAW one), the percentage
  where the series has one, and status 'normal'. }
function TyLabelParams(AStore: TTyDataStore; ARow: Integer;
  const ASeriesName: string; AValueDim: Integer; APercent: Double;
  AHasPercent: Boolean; ASeriesIndex: Integer; const ASeriesType: string;
  AColor: TTyChartColor; const ADataType: string): TTyChartCallbackParams;

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

uses jsonparser, tyControls.AdvChart.Scale, tyControls.AdvChart.RichStyle;

{ THE LABEL'S TEXT BLOCK, resolved over every label node the spec was read
  from -- ANode first, then its base's -- when any of them asks for one: a
  data item's `rich` cascades over its series' as upstream's model chain
  does. The base's nodes are held as text and parsed back here. [Batch 86] }
procedure ResolveBlock(ANode: TJSONObject; var ASpec: TTyLabelSpec);
var
  chain: array of TJSONObject;
  parsed: array of TJSONData;
  prior: TTyStringArray;
  i: Integer;
begin
  prior := ASpec.RtChain;
  SetLength(ASpec.RtChain, Length(prior) + 1);
  ASpec.RtChain[0] := ANode.AsJSON;
  for i := 0 to High(prior) do ASpec.RtChain[i + 1] := prior[i];
  ASpec.RtAny := ASpec.RtAny or TyRtNodeWantsBlock(ANode);
  if not ASpec.RtAny then Exit;
  SetLength(chain, Length(prior) + 1);
  SetLength(parsed, Length(prior));
  chain[0] := ANode;
  try
    for i := 0 to High(prior) do
    begin
      parsed[i] := nil;
      try
        parsed[i] := GetJSON(prior[i]);
      except
        parsed[i] := nil;
      end;
      if parsed[i] is TJSONObject then chain[i + 1] := TJSONObject(parsed[i])
      else chain[i + 1] := nil;
    end;
    ASpec.Rt := TyRtResolve(chain, ASpec.RtGlobal, TyRtResolveOpt(True));
  finally
    for i := 0 to High(parsed) do parsed[i].Free;
  end;
end;

function TyLabelParams(AStore: TTyDataStore; ARow: Integer;
  const ASeriesName: string; AValueDim: Integer; APercent: Double;
  AHasPercent: Boolean; ASeriesIndex: Integer; const ASeriesType: string;
  AColor: TTyChartColor; const ADataType: string): TTyChartCallbackParams;
var v: Double;
begin
  Result := TyChartBlankParams;
  Result.ComponentType := 'series';
  Result.SeriesType := ASeriesType;
  Result.SeriesIndex := ASeriesIndex;
  Result.SeriesName := ASeriesName;
  Result.DataType := ADataType;
  Result.Color := AColor;
  Result.Status := 'normal';
  Result.DataIndex := ARow;
  Result.HasPercent := AHasPercent;
  if AHasPercent then Result.Percent := APercent;
  if AStore = nil then Exit;
  if (ARow < 0) or (ARow >= AStore.Count) then Exit;
  Result.RawDataIndex := AStore.GetRawIndex(ARow);
  Result.Name := AStore.GetItemName(ARow);
  Result.Raw := AStore.RawItem(ARow);
  if (AValueDim >= 0) and (AValueDim < AStore.DimCount) then
  begin
    v := AStore.Get(AValueDim, ARow);
    SetLength(Result.Values, 1);
    Result.Values[0] := v;
  end;
  if Result.Raw.Shape <> rshNone then
    Result.ValueText := TyRawItemText(Result.Raw)
  else if Length(Result.Values) > 0 then
    Result.ValueText := TyLabelNumToStr(Result.Values[0]);
end;

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

{ zrender's parsePercent test: a string with a '%' in it }
function IsPercentText(AData: TJSONData): Boolean;
begin
  Result := (AData <> nil) and (AData.JSONType = jtString) and (Pos('%', AData.AsString) > 0);
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
var series: TJSONObject;
begin
  Result := ABase;
  if AOption = nil then Exit;
  series := ObjOf(AOption.ComponentAt('series', ASlot));
  if series = nil then Exit;
  Result := TyLabelSpecOfNode(ObjOf(series.Find('label')), series, ABase);
end;

function TyLabelSpecOfNode(ANode, ASeries: TJSONObject;
  const ABase: TTyLabelSpec): TTyLabelSpec;
const
  cStates: array[0..2] of string = ('emphasis', 'blur', 'select');
var
  st: TJSONObject;
  k: Integer;
  series, node: TJSONObject;
  d: TJSONData;
  arr: TJSONArray;
  known: Boolean;
  pos: TTyLabelPosition;
  s: string;
  v: Double;
begin
  Result := ABase;
  series := ASeries;
  node := ANode;
  { A STATE THAT SHOWS THE LABEL, read whether or not the series writes a
    `label` of its own: needsCreateText [Batch 88] }
  if series <> nil then
    for k := 0 to 2 do
    begin
      st := ObjOf(series.Find(cStates[k]));
      if st <> nil then st := ObjOf(st.Find('label'));
      if st = nil then Continue;
      d := st.Find('show');
      if (d <> nil) and (d.JSONType = jtBoolean) and d.AsBoolean then
        Result.StateShow := True;
    end;
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
      if arr.Count > 0 then
      begin
        PercentOf(arr.Items[0], 1, Result.AtX);
        Result.AtXIsPercent := IsPercentText(arr.Items[0]);
      end;
      if arr.Count > 1 then
      begin
        PercentOf(arr.Items[1], 1, Result.AtY);
        Result.AtYIsPercent := IsPercentText(arr.Items[1]);
      end;
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
    { `labelRotate *= Math.PI / 180`: the factor first [Batch 103: it was
      (r * Pi) / 180, an ulp off] }
    Result.RotationRad :=
      Max(Double(-360), Min(Double(360), d.AsFloat)) * (Pi / 180);

  { align / verticalAlign (baseline its old name), normalised as zrender's
    Text normalizeStyle does }
  d := node.Find('align');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    Result.HasAlignH := True;
    s := d.AsString;
    if (s = 'center') or (s = 'middle') then Result.AlignH := tahCentre
    else if s = 'right' then Result.AlignH := tahRight
    else Result.AlignH := tahLeft;
  end;
  d := node.Find('verticalAlign');
  if (d = nil) or (d.JSONType = jtNull) then d := node.Find('baseline');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    Result.HasAlignV := True;
    s := d.AsString;
    if (s = 'middle') or (s = 'center') then Result.AlignV := tavMiddle
    else if s = 'bottom' then Result.AlignV := tavBottom
    else Result.AlignV := tavTop;
  end;

  { minMargin over textMargin, each through the model chain: a minMargin
    the base read stays over this node's textMargin (labelStyle.ts:465-480)
    [Batch 103] }
  d := node.Find('minMargin');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    Result.MarginType := 1;
    { `!isNumber(minMargin) ? 0 : minMargin / 2` }
    if d.JSONType = jtNumber then v := d.AsFloat / 2 else v := 0;
    for k := 0 to 3 do Result.MarginLogical[k] := v;
  end
  else if Result.MarginType <> 1 then
  begin
    d := node.Find('textMargin');
    if (d <> nil) and (d.JSONType <> jtNull) then
    begin
      Result.MarginType := 2;
      { normalizeCssArray }
      if d.JSONType = jtNumber then
        for k := 0 to 3 do Result.MarginLogical[k] := d.AsFloat
      else if d is TJSONArray then
      begin
        arr := TJSONArray(d);
        for k := 0 to 3 do Result.MarginLogical[k] := NaN;
        for k := 0 to Min(arr.Count, 4) - 1 do
          if arr.Items[k].JSONType = jtNumber then
            Result.MarginLogical[k] := arr.Items[k].AsFloat;
        if arr.Count = 2 then
        begin
          Result.MarginLogical[2] := Result.MarginLogical[0];
          Result.MarginLogical[3] := Result.MarginLogical[1];
        end
        else if arr.Count = 3 then
          Result.MarginLogical[3] := Result.MarginLogical[1];
      end
      else
        Result.MarginType := 0;
    end;
  end;

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

  { valueAnimation and its precision [Batch 92] }
  d := node.Find('valueAnimation');
  if d <> nil then
    case d.JSONType of
      jtBoolean: Result.ValueAnim := d.AsBoolean;
      jtNumber: Result.ValueAnim := (not IsNan(d.AsFloat)) and (d.AsFloat <> 0);
      jtString: Result.ValueAnim := d.AsString <> '';
      jtNull: Result.ValueAnim := False;
    else
      Result.ValueAnim := True;
    end;
  d := node.Find('precision');
  if d <> nil then
  begin
    if d.JSONType = jtNumber then
    begin
      Result.HasPrecision := True;
      Result.Precision := d.AsFloat;
    end
    else if (d.JSONType = jtNull) or ((d.JSONType = jtString) and (d.AsString = 'auto')) then
      Result.HasPrecision := False;
  end;

  { AN AUTHOR'S fontSize IS CSS PX, not the theme's points: 14 read as a
    point size drew a third too large [Batch 83] }
  Result.FontSizeLogical := TyOptFontSize(node.Find('fontSize'),
    Result.FontSizeLogical);
  s := StrIn(node, 'fontWeight');
  if (s = 'bold') or (s = 'bolder') then Result.FontWeight := 700
  else if s = 'normal' then Result.FontWeight := 400
  else
    Result.FontWeight := TyRoundOpt(NumIn(node, 'fontWeight', Result.FontWeight),
      Result.FontWeight);
  ResolveBlock(node, Result);
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
  s := StrIn(emph, 'textBorderColor');
  if s <> '' then
  begin
    ASpec.EmphHasBorderColour := True;
    if (s = 'none') or (s = 'transparent') then ASpec.EmphBorderColourNone := True
    else if (s = 'inherit') or (s = 'auto') then ASpec.EmphBorderColourInherit := True
    else if TyTryParseChartColor(s, c) then ASpec.EmphBorderColour := c
    else ASpec.EmphBorderColourNone := True;
  end;
end;

procedure TyLabelReadBlock(ALabel: TJSONObject; ARoot: TJSONData;
  var ASpec: TTyLabelSpec);
var root: TJSONObject;
begin
  if ARoot is TJSONObject then root := TJSONObject(ARoot) else root := nil;
  ASpec.RtGlobal := TyRtGlobalOf(root, '', 0, 0);
  if (ALabel = nil) or not TyRtNodeWantsBlock(ALabel) then Exit;
  ASpec.Rt := TyRtResolve([ALabel], ASpec.RtGlobal, TyRtResolveOpt(True));
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

function TyLabelValueTemplate(const AFormatter: string; AHasFormatter: Boolean;
  ADefault: TTyLabelDefaultText; AStore: TTyDataStore; ARow: Integer;
  const ASeriesName: string; AValueDim: Integer; ASeriesIndex: Integer;
  const ASeriesType: string; AColor: TTyChartColor): string;
begin
  if AHasFormatter and TyChartIsHandlerRef(AFormatter) then Exit('');
  Result := TyLabelText(AFormatter, AHasFormatter, ADefault, AStore, ARow,
    ASeriesName, AValueDim, 0, False, ASeriesIndex, ASeriesType, AColor, '',
    True, #1);
end;

function TyLabelText(const AFormatter: string; AHasFormatter: Boolean;
  ADefault: TTyLabelDefaultText; AStore: TTyDataStore; ARow: Integer;
  const ASeriesName: string; AValueDim: Integer; APercent: Double;
  AHasPercent: Boolean; ASeriesIndex: Integer; const ASeriesType: string;
  AColor: TTyChartColor; const ADataType: string; AHasValueText: Boolean;
  const AValueText: string): string;
var
  nameText, valueText: string;
  i, dim, openAt, n: Integer;
  v: Double;
  key: string;
  vars: array of TTyStringArray;
  it: TTyRawItem;
  hasRaw: Boolean;
  cell: TTyDataValue;
  lp: TTyIntegerArray;
begin
  { A NAMED HANDLER IS HANDED THE PARAMS AND ITS ANSWER IS THE LABEL, as
    upstream's getFormattedLabel returns a function formatter's result as it
    stands -- no template pass over it. }
  if AHasFormatter and TyChartIsHandlerRef(AFormatter) then
    Exit(TyChartRunHandler(AFormatter, TyChartOneParams(TyLabelParams(AStore,
      ARow, ASeriesName, AValueDim, APercent, AHasPercent, ASeriesIndex,
      ASeriesType, AColor, ADataType))));
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
    if hasRaw and AStore.HasLabelPositions then
    begin
      { upstream's defaultedLabel: `encode.label`, or the last coordinate a
        label suits -- none on a category-category chart. Several are
        String()-ed and joined by ONE space, a gap as nothing. }
      lp := AStore.LabelPositions;
      for i := 0 to High(lp) do
      begin
        if i > 0 then valueText := valueText + ' ';
        if TTyDataStore.RawCell(it, lp[i], cell) then
          valueText := valueText + TyJsValueText(cell, '');
      end;
    end
    else if (AValueDim >= 0) and (AValueDim < AStore.DimCount) then
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
    { an interpolated value is its own default text, whatever the type's }
    if AHasValueText then Exit(AValueText);
    if ADefault = tldName then Exit(nameText);
    if ADefault = tldRawThird then
    begin
      { `rawValue[2] + ''` when the raw value has a third element that is not
        null, else '-' }
      if hasRaw and TTyDataStore.RawCell(it, 2, cell) and (cell.Kind <> dvkNone) then
        Exit(TyJsValueText(cell, ''));
      Exit('-');
    end;
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
  { params.value is the interpolated one [Batch 92] }
  if AHasValueText then vars[0][2] := AValueText;
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
