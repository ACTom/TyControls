unit test.advchart.richtext;
{$mode objfpc}{$H+}
{ ZRENDER'S TEXT BLOCK, held to upstream: the engine alone.

  tools/advchart-oracle/rich-text.js records, for every text the real
  ECharts 6.1 build draws in its cases, the style zrender received (the
  block's and each rich name's, after ECharts resolved the option), the
  host's defaults, the anchor, and every piece zrender painted in order --
  the block's rect, each token's rect and text -- in the text's own frame.
  This hands AdvChart.RichText exactly those styles and compares the pieces
  it answers, one by one: kind, place and size, words, alignment, font,
  fill, stroke and its width, the border painted first, the corner radii.
  Resolving an ECharts option into these styles is the wiring's; it is held
  by the chart-level test. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Color, tyControls.AdvChart.RichText,
     test.advchart.gridbounds;
type
  TAdvChartRichTextEngineOracleTest = class(TTestCase)
  private
    FRoot: TJSONData;
    FMeasurer: ITyTextMeasurer;
    FBad, FCompared, FTexts: Integer;
    FReport: string;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Miss(const AWhere, AWhat: string);
    procedure CheckText(const ACase: string; T: TJSONObject);
  published
    procedure TestTheBlockAsUpstream;
  end;

implementation

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
  { a value zrender kept as written ('15px', '50%') rather than a number }
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

function Near(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  Result := Abs(A - B) <= 1e-9 * Max(1.0, Abs(B));
end;

function AlignOf(const S: string): TTyRtAlign;
begin
  if S = 'left' then Result := rtaLeft
  else if (S = 'center') or (S = 'middle') then Result := rtaCenter
  else if S = 'right' then Result := rtaRight
  else Result := rtaNone;
end;

function VAlignOf(const S: string): TTyRtVAlign;
begin
  if S = 'top' then Result := rtvTop
  else if (S = 'middle') or (S = 'center') then Result := rtvMiddle
  else if S = 'bottom' then Result := rtvBottom
  else Result := rtvNone;
end;

function AlignWord(A: TTyRtAlign): string;
begin
  case A of
    rtaLeft: Result := 'left';
    rtaCenter: Result := 'center';
    rtaRight: Result := 'right';
  else
    Result := '';
  end;
end;

function WeightOf(const S: string): Integer;
begin
  if (S = 'bold') or (S = 'bolder') then Exit(700);
  if (S = '') or (S = 'normal') then Exit(400);
  Result := StrToIntDef(S, 400);
end;

{ a colour string as the chart parses it; '' and none/transparent are none }
function ColourOf(const S: string; out AC: TTyChartColor): Boolean;
begin
  AC := 0;
  if (S = '') or (S = 'none') or (S = 'transparent') then Exit(False);
  Result := TyTryParseChartColor(S, AC);
end;

{ one zrender style object into the engine's }
function StyleOf(O: TJSONObject): TTyRtStyle;
var
  d: TJSONData;
  s: string;
  k: Integer;
  c: TTyChartColor;
begin
  Result := TyRtStyleDefault;
  Result.FontSizePx := 0;
  if O = nil then Exit;
  d := O.Find('fontSize');
  if d <> nil then
  begin
    Result.FontSizePx := Hex(d);
    Result.FontFamily := Str(O.Find('fontFamily'));
    Result.FontWeight := WeightOf(Str(O.Find('fontWeight')));
  end;
  if O.Find('fill') <> nil then
  begin
    Result.HasFill := True;
    Result.FillNone := not ColourOf(Str(O.Find('fill')), c);
    Result.Fill := c;
  end;
  if O.Find('stroke') <> nil then
  begin
    Result.HasStroke := True;
    Result.StrokeNone := not ColourOf(Str(O.Find('stroke')), c);
    Result.Stroke := c;
  end;
  d := O.Find('lineWidth');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    Result.HasLineWidth := True;
    Result.LineWidth := Hex(d);
  end;
  Result.Align := AlignOf(Str(O.Find('align')));
  Result.VAlign := VAlignOf(Str(O.Find('verticalAlign')));
  d := O.Find('lineHeight');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    Result.HasLineHeight := True;
    Result.LineHeight := Hex(d);
  end;
  d := O.Find('width');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    s := Str(d);
    if s = 'auto' then Result.WidthKind := rtwAuto
    else if (s <> '') and (s[Length(s)] = '%') then
    begin
      Result.WidthKind := rtwPercent;
      Result.Width := StrToFloat(Copy(s, 1, Length(s) - 1));
    end
    else
    begin
      Result.WidthKind := rtwNumber;
      Result.Width := Hex(d);
    end;
  end;
  d := O.Find('height');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    Result.HasHeight := True;
    Result.Height := Hex(d);
  end;
  d := O.Find('padding');
  if d is TJSONArray then
  begin
    Result.HasPadding := True;
    for k := 0 to 3 do Result.Padding[k] := Hex(TJSONArray(d).Items[k]);
  end;
  if ColourOf(Str(O.Find('backgroundColor')), c) then
  begin
    Result.HasBackground := True;
    Result.Background := c;
  end;
  if ColourOf(Str(O.Find('borderColor')), c) then
  begin
    Result.HasBorderColor := True;
    Result.BorderColor := c;
  end;
  d := O.Find('borderWidth');
  if (d <> nil) and (d.JSONType <> jtNull) then Result.BorderWidth := Hex(d);
  d := O.Find('borderRadius');
  if d is TJSONArray then
  begin
    for k := 0 to 3 do
      if k < TJSONArray(d).Count then Result.Radius[k] := Hex(TJSONArray(d).Items[k]);
    { the CSS spread of fewer than four }
    case TJSONArray(d).Count of
      1: begin Result.Radius[1] := Result.Radius[0]; Result.Radius[2] := Result.Radius[0];
           Result.Radius[3] := Result.Radius[0]; end;
      2: begin Result.Radius[2] := Result.Radius[0]; Result.Radius[3] := Result.Radius[1]; end;
      3: Result.Radius[3] := Result.Radius[1];
    end;
  end
  else if (d <> nil) and (d.JSONType <> jtNull) then
    for k := 0 to 3 do Result.Radius[k] := Hex(d);
  d := O.Find('opacity');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    Result.HasOpacity := True;
    Result.Opacity := Hex(d);
  end;
  s := Str(O.Find('overflow'));
  if s = 'truncate' then Result.Overflow := rtoTruncate
  else if s = 'break' then Result.Overflow := rtoBreak
  else if s = 'breakAll' then Result.Overflow := rtoBreakAll;
  Result.LineOverflowTruncate := Str(O.Find('lineOverflow')) = 'truncate';
  if O.Find('ellipsis') <> nil then
  begin
    Result.HasEllipsis := True;
    Result.Ellipsis := Str(O.Find('ellipsis'));
  end;
end;

procedure TAdvChartRichTextEngineOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FMeasurer := TZrSsrMeasurer.Create(
    TJSONObject(FRoot).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FRoot).Objects['ratios'].Integers['firstCode']);
  FBad := 0;
  FCompared := 0;
  FTexts := 0;
  FReport := '';
end;

procedure TAdvChartRichTextEngineOracleTest.TearDown;
begin
  FMeasurer := nil;
  FRoot.Free;
  inherited TearDown;
end;

procedure TAdvChartRichTextEngineOracleTest.Miss(const AWhere, AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 7000 then
    FReport := FReport + LineEnding + '  ' + AWhere + ': ' + AWhat;
end;

procedure TAdvChartRichTextEngineOracleTest.CheckText(const ACase: string;
  T: TJSONObject);
var
  style: TTyRtStyle;
  rich: TTyRtRich;
  def: TTyRtDefault;
  ds, rs: TJSONObject;
  i, k, n: Integer;
  res: TTyRtResult;
  pieces: TJSONArray;
  p: TJSONObject;
  q: TTyRtPiece;
  where, fill, stroke, w: string;
  c: TTyChartColor;
  bx, by: Double;
begin
  Inc(FTexts);
  if T.Find('style') is TJSONObject then style := StyleOf(T.Objects['style'])
  else style := StyleOf(nil);
  if style.FontSizePx <= 0 then style.FontSizePx := 12;
  if style.FontFamily = '' then style.FontFamily := 'sans-serif';
  rich := nil;
  rs := nil;
  if T.Find('richStyles') is TJSONObject then rs := T.Objects['richStyles'];
  if rs <> nil then
  begin
    SetLength(rich, rs.Count);
    for i := 0 to rs.Count - 1 do
    begin
      rich[i].Name := rs.Names[i];
      if rs.Items[i] is TJSONObject then rich[i].Style := StyleOf(TJSONObject(rs.Items[i]))
      else rich[i].Style := StyleOf(nil);
    end;
  end;
  def := Default(TTyRtDefault);
  ds := nil;
  if T.Find('defaultStyle') is TJSONObject then ds := T.Objects['defaultStyle'];
  if ds <> nil then
  begin
    def.HasFill := ColourOf(Str(ds.Find('fill')), c);
    def.Fill := c;
    def.HasStroke := ColourOf(Str(ds.Find('stroke')), c);
    def.Stroke := c;
    def.AutoStroke := (ds.Find('autoStroke') <> nil) and (ds.Find('autoStroke').JSONType = jtBoolean)
      and ds.Find('autoStroke').AsBoolean;
    def.Align := AlignOf(Str(ds.Find('align')));
    def.VAlign := VAlignOf(Str(ds.Find('verticalAlign')));
  end;
  bx := 0;
  by := 0;
  if T.Find('anchor') is TJSONObject then
  begin
    bx := Hex(T.Objects['anchor'].Find('x'));
    by := Hex(T.Objects['anchor'].Find('y'));
    if IsNan(bx) then bx := 0;
    if IsNan(by) then by := 0;
  end;
  res := TyRtLayout(T.Strings['text'], style, rich,
    (T.Find('rich') <> nil) and (T.Find('rich').JSONType = jtBoolean) and T.Booleans['rich'],
    def, bx, by, FMeasurer);
  pieces := T.Arrays['pieces'];
  where := ACase + ' "' + T.Strings['text'] + '"';
  n := 0;
  for i := 0 to pieces.Count - 1 do
  begin
    p := pieces.Objects[i];
    { an undrawn rect counts: zrender makes it (and bounds by it) }
    if n > High(res.Pieces) then
    begin
      Miss(where, Format('upstream piece %d (%s) missing', [i, p.Strings['kind']]));
      Break;
    end;
    q := res.Pieces[n];
    Inc(n);
    Inc(FCompared);
    if (p.Strings['kind'] = 'rect') <> (q.Kind = rpkRect) then
    begin
      Miss(where, Format('piece %d is a %s upstream', [i, p.Strings['kind']]));
      Continue;
    end;
    if q.Kind = rpkRect then
    begin
      if not (Near(q.X, Hex(p.Find('x'))) and Near(q.Y, Hex(p.Find('y')))
        and Near(q.W, Hex(p.Find('width'))) and Near(q.H, Hex(p.Find('height')))) then
        Miss(where, Format('rect %d %s,%s %sx%s upstream, %s,%s %sx%s here', [i,
          Str(p.Find('xText')), Str(p.Find('yText')), Str(p.Find('widthText')),
          Str(p.Find('heightText')), FloatToStr(q.X), FloatToStr(q.Y),
          FloatToStr(q.W), FloatToStr(q.H)]));
      fill := Str(p.Find('fill'));
      if ColourOf(fill, c) <> q.HasFill then
        Miss(where, Format('rect %d fill %s upstream', [i, fill]))
      else if q.HasFill and ((c or $FF000000) <> (q.Fill or $FF000000)) then
        Miss(where, Format('rect %d fill %s upstream, %s here', [i, fill, IntToHex(q.Fill, 8)]));
      stroke := Str(p.Find('stroke'));
      if ColourOf(stroke, c) <> q.HasStroke then
        Miss(where, Format('rect %d stroke %s upstream', [i, stroke]))
      else if q.HasStroke then
      begin
        if not Near(q.LineWidth, Hex(p.Find('lineWidth'))) then
          Miss(where, Format('rect %d line width %s upstream, %s here', [i,
            Str(p.Find('lineWidthText')), FloatToStr(q.LineWidth)]));
        if (p.Find('strokeFirst') <> nil) and (p.Find('strokeFirst').JSONType = jtBoolean)
          and (p.Booleans['strokeFirst'] <> q.StrokeFirst) then
          Miss(where, Format('rect %d strokeFirst', [i]));
      end;
      if p.Find('r4') is TJSONArray then
        for k := 0 to 3 do
          if not Near(q.Radius[k], Hex(p.Arrays['r4'].Items[k])) then
          begin
            Miss(where, Format('rect %d radius %d', [i, k]));
            Break;
          end;
    end
    else
    begin
      if q.Text <> p.Strings['text'] then
        Miss(where, Format('text %d "%s" upstream, "%s" here', [i, p.Strings['text'], q.Text]));
      if not (Near(q.X, Hex(p.Find('x'))) and Near(q.Y, Hex(p.Find('y')))) then
        Miss(where, Format('text %d "%s" at %s,%s upstream, %s,%s here', [i,
          p.Strings['text'], Str(p.Find('xText')), Str(p.Find('yText')),
          FloatToStr(q.X), FloatToStr(q.Y)]));
      if AlignWord(q.TextAlign) <> Str(p.Find('textAlign')) then
        Miss(where, Format('text %d align %s upstream, %s here', [i,
          Str(p.Find('textAlign')), AlignWord(q.TextAlign)]));
      if (p.Find('px') <> nil) and not Near(q.FontSizePx, p.Floats['px']) then
        Miss(where, Format('text %d size %s upstream, %s here', [i,
          p.Get('px', ''), FloatToStr(q.FontSizePx)]));
      { a font handed over as one CSS string leaves the part empty: read
        the weight off the string }
      w := Str(p.Find('fontWeight'));
      if (w = '') and (Pos('bold', Str(p.Find('font'))) > 0) then w := 'bold';
      if WeightOf(w) <> q.FontWeight then
        Miss(where, Format('text %d weight %s upstream, %d here', [i,
          Str(p.Find('fontWeight')), q.FontWeight]));
      fill := Str(p.Find('fill'));
      if ColourOf(fill, c) <> q.HasFill then
        Miss(where, Format('text %d fill %s upstream', [i, fill]))
      else if q.HasFill and ((c or $FF000000) <> (q.Fill or $FF000000)) then
        Miss(where, Format('text %d fill %s upstream, %s here', [i, fill, IntToHex(q.Fill, 8)]));
      stroke := Str(p.Find('stroke'));
      if ColourOf(stroke, c) <> q.HasStroke then
        Miss(where, Format('text %d stroke %s upstream, %s here', [i, stroke,
          BoolToStr(q.HasStroke, IntToHex(q.Stroke, 8), 'none')]))
      else if q.HasStroke and not Near(q.LineWidth, Hex(p.Find('lineWidth'))) then
        Miss(where, Format('text %d stroke width %s upstream, %s here', [i,
          Str(p.Find('lineWidthText')), FloatToStr(q.LineWidth)]));
    end;
  end;
  Inc(FCompared);
  if n <> Length(res.Pieces) then
    Miss(where, Format('%d pieces upstream, %d here', [pieces.Count, Length(res.Pieces)]));
end;

procedure TAdvChartRichTextEngineOracleTest.TestTheBlockAsUpstream;
var
  cases, texts: TJSONArray;
  c, t: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    texts := cases.Objects[c].Arrays['texts'];
    for t := 0 to texts.Count - 1 do
      try
        CheckText(cases.Objects[c].Strings['name'], texts.Objects[t]);
      except
        on E: Exception do
          Miss(cases.Objects[c].Strings['name'] + ' text ' + IntToStr(t),
            E.ClassName + ': ' + E.Message);
      end;
  end;
  AssertTrue(Format('%d of %d differ:%s', [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('only %d texts', [FTexts]), FTexts >= 190);
end;

initialization
  RegisterTest(TAdvChartRichTextEngineOracleTest);
end.
