unit tyControls.RichEdit.Builder;

{ TTyRichBuilder: content made from code - a home page, a navigation or a help page - in calls
  that read as the page does:

    B := TTyRichBuilder.Create;          // or Rich.NewBuilder (the document's defaults)
    B.Align(paraCenter).Font('Microsoft YaHei', 20).Bold.Text('Welcome');
    B.Paragraph.Reset.Text('Read the ').Link('guide', '#guide').Text('.');
    B.Paragraph.Picture(ImageList1, 3);
    B.Table([2400, 4800]).Cell.Text('Name').Cell.Text('What it is');
    B.Row.Cell.Text('A').Cell.Text('...').EndTable;
    B.Paragraph.Bookmark('guide').Bold.Text('The guide');
    Rich.SetContent(B);                  // or AppendContent / InsertContent; B is still yours

  It holds what is built as records - paragraphs, their runs, the pictures, links, bookmarks and
  tables - and makes a document of its own of them when it is put in (MakeDocument): the
  engine's fragment source, which the control's insert-fragment command takes. It needs no
  control and no document while it builds, so an importer (Markdown, docx) can be written
  against it alone. Everything is linear in what is built: formats are pooled (hashed), nothing
  is laid out.

  The state: a current character format, which every character method changes for what is
  added after it, and the format of the paragraph being built, which every paragraph method
  changes (any time before the next Paragraph). The first paragraph is there from the start;
  Paragraph ends it and starts the next in the default paragraph format, keeping the character
  format (Reset takes that back to the default). A builder with nothing added puts nothing in.

  Misuse - a cell outside a table, an EndTable without a table, a table inside a cell, a bad
  link address or bookmark name, a picture that cannot be read - raises ETyRichEdit, its text
  naming the call. Use it on the thread of the documents it goes into. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, ImgList, tyControls.RichEdit.Text, tyControls.RichEdit.Model,
  tyControls.RichEdit.Attrs;

type
  TTyRichBuilder = class
  private
    type
      TObjKind = (okNone, okPicture, okLinkOpen, okLinkClose, okBookmarkStart, okBookmarkEnd);
      TBRun = record
        Start: Integer;          // characters from the paragraph's start
        Format: Integer;         // the builder's pool
        Kind: TObjKind;
        Data: Integer;           // a picture's, a link's or a bookmark's index
      end;
      TBPara = record
        TextStart, TextLen: Integer;   // bytes of FText
        Chars: Integer;
        RunFirst, RunCount: Integer;
        Format: Integer;               // the builder's pool (-1 while it is being built)
        Table, Row, Cell: Integer;     // -1: in no table
      end;
      TBCell = record
        Shading: TColor;               // clNone: none (recorded for the table properties)
      end;
      TBRow = record
        HeightPt: Double;              // 0: automatic (recorded for the table properties)
        Cells: array of TBCell;
        CellCount: Integer;
      end;
      TBTable = record
        Widths: array of Integer;      // twips; empty: equal columns
        Rows: array of TBRow;
        RowCount: Integer;
      end;
      TBStyle = record
        Name: string;
        Char: TTyCharFormat;
        Para: TTyParaFormat;
      end;
  private
    FPool: TTyFormatPool;
    FText: RawByteString;
    FTextLen: Integer;
    FParas: array of TBPara;
    FParaCount: Integer;
    FRuns: array of TBRun;
    FRunCount: Integer;
    FPictures: array of TTyRichPicture;
    FPictureCount: Integer;
    FLinks: array of UTF8String;
    FLinkCount: Integer;
    FBookmarks: array of UTF8String;
    FBookmarkCount: Integer;
    FTables: array of TBTable;
    FTableCount: Integer;
    FStyles: array of TBStyle;
    FCurChar: TTyCharFormat;
    FCurCharId: Integer;           // -1: not interned yet
    FCurPara: TTyParaFormat;
    FDefaultChar: TTyCharFormat;
    FDefaultPara: TTyParaFormat;
    FTextWidth: Integer;
    // the table being built (-1: none), its row and whether a cell is open
    FTable, FCellOpen: Integer;
    FHasPage, FHasColor: Boolean;
    // the paragraph EndTable started holds nothing yet: a Paragraph right after is that one
    FAfterTable: Boolean;
    FPaperWidth, FMarginLeft, FMarginRight: Integer;
    FColor: TColor;
    FTouched: Boolean;
    procedure Misuse(const ACall, AWhat: string);
    function CharId: Integer;
    procedure CharChanged;
    procedure AddBytes(const S: RawByteString);
    procedure AddRun(AKind: TObjKind; AData, AFormat: Integer);
    procedure AddObject(AKind: TObjKind; AData, AFormat: Integer);
    procedure CloseParagraph;
    procedure OpenParagraph;
    procedure NeedTextPlace(const ACall: string);
    procedure AddPicture(const ACall: string; APic: TTyRichPicture);
    function PictureOfGraphic(const ACall: string; AGraphic: TGraphic;
      AWidthPt, AHeightPt: Double): TTyRichPicture;
    function PictureOfStream(const ACall: string; AStream: TStream;
      AWidthPt, AHeightPt: Double): TTyRichPicture;
    procedure CloseRow(const ACall: string);
    function ColumnEdges(ATable: Integer; ACells: Integer): TTyRichEdges;
  public
    { A builder of its own: the engine's defaults (the theme's font and size, no paragraph
      format of its own), a page text width of A4 with 1.25-inch margins (what a table of
      equal columns is spread over). }
    constructor Create;
    { The same with ACharDefault, AParaDefault as the defaults (what Reset and Paragraph go
      back to) and ATextWidthTwips as the width equal columns share - what a control's
      NewBuilder gives it from its document. }
    constructor CreateFor(const ACharDefault: TTyCharFormat; const AParaDefault: TTyParaFormat;
      ATextWidthTwips: Integer);
    destructor Destroy; override;

    { ---- the text ---- }
    { Ends the paragraph being built and starts the next in the default paragraph format
      (the character format stays). Inside a table cell: another paragraph of that cell. }
    function Paragraph: TTyRichBuilder;
    { S in the current character format: #9 a tab, #10 (or #13#10) a line break inside the
      paragraph; other control characters and U+FFFC are left out. Inside a table: after Cell. }
    function Text(const S: string): TTyRichBuilder;
    { The character format back to the document's default (the theme's for a builder of its
      own). }
    function Reset: TTyRichBuilder;

    { ---- the character format of what is added next ---- }
    { ASizePt 0: the size stays; to the half point. A name '' (or one the LCL takes for its
      default) is the document's own font. }
    function Font(const AName: string; ASizePt: Double = 0): TTyRichBuilder;
    function Bold(AOn: Boolean = True): TTyRichBuilder;
    function Italic(AOn: Boolean = True): TTyRichBuilder;
    function Underline(AOn: Boolean = True): TTyRichBuilder;
    function StrikeOut(AOn: Boolean = True): TTyRichBuilder;
    function Superscript(AOn: Boolean = True): TTyRichBuilder;
    function Subscript(AOn: Boolean = True): TTyRichBuilder;
    { A colour of the text's own (clDefault / clWindowText: automatic, the theme's). }
    function Color(AColor: TColor): TTyRichBuilder;
    { The text's highlight (clNone: none). }
    function Highlight(AColor: TColor): TTyRichBuilder;

    { ---- the format of the paragraph being built ---- }
    function Align(AAlign: TTyParaAlign): TTyRichBuilder;
    { Points: the lines after the first from the left margin, the first line's offset from
      them (negative: a hanging indent), from the right margin. }
    function Indent(ALeftPt, AFirstPt, ARightPt: Double): TTyRichBuilder;
    { The space before and after the paragraph, points. }
    function Spacing(ABeforePt, AAfterPt: Double): TTyRichBuilder;
    function SpaceBefore(APt: Double): TTyRichBuilder;
    function SpaceAfter(APt: Double): TTyRichBuilder;
    { The lines AMultiple times their own height (any multiple, to a 240th; 1 single). }
    function LineSpacing(AMultiple: Double): TTyRichBuilder;
    { The lines exactly APt points high. }
    function LineSpacingExact(APt: Double): TTyRichBuilder;
    { A tab stop added at APosPt points from the left indent's origin. }
    function Tab(APosPt: Double; AAlign: TTyRichTabAlign = rtaLeft;
      ALeader: TTyRichTabLeader = rtlNone): TTyRichBuilder;
    { A bullet item at ALevel (0 the outermost), its bullet AText ('' the round one); the
      default hanging indent of its level. }
    function Bullet(ALevel: Integer = 0; const AText: string = ''): TTyRichBuilder;
    { A numbered item (1, 2, 3 ...) at ALevel, its list starting at AStart. }
    function Numbered(ALevel: Integer = 0; AStart: Integer = 1): TTyRichBuilder;
    { The paragraph's ground (clNone: none). Inside a table cell: the cell's shading -
      recorded for the cell properties to come; until they come it shows nothing (a
      paragraph's shading is not put in its place). }
    function Shading(AColor: TColor): TTyRichBuilder;

    { ---- links and bookmarks ---- }
    { AText as a link to AURL, in the current character format underlined; automatic text is
      drawn in the theme's link colour, a colour of its own as it is. '#name' is the bookmark
      name in this document (a click jumps there by itself: FollowBookmarkLinks); 'file#name'
      a bookmark of another file. AText '' shows the address. The text comes first, in the
      order the page reads (as Text); the control's InsertLink(AURL, AText) takes the address
      first, its text being optional - mind the order. }
    function Link(const AText, AURL: string): TTyRichBuilder;
    { A bookmark AName at this place (a point: what a '#AName' link jumps to). Word's rule for
      the name (a letter first, letters, digits and '_', at most 40). }
    function Bookmark(const AName: string): TTyRichBuilder;
    { The start and the end of a bookmark over what lies between (in one paragraph or
      across). }
    function BookmarkStart(const AName: string): TTyRichBuilder;
    function BookmarkEnd(const AName: string): TTyRichBuilder;

    { ---- pictures: in line, a run of the paragraph being built ---- }
    { AWidthPt, AHeightPt: the size shown, points; both 0 its own (its pixels at 96 dpi); one
      0, in proportion. A PNG and a JPEG keep their bytes, any other graphic becomes PNG. }
    function Picture(AGraphic: TGraphic; AWidthPt: Double = 0; AHeightPt: Double = 0): TTyRichBuilder;
      overload;
    function Picture(const AFileName: string; AWidthPt: Double = 0;
      AHeightPt: Double = 0): TTyRichBuilder; overload;
    function Picture(AStream: TStream; AWidthPt: Double = 0;
      AHeightPt: Double = 0): TTyRichBuilder; overload;
    function Picture(AImages: TCustomImageList; AIndex: Integer; AWidthPt: Double = 0;
      AHeightPt: Double = 0): TTyRichBuilder; overload;
    { A picture of the application's resources (RCDATA, by name). }
    function PictureResource(const AResName: string; AWidthPt: Double = 0;
      AHeightPt: Double = 0): TTyRichBuilder;

    { ---- tables ---- }
    { A table, starting in a paragraph of its own: its columns AColWidthsTwips wide (empty:
      equal columns over the text width). Its first row is open; Cell opens each cell, Row
      the next row, EndTable ends it. A table inside a cell is not made (raises). }
    function Table(const AColWidthsTwips: array of Integer): TTyRichBuilder;
    { The next row; AHeightPt (0 automatic) is recorded for the row properties to come. }
    function Row(AHeightPt: Double = 0): TTyRichBuilder;
    { The next cell of the row: what follows is its content (paragraphs, links, pictures). }
    function Cell: TTyRichBuilder;
    { The table ends; what follows is a paragraph after it (a Paragraph right after EndTable
      is that same paragraph, not one more: call it twice for an empty one between). Every
      row must have as many cells as the table has columns. }
    function EndTable: TTyRichBuilder;

    { ---- styles: a convenience of the build, nothing of them goes into the document ---- }
    { The current character format and the paragraph format being built, under AName. }
    function DefineStyle(const AName: string): TTyRichBuilder;
    { Both formats of style AName applied: the character format for what follows, the
      paragraph format to the paragraph being built. }
    function Style(const AName: string): TTyRichBuilder;

    { ---- the document's own (taken by SetContent only) ---- }
    { The paper's width and the left and right margins, twips. }
    function PageSetup(AWidthTwips, ALeftTwips, ARightTwips: Integer): TTyRichBuilder;
    { The document's own ground (clNone: the theme's). }
    function DocumentColor(AColor: TColor): TTyRichBuilder;

    { ---- what was built ---- }
    { Nothing was added: no text, object, table, nor a paragraph or format change of the
      content. }
    function IsEmpty: Boolean;
    { A document of its own holding what was built (the caller's: a fragment's source, what
      TTyRichInsertFragment takes; one paragraph per paragraph built). The builder stays as it
      is and can make another. Raises when a table is not ended. }
    function MakeDocument: TTyRichDocument;
    { Paragraphs built so far (the one being built counts). }
    property ParagraphCount: Integer read FParaCount;
    property HasPageSetup: Boolean read FHasPage;
    property PaperWidth: Integer read FPaperWidth;
    property MarginLeft: Integer read FMarginLeft;
    property MarginRight: Integer read FMarginRight;
    property HasDocumentColor: Boolean read FHasColor;
    property DocumentColorValue: TColor read FColor;
  end;

implementation

uses
  Math, LCLType, LCLIntf, Types, tyControls.RichEdit.Commands, tyControls.RichEdit.RowFormat,
  tyControls.RichEdit.Bookmarks, tyControls.RichEdit;

type
  // the readers' way in: a document's text and paragraphs set as a load sets them
  TBuilderAccess = class(TTyRichDocBuilder)
  end;

const
  // A4 less WordPad's 1.25-inch margins (the engine's new document's page)
  CDefaultTextWidth = 11906 - 1800 - 1800;
  // U+FFFC, the character an object takes
  CObj: RawByteString = #$EF#$BF#$BC;

function PtTwips(APt: Double): Integer;
begin
  Result := Round(APt * 20);
end;

{ ---- TTyRichBuilder ---- }

constructor TTyRichBuilder.Create;
begin
  CreateFor(TyDefaultCharFormat, TyDefaultParaFormat, CDefaultTextWidth);
end;

constructor TTyRichBuilder.CreateFor(const ACharDefault: TTyCharFormat;
  const AParaDefault: TTyParaFormat; ATextWidthTwips: Integer);
begin
  inherited Create;
  FPool := TTyFormatPool.Create;
  FDefaultChar := ACharDefault;
  FDefaultPara := AParaDefault;
  if ATextWidthTwips > 0 then FTextWidth := ATextWidthTwips else FTextWidth := CDefaultTextWidth;
  FCurChar := FDefaultChar;
  FCurCharId := -1;
  FCurPara := FDefaultPara;
  FTable := -1;
  FCellOpen := -1;
  FColor := clNone;
  SetLength(FText, 256);
  OpenParagraph;
end;

destructor TTyRichBuilder.Destroy;
var
  i: Integer;
begin
  for i := 0 to FPictureCount - 1 do FPictures[i].Release;
  FPool.Free;
  inherited Destroy;
end;

procedure TTyRichBuilder.Misuse(const ACall, AWhat: string);
begin
  raise ETyRichEdit.CreateFmt('TTyRichBuilder.%s: %s', [ACall, AWhat]);
end;

function TTyRichBuilder.CharId: Integer;
begin
  if FCurCharId < 0 then FCurCharId := FPool.InternChar(FCurChar);
  Result := FCurCharId;
end;

procedure TTyRichBuilder.CharChanged;
begin
  FCurCharId := -1;
end;

procedure TTyRichBuilder.AddBytes(const S: RawByteString);
var
  n: Integer;
begin
  n := Length(S);
  if n = 0 then Exit;
  if FTextLen + n > Length(FText) then SetLength(FText, (FTextLen + n) * 2);
  Move(S[1], FText[FTextLen + 1], n);
  Inc(FTextLen, n);
end;

procedure TTyRichBuilder.AddRun(AKind: TObjKind; AData, AFormat: Integer);
var
  p: ^TBPara;
begin
  p := @FParas[FParaCount - 1];
  // text in the format of the run before it goes on in that run
  if (AKind = okNone) and (p^.RunCount > 0) and (FRuns[FRunCount - 1].Kind = okNone) and
     (FRuns[FRunCount - 1].Format = AFormat) then
    Exit;
  // an empty paragraph's one run (no characters yet) takes the format of what comes first
  if (p^.RunCount = 1) and (p^.Chars = 0) and (FRuns[FRunCount - 1].Kind = okNone) then
  begin
    FRuns[FRunCount - 1].Format := AFormat;
    FRuns[FRunCount - 1].Kind := AKind;
    FRuns[FRunCount - 1].Data := AData;
    Exit;
  end;
  if FRunCount = Length(FRuns) then SetLength(FRuns, FRunCount * 2 + 16);
  FRuns[FRunCount].Start := p^.Chars;
  FRuns[FRunCount].Format := AFormat;
  FRuns[FRunCount].Kind := AKind;
  FRuns[FRunCount].Data := AData;
  Inc(FRunCount);
  Inc(p^.RunCount);
end;

procedure TTyRichBuilder.AddObject(AKind: TObjKind; AData, AFormat: Integer);
begin
  FAfterTable := False;
  AddRun(AKind, AData, AFormat);
  AddBytes(CObj);
  Inc(FParas[FParaCount - 1].Chars);
  Inc(FParas[FParaCount - 1].TextLen, Length(CObj));
  FTouched := True;
end;

procedure TTyRichBuilder.OpenParagraph;
var
  p: ^TBPara;
begin
  if FParaCount = Length(FParas) then SetLength(FParas, FParaCount * 2 + 16);
  p := @FParas[FParaCount];
  Inc(FParaCount);
  p^.TextStart := FTextLen;
  p^.TextLen := 0;
  p^.Chars := 0;
  p^.RunFirst := FRunCount;
  p^.RunCount := 0;
  p^.Format := -1;
  p^.Table := -1;
  p^.Row := -1;
  p^.Cell := -1;
  // every paragraph has a run: the format an empty one shows (its mark's)
  if FRunCount = Length(FRuns) then SetLength(FRuns, FRunCount * 2 + 16);
  FRuns[FRunCount].Start := 0;
  FRuns[FRunCount].Format := CharId;
  FRuns[FRunCount].Kind := okNone;
  FRuns[FRunCount].Data := 0;
  Inc(FRunCount);
  p^.RunCount := 1;
end;

procedure TTyRichBuilder.CloseParagraph;
begin
  FParas[FParaCount - 1].Format := FPool.InternPara(FCurPara);
end;

procedure TTyRichBuilder.NeedTextPlace(const ACall: string);
begin
  if (FTable >= 0) and (FCellOpen < 0) then
    Misuse(ACall, 'inside a table, content goes into a cell: call Cell first');
end;

function TTyRichBuilder.Paragraph: TTyRichBuilder;
var
  t, r, c: Integer;
begin
  Result := Self;
  NeedTextPlace('Paragraph');
  // (EndTable began the paragraph after the table: B.EndTable; B.Paragraph... is one)
  if FAfterTable and (FParas[FParaCount - 1].Chars = 0) then
  begin
    FAfterTable := False;
    Exit;
  end;
  t := FParas[FParaCount - 1].Table;
  r := FParas[FParaCount - 1].Row;
  c := FParas[FParaCount - 1].Cell;
  CloseParagraph;
  OpenParagraph;
  // another paragraph of the same cell
  FParas[FParaCount - 1].Table := t;
  FParas[FParaCount - 1].Row := r;
  FParas[FParaCount - 1].Cell := c;
  FCurPara := FDefaultPara;
  FTouched := True;
end;

function TTyRichBuilder.Text(const S: string): TTyRichBuilder;
var
  i, n, start, chars: Integer;
  b: Byte;
  clean: RawByteString;
  p: ^TBPara;
begin
  Result := Self;
  if S = '' then Exit;
  NeedTextPlace('Text');
  // the bytes as they go in: #10 (#13#10) a line break, no other control character, no U+FFFC
  clean := '';
  SetLength(clean, Length(S) + 4);
  n := 0;
  chars := 0;
  i := 1;
  while i <= Length(S) do
  begin
    b := Ord(S[i]);
    if (b = 13) and (i < Length(S)) and (S[i + 1] = #10) then
    begin
      Inc(i);
      Continue;
    end;
    if (b = $EF) and (i + 2 <= Length(S)) and (S[i + 1] = #$BF) and (S[i + 2] = #$BC) then
    begin
      Inc(i, 3);
      Continue;
    end;
    if (b = 10) or (b = 13) then b := 11
    else if (b < 32) and (b <> 9) and (b <> 11) then
    begin
      Inc(i);
      Continue;
    end;
    if n >= Length(clean) then SetLength(clean, n * 2 + 8);
    Inc(n);
    clean[n] := AnsiChar(b);
    // a character is counted at its lead byte (a continuation byte starts none)
    if (b and $C0) <> $80 then Inc(chars);
    Inc(i);
  end;
  SetLength(clean, n);
  if n = 0 then Exit;
  FAfterTable := False;
  start := CharId;
  AddRun(okNone, 0, start);
  AddBytes(clean);
  p := @FParas[FParaCount - 1];
  Inc(p^.Chars, chars);
  Inc(p^.TextLen, n);
  FTouched := True;
end;

function TTyRichBuilder.Reset: TTyRichBuilder;
begin
  Result := Self;
  FCurChar := FDefaultChar;
  CharChanged;
end;

function TTyRichBuilder.Font(const AName: string; ASizePt: Double): TTyRichBuilder;
begin
  Result := Self;
  FCurChar.FontName := TyRichFontNameIn(AName);
  FCurChar.Charset := DEFAULT_CHARSET;
  if ASizePt > 0 then FCurChar.SizeHalfPt := Round(Min(ASizePt, 1638) * 2);
  CharChanged;
end;

function SetStyle(const AStyles: TFontStyles; AStyle: TFontStyle; AOn: Boolean): TFontStyles;
begin
  Result := AStyles;
  if AOn then Include(Result, AStyle) else Exclude(Result, AStyle);
end;

function TTyRichBuilder.Bold(AOn: Boolean): TTyRichBuilder;
begin
  Result := Self;
  FCurChar.Style := SetStyle(FCurChar.Style, fsBold, AOn);
  CharChanged;
end;

function TTyRichBuilder.Italic(AOn: Boolean): TTyRichBuilder;
begin
  Result := Self;
  FCurChar.Style := SetStyle(FCurChar.Style, fsItalic, AOn);
  CharChanged;
end;

function TTyRichBuilder.Underline(AOn: Boolean): TTyRichBuilder;
begin
  Result := Self;
  FCurChar.Style := SetStyle(FCurChar.Style, fsUnderline, AOn);
  CharChanged;
end;

function TTyRichBuilder.StrikeOut(AOn: Boolean): TTyRichBuilder;
begin
  Result := Self;
  FCurChar.Strike := AOn;
  FCurChar.Style := FCurChar.Style - [fsStrikeOut];
  CharChanged;
end;

function TTyRichBuilder.Superscript(AOn: Boolean): TTyRichBuilder;
begin
  Result := Self;
  if AOn then FCurChar.VertAlign := vaSuper
  else if FCurChar.VertAlign = vaSuper then FCurChar.VertAlign := vaNone;
  CharChanged;
end;

function TTyRichBuilder.Subscript(AOn: Boolean): TTyRichBuilder;
begin
  Result := Self;
  if AOn then FCurChar.VertAlign := vaSub
  else if FCurChar.VertAlign = vaSub then FCurChar.VertAlign := vaNone;
  CharChanged;
end;

function TTyRichBuilder.Color(AColor: TColor): TTyRichBuilder;
begin
  Result := Self;
  FCurChar.Color := TyRichTextColorIn(AColor);
  CharChanged;
end;

function TTyRichBuilder.Highlight(AColor: TColor): TTyRichBuilder;
begin
  Result := Self;
  FCurChar.HighlightColor := TyRichBackColorIn(AColor);
  CharChanged;
end;

function TTyRichBuilder.Align(AAlign: TTyParaAlign): TTyRichBuilder;
begin
  Result := Self;
  FCurPara.Align := AAlign;
  FTouched := True;
end;

function TTyRichBuilder.Indent(ALeftPt, AFirstPt, ARightPt: Double): TTyRichBuilder;
begin
  Result := Self;
  FCurPara.LeftIndent := PtTwips(ALeftPt);
  FCurPara.FirstIndent := PtTwips(AFirstPt);
  FCurPara.RightIndent := PtTwips(ARightPt);
  FTouched := True;
end;

function TTyRichBuilder.Spacing(ABeforePt, AAfterPt: Double): TTyRichBuilder;
begin
  Result := Self;
  FCurPara.SpaceBefore := Max(0, PtTwips(ABeforePt));
  FCurPara.SpaceAfter := Max(0, PtTwips(AAfterPt));
  FTouched := True;
end;

function TTyRichBuilder.SpaceBefore(APt: Double): TTyRichBuilder;
begin
  Result := Self;
  FCurPara.SpaceBefore := Max(0, PtTwips(APt));
  FTouched := True;
end;

function TTyRichBuilder.SpaceAfter(APt: Double): TTyRichBuilder;
begin
  Result := Self;
  FCurPara.SpaceAfter := Max(0, PtTwips(APt));
  FTouched := True;
end;

function TTyRichBuilder.LineSpacing(AMultiple: Double): TTyRichBuilder;
begin
  Result := Self;
  TyRichSetLineMultiple(FCurPara, AMultiple);
  FTouched := True;
end;

function TTyRichBuilder.LineSpacingExact(APt: Double): TTyRichBuilder;
begin
  Result := Self;
  FCurPara.LineSpacing := lsExact;
  FCurPara.LineSpacingValue := Max(1, PtTwips(APt));
  FTouched := True;
end;

function TTyRichBuilder.Tab(APosPt: Double; AAlign: TTyRichTabAlign;
  ALeader: TTyRichTabLeader): TTyRichBuilder;
var
  n: Integer;
begin
  Result := Self;
  // (a new array: a format pooled before keeps its own)
  FCurPara.Tabs := Copy(FCurPara.Tabs);
  n := Length(FCurPara.Tabs);
  SetLength(FCurPara.Tabs, n + 1);
  FCurPara.Tabs[n].Position := PtTwips(APosPt);
  FCurPara.Tabs[n].Align := AAlign;
  FCurPara.Tabs[n].Leader := ALeader;
  FTouched := True;
end;

function TTyRichBuilder.Bullet(ALevel: Integer; const AText: string): TTyRichBuilder;
begin
  Result := Self;
  if ALevel < 0 then ALevel := 0;
  FCurPara.List.Kind := lkBullet;
  FCurPara.List.Level := ALevel;
  FCurPara.List.StartAt := 0;
  FCurPara.List.Bullet := AText;
  // the default hanging indent, a half inch deeper a level
  FCurPara.LeftIndent := CTyListLeftIndent + ALevel * 360;
  FCurPara.FirstIndent := CTyListFirstIndent;
  FTouched := True;
end;

function TTyRichBuilder.Numbered(ALevel: Integer; AStart: Integer): TTyRichBuilder;
begin
  Result := Self;
  if ALevel < 0 then ALevel := 0;
  if AStart < 1 then AStart := 1;
  FCurPara.List.Kind := lkDecimal;
  FCurPara.List.Level := ALevel;
  FCurPara.List.StartAt := AStart;
  FCurPara.List.Bullet := '';
  FCurPara.LeftIndent := CTyListLeftIndent + ALevel * 360;
  FCurPara.FirstIndent := CTyListFirstIndent;
  FTouched := True;
end;

function TTyRichBuilder.Shading(AColor: TColor): TTyRichBuilder;
var
  p: ^TBPara;
begin
  Result := Self;
  p := @FParas[FParaCount - 1];
  if p^.Table >= 0 then
    // the cell's: recorded for the cell properties (see MakeDocument)
    FTables[p^.Table].Rows[p^.Row].Cells[p^.Cell].Shading := TyRichBackColorIn(AColor)
  else
    FCurPara.Shading := TyRichBackColorIn(AColor);
  FTouched := True;
end;

function TTyRichBuilder.Link(const AText, AURL: string): TTyRichBuilder;
var
  outside, look: Integer;
  f: TTyCharFormat;
begin
  Result := Self;
  NeedTextPlace('Link');
  if (AURL = '') or (AURL = '#') or (Pos(#10, AURL) > 0) or (Pos(#13, AURL) > 0) then
    Misuse('Link', Format('"%s" is no link address', [AURL]));
  if FLinkCount = Length(FLinks) then SetLength(FLinks, FLinkCount * 2 + 4);
  FLinks[FLinkCount] := AURL;
  outside := CharId;
  // the text underlined, its colour as it is (automatic: the theme's link colour)
  f := FCurChar;
  Include(f.Style, fsUnderline);
  look := FPool.InternChar(f);
  AddObject(okLinkOpen, FLinkCount, outside);
  if AText <> '' then
  begin
    FCurChar := f;
    FCurCharId := look;
    try
      Text(AText);
    finally
      FCurChar := FPool.CharFormat(outside);
      FCurCharId := outside;
    end;
  end
  else
  begin
    FCurChar := f;
    FCurCharId := look;
    try
      Text(AURL);
    finally
      FCurChar := FPool.CharFormat(outside);
      FCurCharId := outside;
    end;
  end;
  AddObject(okLinkClose, FLinkCount, outside);
  Inc(FLinkCount);
end;

function TTyRichBuilder.Bookmark(const AName: string): TTyRichBuilder;
begin
  BookmarkStart(AName);
  Result := BookmarkEnd(AName);
end;

function TTyRichBuilder.BookmarkStart(const AName: string): TTyRichBuilder;
begin
  Result := Self;
  NeedTextPlace('BookmarkStart');
  if not TyRichBookmarkNameValid(AName) then
    Misuse('BookmarkStart', Format('"%s" is no bookmark name (a letter first, then letters, ' +
      'digits and "_", at most 40)', [AName]));
  if FBookmarkCount = Length(FBookmarks) then SetLength(FBookmarks, FBookmarkCount * 2 + 4);
  FBookmarks[FBookmarkCount] := AName;
  AddObject(okBookmarkStart, FBookmarkCount, CharId);
  Inc(FBookmarkCount);
end;

function TTyRichBuilder.BookmarkEnd(const AName: string): TTyRichBuilder;
begin
  Result := Self;
  NeedTextPlace('BookmarkEnd');
  if not TyRichBookmarkNameValid(AName) then
    Misuse('BookmarkEnd', Format('"%s" is no bookmark name', [AName]));
  if FBookmarkCount = Length(FBookmarks) then SetLength(FBookmarks, FBookmarkCount * 2 + 4);
  FBookmarks[FBookmarkCount] := AName;
  AddObject(okBookmarkEnd, FBookmarkCount, CharId);
  Inc(FBookmarkCount);
end;

procedure TTyRichBuilder.AddPicture(const ACall: string; APic: TTyRichPicture);
begin
  NeedTextPlace(ACall);
  APic.AddRef;
  if FPictureCount = Length(FPictures) then SetLength(FPictures, FPictureCount * 2 + 4);
  FPictures[FPictureCount] := APic;
  AddObject(okPicture, FPictureCount, CharId);
  Inc(FPictureCount);
end;

function TTyRichBuilder.PictureOfGraphic(const ACall: string; AGraphic: TGraphic;
  AWidthPt, AHeightPt: Double): TTyRichPicture;
begin
  Result := nil;
  try
    Result := TTyRichInsertPicture.PictureOf(AGraphic, Max(0, PtTwips(AWidthPt)),
      Max(0, PtTwips(AHeightPt)));
  except
    on E: ETyRichModel do Misuse(ACall, E.Message);
  end;
end;

function TTyRichBuilder.PictureOfStream(const ACall: string; AStream: TStream;
  AWidthPt, AHeightPt: Double): TTyRichPicture;
var
  pic: TPicture;
begin
  Result := nil;
  pic := TPicture.Create;
  try
    try
      pic.LoadFromStream(AStream);
    except
      on E: Exception do Misuse(ACall, 'the picture cannot be read: ' + E.Message);
    end;
    Result := PictureOfGraphic(ACall, pic.Graphic, AWidthPt, AHeightPt);
  finally
    pic.Free;
  end;
end;

function TTyRichBuilder.Picture(AGraphic: TGraphic; AWidthPt, AHeightPt: Double): TTyRichBuilder;
begin
  Result := Self;
  NeedTextPlace('Picture');
  AddPicture('Picture', PictureOfGraphic('Picture', AGraphic, AWidthPt, AHeightPt));
end;

function TTyRichBuilder.Picture(const AFileName: string; AWidthPt, AHeightPt: Double): TTyRichBuilder;
var
  f: TFileStream;
begin
  Result := Self;
  NeedTextPlace('Picture');
  f := nil;
  try
    f := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  except
    on E: Exception do Misuse('Picture', 'the file cannot be read: ' + E.Message);
  end;
  try
    AddPicture('Picture', PictureOfStream('Picture', f, AWidthPt, AHeightPt));
  finally
    f.Free;
  end;
end;

function TTyRichBuilder.Picture(AStream: TStream; AWidthPt, AHeightPt: Double): TTyRichBuilder;
begin
  Result := Self;
  NeedTextPlace('Picture');
  if AStream = nil then Misuse('Picture', 'no stream');
  AddPicture('Picture', PictureOfStream('Picture', AStream, AWidthPt, AHeightPt));
end;

function TTyRichBuilder.Picture(AImages: TCustomImageList; AIndex: Integer; AWidthPt,
  AHeightPt: Double): TTyRichBuilder;
var
  pic: TTyRichPicture;
begin
  Result := Self;
  NeedTextPlace('Picture');
  pic := nil;
  try
    pic := TTyRichInsertPicture.PictureOfList(AImages, AIndex, Max(0, PtTwips(AWidthPt)),
      Max(0, PtTwips(AHeightPt)));
  except
    on E: ETyRichModel do Misuse('Picture', E.Message);
  end;
  AddPicture('Picture', pic);
end;

function TTyRichBuilder.PictureResource(const AResName: string; AWidthPt,
  AHeightPt: Double): TTyRichBuilder;
var
  st: TResourceStream;
begin
  Result := Self;
  NeedTextPlace('PictureResource');
  st := nil;
  try
    st := TResourceStream.Create(HInstance, AResName, RT_RCDATA);
  except
    on E: Exception do Misuse('PictureResource', 'no resource ' + AResName + ': ' + E.Message);
  end;
  try
    AddPicture('PictureResource', PictureOfStream('PictureResource', st, AWidthPt, AHeightPt));
  finally
    st.Free;
  end;
end;

function TTyRichBuilder.Table(const AColWidthsTwips: array of Integer): TTyRichBuilder;
var
  i: Integer;
  p: ^TBPara;
begin
  Result := Self;
  if FTable >= 0 then Misuse('Table', 'a table inside a table cell is not made');
  for i := 0 to High(AColWidthsTwips) do
    if AColWidthsTwips[i] <= 0 then Misuse('Table', 'a column width must be above 0');
  // a paragraph of its own: the one being built when it holds nothing, else the next
  p := @FParas[FParaCount - 1];
  if (p^.Chars > 0) then Paragraph;
  if FTableCount = Length(FTables) then SetLength(FTables, FTableCount * 2 + 2);
  FTables[FTableCount] := Default(TBTable);
  SetLength(FTables[FTableCount].Widths, Length(AColWidthsTwips));
  for i := 0 to High(AColWidthsTwips) do FTables[FTableCount].Widths[i] := AColWidthsTwips[i];
  SetLength(FTables[FTableCount].Rows, 4);
  FTables[FTableCount].RowCount := 1;
  FTables[FTableCount].Rows[0] := Default(TBRow);
  FTable := FTableCount;
  Inc(FTableCount);
  FCellOpen := -1;
  FTouched := True;
end;

procedure TTyRichBuilder.CloseRow(const ACall: string);
var
  t: ^TBTable;
begin
  t := @FTables[FTable];
  if t^.Rows[t^.RowCount - 1].CellCount = 0 then
    Misuse(ACall, Format('row %d has no cell', [t^.RowCount - 1]));
end;

function TTyRichBuilder.Row(AHeightPt: Double): TTyRichBuilder;
var
  t: ^TBTable;
begin
  Result := Self;
  if FTable < 0 then Misuse('Row', 'no table: call Table first');
  CloseRow('Row');
  t := @FTables[FTable];
  if t^.RowCount = Length(t^.Rows) then SetLength(t^.Rows, t^.RowCount * 2);
  t^.Rows[t^.RowCount] := Default(TBRow);
  t^.Rows[t^.RowCount].HeightPt := Max(0, AHeightPt);
  Inc(t^.RowCount);
  FCellOpen := -1;
end;

function TTyRichBuilder.Cell: TTyRichBuilder;
var
  t: ^TBTable;
  r: ^TBRow;
  p: ^TBPara;
  first: Boolean;
begin
  Result := Self;
  if FTable < 0 then Misuse('Cell', 'no table: Cell is called inside Table .. EndTable');
  t := @FTables[FTable];
  r := @t^.Rows[t^.RowCount - 1];
  if (Length(t^.Widths) > 0) and (r^.CellCount >= Length(t^.Widths)) then
    Misuse('Cell', Format('the table has %d columns', [Length(t^.Widths)]));
  // the first cell of the table takes the paragraph Table started; every other a new one
  p := @FParas[FParaCount - 1];
  first := (p^.Table < 0) and (p^.Chars = 0) and (FCellOpen < 0) and (t^.RowCount = 1) and
    (r^.CellCount = 0);
  if not first then
  begin
    CloseParagraph;
    OpenParagraph;
    FCurPara := FDefaultPara;
  end;
  if r^.CellCount = Length(r^.Cells) then SetLength(r^.Cells, r^.CellCount * 2 + 2);
  r^.Cells[r^.CellCount].Shading := clNone;
  p := @FParas[FParaCount - 1];
  p^.Table := FTable;
  p^.Row := t^.RowCount - 1;
  p^.Cell := r^.CellCount;
  FCellOpen := r^.CellCount;
  Inc(r^.CellCount);
  FTouched := True;
end;

function TTyRichBuilder.EndTable: TTyRichBuilder;
var
  t: ^TBTable;
  i, n: Integer;
begin
  Result := Self;
  if FTable < 0 then Misuse('EndTable', 'no table to end');
  CloseRow('EndTable');
  t := @FTables[FTable];
  if Length(t^.Widths) > 0 then n := Length(t^.Widths) else n := t^.Rows[0].CellCount;
  for i := 0 to t^.RowCount - 1 do
    if t^.Rows[i].CellCount <> n then
      Misuse('EndTable', Format('row %d has %d cells, the table %d columns',
        [i, t^.Rows[i].CellCount, n]));
  // what follows is a paragraph after the table
  CloseParagraph;
  FTable := -1;
  FCellOpen := -1;
  OpenParagraph;
  FCurPara := FDefaultPara;
  FAfterTable := True;
end;

function TTyRichBuilder.DefineStyle(const AName: string): TTyRichBuilder;
var
  i: Integer;
begin
  Result := Self;
  for i := 0 to High(FStyles) do
    if SameText(FStyles[i].Name, AName) then
    begin
      FStyles[i].Char := FCurChar;
      FStyles[i].Para := FCurPara;
      Exit;
    end;
  i := Length(FStyles);
  SetLength(FStyles, i + 1);
  FStyles[i].Name := AName;
  FStyles[i].Char := FCurChar;
  FStyles[i].Para := FCurPara;
end;

function TTyRichBuilder.Style(const AName: string): TTyRichBuilder;
var
  i: Integer;
begin
  Result := Self;
  for i := 0 to High(FStyles) do
    if SameText(FStyles[i].Name, AName) then
    begin
      FCurChar := FStyles[i].Char;
      CharChanged;
      FCurPara := FStyles[i].Para;
      FTouched := True;
      Exit;
    end;
  Misuse('Style', Format('no style "%s" (DefineStyle first)', [AName]));
end;

function TTyRichBuilder.PageSetup(AWidthTwips, ALeftTwips, ARightTwips: Integer): TTyRichBuilder;
begin
  Result := Self;
  if (AWidthTwips <= 0) or (ALeftTwips < 0) or (ARightTwips < 0) or
     (AWidthTwips - ALeftTwips - ARightTwips <= 0) then
    Misuse('PageSetup', 'the margins leave no width for the text');
  FHasPage := True;
  FPaperWidth := AWidthTwips;
  FMarginLeft := ALeftTwips;
  FMarginRight := ARightTwips;
  FTextWidth := AWidthTwips - ALeftTwips - ARightTwips;
end;

function TTyRichBuilder.DocumentColor(AColor: TColor): TTyRichBuilder;
begin
  Result := Self;
  FHasColor := True;
  if (AColor = clDefault) or (AColor = clWindow) then AColor := clNone;
  FColor := AColor;
end;

function TTyRichBuilder.IsEmpty: Boolean;
begin
  Result := not FTouched and (FParaCount = 1) and (FParas[0].Chars = 0) and
    FCurPara.Equals(FDefaultPara);
end;

function TTyRichBuilder.ColumnEdges(ATable: Integer; ACells: Integer): TTyRichEdges;
var
  i, w, x: Integer;
begin
  Result := nil;
  SetLength(Result, ACells);
  x := 0;
  for i := 0 to ACells - 1 do
  begin
    if Length(FTables[ATable].Widths) > 0 then w := FTables[ATable].Widths[i]
    else w := Max(1, FTextWidth div Max(1, ACells));
    Inc(x, w);
    Result[i] := x;
  end;
end;

function TTyRichBuilder.MakeDocument: TTyRichDocument;
var
  bytes: TBytes;
  charMap, paraMap: array of Integer;
  tables: array of TTyRichTable;
  opens, closes: array of TTyRichFieldMark;
  i, k, r, last: Integer;
  runs: TTyRunArray;
  run: ^TBRun;
  p: ^TBPara;
  edges: TTyRichEdges;
  bcell: TTyRichCell;
  obj: TTyRichObject;
  pf: Integer;
  doc: TTyRichDocument;

  function MapChar(AId: Integer): Integer;
  begin
    if charMap[AId] < 0 then charMap[AId] := doc.Formats.InternChar(FPool.CharFormat(AId));
    MapChar := charMap[AId];
  end;

begin
  if FTable >= 0 then raise ETyRichEdit.Create('TTyRichBuilder: a table is not ended (EndTable)');
  // the paragraph being built has its format as it is now (the builder goes on building)
  pf := FPool.InternPara(FCurPara);
  // the text: the paragraphs' bytes, a paragraph mark between them
  bytes := nil;
  SetLength(bytes, FTextLen + FParaCount);
  k := 0;
  for i := 0 to FParaCount - 1 do
  begin
    p := @FParas[i];
    if p^.TextLen > 0 then Move(FText[p^.TextStart + 1], bytes[k], p^.TextLen);
    Inc(k, p^.TextLen);
    if i < FParaCount - 1 then
    begin
      bytes[k] := 10;
      Inc(k);
    end;
  end;
  SetLength(bytes, k);
  Result := TTyRichDocument.Create;
  doc := Result;
  try
    TBuilderAccess.ReplaceText(Result, TTyRichText.CreateFromUtf8(bytes));
    charMap := nil;
    SetLength(charMap, FPool.CharCount);
    for i := 0 to High(charMap) do charMap[i] := -1;
    paraMap := nil;
    SetLength(paraMap, FPool.ParaCount);
    for i := 0 to High(paraMap) do paraMap[i] := -1;
    { The tables: rows of the cells built, the columns as given (or equal over the text
      width), each row in the engine's grid format (single lines, Word's half gap).
      >>> THE TABLE PROPERTIES' PLACE: once the table property commands are there
      (TTyRichSetCellProps, TTyRichSetRowProps of tyControls.RichEdit.TableProps), what the
      builder recorded and does not show yet goes into the table here - a cell's shading
      (FTables[t].Rows[r].Cells[c].Shading), a row's height (Rows[r].HeightPt); borders,
      padding and vertical alignment when the builder takes them. Until then the widths
      are the one property applied (they are the rows' own cell edges). <<< }
    tables := nil;
    SetLength(tables, FTableCount);
    for i := 0 to FTableCount - 1 do
    begin
      edges := ColumnEdges(i, FTables[i].Rows[0].CellCount);
      tables[i] := TTyRichTable.Create(edges);
      for r := 0 to FTables[i].RowCount - 1 do
        tables[i].AddRow(FTables[i].Rows[r].CellCount, TyRtfGridRowFormat(edges), edges);
    end;
    // the links' marks and the bookmarks', made anew for each document (their own ids)
    opens := nil;
    closes := nil;
    SetLength(opens, FLinkCount);
    SetLength(closes, FLinkCount);
    for i := 0 to FLinkCount - 1 do
    begin
      k := TTyRichFieldMark.NewId;
      opens[i] := TTyRichFieldMark.CreateOwned(rfmOpen, k, TyRichLinkInstruction(FLinks[i]));
      closes[i] := TTyRichFieldMark.CreateOwned(rfmClose, k);
    end;
    for i := 0 to FParaCount - 1 do
    begin
      p := @FParas[i];
      runs := nil;
      SetLength(runs, p^.RunCount);
      for k := 0 to p^.RunCount - 1 do
      begin
        run := @FRuns[p^.RunFirst + k];
        runs[k].Start := run^.Start;
        runs[k].Format := MapChar(run^.Format);
        case run^.Kind of
          okPicture: obj := FPictures[run^.Data];
          okLinkOpen: obj := opens[run^.Data];
          okLinkClose: obj := closes[run^.Data];
          okBookmarkStart: obj := TTyRichBookmarkMark.CreateNew(rbmStart, FBookmarks[run^.Data]);
          okBookmarkEnd: obj := TTyRichBookmarkMark.CreateNew(rbmEnd, FBookmarks[run^.Data]);
        else
          obj := nil;
        end;
        runs[k].Obj := obj;
      end;
      if i = FParaCount - 1 then last := pf else last := p^.Format;
      if paraMap[last] < 0 then paraMap[last] := Result.Formats.InternPara(FPool.ParaFormat(last));
      if p^.Table >= 0 then bcell := tables[p^.Table].Rows[p^.Row].Cells[p^.Cell] else bcell := nil;
      TBuilderAccess.SetParagraph(Result, i, paraMap[last], runs, bcell);
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
