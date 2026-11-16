unit test.richedit.layout;

{ Paragraph layout for TTyRichEdit (tyControls.RichEdit.Layout): line breaking (CJK between
  characters with the kinsoku rules, Latin at spaces, long words cut), font fallback, the wrap
  modes, paragraph and character formatting, the caret and hit-test queries, what a layout
  costs in measure calls (counted on the test device, never timed) and the cache.

  Most tests lay out with TTyRichTestDevice at 96 PPI and a base font of 30 half-points, so
  20 pixels: a Latin letter is 10 wide, a space 5, a CJK character 20, the ascent 16 and the
  descent 4 - every expected number below is worked out from those. The render check and the
  glyph check use the real device. Each test makes and frees its own documents, layouters
  and devices. }

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, Types, Graphics, fpcunit, testregistry, BGRABitmap, BGRABitmapTypes,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.Layout, test.richedit.layoutdevice;

type
  TTyRichLayoutTest = class(TTestCase)
  private
    FDocs: TFPList;
    FLayouts: TFPList;
    FLayouter: TTyRichLayouter;
    FDevice: TTyRichTestDevice;
    FChanges: Integer;
    FEventFont: string;
    procedure DocChanged(Sender: TObject; const AChange: TTyRichChange);
    procedure FallbackEvent(Sender: TObject; const ABaseFont: string; ACode: Cardinal;
      var AFontName: string);
    function NewDoc(const AText: UTF8String): TTyRichDocument;
    function NewLayouter: TTyRichLayouter;
    function Lay(ADoc: TTyRichDocument; AIndex, AWidth: Integer; AZoom: Single = 1): TTyParaLayout;
    procedure SetPara(ADoc: TTyRichDocument; AIndex: Integer; AMask: TTyParaFormatMask;
      const AValue: TTyParaFormat);
    procedure SetChar(ADoc: TTyRichDocument; APos, ALen: TTyRichPos; AMask: TTyCharFormatMask;
      const AValue: TTyCharFormat);
    function LineText(L: TTyParaLayout; ALine: Integer): UTF8String;
    function FragAt(L: TTyParaLayout; APos: Integer): TTyRichFragment;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // the plan's list
    procedure TestCjkBreaksBetweenCharactersButNotBeforeClosingPunctuation;
    procedure TestLatinBreaksAtSpacesAndForcesLongWords;
    procedure TestMissingGlyphFallsBack;
    procedure TestWrapModes;
    procedure TestOnlyVisibleParagraphsAreMeasured;
    procedure TestCacheInvalidatesOnlyTheEditedParagraph;
    procedure TestCaretAndPointAgree;
    // the controller's
    procedure TestTabsAdvanceToExplicitAndDefaultStops;
    procedure TestAlignmentsPlaceALine;
    procedure TestLineAndParagraphSpacing;
    procedure TestVerticalTabForcesALineBreak;
    procedure TestAnInvalidBytePairShowsOneReplacement;
    procedure TestClustersStayOnOneLineInOnePiece;
    procedure TestALongParagraphLaysOutInLinearCalls;
    procedure TestTheCacheIsBoundedByCountAndBySize;
    procedure TestCachedLayoutsFollowInsertedAndDeletedParagraphs;
    procedure TestAHandedOutLayoutOutlivesTheCache;
    procedure TestALayoutKeepsItsObjectAlivePastEviction;
    procedure TestRenderedInkStaysInsideTheMeasuredBoxes;
    procedure TestTheRealDeviceKnowsWhichGlyphsAFontHas;
    procedure TestZoomScalesWidthAndFontAndLeavesTheDocument;
    // mine
    procedure TestAnEmptyParagraphHasOneLineOfItsFont;
    procedure TestSuperscriptShiftsWithoutGrowingTheLineMoreThanItNeeds;
    procedure TestObjectsAreBoxes;
    procedure TestSelectionRectsCoverTheRangeLineByLine;
  end;

implementation

uses
  Math, test.danglingrefs;

const
  MB = 1024 * 1024;

type
  TBuilderAccess = class(TTyRichDocBuilder)
  public
    class function Value(ADoc: TTyRichDocument; AIndex: Integer): Pointer;
  end;

class function TBuilderAccess.Value(ADoc: TTyRichDocument; AIndex: Integer): Pointer;
begin
  Result := ParagraphValue(ADoc, AIndex);
end;

function ByteArray(const A: array of Byte): TBytes;
var
  i: Integer;
begin
  Result := nil;
  SetLength(Result, Length(A));
  for i := 0 to High(A) do Result[i] := A[i];
end;

function BytesOf(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[0], Length(S));
end;

function U(ACode: Cardinal): UTF8String;
var
  b: array[0..3] of Byte;
  n, i: Integer;
begin
  if ACode < $80 then
  begin
    b[0] := ACode;
    n := 1;
  end
  else if ACode < $800 then
  begin
    b[0] := $C0 or (ACode shr 6);
    b[1] := $80 or (ACode and $3F);
    n := 2;
  end
  else if ACode < $10000 then
  begin
    b[0] := $E0 or (ACode shr 12);
    b[1] := $80 or ((ACode shr 6) and $3F);
    b[2] := $80 or (ACode and $3F);
    n := 3;
  end
  else
  begin
    b[0] := $F0 or (ACode shr 18);
    b[1] := $80 or ((ACode shr 12) and $3F);
    b[2] := $80 or ((ACode shr 6) and $3F);
    b[3] := $80 or (ACode and $3F);
    n := 4;
  end;
  Result := '';
  SetLength(Result, n);
  for i := 0 to n - 1 do Result[i + 1] := AnsiChar(b[i]);
end;

{ ---- fixtures ---- }

procedure TTyRichLayoutTest.SetUp;
begin
  FDocs := TFPList.Create;
  FLayouts := TFPList.Create;
  FChanges := 0;
  FEventFont := '';
  FDevice := TTyRichTestDevice.Create;
  FLayouter := TTyRichLayouter.Create(FDevice, True);
  FLayouter.BaseFontName := 'Test';
  FLayouter.BaseFontSizeHalfPt := 30;
end;

procedure TTyRichLayoutTest.TearDown;
var
  i: Integer;
begin
  for i := 0 to FLayouts.Count - 1 do TTyBlockLayout(FLayouts[i]).Release;
  FLayouts.Free;
  FLayouter.Free;
  FLayouter := nil;
  FDevice := nil;
  for i := 0 to FDocs.Count - 1 do TObject(FDocs[i]).Free;
  FDocs.Free;
end;

procedure TTyRichLayoutTest.DocChanged(Sender: TObject; const AChange: TTyRichChange);
begin
  Inc(FChanges);
  if FLayouter <> nil then FLayouter.DocumentChanged(AChange);
end;

procedure TTyRichLayoutTest.FallbackEvent(Sender: TObject; const ABaseFont: string;
  ACode: Cardinal; var AFontName: string);
begin
  AFontName := FEventFont;
end;

function TTyRichLayoutTest.NewDoc(const AText: UTF8String): TTyRichDocument;
begin
  Result := TTyRichDocument.CreateFromUtf8(BytesOf(AText));
  FDocs.Add(Result);
end;

function TTyRichLayoutTest.NewLayouter: TTyRichLayouter;
begin
  Result := TTyRichLayouter.Create(TTyRichTestDevice.Create, True);
  Result.BaseFontName := 'Test';
  Result.BaseFontSizeHalfPt := 30;
end;

function TTyRichLayoutTest.Lay(ADoc: TTyRichDocument; AIndex, AWidth: Integer;
  AZoom: Single): TTyParaLayout;
begin
  Result := FLayouter.LayoutPara(ADoc, AIndex, AWidth, 96, AZoom);
  FLayouts.Add(Result);
end;

procedure TTyRichLayoutTest.SetPara(ADoc: TTyRichDocument; AIndex: Integer;
  AMask: TTyParaFormatMask; const AValue: TTyParaFormat);
begin
  AssertTrue('para format set', ADoc.Execute(TTyRichSetParaFormat.Create(AIndex, AIndex, AMask,
    AValue)));
end;

procedure TTyRichLayoutTest.SetChar(ADoc: TTyRichDocument; APos, ALen: TTyRichPos;
  AMask: TTyCharFormatMask; const AValue: TTyCharFormat);
begin
  AssertTrue('char format set', ADoc.Execute(TTyRichSetCharFormat.Create(TyRichRange(APos, ALen),
    AMask, AValue)));
end;

{ The characters of line ALine, as UTF-8. }
function TTyRichLayoutTest.LineText(L: TTyParaLayout; ALine: Integer): UTF8String;
var
  codes: TCardinalDynArray;
  i: Integer;
  ln: TTyRichLine;
begin
  codes := TestCodes(L.Text);
  ln := L.Lines[ALine];
  Result := '';
  for i := ln.First to ln.First + ln.Count - 1 do Result := Result + U(codes[i]);
end;

function TTyRichLayoutTest.FragAt(L: TTyParaLayout; APos: Integer): TTyRichFragment;
var
  i: Integer;
begin
  for i := 0 to L.FragmentCount - 1 do
    if (APos >= L.Fragments[i].First) and (APos < L.Fragments[i].First + L.Fragments[i].Count) then
      Exit(L.Fragments[i]);
  Fail(Format('no fragment holds position %d', [APos]));
end;

{ ---- the plan's list ---- }

{ A narrow paragraph of Chinese with its punctuation: it breaks between the characters, and
  no line starts with ， or 。 (the kinsoku table). At 50 px (two and a half characters) the
  lines are worked out: 中 / 文， / 标 / 点。 - each punctuation mark stays with the character
  before it, even where that leaves room. }
procedure TTyRichLayoutTest.TestCjkBreaksBetweenCharactersButNotBeforeClosingPunctuation;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  w, i: Integer;
  first: UTF8String;
begin
  d := NewDoc('中文，标点。中文，标点。中文，标点。');
  L := Lay(d, 0, 50);
  AssertTrue('several lines', L.LineCount >= 4);
  AssertEquals('line 1', '中', LineText(L, 0));
  AssertEquals('line 2', '文，', LineText(L, 1));
  AssertEquals('line 3', '标', LineText(L, 2));
  AssertEquals('line 4', '点。', LineText(L, 3));
  for w := 40 to 130 do
  begin
    FLayouter.Clear;
    L := Lay(d, 0, w);
    AssertTrue(Format('more than one line at %d', [w]), L.LineCount > 1);
    for i := 1 to L.LineCount - 1 do
    begin
      first := Copy(LineText(L, i), 1, 3);
      AssertTrue(Format('at %d px line %d starts with %s', [w, i, first]),
        (first <> '，') and (first <> '。'));
    end;
    for i := 0 to L.LineCount - 1 do
      AssertTrue(Format('at %d px line %d fits', [w, i]), L.Lines[i].ContentWidth <= w);
  end;
  // and no line ends with an opening bracket: it goes down with what it opens
  d := NewDoc('中文（中文）中文「中文」中文（中文）中文「中文」');
  for w := 40 to 130 do
  begin
    FLayouter.Clear;
    L := Lay(d, 0, w);
    AssertTrue(Format('more than one line at %d', [w]), L.LineCount > 1);
    for i := 0 to L.LineCount - 2 do
    begin
      first := LineText(L, i);
      first := Copy(first, Length(first) - 2, 3);
      AssertTrue(Format('at %d px line %d ends with %s', [w, i, first]),
        (first <> '（') and (first <> '「'));
      AssertTrue(Format('at %d px line %d starts with a closing bracket', [w, i + 1]),
        (Copy(LineText(L, i + 1), 1, 3) <> '）') and (Copy(LineText(L, i + 1), 1, 3) <> '」'));
    end;
  end;
end;

{ Latin breaks at spaces, the spaces hang past the edge; a word longer than the line is cut at
  the edge; and a word in two formats is still one word: the line goes back to the space
  before it. }
procedure TTyRichLayoutTest.TestLatinBreaksAtSpacesAndForcesLongWords;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  f: TTyCharFormat;
  i: Integer;
begin
  d := NewDoc('hello world foo'#10 + StringOfChar('a', 30) + #10'ab cdefghijklmnop'#10'xx abcdef');
  L := Lay(d, 0, 120);
  AssertEquals('two lines', 2, L.LineCount);
  AssertEquals('first line, its space included', 'hello world ', LineText(L, 0));
  AssertEquals('second', 'foo', LineText(L, 1));
  AssertEquals('the trailing space hangs', 105, L.Lines[0].ContentWidth);
  // a 300 px word at 95 px: nine letters a line
  L := Lay(d, 1, 95);
  AssertEquals('cut in four', 4, L.LineCount);
  for i := 0 to 2 do AssertEquals('nine letters', 9, L.Lines[i].Count);
  AssertEquals('the rest', 3, L.Lines[3].Count);
  for i := 0 to 3 do AssertTrue('each fits', L.Lines[i].ContentWidth <= 95);
  // a short word, then a long one: the long one starts its own line and is cut there
  L := Lay(d, 2, 60);
  AssertEquals('lines', 4, L.LineCount);
  AssertEquals('1', 'ab ', LineText(L, 0));
  AssertEquals('2', 'cdefgh', LineText(L, 1));
  AssertEquals('3', 'ijklmn', LineText(L, 2));
  AssertEquals('4', 'op', LineText(L, 3));
  // "abcdef" with "def" bold: no break at the format change
  f := TyDefaultCharFormat;
  f.Style := [fsBold];
  SetChar(d, d.Text.ParaStart(3) + 6, 3, [cffBold], f);
  L := Lay(d, 3, 70);
  AssertEquals('two lines', 2, L.LineCount);
  AssertEquals('the space ends the first', 'xx ', LineText(L, 0));
  AssertEquals('the word whole', 'abcdef', LineText(L, 1));
end;

{ Chinese in an Arial paragraph: Arial (on the test device) has only ASCII, so the Chinese goes
  to the first candidate that has it; the event names a font of its own; an emoji goes past a
  candidate that lacks it; a character nobody has stays in Arial and keeps its place. }
procedure TTyRichLayoutTest.TestMissingGlyphFallsBack;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  f: TTyCharFormat;
  fr: TTyRichFragment;
  i: Integer;
  plan: TStringList;
begin
  // the plan's lists
  plan := TStringList.Create;
  try
    {$IF DEFINED(MSWINDOWS)}
    plan.CommaText := '"Microsoft YaHei",SimSun,SimSun-ExtB,"Segoe UI Emoji","Segoe UI Symbol"';
    {$ELSEIF DEFINED(DARWIN)}
    plan.CommaText := '"PingFang SC","Hiragino Sans GB","Apple Color Emoji"';
    {$ELSE}
    plan.CommaText := '"Noto Sans CJK SC","WenQuanYi Micro Hei","Noto Color Emoji"';
    {$ENDIF}
    AssertEquals('the platform''s candidates', plan.Text, FLayouter.FallbackFonts.Text);
  finally
    plan.Free;
  end;
  d := NewDoc('ab中文 cd' + U($1F600));
  f := TyDefaultCharFormat;
  f.FontName := 'Arial';
  SetChar(d, 0, d.Text.Length, [cffFontName], f);
  FDevice.SetRepertoire('Arial', [$20, $7E]);
  L := Lay(d, 0, 1000);
  AssertEquals('Latin stays in Arial', 'Arial', FDevice.FontName(FragAt(L, 0).Font));
  fr := FragAt(L, 2);
  AssertTrue('Chinese is not in Arial', FDevice.FontName(fr.Font) <> 'Arial');
  AssertEquals('it is in the first candidate', FLayouter.FallbackFonts[0],
    FDevice.FontName(fr.Font));
  AssertEquals('and the size is the paragraph''s', 20, FDevice.FontPixelHeight(fr.Font));
  AssertEquals('Latin after it is Arial again', 'Arial', FDevice.FontName(FragAt(L, 5).Font));
  // the event first
  FEventFont := 'Event Font';
  FLayouter.OnFallbackFont := @FallbackEvent;
  FLayouter.Clear;
  L := Lay(d, 0, 1000);
  AssertEquals('the event''s font', 'Event Font', FDevice.FontName(FragAt(L, 2).Font));
  FLayouter.OnFallbackFont := nil;
  // an emoji passes a candidate without it
  FDevice.SetRepertoire(FLayouter.FallbackFonts[0], [$4E00, $9FFF]);
  FLayouter.Clear;
  L := Lay(d, 0, 1000);
  AssertEquals('Chinese: the first', FLayouter.FallbackFonts[0], FDevice.FontName(FragAt(L, 2).Font));
  AssertEquals('the emoji: the second', FLayouter.FallbackFonts[1],
    FDevice.FontName(FragAt(L, 7).Font));
  // nobody has it
  for i := 0 to FLayouter.FallbackFonts.Count - 1 do
    FDevice.SetRepertoire(FLayouter.FallbackFonts[i], [$20, $7E]);
  FLayouter.Clear;
  L := Lay(d, 0, 1000);
  AssertEquals('it stays in Arial', 'Arial', FDevice.FontName(FragAt(L, 2).Font));
  AssertEquals('every character is still there', 8, L.Length);
  AssertTrue('and drawn', Pos('中', Copy(L.Text, FragAt(L, 2).ByteStart + 1,
    FragAt(L, 2).ByteLen)) > 0);
end;

{ The same paragraph: at the window's width, at the page's text width, and unwrapped. }
procedure TTyRichLayoutTest.TestWrapModes;
var
  d: TTyRichDocument;
  s: UTF8String;
  i: Integer;
  L: TTyParaLayout;
begin
  s := '';
  for i := 1 to 40 do s := s + 'aaaa ';
  d := NewDoc(s);
  // "aaaa " is 45 px: four words fit 200 px (the fourth's space hangs), a fifth would end at 220
  AssertEquals('window width as given', 200, TyRichLayoutWidth(rwmWindow, 200, d, 96, 1));
  L := Lay(d, 0, TyRichLayoutWidth(rwmWindow, 200, d, 96, 1));
  AssertEquals('window: ten lines', 10, L.LineCount);
  // the page: 12240 - 1800 - 1800 twips = 576 px; twelve words end at 535, a 13th at 580
  AssertEquals('page width', 576, TyRichLayoutWidth(rwmPage, 200, d, 96, 1));
  L := Lay(d, 0, TyRichLayoutWidth(rwmPage, 200, d, 96, 1));
  AssertEquals('page: four lines', 4, L.LineCount);
  AssertEquals('page: twelve words', 60, L.Lines[0].Count);
  AssertEquals('no wrap', CRichNoWrap, TyRichLayoutWidth(rwmNone, 200, d, 96, 1));
  L := Lay(d, 0, TyRichLayoutWidth(rwmNone, 200, d, 96, 1));
  AssertEquals('none: one line', 1, L.LineCount);
  // the page at 200 %: twice the width and twice the font - the same four lines
  AssertEquals('page width zoomed', 1152, TyRichLayoutWidth(rwmPage, 200, d, 96, 2));
  L := Lay(d, 0, TyRichLayoutWidth(rwmPage, 200, d, 96, 2), 2);
  AssertEquals('page zoomed: four lines', 4, L.LineCount);
end;

{ Laying out paragraph 1,000,000 of 2,000,000 measures what laying out the same paragraph
  alone measures - not one call more - and reads the text index along one path. }
procedure TTyRichLayoutTest.TestOnlyVisibleParagraphsAreMeasured;
const
  Paras = 2000000;
  Target = 1000000;
var
  b: TBytes;
  line: RawByteString;
  i, at: Integer;
  big, one: TTyRichDocument;
  L: TTyParaLayout;
  lo: TTyRichLayouter;
  calls, chars, glyphs, visits: Int64;
begin
  b := nil;
  SetLength(b, Paras * 24);
  at := 0;
  for i := 0 to Paras - 1 do
  begin
    line := 'p' + IntToStr(i) + ' 中文 end'#10;
    Move(line[1], b[at], Length(line));
    Inc(at, Length(line));
  end;
  SetLength(b, at - 1);
  big := TTyRichDocument.CreateFromUtf8(b);
  FDocs.Add(big);
  AssertEquals('paragraphs', Paras, big.Text.ParaCount);
  FDevice.ResetCounters;
  big.Text.NodeVisits := 0;
  L := Lay(big, Target, 400);
  calls := FDevice.MeasureCalls;
  chars := FDevice.MeasuredChars;
  glyphs := FDevice.GlyphQueries;
  visits := big.Text.NodeVisits;
  AssertTrue('it measured', calls > 0);
  AssertTrue(Format('index nodes visited: %d', [visits]), visits < 200);
  // the same paragraph alone, on a fresh layouter and device
  one := NewDoc('p' + IntToStr(Target) + ' 中文 end');
  lo := NewLayouter;
  try
    lo.LayoutPara(one, 0, 400, 96, 1).Release;
    AssertEquals('measure calls', TTyRichTestDevice(lo.Device).MeasureCalls, calls);
    AssertEquals('measured characters', TTyRichTestDevice(lo.Device).MeasuredChars, chars);
    AssertEquals('glyph questions', TTyRichTestDevice(lo.Device).GlyphQueries, glyphs);
  finally
    lo.Free;
  end;
  AssertEquals('its text', 'p1000000 中文 end', L.Text);
end;

{ An edit of paragraph 5 (index 4) drops its layout and only its: paragraphs 4 and 6 are
  served from the cache, without measuring. }
procedure TTyRichLayoutTest.TestCacheInvalidatesOnlyTheEditedParagraph;
var
  d: TTyRichDocument;
  i: Integer;
  s: UTF8String;
  L4, L: TTyParaLayout;
  hits, misses, calls: Int64;
begin
  s := '';
  for i := 0 to 9 do s := s + 'paragraph ' + IntToStr(i) + ' 中文'#10;
  d := NewDoc(s);
  d.OnChange := @DocChanged;
  Lay(d, 3, 300);
  L4 := Lay(d, 4, 300);
  Lay(d, 5, 300);
  AssertTrue('typed', d.Execute(TTyRichInsertText.Create(d.Text.ParaStart(4) + 2, 'XYZ')));
  AssertEquals('one change', 1, FChanges);
  AssertTrue('the edited one''s layout is stale', L4.Stale);
  hits := FLayouter.CacheHits;
  misses := FLayouter.CacheMisses;
  calls := FDevice.MeasureCalls;
  L := Lay(d, 3, 300);
  AssertFalse('4 is not stale', L.Stale);
  L := Lay(d, 5, 300);
  AssertEquals('4 and 6 are hits', hits + 2, FLayouter.CacheHits);
  AssertEquals('no miss', misses, FLayouter.CacheMisses);
  AssertEquals('nothing measured', calls, FDevice.MeasureCalls);
  L := Lay(d, 4, 300);
  AssertEquals('5 is a miss', misses + 1, FLayouter.CacheMisses);
  AssertEquals('5 has the edit', 'paXYZragraph 4 中文', L.Text);
end;

{ The caret at every caret place, its middle handed back to PosAtPoint, gives that place -
  on wrapped lines of mixed Latin, CJK, punctuation, a combining sequence and an emoji, left
  aligned and justified. (Bidirectional text is not laid out: spec 6.1.) }
procedure TTyRichLayoutTest.TestCaretAndPointAgree;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  s: UTF8String;
  codes: TCardinalDynArray;
  p, q, al: Integer;
  r: TRect;
  pf: TTyParaFormat;
  checked: Integer;
begin
  s := '';
  for p := 1 to 4 do
    s := s + 'The quick 中文字 brown fox, 标点。 e' + U($301) + ' jumps over ' + U($1F600) +
      ' lazy dog.  ';
  d := NewDoc(s);
  codes := TestCodes(s);
  for al := 0 to 1 do
  begin
    pf := TyDefaultParaFormat;
    if al = 1 then pf.Align := paraJustify;
    SetPara(d, 0, [pffAlign], pf);
    FLayouter.Clear;
    L := Lay(d, 0, 150);
    AssertTrue('wrapped', L.LineCount > 5);
    checked := 0;
    for p := 0 to L.Length do
    begin
      // a place inside a cluster is not a caret place
      if (p < L.Length) and TyRichIsClusterExtend(codes[p]) then Continue;
      r := L.CaretRect(p);
      AssertEquals('one pixel wide', 1, r.Right - r.Left);
      q := L.PosAtPoint((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
      AssertEquals(Format('align %d: position %d (x %d, y %d)', [al, p, r.Left, r.Top]), p, q);
      Inc(checked);
    end;
    AssertTrue('checked them all', checked > 200);
  end;
end;

{ ---- the controller's ---- }

{ Default stops every 720 twips (48 px); explicit stops left, right, centre and decimal; past
  the last explicit stop the defaults again; the leader is on the tab's fragment. }
procedure TTyRichLayoutTest.TestTabsAdvanceToExplicitAndDefaultStops;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  pf: TTyParaFormat;

  procedure Stop(APos: Integer; AAlign: TTyTabAlign; ALeader: TTyTabLeader = ttlNone);
  begin
    SetLength(pf.Tabs, Length(pf.Tabs) + 1);
    pf.Tabs[High(pf.Tabs)].Position := APos;
    pf.Tabs[High(pf.Tabs)].Align := AAlign;
    pf.Tabs[High(pf.Tabs)].Leader := ALeader;
  end;

begin
  d := NewDoc('a'#9'b'#10'aaaaa'#9'b'#10'a'#9'b'#9'c'#10'a'#9'bcd'#10'a'#9'bcd'#10'a'#9'12.5');
  L := Lay(d, 0, 400);
  AssertEquals('default stop', 48, FragAt(L, 2).X);
  AssertEquals('the tab fills to it', 38, FragAt(L, 1).Width);
  L := Lay(d, 1, 400);
  AssertEquals('the next default stop', 96, FragAt(L, 6).X);
  // an explicit left stop at 1440 twips (96 px), then the defaults past it
  pf := TyDefaultParaFormat;
  Stop(1440, ttaLeft);
  SetPara(d, 2, [pffTabs], pf);
  L := Lay(d, 2, 400);
  AssertEquals('explicit stop', 96, FragAt(L, 2).X);
  AssertEquals('a default past the last explicit one', 144, FragAt(L, 4).X);
  // right, centre, decimal at 2880 twips (192 px)
  pf := TyDefaultParaFormat;
  Stop(2880, ttaRight, ttlDot);
  SetPara(d, 3, [pffTabs], pf);
  L := Lay(d, 3, 400);
  AssertEquals('right: the text ends at the stop', 162, FragAt(L, 2).X);
  AssertEquals('the leader', Ord(ttlDot), Ord(FragAt(L, 1).Leader));
  AssertEquals('the tab is a tab', Ord(rfkTab), Ord(FragAt(L, 1).Kind));
  pf := TyDefaultParaFormat;
  Stop(2880, ttaCenter);
  SetPara(d, 4, [pffTabs], pf);
  L := Lay(d, 4, 400);
  AssertEquals('centre: centred on the stop', 177, FragAt(L, 2).X);
  pf := TyDefaultParaFormat;
  Stop(2880, ttaDecimal);
  SetPara(d, 5, [pffTabs], pf);
  L := Lay(d, 5, 400);
  AssertEquals('decimal: the point at the stop', 172, FragAt(L, 2).X);
end;

{ A short line left, centred, right; justified lines stretch their spaces - or, with none,
  the gaps between CJK characters - to the right edge, and the last line does not. }
procedure TTyRichLayoutTest.TestAlignmentsPlaceALine;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  pf: TTyParaFormat;
  fr: TTyRichFragment;
begin
  d := NewDoc('abc'#10'abc'#10'abc'#10'aa bb cc dd ee ff'#10'中文中文中文'#10'abc');
  L := Lay(d, 0, 200);
  AssertEquals('left', 0, L.Fragments[0].X);
  pf := TyDefaultParaFormat;
  pf.Align := paraCenter;
  SetPara(d, 1, [pffAlign], pf);
  L := Lay(d, 1, 200);
  AssertEquals('centre', 85, L.Fragments[0].X);
  pf.Align := paraRight;
  SetPara(d, 2, [pffAlign], pf);
  L := Lay(d, 2, 200);
  AssertEquals('right', 170, L.Fragments[0].X);
  // justified: "aa bb cc dd " is 95 px of content at 100: 5 px over three spaces
  pf.Align := paraJustify;
  SetPara(d, 3, [pffAlign], pf);
  L := Lay(d, 3, 100);
  AssertEquals('lines', 2, L.LineCount);
  fr := FragAt(L, 9);   // the "dd"
  AssertEquals('the last word ends at the edge', 100, fr.X + fr.Width);
  fr := FragAt(L, 15);  // the "ff"
  AssertEquals('the last line is not stretched', 45, fr.X + fr.Width);
  // CJK: four characters (80 px) at 90, 10 px over three gaps
  SetPara(d, 4, [pffAlign], pf);
  L := Lay(d, 4, 90);
  fr := FragAt(L, 3);
  AssertEquals('the fourth character ends at the edge', 90, fr.X + fr.Width);
  AssertEquals('the first stays', 0, FragAt(L, 0).X);
  // the right indent moves the right edge (1500 twips = 100 px)
  pf.Align := paraRight;
  pf.RightIndent := 1500;
  SetPara(d, 5, [pffAlign, pffRightIndent], pf);
  L := Lay(d, 5, 200);
  AssertEquals('right, indented', 70, L.Fragments[0].X);
end;

{ The line spacings on a 20 px line, and the space before and after the paragraph. }
procedure TTyRichLayoutTest.TestLineAndParagraphSpacing;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  pf: TTyParaFormat;

  function H(ASpacing: TTyLineSpacing; AValue: Integer): Integer;
  begin
    pf := TyDefaultParaFormat;
    pf.LineSpacing := ASpacing;
    pf.LineSpacingValue := AValue;
    SetPara(d, 0, [pffLineSpacing], pf);
    FLayouter.Clear;
    Result := Lay(d, 0, 1000).Lines[0].Height;
  end;

begin
  d := NewDoc('abc'#10'aaaa bbbb');
  AssertEquals('single', 20, H(lsSingle, 0));
  AssertEquals('1.15', 23, H(ls115, 0));
  AssertEquals('1.5', 30, H(ls15, 0));
  AssertEquals('double', 40, H(lsDouble, 0));
  AssertEquals('exactly 600 twips', 40, H(lsExact, 600));
  AssertEquals('at least 150 twips: the font is taller', 20, H(lsAtLeast, 150));
  AssertEquals('at least 600 twips', 40, H(lsAtLeast, 600));
  // two double-spaced lines, 300 twips before and 150 after
  pf := TyDefaultParaFormat;
  pf.LineSpacing := lsDouble;
  pf.SpaceBefore := 300;
  pf.SpaceAfter := 150;
  SetPara(d, 1, [pffLineSpacing, pffSpaceBefore, pffSpaceAfter], pf);
  L := Lay(d, 1, 60);
  AssertEquals('two lines', 2, L.LineCount);
  AssertEquals('the first below the space before', 20, L.Lines[0].Top);
  AssertEquals('the second', 60, L.Lines[1].Top);
  AssertEquals('the spacing goes above the text', 56, L.Lines[0].Baseline);
  AssertEquals('the paragraph''s height', 110, L.Height);
end;

{ U+000B ends a line wherever it is; the caret after it is on the next line, also at the end of
  the paragraph. }
procedure TTyRichLayoutTest.TestVerticalTabForcesALineBreak;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
begin
  d := NewDoc('ab'#11'cd'#10'ab'#11);
  L := Lay(d, 0, 1000);
  AssertEquals('two lines', 2, L.LineCount);
  AssertTrue('the first is forced', L.Lines[0].Forced);
  AssertEquals('it holds the U+000B', 3, L.Lines[0].Count);
  AssertEquals('before it: the first line', 0, L.CaretRect(2).Top);
  AssertEquals('after it: the second', 20, L.CaretRect(3).Top);
  AssertEquals('at its start', 0, L.CaretRect(3).Left);
  AssertEquals('past the first line''s end: before the U+000B', 2, L.PosAtPoint(500, 5));
  L := Lay(d, 1, 1000);
  AssertEquals('at the end: an empty line after it', 2, L.LineCount);
  AssertEquals('the caret there', 20, L.CaretRect(3).Top);
end;

{ An escaped byte (F8+, 80+: two characters) shows as one replacement glyph: the first
  character has its advance, the second none, and both keep a caret place. A lone invalid
  byte is one character and one glyph. No raw byte reaches the renderer. }
procedure TTyRichLayoutTest.TestAnInvalidBytePairShowsOneReplacement;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  fr: TTyRichFragment;
  i: Integer;
begin
  d := TTyRichDocument.CreateFromUtf8(ByteArray([Ord('a'), $FA, $81, Ord('b'), 10,
    Ord('x'), $FF, Ord('y')]));
  FDocs.Add(d);
  AssertEquals('four characters', 4, d.Text.ParaLength(0));
  L := Lay(d, 0, 1000);
  AssertEquals('layout length', 4, L.Length);
  fr := FragAt(L, 1);
  AssertEquals('a replacement', Ord(rfkReplacement), Ord(fr.Kind));
  AssertEquals('covering both', 2, fr.Count);
  AssertEquals('one glyph''s advance', 20, fr.Width);
  AssertEquals('drawn as U+FFFD', U($FFFD), fr.Text);
  AssertEquals('caret 0', 0, L.CaretRect(0).Left);
  AssertEquals('caret 1', 10, L.CaretRect(1).Left);
  AssertEquals('caret 2: after the glyph', 30, L.CaretRect(2).Left);
  AssertEquals('caret 3', 30, L.CaretRect(3).Left);
  AssertEquals('caret 4', 40, L.CaretRect(4).Left);
  for i := 0 to L.FragmentCount - 1 do
    AssertTrue('no raw byte drawn', Pos(AnsiChar($FA), L.FragmentText(i)) = 0);
  L := Lay(d, 1, 1000);
  AssertEquals('three characters', 3, L.Length);
  fr := FragAt(L, 1);
  AssertEquals('one replacement', 1, fr.Count);
  AssertEquals('caret 2', 30, L.CaretRect(2).Left);
end;

{ A base with a combining mark, an emoji with a variation selector, one with a skin tone and a
  ZWJ family are each one cluster: never cut by a line, measured and drawn as one piece, and
  a caret place inside one goes to its start. }
procedure TTyRichLayoutTest.TestClustersStayOnOneLineInOnePiece;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  s, family: UTF8String;
begin
  family := U($1F468) + U($200D) + U($1F469) + U($200D) + U($1F467);
  s := 'e' + U($301) + U($2764) + U($FE0F) + U($1F44D) + U($1F3FD) + family + 'x';
  d := NewDoc(s);
  // one pixel: a cluster a line, whole
  L := Lay(d, 0, 1);
  AssertEquals('five lines', 5, L.LineCount);
  AssertEquals('1', 'e' + U($301), LineText(L, 0));
  AssertEquals('2', U($2764) + U($FE0F), LineText(L, 1));
  AssertEquals('3', U($1F44D) + U($1F3FD), LineText(L, 2));
  AssertEquals('4', family, LineText(L, 3));
  AssertEquals('5', 'x', LineText(L, 4));
  AssertEquals('one piece each', 5, L.FragmentCount);
  // narrower than the family: still whole
  FLayouter.Clear;
  L := Lay(d, 0, 30);
  AssertEquals('the family on a line of its own', family, LineText(L, L.LineOfPos(6)));
  // wide: one line, and each cluster inside one fragment
  L := Lay(d, 0, 1000);
  AssertEquals('one line', 1, L.LineCount);
  AssertEquals('one piece', 1, L.FragmentCount);
  AssertEquals('inside the first cluster: its start', L.CaretRect(0).Left, L.CaretRect(1).Left);
  AssertEquals('inside the family: its start', L.CaretRect(6).Left, L.CaretRect(8).Left);
  AssertEquals('after it', L.CaretRect(6).Left + 60, L.CaretRect(11).Left);
end;

{ A paragraph of 100,000 and one of 200,000 characters - words, Chinese, and long words that
  have to be cut on every line: the measure calls and the characters handed to the device
  grow with the length (no prefix-by-prefix measuring of long stretches), and what the layout
  keeps is per line, not per character. }
procedure TTyRichLayoutTest.TestALongParagraphLaysOutInLinearCalls;
var
  calls, chars, mem: array[0..1] of Int64;
  lines: array[0..1] of Integer;
  k, i, n: Integer;
  s: UTF8String;
  d: TTyRichDocument;
  lo: TTyRichLayouter;
  L: TTyParaLayout;
  cp: Int64;
begin
  for k := 0 to 1 do
  begin
    n := 100000 * (k + 1);
    s := '';
    cp := 0;
    i := 0;
    while cp < n do
    begin
      if i mod 40 = 39 then
      begin
        s := s + StringOfChar('z', 2000) + ' ';
        Inc(cp, 2001);
      end
      else if i mod 7 = 3 then
      begin
        s := s + '中文字 ';
        Inc(cp, 4);
      end
      else
      begin
        s := s + 'w' + IntToStr(i mod 1000) + ' ';
        Inc(cp, Length('w' + IntToStr(i mod 1000) + ' '));
      end;
      Inc(i);
    end;
    d := NewDoc(s);
    lo := NewLayouter;
    try
      L := lo.LayoutPara(d, 0, 400, 96, 1);
      try
        calls[k] := TTyRichTestDevice(lo.Device).MeasureCalls;
        chars[k] := TTyRichTestDevice(lo.Device).MeasuredChars;
        mem[k] := L.MemSize;
        lines[k] := L.LineCount;
        AssertTrue(Format('%d: measured %d characters in %d calls, %d lines, keeps %d bytes',
          [cp, chars[k], calls[k], lines[k], mem[k]]),
          (chars[k] <= 20 * cp) and (calls[k] <= cp div 2) and (mem[k] <= 16 * cp));
      finally
        L.Release;
      end;
    finally
      lo.Free;
    end;
  end;
  AssertTrue(Format('calls %d then %d', [calls[0], calls[1]]), calls[1] <= 2 * calls[0] + 100);
  AssertTrue(Format('characters %d then %d', [chars[0], chars[1]]),
    chars[1] <= 2 * chars[0] + 10000);
  AssertTrue(Format('kept %d then %d', [mem[0], mem[1]]), mem[1] <= 2 * mem[0] + 65536);
end;

{ At most CLayoutCacheParas layouts, the least recently used going first; and at most
  CLayoutCacheChars characters in them, the one laid out last always staying. }
procedure TTyRichLayoutTest.TestTheCacheIsBoundedByCountAndBySize;
var
  d: TTyRichDocument;
  s, word: UTF8String;
  i, n: Integer;
begin
  s := '';
  for i := 0 to 2099 do s := s + 'p' + IntToStr(i) + #10;
  d := NewDoc(s);
  for i := 0 to 2099 do FLayouter.LayoutPara(d, i, 300, 96, 1).Release;
  AssertEquals('the count bound', CLayoutCacheParas, FLayouter.CachedCount);
  AssertTrue('the first went', FLayouter.CachedLayout(0) = nil);
  AssertTrue('the oldest left went', FLayouter.CachedLayout(2099 - CLayoutCacheParas) = nil);
  AssertTrue('the newest stays', FLayouter.CachedLayout(2099) <> nil);
  AssertTrue('the oldest kept', FLayouter.CachedLayout(2100 - CLayoutCacheParas) <> nil);
  // giant paragraphs: 25 of 100,000 characters
  word := '';
  for i := 1 to 20000 do word := word + 'abcd ';
  s := '';
  for i := 1 to 25 do s := s + word + #10;
  d := NewDoc(s);
  for i := 0 to 24 do FLayouter.LayoutPara(d, i, 300, 96, 1).Release;
  n := FLayouter.CachedCount;
  AssertTrue(Format('%d characters held in %d layouts', [FLayouter.CachedChars, n]),
    FLayouter.CachedChars <= CLayoutCacheChars);
  AssertTrue('some stay', n >= 1);
  AssertTrue('not all', n < 25);
  AssertTrue('the last one laid out stays', FLayouter.CachedLayout(24) <> nil);
end;

{ A paragraph inserted before the cached ones, then three deleted: the cached layouts follow
  their paragraphs to the new indexes, and are hits there. }
procedure TTyRichLayoutTest.TestCachedLayoutsFollowInsertedAndDeletedParagraphs;
var
  d: TTyRichDocument;
  s: UTF8String;
  i: Integer;
  L: TTyParaLayout;
  hits: Int64;
begin
  s := '';
  for i := 0 to 9 do s := s + 'para' + IntToStr(i) + #10;
  d := NewDoc(s);
  d.OnChange := @DocChanged;
  for i := 5 to 8 do Lay(d, i, 300);
  AssertTrue('inserted', d.Execute(TTyRichInsertText.Create(d.Text.ParaStart(1), 'x'#10)));
  for i := 6 to 9 do
  begin
    AssertTrue(Format('a layout at %d', [i]), FLayouter.CachedLayout(i) <> nil);
    AssertEquals('its first paragraph', i, FLayouter.CachedLayout(i).FirstPara);
  end;
  hits := FLayouter.CacheHits;
  L := Lay(d, 6, 300);
  AssertEquals('a hit', hits + 1, FLayouter.CacheHits);
  AssertEquals('what was paragraph 5', 'para5', L.Text);
  AssertFalse('not stale', L.Stale);
  // paragraphs 0, 1 and 2 ("para0", "x", "para1") go
  AssertTrue('deleted', d.Execute(TTyRichDelete.Create(0, d.Text.ParaStart(3))));
  AssertEquals('para2 is first', 'para2', d.Text.GetText(0, d.Text.ParaLength(0)));
  hits := FLayouter.CacheHits;
  L := Lay(d, 3, 300);
  AssertEquals('a hit again', hits + 1, FLayouter.CacheHits);
  AssertEquals('still paragraph 5''s', 'para5', L.Text);
  AssertEquals('at 3', 3, L.FirstPara);
  L := Lay(d, 6, 300);
  AssertEquals('para8 at 6', 'para8', L.Text);
end;

{ A layout handed out stays the caller's: the cache dropping it (cleared, evicted) lets go of
  the cache's reference only, and the layout answers until the caller releases it. Freed
  memory is poisoned meanwhile, so a layout freed under the caller would not answer. }
procedure TTyRichLayoutTest.TestAHandedOutLayoutOutlivesTheCache;
var
  d: TTyRichDocument;
  L, L0: TTyParaLayout;
  s: UTF8String;
  i: Integer;
begin
  s := 'hello world'#10;
  for i := 1 to 2100 do s := s + 'p' + IntToStr(i) + #10;
  d := NewDoc(s);
  L := FLayouter.LayoutPara(d, 0, 300, 96, 1);
  try
    AssertEquals('the cache''s and the caller''s', 2, L.RefCount);
    BeginPoison;
    try
      FLayouter.Clear;
      AssertEquals('only the caller''s', 1, L.RefCount);
      AssertTrue('stale', L.Stale);
      AssertEquals('it still answers', 30, L.CaretRect(3).Left);
      AssertEquals('its lines', 1, L.LineCount);
    finally
      EndPoison;
    end;
  finally
    L.Release;
  end;
  // evicted by the count bound while held
  L0 := FLayouter.LayoutPara(d, 0, 300, 96, 1);
  try
    BeginPoison;
    try
      for i := 1 to 2100 do FLayouter.LayoutPara(d, i, 300, 96, 1).Release;
      AssertTrue('it left the cache', FLayouter.CachedLayout(0) = nil);
      AssertFalse('evicted is not stale', L0.Stale);
      AssertEquals('it still answers', 50, L0.CaretRect(5).Left);
      AssertEquals('one reference', 1, L0.RefCount);
    finally
      EndPoison;
    end;
  finally
    L0.Release;
  end;
end;

{ A document that parses on demand sends paragraphs it read back to unparsed, and the objects
  they held go with them. A cached layout of a paragraph with a picture keeps the picture: it
  is still there, and the same, after that paragraph's interval was sent back. }
procedure TTyRichLayoutTest.TestALayoutKeepsItsObjectAlivePastEviction;
var
  b, sample: TBytes;
  header, body, trailer: RawByteString;
  m: TTyRtfSourceMap;
  d, full: TTyRichDocument;
  st: TBytesStream;
  load: TTyRtfLoad;
  q, i, j, w, h, n: Integer;
  runs: TTyRunArray;
  L: TTyParaLayout;
  obj: TTyRichObject;
  fr: TTyRichFragment;
  found: Boolean;
  bb: RawByteString;

  function ReadFile(const APath: string): TBytes;
  var
    f: TFileStream;
  begin
    Result := nil;
    f := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
    try
      SetLength(Result, f.Size);
      if f.Size > 0 then f.ReadBuffer(Result[0], f.Size);
    finally
      f.Free;
    end;
  end;

  function Part(AFrom, ACount: Int64): RawByteString;
  begin
    Result := '';
    SetLength(Result, ACount);
    if ACount > 0 then Move(sample[AFrom], Result[1], ACount);
  end;

begin
  sample := ReadFile(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim +
    'fixtures' + PathDelim + 'rtf' + PathDelim + 're-zh-picture.rtf');
  // the sample's header, its paragraphs repeated to a megabyte, its trailer
  m := TTyRtfSourceMap.Create;
  full := TTyRichDocument.Create;
  st := TBytesStream.Create(sample);
  try
    TyRichLoadRtfFull(full, st, m);
    header := Part(0, m.Header.Stop);
    body := Part(m.Header.Stop, m.Trailer.Start - m.Header.Stop);
    trailer := Part(m.Trailer.Start, Length(sample) - m.Trailer.Start);
  finally
    st.Free;
    full.Free;
    m.Free;
  end;
  bb := header;
  while Length(bb) < MB do bb := bb + body;
  bb := bb + trailer;
  b := BytesOf(bb);
  d := TTyRichDocument.Create;
  FDocs.Add(d);
  st := TBytesStream.Create(b);
  try
    TyRichLoadRtf(d, st);
  finally
    st.Free;
  end;
  load := TyRichRtfLoadOf(d);
  AssertTrue('loaded lazily', load <> nil);
  load.MaxResidentIntervals := 1;
  AssertTrue('intervals', load.IntervalCount >= 6);
  // a paragraph of the third interval that holds a picture
  q := -1;
  for i := load.IntervalFirstPara(2) to load.IntervalFirstPara(2) + 6 do
  begin
    runs := d.RunsOf(i);
    for j := 0 to High(runs) do
      if runs[j].Obj is TTyRichPicture then q := i;
    if q >= 0 then Break;
  end;
  AssertTrue('a picture paragraph', q >= 0);
  L := FLayouter.LayoutPara(d, q, 400, 96, 1);
  try
    found := False;
    obj := nil;
    for i := 0 to L.FragmentCount - 1 do
      if L.Fragments[i].Obj <> nil then
      begin
        fr := L.Fragments[i];
        obj := fr.Obj;
        found := True;
        Break;
      end;
    AssertTrue('the layout shows the picture', found);
    w := TTyRichPicture(obj).WidthTwips;
    h := TTyRichPicture(obj).HeightTwips;
    n := Length(TTyRichPicture(obj).Data);
    AssertTrue('a size', (w > 0) and (h > 0) and (n > 0));
    AssertEquals('its box', TyRichTwipsToPx(w, 96, 1), fr.Width);
    BeginPoison;
    try
      // reading other intervals sends the picture's back to unparsed
      for i := 3 to 5 do d.EnsureParsed(load.IntervalFirstPara(i) + 1);
      AssertTrue('the picture''s paragraph went back to unparsed',
        TBuilderAccess.Value(d, q) = nil);
      AssertEquals('the width, still', w, TTyRichPicture(obj).WidthTwips);
      AssertEquals('the height', h, TTyRichPicture(obj).HeightTwips);
      AssertEquals('the data', n, Length(TTyRichPicture(obj).Data));
      AssertTrue('held', obj.RefCount >= 1);
    finally
      EndPoison;
    end;
  finally
    L.Release;
  end;
end;

{ The real device: each fragment of a laid-out line drawn on its own on a sentinel ground,
  through the device, at the X and baseline the layout gave it - its ink must stay inside the
  box the layout measured for it (a pixel or two of overhang allowed), and there must be ink.
  So what is measured is what is drawn, where it was measured. }
procedure TTyRichLayoutTest.TestRenderedInkStaysInsideTheMeasuredBoxes;
const
  Pad = 20;
  Slack = 2;
var
  dev: TTyRichBgraDevice;
  lo: TTyRichLayouter;
  d: TTyRichDocument;
  L: TTyParaLayout;
  ln: TTyRichLine;
  fr: TTyRichFragment;
  bmp: TBGRABitmap;
  k, i, x, y, ink, outside: Integer;
  p: PBGRAPixel;
  sentinel: TBGRAPixel;
  text: UTF8String;
begin
  sentinel := BGRA(255, 0, 255, 255);
  dev := TTyRichBgraDevice.Create;
  lo := TTyRichLayouter.Create(dev, True);
  try
    {$IFDEF MSWINDOWS}
    lo.BaseFontName := 'Arial';
    {$ENDIF}
    lo.BaseFontSizeHalfPt := 24;
    d := NewDoc('Hello 世界, ink check: 中文和English mixed. Wrapped (twice) text here.');
    L := lo.LayoutPara(d, 0, 260, 96, 1);
    try
      AssertTrue('wrapped', L.LineCount >= 2);
      for k := 0 to L.LineCount - 1 do
      begin
        ln := L.Lines[k];
        for i := ln.FirstFrag to ln.FirstFrag + ln.FragCount - 1 do
        begin
          fr := L.Fragments[i];
          if fr.Kind <> rfkText then Continue;
          text := L.FragmentText(i);
          if Trim(text) = '' then Continue;
          bmp := TBGRABitmap.Create(L.Width + 2 * Pad + 40, L.Height + 2 * Pad, sentinel);
          try
            dev.DrawText(bmp, fr.Font, fr.X + Pad, ln.Baseline + fr.Shift + Pad, text, BGRABlack);
            ink := 0;
            outside := 0;
            for y := 0 to bmp.Height - 1 do
            begin
              p := bmp.ScanLine[y];
              for x := 0 to bmp.Width - 1 do
              begin
                if (p^.red <> 255) or (p^.green <> 0) or (p^.blue <> 255) then
                begin
                  Inc(ink);
                  if (x < fr.X + Pad - Slack) or (x >= fr.X + fr.Width + Pad + Slack) or
                    (y < ln.Top + Pad - Slack) or (y >= ln.Top + ln.Height + Pad + Slack) then
                    Inc(outside);
                end;
                Inc(p);
              end;
            end;
            AssertTrue(Format('"%s" has ink', [text]), ink > 20);
            AssertEquals(Format('"%s": ink outside its box [%d, %d) x [%d, %d)', [text, fr.X,
              fr.X + fr.Width, ln.Top, ln.Top + ln.Height]), 0, outside);
          finally
            bmp.Free;
          end;
        end;
      end;
    finally
      L.Release;
    end;
  finally
    lo.Free;
  end;
end;

{ The real device's glyph question. On Windows it reads the font's cmap: Arial has A and no
  中, SimSun has 中, Segoe UI Emoji has U+1F600 (a code point past the BMP, from the format-12
  table). Elsewhere it goes by the font's name. }
procedure TTyRichLayoutTest.TestTheRealDeviceKnowsWhichGlyphsAFontHas;
var
  dev: TTyRichBgraDevice;
begin
  dev := TTyRichBgraDevice.Create;
  try
    {$IFDEF MSWINDOWS}
    AssertTrue('Arial has A', dev.HasGlyph(dev.ResolveFont('Arial', 16, []), Ord('A')));
    AssertFalse('Arial has no 中', dev.HasGlyph(dev.ResolveFont('Arial', 16, []), $4E2D));
    AssertTrue('SimSun has 中', dev.HasGlyph(dev.ResolveFont('SimSun', 16, []), $4E2D));
    AssertTrue('Segoe UI Emoji has U+1F600',
      dev.HasGlyph(dev.ResolveFont('Segoe UI Emoji', 16, []), $1F600));
    AssertFalse('Arial has no U+1F600', dev.HasGlyph(dev.ResolveFont('Arial', 16, []), $1F600));
    {$ELSE}
    AssertTrue('a Latin glyph', dev.HasGlyph(dev.ResolveFont('Sans', 16, []), Ord('A')));
    AssertFalse('a Latin font has no 中', dev.HasGlyph(dev.ResolveFont('Sans', 16, []), $4E2D));
    AssertTrue('a CJK font has 中', dev.HasGlyph(dev.ResolveFont('Noto Sans CJK SC', 16, []), $4E2D));
    {$ENDIF}
  finally
    dev.Free;
  end;
end;

{ At 200 % the page's text width and the font double, the lines are the same, and the
  document is not touched (no change, no undo step, not modified). }
procedure TTyRichLayoutTest.TestZoomScalesWidthAndFontAndLeavesTheDocument;
var
  d: TTyRichDocument;
  L1, L2: TTyParaLayout;
  s: UTF8String;
  i, fmts, undo: Integer;
begin
  s := '';
  for i := 1 to 30 do s := s + 'word 中文 ';
  d := NewDoc(s);
  d.OnChange := @DocChanged;
  fmts := d.Formats.CharCount;
  undo := d.UndoDepth;
  L1 := Lay(d, 0, TyRichLayoutWidth(rwmPage, 0, d, 96, 1), 1);
  L2 := FLayouter.LayoutPara(d, 0, TyRichLayoutWidth(rwmPage, 0, d, 96, 2), 96, 2);
  FLayouts.Add(L2);
  AssertEquals('the width doubles', 2 * L1.LayoutWidth, L2.LayoutWidth);
  AssertEquals('the font doubles', 2 * FDevice.FontPixelHeight(L1.Fragments[0].Font),
    FDevice.FontPixelHeight(L2.Fragments[0].Font));
  AssertEquals('so do the lines', 2 * L1.Lines[0].Height, L2.Lines[0].Height);
  AssertEquals('the same lines', L1.LineCount, L2.LineCount);
  for i := 0 to L1.LineCount - 1 do
    AssertEquals('line ' + IntToStr(i), L1.Lines[i].Count, L2.Lines[i].Count);
  AssertEquals('no change reported', 0, FChanges);
  AssertFalse('not modified', d.Modified);
  AssertEquals('no undo step', undo, d.UndoDepth);
  AssertEquals('no new format', fmts, d.Formats.CharCount);
  AssertEquals('the text', s, d.Text.GetText(0, d.Text.Length));
end;

{ ---- mine ---- }

{ An empty paragraph has one line as tall as its own font, and its caret at the start. }
procedure TTyRichLayoutTest.TestAnEmptyParagraphHasOneLineOfItsFont;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  f: TTyCharFormat;
  r: TRect;
begin
  d := NewDoc('a'#10#10'b');
  L := Lay(d, 1, 300);
  AssertEquals('one line', 1, L.LineCount);
  AssertEquals('no fragment', 0, L.FragmentCount);
  AssertEquals('the base font''s height', 20, L.Height);
  r := L.CaretRect(0);
  AssertEquals('caret left', 0, r.Left);
  AssertEquals('caret top', 0, r.Top);
  AssertEquals('caret bottom', 20, r.Bottom);
  AssertEquals('a click lands there', 0, L.PosAtPoint(100, 100));
  // its typing format, 60 half-points (40 px), makes it taller
  f := TyDefaultCharFormat;
  f.SizeHalfPt := 60;
  SetChar(d, d.Text.ParaStart(1), 1, [cffSize], f);
  FLayouter.Clear;
  L := Lay(d, 1, 300);
  AssertEquals('as tall as its font', 40, L.Height);
end;

{ A superscript is two thirds the size, its baseline a third of the font up: the line grows by
  what the shift needs, not by a whole font. A subscript the other way. }
procedure TTyRichLayoutTest.TestSuperscriptShiftsWithoutGrowingTheLineMoreThanItNeeds;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  f: TTyCharFormat;
  fr: TTyRichFragment;
begin
  d := NewDoc('x2'#10'x2');
  f := TyDefaultCharFormat;
  f.VertAlign := vaSuper;
  SetChar(d, 1, 1, [cffVertAlign], f);
  f.VertAlign := vaSub;
  SetChar(d, d.Text.ParaStart(1) + 1, 1, [cffVertAlign], f);
  L := Lay(d, 0, 300);
  fr := FragAt(L, 1);
  AssertEquals('two thirds', 13, FDevice.FontPixelHeight(fr.Font));
  AssertEquals('up a third', -7, fr.Shift);
  // its top: 10 above its baseline, 7 up: 17 against the line's 16
  AssertEquals('one pixel more than a plain line', 21, L.Lines[0].Height);
  L := Lay(d, 1, 300);
  fr := FragAt(L, 1);
  AssertEquals('sub: two thirds', 13, FDevice.FontPixelHeight(fr.Font));
  AssertEquals('down a sixth', 3, fr.Shift);
  AssertEquals('sub: 6 below against 4', 22, L.Lines[0].Height);
end;

{ A picture is a box of its display size (a default box with none); an opaque object with a
  display text is that text, one character for positions; without one it has no width. }
procedure TTyRichLayoutTest.TestObjectsAreBoxes;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  fr: TTyRichFragment;
begin
  d := NewDoc('abcd'#10'abcd'#10'abcd'#10'abcd');
  AssertTrue('picture', d.Execute(TTyRichInsertObject.Create(2,
    TTyRichPicture.Create(rpfPng, nil, 1440, 720))));
  AssertTrue('no size', d.Execute(TTyRichInsertObject.Create(d.Text.ParaStart(1) + 2,
    TTyRichPicture.Create(rpfPng, nil, 0, 0))));
  AssertTrue('opaque', d.Execute(TTyRichInsertObject.Create(d.Text.ParaStart(2) + 2,
    TTyRichOpaque.Create('{\*\x}', 'abc'))));
  AssertTrue('opaque, nothing shown', d.Execute(TTyRichInsertObject.Create(
    d.Text.ParaStart(3) + 2, TTyRichOpaque.Create('{\*\y}'))));
  L := Lay(d, 0, 1000);
  fr := FragAt(L, 2);
  AssertEquals('an object', Ord(rfkObject), Ord(fr.Kind));
  AssertEquals('1440 twips', 96, fr.Width);
  AssertEquals('720 twips above the baseline', 48, fr.Ascent);
  AssertEquals('the line: the picture and the descent', 52, L.Lines[0].Height);
  AssertEquals('after it', 116, L.CaretRect(3).Left);
  L := Lay(d, 1, 1000);
  AssertEquals('the default box', 32, FragAt(L, 2).Width);
  L := Lay(d, 2, 1000);
  fr := FragAt(L, 2);
  AssertEquals('its text''s width', 30, fr.Width);
  AssertEquals('one character', 1, fr.Count);
  AssertEquals('shown as', 'abc', fr.Text);
  AssertEquals('caret after it', 50, L.CaretRect(3).Left);
  AssertEquals('a click on its left part: before it', 2, L.PosAtPoint(30, 5));
  AssertEquals('on its right part: after it', 3, L.PosAtPoint(40, 5));
  L := Lay(d, 3, 1000);
  AssertEquals('nothing shown: no width', 0, FragAt(L, 2).Width);
end;

{ One rectangle per line the range touches: from the start's caret to the end's, a whole
  middle line to its end with its hanging spaces; the paragraph's separator selected adds a
  mark past the last line's end. }
procedure TTyRichLayoutTest.TestSelectionRectsCoverTheRangeLineByLine;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  r: TRectArray;
begin
  d := NewDoc('hello world foo');
  L := Lay(d, 0, 120);
  r := L.SelectionRects(3, 13);
  AssertEquals('two lines', 2, Length(r));
  AssertEquals('from the start', 30, r[0].Left);
  AssertEquals('to the end of the first line, its space included', 110, r[0].Right);
  AssertEquals('line 1 top', 0, r[0].Top);
  AssertEquals('line 1 bottom', 20, r[0].Bottom);
  AssertEquals('line 2 from its start', 0, r[1].Left);
  AssertEquals('to the end', 10, r[1].Right);
  AssertEquals('line 2 top', 20, r[1].Top);
  r := L.SelectionRects(12, 16);
  AssertEquals('one line', 1, Length(r));
  AssertTrue('the separator''s mark', r[0].Right > 30);
  AssertEquals('nothing selected', 0, Length(L.SelectionRects(5, 5)));
end;

initialization
  RegisterTest(TTyRichLayoutTest);

end.
