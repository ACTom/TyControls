unit test.advchart.richwiring;
{$mode objfpc}{$H+}
{ ZRENDER'S TEXT BLOCK, WIRED INTO THE CHART, held to upstream.

  tools/advchart-oracle/rich-text.js records every text the real ECharts 6.1
  build draws in its cases -- series labels, marker labels, axis labels and
  names, titles, legend items, a gauge's words -- with every piece zrender
  painted: the block's rect, each token's rect and text, in paint order, and
  where each lands on the canvas. test.advchart.richtext holds the engine to
  it with the styles zrender received; THIS holds the chart: the option goes
  through the real control (zrender's SSR measurer injected), and the pieces
  each site hung on its text -- resolved from the option, finished in the
  site's font, laid out about the site's anchor -- are compared with
  upstream's, one by one: kind, where (a text's point, a rect's four corners
  on the canvas), size, words, alignment, font, fill, stroke and its width,
  the border painted first, the corner radii, a text's shadow -- and the box
  the pieces occupy (zrender's Text getBoundingRect), which is what a legend
  lays out and the label layout overlaps.

  A SKIN THAT NAMES NO FONT WEIGHT means the normal one, 400: a block drawn
  in it is compared as 400.

  A text the port draws as its one-run caption (no rich, no box) is laid out
  here as the plain block its caption stands for, so the anchor and the font
  are compared all the same.

  WHAT IS THE SKIN'S IS NOT COMPARED: a colour upstream took from its theme
  -- a default ink or halo, the component's own colour, the palette colour an
  'inherit' names -- must be there, not be upstream's. A text whose block
  font the skin decides differently (a title's 18px bold is the skin's 12)
  has its geometry and its inherited sizes left out; what the case authored
  is compared regardless. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.FontUnits, tyControls.Types,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Layout, tyControls.AdvChart.Builder,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Color,
     tyControls.AdvChart.Title, tyControls.AdvChart.RichText,
     tyControls.AdvChart.Labels, tyControls.AdvChart.RichStyle,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TRwProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    { answer device px at the render's PPI }
    DpiAware: Boolean;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  { one text as the port drew it }
  TRwDrawn = record
    Found: Boolean;
    D: TTyRtDrawn;
    { the block's font, the skin's or the author's }
    BlockPx: Double;
    BlockWeight: Integer;
    { drawn as the one-run caption, laid out here as its plain block }
    OneRun: Boolean;
  end;

  TAdvChartRichWiringOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TRwProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FSsr: ITyTextMeasurer;
    FBad, FCompared, FSkipped, FTexts, FOneRun: Integer;
    FReport, FCase: string;
    FUsed: array of Boolean;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Miss(const AWhat: string);
    procedure Draw(ACase: TJSONObject);
    function PlainDrawn(const AText, AFont: string; ASize, AWeight: Integer;
      AHasInk: Boolean; AInk: TTyChartColor; AHasHalo: Boolean;
      AHalo: TTyChartColor; AHaloW: Double; AH: TTyTextAnchorH;
      AV: TTyTextAnchorV; AX, AY, ARot: Double): TRwDrawn;
    function FromCaption(const E: TTyChartElement): TRwDrawn;
    function FindDrawn(T: TJSONObject): TRwDrawn;
    procedure CheckText(T: TJSONObject);
  published
    procedure TestTheBlocksAsUpstream;
    procedure TestAPlainLabelKeepsItsOneRun;
    procedure TestAHoverReinksTheBlock;
    procedure TestTheCaptionsBoxIsItsBlocks;
    procedure TestAnAxisLabelIsMeasuredAsItsBlock;
    procedure TestAnItemsRichCascadesOverItsSeries;
    procedure TestTheCascadeRunsThroughALevel;
    procedure TestAPieAndAFunnelLabelTakeTheirBlock;
    procedure TestTheRootColourReachesAFreeTokenNotTheBlock;
    procedure TestTheBlockIsLaidOutInCssPx;
    procedure TestAnInheritTokenIsTheSeriesColour;
    procedure TestAHoverRestrokesTheDefaultStrokeOnly;
    procedure TestASkinWithNoWeightDrawsTheNormalOne;
    procedure TestAShadowWithoutABlurIsNotDrawn;
  end;

  { device px at a PPI from a measurer that answers CSS px }
  TRwDpiMeasurer = class(TInterfacedObject, ITyTextMeasurer)
  private
    FInner: ITyTextMeasurer;
    FScale: Double;
  public
    constructor Create(const AInner: ITyTextMeasurer; AScale: Double);
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

implementation

{ EVERY CASE IS COMPARED. A case the port cannot draw as upstream does would
  be named here with the reason; none is. }
const
  cDeferred: array[0..0] of string = ('');

  { ECharts 6's theme palette: a colour 'inherit' names is one of these, and
    the port's palette is the skin's }
  cPalette: array[0..8] of string = ('#5070dd', '#b6d634', '#505372',
    '#ff994d', '#0ca8df', '#ffd10a', '#fb628b', '#785db0', '#3fbe95');

{ ==================== the probe ==================== }

function TRwProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer = nil then Exit(inherited NewTextMeasurer(APPI));
  if DpiAware and (APPI <> 96) then
    Result := TRwDpiMeasurer.Create(Measurer, APPI / 96)
  else
    Result := Measurer;
end;

constructor TRwDpiMeasurer.Create(const AInner: ITyTextMeasurer; AScale: Double);
begin
  inherited Create;
  FInner := AInner;
  FScale := AScale;
end;

procedure TRwDpiMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
begin
  FInner.MeasureLine(AText, AFontName, AFontSizeLogical, AWeight, AW, AH);
  AW := AW * FScale;
  AH := AH * FScale;
end;

function TRwDpiMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
begin
  Result := AText;
end;

procedure TRwProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TRwProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

{ ==================== plumbing ==================== }

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-rich-text.json';
end;

function Hex(AData: TJSONData): Double;
var q: QWord; s: string;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(NaN);
  if AData.JSONType = jtNumber then Exit(AData.AsFloat);
  s := AData.AsString;
  if (Length(s) <> 16) or (LastDelimiter('ghijklmnopqrstuvwxyz%.', LowerCase(s)) > 0) then
  begin
    s := StringReplace(s, 'px', '', []);
    if not TryStrToFloat(s, Result, DefaultFormatSettings) then Result := NaN;
    Exit;
  end;
  q := StrToQWord('$' + s);
  Move(q, Result, SizeOf(Result));
end;

function Str(AData: TJSONData): string;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit('');
  Result := AData.AsString;
end;

function Obj(AData: TJSONData): TJSONObject;
begin
  if AData is TJSONObject then Result := TJSONObject(AData) else Result := nil;
end;

function Near(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  Result := Abs(A - B) <= 1e-6 * Max(1.0, Abs(B));
end;

function WeightOf(const S: string): Integer;
begin
  if (S = 'bold') or (S = 'bolder') then Exit(700);
  if (S = '') or (S = 'normal') then Exit(400);
  Result := StrToIntDef(S, 400);
end;

function AlignWord(A: TTyRtAlign): string;
begin
  case A of
    rtaCenter: Result := 'center';
    rtaRight: Result := 'right';
  else
    Result := 'left';
  end;
end;

{ a css colour as the chart reads it; none for '' and none/transparent }
function ColourOf(const S: string; out AC: TTyChartColor): Boolean;
begin
  AC := 0;
  if (S = '') or (S = 'none') or (S = 'transparent') then Exit(False);
  Result := TyTryParseChartColor(S, AC);
end;

function SameRgb(A, B: TTyChartColor): Boolean;
begin
  Result := (A and $00FFFFFF) = (B and $00FFFFFF);
end;

{ a caption's block hung where it is drawn, as the label pass boxes it }
function TyRtDeviceBoxOf(const E: TTyChartElement): TTyRectF;
begin
  Result := TyRtDeviceBox(E.Caption.RtPieces, E.Caption.X, E.Caption.Y,
    E.Caption.RotationRad, E.Caption.RtScale);
end;

function InPalette(const S: string): Boolean;
var k: Integer;
begin
  for k := 0 to High(cPalette) do
    if LowerCase(S) = cPalette[k] then Exit(True);
  Result := False;
end;

procedure TAdvChartRichWiringOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TRwProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FSsr := TZrSsrMeasurer.Create(
    TJSONObject(FRoot).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FRoot).Objects['ratios'].Integers['firstCode']);
  FChart.Measurer := TPtToPxMeasurer.Create(FSsr);
  FBad := 0;
  FCompared := 0;
  FSkipped := 0;
  FTexts := 0;
  FOneRun := 0;
  FReport := '';
end;

procedure TAdvChartRichWiringOracleTest.TearDown;
begin
  FChart.Measurer := nil;
  FSsr := nil;
  FRoot.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartRichWiringOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 9000 then
    FReport := FReport + LineEnding + '  ' + FCase + ': ' + AWhat;
end;

procedure TAdvChartRichWiringOracleTest.Draw(ACase: TJSONObject);
var w, h: Integer;
begin
  w := ACase.Get('W', 600);
  h := ACase.Get('H', 400);
  FBmp.SetSize(w, h);
  FChart.Option := ACase.Objects['option'].AsJSON;
  FChart.SetBounds(0, 0, w, h);
  FChart.Render(FBmp.Canvas, Rect(0, 0, w, h), 96);
  FUsed := nil;
  if FChart.List <> nil then SetLength(FUsed, FChart.List.Count);
end;

{ ==================== the port's side ==================== }

{ THE ONE-RUN CAPTION AS THE PLAIN BLOCK IT STANDS FOR: its words in its
  font, hung by its alignment, in its ink and halo }
function TAdvChartRichWiringOracleTest.PlainDrawn(const AText, AFont: string;
  ASize, AWeight: Integer; AHasInk: Boolean; AInk: TTyChartColor;
  AHasHalo: Boolean; AHalo: TTyChartColor; AHaloW: Double; AH: TTyTextAnchorH;
  AV: TTyTextAnchorV; AX, AY, ARot: Double): TRwDrawn;
var
  st: TTyRtStyle;
  def: TTyRtDefault;
begin
  Result := Default(TRwDrawn);
  Result.Found := True;
  Result.OneRun := True;
  st := TyRtStyleDefault;
  st.FontFamily := AFont;
  st.FontSizePx := TyFontPxOf(ASize);
  if AWeight <= 0 then AWeight := 400;
  st.FontWeight := AWeight;
  if AHasHalo then
  begin
    st.HasLineWidth := True;
    st.LineWidth := AHaloW;
  end;
  def := Default(TTyRtDefault);
  def.HasFill := AHasInk;
  def.Fill := AInk;
  def.HasStroke := AHasHalo;
  def.Stroke := AHalo;
  case AH of
    tahCentre: def.Align := rtaCenter;
    tahRight: def.Align := rtaRight;
  else
    def.Align := rtaLeft;
  end;
  case AV of
    tavMiddle: def.VAlign := rtvMiddle;
    tavBottom: def.VAlign := rtvBottom;
  else
    def.VAlign := rtvTop;
  end;
  Result.D.Pieces := TyRtLayout(AText, st, nil, False, def, 0, 0, FSsr).Pieces;
  Result.D.X := AX;
  Result.D.Y := AY;
  Result.D.RotationRad := ARot;
  Result.D.Scale := 1;
  Result.BlockPx := st.FontSizePx;
  Result.BlockWeight := AWeight;
end;

function TAdvChartRichWiringOracleTest.FromCaption(const E: TTyChartElement): TRwDrawn;
begin
  if Length(E.Caption.RtPieces) = 0 then
    Exit(PlainDrawn(E.Caption.Text, E.Caption.FontName, E.Caption.FontSizeLogical,
      E.Caption.FontWeight, True, E.Caption.Colour, E.Caption.StrokeWidthLogical > 0,
      E.Caption.StrokeColour, E.Caption.StrokeWidthLogical, E.Caption.AnchorH,
      E.Caption.AnchorV, E.Caption.X, E.Caption.Y, E.Caption.RotationRad));
  Result := Default(TRwDrawn);
  Result.Found := True;
  Result.D.Pieces := E.Caption.RtPieces;
  Result.D.X := E.Caption.X;
  Result.D.Y := E.Caption.Y;
  Result.D.RotationRad := E.Caption.RotationRad;
  Result.D.Scale := E.Caption.RtScale;
  Result.BlockPx := TyFontPxOf(E.Caption.FontSizeLogical);
  Result.BlockWeight := E.Caption.FontWeight;
end;

{ THE TEXT UPSTREAM RECORDED, found where the port's site keeps it: the
  paint list's captions (series and marker labels, legend items, a gauge's
  words), an axis' placements and name, a title's lines }
function TAdvChartRichWiringOracleTest.FindDrawn(T: TJSONObject): TRwDrawn;
var
  comp, owner, text: string;
  lst: TTyPaintList;
  k, q, line: Integer;
  e: TTyChartElement;
  gb: TTyGridBuild;
  ax: TTyAxis;
  spec: PTyAxisLayoutSpec;
  pl: TTyAxisLabelPlacement;
  lay: TTyTitleLayout;
  f: TTyTitleFont;
  rt: TTyRtDrawn;
  si: Integer;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
  x, y: Double;
begin
  Result := Default(TRwDrawn);
  comp := T.Strings['component'];
  owner := Str(T.Find('owner'));
  text := T.Strings['text'];
  if (comp = 'seriesLabel') or (comp = 'markerLabel') or (comp = 'legend')
    or (comp = 'chartText') then
  begin
    lst := FChart.List;
    if lst = nil then Exit;
    si := -1;
    if Copy(owner, 1, 6) = 'series' then si := StrToIntDef(Copy(owner, 7, 9), -1);
    for k := 0 to lst.Count - 1 do
    begin
      if (k <= High(FUsed)) and FUsed[k] then Continue;
      e := lst.Element(k);
      if (e.Caption.FontSizeLogical <= 0) or (e.Caption.Text <> text) then Continue;
      if comp = 'seriesLabel' then
      begin
        if (e.Datum.Kind <> ctkSeries) or (e.Datum.SeriesIndex <> si) then Continue;
      end
      else if comp = 'markerLabel' then
      begin
        if e.Datum.SeriesIndex >= 0 then Continue;
      end
      else if comp = 'legend' then
      begin
        if e.Datum.SeriesIndex >= 0 then Continue;
      end;
      if k <= High(FUsed) then FUsed[k] := True;
      Exit(FromCaption(e));
    end;
    Exit;
  end;
  if (comp = 'axisLabel') or (comp = 'axisName') then
  begin
    if (FChart.Build = nil) or (FChart.Build.GridCount = 0) then Exit;
    gb := FChart.Build.Grid(0);
    if owner = 'xAxis0' then ax := gb.XAxis(0)
    else if owner = 'yAxis0' then ax := gb.YAxis(0)
    else Exit;
    spec := gb.SpecFor(ax);
    if spec = nil then Exit;
    if comp = 'axisName' then
    begin
      if not spec^.NamePlacement.Shown or (spec^.NamePlacement.Text <> text) then Exit;
      if Length(spec^.NamePlacement.Rt) > 0 then
      begin
        Result.Found := True;
        Result.D.Pieces := spec^.NamePlacement.Rt;
        Result.D.X := spec^.NamePlacement.X;
        Result.D.Y := spec^.NamePlacement.Y;
        Result.D.RotationRad := spec^.NamePlacement.RotationRad;
        Result.D.Scale := spec^.RtScale;
        Result.BlockPx := TyFontPxOf(spec^.NameFontSizeLogical);
        Result.BlockWeight := spec^.NameFontWeight;
      end
      else
        Result := PlainDrawn(text, spec^.NameFontName, spec^.NameFontSizeLogical,
          spec^.NameFontWeight, False, 0, False, 0, 0, spec^.NamePlacement.AnchorH,
          spec^.NamePlacement.AnchorV, spec^.NamePlacement.X, spec^.NamePlacement.Y,
          spec^.NamePlacement.RotationRad);
      Exit;
    end;
    for q := 0 to High(spec^.Placements) do
    begin
      pl := spec^.Placements[q];
      if not pl.Shown or (pl.Text <> text) then Continue;
      if Length(pl.Rt) > 0 then
      begin
        Result.Found := True;
        Result.D.Pieces := pl.Rt;
        Result.D.X := pl.X;
        Result.D.Y := pl.Y;
        Result.D.RotationRad := spec^.RotationRad;
        Result.D.Scale := spec^.RtScale;
        Result.BlockPx := TyFontPxOf(spec^.FontSizeLogical);
        Result.BlockWeight := spec^.FontWeight;
      end
      else
        Result := PlainDrawn(text, spec^.FontName, spec^.FontSizeLogical,
          spec^.FontWeight, False, 0, False, 0, 0, pl.AnchorH, pl.AnchorV, pl.X,
          pl.Y, spec^.RotationRad);
      Exit;
    end;
    Exit;
  end;
  if (comp = 'title') or (comp = 'subtitle') then
  begin
    if FChart.TitleCount = 0 then Exit;
    if comp = 'title' then line := 0 else line := 1;
    lay := FChart.TitleLayoutOf(0);
    if not lay.Valid then Exit;
    f := FChart.TitleFontUsed(0, line);
    rt := FChart.TitleRt(0, line);
    if Length(rt.Pieces) > 0 then
    begin
      Result.Found := True;
      Result.D := rt;
      Result.BlockPx := TyFontPxOf(f.SizeLogical);
      Result.BlockWeight := f.Weight;
      Exit;
    end;
    case lay.Align of
      ttaCentre: ah := tahCentre;
      ttaRight: ah := tahRight;
    else
      ah := tahLeft;
    end;
    case lay.VAlign of
      ttvMiddle: av := tavMiddle;
      ttvBottom: av := tavBottom;
    else
      av := tavTop;
    end;
    if line = 0 then begin x := lay.TextX; y := lay.TextY; end
    else begin x := lay.SubX; y := lay.SubY; end;
    Result := PlainDrawn(text, f.Name, f.SizeLogical, f.Weight, False, 0, False,
      0, 0, ah, av, x, y, 0);
  end;
end;

{ ==================== the comparison ==================== }

procedure TAdvChartRichWiringOracleTest.CheckText(T: TJSONObject);
type
  TSource = (srcToken, srcBlock, srcDefault);
var
  dr: TRwDrawn;
  pieces: TJSONArray;
  p, style, rich, rs: TJSONObject;
  i, k, n: Integer;
  q: TTyRtPiece;
  where, name, up, w: string;
  attached, geometry: Boolean;
  upPx, upBlockPx, gx, gy: Double;
  c: TTyChartColor;
  corners: TJSONArray;
  sh: TJSONObject;
  bb: TTyXYWH;

  function StyleName(AP: TJSONObject): string;
  var ln, tk: Integer; lines: TJSONArray;
  begin
    Result := '';
    if Str(AP.Find('of')) <> 'token' then Exit;
    if not (T.Find('lines') is TJSONArray) then Exit;
    lines := T.Arrays['lines'];
    ln := AP.Get('line', -1);
    tk := AP.Get('token', -1);
    if (ln < 0) or (ln >= lines.Count) then Exit;
    if (tk < 0) or (tk >= lines.Objects[ln].Arrays['tokens'].Count) then Exit;
    Result := Str(lines.Objects[ln].Arrays['tokens'].Objects[tk].Find('styleName'));
  end;

  function RichOf(const AName: string): TJSONObject;
  begin
    Result := nil;
    if (AName = '') or (rich = nil) then Exit;
    Result := Obj(rich.Find(AName));
  end;

  { a colour upstream drew, against the port's: compared where the case
    authored it, and only required to be there where the skin decides it }
  procedure CheckColour(const AWhat, AUp: string; ASource: TSource;
    APortHas: Boolean; APort: TTyChartColor; APortDefault: Boolean);
  var skin: Boolean;
  begin
    Inc(FCompared);
    if AUp = '' then
    begin
      if APortHas then
        Miss(Format('%s: none upstream, %s here', [AWhat, IntToHex(APort, 8)]));
      Exit;
    end;
    skin := InPalette(AUp) or (ASource = srcDefault)
      or ((ASource = srcBlock) and not attached)
      or ((ASource = srcToken) and not attached and (AUp = Str(style.Find('fill'))));
    if skin then
    begin
      if not APortHas and not APortDefault then
        Miss(Format('%s: %s upstream (the skin''s here), none here', [AWhat, AUp]));
      Exit;
    end;
    if not ColourOf(AUp, c) then Exit;
    if not APortHas then
      Miss(Format('%s: %s upstream, none here', [AWhat, AUp]))
    else if not SameRgb(c, APort) then
      Miss(Format('%s: %s upstream, %s here', [AWhat, AUp, IntToHex(APort, 8)]));
  end;

  function FillSource(AP: TJSONObject; const AKey, ABlockKey: string): TSource;
  begin
    rs := RichOf(StyleName(AP));
    if (rs <> nil) and (rs.Find(AKey) <> nil) then Exit(srcToken);
    if (Str(AP.Find('of')) <> 'token') and (style.Find(ABlockKey) <> nil) then
      Exit(srcBlock);
    if (rs = nil) and (style.Find(ABlockKey) <> nil) then Exit(srcBlock);
    Result := srcDefault;
  end;

begin
  Inc(FTexts);
  where := T.Strings['component'] + ' ' + Str(T.Find('owner')) + ' "'
    + StringReplace(T.Strings['text'], #10, '\n', [rfReplaceAll]) + '"';
  dr := FindDrawn(T);
  Inc(FCompared);
  if not dr.Found then
  begin
    Miss(where + ': not drawn');
    Exit;
  end;
  { WHAT UPSTREAM LAID OUT AS RICH TEXT THE PORT DRAWS AS ITS BLOCK: a rich
    text drawn as the one-run caption would still match where its markup
    measured as its words }
  Inc(FCompared);
  if (T.Find('rich') <> nil) and T.Booleans['rich'] and dr.OneRun then
    Miss(where + ': rich upstream, one run here');
  if dr.OneRun then Inc(FOneRun);
  { a skin that names no weight draws the normal one }
  if dr.BlockWeight <= 0 then dr.BlockWeight := 400;
  style := Obj(T.Find('style'));
  rich := Obj(T.Find('richStyles'));
  attached := (T.Find('attached') <> nil) and T.Booleans['attached'];
  upBlockPx := Hex(style.Find('fontSize'));
  if IsNan(upBlockPx) then upBlockPx := 12;
  geometry := Abs(dr.BlockPx - upBlockPx) < 1e-6;
  pieces := T.Arrays['pieces'];
  Inc(FCompared);
  if pieces.Count <> Length(dr.D.Pieces) then
  begin
    Miss(Format('%s: %d pieces upstream, %d here', [where, pieces.Count,
      Length(dr.D.Pieces)]));
    n := Min(pieces.Count, Length(dr.D.Pieces));
  end
  else
    n := pieces.Count;
  for i := 0 to n - 1 do
  begin
    p := pieces.Objects[i];
    q := dr.D.Pieces[i];
    Inc(FCompared);
    if (p.Strings['kind'] = 'rect') <> (q.Kind = rpkRect) then
    begin
      Miss(Format('%s: piece %d is a %s upstream', [where, i, p.Strings['kind']]));
      Continue;
    end;
    if q.Kind = rpkRect then
    begin
      if geometry then
      begin
        corners := p.Arrays['corners'];
        for k := 0 to 3 do
        begin
          case k of
            0: TyRtPoint(dr.D.X, dr.D.Y, dr.D.RotationRad, dr.D.Scale, q.X, q.Y, gx, gy);
            1: TyRtPoint(dr.D.X, dr.D.Y, dr.D.RotationRad, dr.D.Scale, q.X + q.W, q.Y, gx, gy);
            2: TyRtPoint(dr.D.X, dr.D.Y, dr.D.RotationRad, dr.D.Scale, q.X + q.W, q.Y + q.H, gx, gy);
          else
            TyRtPoint(dr.D.X, dr.D.Y, dr.D.RotationRad, dr.D.Scale, q.X, q.Y + q.H, gx, gy);
          end;
          Inc(FCompared);
          if not (Near(gx, Hex(corners.Objects[k].Find('x')))
            and Near(gy, Hex(corners.Objects[k].Find('y')))) then
          begin
            Miss(Format('%s: rect %d corner %d at %s,%s upstream, %g,%g here', [where,
              i, k, Str(corners.Objects[k].Find('xText')),
              Str(corners.Objects[k].Find('yText')), gx, gy]));
            Break;
          end;
        end;
        Inc(FCompared);
        if not (Near(q.W, Hex(p.Find('width'))) and Near(q.H, Hex(p.Find('height')))) then
          Miss(Format('%s: rect %d %sx%s upstream, %gx%g here', [where, i,
            Str(p.Find('widthText')), Str(p.Find('heightText')), q.W, q.H]));
      end
      else
        Inc(FSkipped);
      if Str(p.Find('of')) = 'box' then
        CheckColour(Format('%s: rect %d fill', [where, i]), Str(p.Find('fill')),
          srcBlock, q.HasFill, q.Fill, False)
      else
        CheckColour(Format('%s: rect %d fill', [where, i]), Str(p.Find('fill')),
          srcToken, q.HasFill, q.Fill, False);
      up := Str(p.Find('stroke'));
      Inc(FCompared);
      if (up <> '') <> q.HasStroke then
        Miss(Format('%s: rect %d stroke %s upstream', [where, i, up]))
      else if q.HasStroke then
      begin
        if not InPalette(up) and ColourOf(up, c) and not SameRgb(c, q.Stroke) then
          Miss(Format('%s: rect %d stroke %s upstream, %s here', [where, i, up,
            IntToHex(q.Stroke, 8)]));
        if not Near(q.LineWidth, Hex(p.Find('lineWidth'))) then
          Miss(Format('%s: rect %d line width %s upstream, %g here', [where, i,
            Str(p.Find('lineWidthText')), q.LineWidth]));
        if p.Booleans['strokeFirst'] <> q.StrokeFirst then
          Miss(Format('%s: rect %d strokeFirst', [where, i]));
      end;
      Inc(FCompared);
      if p.Find('r4') is TJSONArray then
        for k := 0 to 3 do
          if not Near(q.Radius[k], Hex(p.Arrays['r4'].Items[k])) then
          begin
            Miss(Format('%s: rect %d radius %d', [where, i, k]));
            Break;
          end;
      Inc(FCompared);
      if p.Booleans['drawn'] <> q.Drawn then
        Miss(Format('%s: rect %d drawn differs', [where, i]));
      Continue;
    end;
    { a text }
    Inc(FCompared);
    if q.Text <> p.Strings['text'] then
      Miss(Format('%s: text %d "%s" upstream, "%s" here', [where, i,
        p.Strings['text'], q.Text]));
    Inc(FCompared);
    if AlignWord(q.TextAlign) <> Str(p.Find('textAlign')) then
      Miss(Format('%s: text %d align %s upstream, %s here', [where, i,
        Str(p.Find('textAlign')), AlignWord(q.TextAlign)]));
    if geometry then
    begin
      TyRtPoint(dr.D.X, dr.D.Y, dr.D.RotationRad, dr.D.Scale, q.X, q.Y, gx, gy);
      Inc(FCompared);
      if not (Near(gx, Hex(p.Find('gx'))) and Near(gy, Hex(p.Find('gy')))) then
        Miss(Format('%s: text %d "%s" at %s,%s upstream, %g,%g here', [where, i,
          p.Strings['text'], Str(p.Find('gxText')), Str(p.Find('gyText')), gx, gy]));
    end
    else
      Inc(FSkipped);
    { the size: the block's where the skin and upstream agree on it, a
      token's own wherever it is not the block's }
    upPx := p.Get('px', 12.0);
    if geometry or (Abs(upPx - upBlockPx) > 1e-9) then
    begin
      Inc(FCompared);
      if Abs(q.FontSizePx - upPx) > 1e-6 then
        Miss(Format('%s: text %d "%s" %gpx upstream, %gpx here', [where, i,
          p.Strings['text'], upPx, q.FontSizePx]));
    end;
    w := Str(p.Find('fontWeight'));
    if (w = '') and (Pos('bold', Str(p.Find('font'))) > 0) then w := 'bold';
    if (WeightOf(w) <> WeightOf(Str(style.Find('fontWeight'))))
      or (dr.BlockWeight = WeightOf(Str(style.Find('fontWeight')))) then
    begin
      Inc(FCompared);
      if WeightOf(w) <> q.FontWeight then
        Miss(Format('%s: text %d "%s" weight %s upstream, %d here', [where, i,
          p.Strings['text'], w, q.FontWeight]));
    end;
    CheckColour(Format('%s: text %d "%s" fill', [where, i, p.Strings['text']]),
      Str(p.Find('fill')), FillSource(p, 'fill', 'fill'), q.HasFill, q.Fill,
      q.DefaultFill);
    { the stroke: there or not, as wide; its colour where the case wrote it }
    up := Str(p.Find('stroke'));
    Inc(FCompared);
    if (up <> '') <> q.HasStroke then
      Miss(Format('%s: text %d "%s" stroke %s upstream, %s here', [where, i,
        p.Strings['text'], up, BoolToStr(q.HasStroke, IntToHex(q.Stroke, 8), 'none')]))
    else if q.HasStroke then
    begin
      if not Near(q.LineWidth, Hex(p.Find('lineWidth'))) then
        Miss(Format('%s: text %d stroke width %s upstream, %g here', [where, i,
          Str(p.Find('lineWidthText')), q.LineWidth]));
      if FillSource(p, 'stroke', 'stroke') <> srcDefault then
        CheckColour(Format('%s: text %d stroke', [where, i]), up,
          FillSource(p, 'stroke', 'stroke'), True, q.Stroke, False);
    end;
    { THE SHADOW: there or not (zrender sets none without a blur), its blur,
      its offsets and its colour }
    sh := Obj(p.Find('shadow'));
    Inc(FCompared);
    if (sh <> nil) <> q.HasShadow then
      Miss(Format('%s: text %d "%s" shadow %s upstream, %s here', [where, i,
        p.Strings['text'], BoolToStr(sh <> nil, 'set', 'none'),
        BoolToStr(q.HasShadow, 'set', 'none')]))
    else if sh <> nil then
    begin
      if not (Near(q.ShadowBlur, Hex(sh.Find('blur')))
        and Near(q.ShadowOffsetX, Hex(sh.Find('offsetX')))
        and Near(q.ShadowOffsetY, Hex(sh.Find('offsetY')))) then
        Miss(Format('%s: text %d "%s" shadow blur %s offset %s,%s upstream, '
          + '%g offset %g,%g here', [where, i, p.Strings['text'],
          Str(sh.Find('blurText')), Str(sh.Find('offsetXText')),
          Str(sh.Find('offsetYText')), q.ShadowBlur, q.ShadowOffsetX,
          q.ShadowOffsetY]));
      if ColourOf(Str(sh.Find('color')), c) and not SameRgb(c, q.ShadowColor) then
        Miss(Format('%s: text %d "%s" shadow colour %s upstream, %s here', [where,
          i, p.Strings['text'], Str(sh.Find('color')), IntToHex(q.ShadowColor, 8)]));
    end;
  end;
  { THE BOX THE PIECES OCCUPY, turned onto the canvas: upstream's Text
    getBoundingRect, a stroked rect grown by its stroke, a text by a stroke
    its style gave it }
  if geometry and (T.Find('bounds') is TJSONObject) then
  begin
    bb := TyRtBounds(dr.D.Pieces);
    corners := T.Objects['bounds'].Arrays['corners'];
    for k := 0 to 3 do
    begin
      case k of
        0: TyRtPoint(dr.D.X, dr.D.Y, dr.D.RotationRad, dr.D.Scale, bb.X, bb.Y, gx, gy);
        1: TyRtPoint(dr.D.X, dr.D.Y, dr.D.RotationRad, dr.D.Scale, bb.X + bb.W, bb.Y, gx, gy);
        2: TyRtPoint(dr.D.X, dr.D.Y, dr.D.RotationRad, dr.D.Scale, bb.X + bb.W, bb.Y + bb.H, gx, gy);
      else
        TyRtPoint(dr.D.X, dr.D.Y, dr.D.RotationRad, dr.D.Scale, bb.X, bb.Y + bb.H, gx, gy);
      end;
      Inc(FCompared);
      if not (Near(gx, Hex(corners.Objects[k].Find('x')))
        and Near(gy, Hex(corners.Objects[k].Find('y')))) then
      begin
        Miss(Format('%s: bounds corner %d at %s,%s upstream, %g,%g here', [where,
          k, Str(corners.Objects[k].Find('xText')),
          Str(corners.Objects[k].Find('yText')), gx, gy]));
        Break;
      end;
    end;
  end
  else
    Inc(FSkipped);
end;

procedure TAdvChartRichWiringOracleTest.TestTheBlocksAsUpstream;
var
  cases, texts: TJSONArray;
  cs: TJSONObject;
  c, t, k: Integer;
  skip: Boolean;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    FCase := cs.Strings['name'];
    skip := False;
    for k := 0 to High(cDeferred) do
      if FCase = cDeferred[k] then skip := True;
    if skip then Continue;
    try
      Draw(cs);
      texts := cs.Arrays['texts'];
      for t := 0 to texts.Count - 1 do
        CheckText(texts.Objects[t]);
    except
      on E: Exception do Miss(E.ClassName + ': ' + E.Message);
    end;
  end;
  AssertTrue(Format('%d of %d differ from upstream (%d geometry checks left to '
    + 'the skin):%s', [FBad, FCompared, FSkipped, FReport]), FBad = 0);
  AssertTrue(Format('only %d texts', [FTexts]), FTexts >= 200);
  { the two texts with nothing a block is needed for -- the gauge's plain
    title and the title whose box upstream disables -- and no others }
  AssertEquals('texts drawn as one run', 2, FOneRun);
  AssertTrue(Format('only %d compared', [FCompared]), FCompared >= 3000);
end;

{ A LABEL WITH NOTHING THAT NEEDS A BLOCK KEEPS THE ONE-RUN CAPTION it always
  had -- no pieces -- and one with a background takes the block. }
procedure TAdvChartRichWiringOracleTest.TestAPlainLabelKeepsItsOneRun;
var
  lst: TTyPaintList;
  k, plain, blocks: Integer;
begin
  FChart.Option := '{"animation":false,"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","data":[1,2],'
    + '"label":{"show":true,"position":"top","fontSize":14}},'
    + '{"type":"bar","data":[3,4],"label":{"show":true,"backgroundColor":"#eee"}}]}';
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  lst := FChart.List;
  plain := 0;
  blocks := 0;
  for k := 0 to lst.Count - 1 do
  begin
    if lst.Element(k).Caption.FontSizeLogical <= 0 then Continue;
    if lst.Element(k).Datum.SeriesIndex = 0 then
    begin
      Inc(plain);
      AssertEquals('a plain label has no block', 0,
        Length(lst.Element(k).Caption.RtPieces));
    end
    else if lst.Element(k).Datum.SeriesIndex = 1 then
    begin
      Inc(blocks);
      AssertTrue('a label with a background is its block',
        Length(lst.Element(k).Caption.RtPieces) > 0);
    end;
  end;
  AssertEquals('both plain labels', 2, plain);
  AssertEquals('both boxed labels', 2, blocks);
end;

{ UNDER A HOVER THE BLOCK TAKES THE HOVER'S INK: the pieces whose fill came
  from the host's default are re-inked with the emphasis colour, a token's
  own colour is kept. }
procedure TAdvChartRichWiringOracleTest.TestAHoverReinksTheBlock;
var
  lst: TTyPaintList;
  k, j: Integer;
  cap: TTyElementCaption;
  own, dflt: Boolean;
begin
  FChart.Option := '{"animation":false,"xAxis":{"type":"category","data":["a"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","data":[1],'
    + '"emphasis":{"label":{"color":"#00ff00"}},'
    + '"label":{"show":true,"position":"top","formatter":"{a|x}{b|y}",'
    + '"rich":{"a":{"color":"#ff0000"},"b":{}}}}]}';
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  lst := FChart.List;
  for k := 0 to lst.Count - 1 do
  begin
    cap := lst.Element(k).Caption;
    if (cap.FontSizeLogical <= 0) or (Length(cap.RtPieces) = 0) then Continue;
    AssertTrue('the hover ink was stamped', cap.HasEmph);
    TyCaptionToEmphasis(cap);
    own := False;
    dflt := False;
    for j := 0 to High(cap.RtPieces) do
    begin
      if cap.RtPieces[j].Kind <> rpkText then Continue;
      if cap.RtPieces[j].Text = 'x' then
      begin
        own := True;
        AssertEquals('a token''s own colour stays', $FF0000,
          Integer(cap.RtPieces[j].Fill and $FFFFFF));
      end
      else if cap.RtPieces[j].Text = 'y' then
      begin
        dflt := True;
        AssertEquals('the default ink is the hover''s', $00FF00,
          Integer(cap.RtPieces[j].Fill and $FFFFFF));
      end;
    end;
    AssertTrue('both tokens', own and dflt);
    Exit;
  end;
  Fail('no rich label was drawn');
end;

{ THE POINTER AND THE LABEL LAYOUT SEE WHAT IS DRAWN: a block caption's
  shape is the box of its pieces (padding and border included), turned as it
  is drawn -- not the box of its words. }
procedure TAdvChartRichWiringOracleTest.TestTheCaptionsBoxIsItsBlocks;
var
  lst: TTyPaintList;
  k: Integer;
  e: TTyChartElement;
  b, want: TTyRectF;
  seen: Boolean;
begin
  FChart.Option := '{"animation":false,"xAxis":{"type":"category","data":["a"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","data":[1],'
    + '"label":{"show":true,"position":"top","rotate":30,"padding":[6,20],'
    + '"backgroundColor":"#eee","borderColor":"#333","borderWidth":2}}]}';
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  lst := FChart.List;
  seen := False;
  for k := 0 to lst.Count - 1 do
  begin
    e := lst.Element(k);
    if (e.Caption.FontSizeLogical <= 0) or (Length(e.Caption.RtPieces) = 0) then
      Continue;
    seen := True;
    want := TyRtDeviceBoxOf(e);
    b := e.Shape.Bounds;
    AssertEquals('left', want.Left, b.Left, 1e-9);
    AssertEquals('top', want.Top, b.Top, 1e-9);
    AssertEquals('right', want.Right, b.Right, 1e-9);
    AssertEquals('bottom', want.Bottom, b.Bottom, 1e-9);
    { the padding is in it: wider than the words by both sides' 20 }
    AssertTrue('the padded box, turned', b.Right - b.Left > 40);
  end;
  AssertTrue('a block caption was drawn', seen);
end;

{ AN AXIS LABEL IS MEASURED AS ITS BLOCK: with containLabel the grid makes
  room for the labels as drawn, so a padding of 40 each side on the y axis'
  labels takes 80 more from the plot's left than the same labels without. }
procedure TAdvChartRichWiringOracleTest.TestAnAxisLabelIsMeasuredAsItsBlock;
var
  plainLeft, boxLeft: Double;

  function PlotLeft(const ALabel: string): Double;
  begin
    FChart.Option := '{"animation":false,"grid":{"containLabel":true,"left":10},'
      + '"xAxis":{"type":"category","data":["a","b"]},'
      + '"yAxis":{"type":"value","axisLabel":{' + ALabel + '}},'
      + '"series":[{"type":"bar","data":[100,2000]}]}';
    FChart.SetBounds(0, 0, 600, 400);
    FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
    Result := FChart.Build.Grid(0).PlotRect.Left;
  end;

begin
  plainLeft := PlotLeft('"show":true');
  boxLeft := PlotLeft('"padding":[0,40],"backgroundColor":"#eee"');
  AssertEquals('the padding is room the grid gives', 80.0, boxLeft - plainLeft, 1e-6);
end;

{ the first block caption of series ASeries }
function FirstBlock(AList: TTyPaintList; ASeries: Integer;
  out ACaption: TTyElementCaption): Boolean;
var k: Integer;
begin
  for k := 0 to AList.Count - 1 do
  begin
    ACaption := AList.Element(k).Caption;
    if (ACaption.FontSizeLogical > 0) and (Length(ACaption.RtPieces) > 0)
      and (AList.Element(k).Datum.SeriesIndex = ASeries) then Exit(True);
  end;
  Result := False;
end;

{ AN ITEM'S RICH STYLE CASCADES OVER ITS SERIES' -- upstream's model chain:
  the series says the token is red and 20px, the item adds a background,
  and the item's token is all three. }
procedure TAdvChartRichWiringOracleTest.TestAnItemsRichCascadesOverItsSeries;
var
  cap: TTyElementCaption;
  j: Integer;
  hasRect, hasText: Boolean;
begin
  FChart.Option := '{"animation":false,"xAxis":{"type":"category","data":["a"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar",'
    + '"data":[{"value":1,"label":{"rich":{"a":{"backgroundColor":"#00ff00"}}}}],'
    + '"label":{"show":true,"position":"top","formatter":"{a|x}",'
    + '"rich":{"a":{"color":"#ff0000","fontSize":20}}}}]}';
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  AssertTrue('the label is a block', FirstBlock(FChart.List, 0, cap));
  hasRect := False;
  hasText := False;
  for j := 0 to High(cap.RtPieces) do
    if cap.RtPieces[j].Kind = rpkRect then
    begin
      hasRect := True;
      AssertEquals('the item''s background', $00FF00,
        Integer(cap.RtPieces[j].Fill and $FFFFFF));
    end
    else
    begin
      hasText := True;
      AssertEquals('the series'' colour', $FF0000,
        Integer(cap.RtPieces[j].Fill and $FFFFFF));
      AssertEquals('the series'' size', 20.0, cap.RtPieces[j].FontSizePx, 1e-9);
    end;
  AssertTrue('a rect and a text', hasRect and hasText);
end;

{ AND THROUGH A LEVEL: a sunburst node's label reads its level's over its
  series', so the chain is three long -- the item's background over the
  level's size over the series' colour. }
procedure TAdvChartRichWiringOracleTest.TestTheCascadeRunsThroughALevel;
var
  lst: TTyPaintList;
  cap: TTyElementCaption;
  k, j: Integer;
  seen: Boolean;
begin
  FChart.Option := '{"animation":false,"series":[{"type":"sunburst",'
    + '"label":{"formatter":"{a|x}","rich":{"a":{"color":"#ff0000"}}},'
    + '"levels":[{},{"label":{"rich":{"a":{"fontSize":20}}}}],'
    + '"data":[{"name":"n","value":1,'
    + '"label":{"rich":{"a":{"backgroundColor":"#00ff00"}}}}]}]}';
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  lst := FChart.List;
  seen := False;
  for k := 0 to lst.Count - 1 do
  begin
    cap := lst.Element(k).Caption;
    if (cap.FontSizeLogical <= 0) or (Length(cap.RtPieces) = 0) then Continue;
    seen := True;
    for j := 0 to High(cap.RtPieces) do
      if cap.RtPieces[j].Kind = rpkRect then
        AssertEquals('the item''s background', $00FF00,
          Integer(cap.RtPieces[j].Fill and $FFFFFF))
      else
      begin
        AssertEquals('the series'' colour', $FF0000,
          Integer(cap.RtPieces[j].Fill and $FFFFFF));
        AssertEquals('the level''s size', 20.0, cap.RtPieces[j].FontSizePx, 1e-9);
      end;
  end;
  AssertTrue('the node''s label is a block', seen);
end;

{ THE SERIES THAT PLACE THEIR OWN LABELS -- a pie, a funnel -- draw them
  as their blocks too: 'inherit' is the slice's colour, and the box is the
  pieces'. The fixture has no pie or funnel, so this holds the wiring, not
  the geometry. }
procedure TAdvChartRichWiringOracleTest.TestAPieAndAFunnelLabelTakeTheirBlock;
const
  cTypes: array[0..1] of string = ('pie', 'funnel');
var
  typ: string;
  lst: TTyPaintList;
  e: TTyChartElement;
  k, j: Integer;
  blocks: Integer;
  want: TTyRectF;
begin
  for typ in cTypes do
  begin
    FChart.Option := '{"animation":false,"series":[{"type":"' + typ + '",'
      + '"data":[{"name":"a","value":1},{"name":"b","value":2}],'
      + '"label":{"show":true,"formatter":"{a|{b}}",'
      + '"rich":{"a":{"backgroundColor":"inherit","color":"#ffffff","padding":3}}}}]}';
    FChart.SetBounds(0, 0, 600, 400);
    FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
    lst := FChart.List;
    blocks := 0;
    for k := 0 to lst.Count - 1 do
    begin
      e := lst.Element(k);
      if (e.Caption.FontSizeLogical <= 0) or (Length(e.Caption.RtPieces) = 0) then
        Continue;
      Inc(blocks);
      AssertEquals(typ + ': a rect and a text', 2, Length(e.Caption.RtPieces));
      for j := 0 to 1 do
        if e.Caption.RtPieces[j].Kind = rpkText then
          AssertEquals(typ + ': the token''s colour', $FFFFFF,
            Integer(e.Caption.RtPieces[j].Fill and $FFFFFF))
        else
          AssertTrue(typ + ': the background is the slice''s',
            e.Caption.RtPieces[j].HasFill and ((e.Caption.RtPieces[j].Fill and $FFFFFF) <> $FFFFFF));
      want := TyRtDeviceBoxOf(e);
      AssertEquals(typ + ': the box is the block', want.Right - want.Left,
        e.Shape.Bounds.Right - e.Shape.Bounds.Left, 1e-9);
    end;
    AssertEquals(typ + ': both labels are blocks', 2, blocks);
  end;
end;

{ THE ROOT textStyle.color REACHES A FREE TEXT'S RICH TOKEN AND NOT ITS
  BLOCK: an axis label's token without a colour is the root's, its plain
  part keeps the axis' own ink (the skin's, at paint) }
procedure TAdvChartRichWiringOracleTest.TestTheRootColourReachesAFreeTokenNotTheBlock;
var
  spec: PTyAxisLayoutSpec;
  gb: TTyGridBuild;
  j: Integer;
  tok, plain: Boolean;
  pc: TTyRtPiece;
begin
  FChart.Option := '{"animation":false,"textStyle":{"color":"#123456"},'
    + '"xAxis":{"type":"category","data":["a"],"axisLabel":{"formatter":"{a|{value}}!",'
    + '"rich":{"a":{}}}},"yAxis":{"type":"value"},'
    + '"series":[{"type":"bar","data":[1]}]}';
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  gb := FChart.Build.Grid(0);
  spec := gb.SpecFor(gb.XAxis(0));
  tok := False;
  plain := False;
  for j := 0 to High(spec^.Placements[0].Rt) do
  begin
    pc := spec^.Placements[0].Rt[j];
    if pc.Kind <> rpkText then Continue;
    if pc.Text = 'a' then
    begin
      tok := True;
      AssertTrue('the token has a colour', pc.HasFill);
      AssertEquals('the root''s', $123456, Integer(pc.Fill and $FFFFFF));
    end
    else if pc.Text = '!' then
    begin
      plain := True;
      AssertFalse('the plain part is the skin''s, at paint', pc.HasFill);
      AssertTrue('... from the default', pc.DefaultFill);
    end;
  end;
  AssertTrue('both parts', tok and plain);
end;

{ THE PIECES ARE CSS PX WHATEVER THE PPI: at 144 the same block lays out to
  the same pieces, and RtScale says how many device px each is. }
procedure TAdvChartRichWiringOracleTest.TestTheBlockIsLaidOutInCssPx;
const
  cOpt = '{"animation":false,"xAxis":{"type":"category","data":["a"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","data":[1],'
    + '"label":{"show":true,"position":"top","formatter":"{a|Mon}\n{b|120}",'
    + '"padding":4,"backgroundColor":"#eee","rich":{"a":{"fontSize":14},'
    + '"b":{"padding":[2,6],"backgroundColor":"#ddd"}}}}]}';
var
  at96, at144: TTyElementCaption;
  j: Integer;
begin
  FChart.DpiAware := True;
  FChart.Option := cOpt;
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  AssertTrue('at 96', FirstBlock(FChart.List, 0, at96));
  FBmp.SetSize(900, 600);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 900, 600), 144);
  AssertTrue('at 144', FirstBlock(FChart.List, 0, at144));
  AssertEquals('device px per piece px', 1.5, at144.RtScale, 1e-9);
  AssertEquals('the same pieces', Length(at96.RtPieces), Length(at144.RtPieces));
  for j := 0 to High(at96.RtPieces) do
  begin
    AssertEquals('x', at96.RtPieces[j].X, at144.RtPieces[j].X, 1e-6);
    AssertEquals('y', at96.RtPieces[j].Y, at144.RtPieces[j].Y, 1e-6);
    AssertEquals('w', at96.RtPieces[j].W, at144.RtPieces[j].W, 1e-6);
    AssertEquals('h', at96.RtPieces[j].H, at144.RtPieces[j].H, 1e-6);
  end;
end;

{ A TOKEN'S color 'inherit' IS THE COLOUR THE CONTROL PAINTS ITS BAR IN
  (labelStyle.ts:554-563, inheritColor): the series' palette colour, which
  is the skin's and not upstream's, so the fixture cannot say it. Inside the
  bar the default ink is the band's (white on this fill), so a token that
  lost its 'inherit' would take that instead. }
procedure TAdvChartRichWiringOracleTest.TestAnInheritTokenIsTheSeriesColour;
var
  lst: TTyPaintList;
  k, j: Integer;
  bar: TTyChartColor;
  hasBar, own, dflt: Boolean;
  cap: TTyElementCaption;
begin
  FChart.Option := '{"animation":false,"xAxis":{"type":"category","data":["a"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","data":[1],'
    + '"label":{"show":true,"position":"inside","formatter":"{a|x}{b|y}",'
    + '"rich":{"a":{"color":"inherit"},"b":{}}}}]}';
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  lst := FChart.List;
  hasBar := False;
  bar := 0;
  for k := 0 to lst.Count - 1 do
    if (lst.Element(k).Datum.SeriesIndex = 0) and (lst.Element(k).Caption.FontSizeLogical <= 0)
      and lst.Element(k).Style.HasFill then
    begin
      hasBar := True;
      bar := lst.Element(k).Style.FillColor;
      Break;
    end;
  AssertTrue('the bar is drawn', hasBar);
  AssertTrue('the label is a block', FirstBlock(lst, 0, cap));
  own := False;
  dflt := False;
  for j := 0 to High(cap.RtPieces) do
  begin
    if cap.RtPieces[j].Kind <> rpkText then Continue;
    if cap.RtPieces[j].Text = 'x' then
    begin
      own := True;
      AssertTrue('''inherit'' is a colour of the token''s own', cap.RtPieces[j].HasFill
        and not cap.RtPieces[j].DefaultFill);
      AssertEquals('''inherit'' is the bar''s colour', Integer(bar and $FFFFFF),
        Integer(cap.RtPieces[j].Fill and $FFFFFF));
    end
    else if cap.RtPieces[j].Text = 'y' then
    begin
      dflt := True;
      AssertTrue('the plain token takes the default ink', cap.RtPieces[j].DefaultFill);
      AssertTrue('... which is not the bar''s colour here',
        (cap.RtPieces[j].Fill and $FFFFFF) <> (bar and $FFFFFF));
    end;
  end;
  AssertTrue('both tokens', own and dflt);
end;

{ UNDER A HOVER THE DEFAULT STROKE IS THE HOVER'S: emphasis.label's
  textBorderColor and textBorderWidth reach a token whose stroke was the
  host's auto one -- zrender's _placeToken takes the merged style's `stroke`
  and `lineWidth` when the token has none (Text.ts:833-872) -- and a token
  with its own textBorderColor and width keeps both. }
procedure TAdvChartRichWiringOracleTest.TestAHoverRestrokesTheDefaultStrokeOnly;
var
  cap: TTyElementCaption;
  j: Integer;
  own, dflt: Boolean;
begin
  FChart.Option := '{"animation":false,"xAxis":{"type":"category","data":["a"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","data":[1],'
    + '"emphasis":{"label":{"textBorderColor":"#00ff00","textBorderWidth":5}},'
    + '"label":{"show":true,"position":"top","formatter":"{a|x}{b|y}",'
    + '"rich":{"a":{"textBorderColor":"#ff0000","textBorderWidth":3},"b":{}}}}]}';
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  AssertTrue('the label is a block', FirstBlock(FChart.List, 0, cap));
  { the normal state: b's stroke is the host's default, a's its own }
  for j := 0 to High(cap.RtPieces) do
    if (cap.RtPieces[j].Kind = rpkText) and (cap.RtPieces[j].Text = 'y') then
    begin
      AssertTrue('b is stroked by default', cap.RtPieces[j].HasStroke
        and cap.RtPieces[j].DefaultStroke);
      AssertEquals('... two wide', 2.0, cap.RtPieces[j].LineWidth, 1e-9);
    end;
  AssertTrue('the hover ink was stamped', cap.HasEmph);
  TyCaptionToEmphasis(cap);
  own := False;
  dflt := False;
  for j := 0 to High(cap.RtPieces) do
  begin
    if cap.RtPieces[j].Kind <> rpkText then Continue;
    if cap.RtPieces[j].Text = 'x' then
    begin
      own := True;
      AssertTrue('a keeps a stroke', cap.RtPieces[j].HasStroke);
      AssertEquals('a keeps its own colour', $FF0000,
        Integer(cap.RtPieces[j].Stroke and $FFFFFF));
      AssertEquals('a keeps its own width', 3.0, cap.RtPieces[j].LineWidth, 1e-9);
    end
    else if cap.RtPieces[j].Text = 'y' then
    begin
      dflt := True;
      AssertTrue('b is stroked under the hover', cap.RtPieces[j].HasStroke);
      AssertEquals('b takes the hover''s colour', $00FF00,
        Integer(cap.RtPieces[j].Stroke and $FFFFFF));
      AssertEquals('b takes the hover''s width', 5.0, cap.RtPieces[j].LineWidth, 1e-9);
    end;
  end;
  AssertTrue('both tokens', own and dflt);
end;

{ A SKIN THAT NAMES NO FONT WEIGHT MEANS THE NORMAL ONE: the label's skin
  rule has no font-weight, so the site hands the block a weight of 0, and
  the block and a token that inherits it are 400 -- not 0. }
procedure TAdvChartRichWiringOracleTest.TestASkinWithNoWeightDrawsTheNormalOne;
var
  cap: TTyElementCaption;
  j, n: Integer;
begin
  FChart.Option := '{"animation":false,"xAxis":{"type":"category","data":["a"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","data":[1],'
    + '"label":{"show":true,"position":"top","formatter":"{a|x}y",'
    + '"rich":{"a":{"color":"#ff0000"}}}}]}';
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
  AssertTrue('the label is a block', FirstBlock(FChart.List, 0, cap));
  AssertEquals('the skin names no weight for a label', 0, cap.FontWeight);
  n := 0;
  for j := 0 to High(cap.RtPieces) do
    if cap.RtPieces[j].Kind = rpkText then
    begin
      Inc(n);
      AssertEquals('"' + cap.RtPieces[j].Text + '" is the normal weight', 400,
        cap.RtPieces[j].FontWeight);
    end;
  AssertEquals('the token and the plain part', 2, n);
end;

{ A TEXT SHADOW WITHOUT A BLUR IS NO SHADOW: zrender sets the TSpan's
  shadow only when textShadowBlur > 0 (Text.ts:611, 850-861), so offsets and
  a colour alone draw nothing -- while the port, which has no glyph blur,
  draws a blurred one as its offset copy. Counted on the canvas: magenta
  pixels, which nothing else in the chart is. }
procedure TAdvChartRichWiringOracleTest.TestAShadowWithoutABlurIsNotDrawn;

  function Magenta(const ABlur: string): Integer;
  var
    x, y: Integer;
    row: PBGRAPixel;
  begin
    FBmp.SetSize(600, 400);
    FBmp.Fill(BGRAWhite);
    FChart.Option := '{"animation":false,"xAxis":{"type":"category","data":["a"]},'
      + '"yAxis":{"type":"value"},"series":[{"type":"bar","data":[1],'
      + '"label":{"show":true,"position":"top","fontSize":24,"formatter":"MMMM",'
      + '"textShadowColor":"#ff00ff","textShadowOffsetX":6,"textShadowOffsetY":6'
      + ABlur + '}}]}';
    FChart.SetBounds(0, 0, 600, 400);
    FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
    Result := 0;
    for y := 0 to FBmp.Height - 1 do
    begin
      row := FBmp.ScanLine[y];
      for x := 0 to FBmp.Width - 1 do
      begin
        if (row^.red > 180) and (row^.blue > 180) and (row^.green < 90) then
          Inc(Result);
        Inc(row);
      end;
    end;
  end;

begin
  AssertTrue('a blurred shadow is drawn (the count sees it)', Magenta(',"textShadowBlur":2') > 20);
  AssertEquals('no blur, no shadow', 0, Magenta(''));
end;

initialization
  RegisterTest(TAdvChartRichWiringOracleTest);
end.
