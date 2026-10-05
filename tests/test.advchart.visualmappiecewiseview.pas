unit test.advchart.visualmappiecewiseview;
{$mode objfpc}{$H+}
{ A piecewise visualMap's own picture -- PiecewiseView: an item group per
  piece (the controller's symbol in the item box, the label beside it), the
  ends texts, layout.box stacking them with the NEXT child's offset, the
  background and where positionGroup puts the view group -- held to what
  ECharts 6.1 itself lays out.

  tools/advchart-oracle/visualmap-piecewise.js records every child's
  position and rect, the symbol's type, box, fill and bounding rect, each
  label's text, anchor, alignment, opacity and rect, the two bounding rects
  upstream reads and the group's final place. Text sizes are zrender's own
  measure, fed through a table measurer.

  EXACT: bit for bit, -0 and 0 one. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Layout, tyControls.AdvChart.VisualMap,
     tyControls.AdvChart.VisualMapView, tyControls.AdvanceChart;
type
  TVmpvMeasurer = class(TInterfacedObject, ITyTextMeasurer)
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

  TVmpvProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartVisualMapPiecewiseViewOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TVmpvProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FMeas: TVmpvMeasurer;
    FBad, FCompared: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure Num(const AWhat: string; AGot: Double; const AHex: string);
    procedure Rect(const AWhat: string; const AGot: TTyXYWH; ARec: TJSONObject);
    procedure CheckText(const AWhat: string; const AGot: TTyVmText;
      AOpacity: Double; ARec: TJSONObject; AGlobalX, AGlobalY: Double);
    procedure CheckView(AIndex: Integer; AVm: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryPiecewiseViewAsUpstreamLaysItOut;
    procedure TestSymbolRectsAreZrenders;
    procedure TestTheItemsAreDrawn;
  end;

implementation

uses tyControls.AdvChart.Scale;

constructor TVmpvMeasurer.Create;
begin
  inherited Create;
  Names := TStringList.Create;
  { 'low' and 'Low' are two strings }
  Names.CaseSensitive := True;
end;

destructor TVmpvMeasurer.Destroy;
begin
  Names.Free;
  inherited Destroy;
end;

procedure TVmpvMeasurer.Add(const AText: string; AW, AH: Double);
var k: Integer;
begin
  if Names.IndexOf(AText) >= 0 then Exit;
  k := Names.Add(AText);
  SetLength(W, k + 1);
  SetLength(H, k + 1);
  W[k] := AW;
  H[k] := AH;
end;

procedure TVmpvMeasurer.MeasureLine(const AText, AFontName: string;
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

function TVmpvMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
begin
  Result := AText;
end;

function TVmpvProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Exit(Measurer);
  Result := inherited NewTextMeasurer(APPI);
end;

procedure TVmpvProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TVmpvProbe.List: TTyPaintList;
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

function SameColour(const C: TTyVisualColor; AObj: TJSONObject): Boolean;
begin
  if AObj.Booleans['undef'] then Exit(not C.Defined);
  Result := C.Defined and (C.R = AObj.Integers['r'])
    and (C.G = AObj.Integers['g']) and (C.B = AObj.Integers['b'])
    and SameNum(C.A, AObj.Strings['a']);
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

function XYWH(AX, AY, AW, AH: Double): TTyXYWH;
begin
  Result.X := AX;
  Result.Y := AY;
  Result.W := AW;
  Result.H := AH;
end;

procedure TAdvChartVisualMapPiecewiseViewOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartVisualMapPiecewiseViewOracleTest.Num(const AWhat: string;
  AGot: Double; const AHex: string);
begin
  Inc(FCompared);
  if not SameNum(AGot, AHex) then
    Miss(Format('%s: %s upstream, %s here', [AWhat, Fmt(FromHex(AHex)), Fmt(AGot)]));
end;

procedure TAdvChartVisualMapPiecewiseViewOracleTest.Rect(const AWhat: string;
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

{ a label or an ends text, and the caption drawn for it at the global
  point }
procedure TAdvChartVisualMapPiecewiseViewOracleTest.CheckText(const AWhat: string;
  const AGot: TTyVmText; AOpacity: Double; ARec: TJSONObject; AGlobalX,
  AGlobalY: Double);
var
  lst: TTyPaintList;
  k, found: Integer;
  e: TTyChartElement;
  gx, gy: Double;
begin
  Inc(FCompared);
  if AGot.Text <> ARec.Strings['string'] then
  begin
    Miss(Format('%s: "%s" upstream, "%s" here', [AWhat, ARec.Strings['string'], AGot.Text]));
    Exit;
  end;
  Num(AWhat + ' x', AGot.X, ARec.Strings['x']);
  Num(AWhat + ' y', AGot.Y, ARec.Strings['y']);
  Inc(FCompared);
  if (HText(AGot.AlignH) <> ARec.Strings['align'])
    or (VText(AGot.AlignV) <> ARec.Strings['verticalAlign']) then
    Miss(Format('%s: %s/%s upstream, %s/%s here', [AWhat, ARec.Strings['align'],
      ARec.Strings['verticalAlign'], HText(AGot.AlignH), VText(AGot.AlignV)]));
  if (ARec.Find('opacity') <> nil) and (ARec.Find('opacity').JSONType = jtString) then
    Num(AWhat + ' opacity', AOpacity, ARec.Strings['opacity']);
  Rect(AWhat + ' rect', AGot.Rect, ARec.Objects['rect']);
  { AND DRAWN THERE }
  lst := FChart.List;
  gx := AGlobalX + AGot.X;
  gy := AGlobalY + AGot.Y;
  found := 0;
  if lst <> nil then
    for k := 0 to lst.Count - 1 do
    begin
      e := lst.Element(k);
      if (e.Caption.Text = AGot.Text) and (e.Caption.X = gx) and (e.Caption.Y = gy) then
      begin
        Inc(found);
        { the opacity on the skin's text colour }
        if Abs(Integer(e.Caption.Colour shr 24) - Round(Integer(TTyChartColor(
          FCtl.Model.ResolveStyle('TyAdvChartVisualMap', '', []).TextColor) shr 24)
          * AOpacity)) > 1 then
          Miss(Format('%s: drawn at alpha %d', [AWhat, e.Caption.Colour shr 24]));
      end;
    end;
  Inc(FCompared);
  if found = 0 then
    Miss(Format('%s: no caption "%s" drawn at %s,%s', [AWhat, AGot.Text, Fmt(gx), Fmt(gy)]));
end;

procedure TAdvChartVisualMapPiecewiseViewOracleTest.CheckView(AIndex: Integer;
  AVm: TJSONObject);
var
  L: TTyVisualMapLayout;
  v, ch, sym, sh: TJSONObject;
  kids, ends: TJSONArray;
  k: Integer;
  it: TTyVmItem;
  gx, gy: Double;
begin
  L := FChart.VisualMapLayout(AIndex);
  Inc(FCompared);
  if not AVm.Booleans['show'] then
  begin
    if L.Valid then Miss('shown here, hidden upstream');
    Exit;
  end;
  if not L.Valid then
  begin
    Miss('not laid out here');
    Exit;
  end;
  v := AVm.Objects['view'];
  Inc(FCompared);
  if L.ItemAlign <> v.Strings['itemAlign'] then
    Miss(Format('item align %s upstream, %s here', [v.Strings['itemAlign'], L.ItemAlign]));
  if L.ShowLabel <> v.Booleans['labels'] then
    Miss(Format('labels %s here', [BoolToStr(L.ShowLabel, True)]));
  ends := nil;
  if v.Find('endsText').JSONType = jtArray then ends := v.Arrays['endsText'];
  Inc(FCompared);
  if (ends <> nil) <> L.HasEnds then
    Miss('ends text differs')
  else if (ends <> nil) and ((ends.Strings[0] <> L.EndsText[0])
    or (ends.Strings[1] <> L.EndsText[1])) then
    Miss(Format('ends %s upstream, [%s, %s] here', [ends.AsJSON, L.EndsText[0], L.EndsText[1]]));
  Num('group x', L.GroupX, v.Objects['group'].Strings['x']);
  Num('group y', L.GroupY, v.Objects['group'].Strings['y']);
  Rect('bbox for the background', L.BBoxBackground, v.Objects['bboxBackground'].Objects['rect']);
  Rect('background', L.Background, v.Objects['background'].Objects['shape']);
  Rect('bbox for the position', L.BBoxPosition, v.Objects['bboxPosition'].Objects['rect']);
  kids := v.Arrays['children'];
  Inc(FCompared);
  if Length(L.Items) <> kids.Count then
  begin
    Miss(Format('%d children upstream, %d here', [kids.Count, Length(L.Items)]));
    Exit;
  end;
  for k := 0 to kids.Count - 1 do
  begin
    ch := kids.Objects[k];
    it := L.Items[k];
    Inc(FCompared);
    if it.IsText <> (ch.Strings['kind'] = 'endText') then
    begin
      Miss(Format('child %d: %s upstream', [k, ch.Strings['kind']]));
      Continue;
    end;
    Num(Format('child %d x', [k]), it.X, ch.Strings['x']);
    Num(Format('child %d y', [k]), it.Y, ch.Strings['y']);
    Rect(Format('child %d rect', [k]), it.Rect, ch.Objects['rect']);
    gx := L.GroupX + it.X;
    gy := L.GroupY + it.Y;
    if it.IsText then
    begin
      CheckText(Format('child %d text', [k]), it.Label_, 1, ch.Objects['text'], gx, gy);
      Continue;
    end;
    Inc(FCompared);
    if it.PieceIndex <> ch.Integers['pieceIndex'] then
      Miss(Format('child %d: piece %d upstream, %d here', [k, ch.Integers['pieceIndex'],
        it.PieceIndex]));
    sym := ch.Objects['symbol'];
    sh := sym.Objects['shape'];
    Inc(FCompared);
    if it.Symbol <> sym.Strings['symbolType'] then
      Miss(Format('child %d: symbol %s upstream, %s here', [k, sym.Strings['symbolType'],
        it.Symbol]));
    if not ((it.SymbolBox.X = sh.Floats['x']) and (it.SymbolBox.Y = sh.Floats['y'])
      and (it.SymbolBox.W = sh.Floats['width']) and (it.SymbolBox.H = sh.Floats['height'])) then
      Miss(Format('child %d: symbol box differs', [k]));
    Inc(FCompared);
    if not SameColour(it.Fill, sym.Objects['fill']) then
      Miss(Format('child %d: fill %s upstream', [k, sym.Objects['fill'].Strings['css']]));
    Rect(Format('child %d symbol rect', [k]), it.SymbolRect, sym.Objects['rect']);
    Inc(FCompared);
    if (ch.Find('label').JSONType = jtObject) <> it.HasLabel then
      Miss(Format('child %d: label %s here', [k, BoolToStr(it.HasLabel, True)]))
    else if it.HasLabel then
      CheckText(Format('child %d label', [k]), it.Label_, it.LabelOpacity,
        ch.Objects['label'], gx, gy);
  end;
end;

procedure TAdvChartVisualMapPiecewiseViewOracleTest.SetUp;
var sl: TStringList; ms: TJSONArray; k: Integer; m: TJSONObject;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TVmpvProbe.Create(FForm);
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
  FMeas := TVmpvMeasurer.Create;
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

procedure TAdvChartVisualMapPiecewiseViewOracleTest.TearDown;
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

procedure TAdvChartVisualMapPiecewiseViewOracleTest.TestEveryPiecewiseViewAsUpstreamLaysItOut;
const
  cPalette = '["#5070dd","#b6d634","#505372","#ff994d","#0ca8df","#ffd10a",'
    + '"#fb628b","#785db0","#3fbe95"]';
var
  cases, vms: TJSONArray;
  cs, opt, vm: TJSONObject;
  d: TJSONData;
  sl: TStringList;
  c, k: Integer;

  procedure Upstream(AVm: TJSONObject);
  begin
    if AVm.Find('contentColor') = nil then AVm.Add('contentColor', '#5070dd');
    if AVm.Find('inactiveColor') = nil then AVm.Add('inactiveColor', '#cfd2d7');
  end;

begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
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
      for k := 0 to vms.Count - 1 do
      begin
        vm := vms.Objects[k];
        FName := cs.Strings['id'] + ' vm' + IntToStr(vm.Integers['index']);
        CheckView(vm.Integers['index'], vm);
      end;
    finally
      opt.Free;
    end;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > 2000);
end;

procedure TAdvChartVisualMapPiecewiseViewOracleTest.TestSymbolRectsAreZrenders;
var r: TTyXYWH;
begin
  { V9: a circle in 20.3 x 14.1 -- cx - r and (cx + r) - (cx - r) }
  r := TyVmSymbolRect('circle', XYWH(0, 0, 20.3, 14.1));
  AssertTrue('circle x ' + Fmt(r.X), SameNum(r.X, '4008ccccccccccce'));
  AssertTrue('circle w ' + Fmt(r.W), SameNum(r.W, '402c333333333332'));
  AssertTrue('circle y ' + Fmt(r.Y), SameNum(r.Y, '0000000000000000'));
  AssertTrue('circle h ' + Fmt(r.H), SameNum(r.H, '402c333333333333'));
  { a round rect's corners reach its box }
  r := TyVmSymbolRect('roundRect', XYWH(0, 0, 20, 14));
  AssertTrue('roundRect', (r.X = 0) and (r.Y = 0) and (r.W = 20) and (r.H = 14));
end;

procedure TAdvChartVisualMapPiecewiseViewOracleTest.TestTheItemsAreDrawn;
var
  lst: TTyPaintList;
  k, n: Integer;
  e: TTyChartElement;
begin
  FChart.Option := '{"visualMap": {"type": "piecewise", "min": 0, "max": 100,'
    + ' "inRange": {"color": ["#000000", "#ff0000"]}},'
    + ' "xAxis": {"type": "category", "data": ["a"]}, "yAxis": {},'
    + ' "series": [{"type": "bar", "data": [30]}]}';
  FChart.SetBounds(0, 0, 800, 600);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
  lst := FChart.List;
  n := 0;
  for k := 0 to lst.Count - 1 do
  begin
    e := lst.Element(k);
    if (e.Datum.SeriesIndex = -1) and e.Style.HasFill
      and (e.Shape.Kind <> cskRect) then Inc(n);
  end;
  { five pieces, five round rects }
  AssertEquals('an item per piece', 5, n);
end;

initialization
  RegisterTest(TAdvChartVisualMapPiecewiseViewOracleTest);
end.
