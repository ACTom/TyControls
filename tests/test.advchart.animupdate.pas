unit test.advchart.animupdate;
{$mode objfpc}{$H+}
{ THE UPDATE AND LEAVE ANIMATIONS ON THE REAL CONTROL, held to upstream.
  [Batch 90, AN3]

  Two fixtures, both from the real ECharts 6.1 build under the hand-driven
  clock of tools/advchart-oracle/animation.js:

    advchart-animation.json, the 11 `update` cases: the first option at
    T0, run out, the second at T1 = T0 + 10000, recorded at T1 + 0, 1, 16,
    50, 100, 250, 500, 750, 999, 1000, 1001 and 1500 ms. Upstream merged the
    second; the control's Option is notMerge, so
    advchart-animation-update.json's `twins` hold each case's merged option
    and the clip counts of setting it whole with notMerge -- guarded there:
    every series element records exactly as the merge run does, and no
    component animates (the axes are new views under notMerge: no
    groupTransition);

    advchart-animation-update.json's own `cases`, every option set whole:
    a shift with a delay function (the NEW row's delay), a third option in
    the middle of a tween (from where it is), a series removed (gone at
    once), a named series moving to another index (its view goes with the
    name), scatter (moves, grows, leaves, enters), a line past the 3000 px
    cutoff, an area line with a point added (point and base from the old
    axes), a null filled in, a wider pen (the clip at enter timing), a
    'scale' pie.

  Each case runs on a TTyAdvanceChart (zrender's SSR text measure, 400 x
  300, camAlways): the first option rendered at T0 and run out, the second
  set and rendered at T1 (the render arms it and takes the synchronous first
  step), AnimTick to every sample. Every series element upstream animates
  is mapped to the proxy that stands for it -- a leaving one to its GHOST,
  found by its old row -- and compared:

    - present exactly where upstream's is (a ghost until its fade ends);
    - every tracked key BIT FOR BIT, final value included, and every key
      upstream tracks must be one the proxy holds; the proxy's other keys
      hold still;
    - the proxy's animators against the sum of its elements';
    - the clips against upstream's, all of them [Batch 92: a label's move
      from its old layout, a guide line's points and a value counting are
      modelled -- nothing is subtracted]; the words a count writes as
      strings;
    - the frame holds the list plus one silent element per live ghost;
    - at rest: no ghost, every key at (to - from) * 1 + from, and the frame
      the static list wherever the proxy rests on the layout. }
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
  TAuProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    function Frame: TTyPaintList;
  end;

  TAuKind = (aukStatic, aukModel, aukDeferred, aukUnknown);
  TAuMap = record
    Kind: TAuKind;
    Series, Index: Integer;
    Role: string;
    Ghost: Boolean;
  end;

  TAdvChartAnimUpdateTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TAuProbe;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport: string;
    FSeen: TStringList;
    procedure Miss(const AWhere: string; const AOnce: string = '');
    function HIdx30(ADataIndex: Integer; AHasIndex: Boolean): Double;
    function HIdx50(ADataIndex: Integer; AHasIndex: Boolean): Double;
    procedure NewChart(AMode: TTyChartAnimationMode);
    procedure Load(const AOption: string);
    procedure SetNext(const AOption: string);
    function Draw: TBGRABitmap;
    procedure RunCase(const AName: string; AOption, ANext, AMid: TJSONData;
      AClips, AEls: TJSONArray);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestUpdateTimelinesAsUpstream;
    procedure TestAn4UpdateTimelinesAsUpstream;
    procedure TestDataDiffAsUpstream;
    procedure TestLineBoundingDiff;
    procedure TestAGhostIsDrawnAndSilent;
    procedure TestAResizeEndsAnUpdate;
    procedure TestHeadlessUpdateWaitsForTheWindow;
  end;

implementation

const
  cW = 400;
  cH = 300;

var
  GMain: TJSONData = nil;
  GExtra: TJSONData = nil;
  GAn4: TJSONData = nil;

function LoadJson(const AName: string): TJSONData;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName);
    Result := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
end;

function Main: TJSONObject;
begin
  if GMain = nil then GMain := LoadJson('advchart-animation.json');
  Result := TJSONObject(GMain);
end;

function Extra: TJSONObject;
begin
  if GExtra = nil then GExtra := LoadJson('advchart-animation-update.json');
  Result := TJSONObject(GExtra);
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

function ValNums(const V: TTyAnimValue; out ANums: TTyDoubleArray): Boolean;
begin
  ANums := nil;
  case V.Kind of
    avkNumber, avkBool:
      begin
        SetLength(ANums, 1);
        ANums[0] := V.Num;
        Result := True;
      end;
    avkArray:
      begin
        ANums := Copy(V.Arr, 0, Length(V.Arr));
        Result := True;
      end;
  else
    Result := False;
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

function OptionText(AData: TJSONData): string;
var c: TJSONData;
begin
  c := AData.Clone;
  try
    ConvertFns(c);
    Result := c.AsJSON;
  finally
    c.Free;
  end;
end;

function An4: TJSONObject;
begin
  if GAn4 = nil then GAn4 := LoadJson('advchart-animation-an4.json');
  Result := TJSONObject(GAn4);
end;

function T0: Double;
begin
  Result := Main.Objects['clock'].Floats['T0'];
end;

function T1: Double;
begin
  Result := T0 + Main.Objects['clock'].Floats['T1Offset'];
end;

{ ==================== the probe ==================== }

function TAuProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TAuProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TAuProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TAuProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

{ ==================== mapping upstream's elements ==================== }

function Tracks(AEl: TJSONObject; const AKey: string): Boolean;
var d: TJSONData;
begin
  d := AEl.Find('track');
  Result := (d is TJSONObject) and (TJSONObject(d).Find(AKey) <> nil);
end;

function HasLeave(AEl: TJSONObject): Boolean;
var
  d: TJSONData;
  i: Integer;
begin
  Result := False;
  d := AEl.Find('scopes');
  if not (d is TJSONArray) then Exit;
  for i := 0 to d.Count - 1 do
    if d.Items[i].AsString = 'leave' then Exit(True);
end;

{ the dataIndex of the element at id AId, -1 for none }
function DataIndexOf(AEls: TJSONArray; const AId: string): Integer;
var
  i: Integer;
  e: TJSONObject;
  d: TJSONData;
begin
  for i := 0 to AEls.Count - 1 do
  begin
    e := AEls.Objects[i];
    if e.Strings['id'] <> AId then Continue;
    d := e.Find('dataIndex');
    if (d <> nil) and (d.JSONType = jtNumber) then Exit(d.AsInteger);
    Exit(-1);
  end;
  Result := -1;
end;

function MapElement(AEls: TJSONArray; AEl: TJSONObject): TAuMap;
var
  id, owner, path, typ, stype, base, host: string;
  p, k, di: Integer;
  hasTrack, hasAnim: Boolean;
  d, a: TJSONData;
  parts: TStringList;
begin
  Result := Default(TAuMap);
  Result.Kind := aukStatic;
  id := AEl.Strings['id'];
  owner := AEl.Strings['owner'];
  typ := AEl.Strings['type'];
  d := AEl.Find('track');
  hasTrack := (d <> nil) and (d.JSONType = jtObject) and (d.Count > 0);
  hasAnim := False;
  a := AEl.Find('animators');
  if (a <> nil) and (a.JSONType = jtArray) then
    for k := 0 to a.Count - 1 do
      if a.Items[k].AsInteger > 0 then hasAnim := True;
  if not (hasTrack or hasAnim) then Exit;
  { a component: the merge run's axes, which notMerge never animates (the
    twins' clips are notMerge's) }
  if Pos('series', owner) <> 1 then Exit;
  di := -1;
  d := AEl.Find('dataIndex');
  if (d <> nil) and (d.JSONType = jtNumber) then di := d.AsInteger;
  Result.Kind := aukUnknown;
  p := Pos(':', owner);
  if p = 0 then Exit;
  Result.Series := StrToIntDef(Copy(owner, 7, p - 7), -1);
  stype := Copy(owner, p + 1, MaxInt);
  path := Copy(id, Pos('/', id) + 1, MaxInt);
  base := path;
  if Pos('#', base) > 0 then base := Copy(base, 1, Pos('#', base) - 1);
  host := Copy(id, 1, Pos('/', id)) + base;
  Result.Ghost := HasLeave(AEl);
  parts := TStringList.Create;
  try
    parts.Delimiter := '.';
    parts.StrictDelimiter := True;
    parts.DelimitedText := base;
    if (Pos('#label', id) > 0) or (Pos('#guide', id) > 0) then
    begin
      Result.Kind := aukModel;
      if Pos('#label', id) > 0 then Result.Role := 'label' else Result.Role := 'guide';
      Result.Index := DataIndexOf(AEls, host);
      Exit;
    end;
    if stype = 'bar' then
    begin
      if typ = 'rect' then
      begin
        Result.Kind := aukModel;
        Result.Role := 'bar';
        Result.Index := di;
      end;
    end
    else if stype = 'pie' then
    begin
      Result.Kind := aukModel;
      Result.Role := 'sector';
      Result.Index := di;
    end
    else if stype = 'line' then
    begin
      if Pos('#clip', id) > 0 then
      begin
        Result.Kind := aukModel;
        Result.Role := 'lineClip';
        Result.Index := -1;
      end
      else if typ = 'ec-polyline' then
      begin
        Result.Kind := aukModel;
        Result.Role := 'linePoly';
        Result.Index := -1;
      end
      else if typ = 'ec-polygon' then
      begin
        Result.Kind := aukModel;
        Result.Role := 'lineArea';
        Result.Index := -1;
      end
      else if (typ = 'group') and (di >= 0) then
      begin
        Result.Kind := aukModel;
        Result.Role := 'lineSymbol';
        Result.Index := di;
      end
      else if (typ = 'path') and (di >= 0) and Result.Ghost then
      begin
        Result.Kind := aukModel;
        Result.Role := 'lineSymbol';
        Result.Index := di;
      end;
    end
    else if stype = 'scatter' then
    begin
      if di >= 0 then
      begin
        Result.Kind := aukModel;
        Result.Role := 'symbol';
        Result.Index := di;
      end;
    end
    else if stype = 'effectScatter' then
    begin
      { 0.<row> the group, 0.<row>.0.0 the symbol's path -- one proxy;
        0.<row>.1.<i> ripple i [Batch 92] }
      if parts.Count >= 2 then
      begin
        Result.Kind := aukModel;
        Result.Index := StrToIntDef(parts[1], -1);
        if (parts.Count >= 4) and (parts[2] = '1') then Result.Role := 'ripple' + parts[3]
        else Result.Role := 'effectSymbol';
      end;
    end
    else if stype = 'gauge' then
    begin
      Result.Kind := aukModel;
      Result.Index := di;
      if typ = 'pointer' then Result.Role := 'gaugePointer'
      else if typ = 'sector' then Result.Role := 'gaugeProgress'
      else if (typ = 'text') and (parts.Count >= 3) then
      begin
        Result.Role := 'gaugeDetail';
        Result.Index := StrToIntDef(parts[1], -1);
      end
      else Result.Kind := aukUnknown;
    end;
  finally
    parts.Free;
  end;
end;

{ which proxy holds a key upstream tracks on an element of role ARole: the
  polygon's points are its polyline's array, `__points` without a step is
  `points` }
procedure KeyTarget(const ARole, AKey: string; out ARoleOut, AKeyOut: string);
begin
  ARoleOut := ARole;
  AKeyOut := AKey;
  if (ARole = 'linePoly') and (AKey = 'shape.__points') then AKeyOut := 'shape.points'
  else if (ARole = 'lineArea') and (AKey = 'shape.points') then ARoleOut := 'linePoly';
end;

{ ==================== plumbing ==================== }

function TAdvChartAnimUpdateTest.HIdx30(ADataIndex: Integer; AHasIndex: Boolean): Double;
begin
  { (idx) => idx * 30; undefined * 30 is not a number, and `delay || 0` }
  if AHasIndex then Result := ADataIndex * 30 else Result := NaN;
end;

function TAdvChartAnimUpdateTest.HIdx50(ADataIndex: Integer; AHasIndex: Boolean): Double;
begin
  if AHasIndex then Result := ADataIndex * 50 else Result := NaN;
end;

procedure TAdvChartAnimUpdateTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  TyChartRegisterAnimTiming('idx*30', @HIdx30);
  TyChartRegisterAnimTiming('idx*50', @HIdx50);
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
  FReport := '';
end;

procedure TAdvChartAnimUpdateTest.TearDown;
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

procedure TAdvChartAnimUpdateTest.Miss(const AWhere: string; const AOnce: string);
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

procedure TAdvChartAnimUpdateTest.NewChart(AMode: TTyChartAnimationMode);
begin
  FreeAndNil(FChart);
  FChart := TAuProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := AMode;
  FChart.AnimNow := T0;
end;

function TAdvChartAnimUpdateTest.Draw: TBGRABitmap;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
  Result := FBmp;
end;

procedure TAdvChartAnimUpdateTest.Load(const AOption: string);
begin
  FChart.Option := AOption;
  AssertEquals('the option parses', '', FChart.OptionError);
  FChart.SetBounds(0, 0, cW, cH);
  Draw;
end;

procedure TAdvChartAnimUpdateTest.SetNext(const AOption: string);
begin
  FChart.Option := AOption;
  AssertEquals('the next option parses', '', FChart.OptionError);
  Draw;
end;

{ ==================== the timelines ==================== }

type
  TAuEntry = record
    Map: TAuMap;
    Els: array of Integer;
  end;

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
    and (Length(A.Shape.Points) = Length(B.Shape.Points))
    and (Length(A.Shape.Cmds) = Length(B.Shape.Cmds))
    and SameBits(A.Style.Alpha, B.Style.Alpha)
    and (A.HasClip = B.HasClip)
    and SameBits(A.ClipRect.Top, B.ClipRect.Top)
    and SameBits(A.ClipRect.Bottom, B.ClipRect.Bottom)
    and (A.Caption.Text = B.Caption.Text);
  if not Result then Exit;
  for i := 0 to High(A.Shape.Points) do
    if not (SameBits(A.Shape.Points[i].X, B.Shape.Points[i].X)
      and SameBits(A.Shape.Points[i].Y, B.Shape.Points[i].Y)) then Exit(False);
end;

function PresentAt(AEl: TJSONObject; ASample: Integer): Boolean;
var
  d: TJSONData;
  i: Integer;
begin
  d := AEl.Find('present');
  if (d = nil) or (d.JSONType <> jtArray) then Exit(True);
  for i := 0 to d.Count - 1 do
    if d.Items[i].AsInteger = ASample then Exit(True);
  Result := False;
end;

procedure TAdvChartAnimUpdateTest.RunCase(const AName: string; AOption, ANext,
  AMid: TJSONData; AClips, AEls: TJSONArray);
var
  samples, anim, steps: TJSONArray;
  maps: array of TAuMap;
  entries: array of TAuEntry;
  e, s, k, j, n, ti, want, sumAnim, live, ghosts: Integer;
  el, track: TJSONObject;
  m: TAuMap;
  p, tp: TTyChartAnimProxy;
  key, tRole, tKey, eid: string;
  up, upF, got, gotF: TTyDoubleArray;
  tracked: TStringList;
  present, upPresent: Boolean;
  start, t: Double;
  upT: TJSONData;
  lst, frm: TTyPaintList;
  a, b: TTyChartElement;

  function ProxyOf(const AM: TAuMap; const ARole: string): TTyChartAnimProxy;
  begin
    if AM.Ghost then Result := FChart.AnimFindGhost(AM.Series, AM.Index, ARole)
    else Result := FChart.AnimFindProxy(AM.Series, AM.Index, ARole);
  end;

begin
  NewChart(camAlways);
  Load(OptionText(AOption));
  { THE FIRST RENDER RUN OUT on the oracle's own frames, every 250 ms from
    16: a looping clip restarts at whatever frame passes its end, so the
    ripples' phase -- to the bit, at the epoch's ulp -- follows the frames
    [Batch 92] }
  t := 16;
  while t <= 5000 do
  begin
    FChart.AnimTick(T0 + t);
    t := t + 250;
  end;
  if FChart.AnimClipCount <> FChart.AnimLoopClipCount then
    Miss(AName + ': the first render did not settle');
  FChart.AnimNow := T1;
  SetNext(OptionText(ANext));
  start := T1;
  if AMid <> nil then
  begin
    steps := TJSONObject(AMid).Arrays['steps'];
    for k := 0 to steps.Count - 1 do FChart.AnimTick(T1 + steps.Items[k].AsFloat);
    start := T1 + steps.Items[steps.Count - 1].AsFloat;
    FChart.AnimNow := start;
    SetNext(OptionText(TJSONObject(AMid).Elements['next']));
  end;

  samples := Extra.Arrays['samplesMs'];
  SetLength(maps, AEls.Count);
  entries := nil;
  for e := 0 to AEls.Count - 1 do
  begin
    maps[e] := MapElement(AEls, AEls.Objects[e]);
    if maps[e].Kind = aukUnknown then
      Miss(Format('%s: %s is not mapped', [AName, AEls.Objects[e].Strings['id']]));
    if maps[e].Kind <> aukModel then Continue;
    { one entry per proxy: a scatter symbol's group and path share one }
    n := -1;
    for j := 0 to High(entries) do
      if (entries[j].Map.Series = maps[e].Series) and (entries[j].Map.Index = maps[e].Index)
        and (entries[j].Map.Role = maps[e].Role) and (entries[j].Map.Ghost = maps[e].Ghost) then
        n := j;
    if n < 0 then
    begin
      n := Length(entries);
      SetLength(entries, n + 1);
      entries[n].Map := maps[e];
    end;
    SetLength(entries[n].Els, Length(entries[n].Els) + 1);
    entries[n].Els[High(entries[n].Els)] := e;
  end;

  tracked := TStringList.Create;
  try
    for s := 0 to samples.Count - 1 do
    begin
      if s > 0 then FChart.AnimTick(start + samples.Items[s].AsFloat);
      frm := FChart.Frame;
      lst := FChart.List;
      ghosts := 0;
      for j := 0 to High(entries) do
      begin
        m := entries[j].Map;
        p := ProxyOf(m, m.Role);
        present := p <> nil;
        upPresent := False;
        sumAnim := 0;
        for k := 0 to High(entries[j].Els) do
        begin
          el := AEls.Objects[entries[j].Els[k]];
          if PresentAt(el, s) then upPresent := True;
          if el.Find('animators') is TJSONArray then
            Inc(sumAnim, el.Arrays['animators'].Items[s].AsInteger);
        end;
        eid := AEls.Objects[entries[j].Els[0]].Strings['id'];
        if m.Ghost then
        begin
          if present <> upPresent then
            Miss(Format('%s t=%s %s: present here %s, upstream %s', [AName,
              samples.Items[s].AsString, eid, BoolToStr(present, True),
              BoolToStr(upPresent, True)]), AName + eid + 'present');
          if present then Inc(ghosts);
        end
        else if not present then
        begin
          Miss(Format('%s t=%s: no proxy for %s (%d,%d,%s)', [AName,
            samples.Items[s].AsString, eid, m.Series, m.Index, m.Role]), AName + eid + 'none');
          Continue;
        end;
        if (p = nil) or not upPresent then Continue;
        Inc(FCompared);
        if p.AnimatorCount <> sumAnim then
          Miss(Format('%s t=%s %s: %d animators here, %d upstream', [AName,
            samples.Items[s].AsString, eid, p.AnimatorCount, sumAnim]), AName + eid + 'anim');
        { every tracked key, bit for bit }
        tracked.Clear;
        for k := 0 to High(entries[j].Els) do
        begin
          el := AEls.Objects[entries[j].Els[k]];
          if not (el.Find('track') is TJSONObject) then Continue;
          track := el.Objects['track'];
          for ti := 0 to track.Count - 1 do
          begin
            key := track.Names[ti];
            KeyTarget(m.Role, key, tRole, tKey);
            if tRole = m.Role then
            begin
              tp := p;
              tracked.Add(tKey);
            end
            else
              tp := ProxyOf(m, tRole);
            if tp = nil then
            begin
              Miss(Format('%s: no %s proxy for %s', [AName, tRole, eid]), AName + eid + tRole);
              Continue;
            end;
            { THE WORDS A COUNT WRITES, as strings [Batch 92] }
            if tKey = 'style.text' then
            begin
              upT := track.Arrays[key].Items[s];
              if not tp.HasText then
                Miss(Format('%s t=%s %s: no words counted here', [AName,
                  samples.Items[s].AsString, eid]), AName + eid + 'text0')
              else if (upT.JSONType = jtString) and (tp.Text <> upT.AsString) then
                Miss(Format('%s t=%s %s: "%s" here, "%s" upstream', [AName,
                  samples.Items[s].AsString, eid, tp.Text, upT.AsString]), AName + eid + 'text');
              Continue;
            end;
            if not ValNums(tp.GetAnimProp(tKey), got) then
            begin
              Miss(Format('%s: %s %s is not modelled', [AName, eid, key]), AName + eid + key + 'mod');
              Continue;
            end;
            if not NumsOf(track.Arrays[key].Items[s], up) then Continue;
            if (Length(up) <> Length(got)) then
            begin
              Miss(Format('%s t=%s %s: %s has %d numbers here, %d upstream',
                [AName, samples.Items[s].AsString, eid, key, Length(got), Length(up)]),
                AName + eid + key + 'len');
              Continue;
            end;
            for n := 0 to High(got) do
              if not SameBits(got[n], up[n]) then
              begin
                Miss(Format('%s t=%s %s: %s[%d] %s here, %s upstream',
                  [AName, samples.Items[s].AsString, eid, key, n, Fmt(got[n]),
                   Fmt(up[n])]), AName + eid + key);
                Break;
              end;
            { and where it comes to rest: the layout's value -- a ripple never
              rests, and a tween that set out in flight lands where its own
              final step puts it, `(to - from) * 1 + from` for a `from` no
              layout knows, a unit or two in the last place off (the samples
              above hold it to upstream's, bit for bit) [Batch 92] }
            if (not m.Ghost) and (Pos('ripple', m.Role) <> 1)
              and NumsOf(el.Objects['final'].Find(key), upF)
              and ValNums(tp.FinalOf(tKey), gotF) and (Length(upF) = Length(gotF)) then
              for n := 0 to High(gotF) do
                if not SameBits(gotF[n], upF[n])
                  and not (Abs(gotF[n] - upF[n]) <= 4e-16 * Max(Abs(upF[n]), 1)) then
                begin
                  Miss(Format('%s %s: %s[%d] rests at %s here, %s upstream',
                    [AName, eid, key, n, Fmt(gotF[n]), Fmt(upF[n])]), AName + eid + key + 'final');
                  Break;
                end;
          end;
        end;
        { the proxy's other keys hold still }
        if not m.Ghost then
          for k := 0 to High(p.Final) do
          begin
            key := p.Final[k].Key;
            if tracked.IndexOf(key) >= 0 then Continue;
            if (key = 'style.strokePercent') or (key = 'percent') then Continue;
            if not ValNums(p.GetAnimProp(key), got) then Continue;
            if not ValNums(p.FinalOf(key), gotF) then Continue;
            if Length(got) <> Length(gotF) then Continue;
            for n := 0 to High(got) do
              if not SameBits(got[n], gotF[n]) then
              begin
                Miss(Format('%s t=%s %s: %s moves here (%s, rests %s), not upstream',
                  [AName, samples.Items[s].AsString, eid, key, Fmt(got[n]), Fmt(gotF[n])]),
                  AName + eid + key + 'still');
                Break;
              end;
          end;
      end;
      { the frame: the list, then one element per ghost still leaving }
      live := FChart.AnimGhostCount;
      if live <> ghosts then
        Miss(Format('%s t=%s: %d ghosts here, %d upstream', [AName,
          samples.Items[s].AsString, live, ghosts]), AName + 'ghosts');
      if (lst <> nil) and (frm <> nil) and (frm <> lst) then
        if frm.Count <> lst.Count + live then
          Miss(Format('%s t=%s: a frame of %d for a list of %d and %d ghosts', [AName,
            samples.Items[s].AsString, frm.Count, lst.Count, live]), AName + 'frame');
      want := AClips.Items[s].AsInteger;
      if FChart.AnimClipCount <> want then
        Miss(Format('%s t=%s: %d clips here, %d upstream',
          [AName, samples.Items[s].AsString, FChart.AnimClipCount,
           AClips.Items[s].AsInteger]), AName + 'clips');
    end;
  finally
    tracked.Free;
  end;

  { AT REST }
  if FChart.AnimClipCount = 0 then
  begin
    if FChart.AnimLive then Miss(AName + ': still live with no clip');
    if FChart.AnimGhostCount <> 0 then Miss(AName + ': a ghost outlives its fade');
    for k := 0 to FChart.AnimProxyCount - 1 do
    begin
      p := FChart.AnimProxy(k);
      for j := 0 to High(p.Final) do
      begin
        if not ValNums(p.GetAnimProp(p.Final[j].Key), got) then Continue;
        if not ValNums(p.FinalOf(p.Final[j].Key), gotF) then Continue;
        if Length(gotF) <> Length(got) then
        begin
          Miss(Format('%s: %s.%s rests with %d numbers, the layout has %d', [AName,
            p.Role, p.Final[j].Key, Length(got), Length(gotF)]));
          Continue;
        end;
        for n := 0 to High(got) do
          if not SameBits(got[n], gotF[n]) then
            if not SameBits(got[n], (gotF[n] - got[n]) * 1 + got[n])
              and not (Abs(got[n] - gotF[n]) <= 4e-16 * Max(Abs(gotF[n]), 1)) then
              Miss(Format('%s: %s.%s rests at %s, the layout says %s', [AName,
                p.Role, p.Final[j].Key, Fmt(got[n]), Fmt(gotF[n])]));
      end;
    end;
    Draw;
    lst := FChart.List;
    frm := FChart.Frame;
    if (lst <> nil) and (frm <> nil) then
    begin
      if lst.Count <> frm.Count then
        Miss(Format('%s: a frame of %d, a list of %d', [AName, frm.Count, lst.Count]))
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
          tp := nil;
          if a.Anim.Role in [carLineRun, carLineArea] then
            tp := FChart.AnimFindProxy(a.Anim.Series, -1, 'linePoly');
          if ((p = nil) or p.AtFinal) and ((tp = nil) or tp.AtFinal)
            and not SameShape(a, b) then
            Miss(Format('%s: element %d at rest is not the static one', [AName, k]));
        end;
    end;
  end;
end;

procedure TAdvChartAnimUpdateTest.TestUpdateTimelinesAsUpstream;
var
  twins, cases, mainCases: TJSONArray;
  tw, cs, mc: TJSONObject;
  i, c, ran: Integer;
  mid: TJSONData;
begin
  twins := Extra.Arrays['twins'];
  mainCases := Main.Arrays['cases'];
  ran := 0;
  { THE MAIN FIXTURE'S UPDATE CASES, set whole }
  for i := 0 to twins.Count - 1 do
  begin
    tw := twins.Objects[i];
    AssertTrue(tw.Strings['id'] + ': series as merge', tw.Booleans['seriesSame']);
    AssertTrue(tw.Strings['id'] + ': components still', tw.Booleans['componentsStill']);
    mc := nil;
    for c := 0 to mainCases.Count - 1 do
      if mainCases.Objects[c].Strings['id'] = tw.Strings['id'] then
        mc := mainCases.Objects[c];
    AssertNotNull(tw.Strings['id'] + ' is in the main fixture', mc);
    RunCase(tw.Strings['id'], mc.Elements['option'], tw.Elements['merged'], nil,
      tw.Arrays['clips'], mc.Arrays['elements']);
    Inc(ran);
  end;
  { AND THE SUPPLEMENT'S }
  cases := Extra.Arrays['cases'];
  for i := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[i];
    mid := cs.Find('mid');
    if (mid <> nil) and (mid.JSONType <> jtObject) then mid := nil;
    RunCase(cs.Strings['id'], cs.Elements['option'], cs.Elements['next'], mid,
      cs.Arrays['clips'], cs.Arrays['elements']);
    Inc(ran);
  end;
  AssertTrue(Format('%d mismatches over %d proxy samples:%s', [FBad, FCompared, FReport]),
    FBad = 0);
  AssertTrue(Format('only %d cases ran', [ran]), ran >= 22);
  AssertTrue(Format('only %d proxy samples', [FCompared]), FCompared >= 1400);
end;

{ THE AN4 FIXTURE'S UPDATE CASES [Batch 92], every option set whole: counts
  changed and changed again in flight (the count goes on from the
  interpolated value), a gauge counting down, a pie interrupted (every label
  jumps to its last layout and moves on from there), effectScatter symbols
  moving under running ripples, an end-label line updated (the label stands
  at its end). }
procedure TAdvChartAnimUpdateTest.TestAn4UpdateTimelinesAsUpstream;
var
  cases: TJSONArray;
  cs: TJSONObject;
  i, ran: Integer;
  mid: TJSONData;
begin
  AssertEquals('the same samples', Extra.Arrays['samplesMs'].AsJSON,
    An4.Arrays['samplesMs'].AsJSON);
  cases := An4.Arrays['cases'];
  ran := 0;
  for i := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[i];
    if cs.Strings['kind'] <> 'update' then Continue;
    mid := cs.Find('mid');
    if (mid <> nil) and (mid.JSONType <> jtObject) then mid := nil;
    RunCase(cs.Strings['id'], cs.Elements['option'], cs.Elements['next'], mid,
      cs.Arrays['clips'], cs.Arrays['elements']);
    Inc(ran);
  end;
  AssertTrue(Format('%d mismatches over %d proxy samples:%s', [FBad, FCompared, FReport]),
    FBad = 0);
  AssertTrue(Format('only %d cases ran', [ran]), ran >= 5);
  AssertTrue(Format('only %d proxy samples', [FCompared]), FCompared >= 250);
end;

{ ==================== by hand ==================== }

function Strs(const A: array of string): TTyStringArray;
var i: Integer;
begin
  SetLength(Result, Length(A));
  for i := 0 to High(A) do Result[i] := A[i];
end;

function CmdText(const ACmds: TTyDataDiffCmdArray): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to High(ACmds) do
  begin
    case ACmds[i].Kind of
      ddkAdd: Result := Result + Format('A%d ', [ACmds[i].NewIdx]);
      ddkUpdate: Result := Result + Format('U%d<%d ', [ACmds[i].NewIdx, ACmds[i].OldIdx]);
      ddkRemove: Result := Result + Format('R%d ', [ACmds[i].OldIdx]);
    end;
  end;
  Result := Trim(Result);
end;

{ DataDiffer one to one: old rows in order (the first new row left of the
  key, else a remove), then the new rows left, in order. }
procedure TAdvChartAnimUpdateTest.TestDataDiffAsUpstream;
begin
  AssertEquals('kept, removed, kept again, added', 'U0<0 R1 U1<2 A2',
    CmdText(TyDataDiff(Strs(['a', 'b', 'a']), Strs(['a', 'a', 'c']))));
  AssertEquals('a shift', 'R0 U0<1 U1<2 A2',
    CmdText(TyDataDiff(Strs(['A', 'B', 'C']), Strs(['B', 'C', 'D']))));
  AssertEquals('a key twice among the new: both added at the first',
    'R0 A0 A2 A1',
    CmdText(TyDataDiff(Strs(['z']), Strs(['x', 'y', 'x']))));
  AssertEquals('nothing before', 'A0 A1', CmdText(TyDataDiff(nil, Strs(['p', 'q']))));
end;

{ getBoundingDiff: the greatest corner distance of the two extents, illegal
  points left out; nothing legal is not a number (Infinity - Infinity). }
procedure TAdvChartAnimUpdateTest.TestLineBoundingDiff;
var a, b: TTyDoubleArray;
begin
  a := TTyDoubleArray.Create(0, 0, 10, 10);
  b := TTyDoubleArray.Create(0, 0, 10, 3010.5, NaN, 99999);
  AssertEquals('the far corner', 3000.5, TyLineBoundingDiff(a, b), 0);
  b := TTyDoubleArray.Create(NaN, NaN);
  AssertTrue('nothing legal on one side: infinite, past the cutoff',
    IsInfinite(TyLineBoundingDiff(a, b)));
  AssertTrue('nothing legal on either: Infinity - Infinity is not a number',
    IsNan(TyLineBoundingDiff(b, b)));
end;

const
  cBars = '{"xAxis":{"type":"category","data":["A","B","C"]},"yAxis":{"type":"value"},'
    + '"series":[{"type":"bar","label":{"show":true},"data":[10,30,20]}]}';
  cBarsShift = '{"xAxis":{"type":"category","data":["B","C","D"]},"yAxis":{"type":"value"},'
    + '"series":[{"type":"bar","label":{"show":true},"data":[30,20,25]}]}';

function LabelCount(AList: TTyPaintList): Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to AList.Count - 1 do
    if AList.Element(i).Caption.Text <> '' then Inc(Result);
end;

{ A GHOST IS DRAWN, AFTER THE LIST, SILENT, WORDLESS: bar A, removed, is
  still in the frame half way through its fade at its old place and at the
  proxy's opacity -- the pointer goes through it, and its label went at once
  (removeElementWithFadeOut drops the text first). }
procedure TAdvChartAnimUpdateTest.TestAGhostIsDrawnAndSilent;
var
  frm, lst: TTyPaintList;
  g: TTyChartAnimProxy;
  e: TTyChartElement;
  i: Integer;
  found: Boolean;
begin
  NewChart(camAlways);
  Load(cBars);
  FChart.AnimTick(T0 + 5000);
  FChart.AnimNow := T1;
  SetNext(cBarsShift);
  g := FChart.AnimFindGhost(0, 0, 'bar');
  AssertNotNull('bar A leaves', g);
  AssertEquals('one ghost, the bar alone', 1, FChart.AnimGhostCount);
  FChart.AnimTick(T1 + 100);
  frm := FChart.Frame;
  lst := FChart.List;
  AssertEquals('the frame is the list and the ghost', lst.Count + 1, frm.Count);
  AssertTrue('the list has its labels', LabelCount(lst) > 0);
  AssertEquals('no word more in the frame than in the list', LabelCount(lst),
    LabelCount(frm));
  e := frm.Element(frm.Count - 1);
  AssertTrue('the ghost is silent', e.Silent);
  AssertEquals('it has no label', '', e.Caption.Text);
  AssertEquals('at its proxy''s opacity: cubicOut(0.5) from 1',
    1 - (1 - Power(1 - 0.5, 3)), e.Style.Alpha, 1e-12);
  AssertEquals('the proxy says so too', e.Style.Alpha, g.Num('style.opacity'), 0);
  found := False;
  for i := 0 to lst.Count - 1 do
    if (lst.Element(i).Anim.Role = carBar) and (lst.Element(i).Anim.Index = 0) then
    begin
      found := True;
      AssertEquals('A fades in the first slot, where B now stands',
        lst.Element(i).Shape.Bounds.Left, e.Shape.Bounds.Left, 1e-9);
      AssertTrue('at its own height, not B''s',
        Abs((e.Shape.Bounds.Bottom - e.Shape.Bounds.Top)
          - (lst.Element(i).Shape.Bounds.Bottom - lst.Element(i).Shape.Bounds.Top)) > 10);
    end;
  AssertTrue('a bar at row 0', found);
  FChart.AnimTick(T1 + 250);
  AssertEquals('gone when the fade ends', 0, FChart.AnimGhostCount);
  AssertNull('and not found', FChart.AnimFindGhost(0, 0, 'bar'));
  AssertEquals('the frame is the list again', FChart.List.Count, FChart.Frame.Count);
end;

{ A RESIZE IN THE MIDDLE OF AN UPDATE SNAPS: no proxy, no ghost. }
procedure TAdvChartAnimUpdateTest.TestAResizeEndsAnUpdate;
begin
  NewChart(camAlways);
  Load(cBars);
  FChart.AnimTick(T0 + 5000);
  FChart.AnimNow := T1;
  SetNext(cBarsShift);
  AssertTrue('live', FChart.AnimLive);
  FChart.SetBounds(0, 0, cW - 30, cH);
  Draw;
  AssertFalse('a resize finishes it', FChart.AnimLive);
  AssertEquals('no ghost', 0, FChart.AnimGhostCount);
  AssertEquals('no proxy', 0, FChart.AnimProxyCount);
end;

{ camAuto: a headless render of the new option draws it as laid out and
  binds nothing -- the old render's proxies stand for the old rows -- and
  the update waits for the window. }
procedure TAdvChartAnimUpdateTest.TestHeadlessUpdateWaitsForTheWindow;
var
  lst, frm: TTyPaintList;
  i: Integer;
begin
  NewChart(camAlways);
  Load(cBars);
  FChart.AnimTick(T0 + 5000);
  FChart.AnimationMode := camAuto;
  FChart.AnimNow := T1;
  SetNext(cBarsShift);
  AssertEquals('nothing armed', 0, FChart.AnimClipCount);
  AssertEquals('nothing leaving', 0, FChart.AnimGhostCount);
  lst := FChart.List;
  frm := FChart.Frame;
  AssertEquals('the frame is the list', lst.Count, frm.Count);
  for i := 0 to lst.Count - 1 do
    AssertTrue(Format('element %d drawn as laid out', [i]),
      SameShape(lst.Element(i), frm.Element(i)));
end;

initialization
  RegisterTest(TAdvChartAnimUpdateTest);
finalization
  FreeAndNil(GMain);
  FreeAndNil(GExtra);
  FreeAndNil(GAn4);
end.
