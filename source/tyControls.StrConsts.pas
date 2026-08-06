unit tyControls.StrConsts;

{$mode objfpc}{$H+}

interface

{ Central resourcestring table for the tyControls RUNTIME package — every user-facing
  diagnostic (ThemeLint warnings, CSS parser / value / StyleModel errors). English is the
  msgid; translations live in languages/tycontrols.strconsts.<lang>.po. See
  docs/superpowers/specs/2026-06-25-i18n-design.md. Deep CSS-syntax errors keep an English
  msgid (their .po msgstr == msgid) per spec decision 5. }
resourcestring
  // --- Shell list view: file-size units ---
  // Shown in the Size column. Hard-coded English before, so a translated build showed
  // '1.2 KB' among otherwise translated headers.
  rsTyFileSizeBytes = 'B';
  rsTyFileSizeKB    = 'KB';
  rsTyFileSizeMB    = 'MB';
  rsTyFileSizeGB    = 'GB';
  rsTyFileSizeTB    = 'TB';
  // --- Grid ---
  // Group row caption: %s = the group value, %d = how many rows in it.
  // Used to be hard-coded as '%s  (%d)' inside RenderGroupRow: untranslatable
  // and unconfigurable.
  rsGridGroupRow          = '%s  (%d)';
  { 列头筛选下拉(Excel 式:搜索 + 逐值计数 + 确定/取消)。 }
  rsGridFilterSearchHint  = 'Search';
  rsGridFilterSelectAll   = '(Select all)';
  rsGridFilterBlank       = '(Blanks)';
  rsGridFilterOk          = 'OK';
  rsGridFilterCancel      = 'Cancel';

  // --- ThemeLint warnings (all translated) ---
  rsLintUndefinedVar      = 'undefined variable --%s';
  rsLintMissingAsset      = 'missing asset ''%s''';
  rsLintLowContrast       = 'low contrast on ''%s''';
  rsLintImportTooDeep     = 'import nesting too deep (> %d)';
  rsLintEmptyImportPath   = 'empty @import path';
  rsLintMissingImport     = 'missing @import ''%s''';
  rsLintImportCycle       = '@import cycle ''%s''';
  rsLintUnreadableImport  = 'unreadable @import ''%s''';
  rsLintImportParseError  = 'parse error in @import ''%s'': %s';
  rsLintUnknownProperty   = 'unknown property ''%s''';
  rsLintParseError        = 'parse error: %s';

  // --- CSS parser (rsCssErrorFrame + rsCssImportMustPrecedeRules translated; rest English) ---
  rsCssErrorFrame             = '%s at line %d, col %d (got "%s")';
  rsCssUnexpectedToken        = 'Unexpected token';
  rsCssUnknownPseudoClass     = 'Unknown pseudo-class "%s"';
  rsCssUnterminatedRootBlock  = 'Unterminated :root block';
  rsCssExpectedVariableName   = 'Expected --variable name';
  rsCssUnterminatedRuleBlock  = 'Unterminated rule block';
  rsCssImportMustPrecedeRules = 'An @import must precede all style rules';
  rsCssExpectedPathInUrl      = 'Expected a path inside url() for @import';
  rsCssExpectedPathAfterImport= 'Expected a quoted path or url() after @import';
  rsCssExpectedModeName       = 'Expected a mode name after "@mode"';
  rsCssUnterminatedModeBlock  = 'Unterminated @mode block';
  rsCssExpectedRootInMode     = 'Expected "root" after ":" inside @mode';
  rsCssOnlyRootInMode         = 'Only :root blocks are allowed inside @mode';
  rsCssExpectedAtRuleName     = 'Expected an at-rule name after "@"';
  rsCssUnknownAtRule          = 'Unknown at-rule "@%s"';
  rsCssExpectedRootAfterColon = 'Expected "root" after ":"';
  rsCssExpectedSelectorOrRoot = 'Expected selector or :root';

  // --- CSS value eval (Css.Values) — technical, English msgid ---
  rsCssInvalidColorLiteral  = 'Invalid color literal: %s';
  rsCssInvalidColorLength   = 'Invalid color length: %s';
  rsCssInvalidHexInColor    = 'Invalid hex in color: %s';
  rsCssUndefinedVariable    = 'Undefined variable: --%s';
  rsCssEmptyColorExpression = 'Empty color expression';
  rsCssUnknownColorFunction = 'Unknown color function: %s/%d';
  rsCssCannotEvaluateColor  = 'Cannot evaluate color: %s';

  // --- StyleModel declaration errors (technical, English) + @import errors (translated) ---
  rsSmInvalidPadding            = 'Invalid padding: %s';
  rsSmInvalidLinearGradient     = 'Invalid linear-gradient: %s';
  rsSmBackgroundImageNeedsUrl   = 'background-image needs url(): %s';
  rsSmBackgroundImageNeedsSlice = 'background-image needs slice(): %s';
  rsSmSliceNeeds4Values         = 'slice() needs 4 values: %s';
  rsSmInvalidShadow             = 'Invalid shadow: %s';
  rsSmBorderRadiusNeeds1Or4     = 'border-radius needs 1 or 4 values: %s';
  rsSmImportNestingTooDeep      = '@import nesting too deep (> %d)';
  rsSmImportEmptyPath           = '@import has an empty path';
  rsSmImportTargetNotFound      = '@import target not found: "%s"';
  rsSmImportCycleDetected       = '@import cycle detected: "%s"';

  // --- Message dialogs (button captions + type titles) — user-facing, translated ---
  rsMsgBtnYes          = 'Yes';
  rsMsgBtnNo           = 'No';
  rsMsgBtnOK           = 'OK';
  rsMsgBtnCancel       = 'Cancel';
  rsMsgBtnAbort        = 'Abort';
  rsMsgBtnRetry        = 'Retry';
  rsMsgBtnIgnore       = 'Ignore';
  rsMsgBtnAll          = 'All';
  rsMsgBtnNoToAll      = 'No to All';
  rsMsgBtnYesToAll     = 'Yes to All';
  rsMsgBtnHelp         = 'Help';
  rsMsgBtnClose        = 'Close';
  rsMsgTypeWarning     = 'Warning';
  rsMsgTypeError       = 'Error';
  rsMsgTypeConfirm     = 'Confirm';
  rsMsgTypeInformation = 'Information';

  // --- Dialog window titles — user-facing, translated ---
  rsDlgAboutTitle      = 'About';
  rsDlgSelectPathTitle = 'Select Folder';
  rsDlgColorTitle      = 'Color';
  rsDlgFontTitle       = 'Font';
  rsDlgFindTitle       = 'Find';
  rsDlgReplaceTitle    = 'Replace';

  // --- Input-family dialogs (S2) — user-facing, translated ---
  rsDlgFolderPath      = 'Folder path (type or paste, then Enter)';
  rsDlgNewFolder       = 'New Folder';
  rsDlgNewFolderPrompt = 'Folder name:';
  rsDlgCreateFolderErr = 'Could not create folder: %s';

  // --- Color picker dialog (S3) — section labels, user-facing, translated ---
  rsDlgHex             = 'Hex';
  rsDlgAlpha           = 'Alpha';
  rsDlgPreview         = 'Preview';
  rsDlgBasicColors     = 'Basic colors';

  // --- Font picker dialog (S3) — section labels, user-facing, translated ---
  rsDlgFontFamily      = 'Family';
  rsDlgFontSize        = 'Size';
  rsDlgFontBold        = 'Bold';
  rsDlgFontItalic      = 'Italic';
  rsDlgFontUnderline   = 'Underline';
  rsDlgFontStrike      = 'Strikeout';
  rsDlgFontColor       = 'Color';
  rsDlgFontSample      = 'AaBbYyZz 0123';

  // --- Find/Replace dialog (S4) — user-facing, translated ---
  rsDlgFindWhat        = 'Find what:';
  rsDlgReplaceWith     = 'Replace with:';
  rsDlgMatchCase       = 'Match case';
  rsDlgWholeWord       = 'Whole word';
  rsDlgSearchUp        = 'Search up';
  rsDlgFindNext        = 'Find Next';
  rsDlgReplace         = 'Replace';
  rsDlgReplaceAll      = 'Replace All';

  // --- File dialogs (TTyOpen/Save[Picture/Preview]Dialog) ---
  rsFdOpenTitle      = 'Open';
  rsFdSaveTitle      = 'Save As';
  rsFdBtnOpen        = 'Open';
  rsFdBtnSave        = 'Save';
  rsFdLookIn         = 'Look in:';
  rsFdFileNameLbl    = 'File name:';
  rsFdFileTypeLbl    = 'File type:';
  rsFdUp             = 'Up';
  rsFdOverwritePrompt = 'The file "%s" already exists.'#10'Do you want to replace it?';
  rsFdMustExist      = 'The file "%s" does not exist.';
  rsFdAllFilesFilter = 'All Files (*.*)|*.*';
  rsFdPictureFilter  = 'Images (*.png;*.jpg;*.jpeg;*.bmp;*.gif)|' +
                       '*.png;*.jpg;*.jpeg;*.bmp;*.gif|All Files (*.*)|*.*';
  rsFdCommonFilter   = 'Common Formats (*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.txt;*.md;' +
                       '*.json;*.xml;*.csv;*.log;*.ini)|' +
                       '*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.txt;*.md;*.json;*.xml;*.csv;' +
                       '*.log;*.ini|All Files (*.*)|*.*';
  // --- Preview box ---
  rsPvCannotPreview  = 'Cannot preview this file';

  // --- TTyFormSurface (content host) ---
  rsTySurfacePurpose = 'TTyForm content host — click for details';
  rsTySurfaceDeleted =
    'You just deleted the form''s content host (Surface) — and with it every control it hosted.'#10#10 +
    'Press Ctrl+Z to undo.'#10#10 +
    'If undo does not restore it, close this form WITHOUT saving and reopen it — the Surface is not ' +
    'on the component palette, so it cannot be dropped back.';

  // --- Badge ---
  // What a count past 99 collapses to, shared by TTyButton's built-in badge and the
  // standalone TTyBadge (the only user-visible TEXT the runtime controls draw by
  // themselves). Translatable because the '+' overflow marker is not universal — a
  // locale may want its own affix — but most translations will simply repeat the msgid.
  rsBadgeOverflow = '99+';

  // --- Empty (placeholder) ---
  // TTyEmpty's default message, drawn whenever its Description is left blank. Translatable
  // for the obvious reason: it is a sentence addressed to the user, in their language.
  // The runtime controls draw almost NO text of their own (they draw what the app gives
  // them) — this and rsBadgeOverflow above are the only exceptions, because an empty state
  // has, by definition, no app text to show.
  rsEmptyDescription = 'No data';

  { --- TTyGrid ---------------------------------------------------------------
    网格里唯一会显示给用户的文本:汇总带的聚合前缀、取色对话框标题,
    以及"勾选框认哪些值为真"里的本地化写法(中文表里常见 '是')。 }
  rsGridSumPrefix   = 'Sum ';
  rsGridAvgPrefix   = 'Avg ';
  rsGridMinPrefix   = 'Min ';
  rsGridMaxPrefix   = 'Max ';
  rsGridCountPrefix = 'Count ';
  rsGridPickColor   = 'Select colour';
  { 勾选框判真时额外认的**本地化**词(中文 .po 里是 '是')。内建的 1/true/yes/y
    永远认,不受它影响。

    英文基线**必须非空**,尽管在英文下它是多余的(yes 本来就在内建表里)。
    从前它是 `''`,理由写着"英文不需要额外的词" —— 运行期这条路其实是通的
    (LazUtils 按标识符查条目,不按 msgid,空 msgid 也找得到),
    **但 Lazarus 的提取器会跳过值为空的字符串**:这一条从来没进过
    languages/tyControls.StrConsts.pot,于是任何译者都看不见它,中文那句 '是'
    压根没地方写。空基线在这里不是"省一个词",是"这个功能翻译不了"。
    由 test.i18n 的 TestEveryStrConstsResourcestringIsInThePot 钉住。 }
  rsGridCheckedWord = 'yes';

  { --- TTyToolBarEx ----------------------------------------------------------
    Tooltip on the overflow chevron that appears when the bar is too narrow for all
    its buttons. It was a hardcoded Chinese literal in library code, so an English
    application showed a Chinese tooltip and no catalogue could reach it. }
  rsToolBarMoreCommands = 'More commands';

  { --- TTyUpDown -------------------------------------------------------------
    Raised when a second up-down is pointed at a control another one already drives.
    Two steppers writing one field is not a configuration, it is a fight, and the
    silent version of it is unbearable to debug -- so it is refused out loud, the way
    LCL refuses it (customupdown.inc:380-389). %s = the field's name, %s = the name of
    the up-down that already has it. }
  rsTyUpDownAlreadyAssociated =
    '"%s" is already associated with the up-down "%s".';

  // --- Design-time hints (shown in the IDE designer) ---
  rsTyGraphicControlOnForm =
    'The graphic control "%s" was placed directly on the form.'#10 +
    'Windowless (graphic) controls paint onto the form itself and will be HIDDEN behind the '#10 +
    'content area. Move it into the Surface content container so it stays visible.';

implementation

end.
