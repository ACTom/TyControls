unit test.advchart.fontstyle;
{$mode objfpc}{$H+}
{ fontStyle: 'italic' -- held to upstream [R5-A].

  tools/advchart-oracle/font-style.js runs ECharts 6.1 (SSR, 600 x 400) over
  one chart per site with `fontStyle: 'italic'` (or 'oblique') written there
  -- series labels of every kind, rich tokens, titles, legends, axis labels
  and names of every coordinate system, calendar labels, the timeline, graphic
  texts, visualMap texts, a gauge's texts, markers, a map, a matrix, an
  axisPointer's label, the loading text, the root textStyle -- and records
  every text it draws with whether its font is slanted.

  THE PICTURE IS HELD TO IT: the painter logs every text it is asked to draw
  with the weight it was asked for (TyPainterTextLogForTest); a text upstream
  draws italic must be drawn here with the italic flag above its weight
  (TyFontItalic) and an upright one without, string for string. That the flag
  then draws a slanted face and is measured in it is held by the two tests
  after. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.Types, tyControls.Painter,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Measure, tyControls.AdvanceChart.Geo,
     tyControls.AdvanceChart;
type
  { the painter's measurer, every line it measures logged as the painter's
    draws are: text, weight }
  TFsMeasurer = class(TInterfacedObject, ITyTextMeasurer)
  private
    FInner: ITyTextMeasurer;
  public
    Log: TStrings;
    constructor Create(APPI: Integer);
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

  TFsProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    MeasureLog: TStrings;
    procedure Hover(AX, AY: Integer);
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure RenderWindow(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartFontStyleOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TFsProbe;
    FRoot: TJSONData;
    FBad, FCompared: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure Show(ACase: TJSONObject; ALog: TStrings; AMeasured: TStrings = nil);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryTextInUpstreamsStyle;
    procedure TestTheItalicFlagDrawsASlantedFace;
    procedure TestALabelIsMeasuredInItsItalicFace;
    procedure TestAFontStyleIsAStringOnly;
    procedure TestAnHtmlTooltipTakesTheStyle;
    procedure TestAToolboxTitleTakesTextFontStyle;
  end;

implementation

uses tyControls.AdvanceChart.Option;

const
  cW = 600;
  cH = 400;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-font-style.json';
end;

function LoadJson(const APath: string): TJSONData;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(APath);
    Result := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
end;

constructor TFsMeasurer.Create(APPI: Integer);
begin
  inherited Create;
  FInner := TTyPainterTextMeasurer.Create(APPI);
end;

procedure TFsMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
begin
  if Log <> nil then Log.Add(AText + #9 + IntToStr(AWeight));
  FInner.MeasureLine(AText, AFontName, AFontSizeLogical, AWeight, AW, AH);
end;

function TFsMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
begin
  Result := FInner.WrapToWidth(AText, AFontName, AFontSizeLogical, AWeight, AMaxWidth);
end;

function TFsProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
var m: TFsMeasurer;
begin
  m := TFsMeasurer.Create(APPI);
  m.Log := MeasureLog;
  Result := m;
end;

procedure TFsProbe.RenderWindow(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderCached(ACanvas, ARect, APPI);
end;

procedure TFsProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TFsProbe.Hover(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

function TFsProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TAdvChartFontStyleOracleTest.SetUp;
var maps: TJSONObject; i: Integer;
begin
  inherited SetUp;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  FRoot := LoadJson(FixturePath);
  maps := TJSONObject(FRoot).Objects['maps'];
  for i := 0 to maps.Count - 1 do
    AssertTrue('the map registers', TyChartRegisterMap(maps.Names[i], maps.Items[i].AsString));
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartFontStyleOracleTest.TearDown;
begin
  TyPainterTextLogForTest(nil);
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FRoot);
  inherited TearDown;
end;

procedure TAdvChartFontStyleOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 60 then FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartFontStyleOracleTest.Show(ACase: TJSONObject; ALog: TStrings;
  AMeasured: TStrings);
var bmp: TBitmap;
begin
  FName := ACase.Strings['id'];
  FreeAndNil(FChart);
  FChart := TFsProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.AnimationMode := camOff;
  FChart.MeasureLog := AMeasured;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Option := ACase.Objects['option'].AsJSON;
  if ACase.Find('loading') <> nil then
    FChart.ShowLoading('default', ACase.Objects['loading'].AsJSON);
  if ACase.Find('showTip') <> nil then
  begin
    { laid out first: the action asks the layout where the item is }
    bmp := TBitmap.Create;
    try
      bmp.SetSize(cW, cH);
      FChart.RenderWindow(bmp.Canvas, Rect(0, 0, cW, cH), 96);
    finally
      bmp.Free;
    end;
    AssertTrue(FName + ': showTip', FChart.DispatchAction(ACase.Objects['showTip'].AsJSON));
  end;
  bmp := TBitmap.Create;
  try
    bmp.SetSize(cW, cH);
    TyPainterTextLogForTest(ALog);
    try
      FChart.RenderWindow(bmp.Canvas, Rect(0, 0, cW, cH), 96);
    finally
      TyPainterTextLogForTest(nil);
    end;
  finally
    bmp.Free;
  end;
end;

{ A TEXT'S STYLE, AS A SET: the same words can be drawn upright and italic in
  one chart (a '5' on the axis and a '5' on a bar), so each string carries
  the set of styles it is drawn in -- bit 0 upright, bit 1 italic -- and the
  two sets must be equal. A string drawn here and not upstream (or the other
  way) is not compared: which words a chart shows is other batches' business. }
procedure TAdvChartFontStyleOracleTest.TestEveryTextInUpstreamsStyle;
var
  cases, texts: TJSONArray;
  cs, t: TJSONObject;
  c, k, i, w: Integer;
  up, here, meas: TStringList;
  log, mlog: TStringList;
  parts: TStringArray;
  bit: Integer;
  italics, measured: Integer;

  procedure Put(AList: TStringList; const AText: string; ABit: Integer);
  var j: Integer;
  begin
    j := AList.IndexOf(AText);
    if j < 0 then AList.AddObject(AText, TObject(PtrInt(ABit)))
    else AList.Objects[j] := TObject(PtrInt(PtrInt(AList.Objects[j]) or ABit));
  end;

  { the weights a string was drawn in, for the report }
  function Weights(const AText: string): string;
  var j: Integer;
  begin
    Result := ' (drawn';
    for j := 0 to log.Count - 1 do
      if Copy(log[j], 1, Pos(#9, log[j]) - 1) = AText then
        Result := Result + ' ' + StringReplace(Copy(log[j], Pos(#9, log[j]) + 1, MaxInt),
          #9, '/', []);
    Result := Result + ')';
  end;

  function Styles(ABits: PtrInt): string;
  begin
    Result := '';
    if (ABits and 1) <> 0 then Result := 'upright';
    if (ABits and 2) <> 0 then
    begin
      if Result <> '' then Result := Result + '+';
      Result := Result + 'italic';
    end;
  end;

begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  italics := 0;
  measured := 0;
  log := nil;
  up := TStringList.Create;
  here := TStringList.Create;
  meas := TStringList.Create;
  log := TStringList.Create;
  mlog := TStringList.Create;
  try
    for c := 0 to cases.Count - 1 do
    begin
      cs := cases.Objects[c];
      up.Clear;
      here.Clear;
      meas.Clear;
      log.Clear;
      mlog.Clear;
      texts := cs.Arrays['texts'];
      for k := 0 to texts.Count - 1 do
      begin
        t := texts.Objects[k];
        if t.Booleans['italic'] then bit := 2 else bit := 1;
        Put(up, t.Strings['text'], bit);
      end;
      Show(cs, log, mlog);
      for i := 0 to mlog.Count - 1 do
      begin
        parts := mlog[i].Split([#9]);
        if (StrToIntDef(parts[1], 0) and TyFontItalic) <> 0 then bit := 2 else bit := 1;
        Put(meas, parts[0], bit);
      end;
      for i := 0 to log.Count - 1 do
      begin
        parts := log[i].Split([#9]);
        { a text drawn in an ink of no alpha shows nothing: not a text }
        if StrToIntDef(parts[2], 0) = 0 then Continue;
        w := StrToIntDef(parts[1], 0);
        if (w and TyFontItalic) <> 0 then bit := 2 else bit := 1;
        Put(here, parts[0], bit);
      end;
      for k := 0 to up.Count - 1 do
      begin
        i := here.IndexOf(up[k]);
        if i < 0 then
        begin
          { an italic text not drawn at all is a miss: it is what this holds }
          if (PtrInt(up.Objects[k]) and 2) <> 0 then
            Miss(Format('"%s" (%s upstream) is not drawn', [up[k], Styles(PtrInt(up.Objects[k]))]));
          Continue;
        end;
        Inc(FCompared);
        if (PtrInt(up.Objects[k]) and 2) <> 0 then Inc(italics);
        if PtrInt(up.Objects[k]) <> PtrInt(here.Objects[i]) then
          Miss(Format('"%s": %s upstream, %s here%s', [up[k],
            Styles(PtrInt(up.Objects[k])), Styles(PtrInt(here.Objects[i])), Weights(up[k])]));
        { WHAT THE LAYOUT MEASURED is a face it draws: a text measured only
          in a style it is never drawn in sized its box for another font.
          (Measured in both is legitimate: a category interval measures every
          label in the label model's font, a state's label drawn otherwise --
          the timeline's current one -- or a hidden axis' labels.) }
        i := meas.IndexOf(up[k]);
        if i < 0 then Continue;
        Inc(measured);
        if (PtrInt(meas.Objects[i]) and PtrInt(up.Objects[k])) = 0 then
          Miss(Format('"%s": measured %s, %s upstream', [up[k],
            Styles(PtrInt(meas.Objects[i])), Styles(PtrInt(up.Objects[k]))]));
      end;
    end;
  finally
    mlog.Free;
    log.Free;
    meas.Free;
    here.Free;
    up.Free;
  end;
  AssertTrue(Format('%d of %d differ from upstream:%s', [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('only %d measured', [measured]), measured >= 100);
  AssertTrue(Format('only %d compared', [FCompared]), FCompared >= 120);
  AssertTrue(Format('only %d italic compared', [italics]), italics >= 60);
end;

{ THE FLAG DRAWS THE SLANTED FACE: tall strokes drawn italic lean -- their
  ink in the top rows sits to the right of their ink in the bottom rows --
  and drawn upright they do not; on the BGRA path and on the turned one. }
procedure TAdvChartFontStyleOracleTest.TestTheItalicFlagDrawsASlantedFace;

  function Lean(AWeight: Integer; ARotated: Boolean): Double;
  var
    bmp: TBGRABitmap;
    p: TTyPainter;
    x, y, top, bot, inkTop, inkBot: Integer;
    sumTop, sumBot, a: Double;
    px: TBGRAPixel;
    y0, y1: Integer;
  begin
    bmp := TBGRABitmap.Create(200, 80, BGRAWhite);
    p := TTyPainter.Create;
    try
      p.BeginPaintOn(nil, Rect(0, 0, 200, 80), 96, bmp);
      if ARotated then
        p.DrawTextRotated('lllll', 'Arial', 40, AWeight, TyRGB(0, 0, 0), 20, 40, 0,
          taLeftJustify, tlCenter)
      else
        p.DrawText(Rect(20, 0, 200, 80), 'lllll', 'Arial', 40, AWeight, TyRGB(0, 0, 0),
          taLeftJustify, tlCenter, False);
      p.EndPaint;
      { the ink's rows }
      top := -1;
      bot := -1;
      for y := 0 to bmp.Height - 1 do
        for x := 0 to bmp.Width - 1 do
          if bmp.GetPixel(x, y).red < 128 then
          begin
            if top < 0 then top := y;
            bot := y;
          end;
      AssertTrue('ink', top >= 0);
      y0 := top + (bot - top) div 4;
      y1 := bot - (bot - top) div 4;
      sumTop := 0; sumBot := 0; inkTop := 0; inkBot := 0;
      for y := top to bot do
        for x := 0 to bmp.Width - 1 do
        begin
          px := bmp.GetPixel(x, y);
          a := (255 - px.red) / 255;
          if a <= 0 then Continue;
          if y <= y0 then begin sumTop := sumTop + a * x; Inc(inkTop); end;
          if y >= y1 then begin sumBot := sumBot + a * x; Inc(inkBot); end;
        end;
      Result := sumTop / Max(1, inkTop) - sumBot / Max(1, inkBot);
    finally
      p.Free;
      bmp.Free;
    end;
  end;

begin
  AssertTrue(Format('upright leans %.2f', [Lean(400, False)]), Abs(Lean(400, False)) < 0.75);
  AssertTrue(Format('italic leans %.2f', [Lean(400 or TyFontItalic, False)]),
    Lean(400 or TyFontItalic, False) > 2);
  AssertTrue(Format('turned upright leans %.2f', [Lean(400, True)]), Abs(Lean(400, True)) < 0.75);
  AssertTrue(Format('turned italic leans %.2f', [Lean(400 or TyFontItalic, True)]),
    Lean(400 or TyFontItalic, True) > 2);
end;

{ THE LAYOUT MEASURES WHAT IS DRAWN: a label written italic in a face whose
  italic is narrower than its upright is laid out at the italic width -- the
  measurer is handed the flag. }
procedure TAdvChartFontStyleOracleTest.TestALabelIsMeasuredInItsItalicFace;
var
  m: ITyTextMeasurer;
  wu, wi, h, lw: Double;
  i: Integer;
  e: TTyChartElement;
  found: Boolean;
  bmp: TBitmap;
begin
  m := TTyPainterTextMeasurer.Create(96);
  FChart := TFsProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Option := '{"animation":false,"xAxis":{"type":"category","data":["a"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","data":[5],'
    + '"label":{"show":true,"position":"top","formatter":"ffffffffffffffff",'
    + '"fontFamily":"Times New Roman","fontSize":20,"fontStyle":"italic"}}]}';
  bmp := TBitmap.Create;
  try
    bmp.SetSize(cW, cH);
    FChart.RenderWindow(bmp.Canvas, Rect(0, 0, cW, cH), 96);
  finally
    bmp.Free;
  end;
  found := False;
  lw := 0;
  wu := 0;
  wi := 0;
  for i := 0 to FChart.List.Count - 1 do
  begin
    e := FChart.List.Element(i);
    { the answer, not the mark's request (a caption with no font) }
    if (e.Caption.Text <> 'ffffffffffffffff') or (e.Caption.FontSizeLogical <= 0) then Continue;
    found := True;
    AssertTrue('the caption carries the flag', (e.Caption.FontWeight and TyFontItalic) <> 0);
    lw := e.Shape.Bounds.Right - e.Shape.Bounds.Left;
    m.MeasureLine(e.Caption.Text, e.Caption.FontName, e.Caption.FontSizeLogical,
      e.Caption.FontWeight, wi, h);
    m.MeasureLine(e.Caption.Text, e.Caption.FontName, e.Caption.FontSizeLogical,
      e.Caption.FontWeight and not TyFontItalic, wu, h);
  end;
  AssertTrue('the label', found);
  AssertTrue(Format('the italic face measures otherwise (%s against %s)',
    [FloatToStr(wi), FloatToStr(wu)]), Abs(wi - wu) >= 1);
  AssertTrue(Format('laid out at the italic width %s, not %s: %s',
    [FloatToStr(wi), FloatToStr(wu), FloatToStr(lw)]), Abs(lw - wi) < 0.5);
end;

{ makeFont joins whatever fontStyle holds; only a string names a face. }
procedure TAdvChartFontStyleOracleTest.TestAFontStyleIsAStringOnly;
var d: TJSONData;
begin
  d := GetJSON('{"a":"italic","b":"oblique 10deg","c":"normal","d":5,"e":null,"f":"Italic","g":"bogus","w":"bold"}');
  try
    AssertEquals('italic', 400 or TyFontItalic, TyFontStyleOver(TJSONObject(d).Find('a'), 400));
    AssertEquals('oblique with its angle', 700 or TyFontItalic, TyFontStyleOver(TJSONObject(d).Find('b'), 700));
    AssertEquals('normal clears', 400, TyFontStyleOver(TJSONObject(d).Find('c'), 400 or TyFontItalic));
    AssertEquals('a number leaves', 400 or TyFontItalic, TyFontStyleOver(TJSONObject(d).Find('d'), 400 or TyFontItalic));
    AssertEquals('null leaves', 400 or TyFontItalic, TyFontStyleOver(TJSONObject(d).Find('e'), 400 or TyFontItalic));
    AssertEquals('absent leaves', 400, TyFontStyleOver(nil, 400));
    AssertEquals('keywords are case-blind', 400 or TyFontItalic, TyFontStyleOver(TJSONObject(d).Find('f'), 400));
    AssertEquals('another word is upright', 400, TyFontStyleOver(TJSONObject(d).Find('g'), 400 or TyFontItalic));
    { a weight replaces the weight, not the style }
    AssertEquals('bold keeps italic', 700 or TyFontItalic,
      TyFontWeightOf(TJSONObject(d).Find('w'), 400 or TyFontItalic));
  finally
    d.Free;
  end;
end;

{ AN HTML TOOLTIP IS ITALIC where its textStyle (or the root's) says so: the
  box's css font is getFont() (TooltipHTMLContent assembleFont) and the
  default content's spans name no style of their own. Not in the fixture --
  node has no DOM to run html mode in; the richText cases there are upright. }
procedure TAdvChartFontStyleOracleTest.TestAnHtmlTooltipTakesTheStyle;

  function Italic(const ATip, ARoot: string; const AText: string): Integer;
  var cs: TJSONObject; log: TStringList; i: Integer; parts: TStringArray;
  begin
    cs := TJSONObject(GetJSON('{"id":"html","option":{"animation":false,'
      + '"tooltip":{"trigger":"item"' + ATip + '}' + ARoot + ','
      + '"series":[{"type":"pie","name":"Ser","label":{"show":false},'
      + '"data":[{"name":"Pt","value":123},{"name":"Qt","value":77}]}]},'
      + '"showTip":{"type":"showTip","seriesIndex":0,"dataIndex":0}}'));
    log := TStringList.Create;
    try
      Show(cs, log);
      { 1 italic, 0 upright, -1 not drawn }
      Result := -1;
      for i := 0 to log.Count - 1 do
      begin
        parts := log[i].Split([#9]);
        if (parts[0] <> AText) or (StrToIntDef(parts[2], 0) = 0) then Continue;
        if (StrToIntDef(parts[1], 0) and TyFontItalic) <> 0 then Result := 1
        else Exit(0);
      end;
    finally
      log.Free;
      cs.Free;
    end;
  end;

begin
  AssertEquals('textStyle italic: the name', 1, Italic(',"textStyle":{"fontStyle":"italic"}', '', 'Pt'));
  AssertEquals('textStyle italic: the value', 1, Italic(',"textStyle":{"fontStyle":"italic"}', '', '123'));
  AssertEquals('the root italic', 1, Italic('', ',"textStyle":{"fontStyle":"italic"}', 'Pt'));
  AssertEquals('textStyle normal over a root italic', 0,
    Italic(',"textStyle":{"fontStyle":"normal"}', ',"textStyle":{"fontStyle":"italic"}', 'Pt'));
  AssertEquals('nothing written', 0, Italic('', '', 'Pt'));
  AssertEquals('richText mode stays upright', 0,
    Italic(',"renderMode":"richText","textStyle":{"fontStyle":"italic"}', '', 'Pt'));
end;

{ A TOOLBOX TITLE (shown under the pointer) is drawn in getFont() of
  emphasis.iconStyle's textFontStyle / ... (ToolboxView), the root
  textStyle's where it has none. }
procedure TAdvChartFontStyleOracleTest.TestAToolboxTitleTakesTextFontStyle;

  function Italic(const AEmph, ARoot: string): Integer;
  var
    log: TStringList;
    i, x, y: Integer;
    parts: TStringArray;
    bmp: TBitmap;
  begin
    Result := -1;
    FreeAndNil(FChart);
    FChart := TFsProbe.Create(FForm);
    FChart.Parent := FForm;
    FChart.Controller := FCtl;
    FChart.AnimationMode := camOff;
    FChart.SetBounds(0, 0, cW, cH);
    FChart.Option := '{"animation":false' + ARoot + ',"xAxis":{"type":"category","data":["a"]},'
      + '"yAxis":{"type":"value"},"series":[{"type":"bar","data":[5]}],"toolbox":{"left":0,"top":0,'
      + '"itemSize":20,"feature":{"saveAsImage":{"title":"Tb"}}' + AEmph + '}}';
    log := TStringList.Create;
    bmp := TBitmap.Create;
    try
      bmp.SetSize(cW, cH);
      FChart.Render(bmp.Canvas, Rect(0, 0, cW, cH), 96);
      for y := 2 to 30 do
        for x := 2 to 30 do
        begin
          if Result >= 0 then Exit;
          FChart.Hover(x, y);
          log.Clear;
          TyPainterTextLogForTest(log);
          try
            FChart.Render(bmp.Canvas, Rect(0, 0, cW, cH), 96);
          finally
            TyPainterTextLogForTest(nil);
          end;
          for i := 0 to log.Count - 1 do
          begin
            parts := log[i].Split([#9]);
            if (parts[0] <> 'Tb') or (StrToIntDef(parts[2], 0) = 0) then Continue;
            if (StrToIntDef(parts[1], 0) and TyFontItalic) <> 0 then Result := 1
            else Result := 0;
          end;
        end;
    finally
      bmp.Free;
      log.Free;
    end;
  end;

begin
  AssertEquals('textFontStyle italic', 1,
    Italic(',"emphasis":{"iconStyle":{"textFontStyle":"italic"}}', ''));
  AssertEquals('none written', 0, Italic('', ''));
  AssertEquals('the root italic', 1, Italic('', ',"textStyle":{"fontStyle":"italic"}'));
  AssertEquals('textFontStyle normal over the root', 0,
    Italic(',"emphasis":{"iconStyle":{"textFontStyle":"normal"}}', ',"textStyle":{"fontStyle":"italic"}'));
end;

initialization
  RegisterTest(TAdvChartFontStyleOracleTest);
end.
