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
  rule (tyControls.RichEdit.Model's TyRichWordClass) in two - at each end, the character
  outside and the needle's own character there are not both word characters of one word. A
  character of a script written without spaces (Chinese, kana, Hangul, full-width forms - the
  line breaker's set) bounds a word on both of its sides: a Chinese needle is a whole word
  between two ideographs, and a Latin word inside Chinese text is bounded by them (Joins).

  Text that was never parsed (a lazily read RTF): a paragraph that is still its bytes in the
  file is read like any other - the reader parses it as the search reaches it, and the
  needle is looked for in the text it reads as. Nothing is concluded from a paragraph's
  bytes: what they read as is the reader's to say (a code page, a group left open, a byte
  still waiting for its second), and a find that guessed could miss a hit. So a find in a
  very big file reads the file's paragraphs as it goes - through the text's walk that hands
  out paragraph values of the moment (nothing is set, nothing is kept beyond what the
  reader keeps of any read), so memory stays as bounded as the reader keeps it. A needle
  with paragraph ends is looked for paragraph by paragraph: a middle paragraph must be a
  segment whole (its length, from the paragraph tree, says much: two paragraph ends in a
  row are an empty paragraph), the first must be as long as the first segment and the last
  as long as the last; only the paragraphs of a match that may be there are read.

  An object never matches text - and a field (a link) is an object: its display text is not
  found. When field results become text the control shows, the finder must see them.

  Replacing: TTyRichReplaceAllCommand replaces every match of a range, walking it from its
  start a range of paragraphs at a time, as ONE undo step that merges with no other (see its
  declaration). }

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
  { A replace of every match (TTyRichReplaceAllCommand) ends when its undo step keeps this many
    times the document's MaxUndoBytes (64 MB by default: 256 MB): what it replaced is one step,
    and it says the limit ended it. }
  CRichReplaceLimitFactor = 4;
  { The range of paragraphs a replace of every match reads and replaces at a time, in
    characters (TTyRichReplaceAllCommand.RangeChars). }
  CRichReplaceRangeChars = 64 * 1024;
  { The most matches a part of it replaces (the last of its range's: the others wait for the
    next part). }
  CRichReplacePartMatches = 8192;
  { The ordinary edits of a part (a replacement with a paragraph end): while the part's matches
    lie within this many characters they go the first one, then from the last back; farther
    apart, from the first on (TTyRichReplaceAllCommand's run says why). }
  CRichReplaceBackSpan = 32 * 1024;

type
  TTyRichCodeArray = array of Cardinal;

  { What stood right before a place in the text, as a walk saw it there. Known False: nothing
    is known - the text as it is says. Code: the character; TyRichFindParaEnd where a paragraph
    began at the place (nothing stood before it). }
  TTyRichBefore = record
    Known: Boolean;
    Code: Cardinal;
  end;

  { rfoWrap is the control's (TTyCustomRichEdit.FindNext: past the end, on from the other
    end); a finder searches its range and does not look at it. }
  TTyRichFindOption = (rfoMatchCase, rfoWholeWord, rfoBackward, rfoWrap);
  TTyRichFindOptions = set of TTyRichFindOption;

  { What a step of a finder ended with. rfrMore: its budget is spent (or, Waiting, the text it
    may search is searched and a load is still adding to it) - call Step again. }
  TTyRichFindResult = (rfrMore, rfrFound, rfrNotFound);

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
    FLoad: TTyRtfLoad;                // the lazily read file the text is of (Source)
    FLoadAsked: Boolean;
    // counts
    FParasRead, FSteps: Int64;
    FTextBytes, FFileBytes, FPassedBytes, FPieces: Int64;
    // the scan in progress
    FMode: Integer;                   // 0 first, 1 all, 2 last
    FScanEnd: TTyRichPos;             // matches end at or before it
    FRunPos: TTyRichPos;              // where the paragraph being read starts
    FBest: TTyRichPos;
    FStop: Boolean;
    FRing: array of Cardinal;
    { ScanWindow (a needle with paragraph ends): what is known of paragraphs FWinFirst ..
      FWinFirst + n - 1 - characters, start, the value a walk gave, the file's bytes of an
      unparsed one; and, per role, whether it can play it (-1 not known yet, 0 no, 1 yes, 2
      it may - its text will say): the first of a match (it ends with the first segment), a
      middle one (it is segment k), the last (it begins with the last segment); hidden (a
      cell merged away). }
    FWinFirst: Integer;
    FWinLen: array of Int64;
    FWinStart: array of TTyRichPos;
    FWinData: array of Pointer;
    FWinSrc, FWinBytes: array of Int64;
    FWinTail, FWinHead, FWinHidden: array of ShortInt;
    FWinMid: array of array of ShortInt;
    FWinNeed: array of Boolean;
    // where the bytes of paragraphs FSrcFirst .. are in the file (-1: not a paragraph of a
    // lazily read file, or one edited since)
    FSrc, FSrcBytes: array of Int64;
    FSrcFirst: Integer;
    { The scan of a needle without paragraph ends stands in paragraph FNext, FCurOff
      characters and FCurByte bytes into its text (both 0: at its start), the matcher's
      state FK and FPend there. A step reads FBudget units. Backward, and for CollectRange:
      the range FRangeLo .. FRangeHi being read (-1: none). }
    FCurOff: TTyRichPos;
    FCurByte: PtrInt;
    FPassTo: TTyRichPos;              // characters of FNext passed, not matched (a start inside it)
    FK: Integer;
    FPend: Int64;
    FBudget: Int64;
    { The text of paragraph FKeepPara, kept while the scan stands inside it and the document's
      content is as it was (FKeepState): fetched once, not once a step. }
    FKeep: RawByteString;
    FKeepPara: Integer;
    FKeepState: Int64;
    FKeepBase: TTyRichPos;            // where the kept paragraph starts
    FKeepShift: TTyRichPos;           // what changed before the scan since it was kept (Moved)
    { Moved: the content's number changes when the part's run is over, after Moved - the next
      step takes it as the kept text's (a caller that changed the text otherwise between them
      would find its part refused by the document: TTyRichDocument.ExecutePart). }
    FKeepMoved: Boolean;
    FCap: Integer;                    // CollectRange: the most matches it collects (0: all)
    FCapped: Boolean;
    FStartAt: TTyRichPos;             // the start it was made with
    FStartBefore: TTyRichBefore;      // what stood before that, as its maker says
    FFetchedBytes: Int64;
    FRangeLo, FRangeHi: Integer;
    procedure ParseNeedle(const ANeedle: UTF8String);
    procedure SourceOf(AIndex: Integer; AData: Pointer; ASrcOffset, ASrcBytes: Int64;
      var AContinue: Boolean);
    function ScanEnd: TTyRichPos;
    function HiddenValue(AData: Pointer): Boolean;
    function Source: TTyRtfLoad;
    function BeforeCode: Cardinal;
    function Accept(AStart: TTyRichPos): Boolean;
    procedure NextPara;
    procedure LoadSources(AFirst, ALast: Integer);
    procedure ScanRange(ALast: Integer);
    procedure ScanWindow(ALo, AHi: Integer);
    function WindowHi(ALo, ALast: Integer; ABudget: Int64): Integer;
    procedure ExactPara(AIndex: Integer; AData: Pointer; AText: PByte; ALen: PtrInt;
      var AContinue: Boolean);
    procedure WindowPara(AIndex: Integer; AData: Pointer; AText: PByte; ALen: PtrInt;
      var AContinue: Boolean);
    procedure WindowSource(AIndex: Integer; AData: Pointer; ASrcOffset, ASrcBytes: Int64;
      var AContinue: Boolean);
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
    { Searches on for about ABudget units of work: a byte of text read is one, a paragraph
      begun sixteen, and a paragraph of a lazily read file as many more as it has bytes in
      the file (the reader parses them for the search: a picture's paragraph is one character
      and may be megabytes). A paragraph whose text is larger than the budget is read in
      pieces over several steps (the matcher keeps its state in it); the one thing a step
      may go over its budget by is the paragraph it is in when the budget ends - a
      paragraph is parsed in one piece (at most its interval group of the file is parsed for
      it) - and, for a needle with paragraph ends, the paragraphs of one match window, which
      are read whole. rfrFound: the next match is MatchPos (MatchLen characters); the next
      Step goes on right after it (backward: before it). With Collect, matches are kept in
      Matches and the step goes on to its budget. rfrNotFound: no match is left. rfrMore:
      call again (Waiting: what can be searched is, and the document is still loading). }
    function Step(ABudget: Int64): TTyRichFindResult;
    { For a replace that walks the text range by range (a needle without paragraph ends): the
      matches in paragraphs ALo .. AHi that lie in [AFrom, ATo] (ATo < 0: to AHi's end;
      leftmost, never overlapping), read for about ABudget units (< 0: no bound) - rfrMore:
      call again with the same range; rfrFound / rfrNotFound: the range is read and its
      matches are Matches. }
    function CollectRange(ALo, AHi: Integer; AFrom, ATo: TTyRichPos;
      ABudget: Int64; ACap: Integer = 0): TTyRichFindResult;
    { CollectRange stopped at ACap matches (rfrFound), the range not read through: the next
      call with the same range goes on right after the last one. }
    property Capped: Boolean read FCapped;
    { What stood right before the finder's start (AStart), as whoever made the finder saw it:
      taken for the whole-word test of a match that begins exactly there, in place of the
      character the text has before it now. For a replace that goes on where another stopped:
      that one replaced what stood before the place, and the one walk the two are parts of
      judged the word boundary by the text as it was. Not Known (the default): the text as it
      is. Set before the first step. }
    property StartBefore: TTyRichBefore read FStartBefore write FStartBefore;
    { The text before where the scan stands changed by ADelta characters and AParas paragraphs
      (a replace's own part, of the matches it collected): the scan goes on where it stood, in
      the paragraph's text it keeps, its places moved by the change. }
    procedure Moved(ADelta: TTyRichPos; AParas: Integer);
    { A count that grows with everything a step does (text read or passed, paragraphs begun,
      the paragraph it stands in): a step that leaves it as it was did nothing. }
    function WorkDone: Int64;
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
    { Counts: paragraphs read, steps, bytes of text read; and, of the paragraphs read that
      are a lazily read file's (never edited), their bytes in the file - what the reader
      parsed for the search, or had parsed already. }
    property ParasRead: Int64 read FParasRead;
    property Steps: Int64 read FSteps;
    property TextBytes: Int64 read FTextBytes;
    property FileBytes: Int64 read FFileBytes;
    { Bytes of paragraph text the finder had handed to it (gathered from pieces or decoded):
      a paragraph read over many steps counts once. Characters passed before a start inside a
      paragraph, in bytes (never matched; a step passes at most eight times its budget). }
    property FetchedBytes: Int64 read FFetchedBytes;
    property PassedBytes: Int64 read FPassedBytes;
    { The pieces paragraphs were read in (a paragraph read in one go is one). }
    property Pieces: Int64 read FPieces;
    { Bytes of the paragraph text it keeps (the paragraph it stands in, read over steps). }
    function KeptBytes: Int64;
  end;

  { What a replace of every match has done so far, written by TTyRichReplaceAllCommand as its
    parts run (Execute, ExecutePart - not a redo): for a caller that may not hold the command
    any more when it reads (a document's handler may have let the history go). }
  TTyRichReplaceTally = record
    Replaced, Skipped: Integer;
    Limited: Boolean;
    { The walk could not go on (a part that made no progress - a guard, never the ordinary
      way to end). }
    Failed: Boolean;
    { Where a run that did not get through its range may be run again from (see
      TTyRichReplaceAllCommand.ResumeAt), and the characters from there to the range's end
      (-1: to the text's end). }
    ResumeAt, ResumeLength: TTyRichPos;
    { What the walk saw right before ResumeAt (TTyRichReplaceAllCommand.ResumeBefore). }
    ResumeBefore: TTyRichBefore;
  end;
  PTyRichReplaceTally = ^TTyRichReplaceTally;

  { Every match of AFind in a range of the text replaced by AReplace, as ONE command and one
    undo step, never merged with another.

    The walk: through the range once, a range of paragraphs at a time (RangeChars characters):
    the range's matches are found on the text as it is (Prepare - it changes nothing, and goes
    on in pieces of a budget) and replaced right after (the command's run: Execute for the
    first range, TTyRichDocument.ExecutePart for each next one - the document consistent and
    reported between two; at most CRichReplacePartMatches a part, the others of the range
    moved by what the part changed). So no position is used after the text changed before
    it, an interval of a lazily read RTF is parsed once (found and replaced while it is
    resident), no list of every match is kept, and a replacement is never searched again;
    the walk goes from the range's start to its end. A needle with a paragraph end is the
    simple way: every match is found
    first (a position each, 8 bytes), then they are replaced from the first on in ranges of
    the same size, each moved by what the ones before it changed.

    What the undo step keeps: a needle and a replacement without paragraph ends - one record
    for a range (TTyRichDocument.ReplaceInParas): for each paragraph changed its pieces before
    and its value before (references, no text: a few dozen bytes a paragraph, however many
    matches it holds); otherwise the ordinary records of a delete and an insert for each
    match. The promises of any command hold: an undo puts back the text, the formats and the
    objects exactly (a lazily read paragraph is its file's bytes again) and the step's
    selection marks; one OnChange for each run (Execute or ExecutePart).

    Which matches: leftmost, never overlapping, as a forward find has them; a replacement is
    never searched again ("a" by "aa" replaces each "a" once). Each takes the format of the
    first character it replaces (a paragraph's end: what typing there gets). A match the
    document will not let a user's edit change - a row that holds a nested table
    (CanChange), a cell's or a row's edge (TTyRichDocument.UserRangeAllowed) - is left
    and counted (Skipped).

    The limit: when the step keeps CRichReplaceLimitFactor times the document's MaxUndoBytes
    (and that is > 0), the replace ends after the range that reached it - Limited: what was
    replaced is the one step. ResumeAt says where it stopped: right behind the last match it
    dealt with, in the text as it is now; a new command from there (to the range's end,
    ResumeLength) replaces the rest and nothing twice - also where a replacement holds the
    needle. A redo replays what the first run replaced, all of it at once.

    Whole word, and a stop between two matches that touch: the walk judged the second by the
    character before it in the text as it was - the first match's last -, and a new command
    from ResumeAt would judge it by the replacement's last character, which may answer the
    other way. So a stop also says what the walk saw there (ResumeBefore), and the command
    that goes on from exactly that place, the text unchanged since, is given it (StartBefore):
    the two replace what one walk replaces. A part ends between touching matches like
    anywhere else. }
  TTyRichReplaceAllCommand = class(TTyRichCommand)
  private
    FTarget: TTyRichDocument;
    FFind, FRepl: UTF8String;
    FOptions: TTyRichFindOptions;
    FFinder: TTyRichFinder;
    FLen: TTyRichPos;
    FFrom, FTo: TTyRichPos;           // the range, in the text it began on (FTo < 0: its end)
    FResume: TTyRichPos;              // behind the last match dealt with, in the text as it is
    FStuck: Boolean;
    FStartBefore, FResumeBefore: TTyRichBefore;
    FSimple: Boolean;                 // a paragraph end in the needle: every match first
    FFast: Boolean;                   // none in either: ReplaceInParas
    FAllAtOnce: Boolean;
    FRangeChars: Int64;
    FStarted, FWalkDone, FLimited: Boolean;
    FStopped: Boolean;                // let go of before the walk was through its range
    FTotal: TTyRichPos;               // the text's length when the walk began
    // the walk: the next range begins with FNextPara; the one being read; the paragraphs then
    FNextPara, FRangeLo, FRangeHi, FRangeParas: Integer;
    FRangeOpen: Boolean;              // its finder stopped at a part's matches inside it
    FCharDelta: TTyRichPos;           // what the replacements so far changed the length by
    FHighPos: TTyRichPos;             // where what was replaced ends, in the text it began on (-1)
    FRedoTo: TTyRichPos;              // a redo replaces the matches before here (-1: no redo)
    FReady: array of TTyRichPos;      // the next part's matches, rising
    FReadyCount: Integer;
    FReadyState: Int64;               // the content they were found in
    FReadyFresh: Boolean;             // none of them replaced yet
    FAskedFrom, FAskedTo: TTyRichPos; // the paragraph Allowed asked last, and its answer
    FAskedAnswer: Boolean;
    FAll: array of TTyRichPos;        // the simple way: every match
    FAllCount, FAllNext: Integer;     // ... and the next to replace
    FCollected: Boolean;
    FReplaced, FSkipped: Integer;
    FRecBytes: Int64;
    FTally: PTyRichReplaceTally;
    FId: Int64;
    function Allowed(APos: TTyRichPos): Boolean;
    procedure Take(APos: TTyRichPos);
    procedure Apply(ADoc: TTyRichDocument);
    procedure Run(ADoc: TTyRichDocument);
    procedure Report;
    function Search(ABudget: Int64): Boolean;
    procedure Fail;
    function RangeEnd: TTyRichPos;
    procedure SetStartBefore(const AValue: TTyRichBefore);
  protected
    procedure DoExecute(ADoc: TTyRichDocument); override;
    procedure DoContinue(ADoc: TTyRichDocument); override;
    procedure DoUndo(ADoc: TTyRichDocument); override;
    procedure DoRedo(ADoc: TTyRichDocument); override;
  public
    { A step on top of it: the walk will not go on (LetGo). }
    procedure Covered; override;
    { A replace in ADoc (the document it will run in) of the matches that lie wholly in
      [AStart, AStart + ALength) (ALength < 0, or past the end: to the text's end, also as
      the replacements make it longer). rfoBackward and rfoWrap are not looked at. Nothing is
      searched before Prepare (or the first run). }
    constructor Create(ADoc: TTyRichDocument; const AFind, AReplace: UTF8String;
      AOptions: TTyRichFindOptions; AStart: TTyRichPos = 0; ALength: TTyRichPos = -1);
    destructor Destroy; override;
    { Searches on toward the range's end for about ABudget units (a finder's step's; < 0:
      no bound) until the next range with a match the document lets change is found: True
      when that part is Ready - or when nothing is left (Finished). Changes nothing; the
      document must not change between it and the run that replaces what it found. A call
      with a budget always gets on (a call that would not ends the walk: Failed). }
    function Prepare(ABudget: Int64): Boolean;
    { A part waits for the next run (Execute, then TTyRichDocument.ExecutePart). }
    function Ready: Boolean;
    { Nothing is left to replace: the walk reached the range's end, the limit ended it, or it
      Failed. A walk that was let go of before that is not finished: it is Stopped. }
    function Finished: Boolean;
    { The walk was let go of before it was through its range (LetGo: its caller stopped it, a
      step went on top of its own, its step was undone - also when it was redone since): it
      finds and replaces nothing more, and what is left of its range is still to do, from
      ResumeAt. Never together with Finished. }
    property Stopped: Boolean read FStopped;
    { Where a run again would go on from: right behind the last match of the last part that
      ran, in the text as it is now - the range's start before any part ran; and the
      characters from there to the range's end (-1: to the text's end). Run again from there,
      what was replaced is not replaced twice (a match the document did not let change before
      the place may be counted as Skipped again). }
    property ResumeAt: TTyRichPos read FResume;
    function ResumeLength: TTyRichPos;
    { What stood right before ResumeAt in the text as the walk saw it: the last character of
      the last match it replaced (a paragraph's end: TyRichFindParaEnd) - before any part
      ran, what it was given as StartBefore. For the command that goes on from ResumeAt. }
    property ResumeBefore: TTyRichBefore read FResumeBefore;
    { For a command that goes on exactly where another stopped (that one's ResumeAt), the text
      unchanged since: that one's ResumeBefore - what the walk saw before this command's
      start (TTyRichFinder.StartBefore). Set before the first Prepare or run. }
    property StartBefore: TTyRichBefore read FStartBefore write SetStartBefore;
    { The walk could not go on: a part that made no progress ended it (a guard: an end that
      the ordinary way never takes). }
    property Failed: Boolean read FStuck;
    { The walk will not go on (its caller stopped it before its end - a cancel, an edit, a
      save): the finder and its kept paragraph text go, and what is left is the undo record.
      A walk that was not through its range is Stopped from here on - not Finished. }
    procedure LetGo;
    { What it holds besides its undo record: the finder's kept text, the lists of matches. }
    function HeldBytes: Int64;
    function Description: string; override;
    { What the step keeps, counted as its parts ran (no pass over its records). }
    function MemSize: Int64; override;
    { How far it has come, in characters of the text it began on (ADone = ATotal at the end;
      the simple way counts its search as the first half). }
    procedure Progress(out ADone, ATotal: Int64);
    { DoExecute runs the whole walk at once - the way inside an update block, and a redo's. }
    property AllAtOnce: Boolean read FAllAtOnce write FAllAtOnce;
    { The range of paragraphs a part reads and replaces (characters; CRichReplaceRangeChars). }
    property RangeChars: Int64 read FRangeChars write FRangeChars;
    property Replaced: Integer read FReplaced;
    property Skipped: Integer read FSkipped;
    property Limited: Boolean read FLimited;
    property Tally: PTyRichReplaceTally read FTally write FTally;
    { A number of its own (never given twice): who holds a pointer to it can tell it from
      another command made later at the same address. }
    property Id: Int64 read FId;
  end;

{ The character as a find without rfoMatchCase compares it (see the unit comment). }
function TyRichFoldChar(C: Cardinal): Cardinal;
{ The characters of UTF-8 text as the finder reads them: a paragraph separator (CR LF, CR, LF)
  is TyRichFindParaEnd, a byte that starts no valid sequence TyRichFindRawByte plus it. }
function TyRichFindCodes(const S: RawByteString): TTyRichCodeArray;

implementation

uses
  LazUTF16, tyControls.RichEdit.RowFormat, tyControls.StrConsts;

const
  CObject = $FFFC;
  CNone = $FFFFFFFE;      // no character (before the text's start)

function Max64(A, B: Int64): Int64; inline;
begin
  if A > B then Result := A else Result := B;
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
  (TyRichNoSpaceScript - Hangul Jamo and syllables, the CJK radicals, punctuation, kana, Bopomofo,
  the ideographs of every extension, Yi, the compatibility ideographs and forms, and the
  full-width forms). So a Chinese needle is a whole word between two ideographs, and a Latin
  word inside Chinese text is bounded by them. }
function Joins(AOutside, AEdge: Cardinal): Boolean; inline;
begin
  Result := (TyRichWordClass(AOutside) = 1) and (TyRichWordClass(AEdge) = 1) and
    not TyRichNoSpaceScript(AOutside) and not TyRichNoSpaceScript(AEdge);
end;

{ ---- TTyRichFinder ---- }

constructor TTyRichFinder.Create(ADoc: TTyRichDocument; const ANeedle: UTF8String;
  AOptions: TTyRichFindOptions; AStart: TTyRichPos; AEnd: TTyRichPos);
begin
  inherited Create;
  FDoc := ADoc;
  FText := ADoc.Text;
  FOptions := AOptions;
  if AStart < 0 then AStart := 0;
  FMin := AStart;
  FMax := AEnd;
  FNext := -1;
  FMatchPos := -1;
  FRangeLo := -1;
  FRangeHi := -1;
  FPend := -1;
  FKeepPara := -1;
  FStartAt := AStart;
  ParseNeedle(ANeedle);
  if (FMax >= 0) and (FMax - FMin < FLen) then FNever := True;
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
  if rfoBackward in FOptions then
  begin
    // (a range being read: nothing below its top is known yet)
    if FRangeHi >= 0 then Exit(FText.ParaStart(FRangeHi) + FText.ParaLength(FRangeHi));
    if FNext >= FText.ParaCount then Exit(FText.Length);
    Exit(FText.ParaStart(FNext) + FText.ParaLength(FNext));
  end;
  if FNext >= FText.ParaCount then Exit(FText.Length);
  Result := FText.ParaStart(FNext) + FCurOff;
end;

function TTyRichFinder.ScanEnd: TTyRichPos;
begin
  Result := FText.Length;
  if (FMax >= 0) and (FMax < Result) then Result := FMax;
end;

{ The lazily read RTF file the document's text is of (nil: none), asked for once. }
function TTyRichFinder.Source: TTyRtfLoad;
begin
  if not FLoadAsked then
  begin
    FLoadAsked := True;
    FLoad := TyRichRtfLoadOf(FDoc);
  end;
  Result := FLoad;
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

{ StartBefore's character for the whole-word test (a paragraph's end: no character). }
function TTyRichFinder.BeforeCode: Cardinal;
begin
  if FStartBefore.Code = TyRichFindParaEnd then Result := CNone else Result := FStartBefore.Code;
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
        if (FCap > 0) and (FMatchCount >= FCap) then
        begin
          // as many as a caller takes at a time: the scan stands right after this one
          FStop := True;
          Result := True;
        end;
      end;
  else
    if AStart > FBest then FBest := AStart;
  end;
end;

{ The paragraph FNext is read: the scan goes on at the next one's start. }
procedure TTyRichFinder.NextPara;
begin
  Inc(FNext);
  FCurOff := 0;
  FCurByte := 0;
  FPassTo := 0;
  FK := 0;
  FPend := -1;
  // (the scan has left the paragraph: its text goes)
  FKeep := '';
  FKeepPara := -1;
  FKeepMoved := False;
end;

{ Paragraph AIndex's text, read from where the scan stands in it (FCurOff characters, FCurByte
  bytes in; up to FPassTo characters only passed, a start inside it) for as many bytes as
  FBudget allows. A match stops the walk (mode 0: the scan then stands right after it); a
  budget spent inside the paragraph keeps the matcher's state there, and the text itself
  (KeepText): the next step goes on from it without fetching the paragraph again. }
procedure TTyRichFinder.ExactPara(AIndex: Integer; AData: Pointer; AText: PByte; ALen: PtrInt;
  var AContinue: Boolean);
var
  p, q, stop, lim, first: PByte;
  k, n, ringN: Integer;
  code, prev: Cardinal;
  pos, pending: Int64;
  matchCase, whole: Boolean;

  // the scan stays in the paragraph: its text is kept for the next step (once)
  procedure KeepText;
  begin
    if (FKeepPara = AIndex) and (Pointer(AText) = Pointer(FKeep)) then Exit;
    SetLength(FKeep, ALen);
    if ALen > 0 then Move(AText^, Pointer(FKeep)^, ALen);
    FKeepPara := AIndex;
    FKeepState := FDoc.ContentState;
    FKeepBase := FRunPos;
    FKeepShift := 0;
  end;

  procedure Leave(AAt: PByte; AOff: Int64; AK: Integer; APending: Int64);
  begin
    KeepText;
    Inc(FTextBytes, AAt - first);
    Dec(FBudget, AAt - first);
    FCurByte := AAt - AText;
    FCurOff := AOff;
    FK := AK;
    FPend := APending;
    AContinue := False;
  end;

begin
  Inc(FPieces);
  if Pointer(AText) <> Pointer(FKeep) then Inc(FFetchedBytes, ALen);
  if (FCurOff = 0) and (FCurByte = 0) then
  begin
    Inc(FParasRead);
    // a paragraph of a lazily read file: its bytes there count (the reader parses them)
    k := AIndex - FSrcFirst;
    if (k >= 0) and (k < Length(FSrc)) and (FSrc[k] >= 0) then
    begin
      Inc(FFileBytes, FSrcBytes[k]);
      Dec(FBudget, FSrcBytes[k]);
    end;
    if HiddenValue(AData) then
    begin
      // not there for a find: only its length counts
      FRunPos := FRunPos + FText.ParaLength(AIndex) + 1;
      NextPara;
      Dec(FBudget, 16);
      if FBudget <= 0 then AContinue := False;
      Exit;
    end;
  end;
  matchCase := rfoMatchCase in FOptions;
  whole := rfoWholeWord in FOptions;
  ringN := FLen + 1;
  stop := AText + ALen;
  if FCurOff < FPassTo then
  begin
    { The scan begins inside the paragraph: its characters before are passed, not matched -
      an eighth of a unit a byte, and in pieces like any reading. }
    p := AText + FCurByte;
    first := p;
    // (an unbounded step's budget is near High(Int64): eight times it would not fit)
    if FBudget < (stop - p) div 8 then
    begin
      lim := p + FBudget * 8;
      if lim <= p then lim := p + 1;
    end
    else
      lim := stop;
    pos := FCurOff;
    while (pos < FPassTo) and (p < lim) do
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
      if whole then FRing[pos mod ringN] := code;
      Inc(pos);
    end;
    Dec(FBudget, (p - first) div 8 + 1);
    Inc(FPassedBytes, p - first);
    FCurByte := p - AText;
    FCurOff := pos;
    if (pos < FPassTo) and (p < stop) then
    begin
      // the budget is spent before the start: the next step passes on from here
      KeepText;
      AContinue := False;
      Exit;
    end;
  end;
  p := AText + FCurByte;
  first := p;
  if FBudget < stop - p then
  begin
    lim := p + FBudget;
    if lim <= p then lim := p + 1;
  end
  else
    lim := stop;
  pos := FCurOff;
  k := FK;
  pending := FPend;
  while p < lim do
  begin
    q := p;
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
          // (that character is read again from here)
          Leave(q, pos, 0, -1);
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
          Leave(p, pos + 1, 0, -1);
          Exit;
        end;
      end
      else
      begin
        if pos - FLen >= 0 then prev := FRing[(pos - FLen) mod ringN] else prev := CNone;
        // (a match that begins where the finder was started: what its maker saw before it)
        if FStartBefore.Known and (FRunPos + pos - FLen + 1 = FStartAt) then prev := BeforeCode;
        if not Joins(prev, FFirstChar) then
          pending := pos - FLen + 1;
      end;
      k := FKmp[k];
    end;
    Inc(pos);
  end;
  if p < stop then
  begin
    // the budget is spent inside the paragraph: the next step goes on here
    Leave(p, pos, k, pending);
    Exit;
  end;
  // the paragraph's end is no word
  if (pending >= 0) and Accept(FRunPos + pending) then
  begin
    Leave(p, pos, 0, -1);
    Exit;
  end;
  Inc(FTextBytes, p - first);
  Dec(FBudget, p - first + 16);
  FRunPos := FRunPos + pos + 1;
  NextPara;
  if (FBudget <= 0) or FStop then AContinue := False;
end;

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

{ Where the bytes of paragraphs AFirst .. (at most CSourceBatch of them, to ALast) are in the
  file: one walk, not a lookup each. }
procedure TTyRichFinder.LoadSources(AFirst, ALast: Integer);
const
  CSourceBatch = 256;
var
  i, n: Integer;
begin
  n := ALast - AFirst + 1;
  if n > CSourceBatch then n := CSourceBatch;
  if n < 1 then n := 1;
  SetLength(FSrc, n);
  SetLength(FSrcBytes, n);
  for i := 0 to n - 1 do
  begin
    FSrc[i] := -1;
    FSrcBytes[i] := 0;
  end;
  FSrcFirst := AFirst;
  FText.WalkParas(AFirst, @SourceOf);
end;

{ Reads on from paragraph FNext (and from where the scan stands in it) to ALast, a needle
  without paragraph ends, until a match stops it (mode 0), FBudget is spent, or ALast is read.
  Every paragraph is read in its text, in runs of one walk each; of a lazily read file a
  run goes as far as the paragraphs' bytes in the file are known (LoadSources: what a
  paragraph begun costs the step). }
procedure TTyRichFinder.ScanRange(ALast: Integer);
var
  cont: Boolean;
  e: Integer;
begin
  while (FBudget > 0) and not FStop and (FNext <= ALast) do
  begin
    { Inside the paragraph since an earlier step, its text kept and the content as it was:
      read on in the kept text (not fetched again). }
    if FKeepMoved then
    begin
      FKeepMoved := False;
      FKeepState := FDoc.ContentState;
    end;
    if (FKeepPara = FNext) and (FKeepState = FDoc.ContentState) and
      ((FCurByte > 0) or (FCurOff > 0)) then
    begin
      cont := True;
      // (the kept text's places: where it began, and what changed before the scan since)
      FRunPos := FKeepBase + FKeepShift;
      ExactPara(FNext, nil, PByte(Pointer(FKeep)), Length(FKeep), cont);
      Continue;
    end;
    e := ALast;
    if Source <> nil then
    begin
      if (FNext < FSrcFirst) or (FNext >= FSrcFirst + Length(FSrc)) then
        LoadSources(FNext, ALast);
      if e > FSrcFirst + High(FSrc) then e := FSrcFirst + High(FSrc);
    end;
    FRunPos := FText.ParaStart(FNext);
    FText.WalkParaTexts(FNext, e, @ExactPara, True);
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
  if FWinSrc[i] >= 0 then Inc(FFileBytes, FWinBytes[i]);
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
    // (a match that begins where the finder was started: what its maker saw before it)
    if FStartBefore.Known and (FWinStart[i] + pos - s = FStartAt) then prev := BeforeCode;
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

{ The roles, by a paragraph's length before its text is read: 1 it plays it, 0 it cannot, 2
  it may (its text will say: WindowPara); asked once, kept. }
function TTyRichFinder.WinTail(I: Integer): Boolean;
var
  s: Integer;
begin
  if FWinTail[I] < 0 then
  begin
    s := Length(FSegs[0]);
    if s = 0 then FWinTail[I] := 1
    else if FWinLen[I] < s then FWinTail[I] := 0
    else FWinTail[I] := 2;
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
    else FWinMid[K][I] := 2;
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
    else FWinHead[I] := 2;
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
  if Source = nil then Exit;
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
  one, the file's tables (a paragraph outside them is no cell merged away); only the
  paragraphs of a match that may be there are read. }
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
    for k := 1 to FParaEnds - 1 do FWinMid[k][i] := -1;
  end;
  FText.WalkParas(ALo, @WindowSource);
  // merged away or not, known without the text: from a value, or outside the file's tables
  for i := 0 to n - 1 do
    if (FWinData[i] <> nil) or (Source = nil) then
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
{ A needle with paragraph ends reads whole paragraphs: the range from ALo is cut at about ABudget
  characters, and where the file's bytes of its unparsed paragraphs pass ABudget - a picture's
  paragraph is one character and may be megabytes. At least one paragraph. }
function TTyRichFinder.WindowHi(ALo, ALast: Integer; ABudget: Int64): Integer;
var
  limit: TTyRichPos;
  i: Integer;
  bytes: Int64;
begin
  limit := FText.ParaStart(ALo) + Max64(ABudget, 1);
  if limit > FText.Length then limit := FText.Length;
  Result := FText.ParaOfPos(limit);
  if Result > ALast then Result := ALast;
  if Result < ALo then Result := ALo;
  if Source <> nil then
  begin
    LoadSources(ALo, Result);
    if Result > ALo + High(FSrc) then Result := ALo + High(FSrc);
    bytes := 0;
    for i := 0 to Result - ALo do
    begin
      if FSrc[i] >= 0 then Inc(bytes, FSrcBytes[i]);
      if (bytes > ABudget) and (i > 0) then
      begin
        Result := ALo + i - 1;
        Break;
      end;
    end;
  end;
end;

function TTyRichFinder.StepForward(ABudget: Int64): TTyRichFindResult;
var
  lo, hi, lastPara: Integer;
  endPos: TTyRichPos;
  open: Boolean;
begin
  endPos := ScanEnd;
  // a needle with paragraph ends: a match starts that many paragraphs before its end at most
  lastPara := FText.ParaOfPos(endPos) - FParaEnds;
  { A document still loading, searched to its end as it grows: its last paragraph is the one
    the load goes on from (it may still be the empty one appended last), so it waits - and the
    paragraphs a needle with paragraph ends would reach into it from. }
  open := (FMax < 0) and FDoc.Loading and FWaitOpen;
  if open then Dec(lastPara);
  if FNext < 0 then
  begin
    FNext := FText.ParaOfPos(FMin);
    // (a scan that begins inside a paragraph passes its characters before FMin first)
    FPassTo := FMin - FText.ParaStart(FNext);
    FCurOff := 0;
    FCurByte := 0;
    FK := 0;
    FPend := -1;
  end;
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
  FScanEnd := endPos;
  if FCollect then FMode := 1 else FMode := 0;
  FStop := False;
  FBest := -1;
  FBudget := Max64(ABudget, 1);
  if FParaEnds = 0 then
    ScanRange(lastPara)
  else
  begin
    lo := FNext;
    hi := WindowHi(lo, lastPara, ABudget);
    ScanWindow(lo, hi);
    if not FStop then FNext := hi + 1;
  end;
  if FStop then
  begin
    FMatchPos := FBest;
    FMin := FBest + FLen;
    // (without paragraph ends the scan stands right after the match already)
    if FParaEnds > 0 then FNext := FText.ParaOfPos(FBest);
    Exit(rfrFound);
  end;
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

{ Backward: a range of paragraphs below the last match (or the end) is read forward - over as
  many steps as its bytes take - keeping the last match in it; then the range below it. }
function TTyRichFinder.StepBackward(ABudget: Int64): TTyRichFindResult;
var
  lo, hi, first: Integer;
  endPos, limit: TTyRichPos;
begin
  endPos := ScanEnd;
  first := FText.ParaOfPos(FMin);
  if FRangeLo < 0 then
  begin
    if FNext < 0 then FNext := FText.ParaOfPos(endPos);
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
    FRangeLo := lo;
    FRangeHi := hi;
    FBest := -1;
    FNext := lo;
    FCurOff := 0;
    FCurByte := 0;
    FPassTo := 0;
    FK := 0;
    FPend := -1;
    FKeep := '';
    FKeepPara := -1;
  end;
  FScanEnd := endPos;
  FMode := 2;
  FStop := False;
  FBudget := Max64(ABudget, 1);
  if FParaEnds = 0 then
  begin
    ScanRange(FRangeHi);
    // the range is not read through yet
    if FNext <= FRangeHi then Exit(rfrMore);
  end
  else
    ScanWindow(FRangeLo, FRangeHi);
  lo := FRangeLo;
  FRangeLo := -1;
  FRangeHi := -1;
  if FBest >= 0 then
  begin
    FMatchPos := FBest;
    // the next one (backward) ends where this one begins
    FMax := FBest;
    FNext := FText.ParaOfPos(FBest);
    FBest := -1;
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

function TTyRichFinder.CollectRange(ALo, AHi: Integer; AFrom, ATo: TTyRichPos;
  ABudget: Int64; ACap: Integer): TTyRichFindResult;
begin
  Inc(FSteps);
  if FNever then Exit(rfrNotFound);
  if (FRangeLo <> ALo) or (FRangeHi <> AHi) then
  begin
    FRangeLo := ALo;
    FRangeHi := AHi;
    FNext := ALo;
    FK := 0;
    FPend := -1;
    FMatchCount := 0;
    FMin := FText.ParaStart(ALo);
    if AFrom > FMin then FMin := AFrom;
    // (a range that begins inside its first paragraph passes the characters before it first)
    FPassTo := FMin - FText.ParaStart(ALo);
    FCurOff := 0;
    FCurByte := 0;
    FKeep := '';
    FKeepPara := -1;
  end;
  FScanEnd := FText.ParaStart(AHi) + FText.ParaLength(AHi);
  if (ATo >= 0) and (ATo < FScanEnd) then FScanEnd := ATo;
  FMode := 1;
  FStop := False;
  if ABudget < 0 then FBudget := High(Int64) div 4 else FBudget := Max64(ABudget, 1);
  FCap := ACap;
  FCapped := False;
  try
    ScanRange(AHi);
  finally
    FCap := 0;
  end;
  if FStop then
  begin
    // (the range stays: the next call goes on after the last match)
    FCapped := True;
    Exit(rfrFound);
  end;
  if FNext <= AHi then Exit(rfrMore);
  FRangeLo := -1;
  FRangeHi := -1;
  if FMatchCount > 0 then Result := rfrFound else Result := rfrNotFound;
end;

procedure TTyRichFinder.Moved(ADelta: TTyRichPos; AParas: Integer);
begin
  Inc(FMin, ADelta);
  // (past its start, and the places before the scan are other ones now: nothing begins there)
  FStartBefore.Known := False;
  Inc(FNext, AParas);
  if FRangeHi >= 0 then Inc(FRangeHi, AParas);
  if FKeepPara >= 0 then
  begin
    Inc(FKeepPara, AParas);
    Inc(FKeepShift, ADelta);
    FKeepMoved := True;
  end;
  // (the walk's batch of sources is of the text before)
  SetLength(FSrc, 0);
  SetLength(FSrcBytes, 0);
end;

function TTyRichFinder.KeptBytes: Int64;
begin
  Result := Length(FKeep);
end;

function TTyRichFinder.WorkDone: Int64;
begin
  Result := FTextBytes + FFileBytes + FPassedBytes + FParasRead + FNext;
end;

{ ---- TTyRichReplaceAllCommand ---- }

var
  GRichReplaceIds: Int64 = 0;

{ A match the document lets a user's edit replace: no row that holds a nested table in the way
  (CanChange) and the table-edge rule as the keys have it (TTyRichDocument.UserRangeAllowed) - the paragraph
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

function HasBreak(const S: UTF8String): Boolean;
var
  i: Integer;
begin
  for i := 1 to Length(S) do
    if S[i] in [#10, #13] then Exit(True);
  Result := False;
end;

constructor TTyRichReplaceAllCommand.Create(ADoc: TTyRichDocument; const AFind,
  AReplace: UTF8String; AOptions: TTyRichFindOptions; AStart: TTyRichPos; ALength: TTyRichPos);
var
  len: TTyRichPos;
begin
  inherited Create;
  FTarget := ADoc;
  FFind := AFind;
  FRepl := AReplace;
  FOptions := AOptions - [rfoBackward, rfoWrap];
  FSimple := HasBreak(AFind);
  FFast := not FSimple and not HasBreak(AReplace);
  FRangeChars := CRichReplaceRangeChars;
  FHighPos := -1;
  FRedoTo := -1;
  FRangeLo := -1;
  len := ADoc.Text.Length;
  if AStart < 0 then AStart := 0;
  if AStart > len then AStart := len;
  FFrom := AStart;
  if (ALength < 0) or (ALength > len - AStart) then FTo := -1 else FTo := AStart + ALength;
  FResume := FFrom;
  Inc(GRichReplaceIds);
  FId := GRichReplaceIds;
end;

procedure TTyRichReplaceAllCommand.SetStartBefore(const AValue: TTyRichBefore);
begin
  FStartBefore := AValue;
  // (nothing replaced yet: where it would go on from is its start, with what stood before that)
  if not FStarted then FResumeBefore := AValue;
end;

{ The range's end in the text as it is now. }
function TTyRichReplaceAllCommand.RangeEnd: TTyRichPos;
begin
  if FTo < 0 then Result := FTarget.Text.Length else Result := FTo + FCharDelta;
end;

function TTyRichReplaceAllCommand.ResumeLength: TTyRichPos;
begin
  if FTo < 0 then Exit(-1);
  Result := FTo + FCharDelta - FResume;
  if Result < 0 then Result := 0;
end;

{ A search that could not get on: the walk ends there, told as Failed (what was replaced stays
  the step). }
procedure TTyRichReplaceAllCommand.Fail;
begin
  FStuck := True;
  FWalkDone := True;
  FReadyCount := 0;
  FreeAndNil(FFinder);
end;

destructor TTyRichReplaceAllCommand.Destroy;
begin
  FFinder.Free;
  inherited Destroy;
end;

function TTyRichReplaceAllCommand.Ready: Boolean;
begin
  Result := FReadyCount > 0;
end;

function TTyRichReplaceAllCommand.Finished: Boolean;
begin
  Result := (FReadyCount = 0) and (FWalkDone or FLimited);
end;

function TTyRichReplaceAllCommand.Allowed(APos: TTyRichPos): Boolean;
var
  t: TTyRichText;
  k: Integer;
begin
  if FSimple then Exit(MatchAllowed(FTarget, APos, FLen));
  { A match inside one paragraph never reaches across an edge: only its paragraph's row is
    asked, once a paragraph (a paragraph of megabytes may hold millions of matches). }
  if (APos >= FAskedFrom) and (APos < FAskedTo) then Exit(FAskedAnswer);
  t := FTarget.Text;
  k := t.ParaOfPos(APos);
  FAskedFrom := t.ParaStart(k);
  FAskedTo := FAskedFrom + t.ParaLength(k);
  FAskedAnswer := FTarget.CanChange(APos, FLen);
  Result := FAskedAnswer;
end;

procedure TTyRichReplaceAllCommand.Take(APos: TTyRichPos);
begin
  // (a redo replaces what the first run did, and only that: matches before where it ended)
  if (FRedoTo >= 0) and (APos - FCharDelta >= FRedoTo) then Exit;
  if not Allowed(APos) then
  begin
    Inc(FSkipped);
    Exit;
  end;
  if FReadyCount = Length(FReady) then SetLength(FReady, FReadyCount * 2 + 16);
  FReady[FReadyCount] := APos;
  Inc(FReadyCount);
end;

function TTyRichReplaceAllCommand.Prepare(ABudget: Int64): Boolean;
var
  mark: Int64;
  allNext, nextPara, rangeLo: Integer;
  collected: Boolean;
begin
  try
    if FFinder <> nil then mark := FFinder.WorkDone else mark := -1;
    allNext := FAllNext;
    nextPara := FNextPara;
    rangeLo := FRangeLo;
    collected := FCollected;
    Result := Search(ABudget);
    { A search with a budget always gets on: one that left everything as it was would be
      called again and again, for ever. The walk ends there instead (Failed). }
    if not Result and FStarted and (FFinder <> nil) and (FFinder.WorkDone = mark) and
      (FAllNext = allNext) and (FNextPara = nextPara) and (FRangeLo = rangeLo) and
      (FCollected = collected) then
    begin
      Fail;
      Result := True;
    end;
  finally
    // (what it left - a match the document refuses - is told even when no part runs)
    Report;
  end;
end;

function TTyRichReplaceAllCommand.Search(ABudget: Int64): Boolean;
var
  t: TTyRichText;
  limit, last, stop: TTyRichPos;
  i, k, hi: Integer;
  r: TTyRichFindResult;
  mark: Int64;
begin
  Result := True;
  if (FReadyCount > 0) or FWalkDone or FLimited or FStopped then Exit;
  t := FTarget.Text;
  // (what Allowed knew was of the text before the last part)
  FAskedFrom := 0;
  FAskedTo := 0;
  if not FStarted then
  begin
    FStarted := True;
    if FTo < 0 then FTotal := t.Length - FFrom else FTotal := FTo - FFrom;
    FNextPara := t.ParaOfPos(FFrom);
    FFinder := TTyRichFinder.Create(FTarget, FFind, FOptions, FFrom, FTo);
    FFinder.Collect := True;
    FFinder.StartBefore := FStartBefore;
    FLen := FFinder.MatchLen;
    if FFinder.Never then
    begin
      FWalkDone := True;
      FreeAndNil(FFinder);
      Exit;
    end;
  end;
  if FSimple then
  begin
    // every match first, forward
    if not FCollected then
    begin
      repeat
        mark := FFinder.WorkDone;
        if ABudget < 0 then r := FFinder.Step(1 shl 20) else r := FFinder.Step(ABudget);
        // (a step that did nothing would be taken again for ever)
        if (r = rfrMore) and (ABudget < 0) and (FFinder.WorkDone = mark) then
        begin
          Fail;
          Exit;
        end;
      until (r <> rfrMore) or (ABudget >= 0);
      if r = rfrMore then Exit(False);
      FAllCount := FFinder.MatchCount;
      SetLength(FAll, FAllCount);
      for i := 0 to FAllCount - 1 do FAll[i] := FFinder.Match(i);
      FreeAndNil(FFinder);
      FCollected := True;
      FAllNext := 0;
    end;
    { The next ones, about a range's characters of them; replaced first to last, each moved
      by what the ones before it changed (they all lie after them). }
    while FAllNext < FAllCount do
    begin
      if (FRedoTo >= 0) and (FAll[FAllNext] >= FRedoTo) then Break;
      last := FAll[FAllNext];
      k := FAllNext;
      FTarget.BeginRead;
      try
        // (the first one whatever its length: a needle may be longer than the range)
        while (k < FAllCount) and ((k = FAllNext) or (FAll[k] + FLen - last <= FRangeChars)) do
        begin
          Take(FAll[k] + FCharDelta);
          Inc(k);
        end;
      finally
        FTarget.EndRead;
      end;
      if k = FAllNext then
      begin
        Fail;
        Exit;
      end;
      FAllNext := k;
      if FReadyCount > 0 then
      begin
        FReadyState := FTarget.ContentState;
        FReadyFresh := True;
        Exit;
      end;
    end;
    FWalkDone := True;
    Exit;
  end;
  // range by range from the start: each range's matches found on the text as it is, then replaced
  repeat
    stop := RangeEnd;
    if FRangeLo < 0 then
    begin
      if (FNextPara >= t.ParaCount) or (t.ParaStart(FNextPara) + FLen > stop) or
        ((FRedoTo >= 0) and (t.ParaStart(FNextPara) - FCharDelta >= FRedoTo)) then
      begin
        FWalkDone := True;
        FreeAndNil(FFinder);
        Exit;
      end;
      FRangeLo := FNextPara;
      limit := t.ParaStart(FNextPara) + FRangeChars;
      if limit > stop then limit := stop;
      hi := t.ParaOfPos(limit);
      if hi < FRangeLo then hi := FRangeLo;
      FRangeHi := hi;
    end;
    { At most a part's matches at a time: a range is at least a paragraph, and one paragraph
      may hold millions (a one-line file) - a list of all of them would cost what the step's
      record saves. The finder then stands after the last one, in the paragraph's text it
      keeps, and goes on from there after the part (Moved). }
    r := FFinder.CollectRange(FRangeLo, FRangeHi, FFrom, stop, ABudget, CRichReplacePartMatches);
    if r = rfrMore then Exit(False);
    // (one read scope for the range's checks: the loader trims once, when it ends)
    FTarget.BeginRead;
    try
      for k := 0 to FFinder.MatchCount - 1 do Take(FFinder.Match(k));
    finally
      FTarget.EndRead;
    end;
    FFinder.ClearMatches;
    FRangeParas := t.ParaCount;
    FRangeOpen := FFinder.Capped;
    if not FRangeOpen then FRangeLo := -1;
    if FReadyCount > 0 then
    begin
      FReadyState := FTarget.ContentState;
      FReadyFresh := True;
      Exit;
    end;
    // a range with nothing to replace: the walk goes on after it (or in it, after its last)
    if not FRangeOpen then FNextPara := FRangeHi + 1;
    // (a bounded search goes on in the next call: the range read was its piece)
  until ABudget >= 0;
  Result := False;
end;

procedure TTyRichReplaceAllCommand.Apply(ADoc: TTyRichDocument);
var
  i, k, r, para, left, n0, n: Integer;
  t: TTyRichText;
  runs: TTyRunArray;
  off, len0, d, p: TTyRichPos;
  fmt: TTyCharFormatId;
  last: TTyRichCodeArray;
  back: Boolean;
begin
  if FReadyCount = 0 then Exit;
  // (the first part of what a search found; the next ones only follow its own: ExecutePart)
  if FReadyFresh and (ADoc.ContentState <> FReadyState) then
    raise ETyRichModel.Create('The text changed between a replace''s search and its run');
  FReadyFresh := False;
  n0 := RecordCount;
  t := ADoc.Text;
  len0 := t.Length;
  { At most CRichReplacePartMatches a part, the first ones: those after them wait for the next
    part, moved by what this one changed - a paragraph of megabytes with matches all through
    it is replaced in parts too. }
  n := FReadyCount;
  if n > CRichReplacePartMatches then n := CRichReplacePartMatches;
  { What stands right before the place this part ends at, while it is still there: the last
    character of its last match - how the walk sees the boundary of a match that begins right
    behind it (ResumeBefore). }
  last := TyRichFindCodes(t.GetText(FReady[n - 1] + FLen - 1, 1));
  FResumeBefore.Known := Length(last) = 1;
  if FResumeBefore.Known then FResumeBefore.Code := last[0];
  if FFast then
  begin
    left := 0;
    ReplaceInParas(ADoc, FReady, 0, n, FLen, FRepl, left);
    Inc(FReplaced, n - left);
    Inc(FSkipped, left);
  end
  else if not FSimple then
  begin
    { The ordinary edits, a delete and an insert a match. Their order is chosen for what an
      edit costs in the text storage: it makes its place a boundary of the paragraph's pieces
      of text, found by counting characters from the start of the piece the place is in. From
      the last match back, every edit of a part would count from the start of the same long
      piece - the part's matches times the stretch they lie in, and times the whole line
      before them where the part's first match is far into a long paragraph. So the first
      match goes first: the piece it leaves behind starts at it. Then, where the part's
      matches lie close together (CRichReplaceBackSpan), from the last back - each counts that
      short stretch at most, and the paragraphs the replacements make come to lie behind the
      place being edited, which the text's tree takes best; farther apart, from the first on,
      each counting only the characters between two matches. (A match lies inside one
      paragraph and takes the format of its first character's run: the order changes nothing
      else.) }
    back := FReady[n - 1] - FReady[0] <= CRichReplaceBackSpan;
    d := 0;
    for k := 0 to n - 1 do
    begin
      if back and (k > 0) then i := n - k else i := k;
      // (its place: moved by every one before it - from the last back, by the first alone)
      if not back then d := t.Length - len0;
      p := FReady[i] + d;
      para := t.ParaOfPos(p);
      off := p - t.ParaStart(para);
      runs := ADoc.RunsOf(para);
      r := High(runs);
      while (r > 0) and (runs[r].Start > off) do Dec(r);
      if r >= 0 then fmt := runs[r].Format else fmt := ADoc.TypingFormatAt(p);
      DeleteRange(ADoc, p, FLen);
      if FRepl <> '' then InsertText(ADoc, p, FRepl, fmt);
      Inc(FReplaced);
      if k = 0 then d := t.Length - len0;
    end;
  end
  else
    // a needle with a paragraph end: the ordinary edits, the last first
    for i := n - 1 downto 0 do
    begin
      para := t.ParaOfPos(FReady[i]);
      off := FReady[i] - t.ParaStart(para);
      if off < t.ParaLength(para) then
      begin
        // the first character replaced: its run's format
        runs := ADoc.RunsOf(para);
        r := High(runs);
        while (r > 0) and (runs[r].Start > off) do Dec(r);
        if r >= 0 then fmt := runs[r].Format else fmt := ADoc.TypingFormatAt(FReady[i]);
      end
      else
        // a paragraph's end: what typing there gets
        fmt := ADoc.TypingFormatAt(FReady[i]);
      DeleteRange(ADoc, FReady[i], FLen);
      if FRepl <> '' then InsertText(ADoc, FReady[i], FRepl, fmt);
      Inc(FReplaced);
    end;
  // where the first run ended, in the text it began on (what a redo replays to)
  FHighPos := FReady[n - 1] + FLen - FCharDelta;
  d := t.Length - len0;
  { Behind the last match of the part, in the text as it is now: everything the part changed
    lies before that place, so it moved by all of it. }
  FResume := FReady[n - 1] + FLen + d;
  Inc(FCharDelta, d);
  // the others of the range, after what changed: moved by it
  for i := n to FReadyCount - 1 do FReady[i - n] := FReady[i] + d;
  Dec(FReadyCount, n);
  // the range done: the walk goes on after it (and after the paragraphs a replacement made)
  if (FReadyCount = 0) and not FSimple then
    if FRangeOpen and (FFinder <> nil) then
    begin
      // not read through: its finder goes on where it stood, moved by what the part changed
      FFinder.Moved(d, t.ParaCount - FRangeParas);
      Inc(FRangeHi, t.ParaCount - FRangeParas);
      FRangeParas := t.ParaCount;
    end
    else
      FNextPara := FRangeHi + 1 + (t.ParaCount - FRangeParas);
  Inc(FRecBytes, RecordsSize(n0));
  // the limit (not for a redo: it replays what the first run did)
  if (FRedoTo < 0) and (ADoc.MaxUndoBytes > 0) and
    (MemSize >= CRichReplaceLimitFactor * ADoc.MaxUndoBytes) and not Finished then
  begin
    FLimited := True;
    FReadyCount := 0;
    FreeAndNil(FFinder);
  end;
end;

procedure TTyRichReplaceAllCommand.Report;
begin
  if FTally = nil then Exit;
  FTally^.Replaced := FReplaced;
  FTally^.Skipped := FSkipped;
  FTally^.Limited := FLimited;
  FTally^.Failed := FStuck;
  FTally^.ResumeAt := FResume;
  FTally^.ResumeLength := ResumeLength;
  FTally^.ResumeBefore := FResumeBefore;
end;

procedure TTyRichReplaceAllCommand.Run(ADoc: TTyRichDocument);
begin
  if FAllAtOnce then
    repeat
      Prepare(-1);
      Apply(ADoc);
    until Finished
  else
  begin
    // (a caller that did not prepare: the next part found now)
    if FReadyCount = 0 then Prepare(-1);
    Apply(ADoc);
  end;
end;

procedure TTyRichReplaceAllCommand.DoExecute(ADoc: TTyRichDocument);
begin
  try
    Run(ADoc);
  finally
    Report;
  end;
end;

procedure TTyRichReplaceAllCommand.DoContinue(ADoc: TTyRichDocument);
begin
  try
    Run(ADoc);
  finally
    Report;
  end;
end;

procedure TTyRichReplaceAllCommand.DoUndo(ADoc: TTyRichDocument);
begin
  inherited DoUndo(ADoc);
  // the records are reverted and go: nothing is kept for them any more
  FRecBytes := 0;
  // (undone, the walk cannot go on: a redo starts it again from the range's start)
  LetGo;
end;

procedure TTyRichReplaceAllCommand.Covered;
begin
  LetGo;
end;

procedure TTyRichReplaceAllCommand.LetGo;
begin
  FreeAndNil(FFinder);
  FReady := nil;
  FReadyCount := 0;
  FAll := nil;
  FAllCount := 0;
  FAllNext := 0;
  FRangeOpen := False;
  FRangeLo := -1;
  // (through its range, at the limit or failed it has ended already: that stays what it is)
  if not (FWalkDone or FLimited) then FStopped := True;
end;

function TTyRichReplaceAllCommand.HeldBytes: Int64;
begin
  Result := (Length(FReady) + Length(FAll)) * SizeOf(TTyRichPos);
  if FFinder <> nil then Inc(Result, FFinder.KeptBytes);
end;

procedure TTyRichReplaceAllCommand.DoRedo(ADoc: TTyRichDocument);
var
  highPos: TTyRichPos;
  wasLimited, wasDone: Boolean;
begin
  // what the first run replaced, again: the same walk, to where the first run ended
  // (and told to nobody: the tally was the first run's caller's)
  FTally := nil;
  highPos := FHighPos;
  wasLimited := FLimited;
  wasDone := FWalkDone;
  FreeAndNil(FFinder);
  FStarted := False;
  FWalkDone := False;
  FStopped := False;
  FLimited := False;
  FCollected := False;
  FReadyCount := 0;
  FAllCount := 0;
  FAll := nil;
  FRangeLo := -1;
  FRangeOpen := False;
  FCharDelta := 0;
  FReplaced := 0;
  FSkipped := 0;
  FRecBytes := 0;
  FRedoTo := highPos;
  try
    if highPos >= 0 then
      repeat
        Prepare(-1);
        Apply(ADoc);
      until Finished;
  finally
    FRedoTo := -1;
    FHighPos := highPos;
    // as the first run ended: through its range, at the limit - or stopped before either
    FWalkDone := wasDone or FStuck;
    FLimited := wasLimited;
    FStopped := not (FWalkDone or FLimited);
    FreeAndNil(FFinder);
  end;
end;

function TTyRichReplaceAllCommand.Description: string;
begin
  Result := rsRichUndoReplace;
end;

function TTyRichReplaceAllCommand.MemSize: Int64;
begin
  Result := InstanceSize + FRecBytes + RecordCount * SizeOf(Pointer) +
    (Length(FReady) + Length(FAll)) * SizeOf(TTyRichPos) + Length(FFind) + Length(FRepl);
end;

procedure TTyRichReplaceAllCommand.Progress(out ADone, ATotal: Int64);
var
  t: TTyRichText;
  at: TTyRichPos;
begin
  t := FTarget.Text;
  if not FStarted then
  begin
    if FTo < 0 then ATotal := t.Length - FFrom else ATotal := FTo - FFrom;
    if FSimple then ATotal := 2 * ATotal;
    ADone := 0;
    Exit;
  end;
  ATotal := FTotal;
  if FSimple then
  begin
    ATotal := 2 * FTotal;
    if not FCollected then
    begin
      if FFinder <> nil then ADone := FFinder.Reached - FFrom else ADone := 0;
      if ADone < 0 then ADone := 0;
      if ADone > FTotal then ADone := FTotal;
      Exit;
    end;
    // the replacing, from the start on
    if Finished or (FAllNext >= FAllCount) then ADone := ATotal
    else ADone := FTotal + FAll[FAllNext] - FFrom;
    if ADone > ATotal then ADone := ATotal;
    Exit;
  end;
  // where the walk stands, in the text it began on: what lies before it is done
  if Finished then
    ADone := ATotal
  else
  begin
    if FReadyCount > 0 then at := FReady[0]
    else if FRangeOpen and (FFinder <> nil) then at := FFinder.Reached
    else if FRangeLo >= 0 then at := t.ParaStart(FRangeLo)
    else if FNextPara < t.ParaCount then at := t.ParaStart(FNextPara)
    else at := t.Length;
    ADone := at - FCharDelta - FFrom;
  end;
  if ADone < 0 then ADone := 0;
  if ADone > ATotal then ADone := ATotal;
end;

end.
