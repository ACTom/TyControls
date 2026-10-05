unit test.themebuilder.parser;
{ ETyCssError.Line / Col (theme builder, phase 1): the parser's error says where it stopped as
  numbers, not only inside its message. The column counts bytes (SynEdit's logical column),
  line breaks are LF, CRLF or a lone CR. An ETyCssError the style model raises itself (a
  failed @import) has no position: 0 / 0. The message text is guarded separately, byte for
  byte, by test.themebuilder.golden. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry;

type
  TTbParserPosTests = class(TTestCase)
  private
    procedure CheckAt(const ALabel, ASource: string; ALine, ACol: Integer);
  published
    procedure TestLfLineBreak;
    procedure TestCrLfLineBreak;
    procedure TestCrLineBreak;
    procedure TestUnknownPseudoClassColumn;
    procedure TestUnterminatedRootAtEof;
    procedure TestImportAfterRule;
    procedure TestRuleInsideMode;
    procedure TestColumnsCountBytes;
    procedure TestCommentAcrossLines;
    procedure TestModelErrorsHaveNoPosition;
  end;

implementation

uses
  tyControls.Css.Parser, tyControls.StyleModel;

procedure TTbParserPosTests.CheckAt(const ALabel, ASource: string; ALine, ACol: Integer);
var
  parser: TTyCssParser;
  sheet: TTyCssStylesheet;
  raised: Boolean;
begin
  raised := False;
  parser := TTyCssParser.Create(ASource);
  try
    try
      sheet := parser.Parse;
      sheet.Free;
    except
      on E: ETyCssError do
      begin
        raised := True;
        AssertEquals(ALabel + ': line', ALine, E.Line);
        AssertEquals(ALabel + ': col', ACol, E.Col);
        { the fields and the message come from the same token }
        AssertTrue(ALabel + ': the message says the same place: ' + E.Message,
          Pos(Format(' at line %d, col %d ', [ALine, ACol]), E.Message) > 0);
      end;
    end;
  finally
    parser.Free;
  end;
  AssertTrue(ALabel + ': the parser rejected it', raised);
end;

procedure TTbParserPosTests.TestLfLineBreak;
begin
  CheckAt('P1', 'TyButton {'#10'  color red;'#10'}', 2, 9);
end;

procedure TTbParserPosTests.TestCrLfLineBreak;
begin
  CheckAt('P2', 'TyButton {'#13#10'  color red;'#13#10'}', 2, 9);
end;

procedure TTbParserPosTests.TestCrLineBreak;
begin
  CheckAt('P3', 'TyButton {'#13'  color red;'#13'}', 2, 9);
end;

procedure TTbParserPosTests.TestUnknownPseudoClassColumn;
begin
  CheckAt('P4', 'TyButton:hover2 { }', 1, 10);
end;

procedure TTbParserPosTests.TestUnterminatedRootAtEof;
begin
  CheckAt('P5', ':root { --a: 1px;', 1, 18);
end;

procedure TTbParserPosTests.TestImportAfterRule;
begin
  CheckAt('P6', 'TyButton { }'#10'@import "a.tycss";', 2, 1);
end;

procedure TTbParserPosTests.TestRuleInsideMode;
begin
  CheckAt('P7', '@mode dark { TyButton { } }', 1, 14);
end;

procedure TTbParserPosTests.TestColumnsCountBytes;
begin
  { the comment holds one Chinese character: three bytes, so 'x' is at byte 20 }
  CheckAt('P8', '/* '#$E4#$B8#$AD' */ TyButton:x {}', 1, 20);
end;

procedure TTbParserPosTests.TestCommentAcrossLines;
begin
  CheckAt('P9', '/* a'#10'b */ TyButton {'#10' color red; }', 3, 8);
end;

procedure TTbParserPosTests.TestModelErrorsHaveNoPosition;
var
  model: TTyStyleModel;
  raised: Boolean;
begin
  raised := False;
  model := TTyStyleModel.Create;
  try
    try
      model.LoadFromCss('@import "definitely_missing.tycss";');
    except
      on E: ETyCssError do
      begin
        raised := True;
        AssertEquals('P10: line', 0, E.Line);
        AssertEquals('P10: col', 0, E.Col);
      end;
    end;
  finally
    model.Free;
  end;
  AssertTrue('P10: the model raised an ETyCssError', raised);
end;

initialization
  RegisterTest(TTbParserPosTests);
end.
