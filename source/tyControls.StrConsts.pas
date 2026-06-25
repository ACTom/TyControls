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

implementation

end.
