unit test.advchart.cursor;
{$mode objfpc}{$H+}
{ [F6a] THE CHART'S CURSOR AND ITS PICTURES, held to upstream.

  tools/advchart-oracle/cursor.js drives zrender's Handler over the real
  ECharts 6.1 build and records the cursor the canvas holds after every
  pointer step (the hovered element's own, the RoamControllers' grab /
  grabbing, ...), and where every `image://` picture lands once a browser
  would have loaded it. TAdvChartCursorOracleTest replays the steps through
  the control's own MouseMove / MouseDown / MouseUp and compares CursorName
  and the control's Cursor (TyChartCssCursor of the name, the host's own for
  'default'); it builds the picture cases twice -- with the data URLs, and
  with every picture an image of a TImageList instead (registered by name,
  or found on the chart's Owner) -- and compares every picture's four
  corners.

  TAdvChartImageListTest: the image list's lookup (the registry, the
  Owner, a freed list), the resolution for the pixels drawn, the natural
  size, pixels actually drawn, the CSS-to-LCL table and the host's cursor. }
interface

uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, ImgList, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Measure, tyControls.AdvChart.Geo, tyControls.AdvChart.Images,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;

type
  TCurProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Move(AX, AY: Integer);
    procedure Down(AX, AY: Integer);
    procedure Up(AX, AY: Integer);
    procedure Leave;
    function List: TTyPaintList;
  end;

  TAdvChartCursorOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TCurProbe;
    FRoot: TJSONData;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FWide, FTall: TImageList;
    FBad, FCompared: Integer;
    FReport: string;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure NewChart;
    procedure Miss(const AWhat: string);
    function ListOf(const AKey: string; W, H: Integer): TImageList;
    procedure Pictures(AWithLists: Boolean);
  published
    procedure TestCursorsAsUpstream;
    procedure TestPicturesFromDataUrlsAsUpstream;
    procedure TestPicturesFromImageListsAsUpstream;
  end;

  TAdvChartImageListTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TCurProbe;
    FBmp, FPix: TBGRABitmap;
    procedure SetUp; override;
    procedure TearDown; override;
    function NewOwnedChart(AOwner: TComponent): TCurProbe;
    procedure ShowOn(AChart: TCurProbe; const AOption: string);
    function SolidList(AOwner: TComponent; const AName: string; W, H: Integer;
      AColor: TColor): TImageList;
    procedure Show(const AOption: string);
    function Px(X, Y: Integer): TBGRAPixel;
  published
    procedure TestTheReferenceIsANameAndAnIndex;
    procedure TestTheRegistryThenTheOwner;
    procedure TestAFreedListIsForgotten;
    procedure TestTheResolutionCoversTheDevicePixels;
    procedure TestASymbolPictureIsDrawn;
    procedure TestAnOwnerListIsFoundAndAStrangersIsNot;
    procedure TestAPatternTakesAListImage;
    procedure TestAnAxisArrowPictureIsDrawn;
    procedure TestALargeBatchDrawsNoPicture;
    procedure TestTheCssTable;
    procedure TestTheHostsCursorComesBack;
    procedure TestAHostCursorSetMeanwhileIsKept;
  end;

implementation

{ ==================== the probe ==================== }

procedure TCurProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TCurProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TCurProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TCurProbe.Down(AX, AY: Integer);
begin
  MouseDown(mbLeft, [ssLeft], AX, AY);
end;

procedure TCurProbe.Up(AX, AY: Integer);
begin
  MouseUp(mbLeft, [], AX, AY);
end;

procedure TCurProbe.Leave;
begin
  MouseLeave;
end;

function TCurProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixtureText(const AName: string): string;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName);
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

{ a picture as a TBitmap of its own size, decoded from its data URL }
function DataBitmap(const AUrl: string): TBitmap;
var
  b: TBGRABitmap;
  nw, nh: Double;
begin
  b := TyChartImage(AUrl, 0, nw, nh);
  if b = nil then Exit(nil);
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(b.Width, b.Height);
  Result.Canvas.Draw(0, 0, b.Bitmap);
end;

{ ==================== the oracle ==================== }

procedure TAdvChartCursorOracleTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  FRoot := GetJSON(FixtureText('advchart-cursor.json'));
  FMeasure := GetJSON(FixtureText('advchart-text-style.json'));
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartCursorOracleTest.TearDown;
begin
  TyChartUnregisterImageList('cursorWide');
  TyChartUnregisterImageList('cursorTall');
  FreeAndNil(FWide);
  FreeAndNil(FTall);
  FRoot.Free;
  FMeasure.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  TyChartClearMaps;
  inherited TearDown;
end;

procedure TAdvChartCursorOracleTest.NewChart;
begin
  FreeAndNil(FChart);
  FChart := TCurProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.AnimationMode := camOff;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.SetBounds(0, 0, 600, 400);
end;

procedure TAdvChartCursorOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 6000 then FReport := FReport + LineEnding + AWhat;
end;

procedure TAdvChartCursorOracleTest.TestCursorsAsUpstream;
var
  cases, steps, maps: TJSONArray;
  cs, st: TJSONObject;
  c, s, i: Integer;
  kind, want: string;
  x, y: Integer;
  lcl: TCursor;
begin
  maps := TJSONObject(FRoot).Arrays['maps'];
  for i := 0 to maps.Count - 1 do
    AssertTrue('the map', TyChartRegisterMap(maps.Objects[i].Strings['name'],
      maps.Objects[i].Strings['text']));
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    NewChart;
    FChart.Option := cs.Objects['option'].AsJSON;
    FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
    steps := cs.Arrays['steps'];
    for s := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[s];
      kind := st.Strings['type'];
      x := st.Integers['x'];
      y := st.Integers['y'];
      if kind = 'move' then FChart.Move(x, y)
      else if kind = 'down' then FChart.Down(x, y)
      else FChart.Up(x, y);
      FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
      want := st.Strings['cursor'];
      Inc(FCompared);
      if FChart.CursorName <> want then
        Miss(Format('%s step %d (%s %d,%d, %s): cursor %s upstream, %s here', [cs.Strings['id'], s,
          kind, x, y, st.Strings['aim'], want, FChart.CursorName]));
      { the control's own: the table's, the host's for 'default' }
      if not TyChartCssCursor(want, lcl) then lcl := crDefault;
      Inc(FCompared);
      if FChart.Cursor <> lcl then
        Miss(Format('%s step %d: the control''s Cursor %d, %d for %s', [cs.Strings['id'], s,
          FChart.Cursor, lcl, want]));
    end;
  end;
  AssertTrue(Format('%d of %d comparisons differ:%s', [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('only %d compared', [FCompared]), FCompared >= 200);
end;

function TAdvChartCursorOracleTest.ListOf(const AKey: string; W, H: Integer): TImageList;
var bmp: TBitmap;
begin
  Result := TImageList.Create(nil);
  Result.Width := W;
  Result.Height := H;
  bmp := DataBitmap(TJSONObject(FRoot).Objects['images'].Objects[AKey].Strings['url']);
  try
    AssertNotNull('the picture decodes', bmp);
    Result.Add(bmp, nil);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartCursorOracleTest.Pictures(AWithLists: Boolean);
var
  pics, ims, corners: TJSONArray;
  pc, im: TJSONObject;
  p, i, j, k, q, found, sx, sy: Integer;
  opt, src, key, urlW, urlT: string;
  L: TTyPaintList;
  el: TTyChartElement;
  used: array of Boolean;
  ok, listed: Boolean;
  px, py, u, v, nw, nh: Double;
  cx, cy: array[0..3] of Double;
  pix: TBGRABitmap;
  c: TBGRAPixel;

  function KeyOf(const ASrc: string): string;
  var s: string;
  begin
    s := ASrc;
    if Copy(s, 1, 8) = 'image://' then Delete(s, 1, 8);
    if (s = urlW) or (s = 'cursorWide/0') then Result := 'wide'
    else if (s = urlT) or (s = 'cursorTall/0') then Result := 'tall'
    else Result := '?' + Copy(s, 1, 20);
  end;

  function Hex(AData: TJSONData): Double;
  var
    w: QWord;
  begin
    w := StrToQWord('$' + AData.AsString);
    System.Move(w, Result, 8);
  end;

  { the picture's own colour at (AU, AV) of its pixels: the wide one red
    left of 10, blue right; the tall one green above 8, black below --
    over white, through the scatter's 0.8 }
  function Looks(const AKey: string; AU, AV: Double; const AC: TBGRAPixel): Boolean;
  begin
    if AKey = 'wide' then
    begin
      if AU < 10 then Result := (AC.red > AC.green + 100) and (AC.red > AC.blue + 100)
      else Result := (AC.blue > AC.red + 100) and (AC.blue > AC.green + 100);
    end
    else
    begin
      if AV < 8 then Result := (AC.green > AC.red + 60) and (AC.green > AC.blue + 60)
      else Result := (AC.red < 110) and (AC.green < 110) and (AC.blue < 110);
    end;
  end;

begin
  urlW := TJSONObject(FRoot).Objects['images'].Objects['wide'].Strings['url'];
  urlT := TJSONObject(FRoot).Objects['images'].Objects['tall'].Strings['url'];
  if AWithLists then
  begin
    FWide := ListOf('wide', 20, 10);
    FTall := ListOf('tall', 8, 16);
    TyChartRegisterImageList('cursorWide', FWide);
    TyChartRegisterImageList('cursorTall', FTall);
  end;
  pics := TJSONObject(FRoot).Arrays['pictures'];
  for p := 0 to pics.Count - 1 do
  begin
    pc := pics.Objects[p];
    opt := pc.Objects['option'].AsJSON;
    if AWithLists then
    begin
      { a symbol's `image://<data URL>` the list's `image://name/0`; a
        graphic image's bare data URL its bare `name/0` }
      opt := StringReplace(opt, urlW, 'cursorWide/0', [rfReplaceAll]);
      opt := StringReplace(opt, urlT, 'cursorTall/0', [rfReplaceAll]);
    end;
    NewChart;
    FChart.Option := opt;
    pix := FChart.RenderToBitmap('{"backgroundColor":"#ffffff"}');
    try
      FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
      L := FChart.List;
      AssertNotNull(pc.Strings['id'] + ': a list', L);
      { an axis arrow is painted with the axes, not from the list: its
        pixels alone }
      listed := pc.Strings['id'] <> 'axis-arrow';
      ims := pc.Arrays['images'];
      SetLength(used, L.Count);
      for k := 0 to High(used) do used[k] := False;
      for i := 0 to ims.Count - 1 do
      begin
        im := ims.Objects[i];
        corners := im.Arrays['corners'];
        for q := 0 to 3 do
        begin
          cx[q] := Hex(corners.Arrays[q].Items[0]);
          cy[q] := Hex(corners.Arrays[q].Items[1]);
        end;
        { THE PIXELS: four points inside the picture, mapped through its
          corners, the picture's own colour there }
        if im.Strings['image'] = 'wide' then
        begin
          nw := 20;
          nh := 10;
        end
        else
        begin
          nw := 8;
          nh := 16;
        end;
        for sy := 0 to 1 do
          for sx := 0 to 1 do
          begin
            u := nw * (0.25 + 0.5 * sx);
            v := nh * (0.25 + 0.5 * sy);
            px := cx[0] + (cx[1] - cx[0]) * u / nw + (cx[3] - cx[0]) * v / nh;
            py := cy[0] + (cy[1] - cy[0]) * u / nw + (cy[3] - cy[0]) * v / nh;
            c := pix.GetPixel(Floor(px), Floor(py));
            Inc(FCompared);
            if not Looks(im.Strings['image'], u, v, c) then
              Miss(Format('%s image %d (%s): at %.1f,%.1f (its %.1f,%.1f) the pixel is %d,%d,%d',
                [pc.Strings['id'], i, im.Strings['image'], px, py, u, v, c.red, c.green, c.blue]));
          end;
        if not listed then Continue;
        { THE CORNERS: an element of the list drawing that picture there }
        found := -1;
        for k := 0 to L.Count - 1 do
        begin
          if used[k] then Continue;
          el := L.Element(k);
          if el.Ignore then Continue;
          if el.Shape.Image <> '' then src := el.Shape.Image
          else if el.Style.FillPattern.Present and el.Style.FillPattern.UnitImage then
            src := el.Style.FillPattern.Image
          else Continue;
          key := KeyOf(src);
          if key <> im.Strings['image'] then Continue;
          if Length(el.Shape.Points) <> 4 then Continue;
          ok := True;
          for q := 0 to 3 do
            if (Abs(el.Shape.Points[q].X - cx[q]) > 1e-4) or (Abs(el.Shape.Points[q].Y - cy[q]) > 1e-4) then
              ok := False;
          if ok then
          begin
            found := k;
            Break;
          end;
        end;
        Inc(FCompared);
        if found < 0 then
        begin
          { what the port has, for the report }
          src := '';
          for k := 0 to L.Count - 1 do
          begin
            el := L.Element(k);
            if (el.Shape.Image = '') and not (el.Style.FillPattern.Present and el.Style.FillPattern.UnitImage) then Continue;
            src := src + ' [';
            for j := 0 to High(el.Shape.Points) do
              src := src + Format('(%.4f,%.4f)', [el.Shape.Points[j].X, el.Shape.Points[j].Y]);
            src := src + ']';
          end;
          Miss(Format('%s image %d (%s) at %s: none here like it; here:%s', [pc.Strings['id'], i,
            im.Strings['image'], im.Arrays['cornersText'].AsJSON, src]));
        end
        else
          used[found] := True;
      end;
    finally
      pix.Free;
    end;
  end;
  AssertTrue(Format('%d of %d comparisons differ:%s', [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('only %d compared', [FCompared]), FCompared >= 120);
end;

procedure TAdvChartCursorOracleTest.TestPicturesFromDataUrlsAsUpstream;
begin
  Pictures(False);
end;

procedure TAdvChartCursorOracleTest.TestPicturesFromImageListsAsUpstream;
begin
  Pictures(True);
end;

{ ==================== the image lists ==================== }

procedure TAdvChartImageListTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TCurProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, 300, 200);
  FBmp := TBGRABitmap.Create(300, 200, BGRA(255, 255, 255, 255));
end;

procedure TAdvChartImageListTest.TearDown;
begin
  FPix.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

function TAdvChartImageListTest.SolidList(AOwner: TComponent; const AName: string;
  W, H: Integer; AColor: TColor): TImageList;
var bmp: TBitmap;
begin
  Result := TImageList.Create(AOwner);
  if AName <> '' then Result.Name := AName;
  Result.Width := W;
  Result.Height := H;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(W, H);
    bmp.Canvas.Brush.Color := AColor;
    bmp.Canvas.FillRect(0, 0, W, H);
    Result.Add(bmp, nil);
  finally
    bmp.Free;
  end;
end;

function TAdvChartImageListTest.NewOwnedChart(AOwner: TComponent): TCurProbe;
begin
  Result := TCurProbe.Create(AOwner);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.AnimationMode := camOff;
  Result.SetBounds(0, 0, 300, 200);
end;

{ the option, a render on a canvas (what the pointer then hits) and the
  picture as an export on white (what the pixels are read from) }
procedure TAdvChartImageListTest.ShowOn(AChart: TCurProbe; const AOption: string);
begin
  AChart.Option := AOption;
  FreeAndNil(FPix);
  FPix := AChart.RenderToBitmap('{"backgroundColor":"#ffffff"}');
  AChart.Render(FBmp.Canvas, Rect(0, 0, 300, 200), 96);
end;

procedure TAdvChartImageListTest.Show(const AOption: string);
begin
  ShowOn(FChart, AOption);
end;

function TAdvChartImageListTest.Px(X, Y: Integer): TBGRAPixel;
begin
  Result := FPix.GetPixel(X, Y);
end;

procedure TAdvChartImageListTest.TestTheReferenceIsANameAndAnIndex;
var nm: string; idx: Integer;
begin
  AssertTrue('prefixed', TyChartImageListRef('image://mapList/12', nm, idx));
  AssertEquals('mapList', nm);
  AssertEquals(12, idx);
  AssertTrue('bare', TyChartImageListRef('_l2/0', nm, idx));
  AssertEquals('_l2', nm);
  AssertFalse('a data URL', TyChartImageListRef('image://data:image/png;base64,AAAA', nm, idx));
  AssertFalse('an http URL', TyChartImageListRef('image://http://x/1', nm, idx));
  AssertFalse('a digit first', TyChartImageListRef('1list/0', nm, idx));
  AssertFalse('no index', TyChartImageListRef('list/', nm, idx));
  AssertFalse('a negative index', TyChartImageListRef('list/-1', nm, idx));
  AssertFalse('two slashes', TyChartImageListRef('a/b/1', nm, idx));
end;

procedure TAdvChartImageListTest.TestTheRegistryThenTheOwner;
var
  reg, own: TImageList;
  w, h: Double;
  prev: TComponent;
begin
  reg := SolidList(nil, '', 12, 6, clRed);
  own := SolidList(FForm, 'twoNames', 10, 10, clBlue);
  try
    { the owner's, in its scope only }
    AssertFalse('no scope, no owner', TyChartImageSize('image://twoNames/0', w, h));
    prev := TyChartImageScopeEnter(FForm);
    try
      AssertTrue('the owner''s', TyChartImageSize('image://twoNames/0', w, h));
      AssertEquals(10, w, 0);
      { the registry first }
      TyChartRegisterImageList('twoNames', reg);
      AssertTrue('the registered', TyChartImageSize('image://twoNames/0', w, h));
      AssertEquals('the registered one''s width', 12, w, 0);
      AssertEquals(6, h, 0);
      AssertTrue('case-insensitive', TyChartImageSize('image://TWONAMES/0', w, h));
      AssertFalse('an index past the end', TyChartImageSize('image://twoNames/1', w, h));
      TyChartUnregisterImageList('twoNames');
      AssertTrue('the owner''s again', TyChartImageSize('image://twoNames/0', w, h));
      AssertEquals(10, w, 0);
    finally
      TyChartImageScopeLeave(prev);
    end;
  finally
    TyChartUnregisterImageList('twoNames');
    reg.Free;
  end;
end;

procedure TAdvChartImageListTest.TestAFreedListIsForgotten;
var
  L: TImageList;
  w, h: Double;
begin
  L := SolidList(nil, '', 8, 8, clGreen);
  TyChartRegisterImageList('soonGone', L);
  AssertTrue('registered', TyChartImageSize('soonGone/0', w, h));
  AssertNotNull('a bitmap', TyChartImage('soonGone/0', 8, w, h));
  L.Free;
  AssertNull('freed: unregistered', TyChartRegisteredImageList('soonGone'));
  AssertFalse('freed: no picture', TyChartImageSize('soonGone/0', w, h));
end;

procedure TAdvChartImageListTest.TestTheResolutionCoversTheDevicePixels;
var
  L: TImageList;
  b16, b32: TBitmap;
  bmp: TBGRABitmap;
  w, h: Double;
begin
  L := TImageList.Create(nil);
  b16 := TBitmap.Create;
  b32 := TBitmap.Create;
  try
    L.Scaled := True;
    L.Width := 16;
    L.Height := 16;
    L.RegisterResolutions([16, 32]);
    b16.PixelFormat := pf24bit;
    b16.SetSize(16, 16);
    b16.Canvas.Brush.Color := clRed;
    b16.Canvas.FillRect(0, 0, 16, 16);
    b32.PixelFormat := pf24bit;
    b32.SetSize(32, 32);
    b32.Canvas.Brush.Color := clBlue;
    b32.Canvas.FillRect(0, 0, 32, 32);
    L.AddMultipleResolutions([TCustomBitmap(b16), TCustomBitmap(b32)]);
    TyChartRegisterImageList('twoSizes', L);
    bmp := TyChartImage('image://twoSizes/0', 16, w, h);
    AssertEquals('16 px: the 16', 16, bmp.Width);
    AssertEquals('the natural size is the list''s', 16, w, 0);
    bmp := TyChartImage('image://twoSizes/0', 24, w, h);
    AssertEquals('24 px: the 32 covers it', 32, bmp.Width);
    AssertEquals('still the natural 16', 16, w, 0);
    AssertTrue('the 32''s own pixels', bmp.GetPixel(5, 5).blue > 200);
    bmp := TyChartImage('image://twoSizes/0', 100, w, h);
    AssertEquals('past the widest: the widest', 32, bmp.Width);
    bmp := TyChartImage('image://twoSizes/0', 0, w, h);
    AssertEquals('no size: the list''s own width', 16, bmp.Width);
    AssertEquals('no resolution was made', 2, L.ResolutionCount);
  finally
    TyChartUnregisterImageList('twoSizes');
    L.Free;
    b16.Free;
    b32.Free;
  end;
end;

procedure TAdvChartImageListTest.TestASymbolPictureIsDrawn;
var
  L: TImageList;
  i, n: Integer;
  el: TTyChartElement;
  c: TBGRAPixel;
begin
  L := SolidList(nil, '', 20, 20, clRed);
  try
    TyChartRegisterImageList('redSquare', L);
    Show('{"animation":false,"grid":{"left":0,"right":0,"top":0,"bottom":0},' +
      '"xAxis":{"min":0,"max":10,"show":false},"yAxis":{"min":0,"max":10,"show":false},' +
      '"series":[{"type":"scatter","symbol":"image://redSquare/0","symbolSize":30,' +
      '"itemStyle":{"color":"#00ff00","opacity":1},"data":[[5,5]]}]}');
    n := 0;
    for i := 0 to FChart.List.Count - 1 do
    begin
      el := FChart.List.Element(i);
      if el.Shape.Image = 'redSquare/0' then Inc(n);
    end;
    AssertEquals('one picture element, its source after the prefix', 1, n);
    { the picture, not the series' colour }
    c := Px(150, 100);
    AssertTrue(Format('red at the symbol (%d,%d,%d)', [c.red, c.green, c.blue]),
      (c.red > 200) and (c.green < 60) and (c.blue < 60));
    c := Px(150 + 12, 100 + 12);
    AssertTrue('inside the 30 px box', (c.red > 200) and (c.green < 60));
    c := Px(150 + 20, 100);
    AssertTrue('nothing past it', (c.red > 200) and (c.green > 200));
    { the pointer finds it: a picture answers over its box }
    FChart.Move(150 + 13, 100);
    AssertEquals('pointer', FChart.CursorName);
    { past the box and the port's own pad round a symbol (HitPadLogical) }
    FChart.Move(150 + 30, 100);
    AssertEquals('default', FChart.CursorName);
  finally
    TyChartUnregisterImageList('redSquare');
    L.Free;
  end;
end;

procedure TAdvChartImageListTest.TestAnOwnerListIsFoundAndAStrangersIsNot;
var
  mine, other: TImageList;
  stranger: TComponent;
  elsewhere: TCurProbe;
  c: TBGRAPixel;
const
  cOpt = '{"animation":false,"graphic":[{"type":"image","x":100,"y":50,' +
    '"style":{"image":"image://ownedIcons/0","width":40,"height":40}}]}';
begin
  mine := SolidList(FForm, 'ownedIcons', 16, 16, clBlue);
  AssertNotNull(mine);
  stranger := TComponent.Create(nil);
  try
    Show(cOpt);
    c := Px(120, 70);
    AssertTrue(Format('the owner''s blue (%d,%d,%d)', [c.red, c.green, c.blue]),
      (c.blue > 200) and (c.red < 60));
    { a chart owned elsewhere sees its own owner's list of that name, not
      the form's }
    other := SolidList(stranger, 'ownedIcons', 16, 16, clRed);
    AssertNotNull(other);
    elsewhere := NewOwnedChart(stranger);
    ShowOn(elsewhere, cOpt);
    c := Px(120, 70);
    AssertTrue(Format('the stranger''s own red (%d,%d,%d)', [c.red, c.green, c.blue]),
      (c.red > 200) and (c.blue < 60));
    { and with none there, nothing }
    other.Free;
    ShowOn(elsewhere, cOpt);
    c := Px(120, 70);
    AssertTrue(Format('no list: nothing (%d,%d,%d)', [c.red, c.green, c.blue]),
      (c.red > 200) and (c.green > 200) and (c.blue > 200));
  finally
    stranger.Free;
  end;
end;

procedure TAdvChartImageListTest.TestAPatternTakesAListImage;
var
  L: TImageList;
  c: TBGRAPixel;
begin
  L := SolidList(nil, '', 4, 4, clRed);
  try
    TyChartRegisterImageList('tile', L);
    Show('{"animation":false,"grid":{"left":0,"right":0,"top":0,"bottom":0},' +
      '"xAxis":{"type":"category","data":["a"],"show":false},"yAxis":{"max":10,"show":false},' +
      '"series":[{"type":"bar","barWidth":200,"data":[10],' +
      '"itemStyle":{"color":{"image":"image://tile/0","repeat":"repeat"}}}]}');
    c := Px(150, 100);
    AssertTrue(Format('the tile under the bar (%d,%d,%d)', [c.red, c.green, c.blue]),
      (c.red > 200) and (c.green < 60) and (c.blue < 60));
  finally
    TyChartUnregisterImageList('tile');
    L.Free;
  end;
end;

procedure TAdvChartImageListTest.TestAnAxisArrowPictureIsDrawn;
var
  L: TImageList;
  c: TBGRAPixel;
begin
  L := SolidList(nil, '', 10, 10, clLime);
  try
    TyChartRegisterImageList('arrowPic', L);
    Show('{"animation":false,"grid":{"left":40,"right":40,"top":20,"bottom":40},' +
      '"xAxis":{"type":"category","data":["a","b"],"axisLine":{"symbol":["none","image://arrowPic/0"],' +
      '"symbolSize":[16,16]}},"yAxis":{"show":false},"series":[]}');
    { the arrow sits on the axis line's end: x 260, y 160 }
    c := Px(260, 160);
    AssertTrue(Format('the picture at the end (%d,%d,%d)', [c.red, c.green, c.blue]),
      (c.green > 200) and (c.red < 60) and (c.blue < 60));
  finally
    TyChartUnregisterImageList('arrowPic');
    L.Free;
  end;
end;

procedure TAdvChartImageListTest.TestALargeBatchDrawsNoPicture;
var
  L: TImageList;
  s: string;
  i: Integer;
  c: TBGRAPixel;
begin
  L := SolidList(nil, '', 10, 10, clRed);
  try
    TyChartRegisterImageList('bigRed', L);
    s := '';
    for i := 0 to 299 do
    begin
      if s <> '' then s := s + ',';
      s := s + '[5,5]';
    end;
    Show('{"animation":false,"grid":{"left":0,"right":0,"top":0,"bottom":0},' +
      '"xAxis":{"min":0,"max":10,"show":false},"yAxis":{"min":0,"max":10,"show":false},' +
      '"series":[{"type":"scatter","large":true,"largeThreshold":100,"symbol":"image://bigRed/0",' +
      '"symbolSize":30,"itemStyle":{"color":"#0000ff"},"data":[' + s + ']}]}');
    { LargeSymbolPath builds through the symbol's path, and a picture has
      none: nothing at all -- not a box in the series' colour }
    c := Px(150, 100);
    AssertTrue(Format('nothing drawn (%d,%d,%d)', [c.red, c.green, c.blue]),
      (c.red > 200) and (c.green > 200) and (c.blue > 200));
  finally
    TyChartUnregisterImageList('bigRed');
    L.Free;
  end;
end;

procedure TAdvChartImageListTest.TestTheCssTable;

  procedure Is_(const ACss: string; AWant: TCursor);
  var c: TCursor;
  begin
    AssertTrue(ACss + ' maps', TyChartCssCursor(ACss, c));
    AssertEquals(ACss, AWant, c);
  end;

  procedure Not_(const ACss: string);
  var c: TCursor;
  begin
    AssertFalse(ACss + ' is the host''s', TyChartCssCursor(ACss, c));
  end;

begin
  Is_('pointer', crHandPoint);
  Is_('move', crSizeAll);
  Is_('grab', crHandPoint);
  Is_('grabbing', crSizeAll);
  Is_('crosshair', crCross);
  Is_('text', crIBeam);
  Is_('not-allowed', crNo);
  Is_('help', crHelp);
  Is_('wait', crHourGlass);
  Is_('progress', crAppStart);
  Is_('ew-resize', crSizeWE);
  Is_('ns-resize', crSizeNS);
  Is_('nwse-resize', crSizeNWSE);
  Is_('nesw-resize', crSizeNESW);
  Is_('col-resize', crHSplit);
  Is_('row-resize', crVSplit);
  Is_('none', crNone);
  Is_(' Pointer ', crHandPoint);
  Is_('url(hand.cur), pointer', crHandPoint);
  Not_('default');
  Not_('auto');
  Not_('');
  Not_('zoom-in');
end;

procedure TAdvChartImageListTest.TestTheHostsCursorComesBack;
begin
  FChart.Cursor := crIBeam;
  Show('{"animation":false,"grid":{"left":0,"right":0,"top":0,"bottom":0},' +
    '"xAxis":{"type":"category","data":["a","b"],"show":false},"yAxis":{"max":10,"show":false},' +
    '"series":[{"type":"bar","barWidth":40,"cursor":"help","data":[10,10]}]}');
  FChart.Move(75, 100);
  AssertEquals('help', FChart.CursorName);
  AssertEquals('help over the bar', crHelp, FChart.Cursor);
  FChart.Move(150, 100);
  AssertEquals('default', FChart.CursorName);
  AssertEquals('the host''s own between the bars', crIBeam, FChart.Cursor);
  FChart.Move(225, 100);
  AssertEquals(crHelp, FChart.Cursor);
  FChart.Leave;
  AssertEquals('leaving gives it back', crIBeam, FChart.Cursor);
end;

procedure TAdvChartImageListTest.TestAHostCursorSetMeanwhileIsKept;
begin
  FChart.Cursor := crIBeam;
  Show('{"animation":false,"grid":{"left":0,"right":0,"top":0,"bottom":0},' +
    '"xAxis":{"type":"category","data":["a","b"],"show":false},"yAxis":{"max":10,"show":false},' +
    '"series":[{"type":"bar","barWidth":40,"data":[10,10]}]}');
  FChart.Move(75, 100);
  AssertEquals(crHandPoint, FChart.Cursor);
  { the host changes its mind while the chart shows its own }
  FChart.Cursor := crCross;
  FChart.Move(225, 100);
  AssertEquals('the chart''s again', crHandPoint, FChart.Cursor);
  FChart.Move(150, 100);
  AssertEquals('the host''s new one, not the first', crCross, FChart.Cursor);
end;

initialization
  RegisterTest(TAdvChartCursorOracleTest);
  RegisterTest(TAdvChartImageListTest);
end.
