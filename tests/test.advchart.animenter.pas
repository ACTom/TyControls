unit test.advchart.animenter;
{$mode objfpc}{$H+}
{ THE ENTER ANIMATIONS ON THE REAL CONTROL, held to upstream. [Batch 89, AN2]

  tools/advchart-oracle/animation.js steps the real ECharts 6.1 build under a
  hand-driven clock and records every element's animated properties at
  t = 0, 1, 16, 50, 100, 250, 500, 750, 999, 1000, 1001 and 1500 ms, with
  the live clip count at each. This builds every enter and threshold case's
  option on a TTyAdvanceChart (zrender's SSR text measure, 400 x 300,
  camAlways), renders it with the clock at T0 = 1700000000000 -- the render
  takes the synchronous first step, upstream's flush -- steps the clock to
  each sample with AnimTick, and compares:

    - every animated element the port models: its proxy's value of every
      tracked key, BIT FOR BIT, final value included; the one exception is a
      candle's across coordinate (upstream sub-pixel-optimises the body's
      sides, the port does not), which must hold still on both sides and is
      compared by its animation WEIGHT; keys the fixture does not track must
      hold still;
    - the proxy's animator count against the element's;
    - the clip count against upstream's, less the animators of the elements
      a later batch models (a value count-up, a marker, a ripple);
    - at rest: every key at (to - from) * 1 + from, and the frame drawn from
      the proxies identical to the static list wherever the proxy rests on
      the layout.

  Deferred, by element: valueAnimation texts (the gauge detail, bar-label's
  labels, line-endlabel's end label), markLine / markPoint, and the whole
  effectScatter case (its ripples) -- AN4. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Measure,
     tyControls.AdvChart.Anim, tyControls.AdvChart.AnimOpt,
     tyControls.AdvChart.AnimView, tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TAnProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    function Frame: TTyPaintList;
  end;

  TAnMapKind = (amkStatic, amkModel, amkDeferred, amkUnknown);
  TAnMap = record
    Kind: TAnMapKind;
    Series, Index: Integer;
    Role: string;
  end;

  TAdvChartAnimEnterTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TAnProbe;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FWeighed: Integer;
    FReport: string;
    FSeen: TStringList;
    procedure Miss(const AWhere: string; const AOnce: string = '');
    function HIdx50(ADataIndex: Integer; AHasIndex: Boolean): Double;
    function HDur600(ADataIndex: Integer; AHasIndex: Boolean): Double;
    procedure NewChart(AMode: TTyChartAnimationMode);
    procedure Load(const AOption: string);
    procedure RunCase(ACase: TJSONObject);
    function Draw: TBGRABitmap;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEnterTimelinesAsUpstream;
    procedure TestHeadlessRenderDoesNotAnimateByDefault;
    procedure TestOffModeAndOptionOff;
    procedure TestSeriesMoveInTheDynamicLayer;
    procedure TestABarLabelRidesItsBar;
    procedure TestHeatmapCellsNeverAnimate;
    procedure TestANewOptionAnimatesAgainAndAResizeSnaps;
    procedure TestClipFalseLosesItsWideningWhenAnimated;
  end;

implementation

const
  cW = 400;
  cH = 300;

var
  GFixture: TJSONData = nil;

function Fixture: TJSONObject;
var sl: TStringList;
begin
  if GFixture = nil then
  begin
    sl := TStringList.Create;
    try
      sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
        + 'advchart-animation.json');
      GFixture := GetJSON(sl.Text);
    finally
      sl.Free;
    end;
  end;
  Result := TJSONObject(GFixture);
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Hex(A: Double): string;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

function SameBits(A, B: Double): Boolean;
begin
  Result := Hex(A) = Hex(B);
end;

function Fmt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function IsHex16(AData: TJSONData): Boolean;
var s: string; i: Integer;
begin
  Result := False;
  if (AData = nil) or (AData.JSONType <> jtString) then Exit;
  s := AData.AsString;
  if Length(s) <> 16 then Exit;
  for i := 1 to 16 do
    if not (s[i] in ['0'..'9', 'a'..'f', 'A'..'F']) then Exit;
  Result := True;
end;

{ A recorded value as numbers: one, or a flattened array. False for a value
  that is not a number (a colour string, a text, a boolean). }
function NumsOf(AData: TJSONData; out ANums: TTyDoubleArray): Boolean;
var i: Integer;
begin
  ANums := nil;
  Result := False;
  if AData = nil then Exit;
  if IsHex16(AData) then
  begin
    SetLength(ANums, 1);
    ANums[0] := FromHex(AData.AsString);
    Exit(True);
  end;
  if AData.JSONType <> jtArray then Exit;
  SetLength(ANums, AData.Count);
  for i := 0 to AData.Count - 1 do
  begin
    if not IsHex16(AData.Items[i]) then Exit(False);
    ANums[i] := FromHex(AData.Items[i].AsString);
  end;
  Result := True;
end;

function ProxyNums(AProxy: TTyChartAnimProxy; const AKey: string;
  out ANums: TTyDoubleArray): Boolean;
var v: TTyAnimValue;
begin
  ANums := nil;
  v := AProxy.GetAnimProp(AKey);
  case v.Kind of
    avkNumber, avkBool:
      begin
        SetLength(ANums, 1);
        ANums[0] := v.Num;
        Result := True;
      end;
    avkArray:
      begin
        ANums := Copy(v.Arr, 0, Length(v.Arr));
        Result := True;
      end;
  else
    Result := False;
  end;
end;

function FinalNums(AProxy: TTyChartAnimProxy; const AKey: string): TTyDoubleArray;
var v: TTyAnimValue;
begin
  Result := nil;
  v := AProxy.FinalOf(AKey);
  case v.Kind of
    avkNumber, avkBool:
      begin
        SetLength(Result, 1);
        Result[0] := v.Num;
      end;
    avkArray: Result := Copy(v.Arr, 0, Length(v.Arr));
  end;
end;

// {"$fn": name} -> '@name', in place, everywhere
procedure ConvertFns(AData: TJSONData);
var
  i: Integer;
  o: TJSONObject;
  child: TJSONData;
begin
  if AData = nil then Exit;
  if AData.JSONType = jtArray then
  begin
    for i := 0 to AData.Count - 1 do
    begin
      child := AData.Items[i];
      if (child.JSONType = jtObject) and (TJSONObject(child).Count = 1)
        and (TJSONObject(child).Find('$fn') <> nil) then
        TJSONArray(AData).Items[i] := TJSONString.Create('@' + TJSONObject(child).Strings['$fn'])
      else
        ConvertFns(child);
    end;
  end
  else if AData.JSONType = jtObject then
  begin
    o := TJSONObject(AData);
    for i := 0 to o.Count - 1 do
    begin
      child := o.Items[i];
      if (child.JSONType = jtObject) and (TJSONObject(child).Count = 1)
        and (TJSONObject(child).Find('$fn') <> nil) then
        o.Items[i] := TJSONString.Create('@' + TJSONObject(child).Strings['$fn'])
      else
        ConvertFns(child);
    end;
  end;
end;

function T0: Double;
begin
  Result := Fixture.Objects['clock'].Floats['T0'];
end;

{ ==================== the probe ==================== }

function TAnProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TAnProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TAnProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TAnProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

{ ==================== mapping upstream's elements ==================== }

{ 'seriesN:type' -> N, type; and the path's leading number }
function MapElement(AEl: TJSONObject): TAnMap;
var
  id, owner, path, typ, stype, role, base: string;
  p, k, di: Integer;
  hasTrack, hasAnim: Boolean;
  d, a: TJSONData;
  parts: TStringList;
begin
  Result := Default(TAnMap);
  Result.Kind := amkStatic;
  id := AEl.Strings['id'];
  owner := AEl.Strings['owner'];
  role := AEl.Strings['role'];
  typ := AEl.Strings['type'];
  d := AEl.Find('track');
  hasTrack := (d <> nil) and (d.JSONType = jtObject) and (d.Count > 0);
  hasAnim := False;
  a := AEl.Find('animators');
  if (a <> nil) and (a.JSONType = jtArray) then
    for k := 0 to a.Count - 1 do
      if a.Items[k].AsInteger > 0 then hasAnim := True;
  if not (hasTrack or hasAnim) then Exit;
  di := -1;
  d := AEl.Find('dataIndex');
  if (d <> nil) and (d.JSONType = jtNumber) then di := d.AsInteger;
  { the markers, and a value counting up: AN4's }
  if (Pos('markLine', owner) = 1) or (Pos('markPoint', owner) = 1)
    or (Pos('markArea', owner) = 1) then
  begin
    Result.Kind := amkDeferred;
    Exit;
  end;
  d := AEl.Find('track');
  if (d <> nil) and (d.JSONType = jtObject)
    and (TJSONObject(d).Find('style.text') <> nil) then
  begin
    Result.Kind := amkDeferred;
    Exit;
  end;
  Result.Kind := amkUnknown;
  p := Pos(':', owner);
  if (Pos('series', owner) <> 1) or (p = 0) then Exit;
  Result.Series := StrToIntDef(Copy(owner, 7, p - 7), -1);
  stype := Copy(owner, p + 1, MaxInt);
  path := Copy(id, Pos('/', id) + 1, MaxInt);
  base := path;
  if Pos('#', base) > 0 then base := Copy(base, 1, Pos('#', base) - 1);
  parts := TStringList.Create;
  try
    parts.Delimiter := '.';
    parts.StrictDelimiter := True;
    parts.DelimitedText := base;
    if stype = 'effectScatter' then
    begin
      Result.Kind := amkDeferred;
      Exit;
    end;
    if stype = 'bar' then
    begin
      if Pos('#label', id) > 0 then
      begin
        { a counting label is AN4's; a plain one fades }
        Result.Kind := amkModel;
        Result.Role := 'label';
        Result.Index := StrToIntDef(parts[0], -1);
      end
      else if typ = 'rect' then
      begin
        Result.Kind := amkModel;
        Result.Role := 'bar';
        Result.Index := di;
      end;
    end
    else if stype = 'line' then
    begin
      if Pos('#clip', id) > 0 then
      begin
        Result.Kind := amkModel;
        Result.Role := 'lineClip';
        Result.Index := -1;
      end
      else if Pos('#label', id) > 0 then
      begin
        { a symbol's label is 0.<row>.0#label; the end label (1.0#label)
          slides with the clip -- AN4's }
        if (parts.Count >= 3) and (parts[0] = '0') then
        begin
          Result.Kind := amkModel;
          Result.Role := 'label';
          Result.Index := StrToIntDef(parts[1], -1);
        end
        else
          Result.Kind := amkDeferred;
      end
      else if (typ = 'group') and (di >= 0) then
      begin
        Result.Kind := amkModel;
        Result.Role := 'lineSymbol';
        Result.Index := di;
      end;
    end
    else if stype = 'scatter' then
    begin
      if Pos('#label', id) > 0 then
      begin
        Result.Kind := amkModel;
        Result.Role := 'label';
        Result.Index := StrToIntDef(parts[1], -1);
      end
      else if di >= 0 then
      begin
        Result.Kind := amkModel;
        Result.Role := 'symbol';
        Result.Index := di;
      end;
    end
    else if (stype = 'pie') or (stype = 'funnel') then
    begin
      Result.Kind := amkModel;
      Result.Index := StrToIntDef(parts[0], -1);
      if Pos('#label', id) > 0 then Result.Role := 'label'
      else if Pos('#guide', id) > 0 then Result.Role := 'guide'
      else if stype = 'pie' then Result.Role := 'sector'
      else Result.Role := 'funnel';
    end
    else if stype = 'gauge' then
    begin
      Result.Index := di;
      if typ = 'pointer' then
      begin
        Result.Kind := amkModel;
        Result.Role := 'gaugePointer';
      end
      else if typ = 'sector' then
      begin
        Result.Kind := amkModel;
        Result.Role := 'gaugeProgress';
      end;
    end
    else if stype = 'radar' then
    begin
      Result.Kind := amkModel;
      Result.Index := StrToIntDef(parts[0], -1);
      if (parts.Count >= 2) and (parts[1] = '1') then Result.Role := 'radarArea'
      else Result.Role := 'radarLine';
    end
    else if stype = 'candlestick' then
    begin
      Result.Kind := amkModel;
      Result.Role := 'candle';
      Result.Index := di;
    end;
  finally
    parts.Free;
  end;
end;

{ ==================== plumbing ==================== }

function TAdvChartAnimEnterTest.HIdx50(ADataIndex: Integer; AHasIndex: Boolean): Double;
begin
  { (idx) => idx * 50; null * 50 is 0, and undefined's NaN is a 0 delay too }
  if AHasIndex then Result := ADataIndex * 50 else Result := 0;
end;

function TAdvChartAnimEnterTest.HDur600(ADataIndex: Integer; AHasIndex: Boolean): Double;
begin
  if AHasIndex then Result := 600 + ADataIndex * 100 else Result := 600;
end;

procedure TAdvChartAnimEnterTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  TyChartRegisterAnimTiming('idx*50', @HIdx50);
  TyChartRegisterAnimTiming('dur:600+idx*100', @HDur600);
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-text-style.json');
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart := nil;
  FSeen := TStringList.Create;
  FBad := 0;
  FCompared := 0;
  FWeighed := 0;
  FReport := '';
end;

procedure TAdvChartAnimEnterTest.TearDown;
begin
  TyChartClearAnimTimings;
  FreeAndNil(FSeen);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

{ AOnce: report one failure of that name only, the first sample's }
procedure TAdvChartAnimEnterTest.Miss(const AWhere: string; const AOnce: string);
begin
  Inc(FBad);
  if AOnce <> '' then
  begin
    if FSeen.IndexOf(AOnce) >= 0 then Exit;
    FSeen.Add(AOnce);
  end;
  if FSeen.Count + Ord(AOnce = '') <= 40 then
    FReport := FReport + LineEnding + '  ' + AWhere;
end;

procedure TAdvChartAnimEnterTest.NewChart(AMode: TTyChartAnimationMode);
begin
  FreeAndNil(FChart);
  FChart := TAnProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := AMode;
  FChart.AnimNow := T0;
end;

procedure TAdvChartAnimEnterTest.Load(const AOption: string);
begin
  FChart.Option := AOption;
  AssertEquals('the option parses', '', FChart.OptionError);
  FChart.SetBounds(0, 0, cW, cH);
  Draw;
end;

{ the keys the oracle records: the transform, nine style keys, every shape
  key }
function Recorded(const AKey: string): Boolean;
const
  cStyle: array[0..8] of string = ('opacity', 'fill', 'stroke', 'lineWidth',
    'text', 'x', 'y', 'fillOpacity', 'strokeOpacity');
var i: Integer;
begin
  if Pos('shape.', AKey) = 1 then Exit(True);
  if Pos('style.', AKey) = 1 then
  begin
    for i := 0 to High(cStyle) do
      if AKey = 'style.' + cStyle[i] then Exit(True);
    Exit(False);
  end;
  Result := True;
end;

function TAdvChartAnimEnterTest.Draw: TBGRABitmap;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
  Result := FBmp;
end;

{ ==================== the timelines ==================== }

function SameShape(const A, B: TTyChartElement): Boolean;
var i: Integer;
begin
  Result := (A.Shape.Kind = B.Shape.Kind)
    and SameBits(A.Shape.Bounds.Left, B.Shape.Bounds.Left)
    and SameBits(A.Shape.Bounds.Top, B.Shape.Bounds.Top)
    and SameBits(A.Shape.Bounds.Right, B.Shape.Bounds.Right)
    and SameBits(A.Shape.Bounds.Bottom, B.Shape.Bounds.Bottom)
    and SameBits(A.Shape.CX, B.Shape.CX) and SameBits(A.Shape.CY, B.Shape.CY)
    and SameBits(A.Shape.R0, B.Shape.R0) and SameBits(A.Shape.R1, B.Shape.R1)
    and SameBits(A.Shape.StartRad, B.Shape.StartRad)
    and SameBits(A.Shape.EndRad, B.Shape.EndRad)
    and SameBits(A.Shape.RotationRad, B.Shape.RotationRad)
    and (Length(A.Shape.Points) = Length(B.Shape.Points))
    and SameBits(A.Style.Alpha, B.Style.Alpha)
    and (A.HasClip = B.HasClip)
    and SameBits(A.ClipRect.Left, B.ClipRect.Left)
    and SameBits(A.ClipRect.Top, B.ClipRect.Top)
    and SameBits(A.ClipRect.Right, B.ClipRect.Right)
    and SameBits(A.ClipRect.Bottom, B.ClipRect.Bottom)
    and SameBits(A.Caption.X, B.Caption.X) and SameBits(A.Caption.Y, B.Caption.Y)
    and (A.Caption.Text = B.Caption.Text);
  if not Result then Exit;
  for i := 0 to High(A.Shape.Points) do
    if not (SameBits(A.Shape.Points[i].X, B.Shape.Points[i].X)
      and SameBits(A.Shape.Points[i].Y, B.Shape.Points[i].Y)) then Exit(False);
end;

procedure TAdvChartAnimEnterTest.RunCase(ACase: TJSONObject);
var
  opt: TJSONData;
  samples, clips, els, anim: TJSONArray;
  el, track: TJSONObject;
  maps: array of TAnMap;
  name, key: string;
  s, e, k, j, want, deferred, n: Integer;
  m: TAnMap;
  p: TTyChartAnimProxy;
  up, upF, up0, got, gotF: TTyDoubleArray;
  got0: array of array of TTyDoubleArray;
  exact: Boolean;
  wu, wp: Double;
  lst, frm: TTyPaintList;
  a, b: TTyChartElement;
begin
  name := ACase.Strings['id'];
  opt := ACase.Objects['option'].Clone;
  try
    ConvertFns(opt);
    NewChart(camAlways);
    Load(opt.AsJSON);
  finally
    opt.Free;
  end;
  samples := Fixture.Arrays['samplesMs'];
  clips := ACase.Arrays['clips'];
  els := ACase.Arrays['elements'];
  SetLength(maps, els.Count);
  SetLength(got0, els.Count);
  for e := 0 to els.Count - 1 do
  begin
    maps[e] := MapElement(els.Objects[e]);
    if maps[e].Kind = amkUnknown then
      Miss(Format('%s: %s is not mapped', [name, els.Objects[e].Strings['id']]));
  end;

  for s := 0 to samples.Count - 1 do
  begin
    if s > 0 then FChart.AnimTick(T0 + samples.Items[s].AsFloat);
    { a frame is built every sample; drawn on one }
    FChart.Frame;
    if s = 5 then Draw;
    deferred := 0;
    for e := 0 to els.Count - 1 do
    begin
      el := els.Objects[e];
      m := maps[e];
      anim := nil;
      if el.Find('animators') is TJSONArray then anim := el.Arrays['animators'];
      if m.Kind = amkDeferred then
      begin
        if anim <> nil then Inc(deferred, anim.Items[s].AsInteger);
        Continue;
      end;
      if m.Kind <> amkModel then Continue;
      p := FChart.AnimFindProxy(m.Series, m.Index, m.Role);
      if p = nil then
      begin
        if s = 0 then
          Miss(Format('%s: no proxy for %s (%d,%d,%s)', [name, el.Strings['id'],
            m.Series, m.Index, m.Role]));
        Continue;
      end;
      Inc(FCompared);
      if anim <> nil then
        if p.AnimatorCount <> anim.Items[s].AsInteger then
          Miss(Format('%s t=%s %s: %d animators here, %d upstream', [name,
            samples.Items[s].AsString, el.Strings['id'], p.AnimatorCount,
            anim.Items[s].AsInteger]), name + el.Strings['id'] + 'anim');
      if s = 0 then SetLength(got0[e], Length(p.Final));
      { every key the port holds: tracked ones against upstream, the rest
        held still at the layout's value }
      if el.Find('track') is TJSONObject then track := el.Objects['track']
      else track := nil;
      for k := 0 to High(p.Final) do
      begin
        key := p.Final[k].Key;
        if not ProxyNums(p, key, got) then Continue;
        if s = 0 then got0[e][k] := Copy(got, 0, Length(got));
        gotF := FinalNums(p, key);
        { a key upstream's oracle does not record (strokePercent) says
          nothing either way }
        if not Recorded(key) then Continue;
        if (track = nil) or (track.Find(key) = nil) then
        begin
          { not animated upstream -- unless it rests at its own final value,
            which a forced track writes back unchanged }
          if Length(gotF) = Length(got) then
            for j := 0 to High(got) do
              if not SameBits(got[j], gotF[j]) then
              begin
                Miss(Format('%s t=%s %s: %s moves here (%s, rests %s), not upstream',
                  [name, samples.Items[s].AsString, el.Strings['id'], key,
                   Fmt(got[j]), Fmt(gotF[j])]), name + el.Strings['id'] + key + 'still');
                Break;
              end;
          Continue;
        end;
        if not NumsOf(track.Arrays[key].Items[s], up) then Continue;
        if not NumsOf(el.Objects['final'].Find(key), upF) then Continue;
        if not NumsOf(track.Arrays[key].Items[0], up0) then Continue;
        if (Length(up) <> Length(got)) or (Length(upF) <> Length(gotF)) then
        begin
          Miss(Format('%s t=%s %s: %s has %d numbers here, %d upstream',
            [name, samples.Items[s].AsString, el.Strings['id'], key,
             Length(got), Length(up)]));
          Continue;
        end;
        for j := 0 to High(got) do
        begin
          exact := SameBits(gotF[j], upF[j]);
          if exact then
          begin
            if not SameBits(got[j], up[j]) then
              Miss(Format('%s t=%s %s: %s[%d] %s here, %s upstream',
                [name, samples.Items[s].AsString, el.Strings['id'], key, j,
                 Fmt(got[j]), Fmt(up[j])]), name + el.Strings['id'] + key);
          end
          else if (m.Role <> 'candle') or not SameBits(up0[j], upF[j]) then
            { A DIFFERENT FINAL VALUE IS A DIFFERENT ANSWER, except where the
              port's layout is known to differ and the number does not move }
            Miss(Format('%s t=%s %s: %s[%d] rests at %s here, %s upstream',
              [name, samples.Items[s].AsString, el.Strings['id'], key, j,
               Fmt(gotF[j]), Fmt(upF[j])]), name + el.Strings['id'] + key + 'final')
          else
          begin
            { A CANDLE'S ACROSS COORDINATE: upstream sub-pixel-optimises the
              body's sides and the port does not -- neither moves, which is
              what the weight (nought throughout) says }
            Inc(FWeighed);
            if upF[j] = up0[j] then wu := 0 else wu := (up[j] - up0[j]) / (upF[j] - up0[j]);
            if gotF[j] = got0[e][k][j] then wp := 0
            else wp := (got[j] - got0[e][k][j]) / (gotF[j] - got0[e][k][j]);
            if Abs(wu - wp) > 1e-9 then
              Miss(Format('%s t=%s %s: %s[%d] weight %s here, %s upstream',
                [name, samples.Items[s].AsString, el.Strings['id'], key, j,
                 Fmt(wp), Fmt(wu)]), name + el.Strings['id'] + key + 'w');
          end;
        end;
      end;
    end;
    want := clips.Items[s].AsInteger - deferred;
    if FChart.AnimClipCount <> want then
      Miss(Format('%s t=%s: %d clips here, %d upstream less %d deferred',
        [name, samples.Items[s].AsString, FChart.AnimClipCount,
         clips.Items[s].AsInteger, deferred]), name + 'clips');
  end;

  { AT REST. Every key at (to - from) * 1 + from, from being what the first
    step wrote; and once more drawn, the frame is the static list wherever a
    proxy rests on the layout. }
  if FChart.AnimClipCount = 0 then
  begin
    if FChart.AnimLive then Miss(name + ': still live with no clip');
    for k := 0 to FChart.AnimProxyCount - 1 do
    begin
      p := FChart.AnimProxy(k);
      for j := 0 to High(p.Final) do
      begin
        if not ProxyNums(p, p.Final[j].Key, got) then Continue;
        gotF := FinalNums(p, p.Final[j].Key);
        if Length(gotF) <> Length(got) then Continue;
        for n := 0 to High(got) do
          if not SameBits(got[n], gotF[n]) then
            { off the layout: only by the final step's own arithmetic }
            if not SameBits(got[n], (gotF[n] - got[n]) * 1 + got[n]) then
              Miss(Format('%s: %s.%s rests at %s, the layout says %s', [name,
                p.Role, p.Final[j].Key, Fmt(got[n]), Fmt(gotF[n])]));
      end;
    end;
    Draw;
    lst := FChart.List;
    frm := FChart.Frame;
    if (lst <> nil) and (frm <> nil) then
    begin
      if lst.Count <> frm.Count then
        Miss(Format('%s: a frame of %d, a list of %d', [name, frm.Count, lst.Count]))
      else
        for k := 0 to lst.Count - 1 do
        begin
          a := lst.Element(k);
          b := frm.Element(k);
          p := nil;
          if a.Anim.Role <> carNone then
          begin
            if a.Anim.Role in [carLineRun, carLineArea] then
              p := FChart.AnimFindProxy(a.Anim.Series, -1, TyChartAnimProxyRole(a.Anim.Role))
            else
              p := FChart.AnimFindProxy(a.Anim.Series, a.Anim.Index,
                TyChartAnimProxyRole(a.Anim.Role));
          end;
          if ((p = nil) or p.AtFinal) and not SameShape(a, b) then
            Miss(Format('%s: element %d at rest is not the static one', [name, k]));
        end;
    end;
  end;
end;

procedure TAdvChartAnimEnterTest.TestEnterTimelinesAsUpstream;
var
  cases: TJSONArray;
  cs: TJSONObject;
  c, ran: Integer;
  kind: string;
begin
  cases := Fixture.Arrays['cases'];
  ran := 0;
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    kind := cs.Strings['kind'];
    if (kind <> 'enter') and (kind <> 'threshold') then Continue;
    { the ripples loop for ever: AN4's }
    if cs.Strings['chart'] = 'effectScatter' then Continue;
    RunCase(cs);
    Inc(ran);
  end;
  AssertTrue(Format('%d mismatches over %d element samples (%d weighed):%s',
    [FBad, FCompared, FWeighed, FReport]), FBad = 0);
  AssertTrue(Format('only %d cases ran', [ran]), ran >= 55);
  AssertTrue(Format('only %d element samples', [FCompared]), FCompared >= 3000);
end;

{ ==================== the policy ==================== }

const
  cBars = '{"xAxis":{"type":"category","data":["A","B","C"]},"yAxis":{"type":"value"},'
    + '"series":[{"type":"bar","data":[10,30,20]}]}';

{ A HEADLESS RENDER DRAWS THE FINISHED PICTURE: camAuto animates only a
  window's paint, so RenderTo -- an export, the designer, every test of a
  static layout -- never sees a frame. The option stays pending for the
  window. }
procedure TAdvChartAnimEnterTest.TestHeadlessRenderDoesNotAnimateByDefault;
begin
  NewChart(camAuto);
  Load(cBars);
  AssertEquals('no proxies', 0, FChart.AnimProxyCount);
  AssertEquals('no clips', 0, FChart.AnimClipCount);
  AssertFalse('not live', FChart.AnimLive);
  { and the same chart in camAlways animates the very same option }
  NewChart(camAlways);
  Load(cBars);
  AssertEquals('three bars armed', 3, FChart.AnimClipCount);
  AssertTrue('live', FChart.AnimLive);
end;

procedure TAdvChartAnimEnterTest.TestOffModeAndOptionOff;
begin
  NewChart(camOff);
  Load(cBars);
  AssertEquals('camOff: no clips', 0, FChart.AnimClipCount);
  AssertFalse('camOff: not live', FChart.AnimLive);
  NewChart(camAlways);
  Load('{"animation":false,"xAxis":{"type":"category","data":["A","B","C"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","data":[10,30,20]}]}');
  AssertEquals('animation: false -- no clips', 0, FChart.AnimClipCount);
  AssertFalse('animation: false -- not live', FChart.AnimLive);
  { switched off mid-flight, the picture finishes }
  NewChart(camAlways);
  Load(cBars);
  AssertTrue('live', FChart.AnimLive);
  FChart.AnimationMode := camOff;
  AssertFalse('off: no longer live', FChart.AnimLive);
  AssertEquals('off: no clips', 0, FChart.AnimProxyCount);
end;

{ THE SERIES MOVE IN THE DYNAMIC LAYER: at t = 0 a bar has no height, so the
  pixel in the middle of the tallest bar is the ground; once the clock has
  run out it is the bar -- and the static list held the finished bar all
  along. }
procedure TAdvChartAnimEnterTest.TestSeriesMoveInTheDynamicLayer;
var
  lst: TTyPaintList;
  i, cx, cy: Integer;
  e: TTyChartElement;
  r: TTyRectF;
  px0, px1: TBGRAPixel;
begin
  NewChart(camAlways);
  Load(cBars);
  lst := FChart.List;
  r := TyRectF(0, 0, 0, 0);
  for i := 0 to lst.Count - 1 do
  begin
    e := lst.Element(i);
    if (e.Anim.Role = carBar) and (e.Anim.Index = 1) then r := TyShapeBounds(e.Shape);
  end;
  AssertTrue('the static list holds the finished bar', r.Bottom - r.Top > 50);
  { a third of the way down, off any split line }
  cx := Round((r.Left + r.Right) / 2);
  cy := Round(r.Top + (r.Bottom - r.Top) * 0.3);
  px0 := Draw.GetPixel(cx, cy);
  FChart.AnimTick(T0 + 2000);
  AssertFalse('at rest', FChart.AnimLive);
  px1 := Draw.GetPixel(cx, cy);
  AssertFalse('at rest the bar is there',
    (px1.red > 240) and (px1.green > 240) and (px1.blue > 240));
  AssertTrue(Format('at t = 0 it is not (%d,%d,%d against %d,%d,%d)',
    [px0.red, px0.green, px0.blue, px1.red, px1.green, px1.blue]),
    Abs(px0.red - px1.red) + Abs(px0.green - px1.green) + Abs(px0.blue - px1.blue) > 60);
end;

{ A BAR'S 'top' LABEL RIDES THE BAR: half way, the label stands over the bar's
  current top, not its final one; and it is half faded in. }
procedure TAdvChartAnimEnterTest.TestABarLabelRidesItsBar;
var
  frm, lst: TTyPaintList;
  i: Integer;
  e, bar, lbl, barS, lblS: TTyChartElement;
begin
  NewChart(camAlways);
  Load('{"xAxis":{"type":"category","data":["A","B","C"]},"yAxis":{"type":"value"},'
    + '"series":[{"type":"bar","animationEasing":"linear","label":{"show":true,"position":"top"},'
    + '"data":[10,30,20]}]}');
  FChart.AnimTick(T0 + 500);
  lst := FChart.List;
  frm := FChart.Frame;
  bar := Default(TTyChartElement);
  lbl := Default(TTyChartElement);
  barS := bar;
  lblS := lbl;
  for i := 0 to frm.Count - 1 do
  begin
    e := frm.Element(i);
    if (e.Anim.Index = 1) and (e.Anim.Role = carBar) then
    begin
      bar := e;
      barS := lst.Element(i);
    end;
    if (e.Anim.Index = 1) and (e.Anim.Role = carLabel) then
    begin
      lbl := e;
      lblS := lst.Element(i);
    end;
  end;
  AssertTrue('the bar is found', bar.Anim.Role = carBar);
  AssertTrue('the label is found', lbl.Anim.Role = carLabel);
  AssertEquals('half the bar', (barS.Shape.Bounds.Bottom - barS.Shape.Bounds.Top) / 2,
    bar.Shape.Bounds.Bottom - bar.Shape.Bounds.Top, 1e-9);
  AssertEquals('the label moved with the top',
    bar.Shape.Bounds.Top - barS.Shape.Bounds.Top, lbl.Caption.Y - lblS.Caption.Y, 1e-9);
  AssertEquals('half faded in', lblS.Style.Alpha * 0.5, lbl.Style.Alpha, 1e-9);
end;

{ A HEATMAP'S CELLS NEVER MOVE: nothing of it is armed, labels or not --
  well, its labels fade (upstream's LabelManager), its cells do not. }
procedure TAdvChartAnimEnterTest.TestHeatmapCellsNeverAnimate;
var
  i: Integer;
begin
  NewChart(camAlways);
  Load('{"xAxis":{"type":"category","data":["x0","x1"]},"yAxis":{"type":"category",'
    + '"data":["y0","y1"]},"visualMap":{"min":0,"max":10,"show":false},'
    + '"series":[{"type":"heatmap","label":{"show":true},"data":[[0,0,1],[0,1,5],[1,0,3],[1,1,7]]}]}');
  for i := 0 to FChart.AnimProxyCount - 1 do
    AssertEquals('only labels animate on a heatmap', 'label', FChart.AnimProxy(i).Role);
  AssertEquals('four labels fade in', 4, FChart.AnimProxyCount);
end;

{ A NEW OPTION ENTERS AGAIN; A RESIZE SNAPS. }
procedure TAdvChartAnimEnterTest.TestANewOptionAnimatesAgainAndAResizeSnaps;
begin
  NewChart(camAlways);
  Load(cBars);
  AssertTrue('live', FChart.AnimLive);
  FChart.SetBounds(0, 0, cW - 20, cH);
  Draw;
  AssertFalse('a resize finishes it', FChart.AnimLive);
  AssertEquals('and drops the proxies', 0, FChart.AnimProxyCount);
  FChart.Option := '{"xAxis":{"type":"category","data":["A","B"]},"yAxis":{"type":"value"},'
    + '"series":[{"type":"bar","data":[5,6]}]}';
  Draw;
  AssertTrue('the next option enters', FChart.AnimLive);
  AssertEquals('two bars', 2, FChart.AnimClipCount);
end;

{ UPSTREAM'S QUIRK, KEPT: `clip: false` widens the line's clip rect after
  initProps -- and the clip animation is forced (it has a done), so every
  key has a track and the first frame writes the unwidened y and height
  back. Animated, the line ends clipped to the grid; with `animation: false`
  it keeps the widening. (Probed on the real build: animated {y 64,
  height 157} at rest; not animated {y -238, height 761}.) }
procedure TAdvChartAnimEnterTest.TestClipFalseLosesItsWideningWhenAnimated;
const
  cOpt = '"xAxis":{"type":"category","data":["A","B","C"]},'
    + '"yAxis":{"type":"value","max":10},'
    + '"series":[{"type":"line","clip":false,"data":[1,20,5]}]}';
var
  p: TTyChartAnimProxy;
  lst, frm: TTyPaintList;
  i: Integer;
  e, f: TTyChartElement;
  found: Boolean;
begin
  NewChart(camAlways);
  Load('{' + cOpt);
  p := FChart.AnimFindProxy(0, -1, 'lineClip');
  AssertNotNull('the clip proxy', p);
  FChart.AnimTick(T0 + 1500);
  AssertFalse('at rest', FChart.AnimLive);
  Draw;
  lst := FChart.List;
  frm := FChart.Frame;
  found := False;
  for i := 0 to lst.Count - 1 do
  begin
    e := lst.Element(i);
    if e.Anim.Role <> carLineRun then Continue;
    f := frm.Element(i);
    found := True;
    AssertEquals('the static rect is the widened one, y', e.Anim.G[1] - e.Anim.G[4],
      e.ClipRect.Top, 0);
    AssertEquals('the frame rests on the unwidened y', e.Anim.G[1], f.ClipRect.Top, 0);
    AssertEquals('and the unwidened height', e.Anim.G[1] + e.Anim.G[3],
      f.ClipRect.Bottom, 0);
    AssertEquals('the proxy at y', e.Anim.G[1], p.Num('shape.y'), 0);
    AssertEquals('the proxy at height', e.Anim.G[3], p.Num('shape.height'), 0);
  end;
  AssertTrue('a run', found);
  { NOT ANIMATED: the widening stays }
  NewChart(camAlways);
  Load('{"animation":false,' + cOpt);
  lst := FChart.List;
  frm := FChart.Frame;
  for i := 0 to lst.Count - 1 do
  begin
    e := lst.Element(i);
    if e.Anim.Role <> carLineRun then Continue;
    f := frm.Element(i);
    AssertEquals('off: the frame keeps the widened y', e.ClipRect.Top, f.ClipRect.Top, 0);
    AssertEquals('off: and its height', e.ClipRect.Bottom, f.ClipRect.Bottom, 0);
  end;
end;

initialization
  RegisterTest(TAdvChartAnimEnterTest);
finalization
  FreeAndNil(GFixture);
end.
