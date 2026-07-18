unit tyControls.StrConsts;

{$mode objfpc}{$H+}

interface

{ Central resourcestring table for the tyControls RUNTIME package — every user-facing
  diagnostic (ThemeLint warnings, CSS parser / value / StyleModel errors). English is the
  msgid; translations live in languages/tycontrols.strconsts.<lang>.po. See
  docs/superpowers/specs/2026-06-25-i18n-design.md. Deep CSS-syntax errors keep an English
  msgid (their .po msgstr == msgid) per spec decision 5. }
resourcestring
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
  { 勾选框判真时额外认这个词(英文基线为空 = 只认 1/true/yes/y;
    中文 .po 里译成 '是')。 }
  rsGridCheckedWord = '';

  // --- Design-time hints (shown in the IDE designer) ---
  rsTyGraphicControlOnForm =
    'The graphic control "%s" was placed directly on the form.'#10 +
    'Windowless (graphic) controls paint onto the form itself and will be HIDDEN behind the '#10 +
    'content area. Move it into the Surface content container so it stays visible.';

implementation

end.
