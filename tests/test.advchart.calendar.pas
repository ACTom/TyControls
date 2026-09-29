unit test.advchart.calendar;
{$mode objfpc}{$H+}
{ THE CALENDAR COORDINATE SYSTEM AND ITS PICTURE, held to what ECharts 6.1
  lays out and draws.

  tools/advchart-oracle/calendar-layout.js runs every case under TZ=UTC and
  records, per calendar: the box after both normalisation passes, the rect
  and cell size, the range info, the day cells, every split and edge line,
  every label's words and anchor, and a set of probe dates through
  dataToPoint / dataToLayout / dataToCalendarLayout. The port's calendar is
  run with its UTC seam on and compared to the bit.

  Colours and fonts are compared where the option wrote them: the defaults
  are the skin's, by the theme rule, and upstream's tokens are not. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.AdvanceChart,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Data, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Shape, tyControls.AdvChart.Color,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Calendar,
     tyControls.StrConsts;
type
  TFixedMeasurer = class(TInterfacedObject, ITyTextMeasurer)
  public
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

  TAdvChartCalendarOracleTest = class(TTestCase)
  private
    FRoot: TJSONData;
    FOpt: TTyChartOption;
    FBad, FCompared: Integer;
    FReport, FName: string;
    FSavedSource: TTyDateTimeNameSource;
    procedure Miss(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SamePt(const AWhat: string; const AGot: TTyPointF; AWant: TJSONData);
    procedure SameD(const AWhat: string; AGot, AWant: Double);
    procedure CheckCalendar(ACase, ACal: TJSONObject);
    procedure RunCases(AGallery: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheCalendarAsUpstreamLaysItOut;
    procedure TestTheGalleryCalendarsAsUpstream;
    procedure TestAHeatmapCellSitsBetweenTheDayAndTheSplitLine;
    procedure TestAFractionOfAMillisecondCarriesIntoTheNextDay;
  end;

  TCalProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  { THE CALENDAR IN THE CONTROL: laid out by the chart and drawn into its
    paint list, with the skin's ink }
  TAdvChartCalendarChartTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TCalProbe;
    FBmp: TBGRABitmap;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestACalendarWithNoSeriesIsDrawn;
  end;

implementation

procedure TCalProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TCalProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-calendar-layout.json';
end;

function Bits(A: Double): QWord;
begin
  Result := 0;
  Move(A, Result, SizeOf(Result));
end;

function IsNull(AData: TJSONData): Boolean;
begin
  Result := (AData = nil) or (AData.JSONType = jtNull);
end;

function Num(AData: TJSONData): Double;
begin
  if IsNull(AData) then Exit(NaN);
  if AData.JSONType = jtString then Exit(TyJsToNumber(AData.AsString));
  Result := AData.AsFloat;
end;

procedure TFixedMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
begin
  AW := 10 * Length(AText);
  AH := AFontSizeLogical;
end;

function TFixedMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
begin
  Result := AText;
end;

procedure TAdvChartCalendarOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FOpt := TTyChartOption.Create;
  { THE CHART'S LOCALE IS THE LIBRARY'S, and upstream's is English under
    node: pinned to the English resourcestrings so this reads the same on
    every machine }
  FSavedSource := TyDateTimeNameSource;
  TyDateTimeNameSource := dnTranslation;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartCalendarOracleTest.TearDown;
begin
  TyDateTimeNameSource := FSavedSource;
  FreeAndNil(FOpt);
  FreeAndNil(FRoot);
  inherited TearDown;
end;

procedure TAdvChartCalendarOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartCalendarOracleTest.Same(const AWhat: string; AGot: Double;
  AWant: TJSONData);
var want: Double;
begin
  Inc(FCompared);
  want := Num(AWant);
  if IsNan(want) and IsNan(AGot) then Exit;
  if IsNan(want) or IsNan(AGot) or (Bits(AGot) <> Bits(want)) then
    Miss(Format('%s %s, upstream %s', [AWhat, FloatToStr(AGot), FloatToStr(want)]));
end;

procedure TAdvChartCalendarOracleTest.SamePt(const AWhat: string;
  const AGot: TTyPointF; AWant: TJSONData);
begin
  if IsNull(AWant) then
  begin
    Inc(FCompared);
    if not (IsNan(AGot.X) and IsNan(AGot.Y)) then Miss(AWhat + ' drawn, upstream not');
    Exit;
  end;
  Same(AWhat + '.x', AGot.X, AWant.Items[0]);
  Same(AWhat + '.y', AGot.Y, AWant.Items[1]);
end;

procedure TAdvChartCalendarOracleTest.SameD(const AWhat: string; AGot,
  AWant: Double);
begin
  Inc(FCompared);
  if IsNan(AWant) and IsNan(AGot) then Exit;
  if IsNan(AWant) or IsNan(AGot) or (Bits(AGot) <> Bits(AWant)) then
    Miss(Format('%s %s, upstream %s', [AWhat, FloatToStr(AGot), FloatToStr(AWant)]));
end;

function AlignWord(A: TTyTextAnchorH): string;
begin
  case A of
    tahLeft: Result := 'left';
    tahRight: Result := 'right';
  else
    Result := 'center';
  end;
end;

function VAlignWord(A: TTyTextAnchorV): string;
begin
  case A of
    tavTop: Result := 'top';
    tavBottom: Result := 'bottom';
  else
    Result := 'middle';
  end;
end;

{ zrender's dash for a style's lineDash word or array at a width }
function WantDash(AStyle: TJSONObject): TTyDoubleArray;
var
  d: TJSONData;
  w: Double;
  i: Integer;
begin
  Result := nil;
  d := AStyle.Find('lineDash');
  w := Num(AStyle.Find('lineWidth'));
  if IsNull(d) or not (w > 0) then Exit;
  if d.JSONType = jtArray then
  begin
    SetLength(Result, d.Count);
    for i := 0 to d.Count - 1 do Result[i] := d.Items[i].AsFloat;
  end
  else if d.AsString = 'dashed' then
  begin
    SetLength(Result, 2);
    Result[0] := 4 * w;
    Result[1] := 2 * w;
  end
  else if d.AsString = 'dotted' then
  begin
    SetLength(Result, 1);
    Result[0] := w;
  end;
end;

function DashText(const A: TTyDoubleArray): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to High(A) do Result := Result + FloatToStr(A[i]) + ' ';
end;

{ a skin's ink: upstream's own 12px labels }
function TestInk: TTyCalendarInk;
begin
  Result := Default(TTyCalendarInk);
  { sentinels, so a default is seen to be the skin's and not upstream's }
  Result.CellFill := $FF0A0B0C;
  Result.CellBorder := $FF0D0E0F;
  Result.SplitLine := $FF101112;
  Result.LabelColour := $FF131415;
  Result.YearColour := $FF161718;
  Result.LabelFontSizeLogical := 12;
  Result.LabelFontWeight := 400;
  Result.YearFontName := 'sans-serif';
end;

procedure TAdvChartCalendarOracleTest.CheckCalendar(ACase, ACal: TJSONObject);
var
  spec: TTyCalendarSpec;
  cal: TTyCalendar;
  list: TTyPaintList;
  meas: ITyTextMeasurer;
  ri, dr, com, st, el, pr, lay, cc, tc: TJSONObject;
  d, xy, pts: TJSONData;
  rects, polys, texts: array of TTyChartElement;
  e: TTyChartElement;
  i, k, n, j: Integer;
  themed: Boolean;
  c: TTyChartColor;
  ms: Double;
  v: TTyDataValue;
  lay2: TTyCoordLayout;
  cell: TTyCalCellLayout;
  s, grp: string;
  want: TTyDoubleArray;
  info: TTyCalDateInfo;
  ax, ay: Double;
begin
  themed := not IsNull(ACase.Find('theme'));
  spec := TyCalendarSpecOf(FOpt, ACal.Integers['index']);
  cal := TTyCalendar.Create(spec);
  list := TTyPaintList.Create;
  meas := TFixedMeasurer.Create;
  try
    cal.UTC := True;
    cal.Resize(TyRectF(0, 0, 800, 600), 96);
    { ---- geometry ---- }
    d := ACal.Find('rect');
    Same('rect.x', cal.Rect.X, TJSONObject(d).Find('x'));
    Same('rect.y', cal.Rect.Y, TJSONObject(d).Find('y'));
    Same('rect.w', cal.Rect.W, TJSONObject(d).Find('width'));
    Same('rect.h', cal.Rect.H, TJSONObject(d).Find('height'));
    Same('cell w', cal.CellW, ACal.Arrays['cellSize'].Items[0]);
    Same('cell h', cal.CellH, ACal.Arrays['cellSize'].Items[1]);
    Same('lineWidth', cal.LineWidth, ACal.Find('lineWidth'));
    ri := TJSONObject(ACal.Find('rangeInfo'));
    Same('start', cal.Range.Start.Time, TJSONObject(ri.Find('start')).Find('time'));
    Same('end', cal.Range.Stop.Time, TJSONObject(ri.Find('end')).Find('time'));
    Same('allDay', cal.Range.AllDay, ri.Find('allDay'));
    Same('weeks', cal.Range.Weeks, ri.Find('weeks'));
    Same('nthWeek', cal.Range.NthWeek, ri.Find('nthWeek'));
    Same('fweek', cal.Range.FWeek, ri.Find('fweek'));
    Same('lweek', cal.Range.LWeek, ri.Find('lweek'));

    { ---- probes ---- }
    d := ACal.Find('probes');
    if d <> nil then
      for i := 0 to d.Count - 1 do
      begin
        pr := TJSONObject(d.Items[i]);
        v := Default(TTyDataValue);
        case pr.Find('input').JSONType of
          jtNumber: v := TyDataNum(pr.Find('input').AsFloat);
          jtString:
            begin
              v.Kind := dvkText;
              v.Text := pr.Find('input').AsString;
            end;
        end;
        s := 'probe ' + pr.Find('input').AsJSON;
        ms := cal.ParseDate(v);
        info := cal.DateInfo(ms);
        Same(s + ' time', ms, TJSONObject(pr.Find('info')).Find('time'));
        Same(s + ' day', info.Day, TJSONObject(pr.Find('info')).Find('day'));
        SamePt(s + ' point', cal.DatePoint(ms, True), pr.Find('point'));
        lay := TJSONObject(pr.Find('layout'));
        lay2 := cal.DateLayout(ms, True);
        Same(s + ' rect.x', lay2.Rect.Left, TJSONObject(lay.Find('rect')).Find('x'));
        Same(s + ' rect.y', lay2.Rect.Top, TJSONObject(lay.Find('rect')).Find('y'));
        cc := TJSONObject(lay.Find('contentRect'));
        Same(s + ' content.x', lay2.ContentRect.Left, cc.Find('x'));
        Same(s + ' content.y', lay2.ContentRect.Top, cc.Find('y'));
        { the far edges as x + width: a width read back as right - left
          loses bits, and is not a number at all where x is not }
        SameD(s + ' content.right', lay2.ContentRect.Right,
          Num(cc.Find('x')) + Num(cc.Find('width')));
        SameD(s + ' content.bottom', lay2.ContentRect.Bottom,
          Num(cc.Find('y')) + Num(cc.Find('height')));
        cell := cal.DateCell(ms, False);
        cc := TJSONObject(pr.Find('cal'));
        SamePt(s + ' centre', cell.Centre, cc.Find('center'));
        SamePt(s + ' tl', cell.TL, cc.Find('tl'));
        SamePt(s + ' tr', cell.TR, cc.Find('tr'));
        SamePt(s + ' br', cell.BR, cc.Find('br'));
        SamePt(s + ' bl', cell.BL, cc.Find('bl'));
      end;

    { ---- the picture ---- }
    TyBuildCalendar(cal, TestInk, meas, 96, list);
    rects := nil;
    polys := nil;
    texts := nil;
    for i := 0 to list.Count - 1 do
    begin
      e := list.Element(i);
      if e.Caption.Text <> '' then
      begin
        SetLength(texts, Length(texts) + 1);
        texts[High(texts)] := e;
      end
      else if e.Z2 = 20 then
      begin
        SetLength(polys, Length(polys) + 1);
        polys[High(polys)] := e;
      end
      else
      begin
        SetLength(rects, Length(rects) + 1);
        rects[High(rects)] := e;
      end;
    end;
    cc := TJSONObject(ACal.Find('counts'));
    Inc(FCompared);
    if Length(rects) <> cc.Integers['rect'] then
      Miss(Format('%d day cells, upstream %d', [Length(rects), cc.Integers['rect']]));
    Inc(FCompared);
    if Length(polys) <> cc.Integers['polyline'] then
      Miss(Format('%d lines, upstream %d', [Length(polys), cc.Integers['polyline']]));

    { the day cells: where, and how they are painted }
    dr := nil;
    if not IsNull(ACal.Find('dayRects')) then dr := TJSONObject(ACal.Find('dayRects'));
    if (dr <> nil) and (Length(rects) = cc.Integers['rect']) then
    begin
      xy := dr.Find('xy');
      com := TJSONObject(dr.Find('common'));
      st := TJSONObject(com.Find('style'));
      for i := 0 to High(rects) do
      begin
        Same(Format('cell %d x', [i]), rects[i].Shape.Bounds.Left, xy.Items[2 * i]);
        Same(Format('cell %d y', [i]), rects[i].Shape.Bounds.Top, xy.Items[2 * i + 1]);
        SameD(Format('cell %d right', [i]), rects[i].Shape.Bounds.Right,
          Num(xy.Items[2 * i]) + Num(com.Find('width')));
        if i > 3 then Break;
      end;
      for i := 0 to High(rects) do
      begin
        Inc(FCompared);
        if (Bits(rects[i].Shape.Bounds.Left) <> Bits(Num(xy.Items[2 * i])))
          or (Bits(rects[i].Shape.Bounds.Top) <> Bits(Num(xy.Items[2 * i + 1]))) then
        begin
          Miss(Format('cell %d at %s,%s, upstream %s,%s', [i,
            FloatToStr(rects[i].Shape.Bounds.Left), FloatToStr(rects[i].Shape.Bounds.Top),
            xy.Items[2 * i].AsJSON, xy.Items[2 * i + 1].AsJSON]));
          Break;
        end;
      end;
      e := rects[0];
      Same('cell border width', e.Style.StrokeWidthLogical, st.Find('lineWidth'));
      Same('cell z', e.Z, com.Find('z'));
      Same('cell z2', e.Z2, com.Find('z2'));
      if not themed then
      begin
        if st.Get('fill', '') = '#fff' then c := TestInk.CellFill
        else if not TyTryParseChartColor(st.Get('fill', ''), c) then c := 0;
        Inc(FCompared);
        if e.Style.FillColor <> c then Miss('the cell fill differs');
        if st.Get('stroke', '') = '#e8ebf0' then c := TestInk.CellBorder
        else if not TyTryParseChartColor(st.Get('stroke', ''), c) then c := 0;
        Inc(FCompared);
        if e.Style.StrokeColor <> c then Miss('the cell border differs');
      end;
      if st.Find('opacity') <> nil then Same('cell opacity', e.Style.Alpha, st.Find('opacity'));
      want := WantDash(st);
      Inc(FCompared);
      if DashText(want) <> DashText(e.Style.DashLogical) then
        Miss('cell dash ' + DashText(e.Style.DashLogical) + ', upstream ' + DashText(want));
    end;

    { the lines and the labels, in order }
    n := 0;
    k := 0;
    d := ACal.Find('elements');
    for i := 0 to d.Count - 1 do
    begin
      el := TJSONObject(d.Items[i]);
      grp := el.Get('group', '');
      if el.Get('kind', '') = 'polyline' then
      begin
        if n > High(polys) then Continue;
        e := polys[n];
        pts := el.Find('points');
        Inc(FCompared);
        if Length(e.Shape.Points) <> pts.Count then
          Miss(Format('%s line %d has %d points, upstream %d',
            [grp, n, Length(e.Shape.Points), pts.Count]))
        else
          for j := 0 to pts.Count - 1 do
            SamePt(Format('%s line %d point %d', [grp, n, j]), e.Shape.Points[j],
              pts.Items[j]);
        st := TJSONObject(el.Find('style'));
        Same(grp + ' line width', e.Style.StrokeWidthLogical, st.Find('lineWidth'));
        Same(grp + ' line z', e.Z, el.Find('z'));
        Same(grp + ' line z2', e.Z2, el.Find('z2'));
        if st.Find('opacity') <> nil then Same(grp + ' line opacity', e.Style.Alpha, st.Find('opacity'));
        if not themed then
        begin
          if st.Get('stroke', '') = '#54555a' then c := TestInk.SplitLine
          else if not TyTryParseChartColor(st.Get('stroke', ''), c) then c := 0;
          Inc(FCompared);
          if e.Style.StrokeColor <> c then Miss(grp + ' line colour differs');
        end;
        want := nil;
        if not IsNull(el.Find('dash')) then
        begin
          SetLength(want, el.Find('dash').Count);
          for j := 0 to High(want) do want[j] := el.Find('dash').Items[j].AsFloat;
        end;
        Inc(FCompared);
        if DashText(want) <> DashText(e.Style.DashLogical) then
          Miss(grp + ' line dash ' + DashText(e.Style.DashLogical) + ', upstream ' + DashText(want));
        Inc(n);
      end
      else
      begin
        { a text with no span paints nothing; the port emits nothing }
        if IsNull(el.Find('paint')) then Continue;
        { NOR ONE WHOSE ANCHOR IS NOT A NUMBER -- a month margin of '10%'.
          Upstream's span lands at y -6, off the top edge; the port does not
          draw it at all }
        ax := Num(el.Find('x'));
        if el.Find('styleX') <> nil then ax := ax + Num(el.Find('styleX'));
        ay := Num(el.Find('y'));
        if el.Find('styleY') <> nil then ay := ay + Num(el.Find('styleY'));
        if IsNan(ax) or IsNan(ay) then Continue;
        Inc(FCompared);
        if k > High(texts) then
        begin
          Miss(Format('%s "%s" not drawn', [grp, el.Get('text', '')]));
          Continue;
        end;
        e := texts[k];
        Inc(k);
        if e.Caption.Text <> el.Get('text', '') then
          Miss(Format('%s text "%s", upstream "%s"', [grp, e.Caption.Text, el.Get('text', '')]));
        ax := Num(el.Find('x'));
        if el.Find('styleX') <> nil then ax := ax + Num(el.Find('styleX'));
        ay := Num(el.Find('y'));
        if el.Find('styleY') <> nil then ay := ay + Num(el.Find('styleY'));
        SameD(grp + ' "' + el.Get('text', '') + '" x', e.Caption.X, ax);
        SameD(grp + ' "' + el.Get('text', '') + '" y', e.Caption.Y, ay);
        Same(grp + ' rotation', e.Caption.RotationRad, el.Find('rotation'));
        Inc(FCompared);
        if (AlignWord(e.Caption.AnchorH) <> el.Get('align', ''))
          or (VAlignWord(e.Caption.AnchorV) <> el.Get('verticalAlign', '')) then
          Miss(Format('%s "%s" aligned %s/%s, upstream %s/%s', [grp, el.Get('text', ''),
            AlignWord(e.Caption.AnchorH), VAlignWord(e.Caption.AnchorV),
            el.Get('align', ''), el.Get('verticalAlign', '')]));
        Same(grp + ' z', e.Z, TJSONObject(ACal.Find('textCommon')).Objects[grp].Find('z'));
        Same(grp + ' z2', e.Z2, TJSONObject(ACal.Find('textCommon')).Objects[grp].Find('z2'));
        tc := TJSONObject(TJSONObject(ACal.Find('textCommon')).Objects[grp].Find('style'));
        if (grp = 'year') or (tc.Integers['fontSize'] <> 12) then
          Same(grp + ' font size', e.Caption.FontSizeLogical, tc.Find('fontSize'));
        s := tc.Get('fontWeight', 'normal');
        if (grp = 'year') or (s <> 'normal') then
        begin
          Inc(FCompared);
          if ((s = 'bold') or (s = 'bolder')) <> (e.Caption.FontWeight >= 700) then
            Miss(grp + ' weight ' + IntToStr(e.Caption.FontWeight) + ', upstream ' + s);
        end;
        s := tc.Get('fill', '');
        if not themed then
        begin
          if s = '#86878c' then c := TestInk.YearColour
          else if s = '#54555a' then c := TestInk.LabelColour
          else if not TyTryParseChartColor(s, c) then c := 0;
          Inc(FCompared);
          if e.Caption.Colour <> c then Miss(grp + ' colour differs');
        end;
      end;
    end;
    Inc(FCompared);
    if k <> Length(texts) then
      Miss(Format('%d labels drawn, upstream %d', [Length(texts), k]));
  finally
    list.Free;
    cal.Free;
  end;
end;

procedure TAdvChartCalendarOracleTest.RunCases(AGallery: Boolean);
var
  cases, cals: TJSONData;
  cs: TJSONObject;
  i, j, ran: Integer;
begin
  cases := TJSONObject(FRoot).Find('cases');
  ran := 0;
  for i := 0 to cases.Count - 1 do
  begin
    cs := TJSONObject(cases.Items[i]);
    if (not IsNull(cs.Find('gallery'))) <> AGallery then Continue;
    FOpt.SetOptionText('{}');
    AssertTrue(cs.Strings['id'] + ' parses',
      FOpt.SetOptionText(cs.Find('option').AsJSON));
    cals := cs.Find('calendars');
    for j := 0 to cals.Count - 1 do
    begin
      FName := cs.Strings['id'] + '#' + IntToStr(j);
      CheckCalendar(cs, TJSONObject(cals.Items[j]));
    end;
    Inc(ran);
  end;
  AssertTrue(Format('cases ran (%d)', [ran]), ran > 0);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' differ from upstream:' + FReport, 0, FBad);
end;

procedure TAdvChartCalendarOracleTest.TestTheCalendarAsUpstreamLaysItOut;
begin
  RunCases(False);
end;

procedure TAdvChartCalendarOracleTest.TestTheGalleryCalendarsAsUpstream;
begin
  RunCases(True);
end;

procedure TAdvChartCalendarOracleTest.TestAHeatmapCellSitsBetweenTheDayAndTheSplitLine;
var
  spec: TTyCalendarSpec;
  cal: TTyCalendar;
  list: TTyPaintList;
  i, cells, lines: Integer;
begin
  { z 2 for everything; the order is z2: a day cell 0, a heatmap cell 1, a
    split line 20, a label 30 -- so a heatmap cell covers its day and the
    month's border still shows over it }
  FOpt.SetOptionText('{"calendar": {"range": "2017-02"}}');
  spec := TyCalendarSpecOf(FOpt, 0);
  cal := TTyCalendar.Create(spec);
  list := TTyPaintList.Create;
  try
    cal.UTC := True;
    cal.Resize(TyRectF(0, 0, 800, 600), 96);
    TyBuildCalendar(cal, TestInk, TFixedMeasurer.Create, 96, list);
    cells := 0;
    lines := 0;
    for i := 0 to list.Count - 1 do
    begin
      if list.Element(i).Caption.Text <> '' then
        AssertEquals('a label over everything', 30, list.Element(i).Z2)
      else if list.Element(i).Z2 = 0 then Inc(cells)
      else
      begin
        AssertEquals('a line over a heatmap cell', 20, list.Element(i).Z2);
        Inc(lines);
      end;
      AssertEquals('all at the calendar''s z', 2, list.Element(i).Z);
    end;
    AssertEquals('a cell a day', 28, cells);
    AssertEquals('Feb 1, Mar 1 and two edges', 4, lines);
  finally
    list.Free;
    cal.Free;
  end;
end;

procedure TAdvChartCalendarChartTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TCalProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(800, 600, BGRA(255, 255, 255, 255));
end;

procedure TAdvChartCalendarChartTest.TearDown;
begin
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartCalendarChartTest.TestACalendarWithNoSeriesIsDrawn;
var
  lst: TTyPaintList;
  k, cells, lines, names: Integer;
  e: TTyChartElement;
  cal: TTyCalendar;
begin
  { a calendar alone is a chart, the way a radar with no series is: the
    frame is what the author sees while still typing the data }
  FChart.Option := '{"calendar": {"range": "2017-02", "dayLabel": {"nameMap": "EN"}}}';
  FChart.SetBounds(0, 0, 800, 600);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
  cal := FChart.CalendarLayout(0);
  AssertNotNull('the chart laid the calendar out', cal);
  AssertTrue('on the canvas', cal.Valid);
  AssertEquals('at upstream''s default left', 80, cal.Rect.X);
  lst := FChart.List;
  cells := 0;
  lines := 0;
  names := 0;
  for k := 0 to lst.Count - 1 do
  begin
    e := lst.Element(k);
    if e.Caption.Text <> '' then Inc(names)
    else if e.Z2 = 20 then Inc(lines)
    else if e.Z2 = 0 then
    begin
      Inc(cells);
      AssertTrue('a day cell is filled with the skin''s ground',
        e.Style.HasFill and (e.Style.FillColor <> 0));
      AssertTrue('and edged', e.Style.StrokeColor <> 0);
    end;
  end;
  AssertEquals('a cell a day', 28, cells);
  AssertEquals('two month lines and two edges', 4, lines);
  AssertEquals('the year, the month and seven days', 9, names);
end;

procedure TAdvChartCalendarOracleTest.TestAFractionOfAMillisecondCarriesIntoTheNextDay;
var
  cal: TTyCalendar;
  first, second: TTyPointF;
begin
  { getDateInfo is parseDate on the instant, and a number is
    new Date(Math.round(n)): the last 0.6 ms of a day rounds into the next.
    The store keeps a timestamp's fraction, so this is the calendar's to do
    -- a heatmap row at 1485993599999.6 is drawn on 2 February. }
  FOpt.SetOptionText('{"calendar": {"range": "2017-02"}}');
  cal := TTyCalendar.Create(TyCalendarSpecOf(FOpt, 0));
  try
    cal.UTC := True;
    cal.Resize(TyRectF(0, 0, 800, 600), 96);
    first := cal.DatePoint(1485907200000, True);          // 2017-02-01T00:00Z
    second := cal.DatePoint(1485907200000 + 86399999.6, True);
    AssertEquals('the next day''s row', first.Y + cal.CellH, second.Y);
    AssertEquals('0.6 ms short of midnight is still the first',
      first.Y, cal.DatePoint(1485907200000 + 86399999.4, True).Y);
    { AND THE CLAMP SEES THE ROUNDED INSTANT: 0.4 ms before the range starts
      rounds onto its first millisecond, which is inside }
    AssertFalse('rounded into the range',
      IsNan(cal.DatePoint(1485907200000 - 0.4, True).Y));
    AssertEquals('onto its first day', first.Y,
      cal.DatePoint(1485907200000 - 0.4, True).Y);
  finally
    cal.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartCalendarOracleTest);
  RegisterTest(TAdvChartCalendarChartTest);
end.
