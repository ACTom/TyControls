unit test.advchart.decalaria;
{$mode objfpc}{$H+}
{ DECALS AND THE CHART'S DESCRIPTION, held to what ECharts 6.1 does
  [Batch 131]: the tile a decal object generates (its size by the least
  common multiple of the dashes, every symbol's box in brush order), the
  decal every series and every view row is drawn with (the style's, the
  item's, the aria palette's merged under them, the series scope that
  outlives a merge and not a notMerge, the type scope of a series coloured
  by data, the legend's filter), what the bars, the slices, the bands, a
  line's area and the legend icons really carry, and the aria-label text.

  tools/advchart-oracle/decal-aria.js records them under the real dist;
  each case is replayed here and compared bit for bit. The pixel tests check
  that a decal really draws. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.Types,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Color, tyControls.AdvChart.Render,
     tyControls.AdvChart.Legend, tyControls.AdvChart.Decal, tyControls.AdvChart.Aria,
     tyControls.AdvanceChart;
type
  TDaProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartDecalAriaOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TDaProbe;
    FRoot: TJSONObject;
    FBmp: TBGRABitmap;
    FSkin: TTyChartColor;
    FBad, FCompared: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    function Expected(ARec: TJSONObject; ASkinDefault: Boolean): TTyChartDecal;
    procedure CheckResolved(const AWhat: string; const A: TTyChartDecal;
      ARec: TJSONObject; ASkinDefault: Boolean);
    procedure CheckTile(const AWhat: string; const A: TTyChartDecal; ATile: TJSONObject);
    procedure CheckPattern(const AWhat: string; const A: TTyChartDecal;
      APats: TJSONArray; AIdx: TJSONData);
    function FindRowEl(ASeries, ARaw: Integer; out AEl: TTyChartElement): Boolean;
    function FindAreaEl(ASeries: Integer; out AEl: TTyChartElement): Boolean;
    procedure Step(AStep: TJSONObject);
    procedure CheckDecals(ARec: TJSONObject);
    procedure Done(const ATitle: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTilesAsUpstream;
    procedure TestDecalsAsUpstream;
    procedure TestDescriptionsAsUpstream;
  end;

  TAdvChartDecalAriaTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TDaProbe;
    FBmp: TBGRABitmap;
    procedure Load(const AOption: string; AW, AH, APPI: Integer);
    function Px(AX, AY: Integer): TBGRAPixel;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestATileHoldsItsSymbols;
    procedure TestABarWearsItsDecal;
    procedure TestTheRotationTurnsTheRepeat;
    procedure TestAPolarBarWearsItsDecal;
    procedure TestTheTileScalesWithTheDevice;
    procedure TestTheLegendIconWearsTheDecal;
    procedure TestTheUnwrittenColourIsTheSkins;
    procedure TestTheLocaleAndItsSeparators;
    procedure TestReplacementStrings;
  end;

implementation

const
  { upstream's default decal colour: what the port's skin key stands for }
  cUpstreamDefault = 'rgba(0, 0, 0, 0.2)';

procedure TDaProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TDaProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-decal-aria.json';
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Bits(A: Double): QWord;
begin
  Move(A, Result, SizeOf(Result));
end;

function Fmt(A: Double): string;
begin
  if IsNan(A) then Exit('NaN');
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function SameNum(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  Result := Bits(A) = Bits(B);
end;

function IsNull(A: TJSONData): Boolean;
begin
  Result := (A = nil) or (A.JSONType = jtNull);
end;

{ a recorded decal value as the option node it was: "x:<hex>" a number }
function ValToJson(A: TJSONData): TJSONData;
var i: Integer;
begin
  if A = nil then Exit(TJSONNull.Create);
  case A.JSONType of
    jtString:
      if Copy(A.AsString, 1, 2) = 'x:' then
        Result := TJSONFloatNumber.Create(FromHex(Copy(A.AsString, 3, MaxInt)))
      else
        Result := TJSONString.Create(A.AsString);
    jtArray:
      begin
        Result := TJSONArray.Create;
        for i := 0 to A.Count - 1 do TJSONArray(Result).Add(ValToJson(A.Items[i]));
      end;
  else
    Result := A.Clone;
  end;
end;

{ ==================== the replay ==================== }

procedure TAdvChartDecalAriaOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TDaProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, 600, 400);
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  FSkin := TTyChartColor(FCtl.Model.ResolveStyle(TyDecalSkin, '', []).TextColor);
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := TJSONObject(GetJSON(sl.Text));
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartDecalAriaOracleTest.TearDown;
begin
  FRoot.Free;
  FBmp.Free;
  FChart.Controller := nil;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartDecalAriaOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartDecalAriaOracleTest.Done(const ATitle: string);
begin
  if GetEnvironmentVariable('TY_DECALARIA_COUNTS') = '1' then
    WriteLn(ATitle, ': ', FCompared, ' compared');
  AssertEquals(ATitle + ' (' + IntToStr(FCompared) + ' compared):' + FReport, 0, FBad);
end;

{ the decal upstream resolved, normalised by the port: the recorded object
  as the option node it was -- its default colour taken as the skin's where
  ASkinDefault (no option wrote it: globalDefault's six, a decal that named
  none) }
function TAdvChartDecalAriaOracleTest.Expected(ARec: TJSONObject;
  ASkinDefault: Boolean): TTyChartDecal;
var
  o: TJSONObject;
  k: TTyDecalKey;
  v: TJSONData;
begin
  o := TJSONObject.Create;
  try
    for k := Low(TTyDecalKey) to High(TTyDecalKey) do
    begin
      v := ARec.Find(TyDecalKeyNames[k]);
      if ASkinDefault and (k = dkColor) and (v <> nil) and (v.JSONType = jtString)
        and (v.AsString = cUpstreamDefault) then Continue;
      o.Add(TyDecalKeyNames[k], ValToJson(v));
    end;
    Result := TyDecalResolve(TyDecalRawOf(o), FSkin);
  finally
    o.Free;
  end;
end;

procedure TAdvChartDecalAriaOracleTest.CheckResolved(const AWhat: string;
  const A: TTyChartDecal; ARec: TJSONObject; ASkinDefault: Boolean);
var
  e: TTyChartDecal;
  i, j: Integer;
  ok: Boolean;
begin
  e := Expected(ARec, ASkinDefault);
  Inc(FCompared);
  if not A.Present then
  begin
    Miss(AWhat + ': no decal here');
    Exit;
  end;
  ok := Length(A.Symbols) = Length(e.Symbols);
  if ok then
    for i := 0 to High(e.Symbols) do
    begin
      ok := ok and (Length(A.Symbols[i]) = Length(e.Symbols[i]));
      if ok then
        for j := 0 to High(e.Symbols[i]) do ok := ok and (A.Symbols[i][j] = e.Symbols[i][j]);
    end;
  if not ok then Miss(AWhat + ': the symbols differ');
  Inc(FCompared, 8);
  if not SameNum(A.SymbolSize, e.SymbolSize) then
    Miss(Format('%s: symbolSize %s upstream, %s here', [AWhat, Fmt(e.SymbolSize), Fmt(A.SymbolSize)]));
  if A.KeepAspect <> e.KeepAspect then Miss(AWhat + ': keepAspect');
  if A.Color <> e.Color then
    Miss(Format('%s: colour $%.8x upstream, $%.8x here', [AWhat, e.Color, A.Color]));
  if (A.HasBackground <> e.HasBackground)
    or (A.HasBackground and (A.Background <> e.Background)) then
    Miss(AWhat + ': the background');
  if not SameNum(A.Rotation, e.Rotation) then
    Miss(Format('%s: rotation %s upstream, %s here', [AWhat, Fmt(e.Rotation), Fmt(A.Rotation)]));
  if not (SameNum(A.MaxTileW, e.MaxTileW) and SameNum(A.MaxTileH, e.MaxTileH)) then
    Miss(AWhat + ': the tile maxima');
  ok := Length(A.DashX) = Length(e.DashX);
  if ok then
    for i := 0 to High(e.DashX) do
    begin
      ok := ok and (Length(A.DashX[i]) = Length(e.DashX[i]));
      if ok then
        for j := 0 to High(e.DashX[i]) do ok := ok and SameNum(A.DashX[i][j], e.DashX[i][j]);
    end;
  if not ok then Miss(AWhat + ': dashArrayX');
  ok := Length(A.DashY) = Length(e.DashY);
  if ok then
    for i := 0 to High(e.DashY) do ok := ok and SameNum(A.DashY[i], e.DashY[i]);
  if not ok then Miss(AWhat + ': dashArrayY');
end;

procedure TAdvChartDecalAriaOracleTest.CheckTile(const AWhat: string;
  const A: TTyChartDecal; ATile: TJSONObject);
var
  t: TTyDecalTile;
  syms: TJSONArray;
  s: TJSONObject;
  i: Integer;
begin
  t := TyDecalTile(A);
  Inc(FCompared, 3);
  if not SameNum(t.W, ATile.Floats['w']) or not SameNum(t.H, ATile.Floats['h']) then
    Miss(Format('%s: the tile is %s x %s upstream, %s x %s here', [AWhat,
      Fmt(ATile.Floats['w']), Fmt(ATile.Floats['h']), Fmt(t.W), Fmt(t.H)]));
  if not SameNum(A.Rotation, FromHex(ATile.Strings['rotation'])) then
    Miss(AWhat + ': the pattern''s rotation');
  syms := ATile.Arrays['symbols'];
  if Length(t.Symbols) <> syms.Count then
  begin
    Miss(Format('%s: %d symbols upstream, %d here', [AWhat, syms.Count, Length(t.Symbols)]));
    Exit;
  end;
  for i := 0 to syms.Count - 1 do
  begin
    s := syms.Objects[i];
    Inc(FCompared, 5);
    if t.Symbols[i].Kind <> s.Strings['type'] then
      Miss(Format('%s: symbol %d is %s upstream, %s here', [AWhat, i, s.Strings['type'], t.Symbols[i].Kind]));
    if not (SameNum(t.Symbols[i].X, FromHex(s.Strings['x']))
      and SameNum(t.Symbols[i].Y, FromHex(s.Strings['y']))
      and SameNum(t.Symbols[i].W, FromHex(s.Strings['w']))
      and SameNum(t.Symbols[i].H, FromHex(s.Strings['h']))) then
      Miss(Format('%s: symbol %d at (%s, %s, %s, %s) upstream, (%s, %s, %s, %s) here',
        [AWhat, i, Fmt(FromHex(s.Strings['x'])), Fmt(FromHex(s.Strings['y'])),
         Fmt(FromHex(s.Strings['w'])), Fmt(FromHex(s.Strings['h'])),
         Fmt(t.Symbols[i].X), Fmt(t.Symbols[i].Y), Fmt(t.Symbols[i].W), Fmt(t.Symbols[i].H)]));
  end;
end;

procedure TAdvChartDecalAriaOracleTest.CheckPattern(const AWhat: string;
  const A: TTyChartDecal; APats: TJSONArray; AIdx: TJSONData);
var p: TJSONObject;
begin
  Inc(FCompared);
  if IsNull(AIdx) then
  begin
    if A.Present then Miss(AWhat + ': no decal upstream, one here');
    Exit;
  end;
  if AIdx.JSONType <> jtNumber then Exit;
  if not A.Present then
  begin
    Miss(AWhat + ': a decal upstream, none here');
    Exit;
  end;
  p := APats.Objects[AIdx.AsInteger];
  if p.Find('resolved') is TJSONObject then
    CheckResolved(AWhat, A, p.Objects['resolved'], True);
  CheckTile(AWhat, A, p.Objects['tile']);
end;

function TAdvChartDecalAriaOracleTest.FindRowEl(ASeries, ARaw: Integer;
  out AEl: TTyChartElement): Boolean;
var
  k: Integer;
  e: TTyChartElement;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  for k := 0 to FChart.List.Count - 1 do
  begin
    e := FChart.List.Element(k);
    if e.Ignore or (e.Datum.Kind <> ctkSeries) then Continue;
    if (e.Datum.SeriesIndex <> ASeries) or (e.Datum.RawDataIndex <> ARaw) then Continue;
    if (e.Caption.Text <> '') or (e.Shape.Kind = cskPolyline) or e.Silent then Continue;
    AEl := e;
    Exit(True);
  end;
end;

function TAdvChartDecalAriaOracleTest.FindAreaEl(ASeries: Integer;
  out AEl: TTyChartElement): Boolean;
var
  k: Integer;
  e: TTyChartElement;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  for k := 0 to FChart.List.Count - 1 do
  begin
    e := FChart.List.Element(k);
    if e.Ignore or (e.Datum.Kind <> ctkSeries) then Continue;
    if (e.Datum.SeriesIndex <> ASeries) or (e.Datum.DataIndex <> -1) then Continue;
    if not (e.Style.HasFill and (e.Shape.Kind = cskPolygon)) then Continue;
    AEl := e;
    Exit(True);
  end;
end;

procedure TAdvChartDecalAriaOracleTest.Step(AStep: TJSONObject);
var opt: TJSONObject;
begin
  opt := TJSONObject(AStep.Objects['option'].Clone);
  try
    if AStep.Booleans['merge'] then
      FChart.SetOption(opt.AsJSON, False)
    else
    begin
      opt.Add('animation', False);
      FChart.SetOption(opt.AsJSON, True);
    end;
  finally
    opt.Free;
  end;
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 600, 400), 96);
end;

procedure TAdvChartDecalAriaOracleTest.CheckDecals(ARec: TJSONObject);
var
  pats, series, raws, items, drawn, legend: TJSONArray;
  s, it: TJSONObject;
  i, v, si, raw, j: Integer;
  typ: string;
  el: TTyChartElement;
  lay: TTyLegendLayout;
  found: Boolean;
begin
  pats := ARec.Arrays['patterns'];
  series := ARec.Arrays['series'];
  for i := 0 to series.Count - 1 do
  begin
    s := series.Objects[i];
    si := s.Integers['index'];
    typ := s.Strings['type'];
    { a sunburst and a treemap decide their own decals: not drawn here }
    if (typ = 'sunburst') or (typ = 'treemap') then Continue;
    CheckPattern(Format('series %d', [si]), FChart.DecalOfSeries(si), pats, s.Find('decal'));
    raws := s.Arrays['raws'];
    items := s.Arrays['items'];
    drawn := s.Arrays['drawn'];
    for v := 0 to raws.Count - 1 do
    begin
      raw := raws.Integers[v];
      CheckPattern(Format('series %d row %d', [si, raw]), FChart.DecalOfRow(si, raw),
        pats, items.Items[v]);
      if (drawn.Items[v].JSONType = jtString) then Continue;
      Inc(FCompared);
      if not FindRowEl(si, raw, el) then
      begin
        Miss(Format('series %d row %d: no element', [si, raw]));
        Continue;
      end;
      CheckPattern(Format('series %d row %d drawn', [si, raw]), el.Style.Decal,
        pats, drawn.Items[v]);
    end;
    if s.Find('area').JSONType <> jtString then
    begin
      Inc(FCompared);
      if not FindAreaEl(si, el) then
        Miss(Format('series %d: no area', [si]))
      else
        CheckPattern(Format('series %d area', [si]), el.Style.Decal, pats, s.Find('area'));
    end;
  end;
  legend := ARec.Arrays['legend'];
  if legend.Count > 0 then
  begin
    lay := FChart.LegendLayout(0);
    for i := 0 to legend.Count - 1 do
    begin
      it := legend.Objects[i];
      found := False;
      for j := 0 to High(lay.Items) do
        if lay.Items[j].Name = it.Strings['name'] then
        begin
          found := True;
          CheckPattern('legend ' + it.Strings['name'], lay.Items[j].Decal, pats, it.Find('decal'));
        end;
      Inc(FCompared);
      if not found then Miss('legend ' + it.Strings['name'] + ': no item');
    end;
  end;
end;

procedure TAdvChartDecalAriaOracleTest.TestTilesAsUpstream;
var
  tiles: TJSONArray;
  t: TJSONObject;
  i: Integer;
  dec: TTyChartDecal;
begin
  tiles := FRoot.Arrays['tiles'];
  AssertTrue('the fixture has tiles', tiles.Count > 30);
  for i := 0 to tiles.Count - 1 do
  begin
    t := tiles.Objects[i];
    FName := 'tile ' + t.Strings['id'];
    { THE OPTION AS WRITTEN, read by the port: its normalisation, then its
      tile -- the colour an unwritten one leaves is the skin's }
    dec := TyDecalResolve(TyDecalRawOf(t.Objects['decal']), FSkin);
    { the case wrote its colour when it has one: the port reads it }
    CheckResolved('resolved', dec, t.Objects['resolved'],
      t.Objects['decal'].Find('color') = nil);
    CheckTile('tile', dec, t.Objects['tile']);
  end;
  Done('tiles');
end;

procedure TAdvChartDecalAriaOracleTest.TestDecalsAsUpstream;
var
  scs, steps, ser: TJSONArray;
  sc, st, rec: TJSONObject;
  i, j, k: Integer;
begin
  scs := FRoot.Arrays['scenarios'];
  for i := 0 to scs.Count - 1 do
  begin
    sc := scs.Objects[i];
    if Copy(sc.Strings['id'], 1, 6) = 'label-' then Continue;
    steps := sc.Arrays['steps'];
    for j := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[j];
      FName := sc.Strings['id'] + '#' + IntToStr(j);
      Step(st);
      rec := st.Objects['record'];
      if not IsNull(rec.Find('error')) then
      begin
        { UPSTREAM THREW (a decal written as a string, a visualMap decal on
          pieces or a continuous map, an empty decal palette): the port
          draws no decal at all }
        Inc(FCompared);
        for k := 0 to 7 do
          if FChart.DecalOfSeries(k).Present or FChart.DecalOfRow(k, 0).Present
            or FChart.DecalOfRow(k, 1).Present then
            Miss(Format('series %d: a decal where upstream threw', [k]));
        Continue;
      end;
      ser := rec.Arrays['series'];
      if ser = nil then Continue;
      CheckDecals(rec);
    end;
  end;
  Done('decals');
end;

procedure TAdvChartDecalAriaOracleTest.TestDescriptionsAsUpstream;
var
  scs, steps: TJSONArray;
  sc, st, rec: TJSONObject;
  i, j: Integer;
  want, got: string;
  d: TJSONData;
begin
  scs := FRoot.Arrays['scenarios'];
  for i := 0 to scs.Count - 1 do
  begin
    sc := scs.Objects[i];
    steps := sc.Arrays['steps'];
    for j := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[j];
      FName := sc.Strings['id'] + '#' + IntToStr(j);
      Step(st);
      rec := st.Objects['record'];
      if not IsNull(rec.Find('error')) then Continue;
      { a sunburst's rows are its tree's nodes, the virtual root first:
        not the port's store }
      if sc.Strings['id'] = 'sunburst' then Continue;
      d := rec.Objects['aria'].Find('label');
      if IsNull(d) then want := '' else want := d.AsString;
      got := FChart.AriaDescription;
      Inc(FCompared);
      if got <> want then
        Miss(LineEnding + '    upstream: ' + want + LineEnding + '    here:     ' + got);
    end;
  end;
  Done('descriptions');
end;

{ ==================== the hand-written ones ==================== }

procedure TAdvChartDecalAriaTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TDaProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := nil;
end;

procedure TAdvChartDecalAriaTest.TearDown;
begin
  FBmp.Free;
  FChart.Controller := nil;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartDecalAriaTest.Load(const AOption: string; AW, AH, APPI: Integer);
var dw, dh: Integer;
begin
  dw := AW * APPI div 96;
  dh := AH * APPI div 96;
  FBmp.Free;
  FBmp := TBGRABitmap.Create(dw, dh, BGRA(255, 255, 255, 255));
  FChart.Option := '{}';
  FChart.Option := AOption;
  FChart.SetBounds(0, 0, AW, AH);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, dw, dh), APPI);
end;

function TAdvChartDecalAriaTest.Px(AX, AY: Integer): TBGRAPixel;
begin
  Result := FBmp.GetPixel(AX, AY);
end;

function DecalOf(const AJson: string; ASkin: TTyChartColor): TTyChartDecal;
var d: TJSONData;
begin
  d := GetJSON(AJson);
  try
    Result := TyDecalResolve(TyDecalRawOf(d), ASkin);
  finally
    d.Free;
  end;
end;

procedure TAdvChartDecalAriaTest.TestATileHoldsItsSymbols;
var
  dec: TTyChartDecal;
  img: TBGRABitmap;
begin
  { globalDefault's second: circles of radius 2.4 (min(6.4, 4.8) / 2) on a
    16 x 12 tile -- the rows start a block above it, so the band y 0..6
    takes the second line ([0, 8, 8, 0]: its circle at (12, 3)) and the band
    6..12 the first ([8, 8]: at (4, 9)) }
  dec := DecalOf('{"symbol":"circle","dashArrayX":[[8,8],[0,8,8,0]],'
    + '"dashArrayY":[6,0],"symbolSize":0.8,"color":"#ff0000"}', 0);
  img := TyDecalTileImage(dec, 1);
  AssertTrue('a tile', img <> nil);
  AssertEquals('16 wide', 16, img.Width);
  AssertEquals('12 high', 12, img.Height);
  AssertTrue('the circle at (12, 3)', img.GetPixel(12, 3).alpha > 200);
  AssertEquals('in the decal''s colour', 255, Integer(img.GetPixel(12, 3).red));
  AssertTrue('the circle at (4, 9)', img.GetPixel(4, 9).alpha > 200);
  AssertEquals('nothing at (4, 3): the line there starts with a gap', 0,
    Integer(img.GetPixel(4, 3).alpha));
  AssertEquals('nothing at (12, 9)', 0, Integer(img.GetPixel(12, 9).alpha));
  AssertEquals('nothing between the bands', 0, Integer(img.GetPixel(8, 6).alpha));
  { a background fills the tile first }
  dec := DecalOf('{"symbol":"circle","dashArrayX":[[8,8],[0,8,8,0]],'
    + '"dashArrayY":[6,0],"symbolSize":0.8,"color":"#ff0000","backgroundColor":"#0000ff"}', 0);
  img := TyDecalTileImage(dec, 1);
  AssertEquals('the background between the circles', 255, Integer(img.GetPixel(4, 3).blue));
  AssertEquals('opaque', 255, Integer(img.GetPixel(4, 3).alpha));
  { dashes that make no tile draw nothing and do not crash }
  dec := DecalOf('{"dashArrayY":[0,0]}', $FF000000);
  img := TyDecalTileImage(dec, 1);
  AssertTrue('an empty tile is still a tile', img <> nil);
  AssertEquals('with nothing on it', 0, Integer(img.GetPixel(0, 0).alpha));
end;

procedure TAdvChartDecalAriaTest.TestABarWearsItsDecal;
var
  x, y, red, other: Integer;
  p: TBGRAPixel;
  el: TTyChartElement;
  k: Integer;
  found: Boolean;
begin
  { one wide red bar under a black decal of 4 x 4 squares every 8 px }
  Load('{"animation":false,"grid":{"left":0,"right":0,"top":0,"bottom":0},'
    + '"xAxis":{"data":["a"],"show":false},"yAxis":{"show":false,"max":10},'
    + '"series":[{"type":"bar","barWidth":"100%","itemStyle":{"color":"#ff0000",'
    + '"decal":{"color":"#000000","dashArrayX":[4,4],"dashArrayY":[4,4]}},'
    + '"data":[10]}]}', 200, 100, 96);
  red := 0;
  other := 0;
  for y := 10 to 89 do
    for x := 10 to 189 do
    begin
      p := Px(x, y);
      if (p.red = 255) and (p.green = 0) and (p.blue = 0) then Inc(red)
      else if (p.red < 10) and (p.green < 10) and (p.blue < 10) then Inc(other);
    end;
  AssertTrue('the bar''s own red shows', red > 3000);
  AssertTrue('and the decal''s black squares over it', other > 3000);
  { the decal is in CANVAS space: the square at (0..4, 0..4) of every 8 }
  AssertTrue('a decal square at (17, 17)', Px(17, 17).red < 10);
  AssertEquals('the bar between them at (21, 17)', 255, Integer(Px(21, 17).red));
  found := False;
  for k := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(k);
    if (el.Datum.SeriesIndex = 0) and (el.Datum.DataIndex = 0) and (el.Caption.Text = '') then
      found := found or el.Style.Decal.Present;
  end;
  AssertTrue('the bar element carries the decal', found);
  { no decal, no squares }
  Load('{"animation":false,"grid":{"left":0,"right":0,"top":0,"bottom":0},'
    + '"xAxis":{"data":["a"],"show":false},"yAxis":{"show":false,"max":10},'
    + '"series":[{"type":"bar","barWidth":"100%","itemStyle":{"color":"#ff0000"},'
    + '"data":[10]}]}', 200, 100, 96);
  AssertEquals('only red without one', 255, Integer(Px(17, 17).red));
  AssertEquals('only red without one (green)', 0, Integer(Px(17, 17).green));
end;

procedure TAdvChartDecalAriaTest.TestTheRotationTurnsTheRepeat;
var
  dec: TTyChartDecal;
  m: TTyDoubleArray;
begin
  { a quarter turn: the matrix turns the tile, and only turns it }
  dec := DecalOf('{"rotation":1.5707963267948966}', 0);
  TyDecalMatrix(dec, 1, m);
  AssertEquals('cos', 0, m[0], 1e-15);
  AssertEquals('sin', 1, m[1], 1e-15);
  AssertEquals('-sin', -1, m[2], 1e-15);
  AssertEquals('cos again', 0, m[3], 1e-15);
  AssertEquals('no move x', 0, m[4], 0);
  AssertEquals('no move y', 0, m[5], 0);
  { full-height stripes 2 wide every 8, turned a quarter, run across: one
    row is ink end to end, a row four below is clear }
  Load('{"animation":false,"grid":{"left":0,"right":0,"top":0,"bottom":0},'
    + '"xAxis":{"data":["a"],"show":false},"yAxis":{"show":false,"max":10},'
    + '"series":[{"type":"bar","barWidth":"100%","itemStyle":{"color":"#ffffff",'
    + '"decal":{"color":"#000000","dashArrayX":[2,6],"dashArrayY":[1,0],'
    + '"rotation":1.5707963267948966}},"data":[10]}]}', 200, 100, 96);
  { canvas space, turned about its origin: the pattern's x band [0, 2)
    lands on y [0, 2) of every 8 -- a turn the other way would put it on
    [6, 8) }
  AssertTrue('ink on y 33', Px(40, 33).red < 128);
  AssertTrue('the same row across', Px(120, 33).red < 128);
  AssertTrue('clear on y 37', Px(40, 37).red > 128);
  AssertTrue('clear on y 39', Px(40, 39).red > 128);
end;

procedure TAdvChartDecalAriaTest.TestAPolarBarWearsItsDecal;
var
  k, n: Integer;
  el: TTyChartElement;
begin
  { a bar on a polar takes the same row decal a cartesian one does }
  Load('{"animation":false,"polar":{},"angleAxis":{"type":"category","data":["a","b"]},'
    + '"radiusAxis":{},"series":[{"type":"bar","coordinateSystem":"polar",'
    + '"itemStyle":{"decal":{"symbol":"circle"}},'
    + '"data":[1,{"value":2,"itemStyle":{"decal":{"symbol":"triangle"}}}]}]}', 400, 300, 96);
  n := 0;
  for k := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(k);
    if (el.Datum.SeriesIndex <> 0) or (el.Datum.DataIndex < 0) or (el.Caption.Text <> '') then Continue;
    if not el.Style.Decal.Present then Continue;
    Inc(n);
    if el.Datum.DataIndex = 0 then
      AssertEquals('the series'' decal on the first', 'circle', el.Style.Decal.Symbols[0][0])
    else
      AssertEquals('the item''s own on the second', 'triangle', el.Style.Decal.Symbols[0][0]);
  end;
  AssertEquals('both sectors carry one', 2, n);
end;

procedure TAdvChartDecalAriaTest.TestTheTileScalesWithTheDevice;
var
  dec: TTyChartDecal;
  img: TBGRABitmap;
  m: TTyDoubleArray;
begin
  { canvas.width = width * dpr, the pattern scaled back by 1 / dpr: at 2x the
    tile has four times the pixels and the matrix is the unit }
  dec := DecalOf('{}', $FF000000);
  img := TyDecalTileImage(dec, 2);
  AssertEquals('20 px for 10 css px', 20, img.Width);
  AssertEquals('20 high', 20, img.Height);
  TyDecalMatrix(dec, 2, m);
  AssertEquals('the unit', 1, m[0], 1e-15);
  AssertEquals('the unit', 1, m[3], 1e-15);
  { 1.25x: 12.5, which a canvas' width truncates }
  img := TyDecalTileImage(dec, 1.25);
  AssertEquals('12.5 truncated', 12, img.Width);
end;

procedure TAdvChartDecalAriaTest.TestTheLegendIconWearsTheDecal;
var
  lay: TTyLegendLayout;
  k, n: Integer;
  el: TTyChartElement;
begin
  Load('{"animation":false,"aria":{"decal":{"show":true}},"legend":{},'
    + '"xAxis":{"data":["a"]},"yAxis":{},'
    + '"series":[{"type":"bar","name":"A","data":[1]},{"type":"bar","name":"B","data":[2]}]}',
    400, 300, 96);
  lay := FChart.LegendLayout(0);
  AssertEquals('two items', 2, Length(lay.Items));
  AssertTrue('A wears one', lay.Items[0].Decal.Present);
  AssertTrue('B wears another', lay.Items[1].Decal.Present);
  AssertFalse('not the same', lay.Items[0].Decal.SymbolSize = lay.Items[1].Decal.SymbolSize);
  n := 0;
  for k := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(k);
    { the icons carry no datum (the item's hit rect does) }
    if el.Style.Decal.Present and (el.Datum.SeriesIndex < 0) then Inc(n);
  end;
  AssertEquals('both icons are drawn with it', 2, n);
end;

procedure TAdvChartDecalAriaTest.TestTheUnwrittenColourIsTheSkins;
var
  dec: TTyChartDecal;
  skin: TTyChartColor;
begin
  Load('{"animation":false,"aria":{"decal":{"show":true}},'
    + '"xAxis":{"data":["a"]},"yAxis":{},"series":[{"type":"bar","data":[1]},'
    + '{"type":"bar","data":[1],"itemStyle":{"decal":{"color":"red"}}}]}', 400, 300, 96);
  skin := TTyChartColor(FCtl.Model.ResolveStyle(TyDecalSkin, '', []).TextColor);
  AssertTrue('the skin key has a colour', (skin shr 24) > 0);
  dec := FChart.DecalOfSeries(0);
  AssertTrue('a decal', dec.Present);
  AssertEquals('the built-in decal takes the skin''s colour', Int64(skin), Int64(dec.Color));
  AssertEquals('a written one is the author''s', Int64($FFFF0000),
    Int64(FChart.DecalOfSeries(1).Color));
  AssertTrue('and keeps the palette''s shape under it',
    Abs(FChart.DecalOfSeries(1).SymbolSize - 0.8) < 1e-12);
end;

procedure TAdvChartDecalAriaTest.TestTheLocaleAndItsSeparators;
var
  loc: TTyAriaLocale;
  f: TTyAriaFacts;
begin
  loc := TyAriaDefaultLocale;
  AssertEquals('no separator between series in English', '', loc.SeriesMiddle);
  AssertEquals('nor after them', '', loc.SeriesEnd);
  AssertEquals('a comma between values', ', ', loc.DataMiddle);
  AssertEquals('a full stop after them', '. ', loc.DataEnd);
  AssertEquals('an unknown type is a chart', 'Chart', TyAriaTypeName('nope'));
  f := Default(TTyAriaFacts);
  AssertEquals('no series, no sentence', '', TyAriaLabel(loc, f));
  f.SeriesCount := 1;
  f.MaxData := 10;
  f.MaxDataText := '10';
  f.MaxSeries := 10;
  SetLength(f.Series, 1);
  f.Series[0].TypeName := 'Bar chart';
  SetLength(f.Series[0].Rows, 1);
  f.Series[0].Rows[0].Name := 'a';
  f.Series[0].Rows[0].Values := ['0', '1'];
  AssertEquals('one series',
    'This is a chart with type Bar chart.The data is as follows: the data for a is 0, 1. ',
    TyAriaLabel(loc, f));
end;

procedure TAdvChartDecalAriaTest.TestReplacementStrings;
begin
  AssertEquals('blanks inside the braces', '[x] [x]',
    TyAriaReplace('[{a}] [{ a }]', ['a'], ['x']));
  AssertEquals('$& is the match, $$ a dollar', '<{a}$>',
    TyAriaReplace('<{a}>', ['a'], ['$&$$']));
  AssertEquals('$` what came before, $'' what comes after', 'pq-pq--r-r',
    TyAriaReplace('pq-{a}-r', ['a'], ['$`$''']));
  AssertEquals('a value holding a later key is replaced too', 'xBy',
    TyAriaReplace('{a}', ['a', 'b'], ['x{b}y', 'B']));
  AssertEquals('an unmatched brace stays', '{a', TyAriaReplace('{a', ['a'], ['x']));
end;

initialization
  RegisterTest(TAdvChartDecalAriaOracleTest);
  RegisterTest(TAdvChartDecalAriaTest);

end.
