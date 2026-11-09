unit tyControls.AdvanceChart.StrConsts;

{$mode objfpc}{$H+}

interface

{ The resourcestrings of the chart (TTyAdvanceChart and its design-time editors' runtime
  part): what an option tree can say that cannot be honoured, the toolbox, the aria
  description, the dataset transforms, the option and series editors' vocabulary. English
  is the msgid; translations live in
  languages/tycontrols.advancechart.strconsts.<lang>.po, which an application loads beside
  the main package's catalogue. The loader takes a file name without a dot (LCL reads what
  follows a dot as an extension and swaps the language in for it), so deploy the file as
  tycontrols_advancechart.<lang>.po next to the library's own and add one line at start-up:

    TranslateUnitResourceStringsEx('', LangDir, 'tycontrols_advancechart',
      'tyControls.AdvanceChart.StrConsts');

  The names are the ones they had in tyControls.StrConsts, so the chart's code changed only
  in its uses clauses. }
resourcestring
  // --- AdvanceChart: what an option tree can say that cannot be honoured ---
  // Both reach the user through the chart's diagnostics list, so they are as
  // user-facing as any caption.
  rsTyChartNoSuchHandler = 'No formatter named ''%s'' is registered.';
  rsTyOptTooDeep = 'The option is nested more than %d levels deep.';
  rsTyOptFunctionValue =
    'JavaScript functions cannot be used here. Write a template string such as '
  + '''{b}: {c}'', or the name of a registered handler such as ''@MyFormatter''.';
  rsTyOptMergeNotObject = 'An option to merge must be an object.';
  rsTyOptDuplicateId = 'Two %s components carry the id "%s".';
  rsTyOptReplaceMergeBadType = 'replaceMerge names "%s", which is not a component main type.';
  rsTyOptSetOptsNotObject = 'The setOption options must be an object.';

  // --- AdvanceChart: the legend's selector buttons (ECharts' locale
  // legend.selector.all / inverse; upstream's English is 'All' / 'Inv') ---
  rsTyChartLegendSelectAll = 'All';
  rsTyChartLegendSelectInverse = 'Inv';

  // --- AdvanceChart: export and loading [Batch 106] ---
  // The loading effect's default text. Upstream's is 'loading' and ECharts
  // does not translate it; a control in a translated application should not
  // be the one English word on the form, so this one is a resourcestring --
  // and the English stays upstream's, so an untranslated build lays the
  // effect out exactly as upstream does.
  rsTyChartLoading = 'loading';
  // What the export and loading calls raise for options that are not JSON.
  rsTyChartExportOptsBad = 'The export options are not valid JSON.';
  rsTyChartLoadingCfgBad = 'The loading options are not valid JSON.';

  // --- AdvanceChart: the toolbox [Batch 125] ---
  // The icons' titles and the data view's words. The English is ECharts'
  // own locale (langEN.ts toolbox), so an untranslated build measures and
  // lays out the titles exactly as upstream does; the data view's Close
  // button is rsMsgBtnClose.
  rsTyChartToolboxSaveAsImage = 'Save as Image';
  rsTyChartToolboxRestore = 'Restore';
  rsTyChartToolboxDataView = 'Data View';
  rsTyChartToolboxDataViewRefresh = 'Refresh';
  // the data view's two pages [spec 232]: the blocks as grids, and the text
  rsTyChartToolboxDataViewTable = 'Table';
  rsTyChartToolboxDataViewText = 'Text';
  rsTyChartToolboxZoom = 'Zoom';
  rsTyChartToolboxZoomBack = 'Zoom Reset';
  rsTyChartToolboxLine = 'Switch to Line Chart';
  rsTyChartToolboxBar = 'Switch to Bar Chart';
  rsTyChartToolboxStack = 'Stack';
  rsTyChartToolboxTiled = 'Tile';
  // the brush feature's buttons [Batch 127] (langEN.ts toolbox.brush.title)
  rsTyChartToolboxBrushRect = 'Box Select';
  rsTyChartToolboxBrushPolygon = 'Lasso Select';
  rsTyChartToolboxBrushLineX = 'Horizontally Select';
  rsTyChartToolboxBrushLineY = 'Vertically Select';
  rsTyChartToolboxBrushKeep = 'Keep Selections';
  rsTyChartToolboxBrushClear = 'Clear Selections';
  // what the data view says when its text does not parse back
  rsTyChartToolboxDataViewBad = 'The data view''s text could not be read back: %s';
  // the save dialog's filter for saveAsImage
  rsTyChartToolboxImageFilter = 'PNG image (*.png)|*.png|JPEG image (*.jpeg;*.jpg)|*.jpeg;*.jpg|All files (*.*)|*.*';


  // --- AdvanceChart: the chart's description, its aria-label [Batch 131] ---
  // ECharts' own locale (langEN.ts aria and series.typeNames), so an
  // untranslated build says exactly what upstream's EN build says. The words
  // in braces are placeholders the chart fills in: keep them as they are.
  // A leading or trailing space is part of the sentence.
  rsTyChartAriaWithTitle = 'This is a chart about "{title}"';
  rsTyChartAriaWithoutTitle = 'This is a chart';
  rsTyChartAriaSingleWithName = ' with type {seriesType} named {seriesName}.';
  rsTyChartAriaSingleWithoutName = ' with type {seriesType}.';
  rsTyChartAriaMultiplePrefix = '. It consists of {seriesCount} series count.';
  rsTyChartAriaMultipleWithName = ' The {seriesId} series is a {seriesType} representing {seriesName}.';
  rsTyChartAriaMultipleWithoutName = ' The {seriesId} series is a {seriesType}.';
  rsTyChartAriaAllData = 'The data is as follows: ';
  rsTyChartAriaPartialData = 'The first {displayCnt} items are: ';
  rsTyChartAriaDataWithName = 'the data for {name} is {value}';
  // The four separators in one string, '|' between them: between two
  // series, after the last, between two values or rows, after the last.
  // One string because some are empty in one language and not another.
  rsTyChartAriaSeparators = '||, |. ';
  // the series types' names (series.typeNames)
  rsTyChartTypePie = 'Pie chart';
  rsTyChartTypeBar = 'Bar chart';
  rsTyChartTypeLine = 'Line chart';
  rsTyChartTypeScatter = 'Scatter plot';
  rsTyChartTypeEffectScatter = 'Ripple scatter plot';
  rsTyChartTypeRadar = 'Radar chart';
  rsTyChartTypeTree = 'Tree';
  rsTyChartTypeTreemap = 'Treemap';
  rsTyChartTypeBoxplot = 'Boxplot';
  rsTyChartTypeCandlestick = 'Candlestick';
  rsTyChartTypeK = 'K line chart';
  rsTyChartTypeHeatmap = 'Heat map';
  rsTyChartTypeMap = 'Map';
  rsTyChartTypeParallel = 'Parallel coordinate map';
  rsTyChartTypeLines = 'Line graph';
  rsTyChartTypeGraph = 'Relationship graph';
  rsTyChartTypeSankey = 'Sankey diagram';
  rsTyChartTypeFunnel = 'Funnel chart';
  rsTyChartTypeGauge = 'Gauge';
  rsTyChartTypePictorialBar = 'Pictorial bar';
  rsTyChartTypeThemeRiver = 'Theme River Map';
  rsTyChartTypeSunburst = 'Sunburst';
  rsTyChartTypeCustom = 'Custom chart';
  // Also what a screen reader calls a chart that has no title [Batch 144;
  // one string since Milestone D9-D14, not a second 'Chart'].
  rsTyChartTypeChart = 'Chart';
  // [F5] the accessible tree's chart components: their names, a dataZoom's
  // window (two percents) and a brush's areas as values
  rsTyChartAccBrush = 'Brush';
  rsTyChartAccBrushAreas = '%d selected areas';
  rsTyChartAccDataZoom = 'Data zoom';
  rsTyChartAccHandleEnd = 'End handle';
  rsTyChartAccHandleStart = 'Start handle';
  rsTyChartAccLegend = 'Legend';
  rsTyChartAccMarkArea = 'Mark area';
  rsTyChartAccMarkLine = 'Mark line';
  rsTyChartAccMarkPoint = 'Mark point';
  rsTyChartAccMarkers = 'Markers';
  rsTyChartAccPercentRange = '%s%% to %s%%';
  rsTyChartAccTimeline = 'Timeline';
  rsTyChartAccToolbox = 'Toolbox';
  rsTyChartAccVisualMap = 'Visual map';

  // --- AdvanceChart: what the build could not honour ---
  // These reach the user through the chart's diagnostics list and through the
  // design-time editor, so they are as translatable as any caption. They were
  // English literals inside the builder until 2026-09-03.
  rsTyChartAxisTypeUnknown =
    '%s[%d].type: "%s" is not one of value, category, time or log; treated as value';
  rsTyChartAxisWithoutPair =
    'xAxis or yAxis without the other: no grid was created, so neither is drawn';
  rsTyChartXAxisNoGrid = 'xAxis[%d] names no grid, so it is not drawn';
  rsTyChartYAxisNoGrid = 'yAxis[%d] names no grid, so it is not drawn';
  rsTyChartGridOneDirection =
    'grid[%d] has axes in only one direction, so it draws nothing';
  rsTyChartPolarNoAxis = 'polar[%d] has no %s, so it is not drawn';
  rsTyChartSeriesNoType = 'series[%d] has no type, so it is not drawn';
  rsTyChartSeriesBadType = 'series[%d]: "%s" is not a series type';
  rsTyChartSeriesCoordSys = 'series[%d]: coordinateSystem "%s" is not built yet';
  rsTyChartSeriesNoRenderer = 'series[%d]: the "%s" series type is not drawn yet';
  { [spec 259] %d the series, %s the value coordinate, %d the places its
    encode list reaches, %d the places the type needs, %s the type }
  rsTyChartSeriesShortEncode =
    'series[%d]: encode.%s reaches %d of the %d dimensions a %s needs, so it is not drawn';
  rsTyChartCustomNoRenderItem =
    'series[%d]: no renderItem is registered as "%s", so nothing is drawn';
  rsTyChartCustomRenderItemFailed = 'series[%d]: renderItem "%s" failed: %s';
  { %s the component ('geo[0]', 'series[2]'), %s the map name it asks for
    [F1b] }
  rsTyChartMapNotRegistered =
    '%s: no map is registered as "%s", so nothing is drawn';
  rsTyChartSeriesNoAxis = 'series[%d] names an axis that does not exist';
  rsTyChartSeriesAxesSplit =
    'series[%d]: xAxis[%d] and yAxis[%d] are not on one grid';
  // --- AdvanceChart: dataset transforms [Batch 133] ---
  // Why a dataset has no table: the chart's diagnostics say
  // rsTyChartDatasetNoTable with one of the reasons below.  Upstream
  // throws out of setOption instead.
  rsTyChartDatasetNoTable = 'dataset[%d] has no table: %s';
  rsTyDsReadsItself = 'it reads itself';
  rsTyDsUpstreamFailed = 'dataset[%d], which it reads, has no table';
  rsTyDsNoResult = 'its upstream has no result %s';
  rsTyDsOneUpstream = 'fromTransformResult needs exactly one upstream dataset';
  rsTyDsEmptyPipe = 'the transform list is empty';
  rsTyDsNotObject = 'a transform is not an object';
  rsTyDsUnknownType = 'no transform is registered as "%s"';
  rsTyDsUpstreamMissing = 'a transform has no input';
  rsTyDsUpstreamByRow = 'its upstream is laid out by row';
  rsTyDsUpstreamFormat = 'its upstream is not a table';
  rsTyDsDuplicateDim = 'the dimension name "%s" is used twice';
  rsTyDsCopyHasNoMeta =
    'it reads a fromTransformResult copy, which has no dimensions to pass on';
  rsTyDsBadResult = 'a transform result is not a table of arrays or of objects';
  rsTyDsNotSupported =
    '%s is not available to a transform registered outside ECharts';
  rsTyDsKeyedNoDims = 'its upstream table of columns has no dimensions';
  rsTyDsRowNotList = 'a row of the table is not a list';
  rsTyDsCondNotObject = 'a filter condition is not an object';
  rsTyDsCondAndOr = '"%s" must be a non-empty list of conditions';
  rsTyDsCondNot = '"not" must be a condition object';
  rsTyDsCondNoDimension = 'a filter condition has no dimension';
  rsTyDsNoDimension = 'there is no dimension %s';
  rsTyDsCondNoOperator = 'a filter condition has no operator';
  rsTyDsCondBadOperator = '"%s" is not a filter operator';
  rsTyDsCondNeedsNumber = '"%s" compares with a number only';
  rsTyDsCondReg = '"reg" is not a regular expression: %s';
  rsTyDsCondRegSlow = 'the regular expression in "reg" runs too long: %s';
  rsTyDsSortEmpty = 'the sort has no config';
  rsTyDsSortNoDimension = 'a sort key has no dimension';
  rsTyDsSortOrder = 'a sort key''s order must be "asc" or "desc"';
  rsTyDsSortIncomparable = '"incomparable" must be "min" or "max"';
  rsTyDsSortParser = '"%s" is not a parser';
  rsTyDsSortFormat = 'the sort reads only a table of arrays or of objects';
  rsTyDsBoxplotRows = 'the boxplot reads only a table of arrays';
  // --- AdvanceChart: ecStat's dataset transforms [Batch 134] ---
  // More reasons for rsTyChartDatasetNoTable: what 'ecStat:regression',
  // 'ecStat:histogram' and 'ecStat:clustering' refuse.
  rsTyStatRegMethod = '"%s" is not a regression method';
  rsTyStatPolyOrder = 'the polynomial order must be a whole number from -1 to %d';
  rsTyStatBinMethod = '"%s" is not a binning method';
  rsTyStatBinLayout = 'the bins cannot be laid out over these values';
  rsTyStatBinPrecision = 'the bins are finer than 20 decimal places';
  rsTyStatTooManyBins = 'more than %d bins';
  rsTyStatClusterCount = '"clusterCount" must be a number of 2 or more';
  rsTyStatClusterIndex = '"outputClusterIndexDimension" is required, as a number';
  rsTyStatNewDim = 'a new dimension must be an index or { name, index }';
  rsTyStatIndexNotNumber = 'the index of a new dimension must be written as a number';
  rsTyStatTooManyClusters = 'more than %d clusters';
  rsTyStatNoSplit = 'no cluster could be split';
  rsTyStatUnassigned = 'a point belongs to no cluster';
  rsTyStatNoConverge = 'k-means did not settle';
  rsTyStatDimHole = 'a dimension of the result is left undefined';
  rsTyStatIndexTooFar = 'a new dimension''s index is past %d';

  // --- AdvanceChart: the option editor's own vocabulary ---
  // Shown in the design-time editor's status line and its completion popup.
  rsTyOptSummaryDefault = 'default %s';
  rsTyOptSummaryRange = 'range %s..%s';
  rsTyOptSummarySince = 'since %s';
  rsTyOptStatusRoot = '(the option root)';
  rsTyOptStatusNeedsType =
    'write a type first -- what is under here depends on which one';
  // What the editor SAYS about a piece of option text.
  rsTyOptDiagUnknown = '%s is not an option ECharts 6.1 knows.';
  rsTyOptDiagDidYouMean = 'Did you mean "%s"?';
  rsTyOptDiagBadEnum = '%s: "%s" is not one of %s.';
  rsTyOptDiagNoType = '%s[%d] has no type yet, so nothing under it can be '
    + 'checked. One of: %s.';
  rsTyOptDiagNothingPaintsYet =
    'The option is understood. Series marks are not painted yet, so this '
    + 'draws its axes and nothing else.';
  // The same all-clear for a chart whose series have no axes -- a pie, a gauge
  // -- where promising axes would be a lie.
  rsTyOptDiagNoMarksAtAll =
    'The option is understood. Series marks are not painted yet, and this '
    + 'chart has no axes, so nothing is drawn.';
  // Every series that resolved has a renderer: there is nothing to warn
  // about, and the row exists only so a valid option is never met with an
  // empty panel.
  rsTyOptDiagAllClear = 'The option is understood.';
  // Some of them do and some do not -- name the ones that will not appear,
  // because "understood" alone would leave the author looking for them.
  rsTyOptDiagSomeNotPainted =
    'The option is understood. Not painted yet: %s.';
  rsTyOptDiagNoSeries =
    'The option is understood. There are no series, so only the axes would '
    + 'draw.';
  rsTyOptDiagMoreRows = 'and %d more like these.';

  // --- AdvanceChart: the design-time series and data editor [Batch 143] ---
  // Said by tyControls.AdvanceChart.SeriesEdit, shown in the series dialog.
  rsTySerEdNotObject = 'The option is not an object, so it has no series to edit.';
  rsTySerEdEmptyLiteral = 'Write a value here, or clear the field to remove the key.';
  rsTySerEdOneValue = 'Write exactly one value here.';
  rsTySerEdNotInteger = '"%s" is not a whole number.';
  rsTySerEdNotBoolean = '"%s" is neither true nor false.';
  rsTySerEdCaption = '%d: %s';
  rsTySerEdCaptionNamed = '%d: %s "%s"';
  rsTySerEdHole = '(empty slot)';
  rsTySerEdNoType = '(no type)';
  rsTySerEdColCategory = '%s category';
  rsTySerEdColName = 'name';
  rsTySerEdColValue = 'value';
  rsTySerEdColDim = 'dim %d';
  rsTySerEdNoteHole = 'This slot holds no object, so there is nothing to edit in it.';
  rsTySerEdNoteNotList = 'This data is not a list; edit it as text.';
  rsTySerEdNoteTree = 'This data is a tree (items have children); edit it as text.';
  rsTySerEdNoteNoData =
    'This series has no data of its own and reads a dataset. Rows '
    + 'added here give it data of its own, which then wins over the '
    + 'dataset.';
  rsTySerEdNoteCategory =
    'Each row is a category of %s. Deleting a row deletes that '
    + 'category, and its value in every series on that axis.';
  rsTySerEdNoteTransform =
    'This dataset is made from another one by a transform; edit '
    + 'the source dataset instead.';
  rsTySerEdNoteDatasetForm = 'This dataset is not a table of rows; edit it as text.';

implementation

end.
