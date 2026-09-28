unit test.advchart.datazoomslider;
{$mode objfpc}{$H+}
{ A slider dataZoom's own picture -- SliderZoomView's first render: where
  _resetLocation puts it, the handle ends _resetInterval gives, the rect
  _positionGroup reads from the half-built slider group and the offset it
  moves the view group by, and then every element as _updateView leaves it
  -- background, filler, frame, the two handles with their icon's path data,
  the move bar, its icon and its zone, the three data-shadow groups with
  their points and clips, the two labels -- and the storage's paint order,
  held to what ECharts 6.1 itself lays out.

  tools/advchart-oracle/datazoom-slider.js records each slider's resolved
  inputs, its shadow points, and every element's local and global matrix,
  bounding rect (stroke included), shape or path, and the final rects. Text
  sizes are zrender's own measure, fed through a table measurer, for the
  axis labels too -- so the grid lands where upstream's does.

  EXACT: bit for bit, -0 and 0 one. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Layout, tyControls.AdvChart.ZrPath,
     tyControls.AdvChart.DataZoomView, tyControls.AdvanceChart;
type
  TDzsMeasurer = class(TInterfacedObject, ITyTextMeasurer)
  public
    Names: TStringList;
    W, H: array of Double;
    Missed: string;
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AText: string; AW, AH: Double);
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

  TDzsProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartDataZoomSliderOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TDzsProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FMeas: TDzsMeasurer;
    FBad, FCompared: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure Num(const AWhat: string; AGot: Double; AData: TJSONData);
    procedure Rect(const AWhat: string; const AGot: TTyXYWH; ARec: TJSONObject);
    procedure Mat(const AWhat: string; const AGot: TTyMat2D; AArr: TJSONArray);
    procedure Points(const AWhat: string; const AGot: TTyPointFArray; AArr: TJSONArray);
    procedure PathData(const AWhat: string; const AGot: TTyZrPath; AArr: TJSONArray);
    procedure CheckSlider(ADz: TJSONObject);
    procedure RunCases(const APrefix: string; AMin: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSlidersAsUpstreamLaysThemOut;
    procedure TestGallerySlidersAsUpstream;
    procedure TestTheSliderIsDrawn;
    procedure TestTheSliderTakesTheAuthorsInk;
    procedure TestTheBoxMergeKeepsTwoOfThree;
    procedure TestAShadowSkipsByTheStride;
  end;

implementation

uses tyControls.AdvChart.JsMath;

constructor TDzsMeasurer.Create;
begin
  inherited Create;
  Names := TStringList.Create;
  Names.CaseSensitive := True;
end;

destructor TDzsMeasurer.Destroy;
begin
  Names.Free;
  inherited Destroy;
end;

procedure TDzsMeasurer.Add(const AText: string; AW, AH: Double);
var k: Integer;
begin
  if Names.IndexOf(AText) >= 0 then Exit;
  k := Names.Add(AText);
  SetLength(W, k + 1);
  SetLength(H, k + 1);
  W[k] := AW;
  H[k] := AH;
end;

procedure TDzsMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
var k: Integer;
begin
  k := Names.IndexOf(AText);
  if k < 0 then
  begin
    if Pos('"' + AText + '"', Missed) = 0 then
      Missed := Missed + ' "' + AText + '"';
    AW := 0;
    AH := 12;
    Exit;
  end;
  AW := W[k];
  AH := H[k];
end;

function TDzsMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
begin
  Result := AText;
end;

function TDzsProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Exit(Measurer);
  Result := inherited NewTextMeasurer(APPI);
end;

procedure TDzsProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TDzsProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-datazoom-slider.json';
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

function Fmt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function SameNum(A: Double; const AHex: string): Boolean;
var b: Double;
begin
  b := FromHex(AHex);
  if IsNan(A) or IsNan(b) then Exit(IsNan(A) and IsNan(b));
  if (A = 0) and (b = 0) then Exit(True);
  Result := Bits(A) = Bits(b);
end;

function HText(A: TTyTextAnchorH): string;
begin
  case A of
    tahRight: Result := 'right';
    tahCentre: Result := 'center';
  else
    Result := 'left';
  end;
end;

function VText(A: TTyTextAnchorV): string;
begin
  case A of
    tavBottom: Result := 'bottom';
    tavMiddle: Result := 'middle';
  else
    Result := 'top';
  end;
end;

function RoleName(A: TTyDzRole): string;
const
  cNames: array[TTyDzRole] of string = ('background', 'clickPanel', 'filler',
    'frame', 'handle0', 'handle1', 'moveHandle', 'moveHandleIcon', 'moveZone',
    'shadow0', 'shadow1', 'shadow2', 'shadowPolygon0', 'shadowPolygon1',
    'shadowPolygon2', 'shadowPolyline0', 'shadowPolyline1', 'shadowPolyline2',
    'label0', 'label1');
begin
  Result := cNames[A];
end;

function RoleOf(const AName: string; out ARole: TTyDzRole): Boolean;
var r: TTyDzRole;
begin
  for r := Low(TTyDzRole) to High(TTyDzRole) do
    if RoleName(r) = AName then
    begin
      ARole := r;
      Exit(True);
    end;
  Result := False;
end;

procedure TAdvChartDataZoomSliderOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartDataZoomSliderOracleTest.Num(const AWhat: string;
  AGot: Double; AData: TJSONData);
begin
  Inc(FCompared);
  if (AData = nil) or (AData.JSONType = jtNull) then
  begin
    if not IsNan(AGot) then Miss(Format('%s: none upstream, %s here', [AWhat, Fmt(AGot)]));
    Exit;
  end;
  if not SameNum(AGot, AData.AsString) then
    Miss(Format('%s: %s upstream, %s here', [AWhat, Fmt(FromHex(AData.AsString)), Fmt(AGot)]));
end;

procedure TAdvChartDataZoomSliderOracleTest.Rect(const AWhat: string;
  const AGot: TTyXYWH; ARec: TJSONObject);
begin
  Inc(FCompared);
  if not (SameNum(AGot.X, ARec.Strings['x']) and SameNum(AGot.Y, ARec.Strings['y'])
    and SameNum(AGot.W, ARec.Strings['width'])
    and SameNum(AGot.H, ARec.Strings['height'])) then
    Miss(Format('%s: %s,%s %sx%s upstream, %s,%s %sx%s here', [AWhat,
      Fmt(FromHex(ARec.Strings['x'])), Fmt(FromHex(ARec.Strings['y'])),
      Fmt(FromHex(ARec.Strings['width'])), Fmt(FromHex(ARec.Strings['height'])),
      Fmt(AGot.X), Fmt(AGot.Y), Fmt(AGot.W), Fmt(AGot.H)]));
end;

procedure TAdvChartDataZoomSliderOracleTest.Mat(const AWhat: string;
  const AGot: TTyMat2D; AArr: TJSONArray);
var k: Integer; ok: Boolean;
begin
  Inc(FCompared);
  ok := AArr.Count = 6;
  if ok then
    for k := 0 to 5 do
      if not SameNum(AGot[k], AArr.Strings[k]) then ok := False;
  if not ok then
    Miss(Format('%s: [%s %s %s %s %s %s] here', [AWhat, Fmt(AGot[0]), Fmt(AGot[1]),
      Fmt(AGot[2]), Fmt(AGot[3]), Fmt(AGot[4]), Fmt(AGot[5])]));
end;

procedure TAdvChartDataZoomSliderOracleTest.Points(const AWhat: string;
  const AGot: TTyPointFArray; AArr: TJSONArray);
var k: Integer;
begin
  Inc(FCompared);
  if Length(AGot) <> AArr.Count then
  begin
    Miss(Format('%s: %d points upstream, %d here', [AWhat, AArr.Count, Length(AGot)]));
    Exit;
  end;
  for k := 0 to AArr.Count - 1 do
    if not (SameNum(AGot[k].X, TJSONArray(AArr.Items[k]).Strings[0])
      and SameNum(AGot[k].Y, TJSONArray(AArr.Items[k]).Strings[1])) then
    begin
      Miss(Format('%s: point %d is %s,%s upstream, %s,%s here', [AWhat, k,
        Fmt(FromHex(TJSONArray(AArr.Items[k]).Strings[0])),
        Fmt(FromHex(TJSONArray(AArr.Items[k]).Strings[1])),
        Fmt(AGot[k].X), Fmt(AGot[k].Y)]));
      Exit;
    end;
end;

procedure TAdvChartDataZoomSliderOracleTest.PathData(const AWhat: string;
  const AGot: TTyZrPath; AArr: TJSONArray);
var
  k, j: Integer;
  seg: TJSONObject;
  args: TJSONArray;
begin
  Inc(FCompared);
  if Length(AGot) <> AArr.Count then
  begin
    Miss(Format('%s: %d commands upstream, %d here', [AWhat, AArr.Count, Length(AGot)]));
    Exit;
  end;
  for k := 0 to AArr.Count - 1 do
  begin
    seg := AArr.Objects[k];
    args := seg.Arrays['args'];
    if (seg.Strings['cmd'] <> TyZrCmdName[AGot[k].Cmd])
      or (args.Count <> TyZrArgCount(AGot[k].Cmd)) then
    begin
      Miss(Format('%s: command %d is %s upstream, %s here', [AWhat, k,
        seg.Strings['cmd'], TyZrCmdName[AGot[k].Cmd]]));
      Exit;
    end;
    for j := 0 to args.Count - 1 do
      if not SameNum(AGot[k].V[j], args.Strings[j]) then
      begin
        Miss(Format('%s: command %d (%s) argument %d is %s upstream, %s here',
          [AWhat, k, seg.Strings['cmd'], j, Fmt(FromHex(args.Strings[j])),
          Fmt(AGot[k].V[j])]));
        Exit;
      end;
  end;
end;

procedure TAdvChartDataZoomSliderOracleTest.CheckSlider(ADz: TJSONObject);
var
  L: TTyDzSliderLayout;
  r, sh, v, pos, e, g, shape: TJSONObject;
  kids, els, groups, arr: TJSONArray;
  k, j, n: Integer;
  role: TTyDzRole;
  lb: TTyDzLabel;
  G0, M: TTyMat2D;
  el: TTyDzElement;
  radii: TTyDoubleArray;
  allZero, same: Boolean;
  d: TJSONData;
  paint: string;
begin
  L := FChart.DataZoomSliderLayout(ADz.Integers['index']);
  Inc(FCompared);
  if (not ADz.Booleans['show']) or ADz.Booleans['noTarget'] then
  begin
    if L.Valid then Miss('laid out here, nothing drawn upstream');
    Exit;
  end;
  if not L.Valid then
  begin
    Miss('not laid out here');
    Exit;
  end;
  r := ADz.Objects['resolved'];
  Inc(FCompared);
  if L.Horizontal <> (r.Strings['orient'] = 'horizontal') then Miss('orient differs');
  Rect('coord rect', L.CoordRect, r.Objects['coordRect']);
  Num('location x', L.LocX, r.Objects['location'].Find('x'));
  Num('location y', L.LocY, r.Objects['location'].Find('y'));
  Num('length', L.L, r.Arrays['size'].Items[0]);
  Num('thickness', L.T, r.Arrays['size'].Items[1]);
  for k := 0 to 1 do
  begin
    Num(Format('range %d', [k]), L.Range[k], r.Arrays['range'].Items[k]);
    Num(Format('handle end %d', [k]), L.HandleEnds[k], r.Arrays['handleEnds'].Items[k]);
  end;
  Num('handle width', L.HandleW, r.Find('handleWidth'));
  Num('handle height', L.HandleH, r.Find('handleHeight'));
  Num('move bar height', L.MoveH, r.Find('moveHandleHeight'));
  { the data shadow }
  d := ADz.Find('shadow');
  Inc(FCompared);
  if (d = nil) or (d.JSONType <> jtObject) or not TJSONObject(d).Booleans['drawn'] then
  begin
    if L.ShadowDrawn then Miss('a shadow here, none upstream');
  end
  else if not L.ShadowDrawn then
    Miss('no shadow here')
  else
  begin
    sh := TJSONObject(d);
    for k := 0 to 1 do
    begin
      Num(Format('shadow this extent %d', [k]), L.ThisExt[k],
        sh.Arrays['thisDataExtent'].Items[k]);
      Num(Format('shadow other extent %d', [k]), L.OtherExt[k],
        sh.Arrays['otherDataExtent'].Items[k]);
    end;
    Points('shadow area', L.Area, sh.Arrays['area']);
    Points('shadow line', L.Line, sh.Arrays['line']);
  end;
  v := ADz.Objects['view'];
  { _positionGroup }
  Mat('slider group local', L.SG, v.Objects['sliderGroup'].Arrays['local']);
  G0 := TyZrLocal(1, 1, 0, L.GroupX, L.GroupY);
  Mat('slider group to the view group', TyMatMul(L.SG, TyMatMul(TyMatIdentity, TyMatIdentity)),
    v.Objects['sliderGroup'].Arrays['toGroup']);
  Mat('slider group global', TyMatMul(G0, TyMatMul(L.SG, TyMatIdentity)),
    v.Objects['sliderGroup'].Arrays['global']);
  pos := v.Objects['position'];
  Rect('the slider rect _positionGroup reads', L.PosSliderRect, pos.Objects['sliderRect']);
  Rect('the group rect _positionGroup reads', L.PosGroupRect, pos.Objects['groupRect']);
  Num('group x', L.GroupX, v.Objects['group'].Find('x'));
  Num('group y', L.GroupY, v.Objects['group'].Find('y'));
  Mat('group matrix', G0, v.Objects['group'].Arrays['matrix']);
  kids := pos.Arrays['children'];
  n := 0;
  for role := dzrBackground to dzrShadow2 do
    if L.PosKids[role].Present then Inc(n);
  Inc(FCompared);
  if n <> kids.Count then Miss(Format('%d children at _positionGroup upstream, %d here',
    [kids.Count, n]));
  for k := 0 to kids.Count - 1 do
  begin
    e := kids.Objects[k];
    if not RoleOf(e.Strings['role'], role) then
    begin
      Miss('unknown role ' + e.Strings['role']);
      Continue;
    end;
    el := L.PosKids[role];
    Inc(FCompared);
    if (not el.Present) or (el.Included <> e.Booleans['included']) then
    begin
      Miss(Format('%s at _positionGroup: present %s included %s here',
        [RoleName(role), BoolToStr(el.Present, True), BoolToStr(el.Included, True)]));
      Continue;
    end;
    Rect('pos ' + RoleName(role) + ' rect', el.Rect, e.Objects['rect']);
    Mat('pos ' + RoleName(role) + ' local', el.Local, e.Arrays['local']);
  end;
  { the shadow groups }
  groups := v.Arrays['shadowGroups'];
  for k := 0 to groups.Count - 1 do
  begin
    g := groups.Objects[k];
    role := TTyDzRole(Ord(dzrShadow0) + g.Integers['i']);
    el := L.Kids[role];
    Rect(RoleName(role) + ' clip', el.Clip, g.Objects['clip']);
    Rect(RoleName(role) + ' rect', el.Rect, g.Objects['rect']);
    Mat(RoleName(role) + ' local', el.Local, g.Arrays['local']);
  end;
  { every element, in paint order }
  els := v.Arrays['elements'];
  paint := '';
  for k := 0 to els.Count - 1 do
  begin
    e := els.Objects[k];
    if paint <> '' then paint := paint + ',';
    paint := paint + e.Strings['role'];
    if not RoleOf(e.Strings['role'], role) then
    begin
      Miss('unknown role ' + e.Strings['role']);
      Continue;
    end;
    if e.Strings['type'] = 'text' then
    begin
      lb := L.Labels[Ord(role) - Ord(dzrLabel0)];
      Inc(FCompared);
      if (lb.Text <> e.Strings['text']) or (HText(lb.AlignH) <> e.Strings['align'])
        or (VText(lb.AlignV) <> e.Strings['verticalAlign'])
        or (lb.Visible = e.Booleans['invisible']) then
        Miss(Format('%s: "%s" %s/%s upstream, "%s" %s/%s here', [RoleName(role),
          e.Strings['text'], e.Strings['align'], e.Strings['verticalAlign'], lb.Text,
          HText(lb.AlignH), VText(lb.AlignV)]));
      Num(RoleName(role) + ' x', lb.X, e.Find('textX'));
      Num(RoleName(role) + ' y', lb.Y, e.Find('textY'));
      Rect(RoleName(role) + ' rect', lb.Rect, e.Objects['rect']);
      Rect(RoleName(role) + ' global rect', TyRectApplyMat(lb.Rect, TyMatMul(G0, TyMatIdentity)),
        e.Objects['globalRect']);
      Continue;
    end;
    el := L.Kids[role];
    Inc(FCompared);
    if not el.Present then
    begin
      Miss(RoleName(role) + ' is not here');
      Continue;
    end;
    M := TyDzGlobal(L, role);
    Rect(RoleName(role) + ' rect', el.Rect, e.Objects['rect']);
    Mat(RoleName(role) + ' local', el.Local, e.Arrays['local']);
    Mat(RoleName(role) + ' global', M, e.Arrays['global']);
    Rect(RoleName(role) + ' global rect', TyRectApplyMat(el.Rect, M),
      e.Objects['globalRect']);
    if e.Strings['type'] = 'rect' then
    begin
      shape := e.Objects['shape'];
      Rect(RoleName(role) + ' shape', el.Shape, shape);
      { the corners: zero, absent and an empty list all mean square }
      radii := nil;
      d := shape.Find('r');
      if (d <> nil) and (d.JSONType = jtNumber) then
      begin
        SetLength(radii, 1);
        radii[0] := d.AsFloat;
      end
      else if (d <> nil) and (d.JSONType = jtArray) then
      begin
        SetLength(radii, TJSONArray(d).Count);
        for j := 0 to High(radii) do radii[j] := TJSONArray(d).Floats[j];
      end;
      allZero := True;
      for j := 0 to High(radii) do if radii[j] <> 0 then allZero := False;
      same := True;
      if (d <> nil) and (d.JSONType = jtArray) then
        same := el.HasR and (Length(el.R) = Length(radii))
      else if allZero then
        same := (not el.HasR) or (Length(el.R) = 0) or ((Length(el.R) = 1) and (el.R[0] = 0))
      else
        same := el.HasR and (Length(el.R) = 1);
      if same then
        for j := 0 to Min(High(radii), High(el.R)) do
          if radii[j] <> el.R[j] then same := False;
      Inc(FCompared);
      if not same then Miss(RoleName(role) + ' corners differ');
    end;
    arr := nil;
    if e.Find('path') <> nil then arr := e.Arrays['path'];
    if arr <> nil then
    begin
      PathData(RoleName(role) + ' path', el.Path, arr);
      Rect(RoleName(role) + ' path rect', el.PathRect, e.Objects['pathRect']);
    end;
    if e.Find('pathLen') <> nil then
    begin
      Inc(FCompared);
      if el.DataLen <> e.Integers['pathLen'] then
        Miss(Format('%s: data length %d upstream, %d here', [RoleName(role),
          e.Integers['pathLen'], el.DataLen]));
    end;
  end;
  { the paint order, the unpainted labels last }
  Inc(FCompared);
  if Length(L.Paint) <> els.Count then
    Miss(Format('%d elements painted upstream, %d here', [els.Count, Length(L.Paint)]))
  else
    for k := 0 to els.Count - 1 do
      if RoleName(L.Paint[k]) <> els.Objects[k].Strings['role'] then
      begin
        Miss(Format('paint %d is %s upstream, %s here', [k, els.Objects[k].Strings['role'],
          RoleName(L.Paint[k])]));
        Break;
      end;
  Inc(FCompared);
  n := 0;
  for k := 0 to els.Count - 1 do
    if els.Objects[k].Booleans['painted'] then Inc(n);
  if n <> L.Painted then Miss(Format('%d painted upstream, %d here', [n, L.Painted]));
  Rect('final slider rect', L.FinalSliderRect, v.Objects['finalSliderRect']);
  Rect('final group rect', L.FinalGroupRect, v.Objects['finalGroupRect']);
  Rect('final group global rect', TyRectApplyMat(L.FinalGroupRect, G0),
    v.Objects['finalGroupGlobalRect']);
end;

procedure TAdvChartDataZoomSliderOracleTest.RunCases(const APrefix: string;
  AMin: Integer);
var
  cases, dzs: TJSONArray;
  cs, opt, dz: TJSONObject;
  sl: TStringList;
  c, k: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if Copy(cs.Strings['id'], 1, Length(APrefix)) <> APrefix then Continue;
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
      dzs := cs.Arrays['dataZooms'];
      for k := 0 to dzs.Count - 1 do
      begin
        dz := dzs.Objects[k];
        if dz.Strings['subType'] <> 'slider' then
        begin
          { an inside or a toolbox dataZoom draws nothing }
          Inc(FCompared);
          if FChart.DataZoomSliderLayout(dz.Integers['index']).Valid then
            Miss(Format('dz%d: a %s laid out as a slider', [dz.Integers['index'],
              dz.Strings['subType']]));
          Continue;
        end;
        FName := cs.Strings['id'] + ' dz' + IntToStr(dz.Integers['index']);
        CheckSlider(dz);
      end;
    finally
      opt.Free;
    end;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > AMin);
end;

procedure TAdvChartDataZoomSliderOracleTest.SetUp;
var sl: TStringList; ms: TJSONArray; k: Integer; m: TJSONObject;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TDzsProbe.Create(FForm);
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
  FMeas := TDzsMeasurer.Create;
  FChart.Measurer := FMeas;
  ms := TJSONObject(FRoot).Arrays['measure'];
  for k := 0 to ms.Count - 1 do
  begin
    m := ms.Objects[k];
    FMeas.Add(m.Strings['string'], FromHex(m.Strings['width']),
      FromHex(m.Strings['height']));
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartDataZoomSliderOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  FreeAndNil(FBmp);
  if FChart <> nil then FChart.Measurer := nil;
  FChart := nil;
  FMeas := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartDataZoomSliderOracleTest.TestSlidersAsUpstreamLaysThemOut;
begin
  RunCases('D', 3000);
end;

procedure TAdvChartDataZoomSliderOracleTest.TestGallerySlidersAsUpstream;
begin
  RunCases('G-', 300);
end;

procedure TAdvChartDataZoomSliderOracleTest.TestTheSliderIsDrawn;
var
  lst: TTyPaintList;
  k, handles, polys, lines, fills: Integer;
  e: TTyChartElement;
  L: TTyDzSliderLayout;
  r: TTyXYWH;
begin
  FChart.Option := '{"xAxis": {"type": "category", "data": ["a", "b", "c", "d"]},'
    + ' "yAxis": {}, "series": [{"type": "line", "data": [3, 1, 4, 1]}],'
    + ' "dataZoom": [{"type": "slider", "start": 25, "end": 75}]}';
  FChart.SetBounds(0, 0, 800, 600);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
  lst := FChart.List;
  L := FChart.DataZoomSliderLayout(0);
  AssertTrue('laid out', L.Valid);
  handles := 0;
  polys := 0;
  lines := 0;
  fills := 0;
  for k := 0 to lst.Count - 1 do
  begin
    e := lst.Element(k);
    if e.Datum.SeriesIndex <> -1 then Continue;
    if e.Z2 = 5 then Inc(handles);
    if (e.Z2 = -20) and (e.Shape.Kind = cskPolygon) then
    begin
      Inc(polys);
      { each shadow cut to its stretch of the slider }
      AssertTrue('a shadow polygon is clipped', e.HasClip);
      r := TyRectApplyMat(L.Kids[TTyDzRole(Ord(dzrShadow0) + polys - 1)].Clip,
        TyDzGlobal(L, TTyDzRole(Ord(dzrShadow0) + polys - 1)));
      AssertEquals('clip left', r.X, e.ClipRect.Left, 1e-9);
      AssertEquals('clip right', r.X + r.W, e.ClipRect.Right, 1e-9);
    end;
    if (e.Z2 = -19) and (e.Shape.Kind = cskPolyline) then Inc(lines);
    if (e.Z2 = 0) and e.Style.HasFill and (e.Shape.Kind = cskRect) then
    begin
      Inc(fills);
      { the theme's filler }
      AssertEquals('the filler is the theme''s', Integer(TTyChartColor(FCtl.Model.ResolveStyle(
        'TyAdvChartDataZoomFiller', '', []).Background.Color)), Integer(e.Style.FillColor));
      r := TyRectApplyMat(L.Kids[dzrFiller].Shape, TyDzGlobal(L, dzrFiller));
      AssertEquals('filler left', r.X, e.Shape.Bounds.Left, 1e-9);
      AssertEquals('filler width', r.W, e.Shape.Bounds.Right - e.Shape.Bounds.Left, 1e-9);
    end;
  end;
  AssertEquals('two handles', 2, handles);
  AssertEquals('three shadow polygons', 3, polys);
  AssertEquals('three shadow polylines', 3, lines);
  { the filler; the transparent background and click panel draw nothing }
  AssertEquals('the filler', 1, fills);
end;

procedure TAdvChartDataZoomSliderOracleTest.TestTheSliderTakesTheAuthorsInk;
var
  lst: TTyPaintList;
  k, seen, polys: Integer;
  e: TTyChartElement;
begin
  { what the author writes wins over the skin: the filler's colour and
    alpha, the handles' rim and its width, and an area colour written
    without an opacity takes upstream's default fifth }
  FChart.Option := '{"xAxis": {"type": "category", "data": ["a", "b", "c", "d"]},'
    + ' "yAxis": {}, "series": [{"type": "line", "data": [3, 1, 4, 1]}],'
    + ' "dataZoom": [{"type": "slider", "start": 25, "end": 75,'
    + ' "fillerColor": "rgba(255,0,0,0.25)",'
    + ' "handleStyle": {"borderColor": "#00ff00", "borderWidth": 2},'
    + ' "dataBackground": {"areaStyle": {"color": "#0000ff"}}}]}';
  FChart.SetBounds(0, 0, 800, 600);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
  lst := FChart.List;
  seen := 0;
  polys := 0;
  for k := 0 to lst.Count - 1 do
  begin
    e := lst.Element(k);
    if e.Datum.SeriesIndex <> -1 then Continue;
    if (e.Z2 = 0) and e.Style.HasFill and (e.Shape.Kind = cskRect) then
    begin
      AssertEquals('filler rgb', $FF0000, Integer(e.Style.FillColor and $FFFFFF));
      AssertEquals('filler alpha', Round(255 * 0.25), Integer(e.Style.FillColor shr 24));
      Inc(seen);
    end;
    if e.Z2 = 5 then
    begin
      AssertEquals('handle rim', $00FF00, Integer(e.Style.StrokeColor and $FFFFFF));
      AssertEquals('handle rim width', 2, e.Style.StrokeWidthLogical, 0);
      Inc(seen);
    end;
    if (e.Z2 = -20) and (e.Shape.Kind = cskPolygon) then Inc(polys);
    if (e.Z2 = -20) and (e.Shape.Kind = cskPolygon) and (polys = 1) then
    begin
      { the outer stretches take dataBackground; the author's blue at 0.2 }
      AssertEquals('area rgb', $0000FF, Integer(e.Style.FillColor and $FFFFFF));
      AssertEquals('area alpha', Round(255 * 0.2), Integer(e.Style.FillColor shr 24));
      Inc(seen);
    end;
  end;
  AssertEquals('filler, two handles, the first shadow', 4, seen);
end;

procedure TAdvChartDataZoomSliderOracleTest.TestTheBoxMergeKeepsTwoOfThree;
var b, m: TTyRawBox;
begin
  { D13b: left and right written -- exactly those two, the width gone }
  b := Default(TTyRawBox);
  b.Left := TyBoxRawNum(50);
  b.Right := TyBoxRawNum(80);
  m := TyDzMergeBox(b);
  AssertTrue('left kept', (m.Left.Kind = brNumber) and (m.Left.Num = 50));
  AssertTrue('right kept', (m.Right.Kind = brNumber) and (m.Right.Num = 80));
  AssertTrue('width dropped', m.Width.Kind = brAbsent);
  { D13d: left alone -- the width placeholder beside it }
  b := Default(TTyRawBox);
  b.Left := TyBoxRawNum(50);
  m := TyDzMergeBox(b);
  AssertTrue('width placeholder', (m.Width.Kind = brString) and (m.Width.Str = 'ph'));
  AssertTrue('right dropped', m.Right.Kind = brAbsent);
end;

procedure TAdvChartDataZoomSliderOracleTest.TestAShadowSkipsByTheStride;
var
  this_, other: TTyDoubleArray;
  area, line: TTyPointFArray;
  e0, e1, o0, o1: Double;
  k: Integer;
begin
  { ten rows on a four-pixel slider: stride round(10 / 4) = 3, every third
    row drawn, the skipped ones still stepping the coordinate }
  SetLength(this_, 10);
  SetLength(other, 10);
  for k := 0 to 9 do
  begin
    this_[k] := k;
    other[k] := k;
  end;
  TyDzShadowPoints(this_, other, 4, 30, False, area, line, e0, e1, o0, o1);
  AssertEquals('rows 0, 3, 6, 9', 4, Length(line));
  AssertTrue('the fourth drawn row at the end', SameValue(line[3].X, 4, 1e-12));
end;

initialization
  RegisterTest(TAdvChartDataZoomSliderOracleTest);
end.
