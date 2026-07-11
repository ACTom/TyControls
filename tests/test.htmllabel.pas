unit test.htmllabel;

{ Headless tests for the ONLY headless-testable seam of TTyHtmlLabel: the pure parser

    function TyHtmlParse(const AHtml: string): TTyHtmlRunArray;

  The windowed control (paint / link hit-testing) is real-machine; every rule here is
  pinned against the pure function alone. }

{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Graphics, fpcunit, testregistry, tyControls.HtmlLabel;
type
  TTyHtmlLabelTest = class(TTestCase)
  private
    { The concatenated visible text of every non-linebreak run. }
    function AllText(const R: TTyHtmlRunArray): string;
    function LineBreaks(const R: TTyHtmlRunArray): Integer;
  published
    procedure TestPlainRunsWithBold;
    procedure TestNestedBoldItalic;
    procedure TestAnchorHref;
    procedure TestBrIsLineBreak;
    procedure TestEntitiesDecode;
    procedure TestFontColorRed;
    procedure TestFontSize;
    procedure TestFontSizeSelfClosing;
    procedure TestUnderlineStrikeItalic;
    procedure TestCloseFontRestoresPrevious;
    procedure TestMalformedNeverCrashes;
    procedure TestStrayCloseNoUnderflow;
  end;

implementation

function TTyHtmlLabelTest.AllText(const R: TTyHtmlRunArray): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to High(R) do
    if not R[i].LineBreak then
      Result := Result + R[i].Text;
end;

function TTyHtmlLabelTest.LineBreaks(const R: TTyHtmlRunArray): Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to High(R) do
    if R[i].LineBreak then Inc(Result);
end;

{ 'a<b>b</b>c' -> three runs a/b/c, only the middle Bold. }
procedure TTyHtmlLabelTest.TestPlainRunsWithBold;
var r: TTyHtmlRunArray;
begin
  r := TyHtmlParse('a<b>b</b>c');
  AssertEquals('three runs', 3, Length(r));
  AssertEquals('run 0 text', 'a', r[0].Text);
  AssertFalse('run 0 not bold', r[0].Bold);
  AssertEquals('run 1 text', 'b', r[1].Text);
  AssertTrue('run 1 bold', r[1].Bold);
  AssertEquals('run 2 text', 'c', r[2].Text);
  AssertFalse('run 2 not bold', r[2].Bold);
end;

{ '<b><i>x</i></b>' -> x is Bold AND Italic. }
procedure TTyHtmlLabelTest.TestNestedBoldItalic;
var r: TTyHtmlRunArray;
begin
  r := TyHtmlParse('<b><i>x</i></b>');
  AssertEquals('all text', 'x', AllText(r));
  AssertTrue('bold', r[0].Bold);
  AssertTrue('italic', r[0].Italic);
end;

{ '<a href="http://x">t</a>' -> run t carries Href. }
procedure TTyHtmlLabelTest.TestAnchorHref;
var r: TTyHtmlRunArray;
begin
  r := TyHtmlParse('<a href="http://x">t</a>');
  AssertEquals('all text', 't', AllText(r));
  AssertEquals('href', 'http://x', r[0].Href);
end;

{ '<br>' produces one LineBreak run between the two text runs. }
procedure TTyHtmlLabelTest.TestBrIsLineBreak;
var r: TTyHtmlRunArray;
begin
  r := TyHtmlParse('a<br>b');
  AssertEquals('one line break', 1, LineBreaks(r));
  AssertEquals('text across the break', 'ab', AllText(r));
end;

{ Entities decode. }
procedure TTyHtmlLabelTest.TestEntitiesDecode;
var r: TTyHtmlRunArray; t: string;
begin
  r := TyHtmlParse('&lt;&gt;&amp;&quot;');
  t := AllText(r);
  AssertEquals('lt/gt/amp/quot decoded', '<>&"', t);
  { &nbsp; must not be left literal (it decodes to a non-'&' whitespace char). }
  r := TyHtmlParse('&nbsp;');
  t := AllText(r);
  AssertTrue('nbsp decoded (not literal &)', (t <> '') and (Pos('&', t) = 0));
end;

{ '<font color=#ff0000>r</font>' -> HasColor + pure red. }
procedure TTyHtmlLabelTest.TestFontColorRed;
var r: TTyHtmlRunArray; c: TColor;
begin
  r := TyHtmlParse('<font color=#ff0000>r</font>');
  AssertEquals('all text', 'r', AllText(r));
  AssertTrue('has colour', r[0].HasColor);
  c := r[0].Color;
  AssertEquals('red 255',   255, Red(c));
  AssertEquals('green 0',     0, Green(c));
  AssertEquals('blue 0',      0, Blue(c));
end;

{ '<font size=14>x</font>' -> SizePt = 14. }
procedure TTyHtmlLabelTest.TestFontSize;
var r: TTyHtmlRunArray;
begin
  r := TyHtmlParse('<font size=14>x</font>');
  AssertEquals('all text', 'x', AllText(r));
  AssertEquals('size 14', 14, r[0].SizePt);
end;

{ '<font size=14/>x' -- a self-closing tag with a bare value must still yield SizePt=14
  (the trailing '/' is not swallowed into the value). }
procedure TTyHtmlLabelTest.TestFontSizeSelfClosing;
var r: TTyHtmlRunArray; i, found: Integer;
begin
  r := TyHtmlParse('<font size=14/>x');
  found := -1;
  for i := 0 to High(r) do
    if r[i].SizePt = 14 then found := i;
  AssertTrue('a run carries size 14 despite the self-closing slash', found >= 0);
end;

{ '<u>/<s>/<i>' set Underline / Strike / Italic. }
procedure TTyHtmlLabelTest.TestUnderlineStrikeItalic;
var r: TTyHtmlRunArray;
begin
  r := TyHtmlParse('<u>x</u>');  AssertTrue('underline', r[0].Underline);
  r := TyHtmlParse('<s>x</s>');  AssertTrue('strike',    r[0].Strike);
  r := TyHtmlParse('<i>x</i>');  AssertTrue('italic',    r[0].Italic);
end;

{ A close-font restores the PREVIOUS colour, not the base: outer red, inner blue, then
  text after </font> is red again. }
procedure TTyHtmlLabelTest.TestCloseFontRestoresPrevious;
var r: TTyHtmlRunArray; i: Integer; sawRedAfter: Boolean;
begin
  r := TyHtmlParse('<font color=#ff0000>a<font color=#0000ff>b</font>c</font>');
  { the run with text 'c' must be red again (previous colour restored) }
  sawRedAfter := False;
  for i := 0 to High(r) do
    if (r[i].Text = 'c') and r[i].HasColor
       and (Red(r[i].Color) = 255) and (Blue(r[i].Color) = 0) then
      sawRedAfter := True;
  AssertTrue('close-font restores the previous (red) colour', sawRedAfter);
end;

{ Malformed / unknown / stray markup never raises and preserves the visible text. }
procedure TTyHtmlLabelTest.TestMalformedNeverCrashes;
begin
  AssertEquals('unclosed bold', 'x', AllText(TyHtmlParse('<b>x')));
  AssertEquals('unknown tag', 'y', AllText(TyHtmlParse('<unknown>y</unknown>')));
  AssertTrue('stray < kept literal', Pos('<', AllText(TyHtmlParse('a < b'))) > 0);
  AssertEquals('empty string', 0, Length(TyHtmlParse('')));
  { a tag open at EOF must not raise }
  AssertTrue('tag at eof', AllText(TyHtmlParse('abc<b')) <> '');
end;

{ A stray close tag with nothing open must not underflow the style stack. }
procedure TTyHtmlLabelTest.TestStrayCloseNoUnderflow;
var r: TTyHtmlRunArray;
begin
  r := TyHtmlParse('</b>x');
  AssertEquals('stray close ignored, text kept', 'x', AllText(r));
  AssertFalse('not spuriously bold', r[High(r)].Bold);
end;

initialization
  RegisterTest(TTyHtmlLabelTest);
end.
