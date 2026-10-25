unit test.advchart.mergevis;
{$mode objfpc}{$H+}
{ [R3-B] THE MERGE ORACLES' `vis` AND `gfx` RECORDS, against a chart.

  tools/advchart-oracle/option-merge.js, media.js and timeline.js record,
  in the cases marked so:
    vis  {vm, items}: per visualMap slot the model's own inRange /
         outOfRange / target / controller -- what completeVisualOption made
         of them and the merges kept -- and per series slot each item's
         element [fill, opacity];
    gfx  the graphic view's elements by id: [id, x, y, fill] (x and y the
         16 hex digits of the double where AHex, else numbers).
  The visuals are compared as JSON values, key order aside (the model's
  keys are upstream's merges' order, which the port's JSON does not
  promise); a fill as its colour and alpha; positions exactly. }
interface
uses SysUtils, Math, fpjson, jsonparser,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Color, tyControls.AdvanceChart.GfxEl,
     tyControls.AdvanceChart;

type
  TTyMvBad = procedure(const AWhere, AWhat: string) of object;

{ the comparisons made; every difference reported through ABad }
function TyMvCheckVis(AChart: TTyAdvanceChart; AList: TTyPaintList;
  AExp: TJSONObject; const AWhere: string; ABad: TTyMvBad): Integer;
function TyMvCheckGfx(AChart: TTyAdvanceChart; AExp: TJSONArray; AHex: Boolean;
  const AWhere: string; ABad: TTyMvBad): Integer;
{ a JSON value as upstream's, key order aside; numbers exactly }
function TyMvCmpSame(const APath: string; AExp, AGot: TJSONData; ABad: TTyMvBad): Integer;

implementation

function HexOf(AColor: TTyChartColor): string;
begin
  Result := LowerCase(Format('#%.2x%.2x%.2x', [(AColor shr 16) and 255,
    (AColor shr 8) and 255, AColor and 255]));
end;

function HexNum(AData: TJSONData): Double;
var q: QWord;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(NaN);
  q := StrToQWord('$' + AData.AsString);
  Result := 0;
  Move(q, Result, SizeOf(Result));
end;

function SameNum(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  Result := A = B;
end;

function TyMvCmpSame(const APath: string; AExp, AGot: TJSONData; ABad: TTyMvBad): Integer;
var
  i: Integer;
begin
  Result := 1;
  if (AGot = nil) or (AExp.JSONType <> AGot.JSONType) then
  begin
    if AGot = nil then ABad(APath, 'upstream ' + AExp.AsJSON + ', nothing here')
    else ABad(APath, 'upstream ' + AExp.AsJSON + ', here ' + AGot.AsJSON);
    Exit;
  end;
  case AExp.JSONType of
    jtNumber:
      if not SameNum(AExp.AsFloat, AGot.AsFloat) then
        ABad(APath, Format('upstream %.17g, here %.17g', [AExp.AsFloat, AGot.AsFloat]));
    jtString, jtBoolean:
      if AExp.AsJSON <> AGot.AsJSON then ABad(APath, 'upstream ' + AExp.AsJSON + ', here ' + AGot.AsJSON);
    jtArray:
      if AExp.Count <> AGot.Count then
        ABad(APath, 'upstream ' + AExp.AsJSON + ', here ' + AGot.AsJSON)
      else
        for i := 0 to AExp.Count - 1 do
          Inc(Result, TyMvCmpSame(APath + '[' + IntToStr(i) + ']', AExp.Items[i], AGot.Items[i], ABad));
    jtObject:
      begin
        if AExp.Count <> AGot.Count then
          ABad(APath, 'upstream ' + AExp.AsJSON + ', here ' + AGot.AsJSON);
        for i := 0 to AExp.Count - 1 do
          Inc(Result, TyMvCmpSame(APath + '.' + TJSONObject(AExp).Names[i], AExp.Items[i],
            TJSONObject(AGot).Find(TJSONObject(AExp).Names[i]), ABad));
      end;
  end;
end;

function TyMvCheckVis(AChart: TTyAdvanceChart; AList: TTyPaintList;
  AExp: TJSONObject; const AWhere: string; ABad: TTyMvBad): Integer;
var
  arr, it, pair: TJSONArray;
  s, i, k: Integer;
  el: TTyChartElement;
  found: Boolean;
  c: TTyChartColor;
  got: TJSONData;
  w: string;
begin
  Result := 0;
  arr := TJSONArray(AExp.Find('vm'));
  for k := 0 to arr.Count - 1 do
  begin
    w := Format('%s.vm[%d]', [AWhere, k]);
    if arr.Items[k].JSONType = jtNull then Continue;
    got := GetJSON(AChart.VisualMapVisualsJson(k));
    try
      Inc(Result, TyMvCmpSame(w, arr.Items[k], got, ABad));
    finally
      got.Free;
    end;
  end;
  arr := TJSONArray(AExp.Find('items'));
  for s := 0 to arr.Count - 1 do
  begin
    if arr.Items[s].JSONType = jtNull then Continue;
    it := TJSONArray(arr.Items[s]);
    for i := 0 to it.Count - 1 do
    begin
      w := Format('%s.items[%d][%d]', [AWhere, s, i]);
      found := False;
      el := Default(TTyChartElement);
      if AList <> nil then
        for k := 0 to AList.Count - 1 do
        begin
          el := AList.Element(k);
          if (el.Datum.SeriesIndex <> s) or (el.Datum.DataIndex <> i) or el.Ignore then Continue;
          if not (el.Shape.Kind in [cskRect, cskRoundRect]) then Continue;
          found := True;
          Break;
        end;
      Inc(Result);
      if it.Items[i].JSONType = jtNull then
      begin
        if found then ABad(w, 'no element upstream, one here');
        Continue;
      end;
      if not found then
      begin
        ABad(w, 'no element here');
        Continue;
      end;
      pair := TJSONArray(it.Items[i]);
      if (pair.Items[0] is TJSONString) and TyTryParseChartColor(pair.Strings[0], c) then
      begin
        Inc(Result);
        if (HexOf(c) <> HexOf(el.Style.FillColor))
          or (Abs(TyChartColorAlpha(c) - TyChartColorAlpha(el.Style.FillColor)) > 0.002) then
          ABad(w + '.fill', Format('upstream %s, here %s alpha %g', [pair.Strings[0],
            HexOf(el.Style.FillColor), TyChartColorAlpha(el.Style.FillColor)]));
      end;
      Inc(Result);
      if not SameNum(pair.Floats[1], el.Style.Alpha) then
        ABad(w + '.opacity', Format('upstream %.17g, here %.17g', [pair.Floats[1], el.Style.Alpha]));
    end;
  end;
end;

function TyMvCheckGfx(AChart: TTyAdvanceChart; AExp: TJSONArray; AHex: Boolean;
  const AWhere: string; ABad: TTyMvBad): Integer;
var
  i, n: Integer;
  e: TJSONArray;
  el: TTyGfxEl;
  w, fill: string;
  x, y: Double;
  d: TJSONData;
  a, b: TTyChartColor;
  all: TTyGfxElArray;
begin
  Result := 1;
  { as many elements as the view keeps }
  all := nil;
  if AChart.GraphicView <> nil then TyGfxTraverse(AChart.GraphicView.Root, all);
  n := 0;
  for i := 0 to High(all) do
    if (all[i] <> AChart.GraphicView.Root) and (all[i].Host = nil) and not all[i].Gone then Inc(n);
  if n <> AExp.Count then
    ABad(AWhere, Format('upstream %d elements, here %d', [AExp.Count, n]));
  for i := 0 to AExp.Count - 1 do
  begin
    e := TJSONArray(AExp.Items[i]);
    w := AWhere + '[' + e.Strings[0] + ']';
    el := nil;
    if AChart.GraphicView <> nil then el := AChart.GraphicView.Find(e.Strings[0]);
    Inc(Result);
    if el = nil then
    begin
      ABad(w, 'no element here');
      Continue;
    end;
    if AHex then
    begin
      x := HexNum(e.Items[1]);
      y := HexNum(e.Items[2]);
    end
    else
    begin
      x := e.Floats[1];
      y := e.Floats[2];
    end;
    Inc(Result, 2);
    if not SameNum(x, el.X) then ABad(w + '.x', Format('upstream %.17g, here %.17g', [x, el.X]));
    if not SameNum(y, el.Y) then ABad(w + '.y', Format('upstream %.17g, here %.17g', [y, el.Y]));
    if e.Items[3].JSONType = jtString then
    begin
      Inc(Result);
      { zrender's path default where the style has none }
      fill := '#000';
      d := el.Style.Find('fill');
      if (d <> nil) and (d.JSONType = jtString) then fill := d.AsString;
      if not (TyTryParseChartColor(e.Strings[3], a) and TyTryParseChartColor(fill, b) and (a = b)) then
        ABad(w + '.fill', 'upstream ' + e.Strings[3] + ', here ' + fill);
    end;
  end;
end;

end.
