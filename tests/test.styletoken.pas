unit test.styletoken;
{ #101: a control's own StyleOverride sets the keyword and colour tokens it reads.

  StyleMetric (#98/#99, test.stylemetric) reads a LENGTH token as a control sees it. The
  tree's lines are chosen by words (--treeview-lines: guides, --treeview-expander:
  plus-minus), a dash list (--treeview-lines-style: 6px 3px) and a colour
  (--treeview-lines-color), so a control also reads a token's TEXT (StyleToken) and a
  token's COLOUR (StyleColor) the same way: a '--' declaration in its own StyleOverride
  first, then the theme, then the caller's default. A value that is only a reference --
  var(--x) or a bare --x -- is followed, through the block's own declarations laid over the
  theme's; a reference that leads nowhere, or a colour that does not evaluate, is the
  theme's answer instead. Both base classes carry them, as they carry StyleOverride. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.Button,
  tyControls.TyLabel, tyControls.Css.Values;

type
  TStyleTokenTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FButton, FOther: TTyButton;
    FLabel: TTyLabel;
    procedure CheckColor(const AMsg: string; AExpected, AActual: TTyColor);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestOwnStyleOverrideSetsTheText;
    procedure TestTheThemeAnswersWithoutIt;
    procedure TestAReferenceIsFollowed;
    procedure TestAReferenceThatLeadsNowhereIsTheThemes;
    procedure TestTheTextIsNotEvaluated;
    procedure TestAColourToken;
    procedure TestAColourThatDoesNotEvaluateIsTheThemes;
    procedure TestTheReadFollowsTheTextAndTheTheme;
    procedure TestTheGraphicTwinReadsThemToo;
  end;

implementation

const
  { tokens no theme defines, so the theme's answer is the default the caller passes }
  TOK = '--test-style-token';
  COL = '--test-style-colour';
  RED: TTyColor = $FFFF0000;
  BLUE: TTyColor = $FF0000FF;
  GREY: TTyColor = $FF808080;

procedure TStyleTokenTest.CheckColor(const AMsg: string; AExpected, AActual: TTyColor);
begin
  AssertEquals(AMsg, IntToHex(AExpected, 8), IntToHex(AActual, 8));
end;

procedure TStyleTokenTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FButton := TTyButton.Create(nil);
  FButton.Controller := FCtl;
  FOther := TTyButton.Create(nil);
  FOther.Controller := FCtl;
  FLabel := TTyLabel.Create(nil);
  FLabel.Controller := FCtl;
end;

procedure TStyleTokenTest.TearDown;
begin
  FLabel.Free;
  FOther.Free;
  FButton.Free;
  FCtl.Free;
end;

procedure TStyleTokenTest.TestOwnStyleOverrideSetsTheText;
begin
  AssertEquals('no override: the theme (here the caller''s default)', 'guides',
    FButton.StyleToken(TOK, 'guides'));
  FButton.StyleOverride := TOK + ': classic';
  AssertEquals('the control''s own declaration', 'classic', FButton.StyleToken(TOK, 'guides'));
  FButton.StyleOverride := TOK + ':   none  ';
  AssertEquals('trimmed', 'none', FButton.StyleToken(TOK, 'guides'));
  AssertEquals('another control under the same controller keeps the theme', 'guides',
    FOther.StyleToken(TOK, 'guides'));
  AssertEquals('another token on the same control keeps the theme', 'x',
    FButton.StyleToken('--test-style-token-other', 'x'));
end;

procedure TStyleTokenTest.TestTheThemeAnswersWithoutIt;
begin
  FCtl.StyleOverride := ':root { ' + TOK + ': dotted; }';
  AssertEquals('the theme''s value', 'dotted', FOther.StyleToken(TOK, 'solid'));
  FButton.StyleOverride := 'border-width: 2px';
  AssertEquals('an override that does not declare the token: still the theme''s', 'dotted',
    FButton.StyleToken(TOK, 'solid'));
  FButton.StyleOverride := TOK + ': dashed';
  AssertEquals('the control''s own wins over the theme', 'dashed', FButton.StyleToken(TOK, 'solid'));
end;

procedure TStyleTokenTest.TestAReferenceIsFollowed;
begin
  FCtl.StyleOverride := ':root { --test-lines: guides; }';
  FButton.StyleOverride := TOK + ': var(--test-lines)';
  AssertEquals('var() to a theme var', 'guides', FButton.StyleToken(TOK, 'x'));
  FButton.StyleOverride := TOK + ': --test-lines';
  AssertEquals('a bare --name too', 'guides', FButton.StyleToken(TOK, 'x'));
  FButton.StyleOverride := '--test-local: none; ' + TOK + ': var(--test-local)';
  AssertEquals('a var the block declares itself', 'none', FButton.StyleToken(TOK, 'x'));
  FButton.StyleOverride := '--test-lines: classic; ' + TOK + ': var(--test-lines)';
  AssertEquals('the block''s own var shadows the theme''s', 'classic', FButton.StyleToken(TOK, 'x'));
  FButton.StyleOverride := '';
  FCtl.StyleOverride := ':root { --test-lines: guides; --test-mid: var(--test-lines); '
    + TOK + ': var(--test-mid); }';
  AssertEquals('the theme''s own value is followed, through more than one step', 'guides',
    FButton.StyleToken(TOK, 'x'));
end;

procedure TStyleTokenTest.TestAReferenceThatLeadsNowhereIsTheThemes;
begin
  FCtl.StyleOverride := ':root { ' + TOK + ': dotted; }';
  FButton.StyleOverride := TOK + ': var(--test-undefined)';
  AssertEquals('an undefined var: the theme''s', 'dotted', FButton.StyleToken(TOK, 'solid'));
  FButton.StyleOverride := TOK + ': var(--test-a); --test-a: var(--test-b); --test-b: var(--test-a)';
  AssertEquals('a cycle: the theme''s', 'dotted', FButton.StyleToken(TOK, 'solid'));
  FButton.StyleOverride := TOK + ': dashed; {{';
  AssertEquals('a block that does not parse: the theme''s', 'dotted', FButton.StyleToken(TOK, 'solid'));
  FCtl.StyleOverride := ':root { ' + TOK + ': var(--test-undefined); }';
  FButton.StyleOverride := '';
  AssertEquals('a theme value that leads nowhere: the default', 'solid', FButton.StyleToken(TOK, 'solid'));
end;

procedure TStyleTokenTest.TestTheTextIsNotEvaluated;
begin
  FButton.StyleOverride := TOK + ': 6px 3px';
  AssertEquals('a list stays as written', '6px 3px', FButton.StyleToken(TOK, 'solid'));
  FCtl.StyleOverride := ':root { --test-dash: 6px; }';
  FButton.StyleOverride := TOK + ': var(--test-dash) 2px';
  AssertEquals('only a value that is nothing BUT a reference is followed', 'var(--test-dash) 2px',
    FButton.StyleToken(TOK, 'solid'));
  FButton.StyleOverride := TOK + ': var(--test-dash) var(--test-dash)';
  AssertEquals('two references are a list too', 'var(--test-dash) var(--test-dash)',
    FButton.StyleToken(TOK, 'solid'));
end;

procedure TStyleTokenTest.TestAColourToken;
begin
  CheckColor('no override: the theme (here the caller''s default)', GREY, FButton.StyleColor(COL, GREY));
  FButton.StyleOverride := COL + ': #ff0000';
  CheckColor('the control''s own declaration', RED, FButton.StyleColor(COL, GREY));
  CheckColor('another control keeps the theme', GREY, FOther.StyleColor(COL, GREY));
  FCtl.StyleOverride := ':root { --test-c: #0000ff; }';
  FButton.StyleOverride := COL + ': var(--test-c)';
  CheckColor('through a theme var', BLUE, FButton.StyleColor(COL, GREY));
  FButton.StyleOverride := '--test-c: #ff0000; ' + COL + ': var(--test-c)';
  CheckColor('the block''s own var shadows the theme''s', RED, FButton.StyleColor(COL, GREY));
  FButton.StyleOverride := COL + ': alpha(var(--test-c), 0.5)';
  CheckColor('a colour function, against the vars', TyEvalColor('alpha(#0000ff, 0.5)', nil),
    FButton.StyleColor(COL, GREY));
  FButton.StyleOverride := '';
  FCtl.StyleOverride := ':root { ' + COL + ': #0000ff; }';
  CheckColor('the theme''s value', BLUE, FButton.StyleColor(COL, GREY));
end;

procedure TStyleTokenTest.TestAColourThatDoesNotEvaluateIsTheThemes;
begin
  FCtl.StyleOverride := ':root { ' + COL + ': #0000ff; }';
  FButton.StyleOverride := COL + ': banana';
  CheckColor('not a colour: the theme''s', BLUE, FButton.StyleColor(COL, GREY));
  FButton.StyleOverride := COL + ': var(--test-undefined)';
  CheckColor('an undefined var: the theme''s', BLUE, FButton.StyleColor(COL, GREY));
  FCtl.StyleOverride := ':root { ' + COL + ': banana; }';
  FButton.StyleOverride := '';
  CheckColor('a theme value that is not a colour: the default', GREY, FButton.StyleColor(COL, GREY));
end;

procedure TStyleTokenTest.TestTheReadFollowsTheTextAndTheTheme;
begin
  FButton.StyleOverride := TOK + ': classic';
  AssertEquals('classic', FButton.StyleToken(TOK, 'x'));
  FButton.StyleOverride := TOK + ': none';
  AssertEquals('a new text is read again', 'none', FButton.StyleToken(TOK, 'x'));
  FCtl.StyleOverride := ':root { --test-root: guides; }';
  FButton.StyleOverride := TOK + ': var(--test-root)';
  AssertEquals('guides', FButton.StyleToken(TOK, 'x'));
  FCtl.StyleOverride := ':root { --test-root: classic; }';
  AssertEquals('a theme change is read again', 'classic', FButton.StyleToken(TOK, 'x'));
  FCtl.StyleOverride := ':root { --test-root: #ff0000; }';
  FButton.StyleOverride := COL + ': var(--test-root)';
  CheckColor('a colour through a theme var', RED, FButton.StyleColor(COL, GREY));
  FCtl.StyleOverride := ':root { --test-root: #0000ff; }';
  CheckColor('a colour after a theme change too', BLUE, FButton.StyleColor(COL, GREY));
end;

procedure TStyleTokenTest.TestTheGraphicTwinReadsThemToo;
begin
  AssertEquals('x', FLabel.StyleToken(TOK, 'x'));
  FLabel.StyleOverride := TOK + ': classic; ' + COL + ': #ff0000';
  AssertEquals('TTyGraphicControl: the text', 'classic', FLabel.StyleToken(TOK, 'x'));
  CheckColor('TTyGraphicControl: the colour', RED, FLabel.StyleColor(COL, GREY));
  FCtl.StyleOverride := ':root { --test-root: dotted; }';
  FLabel.StyleOverride := TOK + ': var(--test-root)';
  AssertEquals('through a theme var', 'dotted', FLabel.StyleToken(TOK, 'x'));
end;

initialization
  RegisterTest(TStyleTokenTest);
end.
