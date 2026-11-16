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
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.RowFormat, tyControls.RichEdit.Layout,
  test.richedit.layoutdevice;

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
    function LoadFixture(const AName: string): TTyRichDocument;
    function NewTableDoc(const AText: RawByteString): TTyRichDocument;
    function Block(ADoc: TTyRichDocument; AIndex, AWidth: Integer): TTyBlockLayout;
    { The sample's paragraphs repeated to a megabyte, loaded lazily, one interval resident. }
    function LoadLazyRepeated(const AName: string): TTyRichDocument;
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
    // 8b: list markers
    procedure TestListMarkersAreLaidOutAheadOfTheFirstLine;
    procedure TestListNumbersCountTheItemsOfOneLevel;
    procedure TestAlphaAndRomanNumbersPastTheirRanges;
    procedure TestTheNumberingWalkIsCappedAndRemembered;
    // 8b: table rows
    procedure TestTableCellsLayOutAndRowHeightIsTheTallest;
    procedure TestARowIsAsTallAsItsFormatDemands;
    procedure TestPositionsRunAcrossTheCellsOfARow;
    procedure TestARowIsFoundFromItsOwnParagraphs;
    procedure TestMergedCellsAreShownMerged;
    procedure TestARowInALazyDocumentSurvivesEviction;
    procedure TestTheRowFormatIsRead;
    // 8b: pictures
    procedure TestPicturesAreDecodedWhenDrawnAndKept;
    procedure TestThePictureCacheIsBoundedByBytes;
    procedure TestPicturesThatCannotBeShownArePlaceholders;
    procedure TestTheWordPadPictureShowsItsBitmap;
    // 8b: painting
    procedure TestPaintDrawsOnlyWhatMeetsTheClip;
    procedure TestPaintSelectionKeepsTheGlyphsInPlace;
    procedure TestPaintedSelectionDoesNotMoveGlyphsOnTheRealDevice;
    procedure TestPaintHighlightUnderlineAndStrike;
    procedure TestPaintTabLeadersAndTheMarker;
    procedure TestPaintARowsContentsThenItsLines;
    procedure TestPaintDecodesOnlyThePicturesItDraws;
    // the review's findings (fix wave W1)
    procedure TestADecimalTabFindsThePointInALaterPiece;
    procedure TestAPointAtALineEndGivesACaretThere;
    procedure TestAJustifiedLineKeepsAFewFragments;
    procedure TestTheDocumentIsToldNotRecognisedByItsAddress;
    procedure TestSizesFromAFileHaveCeilingsOnTheWayToPixels;
    procedure TestAGiantParagraphIsLaidOutUpToTheCap;
    procedure TestAHeldLayoutTheCacheLetGoOfIsStaleAfterAChange;
    procedure TestASpaceCarryingAMarkIsText;
    procedure TestATabPastTheRightEdgeGoesToTheNextLine;
    procedure TestTheHangingIndentIsATabStopOfTheFirstLine;
    procedure TestTheFallbackEventAndListDropWhatWasFound;
    procedure TestTheCmapReaderBoundsItsCounts;
    procedure TestTheMeasureCacheIsBoundedByBytes;
    procedure TestChangesInsideAndAcrossCachedParagraphsAreFollowed;
    // fix wave W2: rows
    procedure TestWordsBorderlessCellsHaveNoLines;
    procedure TestDeclaredLinesAreDrawnOnceAndNotLost;
    procedure TestARowIsPlacedAndBoundedAsItsFormatSays;
    procedure TestAnExactRowShowsAndAnswersOnlyItsBox;
    procedure TestPaintLeavesTheClipAndHidesMergedAwayText;
    // fix wave W2: pictures
    procedure TestOneScreensPicturesNeverEvictEachOther;
    procedure TestPictureSizesAreBoundedBeforeAnythingIsAllocated;
    procedure TestAPreparedPictureIsReady;
    procedure TestPictureCacheDetails;
    // fix wave W2: lists
    procedure TestWordListsShowTheFilesNumbers;
    procedure TestACappedWalkAnchorsOnARememberedNumber;
    procedure TestTheMarkerGoesWithTheFirstLine;
    procedure TestBulletsForEveryLevel;
  end;

implementation

uses
  Math, FPWriteJPEG, tyControls.StrConsts, test.danglingrefs;

type
  { The layouter with its decoder and resampler counted, and made to raise on request. }
  TSeamLayouter = class(TTyRichLayouter)
  protected
    function DecodeImage(AStream: TStream; AJpegScale: Integer): TBGRABitmap; override;
    function ScaleImage(AImage: TBGRABitmap; AWidth, AHeight: Integer): TBGRABitmap; override;
  public
    DecodeRaise, ScaleRaise: ExceptClass;
    DecodeCalls, ScaleCalls: Integer;
  end;

function TSeamLayouter.DecodeImage(AStream: TStream; AJpegScale: Integer): TBGRABitmap;
begin
  Inc(DecodeCalls);
  if DecodeRaise <> nil then raise DecodeRaise.Create('a decoder that fails');
  Result := inherited DecodeImage(AStream, AJpegScale);
end;

function TSeamLayouter.ScaleImage(AImage: TBGRABitmap; AWidth, AHeight: Integer): TBGRABitmap;
begin
  Inc(ScaleCalls);
  if ScaleRaise <> nil then raise ScaleRaise.Create('a resample that fails');
  Result := inherited ScaleImage(AImage, AWidth, AHeight);
end;

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

type
  { Parses on demand: every paragraph it is asked for becomes a list item in ParaFmt; counts
    what it was asked (a read that had to parse). }
  TListLoader = class(TTyRichParaLoader)
  public
    Calls: Integer;
    ParaFmt: TTyParaFormatId;
    CharFmt: TTyCharFormatId;
    procedure LoadParagraph(ADoc: TTyRichDocument; AIndex: Integer); override;
  end;

procedure TListLoader.LoadParagraph(ADoc: TTyRichDocument; AIndex: Integer);
var
  runs: TTyRunArray;
begin
  Inc(Calls);
  runs := nil;
  SetLength(runs, 1);
  runs[0].Start := 0;
  runs[0].Format := CharFmt;
  runs[0].Obj := nil;
  SetParagraph(ADoc, AIndex, ParaFmt, runs);
end;

type
  { MarkTable, which only a command may call otherwise. }
  TDocAccess = class(TTyRichDocument)
  end;

  { Parses on demand: paragraph i is cell i mod Cells of row i div Cells of its table; counts
    what it was asked. }
  TTableLoader = class(TTyRichParaLoader)
  public
    Calls: Integer;
    ParaFmt: TTyParaFormatId;
    CharFmt: TTyCharFormatId;
    Table: TTyRichTable;
    Cells: Integer;
    constructor Create(ARows, ACells: Integer);
    destructor Destroy; override;
    procedure LoadParagraph(ADoc: TTyRichDocument; AIndex: Integer); override;
  end;

constructor TTableLoader.Create(ARows, ACells: Integer);
var
  i: Integer;
begin
  inherited Create;
  Cells := ACells;
  Table := TTyRichTable.Create([1440, 2880]);
  Table.AddRef;
  for i := 1 to ARows do Table.AddRow(ACells);
end;

destructor TTableLoader.Destroy;
begin
  Table.Release;
  inherited Destroy;
end;

procedure TTableLoader.LoadParagraph(ADoc: TTyRichDocument; AIndex: Integer);
var
  runs: TTyRunArray;
begin
  Inc(Calls);
  runs := nil;
  SetLength(runs, 1);
  runs[0].Start := 0;
  runs[0].Format := CharFmt;
  runs[0].Obj := nil;
  SetParagraph(ADoc, AIndex, ParaFmt, runs,
    Table.Rows[AIndex div Cells].Cells[AIndex mod Cells]);
end;

{ A ground no painting produces (magenta), so that "painted" and "not painted" are told
  apart. }
function Sentinel: TBGRAPixel;
begin
  Result := BGRA(255, 0, 255, 255);
end;

function SamePx(const A, B: TBGRAPixel): Boolean;
begin
  Result := (A.red = B.red) and (A.green = B.green) and (A.blue = B.blue) and
    (A.alpha = B.alpha);
end;

{ A PNG of AW x AH pixels of one colour. }
function PngBytes(AW, AH: Integer; AColor: TBGRAPixel): TBytes;
var
  b: TBGRABitmap;
  st: TBytesStream;
begin
  b := TBGRABitmap.Create(AW, AH, AColor);
  st := TBytesStream.Create;
  try
    b.SaveToStreamAsPng(st);
    Result := Copy(st.Bytes, 0, st.Size);
  finally
    st.Free;
    b.Free;
  end;
end;

{ A JPEG of AW x AH pixels of one colour. }
function JpegBytes(AW, AH: Integer; AColor: TBGRAPixel): TBytes;
var
  b: TBGRABitmap;
  st: TBytesStream;
  wr: TFPWriterJPEG;
begin
  b := TBGRABitmap.Create(AW, AH, AColor);
  st := TBytesStream.Create;
  wr := TFPWriterJPEG.Create;
  try
    b.SaveToStream(st, wr);
    Result := Copy(st.Bytes, 0, st.Size);
  finally
    wr.Free;
    st.Free;
    b.Free;
  end;
end;

{ A PNG's signature and IHDR saying AW x AH, then bytes that decode to nothing. }
function PngHeaderBytes(AW, AH: Cardinal): TBytes;
var
  i: Integer;
begin
  Result := nil;
  SetLength(Result, 33 + 64);
  FillChar(Result[0], Length(Result), 0);
  Result[0] := $89; Result[1] := $50; Result[2] := $4E; Result[3] := $47;
  Result[4] := $0D; Result[5] := $0A; Result[6] := $1A; Result[7] := $0A;
  Result[11] := 13;
  Result[12] := Ord('I'); Result[13] := Ord('H'); Result[14] := Ord('D'); Result[15] := Ord('R');
  for i := 0 to 3 do
  begin
    Result[16 + i] := (AW shr (24 - 8 * i)) and $FF;
    Result[20 + i] := (AH shr (24 - 8 * i)) and $FF;
  end;
  Result[24] := 8;
  Result[25] := 6;
  for i := 33 to High(Result) do Result[i] := i * 7;
end;

function FixtureBytes(const AName: string): TBytes;
var
  f: TFileStream;
begin
  Result := nil;
  f := TFileStream.Create(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim +
    'fixtures' + PathDelim + 'rtf' + PathDelim + AName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, f.Size);
    if f.Size > 0 then f.ReadBuffer(Result[0], f.Size);
  finally
    f.Free;
  end;
end;

function ListFormat(AKind: TTyListKind; ALevel, AStartAt: Integer): TTyParaFormat;
begin
  Result := TyDefaultParaFormat;
  Result.List.Kind := AKind;
  Result.List.Level := ALevel;
  Result.List.StartAt := AStartAt;
  Result.LeftIndent := 720;
  Result.FirstIndent := -360;
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

{$IFDEF MSWINDOWS}
type
  // GDI's LOGFONTW
  TFontQuery = record
    Height, Width, Escapement, Orientation, Weight: LongInt;
    Italic, Underline, StrikeOut, CharSet, OutPrecision, ClipPrecision, Quality,
      PitchAndFamily: Byte;
    FaceName: array[0..31] of WideChar;
  end;

function TyGetDC(AWnd: PtrUInt): PtrUInt; stdcall; external 'user32' name 'GetDC';
function TyReleaseDC(AWnd, ADC: PtrUInt): LongInt; stdcall; external 'user32' name 'ReleaseDC';
function TyEnumFontFamiliesExW(ADC: PtrUInt; var AFont: TFontQuery; AProc: Pointer;
  AData: PtrInt; AFlags: LongWord): LongInt; stdcall; external 'gdi32' name 'EnumFontFamiliesExW';

function FontFound(AFont, AMetric: Pointer; AType: LongWord; AData: PtrInt): LongInt; stdcall;
begin
  PBoolean(AData)^ := True;
  Result := 0;
end;

{ A font family GDI has, by its English or its local name (no window: the screen's DC). }
function FontInstalled(const AName: string): Boolean;
var
  q: TFontQuery;
  dc: PtrUInt;
  w: UnicodeString;
  found: Boolean;
begin
  FillChar(q, SizeOf(q), 0);
  q.CharSet := 1;   // DEFAULT_CHARSET
  w := UnicodeString(AName);
  Move(PWideChar(w)^, q.FaceName[0], Min(Length(w), 31) * SizeOf(WideChar));
  found := False;
  dc := TyGetDC(0);
  try
    TyEnumFontFamiliesExW(dc, q, @FontFound, PtrInt(@found), 0);
  finally
    TyReleaseDC(0, dc);
  end;
  Result := found;
end;
{$ENDIF}

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

function TTyRichLayoutTest.LoadFixture(const AName: string): TTyRichDocument;
var
  st: TBytesStream;
begin
  Result := TTyRichDocument.Create;
  FDocs.Add(Result);
  st := TBytesStream.Create(FixtureBytes(AName));
  try
    TyRichLoadRtf(Result, st);
  finally
    st.Free;
  end;
end;

function TTyRichLayoutTest.NewTableDoc(const AText: RawByteString): TTyRichDocument;
begin
  Result := TDocAccess.CreateFromUtf8(BytesOf(AText));
  FDocs.Add(Result);
end;

function TTyRichLayoutTest.Block(ADoc: TTyRichDocument; AIndex, AWidth: Integer): TTyBlockLayout;
begin
  Result := FLayouter.LayoutBlock(ADoc, AIndex, AWidth, 96, 1);
  FLayouts.Add(Result);
end;

function TTyRichLayoutTest.LoadLazyRepeated(const AName: string): TTyRichDocument;
var
  sample: TBytes;
  m: TTyRtfSourceMap;
  full: TTyRichDocument;
  st: TBytesStream;
  header, body, trailer, bb: RawByteString;

  function Part(AFrom, ACount: Int64): RawByteString;
  begin
    Result := '';
    SetLength(Result, ACount);
    if ACount > 0 then Move(sample[AFrom], Result[1], ACount);
  end;

begin
  sample := FixtureBytes(AName);
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
  Result := TTyRichDocument.Create;
  FDocs.Add(Result);
  st := TBytesStream.Create(BytesOf(bb));
  try
    TyRichLoadRtf(Result, st);
  finally
    st.Free;
  end;
  AssertTrue('loaded lazily', TyRichRtfLoadOf(Result) <> nil);
  TyRichRtfLoadOf(Result).MaxResidentIntervals := 1;
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

{ A paragraph of 50,000 and one of 100,000 characters (both under the cut a paragraph is laid
  out to, CRichMaxParaLayoutChars) - words, Chinese, and long words that have to be cut on
  every line: the measure calls and the characters handed to the device grow with the length
  (no prefix-by-prefix measuring of long stretches), and what the layout keeps is per line, not
  per character. Left aligned, justified (a justified line keeps a fragment per word, not per
  character), and left aligned with the base device's own fit - the binary search the real
  device runs, each probe counted. }
procedure TTyRichLayoutTest.TestALongParagraphLaysOutInLinearCalls;
var
  calls, chars, mem: array[0..1] of Int64;
  lines: array[0..1] of Integer;
  k, i, n, mode: Integer;
  s: UTF8String;
  d: TTyRichDocument;
  lo: TTyRichLayouter;
  L: TTyParaLayout;
  cp: Int64;
  pf: TTyParaFormat;
begin
  for mode := 0 to 2 do
  begin
  for k := 0 to 1 do
  begin
    n := 50000 * (k + 1);
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
    if mode = 1 then
    begin
      pf := TyDefaultParaFormat;
      pf.Align := paraJustify;
      SetPara(d, 0, [pffAlign], pf);
    end;
    lo := NewLayouter;
    try
      TTyRichTestDevice(lo.Device).BaseFitCount := mode = 2;
      L := lo.LayoutPara(d, 0, 400, 96, 1);
      try
        calls[k] := TTyRichTestDevice(lo.Device).MeasureCalls;
        chars[k] := TTyRichTestDevice(lo.Device).MeasuredChars;
        mem[k] := L.MemSize;
        lines[k] := L.LineCount;
        AssertTrue(Format('mode %d, %d: measured %d characters in %d calls, %d lines, keeps %d bytes',
          [mode, cp, chars[k], calls[k], lines[k], mem[k]]),
          ((mode = 2) or (chars[k] <= 20 * cp)) and (chars[k] <= 100 * cp) and
          (calls[k] <= cp div 2) and (mem[k] <= 16 * cp));
      finally
        L.Release;
      end;
    finally
      lo.Free;
    end;
  end;
  AssertTrue(Format('mode %d: calls %d then %d', [mode, calls[0], calls[1]]),
    calls[1] <= 2 * calls[0] + 100);
  AssertTrue(Format('mode %d: characters %d then %d', [mode, chars[0], chars[1]]),
    chars[1] <= 2 * chars[0] + 10000);
  AssertTrue(Format('mode %d: kept %d then %d', [mode, mem[0], mem[1]]),
    mem[1] <= 2 * mem[0] + 65536);
  end;
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
  So what is measured is what is drawn, where it was measured. The ink also reaches into the
  box from both ends (within half the font size), so measuring far too wide fails too. Needs
  Arial and a CJK fallback font on Windows: skipped, saying so, without them. }
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
  k, i, x, y, ink, outside, inkL, inkR, inner: Integer;
  p: PBGRAPixel;
  sentinel: TBGRAPixel;
  text: UTF8String;
begin
  sentinel := BGRA(255, 0, 255, 255);
  {$IFDEF MSWINDOWS}
  if not FontInstalled('Arial') or (not FontInstalled('Microsoft YaHei') and
    not FontInstalled('SimSun')) then
    Ignore('needs Arial and Microsoft YaHei or SimSun installed');
  {$ENDIF}
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
            inkL := MaxInt;
            inkR := -1;
            for y := 0 to bmp.Height - 1 do
            begin
              p := bmp.ScanLine[y];
              for x := 0 to bmp.Width - 1 do
              begin
                if (p^.red <> 255) or (p^.green <> 0) or (p^.blue <> 255) then
                begin
                  Inc(ink);
                  inkL := Min(inkL, x);
                  inkR := Max(inkR, x);
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
            // and from inside: the box is not much wider than the ink (no trailing space in
            // a drawn text fragment: the spaces after a line's content are a fragment apart)
            inner := dev.FontPixelHeight(fr.Font) div 2 + Slack;
            AssertTrue(Format('"%s": ink from %d, the box from %d', [text, inkL - Pad, fr.X]),
              inkL - Pad <= fr.X + inner);
            AssertTrue(Format('"%s": ink to %d, the box to %d', [text, inkR - Pad + 1,
              fr.X + fr.Width]), inkR - Pad + 1 >= fr.X + fr.Width - inner);
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
  {$IFDEF MSWINDOWS}
  if not FontInstalled('Arial') or not FontInstalled('SimSun') or
    not FontInstalled('Segoe UI Emoji') then
    Ignore('needs Arial, SimSun and Segoe UI Emoji installed');
  {$ENDIF}
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

{ ---- 8b: list markers ---- }

{ A list paragraph gets a marker the layout makes - not in the text, no position - as WordPad
  places it: at the first line's indent (left 720 + first -360 twips = 24 px), the text at the
  left indent (48 px) when the marker ends before it, else at the next tab stop after the
  marker. In the first run's font; a bullet per level. }
procedure TTyRichLayoutTest.TestListMarkersAreLaidOutAheadOfTheFirstLine;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  pf: TTyParaFormat;
  f: TTyCharFormat;
  m: TTyRichFragment;
begin
  d := NewDoc('one'#10'two'#10'three'#10'four four four four four four'#10'five'#10'six');
  SetPara(d, 0, [pffList, pffLeftIndent, pffFirstIndent], ListFormat(lkBullet, 0, 0));
  SetPara(d, 1, [pffList, pffLeftIndent, pffFirstIndent], ListFormat(lkBullet, 1, 0));
  SetPara(d, 2, [pffList, pffLeftIndent, pffFirstIndent], ListFormat(lkDecimal, 0, 5));
  pf := ListFormat(lkDecimal, 0, 5);
  pf.FirstIndent := -150;
  SetPara(d, 3, [pffList, pffLeftIndent, pffFirstIndent], pf);
  f := TyDefaultCharFormat;
  f.SizeHalfPt := 60;
  SetChar(d, d.Text.ParaStart(4), 4, [cffSize], f);
  SetPara(d, 4, [pffList, pffLeftIndent, pffFirstIndent], ListFormat(lkBullet, 0, 0));
  L := Lay(d, 0, 1000);
  AssertTrue('a marker', L.HasMarker);
  m := L.Marker;
  AssertEquals('a bullet', U($2022), m.Text);
  AssertEquals('at the first line''s indent', 24, m.X);
  AssertEquals('its width', 10, m.Width);
  AssertEquals('no characters', 0, m.Count);
  AssertEquals('the text at the left indent', 48, L.CaretRect(0).Left);
  AssertEquals('the line starts there', 48, L.Lines[0].Left);
  AssertEquals('a click on the marker: the first position', 0, L.PosAtPoint(28, 5));
  AssertEquals('the text is the text', 'one', L.Text);
  AssertEquals('three characters and the separator', 4, L.CharCount);
  AssertEquals('the base font', 20, FDevice.FontPixelHeight(m.Font));
  L := Lay(d, 1, 1000);
  AssertEquals('level 1: a white bullet', U($25E6), L.Marker.Text);
  // a number that does not fit before the left indent: the text goes to the next tab stop
  L := Lay(d, 2, 1000);
  AssertEquals('a number from StartAt', '5.', L.Marker.Text);
  AssertEquals('it fits', 48, L.CaretRect(0).Left);
  L := Lay(d, 3, 100);
  AssertEquals('the next item', '6.', L.Marker.Text);
  AssertEquals('at 720 - 150 twips', 38, L.Marker.X);
  AssertEquals('ends at 58, past the indent: the default stop at 96', 96, L.CaretRect(0).Left);
  AssertTrue('wrapped', L.LineCount >= 2);
  AssertEquals('the second line at the left indent', 48, L.Lines[1].Left);
  L := Lay(d, 4, 1000);
  AssertEquals('the first run''s size', 40, FDevice.FontPixelHeight(L.Marker.Font));
  L := Lay(d, 5, 1000);
  AssertFalse('no list, no marker', L.HasMarker);
  AssertEquals('no marker: the text at the indent', 0, L.CaretRect(0).Left);
  // WordPad's own lists (\fi-360\li720, 12 pt): bullets and 1. 2. 3., the text at 48 px
  d := LoadFixture('wp-zh-list.rtf');
  L := Lay(d, 2, 1000);
  AssertEquals('WordPad''s bullet', U($2022), L.Marker.Text);
  AssertEquals('its place', 24, L.Marker.X);
  AssertEquals('WordPad''s text', 48, L.CaretRect(0).Left);
  AssertEquals('in the run''s 12 points', 16, FDevice.FontPixelHeight(L.Marker.Font));
  AssertEquals('WordPad''s second number', '2.', Lay(d, 6, 1000).Marker.Text);
  AssertEquals('and third', '3.', Lay(d, 7, 1000).Marker.Text);
  AssertEquals('the first', '1.', Lay(d, 5, 1000).Marker.Text);
  AssertFalse('the paragraph after the list', Lay(d, 8, 1000).HasMarker);
end;

{ The number is the paragraph's place among the consecutive items of its level and kind: a
  deeper level in between is passed over, a shallower one, another kind on the level or a
  plain paragraph ends the list; StartAt of the list's first item starts it. Laid out last to
  first, so that no number comes from one remembered before. }
procedure TTyRichLayoutTest.TestListNumbersCountTheItemsOfOneLevel;
const
  Want: array[0..16] of string = ('', '1.', '2.', 'a.', 'b.', '3.', 'i.', 'I.', '', '1.',
    'C.', 'D.', '1.', '1.', '2.', '2.', '1.');
var
  d: TTyRichDocument;
  s: UTF8String;
  i: Integer;
  L: TTyParaLayout;

  procedure Item(AIndex: Integer; AKind: TTyListKind; ALevel, AStart: Integer);
  begin
    SetPara(d, AIndex, [pffList, pffLeftIndent, pffFirstIndent],
      ListFormat(AKind, ALevel, AStart));
  end;

begin
  s := '';
  for i := 0 to 16 do s := s + 'p' + IntToStr(i) + #10;
  d := NewDoc(s);
  Item(1, lkDecimal, 0, 1);
  Item(2, lkDecimal, 0, 1);
  Item(3, lkLowerAlpha, 1, 1);
  Item(4, lkLowerAlpha, 1, 1);
  Item(5, lkDecimal, 0, 1);
  Item(6, lkLowerRoman, 1, 1);
  Item(7, lkUpperRoman, 0, 1);
  Item(9, lkDecimal, 0, 1);
  Item(10, lkUpperAlpha, 0, 3);
  Item(11, lkUpperAlpha, 0, 9);
  // one kind on two levels: the outer item ends the inner list, the inner ones are passed
  Item(12, lkDecimal, 0, 1);
  Item(13, lkDecimal, 1, 1);
  Item(14, lkDecimal, 1, 1);
  Item(15, lkDecimal, 0, 1);
  Item(16, lkDecimal, 1, 1);
  for i := 16 downto 0 do
  begin
    L := Lay(d, i, 1000);
    if Want[i] = '' then
      AssertFalse(Format('%d: no marker', [i]), L.HasMarker)
    else
      AssertEquals(Format('%d', [i]), Want[i], L.Marker.Text);
  end;
  FLayouter.Clear;
  for i := 0 to 16 do
  begin
    L := Lay(d, i, 1000);
    if Want[i] <> '' then AssertEquals(Format('%d, first to last', [i]), Want[i], L.Marker.Text);
  end;
end;

{ Letters go on past z as aa, ab, ... (bijective base 26), roman numerals stop at 3999 and
  a number past them, or one below 1, is written as a decimal; nothing loops or raises,
  whatever the number. }
procedure TTyRichLayoutTest.TestAlphaAndRomanNumbersPastTheirRanges;
var
  s: UTF8String;
  i: Integer;
begin
  AssertEquals('a.', TyRichListMarkerText(lkLowerAlpha, 0, 1));
  AssertEquals('z.', TyRichListMarkerText(lkLowerAlpha, 0, 26));
  AssertEquals('aa.', TyRichListMarkerText(lkLowerAlpha, 0, 27));
  AssertEquals('ab.', TyRichListMarkerText(lkLowerAlpha, 0, 28));
  AssertEquals('az.', TyRichListMarkerText(lkLowerAlpha, 0, 52));
  AssertEquals('ba.', TyRichListMarkerText(lkLowerAlpha, 0, 53));
  AssertEquals('zz.', TyRichListMarkerText(lkLowerAlpha, 0, 702));
  AssertEquals('aaa.', TyRichListMarkerText(lkLowerAlpha, 0, 703));
  AssertEquals('AB.', TyRichListMarkerText(lkUpperAlpha, 0, 28));
  AssertEquals('alpha 0', '0.', TyRichListMarkerText(lkLowerAlpha, 0, 0));
  s := TyRichListMarkerText(lkUpperAlpha, 0, High(Int64));
  AssertTrue('the largest: ' + s, (Length(s) >= 2) and (Length(s) <= 15));
  for i := 1 to Length(s) - 1 do AssertTrue('letters', s[i] in ['A'..'Z']);
  AssertEquals('i.', TyRichListMarkerText(lkLowerRoman, 0, 1));
  AssertEquals('iv.', TyRichListMarkerText(lkLowerRoman, 0, 4));
  AssertEquals('ix.', TyRichListMarkerText(lkLowerRoman, 0, 9));
  AssertEquals('xiv.', TyRichListMarkerText(lkLowerRoman, 0, 14));
  AssertEquals('xl.', TyRichListMarkerText(lkLowerRoman, 0, 40));
  AssertEquals('xc.', TyRichListMarkerText(lkLowerRoman, 0, 90));
  AssertEquals('cd.', TyRichListMarkerText(lkLowerRoman, 0, 400));
  AssertEquals('mcmxciv.', TyRichListMarkerText(lkLowerRoman, 0, 1994));
  AssertEquals('MMMCMXCIX.', TyRichListMarkerText(lkUpperRoman, 0, 3999));
  AssertEquals('4000.', TyRichListMarkerText(lkUpperRoman, 0, 4000));
  AssertEquals('roman 0', '0.', TyRichListMarkerText(lkLowerRoman, 0, 0));
  AssertEquals('-2.', TyRichListMarkerText(lkLowerRoman, 0, -2));
  AssertEquals('9223372036854775807.', TyRichListMarkerText(lkUpperRoman, 0, High(Int64)));
  AssertEquals('-5.', TyRichListMarkerText(lkDecimal, 0, -5));
  AssertEquals('a bullet whatever the number', U($2022), TyRichListMarkerText(lkBullet, 0, 77));
  AssertEquals('level 2', U($25AA), TyRichListMarkerText(lkBullet, 2, 0));
  AssertEquals('level 3 starts over', U($2022), TyRichListMarkerText(lkBullet, 3, 0));
  AssertEquals('no list', '', TyRichListMarkerText(lkNone, 0, 1));
end;

{ A list of 100,000 items in a document that parses on demand. Item 50,000 is numbered by
  looking back at most CRichListWalkParas paragraphs - the count starts at the cap - and the
  paragraphs parsed for it are no more than that; the numbers found are remembered, so the
  next item costs one step and one already seen none. An edit above (an item made plain)
  drops the numbers at and after it, and the layouts that showed them: the items after it
  count again from there. }
procedure TTyRichLayoutTest.TestTheNumberingWalkIsCappedAndRemembered;
const
  N = 100000;
var
  d: TTyRichDocument;
  ld: TListLoader;
  s: RawByteString;
  i: Integer;
  steps: Int64;
  L: TTyParaLayout;
  pf: TTyParaFormat;
begin
  SetLength(s, 2 * N - 1);
  for i := 1 to N do
  begin
    s[2 * i - 1] := 'x';
    if i < N then s[2 * i] := #10;
  end;
  d := NewDoc(s);
  ld := TListLoader.Create;
  ld.ParaFmt := d.Formats.InternPara(ListFormat(lkDecimal, 0, 1));
  ld.CharFmt := d.DefaultCharFormatId;
  d.InstallLoader(ld, True);
  d.OnChange := @DocChanged;
  ld.Calls := 0;
  steps := FLayouter.ListWalkSteps;
  L := Lay(d, 50000, 300);
  AssertEquals('50,000: counted from the cap', IntToStr(CRichListWalkParas + 1) + '.',
    L.Marker.Text);
  AssertEquals('it looked back as far as the cap', CRichListWalkParas,
    FLayouter.ListWalkSteps - steps);
  AssertTrue(Format('parsed %d paragraphs', [ld.Calls]), ld.Calls <= CRichListWalkParas + 1);
  steps := FLayouter.ListWalkSteps;
  L := Lay(d, 50001, 300);
  AssertEquals('the next', IntToStr(CRichListWalkParas + 2) + '.', L.Marker.Text);
  AssertEquals('one step', 1, FLayouter.ListWalkSteps - steps);
  steps := FLayouter.ListWalkSteps;
  L := Lay(d, 49990, 300);
  AssertEquals('one seen on the way', IntToStr(CRichListWalkParas - 9) + '.', L.Marker.Text);
  AssertEquals('no step', 0, FLayouter.ListWalkSteps - steps);
  L := Lay(d, 49000, 300);
  AssertEquals('another', IntToStr(CRichListWalkParas + 1 - 1000) + '.', L.Marker.Text);
  AssertEquals('no step either', 0, FLayouter.ListWalkSteps - steps);
  // item 49,990 becomes a plain paragraph
  pf := TyDefaultParaFormat;
  SetPara(d, 49990, [pffList], pf);
  AssertTrue('the numbered layouts after it went', FLayouter.CachedLayout(50001) = nil);
  AssertTrue('and that of 50,000', FLayouter.CachedLayout(50000) = nil);
  AssertTrue('one before it stays', FLayouter.CachedLayout(49000) <> nil);
  steps := FLayouter.ListWalkSteps;
  L := Lay(d, 50001, 300);
  AssertEquals('counted from 49,991', '11.', L.Marker.Text);
  AssertEquals('back to the plain paragraph', 11, FLayouter.ListWalkSteps - steps);
  L := Lay(d, 50000, 300);
  AssertEquals('and 50,000', '10.', L.Marker.Text);
end;

{ ---- 8b: table rows ---- }

{ A row is one block: the paragraphs of all its cells, each cell's laid out by itself at the
  cell's width less the half gap on either side (a table made here: 108 twips, 7 px; a line of
  10 twips, 1 px, on every side), stacked in the cell; the row as tall as its tallest cell
  (its four lines, 80 px, and the top and bottom lines). Any paragraph of the row gives it. }
procedure TTyRichLayoutTest.TestTableCellsLayOutAndRowHeightIsTheTallest;
var
  d: TTyRichDocument;
  t: TTyRichTable;
  B: TTyBlockLayout;
  R: TTyRowLayout;
begin
  d := NewTableDoc('before'#10'a'#10'long long long long'#10'c1'#10'c2'#10'after');
  t := TTyRichTable.Create([1440, 2880, 4320]);
  t.AddRow(3);
  TDocAccess(d).MarkTable(1, t, [1, 1, 2]).Free;
  B := Block(d, 2, 1000);
  AssertTrue('a row', B is TTyRowLayout);
  R := TTyRowLayout(B);
  AssertEquals('its first paragraph', 1, R.FirstPara);
  AssertEquals('its last', 4, R.LastPara);
  AssertEquals('three cells', 3, R.CellCount);
  AssertEquals('four paragraphs', 4, R.ItemCount);
  AssertEquals('cell 1 from 1440 twips', 96, R.Cells[1].Left);
  AssertEquals('to 2880', 192, R.Cells[1].Right);
  AssertEquals('the text inside the half gap', 103, R.Items[1].X);
  AssertEquals('below the top line', 1, R.Items[1].Y);
  AssertEquals('laid out at the cell''s width', 82, R.Items[1].Layout.LayoutWidth);
  AssertEquals('four lines there', 4, R.Items[1].Layout.LineCount);
  AssertEquals('the tallest cell, and its lines', 82, R.Height);
  AssertEquals('the second paragraph of cell 2 below the first', 21, R.Items[3].Y);
  AssertEquals('in cell 2', 2, R.Items[3].Cell);
  AssertEquals('characters of the row, separators included', 28, R.CharCount);
  AssertEquals('positions in text order', 22, R.Items[2].Pos);
  AssertTrue('the same block from its first paragraph', Block(d, 1, 1000) = B);
  AssertTrue('and from its last', Block(d, 4, 1000) = B);
  AssertTrue('a paragraph before it is a paragraph', Block(d, 0, 1000) is TTyParaLayout);
  AssertTrue('and one after it', Block(d, 5, 1000) is TTyParaLayout);
  AssertEquals('the widest cell''s right edge', 288, R.Width);
  // a paragraph inserted before the table: the cached row and its paragraphs follow
  d.OnChange := @DocChanged;
  AssertTrue('inserted', d.Execute(TTyRichInsertText.Create(0, 'x'#10)));
  AssertTrue('the row moved on', FLayouter.CachedLayout(2) = B);
  AssertEquals('its first paragraph', 2, R.FirstPara);
  AssertEquals('and its items''', 2, R.Items[0].Layout.FirstPara);
  AssertEquals('the last', 5, R.Items[3].Layout.LastPara);
end;

{ \trrh: at least so tall (600 twips, 40 px, over one line of text), or exactly (a negative
  height: 600 twips, under four lines); a cell's content placed by its vertical alignment. }
procedure TTyRichLayoutTest.TestARowIsAsTallAsItsFormatDemands;
var
  d: TTyRichDocument;
  t: TTyRichTable;
  R: TTyRowLayout;
begin
  d := NewTableDoc('a'#10'b'#10'long long long long'#10'c');
  t := TTyRichTable.Create([1440, 2880]);
  t.AddRow(2, '\trowd\trgaph108\trrh600\cellx1440\clvertalc\cellx2880');
  t.AddRow(2, '\trowd\trgaph108\trrh-600\cellx1440\clvertalb\cellx2880');
  TDocAccess(d).MarkTable(0, t, [1, 1, 1, 1]).Free;
  R := TTyRowLayout(Block(d, 0, 1000));
  AssertEquals('at least 600 twips', 40, R.Height);
  AssertEquals('no line declared: the text at the top', 0, R.Items[0].Y);
  AssertEquals('the centred cell''s line in the middle', 10, R.Items[1].Y);
  R := TTyRowLayout(Block(d, 2, 1000));
  AssertEquals('four lines in it', 4, R.Items[0].Layout.LineCount);
  AssertEquals('exactly 600 twips', 40, R.Height);
  AssertEquals('the cell at the bottom: its line at the row''s', 20, R.Items[1].Y);
end;

{ Positions run cell after cell, paragraph after paragraph, each paragraph end one character;
  the caret, hit tests and selections take them across the cells. A point in a cell's
  padding or below its text goes to the nearest place in that cell. }
procedure TTyRichLayoutTest.TestPositionsRunAcrossTheCellsOfARow;
var
  d: TTyRichDocument;
  t: TTyRichTable;
  R: TTyRowLayout;
  rc: TRect;
  rs: TRectArray;
  p: Integer;
begin
  d := NewTableDoc('a'#10'long long long long'#10'c1'#10'c2');
  t := TTyRichTable.Create([1440, 2880, 4320]);
  t.AddRow(3);
  TDocAccess(d).MarkTable(0, t, [1, 1, 2]).Free;
  R := TTyRowLayout(Block(d, 0, 1000));
  rc := R.CaretRect(0);
  AssertEquals('cell 0 starts at its text', 7, rc.Left);
  AssertEquals('below the top line', 1, rc.Top);
  rc := R.CaretRect(2);
  AssertEquals('cell 1''s first position', 103, rc.Left);
  rc := R.CaretRect(21);
  AssertEquals('cell 1''s end: on its last line', 61, rc.Top);
  AssertEquals('after "long"', 143, rc.Left);
  rc := R.CaretRect(25);
  AssertEquals('cell 2''s second paragraph', 21, rc.Top);
  AssertEquals('at cell 2''s text', 199, rc.Left);
  AssertEquals('a click in cell 1''s text', 4, R.PosAtPoint(103 + 22, 6));
  AssertEquals('in its left padding', 2, R.PosAtPoint(98, 6));
  AssertEquals('below cell 0''s text: the end of its last line', 1, R.PosAtPoint(20, 70));
  AssertEquals('below cell 2''s text: in its last paragraph', 25, R.PosAtPoint(200, 75));
  AssertEquals('left of the row: cell 0', 0, R.PosAtPoint(-30, 5));
  AssertEquals('right of the row: the last cell', 25 + 2, R.PosAtPoint(900, 30));
  for p := 0 to R.CharCount - 1 do
  begin
    rc := R.CaretRect(p);
    AssertEquals(Format('the caret at %d and the point agree', [p]), p,
      R.PosAtPoint(rc.Left, (rc.Top + rc.Bottom) div 2));
  end;
  // from after "a" (its end selected) to after the "c" of c1
  rs := R.SelectionRects(1, 23);
  AssertEquals('cell 0''s line, cell 1''s four, c1''s', 6, Length(rs));
  AssertTrue('cell 0''s end marked past it', rs[0].Right > 17);
  AssertEquals('c1 from its start', 199, rs[5].Left);
  AssertEquals('to after c', 209, rs[5].Right);
  AssertEquals('in its line', 1, rs[5].Top);
end;

{ The finding of a row's paragraphs reads the row and one paragraph on either side, never the
  table: a table of 2000 one-paragraph cells in a document that parses on demand, a row in
  its middle. }
procedure TTyRichLayoutTest.TestARowIsFoundFromItsOwnParagraphs;
const
  Rows = 1000;
var
  d: TTyRichDocument;
  ld: TTableLoader;
  s: RawByteString;
  i: Integer;
  R: TTyRowLayout;
begin
  SetLength(s, 4 * Rows - 1);
  for i := 1 to 2 * Rows do
  begin
    s[2 * i - 1] := 'x';
    if i < 2 * Rows then s[2 * i] := #10;
  end;
  d := NewTableDoc(s);
  ld := TTableLoader.Create(Rows, 2);
  ld.ParaFmt := d.Formats.InternPara(TyDefaultParaFormat);
  ld.CharFmt := d.DefaultCharFormatId;
  d.InstallLoader(ld, True);
  R := TTyRowLayout(Block(d, 1001, 1000));
  AssertEquals('row 500', 500, R.RowIndex);
  AssertEquals('from paragraph 1000', 1000, R.FirstPara);
  AssertEquals('to 1001', 1001, R.LastPara);
  AssertTrue(Format('parsed %d paragraphs', [ld.Calls]), ld.Calls <= 4);
end;

{ The two merged samples. Word's way written by hand (\clmgf/\clmrg, \clvmgf/\clvmrg, a nested
  table in the last cell of the last row): the first row's first two cells are one box with
  the first cell's text, which no point hits the other's empty paragraph in; the cell that
  continues the one above has no line on top, its neighbours have; the last row closes the
  table; the nested table's paragraphs are stacked in the outer cell. Word's own way (a cell
  across two columns is one wider cell) is a wide box. }
procedure TTyRichLayoutTest.TestMergedCellsAreShownMerged;
var
  d: TTyRichDocument;
  R0, R1, R2: TTyRowLayout;
  f, x, k, hid: Integer;
  p: TTyRichPos;
  rc, er: TRect;

  function FirstCellPara: Integer;
  begin
    Result := 0;
    while d.CellAt(Result) = nil do Inc(Result);
  end;

begin
  d := LoadFixture('hand-word-table-merged.rtf');
  f := FirstCellPara;
  AssertEquals('the table starts at paragraph 1', 1, f);
  R0 := TTyRowLayout(Block(d, f, 1000));
  AssertEquals('row 0', 0, R0.RowIndex);
  AssertEquals('three cells', 3, R0.CellCount);
  AssertEquals('three paragraphs', 3, R0.ItemCount);
  AssertTrue('the second merged into the first', R0.Cells[1].Hidden);
  AssertEquals('into the first', 0, R0.Cells[1].Owner);
  AssertEquals('from \trleft', TyRichTwipsToPx(-108, 96, 1), R0.Cells[0].Left);
  AssertEquals('one box over both columns', TyRichTwipsToPx(5572, 96, 1), R0.Cells[0].Right);
  AssertEquals('the third after them', TyRichTwipsToPx(5572, 96, 1), R0.Cells[2].Left);
  AssertEquals('the first cell''s text laid out across the box',
    TyRichTwipsToPx(5572, 96, 1) - TyRichTwipsToPx(-108, 96, 1) - 2 * TyRichTwipsToPx(108, 96, 1),
    R0.Items[0].Layout.LayoutWidth);
  for x := -20 to R0.Width + 20 do
  begin
    p := R0.PosAtPoint(x, R0.Height div 2);
    AssertFalse(Format('a point at %d lands in a shown cell', [x]),
      R0.Cells[R0.Items[R0.ItemAt(p)].Cell].Hidden);
  end;
  hid := -1;
  for k := 0 to R0.ItemCount - 1 do
    if R0.Items[k].Cell = 1 then hid := k;
  AssertTrue('the merged cell''s paragraph', hid >= 0);
  rc := R0.CaretRect(R0.Items[hid].Pos);
  er := R0.CaretRect(R0.Items[0].Pos + R0.Items[0].Layout.Length);
  AssertEquals('its caret at the end of the box''s text', er.Left, rc.Left);
  AssertEquals('on its line', er.Top, rc.Top);
  AssertEquals('it selects nothing', 0, Length(R0.SelectionRects(R0.Items[hid].Pos,
    R0.Items[hid].Pos + 1)));
  R1 := TTyRowLayout(Block(d, R0.LastPara + 1, 1000));
  AssertEquals('row 1', 1, R1.RowIndex);
  AssertTrue('a vertical merge''s first cell has its top line', rcsTop in R1.Cells[0].Sides);
  AssertFalse('a row above the last does not close the table', rcsBottom in R1.Cells[1].Sides);
  R2 := TTyRowLayout(Block(d, R1.LastPara + 1, 1000));
  AssertEquals('row 2', 2, R2.RowIndex);
  AssertFalse('the cell that continues it: no line toward the cell above',
    rcsTop in R2.Cells[0].Sides);
  AssertTrue('its neighbour has one', rcsTop in R2.Cells[1].Sides);
  AssertTrue('the last row closes the table', rcsBottom in R2.Cells[1].Sides);
  AssertTrue('the last cell closes the row', rcsRight in R2.Cells[2].Sides);
  AssertFalse('a cell before it does not', rcsRight in R2.Cells[1].Sides);
  AssertTrue('a row with a nested table', R2.Table.Rows[R2.RowIndex].HoldsNestedTable);
  AssertEquals('its paragraphs stacked in the outer cell', 3, R2.Cells[2].ItemCount);
  k := R2.Cells[2].FirstItem;
  AssertTrue('one below the other', R2.Items[k + 1].Y > R2.Items[k].Y);
  AssertEquals('in one column', R2.Items[k].X, R2.Items[k + 2].X);
  AssertTrue('the paragraph after the table is a paragraph',
    Block(d, R2.LastPara + 1, 1000) is TTyParaLayout);
  // Word's own merge: the first row has two cells, the first one wider
  d := LoadFixture('word-table-merged.rtf');
  f := FirstCellPara;
  R0 := TTyRowLayout(Block(d, f, 1000));
  AssertEquals('two cells', 2, R0.CellCount);
  AssertFalse('none merged away', R0.Cells[1].Hidden);
  AssertEquals('from \trleft', TyRichTwipsToPx(5, 96, 1), R0.Cells[0].Left);
  AssertEquals('across two columns', TyRichTwipsToPx(5542, 96, 1), R0.Cells[0].Right);
  R1 := TTyRowLayout(Block(d, R0.LastPara + 1, 1000));
  R2 := TTyRowLayout(Block(d, R1.LastPara + 1, 1000));
  AssertTrue('Word''s vertical merge starts with a line', rcsTop in R1.Cells[0].Sides);
  AssertFalse('and continues without one', rcsTop in R2.Cells[0].Sides);
end;

{ A row read from a document that parses on demand keeps its table: after the interval it
  came from was sent back to unparsed (and its table let go of by the document), the row,
  its table and its paragraphs' layouts still answer. Freed memory is poisoned meanwhile. }
procedure TTyRichLayoutTest.TestARowInALazyDocumentSurvivesEviction;
var
  d: TTyRichDocument;
  load: TTyRtfLoad;
  q, i, rows, cells, h: Integer;
  R: TTyRowLayout;
  text0: RawByteString;
begin
  d := LoadLazyRepeated('re-zh-table.rtf');
  load := TyRichRtfLoadOf(d);
  AssertTrue('intervals', load.IntervalCount >= 6);
  q := -1;
  for i := load.IntervalFirstPara(2) to load.IntervalFirstPara(2) + 20 do
    if d.CellAt(i) <> nil then
    begin
      q := i;
      Break;
    end;
  AssertTrue('a table paragraph', q >= 0);
  R := TTyRowLayout(FLayouter.LayoutBlock(d, q, 1000, 96, 1));
  try
    AssertTrue('a row', TTyBlockLayout(R) is TTyRowLayout);
    rows := R.Table.RowCount;
    cells := R.Table.Rows[R.RowIndex].CellCount;
    text0 := R.Items[0].Layout.Text;
    h := R.Height;
    AssertEquals('three by three', 3, rows);
    AssertEquals('three cells', 3, cells);
    BeginPoison;
    try
      for i := 3 to 5 do d.EnsureParsed(load.IntervalFirstPara(i) + 1);
      AssertTrue('the row''s paragraph went back to unparsed',
        TBuilderAccess.Value(d, R.FirstPara) = nil);
      AssertEquals('its table, still', rows, R.Table.RowCount);
      AssertEquals('its row', cells, R.Table.Rows[R.RowIndex].CellCount);
      AssertEquals('its first paragraph', text0, R.Items[0].Layout.Text);
      AssertEquals('its height', h, R.Height);
      AssertEquals('it answers', R.Items[1].Pos, R.PosAtPoint(R.Items[1].X, 3));
    finally
      EndPoison;
    end;
  finally
    R.Release;
  end;
end;

{ The row-format function on WordPad's row, on Word's merged ones and on the edges: words in
  groups passed over, a width before or after the style, \brdrnone taking a side away, a
  border word after \trbrdr* not a cell's, a missing \cellx number. }
procedure TTyRichLayoutTest.TestTheRowFormatIsRead;
var
  r: TTyRowDisplay;
begin
  r := TyRtfRowDisplay('\trowd\trgaph108\trleft5\trbrdrl\brdrs\brdrw10 \trpaddl108' +
    '\clbrdrl\brdrw10\brdrs\clbrdrt\brdrw15\brdrs\clbrdrr\brdrw10\brdrs\clbrdrb\brdrw10\brdrs ' +
    '\cellx2773\clvmgf\clvertalc\clbrdrt\brdrs\brdrw20 \cellx5542 \clmrg\clvmrg\clvertalb' +
    '\clbrdrl\brdrs\brdrnone\clbrdrb\brdrdb\cellx8311');
  AssertEquals('half gap', 108, r.HalfGap);
  AssertEquals('left', 5, r.Left);
  AssertEquals('no height', 0, r.Height);
  AssertEquals('three cells', 3, Length(r.Cells));
  AssertEquals('right edge', 2773, r.Cells[0].Right);
  AssertTrue('all four sides', r.Cells[0].Borders = [rcsLeft, rcsTop, rcsRight, rcsBottom]);
  AssertEquals('a width before the style', 15, r.Cells[0].BorderWidth[rcsTop]);
  AssertEquals('the left one''s width', 10, r.Cells[0].BorderWidth[rcsLeft]);
  AssertTrue('no merge', (r.Cells[0].VMerge = rcmNone) and (r.Cells[0].HMerge = rcmNone));
  AssertTrue('starts a vertical merge', r.Cells[1].VMerge = rcmFirst);
  AssertTrue('centred', r.Cells[1].VAlign = rcvCenter);
  AssertTrue('only its top', r.Cells[1].Borders = [rcsTop]);
  AssertEquals('a width after the style', 20, r.Cells[1].BorderWidth[rcsTop]);
  AssertTrue('merged into the one before', r.Cells[2].HMerge = rcmContinue);
  AssertTrue('continues the one above', r.Cells[2].VMerge = rcmContinue);
  AssertTrue('at the bottom', r.Cells[2].VAlign = rcvBottom);
  AssertTrue('none on the left, a double line below', r.Cells[2].Borders = [rcsBottom]);
  r := TyRtfRowDisplay('\trowd\trrh-400{\*\x\clmgf\cellx1}\clmgf\cellx\cellx-3');
  AssertEquals('an exact height', -400, r.Height);
  AssertEquals('the group passed over: two cells', 2, Length(r.Cells));
  AssertTrue('first of a merge', r.Cells[0].HMerge = rcmFirst);
  AssertFalse('no number: no edge', r.Cells[0].HasRight);
  AssertTrue('a negative edge is an edge', r.Cells[1].HasRight);
  AssertEquals('a negative edge as written', -3, r.Cells[1].Right);
  AssertTrue('no \trgaph: 0', r.HalfGap = 0);
  r := TyRtfRowDisplay('\trowd\cellx-1\cellx');
  AssertTrue('\cellx-1 is an edge at -1', r.Cells[0].HasRight and (r.Cells[0].Right = -1));
  AssertFalse('\cellx alone is none', r.Cells[1].HasRight);
  r := TyRtfRowDisplay('\trowd\clbrdrt\brdrs\trbrdrb\brdrw30\brdrnone \cellx100');
  AssertTrue('after \trbrdrb the words are the row''s', r.Cells[0].Borders = [rcsTop]);
  AssertEquals('and so is the width', 0, r.Cells[0].BorderWidth[rcsTop]);
  r := TyRtfRowDisplay('');
  AssertEquals('nothing: no cells', 0, Length(r.Cells));
  // Word's cell in a table without borders: \brdrtbl on every side is no line
  r := TyRtfRowDisplay('\trowd\trgaph108\trleft-108\clbrdrt\brdrtbl \clbrdrl\brdrtbl ' +
    '\clbrdrb\brdrtbl \clbrdrr\brdrtbl \cltxlrtb\clftsWidth3\clwWidth4788 \cellx4680');
  AssertEquals('Word''s borderless cell', 1, Length(r.Cells));
  AssertTrue('\brdrtbl: no sides', r.Cells[0].Borders = []);
  r := TyRtfRowDisplay('\trowd\clbrdrt\brdrs\brdrtbl\cellx100');
  AssertTrue('\brdrtbl after a style takes the side away', r.Cells[0].Borders = []);
  // a diagonal closes the side before it
  r := TyRtfRowDisplay('\trowd\clbrdrr\brdrnone\cldglu\brdrs\brdrw10 \cellx100' +
    '\clbrdrl\brdrs\brdrw5 \cldgll\brdrw40\brdrdb \cellx200');
  AssertTrue('a diagonal is no right side', r.Cells[0].Borders = []);
  AssertEquals('nor its width', 0, r.Cells[0].BorderWidth[rcsRight]);
  AssertTrue('the left before \cldgll stays', r.Cells[1].Borders = [rcsLeft]);
  AssertEquals('with its own width', 5, r.Cells[1].BorderWidth[rcsLeft]);
  // \binN: its bytes are data, braces included, in a group or not
  r := TyRtfRowDisplay('\trowd{\*\x\bin2 {{}\trleft7\bin3 a{b\cellx200');
  AssertEquals('read past the binary data', 7, r.Left);
  AssertEquals('and its cell', 1, Length(r.Cells));
  AssertEquals('its edge', 200, r.Cells[0].Right);
  r := TyRtfRowDisplay('\trowd\bin999999 ');
  AssertEquals('data past the end: nothing', 0, Length(r.Cells));
  // a centred, a right-aligned row
  r := TyRtfRowDisplay('\trowd\trqc\cellx100');
  AssertTrue('\trqc', r.Align = rraCenter);
  r := TyRtfRowDisplay('\trowd\trqr\cellx100');
  AssertTrue('\trqr', r.Align = rraRight);
  r := TyRtfRowDisplay('\trowd\trqr\trql\cellx100');
  AssertTrue('\trql', r.Align = rraLeft);
  r := TyDefaultRowDisplay(2);
  AssertEquals('a row made here: two cells', 2, Length(r.Cells));
  AssertEquals('Word''s half gap', 108, r.HalfGap);
  AssertTrue('a line on every side', r.Cells[1].Borders = [rcsLeft, rcsTop, rcsRight, rcsBottom]);
  AssertEquals('a thin one', 10, r.Cells[1].BorderWidth[rcsLeft]);
end;

{ ---- 8b: pictures ---- }

{ A picture is decoded the first time it is drawn - never at layout - and kept: drawn again,
  it is not decoded again; drawn at another size it is scaled once to that size and the
  scaled image kept. The cache holds a reference to the picture and lets go of it when it
  is emptied. }
procedure TTyRichLayoutTest.TestPicturesAreDecodedWhenDrawnAndKept;
var
  d: TTyRichDocument;
  pic: TTyRichPicture;
  L: TTyParaLayout;
  bmp: TBGRABitmap;
  st: TTyRichPaintStyle;
  green: TBGRAPixel;
  n: Integer;
begin
  green := BGRA(0, 200, 0, 255);
  st := TyRichDefaultPaintStyle;
  pic := TTyRichPicture.Create(rpfPng, PngBytes(20, 10, green), 300, 150);
  pic.AddRef;
  try
    d := NewDoc('ab');
    AssertTrue('inserted', d.Execute(TTyRichInsertObject.Create(1, pic)));
    L := Lay(d, 0, 1000);
    AssertEquals('20 x 10 px', 20, FragAt(L, 1).Width);
    AssertEquals('laid out, not decoded', 0, FLayouter.PictureDecodes);
    bmp := TBGRABitmap.Create(60, 40, Sentinel);
    try
      AssertTrue('shown', FLayouter.DrawPicture(bmp, pic, Rect(5, 5, 25, 15), 1, st));
      AssertEquals('decoded once', 1, FLayouter.PictureDecodes);
      AssertEquals('at its own size: not scaled', 0, FLayouter.PictureScales);
      AssertTrue('its pixels', SamePx(green, bmp.GetPixel(15, 10)));
      AssertTrue('outside its box the ground', SamePx(Sentinel, bmp.GetPixel(30, 20)));
      FLayouter.DrawPicture(bmp, pic, Rect(5, 5, 25, 15), 1, st);
      AssertEquals('kept: not decoded again', 1, FLayouter.PictureDecodes);
      // twice the size (at 200 %): drawn from the decoded image, no copy made or kept
      AssertTrue('shown larger', FLayouter.DrawPicture(bmp, pic, Rect(0, 0, 40, 20), 1, st));
      AssertEquals('an enlargement is not scaled', 0, FLayouter.PictureScales);
      AssertTrue('its pixels', SamePx(green, bmp.GetPixel(35, 18)));
      FLayouter.DrawPicture(bmp, pic, Rect(10, 10, 50, 30), 1, st);
      AssertEquals('still decoded once', 1, FLayouter.PictureDecodes);
      // half the size: reduced once, and kept at that size
      AssertTrue('shown smaller', FLayouter.DrawPicture(bmp, pic, Rect(0, 0, 10, 5), 1, st));
      AssertEquals('scaled', 1, FLayouter.PictureScales);
      AssertTrue('scaled pixels', SamePx(green, bmp.GetPixel(5, 2)));
      FLayouter.DrawPicture(bmp, pic, Rect(10, 10, 20, 15), 1, st);
      AssertEquals('the same size again: not scaled again', 1, FLayouter.PictureScales);
      AssertEquals('and not decoded again', 1, FLayouter.PictureDecodes);
    finally
      bmp.Free;
    end;
    AssertEquals('one kept', 1, FLayouter.PictureCacheCount);
    n := pic.RefCount;
    FLayouter.Clear;
    AssertEquals('emptied', 0, FLayouter.PictureCacheCount);
    AssertEquals('it let go of the picture', n - 1, pic.RefCount);
  finally
    pic.Release;
  end;
end;

{ At most PictureCacheLimit bytes of decoded and scaled images (and the pictures held for
  them): the least recently drawn go first and are decoded again when drawn again; the one
  drawn last stays even when it alone is over the bound. }
procedure TTyRichLayoutTest.TestThePictureCacheIsBoundedByBytes;
const
  N = 40;
var
  pics: array[0..N - 1] of TTyRichPicture;
  big: TTyRichPicture;
  bmp: TBGRABitmap;
  st: TTyRichPaintStyle;
  i: Integer;
  dec: Int64;
begin
  st := TyRichDefaultPaintStyle;
  AssertEquals('the default bound', CRichPictureCacheBytes, FLayouter.PictureCacheLimit);
  FLayouter.PictureCacheLimit := 64 * 1024;
  for i := 0 to N - 1 do pics[i] := nil;
  big := nil;
  bmp := TBGRABitmap.Create(300, 300, Sentinel);
  try
    for i := 0 to N - 1 do
    begin
      pics[i] := TTyRichPicture.Create(rpfPng, PngBytes(32, 32, BGRA(i * 6, 0, 0, 255)), 480, 480);
      pics[i].AddRef;
      AssertTrue('shown', FLayouter.DrawPicture(bmp, pics[i], Rect(0, 0, 32, 32), 1, st));
      AssertTrue(Format('%d bytes kept', [FLayouter.PictureCacheBytes]),
        FLayouter.PictureCacheBytes <= FLayouter.PictureCacheLimit);
    end;
    AssertEquals('each decoded once', N, FLayouter.PictureDecodes);
    AssertTrue(Format('%d kept', [FLayouter.PictureCacheCount]),
      (FLayouter.PictureCacheCount >= 8) and (FLayouter.PictureCacheCount < N));
    dec := FLayouter.PictureDecodes;
    FLayouter.DrawPicture(bmp, pics[N - 1], Rect(0, 0, 32, 32), 1, st);
    AssertEquals('the newest is kept', dec, FLayouter.PictureDecodes);
    FLayouter.DrawPicture(bmp, pics[0], Rect(0, 0, 32, 32), 1, st);
    AssertEquals('the oldest went: decoded again', dec + 1, FLayouter.PictureDecodes);
    AssertEquals('the pictures that went were let go of', 1, pics[1].RefCount);
    big := TTyRichPicture.Create(rpfPng, PngBytes(256, 256, BGRABlack), 3840, 3840);
    big.AddRef;
    AssertTrue('a picture over the bound', FLayouter.DrawPicture(bmp, big, Rect(0, 0, 256, 256),
      1, st));
    AssertEquals('it alone stays', 1, FLayouter.PictureCacheCount);
    AssertEquals('held', 2, big.RefCount);
  finally
    bmp.Free;
    for i := 0 to N - 1 do
      if pics[i] <> nil then pics[i].Release;
    if big <> nil then big.Release;
  end;
end;

{ What cannot be shown is a placeholder of the box - filled, framed ALinePx thick - and never
  raises: bytes that do not decode (tried once, not on every paint), a metafile that draws
  more than one bitmap, an EMF, no bytes at all. }
procedure TTyRichLayoutTest.TestPicturesThatCannotBeShownArePlaceholders;
var
  bmp: TBGRABitmap;
  st: TTyRichPaintStyle;
  broken, emf, wmf, empty: TTyRichPicture;
  fill, frame: TBGRAPixel;
begin
  st := TyRichDefaultPaintStyle;
  fill := BGRA(1, 2, 3, 255);
  frame := BGRA(4, 5, 6, 255);
  st.PlaceholderFill := fill;
  st.PlaceholderFrame := frame;
  broken := TTyRichPicture.Create(rpfPng, ByteArray([$89, $50, $4E, $47, $0D, $0A, 1, 2, 3]),
    300, 300);
  emf := TTyRichPicture.Create(rpfEmf, ByteArray([1, 0, 0, 0, 88, 0, 0, 0]), 300, 300);
  // a metafile that draws a line: its header, LineTo(10, 10), the end record
  wmf := TTyRichPicture.Create(rpfWmf, ByteArray([1, 0, 9, 0, 0, 3, 17, 0, 0, 0, 0, 0, 5, 0,
    0, 0, 0, 0, 5, 0, 0, 0, $13, $02, 10, 0, 10, 0, 3, 0, 0, 0, 0, 0]), 300, 300);
  empty := TTyRichPicture.Create(rpfPng, nil, 300, 300);
  broken.AddRef;
  emf.AddRef;
  wmf.AddRef;
  empty.AddRef;
  bmp := TBGRABitmap.Create(40, 40, Sentinel);
  try
    AssertFalse('bytes that do not decode', FLayouter.DrawPicture(bmp, broken,
      Rect(5, 5, 25, 25), 2, st));
    AssertTrue('filled', SamePx(fill, bmp.GetPixel(15, 15)));
    AssertTrue('framed', SamePx(frame, bmp.GetPixel(5, 15)));
    AssertTrue('two pixels thick', SamePx(frame, bmp.GetPixel(6, 15)));
    AssertTrue('and no more', SamePx(fill, bmp.GetPixel(7, 15)));
    AssertTrue('the bottom', SamePx(frame, bmp.GetPixel(15, 24)));
    AssertTrue('outside it the ground', SamePx(Sentinel, bmp.GetPixel(30, 30)));
    AssertEquals('tried', 1, FLayouter.PictureDecodes);
    AssertFalse('again', FLayouter.DrawPicture(bmp, broken, Rect(5, 5, 25, 25), 2, st));
    AssertEquals('not tried again', 1, FLayouter.PictureDecodes);
    bmp.FillRect(0, 0, 40, 40, Sentinel, dmSet);
    AssertFalse('an EMF', FLayouter.DrawPicture(bmp, emf, Rect(5, 5, 25, 25), 1, st));
    AssertTrue('its placeholder', SamePx(fill, bmp.GetPixel(15, 15)));
    AssertFalse('a metafile with a line', FLayouter.DrawPicture(bmp, wmf, Rect(5, 5, 25, 25),
      1, st));
    AssertFalse('no bytes', FLayouter.DrawPicture(bmp, empty, Rect(5, 5, 25, 25), 1, st));
    AssertEquals('nothing to decode in them', 1, FLayouter.PictureDecodes);
  finally
    bmp.Free;
    broken.Release;
    emf.Release;
    wmf.Release;
    empty.Release;
  end;
end;

{ WordPad saves every picture as a metafile holding one DIB (wp-zh-picture.rtf): it shows as
  that bitmap, not a placeholder. }
procedure TTyRichLayoutTest.TestTheWordPadPictureShowsItsBitmap;
var
  d: TTyRichDocument;
  runs: TTyRunArray;
  i, j, q, x, y, shown: Integer;
  pic: TTyRichPicture;
  L: TTyParaLayout;
  fr: TTyRichFragment;
  bmp: TBGRABitmap;
  st: TTyRichPaintStyle;
  fmt: TTyRichPictureFormat;
  a, c: Integer;
  px: TBGRAPixel;
begin
  st := TyRichDefaultPaintStyle;
  d := LoadFixture('wp-zh-picture.rtf');
  pic := nil;
  q := -1;
  for i := 0 to d.Text.ParaCount - 1 do
  begin
    runs := d.RunsOf(i);
    for j := 0 to High(runs) do
      if (pic = nil) and (runs[j].Obj is TTyRichPicture) then
      begin
        pic := TTyRichPicture(runs[j].Obj);
        q := i;
      end;
  end;
  AssertTrue('a picture', pic <> nil);
  AssertTrue('a metafile', pic.PictureFormat = rpfWmf);
  AssertTrue('with one bitmap', pic.DisplayData(fmt, a, c) and (fmt = rpfDib));
  L := Lay(d, q, 4000);
  fr.Width := 0;
  for i := 0 to L.FragmentCount - 1 do
    if L.Fragments[i].Obj = pic then fr := L.Fragments[i];
  AssertTrue('its box', (fr.Width > 0) and (fr.Ascent > 0));
  bmp := TBGRABitmap.Create(fr.Width, fr.Ascent, Sentinel);
  try
    AssertTrue('shown', FLayouter.DrawPicture(bmp, pic, Rect(0, 0, fr.Width, fr.Ascent), 1, st));
    AssertEquals('decoded', 1, FLayouter.PictureDecodes);
    shown := 0;
    for y := 0 to bmp.Height - 1 do
      for x := 0 to bmp.Width - 1 do
      begin
        px := bmp.GetPixel(x, y);
        if not SamePx(Sentinel, px) and not SamePx(st.PlaceholderFill, px) then Inc(shown);
      end;
    AssertTrue(Format('%d of %d pixels its own', [shown, bmp.Width * bmp.Height]),
      shown >= bmp.Width * bmp.Height * 9 div 10);
  finally
    bmp.Free;
  end;
  { At the DIB's own size (96 x 64, 24-bit, bottom-up), known pixels of the fixture's bitmap,
    read from its bits: a grey frame, a light ground, a steel-blue box at the top left, a
    gold one at the bottom right. A wrong bits offset or rows the wrong way up misses them. }
  bmp := TBGRABitmap.Create(96, 64, Sentinel);
  try
    AssertTrue('shown at its own size', FLayouter.DrawPicture(bmp, pic, Rect(0, 0, 96, 64), 1, st));
    AssertTrue('the frame', SamePx(BGRA(105, 105, 105, 255), bmp.GetPixel(0, 0)));
    AssertTrue('the ground', SamePx(BGRA(240, 244, 250, 255), bmp.GetPixel(4, 4)));
    AssertTrue('the blue box, top left', SamePx(BGRA(70, 130, 180, 255), bmp.GetPixel(20, 16)));
    AssertTrue('the gold box, bottom right', SamePx(BGRA(218, 165, 32, 255), bmp.GetPixel(70, 44)));
    AssertTrue('the ground under the blue box', SamePx(BGRA(240, 244, 250, 255),
      bmp.GetPixel(20, 40)));
  finally
    bmp.Free;
  end;
end;

{ ---- 8b: painting ---- }

{ Each text fragment is drawn once, as measured, at its measured place (the device's draw log:
  text, X, baseline); only the lines a clip meets are drawn, and on a line only the fragments
  it meets. }
procedure TTyRichLayoutTest.TestPaintDrawsOnlyWhatMeetsTheClip;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  bmp: TBGRABitmap;
  st: TTyRichPaintStyle;
begin
  st := TyRichDefaultPaintStyle;
  d := NewDoc('one two three four five six seven eight nine ten eleven twelve'#10 +
    'a'#9'b'#9'c'#9'd'#9'e'#9'f');
  L := Lay(d, 0, 60);
  AssertEquals('a word a line', 12, L.LineCount);
  bmp := TBGRABitmap.Create(100, 300, Sentinel);
  try
    FDevice.DrawLog.Clear;
    L.Paint(bmp, 10, 5, Rect(0, 0, 100, 300), st, 0, 0);
    AssertEquals('every line''s word, its spaces not drawn', 12, FDevice.DrawLog.Count);
    AssertEquals('at its measured place', 'one|10|21', FDevice.DrawLog[0]);
    AssertEquals('the last', 'twelve|10|241', FDevice.DrawLog[11]);
    FDevice.DrawLog.Clear;
    L.Paint(bmp, 10, 5, Rect(0, 65, 100, 105), st, 0, 0);
    AssertEquals('the clip meets lines 3 and 4', 'four|10|81,five|10|101',
      FDevice.DrawLog.CommaText);
    FDevice.DrawLog.Clear;
    L.Paint(bmp, 10, 5, Rect(0, 64, 100, 65), st, 0, 0);
    AssertEquals('one pixel of line 2', 'three|10|61', FDevice.DrawLog.CommaText);
    FDevice.DrawLog.Clear;
    L.Paint(bmp, 10, 5, Rect(0, 250, 100, 300), st, 0, 0);
    AssertEquals('below the text: nothing', 0, FDevice.DrawLog.Count);
  finally
    bmp.Free;
  end;
  L := Lay(d, 1, 1000);
  bmp := TBGRABitmap.Create(400, 40, Sentinel);
  try
    FDevice.DrawLog.Clear;
    L.Paint(bmp, 0, 0, Rect(0, 0, 60, 40), st, 0, 0);
    AssertEquals('the fragments the clip meets', 'a|0|16,b|48|16', FDevice.DrawLog.CommaText);
  finally
    bmp.Free;
  end;
end;

{ Selected text in the selection's text colour over its background; a fragment selected in
  part is drawn whole, once a part, each clipped to its part - no glyph moves (the ink columns
  are the columns unselected), and the parts left and right of the selection stay as they
  were. A fully selected fragment is drawn once. }
procedure TTyRichLayoutTest.TestPaintSelectionKeepsTheGlyphsInPlace;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  b1, b2: TBGRABitmap;
  st: TTyRichPaintStyle;
  x: Integer;
  p1, p2: TBGRAPixel;
begin
  st := TyRichDefaultPaintStyle;
  st.TextColor := BGRA(0, 0, 200, 255);
  st.SelectionText := BGRA(200, 0, 0, 255);
  st.SelectionBack := BGRA(0, 200, 0, 255);
  d := NewDoc('abcdef');
  L := Lay(d, 0, 300);
  b1 := TBGRABitmap.Create(80, 30, Sentinel);
  b2 := TBGRABitmap.Create(80, 30, Sentinel);
  try
    L.Paint(b1, 0, 0, Rect(0, 0, 80, 30), st, 0, 0);
    FDevice.ResetCounters;
    L.Paint(b2, 0, 0, Rect(0, 0, 80, 30), st, 2, 4);
    AssertEquals('drawn in three parts', 3, FDevice.DrawCalls);
    AssertTrue('a: the text colour', SamePx(st.TextColor, b2.GetPixel(5, 8)));
    AssertTrue('c: selected', SamePx(st.SelectionText, b2.GetPixel(25, 8)));
    AssertTrue('d: selected', SamePx(st.SelectionText, b2.GetPixel(35, 8)));
    AssertTrue('e: not', SamePx(st.TextColor, b2.GetPixel(45, 8)));
    AssertTrue('between c and d: the selection''s ground', SamePx(st.SelectionBack,
      b2.GetPixel(30, 8)));
    AssertTrue('between b and c: still the selection', SamePx(st.SelectionBack, b2.GetPixel(20, 8)));
    AssertTrue('between a and b: the ground', SamePx(Sentinel, b2.GetPixel(10, 8)));
    for x := 0 to 79 do
    begin
      p1 := b1.GetPixel(x, 8);
      p2 := b2.GetPixel(x, 8);
      AssertEquals(Format('ink at column %d where it was', [x]), SamePx(st.TextColor, p1),
        SamePx(st.TextColor, p2) or SamePx(st.SelectionText, p2));
    end;
    FDevice.ResetCounters;
    L.Paint(b2, 0, 0, Rect(0, 0, 80, 30), st, 0, 7);
    AssertEquals('all of it: drawn once', 1, FDevice.DrawCalls);
    AssertTrue('in the selection''s colour', SamePx(st.SelectionText, b2.GetPixel(5, 8)));
    AssertTrue('the separator''s mark', SamePx(st.SelectionBack, b2.GetPixel(61, 8)));
  finally
    b1.Free;
    b2.Free;
  end;
end;

{ The real device: a line painted with part of it selected, in the same colours as unselected
  (the selection's ground the ground, its text colour the text's), is the same pixels - the
  parts are the same glyphs at the same places, cut by the clip, not text measured and drawn
  again; in a selection colour of its own the selected glyphs change colour and the rest
  does not. }
procedure TTyRichLayoutTest.TestPaintedSelectionDoesNotMoveGlyphsOnTheRealDevice;
var
  dev: TTyRichBgraDevice;
  lo: TTyRichLayouter;
  d: TTyRichDocument;
  L: TTyParaLayout;
  b1, b2: TBGRABitmap;
  st: TTyRichPaintStyle;
  x, y, diff, xa, xb, redIn, redOut: Integer;
  p: TBGRAPixel;
  rc: TRect;
begin
  dev := TTyRichBgraDevice.Create;
  lo := TTyRichLayouter.Create(dev, True);
  b1 := nil;
  b2 := nil;
  try
    {$IFDEF MSWINDOWS}
    lo.BaseFontName := 'Arial';
    {$ENDIF}
    lo.BaseFontSizeHalfPt := 24;
    d := NewDoc('Wavy AVATAR Typography, kerned: To WA 中文字');
    L := lo.LayoutPara(d, 0, 2000, 96, 1);
    try
      st := TyRichDefaultPaintStyle;
      st.TextColor := BGRABlack;
      st.SelectionText := BGRABlack;
      st.SelectionBack := Sentinel;
      b1 := TBGRABitmap.Create(L.Width + 20, L.Height + 10, Sentinel);
      b2 := TBGRABitmap.Create(L.Width + 20, L.Height + 10, Sentinel);
      L.Paint(b1, 5, 5, Rect(0, 0, b1.Width, b1.Height), st, 0, 0);
      L.Paint(b2, 5, 5, Rect(0, 0, b2.Width, b2.Height), st, 7, 30);
      diff := 0;
      for y := 0 to b1.Height - 1 do
        for x := 0 to b1.Width - 1 do
          if not SamePx(b1.GetPixel(x, y), b2.GetPixel(x, y)) then Inc(diff);
      AssertEquals('the same pixels', 0, diff);
      // a red selection: the selected stretch changes, nothing outside it
      st.SelectionText := BGRA(255, 0, 0, 255);
      b2.FillRect(0, 0, b2.Width, b2.Height, Sentinel, dmSet);
      L.Paint(b2, 5, 5, Rect(0, 0, b2.Width, b2.Height), st, 7, 30);
      rc := L.CaretRect(7);
      xa := rc.Left + 5;
      rc := L.CaretRect(30);
      xb := rc.Left + 5;
      redIn := 0;
      redOut := 0;
      for y := 0 to b2.Height - 1 do
        for x := 0 to b2.Width - 1 do
        begin
          p := b2.GetPixel(x, y);
          if not SamePx(b1.GetPixel(x, y), p) then
            if (x >= xa) and (x < xb) then Inc(redIn) else Inc(redOut);
        end;
      AssertTrue(Format('the selected glyphs change colour: %d pixels', [redIn]), redIn > 50);
      AssertEquals('nothing outside the selection changes', 0, redOut);
    finally
      L.Release;
    end;
  finally
    b1.Free;
    b2.Free;
    lo.Free;
  end;
end;

{ A highlight fills its fragments' line box, under the text; underline and strike-through
  are drawn across their fragments (their thickness and place from the font's size: at
  20 px a line of 1 pixel 2 below the baseline, and 6 above it), not across the others. }
procedure TTyRichLayoutTest.TestPaintHighlightUnderlineAndStrike;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  bmp: TBGRABitmap;
  st: TTyRichPaintStyle;
  f: TTyCharFormat;
  yellow: TBGRAPixel;
begin
  st := TyRichDefaultPaintStyle;
  st.TextColor := BGRA(0, 0, 200, 255);
  yellow := ColorToBGRA(ColorToRGB(clYellow));
  d := NewDoc('abc def');
  f := TyDefaultCharFormat;
  f.HighlightColor := clYellow;
  f.Style := [fsUnderline];
  SetChar(d, 0, 3, [cffHighlight, cffUnderline], f);
  f := TyDefaultCharFormat;
  f.Strike := True;
  SetChar(d, 4, 3, [cffStrike], f);
  L := Lay(d, 0, 300);
  bmp := TBGRABitmap.Create(100, 30, Sentinel);
  try
    L.Paint(bmp, 0, 0, Rect(0, 0, 100, 30), st, 0, 0);
    AssertTrue('the highlight between glyphs', SamePx(yellow, bmp.GetPixel(0, 2)));
    AssertTrue('to the bottom of the line', SamePx(yellow, bmp.GetPixel(10, 19)));
    AssertTrue('a glyph over it', SamePx(st.TextColor, bmp.GetPixel(5, 8)));
    AssertTrue('the space after it: no highlight', SamePx(Sentinel, bmp.GetPixel(32, 2)));
    AssertTrue('underlined: 2 below the baseline', SamePx(st.TextColor, bmp.GetPixel(0, 18)));
    AssertTrue('one pixel thick', SamePx(yellow, bmp.GetPixel(0, 19)));
    AssertTrue('the space is not underlined', SamePx(Sentinel, bmp.GetPixel(32, 18)));
    AssertTrue('struck: 6 above the baseline', SamePx(st.TextColor, bmp.GetPixel(35, 10)));
    AssertTrue('not above that', SamePx(Sentinel, bmp.GetPixel(35, 9)));
    AssertTrue('nor under the struck word', SamePx(Sentinel, bmp.GetPixel(35, 18)));
    AssertTrue('nothing struck in the first word', SamePx(yellow, bmp.GetPixel(10, 10)));
  finally
    bmp.Free;
  end;
end;

{ A tab's leader across the tab (dots every quarter of the font, a line), and a list item's
  marker where the layout put it, on the first line's baseline. }
procedure TTyRichLayoutTest.TestPaintTabLeadersAndTheMarker;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  bmp: TBGRABitmap;
  st: TTyRichPaintStyle;
  pf: TTyParaFormat;
  x, ink: Integer;
begin
  st := TyRichDefaultPaintStyle;
  d := NewDoc('a'#9'b'#10'a'#9'b'#10'x');
  pf := TyDefaultParaFormat;
  SetLength(pf.Tabs, 1);
  pf.Tabs[0].Position := 1440;
  pf.Tabs[0].Align := ttaLeft;
  pf.Tabs[0].Leader := ttlDot;
  SetPara(d, 0, [pffTabs], pf);
  pf.Tabs[0].Leader := ttlUnderline;
  SetPara(d, 1, [pffTabs], pf);
  SetPara(d, 2, [pffList, pffLeftIndent, pffFirstIndent], ListFormat(lkBullet, 0, 0));
  bmp := TBGRABitmap.Create(200, 30, Sentinel);
  try
    L := Lay(d, 0, 1000);
    L.Paint(bmp, 0, 0, Rect(0, 0, 200, 30), st, 0, 0);
    ink := 0;
    for x := 10 to 95 do
      if SamePx(st.TextColor, bmp.GetPixel(x, 15)) then Inc(ink);
    AssertEquals('dots every 5 pixels from 10 to 95', 18, ink);
    AssertTrue('a gap between them', SamePx(Sentinel, bmp.GetPixel(11, 15)));
    AssertTrue('not after the tab', SamePx(Sentinel, bmp.GetPixel(96, 15)));
    bmp.FillRect(0, 0, 200, 30, Sentinel, dmSet);
    L := Lay(d, 1, 1000);
    L.Paint(bmp, 0, 0, Rect(0, 0, 200, 30), st, 0, 0);
    ink := 0;
    for x := 10 to 95 do
      if SamePx(st.TextColor, bmp.GetPixel(x, 18)) then Inc(ink);
    AssertEquals('a line across the tab', 86, ink);
    L := Lay(d, 2, 1000);
    FDevice.DrawLog.Clear;
    L.Paint(bmp, 3, 4, Rect(0, 0, 200, 30), st, 0, 0);
    AssertEquals('the marker, then nothing else but the text', 'x|51|20,' + U($2022) + '|27|20',
      FDevice.DrawLog.CommaText);
  finally
    bmp.Free;
  end;
end;

{ A row paints its cells' paragraphs, each where the row put it and clipped to its cell's box,
  and then its lines over them; a clip that meets one cell paints that cell. The hand-written
  Word merge: the cell that continues the one above has no line on top. }
procedure TTyRichLayoutTest.TestPaintARowsContentsThenItsLines;
var
  d: TTyRichDocument;
  t: TTyRichTable;
  R: TTyRowLayout;
  bmp: TBGRABitmap;
  st: TTyRichPaintStyle;
  x0: Integer;
begin
  st := TyRichDefaultPaintStyle;
  st.TableBorder := BGRA(0, 0, 255, 255);
  d := NewTableDoc('a'#10'b'#10'c');
  t := TTyRichTable.Create([1440, 2880, 4320]);
  t.AddRow(3);
  TDocAccess(d).MarkTable(0, t, [1, 1, 1]).Free;
  R := TTyRowLayout(Block(d, 0, 1000));
  bmp := TBGRABitmap.Create(400, 60, Sentinel);
  try
    FDevice.DrawLog.Clear;
    R.Paint(bmp, 10, 10, Rect(0, 0, 400, 60), st, 0, 0);
    AssertEquals('the cells'' text', 'a|17|27,b|113|27,c|209|27', FDevice.DrawLog.CommaText);
    AssertTrue('the top line', SamePx(st.TableBorder, bmp.GetPixel(60, 10)));
    AssertTrue('a cell''s left line', SamePx(st.TableBorder, bmp.GetPixel(106, 20)));
    AssertTrue('drawn once: the cell before has no right line', SamePx(Sentinel,
      bmp.GetPixel(105, 20)));
    AssertTrue('the last cell''s right line', SamePx(st.TableBorder, bmp.GetPixel(297, 20)));
    AssertTrue('the bottom line', SamePx(st.TableBorder, bmp.GetPixel(60, 10 + R.Height - 1)));
    AssertTrue('inside: the ground', SamePx(Sentinel, bmp.GetPixel(60, 30)));
    FDevice.DrawLog.Clear;
    R.Paint(bmp, 10, 10, Rect(110, 0, 200, 60), st, 0, 0);
    AssertEquals('a clip in cell 1: its text only', 'b|113|27', FDevice.DrawLog.CommaText);
  finally
    bmp.Free;
  end;
  d := LoadFixture('hand-word-table-merged.rtf');
  R := TTyRowLayout(Block(d, 1, 1000));
  R := TTyRowLayout(Block(d, R.LastPara + 1, 1000));
  R := TTyRowLayout(Block(d, R.LastPara + 1, 1000));
  AssertEquals('the last row', 2, R.RowIndex);
  bmp := TBGRABitmap.Create(R.Width + 40, R.Height + 20, Sentinel);
  try
    R.Paint(bmp, 20, 10, Rect(0, 0, bmp.Width, bmp.Height), st, 0, 0);
    x0 := 20 + (R.Cells[0].Left + R.Cells[0].Right) div 2;
    AssertTrue('no line on top of the continued cell', SamePx(Sentinel, bmp.GetPixel(x0, 10)));
    x0 := 20 + (R.Cells[1].Left + R.Cells[1].Right) div 2;
    AssertTrue('its neighbour''s', SamePx(st.TableBorder, bmp.GetPixel(x0, 10)));
    AssertTrue('the continued cell''s left line', SamePx(st.TableBorder,
      bmp.GetPixel(20 + R.Cells[0].Left, 15)));
  finally
    bmp.Free;
  end;
end;

{ Pictures drawn in a paint are decoded then, and only those the clip meets; a selected
  picture gets the object frame. }
procedure TTyRichLayoutTest.TestPaintDecodesOnlyThePicturesItDraws;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  bmp: TBGRABitmap;
  st: TTyRichPaintStyle;
  i: Integer;
  pic: TTyRichPicture;
  fr: TTyRichFragment;
begin
  st := TyRichDefaultPaintStyle;
  st.ObjectFrame := BGRA(0, 255, 0, 255);
  d := NewDoc('          ');
  for i := 9 downto 0 do
  begin
    pic := TTyRichPicture.Create(rpfPng, PngBytes(20, 10, BGRA(i * 20, 0, 100, 255)), 300, 150);
    AssertTrue('inserted', d.Execute(TTyRichInsertObject.Create(i, pic)));
  end;
  L := Lay(d, 0, 25);
  AssertEquals('a picture a line', 10, L.LineCount);
  AssertEquals('not decoded at layout', 0, FLayouter.PictureDecodes);
  bmp := TBGRABitmap.Create(60, 220, Sentinel);
  try
    L.Paint(bmp, 0, 0, Rect(0, 0, 60, 40), st, 0, 0);
    AssertEquals('the two lines the clip meets', 2, FLayouter.PictureDecodes);
    L.Paint(bmp, 0, 0, Rect(0, 0, 60, 220), st, 0, 0);
    AssertEquals('then all of them', 10, FLayouter.PictureDecodes);
    fr := FragAt(L, 2);
    L.Paint(bmp, 0, 0, Rect(0, 0, 60, 220), st, 2, 3);
    AssertTrue('the selected one framed', SamePx(st.ObjectFrame,
      bmp.GetPixel(fr.X, L.Lines[1].Baseline - fr.Ascent)));
    AssertFalse('the others not', SamePx(st.ObjectFrame,
      bmp.GetPixel(fr.X, L.Lines[0].Baseline - fr.Ascent)));
  finally
    bmp.Free;
  end;
  // two on one line, a clip that meets the first
  d := NewDoc(' ');
  for i := 1 downto 0 do
  begin
    pic := TTyRichPicture.Create(rpfPng, PngBytes(20, 10, BGRA(0, i * 200, 100, 255)), 300, 150);
    AssertTrue('inserted', d.Execute(TTyRichInsertObject.Create(i, pic)));
  end;
  L := Lay(d, 0, 1000);
  AssertEquals('on one line', 1, L.LineCount);
  bmp := TBGRABitmap.Create(60, 30, Sentinel);
  try
    FLayouter.Clear;
    L.Paint(bmp, 0, 0, Rect(0, 0, 15, 30), st, 0, 0);
    AssertEquals('the one the clip meets', 11, FLayouter.PictureDecodes);
  finally
    bmp.Free;
  end;
end;

{ ---- the review's findings (fix wave W1) ---- }

{ A decimal tab puts the point at its stop also when the point is not in the number's first
  piece: after a space ("1 234.5", a thousands separator) and after a break opportunity
  ("中12.5"). The line's merged fragment is measured up to the point as one string. }
procedure TTyRichLayoutTest.TestADecimalTabFindsThePointInALaterPiece;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  pf: TTyParaFormat;
  i: Integer;
begin
  d := NewDoc('a'#9'1 234.5'#10'a'#9'中12.5'#10'a'#9'12.5');
  pf := TyDefaultParaFormat;
  SetLength(pf.Tabs, 1);
  pf.Tabs[0].Position := 2880;
  pf.Tabs[0].Align := ttaDecimal;
  pf.Tabs[0].Leader := ttlNone;
  for i := 0 to 2 do SetPara(d, i, [pffTabs], pf);
  // "1 234" is 45 px: the text starts 45 px left of the stop (192 px)
  L := Lay(d, 0, 400);
  AssertEquals('a space before the point: where the text starts', 147, FragAt(L, 2).X);
  AssertEquals('the point at the stop', 192, L.CaretRect(7).Left);
  // "中12" is 40 px
  L := Lay(d, 1, 400);
  AssertEquals('the point in a later piece: where the text starts', 152, FragAt(L, 2).X);
  AssertEquals('its point at the stop', 192, L.CaretRect(5).Left);
  L := Lay(d, 2, 400);
  AssertEquals('one piece: the point at the stop', 192, L.CaretRect(4).Left);
end;

{ A point on a line, handed to PosAtPoint, gives a position and a flag whose caret is on that
  line, at the caret place nearest the point - every pixel across every line, past their ends
  included: wrapped Latin, wrapped Chinese (the place after a line's last character is one),
  justified lines of both, lines that U+000B ends (no flag there: the U+000B is a character)
  and the paragraph's end; the flag is set exactly at the end of a wrapped line. A row passes
  it through to its cell's paragraph. }
procedure TTyRichLayoutTest.TestAPointAtALineEndGivesACaretThere;
var
  d, td: TTyRichDocument;
  L: TTyParaLayout;
  pf: TTyParaFormat;
  t: TTyRichTable;
  row: TTyRowLayout;
  para, ln, x, y, p, q, best, places, lastPos: Integer;
  atEnd: Boolean;
  r: TRect;
  xs: array of Integer;
  s: UTF8String;
begin
  s := '';
  for p := 1 to 30 do s := s + U($4E00 + Cardinal(p));
  d := NewDoc('hello world foo bar baz qux'#10'中文中文中文中文'#10 +
    'The quick 中文字 brown fox jumps over the lazy dog again and again'#10 + s + #10 +
    'ab'#11'cd'#11'ef'#10'hello   world   x');
  pf := TyDefaultParaFormat;
  pf.Align := paraJustify;
  SetPara(d, 2, [pffAlign], pf);
  SetPara(d, 3, [pffAlign], pf);
  // the review's two cases
  L := Lay(d, 0, 120);
  q := L.PosAtPoint(119, 5, atEnd);
  AssertEquals('past "hello world ": its end', 12, q);
  AssertTrue('at the line''s end', atEnd);
  r := L.CaretRect(q, atEnd);
  AssertEquals('the caret on the first line', 0, r.Top);
  AssertEquals('after its space', 110, r.Left);
  AssertEquals('without the flag: the next line''s start', 20, L.CaretRect(q).Top);
  L := Lay(d, 1, 70);
  q := L.PosAtPoint(55, 5, atEnd);
  AssertEquals('the right half of the third character: after it', 3, q);
  AssertTrue('the end of the first line', atEnd);
  r := L.CaretRect(q, atEnd);
  AssertEquals('shown there', 0, r.Top);
  AssertEquals('after the character', 60, r.Left);
  for para := 0 to 5 do
  begin
    case para of
      0: L := Lay(d, 0, 120);
      1: L := Lay(d, 1, 70);
      2: L := Lay(d, 2, 150);
      3: L := Lay(d, 3, 150);
      4: L := Lay(d, 4, 1000);
    else
      L := Lay(d, 5, 60);
    end;
    AssertTrue(Format('paragraph %d has lines', [para]), (para = 4) or (L.LineCount > 1));
    for ln := 0 to L.LineCount - 1 do
    begin
      // the line's caret places, its end with the flag (a wrapped line) or before its U+000B
      lastPos := L.Lines[ln].First + L.Lines[ln].Count - Ord(L.Lines[ln].Forced);
      places := lastPos - L.Lines[ln].First + 1;
      SetLength(xs, places);
      for p := 0 to places - 1 do
      begin
        r := L.CaretRect(L.Lines[ln].First + p, (p = places - 1) and not L.Lines[ln].Forced);
        AssertEquals(Format('paragraph %d line %d: place %d is on it', [para, ln, p]),
          L.Lines[ln].Top, r.Top);
        xs[p] := r.Left;
      end;
      y := L.Lines[ln].Top + L.Lines[ln].Height div 2;
      for x := L.Lines[ln].Left - 5 to Max(L.Lines[ln].EndX, L.LayoutWidth) + 10 do
      begin
        q := L.PosAtPoint(x, y, atEnd);
        r := L.CaretRect(q, atEnd);
        AssertEquals(Format('paragraph %d line %d x %d: the caret on the line (position %d)',
          [para, ln, x, q]), L.Lines[ln].Top, r.Top);
        best := MaxInt;
        for p := 0 to places - 1 do best := Min(best, Abs(xs[p] - x));
        AssertTrue(Format('paragraph %d line %d x %d: caret at %d, a place %d away',
          [para, ln, x, r.Left, best]), Abs(r.Left - x) <= best + 1);
        AssertEquals(Format('paragraph %d line %d x %d: the flag', [para, ln, x]),
          (ln < L.LineCount - 1) and not L.Lines[ln].Forced and
          (q = L.Lines[ln].First + L.Lines[ln].Count), atEnd);
      end;
    end;
  end;
  // after a U+000B the next line's start is no other line's end: the flag changes nothing
  L := Lay(d, 4, 1000);
  AssertEquals('after the U+000B, flag or not', 20, L.CaretRect(3, True).Top);
  AssertEquals('the paragraph''s end, flag or not', L.CaretRect(8).Left, L.CaretRect(8, True).Left);
  // a row: the flag goes to the cell's paragraph and back
  td := NewTableDoc('a'#10'long long long long'#10'c1'#10'c2');
  t := TTyRichTable.Create([1440, 2880, 4320]);
  t.AddRow(3);
  TDocAccess(td).MarkTable(0, t, [1, 1, 2]).Free;
  row := TTyRowLayout(Block(td, 0, 1000));
  q := row.PosAtPoint(103 + 70, 6, atEnd);
  AssertEquals('past cell 1''s first line', 7, q);
  AssertTrue('its end', atEnd);
  AssertEquals('the caret on that line', row.CaretRect(2).Top, row.CaretRect(q, atEnd).Top);
  AssertTrue('without the flag: the line below', row.CaretRect(q).Top > row.CaretRect(2).Top);
end;

{ A justified paragraph of 20,000 ideographs keeps a fragment a line, not one a character:
  the stretch between the characters is the fragment's (an advance added at each break
  opportunity), and caret places, hit tests and painting all apply it - each character drawn
  where its caret place is. A justified line with spaces keeps a fragment per word: the
  spaces take the stretch, the Chinese between them is one fragment. }
procedure TTyRichLayoutTest.TestAJustifiedLineKeepsAFewFragments;
var
  d, d2: TTyRichDocument;
  L: TTyParaLayout;
  pf: TTyParaFormat;
  s: UTF8String;
  i, k, ln: Integer;
  r: TRect;
  bmp: TBGRABitmap;
  parts: TStringList;
begin
  s := '';
  for i := 0 to 19999 do s := s + U($4E00 + Cardinal(i mod 2000));
  s := s + #10;
  for i := 0 to 199 do s := s + 'word 中文字中文 ';
  d := NewDoc(s);
  pf := TyDefaultParaFormat;
  pf.Align := paraJustify;
  SetPara(d, 0, [pffAlign], pf);
  SetPara(d, 1, [pffAlign], pf);
  // 810 px: forty ideographs a line (800 px), 10 px over the 39 gaps
  L := Lay(d, 0, 810);
  AssertEquals('lines', 500, L.LineCount);
  AssertTrue(Format('%d fragments for %d lines', [L.FragmentCount, L.LineCount]),
    L.FragmentCount <= L.LineCount);
  AssertTrue(Format('%d bytes kept for 20000 characters', [L.MemSize]), L.MemSize <= 16 * 20000);
  for ln := 0 to L.LineCount - 2 do
    AssertEquals(Format('line %d ends at the edge', [ln]), 810, L.Lines[ln].EndX);
  AssertEquals('the last line is not stretched', 800, L.Lines[L.LineCount - 1].EndX);
  // the gaps: 10 px spread over 39 the way the line spreads them
  for k := 0 to 39 do
  begin
    AssertEquals(Format('caret %d', [k]), 20 * k + 10 * k div 39, L.CaretRect(k).Left);
    AssertEquals(Format('caret %d of line 7', [k]), 20 * k + 10 * k div 39,
      L.CaretRect(280 + k).Left);
  end;
  for k := 0 to 120 do
  begin
    r := L.CaretRect(k);
    AssertEquals(Format('point to position %d', [k]), k,
      L.PosAtPoint((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2));
  end;
  // painted: each character where its caret place is
  bmp := TBGRABitmap.Create(820, 60, Sentinel);
  parts := TStringList.Create;
  try
    FDevice.DrawLog.Clear;
    L.Paint(bmp, 0, 0, Rect(0, 0, 820, 40), TyRichDefaultPaintStyle, 0, 0);
    AssertEquals('two lines, a call a character', 80, FDevice.DrawLog.Count);
    for k := 0 to 79 do
    begin
      parts.Delimiter := '|';
      parts.StrictDelimiter := True;
      parts.DelimitedText := FDevice.DrawLog[k];
      AssertEquals(Format('draw %d: one character', [k]), U($4E00 + Cardinal(k)), parts[0]);
      AssertEquals(Format('draw %d: at its caret place', [k]), L.CaretRect(k).Left,
        StrToInt(parts[1]));
    end;
  finally
    parts.Free;
    bmp.Free;
  end;
  // Latin inside a line stretched between characters: "ab" is one segment (no break between
  // two letters), drawn as one string where its caret place is
  d2 := NewDoc('中文ab中文ab中文ab中文ab中文ab中文ab中文ab中文ab');
  SetPara(d2, 0, [pffAlign], pf);
  L := Lay(d2, 0, 150);
  AssertTrue('wrapped', L.LineCount > 1);
  AssertEquals('one fragment on the first line', 1, L.Lines[0].FragCount);
  AssertEquals('it reaches the edge', 150, L.Lines[0].EndX);
  bmp := TBGRABitmap.Create(160, 30, Sentinel);
  parts := TStringList.Create;
  try
    FDevice.DrawLog.Clear;
    L.Paint(bmp, 0, 0, Rect(0, 0, 160, 20), TyRichDefaultPaintStyle, 0, 0);
    parts.Delimiter := '|';
    parts.StrictDelimiter := True;
    k := 0;
    for i := 0 to FDevice.DrawLog.Count - 1 do
    begin
      parts.DelimitedText := FDevice.DrawLog[i];
      AssertEquals(Format('draw %d at its caret place', [i]), L.CaretRect(k).Left, StrToInt(parts[1]));
      if parts[0] = 'ab' then Inc(k, 2)
      else
      begin
        AssertEquals(Format('draw %d: a character or "ab"', [i]), 3, Length(parts[0]));
        Inc(k);
      end;
    end;
    AssertEquals('the first line drawn', L.Lines[0].Count, k);
  finally
    parts.Free;
    bmp.Free;
  end;
  for k := 0 to L.Lines[0].Count - 1 do
    AssertTrue(Format('caret %d before %d', [k, k + 1]),
      L.CaretRect(k).Left < L.CaretRect(k + 1, True).Left);
  // spaces on every line: a fragment a word, a space, a run of Chinese
  L := Lay(d, 1, 400);
  AssertTrue(Format('%d fragments for 200 groups on %d lines', [L.FragmentCount, L.LineCount]),
    L.FragmentCount <= 4 * 200 + 2 * L.LineCount);
  // the content (the spaces that hang past it left out) reaches the edge
  for ln := 0 to L.LineCount - 2 do
    AssertEquals(Format('mixed line %d ends at the edge', [ln]), 400,
      L.Lines[ln].Left + L.Lines[ln].ContentWidth);
end;

{ The layouter lays out the document it was given: a second document switches it (the cache
  emptied, each shows its own text, back and forth); and a document freed and another made
  at the same address shows the new one's text once it is set - the review's sequence. }
procedure TTyRichLayoutTest.TestTheDocumentIsToldNotRecognisedByItsAddress;
var
  x, y, a, b: TTyRichDocument;
  lo: TTyRichLayouter;
  L: TTyParaLayout;
  addr: Pointer;
begin
  x := NewDoc('the x document');
  y := NewDoc('the y document');
  lo := NewLayouter;
  try
    lo.Document := x;
    AssertTrue('set', lo.Document = x);
    L := lo.LayoutPara(x, 0, 300, 96, 1);
    AssertEquals('x', 'the x document', L.Text);
    L.Release;
    L := lo.LayoutPara(y, 0, 300, 96, 1);
    AssertEquals('another document: its text', 'the y document', L.Text);
    L.Release;
    AssertTrue('switched to', lo.Document = y);
    AssertEquals('the cache holds only its layout', 1, lo.CachedCount);
    L := lo.LayoutPara(x, 0, 300, 96, 1);
    AssertEquals('and back', 'the x document', L.Text);
    L.Release;
    // freed, and another made where it was
    a := TTyRichDocument.CreateFromUtf8(BytesOf('first document'));
    lo.Document := a;
    L := lo.LayoutPara(a, 0, 300, 96, 1);
    AssertEquals('first', 'first document', L.Text);
    L.Release;
    addr := Pointer(a);
    a.Free;
    b := TTyRichDocument.CreateFromUtf8(BytesOf('second document'));
    try
      lo.Document := b;
      L := lo.LayoutPara(b, 0, 300, 96, 1);
      AssertEquals('the new document''s text', 'second document', L.Text);
      L.Release;
      lo.Document := nil;
      AssertEquals('let go of: nothing kept', 0, lo.CachedCount);
    finally
      b.Free;
    end;
    if Pointer(b) <> addr then Ignore('the heap did not hand the freed address out again');
  finally
    lo.Free;
  end;
end;

{ Sizes a file gives become pixels under a ceiling, the document keeping what it read: a font
  of \fs60000 is CRichMaxFontPx for measuring, metrics and drawing alike (Word's largest size
  at 144 PPI is not cut); lengths saturate at CRichMaxLengthPx; a paragraph of lines exactly
  2,000,000,000 twips high has a positive height, which stops at CRichMaxBlockPx. }
procedure TTyRichLayoutTest.TestSizesFromAFileHaveCeilingsOnTheWayToPixels;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  f: TTyCharFormat;
  pf: TTyParaFormat;
  fr: TTyRichFragment;
  i: Integer;
  bmp: TBGRABitmap;
begin
  AssertEquals('\fs60000', CRichMaxFontPx, TyRichHalfPointsToPx(60000, 96, 1));
  AssertEquals('the largest half-points', CRichMaxFontPx, TyRichHalfPointsToPx(MaxInt, 144, 5));
  AssertEquals('Word''s largest at 144 PPI', 3276, TyRichHalfPointsToPx(3276, 144, 1));
  AssertEquals('at least a pixel', 1, TyRichHalfPointsToPx(-5, 96, 1));
  AssertEquals('twips saturate', CRichMaxLengthPx, TyRichTwipsToPx(High(Int64) div 2, 96, 5));
  AssertEquals('both ways', -CRichMaxLengthPx, TyRichTwipsToPx(Low(Int64) div 2, 96, 5));
  AssertEquals('2e9 twips', CRichMaxLengthPx, TyRichTwipsToPx(2000000000, 96, 1));
  AssertEquals('an ordinary length', 96, TyRichTwipsToPx(1440, 96, 1));
  AssertEquals('the device''s ceiling', CRichMaxFontPx,
    FDevice.FontPixelHeight(FDevice.ResolveFont('Any', 100000, [])));
  d := NewDoc('ab'#10'ab'#11'cd'#10'a'#9'b'#10'xy'#10 + StringOfChar(#11, 70000));
  f := TyDefaultCharFormat;
  f.SizeHalfPt := 60000;
  SetChar(d, 0, 2, [cffSize], f);
  L := Lay(d, 0, 10000);
  fr := FragAt(L, 0);
  AssertEquals('the font', CRichMaxFontPx, FDevice.FontPixelHeight(fr.Font));
  AssertEquals('measured at it', 2 * (CRichMaxFontPx div 2), fr.Width);
  AssertEquals('its metrics', CRichMaxFontPx * 4 div 5, fr.Ascent);
  AssertEquals('the line', CRichMaxFontPx, L.Height);
  AssertEquals('the document keeps its size', 60000, d.Formats.CharFormat(
    d.RunsOf(0)[0].Format).SizeHalfPt);
  bmp := TBGRABitmap.Create(50, 50, Sentinel);
  try
    FDevice.DrawLog.Clear;
    L.Paint(bmp, 0, 0, Rect(0, 0, 50, 50), TyRichDefaultPaintStyle, 0, 0);
    AssertEquals('drawn at it: the baseline the metrics give', 'ab|0|' +
      IntToStr(CRichMaxFontPx * 4 div 5), FDevice.DrawLog.CommaText);
  finally
    bmp.Free;
  end;
  // exact lines of 2e9 twips, as much before and after
  pf := TyDefaultParaFormat;
  pf.LineSpacing := lsExact;
  pf.LineSpacingValue := 2000000000;
  pf.SpaceBefore := 2000000000;
  pf.SpaceAfter := 2000000000;
  SetPara(d, 1, [pffLineSpacing, pffSpaceBefore, pffSpaceAfter], pf);
  L := Lay(d, 1, 1000);
  AssertEquals('two lines', 2, L.LineCount);
  AssertEquals('each at the ceiling', CRichMaxLengthPx, L.Lines[1].Height);
  AssertEquals('positive, and summed', 4 * CRichMaxLengthPx, L.Height);
  // an indent and a tab stop of 2e9 twips, a picture of 2e9 by 2e9
  pf := TyDefaultParaFormat;
  pf.LeftIndent := 2000000000;
  SetLength(pf.Tabs, 1);
  pf.Tabs[0].Position := 2000000000;
  pf.Tabs[0].Align := ttaLeft;
  pf.Tabs[0].Leader := ttlNone;
  SetPara(d, 2, [pffLeftIndent, pffTabs], pf);
  L := Lay(d, 2, CRichNoWrap);
  AssertEquals('the indent', CRichMaxLengthPx, FragAt(L, 0).X);
  AssertEquals('the stop (clamped) is behind the text: the next default one',
    ((CRichMaxLengthPx + 10) div 48 + 1) * 48, FragAt(L, 2).X);
  AssertTrue('picture', d.Execute(TTyRichInsertObject.Create(d.Text.ParaStart(3) + 1,
    TTyRichPicture.Create(rpfPng, nil, 2000000000, 2000000000))));
  L := Lay(d, 3, 1000);
  fr := FragAt(L, 1);
  AssertEquals('the box''s width', CRichMaxLengthPx, fr.Width);
  AssertEquals('its height', CRichMaxLengthPx, fr.Ascent);
  // 70,001 lines of the ceiling's height: the block stops at CRichMaxBlockPx
  pf := TyDefaultParaFormat;
  pf.LineSpacing := lsExact;
  pf.LineSpacingValue := 2000000000;
  SetPara(d, 4, [pffLineSpacing], pf);
  L := Lay(d, 4, 1000);
  AssertEquals('lines', 70001, L.LineCount);
  AssertEquals('the height stops', CRichMaxBlockPx, L.Height);
  for i := 1 to L.LineCount - 1 do
    if L.Lines[i].Top < L.Lines[i - 1].Top then
      Fail(Format('line %d goes up: %d after %d', [i, L.Lines[i].Top, L.Lines[i - 1].Top]));
end;

{ R38: a paragraph of 300,000 characters is laid out as far as CRichMaxParaLayoutChars - with the
  measure calls, the characters measured and the bytes kept of a 100,000-character one - and a
  line under it says how many are not shown. Positions past the cut show at the cut; the notice
  has none; a selection covers what is shown; the document keeps the whole paragraph. The cut
  is at a cluster's start. }
procedure TTyRichLayoutTest.TestAGiantParagraphIsLaidOutUpToTheCap;
var
  chunk, p100, p300: UTF8String;
  d: TTyRichDocument;
  lo: TTyRichLayouter;
  L, L100: TTyParaLayout;
  calls, chars: array[0..1] of Int64;
  mem: array[0..1] of Int64;
  i, k: Integer;
  rs: TRectArray;
  bmp: TBGRABitmap;
  r: TRect;
begin
  chunk := '';
  for i := 1 to 500 do chunk := chunk + 'word 中文 ';
  // 8 characters a unit: 4,000 a block
  p100 := '';
  for i := 1 to 25 do p100 := p100 + chunk;
  p300 := p100 + p100 + p100;
  d := NewDoc(p100 + #10 + p300 + #10 + StringOfChar('a', 99999) + 'e' + U($301) + 'bbb');
  AssertEquals('100,000', 100000, d.Text.ParaLength(0));
  AssertEquals('300,000', 300000, d.Text.ParaLength(1));
  L100 := nil;
  for k := 0 to 1 do
  begin
    lo := NewLayouter;
    try
      L := lo.LayoutPara(d, k, 400, 96, 1);
      try
        calls[k] := TTyRichTestDevice(lo.Device).MeasureCalls;
        chars[k] := TTyRichTestDevice(lo.Device).MeasuredChars;
        mem[k] := L.MemSize;
        if k = 0 then
        begin
          AssertFalse('100,000 is not cut', L.Truncated);
          AssertEquals('all shown', L.CharCount, L.ShownChars);
          L100 := L;
          L100.AddRef;
        end
        else
        begin
          AssertTrue('300,000 is cut', L.Truncated);
          AssertEquals('shown', 100000, L.ShownChars);
          AssertEquals('its length', 300000, L.Length);
          AssertEquals('its positions', 300001, L.CharCount);
          AssertEquals('the lines of the 100,000', L100.LineCount, L.LineCount);
          AssertEquals('the notice', Format(rsRichEditParaNotShown, ['200000']), L.Notice.Text);
          AssertEquals('under the text', L100.Height + 20, L.Height);
          r := L.CaretRect(100000);
          AssertEquals('past the cut: at the cut', r.Left, L.CaretRect(150000).Left);
          AssertEquals('the end too', r.Top, L.CaretRect(300000).Top);
          AssertEquals('a click on the notice', 100000, L.PosAtPoint(5, L.NoticeBaseline - 2));
          AssertEquals('a click below it', 100000, L.PosAtPoint(5000, L.Height + 50));
          rs := L.SelectionRects(0, 300001);
          AssertEquals('a rectangle a shown line', L.LineCount, Length(rs));
          AssertTrue('none on the notice', rs[High(rs)].Bottom <= L.NoticeBaseline - L.Notice.Ascent);
          bmp := TBGRABitmap.Create(400, 40, Sentinel);
          try
            TTyRichTestDevice(lo.Device).DrawLog.Clear;
            L.Paint(bmp, 0, -(L.Height - 30), Rect(0, 0, 400, 40), TyRichDefaultPaintStyle, 0, 0);
            AssertTrue('the notice is drawn', Pos(L.Notice.Text + '|0|',
              TTyRichTestDevice(lo.Device).DrawLog.Text) > 0);
          finally
            bmp.Free;
          end;
        end;
      finally
        L.Release;
      end;
    finally
      lo.Free;
    end;
  end;
  L100.Release;
  AssertTrue(Format('measure calls %d then %d', [calls[0], calls[1]]), calls[1] <= calls[0] + 2);
  AssertTrue(Format('characters measured %d then %d', [chars[0], chars[1]]),
    chars[1] <= chars[0] + 100);
  AssertTrue(Format('bytes kept %d then %d', [mem[0], mem[1]]), mem[1] <= mem[0] + 1024);
  AssertEquals('the document keeps all of it', 300000, d.Text.ParaLength(1));
  // a mark at the cap: cut before the cluster it is in
  L := Lay(d, 2, 400);
  AssertTrue('cut', L.Truncated);
  AssertEquals('at the cluster''s start', 99999, L.ShownChars);
  AssertEquals('the rest', Format(rsRichEditParaNotShown, ['5']), L.Notice.Text);
end;

{ A layout the cache let go of while it was held (the count bound evicted it) cannot follow its
  paragraph to a new index: after a change it says it is stale, so its holder asks again. One
  the cache kept follows, and is not stale. }
procedure TTyRichLayoutTest.TestAHeldLayoutTheCacheLetGoOfIsStaleAfterAChange;
var
  d: TTyRichDocument;
  s: UTF8String;
  i: Integer;
  held, kept: TTyParaLayout;
begin
  s := '';
  for i := 0 to 2399 do s := s + 'p' + IntToStr(i) + #10;
  d := NewDoc(s);
  d.OnChange := @DocChanged;
  held := Lay(d, 100, 300);
  for i := 200 to 200 + CLayoutCacheParas do FLayouter.LayoutPara(d, i, 300, 96, 1).Release;
  AssertTrue('it left the cache', FLayouter.CachedLayout(100) = nil);
  kept := Lay(d, 2300, 300);
  AssertFalse('no change yet: not stale', held.Stale);
  AssertTrue('inserted', d.Execute(TTyRichInsertText.Create(0, 'x'#10)));
  AssertEquals('it says what it was', 'p100', held.Text);
  AssertEquals('which is no longer paragraph 100', 'p99',
    d.Text.GetText(d.Text.ParaStart(100), d.Text.ParaLength(100)));
  AssertTrue('so it is stale', held.Stale);
  AssertFalse('the kept one is not', kept.Stale);
  AssertEquals('and followed its paragraph', 2301, kept.FirstPara);
  // a change after it (typing in the last paragraph) leaves it where it is, and good
  AssertTrue('typed at the end', d.Execute(TTyRichInsertText.Create(d.Text.Length, 'z')));
  AssertFalse('a change after it: not stale', kept.Stale);
  // evicted after the changes, with none since: it was good at them, it still is
  for i := 0 to CLayoutCacheParas do FLayouter.LayoutPara(d, i, 300, 96, 1).Release;
  AssertTrue('the kept one left the cache too', FLayouter.CachedLayout(2301) = nil);
  AssertFalse('no change since: not stale', kept.Stale);
end;

{ A space with a combining mark is one cluster that is text: drawn (a space is not), measured
  as the characters it has. }
procedure TTyRichLayoutTest.TestASpaceCarryingAMarkIsText;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  fr: TTyRichFragment;
  bmp: TBGRABitmap;
begin
  d := NewDoc(' ' + U($301) + #9'x');
  L := Lay(d, 0, 400);
  fr := FragAt(L, 0);
  AssertEquals('text', Ord(rfkText), Ord(fr.Kind));
  AssertEquals('both characters', 2, fr.Count);
  AssertEquals('a space''s advance', 5, fr.Width);
  AssertEquals('the tab after it to the stop', 48, FragAt(L, 3).X);
  bmp := TBGRABitmap.Create(100, 30, Sentinel);
  try
    FDevice.DrawLog.Clear;
    L.Paint(bmp, 0, 0, Rect(0, 0, 100, 30), TyRichDefaultPaintStyle, 0, 0);
    AssertEquals('drawn: two strings', 2, FDevice.DrawLog.Count);
    AssertEquals('the space with its mark', ' ' + U($301) + '|0|16', FDevice.DrawLog[0]);
    AssertEquals('then the x', 'x|48|16', FDevice.DrawLog[1]);
  finally
    bmp.Free;
  end;
end;

{ A tab whose stop lies past the right edge goes to the next line, as Word puts it, unless it is
  the line's first item - then it reaches to the edge. No line is wider than the layout. }
procedure TTyRichLayoutTest.TestATabPastTheRightEdgeGoesToTheNextLine;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  pf: TTyParaFormat;
  i: Integer;
begin
  d := NewDoc(StringOfChar(#9, 50) + 'x'#10'abc'#9'd');
  // default stops at 48, 96, 144, 192: four tabs a line at 200 px
  L := Lay(d, 0, 200);
  AssertEquals('thirteen lines', 13, L.LineCount);
  AssertEquals('four tabs on the first', 4, L.Lines[0].Count);
  for i := 0 to L.LineCount - 1 do
    AssertTrue(Format('line %d is %d wide', [i, L.Lines[i].ContentWidth]),
      L.Lines[i].Left + L.Lines[i].ContentWidth <= 200);
  AssertTrue(Format('the block is %d wide', [L.Width]), L.Width <= 200);
  // an explicit stop at 333 px
  pf := TyDefaultParaFormat;
  SetLength(pf.Tabs, 1);
  pf.Tabs[0].Position := 5000;
  pf.Tabs[0].Align := ttaLeft;
  pf.Tabs[0].Leader := ttlNone;
  SetPara(d, 1, [pffTabs], pf);
  L := Lay(d, 1, 200);
  AssertEquals('the tab leaves the first line', 3, L.Lines[0].Count);
  AssertEquals('the second line starts with it', 3, L.Lines[1].First);
  AssertTrue(Format('the block is %d wide', [L.Width]), L.Width <= 200);
end;

{ With a hanging indent the left indent is a stop for the first line's text (Word and RichEdit
  put a hand-numbered item's text there): "1.<tab>text" starts the text at the indent, default
  stops before it passed over; an explicit stop before it still comes first. }
procedure TTyRichLayoutTest.TestTheHangingIndentIsATabStopOfTheFirstLine;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  pf: TTyParaFormat;
begin
  d := NewDoc('1.'#9'text'#10'1.'#9'text'#10'1.'#9'text'#10'1.'#9'text');
  pf := TyDefaultParaFormat;
  pf.FirstIndent := -360;
  pf.LeftIndent := 360;
  SetPara(d, 0, [pffFirstIndent, pffLeftIndent], pf);
  L := Lay(d, 0, 400);
  AssertEquals('at the indent (24 px)', 24, FragAt(L, 3).X);
  // indent 72 px, the first line at 24: the default stop at 48 is passed over
  pf.FirstIndent := -720;
  pf.LeftIndent := 1080;
  SetPara(d, 1, [pffFirstIndent, pffLeftIndent], pf);
  L := Lay(d, 1, 400);
  AssertEquals('the item starts at the first line''s indent', 24, FragAt(L, 0).X);
  AssertEquals('its text at the indent (72 px)', 72, FragAt(L, 3).X);
  // an explicit stop at 60 px comes before the indent
  SetLength(pf.Tabs, 1);
  pf.Tabs[0].Position := 900;
  pf.Tabs[0].Align := ttaLeft;
  pf.Tabs[0].Leader := ttlNone;
  SetPara(d, 2, [pffFirstIndent, pffLeftIndent, pffTabs], pf);
  L := Lay(d, 2, 400);
  AssertEquals('the explicit stop first', 60, FragAt(L, 3).X);
  // an explicit stop past the indent (96 px): the indent comes first
  pf.FirstIndent := -360;
  pf.LeftIndent := 360;
  pf.Tabs[0].Position := 1440;
  SetPara(d, 3, [pffFirstIndent, pffLeftIndent, pffTabs], pf);
  L := Lay(d, 3, 400);
  AssertEquals('the indent before a later stop', 24, FragAt(L, 3).X);
end;

{ Naming a fallback event, or changing the candidate list, forgets the fonts found for missing
  glyphs and the layouts made with them: the next layout asks again. }
procedure TTyRichLayoutTest.TestTheFallbackEventAndListDropWhatWasFound;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  f: TTyCharFormat;
begin
  d := NewDoc('ab中文');
  f := TyDefaultCharFormat;
  f.FontName := 'Arial';
  SetChar(d, 0, d.Text.Length, [cffFontName], f);
  FDevice.SetRepertoire('Arial', [$20, $7E]);
  L := Lay(d, 0, 1000);
  AssertEquals('the first candidate', FLayouter.FallbackFonts[0], FDevice.FontName(FragAt(L, 2).Font));
  FEventFont := 'Event Font';
  FLayouter.OnFallbackFont := @FallbackEvent;
  L := Lay(d, 0, 1000);
  AssertEquals('the event is asked', 'Event Font', FDevice.FontName(FragAt(L, 2).Font));
  FLayouter.OnFallbackFont := nil;
  L := Lay(d, 0, 1000);
  AssertEquals('no event: the list again', FLayouter.FallbackFonts[0],
    FDevice.FontName(FragAt(L, 2).Font));
  FLayouter.FallbackFonts.Insert(0, 'Other Font');
  L := Lay(d, 0, 1000);
  AssertEquals('a changed list', 'Other Font', FDevice.FontName(FragAt(L, 2).Font));
end;

{ A cmap table read as the real device reads it (Windows): a well-formed format 4 table gives
  its ranges; a malformed one costs what its size holds - no count in it is trusted past what
  the table can contain (no tables, more tables or segments or groups than bytes, segments
  that each claim the whole BMP). }
procedure TTyRichLayoutTest.TestTheCmapReaderBoundsItsCounts;
var
  b: TBytes;
  r: TTyRichCodeRanges;
  sym: Boolean;
  steps: Int64;
  i: Integer;

  procedure W16(AAt: Integer; AValue: Cardinal);
  begin
    b[AAt] := (AValue shr 8) and $FF;
    b[AAt + 1] := AValue and $FF;
  end;

  procedure W32(AAt: Integer; AValue: Cardinal);
  begin
    W16(AAt, AValue shr 16);
    W16(AAt + 2, AValue and $FFFF);
  end;

  // a header with one record (3, AEnc) pointing at 12
  procedure Header(ASize, ATables: Integer; AEnc: Cardinal);
  begin
    b := nil;
    SetLength(b, ASize);
    W16(2, ATables);
    W16(4, 3);
    W16(6, AEnc);
    W32(8, 12);
  end;

begin
  // A..Z: two segments, the second the closing $FFFF one
  Header(44, 1, 1);
  W16(12, 4);
  W16(18, 4);
  W16(26, $5A); W16(28, $FFFF);
  W16(32, $41); W16(34, $FFFF);
  W16(36, 1); W16(38, 1);
  r := TyRichReadCmapTable(b, sym, steps);
  AssertEquals('one range', 1, Length(r));
  AssertEquals('from A', $41, r[0].First);
  AssertEquals('to Z', $5A, r[0].Last);
  AssertFalse('not a symbol font', sym);
  AssertTrue(Format('%d steps', [steps]), steps <= 2 + 26 + 1);
  // no tables
  Header(12, 0, 1);
  r := TyRichReadCmapTable(b, sym, steps);
  AssertEquals('no tables: nothing', 0, Length(r));
  AssertEquals('and nothing looked at', 0, steps);
  // 65,535 tables in a table with room for one
  Header(12, 65535, 1);
  r := TyRichReadCmapTable(b, sym, steps);
  AssertTrue(Format('records: %d steps', [steps]), steps <= 1);
  // 32,767 segments claimed in 64 bytes
  Header(64, 1, 1);
  W16(12, 4);
  W16(18, 65534);
  r := TyRichReadCmapTable(b, sym, steps);
  AssertTrue(Format('segments: %d steps', [steps]), steps <= 64);
  // 4,294,967,295 groups claimed in 40 bytes
  Header(40, 1, 10);
  W16(12, 12);
  W32(24, $FFFFFFFF);
  r := TyRichReadCmapTable(b, sym, steps);
  AssertTrue(Format('groups: %d steps', [steps]), steps <= 40);
  // a hundred segments that each claim the whole BMP
  Header(12 + 16 + 100 * 8, 1, 1);
  W16(12, 4);
  W16(18, 200);
  for i := 0 to 99 do
  begin
    W16(26 + i * 2, $FFFE);
    W16(26 + 200 + 2 + i * 2, 0);
    W16(26 + 400 + 2 + i * 2, 1);
  end;
  r := TyRichReadCmapTable(b, sym, steps);
  AssertTrue(Format('codes: %d steps', [steps]), steps <= 65536 + 100 + 1);
end;

{ The kept advances are bounded by bytes as well as by count: 30,000 measures of distinct
  600-byte Chinese fragments (fewer entries than the count bound lets through) keep at most
  CRichMeasureCacheBytes, and what went is measured again when asked. }
procedure TTyRichLayoutTest.TestTheMeasureCacheIsBoundedByBytes;
var
  lo: TTyRichLayouter;
  font: TTyRichFontId;
  base: UTF8String;
  i: Integer;
  most, calls: Int64;
begin
  base := '';
  for i := 1 to 200 do base := base + U($4E00 + Cardinal(i));
  lo := NewLayouter;
  try
    font := lo.Device.ResolveFont('Test', 20, []);
    most := 0;
    for i := 0 to 29999 do
    begin
      lo.MeasureText(font, IntToStr(i) + base);
      if lo.MeasureCacheBytes > most then most := lo.MeasureCacheBytes;
    end;
    AssertTrue('fewer than the count bound lets through', 30000 < CRichMeasureCacheEntries div 2);
    AssertTrue(Format('at most %d bytes kept', [most]), most <= CRichMeasureCacheBytes + 1024);
    calls := lo.Device.MeasureCalls;
    lo.MeasureText(font, '0' + base);
    AssertEquals('the first went: measured again', calls + 1, lo.Device.MeasureCalls);
    lo.MeasureText(font, '29999' + base);
    AssertEquals('the last stayed', calls + 1, lo.Device.MeasureCalls);
  finally
    lo.Free;
  end;
end;

{ A change inside a cached paragraph that splits it, one across cached paragraphs that joins
  them, and a change of no old paragraphs (paragraphs put in before one, as a load slice
  reports): the paragraphs the change met lose their layouts (stale), the others follow to
  their new indexes and are hits there, the ones before stay. }
procedure TTyRichLayoutTest.TestChangesInsideAndAcrossCachedParagraphsAreFollowed;
var
  d: TTyRichDocument;
  s: UTF8String;
  i: Integer;
  met: TTyParaLayout;
  ch: TTyRichChange;
  hits: Int64;
begin
  s := '';
  for i := 0 to 9 do s := s + 'para' + IntToStr(i) + #10;
  d := NewDoc(s);
  d.OnChange := @DocChanged;
  for i := 2 to 8 do Lay(d, i, 300);
  met := TTyParaLayout(FLayouter.CachedLayout(3));
  // inside paragraph 3: it splits in two, 4..8 move one down
  AssertTrue('split', d.Execute(TTyRichInsertText.Create(d.Text.ParaStart(3) + 2, 'x'#10)));
  AssertTrue('the split one is stale', met.Stale);
  AssertTrue('and gone', FLayouter.CachedLayout(3) = nil);
  AssertEquals('the one before stays', 'para2', TTyParaLayout(FLayouter.CachedLayout(2)).Text);
  for i := 5 to 9 do
  begin
    AssertTrue(Format('a layout at %d', [i]), FLayouter.CachedLayout(i) <> nil);
    AssertEquals(Format('at %d', [i]), 'para' + IntToStr(i - 1),
      TTyParaLayout(FLayouter.CachedLayout(i)).Text);
    AssertFalse('not stale', FLayouter.CachedLayout(i).Stale);
  end;
  // across 5..7, from inside 5 to inside 7: they join, 8 and 9 move up two
  met := TTyParaLayout(FLayouter.CachedLayout(6));
  AssertTrue('joined', d.Execute(TTyRichDelete.Create(d.Text.ParaStart(5) + 2,
    d.Text.ParaStart(7) - d.Text.ParaStart(5))));
  AssertEquals('the joined text', 'para6', d.Text.GetText(d.Text.ParaStart(5),
    d.Text.ParaLength(5)));
  AssertTrue('a joined one is stale', met.Stale);
  AssertTrue('gone', FLayouter.CachedLayout(5) = nil);
  hits := FLayouter.CacheHits;
  AssertEquals('para7 at 6', 'para7', Lay(d, 6, 300).Text);
  AssertEquals('para8 at 7', 'para8', Lay(d, 7, 300).Text);
  AssertEquals('both hits', hits + 2, FLayouter.CacheHits);
  // no old paragraphs, two new ones at 6: the one there goes (conservatively), the next moves
  met := TTyParaLayout(FLayouter.CachedLayout(6));
  ch.Kinds := [rckStructure];
  ch.Pos := d.Text.ParaStart(6);
  ch.OldLen := 0;
  ch.NewLen := 0;
  ch.FirstPara := 6;
  ch.OldParaCount := 0;
  ch.NewParaCount := 2;
  FLayouter.DocumentChanged(ch);
  AssertTrue('the one at its paragraph goes', FLayouter.CachedLayout(6) = nil);
  AssertTrue('stale', met.Stale);
  AssertTrue('the next moved two', FLayouter.CachedLayout(9) <> nil);
  AssertEquals('it is para8''s', 'para8', TTyParaLayout(FLayouter.CachedLayout(9)).Text);
  AssertEquals('and knows it', 9, FLayouter.CachedLayout(9).FirstPara);
  AssertEquals('the one before stays', 'para2', TTyParaLayout(FLayouter.CachedLayout(2)).Text);
end;

{ ---- fix wave W2: rows ---- }

function CountPx(ABmp: TBGRABitmap; const APx: TBGRAPixel): Integer;
var
  x, y: Integer;
begin
  Result := 0;
  for y := 0 to ABmp.Height - 1 do
    for x := 0 to ABmp.Width - 1 do
      if SamePx(APx, ABmp.GetPixel(x, y)) then Inc(Result);
end;

{ Word writes \brdrtbl on every side of every cell of a table without borders (letterheads,
  forms, text side by side): no line is drawn. }
procedure TTyRichLayoutTest.TestWordsBorderlessCellsHaveNoLines;
var
  d: TTyRichDocument;
  t: TTyRichTable;
  R: TTyRowLayout;
  bmp: TBGRABitmap;
  st: TTyRichPaintStyle;
  cellFmt: RawByteString;
begin
  st := TyRichDefaultPaintStyle;
  st.TableBorder := BGRA(0, 0, 255, 255);
  cellFmt := '\clbrdrt\brdrtbl \clbrdrl\brdrtbl \clbrdrb\brdrtbl \clbrdrr\brdrtbl ';
  d := NewTableDoc('a'#10'b');
  t := TTyRichTable.Create([1440, 2880]);
  t.AddRow(2, '\trowd\trgaph108\trleft-108' + cellFmt + '\cellx1440' + cellFmt + '\cellx2880');
  TDocAccess(d).MarkTable(0, t, [1, 1]).Free;
  R := TTyRowLayout(Block(d, 0, 1000));
  AssertTrue('cell 0: no lines', R.Cells[0].Sides = []);
  AssertTrue('cell 1: no lines', R.Cells[1].Sides = []);
  AssertEquals('as tall as its text', 20, R.Height);
  bmp := TBGRABitmap.Create(300, 40, Sentinel);
  try
    FDevice.DrawLog.Clear;
    R.Paint(bmp, 20, 10, Rect(0, 0, 300, 40), st, 0, 0);
    AssertEquals('the text', 2, FDevice.DrawLog.Count);
    AssertEquals('no line anywhere', 0, CountPx(bmp, st.TableBorder));
  finally
    bmp.Free;
  end;
end;

{ A line between two cells (rows) is drawn once, as the later one's left (top). A cell that
  declares its right (bottom) line while the next cell (the cell below) declares no left (top)
  draws it itself - a table with only bottom lines, as report generators write it, keeps
  them; inside a vertical merge there is none. }
procedure TTyRichLayoutTest.TestDeclaredLinesAreDrawnOnceAndNotLost;
var
  d: TTyRichDocument;
  t: TTyRichTable;
  R0, R1, R2: TTyRowLayout;
  bmp: TBGRABitmap;
  st: TTyRichPaintStyle;
begin
  st := TyRichDefaultPaintStyle;
  st.TableBorder := BGRA(0, 0, 255, 255);
  d := NewTableDoc('a'#10'b'#10'c'#10'd'#10'e'#10'f');
  t := TTyRichTable.Create([1440, 2880]);
  t.AddRow(2, '\trowd\trgaph108\clbrdrb\brdrs\cellx1440\clbrdrb\brdrs\clbrdrr\brdrs\cellx2880');
  t.AddRow(2, '\trowd\trgaph108\clbrdrr\brdrs\clbrdrb\brdrs\cellx1440\cellx2880');
  t.AddRow(2, '\trowd\trgaph108\clbrdrt\brdrs\clbrdrr\brdrs\clbrdrb\brdrs\cellx1440' +
    '\clbrdrl\brdrs\clbrdrt\brdrs\cellx2880');
  TDocAccess(d).MarkTable(0, t, [1, 1, 1, 1, 1, 1]).Free;
  R0 := TTyRowLayout(Block(d, 0, 1000));
  R1 := TTyRowLayout(Block(d, 2, 1000));
  R2 := TTyRowLayout(Block(d, 4, 1000));
  AssertTrue('row 0: a bottom the cell below does not draw', rcsBottom in R0.Cells[0].Sides);
  AssertTrue('row 0, cell 1 too', rcsBottom in R0.Cells[1].Sides);
  AssertTrue('the last cell closes the row', rcsRight in R0.Cells[1].Sides);
  AssertEquals('the bottom line in the row''s height', 21, R0.Height);
  AssertTrue('row 1: a right the next cell does not draw', rcsRight in R1.Cells[0].Sides);
  AssertFalse('row 1: its bottom is the top of the cell below', rcsBottom in R1.Cells[0].Sides);
  AssertTrue('row 1, cell 1: nothing', R1.Cells[1].Sides = []);
  AssertFalse('row 2: its right is the next cell''s left', rcsRight in R2.Cells[0].Sides);
  AssertTrue('which draws it', rcsLeft in R2.Cells[1].Sides);
  AssertTrue('the last row closes the table', rcsBottom in R2.Cells[0].Sides);
  bmp := TBGRABitmap.Create(300, 40, Sentinel);
  try
    R0.Paint(bmp, 20, 10, Rect(0, 0, 300, 40), st, 0, 0);
    AssertTrue('row 0''s bottom line', SamePx(st.TableBorder, bmp.GetPixel(20 + 48, 10 + 20)));
    AssertTrue('under cell 1 too', SamePx(st.TableBorder, bmp.GetPixel(20 + 140, 10 + 20)));
    bmp.FillRect(0, 0, 300, 40, Sentinel, dmSet);
    R1.Paint(bmp, 20, 10, Rect(0, 0, 300, 40), st, 0, 0);
    AssertTrue('row 1''s line between its cells', SamePx(st.TableBorder,
      bmp.GetPixel(20 + R1.Cells[0].Right - 1, 15)));
  finally
    bmp.Free;
  end;
  // a vertical merge: no line inside it
  d := NewTableDoc('a'#10'b');
  t := TTyRichTable.Create([1440]);
  t.AddRow(1, '\trowd\clvmgf\clbrdrb\brdrs\cellx1440');
  t.AddRow(1, '\trowd\clvmrg\cellx1440');
  TDocAccess(d).MarkTable(0, t, [1, 1]).Free;
  R0 := TTyRowLayout(Block(d, 0, 1000));
  AssertFalse('no bottom toward the cell that continues it', rcsBottom in R0.Cells[0].Sides);
end;

{ \trqc and \trqr place the row in the layout width (not without wrapping); a border wider
  than Word's 75 twips is drawn 75 twips wide; the gap is at most half the cell, and a cell
  with no room for text takes no height for it (its paragraphs a line each, unwrapped); edges
  at the ends of the integers stay inside the pixel range. }
procedure TTyRichLayoutTest.TestARowIsPlacedAndBoundedAsItsFormatSays;
var
  d: TTyRichDocument;
  t: TTyRichTable;
  R: TTyRowLayout;
  rc: TRect;
begin
  d := NewTableDoc('a'#10'b'#10'c'#10'd'#10'e'#10'f'#10'some words here'#10'more words'#10 +
    'x'#10'y');
  t := TTyRichTable.Create([]);
  t.AddRow(2, '\trowd\trgaph108\trqc\cellx1440\cellx2880');
  t.AddRow(2, '\trowd\trgaph108\trqr\trleft500\cellx1440\cellx2880');
  t.AddRow(2, '\trowd\trgaph108\clbrdrt\brdrs\brdrw2000000000 \cellx1440' +
    '\clbrdrl\brdrs\brdrw-5 \cellx2880');
  t.AddRow(2, '\trowd\trgaph100000\cellx1440\cellx1440');
  t.AddRow(2, '\trowd\trgaph108\trleft-2147483647\cellx2147483647\cellx-2147483647');
  TDocAccess(d).MarkTable(0, t, [1, 1, 1, 1, 1, 1, 1, 1, 1, 1]).Free;
  R := TTyRowLayout(Block(d, 0, 1000));
  AssertEquals('\trqc: centred in 1000', 404, R.Cells[0].Left);
  AssertEquals('its right', 596, R.Cells[1].Right);
  AssertEquals('the text with it', 411, R.Items[0].X);
  R := TTyRowLayout(Block(d, 0, CRichNoWrap));
  AssertEquals('without wrapping: at \trleft', 0, R.Cells[0].Left);
  R := TTyRowLayout(Block(d, 2, 1000));
  AssertEquals('\trqr: at the right', 1000, R.Cells[1].Right);
  AssertEquals('its first cell', 841, R.Cells[0].Left);
  R := TTyRowLayout(Block(d, 4, 1000));
  AssertEquals('a border of 2e9 twips: 75 twips', 5, R.Cells[0].LinePx[rcsTop]);
  AssertEquals('a negative width: the thinnest', 1, R.Cells[1].LinePx[rcsLeft]);
  AssertEquals('the row: the line and the text', 25, R.Height);
  R := TTyRowLayout(Block(d, 6, 1000));
  AssertEquals('a gap past half the cell: no room, no height', 1, R.Height);
  AssertEquals('the text at the cell''s middle', 48, R.Items[0].X);
  AssertEquals('its paragraph one line', 1, R.Items[0].Layout.LineCount);
  AssertEquals('a cell with no width: one line too', 1, R.Items[1].Layout.LineCount);
  rc := R.CaretRect(R.Items[0].Layout.Length);
  AssertTrue(Format('the caret past the cell''s right stays in it: %d', [rc.Left]),
    (rc.Left >= R.Cells[0].Left) and (rc.Right <= R.Cells[0].Right));
  AssertTrue('and in the row', (rc.Top >= 0) and (rc.Bottom <= R.Height));
  R := TTyRowLayout(Block(d, 8, 1000));
  AssertEquals('the far left edge', -CRichMaxLengthPx, R.Cells[0].Left);
  AssertEquals('the far right edge', CRichMaxLengthPx, R.Cells[0].Right);
  AssertEquals('an edge left of the one before: an empty cell', R.Cells[1].Left, R.Cells[1].Right);
  AssertEquals('the text''s row', 20, R.Height);
end;

{ An exact row (\trrh negative) shows only its box: what does not fit is not painted, and the
  caret and the selection of a position in the part it clips stay inside the box (the caret
  is never drawn over the next row). }
procedure TTyRichLayoutTest.TestAnExactRowShowsAndAnswersOnlyItsBox;
var
  d: TTyRichDocument;
  t: TTyRichTable;
  R: TTyRowLayout;
  rc: TRect;
  rs: TRectArray;
  p, i, x, y, o: Integer;
  bmp: TBGRABitmap;
  st: TTyRichPaintStyle;
begin
  st := TyRichDefaultPaintStyle;
  d := NewTableDoc('long long long long'#10'c');
  t := TTyRichTable.Create([1440, 2880]);
  t.AddRow(2, '\trowd\trgaph108\trrh-600\cellx1440\cellx2880');
  TDocAccess(d).MarkTable(0, t, [1, 1]).Free;
  R := TTyRowLayout(Block(d, 0, 1000));
  AssertEquals('exactly 600 twips', 40, R.Height);
  AssertEquals('four lines in it', 4, R.Items[0].Layout.LineCount);
  rc := R.CaretRect(16);
  AssertTrue(Format('a caret in the fourth line stays in the row: %d..%d', [rc.Top, rc.Bottom]),
    (rc.Top >= 0) and (rc.Bottom <= 40) and (rc.Bottom > rc.Top));
  for p := 0 to R.CharCount - 1 do
  begin
    rc := R.CaretRect(p);
    o := R.Cells[R.Items[R.ItemAt(p)].Cell].Owner;
    AssertTrue(Format('caret %d in the row', [p]), (rc.Top >= 0) and (rc.Bottom <= R.Height) and
      (rc.Bottom > rc.Top));
    AssertTrue(Format('caret %d in its cell', [p]), (rc.Left >= R.Cells[o].Left) and
      (rc.Right <= R.Cells[o].Right));
  end;
  rs := R.SelectionRects(0, R.CharCount);
  AssertEquals('the two lines shown of cell 0, and cell 1''s', 3, Length(rs));
  for i := 0 to High(rs) do
    AssertTrue(Format('rectangle %d in the row', [i]), (rs[i].Top >= 0) and
      (rs[i].Bottom <= 40) and (rs[i].Bottom > rs[i].Top));
  bmp := TBGRABitmap.Create(300, 80, Sentinel);
  try
    FDevice.DrawLog.Clear;
    R.Paint(bmp, 0, 0, Rect(0, 0, 300, 80), st, 0, 0);
    AssertEquals('the lines in the box, no more', 'long|7|16,long|7|36,c|103|16',
      FDevice.DrawLog.CommaText);
    for y := 40 to 79 do
      for x := 0 to 299 do
        if not SamePx(Sentinel, bmp.GetPixel(x, y)) then
          Fail(Format('ink below the row at (%d, %d)', [x, y]));
  finally
    bmp.Free;
  end;
end;

{ Painting leaves the target's clip as it found it - a paragraph with a fragment selected in
  part (its parts are drawn with the clip cut), a row - and a cell merged into the one before
  it paints nothing of its own text. }
procedure TTyRichLayoutTest.TestPaintLeavesTheClipAndHidesMergedAwayText;
var
  d: TTyRichDocument;
  t: TTyRichTable;
  L: TTyParaLayout;
  R: TTyRowLayout;
  bmp: TBGRABitmap;
  st: TTyRichPaintStyle;
  before: TRect;
  i: Integer;
begin
  st := TyRichDefaultPaintStyle;
  before := Rect(3, 4, 250, 70);
  bmp := TBGRABitmap.Create(300, 80, Sentinel);
  try
    d := NewDoc('abcdef ghi');
    L := Lay(d, 0, 300);
    bmp.ClipRect := before;
    FDevice.DrawLog.Clear;
    L.Paint(bmp, 0, 0, Rect(0, 0, 100, 30), st, 2, 4);
    AssertTrue('a fragment selected in part: drawn in parts', FDevice.DrawLog.Count >= 3);
    AssertTrue('the clip after a paragraph', Types.EqualRect(before, bmp.ClipRect));
    // (long enough to reach into the merged-away cell's own box were it painted)
    d := NewTableDoc('shown'#10'hidden hidden hidden');
    t := TTyRichTable.Create([1440, 2880]);
    t.AddRow(2, '\trowd\trgaph108\clmgf\cellx1440\clmrg\cellx2880');
    TDocAccess(d).MarkTable(0, t, [1, 1]).Free;
    R := TTyRowLayout(Block(d, 0, 1000));
    AssertTrue('merged away', R.Cells[1].Hidden);
    bmp.ClipRect := before;
    FDevice.DrawLog.Clear;
    R.Paint(bmp, 0, 0, Rect(0, 0, 300, 80), st, 1, 3);
    AssertTrue('the clip after a row', Types.EqualRect(before, bmp.ClipRect));
    AssertTrue('the shown cell drawn', FDevice.DrawLog.Count >= 1);
    for i := 0 to FDevice.DrawLog.Count - 1 do
      AssertEquals('only the shown cell''s text: ' + FDevice.DrawLog[i], 1,
        Pos('shown|', FDevice.DrawLog[i]));
  finally
    bmp.Free;
  end;
end;

{ ---- fix wave W2: pictures ---- }

procedure ReleaseSkipped(const A: TTyRichSkippedPictures);
var
  i: Integer;
begin
  for i := 0 to High(A) do A[i].Picture.Release;
end;

{ Two pictures on one screen whose decoded images together are over the cache's bound: a
  paint pass never evicts a picture it used, and a picture shown reduced keeps only its
  reduced copy - so after the first paint, repaints decode and scale nothing. }
procedure TTyRichLayoutTest.TestOneScreensPicturesNeverEvictEachOther;
var
  d: TTyRichDocument;
  L, L0, L1: TTyParaLayout;
  bmp: TBGRABitmap;
  st: TTyRichPaintStyle;
  i, k: Integer;
  dec, sc: Int64;
  pa, pb: TTyRichPicture;
  lo: TTyRichLayouter;
begin
  st := TyRichDefaultPaintStyle;
  bmp := TBGRABitmap.Create(300, 120, Sentinel);
  try
    // at their own size, 100 x 100 (40 KB decoded each), against a bound of 64 KB
    FLayouter.PictureCacheLimit := 64 * 1024;
    d := NewDoc(' ');
    for i := 1 downto 0 do
      AssertTrue('inserted', d.Execute(TTyRichInsertObject.Create(i,
        TTyRichPicture.Create(rpfPng, PngBytes(100, 100, BGRA(0, i * 200, 100, 255)), 1500, 1500))));
    L := Lay(d, 0, 1000);
    L.Paint(bmp, 0, 0, Rect(0, 0, 300, 120), st, 0, 0);
    AssertEquals('both decoded', 2, FLayouter.PictureDecodes);
    AssertEquals('both kept: one paint used them', 2, FLayouter.PictureCacheCount);
    for k := 1 to 3 do L.Paint(bmp, 0, 0, Rect(0, 0, 300, 120), st, 0, 0);
    AssertEquals('repaints decode nothing', 2, FLayouter.PictureDecodes);
    AssertEquals('nor scale', 0, FLayouter.PictureScales);
    // the control's way: two blocks, one pass a paint (BeginPaintPass)
    d := NewDoc(' '#10' ');
    pb := TTyRichPicture.Create(rpfPng, PngBytes(100, 100, BGRA(0, 0, 200, 255)), 1500, 1500);
    pa := TTyRichPicture.Create(rpfPng, PngBytes(100, 100, BGRA(200, 0, 0, 255)), 1500, 1500);
    AssertTrue('b', d.Execute(TTyRichInsertObject.Create(2, pb)));
    AssertTrue('a', d.Execute(TTyRichInsertObject.Create(0, pa)));
    L0 := Lay(d, 0, 1000);
    L1 := Lay(d, 1, 1000);
    dec := FLayouter.PictureDecodes;
    for k := 1 to 3 do
    begin
      FLayouter.BeginPaintPass;
      L0.Paint(bmp, 0, 0, Rect(0, 0, 300, 120), st, 0, 0);
      L1.Paint(bmp, 0, 0, Rect(0, 0, 300, 120), st, 0, 0);
    end;
    AssertEquals('two blocks of one paint: each decoded once', dec + 2, FLayouter.PictureDecodes);
  finally
    bmp.Free;
  end;
  // shown reduced (200 x 200, 160 KB decoded, at 50 x 50): only the reduced copy stays, so
  // both fit under 100 KB and even paints that are passes of their own decode nothing more
  lo := NewLayouter;
  L := nil;
  bmp := TBGRABitmap.Create(300, 120, Sentinel);
  try
    lo.PictureCacheLimit := 100 * 1024;
    d := NewDoc(' ');
    for i := 1 downto 0 do
      AssertTrue('inserted', d.Execute(TTyRichInsertObject.Create(i,
        TTyRichPicture.Create(rpfPng, PngBytes(200, 200, BGRA(i * 200, 100, 0, 255)), 750, 750))));
    L := lo.LayoutPara(d, 0, 1000, 96, 1);
    L.Paint(bmp, 0, 0, Rect(0, 0, 300, 120), st, 0, 0);
    AssertEquals('both decoded', 2, lo.PictureDecodes);
    sc := lo.PictureScales;
    AssertEquals('both reduced', 2, sc);
    AssertTrue(Format('the full images went: %d bytes', [lo.PictureCacheBytes]),
      lo.PictureCacheBytes < 2 * (50 * 50 * 4 + 4096));
    // each picture painted by itself: a pass a paint
    for k := 1 to 3 do
    begin
      L.Paint(bmp, 0, 0, Rect(0, 0, 40, 120), st, 0, 0);
      L.Paint(bmp, 0, 0, Rect(60, 0, 300, 120), st, 0, 0);
    end;
    AssertEquals('repaints decode nothing', 2, lo.PictureDecodes);
    AssertEquals('nor scale', sc, lo.PictureScales);
  finally
    if L <> nil then L.Release;
    bmp.Free;
    lo.Free;
  end;
end;

{ A picture's size is read from its header before anything is decoded: one that says
  30000 x 30000 is a placeholder and nothing is allocated for it; over the budget a PNG is a
  placeholder and a JPEG decodes reduced. An enlargement (a page-wide picture at 500 %), and a
  reduction past the budget of a kept copy, are drawn from the decoded image for the part in
  the clip: no scaled copy is made. }
procedure TTyRichLayoutTest.TestPictureSizesAreBoundedBeforeAnythingIsAllocated;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  bmp: TBGRABitmap;
  st: TTyRichPaintStyle;
  huge, png, jpg, big: TTyRichPicture;
  blue: TBGRAPixel;
  fr: TTyRichFragment;
begin
  st := TyRichDefaultPaintStyle;
  blue := BGRA(0, 0, 255, 255);
  huge := TTyRichPicture.Create(rpfPng, PngHeaderBytes(30000, 30000), 1500, 1500);
  png := TTyRichPicture.Create(rpfPng, PngBytes(400, 300, blue), 6000, 4500);
  jpg := TTyRichPicture.Create(rpfJpeg, JpegBytes(400, 300, blue), 6000, 4500);
  huge.AddRef;
  png.AddRef;
  jpg.AddRef;
  bmp := TBGRABitmap.Create(300, 200, Sentinel);
  try
    AssertFalse('30000 x 30000: a placeholder', FLayouter.DrawPicture(bmp, huge,
      Rect(0, 0, 100, 100), 1, st));
    AssertTrue('its fill', SamePx(st.PlaceholderFill, bmp.GetPixel(50, 50)));
    AssertEquals('tried', 1, FLayouter.PictureDecodes);
    AssertEquals('no pixel decoded', 0, FLayouter.PictureDecodedPixels);
    AssertTrue('ready: the placeholder is what is drawn', FLayouter.PictureReady(huge, 100, 100));
    FLayouter.DrawPicture(bmp, huge, Rect(0, 0, 100, 100), 1, st);
    AssertEquals('not tried again', 1, FLayouter.PictureDecodes);
    // a budget of 40,000 pixels: 400 x 300 is over it
    FLayouter.PictureDecodeBudget := 40000;
    AssertFalse('a PNG over the budget: a placeholder', FLayouter.DrawPicture(bmp, png,
      Rect(0, 0, 200, 150), 1, st));
    AssertEquals('nothing decoded of it', 0, FLayouter.PictureDecodedPixels);
    AssertTrue('a JPEG over it: decoded at half its size', FLayouter.DrawPicture(bmp, jpg,
      Rect(0, 0, 200, 150), 1, st));
    AssertEquals('200 x 150 pixels', 30000, FLayouter.PictureDecodedPixels);
    AssertEquals('drawn at that size: not scaled', 0, FLayouter.PictureScales);
    // (a JPEG's blue is near blue, not exactly it)
    AssertTrue('its pixels', (bmp.GetPixel(100, 75).blue > 200) and
      (bmp.GetPixel(100, 75).red < 60) and (bmp.GetPixel(100, 75).green < 60));
  finally
    bmp.Free;
    huge.Release;
    png.Release;
    jpg.Release;
  end;
  // a page-wide picture (6 x 4 inches, 600 x 400 pixels) at 500 %: 2880 x 1920
  FLayouter.PictureDecodeBudget := CRichPictureMaxPixels;
  big := TTyRichPicture.Create(rpfPng, PngBytes(600, 400, blue), 8640, 5760);
  d := NewDoc('a');
  AssertTrue('inserted', d.Execute(TTyRichInsertObject.Create(0, big)));
  L := Lay(d, 0, 4000, 5);
  fr := FragAt(L, 0);
  AssertEquals('2880 wide', 2880, fr.Width);
  AssertEquals('1920 tall', 1920, fr.Ascent);
  bmp := TBGRABitmap.Create(300, 200, Sentinel);
  try
    L.Paint(bmp, 0, 0, Rect(0, 0, 300, 200), st, 0, 0);
    AssertEquals('an enlargement: no scaled copy', 0, FLayouter.PictureScales);
    AssertTrue(Format('kept: the decoded image alone (%d bytes)', [FLayouter.PictureCacheBytes]),
      FLayouter.PictureCacheBytes <= 600 * 400 * 4 + Length(big.Data) + 1024);
    AssertTrue('the part in the clip drawn', SamePx(blue, bmp.GetPixel(150, 100)));
    // a reduction to more than the copy budget: drawn from the decoded image as well
    FLayouter.PictureScaleBudget := 1000;
    bmp.FillRect(0, 0, 300, 200, Sentinel, dmSet);
    AssertTrue('reduced past the budget', FLayouter.DrawPicture(bmp, big, Rect(0, 0, 60, 40), 1,
      st));
    AssertEquals('no copy', 0, FLayouter.PictureScales);
    AssertTrue('drawn', SamePx(blue, bmp.GetPixel(30, 20)));
    AssertTrue('in its box only', SamePx(Sentinel, bmp.GetPixel(70, 20)));
  finally
    bmp.Free;
  end;
end;

{ PictureReady is the layouter's own "drawing this now would neither decode nor resample", and
  PreparePicture makes it so: an enlargement is ready once decoded (no copy is made for it); a
  picture reduced (its full image let go) and then zoomed in needs a decode again, and is
  ready after one prepare; a reduction that fails is ready as its placeholder and is not tried
  again. After one PreparePicture each, a deferred paint passes nothing over. }
procedure TTyRichLayoutTest.TestAPreparedPictureIsReady;
var
  d: TTyRichDocument;
  L: TTyParaLayout;
  bmp: TBGRABitmap;
  st: TTyRichPaintStyle;
  pic: TTyRichPicture;
  green: TBGRAPixel;
  lo: TSeamLayouter;
  dec: Int64;
begin
  st := TyRichDefaultPaintStyle;
  st.DeferPictures := True;
  green := BGRA(0, 200, 0, 255);
  bmp := TBGRABitmap.Create(200, 100, Sentinel);
  try
    // an enlargement: 20 x 10 at 200 %
    pic := TTyRichPicture.Create(rpfPng, PngBytes(20, 10, green), 300, 150);
    d := NewDoc('a');
    AssertTrue('inserted', d.Execute(TTyRichInsertObject.Create(0, pic)));
    L := Lay(d, 0, 1000, 2);
    AssertFalse('never drawn: not ready', FLayouter.PictureReady(pic, 40, 20));
    L.Paint(bmp, 0, 0, Rect(0, 0, 200, 100), st, 0, 0);
    AssertEquals('passed over', 1, FLayouter.SkippedPictureCount);
    ReleaseSkipped(FLayouter.TakeSkippedPictures);
    FLayouter.PreparePicture(pic, 40, 20);
    AssertTrue('an enlargement is ready once decoded', FLayouter.PictureReady(pic, 40, 20));
    AssertEquals('with no copy made', 0, FLayouter.PictureScales);
    L.Paint(bmp, 0, 0, Rect(0, 0, 200, 100), st, 0, 0);
    AssertEquals('nothing passed over', 0, FLayouter.SkippedPictureCount);
    AssertTrue('drawn', SamePx(green, bmp.GetPixel(30, L.Lines[0].Baseline - 5)));
    // reduced (40 x 20 at 20 x 10), then zoomed in to 80 x 40
    pic := TTyRichPicture.Create(rpfPng, PngBytes(40, 20, green), 300, 150);
    d := NewDoc('a');
    AssertTrue('inserted', d.Execute(TTyRichInsertObject.Create(0, pic)));
    L := Lay(d, 0, 1000, 1);
    FLayouter.PreparePicture(pic, 20, 10);
    AssertTrue('reduced: ready', FLayouter.PictureReady(pic, 20, 10));
    AssertEquals('one reduction', 1, FLayouter.PictureScales);
    AssertFalse('its own size needs the full image again', FLayouter.PictureReady(pic, 40, 20));
    AssertFalse('and so does an enlargement', FLayouter.PictureReady(pic, 80, 40));
    dec := FLayouter.PictureDecodes;
    L := Lay(d, 0, 1000, 4);
    L.Paint(bmp, 0, 0, Rect(0, 0, 200, 100), st, 0, 0);
    AssertEquals('zoomed in: passed over', 1, FLayouter.SkippedPictureCount);
    ReleaseSkipped(FLayouter.TakeSkippedPictures);
    FLayouter.PreparePicture(pic, 80, 40);
    AssertEquals('decoded again', dec + 1, FLayouter.PictureDecodes);
    AssertTrue('ready', FLayouter.PictureReady(pic, 80, 40));
    L.Paint(bmp, 0, 0, Rect(0, 0, 200, 100), st, 0, 0);
    AssertEquals('nothing passed over', 0, FLayouter.SkippedPictureCount);
    AssertTrue('and the reduced size still is', FLayouter.PictureReady(pic, 20, 10));
  finally
    bmp.Free;
  end;
  // a reduction that fails (the resampler raises)
  lo := TSeamLayouter.Create(TTyRichTestDevice.Create, True);
  bmp := TBGRABitmap.Create(200, 100, Sentinel);
  L := nil;
  try
    lo.BaseFontName := 'Test';
    lo.BaseFontSizeHalfPt := 30;
    lo.ScaleRaise := Exception;
    pic := TTyRichPicture.Create(rpfPng, PngBytes(40, 20, green), 300, 150);
    d := NewDoc('a');
    AssertTrue('inserted', d.Execute(TTyRichInsertObject.Create(0, pic)));
    L := lo.LayoutPara(d, 0, 1000, 96, 1);
    lo.PreparePicture(pic, 20, 10);
    AssertEquals('tried once', 1, lo.ScaleCalls);
    AssertTrue('ready: its placeholder is what is drawn', lo.PictureReady(pic, 20, 10));
    L.Paint(bmp, 0, 0, Rect(0, 0, 200, 100), st, 0, 0);
    L.Paint(bmp, 0, 0, Rect(0, 0, 200, 100), st, 0, 0);
    AssertEquals('nothing passed over', 0, lo.SkippedPictureCount);
    AssertEquals('not tried again', 1, lo.ScaleCalls);
    AssertTrue('the placeholder', SamePx(st.PlaceholderFill,
      bmp.GetPixel(10, L.Lines[0].Baseline - 5)));
    AssertTrue('at another size it is tried', not lo.PictureReady(pic, 30, 15));
  finally
    if L <> nil then L.Release;
    bmp.Free;
    lo.Free;
  end;
end;

{ A placeholder does not count its file's bytes; a font or fallback change keeps the decoded
  pictures (they depend on no font); a decoder's or the resampler's exception is a
  placeholder, but an access violation and out-of-memory are let through. }
procedure TTyRichLayoutTest.TestPictureCacheDetails;
var
  bmp: TBGRABitmap;
  st: TTyRichPaintStyle;
  junk, pic: TTyRichPicture;
  data: TBytes;
  lo: TSeamLayouter;
  raised: Boolean;
  dec: Int64;
begin
  st := TyRichDefaultPaintStyle;
  data := PngHeaderBytes(10, 10);
  SetLength(data, 1024 * 1024);
  junk := TTyRichPicture.Create(rpfPng, data, 300, 300);
  pic := TTyRichPicture.Create(rpfPng, PngBytes(20, 10, BGRABlack), 300, 150);
  junk.AddRef;
  pic.AddRef;
  bmp := TBGRABitmap.Create(60, 40, Sentinel);
  lo := nil;
  try
    AssertFalse('a megabyte that does not decode', FLayouter.DrawPicture(bmp, junk,
      Rect(0, 0, 20, 20), 1, st));
    AssertTrue(Format('a placeholder keeps no bytes: %d', [FLayouter.PictureCacheBytes]),
      FLayouter.PictureCacheBytes < 1024);
    AssertTrue('drawn', FLayouter.DrawPicture(bmp, pic, Rect(0, 0, 20, 10), 1, st));
    dec := FLayouter.PictureDecodes;
    FLayouter.BaseFontName := 'Other';
    FLayouter.BaseFontSizeHalfPt := 40;
    FLayouter.FallbackFonts.Add('Another');
    AssertEquals('font changes keep the pictures', 2, FLayouter.PictureCacheCount);
    FLayouter.DrawPicture(bmp, pic, Rect(0, 0, 20, 10), 1, st);
    AssertEquals('not decoded again', dec, FLayouter.PictureDecodes);
    FLayouter.Clear;
    AssertEquals('Clear empties them', 0, FLayouter.PictureCacheCount);
    // exceptions
    lo := TSeamLayouter.Create(TTyRichTestDevice.Create, True);
    lo.DecodeRaise := Exception;
    AssertFalse('a decoder that raises: a placeholder', lo.DrawPicture(bmp, pic,
      Rect(0, 0, 20, 10), 1, st));
    lo.Clear;
    lo.DecodeRaise := EAccessViolation;
    raised := False;
    try
      lo.DrawPicture(bmp, pic, Rect(0, 0, 20, 10), 1, st);
    except
      on E: EAccessViolation do raised := True;
    end;
    AssertTrue('an access violation goes through', raised);
    lo.Clear;
    lo.DecodeRaise := EOutOfMemory;
    raised := False;
    try
      lo.DrawPicture(bmp, pic, Rect(0, 0, 20, 10), 1, st);
    except
      on E: EOutOfMemory do raised := True;
    end;
    AssertTrue('out of memory goes through', raised);
    lo.Clear;
    lo.DecodeRaise := nil;
    lo.ScaleRaise := EOutOfMemory;
    raised := False;
    try
      lo.DrawPicture(bmp, pic, Rect(0, 0, 10, 5), 1, st);
    except
      on E: EOutOfMemory do raised := True;
    end;
    AssertTrue('also from the resampler', raised);
  finally
    lo.Free;
    bmp.Free;
    junk.Release;
    pic.Release;
  end;
end;

{ ---- fix wave W2: lists ---- }

{ A Word list interrupted by ordinary paragraphs: the items share \ls1 and the file says 1, 2,
  3 in their {\listtext}; that is what is shown, loaded on demand and loaded whole. A change
  that can renumber stops trusting the file's markers from its paragraph on (those below fall
  back to counting items one after another, so the list restarts after each body paragraph);
  typing does not; the document set again trusts them again. RichEdit's own lists show what
  they showed before. }
procedure TTyRichLayoutTest.TestWordListsShowTheFilesNumbers;
const
  Names: array[0..2] of string = ('re-zh-list.rtf', 'wp-zh-list.rtf', 'word-zh.rtf');
var
  d: TTyRichDocument;
  st: TBytesStream;
  lo: TTyRichLayouter;
  i, n: Integer;
  L2: TTyParaLayout;
begin
  d := LoadFixture('hand-word-list.rtf');
  AssertEquals('on demand: 1', '1.', Lay(d, 1, 1000).Marker.Text);
  AssertEquals('on demand: 2', '2.', Lay(d, 3, 1000).Marker.Text);
  AssertEquals('on demand: 3', '3.', Lay(d, 5, 1000).Marker.Text);
  d := TTyRichDocument.Create;
  FDocs.Add(d);
  st := TBytesStream.Create(FixtureBytes('hand-word-list.rtf'));
  try
    TyRichLoadRtfFull(d, st);
  finally
    st.Free;
  end;
  AssertEquals('whole: 1', '1.', Lay(d, 1, 1000).Marker.Text);
  AssertEquals('whole: 2', '2.', Lay(d, 3, 1000).Marker.Text);
  AssertEquals('whole: 3', '3.', Lay(d, 5, 1000).Marker.Text);
  d.OnChange := @DocChanged;
  // typing in an item: still the file's numbers
  AssertTrue('typed', d.Execute(TTyRichInsertText.Create(d.Text.ParaStart(5) + 1, 'x')));
  AssertEquals('typing: still 3', '3.', Lay(d, 5, 1000).Marker.Text);
  // a paragraph inserted above the second item
  AssertTrue('inserted', d.Execute(TTyRichInsertText.Create(d.Text.ParaStart(3), 'new'#10)));
  AssertEquals('above the change: the file''s', '1.', Lay(d, 1, 1000).Marker.Text);
  AssertEquals('at it: counted, after a body paragraph', '1.', Lay(d, 3, 1000).Marker.Text);
  AssertEquals('the next item: counted', '2.', Lay(d, 4, 1000).Marker.Text);
  AssertEquals('the third: counted, after a body paragraph', '1.', Lay(d, 6, 1000).Marker.Text);
  FLayouter.Document := d;
  AssertEquals('set again: the file''s again', '3.', Lay(d, 6, 1000).Marker.Text);
  // RichEdit's lists: the file's markers say what counting said
  for i := 0 to High(names) do
  begin
    d := LoadFixture(names[i]);
    lo := NewLayouter;
    try
      lo.Document := d;
      lo.Invalidate(0, 1);
      for n := 0 to d.Text.ParaCount - 1 do
      begin
        L2 := lo.LayoutPara(d, n, 1000, 96, 1);
        try
          AssertEquals(Format('%s paragraph %d', [names[i], n]), L2.Marker.Text,
            Lay(d, n, 1000).Marker.Text);
        finally
          L2.Release;
        end;
      end;
    finally
      lo.Free;
    end;
  end;
end;

{ A level-0 item after a sublist longer than the cap: the walk passes over the sublist up to
  the cap and anchors on the number remembered for the item before the sublist. With nothing
  remembered it counts from the cap (what remains, as the constant says). }
procedure TTyRichLayoutTest.TestACappedWalkAnchorsOnARememberedNumber;
const
  N = 5002;
var
  d: TTyRichDocument;
  s: RawByteString;
  i: Integer;
  lo: TTyRichLayouter;
  L: TTyParaLayout;
begin
  SetLength(s, 2 * N - 1);
  for i := 1 to N do
  begin
    s[2 * i - 1] := 'x';
    if i < N then s[2 * i] := #10;
  end;
  d := NewDoc(s);
  SetPara(d, 0, [pffList, pffLeftIndent, pffFirstIndent], ListFormat(lkDecimal, 0, 1));
  AssertTrue('the sublist', d.Execute(TTyRichSetParaFormat.Create(1, N - 2,
    [pffList, pffLeftIndent, pffFirstIndent], ListFormat(lkDecimal, 1, 1))));
  SetPara(d, N - 1, [pffList, pffLeftIndent, pffFirstIndent], ListFormat(lkDecimal, 0, 1));
  lo := NewLayouter;
  try
    L := lo.LayoutPara(d, N - 1, 1000, 96, 1);
    try
      AssertEquals('nothing remembered: counted from the cap', '1.', L.Marker.Text);
    finally
      L.Release;
    end;
  finally
    lo.Free;
  end;
  AssertEquals('the first item', '1.', Lay(d, 0, 1000).Marker.Text);
  AssertEquals('after the long sublist: from the one remembered', '2.',
    Lay(d, N - 1, 1000).Marker.Text);
end;

{ The marker moves with a centred or right-aligned first line (as Word and WordPad put it),
  and it is as tall as the first line needs to be: a list item that is only a small picture
  has its marker inside the line. }
procedure TTyRichLayoutTest.TestTheMarkerGoesWithTheFirstLine;
var
  d: TTyRichDocument;
  L0, L1, L2: TTyParaLayout;
  pf: TTyParaFormat;
begin
  d := NewDoc('abc'#10'abc'#10'abc');
  pf := ListFormat(lkBullet, 0, 0);
  SetPara(d, 0, [pffList, pffLeftIndent, pffFirstIndent], pf);
  pf.Align := paraCenter;
  SetPara(d, 1, [pffList, pffLeftIndent, pffFirstIndent, pffAlign], pf);
  pf.Align := paraRight;
  SetPara(d, 2, [pffList, pffLeftIndent, pffFirstIndent, pffAlign], pf);
  L0 := Lay(d, 0, 300);
  L1 := Lay(d, 1, 300);
  L2 := Lay(d, 2, 300);
  AssertTrue('centred: the marker moved', L1.Marker.X > L0.Marker.X);
  AssertEquals('centred: as far from the text as on the left',
    L0.Fragments[0].X - L0.Marker.X, L1.Fragments[0].X - L1.Marker.X);
  AssertEquals('right: as far from the text as on the left',
    L0.Fragments[0].X - L0.Marker.X, L2.Fragments[0].X - L2.Marker.X);
  AssertEquals('right: the text at the edge', 300, L2.Fragments[0].X + L2.Fragments[0].Width);
  // an item that is a picture 10 px tall: the marker's ascent (16) makes the line
  d := NewDoc('');
  AssertTrue('a picture', d.Execute(TTyRichInsertObject.Create(0,
    TTyRichPicture.Create(rpfPng, PngBytes(20, 10, BGRABlack), 300, 150))));
  SetPara(d, 0, [pffList, pffLeftIndent, pffFirstIndent], ListFormat(lkBullet, 0, 0));
  L0 := Lay(d, 0, 300);
  AssertEquals('the marker''s ascent', 16, L0.Marker.Ascent);
  AssertTrue(Format('its baseline under the marker''s top: %d', [L0.Lines[0].Baseline]),
    L0.Lines[0].Baseline >= L0.Marker.Ascent);
  AssertTrue('and the line holds its descent', L0.Lines[0].Height >=
    L0.Marker.Ascent + L0.Marker.Descent);
end;

{ A bullet for any level, the most negative included (Abs of it overflows). }
procedure TTyRichLayoutTest.TestBulletsForEveryLevel;
begin
  AssertEquals('level 0', U($2022), TyRichListMarkerText(lkBullet, 0, 0));
  AssertEquals('level 1', U($25E6), TyRichListMarkerText(lkBullet, 1, 0));
  AssertEquals('level 2', U($25AA), TyRichListMarkerText(lkBullet, 2, 0));
  AssertEquals('level 3: again', U($2022), TyRichListMarkerText(lkBullet, 3, 0));
  AssertEquals('level -1', U($25AA), TyRichListMarkerText(lkBullet, -1, 0));
  AssertEquals('Low(Integer)', U($25E6), TyRichListMarkerText(lkBullet, Low(Integer), 0));
  AssertEquals('High(Integer)', U($25E6), TyRichListMarkerText(lkBullet, High(Integer), 0));
end;

initialization
  RegisterTest(TTyRichLayoutTest);

end.
