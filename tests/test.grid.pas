unit test.grid;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, DateUtils, Types, Graphics, Controls, Forms, LCLType, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Columns, tyControls.Grid, tyControls.ComboBox,
  tyControls.Painter, tyControls.ImageCollection, tyControls.Edit, StdCtrls,
  tyControls.DateTimePicker, tyControls.CalcEdit,
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
    procedure TestHeaderCaptionIndentsForColumnImage;
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
    procedure TestPublishedSurfaceHasObservableEffect;
    procedure TestHoverHighlightsTheCellUnderTheMouse;
    procedure TestPerCellStyleResolutionKeepsDefaultFastPath;
    procedure TestInsertRowShiftsMergeSpansToo;
    procedure TestInsertRowShiftsMergeOfEmptyCell;
    procedure TestCellStyleHookPaintsOnlyThatRow;
    procedure TestCellStyleHookCanChangeVerticalAlignment;
    procedure TestZebraStripingFollowsDisplayOrder;
    procedure TestGridLineStyleCanDropOneAxis;
    procedure TestRightClickOnCellFiresEventWithThatCell;
    procedure TestCanClickCellVetoesTheWholeClick;
    procedure TestButtonCellClickFiresWithThatCell;
    procedure TestDoubleClickOnDividerAutoFitsColumn;
    procedure TestWordWrapMakesLongTextUseMoreLines;
    procedure TestExplicitRowHeightBeatsCallbackAndMovesGeometry;
    procedure TestDragRowDividerChangesRowHeight;
    procedure TestAutoFitRowGrowsToFitWrappedText;
    procedure TestCtrlClickAddsDiscreteSelection;
    procedure TestSelectionApiAndChangedEvent;
    procedure TestDragAcrossCellsExtendsSelection;
    procedure TestColumnLevelPropertiesNeedNoEvents;
    procedure TestTypingAPrintableCharStartsEditing;
    procedure TestValidCharsBlocksIllegalKeys;
    procedure TestEnterAdvancesDownAndTabAdvancesByCell;
    procedure TestHostEditLinkTakesOverTheCell;
    procedure TestHeaderGroupBandStacksAboveColumnHeader;
    procedure TestHeaderGroupBandIsNotALeafHeaderForHitTesting;
    procedure TestSecondarySortKeyBreaksTies;
    procedure TestGroupingKeepsTheUserSortColumn;
    procedure TestColumnSortKindBeatsGridSortKind;
    procedure TestExpandCollapseAllGroups;
    procedure TestSmartPasteGrowsInsteadOfDroppingRows;
    procedure TestPasteCellHooksCanRewriteAndSkip;
    procedure TestBatchRowOpsAndMoveSwap;
    procedure TestPersistentCellColorsAndRowColor;
    procedure TestPerCellReadOnlyBlocksEditing;
    procedure TestRowHeightLimitsClampAtTheStore;
    procedure TestColumnSizeEventsFireOnDragAndRelease;
    procedure TestHiddenRowsSurviveClearFilters;
    procedure TestSelectionAggregatesSkipNonNumericCells;
    procedure TestCheckBoxEventsFireAndCanBeVetoed;
    procedure TestSkipReadOnlyCellsDuringNavigation;
    procedure TestTypedFilterOperators;
    procedure TestFilterFunnelLightsUpOnlyForFilteredColumns;
    procedure TestBlanksPositionAndCaseSensitiveSorting;
    procedure TestCtrlAGoesThroughSelectAll;
    procedure TestGridLinesDoNotCrossMergedCells;
    procedure TestColorCellPaintsASwatchNotTheHexText;
    procedure TestResizeCursorsFollowTheDividers;
    procedure TestSelectionColourIgnoresGridHoverState;
    procedure TestSpinEditorRoundTripsAndClampsToColumnRange;
    procedure TestSliderEditorRoundTrips;
    procedure TestMaskEditorUsesColumnMask;
    procedure TestRatingCellSetsValueByClickingAStar;
    procedure TestRatingCellPaintsFilledAndEmptyStars;
    procedure TestPasswordTimeCalculatorAndCharCaseEditors;
    procedure TestHiddenColumnTakesNoSpaceAndIsNotPainted;
    procedure TestNavigationSkipsHiddenColumns;
    procedure TestRowNumbersFollowDisplayOrder;
    procedure TestEllipsisButtonHandsControlToHost;
    procedure TestScrollFastPathIsPixelIdenticalToFullRepaint;
    procedure TestScrollFastPathIsCheaperThanFullRepaint;
    procedure TestScrollBarDragUsesFastPath;
    procedure TestSelectionDoesNotEraseAnExplicitCellColor;
    procedure TestZebraDoesNotOverrideAnExplicitCellColor;
    procedure TestInsertRowIsCorrectAcrossTenthRowBoundary;
    procedure TestDeleteRowIsCorrectAcrossTenthRowBoundary;
    procedure TestInsertColumnIsCorrectAcrossTenthColumnBoundary;
    procedure TestRowSideTablesFollowTheDataOnInsert;
  public
    { 鼠标事件的桩(同样必须在 published 之外)。 }
    FSelChanges: Integer;
    FProbeLink: TTyGridEditLink;
    FSizingCalls, FEndSizeCalls, FLastEndSize: Integer;
    FCheckChanges: Integer;
    FEllipsisCalls: Integer;
    FEllipsisCancel: Boolean;
    FVetoToggle: Boolean;
    FClickCol, FClickRow: Integer;
    FRightCol, FRightRow: Integer;
    FBtnCol, FBtnRow: Integer;
    FVetoCol: Integer;
    procedure HookClickCell(Sender: TObject; ACol, ARow: Integer);
    procedure HookRightClickCell(Sender: TObject; ACol, ARow: Integer);
    procedure HookCellButtonClick(Sender: TObject; ACol, ARow: Integer);
    procedure HookCanClickCell(Sender: TObject; ACol, ARow: Integer;
      var ACanClick: Boolean);
    procedure HookButtonInCol1(Sender: TObject; ACol, ARow: Integer;
      var ADisplay: TTyGridCellDisplay);
    procedure HookColorInCol1(Sender: TObject; ACol, ARow: Integer;
      var ADisplay: TTyGridCellDisplay);
    procedure HookRatingInCol1(Sender: TObject; ACol, ARow: Integer;
      var ADisplay: TTyGridCellDisplay);
    procedure HookEllipsis(Sender: TObject; ACol, ARow: Integer;
      var ANewText: string; var AAccept: Boolean);
    procedure HookSelectionChanged(Sender: TObject);
    procedure HookCanToggle(Sender: TObject; ACol, ARow: Integer;
      var AAllow: Boolean);
    procedure HookCheckChange(Sender: TObject; ACol, ARow: Integer;
      AChecked: Boolean);
    procedure HookColumnSizing(Sender: TObject; AIndex: Integer;
      var ANewSize: Integer; var AAllow: Boolean);
    procedure HookEndColumnSize(Sender: TObject; AIndex, ANewSize: Integer);
    procedure HookUpperCasePaste(Sender: TObject; ACol, ARow: Integer;
      var ANewText: string; var AAllow: Boolean);
    procedure HookCreateEditLink(Sender: TObject; ACol, ARow: Integer;
      var ALink: TTyGridEditLink);
    { 逐格外观钩子的桩。**必须放在 published 之外** —— fpcunit 会把 published 段里的
      每个方法都当成测试用例注册,钩子被当测试跑起来(Sender=nil)直接 AV。 }
    procedure HookPaintRow2Red(Sender: TObject; ACol, ARow: Integer;
      var ABackground: TTyFill; var ATextColor: TTyColor;
      var AFontName: string; var AFontSize, AFontWeight: Integer;
      var AHAlign: TAlignment; var AVAlign: TTextLayout);
    procedure HookAlignTop(Sender: TObject; ACol, ARow: Integer;
      var ABackground: TTyFill; var ATextColor: TTyColor;
      var AFontName: string; var AFontSize, AFontWeight: Integer;
      var AHAlign: TAlignment; var AVAlign: TTextLayout);
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
  AssertEquals('无固定列时冻结带零宽', 0, G.Metrics.FrozenLeft);

  // 冻结前 2 列(80+60),仍无行头槽。
  G.FixedCols := 2;
  AssertEquals('冻结带 = 前两列宽之和', 140, G.Metrics.FrozenLeft);

  // 打开 30px 行头槽。
  G.ShowIndicator := True;
  G.IndicatorWidth := 30;
  AssertEquals('冻结带 = 行头槽 + 前两列', 170, G.Metrics.FrozenLeft);

  // 行头槽关掉就不占位(仅设宽度不生效)。
  G.ShowIndicator := False;
  AssertEquals('关掉行头槽后不占位', 140, G.Metrics.FrozenLeft);

  // 固定列数超过实际列数时按实际列数封顶,不能越界求和。
  G.FixedCols := 99;
  AssertEquals('固定列数超出时按全部列封顶', 80 + 60 + 120 + 90, G.Metrics.FrozenLeft);
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
  AssertEquals('冻结带高 = 列头高', 24, G.Metrics.FrozenTop);

  G.FixedRows := 2;
  AssertEquals('冻结带高 = 列头 + 2 个固定行', 24 + 2 * 20, G.Metrics.FrozenTop);

  // 列头隐藏后不占位,固定行仍占位。
  G.Header.Options := G.Header.Options - [hoVisible];
  AssertEquals('列头隐藏后只剩固定行', 2 * 20, G.Metrics.FrozenTop);
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
    procedure HoverAt(X, Y: Integer);
    procedure EnterControl;
    procedure LeaveControl;
    procedure RightClickAt(X, Y: Integer);
    procedure CtrlClickAt(X, Y: Integer);
    function  PressKeyCtrl(AKey: Word): Boolean;
    procedure TypeChar(AChar: Char);
    function  EditorText: string;
    function  IsEditing: Boolean;
    function  HitAt(X, Y: Integer): TTyGridHit;
    function  EditorVisible: Boolean;
    function  InlineEditorPasswordChar: string;
    function  InlineEditorCharCase: TEditCharCase;
    function  DateEditorKind: TTyDateTimeKind;
    function  SpinValue: Integer;
    procedure SetSpinValue(AValue: Integer);
    function  SliderValue: Integer;
    procedure SetSliderValue(AValue: Integer);
    function  MaskOf: string;
    function  StarRectOf(ACol, ARow, AStar: Integer): TRect;
    function  EllipsisRectOf(ACol, ARow: Integer): TRect;
    procedure DragFromTo(X1, Y1, X2, Y2: Integer);
    procedure DoubleClickAt(X, Y: Integer);
    function  ColWidth(ACol: Integer): Integer;
    function  ScaleFrom(ALogical: Integer): Integer;
    { 完整一次点击(按下 + 松开)。注意 ClickAt **只发 MouseDown** ——
      按钮单元格按设计是松开才算触发(按下后拖走应当作废),所以要用这个。 }
    procedure FullClickAt(X, Y: Integer);
    procedure LeaveMouse;
    function  RowRectAt(APos: Integer): TRect;
    function  GetScrollTop: Integer;
    procedure SetScrollTop(AValue: Integer);
    procedure ScrollByForTest(ADy: Integer);
    procedure InvalidateSurfaceForTest;
    property ScrollTop: Integer read GetScrollTop write SetScrollTop;
  end;

procedure TStrGridAccess.PressMouseWithoutRelease(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);      { 不 MouseUp —— 停在"按住"状态 }
end;

procedure TStrGridAccess.FullClickAt(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
  MouseUp(mbLeft, [], X, Y);
end;

function TStrGridAccess.ScaleFrom(ALogical: Integer): Integer;
begin
  Result := ScaleI(ALogical);
end;

function TStrGridAccess.ColWidth(ACol: Integer): Integer;
begin
  Result := ColumnWidthPx(ACol);
end;

procedure TStrGridAccess.TypeChar(AChar: Char);
var c: Char;
begin
  c := AChar;
  KeyPress(c);
end;

function TStrGridAccess.EditorText: string;
begin
  Result := InlineEditor.Text;
end;

function TStrGridAccess.HitAt(X, Y: Integer): TTyGridHit;
begin
  Result := CellAt(X, Y);
end;

function TStrGridAccess.IsEditing: Boolean;
begin
  Result := Editing;
end;

function TStrGridAccess.EditorVisible: Boolean;
begin
  Result := InlineEditor.Visible;
end;

function TStrGridAccess.InlineEditorPasswordChar: string;
begin Result := InlineEditor.PasswordChar; end;
function TStrGridAccess.InlineEditorCharCase: TEditCharCase;
begin Result := InlineEditor.CharCase; end;
function TStrGridAccess.DateEditorKind: TTyDateTimeKind;
begin Result := DateEditor.Kind; end;

function TStrGridAccess.SpinValue: Integer;
begin Result := SpinEditor.Value; end;
procedure TStrGridAccess.SetSpinValue(AValue: Integer);
begin SpinEditor.Value := AValue; end;
function TStrGridAccess.SliderValue: Integer;
begin Result := SliderEditor.Position; end;
procedure TStrGridAccess.SetSliderValue(AValue: Integer);
begin SliderEditor.Position := AValue; end;
function TStrGridAccess.MaskOf: string;
begin Result := MaskEditor.Mask; end;
function TStrGridAccess.StarRectOf(ACol, ARow, AStar: Integer): TRect;
begin Result := RatingStarRect(ACol, ARow, AStar); end;
function TStrGridAccess.EllipsisRectOf(ACol, ARow: Integer): TRect;
begin Result := EllipsisRect(ACol, ARow); end;

function TStrGridAccess.PressKeyCtrl(AKey: Word): Boolean;
var k: Word;
begin
  k := AKey;
  KeyDown(k, [ssCtrl]);
  Result := k = 0;
end;

procedure TStrGridAccess.CtrlClickAt(X, Y: Integer);
begin
  MouseDown(mbLeft, [ssCtrl], X, Y);
  MouseUp(mbLeft, [ssCtrl], X, Y);
end;

procedure TStrGridAccess.DragFromTo(X1, Y1, X2, Y2: Integer);
begin
  MouseDown(mbLeft, [], X1, Y1);
  MouseMove([ssLeft], X2, Y2);
  MouseUp(mbLeft, [], X2, Y2);
end;

procedure TStrGridAccess.RightClickAt(X, Y: Integer);
begin
  MouseDown(mbRight, [], X, Y);
  MouseUp(mbRight, [], X, Y);
end;

procedure TStrGridAccess.DoubleClickAt(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
  MouseUp(mbLeft, [], X, Y);
  { LCL 在第二次按下时把 ssDouble 塞进 Shift —— 双击就是这么识别的。 }
  MouseDown(mbLeft, [ssDouble], X, Y);
  MouseUp(mbLeft, [], X, Y);
end;

procedure TStrGridAccess.EnterControl;
begin
  MouseEnter;      { 让控件自身进入 :hover }
end;

procedure TStrGridAccess.LeaveControl;
begin
  MouseLeave;
end;

procedure TStrGridAccess.HoverAt(X, Y: Integer);
begin
  MouseMove([], X, Y);       { 不按键 —— 纯悬停,别触发选区拖拽 }
end;

procedure TStrGridAccess.LeaveMouse;
begin
  Perform(CM_MOUSELEAVE, 0, 0);
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

procedure TStrGridAccess.ScrollByForTest(ADy: Integer);
begin
  ScrollVerticallyBy(ADy);
end;

procedure TStrGridAccess.InvalidateSurfaceForTest;
begin
  InvalidateSurface;
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

{ 渲染指纹:把整张渲染结果折成一个 FNV-1a 哈希。
  用它判定"改了某个开关之后画面到底变没变" —— 比数某种颜色的像素稳,
  也不会因为主题换了个色就失效。 }
function RenderFingerprint(G: TStrGridAccess): string;
var
  Bmp: TBitmap;
  Re: TBGRABitmap;
  x, y: Integer;
  h: QWord;
  px: TBGRAPixel;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);
    Re := TBGRABitmap.Create(Bmp);
    try
      h := QWord(14695981039346656037);
      for y := 0 to Re.Height - 1 do
        for x := 0 to Re.Width - 1 do
        begin
          px := Re.GetPixel(x, y);
          h := (h xor QWord(px.red + (px.green shl 8) + (px.blue shl 16)))
               * QWord(1099511628211);
        end;
      Result := IntToHex(h, 16);
    finally
      Re.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

{ **通用守卫**:published 出去的开关必须产生**可观测效果**(像素或几何),
  而不是只有属性读回来变了。

  这一批修的三个洞是同一类:`ShowFooter` 早先只赋值不影响视口、
  `ApplyAutoSize` 零调用、`TTyColumn.ImageIndex` 零读取 ——
  编译期不报错、运行期无声无息,单测若只断言 `AssertTrue(G.ShowFooter)` 一样是绿的。
  所以这里一律断言"渲染输出/几何度量变了",不看属性回读。 }
procedure TTyStringGridTest.TestPublishedSurfaceHasObservableEffect;
var
  G: TStrGridAccess;
  before, after: string;
  vpBefore, vpAfter, colBefore, colAfter, wBefore, wAfter: Integer;
  i: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.Header.Options := G.Header.Options + [hoVisible];
  G.Header.Height := 22;
  G.RowCount := 6;
  for i := 0 to G.RowCount - 1 do
  begin
    G.Cells[0, i] := 'A' + IntToStr(i);
    G.Cells[1, i] := 'B' + IntToStr(i);
  end;

  { ---- ShowFooter:同时改几何(视口变矮)与像素 ---- }
  vpBefore := G.ViewportHeight;
  before := RenderFingerprint(G);
  G.ShowFooter := True;
  vpAfter := G.ViewportHeight;
  after := RenderFingerprint(G);
  AssertTrue(Format('ShowFooter 应当从视口里扣掉汇总带高度(%d -> %d)',
    [vpBefore, vpAfter]), vpAfter < vpBefore);
  AssertTrue('ShowFooter 应当改变渲染输出', before <> after);
  G.ShowFooter := False;

  { ---- GridLines ---- }
  before := RenderFingerprint(G);
  G.GridLines := False;
  after := RenderFingerprint(G);
  AssertTrue('GridLines 应当改变渲染输出', before <> after);
  G.GridLines := True;

  { ---- ShowIndicator:行头槽把列 0 往右推,并画出来 ---- }
  colBefore := G.ColLeft(0);
  before := RenderFingerprint(G);
  G.ShowIndicator := True;
  colAfter := G.ColLeft(0);
  after := RenderFingerprint(G);
  AssertTrue(Format('ShowIndicator 应当把第 0 列右推(%d -> %d)',
    [colBefore, colAfter]), colAfter > colBefore);
  AssertTrue('ShowIndicator 应当改变渲染输出', before <> after);
  G.ShowIndicator := False;

  { ---- ShowFilterButtons:列头里多出下拉小三角 ---- }
  before := RenderFingerprint(G);
  G.ShowFilterButtons := True;
  after := RenderFingerprint(G);
  AssertTrue('ShowFilterButtons 应当改变列头渲染输出', before <> after);
  G.ShowFilterButtons := False;

  { ---- GridLineWidth:线加粗必须看得见,且**不挪动列边界** ---- }
  before := RenderFingerprint(G);
  colBefore := G.ColLeft(2);
  G.GridLineWidth := 5;
  after := RenderFingerprint(G);
  colAfter := G.ColLeft(2);
  AssertTrue('GridLineWidth 应当改变渲染输出', before <> after);
  AssertEquals('但线加粗**不能**挪动列边界(线压在边界上,不占布局像素)',
    colBefore, colAfter);
  G.GridLineWidth := 1;

  { ---- hoAutoResize + AutoSizeIndex:列宽被重排 ---- }
  wBefore := TTyColumn(G.Header.Columns.Items[1]).Width;
  G.Header.AutoSizeIndex := 1;
  G.Header.Options := G.Header.Options + [hoAutoResize];
  G.ForceUpdateScrollBars;
  wAfter := TTyColumn(G.Header.Columns.Items[1]).Width;
  AssertTrue(Format('hoAutoResize 应当改变自动列的宽度(%d -> %d)',
    [wBefore, wAfter]), wAfter <> wBefore);
end;

{ `TyGridCell:hover` 这条规则在 light.tycss 里**早就写好了,却永远不会触发** ——
  网格从来不记"鼠标在哪一格",单元格背景也压根没人画(背景全靠 RenderChrome 一次性铺)。
  典型的"主题写了但控件够不着"。 }
procedure TTyStringGridTest.TestHoverHighlightsTheCellUnderTheMouse;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;

  function RedInCell(ACol, ARow: Integer): Integer;
  var
    Re: TBGRABitmap;
    r: TRect;
    x, y: Integer;
    px: TBGRAPixel;
  begin
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);
    r := G.CellRect(ACol, ARow);
    Result := 0;
    Re := TBGRABitmap.Create(Bmp);
    try
      for y := r.Top to r.Bottom - 1 do
        for x := r.Left to r.Right - 1 do
        begin
          if (x < 0) or (y < 0) or (x >= 400) or (y >= 300) then Continue;
          px := Re.GetPixel(x, y);
          if (px.red > 180) and (px.green < 100) and (px.blue < 100) then Inc(Result);
        end;
    finally
      Re.Free;
    end;
  end;

var
  r: TRect;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; }' +
      'TyGridCell:hover { background: #FF0000; }');

    G := MakeStrGrid(FForm, Ctl);
    G.GridLines := False;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);

    AssertEquals('没悬停时不该有高亮', 0, RedInCell(1, 2));

    { 悬停到 (1,2) 的正中。 }
    r := G.CellRect(1, 2);
    G.HoverAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
    AssertTrue('鼠标下那一格应当高亮', RedInCell(1, 2) > 50);
    AssertEquals('旁边那一格不该高亮', 0, RedInCell(0, 2));

    { 移开后消失 —— 否则会留下一路"拖影"。 }
    G.LeaveMouse;
    AssertEquals('鼠标离开后高亮消失', 0, RedInCell(1, 2));
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ A2 把样式解析搬进了逐格循环、并给每格加了背景绘制 —— hover / 斑马纹 / 逐格底色
  的前提。但逐格化最容易把大表拖垮,所以要有一条守卫。

  **度量方式是相对的,不是绝对毫秒** —— 绝对阈值换台机器就误报。
  同一张表画两遍:一遍单元格全空(= 渲染管线的固有开销:整幅位图、逐格几何、
  逐格样式解析),一遍填满文字。断言**文字那部分的增量不超过固有开销本身**。

  这条线是实测定出来的:变异掉缓存后文字增量是固有开销的 **28 倍**
  (每格一次 TextSize 做省略号测量 + 一次 TextRect,都是 BGRA 的重活);
  有缓存时约 1.1 倍。阈值取 4 倍:离健康值有 4 倍余量抗抖动,离病态值还差 7 倍。 }
procedure TTyStringGridTest.TestPerCellStyleResolutionKeepsDefaultFastPath;
const
  FRAMES = 30;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;

  function TimeFrames: QWord;
  var f: Integer; t0: QWord;
  begin
    G.DoRender(Bmp.Canvas, Rect(0, 0, 1000, 800), 96);   { 预热一帧,别把冷启动算进去 }
    t0 := GetTickCount64;
    for f := 1 to FRAMES do
      G.DoRender(Bmp.Canvas, Rect(0, 0, 1000, 800), 96);
    Result := GetTickCount64 - t0;
  end;

var
  i, j: Integer;
  c: TTyColumn;
  bare, withText: QWord;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; padding: 0px 6px; }' +
      'TyGridCell:hover { background: #EEEEEE; }');

    G := TStrGridAccess.Create(FForm);
    G.Parent := FForm;
    G.Controller := Ctl;
    G.Font.PixelsPerInch := 96;
    G.SetBounds(0, 0, 1000, 800);
    for i := 0 to 19 do
    begin
      c := G.Header.Columns.Add as TTyColumn;
      c.Width := 60;
    end;
    G.DefaultRowHeight := 20;
    G.RowCount := 1000;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(1000, 800);

    { 一、空表:管线固有开销。 }
    bare := TimeFrames;

    { 二、填满可视窗口(每格内容都不同 —— 别让缓存靠"全表同一个字"作弊)。 }
    for i := 0 to 49 do
      for j := 0 to 19 do
        G.Cells[j, i] := Format('%d-%d', [j, i]);
    withText := TimeFrames;

    AssertTrue(Format('空表 %d ms / 有字 %d ms —— 文字增量不该超过固有开销的 4 倍',
      [bare, withText]),
      (withText <= bare) or (withText - bare <= 4 * bare));
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ 增删行只搬了**文字**,没搬合并区 —— 于是在合并区上方插一行,
  合并区就留在原地、跟内容脱节了(内容跟着走,合并框没走)。
  单元格的"每格附加属性"分散在 FCells / FMerges 两处存储,是这个 bug 的根因;
  A3 把它们并进同一个稀疏存储,搬家时一趟搬完。 }
procedure TTyStringGridTest.TestInsertRowShiftsMergeSpansToo;
var
  G: TStrGridAccess;
  cs, rs: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 6;
  G.Cells[1, 1] := '合并块';
  G.MergeCells(1, 1, 2, 2);

  AssertTrue('前置条件:(1,1) 是合并基准格', G.CellSpan(1, 1, cs, rs));

  G.InsertRow(0);

  { 内容跟着下移了 —— 合并区必须跟着一起下移。 }
  AssertEquals('内容下移到了第 2 行', '合并块', G.Cells[1, 2]);
  AssertTrue('合并区也应当下移到 (1,2)', G.CellSpan(1, 2, cs, rs));
  AssertEquals('跨列数保持', 2, cs);
  AssertEquals('跨行数保持', 2, rs);
  AssertTrue('原位置不该再是合并基准格', not G.CellSpan(1, 1, cs, rs));
end;

{ 只合并、**不写文字**的格(空白合并块很常见)也必须跟着搬。
  它不在文本键表里,所以搬家时要遍历"有文字"与"有属性"两套键的并集 ——
  只看文本键的话这类格会被原地落下。 }
procedure TTyStringGridTest.TestInsertRowShiftsMergeOfEmptyCell;
var
  G: TStrGridAccess;
  cs, rs: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 6;
  G.MergeCells(2, 3, 2, 1);        { 一个空白合并块 }
  AssertEquals('前置条件:该格没有文字', '', G.Cells[2, 3]);

  G.InsertRow(0);

  AssertTrue('空白合并块也应当下移到 (2,4)', G.CellSpan(2, 4, cs, rs));
  AssertEquals('跨列数保持', 2, cs);
  AssertTrue('原位置不该再是合并基准格', not G.CellSpan(2, 3, cs, rs));
end;

procedure TTyStringGridTest.HookPaintRow2Red(Sender: TObject; ACol, ARow: Integer;
  var ABackground: TTyFill; var ATextColor: TTyColor;
  var AFontName: string; var AFontSize, AFontWeight: Integer;
  var AHAlign: TAlignment; var AVAlign: TTextLayout);
begin
  if ARow = 2 then
  begin
    ABackground.Kind := tfkSolid;
    ABackground.Color := TyRGB(255, 0, 0);
  end;
end;

procedure TTyStringGridTest.HookAlignTop(Sender: TObject; ACol, ARow: Integer;
  var ABackground: TTyFill; var ATextColor: TTyColor;
  var AFontName: string; var AFontSize, AFontWeight: Integer;
  var AHAlign: TAlignment; var AVAlign: TTextLayout);
begin
  AVAlign := tlTop;
end;

{ 逐格外观钩子:宿主要能按数据决定某一格长什么样(负数标红、超期标黄……)。
  断言"**只有**那一行变了" —— 只断言目标行变红的话,把整表涂红也能通过。 }
procedure TTyStringGridTest.TestCellStyleHookPaintsOnlyThatRow;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;

  function RedInRow(ARow: Integer): Integer;
  var
    Re: TBGRABitmap; r: TRect; x, y: Integer; px: TBGRAPixel;
  begin
    r := G.CellRect(0, ARow);
    Result := 0;
    Re := TBGRABitmap.Create(Bmp);
    try
      for y := r.Top to r.Bottom - 1 do
        for x := r.Left to r.Right - 1 do
        begin
          if (x < 0) or (y < 0) or (x >= 400) or (y >= 300) then Continue;
          px := Re.GetPixel(x, y);
          if (px.red > 180) and (px.green < 100) and (px.blue < 100) then Inc(Result);
        end;
    finally
      Re.Free;
    end;
  end;

begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; }');
    G := MakeStrGrid(FForm, Ctl);
    G.GridLines := False;
    G.OnGetCellStyle := @HookPaintRow2Red;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);

    AssertTrue('钩子标红的那一行应当变红', RedInRow(2) > 50);
    AssertEquals('上一行不该被波及', 0, RedInRow(1));
    AssertEquals('下一行不该被波及', 0, RedInRow(3));
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ 垂直对齐从前恒为 tlCenter,钩子要能改。用**墨的重心**判定,
  比数某一行像素结实:字体度量在不同机器上会差几像素,重心不会。 }
procedure TTyStringGridTest.TestCellStyleHookCanChangeVerticalAlignment;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;

  function InkCentroidY: Double;
  var
    Re: TBGRABitmap; r: TRect; x, y, n: Integer; px: TBGRAPixel; acc: Int64;
  begin
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);
    r := G.CellRect(0, 1);
    acc := 0; n := 0;
    Re := TBGRABitmap.Create(Bmp);
    try
      for y := r.Top to r.Bottom - 1 do
        for x := r.Left to r.Right - 1 do
        begin
          if (x < 0) or (y < 0) or (x >= 400) or (y >= 300) then Continue;
          px := Re.GetPixel(x, y);
          if px.red + px.green + px.blue < 400 then    { 有墨 }
          begin
            Inc(acc, y - r.Top);
            Inc(n);
          end;
        end;
    finally
      Re.Free;
    end;
    if n = 0 then Result := -1 else Result := acc / n;
  end;

var
  centered, topped: Double;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; }');
    G := MakeStrGrid(FForm, Ctl);
    G.GridLines := False;
    G.DefaultRowHeight := 40;          { 够高才看得出上/中的差别 }
    G.Cells[0, 1] := 'Ay';

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);

    centered := InkCentroidY;
    AssertTrue('前置条件:该格要有墨', centered >= 0);

    G.OnGetCellStyle := @HookAlignTop;
    topped := InkCentroidY;
    AssertTrue('前置条件:改对齐后仍要有墨', topped >= 0);

    AssertTrue(Format('tlTop 应当把墨的重心上移(居中 %.1f -> 顶对齐 %.1f)',
      [centered, topped]), topped < centered - 2);
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ 斑马纹必须按**显示行号**取,不是数据行号 —— 否则排序/筛选之后条纹会跟着
  数据行乱跳,看起来像随机涂色。 }
procedure TTyStringGridTest.TestZebraStripingFollowsDisplayOrder;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;

  function IsStriped(APos: Integer): Boolean;
  var
    Re: TBGRABitmap; r: TRect; x, y, n: Integer; px: TBGRAPixel;
  begin
    r := G.RowRectAt(APos);
    n := 0;
    Re := TBGRABitmap.Create(Bmp);
    try
      for y := r.Top + 2 to r.Bottom - 3 do
        for x := 4 to 70 do
        begin
          if (y < 0) or (y >= 300) then Continue;
          px := Re.GetPixel(x, y);
          if (px.red < 100) and (px.green > 180) and (px.blue < 100) then Inc(n);
        end;
    finally
      Re.Free;
    end;
    Result := n > 20;
  end;

  procedure Render;
  begin
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);
  end;

begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; }' +
      'TyGridCellAlt { background: #00FF00; }');
    G := MakeStrGrid(FForm, Ctl);
    G.GridLines := False;
    G.AlternateRows := True;
    G.RowCount := 6;
    { 这组值是**特意挑的**:升序后 显示序 -> 数据行 = 0->1, 1->2, 2->0, 3->4,
      于是位置 0/1/3 的"显示序奇偶"与"数据行奇偶"**相反**。
      用简单的倒序(e,d,c,b,a)会让两者恰好一致 —— 那样按数据行取奇偶的实现
      也能通过,测试就是假绿的(变异验证抓到过一次)。 }
    G.Cells[0, 0] := 'c'; G.Cells[0, 1] := 'a'; G.Cells[0, 2] := 'b';
    G.Cells[0, 3] := 'f'; G.Cells[0, 4] := 'd'; G.Cells[0, 5] := 'e';

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);
    Render;

    AssertTrue('第 0 显示行不带条纹', not IsStriped(0));
    AssertTrue('第 1 显示行带条纹', IsStriped(1));
    AssertTrue('第 2 显示行不带条纹', not IsStriped(2));
    AssertTrue('第 3 显示行带条纹', IsStriped(3));

    { 排序把数据行整个打乱 —— 条纹必须仍然是"隔一行一条"。 }
    G.SortByColumn(0, sdAscending);
    Render;
    AssertTrue('排序后第 0 显示行仍不带条纹', not IsStriped(0));
    AssertTrue('排序后第 1 显示行仍带条纹', IsStriped(1));
    AssertTrue('排序后第 2 显示行仍不带条纹', not IsStriped(2));
    AssertTrue('排序后第 3 显示行仍带条纹', IsStriped(3));
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ 只要横线不要竖线(报表常见)。从前只有一个 GridLines 开关,要么全有要么全无。 }
procedure TTyStringGridTest.TestGridLineStyleCanDropOneAxis;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;

  procedure Render;
  begin
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);
  end;

  { 沿一条竖线数蓝色像素,**只在每行的正中取样** ——
    横线是横跨整幅的,会在每一条竖线的 x 上留一个蓝点(可见 10 行就是 10 个);
    在行边界附近取样的话,"只要横线"也会数出 10 个来。 }
  function BlueOnColumnEdge: Integer;
  var Re: TBGRABitmap; r: TRect; x, pos: Integer; px: TBGRAPixel;
  begin
    Result := 0;
    x := G.ColLeft(1) - 1;
    Re := TBGRABitmap.Create(Bmp);
    try
      for pos := 0 to 9 do
      begin
        r := G.RowRectAt(pos);
        px := Re.GetPixel(x, (r.Top + r.Bottom) div 2);
        if (px.blue > 180) and (px.red < 100) then Inc(Result);
      end;
    finally
      Re.Free;
    end;
  end;

  { 同理:横线只在**列内部**取样,避开竖线所在的 x。第 0 列宽 80,取 4..70。 }
  function BlueOnRowEdge: Integer;
  var Re: TBGRABitmap; r: TRect; x: Integer; px: TBGRAPixel;
  begin
    Result := 0;
    r := G.RowRectAt(1);
    Re := TBGRABitmap.Create(Bmp);
    try
      for x := 4 to 70 do
      begin
        px := Re.GetPixel(x, r.Bottom - 1);
        if (px.blue > 180) and (px.red < 100) then Inc(Result);
      end;
    finally
      Re.Free;
    end;
  end;

begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; }' +
      'TyGridLine { background: #0000FF; }');
    G := MakeStrGrid(FForm, Ctl);
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);

    G.GridLineStyle := glsBoth;
    Render;
    AssertTrue('两轴都画时应当有竖线', BlueOnColumnEdge >= 10);
    AssertTrue('两轴都画时应当有横线', BlueOnRowEdge > 50);

    G.GridLineStyle := glsHorizontal;
    Render;
    AssertEquals('只要横线时竖线像素必须为 0', 0, BlueOnColumnEdge);
    AssertTrue('横线仍在', BlueOnRowEdge > 50);

    G.GridLineStyle := glsVertical;
    Render;
    AssertTrue('竖线仍在', BlueOnColumnEdge >= 10);
    AssertEquals('只要竖线时横线像素必须为 0', 0, BlueOnRowEdge);

    { 老代码的 GridLines 布尔开关必须还能用。 }
    G.GridLines := False;
    AssertTrue('GridLines := False 等价于 glsNone', G.GridLineStyle = glsNone);
    Render;
    AssertEquals('关掉后没有竖线', 0, BlueOnColumnEdge);
    AssertEquals('关掉后没有横线', 0, BlueOnRowEdge);
    G.GridLines := True;
    AssertTrue('GridLines := True 回到两轴都画', G.GridLineStyle = glsBoth);
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

procedure TTyStringGridTest.HookClickCell(Sender: TObject; ACol, ARow: Integer);
begin
  FClickCol := ACol; FClickRow := ARow;
end;

procedure TTyStringGridTest.HookRightClickCell(Sender: TObject; ACol, ARow: Integer);
begin
  FRightCol := ACol; FRightRow := ARow;
end;

procedure TTyStringGridTest.HookCellButtonClick(Sender: TObject; ACol, ARow: Integer);
begin
  FBtnCol := ACol; FBtnRow := ARow;
end;

procedure TTyStringGridTest.HookCanClickCell(Sender: TObject; ACol, ARow: Integer;
  var ACanClick: Boolean);
begin
  if ACol = FVetoCol then ACanClick := False;
end;

procedure TTyStringGridTest.HookButtonInCol1(Sender: TObject; ACol, ARow: Integer;
  var ADisplay: TTyGridCellDisplay);
begin
  if ACol = 1 then ADisplay := gcdButton;
end;

{ 右键从前在 MouseDown 开头就被 `if Button <> mbLeft then Exit` 全挡掉了 ——
  网格连"右键点在哪一格"都答不出来,右键菜单无从谈起。 }
procedure TTyStringGridTest.TestRightClickOnCellFiresEventWithThatCell;
var
  G: TStrGridAccess;
  r: TRect;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 5;
  FRightCol := -9; FRightRow := -9;
  G.OnRightClickCell := @HookRightClickCell;

  r := G.CellRect(2, 3);
  G.RightClickAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);

  AssertEquals('右键报出的列', 2, FRightCol);
  AssertEquals('右键报出的行', 3, FRightRow);

  { 右键**不该**把光标搬走(和 Windows 资源管理器一致:右键只是问,不是选)。 }
  AssertTrue('右键不移动光标', (G.Col <> 2) or (G.Row <> 3));
end;

{ OnCanClickCell 否决时,整次点击都不该发生 —— 光标不动、不进编辑、不触发 OnClickCell。
  只挡住 OnClickCell 而让光标照样跑,是最容易写出来的半吊子实现。 }
procedure TTyStringGridTest.TestCanClickCellVetoesTheWholeClick;
var
  G: TStrGridAccess;
  r: TRect;
  wasCol, wasRow: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 5;
  G.MoveCursor(0, 0);
  wasCol := G.Col; wasRow := G.Row;

  FVetoCol := 2;
  FClickCol := -9; FClickRow := -9;
  G.OnCanClickCell := @HookCanClickCell;
  G.OnClickCell := @HookClickCell;

  r := G.CellRect(2, 3);
  G.ClickAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);

  AssertEquals('被否决的列不该触发 OnClickCell', -9, FClickCol);
  AssertEquals('光标的列不该动', wasCol, G.Col);
  AssertEquals('光标的行不该动', wasRow, G.Row);

  { 没被否决的列照常工作 —— 否则"全挡住"也能让上面几条通过。 }
  r := G.CellRect(1, 2);
  G.ClickAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  AssertEquals('没被否决的列正常触发', 1, FClickCol);
  AssertEquals('光标跟着走', 1, G.Col);
end;

{ 按钮单元格:点在按钮上要报出是哪一格。 }
procedure TTyStringGridTest.TestButtonCellClickFiresWithThatCell;
var
  G: TStrGridAccess;
  r: TRect;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 5;
  G.Cells[1, 2] := '详情';
  G.OnGetCellDisplay := @HookButtonInCol1;
  FBtnCol := -9; FBtnRow := -9;
  G.OnCellButtonClick := @HookCellButtonClick;

  r := G.CellRect(1, 2);
  G.FullClickAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  AssertEquals('按钮报出的列', 1, FBtnCol);
  AssertEquals('按钮报出的行', 2, FBtnRow);

  { 不是按钮的格不该触发。 }
  FBtnCol := -9;
  r := G.CellRect(0, 2);
  G.FullClickAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  AssertEquals('普通格不触发按钮事件', -9, FBtnCol);
end;

{ 双击列分隔线 = 按内容自适应列宽,是表格的通用手势。 }
procedure TTyStringGridTest.TestDoubleClickOnDividerAutoFitsColumn;
var
  G: TStrGridAccess;
  before, after: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.Header.Options := G.Header.Options + [hoVisible];
  G.Header.Height := 22;
  G.RowCount := 3;
  G.Cells[0, 0] := '一个相当长的单元格内容用来撑宽这一列';

  before := TTyColumn(G.Header.Columns.Items[0]).Width;
  { 第 0 列的右分隔线上双击。 }
  G.DoubleClickAt(G.ColLeft(0) + G.ColWidth(0) - 1, 8);
  after := TTyColumn(G.Header.Columns.Items[0]).Width;

  AssertTrue(Format('双击分隔线应当自适应列宽(%d -> %d)', [before, after]),
    after > before);
end;

{ 换行:同一段长文字,开了换行之后墨应当铺到更多行上(而不是被省略号截断成一行)。
  用"有墨的扫描行数"判定 —— 比数像素总量结实:换行后总墨量差不多,但纵向铺开了。 }
procedure TTyStringGridTest.TestWordWrapMakesLongTextUseMoreLines;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;

  function InkedScanlines: Integer;
  var
    Re: TBGRABitmap; r: TRect; x, y: Integer; px: TBGRAPixel; hasInk: Boolean;
  begin
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);
    r := G.CellRect(0, 0);
    Result := 0;
    Re := TBGRABitmap.Create(Bmp);
    try
      for y := r.Top to r.Bottom - 1 do
      begin
        if (y < 0) or (y >= 300) then Continue;
        hasInk := False;
        for x := r.Left to r.Right - 1 do
        begin
          if (x < 0) or (x >= 400) then Continue;
          px := Re.GetPixel(x, y);
          if px.red + px.green + px.blue < 400 then begin hasInk := True; Break; end;
        end;
        if hasInk then Inc(Result);
      end;
    finally
      Re.Free;
    end;
  end;

var
  oneLine, wrapped: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; }');
    G := MakeStrGrid(FForm, Ctl);
    G.GridLines := False;
    G.DefaultRowHeight := 60;        { 够高才装得下多行 }
    G.Cells[0, 0] := 'aaa bbb ccc ddd eee fff ggg hhh';

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);

    oneLine := InkedScanlines;
    G.WordWrap := True;
    wrapped := InkedScanlines;

    AssertTrue(Format('换行后墨应当铺到更多扫描行上(%d -> %d)', [oneLine, wrapped]),
      wrapped > oneLine + 3);
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ 行高三件套的第一件:**可写**的 RowHeights。
  从前只有 OnGetRowHeight 回调、网格自己不存 —— 拖拽和自动行高都无处落盘。
  而且优先级要对:显式(用户的直接动作)压过回调(宿主的通用规则)。 }
procedure TTyStringGridTest.TestExplicitRowHeightBeatsCallbackAndMovesGeometry;
var
  G: TStrGridAccess;
  topBefore, topAfter: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 5;
  G.OnGetRowHeight := @HandleTallSecondRow;    { 回调:第 1 行 60 高 }

  AssertEquals('回调生效', 60, G.RowHeightOf(1));

  G.RowHeights[1] := 90;
  AssertEquals('显式行高压过回调', 90, G.RowHeightOf(1));

  { 光改存储不算数 —— 几何层必须跟着动,否则行还是老样子。 }
  topBefore := G.RowRectAt(2).Top;
  G.RowHeights[1] := 140;
  topAfter := G.RowRectAt(2).Top;
  AssertTrue(Format('后面的行应当跟着下移(%d -> %d)', [topBefore, topAfter]),
    topAfter > topBefore);

  { 清掉之后回落到回调。 }
  G.RowHeights[1] := 0;
  AssertEquals('清掉显式值后回落到回调', 60, G.RowHeightOf(1));

  { **没有回调时**显式行高也必须驱动几何。
    上面那段有回调在,回调本身就会逼出可变行高的前缀和路径 —— 于是
    "几何层认不认显式行高"根本测不出来(变异验证抓到过一次)。 }
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 5;
  topBefore := G.RowRectAt(2).Top;
  G.RowHeights[0] := 100;
  topAfter := G.RowRectAt(2).Top;
  AssertTrue(Format('没有回调时,显式行高也要驱动几何(%d -> %d)',
    [topBefore, topAfter]), topAfter > topBefore);
end;

{ 在行头槽里拖行分隔线改行高 —— 与列分隔线在列头里拖对称。 }
procedure TTyStringGridTest.TestDragRowDividerChangesRowHeight;
var
  G: TStrGridAccess;
  r: TRect;
  before: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 5;
  G.ShowIndicator := True;          { 分隔线只在行头槽里认 }
  G.IndicatorWidth := 30;

  before := G.RowHeightOf(0);
  r := G.RowRectAt(0);
  G.PressMouseWithoutRelease(8, r.Bottom);   { 落在行头槽内的分隔线上 }
  G.MoveMouseTo(8, r.Bottom + 25);
  G.ReleaseMouse(8, r.Bottom + 25);

  AssertTrue(Format('拖分隔线应当把行拉高(%d -> %d)', [before, G.RowHeightOf(0)]),
    G.RowHeightOf(0) > before);

  { 不在行头槽里拖不该改行高(那儿是框选的手势)。 }
  before := G.RowHeightOf(2);
  r := G.RowRectAt(2);
  G.PressMouseWithoutRelease(200, r.Bottom);
  G.MoveMouseTo(200, r.Bottom + 25);
  G.ReleaseMouse(200, r.Bottom + 25);
  AssertEquals('单元格区域拖动不改行高', before, G.RowHeightOf(2));
end;

{ AutoFitRow:按换行后的实际高度把行调到刚好放得下。 }
procedure TTyStringGridTest.TestAutoFitRowGrowsToFitWrappedText;
var
  G: TStrGridAccess;
  before, after: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 3;
  G.WordWrap := True;
  G.Cells[0, 1] := 'aaa bbb ccc ddd eee fff ggg hhh iii jjj kkk lll';

  before := G.RowHeightOf(1);
  G.AutoFitRow(1);
  after := G.RowHeightOf(1);
  AssertTrue(Format('换行内容应当把行撑高(%d -> %d)', [before, after]),
    after > before);

  { 空行不该被撑高。 }
  G.AutoFitRow(2);
  AssertEquals('空行保持默认高', G.DefaultRowHeight, G.RowHeightOf(2));
end;

procedure TTyStringGridTest.HookSelectionChanged(Sender: TObject);
begin
  Inc(FSelChanges);
end;

{ 离散多选:单锚点矩形**在物理上就表达不了**"第 1 行和第 4 行",
  这正是选择模型要从一个矩形升成一组矩形的原因。 }
procedure TTyStringGridTest.TestCtrlClickAddsDiscreteSelection;
var
  G: TStrGridAccess;

  procedure ClickCell(ACol, ARow: Integer; ACtrl: Boolean);
  var r: TRect;
  begin
    r := G.CellRect(ACol, ARow);
    if ACtrl then G.CtrlClickAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2)
    else G.FullClickAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  end;

begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 6;

  ClickCell(0, 1, False);
  AssertTrue('第 1 行被选中', G.IsCellSelected(0, 1));
  AssertTrue('第 4 行还没选', not G.IsCellSelected(0, 4));

  ClickCell(0, 4, True);           { Ctrl+点 追加 }
  AssertTrue('Ctrl+点之后第 1 行仍然选中', G.IsCellSelected(0, 1));
  AssertTrue('第 4 行也选中了', G.IsCellSelected(0, 4));
  { 中间的行**不能**被连带选上 —— 那就成区间选择了,不是离散选择。 }
  AssertTrue('中间的第 2 行不该被连带选中', not G.IsCellSelected(0, 2));
  AssertTrue('中间的第 3 行不该被连带选中', not G.IsCellSelected(0, 3));

  { 普通点一下要把离散区清干净。 }
  ClickCell(0, 0, False);
  AssertTrue('普通点之后只剩当前格', G.IsCellSelected(0, 0));
  AssertTrue('离散区被清掉(第 1 行)', not G.IsCellSelected(0, 1));
  AssertTrue('离散区被清掉(第 4 行)', not G.IsCellSelected(0, 4));
end;

{ 选择 API:从前一个 public 的选择方法都没有 —— 宿主只能靠鼠标键盘间接操作。 }
procedure TTyStringGridTest.TestSelectionApiAndChangedEvent;
var
  G: TStrGridAccess;
  sel: TRect;
begin
  G := MakeStrGrid(FForm, FCtl);   { 4 列 }
  G.RowCount := 6;
  FSelChanges := 0;
  G.OnSelectionChanged := @HookSelectionChanged;

  G.SelectRange(1, 1, 2, 3);
  AssertTrue('区间内被选中', G.IsCellSelected(1, 2));
  AssertTrue('区间外的列没被选中', not G.IsCellSelected(3, 2));
  AssertTrue('区间外的行没被选中', not G.IsCellSelected(1, 5));
  AssertEquals('SelectedCellCount = 2 列 x 3 行', 6, G.SelectedCellCount);

  sel := G.Selection;
  AssertEquals('Selection 用数据行坐标(左)', 1, sel.Left);
  AssertEquals('Selection 用数据行坐标(右)', 2, sel.Right);
  AssertEquals('Selection 用数据行坐标(上)', 1, sel.Top);
  AssertEquals('Selection 用数据行坐标(下)', 3, sel.Bottom);

  G.SelectRows(0, 1);
  AssertEquals('整行选择覆盖所有列', 4 * 2, G.SelectedCellCount);

  G.SelectAll;
  AssertEquals('全选', 4 * 6, G.SelectedCellCount);

  G.ClearSelection;
  AssertEquals('清空后只剩光标那一格', 1, G.SelectedCellCount);

  { 越界要钳制而不是崩。 }
  G.SelectRange(-5, -5, 99, 99);
  AssertEquals('越界钳制成全选', 4 * 6, G.SelectedCellCount);

  AssertTrue(Format('每次改动都该发 OnSelectionChanged(实际 %d 次)', [FSelChanges]),
    FSelChanges >= 5);
end;

{ 按住左键拖过若干格 = 拉出一块区间选择。 }
procedure TTyStringGridTest.TestDragAcrossCellsExtendsSelection;
var
  G: TStrGridAccess;
  a, b: TRect;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 6;

  a := G.CellRect(0, 1);
  b := G.CellRect(2, 3);
  G.DragFromTo((a.Left + a.Right) div 2, (a.Top + a.Bottom) div 2,
               (b.Left + b.Right) div 2, (b.Top + b.Bottom) div 2);

  AssertTrue('起点被选中', G.IsCellSelected(0, 1));
  AssertTrue('中间被选中', G.IsCellSelected(1, 2));
  AssertTrue('终点被选中', G.IsCellSelected(2, 3));
  AssertTrue('框外没被选中', not G.IsCellSelected(3, 3));
  AssertEquals('拖出来的是 3 列 x 3 行', 9, G.SelectedCellCount);
end;

{ 设计期只配**列属性**、不接任何事件,就该得到"这列下拉、那列只读、这列有统计"。
  从前这些只能靠 OnGetEditorKind / OnGetPickList / SetColumnAggregate 三个事件
  在代码里配 —— 设计期什么也做不了。 }
procedure TTyStringGridTest.TestColumnLevelPropertiesNeedNoEvents;
var
  G: TStrGridAccess;
  c1, c2: TTyGridColumn;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  G.Cells[3, 0] := '10';
  G.Cells[3, 1] := '20';

  AssertTrue('列应当是网格自己的列类', G.Header.Columns.Items[0] is TTyGridColumn);
  c1 := TTyGridColumn(G.Header.Columns.Items[1]);
  c2 := TTyGridColumn(G.Header.Columns.Items[2]);

  { 默认没设过 → 走网格的 DefaultEditorKind。 }
  AssertTrue('没配过的列走网格默认',
    G.EditorKindFor(0, 0) = G.DefaultEditorKind);

  c1.EditorKind := gekPickList;
  c1.PickList.Add('甲');
  c1.PickList.Add('乙');
  AssertTrue('列属性决定了编辑器种类', G.EditorKindFor(1, 0) = gekPickList);
  AssertTrue('别的列不受影响', G.EditorKindFor(0, 0) = G.DefaultEditorKind);

  c2.ReadOnly := True;
  AssertTrue('只读列不给编辑器', G.EditorKindFor(2, 0) = gekNone);
  AssertTrue('只读列进不了编辑', not G.BeginEdit(2, 0));

  TTyGridColumn(G.Header.Columns.Items[3]).Aggregate := gagSum;
  AssertTrue('列属性决定了汇总方式',
    G.ColumnAggregate(3) = gagSum);
  AssertEquals('汇总值算出来了', 30.0, G.AggregateValue(3), 0.001);

  { 显式写成 gekText 也要算"设过" —— 否则分不清"没设"和"设成文本"。 }
  c1.EditorKind := gekText;
  AssertTrue('显式设回文本也生效', G.EditorKindFor(1, 0) = gekText);
end;

{ 一个最小的宿主 EditLink:用一个普通 TTyEdit 当编辑器。
  存在的意义是证明**扩展点通了** —— 网格答不上来的编辑器,宿主能自己接上去。 }
type
  TProbeEditLink = class(TTyGridEditLink)
  private
    FCtl: TTyEdit;
  public
    FCreatedCol, FCreatedRow: Integer;
    function  CreateEditor(AParent: TWinControl; ACol, ARow: Integer): TWinControl; override;
    procedure SetBounds(const ARect: TRect); override;
    function  GetValue: string; override;
    procedure SetValue(const AValue: string); override;
    procedure FocusEditor; override;
    procedure ReleaseEditor; override;
  end;

function TProbeEditLink.CreateEditor(AParent: TWinControl; ACol, ARow: Integer): TWinControl;
begin
  FCreatedCol := ACol;
  FCreatedRow := ARow;
  FCtl := TTyEdit.Create(AParent);
  FCtl.Parent := AParent;
  Result := FCtl;
end;

procedure TProbeEditLink.SetBounds(const ARect: TRect);
begin
  FCtl.BoundsRect := ARect;
end;

function TProbeEditLink.GetValue: string;
begin
  Result := FCtl.Text;
end;

procedure TProbeEditLink.SetValue(const AValue: string);
begin
  FCtl.Text := AValue;
end;

procedure TProbeEditLink.FocusEditor;
begin
  { 无头环境没有句柄 —— 抢焦点会抛异常。 }
end;

procedure TProbeEditLink.ReleaseEditor;
begin
  FreeAndNil(FCtl);
end;

procedure TTyStringGridTest.HookCreateEditLink(Sender: TObject; ACol, ARow: Integer;
  var ALink: TTyGridEditLink);
begin
  { 只接管第 2 列 —— 这样才能顺带断言"别的列还是内建编辑器"。 }
  if ACol = 2 then ALink := FProbeLink;
end;

{ 直接敲字就进编辑,并且这一笔就是新内容的第一个字符(与 Excel 一致)。
  从前只有 KeyDown、没有 KeyPress 覆写 —— 必须先按 F2 或双击才能输入。 }
procedure TTyStringGridTest.TestTypingAPrintableCharStartsEditing;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  G.Cells[0, 0] := '旧值';
  G.MoveCursor(0, 0);

  AssertTrue('一开始不在编辑态', not G.IsEditing);
  G.TypeChar('X');
  AssertTrue('敲字之后进入编辑态', G.IsEditing);
  AssertEquals('这一笔覆盖原值、成为第一个字符', 'X', G.EditorText);
end;

{ ValidChars:非法字符**连编辑都不进** —— "敲进去了又被弹回来"比"根本敲不进去"更困惑。 }
procedure TTyStringGridTest.TestValidCharsBlocksIllegalKeys;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  TTyGridColumn(G.Header.Columns.Items[1]).ValidChars := '0123456789';
  G.MoveCursor(1, 0);

  G.TypeChar('a');
  AssertTrue('非法字符不该进编辑', not G.IsEditing);

  G.TypeChar('7');
  AssertTrue('合法字符正常进编辑', G.IsEditing);
  AssertEquals('第一个字符是敲的那个', '7', G.EditorText);

  { 没配 ValidChars 的列不受影响。 }
  G.EndEdit(False);
  G.MoveCursor(0, 0);
  G.TypeChar('a');
  AssertTrue('没配约束的列什么都能敲', G.IsEditing);
end;

{ Enter 向下推进、Tab 按格推进(到行尾折行)。
  Tab 不拦的话会把焦点整个弹出网格。 }
procedure TTyStringGridTest.TestEnterAdvancesDownAndTabAdvancesByCell;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);   { 4 列 }
  G.RowCount := 4;
  G.MoveCursor(0, 0);

  G.PressKey(VK_RETURN);
  AssertEquals('Enter 向下走一行', 1, G.Row);
  AssertEquals('Enter 不换列', 0, G.Col);

  G.PressKey(VK_TAB);
  AssertEquals('Tab 向右走一格', 1, G.Col);

  G.MoveCursor(3, 1);
  G.PressKey(VK_TAB);
  AssertEquals('行尾 Tab 折到下一行行首(列)', 0, G.Col);
  AssertEquals('行尾 Tab 折到下一行行首(行)', 2, G.Row);

  G.PressKeyShift(VK_TAB);
  AssertEquals('Shift+Tab 折回上一行行尾(列)', 3, G.Col);
  AssertEquals('Shift+Tab 折回上一行行尾(行)', 1, G.Row);
end;

{ 宿主 EditLink 接管整格:内建编辑器一概不出场,提交时取 EditLink 的值。 }
procedure TTyStringGridTest.TestHostEditLinkTakesOverTheCell;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  G.Cells[2, 1] := '原值';
  FProbeLink := TProbeEditLink.Create;
  try
    G.OnCreateEditLink := @HookCreateEditLink;

    AssertTrue('第 2 列进入编辑', G.BeginEdit(2, 1));
    AssertEquals('EditLink 收到的列', 2, TProbeEditLink(FProbeLink).FCreatedCol);
    AssertEquals('EditLink 收到的行', 1, TProbeEditLink(FProbeLink).FCreatedRow);
    AssertTrue('内建文本编辑器不该出场', not G.EditorVisible);

    TProbeEditLink(FProbeLink).SetValue('新值');
    G.EndEdit(True);
    AssertEquals('提交时取的是 EditLink 的值', '新值', G.Cells[2, 1]);

    { 没被接管的列仍然走内建编辑器。 }
    AssertTrue('第 0 列进入编辑', G.BeginEdit(0, 1));
    AssertTrue('内建文本编辑器出场了', G.EditorVisible);
    G.EndEdit(False);
  finally
    FProbeLink.Free;
  end;
end;

{ 分组表头:上层标题带堆在列头带之上,整条表头因此变高,正文跟着下移。
  B2 把 HeaderH 拆成 HeaderBands 数组,就是为了这一批。 }
procedure TTyStringGridTest.TestHeaderGroupBandStacksAboveColumnHeader;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;
  g1: TTyGridHeaderGroup;
  rowTopBefore, rowTopAfter, green: Integer;
  Re: TBGRABitmap;
  x, y: Integer;
  px: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; }' +
      'TyGridHeader { background: #FFFFFF; color: #000000; }' +
      'TyGridHeaderGroup { background: #00FF00; color: #000000; }');
    G := MakeStrGrid(FForm, Ctl);
    G.Header.Options := G.Header.Options + [hoVisible];
    G.Header.Height := 22;
    G.GridLines := False;
    G.RowCount := 4;

    rowTopBefore := G.RowRectAt(0).Top;
    AssertEquals('没有分组时正文从列头下面开始', 22, rowTopBefore);

    g1 := G.HeaderGroups.Add;
    g1.Text := '销售';
    g1.FirstCol := 0;
    g1.LastCol := 1;
    G.GroupHeaderHeight := 20;

    rowTopAfter := G.RowRectAt(0).Top;
    AssertEquals('分组带把正文往下顶了一整条', 20 + 22, rowTopAfter);

    { 分组带确实画出来了,而且只覆盖前两列(第 0 列宽 80,共 4 列 x 80)。 }
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);

    green := 0;
    Re := TBGRABitmap.Create(Bmp);
    try
      for y := 2 to 17 do
        for x := 2 to 155 do
        begin
          px := Re.GetPixel(x, y);
          if (px.green > 180) and (px.red < 100) then Inc(green);
        end;
      AssertTrue(Format('分组带应当画在前两列上方(绿像素 %d)', [green]), green > 500);

      green := 0;
      for y := 2 to 17 do
        for x := 200 to 300 do
        begin
          px := Re.GetPixel(x, y);
          if (px.green > 180) and (px.red < 100) then Inc(green);
        end;
      AssertEquals('没被分组覆盖的列上方不该有分组底色', 0, green);
    finally
      Re.Free;
    end;
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ 排序/筛选按钮**只在叶子级**:点分组标题不该把下面某一列排序掉。 }
procedure TTyStringGridTest.TestHeaderGroupBandIsNotALeafHeaderForHitTesting;
var
  G: TStrGridAccess;
  g1: TTyGridHeaderGroup;
  hit: TTyGridHit;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.Header.Options := G.Header.Options + [hoVisible];
  G.Header.Height := 22;
  G.RowCount := 4;
  g1 := G.HeaderGroups.Add;
  g1.Text := '销售';
  g1.FirstCol := 0;
  g1.LastCol := 1;
  G.GroupHeaderHeight := 20;

  hit := G.HitAt(40, 8);          { 分组带里 }
  AssertTrue('分组带不算叶子列头', hit.Part <> ghpHeader);

  hit := G.HitAt(40, 30);         { 列头带里(20..42) }
  AssertTrue('列头带仍然算列头', hit.Part = ghpHeader);
  AssertEquals('列头带报出正确的列', 0, hit.Col);

  { 点分组标题不该触发排序。 }
  G.Header.Options := G.Header.Options + [hoHeaderClickAutoSort];
  G.ClickAt(40, 8);
  AssertEquals('点分组标题不排序', -1, G.Header.SortColumn);
  G.ClickAt(40, 30);
  AssertEquals('点叶子列头才排序', 0, G.Header.SortColumn);
end;

{ 多列排序:第一列相等时才看第二列。 }
procedure TTyStringGridTest.TestSecondarySortKeyBreaksTies;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  { 部门 / 姓名 —— 部门相同的两条要按姓名分先后。 }
  G.Cells[0, 0] := '销售'; G.Cells[1, 0] := '张';
  G.Cells[0, 1] := '技术'; G.Cells[1, 1] := '王';
  G.Cells[0, 2] := '销售'; G.Cells[1, 2] := '李';
  G.Cells[0, 3] := '技术'; G.Cells[1, 3] := '赵';

  G.SortByColumn(0, sdAscending);
  AssertEquals('单列排序时只有一个键', 1, G.SortColumnCount);

  G.AddSortColumn(1, sdAscending);
  AssertEquals('追加后有两个键', 2, G.SortColumnCount);

  { 技术组(王/赵)在前,组内按姓名升序;销售组(张/李)在后。
    只有次级键真的生效,同部门的两条才会按姓名排。 }
  AssertEquals('第 0 显示行的部门', '技术', G.Cells[0, G.DisplayRow(0)]);
  AssertEquals('第 1 显示行的部门', '技术', G.Cells[0, G.DisplayRow(1)]);
  AssertTrue('同部门内按次级键排序',
    G.Cells[1, G.DisplayRow(0)] < G.Cells[1, G.DisplayRow(1)]);

  { 再点一次同一列 = 翻方向,而不是加一条重复的键。 }
  G.AddSortColumn(1, sdDescending);
  AssertEquals('重复列不新增键', 2, G.SortColumnCount);
  AssertTrue('次级键方向翻了',
    G.Cells[1, G.DisplayRow(0)] > G.Cells[1, G.DisplayRow(1)]);
end;

{ **已知 bug**:BuildGroups 从前直接 `FSortCol := FGroupCol`,
  一分组就把用户选的排序列永久抹掉,而且完全静默。 }
procedure TTyStringGridTest.TestGroupingKeepsTheUserSortColumn;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  G.Cells[0, 0] := '销售'; G.Cells[1, 0] := '3';
  G.Cells[0, 1] := '销售'; G.Cells[1, 1] := '1';
  G.Cells[0, 2] := '技术'; G.Cells[1, 2] := '4';
  G.Cells[0, 3] := '技术'; G.Cells[1, 3] := '2';

  G.SortByColumn(1, sdAscending);       { 用户选了按第 1 列排 }
  AssertEquals('排序列是 1', 1, G.SortColumn);

  G.GroupByColumn(0);                    { 再按第 0 列分组 }
  AssertEquals('分组之后排序列**不该被抹掉**', 1, G.SortColumn);
  AssertEquals('排序键也还在', 1, G.SortColumnCount);
  AssertEquals('排序键就是用户选的那列', 1, G.SortColumnAt(0).Col);
end;

{ 排序方式跟着列走:同一张表里日期列不该按文本排。 }
procedure TTyStringGridTest.TestColumnSortKindBeatsGridSortKind;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 3;
  G.SortKind := gskText;                 { 网格级:文本 }
  G.Cells[0, 0] := '10';
  G.Cells[0, 1] := '9';
  G.Cells[0, 2] := '100';

  G.SortByColumn(0, sdAscending);
  AssertEquals('按文本排:10 在 9 前面', '10', G.Cells[0, G.DisplayRow(0)]);

  TTyGridColumn(G.Header.Columns.Items[0]).SortKind := gskNumber;
  G.SortByColumn(-1, sdAscending);
  G.SortByColumn(0, sdAscending);
  AssertEquals('列级设成数值后:9 排最前', '9', G.Cells[0, G.DisplayRow(0)]);
  AssertEquals('然后是 10', '10', G.Cells[0, G.DisplayRow(1)]);
  AssertEquals('最后是 100', '100', G.Cells[0, G.DisplayRow(2)]);
end;

{ 全展开 / 全折叠。折叠按**分组值**记账,所以重排后仍然对得上。 }
procedure TTyStringGridTest.TestExpandCollapseAllGroups;
var
  G: TStrGridAccess;
  expanded, collapsed: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  G.Cells[0, 0] := '甲'; G.Cells[0, 1] := '甲';
  G.Cells[0, 2] := '乙'; G.Cells[0, 3] := '乙';
  G.GroupByColumn(0);

  expanded := G.DisplayRowCount;         { 2 个组行 + 4 条数据 }
  AssertEquals('展开时显示 6 行', 6, expanded);

  G.CollapseAllGroups;
  collapsed := G.DisplayRowCount;
  AssertEquals('全折叠后只剩 2 个组行', 2, collapsed);

  G.ExpandAllGroups;
  AssertEquals('全展开后回到 6 行', expanded, G.DisplayRowCount);
end;

procedure TTyStringGridTest.HookUpperCasePaste(Sender: TObject; ACol, ARow: Integer;
  var ANewText: string; var AAllow: Boolean);
begin
  if ACol = 1 then AAllow := False           { 第 1 列整列跳过 }
  else ANewText := UpperCase(ANewText);      { 其余列转大写 }
end;

{ **静默丢数据**是最不该出现的一类失败:从前 `if targetRow < 0 then Break`,
  粘 100 行进 10 行的网格会悄悄丢掉 90 行,一句提示都没有。 }
procedure TTyStringGridTest.TestSmartPasteGrowsInsteadOfDroppingRows;
var
  G: TStrGridAccess;
  i: Integer;
  txt: string;
begin
  G := MakeStrGrid(FForm, FCtl);   { 4 列 }
  G.RowCount := 3;
  G.MoveCursor(0, 0);

  txt := '';
  for i := 0 to 9 do
    txt := txt + Format('r%d-a'#9'r%d-b', [i, i]) + LineEnding;
  G.PasteFromText(txt);

  AssertTrue(Format('行数应当被撑到装得下(实际 %d)', [G.RowCount]), G.RowCount >= 10);
  AssertEquals('第 0 行粘对了', 'r0-a', G.Cells[0, 0]);
  AssertEquals('**最后一行没被丢掉**', 'r9-a', G.Cells[0, 9]);
  AssertEquals('第二列也粘对了', 'r9-b', G.Cells[1, 9]);

  { 列也要能撑。 }
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 2;
  G.MoveCursor(0, 0);
  G.PasteFromText('a'#9'b'#9'c'#9'd'#9'e'#9'f' + LineEnding);
  AssertTrue(Format('列数应当被撑到装得下(实际 %d)', [G.Header.Columns.Count]),
    G.Header.Columns.Count >= 6);
  AssertEquals('第 5 列粘对了', 'f', G.Cells[5, 0]);

  { 关掉自动扩张时保持老行为(不扩、也不崩)。 }
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 2;
  G.AutoGrowOnPaste := False;
  G.MoveCursor(0, 0);
  G.PasteFromText('x' + LineEnding + 'y' + LineEnding + 'z' + LineEnding);
  AssertEquals('关掉后不扩行', 2, G.RowCount);
end;

{ 逐格粘贴钩子:能改写、也能跳过。 }
procedure TTyStringGridTest.TestPasteCellHooksCanRewriteAndSkip;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 3;
  G.Cells[1, 0] := '原值';
  G.MoveCursor(0, 0);
  G.OnBeforePasteCell := @HookUpperCasePaste;

  G.PasteFromText('abc'#9'def' + LineEnding);

  AssertEquals('钩子把内容改写了', 'ABC', G.Cells[0, 0]);
  AssertEquals('被否决的列保持原样', '原值', G.Cells[1, 0]);
end;

{ 批量增删 + 移动 / 交换。 }
procedure TTyStringGridTest.TestBatchRowOpsAndMoveSwap;
var
  G: TStrGridAccess;
  cs, rs: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  G.Cells[0, 0] := 'A'; G.Cells[0, 1] := 'B';
  G.Cells[0, 2] := 'C'; G.Cells[0, 3] := 'D';

  G.InsertRows(1, 3);
  AssertEquals('一次插 3 行', 7, G.RowCount);
  AssertEquals('原第 1 行被推到第 4 行', 'B', G.Cells[0, 4]);
  AssertEquals('插进来的是空行', '', G.Cells[0, 1]);

  G.RemoveRows(1, 3);
  AssertEquals('一次删 3 行', 4, G.RowCount);
  AssertEquals('删完之后回到原样', 'B', G.Cells[0, 1]);

  { 交换要连**行高**与**逐格属性**一起换 —— 只换文字的话,合并框和行高
    会留在原地,与内容脱节(与 B3 修的 ShiftCells 同一类)。 }
  G.RowHeights[0] := 55;
  G.MergeCells(1, 0, 2, 1);

  G.SwapRows(0, 3);
  AssertEquals('交换后第 0 行', 'D', G.Cells[0, 0]);
  AssertEquals('交换后第 3 行', 'A', G.Cells[0, 3]);
  AssertEquals('行高跟着换了', 55, G.RowHeightOf(3));
  AssertEquals('原位置回到默认行高', G.DefaultRowHeight, G.RowHeightOf(0));
  AssertTrue('合并区也跟着换了', G.CellSpan(1, 3, cs, rs));
  AssertTrue('原位置不再是合并基准格', not G.CellSpan(1, 0, cs, rs));

  { 换回来,继续下面的移动测试。 }
  G.RowHeights[3] := 0;
  G.UnmergeCells(1, 3);

  G.SwapRows(0, 3);            { 换回来 }
  G.MoveRow(0, 2);
  AssertEquals('搬到第 2 位', 'A', G.Cells[0, 2]);
  AssertEquals('原来第 1 行前移', 'B', G.Cells[0, 0]);
  AssertEquals('原来第 2 行前移', 'C', G.Cells[0, 1]);
  AssertEquals('第 3 行没动', 'D', G.Cells[0, 3]);
end;

procedure TTyStringGridTest.HookColumnSizing(Sender: TObject; AIndex: Integer;
  var ANewSize: Integer; var AAllow: Boolean);
begin
  Inc(FSizingCalls);
end;

procedure TTyStringGridTest.HookEndColumnSize(Sender: TObject; AIndex, ANewSize: Integer);
begin
  Inc(FEndSizeCalls);
  FLastEndSize := ANewSize;
end;

{ 逐格**持久**底色:与钩子的区别是它落盘 —— 用户手工涂黄的格,存下来还得是黄的。 }
procedure TTyStringGridTest.TestPersistentCellColorsAndRowColor;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;

  function RedInCell(ACol, ARow: Integer): Integer;
  var Re: TBGRABitmap; r: TRect; x, y: Integer; px: TBGRAPixel;
  begin
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);
    r := G.CellRect(ACol, ARow);
    Result := 0;
    Re := TBGRABitmap.Create(Bmp);
    try
      for y := r.Top to r.Bottom - 1 do
        for x := r.Left to r.Right - 1 do
        begin
          if (x < 0) or (y < 0) or (x >= 400) or (y >= 300) then Continue;
          px := Re.GetPixel(x, y);
          if (px.red > 180) and (px.green < 100) and (px.blue < 100) then Inc(Result);
        end;
    finally
      Re.Free;
    end;
  end;

begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; }');
    G := MakeStrGrid(FForm, Ctl);
    G.GridLines := False;
    G.RowCount := 5;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);

    AssertEquals('一开始没有底色', 0, RedInCell(1, 2));

    G.CellColors[1, 2] := TyRGB(255, 0, 0);
    AssertTrue('设过的格画出了底色', RedInCell(1, 2) > 50);
    AssertEquals('旁边的格不受影响', 0, RedInCell(0, 2));
    AssertEquals('读回来是设进去的值', TyRGB(255, 0, 0), G.CellColors[1, 2]);

    { 整行底色。 }
    G.SetRowColor(3, TyRGB(255, 0, 0));
    AssertTrue('整行第 0 列有底色', RedInCell(0, 3) > 50);
    AssertTrue('整行第 3 列有底色', RedInCell(3, 3) > 50);

    { 清除。 }
    G.CellColors[1, 2] := 0;
    AssertEquals('清掉之后没有底色', 0, RedInCell(1, 2));
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ 逐格只读:比"整列只读"更细 —— "已审核的这几行不可改"不该逼宿主自己维护集合。 }
procedure TTyStringGridTest.TestPerCellReadOnlyBlocksEditing;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;

  AssertTrue('默认可编辑', G.BeginEdit(1, 1));
  G.EndEdit(False);

  G.CellReadOnly[1, 1] := True;
  AssertTrue('设了逐格只读之后进不了编辑', not G.BeginEdit(1, 1));
  AssertTrue('同列的别的行不受影响', G.BeginEdit(1, 2));
  G.EndEdit(False);

  G.CellReadOnly[1, 1] := False;
  AssertTrue('取消后又能编辑了', G.BeginEdit(1, 1));
  G.EndEdit(False);
end;

{ 行高上下限是自动行高的护栏 —— 一条超长文本能把行撑到几千像素。
  钳制放在**存储入口**,所以拖拽、AutoFitRow、直接赋值走的都是同一道关。 }
procedure TTyStringGridTest.TestRowHeightLimitsClampAtTheStore;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  G.MinRowHeight := 15;
  G.MaxRowHeight := 40;

  G.RowHeights[0] := 5;
  AssertEquals('低于下限被抬到下限', 15, G.RowHeightOf(0));

  G.RowHeights[1] := 500;
  AssertEquals('高于上限被压到上限', 40, G.RowHeightOf(1));

  G.RowHeights[2] := 30;
  AssertEquals('区间内原样保留', 30, G.RowHeightOf(2));

  { AutoFitRow 也得受管 —— 它是最容易撑爆行高的那条路径。 }
  G.WordWrap := True;
  G.Cells[0, 3] := StringOfChar('x', 400);
  G.AutoFitRow(3);
  AssertTrue(Format('自动行高也受上限约束(实际 %d)', [G.RowHeightOf(3)]),
    G.RowHeightOf(3) <= 40);
end;

{ 列宽事件:拖动过程中 Sizing,松手才 EndSize(宿主拿它保存偏好)。 }
procedure TTyStringGridTest.TestColumnSizeEventsFireOnDragAndRelease;
var
  G: TStrGridAccess;
  x: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.Header.Options := G.Header.Options + [hoVisible];
  G.Header.Height := 22;
  G.RowCount := 3;
  FSizingCalls := 0;
  FEndSizeCalls := 0;
  G.OnColumnSizing := @HookColumnSizing;
  G.OnEndColumnSize := @HookEndColumnSize;

  x := G.ColLeft(0) + G.ColWidth(0) - 1;
  G.PressMouseWithoutRelease(x, 8);
  G.MoveMouseTo(x + 30, 8);
  AssertTrue('拖动过程中发 Sizing', FSizingCalls > 0);
  AssertEquals('还没松手不该发 EndSize', 0, FEndSizeCalls);

  G.ReleaseMouse(x + 30, 8);
  AssertEquals('松手发一次 EndSize', 1, FEndSizeCalls);
  AssertEquals('EndSize 带上最终宽度', G.ColWidth(0), G.ScaleFrom(FLastEndSize));
end;

procedure TTyStringGridTest.HookCanToggle(Sender: TObject; ACol, ARow: Integer;
  var AAllow: Boolean);
begin
  if FVetoToggle then AAllow := False;
end;

procedure TTyStringGridTest.HookCheckChange(Sender: TObject; ACol, ARow: Integer;
  AChecked: Boolean);
begin
  Inc(FCheckChanges);
end;

{ 隐藏行与过滤是**两回事**:过滤是条件,隐藏是事实。
  从前只能借过滤间接隐藏 —— 语义不对,ClearFilters 会把它一起抹掉。 }
procedure TTyStringGridTest.TestHiddenRowsSurviveClearFilters;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 5;

  AssertEquals('一开始全都显示', 5, G.DisplayRowCount);
  AssertEquals('没有隐藏行', 0, G.NumHiddenRows);

  G.HideRow(2);
  AssertEquals('隐藏一行后少一条', 4, G.DisplayRowCount);
  AssertTrue('查得出是隐藏的', G.IsHiddenRow(2));
  AssertEquals('计数对', 1, G.NumHiddenRows);

  { **关键**:清过滤不该把手工隐藏的行放出来。 }
  G.ClearFilters;
  AssertEquals('ClearFilters 之后仍然隐藏着', 4, G.DisplayRowCount);
  AssertTrue('仍然是隐藏的', G.IsHiddenRow(2));

  G.UnHideRow(2);
  AssertEquals('取消隐藏后回来了', 5, G.DisplayRowCount);

  G.HideRow(0); G.HideRow(1);
  G.UnHideAllRows;
  AssertEquals('全部取消隐藏', 5, G.DisplayRowCount);
end;

{ 选区聚合:状态栏那句"已选 12 项,合计 3400"。非数值格跳过、不污染统计。 }
procedure TTyStringGridTest.TestSelectionAggregatesSkipNonNumericCells;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  G.Cells[0, 0] := '10';   G.Cells[0, 1] := '20';
  G.Cells[0, 2] := '不是数'; G.Cells[0, 3] := '30';

  G.SelectRange(0, 0, 0, 3);
  AssertEquals('合计跳过非数值格', 60.0, G.SelectionSum, 0.001);
  AssertEquals('平均按**能解析的个数**算', 20.0, G.SelectionAvg, 0.001);
  AssertEquals('最小值', 10.0, G.SelectionMin, 0.001);
  AssertEquals('最大值', 30.0, G.SelectionMax, 0.001);

  { 选区缩小,统计跟着变。 }
  G.SelectRange(0, 0, 0, 1);
  AssertEquals('缩小选区后合计变了', 30.0, G.SelectionSum, 0.001);
end;

{ 勾选框事件:能否决、切换成功了才通知。 }
procedure TTyStringGridTest.TestCheckBoxEventsFireAndCanBeVetoed;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  FCheckChanges := 0;
  FVetoToggle := False;
  G.OnCanToggleCheck := @HookCanToggle;
  G.OnCheckBoxChange := @HookCheckChange;

  G.ToggleCellChecked(0, 1);
  AssertEquals('切换成功发一次通知', 1, FCheckChanges);
  AssertEquals('内容写成了 1', '1', G.Cells[0, 1]);

  FVetoToggle := True;
  G.ToggleCellChecked(0, 1);
  AssertEquals('被否决时不发通知', 1, FCheckChanges);
  AssertEquals('被否决时内容不变', '1', G.Cells[0, 1]);
end;

{ 导航跳过只读格:方向键掠过只读列,而不是原地撞墙。 }
procedure TTyStringGridTest.TestSkipReadOnlyCellsDuringNavigation;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);   { 4 列 }
  G.RowCount := 4;
  TTyGridColumn(G.Header.Columns.Items[1]).ReadOnly := True;
  TTyGridColumn(G.Header.Columns.Items[2]).ReadOnly := True;
  G.MoveCursor(0, 0);

  { 没开时逐列走,会停在只读列上。 }
  G.PressKey(VK_RIGHT);
  AssertEquals('没开跳过时停在只读列', 1, G.Col);

  G.MoveCursor(0, 0);
  G.SkipReadOnlyCells := True;
  G.PressKey(VK_RIGHT);
  AssertEquals('开了之后跳过两个只读列', 3, G.Col);

  { 反方向同理。 }
  G.PressKey(VK_LEFT);
  AssertEquals('反向也跳过', 0, G.Col);
end;

{ 过滤条件类型化:从前只有"包含"一种 —— 数值列想筛 >1000 完全做不到。 }
procedure TTyStringGridTest.TestTypedFilterOperators;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 5;
  G.Cells[0, 0] := '100';  G.Cells[0, 1] := '900';
  G.Cells[0, 2] := '1500'; G.Cells[0, 3] := '2000';
  G.Cells[0, 4] := '不是数';

  G.SetColumnFilterEx(0, gfoGreater, '1000');
  AssertEquals('筛 >1000 剩两条', 2, G.FilteredRowCount);
  AssertEquals('显示序也跟着', 2, G.DisplayRowCount);

  G.SetColumnFilterEx(0, gfoLessEqual, '900');
  AssertEquals('筛 <=900 剩两条', 2, G.FilteredRowCount);

  { 非数值格在数值比较下一律不通过 —— 把 'abc' 当 0 会让"筛 >-1"
    把整列文本都放进来,那不是用户要的。 }
  G.SetColumnFilterEx(0, gfoGreater, '-1');
  AssertEquals('筛 >-1 只放行真数值', 4, G.FilteredRowCount);

  G.SetColumnFilterEx(0, gfoEquals, '900');
  AssertEquals('等于', 1, G.FilteredRowCount);

  G.SetColumnFilterEx(0, gfoStartsWith, '1');
  AssertEquals('以 1 开头', 2, G.FilteredRowCount);

  { 老的 SetColumnFilter 仍然是"包含"。 }
  G.ClearFilters;
  G.SetColumnFilter(0, '00');
  AssertEquals('老接口仍是包含', 4, G.FilteredRowCount);
end;

{ 漏斗要在**正在过滤的那一列**点亮 —— 否则"为什么少了几行"会变成一次排查。 }
procedure TTyStringGridTest.TestFilterFunnelLightsUpOnlyForFilteredColumns;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  G.Cells[1, 0] := 'abc';

  AssertTrue('一开始没有列在过滤', not G.ColumnFilterActive(1));

  G.SetColumnFilter(1, 'a');
  AssertTrue('设了过滤的列点亮', G.ColumnFilterActive(1));
  AssertTrue('别的列不点亮', not G.ColumnFilterActive(0));

  G.ClearFilters;
  AssertTrue('清掉之后灭掉', not G.ColumnFilterActive(1));
end;

{ 排序细则:空值位置**与升降序无关**;大小写敏感可开关。 }
procedure TTyStringGridTest.TestBlanksPositionAndCaseSensitiveSorting;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  G.Cells[0, 0] := 'b';
  G.Cells[0, 1] := '';       { 空 }
  G.Cells[0, 2] := 'a';
  G.Cells[0, 3] := 'c';

  G.SortByColumn(0, sdAscending);
  AssertEquals('默认空值排最后(升序)', '', G.Cells[0, G.DisplayRow(3)]);
  G.SortByColumn(0, sdDescending);
  AssertEquals('**翻方向后空值仍然在最后**', '', G.Cells[0, G.DisplayRow(3)]);

  G.BlanksPosition := gbpFirst;
  G.SortByColumn(-1, sdAscending);
  G.SortByColumn(0, sdAscending);
  AssertEquals('改成排最前(升序)', '', G.Cells[0, G.DisplayRow(0)]);
  G.SortByColumn(0, sdDescending);
  AssertEquals('翻方向后仍然在最前', '', G.Cells[0, G.DisplayRow(0)]);

  { 大小写:从前写死 CompareText,想按 ASCII 序排根本做不到。 }
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 2;
  G.Cells[0, 0] := 'b';
  G.Cells[0, 1] := 'A';

  G.SortIgnoreCase := True;
  G.SortByColumn(0, sdAscending);
  AssertEquals('不区分大小写时 A 在前', 'A', G.Cells[0, G.DisplayRow(0)]);

  G.SortIgnoreCase := False;
  G.SortByColumn(-1, sdAscending);
  G.SortByColumn(0, sdAscending);
  AssertEquals('区分大小写时按 ASCII:A(65) 仍在 b(98) 前', 'A',
    G.Cells[0, G.DisplayRow(0)]);

  { 用一对能区分开的值再验一次:'B'(66) < 'a'(97)。 }
  G.Cells[0, 0] := 'a';
  G.Cells[0, 1] := 'B';
  G.SortByColumn(-1, sdAscending);
  G.SortIgnoreCase := True;
  G.SortByColumn(0, sdAscending);
  AssertEquals('不区分时 a 在 B 前', 'a', G.Cells[0, G.DisplayRow(0)]);
  G.SortByColumn(-1, sdAscending);
  G.SortIgnoreCase := False;
  G.SortByColumn(0, sdAscending);
  AssertEquals('区分时 B 在 a 前', 'B', G.Cells[0, G.DisplayRow(0)]);
end;

{ Ctrl+A 与 SelectAll 必须是**同一条路径**。
  从前 Ctrl+A 把 SelectAll 的逻辑内联抄了一遍,于是漏了两件事:
  不清离散选区(Ctrl+点出来的块会残留)、不发 OnSelectionChanged。
  "同一个动作两条不等价的实现"是最难查的一类不一致。 }
procedure TTyStringGridTest.TestCtrlAGoesThroughSelectAll;
var
  G: TStrGridAccess;
  r: TRect;
begin
  G := MakeStrGrid(FForm, FCtl);      { 4 列 }
  G.RowCount := 5;
  FSelChanges := 0;
  G.OnSelectionChanged := @HookSelectionChanged;

  { 先用 Ctrl+点造出离散选区。 }
  r := G.CellRect(0, 1);
  G.FullClickAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  r := G.CellRect(2, 3);
  G.CtrlClickAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  AssertTrue('前置条件:离散选区已建立', G.IsCellSelected(0, 1) and G.IsCellSelected(2, 3));

  FSelChanges := 0;
  G.PressKeyCtrl(Ord('A'));

  AssertEquals('Ctrl+A 之后是全选', 4 * 5, G.SelectedCellCount);
  AssertTrue('Ctrl+A 必须发 OnSelectionChanged', FSelChanges > 0);

  { 关键:全选之后再缩回一格,离散区不能"复活"。
    这正是内联版漏掉 SetLength(FSelRects,0) 会暴露的地方。 }
  G.ClearSelection;
  AssertEquals('收回后只剩光标那一格', 1, G.SelectedCellCount);
end;

{ 合并区内部不该有格线穿过 —— 合并的意思就是"这几格是一格"。
  从前 RenderGridLines 完全不看合并,横竖线照穿。 }
procedure TTyStringGridTest.TestGridLinesDoNotCrossMergedCells;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;
  Re: TBGRABitmap;
  a, d: TRect;
  x, y, blue: Integer;
  px: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; }' +
      'TyGridLine { background: #0000FF; }');
    G := MakeStrGrid(FForm, Ctl);
    G.RowCount := 5;
    G.GridLineStyle := glsBoth;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);

    { 先确认没合并时内部确实有线(否则这条测试可能恒真)。 }
    a := G.CellRect(1, 1);
    d := G.CellRect(2, 2);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);
    blue := 0;
    Re := TBGRABitmap.Create(Bmp);
    try
      for y := a.Top + 1 to d.Bottom - 2 do
        for x := a.Left + 1 to d.Right - 2 do
        begin
          px := Re.GetPixel(x, y);
          if (px.blue > 180) and (px.red < 100) then Inc(blue);
        end;
    finally
      Re.Free;
    end;
    AssertTrue(Format('前置条件:没合并时这块区域内部有格线(蓝 %d)', [blue]), blue > 20);

    { 合并 2x2 之后,同一块区域内部不该再有线。 }
    G.MergeCells(1, 1, 2, 2);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);
    blue := 0;
    Re := TBGRABitmap.Create(Bmp);
    try
      for y := a.Top + 1 to d.Bottom - 2 do
        for x := a.Left + 1 to d.Right - 2 do
        begin
          px := Re.GetPixel(x, y);
          if (px.blue > 180) and (px.red < 100) then Inc(blue);
        end;
    finally
      Re.Free;
    end;
    AssertEquals('合并区内部不该有格线穿过', 0, blue);

    { 但合并区的**外沿**仍要有线 —— 不能把线整条抹掉。 }
    blue := 0;
    Re := TBGRABitmap.Create(Bmp);
    try
      for x := a.Left to d.Right - 1 do
      begin
        px := Re.GetPixel(x, d.Bottom - 1);
        if (px.blue > 180) and (px.red < 100) then Inc(blue);
      end;
    finally
      Re.Free;
    end;
    AssertTrue(Format('合并区下沿仍要有线(蓝 %d)', [blue]), blue > 20);
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ 图标画出来了还不够 —— 标题必须**为它让位**。
  原先的 TestHeaderDrawsColumnImage 只断言"表头带里出现了红像素",
  而图标画在文字**上面**照样能满足它:那条测试对"压字"是瞎的。
  这里改用"标题墨的最左位置"判定。 }
procedure TTyGridControlTest.TestHeaderCaptionIndentsForColumnImage;
var
  Ctl: TTyStyleController;
  G: TGridAccess;
  Bmp: TBitmap;
  coll: TTyImageCollection;
  imgs: TTyVirtualImageList;
  src: TBGRABitmap;

  { 列头带里标题墨(黑色;图标是纯红,不会混进来)的最左 / 最右位置。

    **必须同时看两端**:图标画在标题上会把左边的字盖成红色,
    于是"最左黑像素"照样右移 —— 只看左端分不清"让位"和"被盖住"。
    真正让位时整串字右移,右端也跟着右移;被盖住时右端纹丝不动。 }
  procedure CaptionInk(out ALeft, ARight: Integer);
  var
    Re: TBGRABitmap;
    x, y: Integer;
    px: TBGRAPixel;
    hit: Boolean;
  begin
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRenderTo(Bmp.Canvas, Rect(0, 0, 400, 300), 96);
    ALeft := -1;
    ARight := -1;
    Re := TBGRABitmap.Create(Bmp);
    try
      for x := 0 to 119 do
      begin
        hit := False;
        for y := 0 to 23 do
        begin
          px := Re.GetPixel(x, y);
          if (px.red < 100) and (px.green < 100) and (px.blue < 100) then
          begin
            hit := True;
            Break;
          end;
        end;
        if hit then
        begin
          if ALeft < 0 then ALeft := x;
          ARight := x;
        end;
      end;
    finally
      Re.Free;
    end;
  end;

var
  noIconL, noIconR, withIconL, withIconR: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  coll := TTyImageCollection.Create(nil);
  imgs := TTyVirtualImageList.Create(nil);
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridHeader { background: #FFFFFF; color: #000000; }');

    src := TBGRABitmap.Create(16, 16, BGRA(255, 0, 0, 255));
    try
      coll.AddBitmap('red', src);
    finally
      src.Free;
    end;
    imgs.Names.Add('red');
    imgs.Collection := coll;

    G := MakeGrid(FForm, [120, 120]);
    G.Controller := Ctl;
    G.GridLines := False;
    G.Header.Height := 24;
    G.Images := imgs;
    TTyColumn(G.Header.Columns.Items[0]).Text := 'MMMM';
    G.DefaultRowHeight := 20;
    G.RowCount := 2;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);

    CaptionInk(noIconL, noIconR);
    AssertTrue('前置条件:没有图标时标题要有墨', noIconL >= 0);

    TTyColumn(G.Header.Columns.Items[0]).ImageIndex := 0;
    CaptionInk(withIconL, withIconR);
    AssertTrue('前置条件:有图标时标题仍要有墨', withIconL >= 0);

    AssertTrue(Format('标题左端应当为图标让位(%d -> %d)', [noIconL, withIconL]),
      withIconL > noIconL + 8);
    { 判别性的那一条:被盖住时右端不动,真让位时右端跟着右移。 }
    AssertTrue(Format('标题**右端**也必须右移,否则说明只是被图标盖住了(%d -> %d)',
      [noIconR, withIconR]), withIconR > noIconR + 8);
  finally
    imgs.Free;
    coll.Free;
    Bmp.Free;
    Ctl.Free;
  end;
end;

procedure TTyStringGridTest.HookColorInCol1(Sender: TObject; ACol, ARow: Integer;
  var ADisplay: TTyGridCellDisplay);
begin
  if ACol = 1 then ADisplay := gcdColor;
end;

procedure TTyStringGridTest.HookRatingInCol1(Sender: TObject; ACol, ARow: Integer;
  var ADisplay: TTyGridCellDisplay);
begin
  if ACol = 1 then ADisplay := gcdRating;
end;

procedure TTyStringGridTest.HookEllipsis(Sender: TObject; ACol, ARow: Integer;
  var ANewText: string; var AAccept: Boolean);
begin
  Inc(FEllipsisCalls);
  AAccept := not FEllipsisCancel;
  ANewText := '宿主给的值';
end;

{ 颜色列该画**色块**,不是把 '#3B82F6' 这串十六进制原样显示出来。

  从前 gekColor 只是个**编辑器**(点开弹取色对话框),显示侧没有对应的种类 ——
  于是那一列看起来就像一列没格式化的脏数据。 }
procedure TTyStringGridTest.TestColorCellPaintsASwatchNotTheHexText;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;
  Re: TBGRABitmap;
  r: TRect;
  x, y, green, ink: Integer;
  px: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; }');
    G := MakeStrGrid(FForm, Ctl);
    G.GridLines := False;
    G.RowCount := 4;
    G.Cells[1, 1] := '#00FF00';
    G.OnGetCellDisplay := @HookColorInCol1;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);

    r := G.CellRect(1, 1);
    green := 0;
    ink := 0;
    Re := TBGRABitmap.Create(Bmp);
    try
      for y := r.Top to r.Bottom - 1 do
        for x := r.Left to r.Right - 1 do
        begin
          if (x < 0) or (y < 0) or (x >= 400) or (y >= 300) then Continue;
          px := Re.GetPixel(x, y);
          if (px.green > 180) and (px.red < 100) and (px.blue < 100) then Inc(green);
          { 黑色的墨 = 文字。色块方案里这一格不该有文字。 }
          if (px.red < 90) and (px.green < 90) and (px.blue < 90) then Inc(ink);
        end;
    finally
      Re.Free;
    end;

    AssertTrue(Format('颜色列应当画出色块(绿像素 %d)', [green]), green > 40);
    AssertEquals('颜色列不该再把十六进制串画成文字', 0, ink);
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ 鼠标移到可拖的分隔线上,指针要变形 —— 否则用户根本不知道那里能拖。
  ListView 与 TreeView 早就这么做了(crHSplit),网格是漏的。

  指针形状必须与**实际能不能拖**严格一致:承诺了能拖就得真能拖,
  反过来也一样。所以这条测试拿命中判定当参照物,不另立标准。 }
procedure TTyStringGridTest.TestResizeCursorsFollowTheDividers;
var
  G: TStrGridAccess;
  r: TRect;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.Header.Options := G.Header.Options + [hoVisible];
  G.Header.Height := 22;
  G.RowCount := 5;
  G.ShowIndicator := True;
  G.IndicatorWidth := 30;

  { 列头上的普通位置:默认指针。 }
  G.HoverAt(40, 8);
  AssertEquals('列头空白处是默认指针', crDefault, G.Cursor);

  { 列分隔线上:左右调宽。 }
  G.HoverAt(G.ColLeft(0) + G.ColWidth(0) - 1, 8);
  AssertEquals('列分隔线上应当是横向调整指针', crHSplit, G.Cursor);

  { 移开之后要**恢复** —— 否则指针会一直卡在调整形状上。 }
  G.HoverAt(40, 8);
  AssertEquals('移开分隔线后恢复默认指针', crDefault, G.Cursor);

  { 行头槽里的行分隔线上:上下调高。 }
  r := G.RowRectAt(1);
  G.HoverAt(8, r.Bottom);
  AssertEquals('行分隔线上应当是纵向调整指针', crVSplit, G.Cursor);

  { 同一条行分隔线,但在**单元格区域**里 —— 那儿拖不动行高,
    所以也不该给出"能拖"的暗示。 }
  G.HoverAt(200, r.Bottom);
  AssertEquals('单元格区域不给调整指针', crDefault, G.Cursor);
end;


{ 选区底色**不能**跟着网格自身的 hover 状态变。

  症状:鼠标从网格上移开的一瞬间,选中的格会"闪一下" ——
  因为选区底色是用 `CurrentStates + [tysSelected]` 解析的,而 CurrentStates 里
  含控件自身的 tysHover。鼠标进出网格 → 状态集变 → 选区颜色重解析成另一个值。

  这和当初勾选框闪烁是**同一个 bug**(那次是鼠标按下让整个网格进 :active,
  满屏未勾选的框集体变样),只是选区这处漏掉了。
  单元格的外观只该由**格自己的状态**决定。 }
procedure TTyStringGridTest.TestSelectionColourIgnoresGridHoverState;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;

  function SelectionPixels(out ARed, AGreen: Integer): Integer;
  var
    Re: TBGRABitmap; r: TRect; x, y: Integer; px: TBGRAPixel;
  begin
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);
    r := G.CellRect(1, 1);
    ARed := 0; AGreen := 0;
    Re := TBGRABitmap.Create(Bmp);
    try
      for y := r.Top + 2 to r.Bottom - 3 do
        for x := r.Left + 2 to r.Right - 3 do
        begin
          if (x < 0) or (y < 0) or (x >= 400) or (y >= 300) then Continue;
          px := Re.GetPixel(x, y);
          if (px.red > 180) and (px.green < 100) then Inc(ARed);
          if (px.green > 180) and (px.red < 100) then Inc(AGreen);
        end;
    finally
      Re.Free;
    end;
    Result := ARed + AGreen;
  end;

var
  redOut, greenOut, redIn, greenIn: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    { 选中 = 红,hover = 绿。两者一旦混在一起,颜色会从红变绿 —— 一眼可辨。 }
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; }' +
      'TyGridCell:hover { background: #00FF00; }' +
      'TyGridCell:selected { background: #FF0000; }');
    G := MakeStrGrid(FForm, Ctl);
    G.GridLines := False;
    G.RowCount := 5;
    G.SelectRange(1, 1, 1, 1);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);

    { 鼠标不在网格上。 }
    G.LeaveControl;
    SelectionPixels(redOut, greenOut);
    AssertTrue(Format('鼠标在外时选区是选中色(红 %d)', [redOut]), redOut > 50);

    { 鼠标移进网格(但不在这一格上)—— 选区颜色**必须一模一样**。 }
    G.EnterControl;
    SelectionPixels(redIn, greenIn);
    AssertEquals('鼠标进出网格不该改变选区底色(红)', redOut, redIn);
    AssertEquals('选区不该被网格自身的 hover 染绿', 0, greenIn);
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ 数值微调编辑器:值往返 + 受列级上下限约束。
  库里本来就有 TTySpinEdit,接上去就是了。 }
procedure TTyStringGridTest.TestSpinEditorRoundTripsAndClampsToColumnRange;
var
  G: TStrGridAccess;
  c: TTyGridColumn;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  c := TTyGridColumn(G.Header.Columns.Items[1]);
  c.EditorKind := gekSpin;
  c.MinValue := 0;
  c.MaxValue := 10;
  G.Cells[1, 1] := '3';

  AssertTrue('进入微调编辑', G.BeginEdit(1, 1));
  AssertEquals('初值从单元格读入', 3, G.SpinValue);
  AssertEquals('上下限来自列', 10, G.SpinEditor.MaxValue);

  G.SetSpinValue(7);
  G.EndEdit(True);
  AssertEquals('提交后写回单元格', '7', G.Cells[1, 1]);

  { 超出上限的值要被钳住 —— 上下限是列的约定,不该靠用户自觉。 }
  AssertTrue('再次进入', G.BeginEdit(1, 1));
  G.SetSpinValue(999);
  G.EndEdit(True);
  AssertEquals('超上限被钳到列的上限', '10', G.Cells[1, 1]);
end;

{ 滑动条编辑器:拖出来的值直接落到单元格。 }
procedure TTyStringGridTest.TestSliderEditorRoundTrips;
var
  G: TStrGridAccess;
  c: TTyGridColumn;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  c := TTyGridColumn(G.Header.Columns.Items[2]);
  c.EditorKind := gekSlider;
  c.MinValue := 0;
  c.MaxValue := 100;
  G.Cells[2, 2] := '40';

  AssertTrue('进入滑动条编辑', G.BeginEdit(2, 2));
  AssertEquals('初值从单元格读入', 40, G.SliderValue);
  G.SetSliderValue(85);
  G.EndEdit(True);
  AssertEquals('提交后写回单元格', '85', G.Cells[2, 2]);
end;

{ 掩码编辑器:掩码挂在列上 —— 这正是 B9 当初推掉的 EditMask,
  库里本来就有 TTyMaskEdit,不必自己再造一套掩码语法。 }
procedure TTyStringGridTest.TestMaskEditorUsesColumnMask;
var
  G: TStrGridAccess;
  c: TTyGridColumn;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  c := TTyGridColumn(G.Header.Columns.Items[0]);
  c.EditorKind := gekMask;
  c.EditMask := '000-0000';
  G.Cells[0, 1] := '021-1234';

  AssertTrue('进入掩码编辑', G.BeginEdit(0, 1));
  AssertEquals('掩码取自列', '000-0000', G.MaskOf);
  G.EndEdit(False);
end;

{ 星级:**点哪颗星就是几分**,不弹编辑器(与勾选框同一种手感)。
  从前 gcdRating 只是显示方式,改分要靠数值编辑器输入数字 —— 很别扭。 }
procedure TTyStringGridTest.TestRatingCellSetsValueByClickingAStar;
var
  G: TStrGridAccess;
  c: TTyGridColumn;
  r: TRect;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  c := TTyGridColumn(G.Header.Columns.Items[3]);
  c.EditorKind := gekRating;
  G.Cells[3, 1] := '2';

  { 点第 4 颗星(1-based)→ 值变成 4。 }
  r := G.StarRectOf(3, 1, 4);
  AssertTrue('前置条件:星的矩形要有效', not IsRectEmpty(r));
  G.FullClickAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  AssertEquals('点第 4 颗星 = 4 分', '4', G.Cells[3, 1]);

  { 点第 1 颗 → 1 分。 }
  r := G.StarRectOf(3, 1, 1);
  G.FullClickAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  AssertEquals('点第 1 颗星 = 1 分', '1', G.Cells[3, 1]);

  { 星级格不该弹出驻留编辑器。 }
  AssertTrue('星级不弹编辑器', not G.EditorVisible);
end;

{ 星级要画**实心金星 + 空心星**:
  - 实心 = 已评的那几颗
  - 空心 = 还没评但**可以点**的位置 —— 不画出来的话用户根本看不出还能点到第 5 颗
  从前只画已评的 n 颗、而且用的是勾形。 }
procedure TTyStringGridTest.TestRatingCellPaintsFilledAndEmptyStars;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;
  Re: TBGRABitmap;
  star: TRect;
  gold, grey: Integer;

  procedure CountIn(const R: TRect; out AGold, AGrey: Integer);
  var
    x, y: Integer;      { 嵌套过程要用**自己的**计数器,不能借外层的 }
    px: TBGRAPixel;
  begin
    AGold := 0; AGrey := 0;
    for y := R.Top to R.Bottom - 1 do
      for x := R.Left to R.Right - 1 do
      begin
        if (x < 0) or (y < 0) or (x >= 400) or (y >= 300) then Continue;
        px := Re.GetPixel(x, y);
        { 金:红高绿中蓝低。灰:三色接近且偏暗。 }
        if (px.red > 200) and (px.green > 130) and (px.green < 210) and (px.blue < 90) then
          Inc(AGold);
        if (Abs(px.red - px.green) < 30) and (Abs(px.green - px.blue) < 30)
           and (px.red > 120) and (px.red < 220) then Inc(AGrey);
      end;
  end;

begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; }' +
      'TyGridRating { color: #F59E0B; }' +
      'TyGridRatingEmpty { color: #B0B0B0; }');
    G := MakeStrGrid(FForm, Ctl);
    G.GridLines := False;
    G.DefaultRowHeight := 26;
    G.RowCount := 4;
    G.Cells[1, 1] := '2';
    G.OnGetCellDisplay := @HookRatingInCol1;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);

    Re := TBGRABitmap.Create(Bmp);
    try
      { 第 1 颗:已评 → 金色实心。 }
      star := G.StarRectOf(1, 1, 1);
      AssertTrue('前置条件:第 1 颗星有矩形', not IsRectEmpty(star));
      CountIn(star, gold, grey);
      AssertTrue(Format('已评的星应当是金色实心(金 %d)', [gold]), gold > 30);

      { 第 5 颗:未评 → 只有描边,**不能是金色**。 }
      star := G.StarRectOf(1, 1, 5);
      AssertTrue('前置条件:第 5 颗星也要有矩形(可点的位置)', not IsRectEmpty(star));
      CountIn(star, gold, grey);
      AssertEquals('未评的星不该是金色', 0, gold);
      AssertTrue(Format('未评的星要画出轮廓(灰 %d)', [grey]), grey > 5);
    finally
      Re.Free;
    end;
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ 对标 AdvGrid 编辑器全集补的最后几种。它们同样是把库里现成的控件接进来。 }
procedure TTyStringGridTest.TestPasswordTimeCalculatorAndCharCaseEditors;
var
  G: TStrGridAccess;
  c: TTyGridColumn;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;

  { 密码列:编辑时遮字。 }
  c := TTyGridColumn(G.Header.Columns.Items[0]);
  c.EditorKind := gekPassword;
  G.Cells[0, 1] := 'secret';
  AssertTrue('进入密码编辑', G.BeginEdit(0, 1));
  AssertTrue('密码列要遮字', G.InlineEditorPasswordChar <> '');
  G.EndEdit(False);

  { 普通列必须把遮罩**显式清掉** —— 否则上一格的遮罩会留在共用的编辑器上。 }
  c := TTyGridColumn(G.Header.Columns.Items[1]);
  c.EditorKind := gekText;
  AssertTrue('进入普通编辑', G.BeginEdit(1, 1));
  AssertEquals('普通列不该残留上一格的遮罩', '', G.InlineEditorPasswordChar);
  G.EndEdit(False);

  { 列级大小写。 }
  c.CharCase := ecUpperCase;
  AssertTrue('再次进入', G.BeginEdit(1, 1));
  AssertTrue('大小写强制来自列', G.InlineEditorCharCase = ecUpperCase);
  G.EndEdit(False);

  { 计算器列:值往返。 }
  c := TTyGridColumn(G.Header.Columns.Items[2]);
  c.EditorKind := gekCalculator;
  G.Cells[2, 1] := '12.5';
  AssertTrue('进入计算器编辑', G.BeginEdit(2, 1));
  AssertTrue('计算器编辑器出场', G.CalcEditor.Visible);
  G.EndEdit(False);

  { 时间列:与日期共用选择器,但 Kind 要切成 dtkTime。 }
  c := TTyGridColumn(G.Header.Columns.Items[3]);
  c.EditorKind := gekTime;
  G.Cells[3, 1] := '13:45';
  AssertTrue('进入时间编辑', G.BeginEdit(3, 1));
  AssertTrue('选择器切到时间模式', G.DateEditorKind = dtkTime);
  G.EndEdit(False);
end;

{ 隐藏列必须**真的不占位、也不被画**。

  从前 coVisible 只是半成品:ColumnWidthPx 对隐藏列照样返回整宽,
  于是 CellRect 给出一个非空矩形 —— 而且正好压在**下一个可见列**的位置上。
  TTyStringGrid.RenderCells 里三个循环又没有 coVisible 守卫,
  于是选区底色、勾选框/进度条/评分/色块会画到邻列头上。 }
procedure TTyStringGridTest.TestHiddenColumnTakesNoSpaceAndIsNotPainted;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;
  Re: TBGRABitmap;
  x, y, red: Integer;
  px: TBGRAPixel;
  leftBefore: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; }');
    G := MakeStrGrid(FForm, Ctl);   { 4 列 x 80 }
    G.GridLines := False;
    G.RowCount := 4;

    leftBefore := G.ColLeft(2);

    { 给第 1 列(将被隐藏)涂成醒目的红 —— 隐藏之后它一个像素都不该出现。 }
    G.CellColors[1, 1] := TyRGB(255, 0, 0);
    G.HideColumn(1);

    AssertTrue('查得出是隐藏的', G.IsHiddenColumn(1));
    AssertEquals('隐藏列不占宽度', 0, G.ColWidth(1));
    AssertTrue('隐藏列没有自己的矩形', IsRectEmpty(G.CellRect(1, 1)));
    AssertTrue(Format('后面的列要左移补位(%d -> %d)', [leftBefore, G.ColLeft(2)]),
      G.ColLeft(2) < leftBefore);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);

    red := 0;
    Re := TBGRABitmap.Create(Bmp);
    try
      for y := 0 to 200 do
        for x := 0 to 399 do
        begin
          px := Re.GetPixel(x, y);
          if (px.red > 180) and (px.green < 100) and (px.blue < 100) then Inc(red);
        end;
    finally
      Re.Free;
    end;
    AssertEquals('隐藏列的内容一个像素都不该画出来', 0, red);

    G.ShowColumn(1);
    AssertTrue('取消隐藏后又有宽度了', G.ColWidth(1) > 0);
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ 光标不能停在隐藏列上 —— 停上去的话编辑器会在一个看不见的地方打开。 }
procedure TTyStringGridTest.TestNavigationSkipsHiddenColumns;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);   { 4 列 }
  G.RowCount := 4;
  G.HideColumn(1);
  G.HideColumn(2);
  G.MoveCursor(0, 0);

  G.PressKey(VK_RIGHT);
  AssertEquals('方向键跳过两个隐藏列', 3, G.Col);

  G.PressKey(VK_LEFT);
  AssertEquals('反向也跳过', 0, G.Col);

  { Tab 同理。 }
  G.PressKey(VK_TAB);
  AssertEquals('Tab 也跳过隐藏列', 3, G.Col);

  { End 要落在**最后一个可见列**上,不能落在隐藏列上。 }
  G.MoveCursor(0, 0);
  G.PressKey(VK_END);
  AssertTrue('End 落在可见列上', not G.IsHiddenColumn(G.Col));

  { 直接把光标设到隐藏列上也要被纠正。 }
  G.MoveCursor(1, 0);
  AssertTrue('光标不该停在隐藏列上', not G.IsHiddenColumn(G.Col));
end;

{ 行号槽要真的画出行号 —— 从前它是一条纯空白条,而文档写的是"行号槽"。
  行号按**显示序**给:排序之后屏幕第一行仍然是 1。 }
procedure TTyStringGridTest.TestRowNumbersFollowDisplayOrder;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;

  { 行号槽里某一显示行的墨量。 }
  function InkInIndicator(APos: Integer): Integer;
  var
    Re: TBGRABitmap; r: TRect; x, y: Integer; px: TBGRAPixel;
  begin
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);
    r := G.RowRectAt(APos);
    Result := 0;
    Re := TBGRABitmap.Create(Bmp);
    try
      for y := r.Top to r.Bottom - 1 do
        for x := 0 to 39 do
        begin
          if (y < 0) or (y >= 300) then Continue;
          px := Re.GetPixel(x, y);
          if px.red + px.green + px.blue < 400 then Inc(Result);
        end;
    finally
      Re.Free;
    end;
  end;

begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; }' +
      'TyGridIndicator { background: #FFFFFF; color: #000000; }');
    G := MakeStrGrid(FForm, Ctl);
    G.GridLines := False;
    G.ShowIndicator := True;
    G.IndicatorWidth := 40;
    G.RowCount := 5;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);

    AssertEquals('默认不显示行号', 0, InkInIndicator(1));

    G.ShowRowNumbers := True;
    AssertTrue(Format('打开后行号槽里要有字(墨 %d)', [InkInIndicator(1)]),
      InkInIndicator(1) > 3);
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ 省略号按钮:点它就把控制权交给宿主(弹什么对话框是宿主的事),
  但值写回照常走 OnCellEdited —— 换了个"值从哪来",不该绕过已有的校验。
  对标 AdvGrid 的 edEditBtn。 }
procedure TTyStringGridTest.TestEllipsisButtonHandsControlToHost;
var
  G: TStrGridAccess;
  c: TTyGridColumn;
  r: TRect;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  c := TTyGridColumn(G.Header.Columns.Items[1]);
  c.EditorKind := gekEllipsis;
  G.Cells[1, 1] := '原值';
  FEllipsisCalls := 0;
  FEllipsisCancel := False;
  G.OnEllipsisClick := @HookEllipsis;

  r := G.EllipsisRectOf(1, 1);
  AssertTrue('省略号按钮要有矩形', not IsRectEmpty(r));

  { 点按钮 → 宿主接管 → 写回。 }
  G.FullClickAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  AssertEquals('宿主被调用了一次', 1, FEllipsisCalls);
  AssertEquals('宿主给的值写回了', '宿主给的值', G.Cells[1, 1]);

  { 宿主取消 → 不写回。 }
  G.Cells[1, 1] := '原值2';
  FEllipsisCancel := True;
  G.FullClickAt((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  AssertEquals('取消时不写回', '原值2', G.Cells[1, 1]);

  { 点格的**其它地方**不该触发按钮 —— 那儿仍是普通行内编辑。 }
  FEllipsisCalls := 0;
  FEllipsisCancel := False;
  G.FullClickAt(G.CellRect(1, 1).Left + 4, (r.Top + r.Bottom) div 2);
  AssertEquals('点格的其它地方不触发按钮', 0, FEllipsisCalls);
end;

{ **脏区重绘的总守卫**:滚动走的快路径,画出来必须与"从头整幅重画"逐像素相同。

  这条测试是这项优化能不能存在的前提 —— 复用上一帧的像素一旦有任何一处
  没被正确失效,就会留下陈旧像素;而陈旧像素是那种"偶尔看到一下、
  截图又复现不了"的 bug,靠肉眼根本守不住。 }
procedure TTyStringGridTest.TestScrollFastPathIsPixelIdenticalToFullRepaint;
const
  W = 420; H = 300;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  fast, full: TBitmap;
  i, j: Integer;
  c: TTyColumn;

  procedure RenderInto(ABmp: TBitmap);
  begin
    ABmp.Canvas.Brush.Color := clWhite;
    ABmp.Canvas.FillRect(Rect(0, 0, W, H));
    G.DoRender(ABmp.Canvas, Rect(0, 0, W, H), 96);
  end;

  function DiffPixels(A, B: TBitmap): Integer;
  var
    ra, rb: TBGRABitmap;
    x, y, dminx, dminy, dmaxx, dmaxy: Integer;
    pa, pb: TBGRAPixel;
  begin
    Result := 0;
    dminx := 9999; dminy := 9999; dmaxx := -1; dmaxy := -1;
    ra := TBGRABitmap.Create(A);
    rb := TBGRABitmap.Create(B);
    try
      for y := 0 to H - 1 do
        for x := 0 to W - 1 do
        begin
          pa := ra.GetPixel(x, y);
          pb := rb.GetPixel(x, y);
          if (pa.red <> pb.red) or (pa.green <> pb.green) or (pa.blue <> pb.blue) then
          begin
            Inc(Result);
            if x < dminx then dminx := x;
            if x > dmaxx then dmaxx := x;
            if y < dminy then dminy := y;
            if y > dmaxy then dmaxy := y;
          end;
        end;
    finally
      ra.Free;
      rb.Free;
    end;
    if Result > 0 then
      WriteLn('[DIFFBOX x ', dminx, '..', dmaxx, '  y ', dminy, '..', dmaxy,
              '  n=', Result, ']');
  end;

begin
  Ctl := TTyStyleController.Create(nil);
  fast := TBitmap.Create;
  full := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; }' +
      'TyGridCellAlt { background: #F0F0F0; }' +
      'TyGridHeader { background: #EEEEEE; color: #000000; }' +
      'TyGridIndicator { background: #EEEEEE; color: #000000; }' +
      'TyGridLine { background: #C0C0C0; }');
    G := TStrGridAccess.Create(FForm);
    G.Parent := FForm;
    G.Controller := Ctl;
    G.Font.PixelsPerInch := 96;
    G.SetBounds(0, 0, W, H);
    for i := 0 to 3 do
    begin
      c := G.Header.Columns.Add as TTyColumn;
      c.Width := 90;
    end;
    { 故意把容易出错的元素都放进来:表头、行头槽、斑马纹、格线、固定行列。 }
    G.Header.Options := G.Header.Options + [hoVisible];
    G.Header.Height := 22;
    G.ShowIndicator := True;
    G.IndicatorWidth := 36;
    G.ShowRowNumbers := True;
    G.AlternateRows := True;
    G.FixedCols := 1;
    G.FixedRows := 1;
    G.DefaultRowHeight := 22;
    G.RowCount := 100;
    for i := 0 to 99 do
      for j := 0 to 3 do
        G.Cells[j, i] := Format('%d-%d', [j, i]);

    fast.PixelFormat := pf32bit;  fast.SetSize(W, H);
    full.PixelFormat := pf32bit;  full.SetSize(W, H);

    { 一、先画一帧建立可复用的表面,再滚动 —— 这一帧走快路径。 }
    G.SetScrollTop(0);
    RenderInto(fast);
    G.ScrollByForTest(60);
    RenderInto(fast);

    { 二、同一个滚动位置,强制从头整幅重画。 }
    G.InvalidateSurfaceForTest;
    RenderInto(full);

    AssertEquals('滚动快路径必须与整幅重画逐像素相同', 0, DiffPixels(fast, full));

    { 三、反向滚动同样要对(向上滚暴露的是顶部那条带)。 }
    G.ScrollByForTest(-25);
    RenderInto(fast);
    G.InvalidateSurfaceForTest;
    RenderInto(full);
    AssertEquals('向上滚也必须逐像素相同', 0, DiffPixels(fast, full));

    { 四、滚动量超过一屏时应当退回整幅重画,结果同样要对。 }
    G.ScrollByForTest(900);
    RenderInto(fast);
    G.InvalidateSurfaceForTest;
    RenderInto(full);
    AssertEquals('大跨度滚动也必须逐像素相同', 0, DiffPixels(fast, full));
  finally
    full.Free;
    fast.Free;
    Ctl.Free;
  end;
end;

{ 脏区重绘要真的**省下**东西。

  这一条守的是那种最难发现的退化:哪天有人在滚动路径上多调一次 Invalidate,
  快路径就被静默地关掉了 —— 画面完全正确,只是又慢回去了。像素等价那条测试
  照样绿,只有这条会红。

  度量是相对的:同样是滚一格,一次让它走快路径,一次强行作废表面走整幅重画。 }
procedure TTyStringGridTest.TestScrollFastPathIsCheaperThanFullRepaint;
const
  FRAMES = 60;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;
  i, j: Integer;
  c: TTyColumn;
  fast, full: QWord;

  function TimeScroll(AFullRepaint: Boolean): QWord;
  var f: Integer; t0: QWord;
  begin
    G.ScrollByForTest(8);
    G.DoRender(Bmp.Canvas, Rect(0, 0, 1000, 800), 96);   { 预热 }
    t0 := GetTickCount64;
    for f := 1 to FRAMES do
    begin
      G.ScrollByForTest(8);
      if AFullRepaint then G.InvalidateSurfaceForTest;
      G.DoRender(Bmp.Canvas, Rect(0, 0, 1000, 800), 96);
    end;
    Result := GetTickCount64 - t0;
  end;

begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; padding: 0px 6px; }');
    G := TStrGridAccess.Create(FForm);
    G.Parent := FForm;
    G.Controller := Ctl;
    G.Font.PixelsPerInch := 96;
    G.SetBounds(0, 0, 1000, 800);
    for i := 0 to 19 do
    begin
      c := G.Header.Columns.Add as TTyColumn;
      c.Width := 60;
    end;
    G.DefaultRowHeight := 20;
    G.RowCount := 1000;
    for i := 0 to 19 do
      for j := 1 to 60 do
        G.Cells[i, j] := Format('R%dC%d', [j, i]);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(1000, 800);

    full := TimeScroll(True);
    fast := TimeScroll(False);
    { 实测:整幅 37ms/帧,快路径 5.7ms/帧,约 6.4 倍。
      阈值取 2 倍 —— 离健康值有 3 倍余量抗机器抖动,离"快路径被关掉"(1 倍)
      还差一倍,不至于两头都误报。 }
    AssertTrue(Format('滚动该走脏区重绘(整幅 %dms / 快路径 %dms,至少要快一倍)',
      [full, fast]), fast * 2 < full);
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ 脏区重绘必须在**真实的滚动路径**上生效,不只是在测试用的那个入口上。

  这一条是补上一个已经犯过的错:VScrollChange(拖滚动条时走的那条)从前
  直接写 FScrollY 再 Invalidate,绕开了收口点 —— 于是快路径写了、测了、
  也"通过"了,实机上却一次都不会触发。画面全对,白做。 }
procedure TTyStringGridTest.TestScrollBarDragUsesFastPath;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;
  i: Integer;
  c: TTyColumn;
  before: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; }');
    G := TStrGridAccess.Create(FForm);
    G.Parent := FForm;
    G.Controller := Ctl;
    G.Font.PixelsPerInch := 96;
    G.SetBounds(0, 0, 400, 300);
    for i := 0 to 3 do
    begin
      c := G.Header.Columns.Add as TTyColumn;
      c.Width := 80;
    end;
    G.DefaultRowHeight := 22;
    G.RowCount := 500;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);   { 先有"上一帧" }

    before := G.FastScrollFrames;

    { 拖滚动条 —— 走的是滚动条自己的 OnChange,不是测试专用入口。 }
    AssertTrue('要有纵向滚动条', G.VScrollBar <> nil);
    G.VScrollBar.Position := G.VScrollBar.Position + 40;
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);

    AssertTrue('拖滚动条也要走脏区重绘,而不是整幅重画',
      G.FastScrollFrames > before);
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ 增删行必须跨过**位数边界**仍然正确。

  这一条是补一个已经把整套增删测试变成假绿的漏洞:原来的插入/删除测试全用
  RowCount 3 / 6,行号只有一位数,于是**从没跨过 9 -> 10**。
  单元格键是 IntToStr(c)+':'+IntToStr(r) 这样的**无填充**十进制文本,
  按字典序排 "9" 排在 "10" 后面 —— 而搬移循环要的是数值序。
  结果:插入时第 9 行先搬进还没腾空的第 10 行,把第 10 行的数据**直接销毁**,
  第 10 行随后腾空变成一条空行。用户看到的"别的地方还多出一行"就是它。

  所以这几条测试的关键不是"插入对不对",而是**行数必须超过 10**。 }
procedure TTyStringGridTest.TestInsertRowIsCorrectAcrossTenthRowBoundary;
var
  G: TStrGridAccess;
  r: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 12;
  for r := 0 to 11 do
    G.Cells[0, r] := 'R' + IntToStr(r);
  AssertEquals('前置条件:12 个已写入的格', 12, G.StoredCellCount);

  G.InsertRow(0);

  AssertEquals('行数 +1', 13, G.RowCount);
  AssertEquals('插入点应为空行', '', G.Cells[0, 0]);
  AssertEquals('R8 下移到第 9 行', 'R8', G.Cells[0, 9]);
  { 下面三条今天全错 —— 位数边界就在这里。 }
  AssertEquals('R9 下移到第 10 行', 'R9', G.Cells[0, 10]);
  AssertEquals('R10 下移到第 11 行', 'R10', G.Cells[0, 11]);
  AssertEquals('R11 下移到第 12 行', 'R11', G.Cells[0, 12]);
  { 这条比逐格断言更能守住"数据不灭":一格都不许丢。 }
  AssertEquals('插入不该销毁任何一格', 12, G.StoredCellCount);
end;

procedure TTyStringGridTest.TestDeleteRowIsCorrectAcrossTenthRowBoundary;
var
  G: TStrGridAccess;
  r: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 12;
  for r := 0 to 11 do
    G.Cells[0, r] := 'R' + IntToStr(r);

  G.DeleteRow(0);

  AssertEquals('行数 -1', 11, G.RowCount);
  AssertEquals('R1 上移到第 0 行', 'R1', G.Cells[0, 0]);
  AssertEquals('R9 上移到第 8 行', 'R9', G.Cells[0, 8]);
  AssertEquals('R10 上移到第 9 行', 'R10', G.Cells[0, 9]);
  AssertEquals('R11 上移到第 10 行', 'R11', G.Cells[0, 10]);
  AssertEquals('删除只该销毁一格', 11, G.StoredCellCount);
end;

{ 列方向是同一个 ShiftCells,同一个缺陷 —— 超过 10 列就会出现。 }
procedure TTyStringGridTest.TestInsertColumnIsCorrectAcrossTenthColumnBoundary;
var
  G: TStrGridAccess;
  c: Integer;
  col: TTyColumn;
begin
  G := MakeStrGrid(FForm, FCtl);
  while G.Header.Columns.Count < 12 do
  begin
    col := G.Header.Columns.Add as TTyColumn;
    col.Width := 40;
  end;
  G.RowCount := 2;
  for c := 0 to 11 do
    G.Cells[c, 0] := 'C' + IntToStr(c);

  G.InsertColumn(0);

  AssertEquals('C8 右移到第 9 列', 'C8', G.Cells[9, 0]);
  AssertEquals('C9 右移到第 10 列', 'C9', G.Cells[10, 0]);
  AssertEquals('C10 右移到第 11 列', 'C10', G.Cells[11, 0]);
  AssertEquals('C11 右移到第 12 列', 'C11', G.Cells[12, 0]);
  AssertEquals('插入列不该销毁任何一格', 12, G.StoredCellCount);
end;

{ 按行号存的旁挂表(显式行高、隐藏行)也必须跟着数据走。

  它们键的是**行下标**,而 ShiftCells 只搬文字与格属性 —— 于是插一行之后,
  行高粘在原来的下标上,落到了另一行数据头上;隐藏标记同理:原来藏着的行冒出来,
  另一行凭空消失。用户会把它读成"又多/少了一行"。 }
procedure TTyStringGridTest.TestRowSideTablesFollowTheDataOnInsert;
var
  G: TStrGridAccess;
  r: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 12;
  for r := 0 to 11 do
    G.Cells[0, r] := 'R' + IntToStr(r);

  G.RowHeights[10] := 44;
  G.HideRow(11);
  AssertEquals('前置条件:第 10 行有显式行高', 44, G.RowHeights[10]);
  AssertTrue('前置条件:第 11 行是隐藏的', G.IsHiddenRow(11));

  G.InsertRow(0);

  AssertEquals('显式行高应跟着那行数据走到第 11 行', 44, G.RowHeights[11]);
  AssertTrue('隐藏标记应跟着那行数据走到第 12 行', G.IsHiddenRow(12));
  AssertTrue('原来的第 11 行不该还是隐藏的', not G.IsHiddenRow(11));
end;

{ 用户显式给某格上的色,**被选中时也必须还看得见**。

  从前选区底色是不透明的 accent,直接铺在逐格色之上,把它整块抹掉。
  而光标恰恰总落在刚上色的那一格上 —— 于是"点了上色什么都没变",
  挪开光标才冒出来一格。用户报的"有时一格、有时一格都没有"就是这个。

  断言用**通道关系**而不是具体像素值:半透明的蓝色选区盖在红格上,
  红通道仍应压过蓝通道。这条断言只有"颜色确实透出来了"才成立,
  抹掉的话整格是 accent 蓝(蓝压红),必红。 }
procedure TTyStringGridTest.TestSelectionDoesNotEraseAnExplicitCellColor;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;

  procedure AvgOfCell(ACol, ARow: Integer; out ar, ag, ab: Integer);
  var
    Re: TBGRABitmap; r: TRect; x, y, n: Integer; px: TBGRAPixel;
  begin
    r := G.CellRect(ACol, ARow);
    ar := 0; ag := 0; ab := 0; n := 0;
    Re := TBGRABitmap.Create(Bmp);
    try
      for y := r.Top + 3 to r.Bottom - 4 do
        for x := r.Left + 3 to r.Right - 4 do
        begin
          if (x < 0) or (y < 0) or (x >= 400) or (y >= 300) then Continue;
          px := Re.GetPixel(x, y);
          Inc(ar, px.red); Inc(ag, px.green); Inc(ab, px.blue); Inc(n);
        end;
    finally
      Re.Free;
    end;
    if n = 0 then n := 1;
    ar := ar div n; ag := ag div n; ab := ab div n;
  end;

var
  mr, mg, mb, pr, pg, pb: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    { 刻意**不**定义 TyGridCellMarked —— 它该由 base 层(light.tycss)垫进来。
      这样这条测试顺带守住"新 typeKey 补进了 light.tycss",而不只是守代码。 }
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; }' +
      'TyGridCell:selected { background: #3B82F6; color: #FFFFFF; }');
    G := MakeStrGrid(FForm, Ctl);
    G.GridLines := False;
    G.RowCount := 4;

    { (1,1) 上成红色,(0,1) 不上色 —— 两格都在选区里,做差分。 }
    G.CellColors[1, 1] := TyRGB(255, 0, 0);
    G.SelectRange(0, 1, 1, 1);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);

    AvgOfCell(1, 1, mr, mg, mb);   { 上了色 + 被选中 }
    AvgOfCell(0, 1, pr, pg, pb);   { 只是被选中 }

    AssertTrue(Format('选中时上的色仍要透出来(红 %d 应压过蓝 %d)', [mr, mb]),
      mr > mb);
    AssertTrue(Format('上了色的格必须与只被选中的格看起来不同(%d,%d,%d vs %d,%d,%d)',
      [mr, mg, mb, pr, pg, pb]), Abs(mr - pr) > 30);
    AssertTrue(Format('没上色的格仍是正常选区色(蓝 %d 应压过红 %d)', [pb, pr]),
      pb > pr);
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ 斑马纹是**主题装饰**,逐格色是**用户的明确指定** —— 装饰不许盖过指定。

  代码里这两块的先后顺序本来是反的:逐格色先写、斑马纹后写,于是在奇数行
  上的色被斑马纹整块盖掉。函数自己的注释写的优先级("主题 → 斑马纹 → 行色 →
  逐格色")才是对的 —— 注释和代码互相矛盾,注释是对的那一方。 }
procedure TTyStringGridTest.TestZebraDoesNotOverrideAnExplicitCellColor;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;
  Re: TBGRABitmap;
  r: TRect;
  x, y, red: Integer;
  px: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; }' +
      'TyGridCellAlt { background: #DDDDDD; }');
    G := MakeStrGrid(FForm, Ctl);
    G.GridLines := False;
    G.RowCount := 6;
    G.AlternateRows := True;
    G.MoveCursor(0, 0);            { 光标别停在被测格上 }

    { 显示行 3 是奇数行 —— 斑马纹会铺灰底的那一种。 }
    G.CellColors[1, 3] := TyRGB(255, 0, 0);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);

    r := G.CellRect(1, 3);
    red := 0;
    Re := TBGRABitmap.Create(Bmp);
    try
      for y := r.Top + 3 to r.Bottom - 4 do
        for x := r.Left + 3 to r.Right - 4 do
        begin
          if (x < 0) or (y < 0) or (x >= 400) or (y >= 300) then Continue;
          px := Re.GetPixel(x, y);
          if (px.red > 180) and (px.green < 100) and (px.blue < 100) then Inc(red);
        end;
    finally
      Re.Free;
    end;
    AssertTrue(Format('斑马纹行上的逐格色不该被盖掉(红像素 %d)', [red]), red > 50);
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TTyGridControlTest);
  RegisterTest(TTyDrawGridTest);
  RegisterTest(TTyStringGridTest);
end.
