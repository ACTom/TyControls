unit test.advchart.visualmappiecewise;
{$mode objfpc}{$H+}
{ The piecewise visualMap's model and encoding -- the pieces its three
  modes build, the selected map, the completed target and controller
  visuals and the mappings made of them, what each targeted datum is
  given, the piecewise visualMeta and the gradient a line makes of it --
  held to what ECharts 6.1 itself computes.

  tools/advchart-oracle/visualmap-piecewise.js runs the real build and
  records the model's piece list after resetMethods (splitNumber with its
  precision write-back, pieces through reformIntervals, categories reversed
  when vertical), each piece's key, selection, representative value and
  state, the mappings with their method and visual, every row's piece, state
  and visuals, the visualMetas and the line's paint.

  EXACT. Doubles bit for bit; colours as zrender holds them, then as the
  drawn element carries them, packed here rather than by the port.

  The view -- item groups, ends texts, layout -- is B4b's. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Shape, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Scale,
     tyControls.AdvChart.VisualMap, tyControls.AdvanceChart;
type
  TVmpProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartVisualMapPiecewiseOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TVmpProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport: string;
    FName: string;
    procedure Miss(const AWhat: string);
    procedure CheckModel(AVm: TJSONObject);
    procedure CheckPieces(const ASpec: TTyVisualMapSpec; AVm: TJSONObject);
    procedure CheckMappings(const AWhat: string; const AMaps: TTyVisualMappingArray;
      const ASpec: TTyVisualMapSpec; AList: TJSONArray);
    procedure CheckSeries(AOption, ASeries: TJSONObject);
    procedure CheckMetas(ASeries: TJSONObject);
    procedure CheckLine(ASeries: TJSONObject);
    procedure RunCases(const AIds: array of string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSplitNumberAsUpstream;
    procedure TestPiecesAsUpstream;
    procedure TestCategoriesAsUpstream;
    procedure TestViewCasesEncodeAsUpstream;
    procedure TestLineMetasAsUpstream;
    procedure TestGalleryAsUpstream;
    procedure TestTheNoteIsGone;
  end;

implementation

const
  cPalette = '["#5070dd","#b6d634","#505372","#ff994d","#0ca8df","#ffd10a",'
    + '"#fb628b","#785db0","#3fbe95"]';
  cStates: array[TTyVisualState] of string = ('inRange', 'outOfRange');

procedure TVmpProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TVmpProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-visualmap-piecewise.json';
end;

function GalleryPath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'examples'
    + PathDelim + 'advchart' + PathDelim + 'gallery' + PathDelim + AName + '.json';
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

function SameBits(A: Double; const AHex: string): Boolean;
begin
  Result := Bits(A) = Bits(FromHex(AHex));
end;

function Fmt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function IsNull(AData: TJSONData): Boolean;
begin
  Result := (AData = nil) or (AData.JSONType = jtNull);
end;

function ColourText(const C: TTyVisualColor): string;
begin
  if not C.Defined then Exit('undefined');
  Result := Format('(%s,%s,%s,%s)', [Fmt(C.R), Fmt(C.G), Fmt(C.B), Fmt(C.A)]);
end;

function FixColour(AObj: TJSONObject): TTyVisualColor;
begin
  if AObj.Booleans['undef'] then Exit(TyVisualUndefined);
  Result := TyVisualRgba(AObj.Integers['r'], AObj.Integers['g'],
    AObj.Integers['b'], FromHex(AObj.Strings['a']));
end;

function SameColour(const C: TTyVisualColor; AObj: TJSONObject): Boolean;
begin
  if AObj.Booleans['undef'] then Exit(not C.Defined);
  Result := C.Defined and (C.R = AObj.Integers['r'])
    and (C.G = AObj.Integers['g']) and (C.B = AObj.Integers['b'])
    and SameBits(C.A, AObj.Strings['a']);
end;

{ A colour string as zrender parses it for a mapping: an unparsable one is
  black, as setVisualToOption falls back }
function ParsedOf(const AText: string): TTyVisualColor;
begin
  if not TyVisualTryParse(AText, Result) then Result := TyVisualRgba(0, 0, 0, 1);
end;

function SameVisual(const A, B: TTyVisualColor): Boolean;
begin
  Result := (A.Defined = B.Defined) and (not A.Defined
    or ((A.R = B.R) and (A.G = B.G) and (A.B = B.B) and (Bits(A.A) = Bits(B.A))));
end;

{ packed here, not by TyVisualToChart }
function PackFix(AObj: TJSONObject): TTyChartColor;
  function B(A: Double): Cardinal;
  begin
    Result := Cardinal(Floor(A + 0.5));
  end;
begin
  if AObj.Booleans['undef'] then Exit(0);
  Result := TTyChartColor((B(FromHex(AObj.Strings['a']) * 255) shl 24)
    or (B(AObj.Integers['r']) shl 16) or (B(AObj.Integers['g']) shl 8)
    or B(AObj.Integers['b']));
end;

function KeysText(const AKeys: TTyStringArray): string;
var i: Integer;
begin
  Result := '[';
  for i := 0 to High(AKeys) do
  begin
    if i > 0 then Result := Result + ', ';
    Result := Result + '"' + AKeys[i] + '"';
  end;
  Result := Result + ']';
end;

function ObjKeysText(AObj: TJSONObject): string;
var i: Integer;
begin
  Result := '[';
  if AObj <> nil then
    for i := 0 to AObj.Count - 1 do
    begin
      if i > 0 then Result := Result + ', ';
      Result := Result + '"' + AObj.Names[i] + '"';
    end;
  Result := Result + ']';
end;

function KindsText(const AMaps: TTyVisualMappingArray): string;
var i: Integer;
begin
  Result := '[';
  for i := 0 to High(AMaps) do
  begin
    if i > 0 then Result := Result + ', ';
    Result := Result + '"' + AMaps[i].Kind + '"';
  end;
  Result := Result + ']';
end;

function ArrText(AArr: TJSONArray): string;
var i: Integer;
begin
  Result := '[';
  if AArr <> nil then
    for i := 0 to AArr.Count - 1 do
    begin
      if i > 0 then Result := Result + ', ';
      Result := Result + '"' + AArr.Items[i].AsString + '"';
    end;
  Result := Result + ']';
end;

function ItemNode(AOption: TJSONObject; ASeries, ARow: Integer): TJSONObject;
var d, s: TJSONData;
begin
  Result := nil;
  d := AOption.Find('series');
  if d = nil then Exit;
  if d.JSONType = jtArray then
  begin
    if ASeries >= TJSONArray(d).Count then Exit;
    s := TJSONArray(d).Items[ASeries];
  end
  else
    s := d;
  if s.JSONType <> jtObject then Exit;
  d := TJSONObject(s).Find('data');
  if (d = nil) or (d.JSONType <> jtArray) or (ARow >= TJSONArray(d).Count) then Exit;
  d := TJSONArray(d).Items[ARow];
  if d.JSONType = jtObject then Result := TJSONObject(d);
end;

function ItemHas(AOption: TJSONObject; ASeries, ARow: Integer;
  const AKey: string): Boolean;
var o: TJSONObject;
begin
  o := ItemNode(AOption, ASeries, ARow);
  Result := (o <> nil) and (o.FindPath('itemStyle.' + AKey) <> nil);
end;

{ the piece visual record against the fixture's: a colour as a colour
  record, anything else as written }
function SamePieceVisual(const AV: TTyVisualPieceVisual; AData: TJSONData): Boolean;
var c: TTyVisualColor;
begin
  if IsNull(AData) then Exit(not AV.Defined);
  if not AV.Defined then Exit(False);
  if AV.Kind = 'color' then
  begin
    if AData.JSONType <> jtObject then Exit(False);
    if not TyVisualTryParse(AV.Str, c) then c := TyVisualUndefined;
    Exit(SameColour(c, TJSONObject(AData)));
  end;
  case AData.JSONType of
    jtNumber: Result := AV.IsNum and (Bits(AV.Num) = Bits(AData.AsFloat));
    jtString: Result := (not AV.IsNum) and (AV.Str = AData.AsString);
  else
    Result := False;
  end;
end;

procedure TAdvChartVisualMapPiecewiseOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TVmpProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(800, 600, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartVisualMapPiecewiseOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  FreeAndNil(FBmp);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartVisualMapPiecewiseOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

{ ==================== the model ==================== }

procedure TAdvChartVisualMapPiecewiseOracleTest.CheckPieces(
  const ASpec: TTyVisualMapSpec; AVm: TJSONObject);
var
  arr: TJSONArray;
  p, v: TJSONObject;
  i, k: Integer;
  pc: TTyVisualPiece;
  rv: Double;
  text: string;
  st: TTyVisualState;
  sel: TJSONObject;
  keys: TTyStringArray;
begin
  arr := AVm.Arrays['pieces'];
  Inc(FCompared);
  if Length(ASpec.Pieces) <> arr.Count then
  begin
    Miss(Format('%d pieces upstream, %d here', [arr.Count, Length(ASpec.Pieces)]));
    Exit;
  end;
  { THE SELECTED MAP holds exactly the pieces' keys }
  sel := AVm.Objects['model'].Objects['selected'];
  SetLength(keys, Length(ASpec.Pieces));
  for i := 0 to High(ASpec.Pieces) do keys[i] := ASpec.Pieces[i].Key;
  Inc(FCompared);
  if sel.Count <> Length(ASpec.Pieces) then
    Miss(Format('selected keys %s upstream, pieces %s here', [ObjKeysText(sel),
      KeysText(keys)]));
  for i := 0 to arr.Count - 1 do
  begin
    p := arr.Objects[i];
    pc := ASpec.Pieces[i];
    Inc(FCompared);
    if pc.Key <> p.Strings['key'] then
      Miss(Format('piece %d: key %s upstream, %s here', [i, p.Strings['key'], pc.Key]));
    if pc.Text <> p.Strings['text'] then
      Miss(Format('piece %d: text "%s" upstream, "%s" here', [i, p.Strings['text'], pc.Text]));
    if IsNull(p.Find('index')) then
    begin
      if pc.Index <> -1 then Miss(Format('piece %d: index %d here', [i, pc.Index]));
    end
    else if pc.Index <> p.Integers['index'] then
      Miss(Format('piece %d: index %d upstream, %d here', [i, p.Integers['index'], pc.Index]));
    if (i <= High(ASpec.Selected)) and (sel.Find(pc.Key) <> nil)
      and (ASpec.Selected[i] <> sel.Booleans[pc.Key]) then
      Miss(Format('piece %d: selected %s here', [i, BoolToStr(ASpec.Selected[i], True)]));
    { the interval and its ends }
    if IsNull(p.Find('interval')) then
    begin
      if pc.HasInterval then Miss(Format('piece %d: an interval here', [i]));
    end
    else if not (pc.HasInterval and SameBits(pc.Lo, p.Arrays['interval'].Strings[0])
      and SameBits(pc.Hi, p.Arrays['interval'].Strings[1])
      and (pc.Close0 = p.Arrays['close'].Integers[0])
      and (pc.Close1 = p.Arrays['close'].Integers[1])) then
      Miss(Format('piece %d: %s%s, %s%s upstream, %s%s, %s%s here', [i,
        Copy('([', p.Arrays['close'].Integers[0] + 1, 1), p.Arrays['intervalText'].Strings[0],
        p.Arrays['intervalText'].Strings[1], Copy(')]', p.Arrays['close'].Integers[1] + 1, 1),
        Copy('([', pc.Close0 + 1, 1), Fmt(pc.Lo), Fmt(pc.Hi), Copy(')]', pc.Close1 + 1, 1)]));
    { the value: a number, or a string }
    if not IsNull(p.Find('valueString')) then
    begin
      if not (pc.HasValue and pc.ValueIsStr and (pc.ValueStr = p.Strings['valueString'])) then
        Miss(Format('piece %d: value "%s" upstream', [i, p.Strings['valueString']]));
    end
    else if not IsNull(p.Find('value')) then
    begin
      if not (pc.HasValue and not pc.ValueIsStr and SameBits(pc.Value, p.Strings['value'])) then
        Miss(Format('piece %d: value %s upstream', [i, p.Strings['valueText']]));
    end
    else if pc.HasValue then
      Miss(Format('piece %d: a value %s here', [i, Fmt(pc.Value)]));
    { its own visuals }
    if IsNull(p.Find('visual')) then
    begin
      if Length(pc.Visuals) > 0 then Miss(Format('piece %d: own visuals here', [i]));
    end
    else
    begin
      v := p.Objects['visual'];
      if v.Count <> Length(pc.Visuals) then
        Miss(Format('piece %d: %d own visuals upstream, %d here', [i, v.Count, Length(pc.Visuals)]))
      else
        for k := 0 to High(pc.Visuals) do
          if (v.Names[k] <> pc.Visuals[k].Kind)
            or not SamePieceVisual(pc.Visuals[k], v.Items[k]) then
            Miss(Format('piece %d: own %s differs', [i, v.Names[k]]));
    end;
    { the representative value and its state }
    if IsNull(p.Find('representString')) then
    begin
      rv := TyVisualRepresent(pc);
      text := TyJsNumberToString(rv);
      if not SameBits(rv, p.Strings['representValue']) then
        Miss(Format('piece %d: represented by %s upstream, %s here', [i,
          p.Strings['representValueText'], Fmt(rv)]));
    end
    else
    begin
      rv := NaN;
      text := p.Strings['representString'];
    end;
    st := TyVisualValueState(ASpec, rv, text);
    if cStates[st] <> p.Strings['state'] then
      Miss(Format('piece %d: %s upstream, %s here', [i, p.Strings['state'], cStates[st]]));
  end;
end;

procedure TAdvChartVisualMapPiecewiseOracleTest.CheckMappings(const AWhat: string;
  const AMaps: TTyVisualMappingArray; const ASpec: TTyVisualMapSpec;
  AList: TJSONArray);
var
  i, k, j, own: Integer;
  m: TJSONObject;
  vis: TJSONArray;
  mp: TTyVisualMapping;
  found, special, anyVisual: Boolean;
  method: string;
begin
  own := 0;
  anyVisual := False;
  for k := 0 to High(ASpec.Pieces) do
    if Length(ASpec.Pieces[k].Visuals) > 0 then anyVisual := True;
  for i := 0 to AList.Count - 1 do
  begin
    m := AList.Objects[i];
    { the hidden __alphaForOpacity is the visualMeta's opacity, applied
      through AForMeta }
    if m.Booleans['alpha'] then Continue;
    Inc(own);
    Inc(FCompared);
    found := False;
    mp := Default(TTyVisualMapping);
    for k := 0 to High(AMaps) do
      if AMaps[k].Kind = m.Strings['type'] then
      begin
        mp := AMaps[k];
        found := True;
      end;
    if not found then
    begin
      Miss(Format('%s: no %s mapping here', [AWhat, m.Strings['type']]));
      Continue;
    end;
    case mp.Method of
      tvmLinear: method := 'linear';
      tvmPiecewise: method := 'piecewise';
      tvmCategory: method := 'category';
    end;
    if method <> m.Strings['method'] then
    begin
      Miss(Format('%s.%s: %s upstream, %s here', [AWhat, mp.Kind, m.Strings['method'], method]));
      Continue;
    end;
    { hasSpecialVisual: the in-range piecewise mappings, when a piece has
      one }
    special := (mp.Method = tvmPiecewise) and mp.UsePieces and anyVisual;
    if IsNull(m.Find('hasSpecialVisual')) then
    begin
      if special then Miss(Format('%s.%s: special here', [AWhat, mp.Kind]));
    end
    else if special <> m.Booleans['hasSpecialVisual'] then
      Miss(Format('%s.%s: hasSpecialVisual %s upstream', [AWhat, mp.Kind,
        BoolToStr(m.Booleans['hasSpecialVisual'], True)]));
    vis := m.Arrays['visual'];
    if mp.Method = tvmCategory then
    begin
      { by index, null where a category has none; the default slot }
      for j := 0 to vis.Count - 1 do
        if (j > High(mp.CatVals)) or ((mp.CatVals[j].Kind = 'color')
          and not IsNull(vis.Items[j])
          and not SameVisual(ParsedOf(mp.CatVals[j].Str), ParsedOf(vis.Items[j].AsString)))
          or ((mp.CatVals[j].Kind <> 'color')
          and not SamePieceVisual(mp.CatVals[j], vis.Items[j]))
          or (IsNull(vis.Items[j]) <> not mp.CatVals[j].Defined) then
          Miss(Format('%s.%s: category %d differs', [AWhat, mp.Kind, j]));
      for j := vis.Count to High(mp.CatVals) do
        if mp.CatVals[j].Defined then
          Miss(Format('%s.%s: category %d has a visual here', [AWhat, mp.Kind, j]));
      if IsNull(m.Find('visualDefault')) <> not mp.CatDefault.Defined then
        Miss(Format('%s.%s: default slot differs', [AWhat, mp.Kind]))
      else if mp.CatDefault.Defined and (mp.Kind = 'color') then
      begin
        if not SameVisual(ParsedOf(mp.CatDefault.Str), ParsedOf(m.Strings['visualDefault'])) then
          Miss(Format('%s.%s: default %s upstream', [AWhat, mp.Kind, m.Strings['visualDefault']]));
      end
      else if mp.CatDefault.Defined and not SamePieceVisual(mp.CatDefault, m.Find('visualDefault')) then
        Miss(Format('%s.%s: default %s upstream', [AWhat, mp.Kind, m.Find('visualDefault').AsJSON]));
      Continue;
    end;
    if mp.Kind = 'color' then
    begin
      if Length(mp.Colors) <> vis.Count then
        Miss(Format('%s.color: %d stops upstream, %d here', [AWhat, vis.Count, Length(mp.Colors)]))
      else
        for j := 0 to vis.Count - 1 do
          if not SameVisual(mp.Colors[j], ParsedOf(vis.Strings[j])) then
            Miss(Format('%s.color %d: %s upstream, %s here', [AWhat, j, vis.Strings[j],
              ColourText(mp.Colors[j])]));
    end
    else if mp.Kind = 'symbol' then
    begin
      if KeysText(mp.Strs) <> ArrText(vis) then
        Miss(Format('%s.symbol: %s upstream, %s here', [AWhat, ArrText(vis), KeysText(mp.Strs)]));
    end
    else if Length(mp.Nums) <> vis.Count then
      Miss(Format('%s.%s: %d values upstream, %d here', [AWhat, mp.Kind, vis.Count, Length(mp.Nums)]))
    else
      for j := 0 to vis.Count - 1 do
        if (vis.Items[j].JSONType <> jtNumber) or (Bits(mp.Nums[j]) <> Bits(vis.Items[j].AsFloat)) then
          Miss(Format('%s.%s %d: %s upstream, %s here', [AWhat, mp.Kind, j,
            vis.Items[j].AsJSON, Fmt(mp.Nums[j])]));
  end;
  Inc(FCompared);
  if own <> Length(AMaps) then
    Miss(Format('%s: %d mappings upstream, %d here', [AWhat, own, Length(AMaps)]));
end;

procedure TAdvChartVisualMapPiecewiseOracleTest.CheckModel(AVm: TJSONObject);
const
  cModes: array[TTyPiecewiseMode] of string = ('splitNumber', 'pieces', 'categories');
var
  spec: TTyVisualMapSpec;
  model, tgt, ctl: TJSONObject;
  st: TTyVisualState;
  cats: TJSONData;
  i: Integer;
begin
  spec := FChart.VisualMapSpec(AVm.Integers['index']);
  model := AVm.Objects['model'];
  Inc(FCompared);
  if spec.SubType <> AVm.Strings['subType'] then
  begin
    Miss('subtype ' + spec.SubType);
    Exit;
  end;
  if cModes[spec.Mode] <> AVm.Strings['mode'] then
    Miss(Format('mode %s upstream, %s here', [AVm.Strings['mode'], cModes[spec.Mode]]));
  if not (SameBits(spec.Extent0, model.Arrays['extent'].Strings[0])
    and SameBits(spec.Extent1, model.Arrays['extent'].Strings[1])) then
    Miss(Format('extent %s..%s here', [Fmt(spec.Extent0), Fmt(spec.Extent1)]));
  { the auto precision, written back }
  if spec.Precision <> model.Integers['precision'] then
    Miss(Format('precision %d upstream, %d here', [model.Integers['precision'], spec.Precision]));
  cats := model.Find('categories');
  if spec.IsCategory <> not IsNull(cats) then
    Miss('isCategory differs');
  if (spec.Mode = tpmCategories) and (cats.JSONType = jtArray) then
  begin
    if Length(spec.Categories) <> TJSONArray(cats).Count then
      Miss('categories differ')
    else
      for i := 0 to High(spec.Categories) do
        if spec.Categories[i] <> TJSONArray(cats).Strings[i] then
          Miss(Format('category %d: %s here', [i, spec.Categories[i]]));
  end;
  CheckPieces(spec, AVm);
  tgt := model.Objects['target'];
  ctl := model.Objects['controller'];
  for st := Low(TTyVisualState) to High(TTyVisualState) do
  begin
    Inc(FCompared);
    if KeysText(spec.Keys[st]) <> ObjKeysText(tgt.Objects[cStates[st]]) then
      Miss(Format('target.%s keys %s upstream, %s here', [cStates[st],
        ObjKeysText(tgt.Objects[cStates[st]]), KeysText(spec.Keys[st])]));
    if KindsText(spec.States[st]) <> model.Objects['order'].Arrays[cStates[st]].AsJSON then
      Miss(Format('target.%s applied as %s upstream, %s here', [cStates[st],
        model.Objects['order'].Arrays[cStates[st]].AsJSON, KindsText(spec.States[st])]));
    if KeysText(spec.ControllerKeys[st]) <> ObjKeysText(ctl.Objects[cStates[st]]) then
      Miss(Format('controller.%s keys %s upstream, %s here', [cStates[st],
        ObjKeysText(ctl.Objects[cStates[st]]), KeysText(spec.ControllerKeys[st])]));
    if KindsText(spec.Controller[st]) <> model.Objects['controllerOrder'].Arrays[cStates[st]].AsJSON then
      Miss(Format('controller.%s applied as %s upstream, %s here', [cStates[st],
        model.Objects['controllerOrder'].Arrays[cStates[st]].AsJSON,
        KindsText(spec.Controller[st])]));
    CheckMappings('target.' + cStates[st], spec.States[st], spec,
      AVm.Objects['mappings'].Objects['target'].Arrays[cStates[st]]);
    CheckMappings('controller.' + cStates[st], spec.Controller[st], spec,
      AVm.Objects['mappings'].Objects['controller'].Arrays[cStates[st]]);
  end;
end;

{ ==================== the rows ==================== }

procedure TAdvChartVisualMapPiecewiseOracleTest.CheckSeries(AOption,
  ASeries: TJSONObject);
var
  rows, vals: TJSONArray;
  r, vv: TJSONObject;
  si, i, j, k, raw, found, pIdx: Integer;
  row: TTyVisualRow;
  spec: TTyVisualMapSpec;
  value: Double;
  text, typ: string;
  st: TTyVisualState;
  lst: TTyPaintList;
  e, el: TTyChartElement;
  want: TTyChartColor;
  wantAlpha: Double;
begin
  si := ASeries.Integers['index'];
  typ := ASeries.Strings['type'];
  rows := ASeries.Arrays['rows'];
  lst := FChart.List;
  for i := 0 to rows.Count - 1 do
  begin
    r := rows.Objects[i];
    raw := r.Integers['rawIndex'];
    { THE PIECE AND THE STATE of each value, by the spec's own search }
    vals := r.Arrays['values'];
    for j := 0 to vals.Count - 1 do
    begin
      vv := vals.Objects[j];
      spec := FChart.VisualMapSpec(vv.Integers['vm']);
      if not IsNull(vv.Find('valueString')) then
      begin
        value := NaN;
        text := vv.Strings['valueString'];
      end
      else
      begin
        value := FromHex(vv.Strings['value']);
        text := TyJsNumberToString(value);
      end;
      Inc(FCompared);
      pIdx := TyVisualFindPiece(spec.Pieces, value, text, False);
      if (IsNull(vv.Find('piece')) and (pIdx <> -1))
        or (not IsNull(vv.Find('piece')) and (pIdx <> vv.Integers['piece'])) then
        Miss(Format('s%d row %d (%s): piece %s upstream, %d here', [si, raw,
          vv.Strings['valueText'], vv.Find('piece').AsJSON, pIdx]));
      pIdx := TyVisualFindPiece(spec.Pieces, value, text, True);
      if (IsNull(vv.Find('closest')) and (pIdx <> -1))
        or (not IsNull(vv.Find('closest')) and (pIdx <> vv.Integers['closest'])) then
        Miss(Format('s%d row %d (%s): closest piece %s upstream, %d here', [si, raw,
          vv.Strings['valueText'], vv.Find('closest').AsJSON, pIdx]));
      st := TyVisualValueState(spec, value, text);
      if cStates[st] <> vv.Strings['state'] then
        Miss(Format('s%d row %d (%s): %s upstream, %s here', [si, raw,
          vv.Strings['valueText'], vv.Strings['state'], cStates[st]]));
    end;

    { WHAT THE ROW WAS GIVEN }
    Inc(FCompared);
    if not FChart.VisualRow(si, raw, row) then
    begin
      Miss(Format('s%d row %d: no visual row', [si, raw]));
      Continue;
    end;
    if row.ColorSet and not ItemHas(AOption, si, raw, 'color')
      and not SameColour(row.Color, r.Objects['fill']) then
      Miss(Format('s%d row %d: %s upstream, %s here', [si, raw,
        ColourText(FixColour(r.Objects['fill'])), ColourText(row.Color)]));
    if (typ <> 'scatter') and not ItemHas(AOption, si, raw, 'opacity') then
    begin
      if IsNull(r.Find('opacity')) then
      begin
        { undefined, written, draws at 1 }
        if row.OpacitySet and (row.Opacity <> 1) then
          Miss(Format('s%d row %d: opacity %s written here', [si, raw, Fmt(row.Opacity)]));
      end
      else if not (row.OpacitySet and SameBits(row.Opacity, r.Strings['opacity'])) then
        Miss(Format('s%d row %d: opacity %s upstream, %s here', [si, raw,
          r.Strings['opacityText'], Fmt(row.Opacity)]));
    end;
    { a symbol and a size mapped, else the series' own }
    if row.SymbolSet and (row.Symbol <> r.Strings['symbol']) then
      Miss(Format('s%d row %d: symbol %s upstream, %s here', [si, raw,
        r.Strings['symbol'], row.Symbol]));
    if not row.SymbolSet and not IsNull(r.Find('symbol'))
      and (r.Strings['symbol'] <> ASeries.Strings['symbol']) then
      Miss(Format('s%d row %d: symbol %s mapped upstream, none here', [si, raw,
        r.Strings['symbol']]));
    if (r.Find('symbolSize') <> nil) and (r.Find('symbolSize').JSONType = jtNumber) then
    begin
      if row.SizeSet and (Bits(row.Size) <> Bits(r.Floats['symbolSize'])) then
        Miss(Format('s%d row %d: size %s upstream, %s here', [si, raw,
          r.Find('symbolSize').AsJSON, Fmt(row.Size)]));
      if not row.SizeSet and (ASeries.Find('symbolSize').JSONType = jtNumber)
        and (Bits(ASeries.Floats['symbolSize']) <> Bits(r.Floats['symbolSize'])) then
        Miss(Format('s%d row %d: size %s mapped upstream, none here', [si, raw,
          r.Find('symbolSize').AsJSON]));
    end;

    { THE SAME ROW AS DRAWN: a bar's or a scatter's element }
    if ((typ = 'bar') or (typ = 'scatter')) and (lst <> nil)
      and not ItemHas(AOption, si, raw, 'color') then
    begin
      found := 0;
      el := Default(TTyChartElement);
      for k := 0 to lst.Count - 1 do
      begin
        e := lst.Element(k);
        if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si)
          or (e.Datum.RawDataIndex <> raw) then Continue;
        if e.Caption.FontSizeLogical > 0 then Continue;
        Inc(found);
        el := e;
      end;
      if found = 1 then
      begin
        want := PackFix(r.Objects['fill']);
        if IsNull(r.Find('opacity')) then wantAlpha := 1
        else wantAlpha := FromHex(r.Strings['opacity']);
        Inc(FCompared);
        if (el.Style.FillColor <> want) or (el.Style.HasFill <> (want <> 0)) then
          Miss(Format('s%d row %d: drawn in $%.8x, upstream $%.8x', [si, raw,
            el.Style.FillColor, want]))
        else if el.Style.Alpha <> wantAlpha then
          Miss(Format('s%d row %d: alpha %s, upstream %s', [si, raw,
            Fmt(el.Style.Alpha), Fmt(wantAlpha)]));
      end;
    end;
  end;
  CheckMetas(ASeries);
  if typ = 'line' then CheckLine(ASeries);
end;

procedure TAdvChartVisualMapPiecewiseOracleTest.CheckMetas(ASeries: TJSONObject);
var
  metas, stops: TJSONArray;
  m, st: TJSONObject;
  si, i, k: Integer;
  got: TTyVisualMetaArray;
begin
  si := ASeries.Integers['index'];
  metas := ASeries.Arrays['visualMeta'];
  got := FChart.VisualMetas(si);
  Inc(FCompared);
  if Length(got) <> metas.Count then
  begin
    Miss(Format('s%d: %d visualMetas upstream, %d here', [si, metas.Count, Length(got)]));
    Exit;
  end;
  for i := 0 to metas.Count - 1 do
  begin
    m := metas.Objects[i];
    Inc(FCompared);
    if (got[i].VisualMap <> m.Integers['vm'])
      or (got[i].Dimension <> m.Integers['dimension']) then
    begin
      Miss(Format('s%d meta %d: vm %d dim %d here', [si, i, got[i].VisualMap,
        got[i].Dimension]));
      Continue;
    end;
    { outerColors: '' is nothing }
    if m.Arrays['outerColors'].Count = 2 then
    begin
      if not (SameColour(got[i].Outer0, m.Arrays['outerColors'].Objects[0])
        and SameColour(got[i].Outer1, m.Arrays['outerColors'].Objects[1])) then
        Miss(Format('s%d meta %d: outer colours %s %s here', [si, i,
          ColourText(got[i].Outer0), ColourText(got[i].Outer1)]));
    end
    else if got[i].Outer0.Defined or got[i].Outer1.Defined then
      Miss(Format('s%d meta %d: outer colours here', [si, i]));
    stops := m.Arrays['stops'];
    if Length(got[i].Stops) <> stops.Count then
    begin
      Miss(Format('s%d meta %d: %d stops upstream, %d here', [si, i, stops.Count,
        Length(got[i].Stops)]));
      Continue;
    end;
    for k := 0 to stops.Count - 1 do
    begin
      st := stops.Objects[k];
      if not SameBits(got[i].Stops[k].Value, st.Strings['value']) then
      begin
        Miss(Format('s%d meta %d stop %d: value %s upstream, %s here', [si, i, k,
          st.Strings['valueText'], Fmt(got[i].Stops[k].Value)]));
        Break;
      end;
      if not SameColour(got[i].Stops[k].Color, st.Objects['color']) then
      begin
        Miss(Format('s%d meta %d stop %d (%s): %s upstream, %s here', [si, i, k,
          st.Strings['valueText'], ColourText(FixColour(st.Objects['color'])),
          ColourText(got[i].Stops[k].Color)]));
        Break;
      end;
    end;
  end;
end;

procedure TAdvChartVisualMapPiecewiseOracleTest.CheckLine(ASeries: TJSONObject);
var
  fill: TTyVisualLineFill;
  si: Integer;
  area: TJSONObject;

  procedure SameFill(ARec: TJSONObject; const AWhat: string);
  var st: TJSONArray; j: Integer; lo, hi: string;
  begin
    Inc(FCompared);
    if ARec.Strings['kind'] = 'color' then
    begin
      if (fill.Kind <> vlfSolid) or not SameColour(fill.Solid, ARec.Objects['color']) then
        Miss(Format('s%d %s: one colour upstream, not here', [si, AWhat]));
      Exit;
    end;
    if fill.Kind <> vlfGradient then
    begin
      Miss(Format('s%d %s: a gradient upstream, none here', [si, AWhat]));
      Exit;
    end;
    if fill.Vertical then
    begin
      lo := ARec.Strings['y'];
      hi := ARec.Strings['y2'];
    end
    else
    begin
      lo := ARec.Strings['x'];
      hi := ARec.Strings['x2'];
    end;
    if not SameBits(fill.Lo, lo) or not SameBits(fill.Hi, hi) then
    begin
      Miss(Format('s%d %s: %s..%s here', [si, AWhat, Fmt(fill.Lo), Fmt(fill.Hi)]));
      Exit;
    end;
    st := ARec.Arrays['stops'];
    if Length(fill.Stops) <> st.Count then
    begin
      Miss(Format('s%d %s: %d stops upstream, %d here', [si, AWhat, st.Count,
        Length(fill.Stops)]));
      Exit;
    end;
    for j := 0 to st.Count - 1 do
      if not (SameBits(fill.Stops[j].Offset, st.Objects[j].Strings['offset'])
        and SameColour(fill.Stops[j].Color, st.Objects[j].Objects['color'])) then
      begin
        Miss(Format('s%d %s stop %d: %s %s upstream, %s %s here', [si, AWhat, j,
          st.Objects[j].Strings['offsetText'],
          ColourText(FixColour(st.Objects[j].Objects['color'])),
          Fmt(fill.Stops[j].Offset), ColourText(fill.Stops[j].Color)]));
        Exit;
      end;
  end;

begin
  si := ASeries.Integers['index'];
  { KNOWN: line-aqi's dataZoom is not ported, so its value axis spans the
    unfiltered data (0..500, not 0..400) and every stop lands elsewhere; the
    visualMeta itself is held above }
  if FName = 'G-line-aqi' then Exit;
  fill := FChart.VisualLineFill(si);
  if not ASeries.Booleans['lineStyleColorWritten']
    and (ASeries.Find('polyline').JSONType = jtObject) then
    SameFill(ASeries.Objects['polyline'], 'polyline');
  area := nil;
  if ASeries.Find('area').JSONType = jtObject then area := ASeries.Objects['area'];
  if area <> nil then SameFill(area, 'area');
end;

procedure TAdvChartVisualMapPiecewiseOracleTest.RunCases(const AIds: array of string);
var
  cases, vms, ser: TJSONArray;
  cs: TJSONObject;
  opt: TJSONObject;
  sl: TStringList;
  d: TJSONData;
  c, k, j, ran: Integer;
  wanted: Boolean;

  procedure Upstream(AVm: TJSONObject);
  begin
    if AVm.Find('inactiveColor') = nil then AVm.Add('inactiveColor', '#cfd2d7');
  end;

begin
  ran := 0;
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    wanted := False;
    for j := 0 to High(AIds) do
      if (cs.Strings['id'] = AIds[j])
        or ((AIds[j] = 'G*') and (Copy(cs.Strings['id'], 1, 2) = 'G-')) then
        wanted := True;
    if not wanted then Continue;
    Inc(ran);
    FName := cs.Strings['id'];
    if cs.Find('option').JSONType = jtObject then
      opt := TJSONObject(cs.Objects['option'].Clone)
    else
    begin
      sl := TStringList.Create;
      try
        sl.LoadFromFile(GalleryPath(cs.Strings['gallery']));
        opt := TJSONObject(GetJSON(sl.Text));
      finally
        sl.Free;
      end;
    end;
    try
      { upstream's palette and ramp, so the theme is out of the comparison }
      if opt.Find('color') = nil then opt.Add('color', GetJSON(cPalette));
      if opt.Find('gradientColor') = nil then
        opt.Add('gradientColor', GetJSON('["rgba(212,220,247,1)","#5070dd"]'));
      d := opt.Find('visualMap');
      if (d <> nil) and (d.JSONType = jtObject) then Upstream(TJSONObject(d))
      else if (d <> nil) and (d.JSONType = jtArray) then
        for k := 0 to TJSONArray(d).Count - 1 do
          if TJSONArray(d).Items[k].JSONType = jtObject then
            Upstream(TJSONObject(TJSONArray(d).Items[k]));
      FChart.Option := opt.AsJSON;
      AssertEquals(FName + ' parses', '', FChart.OptionError);
      FChart.SetBounds(0, 0, cs.Integers['width'], cs.Integers['height']);
      try
        FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cs.Integers['width'],
          cs.Integers['height']), 96);
      except
        on E: Exception do
        begin
          Miss(E.ClassName + ': ' + E.Message);
          Continue;
        end;
      end;
      vms := cs.Arrays['visualMaps'];
      Inc(FCompared);
      if FChart.VisualMapCount <> vms.Count then
        Miss(Format('%d visualMaps upstream, %d here', [vms.Count, FChart.VisualMapCount]));
      for k := 0 to vms.Count - 1 do
        CheckModel(vms.Objects[k]);
      if (cs.Find('series') <> nil) and (cs.Find('series').JSONType = jtArray) then
      begin
        ser := cs.Arrays['series'];
        for k := 0 to ser.Count - 1 do
          CheckSeries(opt, ser.Objects[k]);
      end;
    finally
      opt.Free;
    end;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue('every named case ran', ran >= Length(AIds));
end;

{ ==================== the cases ==================== }

procedure TAdvChartVisualMapPiecewiseOracleTest.TestSplitNumberAsUpstream;
begin
  RunCases(['S1', 'S2', 'P2', 'P3', 'S4', 'S5', 'S6', 'S7', 'S8', 'S9']);
end;

procedure TAdvChartVisualMapPiecewiseOracleTest.TestPiecesAsUpstream;
begin
  RunCases(['P4', 'P5', 'P6', 'P7', 'P11', 'P12', 'P13', 'P14', 'P15', 'P16', 'P17',
    'P18', 'P19', 'P20', 'P21']);
end;

procedure TAdvChartVisualMapPiecewiseOracleTest.TestCategoriesAsUpstream;
begin
  RunCases(['C1', 'C2', 'C3', 'C4']);
end;

procedure TAdvChartVisualMapPiecewiseOracleTest.TestViewCasesEncodeAsUpstream;
begin
  RunCases(['V1', 'V2', 'V3', 'V4', 'V5', 'V6', 'V7', 'V8', 'V9']);
end;

procedure TAdvChartVisualMapPiecewiseOracleTest.TestLineMetasAsUpstream;
begin
  RunCases(['L1', 'L2']);
end;

procedure TAdvChartVisualMapPiecewiseOracleTest.TestGalleryAsUpstream;
begin
  RunCases(['G*']);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > 500);
end;

procedure TAdvChartVisualMapPiecewiseOracleTest.TestTheNoteIsGone;
var i: Integer;
begin
  { a piecewise visualMap encodes now: no "not supported" note }
  FChart.Option := '{"visualMap": {"type": "piecewise", "min": 0, "max": 10},'
    + ' "xAxis": {"type": "category", "data": ["a"]}, "yAxis": {},'
    + ' "series": [{"type": "bar", "data": [3]}]}';
  FChart.SetBounds(0, 0, 400, 300);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 400, 300), 96);
  AssertTrue('the chart said something about it at all', FChart.VisualMapCount = 1);
  for i := 0 to FChart.DiagnosticCount - 1 do
    AssertEquals('note ' + FChart.Diagnostic(i), 0, Pos('piecewise', FChart.Diagnostic(i)));
end;

initialization
  RegisterTest(TAdvChartVisualMapPiecewiseOracleTest);
end.
