unit test.advchart.seriestext;
{$mode objfpc}{$H+}
{ The TEXT a series puts on the screen -- its labels and its tooltips -- held
  to upstream's own.

  tools/advchart-oracle/series-text.js runs the real ECharts 6.1 build and
  records, in tests/fixtures/advchart-series-text.json:
    labels    every label drawn on every item, per series type;
    tooltips  every line of an item or an axis tooltip as zrender lays it out
              (the real TooltipView, in richText mode), and the plain text a
              formatter template comes to;
    gauge     a dial's titles, values and axis labels.
  Cases marked deferred need what this port does not keep yet -- the RAW
  option value ('12.50' as written, an array's c) or a tooltip layout it does
  not build (sub-rows) -- and are skipped here, recorded for the batch that
  takes them on. Every string is compared exactly, and once more with the
  machine's decimal separator set to a comma. }
interface
uses Classes, SysUtils, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Scale, tyControls.AdvChart.Coord,
     tyControls.AdvChart.Builder, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Handlers, tyControls.AdvChart.Tooltip,
     tyControls.AdvanceChart;
type
  TSeriesTextProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    function ItemContent(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
    function ItemParams(const ADatum: TTyChartDatumRef): TTyChartCallbackParams;
    function ItemSpec(const ADatum: TTyChartDatumRef): TTyTooltipSpec;
    function Pointers(AX, AY: Integer): TTyAxisHitArray;
    function AxisContent(const AHits: TTyAxisHitArray;
      const ASpec: TTyTooltipSpec): TTyTooltipBlock;
    function AxisParams(const AHits: TTyAxisHitArray): TTyChartParams;
  end;

  TAdvChartSeriesTextOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TSeriesTextProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad: Integer;
    FCompared: Integer;
    FReport: string;
    procedure SetUp; override;
    procedure TearDown; override;
    function Section(const AName: string): TJSONArray;
    procedure DrawCase(ACase: TJSONObject);
    procedure Miss(ACase: TJSONObject; const AWhat: string);
    procedure CheckLabels;
    procedure CheckTooltips;
    procedure CheckGauges;
    procedure Verdict(AMinimum: Integer);
  published
    procedure TestLabels;
    procedure TestTooltips;
    procedure TestGauges;
    procedure TestNoneOfItFollowsTheLocale;
  end;

implementation

{ ==================== the probe ==================== }

procedure TSeriesTextProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TSeriesTextProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TSeriesTextProbe.ItemContent(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
begin
  Result := TooltipContent(ADatum, TooltipSpecFor(ADatum));
end;

function TSeriesTextProbe.ItemParams(const ADatum: TTyChartDatumRef): TTyChartCallbackParams;
begin
  Result := TooltipParams(ADatum);
end;

function TSeriesTextProbe.ItemSpec(const ADatum: TTyChartDatumRef): TTyTooltipSpec;
begin
  Result := TooltipSpecFor(ADatum);
end;

function TSeriesTextProbe.Pointers(AX, AY: Integer): TTyAxisHitArray;
begin
  Result := ResolveAxisPointers(AX, AY);
end;

function TSeriesTextProbe.AxisContent(const AHits: TTyAxisHitArray;
  const ASpec: TTyTooltipSpec): TTyTooltipBlock;
begin
  Result := AxisTooltipContent(AHits, ASpec);
end;

function TSeriesTextProbe.AxisParams(const AHits: TTyAxisHitArray): TTyChartParams;
begin
  Result := AxisTooltipParams(AHits);
end;

{ ==================== plumbing ==================== }

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-series-text.json';
end;

function IsDeferred(ACase: TJSONObject): Boolean;
begin
  Result := (ACase.Find('deferred') <> nil) and ACase.Booleans['deferred'];
end;

{ THE AUTO SERIES NAME CARRIES A NUL (`series\u00000`), and fpjson's
  scanner drops a `\u0000` -- it takes it for the first half of a surrogate
  pair. So the fixture's text has its NULs turned into U+0001 before it is
  parsed, and every text the port produces goes through this before it is
  compared: the NUL is still compared, as that stand-in. }
function Nul(const AText: string): string;
begin
  Result := StringReplace(AText, #0, #1, [rfReplaceAll]);
end;

{ A JSON string or null, as the fixture writes a line's fields. }
function StrOrNull(AData: TJSONData; out AIsNull: Boolean): string;
begin
  AIsNull := (AData = nil) or (AData.JSONType = jtNull);
  if AIsNull then Result := '' else Result := AData.AsString;
end;

{ The block tree as the lines zrender lays out: a shown header is a line of
  its own, and every name-value row one line, name and value absent where the
  row has none. Written as 'marker|name|value', '~' for an absent field. }
procedure Flatten(ABlock: TTyTooltipBlock; AOut: TStrings);
var i: Integer; m, n, v: string;
begin
  if ABlock = nil then Exit;
  if ABlock.IsSection then
  begin
    if not ABlock.NoHeader then AOut.Add('~|' + Nul(ABlock.Header) + '|~');
    for i := 0 to ABlock.BlockCount - 1 do Flatten(ABlock.Blocks[i], AOut);
    Exit;
  end;
  case ABlock.Marker of
    ttmItem: m := 'item';
    ttmSubItem: m := 'subItem';
  else
    m := '~';
  end;
  if ABlock.NoName then n := '~' else n := ABlock.Name;
  if ABlock.NoValue then v := '~' else v := ABlock.Value;
  AOut.Add(m + '|' + Nul(n) + '|' + Nul(v));
end;

procedure TAdvChartSeriesTextOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TSeriesTextProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(StringReplace(sl.Text, '\u0000', '\u0001', [rfReplaceAll]));
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartSeriesTextOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  FreeAndNil(FBmp);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

function TAdvChartSeriesTextOracleTest.Section(const AName: string): TJSONArray;
begin
  Result := TJSONObject(FRoot).Arrays[AName];
end;

procedure TAdvChartSeriesTextOracleTest.DrawCase(ACase: TJSONObject);
begin
  FChart.Option := ACase.Objects['option'].AsJSON;
  AssertEquals(ACase.Strings['name'] + ' parses', '', FChart.OptionError);
  FChart.SetBounds(0, 0, 600, 400);
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
end;

procedure TAdvChartSeriesTextOracleTest.Miss(ACase: TJSONObject; const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 24 then
    FReport := FReport + LineEnding + '  ' + ACase.Strings['name'] + ': ' + AWhat;
end;

procedure TAdvChartSeriesTextOracleTest.Verdict(AMinimum: Integer);
begin
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared >= AMinimum);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
end;

{ ==================== labels ==================== }

procedure TAdvChartSeriesTextOracleTest.CheckLabels;
var
  cases, series, items, texts: TJSONArray;
  cs, ser, item: TJSONObject;
  c, s, k, i, si, raw: Integer;
  want, got: TStringList;
  e: TTyChartElement;
  lst: TTyPaintList;
begin
  want := TStringList.Create;
  got := TStringList.Create;
  try
    cases := Section('labels');
    for c := 0 to cases.Count - 1 do
    begin
      cs := cases.Objects[c];
      if IsDeferred(cs) then Continue;
      DrawCase(cs);
      lst := FChart.List;
      series := cs.Arrays['series'];
      for s := 0 to series.Count - 1 do
      begin
        ser := series.Objects[s];
        si := ser.Integers['seriesIndex'];
        items := ser.Arrays['items'];
        for k := 0 to items.Count - 1 do
        begin
          item := items.Objects[k];
          raw := item.Integers['dataIndex'];
          { the non-empty texts: an empty label and no label look alike on a
            screen, and the port draws neither }
          want.Clear;
          if item.Booleans['drawn'] then
          begin
            texts := item.Arrays['texts'];
            for i := 0 to texts.Count - 1 do
              if texts.Strings[i] <> '' then want.Add(texts.Strings[i]);
          end;
          got.Clear;
          if lst <> nil then
            for i := 0 to lst.Count - 1 do
            begin
              e := lst.Element(i);
              if e.Datum.IsEdge then Continue;
              if e.Datum.SeriesIndex <> si then Continue;
              if e.Datum.RawDataIndex <> raw then Continue;
              { the ANSWER, the words as drawn: a mark's own caption with no
                size is the label pass' request, not a second label }
              if (e.Caption.Text = '') or (e.Caption.FontSizeLogical <= 0) then
                Continue;
              got.Add(Nul(e.Caption.Text));
            end;
          Inc(FCompared);
          if want.Text <> got.Text then
            Miss(cs, Format('series %d item %d: [%s] upstream, [%s] here',
              [si, raw, Trim(StringReplace(want.Text, LineEnding, ' | ', [rfReplaceAll])),
               Trim(StringReplace(got.Text, LineEnding, ' | ', [rfReplaceAll]))]));
        end;
      end;
    end;
  finally
    want.Free;
    got.Free;
  end;
end;

{ ==================== tooltips ==================== }

procedure TAdvChartSeriesTextOracleTest.CheckTooltips;
var
  cases, lines: TJSONArray;
  cs, ln, edge: TJSONObject;
  c, i, si, raw, ordinal, x, y: Integer;
  want, got: TStringList;
  e: TTyChartElement;
  lst: TTyPaintList;
  datum: TTyChartDatumRef;
  found: Boolean;
  block: TTyTooltipBlock;
  hits: TTyAxisHitArray;
  ax: TTyAxis;
  r: TTyRectF;
  spec: TTyTooltipSpec;
  params: TTyChartParams;
  opt: TTyChartOption;
  text, cat, m, n, v: string;
  isNull: Boolean;
begin
  want := TStringList.Create;
  got := TStringList.Create;
  try
    cases := Section('tooltips');
    for c := 0 to cases.Count - 1 do
    begin
      cs := cases.Objects[c];
      if IsDeferred(cs) then Continue;
      DrawCase(cs);
      block := nil;
      params := nil;
      spec := TyTooltipSpecDefault;

      if cs.Strings['trigger'] = 'axis' then
      begin
        { THE REAL HOVER: over the category, at mid-plot. }
        ax := FChart.Build.Grid(0).XAxis(0);
        cat := cs.Strings['category'];
        ordinal := -1;
        if ax.Scale is TTyOrdinalScale then
          for i := 0 to TTyOrdinalScale(ax.Scale).CategoryCount - 1 do
            if TTyOrdinalScale(ax.Scale).GetLabel(i) = cat then ordinal := i;
        if ordinal < 0 then
        begin
          Miss(cs, 'no category ' + cat);
          Continue;
        end;
        r := FChart.Build.Grid(0).PlotRect;
        x := Round(ax.DataToCoord(ordinal));
        y := Round((r.Top + r.Bottom) / 2);
        hits := FChart.Pointers(x, y);
        opt := TTyChartOption.Create;
        try
          opt.SetOptionText(cs.Objects['option'].AsJSON);
          spec := TyTooltipSpecOf(opt, -1, -1);
        finally
          opt.Free;
        end;
        if spec.Formatter <> '' then params := FChart.AxisParams(hits)
        else block := FChart.AxisContent(hits, spec);
      end
      else
      begin
        { THE ITEM'S OWN DATUM, from the element drawn for it -- which carries
          the view row the store is asked with. }
        found := False;
        lst := FChart.List;
        if cs.Find('edge') is TJSONObject then
        begin
          edge := cs.Objects['edge'];
          datum := TyChartEdgeDatum(edge.Integers['seriesIndex'], edge.Integers['edgeIndex']);
          found := True;
        end
        else
        begin
          si := cs.Integers['seriesIndex'];
          raw := cs.Integers['dataIndex'];
          if lst <> nil then
            for i := 0 to lst.Count - 1 do
            begin
              e := lst.Element(i);
              if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si)
                or (e.Datum.RawDataIndex <> raw) or (e.Datum.DataIndex < 0) then
                Continue;
              datum := e.Datum;
              found := True;
              Break;
            end;
        end;
        if not found then
        begin
          Miss(cs, 'no element for the item');
          Continue;
        end;
        spec := FChart.ItemSpec(datum);
        if spec.Formatter <> '' then
        begin
          SetLength(params, 1);
          params[0] := FChart.ItemParams(datum);
        end
        else
          block := FChart.ItemContent(datum);
      end;

      Inc(FCompared);
      if spec.Formatter <> '' then
      begin
        { A TEMPLATE: the text a reader sees, entities decoded. }
        TyChartResolveText(spec.Formatter, params, text);
        text := Nul(text);
        if text <> cs.Strings['visible'] then
          Miss(cs, Format('"%s" upstream, "%s" here', [cs.Strings['visible'], text]));
        Continue;
      end;
      want.Clear;
      lines := cs.Arrays['lines'];
      for i := 0 to lines.Count - 1 do
      begin
        ln := lines.Objects[i];
        m := StrOrNull(ln.Find('marker'), isNull);
        if isNull then m := '~';
        n := StrOrNull(ln.Find('name'), isNull);
        if isNull then n := '~';
        v := StrOrNull(ln.Find('value'), isNull);
        if isNull then v := '~';
        want.Add(m + '|' + n + '|' + v);
      end;
      got.Clear;
      try
        Flatten(block, got);
      finally
        block.Free;
      end;
      if want.Text <> got.Text then
        Miss(cs, Format('[%s] upstream, [%s] here',
          [Trim(StringReplace(want.Text, LineEnding, ' / ', [rfReplaceAll])),
           Trim(StringReplace(got.Text, LineEnding, ' / ', [rfReplaceAll]))]));
    end;
  finally
    want.Free;
    got.Free;
  end;
end;

{ ==================== gauge ==================== }

procedure TAdvChartSeriesTextOracleTest.CheckGauges;
var
  cases, arr: TJSONArray;
  cs: TJSONObject;
  c, i, k: Integer;
  want, got: TStringList;
  lst: TTyPaintList;
const
  cParts: array[0..2] of string = ('titles', 'details', 'axisLabels');
begin
  want := TStringList.Create;
  got := TStringList.Create;
  try
    want.Sorted := True;
    want.Duplicates := dupAccept;
    got.Sorted := True;
    got.Duplicates := dupAccept;
    cases := Section('gauge');
    for c := 0 to cases.Count - 1 do
    begin
      cs := cases.Objects[c];
      if IsDeferred(cs) then Continue;
      DrawCase(cs);
      { EVERY WORD ON THE DIAL, as a multiset: which caption is a title and
        which a tick is the layout's business; what each one SAYS is this
        test's. }
      want.Clear;
      for k := 0 to High(cParts) do
      begin
        arr := cs.Arrays[cParts[k]];
        for i := 0 to arr.Count - 1 do
          if arr.Strings[i] <> '' then want.Add(arr.Strings[i]);
      end;
      got.Clear;
      lst := FChart.List;
      if lst <> nil then
        for i := 0 to lst.Count - 1 do
          if (lst.Element(i).Caption.Text <> '')
            and (lst.Element(i).Caption.FontSizeLogical > 0) then
            got.Add(Nul(lst.Element(i).Caption.Text));
      Inc(FCompared);
      if want.Text <> got.Text then
        Miss(cs, Format('[%s] upstream, [%s] here',
          [Trim(StringReplace(want.Text, LineEnding, ' ', [rfReplaceAll])),
           Trim(StringReplace(got.Text, LineEnding, ' ', [rfReplaceAll]))]));
    end;
  finally
    want.Free;
    got.Free;
  end;
end;

procedure TAdvChartSeriesTextOracleTest.TestLabels;
begin
  CheckLabels;
  Verdict(365);
end;

procedure TAdvChartSeriesTextOracleTest.TestTooltips;
begin
  CheckTooltips;
  Verdict(117);
end;

procedure TAdvChartSeriesTextOracleTest.TestGauges;
begin
  CheckGauges;
  Verdict(14);
end;

procedure TAdvChartSeriesTextOracleTest.TestNoneOfItFollowsTheLocale;
var saved: TFormatSettings;
begin
  saved := DefaultFormatSettings;
  try
    DefaultFormatSettings.DecimalSeparator := ',';
    DefaultFormatSettings.ThousandSeparator := '.';
    CheckLabels;
    CheckTooltips;
    CheckGauges;
  finally
    DefaultFormatSettings := saved;
  end;
  Verdict(496);
end;

initialization
  RegisterTest(TAdvChartSeriesTextOracleTest);
end.
