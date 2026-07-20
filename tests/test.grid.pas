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
    { OnDblClickCell 的记账(它从前一处都没被触发过)。 }
    FDblCount, FDblCol, FDblRow: Integer;
    FRowMoveCount: Integer;
    FEditorPropCount, FEditorPropCol, FEditorPropRow: Integer;
    FEditorPropCtl: TControl;
    FRowMoveAllow: Boolean;
    procedure HandleGetEditorProp(Sender: TObject; ACol, ARow: Integer;
      AEditor: TControl);
    procedure HandleVirtualText(Sender: TObject; ACol, ARow: Integer;
      var AText: string);
    procedure HandleRowMove(Sender: TObject; AFrom, ATo: Integer;
      var AAllow: Boolean);
    procedure HandleDblClickCell(Sender: TObject; ACol, ARow: Integer);
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
    procedure TestPhysicalSortCarriesCellAttributes;
    procedure TestTopRightCornerCellIsVisibleWithBothFreezes;
    procedure TestFixedRowsAndSortTogetherKeepCellsInTheirPane;
    procedure TestFrozenBandThicknessFollowsDisplayedRows;
    procedure TestFilteringOutTheAnchorDoesNotGrowTheSelection;
    procedure TestUndoRestoresCellAttributesAndRowHeights;
    procedure TestUndoRestoresCellColorAndMerge;
    procedure TestSwappingRowsCarriesTheHiddenFlag;
    procedure TestFooterAggregateIsCachedAndInvalidated;
    procedure TestPasteAndCutAreOneUndoStepEach;
    procedure TestClearAndCsvImportAreUndoable;
    procedure TestNoOpAttributeWriteLeavesTheUndoStackAlone;
    procedure TestMergeCountSurvivesRowRemovalAndUndo;
    procedure TestClearMergesIsOneUndoStep;
    procedure TestOversizedUndoRecordIsDiscardedNotTruncated;
    procedure TestPasteWithAFilteredOutCursorRowKeepsEveryLine;
    procedure TestUndoingARowSwapRestoresTheHiddenFlag;
    procedure TestColouringASelectionIsOneUndoStep;
    procedure TestAutoFitRowsIsOneUndoStep;
    procedure TestColumnKeyedTablesFollowInsertAndDelete;
    procedure TestUndoingRowInsertRestoresHeightsAndHiddenFlags;
    procedure TestMultiLevelGroupingOnUnclusteredData;
    procedure TestTimeEditorCommitsATimeNotADate;
    procedure TestMultiLevelGroupingNestsAndSubtotalsPerLevel;
    procedure TestLayoutRoundTripsAndSurvivesGarbage;
    procedure TestPhysicalSortMovesDataAndUnlocksMergeAndDrag;
    procedure TestPhysicalSortRefusedWhenFilteredOrVirtual;
    procedure TestUndoRedoRestoresCellsAndRowCount;
    procedure TestBulkOperationIsOneUndoStepAndLimitDropsOldest;
    procedure TestNarrowColumnEditorWidensAndDropDownWidthApplies;
    procedure TestOnGetEditorPropFiresBeforeTheEditorShows;
    procedure TestRowDragReordersFromTheIndicatorGutter;
    procedure TestRowDragRefusedWhenDisplayOrderIsNotDataOrder;
    procedure TestFillHandleGeometryMatchesWhatIsDrawn;
    procedure TestFillCopiesRepeatsAndExtrapolates;
    procedure TestProgrammaticCursorMoveDoesNotStretchSelection;
    procedure TestBulkFillStaysLinear;
    procedure TestBeginUpdateCollapsesRepaints;
    procedure TestFixedRowsRenderTheirContent;
    procedure TestBottomFixedRowsPinRenderAndHitTest;
    procedure TestRightFixedColsPinRenderAndHitTest;
    procedure TestGroupSubtotalsComputeAndActuallyRender;
    procedure TestGroupSubtotalSurvivesCollapse;
    procedure TestFilterValueCountsMatchRowTallies;
    procedure TestValueFilterCanSelectBlanksOnly;
    procedure TestMergeSelectionOnSortedGridDoesNotSwallowExtraRows;
    procedure TestMergeStopsApplyingWhenSortBreaksItUpAndReturnsWhenSortedBack;
    procedure TestDoubleClickOutsideCellsDoesNotStartEditing;
    procedure TestOnDblClickCellFiresForCellsOnly;
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
    { 完整的 LCL 双击:第二次按下带 ssDouble,**并且**发一次 DblClick。
      DoubleClickAt 只发鼠标消息 —— 而"双击进编辑"挂在 DblClick 上,
      不补这一下就永远测不到它。 }
    procedure FullDoubleClickAt(X, Y: Integer);
    function  ColWidth(ACol: Integer): Integer;
    function  ScaleFrom(ALogical: Integer): Integer;
    { 完整一次点击(按下 + 松开)。注意 ClickAt **只发 MouseDown** ——
      按钮单元格按设计是松开才算触发(按下后拖走应当作废),所以要用这个。 }
    procedure FullClickAt(X, Y: Integer);
    procedure LeaveMouse;
    function  RowRectAt(APos: Integer): TRect;
    function  GetScrollTop: Integer;
    procedure SetScrollTop(AValue: Integer);
    procedure SetScrollLeftForTest(AValue: Integer);
    procedure ScrollByForTest(ADy: Integer);
    function  RowAtForTest(AY: Integer): Integer;
    function  EditorBoundsForTest: TRect;
    function  ScaleForTest(AValue: Integer): Integer;
    function  GroupToggleRectForTest(APos: Integer): TRect;
    function  BeginEditAt(ACol, ARow: Integer): Boolean;
    function  UndoCountForTest: Integer;
    procedure PressKeyCtrl(AKey: Word);
    function  ColAtForTest(AX: Integer): Integer;
    procedure BaseCellOfForTest(ACol, ARow: Integer; out ABaseCol, ABaseRow: Integer);
    procedure InvalidateSurfaceForTest;
    function  SurfaceFreshForTest: Boolean;
    property ScrollTop: Integer read GetScrollTop write SetScrollTop;
  end;

  { 数"汇总扫了多少格"。页脚每帧都要问一次聚合,而聚合遍历的是全部显示行 ——
    百万行时每帧一次 O(n)。守卫要能看见**扫描本身**,光看结果对不对
    分辨不出"每帧重算"和"用了缓存"。 }
  TCountingGrid = class(TStrGridAccess)
  public
    ScanCount: Integer;
    procedure AccumulateCell(ACol, ADataRow: Integer; AKind: TTyGridAggregate;
      var AAcc: Double; var ACount: Integer; var AStarted: Boolean); override;
  end;

procedure TCountingGrid.AccumulateCell(ACol, ADataRow: Integer;
  AKind: TTyGridAggregate; var AAcc: Double; var ACount: Integer;
  var AStarted: Boolean);
begin
  Inc(ScanCount);
  inherited AccumulateCell(ACol, ADataRow, AKind, AAcc, ACount, AStarted);
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

procedure TStrGridAccess.FullDoubleClickAt(X, Y: Integer);
begin
  DoubleClickAt(X, Y);
  DblClick;
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

procedure TStrGridAccess.BaseCellOfForTest(ACol, ARow: Integer;
  out ABaseCol, ABaseRow: Integer);
begin
  BaseCellOf(ACol, ARow, ABaseCol, ABaseRow);
end;

function TStrGridAccess.ColAtForTest(AX: Integer): Integer;
begin
  Result := ColumnAtX(AX);
end;

function TStrGridAccess.EditorBoundsForTest: TRect;
begin
  Result := Rect(0, 0, 0, 0);
  if EditorControl <> nil then Result := EditorControl.BoundsRect;
end;

function TStrGridAccess.GroupToggleRectForTest(APos: Integer): TRect;
begin
  Result := GroupToggleRect(APos);
end;

function TStrGridAccess.ScaleForTest(AValue: Integer): Integer;
begin
  Result := ScaleI(AValue);
end;

procedure TStrGridAccess.PressKeyCtrl(AKey: Word);
begin
  KeyDown(AKey, [ssCtrl]);
end;

function TStrGridAccess.UndoCountForTest: Integer;
begin
  Result := UndoCount;
end;

function TStrGridAccess.BeginEditAt(ACol, ARow: Integer): Boolean;
begin
  Result := BeginEdit(ACol, ARow);
end;

function TStrGridAccess.RowAtForTest(AY: Integer): Integer;
begin
  Result := TyGridRowAt(AY, GridMetrics);
end;

procedure TStrGridAccess.ScrollByForTest(ADy: Integer);
begin
  ScrollVerticallyBy(ADy);
end;

function TStrGridAccess.SurfaceFreshForTest: Boolean;
begin
  Result := SurfaceFresh;
end;

procedure TStrGridAccess.InvalidateSurfaceForTest;
begin
  InvalidateSurface;
end;

procedure TStrGridAccess.SetScrollLeftForTest(AValue: Integer);
begin
  ScrollX := AValue;
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

procedure TTyStringGridTest.HandleVirtualText(Sender: TObject;
  ACol, ARow: Integer; var AText: string);
begin
  AText := Format('%.2d', [100 - ARow]);
end;

procedure TTyStringGridTest.HandleGetEditorProp(Sender: TObject;
  ACol, ARow: Integer; AEditor: TControl);
begin
  Inc(FEditorPropCount);
  FEditorPropCol := ACol;
  FEditorPropRow := ARow;
  FEditorPropCtl := AEditor;
end;

procedure TTyStringGridTest.HandleRowMove(Sender: TObject; AFrom, ATo: Integer;
  var AAllow: Boolean);
begin
  Inc(FRowMoveCount);
  AAllow := FRowMoveAllow;
end;

procedure TTyStringGridTest.HandleDblClickCell(Sender: TObject; ACol, ARow: Integer);
begin
  Inc(FDblCount);
  FDblCol := ACol;
  FDblRow := ARow;
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

  { 用选区 API 建选区,而不是"赋 Col/Row 让它自己拉长" ——
    程序化移动光标现在会重锚(否则上移/下移一下就莫名多选一格),
    那条路已经不再是建选区的方式了。 }
  G.SelectRange(0, 0, 1, 2);            // 选中 2 列 x 3 行
  txt := G.SelectionAsText;
  AssertTrue('含制表符分隔', Pos('c1' + #9 + 'c2', txt) > 0);
  AssertTrue('含第三行', Pos('b1' + #9 + 'b2', txt) > 0);

  // 排序后再导出 —— 顺序必须跟着显示走,而不是数据行号。
  G.SortByColumn(0, sdAscending);       // a1, b1, c1
  { 同上:走选区 API。数据行 1 = a1(排序后显示在第 0 位),
    数据行 0 = c1(显示在第 2 位)—— 选区按**数据行**给,导出按**显示序**出。 }
  G.SelectRange(0, 1, 1, 0);
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

    { 分组带确实画出来了,而且只覆盖前两列(第 0 列宽 80,Count 4 列 x 80)。 }
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
    { **底部冻结行也要在这张表里** —— 脏区快路径平移的是正文带,平移带的下沿
      必须停在正文窗格下沿而不是视口下沿,否则底部冻结带会跟着一起跑。
      不放一行在这儿的话,那条规则就没人守(变异测试发现的覆盖空洞)。 }
    G.FixedRowsBottom := 1;
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

{ 双击**不是单元格的地方**不许进编辑。

  从前 DblClick 无条件 BeginEdit,从不看双击落在哪里 —— 于是在行号槽、列头、
  末行以下的空白处双击,当前光标格都会莫名进入编辑。用户在行号槽上双击时
  撞见的就是这个:手根本没碰那一格。

  命中判定本来就分好了 ghpCell / ghpIndicator / ghpHeader / ghpNowhere,
  DblClick 只是从来没用它。 }
procedure TTyStringGridTest.TestDoubleClickOutsideCellsDoesNotStartEditing;
var
  G: TStrGridAccess;
  cellX, cellY: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 6;
  G.ShowIndicator := True;
  G.IndicatorWidth := 40;
  G.MoveCursor(1, 2);

  { 先证明双击**格子**确实会进编辑 —— 否则下面几条"没进编辑"毫无意义
    (一个永远不进编辑的实现也能让它们全绿)。 }
  cellX := G.ColLeft(1) + 10;
  cellY := (G.CellRect(1, 2).Top + G.CellRect(1, 2).Bottom) div 2;
  G.FullDoubleClickAt(cellX, cellY);
  AssertTrue('双击单元格要进编辑', G.Editing);
  G.EndEdit(False);

  { 行号槽:双击这里手没碰任何一格。 }
  G.FullDoubleClickAt(8, cellY);
  AssertTrue('双击行号槽不该让光标格进编辑', not G.Editing);

  { 列头带。MakeStrGrid 默认把列头关掉了,这里要显式打开 ——
    不打开的话 Y=4 落在第 0 行,那是**真的**单元格,断言会测错东西。 }
  G.Header.Options := G.Header.Options + [hoVisible];
  G.FullDoubleClickAt(G.ColLeft(1) + 10, 4);
  AssertTrue('双击列头不该进编辑', not G.Editing);
  G.Header.Options := G.Header.Options - [hoVisible];

  { 末行以下的空白。 }
  G.FullDoubleClickAt(cellX, G.CellRect(1, 5).Bottom + 20);
  AssertTrue('双击末行以下的空白不该进编辑', not G.Editing);
end;

{ OnDblClickCell 从前是**声明了、published 了、却一处都没触发过**的死事件。
  (本控件的高发 bug 类:属性/事件暴露了,运行期没有任何代码读它。) }
procedure TTyStringGridTest.TestOnDblClickCellFiresForCellsOnly;
var
  G: TStrGridAccess;
  cellY: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 6;
  G.ShowIndicator := True;
  G.IndicatorWidth := 40;
  G.OnDblClickCell := @HandleDblClickCell;
  FDblCount := 0;

  cellY := (G.CellRect(1, 2).Top + G.CellRect(1, 2).Bottom) div 2;
  G.FullDoubleClickAt(G.ColLeft(1) + 10, cellY);
  AssertEquals('双击单元格要触发 OnDblClickCell', 1, FDblCount);
  AssertEquals('列号要对', 1, FDblCol);
  AssertEquals('行号要对', 2, FDblRow);
  G.EndEdit(False);

  G.FullDoubleClickAt(8, cellY);
  AssertEquals('双击行号槽不该触发 OnDblClickCell', 1, FDblCount);
end;

{ **排序过的表上合并,绝不能吞掉没选中的行。**

  用户报的症状:同一列里选了不到 10 个格,结果几十个格被合并了 —— 而转述的人
  复现不出来。复现不出来是对的:干净表上显示序==数据序,怎么算都对。
  前置条件是**表被排过序**(而"点列头自动排序"是默认开着的,一次随手点击就够了)。

  机制:选区矩形活在**显示序**空间,而 Selection 只把两个端点翻译成数据行 ——
  两个数据行下标之差,在任何一个空间里都不再是"几行"。8 个显示行的选区,
  端点数据行可能差几十,而 RowSpan 的消费方(CellRect / BaseCellOf)
  一律按"从基准格往下数这么多**显示行**"来吞。

  这条测试断言的是**覆盖范围**,不是 RowSpan 的数值 —— 数值对不对无所谓,
  没选中的行有没有被吞掉才是用户看得见的事。 }
procedure TTyStringGridTest.TestMergeSelectionOnSortedGridDoesNotSwallowExtraRows;
var
  G: TStrGridAccess;
  r: Integer;
  covered: Integer;
  bc, br: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 40;
  { 让排序把显示序彻底打乱:数据行 0..39,按倒序的文本排。 }
  for r := 0 to 39 do
    G.Cells[0, r] := Format('%.2d', [39 - r]);
  G.SortByColumn(0, sdAscending);

  { 屏幕上连着的 4 行。 }
  G.SelectRange(0, G.DisplayToData(2), 0, G.DisplayToData(5));

  { 拒绝比吞错更好:屏幕上挨着的这几行在数据里天各一方,合成一块没有意义 ——
    换个排序它就散了。 }
  AssertTrue('排过序、数据行不连续时应当拒绝合并', not G.MergeSelection);

  { 数一数:全表有多少格被某个合并块盖住(自己是基准格的不算)。
    只选了 4 个格,被盖住的最多就是其中 3 个。 }
  covered := 0;
  for r := 0 to 39 do
  begin
    G.BaseCellOfForTest(0, r, bc, br);
    if br <> r then Inc(covered);
  end;
  AssertTrue(Format('被吞掉的行数不该超过选中的(实际盖住 %d 行)', [covered]),
    covered <= 3);
end;

{ 合并块记的是一段**数据行**。排序把这段数据行打散之后,块必须**停止生效** ——
  否则它会照着"从基准格往下数 N 个显示行"继续画,盖住的是另外几行了。
  排回去它要能回来:失效不等于销毁。 }
procedure TTyStringGridTest.TestMergeStopsApplyingWhenSortBreaksItUpAndReturnsWhenSortedBack;
var
  G: TStrGridAccess;
  r, bc, br: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 12;
  for r := 0 to 11 do
    G.Cells[0, r] := Format('%.2d', [r]);

  { 干净表上合并数据行 2..4。 }
  G.MergeCells(0, 2, 1, 3);
  G.BaseCellOfForTest(0, 3, bc, br);
  AssertEquals('前置条件:第 3 行被第 2 行的合并块盖住', 2, br);

  { 把块中间的一行藏起来 —— 数据行 2,4 在屏幕上仍然挨着,但它们已经不是
    "连续升序的 2,3,4"了。基准格仍在上方,所以向上回扫**够得着**它:
    不加守卫的话,这个块会照旧往下吞 3 个显示行,把从没被合并过的第 5 行卷进来。
    (用降序排是测不出来的:那会把基准格排到成员行下面,回扫根本够不着。) }
  G.HideRow(3);
  G.BaseCellOfForTest(0, 5, bc, br);
  AssertEquals('打散后不许把没合并过的行吞进来', 5, br);
  G.BaseCellOfForTest(0, 4, bc, br);
  AssertEquals('打散后合并块整个失效', 4, br);

  { 行放回来,块要回来 —— 失效不等于销毁。 }
  G.UnHideRow(3);
  G.BaseCellOfForTest(0, 3, bc, br);
  AssertEquals('恢复顺序后合并块要回来', 2, br);
end;

{ 下拉里每个值后面要显示"有多少行是这个值"(Excel 那样)。
  计数按**全部数据行**算,不受本列自己的过滤影响 —— 否则勾掉一个值之后
  它的计数变成 0,用户再也判断不出该不该勾回来。 }
procedure TTyStringGridTest.TestFilterValueCountsMatchRowTallies;
var
  G: TStrGridAccess;
  vals: TStringList;
  r, i: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 10;
  for r := 0 to 9 do
    if r < 6 then G.Cells[0, r] := '甲' else G.Cells[0, r] := '乙';

  vals := TStringList.Create;
  try
    G.DistinctColumnValueCounts(0, vals);
    AssertEquals('两个不同的值', 2, vals.Count);
    for i := 0 to vals.Count - 1 do
      if vals[i] = '甲' then
        AssertEquals('甲 有 6 行', 6, PtrInt(vals.Objects[i]))
      else
        AssertEquals('乙 有 4 行', 4, PtrInt(vals.Objects[i]));

    { 本列已经在过滤时,计数不该跟着缩水。 }
    vals.Clear;
    vals.Add('甲');
    G.SetColumnValueFilter(0, vals);
    vals.Clear;
    G.DistinctColumnValueCounts(0, vals);
    AssertEquals('过滤后候选仍是 2 个', 2, vals.Count);
    for i := 0 to vals.Count - 1 do
      if vals[i] = '乙' then
        AssertEquals('被筛掉的值,计数仍要是 4', 4, PtrInt(vals.Objects[i]));
  finally
    vals.Free;
  end;
end;

{ 「(空白)」是下拉里一个能勾的选项,所以"只勾空白"必须是一个**真的过滤**。

  从前值集合编码成 Trim(AValues.Text):只勾空白时它 Trim 完是空串,
  而下游把空串当成"这列没有过滤" —— 勾了等于没勾,还悄悄把别的过滤也清了。 }
procedure TTyStringGridTest.TestValueFilterCanSelectBlanksOnly;
var
  G: TStrGridAccess;
  vals: TStringList;
  r: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 10;
  { 3 行留空,其余有值。 }
  for r := 0 to 9 do
    if r mod 3 <> 0 then G.Cells[0, r] := 'x' + IntToStr(r);

  vals := TStringList.Create;
  try
    vals.Add('');                       { 只勾「(空白)」 }
    G.SetColumnValueFilter(0, vals);
    AssertEquals('只该剩下空白的那几行', 4, G.VisibleRowCount);

    { 回读也要还原成"一个空值",而不是空集合。 }
    vals.Clear;
    G.ColumnValueFilter(0, vals);
    AssertEquals('回读到一个条目', 1, vals.Count);
    AssertEquals('那个条目是空串', '', vals[0]);
  finally
    vals.Free;
  end;
end;

{ 分组小计:按地区分组之后,每组要能给出"本组金额合计"。

  这一条同时守两件事 —— 算得对,**而且真的画在分组行上**。只断言
  GroupAggregateValue 的话,一个从来不画的实现照样全绿(本控件反复出现的
  "published 却无效");只断言画了的话,数值错了看不出来。 }
procedure TTyStringGridTest.TestGroupSubtotalsComputeAndActuallyRender;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;
  Re: TBGRABitmap;
  r: TRect;
  x, y, pos, gi, inkOn, inkOff: Integer;
  px: TBGRAPixel;

  { 第一条分组行在第 1 列范围内的墨量。 }
  function InkInGroupRowCol1: Integer;
  var
    xx, yy, p2, g2: Integer;
    rr: TRect;
    pp: TBGRAPixel;
    bmp2: TBGRABitmap;
  begin
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);
    Result := 0;
    rr := Rect(0, 0, 0, 0);
    for p2 := 0 to G.DisplayRowCount - 1 do
      if G.IsGroupRow(p2, g2) then
      begin
        rr := G.RowRectAt(p2);
        Break;
      end;
    if IsRectEmpty(rr) then Exit;
    bmp2 := TBGRABitmap.Create(Bmp);
    try
      for yy := rr.Top to rr.Bottom - 1 do
        for xx := G.ColLeft(1) to G.ColLeft(1) + G.ColWidth(1) - 1 do
        begin
          if (yy < 0) or (yy >= 300) or (xx < 0) or (xx >= 400) then Continue;
          pp := bmp2.GetPixel(xx, yy);
          if pp.red + pp.green + pp.blue < 400 then Inc(Result);
        end;
    finally
      bmp2.Free;
    end;
  end;

begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; }' +
      'TyGridGroupRow { background: #FFFFFF; color: #000000; }');
    G := MakeStrGrid(FForm, Ctl);
    G.GridLines := False;
    G.RowCount := 6;
    { 地区 A 三行 10/20/30,地区 B 三行 1/2/3。 }
    for pos := 0 to 5 do
      if pos < 3 then
      begin
        G.Cells[0, pos] := 'A';
        G.Cells[1, pos] := IntToStr((pos + 1) * 10);
      end
      else
      begin
        G.Cells[0, pos] := 'B';
        G.Cells[1, pos] := IntToStr(pos - 2);
      end;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);

    G.SetColumnAggregate(1, gagSum);
    G.GroupByColumn(0);

    AssertEquals('分组数', 2, G.GroupCount);
    { 组的顺序按分组值排,A 在前。 }
    AssertEquals('A 组小计 = 60', 60.0, G.GroupAggregateValue(0, 1), 0.001);
    AssertEquals('B 组小计 = 6', 6.0, G.GroupAggregateValue(1, 1), 0.001);

    inkOn := InkInGroupRowCol1;
    G.ShowGroupSubtotals := False;
    inkOff := InkInGroupRowCol1;
    AssertTrue(Format('小计要真的画在分组行的那一列上(开 %d / 关 %d)',
      [inkOn, inkOff]), inkOn > inkOff + 5);
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ 折叠之后小计还得算得出来 —— 所以统计必须按组的**成员数据行**走,
  不能按显示序:组一折叠,成员行就不在显示序里了,小计会变成 0。 }
procedure TTyStringGridTest.TestGroupSubtotalSurvivesCollapse;
var
  G: TStrGridAccess;
  pos: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 6;
  for pos := 0 to 5 do
    if pos < 3 then
    begin
      G.Cells[0, pos] := 'A';
      G.Cells[1, pos] := IntToStr((pos + 1) * 10);
    end
    else
    begin
      G.Cells[0, pos] := 'B';
      G.Cells[1, pos] := IntToStr(pos - 2);
    end;
  G.SetColumnAggregate(1, gagSum);
  G.GroupByColumn(0);
  AssertEquals('展开时 A 组 = 60', 60.0, G.GroupAggregateValue(0, 1), 0.001);

  G.ToggleGroup(0);
  AssertEquals('折叠后 A 组仍是 60', 60.0, G.GroupAggregateValue(0, 1), 0.001);
end;

{ 固定行必须**把内容画出来**,而不只是占住一条高度。

  从前 `TyGridVisibleRows` 把固定行排除在窗口之外,而全文件没有第二个循环
  去画它们 —— 于是 FixedRows 那一条带是空白的。 }
procedure TTyStringGridTest.TestFixedRowsRenderTheirContent;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;
  Re: TBGRABitmap;
  x, y, ink: Integer;
  px: TBGRAPixel;
  r: TRect;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; }' +
      'TyGridFixed { background: #FFFFFF; color: #000000; }');
    G := MakeStrGrid(FForm, Ctl);
    G.GridLines := False;
    G.RowCount := 8;
    G.Cells[0, 0] := 'FIXEDROW';
    G.FixedRows := 1;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);

    r := G.CellRect(0, 0);
    ink := 0;
    Re := TBGRABitmap.Create(Bmp);
    try
      for y := r.Top to r.Bottom - 1 do
        for x := r.Left to r.Right - 1 do
        begin
          if (y < 0) or (y >= 300) or (x < 0) or (x >= 400) then Continue;
          px := Re.GetPixel(x, y);
          if px.red + px.green + px.blue < 400 then Inc(ink);
        end;
    finally
      Re.Free;
    end;
    AssertTrue(Format('固定行里的文字要画出来(墨 %d)', [ink]), ink > 10);

    { 逐格底色那条循环也得覆盖到固定行 —— 十个逐行循环各自漏过一次,
      所以这里再挑一条独立的路径验一遍。 }
    G.CellColors[1, 0] := TyRGB(255, 0, 0);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);
    r := G.CellRect(1, 0);
    ink := 0;
    Re := TBGRABitmap.Create(Bmp);
    try
      for y := r.Top to r.Bottom - 1 do
        for x := r.Left to r.Right - 1 do
        begin
          if (y < 0) or (y >= 300) or (x < 0) or (x >= 400) then Continue;
          px := Re.GetPixel(x, y);
          if (px.red > 180) and (px.green < 100) and (px.blue < 100) then Inc(ink);
        end;
    finally
      Re.Free;
    end;
    AssertTrue(Format('固定行的逐格底色也要画(红 %d)', [ink]), ink > 50);
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ 底部冻结行:钉在视口下沿、不随滚动,内容要画出来,点得到,且**命中是绘制的逆**。

  三条一起断言:只测"画出来了"的话,点不到它等于摆设;只测命中的话,
  一条空白带也能通过。 }
procedure TTyStringGridTest.TestBottomFixedRowsPinRenderAndHitTest;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;
  Re: TBGRABitmap;
  x, y, ink, r0, r1: Integer;
  px: TBGRAPixel;
  rc: TRect;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; }' +
      'TyGridFixed { background: #FFFFFF; color: #000000; }');
    G := MakeStrGrid(FForm, Ctl);
    G.GridLines := False;
    G.RowCount := 60;
    G.Cells[0, 59] := 'TOTALROW';
    G.CellColors[1, 59] := TyRGB(255, 0, 0);
    G.FixedRowsBottom := 1;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);

    { 先滚到中间 —— 底部冻结行必须**仍然**在视口下沿。 }
    G.ScrollByForTest(200);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);

    rc := G.CellRect(0, 59);
    AssertTrue(Format('滚动后底部冻结行仍钉在下沿(底边 %d,视口 %d)',
      [rc.Bottom, G.ClientHeight]), Abs(rc.Bottom - G.ClientHeight) <= 2);

    { 内容画出来了(逐格底色这条独立路径)。 }
    rc := G.CellRect(1, 59);
    ink := 0;
    Re := TBGRABitmap.Create(Bmp);
    try
      for y := rc.Top to rc.Bottom - 1 do
        for x := rc.Left to rc.Right - 1 do
        begin
          if (y < 0) or (y >= 300) or (x < 0) or (x >= 400) then Continue;
          px := Re.GetPixel(x, y);
          if (px.red > 180) and (px.green < 100) and (px.blue < 100) then Inc(ink);
        end;
    finally
      Re.Free;
    end;
    AssertTrue(Format('底部冻结行的内容要画出来(红 %d)', [ink]), ink > 50);

    { 命中 = 绘制的逆:在它的矩形里点一下,拿到的必须是第 59 行。 }
    rc := G.CellRect(0, 59);
    r0 := G.RowAtForTest((rc.Top + rc.Bottom) div 2);
    AssertEquals('点在底部冻结行上要命中它', 59, r0);
    { 它上面一像素不该也算作它。 }
    r1 := G.RowAtForTest(rc.Top - 1);
    AssertTrue(Format('上一像素不该还是它(得到 %d)', [r1]), r1 <> 59);
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ 右侧冻结列:钉在视口右沿、不随横向滚动,内容画得出来,而且**命中是绘制的逆**。 }
procedure TTyStringGridTest.TestRightFixedColsPinRenderAndHitTest;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;
  Re: TBGRABitmap;
  x, y, ink, i: Integer;
  px: TBGRAPixel;
  rc: TRect;
  c: TTyColumn;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; }' +
      'TyGridFixed { background: #FFFFFF; color: #000000; }');
    G := TStrGridAccess.Create(FForm);
    G.Parent := FForm;
    G.Controller := Ctl;
    G.Font.PixelsPerInch := 96;
    G.SetBounds(0, 0, 400, 300);
    for i := 0 to 9 do
    begin
      c := G.Header.Columns.Add as TTyColumn;
      c.Width := 90;                 { 10 x 90 = 900 > 400,必然要横向滚动 }
    end;
    G.GridLines := False;
    G.DefaultRowHeight := 22;
    G.RowCount := 5;
    G.CellColors[9, 1] := TyRGB(255, 0, 0);
    G.FixedColsRight := 1;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);

    { 横向滚到中间 —— 最后一列必须**仍然**贴着右沿。 }
    G.SetScrollLeftForTest(300);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);

    rc := G.CellRect(9, 1);
    AssertTrue(Format('横滚后右冻结列仍贴右沿(右边 %d,视口 %d)',
      [rc.Right, G.ClientWidth]), Abs(rc.Right - G.ClientWidth) <= 2);

    ink := 0;
    Re := TBGRABitmap.Create(Bmp);
    try
      for y := rc.Top to rc.Bottom - 1 do
        for x := rc.Left to rc.Right - 1 do
        begin
          if (y < 0) or (y >= 300) or (x < 0) or (x >= 400) then Continue;
          px := Re.GetPixel(x, y);
          if (px.red > 180) and (px.green < 100) and (px.blue < 100) then Inc(ink);
        end;
    finally
      Re.Free;
    end;
    AssertTrue(Format('右冻结列的内容要画出来(红 %d)', [ink]), ink > 50);

    { 命中:点在它的矩形里要拿到第 9 列,而不是滚到它底下的那个正文列。 }
    AssertEquals('点在右冻结列上要命中它', 9,
      G.ColAtForTest((rc.Left + rc.Right) div 2));
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ 填表必须是**线性**的,不能随已写入的格数变慢。

  这条守的是一次真实的卡死:示例里点「10 万行」直接假死。根因是稀疏存储旁边
  挂了一份**有序的**键表,每写一格 Add 一次 —— 有序 TStringList 的插入要
  memmove 半个表,于是整体 O(n²)。九十万次插入,等于卡死。

  **度量是相对的**:同样大小的三批,后面的批次不能比第一批慢太多。
  绝对毫秒换台机器就误报;"越填越慢"这个**形状**才是缺陷本身。
  修好前逐批递增(281 / 500 / 704 ms …),修好后持平(16 / 15 / 16 ms)。
  阈值取 3 倍:健康值约 1 倍,退化到第 9 批时约 6 倍以上。
  (第一版只比第 1、3 批、阈值 4 倍 —— 变异测试证明它抓不住退化,已改。) }
procedure TTyStringGridTest.TestBulkFillStaysLinear;
const
  BLOCK   = 2500;
  LASTBLK = 8;      { 计时的是第 9 批 }
var
  G: TStrGridAccess;
  i, j: Integer;
  c: TTyColumn;
  t0, firstMs, thirdMs: QWord;
begin
  G := TStrGridAccess.Create(FForm);
  G.Parent := FForm;
  G.Controller := FCtl;
  G.Font.PixelsPerInch := 96;
  G.SetBounds(0, 0, 900, 600);
  for i := 0 to 8 do
  begin
    c := G.Header.Columns.Add as TTyColumn;
    c.Width := 90;
  end;
  G.RowCount := 100000;

  t0 := GetTickCount64;
  for i := 0 to BLOCK - 1 do
    for j := 0 to 8 do
      G.Cells[j, i] := 'x';
  firstMs := GetTickCount64 - t0;

  { 中间几批只填不计时 —— 跨度拉得越开,线性与二次的差别越明显。
    只比第 1 批和第 3 批时,退化后的比值才 2.5,和健康值的距离不够安全。 }
  for i := BLOCK to LASTBLK * BLOCK - 1 do
    for j := 0 to 8 do
      G.Cells[j, i] := 'x';

  t0 := GetTickCount64;
  for i := LASTBLK * BLOCK to (LASTBLK + 1) * BLOCK - 1 do
    for j := 0 to 8 do
      G.Cells[j, i] := 'x';
  thirdMs := GetTickCount64 - t0;

  { 计时精度下限:太快时两边都可能落在 0/15ms,别拿噪声做判据。 }
  if firstMs < 8 then firstMs := 8;
  AssertTrue(Format('填表不该越填越慢(第 1 批 %d ms,第 9 批 %d ms)',
    [firstMs, thirdMs]), thirdMs <= firstMs * 3);
end;

{ 批量灌数据时,送到 LCL 的重画必须**只有一次**。

  每写一格 Invalidate 一次这件事,在 headless 测试里几乎免费(没有窗口句柄),
  所以它躲过了"填表要线性"那条守卫 —— 真实窗口上 90 万次失效调用让界面像死了一样。
  这里断言的是**真正送出去的重画次数**,而不是耗时:耗时在无句柄环境下量不出来。 }
procedure TTyStringGridTest.TestBeginUpdateCollapsesRepaints;
var
  G: TStrGridAccess;
  i, j, before: Integer;
  bmp: TBitmap;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 500;

  { 一、不加锁:每写一格至少一次重画。 }
  before := G.RealInvalidateCount;
  for i := 0 to 99 do
    for j := 0 to 3 do
      G.Cells[j, i] := 'x';
  AssertTrue(Format('不加锁时重画次数应当随写入次数增长(%d 次)',
    [G.RealInvalidateCount - before]),
    G.RealInvalidateCount - before >= 400);

  { 二、加锁:整批只重画一次。 }
  before := G.RealInvalidateCount;
  G.BeginUpdate;
  try
    for i := 100 to 199 do
      for j := 0 to 3 do
        G.Cells[j, i] := 'y';
  finally
    G.EndUpdate;
  end;
  AssertEquals('加锁后整批只重画一次', 1, G.RealInvalidateCount - before);

  { 三、锁住期间**不能**留下"表面还新鲜"的错觉 —— 否则解锁后那一次重画会走
    脏区快路径,复用上一帧的陈旧像素。
    先真画一帧把表面点亮 —— 否则它本来就不新鲜,这条断言两种实现都能过(假绿)。 }
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(400, 300);
    G.DoRender(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    AssertTrue('前置条件:画过一帧之后表面是新鲜的', G.SurfaceFreshForTest);
    G.BeginUpdate;
    G.Cells[0, 0] := 'z';
    AssertTrue('锁住期间表面也必须失效', not G.SurfaceFreshForTest);
    G.EndUpdate;
  finally
    bmp.Free;
  end;

  { 四、可嵌套:内层结束不该提前解锁。 }
  before := G.RealInvalidateCount;
  G.BeginUpdate;
  G.BeginUpdate;
  G.Cells[1, 1] := 'w';
  G.EndUpdate;
  AssertEquals('内层 EndUpdate 不该触发重画', 0, G.RealInvalidateCount - before);
  G.EndUpdate;
  AssertEquals('外层 EndUpdate 才重画', 1, G.RealInvalidateCount - before);
end;

{ 程序化移动光标**不该把选区拉长**。

  用户报的现象:点「上移」之后,原来选中的那一格和被换上来的那一行的对应格
  一起变成选中。原因是选区矩形 = 锚点..光标,而重锚这件事散落在
  MouseDown / KeyDown / FindAndSelect / ClearSelection 四个调用点上各写一遍 ——
  MoveCursor 自己不管。于是任何**没走这四条路**的移动(上移/下移、跳转、
  直接赋 Row/Col)都会留下一个陈旧锚点,选区就从旧位置一路拉到新位置。

  同时守住 Shift 扩选:那才是**应该**拉长的唯一情形,别把它一起修没了。 }
procedure TTyStringGridTest.TestProgrammaticCursorMoveDoesNotStretchSelection;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 10;

  { 一、单点选中一格,然后程序化移动光标 —— 仍应只有一格被选中。 }
  G.MoveCursor(1, 2);
  G.ClearSelection;
  AssertEquals('前置条件:只选中一格', 1, G.SelectedCellCount);

  G.MoveCursor(1, 3);
  AssertEquals('程序化移动光标后仍只选中一格', 1, G.SelectedCellCount);

  { 二、Row / Col 属性赋值走的是同一条路。 }
  G.Row := 6;
  AssertEquals('赋 Row 之后仍只选中一格', 1, G.SelectedCellCount);
  G.Col := 3;
  AssertEquals('赋 Col 之后仍只选中一格', 1, G.SelectedCellCount);

  { 三、Shift 扩选必须**照样**能拉长 —— 这才是选区该变大的唯一情形。 }
  G.MoveCursor(1, 2);
  G.ClearSelection;
  G.PressKeyShift(VK_DOWN);
  G.PressKeyShift(VK_DOWN);
  AssertEquals('Shift+方向键仍要扩选', 3, G.SelectedCellCount);

  { 四、不按 Shift 的方向键则是移动,不是扩选。 }
  G.PressKey(VK_DOWN);
  AssertEquals('不按 Shift 的方向键只移动光标', 1, G.SelectedCellCount);
end;

{ 填充柄的**命中矩形必须就是画出来的那个方块**(不变量 ①:命中 = 绘制的逆)。
  柄画在选区右下角;选区变了,柄跟着走。 }
procedure TTyStringGridTest.TestFillHandleGeometryMatchesWhatIsDrawn;
var
  Ctl: TTyStyleController;
  G: TStrGridAccess;
  Bmp: TBitmap;
  Re: TBGRABitmap;
  h, cell: TRect;
  x, y, ink: Integer;
  px: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
      'TyGridCell { background: none; color: #000000; }' +
      'TyGridCell:selected { background: #3B82F6; color: #FFFFFF; }');
    G := MakeStrGrid(FForm, Ctl);
    G.GridLines := False;
    G.RowCount := 8;
    G.SelectRange(0, 1, 1, 3);

    h := G.FillHandleRect;
    AssertTrue('有选区时柄不该是空的', not IsRectEmpty(h));

    { 柄贴在选区右下角那一格的右下角。 }
    cell := G.CellRect(1, 3);
    AssertTrue(Format('柄在选区右下角(柄 %d,%d 格 %d,%d)',
      [h.Right, h.Bottom, cell.Right, cell.Bottom]),
      (Abs(h.Right - cell.Right) <= 3) and (Abs(h.Bottom - cell.Bottom) <= 3));

    { 画出来:柄那一小块里必须有非选区色的墨(它是自己的颜色)。 }
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(400, 300);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(Rect(0, 0, 400, 300));
    G.DoRender(Bmp.Canvas, Rect(0, 0, 400, 300), 96);
    ink := 0;
    Re := TBGRABitmap.Create(Bmp);
    try
      for y := h.Top to h.Bottom - 1 do
        for x := h.Left to h.Right - 1 do
        begin
          if (y < 0) or (y >= 300) or (x < 0) or (x >= 400) then Continue;
          px := Re.GetPixel(x, y);
          { 选区底色是 #3B82F6;柄要与它明显不同。 }
          if Abs(px.red - 59) + Abs(px.green - 130) + Abs(px.blue - 246) > 90 then
            Inc(ink);
        end;
    finally
      Re.Free;
    end;
    AssertTrue(Format('柄要真的画出来(与选区底色不同的像素 %d)', [ink]), ink > 20);

    { 没有选区时(选区退化成一格)柄仍在 —— Excel 也是这样。 }
    G.MoveCursor(0, 0);
    AssertTrue('单格时柄也在', not IsRectEmpty(G.FillHandleRect));
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ 填充的三种语义:单格复制、等差外推、其余按源区循环重复。 }
procedure TTyStringGridTest.TestFillCopiesRepeatsAndExtrapolates;
var
  G: TStrGridAccess;
  r: Integer;
  h, cell: TRect;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 12;

  { 一、单格 = 复制。 }
  G.Cells[0, 0] := '甲';
  G.SelectRange(0, 0, 0, 0);
  G.FillFromSelectionTo(0, 3);
  for r := 0 to 3 do
    AssertEquals(Format('单格填充是复制(第 %d 行)', [r]), '甲', G.Cells[0, r]);

  { 二、等差数列 = 外推。 }
  G.Cells[1, 0] := '10';
  G.Cells[1, 1] := '20';
  G.SelectRange(1, 0, 1, 1);
  G.FillFromSelectionTo(1, 4);
  AssertEquals('外推 30', '30', G.Cells[1, 2]);
  AssertEquals('外推 40', '40', G.Cells[1, 3]);
  AssertEquals('外推 50', '50', G.Cells[1, 4]);

  { 三、非等差 = 按源区循环重复。 }
  G.Cells[2, 0] := 'a';
  G.Cells[2, 1] := 'b';
  G.Cells[2, 2] := 'c';
  G.SelectRange(2, 0, 2, 2);
  G.FillFromSelectionTo(2, 6);
  AssertEquals('重复 a', 'a', G.Cells[2, 3]);
  AssertEquals('重复 b', 'b', G.Cells[2, 4]);
  AssertEquals('重复 c', 'c', G.Cells[2, 5]);
  AssertEquals('重复 a', 'a', G.Cells[2, 6]);

  { 四、填充完选区要覆盖到新范围 —— 与 Excel 一致。 }
  AssertTrue('填充后选区扩到目标行', G.SelectedCellCount >= 7);

  { 五、**鼠标真的拖得动**:按在柄上 → 拖到目标格 → 松开。
    只测 API 的话,柄有没有接到鼠标事件仍然无人知晓("published 却无效"那一类)。 }
  G.Cells[3, 0] := '5';
  G.SelectRange(3, 0, 3, 0);
  h := G.FillHandleRect;
  cell := G.CellRect(3, 4);
  G.DragFromTo((h.Left + h.Right) div 2, (h.Top + h.Bottom) div 2,
               (cell.Left + cell.Right) div 2, (cell.Top + cell.Bottom) div 2);
  AssertEquals('拖柄之后第 4 行被填上', '5', G.Cells[3, 4]);
end;

{ 在**行头槽**里按下并拖动 = 拖行(与列头拖列对称)。
  单元格上不能抢这个手势 —— 那里是框选。 }
procedure TTyStringGridTest.TestRowDragReordersFromTheIndicatorGutter;
var
  G: TStrGridAccess;
  r1, r3: TRect;
  r: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 8;
  G.ShowIndicator := True;
  G.IndicatorWidth := 40;
  for r := 0 to 7 do
    G.Cells[0, r] := 'R' + IntToStr(r);

  r1 := G.RowRectAt(1);
  r3 := G.RowRectAt(3);

  { 一、阈值以内不该动 —— 否则手抖一像素就把行挪了。
    起点取在行下边缘往上 6 像素:这样 7 像素的位移**已经跨进下一行**,
    却仍在 8 像素的阈值以内 —— 只有真的判了阈值才会不动。
    (两次修正才打准:先是从行中间挪 2 像素,落点还在同一行;
     再是贴着边缘起手,却落进了分隔线的 3 像素判定区,被当成改行高。) }
  G.DragFromTo(10, r1.Bottom - 6, 10, r1.Bottom + 1);
  AssertEquals('阈值以内不该移动', 'R1', G.Cells[0, 1]);

  { 二、拖过阈值:第 1 行落到第 3 行的位置。 }
  G.DragFromTo(10, (r1.Top + r1.Bottom) div 2, 10, (r3.Top + r3.Bottom) div 2);
  AssertEquals('R1 被拖到第 3 行', 'R1', G.Cells[0, 3]);
  AssertEquals('R2 上移', 'R2', G.Cells[0, 1]);
  AssertEquals('R3 上移', 'R3', G.Cells[0, 2]);

  { 三、在**单元格**上拖不该移动行(那是框选)。 }
  G.DragFromTo(60, (r1.Top + r1.Bottom) div 2, 60, (r3.Top + r3.Bottom) div 2);
  AssertEquals('单元格上拖动不移动行', 'R2', G.Cells[0, 1]);

  { 四、钩子能否决。 }
  FRowMoveAllow := False;
  FRowMoveCount := 0;
  G.OnRowMove := @HandleRowMove;
  G.DragFromTo(10, (r1.Top + r1.Bottom) div 2, 10, (r3.Top + r3.Bottom) div 2);
  AssertTrue('钩子被调用', FRowMoveCount > 0);
  AssertEquals('否决之后行没动', 'R2', G.Cells[0, 1]);
end;

{ 排过序/分过组的表上**不许**拖行:显示序不是数据序,把行拖到某个屏幕位置
  没有意义 —— 松手之后排序会立刻把它放回去。
  (与 MergeSelection 拒绝非数据连续的选区是同一条道理:宁可什么都不做,
   也不要做一件用户看不懂的事。) }
procedure TTyStringGridTest.TestRowDragRefusedWhenDisplayOrderIsNotDataOrder;
var
  G: TStrGridAccess;
  r1, r3: TRect;
  r: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 8;
  G.ShowIndicator := True;
  G.IndicatorWidth := 40;
  for r := 0 to 7 do
    G.Cells[0, r] := Format('%.2d', [7 - r]);
  G.SortByColumn(0, sdAscending);

  r1 := G.RowRectAt(1);
  r3 := G.RowRectAt(3);
  G.DragFromTo(10, (r1.Top + r1.Bottom) div 2, 10, (r3.Top + r3.Bottom) div 2);

  { 数据一格都不该动。 }
  for r := 0 to 7 do
    AssertEquals(Format('排序状态下拖行不该改数据(第 %d 行)', [r]),
      Format('%.2d', [7 - r]), G.Cells[0, r]);
end;

{ 窄列上编辑时,编辑器要能**自己加宽**到看得清 —— 60 像素的列里编辑一个长值,
  否则只能看见自己输入内容的一小截。加宽的是编辑器,不是列宽。 }
procedure TTyStringGridTest.TestNarrowColumnEditorWidensAndDropDownWidthApplies;
var
  G: TStrGridAccess;
  cell: TRect;
  c: TTyGridColumn;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  TTyColumn(G.Header.Columns.Items[0]).Width := 50;
  G.Cells[0, 1] := '一个相当长的值需要看清楚';

  { 默认(MinEditorWidth = 0)= 跟着格走,老行为一字不变。 }
  G.MinEditorWidth := 0;
  G.BeginEditAt(0, 1);
  cell := G.CellRect(0, 1);
  AssertEquals('默认跟着格宽', cell.Right - cell.Left, G.EditorBoundsForTest.Width);
  G.EndEdit(False);

  { 打开之后:至少这么宽,但不能越过网格右缘。 }
  G.MinEditorWidth := 160;
  G.BeginEditAt(0, 1);
  AssertTrue(Format('窄列上编辑器要加宽(实得 %d)', [G.EditorBoundsForTest.Width]),
    G.EditorBoundsForTest.Width >= G.ScaleForTest(160));
  AssertTrue('加宽不能越过网格右缘',
    G.EditorBoundsForTest.Right <= G.ClientWidth);
  G.EndEdit(False);

  { 宽列不该被"加宽"缩窄 —— 取的是较大者。 }
  TTyColumn(G.Header.Columns.Items[1]).Width := 300;
  G.BeginEditAt(1, 1);
  cell := G.CellRect(1, 1);
  AssertEquals('宽列保持原宽', cell.Right - cell.Left, G.EditorBoundsForTest.Width);
  G.EndEdit(False);

  { 下拉宽度可以单独配。放在**最左边**那个窄列上测 ——
    靠右的列会被网格右缘钳住,那样测的就不是 DropDownWidth 而是钳制逻辑了。 }
  G.MinEditorWidth := 0;
  c := TTyGridColumn(G.Header.Columns.Items[0]);
  c.EditorKind := gekPickList;
  c.PickList.CommaText := '甲,乙,丙';
  c.DropDownWidth := 200;
  G.BeginEditAt(0, 1);
  AssertTrue(Format('下拉按 DropDownWidth 走(实得 %d)',
    [G.EditorBoundsForTest.Width]),
    G.EditorBoundsForTest.Width >= G.ScaleForTest(200));
  G.EndEdit(False);
end;

{ `OnGetEditorProp` 在编辑器建好之后、把控制权交回调用方之前触发,
  拿到的是真正那个控件 —— 比"要么用内建、要么自己写一整个 EditLink"细一档。
  收口在 BeginEdit 的外层包装里:内建编辑器有十来种分支,逐个插事件迟早漏一种。 }
procedure TTyStringGridTest.TestOnGetEditorPropFiresBeforeTheEditorShows;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  FEditorPropCount := 0;
  FEditorPropCtl := nil;
  G.OnGetEditorProp := @HandleGetEditorProp;

  G.BeginEditAt(1, 2);
  AssertEquals('钩子被调用一次', 1, FEditorPropCount);
  AssertTrue('拿到的是真正的编辑器控件', FEditorPropCtl <> nil);
  AssertEquals('列号对', 1, FEditorPropCol);
  AssertEquals('行号对', 2, FEditorPropRow);
  { 钩子拿到的必须**就是**正在用的那个控件(而不是某个碰巧存在的编辑器)。 }
  AssertTrue('钩子拿到的就是当前编辑器', FEditorPropCtl = G.EditorControl);
  G.EndEdit(False);
end;

{ 撤销/重做:**逐格**回到原状,不是只看行数。
  结构性操作(删行)必须连行数一起还原,否则"撤销"完剩一张缺了一行的表。 }
procedure TTyStringGridTest.TestUndoRedoRestoresCellsAndRowCount;
var
  G: TStrGridAccess;
  r: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 6;
  for r := 0 to 5 do
    G.Cells[0, r] := 'R' + IntToStr(r);
  G.ClearUndo;                     { 建表本身不算用户操作 }
  AssertTrue('清空后没得撤销', not G.CanUndo);

  { 一、改一格。 }
  G.Cells[0, 2] := '改过了';
  AssertTrue('改过之后可以撤销', G.CanUndo);
  G.Undo;
  AssertEquals('撤销还原单元格', 'R2', G.Cells[0, 2]);
  AssertTrue('撤销之后可以重做', G.CanRedo);
  G.Redo;
  AssertEquals('重做再改回去', '改过了', G.Cells[0, 2]);
  G.Undo;

  { 二、删行:内容与行数都要回来。 }
  G.DeleteRow(1);
  AssertEquals('删掉一行', 5, G.RowCount);
  AssertEquals('后面的行上移', 'R2', G.Cells[0, 1]);
  G.Undo;
  AssertEquals('撤销还原行数', 6, G.RowCount);
  for r := 0 to 5 do
    AssertEquals(Format('撤销后第 %d 行逐格还原', [r]),
      'R' + IntToStr(r), G.Cells[0, r]);

  { 三、撤销期间不能再往栈里压新记录 —— 否则会自噬,永远撤销不完。 }
  AssertTrue('撤销到底之后就没得撤了', not G.CanUndo);

  { 四、Ctrl+Z / Ctrl+Y 走键盘 —— 只测 API 的话,键没接上也无人知晓。 }
  G.Cells[0, 3] := '键盘改的';
  G.PressKeyCtrl(Ord('Z'));
  AssertEquals('Ctrl+Z 还原', 'R3', G.Cells[0, 3]);
  G.PressKeyCtrl(Ord('Y'));
  AssertEquals('Ctrl+Y 重做', '键盘改的', G.Cells[0, 3]);
end;

{ 一次批量操作 = **一条**撤销记录(填充、粘贴都在 BeginUpdate 里跑);
  栈满之后丢最老的那条。 }
procedure TTyStringGridTest.TestBulkOperationIsOneUndoStepAndLimitDropsOldest;
var
  G: TStrGridAccess;
  r: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 12;
  G.Cells[0, 0] := '5';
  G.ClearUndo;

  { 拖填充柄铺 5 行 —— 整批只该是一条撤销记录。 }
  G.SelectRange(0, 0, 0, 0);
  G.FillFromSelectionTo(0, 5);
  AssertEquals('填充后第 5 行有值', '5', G.Cells[0, 5]);
  AssertEquals('整批只压了一条记录', 1, G.UndoCountForTest);

  G.Undo;
  for r := 1 to 5 do
    AssertEquals(Format('一次撤销把整批都还原(第 %d 行)', [r]), '', G.Cells[0, r]);

  { 栈上限:超出之后最老的被丢弃。 }
  G.ClearUndo;
  G.UndoLimit := 3;
  for r := 0 to 5 do
    G.Cells[1, 0] := 'v' + IntToStr(r);
  AssertEquals('栈不超过上限', 3, G.UndoCountForTest);
  { 只剩最近 3 条,所以最多撤销回 v2。 }
  G.Undo; G.Undo; G.Undo;
  AssertEquals('撤销到栈底为止', 'v2', G.Cells[1, 0]);
  AssertTrue('栈空了', not G.CanUndo);
end;

{ 物理排序模式:排序**真的把数据换位置**(像 Excel),排完之后
  显示序 == 数据序,于是那几条"排序时拒绝"自动失效。 }
procedure TTyStringGridTest.TestPhysicalSortMovesDataAndUnlocksMergeAndDrag;
var
  G: TStrGridAccess;
  r, bc, br: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 6;
  for r := 0 to 5 do
  begin
    G.Cells[0, r] := Format('%.2d', [5 - r]);      { 05 04 03 02 01 00 }
    G.Cells[1, r] := 'tag' + IntToStr(r);
  end;
  G.RowHeights[0] := 44;                            { 行高要跟着数据走 }
  G.SortMode := gsmData;
  G.ClearUndo;

  G.SortByColumn(0, sdAscending);

  { 一、数据**真的**换了位置 —— 直接看数据行,不是看显示序。 }
  for r := 0 to 5 do
    AssertEquals(Format('第 %d 个数据行就是排好序的值', [r]),
      Format('%.2d', [r]), G.Cells[0, r]);
  AssertEquals('同一行的其他列跟着搬', 'tag5', G.Cells[1, 0]);
  AssertEquals('行高跟着那一行数据走', 44, G.RowHeights[5]);

  { 二、显示序此刻就是数据序。 }
  for r := 0 to 5 do
    AssertEquals(Format('显示序恒等(%d)', [r]), r, G.DisplayToData(r));

  { 三、于是合并不再被拒 —— 这正是当初要解决的问题。 }
  G.SelectRange(0, 1, 0, 3);
  AssertTrue('物理排序后合并不再被拒绝', G.MergeSelection);
  G.BaseCellOfForTest(0, 2, bc, br);
  AssertEquals('合并块成立', 1, br);

  { 四、一次撤销把整次排序退回去(这就是为什么物理排序必须排在撤销之后)。 }
  G.UnmergeCells(0, 1);
  G.ClearUndo;
  G.SortByColumn(0, sdDescending);
  AssertEquals('降序排过了', '05', G.Cells[0, 0]);
  G.Undo;
  AssertEquals('一次撤销退回排序前', '00', G.Cells[0, 0]);
end;

{ 有筛选、或数据由回调提供(虚拟源)时**不能**物理排序:
  前者会把被筛掉的行一起搬(那是数据损坏),后者控件根本不持有数据。
  这两种情况自动退回显示序排序。 }
procedure TTyStringGridTest.TestPhysicalSortRefusedWhenFilteredOrVirtual;
var
  G: TStrGridAccess;
  r: Integer;
begin
  { 一、有筛选。 }
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 6;
  for r := 0 to 5 do
    G.Cells[0, r] := Format('%.2d', [5 - r]);
  G.SortMode := gsmData;
  G.SetColumnFilter(0, '0');
  G.SortByColumn(0, sdAscending);
  AssertEquals('有筛选时数据一格没动', '05', G.Cells[0, 0]);
  AssertTrue('但显示序仍然排好了', G.DisplayToData(0) <> 0);

  { 二、虚拟数据源这一半**当前测不出来**,这里只留一条不会假绿的弱断言。
    原因:排序的比较读的是存储而不是 GetCellText,所以虚拟表根本排不出
    非恒等的序,物理搬也就搬了个寂寞 —— 变异掉那条守卫,任何断言都不会变红。
    与其写一条"看起来在守、其实守不住"的测试,不如把这件事写清楚。
    真正的缺口(排序不认虚拟数据源)已记在计划文件里。 }
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 6;
  G.OnGetCellText := @HandleVirtualText;
  G.SortMode := gsmData;
  G.SortByColumn(0, sdAscending);
  AssertEquals('虚拟源上排序不该凭空造出存储格', 0, G.StoredCellCount);
end;

{ 版式存下来、读回去,逐项一致;残缺/乱码的字符串不能崩、也不能改坏现状。 }
procedure TTyStringGridTest.TestLayoutRoundTripsAndSurvivesGarbage;
var
  G: TStrGridAccess;
  layout: string;
  i: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 6;

  { 改一通:列宽、可见性、排序、冻结数。 }
  TTyColumn(G.Header.Columns.Items[0]).Width := 133;
  TTyColumn(G.Header.Columns.Items[2]).Width := 55;
  G.HideColumn(1);
  G.FixedCols := 1;
  G.FixedRowsBottom := 2;
  G.SortByColumn(2, sdDescending);

  layout := G.SaveLayoutToString;
  AssertTrue('存出来不是空串', layout <> '');

  { 全改回去,再读回来。 }
  TTyColumn(G.Header.Columns.Items[0]).Width := 80;
  TTyColumn(G.Header.Columns.Items[2]).Width := 80;
  G.ShowColumn(1);
  G.FixedCols := 0;
  G.FixedRowsBottom := 0;
  G.SortByColumn(-1, sdAscending);

  AssertTrue('读回来要成功', G.LoadLayoutFromString(layout));
  AssertEquals('列宽还原(0)', 133, TTyColumn(G.Header.Columns.Items[0]).Width);
  AssertEquals('列宽还原(2)', 55, TTyColumn(G.Header.Columns.Items[2]).Width);
  AssertTrue('隐藏还原', G.IsHiddenColumn(1));
  AssertEquals('左冻结还原', 1, G.FixedCols);
  AssertEquals('底部冻结还原', 2, G.FixedRowsBottom);
  AssertEquals('排序列还原', 2, G.SortColumn);
  AssertTrue('排序方向还原', G.SortDirection = sdDescending);

  { --- 坏输入:每一条都必须"拒绝 + 现状一点不动" ---
    关键是每次都断言**版式没被改坏**,而不只是"控件还活着"。
    第一版就只断言了活着,于是三个变异(不校验版本 / 解析不严格 / 不校验列数)
    全都活了下来 —— 因为那些坏串恰好都先被**别的**检查挡掉了。
    所以每条坏串都构造成:除了要测的那一项,其余全部合法。 }

  { 版本认不出。列数、字段全都合法,只有版本号不对。 }
  AssertTrue('认不出的版本要拒绝', not G.LoadLayoutFromString(
    'TYGRIDLAYOUT/999|cols=9:1:0,9:1:1,9:1:2,9:1:3|sort=|frozen=0,0,0,0'));
  AssertEquals('版本不对时列宽不许被动', 133,
    TTyColumn(G.Header.Columns.Items[0]).Width);

  { 字段不是数字。版本对、列数对,只有宽度是乱码。 }
  AssertTrue('非数字字段要拒绝', not G.LoadLayoutFromString(
    'TYGRIDLAYOUT/1|cols=abc:1:0,9:1:1,9:1:2,9:1:3|sort=|frozen=0,0,0,0'));
  AssertEquals('乱码字段时列宽不许被动', 133,
    TTyColumn(G.Header.Columns.Items[0]).Width);

  { 列数对不上(存的是 2 列,表有 4 列)。 }
  AssertTrue('列数对不上要拒绝', not G.LoadLayoutFromString(
    'TYGRIDLAYOUT/1|cols=9:1:0,9:1:1|sort=|frozen=0,0,0,0'));
  AssertEquals('列数不符时列宽不许被动', 133,
    TTyColumn(G.Header.Columns.Items[0]).Width);

  { 任意截断:不许崩,也不许把版式改成半吊子。 }
  for i := 1 to Length(layout) - 1 do
  begin
    G.LoadLayoutFromString(Copy(layout, 1, i));
    AssertEquals(Format('截断到 %d 字符时列宽不许被动', [i]), 133,
      TTyColumn(G.Header.Columns.Items[0]).Width);
  end;
  G.LoadLayoutFromString('');
  G.LoadLayoutFromString('完全不是这玩意儿');
  AssertEquals('乱码之后列宽仍然是原样', 133,
    TTyColumn(G.Header.Columns.Items[0]).Width);

  { 再读一次好串仍然成功 —— 证明前面那些坏串没把内部状态搅坏。 }
  AssertTrue('坏串之后仍能正常 round-trip', G.LoadLayoutFromString(layout));
  AssertEquals('列宽仍然对', 133, TTyColumn(G.Header.Columns.Items[0]).Width);
end;

{ 多级分组:地区 → 城市。分组行带层级,小计按层级各算各的,
  折叠状态按**层级路径**记 —— 按单个值记的话,不同地区下的同名城市会一起折叠。 }
procedure TTyStringGridTest.TestMultiLevelGroupingNestsAndSubtotalsPerLevel;
var
  G: TStrGridAccess;
  i, gi, lvl0, lvl1: Integer;
  info: TTyGridGroupInfo;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 6;
  { **故意让"北京"同时出现在两个地区下** —— 这是多级分组唯一真正难的地方:
    ① 外层变了而内层同名时,必须开一个**新的**子组(只比本级会漏掉);
    ② 折叠必须按**路径**记,按单个键记的话两个北京会一起折。
    第一版的数据里四个城市各不相同,这两条守卫怎么改都测不出来。 }
  G.Cells[0, 0] := '华东'; G.Cells[1, 0] := '上海'; G.Cells[2, 0] := '10';
  G.Cells[0, 1] := '华东'; G.Cells[1, 1] := '上海'; G.Cells[2, 1] := '20';
  G.Cells[0, 2] := '华东'; G.Cells[1, 2] := '北京'; G.Cells[2, 2] := '30';
  G.Cells[0, 3] := '华北'; G.Cells[1, 3] := '北京'; G.Cells[2, 3] := '40';
  G.Cells[0, 4] := '华北'; G.Cells[1, 4] := '北京'; G.Cells[2, 4] := '50';
  G.Cells[0, 5] := '华北'; G.Cells[1, 5] := '天津'; G.Cells[2, 5] := '60';
  G.SetColumnAggregate(2, gagSum);

  G.GroupByColumns([0, 1]);

  { 两级各有几组:地区 2 组、城市 4 组。 }
  lvl0 := 0; lvl1 := 0;
  for i := 0 to G.GroupCount - 1 do
  begin
    info := G.GroupInfo(i);
    if info.Level = 0 then Inc(lvl0)
    else if info.Level = 1 then Inc(lvl1);
  end;
  AssertEquals('第一级 2 组', 2, lvl0);
  { 上海 / 华东-北京 / 华北-北京 / 天津 = 4 组。
    两个"北京"必须是**两组**,合成一组就说明没看祖先。 }
  AssertEquals('第二级 4 组(两个北京算两组)', 4, lvl1);

  { 小计按层级各算各的:华东合计 60,华东/上海合计 30。 }
  for i := 0 to G.GroupCount - 1 do
  begin
    info := G.GroupInfo(i);
    if (info.Level = 0) and (info.Key = '华东') then
      AssertEquals('华东整个地区合计 60', 60.0, G.GroupAggregateValue(i, 2), 0.001);
    if (info.Level = 1) and (info.Key = '上海') then
      AssertEquals('华东/上海合计 30', 30.0, G.GroupAggregateValue(i, 2), 0.001);
  end;

  { 折叠按**路径**记:折叠"华北/北京"之后,"华东/北京"必须还是展开的。 }
  gi := -1;
  for i := 0 to G.GroupCount - 1 do
    if (G.GroupInfo(i).Level = 1) and (G.GroupInfo(i).Path = '华北'#1'北京') then
      gi := i;
  AssertTrue('找得到 华北/北京 这一组', gi >= 0);
  G.ToggleGroup(gi);
  { 两条都要断言:点的那个**确实折了**,别的同名组**确实没折**。
    只断言后半条的话,"折叠彻底失效"这种改坏法照样能过 —— 变异测试证明过了。 }
  lvl0 := 0;
  for i := 0 to G.GroupCount - 1 do
  begin
    if G.GroupInfo(i).Path = '华北'#1'北京' then
    begin
      AssertTrue('点过的那一组确实折起来了', G.GroupInfo(i).Collapsed);
      Inc(lvl0);
    end;
    if G.GroupInfo(i).Path = '华东'#1'北京' then
    begin
      AssertTrue('折叠 华北/北京 不该把 华东/北京 一起折起来',
        not G.GroupInfo(i).Collapsed);
      Inc(lvl0);
    end;
  end;
  AssertEquals('两个北京组都还在', 2, lvl0);

  { 分组行按层级缩进 —— 不缩进的话两级分组行长得一模一样,看不出谁包着谁。
    命中与绘制走同一个矩形,所以这条也顺带守住了"点得到的就是看得见的那一个"。 }
  for i := 0 to G.DisplayRowCount - 1 do
    if G.IsGroupRow(i, gi) and (G.GroupInfo(gi).Level = 1) then
    begin
      AssertTrue('第二级分组行要比第一级更靠右',
        G.GroupToggleRectForTest(i).Left > G.ScaleForTest(4));
      Break;
    end;

  { 折叠上一级会把整棵子树都收起来。 }
  G.UngroupRows;
  AssertEquals('取消分组后显示序回到纯数据行', 6, G.DisplayRowCount);
end;

{ 多级分组必须按**所有**分组列排序,否则第二级的键不连续,同一个子组标题会
  反复出现。上一版只 prepend 了第一个分组列 —— 而测试数据恰好本来就是聚簇的,
  所以全绿。这条测试的关键是**数据故意打乱**。 }
procedure TTyStringGridTest.TestMultiLevelGroupingOnUnclusteredData;
var
  G: TStrGridAccess;
  i, lvl1: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 6;
  { 同一个 (地区,城市) 组合被拆散在表的两头 —— 真实数据就长这样。 }
  G.Cells[0, 0] := '华东'; G.Cells[1, 0] := '上海';
  G.Cells[0, 1] := '华东'; G.Cells[1, 1] := '杭州';
  G.Cells[0, 2] := '华东'; G.Cells[1, 2] := '上海';
  G.Cells[0, 3] := '华北'; G.Cells[1, 3] := '北京';
  G.Cells[0, 4] := '华北'; G.Cells[1, 4] := '天津';
  G.Cells[0, 5] := '华北'; G.Cells[1, 5] := '北京';

  G.GroupByColumns([0, 1]);

  { 两个地区 x 两个城市 = 4 个二级组。若只按第一级排序,上海/杭州/上海 不相邻,
    会切出 5 个甚至更多。 }
  lvl1 := 0;
  for i := 0 to G.GroupCount - 1 do
    if G.GroupInfo(i).Level = 1 then Inc(lvl1);
  AssertEquals('打乱的数据也必须切出 4 个二级组', 4, lvl1);
end;

{ 时间编辑器提交的必须是**时间**。
  开编辑按种类分派、关编辑却按控件可见性分派,而日期与时间**共用一个控件** ——
  于是时间格提交时走了日期分支,写进去的是 DateToStr(小数部分) = 1899-12-30。 }
procedure TTyStringGridTest.TestTimeEditorCommitsATimeNotADate;
var
  G: TStrGridAccess;
  c: TTyGridColumn;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 4;
  c := TTyGridColumn(G.Header.Columns.Items[0]);
  c.EditorKind := gekTime;
  G.Cells[0, 1] := '13:45';

  G.BeginEditAt(0, 1);
  G.EndEdit(True);                     { 原样提交,不改值 }
  AssertEquals('时间格提交之后不该变成日期', '13:45', G.Cells[0, 1]);

  { 编辑过时间格之后,日期列必须还是日期选择器 —— 共享控件不能留着上一格的模式。 }
  c := TTyGridColumn(G.Header.Columns.Items[1]);
  c.EditorKind := gekDate;
  { 用**本地**日期格式写入 —— 日期编辑器按本地格式解析与回写,
    这里要测的是"没被上一次的时间模式带偏",不是本地化解析,别把两件事混在一起。 }
  G.Cells[1, 1] := DateToStr(EncodeDate(2026, 3, 4));
  G.BeginEditAt(1, 1);
  G.EndEdit(True);
  AssertEquals('日期格不该被上一次的时间模式带偏',
    DateToStr(EncodeDate(2026, 3, 4)), G.Cells[1, 1]);
end;

{ A3:物理排序必须把**格属性**(底色/合并跨度/只读)一起搬走。
  只搬文字的话,底色会留在原地装饰到不相干的数据上;而且文字进了撤销栈、
  属性没进 —— Ctrl+Z 之后得到一个从未存在过的状态。 }
procedure TTyStringGridTest.TestPhysicalSortCarriesCellAttributes;
var
  G: TStrGridAccess;
  r: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 5;
  for r := 0 to 4 do
    G.Cells[0, r] := Format('%.2d', [4 - r]);   { 04 03 02 01 00 }
  { 给"值 = 04"那一行(现在是第 0 行)标个显眼的底色。 }
  G.CellColors[0, 0] := TyRGB(255, 0, 0);
  G.SortMode := gsmData;

  G.SortByColumn(0, sdAscending);

  { '04' 排完之后在最后一行 —— 底色必须跟着它走。 }
  AssertEquals('前置:04 排到了最后', '04', G.Cells[0, 4]);
  AssertEquals('底色要跟着那一行数据走', TyRGB(255, 0, 0), G.CellColors[0, 4]);
  AssertEquals('原来那一行不该还留着底色', 0, G.CellColors[0, 0]);
end;

{ A5:同时开顶部固定行与右侧冻结列时,**右上角**那一格必须画得出来。
  顶部带原先只做两路分割(左/中),右上角被判成 gpTop,
  与不含右冻结列的顶部带求交后成了空矩形 —— 那一格凭空消失。 }
procedure TTyStringGridTest.TestTopRightCornerCellIsVisibleWithBothFreezes;
var
  G: TStrGridAccess;
  i: Integer;
  c: TTyColumn;
  vis: TRect;
begin
  G := TStrGridAccess.Create(FForm);
  G.Parent := FForm;
  G.Controller := FCtl;
  G.Font.PixelsPerInch := 96;
  G.SetBounds(0, 0, 400, 300);
  for i := 0 to 9 do
  begin
    c := G.Header.Columns.Add as TTyColumn;
    c.Width := 90;
  end;
  G.DefaultRowHeight := 22;
  G.RowCount := 20;
  G.FixedRows := 1;
  G.FixedColsRight := 1;
  G.Cells[9, 0] := '右上角';

  vis := G.CellVisibleRect(9, 0);
  AssertTrue('右上角那一格不该是空矩形', not IsRectEmpty(vis));
  { 与**它自己的**矩形比,而不是与 ClientWidth 比 ——
    纵向滚动条占掉了十几像素,视口右沿并不等于控件右沿。
    窗格裁剪正确时,完全可见的冻结格的可见矩形应当就是它的矩形。 }
  AssertEquals('右上角那一格不该被裁掉一截',
    G.CellRect(9, 0).Right, vis.Right);
end;

{ A1:固定行与排序**叠加**时,每一格都必须落在它显示位置所属的那个窗格里。

  `CellPane` 的两个判据(`< FixedRows` / `>= DisplayRowCount - FixedRowsBottom`)
  是**显示序**语义,而调用方喂的是**数据行**。两者一致时(没排序)看不出来;
  一排序就错位:数据下标 < FixedRows 的格子一律被判成 gpTop,与冻结带求交后
  成了空矩形 —— 它们滚到哪儿都不画,行**静默变空白**;反过来真正显示在冻结带里
  的行被判成 gpBody,同样被裁没。

  现有测试分别测固定行、分别测排序,从不叠加 —— 所以一直是绿的。 }
procedure TTyStringGridTest.TestFixedRowsAndSortTogetherKeepCellsInTheirPane;
var
  G: TStrGridAccess;
  r, pos: Integer;
  vis, geo: TRect;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 10;
  for r := 0 to 9 do
    G.Cells[0, r] := Format('%.2d', [r]);      { 00 .. 09 }
  G.FixedRows := 2;

  { 降序 —— 显示位置 0/1(冻结带)现在装的是**数据行 9/8**,
    而数据行 0/1 被推到了正文窗格的最下面。 }
  G.SortByColumn(0, sdDescending);
  AssertEquals('前置:降序后显示位置 0 是数据行 9', 9, G.DisplayRow(0));
  AssertEquals('前置:降序后显示位置 9 是数据行 0', 0, G.DisplayRow(9));

  { 10 行 × 20px = 200px,视口 300px 且没有横向滚动 ——
    每一格都完整可见,于是可见矩形应当**恰好等于**它的几何矩形。
    有一格被判错窗格,求交就会把它整个吃掉(空矩形)。 }
  for r := 0 to 9 do
  begin
    pos := G.DisplayRow(r);      { 只为报错信息好读 }
    vis := G.CellVisibleRect(0, r);
    geo := G.CellRect(0, r);
    AssertFalse(Format('数据行 %d(值 %s)的可见矩形不该是空的', [r, G.Cells[0, r]]),
      IsRectEmpty(vis));
    AssertEquals(Format('数据行 %d 的可见矩形顶边(显示位置解出 %d)', [r, pos]),
      geo.Top, vis.Top);
    AssertEquals(Format('数据行 %d 的可见矩形底边', [r]), geo.Bottom, vis.Bottom);
  end;
end;

{ 同族:冻结带的**厚度**也是把显示位置喂给按数据行查表的 `RowHeightOf`。
  可变行高 + 排序时,取的是**另外几行**的高度 —— 冻结带与正文于是错开一截:
  正文首行要么压住固定行、要么与它之间裂开一条缝。

  断言"显示位置 1 的底边 == 显示位置 2 的顶边"——
  纯几何、可观测,且不依赖厚度的具体数值。 }
procedure TTyStringGridTest.TestFrozenBandThicknessFollowsDisplayedRows;
var
  G, G2: TStrGridAccess;
  r: Integer;
  vis: TRect;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 10;
  for r := 0 to 9 do
    G.Cells[0, r] := Format('%.2d', [r]);
  { 让**排完序后落在冻结带里**的那两行高得与众不同。 }
  G.RowHeights[9] := 50;
  G.RowHeights[8] := 40;
  G.FixedRows := 2;

  G.SortByColumn(0, sdDescending);
  AssertEquals('前置:冻结带第一行是数据行 9', 9, G.DisplayRow(0));

  AssertEquals('冻结带厚度必须按**显示在带子里的那两行**算 —— 正文首行要接在它下面',
    G.CellRect(0, G.DisplayRow(1)).Bottom,
    G.CellRect(0, G.DisplayRow(2)).Top);

  { 底部带同理,而且它的症状更直接:带子算薄了,gpBottom 窗格就够不着
    最上面那行的上半截,那一截被裁掉。 }
  G2 := MakeStrGrid(FForm, FCtl);
  G2.RowCount := 10;
  for r := 0 to 9 do
    G2.Cells[0, r] := Format('%.2d', [r]);
  { 降序后显示在**底部两格**里的是数据行 1 和 0。 }
  G2.RowHeights[1] := 50;
  G2.RowHeights[0] := 40;
  G2.FixedRowsBottom := 2;

  G2.SortByColumn(0, sdDescending);
  AssertEquals('前置:底部带第一行是数据行 1', 1, G2.DisplayRow(8));

  vis := G2.CellVisibleRect(0, 1);
  AssertFalse('底部冻结行的可见矩形不该是空的', IsRectEmpty(vis));
  AssertEquals('底部冻结带算薄了会把最上面那行裁掉一截',
    G2.CellRect(0, 1).Top, vis.Top);
end;

{ A6:锚点行被筛掉之后,活动选区不能反而**变大**。

  `ActiveSelectionRect` 把 `DataToDisplay` 的返回值直接喂给 Min/Max,而被筛掉的行
  返回 -1 —— 于是选区从 -1 起算,一路吃到显示位置 0,把表格最上面那些
  从来没被选过的行全括进来。 }
procedure TTyStringGridTest.TestFilteringOutTheAnchorDoesNotGrowTheSelection;
var
  G: TStrGridAccess;
  r: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);            { 4 列 x 10 行 }
  for r := 0 to 9 do
    G.Cells[0, r] := 'keep';
  G.Cells[0, 2] := 'drop';                  { 待会儿把这一行筛掉 }

  { 锚点落在数据行 2,光标拉到数据行 4。 }
  G.Col := 0; G.Row := 2;
  G.AnchorSelection;
  G.PressKeyShift(VK_DOWN);
  G.PressKeyShift(VK_DOWN);
  AssertEquals('前置:光标在数据行 4', 4, G.Row);
  AssertTrue('前置:数据行 3 在选区里', G.IsCellSelected(0, 3));
  AssertFalse('前置:数据行 0 不在选区里', G.IsCellSelected(0, 0));

  { 把**锚点那一行**筛掉 —— 它从此没有显示位置。 }
  G.SetColumnFilter(0, 'keep');
  AssertEquals('前置:筛掉一行', 9, G.DisplayRowCount);

  AssertFalse('筛掉锚点后,表头那边的行不该突然被选中', G.IsCellSelected(0, 0));
  AssertFalse('数据行 1 同样从来没被选过', G.IsCellSelected(0, 1));
  AssertTrue('光标那一行仍然选中', G.IsCellSelected(0, 4));
end;

{ A7:`SwapRows` 搬了三种状态(文字 / 逐格属性 / 行高),而只有文字经过
  `SetCells` 这个记录点 —— 拖完行按 Ctrl+Z,文字回来了、底色和行高留在新位置,
  得到一个从未存在过的状态。

  修法不是"补一条 gukRowSwap":同一条记录里已经有逐格的 gukCell 条目,
  再叠一条整行交换会**双重施加**。要给属性存储和行高各自一个记录点。 }
procedure TTyStringGridTest.TestUndoRestoresCellAttributesAndRowHeights;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.Cells[0, 1] := 'A';
  G.Cells[0, 2] := 'B';
  G.CellColors[0, 1] := TyRGB(255, 0, 0);
  G.RowHeights[1] := 44;
  G.ClearUndo;

  G.SwapRows(1, 2);
  AssertEquals('前置:文字换了位置', 'A', G.Cells[0, 2]);
  AssertEquals('前置:底色跟着那一行走', TyRGB(255, 0, 0), G.CellColors[0, 2]);
  AssertEquals('前置:行高跟着那一行走', 44, G.RowHeights[2]);

  G.Undo;
  AssertEquals('文字回到原位', 'A', G.Cells[0, 1]);
  AssertEquals('底色也要回到原位', TyRGB(255, 0, 0), G.CellColors[0, 1]);
  AssertEquals('换过去的那一行不该还留着底色', 0, G.CellColors[0, 2]);
  { 行高用**几何**断言 —— 存储回读不了了不算数,要真的把行画成那么高。 }
  AssertEquals('行高撤销后必须真的改回几何', 44,
    G.CellRect(0, 1).Bottom - G.CellRect(0, 1).Top);
  AssertEquals('换过去的那一行回到默认行高', 20,
    G.CellRect(0, 2).Bottom - G.CellRect(0, 2).Top);

  G.Redo;
  AssertEquals('重做:文字再换回去', 'A', G.Cells[0, 2]);
  AssertEquals('重做:底色跟着走', TyRGB(255, 0, 0), G.CellColors[0, 2]);
  AssertEquals('重做:行高跟着走', 44,
    G.CellRect(0, 2).Bottom - G.CellRect(0, 2).Top);
end;

{ 记录点收口在属性存储上,于是**所有**改属性的路径一并可撤销 ——
  连 P3 当初明确留下的偏离("合并/取消合并不进撤销栈")也一起补上了。 }
procedure TTyStringGridTest.TestUndoRestoresCellColorAndMerge;
var
  G: TStrGridAccess;
  w1: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.ClearUndo;

  G.CellColors[1, 1] := TyRGB(0, 0, 255);
  AssertTrue('前置:设底色之后有得撤销', G.CanUndo);
  G.Undo;
  AssertEquals('设底色可以撤销', 0, G.CellColors[1, 1]);
  G.Redo;
  AssertEquals('重做把底色放回去', TyRGB(0, 0, 255), G.CellColors[1, 1]);

  { 合并用**几何**断言:基准格的矩形该横跨两列。 }
  w1 := G.CellRect(0, 3).Right - G.CellRect(0, 3).Left;
  G.MergeCells(0, 3, 2, 2);
  AssertEquals('前置:合并后基准格横跨两列', w1 * 2,
    G.CellRect(0, 3).Right - G.CellRect(0, 3).Left);

  G.Undo;
  AssertEquals('撤销合并之后基准格缩回一列宽', w1,
    G.CellRect(0, 3).Right - G.CellRect(0, 3).Left);
  AssertFalse('撤销之后表里不该还有合并区', G.HasMergedCells);

  G.Redo;
  AssertEquals('重做把合并放回去', w1 * 2,
    G.CellRect(0, 3).Right - G.CellRect(0, 3).Left);
  AssertTrue('重做之后合并计数也要回来', G.HasMergedCells);

  { **清除**路径走的是另一条代码路:"改一条已有的属性",而不是"新建一条"。
    上面那两段全是新建,单靠它们守不住清除路径。 }
  G.ClearUndo;
  G.UnmergeCells(0, 3);
  AssertEquals('前置:取消了合并', w1,
    G.CellRect(0, 3).Right - G.CellRect(0, 3).Left);
  G.Undo;
  AssertEquals('取消合并也要能撤销', w1 * 2,
    G.CellRect(0, 3).Right - G.CellRect(0, 3).Left);
  AssertTrue('撤销之后合并计数要回来', G.HasMergedCells);

  G.ClearUndo;
  G.CellColors[1, 1] := 0;                  { 0 = 清掉底色 }
  AssertEquals('前置:底色被清掉了', 0, G.CellColors[1, 1]);
  G.Undo;
  AssertEquals('清底色也要能撤销', TyRGB(0, 0, 255), G.CellColors[1, 1]);
end;

{ B2:三条行置换路径各搬了不同的子集。`SwapRows` 搬了文字、属性、行高,
  唯独漏了**隐藏标记** —— 标记留在旧下标上,于是换过去的那一行凭空消失,
  藏着的那一行冒出来。用户读到的是"表里又多/少了一行"。

  可观测断言:走一遍显示序,看**谁被显示出来**,不看标记本身。 }
procedure TTyStringGridTest.TestSwappingRowsCarriesTheHiddenFlag;
var
  G: TStrGridAccess;
  r, pos: Integer;
  shown: string;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 6;
  for r := 0 to 5 do
    G.Cells[0, r] := Chr(Ord('A') + r);      { A B C D E F }

  G.HideRow(2);                              { 藏起 'C' }
  AssertEquals('前置:少了一行', 5, G.DisplayRowCount);

  G.SwapRows(1, 2);                          { 'C' 换到下标 1,'B' 换到下标 2 }
  AssertEquals('前置:文字换了位置', 'C', G.Cells[0, 1]);

  shown := '';
  for pos := 0 to G.DisplayRowCount - 1 do
    shown := shown + G.Cells[0, G.DisplayRow(pos)];

  AssertEquals('藏起来的那一行换了位置也还该藏着,别的一个都不能少',
    'ABDEF', shown);
end;

{ B3:页脚汇总此前**每帧**遍历全部显示行(RenderFooter → AggregateValue)。
  百万行时滚动就是每帧一次 O(n) 扫描。

  两面都要断言:缓存住了(重复问不再扫),以及**该失效的时候真的失效了**
  —— 陈旧的合计比慢的合计糟得多,用户会照着一个错数做决定。 }
procedure TTyStringGridTest.TestFooterAggregateIsCachedAndInvalidated;
var
  G: TCountingGrid;
  i: Integer;
  c: TTyColumn;
begin
  G := TCountingGrid.Create(FForm);
  G.Parent := FForm;
  G.Controller := FCtl;
  G.Font.PixelsPerInch := 96;
  G.SetBounds(0, 0, 400, 300);
  for i := 0 to 3 do
  begin
    c := G.Header.Columns.Add as TTyColumn;
    c.Width := 80;
  end;
  G.Header.Options := G.Header.Options - [hoVisible];
  G.DefaultRowHeight := 20;
  G.RowCount := 40;
  for i := 0 to 39 do
    G.Cells[0, i] := IntToStr(i + 1);          { 1..40,合计 820 }
  G.SetColumnAggregate(0, gagSum);

  AssertEquals('前置:合计对', 'Sum 820', G.FooterText(0));
  G.ScanCount := 0;
  AssertEquals('再问一次结果不变', 'Sum 820', G.FooterText(0));
  AssertEquals('第二次不该再扫一遍全表', 0, G.ScanCount);

  { --- 以下每一条都是"必须失效"的时机 --- }

  G.Cells[0, 0] := '101';                      { 改一格:820 - 1 + 101 }
  AssertEquals('改了格值,合计必须跟着变', 'Sum 920', G.FooterText(0));

  G.RowCount := 41;
  G.Cells[0, 40] := '80';
  AssertEquals('加了一行,合计必须跟着变', 'Sum 1000', G.FooterText(0));

  G.HideRow(40);
  AssertEquals('藏起一行,合计必须跟着变', 'Sum 920', G.FooterText(0));
  G.UnHideRow(40);

  G.SetColumnFilter(0, '101');                 { 只剩那一行 }
  AssertEquals('筛选之后只统计留下的行', 'Sum 101', G.FooterText(0));
  G.SetColumnFilter(0, '');
  AssertEquals('清掉筛选恢复', 'Sum 1000', G.FooterText(0));

  G.Undo;                                      { 撤销掉 '80' 那一格 }
  AssertEquals('撤销之后合计也要跟着回去', 'Sum 920', G.FooterText(0));

  { 换口径必须换成一个**也走缓存**的口径才有分辨力 ——
    gagCount 是 O(1)、压根不进缓存,拿它当断言等于什么都没测。 }
  G.SetColumnAggregate(0, gagAvg);
  AssertEquals('换了聚合口径也要重算', 'Avg 23', G.FooterText(0));
end;

{ 头文件里写着"一次批量操作(粘贴、填充、删行)算**一条**,因为它们都在
  BeginUpdate 里跑"。粘贴其实跑在 `BeginUpdateOrder` 里 —— 那个只压重排,
  跟撤销事务(BeginUpdate → OpenUndoGroup)是两回事。于是粘 4 格压 4 条记录,
  用户得按 4 次 Ctrl+Z 才退得回去;剪切干脆一点批量都没有。

  断言站在用户那一侧:**按一次撤销,整块都得回来**。 }
procedure TTyStringGridTest.TestPasteAndCutAreOneUndoStepEach;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.Cells[0, 0] := 'a0'; G.Cells[1, 0] := 'b0';
  G.Cells[0, 1] := 'a1'; G.Cells[1, 1] := 'b1';

  { --- 粘贴 --- }
  G.MoveCursor(0, 0);
  G.ClearUndo;
  G.PasteFromText('X' + #9 + 'Y' + LineEnding + 'Z' + #9 + 'W');
  AssertEquals('前置:粘贴生效了', 'X', G.Cells[0, 0]);
  AssertEquals('前置:整块都粘上了', 'W', G.Cells[1, 1]);
  AssertEquals('一次粘贴 = 一条撤销记录', 1, G.UndoCountForTest);

  G.Undo;
  AssertEquals('按一次撤销,左上角就得回来', 'a0', G.Cells[0, 0]);
  AssertEquals('同一次撤销,右下角也得回来', 'b1', G.Cells[1, 1]);
  AssertEquals('中间两格同理', 'b0', G.Cells[1, 0]);
  AssertEquals('中间两格同理', 'a1', G.Cells[0, 1]);

  { --- 剪切 --- }
  G.MoveCursor(0, 0);
  G.AnchorSelection;
  G.PressKeyShift(VK_RIGHT);
  G.PressKeyShift(VK_DOWN);
  G.ClearUndo;
  G.CutToClipboard;
  AssertEquals('前置:剪切清空了左上角', '', G.Cells[0, 0]);
  AssertEquals('前置:剪切清空了右下角', '', G.Cells[1, 1]);
  AssertEquals('一次剪切 = 一条撤销记录', 1, G.UndoCountForTest);

  G.Undo;
  AssertEquals('按一次撤销,剪掉的整块都得回来', 'a0', G.Cells[0, 0]);
  AssertEquals('剪掉的整块都得回来', 'b1', G.Cells[1, 1]);

  { --- 批量增删行 ---
    单数的 InsertRow/DeleteRow 早就包了事务,**复数**那两个没有 ——
    同一条规则逐处重述,又漏了一处。 }
  G.ClearUndo;
  G.InsertRows(0, 3);
  AssertEquals('前置:插了 3 行', 13, G.RowCount);
  AssertEquals('前置:原来的第 0 行被顶到第 3 行', 'a0', G.Cells[0, 3]);
  AssertEquals('插 3 行 = 一条撤销记录', 1, G.UndoCountForTest);
  G.Undo;
  AssertEquals('按一次撤销就回到 10 行', 10, G.RowCount);
  AssertEquals('内容也回原位', 'a0', G.Cells[0, 0]);

  G.ClearUndo;
  G.RemoveRows(0, 2);
  AssertEquals('前置:删了 2 行', 8, G.RowCount);
  AssertEquals('删 2 行 = 一条撤销记录', 1, G.UndoCountForTest);
  G.Undo;
  AssertEquals('按一次撤销就把两行都还回来', 10, G.RowCount);
  AssertEquals('删掉的内容也回来了', 'a0', G.Cells[0, 0]);
  AssertEquals('第二行的内容也回来了', 'a1', G.Cells[0, 1]);
end;

{ `ClearCells` 直接 `FCells.Clear`,绕过了 `SetCells` 那个记录点 ——
  于是它自己不可撤销,连带**导入 CSV**整件事也撤不回来(导入的第一步就是清空)。
  这是"绕过收口点"的代价:收口点保证的只是**经过它的**改动。

  顺带:它也没让汇总缓存失效 —— 清空一张表之后页脚还挂着旧的合计。 }
procedure TTyStringGridTest.TestClearAndCsvImportAreUndoable;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.Cells[0, 0] := '11';
  G.Cells[1, 0] := 'keep';
  G.Cells[0, 1] := '22';
  G.SetColumnAggregate(0, gagSum);
  AssertEquals('前置:合计对', 'Sum 33', G.FooterText(0));

  G.ClearUndo;
  G.ClearCells;
  AssertEquals('前置:清空了', '', G.Cells[0, 0]);
  AssertEquals('清空之后页脚不能还挂着旧合计', 'Sum 0', G.FooterText(0));
  AssertEquals('清空 = 一条撤销记录', 1, G.UndoCountForTest);

  G.Undo;
  AssertEquals('清空可以撤销', '11', G.Cells[0, 0]);
  AssertEquals('每一格都回来', 'keep', G.Cells[1, 0]);
  AssertEquals('每一格都回来', '22', G.Cells[0, 1]);
  AssertEquals('合计也跟着回来', 'Sum 33', G.FooterText(0));

  { 导入 CSV = 清空 + 重填。整件事必须是**一条**记录,
    否则撤销一次只退回半张表 —— 比不能撤销更难排查。 }
  G.ClearUndo;
  { 第一行是**表头**,不是数据 —— 后面两行才是。 }
  G.LoadFromCSVText('h1,h2' + LineEnding + '7,8' + LineEnding + '9,10', ',');
  AssertEquals('前置:导入生效', '7', G.Cells[0, 0]);
  AssertEquals('导入 CSV = 一条撤销记录', 1, G.UndoCountForTest);

  G.Undo;
  AssertEquals('导入 CSV 可以撤销', '11', G.Cells[0, 0]);
  AssertEquals('被导入覆盖掉的格也回来', 'keep', G.Cells[1, 0]);
end;

{ 把记录点挂在属性存储的"即将改动"通知上,代价是它**分不清"要改"和"改成一样的"**。
  `SetCells` 早有这道保护(`if e.OldText <> AValue`),属性这边一开始没跟上:
  于是把红色再设一次红色也压一条空记录 —— 按 Ctrl+Z 一次没反应,
  更阴的是这条空记录**把重做链清掉了**(刚撤销的那一步再也重做不回来)。

  这是本轮引入的回归,对抗审查抓到的。 }
procedure TTyStringGridTest.TestNoOpAttributeWriteLeavesTheUndoStackAlone;
var
  G: TStrGridAccess;
  w1: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);

  G.CellColors[0, 0] := TyRGB(255, 0, 0);
  G.ClearUndo;
  G.CellColors[0, 0] := TyRGB(255, 0, 0);        { 同一个颜色 }
  AssertEquals('设成同一个颜色不该压撤销记录', 0, G.UndoCountForTest);

  G.CellTextColors[1, 1] := TyRGB(0, 128, 0);
  G.ClearUndo;
  G.CellTextColors[1, 1] := TyRGB(0, 128, 0);
  AssertEquals('文字色同理', 0, G.UndoCountForTest);

  G.CellReadOnly[2, 2] := True;
  G.ClearUndo;
  G.CellReadOnly[2, 2] := True;
  AssertEquals('只读同理', 0, G.UndoCountForTest);

  w1 := G.CellRect(0, 4).Right - G.CellRect(0, 4).Left;
  G.MergeCells(0, 4, 2, 2);
  G.ClearUndo;
  G.MergeCells(0, 4, 2, 2);                      { 同样的跨度 }
  AssertEquals('合并成同样的跨度同理', 0, G.UndoCountForTest);
  AssertEquals('而且跨度本身没变', w1 * 2,
    G.CellRect(0, 4).Right - G.CellRect(0, 4).Left);

  { 空记录最阴的一面:它把**重做链**清掉了。 }
  G.CellColors[3, 3] := TyRGB(0, 0, 255);
  G.Undo;
  AssertEquals('前置:撤销掉了', 0, G.CellColors[3, 3]);
  AssertTrue('前置:有得重做', G.CanRedo);
  G.CellColors[0, 0] := TyRGB(255, 0, 0);        { 无变化的写入 }
  AssertTrue('无变化的写入不该把重做链清掉', G.CanRedo);
  G.Redo;
  AssertEquals('重做要能真的把它做回来',
    TyRGB(0, 0, 255), G.CellColors[3, 3]);
end;

{ `FMergeCount` 是旁挂的汇总,不在属性对象里。删行时属性条目被 ShiftCells 直接
  丢掉,计数没跟着减 —— 于是表里"还有合并区"而实际一个都没有。
  本轮给 RestoreAttr 加了对账,但那只管撤销那条路;删除这条路仍然漏。 }
procedure TTyStringGridTest.TestMergeCountSurvivesRowRemovalAndUndo;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.MergeCells(0, 1, 2, 2);
  AssertTrue('前置:合并了', G.HasMergedCells);

  G.RemoveRows(1, 2);                    { 把合并区那两行整个删掉 }
  AssertFalse('合并区被删掉之后,表里就不该还"有合并区"了',
    G.HasMergedCells);

  G.Undo;
  AssertTrue('撤销之后合并区回来了', G.HasMergedCells);
  G.UnmergeCells(0, 1);
  AssertFalse('取消掉唯一那个合并之后,计数必须归零',
    G.HasMergedCells);
end;

{ `ClearMerges` 一次清掉所有合并,却每个格子压一条记录 ——
  与粘贴/剪切/批量增删行是同一族缺陷(规则被逐处重述而不是收口)。 }
procedure TTyStringGridTest.TestClearMergesIsOneUndoStep;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.MergeCells(0, 0, 2, 1);
  G.MergeCells(0, 2, 2, 1);
  G.MergeCells(0, 4, 2, 1);
  G.ClearUndo;

  G.ClearMerges;
  AssertFalse('前置:合并都清掉了', G.HasMergedCells);
  AssertEquals('清掉三处合并 = 一条撤销记录', 1, G.UndoCountForTest);

  G.Undo;
  AssertTrue('按一次撤销,三处合并都回来', G.HasMergedCells);
  AssertFalse('而且栈里不该还剩别的', G.CanUndo);
end;

{ 一条撤销记录攒得过大时,设计是"**整条作废并清空栈**" ——
  注释写得很清楚:半条撤销记录还原出来是一张四不像的表,
  比"这一步撤销不了"危险得多。

  但溢出那条路走的是 `ClearUndo`,而 `ClearUndo` 顺手把 `FUndoOverflow` 清成了
  False —— 于是作废标志自己把自己抹掉,后面的条目继续往里攒,
  收尾时**正好把那半条残缺记录推进了栈**。设计要防的事照样发生了。

  断言站在用户那一侧:超限之后**撤不了**(而不是撤出一张四不像的表)。 }
procedure TTyStringGridTest.TestOversizedUndoRecordIsDiscardedNotTruncated;
var
  G: TStrGridAccess;
  i, n: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  n := 200005;                     { 略高于 200000 那道阈值 }
  G.RowCount := n;
  G.Cells[0, 0] := 'before';
  G.ClearUndo;

  { 一整个事务里灌进超过阈值的改动。 }
  G.BeginUpdate;
  try
    for i := 1 to n - 1 do
      G.Cells[0, i] := 'x';
  finally
    G.EndUpdate;
  end;

  AssertFalse('超限的那条记录必须整条作废 —— 栈里不该留半条', G.CanUndo);
end;

{ 与 A6 同一族:`DataToDisplay` 对被筛掉的行答 -1,而粘贴拿它当起始显示位置
  直接用了。光标停在一个被筛掉的行上时:
    · 第一行 `DisplayToData(-1)` = -1 → 被 `Continue` **静默丢掉**;
    · 其余每行都往上错一位,从表**最顶上**开始铺,而不是光标附近。
  丢数据 + 落错位置,都不报错。(选区那处早有 `if startPos < 0 then startPos := 0`,
  粘贴这条路径漏了 —— 又一次"规则没收口"。) }
procedure TTyStringGridTest.TestPasteWithAFilteredOutCursorRowKeepsEveryLine;
var
  G: TStrGridAccess;
  r: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  for r := 0 to 9 do
    G.Cells[0, r] := 'keep';
  G.Cells[0, 3] := 'drop';

  G.Col := 0;
  G.Row := 3;
  G.SetColumnFilter(0, 'keep');           { 光标那一行被筛掉了 }
  AssertEquals('前置:少了一行', 9, G.DisplayRowCount);

  G.PasteFromText('A' + LineEnding + 'B');

  AssertEquals('第一行不能被静默丢掉', 'A', G.Cells[0, 0]);
  AssertEquals('第二行接在它下面', 'B', G.Cells[0, 1]);
end;

{ `PermuteRowState` 搬四样东西(文字、格属性、行高、隐藏标记),
  前三样都有记录点,隐藏标记没有 —— 于是拖完行按 Ctrl+Z,
  文字和底色回来了、**藏着的还是换过去那一行**。
  这正是 A7 那个缺陷,换了个位置又出现一次。 }
procedure TTyStringGridTest.TestUndoingARowSwapRestoresTheHiddenFlag;
var
  G: TStrGridAccess;
  r, pos: Integer;
  shown: string;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 6;
  for r := 0 to 5 do
    G.Cells[0, r] := Chr(Ord('A') + r);      { A B C D E F }
  G.HideRow(2);                              { 藏起 'C' }
  G.ClearUndo;

  G.SwapRows(1, 2);
  AssertEquals('前置:换过去了', 'C', G.Cells[0, 1]);

  G.Undo;
  AssertEquals('前置:文字换回来了', 'B', G.Cells[0, 1]);

  shown := '';
  for pos := 0 to G.DisplayRowCount - 1 do
    shown := shown + G.Cells[0, G.DisplayRow(pos)];
  AssertEquals('撤销之后,藏着的还得是原来那一行', 'ABDEF', shown);
end;

{ 选中一片格子涂个底色,按一次 Ctrl+Z 应该整片退回去 —— 而不是一格一格退。

  遍历选区的骨架(`ForEachSelectedNumber`)一直只有**只读**那一半:
  四个聚合入口共用它,而写侧什么都没有。于是"给选区涂色"只能由宿主自己写循环,
  而循环里没人记得包事务 —— 示例就是这么写的,用户一撤销就露馅。
  与粘贴/剪切/批量增删行/ClearMerges 是同一族。 }
procedure TTyStringGridTest.TestColouringASelectionIsOneUndoStep;
var
  G: TStrGridAccess;
  red: TTyColor;
begin
  G := MakeStrGrid(FForm, FCtl);
  red := TyRGB(255, 0, 0);

  { 拉一个 2x3 的选区(2 列 x 3 行)。 }
  G.Col := 1; G.Row := 1;
  G.AnchorSelection;
  G.PressKeyShift(VK_RIGHT);
  G.PressKeyShift(VK_DOWN);
  G.PressKeyShift(VK_DOWN);
  AssertEquals('前置:选中 6 格', 6, G.SelectedCellCount);
  G.ClearUndo;

  AssertEquals('涂色返回涂了几格', 6, G.SetSelectionColor(red));
  AssertEquals('前置:左上角涂上了', red, G.CellColors[1, 1]);
  AssertEquals('前置:右下角涂上了', red, G.CellColors[2, 3]);
  AssertEquals('涂一片 = 一条撤销记录', 1, G.UndoCountForTest);

  G.Undo;
  AssertEquals('按一次撤销,左上角就退回去', 0, G.CellColors[1, 1]);
  AssertEquals('同一次撤销,右下角也退回去', 0, G.CellColors[2, 3]);
  AssertEquals('中间的也一样', 0, G.CellColors[1, 2]);
  AssertFalse('而且栈里不该还剩别的', G.CanUndo);

  G.Redo;
  AssertEquals('重做也是一次到位', red, G.CellColors[2, 3]);

  { 清掉底色走同一条路(传 0 = 清除)。 }
  G.ClearUndo;
  AssertEquals('清色也返回格数', 6, G.SetSelectionColor(0));
  AssertEquals('前置:清掉了', 0, G.CellColors[1, 1]);
  AssertEquals('清一片也是一条记录', 1, G.UndoCountForTest);
  G.Undo;
  AssertEquals('撤销把整片颜色还回来', red, G.CellColors[1, 1]);
end;

{ `AutoFitRows` 逐行调 `AutoFitRow`,而行高本轮起有了记录点 ——
  于是"全表自适应行高"一次压 RowCount 条记录。同一族的又一个。
  (逐行的 `AutoFitRow` 本身是一次操作、一条记录,那是对的。) }
procedure TTyStringGridTest.TestAutoFitRowsIsOneUndoStep;
var
  G: TStrGridAccess;
  r: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 8;
  for r := 0 to 7 do
    G.Cells[0, r] := 'a line of text that will need wrapping ' + IntToStr(r);
  G.WordWrap := True;
  G.ClearUndo;

  G.AutoFitRows;
  AssertEquals('全表自适应 = 一条撤销记录', 1, G.UndoCountForTest);

  G.Undo;
  AssertFalse('按一次撤销就全退回去,栈里不该还剩别的', G.CanUndo);
end;

{ B2 的**列轴对偶** —— 做 B2 时只想了按行记账的旁挂表,漏了按列记账的那三张:
  `FColFilters` / `FValFilters` / `FAggregates` 全都是"列下标 = 值",
  而增删列只搬了格子和格属性,这三张表原地不动。

  代价比行那边更狠:筛选留在旧列号上 → 那一列的文字取出来是空 →
  **每一行都不匹配 → 整张表变空**,而漏斗图标已经跟着列走了,
  用户在界面上找不到任何地方去清掉它。 }
procedure TTyStringGridTest.TestColumnKeyedTablesFollowInsertAndDelete;
var
  G: TStrGridAccess;
  r: Integer;
begin
  G := MakeStrGrid(FForm, FCtl);          { 4 列 x 10 行 }
  for r := 0 to 9 do
  begin
    G.Cells[3, r] := 'keep';
    G.Cells[2, r] := IntToStr(r + 1);     { 合计 55 }
  end;
  G.Cells[3, 4] := 'drop';

  G.SetColumnFilter(3, 'keep');
  G.SetColumnAggregate(2, gagSum);
  AssertEquals('前置:筛掉一行', 9, G.DisplayRowCount);
  AssertEquals('前置:合计在第 2 列', 'Sum 50', G.FooterText(2));

  { 在左边插一列 —— 筛选与合计都该跟着各自那一列右移。 }
  G.InsertColumn(0);
  AssertEquals('插列之后筛选要跟着那一列走', 9, G.DisplayRowCount);
  AssertEquals('合计也跟着那一列走', 'Sum 50', G.FooterText(3));
  AssertEquals('原来那一列不该还挂着合计', '', G.FooterText(2));

  { 删掉左边那一列 —— 都该回到原位。 }
  G.DeleteColumn(0);
  AssertEquals('删列之后筛选还在正确的列上', 9, G.DisplayRowCount);
  AssertEquals('合计回到第 2 列', 'Sum 50', G.FooterText(2));

  { 删掉**被筛选的那一列本身** —— 它的筛选必须一起丢掉,
    否则表会按一个已经不存在的列筛,结果是一行都不剩。 }
  G.DeleteColumn(3);
  AssertEquals('被筛选的列删掉之后,筛选也要跟着没', 10, G.DisplayRowCount);
end;

{ 增删行走的是 `ShiftRowKeyedTable`,它直接重建两张表 —— 绕过了
  `SetRowHeights` / `SetRowHidden` 那两个记录点。于是撤销一次增/删行:
  文字和行数都对了,**行高和隐藏标记却永久错位一格**;
  而正落在删除位置上的那一条直接丢掉,再也回不来。

  纯置换那两条路(SwapRows / ApplyOrderToData)本轮已经收口进 PermuteRowState 了,
  增删这条路是它的另一半,当时没做。 }
procedure TTyStringGridTest.TestUndoingRowInsertRestoresHeightsAndHiddenFlags;
var
  G: TStrGridAccess;
begin
  G := MakeStrGrid(FForm, FCtl);
  G.RowCount := 10;
  G.Cells[0, 5] := 'tall';
  G.RowHeights[5] := 60;
  G.HideRow(7);
  G.ClearUndo;

  G.InsertRow(0);
  AssertEquals('前置:行高跟着数据下移了一行', 60, G.RowHeights[6]);
  AssertTrue('前置:隐藏标记也下移了', G.IsHiddenRow(8));

  G.Undo;
  AssertEquals('撤销之后文字回原位', 'tall', G.Cells[0, 5]);
  AssertEquals('行高也要回原位', 60, G.RowHeights[5]);
  AssertEquals('原来那一行不该还留着行高', 0, G.RowHeights[6]);
  AssertTrue('隐藏标记也要回原位', G.IsHiddenRow(7));
  AssertFalse('移过去那一行不该还藏着', G.IsHiddenRow(8));

  { 删掉**承载行高/隐藏标记的那一行本身**,撤销要把它们一起还回来 ——
    这一条从前是直接丢弃、无处可还的。 }
  G.ClearUndo;
  G.DeleteRow(5);
  AssertEquals('前置:删掉了', 0, G.RowHeights[5]);
  G.Undo;
  AssertEquals('删掉的那一行的行高也得还回来', 60, G.RowHeights[5]);
  AssertEquals('文字当然也要还回来', 'tall', G.Cells[0, 5]);
end;

initialization
  RegisterTest(TTyGridControlTest);
  RegisterTest(TTyDrawGridTest);
  RegisterTest(TTyStringGridTest);
end.
