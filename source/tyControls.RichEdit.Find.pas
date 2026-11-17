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
  turns into a character of the needle's first 64, every group either read or passed over,
  every character a \uN may skip), and decoded only when it may hold the needle; it is decoded
  through the text's walk that hands out paragraph values of the moment (nothing is set, nothing
  is kept beyond what the reader keeps of any read). A needle with a paragraph end, a character
  outside the Basic Multilingual Plane or U+FFFD is not filtered: every paragraph is decoded.

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

  { A needle turned into what the raw-byte filter compares: built once per finder. }
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
    function MaskOf(C: Cardinal): QWord;
  public
    { ANeedle: the needle's characters as the finder has them (folded unless AMatchCase), no
      paragraph end in it. ALoad: the file whose code pages the bytes may be in. }
    constructor Create(const ANeedle: array of Cardinal; AMatchCase: Boolean; ALoad: TTyRtfLoad);
    { False only when the RTF bytes [AStart, AStop) of ABuf cannot read as text that holds the
      needle's first characters (see the unit comment). }
    function MayHold(ABuf: PByte; AStart, AStop: PtrInt): Boolean;
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
    FFirstWord, FLastWord: Boolean;   // the needle's first / last character is a word character
    FMin, FMax: TTyRichPos;           // a match lies in [FMin, FMax]; FMax < 0: the text's end
    FNext: Integer;                   // the next paragraph to search (backward: the highest)
    FDone, FWaiting, FWaitOpen: Boolean;
    FCollect: Boolean;
    FMatchPos: TTyRichPos;
    FMatches: array of TTyRichPos;
    FMatchCount: Integer;
    FLoad: TTyRtfLoad;
    FFilter: TTyRichRawFilter;
    FUseFilter, FFilterTried: Boolean;
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
    FWin: array of record
      Start: TTyRichPos;
      Chars: Int64;
      Hidden, TailOk, HeadOk: Boolean;
      Mid: array of Boolean;
    end;
    FWinFirst: Integer;                // the first paragraph of the window walk
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
    holds a nested table (TTyRichDocument.CanChange), one that reaches across a cell's or a
    row's edge (R57: TyRichCrossesCells). So the command never fails halfway for a refusal.
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

{ The characters [APos, APos + ALen) of ADoc reach across a table cell's or a row's edge:
  their paragraphs are not all in the same cell (or all in none). Reads the paragraphs' cells
  (parses them in a document read on demand). }
function TyRichCrossesCells(ADoc: TTyRichDocument; APos, ALen: TTyRichPos): Boolean;

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
  LazUTF16, tyControls.RichEdit.TextIO, tyControls.RichEdit.RowFormat, tyControls.StrConsts;

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

{ ---- the raw-byte filter ---- }

{ The characters the reader makes of control words (TTyRtfParser.BodyWord), and 0 for any
  other word: those are formatting, a table's or a paragraph's end, or kept unread - none is a
  character of the paragraph's text. }
function WordChar(ABuf: PByte; AStart, ALen: Integer): Cardinal;
var
  s: string;
begin
  Result := 0;
  if (ALen < 3) or (ALen > 10) then Exit;
  SetLength(s, ALen);
  Move(ABuf[AStart], s[1], ALen);
  case s of
    'line': Result := $0B;
    'tab': Result := $09;
    'ldblquote': Result := $201C;
    'rdblquote': Result := $201D;
    'lquote': Result := $2018;
    'rquote': Result := $2019;
    'emdash': Result := $2014;
    'endash': Result := $2013;
    'bullet': Result := $2022;
    'emspace': Result := $2003;
    'enspace': Result := $2002;
    'qmspace': Result := $2005;
    'zwj': Result := $200D;
    'zwnj': Result := $200C;
    'ltrmark': Result := $200E;
    'rtlmark': Result := $200F;
    'zwbo': Result := $200B;
    'zwnbo': Result := $FEFF;
  end;
end;

constructor TTyRichRawFilter.Create(const ANeedle: array of Cardinal; AMatchCase: Boolean;
  ALoad: TTyRtfLoad);
var
  k, i, j, b, t, f, cp: Integer;
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
  { The code pages the reader can decode this file's bytes with (UpdateDecoder): each font's,
    the file's \ansicpg (a font it does not know), and 1252 (a code page it has no table for). }
  tables := nil;
  if ALoad <> nil then
  begin
    for f := 0 to ALoad.Scan.FontCount - 1 do
    begin
      cp := ALoad.Scan.Font(f).CodePage;
      if cp > 0 then AddTable(cp);
    end;
    AddTable(ALoad.Scan.AnsiCodePage);
  end;
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

type
  { What the filter carries into a group, to put back (or join) at its end. }
  TFilterSave = record
    D, T, Lead: QWord;
    LeadByte: Integer;
    Wild: QWord;
  end;

{ The needle's first characters looked for in the bytes as the reader may read them - a
  Shift-And automaton (bit k: the needle's first k + 1 characters end here) over a reading
  that takes every way the reader can go:
  - a text byte or a \'xx is a byte: its character in any of the file's code pages, '?', or
    the Symbol charset's; a lead byte and the byte after it (also after control words and
    groups between them, as the reader joins them) a pair of any double-byte code page;
  - \uN is its character; the bytes, \'xx and control symbols after it up to the next control
    word may each be a fallback it skips, or text (any \ucN, also one from before the
    paragraph's bytes);
  - the control words that are characters (\tab, \emdash, ...) and the control symbols that
    are (a tilde, an underscore, an escaped backslash or brace) are those characters; every other control word, CR, LF, NUL and the other control bytes
    are nothing;
  - every group is read through or passed over as if it were not there - whatever the reader
    does with a destination (a field, a picture and a list's marker are no text of the
    paragraph; \upr's \ud is).
  So the answer is False only where no reading the reader can make holds the characters. }
function TTyRichRawFilter.MayHold(ABuf: PByte; AStart, AStop: PtrInt): Boolean;
var
  lex: TTyRtfLexer;
  tok: TTyRtfToken;
  d, t, lead, wild, nd: QWord;
  leadByte: Integer;
  stack: array of TFilterSave;
  depth: Integer;
  p: PtrInt;
  b: Byte;
  c: Cardinal;

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
  Result := True;
  if FCount <= 0 then Exit;
  lex.Init(ABuf, AStart, AStop);
  d := 0;
  t := 0;
  lead := 0;
  wild := 0;
  leadByte := -1;
  stack := nil;
  depth := 0;
  while lex.Next(tok) do
  begin
    case tok.Kind of
      rtkGroupStart:
        begin
          if depth = Length(stack) then SetLength(stack, depth * 2 + 8);
          stack[depth].D := d;
          stack[depth].T := t;
          stack[depth].Lead := lead;
          stack[depth].LeadByte := leadByte;
          stack[depth].Wild := wild;
          Inc(depth);
        end;
      rtkGroupEnd:
        if depth > 0 then
        begin
          Dec(depth);
          // read through, or passed over
          d := d or stack[depth].D;
          t := t or stack[depth].T;
          if stack[depth].Lead <> 0 then
            if (lead = 0) or (leadByte = stack[depth].LeadByte) then
            begin
              lead := lead or stack[depth].Lead;
              leadByte := stack[depth].LeadByte;
            end
            else
              // two lead bytes may be waiting: whatever follows may pair with either
              wild := wild or stack[depth].Lead;
          wild := wild or stack[depth].Wild;
        end;
      rtkWord:
        begin
          if (tok.NameLen = 1) and (ABuf[tok.NameStart] = Ord('u')) and tok.HasParam then
          begin
            // a word ends what a \uN before it was skipping, and this one skips anew
            t := 0;
            c := Cardinal(tok.Param);
            if tok.Param < 0 then c := Cardinal(tok.Param + 65536);
            if (c = 0) or (c = 10) or (c = 13) then
              // no text; the fallback is skipped all the same
            else
              CharUnit(c);
            t := d;
          end
          else
          begin
            t := 0;
            c := WordChar(ABuf, tok.NameStart, tok.NameLen);
            if c <> 0 then CharUnit(c);
          end;
        end;
      rtkSymbol:
        case tok.Value of
          Ord('~'): CharUnit($A0);
          Ord('_'): CharUnit($2011);
          Ord('\'), Ord('{'), Ord('}'): CharUnit(tok.Value);
        end;
      rtkHex:
        if tok.Value >= 0 then ByteUnit(tok.Value);
      rtkText:
        for p := tok.Start to tok.Stop - 1 do
        begin
          b := ABuf[p];
          if (b < $20) and (b <> 9) then Continue;
          ByteUnit(b);
          if d and FAccept <> 0 then Exit;
        end;
      rtkBin: ;
    end;
    if d and FAccept <> 0 then Exit;
  end;
  Result := False;
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
begin
  FFilter.Free;
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
  FFirstWord := TyRichWordClass(raw[0]) = 1;
  FLastWord := TyRichWordClass(raw[FLen - 1]) = 1;
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
  first: array of Cardinal;
  i: Integer;
begin
  if not FFilterTried then
  begin
    FFilterTried := True;
    FLoad := TyRichRtfLoadOf(FDoc);
    if (FLoad <> nil) and (FParaEnds = 0) then
    begin
      first := nil;
      SetLength(first, FLen);
      for i := 0 to FLen - 1 do
      begin
        // what the filter cannot say: a character the reader makes of two \uN, or of many ways
        if (FCodes[i] >= $10000) or (FCodes[i] = $FFFD) then
        begin
          FLoad := nil;
          Break;
        end;
        first[i] := FCodes[i];
      end;
      if FLoad <> nil then
        FFilter := TTyRichRawFilter.Create(first, rfoMatchCase in FOptions, FLoad);
    end;
  end;
  Result := FUseFilter and (FFilter <> nil);
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
      if not (FLastWord and (TyRichWordClass(code) = 1)) then
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
        if not (FFirstWord and (TyRichWordClass(prev) = 1)) then
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
  filter := FilterReady;
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

procedure TTyRichFinder.WindowPara(AIndex: Integer; AData: Pointer; AText: PByte; ALen: PtrInt;
  var AContinue: Boolean);
var
  slot, s, k, j, n, ringN, last: Integer;
  p, stop: PByte;
  code, prev: Cardinal;
  pos: Int64;
  matchCase, whole, ok: Boolean;
  seg: array of Cardinal;
  codes: array of Cardinal;
  start: TTyRichPos;
begin
  Inc(FParasRead);
  Inc(FTextBytes, ALen);
  matchCase := rfoMatchCase in FOptions;
  whole := rfoWholeWord in FOptions;
  slot := (AIndex - FWinFirst) mod (FParaEnds + 1);
  FWin[slot].Start := FRunPos;
  FWin[slot].Hidden := HiddenValue(AData);
  // the paragraph's characters: a head as long as the last segment and the one after it are
  // kept, and a tail as long as the first segment and the one before it (FRing)
  last := Length(FSegs[FParaEnds]);
  codes := nil;
  SetLength(codes, last + 1);
  ringN := Length(FRing);
  p := AText;
  stop := AText + ALen;
  pos := 0;
  // a middle paragraph is compared whole: its characters are kept while they may equal one
  n := 0;
  for s := 1 to FParaEnds - 1 do
    if Length(FSegs[s]) > n then n := Length(FSegs[s]);
  seg := nil;
  SetLength(seg, n);
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
  FWin[slot].Chars := pos;
  FRunPos := FRunPos + pos + 1;
  // ends with the first segment (and nothing before it that a word goes on through)
  s := Length(FSegs[0]);
  ok := pos >= s;
  j := 0;
  while ok and (j < s) do
  begin
    ok := FRing[(pos - s + j) mod ringN] = FSegs[0][j];
    Inc(j);
  end;
  if ok and whole and (s > 0) and FFirstWord then
  begin
    if pos - s - 1 >= 0 then prev := FRing[(pos - s - 1) mod ringN] else prev := CNone;
    ok := TyRichWordClass(prev) <> 1;
  end;
  FWin[slot].TailOk := ok;
  // is a middle segment
  SetLength(FWin[slot].Mid, FParaEnds + 1);
  for k := 1 to FParaEnds - 1 do
  begin
    ok := pos = Length(FSegs[k]);
    j := 0;
    while ok and (j < pos) do
    begin
      ok := seg[j] = FSegs[k][j];
      Inc(j);
    end;
    FWin[slot].Mid[k] := ok;
  end;
  // begins with the last segment (and no word goes on past it)
  ok := pos >= last;
  j := 0;
  while ok and (j < last) do
  begin
    ok := codes[j] = FSegs[FParaEnds][j];
    Inc(j);
  end;
  if ok and whole and (last > 0) and FLastWord and (pos > last) then
    ok := TyRichWordClass(codes[last]) <> 1;
  FWin[slot].HeadOk := ok;
  { A match from paragraph j = AIndex - FParaEnds: j ends with the first segment, the
    paragraphs between are the middle ones, AIndex begins with the last; none of them is a
    cell merged away. }
  j := AIndex - FParaEnds;
  if j < FWinFirst then Exit;
  // (a needle that ends with a paragraph end takes nothing of the last paragraph)
  ok := FWin[slot].HeadOk and ((last = 0) or not FWin[slot].Hidden);
  if ok then
  begin
    n := (j - FWinFirst) mod (FParaEnds + 1);
    ok := FWin[n].TailOk and not FWin[n].Hidden;
  end;
  k := 1;
  while ok and (k < FParaEnds) do
  begin
    n := (j + k - FWinFirst) mod (FParaEnds + 1);
    ok := FWin[n].Mid[k] and not FWin[n].Hidden;
    Inc(k);
  end;
  if not ok then Exit;
  n := (j - FWinFirst) mod (FParaEnds + 1);
  start := FWin[n].Start + FWin[n].Chars - Length(FSegs[0]);
  if Accept(start) then AContinue := False;
end;

{ Matches starting in paragraphs ALo .. AHi of a needle with paragraph ends: a window of that
  many paragraphs after each, in one walk. }
procedure TTyRichFinder.ScanWindow(ALo, AHi: Integer);
var
  last: Integer;
begin
  last := AHi + FParaEnds;
  if last > FText.ParaCount - 1 then last := FText.ParaCount - 1;
  if last - ALo < FParaEnds then Exit;
  FWin := nil;
  SetLength(FWin, FParaEnds + 1);
  FWinFirst := ALo;
  FRunPos := FText.ParaStart(ALo);
  FText.WalkParaTexts(ALo, last, @WindowPara, True);
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

function TyRichCrossesCells(ADoc: TTyRichDocument; APos, ALen: TTyRichPos): Boolean;
var
  first, last, i: Integer;
  cell: TTyRichCell;
begin
  Result := False;
  if ALen <= 0 then Exit;
  first := ADoc.Text.ParaOfPos(APos);
  last := ADoc.Text.ParaOfPos(APos + ALen - 1);
  if first = last then Exit;
  ADoc.BeginRead;
  try
    cell := ADoc.CellAt(first);
    for i := first + 1 to last do
      if ADoc.CellAt(i) <> cell then Exit(True);
  finally
    ADoc.EndRead;
  end;
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
      if ADoc.CanChange(FPos[i], FLen) and not TyRichCrossesCells(ADoc, FPos[i], FLen) then
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
