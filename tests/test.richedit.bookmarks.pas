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
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.Bookmarks, tyControls.RichEdit,
  test.richedit.fieldctl;

type
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

{ ---- the suite ---- }

procedure TTyRichBookmarksTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FRich := TFieldProbe.Create(nil);
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
  AssertEquals('the caret at its start, where it rests', s, FRich.SelStart);
  AssertEquals('no selection', 0, FRich.SelLength);
  r := FRich.PositionRect(FRich.SelStart);
  AssertTrue('in view', (r.Bottom > r.Top) and (r.Top >= 0) and (r.Bottom <= FRich.Height));
  AssertTrue('the text after it', TextOf(FRich.SelStart + 1, 6) = 'target');
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
  AssertTrue('the caret at mark1', (FRich.SelStart <= s) and
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
  // a Chinese name, round trip
  FRich.SelStart := 14;
  AssertTrue('a Chinese name', FRich.AddBookmark('第二节'));
  saved := SaveRtf;
  AssertTrue('written as Unicode', Pos(Rtf('{|*|bkmkstart |u31532?|u20108?|u-32126?}'), saved) > 0);
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

initialization
  RegisterTest(TTyRichBookmarksTest);
end.
