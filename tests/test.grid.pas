unit test.grid;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, DateUtils, Types, Graphics, Controls, Forms, LCLType, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.Columns, tyControls.Grid, tyControls.ComboBox,
  tyControls.Painter, tyControls.ImageCollection,
  tyControls.Grid.Layout;

type
  TTyGridControlTest = class(TTestCase)
  private
    FForm: TForm;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestFrozenBandSumsIndicatorAndFixedColumns;
    procedure TestFrozenBandSumsHeaderAndFixedRows;
    procedure TestFixedColumnsDoNotScrollButBodyColumnsDo;
    procedure TestCellAtIsTheExactInverseOfCellRect;
    procedure TestCellAtRejectsHeaderIndicatorAndBlankSpace;
    procedure TestPaintsSurfaceAndGridLines;
    procedure TestUndefinedGridKeyDrawsNothing;
    procedure TestRendersUnderTheDefaultThemeWithNoCustomCss;
    procedure TestHeaderIndicatorAndFixedPanesPaintTheirOwnTokens;
    procedure TestHeaderPaintsColumnCaptions;
    procedure TestHeaderDrawsColumnImage;
  end;

  { 纯自绘网格:内容全部来自宿主事件。 }
  TTyDrawGridTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FCellText: string;
    FAsked: Integer;      { 宿主被问过多少次 —— 用来证明虚拟化真的生效 }
    procedure HandleGetCellText(Sender: TObject; ACol, ARow: Integer; var AText: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPaintsCellTextSuppliedByTheHost;
    procedure TestOnlyAsksForVisibleRows;
  end;

  { 完整体:稀疏存储 + 二维光标 + 键鼠。 }
  TTyStringGridTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FTakeOverCol: Integer;
    procedure HandleReadOnlyCol2(Sender: TObject; ACol, ARow: Integer;
      var AKind: TTyGridEditorKind);
    procedure HandleGetPickList(Sender: TObject; ACol, ARow: Integer; AItems: TStrings);
    procedure HandleTallSecondRow(Sender: TObject; ARow: Integer; var AHeight: Integer);
    procedure HandleDrawCell(Sender: TObject; ACol, ARow: Integer;
      const ARect: TRect; APainter: TTyPainter; var AHandled: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCellStorageIsSparse;
    procedure TestClickMovesTheCursorToTheClickedCell;
    procedure TestArrowKeysMoveAndClampTheCursor;
    procedure TestStoredTextRendersAndCursorIsHighlighted;
    procedure TestScrollIsClampedToContent;
    procedure TestCursorScrollsItselfIntoView;
    procedure TestScrollBarsAppearOnlyWhenContentOverflows;
    procedure TestEditCommitsOnEnterAndRevertsOnEscape;
    procedure TestReadOnlyAndNoneKindBlockEditing;
    procedure TestMovingTheCursorCommitsTheOpenEditor;
    procedure TestNumericColumnRejectsNonNumericText;
    procedure TestSortReordersDisplayButKeepsCellsAddressedByDataRow;
    procedure TestCursorFollowsItsDataRowAcrossSort;
    procedure TestNumericSortComparesNumbersNotText;
    procedure TestHeaderClickTogglesAscDescThenClears;
    procedure TestShiftArrowsExtendTheRangeAndPlainArrowsCollapseIt;
    procedure TestSortingRealisticGridIsFast;
    procedure TestSortKeepsTheViewportWhereItWas;
    procedure TestProgrammaticScrollSyncsTheScrollBarThumb;
    procedure TestColumnFilterHidesNonMatchingRows;
    procedure TestFilterAndSortComposeAndCellsStayAddressable;
    procedure TestFilteredOutRowHasNoDisplayPosition;
    procedure TestSelectionExportsAsTabbedTextInDisplayOrder;
    procedure TestPasteFillsFromCursorAndSkipsReadOnlyColumns;
    procedure TestCsvRoundTripsQuotesDelimitersAndNewlines;
    procedure TestCsvExportFollowsFilterAndSort;
    procedure TestCheckBoxCellTogglesOnClickAndSpace;
    procedure TestCheckBoxReadsLooseTruthyValuesButWritesCanonical;
    procedure TestPickListEditorCommitsTheChosenItem;
    procedure TestAggregatesCountOnlyVisibleRows;
    procedure TestAggregatesSkipNonNumericCells;
    procedure TestMergedBaseCellSpansAndCoveredCellsHaveNoRect;
    procedure TestClickInsideMergedAreaLandsOnTheBaseCell;
    procedure TestGroupingInsertsSyntheticRowsAndCountsMembers;
    procedure TestCollapsingAGroupHidesItsRowsButKeepsTheHeader;
    procedure TestCollapseStateSurvivesResort;
    procedure TestGroupRowIsNotACell;
    procedure TestCheckBoxLookIgnoresGridTransientStates;
    procedure TestProgressFillWidthTracksTheValue;
    procedure TestDistinctValuesIgnoreThisColumnsOwnFilter;
    procedure TestValueFilterKeepsOnlyCheckedValues;
    procedure TestHeaderDividerDragResizesTheColumn;
    procedure TestHeaderDragReordersColumnsPastAThreshold;
    procedure TestVariableRowHeightsShiftLaterRowsAndHitTest;
    procedure TestUniformGridAllocatesNoRowTopsArray;
    procedure TestFixedRowsStayPutWhileBodyRowsScroll;
    procedure TestFixedRowsAreClickableAndBodyStartsAfterThem;
    procedure TestInsertAndDeleteRowShiftCellContents;
    procedure TestInsertAndDeleteColumnShiftCellContents;
    procedure TestRowSelectionModeSelectsWholeRows;
    procedure TestAutoFitColumnWidensToTheLongestCell;
    procedure TestFindWalksTheWholeGridInDisplayOrderAndWraps;
    procedure TestFindSkipsGroupRowsAndHonoursCaseAndWholeCell;
    procedure TestReplaceAllSkipsReadOnlyColumns;
    procedure TestHtmlExportEscapesAndFollowsFilterOrder;
    procedure TestOnDrawCellCanTakeOverACell;
    procedure TestCsvRoundTripsCellsContainingNewlines;
    procedure TestAutoResizeColumnFillsRemainingWidth;
  end;

implementation

type
  { 够到 protected 的几何装配接缝。 }
  TGridAccess = class(TTyCustomGrid)
  public
    function StyleTypeKey: string;
    function Metrics: TTyGridMetrics;
    procedure ScrollTo(AX, AY: Integer);
    function ColLeft(ACol: Integer): Integer;
    procedure DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

procedure TGridAccess.DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TGridAccess.ScrollTo(AX, AY: Integer);
begin
  ScrollX := AX;
  ScrollY := AY;
end;

function TGridAccess.ColLeft(ACol: Integer): Integer;
begin
  Result := ColumnLeftPx(ACol);
end;

function TGridAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

function TGridAccess.Metrics: TTyGridMetrics;
begin
  Result := GridMetrics;
end;

{ 建一个 96 PPI、已挂父窗体、列宽已知的网格。 }
function MakeGrid(AForm: TForm; const AWidths: array of Integer): TGridAccess;
var
  i: Integer;
  c: TTyColumn;
begin
  Result := TGridAccess.Create(AForm);
  Result.Parent := AForm;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 300);
  for i := 0 to High(AWidths) do
  begin
    c := Result.Header.Columns.Add as TTyColumn;
    c.Width := AWidths[i];
  end;
end;

procedure TTyGridControlTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 600, 400);
end;

procedure TTyGridControlTest.TearDown;
begin
  FreeAndNil(FForm);
end;

{ 必须有自己的 typeKey:借用树/列表的键会让外观主题层够不着本控件,
  而且改那个键会连带波及被借的控件。 }
procedure TTyGridControlTest.TestTypeKey;
var
  G: TGridAccess;
begin
  G := MakeGrid(FForm, [100]);
  AssertEquals('网格用自己的 typeKey', 'TyGrid', G.StyleTypeKey);
end;

{ 冻结带宽 = 行头槽 + 各固定列宽之和。这个值一错,四个窗格的切分就整体错位,
  后面所有绘制与命中都建在斜的地基上。 }
procedure TTyGridControlTest.TestFrozenBandSumsIndicatorAndFixedColumns;
var
  G: TGridAccess;
begin
  G := MakeGrid(FForm, [80, 60, 120, 90]);

  // 没有行头槽、没有固定列 —— 冻结带零宽。
  AssertEquals('无固定列时冻结带零宽', 0, G.Metrics.FrozenW);

  // 冻结前 2 列(80+60),仍无行头槽。
  G.FixedCols := 2;
  AssertEquals('冻结带 = 前两列宽之和', 140, G.Metrics.FrozenW);

  // 打开 30px 行头槽。
  G.ShowIndicator := True;
  G.IndicatorWidth := 30;
  AssertEquals('冻结带 = 行头槽 + 前两列', 170, G.Metrics.FrozenW);

  // 行头槽关掉就不占位(仅设宽度不生效)。
  G.ShowIndicator := False;
  AssertEquals('关掉行头槽后不占位', 140, G.Metrics.FrozenW);

  // 固定列数超过实际列数时按实际列数封顶,不能越界求和。
  G.FixedCols := 99;
  AssertEquals('固定列数超出时按全部列封顶', 80 + 60 + 120 + 90, G.Metrics.FrozenW);
end;

{ 冻结带高 = 列头带(可见时)+ 固定行 * 行高。 }
procedure TTyGridControlTest.TestFrozenBandSumsHeaderAndFixedRows;
var
  G: TGridAccess;
begin
  G := MakeGrid(FForm, [100]);
  G.Header.Height := 24;
  G.DefaultRowHeight := 20;
  G.RowCount := 50;

  // 列头可见(hoVisible 是默认),无固定行。
  AssertEquals('冻结带高 = 列头高', 24, G.Metrics.FrozenH);

  G.FixedRows := 2;
  AssertEquals('冻结带高 = 列头 + 2 个固定行', 24 + 2 * 20, G.Metrics.FrozenH);

  // 列头隐藏后不占位,固定行仍占位。
  G.Header.Options := G.Header.Options - [hoVisible];
  AssertEquals('列头隐藏后只剩固定行', 2 * 20, G.Metrics.FrozenH);
end;

{ 冻结的意义就在这条:横向滚动时固定列必须钉住不动,正文列才平移。
  两者若同步移动,冻结列就白冻了;若反过来,内容会从冻结带底下钻出来。 }
procedure TTyGridControlTest.TestFixedColumnsDoNotScrollButBodyColumnsDo;
var
  G: TGridAccess;
  fixed0, fixed1, body2Before, body2After: Integer;
begin
  G := MakeGrid(FForm, [80, 60, 120, 90]);
  { 视口收窄到 200 —— 内容合计 380px,这样横向滚动才是**真的可以滚**。
    (滚动量现在会被钳在 [0,MaxScrollX];内容比视口窄时压根不该能滚。) }
  G.SetBounds(0, 0, 200, 300);
  G.ShowIndicator := True;
  G.IndicatorWidth := 30;
  G.FixedCols := 2;                 // 第 0、1 列冻结;冻结带 = 30+80+60 = 170

  fixed0 := G.ColLeft(0);
  fixed1 := G.ColLeft(1);
  body2Before := G.ColLeft(2);

  AssertEquals('第 0 列紧贴行头槽右侧', 30, fixed0);
  AssertEquals('第 1 列在第 0 列之后', 30 + 80, fixed1);
  AssertEquals('第 2 列(正文首列)从冻结带右缘起', 170, body2Before);

  // 横向滚动 45px。
  G.ScrollTo(45, 0);
  AssertEquals('固定列 0 纹丝不动', fixed0, G.ColLeft(0));
  AssertEquals('固定列 1 纹丝不动', fixed1, G.ColLeft(1));
  body2After := G.ColLeft(2);
  AssertEquals('正文列左移 45', body2Before - 45, body2After);
end;

{ 二维版的核心不变量,精确表述是:**CellAt 是 CellVisibleRect 的逆**。
  注意不是 CellRect —— 正文列横向滚到冻结带底下的那一段被固定列盖住,本来就点不到,
  拿未裁剪的几何矩形去要求可点是错的(这条测试第一次跑就把这个概念缺口揪了出来)。 }
procedure TTyGridControlTest.TestCellAtIsTheExactInverseOfCellRect;
var
  G: TGridAccess;
  col, row, x, y: Integer;
  r: TRect;
  hit: TTyGridHit;
  swept: Integer;
begin
  G := MakeGrid(FForm, [80, 60, 120, 90]);
  G.SetBounds(0, 0, 200, 300);      { 收窄视口,让 ScrollX 不被钳成 0 }
  G.ShowIndicator := True;
  G.IndicatorWidth := 30;
  G.FixedCols := 1;
  G.Header.Height := 24;
  G.DefaultRowHeight := 20;
  G.RowCount := 100;
  G.ScrollTo(35, 25);               // 两轴都带零头,专挑半露的行列

  swept := 0;
  for col := 0 to 3 do
    for row := 0 to 5 do
    begin
      r := G.CellVisibleRect(col, row);
      if IsRectEmpty(r) then Continue;
      // 逐像素扫可见矩形:每一点都必须反查回本单元格,一个都不能差。
      for x := r.Left to r.Right - 1 do
        for y := r.Top to r.Bottom - 1 do
        begin
          hit := G.CellAt(x, y);
          AssertEquals(Format('(%d,%d) 必须命中单元格', [x, y]), Ord(ghpCell), Ord(hit.Part));
          AssertEquals(Format('(%d,%d) 反查列', [x, y]), col, hit.Col);
          AssertEquals(Format('(%d,%d) 反查行', [x, y]), row, hit.Row);
          Inc(swept);
        end;
    end;
  // 别让"一个可见单元格都没有"伪装成通过。
  AssertTrue('确实扫到了可见像素', swept > 500);
end;

{ 列头带、行头槽、以及最后一行之后的空白都不是单元格。误报成单元格会导致
  点列头就进入编辑、点空白就选中末行。 }
procedure TTyGridControlTest.TestCellAtRejectsHeaderIndicatorAndBlankSpace;
var
  G: TGridAccess;
  hit: TTyGridHit;
begin
  G := MakeGrid(FForm, [80, 60]);
  G.ShowIndicator := True;
  G.IndicatorWidth := 30;
  G.Header.Height := 24;
  G.DefaultRowHeight := 20;
  G.RowCount := 3;                  // 只有 3 行,下方大片空白

  hit := G.CellAt(50, 10);          // 列头带内
  AssertEquals('列头带不是单元格', Ord(ghpHeader), Ord(hit.Part));

  hit := G.CellAt(10, 40);          // 行头槽内(列头之下)
  AssertEquals('行头槽不是单元格', Ord(ghpIndicator), Ord(hit.Part));

  hit := G.CellAt(50, 24 + 3 * 20 + 5);   // 末行之后的空白
  AssertEquals('末行之后是空白', Ord(ghpNowhere), Ord(hit.Part));
  AssertEquals('空白无列', -1, hit.Col);
  AssertEquals('空白无行', -1, hit.Row);

  hit := G.CellAt(50, 24 + 10);     // 第 0 行,正常单元格
  AssertEquals('正文里是单元格', Ord(ghpCell), Ord(hit.Part));
  AssertEquals('命中第 0 行', 0, hit.Row);
end;

{ 渲染:表面铺底 + 网格线落在每行下沿、每列右缘。
  网格线用纯绿、表面用纯白,方便按像素断言而不必跟抗锯齿较劲(故意关掉圆角与列头)。 }
procedure TTyGridControlTest.TestPaintsSurfaceAndGridLines;
var
  Ctl: TTyStyleController;
  G: TGridAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  px: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; border-radius: 0px; }' +
      'TyGridLine { background: #00FF00; }');
    G := MakeGrid(FForm, [100, 100]);
    G.Controller := Ctl;
    G.Header.Options := G.Header.Options - [hoVisible];   // 无列头,几何最简
    G.DefaultRowHeight := 20;
    G.RowCount := 3;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);
    G.DoRenderTo(Bmp.Canvas, Rect(0, 0, 400, 300), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // 单元格内部 = 表面白。
      px := Reread.GetPixel(50, 10);
      AssertTrue(Format('单元格内部应为表面白 (得到 %d,%d,%d)', [px.red, px.green, px.blue]),
        (px.red > 200) and (px.green > 200) and (px.blue > 200));

      // 第 0 行下沿的横线(行高 20 → 第 19 行像素)。
      px := Reread.GetPixel(50, 19);
      AssertTrue(Format('行下沿应有网格线 (得到 %d,%d,%d)', [px.red, px.green, px.blue]),
        (px.green > 150) and (px.red < 150));

      // 第 0 列右缘的竖线(列宽 100 → 第 99 列像素)。
      px := Reread.GetPixel(99, 10);
      AssertTrue(Format('列右缘应有网格线 (得到 %d,%d,%d)', [px.red, px.green, px.blue]),
        (px.green > 150) and (px.red < 150));
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ 主题没给 TyGrid 背景时必须**什么都不画**(而非崩溃或自己发明外观)——
  与库内其他控件的降级约定一致。

  注意写法:这里必须写一条**存在但不含 background 的** TyGrid 规则,而不是干脆不写。
  因为基层(light.tycss)已经给了 TyGrid 全套键,"不写"只会继承基层、照样画得出来;
  而任何 user 规则都会整体压制该 typeKey 的基层(见 UserHasTypeKey),这才能真正制造
  出"背景缺失"的降级场景。 }
procedure TTyGridControlTest.TestUndefinedGridKeyDrawsNothing;
var
  Ctl: TTyStyleController;
  G: TGridAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  x, y, painted: Integer;
  px: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    // 有 TyGrid 规则(足以压制基层),但**故意不给 background**。
    Ctl.LoadThemeCss('TyGrid { color: #111111; }');
    G := MakeGrid(FForm, [100, 100]);
    G.Controller := Ctl;
    G.DefaultRowHeight := 20;
    G.RowCount := 3;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 100);
    Bmp.Canvas.Brush.Color := clFuchsia;      // 打底洋红:凡被画过就会盖掉
    Bmp.Canvas.FillRect(Rect(0, 0, 200, 100));
    G.DoRenderTo(Bmp.Canvas, Rect(0, 0, 200, 100), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      painted := 0;
      for y := 0 to 99 do
        for x := 0 to 199 do
        begin
          px := Reread.GetPixel(x, y);
          // 洋红 = 未被触碰;凡不是洋红的都是被画上去的。
          if not ((px.red > 200) and (px.blue > 200) and (px.green < 100)) then
            Inc(painted);
        end;
      AssertEquals('没有 TyGrid 规则时一个像素都不该画', 0, painted);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ 基层(themes/light.tycss → DefaultTheme.pas)垫在每一个主题之下。只要基层给了 TyGrid,
  即使某张皮肤根本没写过网格的规则,网格在那张皮肤下也画得出来 —— 这正是本库让新控件
  "在 20 个主题下都能显示"的机制。所以基层缺规则 = 新控件在所有皮肤下集体隐身。

  这条测试不加载任何自定义 CSS,直接用默认控制器渲染。 }
procedure TTyGridControlTest.TestRendersUnderTheDefaultThemeWithNoCustomCss;
var
  G: TGridAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  x, y, painted: Integer;
  px: TBGRAPixel;
begin
  G := MakeGrid(FForm, [100, 100]);
  // 不设 Controller:走全局默认控制器 = 纯基层。
  G.DefaultRowHeight := 20;
  G.RowCount := 3;

  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 100);
    Bmp.Canvas.Brush.Color := clFuchsia;
    Bmp.Canvas.FillRect(Rect(0, 0, 200, 100));
    G.DoRenderTo(Bmp.Canvas, Rect(0, 0, 200, 100), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      painted := 0;
      for y := 0 to 99 do
        for x := 0 to 199 do
        begin
          px := Reread.GetPixel(x, y);
          if not ((px.red > 200) and (px.blue > 200) and (px.green < 100)) then
            Inc(painted);
        end;
      AssertTrue(Format('仅靠基层就应画出网格(实际画了 %d 个像素)', [painted]),
        painted > 5000);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

{ 三个"非正文"区域各画各的 token,读者才能一眼分出哪块不滚动:
  列头带横跨整幅宽度并盖住左上角、行头槽在最左、固定列在行头槽与正文之间。
  正文单元格 resting 透明,所以正文区应透出网格表面本色。 }
procedure TTyGridControlTest.TestHeaderIndicatorAndFixedPanesPaintTheirOwnTokens;
var
  Ctl: TTyStyleController;
  G: TGridAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;

  procedure AssertPixel(AX, AY: Integer; const AWhat: string; AR, AG, AB: Byte);
  var px: TBGRAPixel;
  begin
    px := Reread.GetPixel(AX, AY);
    AssertTrue(Format('%s @(%d,%d) 期望 %d,%d,%d 实得 %d,%d,%d',
      [AWhat, AX, AY, AR, AG, AB, px.red, px.green, px.blue]),
      (Abs(Integer(px.red) - AR) < 40) and (Abs(Integer(px.green) - AG) < 40)
      and (Abs(Integer(px.blue) - AB) < 40));
  end;

begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; border-radius: 0px; }' +
      'TyGridHeader { background: #0000FF; }' +
      'TyGridIndicator { background: #FF00FF; }' +
      'TyGridFixed { background: #FFFF00; }');
    G := MakeGrid(FForm, [80, 100, 100]);
    G.Controller := Ctl;
    G.GridLines := False;            // 关掉格线,免得干扰像素断言
    G.ShowIndicator := True;
    G.IndicatorWidth := 30;
    G.FixedCols := 1;                // 第 0 列(宽 80)冻结 → 冻结带 = 30+80 = 110
    G.Header.Height := 24;
    G.DefaultRowHeight := 20;
    G.RowCount := 5;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);
    G.DoRenderTo(Bmp.Canvas, Rect(0, 0, 400, 300), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      AssertPixel(200, 10, '列头带',       0,   0,   255);
      AssertPixel(10,  10, '左上角归列头', 0,   0,   255);   // 列头横跨整幅、盖住角落
      AssertPixel(10,  50, '行头槽',       255, 0,   255);
      AssertPixel(50,  50, '固定列',       255, 255, 0);
      AssertPixel(200, 50, '正文透出表面', 255, 255, 255);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ ---- TTyDrawGrid ---------------------------------------------------------- }

type
  TDrawGridAccess = class(TTyDrawGrid)
  public
    procedure DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

procedure TDrawGridAccess.DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

{ 之前只验了列头**带**被填色,没验标题文字 —— 于是"列头文字根本没画"这个漏实现
  一直没被发现,实机上看起来就像没有列头。这条直接找墨。 }
procedure TTyGridControlTest.TestHeaderPaintsColumnCaptions;
var
  Ctl: TTyStyleController;
  G: TGridAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  x, y, ink: Integer;
  px: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridHeader { background: #FFFFFF; color: #000000; }');
    G := MakeGrid(FForm, [120, 120]);
    G.Controller := Ctl;
    G.GridLines := False;
    G.Header.Height := 24;
    TTyColumn(G.Header.Columns.Items[0]).Text := 'WWWW';
    G.DefaultRowHeight := 20;
    G.RowCount := 2;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);
    G.DoRenderTo(Bmp.Canvas, Rect(0, 0, 400, 300), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      ink := 0;
      for y := 0 to 23 do            // 只扫列头带
        for x := 0 to 119 do         // 只扫第 0 列
        begin
          px := Reread.GetPixel(x, y);
          if (px.red < 128) and (px.green < 128) and (px.blue < 128) then Inc(ink);
        end;
      AssertTrue(Format('列头必须画出标题文字(墨 %d)', [ink]), ink > 0);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ TTyColumn.ImageIndex / TTyHeader.Images 字段一直存在,但 RenderHeaderSections
  **从不读取** —— 又一处"属性存在却无效"。 }
procedure TTyGridControlTest.TestHeaderDrawsColumnImage;
var
  Ctl: TTyStyleController;
  G: TGridAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  coll: TTyImageCollection;
  imgs: TTyVirtualImageList;
  src: TBGRABitmap;
  x, y, red: Integer;
  px: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  coll := TTyImageCollection.Create(nil);
  imgs := TTyVirtualImageList.Create(nil);
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridHeader { background: #FFFFFF; color: #000000; }');

    { 造一张纯红的图,放进图像集。 }
    src := TBGRABitmap.Create(16, 16, BGRA(255, 0, 0, 255));
    try
      coll.AddBitmap('red', src);
    finally
      src.Free;
    end;
    imgs.Collection := coll;
    { TTyVirtualImageList 靠 Names 暴露条目 —— 不设 Names 则 Count=0、什么都取不到。 }
    imgs.Names.Add('red');

    G := MakeGrid(FForm, [120, 120]);
    G.Controller := Ctl;
    G.GridLines := False;
    G.Header.Height := 24;
    G.Images := imgs;
    TTyColumn(G.Header.Columns.Items[0]).Text := 'Col';
    TTyColumn(G.Header.Columns.Items[0]).ImageIndex := 0;
    G.DefaultRowHeight := 20;
    G.RowCount := 2;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRenderTo(Bmp.Canvas, Rect(0, 0, 400, 300), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      red := 0;
      for y := 0 to 23 do
        for x := 0 to 119 do
        begin
          px := Reread.GetPixel(x, y);
          if (px.red > 180) and (px.green < 100) and (px.blue < 100) then Inc(red);
        end;
      AssertTrue(Format('列头应画出图标(红色像素 %d)', [red]), red > 20);
    finally
      Reread.Free;
    end;
  finally
    imgs.Free;
    coll.Free;
    Bmp.Free;
    Ctl.Free;
  end;
end;

procedure TTyDrawGridTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 600, 400);
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(
    'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; border-radius: 0px; }' +
    'TyGridCell { color: #000000; padding: 0px 4px; }');
  FAsked := 0;
end;

procedure TTyDrawGridTest.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
end;

procedure TTyDrawGridTest.HandleGetCellText(Sender: TObject; ACol, ARow: Integer;
  var AText: string);
begin
  Inc(FAsked);
  AText := FCellText;
end;

{ 计一块区域里的"墨"(明显暗于白底的像素)。 }
function InkIn(ABmp: TBGRABitmap; const R: TRect): Integer;
var
  x, y: Integer;
  px: TBGRAPixel;
begin
  Result := 0;
  for y := R.Top to R.Bottom - 1 do
    for x := R.Left to R.Right - 1 do
    begin
      if (x < 0) or (y < 0) or (x >= ABmp.Width) or (y >= ABmp.Height) then Continue;
      px := ABmp.GetPixel(x, y);
      if (px.red < 128) and (px.green < 128) and (px.blue < 128) then Inc(Result);
    end;
end;

function MakeDrawGrid(AForm: TForm; ACtl: TTyStyleController): TDrawGridAccess;
var
  i: Integer;
  c: TTyColumn;
begin
  Result := TDrawGridAccess.Create(AForm);
  Result.Parent := AForm;
  Result.Controller := ACtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 300);
  for i := 0 to 1 do
  begin
    c := Result.Header.Columns.Add as TTyColumn;
    c.Width := 100;
  end;
  Result.Header.Options := Result.Header.Options - [hoVisible];
  Result.GridLines := False;
  Result.DefaultRowHeight := 20;
  Result.RowCount := 3;
end;

{ 内容由宿主提供:给了文本就画得出墨,给空串就一点墨都没有。
  同时证明控件**真的**去问了宿主,而不是自己编。 }
procedure TTyDrawGridTest.TestPaintsCellTextSuppliedByTheHost;
var
  G: TDrawGridAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  inkWithText, inkWithout: Integer;
begin
  G := MakeDrawGrid(FForm, FCtl);
  G.OnGetCellText := @HandleGetCellText;

  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);

    FCellText := 'W';
    FAsked := 0;
    G.DoRenderTo(Bmp.Canvas, Rect(0, 0, 400, 300), 96);
    AssertTrue('控件确实向宿主要过文本', FAsked > 0);
    Reread := TBGRABitmap.Create(Bmp);
    try
      inkWithText := InkIn(Reread, Rect(0, 0, 100, 20));   // 单元格 (0,0)
    finally
      Reread.Free;
    end;
    AssertTrue(Format('给了文本就该有墨(实得 %d)', [inkWithText]), inkWithText > 0);

    // 换成空串重画:同一块区域应当一点墨都没有。
    FCellText := '';
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRenderTo(Bmp.Canvas, Rect(0, 0, 400, 300), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      inkWithout := InkIn(Reread, Rect(0, 0, 100, 20));
    finally
      Reread.Free;
    end;
    AssertEquals('空文本不应留下任何墨', 0, inkWithout);
  finally
    Bmp.Free;
  end;
end;

{ 虚拟化:一百万行时,控件只应向宿主索取**可视窗口内**那几十行的文本。
  若它老老实实遍历全部行,这条会跑到天荒地老 —— 这正是虚拟化的意义。 }
procedure TTyDrawGridTest.TestOnlyAsksForVisibleRows;
var
  G: TDrawGridAccess;
  Bmp: TBitmap;
begin
  G := MakeDrawGrid(FForm, FCtl);
  G.OnGetCellText := @HandleGetCellText;
  G.RowCount := 1000000;

  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);
    FCellText := 'X';
    FAsked := 0;
    G.DoRenderTo(Bmp.Canvas, Rect(0, 0, 400, 300), 96);
    // 视口 300px / 行高 20 = 15 行,2 列 → 约 32 次;给足余量但必须远小于百万。
    AssertTrue(Format('只该问可视行(实际问了 %d 次)', [FAsked]), FAsked < 200);
    AssertTrue('但确实问了', FAsked > 0);
  finally
    Bmp.Free;
  end;
end;

{ ---- TTyStringGrid -------------------------------------------------------- }

type
  TStrGridAccess = class(TTyStringGrid)
  public
    procedure ClickAt(X, Y: Integer);
    function  PressKey(AKey: Word): Boolean;
    procedure DoRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function ViewportWidth: Integer;
    function ViewportHeight: Integer;
    function MaxScrollY: Integer;
    function DisplayRow(APos: Integer): Integer;
    function RankOf(ARow: Integer): Integer;
    function PressKeyShift(AKey: Word): Boolean;
    procedure PressMouseWithoutRelease(X, Y: Integer);
    procedure MoveMouseTo(X, Y: Integer);
    procedure ReleaseMouse(X, Y: Integer);
    function  ColLeft(ACol: Integer): Integer;
    function  Metrics: TTyGridMetrics;
    function  VisibleRows(out AFirst, ALast: Integer): Boolean;
    procedure ForceUpdateScrollBars;
    function  RowRectAt(APos: Integer): TRect;
    function  GetScrollTop: Integer;
    procedure SetScrollTop(AValue: Integer);
    property ScrollTop: Integer read GetScrollTop write SetScrollTop;
  end;

procedure TStrGridAccess.PressMouseWithoutRelease(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);      { 不 MouseUp —— 停在"按住"状态 }
end;

procedure TStrGridAccess.ForceUpdateScrollBars;
begin
  UpdateScrollBars;
end;

function TStrGridAccess.VisibleRows(out AFirst, ALast: Integer): Boolean;
begin
  Result := TyGridVisibleRows(GridMetrics, AFirst, ALast);
end;

function TStrGridAccess.Metrics: TTyGridMetrics;
begin
  Result := GridMetrics;
end;

function TStrGridAccess.ColLeft(ACol: Integer): Integer;
begin
  Result := ColumnLeftPx(ACol);
end;

procedure TStrGridAccess.MoveMouseTo(X, Y: Integer);
begin
  MouseMove([ssLeft], X, Y);
end;

procedure TStrGridAccess.ReleaseMouse(X, Y: Integer);
begin
  MouseUp(mbLeft, [], X, Y);
end;

function TStrGridAccess.RowRectAt(APos: Integer): TRect;
begin
  Result := TyGridRowRect(APos, GridMetrics);
end;

function TStrGridAccess.GetScrollTop: Integer;
begin
  Result := ScrollY;
end;

procedure TStrGridAccess.SetScrollTop(AValue: Integer);
begin
  ScrollY := AValue;
end;

function TStrGridAccess.PressKeyShift(AKey: Word): Boolean;
var k: Word;
begin
  k := AKey;
  KeyDown(k, [ssShift]);
  Result := k = 0;
end;

function TStrGridAccess.DisplayRow(APos: Integer): Integer;
begin
  Result := DisplayToData(APos);
end;

function TStrGridAccess.RankOf(ARow: Integer): Integer;
begin
  Result := DataToDisplay(ARow);
end;

function TStrGridAccess.ViewportWidth: Integer;
begin
  Result := ViewportW;
end;

function TStrGridAccess.ViewportHeight: Integer;
begin
  Result := ViewportH;
end;

function TStrGridAccess.MaxScrollY: Integer;
begin
  Result := inherited MaxScrollY;
end;

procedure TStrGridAccess.DoRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TStrGridAccess.ClickAt(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
end;

function TStrGridAccess.PressKey(AKey: Word): Boolean;
var k: Word;
begin
  k := AKey;
  KeyDown(k, []);
  Result := k = 0;      { 被消费掉 = 控件处理了它 }
end;

function MakeStrGrid(AForm: TForm; ACtl: TTyStyleController): TStrGridAccess;
var
  i: Integer;
  c: TTyColumn;
begin
  Result := TStrGridAccess.Create(AForm);
  Result.Parent := AForm;
  Result.Controller := ACtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 300);
  for i := 0 to 3 do
  begin
    c := Result.Header.Columns.Add as TTyColumn;
    c.Width := 80;
  end;
  Result.Header.Options := Result.Header.Options - [hoVisible];
  Result.DefaultRowHeight := 20;
  Result.RowCount := 10;
end;

procedure TTyStringGridTest.HandleReadOnlyCol2(Sender: TObject; ACol, ARow: Integer;
  var AKind: TTyGridEditorKind);
begin
  if ACol = 2 then AKind := gekNone else AKind := gekText;
end;

procedure TTyStringGridTest.HandleGetPickList(Sender: TObject; ACol, ARow: Integer;
  AItems: TStrings);
begin
  AItems.Add('甲'); AItems.Add('乙'); AItems.Add('丙');
end;

procedure TTyStringGridTest.HandleTallSecondRow(Sender: TObject; ARow: Integer;
  var AHeight: Integer);
begin
  if ARow = 1 then AHeight := 60;
end;

procedure TTyStringGridTest.HandleDrawCell(Sender: TObject; ACol, ARow: Integer;
  const ARect: TRect; APainter: TTyPainter; var AHandled: Boolean);
begin
  { 接管但什么都不画 —— 这样"控件有没有再画"就能用墨量直接判定。 }
  AHandled := ACol = FTakeOverCol;
end;

procedure TTyStringGridTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 600, 400);
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(
    'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
    'TyGridCell { color: #000000; }');
end;

procedure TTyStringGridTest.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
end;

{ 存储必须是**稀疏**的:写 3 格就只占 3 格,而不是按 行x列 预分配。
  这决定了百万行的表能不能开得起。 }
procedure TTyStringGridTest.TestCellStorageIsSparse;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 1000000;

  AssertEquals('初始不占任何条目', 0, G.StoredCellCount);
  G.Cells[0, 0] := 'a';
  G.Cells[2, 999999] := 'b';
  G.Cells[1, 5] := 'c';
  AssertEquals('只存写过的 3 格', 3, G.StoredCellCount);

  AssertEquals('读回 (0,0)', 'a', G.Cells[0, 0]);
  AssertEquals('读回 (2,999999)', 'b', G.Cells[2, 999999]);
  AssertEquals('没写过的格是空串', '', G.Cells[3, 7]);

  // 写空串 = 删条目,不给空值留位置。
  G.Cells[1, 5] := '';
  AssertEquals('写空串后条目减少', 2, G.StoredCellCount);

  G.ClearCells;
  AssertEquals('清空后不占条目', 0, G.StoredCellCount);
end;

{ 点哪格就选哪格 —— 命中走 CellAt(与绘制同源),所以不会错位。 }
procedure TTyStringGridTest.TestClickMovesTheCursorToTheClickedCell;
var
  G: TStrGridAccess;
  r: TRect;
begin
  G := MakeStrGrid(FForm, FCtl);
  AssertEquals('初始光标列', 0, G.Col);
  AssertEquals('初始光标行', 0, G.Row);

  // 直接取第 2 列第 3 行的可见矩形中心去点 —— 用控件自己的几何,杜绝测试算错。
  r := G.CellVisibleRect(2, 3);
  AssertFalse('该格应当可见', IsRectEmpty(r));
  G.ClickAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);

  AssertEquals('光标跟到点击的列', 2, G.Col);
  AssertEquals('光标跟到点击的行', 3, G.Row);
end;

{ 方向键移动光标并在边界钳住 —— 越界的光标会让绘制与命中失去参照。 }
procedure TTyStringGridTest.TestArrowKeysMoveAndClampTheCursor;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);   // 4 列 x 10 行

  AssertTrue('右键被消费', G.PressKey(VK_RIGHT));
  AssertEquals('右移一列', 1, G.Col);
  AssertTrue('下键被消费', G.PressKey(VK_DOWN));
  AssertEquals('下移一行', 1, G.Row);

  // 左上角钳制:再往左/上不能出界。
  G.PressKey(VK_LEFT); G.PressKey(VK_LEFT);
  G.PressKey(VK_UP);   G.PressKey(VK_UP);
  AssertEquals('列钳在 0', 0, G.Col);
  AssertEquals('行钳在 0', 0, G.Row);

  // 右下角钳制。
  G.PressKey(VK_END);
  AssertEquals('End 到最后一列', 3, G.Col);
  G.PressKey(VK_RIGHT);
  AssertEquals('已在末列,再右仍是末列', 3, G.Col);

  G.Row := 9;
  G.PressKey(VK_DOWN);
  AssertEquals('已在末行,再下仍是末行', 9, G.Row);

  // PageDown 一次跳 10 行,同样受钳。
  G.Row := 0;
  G.PressKey(VK_NEXT);
  AssertEquals('PageDown 受末行钳制', 9, G.Row);
end;

{ 存储里的文本要真的画出来,并且当前单元格要有选中底色。 }
procedure TTyStringGridTest.TestStoredTextRendersAndCursorIsHighlighted;
var
  G: TStrGridAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  px: TBGRAPixel;
  ink: Integer;
  r: TRect;
begin
  FCtl.LoadThemeCss(
    'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
    'TyGridCell { color: #000000; }' +
    'TyGridCell:selected { background: #FF0000; }');
  G := MakeStrGrid(FForm, FCtl);
  G.GridLines := False;
  G.Cells[1, 2] := 'W';
  G.Col := 1;
  G.Row := 2;

  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      r := G.CellVisibleRect(1, 2);
      // 选中底色:该格里应能找到红。
      px := Reread.GetPixel(r.Left + 2, r.Top + 2);
      AssertTrue(Format('当前单元格应有选中底色 (得到 %d,%d,%d)',
        [px.red, px.green, px.blue]), (px.red > 150) and (px.green < 120));
      // 文字:该格里应有暗墨。
      ink := InkIn(Reread, r);
      AssertTrue(Format('存储里的文本应被画出(墨 %d)', [ink]), ink > 0);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

{ 滚动量必须钳在 [0, Max]:超出就会把内容整个滚出视口,留一片空白还回不来。 }
procedure TTyStringGridTest.TestScrollIsClampedToContent;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);   // 4 列 x 80 宽,10 行 x 20 高;视口 400x300
  G.RowCount := 10;

  // 内容 200px 高,正文区 300px → 根本不需要滚,上限为 0。
  AssertEquals('内容比视口矮时不可滚', 0, G.MaxScrollY);
  G.ScrollY := 999;
  AssertEquals('强行设的滚动量被钳成 0', 0, G.ScrollY);

  // 行数拉大到需要滚动。
  G.RowCount := 100;               // 2000px 内容 vs 300px 正文
  AssertEquals('最大纵向滚动 = 内容 - 正文', 2000 - 300, G.MaxScrollY);
  G.ScrollY := 999999;
  AssertEquals('钳到上限', G.MaxScrollY, G.ScrollY);
  G.ScrollY := -50;
  AssertEquals('负值钳到 0', 0, G.ScrollY);

  // 横向:内容 320px(4x80)vs 视口 400px → 不需要滚。
  AssertEquals('内容比视口窄时不可横滚', 0, G.MaxScrollX);
end;

{ 光标走出视口时视口必须跟上,否则按方向键会"把光标走丢"。 }
procedure TTyStringGridTest.TestCursorScrollsItselfIntoView;
var
  G: TStrGridAccess;
  i: Integer;
  vis: TRect;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 100;               // 远多于视口能装下的
  AssertEquals('起始未滚动', 0, G.ScrollY);

  // 一路按 Down 走到第 60 行。
  for i := 1 to 60 do G.PressKey(VK_DOWN);
  AssertEquals('光标到第 60 行', 60, G.Row);
  AssertTrue('视口已跟着滚下去', G.ScrollY > 0);

  // 关键:当前单元格必须真的可见。
  vis := G.CellVisibleRect(G.Col, G.Row);
  AssertFalse('当前单元格必须在可视区内', IsRectEmpty(vis));

  // 再一路按 Up 回到顶部,视口应当滚回 0。
  for i := 1 to 60 do G.PressKey(VK_UP);
  AssertEquals('光标回到第 0 行', 0, G.Row);
  AssertEquals('视口滚回顶部', 0, G.ScrollY);
end;

{ 滚动条只在内容真的装不下时出现,并且它吃掉的那条不能再被内容占用
  (否则最后一行/列会钻到滚动条底下)。 }
procedure TTyStringGridTest.TestScrollBarsAppearOnlyWhenContentOverflows;
var
  G: TStrGridAccess;
  hBefore: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);   // 4 列 x 80 = 320 宽内容;视口 400x300
  G.RowCount := 5;                 // 100px 内容,装得下

  AssertFalse('内容装得下时不该有竖条', G.VScrollBar.Visible);
  AssertFalse('内容装得下时不该有横条', G.HScrollBar.Visible);
  hBefore := G.ViewportHeight;
  AssertEquals('无滚动条时视口高 = 客户区高', G.ClientHeight, hBefore);

  // 行数拉到装不下 → 竖条出现,并从视口宽度里扣走一条。
  G.RowCount := 500;
  AssertTrue('内容超高时应出现竖条', G.VScrollBar.Visible);
  AssertTrue('竖条吃掉了视口宽度', G.ViewportWidth < G.ClientWidth);

  // 竖条的 Max 必须是**最大位置**而非内容高度,否则滑块偏小、拖到底会弹回。
  AssertEquals('竖条 Max = MaxScrollY', G.MaxScrollY, G.VScrollBar.Max);

  // 收回去 → 竖条消失,视口恢复。
  G.RowCount := 5;
  AssertFalse('内容缩回后竖条消失', G.VScrollBar.Visible);
  AssertEquals('视口宽度恢复', G.ClientWidth, G.ViewportWidth);
end;

{ 编辑的基本契约:Enter 写回、Esc 丢弃。 }
procedure TTyStringGridTest.TestEditCommitsOnEnterAndRevertsOnEscape;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.Cells[1, 2] := '原值';
  G.Col := 1; G.Row := 2;

  AssertTrue('能开始编辑', G.BeginEdit);
  AssertTrue('处于编辑态', G.Editing);
  AssertEquals('编辑器载入原值', '原值', G.Editor.Text);

  G.Editor.Text := '改过了';
  G.EndEdit(True);
  AssertFalse('编辑已结束', G.Editing);
  AssertEquals('Enter 提交写回存储', '改过了', G.Cells[1, 2]);

  // Esc 路径:改了但丢弃。
  G.BeginEdit;
  G.Editor.Text := '不要这个';
  G.EndEdit(False);
  AssertEquals('Esc 丢弃,存储不变', '改过了', G.Cells[1, 2]);
end;

{ 只读表、以及编辑器种类为 gekNone 的格,都不该开得起编辑。 }
procedure TTyStringGridTest.TestReadOnlyAndNoneKindBlockEditing;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.Cells[0, 0] := 'x';

  G.ReadOnly := True;
  AssertFalse('只读表开不了编辑', G.BeginEdit);
  AssertFalse('也不该进入编辑态', G.Editing);

  G.ReadOnly := False;
  G.DefaultEditorKind := gekNone;
  AssertFalse('gekNone 的格开不了编辑', G.BeginEdit);

  G.DefaultEditorKind := gekText;
  AssertTrue('恢复后可编辑', G.BeginEdit);
end;

{ 光标一动就必须先提交 —— 否则编辑框会悬在旧单元格上,内容也会写丢。 }
procedure TTyStringGridTest.TestMovingTheCursorCommitsTheOpenEditor;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.Cells[1, 1] := 'A';
  G.Col := 1; G.Row := 1;

  G.BeginEdit;
  G.Editor.Text := 'A2';
  G.PressKey(VK_DOWN);              // 光标下移

  AssertFalse('移动后编辑已结束', G.Editing);
  AssertEquals('移动前的修改被提交', 'A2', G.Cells[1, 1]);
  AssertEquals('光标确实移动了', 2, G.Row);
end;

{ 数值列不能被写进 'abc' —— 总比把垃圾存进金额列强。 }
procedure TTyStringGridTest.TestNumericColumnRejectsNonNumericText;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.DefaultEditorKind := gekNumeric;
  G.Cells[0, 0] := '100';
  G.Col := 0; G.Row := 0;

  G.BeginEdit;
  G.Editor.Text := 'abc';
  G.EndEdit(True);
  AssertEquals('非法数值不写回', '100', G.Cells[0, 0]);

  G.BeginEdit;
  G.Editor.Text := '250.5';
  G.EndEdit(True);
  AssertEquals('合法数值照常写回', '250.5', G.Cells[0, 0]);
end;

{ 排序只置换**显示序**:Cells[列,行] 吃的永远是稳定的数据行,内容不会跟着搬家。
  这条要是破了,排一次序全表数据就串位。 }
procedure TTyStringGridTest.TestSortReordersDisplayButKeepsCellsAddressedByDataRow;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  G.Cells[0, 0] := 'delta';
  G.Cells[0, 1] := 'alpha';
  G.Cells[0, 2] := 'charlie';
  G.Cells[0, 3] := 'bravo';

  G.SortByColumn(0, sdAscending);

  // 数据行寻址不变 —— 第 0 行永远是 delta。
  AssertEquals('数据行 0 仍是 delta', 'delta', G.Cells[0, 0]);
  AssertEquals('数据行 1 仍是 alpha', 'alpha', G.Cells[0, 1]);

  // 变的是显示序:alpha 排到第 0 位。
  AssertEquals('显示第 0 位 = 数据行 1(alpha)', 1, G.DisplayRow(0));
  AssertEquals('显示第 1 位 = 数据行 3(bravo)', 3, G.DisplayRow(1));
  AssertEquals('显示第 2 位 = 数据行 2(charlie)', 2, G.DisplayRow(2));
  AssertEquals('显示第 3 位 = 数据行 0(delta)', 0, G.DisplayRow(3));

  // 正逆映射必须互为逆。
  AssertEquals('数据行 1 显示在第 0 位', 0, G.RankOf(1));
  AssertEquals('数据行 0 显示在第 3 位', 3, G.RankOf(0));

  // 降序反过来。
  G.SortByColumn(0, sdDescending);
  AssertEquals('降序第 0 位 = delta', 0, G.DisplayRow(0));

  // 取消排序回到原始顺序。
  G.SortByColumn(-1, sdAscending);
  AssertEquals('取消排序后恒等', 0, G.DisplayRow(0));
  AssertEquals('取消排序后恒等', 2, G.DisplayRow(2));
end;

{ 光标按数据行记账,所以排序后它仍然盯着**同一条数据**,而不是同一个屏幕位置。 }
procedure TTyStringGridTest.TestCursorFollowsItsDataRowAcrossSort;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  G.Cells[0, 0] := 'delta';
  G.Cells[0, 1] := 'alpha';
  G.Cells[0, 2] := 'charlie';
  G.Cells[0, 3] := 'bravo';

  G.Col := 0; G.Row := 0;                 // 停在 delta 上
  AssertEquals('排序前光标内容', 'delta', G.Cells[G.Col, G.Row]);

  G.SortByColumn(0, sdAscending);

  AssertEquals('光标仍是数据行 0', 0, G.Row);
  AssertEquals('光标盯着的还是 delta', 'delta', G.Cells[G.Col, G.Row]);
  // 但它的显示位置从第 0 位变成了第 3 位。
  AssertEquals('delta 现在显示在第 3 位', 3, G.RankOf(G.Row));
end;

{ 数值列按数值比,不能按文本 —— 否则会得到 '10' < '9'。 }
procedure TTyStringGridTest.TestNumericSortComparesNumbersNotText;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 3;
  G.Cells[0, 0] := '9';
  G.Cells[0, 1] := '10';
  G.Cells[0, 2] := '100';

  G.SortKind := gskText;
  G.SortByColumn(0, sdAscending);
  AssertEquals('文本序:10 最小', 1, G.DisplayRow(0));

  G.SortKind := gskNumber;
  G.SortByColumn(0, sdAscending);
  AssertEquals('数值序:9 最小', 0, G.DisplayRow(0));
  AssertEquals('数值序:100 最大', 2, G.DisplayRow(2));
end;

{ 点列头:升序 → 降序 → 取消。 }
procedure TTyStringGridTest.TestHeaderClickTogglesAscDescThenClears;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 3;
  G.Cells[0, 0] := 'c';  G.Cells[0, 1] := 'a';  G.Cells[0, 2] := 'b';

  G.ToggleSortColumn(0);
  AssertEquals('第一次:升序', Ord(sdAscending), Ord(G.SortDirection));
  AssertEquals('排序列 = 0', 0, G.SortColumn);
  AssertEquals('升序首位是 a', 1, G.DisplayRow(0));

  G.ToggleSortColumn(0);
  AssertEquals('第二次:降序', Ord(sdDescending), Ord(G.SortDirection));
  AssertEquals('降序首位是 c', 0, G.DisplayRow(0));

  G.ToggleSortColumn(0);
  AssertEquals('第三次:取消排序', -1, G.SortColumn);
  AssertEquals('回到原始顺序', 0, G.DisplayRow(0));
end;

{ Shift+方向键拉出矩形选区,普通方向键把选区收回一格。
  选区是"锚点 ↔ 光标"的矩形,所以这两种键的差别就在于**动不动锚点**。 }
procedure TTyStringGridTest.TestShiftArrowsExtendTheRangeAndPlainArrowsCollapseIt;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);    // 4 列 x 10 行
  G.Col := 1; G.Row := 1;
  G.AnchorSelection;

  AssertEquals('起始只选中一格', 1, G.SelectedCellCount);
  AssertTrue('光标那格被选中', G.IsCellSelected(1, 1));
  AssertFalse('邻格未被选中', G.IsCellSelected(2, 1));

  // Shift+右、Shift+下 → 2x2 区域。
  G.PressKeyShift(VK_RIGHT);
  G.PressKeyShift(VK_DOWN);
  AssertEquals('拉出 2x2 = 4 格', 4, G.SelectedCellCount);
  AssertTrue('左上角在选区内', G.IsCellSelected(1, 1));
  AssertTrue('右下角在选区内', G.IsCellSelected(2, 2));
  AssertFalse('区域外不在选区', G.IsCellSelected(3, 2));

  // 普通方向键 → 锚点跟着走,选区收回一格。
  G.PressKey(VK_DOWN);
  AssertEquals('普通方向键把选区收回一格', 1, G.SelectedCellCount);
  AssertTrue('只剩光标那格', G.IsCellSelected(G.Col, G.Row));
end;

{ 真实规模的排序必须**很快**。此前的排序测试只有 3-4 行,完全掩盖了两个 O(n) 问题:
  ① 单元格存储用 TStringList.Values 查找是**线性扫描**;② 插入排序是 O(n^2)。
  两者相乘 → 200 行就能把界面卡死(用户实机点列头即挂)。
  这条用 1000 行 x 6 列压出来,慢实现根本跑不完。 }
procedure TTyStringGridTest.TestSortingRealisticGridIsFast;
var
  G: TStrGridAccess;
  r, c: Integer;
  t0: TDateTime;
  ms: Int64;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 1000;
  for r := 0 to 999 do
    for c := 0 to 3 do
      G.Cells[c, r] := Format('v%d-%d', [c, (r * 7) mod 1000]);
  AssertEquals('已填满', 4000, G.StoredCellCount);

  t0 := Now;
  G.SortByColumn(1, sdAscending);
  ms := MilliSecondsBetween(Now, t0);

  { 宽松到 5 秒:哈希存储 + O(n log n) 排序实测在几十毫秒级,
    而线性存储 + 插入排序在这个规模要几分钟 —— 差距足够大,不会误判。 }
  AssertTrue(Format('1000 行排序应在 5 秒内完成(实测 %d ms)', [ms]), ms < 5000);

  { 顺带验证排序真的生效了。 }
  AssertTrue('排序确实产生了置换',
    (G.DisplayRow(0) <> 0) or (G.DisplayRow(1) <> 1));
end;

{ 排序**不该**把视口拽去追光标那条记录。用户看着第一屏点排序,期望看到的是
  "排序后排在最前的那些行",而不是被拖到旧的第一条现在跑到的位置。
  光标仍然按数据行记账(不跑位),但**视口原地不动**。 }
procedure TTyStringGridTest.TestSortKeepsTheViewportWhereItWas;
var
  G: TStrGridAccess;
  r: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 500;
  for r := 0 to 499 do
    G.Cells[0, r] := Format('%04d', [(r * 37) mod 500]);   // 打乱

  G.Col := 0; G.Row := 0;
  AssertEquals('起始在顶部', 0, G.ScrollTop);

  G.SortByColumn(0, sdAscending);
  AssertEquals('排序后视口仍在顶部', 0, G.ScrollTop);

  // 从中间某处排序,视口同样原地不动。
  G.ScrollTop := 1000;
  AssertEquals('先滚到中间', 1000, G.ScrollTop);
  G.SortByColumn(0, sdDescending);
  AssertEquals('再次排序后视口没被拽走', 1000, G.ScrollTop);
end;

{ 任何**程序性**滚动(滚轮 / 键盘跟随 / ScrollIntoView)都必须把滚动条滑块同步过去,
  否则内容滚了、滑块还停在原处 —— 滑块位置与实际视口对不上。 }
procedure TTyStringGridTest.TestProgrammaticScrollSyncsTheScrollBarThumb;
var
  G: TStrGridAccess;
  i: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 500;                 // 足够长,竖条必然出现
  AssertTrue('竖条应出现', G.VScrollBar.Visible);
  AssertEquals('起始滑块在 0', 0, G.VScrollBar.Position);

  // 直接设滚动量。
  G.ScrollTop := 640;
  AssertEquals('滑块跟上程序性滚动', G.ScrollTop, G.VScrollBar.Position);

  // 键盘把光标带出视口 → 视口跟随 → 滑块也必须跟上。
  G.Col := 0; G.Row := 0; G.ScrollTop := 0;
  for i := 1 to 40 do G.PressKey(VK_DOWN);
  AssertTrue('视口已跟随光标滚动', G.ScrollTop > 0);
  AssertEquals('滑块与视口一致', G.ScrollTop, G.VScrollBar.Position);
end;

{ 列过滤把不匹配的行从**显示序**里拿掉;数据本身一格都不动。 }
procedure TTyStringGridTest.TestColumnFilterHidesNonMatchingRows;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 5;
  G.Cells[0, 0] := '北京';  G.Cells[0, 1] := '上海';  G.Cells[0, 2] := '北海';
  G.Cells[0, 3] := '广州';  G.Cells[0, 4] := '北川';

  AssertEquals('未过滤时全部可见', 5, G.VisibleRowCount);

  G.SetColumnFilter(0, '北');
  AssertEquals('只剩 3 行匹配', 3, G.VisibleRowCount);
  AssertEquals('显示第 0 位 = 数据行 0', 0, G.DisplayRow(0));
  AssertEquals('显示第 1 位 = 数据行 2', 2, G.DisplayRow(1));
  AssertEquals('显示第 2 位 = 数据行 4', 4, G.DisplayRow(2));

  // 数据一格没动。
  AssertEquals('被过滤掉的行数据仍在', '上海', G.Cells[0, 1]);
  AssertEquals('RowCount 不变', 5, G.RowCount);

  // 大小写不敏感 + 清除过滤。
  G.SetColumnFilter(0, '');
  AssertEquals('清除后全部回来', 5, G.VisibleRowCount);
end;

{ 过滤与排序叠加:先过滤再排序,且 Cells 仍按数据行寻址。 }
procedure TTyStringGridTest.TestFilterAndSortComposeAndCellsStayAddressable;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 5;
  G.Cells[0, 0] := 'b-x';  G.Cells[0, 1] := 'a-y';  G.Cells[0, 2] := 'c-x';
  G.Cells[0, 3] := 'd-y';  G.Cells[0, 4] := 'a-x';

  G.SetColumnFilter(0, '-x');          // 留下 0,2,4
  AssertEquals('过滤后 3 行', 3, G.VisibleRowCount);

  G.SortByColumn(0, sdAscending);      // a-x(4), b-x(0), c-x(2)
  AssertEquals('过滤+排序后仍是 3 行', 3, G.VisibleRowCount);
  AssertEquals('首位是 a-x(数据行 4)', 4, G.DisplayRow(0));
  AssertEquals('次位是 b-x(数据行 0)', 0, G.DisplayRow(1));
  AssertEquals('末位是 c-x(数据行 2)', 2, G.DisplayRow(2));

  AssertEquals('内容仍按数据行寻址', 'a-y', G.Cells[0, 1]);
end;

{ 被过滤掉的行没有显示位置(-1),它的单元格矩形必须是空的 ——
  否则会在屏幕上画出一个"不存在的行",或者被点中。 }
procedure TTyStringGridTest.TestFilteredOutRowHasNoDisplayPosition;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 3;
  G.Cells[0, 0] := 'keep';  G.Cells[0, 1] := 'drop';  G.Cells[0, 2] := 'keep';

  G.SetColumnFilter(0, 'keep');
  AssertEquals('数据行 1 被过滤掉,无显示位置', -1, G.RankOf(1));
  AssertTrue('被过滤行的可见矩形为空', IsRectEmpty(G.CellVisibleRect(0, 1)));
  AssertFalse('保留行的矩形非空', IsRectEmpty(G.CellVisibleRect(0, 0)));
end;

{ 选区导出成制表符文本(Excel 剪贴板格式),且按**显示序** —— 所见即所得。 }
procedure TTyStringGridTest.TestSelectionExportsAsTabbedTextInDisplayOrder;
var
  G: TStrGridAccess;
  txt: string;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 3;
  G.Cells[0, 0] := 'c1'; G.Cells[1, 0] := 'c2';
  G.Cells[0, 1] := 'a1'; G.Cells[1, 1] := 'a2';
  G.Cells[0, 2] := 'b1'; G.Cells[1, 2] := 'b2';

  G.Col := 0; G.Row := 0; G.AnchorSelection;
  G.Col := 1; G.Row := 2;               // 选中 2 列 x 3 行
  txt := G.SelectionAsText;
  AssertTrue('含制表符分隔', Pos('c1' + #9 + 'c2', txt) > 0);
  AssertTrue('含第三行', Pos('b1' + #9 + 'b2', txt) > 0);

  // 排序后再导出 —— 顺序必须跟着显示走,而不是数据行号。
  G.SortByColumn(0, sdAscending);       // a1, b1, c1
  G.Col := 0; G.Row := 1; G.AnchorSelection;   // 数据行 1 = a1,现在显示在第 0 位
  G.Col := 1; G.Row := 0;                      // 数据行 0 = c1,显示在第 2 位
  txt := G.SelectionAsText;
  AssertTrue('导出以 a1 开头(显示序首行)', Pos('a1', txt) < Pos('c1', txt));
end;

{ 粘贴从光标处铺开,只读列跳过不覆盖。 }
procedure TTyStringGridTest.TestPasteFillsFromCursorAndSkipsReadOnlyColumns;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  G.Col := 1; G.Row := 1;

  G.PasteFromText('x1' + #9 + 'x2' + LineEnding + 'y1' + #9 + 'y2' + LineEnding);
  AssertEquals('粘到光标列', 'x1', G.Cells[1, 1]);
  AssertEquals('粘到右边一列', 'x2', G.Cells[2, 1]);
  AssertEquals('第二行也粘上', 'y1', G.Cells[1, 2]);

  // 只读列不该被覆盖。
  G.ClearCells;
  G.Cells[2, 1] := '不许改';
  G.DefaultEditorKind := gekText;
  G.OnGetEditorKind := @HandleReadOnlyCol2;
  G.Col := 1; G.Row := 1;
  G.PasteFromText('p1' + #9 + 'p2' + LineEnding);
  AssertEquals('可写列被粘上', 'p1', G.Cells[1, 1]);
  AssertEquals('只读列保持原值', '不许改', G.Cells[2, 1]);
end;

{ CSV 必须能原样往返:含分隔符、引号、换行的字段都要正确加引号并读回。 }
procedure TTyStringGridTest.TestCsvRoundTripsQuotesDelimitersAndNewlines;
var
  G, G2: TStrGridAccess;
  csv: string;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 2;
  TTyColumn(G.Header.Columns.Items[0]).Text := '名称';
  TTyColumn(G.Header.Columns.Items[1]).Text := '备注';
  G.Cells[0, 0] := '普通';
  G.Cells[1, 0] := '含,逗号';
  G.Cells[0, 1] := '含"引号"';
  G.Cells[1, 1] := '含' + LineEnding + '换行';

  csv := G.SaveToCSVText(',');

  G2 := MakeStrGrid(FForm, FCtl);
  G2.LoadFromCSVText(csv, ',');

  AssertEquals('列标题读回', '名称', TTyColumn(G2.Header.Columns.Items[0]).Text);
  AssertEquals('普通字段', '普通', G2.Cells[0, 0]);
  AssertEquals('含逗号的字段', '含,逗号', G2.Cells[1, 0]);
  AssertEquals('含引号的字段', '含"引号"', G2.Cells[0, 1]);
end;

{ 导出走显示序:被过滤掉的行不出现,排序后的次序被保留。 }
procedure TTyStringGridTest.TestCsvExportFollowsFilterAndSort;
var
  G: TStrGridAccess;
  csv: string;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  G.Cells[0, 0] := 'keep-c'; G.Cells[0, 1] := 'drop';
  G.Cells[0, 2] := 'keep-a'; G.Cells[0, 3] := 'keep-b';

  G.SetColumnFilter(0, 'keep');
  G.SortByColumn(0, sdAscending);
  csv := G.SaveToCSVText(',');

  AssertEquals('被过滤的行不出现', 0, Pos('drop', csv));
  AssertTrue('按排序后的次序导出',
    (Pos('keep-a', csv) < Pos('keep-b', csv)) and (Pos('keep-b', csv) < Pos('keep-c', csv)));
end;

{ 勾选框列:点方块切换、空格键也切换,且**不弹文本编辑器**。 }
procedure TTyStringGridTest.TestCheckBoxCellTogglesOnClickAndSpace;
var
  G: TStrGridAccess;
  box: TRect;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 3;
  G.DefaultEditorKind := gekCheckBox;
  G.Col := 0; G.Row := 0;

  AssertFalse('初始未勾选', G.CellChecked(0, 0));

  box := G.CheckBoxRect(0, 0);
  AssertFalse('勾选框槽非空', IsRectEmpty(box));
  G.ClickAt((box.Left + box.Right) div 2, (box.Top + box.Bottom) div 2);
  AssertTrue('点方块后勾上', G.CellChecked(0, 0));
  AssertFalse('勾选框不该弹出文本编辑器', G.Editing);

  G.ClickAt((box.Left + box.Right) div 2, (box.Top + box.Bottom) div 2);
  AssertFalse('再点一次取消勾选', G.CellChecked(0, 0));

  // 空格键。
  G.PressKey(VK_SPACE);
  AssertTrue('空格键勾上', G.CellChecked(0, 0));

  { F2/双击也走 BeginEdit —— 勾选框在那条路径上同样必须"切换而非弹编辑器",
    否则会冒出一个让用户手打 '1'/'0' 的文本框。 }
  G.Col := 0; G.Row := 2;
  AssertFalse('第 2 行初始未勾选', G.CellChecked(0, 2));
  AssertTrue('BeginEdit 在勾选框上返回成功', G.BeginEdit);
  AssertTrue('BeginEdit 直接把它勾上了', G.CellChecked(0, 2));
  AssertFalse('且没有进入编辑态', G.Editing);
end;

{ 读的时候宽松(外部系统真值写法五花八门),写回时收敛成 '1'/''。
  注意 '是' 这类**本地化**真值由 TyGridCheckedWord 驱动(从 resourcestring 播种,英文基线为空),
  所以这里显式设置它来模拟中文语境 —— 不能假设运行时加载了哪个 .po。 }
procedure TTyStringGridTest.TestCheckBoxReadsLooseTruthyValuesButWritesCanonical;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 6;
  G.DefaultEditorKind := gekCheckBox;
  TyGridCheckedWord := '是';        { 模拟中文语境;英文基线下该词为空 }
  G.Cells[0, 0] := 'true';  G.Cells[0, 1] := 'YES';  G.Cells[0, 2] := '是';
  G.Cells[0, 3] := '1';     G.Cells[0, 4] := '0';    G.Cells[0, 5] := '';

  AssertTrue('true 算勾上', G.CellChecked(0, 0));
  AssertTrue('YES 算勾上(不分大小写)', G.CellChecked(0, 1));
  AssertTrue('本地化真值词算勾上', G.CellChecked(0, 2));

  { 清掉本地化词后,它就不该再算真 —— 证明这条判定确实由 resourcestring 驱动。 }
  TyGridCheckedWord := '';
  AssertFalse('本地化词为空时不再认它', G.CellChecked(0, 2));
  AssertTrue('通用真值不受影响', G.CellChecked(0, 0));
  TyGridCheckedWord := '是';
  AssertTrue('1 算勾上', G.CellChecked(0, 3));
  AssertFalse('0 不算', G.CellChecked(0, 4));
  AssertFalse('空 不算', G.CellChecked(0, 5));

  // 写回统一。
  G.ToggleCellChecked(0, 4);
  AssertEquals('勾上写成 1', '1', G.Cells[0, 4]);
  G.ToggleCellChecked(0, 0);
  AssertEquals('取消写成空串', '', G.Cells[0, 0]);
end;

{ 下拉编辑器:从候选里选一个,选中即提交。 }
procedure TTyStringGridTest.TestPickListEditorCommitsTheChosenItem;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 3;
  G.DefaultEditorKind := gekPickList;
  G.OnGetPickList := @HandleGetPickList;
  G.Cells[0, 1] := '乙';
  G.Col := 0; G.Row := 1;

  AssertTrue('能开下拉编辑器', G.BeginEdit);
  AssertTrue('处于编辑态', G.Editing);
  AssertEquals('候选已填充', 3, G.PickEditor.Items.Count);
  AssertEquals('定位到当前值', 1, G.PickEditor.ItemIndex);

  G.PickEditor.ItemIndex := 2;
  G.EndEdit(True);
  AssertEquals('提交选中项', '丙', G.Cells[0, 1]);
end;

{ 聚合只统计**通过过滤的行** —— 筛完总计必须跟着变,否则汇总带就是骗人的。 }
procedure TTyStringGridTest.TestAggregatesCountOnlyVisibleRows;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  G.Cells[0, 0] := 'a'; G.Cells[1, 0] := '10';
  G.Cells[0, 1] := 'b'; G.Cells[1, 1] := '20';
  G.Cells[0, 2] := 'a'; G.Cells[1, 2] := '30';
  G.Cells[0, 3] := 'b'; G.Cells[1, 3] := '40';

  G.SetColumnAggregate(1, gagSum);
  AssertEquals('未过滤:合计 100', 100, Round(G.AggregateValue(1)));

  G.SetColumnFilter(0, 'a');
  AssertEquals('筛掉一半后合计只剩 40', 40, Round(G.AggregateValue(1)));

  G.SetColumnAggregate(1, gagCount);
  AssertEquals('计数也只算可见行', 2, Round(G.AggregateValue(1)));

  G.SetColumnAggregate(1, gagAvg);
  AssertEquals('均值 = (10+30)/2', 20, Round(G.AggregateValue(1)));

  G.SetColumnAggregate(1, gagMax);
  AssertEquals('最大 30', 30, Round(G.AggregateValue(1)));
  G.SetColumnAggregate(1, gagMin);
  AssertEquals('最小 10', 10, Round(G.AggregateValue(1)));
end;

{ 非数值格必须跳过,不能当 0 参与统计 —— 那会把均值算歪。 }
procedure TTyStringGridTest.TestAggregatesSkipNonNumericCells;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  G.Cells[0, 0] := '10';
  G.Cells[0, 1] := '待定';      // 非数值
  G.Cells[0, 2] := '';          // 空
  G.Cells[0, 3] := '30';

  G.SetColumnAggregate(0, gagSum);
  AssertEquals('合计只算两个数值格', 40, Round(G.AggregateValue(0)));
  G.SetColumnAggregate(0, gagAvg);
  AssertEquals('均值按 2 个有效值算,不是 4', 20, Round(G.AggregateValue(0)));
end;

{ 合并:基准格跨满整区,被覆盖的格没有自己的矩形(否则区内会画出格线与文字)。 }
procedure TTyStringGridTest.TestMergedBaseCellSpansAndCoveredCellsHaveNoRect;
var
  G: TStrGridAccess;
  baseR, oneR: TRect;
begin
  G := MakeStrGrid(FForm, FCtl);   // 4 列 x 80 宽,行高 20
  G.RowCount := 5;

  oneR := G.CellRect(1, 1);
  G.MergeCells(1, 1, 2, 2);        // 从 (1,1) 起跨 2 列 2 行
  baseR := G.CellRect(1, 1);

  AssertTrue('合并后基准格更宽', baseR.Right - baseR.Left > oneR.Right - oneR.Left);
  AssertTrue('合并后基准格更高', baseR.Bottom - baseR.Top > oneR.Bottom - oneR.Top);
  AssertEquals('宽度 = 两列之和', 160, baseR.Right - baseR.Left);
  AssertEquals('高度 = 两行之和', 40, baseR.Bottom - baseR.Top);

  AssertTrue('被覆盖的 (2,1) 没有矩形', IsRectEmpty(G.CellRect(2, 1)));
  AssertTrue('被覆盖的 (1,2) 没有矩形', IsRectEmpty(G.CellRect(1, 2)));
  AssertTrue('被覆盖的 (2,2) 没有矩形', IsRectEmpty(G.CellRect(2, 2)));
  AssertFalse('区外的 (3,1) 不受影响', IsRectEmpty(G.CellRect(3, 1)));

  G.UnmergeCells(1, 1);
  AssertFalse('取消合并后 (2,1) 恢复', IsRectEmpty(G.CellRect(2, 1)));
end;

{ 点合并区里的任何位置,都应落在基准格上 —— 否则会选中一个不存在的格。 }
procedure TTyStringGridTest.TestClickInsideMergedAreaLandsOnTheBaseCell;
var
  G: TStrGridAccess;
  r: TRect;
  hit: TTyGridHit;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 5;
  G.MergeCells(1, 1, 2, 2);

  r := G.CellVisibleRect(1, 1);
  AssertFalse('基准格可见', IsRectEmpty(r));

  // 点在合并区的右下角(几何上属于原来的 (2,2))。
  hit := G.CellAt(r.Right - 3, r.Bottom - 3);
  AssertEquals('命中归到基准列', 1, hit.Col);
  AssertEquals('命中归到基准行', 1, hit.Row);
end;

{ 分组:显示序里插入**合成分组行**,每组带成员计数;数据行一格不动。 }
procedure TTyStringGridTest.TestGroupingInsertsSyntheticRowsAndCountsMembers;
var
  G: TStrGridAccess;
  gi: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 5;
  G.Cells[0, 0] := '华东'; G.Cells[0, 1] := '华北'; G.Cells[0, 2] := '华东';
  G.Cells[0, 3] := '华北'; G.Cells[0, 4] := '华东';

  G.GroupByColumn(0);
  AssertEquals('分成 2 组', 2, G.GroupCount);
  // 5 个数据行 + 2 个分组行 = 7 个显示位置
  AssertEquals('显示序含分组行', 7, G.VisibleRowCount);

  AssertTrue('第 0 个显示位置是分组行', G.IsGroupRow(0, gi));
  { 不假设哪组排在前(取决于字符序),按分组值找。 }
  for gi := 0 to G.GroupCount - 1 do
    if G.GroupInfo(gi).Key = '华东' then
      AssertEquals('华东组 3 条', 3, G.GroupInfo(gi).Count)
    else if G.GroupInfo(gi).Key = '华北' then
      AssertEquals('华北组 2 条', 2, G.GroupInfo(gi).Count);

  G.UngroupRows;
  AssertEquals('取消分组后回到 5 行', 5, G.VisibleRowCount);
  AssertEquals('数据一格没动', '华东', G.Cells[0, 0]);
end;

{ 折叠:组内行退出显示序,但分组行还在(否则用户就展不开了)。 }
procedure TTyStringGridTest.TestCollapsingAGroupHidesItsRowsButKeepsTheHeader;
var
  G: TStrGridAccess;
  gi: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  G.Cells[0, 0] := 'A'; G.Cells[0, 1] := 'B';
  G.Cells[0, 2] := 'A'; G.Cells[0, 3] := 'B';
  G.GroupByColumn(0);
  AssertEquals('展开时 4 数据行 + 2 分组行', 6, G.VisibleRowCount);

  G.IsGroupRow(0, gi);
  G.ToggleGroup(gi);
  AssertEquals('折叠一组后少 2 行', 4, G.VisibleRowCount);
  AssertTrue('分组行仍在', G.IsGroupRow(0, gi));
  AssertTrue('该组标记为折叠', G.GroupInfo(gi).Collapsed);

  G.ToggleGroup(gi);
  AssertEquals('展开后恢复', 6, G.VisibleRowCount);
end;

{ 折叠状态按**分组值**记账,重排后组号变了也不会张冠李戴。 }
procedure TTyStringGridTest.TestCollapseStateSurvivesResort;
var
  G: TStrGridAccess;
  gi, i: Integer;
  collapsedKey: string;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  G.Cells[0, 0] := 'A'; G.Cells[0, 1] := 'B';
  G.Cells[0, 2] := 'A'; G.Cells[0, 3] := 'B';
  G.GroupByColumn(0);

  G.IsGroupRow(0, gi);
  collapsedKey := G.GroupInfo(gi).Key;
  G.ToggleGroup(gi);
  AssertTrue('已折叠', G.GroupInfo(gi).Collapsed);

  // 反向排序 → 组的先后顺序颠倒,组号跟着变。
  G.SortByColumn(0, sdDescending);

  // 找到同名那一组,它必须仍然是折叠的。
  for i := 0 to G.GroupCount - 1 do
    if G.GroupInfo(i).Key = collapsedKey then
      AssertTrue('重排后同名组仍折叠', G.GroupInfo(i).Collapsed);
end;

{ 分组行不是单元格 —— 点它不该选中什么、更不该开编辑。 }
procedure TTyStringGridTest.TestGroupRowIsNotACell;
var
  G: TStrGridAccess;
  r: TRect;
  hit: TTyGridHit;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 2;
  G.Cells[0, 0] := 'A'; G.Cells[0, 1] := 'A';
  G.GroupByColumn(0);

  r := G.RowRectAt(0);              // 第 0 个显示位置 = 分组行
  hit := G.CellAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  AssertEquals('分组行不是单元格', Ord(ghpNowhere), Ord(hit.Part));
  AssertEquals('也没有行号', -1, hit.Row);
end;

{ 勾选框的样子**只由该格勾没勾决定**,不能掺网格的瞬时状态。
  此前把网格的 CurrentStates 传进样式解析,鼠标一按下网格进 :active,
  满屏未勾选的框会集体闪成实心 —— 真机上肉眼可见,单测却完全看不到。
  这条用"按下鼠标期间重绘"来复现。 }
procedure TTyStringGridTest.TestCheckBoxLookIgnoresGridTransientStates;
var
  G: TStrGridAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  box: TRect;
  inkRest, inkPressed: Integer;

  function InkInBox: Integer;
  begin
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      Result := InkIn(Reread, box);
    finally
      Reread.Free;
    end;
  end;

begin
  FCtl.LoadThemeCss(
    'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
    'TyGridCheckBox { background: #FFFFFF; border-color: #000000; border-width: 1px; }' +
    'TyGridCheckBox:selected { background: #000000; color: #FFFFFF; }' +
    { 关键:给 :active 一个**明显不同**的样子。若实现误把网格的瞬时状态掺进来,
      鼠标按下时未勾选的框就会解析到这条、变成实心 —— 正是真机上看到的闪烁。 }
    'TyGridCheckBox:active { background: #000000; }');
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 3;
  G.GridLines := False;
  G.DefaultEditorKind := gekCheckBox;
  // 全部保持未勾选。
  box := G.CheckBoxRect(0, 1);
  AssertFalse('勾选框槽非空', IsRectEmpty(box));

  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);
    inkRest := InkInBox;

    { 模拟"鼠标按在网格上"的那一刻重绘 —— 网格自身进入 active/focus 态。 }
    G.PressMouseWithoutRelease(5, 5);
    inkPressed := InkInBox;

    AssertEquals('未勾选的框在网格被按下时不能改变外观',
      inkRest, inkPressed);
  finally
    Bmp.Free;
  end;
end;

{ 进度条填充宽度必须随值走。此前填充用的 token 名写错(TyProgressBarFill,
  真实的键是 TyProgressFill),于是填充从来没画过 —— 改值毫无动静。 }
procedure TTyStringGridTest.TestProgressFillWidthTracksTheValue;
var
  G: TStrGridAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  r: TRect;

  function FillPixels(const AValue: string): Integer;
  var x, y: Integer; px: TBGRAPixel;
  begin
    G.Cells[0, 0] := AValue;
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      Result := 0;
      for y := r.Top to r.Bottom - 1 do
        for x := r.Left to r.Right - 1 do
        begin
          px := Reread.GetPixel(x, y);
          if (px.red > 200) and (px.green < 100) and (px.blue < 100) then Inc(Result);
        end;
    finally
      Reread.Free;
    end;
  end;

var
  at20, at80: Integer;
begin
  FCtl.LoadThemeCss(
    'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
    'TyGridProgress { background: #EEEEEE; }' +
    'TyGridProgressFill { background: #FF0000; }');
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 2;
  G.GridLines := False;
  G.DefaultCellDisplay := gcdProgress;
  r := G.CellVisibleRect(0, 0);
  AssertFalse('单元格可见', IsRectEmpty(r));

  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);
    at20 := FillPixels('20');
    at80 := FillPixels('80');
    AssertTrue(Format('20%% 时应有填充(实得 %d)', [at20]), at20 > 0);
    AssertTrue(Format('80%% 的填充应明显多于 20%%(%d vs %d)', [at80, at20]),
      at80 > at20 * 2);
  finally
    Bmp.Free;
  end;
end;

{ 列头下拉的候选必须来自**全部数据行**,而不是当前显示序 ——
  否则一旦筛掉某个值,它就再也不出现在候选里,用户永远选不回来。 }
procedure TTyStringGridTest.TestDistinctValuesIgnoreThisColumnsOwnFilter;
var
  G: TStrGridAccess;
  vals: TStringList;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  G.Cells[0, 0] := '甲'; G.Cells[0, 1] := '乙';
  G.Cells[0, 2] := '甲'; G.Cells[0, 3] := '丙';

  vals := TStringList.Create;
  try
    G.DistinctColumnValues(0, vals);
    AssertEquals('去重后 3 个候选', 3, vals.Count);

    // 只留"甲"之后,候选仍须是 3 个 —— 否则选不回"乙""丙"。
    vals.Clear; vals.Add('甲');
    G.SetColumnValueFilter(0, vals);
    AssertEquals('过滤生效', 2, G.VisibleRowCount);

    vals.Clear;
    G.DistinctColumnValues(0, vals);
    AssertEquals('候选不受本列过滤影响,仍是 3 个', 3, vals.Count);
  finally
    vals.Free;
  end;
end;

{ 值集合过滤:只保留勾中的值;传空即清除。 }
procedure TTyStringGridTest.TestValueFilterKeepsOnlyCheckedValues;
var
  G: TStrGridAccess;
  vals, back: TStringList;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 5;
  G.Cells[0, 0] := 'A'; G.Cells[0, 1] := 'B'; G.Cells[0, 2] := 'C';
  G.Cells[0, 3] := 'A'; G.Cells[0, 4] := 'B';

  vals := TStringList.Create;
  back := TStringList.Create;
  try
    vals.Add('A'); vals.Add('C');
    G.SetColumnValueFilter(0, vals);
    AssertEquals('只留 A 与 C = 3 行', 3, G.VisibleRowCount);

    // 回填:已生效的集合能读回来(下拉重开时要靠它回勾)。
    G.ColumnValueFilter(0, back);
    AssertEquals('回读到 2 个值', 2, back.Count);
    AssertTrue('含 A', back.IndexOf('A') >= 0);
    AssertTrue('含 C', back.IndexOf('C') >= 0);

    G.SetColumnValueFilter(0, nil);
    AssertEquals('清除后全部回来', 5, G.VisibleRowCount);
  finally
    vals.Free;
    back.Free;
  end;
end;

{ 拖列头右边缘改列宽。分隔条必须优先于列体 —— 边缘那几像素上用户想的是改宽,不是排序。 }
procedure TTyStringGridTest.TestHeaderDividerDragResizesTheColumn;
var
  G: TStrGridAccess;
  edge, w0: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.Header.Options := G.Header.Options + [hoVisible, hoColumnResize];
  G.Header.Height := 24;
  w0 := TTyColumn(G.Header.Columns.Items[0]).Width;
  edge := G.ColLeft(0) + w0;

  G.PressMouseWithoutRelease(edge, 10);      // 按在分隔条上
  G.MoveMouseTo(edge + 40, 10);
  G.ReleaseMouse(edge + 40, 10);

  AssertEquals('列宽增加了 40', w0 + 40, TTyColumn(G.Header.Columns.Items[0]).Width);
end;

{ 拖列头把列换位。必须越过阈值才算数,否则点一下列头(手抖一两像素)就把列挪了。 }
procedure TTyStringGridTest.TestHeaderDragReordersColumnsPastAThreshold;
var
  G: TStrGridAccess;
  c0, c1: TTyColumn;
  p0: Cardinal;
begin
  G := MakeStrGrid(FForm, FCtl);
  { 关掉 hoColumnResize:否则列边缘那几像素会被分隔条抢走,测不到拖动路径。 }
  G.Header.Options := (G.Header.Options - [hoColumnResize]) + [hoVisible, hoDrag];
  G.Header.Height := 24;
  c0 := TTyColumn(G.Header.Columns.Items[0]);
  c1 := TTyColumn(G.Header.Columns.Items[1]);
  c0.Options := c0.Options + [coDraggable];
  p0 := c0.Position;

  { 关键:微动必须**跨到另一列**才检验得到阈值 —— 在同一列里挪几像素本来就不会重排,
    那样的测试对阈值是盲的(第一版就是这么写的,变异没抓住)。
    这里从第 0 列右端 5px 跨进第 1 列,位移 < 阈值 8px。 }
  G.PressMouseWithoutRelease(G.ColLeft(1) - 2, 10);
  G.MoveMouseTo(G.ColLeft(1) + 3, 10);
  G.ReleaseMouse(G.ColLeft(1) + 3, 10);
  AssertEquals('跨列但位移不足阈值 → 不重排', p0, c0.Position);

  // 拖到第 1 列上:应当换位。
  G.PressMouseWithoutRelease(G.ColLeft(0) + 20, 10);
  G.MoveMouseTo(G.ColLeft(1) + 20, 10);
  G.ReleaseMouse(G.ColLeft(1) + 20, 10);
  AssertTrue('拖过阈值后位置变了', c0.Position <> p0);
end;

{ 逐行行高:接了 OnGetRowHeight 就启用可变行高 —— 前面行变高,后面的行整体下移,
  且点击命中必须跟着走(几何与命中同源)。 }
procedure TTyStringGridTest.TestVariableRowHeightsShiftLaterRowsAndHitTest;
var
  G: TStrGridAccess;
  r0, r1, r2: TRect;
  hit: TTyGridHit;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 5;
  G.DefaultRowHeight := 20;
  G.OnGetRowHeight := @HandleTallSecondRow;   { 第 1 行 60px,其余 20px }

  r0 := G.CellRect(0, 0);
  r1 := G.CellRect(0, 1);
  r2 := G.CellRect(0, 2);

  AssertEquals('第 0 行仍是 20 高', 20, r0.Bottom - r0.Top);
  AssertEquals('第 1 行 60 高', 60, r1.Bottom - r1.Top);
  AssertEquals('第 1 行紧接第 0 行', r0.Bottom, r1.Top);
  AssertEquals('第 2 行被顶到 60 之后', r1.Bottom, r2.Top);
  AssertEquals('第 2 行恢复 20 高', 20, r2.Bottom - r2.Top);

  { 命中必须跟着走:点在加高那行的中部,应命中第 1 行而不是按等高算出的第 2/3 行。 }
  hit := G.CellAt(10, (r1.Top + r1.Bottom) div 2);
  AssertEquals('命中加高的那一行', 1, hit.Row);

  hit := G.CellAt(10, (r2.Top + r2.Bottom) div 2);
  AssertEquals('命中其后一行', 2, hit.Row);
end;

{ 不接 OnGetRowHeight 时不该分配前缀和数组 —— 百万行时那是个百万项的数组。 }
procedure TTyStringGridTest.TestUniformGridAllocatesNoRowTopsArray;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 1000000;
  AssertEquals('全等高时前缀和为空(走整除快路径)', 0, Length(G.Metrics.RowTops));

  G.OnGetRowHeight := @HandleTallSecondRow;
  G.RowCount := 5;
  AssertEquals('接了事件才建前缀和', 6, Length(G.Metrics.RowTops));
end;

{ 固定行钉在列头之下、**不随滚动**;正文行才滚。
  此前 FixedRows 只在冻结带里预留高度、什么都不画 —— 设了等于凭空多出一片空白。 }
procedure TTyStringGridTest.TestFixedRowsStayPutWhileBodyRowsScroll;
var
  G: TStrGridAccess;
  fixed0Before, fixed0After: TRect;
  body0Before, body0After: TRect;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 100;
  G.DefaultRowHeight := 20;
  G.Header.Options := G.Header.Options + [hoVisible];
  G.Header.Height := 24;
  G.FixedRows := 2;

  fixed0Before := G.CellRect(0, 0);
  body0Before  := G.CellRect(0, 2);      // 第一条正文行

  AssertEquals('固定行 0 紧贴列头下沿', 24, fixed0Before.Top);
  AssertEquals('固定行 1 在其后', 44, G.CellRect(0, 1).Top);
  { 正文首行紧接冻结带(24 列头 + 2×20 固定行 = 64)—— 中间不能留空洞。 }
  AssertEquals('正文首行紧接冻结带', 64, body0Before.Top);

  G.ScrollTop := 200;
  fixed0After := G.CellRect(0, 0);
  body0After  := G.CellRect(0, 2);

  AssertEquals('固定行纹丝不动', fixed0Before.Top, fixed0After.Top);
  AssertTrue('正文行随滚动上移', body0After.Top < body0Before.Top);
end;

{ 固定行也是真实的行:点得到,而且正文可视窗口必须从固定行**之后**开始 ——
  否则前两行会被画两遍(一次在冻结带、一次在正文)。 }
procedure TTyStringGridTest.TestFixedRowsAreClickableAndBodyStartsAfterThem;
var
  G: TStrGridAccess;
  r: TRect;
  hit: TTyGridHit;
  f, l: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 100;
  G.DefaultRowHeight := 20;
  G.Header.Options := G.Header.Options + [hoVisible];
  G.Header.Height := 24;
  G.FixedRows := 2;

  r := G.CellRect(0, 1);
  hit := G.CellAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  AssertEquals('点固定行命中它自己', 1, hit.Row);
  AssertEquals('且是单元格', Ord(ghpCell), Ord(hit.Part));

  AssertTrue('有可见行', G.VisibleRows(f, l));
  AssertEquals('正文窗口自固定行之后起', 2, f);

  // 滚动后仍然如此(固定行不该混进滚动窗口)。
  G.ScrollTop := 300;
  AssertTrue('滚动后仍有可见行', G.VisibleRows(f, l));
  AssertTrue('正文窗口首行不早于固定行数', f >= 2);
end;

{ 插入/删除行:内容随之整体搬移(稀疏存储只搬写过的格)。 }
procedure TTyStringGridTest.TestInsertAndDeleteRowShiftCellContents;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 3;
  G.Cells[0, 0] := 'A'; G.Cells[0, 1] := 'B'; G.Cells[0, 2] := 'C';

  G.InsertRow(1);
  AssertEquals('行数 +1', 4, G.RowCount);
  AssertEquals('插入点之前不动', 'A', G.Cells[0, 0]);
  AssertEquals('插入点是空行', '', G.Cells[0, 1]);
  AssertEquals('原 B 被推到第 2 行', 'B', G.Cells[0, 2]);
  AssertEquals('原 C 被推到第 3 行', 'C', G.Cells[0, 3]);
  AssertEquals('稀疏条目仍是 3 个(空行不占位)', 3, G.StoredCellCount);

  G.DeleteRow(1);
  AssertEquals('行数 -1', 3, G.RowCount);
  AssertEquals('删除后回到原样', 'B', G.Cells[0, 1]);
  AssertEquals('C 也回位', 'C', G.Cells[0, 2]);

  // 删掉有内容的那行,其内容应消失而不是残留。
  G.DeleteRow(0);
  AssertEquals('A 被删掉', 'B', G.Cells[0, 0]);
  AssertEquals('条目减少', 2, G.StoredCellCount);
end;

{ 插入/删除列同理,并且列集合本身也要跟着增删。 }
procedure TTyStringGridTest.TestInsertAndDeleteColumnShiftCellContents;
var
  G: TStrGridAccess;
  n: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);   // 4 列
  G.RowCount := 2;
  n := G.Header.Columns.Count;
  G.Cells[0, 0] := 'c0'; G.Cells[1, 0] := 'c1'; G.Cells[2, 0] := 'c2';

  G.InsertColumn(1);
  AssertEquals('列数 +1', n + 1, G.Header.Columns.Count);
  AssertEquals('第 0 列不动', 'c0', G.Cells[0, 0]);
  AssertEquals('插入点为空', '', G.Cells[1, 0]);
  AssertEquals('原 c1 右移', 'c1', G.Cells[2, 0]);

  G.DeleteColumn(1);
  AssertEquals('列数还原', n, G.Header.Columns.Count);
  AssertEquals('内容还原', 'c1', G.Cells[1, 0]);
end;

{ 整行选择模式:列不参与判定,选中就是整条行。 }
procedure TTyStringGridTest.TestRowSelectionModeSelectsWholeRows;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);   // 4 列 x 10 行
  G.RowCount := 10;
  G.Col := 1; G.Row := 2;
  G.AnchorSelection;

  AssertFalse('单元格模式下别的列不选中', G.IsCellSelected(3, 2));

  G.SelectionMode := gsmRow;
  AssertTrue('整行模式:同一行的任意列都选中', G.IsCellSelected(0, 2));
  AssertTrue('包括最后一列', G.IsCellSelected(3, 2));
  AssertFalse('别的行仍不选中', G.IsCellSelected(0, 3));

  // Shift+下 拉两行:两整行都选中。
  G.PressKeyShift(VK_DOWN);
  AssertTrue('第 2 行仍在选区', G.IsCellSelected(3, 2));
  AssertTrue('第 3 行也进选区', G.IsCellSelected(3, 3));
end;

{ 自动适宽:列宽跟着最长的内容走,且只量写过的格(不扫全表)。 }
procedure TTyStringGridTest.TestAutoFitColumnWidensToTheLongestCell;
var
  G: TStrGridAccess;
  w0, w1: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 1000000;           // 百万行,但只写 2 格
  G.Cells[0, 0] := 'ab';
  G.Cells[0, 500] := 'ab';
  G.AutoFitColumn(0);
  w0 := TTyColumn(G.Header.Columns.Items[0]).Width;

  G.Cells[0, 900000] := 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  G.AutoFitColumn(0);
  w1 := TTyColumn(G.Header.Columns.Items[0]).Width;

  AssertTrue(Format('更长的内容把列撑宽(%d → %d)', [w0, w1]), w1 > w0);
end;

{ 查找按**显示序**走,并从当前光标之后环绕一圈 —— 连按"下一个"要能不重不漏走遍全表。 }
procedure TTyStringGridTest.TestFindWalksTheWholeGridInDisplayOrderAndWraps;
var
  G: TStrGridAccess;
  c, r, hits: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);   // 4 列
  G.RowCount := 3;
  G.Cells[1, 0] := 'target';
  G.Cells[3, 2] := 'target';

  G.Col := 0; G.Row := 0;
  AssertTrue('找到第一处', G.FindNext('target', False, False));
  AssertEquals('列', 1, G.Col);
  AssertEquals('行', 0, G.Row);

  AssertTrue('找到第二处', G.FindNext('target', False, False));
  AssertEquals('列', 3, G.Col);
  AssertEquals('行', 2, G.Row);

  { 再找一次应当环绕回第一处 —— 而不是停在末尾找不到。 }
  AssertTrue('环绕回第一处', G.FindNext('target', False, False));
  AssertEquals('绕回列', 1, G.Col);
  AssertEquals('绕回行', 0, G.Row);

  // 全表扫一圈应恰好命中 2 次。
  hits := 0;
  G.Col := 0; G.Row := 0;
  while G.FindCell('target', False, False, c, r) do
  begin
    Inc(hits);
    G.Col := c; G.Row := r;
    if hits > 5 then Break;    { 防死循环 }
  end;
  AssertTrue('确实找得到', hits > 0);
end;

{ 大小写与整格匹配开关必须生效;分组行不是数据行,不参与查找。 }
procedure TTyStringGridTest.TestFindSkipsGroupRowsAndHonoursCaseAndWholeCell;
var
  G: TStrGridAccess;
  c, r: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 3;
  G.Cells[0, 0] := 'Alpha'; G.Cells[0, 1] := 'alphabet'; G.Cells[0, 2] := 'X';

  AssertTrue('不分大小写能找到', G.FindCell('ALPHA', False, False, c, r));
  AssertFalse('区分大小写就找不到 ALPHA', G.FindCell('ALPHA', True, False, c, r));

  AssertTrue('整格匹配能找到 Alpha', G.FindCell('Alpha', False, True, c, r));
  AssertEquals('整格匹配命中的是 Alpha 那行', 0, r);
  AssertFalse('整格匹配不该命中 alphabet 的子串', G.FindCell('alph', False, True, c, r));

  // 分组后:分组行不参与查找(它没有数据行)。
  G.GroupByColumn(0);
  AssertTrue('分组后仍能找到数据格', G.FindCell('alphabet', False, False, c, r));
  AssertEquals('命中的是数据行 1', 1, r);
end;

{ 批量替换:只读列必须跳过,不能被改掉。 }
procedure TTyStringGridTest.TestReplaceAllSkipsReadOnlyColumns;
var
  G: TStrGridAccess;
  n: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 2;
  G.Cells[1, 0] := 'old'; G.Cells[2, 0] := 'old';
  G.Cells[1, 1] := 'old'; G.Cells[2, 1] := 'old';
  G.OnGetEditorKind := @HandleReadOnlyCol2;   { 第 2 列只读 }

  n := G.ReplaceCells('old', 'new', False, True, True);
  AssertEquals('替换了 2 处(只读列跳过)', 2, n);
  AssertEquals('可写列被替换', 'new', G.Cells[1, 0]);
  AssertEquals('只读列保持原值', 'old', G.Cells[2, 0]);
end;

{ HTML 导出:特殊字符要转义,且与 CSV 一样走显示序。 }
procedure TTyStringGridTest.TestHtmlExportEscapesAndFollowsFilterOrder;
var
  G: TStrGridAccess;
  html: string;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 3;
  G.Cells[0, 0] := 'keep-b';
  G.Cells[0, 1] := 'drop';
  G.Cells[0, 2] := 'keep-a <script>';

  G.SetColumnFilter(0, 'keep');
  G.SortByColumn(0, sdAscending);
  html := G.SaveToHTMLText;

  AssertTrue('是个表格', Pos('<table', html) > 0);
  AssertEquals('被筛掉的行不出现', 0, Pos('drop', html));
  AssertTrue('尖括号被转义', Pos('&lt;script&gt;', html) > 0);
  AssertEquals('原始尖括号不该出现在内容里', 0, Pos('<script>', html));
  AssertTrue('按排序后的次序导出', Pos('keep-a', html) < Pos('keep-b', html));
end;

{ OnDrawCell 置 AHandled 后,控件不该再往那格画文字。 }
procedure TTyStringGridTest.TestOnDrawCellCanTakeOverACell;
var
  G: TStrGridAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  inkNormal, inkHandled: Integer;
  r: TRect;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 2;
  G.GridLines := False;
  G.Cells[0, 0] := 'WWWW';
  r := G.CellVisibleRect(0, 0);

  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);

    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try inkNormal := InkIn(Reread, r); finally Reread.Free; end;
    AssertTrue('默认会画文字', inkNormal > 0);

    { 接管后控件不画 —— 宿主什么都不画,所以那格应当没有墨。 }
    FTakeOverCol := 0;
    G.OnDrawCell := @HandleDrawCell;
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try inkHandled := InkIn(Reread, r); finally Reread.Free; end;
    AssertEquals('被接管的格控件不再画文字', 0, inkHandled);
  finally
    Bmp.Free;
  end;
end;

{ CSV 里含换行的引号字段必须能原样往返。
  此前 LoadFromCSVText 先按 TStringList.Text 切行、再逐行拆字段 ——
  引号内的换行会被当成行分隔符,**Excel 导出的 CSV 会静默串数据**
  (行数凭空变多、单元格被拦腰截断)。这是数据正确性缺陷,不是功能缺失。 }
procedure TTyStringGridTest.TestCsvRoundTripsCellsContainingNewlines;
var
  G, G2: TStrGridAccess;
  csv, multi: string;
begin
  multi := '第一行' + LineEnding + '第二行';

  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 2;
  TTyColumn(G.Header.Columns.Items[0]).Text := '名称';
  TTyColumn(G.Header.Columns.Items[1]).Text := '备注';
  G.Cells[0, 0] := 'A';  G.Cells[1, 0] := multi;
  G.Cells[0, 1] := 'B';  G.Cells[1, 1] := '普通';

  csv := G.SaveToCSVText(',');

  G2 := MakeStrGrid(FForm, FCtl);
  G2.LoadFromCSVText(csv, ',');

  { 行数不能因为字段里的换行而膨胀。 }
  AssertEquals('行数原样往返', 2, G2.RowCount);
  { 内容必须逐字符相等,不能被截断。 }
  AssertEquals('含换行的字段原样往返', multi, G2.Cells[1, 0]);
  AssertEquals('同行的其它字段没串位', 'A', G2.Cells[0, 0]);
  AssertEquals('下一行没被吃掉', 'B', G2.Cells[0, 1]);
  AssertEquals('下一行的备注也对', '普通', G2.Cells[1, 1]);
end;

{ hoAutoResize + Header.AutoSizeIndex 此前**已 published 却完全不生效**
  —— TTyColumns.ApplyAutoSize 在 Grid.pas 里零调用。
  这类"设了没有任何可观测效果"的洞编译期不报错、运行期无声无息,和之前 ShowFooter 同一类。 }
procedure TTyStringGridTest.TestAutoResizeColumnFillsRemainingWidth;
var
  G: TStrGridAccess;
  before, after: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);      // 4 列 x 80 = 320 宽
  G.SetBounds(0, 0, 500, 300);        // 视口 500,富余 180
  G.RowCount := 3;

  before := TTyColumn(G.Header.Columns.Items[1]).Width;

  G.Header.AutoSizeIndex := 1;
  G.Header.Options := G.Header.Options + [hoAutoResize];
  G.ForceUpdateScrollBars;            { 触发一次布局 }

  after := TTyColumn(G.Header.Columns.Items[1]).Width;
  AssertTrue(Format('自动列吸收了剩余宽度(%d -> %d)', [before, after]), after > before);

  { 总宽应当基本填满视口(允许几像素误差)。 }
  AssertTrue(Format('列总宽填满视口(总宽 %d,视口 %d)',
    [G.Header.Columns.TotalWidth, G.ClientWidth]),
    Abs(G.Header.Columns.TotalWidth - G.ClientWidth) < 20);
end;

initialization
  RegisterTest(TTyGridControlTest);
  RegisterTest(TTyDrawGridTest);
  RegisterTest(TTyStringGridTest);
end.
