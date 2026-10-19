unit test.devicescale.grid;
{$mode objfpc}{$H+}

{ #83: the grid at the device scale.

  The grid keeps more between frames than any other control: a persistent surface whose body is
  shifted on a scroll instead of redrawn, and a cache of every cell's text as a bitmap. Both are
  held in device pixels; both must follow a change of the device scale. On top of them it draws
  straight onto the layer: grid lines, cell borders, header dividers and groups, a background
  picture and image cells. Each check builds a grid in the state that reaches the drawing and
  compares S = 2 with S = 1 (test.devicescale.support). }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, ImgList, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Columns, tyControls.Grid, tyControls.Grid.Layout,
  test.devicescale.support, test.devicescale.controls;

type
  TDeviceScaleGridTest = class(TDeviceScaleCase)
  private
    FImages: TImageList;
    FBackground: TBGRABitmap;
    FMode: Integer;
    function Images: TImageList;
    function NewGrid(AParent: TWinControl; APPI, ARows: Integer): TTyStringGrid;
    function Metrics(ABuild: TTyBuildForScale): TTyGridMetrics;
    function BuildLinesFrozen(AParent: TWinControl; APPI: Integer): TControl;
    function BuildLines(AParent: TWinControl; APPI: Integer): TControl;
    function BuildHeaderGroups(AParent: TWinControl; APPI: Integer): TControl;
    function BuildCellBorders(AParent: TWinControl; APPI: Integer): TControl;
    function BuildBackground(AParent: TWinControl; APPI: Integer): TControl;
    function BuildImages(AParent: TWinControl; APPI: Integer): TControl;
    function BuildLong(AParent: TWinControl; APPI: Integer): TControl;
    function BuildDrawGrid(AParent: TWinControl; APPI: Integer): TControl;
    function BuildSelectionFar(AParent: TWinControl; APPI: Integer): TControl;
    procedure DrawGridText(Sender: TObject; ACol, ARow: Integer; var AText: string);
    procedure CellBorder(Sender: TObject; ACol, ARow: Integer; var ABorders: TTyGridCellBorders);
    procedure CellDisplay(Sender: TObject; ACol, ARow: Integer; var ADisplay: TTyGridCellDisplay);
    procedure CheckFastScroll(AScale: Integer);
  protected
    procedure TearDown; override;
  published
    procedure TestLinesWithFrozenRowsAndColumns;
    procedure TestGridLineRules;
    procedure TestHeaderDividerRules;
    procedure TestHeaderGroups;
    procedure TestCellBorders;
    procedure TestBackgroundStretched;
    procedure TestBackgroundTiled;
    procedure TestBackgroundCentred;
    procedure TestImageCellsAndHeaderIcon;
    { TTyDrawGrid lays its cells out itself: text from OnGetCellText, clipped per cell. }
    procedure TestDrawGridText;
    { The selection frame and its fill handle are clipped to the pane of the selected cell; with
      the cursor far from the origin, a clip left in layout pixels cuts them away. }
    procedure TestSelectionFrameAwayFromTheOrigin;
    { The fast path shifts the surface by the scroll and redraws only the strip that came into
      view; at S = 2 the shift is S times the scroll. The result must be the full redraw of the
      grid scrolled there, pixel for pixel. }
    procedure TestFastScrollMatchesFullRedraw;
    procedure TestFastScrollMatchesFullRedrawAtOne;
    { A window dragged from a Retina screen to a plain one (Review Focus 1): the surface and the
      text cache were filled at S = 2; the next frame at S = 1 must be the grid drawn at S = 1
      from the start, pixel for pixel. And the other way. }
    procedure TestSurfaceFollowsScaleDown;
    procedure TestSurfaceFollowsScaleUp;
    { The picture is scaled once per device scale, not every frame; an Invalidate -- a new or
      repainted picture -- scales it again. }
    procedure TestTiledBackgroundIsScaledOncePerScale;
    { At S = 2 each cached cell text holds S^2 the pixels: the cache is bounded in pixels too. }
    procedure TestTextCacheIsBoundedInPixels;
  end;

implementation

type
  TControlAccess = class(TControl);
  TGridAccess = class(TTyStringGrid);

const
  CGridW = 300;
  CGridH = 200;
  CColNames: array[0..3] of string = ('Name', 'Qty', 'Price', 'Note');
  CColW: array[0..3] of Integer = (80, 60, 70, 80);
  CFrameGap = 4;

procedure SaveForLooking(const AName: string; A, B: TBGRABitmap);
var
  dir: string;
begin
  dir := GetEnvironmentVariable('TY_SWEEP_DIR');
  if dir = '' then Exit;
  A.SaveToFile(IncludeTrailingPathDelimiter(dir) + AName + '-a.png');
  B.SaveToFile(IncludeTrailingPathDelimiter(dir) + AName + '-b.png');
end;

function PixelsApart(A, B: TBGRABitmap): Integer;
var
  x, y: Integer;
  pa, pb: PBGRAPixel;
begin
  if (A.Width <> B.Width) or (A.Height <> B.Height) then Exit(MaxInt);
  Result := 0;
  for y := 0 to A.Height - 1 do
  begin
    pa := A.ScanLine[y];
    pb := B.ScanLine[y];
    for x := 0 to A.Width - 1 do
      if LongWord(pa[x]) <> LongWord(pb[x]) then Inc(Result);
  end;
end;

procedure TDeviceScaleGridTest.TearDown;
begin
  FreeAndNil(FImages);
  FreeAndNil(FBackground);
  inherited TearDown;
end;

function TDeviceScaleGridTest.Images: TImageList;
var
  b: TBitmap;
begin
  if FImages = nil then
  begin
    FImages := TImageList.Create(nil);
    FImages.Width := 16;
    FImages.Height := 16;
    b := TBitmap.Create;
    try
      TyFillTestPicture(b, 16, 16);
      FImages.Add(b, nil);
    finally
      b.Free;
    end;
  end;
  Result := FImages;
end;

function TDeviceScaleGridTest.NewGrid(AParent: TWinControl; APPI, ARows: Integer): TTyStringGrid;
var
  i, r: Integer;
  col: TTyColumn;
begin
  Result := TTyStringGrid.Create(AParent);
  Result.Parent := AParent;
  TControlAccess(Result).Font.PixelsPerInch := APPI;
  Result.SetBounds(0, 0, CGridW, CGridH);
  Result.Header.Options := Result.Header.Options + [hoVisible];
  for i := 0 to High(CColNames) do
  begin
    col := Result.Header.Columns.Add as TTyColumn;
    col.Text := CColNames[i];
    col.Width := CColW[i];
  end;
  Result.RowCount := ARows;
  for r := 0 to ARows - 1 do
    for i := 0 to High(CColNames) do
      Result.Cells[i, r] := CColNames[i] + ' ' + IntToStr(r);
end;

function TDeviceScaleGridTest.Metrics(ABuild: TTyBuildForScale): TTyGridMetrics;
var
  f: TForm;
  c: TControl;
begin
  f := TForm.CreateNew(nil);
  try
    f.SetBounds(0, 0, CGridW + 40, CGridH + 40);
    c := ABuild(f, 96);
    c.SetBounds(0, 0, CGridW, CGridH);
    Result := TGridAccess(c).GridMetrics;
  finally
    f.Free;
  end;
end;

function TDeviceScaleGridTest.BuildLinesFrozen(AParent: TWinControl; APPI: Integer): TControl;
var
  g: TTyStringGrid;
begin
  g := NewGrid(AParent, APPI, 20);
  g.GridLineStyle := glsBoth;
  g.FixedCols := 1;
  g.FixedRows := 1;
  g.ShowRowNumbers := True;
  Result := g;
end;

function TDeviceScaleGridTest.BuildLines(AParent: TWinControl; APPI: Integer): TControl;
var
  g: TTyStringGrid;
begin
  g := NewGrid(AParent, APPI, 20);
  g.GridLineStyle := glsBoth;
  Result := g;
end;

function TDeviceScaleGridTest.BuildHeaderGroups(AParent: TWinControl; APPI: Integer): TControl;
var
  g: TTyStringGrid;
  grp: TTyGridHeaderGroup;
begin
  g := NewGrid(AParent, APPI, 6);
  g.GridLineStyle := glsBoth;
  grp := g.HeaderGroups.Add;
  grp.Text := 'Item';
  grp.FirstCol := 0; grp.LastCol := 1; grp.Level := 0;
  grp := g.HeaderGroups.Add;
  grp.Text := 'Money';
  grp.FirstCol := 2; grp.LastCol := 3; grp.Level := 0;
  grp := g.HeaderGroups.Add;
  grp.Text := 'Cost';
  grp.FirstCol := 2; grp.LastCol := 2; grp.Level := 1;
  Result := g;
end;

procedure TDeviceScaleGridTest.CellBorder(Sender: TObject; ACol, ARow: Integer;
  var ABorders: TTyGridCellBorders);
begin
  if (ACol = 1) and (ARow in [1, 2]) then
  begin
    ABorders.Left := True;
    ABorders.Top := ARow = 1;
    ABorders.Right := True;
    ABorders.Bottom := ARow = 2;
    ABorders.Width := 2;
    ABorders.Color := TyRGBA(200, 30, 30, 255);   // a TTyColor carries alpha: clRed is clear
  end;
  if (ACol = 3) and (ARow = 4) then
  begin
    ABorders.Bottom := True;
    ABorders.Width := 1;
    ABorders.Color := TyRGBA(30, 30, 200, 255);
  end;
end;

function TDeviceScaleGridTest.BuildCellBorders(AParent: TWinControl; APPI: Integer): TControl;
var
  g: TTyStringGrid;
begin
  g := NewGrid(AParent, APPI, 8);
  g.OnGetCellBorder := @CellBorder;
  Result := g;
end;

function TDeviceScaleGridTest.BuildBackground(AParent: TWinControl; APPI: Integer): TControl;
var
  g: TTyStringGrid;
  b: TBitmap;
begin
  if FBackground = nil then
  begin
    b := TBitmap.Create;
    try
      TyFillTestPicture(b, 36, 24);
      FBackground := TBGRABitmap.Create(b);
    finally
      b.Free;
    end;
  end;
  { Two rows: the picture shows in the body below them. }
  g := NewGrid(AParent, APPI, 2);
  g.BackgroundBitmap := FBackground;
  g.BackgroundMode := TTyGridBackgroundMode(FMode);
  g.BackgroundScope := gbsWholeGrid;
  Result := g;
end;

procedure TDeviceScaleGridTest.CellDisplay(Sender: TObject; ACol, ARow: Integer;
  var ADisplay: TTyGridCellDisplay);
begin
  if ACol = 1 then ADisplay := gcdImage;
end;

function TDeviceScaleGridTest.BuildImages(AParent: TWinControl; APPI: Integer): TControl;
var
  g: TTyStringGrid;
  r: Integer;
begin
  g := NewGrid(AParent, APPI, 6);
  g.Images := Images;
  g.OnGetCellDisplay := @CellDisplay;
  for r := 0 to 5 do g.Cells[1, r] := '0';
  (g.Header.Columns.Items[0] as TTyColumn).ImageIndex := 0;
  Result := g;
end;

function TDeviceScaleGridTest.BuildLong(AParent: TWinControl; APPI: Integer): TControl;
var
  g: TTyStringGrid;
begin
  g := NewGrid(AParent, APPI, 200);
  g.GridLineStyle := glsBoth;
  Result := g;
end;

procedure TDeviceScaleGridTest.DrawGridText(Sender: TObject; ACol, ARow: Integer;
  var AText: string);
begin
  AText := CColNames[ACol mod Length(CColNames)] + ' ' + IntToStr(ARow);
end;

function TDeviceScaleGridTest.BuildDrawGrid(AParent: TWinControl; APPI: Integer): TControl;
var
  g: TTyDrawGrid;
  i: Integer;
  col: TTyColumn;
begin
  g := TTyDrawGrid.Create(AParent);
  g.Parent := AParent;
  TControlAccess(g).Font.PixelsPerInch := APPI;
  g.SetBounds(0, 0, CGridW, CGridH);
  g.Header.Options := g.Header.Options + [hoVisible];
  for i := 0 to High(CColNames) do
  begin
    col := g.Header.Columns.Add as TTyColumn;
    col.Text := CColNames[i];
    col.Width := CColW[i];
  end;
  g.RowCount := 20;
  g.GridLineStyle := glsBoth;
  g.OnGetCellText := @DrawGridText;
  Result := g;
end;

function TDeviceScaleGridTest.BuildSelectionFar(AParent: TWinControl; APPI: Integer): TControl;
var
  g: TTyStringGrid;
begin
  { A range, so the frame shows against the range's lighter fill, not only at its handle. }
  g := NewGrid(AParent, APPI, 12);
  g.SelectRange(2, 3, 3, 6);
  Result := g;
end;

procedure TDeviceScaleGridTest.TestSelectionFrameAwayFromTheOrigin;
begin
  CheckScale('TTyStringGrid-selection-far', @BuildSelectionFar, CGridW, CGridH);
end;

procedure TDeviceScaleGridTest.TestDrawGridText;
begin
  CheckScale('TTyDrawGrid-text', @BuildDrawGrid, CGridW, CGridH);
end;

procedure TDeviceScaleGridTest.TestLinesWithFrozenRowsAndColumns;
begin
  CheckScale('TTyStringGrid-lines-frozen', @BuildLinesFrozen, CGridW, CGridH);
end;

procedure TDeviceScaleGridTest.TestGridLineRules;
var
  m: TTyGridMetrics;
  body: TRect;
begin
  m := Metrics(@BuildLines);
  { Off the frame on both sides: its antialiased edge comes out a shade apart at the two scales. }
  body := Rect(CFrameGap, m.FrozenTop, m.ClientW - CFrameGap, m.ClientH);
  AssertTrue('the grid has a body', body.Bottom - body.Top > 40);
  { The columns' right edges inside the frame; a line under each of the rows in view. }
  CheckRules('the grid''s column lines', @BuildLines, CGridW, CGridH, body, True, 3, 8);
  CheckRules('the grid''s row lines', @BuildLines, CGridW, CGridH, body, False, 4, 20);
end;

procedure TDeviceScaleGridTest.TestHeaderDividerRules;
var
  m: TTyGridMetrics;
begin
  m := Metrics(@BuildLines);
  AssertTrue('the grid has a header', m.FrozenTop > 8);
  CheckRules('the grid''s header dividers', @BuildLines, CGridW, CGridH,
    Rect(CFrameGap, 0, m.ClientW - CFrameGap, m.FrozenTop), True, 3, 8);
end;

procedure TDeviceScaleGridTest.TestHeaderGroups;
begin
  CheckScale('TTyStringGrid-header-groups', @BuildHeaderGroups, CGridW, CGridH);
end;

procedure TDeviceScaleGridTest.TestCellBorders;
begin
  CheckScale('TTyStringGrid-cell-borders', @BuildCellBorders, CGridW, CGridH);
end;

procedure TDeviceScaleGridTest.TestBackgroundStretched;
begin
  FMode := Ord(gbmStretch);
  CheckScale('TTyStringGrid-background-stretched', @BuildBackground, CGridW, CGridH);
end;

procedure TDeviceScaleGridTest.TestBackgroundTiled;
begin
  FMode := Ord(gbmTile);
  CheckScale('TTyStringGrid-background-tiled', @BuildBackground, CGridW, CGridH);
end;

procedure TDeviceScaleGridTest.TestBackgroundCentred;
begin
  FMode := Ord(gbmCenter);
  CheckScale('TTyStringGrid-background-centred', @BuildBackground, CGridW, CGridH);
end;

procedure TDeviceScaleGridTest.TestImageCellsAndHeaderIcon;
begin
  CheckScale('TTyStringGrid-images', @BuildImages, CGridW, CGridH);
end;

procedure TDeviceScaleGridTest.TestFastScrollMatchesFullRedraw;
begin
  CheckFastScroll(2);
end;

procedure TDeviceScaleGridTest.TestFastScrollMatchesFullRedrawAtOne;
begin
  CheckFastScroll(1);
end;

procedure TDeviceScaleGridTest.CheckFastScroll(AScale: Integer);
var
  f1, f2: TForm;
  g1, g2: TTyStringGrid;
  first, scrolled, fresh: TBGRABitmap;
  before: Integer;
begin
  scrolled := nil;
  fresh := nil;
  f1 := TForm.CreateNew(nil);
  f2 := TForm.CreateNew(nil);
  try
    f1.SetBounds(0, 0, CGridW + 40, CGridH + 40);
    f2.SetBounds(0, 0, CGridW + 40, CGridH + 40);
    g1 := TTyStringGrid(BuildLong(f1, 96));
    first := TyPaintOwnSurface(g1, AScale);   // the frame the scroll reuses
    first.Free;
    before := TGridAccess(g1).FastScrollFrames;
    g1.TopRow := g1.TopRow + 3;
    scrolled := TyPaintOwnSurface(g1, AScale);
    AssertTrue('the scroll took the fast path', TGridAccess(g1).FastScrollFrames > before);

    g2 := TTyStringGrid(BuildLong(f2, 96));
    g2.TopRow := 3;
    fresh := TyPaintOwnSurface(g2, AScale);
    if PixelsApart(scrolled, fresh) <> 0 then
      SaveForLooking('grid-fast-scroll-' + IntToStr(AScale), scrolled, fresh);
    AssertEquals(Format('scrolled at S = %d by the fast path = drawn there in full', [AScale]), 0,
      PixelsApart(scrolled, fresh));
  finally
    scrolled.Free;
    fresh.Free;
    f2.Free;
    f1.Free;
  end;
end;

procedure TDeviceScaleGridTest.TestSurfaceFollowsScaleDown;
var
  f1, f2: TForm;
  g1, g2: TControl;
  pic, ref: TBGRABitmap;
begin
  pic := nil;
  ref := nil;
  f1 := TForm.CreateNew(nil);
  f2 := TForm.CreateNew(nil);
  try
    f1.SetBounds(0, 0, CGridW + 40, CGridH + 40);
    f2.SetBounds(0, 0, CGridW + 40, CGridH + 40);
    g1 := BuildLines(f1, 96);
    TyPaintOwnSurface(g1, 2).Free;
    pic := TyPaintOwnSurface(g1, 1);
    g2 := BuildLines(f2, 96);
    ref := TyPaintOwnSurface(g2, 1);
    AssertEquals('S = 2 then S = 1 = S = 1 from the start', 0, PixelsApart(pic, ref));
  finally
    pic.Free;
    ref.Free;
    f2.Free;
    f1.Free;
  end;
end;

procedure TDeviceScaleGridTest.TestSurfaceFollowsScaleUp;
var
  f1, f2: TForm;
  g1, g2: TControl;
  pic, ref: TBGRABitmap;
begin
  pic := nil;
  ref := nil;
  f1 := TForm.CreateNew(nil);
  f2 := TForm.CreateNew(nil);
  try
    f1.SetBounds(0, 0, CGridW + 40, CGridH + 40);
    f2.SetBounds(0, 0, CGridW + 40, CGridH + 40);
    g1 := BuildLines(f1, 96);
    TyPaintOwnSurface(g1, 1).Free;
    pic := TyPaintOwnSurface(g1, 2);
    g2 := BuildLines(f2, 96);
    ref := TyPaintOwnSurface(g2, 2);
    AssertEquals('S = 1 then S = 2 = S = 2 from the start', 0, PixelsApart(pic, ref));
  finally
    pic.Free;
    ref.Free;
    f2.Free;
    f1.Free;
  end;
end;

procedure TDeviceScaleGridTest.TestTiledBackgroundIsScaledOncePerScale;
var
  f: TForm;
  g: TTyStringGrid;
  pic: TBGRABitmap;
  m: TTyGridMetrics;
begin
  f := TForm.CreateNew(nil);
  try
    f.SetBounds(0, 0, CGridW + 40, CGridH + 40);
    FMode := Ord(gbmTile);
    g := TTyStringGrid(BuildBackground(f, 96));
    TyPaintOwnSurface(g, 2).Free;
    AssertEquals('scaled for the first frame', 1, TGridAccess(g).BackgroundTileBuilds);
    TyPaintOwnSurface(g, 2).Free;
    AssertEquals('and reused for the next', 1, TGridAccess(g).BackgroundTileBuilds);
    TyPaintOwnSurface(g, 1).Free;
    AssertEquals('S = 1 draws the picture as it is', 1, TGridAccess(g).BackgroundTileBuilds);
    FBackground.Fill(BGRA(0, 0, 255, 255));   // the picture repainted in place ...
    g.Invalidate;                              // ... and the grid told
    pic := TyPaintOwnSurface(g, 2);
    try
      AssertEquals('scaled again after an Invalidate', 2, TGridAccess(g).BackgroundTileBuilds);
      m := TGridAccess(g).GridMetrics;
      AssertTrue('and the new picture shows', BGRAToColor(pic.GetPixel(2 * (m.ClientW div 2),
        2 * (m.ClientH - 10))) = clBlue);
    finally
      pic.Free;
    end;
  finally
    f.Free;
  end;
end;

procedure TDeviceScaleGridTest.TestTextCacheIsBoundedInPixels;
var
  f: TForm;
  g: TTyStringGrid;
begin
  f := TForm.CreateNew(nil);
  try
    f.SetBounds(0, 0, CGridW + 40, CGridH + 40);
    g := TTyStringGrid(BuildLines(f, 96));
    { A cell's text bitmap at S = 2 is some 150 x 40 device pixels: a 20 000-pixel budget holds
      three or four of them, where the count cap alone would keep every cell in view. }
    TGridAccess(g).TextCachePixelBudget := 20000;
    TyPaintOwnSurface(g, 2).Free;
    AssertTrue(Format('the cached pixels stay in the budget (%d)', [TGridAccess(g).TextCachePixels]),
      TGridAccess(g).TextCachePixels <= 20000);
    AssertTrue(Format('so few cells stay cached (%d)', [TGridAccess(g).TextCacheCount]),
      TGridAccess(g).TextCacheCount <= 4);
  finally
    f.Free;
  end;
end;

initialization
  RegisterTest(TDeviceScaleGridTest);

end.
