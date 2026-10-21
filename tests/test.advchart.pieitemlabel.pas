unit test.advchart.pieitemlabel;
{$mode objfpc}{$H+}
{ A PIE'S DATA ITEMS' OWN `label` AND `labelLine`, held to ECharts 6.1.
  [R2-A b2, spec 218]

  tools/advchart-oracle/pie-item-label.js runs the real dist and records
  every slice's label -- its words, whether it is hidden, where its computed
  transform puts it, its turn and alignment, its global rect, the painted
  ink -- and its guide line, for items that write their own formatter,
  colour, show, position (inside, '', null), distanceToLabelLine, alignTo,
  rotate, rich block and labelLine, and for a position the emphasis one
  stands in for.

  The control renders each option (text measured with zrender's SSR width
  table) and every slice's label and line are compared bit for bit. A label
  upstream hides (show: false) may be absent here: the port builds none. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.StyleModel,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Color, tyControls.AdvanceChart.Anim,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TPilProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartPieItemLabelOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TPilProbe;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FSeen, FGuides, FHidden: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure Num(const AWhat: string; AGot: Double; const AHex: string);
    procedure Str(const AWhat, AGot, AWant: string);
    procedure Close(const AWhat: string; AGot: Double; const AHex: string);
    procedure Ink(const AWhat: string; AGot: TTyChartColor; AWant: TJSONData;
      AOutside: Boolean);
    function Find(ARole: TTyChartAnimRole; AD: Integer; out AEl: TTyChartElement): Boolean;
    procedure CheckCase(ACase: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheItemLabelsAsUpstream;
  end;

implementation

const
  cW = 600;
  cH = 400;

function TPilProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TPilProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TPilProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
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

function IsNull(D: TJSONData): Boolean;
begin
  Result := (D = nil) or (D.JSONType = jtNull);
end;

function AlignName(AH: TTyTextAnchorH): string;
begin
  case AH of
    tahCentre: Result := 'center';
    tahRight: Result := 'right';
  else
    Result := 'left';
  end;
end;

function VAlignName(AV: TTyTextAnchorV): string;
begin
  case AV of
    tavMiddle: Result := 'middle';
    tavBottom: Result := 'bottom';
  else
    Result := 'top';
  end;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-pie-item-label.json';
end;

procedure TAdvChartPieItemLabelOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-text-style.json');
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart := TPilProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, cW, cH);
  FBad := 0;
  FCompared := 0;
  FSeen := 0;
  FGuides := 0;
  FHidden := 0;
  FReport := '';
end;

procedure TAdvChartPieItemLabelOracleTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FRoot);
  FreeAndNil(FMeasure);
  FreeAndNil(FBmp);
  inherited TearDown;
end;

procedure TAdvChartPieItemLabelOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartPieItemLabelOracleTest.Num(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if Bits(AGot) <> Bits(FromHex(AHex)) then
    Miss(Format('%s %s upstream, %s here', [AWhat, Fmt(FromHex(AHex)), Fmt(AGot)]));
end;

procedure TAdvChartPieItemLabelOracleTest.Close(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if not SameValue(AGot, FromHex(AHex), 1e-9) then
    Miss(Format('%s %s upstream, %s here', [AWhat, Fmt(FromHex(AHex)), Fmt(AGot)]));
end;

procedure TAdvChartPieItemLabelOracleTest.Str(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then Miss(Format('%s "%s" upstream, "%s" here', [AWhat, AWant, AGot]));
end;

{ a painted colour; upstream's automatic outside #333 is the theme's own ink
  here (test.advchart.insidelabel) }
procedure TAdvChartPieItemLabelOracleTest.Ink(const AWhat: string; AGot: TTyChartColor;
  AWant: TJSONData; AOutside: Boolean);
var c: TTyChartColor;
begin
  Inc(FCompared);
  if IsNull(AWant) then
  begin
    if (AGot shr 24) <> 0 then Miss(Format('%s none upstream, $%.8x here', [AWhat, AGot]));
    Exit;
  end;
  if not TyTryParseChartColor(AWant.AsString, c) then
  begin
    Miss(AWhat + ' unparsed ' + AWant.AsString);
    Exit;
  end;
  if AOutside and (c = TTyChartColor($FF333333)) then
    c := TTyChartColor(FCtl.Model.ResolveStyle('TyAdvChartLabel', '', []).TextColor);
  if c <> AGot then
    Miss(Format('%s %s ($%.8x) upstream, $%.8x here', [AWhat, AWant.AsString, c, AGot]));
end;

function TAdvChartPieItemLabelOracleTest.Find(ARole: TTyChartAnimRole; AD: Integer;
  out AEl: TTyChartElement): Boolean;
var i: Integer;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  for i := 0 to FChart.List.Count - 1 do
    if (FChart.List.Element(i).Anim.Role = ARole)
      and (FChart.List.Element(i).Datum.SeriesIndex = 0)
      and (FChart.List.Element(i).Datum.DataIndex = AD) then
    begin
      AEl := FChart.List.Element(i);
      Exit(True);
    end;
end;

procedure TAdvChartPieItemLabelOracleTest.CheckCase(ACase: TJSONObject);
var
  labs, rect, pts: TJSONArray;
  i, k: Integer;
  lb, gd: TJSONObject;
  el, ge: TTyChartElement;
  b: TTyRectF;
  full: string;
begin
  FChart.Option := '{}';
  FChart.Option := ACase.Objects['option'].AsJSON;
  AssertEquals(ACase.Strings['id'] + ': the option parses', '', FChart.OptionError);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
  labs := ACase.Arrays['labels'];
  for i := 0 to labs.Count - 1 do
  begin
    lb := labs.Objects[i];
    FName := Format('%s d%d', [ACase.Strings['id'], lb.Integers['d']]);
    { ---- the words ---- }
    Inc(FCompared);
    if not Find(carLabel, lb.Integers['d'], el) then
    begin
      if lb.Booleans['ignore'] then Inc(FHidden)
      else Miss('a label upstream, none here');
    end
    else if lb.Booleans['ignore'] then
    begin
      Inc(FHidden);
      if not el.Ignore then Miss('hidden upstream, shown here');
    end
    else
    begin
      Inc(FSeen);
      if el.Ignore then Miss('shown upstream, hidden here');
      full := el.Caption.LmText;
      if full = '' then full := el.Caption.Text;
      Str('text', full, lb.Strings['text']);
      Num('x', el.Caption.X, lb.Strings['x']);
      Num('y', el.Caption.Y, lb.Strings['y']);
      Num('rotation', el.Caption.RotationRad, lb.Strings['rotation']);
      Str('align', AlignName(el.Caption.AnchorH), lb.Strings['align']);
      Str('verticalAlign', VAlignName(el.Caption.AnchorV), lb.Strings['verticalAlign']);
      { THE BOX, where the label is level (a turned one-run label's box is
        not turned here); its width and height come from its edges, an ulp
        either way }
      if el.Caption.RotationRad = 0 then
      begin
        rect := lb.Arrays['rect'];
        b := el.Shape.Bounds;
        Num('rect x', b.Left, rect.Strings[0]);
        Num('rect y', b.Top, rect.Strings[1]);
        Close('rect w', b.Right - b.Left, rect.Strings[2]);
        Close('rect h', b.Bottom - b.Top, rect.Strings[3]);
      end;
      { a block's ink is its pieces'; a one-run label's the caption's }
      if Length(el.Caption.RtPieces) = 0 then
      begin
        Ink('fill', el.Caption.Colour, lb.Find('fill'), not el.Caption.LmInkInside);
        if IsNull(lb.Find('stroke')) then
        begin
          Inc(FCompared);
          if (el.Caption.StrokeWidthLogical > 0) and ((el.Caption.StrokeColour shr 24) <> 0) then
            Miss('no halo upstream, one here');
        end
        else
        begin
          Ink('stroke', el.Caption.StrokeColour, lb.Find('stroke'), False);
          Num('lineWidth', el.Caption.StrokeWidthLogical, lb.Strings['lineWidth']);
        end;
      end;
    end;
    { ---- the guide line ---- }
    Inc(FCompared);
    if IsNull(lb.Find('guide')) then
    begin
      if Find(carGuide, lb.Integers['d'], ge) then Miss('no line upstream, one here');
      Continue;
    end;
    gd := lb.Objects['guide'];
    if not Find(carGuide, lb.Integers['d'], ge) then
    begin
      { A HIDDEN LINE upstream (labelLine.show false, or its label hidden)
        is no line here: the port builds none }
      if not gd.Booleans['ignore'] then
        Miss('a line upstream, none here');
      Continue;
    end;
    Inc(FGuides);
    Inc(FCompared);
    if ge.Ignore <> gd.Booleans['ignore'] then
      Miss(Format('line hidden %s upstream, %s here',
        [BoolToStr(gd.Booleans['ignore'], True), BoolToStr(ge.Ignore, True)]));
    if gd.Booleans['ignore'] then Continue;
    pts := gd.Arrays['points'];
    Inc(FCompared);
    if Length(ge.Shape.Points) <> pts.Count then
      Miss(Format('%d line points upstream, %d here', [pts.Count, Length(ge.Shape.Points)]))
    else
      for k := 0 to pts.Count - 1 do
      begin
        Num('line x' + IntToStr(k), ge.Shape.Points[k].X, TJSONArray(pts.Items[k]).Strings[0]);
        Num('line y' + IntToStr(k), ge.Shape.Points[k].Y, TJSONArray(pts.Items[k]).Strings[1]);
      end;
  end;
end;

procedure TAdvChartPieItemLabelOracleTest.TestTheItemLabelsAsUpstream;
var
  cases: TJSONArray;
  c: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
    CheckCase(cases.Objects[c]);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > 400);
  AssertTrue(Format('labels compared (%d)', [FSeen]), FSeen >= 30);
  AssertTrue(Format('lines compared (%d)', [FGuides]), FGuides >= 20);
  AssertTrue(Format('hidden labels compared (%d)', [FHidden]), FHidden >= 5);
end;

initialization
  RegisterTest(TAdvChartPieItemLabelOracleTest);
end.
