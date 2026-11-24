unit test.richedit.wordlists;

{ What Word reads in a file the writer made: the page colour's group puts no text into the
  document, and a list the model owns shows in Word the markers the control draws - numbers
  on several levels, an outer list going on after its inner items, starts other than 1, a
  list after a plain paragraph starting again, a list right after another, bullets on two
  levels, a bullet of the user's own text.

  Word is not run here: what it shows is worked out from the file by Word's own rules for a
  list table (WordMarkers below: a list's numbers count per list and level, a level starts
  again after an item of a shallower level, at the override's start where the override has
  one, else at the level's; the marker is the level's text with each level's number in its
  place). Those rules are the ones a file checked in Word 16 showed (one list table per
  run of items, an override with its start, \lsN \ilvlM on the paragraph).

  Headless, on the display suite's probe (the test device). The system's RichEdit is asked
  where it is there (Windows). }

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Controls, Graphics, LCLType,
  tyControls.Controller, tyControls.RichEdit.Text, tyControls.RichEdit.Model,
  tyControls.RichEdit.Commands, tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite,
  tyControls.RichEdit.Layout, tyControls.RichEdit.Builder, tyControls.RichEdit.Attrs,
  tyControls.RichEdit,
  test.richedit.control, test.richedit.display, test.richedit.msftedit;

type
  TUtf8Array = array of UTF8String;

  TTyRichWordListTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TDisplayProbe;
    FBack: TDisplayProbe;
    function NewProbe: TDisplayProbe;
    function Saved(AProbe: TDisplayProbe = nil): TBytes;
    function ReadBack(const B: TBytes): TTyRichDocument;
    function ParaText(ADoc: TTyRichDocument; AIndex: Integer): string;
    function PF(ADoc: TTyRichDocument; AIndex: Integer): TTyParaFormat;
    function Drawn(AProbe: TDisplayProbe; AIndex: Integer): UTF8String;
    procedure LoadFixture(const AName: string);
    procedure AppendParagraphs(const ATexts: array of string);
    procedure SelectParagraph(AIndex: Integer);
    procedure Build(AWhich: Integer);
    // every list item of FRich (and of the file B read back): Word's marker, the file's own
    // marker text for readers that do not number themselves, and what the control draws
    procedure CheckWordShowsWhatIsDrawn(const B: TBytes; const AWhat: string;
      AFrom: Integer = 0);
    procedure CheckReadsBackTheSame(const B: TBytes);
    procedure Dump(const B: TBytes; const AWhat: string; AFrom: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestThePageColourPutsNoTextIntoTheDocument;
    procedure TestNumbersOnThreeLevelsAndAnOuterListGoingOn;
    procedure TestStartsAPlainParagraphAndAListRightAfterAnother;
    procedure TestBulletsOnTwoLevelsAndABulletOfItsOwn;
    procedure TestEveryKindOfNumberThroughTheParagraphDoors;
    procedure TestTheWrittenFileReadsBackToTheSameLists;
    procedure TestTheReadBackFileSavedAgainIsTheSame;
    procedure TestAWordFileGetsTheListsInTablesOfItsOwn;
    procedure TestAWordFileWithListTablesGetsTheListsAddedToThem;
    procedure TestTheOlderPnFormReadsAsBefore;
    procedure TestTheSystemRichEditReadsTheLists;
    procedure TestAStartGivenThroughTheDoorBeginsANewList;
    procedure TestEnterOnAnItemGivenAStartGoesOn;
    procedure TestRichMemosForceNewNum;
    procedure TestAnOlderPnRunGoesOnAsBefore;
    procedure TestEveryCaseInOneFile;
  end;

  // Word's reading of the list items of an RTF file. ATexts: the text of every paragraph of
  // the document in order (each unique, ASCII, as it is in the file); for each, the marker
  // Word shows ('' for none) and the text of the paragraph's {\pntext} ('' for none).
  procedure WordMarkers(const B: TBytes; const ATexts: array of string;
    out AMarkers, APnTexts: TUtf8Array);

implementation

const
  BS = #92;
  Arrow = #$E2#$86#$92;      // U+2192
  Star = #$E2#$98#$85;       // U+2605
  RoundBullet = #$E2#$80#$A2;  // U+2022
  WhiteBullet = #$E2#$97#$A6;  // U+25E6

function AsRaw(const B: TBytes): RawByteString;
begin
  Result := '';
  SetLength(Result, Length(B));
  if Length(B) > 0 then Move(B[0], Result[1], Length(B));
end;

function AsBytes(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[0], Length(S));
end;

function Occurrences(const S, APart: RawByteString): Integer;
var
  i: Integer;
begin
  Result := 0;
  i := Pos(APart, S);
  while i > 0 do
  begin
    Inc(Result);
    i := Pos(APart, S, i + 1);
  end;
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

function FixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim + 'fixtures' +
    PathDelim + 'rtf' + PathDelim + AName;
end;

function Utf8Of(ACode: Cardinal): UTF8String;
var
  r: RawByteString;

  procedure Put(AByte: Cardinal);
  begin
    SetLength(r, Length(r) + 1);
    r[Length(r)] := AnsiChar(AByte);
  end;

begin
  r := '';
  if ACode < $80 then Put(ACode)
  else if ACode < $800 then
  begin
    Put($C0 or (ACode shr 6));
    Put($80 or (ACode and $3F));
  end
  else if ACode < $10000 then
  begin
    Put($E0 or (ACode shr 12));
    Put($80 or ((ACode shr 6) and $3F));
    Put($80 or (ACode and $3F));
  end
  else
  begin
    Put($F0 or (ACode shr 18));
    Put($80 or ((ACode shr 12) and $3F));
    Put($80 or ((ACode shr 6) and $3F));
    Put($80 or (ACode and $3F));
  end;
  SetCodePage(r, CP_UTF8, False);
  Result := r;
end;

{ ---- Word's rules, read off the file ---- }

type
  TIdxArray = array of Integer;

  TWLevel = record
    Nfc, Start, Font: Integer;
    Text: array of Cardinal;     // the level text: codes below 9 are level numbers' places
  end;
  TWList = record
    Id: Integer;
    Levels: array[0..8] of TWLevel;
    Cnt: array[0..8] of Integer;
    Have: array[0..8] of Boolean;
    LastLs: Integer;
  end;
  TWOver = record
    Ls, Id: Integer;
    Starts: array[0..8] of Integer;   // -1: not overridden
  end;

// the '}' that closes the group whose '{' is at AOpen
function GroupEnd(const S: RawByteString; AOpen: Integer): Integer;
var
  d: Integer;
begin
  d := 0;
  Result := AOpen;
  while Result <= Length(S) do
  begin
    case S[Result] of
      '\': Inc(Result);
      '{': Inc(d);
      '}':
        begin
          Dec(d);
          if d = 0 then Exit;
        end;
    end;
    Inc(Result);
  end;
end;

// the groups right inside the group at AOpen
function Children(const S: RawByteString; AOpen: Integer): TIdxArray;
var
  i, e, n: Integer;
begin
  Result := nil;
  n := 0;
  e := GroupEnd(S, AOpen);
  i := AOpen + 1;
  while i < e do
  begin
    if S[i] = '\' then Inc(i, 2)
    else if S[i] = '{' then
    begin
      SetLength(Result, n + 1);
      Result[n] := i;
      Inc(n);
      i := GroupEnd(S, i) + 1;
    end
    else
      Inc(i);
  end;
end;

// the group's first word ('\*' passed over)
function GroupWord(const S: RawByteString; AOpen: Integer): string;
var
  i: Integer;
begin
  Result := '';
  i := AOpen + 1;
  if Copy(S, i, 2) = '\*' then Inc(i, 2);
  while (i <= Length(S)) and (S[i] in [#10, #13, ' ']) do Inc(i);
  if (i > Length(S)) or (S[i] <> '\') then Exit;
  Inc(i);
  while (i <= Length(S)) and (S[i] in ['a'..'z', 'A'..'Z']) do
  begin
    Result := Result + S[i];
    Inc(i);
  end;
end;

// the group's own text from AOpen to its end with its child groups left out
function OwnText(const S: RawByteString; AOpen: Integer): RawByteString;
var
  i, e: Integer;
begin
  Result := '';
  e := GroupEnd(S, AOpen);
  i := AOpen + 1;
  while i < e do
  begin
    if S[i] = '\' then
    begin
      Result := Result + S[i] + S[i + 1];
      Inc(i, 2);
    end
    else if S[i] = '{' then
      i := GroupEnd(S, i) + 1
    else
    begin
      Result := Result + S[i];
      Inc(i);
    end;
  end;
end;

// \NAME followed by a number in S (the last one): its number
function LastWord(const S: RawByteString; const AName: string; out AValue: Integer): Boolean;
var
  i, j, k: Integer;
  pat: string;
begin
  Result := False;
  pat := BS + AName;
  i := Length(S) - Length(pat) + 1;
  while i >= 1 do
  begin
    if (Copy(S, i, Length(pat)) = pat) and ((i = 1) or (S[i - 1] <> '\')) then
    begin
      j := i + Length(pat);
      k := j;
      if (k <= Length(S)) and (S[k] = '-') then Inc(k);
      if (k <= Length(S)) and (S[k] in ['0'..'9']) then
      begin
        while (k <= Length(S)) and (S[k] in ['0'..'9']) do Inc(k);
        AValue := StrToInt(Copy(S, j, k - j));
        Exit(True);
      end;
    end;
    Dec(i);
  end;
end;

function HexVal(C: Char): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
  else
    Result := 0;
  end;
end;

// {\leveltext ...;}: its codes (UTF-16 joined), the length byte left out
function LevelText(const S: RawByteString; AOpen: Integer): TWLevel;
var
  i, e, uc, skip, n, v: Integer;
  name: string;
  codes: array of Cardinal;
  pend: Cardinal;

  procedure Add(ACode: Cardinal);
  begin
    if skip > 0 then
    begin
      Dec(skip);
      Exit;
    end;
    if (ACode >= $D800) and (ACode < $DC00) then
    begin
      pend := ACode;
      Exit;
    end;
    if (ACode >= $DC00) and (ACode < $E000) and (pend <> 0) then
      ACode := $10000 + ((pend - $D800) shl 10) + (ACode - $DC00);
    pend := 0;
    SetLength(codes, Length(codes) + 1);
    codes[High(codes)] := ACode;
  end;

begin
  Result := Default(TWLevel);
  codes := nil;
  uc := 1;
  skip := 0;
  pend := 0;
  e := GroupEnd(S, AOpen);
  i := AOpen + 1;
  while i < e do
  begin
    if S[i] = '\' then
    begin
      if S[i + 1] = '''' then
      begin
        Add(HexVal(S[i + 2]) * 16 + HexVal(S[i + 3]));
        Inc(i, 4);
        Continue;
      end;
      if not (S[i + 1] in ['a'..'z', 'A'..'Z']) then
      begin
        Add(Ord(S[i + 1]));
        Inc(i, 2);
        Continue;
      end;
      Inc(i);
      name := '';
      while S[i] in ['a'..'z', 'A'..'Z'] do
      begin
        name := name + S[i];
        Inc(i);
      end;
      n := i;
      if S[i] = '-' then Inc(i);
      while S[i] in ['0'..'9'] do Inc(i);
      v := StrToIntDef(Copy(S, n, i - n), 0);
      if S[i] = ' ' then Inc(i);
      if name = 'u' then
      begin
        if v < 0 then Inc(v, 65536);
        Add(v);
        skip := uc;
      end
      else if name = 'uc' then
        uc := v;
      Continue;
    end;
    if S[i] = ';' then Break;
    if not (S[i] in [#10, #13]) then Add(Ord(S[i]));
    Inc(i);
  end;
  // the first code is the text's length
  if Length(codes) > 0 then
    Result.Text := Copy(codes, 1, Length(codes) - 1);
end;

function FontIsSymbol(const S: RawByteString; AFont: Integer): Boolean;
var
  t, k, v: Integer;
  ch: TIdxArray;
  own: RawByteString;
begin
  Result := False;
  t := Pos('{' + BS + 'fonttbl', S);
  if t = 0 then Exit;
  ch := Children(S, t);
  for k := 0 to High(ch) do
  begin
    own := Copy(S, ch[k], GroupEnd(S, ch[k]) - ch[k] + 1);
    if LastWord(own, 'f', v) and (v = AFont) then
      Exit((Pos(BS + 'fcharset2', own) > 0) or (Pos('Symbol', own) > 0));
  end;
end;

procedure ReadTables(const S: RawByteString; out ALists: array of TWList; out ANLists: Integer;
  out AOvers: array of TWOver; out ANOvers: Integer);
var
  t, k, j, l, m, v: Integer;
  lists, levels, parts, lfos: TIdxArray;
  own: RawByteString;
begin
  ANLists := 0;
  ANOvers := 0;
  t := Pos('{' + BS + '*' + BS + 'listtable', S);
  if t > 0 then
  begin
    lists := Children(S, t);
    for k := 0 to High(lists) do
    begin
      if GroupWord(S, lists[k]) <> 'list' then Continue;
      ALists[ANLists] := Default(TWList);
      LastWord(OwnText(S, lists[k]), 'listid', ALists[ANLists].Id);
      levels := Children(S, lists[k]);
      l := 0;
      for j := 0 to High(levels) do
      begin
        if GroupWord(S, levels[j]) <> 'listlevel' then Continue;
        if l > 8 then Break;
        own := OwnText(S, levels[j]);
        parts := Children(S, levels[j]);
        for m := 0 to High(parts) do
          if GroupWord(S, parts[m]) = 'leveltext' then
            ALists[ANLists].Levels[l] := LevelText(S, parts[m]);
        if not LastWord(own, 'levelnfc', ALists[ANLists].Levels[l].Nfc) then
          ALists[ANLists].Levels[l].Nfc := 0;
        if not LastWord(own, 'levelstartat', ALists[ANLists].Levels[l].Start) then
          ALists[ANLists].Levels[l].Start := 1;
        if not LastWord(own, 'f', ALists[ANLists].Levels[l].Font) then
          ALists[ANLists].Levels[l].Font := -1;
        Inc(l);
      end;
      ALists[ANLists].LastLs := -1;
      Inc(ANLists);
    end;
  end;
  t := Pos('{' + BS + '*' + BS + 'listoverridetable', S);
  if t > 0 then
  begin
    lists := Children(S, t);
    for k := 0 to High(lists) do
    begin
      if GroupWord(S, lists[k]) <> 'listoverride' then Continue;
      own := OwnText(S, lists[k]);
      AOvers[ANOvers] := Default(TWOver);
      LastWord(own, 'listid', AOvers[ANOvers].Id);
      LastWord(own, 'ls', AOvers[ANOvers].Ls);
      for l := 0 to 8 do AOvers[ANOvers].Starts[l] := -1;
      lfos := Children(S, lists[k]);
      l := 0;
      for j := 0 to High(lfos) do
      begin
        if GroupWord(S, lfos[j]) <> 'lfolevel' then Continue;
        own := OwnText(S, lfos[j]);
        if (l <= 8) and (Pos(BS + 'listoverridestartat', own) > 0) and
           LastWord(own, 'levelstartat', v) then
          AOvers[ANOvers].Starts[l] := v;
        Inc(l);
      end;
      Inc(ANOvers);
    end;
  end;
end;

function FormatNumber(ANfc, AValue: Integer): string;
const
  RV: array[0..12] of Integer = (1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1);
  RT: array[0..12] of string = ('m', 'cm', 'd', 'cd', 'c', 'xc', 'l', 'xl', 'x', 'ix', 'v',
    'iv', 'i');
var
  i, n: Integer;
begin
  Result := '';
  case ANfc of
    1, 2:
      begin
        n := AValue;
        for i := 0 to High(RV) do
          while n >= RV[i] do
          begin
            Result := Result + RT[i];
            Dec(n, RV[i]);
          end;
        if ANfc = 1 then Result := UpperCase(Result);
      end;
    3, 4:
      begin
        // Word's letters: a .. z, then aa, bb ... (not reached by these tests)
        Result := StringOfChar(Chr(Ord('a') + (AValue - 1) mod 26), (AValue - 1) div 26 + 1);
        if ANfc = 3 then Result := UpperCase(Result);
      end;
  else
    Result := IntToStr(AValue);
  end;
end;

procedure WordMarkers(const B: TBytes; const ATexts: array of string;
  out AMarkers, APnTexts: TUtf8Array);
var
  S, seg: RawByteString;
  lists: array[0..255] of TWList;
  overs: array[0..1023] of TWOver;
  nl, no, k, p, from, pard, i, ls, ilvl, oi, li, d, n, c, e: Integer;
  lv: TWLevel;
  m, pn: UTF8String;
begin
  S := AsRaw(B);
  ReadTables(S, lists, nl, overs, no);
  SetLength(AMarkers, Length(ATexts));
  SetLength(APnTexts, Length(ATexts));
  from := 1;
  for k := 0 to High(ATexts) do
  begin
    AMarkers[k] := '';
    APnTexts[k] := '';
    p := Pos(ATexts[k], Copy(S, from, MaxInt));
    if p = 0 then raise Exception.CreateFmt('the paragraph "%s" is not in the file', [ATexts[k]]);
    p := p + from - 1;
    from := p + Length(ATexts[k]);
    // the paragraph's words: from the last \pard before its text
    pard := p;
    while (pard > 1) and not ((Copy(S, pard, 5) = BS + 'pard') and
      not (S[pard + 5] in ['a'..'z', 'A'..'Z'])) do Dec(pard);
    seg := Copy(S, pard, p - pard);
    // its {\pntext ...}: the text before \tab, its words left out
    i := Length(seg);
    while (i > 0) and (Copy(seg, i, 8) <> '{' + BS + 'pntext') do Dec(i);
    if i > 0 then
    begin
      e := GroupEnd(seg, i);
      pn := '';
      c := i + 8;
      if seg[c] = ' ' then Inc(c);
      while c < e do
      begin
        if seg[c] = '\' then
        begin
          if seg[c + 1] = '''' then
          begin
            pn := pn + Utf8Of($F000 + Cardinal(HexVal(seg[c + 2]) * 16 + HexVal(seg[c + 3])));
            Inc(c, 4);
            Continue;
          end;
          if Copy(seg, c, 4) = BS + 'tab' then Break;
          Inc(c);
          while (c < e) and (seg[c] in ['a'..'z', 'A'..'Z', '0'..'9', '-']) do Inc(c);
          if (c < e) and (seg[c] = ' ') then Inc(c);
          Continue;
        end;
        pn := pn + seg[c];
        Inc(c);
      end;
      APnTexts[k] := pn;
    end;
    if not LastWord(seg, 'ls', ls) then Continue;
    if not LastWord(seg, 'ilvl', ilvl) then ilvl := 0;
    oi := -1;
    for i := 0 to no - 1 do
      if overs[i].Ls = ls then oi := i;
    if oi < 0 then raise Exception.CreateFmt('\ls%d has no override', [ls]);
    li := -1;
    for i := 0 to nl - 1 do
      if lists[i].Id = overs[oi].Id then li := i;
    if li < 0 then raise Exception.CreateFmt('\ls%d: list %d is not in the table', [ls, overs[oi].Id]);
    // Word: an override with a start begins its list again where it is first used
    if lists[li].LastLs <> ls then
    begin
      for d := 0 to 8 do
        if overs[oi].Starts[d] >= 0 then lists[li].Have[d] := False;
      lists[li].LastLs := ls;
    end;
    for d := ilvl + 1 to 8 do lists[li].Have[d] := False;
    if lists[li].Have[ilvl] then n := lists[li].Cnt[ilvl] + 1
    else if overs[oi].Starts[ilvl] >= 0 then n := overs[oi].Starts[ilvl]
    else n := lists[li].Levels[ilvl].Start;
    lists[li].Cnt[ilvl] := n;
    lists[li].Have[ilvl] := True;
    lv := lists[li].Levels[ilvl];
    m := '';
    for i := 0 to High(lv.Text) do
      if lv.Text[i] < 9 then
        m := m + FormatNumber(lists[li].Levels[lv.Text[i]].Nfc, lists[li].Cnt[lv.Text[i]])
      else if (lv.Font >= 0) and FontIsSymbol(S, lv.Font) and
        ((lv.Text[i] = $F0B7) or (lv.Text[i] = $B7)) then
        m := m + RoundBullet
      else
        m := m + Utf8Of(lv.Text[i]);
    AMarkers[k] := m;
  end;
end;

{ ---- fixtures ---- }

// Inside S's header group {\*\ATable ...}: every \AWord<N> at its entries' own level (its
// groups' first level) once.
procedure CheckUniqueWords(const S: RawByteString; const ATable, AWord: string);
var
  t, k, v: Integer;
  ch: TIdxArray;
  seen: array of Integer;
begin
  t := Pos('{' + BS + '*' + BS + ATable, S);
  if t = 0 then raise Exception.Create('no ' + ATable);
  ch := Children(S, t);
  seen := nil;
  for k := 0 to High(ch) do
    if LastWord(OwnText(S, ch[k]), AWord, v) then
    begin
      for t := 0 to High(seen) do
        if seen[t] = v then
          raise Exception.CreateFmt('%s: \%s%d twice', [ATable, AWord, v]);
      SetLength(seen, Length(seen) + 1);
      seen[High(seen)] := v;
    end;
end;

procedure TTyRichWordListTest.Dump(const B: TBytes; const AWhat: string; AFrom: Integer);
var
  dir, s: string;
  f: TFileStream;
  i: Integer;
  sl: TStringList;
begin
  dir := GetEnvironmentVariable('TY_LIST_DUMP');
  if dir = '' then Exit;
  f := TFileStream.Create(IncludeTrailingPathDelimiter(dir) + AWhat + '.rtf', fmCreate);
  try
    if Length(B) > 0 then f.WriteBuffer(B[0], Length(B));
  finally
    f.Free;
  end;
  sl := TStringList.Create;
  try
    for i := AFrom to FRich.Document.Text.ParaCount - 1 do
    begin
      s := Drawn(FRich, i);
      if s <> '' then sl.Add(ParaText(FRich.Document, i) + #9 + s);
    end;
    sl.WriteBOM := False;
    sl.SaveToFile(IncludeTrailingPathDelimiter(dir) + AWhat + '.markers.txt', TEncoding.UTF8);
  finally
    sl.Free;
  end;
end;

procedure TTyRichWordListTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FRich := NewProbe;
  FBack := nil;
end;

procedure TTyRichWordListTest.TearDown;
begin
  FreeAndNil(FBack);
  FreeAndNil(FRich);
  FreeAndNil(FCtl);
end;

function TTyRichWordListTest.NewProbe: TDisplayProbe;
begin
  Result := TDisplayProbe.Create(nil);
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 300);
end;

function TTyRichWordListTest.Saved(AProbe: TDisplayProbe): TBytes;
var
  st: TMemoryStream;
begin
  if AProbe = nil then AProbe := FRich;
  st := TMemoryStream.Create;
  try
    AProbe.SaveToStream(st, rfRtf);
    Result := nil;
    SetLength(Result, st.Size);
    if st.Size > 0 then Move(st.Memory^, Result[0], st.Size);
  finally
    st.Free;
  end;
end;

function TTyRichWordListTest.ReadBack(const B: TBytes): TTyRichDocument;
var
  st: TBytesStream;
begin
  FreeAndNil(FBack);
  FBack := NewProbe;
  st := TBytesStream.Create(B);
  try
    FBack.LoadFromStream(st);
  finally
    st.Free;
  end;
  FBack.FinishLoading;
  Result := FBack.Document;
end;

function TTyRichWordListTest.ParaText(ADoc: TTyRichDocument; AIndex: Integer): string;
begin
  Result := ADoc.Text.GetText(ADoc.Text.ParaStart(AIndex), ADoc.Text.ParaLength(AIndex));
end;

function TTyRichWordListTest.PF(ADoc: TTyRichDocument; AIndex: Integer): TTyParaFormat;
begin
  Result := ADoc.Formats.ParaFormat(ADoc.ParaFormatOf(AIndex));
end;

function TTyRichWordListTest.Drawn(AProbe: TDisplayProbe; AIndex: Integer): UTF8String;
var
  L: TTyBlockLayout;
begin
  L := AProbe.Layouter.LayoutBlock(AProbe.Document, AIndex, 1000, 96, 1);
  try
    Result := '';
    if TTyParaLayout(L).HasMarker then Result := TTyParaLayout(L).Marker.Text;
  finally
    L.Release;
  end;
end;

procedure TTyRichWordListTest.LoadFixture(const AName: string);
begin
  FRich.LoadFromFile(FixturePath(AName));
  FRich.FinishLoading;
end;

// ATexts as paragraphs of their own after the document's last one
procedure TTyRichWordListTest.AppendParagraphs(const ATexts: array of string);
var
  i: Integer;
  s: string;
begin
  s := '';
  for i := 0 to High(ATexts) do s := s + #13#10 + ATexts[i];
  FRich.SelStart := FRich.Document.Text.Length;
  FRich.SelLength := 0;
  FRich.SelText := s;
end;

procedure TTyRichWordListTest.SelectParagraph(AIndex: Integer);
begin
  FRich.SelStart := FRich.Document.Text.ParaStart(AIndex);
  FRich.SelLength := 0;
end;

{ The documents of the tests, made by the builder. }
procedure TTyRichWordListTest.Build(AWhich: Integer);
var
  B: TTyRichBuilder;
begin
  B := FRich.NewBuilder;
  try
    case AWhich of
      0:
        begin
          // levels: three deep, the outer list going on after its inner items
          B.Numbered(0, 3).Text('numbered from three');
          B.Paragraph.Numbered(0).Text('numbered next');
          B.Paragraph.Numbered(1).Text('numbered inner');
          B.Paragraph.Numbered(1).Text('numbered inner two');
          B.Paragraph.Numbered(2).Text('numbered third level');
          B.Paragraph.Numbered(2).Text('numbered third level two');
          B.Paragraph.Numbered(1).Text('numbered inner three');
          B.Paragraph.Numbered(0).Text('numbered outer again');
          B.Paragraph.Numbered(1).Text('numbered inner after the outer');
          B.Paragraph.Text('the end');
        end;
      1:
        begin
          { starts: an item with none goes on, a plain paragraph ends the list, an item
            given a start begins a new list right after another; inner items after a new
            outer item and after one that goes on }
          B.Numbered(0, 3).Text('from three');
          B.Paragraph.Numbered(0).Text('then one more');
          B.Paragraph.Text('a plain paragraph between');
          B.Paragraph.Numbered(0).Text('second list one');
          B.Paragraph.Numbered(0).Text('second list two');
          B.Paragraph.Numbered(0, 10).Text('right after from ten');
          B.Paragraph.Numbered(0).Text('right after again');
          B.Paragraph.Text('another plain paragraph');
          B.Paragraph.Numbered(0, 5).Text('a list from five');
          B.Paragraph.Numbered(0).Text('five goes on');
          B.Paragraph.Numbered(0).Text('five goes on again');
          B.Paragraph.Numbered(0, 1).Text('a new list from one right after');
          B.Paragraph.Numbered(0).Text('the new list goes on');
          B.Paragraph.Numbered(1, 4).Text('its inner from four');
          B.Paragraph.Numbered(1).Text('its inner goes on');
          B.Paragraph.Numbered(0, 1).Text('a new outer list');
          B.Paragraph.Numbered(1).Text('inner after the new outer');
          B.Paragraph.Numbered(1).Text('inner after the new outer two');
          B.Paragraph.Numbered(0).Text('an outer that goes on');
          B.Paragraph.Numbered(1).Text('inner after the outer that goes on');
          B.Paragraph.Text('the end');
        end;
      2:
        begin
          B.Bullet(0).Text('bullet level one');
          B.Paragraph.Bullet(1).Text('bullet level two');
          B.Paragraph.Bullet(1).Text('bullet level two again');
          B.Paragraph.Bullet(0).Text('bullet level one again');
          B.Paragraph.Bullet(0, Arrow).Text('a bullet of its own');
          B.Paragraph.Bullet(0, Arrow).Text('another of its own');
          B.Paragraph.Bullet(1, Star).Text('a deeper one of its own');
          B.Paragraph.Bullet(0).Text('a round one after them');
          B.Paragraph.Numbered(1).Text('a number under a bullet');
          B.Paragraph.Text('the end');
        end;
    end;
    FRich.SetContent(B);
  finally
    B.Free;
  end;
end;

procedure TTyRichWordListTest.CheckWordShowsWhatIsDrawn(const B: TBytes; const AWhat: string;
  AFrom: Integer);
var
  texts: TStringArray;
  markers, pns: TUtf8Array;
  i, n, items: Integer;
  d: TTyRichDocument;
  k: TTyListKind;
begin
  // (from AFrom on: the paragraphs a file is given; Word's own items are its business)
  // (TY_LIST_DUMP names a folder: each file looked at is put there, with the markers drawn)
  Dump(B, AWhat, AFrom);
  d := FRich.Document;
  n := d.Text.ParaCount - AFrom;
  texts := nil;
  SetLength(texts, n);
  for i := 0 to n - 1 do texts[i] := ParaText(d, AFrom + i);
  WordMarkers(B, texts, markers, pns);
  items := 0;
  for i := 0 to n - 1 do
  begin
    k := PF(d, AFrom + i).List.Kind;
    AssertEquals(Format('%s: "%s" - Word shows what the control draws', [AWhat, texts[i]]),
      Drawn(FRich, AFrom + i), markers[i]);
    if k <> lkNone then Inc(items);
    // the file's own text of the marker (for readers that number nothing): the number drawn
    if not (k in [lkNone, lkBullet]) then
      AssertEquals(Format('%s: "%s" - its marker text', [AWhat, texts[i]]),
        Drawn(FRich, AFrom + i), pns[i]);
  end;
  AssertTrue(AWhat + ': list items were looked at', items > 0);
end;

procedure TTyRichWordListTest.CheckReadsBackTheSame(const B: TBytes);
var
  d, back: TTyRichDocument;
  i, k, param: Integer;
  a, c: TTyParaFormat;
begin
  d := FRich.Document;
  back := ReadBack(B);
  AssertEquals('the paragraphs', d.Text.ParaCount, back.Text.ParaCount);
  for i := 0 to d.Text.ParaCount - 1 do
  begin
    a := PF(d, i);
    c := PF(back, i);
    AssertEquals(Format('%d: the kind', [i]), Ord(a.List.Kind), Ord(c.List.Kind));
    AssertEquals(Format('%d: the level', [i]), a.List.Level, c.List.Level);
    AssertEquals(Format('%d: the start', [i]), a.List.StartAt, c.List.StartAt);
    AssertEquals(Format('%d: the bullet text', [i]), a.List.Bullet, c.List.Bullet);
    AssertEquals(Format('%d: the indent', [i]), a.LeftIndent, c.LeftIndent);
    if a.List.Kind <> lkNone then
      for k := 0 to c.Extra.Count - 1 do
        AssertTrue(Format('%d: the list says it all (only its \ls and \ilvl kept)', [i]),
          TyRtfParaExtraKind(c.Extra.Item(k), param) in [pekLs, pekIlvl]);
    AssertEquals(Format('%d: drawn the same', [i]), Drawn(FRich, i), Drawn(FBack, i));
  end;
end;

{ ---- the tests ---- }

// Word reads a space between two of the background shape's groups as text: the document
// then starts with a space. Inside the group, between a closing brace and the next opening
// one, only line breaks.
procedure TTyRichWordListTest.TestThePageColourPutsNoTextIntoTheDocument;
  procedure Check(const AWhat: string);
  var
    S: RawByteString;
    a, e, i, j: Integer;
  begin
    S := AsRaw(Saved);
    a := Pos('{' + BS + '*' + BS + 'background', S);
    AssertTrue(AWhat + ': the group is there', a > 0);
    e := GroupEnd(S, a);
    for i := a to e do
      if S[i] = '}' then
      begin
        j := i + 1;
        while (j < e) and not (S[j] in ['{', '}']) do
        begin
          AssertTrue(Format('%s: only a line break after the "}" at %d, not #%d',
            [AWhat, i - a, Ord(S[j])]), S[j] in [#13, #10]);
          Inc(j);
        end;
      end;
    // Word's own bytes: a line break after \shplid1025 and before fLayoutInCell
    AssertTrue(AWhat + ': a line break after the shape''s id',
      Pos(BS + 'shplid1025'#13#10'{' + BS + 'sp{', S) > 0);
    AssertTrue(AWhat + ': a line break before fLayoutInCell',
      Pos('{' + BS + 'sv 1}}'#13#10'{' + BS + 'sp{' + BS + 'sn fLayoutInCell}', S) > 0);
    AssertEquals(AWhat + ': read back, the first paragraph has no space', 'Heading one',
      ParaText(ReadBack(AsBytes(S)), 0));
  end;

begin
  FRich.Text := 'Heading one';
  FRich.DocumentColor := TColor($00C0FFC0);
  Check('a document of its own');
  // a file's header written again for the new colour
  LoadFixture('word-toc.rtf');
  FRich.SelStart := 0;
  FRich.SelText := 'Heading one'#13#10;
  FRich.DocumentColor := TColor($00C0FFC0);
  Check('a file''s header');
end;

procedure TTyRichWordListTest.TestNumbersOnThreeLevelsAndAnOuterListGoingOn;
var
  B: TBytes;
begin
  Build(0);
  // what the control draws (its own rule: a deeper item is passed over)
  AssertEquals('the first, from three', '3.', Drawn(FRich, 0));
  AssertEquals('the outer goes on after its inner items', '5.', Drawn(FRich, 7));
  AssertEquals('the inner level starts again after the outer item', '1.', Drawn(FRich, 8));
  AssertEquals('the third level goes on', '2.', Drawn(FRich, 5));
  AssertEquals('the second level goes on past the third', '3.', Drawn(FRich, 6));
  B := Saved;
  CheckWordShowsWhatIsDrawn(B, 'levels');
  // the items one after the other, every level counted as Word counts it: one list
  AssertEquals('one list of the table', 1, Occurrences(AsRaw(B), '{' + BS + 'listoverride' + BS));
end;

procedure TTyRichWordListTest.TestStartsAPlainParagraphAndAListRightAfterAnother;
var
  B: TBytes;
begin
  Build(1);
  AssertEquals('an item with no start goes on', '4.', Drawn(FRich, 1));
  AssertEquals('after a plain paragraph: 1', '1.', Drawn(FRich, 3));
  AssertEquals('a start given right after another list: a new list', '10.', Drawn(FRich, 5));
  AssertEquals('it goes on', '11.', Drawn(FRich, 6));
  AssertEquals('from five', '5.', Drawn(FRich, 8));
  AssertEquals('5, 6, 7', '7.', Drawn(FRich, 10));
  AssertEquals('a new list from one right after', '1.', Drawn(FRich, 11));
  AssertEquals('which goes on', '2.', Drawn(FRich, 12));
  AssertEquals('its inner from four', '4.', Drawn(FRich, 13));
  AssertEquals('the inner goes on', '5.', Drawn(FRich, 14));
  AssertEquals('a new outer list', '1.', Drawn(FRich, 15));
  AssertEquals('an inner item after a new outer one: 1', '1.', Drawn(FRich, 16));
  AssertEquals('the outer goes on', '2.', Drawn(FRich, 18));
  AssertEquals('an inner item after an outer one that goes on: 1 too', '1.', Drawn(FRich, 19));
  B := Saved;
  CheckWordShowsWhatIsDrawn(B, 'starts');
end;

procedure TTyRichWordListTest.TestBulletsOnTwoLevelsAndABulletOfItsOwn;
var
  B: TBytes;
  S: RawByteString;
  i: Integer;
begin
  Build(2);
  AssertEquals('level one', RoundBullet, Drawn(FRich, 0));
  AssertEquals('level two', WhiteBullet, Drawn(FRich, 1));
  AssertEquals('its own', Arrow, Drawn(FRich, 4));
  B := Saved;
  CheckWordShowsWhatIsDrawn(B, 'bullets');
  // Word's level of a bullet of the second level is its second (\ilvl1)
  S := AsRaw(B);
  i := Pos('bullet level two', S);
  AssertTrue('the level-two bullet names its level', Pos(BS + 'ilvl1',
    Copy(S, i - 200, 200)) > 0);
end;

{ Lists made through the paragraph doors: every kind of number, a deeper level than three. }
procedure TTyRichWordListTest.TestEveryKindOfNumberThroughTheParagraphDoors;
const
  Kinds: array[0..4] of TTyListKind = (lkDecimal, lkLowerAlpha, lkUpperAlpha, lkLowerRoman,
    lkUpperRoman);
var
  i: Integer;
  B: TBytes;
begin
  FRich.Text := 'top one';
  AppendParagraphs(['top two', 'letters one', 'letters two', 'capitals', 'small roman',
    'capital roman', 'capital roman two', 'deep five', 'top three', 'after']);
  for i := 0 to 9 do
  begin
    SelectParagraph(i);
    case i of
      0, 1, 9: FRich.Paragraph.Numbering := lkDecimal;
      2, 3:
        begin
          FRich.Paragraph.Numbering := lkLowerAlpha;
          FRich.Paragraph.ListLevel := 1;
        end;
      4:
        begin
          FRich.Paragraph.Numbering := lkUpperAlpha;
          FRich.Paragraph.ListLevel := 2;
        end;
      5:
        begin
          FRich.Paragraph.Numbering := lkLowerRoman;
          FRich.Paragraph.ListLevel := 3;
          FRich.Paragraph.NumberingStart := 4;
        end;
      6, 7:
        begin
          FRich.Paragraph.Numbering := lkUpperRoman;
          FRich.Paragraph.ListLevel := 3;
        end;
      8:
        begin
          FRich.Paragraph.Numbering := Kinds[0];
          FRich.Paragraph.ListLevel := 5;
        end;
    end;
  end;
  AssertEquals('letters on the second level', 'b.', Drawn(FRich, 3));
  AssertEquals('the outer goes on', '3.', Drawn(FRich, 9));
  B := Saved;
  CheckWordShowsWhatIsDrawn(B, 'kinds');
  CheckReadsBackTheSame(B);
end;

procedure TTyRichWordListTest.TestTheWrittenFileReadsBackToTheSameLists;
var
  w: Integer;
begin
  for w := 0 to 2 do
  begin
    Build(w);
    CheckReadsBackTheSame(Saved);
  end;
end;

{ The file read back and saved untouched: its bytes; one of its list items edited: the lists
  still show what the control draws. }
procedure TTyRichWordListTest.TestTheReadBackFileSavedAgainIsTheSame;
var
  B, again: TBytes;
  keep: TDisplayProbe;
begin
  Build(0);
  B := Saved;
  ReadBack(B);
  again := Saved(FBack);
  AssertTrue('untouched: the same bytes', SameBytes(B, again));
  // an edit of the read-back file: a word typed into an item, a new item after the outer one
  keep := FRich;
  FRich := FBack;
  FBack := nil;
  try
    FRich.SelStart := FRich.Document.Text.ParaStart(7) + 8;
    FRich.SelText := 'X';
    FRich.SelStart := FRich.Document.Text.ParaStart(8);
    FRich.SelText := 'numbered added'#13#10;
    CheckWordShowsWhatIsDrawn(Saved, 'edited after a read');
  finally
    FreeAndNil(FBack);
    FBack := FRich;
    FRich := keep;
  end;
end;

{ word-toc.rtf has no list table: a two-level list added through the paragraph doors gets
  tables of its own in the header; the file's paragraphs stay its bytes. }
procedure TTyRichWordListTest.TestAWordFileGetsTheListsInTablesOfItsOwn;
var
  B, again: TBytes;
  n, i: Integer;
  S, orig: RawByteString;
  info: TTyRtfWriteInfo;
  st: TMemoryStream;
begin
  LoadFixture('word-toc.rtf');
  orig := AsRaw(Saved);
  n := FRich.Document.Text.ParaCount;
  AppendParagraphs(['Alpha item one', 'Alpha item two', 'Alpha inner one', 'Alpha inner two',
    'Alpha item three', 'Alpha plain after', 'Alpha again one', 'Alpha five one',
    'Alpha five two', 'Alpha five inner', 'Alpha new list one', 'Alpha new list two']);
  for i := n to n + 11 do
  begin
    SelectParagraph(i);
    if i = n + 5 then Continue;
    FRich.Paragraph.Numbering := lkDecimal;
    if (i = n + 2) or (i = n + 3) or (i = n + 9) then FRich.Paragraph.ListLevel := 1;
    // a list from five right after the one before it, then a new one from one right after
    if i = n + 7 then FRich.Paragraph.NumberingStart := 5;
    if i = n + 10 then FRich.Paragraph.NumberingStart := 1;
  end;
  B := Saved;
  S := AsRaw(B);
  AssertTrue('a list table', Pos('{' + BS + '*' + BS + 'listtable', S) > 0);
  AssertTrue('an override table', Pos('{' + BS + '*' + BS + 'listoverridetable', S) > 0);
  AssertTrue('the tables in the header (before the first paragraph)',
    Pos('{' + BS + '*' + BS + 'listoverridetable', S) < Pos(BS + 'pard', S));
  CheckWordShowsWhatIsDrawn(B, 'word-toc', n);
  AssertEquals('the outer goes on', '3.', Drawn(FRich, n + 4));
  AssertEquals('after the plain paragraph', '1.', Drawn(FRich, n + 6));
  AssertEquals('a list from five', '5.', Drawn(FRich, n + 7));
  AssertEquals('its inner item', '1.', Drawn(FRich, n + 9));
  AssertEquals('a new list from one right after', '1.', Drawn(FRich, n + 10));
  AssertEquals('which goes on', '2.', Drawn(FRich, n + 11));
  // the file's paragraphs are its bytes: one stretch from the model, at the end
  st := TMemoryStream.Create;
  try
    TyRichSaveRtf(FRich.Document, st, info);
  finally
    st.Free;
  end;
  AssertEquals('one stretch from the model', 1, Length(info.Stretches));
  AssertTrue('the file''s paragraphs as their bytes', info.VerbatimParas >= n - 1);
  AssertEquals('read back: the lists', Ord(lkDecimal), Ord(PF(ReadBack(B), n + 2).List.Kind));
  AssertEquals('read back: the level', 1, PF(FBack.Document, n + 2).List.Level);
  again := Saved(FBack);
  AssertTrue('read back and saved untouched: the same bytes', SameBytes(B, again));
  AssertTrue('the file before: no list table', Pos('listtable', orig) = 0);
end;

{ word-list.rtf has Word's tables: the lists made here are added to them (their ids and
  numbers above the file's), and Word's own items keep their numbers. }
procedure TTyRichWordListTest.TestAWordFileWithListTablesGetsTheListsAddedToThem;
var
  B: TBytes;
  S: RawByteString;
  n, i: Integer;
begin
  LoadFixture('word-list.rtf');
  n := FRich.Document.Text.ParaCount;
  AppendParagraphs(['Beta item one', 'Beta inner one', 'Beta item two']);
  for i := n to n + 2 do
  begin
    SelectParagraph(i);
    FRich.Paragraph.Numbering := lkDecimal;
    if i = n + 1 then FRich.Paragraph.ListLevel := 1;
  end;
  B := Saved;
  S := AsRaw(B);
  AssertEquals('one list table', 1, Occurrences(S, '{' + BS + '*' + BS + 'listtable'));
  AssertEquals('one override table', 1,
    Occurrences(S, '{' + BS + '*' + BS + 'listoverridetable'));
  // only the paragraphs added are looked at (Word's own are the file's)
  CheckWordShowsWhatIsDrawn(B, 'word-list', n);
  // the lists added have numbers of their own: no \ls, no \listid of the file's again
  CheckUniqueWords(S, 'listoverridetable', 'ls');
  CheckUniqueWords(S, 'listtable', 'listid');
  // Word's own items: still what the file says
  AssertEquals('Word''s item keeps its list', Ord(PF(FRich.Document, 1).List.Kind),
    Ord(PF(ReadBack(B), 1).List.Kind));
end;

// A file in the form earlier builds wrote ({\*\pn ...} alone, levels as \pnlvlN): read as
// before.
procedure TTyRichWordListTest.TestTheOlderPnFormReadsAsBefore;
var
  d: TTyRichDocument;
  S: RawByteString;
begin
  S := '{' + BS + 'rtf1' + BS + 'ansi' + BS + 'deff0{' + BS + 'fonttbl{' + BS + 'f0' + BS +
    'fnil Arial;}{' + BS + 'f1' + BS + 'fnil' + BS + 'fcharset2 Symbol;}}'#13#10 +
    BS + 'viewkind4' + BS + 'uc1 '#13#10 +
    BS + 'pard{' + BS + 'pntext' + BS + 'f1' + BS + '''B7' + BS + 'tab}{' + BS + '*' + BS +
      'pn' + BS + 'pnlvlblt' + BS + 'pnf1' + BS + 'pnindent0{' + BS + 'pntxtb' + BS +
      '''B7}}' + BS + 'fi-360' + BS + 'li720 bullet\par'#13#10 +
    BS + 'pard{' + BS + 'pntext' + BS + 'f0 3.' + BS + 'tab}{' + BS + '*' + BS + 'pn' + BS +
      'pnlvlbody' + BS + 'pnf0' + BS + 'pnindent0' + BS + 'pnstart3' + BS + 'pndec{' + BS +
      'pntxta.}}' + BS + 'fi-360' + BS + 'li720 three\par'#13#10 +
    BS + 'pard{' + BS + 'pntext' + BS + 'f0 1.' + BS + 'tab}{' + BS + '*' + BS + 'pn' + BS +
      'pnlvl2' + BS + 'pnf0' + BS + 'pnindent0' + BS + 'pnstart1' + BS + 'pndec{' + BS +
      'pntxta.}}' + BS + 'fi-360' + BS + 'li1080 inner\par'#13#10 +
    BS + 'pard{' + BS + 'pntext' + BS + 'f0 ' + Arrow + BS + 'tab}{' + BS + '*' + BS + 'pn' +
      BS + 'pnlvlblt' + BS + 'pnindent0{' + BS + 'pntxtb ' + BS + 'u8594?}}' + BS + 'fi-360' +
      BS + 'li720 arrow\par'#13#10 + '}';
  d := ReadBack(AsBytes(S));
  AssertEquals('a bullet', Ord(lkBullet), Ord(PF(d, 0).List.Kind));
  AssertEquals('its words are the list''s', 0, PF(d, 0).Extra.Count);
  AssertEquals('numbers', Ord(lkDecimal), Ord(PF(d, 1).List.Kind));
  AssertEquals('from three', 3, PF(d, 1).List.StartAt);
  AssertEquals('its words are the list''s', 0, PF(d, 1).Extra.Count);
  AssertEquals('the second level', 1, PF(d, 2).List.Level);
  AssertEquals('a bullet of its own', Arrow, PF(d, 3).List.Bullet);
  AssertEquals('its words are the list''s', 0, PF(d, 3).Extra.Count);
end;

// The system's RichEdit numbers by the {\*\pn ...} beside the list table: a list of one level
// as before - numbered by the control itself, nothing of the marker taken as text; nested
// lists too, each item at the number drawn.
procedure TTyRichWordListTest.TestTheSystemRichEditReadsTheLists;
{$IFDEF WINDOWS}
var
  paras: TReListParas;
  B: TBytes;
  i, w: Integer;
  d: TTyRichDocument;
  k: TTyListKind;
{$ENDIF}
begin
  {$IFDEF WINDOWS}
  for w := 0 to 3 do
  begin
    if w < 3 then Build(w)
    else
    begin
      FRich.Text := 'one';
      AppendParagraphs(['two', 'three', 'plain', 'dot one', 'dot two']);
      for i := 0 to 5 do
      begin
        SelectParagraph(i);
        if i < 3 then FRich.Paragraph.Numbering := lkDecimal
        else if i > 3 then FRich.Paragraph.Numbering := lkBullet;
      end;
    end;
    B := Saved;
    if not RichEditLists(B, paras) then Exit;
    d := FRich.Document;
    AssertEquals(Format('%d: the paragraphs', [w]), d.Text.ParaCount, Length(paras));
    for i := 0 to High(paras) do
    begin
      k := PF(d, i).List.Kind;
      AssertEquals(Format('%d, "%s": no marker taken as text', [w, ParaText(d, i)]),
        ParaText(d, i), string(paras[i].Text));
      if k = lkNone then
        AssertEquals(Format('%d, "%s": no list', [w, ParaText(d, i)]), 0, paras[i].Numbering)
      else if k = lkBullet then
        AssertEquals(Format('%d, "%s": a bullet', [w, ParaText(d, i)]), 1, paras[i].Numbering)
      else
        AssertEquals(Format('%d, "%s": numbers', [w, ParaText(d, i)]), 2, paras[i].Numbering);
    end;
    if w = 3 then
    begin
      AssertEquals('a list of one level: from one', 1, paras[0].Start);
    end;
  end;
  {$ENDIF}
end;

{ NumberingStart written on a selection: its first item begins a new list at that number,
  the others go on; read on an item that goes on: 0; 0 written: they all go on again. }
procedure TTyRichWordListTest.TestAStartGivenThroughTheDoorBeginsANewList;
var
  i: Integer;
begin
  FRich.Text := 'one';
  AppendParagraphs(['two', 'three', 'four', 'five']);
  FRich.SelStart := 0;
  FRich.SelLength := FRich.Document.Text.Length;
  FRich.Paragraph.Numbering := lkDecimal;
  AssertEquals('a list made: no start given', 0, FRich.Paragraph.NumberingStart);
  for i := 0 to 4 do
    AssertEquals(Format('%d: goes on', [i]), IntToStr(i + 1) + '.', string(Drawn(FRich, i)));
  // the last three: a new list from 1, right after the first two
  FRich.SelStart := FRich.Document.Text.ParaStart(2);
  FRich.SelLength := FRich.Document.Text.Length - FRich.SelStart;
  FRich.Paragraph.NumberingStart := 1;
  AssertEquals('the first selected item: its start', 1, PF(FRich.Document, 2).List.StartAt);
  AssertEquals('the others go on', 0, PF(FRich.Document, 3).List.StartAt);
  AssertEquals('before it', '2.', string(Drawn(FRich, 1)));
  AssertEquals('a new list', '1.', string(Drawn(FRich, 2)));
  AssertEquals('which goes on', '3.', string(Drawn(FRich, 4)));
  SelectParagraph(3);
  AssertEquals('read on an item that goes on', 0, FRich.Paragraph.NumberingStart);
  SelectParagraph(2);
  AssertEquals('read on the one given it', 1, FRich.Paragraph.NumberingStart);
  CheckWordShowsWhatIsDrawn(Saved, 'door starts');
  CheckReadsBackTheSame(Saved);
  // 0: it goes on again
  FRich.Paragraph.NumberingStart := 0;
  AssertEquals('goes on again', '3.', string(Drawn(FRich, 2)));
  AssertEquals('and the rest', '5.', string(Drawn(FRich, 4)));
  // one step each
  FRich.Undo;
  AssertEquals('undone', '1.', string(Drawn(FRich, 2)));
end;

{ An item given a start split by Enter: the part after it is the next number, not a list of
  its own; Enter at its start: the empty item keeps the start. }
procedure TTyRichWordListTest.TestEnterOnAnItemGivenAStartGoesOn;
var
  B: TTyRichBuilder;
begin
  B := FRich.NewBuilder;
  try
    B.Numbered(0, 5).Text('fivefive');
    FRich.SetContent(B);
  finally
    B.Free;
  end;
  FRich.SelStart := 4;
  FRich.SelText := #13#10;
  AssertEquals('two items', 2, FRich.Document.Text.ParaCount);
  AssertEquals('the first keeps its start', '5.', string(Drawn(FRich, 0)));
  AssertEquals('the part after it goes on', '6.', string(Drawn(FRich, 1)));
  AssertEquals('it is given no start', 0, PF(FRich.Document, 1).List.StartAt);
  FRich.SelStart := 0;
  FRich.SelText := 'zero'#13#10;
  AssertEquals('a break at the start: the first part keeps the start', '5.',
    string(Drawn(FRich, 0)));
  AssertEquals('the text after it', '6.', string(Drawn(FRich, 1)));
  AssertEquals('and the last', '7.', string(Drawn(FRich, 2)));
  CheckWordShowsWhatIsDrawn(Saved, 'enter');
end;

{ RichMemo: ForceNewNum with NumberStart begins a new list at the range's first item; without
  it the items go on; a read says which. }
procedure TTyRichWordListTest.TestRichMemosForceNewNum;
var
  n: TTyParaNumbering;
begin
  FRich.Text := 'one';
  AppendParagraphs(['two', 'three', 'four']);
  n := Default(TTyParaNumbering);
  n.Style := pnNumber;
  FRich.SetParaNumbering(0, FRich.Document.Text.Length, n);
  AssertEquals('no ForceNewNum: they go on', '4.', string(Drawn(FRich, 3)));
  // a start without ForceNewNum is no start given
  n.NumberStart := 5;
  FRich.SetParaNumbering(FRich.Document.Text.ParaStart(2), 3, n);
  AssertEquals('NumberStart alone: they go on', '3.', string(Drawn(FRich, 2)));
  n.ForceNewNum := True;
  n.NumberStart := 7;
  FRich.SetParaNumbering(FRich.Document.Text.ParaStart(2), 3, n);
  AssertEquals('ForceNewNum: a new list at the range''s first item', '7.', string(Drawn(FRich, 2)));
  AssertEquals('the next goes on', '8.', string(Drawn(FRich, 3)));
  AssertEquals('before it', '2.', string(Drawn(FRich, 1)));
  AssertTrue('read: given a start', FRich.GetParaNumbering(FRich.Document.Text.ParaStart(2), n));
  AssertTrue('ForceNewNum read', n.ForceNewNum);
  AssertEquals('NumberStart read', 7, n.NumberStart);
  FRich.GetParaNumbering(FRich.Document.Text.ParaStart(3), n);
  AssertFalse('an item that goes on: no ForceNewNum', n.ForceNewNum);
  AssertEquals('and no start', 0, n.NumberStart);
end;

// Earlier builds wrote every item's {\*\pn ...} with its \pnstart, the items after the first
// with the same group (or none, which keeps it): the first is given the start, the others go
// on - read as they were drawn.
procedure TTyRichWordListTest.TestAnOlderPnRunGoesOnAsBefore;
var
  d: TTyRichDocument;
  S, pn3, pn1: RawByteString;
begin
  pn3 := '{' + BS + '*' + BS + 'pn' + BS + 'pnlvlbody' + BS + 'pnf0' + BS + 'pnindent0' + BS +
    'pnstart3' + BS + 'pndec{' + BS + 'pntxta.}}';
  pn1 := '{' + BS + '*' + BS + 'pn' + BS + 'pnlvlbody' + BS + 'pnf0' + BS + 'pnindent0' + BS +
    'pnstart1' + BS + 'pndec{' + BS + 'pntxta.}}';
  S := '{' + BS + 'rtf1' + BS + 'ansi' + BS + 'deff0{' + BS + 'fonttbl{' + BS + 'f0' + BS +
    'fnil Arial;}}'#13#10 + BS + 'viewkind4' + BS + 'uc1 '#13#10 +
    BS + 'pard{' + BS + 'pntext' + BS + 'f0 3.' + BS + 'tab}' + pn3 + BS + 'fi-360' + BS +
      'li720 three\par'#13#10 +
    '{' + BS + 'pntext' + BS + 'f0 4.' + BS + 'tab}four\par'#13#10 +
    BS + 'pard{' + BS + 'pntext' + BS + 'f0 5.' + BS + 'tab}' + pn3 + BS + 'fi-360' + BS +
      'li720 five\par'#13#10 +
    BS + 'pard{' + BS + 'pntext' + BS + 'f0 1.' + BS + 'tab}' + pn1 + BS + 'fi-360' + BS +
      'li720 one again\par'#13#10 + '}';
  d := ReadBack(AsBytes(S));
  AssertEquals('the first: its start', 3, PF(d, 0).List.StartAt);
  AssertEquals('the next (the group kept): goes on', 0, PF(d, 1).List.StartAt);
  AssertEquals('the same group again: goes on', 0, PF(d, 2).List.StartAt);
  AssertEquals('another group: its start', 1, PF(d, 3).List.StartAt);
  AssertEquals('drawn: 3', '3.', string(Drawn(FBack, 0)));
  AssertEquals('drawn: 4', '4.', string(Drawn(FBack, 1)));
  AssertEquals('drawn: 5', '5.', string(Drawn(FBack, 2)));
  AssertEquals('drawn: 1', '1.', string(Drawn(FBack, 3)));
end;

{ Every case at once, in one file of the builder's (the file the Word check opens): numbers on
  three levels, an outer list going on after its inner items, a start other than 1, a list
  after a plain paragraph starting again, a list given a start right after another, a list
  from 5 followed by a new list from 1, inner items after a new and after a going-on outer
  item, bullets on two levels, a bullet of the user's own. }
procedure TTyRichWordListTest.TestEveryCaseInOneFile;
var
  B: TTyRichBuilder;
begin
  B := FRich.NewBuilder;
  try
    B.Text('Lists as the control draws them');
    B.Paragraph.Numbered(0, 3).Text('A1 numbered from three');
    B.Paragraph.Numbered(0).Text('A2 numbered next');
    B.Paragraph.Numbered(1).Text('A3 inner one');
    B.Paragraph.Numbered(1).Text('A4 inner two');
    B.Paragraph.Numbered(2).Text('A5 third level one');
    B.Paragraph.Numbered(2).Text('A6 third level two');
    B.Paragraph.Numbered(1).Text('A7 inner three');
    B.Paragraph.Numbered(0).Text('A8 outer goes on after its inner items');
    B.Paragraph.Text('B0 a plain paragraph');
    B.Paragraph.Numbered(0).Text('B1 after the plain paragraph');
    B.Paragraph.Numbered(0).Text('B2 goes on');
    B.Paragraph.Numbered(0, 10).Text('B3 a new list from ten right after');
    B.Paragraph.Numbered(0).Text('B4 goes on from ten');
    B.Paragraph.Text('C0 another plain paragraph');
    B.Paragraph.Numbered(0, 5).Text('C1 a list from five');
    B.Paragraph.Numbered(0).Text('C2 goes on');
    B.Paragraph.Numbered(0).Text('C3 goes on again');
    B.Paragraph.Numbered(0, 1).Text('C4 a new list from one right after');
    B.Paragraph.Numbered(0).Text('C5 goes on');
    B.Paragraph.Numbered(1).Text('C6 inner after it');
    B.Paragraph.Numbered(1, 4).Text('C7 inner from four');
    B.Paragraph.Numbered(1).Text('C8 inner goes on');
    B.Paragraph.Numbered(0, 1).Text('C9 a new outer list');
    B.Paragraph.Numbered(1).Text('D1 inner after the new outer');
    B.Paragraph.Numbered(0).Text('D2 outer that goes on');
    B.Paragraph.Numbered(1).Text('D3 inner after the outer that goes on');
    B.Paragraph.Text('E0 a plain paragraph before the bullets');
    B.Paragraph.Bullet(0).Text('E1 bullet level one');
    B.Paragraph.Bullet(1).Text('E2 bullet level two');
    B.Paragraph.Bullet(1).Text('E3 bullet level two again');
    B.Paragraph.Bullet(0).Text('E4 bullet level one again');
    B.Paragraph.Bullet(0, Arrow).Text('E5 a bullet of its own');
    B.Paragraph.Bullet(1, Star).Text('E6 a deeper bullet of its own');
    B.Paragraph.Text('F0 the end');
    FRich.SetContent(B);
  finally
    B.Free;
  end;
  AssertEquals('A8', '5.', string(Drawn(FRich, 8)));
  AssertEquals('B3', '10.', string(Drawn(FRich, 12)));
  AssertEquals('C4', '1.', string(Drawn(FRich, 18)));
  AssertEquals('C6', '1.', string(Drawn(FRich, 20)));
  AssertEquals('D3', '1.', string(Drawn(FRich, 26)));
  CheckWordShowsWhatIsDrawn(Saved, 'builder-every-case');
  CheckReadsBackTheSame(Saved);
end;

initialization
  RegisterTest(TTyRichWordListTest);

end.
