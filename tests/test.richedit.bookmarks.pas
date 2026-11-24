unit test.richedit.bookmarks;

{ TTyRichEdit's bookmarks: listed, found, added, deleted and renamed, jumped to, and followed
  from a link to a place of the document; how a file's own bookmarks are kept byte for byte
  and how one made here is written; a document read on demand finds a bookmark by parsing only
  where it is.

  Headless, on the probe of test.richedit.fieldctl. No window, no clipboard, no dialog. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, fpcunit, testregistry, Controls, Graphics, LCLType, Forms,
  tyControls.Controller, tyControls.StrConsts,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.Bookmarks, tyControls.RichEdit.Builder,
  tyControls.RichEdit, test.richedit.fieldctl;

type
  { The probe with the pointer and the caret's ink to look at. }
  TBkmProbe = class(TFieldProbe)
  public
    function PointerAt(X, Y: Integer): TCursor;
    function CaretInk: Integer;
    // how many times the list BookmarkCount reads was built
    function ListBuilds: Integer;
  end;

  TTyRichBookmarksTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TFieldProbe;
    FClicks, FFollows: Integer;
    FClickPos: TTyRichPos;
    FFollowName: string;
    FAllow: Boolean;
    FDoOnFollow: Integer;     // 0 nothing, 1 free the control, 2 load another document
    procedure LinkClicked(Sender: TObject; const AURL: string; AButton: TMouseButton);
    procedure Follow(Sender: TObject; const AName: string; var AAllow: Boolean);
    procedure Load(const S: RawByteString);
    function Fixture(const AName: string): RawByteString;
    function SaveRtf: RawByteString;
    function Doc: TTyRichDocument;
    function TextOf(APos, ALen: TTyRichPos): RawByteString;
    function MarkAt(APos: TTyRichPos): TTyRichBookmarkMark;
    function ParaText(AIndex: Integer): RawByteString;
    procedure ClickChar(AChar: TTyRichPos);
    procedure CheckAgree(const AWhat: string; ARich: TFieldProbe = nil);
    function LazySource(ACount: Integer): RawByteString;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestBookmarksOfWordsFileAreListed;
    procedure TestGoToBookmarkScrollsAndPlacesTheCaret;
    procedure TestAClickOnAContentsEntryJumpsToItsHeading;
    procedure TestAddDeleteRenameAreOneUndoStepEach;
    procedure TestNamesFollowWordsRule;
    procedure TestOpenSaveStaysByteIdentical;
    procedure TestLazyFileFindsABookmarkWithoutReadingTheRest;
    procedure TestTheCaretNeverRestsBetweenBookmarkMarks;
    procedure TestADeletionThatHoldsOneEndCollapsesTheBookmark;
    procedure TestAHomePageFollowsItsLinks;
    procedure TestANameIsWrittenInTheFilesCodePage;
    procedure TestAJumpShowsItsTargetAtTheTop;
    procedure TestALinkToNoBookmarkAsksNothing;
    procedure TestTypingAtABookmarksEdgesAsWord;
    procedure TestAPasteTakesABookmarkAsWordDoes;
    procedure TestDeletingATableLeavesNoLoneMark;
    procedure TestALazyDeletionParsesOnlyItsEdges;
    procedure TestTheListIsKeptAcrossAKey;
    procedure TestNamesAreListedWithoutRegardToCase;
    procedure TestAddingANameOverItsOwnStart;
  end;

implementation

const
  BS = #92;
  Head = '{|rtf1|ansi|ansicpg936|deff0{|fonttbl{|f0 Arial;}}|pard|f0 ';

function Rtf(const S: RawByteString): RawByteString;
var
  i: Integer;
begin
  Result := S;
  UniqueString(Result);
  for i := 1 to Length(Result) do
    if Result[i] = '|' then Result[i] := BS;
  SetCodePage(Result, CP_NONE, False);
end;

function Raw(const S: string): RawByteString;
begin
  Result := S;
  SetCodePage(Result, CP_NONE, False);
end;

// (a literal of this unit is its UTF-8 bytes in a string: no conversion on the way)
function Valid(const S: string): Boolean;
begin
  Result := TyRichBookmarkNameValid(S);
end;

function BytesOf(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[0], Length(S));
end;

// how many times ASub is in S
function Occ(const S, ASub: RawByteString): Integer;
var
  p: Integer;
begin
  Result := 0;
  p := Pos(ASub, S);
  while p > 0 do
  begin
    Inc(Result);
    p := Pos(ASub, S, p + Length(ASub));
  end;
end;

{ ab[cd]ef / gh: a0 b1 start2 c3 d4 end5 e6 f7, the separator 8, g9 h10. }
function BaseDoc: RawByteString;
begin
  Result := Rtf(Head + 'ab{|*|bkmkstart m}cd{|*|bkmkend m}ef|par gh|par}');
end;

{ ---- the probe ---- }

function TBkmProbe.PointerAt(X, Y: Integer): TCursor;
begin
  Result := CursorAt(X, Y);
end;

function TBkmProbe.ListBuilds: Integer;
begin
  Result := BookmarkList.Builds;
end;

function TBkmProbe.CaretInk: Integer;
var
  bmp: TBitmap;
  x, y: Integer;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(Width, Height);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, Width, Height);
    DrawCaret(bmp.Canvas);
    Result := 0;
    for y := 0 to Height - 1 do
      for x := 0 to Width - 1 do
        if bmp.Canvas.Pixels[x, y] <> clWhite then Inc(Result);
  finally
    bmp.Free;
  end;
end;

{ ---- the suite ---- }

procedure TTyRichBookmarksTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FRich := TBkmProbe.Create(nil);
  FRich.Controller := FCtl;
  FRich.Font.PixelsPerInch := 96;
  FRich.SetBounds(0, 0, 600, 300);
  FRich.OnLinkClick := @LinkClicked;
  FClicks := 0;
  FFollows := 0;
  FAllow := True;
  FDoOnFollow := 0;
end;

procedure TTyRichBookmarksTest.TearDown;
begin
  FreeAndNil(FRich);
  FreeAndNil(FCtl);
end;

procedure TTyRichBookmarksTest.LinkClicked(Sender: TObject; const AURL: string;
  AButton: TMouseButton);
begin
  Inc(FClicks);
  // (followed after this handler: the caret is still where the click was)
  FClickPos := FRich.SelStart;
end;

procedure TTyRichBookmarksTest.Follow(Sender: TObject; const AName: string; var AAllow: Boolean);
begin
  Inc(FFollows);
  FFollowName := AName;
  AAllow := FAllow;
  case FDoOnFollow of
    1: FreeAndNil(FRich);
    2: Load(Rtf(Head + 'another|par}'));
  end;
end;

procedure TTyRichBookmarksTest.Load(const S: RawByteString);
var
  st: TBytesStream;
begin
  st := TBytesStream.Create(BytesOf(S));
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
  FRich.UpdateView;
  FRich.Refused := 0;
  FRich.LastReason := '';
end;

function TTyRichBookmarksTest.Fixture(const AName: string): RawByteString;
var
  f: TFileStream;
begin
  f := TFileStream.Create(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim +
    'fixtures' + PathDelim + 'rtf' + PathDelim + AName, fmOpenRead or fmShareDenyWrite);
  try
    Result := '';
    SetLength(Result, f.Size);
    if f.Size > 0 then f.ReadBuffer(Result[1], f.Size);
    SetCodePage(Result, CP_NONE, False);
  finally
    f.Free;
  end;
end;

function TTyRichBookmarksTest.SaveRtf: RawByteString;
var
  st: TBytesStream;
begin
  st := TBytesStream.Create;
  try
    FRich.SaveToStream(st, rfRtf);
    Result := '';
    SetLength(Result, st.Size);
    if st.Size > 0 then Move(st.Bytes[0], Result[1], st.Size);
    SetCodePage(Result, CP_NONE, False);
  finally
    st.Free;
  end;
end;

function TTyRichBookmarksTest.Doc: TTyRichDocument;
begin
  Result := FRich.Document;
end;

function TTyRichBookmarksTest.TextOf(APos, ALen: TTyRichPos): RawByteString;
begin
  Result := Doc.Text.GetText(APos, ALen);
  SetCodePage(Result, CP_NONE, False);
end;

function TTyRichBookmarksTest.MarkAt(APos: TTyRichPos): TTyRichBookmarkMark;
var
  o: TTyRichObject;
begin
  Result := nil;
  if (APos < 0) or (APos >= Doc.Text.Length) then Exit;
  o := Doc.ObjectAt(APos);
  if o is TTyRichBookmarkMark then Result := TTyRichBookmarkMark(o);
end;

function TTyRichBookmarksTest.ParaText(AIndex: Integer): RawByteString;
begin
  Result := TextOf(Doc.Text.ParaStart(AIndex), Doc.Text.ParaLength(AIndex));
end;

procedure TTyRichBookmarksTest.ClickChar(AChar: TTyRichPos);
var
  r, r2: TRect;
  x, y: Integer;
begin
  FRich.SelStart := AChar;
  FRich.UpdateView;
  r := FRich.PositionRect(AChar);
  r2 := FRich.PositionRect(AChar + 1, True);
  AssertTrue('the character is in view', r.Bottom > r.Top);
  x := (r.Left + r2.Left) div 2;
  y := (r.Top + r.Bottom) div 2;
  FRich.MDown(mbLeft, [ssLeft], x, y);
  if FRich <> nil then FRich.MUp(mbLeft, [], x, y);
end;

{ The file and the control agree: as many bookmarks counted as the saved file starts, and as
  many ends as starts (no lone mark). }
procedure TTyRichBookmarksTest.CheckAgree(const AWhat: string; ARich: TFieldProbe);
var
  st: TBytesStream;
  s: RawByteString;
begin
  if ARich = nil then ARich := FRich;
  st := TBytesStream.Create;
  try
    ARich.SaveToStream(st, rfRtf);
    s := '';
    SetLength(s, st.Size);
    if st.Size > 0 then Move(st.Bytes[0], s[1], st.Size);
    SetCodePage(s, CP_NONE, False);
  finally
    st.Free;
  end;
  AssertEquals(AWhat + ': the file''s starts are the count', ARich.BookmarkCount(True),
    Occ(s, Raw('bkmkstart')));
  AssertEquals(AWhat + ': as many ends', Occ(s, Raw('bkmkstart')), Occ(s, Raw('bkmkend')));
end;

{ ACount paragraphs, each with a bookmark bmN around "text of N": a file the control reads on
  demand. }
function TTyRichBookmarksTest.LazySource(ACount: Integer): RawByteString;
var
  i: Integer;
begin
  Result := Head;
  for i := 1 to ACount do
    Result := Result + 'paragraph number ' + IntToStr(i) + ' {|*|bkmkstart bm' + IntToStr(i) +
      '}text of ' + IntToStr(i) + '{|*|bkmkend bm' + IntToStr(i) + '} and some more words|par ';
  Result := Rtf(Result + '}');
end;

{ Word's file: its one visible bookmark (mark1) is listed; its 42 hidden ones for the table
  of contents' headings (_Toc...) only with the hidden ones - 43, as Word counts them; each is
  found by its name, in any case, and the text between its marks is the heading's. }
procedure TTyRichBookmarksTest.TestBookmarksOfWordsFileAreListed;
var
  i: Integer;
  s, e: TTyRichPos;
  m: TTyRichBookmarkMark;
begin
  Load(Fixture('word-toc.rtf'));
  AssertEquals('the visible ones', 1, FRich.BookmarkCount);
  AssertEquals('mark1', 'mark1', FRich.BookmarkName(0));
  AssertEquals('with the hidden ones, as Word counts them', 43, FRich.BookmarkCount(True));
  for i := 0 to FRich.BookmarkCount(True) - 1 do
    AssertTrue('found by its name: ' + FRich.BookmarkName(i, True),
      FRich.FindBookmark(FRich.BookmarkName(i, True), s, e));
  AssertTrue('any case', FRich.FindBookmark('MARK1', s, e));
  m := MarkAt(s);
  AssertTrue('a start mark there', (m <> nil) and (m.Kind = rbmStart) and (m.Name = 'mark1'));
  m := MarkAt(e);
  AssertTrue('its end mark', (m <> nil) and (m.Kind = rbmEnd) and (m.Name = 'mark1'));
  AssertTrue('a hidden one first', TyRichBookmarkHidden(FRich.BookmarkName(0, True)));
  AssertTrue('the first heading''s', FRich.FindBookmark('_Toc246044258', s, e));
  AssertTrue('its text is the heading''s', Pos(Raw('概述 Chapter 1'), TextOf(s, e - s)) > 0);
  AssertFalse('a name that is not there', FRich.FindBookmark('sec2', s, e));
end;

{ GoToBookmark: the caret to the bookmark's start (where it rests), shown; a move, also when
  ReadOnly; nothing for a name that is not there. }
procedure TTyRichBookmarksTest.TestGoToBookmarkScrollsAndPlacesTheCaret;
var
  src: RawByteString;
  i: Integer;
  s, e: TTyRichPos;
  r: TRect;
begin
  src := Head;
  for i := 1 to 200 do src := src + 'line ' + IntToStr(i) + '|par ';
  src := src + 'here {|*|bkmkstart far}target{|*|bkmkend far} text|par ';
  for i := 1 to 50 do src := src + 'more ' + IntToStr(i) + '|par ';
  Load(Rtf(src + '}'));
  FRich.ReadOnly := True;
  AssertTrue('found', FRich.FindBookmark('far', s, e));
  r := FRich.PositionRect(s);
  AssertTrue('not in view yet', r.Bottom <= r.Top);
  AssertTrue('gone to', FRich.GoToBookmark('far'));
  AssertEquals('the caret at its start, where it rests (after the start mark: in it)', s + 1,
    FRich.SelStart);
  AssertEquals('no selection', 0, FRich.SelLength);
  r := FRich.PositionRect(FRich.SelStart);
  AssertTrue('in view', (r.Bottom > r.Top) and (r.Top >= 0) and (r.Bottom <= FRich.Height));
  AssertTrue('the text after it', TextOf(FRich.SelStart, 6) = 'target');
  FRich.SelStart := 0;
  AssertFalse('a name that is not there', FRich.GoToBookmark('near'));
  AssertEquals('the caret stays', 0, FRich.SelStart);
  AssertEquals('nothing changed', 0, Doc.UndoDepth);
end;

{ A click on an entry of Word's table of contents (a \l link) goes to its heading; with
  FollowBookmarkLinks off, or OnFollowLink saying no, it stays; a link with a target and a
  place is not followed; a handler may free the control or load another document. }
procedure TTyRichBookmarksTest.TestAClickOnAContentsEntryJumpsToItsHeading;
var
  p, q, s, e: TTyRichPos;
  head: Integer;
begin
  Load(Fixture('word-toc.rtf'));
  FRich.ReadOnly := True;
  FRich.OnFollowLink := @Follow;
  // the tenth entry
  p := FRich.FindText('主题：用法 Usage', 0, -1, []);
  AssertTrue('the tenth entry', p > 0);
  AssertTrue('in the contents', Doc.FieldDepthAt(p) > 0);
  ClickChar(p + 1);
  AssertEquals('the click', 1, FClicks);
  AssertEquals('OnLinkClick before the jump', p + 1, FClickPos);
  AssertEquals('asked', 1, FFollows);
  AssertEquals('its bookmark', '_Toc246044267', FFollowName);
  AssertTrue('the bookmark', FRich.FindBookmark('_Toc246044267', s, e));
  head := Doc.Text.ParaOfPos(FRich.SelStart);
  AssertEquals('the caret at the heading', Doc.Text.ParaOfPos(s), head);
  AssertTrue('the heading''s paragraph', Pos(Raw('主题：用法 Usage'), ParaText(head)) > 0);
  AssertTrue('after the contents', head > Doc.Text.ParaOfPos(p));
  // not followed
  FRich.FollowBookmarkLinks := False;
  q := FRich.SelStart;
  ClickChar(p + 1);
  AssertEquals('off: the click', 2, FClicks);
  AssertEquals('off: not asked', 1, FFollows);
  FRich.FollowBookmarkLinks := True;
  FAllow := False;
  ClickChar(p + 1);
  AssertEquals('asked again', 2, FFollows);
  AssertEquals('refused: the caret where the click left it', p + 1, FRich.SelStart);
  FAllow := True;
  // a link to a place of the document alone: mark1
  q := FRich.FindText('到书签', 0, -1, []);
  AssertTrue('the link to mark1', q > 0);
  FFollows := 0;
  ClickChar(q + 1);
  AssertEquals('followed', 1, FFollows);
  AssertTrue('mark1', FRich.FindBookmark('mark1', s, e));
  AssertTrue('the caret at mark1', (FRich.SelStart <= s + 1) and
    (Doc.Text.ParaOfPos(FRich.SelStart) = Doc.Text.ParaOfPos(s)));
  // a target with a place: the application's
  q := FRich.FindText('page#sec2', 0, -1, []);
  AssertTrue('the link with a target and a place', q > 0);
  FFollows := 0;
  ClickChar(q + 1);
  AssertEquals('not followed', 0, FFollows);
  AssertEquals('the caret where the click left it', q + 1, FRich.SelStart);
  FFollows := 0;
  // the handler frees the control / loads another document
  FDoOnFollow := 2;
  ClickChar(p + 1);
  AssertTrue('another document', Pos(Raw('another'), TextOf(0, Doc.Text.Length)) > 0);
  Load(Fixture('word-toc.rtf'));
  FRich.ReadOnly := True;
  FDoOnFollow := 1;
  ClickChar(p + 1);
  AssertNull('freed by its handler', FRich);
end;

{ Add, delete and rename: one undo step each; saved, a made bookmark is Word's syntax and read
  back with its name - a Chinese one as \uN; the same name again moves the bookmark; undo
  gives the bytes back. }
procedure TTyRichBookmarksTest.TestAddDeleteRenameAreOneUndoStepEach;
var
  before, saved: RawByteString;
  depth: Integer;
  s, e: TTyRichPos;
begin
  Load(Rtf(Head + 'one two three|par four|par}'));
  before := SaveRtf;
  depth := Doc.UndoDepth;
  FRich.SelStart := 4;
  FRich.SelLength := 3;
  AssertTrue('can', FRich.CanEditBookmarks);
  AssertTrue('added', FRich.AddBookmark('b1'));
  AssertEquals('one step', depth + 1, Doc.UndoDepth);
  AssertTrue('found', FRich.FindBookmark('b1', s, e));
  AssertEquals('its start', 4, s);
  AssertEquals('its end', 8, e);
  AssertTrue('its text', TextOf(s + 1, e - s - 1) = 'two');
  saved := SaveRtf;
  AssertTrue('Word''s syntax', Pos(Rtf('{|*|bkmkstart b1}two{|*|bkmkend b1}'), saved) > 0);
  Load(saved);
  AssertTrue('read back', FRich.FindBookmark('b1', s, e));
  AssertTrue('read back: its text', TextOf(s + 1, e - s - 1) = 'two');
  FRich.Undo;   // (nothing: a load has no history)
  Load(before);
  FRich.SelStart := 4;
  FRich.SelLength := 3;
  FRich.AddBookmark('b1');
  FRich.Undo;
  AssertTrue('undone: the bytes', SaveRtf = before);
  // a Chinese name in a cp936 document: the bytes Word 16 writes for it, read back
  FRich.SelStart := 14;
  AssertTrue('a Chinese name', FRich.AddBookmark('第二节'));
  saved := SaveRtf;
  AssertTrue('written as Word writes it', Pos(Rtf('{|*|bkmkstart |''b5|''da|''b6|''fe|''bd|''da}'),
    saved) > 0);
  AssertTrue('its end too', Pos(Rtf('{|*|bkmkend |''b5|''da|''b6|''fe|''bd|''da}'), saved) > 0);
  Load(saved);
  AssertTrue('read back by its name', FRich.FindBookmark('第二节', s, e));
  AssertEquals('a place', s + 1, e);
  AssertEquals('listed', '第二节', FRich.BookmarkName(0));
  // the same name again: moved
  FRich.SelStart := 0;
  FRich.SelLength := 3;
  depth := Doc.UndoDepth;
  AssertTrue('again', FRich.AddBookmark('第二节'));
  AssertEquals('one step', depth + 1, Doc.UndoDepth);
  AssertEquals('one bookmark', 1, FRich.BookmarkCount);
  AssertTrue('moved', FRich.FindBookmark('第二节', s, e) and (s = 0) and (e = 4));
  // rename
  AssertTrue('renamed', FRich.RenameBookmark('第二节', 'sec2'));
  AssertEquals('one step', depth + 2, Doc.UndoDepth);
  AssertFalse('the old name gone', FRich.FindBookmark('第二节', s, e));
  AssertTrue('the new name', FRich.FindBookmark('SEC2', s, e) and (s = 0) and (e = 4));
  FRich.Undo;
  AssertTrue('undone: the old name', FRich.FindBookmark('第二节', s, e));
  FRich.Redo;
  // delete
  AssertTrue('deleted', FRich.DeleteBookmark('sec2'));
  AssertEquals('one step', depth + 3, Doc.UndoDepth);
  AssertEquals('none left', 0, FRich.BookmarkCount);
  AssertTrue('its text stays', TextOf(0, 3) = 'one');
  FRich.Undo;
  AssertEquals('undone: it is back', 1, FRich.BookmarkCount);
  // refusals told once
  FRich.Refused := 0;
  AssertFalse('no such bookmark', FRich.DeleteBookmark('nope'));
  AssertEquals('told', rsRichEditRefusedNoBookmark, FRich.LastReason);
  FRich.SelStart := 5;
  FRich.AddBookmark('other');
  FRich.Refused := 0;
  AssertFalse('a name in use', FRich.RenameBookmark('sec2', 'OTHER'));
  AssertEquals('told once', 1, FRich.Refused);
  AssertEquals('why', rsRichEditRefusedBookmarkExists, FRich.LastReason);
  // read-only: the door is closed, nothing told
  FRich.ReadOnly := True;
  FRich.Refused := 0;
  AssertFalse('read-only', FRich.AddBookmark('ro'));
  AssertFalse('read-only: Can...', FRich.CanEditBookmarks);
  AssertEquals('read-only: nothing told', 0, FRich.Refused);
end;

{ Word's rule for a new name: a letter (or an ideograph) first, then letters, digits and "_",
  at most 40. A refused name is told once and changes nothing; so is a place in a link's text;
  a bookmark may still be a place inside a result (Word's own are). }
procedure TTyRichBookmarksTest.TestNamesFollowWordsRule;
var
  before: RawByteString;
begin
  AssertTrue('a', Valid('a'));
  AssertTrue('Chapter_1', Valid('Chapter_1'));
  AssertTrue('第二节', Valid('第二节'));
  AssertTrue('节2', Valid('节2'));
  AssertTrue('40 letters', Valid(StringOfChar('x', 40)));
  AssertFalse('41 letters', Valid(StringOfChar('x', 41)));
  AssertFalse('empty', Valid(''));
  AssertFalse('a digit first', Valid('1a'));
  AssertFalse('_ first', Valid('_Toc1'));
  AssertFalse('a space', Valid('a b'));
  AssertFalse('a hyphen', Valid('a-b'));
  AssertFalse('a full stop', Valid('a.b'));
  AssertFalse('Chinese punctuation', Valid('节，二'));
  Load(Rtf(Head + 'ab {|field{|*|fldinst HYPERLINK "http://x"}{|fldrslt link}} cd|par}'));
  before := SaveRtf;
  FRich.SelStart := 0;
  AssertFalse('a digit first', FRich.AddBookmark('1x'));
  AssertEquals('told once', 1, FRich.Refused);
  AssertEquals('why', rsRichEditRefusedBookmarkName, FRich.LastReason);
  FRich.Refused := 0;
  FRich.SelStart := 5;
  AssertFalse('in a link''s text', FRich.AddBookmark('inlink'));
  AssertEquals('told once', 1, FRich.Refused);
  AssertEquals('the field''s reason', rsRichEditRefusedField, FRich.LastReason);
  AssertTrue('nothing changed', SaveRtf = before);
  AssertEquals('no step', 0, Doc.UndoDepth);
end;

{ Word's file open and saved: byte for byte; a bookmark added beside, the file's own
  bookmarks keep their bytes. }
procedure TTyRichBookmarksTest.TestOpenSaveStaysByteIdentical;
var
  f, saved: RawByteString;
  s, e: TTyRichPos;
begin
  f := Fixture('word-toc.rtf');
  Load(f);
  AssertTrue('as it came', SaveRtf = f);
  AssertTrue('mark1', FRich.FindBookmark('mark1', s, e));
  FRich.SelStart := Doc.Text.Length;
  AssertTrue('added', FRich.AddBookmark('added'));
  saved := SaveRtf;
  AssertTrue('the file''s own bytes for mark1', Pos(Rtf('{|*|bkmkstart mark1}'), saved) > 0);
  Load(saved);
  AssertEquals('both read back', 2, FRich.BookmarkCount);
  AssertEquals('and the hidden ones', 44, FRich.BookmarkCount(True));
end;

{ A file read on demand: a bookmark is found - and gone to - by parsing the intervals its two
  ends are in, no more; the names are listed with nothing parsed. }
procedure TTyRichBookmarksTest.TestLazyFileFindsABookmarkWithoutReadingTheRest;
var
  src: RawByteString;
  d: TTyRichDocument;
  st: TBytesStream;
  ld: TTyRtfLoad;
  i, parses: Integer;
  s, e: TTyRichPos;
  names: TStringArray;
begin
  src := Head;
  for i := 1 to 6000 do
    src := src + 'paragraph number ' + IntToStr(i) + ' {|*|bkmkstart bm' + IntToStr(i) +
      '}text of ' + IntToStr(i) + '{|*|bkmkend bm' + IntToStr(i) + '} and some more words|par ';
  src := Rtf(src + '}');
  d := TTyRichDocument.Create;
  try
    st := TBytesStream.Create(BytesOf(src));
    try
      TyRichLoadRtf(d, st);
    finally
      st.Free;
    end;
    ld := TyRichRtfLoadOf(d);
    AssertTrue('read on demand', ld <> nil);
    while not ld.Step(1 shl 20) do ;
    parses := ld.ParseCount;
    AssertTrue('found', TyRichFindBookmark(d, 'BM4321', s, e));
    AssertTrue('at most two intervals parsed', ld.ParseCount - parses <= 2);
    AssertTrue('its text', d.Text.GetText(s + 1, e - s - 1) = 'text of 4321');
    parses := ld.ParseCount;
    names := TyRichBookmarkNames(d, False);
    AssertEquals('every one listed', 6000, Length(names));
    AssertEquals('in order', 'bm1', names[0]);
    AssertEquals('in order: the last', 'bm6000', names[5999]);
    AssertEquals('listed with nothing parsed', parses, ld.ParseCount);
    parses := ld.ParseCount;
    AssertFalse('a name not there', TyRichFindBookmark(d, 'bm6001', s, e));
    AssertEquals('looked for with nothing parsed', parses, ld.ParseCount);
  finally
    d.Free;
  end;
end;

{ The two marks of a bookmark at one place are one resting place: the caret set anywhere in
  them rests at one position, and a key's step passes them. }
procedure TTyRichBookmarksTest.TestTheCaretNeverRestsBetweenBookmarkMarks;
var
  p, rest: TTyRichPos;
begin
  Load(Rtf(Head + 'ab{|*|bkmkstart m}{|*|bkmkend m}cd|par}'));
  FRich.SelStart := 2;
  rest := FRich.SelStart;
  for p := 2 to 4 do
  begin
    FRich.SelStart := p;
    AssertEquals('one resting place, from ' + IntToStr(p), rest, FRich.SelStart);
  end;
  FRich.SelStart := 1;
  FRich.Press(VK_RIGHT, []);
  AssertEquals('one step over b', rest, FRich.SelStart);
  FRich.Press(VK_RIGHT, []);
  AssertEquals('the next step is over c', 5, FRich.SelStart);
  // Delete and Backspace pass over them and leave them
  FRich.SelStart := rest;
  FRich.Press(VK_DELETE, []);
  AssertTrue('c went', TextOf(4, 1) = 'd');
  AssertTrue('the bookmark stays', FRich.FindBookmark('m', p, rest));
end;

{ A deletion that holds one end of a bookmark and not the other leaves both: the bookmark
  collapses to where the text was, as in Word; one that holds both takes it with it. }
procedure TTyRichBookmarksTest.TestADeletionThatHoldsOneEndCollapsesTheBookmark;
var
  s, e: TTyRichPos;
  before: RawByteString;
begin
  // ab[cd]ef: "b", the start mark and "c" deleted - the start stays where the text was
  Load(Rtf(Head + 'ab{|*|bkmkstart m}cd{|*|bkmkend m}ef|par}'));
  before := SaveRtf;
  FRich.SelStart := 1;
  FRich.SelLength := 3;    // b, the start mark, c
  FRich.Press(VK_DELETE, []);
  AssertTrue('found still', FRich.FindBookmark('m', s, e));
  AssertEquals('its start where the text was', 1, s);
  AssertTrue('the text', TextOf(0, 1) = 'a');
  AssertTrue('d is its text now', TextOf(s + 1, e - s - 1) = 'd');
  FRich.Undo;
  AssertTrue('undone: the bytes', SaveRtf = before);
  // the end held: the bookmark keeps its start and ends where the text was
  FRich.SelStart := 4;
  FRich.SelLength := 3;    // d, the end mark, e
  FRich.Press(VK_DELETE, []);
  AssertTrue('found still', FRich.FindBookmark('m', s, e));
  AssertTrue('its text', TextOf(s + 1, e - s - 1) = 'c');
  FRich.Undo;
  // both held: it goes
  FRich.SelStart := 1;
  FRich.SelLength := 6;
  FRich.Press(VK_DELETE, []);
  AssertFalse('gone with the text', FRich.FindBookmark('m', s, e));
  FRich.Undo;
  AssertTrue('undone: the bytes', SaveRtf = before);
end;

{ A home page: read-only, no selection, no caret, no focus by a click. Its "#name" link is
  under the hand, a plain left click fires it and the control goes to the bookmark - in
  view, still no caret drawn, nothing selected. }
procedure TTyRichBookmarksTest.TestAHomePageFollowsItsLinks;
var
  src: RawByteString;
  i: Integer;
  p, s, e: TTyRichPos;
  r, r2: TRect;
  x, y: Integer;
begin
  src := Head + 'go {|field{|*|fldinst HYPERLINK ||l "far"}{|fldrslt there}}|par ';
  for i := 1 to 200 do src := src + 'line ' + IntToStr(i) + '|par ';
  src := src + '{|*|bkmkstart far}the far place{|*|bkmkend far}|par }';
  Load(Rtf(src));
  FRich.ReadOnly := True;
  FRich.AllowSelection := False;
  FRich.CaretWhenReadOnly := False;
  FRich.FocusOnClick := False;
  FRich.OnFollowLink := @Follow;
  FRich.UpdateView;
  p := 4;
  r := FRich.PositionRect(p);
  r2 := FRich.PositionRect(p + 1, True);
  x := (r.Left + r2.Left) div 2;
  y := (r.Top + r.Bottom) div 2;
  AssertTrue('the hand over the link', TBkmProbe(FRich).PointerAt(x, y) = crHandPoint);
  FRich.MDown(mbLeft, [ssLeft], x, y);
  FRich.MUp(mbLeft, [], x, y);
  AssertEquals('the click', 1, FClicks);
  AssertEquals('followed', 1, FFollows);
  AssertTrue('the bookmark', FRich.FindBookmark('far', s, e));
  r := FRich.PositionRect(s + 1);
  AssertTrue('the bookmark in view', (r.Bottom > r.Top) and (r.Top >= 0) and
    (r.Bottom <= FRich.Height));
  AssertEquals('nothing selected', 0, FRich.SelLength);
  AssertEquals('no caret drawn', 0, TBkmProbe(FRich).CaretInk);
  AssertFalse('no focus taken', FRich.Focused);
end;

{ A name made here is written as Word writes it: the file's code page's bytes where every
  character has them (cp936: the bytes Word 16 wrote for 第二节), \uN for one that has none
  there (Hangul in cp936); both read back. A link to "#第二节" made here jumps to it after a
  save and a reload. }
procedure TTyRichBookmarksTest.TestANameIsWrittenInTheFilesCodePage;
var
  saved: RawByteString;
  s, e, p: TTyRichPos;
begin
  Load(Rtf(Head + 'one two|par three|par}'));
  FRich.SelStart := 0;
  AssertTrue('a name with no cp936 form', FRich.AddBookmark('장'));
  FRich.SelStart := Doc.Text.ParaStart(1);
  AssertTrue('a Chinese one', FRich.AddBookmark('第二节'));
  FRich.SelStart := Doc.Text.Length;
  AssertTrue('a link to it', FRich.InsertLink('#第二节', 'go'));
  saved := SaveRtf;
  AssertTrue('Hangul as Unicode', Pos(Rtf('{|*|bkmkstart |u-14427?}'), saved) > 0);
  AssertTrue('Chinese as the code page''s bytes',
    Pos(Rtf('{|*|bkmkstart |''b5|''da|''b6|''fe|''bd|''da}'), saved) > 0);
  Load(saved);
  AssertTrue('read back: Hangul', FRich.FindBookmark('장', s, e));
  AssertTrue('read back: Chinese', FRich.FindBookmark('第二节', s, e));
  AssertTrue('read back: its paragraph', Doc.Text.ParaOfPos(s) = 1);
  FRich.ReadOnly := True;
  FRich.OnFollowLink := @Follow;
  p := FRich.FindText('go', 0, -1, []);
  AssertTrue('the link', p > 0);
  FRich.SelStart := 0;
  ClickChar(p);
  AssertEquals('followed', 1, FFollows);
  AssertEquals('to its name', '第二节', FFollowName);
  AssertTrue('the caret at it', Doc.Text.ParaOfPos(FRich.SelStart) = 1);
end;

{ A jump shows its target where reading starts: the contents' tenth entry followed, its
  heading's line at the view's top (the text area's top: the padding above it); a target in
  view in the top third already: nothing moves; the document's last heading: the view ends at
  the document's end. }
procedure TTyRichBookmarksTest.TestAJumpShowsItsTargetAtTheTop;
var
  p, s, e: TTyRichPos;
  r: TRect;
  src: RawByteString;
  i: Integer;
  y0: Int64;
begin
  Load(Fixture('word-toc.rtf'));
  FRich.ReadOnly := True;
  p := FRich.FindText('主题：用法 Usage', 0, -1, []);
  AssertTrue('the tenth entry', p > 0);
  ClickChar(p + 1);
  AssertTrue('the bookmark', FRich.FindBookmark('_Toc246044267', s, e));
  AssertEquals('the caret at the heading', Doc.Text.ParaOfPos(s), Doc.Text.ParaOfPos(FRich.SelStart));
  r := FRich.PositionRect(FRich.SelStart);
  AssertTrue(Format('the heading''s line at the top (%d, the text''s top %d)',
    [r.Top, FRich.Area.Top]), Abs(r.Top - FRich.Area.Top) <= 1);
  // already in the top third: no scroll
  src := Head;
  for i := 1 to 100 do src := src + 'line ' + IntToStr(i) + '|par ';
  src := src + '{|*|bkmkstart a}first{|*|bkmkend a}|par second|par {|*|bkmkstart b}third{|*|bkmkend b}|par ';
  for i := 1 to 100 do src := src + 'more ' + IntToStr(i) + '|par ';
  src := src + '{|*|bkmkstart last}the last line{|*|bkmkend last}|par }';
  Load(Rtf(src));
  AssertTrue('to a', FRich.GoToBookmark('a'));
  r := FRich.PositionRect(FRich.SelStart);
  AssertTrue('a at the top', Abs(r.Top - FRich.Area.Top) <= 1);
  y0 := FRich.ScrollY;
  AssertTrue('to b', FRich.GoToBookmark('b'));
  AssertEquals('b in the top third already: no scroll', y0, FRich.ScrollY);
  FRich.FindBookmark('b', s, e);
  AssertEquals('the caret at b (after its start mark)', s + 1, FRich.SelStart);
  // the last line: the view ends at the document's end
  AssertTrue('to the last', FRich.GoToBookmark('last'));
  y0 := FRich.ScrollY;
  FRich.ScrollViewBy(200);
  AssertEquals('at the end already', y0, FRich.ScrollY);
  r := FRich.PositionRect(FRich.SelStart);
  AssertTrue('the last line in view', (r.Bottom > r.Top) and (r.Bottom <= FRich.Height));
  AssertTrue('not at the top: the document ends below it', r.Top > FRich.Area.Top + 10);
end;

{ A link to a bookmark that is not there: the click is told (OnLinkClick), nothing is
  followed and OnFollowLink is not asked - the control looks first. }
procedure TTyRichBookmarksTest.TestALinkToNoBookmarkAsksNothing;
begin
  FRich.Lines.Text := 'Go there, or stay here.';
  FRich.UpdateView;
  FRich.SelStart := 0;
  FRich.SelLength := 8;
  AssertTrue('a link', FRich.InsertLink('#missing'));
  FRich.Lines.Add('Second paragraph.');
  FRich.ReadOnly := True;
  FRich.OnFollowLink := @Follow;
  FRich.UpdateView;
  FClicks := 0;
  FFollows := 0;
  ClickChar(3);
  AssertEquals('the click is told', 1, FClicks);
  AssertEquals('no such bookmark: not asked', 0, FFollows);
end;

{ As Word has it: typed right at a bookmark's start (after its opening mark), text is in the
  bookmark; right at its end (after its closing mark), outside it; at a bookmark that is a
  place, the place stays before the text. So for a paste and an input method's text. A link's
  marks are as they were: typed at a link's edges, text is outside the link - also where a
  bookmark's start is right before the link, or right inside it. }
procedure TTyRichBookmarksTest.TestTypingAtABookmarksEdgesAsWord;
var
  s, e: TTyRichPos;
  before: RawByteString;
begin
  Load(BaseDoc);
  before := SaveRtf;
  FRich.SelStart := 2;
  AssertEquals('the caret at the start rests after its mark', 3, FRich.SelStart);
  FRich.Key8('X');
  AssertTrue('found', FRich.FindBookmark('m', s, e));
  AssertTrue('typed at the start: in the bookmark', TextOf(s + 1, e - s - 1) = 'Xcd');
  FRich.Undo;
  AssertTrue('undone', SaveRtf = before);
  FRich.SelStart := 5;
  AssertEquals('the caret at the end rests after its mark', 6, FRich.SelStart);
  FRich.Key8('Y');
  AssertTrue('found', FRich.FindBookmark('m', s, e));
  AssertTrue('typed at the end: outside it', TextOf(s + 1, e - s - 1) = 'cd');
  AssertTrue('right after its end', TextOf(e + 1, 1) = 'Y');
  FRich.Undo;
  // a paste and an input method's text go where typing goes
  FRich.SelStart := 2;
  FRich.ClipRtf := '';
  FRich.ClipText := 'P';
  FRich.PasteFromClipboard;
  FRich.FindBookmark('m', s, e);
  AssertTrue('pasted at the start: in it', TextOf(s + 1, e - s - 1) = 'Pcd');
  FRich.Undo;
  FRich.SelStart := 5;
  FRich.PasteFromClipboard;
  FRich.FindBookmark('m', s, e);
  AssertTrue('pasted at the end: outside', (TextOf(s + 1, e - s - 1) = 'cd') and (TextOf(e + 1, 1) = 'P'));
  FRich.Undo;
  FRich.SelStart := 2;
  AssertTrue('a composition', FRich.BeginComposition);
  FRich.UpdateComposition('zz');
  FRich.CommitComposition('zz');
  FRich.FindBookmark('m', s, e);
  AssertTrue('committed at the start: in it', TextOf(s + 1, e - s - 1) = 'zzcd');
  FRich.Undo;
  FRich.SelStart := 5;
  AssertTrue('a composition', FRich.BeginComposition);
  FRich.UpdateComposition('zz');
  FRich.CommitComposition('zz');
  FRich.FindBookmark('m', s, e);
  AssertTrue('committed at the end: outside', TextOf(s + 1, e - s - 1) = 'cd');
  FRich.Undo;
  AssertTrue('undone at last', SaveRtf = before);
  // a place: it stays before what is typed there
  Load(Rtf(Head + 'ab{|*|bkmkstart p}{|*|bkmkend p}cd|par}'));
  FRich.SelStart := 2;
  FRich.Key8('Z');
  AssertTrue('found', FRich.FindBookmark('p', s, e));
  AssertEquals('still a place', s + 1, e);
  AssertTrue('the text after it', TextOf(e + 1, 1) = 'Z');
  // a bookmark's start right before a link: typed there, in the bookmark, outside the link
  Load(Rtf(Head + 'ab {|*|bkmkstart k}{|field{|*|fldinst HYPERLINK "http://x"}{|fldrslt link}}' +
    '{|*|bkmkend k} cd|par}'));
  FRich.SelStart := 3;
  AssertEquals('between the bookmark''s start and the link', 4, FRich.SelStart);
  FRich.Key8('Q');
  AssertTrue('typed: in the bookmark', FRich.FindBookmark('k', s, e) and (TextOf(s + 1, 1) = 'Q'));
  AssertTrue('the link''s open mark after it', Doc.ObjectAt(5) is TTyRichFieldMark);
  AssertEquals('nothing refused', 0, FRich.Refused);
  // a bookmark right inside a link's result: typed at the link's start, outside the link
  Load(Rtf(Head + 'ab {|field{|*|fldinst HYPERLINK "http://x"}{|fldrslt {|*|bkmkstart i}link' +
    '{|*|bkmkend i}}} cd|par}'));
  FRich.SelStart := 4;
  AssertEquals('before the link''s open mark', 3, FRich.SelStart);
  FRich.Key8('W');
  AssertTrue('typed before the link', TextOf(3, 1) = 'W');
  AssertTrue('the link''s open mark after it', Doc.ObjectAt(4) is TTyRichFieldMark);
  AssertEquals('nothing refused', 0, FRich.Refused);
end;

{ A copy of a bookmark pasted - or dropped, or put in by InsertContent / AppendContent - into a
  document that has its name: its text comes in, the bookmark does not (the original stays);
  one of its ends alone: left out too. A cut and a paste, and a drag that moves, move it. Into
  a control that has no such name, it comes along. One step each, undone to the bytes; the
  count and the file agree every time. }
procedure TTyRichBookmarksTest.TestAPasteTakesABookmarkAsWordDoes;
var
  before, clip, part: RawByteString;
  s, e: TTyRichPos;
  depth: Integer;
  other: TFieldProbe;
  st: TBytesStream;
  B: TTyRichBuilder;
begin
  Load(BaseDoc);
  before := SaveRtf;
  FRich.SelStart := 1;
  FRich.SelLength := 6;
  FRich.ClipRtf := '';
  FRich.CopyToClipboard;
  clip := FRich.ClipRtf;
  AssertTrue('copied with its bookmark', Pos(Raw('bkmkstart m'), clip) > 0);
  depth := Doc.UndoDepth;
  FRich.SelStart := 10;
  FRich.PasteFromClipboard;
  AssertEquals('one step', depth + 1, Doc.UndoDepth);
  AssertTrue('the text came in', ParaText(1) = 'gbcdeh');
  AssertEquals('the caret after it', 14, FRich.SelStart);
  AssertEquals('one bookmark', 1, FRich.BookmarkCount);
  AssertTrue('the original stays', FRich.FindBookmark('m', s, e) and (s = 2) and (e = 5));
  CheckAgree('a copy pasted');
  FRich.Undo;
  AssertTrue('undone: the bytes', SaveRtf = before);
  FRich.Redo;
  AssertTrue('redone: the text', ParaText(1) = 'gbcdeh');
  CheckAgree('redone');
  FRich.Undo;
  // one end of it only
  FRich.SelStart := 1;
  FRich.SelLength := 3;
  FRich.ClipRtf := '';
  FRich.CopyToClipboard;
  part := FRich.ClipRtf;
  AssertTrue('copied with the start alone', Pos(Raw('bkmkstart m'), part) > 0);
  FRich.SelStart := 10;
  FRich.PasteFromClipboard;
  AssertTrue('its text', ParaText(1) = 'gbch');
  AssertEquals('one bookmark', 1, FRich.BookmarkCount);
  AssertTrue('the original stays', FRich.FindBookmark('m', s, e) and (s = 2) and (e = 5));
  CheckAgree('one end pasted');
  FRich.Undo;
  AssertTrue('undone: the bytes', SaveRtf = before);
  // cut and pasted: moved
  FRich.SelStart := 1;
  FRich.SelLength := 6;
  FRich.CutToClipboard;
  AssertEquals('cut: gone', 0, FRich.BookmarkCount);
  FRich.SelStart := Doc.Text.ParaStart(1) + 1;
  FRich.PasteFromClipboard;
  AssertEquals('moved', 1, FRich.BookmarkCount);
  AssertTrue('in the second paragraph', FRich.FindBookmark('m', s, e) and
    (Doc.Text.ParaOfPos(s) = 1));
  AssertTrue('around its text', TextOf(s + 1, e - s - 1) = 'cd');
  CheckAgree('cut and pasted');
  FRich.Undo;
  FRich.Undo;
  AssertTrue('undone: the bytes', SaveRtf = before);
  // a drag inside the control: a move moves it, a copy leaves it out
  AssertTrue('moved by a drag', Doc.Execute(TTyRichMove.Create(1, 6, 10)));
  AssertTrue('moved', FRich.FindBookmark('m', s, e) and (Doc.Text.ParaOfPos(s) = 1));
  AssertTrue('around its text', TextOf(s + 1, e - s - 1) = 'cd');
  CheckAgree('a drag that moves');
  FRich.Undo;
  AssertTrue('undone: the bytes', SaveRtf = before);
  AssertTrue('copied by a drag', Doc.Execute(TTyRichCopy.Create(1, 6, 10)));
  AssertTrue('the text came in', ParaText(1) = 'gbcdeh');
  AssertTrue('the original stays', FRich.FindBookmark('m', s, e) and (s = 2) and (e = 5));
  CheckAgree('a drag that copies');
  FRich.Undo;
  AssertTrue('undone: the bytes', SaveRtf = before);
  // the content's doors: a name the document has (in another case) left out, a new one kept
  B := TTyRichBuilder.Create;
  try
    B.Text('new ').Bookmark('M').Text('place');
    depth := Doc.UndoDepth;
    FRich.AppendContent(B);
    AssertEquals('appended: one step', depth + 1, Doc.UndoDepth);
    AssertEquals('appended: one bookmark', 1, FRich.BookmarkCount);
    AssertTrue('the original stays', FRich.FindBookmark('m', s, e) and (s = 2) and (e = 5));
    AssertTrue('its text came in', ParaText(Doc.Text.ParaCount - 1) = 'new place');
    CheckAgree('appended');
    FRich.Undo;
    AssertTrue('undone: the bytes', SaveRtf = before);
    FRich.InsertContent(10, B);
    AssertEquals('inserted: one bookmark', 1, FRich.BookmarkCount);
    AssertTrue('the original stays', FRich.FindBookmark('m', s, e) and (s = 2) and (e = 5));
    CheckAgree('inserted');
    FRich.Undo;
    AssertTrue('undone: the bytes', SaveRtf = before);
    B.Text(' and ').Bookmark('fresh');
    FRich.AppendContent(B);
    AssertEquals('a new name comes in', 2, FRich.BookmarkCount);
    AssertTrue('found', FRich.FindBookmark('fresh', s, e));
    CheckAgree('a new name');
  finally
    B.Free;
  end;
  // into another control that has no such name: it comes along
  other := TFieldProbe.Create(nil);
  try
    other.Controller := FCtl;
    other.SetBounds(0, 0, 400, 200);
    st := TBytesStream.Create(BytesOf(Rtf(Head + 'xy|par}')));
    try
      other.LoadFromStream(st);
    finally
      st.Free;
    end;
    other.FinishLoading;
    other.ClipRtf := clip;
    other.ClipText := '';
    other.SelStart := 1;
    other.PasteFromClipboard;
    AssertEquals('another control: it comes along', 1, other.BookmarkCount);
    AssertTrue('there', other.FindBookmark('m', s, e));
    AssertTrue('around its text', RawByteString(other.Document.Text.GetText(s + 1, e - s - 1)) = 'cd');
    CheckAgree('into another control', other);
    // its one end alone: left out there too
    other.Undo;
    other.ClipRtf := part;
    other.PasteFromClipboard;
    AssertEquals('one end alone: left out', 0, other.BookmarkCount(True));
    CheckAgree('one end into another control', other);
  finally
    other.Free;
  end;
end;

{ A table deleted whose cell holds one end of a bookmark, its other end outside: no lone mark
  is left - the end in the cell comes back at the deletion's place, as the others there keep
  theirs. Both ways round: the start in the cell, the end in it. Undone to the bytes. }
procedure TTyRichBookmarksTest.TestDeletingATableLeavesNoLoneMark;
var
  before: RawByteString;
  s, e: TTyRichPos;
  i: Integer;
begin
  for i := 0 to 1 do
  begin
    if i = 0 then
      Load(Rtf(Head + 'x|par|trowd|cellx2000|cellx4000 |pard|intbl {|*|bkmkstart m}A|cell B|cell|row' +
        '|pard af{|*|bkmkend m}ter|par}'))
    else
      Load(Rtf(Head + 'x{|*|bkmkstart m}y|par|trowd|cellx2000|cellx4000 |pard|intbl A{|*|bkmkend m}' +
        '|cell B|cell|row|pard after|par}'));
    before := SaveRtf;
    AssertTrue(Format('%d: a table', [i]), Doc.CellAt(1) <> nil);
    // its rows, whole (the model's deletion)
    AssertTrue(Format('%d: deleted', [i]), Doc.Execute(TTyRichDelete.Create(Doc.Text.ParaStart(1),
      Doc.Text.ParaStart(Doc.Text.ParaCount - 1) - Doc.Text.ParaStart(1))));
    AssertTrue(Format('%d: the table gone', [i]), Doc.CellAt(1) = nil);
    AssertTrue(Format('%d: the bookmark stays', [i]), FRich.FindBookmark('m', s, e));
    AssertEquals(Format('%d: one', [i]), 1, FRich.BookmarkCount);
    CheckAgree(Format('%d: the table deleted', [i]));
    FRich.Undo;
    AssertTrue(Format('%d: undone: the bytes', [i]), SaveRtf = before);
  end;
end;

{ A file read on demand with a bookmark a paragraph: a deletion decides the bookmarks from the
  load's index - everything selected and a key typed parses nothing; a half deleted parses its
  two edges at most; one of a bookmark's ends in the range, it stays (collapsed). }
procedure TTyRichBookmarksTest.TestALazyDeletionParsesOnlyItsEdges;
var
  src: RawByteString;
  ld: TTyRtfLoad;
  parses: Integer;
  s, e, a, z: TTyRichPos;
begin
  src := LazySource(6000);
  Load(src);
  ld := TyRichRtfLoadOf(Doc);
  AssertTrue('read on demand', ld <> nil);
  // (the selection's end shown: the last paragraph read for it)
  FRich.SelectAll;
  parses := ld.ParseCount;
  FRich.Key8('x');
  AssertEquals('everything replaced: nothing parsed', parses, ld.ParseCount);
  AssertEquals('no bookmark left', 0, FRich.BookmarkCount(True));
  FRich.Undo;
  AssertEquals('undone: every one', 6000, FRich.BookmarkCount(True));
  // a half, from the middle of one paragraph to the middle of another
  Load(src);
  ld := TyRichRtfLoadOf(Doc);
  a := Doc.Text.ParaStart(1000) + 3;
  z := Doc.Text.ParaStart(4000) + 3;
  parses := ld.ParseCount;
  // (the model's deletion: a selection shown would read its ends' paragraphs for the view)
  AssertTrue('deleted', Doc.Execute(TTyRichDelete.Create(a, z - a)));
  AssertTrue(Format('the two edges parsed at most (%d)', [ld.ParseCount - parses]),
    ld.ParseCount - parses <= 2);
  AssertEquals('the ones in it gone', 3000, FRich.BookmarkCount(True));
  AssertTrue('the one before', FRich.FindBookmark('bm1000', s, e));
  AssertTrue('the one after', FRich.FindBookmark('bm4001', s, e));
  AssertFalse('one in it', FRich.FindBookmark('bm2000', s, e));
  // a range that holds one end of a bookmark: it stays, collapsed to the range's place
  Load(src);
  ld := TyRichRtfLoadOf(Doc);
  AssertTrue('bm2000', FRich.FindBookmark('bm2000', s, e));
  a := s + 3;
  // (into bm3001's text: "paragraph number 3001 " its start, then "te")
  z := Doc.Text.ParaStart(3000) + 25;
  parses := ld.ParseCount;
  AssertTrue('deleted', Doc.Execute(TTyRichDelete.Create(a, z - a)));
  AssertTrue(Format('the edges parsed at most (%d)', [ld.ParseCount - parses]),
    ld.ParseCount - parses <= 2);
  AssertTrue('its end held: it stays', FRich.FindBookmark('bm2000', s, e));
  AssertTrue('its text up to the place', TextOf(s + 1, e - s - 1) = 'te');
  AssertTrue('its start held: the next stays', FRich.FindBookmark('bm3001', s, e));
  AssertTrue('its text from the place', TextOf(s + 1, e - s - 1) = 'xt of 3001');
  AssertEquals('the others in it gone', 6000 - 1000, FRich.BookmarkCount(True));
  CheckAgree('a lazy deletion');
end;

{ BookmarkCount and BookmarkName read a list that is kept: asked again, with CanEditBookmarks
  between (an idle handler), it is not built again and nothing is parsed; a character typed
  in a bookmark's paragraph keeps it; a paragraph more, a bookmark added, build it again. }
procedure TTyRichBookmarksTest.TestTheListIsKeptAcrossAKey;
var
  ld: TTyRtfLoad;
  b, parses, i: Integer;
  s, e: TTyRichPos;
begin
  Load(LazySource(6000));
  ld := TyRichRtfLoadOf(Doc);
  AssertTrue('read on demand', ld <> nil);
  parses := ld.ParseCount;
  AssertEquals('every one', 6000, FRich.BookmarkCount);
  b := TBkmProbe(FRich).ListBuilds;
  AssertEquals('counted with nothing parsed', parses, ld.ParseCount);
  for i := 1 to 10 do
  begin
    AssertTrue('Can...', FRich.CanEditBookmarks);
    AssertEquals('again', 6000, FRich.BookmarkCount);
    AssertEquals('again, the hidden ones too', 6000, FRich.BookmarkCount(True));
  end;
  AssertEquals('asked again: not built again', b, TBkmProbe(FRich).ListBuilds);
  AssertEquals('asked again: nothing parsed', parses, ld.ParseCount);
  AssertEquals('a name of the index', 'bm101', FRich.BookmarkName(100));
  // a character typed in a bookmark's paragraph
  AssertTrue('bm101', FRich.FindBookmark('bm101', s, e));
  FRich.SelStart := s + 3;
  FRich.Key8('x');
  AssertEquals('typed: the same', 6000, FRich.BookmarkCount);
  AssertEquals('typed: kept', b, TBkmProbe(FRich).ListBuilds);
  AssertEquals('its name', 'bm101', FRich.BookmarkName(100));
  // a paragraph more: built again
  FRich.Press(VK_RETURN, []);
  AssertEquals('a paragraph more: the same', 6000, FRich.BookmarkCount);
  AssertEquals('built again', b + 1, TBkmProbe(FRich).ListBuilds);
  // a bookmark added in a paragraph that had none
  FRich.SelStart := Doc.Text.ParaStart(101);
  AssertTrue('added', FRich.AddBookmark('added'));
  AssertEquals('one more', 6001, FRich.BookmarkCount);
  AssertEquals('in its place', 'added', FRich.BookmarkName(101));
  FRich.Undo;
  AssertEquals('undone', 6000, FRich.BookmarkCount);
  // the start of one deleted: gone from the list
  AssertTrue('bm7', FRich.FindBookmark('bm7', s, e));
  FRich.SelStart := s - 1;
  FRich.SelLength := 3;
  FRich.Press(VK_DELETE, []);
  AssertTrue('still found: collapsed', FRich.FindBookmark('bm7', s, e));
  AssertEquals('listed still', 6000, FRich.BookmarkCount);
  AssertTrue('deleted', FRich.DeleteBookmark('bm7'));
  AssertFalse('gone', FRich.FindBookmark('bm7', s, e));
  AssertEquals('one fewer', 5999, FRich.BookmarkCount);
  AssertEquals('the next in its place', 'bm8', FRich.BookmarkName(6));
end;

{ Names are one name whatever their case, as Word has them: a file that has dup and DUP lists
  one, the first; found by either. }
procedure TTyRichBookmarksTest.TestNamesAreListedWithoutRegardToCase;
var
  s, e: TTyRichPos;
begin
  Load(Rtf(Head + '{|*|bkmkstart dup}a{|*|bkmkend dup} {|*|bkmkstart DUP}b{|*|bkmkend DUP} ' +
    '{|*|bkmkstart other}c{|*|bkmkend other}|par}'));
  AssertEquals('two names', 2, FRich.BookmarkCount);
  AssertEquals('the first of dup and DUP', 'dup', FRich.BookmarkName(0));
  AssertEquals('then other', 'other', FRich.BookmarkName(1));
  AssertTrue('found as DUP', FRich.FindBookmark('DUP', s, e));
  AssertEquals('the first', 0, s);
end;

{ AddBookmark over a selection that holds the same name's old start: the old one goes and the
  new one is over the selection's text - the old start was in it, one character fewer. }
procedure TTyRichBookmarksTest.TestAddingANameOverItsOwnStart;
var
  s, e: TTyRichPos;
  before: RawByteString;
begin
  Load(BaseDoc);
  before := SaveRtf;
  FRich.SelStart := 1;
  FRich.SelLength := 3;     // b, the start, c
  AssertTrue('added', FRich.AddBookmark('m'));
  AssertEquals('one', 1, FRich.BookmarkCount);
  AssertTrue('found', FRich.FindBookmark('m', s, e));
  AssertEquals('its start before b', 1, s);
  AssertTrue('over the selection''s text', TextOf(s + 1, e - s - 1) = 'bc');
  CheckAgree('added over its own start');
  FRich.Undo;
  AssertTrue('undone: the bytes', SaveRtf = before);
end;

initialization
  RegisterTest(TTyRichBookmarksTest);
end.
