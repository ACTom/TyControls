unit test.advchart.labelfontstates;
{$mode objfpc}{$H+}
{ THE AUTHOR'S FONT ON A LABEL, AT REST AND HOVERED, held to ECharts 6.1.
  [R5-F, spec 243]

  tools/advchart-oracle/label-font-states.js runs the real dist and records
  every label of series 0 -- its words, whether it is hidden, its anchor and
  alignment, its global rect, and the spans painted with zrender's font
  string -- for pies and funnels whose label (or an item's) writes
  fontSize / fontWeight, the root textStyle under them, and, after a
  highlight action, the hovered label laid out again in the emphasis
  label's font and rich styles (the series' and an item's own).

  The control renders each option (text measured with zrender's SSR width
  table) and dispatches the same highlight; every label is compared: the
  words and the font of each span, the anchor and alignment, and the rect
  at rest. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.StyleModel,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Option, tyControls.AdvanceChart.Anim, tyControls.FontUnits,
     tyControls.AdvanceChart.RichStyle,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TLfsProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartLabelFontStatesOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TLfsProbe;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FRuns, FHovered: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure Num(const AWhat: string; AGot: Double; const AHex: string);
    procedure Close(const AWhat: string; AGot: Double; const AHex: string);
    procedure Str(const AWhat, AGot, AWant: string);
    function Find(AD: Integer; out AEl: TTyChartElement): Boolean;
    procedure CompareRuns(const AEl: TTyChartElement; ARuns: TJSONArray);
    procedure CompareLabels(const AId: string; ALabels: TJSONArray; AHover: Boolean);
    procedure CheckCase(ACase: TJSONObject);
    procedure NewChart;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheLabelFontsAsUpstream;
  end;

implementation

const
  cW = 600;
  cH = 400;

function TLfsProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TLfsProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TLfsProbe.List: TTyPaintList;
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

{ zrender's font string 'normal bold 20px Microsoft YaHei': the weight as a
  number and the size in px }
procedure ParseFont(const AFont: string; out AWeight: Integer; out ASize: Double);
var
  parts: TStringList;
  i: Integer;
  w, s: string;
begin
  AWeight := 400;
  ASize := 0;
  parts := TStringList.Create;
  try
    parts.Delimiter := ' ';
    parts.StrictDelimiter := True;
    parts.DelimitedText := AFont;
    for i := 0 to parts.Count - 1 do
    begin
      s := parts[i];
      if (Length(s) > 2) and (Copy(s, Length(s) - 1, 2) = 'px') then
      begin
        ASize := StrToFloat(Copy(s, 1, Length(s) - 2), DefaultFormatSettings);
        if i > 0 then
        begin
          w := parts[i - 1];
          if w = 'bold' then AWeight := 700
          else if w = 'normal' then AWeight := 400
          else AWeight := StrToIntDef(w, 400);
        end;
        Exit;
      end;
    end;
  finally
    parts.Free;
  end;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-label-font-states.json';
end;

procedure TAdvChartLabelFontStatesOracleTest.SetUp;
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
  NewChart;
  FBad := 0;
  FCompared := 0;
  FRuns := 0;
  FHovered := 0;
  FReport := '';
end;

{ A CHART OF ITS OWN FOR EVERY CASE, as the oracle's: a highlight is the
  chart's state, not the option's }
procedure TAdvChartLabelFontStatesOracleTest.NewChart;
begin
  FreeAndNil(FChart);
  FChart := TLfsProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, cW, cH);
end;

procedure TAdvChartLabelFontStatesOracleTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FRoot);
  FreeAndNil(FMeasure);
  FreeAndNil(FBmp);
  inherited TearDown;
end;

procedure TAdvChartLabelFontStatesOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartLabelFontStatesOracleTest.Num(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if Bits(AGot) <> Bits(FromHex(AHex)) then
    Miss(Format('%s %s upstream, %s here', [AWhat, Fmt(FromHex(AHex)), Fmt(AGot)]));
end;

procedure TAdvChartLabelFontStatesOracleTest.Close(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if not SameValue(AGot, FromHex(AHex), 1e-9) then
    Miss(Format('%s %s upstream, %s here', [AWhat, Fmt(FromHex(AHex)), Fmt(AGot)]));
end;

procedure TAdvChartLabelFontStatesOracleTest.Str(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then Miss(Format('%s "%s" upstream, "%s" here', [AWhat, AWant, AGot]));
end;

function TAdvChartLabelFontStatesOracleTest.Find(AD: Integer;
  out AEl: TTyChartElement): Boolean;
var i: Integer;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  for i := 0 to FChart.List.Count - 1 do
    if (FChart.List.Element(i).Anim.Role = carLabel)
      and (FChart.List.Element(i).Datum.SeriesIndex = 0)
      and (FChart.List.Element(i).Datum.DataIndex = AD) then
    begin
      AEl := FChart.List.Element(i);
      Exit(True);
    end;
end;

{ the spans as painted: a one-run caption's words in its font, else the
  block's text pieces in order }
procedure TAdvChartLabelFontStatesOracleTest.CompareRuns(const AEl: TTyChartElement;
  ARuns: TJSONArray);
var
  i, n, w: Integer;
  sz: Double;
  rn: TJSONObject;
  texts: array of string;
  sizes: array of Double;
  weights: array of Integer;
begin
  texts := nil;
  sizes := nil;
  weights := nil;
  if Length(AEl.Caption.RtPieces) = 0 then
  begin
    SetLength(texts, 1);
    SetLength(sizes, 1);
    SetLength(weights, 1);
    if AEl.Caption.LmText <> '' then texts[0] := AEl.Caption.LmText
    else texts[0] := AEl.Caption.Text;
    sizes[0] := TyFontPxOf(AEl.Caption.FontSizeLogical);
    weights[0] := AEl.Caption.FontWeight and TyChartFontWeightMask;
  end
  else
    for i := 0 to High(AEl.Caption.RtPieces) do
      if AEl.Caption.RtPieces[i].Kind = rpkText then
      begin
        n := Length(texts);
        SetLength(texts, n + 1);
        SetLength(sizes, n + 1);
        SetLength(weights, n + 1);
        texts[n] := AEl.Caption.RtPieces[i].Text;
        sizes[n] := AEl.Caption.RtPieces[i].FontSizePx;
        weights[n] := AEl.Caption.RtPieces[i].FontWeight and TyChartFontWeightMask;
      end;
  Inc(FCompared);
  if Length(texts) <> ARuns.Count then
  begin
    Miss(Format('%d spans upstream, %d here', [ARuns.Count, Length(texts)]));
    Exit;
  end;
  for i := 0 to ARuns.Count - 1 do
  begin
    rn := ARuns.Objects[i];
    Inc(FRuns);
    ParseFont(rn.Strings['font'], w, sz);
    Str(Format('span %d text', [i]), texts[i], rn.Strings['text']);
    Inc(FCompared);
    if not SameValue(sizes[i], sz, 1e-9) then
      Miss(Format('span %d "%s" size %s upstream, %s here', [i, rn.Strings['text'],
        Fmt(sz), Fmt(sizes[i])]));
    { the theme's weight 0 is the normal face }
    if weights[i] = 0 then weights[i] := 400;
    Inc(FCompared);
    if weights[i] <> w then
      Miss(Format('span %d "%s" weight %d upstream, %d here', [i, rn.Strings['text'],
        w, weights[i]]));
  end;
end;

procedure TAdvChartLabelFontStatesOracleTest.CompareLabels(const AId: string;
  ALabels: TJSONArray; AHover: Boolean);
var
  i: Integer;
  lb: TJSONObject;
  el: TTyChartElement;
  rect: TJSONArray;
  b: TTyRectF;
  funnel: Boolean;
begin
  funnel := Pos('funnel', AId) = 1;
  for i := 0 to ALabels.Count - 1 do
  begin
    lb := ALabels.Objects[i];
    if AHover then FName := Format('%s hovered d%d', [AId, lb.Integers['d']])
    else FName := Format('%s d%d', [AId, lb.Integers['d']]);
    Inc(FCompared);
    if not Find(lb.Integers['d'], el) then
    begin
      if not lb.Booleans['ignore'] then Miss('a label upstream, none here');
      Continue;
    end;
    if el.Ignore <> lb.Booleans['ignore'] then
    begin
      Miss(Format('hidden %s upstream, %s here',
        [BoolToStr(lb.Booleans['ignore'], True), BoolToStr(el.Ignore, True)]));
      Continue;
    end;
    if lb.Booleans['ignore'] then Continue;
    if AHover then Inc(FHovered);
    CompareRuns(el, lb.Arrays['runs']);
    { a funnel's label hangs off its style's x / y upstream (no transform):
      its rect says where it is }
    if not funnel then
    begin
      Num('x', el.Caption.X, lb.Strings['x']);
      Num('y', el.Caption.Y, lb.Strings['y']);
    end;
    Str('align', AlignName(el.Caption.AnchorH), lb.Strings['align']);
    Str('verticalAlign', VAlignName(el.Caption.AnchorV), lb.Strings['verticalAlign']);
    { THE BOX: at rest the caption's; hovered, the block's laid out again
      (its pieces' union about the anchor) where it is one }
    if el.Caption.RotationRad = 0 then
    begin
      rect := lb.Arrays['rect'];
      if AHover and (Length(el.Caption.RtPieces) > 0) then
        b := TyRtDeviceBox(el.Caption.RtPieces, el.Caption.X, el.Caption.Y, 0,
          el.Caption.RtScale)
      else
        b := el.Shape.Bounds;
      Close('rect x', b.Left, rect.Strings[0]);
      Close('rect y', b.Top, rect.Strings[1]);
      Close('rect w', b.Right - b.Left, rect.Strings[2]);
      Close('rect h', b.Bottom - b.Top, rect.Strings[3]);
    end;
  end;
end;

procedure TAdvChartLabelFontStatesOracleTest.CheckCase(ACase: TJSONObject);
var id: string;
begin
  id := ACase.Strings['id'];
  NewChart;
  FChart.Option := ACase.Objects['option'].AsJSON;
  AssertEquals(id + ': the option parses', '', FChart.OptionError);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
  CompareLabels(id, ACase.Arrays['labels'], False);
  if ACase.Find('labelsHl') = nil then Exit;
  FChart.DispatchAction(Format('{"type":"highlight","seriesIndex":0,"dataIndex":%d}',
    [ACase.Integers['hl']]));
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
  CompareLabels(id, ACase.Arrays['labelsHl'], True);
end;

procedure TAdvChartLabelFontStatesOracleTest.TestTheLabelFontsAsUpstream;
var
  cases: TJSONArray;
  c: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
    CheckCase(cases.Objects[c]);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > 600);
  AssertTrue(Format('spans compared (%d)', [FRuns]), FRuns >= 60);
  AssertTrue(Format('hovered labels compared (%d)', [FHovered]), FHovered >= 20);
end;

initialization
  RegisterTest(TAdvChartLabelFontStatesOracleTest);
end.
