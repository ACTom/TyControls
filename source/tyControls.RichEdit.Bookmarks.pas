unit tyControls.RichEdit.Bookmarks;

{ Bookmarks of a TTyRichEdit document, found by name and listed. A bookmark is two zero-width
  objects of the model (TTyRichBookmarkMark: its start and its end, each with the name); what
  lies between them is the bookmark's text.

  A document read on demand (RTF, its paragraphs parsed when they are first read) is never
  read whole for this: the load's index scan records each bookmark end it meets - its kind,
  the hash of its name, the file offsets of its group and of its paragraph
  (TTyRichParaLoader.BookmarkIndexEntry: 13 bytes an end in the scan and 8 in the load, 42
  bytes a bookmark) - so a bookmark is found by parsing only the paragraphs its two ends are
  in, and the names are listed from the file's bytes with nothing parsed. Paragraphs that are
  no longer the file's (edited, or made by an edit) are asked by their values, which a walk of
  the paragraphs hands out without a parse; a document with no index (a text file, a whole
  load, a new document) is asked so throughout. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, tyControls.RichEdit.Text, tyControls.RichEdit.Model;

const
  // the longest name Word takes for a bookmark
  CTyRichBookmarkMaxName = 40;

{ A name Word takes for a new bookmark: 1 to 40 characters, the first a letter (an ideograph
  is one), the rest letters, digits or "_". (Names in files may be otherwise - Word's own
  hidden ones begin with "_" - and are found and listed as they are.) }
function TyRichBookmarkNameValid(const AName: UTF8String): Boolean;
{ A hidden bookmark: its name begins with "_" (Word's for a table of contents' headings, its
  cross-references), not listed unless asked for. }
function TyRichBookmarkHidden(const AName: UTF8String): Boolean;
{ The bookmark named AName (case does not matter): AStart the position of its start mark,
  AEnd of its end mark (its text is what lies between). With no end mark in the document AEnd
  is AStart. False: no start mark of that name. Reads what is said above. }
function TyRichFindBookmark(ADoc: TTyRichDocument; const AName: UTF8String;
  out AStart, AEnd: TTyRichPos): Boolean;
{ The names of the document's bookmarks, in the order of their start marks; the hidden ones
  (TyRichBookmarkHidden) only with AIncludeHidden. A name met twice is listed once. }
function TyRichBookmarkNames(ADoc: TTyRichDocument; AIncludeHidden: Boolean): TStringArray;

implementation

uses
  LazUTF8;

function CodeAt(const S: UTF8String; var I: Integer): Cardinal;
var
  b: Byte;
  n: Integer;
begin
  b := Byte(S[I]);
  if b < $80 then n := 1
  else if b >= $F0 then n := 4
  else if b >= $E0 then n := 3
  else if b >= $C0 then n := 2
  else n := 1;
  if I + n - 1 > Length(S) then n := 1;
  case n of
    2: Result := ((b and $1F) shl 6) or (Byte(S[I + 1]) and $3F);
    3: Result := ((b and $F) shl 12) or ((Byte(S[I + 1]) and $3F) shl 6) or (Byte(S[I + 2]) and $3F);
    4: Result := ((b and 7) shl 18) or ((Byte(S[I + 1]) and $3F) shl 12) or
         ((Byte(S[I + 2]) and $3F) shl 6) or (Byte(S[I + 3]) and $3F);
  else
    if b < $80 then Result := b else Result := $FFFD;
  end;
  Inc(I, n);
end;

{ The punctuation and symbols of the CJK blocks and the full-width forms: no letters. }
function CjkPunctuation(C: Cardinal): Boolean;
begin
  Result := ((C >= $3000) and (C <= $303F)) or ((C >= $FF00) and (C <= $FF0F)) or
    ((C >= $FF1A) and (C <= $FF20)) or ((C >= $FF3B) and (C <= $FF40)) or
    ((C >= $FF5B) and (C <= $FF65)) or ((C >= $2000) and (C <= $206F));
end;

function TyRichBookmarkNameValid(const AName: UTF8String): Boolean;
var
  i, count: Integer;
  c: Cardinal;
  letter, digit: Boolean;
begin
  Result := False;
  i := 1;
  count := 0;
  while i <= Length(AName) do
  begin
    c := CodeAt(AName, i);
    Inc(count);
    if count > CTyRichBookmarkMaxName then Exit;
    digit := (c >= Ord('0')) and (c <= Ord('9'));
    letter := ((c >= Ord('A')) and (c <= Ord('Z'))) or ((c >= Ord('a')) and (c <= Ord('z'))) or
      ((c >= $80) and (c <> $FFFD) and (TyRichWordClass(c) = 1) and not CjkPunctuation(c));
    if count = 1 then
    begin
      if not letter then Exit;
    end
    else if not (letter or digit or (c = Ord('_'))) then
      Exit;
  end;
  Result := count > 0;
end;

function TyRichBookmarkHidden(const AName: UTF8String): Boolean;
begin
  Result := (AName <> '') and (AName[1] = '_');
end;

type
  { One walk of the paragraphs' values for bookmark marks (those the index does not cover). }
  TTyRichBookmarkWalk = class
  public
    Doc: TTyRichDocument;
    Indexed: Boolean;           // the load's index covers the unedited lazy paragraphs
    // what is looked for: a mark of Kind named Name at or after From (Name '' : every start)
    Name: UTF8String;
    Kind: TTyRichBookmarkKind;
    From: TTyRichPos;
    Found: TTyRichPos;
    // listing: every start met, with where it is
    Listing: Boolean;
    Names: array of UTF8String;
    Paras: array of Integer;
    Subs: array of Int64;
    Count: Integer;
    procedure Visit(AIndex: Integer; AData: Pointer; ASrcOffset, ASrcBytes: Int64;
      var AContinue: Boolean);
  end;

procedure TTyRichBookmarkWalk.Visit(AIndex: Integer; AData: Pointer; ASrcOffset,
  ASrcBytes: Int64; var AContinue: Boolean);
var
  fmt: TTyParaFormatId;
  runs: TTyRunArray;
  cell: TTyRichCell;
  i: Integer;
  ps, p: TTyRichPos;
  m: TTyRichBookmarkMark;
begin
  // (the index covers the file's own paragraphs; one not parsed has no value, and no mark)
  if (AData = nil) or (Indexed and (ASrcOffset >= 0)) then Exit;
  if not Doc.ReadValue(AData, fmt, runs, cell) then Exit;
  ps := -1;
  for i := 0 to High(runs) do
  begin
    if not (runs[i].Obj is TTyRichBookmarkMark) then Continue;
    m := TTyRichBookmarkMark(runs[i].Obj);
    if ps < 0 then ps := Doc.Text.ParaStart(AIndex);
    p := ps + runs[i].Start;
    if Listing then
    begin
      if m.Kind <> rbmStart then Continue;
      if Count = Length(Names) then
      begin
        SetLength(Names, Count * 2 + 16);
        SetLength(Paras, Count * 2 + 16);
        SetLength(Subs, Count * 2 + 16);
      end;
      Names[Count] := m.Name;
      Paras[Count] := AIndex;
      Subs[Count] := runs[i].Start;
      Inc(Count);
      Continue;
    end;
    if (m.Kind = Kind) and (p >= From) and TyRichSameBookmarkName(m.Name, Name) then
    begin
      Found := p;
      AContinue := False;
      Exit;
    end;
  end;
end;

{ The mark of AKind named AName in paragraph AIndex (parsed), -1: none. }
function MarkInPara(ADoc: TTyRichDocument; AIndex: Integer; AKind: TTyRichBookmarkKind;
  const AName: UTF8String; AFrom: TTyRichPos): TTyRichPos;
var
  runs: TTyRunArray;
  i: Integer;
  ps: TTyRichPos;
  m: TTyRichBookmarkMark;
begin
  Result := -1;
  ADoc.BeginRead;
  try
    runs := ADoc.RunsOf(AIndex);
    ps := ADoc.Text.ParaStart(AIndex);
    for i := 0 to High(runs) do
      if runs[i].Obj is TTyRichBookmarkMark then
      begin
        m := TTyRichBookmarkMark(runs[i].Obj);
        if (m.Kind = AKind) and (ps + runs[i].Start >= AFrom) and
          TyRichSameBookmarkName(m.Name, AName) then
          Exit(ps + runs[i].Start);
      end;
  finally
    ADoc.EndRead;
  end;
end;

function IndexOf(ADoc: TTyRichDocument): TTyRichParaLoader;
begin
  Result := ADoc.Loader;
  if (Result <> nil) and (Result.BookmarkIndexCount < 0) then Result := nil;
end;

{ The mark of AKind named AName at or after AFrom, through the index (its entries whose
  paragraph is the file's still) and then the values. }
function FindMark(ADoc: TTyRichDocument; AKind: TTyRichBookmarkKind; const AName: UTF8String;
  AFrom: TTyRichPos): TTyRichPos;
var
  ld: TTyRichParaLoader;
  i, para: Integer;
  k: TTyRichBookmarkKind;
  h, hk: Cardinal;
  psrc, gsrc: Int64;
  w: TTyRichBookmarkWalk;
begin
  Result := -1;
  ld := IndexOf(ADoc);
  if ld <> nil then
  begin
    h := TyRichBookmarkHash(AName);
    for i := 0 to ld.BookmarkIndexCount - 1 do
    begin
      ld.BookmarkIndexEntry(i, k, hk, psrc, gsrc);
      if (k <> AKind) or (hk <> h) then Continue;
      para := ADoc.Text.ParaOfLazySource(psrc);
      if para < 0 then Continue;
      if ADoc.Text.ParaStart(para) + ADoc.Text.ParaLength(para) < AFrom then Continue;
      Result := MarkInPara(ADoc, para, AKind, AName, AFrom);
      if Result >= 0 then Exit;
    end;
  end;
  w := TTyRichBookmarkWalk.Create;
  try
    w.Doc := ADoc;
    w.Indexed := ld <> nil;
    w.Name := AName;
    w.Kind := AKind;
    w.From := AFrom;
    w.Found := -1;
    ADoc.BeginRead;
    try
      ADoc.Text.WalkParas(0, @w.Visit);
    finally
      ADoc.EndRead;
    end;
    Result := w.Found;
  finally
    w.Free;
  end;
end;

function TyRichFindBookmark(ADoc: TTyRichDocument; const AName: UTF8String;
  out AStart, AEnd: TTyRichPos): Boolean;
begin
  AStart := -1;
  AEnd := -1;
  Result := False;
  if (ADoc = nil) or (AName = '') then Exit;
  AStart := FindMark(ADoc, rbmStart, AName, 0);
  if AStart < 0 then Exit;
  AEnd := FindMark(ADoc, rbmEnd, AName, AStart);
  if AEnd < 0 then AEnd := AStart;
  Result := True;
end;

function TyRichBookmarkNames(ADoc: TTyRichDocument; AIncludeHidden: Boolean): TStringArray;
var
  ld: TTyRichParaLoader;
  w: TTyRichBookmarkWalk;
  i, j, n, para: Integer;
  k: TTyRichBookmarkKind;
  hk: Cardinal;
  psrc, gsrc, sub: Int64;
  name, tmp: UTF8String;
  seen: TStringList;
  order: array of Integer;
  t, walked: Integer;

  function Less(A, B: Integer): Boolean;
  begin
    Result := (w.Paras[A] < w.Paras[B]) or ((w.Paras[A] = w.Paras[B]) and (w.Subs[A] < w.Subs[B]));
  end;

begin
  Result := nil;
  if ADoc = nil then Exit;
  ld := IndexOf(ADoc);
  w := TTyRichBookmarkWalk.Create;
  seen := TStringList.Create;
  try
    w.Doc := ADoc;
    w.Indexed := ld <> nil;
    w.Listing := True;
    ADoc.BeginRead;
    try
      ADoc.Text.WalkParas(0, @w.Visit);
    finally
      ADoc.EndRead;
    end;
    walked := w.Count;
    // the file's own paragraphs: from the index, by the file's bytes
    if ld <> nil then
      for i := 0 to ld.BookmarkIndexCount - 1 do
      begin
        ld.BookmarkIndexEntry(i, k, hk, psrc, gsrc);
        if k <> rbmStart then Continue;
        para := ADoc.Text.ParaOfLazySource(psrc);
        if para < 0 then Continue;
        name := ld.BookmarkIndexName(i);
        sub := gsrc - psrc;
        if w.Count = Length(w.Names) then
        begin
          SetLength(w.Names, w.Count * 2 + 16);
          SetLength(w.Paras, w.Count * 2 + 16);
          SetLength(w.Subs, w.Count * 2 + 16);
        end;
        w.Names[w.Count] := name;
        w.Paras[w.Count] := para;
        w.Subs[w.Count] := sub;
        Inc(w.Count);
      end;
    // in the order of the document: the walk's and the index's are each in order - merged
    order := nil;
    SetLength(order, w.Count);
    i := 0;
    j := walked;
    t := 0;
    while (i < walked) or (j < w.Count) do
    begin
      if (j >= w.Count) or ((i < walked) and Less(i, j)) then
      begin
        order[t] := i;
        Inc(i);
      end
      else
      begin
        order[t] := j;
        Inc(j);
      end;
      Inc(t);
    end;
    seen.Sorted := True;
    seen.CaseSensitive := True;
    n := 0;
    SetLength(Result, w.Count);
    for i := 0 to w.Count - 1 do
    begin
      name := w.Names[order[i]];
      if not AIncludeHidden and TyRichBookmarkHidden(name) then Continue;
      tmp := UTF8UpperCase(name);
      if seen.IndexOf(tmp) >= 0 then Continue;
      seen.Add(tmp);
      Result[n] := name;
      Inc(n);
    end;
    SetLength(Result, n);
  finally
    seen.Free;
    w.Free;
  end;
end;

end.
