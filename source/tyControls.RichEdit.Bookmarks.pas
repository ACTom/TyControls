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
  Classes, SysUtils, Generics.Collections, tyControls.RichEdit.Text, tyControls.RichEdit.Model;

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
{ The mark of AKind named AName at or after AFrom (-1: none): what TyRichFindBookmark asks. }
function TyRichFindBookmarkMark(ADoc: TTyRichDocument; AKind: TTyRichBookmarkKind;
  const AName: UTF8String; AFrom: TTyRichPos): TTyRichPos;

type
  { One bookmark the list knows: from a paragraph's value (Name known) or from the load's index
    (Entry; its name decoded the first time it is asked for). }
  TTyRichBookmarkItem = record
    Entry: Integer;
    Para: Integer;
    Sub: Int64;
    Hash: Cardinal;
    Hidden: Boolean;
    Named: Boolean;
    Name: UTF8String;
  end;

  { The document's bookmarks for a view that asks for them often (BookmarkCount and
    BookmarkName in an idle handler, a list in a form): counted from the load's index and the
    paragraphs' values without decoding a name (a name of the index is decoded when it is
    asked for, once), in the order of their starts, one per name (names compare without
    regard to case). Kept across a change of the document that leaves the paragraphs as many
    as they were and touches no paragraph a bookmark is in, before or after it (one typed
    character); any other change (Changed) has it built again when next asked. }
  TTyRichBookmarkList = class
  private
    FDoc: TTyRichDocument;
    FValid: Boolean;
    FItems: array of TTyRichBookmarkItem;
    FItemN: Integer;
    FAll, FShown: array of Integer;
    FBuilds: Integer;
    // the walk's unparsed paragraphs of the file: their offsets and indexes
    FLazySrc: array of Int64;
    FLazyPara: array of Integer;
    FLazyN: Integer;
    procedure Build;
    procedure Visit(AIndex: Integer; AData: Pointer; ASrcOffset, ASrcBytes: Int64;
      var AContinue: Boolean);
    procedure Add(const AItem: TTyRichBookmarkItem);
    function ItemName(AItem: Integer): UTF8String;
    function SameItem(A, B: Integer): Boolean;
    // the first item of paragraph APara or after it (FItems is in order)
    function FirstOf(APara: Integer): Integer;
  public
    constructor Create(ADoc: TTyRichDocument);
    destructor Destroy; override;
    { The document's change (its OnChange's): the list is kept or let go. }
    procedure Changed(const AChange: TTyRichChange);
    // the document is another or has another content: built again when next asked
    procedure Reset;
    function Count(AIncludeHidden: Boolean): Integer;
    function Name(AIndex: Integer; AIncludeHidden: Boolean): UTF8String;
    // how many times it was built (for the tests that hold it to one)
    property Builds: Integer read FBuilds;
  end;

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

function TyRichFindBookmarkMark(ADoc: TTyRichDocument; AKind: TTyRichBookmarkKind;
  const AName: UTF8String; AFrom: TTyRichPos): TTyRichPos;
begin
  Result := FindMark(ADoc, AKind, AName, AFrom);
end;

{ ---- TTyRichBookmarkList ---- }

constructor TTyRichBookmarkList.Create(ADoc: TTyRichDocument);
begin
  inherited Create;
  FDoc := ADoc;
end;

destructor TTyRichBookmarkList.Destroy;
begin
  inherited Destroy;
end;

function TTyRichBookmarkList.FirstOf(APara: Integer): Integer;
var
  lo, hi, mid: Integer;
begin
  lo := 0;
  hi := FItemN;
  while lo < hi do
  begin
    mid := (lo + hi) shr 1;
    if FItems[mid].Para < APara then lo := mid + 1 else hi := mid;
  end;
  Result := lo;
end;

procedure TTyRichBookmarkList.Reset;
begin
  FValid := False;
end;

procedure TTyRichBookmarkList.Add(const AItem: TTyRichBookmarkItem);
begin
  if FItemN = Length(FItems) then SetLength(FItems, FItemN * 2 + 64);
  FItems[FItemN] := AItem;
  Inc(FItemN);
end;

procedure TTyRichBookmarkList.Visit(AIndex: Integer; AData: Pointer; ASrcOffset,
  ASrcBytes: Int64; var AContinue: Boolean);
var
  fmt: TTyParaFormatId;
  runs: TTyRunArray;
  cell: TTyRichCell;
  i: Integer;
  m: TTyRichBookmarkMark;
  it: TTyRichBookmarkItem;
begin
  if AData = nil then
  begin
    // the file's own, unparsed: the index speaks for it
    if ASrcOffset < 0 then Exit;
    if FLazyN = Length(FLazySrc) then
    begin
      SetLength(FLazySrc, FLazyN * 2 + 256);
      SetLength(FLazyPara, FLazyN * 2 + 256);
    end;
    FLazySrc[FLazyN] := ASrcOffset;
    FLazyPara[FLazyN] := AIndex;
    Inc(FLazyN);
    Exit;
  end;
  if not FDoc.ReadValue(AData, fmt, runs, cell) then Exit;
  for i := 0 to High(runs) do
    if runs[i].Obj is TTyRichBookmarkMark then
    begin
      m := TTyRichBookmarkMark(runs[i].Obj);
      if m.Kind <> rbmStart then Continue;
      it.Entry := -1;
      it.Para := AIndex;
      it.Sub := runs[i].Start;
      it.Hash := TyRichBookmarkHash(m.Name);
      it.Hidden := TyRichBookmarkHidden(m.Name);
      it.Named := True;
      it.Name := m.Name;
      Add(it);
    end;
end;

procedure TTyRichBookmarkList.Build;
var
  ld: TTyRichParaLoader;
  vals: array of TTyRichBookmarkItem;
  valN, i, j, n, t: Integer;
  k: TTyRichBookmarkKind;
  h: Cardinal;
  psrc, gsrc: Int64;
  it: TTyRichBookmarkItem;
  seen: TTyRichHashCounts;
  merged: array of TTyRichBookmarkItem;
  first: Integer;
  v: Int64;
  dup: Boolean;
begin
  Inc(FBuilds);
  FItemN := 0;
  FItems := nil;
  FLazyN := 0;
  ld := FDoc.Loader;
  if (ld <> nil) and (ld.BookmarkIndexCount < 0) then ld := nil;
  FDoc.BeginRead;
  try
    FDoc.Text.WalkParas(0, @Visit);
  finally
    FDoc.EndRead;
  end;
  // the values' items (in order), then the index's for the unparsed paragraphs (in order)
  valN := FItemN;
  vals := Copy(FItems, 0, valN);
  FItemN := 0;
  if (ld <> nil) and (FLazyN > 0) then
  begin
    n := ld.BookmarkIndexCount;
    j := 0;
    for i := 0 to n - 1 do
    begin
      ld.BookmarkIndexEntry(i, k, h, psrc, gsrc);
      if k <> rbmStart then Continue;
      while (j < FLazyN) and (FLazySrc[j] < psrc) do Inc(j);
      if j >= FLazyN then Break;
      if FLazySrc[j] <> psrc then Continue;
      it.Entry := i;
      it.Para := FLazyPara[j];
      it.Sub := gsrc - psrc;
      it.Hash := h;
      it.Hidden := ld.BookmarkIndexHidden(i);
      it.Named := False;
      it.Name := '';
      Add(it);
    end;
  end;
  // merged by paragraph (no paragraph is in both)
  merged := nil;
  SetLength(merged, valN + FItemN);
  i := 0;
  j := 0;
  t := 0;
  while (i < valN) or (j < FItemN) do
  begin
    if (j >= FItemN) or ((i < valN) and ((vals[i].Para < FItems[j].Para) or
      ((vals[i].Para = FItems[j].Para) and (vals[i].Sub < FItems[j].Sub)))) then
    begin
      merged[t] := vals[i];
      Inc(i);
    end
    else
    begin
      merged[t] := FItems[j];
      Inc(j);
    end;
    Inc(t);
  end;
  FItems := merged;
  FItemN := t;
  { one per name, the first. Told apart by the names' hashes (the first item of each); a hash
    met again has the two names decoded and compared (a hash is no name: two names may have
    one) }
  seen := TTyRichHashCounts.Create(FItemN);
  try
    FAll := nil;
    FShown := nil;
    SetLength(FAll, FItemN);
    SetLength(FShown, FItemN);
    n := 0;
    t := 0;
    for i := 0 to FItemN - 1 do
    begin
      if seen.TryGet(FItems[i].Hash, v) then
      begin
        first := Integer(v);
        dup := SameItem(i, first);
        // (another name of that hash: the ones taken so far of it, each)
        for j := 0 to n - 1 do
          if dup then Break
          else if (FAll[j] <> first) and (FItems[FAll[j]].Hash = FItems[i].Hash) then
            dup := SameItem(i, FAll[j]);
        if dup then Continue;
      end
      else
        seen.Add(FItems[i].Hash, i);
      FAll[n] := i;
      Inc(n);
      if not FItems[i].Hidden then
      begin
        FShown[t] := i;
        Inc(t);
      end;
    end;
    SetLength(FAll, n);
    SetLength(FShown, t);
  finally
    seen.Free;
  end;
  FValid := True;
end;

procedure TTyRichBookmarkList.Changed(const AChange: TTyRichChange);
const
  // (more changed paragraphs than a key's: built again, none of them read)
  CFew = 8;
var
  p, i, j: Integer;
  runs: TTyRunArray;
  m: TTyRichBookmarkMark;
  has: Boolean;
begin
  if not FValid then Exit;
  // paragraphs came or went: every paragraph after them is another index
  if (AChange.OldParaCount <> AChange.NewParaCount) or (rckStructure in AChange.Kinds) or
    (AChange.NewParaCount > CFew) then
  begin
    FValid := False;
    Exit;
  end;
  { Each changed paragraph's starts against the list's: the same names in the same order (a
    character typed beside them) keep the list; their places follow. }
  for p := AChange.FirstPara to AChange.FirstPara + AChange.NewParaCount - 1 do
  begin
    if (p < 0) or (p >= FDoc.Text.ParaCount) then Continue;
    j := FirstOf(p);
    has := (j < FItemN) and (FItems[j].Para = p);
    runs := FDoc.RunsOf(p);
    for i := 0 to High(runs) do
    begin
      if not (runs[i].Obj is TTyRichBookmarkMark) then Continue;
      m := TTyRichBookmarkMark(runs[i].Obj);
      if m.Kind <> rbmStart then Continue;
      if not has or (j >= FItemN) or (FItems[j].Para <> p) or
        (FItems[j].Hash <> TyRichBookmarkHash(m.Name)) or (ItemName(j) <> m.Name) then
      begin
        FValid := False;
        Exit;
      end;
      FItems[j].Sub := runs[i].Start;
      Inc(j);
    end;
    // a start that went
    if has and (j < FItemN) and (FItems[j].Para = p) then
    begin
      FValid := False;
      Exit;
    end;
  end;
end;

function TTyRichBookmarkList.ItemName(AItem: Integer): UTF8String;
var
  ld: TTyRichParaLoader;
begin
  if not FItems[AItem].Named then
  begin
    ld := FDoc.Loader;
    if ld <> nil then FItems[AItem].Name := ld.BookmarkIndexName(FItems[AItem].Entry);
    FItems[AItem].Named := True;
  end;
  Result := FItems[AItem].Name;
end;

function TTyRichBookmarkList.SameItem(A, B: Integer): Boolean;
begin
  Result := TyRichSameBookmarkName(ItemName(A), ItemName(B));
end;

function TTyRichBookmarkList.Count(AIncludeHidden: Boolean): Integer;
begin
  if not FValid then Build;
  if AIncludeHidden then Result := Length(FAll) else Result := Length(FShown);
end;

function TTyRichBookmarkList.Name(AIndex: Integer; AIncludeHidden: Boolean): UTF8String;
var
  i: Integer;
  ld: TTyRichParaLoader;
begin
  if not FValid then Build;
  if AIncludeHidden then
  begin
    if (AIndex < 0) or (AIndex > High(FAll)) then raise EListError.CreateFmt('Bookmark %d', [AIndex]);
    i := FAll[AIndex];
  end
  else
  begin
    if (AIndex < 0) or (AIndex > High(FShown)) then raise EListError.CreateFmt('Bookmark %d', [AIndex]);
    i := FShown[AIndex];
  end;
  Result := ItemName(i);
end;

end.
