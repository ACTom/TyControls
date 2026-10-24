unit test.stylemetric;
{ #98/#99: a control's own StyleOverride sets the theme tokens it reads.

  The layout tokens (--listview-text-margin, --treeview-margin, ...) used to be read only
  from the theme, through ActiveController.Metric, so the one way to change a single
  control's spacing was to change the library. StyleMetric reads a '--' declaration in the
  control's own StyleOverride first, then the theme. The rule under test: the block's '--'
  declarations are variables laid over the theme's (so one may name another, or a theme
  var), only a token the block declares is the block's answer, a value that does not
  evaluate falls back to the theme, and what was read follows the override text and the
  theme. Both base classes carry it, as they carry StyleOverride. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.Button,
  tyControls.TyLabel, tyControls.Css.Complete;

type
  TStyleMetricTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FButton, FOther: TTyButton;
    FLabel: TTyLabel;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestOwnStyleOverrideSetsTheToken;
    procedure TestOnlyThatControlAndThatToken;
    procedure TestTheThemeAnswersWithoutIt;
    procedure TestVarsResolveThroughTheBlockAndTheTheme;
    procedure TestABadValueFallsBackToTheTheme;
    procedure TestTheReadFollowsTheTextAndTheTheme;
    procedure TestTheGraphicTwinReadsItToo;
    procedure TestBlockVarsStyleTheBlock;
    procedure TestTheEditorDoesNotFlagCustomProperties;
  end;

implementation

type
  TButtonAccess = class(TTyButton);

const
  { a token no theme defines, so the theme's answer is the default the caller passes }
  TOK = '--test-style-metric';

procedure TStyleMetricTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FButton := TTyButton.Create(nil);
  FButton.Controller := FCtl;
  FOther := TTyButton.Create(nil);
  FOther.Controller := FCtl;
  FLabel := TTyLabel.Create(nil);
  FLabel.Controller := FCtl;
end;

procedure TStyleMetricTest.TearDown;
begin
  FLabel.Free;
  FOther.Free;
  FButton.Free;
  FCtl.Free;
end;

procedure TStyleMetricTest.TestOwnStyleOverrideSetsTheToken;
begin
  AssertEquals('no override: the theme (here the caller''s default)', 3, FButton.StyleMetric(TOK, 3));
  FButton.StyleOverride := TOK + ': 9px';
  AssertEquals('the control''s own declaration', 9, FButton.StyleMetric(TOK, 3));
  FButton.StyleOverride := TOK + ': 12';
  AssertEquals('a bare number is px too', 12, FButton.StyleMetric(TOK, 3));
end;

procedure TStyleMetricTest.TestOnlyThatControlAndThatToken;
begin
  FButton.StyleOverride := TOK + ': 9px';
  AssertEquals('another control under the same controller keeps the theme', 3,
    FOther.StyleMetric(TOK, 3));
  AssertEquals('another token on the same control keeps the theme', 5,
    FButton.StyleMetric('--test-style-metric-other', 5));
end;

procedure TStyleMetricTest.TestTheThemeAnswersWithoutIt;
begin
  FCtl.StyleOverride := ':root { ' + TOK + ': 11px; }';
  AssertEquals('the theme''s value', 11, FOther.StyleMetric(TOK, 3));
  FButton.StyleOverride := 'border-width: 2px';
  AssertEquals('an override that does not declare the token: still the theme''s', 11,
    FButton.StyleMetric(TOK, 3));
  FButton.StyleOverride := TOK + ': 4px';
  AssertEquals('the control''s own wins over the theme', 4, FButton.StyleMetric(TOK, 3));
end;

procedure TStyleMetricTest.TestVarsResolveThroughTheBlockAndTheTheme;
begin
  FCtl.StyleOverride := ':root { --test-base-gap: 7px; }';
  FButton.StyleOverride := TOK + ': var(--test-base-gap)';
  AssertEquals('a theme var', 7, FButton.StyleMetric(TOK, 3));
  FButton.StyleOverride := '--test-local: 5px; ' + TOK + ': var(--test-local)';
  AssertEquals('a var the block declares itself', 5, FButton.StyleMetric(TOK, 3));
  FButton.StyleOverride := '--test-base-gap: 2px; ' + TOK + ': var(--test-base-gap)';
  AssertEquals('the block''s own var shadows the theme''s', 2, FButton.StyleMetric(TOK, 3));
end;

procedure TStyleMetricTest.TestABadValueFallsBackToTheTheme;
begin
  FCtl.StyleOverride := ':root { ' + TOK + ': 11px; }';
  FButton.StyleOverride := TOK + ': banana';
  AssertEquals('a value that does not evaluate', 11, FButton.StyleMetric(TOK, 3));
  FButton.StyleOverride := TOK + ': var(--test-undefined)';
  AssertEquals('an undefined var', 11, FButton.StyleMetric(TOK, 3));
  FButton.StyleOverride := TOK + ': 9px; {{';
  AssertEquals('a block that does not parse', 11, FButton.StyleMetric(TOK, 3));
end;

procedure TStyleMetricTest.TestTheReadFollowsTheTextAndTheTheme;
begin
  FButton.StyleOverride := TOK + ': 9px';
  AssertEquals(9, FButton.StyleMetric(TOK, 3));
  FButton.StyleOverride := TOK + ': 6px';
  AssertEquals('a new text is read again', 6, FButton.StyleMetric(TOK, 3));
  FCtl.StyleOverride := ':root { --test-root: 6px; }';
  FButton.StyleOverride := TOK + ': var(--test-root)';
  AssertEquals(6, FButton.StyleMetric(TOK, 3));
  FCtl.StyleOverride := ':root { --test-root: 8px; }';
  AssertEquals('a theme change is read again', 8, FButton.StyleMetric(TOK, 3));
  FButton.StyleOverride := TOK + ': banana';
  AssertEquals('the default is part of what was read', 1, FButton.StyleMetric(TOK, 1));
  AssertEquals('...for each default', 3, FButton.StyleMetric(TOK, 3));
  FButton.StyleOverride := '';
  AssertEquals('no override: the theme again', 3, FButton.StyleMetric(TOK, 3));
end;

procedure TStyleMetricTest.TestTheGraphicTwinReadsItToo;
begin
  AssertEquals(3, FLabel.StyleMetric(TOK, 3));
  FLabel.StyleOverride := TOK + ': 9px';
  AssertEquals('TTyGraphicControl', 9, FLabel.StyleMetric(TOK, 3));
  FCtl.StyleOverride := ':root { --test-root: 4px; }';
  FLabel.StyleOverride := TOK + ': var(--test-root)';
  AssertEquals('through a theme var', 4, FLabel.StyleMetric(TOK, 3));
  FCtl.StyleOverride := ':root { --test-root: 7px; }';
  AssertEquals('and again after a theme change', 7, FLabel.StyleMetric(TOK, 3));
end;

procedure TStyleMetricTest.TestBlockVarsStyleTheBlock;
begin
  FButton.StyleOverride := 'border-width: 5px; ' + TOK + ': 9px';
  AssertEquals('a token next to a style property: the property still styles', 5,
    TButtonAccess(FButton).CurrentStyle.BorderWidth);
  AssertEquals('and the token is read', 9, FButton.StyleMetric(TOK, 3));
  FButton.StyleOverride := '--test-w: 6px; border-width: var(--test-w)';
  AssertEquals('a var the block declares styles the block', 6,
    TButtonAccess(FButton).CurrentStyle.BorderWidth);
end;

procedure TStyleMetricTest.TestTheEditorDoesNotFlagCustomProperties;
var
  unknown: string;
begin
  unknown := TyCssUnknownProps(TOK + ': 9px; bordr-width: 1px;');
  AssertTrue('a custom property is not flagged: ' + unknown, Pos(TOK, unknown) = 0);
  AssertTrue('a misspelled property still is', Pos('bordr-width', unknown) > 0);
  AssertEquals('a control-level block with a custom property validates', '',
    TyCssValidate(TOK + ': 9px; border-width: 2px;', False));
end;

initialization
  RegisterTest(TStyleMetricTest);
end.
