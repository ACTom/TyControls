unit test.advchart.animmerge;
{$mode objfpc}{$H+}
{ A MERGE setOption AS AN UPDATE ON THE REAL CONTROL, held to upstream.
  [Batch 99, AN6]

  tools/advchart-oracle/merge-anim.js drives the real ECharts 6.1 build
  under the hand-driven clock: an option set at T0 and settled, then at
  T1 + t the events of each sample -- a merge setOption (with replaceMerge,
  with lazyUpdate), a pointer hover, a highlight or select action -- and one
  frame (a synchronous setOption flushes instead; a lazy one renders inside
  the frame, after its step). Recorded per sample: every element of every
  series view and of the marker views, every leaf of every cartesian axis
  group by its anid, and which view object each series and axis model has.

  The replay drives the control the same way -- SetOption with the options
  object, MouseMove, DispatchAction -- in camAlways with the injected clock,
  AnimTick (unless a synchronous setOption flushed) and a render per sample,
  and compares:
    - every series element upstream animates against the proxy that stands
      for it (a leaving one against its ghost): present where upstream's is,
      every tracked key BIT FOR BIT, the animator count;
    - the markers: a markPoint's group and path against its proxy (x / y,
      scale, the animators of both), a markLine's line against its proxy
      (the ends), its end symbols and its label against what the port
      derives from that proxy, and the frame drawing them there;
    - every axis leaf against the axis proxy of its anid: present exactly
      where upstream's is, x / y / rotation of a label and the four ends of
      a line bit for bit, the animator count -- and a leaf upstream moves
      while the control has no axis proxy is a miss;
    - the state list and state animators of a hovered, highlighted or
      selected element through the merge;
    - the clips, all of them. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Measure,
     tyControls.AdvChart.Anim, tyControls.AdvChart.AnimOpt,
     tyControls.AdvChart.AnimView, tyControls.AdvChart.MarkerView,
     tyControls.AdvanceChart, tyControls.AdvChart.Events,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TMaProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Move(AX, AY: Integer);
    function List: TTyPaintList;
    function Frame: TTyPaintList;
  end;

  TMaKind = (makStatic, makModel, makDerived, makAxis, makUnknown);
  TMaMap = record
    Kind: TMaKind;
    Series, Index: Integer;
    Role: string;
    Ghost: Boolean;
    { makDerived: 'markFrom', 'markTo', 'markLabel' }
    Derived: string;
    AxisKey, Anid: string;
  end;

  TAdvChartAnimMergeTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TMaProbe;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FAxisCompared, FStateCompared, FMarkCompared: Integer;
    FReport: string;
    FSeen, FTally, FEvents: TStringList;
    procedure OnEv(Sender: TObject; const AEvent: TTyChartEvent);
    procedure Miss(const AWhere: string; const AOnce: string = '');
    procedure NewChart(AMode: TTyChartAnimationMode);
    function Draw: TBGRABitmap;
    procedure Load(const AOption: string);
    procedure Settle(AStart: Double);
    procedure Merge(const AJson: string; const AOpts: string = '');
    procedure CompareDerived(const AName: string; AEl: TJSONObject; const M: TMaMap;
      ASample: Integer);
    procedure RunCase(ACase: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestMergesAsUpstream;
    procedure TestAnAxisWhoseTypeChangesIsANewView;
    procedure TestALazyMergeArmsAtTheDeferredRender;
    procedure TestAHoverHeldThroughAMergeSendsNoOver;
    procedure TestTwoMergesBeforeARenderKeepTheHover;
    procedure TestAMarkPointLabelRidesItsSymbol;
  end;

implementation

const
  cW = 400;
  cH = 300;

var
  GFix: TJSONData = nil;

function Fix: TJSONObject;
var sl: TStringList;
begin
  if GFix = nil then
  begin
    sl := TStringList.Create;
    try
      sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
        + 'advchart-merge-anim.json');
      GFix := GetJSON(sl.Text);
    finally
      sl.Free;
    end;
  end;
  Result := TJSONObject(GFix);
end;

function T0: Double;
begin
  Result := Fix.Objects['clock'].Floats['T0'];
end;

function T1: Double;
begin
  Result := T0 + Fix.Objects['clock'].Floats['T1Offset'];
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
    if not (s[i] in ['0'..'9', 'a'..'f']) then Exit;
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

function StateAnimsOf(P: TTyChartAnimProxy): string;
var
  i: Integer;
  a: TTyAnimator;
begin
  Result := '';
  if P = nil then Exit;
  for i := 0 to P.AnimatorCount - 1 do
  begin
    a := P.AnimatorAt(i);
    if a.FromStateTransition = '' then Continue;
    if Result <> '' then Result := Result + ' ';
    Result := Result + a.FromStateTransition + ':' + a.TargetName;
  end;
end;

function FindListEl(AList: TTyPaintList; ARole: TTyChartAnimRole;
  ASeries, AIndex: Integer; out AEl: TTyChartElement): Boolean;
var i: Integer;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  if AList = nil then Exit;
  for i := 0 to AList.Count - 1 do
    if (AList.Element(i).Anim.Role = ARole) and (AList.Element(i).Anim.Series = ASeries)
      and (AList.Element(i).Anim.Index = AIndex) then
    begin
      AEl := AList.Element(i);
      Exit(True);
    end;
end;

{ the series index of the AOrdinal-th series whose AKey has data }
function MarkerSeries(AOption: TJSONData; const AKey: string; AOrdinal: Integer): Integer;
var
  ser, s, m: TJSONData;
  i, n, k: Integer;
begin
  Result := -1;
  if not (AOption is TJSONObject) then Exit;
  ser := TJSONObject(AOption).Find('series');
  if ser = nil then Exit;
  if ser.JSONType = jtArray then n := ser.Count else n := 1;
  k := 0;
  for i := 0 to n - 1 do
  begin
    if ser.JSONType = jtArray then s := ser.Items[i] else s := ser;
    if not (s is TJSONObject) then Continue;
    m := TJSONObject(s).Find(AKey);
    if not (m is TJSONObject) or (TJSONObject(m).Find('data') = nil) then Continue;
    if k = AOrdinal then Exit(i);
    Inc(k);
  end;
end;

{ ==================== the probe ==================== }

function TMaProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TMaProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TMaProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

function TMaProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TMaProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

{ ==================== mapping upstream's elements ==================== }

function ScopeAt(AEl: TJSONObject; ASample: Integer): string;
var d: TJSONData;
begin
  Result := '';
  d := AEl.Find('scopes');
  if (d is TJSONArray) and (ASample < d.Count) then Result := d.Items[ASample].AsString;
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
    if Pos('leave:', d.Items[i].AsString) > 0 then Exit(True);
end;

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

function MapElement(AEls: TJSONArray; AEl: TJSONObject; AOption: TJSONData): TMaMap;
var
  id, owner, typ, stype, base, path: string;
  p, k, di: Integer;
  hasTrack, hasAnim: Boolean;
  d, a: TJSONData;
  parts: TStringList;
begin
  Result := Default(TMaMap);
  Result.Kind := makStatic;
  id := AEl.Strings['id'];
  owner := AEl.Strings['owner'];
  typ := AEl.Strings['type'];
  if AEl.Strings['role'] = 'axis' then
  begin
    Result.Kind := makAxis;
    Result.AxisKey := owner;
    Result.Anid := Copy(id, Pos('/', id) + 1, MaxInt);
    Exit;
  end;
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
  { THE MARKERS: a markPoint's group and its path share a proxy; a
    markLine's line is its proxy, its two symbols and its label derived }
  if (Pos('markLine', owner) = 1) or (Pos('markPoint', owner) = 1) then
  begin
    Result.Kind := makUnknown;
    path := Copy(id, Pos('/', id) + 1, MaxInt);
    base := path;
    if Pos('#', base) > 0 then base := Copy(base, 1, Pos('#', base) - 1);
    parts := TStringList.Create;
    try
      parts.Delimiter := '.';
      parts.StrictDelimiter := True;
      parts.DelimitedText := base;
      if parts.Count < 2 then Exit;
      if di < 0 then di := StrToIntDef(parts[1], -1);
      if Pos('markPoint', owner) = 1 then
      begin
        if Pos('#label', id) > 0 then Exit;
        Result.Kind := makModel;
        Result.Role := 'markPoint';
        Result.Series := MarkerSeries(AOption, 'markPoint', StrToIntDef(parts[0], -1));
        Result.Index := di;
      end
      else
      begin
        Result.Series := MarkerSeries(AOption, 'markLine', StrToIntDef(parts[0], -1));
        Result.Index := di;
        Result.Role := 'markLine';
        if Pos('#label', id) > 0 then
        begin
          Result.Kind := makDerived;
          Result.Derived := 'markLabel';
        end
        else if parts.Count >= 3 then
        begin
          if parts[2] = '0' then Result.Kind := makModel
          else
          begin
            Result.Kind := makDerived;
            if parts[2] = '1' then Result.Derived := 'markFrom'
            else Result.Derived := 'markTo';
          end;
        end;
      end;
    finally
      parts.Free;
    end;
    Exit;
  end;
  Result.Kind := makUnknown;
  p := Pos(':', owner);
  if p = 0 then Exit;
  Result.Series := StrToIntDef(Copy(owner, 7, p - 7), -1);
  stype := Copy(owner, p + 1, MaxInt);
  Result.Ghost := HasLeave(AEl);
  if (Pos('#label', id) > 0) or (Pos('#guide', id) > 0) then
  begin
    Result.Kind := makModel;
    if Pos('#label', id) > 0 then Result.Role := 'label' else Result.Role := 'guide';
    base := Copy(id, Pos('/', id) + 1, MaxInt);
    base := Copy(base, 1, Pos('#', base) - 1);
    Result.Index := DataIndexOf(AEls, Copy(id, 1, Pos('/', id)) + base);
    Exit;
  end;
  if stype = 'bar' then
  begin
    if typ = 'rect' then
    begin
      Result.Kind := makModel;
      Result.Role := 'bar';
      Result.Index := di;
    end;
  end
  else if stype = 'line' then
  begin
    if Pos('#clip', id) > 0 then
    begin
      Result.Kind := makModel;
      Result.Role := 'lineClip';
      Result.Index := -1;
    end
    else if typ = 'ec-polyline' then
    begin
      Result.Kind := makModel;
      Result.Role := 'linePoly';
      Result.Index := -1;
    end
    else if typ = 'ec-polygon' then
    begin
      Result.Kind := makModel;
      Result.Role := 'lineArea';
      Result.Index := -1;
    end
    else if (typ = 'group') and (di >= 0) then
    begin
      Result.Kind := makModel;
      Result.Role := 'lineSymbol';
      Result.Index := di;
    end
    else if (typ = 'path') and (di >= 0) and Result.Ghost then
    begin
      Result.Kind := makModel;
      Result.Role := 'lineSymbol';
      Result.Index := di;
    end
    else if (typ = 'path') and (di >= 0) then
      Result.Kind := makStatic;
  end
  else if stype = 'scatter' then
  begin
    if di >= 0 then
    begin
      Result.Kind := makModel;
      Result.Role := 'symbol';
      Result.Index := di;
    end;
  end;
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

function IndexAt(AEls: TJSONArray; AEl: TJSONObject; ASample: Integer): Integer;
var
  d: TJSONData;
  id: string;
begin
  d := AEl.Find('dataIndices');
  if (d is TJSONArray) and (d.Items[ASample].JSONType = jtNumber) then
    Exit(d.Items[ASample].AsInteger);
  d := AEl.Find('dataIndex');
  if (d <> nil) and (d.JSONType = jtNumber) then Exit(d.AsInteger);
  id := AEl.Strings['id'];
  if Pos('#', id) > 0 then Exit(DataIndexOf(AEls, Copy(id, 1, Pos('#', id) - 1)));
  Result := -1;
end;

function LeavingAt(AEl: TJSONObject; ASample: Integer): Boolean;
var
  s: Integer;
  d: TJSONData;
begin
  Result := False;
  d := AEl.Find('scopes');
  if not (d is TJSONArray) then Exit;
  for s := ASample downto 0 do
  begin
    if not PresentAt(AEl, s) then Exit(False);
    if Pos('leave:', d.Items[s].AsString) > 0 then Exit(True);
  end;
end;

function ChildLeaving(AEls: TJSONArray; const AId: string; ASample: Integer): Boolean;
var i: Integer;
begin
  for i := 0 to AEls.Count - 1 do
    if AEls.Objects[i].Strings['id'] = AId + '.0' then
      Exit(LeavingAt(AEls.Objects[i], ASample));
  Result := False;
end;

function StateAnimCount(AEl: TJSONObject; ASample: Integer): Integer;
var
  sa: TJSONData;
  i: Integer;
  s: string;
begin
  Result := 0;
  sa := AEl.Find('stateAnimators');
  if not (sa is TJSONArray) then Exit;
  s := sa.Items[ASample].AsString;
  if s = '' then Exit;
  Result := 1;
  for i := 1 to Length(s) do
    if s[i] = ' ' then Inc(Result);
end;

function AsAtStart(AEl: TJSONObject; ASample: Integer): Boolean;
var
  d, sa: TJSONData;
  tr: TJSONObject;
  i, n: Integer;
begin
  Result := False;
  n := 0;
  sa := AEl.Find('stateAnimators');
  if (sa is TJSONArray) and (sa.Items[ASample].AsString <> '') then
  begin
    n := 1;
    for i := 1 to Length(sa.Items[ASample].AsString) do
      if sa.Items[ASample].AsString[i] = ' ' then Inc(n);
  end;
  d := AEl.Find('animators');
  if (d is TJSONArray) and (d.Items[ASample].AsInteger > n) then Exit;
  d := AEl.Find('track');
  if d is TJSONObject then
  begin
    tr := TJSONObject(d);
    for i := 0 to tr.Count - 1 do
    begin
      if (tr.Names[i] = 'states') or (tr.Names[i] = 'z2') or (Pos('style.', tr.Names[i]) = 1) then
        Continue;
      if tr.Items[i].Items[ASample].AsJSON <> tr.Items[i].Items[0].AsJSON then Exit;
    end;
  end;
  Result := True;
end;

procedure KeyTarget(const ARole, AKey: string; out ARoleOut, AKeyOut: string);
begin
  ARoleOut := ARole;
  AKeyOut := AKey;
  if (ARole = 'linePoly') and (AKey = 'shape.__points') then AKeyOut := 'shape.points'
  else if (ARole = 'lineArea') and (AKey = 'shape.points') then ARoleOut := 'linePoly';
end;

function ValueAt(AEl: TJSONObject; const AKey: string; ASample: Integer): TJSONData;
var tr: TJSONData;
begin
  Result := nil;
  tr := AEl.Find('track');
  if (tr is TJSONObject) and (TJSONObject(tr).Find(AKey) <> nil) then
    Result := TJSONObject(tr).Arrays[AKey].Items[ASample]
  else if TJSONObject(AEl.Find('final')).Find(AKey) <> nil then
    Result := TJSONObject(AEl.Find('final')).Find(AKey);
  if (Result <> nil) and (Result.JSONType = jtNull) then Result := nil;
end;

{ ==================== plumbing ==================== }

procedure TAdvChartAnimMergeTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
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
  FTally := TStringList.Create;
  FEvents := TStringList.Create;
  FBad := 0;
  FCompared := 0;
  FAxisCompared := 0;
  FStateCompared := 0;
  FMarkCompared := 0;
  FReport := '';
end;

procedure TAdvChartAnimMergeTest.TearDown;
begin
  FreeAndNil(FSeen);
  FreeAndNil(FTally);
  FreeAndNil(FEvents);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

procedure TAdvChartAnimMergeTest.OnEv(Sender: TObject; const AEvent: TTyChartEvent);
begin
  FEvents.Add(AEvent.EventType);
end;

procedure TAdvChartAnimMergeTest.Miss(const AWhere: string; const AOnce: string);
var c: string; i, n: Integer;
begin
  Inc(FBad);
  c := Copy(AWhere, 1, Pos(' ', AWhere) - 1);
  if (c <> '') and (c[Length(c)] = ':') then Delete(c, Length(c), 1);
  i := FTally.IndexOfName(c);
  if i < 0 then
  begin
    FTally.Add(c + '=1');
    n := 1;
  end
  else
  begin
    n := StrToInt(FTally.ValueFromIndex[i]) + 1;
    FTally.ValueFromIndex[i] := IntToStr(n);
  end;
  if AOnce <> '' then
  begin
    if FSeen.IndexOf(AOnce) >= 0 then Exit;
    FSeen.Add(AOnce);
  end;
  if n <= 12 then
    FReport := FReport + LineEnding + '  ' + AWhere;
end;

procedure TAdvChartAnimMergeTest.NewChart(AMode: TTyChartAnimationMode);
begin
  FreeAndNil(FChart);
  FChart := TMaProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := AMode;
  FChart.AnimNow := T0;
  FChart.DataZoomNow := T0;
  FChart.SetBounds(0, 0, cW, cH);
end;

function TAdvChartAnimMergeTest.Draw: TBGRABitmap;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
  Result := FBmp;
end;

procedure TAdvChartAnimMergeTest.Load(const AOption: string);
begin
  FChart.Option := AOption;
  AssertEquals('the option parses', '', FChart.OptionError);
  Draw;
end;

procedure TAdvChartAnimMergeTest.Settle(AStart: Double);
var t: Integer;
begin
  t := 16;
  while t <= 5000 do
  begin
    FChart.AnimNow := AStart + t;
    FChart.AnimTick(AStart + t);
    Inc(t, 250);
  end;
  Draw;
  AssertEquals('settled', 0, FChart.AnimClipCount);
end;

procedure TAdvChartAnimMergeTest.Merge(const AJson: string; const AOpts: string);
begin
  AssertTrue('the merge is taken: ' + FChart.OptionError, FChart.SetOption(AJson, AOpts));
end;

{ A markLine's end symbols and its label: upstream places them from the
  line's shape every frame (Line.beforeUpdate); the port derives the same
  from the line's proxy -- compared bit for bit, and the frame must draw
  them there }
procedure TAdvChartAnimMergeTest.CompareDerived(const AName: string; AEl: TJSONObject;
  const M: TMaMap; ASample: Integer);
var
  p: TTyChartAnimProxy;
  track: TJSONObject;
  k, ah, av, i: Integer;
  key, eid: string;
  up: TTyDoubleArray;
  got, pc, tx, ty, lx, ly, tx1, ty1, lx1, ly1, want: Double;
  g, a, b: TTyChartElement;
  mg: TTyDoubleArray;
  role: TTyChartAnimRole;
  lst, frm: TTyPaintList;
begin
  eid := AEl.Strings['id'];
  p := FChart.AnimFindProxy(M.Series, M.Index, M.Role);
  if p = nil then
  begin
    Miss(Format('%s: no %s proxy for %s', [AName, M.Role, eid]), AName + eid + 'dproxy');
    Exit;
  end;
  if not (AEl.Find('track') is TJSONObject) then Exit;
  track := AEl.Objects['track'];
  pc := p.Num('shape.percent');
  if M.Derived = 'markFrom' then role := carMarkLineFrom
  else if M.Derived = 'markTo' then role := carMarkLineTo
  else role := carMarkLineLabel;
  if not FindListEl(FChart.List, role, M.Series, M.Index, g) then
  begin
    Miss(Format('%s: no list element for %s', [AName, eid]), AName + eid + 'dlist');
    Exit;
  end;
  mg := TyAnimMarkLineG(g, p);
  TyMkLineAt(mg, pc, tx, ty, lx, ly, ah, av);
  Inc(FMarkCompared);
  for k := 0 to track.Count - 1 do
  begin
    key := track.Names[k];
    if (key = 'x') or (key = 'y') then
    begin
      if M.Derived = 'markFrom' then
      begin
        if key = 'x' then got := mg[0] else got := mg[1];
      end
      else if M.Derived = 'markTo' then
      begin
        if key = 'x' then got := tx else got := ty;
      end
      else if key = 'x' then got := lx
      else got := ly;
    end
    else if (key = 'scaleX') or (key = 'scaleY') then got := pc
    else
    begin
      Miss(Format('%s: %s %s is not derived here', [AName, eid, key]), AName + eid + key + 'dmod');
      Continue;
    end;
    if not NumsOf(track.Arrays[key].Items[ASample], up) or (Length(up) <> 1) then Continue;
    if not SameBits(got, up[0]) then
      Miss(Format('%s t=%d %s: %s %s here, %s upstream', [AName, ASample, eid, key,
        Fmt(got), Fmt(up[0])]), AName + eid + key);
  end;
  { AND THE FRAME DRAWS IT THERE }
  lst := FChart.List;
  frm := FChart.Frame;
  if (lst = nil) or (frm = nil) or (frm = lst) or not (pc > 0) then Exit;
  for i := 0 to lst.Count - 1 do
  begin
    a := lst.Element(i);
    if (a.Anim.Role <> role) or (a.Anim.Series <> M.Series) or (a.Anim.Index <> M.Index) then
      Continue;
    b := frm.Element(i);
    case role of
      carMarkLineFrom, carMarkLineTo:
        begin
          if role = carMarkLineFrom then
            want := a.Anim.G[0] + (TyShapeBounds(a.Shape).Left - a.Anim.G[0]) * pc
              + (mg[0] - a.Anim.G[0])
          else
            want := a.Anim.G[2] + (TyShapeBounds(a.Shape).Left - a.Anim.G[2]) * pc
              + (tx - a.Anim.G[2]);
          if Abs(TyShapeBounds(b.Shape).Left - want) > 1e-9 then
            Miss(Format('%s %s: the frame''s symbol at %s, the proxy says %s', [AName, eid,
              Fmt(TyShapeBounds(b.Shape).Left), Fmt(want)]), AName + eid + 'frm');
        end;
    else
      begin
        TyMkLineAt(a.Anim.G, 1, tx1, ty1, lx1, ly1, ah, av);
        if (Abs(b.Caption.X - (a.Caption.X + (lx - lx1))) > 1e-9)
          or (Abs(b.Caption.Y - (a.Caption.Y + (ly - ly1))) > 1e-9) then
          Miss(Format('%s %s: the frame''s label at %s, %s', [AName, eid,
            Fmt(b.Caption.X), Fmt(b.Caption.Y)]), AName + eid + 'frm');
      end;
    end;
    Break;
  end;
end;

{ ==================== the timelines ==================== }

type
  TMaEntry = record
    Map: TMaMap;
    Els: array of Integer;
  end;

procedure TAdvChartAnimMergeTest.RunCase(ACase: TJSONObject);
var
  name, s, key, tRole, tKey, eid, want, got, opts: string;
  samples, events, els, clips: TJSONArray;
  si, ei, k, j, n, ti, sumAnim, live, ghosts, q: Integer;
  t: Double;
  e, el, track: TJSONObject;
  maps: array of TMaMap;
  entries: array of TMaEntry;
  m: TMaMap;
  p, tp: TTyChartAnimProxy;
  present, upPresent, flushed, merged: Boolean;
  up, gotN: TTyDoubleArray;
  fv, tr: TJSONData;

  function ProxyOf(const AM: TMaMap; const ARole: string): TTyChartAnimProxy;
  begin
    if AM.Ghost then Result := FChart.AnimFindGhost(AM.Series, AM.Index, ARole)
    else Result := FChart.AnimFindProxy(AM.Series, AM.Index, ARole);
  end;

begin
  name := ACase.Strings['id'];
  samples := Fix.Arrays['samplesMs'];
  events := ACase.Arrays['events'];
  els := ACase.Arrays['elements'];
  clips := ACase.Arrays['clips'];
  NewChart(camAlways);
  Load(ACase.Objects['option'].AsJSON);
  Settle(T0);
  { one entry per element -- a markPoint's group and path one entry, their
    animators summed on the one proxy }
  SetLength(maps, els.Count);
  entries := nil;
  for k := 0 to els.Count - 1 do
  begin
    maps[k] := MapElement(els, els.Objects[k], ACase.Objects['option']);
    if maps[k].Kind = makUnknown then
      Miss(Format('%s: %s is not mapped', [name, els.Objects[k].Strings['id']]));
    if maps[k].Kind <> makModel then Continue;
    merged := False;
    if maps[k].Role = 'markPoint' then
      for q := 0 to High(entries) do
        if (entries[q].Map.Role = 'markPoint') and (entries[q].Map.Series = maps[k].Series)
          and (entries[q].Map.Index = maps[k].Index) then
        begin
          SetLength(entries[q].Els, Length(entries[q].Els) + 1);
          entries[q].Els[High(entries[q].Els)] := k;
          merged := True;
        end;
    if merged then Continue;
    n := Length(entries);
    SetLength(entries, n + 1);
    entries[n].Map := maps[k];
    SetLength(entries[n].Els, 1);
    entries[n].Els[0] := k;
  end;
  for si := 0 to samples.Count - 1 do
  begin
    t := samples.Floats[si];
    FChart.AnimNow := T1 + t;
    FChart.DataZoomNow := T1 + t;
    flushed := False;
    for ei := 0 to events.Count - 1 do
    begin
      e := events.Objects[ei];
      if e.Floats['at'] <> t then Continue;
      s := e.Strings['type'];
      if (s = 'over') or (s = 'out') then
        FChart.Move(e.Integers['x'], e.Integers['y'])
      else if s = 'action' then
        FChart.DispatchAction(e.Objects['payload'].AsJSON)
      else if s = 'setOption' then
      begin
        opts := '';
        if e.Find('opts') is TJSONObject then opts := e.Objects['opts'].AsJSON;
        Merge(e.Objects['option'].AsJSON, opts);
        { a lazy one renders in the frame, after its step }
        if not ((e.Find('opts') is TJSONObject)
          and (e.Objects['opts'].Find('lazyUpdate') <> nil)
          and e.Objects['opts'].Booleans['lazyUpdate']) then
          flushed := True;
      end
      else
        Fail('unknown event ' + s);
    end;
    if not flushed then FChart.AnimTick(T1 + t);
    Draw;
    { THE CLIPS }
    if FChart.AnimClipCount <> clips.Integers[si] then
      Miss(Format('%s t=%s: %d clips here, %d upstream', [name, FloatToStr(t),
        FChart.AnimClipCount, clips.Integers[si]]), name + 'clips');
    { ---- the series and the markers ---- }
    ghosts := 0;
    for j := 0 to High(entries) do
    begin
      m := entries[j].Map;
      el := els.Objects[entries[j].Els[0]];
      if Pos('mark', m.Role) <> 1 then m.Index := IndexAt(els, el, si);
      upPresent := PresentAt(el, si);
      if m.Ghost then
      begin
        if not LeavingAt(el, si) then
        begin
          if el.Strings['type'] = 'path' then Continue;
          m.Ghost := False;
          if not upPresent then Continue;
        end;
      end;
      if (el.Strings['type'] = 'group') and (Pos('mark', m.Role) <> 1)
        and ChildLeaving(els, el.Strings['id'], si) then
        Continue;
      sumAnim := 0;
      for k := 0 to High(entries[j].Els) do
        if els.Objects[entries[j].Els[k]].Find('animators') is TJSONArray then
          Inc(sumAnim, els.Objects[entries[j].Els[k]].Arrays['animators'].Items[si].AsInteger);
      if (m.Role = 'linePoly') or (m.Role = 'lineArea') or (m.Role = 'lineSymbol') then
        Dec(sumAnim, StateAnimCount(el, si));
      p := ProxyOf(m, m.Role);
      present := p <> nil;
      eid := el.Strings['id'];
      if (not m.Ghost) and upPresent and (p = nil)
        and (FChart.AnimFindGhost(m.Series, m.Index, m.Role) <> nil) then Continue;
      if m.Ghost then
      begin
        if present <> upPresent then
          Miss(Format('%s t=%s %s: a ghost here %s, upstream %s', [name, FloatToStr(t),
            eid, BoolToStr(present, True), BoolToStr(upPresent, True)]), name + eid + 'ghost');
        if present then Inc(ghosts);
      end
      else if upPresent and not present then
      begin
        if AsAtStart(el, si) then Continue;
        Miss(Format('%s t=%s: no proxy for %s (%d,%d,%s)', [name, FloatToStr(t), eid,
          m.Series, m.Index, m.Role]), name + eid + 'none');
        Continue;
      end;
      if (p = nil) or not upPresent then Continue;
      Inc(FCompared);
      if Pos('mark', m.Role) = 1 then Inc(FMarkCompared);
      if p.AnimatorCount <> sumAnim then
        Miss(Format('%s t=%s %s: %d animators here, %d upstream (%s)', [name,
          FloatToStr(t), eid, p.AnimatorCount, sumAnim, ScopeAt(el, si)]), name + eid + 'anim');
      for k := 0 to High(entries[j].Els) do
      begin
        el := els.Objects[entries[j].Els[k]];
        if not (el.Find('track') is TJSONObject) then Continue;
        track := el.Objects['track'];
        for ti := 0 to track.Count - 1 do
        begin
          key := track.Names[ti];
          if (key = 'states') or (key = 'z2') or (key = 'style.fill')
            or (key = 'style.stroke') or (key = 'style.lineWidth') then Continue;
          KeyTarget(m.Role, key, tRole, tKey);
          if tRole = m.Role then tp := p else tp := ProxyOf(m, tRole);
          if tp = nil then
          begin
            Miss(Format('%s: no %s proxy for %s', [name, tRole, eid]), name + eid + tRole);
            Continue;
          end;
          if not NumsOf(track.Arrays[key].Items[si], up) then Continue;
          if not ValNums(tp.GetAnimProp(tKey), gotN) then
          begin
            if AsAtStart(el, si) then Continue;
            Miss(Format('%s: %s %s is not modelled', [name, eid, key]), name + eid + key + 'mod');
            Continue;
          end;
          if Length(up) <> Length(gotN) then
          begin
            Miss(Format('%s t=%s %s: %s has %d numbers here, %d upstream', [name,
              FloatToStr(t), eid, key, Length(gotN), Length(up)]), name + eid + key + 'len');
            Continue;
          end;
          for n := 0 to High(gotN) do
            if not SameBits(gotN[n], up[n]) then
            begin
              Miss(Format('%s t=%s %s: %s[%d] %s here, %s upstream', [name,
                FloatToStr(t), eid, key, n, Fmt(gotN[n]), Fmt(up[n])]), name + eid + key);
              Break;
            end;
        end;
      end;
    end;
    { the markLines' derived elements }
    for k := 0 to els.Count - 1 do
      if maps[k].Kind = makDerived then
        CompareDerived(name, els.Objects[k], maps[k], si);
    live := FChart.AnimGhostCount;
    if live <> ghosts then
      Miss(Format('%s t=%s: %d ghosts here, %d upstream', [name, FloatToStr(t), live,
        ghosts]), name + 'ghosts');
    { ---- the states of a hovered, highlighted or selected element ---- }
    for k := 0 to els.Count - 1 do
    begin
      el := els.Objects[k];
      if el.Strings['role'] <> 'el' then Continue;
      if Pos('series', el.Strings['owner']) <> 1 then Continue;
      if el.Find('dataIndex').JSONType <> jtNumber then Continue;
      if (el.Strings['type'] <> 'rect') and (el.Strings['type'] <> 'path') then Continue;
      if (el.Strings['type'] = 'path') and (Pos('line', el.Strings['owner']) = 0) then Continue;
      if not PresentAt(el, si) then Continue;
      if HasLeave(el) then Continue;
      fv := ValueAt(el, 'states', si);
      tr := el.Find('stateAnimators');
      if (fv = nil) or ((fv.AsString = '') and (tr.JSONType = jtNull)
        and not (el.Find('track') is TJSONObject)) then Continue;
      n := StrToIntDef(Copy(el.Strings['owner'], 7, Pos(':', el.Strings['owner']) - 7), -1);
      p := FChart.AnimStateProxy(n, IndexAt(els, el, si), 'host');
      if p = nil then
      begin
        if fv.AsString <> '' then
          Miss(Format('%s t=%s %s: no state proxy, upstream "%s"', [name, FloatToStr(t),
            el.Strings['id'], fv.AsString]), name + el.Strings['id'] + 'stpx');
        Continue;
      end;
      Inc(FStateCompared);
      if p.CurrentStates <> fv.AsString then
        Miss(Format('%s t=%s %s: states "%s", upstream "%s"', [name, FloatToStr(t),
          el.Strings['id'], p.CurrentStates, fv.AsString]), name + el.Strings['id'] + 'st'
          + FloatToStr(t));
      if tr.JSONType = jtNull then want := '' else want := TJSONArray(tr).Strings[si];
      got := StateAnimsOf(p);
      if want <> got then
        Miss(Format('%s t=%s %s: state animators "%s", upstream "%s"', [name, FloatToStr(t),
          el.Strings['id'], got, want]), name + el.Strings['id'] + 'sa' + FloatToStr(t));
    end;
    { ---- the axes ---- }
    for k := 0 to els.Count - 1 do
    begin
      if maps[k].Kind <> makAxis then Continue;
      el := els.Objects[k];
      eid := el.Strings['id'];
      if (Pos('minor', maps[k].Anid) = 1) or (Pos('area_', maps[k].Anid) = 1)
        or (maps[k].Anid = 'name') then Continue;
      sumAnim := 0;
      if el.Find('animators') is TJSONArray then
        sumAnim := el.Arrays['animators'].Items[si].AsInteger;
      upPresent := PresentAt(el, si);
      { NO AXIS PROXY while upstream's leaves move: the merge dropped them }
      if FChart.AnimAxisProxyCount = 0 then
      begin
        if upPresent and (sumAnim > 0) then
          Miss(Format('%s t=%s %s: no axis proxy, upstream moves it', [name, FloatToStr(t),
            eid]), name + eid + 'noaxis');
        Continue;
      end;
      p := FChart.AnimAxisProxy(maps[k].AxisKey, maps[k].Anid);
      if (p <> nil) <> upPresent then
      begin
        Miss(Format('%s t=%s %s: a leaf here %s, upstream %s', [name, FloatToStr(t), eid,
          BoolToStr(p <> nil, True), BoolToStr(upPresent, True)]), name + eid + 'leaf');
        Continue;
      end;
      if p = nil then Continue;
      Inc(FAxisCompared);
      if p.AnimatorCount <> sumAnim then
        Miss(Format('%s t=%s %s: %d animators here, %d upstream', [name, FloatToStr(t),
          eid, p.AnimatorCount, sumAnim]), name + eid + 'aanim');
      for ti := 0 to 6 do
      begin
        case ti of
          0: key := 'x';
          1: key := 'y';
          2: key := 'rotation';
          3: key := 'shape.x1';
          4: key := 'shape.y1';
          5: key := 'shape.x2';
        else
          key := 'shape.y2';
        end;
        if (ti < 3) <> (el.Strings['type'] = 'text') then Continue;
        fv := ValueAt(el, key, si);
        if not IsHex16(fv) then Continue;
        if p.GetAnimProp(key).Kind <> avkNumber then
        begin
          Miss(Format('%s %s: %s is not modelled', [name, eid, key]), name + eid + key + 'mod');
          Continue;
        end;
        if not SameBits(p.Num(key), FromHex(fv.AsString)) then
          Miss(Format('%s t=%s %s: %s %s here, %s upstream', [name, FloatToStr(t), eid,
            key, Fmt(p.Num(key)), Fmt(FromHex(fv.AsString))]), name + eid + key);
      end;
    end;
  end;
  { AT REST }
  if FChart.AnimClipCount = 0 then
  begin
    if FChart.AnimLive then Miss(name + ': still live with no clip');
    if FChart.AnimGhostCount <> 0 then Miss(name + ': a ghost outlives its fade');
  end;
end;

procedure TAdvChartAnimMergeTest.TestMergesAsUpstream;
var
  cases: TJSONArray;
  i: Integer;
begin
  cases := Fix.Arrays['cases'];
  AssertTrue('the fixture has its cases', cases.Count >= 13);
  for i := 0 to cases.Count - 1 do RunCase(cases.Objects[i]);
  if FBad > 0 then
    Fail(Format('%d mismatches over %d proxy samples, %d marker samples, %d axis samples, '
      + '%d state samples (%s):%s', [FBad, FCompared, FMarkCompared, FAxisCompared,
      FStateCompared, FTally.CommaText, FReport]));
  { not a vacuous pass }
  AssertTrue(Format('only %d proxy samples', [FCompared]), FCompared >= 3500);
  AssertTrue(Format('only %d marker samples', [FMarkCompared]), FMarkCompared >= 150);
  AssertTrue(Format('only %d axis samples', [FAxisCompared]), FAxisCompared >= 10000);
  AssertTrue(Format('only %d state samples', [FStateCompared]), FStateCompared >= 3000);
end;

{ ==================== by hand ==================== }

const
  cBars = '{"xAxis":{"type":"category","data":["A","B","C","D","E"]},'
    + '"yAxis":{"type":"value","axisLine":{"show":true},"axisTick":{"show":true}},'
    + '"series":[{"type":"bar","data":[5,20,36,10,8]}]}';

{ A MERGE THAT CHANGES AN AXIS' TYPE makes a new model at the same id, of a
  new class: prepareView's '_ec_' + id + '_' + type is another view, and a
  new view never groupTransitions. The x axis, merged as it was, does. }
procedure TAdvChartAnimMergeTest.TestAnAxisWhoseTypeChangesIsANewView;
var
  i, moving: Integer;
  p: TTyChartAnimProxy;
begin
  NewChart(camAlways);
  Load(cBars);
  Settle(T0);
  FChart.AnimNow := T1;
  Merge('{"yAxis":{"type":"log"},"series":[{"data":[5,20,360,10,8]}]}');
  Draw;
  AssertTrue('the axes have proxies', FChart.AnimAxisProxyCount > 0);
  { the new model is the new option alone (a new class drops the old
    one): no axis line, its labels 1, 10, 100 }
  p := FChart.AnimAxisProxy('yAxis0', 'label_10');
  AssertNotNull('label_10, a value both axes have', p);
  AssertEquals('a new view: it does not move', 0, p.AnimatorCount);
  { and the same merge without the type: the y axis moves }
  NewChart(camAlways);
  Load(cBars);
  Settle(T0);
  FChart.AnimNow := T1;
  Merge('{"series":[{"data":[5,20,72,10,8]}]}');
  Draw;
  p := FChart.AnimAxisProxy('yAxis0', 'label_20');
  AssertNotNull('label_20 kept', p);
  AssertEquals('the kept y axis: label_20 moves', 1, p.AnimatorCount);
  moving := 0;
  for i := 0 to 10 do
  begin
    p := FChart.AnimAxisProxy('yAxis0', 'line_' + IntToStr(i * 10));
    if (p <> nil) and (p.AnimatorCount > 0) then Inc(moving);
  end;
  AssertTrue('its split lines too', moving > 0);
end;

{ LAZY: the merge is in the model at once, the update -- the arming, the
  snapshot of the render before it -- waits for the render that does it }
procedure TAdvChartAnimMergeTest.TestALazyMergeArmsAtTheDeferredRender;
var p: TTyChartAnimProxy;
begin
  NewChart(camAlways);
  Load(cBars);
  Settle(T0);
  p := FChart.AnimFindProxy(0, 2, 'bar');
  AssertNotNull('bar C', p);
  FChart.AnimNow := T1;
  Merge('{"series":[{"data":[5,20,12,10,8]}]}', '{"lazyUpdate":true}');
  AssertTrue('merged at once', Pos('12', FChart.GetOptionJson) > 0);
  FChart.AnimTick(T1);
  AssertEquals('nothing armed before the render', 0, FChart.AnimClipCount);
  AssertEquals('no axis proxy yet', 0, FChart.AnimAxisProxyCount);
  Draw;
  p := FChart.AnimFindProxy(0, 2, 'bar');
  AssertNotNull('bar C kept', p);
  AssertTrue('armed by the render', FChart.AnimClipCount > 0);
  AssertEquals('an update of bar C', 1, p.AnimatorCount);
  AssertTrue('the axes transition', FChart.AnimAxisProxyCount > 0);
end;

{ THE POINTER OVER A REUSED ELEMENT through a merge: the same element, so
  moving on it sends no out and no over, and it stays in emphasis }
procedure TAdvChartAnimMergeTest.TestAHoverHeldThroughAMergeSendsNoOver;
var
  p: TTyChartAnimProxy;
  cx, cy: Integer;
begin
  NewChart(camAlways);
  Load('{"xAxis":{"type":"category","data":["A","B","C","D","E"]},'
    + '"yAxis":{"type":"value","max":40,"min":-10},"series":[{"type":"bar","data":[5,20,36,10,-8]}]}');
  Settle(T0);
  p := FChart.AnimFindProxy(0, 2, 'bar');
  AssertNotNull('bar C', p);
  cx := Round(p.Num('shape.x') + p.Num('shape.width') / 2);
  cy := Round(p.Num('shape.y') + p.Num('shape.height') / 2);
  FChart.OnChartEvent := @OnEv;
  FChart.Move(cx, cy);
  AssertTrue('over it', FEvents.IndexOf('mouseover') >= 0);
  FEvents.Clear;
  FChart.AnimNow := T1;
  Merge('{"series":[{"data":[15,8,30,25,4]}]}');
  Draw;
  AssertEquals('still in emphasis', 'emphasis',
    FChart.AnimStateProxy(0, 2, 'host').CurrentStates);
  FChart.Move(cx + 1, cy);
  AssertEquals('no out', -1, FEvents.IndexOf('mouseout'));
  AssertEquals('no over', -1, FEvents.IndexOf('mouseover'));
  AssertTrue('a move', FEvents.IndexOf('mousemove') >= 0);
end;

{ TWO MERGES BEFORE ONE RENDER: the records belong to the render before
  the first; the second finds them taken and carries nothing new over them }
procedure TAdvChartAnimMergeTest.TestTwoMergesBeforeARenderKeepTheHover;
begin
  NewChart(camAlways);
  Load(cBars);
  Settle(T0);
  FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataIndex":2}');
  Draw;
  AssertEquals('highlighted', 'emphasis', FChart.AnimStateProxy(0, 2, 'host').CurrentStates);
  FChart.AnimNow := T1;
  Merge('{"series":[{"data":[15,8,30,25,4]}]}');
  Merge('{"series":[{"data":[6,9,31,24,5]}]}');
  Draw;
  AssertEquals('still highlighted after both', 'emphasis',
    FChart.AnimStateProxy(0, 2, 'host').CurrentStates);
  { and a notMerge after a merge, before a render, the same }
  FChart.AnimNow := T1 + 3000;
  FChart.AnimTick(T1 + 3000);
  Merge('{"series":[{"data":[16,8,30,25,4]}]}');
  FChart.SetOption(StringReplace(cBars, '[5,20,36,10,8]', '[6,8,30,25,4]', []), True);
  Draw;
  AssertEquals('held through merge and notMerge', 'emphasis',
    FChart.AnimStateProxy(0, 2, 'host').CurrentStates);
end;

{ A KEPT MARKPOINT MOVES: its group's place tweens on its proxy, and its
  label -- the symbol path's text -- goes along in the frame }
procedure TAdvChartAnimMergeTest.TestAMarkPointLabelRidesItsSymbol;
var
  p: TTyChartAnimProxy;
  lst, frm: TTyPaintList;
  i, found: Integer;
  a, b: TTyChartElement;
  dy: Double;
begin
  NewChart(camAlways);
  Load('{"xAxis":{"type":"category","data":["A","B","C","D","E"]},"yAxis":{"type":"value","max":40},'
    + '"series":[{"type":"bar","data":[5,20,36,10,8],'
    + '"markPoint":{"data":[{"type":"max","name":"max"}]}}]}');
  Settle(T0);
  FChart.AnimNow := T1;
  Merge('{"series":[{"data":[5,20,12,10,8]}]}');
  Draw;
  p := FChart.AnimFindProxy(0, 0, 'markPoint');
  AssertNotNull('the markPoint kept its proxy', p);
  AssertEquals('it moves, it does not pop in again', 1, p.AnimatorCount);
  FChart.AnimNow := T1 + 250;
  FChart.AnimTick(T1 + 250);
  Draw;
  dy := p.Num('y') - p.FinalOf('y').Num;
  AssertTrue('half way', Abs(dy) > 5);
  lst := FChart.List;
  frm := FChart.Frame;
  AssertTrue('a frame', (frm <> nil) and (frm <> lst));
  found := 0;
  for i := 0 to lst.Count - 1 do
  begin
    a := lst.Element(i);
    if a.Anim.Role <> carMarkPointLabel then Continue;
    b := frm.Element(i);
    AssertEquals('the label rides the symbol', a.Caption.Y + dy, b.Caption.Y, 1e-9);
    Inc(found);
  end;
  AssertEquals('one label', 1, found);
end;

initialization
  RegisterTest(TAdvChartAnimMergeTest);
finalization
  FreeAndNil(GFix);
end.
