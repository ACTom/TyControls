unit tyControls.AdvChart.Export;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- the export options: what getDataURL / renderToCanvas
  take and how upstream resolves them, read off echarts.ts, zrender
  canvas/Painter.ts getRenderedCanvas and canvas/Layer.ts clear, and held to
  the real dist by tools/advchart-oracle/export-loading.js. [Batch 106, B11]

  THE OPTIONS are an object of `type`, `pixelRatio`, `backgroundColor` and
  `excludeComponents`,
  each read for its JavaScript truthiness, as upstream reads them:

    type               'jpeg' is a JPEG; anything else -- 'png', 'svg',
                       'jpg', unset -- is what a canvas answers
                       toDataURL('image/' + type) with when it cannot make
                       that type: a PNG.
    pixelRatio         `opts.pixelRatio || devicePixelRatio`. Upstream's
                       ratio is per CSS px; the port's CSS px is its logical
                       px (device px * 96 / PPI), so the image is
                       floor(logical size * ratio) and the chart is laid out
                       again at PPI 96 * ratio. Unset (or 0, or not a
                       positive number) is the control's own size and PPI --
                       the device ratio. Capped so that no side passes
                       TyExportMaxSide.
    backgroundColor    `opts.backgroundColor || model backgroundColor`,
                       then the painter's own -- which upstream makes
                       'transparent' and the port makes the skin's ground
                       (the frame the window shows). The chosen value is
                       then what Layer.clear does with it: 'transparent'
                       clears; a colour fills the whole image (an rgba with
                       alpha 0 fills with nothing); a gradient or a pattern
                       object fills; anything else -- 'none', a string that
                       is no colour, a number -- leaves the context's
                       fillStyle at its default and fills OPAQUE BLACK.
    excludeComponents  an array of component main types whose views are
                       hidden for the export. Only an array counts (a string
                       is iterated letter by letter upstream, and no main type
                       is one letter); a type with no view the port draws
                       hides nothing. 'series' throws upstream (a series view
                       is not a component view) and is ignored here.

  WHAT THE EXCLUSION CAN REACH is a VIEW's group. Upstream's axis pointer,
  its richText tooltip and the loading effect are added to zrender directly
  and are never hidden; the grid, the tooltip and the axisPointer components'
  own views hold nothing. The views the port draws are TTyChartView. }
interface
uses
  SysUtils, Math, fpjson, jsonparser,
  tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
  tyControls.AdvChart.Color, tyControls.AdvChart.Option;

type
  { THE VIEWS THE PORT DRAWS, by the component main type upstream files
    them under (every chart view is 'series'). }
  TTyChartView = (cvTitle, cvLegend, cvXAxis, cvYAxis, cvVisualMap,
    cvDataZoom, cvMarkPoint, cvMarkLine, cvMarkArea, cvRadar, cvCalendar,
    cvAngleAxis, cvRadiusAxis, cvSeries);
  TTyChartViews = set of TTyChartView;

  TTyExportImageType = (eitPng, eitJpeg);

  { WHAT THE IMAGE IS CLEARED WITH:
      ebkTheme     nothing was chosen: the skin's ground, the frame the
                   window paints (the port's stand-in for upstream's
                   'transparent' default);
      ebkClear     'transparent', or a colour with no alpha: nothing;
      ebkSolid     a colour;
      ebkGradient, ebkPattern   an object fill over the whole image;
      ebkBlack     a value the canvas cannot take: its default fillStyle. }
  TTyExportBgKind = (ebkTheme, ebkClear, ebkSolid, ebkGradient, ebkPattern,
    ebkBlack);
  TTyExportBg = record
    Kind: TTyExportBgKind;
    Color: TTyChartColor;
    Gradient: TTyChartGradient;
    Pattern: TTyChartPattern;
  end;

  TTyChartExportOpts = record
    { `type` as written (a string), and what it makes }
    HasType: Boolean;
    ImageType: TTyExportImageType;
    { 0 is unset: the control's own size and PPI }
    PixelRatio: Double;
    { opts.backgroundColor was truthy; the value as JSON text }
    HasBackground: Boolean;
    BackgroundJson: string;
    Exclude: TTyChartViews;
  end;

const
  { THE LARGEST SIDE an export is made at, device px. A canvas has limits of
    its own (and a browser fails past them); a bitmap here is width * height
    * 4 bytes, so a stray ratio of 100 must not ask for gigabytes. }
  TyExportMaxSide = 16384;

{ The view a main type names; False for every type the port draws no view
  for (grid, tooltip, axisPointer, toolbox, series, an unknown name). }
function TyChartViewOf(const AMainType: string; out AView: TTyChartView): Boolean;
function TyChartViewName(AView: TTyChartView): string;
{ The views as their main types, sorted, comma-separated -- the oracle's
  `present` and `excluded` lists. }
function TyChartViewsText(AViews: TTyChartViews): string;

{ JavaScript's truthiness of a JSON value: nil, null, false, 0, NaN and ''
  are falsy; every object and array is truthy. }
function TyJsTruthy(AData: TJSONData): Boolean;

{ The export options from their JSON text; '' is none. Text that is valid
  JSON but no object is no options, as upstream's `opts || <empty object>` reads a
  primitive. False only for text that does not parse (or nests too deep). }
function TyExportOptsOf(const AJson: string; out AOpts: TTyChartExportOpts): Boolean;

{ What Layer.clear makes of a chosen (truthy) background value. }
function TyExportBackgroundOf(AData: TJSONData): TTyExportBg;

{ The image's size and the PPI it is laid out at: the control's own for a
  ratio that is not a positive number, else floor(logical size * ratio) at
  PPI round(96 * ratio), the ratio first lowered so that no side passes
  TyExportMaxSide. }
procedure TyExportImageSize(AWidth, AHeight, APPI: Integer; ARatio: Double;
  out AW, AH, AOutPPI: Integer);

implementation

const
  ViewNames: array[TTyChartView] of string = ('title', 'legend', 'xAxis',
    'yAxis', 'visualMap', 'dataZoom', 'markPoint', 'markLine', 'markArea',
    'radar', 'calendar', 'angleAxis', 'radiusAxis', 'series');

function TyChartViewOf(const AMainType: string; out AView: TTyChartView): Boolean;
var v: TTyChartView;
begin
  Result := False;
  AView := cvTitle;
  for v := Low(TTyChartView) to High(TTyChartView) do
    if (v <> cvSeries) and (ViewNames[v] = AMainType) then
    begin
      AView := v;
      Exit(True);
    end;
end;

function TyChartViewName(AView: TTyChartView): string;
begin
  Result := ViewNames[AView];
end;

function TyChartViewsText(AViews: TTyChartViews): string;
var
  names: array of string;
  v: TTyChartView;
  i, j: Integer;
  t: string;
begin
  names := nil;
  for v := Low(TTyChartView) to High(TTyChartView) do
    if v in AViews then
    begin
      SetLength(names, Length(names) + 1);
      names[High(names)] := ViewNames[v];
    end;
  { ordinal order, as JavaScript's sort compares the strings' code units }
  for i := 1 to High(names) do
  begin
    t := names[i];
    j := i - 1;
    while (j >= 0) and (CompareStr(names[j], t) > 0) do
    begin
      names[j + 1] := names[j];
      Dec(j);
    end;
    names[j + 1] := t;
  end;
  Result := '';
  for i := 0 to High(names) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + names[i];
  end;
end;

function TyJsTruthy(AData: TJSONData): Boolean;
begin
  if AData = nil then Exit(False);
  case AData.JSONType of
    jtNull: Result := False;
    jtBoolean: Result := AData.AsBoolean;
    jtNumber: Result := (AData.AsFloat <> 0) and not IsNan(AData.AsFloat);
    jtString: Result := AData.AsString <> '';
  else
    Result := True;
  end;
end;

function TyExportOptsOf(const AJson: string; out AOpts: TTyChartExportOpts): Boolean;
var
  root, d: TJSONData;
  o: TJSONObject;
  arr: TJSONArray;
  i, nLine, nCol: Integer;
  v: TTyChartView;
  r: Double;
begin
  AOpts := Default(TTyChartExportOpts);
  AOpts.ImageType := eitPng;
  Result := True;
  if Trim(AJson) = '' then Exit;
  if TyJsonNestingExceeds(AJson, TyOptionMaxNesting, nLine, nCol) then Exit(False);
  try
    root := GetJSON(AJson);
  except
    Exit(False);
  end;
  try
    if not (root is TJSONObject) then Exit;
    o := TJSONObject(root);
    d := o.Find('type');
    if TyJsTruthy(d) then AOpts.HasType := True;
    if (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'jpeg') then
      AOpts.ImageType := eitJpeg;
    d := o.Find('pixelRatio');
    if (d <> nil) and (d.JSONType = jtNumber) then
    begin
      r := d.AsFloat;
      if (not IsNan(r)) and (not IsInfinite(r)) and (r > 0) then
        AOpts.PixelRatio := r;
    end;
    d := o.Find('backgroundColor');
    if TyJsTruthy(d) then
    begin
      AOpts.HasBackground := True;
      AOpts.BackgroundJson := d.AsJSON;
    end;
    d := o.Find('excludeComponents');
    if d is TJSONArray then
    begin
      arr := TJSONArray(d);
      for i := 0 to arr.Count - 1 do
        if (arr.Items[i].JSONType = jtString)
          and TyChartViewOf(arr.Items[i].AsString, v) then
          Include(AOpts.Exclude, v);
    end;
  finally
    root.Free;
  end;
end;

function TyExportBackgroundOf(AData: TJSONData): TTyExportBg;
var c: TTyChartColor;
begin
  Result := Default(TTyExportBg);
  Result.Kind := ebkTheme;
  if not TyJsTruthy(AData) then Exit;
  Result.Kind := ebkBlack;
  if AData.JSONType = jtString then
  begin
    { Layer.clear: `clearColor && clearColor !== 'transparent'` -- the exact
      string; a colour the canvas reads is filled, alpha and all }
    if AData.AsString = 'transparent' then
      Result.Kind := ebkClear
    else if TyTryParseChartColor(AData.AsString, c) then
    begin
      Result.Color := c;
      if (c shr 24) = 0 then Result.Kind := ebkClear
      else Result.Kind := ebkSolid;
    end;
    Exit;
  end;
  if AData.JSONType = jtObject then
  begin
    if TyTryReadGradient(AData, Result.Gradient)
      and (Result.Gradient.Kind <> cgkNone) then
      Result.Kind := ebkGradient
    else if TyTryReadPattern(AData, Result.Pattern) and Result.Pattern.Present
      and (Result.Pattern.Image <> '') then
      Result.Kind := ebkPattern;
  end;
end;

procedure TyExportImageSize(AWidth, AHeight, APPI: Integer; ARatio: Double;
  out AW, AH, AOutPPI: Integer);
var
  s, lw, lh, big: Double;
begin
  if APPI <= 0 then APPI := 96;
  if IsNan(ARatio) or IsInfinite(ARatio) or (ARatio <= 0) then
  begin
    AW := AWidth;
    AH := AHeight;
    AOutPPI := APPI;
    Exit;
  end;
  { the logical size, exact when the PPI is 96 (a division by 1) }
  s := APPI / 96;
  lw := AWidth / s;
  lh := AHeight / s;
  big := Max(lw, lh) * ARatio;
  if big > TyExportMaxSide then ARatio := TyExportMaxSide / Max(lw, lh);
  AW := Floor(lw * ARatio);
  AH := Floor(lh * ARatio);
  AOutPPI := Max(1, Round(96 * ARatio));
end;

end.
