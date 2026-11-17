unit tyControls.RichEdit.Find;

{ Finding text in TTyRichEdit's document, and replacing what was found: the engine's part. No
  control is needed; the control drives a finder in its background turns or to the end at once.

  What a match is: the needle against the text as the user sees it - the characters of the
  paragraphs in order, a paragraph's end one character. In the needle CR LF, LF and CR are each
  one paragraph end; U+000B (a line break inside a paragraph) is a character of its own. A
  byte of the text that starts no valid UTF-8 sequence (a text file's escaped byte is two of
  them) is a character that only the same byte in the needle matches. An object (U+FFFC) is
  matched by nothing: a needle that holds one finds nothing, and an object in the text breaks
  any match across it. The paragraphs of a table cell merged into the one before it (\clmrg)
  are not there for a find - the layout shows nothing of them. A cut paragraph's hidden tail
  (past CRichMaxParaLayoutChars) is text and is found. Positions are whole characters, as the
  text storage counts them; nothing is normalised (a combining mark is compared as it is).

  Case: without rfoMatchCase every character is compared through TyRichFoldChar - LazUtils'
  UnicodeLowercase per code point (Latin with its supplements and extended blocks, Greek,
  Cyrillic, Armenian, Georgian, full-width Latin, and the other ranges that function covers),
  final sigma as sigma. A code point at a time, as the text is read: no lowered copy of the
  text is made. Whole word (rfoWholeWord): the match does not cut a word of the caret's word
  rule (TyRichWordClass) in two - at each end, the character outside and the needle's own
  character there are not both word characters. Chinese, like Latin letters, is word
  characters, so a Chinese needle matches as a whole word only where a run of word characters
  begins and ends with it (the run that a double click selects).

  Text that was never parsed (a lazily read RTF): a paragraph that is still its bytes in the
  file is first looked for in those bytes (TTyRichRawFilter: every form the reader
  turns into a character of the needle's first 64 - by the reader's own rules, shared with it
  in RtfRead -, every group either read or passed over, every character a \uN may skip, in
  every code page the file ever named), and decoded only when it may hold the needle; it is
  decoded through the text's walk that hands out paragraph values of the moment (nothing is
  set, nothing is kept beyond what the reader keeps of any read). A needle with paragraph ends
  is looked for paragraph by paragraph: a middle paragraph must be a segment whole (its
  length, from the paragraph tree, says much: two paragraph ends in a row are an empty
  paragraph), the first must end with the first segment and the last begin with the last
  (each filtered for its segment's text); only the paragraphs of a match that may be there are
  read. U+FFFD is not filtered: the reader makes it of too many things.

  An object never matches text - and a field (a link) is an object: its display text is not
  found. When field results become text the control shows, the finder must see them.

  Replacing: TTyRichReplaceCommand replaces a list of matches, the last one first, so that no
  position moves before it is used; consecutive commands of one replace (the same session)
  merge into one undo step. }

{$mode objfpc}{$H+}
{$inline on}

interface

uses
  Classes, SysUtils, tyControls.RichEdit.Text, tyControls.RichEdit.Model,
  tyControls.RichEdit.RtfRead;

const
  { The code the finder gives a paragraph's end (in the needle and between paragraphs). }
  TyRichFindParaEnd = $FFFFFFFF;
  { A byte that starts no valid UTF-8 sequence is this plus the byte: it matches only itself. }
  TyRichFindRawByte = $110000;
  { The most characters of the needle the raw-byte filter looks for (its first ones): a match of
    the whole needle holds them, so a longer needle is filtered by them. }
  TyRichFindFilterChars = 64;

type
  TTyRichCodeArray = array of Cardinal;

  { rfoWrap is the control's (TTyCustomRichEdit.FindNext: past the end, on from the other
    end); a finder searches its range and does not look at it. }
  TTyRichFindOption = (rfoMatchCase, rfoWholeWord, rfoBackward, rfoWrap);
  TTyRichFindOptions = set of TTyRichFindOption;

  { What a step of a finder ended with. rfrMore: its budget is spent (or, Waiting, the text it
    may search is searched and a load is still adding to it) - call Step again. }
  TTyRichFindResult = (rfrMore, rfrFound, rfrNotFound);

  { What the raw-byte filter says of a paragraph's bytes: they may hold the needle (decode
    them), they cannot, or (fvMore) its budget ran out first - go on with Run. }
  TTyRichFilterVerdict = (fvMay, fvCannot, fvMore);

  { What the filter carries into a group, to put back (or join) at its end. }
  TTyRichFilterSave = record
    D, T, Lead: QWord;
    LeadByte: Integer;
    Wild: QWord;
  end;

  { A needle turned into what the raw-byte filter compares: built once per finder (and again
    when the file's code pages grew). It reads a paragraph's bytes by the reader's own rules
    (TTyRtfLexer, and RtfRead's TyRtfByteRole, TyRtfUnicodeOf, TyRtfWordChar, TyRtfSymbolChar),
    in pieces: Start, then Run until it says fvMay or fvCannot - its state (a few words and
    a stack of groups) waits between two Runs. }
  TTyRichRawFilter = class
  private
    FCount: Integer;                      // the needle's first characters looked for
    FAccept: QWord;                       // the bit of the last of them
    FChars: array of Cardinal;            // the distinct ones above U+00FF, sorted
    FCharMask: array of QWord;            // ... and where they are in the needle
    FLow: array[0..255] of QWord;         // characters U+0000 .. U+00FF
    FByte: array[0..255] of QWord;        // a byte of text in any of the file's code pages
    FLead: array[0..255] of Boolean;      // a lead byte in one of them
    FPair: array of QWord;                // a lead and a trail byte (lead shl 8 or trail)
    FMatchCase: Boolean;
    // the paragraph being read
    FBuf: PByte;
    FLex: TTyRtfLexer;
    FStop: PtrInt;
    FD, FT, FLeadMask, FWild: QWord;
    FLeadByte: Integer;
    FHigh: Boolean;                       // a high surrogate \uN may be waiting for its pair
    FHighVal: Cardinal;
    FStack: array of TTyRichFilterSave;
    FDepth: Integer;
    FHide: Integer;                       // > 0: inside a group passed over unread (a picture)
    FLooked, FHidden: Int64;
    function MaskOf(C: Cardinal): QWord;
  public
    { ANeedle: the needle's characters as the finder has them (folded unless AMatchCase), no
      paragraph end in it. ACodePages: the code pages the file's bytes may be in (the scan's
      TTyRtfParser.CodePageSeen; 1252 is added). }
    constructor Create(const ANeedle: array of Cardinal; AMatchCase: Boolean;
      const ACodePages: array of Integer);
    { The bytes [AStart, AStop) of ABuf - a paragraph of the file - are read next. }
    procedure Start(ABuf: PByte; AStart, AStop: PtrInt);
    { Reads on for about ABudget units (a byte lexed is one; a byte of a picture passed over is
      one sixteenth: it is only looked at for the braces), taken from ABudget. }
    function Run(var ABudget: Int64): TTyRichFilterVerdict;
    { Start and Run to the end: False only when the RTF bytes [AStart, AStop) of ABuf cannot
      read as text that holds the needle's first characters (see the unit comment). }
    function MayHold(ABuf: PByte; AStart, AStop: PtrInt): Boolean;
    { Bytes lexed, and bytes of pictures passed over without being lexed, since it was made. }
    property Looked: Int64 read FLooked;
    property Hidden: Int64 read FHidden;
  end;

  TTyRichFinder = class
  private
    FDoc: TTyRichDocument;
    FText: TTyRichText;
    FOptions: TTyRichFindOptions;
    FCodes: array of Cardinal;        // the needle, folded unless match case
    FLen: Integer;
    FParaEnds: Integer;
    FSegs: array of array of Cardinal; // by paragraph ends (FParaEnds > 0)
    FKmp: array of Integer;
    FNever: Boolean;
    FFirstChar, FLastChar: Cardinal;  // the needle's first and last characters (whole word)
    FMin, FMax: TTyRichPos;           // a match lies in [FMin, FMax]; FMax < 0: the text's end
    FNext: Integer;                   // the next paragraph to search (backward: the highest)
    FDone, FWaiting, FWaitOpen: Boolean;
    FCollect: Boolean;
    FMatchPos: TTyRichPos;
    FMatches: array of TTyRichPos;
    FMatchCount: Integer;
    FLoad: TTyRtfLoad;
    FFilter: TTyRichRawFilter;
    FUseFilter, FFilterTried, FFilterable, FFiltersMade: Boolean;
    FFilterCps: Integer;              // the scan's code pages the filter was made with
    // counts
    FParasFiltered, FParasRejected, FParasDecoded, FParasRead, FSteps: Int64;
    FRawBytes, FTextBytes: Int64;
    // the scan in progress
    FMode: Integer;                   // 0 first, 1 all, 2 last
    FScanEnd: TTyRichPos;             // matches end at or before it
    FRunPos: TTyRichPos;              // where the paragraph being read starts
    FBest: TTyRichPos;
    FStop: Boolean;
    FRing: array of Cardinal;
    { ScanWindow (a needle with paragraph ends): what is known of paragraphs FWinFirst ..
      FWinFirst + n - 1 - characters, start, the value a walk gave, the file's bytes of an
      unparsed one; and, per role, whether it can play it (-1 not known yet, 0 no, 1 yes): the
      first of a match (it ends with the first segment), a middle one (it is segment k), the
      last (it begins with the last segment); hidden (a cell merged away). }
    FWinFirst: Integer;
    FWinLen: array of Int64;
    FWinStart: array of TTyRichPos;
    FWinData: array of Pointer;
    FWinSrc, FWinBytes: array of Int64;
    FWinTail, FWinHead, FWinHidden: array of ShortInt;
    FWinMid: array of array of ShortInt;
    FWinNeed, FWinLooked: array of Boolean;
    FSegFilter: array of TTyRichRawFilter; // per segment (nil: empty, or not filterable)
    // ScanParas: where each paragraph's bytes are in the file (-1: not an unparsed one)
    FSrc, FSrcBytes: array of Int64;
    FSrcFirst: Integer;
    procedure ParseNeedle(const ANeedle: UTF8String);
    procedure SourceOf(AIndex: Integer; AData: Pointer; ASrcOffset, ASrcBytes: Int64;
      var AContinue: Boolean);
    function ScanEnd: TTyRichPos;
    function HiddenValue(AData: Pointer): Boolean;
    function FilterReady: Boolean;
    function Accept(AStart: TTyRichPos): Boolean;
    procedure ScanParas(ALo, AHi: Integer);
    procedure ScanWindow(ALo, AHi: Integer);
    procedure ExactPara(AIndex: Integer; AData: Pointer; AText: PByte; ALen: PtrInt;
      var AContinue: Boolean);
    procedure WindowPara(AIndex: Integer; AData: Pointer; AText: PByte; ALen: PtrInt;
      var AContinue: Boolean);
    procedure WindowSource(AIndex: Integer; AData: Pointer; ASrcOffset, ASrcBytes: Int64;
      var AContinue: Boolean);
    function WinRaw(I: Integer): Boolean;
    function WinMay(ASeg, I: Integer): Boolean;
    function WinTail(I: Integer): Boolean;
    function WinMid(K, I: Integer): Boolean;
    function WinHead(I: Integer): Boolean;
    function InTable(ASrc: Int64): Boolean;
    function StepForward(ABudget: Int64): TTyRichFindResult;
    function StepBackward(ABudget: Int64): TTyRichFindResult;
  public
    { A finder of ANeedle in ADoc: a match starts at or after AStart and ends at or before
      AEnd (AEnd < 0: the text's end - for a document still loading, also as it grows).
      Forward it finds the matches from AStart on, leftmost first, never overlapping; with
      rfoBackward from AEnd back, the last first. Nothing is searched before the first Step. }
    constructor Create(ADoc: TTyRichDocument; const ANeedle: UTF8String;
      AOptions: TTyRichFindOptions; AStart: TTyRichPos = 0; AEnd: TTyRichPos = -1);
    destructor Destroy; override;
    { Searches on for about ABudget characters of text (and as many bytes of a file's
      unparsed paragraphs). rfrFound: the next match is MatchPos (MatchLen characters); the
      next Step goes on after it (backward: before it). With Collect, matches are kept in
      Matches and the step goes on to its budget. rfrNotFound: no match is left. rfrMore:
      call again (Waiting: what can be searched is, and the document is still loading). }
    function Step(ABudget: Int64): TTyRichFindResult;
    { Steps to the next match or the end. A document still loading is searched as far as it
      is loaded: rfrNotFound there means none in what is loaded yet. }
    function Run: TTyRichFindResult;
    property MatchPos: TTyRichPos read FMatchPos;
    property MatchLen: Integer read FLen;
    { Every match is kept (in order, not overlapping) instead of stopping at each. }
    property Collect: Boolean read FCollect write FCollect;
    property MatchCount: Integer read FMatchCount;
    function Match(AIndex: Integer): TTyRichPos;
    { The matches kept so far are let go (Collect: a caller that took them). }
    procedure ClearMatches;
    { The needle can match nothing (empty, or it holds an object). }
    property Never: Boolean read FNever;
    property Waiting: Boolean read FWaiting;
    property Done: Boolean read FDone;
    property Options: TTyRichFindOptions read FOptions;
    { Where the search has come to (forward: the first position not searched; backward: the
      last one), for progress. }
    function Reached: TTyRichPos;
    { The raw-byte filter is used where it can be (default True; False: every unparsed
      paragraph is decoded, for a test that compares). }
    property UseFilter: Boolean read FUseFilter write FUseFilter;
    { Counts: unparsed paragraphs looked for in their bytes, those the filter ruled out, those
      decoded to be read, every paragraph read, steps; bytes of files and of text read. }
    property ParasFiltered: Int64 read FParasFiltered;
    property ParasRejected: Int64 read FParasRejected;
    property ParasDecoded: Int64 read FParasDecoded;
    property ParasRead: Int64 read FParasRead;
    property Steps: Int64 read FSteps;
    property RawBytes: Int64 read FRawBytes;
    property TextBytes: Int64 read FTextBytes;
  end;

  { Replaces matches of ALen characters by AText: at each position of APositions (in the
    order given, which must be from the last to the first, so that a replacement never moves
    a position not used yet) the characters go and AText comes in, in the format of the first
    character replaced (a paragraph's end: the format typing there gets). A match the
    document refuses to change is left as it is and counted (Skipped): one in a row that
    holds a nested table (TTyRichDocument.CanChange), one whose deletion would join across a
    cell's or a row's edge (R57: TTyRichDocument.UserRangeAllowed - also one that ends with a
    cell's last paragraph end, or with the one before a table). So the command never fails
    halfway for a refusal.
    Commands of the same ASession (any value but 0) merge into one undo step: the history
    keeps one step of a replace that ran in several turns. }
  TTyRichReplaceCommand = class(TTyRichCommand)
  private
    FSession: Int64;
    FPos: array of TTyRichPos;         // FCount of them (the arrays grow by doubling)
    FFormats: array of TTyCharFormatId;
    FCount: Integer;
    FHasFormats: Boolean;
    FLen: TTyRichPos;
    FText: UTF8String;
    FSkipped: Integer;
    FSkipCounter: PInteger;
    { What the records keep (TTyRichCommand.MemSize's part for them) and the objects they hold
      (GatherObjects'), counted once when they were made and added up as batches merge: the
      history asks both of the step at every merge, and a count over all the step's records
      each time would make a replace of n batches cost n times its size. }
    FRecBytes: Int64;
    FObjs: TTyRichObjectList;
    FObjCount: Integer;
    procedure CountRecords;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
    procedure DoUndo(ADoc: TTyRichDocument); override;
  public
    constructor Create(ASession: Int64; const APositions: array of TTyRichPos;
      ALen: TTyRichPos; const AText: UTF8String);
    function TryMerge(ANext: TTyRichCommand): Boolean; override;
    function Description: string; override;
    function MemSize: Int64; override;
    procedure GatherObjects(var AList: TTyRichObjectList; var ACount: Integer); override;
    { The replacements made (after the first run: the matches not skipped). }
    function Count: Integer;
    property Skipped: Integer read FSkipped;
    { Where the first run adds the matches it leaves (also when the command then changes
      nothing and the history does not keep it): the caller's count, good until that run. }
    property SkipCounter: PInteger read FSkipCounter write FSkipCounter;
    property Session: Int64 read FSession;
  end;

{ The caret's word rule (what a double click and Ctrl+Left / Right take): white space (a space,
  a tab, U+00A0, U+000B) and ASCII punctuation are no word (0), an object (U+FFFC) is a word by
  itself (2), every other character is a word character (1) - letters, digits, ideographs,
  marks, a byte that is no text. A paragraph's end (TyRichFindParaEnd) is no word. }
function TyRichWordClass(C: Cardinal): Integer;
{ The character as a find without rfoMatchCase compares it (see the unit comment). }
function TyRichFoldChar(C: Cardinal): Cardinal;
{ The characters of UTF-8 text as the finder reads them: a paragraph separator (CR LF, CR, LF)
  is TyRichFindParaEnd, a byte that starts no valid sequence TyRichFindRawByte plus it. }
function TyRichFindCodes(const S: RawByteString): TTyRichCodeArray;

implementation

uses
  LazUTF16, tyControls.Painter, tyControls.RichEdit.TextIO, tyControls.RichEdit.RowFormat,
  tyControls.StrConsts;

const
  CObject = $FFFC;
  CNone = $FFFFFFFE;      // no character (before the text's start)

function Max64(A, B: Int64): Int64; inline;
begin
  if A > B then Result := A else Result := B;
end;

function TyRichWordClass(C: Cardinal): Integer;
begin
  case C of
    CObject: Result := 2;
    9, 11, 32, $A0, 33..47, 58..64, 91..94, 96, 123..126, TyRichFindParaEnd, CNone: Result := 0;
  else
    Result := 1;
  end;
end;

function TyRichFoldChar(C: Cardinal): Cardinal;
begin
  if C < $80 then
  begin
    if (C >= 65) and (C <= 90) then Result := C + 32 else Result := C;
  end
  else if C = $03C2 then
    // final sigma folds to sigma (CaseFolding.txt); the lowercase table keeps it
    Result := $03C3
  else if C >= TyRichFindRawByte then
    Result := C
  else
    Result := UnicodeLowercase(C);
end;

{ The text storage's sequence rule (tyControls.RichEdit.Text's SeqLen): the length of the
  valid UTF-8 sequence at P, 1 for a byte that starts none. }
function SeqLen(P: PByte; AAvail: PtrInt): Integer; inline;
var
  b0, b1: Byte;
begin
  b0 := P^;
  if b0 < $C2 then Exit(1);
  if b0 < $E0 then
  begin
    if (AAvail >= 2) and (P[1] and $C0 = $80) then Exit(2);
    Exit(1);
  end;
  if b0 < $F0 then
  begin
    if AAvail < 3 then Exit(1);
    b1 := P[1];
    if (b1 and $C0 <> $80) or (P[2] and $C0 <> $80) then Exit(1);
    if (b0 = $E0) and (b1 < $A0) then Exit(1);
    if (b0 = $ED) and (b1 > $9F) then Exit(1);
    Exit(3);
  end;
  if b0 < $F5 then
  begin
    if AAvail < 4 then Exit(1);
    b1 := P[1];
    if (b1 and $C0 <> $80) or (P[2] and $C0 <> $80) or (P[3] and $C0 <> $80) then Exit(1);
    if (b0 = $F0) and (b1 < $90) then Exit(1);
    if (b0 = $F4) and (b1 > $8F) then Exit(1);
    Exit(4);
  end;
  Result := 1;
end;

{ The character at P (ALen its bytes, as SeqLen). }
function CodeAt(P: PByte; ALen: Integer): Cardinal; inline;
begin
  case ALen of
    2: Result := (Cardinal(P[0] and $1F) shl 6) or (P[1] and $3F);
    3: Result := (Cardinal(P[0] and $0F) shl 12) or (Cardinal(P[1] and $3F) shl 6) or
         (P[2] and $3F);
    4: Result := (Cardinal(P[0] and $07) shl 18) or (Cardinal(P[1] and $3F) shl 12) or
         (Cardinal(P[2] and $3F) shl 6) or (P[3] and $3F);
  else
    if P^ < $80 then Result := P^ else Result := TyRichFindRawByte + P^;
  end;
end;

function TyRichFindCodes(const S: RawByteString): TTyRichCodeArray;
var
  i, n, k: Integer;
  p: PByte;
begin
  Result := nil;
  SetLength(Result, Length(S));
  n := 0;
  i := 1;
  while i <= Length(S) do
  begin
    p := PByte(@S[i]);
    if p^ = 13 then
    begin
      Result[n] := TyRichFindParaEnd;
      if (i < Length(S)) and (S[i + 1] = #10) then Inc(i);
      Inc(i);
    end
    else if p^ = 10 then
    begin
      Result[n] := TyRichFindParaEnd;
      Inc(i);
    end
    else
    begin
      k := SeqLen(p, Length(S) - i + 1);
      Result[n] := CodeAt(p, k);
      Inc(i, k);
    end;
    Inc(n);
  end;
  SetLength(Result, n);
end;

{ Whole word: the character outside a match and the needle's own at that end make one word -
  both are word characters of the caret's rule (TyRichWordClass), and neither is of a script
  written without spaces, which bounds a word on both of its sides: the line breaker's set
  (TyIsCJKCodepoint - Hangul Jamo and syllables, the CJK radicals, punctuation, kana, Bopomofo,
  the ideographs of every extension, Yi, the compatibility ideographs and forms, and the
  full-width forms). So a Chinese needle is a whole word between two ideographs, and a Latin
  word inside Chinese text is bounded by them. }
function Joins(AOutside, AEdge: Cardinal): Boolean; inline;
begin
  Result := (TyRichWordClass(AOutside) = 1) and (TyRichWordClass(AEdge) = 1) and
    not TyIsCJKCodepoint(AOutside) and not TyIsCJKCodepoint(AEdge);
end;

{ ---- the raw-byte filter ---- }

constructor TTyRichRawFilter.Create(const ANeedle: array of Cardinal; AMatchCase: Boolean;
  const ACodePages: array of Integer);
var
  k, i, j, b, t: Integer;
  c: Cardinal;
  tables: array of Pointer;
  table, cls: Pointer;

  procedure AddTable(ACodePage: Integer);
  var
    tb: Pointer;
    q: Integer;
  begin
    tb := TyRichCodePageTable(ACodePage);
    if tb = nil then Exit;
    for q := 0 to High(tables) do
      if tables[q] = tb then Exit;
    SetLength(tables, Length(tables) + 1);
    tables[High(tables)] := tb;
  end;

  function Folded(AChar: Cardinal): Cardinal;
  begin
    if FMatchCase then Result := AChar else Result := TyRichFoldChar(AChar);
  end;

begin
  inherited Create;
  FMatchCase := AMatchCase;
  FCount := Length(ANeedle);
  if FCount > TyRichFindFilterChars then FCount := TyRichFindFilterChars;
  FAccept := QWord(1) shl (FCount - 1);
  FillChar(FLow, SizeOf(FLow), 0);
  for k := 0 to FCount - 1 do
  begin
    c := ANeedle[k];
    if c <= $FF then
      FLow[c] := FLow[c] or (QWord(1) shl k)
    else
    begin
      j := -1;
      for i := 0 to High(FChars) do
        if FChars[i] = c then j := i;
      if j < 0 then
      begin
        // sorted, for MaskOf's search
        j := Length(FChars);
        SetLength(FChars, j + 1);
        SetLength(FCharMask, j + 1);
        while (j > 0) and (FChars[j - 1] > c) do
        begin
          FChars[j] := FChars[j - 1];
          FCharMask[j] := FCharMask[j - 1];
          Dec(j);
        end;
        FChars[j] := c;
        FCharMask[j] := 0;
      end;
      FCharMask[j] := FCharMask[j] or (QWord(1) shl k);
    end;
  end;
  { The code pages the reader can decode this file's bytes with (UpdateDecoder): every one the
    scan met - each font entry's of every font table, each \ansicpg - and 1252 (a code page it
    has no table for). }
  tables := nil;
  for i := 0 to High(ACodePages) do
    if ACodePages[i] > 0 then AddTable(ACodePages[i]);
  AddTable(1252);
  // one byte: itself (ASCII), its character in a code page, '?' (a byte no code page has, a
  // lead byte left alone), and the Symbol charset's U+F000 + b
  for b := 0 to 255 do
  begin
    FByte[b] := 0;
    FLead[b] := False;
    if b < $80 then FByte[b] := MaskOf(Folded(b))
    else FByte[b] := MaskOf(Ord('?'));
    if b > $20 then FByte[b] := FByte[b] or MaskOf(Folded($F000 + Cardinal(b)));
  end;
  for t := 0 to High(tables) do
  begin
    table := tables[t];
    cls := TyRichCodePageClasses(table);
    for b := $80 to 255 do
    begin
      if (cls <> nil) and (PByte(cls)[b] = 2) then
      begin
        FLead[b] := True;
        Continue;
      end;
      c := TyRichCodePageChar(table, b, -1);
      if c <> 0 then FByte[b] := FByte[b] or MaskOf(Folded(c));
    end;
  end;
  // two bytes: a pair of a double-byte code page
  for t := 0 to High(tables) do
  begin
    table := tables[t];
    cls := TyRichCodePageClasses(table);
    if cls = nil then Continue;
    if FPair = nil then
    begin
      SetLength(FPair, 65536);
      FillChar(FPair[0], 65536 * SizeOf(QWord), 0);
    end;
    for b := $80 to 255 do
    begin
      if PByte(cls)[b] <> 2 then Continue;
      for i := 0 to 255 do
      begin
        c := TyRichCodePageChar(table, b, i);
        if c <> 0 then FPair[(b shl 8) or i] := FPair[(b shl 8) or i] or MaskOf(Folded(c));
      end;
    end;
  end;
end;

function TTyRichRawFilter.MaskOf(C: Cardinal): QWord;
var
  lo, hi, mid: Integer;
begin
  if C <= $FF then Exit(FLow[C]);
  lo := 0;
  hi := High(FChars);
  while lo <= hi do
  begin
    mid := (lo + hi) div 2;
    if FChars[mid] = C then Exit(FCharMask[mid]);
    if FChars[mid] < C then lo := mid + 1 else hi := mid - 1;
  end;
  Result := 0;
end;

procedure TTyRichRawFilter.Start(ABuf: PByte; AStart, AStop: PtrInt);
begin
  FBuf := ABuf;
  FLex.Init(ABuf, AStart, AStop);
  FStop := AStop;
  FD := 0;
  FT := 0;
  FLeadMask := 0;
  FWild := 0;
  FLeadByte := -1;
  FHigh := False;
  FHighVal := 0;
  FDepth := 0;
  FHide := 0;
end;

{ The needle's first characters looked for in the bytes as the reader may read them - a
  Shift-And automaton (bit k: the needle's first k + 1 characters end here) over a reading
  that takes every way the reader can go, by the reader's own rules (RtfRead's TyRtfByteRole,
  TyRtfUnicodeOf, TyRtfWordChar, TyRtfSymbolChar; its lexer):
  - a text byte or a \'xx is a byte: its character in any of the file's code pages, '?', or
    the Symbol charset's; a lead byte and the byte after it (also after control words and
    groups between them, as the reader joins them) a pair of any double-byte code page. A
    byte the reader drops (NUL, LF, CR, the other control bytes but the tab) is nothing -
    or a fallback a \uN skips;
  - \uN is its character (a high and a low surrogate: the one character they make); \u
    without a number makes none. The bytes, \'xx and control symbols after it up to the next
    control word may each be a fallback it skips, or text (any \ucN, also one from before
    the paragraph's bytes);
  - the control words that are characters (\tab, \emdash, ...) and the control symbols that
    are (a tilde, an underscore, an escaped backslash or brace) are those characters; every
    other control word and symbol is nothing;
  - every group is read through or passed over as if it were not there - whatever the reader
    does with a destination (a field, a list's marker are no text of the paragraph; \upr's
    \ud is); a picture's group (\pict) is passed over unread, by its braces alone;
  - a word that changes how the file decodes (a font table, an \ansicpg) inside the bytes:
    the bytes may hold anything (fvMay).
  So the answer is fvCannot only where no reading the reader can make holds the characters. }
function TTyRichRawFilter.Run(var ABudget: Int64): TTyRichFilterVerdict;
var
  tok, w: TTyRtfToken;
  peek: TTyRtfLexer;
  d, t, lead, wild, nd: QWord;
  leadByte: Integer;
  p, q, p0: PtrInt;
  b: Byte;
  c: Cardinal;
  isU, got: Boolean;
  buf: PByte;
  used: Int64;

  // a character the reader makes, not from a byte (\uN, a control word, a symbol)
  procedure CharUnit(AChar: Cardinal);
  begin
    if not FMatchCase then AChar := TyRichFoldChar(AChar);
    d := (((d shl 1) or 1) and MaskOf(AChar)) or t;
    lead := 0;
    wild := 0;
    leadByte := -1;
  end;

  procedure ByteUnit(AByte: Byte);
  begin
    if TyRtfByteRole(AByte) <> rbrText then
    begin
      { Read as nothing (a lead byte waiting waits on, or reads as the '?' its own reading
        holds already), or a fallback a \uN skips. }
      d := d or t;
      Exit;
    end;
    nd := ((d shl 1) or 1) and FByte[AByte];
    if (lead <> 0) and (FPair <> nil) then
      nd := nd or (lead and FPair[(leadByte shl 8) or AByte]);
    nd := nd or wild or t;
    if FLead[AByte] then
    begin
      lead := (d shl 1) or 1;
      leadByte := AByte;
    end
    else
    begin
      lead := 0;
      leadByte := -1;
    end;
    wild := 0;
    d := nd;
  end;

begin
  Result := fvMay;
  if FCount <= 0 then Exit;
  buf := FBuf;
  d := FD;
  t := FT;
  lead := FLeadMask;
  wild := FWild;
  leadByte := FLeadByte;
  used := 0;
  try
    while True do
    begin
      if used >= ABudget then Exit(fvMore);
      if FHide > 0 then
      begin
        { A group that holds no text the reader takes: only its braces are looked for (an
          escaped one, and a \bin's data, are the lexer's to tell). }
        p := FLex.Position;
        p0 := p;
        if ABudget - used > (FStop - p) div 16 + 1 then q := FStop
        else q := p + (ABudget - used) * 16 + 16;
        if q > FStop then q := FStop;
        while (p < q) and (FHide > 0) do
        begin
          b := buf[p];
          if b = Ord('{') then
            Inc(FHide)
          else if b = Ord('}') then
            Dec(FHide)
          else if b = Ord('\') then
          begin
            peek := FLex;
            peek.Position := p;
            if peek.Next(tok) then p := tok.Stop else p := FStop;
            Continue;
          end;
          Inc(p);
        end;
        if p > FStop then p := FStop;
        FLex.Position := p;
        Inc(FHidden, p - p0);
        Inc(used, (p - p0) div 16 + 1);
        if (FHide > 0) and (p >= FStop) then Exit(fvCannot);
        Continue;
      end;
      if not FLex.Next(tok) then Exit(fvCannot);
      case tok.Kind of
        rtkGroupStart:
          begin
            Inc(used);
            Inc(FLooked);
            peek := FLex;
            got := peek.Next(w);
            if got and (w.Kind = rtkSymbol) and (w.Value = Ord('*')) then got := peek.Next(w);
            if got and (w.Kind = rtkWord) and TyRtfWordHidesGroup(buf, w.NameStart, w.NameLen) then
              FHide := 1
            else
            begin
              if FDepth = Length(FStack) then SetLength(FStack, FDepth * 2 + 8);
              FStack[FDepth].D := d;
              FStack[FDepth].T := t;
              FStack[FDepth].Lead := lead;
              FStack[FDepth].LeadByte := leadByte;
              FStack[FDepth].Wild := wild;
              Inc(FDepth);
            end;
          end;
        rtkGroupEnd:
          begin
            Inc(used);
            Inc(FLooked);
            if FDepth > 0 then
            begin
              Dec(FDepth);
              // read through, or passed over
              d := d or FStack[FDepth].D;
              t := t or FStack[FDepth].T;
              if FStack[FDepth].Lead <> 0 then
                if (lead = 0) or (leadByte = FStack[FDepth].LeadByte) then
                begin
                  lead := lead or FStack[FDepth].Lead;
                  leadByte := FStack[FDepth].LeadByte;
                end
                else
                  // two lead bytes may be waiting: whatever follows may pair with either
                  wild := wild or FStack[FDepth].Lead;
              wild := wild or FStack[FDepth].Wild;
            end;
          end;
        rtkWord:
          begin
            Inc(used, tok.Stop - tok.Start);
            Inc(FLooked, tok.Stop - tok.Start);
            // the code pages may not be the ones the filter was made with
            if TyRtfWordSetsCodePages(buf, tok.NameStart, tok.NameLen) then Exit(fvMay);
            c := TyRtfWordChar(buf, tok.NameStart, tok.NameLen, isU);
            // a word ends what a \uN before it was skipping
            t := 0;
            if isU then
            begin
              c := TyRtfUnicodeOf(tok.Param);
              if (c >= $D800) and (c <= $DBFF) then
              begin
                // the first half of a pair: nothing yet
                FHigh := True;
                FHighVal := c;
              end
              else
              begin
                if (c >= $DC00) and (c <= $DFFF) then
                begin
                  if FHigh then c := $10000 + ((FHighVal - $D800) shl 10) + (c - $DC00)
                  else c := $FFFD;
                end;
                FHigh := False;
                // (0, LF, CR: no text)
                if (c <> 0) and (c <> 10) and (c <> 13) then CharUnit(c);
              end;
              // the fallback after it may be skipped
              t := d;
            end
            else if c <> 0 then
              CharUnit(c);
          end;
        rtkSymbol:
          begin
            Inc(used, tok.Stop - tok.Start);
            Inc(FLooked, tok.Stop - tok.Start);
            c := TyRtfSymbolChar(tok.Value);
            if c <> 0 then CharUnit(c);
          end;
        rtkHex:
          begin
            Inc(used, tok.Stop - tok.Start);
            Inc(FLooked, tok.Stop - tok.Start);
            if tok.Value >= 0 then ByteUnit(tok.Value) else d := d or t;
          end;
        rtkText:
          begin
            // a long run of text is read in pieces: the lexer goes on from inside it
            q := tok.Stop;
            if q - tok.Start > ABudget - used then
            begin
              q := tok.Start + (ABudget - used);
              if q <= tok.Start then q := tok.Start + 1;
              FLex.Position := q;
            end;
            Inc(used, q - tok.Start);
            Inc(FLooked, q - tok.Start);
            for p := tok.Start to q - 1 do
            begin
              ByteUnit(buf[p]);
              if d and FAccept <> 0 then Exit(fvMay);
            end;
          end;
        rtkBin:
          begin
            Inc(used, tok.DataStart - tok.Start);
            Inc(FLooked, tok.DataStart - tok.Start);
            Inc(FHidden, tok.Stop - tok.DataStart);
            d := d or t;
          end;
      end;
      if d and FAccept <> 0 then Exit(fvMay);
    end;
  finally
    FD := d;
    FT := t;
    FLeadMask := lead;
    FWild := wild;
    FLeadByte := leadByte;
    Dec(ABudget, used);
  end;
end;

function TTyRichRawFilter.MayHold(ABuf: PByte; AStart, AStop: PtrInt): Boolean;
var
  budget: Int64;
begin
  Start(ABuf, AStart, AStop);
  budget := High(Int64) div 4;
  Result := Run(budget) <> fvCannot;
end;

{ ---- TTyRichFinder ---- }

constructor TTyRichFinder.Create(ADoc: TTyRichDocument; const ANeedle: UTF8String;
  AOptions: TTyRichFindOptions; AStart: TTyRichPos; AEnd: TTyRichPos);
begin
  inherited Create;
  FDoc := ADoc;
  FText := ADoc.Text;
  FOptions := AOptions;
  FUseFilter := True;
  if AStart < 0 then AStart := 0;
  FMin := AStart;
  FMax := AEnd;
  FNext := -1;
  FMatchPos := -1;
  ParseNeedle(ANeedle);
  if (FMax >= 0) and (FMax - FMin < FLen) then FNever := True;
end;

destructor TTyRichFinder.Destroy;
var
  k: Integer;
begin
  FFilter.Free;
  for k := 0 to High(FSegFilter) do FSegFilter[k].Free;
  inherited Destroy;
end;

procedure TTyRichFinder.ParseNeedle(const ANeedle: UTF8String);
var
  i, k, s: Integer;
  raw: TTyRichCodeArray;
begin
  raw := TyRichFindCodes(ANeedle);
  FLen := Length(raw);
  SetLength(FCodes, FLen);
  FParaEnds := 0;
  FNever := FLen = 0;
  for i := 0 to FLen - 1 do
  begin
    if raw[i] = CObject then FNever := True;
    if raw[i] = TyRichFindParaEnd then Inc(FParaEnds);
    if rfoMatchCase in FOptions then FCodes[i] := raw[i]
    else if raw[i] = TyRichFindParaEnd then FCodes[i] := raw[i]
    else FCodes[i] := TyRichFoldChar(raw[i]);
  end;
  if FNever then Exit;
  FFirstChar := raw[0];
  FLastChar := raw[FLen - 1];
  if FParaEnds = 0 then
  begin
    // the failure function of the needle (Knuth-Morris-Pratt)
    SetLength(FKmp, FLen + 1);
    FKmp[0] := -1;
    k := -1;
    for i := 0 to FLen - 1 do
    begin
      while (k >= 0) and (FCodes[k] <> FCodes[i]) do k := FKmp[k];
      Inc(k);
      if (i + 1 < FLen) and (FCodes[i + 1] = FCodes[k]) then FKmp[i + 1] := FKmp[k]
      else FKmp[i + 1] := k;
    end;
    SetLength(FRing, FLen + 1);
  end
  else
  begin
    SetLength(FSegs, FParaEnds + 1);
    s := 0;
    for i := 0 to FLen - 1 do
      if FCodes[i] = TyRichFindParaEnd then
        Inc(s)
      else
      begin
        k := Length(FSegs[s]);
        SetLength(FSegs[s], k + 1);
        FSegs[s][k] := FCodes[i];
      end;
    SetLength(FRing, Length(FSegs[0]) + 1);
  end;
end;

function TTyRichFinder.Match(AIndex: Integer): TTyRichPos;
begin
  Result := FMatches[AIndex];
end;

procedure TTyRichFinder.ClearMatches;
begin
  FMatchCount := 0;
end;

function TTyRichFinder.Reached: TTyRichPos;
begin
  if FDone then
  begin
    if rfoBackward in FOptions then Exit(FMin);
    Exit(ScanEnd);
  end;
  if FNext < 0 then
  begin
    if rfoBackward in FOptions then Exit(ScanEnd);
    Exit(FMin);
  end;
  if FNext >= FText.ParaCount then Exit(FText.Length);
  Result := FText.ParaStart(FNext);
  if rfoBackward in FOptions then Result := Result + FText.ParaLength(FNext);
end;

function TTyRichFinder.ScanEnd: TTyRichPos;
begin
  Result := FText.Length;
  if (FMax >= 0) and (FMax < Result) then Result := FMax;
end;

function TTyRichFinder.FilterReady: Boolean;
var
  cps: array of Integer;
  i, k: Integer;
  ok: Boolean;
begin
  if not FFilterTried then
  begin
    FFilterTried := True;
    FLoad := TyRichRtfLoadOf(FDoc);
    FFilterable := FLoad <> nil;
  end;
  { Made with every code page the scan has met so far, and made again when it met another (a
    file still loading, a font table given again in the body). }
  if FFilterable and (not FFiltersMade or (FFilterCps <> FLoad.Scan.CodePageCount)) then
  begin
    FreeAndNil(FFilter);
    for k := 0 to High(FSegFilter) do FreeAndNil(FSegFilter[k]);
    FFiltersMade := True;
    FFilterCps := FLoad.Scan.CodePageCount;
    cps := nil;
    SetLength(cps, FFilterCps);
    for i := 0 to FFilterCps - 1 do cps[i] := FLoad.Scan.CodePageSeen(i);
    if FParaEnds = 0 then
    begin
      // what the filter cannot say: U+FFFD, which the reader makes of many things
      ok := True;
      for i := 0 to FLen - 1 do
        if FCodes[i] = $FFFD then ok := False;
      if ok then FFilter := TTyRichRawFilter.Create(FCodes, rfoMatchCase in FOptions, cps);
    end
    else
    begin
      // each segment's text, for the paragraphs that must hold it
      SetLength(FSegFilter, FParaEnds + 1);
      for k := 0 to FParaEnds do
      begin
        ok := Length(FSegs[k]) > 0;
        for i := 0 to High(FSegs[k]) do
          if FSegs[k][i] = $FFFD then ok := False;
        if ok then FSegFilter[k] := TTyRichRawFilter.Create(FSegs[k], rfoMatchCase in FOptions, cps);
      end;
    end;
  end;
  Result := FUseFilter and FFilterable;
end;
function TTyRichFinder.HiddenValue(AData: Pointer): Boolean;
var
  fmt: TTyParaFormatId;
  runs: TTyRunArray;
  cell: TTyRichCell;
  disp: TTyRowDisplay;
begin
  Result := False;
  if (AData = nil) or not FDoc.ReadValue(AData, fmt, runs, cell) or (cell = nil) then Exit;
  if (cell.Index <= 0) or (cell.Row = nil) or (cell.Row.RawFormat = '') then Exit;
  // the layout's rule (TTyRowLayout): a cell merged into the one before it shows nothing
  disp := TyRtfRowDisplay(cell.Row.RawFormat);
  Result := (cell.Index < Length(disp.Cells)) and (disp.Cells[cell.Index].HMerge = rcmContinue);
end;

{ A match from AStart (its whole-word test passed): taken by the scan's mode. True: the walk
  stops here. }
function TTyRichFinder.Accept(AStart: TTyRichPos): Boolean;
begin
  Result := False;
  if (AStart < FMin) or (AStart + FLen > FScanEnd) then Exit;
  case FMode of
    0:
      begin
        FBest := AStart;
        FStop := True;
        Result := True;
      end;
    1:
      begin
        if FMatchCount = Length(FMatches) then SetLength(FMatches, FMatchCount * 2 + 64);
        FMatches[FMatchCount] := AStart;
        Inc(FMatchCount);
        // the next one begins after this one
        FMin := AStart + FLen;
      end;
  else
    if AStart > FBest then FBest := AStart;
  end;
end;

procedure TTyRichFinder.ExactPara(AIndex: Integer; AData: Pointer; AText: PByte; ALen: PtrInt;
  var AContinue: Boolean);
var
  p, stop: PByte;
  k, n, ringN: Integer;
  code, prev: Cardinal;
  pos, pending: Int64;
  matchCase, whole: Boolean;
begin
  Inc(FParasRead);
  Inc(FTextBytes, ALen);
  p := AText;
  stop := AText + ALen;
  pos := 0;
  if HiddenValue(AData) then
  begin
    // not there for a find: only its length counts
    while p < stop do
    begin
      if p^ < $80 then Inc(p) else Inc(p, SeqLen(p, stop - p));
      Inc(pos);
    end;
    FRunPos := FRunPos + pos + 1;
    Exit;
  end;
  matchCase := rfoMatchCase in FOptions;
  whole := rfoWholeWord in FOptions;
  ringN := FLen + 1;
  k := 0;
  pending := -1;
  while p < stop do
  begin
    if p^ < $80 then
    begin
      code := p^;
      Inc(p);
    end
    else
    begin
      n := SeqLen(p, stop - p);
      code := CodeAt(p, n);
      Inc(p, n);
    end;
    if pending >= 0 then
    begin
      // the character after a match: a word goes on past its end?
      if not Joins(code, FLastChar) then
        if Accept(FRunPos + pending) then
        begin
          AContinue := False;
          Exit;
        end;
      pending := -1;
    end;
    if whole then FRing[pos mod ringN] := code;
    if not matchCase then code := TyRichFoldChar(code);
    while (k >= 0) and (FCodes[k] <> code) do k := FKmp[k];
    Inc(k);
    if k = FLen then
    begin
      // a match of the characters [pos - FLen + 1, pos]
      if not whole then
      begin
        if Accept(FRunPos + pos - FLen + 1) then
        begin
          AContinue := False;
          Exit;
        end;
      end
      else
      begin
        if pos - FLen >= 0 then prev := FRing[(pos - FLen) mod ringN] else prev := CNone;
        if not Joins(prev, FFirstChar) then
          pending := pos - FLen + 1;
      end;
      k := FKmp[k];
    end;
    Inc(pos);
  end;
  // the paragraph's end is no word
  if (pending >= 0) and Accept(FRunPos + pending) then
  begin
    AContinue := False;
    Exit;
  end;
  FRunPos := FRunPos + pos + 1;
end;

{ Paragraphs ALo .. AHi, for a needle with no paragraph end: unparsed ones of a file looked for
  in their bytes first, the others (and those that may hold it) read, in runs. }
procedure TTyRichFinder.SourceOf(AIndex: Integer; AData: Pointer; ASrcOffset, ASrcBytes: Int64;
  var AContinue: Boolean);
var
  k: Integer;
begin
  k := AIndex - FSrcFirst;
  if k > High(FSrc) then
  begin
    AContinue := False;
    Exit;
  end;
  FSrc[k] := ASrcOffset;
  FSrcBytes[k] := ASrcBytes;
  if k = High(FSrc) then AContinue := False;
end;

procedure TTyRichFinder.ScanParas(ALo, AHi: Integer);
var
  i, a, n: Integer;
  src, bytes: Int64;
  pass: array of Boolean;
  filter: Boolean;
  buf: PByte;
begin
  n := AHi - ALo + 1;
  if n <= 0 then Exit;
  pass := nil;
  SetLength(pass, n);
  filter := FilterReady and (FFilter <> nil);
  buf := nil;
  if filter then
  begin
    buf := PByte(Pointer(FLoad.Bytes));
    // where the paragraphs' bytes are: one walk, not a lookup each
    SetLength(FSrc, n);
    SetLength(FSrcBytes, n);
    for i := 0 to n - 1 do FSrc[i] := -1;
    FSrcFirst := ALo;
    FText.WalkParas(ALo, @SourceOf);
  end;
  for i := 0 to n - 1 do
  begin
    pass[i] := True;
    if not filter then Continue;
    src := FSrc[i];
    bytes := FSrcBytes[i];
    if (src >= 0) and not FText.IsDecoded(src) and (bytes > 0) and
      (src + bytes <= Length(FLoad.Bytes)) then
    begin
      Inc(FParasFiltered);
      Inc(FRawBytes, bytes);
      if not FFilter.MayHold(buf, src, src + bytes) then
      begin
        pass[i] := False;
        Inc(FParasRejected);
      end
      else
        Inc(FParasDecoded);
    end;
  end;
  i := 0;
  while (i < n) and not FStop do
  begin
    if not pass[i] then
    begin
      Inc(i);
      Continue;
    end;
    a := i;
    while (i < n) and pass[i] do Inc(i);
    FRunPos := FText.ParaStart(ALo + a);
    FText.WalkParaTexts(ALo + a, ALo + i - 1, @ExactPara, True);
  end;
end;

{ A needle with paragraph ends, paragraph AIndex read: what it can be of a match, from its
  text - the first paragraph (it ends with the first segment, no word going on through its
  start), a middle one (it is segment k), the last (it begins with the last segment, no word
  going on past it) - and whether it is a cell merged away. }
procedure TTyRichFinder.WindowPara(AIndex: Integer; AData: Pointer; AText: PByte; ALen: PtrInt;
  var AContinue: Boolean);
var
  i, s, k, j, n, ringN, last: Integer;
  p, stop: PByte;
  code, prev: Cardinal;
  pos: Int64;
  matchCase, whole, ok: Boolean;
  seg: array of Cardinal;
  codes: array of Cardinal;
begin
  Inc(FParasRead);
  Inc(FTextBytes, ALen);
  i := AIndex - FWinFirst;
  matchCase := rfoMatchCase in FOptions;
  whole := rfoWholeWord in FOptions;
  if HiddenValue(AData) then FWinHidden[i] := 1 else FWinHidden[i] := 0;
  // a head as long as the last segment and the one after it are kept, and a tail as long as
  // the first segment and the one before it (FRing); a middle one is kept while it may equal one
  last := Length(FSegs[FParaEnds]);
  codes := nil;
  SetLength(codes, last + 1);
  ringN := Length(FRing);
  n := 0;
  for s := 1 to FParaEnds - 1 do
    if Length(FSegs[s]) > n then n := Length(FSegs[s]);
  seg := nil;
  SetLength(seg, n);
  p := AText;
  stop := AText + ALen;
  pos := 0;
  while p < stop do
  begin
    if p^ < $80 then
    begin
      code := p^;
      Inc(p);
    end
    else
    begin
      k := SeqLen(p, stop - p);
      code := CodeAt(p, k);
      Inc(p, k);
    end;
    if not matchCase then code := TyRichFoldChar(code);
    if pos <= last then codes[pos] := code;
    if pos < n then seg[pos] := code;
    FRing[pos mod ringN] := code;
    Inc(pos);
  end;
  s := Length(FSegs[0]);
  ok := pos >= s;
  j := 0;
  while ok and (j < s) do
  begin
    ok := FRing[(pos - s + j) mod ringN] = FSegs[0][j];
    Inc(j);
  end;
  if ok and whole and (s > 0) then
  begin
    if pos - s - 1 >= 0 then prev := FRing[(pos - s - 1) mod ringN] else prev := CNone;
    ok := not Joins(prev, FFirstChar);
  end;
  FWinTail[i] := Ord(ok);
  for k := 1 to FParaEnds - 1 do
  begin
    ok := pos = Length(FSegs[k]);
    j := 0;
    while ok and (j < pos) do
    begin
      ok := seg[j] = FSegs[k][j];
      Inc(j);
    end;
    FWinMid[k][i] := Ord(ok);
  end;
  ok := pos >= last;
  j := 0;
  while ok and (j < last) do
  begin
    ok := codes[j] = FSegs[FParaEnds][j];
    Inc(j);
  end;
  if ok and whole and (last > 0) and (pos > last) then
    ok := not Joins(codes[last], FLastChar);
  FWinHead[i] := Ord(ok);
  if FWinLooked[i] then
  begin
    // looked at in its bytes, and read
    FWinLooked[i] := False;
    Inc(FParasDecoded);
  end;
end;

procedure TTyRichFinder.WindowSource(AIndex: Integer; AData: Pointer; ASrcOffset,
  ASrcBytes: Int64; var AContinue: Boolean);
var
  i: Integer;
begin
  i := AIndex - FWinFirst;
  if i > High(FWinLen) then
  begin
    AContinue := False;
    Exit;
  end;
  FWinData[i] := AData;
  FWinSrc[i] := ASrcOffset;
  FWinBytes[i] := ASrcBytes;
  if i = High(FWinLen) then AContinue := False;
end;

{ Paragraph I of the window is one the file still has as its bytes, unparsed: a filter can
  look at them. }
function TTyRichFinder.WinRaw(I: Integer): Boolean;
var
  src: Int64;
begin
  src := FWinSrc[I];
  Result := FUseFilter and FFilterable and (src >= 0) and (FWinBytes[I] > 0) and
    not FText.IsDecoded(src) and (src + FWinBytes[I] <= Length(FLoad.Bytes));
end;

{ May paragraph I's bytes hold segment ASeg (True also where there is no filter for it)? }
function TTyRichFinder.WinMay(ASeg, I: Integer): Boolean;
begin
  if (ASeg > High(FSegFilter)) or (FSegFilter[ASeg] = nil) or not WinRaw(I) then Exit(True);
  if not FWinLooked[I] then
  begin
    FWinLooked[I] := True;
    Inc(FParasFiltered);
    Inc(FRawBytes, FWinBytes[I]);
  end;
  Result := FSegFilter[ASeg].MayHold(PByte(Pointer(FLoad.Bytes)), FWinSrc[I], FWinSrc[I] + FWinBytes[I]);
end;

{ The roles: 1 it plays it (known from its text, or from its length alone), 0 it cannot, 2 it
  may (its text not read yet); asked once, kept. }
function TTyRichFinder.WinTail(I: Integer): Boolean;
var
  s: Integer;
begin
  if FWinTail[I] < 0 then
  begin
    s := Length(FSegs[0]);
    if s = 0 then FWinTail[I] := 1
    else if FWinLen[I] < s then FWinTail[I] := 0
    else if WinMay(0, I) then FWinTail[I] := 2
    else FWinTail[I] := 0;
  end;
  Result := FWinTail[I] <> 0;
end;

function TTyRichFinder.WinMid(K, I: Integer): Boolean;
var
  s: Integer;
begin
  if FWinMid[K][I] < 0 then
  begin
    s := Length(FSegs[K]);
    // a middle paragraph is the segment, whole: its length says much
    if FWinLen[I] <> s then FWinMid[K][I] := 0
    else if s = 0 then FWinMid[K][I] := 1
    else if WinMay(K, I) then FWinMid[K][I] := 2
    else FWinMid[K][I] := 0;
  end;
  Result := FWinMid[K][I] <> 0;
end;

function TTyRichFinder.WinHead(I: Integer): Boolean;
var
  s: Integer;
begin
  if FWinHead[I] < 0 then
  begin
    s := Length(FSegs[FParaEnds]);
    if s = 0 then FWinHead[I] := 1
    else if FWinLen[I] < s then FWinHead[I] := 0
    else if WinMay(FParaEnds, I) then FWinHead[I] := 2
    else FWinHead[I] := 0;
  end;
  Result := FWinHead[I] <> 0;
end;

{ The file's bytes at ASrc are inside a table (the scan's extents, in the order of the file):
  a paragraph there may be a cell merged away, which only its value tells. }
function TTyRichFinder.InTable(ASrc: Int64): Boolean;
var
  lo, hi, mid: Integer;
  e: TTyRtfTableExtent;
begin
  Result := False;
  if FLoad = nil then Exit;
  lo := 0;
  hi := FLoad.Scan.TableExtentCount - 1;
  // the last extent that starts at or before ASrc
  while lo <= hi do
  begin
    mid := (lo + hi) div 2;
    if FLoad.Scan.TableExtent(mid).Start <= ASrc then lo := mid + 1 else hi := mid - 1;
  end;
  if hi < 0 then Exit;
  e := FLoad.Scan.TableExtent(hi);
  Result := (e.Stop < 0) or (ASrc < e.Stop);
end;

{ Matches starting in paragraphs ALo .. AHi of a needle with paragraph ends. What a paragraph
  can be of a match is first asked of what costs nothing - its length (a middle paragraph is a
  segment whole: two paragraph ends in a row are an empty paragraph), its value when it has
  one, the file's tables (a paragraph outside them is no cell merged away) - and of the bytes
  of one never parsed, through a filter for the segment it would hold; only the paragraphs of
  a match that may be there are read. }
procedure TTyRichFinder.ScanWindow(ALo, AHi: Integer);
var
  last, n, i, j, k, a: Integer;
  pos: TTyRichPos;
  ok: Boolean;
begin
  last := AHi + FParaEnds;
  if last > FText.ParaCount - 1 then last := FText.ParaCount - 1;
  if last - ALo < FParaEnds then Exit;
  if AHi > last - FParaEnds then AHi := last - FParaEnds;
  n := last - ALo + 1;
  FWinFirst := ALo;
  SetLength(FWinLen, n);
  SetLength(FWinStart, n);
  SetLength(FWinData, n);
  SetLength(FWinSrc, n);
  SetLength(FWinBytes, n);
  SetLength(FWinTail, n);
  SetLength(FWinHead, n);
  SetLength(FWinHidden, n);
  SetLength(FWinNeed, n);
  SetLength(FWinLooked, n);
  SetLength(FWinMid, FParaEnds + 1);
  for k := 1 to FParaEnds - 1 do SetLength(FWinMid[k], n);
  pos := FText.ParaStart(ALo);
  for i := 0 to n - 1 do
  begin
    FWinStart[i] := pos;
    FWinLen[i] := FText.ParaLength(ALo + i);
    pos := pos + FWinLen[i] + 1;
    FWinSrc[i] := -1;
    FWinBytes[i] := 0;
    FWinData[i] := nil;
    FWinTail[i] := -1;
    FWinHead[i] := -1;
    FWinHidden[i] := -1;
    FWinNeed[i] := False;
    FWinLooked[i] := False;
    for k := 1 to FParaEnds - 1 do FWinMid[k][i] := -1;
  end;
  FilterReady;
  FText.WalkParas(ALo, @WindowSource);
  // merged away or not, known without the text: from a value, or outside the file's tables
  for i := 0 to n - 1 do
    if (FWinData[i] <> nil) or (FLoad = nil) then
      FWinHidden[i] := Ord(HiddenValue(FWinData[i]))
    else if (FWinSrc[i] >= 0) and not InTable(FWinSrc[i]) then
      FWinHidden[i] := 0;
  // the matches that may be there: their paragraphs are read
  for j := 0 to AHi - ALo do
  begin
    ok := (FWinHidden[j] <> 1) and WinTail(j);
    k := 1;
    while ok and (k < FParaEnds) do
    begin
      ok := (FWinHidden[j + k] <> 1) and WinMid(k, j + k);
      Inc(k);
    end;
    if ok then
      ok := ((Length(FSegs[FParaEnds]) = 0) or (FWinHidden[j + FParaEnds] <> 1)) and
        WinHead(j + FParaEnds);
    if not ok then Continue;
    if (FWinTail[j] = 2) or (FWinHidden[j] < 0) then FWinNeed[j] := True;
    for k := 1 to FParaEnds - 1 do
      if (FWinMid[k][j + k] = 2) or (FWinHidden[j + k] < 0) then FWinNeed[j + k] := True;
    i := j + FParaEnds;
    if (FWinHead[i] = 2) or ((Length(FSegs[FParaEnds]) > 0) and (FWinHidden[i] < 0)) then
      FWinNeed[i] := True;
  end;
  // read in runs (a value of the moment for one never parsed)
  i := 0;
  while i < n do
  begin
    if not FWinNeed[i] then
    begin
      Inc(i);
      Continue;
    end;
    a := i;
    while (i < n) and FWinNeed[i] do Inc(i);
    FText.WalkParaTexts(ALo + a, ALo + i - 1, @WindowPara, True);
  end;
  // (a paragraph whose bytes were looked at and that was not read: ruled out)
  for i := 0 to n - 1 do
    if FWinLooked[i] then Inc(FParasRejected);
  // the matches, in order
  for j := 0 to AHi - ALo do
  begin
    ok := (FWinTail[j] = 1) and (FWinHidden[j] = 0);
    k := 1;
    while ok and (k < FParaEnds) do
    begin
      ok := (FWinMid[k][j + k] = 1) and (FWinHidden[j + k] = 0);
      Inc(k);
    end;
    i := j + FParaEnds;
    if ok then
      ok := (FWinHead[i] = 1) and ((Length(FSegs[FParaEnds]) = 0) or (FWinHidden[i] = 0));
    if ok and Accept(FWinStart[j] + FWinLen[j] - Length(FSegs[0])) then Exit;
  end;
end;
function TTyRichFinder.StepForward(ABudget: Int64): TTyRichFindResult;
var
  lo, hi, lastPara, count: Integer;
  limit, endPos: TTyRichPos;
  open: Boolean;
begin
  endPos := ScanEnd;
  count := FText.ParaCount;
  // a needle with paragraph ends: a match starts that many paragraphs before its end at most
  lastPara := FText.ParaOfPos(endPos) - FParaEnds;
  { A document still loading, searched to its end as it grows: its last paragraph is the one
    the load goes on from (it may still be the empty one appended last), so it waits - and the
    paragraphs a needle with paragraph ends would reach into it from. }
  open := (FMax < 0) and FDoc.Loading and FWaitOpen;
  if open then Dec(lastPara);
  if FNext < 0 then FNext := FText.ParaOfPos(FMin);
  if FNext > lastPara then
  begin
    if open then
    begin
      FWaiting := True;
      Exit(rfrMore);
    end;
    FDone := True;
    Exit(rfrNotFound);
  end;
  FWaiting := False;
  lo := FNext;
  limit := FText.ParaStart(lo) + Max64(ABudget, 1);
  if limit > endPos then limit := endPos;
  hi := FText.ParaOfPos(limit);
  if hi > lastPara then hi := lastPara;
  if hi < lo then hi := lo;
  if hi >= count then hi := count - 1;
  FScanEnd := endPos;
  if FCollect then FMode := 1 else FMode := 0;
  FStop := False;
  FBest := -1;
  if FParaEnds = 0 then ScanParas(lo, hi) else ScanWindow(lo, hi);
  if FStop then
  begin
    FMatchPos := FBest;
    FMin := FBest + FLen;
    FNext := FText.ParaOfPos(FBest);
    Exit(rfrFound);
  end;
  FNext := hi + 1;
  if FNext > lastPara then
  begin
    if open then
    begin
      FWaiting := True;
      Exit(rfrMore);
    end;
    FDone := True;
    Exit(rfrNotFound);
  end;
  Result := rfrMore;
end;

function TTyRichFinder.StepBackward(ABudget: Int64): TTyRichFindResult;
var
  lo, hi, first: Integer;
  endPos, limit: TTyRichPos;
begin
  endPos := ScanEnd;
  if FNext < 0 then FNext := FText.ParaOfPos(endPos);
  first := FText.ParaOfPos(FMin);
  if (FNext < first) or (endPos - FMin < FLen) then
  begin
    FDone := True;
    Exit(rfrNotFound);
  end;
  hi := FNext;
  limit := FText.ParaStart(hi) + FText.ParaLength(hi) - Max64(ABudget, 1);
  if limit < FMin then limit := FMin;
  lo := FText.ParaOfPos(limit);
  if lo > hi then lo := hi;
  if lo < first then lo := first;
  FScanEnd := endPos;
  FMode := 2;
  FStop := False;
  FBest := -1;
  if FParaEnds = 0 then ScanParas(lo, hi) else ScanWindow(lo, hi);
  if FBest >= 0 then
  begin
    FMatchPos := FBest;
    // the next one (backward) ends where this one begins
    FMax := FBest;
    FNext := FText.ParaOfPos(FBest);
    Exit(rfrFound);
  end;
  FNext := lo - 1;
  if FNext < first then
  begin
    FDone := True;
    Exit(rfrNotFound);
  end;
  Result := rfrMore;
end;

function TTyRichFinder.Step(ABudget: Int64): TTyRichFindResult;
begin
  Inc(FSteps);
  if FNever or FDone then
  begin
    FDone := True;
    Exit(rfrNotFound);
  end;
  if FText.ParaCount = 0 then
  begin
    FDone := True;
    Exit(rfrNotFound);
  end;
  FWaitOpen := True;
  if rfoBackward in FOptions then Result := StepBackward(ABudget)
  else Result := StepForward(ABudget);
end;

function TTyRichFinder.Run: TTyRichFindResult;
begin
  repeat
    Inc(FSteps);
    if FNever or FDone or (FText.ParaCount = 0) then
    begin
      FDone := True;
      Exit(rfrNotFound);
    end;
    // what is loaded is all there is to search now
    FWaitOpen := False;
    if rfoBackward in FOptions then Result := StepBackward(1 shl 20)
    else Result := StepForward(1 shl 20);
  until Result <> rfrMore;
end;

{ ---- TTyRichReplaceCommand ---- }

{ A match the document lets a user's edit replace: no row that holds a nested table in the way
  (CanChange) and R57 as the keys have it (TTyRichDocument.UserRangeAllowed) - the paragraph
  the deletion joins with counts, so a match that ends with a cell's or a row's last
  paragraph end, or with the one before a table, is refused. A range the rule would shorten
  (to keep the separator before a table) is refused too: the replacement would not mean what
  the needle said. }
function MatchAllowed(ADoc: TTyRichDocument; APos, ALen: TTyRichPos): Boolean;
var
  s, n: TTyRichPos;
begin
  Result := ADoc.CanChange(APos, ALen);
  if not Result then Exit;
  s := APos;
  n := ALen;
  Result := ADoc.UserRangeAllowed(s, n) and (s = APos) and (n = ALen);
end;

constructor TTyRichReplaceCommand.Create(ASession: Int64; const APositions: array of TTyRichPos;
  ALen: TTyRichPos; const AText: UTF8String);
var
  i: Integer;
begin
  inherited Create;
  FSession := ASession;
  FCount := Length(APositions);
  SetLength(FPos, FCount);
  for i := 0 to FCount - 1 do FPos[i] := APositions[i];
  FLen := ALen;
  FText := AText;
end;

function TTyRichReplaceCommand.Count: Integer;
begin
  Result := FCount;
end;

procedure TTyRichReplaceCommand.CountRecords;
begin
  FRecBytes := inherited MemSize - InstanceSize;
  FObjCount := 0;
  inherited GatherObjects(FObjs, FObjCount);
end;

procedure TTyRichReplaceCommand.DoExecute(ADoc: TTyRichDocument);
var
  i, k, para, r: Integer;
  t: TTyRichText;
  runs: TTyRunArray;
  off: TTyRichPos;
begin
  t := ADoc.Text;
  { The first run: the matches the document refuses go, and the formats are found; a redo
    runs on the same text and does the same. }
  if not FHasFormats then
  begin
    k := 0;
    for i := 0 to FCount - 1 do
      if MatchAllowed(ADoc, FPos[i], FLen) then
      begin
        FPos[k] := FPos[i];
        Inc(k);
      end
      else
        Inc(FSkipped);
    if FSkipCounter <> nil then Inc(FSkipCounter^, FCount - k);
    FSkipCounter := nil;
    FCount := k;
    SetLength(FPos, k);
    SetLength(FFormats, k);
    FHasFormats := True;
    for i := 0 to FCount - 1 do FFormats[i] := TyRichInheritFormat;
  end;
  for i := 0 to FCount - 1 do
  begin
    if FFormats[i] = TyRichInheritFormat then
    begin
      para := t.ParaOfPos(FPos[i]);
      off := FPos[i] - t.ParaStart(para);
      if off < t.ParaLength(para) then
      begin
        // the first character replaced: its run's format
        runs := ADoc.RunsOf(para);
        r := High(runs);
        while (r > 0) and (runs[r].Start > off) do Dec(r);
        if r >= 0 then FFormats[i] := runs[r].Format
        else FFormats[i] := ADoc.TypingFormatAt(FPos[i]);
      end
      else
        // a paragraph's end: what typing there gets
        FFormats[i] := ADoc.TypingFormatAt(FPos[i]);
    end;
    DeleteRange(ADoc, FPos[i], FLen);
    if FText <> '' then InsertText(ADoc, FPos[i], FText, FFormats[i]);
  end;
  // (a redo of a merged step runs every batch again: its records are counted anew)
  CountRecords;
end;

procedure TTyRichReplaceCommand.DoUndo(ADoc: TTyRichDocument);
begin
  inherited DoUndo(ADoc);
  // the records are reverted and go: nothing is kept for them any more
  FRecBytes := 0;
  FObjCount := 0;
  FObjs := nil;
end;

function TTyRichReplaceCommand.TryMerge(ANext: TTyRichCommand): Boolean;
var
  n: TTyRichReplaceCommand;
  i, cap: Integer;
begin
  Result := (FSession <> 0) and (ANext is TTyRichReplaceCommand) and
    (TTyRichReplaceCommand(ANext).FSession = FSession);
  if not Result then Exit;
  n := TTyRichReplaceCommand(ANext);
  Inc(FSkipped, n.FSkipped);
  // the arrays grow by doubling: a merge costs the batch it takes, not the step it joins
  if FCount + n.FCount > Length(FPos) then
  begin
    cap := Length(FPos) * 2;
    if cap < FCount + n.FCount then cap := FCount + n.FCount;
    SetLength(FPos, cap);
    SetLength(FFormats, cap);
  end;
  for i := 0 to n.FCount - 1 do
  begin
    FPos[FCount + i] := n.FPos[i];
    if n.FHasFormats then FFormats[FCount + i] := n.FFormats[i]
    else FFormats[FCount + i] := TyRichInheritFormat;
  end;
  Inc(FCount, n.FCount);
  FHasFormats := True;
  // the records come over with what was counted of them
  Inc(FRecBytes, n.FRecBytes);
  if FObjCount + n.FObjCount > Length(FObjs) then
    SetLength(FObjs, (FObjCount + n.FObjCount) * 2 + 4);
  for i := 0 to n.FObjCount - 1 do FObjs[FObjCount + i] := n.FObjs[i];
  Inc(FObjCount, n.FObjCount);
  TakeOver(ANext);
end;

function TTyRichReplaceCommand.Description: string;
begin
  Result := rsRichUndoReplace;
end;

function TTyRichReplaceCommand.MemSize: Int64;
begin
  Result := InstanceSize + FRecBytes + Length(FPos) * (SizeOf(TTyRichPos) + SizeOf(TTyCharFormatId)) +
    Length(FText) + Length(FObjs) * SizeOf(Pointer);
end;

procedure TTyRichReplaceCommand.GatherObjects(var AList: TTyRichObjectList; var ACount: Integer);
var
  i: Integer;
begin
  if ACount + FObjCount > Length(AList) then SetLength(AList, (ACount + FObjCount) * 2 + 4);
  for i := 0 to FObjCount - 1 do AList[ACount + i] := FObjs[i];
  Inc(ACount, FObjCount);
end;

end.
