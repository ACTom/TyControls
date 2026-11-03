unit test.advchart.seriesborders;
{$mode objfpc}{$H+}
{ THE PENS OF A SERIES' PATHS, held to upstream. [R6-D]

  tests/fixtures/advchart-series-borders.json, from the real ECharts 6.1
  build (tools/advchart-oracle/series-borders.js): per case settled (an
  action, where one, dispatched and settled), the set of stroke / width /
  dash / dash offset of every stroked path under the series' views -- or of
  the part the case names: a radar item's symbols, a gauge's pointer or
  progress arc, a chord's ribbons -- getItemStyle's border keys and
  getLineStyle's, an item's own over its series', the views' own rules
  (a radar symbol's and a gauge icon's setColor, pointer.itemStyle,
  progress.itemStyle) and the states' styles over them.

  The ends -- lineCap / lineJoin / miterLimit -- go with each pen.

  TestThePensAsUpstream: the same set off the port's frame -- every stroked
  element of a series that is no text and no label line, of that part --
  and, for a part, how many elements it has and how many of them stroke. A
  stroke upstream that is a word zrender cannot parse ('source', a chord's
  default colour) is the canvas' to keep the last element's colour for and
  the port's to draw none: it is not compared; a dash the canvas'
  setLineDash ignores is solid here.

  [R6-E] Cases may carry more: `shapes` -- each path of the part as
  type|cx|cy|r0|r|clockwise start|sweep (a sector, a sausage), a circle's,
  a rect's box -- compared with the elements' shapes; `fills` the set of the
  part's fills (a transparent one, the pictorial bar's rect, not compared);
  `hits` what zr's findHover finds at a point (the part, '' another path,
  '-' nothing), compared with HitTestAt; `clip` a line group's clip rect,
  compared with the elements' ClipRect; `at` the frame at T0 + at with the
  animation running instead of the settled one. A part is also held to its
  path count where it has shapes, and every element of a gauge's progress
  (its round caps too) or track is of the part, with or without a datum.
  A pictorial glyph's pen is drawn in the glyph's frame upstream: the
  oracle writes it times the line scale to four places, and so does this.

  [R6-F] And `looks` -- each element of the part as opacity|shadowBlur|
  shadowOffsetX|shadowOffsetY|shadowColor (the colour where a shadow is
  cast) -- compared with the elements' Alpha and shadow; `cHits` what
  HitTestAt finds at a bar's centre and a pixel either side ('bar' a series
  element, '-' none); the gauge parts `line` (its split lines or ticks),
  `anchor` and `box` (the one other silent path a case shows: the anchor, a
  title's or a reading's plate) and `words` (a title's or a reading's
  words). A pen whose width is Infinity, or whose colour is a word no
  parser reads, is the canvas' to refuse: it strokes with the width / colour
  the element before it left ([R7-W] the port too, held to upstream's canvas
  in test.advchart.linescanvas) -- not compared here. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Color,
     tyControls.AdvanceChart.Measure, tyControls.AdvanceChart.Anim,
     tyControls.AdvanceChart.Render,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TBorderProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function Frame: TTyPaintList;
  end;

  TAdvChartSeriesBordersTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FChart: TBorderProbe;
    procedure Draw;
    procedure Settle(AStart: Double);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestThePensAsUpstream;
    procedure TestARoundCappedArcStrokesOneOutline;
    procedure TestThePenNumbersAsTheCanvasTakesThem;
    procedure TestAPictorialGlyphStrokesInItsOwnFrame;
    procedure TestAPlateStrokesUnderItsFill;
    procedure TestAGaugeTickDashIsMeasuredAtItsWidth;
  end;

implementation

const
  cW = 400;
  cH = 300;
  T0 = 1700000000000.0;
  T1 = T0 + 10000;

function TBorderProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TBorderProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TBorderProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

function LoadJson(const AName: string): TJSONData;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName);
    Result := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
end;

procedure TAdvChartSeriesBordersTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FMeasure := LoadJson('advchart-text-style.json');
end;

procedure TAdvChartSeriesBordersTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

procedure TAdvChartSeriesBordersTest.Draw;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

procedure TAdvChartSeriesBordersTest.Settle(AStart: Double);
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
end;

function NumText(AV: Double): string;
begin
  Result := FloatToStr(AV);
end;

{ String(Math.round(v * 10^ADigits) / 10^ADigits) }
function RoundText(AV: Double; ADigits: Integer): string;
var p: Double;
begin
  p := IntPower(10, ADigits);
  AV := Floor(AV * p + 0.5) / p;
  if AV = 0 then AV := 0;
  Result := FloatToStr(AV);
end;

function ScaledPen(const AEl: TTyChartElement): Boolean;
begin
  Result := AEl.Anim.Role in [carPictorialGlyph, carPictorialClip];
end;

{ stroke|width|dash|offset|cap/join/miterLimit, as the oracle writes it (the
  dash normalizeLineDash'd against the width) }
function PenOf(const AEl: TTyChartElement): string;
var
  c: Cardinal;
  dash: TTyDoubleArray;
  i: Integer;
  ds: string;
  ps: Double;
begin
  { [R6-E] a pen in the shape's frame, as drawn }
  ps := AEl.Style.PenScale;
  if not (ps > 0) then ps := 1;
  if AEl.Style.StrokeGradient.Kind <> cgkNone then Result := 'grad'
  else
  begin
    c := Cardinal(AEl.Style.StrokeColor);
    Result := LowerCase(Format('#%.2x%.2x%.2x%.2x', [(c shr 16) and $FF, (c shr 8) and $FF,
      c and $FF, c shr 24]));
  end;
  { [R6-F] a word's lengths as the renderer takes them -- the element's
    own, which RenderElementAsStyled strokes (the word is measured again
    only for a pen in a shape's frame) [was: the word measured here, blind
    to lengths the builder left measured against another width] }
  if (AEl.Style.DashWord <> 0) and ScaledPen(AEl) then
    dash := TyDashOfWord(AEl.Style.DashWord, AEl.Style.StrokeWidthLogical * ps)
  else if AEl.Style.DashWord <> 0 then
    dash := Copy(AEl.Style.DashLogical, 0, Length(AEl.Style.DashLogical))
  else
  begin
    dash := Copy(AEl.Style.DashLogical, 0, Length(AEl.Style.DashLogical));
    for i := 0 to High(dash) do dash[i] := dash[i] * ps;
  end;
  ds := '';
  for i := 0 to High(dash) do
  begin
    { as drawn: a dash with an entry that is no finite number of nought or
      more strokes solid (the renderer's setLineDash rule) }
    if IsNan(dash[i]) or IsInfinite(dash[i]) or (dash[i] < 0) then
    begin
      ds := '';
      Break;
    end;
    if i > 0 then ds := ds + ',';
    if ScaledPen(AEl) then ds := ds + RoundText(dash[i], 4)
    else ds := ds + NumText(dash[i]);
  end;
  if ds = '' then ds := 'solid';
  if ScaledPen(AEl) then
    Result := Result + '|' + RoundText(AEl.Style.StrokeWidthLogical * ps, 4) + '|' + ds + '|'
      + RoundText(AEl.Style.DashOffsetLogical * ps, 4) + '|'
  else
    Result := Result + '|' + NumText(AEl.Style.StrokeWidthLogical) + '|' + ds + '|'
      + NumText(AEl.Style.DashOffsetLogical) + '|';
  case AEl.Style.LineCap of
    1: Result := Result + 'round';
    2: Result := Result + 'square';
  else
    Result := Result + 'butt';
  end;
  case AEl.Style.LineJoin of
    1: Result := Result + '/round';
    2: Result := Result + '/bevel';
  else
    Result := Result + '/miter';
  end;
  if AEl.Style.MiterLimit > 0 then Result := Result + '/' + NumText(AEl.Style.MiterLimit)
  else Result := Result + '/10';
end;

function PartOf(const AEl: TTyChartElement): string;
begin
  Result := '';
  if (AEl.Anim.Role = carNone) and (AEl.Anim.UtTag = 1) and (AEl.Anim.Sub > 0) then
    Result := 'symbol'
  else if AEl.Anim.Role = carGaugePointer then Result := 'pointer'
  else if AEl.Anim.Role = carGaugeProgress then Result := 'progress'
  else if (AEl.Anim.Role = carChord) and AEl.Datum.IsEdge then Result := 'ribbon'
  { a gauge's track: its silent bands (and their caps) }
  else if (AEl.Anim.Role = carNone) and AEl.Silent and (AEl.Shape.Kind = cskSector)
    and (AEl.Caption.Text = '') then Result := 'track'
  { [R6-F] a gauge's split line or tick (TickElement), its words, and any
    other silent path of its own (its anchor, a title's or a reading's
    plate: a case shows one) }
  else if (AEl.Anim.Role in [carNone, carGaugeDetail]) and (AEl.Caption.Text <> '')
    and (AEl.Caption.FontSizeLogical > 0) then Result := 'words'
  else if (AEl.Anim.Role = carNone) and AEl.Silent and (AEl.Shape.Kind = cskPolyline)
    and (Length(AEl.Shape.Points) = 2) and not AEl.Style.HasFill then Result := 'line'
  else if (AEl.Anim.Role = carNone) and AEl.Silent and (AEl.Caption.Text = '') then
    Result := 'plain';
end;

{ [R7-B] a text block's rect, as the renderer strokes it: its border colour,
  its width as painted (doubled under a fill), its dash normalised against
  it, its phase, the canvas' own ends }
function PiecePenOf(const APc: TTyRtPiece): string;
var
  c: Cardinal;
  pat: TTyDoubleArray;
  ds: string;
  i: Integer;
begin
  c := Cardinal(APc.Stroke);
  Result := LowerCase(Format('#%.2x%.2x%.2x%.2x', [(c shr 16) and $FF, (c shr 8) and $FF,
    c and $FF, c shr 24]));
  ds := '';
  if TyNormalizeLineDash(APc.BorderDash, APc.LineWidth, pat) then
    for i := 0 to High(pat) do
    begin
      if i > 0 then ds := ds + ',';
      ds := ds + NumText(pat[i]);
    end;
  if ds = '' then ds := 'solid';
  Result := Result + '|' + NumText(APc.LineWidth) + '|' + ds + '|'
    + NumText(APc.BorderDashOffset) + '|butt/miter/10';
end;

{ [R7-B] the same looks for a piece: its opacity, and a rect's shadow }
function PieceLooksOf(const APc: TTyRtPiece): string;
var c: Cardinal;
begin
  if APc.Kind = rpkRect then
  begin
    Result := NumText(APc.Opacity) + '|' + NumText(APc.ShadowBlur) + '|'
      + NumText(APc.ShadowOffsetX) + '|' + NumText(APc.ShadowOffsetY) + '|';
    if APc.HasShadow then
    begin
      c := Cardinal(APc.ShadowColor);
      Result := Result + LowerCase(Format('#%.2x%.2x%.2x%.2x', [(c shr 16) and $FF,
        (c shr 8) and $FF, c and $FF, c shr 24]));
    end;
  end
  else
    Result := NumText(APc.Opacity) + '|0|0|0|';
end;

{ [R6-F] opacity|shadowBlur|shadowOffsetX|shadowOffsetY|shadowColor, the
  colour where a shadow is cast }
function LooksOf(const AEl: TTyChartElement): string;
var c: Cardinal;
begin
  Result := NumText(AEl.Style.Alpha) + '|' + NumText(AEl.Style.ShadowBlur) + '|'
    + NumText(AEl.Style.ShadowOffsetX) + '|' + NumText(AEl.Style.ShadowOffsetY) + '|';
  if (AEl.Style.ShadowBlur > 0) or (AEl.Style.ShadowOffsetX <> 0) or (AEl.Style.ShadowOffsetY <> 0) then
  begin
    c := Cardinal(AEl.Style.ShadowColor);
    Result := Result + LowerCase(Format('#%.2x%.2x%.2x%.2x', [(c shr 16) and $FF, (c shr 8) and $FF,
      c and $FF, c shr 24]));
  end;
end;

{ the oracle's type|cx|cy|r0|r|start|sweep, circle|cx|cy|r, rect|x|y|w|h }
function ShapeText(const AEl: TTyChartElement): string;
var a: Double;
begin
  case AEl.Shape.Kind of
    cskSector:
      begin
        if AEl.Shape.Sausage then Result := 'sausage' else Result := 'sector';
        a := AEl.Shape.StartRad - Floor(AEl.Shape.StartRad / (2 * Pi)) * 2 * Pi;
        Result := Result + '|' + RoundText(AEl.Shape.CX, 2) + '|' + RoundText(AEl.Shape.CY, 2) + '|'
          + RoundText(AEl.Shape.R0, 2) + '|' + RoundText(AEl.Shape.R1, 2) + '|' + RoundText(a, 4)
          + '|' + RoundText(Abs(AEl.Shape.EndRad - AEl.Shape.StartRad), 4);
      end;
    cskCircle:
      Result := 'circle|' + RoundText(AEl.Shape.CX, 2) + '|' + RoundText(AEl.Shape.CY, 2) + '|'
        + RoundText(AEl.Shape.R1, 2);
    cskRect, cskRoundRect:
      Result := 'rect|' + RoundText(AEl.Shape.Bounds.Left, 2) + '|' + RoundText(AEl.Shape.Bounds.Top, 2)
        + '|' + RoundText(AEl.Shape.Bounds.Right - AEl.Shape.Bounds.Left, 2) + '|'
        + RoundText(AEl.Shape.Bounds.Bottom - AEl.Shape.Bounds.Top, 2);
  else
    Result := 'kind' + IntToStr(Ord(AEl.Shape.Kind));
  end;
end;

function FillText(const AEl: TTyChartElement): string;
var c: Cardinal;
begin
  Result := '';
  if not AEl.Style.HasFill then Exit;
  if AEl.Style.FillGradient.Kind <> cgkNone then Exit('grad');
  c := Cardinal(AEl.Style.FillColor);
  if (c shr 24) = 0 then Exit;
  Result := LowerCase(Format('#%.2x%.2x%.2x%.2x', [(c shr 16) and $FF, (c shr 8) and $FF,
    c and $FF, c shr 24]));
end;

procedure TAdvChartSeriesBordersTest.TestThePensAsUpstream;
var
  fix: TJSONData;
  cs, pens: TJSONArray;
  c: TJSONObject;
  i, k, j, seen, n, nBad, nCases, nParts, hitEl: Integer;
  lst: TTyPaintList;
  el: TTyChartElement;
  pc: TTyRtPiece;
  got, shapes, fills, clips, looks: TStringList;
  want, have, id, bad, part, p, s: string;
  act, more: TJSONData;
  arr: TJSONArray;

  function SetText(AList: TStringList): string;
  var j: Integer;
  begin
    Result := '';
    for j := 0 to AList.Count - 1 do Result := Result + ' ' + AList[j];
  end;

  function ArrText(AArr: TJSONArray; ASkipClear: Boolean): string;
  var j: Integer;
  begin
    Result := '';
    for j := 0 to AArr.Count - 1 do
      if not (ASkipClear and (Copy(AArr.Strings[j], 8, 2) = '00')) then
        Result := Result + ' ' + AArr.Strings[j];
  end;

begin
  fix := LoadJson('advchart-series-borders.json');
  { the oracle's sort is JS's, by code unit }
  got := TStringList.Create;
  got.UseLocale := False;
  got.CaseSensitive := True;
  got.Sorted := True;
  got.Duplicates := dupIgnore;
  shapes := TStringList.Create;
  shapes.UseLocale := False;
  shapes.CaseSensitive := True;
  shapes.Sorted := True;
  shapes.Duplicates := dupAccept;
  clips := TStringList.Create;
  clips.UseLocale := False;
  clips.CaseSensitive := True;
  clips.Sorted := True;
  clips.Duplicates := dupIgnore;
  fills := TStringList.Create;
  fills.UseLocale := False;
  fills.CaseSensitive := True;
  fills.Sorted := True;
  fills.Duplicates := dupIgnore;
  looks := TStringList.Create;
  looks.UseLocale := False;
  looks.CaseSensitive := True;
  looks.Sorted := True;
  looks.Duplicates := dupIgnore;
  nBad := 0;
  nCases := 0;
  nParts := 0;
  bad := '';
  try
    cs := TJSONObject(fix).Arrays['charts'];
    for i := 0 to cs.Count - 1 do
    begin
      c := cs.Objects[i];
      id := c.Strings['id'];
      part := c.Strings['part'];
      FreeAndNil(FChart);
      FChart := TBorderProbe.Create(FForm);
      FChart.Parent := FForm;
      FChart.Controller := FCtl;
      FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
        TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
        TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
      FChart.AnimationMode := camAlways;
      FChart.AnimNow := T0;
      FChart.SetBounds(0, 0, cW, cH);
      FChart.Option := c.Objects['option'].AsJSON;
      AssertEquals(id + ' parses', '', FChart.OptionError);
      Draw;
      more := c.Find('at');
      if more <> nil then
      begin
        FChart.AnimTick(T0 + more.AsFloat);
        Draw;
      end
      else
        Settle(T0);
      act := c.Find('action');
      if (act <> nil) and (act.JSONType = jtObject) then
      begin
        FChart.AnimNow := T1;
        FChart.DispatchAction(act.AsJSON);
        Settle(T1);
      end;
      lst := FChart.Frame;
      got.Clear;
      shapes.Clear;
      fills.Clear;
      clips.Clear;
      looks.Clear;
      seen := 0;
      n := 0;
      for k := 0 to lst.Count - 1 do
      begin
        el := lst.Element(k);
        if GetEnvironmentVariable('TY_BORDER_DUMP') = id then
          WriteLn(id + ' el ' + IntToStr(k) + ' role ' + IntToStr(Ord(el.Anim.Role)) + ' kind '
            + IntToStr(Ord(el.Datum.Kind)) + ' s ' + IntToStr(el.Datum.SeriesIndex) + ' i '
            + IntToStr(el.Datum.DataIndex) + ' edge ' + BoolToStr(el.Datum.IsEdge, True) + ' ign '
            + BoolToStr(el.Ignore, True) + ' pen ' + PenOf(el) + ' ut ' + IntToStr(el.Anim.UtTag)
            + ' sub ' + IntToStr(el.Anim.Sub) + ' text "' + el.Caption.Text + '"');
        if el.Ignore or el.IsGuide or (el.Anim.Role = carLabel) then Continue;
        p := PartOf(el);
        { [R7-B] a gauge's words laid out in their block: the block's rects
          are the box, its texts the words (Text's children upstream) }
        if (p = 'words') and (Length(el.Caption.RtPieces) > 0)
          and ((part = 'box') or (part = 'words')) then
        begin
          for j := 0 to High(el.Caption.RtPieces) do
          begin
            pc := el.Caption.RtPieces[j];
            if (part = 'words') <> (pc.Kind = rpkText) then Continue;
            Inc(seen);
            looks.Add(PieceLooksOf(pc));
            if (pc.Kind = rpkRect) and pc.HasStroke and (pc.LineWidth > 0) then
            begin
              Inc(n);
              got.Add(PiecePenOf(pc));
            end;
          end;
          Continue;
        end;
        { [R6-F] the one other silent path of a gauge a case shows }
        if (p = 'plain') and ((part = 'anchor') or (part = 'box')) then p := part;
        if (el.Caption.FontSizeLogical > 0) and not ((part = 'words') and (p = 'words')) then Continue;
        if not (((el.Datum.Kind = ctkSeries) and (el.Datum.SeriesIndex >= 0))
          or ((el.Anim.UtTag = 1) and (el.Anim.Series >= 0))
          or ((part <> '') and (p = part) and ((p = 'track') or (p = 'progress') or (p = 'line')
            or (p = 'anchor') or (p = 'box') or (p = 'words')))) then Continue;
        if (part <> '') and (p <> part) then Continue;
        Inc(seen);
        looks.Add(LooksOf(el));
        if p = 'words' then Continue;
        shapes.Add(ShapeText(el));
        s := FillText(el);
        if s <> '' then fills.Add(s);
        if el.HasClip then
          clips.Add('rect|' + RoundText(el.ClipRect.Left, 2) + '|' + RoundText(el.ClipRect.Top, 2) + '|'
            + RoundText(el.ClipRect.Right - el.ClipRect.Left, 2) + '|'
            + RoundText(el.ClipRect.Bottom - el.ClipRect.Top, 2));
        if not (el.Style.StrokeWidthLogical > 0) then Continue;
        if ((el.Style.StrokeColor shr 24) = 0) and (el.Style.StrokeGradient.Kind = cgkNone) then Continue;
        { [R7-W] a width or a colour the canvas carried: not compared }
        if (el.CanvasFlags and (cTyCanvasWidthLeft or cTyCanvasStrokeLeft)) <> 0 then Continue;
        Inc(n);
        got.Add(PenOf(el));
      end;
      pens := c.Arrays['pens'];
      want := '';
      for k := 0 to pens.Count - 1 do
        { a word the canvas cannot take strokes with the last element's
          colour there: no pen here }
        if (Copy(pens.Strings[k], 1, 2) <> 'x:') and (Pos('|Infinity|', pens.Strings[k]) = 0) then
          { a dash setLineDash does not take: the canvas keeps the last
            element's there, the port strokes solid }
          want := want + ' ' + StringReplace(pens.Strings[k], '|ignored|', '|solid|', []);
      have := '';
      for k := 0 to got.Count - 1 do have := have + ' ' + got[k];
      Inc(nCases);
      if part <> '' then
      begin
        Inc(nParts);
        if (seen <> c.Integers['seen']) and (have = want) then
          have := have + Format(' (%d elements, upstream %d)', [seen, c.Integers['seen']]);
      end;
      arr := c.Find('shapes') as TJSONArray;
      if arr <> nil then
      begin
        want := want + ' shapes' + ArrText(arr, False);
        have := have + ' shapes' + SetText(shapes);
      end;
      arr := c.Find('fills') as TJSONArray;
      if arr <> nil then
      begin
        want := want + ' fills' + ArrText(arr, True);
        have := have + ' fills' + SetText(fills);
      end;
      arr := c.Find('clip') as TJSONArray;
      if arr <> nil then
      begin
        want := want + ' clip' + ArrText(arr, False);
        have := have + ' clip' + SetText(clips);
      end;
      arr := c.Find('looks') as TJSONArray;
      if arr <> nil then
      begin
        want := want + ' looks' + ArrText(arr, False);
        have := have + ' looks' + SetText(looks);
      end;
      arr := c.Find('cHits') as TJSONArray;
      if arr <> nil then
      begin
        want := want + ' cHits';
        have := have + ' cHits';
        for k := 0 to arr.Count - 1 do
        begin
          FChart.HitTestAt(TJSONArray(arr.Items[k]).Integers[0], TJSONArray(arr.Items[k]).Integers[1], hitEl);
          if hitEl < 0 then p := '-'
          else if FChart.SeriesList.Element(hitEl).Datum.Kind = ctkSeries then p := 'bar'
          else p := 'other';
          want := want + Format(' %d,%d=%s', [TJSONArray(arr.Items[k]).Integers[0],
            TJSONArray(arr.Items[k]).Integers[1], TJSONArray(arr.Items[k]).Strings[2]]);
          have := have + Format(' %d,%d=%s', [TJSONArray(arr.Items[k]).Integers[0],
            TJSONArray(arr.Items[k]).Integers[1], p]);
        end;
      end;
      arr := c.Find('hits') as TJSONArray;
      if arr <> nil then
      begin
        want := want + ' hits';
        have := have + ' hits';
        for k := 0 to arr.Count - 1 do
        begin
          FChart.HitTestAt(TJSONArray(arr.Items[k]).Integers[0], TJSONArray(arr.Items[k]).Integers[1], hitEl);
          if hitEl < 0 then p := '-' else p := PartOf(FChart.SeriesList.Element(hitEl));
          want := want + Format(' %d,%d=%s', [TJSONArray(arr.Items[k]).Integers[0],
            TJSONArray(arr.Items[k]).Integers[1], TJSONArray(arr.Items[k]).Strings[2]]);
          have := have + Format(' %d,%d=%s', [TJSONArray(arr.Items[k]).Integers[0],
            TJSONArray(arr.Items[k]).Integers[1], p]);
        end;
      end;
      if have <> want then
      begin
        Inc(nBad);
        bad := bad + LineEnding + Format('  %s: %s here, upstream %s', [id, Trim(have),
          Trim(want)]);
      end;
    end;
  finally
    got.Free;
    shapes.Free;
    fills.Free;
    clips.Free;
    looks.Free;
    fix.Free;
  end;
  AssertTrue('cases', nCases >= 40);
  AssertTrue('parts', nParts >= 25);
  AssertTrue(Format('%d of %d differ from upstream:%s', [nBad, nCases, bad]), nBad = 0);
end;

{ [R6-E] A ROUND-CAPPED PROGRESS ARC WITH A BORDER, drawn: its round end is
  stroked round its rim, and where the end meets the ring -- the middle of the
  band at the end angle -- there is fill and no pen (the sector and two discs
  it was stroked the sector's square end across the band and the discs not
  at all) }
procedure TAdvChartSeriesBordersTest.TestARoundCappedArcStrokesOneOutline;
var
  k: Integer;
  el, arc: TTyChartElement;
  rc, dr, a, cx, cy: Double;
  c: TBGRAPixel;

  function Dark(AX, AY: Double): Boolean;
  begin
    c := FBmp.GetPixel(Round(AX), Round(AY));
    Result := (c.red < 90) and (c.green < 90) and (c.blue < 90);
  end;

begin
  FChart := TBorderProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Option := '{"animation":false,"series":[{"type":"gauge","pointer":{"show":false},'
    + '"axisLine":{"show":false},"axisTick":{"show":false},"splitLine":{"show":false},'
    + '"axisLabel":{"show":false},"detail":{"show":false},"title":{"show":false},'
    + '"progress":{"show":true,"roundCap":true,"width":30,"itemStyle":{"color":"#ff0000",'
    + '"borderColor":"#000","borderWidth":3}},"data":[{"value":40}]}]}';
  AssertEquals('parses', '', FChart.OptionError);
  Draw;
  arc := Default(TTyChartElement);
  for k := 0 to FChart.SeriesList.Count - 1 do
  begin
    el := FChart.SeriesList.Element(k);
    if el.Anim.Role = carGaugeProgress then arc := el;
  end;
  AssertTrue('the arc', arc.Shape.Kind = cskSector);
  dr := (arc.Shape.R1 - arc.Shape.R0) / 2;
  rc := arc.Shape.R0 + dr;
  for k := 0 to 1 do
  begin
    if k = 0 then a := arc.Shape.EndRad else a := arc.Shape.StartRad;
    cx := arc.Shape.CX + Cos(a) * rc;
    cy := arc.Shape.CY + Sin(a) * rc;
    AssertFalse(Format('end %d: no pen across the band (%d %d %d)', [k, c.red, c.green, c.blue]),
      Dark(cx, cy) or Dark(cx + Cos(a) * dr * 0.5, cy + Sin(a) * dr * 0.5));
    { the tip of the round end, past the end angle along the band }
    if k = 0 then a := a + Pi / 2 else a := a - Pi / 2;
    { (antialiased: the darkest of three pixels across the rim) }
    AssertTrue(Format('end %d: its rim stroked (%d %d %d)', [k, c.red, c.green, c.blue]),
      Dark(cx + Cos(a) * (dr - 1), cy + Sin(a) * (dr - 1)) or Dark(cx + Cos(a) * dr, cy + Sin(a) * dr)
      or Dark(cx + Cos(a) * (dr + 1), cy + Sin(a) * (dr + 1)));
  end;
end;

{ [R6-E] A PICTORIAL GLYPH'S PEN, DRAWN: built at the pattern size (400)
  and scaled to its 20 px box, a borderWidth of 40 is 2 px on the screen --
  five pixels outside the glyph is ground, inside its edge is the fill }
procedure TAdvChartSeriesBordersTest.TestAPictorialGlyphStrokesInItsOwnFrame;
var
  k: Integer;
  el, glyph: TTyChartElement;
  b: TTyRectF;
  c: TBGRAPixel;
begin
  FChart := TBorderProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Option := '{"animation":false,"xAxis":{"type":"category","data":["a"],"show":false},'
    + '"yAxis":{"show":false},"series":[{"type":"pictorialBar","symbol":"rect","symbolSize":[20,20],'
    + '"itemStyle":{"color":"#ff0000","borderColor":"#000","borderWidth":40},"data":[5]}]}';
  AssertEquals('parses', '', FChart.OptionError);
  Draw;
  glyph := Default(TTyChartElement);
  for k := 0 to FChart.SeriesList.Count - 1 do
  begin
    el := FChart.SeriesList.Element(k);
    if el.Anim.Role in [carPictorialGlyph, carPictorialClip] then glyph := el;
  end;
  AssertTrue('the glyph', glyph.Anim.Role in [carPictorialGlyph, carPictorialClip]);
  AssertEquals('its pen in its frame', 0.05, glyph.Style.PenScale, 1e-9);
  b := TyShapeBounds(glyph.Shape);
  c := FBmp.GetPixel(Round(b.Right + 5), Round((b.Top + b.Bottom) / 2));
  AssertTrue(Format('ground beside it (%d %d %d)', [c.red, c.green, c.blue]),
    (c.red > 200) and (c.green > 200) and (c.blue > 200));
  c := FBmp.GetPixel(Round(b.Right - 4), Round((b.Top + b.Bottom) / 2));
  AssertTrue(Format('fill inside its edge (%d %d %d)', [c.red, c.green, c.blue]),
    (c.red > 200) and (c.green < 60) and (c.blue < 60));
end;

{ [R6-F] A SPLIT LINE'S DASH WORD IN THE LIST: 'dashed' at width 3 is
  [12, 6] on the element itself -- the list is what is painted wherever no
  animation frame stands (AnimFrame hands it over as it is), and a frame
  measures the word again, so the pens' comparison, which reads the frame,
  cannot tell lengths measured against another width }
procedure TAdvChartSeriesBordersTest.TestAGaugeTickDashIsMeasuredAtItsWidth;
var
  k, n: Integer;
  el: TTyChartElement;
begin
  FChart := TBorderProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Option := '{"animation":false,"series":[{"type":"gauge","pointer":{"show":false},'
    + '"axisLine":{"show":false},"axisTick":{"show":false},"axisLabel":{"show":false},'
    + '"detail":{"show":false},"title":{"show":false},"splitLine":{"show":true,'
    + '"lineStyle":{"color":"#ff0000","width":3,"type":"dashed"}},"data":[{"value":40}]}]}';
  AssertEquals('parses', '', FChart.OptionError);
  Draw;
  n := 0;
  for k := 0 to FChart.SeriesList.Count - 1 do
  begin
    el := FChart.SeriesList.Element(k);
    if PartOf(el) <> 'line' then Continue;
    Inc(n);
    AssertEquals('the dash''s two lengths', 2, Length(el.Style.DashLogical));
    AssertEquals('dash', 12, el.Style.DashLogical[0], 1e-9);
    AssertEquals('gap', 6, el.Style.DashLogical[1], 1e-9);
  end;
  AssertEquals('the split lines', 11, n);
end;

{ [R6-F] A READING'S PLATE WITH A FILL AND A BORDER, drawn: zrender's
  _renderBackground strokes it first at twice the width and fills over it
  (strokeFirst) -- the border shows its own 4 px outside the plate, and the
  fill reaches the plate's edge (stroked over the fill at 8 the inner half
  would be black; at 4 the outer half would be 2 px) }
procedure TAdvChartSeriesBordersTest.TestAPlateStrokesUnderItsFill;
var
  k, j: Integer;
  el, plate: TTyChartElement;
  pc: TTyRtPiece;
  b: TTyRectF;
  c: TBGRAPixel;
  my: Integer;
begin
  FChart := TBorderProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Option := '{"animation":false,"series":[{"type":"gauge","pointer":{"show":false},'
    + '"axisLine":{"show":false},"axisTick":{"show":false},"splitLine":{"show":false},'
    + '"axisLabel":{"show":false},"title":{"show":false},"progress":{"show":false},'
    + '"detail":{"show":true,"offsetCenter":[0,0],"color":"#ff0000","backgroundColor":"#ff0000",'
    + '"borderColor":"#000000","borderWidth":4,"width":120,"height":40},"data":[{"value":40}]}]}';
  AssertEquals('parses', '', FChart.OptionError);
  Draw;
  { [R7-B] the reading is laid out in its block: the plate is its rect }
  plate := Default(TTyChartElement);
  pc := Default(TTyRtPiece);
  for k := 0 to FChart.SeriesList.Count - 1 do
  begin
    el := FChart.SeriesList.Element(k);
    if el.Anim.Role <> carGaugeDetail then Continue;
    plate := el;
    for j := 0 to High(el.Caption.RtPieces) do
      if el.Caption.RtPieces[j].Kind = rpkRect then pc := el.Caption.RtPieces[j];
  end;
  AssertTrue('the plate', pc.StrokeFirst and pc.HasFill and pc.HasStroke);
  AssertEquals('painted at twice the border', 8.0, pc.LineWidth, 0);
  b.Left := plate.Caption.X + pc.X;
  b.Top := plate.Caption.Y + pc.Y;
  b.Right := b.Left + pc.W;
  b.Bottom := b.Top + pc.H;
  my := Round((b.Top + b.Bottom) / 2);
  c := FBmp.GetPixel(Round(b.Left + 2), my);
  AssertTrue(Format('the fill at the edge (%d %d %d)', [c.red, c.green, c.blue]),
    (c.red > 200) and (c.green < 60) and (c.blue < 60));
  c := FBmp.GetPixel(Round(b.Left - 3), my);
  AssertTrue(Format('the border outside it (%d %d %d)', [c.red, c.green, c.blue]),
    (c.red < 60) and (c.green < 60) and (c.blue < 60));
end;

{ [R6-E] A PEN'S NUMBERS: a numeric string is its number (the canvas
  converts it); a width that is no number strokes nothing (zrender's
  `lineWidth > 0`); what the canvas refuses -- an infinite width, a phase
  that is no finite number, a miter limit that is no number above nought --
  it keeps from the last element: the width reads as none here (its
  builder marks the infinity, R7-W), the phase as cTyCanvasPhaseLeft and
  the miter as -1, which the paint order settles. Not written (nil, null) is not-a-number: the model's get
  falls through it. }
procedure TAdvChartSeriesBordersTest.TestThePenNumbersAsTheCanvasTakesThem;

  function J(const AText: string): TJSONData;
  begin
    Result := GetJSON('{"v":' + AText + '}');
  end;

  procedure W(const AText: string; AWant: Double);
  var o: TJSONData; v: Double;
  begin
    o := J(AText);
    try
      v := TyOptPenWidth(TJSONObject(o).Find('v'));
      if IsNan(AWant) then AssertTrue('width ' + AText + ' unwritten', IsNan(v))
      else AssertEquals('width ' + AText, AWant, v, 0);
    finally
      o.Free;
    end;
  end;

  procedure O(const AText: string; AWant: Double);
  var x: TJSONData; v: Double;
  begin
    x := J(AText);
    try
      v := TyOptPenOffset(TJSONObject(x).Find('v'));
      if IsNan(AWant) then AssertTrue('offset ' + AText + ' unwritten', IsNan(v))
      else AssertEquals('offset ' + AText, AWant, v, 0);
    finally
      x.Free;
    end;
  end;

  procedure M(const AText: string; AWant: Double);
  var x: TJSONData; v: Double;
  begin
    x := J(AText);
    try
      v := TyOptMiterLimit(TJSONObject(x).Find('v'));
      if IsNan(AWant) then AssertTrue('miter ' + AText + ' unwritten', IsNan(v))
      else AssertEquals('miter ' + AText, AWant, v, 0);
    finally
      x.Free;
    end;
  end;

begin
  W('3', 3); W('"3"', 3); W('" 2.5 "', 2.5); W('"0x10"', 16); W('"abc"', 0); W('""', 0);
  W('"0"', 0); W('true', 1); W('[2]', 2); W('[]', 0); W('[1,2]', 0); W('{}', 0);
  W('"1e999"', 0); W('null', NaN); W('-2', -2);
  AssertTrue('width nil unwritten', IsNan(TyOptPenWidth(nil)));
  { [R7-W] a phase that is no finite number the canvas refuses, keeping the
    one it had: cTyCanvasPhaseLeft for the paint order to settle [was: 0] }
  O('"2"', 2); O('"abc"', cTyCanvasPhaseLeft); O('"1e999"', cTyCanvasPhaseLeft); O('""', 0);
  O('-3', -3); O('null', NaN);
  M('"4"', 4); M('""', 10); M('"0"', -1); M('0', 10); M('-1', -1); M('"abc"', -1);
  M('"1e999"', -1); M('2.5', 2.5); M('null', NaN);
  AssertTrue('miter nil unwritten', IsNan(TyOptMiterLimit(nil)));
end;

initialization
  RegisterTest(TAdvChartSeriesBordersTest);
end.
