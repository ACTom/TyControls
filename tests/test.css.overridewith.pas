unit test.css.overridewith;
{$mode objfpc}{$H+}

{ #226. TyOverrideWith rewrites ONE declaration of a StyleOverride fragment -- sets it, adds
  it, or takes it out -- and hands back everything else as it was written. A property that
  is a view of a token (TTyTabCloseButton) writes through it, so what the form's author
  typed beside that token must come back byte for byte. TyOverrideDeclared reads the text a
  fragment declares for a name, as written. }

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Css.Parser;

type
  TOverrideWithTest = class(TTestCase)
  published
    { adding }
    procedure AnEmptyOverrideBecomesTheOneDeclaration;
    procedure ABlankOverrideBecomesTheOneDeclaration;
    procedure ANewDeclarationGoesAfterTheLastOne;
    procedure ANewDeclarationClosesAnOpenLastOne;
    procedure InAMultiLineOverrideTheNewDeclarationTakesItsOwnLine;
    procedure TheNewLineIsTheOverridesOwnKindOfLineBreak;
    { replacing }
    procedure TheValueIsReplacedWhereTheDeclarationStands;
    procedure TheRestComesBackByteForByte;
    procedure TheLastOfTwoDeclarationsIsTheOneThatCounts;
    procedure TheValueItAlreadyHasChangesNothing;
    procedure ANameInAnotherCaseIsTheSameName;
    procedure ALongerNameIsAnotherName;
    procedure AnOrdinaryPropertyOfThatSpellingIsAnotherName;
    { what is not a separator }
    procedure ASemicolonInAStringSeparatesNothing;
    procedure ASemicolonInParenthesesSeparatesNothing;
    procedure ASemicolonInACommentSeparatesNothing;
    procedure ADeclarationInsideACommentIsNotOne;
    procedure ADeclarationAfterASemicolonInsideACommentIsNotOne;
    procedure AWordWithoutAColonIsNoDeclaration;
    { removing }
    procedure AnEmptyValueTakesTheDeclarationOut;
    procedure TakingOutTheOnlyDeclarationLeavesNothing;
    procedure TakingOutTheFirstLeavesNoLeadingBlank;
    procedure BlanksBeforeAnotherFirstDeclarationStay;
    procedure TakingOutTheLastOpenOneLeavesTheRestClosed;
    procedure EveryDeclarationOfTheNameGoes;
    procedure ACommentBeforeTheDeclarationStays;
    procedure TakingOutWhatIsNotThereChangesNothing;
    procedure InAMultiLineOverrideTheLineGoesWithItsDeclaration;
    { reading }
    procedure TheDeclaredTextIsReadAsWritten;
    procedure WhatIsNotDeclaredIsNotRead;
    procedure OfTwoDeclarationsTheLastIsRead;
    { round trips }
    procedure SetThenRemoveGivesBackTheOverride;
    procedure TheResultStillParses;
  end;

implementation

const
  N = '--tab-close-show';

procedure TOverrideWithTest.AnEmptyOverrideBecomesTheOneDeclaration;
begin
  AssertEquals('--tab-close-show: active;', TyOverrideWith('', N, 'active'));
end;

procedure TOverrideWithTest.ABlankOverrideBecomesTheOneDeclaration;
begin
  AssertEquals('--tab-close-show: active;', TyOverrideWith('   ', N, 'active'));
end;

procedure TOverrideWithTest.ANewDeclarationGoesAfterTheLastOne;
begin
  AssertEquals('color: #FF0000; --tab-close-show: active;',
    TyOverrideWith('color: #FF0000;', N, 'active'));
end;

procedure TOverrideWithTest.ANewDeclarationClosesAnOpenLastOne;
begin
  AssertEquals('color: #FF0000; --tab-close-show: active;',
    TyOverrideWith('color: #FF0000', N, 'active'));
  AssertEquals('trailing blanks of an open declaration are not kept before its semicolon',
    'color: #FF0000; --tab-close-show: active;',
    TyOverrideWith('color: #FF0000  ', N, 'active'));
end;

procedure TOverrideWithTest.InAMultiLineOverrideTheNewDeclarationTakesItsOwnLine;
begin
  AssertEquals('color: #FF0000;'#10'padding: 2px;'#10'--tab-close-show: active;'#10,
    TyOverrideWith('color: #FF0000;'#10'padding: 2px;'#10, N, 'active'));
  AssertEquals('an override that ends without a line break ends without one',
    'color: #FF0000;'#10'padding: 2px;'#10'--tab-close-show: active;',
    TyOverrideWith('color: #FF0000;'#10'padding: 2px;', N, 'active'));
end;

procedure TOverrideWithTest.TheNewLineIsTheOverridesOwnKindOfLineBreak;
begin
  AssertEquals('color: #FF0000;'#13#10'padding: 2px;'#13#10'--tab-close-show: active;'#13#10,
    TyOverrideWith('color: #FF0000;'#13#10'padding: 2px;'#13#10, N, 'active'));
end;

procedure TOverrideWithTest.TheValueIsReplacedWhereTheDeclarationStands;
begin
  AssertEquals('color: #FF0000; --tab-close-show: hover; padding: 2px;',
    TyOverrideWith('color: #FF0000; --tab-close-show: active; padding: 2px;', N, 'hover'));
end;

procedure TOverrideWithTest.TheRestComesBackByteForByte;
const
  Before = '  color:#FF0000 ;'#9'/* why */ background : url("a;b") ;';
  After  = '  PADDING:2PX;;  border-radius:  var( --r ) ';
begin
  AssertEquals(Before + ' --tab-close-show: hover;' + After,
    TyOverrideWith(Before + ' --tab-close-show:active;' + After, N, 'hover'));
end;

procedure TOverrideWithTest.TheLastOfTwoDeclarationsIsTheOneThatCounts;
begin
  AssertEquals('the engine reads the last one, so that is the one rewritten',
    '--tab-close-show: active; color: #FF0000; --tab-close-show: always;',
    TyOverrideWith('--tab-close-show: active; color: #FF0000; --tab-close-show: hover;', N, 'always'));
end;

procedure TOverrideWithTest.TheValueItAlreadyHasChangesNothing;
const
  S = 'color: #FF0000; --tab-close-show:active ; padding: 2px';
begin
  AssertEquals('not even its spacing', S, TyOverrideWith(S, N, 'active'));
end;

procedure TOverrideWithTest.ANameInAnotherCaseIsTheSameName;
begin
  AssertEquals('the engine matches names without case; the spelling stays the author''s',
    '--Tab-Close-SHOW: hover;',
    TyOverrideWith('--Tab-Close-SHOW: active;', N, 'hover'));
  AssertEquals('', TyOverrideWith('--Tab-Close-SHOW: active;', N, ''));
end;

procedure TOverrideWithTest.ALongerNameIsAnotherName;
begin
  AssertEquals('--tab-close-show-all: 1; --tab-close-show: hover;',
    TyOverrideWith('--tab-close-show-all: 1;', N, 'hover'));
  AssertEquals('--x--tab-close-show: 1; --tab-close-show: hover;',
    TyOverrideWith('--x--tab-close-show: 1;', N, 'hover'));
end;

procedure TOverrideWithTest.AnOrdinaryPropertyOfThatSpellingIsAnotherName;
begin
  AssertEquals('color: #FF0000; --color: #00FF00;',
    TyOverrideWith('color: #FF0000;', '--color', '#00FF00'));
  AssertEquals('color: #FF0000;', TyOverrideWith('color: #FF0000;', '--color', ''));
end;

procedure TOverrideWithTest.ASemicolonInAStringSeparatesNothing;
begin
  AssertEquals('--glyph-close: "a; --tab-close-show: active;"; --tab-close-show: hover;',
    TyOverrideWith('--glyph-close: "a; --tab-close-show: active;";', N, 'hover'));
  AssertEquals('--glyph-close: ''a; --tab-close-show: active;''; --tab-close-show: hover;',
    TyOverrideWith('--glyph-close: ''a; --tab-close-show: active;'';', N, 'hover'));
end;

procedure TOverrideWithTest.ASemicolonInParenthesesSeparatesNothing;
begin
  AssertEquals('background: url(a; --tab-close-show: active;); --tab-close-show: hover;',
    TyOverrideWith('background: url(a; --tab-close-show: active;);', N, 'hover'));
end;

procedure TOverrideWithTest.ASemicolonInACommentSeparatesNothing;
begin
  AssertEquals('color: /* a; b */ #FF0000; --tab-close-show: hover;',
    TyOverrideWith('color: /* a; b */ #FF0000;', N, 'hover'));
end;

procedure TOverrideWithTest.ADeclarationInsideACommentIsNotOne;
begin
  AssertEquals('/* --tab-close-show: active; */ color: #FF0000; --tab-close-show: hover;',
    TyOverrideWith('/* --tab-close-show: active; */ color: #FF0000;', N, 'hover'));
  AssertEquals('/* --tab-close-show: active; */ color: #FF0000;',
    TyOverrideWith('/* --tab-close-show: active; */ color: #FF0000;', N, ''));
end;

{ The scan has to know it is inside a comment: the ';' after 'old' would otherwise end a
  declaration and the next words would be read as one. }
procedure TOverrideWithTest.ADeclarationAfterASemicolonInsideACommentIsNotOne;
const
  S = 'color: #FF0000; /* old; --tab-close-show: active; */';
var
  v: string;
begin
  AssertEquals('set: added, the comment untouched', S + ' --tab-close-show: hover;',
    TyOverrideWith(S, N, 'hover'));
  AssertEquals('nothing to take out', S, TyOverrideWith(S, N, ''));
  AssertFalse('nothing declared', TyOverrideDeclared(S, N, v));
end;

{ Not tycss, and so not ours to repair: the word stays as its author left it. }
procedure TOverrideWithTest.AWordWithoutAColonIsNoDeclaration;
const
  S = '--tab-close-show; color: #FF0000;';
var
  v: string;
begin
  AssertFalse(TyOverrideDeclared(S, N, v));
  AssertEquals(S, TyOverrideWith(S, N, ''));
  AssertEquals(S + ' --tab-close-show: hover;', TyOverrideWith(S, N, 'hover'));
end;

procedure TOverrideWithTest.AnEmptyValueTakesTheDeclarationOut;
begin
  AssertEquals('color: #FF0000; padding: 2px;',
    TyOverrideWith('color: #FF0000; --tab-close-show: active; padding: 2px;', N, ''));
end;

procedure TOverrideWithTest.TakingOutTheOnlyDeclarationLeavesNothing;
begin
  AssertEquals('', TyOverrideWith('--tab-close-show: active;', N, ''));
  AssertEquals('', TyOverrideWith('  --tab-close-show: active  ', N, ''));
  AssertEquals('', TyOverrideWith(#10'--tab-close-show: active;'#10, N, ''));
end;

procedure TOverrideWithTest.TakingOutTheFirstLeavesNoLeadingBlank;
begin
  AssertEquals('color: #FF0000;',
    TyOverrideWith('--tab-close-show: active; color: #FF0000;', N, ''));
end;

procedure TOverrideWithTest.BlanksBeforeAnotherFirstDeclarationStay;
begin
  AssertEquals(#10'  color: #FF0000;',
    TyOverrideWith(#10'  color: #FF0000; --tab-close-show: active;', N, ''));
  AssertEquals('  /* mine */ color: #FF0000;',
    TyOverrideWith('  /* mine */ --tab-close-show: active; color: #FF0000;', N, ''));
end;

procedure TOverrideWithTest.TakingOutTheLastOpenOneLeavesTheRestClosed;
begin
  AssertEquals('color: #FF0000;',
    TyOverrideWith('color: #FF0000; --tab-close-show: active', N, ''));
end;

procedure TOverrideWithTest.EveryDeclarationOfTheNameGoes;
begin
  AssertEquals('an earlier one left behind would come back to life',
    'color: #FF0000;',
    TyOverrideWith('--tab-close-show: active; color: #FF0000; --TAB-CLOSE-SHOW: hover;', N, ''));
end;

procedure TOverrideWithTest.ACommentBeforeTheDeclarationStays;
begin
  AssertEquals('color: #FF0000; /* tabs */ padding: 2px;',
    TyOverrideWith('color: #FF0000; /* tabs */ --tab-close-show: active; padding: 2px;', N, ''));
end;

procedure TOverrideWithTest.TakingOutWhatIsNotThereChangesNothing;
const
  S = '  color:#FF0000 ; padding : 2px  ';
begin
  AssertEquals(S, TyOverrideWith(S, N, ''));
  AssertEquals('', TyOverrideWith('', N, ''));
end;

procedure TOverrideWithTest.InAMultiLineOverrideTheLineGoesWithItsDeclaration;
begin
  AssertEquals('color: #FF0000;'#10'padding: 2px;'#10,
    TyOverrideWith('color: #FF0000;'#10'--tab-close-show: active;'#10'padding: 2px;'#10, N, ''));
  AssertEquals('color: #FF0000;'#10,
    TyOverrideWith('color: #FF0000;'#10'--tab-close-show: active;'#10, N, ''));
end;

procedure TOverrideWithTest.TheDeclaredTextIsReadAsWritten;
var
  v: string;
begin
  AssertTrue(TyOverrideDeclared('color: #FF0000; --Tab-Close-Color :  #ff000080 ;', '--tab-close-color', v));
  AssertEquals('the value, without the blanks around it', '#ff000080', v);
  AssertTrue(TyOverrideDeclared('--tab-close-color: var(--accent)', '--tab-close-color', v));
  AssertEquals('a reference is read as the reference', 'var(--accent)', v);
end;

procedure TOverrideWithTest.WhatIsNotDeclaredIsNotRead;
var
  v: string;
begin
  v := 'x';
  AssertFalse(TyOverrideDeclared('color: #FF0000; /* --tab-close-show: active; */', N, v));
  AssertEquals('', v);
  AssertFalse(TyOverrideDeclared('', N, v));
  AssertFalse(TyOverrideDeclared('--tab-close-show-all: 1;', N, v));
end;

procedure TOverrideWithTest.OfTwoDeclarationsTheLastIsRead;
var
  v: string;
begin
  AssertTrue(TyOverrideDeclared('--tab-close-show: active; --tab-close-show: hover;', N, v));
  AssertEquals('hover', v);
end;

procedure TOverrideWithTest.SetThenRemoveGivesBackTheOverride;
const
  S1 = 'color: #FF0000; padding: 2px;';
  S2 = 'color: #FF0000;'#13#10'padding: 2px;'#13#10;
  S3 = 'color: #FF0000';
begin
  AssertEquals(S1, TyOverrideWith(TyOverrideWith(S1, N, 'active'), N, ''));
  AssertEquals(S2, TyOverrideWith(TyOverrideWith(S2, N, 'active'), N, ''));
  AssertEquals('an open last declaration comes back closed', S3 + ';',
    TyOverrideWith(TyOverrideWith(S3, N, 'active'), N, ''));
end;

procedure TOverrideWithTest.TheResultStillParses;
var
  decls: TTyCssDeclarationArray;
  s: string;
begin
  s := TyOverrideWith('color: #FF0000; background: #00FF00', N, 'active');
  AssertTrue('the rewritten override parses', TyParseOverride(s, decls));
  AssertEquals(3, Length(decls));
  AssertEquals('--tab-close-show', decls[2].Prop);
  s := TyOverrideWith(s, '--tab-close-color', '#FF0000');
  s := TyOverrideWith(s, N, '');
  AssertTrue(TyParseOverride(s, decls));
  AssertEquals(3, Length(decls));
  AssertEquals('--tab-close-color', decls[2].Prop);
end;

initialization
  RegisterTest(TOverrideWithTest);

end.
