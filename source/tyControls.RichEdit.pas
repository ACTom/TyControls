unit tyControls.RichEdit;

{ TTyRichEdit: a rich text editor, drawn by the package itself on every platform. It shows a
  document - txt or RTF, of any size - scrolls, zooms and wraps it, and edits it by keyboard:
  typing, Backspace, Delete, Enter, Tab, undo and redo, cut, an input method's
  composition shown in the text and committed as typing, paste, tables (a new table, rows
  and columns inserted and deleted, Tab from cell to cell), pictures (inserted from code,
  resized by the handles of a selected one), the selection dragged to another place by the
  mouse (moved, or copied with Ctrl: DragDropEditing, the receiving side DropEnter .. DropOn),
  also into another TTyRichEdit of the application (two documents: one undo step in each),
  and drops from other programs (AcceptDrops, OnDropFiles; the Windows widgetset only, in
  tyControls.RichEdit.OleDrop).
  Every
  edit is a command of the document (Document.Execute),
  so all of it can be undone; ReadOnly turns the user's editing off and leaves a viewer, while
  code still changes the document through its commands, Lines and the editing methods.

  An edit the control makes places the caret itself, after the command ran (FinishEdit): the
  change the document reports moves neither the caret nor the anchor by arithmetic, and the
  action reports one OnChange and one OnSelectionChange. A change made elsewhere (code, a
  load) moves them by arithmetic, as a viewer's (DocChanged).

  The layers under it (tyControls.RichEdit.*): the text storage with its paragraph and height
  index, the document model and its commands, txt and RTF reading and writing, and the layout
  (blocks: a paragraph or a table row, laid out at a width, PPI and zoom, painted into a
  bitmap). The control owns a document, a layouter and the layouter's device.

  What makes it usable on a 100 MB file is that nothing here walks the document:
  - Scrolling is on the text storage's height index. Every paragraph has a height, measured
    once it was laid out, or the layouter's one-line estimate. The view is ANCHORED: its truth is
    (the block at its top, how many of that block's pixels are above it), and the scroll bar's
    position is derived from the heights above that block. So when laying out blocks corrects
    the estimates above or around the view, the text on screen does not move; the scroll bar's
    range and thumb follow. A table row is one block: its height is written on its first
    paragraph and 0 on the others.
  - Only what is seen is laid out: the visible blocks, one screen ahead and one behind, in one
    read scope of the document per pass. Those blocks are kept (with a reference each) until the
    view moves; a jump lays out only around its target. A width, zoom, PPI or base font change
    makes every height an estimate again (UnmeasureAll: no pass over the document) and keeps the
    anchor.
  - A change of the document is forwarded to the layouter, and invalidates only the rectangles
    of the blocks it changed - and what lies below them only when their height changed.
  - The control keeps one bitmap of what it shows (the surface, see "the kept surface" below):
    a paint draws on it only what is out of date and copies the clip's part to the window. Two
    doors lead to a repaint. InvalidateContent (client pixels, clipped to the text) says what
    is SHOWN changed there: that part of the surface is drawn again, then blitted. The plain
    window invalidation, InvalidateArea, only asks for a blit: for what is drawn over the blit
    after it (a caret), and for a scroll, which moves the surface's pixels itself.
  - Loading never waits on the size: a txt file is the one proportional scan (TyRichLoadText);
    an RTF file is indexed in slices (TTyRtfLoad.Step) in turns of a few milliseconds
    (BackgroundTurn), one per pass of the application's loop or a timer's tick, by widgetset
    (TTyRichTurnDriver), the document readable meanwhile (Loading); FinishLoading runs the
    rest at once. Pictures are
    decoded and scaled the same way, one a turn, never inside a paint that scrolls (the paint
    leaves an empty box and asks for them).

  Neither the RTF reader nor the txt reader keeps the stream: the RTF load holds the file's bytes
  in memory (what the document parses on demand from), the txt load holds the UTF-8 text or its
  conversion. So LoadFromStream reads the stream to its end and lets it go, and a document saved
  over the very file it was read from stays readable: SaveToFile writes a temporary file beside
  the target and puts it in the target's place only when the save completed.

  Bidirectional text is not laid out; a right-to-left control puts its vertical
  scroll bar on the left and keeps the text left to right. }

{$mode objfpc}{$H+}
{$modeswitch nestedprocvars}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Types, Math, Controls, Graphics, Forms, ExtCtrls, LCLType, LCLIntf,
  LMessages, LCLPlatformDef, LazMethodList, StdCtrls, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.StyleModel, tyControls.Painter, tyControls.Base,
  tyControls.ScrollBar, tyControls.TextMenu, tyControls.Controller,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.TextIO, tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite,
  tyControls.RichEdit.Layout, tyControls.RichEdit.Attrs, tyControls.RichEdit.Find,
  tyControls.RichEdit.Bookmarks, tyControls.RichEdit.Builder, tyControls.RichEdit.TableSel,
  tyControls.RichEdit.RowFormat, tyControls.RichEdit.TableProps, tyControls.RichEdit.Grid;

const
  CRichZoomMin = 10;
  CRichZoomMax = 500;
  { Ctrl + one wheel notch. }
  CRichZoomStep = 10;
  { The tallest AutoHeight makes the control, in device pixels: a window, and the LCL's
    layout, fail far above it (a height of about 112,000 raises in SetBounds). A page
    longer than this keeps this height; a document that long belongs in a control that
    scrolls itself. }
  CRichAutoHeightLimit = 32000;
  { ContentHeight measures a document of at most this many paragraphs whole (a page built
    from code, a help page): its answer is then exact. A larger one answers the estimate. }
  CRichContentExactParas = 10000;
  { The most a scroll bar is given as its range: a document taller than this (in pixels) is
    scrolled in steps of more than one pixel per bar unit (see TTyCustomRichEdit.ScrollBarLimit). }
  CRichScrollBarRange = 1 shl 30;
  { The background work (load slices, pictures) a turn does at most, in milliseconds. }
  CRichIdleBudgetMs = 8;
  { ... and at most this many pieces of it (load slices, pictures): a cap that holds whatever
    the clock's resolution is. }
  CRichIdleMaxSteps = 3;
  { One load slice: bytes of RTF indexed per step, at most. }
  CRichLoadStepBytes = 256 * 1024;
  { ... and at least: a load's turns start their slices at this size and double them while
    turns are fast, halve them while they are slow (TTyCustomRichEdit.SliceBytes). }
  CRichLoadMinStepBytes = 16 * 1024;
  { rtdIdle's backstop: while there is work, a timer of this period runs one turn when no
    turn ran since its last tick - for an application whose idle step never comes or never
    reaches the idle handlers (an Application.OnIdle that sets Done := False, a flood of
    messages). In the normal case a tick costs one comparison. }
  CRichBackstopMs = 50;
  { While a load runs, what its own turns change of the scroll bars reaches the bars at most
    once in this many milliseconds (by the turns' clock), and always when the load ends:
    a bar repaints itself whole on every change of its range (about 8 ms), more than a turn's
    work, while its thumb, at its smallest size, does not move. }
  CRichLoadBarsMs = 100;
  { FinishLoading's slice: the progress event fires and a cancel acts every this many bytes. }
  CRichFinishStepBytes = 4 * 1024 * 1024;
  { The kept surface is made in blocks of this many raster pixels: a resize does not make it
    again at every pixel. }
  CRichSurfaceBlock = 64;
  { The most rectangles the surface keeps as dirty; more are merged (see MarkDirty). }
  CRichDirtyMax = 8;
  { The caret's half period, as the memo blinks it (TTyCustomMemo.EnsureBlinkTimer). }
  CRichBlinkMs = 530;
  { How often a drag held outside the text scrolls (milliseconds). }
  CRichDragScrollMs = 50;
  { Characters on either side of a position that a word is looked for in: a "word" longer
    than this (a line of 100,000 letters) is cut there. }
  CRichWordWindow = 4096;
  { A copy of more characters than this shows the wait cursor while it is made. }
  CRichCopyWaitChars = 1000000;
  { What a paragraph laid out counts as against CopyWaitChars (DistributeRows): a layout costs
    about what a hundred characters copied do. }
  CRichLayoutParaChars = 100;
  // a cell index past any row's last: every cell of the rows (a property edit cuts it to each)
  CRichAllCells = 1 shl 20;
  { A background find's piece: units of a finder's step at most, and at least (bytes of text
    read, bytes of a file's unparsed paragraph lexed, a picture's bytes passed over at a
    sixteenth: TTyRichFinder.Step - a paragraph larger than a piece is read in pieces) - a
    find's turns start at the least and double their pieces while turns are fast, halve them
    while slow, as a load's slices do. }
  CRichFindStepChars = 1024 * 1024;
  CRichFindMinStepChars = 16 * 1024;
  { A background replace's piece: matches replaced at most, and at least (the same rule). }
  CRichReplaceBatch = 4096;
  CRichReplaceMinBatch = 16;
  { The budget of one read of ConsistentAttributes (SelAttributes' and Paragraph's):
    at most this many units of work - a run looked at, or a paragraph whose format alone is
    (a paragraph counts at least one; runs, not paragraphs, so that resident
    paragraphs of many runs cost what plain ones cost) -, and at most this many bytes of a
    lazily read file parsed for it (a parse already begun is finished; the first paragraph
    is always read). Measured (Select All + the first read, -O2): 21-23 ms over 20,000
    resident paragraphs of 50 runs each, 23-24 ms on the 100 MB txt, 31 ms on the 100 MB
    RTF read lazily (its 192 KB of parsing) - a run costs about what a plain paragraph
    costs, 0.17 us. A selection larger than that is answered with a
    lower bound: every attribute not proven the same within the budget is "not
    consistent". }
  CRichConsistWork = 130000;
  CRichConsistParseBytes = 192 * 1024;
  { The most paragraphs CanFormatCharacters / CanFormatParagraphs look at (from the
    selection's first): a few look-ups each, so the queries stay within a keystroke over any
    selection; past them the answer is True and the door's own check tells. }
  CRichFormatQueryParas = 1024;
  { The most bytes of image a picture is made from (a paste, TyRichMakePicture): 128 MB. With
    CRichPictureMaxPixels (32 Mi pixels: the most the layouter decodes - a bigger picture
    would only ever show as a placeholder - and 128 MB once decoded) it bounds what one paste
    makes the process hold: the bytes, their decoded pixels while a PNG is made of them, and
    the picture the document and its undo step keep. }
  CRichPictureMaxBytes = 128 * 1024 * 1024;
  { Where a user's edit leaves the caret or the anchor (TTyRichEditPlace, RunUserEdit), when
    not at a position: behind what the document reports the edit changed (the end of its
    change: behind typed text, at the join of a deletion), or where it is (the edit moved the
    caret and the anchor by the text's arithmetic only - a format change leaves them). }
  CRichPlaceChangeEnd = -1;
  CRichPlaceStays = -2;
  { The side of a selected picture's handle in pixels at 96 PPI: it follows the screen's PPI
    (and its device scale), never Zoom - a handle is the control's, not the document's - and
    is made odd, so that it is centred on the frame's pixel. }
  CRichObjectHandleDip = 7;
  { The least a side of an object a handle resizes may be, in twips (20 pixels at 100 %):
    room for its handles to stay apart and grabbable. }
  CRichObjectMinTwips = 300;
  { The most either side may be, in twips: 22 inches, Word's limit. The width is held to the
    room at the object's place as well (the page's text width, or its cell's), when the text
    wraps. }
  CRichObjectMaxTwips = 31680;

type
  ETyRichEdit = class(Exception);

  { Where a user's edit leaves the selection (TTyCustomRichEdit.RunUserEdit): Anchor .. Caret,
    each a position in the text after the edit or CRichPlaceChangeEnd / CRichPlaceStays (an
    Anchor of CRichPlaceChangeEnd is the caret: no selection); AtLineEnd the caret's affinity
    at a line's end. ByGrowth: the two positions were taken in the text before the edit and
    move by what the edit added to its length (behind what a paste put at a place).
    CompositionEnded (read only): the door ended an open composition just before it asked for
    the command - its commit changed the text, and what was read of it before is out of date. }
  TTyRichEditPlace = record
    Anchor, Caret: TTyRichPos;
    AtLineEnd, ByGrowth: Boolean;
    CompositionEnded: Boolean;
  end;

  { Makes the command of a user's edit when RunUserEdit asks for it, from the text and the
    selection as they are then; nil: none (refused - told through EditRefused - or nothing to
    do). APlace says where the edit leaves the selection (see TTyRichEditPlace). }
  TTyRichEditMaker = function(var APlace: TTyRichEditPlace): TTyRichCommand of object;

  { What a stream holds: rfAuto finds out (RTF when it starts with the RTF signature, after an
    optional UTF-8 BOM and white space; anything else is text). RTF, found or named, may have
    such bytes before its signature: they are kept and saved back in front of it. }
  TTyRichFormat = (rfAuto, rfRtf, rfText);

  { Loading: bytes of the file indexed; saving: paragraphs written (RTF) or characters (text).
    ACancel True stops it - a cancelled save leaves the file as it was. }
  TTyRichProgressEvent = procedure(Sender: TObject; ADone, ATotal: Int64;
    var ACancel: Boolean) of object;

  { An edit the user asked for (a key, the menu) was not made; AReason says why. }
  TTyRichEditRefusedEvent = procedure(Sender: TObject; const AReason: string) of object;

  { A click on a link (TTyCustomRichEdit.OnLinkClick): AURL is its target, AButton the button
    the click was made with. }
  TTyRichLinkClickEvent = procedure(Sender: TObject; const AURL: string;
    AButton: TMouseButton) of object;

  { Before the control follows a link to a bookmark of its document (TTyCustomRichEdit's
    FollowBookmarkLinks): AName the bookmark's; AAllow False stays where it is. }
  TTyRichFollowLinkEvent = procedure(Sender: TObject; const AName: string;
    var AAllow: Boolean) of object;

  { What a click or a double click on an object of the document tells
    (TTyCustomRichEdit.OnObjectClick, OnObjectDblClick). A record so that a member added later
    breaks no handler: read the members a handler needs, never build one.
    RichObject: the object (a picture, a block that shows one, another block with a width) -
    good during the call (a reference is held for it); one kept past it takes a reference of
    its own (AddRef). Pos: its character's position in the document. Button, Shift: the
    mouse button and the keys. Point: where the button went down (a double click's second
    press, a click's release), client pixels. Bounds: the object's box, client pixels - Point
    is inside it. }
  TTyRichObjectClick = record
    RichObject: TTyRichObject;
    Pos: TTyRichPos;
    Button: TMouseButton;
    Shift: TShiftState;
    Point: TPoint;
    Bounds: TRect;
    { Point inside a picture of AWidth x AHeight pixels shown in Bounds (an image map: which
      part of the picture was clicked), clamped to the picture. }
    function PointInPicture(AWidth, AHeight: Integer): TPoint;
  end;

  { A click or a double click on an object: AClick says which, where and how (see
    TTyRichObjectClick). AHandled True: what the control would still do with the press does
    not happen. }
  TTyRichObjectClickEvent = procedure(Sender: TObject; const AClick: TTyRichObjectClick;
    var AHandled: Boolean) of object;

  { A field around a place the control has read: its open mark's place, its close mark's (-1
    not known), how deep it is (-1 not known), whether it is a link and its target. }
  TTyRichKnownField = record
    Open, Close: TTyRichPos;
    Depth: Integer;
    Link: Boolean;
    URL: string;
    Used: Int64;   // when it was last asked for
  end;

  { What a background search runs: a find (FindNextAsync) or a replace (ReplaceAllAsync). }
  TTyRichFindTask = (rftFind, rftReplace);
  { After each piece of a background find or replace (ATask says which): ADone of ATotal
    characters of the range it searches, in the text it began on. ACancel True stops it. }
  TTyRichFindProgressEvent = procedure(Sender: TObject; ATask: TTyRichFindTask;
    ADone, ATotal: Int64; var ACancel: Boolean) of object;

  { How a find ended. rfeFound: a match (selected, in view); rfeNotFound: none; rfeCancelled:
    stopped before its end - CancelFind, the progress handler, a second start (also FindNext,
    ReplaceAll), a change of the document (an edit, an undo, a new content: a load, Clear,
    Lines.Text). }
  TTyRichFindEnd = (rfeFound, rfeNotFound, rfeCancelled);
  { A find in the background ended (FindNextAsync): AEnd says how; found, the match is
    [APos, APos + ALen) (characters - the selection may hold more: a whole cluster), otherwise
    APos is -1 and ALen 0. Raised once for every find started, unless the control is destroyed. }
  TTyRichFindDoneEvent = procedure(Sender: TObject; AEnd: TTyRichFindEnd;
    APos, ALen: TTyRichPos) of object;

  { How a replace of every match ended. rreDone: it went through its range (none replaced
    included); rreCancelled: stopped before its end - CancelFind, the progress handler, a
    second start, a change of the document it did not make (an edit, an undo, a new content -
    also an edit undone again, or its own step undone and redone, before its next turn),
    a save (its saved point would end the step), its step let go by the history (ClearUndo,
    the byte limit, the redo side dropped; by a handler too); rreLimit: its
    undo step reached its limit (four times Document.MaxUndoBytes); rreFailed: it could not go
    on (a guard against a walk that makes no progress - not an ordinary end). }
  TTyRichReplaceEnd = (rreDone, rreCancelled, rreLimit, rreFailed);
  { What a replace of every match did (ReplaceAll, and OnReplaceDone for ReplaceAllAsync).
    Replaced: matches replaced - one undo step, also when it did not get through; Skipped: left
    as they were because the document would not let a user's edit change them there.
    ResumeAt, unless Ending is rreDone: right behind the last match it dealt with, in the text
    as it is when told (an edit made since a background replace's last part is counted in);
    ReplaceAll from there for ResumeLength characters (-1: to the text's end) replaces the
    rest, and nothing twice - also when a replacement holds the needle. Whole word: started
    exactly there with the text unchanged, it also replaces a match that touches the last one
    replaced, as one run does (the control remembers how that run saw the place); after any
    edit, or from another start, such a match is judged by the text as it is. -1 when nothing
    is left, or the text it ran on is gone (a new content). }
  TTyRichReplaceResult = record
    Ending: TTyRichReplaceEnd;
    Replaced, Skipped: Integer;
    ResumeAt, ResumeLength: TTyRichPos;
  end;
  { A replace in the background ended (ReplaceAllAsync): AResult says how and what it did.
    Raised once for every replace started, unless the control is destroyed. }
  TTyRichReplaceDoneEvent = procedure(Sender: TObject;
    const AResult: TTyRichReplaceResult) of object;

  // what runs in the background besides the load and the pictures (internal)
  TTyRichFindKind = (rfkNone, rfkFind, rfkReplace);
  // how a find or a replace stops (internal: told as a TTyRichFindEnd or TTyRichReplaceEnd)
  TTyRichFindStop = (rfsFound, rfsNotFound, rfsDone, rfsCancelled);
  { (internal) A frame on the stack that wants to know whether the control was freed meanwhile
    - by a handler of its find or replace events: the destructor marks every one Gone.
    Handler: the frame around a call of such a handler (the application's code is above it);
    the others are the public calls' and the turn's. }
  PTyRichLife = ^TTyRichLife;
  TTyRichLife = record
    Gone: Boolean;
    Handler: Boolean;
    { How many of the application's handlers (any control's) were running when the frame
      began: frames of two depths have the application's code between them. }
    Depth: Integer;
    Next: PTyRichLife;
  end;
  { (internal) The work a frame of the control's runs (TTyCustomRichEdit.Guard), or the
    application's handler it calls (CallHandler). }
  TTyRichGuarded = procedure is nested;
  { (internal) The command of a synchronous ReplaceAll, on that call's stack: the reference is
    taken away when the command is freed under the call (ReplaceCommandFreed). }
  PTyRichSyncReplace = ^TTyRichSyncReplace;
  TTyRichSyncReplace = record
    Cmd: TTyRichReplaceAllCommand;
    Next: PTyRichSyncReplace;
  end;
  { (internal) Raised where a handler freed the control, so that nothing of it is touched any
    more. It never passes through the application's code: it is raised after a handler has
    returned, and unwinds the control's own frames up to the public call (or the turn) that
    lies below them, which returns - also a public call made from inside a handler: that one
    returns to the handler, and the frame around the handler raises again when the handler
    has returned (TyRichGonePasses). }
  ETyRichGone = class(EAbort);

  { The clipboard's flavours a paste takes, in the order it takes them. HTML is none of them:
    a clipboard with HTML and text pastes the text. }
  TTyRichClipFlavour = (rcfRtf, rcfPicture, rcfText);
  TTyRichClipFlavours = set of TTyRichClipFlavour;
  TTyRichClipFormats = array of TClipboardFormat;
  { What PasteFromClipboard takes: rpaBest the first flavour there that can be used (RTF, a
    picture, text); the others that one alone ("paste as plain text"). }
  TTyRichPasteAs = (rpaBest, rpaRtf, rpaPicture, rpaText);
  { The bytes of an image as they come: a PNG, JPEG or TIFF file, a BMP file, a DIB (a BMP
    without its file header, Windows' CF_DIB). }
  TTyRichImageKind = (rikPng, rikDib, rikBmp, rikTiff, rikJpeg);
  { TyRichMakePicture's answer: made; the bytes are no image it can decode; the image is over
    the bounds (CRichPictureMaxBytes, CRichPictureMaxPixels). }
  TTyRichPictureMade = (rpmMade, rpmNoImage, rpmTooLarge);

  { The eight handles of a selected object that can be resized: its corners and the middles
    of its sides, clockwise from the top left. }
  TTyRichHandle = (rhTopLeft, rhTop, rhTopRight, rhRight, rhBottomRight, rhBottom,
    rhBottomLeft, rhLeft);
  TTyRichHandleRects = array[TTyRichHandle] of TRect;

  { A drag of a handle is about to resize AObject to AWidthTwips x AHeightTwips (its new
    display size): change them to constrain it, or set AAllow False to let nothing happen. }
  TTyRichObjectResizeEvent = procedure(Sender: TObject; AObject: TTyRichObject;
    var AWidthTwips, AHeightTwips: Integer; var AAllow: Boolean) of object;

  TTyCustomRichEdit = class;

  { What a drop does (TTyCustomRichEdit's receiving side): nothing - "not here" -, a move
    (the content leaves its place) or a copy. }
  TTyRichDropEffect = (rdeNone, rdeMove, rdeCopy);
  TTyRichDropEffects = set of TTyRichDropEffect;

  { What a drop offers the control (TTyCustomRichEdit.DropEnter .. DropOn): content in the
    flavours a paste takes, read only when the drop goes in, and where it comes from. A
    control's own selection (Source the control itself, SourceRange the selection) goes in by
    TTyRichMove / TTyRichCopy; any other offer as a paste of its flavours does, in the
    paste's order (RTF, then a picture, then the text). Who gives the offer (the control's
    own drag, the platform's drag, another control) owns it, and frees it after DropLeave or
    DropOn. The defaults offer nothing. }
  TTyRichDropOffer = class
  public
    function Flavours: TTyRichClipFlavours; virtual;
    function ReadRtf: RawByteString; virtual;
    { As TTyCustomRichEdit.ReadClipboardPicture: the picture formats in the order they are
      tried (AIndex 0, 1, ...), False past the last, ABytes nil when that one is not there. }
    function ReadPicture(AIndex: Integer; out AKind: TTyRichImageKind;
      out ABytes: TBytes): Boolean; virtual;
    function ReadText: string; virtual;
    { A list of files (another program's: Explorer's), their full names in the order given;
      nil when the offer is no file list. A file list is taken as pictures, or by the
      application (TTyCustomRichEdit.OnDropFiles), never as a paste of its flavours. }
    function Files: TStringArray; virtual;
    { It comes from outside the application (another program's drag through the system): the
      control's AcceptDrops governs it. False by default - an offer of the application's
      own, fed in through DropEnter, is governed by DragDropEditing. }
    function FromOtherProgram: Boolean; virtual;
    { The control whose selection this is; nil: another program's content. }
    function Source: TTyCustomRichEdit; virtual;
    function SourceRange(out AFrom, ALen: TTyRichPos): Boolean; virtual;
    { What its source lets a drop do with it ([rdeCopy] by default: a source that only lends
      its data). }
    function Allowed: TTyRichDropEffects; virtual;
    { A drop took it with AEffect (a move: the source is to take its content away - nothing
      to do for a control's own selection, whose move did that). Never called for a drop that
      was refused or failed: the source keeps its content. }
    procedure Taken(AEffect: TTyRichDropEffect); virtual;
  end;

  { A control's selection as a drop offers it: its range when the drag began, as RTF and as
    plain text the way a copy writes them (read only if asked); a move or a copy - a copy
    only when the control cannot give its content away (ReadOnly, or a range its cut would
    refuse: Movable). Taken: what another control did with it (the source control removes
    the content after a move there: one step of its own). }
  TTyRichSelectionOffer = class(TTyRichDropOffer)
  private
    FOwner: TTyCustomRichEdit;
    FFrom, FLen: TTyRichPos;
    FMovable: Boolean;
    FTaken: TTyRichDropEffect;
    // the source's content when the drag began (ContentState); what a drop takes it as
    FState: Int64;
    FDropAs: TTyRichDropEffect;
    function ReadRange(out AFrom, ALen: TTyRichPos): Boolean;
  public
    constructor Create(AOwner: TTyCustomRichEdit; AFrom, ALen: TTyRichPos);
    function Flavours: TTyRichClipFlavours; override;
    function ReadRtf: RawByteString; override;
    function ReadText: string; override;
    function Source: TTyCustomRichEdit; override;
    function SourceRange(out AFrom, ALen: TTyRichPos): Boolean; override;
    function Allowed: TTyRichDropEffects; override;
    procedure Taken(AEffect: TTyRichDropEffect); override;
    { The source may lose the content (Allowed holds rdeMove); True when made. }
    property Movable: Boolean read FMovable write FMovable;
    { What a drop into another control did with it (rdeNone: nothing yet). }
    property TakenAs: TTyRichDropEffect read FTaken;
  end;

  { A list of files was dropped on the control (from another program): AHandled True takes
    it - the control then does nothing more with it (an application opens a dropped .rtf
    here); False leaves it to the control, which takes pictures only. }
  TTyRichDropFilesEvent = procedure(Sender: TObject; const AFileNames: array of string;
    var AHandled: Boolean) of object;

  { A call the control queues to the application's message loop (TApplication.QueueAsyncCall):
    the next turn of the background work, a selection report a snap made outside a user
    action. One object per kind, so that one kind is taken off the queue without the other
    (RemoveAsyncCalls removes by object); at most one of each is queued (Queued). }
  TTyRichQueuedCall = class
  private
    FOwner: TTyCustomRichEdit;
    FQueued: Boolean;
    procedure Fire(AData: PtrInt);
  public
    constructor Create(AOwner: TTyCustomRichEdit);
    property Queued: Boolean read FQueued;
  end;

  { What drives the background work's turns, chosen per widgetset by what was measured
    or read in its LCL source (TyRichTurnDriverFor):
    - rtdIdle (win32, gtk2, gtk3, qt5, qt6): one turn per pass of the application's loop. While
      there is work the control has an idle handler (Application.AddOnIdleHandler); the idle
      step queues ONE call (QueueAsyncCall) that runs a turn on the next pass, and that turn
      queues nothing itself. The queued call is what makes the loop's wait return. A turn
      that queued the next turn from inside itself would never let the loop go on win32: the
      queue runs there from the application window's WM_NULL handler inside the PeekMessage
      loop, and each queued call posts the next WM_NULL, which PeekMessage hands out before
      input, paints and timers (measured: 150 chained turns = 1 pass of the loop, 0 timer
      ticks, 0 idle steps). On gtk2, gtk3, qt5 and qt6 the queue runs only in the idle step
      and ProcessMessages (read, not run). Beside the idle handler a slow backstop timer
      (CRichBackstopMs, BackstopTick) runs one turn when no turn ran since its last tick: an
      application whose idle step is starved still loads, throttled.
    - rtdTimer (every other widgetset: Cocoa, and anything not named above): a timer whose
      handler runs a turn, as before the queued turns. On Cocoa the queue is run inside the
      wait (lclSyncCheck) and the idle step is not reached between two queued calls, so an
      idle-driven chain would stall there until the next event. Nobody could run Cocoa here:
      the timer is kept because nothing else was shown to work there. }
  TTyRichTurnDriver = (rtdIdle, rtdTimer);

  { The document as lines (one a paragraph), for the form file and for code that thinks in
    lines. Not a copy: Count is the paragraph count, a line is read from the text when it is
    asked for. Assigning the text (Text, Assign, a form file) replaces the content with plain
    text; the other writes (Add, Insert, Delete, Strings[i] :=) are commands, so they can be
    undone. An empty document has no lines. }
  TTyRichEditLines = class(TStrings)
  private
    FOwner: TTyCustomRichEdit;
    FBatch: TStringList;
    { A load asked for inside the update, done by the control when the update ends:
      a stream's bytes, read at once (Lines.LoadFromStream), or a file's name
      (Lines.LoadFromFile), read only then. }
    FBatchLoad: TMemoryStream;
    FBatchFile: string;
    // FBatchFile is a file to load at the update's end, not yet read
    FBatchLoadFile: Boolean;
    FUpdating: Boolean;
    { An empty document is no lines or one empty line: TStrings tells them apart, the text
      cannot. Set by Add('') / Insert on no lines, by a delete that leaves one empty line and
      by a replacement with one empty line; cleared by Clear, by any other replacement and
      when the document is no longer empty. }
    FEmptyLine: Boolean;
    { Put's two commands are one change to the selection (outside a block they are one
      change through their update): Run does not follow them one by one. }
    FNoFollow: Boolean;
    procedure Run(ACmd: TTyRichCommand);
    procedure CheckNoLoad;
  protected
    function Get(Index: Integer): string; override;
    function GetCount: Integer; override;
    procedure Put(Index: Integer; const S: string); override;
    procedure SetTextStr(const Value: string); override;
    { BeginUpdate .. EndUpdate bracket the document's (AddStrings is one undo step); after a
      Clear (what Assign and a form file do) or a Text inside them (what LoadFromStream and
      LoadFromFile do) the lines gather here and become the content once, at the end. }
    procedure SetUpdateState(Updating: Boolean); override;
  public
    constructor Create(AOwner: TTyCustomRichEdit);
    destructor Destroy; override;
    procedure Clear; override;
    procedure Delete(Index: Integer); override;
    procedure Insert(Index: Integer; const S: string); override;
    { As Delphi's TRichEdit.Lines: the control's load and save without a format
      (LoadFromFile, LoadFromStream, SaveToFile, SaveToStream with rfAuto, as PlainText
      says). So a rich control's Lines.SaveToFile writes RTF and its Lines.LoadFromFile
      reads one, and the load decides PlainText (the document follows the file). A load
      inside the lines' BeginUpdate .. EndUpdate is the control's too, put off to the
      update's end (a replacement is gathered the same way); the saves there write the lines
      as TStrings does. }
    procedure LoadFromFile(const FileName: string); overload; override;
    procedure LoadFromStream(Stream: TStream); overload; override;
    procedure SaveToFile(const FileName: string); overload; override;
    procedure SaveToStream(Stream: TStream); overload; override;
  end;

  { A block the view holds: its layout (with a reference), the paragraphs it covers as the
    document numbers them now (the layout's own indexes are those it was made with), and its top
    in pixels from the view's top. Top is an Int64: a block may be CRichMaxBlockPx high, and
    the tops of a few such blocks do not fit an Integer. }
  TTyRichViewBlock = record
    Layout: TTyBlockLayout;
    FirstPara: Integer;
    LastPara: Integer;
    Top: Int64;
    Height: Integer;
  end;

  { What a ruler shows of the paragraph a paragraph format change would begin at
    (TTyCustomRichEdit.ParagraphView): the paragraph, its format (twips) and where its text lies
    on the screen. Its text's left
    edge is the zero its indents and tab stops count from: the page's or the window's text edge,
    or - in a table - its cell's text edge (InCell). The x of a length L of twips from that zero
    in the control's client pixels is Origin + FloorDiv(ZeroRaster + TyRichTwipsToPx(L, PPI,
    Zoom), Scale): the layout's own rounding, so a marker put there stands over the text that
    length places. Raster pixels are client pixels times Scale (the device scale).
    TextWidthRaster: the width the text wraps at, from the zero (CRichNoWrap when it does not
    wrap); ViewRaster: the text area's width. ClipLeft .. ClipRight, ClipTop .. ClipBottom: the
    text clip (client pixels). Editable: a user's paragraph format action would be taken now
    (CanFormatParagraphs: not ReadOnly, enabled, the document taking edits, not in its update,
    not in the designer, and not a range ApplyParagraphFormat would refuse - every paragraph in
    a field's result or in a row that holds a nested table). }
  TTyRichParaView = record
    Para: Integer;
    Format: TTyParaFormat;
    InCell: Boolean;
    Origin: Integer;
    ZeroRaster: Int64;
    TextWidthRaster: Integer;
    ViewRaster: Integer;
    PPI: Integer;
    Zoom: Single;
    Scale: Integer;
    ClipLeft, ClipTop, ClipRight, ClipBottom: Integer;
    Editable: Boolean;
  end;

  { A picture waiting to be decoded or scaled: the size it is to be drawn at and the paragraphs
    of the block it was met in. Holds a reference to the picture. }
  TTyRichPendingPicture = record
    Picture: TTyRichPicture;
    Width, Height: Integer;
    Para, LastPara: Integer;
  end;

  { An edge of the caret's row (TTyCustomRichEdit.CaretRowEdges), for a ruler: Index -1 the
    row's left, else the cell whose right edge it is; Twips where the row's format puts it;
    Offset its place in twips from the caret paragraph's zero (where a ruler's zero is);
    MinOffset / MaxOffset how far a drag may take it, ShiftMinOffset / ShiftMaxOffset with the
    rest of the row following (Shift); Hidden: inside a merged box, not one to drag. }
  TTyRichColumnEdge = record
    Index: Integer;
    Twips: Integer;
    Offset: Integer;
    MinOffset, MaxOffset: Integer;
    ShiftMinOffset, ShiftMaxOffset: Integer;
    Hidden: Boolean;
  end;
  TTyRichColumnEdges = array of TTyRichColumnEdge;

  { The engine's types and values the table doors take, here too: a caller needs this one
    unit (tyControls.RichEdit.RowFormat and .TableProps declare them). }
  TTyRowAlign = tyControls.RichEdit.RowFormat.TTyRowAlign;
  TTyRowCellVAlign = tyControls.RichEdit.RowFormat.TTyRowCellVAlign;
  TTyRowCellSide = tyControls.RichEdit.RowFormat.TTyRowCellSide;
  TTyRowCellSides = tyControls.RichEdit.RowFormat.TTyRowCellSides;
  TTyRichBorderStyle = tyControls.RichEdit.TableProps.TTyRichBorderStyle;
  TTyRichBorder = tyControls.RichEdit.TableProps.TTyRichBorder;
  TTyRichCellLine = tyControls.RichEdit.TableSel.TTyRichCellLine;
  TTyRichCellLines = tyControls.RichEdit.TableSel.TTyRichCellLines;
  // what SelectedCells answers
  TTyRichCellRange = tyControls.RichEdit.TableSel.TTyRichCellRange;

const
  rclLeft = tyControls.RichEdit.TableSel.rclLeft;
  rclTop = tyControls.RichEdit.TableSel.rclTop;
  rclRight = tyControls.RichEdit.TableSel.rclRight;
  rclBottom = tyControls.RichEdit.TableSel.rclBottom;
  rclInsideH = tyControls.RichEdit.TableSel.rclInsideH;
  rclInsideV = tyControls.RichEdit.TableSel.rclInsideV;
  rraLeft = tyControls.RichEdit.RowFormat.rraLeft;
  rraCenter = tyControls.RichEdit.RowFormat.rraCenter;
  rraRight = tyControls.RichEdit.RowFormat.rraRight;
  rcvTop = tyControls.RichEdit.RowFormat.rcvTop;
  rcvCenter = tyControls.RichEdit.RowFormat.rcvCenter;
  rcvBottom = tyControls.RichEdit.RowFormat.rcvBottom;
  rcsLeft = tyControls.RichEdit.RowFormat.rcsLeft;
  rcsTop = tyControls.RichEdit.RowFormat.rcsTop;
  rcsRight = tyControls.RichEdit.RowFormat.rcsRight;
  rcsBottom = tyControls.RichEdit.RowFormat.rcsBottom;
  rbsNone = tyControls.RichEdit.TableProps.rbsNone;
  rbsSingle = tyControls.RichEdit.TableProps.rbsSingle;
  rbsDouble = tyControls.RichEdit.TableProps.rbsDouble;
  rbsDotted = tyControls.RichEdit.TableProps.rbsDotted;
  rbsDashed = tyControls.RichEdit.TableProps.rbsDashed;
  rbsOther = tyControls.RichEdit.TableProps.rbsOther;

type
  { The table properties of the selected cells (else the caret's cell), their rows and their
    table: GetTableProperties fills them in, a form changes some, ApplyTableProperties sets
    those (the table properties action does the three). Two sets that must not be confused:
    Uniform - the control's answer: the fields whose value is the same over every selected
    cell (row); a field not in it is mixed, its value then the first cell's - and Changed -
    the form's: the fields it changed, the only ones applied (none: nothing happens, no undo
    step). }
  TTyRichTablePropField = (tpfRowHeight, tpfColumnWidth, tpfAlign, tpfPadding, tpfVAlign,
    tpfShading, tpfIndent, tpfLineLeft, tpfLineTop, tpfLineRight, tpfLineBottom, tpfLineInsideH,
    tpfLineInsideV);
  TTyRichTablePropFields = set of TTyRichTablePropField;
  TTyRichTableProperties = record
    Uniform: TTyRichTablePropFields;
    Changed: TTyRichTablePropFields;
    // twips; 0: as high as its content (tpfRowHeight: with RowExact)
    RowHeight: Integer;
    // exactly RowHeight, else at least
    RowExact: Boolean;
    // twips: the caret cell's column (the columns right of it shift)
    ColumnWidth: Integer;
    // the table's alignment (all its rows)
    Align: TTyRowAlign;
    { twips: the table's left edge from the margin - \trleft, its first cell's left line (Word's
      dialog shows the text's edge: this and the cell's left padding) }
    Indent: Integer;
    // twips, each side (-1 when changed: that side as it is)
    Pad: array[TTyRowCellSide] of Integer;
    VAlign: TTyRowCellVAlign;
    // clNone: none
    Shading: TColor;
    { The selection's lines (tpfLineLeft .. tpfLineInsideV): its outline's four sides and its
      inner lines, each a border (rbsNone: no line; a line given goes to the facing side of
      the cell beside it too, as every border door's). Uniform has one when every cell side
      that makes it is alike; a selection of one row has no inner horizontal line, nor one of
      one column an inner vertical one. }
    Lines: array[TTyRichCellLine] of TTyRichBorder;
  end;

  { Which lines of the selected cells a border preset sets (SetCellBorders): every side, the
    rectangle's outline, its inside lines, none, one outer side, the inside horizontal or
    vertical lines. }
  TTyRichBorderPreset = (rbpAll, rbpOutside, rbpInside, rbpNone, rbpTop, rbpBottom, rbpLeft,
    rbpRight, rbpInsideH, rbpInsideV);

  { The editor. ITyTextEditActions: the package's text menu (the editing items answer "not
    available" while ReadOnly). ITyImeEditable: Cocoa's input method bridge (a composition
    shown in the text; read-only while ReadOnly). }
  TTyCustomRichEdit = class(TTyCustomControl, ITyScrollBarFrameHost, ITyTextEditActions,
    ITyImeEditable)
  private
    FDoc: TTyRichDocument;
    FText: TTyRichText;              // the text the view was made for (a load replaces it)
    FLayouter: TTyRichLayouter;
    FLines: TTyRichEditLines;
    FZoom: Integer;
    FWrapMode: TTyRichWrapMode;
    FReadOnly: Boolean;
    FTextEncoding: TTyTextEncoding;
    FTextCodePage: Integer;
    FLinesStored: Boolean;
    FSourceFile: string;
    FSourceFormat: TTyRichFormat;
    { What the RTF file had before its signature (a UTF-8 BOM, blank lines, spaces), exactly as
      read: written first whenever the content is saved as RTF. A load of anything else
      and a Lines replacement forget it. }
    FRtfPrefix: TBytes;
    // the view
    FAnchorPara: Integer;
    FAnchorOffset: Int64;
    { A layout parameter changed: the anchor block's offset as a share of its height then, so
      that the same share of it is above the view once it is laid out again. }
    FAnchorShareNum, FAnchorShareDen: Int64;
    { What the last LayoutView did to the view: the held blocks' tops moved (by FMovedBy when
      FMoveKnown: the same paragraph is on top, somewhere else). }
    FViewShifted: Boolean;
    FMoveKnown: Boolean;
    FMovedBy: Int64;
    { A bar decision a layout made in this EnsureView: 0 none, 1 hidden, 2 shown. }
    FLatchV, FLatchH: Integer;
    FScrollX: Integer;              // raster pixels
    { The kept surface: what the control shows, frame and text, at FSurfScale device
      pixels per client pixel; FSurfW x FSurfH client pixels of it are in use. }
    FSurface: TBGRABitmap;
    FSurfW, FSurfH, FSurfScale: Integer;
    FSurfScrollX: Integer;          // the horizontal scroll the text on it was drawn at
    FDirty: array[0..CRichDirtyMax - 1] of TRect;   // raster pixels of the surface
    FDirtyCount: Integer;
    FAllDirty: Boolean;
    FFrameSig: Cardinal;
    FFrameSigValid: Boolean;
    { The device scale the view is laid out at: the last paint's canvas's (1 before any). }
    FScale: Integer;
    FWidestSeen: Integer;
    { A zoom or a PPI change scaled FWidestSeen as a stand-in until the view is laid out again
      (the bars are decided with it before that): the next LayoutView builds it again from what
      it lays out. }
    FExtentStale: Boolean;
    FBlocks: array of TTyRichViewBlock;
    FBlockCount: Integer;
    FViewValid: Boolean;
    FViewW, FViewH: Integer;
    FViewPPI: Integer;
    FLayoutWidth: Integer;
    FLayoutPPI: Integer;
    FLayoutZoom: Single;
    FLayoutFont: string;
    FLayoutFontSize: Integer;
    FLayoutFontStyle: TFontStyles;
    FEstimate: Integer;
    FBarScale: Int64;
    FVBar, FHBar: TTyScrollBar;
    FScrollBarAutoHide: TTyScrollBarAutoHide;
    // a display page's switches (CaretWhenReadOnly, FocusOnClick, AllowSelection, ScrollBars,
    // AutoHeight) and the content's size as last reported (OnContentSizeChange; -1: none yet)
    FCaretWhenReadOnly: Boolean;
    FFocusOnClick: Boolean;
    FAllowSelection: Boolean;
    FScrollBars: TScrollStyle;
    FAutoHeight: Boolean;
    FOnContentSizeChange: TNotifyEvent;
    FSizeCall: TTyRichQueuedCall;
    FReportedW, FReportedH: Integer;
    FSizingSelf: Boolean;
    FPressNoFocus: Boolean;
    FSyncingBars: Boolean;
    FWheelRest, FWheelHRest, FZoomWheelRest: Integer;
    // background work
    FFirstSliceBytes: Int64;
    FStepBytes: Int64;
    FInStep: Boolean;
    FSaving: Integer;
    FCancelRequested: Boolean;
    // inside CancelLoad: the load's notice that it stopped is its own (no edit)
    FInCancel: Boolean;
    FStepCall, FSelCall: TTyRichQueuedCall;
    { The driver's state: the idle handler is registered (rtdIdle), the turn timer
      (rtdTimer; made on the first start, freed with the window), a turn is running. }
    FIdleOn: Boolean;
    FTurnTimer: TTimer;
    FInTurn: Boolean;
    { rtdIdle's backstop timer (made on the first start, freed with the window), the
      turns run so far and how many of them its last tick had seen. }
    FBackstop: TTimer;
    FTurnsRun, FBackstopSeen: Int64;
    { The size of a turn's load slices (see SliceBytes), and within a turn the bytes
      it indexed and the progress handler's milliseconds so far. }
    FSlice, FTurnBytes, FHandlerMs: Int64;
    { inside a load's own change made in a turn (DocChanged); the bars' widgets are behind
      the control's values; the turn clock at which a turn last gave them its range (valid:
      since the load began). }
    FBarsLazy, FBarsBehind, FBarsAtValid: Boolean;
    FBarsAt: QWord;
    { a load whose next turn could not be scheduled ends at the next entry point of the
      loop (see SchedulingFailed). }
    FLoadEndOwed: Boolean;
    FPending: array of TTyRichPendingPicture;
    FPendingCount: Integer;
    { The (picture, size) pairs whose PreparePicture raised (a fatal error: out of memory, an
      access violation), with a reference each: not queued again until the content or the
      layout parameters change. Every other outcome the layouter records itself - after
      PreparePicture the picture is ready or known to be a placeholder. }
    FFailed: array of TTyRichPendingPicture;
    FFailedCount: Integer;
    { The PPI the frame signature was taken at (PointerStateChanged compares at it). }
    FFrameSigPPI: Integer;
    { Inside a window paint whose clip covers the text area: a view laid out there needs no
      window invalidation (the same paint blits it). }
    FPaintCoversText: Boolean;
    FFallbackListChange: TNotifyEvent;
    { The caret and the selection: document positions (characters), the selection from the
      anchor to the caret. FCaretAtEnd is the caret's affinity (the layout's AAtLineEnd): at a
      place where a wrapped line ends and the next begins, the end of the earlier line. }
    FCaret, FSelAnchor: TTyRichPos;
    FCaretAtEnd: Boolean;
    { The x (raster pixels of the layout) Up, Down, PgUp and PgDn keep across a run of them;
      any other move forgets it. }
    FWishX: Integer;
    FWishValid: Boolean;
    FReportedCaret, FReportedAnchor: TTyRichPos;
    // the blink, and where the caret was drawn last (client pixels; empty: not drawn)
    FCaretShown: Boolean;
    FBlinkTimer: TTimer;
    FBlinkMs: Integer;
    FCaretDrawn: TRect;
    { A left button held since a press on the text: the selection follows the pointer, by
      characters (1), words (2: after a double click), paragraphs (3: a triple click) or from
      an object pressed (4: by characters) - the unit FDragFrom .. FDragTo the press selected
      stays selected. }
    FDragging: Boolean;
    FDragUnit: Integer;
    FDragFrom, FDragTo: TTyRichPos;
    FDragPoint: TPoint;
    FDragTimer: TTimer;
    FLastClickX, FLastClickY, FClickCount: Integer;
    FLastClickTick: QWord;
    FTextMenu: TTyTextEditMenu;
    FCopyWaitChars: Int64;
    FSavedCursor: TCursor;
    { A document change moved the caret or the anchor by arithmetic alone: the next paint or
      settled query puts them on caret places. }
    FSnapPending: Boolean;
    { A window paint came while the document held its changes back and drew nothing new (it
      blitted the old surface, or nothing): the window is asked to paint again, whole, when
      the view hears of the change. }
    FSkippedPaint: Boolean;
    { The pointer was last seen over the padding (MouseMove; GetCursor answers the arrow);
      cleared when it leaves the control. }
    FOverPadding: Boolean;
    { The selection was set while the document held its changes back: the positions
      are the text's as it was then, not moved by the update's own change; the update's end
      clamps them to the final text and paints the selection. }
    FSelInUpdate: Boolean;
    { The caret and the anchor already follow the update's text: they were set inside it, or a
      write of the control's own inside it was followed (FollowBlockChange) - also one wholly
      behind the selection, which moved neither. The update's one change at its end does not
      move them again: it is the union of every text change made in the update, and a change
      made straight through Document.Execute before the selection would otherwise carry a
      caret inside that union to its start. Unlike FSelInUpdate it asks for no repaint. }
    FPosInUpdate: Boolean;
    // editing
    FWantTabs: Boolean;
    { Inside an edit the control makes itself (RunEdit, RunHistory, FinishEdit's Select): the
      document's change is heard (FEditHeard, FEditChange: what it reported) but neither
      moves the caret by arithmetic nor is reported - the edit places the caret and reports
      once; a Select there does not end the run of typing. }
    FEditing: Integer;
    FEditHeard: Boolean;
    FEditChange: TTyRichChange;
    { The history step the running edit of the control's own became (or merged into): its
      marks get where the edit leaves the selection (FinishEdit). nil: none - the edit was
      kept inside the document's update, or none runs. }
    FEditStep: TTyRichCommand;
    { A command of the control's own made before it goes through the door of a user's edit
      (RunMade: the keys made it after they ended a composition) and where it leaves the
      selection - what TakeMade hands the door; nil once taken. }
    FMade: TTyRichCommand;
    FMadePlace: TTyRichEditPlace;
    // RunMade's: set when the door took the command (TakeMade), which then owns it
    FMadeTaken: PBoolean;
    { A table action (InsertTable .. DeleteTable, Tab's new row): which one MakeTableEdit makes
      (FTableKind, a CTableXxx of the implementation), with its size or side; and where it
      leaves the caret, worked out after it ran (TableEditCaret) from what it knew before:
      FAimPara a paragraph as the text numbers them after the edit (the new row's first,
      the place of the rows that went, the table's first), FAimRow / FAimCell the caret's row
      and cell index, FAimFollows a row came up into the place of the rows that went,
      FAimBefore a row is left above them. }
    FTableKind: Integer;
    FTableRows, FTableCols: Integer;
    FTableAfter: Boolean;
    FAimPara, FAimRow, FAimCell: Integer;
    FAimFollows, FAimBefore: Boolean;
    { What the Can... functions and InTable found, and for which content, selection and
      state of the document (AskTables): asked again with none of them changed, they answer
      from here. }
    FAskValid: Boolean;
    FAskState: Int64;
    FAskCaret, FAskAnchor: TTyRichPos;
    FAskBusy: Boolean;
    FAskIn, FAskInsTable, FAskRows, FAskColIns, FAskColDel, FAskTable: Boolean;
    { What is true of the whole table (its refusals do not depend on the row or the cell), for
      the table object (a reference held: it is not reused while kept) and content state it
      was found for: a move inside that table reads nothing again. }
    FAskTbl: TTyRichTable;
    { CaretTablePara took the caret's own paragraph because the paragraphs that would tell
      whether whole rows are selected are not read yet (an answer not to be kept). }
    FCaretParaUnread: Boolean;
    FAskTblState: Int64;
    FAskTblRows, FAskTblColIns, FAskTblColDel, FAskTblDelete: Boolean;
    FOnEditRefused: TTyRichEditRefusedEvent;
    // InsertLink / SetLink's arguments, for their makers
    FLinkArgURL, FLinkArgText: string;
    FOnLinkClick: TTyRichLinkClickEvent;
    FFollowBookmarkLinks: Boolean;
    FOnFollowLink: TTyRichFollowLinkEvent;
    FOnObjectClick, FOnObjectDblClick: TTyRichObjectClickEvent;
    // the object a press began on (-1 none), with its button and point: its click's release
    FObjPressAt: TTyRichPos;
    FObjPressButton: TMouseButton;
    FObjPressPoint: TPoint;
    // BookmarkCount / BookmarkName's list (kept across a change that touches no bookmark)
    FBkmIndex: TTyRichBookmarkList;
    FBkmArgName, FBkmArgNew: string;
    { A press on a link that becomes its click when the same button comes up on the same link
      (LinkPress): the button, where, the keys, the link's open mark. Moved past the drag
      threshold it is a press as any (ReplayPress). }
    FLinkPressed: Boolean;
    FLinkButton: TMouseButton;
    FLinkPoint: TPoint;
    FLinkShift: TShiftState;
    FLinkOpen: TTyRichPos;
    FLinkURL: string;
    { The pointer's last place over the control and the keys then: the hand follows Ctrl with
      the pointer still, and ReadOnly. }
    FPointerAt: TPoint;
    FPointerShift: TShiftState;
    FPointerKnown: Boolean;
    { Fields read for the content FKnownState: what a pointer's move asks again is not read
      again (a link's instruction, a field's marks found across paragraphs). }
    FKnownState: Int64;
    FKnown: array of TTyRichKnownField;
    FKnownCount: Integer;
    { Bounded: a new field takes the place of the one asked for longest ago - never of one
      asked for in this look-up (FKnownCall) nor of one the character looked at (FKnownAt) is
      inside (so the fields around the pointer stay while it is inside them). }
    FKnownClock, FKnownCall: Int64;
    FKnownAt: TTyRichPos;
    FLinkReads, FLinkSearches: Int64;
    { A selected object's handles and a resize's outline on the surface: where they are drawn
    (raster pixels of the view, as CaretRaster gives them; empty: none) - the surface's truth,
    kept with its pixels (MoveSurfaceText) and brought to what the view shows by
    SyncObjectOverlay, which paints again the old place and the new one, nothing else. }
    FHandleRect, FPreviewRect: TRect;
    { A drag of a handle (FResizing): the handle, the object's character and the object (not
      held: a document change ends the drag), its box and the press (raster pixels of the view
      then), its size then and now (twips) and the most its width may be. }
    FResizing: Boolean;
    FResizeHandle: TTyRichHandle;
    FResizePos: TTyRichPos;
    FResizeObj: TTyRichObject;
    FResizeBox: TRect;
    FResizeFrom: TPoint;
    FResizeW0, FResizeH0, FResizeW, FResizeH, FResizeMaxW: Integer;
    // where the pointer was last seen in a drag of a handle, and the keys held then
    FResizeLast: TPoint;
    FResizeShift: TShiftState;
    // the cursor of the handle the pointer was last seen over (crDefault: none)
    FOverHandle: TCursor;
    FOnObjectResize: TTyRichObjectResizeEvent;
    { Dragging the selection (DragDropEditing). A left press inside the selection waits
      (FDragPending) for a move past the drag threshold, from FPressPoint, before the drag
      begins; a release first is the click it would have been (at FPressPlace). The drop's
      session (DropEnter .. DropLeave / DropOn): its offer (FDropOwn: the control's own
      drag's, freed by the control), the place under the pointer and the verdict there
      (FDropPos, FDropAtEnd, FDropEffect), the pointer and the keys last known, and
      whether the selection dragged can be moved at all (FDropCuttable). FDropRect: the
      drop mark on the surface (raster pixels of the view, as FHandleRect). FEatMenu: a right
      press ended a drag of the control's own (the selection's or a handle's, OwnDragRunning)
      - its menu is not shown; that press's only: the popup it would bring, the next key, a
      move without the right button or another button's release clear it. }
    FDragDropEditing: Boolean;
    FDragPending: Boolean;
    FPressPoint: TPoint;
    FPressPlace: TTyRichPos;
    FPressAtEnd: Boolean;
    FDragPressObj: TTyRichPos;
    FDropOffer: TTyRichDropOffer;
    FDropOwn: Boolean;
    FDropPos: TTyRichPos;
    FDropAtEnd: Boolean;
    FDropEffect: TTyRichDropEffect;
    FDropPoint: TPoint;
    FDropShift: TShiftState;
    FDropCuttable: Boolean;
    FDropRect: TRect;
    FEatMenu: Boolean;
    FDropFollowing: Boolean;
    { The control's own drag over another rich edit of the application (outside its own
      client area): FDropPeer holds a session over the same offer, fed from here
      (FPeerFeeding while a call into it runs); its verdict is the one the cursor shows. }
    FDropPeer: TTyCustomRichEdit;
    FPeerFeeding: Boolean;
    // the session's offer whose file list was looked at, and the answer (OfferedPictures)
    FFilesOffer: TTyRichDropOffer;
    FFilesPictures: Boolean;
    { Drops from other programs (the Windows widgetset: an OLE drop target for the window). }
    FAcceptDrops: Boolean;
    FOnDropFiles: TTyRichDropFilesEvent;
    {$IFDEF LCLWin32}
    // the drop target (made when first wanted, kept for the control's life) and the window
    // it is registered for (0: none)
    FOleTarget: IUnknown;
    FOleWnd: HWND;
    {$ENDIF}
    { A press on the selection waits for a drag (FDragPending) or was ended while waiting by
      something not the user's (a change, the selection set by code): its release is the plain
      click it was. Esc, another key, another press, a capture taken drop it. }
    FPressClickOwed: Boolean;
    { The input method. A composition goes in at FCompPos (the caret when it began)
      and is not the document's: the layouter shows FCompText there (SetComposition), in
      FCompFormat (the typing format then), the input method's caret and clause in it
      (characters of FCompText). FImeRefused: the input method's session was refused (the
      document took no edit when it began, or a drag of the control's own ran): what it sends
      goes nowhere until it ends. }
    FComposing: Boolean;
    FCompPos: TTyRichPos;
    FCompText: UTF8String;
    FCompCaret, FCompClauseFrom, FCompClauseTo: Integer;
    FCompFormat: TTyCharFormatId;
    FImeRefused: Boolean;
    { Cocoa's bridge counts its positions from the caret's index when the session began. }
    FCocoaBase: Integer;
    { The widgetset's own input method hook (Qt, GTK2: TyImeInstall; nil elsewhere), the Cocoa
      handler (LCLCocoa only) and where the candidate window was put last (client pixels). }
    FImeHook: TObject;
    FCocoaIme: TObject;
    FImePlaced: TRect;
    { FCompAnchor: the selection's anchor when the composition began (FCompPos
      its caret) - the commit replaces that selection, the one the user saw, not one made
      meanwhile; both follow the text as the caret does. FCompPending: the control ended the
      composition and told the input method to commit, and it had not answered while told -
      a result it sends before its next start goes in there (FCompPos, FCompAnchor,
      FCompFormat kept). }
    FCompAnchor: TTyRichPos;
    FCompPending: Boolean;
    { A press made while composing is placed on what the user saw - the text
      with the composition in it: FPressPos (its position; FPressAfter: on the composition or
      behind it, not before it) and FPressObj (the object under it, or -1) are taken before
      the composition ends, and carried through the commit that ends it as any position is
      (FPressCarry: while it runs; cleared when the content is replaced). FCompBefore: such a
      press at the composition's own place but before it, when the input method's result is
      still owed - the late result goes in behind the caret, not before it. FNoEditScroll:
      the commit a press causes leaves the view where the user clicked; FEditQuiet: a late
      result's edit reports nothing itself (the selection it puts back is reported once). }
    FPressPos, FPressObj: TTyRichPos;
    FPressAfter, FPressCarry, FCompBefore: Boolean;
    FNoEditScroll, FEditQuiet: Boolean;
    { The lParam of the last WM_IME_SETCONTEXT that activated the window (what the system
      asked to show; ISC_SHOWUIALL until one came). }
    FImeContextL: PtrInt;
    { Cocoa's bridge: its session is open (ImeSessionBegin .. ImeSessionEnd), one of its calls
      runs (FInBridge), the control ended the session's composition itself (FCocoaSwallow:
      Cocoa keeps its marked text, so what the bridge sends until the session's end goes
      nowhere - it went in, or was dropped, when the control ended it). }
    FCocoaSession, FCocoaSwallow: Boolean;
    FInBridge: Integer;
    { The format API: the two façades' objects; the plain-text state; the
      pending typing format - a format chosen with nothing selected, for the next typed text
      at FPendingAt (FHasPendingFmt); inside a façade's write (FApiWrite: the selection is
      kept as it is and the pending format with it, the view does not scroll). }
    FSelAttributes, FDefAttributes: TTyRichTextAttributes;
    FParagraph: TTyRichParaAttributes;
    FPlainText: Boolean;
    { PlainText was set True by code or the Object Inspector (not by a text file's load): only
      then does a load without a format read text whatever the file is. }
    FPlainTextAsked: Boolean;
    // inside ActionChange: a linked action's Caption is not the document's text
    FInActionChange: Boolean;
    FPendingFmt: TTyCharFormatId;
    FHasPendingFmt: Boolean;
    FPendingAt: TTyRichPos;
    FApiWrite: Integer;
    FConsHave: Boolean;
    FConsBaseId: TTyCharFormatId;
    FConsBase: TTyCharFormat;
    FConsMask: TTyCharFormatMask;
    FConsLast: Integer;
    // the walks' budget: units of work done, the loader's parsed bytes at the start, cut
    FConsBudgetWork: Integer;
    FConsBudgetBytes: Int64;
    FConsSeen: Integer;
    FConsParsed0: Int64;
    FConsCut: Boolean;
    FConsWalks: Integer;
    // the last answers, by selection and content (a repeated read is free)
    FCharConsValid: Boolean;
    FCharConsStart, FCharConsLen, FCharConsState: Int64;
    FCharConsResult: TTyCharFormatMask;
    FParaConsValid: Boolean;
    FParaConsStart, FParaConsLen, FParaConsState: Int64;
    FParaConsResult: TTyRichConsistentParaAttributes;
    // the paragraph walk: the first format met and what is still the same
    FParaConsHave: Boolean;
    FParaConsBaseId: TTyParaFormatId;
    FParaConsBase: TTyParaFormat;
    FParaConsMask: TTyRichConsistentParaAttributes;
    FOnModifiedChange: TNotifyEvent;
    { OnModifiedChange owed by a turn heard inside the control's own edit: raised when
      the edit has made its own reports (PayModifiedOwed). }
    FModifiedOwed: Boolean;
    // BeginEdit .. EndEdit: the depth and the selection the block began with
    FEditBlock: Integer;
    FEditBlockMarks: TTyRichStepMarks;
    procedure DocModifiedChanged(Sender: TObject);
    procedure PayModifiedOwed;
    procedure SetSelAttributes(AValue: TTyRichTextAttributes);
    procedure SetDefAttributes(AValue: TTyRichTextAttributes);
    procedure SetParagraph(AValue: TTyRichParaAttributes);
    procedure SetPlainTextState(AValue: Boolean);
    { The base text without a format of its own is shown in (the control's Font over the
      theme): name, size in half points, style, colour, charset. }
    function BaseCharFormat: TTyCharFormat;
    { The base size in half points (the layouter's BaseFontSizeHalfPt) for AStyle. }
    function BaseHalfPt(const AStyle: TTyStyleSet): Integer;
    { ... and its name: never '' (the Font's when neither the theme nor the platform names
      one). }
    function BaseFontName(const AStyle: TTyStyleSet): string;
    { What RTF written of the document names for text with no font or size of its own
      (TTyRichDocument.BaseFontName, BaseFontSizeHalfPt): the view's, before a save or a copy. }
    procedure NameDocBase;
    procedure SetBaseCharFormat(AMask: TTyCharFormatMask; const AValue: TTyCharFormat);
    { AFormat with the base filled in where it has none of its own (a name, a size). }
    function ResolvedFormat(const AFormat: TTyCharFormat): TTyCharFormat;
    { The format of the character at APos (the paragraph's last run's at its end). }
    function CharFormatIdAt(APos: TTyRichPos): TTyCharFormatId;
    { The fields that are the same over [AStart, AStart + ALen): the paragraphs' runs walked
      until every field differed. }
    function RangeConsistency(AStart, ALen: TTyRichPos): TTyCharFormatMask;
    { RangeConsistency's walk: the first format met, the fields still the same, the last
      paragraph to walk. }
    procedure ConsistencyAdd(AFormat: TTyCharFormatId);
    procedure ConsistencyWalk(AIndex: Integer; AData: Pointer; ASrcOffset, ASrcBytes: Int64;
      var AContinue: Boolean);
    { The budget of a consistency walk: ConsistencyBegin starts one;
      ConsistencyGo says whether the walk may read a paragraph (AUnparsed: reading it
      parses) - False once the budget is spent (FConsCut); ConsistencyUnit counts one unit
      of work (a run looked at, a paragraph's format) and says whether it was within it. }
    procedure ConsistencyBegin;
    function ConsistencyGo(AUnparsed: Boolean): Boolean;
    function ConsistencyUnit: Boolean;
    function ParsedSoFar: Int64;
    { Delphi's Paragraph.ConsistentAttributes over the paragraphs [AStart, AStart + ALen)
      touches: bounded and remembered as RangeConsistency. }
    function ParaConsistency(AStart, ALen: TTyRichPos): TTyRichConsistentParaAttributes;
    procedure ParaConsistencyWalk(AIndex: Integer; AData: Pointer; ASrcOffset,
      ASrcBytes: Int64; var AContinue: Boolean);
    { The format SelAttributes reads: with a selection, of the first character a format write
      formats (one that starts at a paragraph's separator formats nothing of that paragraph:
      the next one's first character); else TypingFormat. }
    function SelFormatId: TTyCharFormatId;
    function GetZoomFactor: Double;
    procedure SetZoomFactor(AValue: Double);
    { The paragraphs [AStart, AStart + ALen) touches: a range that ends at a paragraph's very
      start does not touch it; an empty range, its paragraph. }
    procedure ParasOfRange(AStart, ALen: TTyRichPos; out AFirst, ALast: Integer);
    { The one door of the façades' writes: see the façades' declarations. }
    procedure RunApiEdit(ACmd: TTyRichCommand; AChars: TTyRichPos);
    // the document's settings (DocumentColor, SetPageSetup, SetDefaultFormats)
    function GetDocumentColor: TColor;
    // the display page's switches
    procedure SetCaretWhenReadOnly(AValue: Boolean);
    procedure SetAllowSelection(AValue: Boolean);
    procedure SetScrollBars(AValue: TScrollStyle);
    procedure SetAutoHeight(AValue: Boolean);
    { The wheel scrolls the control this way (else the parent gets it): the bar may show
      there and the content does not fit, or the view is off its start. }
    function WheelScrolls(AVertical: Boolean): Boolean;
    function BarAllowed(AVertical: Boolean): Boolean;
    function CaretHidden: Boolean;
    { Every paragraph measured, where a document small enough is whole (ContentHeight's
      exactness): CRichContentExactParas paragraphs at most, never a file still loading. }
    procedure MeasureContent;
    { The view made and the content measured, the bars as what was measured has them - the
      content size's questions (ContentHeight, ContentWidth) ask it. }
    procedure EnsureContentMeasured;
    function ContentInsets(out AH, AV: Integer): Boolean;
    { The content's size against what was last reported: OnContentSizeChange, and AutoHeight's
      height. AQueue: from a place that must not run it now (a paint, a document's change,
      a resize) - queued to the loop. Nothing at all while nobody listens. }
    procedure CheckContentSize(AQueue: Boolean);
    function AutoHeightFor(AH: Integer): Integer;
    function ContentSizeWanted: Boolean;
    function AutoHeightApplies: Boolean;
    procedure SetDocumentColor(AValue: TColor);
    procedure ApiSettings(const ASettings: TTyRichDocSettings);
    procedure ApiCharFormat(AStart, ALen: TTyRichPos; AMask: TTyCharFormatMask;
      const AValue: TTyCharFormat);
    procedure ApiParaFormat(AStart, ALen: TTyRichPos; AMask: TTyParaFormatMask;
      const AValue: TTyParaFormat);
    function ParaFormatAt(APos: TTyRichPos; out AFormat: TTyParaFormat): Boolean;
  private
    // find and replace in the background
    FFindKind: TTyRichFindKind;
    { Raised by every start and every end of a find or a replace: a turn, a handler's return,
      an event of an older one is never taken for the one running. }
    FFindGen: Int64;
    FFinder: TTyRichFinder;
    FFindText: UTF8String;
    FFindOpts: TTyRichFindOptions;
    FFindWrapLeft: Boolean;           // FindNextAsync with rfoWrap: the second leg is to come
    FFindLen: TTyRichPos;             // the needle's characters
    FFindFrom: TTyRichPos;            // where the first leg began (the second ends there)
    FFindState: Int64;                // the content the find runs on (ContentState)
    FFindDone, FFindTotal: Int64;     // progress, as last reported
    FFindLegFrom, FFindLegTo: TTyRichPos;
    FFindLegBase: Int64;              // what the legs before this one searched
    FFindSlice: Int64;
    FFindTurnWork: Int64;             // what this turn's find pieces searched or replaced
    FFindCancel: Boolean;             // the progress handler's ACancel
    FFindBytesRead: Int64;            // what the synchronous finds read (a test seam)
    { The replace in the background: its command (the history's once it ran), what it did.
      The command says when it is freed - whoever frees it (ReplaceCommandFreed) - and the
      reference goes there: while FReplaceCmd is not nil the command is alive. }
    FReplaceCmd: TTyRichReplaceAllCommand;
    FReplaceRan: Boolean;
    FSyncReplace: PTyRichSyncReplace;  // the synchronous ReplaceAll calls on the stack
    { What its command did, as the command tells it - true of the content its last part left
      (FFindState). A change it did not make leaves that as it is and is followed in
      FReplaceFollowed (ReplaceResumeFollows): when the replace ends, the one that is true of
      the content then is told. }
    FReplaceTally: TTyRichReplaceTally;
    FReplaceFollowed: TTyRichReplaceTally;
    FReplaceFollows: Boolean;
    FReplaceFrom, FReplaceLength: TTyRichPos;  // its range, as asked
    FReplaceWith: UTF8String;         // its replacement
    { The last replace that stopped before its end: the place it said to go on from, the
      content then (ContentState), and what its walk saw right before that place - with its
      needle, replacement and options. A replace of the same three started at exactly that
      place while the content is still that one goes on with it (ResumeBeforeFor): a match
      that begins there is judged a whole word as the one walk judged it, by the text as it
      was before what stood there was replaced. Any other start, or any change since, is
      judged by the text as it is. }
    FResumeValid: Boolean;
    FResumeAt: TTyRichPos;
    FResumeState: Int64;
    FResumeBefore: TTyRichBefore;
    FResumeFind, FResumeRepl: UTF8String;
    FResumeOpts: TTyRichFindOptions;
    // what ended (StopFind), for its event
    FEndedKind: TTyRichFindKind;
    FEndedTally: TTyRichReplaceTally;
    FEndedExact: Boolean;             // ... a replace's: true of the content as it is
    // an end the content's replacement owes its event (PayFindOwed)
    FOwedKind: TTyRichFindKind;
    FOwedStop: TTyRichFindStop;
    FOwedTally: TTyRichReplaceTally;
    FInReplacePart: Boolean;          // the replace's own part runs (DocChanged: not an edit)
    FLife: PTyRichLife;               // the frames that would know of the control being freed
    FFindCall: TTyRichQueuedCall;
    FOnFindProgress: TTyRichFindProgressEvent;
    FOnFindDone: TTyRichFindDoneEvent;
    FOnReplaceDone: TTyRichReplaceDoneEvent;
    procedure LifeEnter(var ALife: TTyRichLife; AHandler: Boolean = False);
    { The one bracket of the control's frames: AWork runs inside ALife; when a handler under it
      freed the control, ETyRichGone stops here (or goes on to the frame below, when that is
      the control's own with none of the application's code between) and nothing of the
      control is touched. ALife.Gone says so afterwards. }
    procedure Guard(var ALife: TTyRichLife; AWork: TTyRichGuarded);
    { An application's handler (AFire) inside a handler frame; see HandlerReturned. }
    procedure CallHandler(AFire: TTyRichGuarded);
    procedure RunHistoryIn(ARedo, AUser: Boolean);
    function EditWithIn(AMake: TTyRichEditMaker; AUser, AEnded: Boolean): Boolean;
    procedure TypeTextIn(const AText: UTF8String; AMergeable, AUser: Boolean;
      AFormat: TTyCharFormatId; ACaretChars: Int64);
    procedure EndEditIn(var ALife: TTyRichLife);
    procedure CommitCompositionIn(const AText: string; var ALife: TTyRichLife);
    procedure RunApiEditIn(ACmd: TTyRichCommand; AChars: TTyRichPos; var ALife: TTyRichLife);
    procedure LifeLeave(var ALife: TTyRichLife);
    procedure TurnBody(var ALife: TTyRichLife);
    // the run of typing ends (TTyRichDocument.BreakMerge)
    procedure EndTypingRun;
    { The find or replace running waits for something - the load, an input method's
      composition, the document's update or save -: it asks for no turn meanwhile, and
      what it waits for wakes it (FindWake). }
    function FindBlocked: Boolean;
    procedure FindWake;
    function GetFindRunning: Boolean;
    procedure StartFind(AKind: TTyRichFindKind);
    procedure FindPiece;
    procedure ReplacePiece;
    procedure FindProgress;
    procedure ReportFindProgress(AKind: TTyRichFindKind; ADone, ATotal: Int64);
    procedure StartFindLeg(AFrom, ATo: TTyRichPos);
    { The background find or replace ends: StopFind ends it with no event; EndFind ends it and
      tells it (AEvent: at once - the progress at its total, then OnFindDone or OnReplaceDone;
      not AEvent: owed to the public call that replaced the content, else to a queued call;
      never from the destructor). }
    procedure StopFind;
    procedure EndFind(AStop: TTyRichFindStop; AEvent: Boolean);
    procedure TellFindEnd(AKind: TTyRichFindKind; AStop: TTyRichFindStop; APos, ALen: TTyRichPos;
      const ATally: TTyRichReplaceTally);
    procedure RaiseFindEnd(AKind: TTyRichFindKind; AStop: TTyRichFindStop; APos, ALen: TTyRichPos;
      const ATally: TTyRichReplaceTally);
    procedure PayFindOwed;
    procedure ReplaceResumeFollows(const AChange: TTyRichChange);
    procedure ReplaceCommandFreed(Sender: TObject);
    procedure RememberResume(const AFind, AReplace: UTF8String; AOptions: TTyRichFindOptions;
      const ATally: TTyRichReplaceTally; AExact: Boolean);
    function ResumeBeforeFor(const AFind, AReplace: UTF8String; AOptions: TTyRichFindOptions;
      AStart: TTyRichPos): TTyRichBefore;
    function SnapPosAfter(APos: TTyRichPos): TTyRichPos;
    procedure SelectFound(APos, ALen: TTyRichPos);
    procedure NoteFindTurn(AMs: Int64);
    function CountMatches(const AFind: string; AOptions: TTyRichFindOptions;
      AStart: TTyRichPos = 0; ALength: TTyRichPos = -1): Integer;
    function SyncFind(const AText: string; AStart, ALen: TTyRichPos;
      AOptions: TTyRichFindOptions; out AFoundLen: TTyRichPos): TTyRichPos;
  private
    // events
    FOnSelectionChange: TNotifyEvent;
    FOnChange: TNotifyEvent;
    FOnZoomChange: TNotifyEvent;
    FOnLoadProgress: TTyRichProgressEvent;
    FOnSaveProgress: TTyRichProgressEvent;
    procedure DocChanged(Sender: TObject; const AChange: TTyRichChange);
    { The document stopped holding its changes back (TTyRichDocument.OnUpdatingEnd), after
      the change, if any, was reported: what was put off while it held them is done now - a
      skipped paint made good, a selection set meanwhile painted. }
    procedure DocUpdatingEnded(Sender: TObject);
    procedure ContentReplaced;
    procedure ChangeInView(const AChange: TTyRichChange);
    procedure RelayStale;
    procedure ReleaseBlocks;
    procedure ClearPending;
    procedure ClearFailed;
    procedure AddBlock(var AList: array of TTyRichViewBlock; var ACount: Integer;
      ALayout: TTyBlockLayout; ATop: Int64);
    procedure WriteHeights(AFrom, ATo: Integer);
    procedure NoteExtent(ALayout: TTyBlockLayout);
    procedure QueuePicturesAhead;
    procedure QueuePicture(APicture: TTyRichPicture; AWidth, AHeight, APara, ALastPara: Integer;
      AHeld: Boolean);
    function FailedIndex(APicture: TTyRichPicture; AWidth, AHeight: Integer): Integer;
    { The anchor block laid out at the new parameters takes the share a layout parameter
      change recorded: its offset becomes that share of its new height. }
    procedure ApplyAnchorShare(ABlock: TTyBlockLayout);
    procedure InvalidatePicture(APicture: TTyRichPicture; AWidth, AHeight: Integer);
    procedure LayoutParamsChanged;
    procedure FallbackListChanged(Sender: TObject);
    { The style the text gets that its format does not give (TTyRichLayouter.BaseFontStyle):
      the resolved style's weight - a theme's font-weight, and the control's Font.Style where
      it was set below the form (the rule the name and the size go by), which the style takes
      in as the weight and its flags. }
    function BaseFontStyle(const AStyle: TTyStyleSet): TFontStyles;
    procedure CheckReplaceable;
    { The view's top in raster pixels of the heights, as the anchor says (no settling). }
    function AnchorY: Int64;
    procedure ScrollRasterTo(AValue: Int64);
    procedure ScrollRasterBy(ADeltaY: Int64);
    function GetTopOffset: Int64;
    function GetScrollX: Integer;
    function GetHorizontalExtent: Integer;
    { Raster pixels relative to the text area's top left (as blocks' tops are) to client
      pixels, rounded outward and kept within an Integer's half range. }
    function ClientOf(const AArea: TRect; AL, AT, AR, AB: Int64): TRect;
    { The text area reaching into the left padding (where a row's lines may be drawn), never
      over the frame: what the text is drawn and clipped in. Client pixels of ARect. }
    function TextClipOf(const ARect, AArea: TRect; APPI: Integer): TRect;
    { The text changed in AL..AR x AT..AB (raster, relative to the text area): that part of the
      surface is dirty and its client rectangle (outward) is invalidated. }
    procedure InvalidateTextRect(AL, AT, AR, AB: Int64);
    { InvalidateTextRect's two halves: ADirty, that part of the surface is drawn again;
      AWindow, the window's part is invalidated (a blit). }
    procedure TextRectChanged(AL, AT, AR, AB: Int64; ADirty, AWindow: Boolean);
    procedure InvalidateBand(ATop, ABottom: Int64);
    procedure MarkDirty(const ARect: TRect);
    procedure MarkTextDirty;
    { The text on the surface moved ADX, ADY raster pixels (right / down when positive): all
      of it (a scroll), or - AFrom, a row of the view (raster, relative to the text area's
      top) - only what lies from that row down, vertically (the blocks below an edit that
      changed their height). Its rows or columns are moved inside the text clip and what was
      dirty there moves along; every row of the clip from where the moving part was or now
      begins down that gets no valid pixels from the move is dirty (the band a scroll
      exposes, the bottom a shorter edit leaves, all of it when nothing of the moving part is
      shown). Nothing is invalidated. }
    procedure MoveSurfaceText(ADX, ADY: Int64; AFrom: Int64 = Low(Int64));
    procedure MoveOverlay(var ARect: TRect; ADX, ADY, AFrom: Int64);
    procedure EnsureSurface(AW, AH, AScale: Integer);
    procedure RedrawSurface(APPI: Integer; ADefer: Boolean);
    procedure BlitSurface(ACanvas: TCanvas; const APart: TRect; ADstX, ADstY: Integer;
      const AScale: TTyCanvasScale);
    procedure PaintLayer(ACanvas: TCanvas; const ARect, AClip: TRect; APPI: Integer;
      ADefer: Boolean; const AScale: TTyCanvasScale);
    procedure QueueSkipped(ABlock: Integer);
    function SurfaceUsable(const AStyle: TTyStyleSet): Boolean;
    function FrameSignature(APPI: Integer): Cardinal;
    { Lays the view out if something left it invalid: what the queries call first. }
    procedure Settle;
    function ScrollBarSize(APPI: Integer): Integer;
    { The PPI the view was last laid out at; the control's before that. }
    function ViewPPI: Integer;
    function VBarShown: Boolean;
    function HBarShown: Boolean;
    function UpdateBars(AMeasured: Boolean): Boolean;
    procedure PlaceBars;
    procedure VBarChange(Sender: TObject);
    procedure HBarChange(Sender: TObject);
    procedure ClampScrollX;
    procedure ViewMoved;
    procedure LoadProgress(Sender: TObject; ADone, ATotal: Int64);
    function SaveProgress(ADone, ATotal: Int64): Boolean;
    procedure StartBackground;
    procedure StopBackground;
    procedure WriteTo(AStream: TStream; AFormat: TTyRichFormat);
    function GetLines: TStrings;
    procedure SetLines(AValue: TStrings);
    function IsLinesStored: Boolean;
    function GetModified: Boolean;
    procedure SetModified(AValue: Boolean);
    function GetLoading: Boolean;
    function GetIncomplete: Boolean;
    function GetFallbackFonts: TStrings;
    function GetOnFallbackFont: TTyRichFallbackEvent;
    procedure SetOnFallbackFont(AValue: TTyRichFallbackEvent);
    procedure SetZoom(AValue: Integer);
    procedure SetWrapMode(AValue: TTyRichWrapMode);
    procedure SetReadOnly(AValue: Boolean);
    procedure SetScrollBarAutoHide(AValue: TTyScrollBarAutoHide);
    function GetScrollY: Int64;
    procedure SetScrollY(AValue: Int64);
    function GetVisibleBlock(AIndex: Integer): TTyRichViewBlock;
    // the caret and the selection
    function GetSelStart: TTyRichPos;
    function GetSelLength: TTyRichPos;
    function GetPlacedSelStart: TTyRichPos;
    function GetPlacedSelLength: TTyRichPos;
    function GetCaretIndex: TTyRichPos;
    procedure SettlePlaces;
    procedure SetSelStart(AValue: TTyRichPos);
    procedure SetSelLength(AValue: TTyRichPos);
    procedure SetCaretIndex(AValue: TTyRichPos);
    function GetCaretPos: TPoint;
    procedure SetCaretPos(const AValue: TPoint);
    function GetAllText: TCaption;
    procedure SetAllText(const AValue: TCaption);
    { The layout parameters are known (a control never laid out takes the theme's now): what
      a query of a block's layout needs, without laying out the view. }
    procedure EnsureParams;
    { The held block paragraph-of-APos is in; -1 when it is not held. }
    function HeldBlockOf(APos: TTyRichPos): Integer;
    { The caret rectangle at APos in raster pixels of the view: x from the text area's left
      (the horizontal scroll taken off), y from its top. False when APos is in no held block. }
    function CaretRaster(APos: TTyRichPos; AAtEnd: Boolean; out ARect: TRect): Boolean;
    { The caret place at layout x AX, view y AY (raster pixels) among the held blocks (the
      first or last one above or below them), and its affinity; -1 when none is held. }
    function HitRaster(AX, AY: Int64; out AAtEnd: Boolean): TTyRichPos;
    { Paragraph APara is a covered cell's: an empty cell that continues a vertical merge (the
      cell above reaches over it; Word keeps such a cell, empty, in the row's text). It shows
      nothing, takes no caret and is no place of the Tab order. One that holds something (a
      file may put text, even a nested table, there) stays a cell of its own: nothing it shows
      is out of reach. Reads inside a read scope of its own. }
    function CoveredPara(APara: Integer): Boolean;
    { APos, or - when it is in a covered cell - the end of the text of the cell that covers it
      (a click, a hit anywhere in a span lands in the cell the span starts with). }
    function SpanOwnerPos(APos: TTyRichPos): TTyRichPos;
    { APos, or - in a covered cell - the first place past it (AForward) or before it. }
    function PastCovered(APos: TTyRichPos; AForward: Boolean): TTyRichPos;
    function HitClient(X, Y: Integer; out AAtEnd: Boolean): TTyRichPos;
    { The caret place at layout x AX on the first (ADown) or the last line of the block after
      (before) held block AK, laid out here when it is not held; -1 when there is none. }
    function HitNeighbour(AK: Integer; ADown: Boolean; AX: Integer; out AAtEnd: Boolean): TTyRichPos;
    { The caret place on the line below (above) the caret's at the wished x: the line in its
      block, else the block after (before) it, held or not; -1 when there is none. The caret's
      rectangle is AR (CaretRaster). }
    function LineFrom(const AR: TRect; ADown: Boolean; out AAtEnd: Boolean): TTyRichPos;
    { APos clamped to the document and moved back to a caret place (a cluster's start, an
      object's or an escaped byte's first character, out of a cell merged away); a place in a
      cut paragraph's hidden tail is kept (it shows at the cut). }
    function SnapPos(APos: TTyRichPos): TTyRichPos;
    { The user's moves never leave the caret or the anchor in a cut paragraph's hidden tail. }
    function OutOfTail(APos: TTyRichPos; AForward: Boolean): TTyRichPos;
    { The caret and the anchor a document change moved, put on caret places. It calls
      no user code: a move is reported by the user action it runs in (its one report at its
      end), else by a queued call after it. }
    procedure SnapAfterChange;
    { The document holds back changes the view has not heard of (TTyRichDocument.Updating, or
      a content the view was not told of yet): the view's blocks may name paragraphs that are
      gone. The one door every entry that needs the layout asks first - the paint and the
      caret, the blink and the drag ticks, keys, the wheel, the mouse, the input method's
      query, the public settled queries and the selection (Select, the selection setters):
      input does nothing (a key the viewer takes is still taken), a query answers "not
      available", a selection is kept and painted when the update ends. }
    function ViewBehind: Boolean;
    procedure StartBlink;
    { The background work's next turn queued (StepCall) or taken off the queue; the selection
      report queued. }
    procedure ScheduleCall(ACall: TTyRichQueuedCall);
    procedure CancelCall(ACall: TTyRichQueuedCall);
    procedure CallFired(ACall: TTyRichQueuedCall);
    procedure TurnTimerTick(Sender: TObject);
    procedure NoteTurn(AMs: Int64);
    procedure SchedulingFailed;
    procedure EndOwedLoad;
    procedure CatchUpBars;
    function CaretStep(APos: TTyRichPos; AForward: Boolean): TTyRichPos;
    function WordStep(APos: TTyRichPos; AForward: Boolean): TTyRichPos;
    procedure WordAt(APos: TTyRichPos; out AFrom, ATo: TTyRichPos);
    procedure MarkUnseen(AStart: TTyRichPos; var ACodes: array of Cardinal);
    procedure ParaRangeAt(APos: TTyRichPos; out AFrom, ATo: TTyRichPos);
    { The object character whose box client point (X, Y) is on, near hit position APos; -1
      when the point is on none. }
    function ObjectAt(X, Y: Integer; APos: TTyRichPos): TTyRichPos;
    { The selection becomes AAnchor .. ACaret: what changed its selected state is painted again
      (only those lines' bands); nothing else - the caller scrolls, blinks and reports. }
    procedure Select(AAnchor, ACaret: TTyRichPos; AAtEnd: Boolean);
    { The one door of every caret place and selection end: Select puts both through it, so the
      keys and their Shift, a click, a drag, a word's or a paragraph's selection, the caret an
      edit, an undo or a redo leaves, a find's selection and SelStart / SelLength / CaretIndex
      from code all land on it. A run of objects the layout gives no width (a field's marks, a
      bookmark's ends) is one place, and the caret has one position there
      (TTyBlockLayout.RestPos): before a link's open mark at its start, after its close mark at
      its end - what is typed there goes outside the link. A place with no object beside it is
      its own (nothing is laid out for it). }
    function RestingPlace(APos: TTyRichPos): TTyRichPos;
    { A place AGiven (on its line with AAtEnd) rested to ARested: True when ARested is shown on
      that same line only with the line-end affinity (it is where that line wraps) - the caret
      stays on the line it was put on. }
    function RestKeepsLineEnd(AGiven, ARested: TTyRichPos; AAtEnd: Boolean): Boolean;
    { The other end of the run of objects with no width APos stands in or beside (AForward its
      end, else its start); APos when there is none. }
    function UnseenEnd(APos: TTyRichPos; AForward: Boolean): TTyRichPos;
    { [AStart, AStart + ALen) grown to the smallest range that holds, whole, every field it cuts
      (takes one mark of and not the other) - also once its ends are put on resting places;
      False when it cuts none. A field around the whole range is not cut. }
    function FieldCover(var AStart, ALen: TTyRichPos): Boolean;
    { A user's edit of [AStart, AStart + ALen) - the selection - that cuts a field: the
      selection grows to hold the fields whole and nothing changes (True; the caller tells the
      refusal or not). False when the range cuts no field. }
    function GrowOverFields(AStart, ALen: TTyRichPos): Boolean;
    { [AFrom, ATo] lies wholly inside one field's result (a caret: AFrom = ATo inside any): an
      edit there is an edit inside that result, refused as it is - the selection does not
      grow. Reads the two ends' paragraphs; those between by their depths (no parse). }
    function InsideOneResult(AFrom, ATo: TTyRichPos): Boolean;
    { [AFrom, ATo) holds a field's mark. }
    function TakesField(AFrom, ATo: TTyRichPos): Boolean;
    // the selection becomes that range, reported (GrowOverFields' and the delete keys')
    procedure ShowCover(AStart, ALen: TTyRichPos);
    { Links. CharBoxAt: the character whose box client point (X, Y) is on (-1: none - the
      space right of a line's end, a paragraph's end, an object with no width). LinkOfChar:
      the innermost HYPERLINK field around character AChar - its open mark's position and its
      target - from what is known (KnownField) or read once and kept. LinkPress: a press of
      AButton that LinkClickFires takes on a link - kept, nothing else done (True). The
      release on the same link fires the click (LinkRelease); a move past the drag threshold
      makes it the press it would have been (ReplayPress). }
    function CharBoxAt(X, Y: Integer): TTyRichPos;
    function KnownField(AOpen: TTyRichPos): Integer;
    function KnownAround(APos: TTyRichPos; ADepth: Integer): Integer;
    function KnowField(AOpen, AClose: TTyRichPos; ADepth: Integer): Integer;
    function LinkOfChar(AChar: TTyRichPos; out AOpen: TTyRichPos; out AURL: string): Boolean;
    function LinkPress(AButton: TMouseButton; AShift: TShiftState; X, Y: Integer): Boolean;
    procedure LinkRelease(AButton: TMouseButton; X, Y: Integer);
    procedure ReplayPress;
    // the hand comes or goes where the pointer is, for the keys AShift (Ctrl down or up)
    procedure PointerKeysChanged(AShift: TShiftState);
    procedure RepaintRange(AFrom, ATo: TTyRichPos);
    { The caret moved: where it was drawn and where it is now are blitted again (the window
      only: the caret is drawn over the blit), and it shows at once. }
    procedure CaretMoved;
    { The end of a user's move: scrolled into view, caret shown, the move reported. }
    procedure Moved(AKeepWish: Boolean);
    procedure MoveVertical(ADown, AExtend: Boolean);
    procedure MoveInLine(AToEnd, AExtend: Boolean);
    procedure MovePage(ADown, AExtend: Boolean);
    procedure ExtendDragTo(X, Y: Integer);
    procedure StopDrag;
    procedure StartDragTimer;
    { Dragging the selection: a press may begin one (DragStartOpen, PressInSelection); the
      click a press and release without a drag is (PlainClick); the control's own drag
      begun, ended with nothing done, its edge scrolling, the mark's place and the drop's
      work. }
    function DragStartOpen: Boolean;
    function PressInSelection(X, Y: Integer): Boolean;
    procedure PlainClick(X, Y: Integer; AQ: TTyRichPos; AAtEnd: Boolean; AObj: TTyRichPos);
    procedure ReleasePending;
    function BeginSelectionDrag(X, Y: Integer; AShift: TShiftState): Boolean;
    function EndBackgroundForUser: Boolean;
    { A view's move during a drop (a scroll, a zoom, a new size): the place, the mark and the
      verdict worked out again at the pointer's last place. }
    procedure DropFollowPointer;
    procedure CancelSelectionDrag;
    function OwnDragging: Boolean;
    { A drag of the control's own runs: a handle's (FResizing), the selection's (OwnDragging)
      or a press inside the selection waiting for one (FDragPending). EndOwnDrag ends it with
      nothing changed (and a press's owed click). OwnDragKey: a key down during it is the
      drag's (True) - Esc ends it, taken; Ctrl makes the drop a copy at once; Shift, Alt and
      the Windows keys do nothing; any other key is taken and does nothing, the drag going on
      as it was - as the system's drag and drop, which delivers no other key while it runs. }
    function OwnDragRunning: Boolean;
    procedure EndOwnDrag;
    function OwnDragKey(var Key: Word): Boolean;
    procedure DropScrollTick;
    function DropPlaceAt(X, Y: Integer; out AAtEnd: Boolean): TTyRichPos;
    function DropMarkRaster(out ARect: TRect): Boolean;
    procedure ShowDropCursor;
    { The drop's work at APos. AWentIn: content from elsewhere went in (the caller gives the
      control the focus). }
    function DropInto(AOffer: TTyRichDropOffer; APos: TTyRichPos; AEffect: TTyRichDropEffect;
      AShift: TShiftState; out AWentIn: Boolean): TTyRichDropEffect;
    { The control's own drag outside its client area: the session of the rich edit under the
      pointer (DropTargetAt) is fed, the one it left ended; AInside: over the control itself
      (no other is). }
    procedure FeedPeer(X, Y: Integer; AShift: TShiftState; AInside: Boolean);
    procedure EndPeer;
    { A session fed by another control's drag (APeer's, ours its source) gave a new verdict
      outside a call from it (its edge scrolling, a zoom, its end): the cursor says it. }
    procedure PeerVerdict(APeer: TTyCustomRichEdit; AEffect: TTyRichDropEffect);
    { What a move into another control leaves to its source: [AFrom, AFrom + ALen) removed,
      one step of this document's own (as a cut removes it). }
    procedure RemoveMovedAway(AFrom, ALen: TTyRichPos);
    { A file list's drop at APos: OnDropFiles first, then the pictures (one step). }
    function DropFileList(AOffer: TTyRichDropOffer; const AFiles: TStringArray;
      APos: TTyRichPos; AEffect: TTyRichDropEffect; out AWentIn: Boolean): TTyRichDropEffect;
    { DropFilesArePictures for AOffer's AFiles, the answer kept for the session's offer. }
    function OfferedPictures(AOffer: TTyRichDropOffer; const AFiles: TStringArray): Boolean;
    function InsertPictureFiles(const AFiles: TStringArray; APos: TTyRichPos): Boolean;
    procedure SetDragDropEditing(AValue: Boolean);
    procedure SetAcceptDrops(AValue: Boolean);
    { Registers the window with the system as a drop target, or revokes it, as AcceptDrops,
      the window and the designer say (the Windows widgetset; nothing elsewhere). }
    procedure SyncDropRegistration;
    procedure RevokeDropRegistration;
    procedure SetScrollXRaster(AValue: Integer);
    function GetSelText: string;
    procedure SetSelText(const AValue: string);
    // editing
    { Why the document takes no edit now ('' when it does): loading, incomplete, saving. }
    function RefusalReason: string;
    { AUser (a key, the menu): EditRefused; otherwise (code) ETyRichEdit is raised. }
    procedure Refuse(const AReason: string; AUser: Boolean);
    function EngineRefusal(E: Exception): string;
    function ChangeRefusalText(APos, ALen: TTyRichPos): string;
    { A user's insert of AText at APos would put its end past the cut of a paragraph too long
      to lay out whole: refused (told), True. }
    function LongParaRefused(APos: TTyRichPos; const AText: UTF8String): Boolean;
    { A user's edit that deletes or replaces [AStart, AStart + ALen): a selection that ends at
      a table's first row and begins before it keeps its last separator (ALen one less); one
      that crosses a cell's or a row's edge is refused (told, False) unless it is whole rows. }
    function UserRangeAllowed(var AStart, ALen: TTyRichPos): Boolean;
    { [AFrom, ATo) is whole rows of one table: from a row's first paragraph's start to the
      start of the paragraph after a row (never the text's end). Inside a read scope. }
    function WholeRows(AFrom, ATo: TTyRichPos): Boolean;
    { Paragraph AIndex out of its list: the numbering goes, the start indent and the hanging
      offset go to 0 (msftedit's reset; the right indent and the alignment stay); one step. }
    procedure LeaveList(AIndex: Integer);
    { The committed text as the key-press events let it through (win32, as the memo's commits
      arrive there): each character asked as a typed one is. }
    function AskCommitKeys(const AText: UTF8String): UTF8String;
    { The caret the user sees: the composition's while composing, else the caret's. }
    function ShownCaretRaster(out ARect: TRect): Boolean;
    { The edit may run: the document takes edits now, and deleting ALen characters at APos
      (and, with AInsert, inserting at APos then) is not refused by a row that holds a nested
      table. Refused: Refuse, False. }
    function EditAllowed(APos, ALen: TTyRichPos; AInsert, AUser: Boolean): Boolean;
    { After an edit of the control's own: the selection AAnchor .. ACaret (put on caret places,
      never in a cut paragraph's hidden tail, AAtEnd the caret's affinity where it stays put,
      the wished x forgotten), scrolled into view, the caret shown, then the one OnChange and
      the one OnSelectionChange of the action. ARestore: a selection an undo puts back as it
      was before its step, taken as it is (a hidden tail too - Select All had it). }
    procedure FinishEdit(AAnchor, ACaret: TTyRichPos; AAtEnd: Boolean = False;
      ARestore: Boolean = False);
    { Runs ACmd (the document owns it from here) as the control's own edit: True when it ran
      and changed something - FEditChange is what it changed, the caret has not been placed.
      The step it became carries the selection before it (its marks; the selection after it
      is FinishEdit's). Refused by the engine (CanExecute, an ETyRichModel the command
      reverted): the caret, the selection and Modified stay as they were, and Refuse with
      the reason that holds (CommandRefusal, EngineRefusal). AUser: told (OnEditRefused),
      else raised (ETyRichEdit). The half of an edit both RunEdit's callers share: a user's
      edit (RunUserEdit) and an edit from code (EditWith). }
    function RunEdit(ACmd: TTyRichCommand; AUser: Boolean): Boolean;
    { Inside any update of the document (BeginEdit .. EndEdit, Lines.BeginUpdate .. EndUpdate,
      Document.BeginUpdate .. EndUpdate) the document holds its reports until the update
      ends: after a write of the control's own (ACmd run through Execute; AStateBefore the
      content's state number before it) this hears its change itself - FEditChange set, the
      caret and the anchor moved over a text change as DocChanged moves them outside an
      update - and keeps the positions out of the update's one change at its end
      (FPosInUpdate). So Delphi's anti-flicker bracket around SelText writes gives what the
      same writes give without it. False when outside an update or when ACmd changed nothing
      (and is gone). }
    function FollowBlockWrite(ACmd: TTyRichCommand; AStateBefore: Int64): Boolean;
    { FollowBlockWrite's moving of the caret and the anchor over AChange (inside an update). }
    procedure FollowBlockChange(const AChange: TTyRichChange);
    { The command AMake makes, run (RunEdit) and finished (FinishEdit, at the place it says):
      what a user's edit (RunUserEdit, AUser True) and an edit from code (AUser False: refusals
      raised, ReadOnly not asked) share. AEnded: TTyRichEditPlace.CompositionEnded. }
    function EditWith(AMake: TTyRichEditMaker; AUser, AEnded: Boolean): Boolean;
    { RunMade's maker: the command made before - dropped (freed, nil) when the door ended a
      composition first, for it was made on the text before that commit. }
    function TakeMade(var APlace: TTyRichEditPlace): TTyRichCommand;
    // links
    { The open mark at AOpen is a HYPERLINK field's (its target in AURL). }
    function IsLinkField(AOpen: TTyRichPos; out AURL: string): Boolean;
    { Why a link cannot go over [AStart, AStart + ALen) now ('' it can): a place where the text
      cannot change, an end in a field's result, a range past its paragraph's end, a range that
      holds a field's mark. Reads the range's paragraph. }
    function LinkPlaceRefusal(AStart, ALen: TTyRichPos): string;
    { The link actions may be asked of the control at all: not ReadOnly, enabled, not inside the
      document's update, the document taking edits, not a plain text document. }
    function LinkActionsOpen: Boolean;
    { The door's makers of InsertLink, SetLink and RemoveLink (their arguments in FLinkArg...). }
    function MakeInsertLink(var APlace: TTyRichEditPlace): TTyRichCommand;
    function MakeSetLink(var APlace: TTyRichEditPlace): TTyRichCommand;
    function MakeRemoveLink(var APlace: TTyRichEditPlace): TTyRichCommand;
    { The layouter's question (TTyRichLayouter.OnLinkField): the field's open mark found near
      (FieldOpenNear), its instruction read - never a walk of a long field. }
    function LayoutLinkField(AAt: TTyRichPos; ADepth: Integer): Boolean;
    { The layouter laid out rows that merged cells tie together: their heights into the
      height index - every row of them, shown or not - when laid out for the view; and when
      their layouts went with a change, their heights estimates until they are laid out. }
    procedure LayoutSpanHeights(const AFirsts, ALasts, AHeights: array of Integer;
      AWidth, APPI: Integer; AZoom: Single);
    procedure LayoutSpanDropped(AFirst, ALast: Integer);
    { The open mark of the field around APos that is ADepth deep there (1 the outermost): in
      APos's paragraph, else in one of the CRichLinkLookBack paragraphs before it (passed by
      their depths). -1: none found there. }
    function FieldOpenNear(APos: TTyRichPos; ADepth: Integer): TTyRichPos;
    // bookmarks
    { A jump's view (GoToBookmark): the caret's line at the view's top - unless it is in view
      already, whole, in the view's top third (then nothing moves); near the document's end
      the view ends at its end, as any scroll. Across: only when the caret is out of view. }
    procedure ShowCaretAtTop;
    function MakeAddBookmark(var APlace: TTyRichEditPlace): TTyRichCommand;
    function MakeDeleteBookmark(var APlace: TTyRichEditPlace): TTyRichCommand;
    function MakeRenameBookmark(var APlace: TTyRichEditPlace): TTyRichCommand;
    { After a link's click: a "#name" link followed to its bookmark (FollowBookmarkLinks,
      OnFollowLink). }
    procedure FollowLink(const AURL: string);
    // objects' clicks
    { The position of the object with a width under client point (X, Y); -1 none. }
    function ObjectPosAtPoint(X, Y: Integer): TTyRichPos;
    { OnObjectDblClick (ADouble) or OnObjectClick for the object at APos, through the lifetime
      guard (the handler may free the control: ETyRichGone travels on). True: AHandled. }
    function FireObjectEvent(ADouble: Boolean; APos: TTyRichPos; AButton: TMouseButton;
      AShift: TShiftState; X, Y: Integer): Boolean;
    { The client box of the object at APos in a held block; False: not laid out in view. }
    function ObjectClientRect(APos: TTyRichPos; out ARect: TRect): Boolean;
    { A release of the button an object's press began with, on that object, no drag between:
      its click. True: handled. }
    function ObjectRelease(AButton: TMouseButton; AShift: TShiftState; X, Y: Integer): Boolean;
    // tables
    { What the user is told when table edit AEdit is refused for AReason. }
    function TableRefusalText(AReason: TTyRichTableRefusal; const AEdit: TTyRichTableEdit): string;
    { The reason of a built-in table command the document refused (RunEdit keeps only its
      edit): CommandRefusal asked of a command like it. }
    function LateTableRefusal(const AEdit: TTyRichTableEdit): string;
    { A table action (FTableKind) through the door of a user's edit: disabled, ReadOnly or
      inside the document's update, nothing (nothing told, as for the user's other actions);
      a plain text document, refused (told). True: it ran. }
    function RunTableAction(AKind: Integer): Boolean;
    { The door's maker of a table action: the command for the caret's (the selection's) table
      as it is now, FAim... set for TableEditCaret; nil and told when the table or the place
      refuses it. }
    function MakeTableEdit(var APlace: TTyRichEditPlace): TTyRichCommand;
    { Rows AR1 .. AR2 of the table at ATablePos deleted where a merge down meets them: from the
      last up, each row's content of a merge that goes on below them moved first into the row
      that then follows (one step). nil: no merge down in them or beside them - the plain way. }
    function SpanRowsDelete(ATablePos: TTyRichPos; AR1, AR2, AFirstPara: Integer): TTyRichCommand;
    { The columns of the table at ATablePos by the grid (merged cells, rows of different cells):
      AInsert, as many as AX0 .. AX1 covers at its right (AAfter) or left edge, each as wide as
      the grid's column beside it; else those AX0 .. AX1 covers deleted. nil: the table is a
      plain grid (the edits by index do it) - or, with AWhole set, the columns are all of it. }
    function GridColumnsEdit(ATablePos: TTyRichPos; AX0, AX1: Integer; AInsert, AAfter: Boolean;
      out AWhole: Boolean): TTyRichCommand;
    function MakeTableEditThen(var APlace: TTyRichEditPlace): TTyRichCommand;
    { Where the table action that just ran leaves the caret (FAim...), in the text as it is
      now. }
    function TableEditCaret: TTyRichPos;
    { The start of the paragraph of cell ACell of the row paragraph AFirst begins (its first
      paragraph; a row with fewer cells: its last cell's). Inside a read scope. }
    function CellStartInRow(AFirst, ACell: Integer): TTyRichPos;
    { The first paragraph of row ARow (counted as TableInfoAt counts them) of the table whose
      first paragraph is AFirst. Inside a read scope. }
    function RowFirstPara(AFirst, ARow: Integer): Integer;
    { What the Can... functions answer, found once for the content, the selection and the
      document's state as they are (FAsk...). }
    procedure AskTables;
    // the table the answers keep, let go
    procedure ReleaseAskedTable;
    { Can a table action be asked of the control now at all: not ReadOnly, enabled, not inside
      the document's update, the document taking edits, not a plain text document. }
    function TableActionsOpen: Boolean;
    { The paragraph whose table the actions take: the caret's - but a caret at the start of a
      paragraph that ends a selection (whole rows selected down to the next row's start)
      stands for the paragraph before it, the last one selected. }
    function CaretTablePara: Integer;
    // the merge the selection asks for (False: it is not cells of one table)
    function SplitRefusalText(const AEdit: TTyRichTableEdit): string;
    { The rows the cell of APara covers when it begins a merge down (its extent row by row, as
      the grid reads it): ASpan of them, the last one's first and last paragraphs. False: no
      merge down (ASpan 1, APara's own row). }
    function MergedRowsOf(APara: Integer; out ASpan, ALastFirst, ALastLast: Integer): Boolean;
    function MergeEditOf(out AArea: TTyRichCellArea; out AEdit: TTyRichTableEdit): Boolean;
    { The cell a split takes - the caret's, or the one cell selected -: its row, index, the
      rows it covers, its extent (twips) and the first paragraph of its row. False: none. }
    function SplitTarget(out ARow, ACell, ASpan, ALeft, ARight, ARowPara: Integer): Boolean;
    { (AGrid: the grid read for a cell over as many columns as ACols - an answer reads none) }
    function SplitEditOf(ACols, ARows: Integer; AGrid: Boolean; out AEdit: TTyRichTableEdit): Boolean;
    { Tab (AForward) or Shift+Tab with the caret in a table: to the next (previous) cell shown,
      its content selected; at the last cell of the table a person sees, a new row (through
      the door). False when the caret is in no table: the key is not the table's. }
    function TableTab(AForward: Boolean): Boolean;
    { What typing AText over [AStart, AStart + ALen) asks before anything is made (EditAllowed,
      and for a user UserRangeAllowed - which may shrink ALen - and LongParaRefused): refused
      (told), False. A composition begins only where this says yes (one character for it). }
    function TypingAllowed(var AStart, ALen: TTyRichPos; const AText: UTF8String;
      AUser: Boolean): Boolean;
    { The one routine of typing - a key's character, Enter, Tab, SelText from code and an input
      method's commit: AText in place of the selection (one undo step: delete and insert),
      else at the caret - AMergeable: typing, which merges with the typing before it - in
      AFormat (left at Low(TTyCharFormatId): TypingFormat asked now; a commit passes the
      format its composition was shown in). The caret behind it: ACaretChars characters from the start
      when >= 0 (a commit's own count), else the end of what the document reports changed. }
    procedure TypeText(const AText: UTF8String; AMergeable, AUser: Boolean;
      AFormat: TTyCharFormatId = Low(TTyCharFormatId); ACaretChars: Int64 = -1);
    { Characters [AFrom, ATo) go; the caret at the join. }
    procedure DeleteText(AFrom, ATo: TTyRichPos; AUser: Boolean);
    { Backspace (AForward False) or Delete, by a character place or (AWord) by a word: the
      selection when there is one. }
    procedure DeleteKey(AForward, AWord: Boolean);
    { May a key take [AFrom, ATo) away when nothing is selected: not across a cell's edge,
      and not the separator after a cut paragraph. }
    function KeyDeleteAllowed(AFrom, ATo: TTyRichPos): Boolean;
    { Enter: a new paragraph, or on an empty list item the item out of the list. }
    procedure ParagraphKey;
    procedure CutSelection(AUser: Boolean);
    { What a copy puts on the clipboard, of [AStart, AStart + ALen): both flavours. }
    procedure CopyRange(AStart, ALen: TTyRichPos);
    { [AStart, AStart + ALen) as a copy writes it as RTF ('' when the writer refuses it). }
    function RangeRtf(AStart, ALen: TTyRichPos): RawByteString;
    { What a paste does with AOffer's flavours (AHave of them) over [AStart, AStart + ALen),
      one step named AName, once the place was found to take an edit: the paste's whole body
      (PasteFromClipboard says what goes in and what is refused). ASelect: what went in is
      selected (a drop), else the caret is behind it (a paste). True: it went in. }
    function InsertOffer(AOffer: TTyRichDropOffer; AHave: TTyRichClipFlavours; AStart,
      ALen: TTyRichPos; AAs: TTyRichPasteAs; const AName: string;
      ASelect: Boolean = False): Boolean;
    function InsertOfferIn(AOffer: TTyRichDropOffer; AHave: TTyRichClipFlavours; AStart,
      ALen: TTyRichPos; AAs: TTyRichPasteAs; const AName: string; ASelect: Boolean;
      var ALife: TTyRichLife): Boolean;
    { A clipboard's text made fit to insert (see PasteFromClipboard). }
    function PastedText(const AText: RawByteString): UTF8String;
    { The width a picture pasted at APos may take, in twips: the view's text width (0 when
      nothing wraps) less the paragraph's indents, or its cell's width. }
    function PictureRoom(APos: TTyRichPos): Integer;
    // pictures from code
    { The door of the picture inserts: an open composition ends first; ReadOnly, disabled or
      inside the document's update nothing (False, nothing told); a plain text document and a
      document that takes no edit now refused (told). }
    function PictureInsertOpen: Boolean;
    { AStream to its end into ABytes, at most CRichPictureMaxBytes: False when it is larger
      (rsRichEditRefusedPicture) or cannot be read (a file's: rsRichEditRefusedPictureFile
      with the system's words, else rsRichEditRefusedNoPicture) - told. }
    function ReadPictureStream(AStream: TStream; AFromFile: Boolean; out ABytes: TBytes): Boolean;
    { ABytes as a picture: PNG and JPEG kept, a bitmap or TIFF decoded to PNG, a metafile
      refused, anything else decoded by the LCL's graphic classes (InsertPicture). }
    function InsertPictureBytes(const ABytes: TBytes): Boolean;
    { ABytes that are none of the kinds told by their first bytes, read by the LCL's graphic
      classes and given back as a picture keeps them (GraphicBytes). An icon or a cursor is
      told by its header here: the LCL of Lazarus 3.0 does not know either from a stream.
      False: refused - told. }
    function LclPictureBytes(const ABytes: TBytes; out AOut: TBytes;
      out AKind: TTyRichImageKind): Boolean;
    { ABytes of AKind as the picture that replaces the selection: one undo step. }
    function InsertPictureMade(const ABytes: TBytes; AKind: TTyRichImageKind): Boolean;
    function InsertGraphicCore(AGraphic: TGraphic): Boolean;
    { AGraphic's bytes as a picture keeps them (PNG and JPEG as they are, else as PNG): False
      when it cannot be written (told). }
    function GraphicBytes(AGraphic: TGraphic; out ABytes: TBytes;
      out AKind: TTyRichImageKind): Boolean;
    { ABytes of AKind as a picture for APos (TyRichMakePicture): False when they are no image
      or too large, or memory runs out (told). }
    function MakePictureFor(const ABytes: TBytes; AKind: TTyRichImageKind; APos: TTyRichPos;
      out APicture: TTyRichPicture): Boolean;
    { A file's bytes as InsertPictureFromFile takes them, as a picture for APos (told when not). }
    function PictureOfFileBytes(const ABytes: TBytes; APos: TTyRichPos;
      out APicture: TTyRichPicture): Boolean;
    // the handles and the resize
    { The object the selection is exactly, when it shows handles - it can be resized and the
      user's edit would be taken there (not ReadOnly, enabled, the document taking edits, the
      place changeable) and its block is held: its character and its box (raster pixels of
      the view). }
    function HandleObject(out APos: TTyRichPos; out ABox: TRect): Boolean;
    { A handle's side and the outline's width in raster pixels (the screen's PPI, not Zoom). }
    function HandlePx: Integer;
    function OverlayLinePx: Integer;
    { The eight handles around ABox (raster pixels), centred on the frame's pixels. }
    function HandleRectsOf(const ABox: TRect): TTyRichHandleRects;
    { What the handles of ABox and its frame cover (raster pixels). }
    function HandleAreaOf(const ABox: TRect): TRect;
    { The resize's outline (raster pixels) for a size of AWidth x AHeight twips, the side
      opposite the dragged handle where it was. }
    function PreviewRectOf(AWidth, AHeight: Integer): TRect;
    procedure SyncObjectOverlay;
    { The handles and the outline drawn onto ABitmap, whose text area's top-left is at
      (AX, AY) of it, inside AClip. }
    procedure PaintObjectOverlay(ABitmap: TBGRABitmap; AX, AY: Integer; const AClip: TRect;
      const AStyle: TTyRichPaintStyle);
    function HandleCursor(AHandle: TTyRichHandle): TCursor;
    procedure StartResize(AHandle: TTyRichHandle; APos: TTyRichPos; const ABox: TRect; X, Y: Integer);
    { The size a drag to client (X, Y) asks for (TyRichResizedSize). }
    procedure ResizeSizeAt(X, Y: Integer; AShift: TShiftState; out AWidth, AHeight: Integer);
    procedure MoveResize(X, Y: Integer; AShift: TShiftState);
    procedure FinishResize(X, Y: Integer; AShift: TShiftState);
    { The drag ends with nothing changed: the outline goes. }
    procedure CancelResize;
    { An undo (ARedo False) or a redo step and where it leaves the caret. }
    procedure RunHistory(ARedo, AUser: Boolean);
    { A key the editor takes (it edits, or would: ReadOnly takes it and does nothing, as the
      memo does). }
    function IsEditKey(AKey: Word; AShift: TShiftState): Boolean;
    { A character typed: inserted when it is printable and whole (not with ReadOnly, not
      inside the document's update). }
    procedure TypeKey(const AKey: TUTF8Char);
    // the input method
    { The composition's paragraph shown again: its block laid out again and its band drawn
      (as a change of the document there would, but none was made). }
    procedure RefreshComposed(APara: Integer);
    { The layouter told what the composition is now, and the view shown with it. }
    procedure ShowComposition;
    { The composition's caret in raster pixels of the view, as CaretRaster gives one. }
    function CompositionRaster(out ARect: TRect): Boolean;
    { The composition put away without a trace (nothing is told to the input method). }
    procedure DropComposition;
    { The control ends the composition (the focus left, a user's edit or action, a press, the
      content replaced, ReadOnly set, disabled, the window or the control going): committed
      or cancelled. The input method is told first (ImeEndOnWidgetset); what it does not
      answer here is done here, or (a commit it was told of) when its result comes. }
    procedure EndComposition(ACommit: Boolean);
    { The one door of a user's edit and action: a composition open in the text
      ends first, committed as a press commits it - see the body for who comes through it. }
    procedure EndCompositionForUser;
    { A press at client (X, Y) that the hit test put at the composition's own place (FCompPos):
      True when it is before the composition (left of its start on its first line, or above
      that line), False on it or behind it. }
    function PressBeforeComposition(X, Y: Integer): Boolean;
    { An input method's text made fit to insert: whole UTF-8, CR LF and CR as LF, no control
      character (TypeKey's filter, ControlCodeLen) but tab, LF and U+000B. }
    function ImeText(const AText: string): UTF8String;
    { The candidate window put at the composition's caret (when it moved since). }
    procedure PlaceImeWindows;
    { What the widgetset's own hook (Qt, GTK2) calls: a whole commit, and the caret's place. }
    procedure HookCommit(const ACommitUtf8: string);
    function HookCaretRect: TRect;
    {$IFDEF LCLWin32}
    { win32: the input method's messages (LCL hands them to the control; Result 1 keeps the
      system's composition window and its WM_IME_CHAR away - the composition is shown in the
      text). }
    procedure WMImeStartComposition(var Message: TLMessage); message $010D;
    procedure WMImeEndComposition(var Message: TLMessage); message $010E;
    procedure WMImeComposition(var Message: TLMessage); message $010F;
    procedure WMImeRequest(var Message: TLMessage); message $0288;
    { win32: the system's composition window kept away when the window gets the
      input context (WM_IME_SETCONTEXT); the composition ended where the window loses the
      focus, while it still has the thread's input context; the candidate window put again
      when the focus comes back from another window. }
    procedure WMImeSetContext(var Message: TLMessage); message $0281;
    procedure WMKillFocus(var Message: TLMKillFocus); message LM_KILLFOCUS;
    procedure WMSetFocus(var Message: TLMSetFocus); message LM_SETFOCUS;
    {$ENDIF}
    {$IFDEF LCLCocoa}
    { Cocoa: LCL-Cocoa asks at the handle's creation for the input method handler (the memo's
      way): the one the constructor made. }
    procedure CocoaImComposition(var Message: TLMessage); message LM_IM_COMPOSITION;
    {$ENDIF}
  private
    { The paragraph view (see the public part): who hears that it may have changed (made when
      the first one is added), and the guide line a ruler's drag asks for (client x; drawn
      only while FGuideOn). }
    FParaViewHandlers: TMethodList;
    FGuideOn: Boolean;
    FGuideX: Integer;
    { The parents whose Enabled the paragraph view's hearers hear of (an owned helper,
      TTyRichParentWatch, made with the first hearer): IsEnabled follows them, and they tell
      a child nothing themselves. }
    FParentWatch: TComponent;
    procedure WatchParents;
    procedure ParagraphViewChanged;
    function GetGuideLine: Integer;
    procedure SetGuideLine(AValue: Integer);
    function GuideLineRect: TRect;
  private
    { Column widths and row heights: an edge's drag (CEdgeColumn / CEdgeRow, 0 none) - the
      row's first paragraph, the edge (-1 a row's left), where the row's format has it (twips)
      and where it was laid out (raster), its limits as it is and with the rest following, the
      top of the dragged row, where the drag has it now, Shift held - and the horizontal guide
      a row drag shows (client y). }
    FEdgeDrag: Integer;
    FEdgePara, FEdgeIndex, FEdgeTwips: Integer;
    FEdgeRaster, FEdgeLo, FEdgeHi, FEdgeShiftLo, FEdgeShiftHi, FEdgeNow, FEdgeTop: Int64;
    // where in the edge's band it was pressed: the edge follows the pointer's moves from there
    FEdgeGrab: Int64;
    FEdgeShift: Boolean;
    // a command to run after the table edit, in its step (CellsKey: a deleted row's lone marks)
    FTableThen: TTyRichDropLoneMarks;
    // (MakeTableEdit's: the rows whose shared lines are agreed after it, -2 none)
    FAgreePos: TTyRichPos;
    FAgreeRow0, FAgreeRow1: Integer;
    FGuideRowOn: Boolean;
    FGuideY: Integer;
    function EdgeBand: Integer;
    function RasterOfTwips(ATwips: Int64): Int64;
    function TwipsOfRaster(ARaster: Int64): Integer;
    function EdgeRowOf(ABlock: Integer): TTyRichRow;
    function EdgesOpen: Boolean;
    function EdgeAt(X, Y: Integer; out AKind, ABlock, AIndex: Integer): Boolean;
    function MinCellTwips(ARow: TTyRichRow; ACell: Integer): Integer;
    // the rows an edge change of row ARow (paragraph APara) moves: read once
    function EdgeMovedRows(ARow: TTyRichRow; APara: Integer): TTyRichRowList;
    procedure SharedEdgeLimits(ARow: TTyRichRow; const ARows: TTyRichRowList; AEdgeTwips: Integer;
      var ALo, AHi, AShiftLo, AShiftHi: Integer);
    procedure EdgeLimits(ARow: TTyRichRow; AIndex: Integer; out ALo, AHi, AShiftLo,
      AShiftHi: Integer);
    function EdgeRows(APara: Integer; AWhole: Boolean; out ATablePos: TTyRichPos;
      out ARow0, ARow1: Integer): Boolean;
    function RunEdgeCommand(ACmd: TTyRichTablePropsCommand): Boolean;
    function RunEdgeParts(const AParts: array of TTyRichTablePropsCommand; const ADescription: string): Boolean;
    function PropsRefusalText(AWhy: TTyRichTableRefusal; const AEdit: TTyRichPropEdit): string;
    procedure SetGuideRow(AValue: Integer);
    function GuideRowRect: TRect;
    function EdgePress(X, Y: Integer; AShift: TShiftState): Boolean;
    procedure ShowEdgeGuide;
    procedure EdgeMove(X, Y: Integer; AShift: TShiftState);
    procedure CancelEdgeDrag;
    procedure EdgeRelease(X, Y: Integer; AShift: TShiftState);
    function WidestRun(APara: Integer): Integer;
    function FitColumnAt(APara, ACell: Integer): Boolean;
    function CaretEdgePara(out APara, ACell: Integer; ATell: Boolean): Boolean;
    function CellTarget(out ATablePos: TTyRichPos; out ARow0, ACol0, ARow1, ACol1: Integer;
      ATell: Boolean): Boolean;
    function RunCellProps(ACmd: TTyRichCommand; ASkipped: Integer = 0): Boolean;
    function TableAlignDoor(AAlign: TTyRowAlign; AIndentTwips: Integer; ASetIndent: Boolean): Boolean;
    // the columns a width door takes: the selected cells' (caret's row's indexes), else the caret's
    procedure WidthColumns(APara, ACell: Integer; out ACol0, ACol1: Integer);
    { Columns ACol0 .. ACol0 + High(AWidths) of the rows the door takes made AWidths[i] wide,
      the columns after them following: one step. }
    { Columns ACol0 .. of the row of APara set to AWidths, the rest of each row following. An
      edge moves in every row that has it, all by the same amount: no further left than every
      such row's cell before it allows (its narrowest - AKeepContent: and what its content
      needs, when it holds any), so the rows stay one table. }
    function SetColumnWidths(APara, ACol0: Integer; const AWidths: array of Integer;
      AKeepContent: Boolean = False): Boolean;
    function FitWidthOf(APara, ACell: Integer; out AWidth: Integer): Boolean;
    procedure TellSkipped;
    function EdgeRowsWhole(APara: Integer; out ATablePos: TTyRichPos;
      out ARow0, ARow1: Integer): Boolean;
    function UserTableDoorOpen: Boolean;
    function CaretParaRead: Boolean;
  private
    { Cell selection (tyControls.RichEdit.TableSel): the cells the selection covers, kept
      for the anchor, the caret and the document's state they were read for; the rows a
      paint highlighted (a count for tests); the table whose handle shows (the first
      paragraph of its first row, -1 none); a press on a zone and its drag. }
    FCellArea: TTyRichCellArea;
    FCellAreaValid: Boolean;
    FCellAreaAnchor, FCellAreaCaret: TTyRichPos;
    FCellAreaState: Int64;
    FCellRowsPainted: Int64;
    FHandlePara: Integer;
    FCellDrag: Integer;
    FCellDragPara, FCellDragLast: Integer;
    function CellArea: TTyRichCellArea;
    function CaretCellPara: Integer;
    function SelectCells(AKind: Integer): Boolean;
    function CellsKey(AForward: Boolean): Boolean;
    procedure ClearArea(const AArea: TTyRichCellArea);
    function FirstAreaCell(const AArea: TTyRichCellArea; out AFirst, ALast: Integer): Boolean;
    function AreaCellCommand(const AArea: TTyRichCellArea; AParas: Boolean; AMaskC: TTyCharFormatMask;
      const AChar: TTyCharFormat; AKeep: TTyCharFormatMask; AMaskP: TTyParaFormatMask;
      const APara: TTyParaFormat): TTyRichCommand;
    function CellsAreTheSelection(AStart, ALen: TTyRichPos): Boolean;
    procedure CopyCells(const AArea: TTyRichCellArea);
    function CellsFlavours(const AArea: TTyRichCellArea; out ARtf: RawByteString;
      out AText: string): Boolean;
    function RangeIsCells(AFrom, ALen: TTyRichPos; out AArea: TTyRichCellArea): Boolean;
    function PasteCells(AOffer: TTyRichDropOffer; AHave: TTyRichClipFlavours; AAs: TTyRichPasteAs;
      APos: TTyRichPos; const AName: string): Boolean;
    function MakeCellsPaste(AOffer: TTyRichDropOffer; AHave: TTyRichClipFlavours; AAs: TTyRichPasteAs;
      APos: TTyRichPos; const AName: string; out ATarget: TTyRichPos): TTyRichCellsEdit;
    function TableZoneAt(X, Y: Integer; out AZone, APara: Integer): Boolean;
    { The zone left of row layout R, in the view's raster units: ALo .. AHi - 1. }
    procedure RowZoneSpan(R: TTyRowLayout; out ALo, AHi: Int64);
    function ZoneMinRaster: Int64;
    { A Shift+press on a row's or a column's zone: the selection grows by whole rows (columns)
      from the anchor's. }
    function TableZoneExtend(X, Y: Integer): Boolean;
    function AreaWholeColumns(const AArea: TTyRichCellArea): Boolean;
    procedure TableZoneDragTo(APara: Integer);
    function TableZonePress(X, Y: Integer): Boolean;
    procedure TableZoneDrag(X, Y: Integer);
    procedure TableHandleHover(X, Y: Integer);
    function TableHandleRect(ABlock: Integer): TRect;
    procedure PaintTableHandle(ABitmap: TBGRABitmap; AX, AY: Integer; const AClip: TRect;
      const AStyle: TTyRichPaintStyle);
  protected
    { Diagnostics a test's subclass reads: the table rows the last paints highlighted as
      selected cells; whether a drag of a table's edge is under way; the row guide's client y
      (-1 none). }
    property CellRowsPainted: Int64 read FCellRowsPainted write FCellRowsPainted;
    function EdgeDragging: Boolean;
    property GuideRow: Integer read FGuideY;
    { Whether the user may select at all: False, the table's zones and handle do not show
      and the Select... methods do nothing. AllowSelection here. }
    function SelectionAllowed: Boolean; virtual;
    { The guides a ruler's drag (GuideLine) and a table edge's drag show, over the blit as the
      caret is (Paint draws them; a test's picture can too). }
    procedure DrawGuideLine(ACanvas: TCanvas);
    { (the parents a paragraph view hearer's Enabled follows are watched again) }
    procedure SetParent(NewParent: TWinControl); override;
    function GetStyleTypeKey: string; override;
    { Caption IS Text, as on LCL's TCustomMemo and the package's Memo: code holding the
      control as a TControl (an action link, a generic text reader) reaches the document. }
    function RealGetText: TCaption; override;
    procedure RealSetText(const AValue: TCaption); override;
    { TControl.ActionChange copies a linked action's Caption into Caption: the content stays. }
    procedure ActionChange(Sender: TObject; CheckDefaults: Boolean); override;
    { The one door of a user's edit - every edit a key, the menu, a paste or an
      input method's commit makes goes through it, and so does a descendant's own command (a
      toolbar's or a menu's action). In this order:
      - ReadOnly (or disabled, or inside the document's update): nothing happens, nothing is
        told - a viewer takes the key and does nothing, as the memo does;
      - an open composition ends first: what the input method shows goes in where it was
        shown (EndCompositionForUser) - so AMake is called only after that commit, and makes
        its command from the text and the selection as they are then (a command made before
        would be one for a text that is gone);
      - a document that takes no edit now (loading, incomplete, saving) refuses it, told
        once through EditRefused with that reason; AMake is not called;
      - AMake makes the command (nil: nothing - a refusal it told itself, or nothing to do)
        and says in APlace where the edit leaves the selection (default: a caret behind what
        the document reports changed);
      - the command runs as one history step that keeps the selection from before it (an undo
        puts that back) and, once placed, the selection after it (a redo leaves that caret);
        the engine's refusal (CanExecute, CommandRefusal; an ETyRichModel it reverted; out of
        memory) is told through EditRefused, nothing changed;
      - the caret and the selection go where APlace says (on caret places, never in a cut
        paragraph's hidden tail), scrolled into view (not for a commit a press caused - the
        view stays where the user clicked), then one OnChange and one OnSelectionChange.
      True: the edit ran and changed the text or its formats. Virtual: a descendant may see
      every user's edit (call inherited). Undo and Redo are not commands and do not come here
      (RunHistory); an edit from code (SelText :=, Lines, the document's API) does not either. }
    function RunUserEdit(AMake: TTyRichEditMaker): Boolean; virtual;
    { ACmd, made by the control before, through the door of a user's edit (AUser) - or, from
      code, EditWith - leaving the selection at APlace. ACmd is the door's: freed when it is
      not run, also when a handler the door runs frees the control. }
    function RunMade(ACmd: TTyRichCommand; const APlace: TTyRichEditPlace; AUser: Boolean): Boolean;
    { Why ACmd's CanExecute would refuse it: the engine's own text commands (an insert, a
      deletion, an object, a fragment) refuse only where a row holds a nested table; a table
      command for its table's reason (TTyRichTableCommand.Refusal, in the words of the
      control's table actions); any other command's reasons are its own - told as a range
      that cannot be edited. }
    function CommandRefusal(ACmd: TTyRichCommand): string; virtual;
    { The reason a copy or a move of [AFrom, AFrom + ALen) to ATo was refused (CommandRefusal of
      one like it: the refused one is freed by then). }
    function LateTransferRefusal(AFrom, ALen, ATo: TTyRichPos; AMove: Boolean): string;
    { The parts a descendant may make its own: the document (called once, from the
      constructor), the device the layout measures and draws with, the layouter. }
    function CreateDocument: TTyRichDocument; virtual;
    function CreateDevice: TTyRichTextDevice; virtual;
    function CreateLayouter: TTyRichLayouter; virtual;
    { What BookmarkCount and BookmarkName read: the document's bookmarks, kept across the
      edits that leave them as they were. }
    property BookmarkList: TTyRichBookmarkList read FBkmIndex;
    { The block paragraph AIndex is in, laid out for the view (with a reference for the
      caller). Every layout the view makes goes through here. }
    function LayoutBlockAt(AIndex: Integer): TTyBlockLayout; virtual;
    { The colours the text is painted with, from the theme: TyRichEdit's text colour, the
      selection (TyRichEditSelection, :focus while focused), a selected picture's frame and
      its handles (TyRichEditObject: border-color, and background their fill), a picture that cannot be shown (TyRichEditPlaceholder); table lines in
      the text colour (a document's "auto" colour). }
    procedure FillPaintStyle(var AStyle: TTyRichPaintStyle); virtual;
    { The one door for "what is shown changed here" (client pixels): the part of ARect inside
      the text clip (TextWindowRect) is drawn again on the kept surface at the next paint, and
      that part of the window is invalidated; a rectangle outside the text does nothing (what
      lies outside it is the frame's, drawn again only when the frame changes). So a
      PositionRect / ParagraphRect of a block cut by the view's edge, or held above or below
      the view, costs only what is on screen of it. A selection goes through here; a caret
      does not (it is drawn over the blit and blinks through InvalidateArea). }
    procedure InvalidateContent(const ARect: TRect); virtual;
    { The window's part to be painted again (client pixels) - a blit from the surface, nothing
      on the surface is drawn again. Every window invalidation goes through here:
      InvalidateContent's, a scroll's, which moves the surface instead of dirtying it, and
      what is drawn over the blit after it - the caret's blinks go through here alone (a test
      records them here). }
    procedure InvalidateArea(const ARect: TRect); virtual;
    { Everything on the surface drawn again at the next paint (frame and text). }
    procedure InvalidateSurface;
    { The text clip in client pixels: what InvalidateContent clips to. }
    function TextWindowRect: TRect;
    { Paints held block AIndex onto ABitmap at AX, AY within AClip (raster pixels). Every
      block a paint draws goes through here. }
    procedure PaintBlock(ABitmap: TBGRABitmap; AIndex, AX, AY: Integer; const AClip: TRect;
      const AStyle: TTyRichPaintStyle); virtual;
    { Draws the frame over the whole surface (a full redraw). }
    procedure PaintSurfaceFrame(APPI: Integer); virtual;
    procedure DestroyWnd; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    { The kept surface (nil before the first paint, after the handle went). }
    property Surface: TBGRABitmap read FSurface;
    { The device scale the view is laid out at (raster pixels per client pixel). }
    property DeviceScale: Integer read FScale;
    { The highest range a scroll bar is given (CRichScrollBarRange): past it, one bar unit is
      more than one pixel. }
    function ScrollBarLimit: Integer; virtual;
    { The theme font, the PPI, the zoom and the width the view is laid out for; when one of them
      changed, every height becomes an estimate again (the anchor stays). }
    procedure CheckLayoutParams(APPI: Integer);
    { Lays out the view: from the anchor down to a screen past the bottom, a screen above it,
      and writes the heights found. }
    procedure LayoutView;
    { CheckLayoutParams, the bars, LayoutView - until the bars stay as they are. }
    procedure EnsureView(APPI: Integer);
    { Draws the part AClip of the control (the canvas's pixels) whose whole is ARect. ADefer:
      pictures not ready are left for the background work (a paint of the window). }
    procedure PaintArea(ACanvas: TCanvas; const ARect, AClip: TRect; APPI: Integer;
      ADefer: Boolean);
    { The text area: the control's rectangle ARect inside its padding and scroll bars. }
    function TextArea(const ARect: TRect; APPI: Integer): TRect;
    { Lays the document's bytes from the stream into it as AFormat (rfRtf / rfText).
      AByAsked: the format was not decided from the file and agrees with an asked PlainText
      (the asking chose text, or the caller asked for rfText); such a load keeps the asking:
      only a load whose format came from the file, or an RTF load, ends it. }
    procedure LoadAs(AStream: TStream; AFormat: TTyRichFormat; AByAsked: Boolean = False);
    { The content replaced with AText as plain text (Lines); not refused by ReadOnly. }
    procedure SetPlainText(const AText: string);
    { What the stream holds, by its first bytes (the position is left where it was). }
    function DetectFormat(AStream: TStream): TTyRichFormat;
    { One piece of the background work: a load slice, else one picture made ready. False when
      there was nothing to do. What a turn runs, a few milliseconds a turn. A load slice that
      raises without having indexed a byte would raise again: the load is cancelled (the
      document keeps what was read, Incomplete) and the error goes on; one that got further
      (a handler of its progress or change raised) leaves the load to go on. }
    function StepBackground: Boolean;
    function HasBackgroundWork: Boolean;
    { One turn of the background work: pieces of it until CRichIdleMaxSteps of them or
      CRichIdleBudgetMs by IdleTicks, whichever comes first. While work is left (also when a
      piece raised) the driver stays on, and it goes when the work is done. The turn itself
      never queues a call: with rtdIdle the application's next idle step queues the one call
      that runs the next turn, so the loop handles its input, paints and timers and reaches
      its idle step (OnIdle, action updates) between two turns, and the next turn follows on
      the next pass - no timer period; with rtdTimer the timer runs the next. Only while the
      control has a window; a turn that comes inside a load step or a save does nothing, and
      the step's or the save's end starts the driver again. }
    function BackgroundTurn: Boolean;
    { The clock a turn is measured by, in milliseconds (GetTickCount64; a test seam). }
    function IdleTicks: QWord; virtual;
    { The driver of the turns on this widgetset: TyRichTurnDriverFor(WidgetSet.LCLPlatform). }
    function TurnDriver: TTyRichTurnDriver; virtual;
    { The seam every scheduling goes through (a test counts it and runs what it scheduled by
      hand): ACall onto the application's queue (QueueAsyncCall) and off it
      (RemoveAsyncCalls); the idle handler registered (Application.AddOnIdleHandler) and
      removed. }
    procedure PostCall(ACall: TTyRichQueuedCall); virtual;
    procedure RemovePostedCall(ACall: TTyRichQueuedCall); virtual;
    procedure WatchIdle(AOn: Boolean); virtual;
    { The application no longer takes scheduling (it is being destroyed; its queue raises
      then, its idle handler lists go): nothing is queued or registered. }
    function SchedulingClosed: Boolean; virtual;
    { rtdIdle's idle handler: queues the one call that runs the next turn; with no work (or
      no window) left it takes itself away. Done is left as it is (the idle step still runs
      the actions' updates). }
    procedure IdleStep(Sender: TObject; var Done: Boolean); virtual;
    { rtdIdle's backstop tick: when no turn ran since the last tick (the idle step is
      starved), one turn - the queued call, if one waits, taken off the queue first, so that it
      does not follow this turn; otherwise nothing. With no work (or no window) left it stops
      the driver. }
    procedure BackstopTick(Sender: TObject); virtual;
    { The background work's next turn is queued: there is work and a window. }
    property BackgroundCall: TTyRichQueuedCall read FStepCall;
    { rtdIdle: the idle handler is registered (there is work and a window). }
    property IdleWatched: Boolean read FIdleOn;
    { rtdTimer: the timer that runs the turns (nil until the first start, after the window
      went). }
    property TurnTimer: TTimer read FTurnTimer;
    { rtdIdle: the backstop timer (nil until the first start, after the window went; enabled
      while the idle handler is registered); the turns run so far. }
    property BackstopTimer: TTimer read FBackstop;
    property TurnsRun: Int64 read FTurnsRun;
    { A selection report a snap made outside a user action is queued. }
    property SelectionCall: TTyRichQueuedCall read FSelCall;
    { A press, a release, a hover or the focus changed: the control is painted again only
      when what its frame looks like changed (FrameSignature); the text is not touched. }
    procedure PointerStateChanged; override;
    { The surface's part of the clip blitted (PaintArea), then the caret drawn over it. }
    procedure Paint; override;
    { The caret, over what was blitted: when the control has the focus, in its blink's on
      half, with no selection (as the memo shows it), the line's height, the theme's text
      colour (the memo's caret: no token of its own), one pixel of 96 PPI wide. }
    procedure DrawCaret(ACanvas: TCanvas);
    { The caret is drawn (a test can stand in for a focus it cannot give). }
    function HasCaretFocus: Boolean; virtual;
    { False inside a press's inherited handling when FocusOnClick is False: the package's
      base control focuses a pressed control that can be focused (TTyCustomControl.MouseDown),
      and that press must not. }
    function CanFocus: Boolean; override;
    property PressRefusesFocus: Boolean read FPressNoFocus;
    { The blink: the caret's half period passed - its rectangle is blitted again, nothing on
      the surface is drawn. }
    procedure BlinkTick(Sender: TObject);
    { A drag held outside the text: the view scrolls, faster the further out the pointer is,
      and the selection follows (what the drag timer runs). }
    procedure DragScrollTick(Sender: TObject);
    { The cursor at client point (X, Y): the I-beam over the text, the arrow over the padding
      (the scroll bars have their own). }
    function CursorAt(X, Y: Integer): TCursor;
    { The handles of the selected object (see the handles in the public part), in client
      pixels (rounded outward): False when it shows none. }
    function ObjectHandleRects(out ARects: TTyRichHandleRects): Boolean;
    { The handle at client point (X, Y): False when the point is on none. }
    function ObjectHandleAt(X, Y: Integer; out AHandle: TTyRichHandle): Boolean;
    { A drag of a handle is held (see the handles). }
    property Resizing: Boolean read FResizing;
    { While a handle is dragged: the outline in client pixels (rounded outward) and the size it
      stands for, in twips. False otherwise. }
    function ResizeOutline(out ARect: TRect; out AWidthTwips, AHeightTwips: Integer): Boolean;
    { Called once at the end of a drag of a handle, before the command: raises
      OnObjectResize. A descendant may constrain AWidthTwips / AHeightTwips (twips, positive)
      or clear AAllow; a size equal to the object's own changes nothing. }
    procedure DoObjectResize(AObject: TTyRichObject; var AWidthTwips, AHeightTwips: Integer;
      var AAllow: Boolean); virtual;
    { The left button is down now (the system's state, not a message's): what tells a capture
      taken away during a drag of a handle from the one its own release lets go of. }
    function LeftButtonHeld: Boolean; virtual;
    { What a drop of AOffer at APos would do (the receiving side asks it at every move and at
      the drop), AShift the keys held. By default: nothing inside the selection dragged (for
      a move also at its ends, and anywhere when that selection cannot be moved: it crosses a
      cell's edge, or the document keeps it), where the document cannot take the content
      (CanChange: a row that holds a nested table), while the document takes no edit
      (loading, saving), in a plain text document for an offer of a picture alone, or for an
      offer of nothing; else a copy with Ctrl held, a move of the control's own selection
      without. Another offer (another control's selection, another program's content): a copy
      with Ctrl held, else a move when its source allows one, else a copy - the system's
      convention. A file list: a copy when OnDropFiles is assigned (the application decides,
      also in a read-only control), or when every file is named as a picture and a picture
      could go in here; never a move (a source deletes what was moved). A descendant may
      decide otherwise (rdeNone: not here). }
    function DropEffectAt(AOffer: TTyRichDropOffer; APos: TTyRichPos;
      AShift: TShiftState): TTyRichDropEffect; virtual;
    { The pointer's shape during the control's own drag: crDrag for a move, crMultiDrag for a
      copy, crNoDrop where nothing would happen. }
    function DropCursor(AEffect: TTyRichDropEffect): TCursor; virtual;
    { The rich edit of this application under the client point X, Y of this control (it is
      outside this control's client area), and that point in its client pixels; nil when
      there is none. By default the LCL's FindControlAtPosition at the point on the screen
      (any form of the application, any widgetset), the control found or the rich edit it is
      inside, when DropTargetTakesInput says it can take input now. Never this control
      itself. }
    function DropTargetAt(X, Y: Integer; out ATargetX, ATargetY: Integer): TTyCustomRichEdit; virtual;
    { The rule DropTargetAt keeps for the control it found: it is enabled, and its form takes
      input now - enabled, and no other form is the modal one (DropModalForm). A descendant's
      DropTargetAt asks it too. }
    function DropTargetTakesInput(ATarget: TTyCustomRichEdit): Boolean;
    { The application's modal form now (Screen.GetCurrentModalForm), nil when none. }
    function DropModalForm: TCustomForm; virtual;
    { The client point of a point on the screen where another program's drop is
      (ScreenToClient by default). }
    function DropPointOf(const AScreen: TPoint): TPoint; virtual;
    { The control takes every one of AFiles itself: each one's name is a picture's (asked once
      per offer). }
    function DropFilesArePictures(const AFiles: TStringArray): Boolean; virtual;
    { The fragment filter a drop's RTF goes in through: AInner (the reader's, MakeFragmentFilter)
      or one of the drop's own around it - for another rich edit's selection one that gives the
      pictures read back the source's very bytes. When it raises, AInner is not taken (the
      caller frees it). }
    function DropFragmentFilter(AOffer: TTyRichDropOffer;
      AInner: TTyRichFragmentFilter): TTyRichFragmentFilter; virtual;
    { Raises OnDropFiles for a dropped file list (before the control's own handling). }
    procedure DoDropFiles(const AFileNames: array of string; var AHandled: Boolean); virtual;
    { After a drop from elsewhere went in (what went in selected): the control takes the
      focus and its form comes to the front (TCustomForm.BringToFront: the system's
      foreground window), as the system's rich edit is after a drop - nothing for a form not
      shown. }
    procedure FocusAfterDrop; virtual;
    {$IFDEF LCLWin32}
    { The control's drop target for the system (tyControls.RichEdit.OleDrop's): made on the
      first call, the same one for the control's life. }
    function OleDropTarget: IUnknown;
    {$ENDIF}
    { The session's offer (nil: no drop under way). }
    property DropOffer: TTyRichDropOffer read FDropOffer;
    { How far the pointer goes, pressed inside the selection, before the drag begins: LCL's
      Mouse.DragThreshold (pixels at 96 PPI) scaled by the control's PPI. }
    function DragThreshold: Integer; virtual;
    { The drop mark in client pixels (rounded outward): False when none is shown. }
    function DropMark(out ARect: TRect): Boolean;
    { A press inside the selection waits for a move to become a drag. }
    property DragPending: Boolean read FDragPending;
    { The verdict at the drop's place now (rdeNone also when no drop is under way). }
    property DropEffectNow: TTyRichDropEffect read FDropEffect;
    procedure KeyUp(var Key: Word; Shift: TShiftState); override;
    { OnSelectionChange, when the caret or the anchor moved since it was last raised. }
    procedure DoSelectionChange; virtual;
    { A copy's two flavours to the clipboard, in one Open .. Close of LCL's Clipboard: the RTF
      under the platform's name for it (TyRichClipboardRtfName; left out when ARtf is ''),
      then the text. The seam a test stands in for: no test reaches the system's clipboard. }
    procedure WriteClipboard(const ARtf: RawByteString; const AText: string); virtual;
    { The paste's side of the clipboard, the seam a test stands in for. ClipboardFormatList:
      the formats there, in one enumeration of LCL's Clipboard (an open, enumerate, close on
      win32; a round trip to the selection's owner on GTK) - nothing is read, so the menu, or
      an action's OnUpdate, can ask at every popup or idle. ClipboardFlavours: the flavours
      those formats are (by default from ClipboardFormatList, once). The reads: the RTF's
      bytes ('' none); the picture formats in the order they are tried - AIndex 0, 1, ...;
      False past the last; ABytes nil when the format at AIndex is not there - and their
      kind; the text (UTF-8 as LCL gives it, '' none). By widgetset (the names LCL hands the
      system): RTF under TyRichClipboardRtfName; a picture - LCL-Win32 the registered "PNG"
      first, then CF_DIB (a raw format id: LCL-Win32 passes it to the system as it is);
      LCL-Cocoa public.png, then public.tiff (LCL's Cocoa clipboard maps no such name, so each
      is the pasteboard type of that very name); elsewhere (GTK, Qt) image/png, the MIME type
      those toolkits offer an image as; last, everywhere, the picture format LCL itself reads
      (Clipboard.FindPictureFormatID: what this application copied through LCL - a TImage's
      bitmap - whose bytes are a BMP, PNG, JPEG or TIFF file); the text LCL's own. }
    function ClipboardFormatList: TTyRichClipFormats; virtual;
    function ClipboardFlavours: TTyRichClipFlavours; virtual;
    function ReadClipboardRtf: RawByteString; virtual;
    function ReadClipboardPicture(AIndex: Integer; out AKind: TTyRichImageKind;
      out ABytes: TBytes): Boolean; virtual;
    function ReadClipboardText: string; virtual;
    { The clipboard's RTF read as a document of its own (TyRichReadRtfFragment; nil: it
      cannot be used). The seam a test stands in for a reader that fails. }
    function ReadRtfSource(const ABytes: TBytes; out AEndsWithParagraph: Boolean): TTyRichDocument; virtual;
    { The filter a paste of ASource into this document goes through
      (TyRichFragmentFilterFor). Made before the command that takes ASource over: a failure
      here (out of memory) frees ASource and refuses the paste. A test seam. }
    function MakeFragmentFilter(ASource: TTyRichDocument): TTyRichFragmentFilter; virtual;
    { Around a copy of more than CopyWaitChars characters: the wait cursor (Screen.Cursor),
      put back after it whatever happened. On Windows LCL sets the cursor at once; whether
      GTK or Cocoa show it before their event loop turns again - the copy lets no message in
      - is not known (not verified on either). }
    procedure BeginWait; virtual;
    procedure EndWait; virtual;
    property CopyWaitChars: Int64 read FCopyWaitChars write FCopyWaitChars;
    { The default menu at client point APos (TTyTextEditMenu, made the first time); a user's
      PopupMenu is shown by LCL instead. }
    procedure ShowTextMenu(const APos: TPoint); virtual;
    procedure DoContextPopup(MousePos: TPoint; var Handled: Boolean); override;
    property TextMenu: TTyTextEditMenu read FTextMenu;
    property DragTimer: TTimer read FDragTimer;
    { The caret's blink: made on entering with a window, gone with the window. }
    property BlinkTimer: TTimer read FBlinkTimer;
    { Cursor as the window shows it: the arrow while the pointer was last seen over the
      padding (MouseMove) and the Cursor set is the I-beam; otherwise, at design time and while
      the component is written, the Cursor set (it streams as it was set). LCL-Win32 answers
      the window's set-cursor message with it (the control does not hear that message). }
    function GetCursor: TCursor; override;
    property Dragging: Boolean read FDragging;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure CaptureChanged; override;
    procedure EnabledChanged; override;
    procedure VisibleChanged; override;
    procedure DoEnter; override;
    procedure DoExit; override;
    procedure Resize; override;
    procedure InitializeWnd; override;
    { The keys: the caret moves (arrows by a cluster, Ctrl by a word, Up / Down by a line
      keeping the x, Home / End the line's ends, Ctrl+Home / Ctrl+End the document's, PgUp /
      PgDn a page), with Shift the selection grows; Ctrl+A selects all, Ctrl+C and
      Ctrl+Insert copy. Every arrow is taken, also where the caret cannot move (it never goes
      to the parent's focus navigation). Editing: Backspace and Delete (Ctrl: by a word),
      Enter (a paragraph) and Shift+Enter (a line break, U+000B), Tab when WantTabs, Ctrl+X
      and Shift+Delete cut, Ctrl+V and Shift+Insert paste, Ctrl+Z undoes, Ctrl+Y and Ctrl+Shift+Z redo (Cmd on a Mac); with
      ReadOnly they are taken and do nothing, Enter is left to the form. Esc, Enter with Ctrl
      or Alt, and Tab without WantTabs are left to the form.
      In a table, with WantTabs: Tab goes to the next cell shown (the row's next, else the
      next row's first; a cell merged away is passed over) and selects its content - from its
      first paragraph's start to its last paragraph's end, an empty cell the caret alone -,
      Shift+Tab to the one before (nothing in the first cell); this moves only, with
      ReadOnly too. Tab in the last cell of the table a person sees (the run of table
      paragraphs, whatever objects the document holds them in) adds a row below it - a
      user's edit, one undo step, refused (told) as InsertRow is, nothing with ReadOnly -
      and goes into its first cell. Ctrl+Tab inserts a tab character there.
      During a drag of the control's own (a handle's, the selection's, or a press inside the
      selection waiting for one) none of this: Esc ends the drag, the modifiers keep their
      meaning, any other key is taken and does nothing (OwnDragKey) - after OnKeyDown, which
      comes first as always. }
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    { A printable character typed (any Unicode): it replaces the selection, else goes in at
      the caret, in TypingFormat; consecutive typing is one undo step (the engine merges it)
      until the caret is moved by the user, another command runs, Enter is pressed or the
      focus leaves - a space does not end it (as the memo's). OnUTF8KeyPress and OnKeyPress
      come first and may stop it (TyAskKeyPress), also with ReadOnly. During a drag of the
      control's own it goes nowhere. }
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    { The character format the next typed text gets: with a selection, its first
      character's (it is typed over); else the character's before the caret in its paragraph,
      at a paragraph's start the one's after it (TTyRichDocument.TypingFormatAt) - unless a
      pending format was chosen at the caret with nothing selected (see the format API),
      which comes first. }
    function TypingFormat: TTyCharFormatId; virtual;
    { The document is plain text (PlainText): a key makes no line break inside a
      paragraph (Shift+Enter makes a paragraph), a paste takes text only. }
    function PlainTextDocument: Boolean; virtual;
    { An edit the user asked for (a key, the menu) was not made: the document is loading,
      incomplete after a cancelled load or being saved, a row that holds a nested table
      cannot be changed, or the engine took no such range (AReason says which). Nothing is
      raised and nothing changed. The default raises OnEditRefused, and nothing else (no
      beep, no dialog). A refusal of an edit made from code raises ETyRichEdit instead. }
    procedure EditRefused(const AReason: string); virtual;
    { The seams to the platform's input method (a test stands in for it; no test reaches a real
      one). ImeEndOnWidgetset: the control ends the composition - the input method is told to
      commit it (ACommit) or to drop it; True when one was told (win32: ImmNotifyIME with a
      context; then a commit comes back through the input method's messages, here, before it
      returns). ImePlaceCandidates: the candidate window to the composition's caret ARect
      (client pixels) - win32: the composition and candidate forms; Qt: asked again
      (TyImeUpdateCaret); GTK2 asks on each key itself; Cocoa asks (ImeCaretBoundClient).
      ImeReadComposition (win32): ImmGetCompositionStringW's result for AIndex (GCS_*), the
      bytes it wrote in AData. ImeSetContextDefault (win32): the default handling of
      WM_IME_SETCONTEXT (DefWindowProc) with the parameters given, its answer. }
    function ImeEndOnWidgetset(ACommit: Boolean): Boolean; virtual;
    procedure ImePlaceCandidates(const ARect: TRect); virtual;
    function ImeReadComposition(AIndex: LongWord; out AData: RawByteString): LongInt; virtual;
    function ImeSetContextDefault(AWParam, ALParam: PtrInt): PtrInt; virtual;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    function DoMouseWheelHorz(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure DoChange; virtual;
    procedure DoZoomChange; virtual;
    property VerticalBar: TTyScrollBar read FVBar;
    property HorizontalBar: TTyScrollBar read FHBar;
    property FirstSliceBytes: Int64 read FFirstSliceBytes write FFirstSliceBytes;
    property StepBytes: Int64 read FStepBytes write FStepBytes;
    { The bytes the next load slice indexes. In a turn (BackgroundTurn): the turns' slice size,
      which starts at CRichLoadMinStepBytes with each load and changes after every turn that
      indexed - halved when the turn took longer than CRichIdleBudgetMs, doubled when it took
      less than a quarter of it, kept in between - within CRichLoadMinStepBytes .. StepBytes
      (see NoteTurn). A file that indexes slowly gets smaller slices, not longer turns,
      its first turn too; one stalled turn costs one halving. Outside a turn (a
      step by hand): StepBytes. A test seam (it records what the loader was asked). }
    function SliceBytes: Int64; virtual;
    property PendingPictureCount: Integer read FPendingCount;
    { The budget of a ConsistentAttributes read (CRichConsistWork, CRichConsistParseBytes;
      a test seam), the walks made so far (a remembered answer makes none) and the units of
      work the last walk did. }
    property ConsistencyBudgetWork: Integer read FConsBudgetWork write FConsBudgetWork;
    property ConsistencyWork: Integer read FConsSeen;
    property ConsistencyBudgetBytes: Int64 read FConsBudgetBytes write FConsBudgetBytes;
    property ConsistencyWalks: Integer read FConsWalks;
    { The background find's piece (a finder step's units, see CRichFindStepChars - and a
      replace's range of paragraphs, in characters), as the turns sized it; the finder at
      work (nil: none); the replace's command (nil: none); what the synchronous finds read
      (bytes of text). Test seams. }
    property FindSlice: Int64 read FFindSlice write FFindSlice;
    property Finder: TTyRichFinder read FFinder;
    property ReplaceCommand: TTyRichReplaceAllCommand read FReplaceCmd;
    property FindBytesRead: Int64 read FFindBytesRead write FFindBytesRead;
    { What finding the link under the pointer read (LinkAtPoint, the hand, a click): a
      field's instruction, a search for a field's marks across paragraphs. Test seams. }
    property LinkFieldReads: Int64 read FLinkReads;
    property LinkFieldSearches: Int64 read FLinkSearches;
    { The door of the format API for a descendant: runs ACmd as the façades' writes
      run theirs (RunApiEdit) - not refused by ReadOnly, an open composition ended first,
      the selection kept with the step and left where it is, no scroll, one OnChange;
      a refusal of the document raised (ETyRichEdit). AChars: how many characters it changes
      (the wait cursor's threshold). RunUserEdit is the user's door (it asks ReadOnly). }
    procedure RunApiCommand(ACmd: TTyRichCommand; AChars: TTyRichPos);
    { Does a press with AShift of AButton on a link make its click (OnLinkClick)? Editable: Ctrl
      with the left or the middle button; ReadOnly: the left or the middle button without
      Shift or Alt. Never the right button, never the second press of a double click
      (ssDouble). The pointer is the hand where this says yes for the left button. The other
      rules are not this function's: a disabled control, a drag, press and release on the same
      link. }
    function LinkClickFires(AShift: TShiftState; AButton: TMouseButton): Boolean; virtual;
    { A click on a link (a HYPERLINK field: the innermost around the place counts): editable,
      a Ctrl + left or middle click; ReadOnly, a plain left or middle click (LinkClickFires
      says which, a descendant may say otherwise) - never the right button, a disabled control,
      a drag (the pointer past the drag threshold), the second click of a double click, and
      only with press and release on the same link's text or a picture in it. AURL: the
      instruction's target ("target", "#name" for \l "name" alone, "target#name" for both;
      the other switches are not looked at). The click does nothing else (no caret move, no
      selection); the control never opens anything itself - with no handler nothing happens.
      Run on the release; the handler may free the control, load another document or show a
      dialog. The pointer is the hand where a left click would be one. As Delphi's
      TRichEdit.OnLinkClick. }
    property OnLinkClick: TTyRichLinkClickEvent read FOnLinkClick write FOnLinkClick;
    { A click on a link to a place of the document ("#name": HYPERLINK \l "name") goes there:
      after OnLinkClick (if any), OnFollowLink is asked, then GoToBookmark. A link with a
      target and a place ("file#name") is never followed, nor any other: the application does
      that (OnLinkClick). A bookmark that is not there: nothing happens. }
    property FollowBookmarkLinks: Boolean read FFollowBookmarkLinks write FFollowBookmarkLinks
      default True;
    { Before a link is followed to its bookmark - one that is there (a link to no bookmark
      asks nothing): AAllow False stays. The handler may free the control, load another
      document or show a dialog. }
    property OnFollowLink: TTyRichFollowLinkEvent read FOnFollowLink write FOnFollowLink;
    { A click on an object (a picture, a block that shows a picture - an equation, an embedded
      object, a shape -, another kept block with a width; never a field's marks, a bookmark's
      ends or anything else with no width): on the release of a press of any button that began
      on that object and ended there without a drag or a resize. The press has done what it
      does (a left press selects the object, a right one leaves the selection for the menu);
      AHandled True stops what the release would still do (the click a press inside the
      selection owes, the menu of a right click). A press that is a link's click (OnLinkClick:
      a picture in a link) is no object's click. Also with AllowSelection False, where the
      press selects nothing. }
    property OnObjectClick: TTyRichObjectClickEvent read FOnObjectClick write FOnObjectClick;
    { A double click on an object: on the second press, before what a double click does
      (selecting the object as a word); AHandled True: that does not happen. The press's
      release is no OnObjectClick. A handler may free the control, load another document or
      show a modal form. }
    property OnObjectDblClick: TTyRichObjectClickEvent read FOnObjectDblClick
      write FOnObjectDblClick;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { RTF or text, by the content (an RTF signature), opened shared for reading. }
    procedure LoadFromFile(const AFileName: string);
    { From the stream's position to its end, read here (nothing keeps the stream). }
    procedure LoadFromStream(AStream: TStream; AFormat: TTyRichFormat = rfAuto);
    { rfAuto (one rule): plain text when PlainText was set True by code or the Object
      Inspector; else by the extension (.rtf RTF, .txt text); else - no extension to go by -
      text for a plain-text document (PlainText True) and RTF for a rich one. Where the
      content came from does not decide: a text file opened, formatted and saved as notes.rtf
      is RTF. Written to a temporary file beside AFileName first, which takes AFileName's
      place only when the save completed: a cancelled or failed save leaves the file as it
      was. Refused for an incomplete document (a cancelled load). A load still going on is
      finished first. Modified: see the property. }
    procedure SaveToFile(const AFileName: string; AFormat: TTyRichFormat = rfAuto);
    { rfAuto: text for a plain-text document (PlainText True), RTF for a rich one. A load
      still going on is finished first; an incomplete document is refused. }
    procedure SaveToStream(AStream: TStream; AFormat: TTyRichFormat = rfAuto);
    { Runs the rest of an RTF load now. }
    procedure FinishLoading;
    { Stops an RTF load: the document keeps what was read and is Incomplete. }
    procedure CancelLoad;
    { Lays out what the view shows now, at the control's PPI (a paint does it by itself). }
    procedure UpdateView;
    { Paints the whole control into ACanvas at ARect, pictures decoded now (a preview, a test).
      It renders the live view, laid out for the control's own size: at the control's PPI it
      costs nothing beyond the drawing; at another PPI it is a PPI change of the view (every
      height an estimate again) and, at the next paint, one back. }
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { Scrolls by ADeltaY pixels, block by block (a jump of more than a few screens goes
      through ScrollY). Lays out the blocks it passes; does nothing at an end. }
    procedure ScrollViewBy(ADeltaY: Integer);
    procedure ScrollToTop;
    { Lays out the last screen's blocks (from the end up) and anchors the view so that the
      last line is at the bottom. }
    procedure ScrollToEnd;
    { Which calls lay out: these queries (PositionAtPoint, PositionRect, ParagraphRect,
      VisibleBlockCount, VisibleBlocks, ScrollY) first settle the view - a scroll, a change or a
      resize since the last layout is laid out now, as a paint would (nothing is done when the
      view is current). TopParagraph / TopOffset are the anchor as it is and never lay out.
      Inside the document's update (Document.Updating: the view has not heard of the change
      yet) they answer "not available", as for a block that is not laid out: PositionAtPoint
      -1, PositionRect / ParagraphRect / CaretClientRect an empty rectangle, VisibleBlockCount
      0, ScrollY -1; and the scrolls (ScrollY :=, ScrollViewBy, ScrollToEnd, UpdateView,
      ScrollCaretIntoView) do nothing.

      The document position at client point (X, Y) of the view, through the visible blocks: the
      nearest caret place of the block under Y (the first or last visible one above or below
      them). -1 when nothing is laid out. AAtLineEnd: the place is the end of a wrapped line
      the point is on (past its end), which is also the next line's start - pass it on to
      PositionRect to have the caret on the line the point was on. What a click does. }
    function PositionAtPoint(X, Y: Integer): TTyRichPos; overload;
    function PositionAtPoint(X, Y: Integer; out AAtLineEnd: Boolean): TTyRichPos; overload;
    { The link under client point (X, Y): True when the point is on a character of a link's
      result - its text, a picture in it, not the empty space right of a line's end - with
      AURL its target as OnLinkClick gives it. The innermost HYPERLINK field around that
      character counts (a page number inside a table of contents' entry is in the entry's
      link). What is read for it is kept until the document changes: asked again over the same
      link, nothing is read again. False when nothing is laid out (as PositionAtPoint). }
    function LinkAtPoint(X, Y: Integer; out AURL: string): Boolean;
    { The innermost field whose result APos is inside (after its open mark, up to its close
      mark): AStart its open mark's position, ALength its characters with both marks, and
      AInstruction its instruction as text (decoded as the reader decodes text: "HYPERLINK
      "https://..." \l "name"", "PAGEREF _Toc1 \h", "TOC \o "1-3""). False outside every field
      (the variables left alone). The cost: the field's own paragraphs are looked up, at most
      three read (TTyRichDocument.FieldRangeAt). }
    function GetFieldRange(APos: TTyRichPos; var AStart, ALength: TTyRichPos;
      var AInstruction: string): Boolean;
    { The caret rectangle of document position APos in client pixels - with AAtLineEnd, at a
      wrapped line's end rather than the next line's start; an empty rectangle when APos is in
      no visible block. Unclipped: the caret drawn (CaretClientRect) is kept inside the text. }
    function PositionRect(APos: TTyRichPos; AAtLineEnd: Boolean = False): TRect;
    { The client rectangle of the visible block paragraph AIndex is in (as wide as the text
      area); empty when it is not laid out in the view. }
    function ParagraphRect(AIndex: Integer): TRect;
    function VisibleBlockCount: Integer;
    { Top and Height are client pixels (from the text area's top), rounded outward: above
      device scale 1 two neighbouring blocks may overlap by a pixel. Everything read off
      Layout is in raster pixels - client pixels times DeviceScale. }
    property VisibleBlocks[AIndex: Integer]: TTyRichViewBlock read GetVisibleBlock;
    { The selection: from SelStart, SelLength characters (a paragraph separator is one). Writing
      SelStart collapses the selection there, writing SelLength extends it from SelStart; both
      clamp to the document and to a caret place (as a click does), forget the affinity and
      scroll the caret into view. A place past a cut paragraph's cut (CRichMaxParaLayoutChars)
      is kept and shown at the cut.
      Written inside the document's BeginUpdate .. EndUpdate (and so CaretIndex, SelectAll,
      CollapseSelection): the positions are stored, clamped to the text as it is at that moment,
      and nothing is laid out, scrolled or painted. The control's own writes made later in the
      same update (SelText, Lines, the format writes, InDelText) move them exactly as outside
      an update; a change made straight through Document.Execute does not. When the update
      ends they are clamped to the final text (and to a caret place) and the selection is
      painted; read right after it (or after an edit from code), they are that caret place
      already - as CaretIndex is. }
    property SelStart: TTyRichPos read GetPlacedSelStart write SetSelStart;
    property SelLength: TTyRichPos read GetPlacedSelLength write SetSelLength;
    { The caret: SelStart's end or the other (the end a Shift move moves); writing it collapses
      the selection there. Inside an update: as SelStart. }
    property CaretIndex: TTyRichPos read GetCaretIndex write SetCaretIndex;
    { Delphi's CaretPos (TCustomRichEdit's): X the column, Y the line of the selection's END
      (its larger end, as Delphi reads EM_EXGETSEL's cpMax), where a line is a paragraph
      (Lines) and a column a character of it; written, the selection collapses at column X
      of paragraph Y (both clamped), as SelStart := does. CaretIndex is the caret's own
      position. }
    property CaretPos: TPoint read GetCaretPos write SetCaretPos;
    { The whole text as one string, paragraphs joined by the platform's line break and
      nothing after the last (Delphi's Text); written, the content becomes that text as plain
      text - as Lines.Text := does (PlainText stays as it is), a line break at the end making
      an empty last paragraph. Caption is Text, as on the package's Memo. Reading it builds
      the whole text: in a large document, that is a copy of all of it. }
    property Text: TCaption read GetAllText write SetAllText;
    { Empties the content (Lines.Clear); Modified is False afterwards, as Delphi's. }
    procedure Clear;
    { The caret's affinity: it stands at the end of a wrapped line rather than at the start of
      the line below (End, a click past a line's end). }
    property CaretAtLineEnd: Boolean read FCaretAtEnd;
    function HasSelection: Boolean;
    { Everything, the last paragraph's whole text (a cut paragraph too); the view does not
      move. Nothing is laid out or walked: only what is on screen is painted again. Inside an
      update: as SelStart (the end is the text's end at that moment, clamped when it ends). }
    procedure SelectAll;
    { The selection collapses onto the caret: the text stays (Delphi's and LCL's
      ClearSelection delete the selection). }
    procedure CollapseSelection;
    { Deletes the selection, as the Delete key does - a user's action: an open
      composition ends first; with ReadOnly or disabled nothing happens; a refusal is told
      (EditRefused), never raised; one undo step. Nothing selected: nothing. As Delphi's
      TCustomEdit.ClearSelection. }
    procedure ClearSelection;
    { The least scroll that shows the caret's line whole (and, where the text scrolls across,
      the caret with a line's height of room). }
    procedure ScrollCaretIntoView;
    { The caret's rectangle in client pixels (empty when its block is not laid out in the view):
      where it is drawn, what an input method is told, what a blink paints again. A caret at
      or past the text's right edge (the end of a justified, right-aligned or full line, whose
      x is the layout width or past it) with nothing to scroll to that way is drawn inside
      the text, against that edge; the same at the left edge. }
    function CaretClientRect: TRect;
    { The selection as plain text: RangeText(SelStart, SelLength). Writing it replaces the
      selection (nothing selected: inserts at the caret) with the text - line breaks make
      paragraphs - in TypingFormat, one undo step that typing does not merge with, the caret
      behind it. An edit from code: not refused by ReadOnly; refused by the document (it is
      loading, incomplete or being saved, a row that holds a nested table), it raises
      ETyRichEdit; a text that starts or ends inside a UTF-8 sequence raises ETyRichModel. }
    property SelText: string read GetSelText write SetSelText;
    { Characters [AFrom, AFrom + ALen) as plain text, as a copy puts them on the clipboard: what
      TyRichCopyRange takes (rows whole once the range reaches past a cell); a paragraph's end
      and a line break inside one (U+000B) become sLineBreak - the line break the memo's
      SelText has, CR LF on Windows, LF elsewhere -, an object (U+FFFC) nothing, an escaped
      byte of a text file (its two characters) one U+FFFD and any other byte that is no text
      one U+FFFD; the cells of a row are parted by a tab - a cell merged away gives its tab
      and nothing else - and a row ends with a line break, as Word copies them. }
    function RangeText(AFrom, ALen: TTyRichPos): string;
    { The selection to the clipboard as RTF (TyRichSaveRtfRange) and as plain text
      (RangeText), through WriteClipboard. Nothing selected: nothing is put there (what the
      clipboard held stays). More than CopyWaitChars characters: the wait cursor meanwhile;
      the copy runs at once and lets no message in. A range the RTF writer refuses (a
      changed row holding a nested table) goes as text alone.
      Memory: both flavours are made whole in memory before the clipboard gets them (for a
      whole 100 MB file about its size each), and the system's clipboard then makes copies
      of its own (on Windows the text again as UTF-16, and each flavour in a global block) -
      a copy of a very large selection needs several times its size for a moment. }
    procedure CopyToClipboard;
    { Copy, then the selection goes: one undo step. Nothing selected: nothing. A user's action,
      as Ctrl+X: an open composition ends first; with ReadOnly or disabled nothing
      happens (nothing is copied); a refusal is told (EditRefused) before anything is
      copied, never raised.

      Two kinds of public methods change the document. The USER's actions - CutToClipboard,
      PasteFromClipboard, ClearSelection, Undo, Redo, the table actions (InsertTable ..
      DeleteTable), what an application wires to its
      toolbar and menu - behave as their keys: they respect ReadOnly (and do nothing on a
      disabled control) and never raise for a refusal, which is told through EditRefused.
      CopyToClipboard and SelectAll always work. The document API - SelText :=, Lines, the
      two format façades (SelAttributes, DefAttributes, Paragraph, SetTextAttributes and the
      other RichMemo-style methods), Document.Execute - edits regardless of ReadOnly and
      raises what the engine raises (ETyRichEdit for a refusal). }
    procedure CutToClipboard;
    { Ctrl+V, Shift+Insert and the menu's Paste: the user's paste, and an application's (its
      own menu item, "paste as plain text" with rpaText). A user's action from any of them:
      an open composition ends first (EndCompositionForUser); with ReadOnly nothing happens
      (the clipboard is not read); a refusal - the document loading, incomplete or being
      saved, a row that holds a nested table, a selection across cells, the caret at
      a cut paragraph's cut, a picture too large - is told once (EditRefused), never raised,
      and nothing changes.
      AAs rpaBest takes the first flavour there that can be used, in this order:
      - RTF, read by the engine's reader (TyRichReadRtfFragment) and inserted as it is
        (TTyRichInsertFragment): formats, objects, tables. It cannot be used when it is no
        RTF (no signature), reading it raised, or it holds no character and no paragraph
        mark;
      - a picture: one picture object (TyRichMakePicture) at most as wide as the paragraph's
        room. It cannot be used when its bytes do not decode; one too large is refused;
      - text: line ends (CR LF, CR, LF, U+2028, U+2029) make paragraphs in the caret
        paragraph's format, U+000B stays a line break (in a plain-text document: a
        paragraph), tabs stay, other control characters go, bytes that are not UTF-8 are read
        as a text file is (TyRichLoadText's rule: the ANSI code page); the typing format.
      The paste replaces the selection: one undo step (named rsRichUndoPaste), never merged
      with typing, one OnChange and one OnSelectionChange, the caret behind what went in; an
      undo puts the selection back. A selection or the caret in a table: the pasted rows go in
      as the text of the cell, never as a nested table. More than CopyWaitChars bytes: the
      wait cursor meanwhile (BeginWait); the paste runs at once and lets no message in.
      What is pasted is read before the document changes: a reader's failure is that
      flavour's (the next one is tried); a lack of memory is refused (rsRichEditRefusedMemory),
      the document untouched. A paste of rows over a selection of whole rows is refused
      (rsRichEditRefusedPasteRows: rows put into a table would need its columns and theirs
      made one; not done). RTF from another
      document leaves behind what names that document's header tables by number
      (TyRichFragmentFilterFor): style
      names, shading, border and underline colours, the font of right-to-left text,
      tracked-change authors, the formatting inside a field's result, footnotes, comments,
      shapes and embedded objects; RTF copied out of this document's own file keeps all of
      it (what the file's own header defines the same). A paste is one undo step however large: one larger than MaxUndoBytes stays the
      only step - every earlier one is dropped (the history keeps the newest step). }
    procedure PasteFromClipboard(AAs: TTyRichPasteAs = rpaBest);
    { The control can be edited by the user now (not ReadOnly, enabled, the document taking
      edits) and the clipboard holds a flavour it takes. Reads nothing (ClipboardFlavours). }
    function CanPaste: Boolean;
    { One step of the document's history back / forward (Ctrl+Z, Ctrl+Y). An undo puts the
      selection back as it was before the step (a step made by code: what it put back is
      selected); after a redo the caret is where the step left it (a resize by a handle: its
      object selected again, as the drag left it). Nothing to undo / redo:
      nothing. A user's action, as the keys: an open composition ends first; with
      ReadOnly or disabled nothing happens; while the document is being saved (or is loading,
      or incomplete) the refusal is told (EditRefused), never raised. Code that must undo on
      a read-only control calls Document.Undo. }
    procedure Undo;
    procedure Redo;
    { The user's, as CanPaste: Undo / Redo would do something now - there is a step,
      the control is not ReadOnly, it is enabled and the document is in no update. Code that
      undoes regardless of ReadOnly asks Document.CanUndo / CanRedo. }
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    { Several writes as ONE undo step: the format and edit writes of the document API
      between BeginEdit and EndEdit (SelAttributes, Paragraph, the RichMemo-style methods,
      SelText, Lines) are one step whose undo puts back the selection there was at BeginEdit
      and whose redo the one there is at EndEdit. A block groups; it does not change what
      each write does: the caret and the selection follow each of these writes exactly as
      outside a block (after SelText := the caret is behind the text put in, a format write
      keeps the selection, a Lines write moves it as the text moves), so the same lines of
      code give the same document inside and outside a block. What it holds back is the
      reporting (one OnChange and one OnSelectionChange at EndEdit), the repaint and the
      scroll into view. What a font dialog's result or the ruler's drag writes. They nest
      (the outermost pair counts); an open composition ends at BeginEdit. Inside, the
      document is in its update (Document.BeginUpdate): the user's actions (Undo, a key) do
      nothing until EndEdit; a change made by code straight through Document.Execute is heard
      at EndEdit, as inside any update, and does not move the selection. A new content - a
      load, Lines.Text :=, Lines.Clear, Text :=, Clear - is refused inside (ETyRichEdit,
      before anything changes): the block is one undo step and a new content has none. Not
      Lines.BeginUpdate, which gathers a replacement of the lines; inside it (and inside
      Document.BeginUpdate) the control's own writes move the selection as they do here.
      EndEdit without BeginEdit raises. }
    procedure BeginEdit;
    procedure EndEdit;
    { The history goes (TTyRichDocument.ClearUndo); the text stays. }
    procedure ClearUndo;
    { Tables: the user's actions for a toolbar, a menu or an action, each one undo step whose
      undo puts the selection back as it was before it and whose redo leaves the caret where
      the action left it. As the user's other actions: an open composition ends first; a
      read-only or disabled control, or one inside the document's update, does nothing and
      tells nothing (False); a refusal is told once through EditRefused (OnEditRefused) with
      its reason, never raised, and nothing changes - a plain text document, the document
      loading, incomplete
      or being saved, the caret in no table, and a table whose rows and columns cannot change
      (merged cells, a table inside a cell, rows of different numbers of cells for a column
      edit, a table too large or not complete in a file read on demand). True: done.
      Code that edits the tables of a read-only control uses the document's commands
      (Document.Execute with TTyRichInsertTable and the others of tyControls.RichEdit.Commands),
      as for every other edit.

      InsertTable: an ARows x ACols table (Word's limits: 32767 rows, 63 columns) as wide as
      the page's text, at the caret - with a selection at its start; the selected text stays.
      The caret goes into its first cell. Not inside a table. }
    function InsertTable(ARows, ACols: Integer): Boolean;
    { A row above (AAfter False) or below the caret's row - with a selection, the row of its
      caret end; the caret goes into the new row's first cell. }
    function InsertRow(AAfter: Boolean = True): Boolean;
    { A column left (AAfter False) or right of the caret's cell; the caret goes into the new
      column's cell of its row. }
    function InsertColumn(AAfter: Boolean = True): Boolean;
    { Every row the selection touches in the caret end's table (the caret's row when nothing
      is selected), as one step. The caret goes into the cell of the same index of the row
      that took their place, else of the row above them, else - the table is gone - to the
      start of the paragraph after it. }
    function DeleteRow: Boolean;
    { The column of every cell the selection covers in the caret end's table, in text order as
      it is painted - in one row the cells between its ends; across rows the start's cell to
      its row's end, every cell of the rows between, the end's row up to its cell (so a whole
      row covered is every column); an end outside the table stands at the table's first
      (last) cell - or the caret's column when nothing is selected; one step: all of the
      table's columns are the table. The caret goes into the cell of its row that took their
      place, else the one left of them. }
    function DeleteColumn: Boolean;
    { The whole table the caret is in, as one step; merged cells or a table inside a cell do
      not keep it. The caret goes to the start of the paragraph after it. }
    function DeleteTable: Boolean;
    { The caret (the selection's caret end) is in a table. }
    function InTable: Boolean;
    { Would the action do something now (what an action's Update greys it by): the same
      reasons as the action's, but never told, never raised. Asked again with nothing changed
      - no edit, no move of the selection, no change of the document's loading or saving -
      they answer from what they found the first time; the first answer reads the caret's
      table once or twice (for a table of 10,000 rows within the time of a keystroke). They
      never read a part of a file read on demand that is not read yet: for a table such a
      file gives in parts they answer True unless what is read of it already refuses (the
      action then reads it, and tells the reason when it is too large), and with the caret
      in a paragraph not read yet, as for a paragraph outside a table. }
    function CanInsertTable: Boolean;
    function CanInsertRow: Boolean;
    function CanInsertColumn: Boolean;
    function CanDeleteRow: Boolean;
    function CanDeleteColumn: Boolean;
    function CanDeleteTable: Boolean;
    { Cell selection. A selection's cells are counted by its selected characters, a cell's
      end mark (the end of its last paragraph) being one of the cell's: anchor at a cell's
      start and caret after its end mark is that cell whole; a selection that stops before the
      end mark is text inside the cell. Anchor and caret in two cells of one table: the
      rectangle between them (in each row the cells under the span of the two corner cells);
      one end outside the table: whole rows. SelectedCells: that range (InTable False: none);
      CaretCell: the caret's table (a position in it), row and cell. The Select... methods
      set the selection to the caret's cell, row, column or table (False: the caret is in no
      table, or SelectionAllowed is False; a column or the whole table of a table too large
      to be read whole is refused and told). With cells selected: Delete clears them (one
      step), Backspace deletes the rows when whole rows are selected and the table when all of
      it is, typing replaces the first cell's content, character and paragraph formats reach
      every selected cell, a copy is a small table and tab-separated text. A paste of a
      table (RTF, or tab-separated text) with the caret in a cell fills cell by cell from
      it, adding rows below and leaving out what passes the columns (told once). }
    function SelectedCells: TTyRichCellRange;
    { The grid of the table at ATablePos (nil: no table there): its columns are the union of
      every cell's edges, each cell covers one or more of them and one or more rows - merge
      marks and Word's wide cells read as one thing (tyControls.RichEdit.Grid). Made on
      demand by one walk of the table's rows - linear in them: what keys, the caret and a
      paint need never makes it. The caller frees it. }
    function TableGrid(ATablePos: TTyRichPos): TTyRichGrid;
    { The selected cells merged into one (Word's Merge Cells): the selection is cells of one
      table - a rectangle, grown to hold every merged cell it touches -, at least two of them,
      in a table with no nested table. The top-left cell becomes the merged one: the others'
      paragraphs follow its own in reading order (an empty cell adds nothing; a bookmark goes
      with its text), it has the top-left cell's shading, padding and alignment and the lines
      that were on the rectangle's outline; across it is one wide cell, down a vertical merge
      (Word's own forms). One undo step; the caret at the merged cell's start. False: nothing
      done (CanMergeCells says no; a refusal is told). }
    function MergeCells: Boolean;
    function CanMergeCells: Boolean;
    { The caret's cell (or the one cell selected) split into ACols cells across and ARows
      down (Word's Split Cells). A cell over C columns of the grid split into C gets the
      grid's own edges back; any other ACols divides its width equally. Over R rows, ARows
      must divide R (each part over R div ARows rows); in one row, ARows - 1 rows go in below
      it and the row's other cells reach down over them. The content stays in the first
      cell; the new cells look as it did. ACols 1 .. 63 (a row's cells as well), ARows as
      the table's rows allow. One undo step. False: nothing done (refused: told). Finding C
      reads the table's grid (TableGrid): one walk of its rows. }
    { The grid columns and rows the caret's cell covers (the cell SplitCell splits; 1 x 1 for
      one that is not merged). Reads the table's grid: one walk of its rows. False: no such
      cell. }
    function CaretCellSpan(out AColumns, ARows: Integer): Boolean;
    function SplitCell(ACols, ARows: Integer): Boolean;
    { A split of the caret's cell (or the one cell selected) may run now: into two cells
      across or two down. }
    function CanSplitCell: Boolean;
    function CaretCell(out ATablePos: TTyRichPos; out ARow, ACol: Integer): Boolean;
    function SelectCell: Boolean;
    function SelectRow: Boolean;
    function SelectColumn: Boolean;
    function SelectTable: Boolean;
    { The four select methods may run now: the caret (the selection's cells) is in a table,
      selecting is allowed. }
    function CanSelectCells: Boolean;
    { Cut may run now - as CutToClipboard does it: a selection, not read-only, and not one
      that reaches from cells out of their table (refused there). Over cells it copies them
      and clears them (whole rows, columns, the table go, as Backspace takes them). }
    function CanCut: Boolean;
    { The selected cells' contents cleared, the cells and their formats kept - what Delete does
      to them -, in one step (rows that hold a nested table are left as they are, told once).
      False: CanClearCells says no. }
    function ClearCells: Boolean;
    { ClearCells may run now: the selection is cells of one table (a rectangle, whole rows,
      columns or the table - not rows reached from outside it), the control not read-only,
      enabled. }
    function CanClearCells: Boolean;
    { Column widths and row heights. With the pointer on a column's edge (the east-west cursor)
      a drag moves that edge: only a guide line follows the pointer, and the release runs ONE
      command - the cells either side trade width and the table keeps its width; with Shift the
      cell to its left changes and everything right of it moves (the table's width changes);
      the table's right edge changes the last column and the table's width; its left edge
      moves the table's start and the first column's width follows. With cells selected only
      their rows change, otherwise every row with an edge there (edges within
      CRichSharedEdgeTwips are one; a row without one is left alone). A cell is never
      narrower than its padding and one average character; Esc, or a release where nothing
      moved, changes nothing. A double click on a column's edge: the column left of it takes
      its widest content's width (AutoFitColumn). On a row's bottom (the north-south cursor) a
      drag sets that row - the selected rows - at least that high, never lower than its
      content. A row holding a nested table does not move; a whole-column change of a table a
      reader gives in parts is refused and told.
      The user's doors (ReadOnly does nothing; a refusal is told once; each one step):
      SetColumnWidth - the caret's cell's column, the columns right of it shifting;
      SetRowHeight - the caret's row (the selected rows) at least / exactly ATwips (0 with
      AExact False: as high as its content); AutoFitColumn - the caret's column to its widest
      content; DistributeColumns - each row's cells equally wide; DistributeRows - the rows as
      high as their average; FitTableToWindow - the table as wide as the text. CanResize...
      say whether an action may run now. }
    function CanResizeColumns: Boolean;
    function CanResizeRows: Boolean;
    function SetColumnWidth(AWidthTwips: Integer): Boolean;
    function SetRowHeight(ATwips: Integer; AExact: Boolean): Boolean;
    function AutoFitColumn: Boolean;
    function DistributeColumns: Boolean;
    function DistributeRows: Boolean;
    function FitTableToWindow: Boolean;
    { For a ruler: the caret's row's edges, placed from the caret paragraph's zero (False: the
      caret is in no row the view holds), and one of them moved there (the same command and
      rules as a drag, the rows a drag takes). }
    function CaretRowEdges(out AEdges: TTyRichColumnEdges): Boolean;
    function MoveCaretRowEdge(AIndex, AOffsetTwips: Integer; AShiftRest: Boolean): Boolean;
    { Cell formats - the selected cells (both ends of the selection in one table), else the
      caret's cell: the shading (clNone: none); borders by a preset, each line set to ABorder
      (rbpNone: none); the padding of each side, twips (-1: as it is); where the content sits.
      The table's alignment and its start (AIndentTwips, Word's indent from the margin) for all
      its rows. One undo step each; ReadOnly does nothing; a refusal is told once (a row that
      holds a nested table, a table a reader gives in parts for the alignment). CanFormatCells:
      may run now. }
    function SetCellShading(AColor: TColor): Boolean;
    function SetCellBorders(APreset: TTyRichBorderPreset; const ABorder: TTyRichBorder): Boolean;
    function SetCellPadding(ALeft, ATop, ARight, ABottom: Integer): Boolean;
    function SetCellVAlign(AAlign: TTyRowCellVAlign): Boolean;
    { The table's alignment, its indent as it is; with AIndentTwips the indent too (the
      table's left edge from the margin, TTyRichTableProperties.Indent). }
    function SetTableAlign(AAlign: TTyRowAlign): Boolean; overload;
    function SetTableAlign(AAlign: TTyRowAlign; AIndentTwips: Integer): Boolean; overload;
    function CanFormatCells: Boolean;
    { The table properties of the selected cells (else the caret's cell): the values, Uniform
      the fields alike over all of them, Changed empty. False outside a table. }
    function GetTableProperties(out AProps: TTyRichTableProperties): Boolean;
    { The table properties AProps.Changed names as one undo step - the selected cells' (else
      the caret cell's) padding, alignment and shading, their rows' height, the caret cell's
      column width (the columns right of it shift), the table's alignment and indent. Changed
      empty: nothing, True. }
    function ApplyTableProperties(const AProps: TTyRichTableProperties): Boolean;
    { Pictures: the user's actions for a toolbar, a menu or an action, as the table actions
      (an open composition ends first; ReadOnly, disabled or inside the document's update:
      nothing, nothing told, False; a refusal told once through EditRefused, never raised).
      The picture replaces the selection, as a paste does: one undo step (rsRichUndoInsertPicture)
      whose undo puts the selection back; the caret behind the picture. Its size: its pixels at
      its own resolution (a PNG's pHYs, a bitmap's pixels per metre) or at 96 dpi, scaled down
      keeping the ratio to the room at the caret (the page's text width, or the cell's) - as a
      pasted picture (TyRichMakePicture). Refused: a plain text document, the document loading,
      incomplete or being saved, a place a paste could not go (a row that holds a nested table,
      a selection across cells), a picture over CRichPictureMaxBytes bytes or
      CRichPictureMaxPixels pixels (rsRichEditRefusedPicture, the paste's reason), and what is
      no picture that can be read.
      InsertPictureFromFile: a PNG or JPEG file goes in with its own bytes, unchanged - the
      way for photographs; a bitmap, GIF, TIFF, icon or any other image the LCL can read is
      decoded and kept as PNG; a metafile (.wmf, .emf)
      is refused, and so is a file that cannot be opened (its reason from the system). No
      dialog is shown: the application asks for the name. InsertPictureFromStream: the same
      from the stream's position to its end (read here; nothing keeps the stream).
      InsertPicture: a TPortableNetworkGraphic as PNG, a TJPEGImage as JPEG (the bytes its
      SaveToStream gives), any other graphic as PNG; nil or an empty graphic is refused. }
    function InsertPictureFromFile(const AFileName: string): Boolean;
    function InsertPictureFromStream(AStream: TStream): Boolean;
    function InsertPicture(AGraphic: TGraphic): Boolean;
    { An insert would be taken now (for an action's Update): not ReadOnly, enabled, not inside
      the document's update, the document taking edits, not a plain text document, and a
      place a paste could go - the selection (or the caret) not inside a field's result, not
      in a row that holds a nested table, not across cells. Reads the selection's two ends,
      never raises. }
    function CanInsertPicture: Boolean;
    { Links: the user's actions, as the picture and table actions (an open composition ends
      first; ReadOnly, disabled or inside the document's update: nothing, nothing told, False;
      a refusal told once through EditRefused, never raised); each one undo step whose undo
      puts the selection back.
      InsertLink: a link to AURL ("#name" a bookmark of the document, "target#name" a place in
      a target; Chinese and any other text as it is). A selection becomes the link's text as it
      is, given the editor's look (underlined, Word's link blue where it has no colour of its
      own: TTyRichInsertLink's rllWordBlue); AText given goes in its place (the format typed there, with the look);
      neither: AURL itself is the text. The caret goes behind the link. Refused: an empty
      address, a plain text document, a selection that reaches past its paragraph's end
      (across paragraphs or table cells), one with an end inside a field's result (a link's,
      a table of contents'), one that holds a field (no link inside a link), a row that holds
      a nested table. A link is a HYPERLINK field: its text is read-only as any field's result
      - typing in it is refused; SetLink changes it.
      SetLink: the link the caret or the selection is in (LinkAtSelection) gets AURL; with
      AText it is replaced by a link holding AText (in the look its text had), else its text
      stays as it is. RemoveLink: that link stops being one - its text and what else it holds
      stay, selected, and so do its formats but the look a link is given, which goes with it
      as in Word (TTyRichRemoveLink: the underline, a link colour, Word's Hyperlink style). Both refused when there is no such link and
      for a link inside another field's result (an entry of a table of contents).
      CanInsertLink / CanEditLink: the action would be taken now (for an action's Update);
      reads the selection's paragraph and the fields around it, never raises. }
    { (The address first, its text optional; the builder's Link(AText, AURL) takes the text
      first, in reading order - mind the order.) }
    function InsertLink(const AURL: string; const AText: string = ''): Boolean;
    function SetLink(const AURL: string; const AText: string = ''): Boolean;
    function RemoveLink: Boolean;
    function CanInsertLink: Boolean;
    function CanEditLink: Boolean;
    { The link the caret or the selection is in: a selection that is a whole link; else the
      innermost link whose text holds the whole selection (or the caret); else, with nothing
      selected, the link the caret stands right before or right after. AStart: its open mark's
      position, ALength: its characters with both marks, AURL: its target as OnLinkClick gives
      it. False: none (0, 0 and ''). }
    function LinkAtSelection(out AStart, ALength: TTyRichPos; out AURL: string): Boolean;
    { Bookmarks. Names as Word has them: compared without regard to case; one that begins
      with "_" is hidden (Word's own, for a table of contents' headings) and counted and named
      only with AIncludeHidden. BookmarkCount / BookmarkName: in the order of the bookmarks'
      starts (a file read on demand is not parsed for them: tyControls.RichEdit.Bookmarks).
      FindBookmark: AStart the position of its start mark, AEnd of its end mark (its text is
      between them); False: none. GoToBookmark: the caret to the bookmark's start (its resting
      place there), shown as a find shows a match - a move, not an edit (also when ReadOnly);
      False: none. Reads only the paragraphs of the bookmark's two ends.
      AddBookmark (a name Word takes: TyRichBookmarkNameValid), DeleteBookmark,
      RenameBookmark: the user's actions, as InsertLink (ReadOnly, disabled or inside the
      document's update: nothing, False; a refusal told once through EditRefused); each one
      undo step. AddBookmark marks the selection (or the caret's place); one of that name goes
      first. Refused: a name Word does not take, a plain text document, a place in a field's
      result (a link's text, a table of contents), no such bookmark, a new name in use.
      CanEditBookmarks: those would be taken now (not ReadOnly, enabled, the document taking
      edits, not plain text). }
    function BookmarkCount(AIncludeHidden: Boolean = False): Integer;
    function BookmarkName(AIndex: Integer; AIncludeHidden: Boolean = False): string;
    function FindBookmark(const AName: string; out AStart, AEnd: TTyRichPos): Boolean;
    function GoToBookmark(const AName: string): Boolean;
    function AddBookmark(const AName: string): Boolean;
    function DeleteBookmark(const AName: string): Boolean;
    function RenameBookmark(const AOld, ANew: string): Boolean;
    function CanEditBookmarks: Boolean;
    { The object under client point (X, Y) with a width (what OnObjectClick reports), APos its
      position; nil (APos -1) elsewhere, over a field's mark or a bookmark's end, outside the
      laid out view. The object is good until the document is read again (a read on demand
      may let it go): keep a reference (AddRef) to keep it. What a pointer's move asks, no
      more. }
    function ObjectAtPoint(X, Y: Integer; out APos: TTyRichPos): TTyRichObject;
    { The handles. When the selection is exactly one object that can be resized
      (TTyRichObject.CanResize - a picture, also one shown as a placeholder) and the user may
      edit it (not ReadOnly, enabled, the document taking edits), it shows its frame and eight
      handles (TTyRichHandle) - the frame and their outline in TyRichEditObject's border-color,
      their fill in its background; CRichObjectHandleDip pixels at 96 PPI, following the
      screen, not Zoom. An object that cannot be resized, or a read-only control, shows the
      frame alone. Over a handle the pointer is the size cursor of its direction; a press on
      one begins a resize (never a selection): an outline follows the pointer, a corner keeping
      the object's shape (its width to its height as shown), with Shift not, a side's middle
      changing that side only, the opposite handle staying where it is; nothing changes in the
      document until the release. Each side at least CRichObjectMinTwips, at most
      CRichObjectMaxTwips, the width at most the room at its place - a shape kept is kept in
      the bounds too; the bounds stop a drag, they never move a side already past them (a
      press and release without a move changes nothing). The release is one command (TTyRichResizeObject, one undo step named
      rsRichUndoResizeObject; OnObjectResize first), the object selected again with its
      handles; a release at the size it had, Esc, the capture lost, the window or the content
      going, a press of another button, a key that is not a modifier or a selection set by
      code end it with nothing changed. The resized picture is shown at once from the pixels
      already decoded and made sharp at its new size by the background work. A resized
      picture keeps its bytes and format; what
      its file's group said besides (scaling words, cropping, other representations of the
      picture) is not kept - it is written at its new size from the model. }
    property OnObjectResize: TTyRichObjectResizeEvent read FOnObjectResize write FOnObjectResize;
    { The receiving side of a drop: DropEnter when an offer comes over the control, DropOver
      at each move (and the edge scrolling's ticks), DropLeave when it goes away with nothing
      dropped, DropOn at the drop. X, Y client pixels; AShift the keys held. Each answers what
      a drop there would do (DropOn: what it did). The place is where a click would put the
      caret (the text area's edge line when the pointer is past it); the drop mark shows it
      while the verdict is a move or a copy (DropEffectAt); near an edge of the text, or past
      it, the view scrolls as a drag-select does. The drop: the control's own selection by
      TTyRichMove / TTyRichCopy (one undo step, rsRichUndoMove / rsRichUndoCopy), another
      offer as a paste of its flavours (one step named by the effect); the content dropped is
      selected and scrolled into view. What the place or the selection does not take is told
      once (OnEditRefused, the paste's and the cut's reasons); a drop inside the selection
      does nothing and tells nothing. A drop from elsewhere that went in leaves the control
      focused (FocusAfterDrop). Disabled or in the designer: no session (DropEnter answers
      rdeNone); nor for another program's offer (FromOtherProgram) with AcceptDrops False,
      nor for any other with DragDropEditing False; read-only: none either, except for the
      control's own selection (it can be dragged out as a copy) and for a file list
      OnDropFiles takes. A session ends with the content replaced, the window gone, the
      control disabled or hidden, ReadOnly set, and with the switch that governs its offer
      set off. A handler a drop runs may free the control (or the other control of a drag
      between two): nothing of a freed control is touched after it, and a drop whose target
      went with what it took reports rdeNone. The control's own drag uses these - and feeds
      another rich edit's the same way when the pointer is over it (DropTargetAt); the
      platform's drag (Windows: tyControls.RichEdit.OleDrop) feeds them too. }
    function DropEnter(AOffer: TTyRichDropOffer; X, Y: Integer;
      AShift: TShiftState): TTyRichDropEffect;
    function DropOver(X, Y: Integer; AShift: TShiftState): TTyRichDropEffect;
    procedure DropLeave;
    function DropOn(X, Y: Integer; AShift: TShiftState): TTyRichDropEffect;
    { A drop's session is under way (DropEnter .. DropLeave / DropOn). }
    function DropActive: Boolean;
    { ITyTextEditActions: Undo, Redo, Cut, Copy, Paste (PasteFromClipboard; offered when
      CanPaste) and Select All. With ReadOnly the menu shows the editing items unavailable and
      they do nothing. }
    function TeControl: TControl;
    function TeController: TTyCustomStyleController;
    procedure TeUndo;
    procedure TeRedo;
    procedure TeCut;
    procedure TeCopy;
    procedure TePaste;
    procedure TeSelectAll;
    function TeCanUndo: Boolean;
    function TeCanRedo: Boolean;
    function TeHasSelection: Boolean;
    function TeCanPaste: Boolean;
    function TeHasText: Boolean;
    function TeIsReadOnly: Boolean;
    { The input method's composition, what each widgetset's input method is turned
      into (win32's messages, Cocoa's bridge, the Qt / GTK hooks' commits). A composition is
      shown where it goes in - at the caret when it began, in the typing format, underlined
      (TyRichEditComposition), laid out with its paragraph - and is not the document's: no
      command, no undo step, no OnChange, not Modified, not in the text, SelText, Lines, a copy
      or a save. A selection stays shown and is replaced at the commit.
      BeginComposition: False when none can begin - ReadOnly or disabled (nothing is told, as
      for a key), where typing would be refused (the document taking no edit, a row that holds
      a nested table, a selection across cells, a cut paragraph's cut: EditRefused once; what
      the input method sends then goes nowhere until its session ends), inside the
      document's update, during a drag of the control's own (a handle's, the selection's, or
      a press inside the selection waiting for one: nothing told, the session's text goes
      nowhere).
      UpdateComposition: the composition's text now (begun when it was not), ACaret its caret
      (characters of AText; -1: at its end), the clause the input method works on.
      CommitComposition: the text goes in as typing does (TypeText: one command, the selection
      replaced in one undo step, merged with the typing before it as the memo's, the caret
      behind it, one OnChange and one OnSelectionChange) - where the composition was shown,
      over the selection there was when it began, in the format it was shown in; also with no
      composition (a commit straight from the input method: at the caret, in the typing
      format); '' commits nothing; one with no composition during a drag of the control's own
      goes nowhere, as a character typed then. A refused one: EditRefused once.
      CancelComposition: nothing of it is left.
      A user's edit or action (a key that edits, Ctrl+A, a press, the menu) commits an open
      composition first; disabling the control or setting ReadOnly cancels it. }
    function BeginComposition: Boolean;
    procedure UpdateComposition(const AText: string; ACaret: Integer = -1;
      AClauseStart: Integer = 0; AClauseLength: Integer = 0);
    procedure CommitComposition(const AText: string);
    procedure CancelComposition;
    property Composing: Boolean read FComposing;
    property CompositionText: UTF8String read FCompText;
    { Where the composition goes in (meaningful while Composing). }
    property CompositionPos: TTyRichPos read FCompPos;
    { ITyImeEditable (Cocoa's bridge): read-only with ReadOnly or disabled; the caret's client
      rectangle while focused - the composition's caret while composing; the caret's index
      (an Integer: past High(Integer) characters, High(Integer)); a session is a composition,
      ImeReplace changes its text (counted from where it began), its end commits what it has
      (an empty text: nothing). }
    function ImeTargetControl: TWinControl;
    function ImeIsReadOnly: Boolean;
    function ImeCaretBoundClient: TRect;
    function ImeCaretIndex: Integer;
    procedure ImeSessionBegin;
    procedure ImeSessionEnd;
    procedure ImeReplace(AStart, ALen: Integer; const AText: string);

    { ---- the format API ----

      Two façades over the same engine, Delphi's TRichEdit (SelAttributes, DefAttributes,
      Paragraph) and Lazarus' RichMemo (SetTextAttributes .. GetParaTabs): thin layers - each
      write is ONE command of the document (TTyRichSetCharFormat / TTyRichSetParaFormat) that
      changes the attributes it names and leaves the others as each character or paragraph
      has them, one undo step; the reads ask the document's formats. They are the document
      API: called from code they edit regardless of ReadOnly (ReadOnly is the user
      interface's) and raise what the engine raises - ETyRichEdit when the document takes no
      edit now (loading, incomplete after a cancelled load, being saved), with that reason.
      An application's toolbar calls them as the user's actions, and so every write behaves
      as one: an open composition ends first (committed where it was shown); the step keeps
      the selection from before it (an undo puts it back) and the selection stays as it
      is (a selection in a cut paragraph's hidden tail too - Select All has it); the view does
      not scroll; one OnChange, and OnSelectionChange only when the selection changed (the
      commit of a composition moves it). A write over more than CopyWaitChars characters
      shows the wait cursor meanwhile (BeginWait); it costs what the command costs: in
      proportion to the paragraphs it touches - a whole lazily read RTF file is parsed by it.
      Inside the document's own update (Document.BeginUpdate) a write is a command of that
      update, reported at its end.
      What a format write does where the engine keeps things as they are: paragraphs of a
      table row that holds a nested table are passed over (the rest of the range changes; a
      range wholly inside such a row changes nothing, but is still one - empty - undo step); a
      range across cells formats every cell's text in it; a cut paragraph's hidden tail is
      formatted as the rest of it (it is not shown, but it is saved so).

      The pending typing format: with NOTHING selected, a write of a character attribute
      (SelAttributes, or SetTextAttributes / SetRangeParams / SetRangeColor of length 0 at the
      caret) changes no text - it is the format the next typed text gets (TypingFormat), and
      what SelAttributes reads. No command, no undo step, no OnChange. It lasts until the
      selection is set again (even to the same place: Windows' rich edit's way - the caret then
      takes its neighbour's format again), an edit other than typing, a change from code, an
      undo or a redo, or a new content - application code that sets the selection again,
      even to the same place (SelStart := SelStart), drops it, as on Windows; typing, an input method's commit and a paste of plain
      text use it once, and the text they put in carries it. A paragraph write with nothing
      selected changes the caret's paragraph at once (a command). }

    { Delphi's SelAttributes: the selection's character format - reading answers for the
      selection's first character (nothing selected: the format the next typed text gets),
      ConsistentAttributes says which attributes the whole selection shares; writing one
      attribute formats the selection (or sets the pending format). A name or a size the
      text has none of its own of reads as the base's (DefAttributes). Assign: all at once. }
    property SelAttributes: TTyRichTextAttributes read FSelAttributes write SetSelAttributes;
    { Delphi's DefAttributes: what text without a font, a size, a style or a colour of its
      own is shown in - the control's Font, laid over the theme (TyApplyControlFont): one
      truth, not two. Reading gives the base as resolved (the theme's font when Font was not
      set); writing sets Font's name, size, style, colour or charset (no command, no undo
      step - Delphi's DefAttributes is not undone either - and the whole view laid out
      again). Its BackColor and VertAlign are always clNone / vaNone: writing them raises
      ETyRichEdit. A document read from RTF names its own default font and size (\deff,
      \fs: content, kept and saved), which its plain text shows instead: DefAttributes then
      reaches only text without a font of its own (text typed in a new document or a text
      file). }
    property DefAttributes: TTyRichTextAttributes read FDefAttributes write SetDefAttributes;
    { Delphi's Paragraph: the paragraph format of the paragraphs the selection touches (see
      TTyRichParaAttributes; points). }
    property Paragraph: TTyRichParaAttributes read FParagraph write SetParagraph;

    { RichMemo's style. Positions are this control's: characters as the engine counts them
      (TTyRichPos - a code point, a paragraph separator one), not RichMemo's UTF-16 units. }
    { The characters [AStart, AStart + ALen) take AParams' name, size, colour, styles,
      highlight (HasBkClr False: none) and vertical position, in one command; ALen 0 at the
      caret with nothing selected: the pending format. ALen 0 elsewhere: nothing. }
    procedure SetTextAttributes(AStart, ALen: TTyRichPos; const AParams: TTyFontParams); overload;
    { ... a TFont's name, size, styles, colour and charset. }
    procedure SetTextAttributes(AStart, ALen: TTyRichPos; AFont: TFont); overload;
    { The format of the character at APos (at a paragraph's end, its last run's): False when
      APos is outside the text. Name and size resolved as SelAttributes reads them. }
    function GetTextAttributes(APos: TTyRichPos; var AParams: TTyFontParams): Boolean;
    procedure SetRangeColor(AStart, ALen: TTyRichPos; AColor: TColor);
    { Only what AModifyMask names: tmm_Name the name, tmm_Size the size, tmm_Color the colour,
      tmm_BackColor the highlight (AParams' HasBkClr / BkColor), tmm_Styles AAddFontStyle
      put on and ARemoveFontStyle taken off (the other styles each character keeps). }
    procedure SetRangeParams(AStart, ALen: TTyRichPos; AModifyMask: TTyTextModifyMask;
      const AFontName: string; AFontSize: Integer; AFontColor: TColor;
      AAddFontStyle, ARemoveFontStyle: TFontStyles); overload;
    procedure SetRangeParams(AStart, ALen: TTyRichPos; AModifyMask: TTyTextModifyMask;
      const AParams: TTyFontParams; AAddFontStyle, ARemoveFontStyle: TFontStyles); overload;
    { The run of characters around APos that share its format, inside its paragraph (a
      paragraph's end: its last run): False outside the text. }
    function GetStyleRange(APos: TTyRichPos; var ARangeStart, ARangeLen: TTyRichPos): Boolean;
    { The paragraph APos is in (False: outside the text); the Set methods change the
      paragraphs [AStart, AStart + ALen) touches, one command each. Points.
      TTyParaAlignment is RichMemo's TParaAlignment (paLeft, paRight, paCenter, paJustify):
      in a unit that also uses Menus (whose TPopupAlignment has paLeft, paRight, paCenter),
      the unit used last decides what a bare paLeft means - qualify the name there. }
    function GetParaAlignment(APos: TTyRichPos; var AAlign: TTyParaAlignment): Boolean; overload;
    function GetParaAlignment(APos: TTyRichPos): TTyParaAlignment; overload;
    procedure SetParaAlignment(AStart, ALen: TTyRichPos; AAlign: TTyParaAlignment);
    function GetParaMetric(APos: TTyRichPos; var AMetric: TTyParaMetric): Boolean;
    { Indents, spaces and the line spacing at once (SetRangeParaParams with every field);
      a LineSpacing of 0 or less leaves the paragraphs' spacing as it is. }
    procedure SetParaMetric(AStart, ALen: TTyRichPos; const AMetric: TTyParaMetric);
    { Only what AModifyMask names, per paragraph (RichMemo's: each paragraph's metric read,
      the named fields changed, written back): pmm_FirstLine moves each first line, the
      other lines staying; pmm_HeadIndent the other lines, each first line staying; both: as
      given. pmm_LineSpacing with 0 or less: nothing. One command. }
    procedure SetRangeParaParams(AStart, ALen: TTyRichPos; AModifyMask: TTyParaModifyMask;
      const AMetric: TTyParaMetric);
    function GetParaNumbering(APos: TTyRichPos; var ANumber: TTyParaNumbering): Boolean;
    { As Paragraph.Numbering: a list turned on gives a paragraph without an indent the
      default hanging indent, turned off takes the indents back to 0 (CTyListMask). }
    procedure SetParaNumbering(AStart, ALen: TTyRichPos; const ANumber: TTyParaNumbering);
    { RichMemo's GetParaRange: the paragraph APos is in - its first character, its length
      without and with its separator (the last paragraph has none). False outside the
      text. }
    function GetParaRange(APos: TTyRichPos; var ARange: TTyParaRange): Boolean; overload;
    function GetParaRange(APos: TTyRichPos; var AStart, ALength: TTyRichPos): Boolean; overload;
    function GetParaTabs(APos: TTyRichPos; var AStopList: TTyTabStopList): Boolean;
    procedure SetParaTabs(AStart, ALen: TTyRichPos; const AStopList: TTyTabStopList);
    { LoadFromStream(AStream, rfRtf) / SaveToStream(AStream, rfRtf): False when it raised
      (what the document had stays). }
    function LoadRichText(AStream: TStream): Boolean;
    function SaveRichText(AStream: TStream): Boolean;
    { RichMemo's GetText / GetUText: RangeText of the clamped range (UTF-8 / UTF-16). }
    function GetText(AStart, ALen: TTyRichPos): string;
    function GetUText(AStart, ALen: TTyRichPos): UnicodeString;
    { RichMemo's InDelText: the characters [AStart, AStart + AReplaceLen) replaced by AText
      (line breaks make paragraphs) in the format of the first character replaced (nothing
      replaced: the format typing there would get), as ONE undo step; a document-API write
      (not refused by ReadOnly; raises ETyRichEdit when the document takes no edit). The
      selection follows the text as it does for any change elsewhere. Returns the number of
      characters inserted (this control's characters). }
    function InDelText(const AText: string; AStart, AReplaceLen: TTyRichPos): TTyRichPos;
    { RichMemo's CharAtPos: the position at client point (X, Y) (PositionAtPoint). }
    function CharAtPos(X, Y: Integer): TTyRichPos;

    { ---- the document's own settings (edits from code: not refused by ReadOnly; one undo
      step each - TTyRichChangeSettings; ETyRichEdit when the document takes no edit) ----
      SetPageSetup: the paper's width and the left and right margins, twips - the width a
      page-wide layout (WrapMode rwmPage) wraps at, and what a file gets; the paper's height
      stays. A width the margins leave no room in raises ETyRichEdit, nothing changes.
      SetDefaultFormats: the formats a paragraph with nothing of its own has (the
      document's DefaultCharFormat and default paragraph format): a new document's text, the
      paragraphs of a text file, what a file names as its defaults (RTF's \defchp and \defpap groups).
      What a file read on demand holds keeps its look (TTyRichDocument.ChangeSettings).
      DocumentColor: the document's own ground, drawn under the text as the file has it (the
      theme does not change it; automatic text over it takes the contrasting colour);
      clNone: none - the theme's ground. A file keeps it as Word's page colour. Written the
      same as it is: no step. }
    procedure SetPageSetup(AWidthTwips, ALeftTwips, ARightTwips: Integer);
    procedure SetDefaultFormats(const AChar: TTyCharFormat; const APara: TTyParaFormat);
    property DocumentColor: TColor read GetDocumentColor write SetDocumentColor;
    { The user's action for the space before and after the paragraphs the selection touches,
      points (ApplyParagraphFormat's rules: refused by ReadOnly, told once). }
    function ApplyParagraphSpacing(ABeforePt, AAfterPt: Double): Boolean;

    { ---- content built from code (tyControls.RichEdit.Builder) ----
      All three are edits from code: ReadOnly is not asked; nothing is laid out or painted
      until the next paint (one layout, one paint); the builder stays the caller's, as it was
      (it can be put in again). A builder that holds nothing puts nothing in. A document being
      saved raises ETyRichEdit and nothing changes; SetContent on a document still loading
      ends the load and replaces the document, AppendContent and InsertContent raise on a
      document that is loading or incomplete.
      NewBuilder: a builder (the caller frees it) whose defaults are this document's - its
      default character and paragraph formats (what Reset and Paragraph go back to) and its
      text width (what equal columns share). }
    function NewBuilder: TTyRichBuilder;
    { A new content, as a load: the history goes, the document not Modified; the document's
      own values (the page, the default formats, the ground) are the builder's where it set
      them (PageSetup, DocumentColor), else what Clear leaves. The paragraphs are the
      builder's, and nothing after them (a document that ends with a table keeps the empty
      paragraph after it). The caret goes to the start, nothing selected. }
    procedure SetContent(ABuilder: TTyRichBuilder);
    { The builder's paragraphs after the document's last (a last paragraph that holds
      something stays as it is, and the content begins a paragraph of its own after it; an
      empty last paragraph takes the content's first), as ONE undo step. The document's own
      values are not touched; the fonts and colours come along. The selection stays where it
      was (a caret at the very end goes along with the end). }
    procedure AppendContent(ABuilder: TTyRichBuilder);
    { The builder's content at APos, one undo step. At a paragraph's start its paragraphs go
      in before that paragraph, whole; inside a paragraph they go in as a paste does - the
      first joins the text before APos (the paragraph takes its format, unless the content is
      one paragraph: then it goes in in line), the last the text after it. In a table cell,
      every paragraph is the cell's (a table of the builder becomes its text: never a table in
      a table). The selection is shifted by what went in before it. }
    procedure InsertContent(APos: TTyRichPos; ABuilder: TTyRichBuilder);

    { ---- finding and replacing ----
      What a match is (tyControls.RichEdit.Find): the needle against the text as it is shown -
      CR LF, LF or CR in it is a paragraph's end, U+000B a line break; an object is matched by
      nothing; the cells merged away are not there; case folded per code point unless asked;
      whole word by the caret's word rule. Positions are this control's characters.

      Delphi's FindText: the first match inside [StartPos, StartPos + Length) - the whole
      match inside -, -1 for none; a Length below 0 searches to the end. stMatchCase,
      stWholeWord. Synchronous, to the end of the range, with the wait cursor (BeginWait)
      when the range is longer than CopyWaitChars; it neither selects nor scrolls, and never
      parses a paragraph of a lazily read file only to learn that it cannot match. A document
      still loading is searched as far as it is loaded (-1: not in what is loaded yet). }
    function FindText(const SearchStr: string; StartPos, Length: TTyRichPos;
      Options: TTySearchTypes): TTyRichPos;
    { RichMemo's Search: forward as FindText - [Start, Start + Len), a Len below 0 to the
      end; soBackward as RichMemo's back ends have it: the search begins at Start and goes
      toward the text's beginning over Len characters - [Start - Len, Start], not below 0, a
      Len below 0 down to 0 -, the match nearest Start (its whole inside). The second form
      gives the match's start and length (characters) and says whether there was one (the
      variables are left as they were when there was none); its Integer form for RichMemo
      code with Integer variables (a match past MaxInt is told as none). }
    function Search(const ANiddle: string; Start, Len: TTyRichPos;
      const SearchOpt: TTySearchOptions): TTyRichPos; overload;
    function Search(const ANiddle: string; Start, Len: TTyRichPos;
      const SearchOpt: TTySearchOptions; var ATextStart, ATextLength: TTyRichPos): Boolean; overload;
    function Search(const ANiddle: string; Start, Len: TTyRichPos;
      const SearchOpt: TTySearchOptions; var ATextStart, ATextLength: Integer): Boolean; overload;
    { The user's Find Next (a user's action - an open composition ends first; it edits
      nothing, so ReadOnly does not stop it): the next match after the selection (rfoBackward:
      the one before it); with rfoWrap the search goes on from the document's other end, to
      where it began (the text is read once). Found: it is selected, in view (as SelStart /
      SelLength place a selection: a match in a cut paragraph's hidden tail stays selected
      there and shows at the cut; a match that begins or ends inside a cluster - a letter of a
      letter with a combining mark - selects the whole cluster, so the selection is never
      empty and the next call goes on after it), one OnSelectionChange; True. Synchronous: the
      wait cursor over a document longer than CopyWaitChars. Stops a background find or
      replace (as a new start does); a handler of its end that frees the control: False, and
      nothing else happens. }
    function FindNext(const AText: string; AOptions: TTyRichFindOptions = [rfoWrap]): Boolean;
    { FindNext in the background: the search runs in the turns of the background work (one
      piece of CRichFindMinStepChars .. CRichFindStepChars units of a finder's step at a time
      - bytes read; a paragraph larger than that is read in pieces -, sized by the turns' time
      as a load's slices are), OnFindProgress after each piece (ACancel stops it), and
      OnFindDone at its end - found: selected and in view. A second start, CancelFind and a
      new content stop it, as does any change of the document (an edit, an undo), noticed at
      its next piece: a position found before it could be stale - each with OnFindDone
      (rfeCancelled; a new content's from the public call that replaced it, before it
      returns). The window made again (RecreateWnd) does not stop it: it waits for the window,
      as a load does. The control's end stops it with no event. A document still loading is
      searched as far as it is loaded, and on as the load goes on. Only while the control
      has a window (as the load's turns). }
    procedure FindNextAsync(const AText: string; AOptions: TTyRichFindOptions = [rfoWrap]);
    { Every match of AFind in the text replaced by AReplace (line breaks make paragraphs), in
      the format of the first character each replaces, as ONE undo step
      (TTyRichReplaceAllCommand: never merged; an undo puts the selection back); a
      document-API write (not refused by ReadOnly). Matches as a forward find has them -
      leftmost, never overlapping ("a" by "aa" replaces each "a" once); rfoBackward and rfoWrap
      are not looked at. A match the document would not let a user's edit change is left as
      it is and counted in Skipped: one in a row that holds a nested table, one whose deletion
      would join across a cell's or a row's edge or into a table (also one that ends with a
      cell's last paragraph end, or with the one before a table), and every match of a
      document that is loading, incomplete or being saved (then nothing is replaced). Nothing
      is raised for a refusal. Returns the number replaced. The third form replaces in the
      range [AStart, AStart + ALength) only (ALength < 0: to the text's end - the shape
      FindText has) and tells how it ended in AResult (Ending: rreDone, rreLimit when the step
      reached its limit - four times Document.MaxUndoBytes -, rreCancelled when the document
      refused the step, rreFailed): what was replaced is the one step, and the same call from
      AResult.ResumeAt for AResult.ResumeLength replaces the rest (repeat it while the ending
      is rreLimit). The text is walked from the range's start, a range of
      paragraphs at a time, as the background form does: a lazily read file is parsed once
      and let go range by range. Synchronous, the wait cursor over a document longer than
      CopyWaitChars; stops a background find or replace first. One OnChange. A handler of that
      one's end that frees the control: nothing is replaced, the result is 0 and AResult an
      empty record whose Ending is rreCancelled (ResumeAt -1). }
    function ReplaceAll(const AFind, AReplace: string;
      AOptions: TTyRichFindOptions = []): Integer; overload;
    function ReplaceAll(const AFind, AReplace: string; AOptions: TTyRichFindOptions;
      out ASkipped: Integer): Integer; overload;
    function ReplaceAll(const AFind, AReplace: string; AOptions: TTyRichFindOptions;
      AStart, ALength: TTyRichPos; out AResult: TTyRichReplaceResult): Integer; overload;
    { ReplaceAll in the background, in the range [AStart, AStart + ALength) (ALength < 0: to
      the text's end): the same command, its parts in the turns - a range of paragraphs
      searched (in pieces as FindNextAsync's), then replaced, the document consistent between
      two -, OnFindProgress after each piece (characters of the range, from its start on), and
      OnReplaceDone at the end (rreDone, rreLimit, rreCancelled; ResumeAt says where a new
      start goes on). Stopped as FindNextAsync is - by CancelFind, the progress handler, a new
      start, any change of the document that is not its own (an edit, an undo), a new
      content, and a save (SaveToFile, SaveToStream, Modified := False: the saved point ends
      the step) -: what was replaced until then stays, as one undo step, and nothing of it is
      left on the redo side. While the file still loads, while an input method composes or
      the document holds its changes back (an update), no part goes in, and it asks for no
      turn. }
    procedure ReplaceAllAsync(const AFind, AReplace: string; AOptions: TTyRichFindOptions = [];
      AStart: TTyRichPos = 0; ALength: TTyRichPos = -1);
    { Stops a background find or replace (OnFindDone rfeCancelled / OnReplaceDone
      rreCancelled); a replace keeps what it replaced, as one undo step. Nothing runs: nothing
      happens. }
    procedure CancelFind;
    { A background find or replace runs. }
    property FindRunning: Boolean read GetFindRunning;
    { After each piece of a background find or replace (ATask says which): ADone of ATotal
      characters of the range it searches, in the text it began on (a replace whose needle
      holds a paragraph end: its search is the first half of ATotal, the replacing the
      second); never back, and at its end - whatever ended it - ADone = ATotal, before the
      done-event. ACancel stops it. }
    property OnFindProgress: TTyRichFindProgressEvent read FOnFindProgress write FOnFindProgress;
    property OnFindDone: TTyRichFindDoneEvent read FOnFindDone write FOnFindDone;
    property OnReplaceDone: TTyRichReplaceDoneEvent read FOnReplaceDone write FOnReplaceDone;
    { RichMemo's SetSelLengthFor: SelLength := the number of characters of AText. }
    procedure SetSelLengthFor(const AText: string);
    { RichMemo's ZoomFactor: Zoom / 100 (written: rounded to Zoom's whole percent). }
    property ZoomFactor: Double read GetZoomFactor write SetZoomFactor;
    { Delphi's PlainText, the plain-text document state - one state, one rule.
      True: a key makes no line break inside a paragraph (Shift+Enter makes a paragraph), a
      paste takes text only, and SaveToStream without a format (Lines.SaveToStream too)
      writes plain text. False: the document is rich - SaveToStream without a format writes
      RTF, whatever the content was loaded from (PlainText := False on an opened text file
      makes it save as RTF).
      Only two things set it: a load through the control (the document follows the file: a
      text file makes it True, an RTF file False) and this property; Lines.Text, Text and
      SelText leave it alone (a rich control filled through Lines stays rich and saves RTF);
      a new control is rich.
      Set True by code or the Object Inspector (asked) it also decides the loads and the
      file saves without a format, as Delphi's: LoadFromFile, LoadFromStream and
      Lines.LoadFromFile read plain text whatever the file is, SaveToFile writes text whatever
      the extension, until PlainText := False, a load whose format came from its file, or an
      RTF load the caller asked for (LoadRichText, LoadFromStream(S, rfRtf)) - a load read as
      text, by the asking or by the caller's rfText, keeps it. Made True by a load it does
      not: SaveToFile then
      goes by the extension (a text file opened, formatted and saved as notes.rtf is RTF),
      else by the state.
      Setting it changes no content: a document with formats keeps them, and a save as text
      writes its characters only (fonts, colours, paragraph formats, pictures and tables'
      structure do not go into a text file - a cell's paragraphs as lines). Such a save of a
      plain-text document clears Modified all the same: the caller asked for text (rfText, a
      .txt name or PlainText), which is the application's choice; a rich document saved as
      text is an export and stays Modified (see Modified). }
    property PlainText: Boolean read FPlainText write SetPlainTextState default False;
    property Document: TTyRichDocument read FDoc;
    property Layouter: TTyRichLayouter read FLayouter;
    { The view's top in pixels of the document's heights (measured and estimated); -1 inside
      the document's update. }
    property ScrollY: Int64 read GetScrollY write SetScrollY;
    property ScrollX: Integer read GetScrollX;
    { The widest block laid out so far: the horizontal extent (never measured over the
      document). }
    property HorizontalExtent: Integer read GetHorizontalExtent;
    { The block at the view's top, and how many of its (client) pixels are above the view. }
    property TopParagraph: Integer read FAnchorPara;
    property TopOffset: Int64 read GetTopOffset;
    property Loading: Boolean read GetLoading;
    property Incomplete: Boolean read GetIncomplete;
    { The document's (TTyRichDocument.Modified): False exactly when the content is the
      one last loaded or saved - an undo back to it or a redo forward to it makes it False
      again; True for good once the history let go of the way back. Cleared by SaveToFile in
      a format that keeps the document (RTF; text for a plain-text document - PlainText
      True -, its formats dropped from the file by the caller's choice) - the saved point is
      set there; a rich document saved as text is an export and stays Modified, with its
      SourceFile and SourceFormat. SaveToStream never touches Modified, SourceFile or
      SourceFormat. Modified := False sets the saved point at the content as it is. A change
      made outside a command (straight on Document.Text, or a primitive run by no command)
      turns Modified at once, but OnModifiedChange is raised only at the next step, undo,
      redo, load or save. }
    property Modified: Boolean read GetModified write SetModified;
    { Modified turned (TTyRichDocument.OnModifiedChange: at the end of the edit, the undo,
      the redo, the load or the save that turned it); OnChange is not raised by Modified
      alone. }
    property OnModifiedChange: TNotifyEvent read FOnModifiedChange write FOnModifiedChange;
    { The file the content was loaded from or last saved to ('' when none). }
    property SourceFile: string read FSourceFile;
    property SourceFormat: TTyRichFormat read FSourceFormat;
    { Fonts tried for a character the font in effect has no glyph for (the layouter's). }
    property FallbackFonts: TStrings read GetFallbackFonts;
    property WrapMode: TTyRichWrapMode read FWrapMode write SetWrapMode default rwmWindow;
    property Zoom: Integer read FZoom write SetZoom default 100;
    { The user's editing, only: with True no key, no menu item, no input method and no paste
      (PasteFromClipboard, as TTyMemo's) changes the document - setting it cancels a
      composition; the caret, the selection and copying work as in a viewer. Code is not
      stopped by it, as TMemo.ReadOnly does not stop Lines.Add: the document's commands
      (Document.Execute), Lines, SelText, Text, the format API and the replace methods change
      the document with ReadOnly True. The user's actions called by code (CutToClipboard,
      PasteFromClipboard, ClearSelection, Undo, Redo) do nothing, as Delphi's. }
    property ReadOnly: Boolean read FReadOnly write SetReadOnly default False;
    { True: the selection - text or an object - can be dragged to another place of the
      control: a left press inside it and a move past the drag threshold (DragThreshold)
      begin the drag - a background find or replace ends at that press, cancelled, as typing
      ends it; a press whose wait something else ends is a plain click at its release -,
      the drop mark shows where it would go (the place under the pointer, also after a scroll
      or a zoom during the drag; outside the control nothing is a place), the release moves it
      there, or copies it with Ctrl held (each one undo step; the clipboard is not used). Esc,
      the right button, the capture lost, a key that is not a modifier, a change of the
      selection or of the content end the drag with nothing changed; a release inside the
      selection does nothing; a press and release without a drag is a plain click. Over
      another TTyRichEdit of the application (any form) the drag goes on there: its mark, its
      edge scrolling, and the release drops there - a copy with Ctrl, else a move (the
      content goes in there as one step of that control's history and leaves this one as one
      step of this history); a copy only when this control cannot give the content away
      (ReadOnly, or a range its cut refuses); nothing changes here when the drop there is
      refused or fails. No clipboard and no system drag are used: it works on every
      widgetset. Elsewhere outside the control nothing is a place. Not while the document
      takes no edit (loading, saving); with ReadOnly the selection can be dragged out as a
      copy, but nothing is taken here. DragMode dmAutomatic leaves the press to LCL's own drag
      (no drag of the selection begins). False: a press inside the selection is a plain
      click, no drag of another control of the application is taken, nor an offer the
      application feeds in (DropEnter answers rdeNone). Drops from other programs are
      AcceptDrops' alone: turning every kind of drop off takes both. }
    property DragDropEditing: Boolean read FDragDropEditing write SetDragDropEditing default True;
    { True (the default): the control takes drops from other programs - on the Windows
      widgetset, where its window is registered with the system as a drop target while it has
      one (never in the designer). What a paste would take, in the paste's order: rich text
      (RTF), a picture (PNG, then a bitmap with either header), plain text (Unicode, else ANSI
      in its locale's code page); a list of files when none of the first two comes with it: OnDropFiles first, then - if every file is named as a picture - each
      file as InsertPictureFromFile takes it, in the order given, one step. Ctrl: a copy;
      otherwise a move when the program allows it (it then deletes its own content), else a
      copy; a drop that is refused or fails reports nothing done, so the program keeps its
      data (a file list the application took in OnDropFiles reports a copy). With it True the control, not its form, receives what is dropped on it; False
      registers nothing, and the form's own file drop (AllowDropFiles, OnDropFiles) works
      over the control. Other widgetsets: no drop from other programs in this version (the
      property is kept, and does nothing). It governs drops from other programs alone: the
      control's own drag and drags between two controls of the application are
      DragDropEditing's; turning every kind of drop off takes both. False ends a drop from
      another program under way. }
    property AcceptDrops: Boolean read FAcceptDrops write SetAcceptDrops default True;
    { A list of files is dropped on the control (AcceptDrops): raised before the control
      handles it, with the names in the order given; AHandled True and the control does
      nothing more (the drop reports a copy). Raised also when the control is read-only. }
    property OnDropFiles: TTyRichDropFilesEvent read FOnDropFiles write FOnDropFiles;
    { True: Tab inserts a tab character (Shift+Tab and Ctrl+Tab too, as the memo) - in a table
      Tab goes to the next cell and Shift+Tab to the one before (Word's keys: see KeyDown),
      and Ctrl+Tab inserts the tab character. False (the default, as the memo): Tab is left
      to the form, which moves the focus, in a table too. }
    property WantTabs: Boolean read FWantTabs write FWantTabs default False;
    { Not published by TTyRichEdit: a rich document cannot live in a form file as lines
      without its formats, so a form stores no content; an application sets the text or
      loads a file at run time. A descendant that publishes it stores only what was set as
      lines (in the designer or by code), never a file loaded at run time. }
    property Lines: TStrings read GetLines write SetLines stored IsLinesStored;
    { A txt file is read in this encoding (teAuto: found out) and, for teAnsi, code page. }
    property TextEncoding: TTyTextEncoding read FTextEncoding write FTextEncoding default teAuto;
    property TextCodePage: Integer read FTextCodePage write FTextCodePage default 0;
    property ScrollBarAutoHide: TTyScrollBarAutoHide read FScrollBarAutoHide
      write SetScrollBarAutoHide default sbahDefault;
    { ---- a display page (a home page, a help page built from code) ----
      CaretWhenReadOnly: False hides the caret while ReadOnly (an editable control shows it
      whatever this says); the caret still is where it was, the end a selection grows from
      with Shift and the arrows, and the selection is drawn as ever. }
    property CaretWhenReadOnly: Boolean read FCaretWhenReadOnly write SetCaretWhenReadOnly default True;
    { False: a mouse press never takes the focus (the wheel still scrolls under the pointer,
      a link still clicks); with TabStop False the control is never focused at all - it still
      paints, follows the theme and fires OnLinkClick. }
    property FocusOnClick: Boolean read FFocusOnClick write FFocusOnClick default True;
    { False: the user makes no selection - no drag, no double or triple click, no Shift+click,
      no Shift+arrow, Ctrl+A does nothing; copying is unavailable (Copy, the menu's Copy and
      Select All, CopyToClipboard); the pointer is the arrow over the text (the hand over a
      link, which a plain left click fires, as under ReadOnly); a press places no caret. What
      code selects (SelStart, SelLength, SelectAll, a find's match) is the application's
      asking: it is drawn and scrolled into view as ever. With ReadOnly as well, a right click
      shows no menu of the control's own (all of it would be grey); PopupMenu and
      OnContextPopup work as on any control. }
    property AllowSelection: Boolean read FAllowSelection write SetAllowSelection default True;
    { The bars that may show, each only when the content needs it (as ScrollBarAutoHide
      decides how it looks); ssNone: never - the keys, ScrollX and the anchor still scroll.
      ssAutoHorizontal, ssAutoVertical, ssAutoBoth are ssHorizontal, ssVertical, ssBoth: every
      bar here is shown only when needed. The wheel is the control's in a direction it can
      scroll (a bar may show there and the content does not fit, or the view is off its
      start) - also at its end; in any other it goes on to the parent (a page in a scroll box
      scrolls with the box). Ctrl + wheel always zooms. }
    property ScrollBars: TScrollStyle read FScrollBars write SetScrollBars default ssBoth;
    { True: the control's Height is ContentHeight (within Constraints), set again whenever the
      content, the width, the zoom, the PPI, the theme or the padding change; no vertical bar
      then. Nothing is set while Align or the anchors (top and bottom) make the parent decide
      the height, nor while the content's size is an estimate (ContentSizeIsEstimate: a file
      still loading, more paragraphs than are measured whole) - the height stays. Never more
      than CRichAutoHeightLimit. For pages, not files: the control keeps a drawing surface of
      its own size (width x height x 4 bytes); a document longer than the limit belongs in a
      control that scrolls itself. }
    property AutoHeight: Boolean read FAutoHeight write SetAutoHeight default False;
    { The client pixels the content needs at the current width, zoom, PPI and theme, the
      padding included (and a horizontal bar that shows): exact once every paragraph is laid
      out - a document built from code or loaded whole of up to CRichContentExactParas
      paragraphs is measured whole when this is asked; else the estimate the scroll bar
      works with, and ContentSizeIsEstimate says so. }
    function ContentHeight: Integer;
    function ContentWidth: Integer;
    function ContentSizeIsEstimate: Boolean;
    { ContentHeight or ContentWidth changed: once per change, never inside a paint (queued to
      the loop from where it cannot run), after UpdateView. A handler may resize the control. }
    property OnContentSizeChange: TNotifyEvent read FOnContentSizeChange write FOnContentSizeChange;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    { The caret or the anchor moved: once per user action (a key, a press, a move of a drag),
      once for a document change that moved them, and not while loading a form file. }
    property OnSelectionChange: TNotifyEvent read FOnSelectionChange write FOnSelectionChange;
    property OnZoomChange: TNotifyEvent read FOnZoomChange write FOnZoomChange;
    { An edit the user asked for was refused (see EditRefused). }
    property OnEditRefused: TTyRichEditRefusedEvent read FOnEditRefused write FOnEditRefused;
    { The progress events run inside a load step or a save. Their handlers must not free the
      control (as the memo's events must not). Replacing the content from them - a load,
      Lines.Text, Lines.Clear - raises ETyRichEdit (the step or the save goes on); CancelLoad
      from a load progress handler stops the load once the step has returned. }
    property OnLoadProgress: TTyRichProgressEvent read FOnLoadProgress write FOnLoadProgress;
    property OnSaveProgress: TTyRichProgressEvent read FOnSaveProgress write FOnSaveProgress;
    property OnFallbackFont: TTyRichFallbackEvent read GetOnFallbackFont write SetOnFallbackFont;
    { The constructor's values: a fresh control stores neither, and a Cursor of crDefault
      set in the designer is stored. }
    property TabStop default True;
    { ITyScrollBarFrameHost }
    function ScrollBarFrameStyle: TTyStyleSet;
    function EmbedsScrollBar(ABar: TTyScrollBar): Boolean;

    { ---- the paragraph view: what a ruler (TTyRichEditRuler, or an application's own) needs,
      in public calls only ----
      ParagraphView: the first paragraph a paragraph format change would apply to - the one
      ApplyParagraphFormat and Paragraph begin at: the caret's with nothing selected, else the
      first the selection touches (a selection that ends at a paragraph's very start does not
      touch that one) - and where its text is on the screen (TTyRichParaView), as the view was
      last laid out. It lays nothing out and reads that paragraph's format and what
      CanFormatParagraphs reads, so it costs the same in any document. False when there is
      nothing to show: the view was never laid out, the document is in its update, or the
      paragraph is in a table cell whose row is not laid out (scrolled away). }
    function ParagraphView(out AView: TTyRichParaView): Boolean;
    { Who hears that the paragraph view may have changed - the caret or the selection moved,
      the content or a format changed, the view was laid out (a zoom, a scroll, a resize, the
      wrap mode, the theme, the PPI), ReadOnly or Enabled changed (its own, or a parent's), the
      format the next typed text gets set with nothing selected: AHandler(Sender = this
      control), not the application's OnChange or OnSelectionChange. It may come when nothing
      that is shown changed: the hearer asks ParagraphView and compares. A handler must not
      free the control or change the document. }
    procedure AddHandlerOnParagraphView(const AHandler: TNotifyEvent);
    procedure RemoveHandlerOnParagraphView(const AHandler: TNotifyEvent);
    { A vertical line through the text at client x GuideLine, over what is shown, in the text
      colour (the caret's: no token of its own), one pixel of 96 PPI wide, inside the text clip -
      where a ruler's drag would put what it moves. -1 (the default): none. Not part of the
      document or the kept surface: setting it blits again its old place and its new one. }
    property GuideLine: Integer read GetGuideLine write SetGuideLine;
    { The user's paragraph format action (a ruler's drag, a toolbar's indent button): AMask's
      fields of AValue (TyMergeParaFormat's meanings) to every paragraph the selection touches
      (the caret's when nothing is selected), in one command - TTyRichSetParaFormat, one undo
      step named as the format API's -, the selection kept where it is and the view not
      scrolled, one OnChange. As the user's other actions: an open composition ends first; a
      read-only or disabled control, one in the designer or inside the document's update does
      nothing and tells nothing (False); a refusal - the document loading, incomplete or being
      saved, a range of fields' results only, a range of a row that holds a nested table
      only (CanFormatParagraphs says so first) - is told once through EditRefused
      (OnEditRefused), never raised, and nothing changes. A plain-text document is formatted as
      the format API formats it (a text save leaves the formats out). True: the formats
      changed. A handler the action runs may free the control: False then. }
    function ApplyParagraphFormat(AMask: TTyParaFormatMask; const AValue: TTyParaFormat): Boolean;
    { The user's list level change (Word's Tab and Shift+Tab at an item, the indent buttons on
      list items): when every paragraph the selection touches (the caret's when nothing is
      selected) is a list item, each goes ADelta levels deeper (1) or shallower (-1), within
      0 .. 8 - an item at level 0 stays where it is on -1, as in Word - its indent with it
      (TTyRichChangeListLevel), in one undo step; the numbers follow (an inner item after an
      outer one starts at 1, the outer list goes on after it). ApplyParagraphFormat's rules
      otherwise: read-only, disabled or the designer do nothing and tell nothing, a refusal is
      told once. True: the paragraphs were all list items (the change was the list level's,
      also when no item could move or it was refused); False: they were not, nothing done -
      the caller does what it does for other paragraphs. }
    function ChangeListLevel(ADelta: Integer): Boolean;
  private
    { The paragraphs of each cell of AArea (VisitArea's order): AFirst[i] .. ALast[i]. }
    procedure AreaParaSpans(const AArea: TTyRichCellArea; out AFirst, ALast: TIntegerDynArray);
    // Tab (ADeeper) or Shift+Tab at a list item's start or over whole items: its level moved
    function ListTab(ADeeper: Boolean): Boolean;
    { The place's half of CanFormatCharacters / CanFormatParagraphs (AParagraphs) and of their
      doors: '' when the change would be taken at the selection, else the reason it would be
      told (rsRichEditRefusedField, rsRichEditRefusedFixedRow). See CanFormatCharacters for
      what it reads. }
    function FormatPlaceRefusal(AParagraphs: Boolean): string;
  public
    { The user's character format action (a toolbar's Bold, a font box): AMask's fields of
      AValue (TyMergeCharFormat's meanings) to the selection, in one command -
      TTyRichSetCharFormat, one undo step named as the format API's -, the selection kept and
      the view not scrolled; with nothing selected, the format the next typed text gets (no
      command, no undo step, as SelAttributes). A name or a size that is the base's leaves the
      text without one of its own, as the format API does. What makes it the user's and not
      the format API's (SelAttributes, SetTextAttributes, which are edits from code): ReadOnly,
      a disabled control, the designer and the document's update take nothing and tell nothing
      (False), as for a key; an open composition ends first; a refusal - the document loading,
      incomplete or being saved, every character of the selection (or the caret) inside a
      field's result or in a row that holds a nested table - is told once through
      EditRefused (OnEditRefused), never raised, and nothing changes. A selection that reaches
      outside a result is formatted outside it (the result keeps its look) and nothing is
      told. True: done. A handler it runs may free the control: False then. }
    function ApplyCharacterFormat(AMask: TTyCharFormatMask; const AValue: TTyCharFormat): Boolean;
    { Would ApplyCharacterFormat / ApplyParagraphFormat take the change now (what a toolbar's
      Update greys its buttons by), never told, never raised: False when ReadOnly, disabled,
      in the designer, inside the document's update, while the document loads, is incomplete
      or is being saved, and where the door would refuse - characters: every character of the
      selection inside a field's result or in a row that holds a nested table (nothing
      selected: typing at the caret would be refused there); paragraphs: every paragraph the
      selection touches ends inside a field's result or is in such a row. No layout is
      needed. What they read is what the engine's own refusal reads, bounded: the selection's
      paragraphs from its first, each one's field depths and cell, stopping at the first that
      takes the change - at most CRichFormatQueryParas of them; past that the answer is True
      (the door's own check then tells). }
    function CanFormatCharacters: Boolean;
    function CanFormatParagraphs: Boolean;
  published
    { TControl publishes Cursor and a redeclaration cannot unpublish it (the memo's #108). }
    property Cursor default crIBeam;
  end;

  { The palette's rich edit. Lines is not published (see TTyCustomRichEdit.Lines): a fresh
    control in a form file is its bounds and TabOrder only. }
  TTyRichEdit = class(TTyCustomRichEdit)
  published
    property Version;
    property Align;
    property Anchors;
    property BorderSpacing;
    property Constraints;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
    property ParentShowHint;
    property PopupMenu;
    property TabOrder;
    property TabStop;
    property Action;
    property DragMode;
    property DragKind;
    property DragCursor;
    property StyleClass;
    property StyleOverride;
    property Controller;
    property WrapMode;
    property Zoom;
    property ReadOnly;
    property DragDropEditing;
    property AcceptDrops;
    property WantTabs;
    property TextEncoding;
    property TextCodePage;
    property ScrollBarAutoHide;
    property CaretWhenReadOnly;
    property FocusOnClick;
    property AllowSelection;
    property ScrollBars;
    property AutoHeight;
    property PlainText;
    property OnChange;
    property OnSelectionChange;
    property OnModifiedChange;
    property OnZoomChange;
    property OnEditRefused;
    property OnLinkClick;
    property FollowBookmarkLinks;
    property OnFollowLink;
    property OnObjectClick;
    property OnObjectDblClick;
    property OnObjectResize;
    property OnDropFiles;
    property OnLoadProgress;
    property OnSaveProgress;
    property OnFindProgress;
    property OnFindDone;
    property OnReplaceDone;
    property OnFallbackFont;
    property OnContentSizeChange;
    property OnClick;
    property OnDblClick;
    property OnEnter;
    property OnExit;
    property OnKeyDown;
    property OnKeyUp;
    property OnKeyPress;
    property OnUTF8KeyPress;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseWheel;
    property OnMouseWheelUp;
    property OnMouseWheelDown;
    property OnMouseWheelHorz;
    property OnMouseWheelLeft;
    property OnMouseWheelRight;
    property OnContextPopup;
    property OnResize;
    property OnChangeBounds;
    property OnShowHint;
    property OnPaint;
    property OnEditingDone;
    property OnDragOver;
    property OnDragDrop;
    property OnStartDrag;
    property OnEndDrag;
  end;

{ The name a copy's RTF goes to the clipboard under, by widgetset (as the picture names are):
  LCL-Win32 the system's registered "Rich Text Format"; LCL-Cocoa (whose clipboard keeps a
  name it has no mapping of as the pasteboard type itself) the type public.rtf,
  NSPasteboardTypeRTF's; elsewhere - GTK, Qt, also Qt on Windows or on a Mac - the MIME type
  text/rtf, which LCL's Qt clipboard hands to Qt and GTK's makes an atom of: how those
  toolkits map it to the system's rich-text type on Windows or a Mac is theirs, not
  verified. }
function TyRichClipboardRtfName: string;

{ How many of a source's pictures were held against pictures read back by drops from another
  rich edit so far (the whole run's count): what a test bounds. }
function TyRichDropPictureCompares: Int64;

{ A picture object made from an image's bytes (what a paste makes of a clipboard's picture;
  inserting a picture from a file can make its own the same way). PNG and JPEG keep their
  bytes; a DIB, a BMP or a TIFF is decoded and stored as PNG (with its alpha when a pixel is
  not opaque; a 32-bit bitmap whose alpha is 0 everywhere is opaque, as Windows' bitmaps
  without alpha are). The image is decoded in any case: bytes that do not decode are no
  image (rpmNoImage). Its size: its pixels at its own resolution (a PNG's pHYs, a bitmap's
  pixels per metre) or at 96 dpi, scaled down keeping the ratio to AMaxWidthTwips when wider
  (0: no bound). Over CRichPictureMaxBytes bytes or CRichPictureMaxPixels pixels (asked of the
  header before anything is decoded: PNG's IHDR, a bitmap's header, a JPEG's frame, a
  TIFF's first directory): rpmTooLarge. An uncompressed DIB or BMP whose header promises
  more pixel bytes than there are is no image. A PNG is kept to its IEND chunk. APicture is the caller's (no reference taken) when rpmMade, else nil. }
function TyRichMakePicture(const ABytes: TBytes; AKind: TTyRichImageKind;
  AMaxWidthTwips: Integer; out APicture: TTyRichPicture): TTyRichPictureMade;

{ The size a drag of handle AHandle asks of an object of AWidth x AHeight twips when the
  pointer moved ADX, ADY twips (right and down positive): a corner moves both sides, the middle
  of a side that side only (the other stays as it is). AKeepRatio (a corner without Shift): the
  shape is kept - the side the drag changed more, relatively, decides, and the other follows.
  The bounds limit how far a drag takes a side, never where a side is already: a side is held
  to AMin .. its maximum (AMaxWidth, AMaxHeight), but one already past a bound is held to
  where it is instead (a side over the maximum can only get smaller, one under AMin only
  larger) - so a pointer that did not move gives the size back exactly. With the shape kept,
  the bounds hold for both sides at once (the shape survives them, unless the bounds leave no
  room for it: then the maximum wins). Each side at least 1. }
procedure TyRichResizedSize(AHandle: TTyRichHandle; AWidth, AHeight, ADX, ADY: Integer;
  AKeepRatio: Boolean; AMin, AMaxWidth, AMaxHeight: Integer; out ANewWidth, ANewHeight: Integer);

var
  { What TyRichMakePicture's walk of a TIFF's directory chain did (tests and probes):
    the directories visited and the entries read, added to on every call. }
  TyRichTiffDirsVisited: Int64 = 0;
  TyRichTiffEntriesRead: Int64 = 0;

{ The driver of the background work's turns on widgetset APlatform (see TTyRichTurnDriver). }
function TyRichTurnDriverFor(APlatform: TLCLPlatform): TTyRichTurnDriver;

{$IFDEF MSWINDOWS}
type
  TTyRichReplaceFileFunc = function(AReplaced, AReplacement, ABackup: PWideChar; AFlags: DWord;
    AExclude, AReserved: Pointer): LongBool; stdcall;

var
  { The call that puts a saved file in its target's place: kernel32's ReplaceFileW. A test
    seam (a test makes it fail with an error of its choice); nothing else sets it. }
  TyRichReplaceFileW: TTyRichReplaceFileFunc;
{$ENDIF}

{ A cell border (tyControls.RichEdit.TableProps.TyRichBorder, here for a caller of this unit
  alone). }
function TyRichBorder(AStyle: TTyRichBorderStyle; AWidthTwips: Integer;
  AColor: TColor = clDefault): TTyRichBorder;

implementation

uses
  {$IFDEF UNIX}BaseUnix,{$ENDIF}
  RTLConsts, Clipbrd, InterfaceBase, LazUTF8, FPImage, BGRAReadPng, BGRAReadBMP, BGRAReadTiff,
  BGRAReadJpeg, BGRAWritePNG, tyControls.StrConsts, tyControls.FontUnits,
  tyControls.PlatformWS, tyControls.Animation
  {$IFDEF LCLCocoa}, tyControls.CocoaWS{$ENDIF}
  {$IFDEF LCLWin32}, tyControls.RichEdit.OleDrop{$ENDIF};

function TyRichBorder(AStyle: TTyRichBorderStyle; AWidthTwips: Integer;
  AColor: TColor): TTyRichBorder;
begin
  Result := tyControls.RichEdit.TableProps.TyRichBorder(AStyle, AWidthTwips, AColor);
end;


const
  // what an edge drag does: none, a column's edge, a row's bottom
  CEdgeNone = 0;
  CEdgeColumn = 1;
  CEdgeRow = 2;
  // how far a drag may take an edge past the table (twips; a sheet is never this wide)
  CEdgeFar = 31680;

function TyRichGonePasses(const ALife: TTyRichLife): Boolean; forward;
procedure HandlerReturned(const ALife: TTyRichLife); forward;

const
  { A table action's place for the caret (TTyRichEditPlace.Caret): worked out once it ran
    (TTyCustomRichEdit.TableEditCaret). }
  CRichPlaceTable = -3;
  { A drop's place for the anchor and the caret: the content where it went
    (TTyRichRangeTransfer.Placed), worked out once it ran. }
  CRichPlaceInserted = -4;
  // where what the edit changed begins (the anchor of a drop's paste: what went in selected)
  CRichPlaceChangeStart = -5;
  { The table actions (TTyCustomRichEdit.FTableKind). }
  CTableInsertTable = 0;
  CTableInsertRow = 1;
  CTableInsertColumn = 2;
  CTableDeleteRow = 3;
  CTableDeleteColumn = 4;
  CTableDeleteTable = 5;
  // Tab in the table's last cell: a row below its last
  CTableTabRow = 6;

{ WM_IME_SETCONTEXT's flags: what the input context asks to show (ImeSetContextDefault, a
  seam on every widgetset; only win32's does something with them). }
const
  ISC_SHOWUICOMPOSITIONWINDOW = PtrInt($80000000);
  ISC_SHOWUIALL = PtrInt($C000000F);

{$IFDEF LCLWin32}
{ IMM32, which FPC's Windows unit does not declare (as tyControls.Win32WS declares it for the
  memo's composition window). }
const
  GCS_COMPSTR = $0008;
  GCS_COMPATTR = $0010;
  GCS_CURSORPOS = $0080;
  GCS_RESULTSTR = $0800;
  ATTR_TARGET_CONVERTED = 1;
  ATTR_TARGET_NOTCONVERTED = 3;
  NI_COMPOSITIONSTR = $0015;
  CPS_COMPLETE = $0001;
  CPS_CANCEL = $0004;
  CFS_POINT = $0002;
  CFS_EXCLUDE = $0080;
  IMR_QUERYCHARPOSITION = $0006;
  WM_IME_SETCONTEXT = $0281;

type
  TTyImmCompositionForm = record
    dwStyle: LongWord;
    ptCurrentPos: TPoint;
    rcArea: TRect;
  end;
  TTyImmCandidateForm = record
    dwIndex: LongWord;
    dwStyle: LongWord;
    ptCurrentPos: TPoint;
    rcArea: TRect;
  end;
  TTyImmCharPosition = record
    dwSize: LongWord;
    dwCharPos: LongWord;
    pt: TPoint;
    cLineHeight: LongWord;
    rcDocument: TRect;
  end;
  PTyImmCharPosition = ^TTyImmCharPosition;

function ImmGetContext(AWnd: THandle): THandle; stdcall; external 'imm32.dll' name 'ImmGetContext';
function ImmReleaseContext(AWnd, AImc: THandle): LongBool; stdcall;
  external 'imm32.dll' name 'ImmReleaseContext';
function ImmGetCompositionStringW(AImc: THandle; AIndex: LongWord; ABuf: Pointer;
  ALen: LongWord): LongInt; stdcall; external 'imm32.dll' name 'ImmGetCompositionStringW';
function ImmNotifyIME(AImc: THandle; AAction, AIndex, AValue: LongWord): LongBool; stdcall;
  external 'imm32.dll' name 'ImmNotifyIME';
function ImmSetCompositionWindow(AImc: THandle; AForm: Pointer): LongBool; stdcall;
  external 'imm32.dll' name 'ImmSetCompositionWindow';
function ImmSetCandidateWindow(AImc: THandle; AForm: Pointer): LongBool; stdcall;
  external 'imm32.dll' name 'ImmSetCandidateWindow';
{ The default window procedure, which LCL-win32 calls for a control of its own window class
  (CallDefaultWindowProc with no subclassed procedure). }
function DefWindowProcW(AWnd: THandle; AMsg: LongWord; AWParam, ALParam: PtrInt): PtrInt;
  stdcall; external 'user32.dll' name 'DefWindowProcW';
{$ENDIF}

{$IFDEF MSWINDOWS}
const
  MOVEFILE_REPLACE_EXISTING = 1;
  MOVEFILE_WRITE_THROUGH = 8;

// kernel32 itself: the Windows unit's RECT type would hide Types.Rect in this unit
function MoveFileExW(AExisting, ANew: PWideChar; AFlags: DWord): LongBool; stdcall;
  external 'kernel32' name 'MoveFileExW';
{$ENDIF}

{ ---- TTyRichQueuedCall ---- }

constructor TTyRichQueuedCall.Create(AOwner: TTyCustomRichEdit);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TTyRichQueuedCall.Fire(AData: PtrInt);
begin
  FQueued := False;
  FOwner.CallFired(Self);
end;

function TyRichTurnDriverFor(APlatform: TLCLPlatform): TTyRichTurnDriver;
begin
  if APlatform in [lpWin32, lpGtk2, lpGtk3, lpQt5, lpQt6] then
    Result := rtdIdle
  else
    Result := rtdTimer;
end;

function FloorDiv(A: Int64; B: Integer): Int64;
begin
  Result := A div B;
  if (A mod B <> 0) and (A < 0) then Dec(Result);
end;

function CeilDiv(A: Int64; B: Integer): Int64;
begin
  Result := -FloorDiv(-A, B);
end;

{ ---- lines ---- }

constructor TTyRichEditLines.Create(AOwner: TTyCustomRichEdit);
begin
  inherited Create;
  FOwner := AOwner;
end;

destructor TTyRichEditLines.Destroy;
begin
  FBatch.Free;
  FBatchLoad.Free;
  inherited Destroy;
end;

{ A line changed after a load put off to the update's end would be changed in the content the
  load is about to replace: refused rather than lost. }
procedure TTyRichEditLines.CheckNoLoad;
begin
  if (FBatchLoad <> nil) or FBatchLoadFile then
    raise ETyRichEdit.Create('Lines: a load inside BeginUpdate waits for EndUpdate');
end;

procedure TTyRichEditLines.Run(ACmd: TTyRichCommand);
var
  state: Int64;
begin
  state := FOwner.FDoc.ContentState;
  if not FOwner.FDoc.Execute(ACmd) then
    raise ETyRichEdit.Create(rsRichEditCannotChange);
  // inside an update of the document the selection moves with the line as it does outside
  if not FNoFollow then FOwner.FollowBlockWrite(ACmd, state);
  FOwner.FLinesStored := True;
end;

{ Paragraph AIndex's text S without the characters of its field marks (TTyRichFieldMark): the
  text a reader of Lines and Text sees. }
function WithoutFieldMarks(ADoc: TTyRichDocument; AIndex: Integer; const S: string): string;
var
  runs: TTyRunArray;
  i, r, b, n: Integer;
  ch: Int64;
  bt: Byte;
begin
  Result := '';
  runs := ADoc.RunsOf(AIndex);
  SetLength(Result, Length(S));
  n := 0;
  r := 0;
  ch := 0;
  i := 1;
  while i <= Length(S) do
  begin
    bt := Byte(S[i]);
    if bt < $C0 then b := 1 else if bt < $E0 then b := 2 else if bt < $F0 then b := 3 else b := 4;
    if i + b - 1 > Length(S) then b := Length(S) - i + 1;
    while (r < High(runs)) and (runs[r + 1].Start <= ch) do Inc(r);
    if not ((runs[r].Start = ch) and (runs[r].Obj is TTyRichFieldMark)) then
    begin
      Move(S[i], Result[n + 1], b);
      Inc(n, b);
    end;
    Inc(i, b);
    Inc(ch);
  end;
  SetLength(Result, n);
end;

function TTyRichEditLines.GetCount: Integer;
var
  t: TTyRichText;
begin
  if FBatch <> nil then Exit(FBatch.Count);
  t := FOwner.FDoc.Text;
  Result := t.ParaCount;
  if (Result = 1) and (t.Length = 0) then Result := Ord(FEmptyLine);
end;

function TTyRichEditLines.Get(Index: Integer): string;
var
  t: TTyRichText;
begin
  if FBatch <> nil then Exit(FBatch[Index]);
  if (Index < 0) or (Index >= GetCount) then Error(SListIndexError, Index);
  t := FOwner.FDoc.Text;
  Result := t.GetText(t.ParaStart(Index), t.ParaLength(Index));
  // a field's marks are no characters of the text (another object is its U+FFFC)
  if Pos(TyRichObjectChar, Result) > 0 then Result := WithoutFieldMarks(FOwner.FDoc, Index, Result);
end;

procedure TTyRichEditLines.Put(Index: Integer; const S: string);
var
  t: TTyRichText;
  d: TTyRichDocument;
  start, len, total: TTyRichPos;
  state: Int64;
  c: TTyRichChange;
begin
  if FBatch <> nil then
  begin
    FBatch[Index] := S;
    Exit;
  end;
  CheckNoLoad;
  if (Index < 0) or (Index >= GetCount) then Error(SListIndexError, Index);
  d := FOwner.FDoc;
  t := d.Text;
  start := t.ParaStart(Index);
  len := t.ParaLength(Index);
  { Never half done: what could refuse is asked before anything
    changes - the row the line is in - and the insert goes first, behind the old text in the
    format it would have got at the line's start, so that one the engine refuses (a text that
    ends inside a UTF-8 sequence) leaves the line, the history and OnChange as they were. }
  if not d.CanChange(start, len) or not d.CanChange(start + len, 0) then
    raise ETyRichEdit.Create(rsRichEditCannotChange);
  state := d.ContentState;
  total := t.Length;
  FNoFollow := True;
  d.BeginUpdate;
  try
    if S <> '' then
      Run(TTyRichInsertText.Create(start + len, S, d.TypingFormatAt(start), False));
    if len > 0 then Run(TTyRichDelete.Create(start, len));
  finally
    FNoFollow := False;
    d.EndUpdate;
  end;
  { Inside an outer update (BeginEdit, Lines.BeginUpdate) the selection follows the line's
    one change, as this update's one report moves it outside one. }
  if d.ContentState <> state then
  begin
    c := Default(TTyRichChange);
    c.Pos := start;
    c.OldLen := len;
    c.NewLen := len + d.Text.Length - total;
    c.Kinds := [rckText];
    FOwner.FollowBlockChange(c);
  end;
end;

procedure TTyRichEditLines.Insert(Index: Integer; const S: string);
var
  t: TTyRichText;
  n: Integer;
begin
  if FBatch <> nil then
  begin
    FBatch.Insert(Index, S);
    Exit;
  end;
  CheckNoLoad;
  n := GetCount;
  if (Index < 0) or (Index > n) then Error(SListIndexError, Index);
  t := FOwner.FDoc.Text;
  if n = 0 then
  begin
    // an empty document: its one paragraph becomes the line
    if S <> '' then Run(TTyRichInsertText.Create(0, S, TyRichInheritFormat, False));
    FEmptyLine := S = '';
    FOwner.FLinesStored := True;
  end
  else if Index = n then
    Run(TTyRichInsertText.Create(t.Length, #10 + S, TyRichInheritFormat, False))
  else
    Run(TTyRichInsertText.Create(t.ParaStart(Index), S + #10, TyRichInheritFormat, False));
end;

procedure TTyRichEditLines.Delete(Index: Integer);
var
  t: TTyRichText;
  n: Integer;
  start: TTyRichPos;
begin
  if FBatch <> nil then
  begin
    FBatch.Delete(Index);
    Exit;
  end;
  CheckNoLoad;
  n := GetCount;
  if (Index < 0) or (Index >= n) then Error(SListIndexError, Index);
  t := FOwner.FDoc.Text;
  if n = 1 then
  begin
    if t.Length > 0 then Run(TTyRichDelete.Create(0, t.Length));
    FEmptyLine := False;
    FOwner.FLinesStored := True;
  end
  else
  begin
    if Index = n - 1 then
    begin
      // the last line goes with the separator before it
      start := t.ParaStart(Index) - 1;
      Run(TTyRichDelete.Create(start, t.Length - start));
    end
    else
    begin
      start := t.ParaStart(Index);
      Run(TTyRichDelete.Create(start, t.ParaStart(Index + 1) - start));
    end;
    // a line is left: if it is an empty one, it is still a line
    FEmptyLine := True;
  end;
end;

procedure TTyRichEditLines.Clear;
begin
  if FUpdating then
  begin
    // a replacement: a load put off before it is replaced too
    FreeAndNil(FBatchLoad);
    FBatchLoadFile := False;
    if FBatch = nil then FBatch := TStringList.Create else FBatch.Clear;
    Exit;
  end;
  FOwner.SetPlainText('');
end;

procedure TTyRichEditLines.SetTextStr(const Value: string);
begin
  { Inside BeginUpdate .. EndUpdate (what LoadFromStream and LoadFromFile do around it) the
    document refuses a replacement: the text is gathered and becomes the content once, at
    EndUpdate. }
  if FUpdating and (FBatch = nil) then FBatch := TStringList.Create;
  if FBatch <> nil then
  begin
    FreeAndNil(FBatchLoad);
    FBatchLoadFile := False;
    FBatch.Text := Value;
    Exit;
  end;
  FOwner.SetPlainText(Value);
end;

procedure TTyRichEditLines.SetUpdateState(Updating: Boolean);
var
  s: string;
  ld: TMemoryStream;
var
  life: TTyRichLife;
begin
  { A handler of a find's or a replace's events may free the control in here: then this
    returns, touching nothing of it (inside another call of the control, that one does). }
  FOwner.LifeEnter(life);
  try
    try
      FUpdating := Updating;
      if Updating then
      begin
        // the commands of a batch (AddStrings) are one undo step
        FOwner.FDoc.BeginUpdate;
        Exit;
      end;
      // closed before a gathered replacement: the content is not replaced inside an update
      FOwner.FDoc.EndUpdate;
      if FBatchLoadFile then
      begin
        // the file is read now, as a load outside an update reads it (one gone by now raises)
        s := FBatchFile;
        FBatchLoadFile := False;
        FBatchFile := '';
        FOwner.LoadFromFile(s);
      end
      else if FBatchLoad <> nil then
      begin
        ld := FBatchLoad;
        FBatchLoad := nil;
        try
          ld.Position := 0;
          FOwner.LoadFromStream(ld);
          if FBatchFile <> '' then FOwner.FSourceFile := FBatchFile;
        finally
          ld.Free;
        end;
      end
      else if FBatch <> nil then
      begin
        s := FBatch.Text;
        FreeAndNil(FBatch);
        FOwner.SetPlainText(s);
      end;
    except
      on ETyRichGone do if TyRichGonePasses(life) then raise;
    end;
  finally
    if not life.Gone then FOwner.LifeLeave(life);
  end;
end;

{ As Delphi's TRichEdit.Lines: the control's load and save (see the declaration). Inside the
  lines' update the document takes no new content: it is loaded by the control at the
  update's end, as the file says. A FILE is only named here and read then, lazily as
  any load of the control (no copy of a 100 MB file held through the update; one gone
  by then raises at EndUpdate, as LoadFromFile would). A STREAM is read at once (below): it
  may not live until the update ends. }
procedure TTyRichEditLines.LoadFromFile(const FileName: string);
begin
  if not FUpdating then
  begin
    FOwner.LoadFromFile(FileName);
    Exit;
  end;
  // the latest replacement wins: a gathered text or an earlier load goes
  FreeAndNil(FBatch);
  FreeAndNil(FBatchLoad);
  FBatchFile := ExpandFileName(FileName);
  FBatchLoadFile := True;
end;

procedure TTyRichEditLines.LoadFromStream(Stream: TStream);
var
  ms: TMemoryStream;
begin
  if not FUpdating then
  begin
    FOwner.LoadFromStream(Stream);
    Exit;
  end;
  ms := TMemoryStream.Create;
  try
    // (CopyFrom with 0 would copy the whole stream from its start)
    if Stream.Size > Stream.Position then ms.CopyFrom(Stream, Stream.Size - Stream.Position);
  except
    ms.Free;
    raise;
  end;
  // the latest replacement wins: a gathered text or an earlier load goes
  FreeAndNil(FBatch);
  FBatchLoad.Free;
  FBatchLoad := ms;
  FBatchFile := '';
  FBatchLoadFile := False;
end;

procedure TTyRichEditLines.SaveToFile(const FileName: string);
begin
  if FUpdating then inherited SaveToFile(FileName) else FOwner.SaveToFile(FileName);
end;

procedure TTyRichEditLines.SaveToStream(Stream: TStream);
begin
  if FUpdating then inherited SaveToStream(Stream) else FOwner.SaveToStream(Stream);
end;

{ ---- the format façades' objects ----

  They hold the control and nothing else: a read asks it, a write is its door's (RunApiEdit). }

type
  TTyRichSelAttrs = class(TTyRichTextAttributes)
  protected
    FOwner: TTyCustomRichEdit;
    function GetFormat: TTyCharFormat; override;
    function GetRawFormat: TTyCharFormat; override;
    function GetConsistent: TTyCharFormatMask; override;
    procedure SetFormat(AMask: TTyCharFormatMask; const AValue: TTyCharFormat); override;
    function GetPPI: Integer; override;
  public
    constructor Create(AOwner: TTyCustomRichEdit);
  end;

  TTyRichDefAttrs = class(TTyRichSelAttrs)
  protected
    function GetFormat: TTyCharFormat; override;
    function GetRawFormat: TTyCharFormat; override;
    function IsBase: Boolean; override;
    function AssignMask: TTyCharFormatMask; override;
    function GetConsistent: TTyCharFormatMask; override;
    procedure SetFormat(AMask: TTyCharFormatMask; const AValue: TTyCharFormat); override;
  end;

  TTyRichParaAttrs = class(TTyRichParaAttributes)
  protected
    FOwner: TTyCustomRichEdit;
    function GetFormat: TTyParaFormat; override;
    function GetConsistentPara: TTyRichConsistentParaAttributes; override;
    procedure SetFormat(AMask: TTyParaFormatMask; const AValue: TTyParaFormat); override;
  public
    constructor Create(AOwner: TTyCustomRichEdit);
  end;

const
  CAllCharFields = CTyFontMask + [cffHighlight, cffVertAlign];

constructor TTyRichSelAttrs.Create(AOwner: TTyCustomRichEdit);
begin
  inherited Create;
  FOwner := AOwner;
end;

function TTyRichSelAttrs.GetFormat: TTyCharFormat;
begin
  // the first character a write formats, or what the next typed text gets (a pending format)
  Result := FOwner.ResolvedFormat(FOwner.FDoc.Formats.CharFormat(FOwner.SelFormatId));
end;

function TTyRichSelAttrs.GetRawFormat: TTyCharFormat;
begin
  Result := FOwner.FDoc.Formats.CharFormat(FOwner.SelFormatId);
end;

function TTyRichSelAttrs.GetConsistent: TTyCharFormatMask;
begin
  if not FOwner.HasSelection then Exit(CAllCharFields);
  Result := FOwner.RangeConsistency(FOwner.GetSelStart, FOwner.GetSelLength);
end;

procedure TTyRichSelAttrs.SetFormat(AMask: TTyCharFormatMask; const AValue: TTyCharFormat);
begin
  // the selection as it is once a composition went in
  FOwner.EndCompositionForUser;
  FOwner.ApiCharFormat(FOwner.GetSelStart, FOwner.GetSelLength, AMask, AValue);
end;

function TTyRichSelAttrs.GetPPI: Integer;
begin
  Result := FOwner.Font.PixelsPerInch;
  if Result <= 0 then Result := 96;
end;

function TTyRichDefAttrs.GetFormat: TTyCharFormat;
begin
  Result := FOwner.BaseCharFormat;
  { The automatic colour reads clDefault here too, so that it equals what automatic
    text reads through SelAttributes; a colour the application gave the base is its own. }
  Result.Color := TyRichTextColorIn(FOwner.Font.Color);
end;

function TTyRichDefAttrs.GetRawFormat: TTyCharFormat;
begin
  Result := GetFormat;
end;

function TTyRichDefAttrs.IsBase: Boolean;
begin
  Result := True;
end;

function TTyRichDefAttrs.AssignMask: TTyCharFormatMask;
begin
  // the base holds neither: an Assign leaves them out, a direct write raises
  Result := CTyFontMask;
end;

function TTyRichDefAttrs.GetConsistent: TTyCharFormatMask;
begin
  // as Delphi's DefAttributes: no selection, nothing to be consistent over
  Result := [];
end;

procedure TTyRichDefAttrs.SetFormat(AMask: TTyCharFormatMask; const AValue: TTyCharFormat);
begin
  FOwner.SetBaseCharFormat(AMask, AValue);
end;

constructor TTyRichParaAttrs.Create(AOwner: TTyCustomRichEdit);
begin
  inherited Create;
  FOwner := AOwner;
end;

function TTyRichParaAttrs.GetFormat: TTyParaFormat;
begin
  if not FOwner.ParaFormatAt(FOwner.GetSelStart, Result) then Result := TyDefaultParaFormat;
end;

function TTyRichParaAttrs.GetConsistentPara: TTyRichConsistentParaAttributes;
begin
  Result := FOwner.ParaConsistency(FOwner.GetSelStart, FOwner.GetSelLength);
end;

procedure TTyRichParaAttrs.SetFormat(AMask: TTyParaFormatMask; const AValue: TTyParaFormat);
begin
  FOwner.EndCompositionForUser;
  FOwner.ApiParaFormat(FOwner.GetSelStart, FOwner.GetSelLength, AMask, AValue);
end;

{ ---- the control ---- }

constructor TTyCustomRichEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle - [csSetCaption];
  TabStop := True;
  FZoom := 100;
  FWrapMode := rwmWindow;
  FHandlePara := -1;
  FImeContextL := ISC_SHOWUIALL;
  FReadOnly := False;
  FWantTabs := False;
  FTextEncoding := teAuto;
  FTextCodePage := 0;
  FScrollBarAutoHide := sbahDefault;
  FCaretWhenReadOnly := True;
  FFocusOnClick := True;
  FAllowSelection := True;
  FScrollBars := ssBoth;
  FAutoHeight := False;
  FReportedW := -1;
  FReportedH := -1;
  FSourceFormat := rfRtf;
  FFirstSliceBytes := CRtfFirstSliceBytes;
  FStepBytes := CRichLoadStepBytes;
  FSlice := CRichLoadMinStepBytes;
  FBarScale := 1;
  FScale := 1;
  FSurfScale := 1;
  FLayoutPPI := 0;
  FViewPPI := 0;
  FStepCall := TTyRichQueuedCall.Create(Self);
  FSelCall := TTyRichQueuedCall.Create(Self);
  FDoc := CreateDocument;
  FBkmIndex := TTyRichBookmarkList.Create(FDoc);
  FText := FDoc.Text;
  FDoc.OnChange := @DocChanged;
  FDoc.OnUpdatingEnd := @DocUpdatingEnded;
  FDoc.OnModifiedChange := @DocModifiedChanged;
  FSelAttributes := TTyRichSelAttrs.Create(Self);
  FDefAttributes := TTyRichDefAttrs.Create(Self);
  FParagraph := TTyRichParaAttrs.Create(Self);
  FPlainText := False;
  FLayouter := CreateLayouter;
  FLayouter.Document := FDoc;
  FLayouter.OnLinkField := @LayoutLinkField;
  FLayouter.OnSpanHeights := @LayoutSpanHeights;
  FLayouter.OnSpanDropped := @LayoutSpanDropped;
  FFollowBookmarkLinks := True;
  FObjPressAt := -1;
  // the layouter empties its caches when the list changes; the view must drop its blocks too
  FFallbackListChange := FLayouter.FallbackFonts.OnChange;
  FLayouter.FallbackFonts.OnChange := @FallbackListChanged;
  FLines := TTyRichEditLines.Create(Self);
  FCaretShown := True;
  FCopyWaitChars := CRichCopyWaitChars;
  FDragDropEditing := True;
  FAcceptDrops := True;
  FDropPos := -1;
  FConsBudgetWork := CRichConsistWork;
  FConsBudgetBytes := CRichConsistParseBytes;
  FFindSlice := CRichFindMinStepChars;
  FFindCall := TTyRichQueuedCall.Create(Self);
  FSizeCall := TTyRichQueuedCall.Create(Self);
  {$IFDEF LCLCocoa}
  { Before the handle: LCL-Cocoa asks for it (LM_IM_COMPOSITION) inside CreateHandle. It holds
    the control as an ITyImeEditable whose _AddRef does nothing (the memo's way). }
  FCocoaIme := TyCocoaNewImeHandler(Self);
  {$ENDIF}
  Cursor := crIBeam;
  AccessibleRole := larTextEditorMultiline;
  Width := 320;
  Height := 240;
end;

destructor TTyCustomRichEdit.Destroy;
var
  life: PTyRichLife;
begin
  // a handler of a find or a replace frees it: the frames below it touch nothing more of it
  life := FLife;
  while life <> nil do
  begin
    life^.Gone := True;
    life := life^.Next;
  end;
  FLife := nil;
  { A drag of the selection: its offer is the control's - another rich edit's session over it
    ends first. (A control whose drag feeds this one's session hears of this control's end
    through the free notification: Notification.) }
  if FDropOwn then
  begin
    EndPeer;
    FreeAndNil(FDropOffer);
  end;
  FDropOffer := nil;
  // the system's drop target lets go of the control (a drag over it finds nothing any more)
  RevokeDropRegistration;
  {$IFDEF LCLWin32}
  if FOleTarget <> nil then TyRichOleDetach(FOleTarget);
  FOleTarget := nil;
  {$ENDIF}
  { A composition ends first, while the window and the document are still there: dropped,
    and the input method told so (what it answers inside that finds none) - otherwise it
    stays open in the thread's input context for whatever gets the focus next. After this
    body LCL takes the focus away and destroys the window (TWinControl.Destroy), and its
    messages and CM_EXIT still come here, with the document freed: from here on csDestroying
    (set before this body) turns every entry they reach away at the door - the input
    method's messages, the focus messages, DoExit, the composition's methods and Cocoa's
    bridge; the timers, the queued calls and the idle handler are taken off below. }
  EndComposition(False);
  FCompPending := False;
  FCompBefore := False;
  if FAskTbl <> nil then FAskTbl.Release;
  FAskTbl := nil;
  FCocoaSession := False;
  FCocoaSwallow := False;
  TyImeUninstall(FImeHook);
  FreeAndNil(FCocoaIme);
  // nothing queued, registered or timed may come back into a freed control
  StopBackground;
  // a find or a replace in the background stops quietly (a replace keeps its one step)
  EndFind(rfsCancelled, False);
  if FSelCall <> nil then CancelCall(FSelCall);
  if FFindCall <> nil then CancelCall(FFindCall);
  if FSizeCall <> nil then CancelCall(FSizeCall);
  FreeAndNil(FTurnTimer);
  FreeAndNil(FBackstop);
  FreeAndNil(FStepCall);
  FreeAndNil(FSelCall);
  FreeAndNil(FFindCall);
  FreeAndNil(FSizeCall);
  FreeAndNil(FBlinkTimer);
  FreeAndNil(FDragTimer);
  FreeAndNil(FTextMenu);
  ReleaseBlocks;
  ClearPending;
  ClearFailed;
  FreeAndNil(FSurface);
  if FDoc <> nil then
  begin
    FDoc.OnChange := nil;
    FDoc.OnUpdatingEnd := nil;
    FDoc.OnModifiedChange := nil;
  end;
  FreeAndNil(FSelAttributes);
  FreeAndNil(FDefAttributes);
  FreeAndNil(FParagraph);
  if FLayouter <> nil then FLayouter.FallbackFonts.OnChange := FFallbackListChange;
  FreeAndNil(FLayouter);
  FreeAndNil(FBkmIndex);
  FreeAndNil(FDoc);
  FreeAndNil(FLines);
  FreeAndNil(FParaViewHandlers);
  inherited Destroy;
end;

function TTyCustomRichEdit.GetStyleTypeKey: string;
begin
  Result := 'TyRichEdit';
end;

function TTyCustomRichEdit.CreateDocument: TTyRichDocument;
begin
  Result := TTyRichDocument.Create;
end;

function TTyCustomRichEdit.CreateDevice: TTyRichTextDevice;
begin
  Result := TTyRichBgraDevice.Create;
end;

function TTyCustomRichEdit.CreateLayouter: TTyRichLayouter;
begin
  Result := TTyRichLayouter.Create(CreateDevice, True);
end;

function TTyCustomRichEdit.LayoutBlockAt(AIndex: Integer): TTyBlockLayout;
begin
  Result := FLayouter.LayoutBlock(FDoc, AIndex, FLayoutWidth, FLayoutPPI, FLayoutZoom);
end;

function TTyCustomRichEdit.ScrollBarLimit: Integer;
begin
  Result := CRichScrollBarRange;
end;

function TTyCustomRichEdit.ScrollBarFrameStyle: TTyStyleSet;
begin
  Result := CurrentStyle;
end;

function TTyCustomRichEdit.EmbedsScrollBar(ABar: TTyScrollBar): Boolean;
begin
  Result := (ABar <> nil) and ((ABar = FVBar) or (ABar = FHBar));
end;

{ ---- properties ---- }

function TTyCustomRichEdit.GetLines: TStrings;
begin
  Result := FLines;
end;

procedure TTyCustomRichEdit.SetLines(AValue: TStrings);
begin
  FLines.Assign(AValue);
end;

function TTyCustomRichEdit.IsLinesStored: Boolean;
begin
  // what was set as lines (in the designer, or by code), not a file loaded at run time
  Result := FLinesStored and (FLines.Count > 0);
end;

function TTyCustomRichEdit.GetModified: Boolean;
begin
  Result := FDoc.Modified;
end;

procedure TTyCustomRichEdit.SetModified(AValue: Boolean);
begin
  FDoc.Modified := AValue;
end;

function TTyCustomRichEdit.GetLoading: Boolean;
begin
  Result := FDoc.Loading;
end;

function TTyCustomRichEdit.GetIncomplete: Boolean;
begin
  Result := FDoc.Incomplete;
end;

function TTyCustomRichEdit.GetFallbackFonts: TStrings;
begin
  Result := FLayouter.FallbackFonts;
end;

function TTyCustomRichEdit.GetOnFallbackFont: TTyRichFallbackEvent;
begin
  Result := FLayouter.OnFallbackFont;
end;

procedure TTyCustomRichEdit.SetOnFallbackFont(AValue: TTyRichFallbackEvent);
var
  was: TTyRichFallbackEvent;
begin
  was := FLayouter.OnFallbackFont;
  FLayouter.OnFallbackFont := AValue;
  if (TMethod(was).Code <> TMethod(AValue).Code) or (TMethod(was).Data <> TMethod(AValue).Data) then
    LayoutParamsChanged;
end;

procedure TTyCustomRichEdit.FallbackListChanged(Sender: TObject);
begin
  if Assigned(FFallbackListChange) then FFallbackListChange(Sender);
  LayoutParamsChanged;
end;

{ The fonts a block is measured with changed (as a font change does): the blocks go, every
  height is an estimate again, the anchor stays, the text is drawn again. }
procedure TTyCustomRichEdit.LayoutParamsChanged;
begin
  CancelResize;
  if FLayoutPPI = 0 then Exit;
  FDoc.Text.UnmeasureAll;
  ReleaseBlocks;
  FWidestSeen := 0;
  InvalidateSurface;
  ViewMoved;
  MarkTextDirty;
end;

procedure TTyCustomRichEdit.SetZoom(AValue: Integer);
begin
  if AValue < CRichZoomMin then AValue := CRichZoomMin;
  if AValue > CRichZoomMax then AValue := CRichZoomMax;
  if AValue = FZoom then Exit;
  FZoom := AValue;
  // CheckLayoutParams sees the new zoom: every height an estimate again, the anchor kept
  ViewMoved;
  // a drop goes on: what is under the pointer at the new zoom
  DropFollowPointer;
  DoZoomChange;
end;

procedure TTyCustomRichEdit.SetWrapMode(AValue: TTyRichWrapMode);
begin
  if AValue = FWrapMode then Exit;
  FWrapMode := AValue;
  FScrollX := 0;
  FWidestSeen := 0;
  ViewMoved;
  DropFollowPointer;
end;

procedure TTyCustomRichEdit.SetReadOnly(AValue: Boolean);
begin
  if FReadOnly = AValue then Exit;
  FReadOnly := AValue;
  // the run of typing ends: what is typed after it being editable again is a step of its own
  EndTypingRun;
  // what is being composed cannot go in any more: it goes, and the input method drops it
  if AValue then EndComposition(False);
  // a viewer resizes nothing: a drag of a handle ends, and the handles go (or come back)
  if AValue then CancelResize;
  // nor drags its selection, nor takes a drop
  if AValue then
  begin
    CancelSelectionDrag;
    DropLeave;
  end;
  SyncObjectOverlay;
  { A focused control's input context was told at the window's activation whether the
    system's composition window is wanted (WMImeSetContext); no activation comes now, so it
    is told again: read-only, the system's window shows what is typed (the memo's way);
    editable, the composition is shown in the text. }
  if HasCaretFocus and not (csDestroying in ComponentState) then
    if ImeIsReadOnly then ImeSetContextDefault(1, FImeContextL)
    else ImeSetContextDefault(1, FImeContextL and not ISC_SHOWUICOMPOSITIONWINDOW);
  // a plain click on a link is its click now, or no more: the hand where the pointer is
  PointerKeysChanged(FPointerShift);
  ParagraphViewChanged;
end;

procedure TTyCustomRichEdit.SetScrollBarAutoHide(AValue: TTyScrollBarAutoHide);
begin
  if FScrollBarAutoHide = AValue then Exit;
  FScrollBarAutoHide := AValue;
  if FVBar <> nil then FVBar.AutoHide := AValue;
  if FHBar <> nil then FHBar.AutoHide := AValue;
end;

function TTyCustomRichEdit.GetVisibleBlock(AIndex: Integer): TTyRichViewBlock;
begin
  // inside the document's update there is none (VisibleBlockCount is 0)
  if not ViewBehind then Settle;
  if (AIndex < 0) or (AIndex >= FBlockCount) or ViewBehind then
    raise ETyRichEdit.CreateFmt('Visible block %d out of range', [AIndex]);
  Result := FBlocks[AIndex];
  // client pixels, rounded outward (the layout's own numbers are raster pixels)
  if FScale > 1 then
  begin
    Result.Top := FloorDiv(FBlocks[AIndex].Top, FScale);
    Result.Height := Integer(CeilDiv(FBlocks[AIndex].Top + FBlocks[AIndex].Height, FScale) -
      Result.Top);
  end;
end;

function TTyCustomRichEdit.GetTopOffset: Int64;
begin
  Result := FAnchorOffset div FScale;
end;

function TTyCustomRichEdit.GetScrollX: Integer;
begin
  Result := FScrollX div FScale;
end;

function TTyCustomRichEdit.GetHorizontalExtent: Integer;
begin
  Result := Integer(CeilDiv(FWidestSeen, FScale));
end;

function TTyCustomRichEdit.VisibleBlockCount: Integer;
begin
  if ViewBehind then Exit(0);
  Settle;
  Result := FBlockCount;
end;

procedure TTyCustomRichEdit.DoChange;

  procedure Fire;
  begin
    FOnChange(Self);
  end;

begin
  // a form file's Lines while streaming, the document going with the control: no event
  if [csLoading, csDestroying] * ComponentState <> [] then Exit;
  ParagraphViewChanged;
  if Assigned(FOnChange) then CallHandler(@Fire);
end;

{ A handler of the application's (OnChange, OnSelectionChange, OnEditRefused,
  OnModifiedChange) returned. If it freed the control and a frame of the control's own lies
  below (a drop, a paste, an edit's door), nothing of it may be touched any more: ETyRichGone
  unwinds to that frame. With no frame below the caller goes on. (No method: the control may
  be gone.) }
procedure HandlerReturned(const ALife: TTyRichLife);
begin
  { An application's handler (OnChange, OnSelectionChange, OnEditRefused, OnModifiedChange)
    returned. If it freed the control and the frame below it is one of the control's own with
    none of the application's code between (its depth), ETyRichGone unwinds to that frame,
    which stops there - so it never passes the application's code. Otherwise the call returns:
    a public method of the control the application called inside a handler stops in its own
    frame, and the control's frames further down find the control gone when that call returns.
    (No method: the control may be gone.) }
  if ALife.Gone and (ALife.Next <> nil) and not ALife.Next^.Handler and
    (ALife.Next^.Depth = ALife.Depth) then
    raise ETyRichGone.Create('The control was freed by its handler');
end;

threadvar
  // how many application handlers run now, of any rich edit (CallHandler)
  GRichAppDepth: Integer;

procedure TTyCustomRichEdit.Guard(var ALife: TTyRichLife; AWork: TTyRichGuarded);
begin
  LifeEnter(ALife);
  try
    try
      AWork();
    except
      on ETyRichGone do if TyRichGonePasses(ALife) then raise;
    end;
  finally
    if not ALife.Gone then LifeLeave(ALife);
  end;
end;

procedure TTyCustomRichEdit.CallHandler(AFire: TTyRichGuarded);
var
  life: TTyRichLife;
begin
  LifeEnter(life, True);
  Inc(GRichAppDepth);
  try
    AFire();
  finally
    Dec(GRichAppDepth);
    if not life.Gone then LifeLeave(life);
  end;
  HandlerReturned(life);
end;

procedure TTyCustomRichEdit.DoZoomChange;
begin
  if Assigned(FOnZoomChange) then FOnZoomChange(Self);
end;

{ ---- the caret and the selection ----

  The caret is a document position and an affinity, the selection the stretch from the anchor
  to it. Neither is on the kept surface: the selection is painted by the blocks (PaintBlock
  gives each its part), so a change of it marks only the bands of the lines whose selected
  part changed (InvalidateContent's way); the caret is drawn over the blit by Paint and blinks
  by blitting its rectangle again (InvalidateArea alone), so a blink or a click that only
  places the caret draws nothing on the surface. Steps go through the layout (a cluster, an
  object, an escaped byte's pair, never a cell merged away); Up and Down are geometry: the
  caret's rectangle, then the hit test at the kept x on the line above or below. }

type
  TTyRichCodes = array of Cardinal;

{ The characters of UTF-8 text as the text storage counts them: a byte that starts no valid
  sequence (an escaped byte's two, a stray byte) is one character, read U+FFFD. }
function RichCodes(const S: RawByteString): TTyRichCodes;
var
  i, n, len: Integer;
  b: Byte;
  c: Cardinal;
  p: PByte;
begin
  Result := nil;
  SetLength(Result, Length(S));
  n := 0;
  i := 1;
  while i <= Length(S) do
  begin
    p := PByte(@S[i]);
    b := p^;
    c := $FFFD;
    len := 1;
    if b < $80 then
      c := b
    else if (b >= $C2) and (b <= $DF) then
    begin
      if (i + 1 <= Length(S)) and (p[1] and $C0 = $80) then
      begin
        c := (Cardinal(b and $1F) shl 6) or (p[1] and $3F);
        len := 2;
      end;
    end
    else if (b >= $E0) and (b <= $EF) then
    begin
      if (i + 2 <= Length(S)) and (p[1] and $C0 = $80) and (p[2] and $C0 = $80) then
      begin
        c := (Cardinal(b and $0F) shl 12) or (Cardinal(p[1] and $3F) shl 6) or (p[2] and $3F);
        if (c >= $800) and ((c < $D800) or (c > $DFFF)) then len := 3 else c := $FFFD;
      end;
    end
    else if (b >= $F0) and (b <= $F4) then
      if (i + 3 <= Length(S)) and (p[1] and $C0 = $80) and (p[2] and $C0 = $80) and
        (p[3] and $C0 = $80) then
      begin
        c := (Cardinal(b and $07) shl 18) or (Cardinal(p[1] and $3F) shl 12) or
          (Cardinal(p[2] and $3F) shl 6) or (p[3] and $3F);
        if (c >= $10000) and (c <= $10FFFF) then len := 4 else c := $FFFD;
      end;
    Result[n] := c;
    Inc(n);
    Inc(i, len);
  end;
  SetLength(Result, n);
end;

{ A character's class for words (a double click, Ctrl+Left / Right): the memo's rule
  (TTyCustomMemo.IsWordCodepoint in tyControls.Memo.pas, itself TTyEdit's) - white space (a
  space, a tab, U+00A0) and ASCII punctuation are no word (0), every other character is (1):
  letters, digits, ideographs, marks, so a run of them, Chinese and Latin alike, is one word as
  in the memo. Added for rich text: an object (U+FFFC) is a word by itself (2), a line break
  inside a paragraph (U+000B) is no word. }
function WordClass(C: Cardinal): Integer;
begin
  // one rule, the find's whole word too (the document's: tyControls.RichEdit.Model)
  Result := TyRichWordClass(C);
end;

{ A place a change left (the document's update, an edit from code) is put where the caret
  rests before it is read - not only by the next paint or key. }
procedure TTyCustomRichEdit.SettlePlaces;
begin
  if FSnapPending and not ViewBehind and not (csDestroying in ComponentState) then Settle;
end;

function TTyCustomRichEdit.GetSelStart: TTyRichPos;
begin
  Result := Math.Min(FCaret, FSelAnchor);
end;

function TTyCustomRichEdit.GetSelLength: TTyRichPos;
begin
  Result := Abs(FCaret - FSelAnchor);
end;

// (the properties' reads: settled first; the control's own reads are not - they run where it
// settles itself, at a key's or a paint's start)
function TTyCustomRichEdit.GetPlacedSelStart: TTyRichPos;
begin
  SettlePlaces;
  Result := Math.Min(FCaret, FSelAnchor);
end;

function TTyCustomRichEdit.GetPlacedSelLength: TTyRichPos;
begin
  SettlePlaces;
  Result := Abs(FCaret - FSelAnchor);
end;

function TTyCustomRichEdit.GetCaretIndex: TTyRichPos;
begin
  SettlePlaces;
  Result := FCaret;
end;

function TTyCustomRichEdit.HasSelection: Boolean;
begin
  Result := FCaret <> FSelAnchor;
end;

{ Inside the document's update (ViewBehind) the setters ask the layout nothing (SnapPos would
  look a block up by a paragraph index the layouter has not heard of): Select keeps the
  positions, the update's end puts them on caret places. }
procedure TTyCustomRichEdit.SetSelStart(AValue: TTyRichPos);
begin
  if not ViewBehind then AValue := SnapPos(AValue);
  Select(AValue, AValue, False);
  Moved(False);
end;

procedure TTyCustomRichEdit.SetSelLength(AValue: TTyRichPos);
var
  s, len: TTyRichPos;
begin
  s := GetSelStart;
  // clamped before the sum: SelLength := High(Int64) means "to the end", not an overflow
  len := FDoc.Text.Length;
  if AValue > len - s then AValue := len - s
  else if AValue < -s then AValue := -s;
  if ViewBehind then
    Select(s, s + AValue, False)
  else
    Select(s, SnapPos(s + AValue), False);
  Moved(False);
end;

procedure TTyCustomRichEdit.SetCaretIndex(AValue: TTyRichPos);
begin
  SetSelStart(AValue);
end;

function TTyCustomRichEdit.GetCaretPos: TPoint;
var
  t: TTyRichText;
  e: TTyRichPos;
  p: Integer;
begin
  t := FDoc.Text;
  // the selection's end, as Delphi's rich edit reads it (cpMax)
  e := Math.Min(Math.Max(FCaret, FSelAnchor), t.Length);
  p := t.ParaOfPos(e);
  Result.Y := p;
  Result.X := Integer(Math.Min(e - t.ParaStart(p), Int64(High(Integer))));
end;

procedure TTyCustomRichEdit.SetCaretPos(const AValue: TPoint);
var
  t: TTyRichText;
  p: Integer;
  x: TTyRichPos;
begin
  t := FDoc.Text;
  p := Math.Max(0, Math.Min(AValue.Y, t.ParaCount - 1));
  x := Math.Max(Int64(0), Math.Min(Int64(AValue.X), t.ParaLength(p)));
  SetSelStart(t.ParaStart(p) + x);
end;

function TTyCustomRichEdit.GetAllText: TCaption;
var
  n: Integer;
begin
  Result := '';
  // (none yet while the control is made, none any more while it goes)
  if FLines = nil then Exit;
  // Lines.Text without the break TStrings adds after the last line
  Result := FLines.Text;
  n := Length(FLines.LineBreak);
  if (n > 0) and (Length(Result) >= n) and
    (Copy(Result, Length(Result) - n + 1, n) = FLines.LineBreak) then
    SetLength(Result, Length(Result) - n);
end;

procedure TTyCustomRichEdit.SetAllText(const AValue: TCaption);
begin
  { As Lines.Text := (a gathered replacement inside Lines.BeginUpdate too); one break more,
    since Lines.Text takes a break at the end as closing the last line and Text as a line
    of its own. }
  if AValue = '' then FLines.Text := '' else FLines.Text := AValue + FLines.LineBreak;
end;

procedure TTyCustomRichEdit.Clear;
begin
  FLines.Clear;
end;

function TTyCustomRichEdit.RealGetText: TCaption;
begin
  Result := GetAllText;
end;

procedure TTyCustomRichEdit.RealSetText(const AValue: TCaption);
begin
  if FInActionChange then Exit;
  SetAllText(AValue);
end;

procedure TTyCustomRichEdit.ActionChange(Sender: TObject; CheckDefaults: Boolean);
begin
  FInActionChange := True;
  try
    inherited ActionChange(Sender, CheckDefaults);
  finally
    FInActionChange := False;
  end;
end;

procedure TTyCustomRichEdit.SelectAll;
begin
  { The document's end, as the text has it: no layout, no walk. During a lazy load that is
    what is indexed so far, and the selection stays there when more comes (slices move
    nothing): a Select All after the load takes the rest. }
  Select(0, FDoc.Text.Length, False);
  FWishValid := False;
  CaretMoved;
  DoSelectionChange;
end;

procedure TTyCustomRichEdit.CollapseSelection;
begin
  Select(FCaret, FCaret, FCaretAtEnd);
  CaretMoved;
  DoSelectionChange;
end;

procedure TTyCustomRichEdit.ClearSelection;
begin
  // a user's action: the Delete key's, with its every check
  EndCompositionForUser;
  if FReadOnly or not IsEnabled or ViewBehind or not HasSelection then Exit;
  DeleteKey(True, False);
end;

procedure TTyCustomRichEdit.DoSelectionChange;

  procedure Fire;
  begin
    FOnSelectionChange(Self);
  end;

begin
  // inside BeginEdit .. EndEdit: reported once, at EndEdit
  if FEditBlock > 0 then Exit;
  if (FCaret = FReportedCaret) and (FSelAnchor = FReportedAnchor) then Exit;
  FReportedCaret := FCaret;
  FReportedAnchor := FSelAnchor;
  ParagraphViewChanged;
  if [csLoading, csDestroying] * ComponentState <> [] then Exit;
  if Assigned(FOnSelectionChange) then CallHandler(@Fire);
end;

procedure TTyCustomRichEdit.EnsureParams;
begin
  if FLayoutPPI = 0 then CheckLayoutParams(ViewPPI);
end;

function TTyCustomRichEdit.HeldBlockOf(APos: TTyRichPos): Integer;
var
  p, k: Integer;
  t: TTyRichText;
begin
  Result := -1;
  if FBlockCount = 0 then Exit;
  t := FDoc.Text;
  if APos < 0 then APos := 0;
  if APos > t.Length then APos := t.Length;
  p := t.ParaOfPos(APos);
  for k := 0 to FBlockCount - 1 do
    if (p >= FBlocks[k].FirstPara) and (p <= FBlocks[k].LastPara) then Exit(k);
end;

function TTyCustomRichEdit.CaretRaster(APos: TTyRichPos; AAtEnd: Boolean; out ARect: TRect): Boolean;
var
  k: Integer;
  r: TRect;

  function Fit(V: Int64): Integer;
  begin
    // a held block is within a few screens of the view; a huge one may still reach far
    Result := Integer(Math.Max(Int64(-MaxInt div 4), Math.Min(V, Int64(MaxInt div 4))));
  end;

begin
  ARect := Rect(0, 0, 0, 0);
  k := HeldBlockOf(APos);
  if k < 0 then Exit(False);
  if APos < 0 then APos := 0;
  r := FBlocks[k].Layout.CaretRect(APos - FDoc.Text.ParaStart(FBlocks[k].FirstPara), AAtEnd);
  ARect := Rect(r.Left - FScrollX, Fit(FBlocks[k].Top + r.Top), r.Right - FScrollX,
    Fit(FBlocks[k].Top + r.Bottom));
  Result := True;
end;

function TTyCustomRichEdit.HitRaster(AX, AY: Int64; out AAtEnd: Boolean): TTyRichPos;
var
  k: Integer;
  by: Int64;
begin
  AAtEnd := False;
  Result := -1;
  if FBlockCount = 0 then Exit;
  k := 0;
  while (k < FBlockCount - 1) and (AY >= FBlocks[k].Top + FBlocks[k].Height) do Inc(k);
  // inside the block (or just outside it): within its height, an Integer
  by := Math.Max(Int64(-1), Math.Min(AY - FBlocks[k].Top, Int64(FBlocks[k].Height)));
  AX := Math.Max(Int64(-MaxInt div 2), Math.Min(AX, Int64(MaxInt div 2)));
  Result := FDoc.Text.ParaStart(FBlocks[k].FirstPara) +
    FBlocks[k].Layout.PosAtPoint(Integer(AX), Integer(by), AAtEnd);
end;

function TTyCustomRichEdit.CoveredPara(APara: Integer): Boolean;
var
  c, p: TTyRichCell;
  f, l: Integer;
begin
  Result := False;
  if (APara < 0) or (APara >= FDoc.Text.ParaCount) then Exit;
  FDoc.BeginRead;
  try
    c := FDoc.CellAt(APara);
    if (c = nil) or (TyRichCellVMerge(c.Row, c.Index) <> rcmContinue) then Exit;
    // (a row that holds a nested table is its file's bytes only: as it is shown)
    if c.Row.HoldsNestedTable then Exit;
    // (empty: one paragraph, no character)
    if not TyRichCellParasOf(FDoc, APara, f, l) or (f <> l) or (FDoc.Text.ParaLength(f) <> 0) then Exit;
    // (a mark that continues nothing - the table's first row - is an ordinary cell)
    if not TyRichRowParas(FDoc, APara, f, l) or (f = 0) then Exit;
    p := FDoc.CellAt(f - 1);
    { (and only the cell above at its column, of its width, as the grid reads it: a mark under
      a cell of another extent is a cell of its own) }
    Result := (p <> nil) and (p.Table = c.Table) and TyRichCellContinuesAbove(p.Row, c.Row, c.Index);
  finally
    FDoc.EndRead;
  end;
end;

function TTyCustomRichEdit.SpanOwnerPos(APos: TTyRichPos): TTyRichPos;
var
  t: TTyRichText;
  k, f, l, pf, pl, o, i, fo, lo, n: Integer;
  c, p: TTyRichCell;
begin
  Result := APos;
  t := FDoc.Text;
  if (APos < 0) or (APos > t.Length) then Exit;
  k := t.ParaOfPos(APos);
  if not CoveredPara(k) then Exit;
  FDoc.BeginRead;
  try
    n := 0;
    while CoveredPara(k) and (n < CRichMaxTableRows) do
    begin
      Inc(n);
      c := FDoc.CellAt(k);
      if not TyRichRowParas(FDoc, k, f, l) then Break;
      p := FDoc.CellAt(f - 1);
      if not TyRichRowParas(FDoc, f - 1, pf, pl) then Break;
      o := TyRichFacingCell(c.Row.CellEdges, c.Row.Format.Row.LeftTwips, c.Index,
        p.Row.CellEdges, p.Row.Format.Row.LeftTwips);
      if o < 0 then Break;
      fo := -1;
      lo := -1;
      for i := pf to pl do
        if FDoc.CellAt(i).Index = o then
        begin
          if fo < 0 then fo := i;
          lo := i;
        end;
      if lo < 0 then Break;
      k := lo;
    end;
    Result := t.ParaStart(k) + t.ParaLength(k);
  finally
    FDoc.EndRead;
  end;
end;

function TTyCustomRichEdit.PastCovered(APos: TTyRichPos; AForward: Boolean): TTyRichPos;
var
  t: TTyRichText;
  k, f, l, n: Integer;
begin
  Result := APos;
  t := FDoc.Text;
  n := 0;
  while (Result >= 0) and (Result <= t.Length) and (n < CRichMaxTableRows) do
  begin
    k := t.ParaOfPos(Result);
    if not CoveredPara(k) or not TyRichCellParasOf(FDoc, k, f, l) then Exit;
    Inc(n);
    if AForward then
    begin
      if l + 1 >= t.ParaCount then Exit;
      Result := t.ParaStart(l + 1);
    end
    else
    begin
      if f = 0 then Exit;
      Result := t.ParaStart(f) - 1;
    end;
  end;
end;

function TTyCustomRichEdit.HitNeighbour(AK: Integer; ADown: Boolean; AX: Integer;
  out AAtEnd: Boolean): TTyRichPos;
var
  t: TTyRichText;
  b: TTyBlockLayout;
  p, y: Integer;
begin
  Result := -1;
  AAtEnd := False;
  t := FDoc.Text;
  if ADown then p := FBlocks[AK].LastPara + 1 else p := FBlocks[AK].FirstPara - 1;
  if (p < 0) or (p >= t.ParaCount) then Exit;
  EnsureParams;
  FDoc.BeginRead;
  try
    b := LayoutBlockAt(p);
    try
      if ADown then y := 0 else y := Math.Max(0, b.Height - 1);
      Result := t.ParaStart(b.FirstPara) + b.PosAtPoint(AX, y, AAtEnd);
    finally
      b.Release;
    end;
  finally
    FDoc.EndRead;
  end;
end;

function TTyCustomRichEdit.LineFrom(const AR: TRect; ADown: Boolean; out AAtEnd: Boolean): TTyRichPos;
var
  k: Integer;
  y: Int64;
  r2: TRect;

  function Went(AQ: TTyRichPos): Boolean;
  begin
    Result := (AQ >= 0) and CaretRaster(AQ, AAtEnd, r2) and
      ((ADown and (r2.Top > AR.Top)) or (not ADown and (r2.Top < AR.Top)));
  end;

begin
  k := HeldBlockOf(FCaret);
  // the line below (above) the caret's, at the kept x: the cell under it in a row
  if ADown then y := AR.Bottom else y := AR.Top - 1;
  Result := HitRaster(FWishX, y, AAtEnd);
  if Went(Result) then Exit;
  Result := -1;
  if k < 0 then Exit;
  { Still the same line: a cell's last (first) line in a row taller than it, or the
    document's end. The block after (before) the caret's, at that x. A block reaching two
    views below the view's top (a tall picture, a long cell beside a short one) leaves the
    one after it unheld: that one is laid out here, and the move scrolls to it. }
  if (ADown and (k < FBlockCount - 1)) or (not ADown and (k > 0)) then
  begin
    if ADown then y := FBlocks[k].Top + FBlocks[k].Height else y := FBlocks[k].Top - 1;
    // (a cell merged over rows: below its last row)
    if ADown and (FBlocks[k].Layout is TTyRowLayout) then
      y := FBlocks[k].Top + TTyRowLayout(FBlocks[k].Layout).CellBottomAt(FCaret -
        FDoc.Text.ParaStart(FBlocks[k].FirstPara));
    Result := HitRaster(FWishX, y, AAtEnd);
    if not Went(Result) then Result := -1;
  end
  else
    Result := HitNeighbour(k, ADown, FWishX, AAtEnd);
end;

function TTyCustomRichEdit.HitClient(X, Y: Integer; out AAtEnd: Boolean): TTyRichPos;
begin
  Result := PositionAtPoint(X, Y, AAtEnd);
end;

function TTyCustomRichEdit.SnapPos(APos: TTyRichPos): TTyRichPos;
var
  t: TTyRichText;
  b: TTyBlockLayout;
  start, r: TTyRichPos;
begin
  t := FDoc.Text;
  if APos < 0 then APos := 0;
  if APos > t.Length then APos := t.Length;
  Result := APos;
  EnsureParams;
  FDoc.BeginRead;
  try
    b := LayoutBlockAt(t.ParaOfPos(APos));
    try
      start := t.ParaStart(b.FirstPara);
      // a cut paragraph's hidden tail: kept (Select All and copying take it; it shows at the cut)
      if (b is TTyParaLayout) and (APos - start > b.LastCaretPos) then Exit;
      // before an object of no width: the run's resting place (a step back would pass it whole)
      if b.UnseenEnd(APos - start, True) <> APos - start then
        Exit(start + b.RestPos(APos - start));
      // one step back from the next character: the caret place at or before APos
      r := b.NextCaretPos(APos - start + 1, False);
      if r >= 0 then Result := start + r;
    finally
      b.Release;
    end;
  finally
    FDoc.EndRead;
  end;
end;

{ The rule for every move a user makes (keys, clicks, drags, word and paragraph selections):
  the caret and the anchor are never left in a cut paragraph's hidden tail - past its
  LastCaretPos nothing is shown, and a caret there would stand at the cut while it moves. A
  place there goes forward to the next block's start (the cut when there is none) or back to
  the cut. The steps (CaretStep, NextCaretPos), Home / End (LineBounds) and the hit test keep
  to it by themselves; word steps, Ctrl+Home / Ctrl+End, a collapse and a word's or a
  paragraph's end go through here. SelectAll and the setters (SelStart, SelLength, CaretIndex)
  keep such a place: it shows at the cut, and copying takes the tail. }
function TTyCustomRichEdit.OutOfTail(APos: TTyRichPos; AForward: Boolean): TTyRichPos;
var
  t: TTyRichText;
  b: TTyBlockLayout;
  start: TTyRichPos;
begin
  t := FDoc.Text;
  if APos < 0 then APos := 0;
  if APos > t.Length then APos := t.Length;
  Result := APos;
  EnsureParams;
  FDoc.BeginRead;
  try
    b := LayoutBlockAt(t.ParaOfPos(APos));
    try
      start := t.ParaStart(b.FirstPara);
      if not (b is TTyParaLayout) or (APos - start <= b.LastCaretPos) then Exit;
      if AForward and (b.LastPara < t.ParaCount - 1) then
        Result := t.ParaStart(b.LastPara + 1)
      else
        Result := start + b.LastCaretPos;
    finally
      b.Release;
    end;
  finally
    FDoc.EndRead;
  end;
end;

function TTyCustomRichEdit.CaretStep(APos: TTyRichPos; AForward: Boolean): TTyRichPos;
var
  t: TTyRichText;
  b, prev: TTyBlockLayout;
  start, r: TTyRichPos;
begin
  t := FDoc.Text;
  Result := APos;
  EnsureParams;
  FDoc.BeginRead;
  try
    b := LayoutBlockAt(t.ParaOfPos(APos));
    try
      start := t.ParaStart(b.FirstPara);
      r := b.NextCaretPos(APos - start, AForward);
      if r >= 0 then
        Result := start + r
      else if AForward then
      begin
        // the next block's start (past a cut paragraph's hidden tail)
        if b.LastPara < t.ParaCount - 1 then Result := t.ParaStart(b.LastPara + 1);
      end
      else if b.FirstPara > 0 then
      begin
        prev := LayoutBlockAt(b.FirstPara - 1);
        try
          Result := t.ParaStart(prev.FirstPara) + prev.LastCaretPos;
        finally
          prev.Release;
        end;
      end;
    finally
      b.Release;
    end;
  finally
    FDoc.EndRead;
  end;
end;

{ The text around APos in its paragraph (CRichWordWindow characters either way) as
  characters, and where it starts. }
procedure WordWindow(AText: TTyRichText; APos: TTyRichPos; out AStart, AParaStart,
  AParaEnd: TTyRichPos; out ACodes: TTyRichCodes);
var
  p: Integer;
  stop: TTyRichPos;
begin
  p := AText.ParaOfPos(APos);
  AParaStart := AText.ParaStart(p);
  AParaEnd := AParaStart + AText.ParaLength(p);
  AStart := Math.Max(AParaStart, APos - CRichWordWindow);
  stop := Math.Min(AParaEnd, APos + CRichWordWindow);
  ACodes := RichCodes(AText.GetText(AStart, stop - AStart));
end;

const
  // an object with no width in a word window: no word and no break - as if it were not there
  CUnseenCode = $FFFFFFFE;

{ The objects of a word window (ACodes, from AStart) that the layout gives no width - a field's
  marks, a bookmark's ends - become CUnseenCode. }
procedure TTyCustomRichEdit.MarkUnseen(AStart: TTyRichPos; var ACodes: array of Cardinal);
var
  i: Integer;
begin
  for i := 0 to High(ACodes) do
    if (ACodes[i] = $FFFC) and (UnseenEnd(AStart + i, True) <> AStart + i) then
      ACodes[i] := CUnseenCode;
end;

{ A word window's character class (WordClass), -1 for an object with no width. }
function WordClassAt(const ACodes: TTyRichCodes; I: Integer): Integer; inline;
begin
  if ACodes[I] = CUnseenCode then Result := -1 else Result := WordClass(ACodes[I]);
end;

// of class AClass, or an object with no width (which goes with what is around it)
function WordIs(const ACodes: TTyRichCodes; I, AClass: Integer): Boolean; inline;
begin
  Result := (ACodes[I] = CUnseenCode) or (WordClass(ACodes[I]) = AClass);
end;

procedure TTyCustomRichEdit.WordAt(APos: TTyRichPos; out AFrom, ATo: TTyRichPos);
var
  a, ps, pe: TTyRichPos;
  codes: TTyRichCodes;
  i, s, e, n, cls: Integer;
begin
  AFrom := APos;
  ATo := APos;
  WordWindow(FDoc.Text, APos, a, ps, pe, codes);
  MarkUnseen(a, codes);
  n := Length(codes);
  if n = 0 then Exit;
  // the character after APos - at the paragraph's end the one before - and its run
  i := Integer(APos - a);
  if i >= n then i := n - 1;
  // (past objects with no width: the next character seen, else the one before)
  while (i < n - 1) and (WordClassAt(codes, i) < 0) do Inc(i);
  while (i > 0) and (WordClassAt(codes, i) < 0) do Dec(i);
  cls := WordClassAt(codes, i);
  if cls < 0 then Exit;
  if cls = 2 then
  begin
    AFrom := a + i;
    ATo := a + i + 1;
    Exit;
  end;
  s := i;
  while (s > 0) and (WordIs(codes, s - 1, cls)) do Dec(s);
  while WordClassAt(codes, s) < 0 do Inc(s);
  e := i + 1;
  while (e < n) and (WordIs(codes, e, cls)) do Inc(e);
  while WordClassAt(codes, e - 1) < 0 do Dec(e);
  AFrom := a + s;
  ATo := a + e;
end;

function TTyCustomRichEdit.WordStep(APos: TTyRichPos; AForward: Boolean): TTyRichPos;
var
  t: TTyRichText;
  a, ps, pe: TTyRichPos;
  codes: TTyRichCodes;
  i, n, p: Integer;
begin
  t := FDoc.Text;
  Result := APos;
  WordWindow(t, APos, a, ps, pe, codes);
  MarkUnseen(a, codes);
  n := Length(codes);
  i := Integer(APos - a);
  if AForward then
  begin
    // (objects with no width before what is seen are not there)
    while (i < n) and (WordClassAt(codes, i) < 0) do Inc(i);
    { The paragraph's end: the next caret place - the next paragraph's start, or in a row the
      next cell shown (a cell merged away is passed over, as Right passes it). }
    if a + i >= pe then
    begin
      Result := CaretStep(APos, True);
      Exit;
    end;
    // as the memo: past this word (an object is one by itself), then past what is no word
    if (i < n) and (WordClassAt(codes, i) = 2) then Inc(i)
    else
      while (i < n) and (WordIs(codes, i, 1)) do Inc(i);
    while (i < n) and (WordIs(codes, i, 0)) do Inc(i);
  end
  else
  begin
    // the paragraph's start: into the one before, from its end
    if APos <= ps then
    begin
      p := t.ParaOfPos(APos);
      if p = 0 then Exit;
      { The caret place before: a cell merged away is passed over (its empty paragraph is no
        place). A cut paragraph's end is in its hidden tail: the step ends at the cut. }
      if OutOfTail(ps - 1, False) <> ps - 1 then Exit(OutOfTail(ps - 1, False));
      APos := CaretStep(APos, False);
      WordWindow(t, APos, a, ps, pe, codes);
      MarkUnseen(a, codes);
      i := Integer(APos - a);
    end;
    while (i > 0) and (WordIs(codes, i - 1, 0)) do Dec(i);
    if (i > 0) and (WordClassAt(codes, i - 1) = 2) then Dec(i)
    else
      while (i > 0) and (WordIs(codes, i - 1, 1)) do Dec(i);
  end;
  // a word in a cut paragraph's hidden tail: on to the next block, or back to the cut
  Result := SnapPos(OutOfTail(a + i, AForward));
end;

procedure TTyCustomRichEdit.ParaRangeAt(APos: TTyRichPos; out AFrom, ATo: TTyRichPos);
var
  t: TTyRichText;
  p: Integer;
begin
  t := FDoc.Text;
  p := t.ParaOfPos(APos);
  AFrom := t.ParaStart(p);
  // with its separator, as Word selects a paragraph; the last paragraph has none
  ATo := AFrom + t.ParaLength(p) + Ord(p < t.ParaCount - 1);
end;

function TTyCustomRichEdit.ObjectAt(X, Y: Integer; APos: TTyRichPos): TTyRichPos;
var
  t: TTyRichText;
  k: Integer;
  q, start: TTyRichPos;
  area, r0, r1: TRect;
  vx, vy: Int64;
  L: TTyBlockLayout;
begin
  Result := -1;
  t := FDoc.Text;
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  vx := (Int64(X) - area.Left) * FScale + FScrollX;
  vy := (Int64(Y) - area.Top) * FScale;
  // the hit test gives an object's nearer edge: the object after it or the one before
  for q := APos downto APos - 1 do
  begin
    if (q < 0) or (q >= t.Length) then Continue;
    k := HeldBlockOf(q);
    if k < 0 then Continue;
    if t.GetText(q, 1) <> TyRichObjectChar then Continue;
    L := FBlocks[k].Layout;
    start := t.ParaStart(FBlocks[k].FirstPara);
    r0 := L.CaretRect(q - start, False);
    r1 := L.CaretRect(q + 1 - start, True);
    if (r0.Top = r1.Top) and (vx >= r0.Left) and (vx < r1.Left) and
      (vy - FBlocks[k].Top >= r0.Top) and (vy - FBlocks[k].Top < r0.Bottom) then
      Exit(q);
  end;
end;

procedure TTyCustomRichEdit.Select(AAnchor, ACaret: TTyRichPos; AAtEnd: Boolean);
var
  len, a0, a1, b0, b1: TTyRichPos;
begin
  len := FDoc.Text.Length;
  if AAnchor < 0 then AAnchor := 0;
  if AAnchor > len then AAnchor := len;
  if ACaret < 0 then ACaret := 0;
  if ACaret > len then ACaret := len;
  { Both ends on resting places (RestingPlace) - not inside the document's update, where
    nothing is laid out: its end puts them there (SnapAfterChange). }
  if not ViewBehind and not (csDestroying in ComponentState) then
  begin
    a0 := RestingPlace(ACaret);
    if AAnchor = ACaret then AAnchor := a0 else AAnchor := RestingPlace(AAnchor);
    { The affinity is of the place it was given for: moved over marks, the caret keeps the line
      it was given on (a place rested over a close mark that ends its line is that line's end). }
    if a0 <> ACaret then AAtEnd := RestKeepsLineEnd(ACaret, a0, AAtEnd);
    ACaret := a0;
  end;
  a0 := Math.Min(FSelAnchor, FCaret);
  a1 := Math.Max(FSelAnchor, FCaret);
  { The caret or the anchor moved by anything but an edit of the control's own (a key, a
    click, a setter, a change from elsewhere): the next typing is an undo step of its own, as
    the memo's caret moves end its run (an edit's own placing is not one: the edits place the
    caret themselves). }
  if (FEditing = 0) and ((AAnchor <> FSelAnchor) or (ACaret <> FCaret)) then EndTypingRun;
  // a drag of a handle is of the selection it began with
  if FResizing and ((AAnchor <> FSelAnchor) or (ACaret <> FCaret)) then CancelResize;
  if (FDragPending or OwnDragging) and ((AAnchor <> FSelAnchor) or (ACaret <> FCaret)) then
    CancelSelectionDrag;
  { The selection set again - also to the same place, and by an edit's own placing - ends a
    pending format (as on Windows' rich edit); a façade's write keeps the selection and it. }
  if FApiWrite = 0 then FHasPendingFmt := False;
  FSelAnchor := AAnchor;
  FCaret := ACaret;
  FCaretAtEnd := AAtEnd;
  { The door: while the document holds its changes back the held blocks may name
    paragraphs that are gone - the positions are kept (clamped to the text as it is now) and
    nothing is painted; the update's end paints the selection (DocUpdatingEnded). }
  if ViewBehind then
  begin
    FSelInUpdate := True;
    FPosInUpdate := True;
    Exit;
  end;
  b0 := Math.Min(AAnchor, ACaret);
  b1 := Math.Max(AAnchor, ACaret);
  // what changed its selected state: where the two stretches differ
  if (a0 = b0) and (a1 = b1) then Exit;
  if a1 <= a0 then
    RepaintRange(b0, b1)
  else if b1 <= b0 then
    RepaintRange(a0, a1)
  else if (b1 <= a0) or (a1 <= b0) then
  begin
    RepaintRange(a0, a1);
    RepaintRange(b0, b1);
  end
  else
  begin
    RepaintRange(Math.Min(a0, b0), Math.Max(a0, b0));
    RepaintRange(Math.Min(a1, b1), Math.Max(a1, b1));
  end;
  // a selected object's handles come or go: their place alone is painted again
  SyncObjectOverlay;
end;

function TTyCustomRichEdit.RestKeepsLineEnd(AGiven, ARested: TTyRichPos; AAtEnd: Boolean): Boolean;
var
  t: TTyRichText;
  b: TTyBlockLayout;
  start, gs, rs0, rs1, e: TTyRichPos;
  atEnd: Boolean;
begin
  Result := False;
  t := FDoc.Text;
  if (ARested <= AGiven) or (t.ParaOfPos(AGiven) <> t.ParaOfPos(ARested)) then Exit;
  EnsureParams;
  FDoc.BeginRead;
  try
    b := LayoutBlockAt(t.ParaOfPos(AGiven));
    try
      start := t.ParaStart(b.FirstPara);
      b.LineBounds(AGiven - start, AAtEnd, gs, e, atEnd);
      b.LineBounds(ARested - start, True, rs1, e, atEnd);
      b.LineBounds(ARested - start, False, rs0, e, atEnd);
      Result := (rs1 = gs) and (rs0 <> gs);
    finally
      b.Release;
    end;
  finally
    FDoc.EndRead;
  end;
end;

{ An object's character right before or right after APos: only then can APos be in a run of
  objects with no width (two characters read, nothing laid out). }
function ObjectBeside(AText: TTyRichText; APos: TTyRichPos): Boolean;
var
  a, b: TTyRichPos;
begin
  a := Math.Max(Int64(0), APos - 1);
  b := Math.Min(AText.Length, APos + 1);
  Result := (b > a) and (Pos(TyRichObjectChar, AText.GetText(a, b - a)) > 0);
end;

function TTyCustomRichEdit.RestingPlace(APos: TTyRichPos): TTyRichPos;
var
  t: TTyRichText;
  b: TTyBlockLayout;
  start: TTyRichPos;
begin
  t := FDoc.Text;
  if APos < 0 then APos := 0;
  if APos > t.Length then APos := t.Length;
  Result := APos;
  if not ObjectBeside(t, APos) then Exit;
  EnsureParams;
  FDoc.BeginRead;
  try
    b := LayoutBlockAt(t.ParaOfPos(APos));
    try
      start := t.ParaStart(b.FirstPara);
      Result := start + b.RestPos(APos - start);
    finally
      b.Release;
    end;
  finally
    FDoc.EndRead;
  end;
end;

function TTyCustomRichEdit.UnseenEnd(APos: TTyRichPos; AForward: Boolean): TTyRichPos;
var
  t: TTyRichText;
  b: TTyBlockLayout;
  start: TTyRichPos;
begin
  t := FDoc.Text;
  if APos < 0 then APos := 0;
  if APos > t.Length then APos := t.Length;
  Result := APos;
  if not ObjectBeside(t, APos) then Exit;
  EnsureParams;
  FDoc.BeginRead;
  try
    b := LayoutBlockAt(t.ParaOfPos(APos));
    try
      start := t.ParaStart(b.FirstPara);
      Result := start + b.UnseenEnd(APos - start, AForward);
    finally
      b.Release;
    end;
  finally
    FDoc.EndRead;
  end;
end;

{ A field cut by [s, e) has one mark inside it: one around s whose close mark is before e, or
  one around e whose open mark is at or after s. Each is found from the innermost field
  around the place outward (TTyRichDocument.FieldRangeAt: a look-up per paragraph of the
  field, at most three paragraphs read); a field around both ends is not cut, and neither is
  any around it. }
function TTyCustomRichEdit.FieldCover(var AStart, ALen: TTyRichPos): Boolean;
var
  s, e, o, c, s0, e0: TTyRichPos;
  i: Integer;
begin
  Result := False;
  s := AStart;
  e := AStart + ALen;
  for i := 1 to 64 do
  begin
    s0 := s;
    e0 := e;
    while FDoc.FieldRangeAt(s, o, c) and (c < e) do s := o;
    while FDoc.FieldRangeAt(e, o, c) and (o >= s) do e := c + 1;
    { (Grown ends are not rested here: a resting place a grown end moves to takes a field's
      mark only when that field holds the whole range - an edit wholly inside one result, which
      is refused before (InsideOneResult); the selection shown rests its ends itself.) }
    if (s = s0) and (e = e0) then Break;
  end;
  Result := (s <> AStart) or (e <> AStart + ALen);
  AStart := s;
  ALen := e - s;
end;

function TTyCustomRichEdit.GrowOverFields(AStart, ALen: TTyRichPos): Boolean;
var
  s, n: TTyRichPos;
begin
  s := AStart;
  n := ALen;
  Result := FieldCover(s, n);
  if Result then ShowCover(s, n);
end;

function TTyCustomRichEdit.InsideOneResult(AFrom, ATo: TTyRichPos): Boolean;
var
  t: TTyRichText;
  k, ks, ke, i, d, st, low: Integer;
  runs: TTyRunArray;
  ps, q: TTyRichPos;
begin
  Result := False;
  t := FDoc.Text;
  FDoc.BeginRead;
  try
    d := FDoc.FieldDepthAt(AFrom);
    if d <= 0 then Exit;
    ks := t.ParaOfPos(AFrom);
    ke := t.ParaOfPos(ATo);
    k := ks;
    while k <= ke do
    begin
      if (k > ks) and (k < ke) then
      begin
        // a paragraph between: the fewest fields open anywhere in it
        FDoc.ParaFieldDepths(k, st, low);
        if low <= 0 then Exit;
        Inc(k);
        Continue;
      end;
      if k > ks then d := FDoc.ParaFieldDepth(k);
      if d <= 0 then Exit;
      // every mark in [AFrom, ATo): a close that leaves no field open ends the result
      runs := FDoc.RunsOf(k);
      ps := t.ParaStart(k);
      for i := 0 to High(runs) do
      begin
        q := ps + runs[i].Start;
        if q < AFrom then Continue;
        if q >= ATo then Break;
        if runs[i].Obj is TTyRichFieldMark then
          if TTyRichFieldMark(runs[i].Obj).Kind = rfmOpen then Inc(d)
          else
          begin
            Dec(d);
            if d <= 0 then Exit;
          end;
      end;
      Inc(k);
    end;
    Result := True;
  finally
    FDoc.EndRead;
  end;
end;

procedure TTyCustomRichEdit.ShowCover(AStart, ALen: TTyRichPos);
begin
  // the caret at the end it was on (a caret alone: at the far end)
  if FCaret < FSelAnchor then Select(AStart + ALen, AStart, False)
  else Select(AStart, AStart + ALen, False);
  FWishValid := False;
  ScrollCaretIntoView;
  CaretMoved;
  DoSelectionChange;
end;

{ The lines of the held blocks in view that [AFrom, ATo) touches are painted again: a block it
  covers whole as its band, one it covers in part line by line (SelectionRects, the separator's
  mark included). Positions only - nothing is laid out, no paragraph outside the view is
  looked at, so all of a huge document costs what the screen costs. A view to be laid out
  again is painted again whole by that pass's paint. }
procedure TTyCustomRichEdit.RepaintRange(AFrom, ATo: TTyRichPos);
var
  t: TTyRichText;
  k, i: Integer;
  start, stop: TTyRichPos;
  rs: TRectArray;
begin
  if ATo <= AFrom then Exit;
  if not FViewValid or (FBlockCount = 0) then
  begin
    MarkTextDirty;
    InvalidateArea(TextWindowRect);
    Exit;
  end;
  t := FDoc.Text;
  for k := 0 to FBlockCount - 1 do
  begin
    if (FBlocks[k].Top >= FViewH) or (FBlocks[k].Top + FBlocks[k].Height <= 0) then Continue;
    start := t.ParaStart(FBlocks[k].FirstPara);
    stop := t.ParaStart(FBlocks[k].LastPara) + t.ParaLength(FBlocks[k].LastPara);
    // its last separator is stop's character
    if (ATo <= start) or (AFrom > stop) then Continue;
    if (AFrom <= start) and (ATo > stop) then
      InvalidateBand(FBlocks[k].Top, FBlocks[k].Top + FBlocks[k].Height)
    else
    begin
      rs := FBlocks[k].Layout.SelectionRects(Math.Max(AFrom - start, 0),
        Math.Min(ATo - start, stop - start + 1));
      for i := 0 to High(rs) do
        InvalidateBand(FBlocks[k].Top + rs[i].Top, FBlocks[k].Top + rs[i].Bottom);
    end;
  end;
end;

function TTyCustomRichEdit.CaretClientRect: TRect;
var
  tw, r: TRect;
  w: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  // while composing: the input method's caret in the composition
  if FComposing and (FCompText <> '') and not ViewBehind then
  begin
    Settle;
    if CompositionRaster(r) then
      Result := ClientOf(TextArea(Rect(0, 0, Width, Height), ViewPPI), r.Left, r.Top, r.Right,
        r.Bottom);
  end;
  if Result.Bottom <= Result.Top then Result := PositionRect(FCaret, FCaretAtEnd);
  if (Result.Bottom <= Result.Top) then Exit(Rect(0, 0, 0, 0));
  w := Math.Max(1, MulDiv(1, ViewPPI, 96));
  Result.Right := Result.Left + w;
  { A line's end at the layout width or past it (a justified or right-aligned line, a full
    one, a wrapped line's hanging spaces) puts the caret on the text's right edge or beyond
    it, where the clip would take it away; with nothing to scroll to that way it is drawn
    inside, against the edge. The same at the left edge. }
  tw := TextWindowRect;
  if tw.Right - tw.Left < w then Exit;
  if (Result.Right > tw.Right) and (FScrollX >= Math.Max(0, FWidestSeen - FViewW)) then
    Types.OffsetRect(Result, tw.Right - Result.Right, 0)
  else if (Result.Left < tw.Left) and (FScrollX <= 0) then
    Types.OffsetRect(Result, tw.Left - Result.Left, 0);
end;

procedure TTyCustomRichEdit.CaretMoved;
var
  r: TRect;
begin
  FCaretShown := True;
  FBlinkMs := 0;
  if not IsRectEmpty(FCaretDrawn) then InvalidateArea(FCaretDrawn);
  if HasCaretFocus then
  begin
    r := CaretClientRect;
    if not IsRectEmpty(r) then InvalidateArea(r);
  end;
end;

procedure TTyCustomRichEdit.Moved(AKeepWish: Boolean);
begin
  if not AKeepWish then FWishValid := False;
  ScrollCaretIntoView;
  CaretMoved;
  DoSelectionChange;
end;

procedure TTyCustomRichEdit.SetScrollXRaster(AValue: Integer);
var
  was: Integer;
begin
  was := FScrollX;
  FScrollX := AValue;
  ClampScrollX;
  if FScrollX = was then Exit;
  CancelResize;
  // a range a load's turns held back first: the position is in the range the bar has
  CatchUpBars;
  if HBarShown then
  begin
    FSyncingBars := True;
    try
      FHBar.Position := FScrollX div FScale;
    finally
      FSyncingBars := False;
    end;
  end;
  MoveSurfaceText(was - FScrollX, 0);
  InvalidateArea(TextWindowRect);
end;

procedure TTyCustomRichEdit.ScrollCaretIntoView;
var
  r: TRect;
  p, margin: Integer;
  below: Boolean;
begin
  if ViewBehind then Exit;
  Settle;
  if (FViewH <= 0) or (FBlockCount = 0) then Exit;
  if not ShownCaretRaster(r) then
  begin
    { not laid out: to its paragraph by the height index, then to its line (while composing
      the composition's, whose caret may be lines below where it began) }
    if FComposing then p := FDoc.Text.ParaOfPos(FCompPos) else p := FDoc.Text.ParaOfPos(FCaret);
    below := p > FBlocks[FBlockCount - 1].LastPara;
    ScrollRasterTo(FDoc.Text.ParaTop(p));
    Settle;
    if not ShownCaretRaster(r) then Exit;
    // as if it had been scrolled to from where the view was: at the bottom, or at the top
    if below then ScrollRasterBy(r.Bottom - FViewH) else ScrollRasterBy(r.Top);
  end
  else if r.Top < 0 then
    ScrollRasterBy(r.Top)
  else if r.Bottom > FViewH then
    // a line taller than the view shows its top
    ScrollRasterBy(Math.Min(r.Bottom - FViewH, r.Top));
  // across (no wrapping, a page wider than the window): with a line's height of room
  if FWidestSeen > FViewW then
  begin
    Settle;
    // (while composing: the composition's caret, so that it follows past the right edge)
    if not ShownCaretRaster(r) then Exit;
    margin := Math.Min(FEstimate, FViewW div 4);
    if r.Left < margin then SetScrollXRaster(FScrollX + r.Left - margin)
    else if r.Right > FViewW - margin then SetScrollXRaster(FScrollX + r.Right - (FViewW - margin));
  end;
end;

procedure TTyCustomRichEdit.MoveVertical(ADown, AExtend: Boolean);
var
  r: TRect;
  q, q2: TTyRichPos;
  atEnd, atEnd2: Boolean;
  n, k: Integer;
begin
  ScrollCaretIntoView;
  Settle;
  if not CaretRaster(FCaret, FCaretAtEnd, r) then Exit;
  if not FWishValid then
  begin
    FWishX := r.Left + FScrollX;
    FWishValid := True;
  end;
  q := LineFrom(r, ADown, atEnd);
  if q < 0 then Exit;
  { Into a covered cell: up, the cell the span starts with (its text's end); down, on to the
    row below the covered cell's - row by row, bounded by the span's rows. }
  n := 0;
  while (q >= 0) and CoveredPara(FDoc.Text.ParaOfPos(q)) and (n < CRichMaxTableRows) do
  begin
    Inc(n);
    if not ADown then
    begin
      q := SpanOwnerPos(q);
      atEnd := False;
      Break;
    end;
    k := HeldBlockOf(q);
    if k < 0 then Break;
    if k < FBlockCount - 1 then
      q2 := HitRaster(FWishX, FBlocks[k].Top + FBlocks[k].Height, atEnd2)
    else
      q2 := HitNeighbour(k, True, FWishX, atEnd2);
    if (q2 < 0) or (q2 = q) then Break;
    q := q2;
    atEnd := atEnd2;
  end;
  // (a covered cell the table ends with: no move)
  if (q >= 0) and CoveredPara(FDoc.Text.ParaOfPos(q)) then Exit;
  if AExtend then Select(FSelAnchor, q, atEnd) else Select(q, q, atEnd);
end;

procedure TTyCustomRichEdit.MoveInLine(AToEnd, AExtend: Boolean);
var
  t: TTyRichText;
  b: TTyBlockLayout;
  start, s, e, q: TTyRichPos;
  eAtEnd: Boolean;
begin
  t := FDoc.Text;
  EnsureParams;
  FDoc.BeginRead;
  try
    b := LayoutBlockAt(t.ParaOfPos(FCaret));
    try
      start := t.ParaStart(b.FirstPara);
      b.LineBounds(FCaret - start, FCaretAtEnd, s, e, eAtEnd);
    finally
      b.Release;
    end;
  finally
    FDoc.EndRead;
  end;
  if AToEnd then q := start + e else q := start + s;
  eAtEnd := AToEnd and eAtEnd;
  if AExtend then Select(FSelAnchor, q, eAtEnd) else Select(q, q, eAtEnd);
end;

procedure TTyCustomRichEdit.MovePage(ADown, AExtend: Boolean);
var
  r, r2: TRect;
  y: Int64;
  page, para: Integer;
  off: Int64;
  q, q2: TTyRichPos;
  atEnd, atEnd2: Boolean;
begin
  ScrollCaretIntoView;
  Settle;
  if not CaretRaster(FCaret, FCaretAtEnd, r) then Exit;
  if not FWishValid then
  begin
    FWishX := r.Left + FScrollX;
    FWishValid := True;
  end;
  page := Math.Max(FEstimate, FViewH - FEstimate);
  para := FAnchorPara;
  off := FAnchorOffset;
  if ADown then ScrollRasterBy(page) else ScrollRasterBy(-page);
  Settle;
  // the caret keeps its place in the view; where the view could not move (an end), it goes
  // the page itself - to the first or the last line
  y := (r.Top + r.Bottom) div 2;
  if (para = FAnchorPara) and (off = FAnchorOffset) then
    if ADown then Inc(y, page) else Dec(y, page);
  q := HitRaster(FWishX, y, atEnd);
  if q < 0 then Exit;
  { A line taller than the page (a picture): the page lands on the caret's own line, and
    showing the caret would scroll back to it - a line on instead, as Down / Up goes. }
  if CaretRaster(FCaret, FCaretAtEnd, r) and CaretRaster(q, atEnd, r2) and
    ((ADown and (r2.Top <= r.Top)) or (not ADown and (r2.Top >= r.Top))) then
  begin
    q2 := LineFrom(r, ADown, atEnd2);
    if q2 >= 0 then
    begin
      q := q2;
      atEnd := atEnd2;
    end;
  end;
  if AExtend then Select(FSelAnchor, q, atEnd) else Select(q, q, atEnd);
end;

function TTyCustomRichEdit.HasCaretFocus: Boolean;
begin
  Result := Focused;
end;

function TTyCustomRichEdit.CanFocus: Boolean;
begin
  if FPressNoFocus then Exit(False);
  Result := inherited CanFocus;
end;

procedure TTyCustomRichEdit.DrawCaret(ACanvas: TCanvas);
var
  r: TRect;
begin
  FCaretDrawn := Rect(0, 0, 0, 0);
  // (inside the document's update the view knows nothing of the change yet: no query)
  if not HasCaretFocus or (csDesigning in ComponentState) or ViewBehind then Exit;
  // a viewer asked to show none (CaretWhenReadOnly): the caret is still there, undrawn
  if CaretHidden then Exit;
  // the candidate window follows the caret: after a scroll, a zoom, a composition's change
  PlaceImeWindows;
  // a composition shows its caret over a selection it will replace
  if not FCaretShown or (HasSelection and not FComposing) then Exit;
  r := CaretClientRect;
  if IsRectEmpty(r) or not IntersectRect(r, r, TextWindowRect) then Exit;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := TyColorToLCL(CurrentStyle.TextColor);
  ACanvas.FillRect(r);
  FCaretDrawn := r;
end;

procedure TTyCustomRichEdit.BlinkTick(Sender: TObject);
var
  vis: Boolean;
  r: TRect;
begin
  { Inside the document's update (an application pumping messages between BeginUpdate and
    EndUpdate) the blocks may name paragraphs that are gone: the blink waits. }
  if ViewBehind or CaretHidden then Exit;
  Inc(FBlinkMs, CRichBlinkMs);
  vis := TyCaretVisible(FBlinkMs, CRichBlinkMs);
  if vis = FCaretShown then Exit;
  FCaretShown := vis;
  // only the caret's rectangle is blitted again: the text under it is on the surface
  if vis then r := CaretClientRect else r := FCaretDrawn;
  if not IsRectEmpty(r) then InvalidateArea(r);
end;

procedure TTyCustomRichEdit.StartBlink;
begin
  // (in the form designer no caret is drawn: no timer either)
  if not HandleAllocated or (csDesigning in ComponentState) then Exit;
  if FBlinkTimer = nil then
  begin
    FBlinkTimer := TTimer.Create(nil);
    FBlinkTimer.Interval := CRichBlinkMs;
    FBlinkTimer.OnTimer := @BlinkTick;
  end;
  FBlinkTimer.Enabled := True;
end;

procedure TTyCustomRichEdit.DoEnter;
begin
  inherited DoEnter;
  if csDestroying in ComponentState then Exit;
  FCaretShown := True;
  FBlinkMs := 0;
  StartBlink;
  CaretMoved;
  // GTK2: the hook's input context composes while the control has the focus (the memo's)
  TyImeSetFocus(FImeHook, True);
  FImePlaced := Rect(0, 0, 0, 0);
end;

procedure TTyCustomRichEdit.DoExit;
begin
  { Freed while focused: LCL sends CM_EXIT after the destructor's body freed the document -
    only the exit's own event then (as every LCL control has it). }
  if csDestroying in ComponentState then
  begin
    inherited DoExit;
    Exit;
  end;
  { The focus left: a composition goes in (the input method commits what it composed),
    before the inherited OnExit, so that it sees the text. Not on win32: there it ended when
    the window lost the focus (WMKillFocus) - CM_EXIT comes from inside the new control's
    set-focus, when the thread's one input context already serves that window, and never
    when the focus goes to another form or program. Cocoa: LCL-Cocoa lets the input context
    commit before the first responder changes (the bridge's session end), so this ends only
    what a focus change made by code leaves; Qt5 / Qt6 / GTK2 / GTK3: the text shown goes in
    (their input methods show the composition themselves, ImeEndOnWidgetset tells none). }
  {$IFNDEF LCLWin32}
  EndComposition(True);
  {$ENDIF}
  inherited DoExit;
  TyImeSetFocus(FImeHook, False);
  // the focus left: the run of typing ends (as the memo's)
  EndTypingRun;
  if FBlinkTimer <> nil then FBlinkTimer.Enabled := False;
  FCaretShown := True;
  StopDrag;
  if not IsRectEmpty(FCaretDrawn) then InvalidateArea(FCaretDrawn);
end;

function TTyCustomRichEdit.CursorAt(X, Y: Integer): TCursor;
var
  h: TTyRichHandle;
  url: string;
  zone, zp, ek: Integer;
begin
  // a handle's size cursor, also where it reaches over the text beside the object
  if FResizing then Exit(HandleCursor(FResizeHandle));
  // the control's own drag of the selection: what a release would do
  if OwnDragging then Exit(DropCursor(FDropEffect));
  if not ViewBehind and ObjectHandleAt(X, Y, h) then Exit(HandleCursor(h));
  // a table's edge: dragged, or under the pointer
  if FEdgeDrag = CEdgeColumn then Exit(crSizeWE);
  if FEdgeDrag = CEdgeRow then Exit(crSizeNS);
  if not ViewBehind and not FDragging and EdgeAt(X, Y, zone, zp, ek) then
    if zone = CEdgeColumn then Exit(crSizeWE) else Exit(crSizeNS);
  // a table's zones: an arrow for a cell or a row, down for a column, the table's handle
  if not ViewBehind and not FDragging and TableZoneAt(X, Y, zone, zp) then
    case zone of
      3: Exit(crUpArrow);
      4: Exit(crSizeAll);
    else
      Exit(crArrow);
    end;
  if PtInRect(TextArea(Rect(0, 0, Width, Height), ViewPPI), Point(X, Y)) then
  begin
    // the hand where a left click makes a link's click (not while a drag selects)
    if not FDragging and not ViewBehind and LinkClickFires(FPointerShift, mbLeft) and
      LinkAtPoint(X, Y, url) then
      Exit(crHandPoint);
    // nothing to select: the arrow (the padding's, see GetCursor)
    if FAllowSelection then Result := crIBeam else Result := crDefault;
  end
  else
    Result := crDefault;
end;

function TTyCustomRichEdit.GetCursor: TCursor;
begin
  Result := inherited GetCursor;
  if (Result = crIBeam) and ([csDesigning, csWriting] * ComponentState = []) then
    if FOverHandle <> crDefault then Result := FOverHandle
    else if FOverPadding then Result := crArrow;
end;

procedure TTyCustomRichEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  q, a, b, o, q0, s0, n0: TTyRichPos;
  atEnd, pre, dblHandled: Boolean;
  clicks: Integer;
  h: TTyRichHandle;
  box: TRect;
  life: TTyRichLife;

  procedure DblClick;
  begin
    dblHandled := FireObjectEvent(True, o, Button, Shift, X, Y);
  end;

begin
  dblHandled := False;
  // (in the form designer a press selects the control, not text: no caret, no drag)
  if not IsEnabled or (csDesigning in ComponentState) then Exit;
  // (a press on a link waiting for its release: any other press ends the wait)
  FLinkPressed := False;
  { Another press during a drag of the control's own (another button: the right one, the
    middle one) - a handle's, the selection's or the press waiting for one: the drag ends with
    nothing changed and the press does nothing else - the selection stays, and the right
    press's menu does not come. }
  FEatMenu := False;
  if OwnDragRunning or FPressClickOwed then
  begin
    EndOwnDrag;
    FEatMenu := Button = mbRight;
    inherited MouseDown(Button, Shift, X, Y);
    Exit;
  end;
  { A press while composing is placed on what the user saw: the text with the composition in
    it (the hit test answers the document's positions behind it), taken before the
    composition ends. A point on the composition is its place, behind it. The object under
    the press is taken there too and carried as a position (DocChanged).
    Not on macOS (accepted as the platform's limit): LCL-Cocoa hands the mouse-down to
    the input context before the control sees it (TCocoaFullControlEdit.mouseDown), and the
    input method commits there - through the bridge, as typing, which scrolls the caret into
    view. Here the composition has ended already, and the press is placed on the committed,
    scrolled text: after a scroll away the view may jump back, and on the composition's line
    the caret may be off by the difference between what was shown and what went in. Doing
    better needs tyControls.CocoaWS (the bridge's commit inside a mouse-down hit-testing the
    event's point on the composition first, and not scrolling). }
  pre := False;
  q := -1;
  o := -1;
  atEnd := False;
  if FComposing and (FCompText <> '') and ((Button = mbLeft) or (Button = mbRight)) and
    not ViewBehind then
  begin
    q := HitClient(X, Y, atEnd);
    if q >= 0 then
    begin
      pre := True;
      FPressPos := q;
      FPressObj := ObjectAt(X, Y, q);
      FPressAfter := (q > FCompPos) or ((q = FCompPos) and not PressBeforeComposition(X, Y));
      FPressCarry := True;
    end;
  end;
  { A press in the text ends a composition first: it goes in where it was shown, then the
    press places the caret (Cocoa's input method commits on the press before it gets here).
    The press's place goes through the commit as any position does (DocChanged), and the
    commit does not scroll: the view stays where the user clicked. An input method that
    answers later sends its result to where the composition was (FCompPending), the caret
    staying where the press put it. }
  FNoEditScroll := True;
  try
    EndCompositionForUser;
  finally
    FNoEditScroll := False;
  end;
  if pre then
  begin
    // (a content replaced meanwhile: the press is hit-tested again below)
    pre := FPressCarry;
    FPressCarry := False;
    q0 := q;
    q := FPressPos;
    o := FPressObj;
    if q <> q0 then atEnd := False;
    // at the composition's place, before it: an owed result goes in behind the caret
    FCompBefore := FCompPending and (q = FCompPos) and not FPressAfter;
  end;
  // (the base control's focus on a press: not when FocusOnClick says no - CanFocus)
  FPressNoFocus := not FFocusOnClick;
  try
    inherited MouseDown(Button, Shift, X, Y);
  finally
    FPressNoFocus := False;
  end;
  // a user action is an entry point of the loop (see SchedulingFailed)
  EndOwedLoad;
  FObjPressAt := -1;
  // the middle button: a link's click, or an object's, or nothing
  if Button = mbMiddle then
  begin
    if not LinkPress(Button, Shift, X, Y) and not ViewBehind then
    begin
      FObjPressAt := ObjectPosAtPoint(X, Y);
      FObjPressButton := Button;
      FObjPressPoint := Point(X, Y);
    end;
    Exit;
  end;
  if (Button <> mbLeft) and (Button <> mbRight) then Exit;
  try
    if FFocusOnClick and CanFocus and not Focused then SetFocus;
  except
    // no focus to be had (a form not shown): the caret is placed all the same
  end;
  // inside the document's update a press places nothing
  if ViewBehind then Exit;
  { A press on a handle of the selected object begins a resize - never a selection, also
    where the handle reaches over the text beside the object (or another object). }
  if (Button = mbLeft) and ObjectHandleAt(X, Y, h) and HandleObject(q, box) then
  begin
    StartResize(h, q, box, X, Y);
    Exit;
  end;
  // a link's click (LinkClickFires): nothing else - no caret, no selection, no object
  if (Button = mbLeft) and LinkPress(Button, Shift, X, Y) then Exit;
  // a table's edge: its drag (Shift: the rest follows), a double click's fit
  if (Button = mbLeft) and EdgePress(X, Y, Shift) then Exit;
  // a table's zones: a cell, a row, a column, the whole table (and a drag over more)
  if (Button = mbLeft) and not (ssShift in Shift) and TableZonePress(X, Y) then Exit;
  if (Button = mbLeft) and (ssShift in Shift) and TableZoneExtend(X, Y) then Exit;
  // an object under the press: its click on the release, its double click now
  FObjPressAt := ObjectPosAtPoint(X, Y);
  FObjPressButton := Button;
  FObjPressPoint := Point(X, Y);
  if (Button = mbLeft) and (ssDouble in Shift) and (FObjPressAt >= 0) then
  begin
    o := FObjPressAt;
    FObjPressAt := -1;
    Guard(life, @DblClick);
    if life.Gone or dblHandled then Exit;
  end;
  // no selection of the user's (AllowSelection): a press places nothing, drags nothing
  if not FAllowSelection then Exit;
  if not pre then
  begin
    q := HitClient(X, Y, atEnd);
    o := -2;
  end;
  q := Math.Min(q, FDoc.Text.Length);
  if q < 0 then Exit;
  if Button = mbRight then
  begin
    // the menu acts on the selection a click inside it keeps; one outside moves the caret first
    if not HasSelection or (q < GetSelStart) or (q > GetSelStart + GetSelLength) then
    begin
      Select(q, q, atEnd);
      FWishValid := False;
      CaretMoved;
      DoSelectionChange;
    end;
    Exit;
  end;
  FDragUnit := 1;
  if ssShift in Shift then
    // extends from the anchor
    Select(FSelAnchor, q, atEnd)
  else
  begin
    // the memo's count: 2 a word, 3 a paragraph, a fourth press a plain click again
    clicks := TyMultiClickCount(ssDouble in Shift, X, Y, FLastClickX, FLastClickY,
      FLastClickTick, FClickCount, ViewPPI);
    if clicks = 2 then
    begin
      // the object under the pointer is the word (on its right half too)
      if o = -2 then o := ObjectAt(X, Y, q);
      if o >= 0 then
      begin
        a := o;
        b := o + 1;
      end
      else
      begin
        WordAt(q, a, b);
        b := OutOfTail(b, False);
      end;
      Select(a, b, False);
      FDragUnit := 2;
    end
    else if clicks = 3 then
    begin
      ParaRangeAt(q, a, b);
      Select(a, OutOfTail(b, False), False);
      FDragUnit := 3;
    end
    else
    begin
      if clicks > 3 then FClickCount := 1;
      if o = -2 then o := ObjectAt(X, Y, q);
      { A press inside the selection (on its text, or on a selected object's body) may begin
        a drag of it: nothing changes until the pointer moves past the drag threshold, or the
        button comes up (the click it would have been). }
      if DragStartOpen and PressInSelection(X, Y) and (FFindKind <> rfkNone) then
      begin
        // the press takes the document in hand: background work ends (its handler may move things)
        s0 := GetSelStart;
        n0 := GetSelLength;
        if not EndBackgroundForUser then Exit;
        if (GetSelStart <> s0) or (GetSelLength <> n0) or ViewBehind then
        begin
          q := Math.Min(HitClient(X, Y, atEnd), FDoc.Text.Length);
          if q < 0 then Exit;
          o := ObjectAt(X, Y, q);
        end;
      end;
      if DragStartOpen and PressInSelection(X, Y) then
      begin
        FDragPending := True;
        FPressClickOwed := True;
        FPressPoint := Point(X, Y);
        FPressPlace := q;
        FPressAtEnd := atEnd;
        FDragPressObj := o;
        Exit;
      end;
      PlainClick(X, Y, q, atEnd, o);
    end;
  end;
  FDragFrom := GetSelStart;
  FDragTo := GetSelStart + GetSelLength;
  FDragging := True;
  FWishValid := False;
  CaretMoved;
  DoSelectionChange;
end;

procedure TTyCustomRichEdit.ExtendDragTo(X, Y: Integer);
var
  area: TRect;
  q, a, b, o: TTyRichPos;
  atEnd: Boolean;
begin
  // the pointer held to the text: past an edge, the line along that edge
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  X := Math.Max(area.Left, Math.Min(X, area.Right - 1));
  Y := Math.Max(area.Top, Math.Min(Y, area.Bottom - 1));
  q := HitClient(X, Y, atEnd);
  if q < 0 then Exit;
  case FDragUnit of
    2:
      begin
        o := ObjectAt(X, Y, q);
        if o >= 0 then
        begin
          a := o;
          b := o + 1;
        end
        else
        begin
          WordAt(q, a, b);
          b := OutOfTail(b, False);
        end;
      end;
    3:
      begin
        ParaRangeAt(q, a, b);
        b := OutOfTail(b, False);
      end;
    4:
      begin
        { From the object pressed: on it (either half: its start or its end) it stays
          selected with the anchor at its start; past it rightwards the anchor stays at its
          start, leftwards it goes to its end - as a word's does. }
        if q > FDragTo then Select(FDragFrom, q, atEnd)
        else if q < FDragFrom then Select(FDragTo, q, atEnd)
        else Select(FDragFrom, FDragTo, False);
        Exit;
      end;
  else
    begin
      Select(FSelAnchor, q, atEnd);
      Exit;
    end;
  end;
  // by whole words (paragraphs): the one the press selected stays
  if q >= FDragFrom then Select(FDragFrom, Math.Max(b, FDragTo), False)
  else Select(FDragTo, a, False);
end;

{ A click on the text: on an object it selects it (one that can be resized shows its handles).
  The object is the pressed unit, as a word is after a double click: it stays selected while
  the pointer moves on it, and a drag extends from it. Elsewhere the caret goes there. }
procedure TTyCustomRichEdit.PlainClick(X, Y: Integer; AQ: TTyRichPos; AAtEnd: Boolean;
  AObj: TTyRichPos);
begin
  if AObj >= 0 then
  begin
    Select(AObj, AObj + 1, False);
    FDragUnit := 4;
  end
  else
    Select(AQ, AQ, AAtEnd);
end;

{ ---- links ---- }

{ The target of a HYPERLINK field's instruction: "target", "#name" for \l "name" alone,
  "target#name" for both. \o and \t (each with its argument), \m, \n, \h and any other switch
  are passed over. An argument in quotes is taken whole (\\ and \" in it are \ and ", the field
  code's own escapes), one without up to the next space. False when it is no HYPERLINK, a quote
  is not closed, or it names neither a target nor a place. }
function LinkTarget(const AInstruction: string; out AURL: string): Boolean;
var
  i, n: Integer;
  tok, arg, target, name: string;
  quoted, q2, bad, hasTarget, hasName: Boolean;
  sw: Char;

  function NextToken(out AText: string; out AQuoted: Boolean): Boolean;
  begin
    AText := '';
    AQuoted := False;
    while (i <= n) and (AInstruction[i] in [' ', #9, #10, #13]) do Inc(i);
    if i > n then Exit(False);
    if AInstruction[i] = '"' then
    begin
      AQuoted := True;
      Inc(i);
      while (i <= n) and (AInstruction[i] <> '"') do
      begin
        if (AInstruction[i] = '\') and (i < n) and (AInstruction[i + 1] in ['\', '"']) then Inc(i);
        AText := AText + AInstruction[i];
        Inc(i);
      end;
      if i > n then bad := True;
      Inc(i);
    end
    else
      while (i <= n) and not (AInstruction[i] in [' ', #9, #10, #13]) do
      begin
        AText := AText + AInstruction[i];
        Inc(i);
      end;
    Result := True;
  end;

begin
  Result := False;
  AURL := '';
  i := 1;
  n := Length(AInstruction);
  bad := False;
  if not NextToken(tok, quoted) or quoted or not SameText(tok, 'HYPERLINK') then Exit;
  target := '';
  name := '';
  hasTarget := False;
  hasName := False;
  while NextToken(tok, quoted) do
  begin
    if bad then Exit;
    if not quoted and (Length(tok) >= 2) and (tok[1] = '\') then
    begin
      sw := LowerCase(Copy(tok, 2, 1))[1];
      if sw in ['l', 'o', 't'] then
      begin
        if not NextToken(arg, q2) or bad then Exit;
        if sw = 'l' then
        begin
          name := arg;
          hasName := True;
        end;
      end;
      Continue;
    end;
    if not hasTarget then
    begin
      target := tok;
      hasTarget := True;
    end;
  end;
  if bad then Exit;
  if target <> '' then
  begin
    AURL := target;
    if hasName and (name <> '') then AURL := AURL + '#' + name;
  end
  else if hasName and (name <> '') then
    AURL := '#' + name
  else
    Exit;
  Result := True;
end;

function TTyCustomRichEdit.LinkClickFires(AShift: TShiftState; AButton: TMouseButton): Boolean;
begin
  Result := False;
  if AShift * [ssDouble, ssTriple, ssQuad] <> [] then Exit;
  if (AButton <> mbLeft) and (AButton <> mbMiddle) then Exit;
  if AShift * [ssShift, ssAlt] <> [] then Exit;
  // (a page the user selects nothing on clicks its links as a viewer does)
  Result := FReadOnly or not FAllowSelection or (ssCtrl in AShift);
end;

function TTyCustomRichEdit.CharBoxAt(X, Y: Integer): TTyRichPos;
var
  t: TTyRichText;
  q, c, start: TTyRichPos;
  k, p: Integer;
  area, r0, r1: TRect;
  vx, vy: Int64;
  L: TTyBlockLayout;
  atEnd: Boolean;
begin
  Result := -1;
  q := PositionAtPoint(X, Y, atEnd);
  if q < 0 then Exit;
  t := FDoc.Text;
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  vx := (Int64(X) - area.Left) * FScale + FScrollX;
  vy := (Int64(Y) - area.Top) * FScale;
  // the hit test gives a character's nearer edge: the character after it or the one before
  for c := q downto q - 1 do
  begin
    if (c < 0) or (c >= t.Length) then Continue;
    p := t.ParaOfPos(c);
    // (a paragraph's end is no character to be on)
    if c = t.ParaStart(p) + t.ParaLength(p) then Continue;
    k := HeldBlockOf(c);
    if k < 0 then Continue;
    L := FBlocks[k].Layout;
    start := t.ParaStart(FBlocks[k].FirstPara);
    r0 := L.CaretRect(c - start, False);
    r1 := L.CaretRect(c + 1 - start, True);
    if (r0.Top = r1.Top) and (vx >= r0.Left) and (vx < r1.Left) and
      (vy - FBlocks[k].Top >= r0.Top) and (vy - FBlocks[k].Top < r0.Bottom) then
      Exit(c);
  end;
end;

function TTyCustomRichEdit.KnownField(AOpen: TTyRichPos): Integer;
var
  i: Integer;
begin
  for i := 0 to FKnownCount - 1 do
    if FKnown[i].Open = AOpen then
    begin
      Inc(FKnownClock);
      FKnown[i].Used := FKnownClock;
      Exit(i);
    end;
  Result := -1;
end;

function TTyCustomRichEdit.KnownAround(APos: TTyRichPos; ADepth: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to FKnownCount - 1 do
    if (FKnown[i].Depth = ADepth) and (FKnown[i].Close >= 0) and (FKnown[i].Open < APos) and
      (APos <= FKnown[i].Close) then
    begin
      Inc(FKnownClock);
      FKnown[i].Used := FKnownClock;
      Exit(i);
    end;
  Result := -1;
end;

{ The field whose open mark is at AOpen kept: its instruction read once (only up to its end, a
  table of contents' group may be megabytes), whether it is a link and its target. }
function TTyCustomRichEdit.KnowField(AOpen, AClose: TTyRichPos; ADepth: Integer): Integer;
const
  CKnownMax = 64;
var
  o: TTyRichObject;
  url: string;
  i: Integer;
  oldest: Int64;
begin
  Result := KnownField(AOpen);
  if Result < 0 then
  begin
    if FKnownCount >= CKnownMax then
    begin
      // the one asked for longest ago that this look-up and the place looked at do not need
      oldest := FKnownCall;
      for i := 0 to FKnownCount - 1 do
        if (FKnown[i].Used < oldest) and not ((FKnown[i].Close >= 0) and
          (FKnown[i].Open < FKnownAt) and (FKnownAt <= FKnown[i].Close)) then
        begin
          oldest := FKnown[i].Used;
          Result := i;
        end;
    end;
    if Result < 0 then
    begin
      if FKnownCount >= Length(FKnown) then SetLength(FKnown, FKnownCount * 2 + 8);
      Result := FKnownCount;
      Inc(FKnownCount);
    end;
    Inc(FKnownClock);
    FKnown[Result].Used := FKnownClock;
    FKnown[Result].Open := AOpen;
    FKnown[Result].Close := -1;
    FKnown[Result].Depth := -1;
    o := FDoc.ObjectAt(AOpen);
    Inc(FLinkReads);
    url := '';
    FKnown[Result].Link := (o is TTyRichFieldMark) and
      LinkTarget(TyRichFieldInstruction(FDoc, TTyRichFieldMark(o)), url);
    FKnown[Result].URL := url;
  end;
  if AClose >= 0 then FKnown[Result].Close := AClose;
  if ADepth >= 0 then FKnown[Result].Depth := ADepth;
end;

{ The fields around character AChar: those opened in its paragraph before it (and not closed),
  innermost first, from the paragraph's runs; then those open at the paragraph's start that
  are still open at it, found outward (TTyRichDocument.FieldRangeAt: a field's own
  paragraphs looked up) and kept, so that the next paragraph of a table of contents finds them
  known. The first that is a link counts. }
function TTyCustomRichEdit.LinkOfChar(AChar: TTyRichPos; out AOpen: TTyRichPos;
  out AURL: string): Boolean;
var
  t: TTyRichText;
  p, i, j, k, nOpen, depth, outer, d: Integer;
  ps, at, o, c: TTyRichPos;
  runs: TTyRunArray;
  opens: array of TTyRichPos;
begin
  Result := False;
  AOpen := -1;
  AURL := '';
  t := FDoc.Text;
  if (AChar < 0) or (AChar >= t.Length) then Exit;
  if FKnownState <> FDoc.ContentState then
  begin
    FKnownState := FDoc.ContentState;
    FKnownCount := 0;
  end;
  // (what this look-up asks for from now on is not given up to it)
  Inc(FKnownClock);
  FKnownCall := FKnownClock;
  FKnownAt := AChar;
  p := t.ParaOfPos(AChar);
  ps := t.ParaStart(p);
  FDoc.BeginRead;
  try
    runs := FDoc.RunsOf(p);
    depth := FDoc.ParaFieldDepth(p);
    // (a paragraph with no mark and outside every field: no link, nothing more read)
    if depth = 0 then
    begin
      i := 0;
      while (i <= High(runs)) and not (runs[i].Obj is TTyRichFieldMark) do Inc(i);
      if i > High(runs) then Exit;
    end;
    opens := nil;
    SetLength(opens, Length(runs));
    nOpen := 0;
    outer := depth;
    for i := 0 to High(runs) do
    begin
      if ps + runs[i].Start >= AChar then Break;
      if not (runs[i].Obj is TTyRichFieldMark) then Continue;
      if TTyRichFieldMark(runs[i].Obj).Kind = rfmOpen then
      begin
        opens[nOpen] := ps + runs[i].Start;
        Inc(nOpen);
      end
      else if nOpen > 0 then
        Dec(nOpen)
      else
        Dec(outer);
    end;
    for j := nOpen - 1 downto 0 do
    begin
      k := KnowField(opens[j], -1, -1);
      if FKnown[k].Link then
      begin
        AOpen := opens[j];
        AURL := FKnown[k].URL;
        Exit(True);
      end;
    end;
    at := ps;
    d := depth;
    while d >= 1 do
    begin
      k := KnownAround(at, d);
      if k < 0 then
      begin
        Inc(FLinkSearches);
        if not FDoc.FieldRangeAt(at, o, c) then Break;
        k := KnowField(o, c, d);
      end;
      // (one closed in the paragraph before the character is not around it)
      if (d <= outer) and FKnown[k].Link then
      begin
        AOpen := FKnown[k].Open;
        AURL := FKnown[k].URL;
        Exit(True);
      end;
      at := FKnown[k].Open;
      Dec(d);
    end;
  finally
    FDoc.EndRead;
  end;
end;

function TTyCustomRichEdit.LinkAtPoint(X, Y: Integer; out AURL: string): Boolean;
var
  c, o: TTyRichPos;
begin
  AURL := '';
  Result := False;
  if ViewBehind then Exit;
  c := CharBoxAt(X, Y);
  if c < 0 then Exit;
  Result := LinkOfChar(c, o, AURL);
end;

function TTyCustomRichEdit.GetFieldRange(APos: TTyRichPos; var AStart, ALength: TTyRichPos;
  var AInstruction: string): Boolean;
var
  o, c: TTyRichPos;
  m: TTyRichObject;
begin
  Result := FDoc.FieldRangeAt(APos, o, c);
  if not Result then Exit;
  AStart := o;
  ALength := c - o + 1;
  FDoc.BeginRead;
  try
    m := FDoc.ObjectAt(o);
    if m is TTyRichFieldMark then AInstruction := TyRichFieldInstruction(FDoc, TTyRichFieldMark(m))
    else AInstruction := '';
  finally
    FDoc.EndRead;
  end;
end;

{ ---- making, changing and removing links ---- }

function LinkTextBreaks(const S: string): Boolean;
begin
  Result := (Pos(#13, S) > 0) or (Pos(#10, S) > 0);
end;

function TTyCustomRichEdit.IsLinkField(AOpen: TTyRichPos; out AURL: string): Boolean;
var
  m: TTyRichObject;
begin
  AURL := '';
  Result := False;
  if (AOpen < 0) or (AOpen >= FDoc.Text.Length) then Exit;
  FDoc.BeginRead;
  try
    m := FDoc.ObjectAt(AOpen);
    Result := (m is TTyRichFieldMark) and (TTyRichFieldMark(m).Kind = rfmOpen) and
      LinkTarget(TyRichFieldInstruction(FDoc, TTyRichFieldMark(m)), AURL);
  finally
    FDoc.EndRead;
  end;
end;

{ How far back from a place the open mark of a field around it is looked for, in paragraphs
  (passed by their depths, without reading them): a link's text is short; a field that began
  further back - a table of contents, a field around most of a file - is taken for no link,
  so that laying out or asking at a place in it never walks the field. }
const
  CRichLinkLookBack = 64;

function TTyCustomRichEdit.FieldOpenNear(APos: TTyRichPos; ADepth: Integer): TTyRichPos;
var
  t: TTyRichText;
  k, j, depth, s, low, stop: Integer;
  ps: TTyRichPos;
  runs: TTyRunArray;
  found: TTyRichPos;

  procedure Walk(AUpTo: TTyRichPos);
  var
    i: Integer;
  begin
    found := -1;
    for i := 0 to High(runs) do
    begin
      if ps + runs[i].Start >= AUpTo then Break;
      if not (runs[i].Obj is TTyRichFieldMark) then Continue;
      if TTyRichFieldMark(runs[i].Obj).Kind = rfmOpen then
      begin
        Inc(depth);
        if depth = ADepth then found := ps + runs[i].Start;
      end
      else
      begin
        Dec(depth);
        if depth < ADepth then found := -1;
      end;
    end;
  end;

begin
  Result := -1;
  t := FDoc.Text;
  if (ADepth <= 0) or (APos < 0) or (APos > t.Length) then Exit;
  FDoc.BeginRead;
  try
    k := t.ParaOfPos(APos);
    ps := t.ParaStart(k);
    runs := FDoc.RunsOf(k);
    depth := FDoc.ParaFieldDepth(k);
    // (a paragraph that starts outside the field: its open mark is in it, or nowhere)
    s := depth;
    Walk(APos);
    if (found >= 0) or (s < ADepth) then Exit(found);
    stop := k - CRichLinkLookBack;
    if stop < 0 then stop := 0;
    for j := k - 1 downto stop do
    begin
      FDoc.ParaFieldDepths(j, s, low);
      if low >= ADepth then Continue;
      runs := FDoc.RunsOf(j);
      ps := t.ParaStart(j);
      depth := s;
      Walk(High(Int64));
      Exit(found);
    end;
  finally
    FDoc.EndRead;
  end;
end;

function TTyCustomRichEdit.LayoutLinkField(AAt: TTyRichPos; ADepth: Integer): Boolean;
var
  url: string;
  o: TTyRichPos;
begin
  if ADepth <= 0 then Exit(IsLinkField(AAt, url));
  o := FieldOpenNear(AAt, ADepth);
  Result := (o >= 0) and IsLinkField(o, url);
end;

function TTyCustomRichEdit.LinkAtSelection(out AStart, ALength: TTyRichPos;
  out AURL: string): Boolean;
var
  s, e, p, o, c, len: TTyRichPos;
  m: TTyRichObject;
  url: string;
  n: Integer;

  function Take(AO, AC: TTyRichPos): Boolean;
  begin
    Result := IsLinkField(AO, url);
    if not Result then Exit;
    AStart := AO;
    ALength := AC - AO + 1;
    AURL := url;
  end;

  function OpenAt(AAt: TTyRichPos): Boolean;
  begin
    m := FDoc.ObjectAt(AAt);
    Result := (m is TTyRichFieldMark) and (TTyRichFieldMark(m).Kind = rfmOpen);
  end;

begin
  Result := False;
  AStart := 0;
  ALength := 0;
  AURL := '';
  if ViewBehind then Exit;
  len := FDoc.Text.Length;
  s := GetSelStart;
  e := s + GetSelLength;
  FDoc.BeginRead;
  try
    // a whole link selected (from the place before its open mark to the one after its close)
    if (e > s) and (s < len) and OpenAt(s) then
    begin
      c := FDoc.FieldPartner(s);
      if (c = e - 1) and Take(s, c) then Exit(True);
    end;
    { the links whose text holds the selection, innermost first; only a link's own close mark
      is looked for (a link is short), never that of a long field around it }
    p := s;
    n := FDoc.FieldDepthAt(p);
    while n > 0 do
    begin
      o := FieldOpenNear(p, n);
      if o < 0 then Break;
      if IsLinkField(o, url) then
      begin
        c := FDoc.FieldPartner(o);
        if (c >= 0) and (e <= c) and Take(o, c) then Exit(True);
      end;
      p := o;
      Dec(n);
    end;
    // a caret right before or right after a link (where it rests at the link's edges)
    if e = s then
    begin
      if (s < len) and OpenAt(s) then
      begin
        c := FDoc.FieldPartner(s);
        if (c >= 0) and Take(s, c) then Exit(True);
      end;
      if s > 0 then
      begin
        m := FDoc.ObjectAt(s - 1);
        if (m is TTyRichFieldMark) and (TTyRichFieldMark(m).Kind = rfmClose) then
        begin
          o := FDoc.FieldPartner(s - 1);
          if (o >= 0) and Take(o, s - 1) then Exit(True);
        end;
      end;
    end;
  finally
    FDoc.EndRead;
  end;
end;

function TTyCustomRichEdit.LinkActionsOpen: Boolean;
begin
  Result := not FReadOnly and IsEnabled and not ViewBehind and (RefusalReason = '') and
    not PlainTextDocument;
end;

function TTyCustomRichEdit.LinkPlaceRefusal(AStart, ALen: TTyRichPos): string;
var
  t: TTyRichText;
  k, i: Integer;
  ps: TTyRichPos;
  runs: TTyRunArray;
begin
  if not FDoc.CanChange(AStart, 0) then Exit(ChangeRefusalText(AStart, 0));
  if (ALen > 0) and not FDoc.CanChange(AStart, ALen) then Exit(ChangeRefusalText(AStart, ALen));
  t := FDoc.Text;
  k := t.ParaOfPos(AStart);
  ps := t.ParaStart(k);
  // (across paragraphs, and so across table cells)
  if AStart + ALen > ps + t.ParaLength(k) then Exit(rsRichEditRefusedLinkParagraphs);
  Result := '';
  if ALen = 0 then Exit;
  runs := FDoc.RunsOf(k);
  for i := 0 to High(runs) do
    if (runs[i].Obj is TTyRichFieldMark) and (ps + runs[i].Start >= AStart) and
      (ps + runs[i].Start < AStart + ALen) then
      Exit(rsRichEditRefusedLinkAroundField);
end;

function TTyCustomRichEdit.MakeInsertLink(var APlace: TTyRichEditPlace): TTyRichCommand;
var
  s, n: TTyRichPos;
  reason: string;
begin
  Result := nil;
  if PlainTextDocument then reason := rsRichEditRefusedPlainLink
  else if (FLinkArgURL = '') or (FLinkArgURL = '#') or LinkTextBreaks(FLinkArgURL) then
    reason := rsRichEditRefusedLinkAddress
  else
  begin
    s := GetSelStart;
    n := GetSelLength;
    reason := LinkPlaceRefusal(s, n);
    if (reason = '') and LinkTextBreaks(FLinkArgText) then
      reason := rsRichEditRefusedLinkParagraphs;
  end;
  if reason <> '' then
  begin
    EditRefused(reason);
    Exit;
  end;
  // the editor's look: what a link made in Word looks like
  Result := TTyRichInsertLink.Create(s, n, FLinkArgURL, FLinkArgText, rllWordBlue);
end;

function TTyCustomRichEdit.MakeSetLink(var APlace: TTyRichEditPlace): TTyRichCommand;
var
  o, l: TTyRichPos;
  url, reason: string;
begin
  Result := nil;
  o := -1;
  l := 0;
  url := '';
  if not LinkAtSelection(o, l, url) then reason := rsRichEditRefusedNoLink
  else if not FDoc.CanChange(o, l) then reason := ChangeRefusalText(o, l)
  else if (FLinkArgURL = '') or (FLinkArgURL = '#') or LinkTextBreaks(FLinkArgURL) then
    reason := rsRichEditRefusedLinkAddress
  else if LinkTextBreaks(FLinkArgText) then reason := rsRichEditRefusedLinkParagraphs
  else reason := '';
  if reason <> '' then
  begin
    EditRefused(reason);
    Exit;
  end;
  Result := TTyRichSetLink.Create(o, FLinkArgURL, FLinkArgText);
end;

function TTyCustomRichEdit.MakeRemoveLink(var APlace: TTyRichEditPlace): TTyRichCommand;
var
  o, l: TTyRichPos;
  url, reason: string;
begin
  Result := nil;
  o := -1;
  l := 0;
  url := '';
  if not LinkAtSelection(o, l, url) then reason := rsRichEditRefusedNoLink
  else if not FDoc.CanChange(o, l) then reason := ChangeRefusalText(o, l)
  else reason := '';
  if reason <> '' then
  begin
    EditRefused(reason);
    Exit;
  end;
  Result := TTyRichRemoveLink.Create(o);
  // what was the link's text, selected (its two marks gone)
  APlace.Anchor := o;
  APlace.Caret := o + l - 2;
end;

function TTyCustomRichEdit.InsertLink(const AURL: string; const AText: string): Boolean;
begin
  FLinkArgURL := AURL;
  FLinkArgText := AText;
  Result := RunUserEdit(@MakeInsertLink);
end;

function TTyCustomRichEdit.SetLink(const AURL: string; const AText: string): Boolean;
begin
  FLinkArgURL := AURL;
  FLinkArgText := AText;
  Result := RunUserEdit(@MakeSetLink);
end;

function TTyCustomRichEdit.RemoveLink: Boolean;
begin
  Result := RunUserEdit(@MakeRemoveLink);
end;

function TTyCustomRichEdit.CanInsertLink: Boolean;
begin
  Result := LinkActionsOpen and (LinkPlaceRefusal(GetSelStart, GetSelLength) = '');
end;

function TTyCustomRichEdit.CanEditLink: Boolean;
var
  o, l: TTyRichPos;
  url: string;
begin
  o := -1;
  l := 0;
  url := '';
  Result := LinkActionsOpen and LinkAtSelection(o, l, url) and FDoc.CanChange(o, l);
end;

{ ---- bookmarks ---- }

function TTyCustomRichEdit.BookmarkCount(AIncludeHidden: Boolean): Integer;
begin
  Result := FBkmIndex.Count(AIncludeHidden);
end;

function TTyCustomRichEdit.BookmarkName(AIndex: Integer; AIncludeHidden: Boolean): string;
begin
  if (AIndex < 0) or (AIndex >= FBkmIndex.Count(AIncludeHidden)) then
    raise ETyRichEdit.CreateFmt('Bookmark index %d out of 0..%d', [AIndex,
      FBkmIndex.Count(AIncludeHidden) - 1]);
  Result := FBkmIndex.Name(AIndex, AIncludeHidden);
end;

function TTyCustomRichEdit.FindBookmark(const AName: string; out AStart,
  AEnd: TTyRichPos): Boolean;
begin
  Result := TyRichFindBookmark(FDoc, AName, AStart, AEnd);
end;

function TTyCustomRichEdit.GoToBookmark(const AName: string): Boolean;
var
  s, e, q: TTyRichPos;
begin
  Result := False;
  if ViewBehind then Exit;
  // a move of the user's: what is being composed goes in first; it edits nothing
  EndCompositionForUser;
  if ViewBehind or not TyRichFindBookmark(FDoc, AName, s, e) then Exit;
  q := SnapPos(s);
  Select(q, q, False);
  // a jump, not a find: the reader starts reading at the target
  FWishValid := False;
  ShowCaretAtTop;
  CaretMoved;
  DoSelectionChange;
  Result := True;
end;

procedure TTyCustomRichEdit.ShowCaretAtTop;
var
  r: TRect;
begin
  if ViewBehind then Exit;
  Settle;
  if (FViewH <= 0) or (FBlockCount = 0) then Exit;
  if ShownCaretRaster(r) and (r.Top >= 0) and (r.Bottom <= FViewH) and (r.Top < FViewH div 3) then
  begin
    // where the eye is already: no scroll (only across, if the caret is out of view)
    if (r.Left < 0) or (r.Right > FViewW) then ScrollCaretIntoView;
    Exit;
  end;
  if not ShownCaretRaster(r) then
  begin
    // not laid out: to its paragraph by the height index first
    ScrollRasterTo(FDoc.Text.ParaTop(FDoc.Text.ParaOfPos(FCaret)));
    Settle;
    if not ShownCaretRaster(r) then Exit;
  end;
  // its line's top at the view's top (the scroll stops at the document's end by itself)
  if r.Top <> 0 then ScrollRasterBy(r.Top);
  Settle;
  if ShownCaretRaster(r) and ((r.Left < 0) or (r.Right > FViewW)) then ScrollCaretIntoView;
end;

{ ---- objects' clicks ---- }

function TTyCustomRichEdit.ObjectPosAtPoint(X, Y: Integer): TTyRichPos;
var
  q: TTyRichPos;
  atEnd: Boolean;
begin
  Result := -1;
  if ViewBehind then Exit;
  q := HitClient(X, Y, atEnd);
  if q < 0 then Exit;
  // (an object's box: one with no width has none to be on)
  Result := ObjectAt(X, Y, Math.Min(q, FDoc.Text.Length));
end;

function TTyCustomRichEdit.ObjectAtPoint(X, Y: Integer; out APos: TTyRichPos): TTyRichObject;
begin
  Result := nil;
  APos := ObjectPosAtPoint(X, Y);
  if APos < 0 then Exit;
  Result := FDoc.ObjectAt(APos);
  if Result = nil then APos := -1;
end;

function TTyRichObjectClick.PointInPicture(AWidth, AHeight: Integer): TPoint;
var
  w, h: Integer;
begin
  Result := Types.Point(0, 0);
  w := Bounds.Right - Bounds.Left;
  h := Bounds.Bottom - Bounds.Top;
  if (w <= 0) or (h <= 0) or (AWidth <= 0) or (AHeight <= 0) then Exit;
  Result.X := Math.Max(0, Math.Min(AWidth - 1, Int64(Point.X - Bounds.Left) * AWidth div w));
  Result.Y := Math.Max(0, Math.Min(AHeight - 1, Int64(Point.Y - Bounds.Top) * AHeight div h));
end;

function TTyCustomRichEdit.ObjectClientRect(APos: TTyRichPos; out ARect: TRect): Boolean;
var
  k: Integer;
  r: TRect;
begin
  ARect := Rect(0, 0, 0, 0);
  Result := False;
  if ViewBehind or not FViewValid then Exit;
  k := HeldBlockOf(APos);
  if k < 0 then Exit;
  if not FBlocks[k].Layout.ObjectBox(APos - FDoc.Text.ParaStart(FBlocks[k].FirstPara), r) then
    Exit;
  ARect := ClientOf(TextArea(Rect(0, 0, Width, Height), ViewPPI), Int64(r.Left) - FScrollX,
    Int64(FBlocks[k].Top) + r.Top, Int64(r.Right) - FScrollX, Int64(FBlocks[k].Top) + r.Bottom);
  Result := True;
end;

function TTyCustomRichEdit.FireObjectEvent(ADouble: Boolean; APos: TTyRichPos;
  AButton: TMouseButton; AShift: TShiftState; X, Y: Integer): Boolean;
var
  info: TTyRichObjectClick;
  obj: TTyRichObject;
  handled: Boolean;
  h: TTyRichObjectClickEvent;

  procedure Fire;
  begin
    h(Self, info, handled);
  end;

begin
  Result := False;
  if ADouble then h := FOnObjectDblClick else h := FOnObjectClick;
  if not Assigned(h) or (APos < 0) or (APos >= FDoc.Text.Length) then Exit;
  obj := FDoc.ObjectAt(APos);
  if obj = nil then Exit;
  info := Default(TTyRichObjectClick);
  info.RichObject := obj;
  info.Pos := APos;
  info.Button := AButton;
  info.Shift := AShift;
  info.Point := Types.Point(X, Y);
  ObjectClientRect(APos, info.Bounds);
  handled := False;
  // (held for the handler: one that loads another document does not free it under it)
  obj.AddRef;
  try
    CallHandler(@Fire);
  finally
    obj.Release;
  end;
  Result := handled;
end;

function TTyCustomRichEdit.ObjectRelease(AButton: TMouseButton; AShift: TShiftState;
  X, Y: Integer): Boolean;
var
  at: TTyRichPos;
begin
  Result := False;
  at := FObjPressAt;
  FObjPressAt := -1;
  if (at < 0) or (AButton <> FObjPressButton) then Exit;
  // a drag (past its threshold) or a resize between: no click
  if (Abs(X - FObjPressPoint.X) > DragThreshold) or (Abs(Y - FObjPressPoint.Y) > DragThreshold) then
    Exit;
  if ObjectPosAtPoint(X, Y) <> at then Exit;
  Result := FireObjectEvent(False, at, AButton, AShift, X, Y);
end;

function TTyCustomRichEdit.CanEditBookmarks: Boolean;
begin
  Result := not FReadOnly and IsEnabled and not ViewBehind and (RefusalReason = '') and
    not PlainTextDocument;
end;

function TTyCustomRichEdit.MakeAddBookmark(var APlace: TTyRichEditPlace): TTyRichCommand;
var
  s, n: TTyRichPos;
  reason: string;
begin
  Result := nil;
  s := GetSelStart;
  n := GetSelLength;
  if PlainTextDocument then reason := rsRichEditRefusedPlainBookmark
  else if not TyRichBookmarkNameValid(FBkmArgName) then reason := rsRichEditRefusedBookmarkName
  else if not FDoc.CanChange(s, 0) then reason := ChangeRefusalText(s, 0)
  else if not FDoc.CanChange(s + n, 0) then reason := ChangeRefusalText(s + n, 0)
  else reason := '';
  if reason <> '' then
  begin
    EditRefused(reason);
    Exit;
  end;
  Result := TTyRichAddBookmark.Create(s, n, FBkmArgName);
  // the selection stays on what it held (moved over the marks that went in, as by any edit)
  APlace.Anchor := CRichPlaceStays;
  APlace.Caret := CRichPlaceStays;
end;

function TTyCustomRichEdit.MakeDeleteBookmark(var APlace: TTyRichEditPlace): TTyRichCommand;
var
  s, e: TTyRichPos;
  reason: string;
begin
  Result := nil;
  if PlainTextDocument then reason := rsRichEditRefusedPlainBookmark
  else if not TyRichFindBookmark(FDoc, FBkmArgName, s, e) then reason := rsRichEditRefusedNoBookmark
  else if not FDoc.CanChange(s, 1) then reason := ChangeRefusalText(s, 1)
  else if not FDoc.CanChange(e, 1) then reason := ChangeRefusalText(e, 1)
  else reason := '';
  if reason <> '' then
  begin
    EditRefused(reason);
    Exit;
  end;
  Result := TTyRichDeleteBookmark.Create(FBkmArgName);
  APlace.Anchor := CRichPlaceStays;
  APlace.Caret := CRichPlaceStays;
end;

function TTyCustomRichEdit.MakeRenameBookmark(var APlace: TTyRichEditPlace): TTyRichCommand;
var
  s, e, s2, e2: TTyRichPos;
  reason: string;
begin
  Result := nil;
  if PlainTextDocument then reason := rsRichEditRefusedPlainBookmark
  else if not TyRichBookmarkNameValid(FBkmArgNew) then reason := rsRichEditRefusedBookmarkName
  else if not TyRichFindBookmark(FDoc, FBkmArgName, s, e) then reason := rsRichEditRefusedNoBookmark
  else if not TyRichSameBookmarkName(FBkmArgName, FBkmArgNew) and
    TyRichFindBookmark(FDoc, FBkmArgNew, s2, e2) then reason := rsRichEditRefusedBookmarkExists
  else if not FDoc.CanChange(s, 1) then reason := ChangeRefusalText(s, 1)
  else if not FDoc.CanChange(e, 1) then reason := ChangeRefusalText(e, 1)
  else reason := '';
  if reason <> '' then
  begin
    EditRefused(reason);
    Exit;
  end;
  Result := TTyRichRenameBookmark.Create(FBkmArgName, FBkmArgNew);
  APlace.Anchor := CRichPlaceStays;
  APlace.Caret := CRichPlaceStays;
end;

function TTyCustomRichEdit.AddBookmark(const AName: string): Boolean;
begin
  FBkmArgName := AName;
  Result := RunUserEdit(@MakeAddBookmark);
end;

function TTyCustomRichEdit.DeleteBookmark(const AName: string): Boolean;
begin
  FBkmArgName := AName;
  Result := RunUserEdit(@MakeDeleteBookmark);
end;

function TTyCustomRichEdit.RenameBookmark(const AOld, ANew: string): Boolean;
begin
  FBkmArgName := AOld;
  FBkmArgNew := ANew;
  Result := RunUserEdit(@MakeRenameBookmark);
end;

function TTyCustomRichEdit.LinkPress(AButton: TMouseButton; AShift: TShiftState;
  X, Y: Integer): Boolean;
var
  c, o: TTyRichPos;
  url: string;
begin
  Result := False;
  FLinkPressed := False;
  // (a disabled control takes no press at all: MouseDown; disabling it ends one, StopDrag)
  if ViewBehind or not LinkClickFires(AShift, AButton) then Exit;
  c := CharBoxAt(X, Y);
  if (c < 0) or not LinkOfChar(c, o, url) then Exit;
  FLinkPressed := True;
  FLinkButton := AButton;
  FLinkPoint := Point(X, Y);
  FLinkShift := AShift;
  FLinkOpen := o;
  FLinkURL := url;
  Result := True;
end;

procedure TTyCustomRichEdit.LinkRelease(AButton: TMouseButton; X, Y: Integer);
var
  c, o: TTyRichPos;
  url: string;

  procedure Fire;
  begin
    FOnLinkClick(Self, url, AButton);
  end;

begin
  if not FLinkPressed or (AButton <> FLinkButton) then Exit;
  FLinkPressed := False;
  if not IsEnabled or ViewBehind then Exit;
  // released on the link it was pressed on: the click
  c := CharBoxAt(X, Y);
  if (c < 0) or not LinkOfChar(c, o, url) or (o <> FLinkOpen) then Exit;
  // (a handler that frees the control ends the call here: CallHandler)
  if Assigned(FOnLinkClick) then CallHandler(@Fire);
  FollowLink(url);
end;

procedure TTyCustomRichEdit.FollowLink(const AURL: string);
var
  bk: string;
  allow: Boolean;
  s, e: TTyRichPos;

  procedure Ask;
  begin
    FOnFollowLink(Self, bk, allow);
  end;

begin
  // a place of this document only: "#name" (a target with a place is the application's)
  if not FFollowBookmarkLinks or (Length(AURL) < 2) or (AURL[1] <> '#') then Exit;
  bk := Copy(AURL, 2, MaxInt);
  // no such bookmark: nothing happens, nothing is asked
  if not FindBookmark(bk, s, e) then Exit;
  allow := True;
  if Assigned(FOnFollowLink) then CallHandler(@Ask);
  if allow then GoToBookmark(bk);
end;

{ A press on a link moved past the drag threshold before its release: no click - the press it
  would have been with no link there, at its own place (a left one: the caret there and a drag
  of the selection's end, or a drag of the selection it was pressed in). }
procedure TTyCustomRichEdit.ReplayPress;
var
  q, o: TTyRichPos;
  atEnd: Boolean;
begin
  if ViewBehind then Exit;
  q := HitClient(FLinkPoint.X, FLinkPoint.Y, atEnd);
  q := Math.Min(q, FDoc.Text.Length);
  if q < 0 then Exit;
  FDragUnit := 1;
  o := ObjectAt(FLinkPoint.X, FLinkPoint.Y, q);
  if DragStartOpen and PressInSelection(FLinkPoint.X, FLinkPoint.Y) then
  begin
    FDragPending := True;
    FPressClickOwed := True;
    FPressPoint := FLinkPoint;
    FPressPlace := q;
    FPressAtEnd := atEnd;
    FDragPressObj := o;
    Exit;
  end;
  PlainClick(FLinkPoint.X, FLinkPoint.Y, q, atEnd, o);
  FDragFrom := GetSelStart;
  FDragTo := GetSelStart + GetSelLength;
  FDragging := True;
  FWishValid := False;
  CaretMoved;
  DoSelectionChange;
end;

procedure TTyCustomRichEdit.PointerKeysChanged(AShift: TShiftState);
var
  c: TCursor;
begin
  FPointerShift := FPointerShift - [ssCtrl, ssShift, ssAlt, ssMeta] +
    AShift * [ssCtrl, ssShift, ssAlt, ssMeta];
  if not FPointerKnown or not IsEnabled or (csDesigning in ComponentState) then Exit;
  c := CursorAt(FPointerAt.X, FPointerAt.Y);
  if c = crHandPoint then FOverHandle := crHandPoint
  else if FOverHandle = crHandPoint then FOverHandle := crDefault
  else Exit;
  if inherited GetCursor = crIBeam then SetTempCursor(GetCursor);
end;

procedure TTyCustomRichEdit.StartDragTimer;
begin
  // (no drag begins in the form designer: MouseDown takes no press there)
  if not HandleAllocated then Exit;
  if FDragTimer = nil then
  begin
    FDragTimer := TTimer.Create(nil);
    FDragTimer.Interval := CRichDragScrollMs;
    FDragTimer.OnTimer := @DragScrollTick;
  end;
  FDragTimer.Enabled := True;
end;

procedure TTyCustomRichEdit.StopDrag;
begin
  FLinkPressed := False;
  CancelResize;
  FPressClickOwed := False;
  CancelSelectionDrag;
  { A session fed from elsewhere (another control's drag, another program's) ends too: the
    content, the window or the control's state it was over is gone. The feeder begins one
    again at its next move, over what is there then. }
  if FDropOffer <> nil then DropLeave;
  FDragging := False;
  if FDragTimer <> nil then FDragTimer.Enabled := False;
  if MouseCapture then MouseCapture := False;
end;

procedure TTyCustomRichEdit.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  area: TRect;
  c: TCursor;
begin
  if not IsEnabled then Exit;
  inherited MouseMove(Shift, X, Y);
  FPointerAt := Point(X, Y);
  FPointerShift := Shift;
  FPointerKnown := True;
  // a press on a link moved past the drag threshold: no click, the press it would have been
  if FLinkPressed and ((Abs(X - FLinkPoint.X) > DragThreshold) or
    (Abs(Y - FLinkPoint.Y) > DragThreshold)) then
  begin
    FLinkPressed := False;
    if FLinkButton = mbLeft then ReplayPress;
  end;
  // a press inside the selection: past the drag threshold the drag begins
  // (a move with no right button held lets the menu come again: see FEatMenu)
  if not (ssRight in Shift) then FEatMenu := False;
  if FDragPending and not ViewBehind and ((Abs(X - FPressPoint.X) > DragThreshold) or
    (Abs(Y - FPressPoint.Y) > DragThreshold)) then
    // (a handler of the background work it ended freed the control: nothing more)
    if not BeginSelectionDrag(X, Y, Shift) then Exit;
  // the drop's place, mark and verdict follow the pointer (the cursor below says it)
  if OwnDragging then DropOver(X, Y, Shift);
  // a press on a table's zone dragged: more rows, columns or cells
  if (FCellDrag <> 0) and (ssLeft in Shift) then TableZoneDrag(X, Y);
  TableHandleHover(X, Y);
  { The arrow over the padding (a cursor set by the user is left alone): GetCursor answers it
    from where the pointer was last seen, which is what LCL-Win32 shows on the window's
    set-cursor message. GTK, Qt and Cocoa set a window's cursor only when told: the
    temporary cursor tells them now (on Windows it sends that message, which asks GetCursor
    again). }
  c := CursorAt(X, Y);
  FOverPadding := c = crDefault;
  if (c = crSizeNWSE) or (c = crSizeNESW) or (c = crSizeNS) or (c = crSizeWE) or
    (c = crDrag) or (c = crMultiDrag) or (c = crNoDrop) or (c = crHandPoint) then
    FOverHandle := c
  else
    FOverHandle := crDefault;
  if inherited GetCursor = crIBeam then SetTempCursor(GetCursor);
  // a table edge's drag: its guide follows, nothing else
  if FEdgeDrag <> CEdgeNone then
  begin
    if not ViewBehind then EdgeMove(X, Y, Shift);
    Exit;
  end;
  // a drag of a handle: the outline follows, nothing else
  if FResizing then
  begin
    if not ViewBehind then MoveResize(X, Y, Shift);
    Exit;
  end;
  if not FDragging or OwnDragging then Exit;
  // inside the document's update the drag waits
  if ViewBehind then Exit;
  FDragPoint := Point(X, Y);
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  if (Y < area.Top) or (Y >= area.Bottom) or
    ((FWidestSeen > FViewW) and ((X < area.Left) or (X >= area.Right))) then
    StartDragTimer
  else if FDragTimer <> nil then
    FDragTimer.Enabled := False;
  ExtendDragTo(X, Y);
  FWishValid := False;
  CaretMoved;
  DoSelectionChange;
end;

procedure TTyCustomRichEdit.DragScrollTick(Sender: TObject);
var
  area: TRect;
  est, steps: Integer;
begin
  if FDropOffer <> nil then
  begin
    DropScrollTick;
    Exit;
  end;
  if not FDragging or not IsEnabled or not IsVisible then
  begin
    StopDrag;
    Exit;
  end;
  // inside the document's update: no query, the drag waits
  if ViewBehind then Exit;
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  est := Math.Max(1, FEstimate div Math.Max(1, FScale));
  // a line a tick, and one more for every line's height the pointer is further out
  steps := 0;
  if FDragPoint.Y < area.Top then steps := -(1 + (area.Top - FDragPoint.Y) div est)
  else if FDragPoint.Y >= area.Bottom then steps := 1 + (FDragPoint.Y - area.Bottom) div est;
  if steps <> 0 then ScrollRasterBy(Int64(steps) * Math.Max(1, FEstimate));
  if FWidestSeen > FViewW then
  begin
    steps := 0;
    if FDragPoint.X < area.Left then steps := -(1 + (area.Left - FDragPoint.X) div est)
    else if FDragPoint.X >= area.Right then steps := 1 + (FDragPoint.X - area.Right) div est;
    if steps <> 0 then SetScrollXRaster(FScrollX + steps * Math.Max(1, FEstimate));
  end;
  ExtendDragTo(FDragPoint.X, FDragPoint.Y);
  CaretMoved;
  DoSelectionChange;
end;

procedure TTyCustomRichEdit.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  life: TTyRichLife;

  procedure OtherRelease;
  begin
    if ObjectRelease(Button, Shift, X, Y) and (Button = mbRight) then FEatMenu := True;
  end;

  procedure Work;
  begin
    FCellDrag := 0;
    // a table edge's drag: its one command
    if FEdgeDrag <> CEdgeNone then
    begin
      EdgeRelease(X, Y, Shift);
      Exit;
    end;
    // a press on a link: its click, on the same link (nothing else)
    if FLinkPressed then
    begin
      LinkRelease(Button, X, Y);
      Exit;
    end;
    if FResizing then
      FinishResize(X, Y, Shift)
    else
    begin
      // an object's click: what the release still owes, not when handled
      if ObjectRelease(Button, Shift, X, Y) then
      begin
        FDragPending := False;
        FPressClickOwed := False;
      end;
      if life.Gone then Exit;
      // a press inside the selection let go without a drag: the click it was
      if FDragPending or FPressClickOwed then ReleasePending
      else if OwnDragging then DropOn(X, Y, Shift);
      if life.Gone then Exit;
      StopDrag;
    end;
  end;

begin
  inherited MouseUp(Button, Shift, X, Y);
  // (another button's release lets the menu come again; the right one's is its press's)
  if Button <> mbRight then FEatMenu := False;
  // the right and the middle button: an object's click (a handled right one: no menu)
  if (Button <> mbLeft) and not (FLinkPressed and (Button = FLinkButton)) then
  begin
    if FObjPressAt >= 0 then
    begin
      Guard(life, @OtherRelease);
      if life.Gone then Exit;
    end;
    Exit;
  end;
  // (a handler the release runs - a drop's, a click's report, a link's - may free the control)
  Guard(life, @Work);
end;

procedure TTyCustomRichEdit.CaptureChanged;
var
  life: TTyRichLife;

  procedure Work;
  begin
    if FDragPending or FPressClickOwed then ReleasePending
    else DropOn(FDropPoint.X, FDropPoint.Y, FDropShift);
  end;

begin
  inherited CaptureChanged;
  { The capture went elsewhere (a menu, another window): the drag is over. A drag of a handle:
    taken away with the button still down, nothing is done; the button already up, this is
    the release's own capture going - before, inside or after the button-up message, by
    widgetset - and the drag ends as the release ends it, at the pointer's last place (the
    release's MouseUp, if it comes after, finds no drag). }
  if FResizing and not MouseCapture then
    if LeftButtonHeld then CancelResize
    else FinishResize(FResizeLast.X, FResizeLast.Y, FResizeShift);
  // (a table edge's drag: the same)
  if (FEdgeDrag <> CEdgeNone) and not MouseCapture then
    if LeftButtonHeld then CancelEdgeDrag
    else EdgeRelease(FPointerAt.X, FPointerAt.Y, FPointerShift);
  { The same for a drag of the selection: taken away with the button down, it ends with
    nothing done; let go by the release itself, the release is done here - the drop at the
    pointer's last place with the keys last known (or the click a press without a drag
    was) - and the button-up after it finds nothing to do. }
  if (FDragPending or FPressClickOwed or OwnDragging) and not MouseCapture then
    if LeftButtonHeld then
    begin
      FPressClickOwed := False;
      CancelSelectionDrag;
    end
    else
    begin
      // (a handler the release runs may free the control: nothing of it is touched after)
      Guard(life, @Work);
      if life.Gone then Exit;
    end;
  if FDragging and not MouseCapture then StopDrag;
end;

procedure TTyCustomRichEdit.EnabledChanged;
begin
  inherited EnabledChanged;
  StopDrag;
  // disabled: what is being composed cannot go in any more - as ReadOnly set, it is dropped
  if not IsEnabled then EndComposition(False);
  // a disabled control's selected object shows no handles
  SyncObjectOverlay;
  ParagraphViewChanged;
end;

procedure TTyCustomRichEdit.VisibleChanged;
begin
  inherited VisibleChanged;
  StopDrag;
end;

{ ---- dragging the selection, and the receiving side of a drop ---- }

function TTyRichDropOffer.Flavours: TTyRichClipFlavours;
begin
  Result := [];
end;

function TTyRichDropOffer.ReadRtf: RawByteString;
begin
  Result := '';
end;

function TTyRichDropOffer.ReadPicture(AIndex: Integer; out AKind: TTyRichImageKind;
  out ABytes: TBytes): Boolean;
begin
  AKind := rikPng;
  ABytes := nil;
  Result := False;
end;

function TTyRichDropOffer.ReadText: string;
begin
  Result := '';
end;

function TTyRichDropOffer.Files: TStringArray;
begin
  Result := nil;
end;

function TTyRichDropOffer.FromOtherProgram: Boolean;
begin
  Result := False;
end;

function TTyRichDropOffer.Source: TTyCustomRichEdit;
begin
  Result := nil;
end;

function TTyRichDropOffer.SourceRange(out AFrom, ALen: TTyRichPos): Boolean;
begin
  AFrom := 0;
  ALen := 0;
  Result := False;
end;

function TTyRichDropOffer.Allowed: TTyRichDropEffects;
begin
  Result := [rdeCopy];
end;

procedure TTyRichDropOffer.Taken(AEffect: TTyRichDropEffect);
begin
end;

constructor TTyRichSelectionOffer.Create(AOwner: TTyCustomRichEdit; AFrom, ALen: TTyRichPos);
begin
  inherited Create;
  FOwner := AOwner;
  FFrom := AFrom;
  FLen := ALen;
  FMovable := True;
  FTaken := rdeNone;
end;

function TTyRichSelectionOffer.Flavours: TTyRichClipFlavours;
begin
  Result := [rcfRtf, rcfText];
end;

{ What a drop reads: the range - for a move the range the source's cut takes (the paragraph
  end kept before a table stays, and is not carried), as a cut and a paste would give it. }
function TTyRichSelectionOffer.ReadRange(out AFrom, ALen: TTyRichPos): Boolean;
begin
  AFrom := FFrom;
  ALen := FLen;
  if FDropAs = rdeMove then
  begin
    FOwner.FDoc.BeginRead;
    try
      if not FOwner.FDoc.UserRangeAllowed(AFrom, ALen) then ALen := 0;
    finally
      FOwner.FDoc.EndRead;
    end;
  end;
  Result := ALen > 0;
end;

// (cells: what their copy writes, a small table and tabbed text)
function TTyRichSelectionOffer.ReadRtf: RawByteString;
var
  f, n: TTyRichPos;
  area: TTyRichCellArea;
  txt: string;
begin
  Result := '';
  if not ReadRange(f, n) then Exit;
  if FOwner.RangeIsCells(f, n, area) and FOwner.CellsFlavours(area, Result, txt) then Exit;
  Result := FOwner.RangeRtf(f, n);
end;

function TTyRichSelectionOffer.ReadText: string;
var
  f, n: TTyRichPos;
  area: TTyRichCellArea;
  rtf: RawByteString;
begin
  Result := '';
  if not ReadRange(f, n) then Exit;
  if FOwner.RangeIsCells(f, n, area) and FOwner.CellsFlavours(area, rtf, Result) then Exit;
  Result := FOwner.RangeText(f, n);
end;

function TTyRichSelectionOffer.Source: TTyCustomRichEdit;
begin
  Result := FOwner;
end;

function TTyRichSelectionOffer.SourceRange(out AFrom, ALen: TTyRichPos): Boolean;
begin
  AFrom := FFrom;
  ALen := FLen;
  Result := True;
end;

function TTyRichSelectionOffer.Allowed: TTyRichDropEffects;
begin
  if FMovable then Result := [rdeMove, rdeCopy] else Result := [rdeCopy];
end;

procedure TTyRichSelectionOffer.Taken(AEffect: TTyRichDropEffect);
begin
  // (the source control removes a moved content once the target's drop has returned)
  FTaken := AEffect;
end;

type
  // the clipboard as a paste reads it: the control's own seams
  TTyRichClipboardOffer = class(TTyRichDropOffer)
  private
    FOwner: TTyCustomRichEdit;
  public
    constructor Create(AOwner: TTyCustomRichEdit);
    function Flavours: TTyRichClipFlavours; override;
    function ReadRtf: RawByteString; override;
    function ReadPicture(AIndex: Integer; out AKind: TTyRichImageKind;
      out ABytes: TBytes): Boolean; override;
    function ReadText: string; override;
  end;

constructor TTyRichClipboardOffer.Create(AOwner: TTyCustomRichEdit);
begin
  inherited Create;
  FOwner := AOwner;
end;

function TTyRichClipboardOffer.Flavours: TTyRichClipFlavours;
begin
  Result := FOwner.ClipboardFlavours;
end;

function TTyRichClipboardOffer.ReadRtf: RawByteString;
begin
  Result := FOwner.ReadClipboardRtf;
end;

function TTyRichClipboardOffer.ReadPicture(AIndex: Integer; out AKind: TTyRichImageKind;
  out ABytes: TBytes): Boolean;
begin
  Result := FOwner.ReadClipboardPicture(AIndex, AKind, ABytes);
end;

function TTyRichClipboardOffer.ReadText: string;
begin
  Result := FOwner.ReadClipboardText;
end;

function TTyCustomRichEdit.DragStartOpen: Boolean;
begin
  { Whatever makes every edit impossible makes no drag (the press is a plain click). ReadOnly
    does not: the selection can be dragged out as a copy (nothing is taken here). }
  Result := FDragDropEditing and (DragMode <> dmAutomatic) and IsEnabled and
    HasSelection and not ViewBehind and (RefusalReason = '');
end;

{ The point is on the selection as it is painted: its text (the paragraph end's mark too) or a
  selected object - only the block under the point is asked. }
function TTyCustomRichEdit.PressInSelection(X, Y: Integer): Boolean;
var
  area: TRect;
  s, k, i: Integer;
  lx, ly: Int64;
  a, b, start, stop: TTyRichPos;
  rs: TRectArray;
  t: TTyRichText;
begin
  Result := False;
  if not HasSelection or not FViewValid or (FBlockCount = 0) then Exit;
  if not PtInRect(TextWindowRect, Point(X, Y)) then Exit;
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  s := Math.Max(1, FScale);
  lx := (Int64(X) - area.Left) * s + FScrollX;
  ly := (Int64(Y) - area.Top) * s;
  a := GetSelStart;
  b := a + GetSelLength;
  t := FDoc.Text;
  for k := 0 to FBlockCount - 1 do
  begin
    if (ly < FBlocks[k].Top) or (ly >= FBlocks[k].Top + FBlocks[k].Height) then Continue;
    start := t.ParaStart(FBlocks[k].FirstPara);
    stop := t.ParaStart(FBlocks[k].LastPara) + t.ParaLength(FBlocks[k].LastPara);
    if (b <= start) or (a > stop) then Exit;
    rs := FBlocks[k].Layout.SelectionRects(Math.Max(a - start, 0),
      Math.Min(b - start, stop - start + 1));
    ly := ly - FBlocks[k].Top;
    for i := 0 to High(rs) do
      if (lx >= rs[i].Left) and (lx < rs[i].Right) and (ly >= rs[i].Top) and
        (ly < rs[i].Bottom) then
        Exit(True);
    Exit;
  end;
end;

procedure TTyCustomRichEdit.ReleasePending;
begin
  // (a press whose wait something else ended is still the click it was)
  if not FDragPending and not FPressClickOwed then Exit;
  FDragPending := False;
  FPressClickOwed := False;
  if ViewBehind then Exit;
  FDragUnit := 1;
  PlainClick(FPressPoint.X, FPressPoint.Y, FPressPlace, FPressAtEnd, FDragPressObj);
  FWishValid := False;
  CaretMoved;
  DoSelectionChange;
end;

function TTyCustomRichEdit.OwnDragging: Boolean;
begin
  Result := (FDropOffer <> nil) and FDropOwn;
end;

function TTyCustomRichEdit.DropActive: Boolean;
begin
  Result := FDropOffer <> nil;
end;

{ A press on the selection, or a drag of it beginning, is the user taking the document in
  hand, as the first character typed is: a background find or replace ends - cancelled, its
  event told - as an edit makes it end at its next turn; nothing changes the document or the
  selection under the press after that. Its handler may change things (or free the control:
  False, nothing to be touched any more). }
function TTyCustomRichEdit.EndBackgroundForUser: Boolean;
var
  life: TTyRichLife;
begin
  Result := True;
  if FFindKind = rfkNone then Exit;
  LifeEnter(life);
  try
    try
      EndFind(rfsCancelled, True);
    except
      on ETyRichGone do if TyRichGonePasses(life) then raise;
    end;
  finally
    if not life.Gone then LifeLeave(life);
  end;
  Result := not life.Gone;
end;

function TTyCustomRichEdit.BeginSelectionDrag(X, Y: Integer; AShift: TShiftState): Boolean;
var
  offer: TTyRichSelectionOffer;
  s, n: TTyRichPos;
begin
  Result := True;
  FDragPending := False;
  FPressClickOwed := False;
  // (begun while a background find or replace runs that the press did not end: it ends now)
  if FFindKind <> rfkNone then
  begin
    s := GetSelStart;
    n := GetSelLength;
    if not EndBackgroundForUser then Exit(False);
    // the drag begins only on what the handler left
    if not DragStartOpen or (GetSelStart <> s) or (GetSelLength <> n) then Exit;
  end;
  if FDropOffer <> nil then DropLeave;
  offer := TTyRichSelectionOffer.Create(Self, GetSelStart, GetSelLength);
  FDropOwn := True;
  try
    DropEnter(offer, X, Y, AShift);
  finally
    // (no session: the control takes no drop now)
    if FDropOffer <> offer then
    begin
      FDropOwn := False;
      offer.Free;
    end;
  end;
end;

procedure TTyCustomRichEdit.DropFollowPointer;
begin
  if (FDropOffer = nil) or FDropFollowing then Exit;
  FDropFollowing := True;
  try
    DropOver(FDropPoint.X, FDropPoint.Y, FDropShift);
  finally
    FDropFollowing := False;
  end;
end;

procedure TTyCustomRichEdit.CancelSelectionDrag;
begin
  FDragPending := False;
  if OwnDragging then DropLeave;
end;

function TTyCustomRichEdit.OwnDragRunning: Boolean;
begin
  Result := FResizing or FDragPending or OwnDragging or (FEdgeDrag <> 0);
end;

procedure TTyCustomRichEdit.EndOwnDrag;
begin
  FPressClickOwed := False;
  CancelEdgeDrag;
  CancelResize;
  CancelSelectionDrag;
end;

function IsDragModifier(AKey: Word): Boolean;
begin
  case AKey of
    VK_SHIFT, VK_LSHIFT, VK_RSHIFT, VK_CONTROL, VK_LCONTROL, VK_RCONTROL, VK_MENU, VK_LMENU,
    VK_RMENU, VK_LWIN, VK_RWIN: Result := True;
  else
    Result := False;
  end;
end;

function TTyCustomRichEdit.OwnDragKey(var Key: Word): Boolean;
begin
  Result := OwnDragRunning;
  if not Result then Exit;
  case Key of
    VK_ESCAPE:
      begin
        EndOwnDrag;
        Key := 0;
      end;
    // (KeyUp: a move again)
    VK_CONTROL, VK_LCONTROL, VK_RCONTROL:
      if OwnDragging then DropOver(FDropPoint.X, FDropPoint.Y, FDropShift + [ssCtrl]);
  else
    { Not ended and nothing done: no text, no caret move, no shortcut, no edit, and taken, so
      that LCL hands it to nothing after the control (the form's shortcuts and action lists,
      the default and cancel buttons, the application's handlers). }
    if not IsDragModifier(Key) then Key := 0;
  end;
end;

function TTyCustomRichEdit.DragThreshold: Integer;
begin
  // LCL's distance is for 96 PPI: the same distance on every screen
  Result := MulDiv(Mouse.DragThreshold, ViewPPI, 96);
end;

function TTyCustomRichEdit.DropCursor(AEffect: TTyRichDropEffect): TCursor;
begin
  case AEffect of
    rdeMove: Result := crDrag;
    rdeCopy: Result := crMultiDrag;
  else
    Result := crNoDrop;
  end;
end;

procedure TTyCustomRichEdit.ShowDropCursor;
begin
  if OwnDragging then FOverHandle := DropCursor(FDropEffect) else FOverHandle := crDefault;
  if inherited GetCursor = crIBeam then SetTempCursor(GetCursor);
end;

function TTyCustomRichEdit.DropPlaceAt(X, Y: Integer; out AAtEnd: Boolean): TTyRichPos;
var
  area: TRect;
begin
  AAtEnd := False;
  // the pointer held to the text: past an edge, the line along that edge (as a drag-select)
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  X := Math.Max(area.Left, Math.Min(X, area.Right - 1));
  Y := Math.Max(area.Top, Math.Min(Y, area.Bottom - 1));
  Result := HitClient(X, Y, AAtEnd);
  if Result > FDoc.Text.Length then Result := FDoc.Text.Length;
  // a place as the caret's: at a link's edge, outside it
  if Result >= 0 then Result := RestingPlace(Result);
end;

function TTyCustomRichEdit.DropEffectAt(AOffer: TTyRichDropOffer; APos: TTyRichPos;
  AShift: TShiftState): TTyRichDropEffect;
var
  f, n: TTyRichPos;
  al: TTyRichDropEffects;
  fl: TTyRichClipFlavours;
  asCopy: Boolean;
  files: TStringArray;
begin
  Result := rdeNone;
  if (AOffer = nil) or (APos < 0) or (APos > FDoc.Text.Length) then Exit;
  if not IsEnabled then Exit;
  al := AOffer.Allowed;
  { A file list: the application's when it asks for file lists (whatever the control's
    state), else pictures where a picture could go in - a copy, never a move. }
  files := AOffer.Files;
  if files <> nil then
  begin
    if not (rdeCopy in al) then Exit;
    if Assigned(FOnDropFiles) then Exit(rdeCopy);
    if FReadOnly or (RefusalReason <> '') or PlainTextDocument or
      not OfferedPictures(AOffer, files) or not FDoc.CanChange(APos, 0) then Exit;
    Exit(rdeCopy);
  end;
  if FReadOnly or (RefusalReason <> '') then Exit;
  if (AOffer.Source = Self) and AOffer.SourceRange(f, n) then
  begin
    { (no move allowed means the selection cannot be moved - FDropCuttable says so too: such
      a drop without Ctrl is nothing, as a move of it would be) }
    asCopy := (ssCtrl in AShift) and (rdeCopy in al);
    if asCopy then
    begin
      // its ends are places for a copy: it goes beside the content
      if not (rdeCopy in al) or ((APos > f) and (APos < f + n)) then Exit;
      Result := rdeCopy;
    end
    else
    begin
      // a move to its own place, or of what cannot be moved, is nothing
      if ((APos >= f) and (APos <= f + n)) or not FDropCuttable then Exit;
      Result := rdeMove;
    end;
  end
  else
  begin
    fl := AOffer.Flavours;
    if fl = [] then Exit;
    // a plain text document takes text only
    if PlainTextDocument and (fl * [rcfRtf, rcfText] = []) then Exit;
    // the system's convention: Ctrl a copy; otherwise a move where the source allows it
    if ((ssCtrl in AShift) or not (rdeMove in al)) and (rdeCopy in al) then Result := rdeCopy
    else if rdeMove in al then Result := rdeMove
    else if rdeCopy in al then Result := rdeCopy;
  end;
  if (Result <> rdeNone) and not FDoc.CanChange(APos, 0) then Result := rdeNone;
end;

function TTyCustomRichEdit.DropEnter(AOffer: TTyRichDropOffer; X, Y: Integer;
  AShift: TShiftState): TTyRichDropEffect;
var
  f, n: TTyRichPos;
begin
  Result := rdeNone;
  if (FDropOffer <> nil) and (FDropOffer <> AOffer) then
  begin
    // (a drag of the control's own is under way: it gives way)
    if FDropOwn then CancelSelectionDrag else DropLeave;
  end;
  if (AOffer = nil) or not IsEnabled or (csDesigning in ComponentState) then Exit;
  { Another program's offer is AcceptDrops' to take; the control's own drag, another
    control's and an offer the application feeds in are DragDropEditing's. }
  if AOffer.FromOtherProgram then
  begin
    if not FAcceptDrops then Exit;
  end
  else if not FDragDropEditing then
    Exit;
  { Read-only takes nothing - but its own selection may be dragged out (a session that feeds
    another control's), and a file list goes to the application when it asks for one. }
  if FReadOnly and (AOffer.Source <> Self) and
    not ((AOffer.Files <> nil) and Assigned(FOnDropFiles)) then Exit;
  FDropOffer := AOffer;
  FFilesOffer := nil;
  FDropPos := -1;
  FDropEffect := rdeNone;
  { This control's own selection is moved by its cut's rule: one that crosses a cell's edge
    (not whole rows), or that the document keeps, cannot move - asked once. Nor can a
    read-only control's: dropped elsewhere, it is a copy (the offer says so to the other
    control). }
  FDropCuttable := False;
  if (AOffer.Source = Self) and AOffer.SourceRange(f, n) and (n > 0) then
  begin
    FDoc.BeginRead;
    try
      FDropCuttable := FDoc.UserRangeAllowed(f, n) and (n > 0) and FDoc.CanChange(f, n);
    finally
      FDoc.EndRead;
    end;
  end;
  if (AOffer.Source = Self) and (AOffer is TTyRichSelectionOffer) then
  begin
    TTyRichSelectionOffer(AOffer).Movable := FDropCuttable and not FReadOnly;
    // the content it is of (a move elsewhere removes it only from that very content)
    TTyRichSelectionOffer(AOffer).FState := FDoc.ContentState;
  end;
  Result := DropOver(X, Y, AShift);
end;

function TTyCustomRichEdit.DropOver(X, Y: Integer; AShift: TShiftState): TTyRichDropEffect;
var
  area: TRect;
  band: Integer;
  q: TTyRichPos;
  atEnd, inside: Boolean;
begin
  Result := rdeNone;
  if FDropOffer = nil then Exit;
  FDropPoint := Point(X, Y);
  FDropShift := AShift;
  // inside the document's update the place waits
  if ViewBehind then Exit(FDropEffect);
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  { Inside the control near an edge of the text (half a line inside it, and the padding
    between it and the control's edge) the view scrolls, at the drag-select's timer and
    speeds; outside the control it does not, and nothing is a place there: no mark, "not here",
    a release does nothing. }
  inside := (X >= 0) and (X < Width) and (Y >= 0) and (Y < Height);
  band := Math.Max(1, (FEstimate div Math.Max(1, FScale)) div 2);
  if inside and ((Y < area.Top + band) or (Y >= area.Bottom - band) or ((FWidestSeen > FViewW) and
    ((X < area.Left + band) or (X >= area.Right - band)))) then
    StartDragTimer
  else if FDragTimer <> nil then
    FDragTimer.Enabled := False;
  if inside then q := DropPlaceAt(X, Y, atEnd)
  else
  begin
    q := -1;
    atEnd := False;
  end;
  FDropPos := q;
  FDropAtEnd := atEnd;
  if q < 0 then FDropEffect := rdeNone
  else FDropEffect := DropEffectAt(FDropOffer, q, AShift);
  // the control's own drag outside it: the rich edit under the pointer takes over (its verdict)
  if FDropOwn then FeedPeer(X, Y, AShift, inside);
  // the mark: its old place and its new one painted again, nothing else
  SyncObjectOverlay;
  if FDropOwn then ShowDropCursor;
  Result := FDropEffect;
  // (a session another control's drag feeds: that control's cursor says it)
  if not FDropOwn and (FDropOffer <> nil) and (FDropOffer.Source <> nil) and
    (FDropOffer.Source <> Self) then
    FDropOffer.Source.PeerVerdict(Self, FDropEffect);
end;

procedure TTyCustomRichEdit.DropLeave;
var
  o: TTyRichDropOffer;
  own: Boolean;
begin
  if FDropOffer = nil then Exit;
  // (the control's own drag: the session it fed in another control ends first)
  if FDropOwn then EndPeer;
  o := FDropOffer;
  own := FDropOwn;
  FDropOffer := nil;
  FFilesOffer := nil;
  FDropOwn := False;
  FDropEffect := rdeNone;
  FDropPos := -1;
  if FDragTimer <> nil then FDragTimer.Enabled := False;
  if not IsRectEmpty(FDropRect) then
  begin
    InvalidateTextRect(FDropRect.Left, FDropRect.Top, FDropRect.Right, FDropRect.Bottom);
    FDropRect := Rect(0, 0, 0, 0);
  end;
  if own then
  begin
    o.Free;
    ShowDropCursor;
  end
  // (another control's drag fed it: its cursor says "not here" until it finds a place)
  else if (o.Source <> nil) and (o.Source <> Self) then
    o.Source.PeerVerdict(Self, rdeNone);
end;

function TTyCustomRichEdit.DropOn(X, Y: Integer; AShift: TShiftState): TTyRichDropEffect;
var
  o: TTyRichDropOffer;
  own, wentIn: Boolean;
  e, r: TTyRichDropEffect;
  q, f, n: TTyRichPos;
  peer: TTyCustomRichEdit;
  life: TTyRichLife;

  procedure Focus;
  begin
    FocusAfterDrop;
  end;

  procedure Work;
  begin
    if peer <> nil then
    begin
      if peer.FDropOffer = o then
      begin
        FPeerFeeding := True;
        try
          r := peer.DropOn(peer.FDropPoint.X, peer.FDropPoint.Y, AShift);
        finally
          if not life.Gone then FPeerFeeding := False;
        end;
      end;
      { A move there: the content leaves this document - one step of its own, after the
        target's went in (a refused or failed drop there leaves it here), and only while this
        document is the content the drag began with: changed meanwhile (by a handler, a load,
        code), nothing is removed - the content is then in both, never lost. }
      if not life.Gone and (r = rdeMove) and (o is TTyRichSelectionOffer) and
        (TTyRichSelectionOffer(o).TakenAs = rdeMove) and
        (TTyRichSelectionOffer(o).FState = FDoc.ContentState) and o.SourceRange(f, n) then
        RemoveMovedAway(f, n);
    end
    else if q >= 0 then
    begin
      r := DropInto(o, q, e, AShift, wentIn);
      { What came from elsewhere went in: the control takes the focus - the application's
        handlers the focus's move runs (OnEnter, OnExit, a form's OnActivate) may free it. }
      if wentIn and not life.Gone and (o.Source <> Self) then CallHandler(@Focus);
    end;
  end;

begin
  Result := rdeNone;
  if FDropOffer = nil then Exit;
  e := DropOver(X, Y, AShift);
  q := FDropPos;
  o := FDropOffer;
  own := FDropOwn;
  { The control's own drag over another rich edit: the drop is that one's. FDropPeer stays
    set through it (its free notification clears it, should a handler there free it); the
    session here ends first all the same (not owned any more: DropLeave leaves the peer's). }
  peer := nil;
  if own then peer := FDropPeer;
  // the session ends first: what the drop does is an edit like any other
  FDropOwn := False;
  DropLeave;
  r := rdeNone;
  wentIn := False;
  { A handler the drop runs - this control's, the other control's, one the focus's move runs -
    may free this control: nothing of it is touched after that, and the frame below (MouseUp's,
    the capture's end, the system's drop target) hears of it. }
  try
    Guard(life, @Work);
  finally
    if not life.Gone then
    begin
      // (a target that raised: its session over the offer ends before the offer goes)
      if peer <> nil then
      begin
        peer := FDropPeer;
        FDropPeer := nil;
        if peer <> nil then
        begin
          peer.RemoveFreeNotification(Self);
          if peer.FDropOffer = o then peer.DropLeave;
        end;
      end;
      if own then ShowDropCursor;
    end;
    // (the control's own offer: no session holds it any more)
    if own then o.Free;
  end;
  // (the control gone with what went in: nothing of the drop is kept)
  if wentIn and life.Gone then r := rdeNone;
  Result := r;
end;

function TTyCustomRichEdit.DropInto(AOffer: TTyRichDropOffer; APos: TTyRichPos;
  AEffect: TTyRichDropEffect; AShift: TShiftState; out AWentIn: Boolean): TTyRichDropEffect;
var
  f, n, s, m: TTyRichPos;
  asCopy: Boolean;
  place: TTyRichEditPlace;
  cmd: TTyRichCommand;
  stepName: string;
  fl: TTyRichClipFlavours;
  files: TStringArray;
  cells: TTyRichCellsEdit;
  comp: TTyRichCompositeCommand;
  at: TTyRichPos;
  area: TTyRichCellArea;

  function stepNameOf(ACopy: Boolean): string;
  begin
    if ACopy then Result := rsRichUndoCopy else Result := rsRichUndoMove;
  end;

begin
  Result := rdeNone;
  AWentIn := False;
  if not IsEnabled or ViewBehind then Exit;
  // a file list: the application's, then the control's pictures
  files := AOffer.Files;
  if files <> nil then
  begin
    Result := DropFileList(AOffer, files, APos, AEffect, AWentIn);
    Exit;
  end;
  if FReadOnly then Exit;
  if (AOffer.Source = Self) and AOffer.SourceRange(f, n) then
  begin
    if AEffect = rdeNone then asCopy := ssCtrl in AShift else asCopy := AEffect = rdeCopy;
    // inside the selection (for a move at its ends too): nothing happens, nothing is told
    if asCopy and (APos > f) and (APos < f + n) then Exit;
    if not asCopy and (APos >= f) and (APos <= f + n) then Exit;
    // what the cut and the paste refuse, told once
    if not asCopy then
    begin
      if not EditAllowed(f, n, False, True) then Exit;
      s := f;
      m := n;
      if not UserRangeAllowed(s, m) then Exit;
      // (only the separator a cut keeps: nothing to move)
      if m <= 0 then Exit;
    end;
    if not EditAllowed(APos, 0, True, True) then Exit;
    if LongParaRefused(APos, 'x') then Exit;
    // (a descendant's own "not here": nothing told)
    if AEffect = rdeNone then Exit;
    { A copy of a range that cuts a field changes nothing there, so it is never refused: it
      takes what a clipboard copy takes (a part of a field as its formatted text). }
    s := f;
    m := n;
    if asCopy and FieldCover(s, m) then
    begin
      if InsertOffer(AOffer, AOffer.Flavours, APos, 0, rpaBest, rsRichUndoCopy, True) then
        Result := AEffect;
      Exit;
    end;
    { A table into a cell: cell by cell, as a cut (or copy) and a paste there - for a move the
      cut and the cells' paste in one step, the paste where the cut leaves the place. }
    cells := MakeCellsPaste(AOffer, AOffer.Flavours, rpaBest, APos, stepNameOf(asCopy), at);
    if cells <> nil then
    begin
      if asCopy then
        cmd := cells
      else
      begin
        // what the cut takes (UserRangeAllowed: a separator it keeps)
        s := f;
        m := n;
        UserRangeAllowed(s, m);
        if APos > s then cells.MoveTo(APos - m) else cells.MoveTo(APos);
        if at > s then Dec(at, m);
        comp := TTyRichCompositeCommand.Create(rsRichUndoMove);
        comp.Add(TTyRichDelete.Create(s, m));
        comp.Add(cells);
        cmd := comp;
      end;
      place := Default(TTyRichEditPlace);
      place.Anchor := at;
      place.Caret := at;
      if RunMade(cmd, place, True) then
      begin
        Result := AEffect;
        if cells.Dropped > 0 then Refuse(rsRichEditPasteCellsDropped, True);
      end;
      Exit;
    end;
    // a copy of cells: what their copy writes, pasted (a small table), not the rows
    if asCopy and RangeIsCells(f, n, area) then
    begin
      if InsertOffer(AOffer, AOffer.Flavours, APos, 0, rpaBest, rsRichUndoCopy, True) then
        Result := AEffect;
      Exit;
    end;
    if asCopy then cmd := TTyRichCopy.Create(f, n, APos)
    else cmd := TTyRichMove.Create(f, n, APos);
    place := Default(TTyRichEditPlace);
    place.Anchor := CRichPlaceInserted;
    place.Caret := CRichPlaceInserted;
    if RunMade(cmd, place, True) then Result := AEffect;
    Exit;
  end;
  // another's content: a paste of its flavours at the place
  if not EditAllowed(APos, 0, True, True) then Exit;
  if LongParaRefused(APos, 'x') then Exit;
  fl := AOffer.Flavours;
  if AEffect = rdeNone then
  begin
    // (a picture alone in a plain text document: the paste's reason)
    if PlainTextDocument and (fl * [rcfRtf, rcfText] = []) and (rcfPicture in fl) then
      EditRefused(rsRichEditRefusedPlainPaste);
    Exit;
  end;
  if AEffect = rdeMove then stepName := rsRichUndoMove else stepName := rsRichUndoCopy;
  // (another rich edit's selection is read as what its cut takes, for a move)
  if AOffer is TTyRichSelectionOffer then TTyRichSelectionOffer(AOffer).FDropAs := AEffect;
  // a table into a cell: cell by cell, as its paste
  if PasteCells(AOffer, fl, rpaBest, APos, stepName) then
  begin
    Result := AEffect;
    AOffer.Taken(AEffect);
    AWentIn := True;
    Exit;
  end;
  if InsertOffer(AOffer, fl, APos, 0, rpaBest, stepName, True) then
  begin
    Result := AEffect;
    AOffer.Taken(AEffect);
    AWentIn := True;
  end;
end;

procedure TTyCustomRichEdit.DropScrollTick;
var
  area: TRect;
  est, steps, band: Integer;
begin
  if not IsEnabled or not IsVisible then
  begin
    if FDropOwn then CancelSelectionDrag
    else if FDragTimer <> nil then FDragTimer.Enabled := False;
    Exit;
  end;
  // inside the document's update: no query, the drag waits
  if ViewBehind then Exit;
  // (outside the control nothing scrolls)
  if (FDropPoint.X < 0) or (FDropPoint.X >= Width) or (FDropPoint.Y < 0) or
    (FDropPoint.Y >= Height) then
  begin
    if FDragTimer <> nil then FDragTimer.Enabled := False;
    Exit;
  end;
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  est := Math.Max(1, FEstimate div Math.Max(1, FScale));
  band := Math.Max(1, est div 2);
  // a line a tick, and one more for every line's height the pointer is past the edge
  steps := 0;
  if FDropPoint.Y < area.Top + band then
    steps := -(1 + Math.Max(0, area.Top - FDropPoint.Y) div est)
  else if FDropPoint.Y >= area.Bottom - band then
    steps := 1 + Math.Max(0, FDropPoint.Y - area.Bottom) div est;
  if steps <> 0 then ScrollRasterBy(Int64(steps) * Math.Max(1, FEstimate));
  if FWidestSeen > FViewW then
  begin
    steps := 0;
    if FDropPoint.X < area.Left + band then
      steps := -(1 + Math.Max(0, area.Left - FDropPoint.X) div est)
    else if FDropPoint.X >= area.Right - band then
      steps := 1 + Math.Max(0, FDropPoint.X - area.Right) div est;
    if steps <> 0 then SetScrollXRaster(FScrollX + steps * Math.Max(1, FEstimate));
  end;
  // the place under the pointer in the text that came
  if FDropOffer <> nil then DropOver(FDropPoint.X, FDropPoint.Y, FDropShift);
end;

function TTyCustomRichEdit.DropMarkRaster(out ARect: TRect): Boolean;
var
  r: TRect;
  lw: Integer;
begin
  ARect := Rect(0, 0, 0, 0);
  Result := False;
  if (FDropOffer = nil) or (FDropEffect = rdeNone) or (FDropPos < 0) or ViewBehind or
    not FViewValid then Exit;
  if not CaretRaster(Math.Min(FDropPos, FDoc.Text.Length), FDropAtEnd, r) then Exit;
  // twice the overlay's line, on the caret's place (drawn dotted: never the blinking caret)
  lw := OverlayLinePx;
  ARect := Rect(r.Left - lw, r.Top, r.Left + lw, r.Bottom);
  Result := ARect.Bottom > ARect.Top;
end;

function TTyCustomRichEdit.DropMark(out ARect: TRect): Boolean;
var
  r: TRect;
begin
  ARect := Rect(0, 0, 0, 0);
  Settle;
  Result := DropMarkRaster(r);
  if Result then
    ARect := ClientOf(TextArea(Rect(0, 0, Width, Height), ViewPPI), r.Left, r.Top, r.Right,
      r.Bottom);
end;

procedure TTyCustomRichEdit.SetDragDropEditing(AValue: Boolean);
begin
  if FDragDropEditing = AValue then Exit;
  FDragDropEditing := AValue;
  if AValue then Exit;
  // off: a drag under way ends, and another control's drop or an application's is taken no more
  if FDropOwn then CancelSelectionDrag;
  FDragPending := False;
  if (FDropOffer <> nil) and not FDropOffer.FromOtherProgram then DropLeave;
end;

procedure TTyCustomRichEdit.KeyUp(var Key: Word; Shift: TShiftState);
begin
  // Ctrl up with the pointer still: the hand over a link goes
  if (Key = VK_CONTROL) or (Key = VK_LCONTROL) or (Key = VK_RCONTROL) then
    PointerKeysChanged(Shift - [ssCtrl]);
  inherited KeyUp(Key, Shift);
  if (Key = 0) or not OwnDragRunning then Exit;
  // Ctrl let go during the control's own drag: a move again, without a move of the pointer
  if OwnDragging and ((Key = VK_CONTROL) or (Key = VK_LCONTROL) or (Key = VK_RCONTROL)) then
    DropOver(FDropPoint.X, FDropPoint.Y, FDropShift - [ssCtrl])
  // another key's release is the drag's as its press is (OwnDragKey): nothing for the form
  else if not IsDragModifier(Key) then
    Key := 0;
end;

{ ---- a drag into another rich edit of the application, drops from other programs ---- }

function TTyCustomRichEdit.DropTargetAt(X, Y: Integer; out ATargetX,
  ATargetY: Integer): TTyCustomRichEdit;
var
  p: TPoint;
  c: TControl;
begin
  Result := nil;
  ATargetX := 0;
  ATargetY := 0;
  // (a control with no window has no place on the screen)
  if not HandleAllocated then Exit;
  p := ClientToScreen(Point(X, Y));
  // the LCL's own lookup: any form of the application, on every widgetset
  c := FindControlAtPosition(p, False);
  while (c <> nil) and not (c is TTyCustomRichEdit) do c := c.Parent;
  if (c = nil) or (c = Self) then Exit;
  // (one on a form that takes no input now is no target)
  if not DropTargetTakesInput(TTyCustomRichEdit(c)) then Exit;
  Result := TTyCustomRichEdit(c);
  p := Result.ScreenToClient(p);
  ATargetX := p.X;
  ATargetY := p.Y;
end;

function TTyCustomRichEdit.DropTargetTakesInput(ATarget: TTyCustomRichEdit): Boolean;
var
  f, m: TCustomForm;
begin
  { The LCL's own answer, the same on every widgetset: the form is disabled, or another form
    is the modal one (ShowModal marks it on all of them; Windows also disables the others'
    windows, GTK, Qt and Cocoa grab or run the modal loop - the LCL's Enabled of the forms
    behind is not changed there). A control on no form answers for itself. }
  Result := (ATarget <> nil) and ATarget.IsEnabled;
  if not Result then Exit;
  f := GetParentForm(ATarget);
  if f = nil then Exit;
  if not f.Enabled then Exit(False);
  m := DropModalForm;
  Result := (m = nil) or (m = f);
end;

function TTyCustomRichEdit.DropModalForm: TCustomForm;
begin
  Result := Screen.GetCurrentModalForm;
end;

procedure TTyCustomRichEdit.EndPeer;
var
  peer: TTyCustomRichEdit;
begin
  if FDropPeer = nil then Exit;
  peer := FDropPeer;
  FDropPeer := nil;
  peer.RemoveFreeNotification(Self);
  if (FDropOffer <> nil) and (peer.FDropOffer = FDropOffer) then
  begin
    FPeerFeeding := True;
    try
      peer.DropLeave;
    finally
      FPeerFeeding := False;
    end;
  end;
end;

procedure TTyCustomRichEdit.FeedPeer(X, Y: Integer; AShift: TShiftState; AInside: Boolean);
var
  target: TTyCustomRichEdit;
  tx, ty: Integer;
  e: TTyRichDropEffect;
begin
  if AInside then target := nil
  else target := DropTargetAt(X, Y, tx, ty);
  if target = Self then target := nil;
  // the one left: its session ends
  if FDropPeer <> target then EndPeer;
  if target = nil then Exit;
  if FDropPeer <> target then
  begin
    FDropPeer := target;
    target.FreeNotification(Self);
  end;
  FPeerFeeding := True;
  try
    // (its session over this offer may have ended meanwhile - its content replaced: a new one)
    if target.FDropOffer <> FDropOffer then e := target.DropEnter(FDropOffer, tx, ty, AShift)
    else e := target.DropOver(tx, ty, AShift);
  finally
    FPeerFeeding := False;
  end;
  FDropEffect := e;
end;

procedure TTyCustomRichEdit.PeerVerdict(APeer: TTyCustomRichEdit; AEffect: TTyRichDropEffect);
begin
  if FPeerFeeding or not OwnDragging or (FDropPeer <> APeer) then Exit;
  FDropEffect := AEffect;
  ShowDropCursor;
end;

procedure TTyCustomRichEdit.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FDropPeer) and (FDropPeer <> nil) then
  begin
    FDropPeer := nil;
    if OwnDragging then
    begin
      FDropEffect := rdeNone;
      ShowDropCursor;
    end;
  end;
end;

procedure TTyCustomRichEdit.RemoveMovedAway(AFrom, ALen: TTyRichPos);
var
  s, m: TTyRichPos;
  comp: TTyRichCompositeCommand;
  place: TTyRichEditPlace;
begin
  if (csDestroying in ComponentState) or ViewBehind then Exit;
  // as a cut removes it: the separator a cut keeps before a table stays
  s := AFrom;
  m := ALen;
  FDoc.BeginRead;
  try
    if (s < 0) or (s + m > FDoc.Text.Length) or not FDoc.UserRangeAllowed(s, m) then Exit;
  finally
    FDoc.EndRead;
  end;
  if m <= 0 then Exit;
  comp := TTyRichCompositeCommand.Create(rsRichUndoMove);
  comp.Add(TTyRichDelete.Create(s, m));
  place := Default(TTyRichEditPlace);
  place.Anchor := CRichPlaceChangeEnd;
  place.Caret := s;
  RunMade(comp, place, True);
end;

function TTyCustomRichEdit.OfferedPictures(AOffer: TTyRichDropOffer;
  const AFiles: TStringArray): Boolean;
begin
  // asked once per offer of the session, not at every move of the pointer
  if (AOffer <> nil) and (AOffer = FFilesOffer) then Exit(FFilesPictures);
  Result := DropFilesArePictures(AFiles);
  if (AOffer <> nil) and (AOffer = FDropOffer) then
  begin
    FFilesOffer := AOffer;
    FFilesPictures := Result;
  end;
end;

function TTyCustomRichEdit.DropFilesArePictures(const AFiles: TStringArray): Boolean;
var
  i: Integer;
  ext: string;
begin
  Result := Length(AFiles) > 0;
  for i := 0 to High(AFiles) do
  begin
    ext := LowerCase(ExtractFileExt(AFiles[i]));
    // what InsertPictureFromFile decodes itself, and what the LCL's graphic classes read
    if (ext = '.png') or (ext = '.jpg') or (ext = '.jpeg') or (ext = '.jpe') or (ext = '.bmp') or
      (ext = '.dib') or (ext = '.tif') or (ext = '.tiff') then Continue;
    // (a metafile is refused by InsertPictureFromFile)
    if (ext = '') or (ext = '.wmf') or (ext = '.emf') or
      (GetGraphicClassForFileExtension(ext) = nil) then
      Exit(False);
  end;
end;

function TTyCustomRichEdit.InsertPictureFiles(const AFiles: TStringArray; APos: TTyRichPos): Boolean;
var
  i: Integer;
  f: TFileStream;
  bytes: TBytes;
  picture: TTyRichPicture;
  fmt: TTyCharFormatId;
  comp: TTyRichCompositeCommand;
  place: TTyRichEditPlace;
  ok: Boolean;
  made: TTyRichCompositeCommand;
begin
  Result := False;
  Settle;
  fmt := FDoc.TypingFormatAt(APos);
  { Every file read and made before anything changes, as InsertPictureFromFile reads each one:
    the first that cannot be is told, and none goes in. }
  comp := TTyRichCompositeCommand.Create(rsRichUndoInsertPicture);
  try
    for i := 0 to High(AFiles) do
    begin
      try
        f := TFileStream.Create(AFiles[i], fmOpenRead or fmShareDenyWrite);
      except
        on E: Exception do
        begin
          EditRefused(Format(rsRichEditRefusedPictureFile, [E.Message]));
          Exit;
        end;
      end;
      try
        ok := ReadPictureStream(f, True, bytes);
      finally
        f.Free;
      end;
      if not ok then Exit;
      // (each sized for the room at the drop's place: the place they all go into)
      if not PictureOfFileBytes(bytes, APos, picture) then Exit;
      bytes := nil;
      comp.Add(TTyRichInsertObject.Create(APos + i, picture, fmt));
    end;
    // what went in selected, from the drop's place
    place := Default(TTyRichEditPlace);
    place.Anchor := CRichPlaceChangeStart;
    place.Caret := APos;
    place.ByGrowth := True;
    // (the door owns it from here, also when a handler it runs frees the control)
    made := comp;
    comp := nil;
    Result := RunMade(made, place, True);
  finally
    comp.Free;
  end;
end;

function TTyCustomRichEdit.DropFileList(AOffer: TTyRichDropOffer; const AFiles: TStringArray;
  APos: TTyRichPos; AEffect: TTyRichDropEffect; out AWentIn: Boolean): TTyRichDropEffect;
var
  handled: Boolean;
  life: TTyRichLife;

  procedure Fire;
  begin
    // (the application's code: a call of this control it makes stops in its own frame)
    Inc(GRichAppDepth);
    try
      DoDropFiles(AFiles, handled);
    finally
      Dec(GRichAppDepth);
    end;
  end;

begin
  Result := rdeNone;
  AWentIn := False;
  if AEffect = rdeNone then
  begin
    // (pictures into a plain text document: InsertPictureFromFile's reason)
    if Assigned(FOnDropFiles) or FReadOnly or not OfferedPictures(AOffer, AFiles) then Exit;
    if PlainTextDocument then EditRefused(rsRichEditRefusedPlainPicture);
    Exit;
  end;
  // the application first (a handler may load a file into the control, or free it)
  handled := False;
  Guard(life, @Fire);
  // (a handler that freed the control: what it said is what happened)
  if handled then
  begin
    AOffer.Taken(rdeCopy);
    Exit(rdeCopy);
  end;
  if life.Gone then Exit;
  // the control's own: pictures, where a picture can go in now (the event may have changed it)
  if FReadOnly or not IsEnabled or ViewBehind or not OfferedPictures(AOffer, AFiles) then Exit;
  if PlainTextDocument then
  begin
    EditRefused(rsRichEditRefusedPlainPicture);
    Exit;
  end;
  if (APos < 0) or (APos > FDoc.Text.Length) then Exit;
  if not EditAllowed(APos, 0, True, True) then Exit;
  if LongParaRefused(APos, 'x') then Exit;
  if not InsertPictureFiles(AFiles, APos) then Exit;
  Result := rdeCopy;
  AOffer.Taken(rdeCopy);
  AWentIn := True;
end;

procedure TTyCustomRichEdit.DoDropFiles(const AFileNames: array of string; var AHandled: Boolean);
begin
  if Assigned(FOnDropFiles) then FOnDropFiles(Self, AFileNames, AHandled);
end;

procedure TTyCustomRichEdit.FocusAfterDrop;
var
  f: TCustomForm;
begin
  if csDestroying in ComponentState then Exit;
  try
    f := GetParentForm(Self);
    // (LCL's form to the front is the system's foreground window; a form not shown: nothing)
    if (f <> nil) and f.Visible and f.HandleAllocated then f.BringToFront;
    if CanFocus and not Focused then SetFocus;
  except
    // no focus to be had (a form not shown, or one disabled by a modal one)
  end;
end;

function TTyCustomRichEdit.DropPointOf(const AScreen: TPoint): TPoint;
begin
  Result := ScreenToClient(AScreen);
end;

procedure TTyCustomRichEdit.SetAcceptDrops(AValue: Boolean);
begin
  if FAcceptDrops = AValue then Exit;
  FAcceptDrops := AValue;
  // off: a drop from another program under way ends, and the window is registered no more
  if not AValue and (FDropOffer <> nil) and FDropOffer.FromOtherProgram then DropLeave;
  SyncDropRegistration;
end;

{$IFDEF LCLWin32}
function TTyCustomRichEdit.OleDropTarget: IUnknown;
begin
  if (FOleTarget = nil) and not (csDestroying in ComponentState) then
    FOleTarget := TyRichOleNewTarget(Self);
  Result := FOleTarget;
end;
{$ENDIF}

procedure TTyCustomRichEdit.SyncDropRegistration;
begin
  {$IFDEF LCLWin32}
  if FAcceptDrops and HandleAllocated and
    ([csDesigning, csDestroying] * ComponentState = []) then
  begin
    if FOleWnd = Handle then Exit;
    RevokeDropRegistration;
    // (OLE not initialised on the thread, or the window registered by someone else: none)
    if TyRichOleRegisterWindow(Handle, OleDropTarget) then FOleWnd := Handle;
  end
  else
    RevokeDropRegistration;
  {$ENDIF}
end;

procedure TTyCustomRichEdit.RevokeDropRegistration;
begin
  {$IFDEF LCLWin32}
  if FOleWnd = 0 then Exit;
  TyRichOleRevokeWindow(FOleWnd);
  FOleWnd := 0;
  {$ENDIF}
end;

{ ---- a selected object's handles, and resizing it ---- }

procedure TyRichResizedSize(AHandle: TTyRichHandle; AWidth, AHeight, ADX, ADY: Integer;
  AKeepRatio: Boolean; AMin, AMaxWidth, AMaxHeight: Integer; out ANewWidth, ANewHeight: Integer);
var
  sx, sy, minW, minH: Integer;
  nw, nh: Int64;
  f, fw, fh, fmin, fmax: Double;

  function Bound(V: Int64; ALeast, AMost: Integer): Integer;
  begin
    if V > AMost then V := AMost;
    if V < ALeast then V := ALeast;
    if V < 1 then V := 1;
    Result := Integer(V);
  end;

begin
  if AWidth < 1 then AWidth := 1;
  if AHeight < 1 then AHeight := 1;
  if AMaxWidth < AMin then AMaxWidth := AMin;
  if AMaxHeight < AMin then AMaxHeight := AMin;
  // a side past a bound already: the bound is where it is
  minW := Math.Min(AMin, AWidth);
  minH := Math.Min(AMin, AHeight);
  AMaxWidth := Math.Max(AMaxWidth, AWidth);
  AMaxHeight := Math.Max(AMaxHeight, AHeight);
  // which way each side moves for a move of the pointer: the left ones and the top ones grow
  // the other way
  case AHandle of
    rhTopLeft, rhLeft, rhBottomLeft: sx := -1;
    rhTopRight, rhRight, rhBottomRight: sx := 1;
  else
    sx := 0;
  end;
  case AHandle of
    rhTopLeft, rhTop, rhTopRight: sy := -1;
    rhBottomLeft, rhBottom, rhBottomRight: sy := 1;
  else
    sy := 0;
  end;
  nw := Int64(AWidth) + Int64(sx) * ADX;
  nh := Int64(AHeight) + Int64(sy) * ADY;
  ANewWidth := AWidth;
  ANewHeight := AHeight;
  if AKeepRatio and (sx <> 0) and (sy <> 0) then
  begin
    // the side changed more, relatively, decides; the bounds are a range of the one factor
    fw := nw / AWidth;
    fh := nh / AHeight;
    if Abs(fw - 1) >= Abs(fh - 1) then f := fw else f := fh;
    fmin := Math.Max(minW / AWidth, minH / AHeight);
    fmax := Math.Min(AMaxWidth / AWidth, AMaxHeight / AHeight);
    if f < fmin then f := fmin;
    if f > fmax then f := fmax;
    ANewWidth := Math.Max(1, Integer(Round(AWidth * f)));
    ANewHeight := Math.Max(1, Integer(Round(AHeight * f)));
    Exit;
  end;
  if sx <> 0 then ANewWidth := Bound(nw, minW, AMaxWidth);
  if sy <> 0 then ANewHeight := Bound(nh, minH, AMaxHeight);
end;

function TTyCustomRichEdit.HandleObject(out APos: TTyRichPos; out ABox: TRect): Boolean;
var
  s: TTyRichPos;
  k: Integer;
  o: TTyRichObject;
  r: TRect;
  ok: Boolean;

  function Fit(V: Int64): Integer;
  begin
    Result := Integer(Math.Max(Int64(-MaxInt div 4), Math.Min(V, Int64(MaxInt div 4))));
  end;

begin
  Result := False;
  APos := -1;
  ABox := Rect(0, 0, 0, 0);
  // one character selected, an object's, in a held block (the cheap questions first)
  if Abs(FCaret - FSelAnchor) <> 1 then Exit;
  if FReadOnly or not IsEnabled or ViewBehind or not FViewValid or (FBlockCount = 0) then Exit;
  if RefusalReason <> '' then Exit;
  s := Math.Min(FCaret, FSelAnchor);
  if FDoc.Text.GetText(s, 1) <> TyRichObjectChar then Exit;
  k := HeldBlockOf(s);
  if k < 0 then Exit;
  FDoc.BeginRead;
  try
    o := FDoc.ObjectAt(s);
    ok := (o <> nil) and o.CanResize and FDoc.CanChange(s, 0);
  finally
    FDoc.EndRead;
  end;
  if not ok then Exit;
  if not FBlocks[k].Layout.ObjectBox(s - FDoc.Text.ParaStart(FBlocks[k].FirstPara), r) then Exit;
  ABox := Rect(r.Left - FScrollX, Fit(FBlocks[k].Top + r.Top), r.Right - FScrollX,
    Fit(FBlocks[k].Top + r.Bottom));
  APos := s;
  Result := True;
end;

function TTyCustomRichEdit.HandlePx: Integer;
var
  rppi: Integer;
begin
  rppi := FLayoutPPI;
  if rppi <= 0 then rppi := ViewPPI * Math.Max(1, FScale);
  Result := Math.Max(3, Round(CRichObjectHandleDip * rppi / 96));
  // odd: the frame's pixel in its middle
  if not Odd(Result) then Inc(Result);
end;

function TTyCustomRichEdit.OverlayLinePx: Integer;
var
  rppi: Integer;
begin
  rppi := FLayoutPPI;
  if rppi <= 0 then rppi := ViewPPI * Math.Max(1, FScale);
  Result := Math.Max(1, Round(rppi / 96));
end;

function TTyCustomRichEdit.HandleRectsOf(const ABox: TRect): TTyRichHandleRects;
var
  h2, xl, xm, xr, yt, ym, yb: Integer;

  function At(AX, AY: Integer): TRect;
  begin
    Result := Rect(AX - h2, AY - h2, AX + h2 + 1, AY + h2 + 1);
  end;

begin
  h2 := HandlePx div 2;
  // the frame's outermost pixels: its first and last column and row
  xl := ABox.Left;
  xr := ABox.Right - 1;
  xm := (xl + xr) div 2;
  yt := ABox.Top;
  yb := ABox.Bottom - 1;
  ym := (yt + yb) div 2;
  Result[rhTopLeft] := At(xl, yt);
  Result[rhTop] := At(xm, yt);
  Result[rhTopRight] := At(xr, yt);
  Result[rhRight] := At(xr, ym);
  Result[rhBottomRight] := At(xr, yb);
  Result[rhBottom] := At(xm, yb);
  Result[rhBottomLeft] := At(xl, yb);
  Result[rhLeft] := At(xl, ym);
end;

function TTyCustomRichEdit.HandleAreaOf(const ABox: TRect): TRect;
var
  h2: Integer;
begin
  h2 := HandlePx div 2;
  Result := Rect(ABox.Left - h2, ABox.Top - h2, ABox.Right + h2, ABox.Bottom + h2);
end;

function TTyCustomRichEdit.PreviewRectOf(AWidth, AHeight: Integer): TRect;
var
  pw, ph: Integer;
  b: TRect;
begin
  b := FResizeBox;
  // a side the drag did not change keeps its pixels (no rounding of twips back and forth)
  if AWidth = FResizeW0 then pw := b.Right - b.Left
  else pw := Math.Max(1, TyRichTwipsToPx(AWidth, FLayoutPPI, FLayoutZoom));
  if AHeight = FResizeH0 then ph := b.Bottom - b.Top
  else ph := Math.Max(1, TyRichTwipsToPx(AHeight, FLayoutPPI, FLayoutZoom));
  // the side opposite the handle stays where it is
  if FResizeHandle in [rhTopLeft, rhLeft, rhBottomLeft] then
    Result := Rect(b.Right - pw, 0, b.Right, 0)
  else
    Result := Rect(b.Left, 0, b.Left + pw, 0);
  if FResizeHandle in [rhTopLeft, rhTop, rhTopRight] then
  begin
    Result.Top := b.Bottom - ph;
    Result.Bottom := b.Bottom;
  end
  else
  begin
    Result.Top := b.Top;
    Result.Bottom := b.Top + ph;
  end;
end;

procedure TTyCustomRichEdit.SyncObjectOverlay;
var
  pos: TTyRichPos;
  box, cur: TRect;
begin
  // (the view not laid out: the paint brings it up to date)
  if ViewBehind or not FViewValid then Exit;
  cur := Rect(0, 0, 0, 0);
  if HandleObject(pos, box) then cur := HandleAreaOf(box);
  if not EqualRect(cur, FHandleRect) then
  begin
    if not IsRectEmpty(FHandleRect) then
      InvalidateTextRect(FHandleRect.Left, FHandleRect.Top, FHandleRect.Right, FHandleRect.Bottom);
    if not IsRectEmpty(cur) then
      InvalidateTextRect(cur.Left, cur.Top, cur.Right, cur.Bottom);
    FHandleRect := cur;
  end;
  cur := Rect(0, 0, 0, 0);
  if FResizing then cur := PreviewRectOf(FResizeW, FResizeH);
  if not EqualRect(cur, FPreviewRect) then
  begin
    if not IsRectEmpty(FPreviewRect) then
      InvalidateTextRect(FPreviewRect.Left, FPreviewRect.Top, FPreviewRect.Right,
        FPreviewRect.Bottom);
    if not IsRectEmpty(cur) then
      InvalidateTextRect(cur.Left, cur.Top, cur.Right, cur.Bottom);
    FPreviewRect := cur;
  end;
  // a drop's mark where the view has its place now
  if not DropMarkRaster(cur) then cur := Rect(0, 0, 0, 0);
  if not EqualRect(cur, FDropRect) then
  begin
    if not IsRectEmpty(FDropRect) then
      InvalidateTextRect(FDropRect.Left, FDropRect.Top, FDropRect.Right, FDropRect.Bottom);
    if not IsRectEmpty(cur) then
      InvalidateTextRect(cur.Left, cur.Top, cur.Right, cur.Bottom);
    FDropRect := cur;
  end;
end;

procedure TTyCustomRichEdit.PaintObjectOverlay(ABitmap: TBGRABitmap; AX, AY: Integer;
  const AClip: TRect; const AStyle: TTyRichPaintStyle);
var
  pos: TTyRichPos;
  box, r, old, clip, mark: TRect;
  rs: TTyRichHandleRects;
  h: TTyRichHandle;
  lw, y: Integer;
  marked: Boolean;

  procedure Outline(const R: TRect);
  begin
    ABitmap.FillRect(R.Left, R.Top, R.Right, R.Top + lw, AStyle.ObjectFrame, dmSet);
    ABitmap.FillRect(R.Left, R.Bottom - lw, R.Right, R.Bottom, AStyle.ObjectFrame, dmSet);
    ABitmap.FillRect(R.Left, R.Top, R.Left + lw, R.Bottom, AStyle.ObjectFrame, dmSet);
    ABitmap.FillRect(R.Right - lw, R.Top, R.Right, R.Bottom, AStyle.ObjectFrame, dmSet);
  end;

begin
  if ABitmap = nil then Exit;
  marked := DropMarkRaster(mark);
  if not HandleObject(pos, box) and not FResizing and not marked then Exit;
  old := ABitmap.ClipRect;
  if not IntersectRect(clip, AClip, old) then Exit;
  ABitmap.ClipRect := clip;
  try
    lw := OverlayLinePx;
    // over whatever is beside the picture: drawn after every block
    if pos >= 0 then
    begin
      rs := HandleRectsOf(box);
      for h := Low(TTyRichHandle) to High(TTyRichHandle) do
      begin
        r := rs[h];
        Types.OffsetRect(r, AX, AY);
        ABitmap.FillRect(r, AStyle.ObjectHandleFill, dmDrawWithTransparency);
        Outline(r);
      end;
    end;
    if FResizing then
    begin
      r := PreviewRectOf(FResizeW, FResizeH);
      Types.OffsetRect(r, AX, AY);
      Outline(r);
    end;
    // the drop mark: dotted, in the object frame's colour, so it is never the blinking caret
    if marked then
    begin
      r := mark;
      Types.OffsetRect(r, AX, AY);
      y := r.Top;
      while y < r.Bottom do
      begin
        ABitmap.FillRect(r.Left, y, r.Right, Math.Min(y + 2 * lw, r.Bottom), AStyle.ObjectFrame,
          dmSet);
        Inc(y, 4 * lw);
      end;
    end;
  finally
    ABitmap.ClipRect := old;
  end;
end;

function TTyCustomRichEdit.ObjectHandleRects(out ARects: TTyRichHandleRects): Boolean;
var
  pos: TTyRichPos;
  box: TRect;
  area: TRect;
  h: TTyRichHandle;
begin
  Settle;
  Result := HandleObject(pos, box);
  if not Result then Exit;
  ARects := HandleRectsOf(box);
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  for h := Low(TTyRichHandle) to High(TTyRichHandle) do
    ARects[h] := ClientOf(area, ARects[h].Left, ARects[h].Top, ARects[h].Right,
      ARects[h].Bottom);
end;

function TTyCustomRichEdit.ObjectHandleAt(X, Y: Integer; out AHandle: TTyRichHandle): Boolean;
var
  pos: TTyRichPos;
  box, area: TRect;
  rs: TTyRichHandleRects;
  h: TTyRichHandle;
  vx, vy, cl, ct, cr, cb: Int64;
  s: Integer;
  clip: TRect;
begin
  Result := False;
  AHandle := rhTopLeft;
  if (FCaret - FSelAnchor <> 1) and (FSelAnchor - FCaret <> 1) then Exit;
  Settle;
  if not HandleObject(pos, box) then Exit;
  rs := HandleRectsOf(box);
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  s := Math.Max(1, FScale);
  // the client pixel's raster pixels: one of them on a handle is enough
  vx := (Int64(X) - area.Left) * s;
  vy := (Int64(Y) - area.Top) * s;
  // only the part of a handle the view shows: what the text clip cuts away is not there
  clip := TextWindowRect;
  cl := (Int64(clip.Left) - area.Left) * s;
  ct := (Int64(clip.Top) - area.Top) * s;
  cr := (Int64(clip.Right) - area.Left) * s;
  cb := (Int64(clip.Bottom) - area.Top) * s;
  if (vx < cl) or (vx >= cr) or (vy < ct) or (vy >= cb) then Exit;
  for h := Low(TTyRichHandle) to High(TTyRichHandle) do
    if (vx + s > rs[h].Left) and (vx < rs[h].Right) and (vy + s > rs[h].Top) and
      (vy < rs[h].Bottom) then
    begin
      AHandle := h;
      Exit(True);
    end;
end;

function TTyCustomRichEdit.HandleCursor(AHandle: TTyRichHandle): TCursor;
begin
  // the text is never mirrored: the top-left and the bottom-right share a diagonal
  case AHandle of
    rhTopLeft, rhBottomRight: Result := crSizeNWSE;
    rhTopRight, rhBottomLeft: Result := crSizeNESW;
    rhTop, rhBottom: Result := crSizeNS;
  else
    Result := crSizeWE;
  end;
end;

procedure TTyCustomRichEdit.DoObjectResize(AObject: TTyRichObject; var AWidthTwips,
  AHeightTwips: Integer; var AAllow: Boolean);

  procedure Fire;
  begin
    FOnObjectResize(Self, AObject, AWidthTwips, AHeightTwips, AAllow);
  end;

begin
  // (the application's code: through the handler bracket - it may call the control, or free it)
  if Assigned(FOnObjectResize) then CallHandler(@Fire);
end;

procedure TTyCustomRichEdit.StartResize(AHandle: TTyRichHandle; APos: TTyRichPos;
  const ABox: TRect; X, Y: Integer);
var
  area: TRect;
  s, w, h: Integer;
  o: TTyRichObject;
begin
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  s := Math.Max(1, FScale);
  FDoc.BeginRead;
  try
    o := FDoc.ObjectAt(APos);
    if (o = nil) or not o.DisplaySize(w, h) then
    begin
      w := 0;
      h := 0;
    end;
  finally
    FDoc.EndRead;
  end;
  // no size of its own (shown at the default size): the box's
  if (w <= 0) or (h <= 0) then
  begin
    w := Math.Max(1, Round((ABox.Right - ABox.Left) * 1440 / (FLayoutPPI * Double(FLayoutZoom))));
    h := Math.Max(1, Round((ABox.Bottom - ABox.Top) * 1440 / (FLayoutPPI * Double(FLayoutZoom))));
  end;
  FResizing := True;
  FResizeHandle := AHandle;
  FResizePos := APos;
  // held through the drag: the release compares it with what is there then
  FResizeObj := o;
  if o <> nil then o.AddRef;
  FResizeLast := Point(X, Y);
  FResizeShift := [];
  FResizeBox := ABox;
  FResizeFrom := Point((X - area.Left) * s, (Y - area.Top) * s);
  FResizeW0 := w;
  FResizeH0 := h;
  FResizeW := w;
  FResizeH := h;
  FResizeMaxW := PictureRoom(APos);
  if (FResizeMaxW <= 0) or (FResizeMaxW > CRichObjectMaxTwips) then
    FResizeMaxW := CRichObjectMaxTwips;
  FOverHandle := HandleCursor(AHandle);
  SyncObjectOverlay;
end;

procedure TTyCustomRichEdit.ResizeSizeAt(X, Y: Integer; AShift: TShiftState; out AWidth,
  AHeight: Integer);
var
  area: TRect;
  s: Integer;
  per: Double;
begin
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  s := Math.Max(1, FScale);
  // twips per raster pixel, as the layout measures an object's box
  per := 1440 / (FLayoutPPI * Double(FLayoutZoom));
  TyRichResizedSize(FResizeHandle, FResizeW0, FResizeH0,
    Round(((Int64(X) - area.Left) * s - FResizeFrom.X) * per),
    Round(((Int64(Y) - area.Top) * s - FResizeFrom.Y) * per),
    not (ssShift in AShift), CRichObjectMinTwips, FResizeMaxW, CRichObjectMaxTwips, AWidth, AHeight);
end;

procedure TTyCustomRichEdit.MoveResize(X, Y: Integer; AShift: TShiftState);
begin
  FResizeLast := Point(X, Y);
  FResizeShift := AShift;
  // nothing in the document changes before the release: the outline alone moves
  ResizeSizeAt(X, Y, AShift, FResizeW, FResizeH);
  SyncObjectOverlay;
end;

procedure TTyCustomRichEdit.CancelResize;
var
  o: TTyRichObject;
begin
  if not FResizing then Exit;
  FResizing := False;
  o := FResizeObj;
  FResizeObj := nil;
  if o <> nil then o.Release;
  FOverHandle := crDefault;
  // the outline goes (the handles stay as the selection has them)
  if not IsRectEmpty(FPreviewRect) then
  begin
    InvalidateTextRect(FPreviewRect.Left, FPreviewRect.Top, FPreviewRect.Right,
      FPreviewRect.Bottom);
    FPreviewRect := Rect(0, 0, 0, 0);
  end;
  if MouseCapture then MouseCapture := False;
end;

procedure TTyCustomRichEdit.FinishResize(X, Y: Integer; AShift: TShiftState);
var
  w, h: Integer;
  allow: Boolean;
  pos: TTyRichPos;
  obj: TTyRichObject;
  place: TTyRichEditPlace;

  // the drag's bounds, which never pull back a side already past them
  function Bounded(V, ALeast, AMost: Integer): Integer;
  begin
    Result := V;
    if Result > AMost then Result := AMost;
    if Result < ALeast then Result := ALeast;
    if Result < 1 then Result := 1;
  end;

begin
  ResizeSizeAt(X, Y, AShift, w, h);
  pos := FResizePos;
  // the drag's reference to the object is this call's now
  obj := FResizeObj;
  FResizeObj := nil;
  CancelResize;
  try
    // the size it had: nothing happens, no step
    if (w = FResizeW0) and (h = FResizeH0) then Exit;
    allow := True;
    DoObjectResize(obj, w, h, allow);
    // what the handler gives goes through the drag's own bounds
    w := Bounded(w, Math.Min(CRichObjectMinTwips, FResizeW0), Math.Max(FResizeMaxW, FResizeW0));
    h := Bounded(h, Math.Min(CRichObjectMinTwips, FResizeH0),
      Math.Max(CRichObjectMaxTwips, FResizeH0));
    if not allow or ViewBehind then Exit;
    if (w = FResizeW0) and (h = FResizeH0) then Exit;
    // (a handler that edited, loaded or freed the selection: the object is not the one dragged)
    FDoc.BeginRead;
    try
      if FDoc.ObjectAt(pos) <> obj then Exit;
    finally
      FDoc.EndRead;
    end;
    // the object, new, selected again: its handles come back with it
    place := Default(TTyRichEditPlace);
    place.Anchor := pos;
    place.Caret := pos + 1;
    RunMade(TTyRichResizeObject.Create(pos, w, h), place, True);
  finally
    if obj <> nil then obj.Release;
  end;
end;

function TTyCustomRichEdit.ResizeOutline(out ARect: TRect; out AWidthTwips,
  AHeightTwips: Integer): Boolean;
var
  r: TRect;
begin
  Result := FResizing;
  ARect := Rect(0, 0, 0, 0);
  AWidthTwips := FResizeW;
  AHeightTwips := FResizeH;
  if not Result then Exit;
  r := PreviewRectOf(FResizeW, FResizeH);
  ARect := ClientOf(TextArea(Rect(0, 0, Width, Height), ViewPPI), r.Left, r.Top, r.Right, r.Bottom);
end;

function TTyCustomRichEdit.LeftButtonHeld: Boolean;
begin
  Result := GetKeyState(VK_LBUTTON) < 0;
end;

{ ---- pictures from code ---- }

function TTyCustomRichEdit.PictureInsertOpen: Boolean;
var
  reason: string;
begin
  Result := False;
  EndOwedLoad;
  // the door of a user's edit: a composition goes in first
  EndCompositionForUser;
  if FReadOnly or not IsEnabled or ViewBehind then Exit;
  if PlainTextDocument then
  begin
    EditRefused(rsRichEditRefusedPlainPicture);
    Exit;
  end;
  reason := RefusalReason;
  if reason <> '' then
  begin
    EditRefused(reason);
    Exit;
  end;
  Result := True;
end;

function TTyCustomRichEdit.CanInsertPicture: Boolean;
var
  s, n: TTyRichPos;
begin
  Result := not FReadOnly and IsEnabled and not ViewBehind and (RefusalReason = '') and
    not PlainTextDocument;
  if not Result then Exit;
  // the place InsertPictureMade asks for, untold: the selection's deletion, the insert, the cells
  s := GetSelStart;
  n := GetSelLength;
  Result := ((n <= 0) or FDoc.CanChange(s, n)) and FDoc.CanChange(s, 0) and
    FDoc.UserRangeAllowed(s, n);
end;

function TTyCustomRichEdit.ReadPictureStream(AStream: TStream; AFromFile: Boolean;
  out ABytes: TBytes): Boolean;
var
  ms: TMemoryStream;
  buf: array of Byte;
  k: Integer;
  n, got: Int64;
  tail: array[0..4095] of Byte;
begin
  Result := False;
  ABytes := nil;
  // a stream that tells its size: refused from it, else read straight into the bytes
  try
    n := AStream.Size - AStream.Position;
  except
    n := -1;
  end;
  if n > CRichPictureMaxBytes then
  begin
    EditRefused(rsRichEditRefusedPicture);
    Exit;
  end;
  if n >= 0 then
  begin
    try
      SetLength(ABytes, n);
      got := 0;
      while got < n do
      begin
        k := AStream.Read(ABytes[got], Math.Min(n - got, Int64(64 * 1024 * 1024)));
        if k <= 0 then Break;
        Inc(got, k);
      end;
      { All it said it holds: it may hold more than it said (a size it does not know is told
        as 0 by some streams, a pipe's seek fails). Asked into a small buffer first, so that a
        stream that told the truth - every file - costs no second block of the picture's size;
        only what it then gives is appended, in pieces until it gives nothing, a byte past the
        limit refused (and nothing more read). }
      if got = n then
        repeat
          // (never more than one byte past the limit is asked for)
          k := AStream.Read(tail[0], Math.Min(Int64(Length(tail)),
            Int64(CRichPictureMaxBytes) + 1 - got));
          if k <= 0 then Break;
          if got + k > CRichPictureMaxBytes then
          begin
            ABytes := nil;
            EditRefused(rsRichEditRefusedPicture);
            Exit;
          end;
          if got + k > Length(ABytes) then
            SetLength(ABytes, Math.Min(got + Math.Max(Int64(k), got div 2),
              Int64(CRichPictureMaxBytes)));
          Move(tail[0], ABytes[got], k);
          Inc(got, k);
        until False;
      // (a stream shorter or longer than it said: what it gave)
      if got <> Length(ABytes) then SetLength(ABytes, got);
    except
      on EOutOfMemory do
      begin
        ABytes := nil;
        EditRefused(rsRichEditRefusedMemory);
        Exit;
      end;
      on E: Exception do
      begin
        ABytes := nil;
        if AFromFile then EditRefused(Format(rsRichEditRefusedPictureFile, [E.Message]))
        else EditRefused(rsRichEditRefusedNoPicture);
        Exit;
      end;
    end;
    Exit(True);
  end;
  ms := TMemoryStream.Create;
  try
    try
      buf := nil;
      SetLength(buf, 64 * 1024);
      // by pieces: a stream that cannot tell its size reads as well, and a huge one stops early
      repeat
        k := AStream.Read(buf[0], Length(buf));
        if k > 0 then ms.WriteBuffer(buf[0], k);
        if ms.Size > CRichPictureMaxBytes then
        begin
          EditRefused(rsRichEditRefusedPicture);
          Exit;
        end;
      until k <= 0;
      SetLength(ABytes, ms.Size);
      if ms.Size > 0 then Move(ms.Memory^, ABytes[0], ms.Size);
    except
      on EOutOfMemory do
      begin
        ABytes := nil;
        EditRefused(rsRichEditRefusedMemory);
        Exit;
      end;
      on E: Exception do
      begin
        ABytes := nil;
        if AFromFile then EditRefused(Format(rsRichEditRefusedPictureFile, [E.Message]))
        else EditRefused(rsRichEditRefusedNoPicture);
        Exit;
      end;
    end;
  finally
    ms.Free;
  end;
  Result := True;
end;

{ What an image's first bytes say it is: a PNG, a JPEG, a BMP or a TIFF (AKind), or a metafile
  (AMetafile: a placeable or plain WMF, an EMF); False for anything else. }
function SniffImage(const B: TBytes; out AKind: TTyRichImageKind; out AMetafile: Boolean): Boolean;
var
  n: Integer;
begin
  AKind := rikPng;
  AMetafile := False;
  Result := True;
  n := Length(B);
  if (n >= 8) and (B[0] = $89) and (B[1] = $50) and (B[2] = $4E) and (B[3] = $47) and
    (B[4] = $0D) and (B[5] = $0A) and (B[6] = $1A) and (B[7] = $0A) then Exit;
  if (n >= 3) and (B[0] = $FF) and (B[1] = $D8) and (B[2] = $FF) then
  begin
    AKind := rikJpeg;
    Exit;
  end;
  if (n >= 2) and (B[0] = Ord('B')) and (B[1] = Ord('M')) then
  begin
    AKind := rikBmp;
    Exit;
  end;
  if (n >= 4) and (((B[0] = Ord('I')) and (B[1] = Ord('I')) and (B[2] = $2A) and (B[3] = 0)) or
    ((B[0] = Ord('M')) and (B[1] = Ord('M')) and (B[2] = 0) and (B[3] = $2A))) then
  begin
    AKind := rikTiff;
    Exit;
  end;
  Result := False;
  // a placeable WMF's key, a WMF's header (memory or disk, 9 words, version 1 or 3), an EMF's
  // first record (type 1) with its signature " EMF" at 40
  AMetafile := ((n >= 4) and (B[0] = $D7) and (B[1] = $CD) and (B[2] = $C6) and (B[3] = $9A)) or
    ((n >= 6) and (B[0] in [1, 2]) and (B[1] = 0) and (B[2] = 9) and (B[3] = 0) and
     (B[4] = 0) and (B[5] in [1, 3])) or
    ((n >= 44) and (B[0] = 1) and (B[1] = 0) and (B[2] = 0) and (B[3] = 0) and
     (B[40] = $20) and (B[41] = $45) and (B[42] = $4D) and (B[43] = $46));
end;

function TTyCustomRichEdit.InsertPictureBytes(const ABytes: TBytes): Boolean;
var
  kind: TTyRichImageKind;
  meta: Boolean;
  bytes: TBytes;
begin
  Result := False;
  if SniffImage(ABytes, kind, meta) then Exit(InsertPictureMade(ABytes, kind));
  if meta then
  begin
    EditRefused(rsRichEditRefusedMetafile);
    Exit;
  end;
  // anything else the LCL's graphic classes can read (GIF, an icon, a portable pixmap ...)
  Result := LclPictureBytes(ABytes, bytes, kind) and InsertPictureMade(bytes, kind);
end;

function TTyCustomRichEdit.LclPictureBytes(const ABytes: TBytes; out AOut: TBytes;
  out AKind: TTyRichImageKind): Boolean;
var
  pic: TPicture;
  own: TGraphic;
  st: TBytesStream;
begin
  Result := False;
  AOut := nil;
  AKind := rikPng;
  // an icon's or a cursor's header: reserved 0, then the type (1, 2), both words
  own := nil;
  if (Length(ABytes) >= 4) and (ABytes[0] = 0) and (ABytes[1] = 0) and (ABytes[3] = 0) then
    case ABytes[2] of
      1: own := TIcon.Create;
      2: own := TCursorImage.Create;
    end;
  pic := TPicture.Create;
  try
    st := TBytesStream.Create(ABytes);
    try
      try
        if own <> nil then own.LoadFromStream(st)
        else pic.LoadFromStream(st);
      except
        on EOutOfMemory do
        begin
          EditRefused(rsRichEditRefusedMemory);
          Exit;
        end;
        on Exception do
        begin
          EditRefused(rsRichEditRefusedNoPicture);
          Exit;
        end;
      end;
    finally
      st.Free;
    end;
    if own <> nil then Result := GraphicBytes(own, AOut, AKind)
    else Result := GraphicBytes(pic.Graphic, AOut, AKind);
  finally
    pic.Free;
    own.Free;
  end;
end;

function TTyCustomRichEdit.InsertGraphicCore(AGraphic: TGraphic): Boolean;
var
  kind: TTyRichImageKind;
  bytes: TBytes;
begin
  Result := GraphicBytes(AGraphic, bytes, kind) and InsertPictureMade(bytes, kind);
end;

function TTyCustomRichEdit.GraphicBytes(AGraphic: TGraphic; out ABytes: TBytes;
  out AKind: TTyRichImageKind): Boolean;
var
  st: TBytesStream;
  png: TPortableNetworkGraphic;
  kind: TTyRichImageKind;
  bytes: TBytes;
  n: Int64;
begin
  Result := False;
  ABytes := nil;
  AKind := rikPng;
  if (AGraphic = nil) or AGraphic.Empty or (AGraphic.Width <= 0) or (AGraphic.Height <= 0) then
  begin
    EditRefused(rsRichEditRefusedNoPicture);
    Exit;
  end;
  st := TBytesStream.Create;
  try
    try
      // a PNG and a JPEG as they are (what their SaveToStream gives); anything else as PNG
      if AGraphic is TPortableNetworkGraphic then
      begin
        AGraphic.SaveToStream(st);
        kind := rikPng;
      end
      else if AGraphic is TJPEGImage then
      begin
        AGraphic.SaveToStream(st);
        kind := rikJpeg;
      end
      else
      begin
        png := TPortableNetworkGraphic.Create;
        try
          png.Assign(AGraphic);
          png.SaveToStream(st);
        finally
          png.Free;
        end;
        kind := rikPng;
      end;
      // the stream's own array, cut to its size once the stream lets go of it (no copy)
      bytes := st.Bytes;
      n := st.Size;
    except
      on EOutOfMemory do
      begin
        EditRefused(rsRichEditRefusedMemory);
        Exit;
      end;
      on Exception do
      begin
        EditRefused(rsRichEditRefusedNoPicture);
        Exit;
      end;
    end;
  finally
    st.Free;
  end;
  SetLength(bytes, n);
  ABytes := bytes;
  AKind := kind;
  Result := True;
end;

function TTyCustomRichEdit.MakePictureFor(const ABytes: TBytes; AKind: TTyRichImageKind;
  APos: TTyRichPos; out APicture: TTyRichPicture): Boolean;
var
  made: TTyRichPictureMade;
begin
  Result := False;
  APicture := nil;
  try
    made := TyRichMakePicture(ABytes, AKind, PictureRoom(APos), APicture);
  except
    on EOutOfMemory do
    begin
      EditRefused(rsRichEditRefusedMemory);
      Exit;
    end;
  end;
  case made of
    rpmNoImage:
      begin
        EditRefused(rsRichEditRefusedNoPicture);
        Exit;
      end;
    rpmTooLarge:
      begin
        EditRefused(rsRichEditRefusedPicture);
        Exit;
      end;
  end;
  Result := True;
end;

function TTyCustomRichEdit.PictureOfFileBytes(const ABytes: TBytes; APos: TTyRichPos;
  out APicture: TTyRichPicture): Boolean;
var
  kind: TTyRichImageKind;
  meta: Boolean;
  bytes: TBytes;
begin
  // as InsertPictureBytes takes them
  Result := False;
  APicture := nil;
  if SniffImage(ABytes, kind, meta) then Exit(MakePictureFor(ABytes, kind, APos, APicture));
  if meta then
  begin
    EditRefused(rsRichEditRefusedMetafile);
    Exit;
  end;
  Result := LclPictureBytes(ABytes, bytes, kind) and MakePictureFor(bytes, kind, APos, APicture);
end;

function TTyCustomRichEdit.InsertPictureMade(const ABytes: TBytes; AKind: TTyRichImageKind): Boolean;
var
  s, n: TTyRichPos;
  fmt: TTyCharFormatId;
  picture: TTyRichPicture;
  comp: TTyRichCompositeCommand;
  place: TTyRichEditPlace;
begin
  Result := False;
  s := GetSelStart;
  n := GetSelLength;
  // where a paste could go (the paste's own questions, told as it tells them)
  if not EditAllowed(s, n, True, True) then Exit;
  if not UserRangeAllowed(s, n) then Exit;
  if LongParaRefused(s, 'x') then Exit;
  Settle;
  fmt := TypingFormat;
  if not MakePictureFor(ABytes, AKind, s, picture) then Exit;
  // one step: the selection's deletion and the picture, as a paste of a picture
  comp := TTyRichCompositeCommand.Create(rsRichUndoInsertPicture);
  if n > 0 then comp.Add(TTyRichDelete.Create(s, n));
  comp.Add(TTyRichInsertObject.Create(s, picture, fmt));
  place := Default(TTyRichEditPlace);
  place.Anchor := CRichPlaceChangeEnd;
  place.Caret := s + n;
  place.ByGrowth := True;
  Result := RunMade(comp, place, True);
end;

function TTyCustomRichEdit.InsertPictureFromFile(const AFileName: string): Boolean;
var
  f: TFileStream;
  ext: string;
  bytes: TBytes;
begin
  Result := False;
  if not PictureInsertOpen then Exit;
  ext := LowerCase(ExtractFileExt(AFileName));
  if (ext = '.wmf') or (ext = '.emf') then
  begin
    EditRefused(rsRichEditRefusedMetafile);
    Exit;
  end;
  try
    f := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  except
    on E: Exception do
    begin
      EditRefused(Format(rsRichEditRefusedPictureFile, [E.Message]));
      Exit;
    end;
  end;
  try
    if not ReadPictureStream(f, True, bytes) then Exit;
  finally
    f.Free;
  end;
  Result := InsertPictureBytes(bytes);
end;

function TTyCustomRichEdit.InsertPictureFromStream(AStream: TStream): Boolean;
var
  bytes: TBytes;
begin
  Result := False;
  if not PictureInsertOpen then Exit;
  if AStream = nil then
  begin
    EditRefused(rsRichEditRefusedNoPicture);
    Exit;
  end;
  if not ReadPictureStream(AStream, False, bytes) then Exit;
  Result := InsertPictureBytes(bytes);
end;

function TTyCustomRichEdit.InsertPicture(AGraphic: TGraphic): Boolean;
begin
  Result := False;
  if not PictureInsertOpen then Exit;
  Result := InsertGraphicCore(AGraphic);
end;

{ ---- copying, the menu, the input method ---- }

function TyRichClipboardRtfName: string;
begin
  // by widgetset, as the picture names are: the name LCL hands its system
  {$IFDEF LCLWin32}
  Result := 'Rich Text Format';
  {$ELSE}
  {$IFDEF LCLCocoa}
  Result := 'public.rtf';
  {$ELSE}
  Result := 'text/rtf';
  {$ENDIF}
  {$ENDIF}
end;

{ ---- a picture from an image's bytes ---- }

function PicBE32(const B: TBytes; AAt: Int64): Int64;
begin
  if (AAt < 0) or (AAt + 4 > Length(B)) then Exit(-1);
  Result := (Int64(B[AAt]) shl 24) or (Int64(B[AAt + 1]) shl 16) or (Int64(B[AAt + 2]) shl 8) or
    B[AAt + 3];
end;

function PicBE16(const B: TBytes; AAt: Int64): Int64;
begin
  if (AAt < 0) or (AAt + 2 > Length(B)) then Exit(-1);
  Result := (Int64(B[AAt]) shl 8) or B[AAt + 1];
end;

function PicLE16(const B: TBytes; AAt: Int64): Int64;
begin
  if (AAt < 0) or (AAt + 2 > Length(B)) then Exit(-1);
  Result := Int64(B[AAt]) or (Int64(B[AAt + 1]) shl 8);
end;

// a signed 32-bit little-endian number; Low(Int64) when the bytes are not there
function PicLE32(const B: TBytes; AAt: Int64): Int64;
begin
  if (AAt < 0) or (AAt + 4 > Length(B)) then Exit(Low(Int64));
  Result := LongInt(Cardinal(B[AAt]) or (Cardinal(B[AAt + 1]) shl 8) or
    (Cardinal(B[AAt + 2]) shl 16) or (Cardinal(B[AAt + 3]) shl 24));
end;

{ A DIB's file header: where its pixels start after the header, the bit masks and the
  palette - what makes a DIB a BMP file a decoder reads. }
procedure WriteDibFileHeader(AStream: TStream; const B: TBytes);
var
  hs, bits, comp, used, entry, masks, pal, off: Int64;
  hdr: array[0..13] of Byte;

  procedure Put32(AAt: Integer; V: Int64);
  begin
    hdr[AAt] := V and $FF;
    hdr[AAt + 1] := (V shr 8) and $FF;
    hdr[AAt + 2] := (V shr 16) and $FF;
    hdr[AAt + 3] := (V shr 24) and $FF;
  end;

begin
  hs := PicLE32(B, 0);
  comp := 0;
  used := 0;
  if hs = 12 then
  begin
    bits := PicLE16(B, 10);
    entry := 3;
  end
  else
  begin
    bits := PicLE16(B, 14);
    comp := PicLE32(B, 16);
    used := PicLE32(B, 32);
    entry := 4;
  end;
  masks := 0;
  // BI_BITFIELDS, BI_ALPHABITFIELDS: the masks follow a plain BITMAPINFOHEADER
  if (hs = 40) and (comp = 3) then masks := 12
  else if (hs = 40) and (comp = 6) then masks := 16;
  pal := 0;
  if (bits >= 1) and (bits <= 8) then
    if (used > 0) and (used <= 256) then pal := used else pal := Int64(1) shl bits
  // more bits: a colour table only when biClrUsed says one is there (an optimisation hint)
  else if (bits > 8) and (used > 0) then
    pal := used;
  off := 14 + hs + masks + pal * entry;
  FillChar(hdr, SizeOf(hdr), 0);
  hdr[0] := Ord('B');
  hdr[1] := Ord('M');
  Put32(2, 14 + Length(B));
  Put32(10, off);
  AStream.WriteBuffer(hdr, SizeOf(hdr));
end;

function TyRichMakePicture(const ABytes: TBytes; AKind: TTyRichImageKind;
  AMaxWidthTwips: Integer; out APicture: TTyRichPicture): TTyRichPictureMade;
var
  w, h, xppm, yppm, base, hs, i, len, bits, comp, used, entry, masks, pal, need, off: Int64;
  tag, typ, cnt, ifd, e, dirs, dw, dh: Int64;
  le: Boolean;
  seen: TBits;
  entries: Int64;
  st: TStream;
  outSt: TBytesStream;
  bmp: TBGRABitmap;
  rd: TFPCustomImageReader;
  wr: TBGRAWriterPNG;
  data: TBytes;
  fmt: TTyRichPictureFormat;
  tw, th: Int64;
  dx, dy: Double;
begin
  APicture := nil;
  Result := rpmNoImage;
  if Length(ABytes) = 0 then Exit;
  if Length(ABytes) > CRichPictureMaxBytes then Exit(rpmTooLarge);
  { The size the header says, before anything is decoded (a decoder finds it by allocating
    it), and the resolution: -1 where the format does not say it up front. }
  w := -1;
  h := -1;
  xppm := 0;
  yppm := 0;
  case AKind of
    rikPng:
      begin
        if (PicBE32(ABytes, 0) <> $89504E47) or (PicBE32(ABytes, 12) <> $49484452) then Exit;
        w := PicBE32(ABytes, 16);
        h := PicBE32(ABytes, 20);
        // pHYs (unit 1: per metre) comes before the image data
        i := 8;
        while i + 8 <= Length(ABytes) do
        begin
          len := PicBE32(ABytes, i);
          if (len < 0) or (PicBE32(ABytes, i + 4) = $49444154) then Break;   // IDAT
          if (PicBE32(ABytes, i + 4) = $70485973) and (len >= 9) and (i + 17 <= Length(ABytes)) and
            (ABytes[i + 16] = 1) then
          begin
            xppm := PicBE32(ABytes, i + 8);
            yppm := PicBE32(ABytes, i + 12);
          end;
          Inc(i, 12 + len);
        end;
      end;
    rikDib, rikBmp:
      begin
        base := 0;
        if AKind = rikBmp then
        begin
          if (Length(ABytes) < 14) or (ABytes[0] <> Ord('B')) or (ABytes[1] <> Ord('M')) then Exit;
          base := 14;
        end;
        hs := PicLE32(ABytes, base);
        comp := 0;
        used := 0;
        if hs = 12 then
        begin
          w := PicLE16(ABytes, base + 4);
          h := PicLE16(ABytes, base + 6);
          bits := PicLE16(ABytes, base + 10);
          entry := 3;
        end
        else if (hs >= 40) and (hs <= 1024) then
        begin
          w := PicLE32(ABytes, base + 4);
          h := Abs(PicLE32(ABytes, base + 8));
          xppm := PicLE32(ABytes, base + 24);
          yppm := PicLE32(ABytes, base + 28);
          bits := PicLE16(ABytes, base + 14);
          comp := PicLE32(ABytes, base + 16);
          used := PicLE32(ABytes, base + 32);
          entry := 4;
        end
        else
          Exit;
        { Uncompressed (BI_RGB, BI_BITFIELDS, BI_ALPHABITFIELDS): the pixel rows the header
          promises must be there - a reader fills what is missing, and a header alone would be
          a picture of nothing. A compressed one is the decoder's to judge. }
        if (comp in [0, 3, 6]) and (w > 0) and (h > 0) then
        begin
          if not (bits in [1, 4, 8, 16, 24, 32]) then Exit;
          masks := 0;
          if (hs = 40) and (comp = 3) then masks := 12
          else if (hs = 40) and (comp = 6) then masks := 16;
          pal := 0;
          if bits <= 8 then
            if (used > 0) and (used <= 256) then pal := used else pal := Int64(1) shl bits
          // more bits with biClrUsed: a colour table before the pixels all the same
          else if used > 0 then
            pal := used;
          need := base + hs + masks + pal * entry;
          if AKind = rikBmp then
          begin
            off := PicLE32(ABytes, 10);
            if off > need then need := off;
          end;
          Inc(need, ((w * bits + 31) div 32) * 4 * h);
          if Length(ABytes) < need then Exit;
        end;
      end;
    rikJpeg:
      begin
        // the frame's size in its SOF segment, before the scan
        if (PicBE16(ABytes, 0) <> $FFD8) then Exit;
        i := 2;
        while i + 4 <= Length(ABytes) do
        begin
          if ABytes[i] <> $FF then Exit;
          case ABytes[i + 1] of
            $FF: begin Inc(i); Continue; end;
            $01, $D0..$D7: begin Inc(i, 2); Continue; end;
            $C0..$C3, $C5..$C7, $C9..$CB, $CD..$CF:
              begin
                h := PicBE16(ABytes, i + 5);
                w := PicBE16(ABytes, i + 7);
                Break;
              end;
            $D9, $DA: Exit;
          end;
          len := PicBE16(ABytes, i + 2);
          if len < 2 then Exit;
          Inc(i, 2 + len);
        end;
        if (w <= 0) or (h <= 0) then Exit;
      end;
    rikTiff:
      begin
        { Every directory's width and length: the decoder reads every image of the file and
          takes the largest. A chain that comes back to a directory it visited, points outside
          the bytes, holds a directory with no size, or makes the walk read more entries than
          the bytes hold (12 bytes each) does not decode: the work is linear in the file's
          bytes, once. The largest image is the one judged. }
        if (Length(ABytes) >= 8) and (ABytes[0] = Ord('I')) and (ABytes[1] = Ord('I')) then le := True
        else if (Length(ABytes) >= 8) and (ABytes[0] = Ord('M')) and (ABytes[1] = Ord('M')) then le := False
        else Exit;
        if le then ifd := Cardinal(PicLE32(ABytes, 4)) else ifd := PicBE32(ABytes, 4);
        dirs := 0;
        entries := 0;
        seen := TBits.Create(Length(ABytes));
        try
        while ifd <> 0 do
        begin
          // a directory takes at least 18 bytes: a chain longer than the bytes could hold
          // distinct ones goes round
          Inc(dirs);
          Inc(TyRichTiffDirsVisited);
          if (dirs > Length(ABytes) div 18 + 1) or (ifd < 8) or (ifd + 2 > Length(ABytes)) then Exit;
          // back at a directory of the chain: it goes round
          if seen[ifd] then Exit;
          seen[ifd] := True;
          if le then cnt := PicLE16(ABytes, ifd) else cnt := PicBE16(ABytes, ifd);
          if (cnt <= 0) or (ifd + 2 + cnt * 12 + 4 > Length(ABytes)) then Exit;
          // directories that overlap each other: no more entries than the bytes hold, in all
          Inc(entries, cnt);
          if entries > Length(ABytes) div 12 then Exit;
          dw := -1;
          dh := -1;
          for e := 0 to cnt - 1 do
          begin
            Inc(TyRichTiffEntriesRead);
            i := ifd + 2 + e * 12;
            if le then
            begin
              tag := PicLE16(ABytes, i);
              typ := PicLE16(ABytes, i + 2);
              if typ = 3 then len := PicLE16(ABytes, i + 8) else len := Cardinal(PicLE32(ABytes, i + 8));
            end
            else
            begin
              tag := PicBE16(ABytes, i);
              typ := PicBE16(ABytes, i + 2);
              if typ = 3 then len := PicBE16(ABytes, i + 8) else len := PicBE32(ABytes, i + 8);
            end;
            if tag = 256 then dw := len
            else if tag = 257 then dh := len;
          end;
          if (dw <= 0) or (dh <= 0) then Exit;
          // (the decoder would take this one or a larger one)
          if dw > CRichPictureMaxPixels div dh then Exit(rpmTooLarge);
          if (w < 0) or (dw * dh > w * h) then
          begin
            w := dw;
            h := dh;
          end;
          i := ifd + 2 + cnt * 12;
          if le then ifd := Cardinal(PicLE32(ABytes, i)) else ifd := PicBE32(ABytes, i);
        end;
        finally
          seen.Free;
        end;
        if (w <= 0) or (h <= 0) then Exit;
      end;
  end;
  if (w = 0) or (h = 0) or (w < -1) or (h < -1) then Exit;
  if (w > 0) and (h > 0) and (w > CRichPictureMaxPixels div h) then Exit(rpmTooLarge);
  { The decoder reads the bytes themselves (no copy of a large file); a DIB gets the file
    header it lacks in a copy of its own. }
  if AKind = rikDib then
  begin
    st := TMemoryStream.Create;
    WriteDibFileHeader(st, ABytes);
    st.WriteBuffer(ABytes[0], Length(ABytes));
  end
  else
    st := TBytesStream.Create(ABytes);
  bmp := TBGRABitmap.Create;
  rd := nil;
  try
    st.Position := 0;
    case AKind of
      rikPng: rd := TBGRAReaderPNG.Create;
      rikDib, rikBmp:
        begin
          rd := TBGRAReaderBMP.Create;
          // a 32-bit bitmap whose alpha is 0 everywhere has no alpha: opaque
          TBGRAReaderBMP(rd).TransparencyOption := toAuto;
        end;
      rikTiff: rd := TBGRAReaderTiff.Create;
      rikJpeg: rd := TBGRAReaderJpeg.Create;
    end;
    try
      bmp.LoadFromStream(st, rd);
    except
      on E: Exception do
      begin
        // a decoder's or the memory's refusal of these bytes: no image we can show
        if E is EOutOfMemory then Exit(rpmTooLarge);
        Exit(rpmNoImage);
      end;
    end;
    if (bmp.Width <= 0) or (bmp.Height <= 0) then Exit(rpmNoImage);
    if Int64(bmp.Width) > CRichPictureMaxPixels div bmp.Height then Exit(rpmTooLarge);
    w := bmp.Width;
    h := bmp.Height;
    case AKind of
      rikPng:
        begin
          { Kept as it is, to its IEND chunk: what follows is no part of it (win32's clipboard
            block is rounded up). }
          data := ABytes;
          i := 8;
          while i + 12 <= Length(ABytes) do
          begin
            len := PicBE32(ABytes, i);
            if (len < 0) or (i + 12 + len > Length(ABytes)) then Break;
            if PicBE32(ABytes, i + 4) = $49454E44 then
            begin
              if i + 12 + len < Length(ABytes) then data := Copy(ABytes, 0, i + 12 + len);
              Break;
            end;
            Inc(i, 12 + len);
          end;
          fmt := rpfPng;
        end;
      rikJpeg:
        begin
          data := ABytes;
          fmt := rpfJpeg;
        end;
    else
      outSt := TBytesStream.Create;
      wr := TBGRAWriterPNG.Create;
      try
        wr.UseAlpha := bmp.HasTransparentPixels;
        bmp.SaveToStream(outSt, wr);
        data := Copy(outSt.Bytes, 0, outSt.Size);
      finally
        wr.Free;
        outSt.Free;
      end;
      fmt := rpfPng;
    end;
  finally
    rd.Free;
    bmp.Free;
    st.Free;
  end;
  // its own resolution where it is a believable one, else 96 dpi
  dx := xppm * 0.0254;
  if not ((dx >= 10) and (dx <= 10000)) then dx := 96;
  dy := yppm * 0.0254;
  if not ((dy >= 10) and (dy <= 10000)) then dy := dx;
  tw := Round(w * 1440 / dx);
  th := Round(h * 1440 / dy);
  if tw < 1 then tw := 1;
  if th < 1 then th := 1;
  if (AMaxWidthTwips > 0) and (tw > AMaxWidthTwips) then
  begin
    th := Round(th * (AMaxWidthTwips / tw));
    if th < 1 then th := 1;
    tw := AMaxWidthTwips;
  end;
  if tw > High(Integer) then tw := High(Integer);
  if th > High(Integer) then th := High(Integer);
  APicture := TTyRichPicture.Create(fmt, data, tw, th);
  Result := rpmMade;
end;

type
  { A stream that gathers what is written into a string: a copy's RTF of a big range is made
    once, not once in a stream and again as a string. }
  TTyRichStringOut = class(TStream)
  private
    FData: RawByteString;
    FSize: Int64;
  public
    function Write(const Buffer; Count: LongInt): LongInt; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    function Take: RawByteString;
  end;

function TTyRichStringOut.Write(const Buffer; Count: LongInt): LongInt;
var
  cap: Int64;
begin
  if Count <= 0 then Exit(0);
  if FSize + Count > Length(FData) then
  begin
    cap := Length(FData) * 2;
    if cap < FSize + Count then cap := FSize + Count + 65536;
    SetLength(FData, cap);
  end;
  Move(Buffer, FData[FSize + 1], Count);
  Inc(FSize, Count);
  Result := Count;
end;

function TTyRichStringOut.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  // written front to back: where it is, and its size, are the same
  Result := FSize;
end;

function TTyRichStringOut.Take: RawByteString;
begin
  SetLength(FData, FSize);
  Result := FData;
  FData := '';
  FSize := 0;
end;

type
  { The plain text of a copy, gathered paragraph by paragraph from one walk of the text. }
  TTyRichTextOut = class
  public
    Doc: TTyRichDocument;
    Range: TTyRichCopyRange;
    Data: RawByteString;
    Size: Int64;
    Prev: TTyRichCell;
    HavePrev: Boolean;
    destructor Destroy; override;
    procedure SetPrev(ACell: TTyRichCell);
    procedure Add(P: PByte; ACount: PtrInt);
    procedure AddS(const S: RawByteString);
    procedure EndPrev(ANext: TTyRichCell);
    procedure Para(AIndex: Integer; AData: Pointer; AText: PByte; ALen: PtrInt;
      var AContinue: Boolean);
  end;

destructor TTyRichTextOut.Destroy;
begin
  SetPrev(nil);
  inherited Destroy;
end;

{ The cell of the paragraph before is asked about when the next one comes: the walk's value
  (and the parsed interval that made it) may be gone by then, so its table is held. }
procedure TTyRichTextOut.SetPrev(ACell: TTyRichCell);
begin
  if ACell <> nil then ACell.Table.AddRef;
  if Prev <> nil then Prev.Table.Release;
  Prev := ACell;
end;

procedure TTyRichTextOut.Add(P: PByte; ACount: PtrInt);
var
  cap: Int64;
begin
  if ACount <= 0 then Exit;
  if Size + ACount > Length(Data) then
  begin
    cap := Length(Data) * 2;
    if cap < Size + ACount then cap := Size + ACount + 4096;
    SetLength(Data, cap);
  end;
  Move(P^, Data[Size + 1], ACount);
  Inc(Size, ACount);
end;

procedure TTyRichTextOut.AddS(const S: RawByteString);
begin
  if S <> '' then Add(PByte(@S[1]), Length(S));
end;

{ The end of the paragraph before, which ANext's paragraph follows: a line break; between two
  cells of a row a tab for each cell boundary (a cell merged away, or one the model left
  without a paragraph, gives its tab); after a row's last one a tab for each cell after it
  that the model left without a paragraph, then a line break. }
procedure TTyRichTextOut.EndPrev(ANext: TTyRichCell);
var
  k: Integer;
begin
  if (Prev <> nil) and (ANext <> nil) and (ANext <> Prev) and (ANext.Row = Prev.Row) then
    for k := Prev.Index + 1 to ANext.Index do AddS(#9)
  else
  begin
    // (not between two paragraphs of one cell)
    if (Prev <> nil) and ((ANext = nil) or (ANext.Row <> Prev.Row)) then
      for k := Prev.Index + 1 to Prev.Row.CellCount - 1 do AddS(#9);
    AddS(sLineBreak);
  end;
end;

procedure TTyRichTextOut.Para(AIndex: Integer; AData: Pointer; AText: PByte; ALen: PtrInt;
  var AContinue: Boolean);
const
  Replacement: array[0..2] of Byte = ($EF, $BF, $BD);
var
  fmt: TTyParaFormatId;
  runs: TTyRunArray;
  cell: TTyRichCell;
  from, upto, ch: Int64;
  p, n: PtrInt;
  b: Byte;
  code: Cardinal;
  k: Integer;
begin
  if AIndex > Range.LastPara then
  begin
    AContinue := False;
    Exit;
  end;
  { the cell from the walk's value - for a paragraph not parsed yet, the value of the moment
    the walk makes of the parse that decoded it (nothing is left set); a paragraph the walk
    has no value for: by its index }
  if not Doc.ReadValue(AData, fmt, runs, cell) then cell := Doc.CellAt(AIndex);
  if Range.InOneCell then cell := nil;
  if HavePrev then EndPrev(cell);
  // a row's first paragraph in a later cell: the cells before it, which the model left
  // without a paragraph, give their tabs
  if (cell <> nil) and ((Prev = nil) or (Prev.Row <> cell.Row)) then
    for k := 0 to cell.Index - 1 do AddS(#9);
  from := 0;
  upto := High(Int64);
  if AIndex = Range.FirstPara then from := Range.FromChar;
  if AIndex = Range.LastPara then upto := Range.ToChar;
  p := 0;
  ch := 0;
  while (p < ALen) and (ch < upto) do
  begin
    b := AText[p];
    // a character's bytes, as the text storage counts characters (the RTF flavour cuts by
    // the same rule)
    code := b;
    if b < $80 then n := 1 else n := TyRichNextChar(AText + p, ALen - p, code);
    if (n = 1) and (b >= $F8) and (b <= $FB) and (p + 1 < ALen) and (AText[p + 1] and $C0 = $80) then
    begin
      // an escaped byte: its two characters are one U+FFFD
      if ch >= from then Add(@Replacement[0], 3);
      Inc(p, 2);
      Inc(ch, 2);
      Continue;
    end;
    if ch >= from then
      if b = $0B then
        AddS(sLineBreak)
      else if (n = 1) and (b >= $80) then
        Add(@Replacement[0], 3)
      else if code <> $FFFC then
        // (U+FFFC, an object, gives nothing)
        Add(AText + p, n);
    Inc(p, n);
    Inc(ch);
  end;
  SetPrev(cell);
  HavePrev := True;
end;

function TTyCustomRichEdit.RangeText(AFrom, ALen: TTyRichPos): string;
var
  o: TTyRichTextOut;
  s: RawByteString;
begin
  Result := '';
  o := TTyRichTextOut.Create;
  try
    o.Doc := FDoc;
    o.Range := TyRichCopyRange(FDoc, AFrom, ALen);
    if o.Range.Empty then Exit;
    FDoc.BeginRead;
    try
      FDoc.Text.WalkParaTexts(o.Range.FirstPara, o.Range.LastPara, @o.Para, True);
    finally
      FDoc.EndRead;
    end;
    // the last paragraph's separator, when the range takes it
    if o.Range.LastSeparator then o.EndPrev(nil);
    SetLength(o.Data, o.Size);
    s := o.Data;
    o.Data := '';
    SetCodePage(s, CP_UTF8, False);
    Result := s;
  finally
    o.Free;
  end;
end;

function TTyCustomRichEdit.GetSelText: string;
begin
  Result := RangeText(GetSelStart, GetSelLength);
end;

procedure TTyCustomRichEdit.CopyToClipboard;
begin
  // nothing selected: nothing put there, the clipboard keeps what it had (and nothing on a
  // page whose text is not to be taken: AllowSelection)
  if not HasSelection or not FAllowSelection then Exit;
  { cells, not whole rows (those are the file's rows, as a copy of them always was): a small
    table of them }
  if TyRichCellsEditable(CellArea) and not TyRichAreaWholeRows(FDoc, CellArea) then
  begin
    CopyCells(CellArea);
    Exit;
  end;
  CopyRange(GetSelStart, GetSelLength);
end;

procedure TTyCustomRichEdit.CopyRange(AStart, ALen: TTyRichPos);
var
  s, n: TTyRichPos;
  rtf: RawByteString;
  txt: string;
  wait: Boolean;
begin
  s := AStart;
  n := ALen;
  wait := n > FCopyWaitChars;
  if wait then BeginWait;
  try
    txt := RangeText(s, n);
    rtf := RangeRtf(s, n);
    WriteClipboard(rtf, txt);
  finally
    if wait then EndWait;
  end;
end;

function TTyCustomRichEdit.RangeRtf(AStart, ALen: TTyRichPos): RawByteString;
var
  st: TTyRichStringOut;
begin
  Result := '';
  NameDocBase;
  st := TTyRichStringOut.Create;
  try
    try
      TyRichSaveRtfRange(FDoc, st, AStart, ALen);
      Result := st.Take;
    except
      // a range the RTF writer refuses (a changed row holding a nested table): the text alone
      on ETyRichRtfWrite do Result := '';
    end;
  finally
    st.Free;
  end;
end;

{ ---- editing ----

  Every edit is a command run by the document (TTyRichDocument.Execute), so the history holds
  all of it; the control never changes the text another way. An edit of the control's own
  goes: EditAllowed (the document takes edits now, no row that holds a nested table is in the
  way) - RunEdit (the command, the document's one OnChange heard but held: FEditing) -
  FinishEdit (the caret placed where the edit leaves it, scrolled into view, then the
  action's one OnChange and one OnSelectionChange). A user's edit - a key, the menu, a paste,
  a commit, a descendant's command - takes these steps through one door, RunUserEdit,
  which asks ReadOnly and ends a composition first. The caret's new place is read off what
  the document reported: the end of the change (behind typed text, the join of a deletion,
  the new paragraph's start after Enter). A key never raises a refusal: it goes to
  EditRefused; a method called from code raises ETyRichEdit. }

function TTyCustomRichEdit.RefusalReason: string;
begin
  // (the document says False to Execute for each of these; a key's refusal says which)
  if FDoc.Loading then Result := rsRichEditRefusedLoading
  else if FDoc.Incomplete then Result := rsRichEditRefusedIncomplete
  else if FDoc.Saving then Result := rsRichEditRefusedSaving
  else Result := '';
end;

{ What the user is told of a refusal the engine raised (an ETyRichModel the command reverted):
  always a reason of the control's own, never the engine's sentence - the document's state, a
  row that holds a nested table, else that the range cannot be edited. }
function TTyCustomRichEdit.EngineRefusal(E: Exception): string;
begin
  Result := RefusalReason;
  if Result <> '' then Exit;
  if (E is ETyRichRefused) and ETyRichRefused(E).FixedRow then Result := rsRichEditRefusedFixedRow
  else if (E is ETyRichRefused) and ETyRichRefused(E).Field then Result := rsRichEditRefusedField
  else Result := rsRichEditRefusedRange;
end;

{ The reason the document gives for refusing a change at APos (ALen: a deletion's length): a
  row that holds a nested table, or a field's result. }
function TTyCustomRichEdit.ChangeRefusalText(APos, ALen: TTyRichPos): string;
begin
  if FDoc.ChangeRefusal(APos, ALen) = rcrField then Result := rsRichEditRefusedField
  else Result := rsRichEditRefusedFixedRow;
end;

procedure TTyCustomRichEdit.Refuse(const AReason: string; AUser: Boolean);
begin
  if AUser then EditRefused(AReason) else raise ETyRichEdit.Create(AReason);
end;

procedure TTyCustomRichEdit.EditRefused(const AReason: string);

  procedure Fire;
  begin
    FOnEditRefused(Self, AReason);
  end;

begin
  if Assigned(FOnEditRefused) then CallHandler(@Fire);
end;

function TTyCustomRichEdit.EditAllowed(APos, ALen: TTyRichPos; AInsert, AUser: Boolean): Boolean;
var
  reason: string;
begin
  reason := RefusalReason;
  { Asked before the command is made: a composite (a selection typed over) that the engine
    refused half way would be reverted, but would have reported a change on the way (Modified
    stays: the history numbers only a content it kept). }
  if (reason = '') and (ALen > 0) and not FDoc.CanChange(APos, ALen) then
  begin
    reason := ChangeRefusalText(APos, ALen);
    { A user's edit of a selection that cuts a field (takes one of its marks without the
      other): nothing changes, the selection grows to the smallest range that holds every
      field it cut, whole - the next attempt acts on what is shown selected - and the refusal
      is told once, below. An edit from code is refused as it is. }
    if AUser and (reason = rsRichEditRefusedField) and (APos = GetSelStart) and
      (ALen = GetSelLength) and not InsideOneResult(APos, APos + ALen) then
      GrowOverFields(APos, ALen);
  end;
  if (reason = '') and AInsert and not FDoc.CanChange(APos, 0) then
    reason := ChangeRefusalText(APos, 0);
  Result := reason = '';
  if not Result then Refuse(reason, AUser);
end;

function TTyCustomRichEdit.RunEdit(ACmd: TTyRichCommand; AUser: Boolean): Boolean;
var
  c, a: TTyRichPos;
  state: Int64;
  atEnd, ok: Boolean;
  marks: TTyRichStepMarks;
  refusal, cannot: string;
  lateWhy, propsWhy, lateFirst, propsFirst, partRefused: Boolean;
  pwhy: TTyRichTableRefusal;
  lateCmd: TTyRichCommand;
  why: TTyRichTableRefusal;
  edit: TTyRichTableEdit;
  pedit: TTyRichPropEdit;
  xfer: Boolean;
  xFrom, xLen, xTo: TTyRichPos;
  xMove: Boolean;
begin
  Result := False;
  refusal := '';
  { A copy or a move of a range: its reason (the places' rows, the cells) asked only when it was
    refused, from one like it. }
  xfer := ACmd is TTyRichRangeTransfer;
  xFrom := 0;
  xLen := 0;
  xTo := 0;
  xMove := ACmd is TTyRichMove;
  if xfer then
  begin
    xFrom := TTyRichRangeTransfer(ACmd).FromPos;
    xLen := TTyRichRangeTransfer(ACmd).RangeLength;
    xTo := TTyRichRangeTransfer(ACmd).ToPos;
  end;
  { Asked before: a command the document refuses is freed by it. A built-in table command
    would read its whole table for a reason that is rarely needed: its edit (a record) is
    kept instead, and the reason asked only when the command was refused. }
  { (a table edit's step: the edit first, then what keeps its lines and marks right - the
    edit's reason is the step's) }
  lateCmd := ACmd;
  lateFirst := False;
  if (ACmd is TTyRichCompositeCommand) and (TTyRichCompositeCommand(ACmd).Count > 0) then
  begin
    lateCmd := TTyRichCompositeCommand(ACmd).Items[0];
    lateFirst := True;
  end;
  lateWhy := (lateCmd.ClassType = TTyRichInsertTable) or (lateCmd.ClassType = TTyRichInsertRow) or
    (lateCmd.ClassType = TTyRichDeleteRow) or (lateCmd.ClassType = TTyRichInsertColumn) or
    (lateCmd.ClassType = TTyRichDeleteColumn);
  if not lateWhy then lateFirst := False;
  partRefused := False;
  { A table properties command reads the rows it changes for its reason as for its work (a
    column's edge in ten thousand rows): the reason is asked only when it was refused. }
  propsWhy := ACmd is TTyRichTablePropsCommand;
  propsFirst := False;
  if propsWhy then pedit := TTyRichTablePropsCommand(ACmd).Edit
  else if (lateCmd <> ACmd) and (lateCmd is TTyRichTablePropsCommand) then
  begin
    // (a properties edit and what keeps its lines right: the edit's reason is the step's)
    propsWhy := True;
    propsFirst := True;
    pedit := TTyRichTablePropsCommand(lateCmd).Edit;
  end;
  if lateWhy then
  begin
    edit := TTyRichTableCommand(lateCmd).Edit;
    cannot := '';
  end
  else if xfer or propsWhy then
    cannot := ''
  else
    cannot := CommandRefusal(ACmd);
  c := FCaret;
  a := FSelAnchor;
  atEnd := FCaretAtEnd;
  FEditHeard := False;
  FEditStep := nil;
  ok := False;
  // the selection the step starts from: what its undo puts back (a merged run keeps its first)
  marks := Default(TTyRichStepMarks);
  marks.HasBefore := True;
  marks.Before.Anchor := a;
  marks.Before.Caret := c;
  marks.Before.AtLineEnd := atEnd;
  ACmd.Marks := marks;
  state := FDoc.ContentState;
  Inc(FEditing);
  try
    try
      ok := FDoc.Execute(ACmd);
      // (a write inside an update of the document: no report comes until the update ends)
      if ok and not FEditHeard then FollowBlockWrite(ACmd, state);
    except
      on E: ETyRichModel do
      begin
        // the engine reverted what the command did: as if it had not run (and the history
        // numbers no content it did not keep: Modified is as it was)
        FCaret := c;
        FSelAnchor := a;
        FCaretAtEnd := atEnd;
        if not AUser then raise;
        refusal := EngineRefusal(E);
        partRefused := (lateFirst or propsFirst) and (E is ETyRichRefused);
      end;
      on E: EOutOfMemory do
      begin
        // (a paste that needs more than there is: the document reverted it the same way)
        FCaret := c;
        FSelAnchor := a;
        FCaretAtEnd := atEnd;
        if not AUser then raise;
        refusal := rsRichEditRefusedMemory;
      end;
    end;
  finally
    Dec(FEditing);
  end;
  // a table edit's step refused at its edit: the edit's own reason
  if partRefused and (RefusalReason = '') then
    if lateFirst then
    begin
      why := FDoc.TableEditRefusal(edit);
      if why <> rtrNone then refusal := TableRefusalText(why, edit);
    end
    else
    begin
      pwhy := FDoc.TablePropsRefusal(pedit);
      if pwhy <> rtrNone then refusal := PropsRefusalText(pwhy, pedit);
    end;
  { Told once the edit's bracket is closed: a handler that changes or loads the document is
    heard as a change from elsewhere (its OnChange), not taken for this edit's. }
  if refusal <> '' then
  begin
    EditRefused(refusal);
    PayModifiedOwed;
    Exit;
  end;
  if not ok then
  begin
    PayModifiedOwed;
    // CanExecute said no: the reason that holds for that command (asked of one like it)
    if lateWhy then cannot := LateTableRefusal(edit);
    if propsWhy then cannot := PropsRefusalText(FDoc.TablePropsRefusal(pedit), pedit);
    if xfer then cannot := LateTransferRefusal(xFrom, xLen, xTo, xMove);
    Refuse(cannot, AUser);
    Exit;
  end;
  // (a command that changed nothing is not kept and reported nothing: the caret stays)
  Result := FEditHeard;
  if not Result then PayModifiedOwed;
  { The step it became - its own, or the run of typing it merged into: the newest of the
    history (inside the document's update it went into the update's block: no step yet). }
  if Result and not FDoc.Updating then FEditStep := FDoc.UndoStep;
end;

function TTyCustomRichEdit.LateTableRefusal(const AEdit: TTyRichTableEdit): string;
var
  cmd: TTyRichCommand;
begin
  case AEdit.Kind of
    rtkInsertTable: cmd := TTyRichInsertTable.Create(AEdit.Pos, AEdit.Rows, AEdit.Cols, AEdit.Width);
    rtkInsertRow: cmd := TTyRichInsertRow.Create(AEdit.Pos, AEdit.Index);
    rtkDeleteRow: cmd := TTyRichDeleteRow.Create(AEdit.Pos, AEdit.Index);
    rtkInsertColumn: cmd := TTyRichInsertColumn.Create(AEdit.Pos, AEdit.Index);
  else
    cmd := TTyRichDeleteColumn.Create(AEdit.Pos, AEdit.Index);
  end;
  try
    Result := CommandRefusal(cmd);
  finally
    cmd.Free;
  end;
end;

function TTyCustomRichEdit.LateTransferRefusal(AFrom, ALen, ATo: TTyRichPos;
  AMove: Boolean): string;
var
  cmd: TTyRichCommand;
begin
  if AMove then cmd := TTyRichMove.Create(AFrom, ALen, ATo)
  else cmd := TTyRichCopy.Create(AFrom, ALen, ATo);
  try
    Result := CommandRefusal(cmd);
  finally
    cmd.Free;
  end;
end;

function TTyCustomRichEdit.CommandRefusal(ACmd: TTyRichCommand): string;
var
  x: TTyRichRangeTransfer;
begin
  { A copy or a move: where a place's row keeps its text (a nested table's), else for a move a
    range across cells, else the range. }
  if ACmd is TTyRichRangeTransfer then
  begin
    x := TTyRichRangeTransfer(ACmd);
    if not FDoc.CanChange(x.ToPos, 0) then
      Result := ChangeRefusalText(x.ToPos, 0)
    else if (ACmd is TTyRichMove) and not FDoc.CanChange(x.FromPos, x.RangeLength) then
      Result := ChangeRefusalText(x.FromPos, x.RangeLength)
    else if ACmd is TTyRichMove then
      Result := rsRichEditRefusedCells
    else
      Result := rsRichEditRefusedRange;
    Exit;
  end;
  if ACmd is TTyRichTableCommand then
    Exit(TableRefusalText(TTyRichTableCommand(ACmd).Refusal(FDoc), TTyRichTableCommand(ACmd).Edit));
  // a resize is refused where its place cannot change, else for its object
  if ACmd is TTyRichResizeObject then
  begin
    if not FDoc.CanChange(TTyRichResizeObject(ACmd).Pos, 0) then
      Result := ChangeRefusalText(TTyRichResizeObject(ACmd).Pos, 0)
    else Result := rsRichEditRefusedRange;
    Exit;
  end;
  // (the engine's composite says the same for the same parts: tyControls.RichEdit.Commands)
  case TyRichCommandRefusal(FDoc, ACmd) of
    rcrFixedRow: Result := rsRichEditRefusedFixedRow;
    rcrField: Result := rsRichEditRefusedField;
  else
    Result := rsRichEditRefusedRange;
  end;
end;

procedure TTyCustomRichEdit.FinishEdit(AAnchor, ACaret: TTyRichPos; AAtEnd: Boolean;
  ARestore: Boolean);
var
  q: TTyRichPos;
  marks: TTyRichStepMarks;
begin
  { The caret and the anchor an edit leaves obey the rule of a user's move: never in a cut
    paragraph's hidden tail (back to the cut). A selection an undo puts back is taken as it was,
    and so is the one a façade's format write keeps. }
  if FApiWrite > 0 then ARestore := True;
  { Inside an update of the document (BeginEdit .. EndEdit, Lines.BeginUpdate, the
    document's own) the view has not heard of the text yet: positions only (the layout is
    asked nothing, Select keeps them for the update's end, which puts them on caret places);
    the scroll and the reports are the update's, at its end. }
  if FDoc.Updating then
  begin
    Inc(FEditing);
    try
      Select(AAnchor, ACaret, AAtEnd);
    finally
      Dec(FEditing);
    end;
    FEditStep := nil;
    FWishValid := False;
    Exit;
  end;
  if not ARestore then
  begin
    ACaret := OutOfTail(ACaret, False);
    AAnchor := OutOfTail(AAnchor, False);
  end;
  Inc(FEditing);
  try
    q := SnapPos(ACaret);
    // the affinity only where the caret stays put (a line's end is that place)
    AAtEnd := AAtEnd and (q = ACaret);
    ACaret := q;
    if AAnchor <> ACaret then AAnchor := SnapPos(AAnchor) else AAnchor := ACaret;
    Select(AAnchor, ACaret, AAtEnd);
  finally
    Dec(FEditing);
  end;
  // where the edit leaves the selection: what a redo of its step puts back
  if FEditStep <> nil then
  begin
    marks := FEditStep.Marks;
    marks.HasAfter := True;
    marks.After.Anchor := FSelAnchor;
    marks.After.Caret := FCaret;
    marks.After.AtLineEnd := FCaretAtEnd;
    FEditStep.Marks := marks;
    FEditStep := nil;
  end;
  FWishValid := False;
  { Not for a commit a press caused (the view stays where the user clicked) nor for a late
    result (the selection it puts back is not at the commit; it reports once itself). }
  // (nor for a façade's format write: the selection stays where it is, and so does the view)
  if not FNoEditScroll and not FEditQuiet and (FApiWrite = 0) then ScrollCaretIntoView;
  CaretMoved;
  if not FEditQuiet then
  begin
    DoChange;
    DoSelectionChange;
  end;
  PayModifiedOwed;
end;

function TTyCustomRichEdit.EditWith(AMake: TTyRichEditMaker; AUser, AEnded: Boolean): Boolean;
var
  life: TTyRichLife;
  r: Boolean;

  procedure Work;
  begin
    r := EditWithIn(AMake, AUser, AEnded);
  end;

begin
  { Every edit through the door (keys, the menu, the table actions, pictures, a drop): a
    handler its report runs may free the control - the call ends there. }
  r := False;
  Guard(life, @Work);
  Result := r and not life.Gone;
end;

function TTyCustomRichEdit.EditWithIn(AMake: TTyRichEditMaker; AUser, AEnded: Boolean): Boolean;
var
  place: TTyRichEditPlace;
  cmd: TTyRichCommand;
  len0, grow, a, q: TTyRichPos;
begin
  Result := False;
  place := Default(TTyRichEditPlace);
  place.Anchor := CRichPlaceChangeEnd;
  place.Caret := CRichPlaceChangeEnd;
  place.CompositionEnded := AEnded;
  cmd := AMake(place);
  if cmd = nil then Exit;
  len0 := FDoc.Text.Length;
  if not RunEdit(cmd, AUser) then Exit;
  if place.ByGrowth then grow := FDoc.Text.Length - len0 else grow := 0;
  case place.Caret of
    CRichPlaceChangeEnd: q := FEditChange.Pos + FEditChange.NewLen;
    CRichPlaceStays: q := FCaret;
    // a table action's: worked out from the table as the edit left it
    CRichPlaceTable: q := TableEditCaret;
    // a drop's: the content where it went
    CRichPlaceInserted: q := TTyRichRangeTransfer(cmd).Placed.Pos +
      TTyRichRangeTransfer(cmd).Placed.Len;
  else
    q := place.Caret + grow;
  end;
  case place.Anchor of
    CRichPlaceChangeEnd: a := q;
    CRichPlaceStays: a := FSelAnchor;
    CRichPlaceInserted: a := TTyRichRangeTransfer(cmd).Placed.Pos;
    CRichPlaceChangeStart: a := FEditChange.Pos;
  else
    a := place.Anchor + grow;
  end;
  FinishEdit(a, q, place.AtLineEnd);
  Result := True;
end;

function TTyCustomRichEdit.RunUserEdit(AMake: TTyRichEditMaker): Boolean;
var
  ended: Boolean;
  reason: string;
begin
  Result := False;
  if FReadOnly or not IsEnabled or ViewBehind then Exit;
  ended := FComposing or FImeRefused;
  EndCompositionForUser;
  // (the commit's own handlers may have made it a viewer, or begun an update)
  if FReadOnly or not IsEnabled or ViewBehind then Exit;
  reason := RefusalReason;
  if reason <> '' then
  begin
    EditRefused(reason);
    Exit;
  end;
  Result := EditWith(AMake, True, ended);
end;

function TTyCustomRichEdit.RunMade(ACmd: TTyRichCommand; const APlace: TTyRichEditPlace;
  AUser: Boolean): Boolean;
var
  keep: TTyRichCommand;
  keepPlace: TTyRichEditPlace;
  keepTaken: PBoolean;
  taken, r: Boolean;
  life: TTyRichLife;

  procedure Work;
  begin
    if AUser then r := RunUserEdit(@TakeMade)
    else r := EditWith(@TakeMade, False, False);
  end;

begin
  Result := False;
  r := False;
  // (kept: an edit inside this one - the commit the door may cause - makes its own)
  keep := FMade;
  keepPlace := FMadePlace;
  keepTaken := FMadeTaken;
  taken := False;
  FMade := ACmd;
  FMadePlace := APlace;
  FMadeTaken := @taken;
  { A handler the edit runs may free the control: nothing of it is touched after that; a
    command the door had not taken yet goes with it. }
  try
    Guard(life, @Work);
  finally
    if life.Gone then
    begin
      if not taken then ACmd.Free;
    end
    else
    begin
      // not taken (the door said no before it asked): it never reached the document
      FreeAndNil(FMade);
      FMade := keep;
      FMadePlace := keepPlace;
      FMadeTaken := keepTaken;
    end;
  end;
  if not life.Gone then Result := r;
end;

function TTyCustomRichEdit.TakeMade(var APlace: TTyRichEditPlace): TTyRichCommand;
begin
  Result := FMade;
  FMade := nil;
  if FMadeTaken <> nil then FMadeTaken^ := True;
  { The control's own callers end a composition before they look at the text; one the door
    found open was committed after this command was made: it is not run on the new text. }
  if APlace.CompositionEnded then
  begin
    FreeAndNil(Result);
    Exit;
  end;
  APlace := FMadePlace;
end;

function TTyCustomRichEdit.TypingFormat: TTyCharFormatId;
var
  t: TTyRichText;
  s: TTyRichPos;
  p: Integer;
begin
  // a format chosen with nothing selected, at this very caret
  if FHasPendingFmt and (FCaret = FSelAnchor) and (FCaret = FPendingAt) then
    Exit(FPendingFmt);
  t := FDoc.Text;
  s := GetSelStart;
  if HasSelection then
  begin
    // typed over: the format of the first character selected (the character before s + 1),
    // unless that is the paragraph's separator
    p := t.ParaOfPos(s);
    if s < t.ParaStart(p) + t.ParaLength(p) then Inc(s);
  end;
  Result := FDoc.TypingFormatAt(s);
end;

function TTyCustomRichEdit.TypingAllowed(var AStart, ALen: TTyRichPos; const AText: UTF8String;
  AUser: Boolean): Boolean;
begin
  Result := EditAllowed(AStart, ALen, AText <> '', AUser) and
    (not AUser or (UserRangeAllowed(AStart, ALen) and not LongParaRefused(AStart, AText)));
end;

procedure TTyCustomRichEdit.TypeText(const AText: UTF8String; AMergeable, AUser: Boolean;
  AFormat: TTyCharFormatId; ACaretChars: Int64);
var
  life: TTyRichLife;

  procedure Work;
  begin
    TypeTextIn(AText, AMergeable, AUser, AFormat, ACaretChars);
  end;

begin
  // (SelText, typing: a handler that frees the control ends the call there)
  Guard(life, @Work);
end;

procedure TTyCustomRichEdit.TypeTextIn(const AText: UTF8String; AMergeable, AUser: Boolean;
  AFormat: TTyCharFormatId; ACaretChars: Int64);
var
  s, n: TTyRichPos;
  fmt: TTyCharFormatId;
  cmd: TTyRichCommand;
  comp: TTyRichCompositeCommand;
  place: TTyRichEditPlace;
  f, l: Integer;
begin
  s := GetSelStart;
  n := GetSelLength;
  // cells selected: what is typed replaces the first cell's content (the others stay, as Word)
  if AUser and (n > 0) and (AText <> '') and TyRichCellsEditable(CellArea) then
    if FirstAreaCell(CellArea, f, l) then
    begin
      s := FDoc.Text.ParaStart(f);
      n := FDoc.Text.ParaStart(l) + FDoc.Text.ParaLength(l) - s;
    end;
  if (AText = '') and (n = 0) then Exit;
  if not TypingAllowed(s, n, AText, AUser) then Exit;
  if (AText = '') and (n = 0) then Exit;
  if AFormat = Low(TTyCharFormatId) then fmt := TypingFormat else fmt := AFormat;
  if n = 0 then
    cmd := TTyRichInsertText.Create(s, AText, fmt, AMergeable)
  else if AText = '' then
    cmd := TTyRichDelete.Create(s, n)
  else
  begin
    { One undo step. A fresh one, as the memo's: typing after it merges into a step of its
      own (the composite takes nothing over), so an undo takes back that typing first. }
    if AMergeable then comp := TTyRichCompositeCommand.Create(rsRichUndoTyping)
    else comp := TTyRichCompositeCommand.Create(rsRichUndoInsertText);
    comp.Add(TTyRichDelete.Create(s, n));
    comp.Add(TTyRichInsertText.Create(s, AText, fmt, False));
    cmd := comp;
  end;
  { Behind what went in (a paragraph separator is one character: after Enter, the new
    paragraph's start) - a commit counts its own text (its change may be a composite's). A
    user's typing goes through the door of a user's edit, as every key's edit does. }
  place := Default(TTyRichEditPlace);
  place.Anchor := CRichPlaceChangeEnd;
  if ACaretChars >= 0 then place.Caret := s + ACaretChars
  else place.Caret := CRichPlaceChangeEnd;
  RunMade(cmd, place, AUser);
end;

{ Where most of the control's edits leave the selection: a caret behind what changed. }
function ChangeEndPlace: TTyRichEditPlace;
begin
  Result := Default(TTyRichEditPlace);
  Result.Anchor := CRichPlaceChangeEnd;
  Result.Caret := CRichPlaceChangeEnd;
end;

procedure TTyCustomRichEdit.DeleteText(AFrom, ATo: TTyRichPos; AUser: Boolean);
begin
  if ATo <= AFrom then Exit;
  if not EditAllowed(AFrom, ATo - AFrom, False, AUser) then Exit;
  // the caret at the join
  RunMade(TTyRichDelete.Create(AFrom, ATo - AFrom), ChangeEndPlace, AUser);
end;

{ The bytes of the control character at S[I] - C0, DEL, C1 (U+0080 .. U+009F, C2 80 .. C2 9F
  in UTF-8) - else 0: what is never typed, by a key (TypeKey) or by an input method's commit
  (ImeText, which keeps tab, LF and U+000B as its line breaks). }
function ControlCodeLen(const S: RawByteString; I: Integer): Integer;
begin
  Result := 0;
  if (I < 1) or (I > Length(S)) then Exit;
  if (S[I] < #32) or (S[I] = #127) then Result := 1
  else if (S[I] = #$C2) and (I < Length(S)) and (S[I + 1] >= #$80) and (S[I + 1] < #$A0) then
    Result := 2;
end;

{ The one code point Backspace takes when it is the last of a cluster and not its start: a
  combining mark (an accent, a vowel sign, a Hangul jamo after the first) - as the edit
  controls of Windows do, so that a wrong accent is typed again without its letter. A
  variation selector, a joiner, an emoji modifier or tag ends an emoji that is one picture:
  the cluster goes whole. }
function BackspaceTakesOne(ACode: Cardinal): Boolean;
begin
  Result := TyRichIsClusterExtend(ACode) and not ((ACode = $200C) or (ACode = $200D) or
    ((ACode >= $FE00) and (ACode <= $FE0F)) or ((ACode >= $1F3FB) and (ACode <= $1F3FF)) or
    ((ACode >= $E0020) and (ACode <= $E007F)) or ((ACode >= $E0100) and (ACode <= $E01EF)));
end;

procedure TTyCustomRichEdit.DeleteKey(AForward, AWord: Boolean);
var
  t: TTyRichText;
  p: Integer;
  ps, pe, a, b, s, n, reach, reachEnd: TTyRichPos;
  codes: TTyRichCodes;
begin
  // cells selected: Delete clears them, Backspace takes whole rows or the table
  if HasSelection and CellsKey(AForward) then Exit;
  if HasSelection then
  begin
    s := GetSelStart;
    n := GetSelLength;
    if not EditAllowed(s, n, False, True) or not UserRangeAllowed(s, n) then Exit;
    DeleteText(s, s + n, True);
    Exit;
  end;
  { The caret inside a field's result: the key is an edit inside it, refused and told - not a
    selection of a field near it. }
  if InsideOneResult(FCaret, FCaret) then
  begin
    Refuse(rsRichEditRefusedField, True);
    Exit;
  end;
  t := FDoc.Text;
  p := t.ParaOfPos(FCaret);
  ps := t.ParaStart(p);
  pe := ps + t.ParaLength(p);
  { Backspace at the start of a list item (empty or not) takes its numbering first, as
    Windows' rich edit and Word do; the next Backspace joins it with the paragraph before. }
  if not AForward and (FCaret = ps) and
    (FDoc.Formats.ParaFormat(FDoc.ParaFormatOf(p)).List.Kind <> lkNone) then
  begin
    LeaveList(p);
    Exit;
  end;
  { A key acts on the nearest thing with a width its way - [a, b): objects with none between
    the caret and it (a bookmark's ends, a field that shows nothing) are passed over and
    stay. A thing across a mark of a field that shows something is not taken: the field is
    selected instead (whole, every field the key's reach cut), nothing told - the key's
    effect there; the next press acts on the selection. }
  if AForward then
  begin
    a := UnseenEnd(FCaret, True);
    // at the document's end nothing happens, and nothing goes on the history
    if a >= t.Length then Exit;
    // at a paragraph's end (Ctrl too, as the memo): the separator, the next paragraph joins
    if a >= pe then b := pe + 1
    else if AWord then b := WordStep(FCaret, True)
    else b := CaretStep(FCaret, True);
    { A step that leaves the paragraph before its end is the cut of a paragraph too long to
      lay out whole: what lies past it is not shown, and a key does not take it. }
    if (b > pe + 1) or ((b > pe) and (a < pe)) then Exit;
    // (a step ends on a resting place, which may be past marks behind the thing)
    b := UnseenEnd(b, False);
    reach := FCaret;
    reachEnd := b;
  end
  else
  begin
    b := UnseenEnd(FCaret, False);
    if b <= 0 then Exit;
    // at a paragraph's start (Ctrl too, as the memo): the separator before it
    if b <= ps then a := ps - 1
    else if AWord then a := WordStep(FCaret, False)
    else
    begin
      codes := RichCodes(t.GetText(b - 1, 1));
      if (Length(codes) = 1) and BackspaceTakesOne(codes[0]) then a := b - 1
      else a := CaretStep(FCaret, False);
    end;
    a := UnseenEnd(a, True);
    reach := a;
    reachEnd := FCaret;
  end;
  if a >= b then Exit;
  s := reach;
  n := reachEnd - reach;
  if not FieldCover(s, n) then
  begin
    s := a;
    n := b - a;
    if not FieldCover(s, n) then n := -1;
  end;
  if n >= 0 then
  begin
    if s > reach then
    begin
      n := n + s - reach;
      s := reach;
    end;
    if s + n < reachEnd then n := reachEnd - s;
    ShowCover(s, n);
    Exit;
  end;
  { A key that would take whole fields (a word that holds them) selects them first too: the
    next press deletes what is shown selected. }
  if TakesField(a, b) then
  begin
    s := Math.Min(a, reach);
    ShowCover(s, Math.Max(b, reachEnd) - s);
    Exit;
  end;
  if KeyDeleteAllowed(a, b) then DeleteText(a, b, True);
end;

function TTyCustomRichEdit.TakesField(AFrom, ATo: TTyRichPos): Boolean;
var
  s: UTF8String;
  i, q: PtrInt;
  c: TTyRichPos;
begin
  Result := False;
  if ATo <= AFrom then Exit;
  s := FDoc.Text.GetText(AFrom, ATo - AFrom);
  // (an object's character found in the bytes, its place counted in characters)
  q := 1;
  c := AFrom;
  while q <= Length(s) do
  begin
    if (Byte(s[q]) = $EF) and (Copy(s, q, 3) = TyRichObjectChar) and
      (FDoc.ObjectAt(c) is TTyRichFieldMark) then
      Exit(True);
    i := 1;
    if Byte(s[q]) >= $F0 then i := 4
    else if Byte(s[q]) >= $E0 then i := 3
    else if Byte(s[q]) >= $C0 then i := 2;
    Inc(q, i);
    Inc(c);
  end;
end;

function TTyCustomRichEdit.KeyDeleteAllowed(AFrom, ATo: TTyRichPos): Boolean;
var
  t: TTyRichText;
  k, m: Integer;
  b: TTyBlockLayout;
begin
  t := FDoc.Text;
  k := t.ParaOfPos(AFrom);
  m := t.ParaOfPos(ATo);
  if m = k then Exit(True);
  // (the cells are compared inside one read: a document that parses on demand keeps them)
  FDoc.BeginRead;
  try
    { Across a cell's edge - two cells, a cell and the text before or after its table - Word
      and WordPad do nothing (the engine would merge the two paragraphs and leave a cell
      without one): neither does a key. A selection that spans cells is the engine's rule. }
    if FDoc.CellAt(k) <> FDoc.CellAt(m) then Exit(False);
    { The separator after a cut paragraph: the paragraph after it would go into the part of
      that one not shown, with the caret. }
    EnsureParams;
    b := LayoutBlockAt(k);
    try
      Result := not ((b is TTyParaLayout) and (b.LastCaretPos < t.ParaLength(k)));
    finally
      b.Release;
    end;
  finally
    FDoc.EndRead;
  end;
end;

procedure TTyCustomRichEdit.ParagraphKey;
var
  t: TTyRichText;
  p: Integer;
  pf: TTyParaFormat;
begin
  if not HasSelection then
  begin
    t := FDoc.Text;
    p := t.ParaOfPos(FCaret);
    pf := FDoc.Formats.ParaFormat(FDoc.ParaFormatOf(p));
    if (pf.List.Kind <> lkNone) and (t.ParaLength(p) = 0) then
    begin
      { An empty list item: Enter ends the list there - the item itself becomes a plain
        paragraph, nothing is added (Word's way; Windows' rich edit adds one), the caret stays. }
      LeaveList(p);
      Exit;
    end;
  end;
  { A new paragraph: the engine gives both parts the paragraph's format (as WordPad), and a
    new empty paragraph the format given here - the typing format. }
  TypeText(#10, False, True);
end;

function TTyCustomRichEdit.PlainTextDocument: Boolean;
begin
  Result := FPlainText;
end;

function TTyCustomRichEdit.LongParaRefused(APos: TTyRichPos; const AText: UTF8String): Boolean;
var
  t: TTyRichText;
begin
  Result := False;
  // a paragraph break puts the caret at the next paragraph's start, which is shown
  if (AText = '') or (Pos(#10, AText) > 0) then Exit;
  t := FDoc.Text;
  { Past the cut the text would go in unseen, with the caret: the user is told instead
    (EditRefused, as for any edit the document refuses) - the paragraph is too long to edit
    there. }
  if APos - t.ParaStart(t.ParaOfPos(APos)) + UTF8Length(AText) <= CRichMaxParaLayoutChars then
    Exit;
  Result := True;
  Refuse(rsRichEditRefusedLongPara, True);
end;

function TTyCustomRichEdit.WholeRows(AFrom, ATo: TTyRichPos): Boolean;
begin
  Result := FDoc.WholeRows(AFrom, ATo);
end;

function TTyCustomRichEdit.UserRangeAllowed(var AStart, ALen: TTyRichPos): Boolean;
begin
  // the document's rule, the one a find's replace asks too
  Result := FDoc.UserRangeAllowed(AStart, ALen);
  { Told once the read scope is closed: a handler that loads a document (or waits on a
    dialog) must not meet it open. }
  if not Result then Refuse(rsRichEditRefusedCells, True);
end;

procedure TTyCustomRichEdit.LeaveList(AIndex: Integer);
var
  place: TTyRichEditPlace;
begin
  if not EditAllowed(FDoc.Text.ParaStart(AIndex), 0, True, True) then Exit;
  // a format change: the caret stays where it is, at its side of a line's end
  place := Default(TTyRichEditPlace);
  place.Anchor := CRichPlaceChangeEnd;
  place.Caret := CRichPlaceStays;
  place.AtLineEnd := FCaretAtEnd;
  // the list's own rule, the one Paragraph.Numbering := nsNone follows (CTyListMask)
  RunMade(TTyRichSetParaFormat.Create(AIndex, AIndex, CTyListMask,
    TyRichListValue(TyDefaultParaFormat.List)), place, True);
end;

{ ---- tables: the user's actions, Tab, and what an action's Update asks ----

  The actions are user's edits through the one door (RunUserEdit); the engine's commands do
  the work (TTyRichInsertTable and the row and column commands), and its reasons are told in
  the control's words (TableRefusalText). Where an action leaves the caret depends on the
  table as the edit left it, so the door is handed CRichPlaceTable and TableEditCaret works
  it out from paragraphs whose numbers the action knew before (FAim...). The row and column
  actions act on the table object the caret is in - the engine's rule; a table a file read
  on demand gives in parts is one table to them when its loader can give it whole, and
  refused otherwise. Tab goes by what a person sees instead: the laid-out row blocks and
  the cells of the paragraphs next to them, never a walk of the table. }

function TTyCustomRichEdit.TableRefusalText(AReason: TTyRichTableRefusal;
  const AEdit: TTyRichTableEdit): string;
begin
  case AReason of
    rtrReadOnly:
      begin
        // the document's state: loading, incomplete, being saved
        Result := RefusalReason;
        if Result = '' then Result := rsRichEditRefusedRange;
      end;
    rtrNoTable: Result := rsRichEditRefusedNoTable;
    rtrInTable: Result := rsRichEditRefusedTableInTable;
    rtrMergedCells: Result := rsRichEditRefusedMergedCells;
    rtrNestedTable:
      if AEdit.Kind = rtkMergeCells then Result := rsRichEditRefusedMergeNested
      else if AEdit.Kind = rtkSplitCell then Result := rsRichEditRefusedSplitNested
      else Result := rsRichEditRefusedNestedTable;
    rtrNotRectangle: Result := rsRichEditRefusedNotRectangle;
    rtrNotWhole: Result := rsRichEditRefusedTableNotWhole;
    rtrIrregularRows: Result := rsRichEditRefusedIrregularRows;
    rtrInField: Result := rsRichEditRefusedField;
    rtrOutOfRange:
      // (a row or cell index out of range is no person's doing: the actions name existing ones)
      if AEdit.Kind = rtkInsertTable then
        Result := Format(rsRichEditRefusedTableSize, [CRichMaxTableRows, CRichMaxTableCols])
      else if AEdit.Kind = rtkInsertColumn then
        Result := Format(rsRichEditRefusedTableColumns, [CRichMaxTableCols])
      else if AEdit.Kind = rtkMergeCells then
        // (one cell, or a cell merged already, selected whole: nothing to merge)
        Result := rsRichEditRefusedMergeWhich
      else if AEdit.Kind = rtkSplitCell then
        Result := SplitRefusalText(AEdit)
      else
        Result := rsRichEditRefusedRange;
  else
    Result := rsRichEditRefusedRange;
  end;
end;

function TTyCustomRichEdit.TableActionsOpen: Boolean;
begin
  Result := not FReadOnly and IsEnabled and not ViewBehind and (RefusalReason = '') and
    not PlainTextDocument;
end;

function TTyCustomRichEdit.CaretTablePara: Integer;
var
  t: TTyRichText;
  q, a: TTyRichPos;
  ka, m, i: Integer;
  ca, cb, cl, cn: TTyRichCell;
  run: Boolean;

  // read already (a file read on demand gives its paragraphs only when asked)
  function Known(AIndex: Integer): Boolean;
  begin
    Result := (AIndex < 0) or (AIndex >= t.ParaCount) or (FDoc.Loader = nil) or
      (t.ParaData[AIndex] <> nil);
  end;

begin
  FCaretParaUnread := False;
  t := FDoc.Text;
  // cells selected: the table of the selection (see CaretCellPara)
  if (FCaret <> FSelAnchor) and CellArea.Range.InTable then Exit(CaretCellPara);
  q := Math.Min(FCaret, t.Length);
  Result := t.ParaOfPos(q);
  if (FSelAnchor >= q) or (Result = 0) or (q <> t.ParaStart(Result)) or (q >= t.Length) then
    Exit;
  m := Result;
  ka := t.ParaOfPos(FSelAnchor);
  // (from after the zero-width marks at a row's start: from the row's start)
  a := FSelAnchor;
  if a <> t.ParaStart(ka) then
  begin
    if not FDoc.AtParaStart(a) then Exit;
    a := t.ParaStart(ka);
  end;
  { Whole rows are told by the anchor's paragraph and the one before it, and the caret's and
    the one before it: when one of them is not read yet, nothing is read just to answer -
    the caret's own paragraph, and the answer is not kept. }
  if not (Known(ka) and Known(ka - 1) and Known(m) and Known(m - 1)) then
  begin
    FCaretParaUnread := True;
    Exit;
  end;
  FDoc.BeginRead;
  try
    if FDoc.WholeRows(a, q) then
      Dec(Result)
    else
    begin
      { Whole rows of the table a person sees, whatever objects hold it (two that came to
        touch): from a row's first paragraph to the end of a row, every paragraph between in
        a table - walked only in this case, and only while read. }
      ca := FDoc.CellAt(ka);
      cl := FDoc.CellAt(m - 1);
      if (ca = nil) or (cl = nil) or (ca.Row.Table = cl.Row.Table) then Exit;
      if ka > 0 then
      begin
        cb := FDoc.CellAt(ka - 1);
        if (cb <> nil) and (cb.Row = ca.Row) then Exit;
      end;
      cn := FDoc.CellAt(m);
      if (cn <> nil) and (cn.Row = cl.Row) then Exit;
      run := True;
      for i := ka + 1 to m - 2 do
      begin
        if not Known(i) then
        begin
          FCaretParaUnread := True;
          run := False;
          Break;
        end;
        if FDoc.CellAt(i) = nil then
        begin
          run := False;
          Break;
        end;
      end;
      if run then Dec(Result);
    end;
  finally
    FDoc.EndRead;
  end;
end;

function TTyCustomRichEdit.RunTableAction(AKind: Integer): Boolean;
begin
  Result := False;
  // a user action is an entry point of the loop (see SchedulingFailed)
  EndOwedLoad;
  { The door's own first step, taken here: what the input method shows goes in before the
    action is set up (its commit's handlers may ask an action of their own). }
  EndCompositionForUser;
  if not IsEnabled or ViewBehind then Exit;
  // a viewer does nothing and tells nothing, as for its other user's actions
  if FReadOnly then Exit;
  // a table cannot be saved into a text file
  if PlainTextDocument then
  begin
    EditRefused(rsRichEditRefusedPlainTable);
    Exit;
  end;
  FTableKind := AKind;
  Result := RunUserEdit(@MakeTableEditThen);
end;

{ MakeTableEdit's command, and after it in the same step the agreement of the lines its rows
  and columns share (FAgreeRow0 .. FAgreeRow1 of the table at FAgreePos, when it set them:
  TTyRichAgreeEdges) and what FTableThen holds (taken over: the lone marks of the rows it
  deletes). }
function TTyCustomRichEdit.MakeTableEditThen(var APlace: TTyRichEditPlace): TTyRichCommand;
var
  comp: TTyRichCompositeCommand;
begin
  FAgreeRow0 := -2;
  Result := MakeTableEdit(APlace);
  if Result = nil then Exit;
  if (FAgreeRow0 = -2) and ((FTableThen = nil) or (FTableThen.Count = 0)) then Exit;
  comp := TTyRichCompositeCommand.Create(Result.Description);
  comp.Add(Result);
  // (rows or columns in or out: the lines the cells share stay one definition each)
  if FAgreeRow0 <> -2 then comp.Add(TTyRichAgreeEdges.Create(FAgreePos, FAgreeRow0, FAgreeRow1));
  if (FTableThen <> nil) and (FTableThen.Count > 0) then
  begin
    comp.Add(FTableThen);
    FTableThen := nil;
  end;
  Result := comp;
end;

function TTyCustomRichEdit.MakeTableEdit(var APlace: TTyRichEditPlace): TTyRichCommand;
var
  t: TTyRichText;
  s, e, pos, from, stop: TTyRichPos;
  k, ks, ke, p1, p2, r1, r2, c1, c2, m, n, lastFirst, ri, rc: Integer;
  cols: array of Boolean;
  info: TTyRichTableInfo;
  why: TTyRichTableRefusal;
  reason: string;
  comp: TTyRichCompositeCommand;
  row: TTyRichRow;
  area: TTyRichCellArea;
  gx0, gx1: Integer;
  whole: Boolean;

  // the selection's extent in twips (the area's, else the caret's cell's)
  procedure GridSpanOf(const AArea: TTyRichCellArea; APara: Integer; out AX0, AX1: Integer);
  var
    l, r: Int64;
    c: TTyRichCell;
  begin
    if AArea.Range.InTable and not AArea.AllCells and (AArea.Table = FDoc.CellAt(APara).Table) then
    begin
      AX0 := Integer(AArea.X0);
      AX1 := Integer(AArea.X1);
      Exit;
    end;
    c := FDoc.CellAt(APara);
    TyRichCellExtent(c.Row, c.Index, l, r);
    AX0 := Integer(l);
    AX1 := Integer(r);
    if AArea.Range.InTable and AArea.AllCells then
    begin
      // (rows reached from outside: every column)
      AX0 := -MaxInt div 2;
      AX1 := MaxInt div 2;
    end;
  end;

  // the caret's row with AX1 - AX0 more twips: wider than a table may be made
  function TooWideWith(APara, AX0, AX1: Integer): Boolean;
  var
    rw: TTyRichRow;
    ee: TTyRichEdges;
  begin
    Result := False;
    if area.Range.InTable and area.AllCells then Exit;
    rw := FDoc.CellAt(APara).Row;
    ee := rw.CellEdges;
    if Length(ee) = 0 then Exit;
    Result := Int64(ee[High(ee)]) + (Int64(AX1) - AX0) - rw.Format.Row.LeftTwips > CRichMaxTableTwips;
  end;

  // the row of table paragraph AP, counted from the caret's row (rows never cross objects)
  function RowOf(AP: Integer): Integer;
  var
    i: Integer;
    r: TTyRichRow;
  begin
    Result := info.Row;
    r := FDoc.CellAt(k).Row;
    if AP > k then
      for i := k + 1 to AP do
      begin
        if FDoc.CellAt(i).Row <> r then Inc(Result);
        r := FDoc.CellAt(i).Row;
      end
    else
      for i := k - 1 downto AP do
      begin
        if FDoc.CellAt(i).Row <> r then Dec(Result);
        r := FDoc.CellAt(i).Row;
      end;
  end;

  // the first paragraph of the table's last row
  function LastRowFirst: Integer;
  var
    r: TTyRichRow;
  begin
    Result := info.Last;
    r := FDoc.CellAt(info.Last).Row;
    while (Result > info.First) and (FDoc.CellAt(Result - 1).Row = r) do Dec(Result);
  end;

  { Rows AFrom (a row's first paragraph) to the table's last, of a table that ends the text,
    as one step (ADescription): a deletion would join what is left with the text's last
    paragraph, which is a cell - the engine's command for the last row leaves a paragraph in
    no table after the table, and the rows before it go as text up to that paragraph. }
  function RowsToTheEnd(AFrom: Integer; const ADescription: string): TTyRichCommand;
  begin
    lastFirst := LastRowFirst;
    if lastFirst <= AFrom then Exit(TTyRichDeleteRow.Create(pos, info.RowCount - 1));
    comp := TTyRichCompositeCommand.Create(ADescription);
    comp.Add(TTyRichDeleteRow.Create(pos, info.RowCount - 1));
    // (the paragraph the engine leaves stands where the last row began)
    comp.Add(TTyRichDelete.Create(t.ParaStart(AFrom), t.ParaStart(lastFirst) - t.ParaStart(AFrom)));
    Result := comp;
  end;

  // the whole table (info) goes, one step; the caret to what followed it
  function WholeTable(ARowWhy: TTyRichTableRefusal): TTyRichCommand;
  begin
    Result := nil;
    FTableKind := CTableDeleteTable;
    FAgreeRow0 := -2;
    FAimPara := info.First;
    if info.Last < t.ParaCount - 1 then
    begin
      // whole rows, up to the paragraph after them
      from := t.ParaStart(info.First);
      comp := TTyRichCompositeCommand.Create(rsRichUndoDeleteTable);
      comp.Add(TTyRichDelete.Create(from, t.ParaStart(info.Last + 1) - from));
      Result := comp;
    end
    else if ARowWhy <> rtrNone then
      // (a table that ends the text and whose rows cannot change: made so by code only)
      reason := TableRefusalText(ARowWhy, TyRichTableEdit(rtkDeleteRow, pos, 0))
    else
      Result := RowsToTheEnd(info.First, rsRichUndoDeleteTable);
  end;

begin
  Result := nil;
  reason := '';
  t := FDoc.Text;
  APlace.Anchor := CRichPlaceChangeEnd;
  APlace.Caret := CRichPlaceTable;
  FAimPara := 0;
  FAimRow := 0;
  FAimCell := 0;
  FAimFollows := False;
  FAimBefore := False;
  if FTableKind = CTableInsertTable then
  begin
    // at the selection's start; the selected text stays (the engine says why it refuses)
    s := GetSelStart;
    FAimPara := t.ParaOfPos(s);
    Exit(TTyRichInsertTable.Create(s, FTableRows, FTableCols));
  end;
  k := CaretTablePara;
  pos := t.ParaStart(k);
  if FTableKind in [CTableInsertRow, CTableTabRow] then
  begin
    { A row beside the caret's row: the engine finds that row in the read it makes anyway
      (CRichRowAbove / CRichRowBelow); here only the caret's row is looked at, for where the
      new row's first paragraph will be. }
    FDoc.BeginRead;
    try
      if FDoc.CellAt(k) = nil then
        reason := rsRichEditRefusedNoTable
      else
      begin
        row := FDoc.CellAt(k).Row;
        p1 := k;
        while (p1 > 0) and (FDoc.CellAt(p1 - 1) <> nil) and (FDoc.CellAt(p1 - 1).Row = row) do
          Dec(p1);
        p2 := k;
        while (p2 < t.ParaCount - 1) and (FDoc.CellAt(p2 + 1) <> nil) and
          (FDoc.CellAt(p2 + 1).Row = row) do
          Inc(p2);
        { Cells selected in this table: as many rows as they span, above the first or below
          the last (Word's way) }
        n := 1;
        if FTableKind = CTableInsertRow then
        begin
          area := CellArea;
          if area.Range.InTable and (area.Table = row.Table) then
          begin
            n := area.Range.Row1 - area.Range.Row0 + 1;
            if FTableAfter then k := area.LastPara else k := area.FirstPara;
            pos := t.ParaStart(k);
            row := FDoc.CellAt(k).Row;
            p1 := k;
            while (p1 > 0) and (FDoc.CellAt(p1 - 1) <> nil) and (FDoc.CellAt(p1 - 1).Row = row) do
              Dec(p1);
            p2 := k;
            while (p2 < t.ParaCount - 1) and (FDoc.CellAt(p2 + 1) <> nil) and
              (FDoc.CellAt(p2 + 1).Row = row) do
              Inc(p2);
          end
          { The caret in a cell merged down stands for the cell: as many rows as it covers,
            above its first row or below its last }
          else if MergedRowsOf(k, m, c1, c2) then
          begin
            n := m;
            if FTableAfter then
            begin
              k := c1;
              pos := t.ParaStart(k);
              p1 := c1;
              p2 := c2;
            end;
          end;
        end;
        // the rows beside the new ones share lines with them
        if FDoc.TableRowIndex(k, ri, rc) then
        begin
          FAgreePos := pos;
          FAgreeRow0 := ri - 1;
          FAgreeRow1 := ri + n + 1;
        end;
        // (Tab's row: below the caret's row, the last of the table a person sees)
        if (FTableKind = CTableTabRow) or FTableAfter then
        begin
          FAimPara := p2 + 1;
          Result := TTyRichInsertRow.Create(pos, CRichRowBelow);
          if n > 1 then
          begin
            comp := TTyRichCompositeCommand.Create(rsRichUndoInsertRow);
            comp.Add(Result);
            for m := 2 to n do comp.Add(TTyRichInsertRow.Create(pos, CRichRowBelow));
            Result := comp;
          end;
        end
        else
        begin
          FAimPara := p1;
          Result := TTyRichInsertRow.Create(pos, CRichRowAbove);
          if n > 1 then
          begin
            comp := TTyRichCompositeCommand.Create(rsRichUndoInsertRow);
            comp.Add(Result);
            for m := 2 to n do comp.Add(TTyRichInsertRow.Create(pos, CRichRowAbove));
            Result := comp;
          end;
        end;
      end;
    finally
      FDoc.EndRead;
    end;
    if reason <> '' then EditRefused(reason);
    Exit;
  end;
  if not FDoc.TableInfoAt(k, info) then
  begin
    EditRefused(rsRichEditRefusedNoTable);
    Exit;
  end;
  FDoc.BeginRead;
  try
    case FTableKind of
      CTableInsertColumn:
        begin
          FAimPara := info.First;
          FAimRow := info.Row;
          FAimCell := info.Cell + Ord(FTableAfter);
          // cells selected in this table: as many columns as they span, left of the first or
          // right of the last
          n := 1;
          area := CellArea;
          if area.Range.InTable and (area.Table = FDoc.CellAt(k).Table) then
          begin
            n := area.Range.Col1 - area.Range.Col0 + 1;
            if FTableAfter then FAimCell := area.Range.Col1 + 1 else FAimCell := area.Range.Col0;
          end;
          FAgreePos := t.ParaStart(info.First);
          FAgreeRow0 := 0;
          FAgreeRow1 := MaxInt;
          GridSpanOf(area, k, gx0, gx1);
          // (what forbids every column - a nested table, a part not read whole - says so first)
          why := FDoc.TableEditRefusal(TyRichTableEdit(rtkInsertColumn, pos, 0));
          // (told below, once the read scope is closed)
          if not (why in [rtrNone, rtrIrregularRows, rtrOutOfRange]) then
            reason := TableRefusalText(why, TyRichTableEdit(rtkInsertColumn, pos, 0))
          else if TooWideWith(k, gx0, gx1) then
            // (the new columns as wide as those they go beside: past the widest a table may be)
            reason := Format(rsRichEditRefusedTableWidth, [CRichMaxTableTwips div 1440])
          else
          begin
            Result := GridColumnsEdit(t.ParaStart(info.First), gx0, gx1, True, FTableAfter, whole);
            if Result <> nil then Exit;
          end;
          Result := TTyRichInsertColumn.Create(pos, FAimCell);
          if n > 1 then
          begin
            comp := TTyRichCompositeCommand.Create(rsRichUndoInsertColumn);
            comp.Add(Result);
            for m := 2 to n do comp.Add(TTyRichInsertColumn.Create(pos, FAimCell));
            Result := comp;
          end;
        end;
      CTableDeleteTable:
        begin
          why := FDoc.TableEditRefusal(TyRichTableEdit(rtkDeleteRow, pos, 0));
          // what keeps the rows and columns from changing does not keep the table
          if why in [rtrNone, rtrMergedCells, rtrNestedTable, rtrIrregularRows] then
            Result := WholeTable(why)
          // (the table cannot be read whole: deleting it is what cannot be done)
          else if why = rtrNotWhole then
            reason := rsRichEditRefusedDeleteNotWhole
          else
            reason := TableRefusalText(why, TyRichTableEdit(rtkDeleteRow, pos, 0));
        end;
    else
      begin
        // the paragraphs the selection touches, in the caret's table
        s := GetSelStart;
        e := s + GetSelLength;
        ks := t.ParaOfPos(s);
        ke := t.ParaOfPos(e);
        if (e > s) and (ke > ks) and (e = t.ParaStart(ke)) then Dec(ke);
        p1 := Math.Max(ks, info.First);
        p2 := Math.Min(ke, info.Last);
        if p1 > k then p1 := k;
        if p2 < k then p2 := k;
        if FTableKind = CTableDeleteRow then
        begin
          { What is highlighted is what goes: the cells' rows as the area grew them over merged
            cells; a caret in a cell merged down stands for every row the cell covers }
          area := CellArea;
          if area.Range.InTable and (area.Table = FDoc.CellAt(k).Table) then
          begin
            p1 := Math.Max(area.FirstPara, info.First);
            p2 := Math.Min(area.LastPara, info.Last);
          end
          else if (GetSelLength = 0) and MergedRowsOf(k, m, c1, c2) then
            p2 := Math.Max(p2, c2);
          r1 := RowOf(p1);
          r2 := RowOf(p2);
          // the first paragraph of row r1, and the last of row r2
          row := FDoc.CellAt(p1).Row;
          while (p1 > info.First) and (FDoc.CellAt(p1 - 1).Row = row) do Dec(p1);
          row := FDoc.CellAt(p2).Row;
          while (p2 < info.Last) and (FDoc.CellAt(p2 + 1).Row = row) do Inc(p2);
          FAimPara := p1;
          FAimCell := FDoc.CellAt(k).Index;
          FAimFollows := r2 < info.RowCount - 1;
          FAimBefore := r1 > 0;
          { selected rows: the caret to the start of the row that takes their place, else to
            the paragraph after the table }
          if CellArea.Range.InTable then
          begin
            FAimCell := 0;
            FAimBefore := False;
          end;
          // the rows before and after those that go come to share a line
          FAgreePos := t.ParaStart(info.First);
          FAgreeRow0 := r1 - 1;
          FAgreeRow1 := r1;
          // (a merge down in or beside them: row by row, its content kept)
          if not ((r1 = 0) and (r2 = info.RowCount - 1)) then
            Result := SpanRowsDelete(t.ParaStart(info.First), r1, r2, p1);
          if Result <> nil then
          else if r1 = r2 then
            Result := TTyRichDeleteRow.Create(pos, r1)
          else
          begin
            why := FDoc.TableEditRefusal(TyRichTableEdit(rtkDeleteRow, pos, r1));
            if why <> rtrNone then
              reason := TableRefusalText(why, TyRichTableEdit(rtkDeleteRow, pos, r1))
            else if (r1 = 0) and (r2 = info.RowCount - 1) then
              Result := WholeTable(why)
            else
            begin
              { Several rows: whole rows go as text (one deletion, not a table edit per row);
                the rows the table object keeps without paragraphs count for nothing. }
              from := t.ParaStart(p1);
              if p2 < info.Last then stop := t.ParaStart(p2 + 1)
              else if info.Last < t.ParaCount - 1 then stop := t.ParaStart(info.Last + 1)
              else
                stop := -1;
              if stop >= 0 then
              begin
                comp := TTyRichCompositeCommand.Create(rsRichUndoDeleteRow);
                comp.Add(TTyRichDelete.Create(from, stop - from));
                Result := comp;
              end
              else
                Result := RowsToTheEnd(p1, rsRichUndoDeleteRow);
            end;
          end;
        end
        else
        begin
          { Columns: those of the selected cells - the rectangle's (rows reached from outside the
            table: all of them) - else the caret's cell's; counted by the grid, never in text
            order. (Rows of different cells the engine refuses for columns.) }
          SetLength(cols, info.CellCount);
          area := CellArea;
          if area.Range.InTable and (area.Table = FDoc.CellAt(k).Table) then
          begin
            c1 := area.Range.Col0;
            c2 := area.Range.Col1;
            if area.AllCells then c2 := High(cols);
            // (the caret to the selection's first row)
            ri := area.Range.Row0;
          end
          else
          begin
            c1 := Math.Min(FDoc.CellAt(k).Index, High(cols));
            c2 := c1;
            ri := info.Row;
          end;
          for m := 0 to High(cols) do cols[m] := (m >= c1) and (m <= c2);
          n := 0;
          c1 := -1;
          for m := High(cols) downto 0 do
            if cols[m] then
            begin
              Inc(n);
              c1 := m;
            end;
          FAimPara := info.First;
          FAimRow := ri;
          FAimCell := c1;
          FAgreePos := t.ParaStart(info.First);
          FAgreeRow0 := 0;
          FAgreeRow1 := MaxInt;
          // (no plain grid: by the grid's columns under the selection)
          GridSpanOf(area, k, gx0, gx1);
          why := FDoc.TableEditRefusal(TyRichTableEdit(rtkDeleteColumn, pos, 0));
          if not (why in [rtrNone, rtrIrregularRows, rtrOutOfRange]) then
            whole := False
          else
            Result := GridColumnsEdit(t.ParaStart(info.First), gx0, gx1, False, False, whole);
          if not (why in [rtrNone, rtrIrregularRows, rtrOutOfRange]) then
            reason := TableRefusalText(why, TyRichTableEdit(rtkDeleteColumn, pos, 0))
          else if whole then
          begin
            FreeAndNil(Result);
            Result := WholeTable(rtrNone);
          end
          else if Result <> nil then
          else if n = 1 then
            Result := TTyRichDeleteColumn.Create(pos, c1)
          else
          begin
            why := FDoc.TableEditRefusal(TyRichTableEdit(rtkDeleteColumn, pos, c1));
            if why <> rtrNone then
              reason := TableRefusalText(why, TyRichTableEdit(rtkDeleteColumn, pos, c1))
            else if n = Length(cols) then
              Result := WholeTable(why)
            else
            begin
              { Right to left: the cell indexes of those still to go stay as they were. Each
                part names the table by the start of its first paragraph: a part deletes cells
                of every row, so a place inside the table (the caret's) would move into the
                rows below or past the table; nothing before the table changes, and the table
                keeps a first paragraph there (all its columns go as WholeTable, never here),
                also at the text's start and when its first cell's column is among them. }
              comp := TTyRichCompositeCommand.Create(rsRichUndoDeleteColumn);
              for m := High(cols) downto 0 do
                if cols[m] then comp.Add(TTyRichDeleteColumn.Create(t.ParaStart(info.First), m));
              Result := comp;
            end;
          end;
        end;
      end;
    end;
  finally
    FDoc.EndRead;
  end;
  // told once the read scope is closed (a handler may load a document)
  if reason <> '' then
  begin
    FreeAndNil(Result);
    EditRefused(reason);
  end;
end;

function TTyCustomRichEdit.CellStartInRow(AFirst, ACell: Integer): TTyRichPos;
var
  t: TTyRichText;
  m, best, bi: Integer;
  c: TTyRichCell;
  row: TTyRichRow;
begin
  t := FDoc.Text;
  Result := t.ParaStart(AFirst);
  c := FDoc.CellAt(AFirst);
  if c = nil then Exit;
  row := c.Row;
  best := AFirst;
  bi := -1;
  m := AFirst;
  while m < t.ParaCount do
  begin
    c := FDoc.CellAt(m);
    if (c = nil) or (c.Row <> row) then Break;
    // the cell's first paragraph, else the last cell before it
    if (c.Index <= ACell) and (c.Index > bi) then
    begin
      bi := c.Index;
      best := m;
      if bi = ACell then Break;
    end;
    Inc(m);
  end;
  Result := t.ParaStart(best);
end;

function TTyCustomRichEdit.RowFirstPara(AFirst, ARow: Integer): Integer;
var
  t: TTyRichText;
  r, m: Integer;
  c: TTyRichCell;
  row: TTyRichRow;
begin
  t := FDoc.Text;
  Result := AFirst;
  c := FDoc.CellAt(AFirst);
  if c = nil then Exit;
  row := c.Row;
  r := 0;
  m := AFirst;
  while (r < ARow) and (m < t.ParaCount - 1) do
  begin
    Inc(m);
    c := FDoc.CellAt(m);
    if c = nil then Break;
    if c.Row <> row then
    begin
      Inc(r);
      row := c.Row;
      Result := m;
    end;
  end;
end;

function TTyCustomRichEdit.TableEditCaret: TTyRichPos;
var
  t: TTyRichText;
  m, f: Integer;
  c: TTyRichCell;
begin
  t := FDoc.Text;
  if FAimPara >= t.ParaCount then Exit(t.Length);
  FDoc.BeginRead;
  try
    case FTableKind of
      CTableInsertTable:
        begin
          // the first cell: at the paragraph, or past what a split or a paragraph that keeps
          // two tables apart put before it
          m := FAimPara;
          while (m < t.ParaCount - 1) and (m < FAimPara + 2) and (FDoc.CellAt(m) = nil) do Inc(m);
          Result := t.ParaStart(m);
        end;
      CTableInsertRow, CTableTabRow:
        Result := t.ParaStart(FAimPara);
      CTableDeleteRow:
        if FAimFollows then
          Result := CellStartInRow(FAimPara, FAimCell)
        else if FAimBefore and (FAimPara > 0) and (FDoc.CellAt(FAimPara - 1) <> nil) then
        begin
          // the row above the ones that went: from its first paragraph
          f := FAimPara - 1;
          c := FDoc.CellAt(f);
          while (f > 0) and (FDoc.CellAt(f - 1) <> nil) and (FDoc.CellAt(f - 1).Row = c.Row) do
            Dec(f);
          Result := CellStartInRow(f, FAimCell);
        end
        else
          Result := t.ParaStart(FAimPara);
      CTableInsertColumn, CTableDeleteColumn:
        // (the table's only column went: the table with it)
        if FDoc.CellAt(FAimPara) = nil then Result := t.ParaStart(FAimPara)
        else Result := CellStartInRow(RowFirstPara(FAimPara, FAimRow), FAimCell);
    else
      Result := t.ParaStart(FAimPara);
    end;
  finally
    FDoc.EndRead;
  end;
end;

function TTyCustomRichEdit.InsertTable(ARows, ACols: Integer): Boolean;
begin
  FTableRows := ARows;
  FTableCols := ACols;
  Result := RunTableAction(CTableInsertTable);
end;

function TTyCustomRichEdit.InsertRow(AAfter: Boolean): Boolean;
begin
  FTableAfter := AAfter;
  Result := RunTableAction(CTableInsertRow);
end;

function TTyCustomRichEdit.InsertColumn(AAfter: Boolean): Boolean;
begin
  FTableAfter := AAfter;
  Result := RunTableAction(CTableInsertColumn);
end;

function TTyCustomRichEdit.DeleteRow: Boolean;
begin
  Result := RunTableAction(CTableDeleteRow);
end;

function TTyCustomRichEdit.DeleteColumn: Boolean;
begin
  Result := RunTableAction(CTableDeleteColumn);
end;

function TTyCustomRichEdit.DeleteTable: Boolean;
begin
  Result := RunTableAction(CTableDeleteTable);
end;

procedure TTyCustomRichEdit.AskTables;
var
  t: TTyRichText;
  k, ks: Integer;
  busy: Boolean;
  c: TTyRichCell;
  rr, cr: TTyRichTableRefusal;
  pos: TTyRichPos;
  same: Boolean;

  // a paragraph a file read on demand has not given yet has no value: not read just to answer
  function Known(AIndex: Integer): Boolean;
  begin
    Result := (FDoc.Loader = nil) or (t.ParaData[AIndex] <> nil);
  end;

begin
  busy := RefusalReason <> '';
  if FAskValid and (FAskState = FDoc.ContentState) and (FAskCaret = FCaret) and
     (FAskAnchor = FSelAnchor) and (FAskBusy = busy) then
    Exit;
  FAskIn := False;
  FAskInsTable := False;
  FAskRows := False;
  FAskColIns := False;
  FAskColDel := False;
  FAskTable := False;
  FAskValid := True;
  FAskState := FDoc.ContentState;
  FAskCaret := FCaret;
  FAskAnchor := FSelAnchor;
  FAskBusy := busy;
  t := FDoc.Text;
  try
    ks := t.ParaOfPos(Math.Min(GetSelStart, t.Length));
    k := CaretTablePara;
    if FCaretParaUnread then FAskValid := False;
    FDoc.BeginRead;
    try
      FAskInsTable := not Known(ks) or (FDoc.CellAt(ks) = nil);
      // (an answer for a paragraph not read yet is not kept: asked again, it is read by then)
      if not Known(ks) then FAskValid := False;
      if not Known(k) then
      begin
        FAskValid := False;
        Exit;
      end;
      c := FDoc.CellAt(k);
      FAskIn := c <> nil;
      if not FAskIn or busy then Exit;
      if c.Table.Cut then
      begin
        { A part of a table a file read on demand gives: whether it can be given whole needs
          its neighbours read. The cheap answer: what is read already - merged cells, a table
          in a cell - says no; else yes, and the action tells the reason it finds. }
        FAskRows := not c.Table.ContentLocked and not c.Row.HoldsNestedTable;
        FAskColIns := FAskRows;
        FAskColDel := FAskRows;
        FAskTable := True;
        Exit;
      end;
      same := (FAskTbl <> nil) and (FAskTbl = c.Table) and (FAskTblState = FDoc.ContentState);
    finally
      FDoc.EndRead;
    end;
    { The table read once, for a column at cell 0 (an index every table has): its reason is
      the rows' reason too - the table's state, what its content forbids - but for rows of
      different numbers of cells, which forbid columns only; only then is it read again,
      for a row. What keeps a row from going keeps the others; a column too many for an
      insert is none too many for a delete. }
    { All of it is true of the whole table: kept for its table object and content, so a
      move inside the table reads nothing. }
    if not same then
    begin
      pos := t.ParaStart(k);
      cr := FDoc.TableEditRefusal(TyRichTableEdit(rtkInsertColumn, pos, 0));
      if cr = rtrIrregularRows then
        rr := FDoc.TableEditRefusal(TyRichTableEdit(rtkInsertRow, pos, 0))
      else if cr = rtrOutOfRange then
        rr := rtrNone
      else
        rr := cr;
      if FAskTbl <> nil then FAskTbl.Release;
      FAskTbl := nil;
      FDoc.BeginRead;
      try
        // (the object read again in a scope: a read in between may have let the first go)
        c := FDoc.CellAt(k);
        if c <> nil then
        begin
          FAskTbl := c.Table;
          FAskTbl.AddRef;
        end;
      finally
        FDoc.EndRead;
      end;
      FAskTblState := FDoc.ContentState;
      FAskTblRows := rr = rtrNone;
      // (rows of different cells: their columns by the grid)
      FAskTblColIns := cr in [rtrNone, rtrIrregularRows];
      FAskTblColDel := cr in [rtrNone, rtrOutOfRange, rtrIrregularRows];
      FAskTblDelete := rr in [rtrNone, rtrMergedCells, rtrNestedTable, rtrIrregularRows];
    end;
    FAskRows := FAskTblRows;
    FAskColIns := FAskTblColIns;
    FAskColDel := FAskTblColDel;
    FAskTable := FAskTblDelete;
  except
    // (never raised to an action's Update: a file that cannot be read answers no)
    on Exception do
    begin
      // (not kept: asked again, it reads again)
      FAskValid := False;
      FAskIn := False;
      FAskInsTable := False;
      FAskRows := False;
      FAskColIns := False;
      FAskColDel := False;
      FAskTable := False;
    end;
  end;
end;

function TTyCustomRichEdit.InTable: Boolean;
begin
  AskTables;
  Result := FAskIn;
end;

function TTyCustomRichEdit.CanInsertTable: Boolean;
begin
  Result := TableActionsOpen;
  if not Result then Exit;
  AskTables;
  Result := FAskInsTable;
end;

function TTyCustomRichEdit.CanInsertRow: Boolean;
begin
  Result := TableActionsOpen;
  if not Result then Exit;
  AskTables;
  Result := FAskRows;
end;

function TTyCustomRichEdit.CanInsertColumn: Boolean;
begin
  Result := TableActionsOpen;
  if not Result then Exit;
  AskTables;
  Result := FAskColIns;
end;

function TTyCustomRichEdit.CanDeleteRow: Boolean;
begin
  Result := TableActionsOpen;
  if not Result then Exit;
  AskTables;
  Result := FAskRows;
end;

function TTyCustomRichEdit.CanDeleteColumn: Boolean;
begin
  Result := TableActionsOpen;
  if not Result then Exit;
  AskTables;
  Result := FAskColDel;
end;

function TTyCustomRichEdit.CanDeleteTable: Boolean;
begin
  Result := TableActionsOpen;
  if not Result then Exit;
  AskTables;
  Result := FAskTable;
end;

function TTyCustomRichEdit.TableTab(AForward: Boolean): Boolean;
var
  t: TTyRichText;
  k, ci, next, fp, lp: Integer;
  b: TTyBlockLayout;
  found: Boolean;
  a, q: TTyRichPos;

  { The cell shown in row block AB from cell AFrom on (backward with Shift+Tab) that has
    paragraphs: its first (fp) and last (lp) paragraph. A cell merged into the one before
    it is passed over. }
  function ShownCell(AB: TTyBlockLayout; AFrom: Integer): Boolean;
  var
    row: TTyRowLayout;
    cell, i: Integer;
  begin
    Result := False;
    if not (AB is TTyRowLayout) then Exit;
    row := TTyRowLayout(AB);
    cell := AFrom;
    while (cell >= 0) and (cell < row.CellCount) do
    begin
      // (merged away across, or covered by the cell above: no place of the Tab order)
      if not row.Cells[cell].Hidden then
      begin
        fp := -1;
        for i := 0 to row.ItemCount - 1 do
          if row.Items[i].Cell = cell then
          begin
            if fp < 0 then fp := AB.FirstPara + i;
            lp := AB.FirstPara + i;
          end;
        if (fp >= 0) and not ((row.Cells[cell].VMerge = rcmContinue) and CoveredPara(fp)) then
          Exit(True);
      end;
      if AForward then Inc(cell) else Dec(cell);
    end;
  end;

begin
  Result := False;
  t := FDoc.Text;
  // the paragraph the methods take too (a caret ending whole rows stands in the last of them)
  k := CaretTablePara;
  found := False;
  fp := -1;
  lp := -1;
  EnsureParams;
  FDoc.BeginRead;
  try
    if FDoc.CellAt(k) = nil then Exit;
    Result := True;
    b := LayoutBlockAt(k);
    try
      if b is TTyRowLayout then
      begin
        // (a caret never stands in a cell merged away; its paragraphs count as the cell's)
        ci := TTyRowLayout(b).Items[k - b.FirstPara].Cell;
        ci := TTyRowLayout(b).Cells[ci].Owner;
        if AForward then found := ShownCell(b, ci + 1) else found := ShownCell(b, ci - 1);
      end;
      if AForward then next := b.LastPara + 1 else next := b.FirstPara - 1;
    finally
      b.Release;
    end;
    { The rows after (before) it as a person sees the table: every row block of table
      paragraphs next to each other, whatever table object holds them. }
    while not found and (next >= 0) and (next < t.ParaCount) and (FDoc.CellAt(next) <> nil) do
    begin
      b := LayoutBlockAt(next);
      try
        if AForward then found := ShownCell(b, 0)
        else if b is TTyRowLayout then found := ShownCell(b, TTyRowLayout(b).CellCount - 1);
        if AForward then next := b.LastPara + 1 else next := b.FirstPara - 1;
      finally
        b.Release;
      end;
    end;
  finally
    FDoc.EndRead;
  end;
  if found then
  begin
    // the cell's content selected, Word's way: not its last paragraph's end
    a := t.ParaStart(fp);
    q := OutOfTail(t.ParaStart(lp) + t.ParaLength(lp), False);
    Select(a, q, False);
    Moved(False);
  end
  else if AForward then
  begin
    { The table's last cell: a row below - an edit, through the door. With ReadOnly nothing,
      as for a typed character - asked first: a viewer is not told that a plain text
      document holds no table. }
    if FReadOnly then Exit;
    if PlainTextDocument then
    begin
      EditRefused(rsRichEditRefusedPlainTable);
      Exit;
    end;
    FTableKind := CTableTabRow;
    RunUserEdit(@MakeTableEditThen);
  end;
end;

type
  // a form's own key-press dispatch (protected in TWinControl)
  TRichKeyAccess = class(TWinControl)
  end;

{ A form among AControl's parents with KeyPreview took AKey (its DoUTF8KeyPress: the form's
  OnUTF8KeyPress cleared it), as LCL asks them before a control's own key-press event. }
function FormsTakeKey(AControl: TWinControl; var AKey: TUTF8Char): Boolean;
var
  p: TWinControl;
begin
  Result := False;
  p := AControl.Parent;
  while p <> nil do
  begin
    if (p is TCustomForm) and TCustomForm(p).KeyPreview and
      TRichKeyAccess(p).DoUTF8KeyPress(AKey) then Exit(True);
    p := p.Parent;
  end;
end;

function TTyCustomRichEdit.AskCommitKeys(const AText: UTF8String): UTF8String;
var
  i, n: Integer;
  k: TUTF8Char;
  c: UTF8String;
begin
  Result := '';
  i := 1;
  while i <= Length(AText) do
  begin
    n := UTF8CodepointSize(@AText[i]);
    if n < 1 then n := 1;
    c := Copy(AText, i, n);
    Inc(i, n);
    { As LCL-win32 delivers a character typed (WM_CHAR, one UTF-16 unit): OnUTF8KeyPress, then
      OnKeyPress for one that is a single byte, each may clear it (it does not go in) or change
      it (the changed one goes in); a character outside the BMP comes as a surrogate pair,
      which LCL-win32 passes by without either event - it goes in as it is. }
    if n >= 4 then
    begin
      Result := Result + c;
      Continue;
    end;
    k := c;
    { As LCL's DoUTF8KeyPress asks a typed character: each parent form with KeyPreview first
      (its OnUTF8KeyPress may take it, or change it), then the control's own. }
    if FormsTakeKey(Self, k) then Continue;
    inherited UTF8KeyPress(k);
    if k = '' then Continue;
    if not TyAskKeyPress(Self, k) then Continue;
    Result := Result + k;
  end;
end;

function TTyCustomRichEdit.ShownCaretRaster(out ARect: TRect): Boolean;
begin
  if FComposing and (FCompText <> '') and CompositionRaster(ARect) then Exit(True);
  Result := CaretRaster(FCaret, FCaretAtEnd, ARect);
end;

procedure TTyCustomRichEdit.CutSelection(AUser: Boolean);
var
  s, n: TTyRichPos;
begin
  if not HasSelection then Exit;
  s := GetSelStart;
  n := GetSelLength;
  // refused before anything is copied: a cut that cannot delete is no cut
  if not EditAllowed(s, n, False, AUser) then Exit;
  if AUser and not UserRangeAllowed(s, n) then Exit;
  { The clipboard gets what is removed: the range the table rule may have shortened (the
    paragraph end
    kept before a table stays, and is not copied); a selection that was only that end
    removes nothing and copies nothing. }
  if n = 0 then Exit;
  CopyRange(s, n);
  RunMade(TTyRichDelete.Create(s, n), ChangeEndPlace, AUser);
end;

procedure TTyCustomRichEdit.CutToClipboard;
var
  area: TTyRichCellArea;
begin
  // a user's action in an application's hands (EndCompositionForUser's list)
  EndCompositionForUser;
  if FReadOnly or not IsEnabled or ViewBehind then Exit;
  { Cells (Word's way): copied, then what Backspace does to them - whole columns go, other
    cells are cleared, their rows and columns stay. Whole rows and the table are cut as the
    file's rows, as before (a copy of them is the file's rows, not a small table). }
  area := CellArea;
  if TyRichCellsEditable(area) and not area.Range.WholeTable and
     not TyRichAreaWholeRows(FDoc, area) then
  begin
    CopyCells(area);
    CellsKey(False);
    Exit;
  end;
  // whole rows, the table: their paragraphs, from the first row's start to the last's end
  if TyRichCellsEditable(area) then
    Select(FDoc.Text.ParaStart(area.FirstPara), Math.Min(FDoc.Text.ParaStart(area.LastPara) +
      FDoc.Text.ParaLength(area.LastPara) + 1, FDoc.Text.Length), False);
  CutSelection(True);
end;

{ ---- pasting ---- }

function TTyCustomRichEdit.PastedText(const AText: RawByteString): UTF8String;
var
  src: RawByteString;
  d: TTyRichDocument;
  st: TBytesStream;
  b: TBytes;
  i, j, n, cl: PtrInt;
  plain: Boolean;
begin
  Result := '';
  src := AText;
  if src = '' then Exit;
  if not TyRichIsUtf8(PByte(src), Length(src)) then
  begin
    { Read as a text file is read (TyRichLoadText's rule): bytes that are not UTF-8 are the
      ANSI code page's, and what is no character there an escape - so no insert ends inside
      a sequence, which the engine would refuse. }
    b := nil;
    SetLength(b, Length(src));
    Move(src[1], b[0], Length(src));
    src := '';
    d := TTyRichDocument.Create;
    try
      st := TBytesStream.Create(b);
      try
        // (the code page a text file would be read with here: TextCodePage, 0 the system's)
        TyRichLoadText(d, st, teAuto, FTextCodePage);
      finally
        st.Free;
      end;
      src := d.Text.GetText(0, d.Text.Length);
    finally
      d.Free;
    end;
  end;
  plain := PlainTextDocument;
  n := Length(src);
  SetLength(Result, n);
  j := 0;
  i := 1;
  // a byte order mark at the start is no character of the text
  if (n >= 3) and (src[1] = #$EF) and (src[2] = #$BB) and (src[3] = #$BF) then i := 4;
  while i <= n do
  begin
    case src[i] of
      #13, #10:
        begin
          // CR LF, CR, LF: a paragraph
          Inc(j);
          Result[j] := #10;
          if (src[i] = #13) and (i < n) and (src[i + 1] = #10) then Inc(i);
          Inc(i);
          Continue;
        end;
      #11:
        begin
          // a line break; a text document has none inside a line (Shift+Enter makes one)
          Inc(j);
          if plain then Result[j] := #10 else Result[j] := #11;
          Inc(i);
          Continue;
        end;
      #9:
        begin
          Inc(j);
          Result[j] := #9;
          Inc(i);
          Continue;
        end;
      #$E2:
        // U+2028 LINE SEPARATOR, U+2029 PARAGRAPH SEPARATOR: a paragraph
        if (i + 2 <= n) and (src[i + 1] = #$80) and (src[i + 2] in [#$A8, #$A9]) then
        begin
          Inc(j);
          Result[j] := #10;
          Inc(i, 3);
          Continue;
        end;
    end;
    // what typing rejects: C0, DEL, C1
    cl := ControlCodeLen(src, i);
    if cl > 0 then
    begin
      Inc(i, cl);
      Continue;
    end;
    Inc(j);
    Result[j] := src[i];
    Inc(i);
  end;
  SetLength(Result, j);
end;

function TTyCustomRichEdit.PictureRoom(APos: TTyRichPos): Integer;
var
  k, gap: Integer;
  w, l, r: Int64;
  c: TTyRichCell;
  pf: TTyParaFormat;
begin
  Result := 0;
  k := FDoc.Text.ParaOfPos(APos);
  FDoc.BeginRead;
  try
    c := FDoc.CellAt(k);
    if c <> nil then
    begin
      // a cell: its own width, from the row's edges (else the table's)
      l := -1;
      r := -1;
      if c.Row.BoundaryCount > c.Index then
      begin
        r := c.Row.Boundaries[c.Index];
        if c.Index > 0 then l := c.Row.Boundaries[c.Index - 1] else l := 0;
      end
      else if c.Table.ColBoundaryCount > c.Index then
      begin
        r := c.Table.ColBoundaries[c.Index];
        if c.Index > 0 then l := c.Table.ColBoundaries[c.Index - 1] else l := 0;
      end;
      if (l >= 0) and (r > l) then
      begin
        { The cell's text area: its width less the row's half gap on either side and the
          paragraph's indents (as the room outside a table has them). }
        if c.Row.RawFormat <> '' then gap := TyRtfRowDisplay(c.Row.RawFormat).HalfGap
        else gap := TyDefaultRowDisplay(c.Row.CellCount).HalfGap;
        pf := FDoc.Formats.ParaFormat(FDoc.ParaFormatOf(k));
        w := r - l - 2 * Int64(gap) - pf.LeftIndent - pf.RightIndent - Math.Max(0, pf.FirstIndent);
        if w < 15 then w := 15;
        Exit(Integer(Min(w, Int64(High(Integer)))));
      end;
    end;
  finally
    FDoc.EndRead;
  end;
  EnsureParams;
  // nothing wraps (CRichNoWrap): no bound
  if (FLayoutWidth <= 0) or (FLayoutPPI <= 0) or not (FLayoutZoom > 0) then Exit;
  w := Round(FLayoutWidth * 1440 / (FLayoutPPI * Double(FLayoutZoom)));
  pf := FDoc.Formats.ParaFormat(FDoc.ParaFormatOf(k));
  w := w - pf.LeftIndent - pf.RightIndent - Math.Max(0, pf.FirstIndent);
  if w < 15 then w := 15;
  Result := Integer(Min(w, Int64(High(Integer))));
end;

{ The text of RTF from a clipboard, for a plain text document: its paragraphs (a table's cells
  each one, as they are in the text) with no format and no object; a paragraph mark at its end
  is a line break at the end. '' when it is no RTF or holds no text. }
function RtfAsText(const ARtf: RawByteString): RawByteString;
var
  b: TBytes;
  d: TTyRichDocument;
  ends: Boolean;
begin
  Result := '';
  if ARtf = '' then Exit;
  b := nil;
  SetLength(b, Length(ARtf));
  Move(ARtf[1], b[0], Length(ARtf));
  d := TyRichReadRtfFragment(b, ends);
  if d = nil then Exit;
  try
    Result := d.Text.GetText(0, d.Text.Length);
    Result := StringReplace(Result, TyRichObjectChar, '', [rfReplaceAll]);
    if ends then Result := Result + #10;
  finally
    d.Free;
  end;
end;

function TTyCustomRichEdit.CanPaste: Boolean;
begin
  Result := not FReadOnly and IsEnabled and (RefusalReason = '');
  if not Result then Exit;
  // a plain text document takes text only: a picture alone is no paste - one ask
  if PlainTextDocument then
    Result := ClipboardFlavours * [rcfRtf, rcfText] <> []
  else
    Result := ClipboardFlavours <> [];
end;

{ Every paragraph of a pasted document read now, and kept read (a load that parses on demand
  keeps every interval): what cannot be read fails here, before the paste's command - the
  flavour cannot be used - not inside it. Out of memory is raised on. }
function ReadWhole(ADoc: TTyRichDocument): Boolean;
var
  load: TTyRtfLoad;
  k: Integer;
begin
  Result := True;
  load := TyRichRtfLoadOf(ADoc);
  if load <> nil then load.MaxResidentIntervals := High(Integer);
  try
    ADoc.BeginRead;
    try
      for k := 0 to ADoc.Text.ParaCount - 1 do
      begin
        ADoc.RunsOf(k);
        ADoc.CellAt(k);
      end;
    finally
      ADoc.EndRead;
    end;
  except
    on EOutOfMemory do raise;
    on Exception do Result := False;
  end;
end;

function HoldsRows(ADoc: TTyRichDocument): Boolean;
var
  k: Integer;
begin
  for k := 0 to ADoc.Text.ParaCount - 1 do
    if ADoc.CellAt(k) <> nil then Exit(True);
  Result := False;
end;

type
  { A drop from another rich edit of the application goes in as a paste of its RTF does. Its
    pictures, read back from that RTF, are each made again with the source picture's own
    bytes (the same array: a picture is immutable, so two documents may share its bytes)
    where the source has a picture of the same bytes - the first such one after the last
    found, in text order -: the target's objects are its own, the bytes are not copied. A
    source picture whose bytes are its file's shares nothing of that file: the one read back
    keeps the copy of its own it has (equal to them). A source picture's bytes are made to be
    compared only when their length is that of the one read back (ImageDataLength makes
    nothing), once each. The rest is the reader's filter's (AInner). }
  TTyRichSharedPictures = class(TTyRichFragmentFilter)
  private
    FInner: TTyRichFragmentFilter;
    FPics: array of TTyRichPicture;
    FNext: Integer;
    FOwnsInner: Boolean;
  public
    constructor Create(AInner: TTyRichFragmentFilter; ASource: TTyRichDocument;
      AFrom, ALen: TTyRichPos);
    destructor Destroy; override;
    function KeepFragment(const AFragment: RawByteString; APara: Boolean): Boolean; override;
    function RowFormat(const ARaw: RawByteString): RawByteString; override;
    function MapObject(AObj: TTyRichObject; out AText: UTF8String): TTyRichObject; override;
  end;

const
  { How many of the source's pictures after the last one matched a picture read back is held
    against: in order they match at once; a picture the round trip changed finds none, and the
    work stays a few comparisons a picture whatever their number. }
  CRichSharedLookAhead = 8;

var
  GSharedPictureCompares: Int64 = 0;

function TyRichDropPictureCompares: Int64;
begin
  Result := GSharedPictureCompares;
end;

constructor TTyRichSharedPictures.Create(AInner: TTyRichFragmentFilter;
  ASource: TTyRichDocument; AFrom, ALen: TTyRichPos);
var
  t: TTyRichText;
  a, b, k, j, c, lo, hi: Integer;
  runs: TTyRunArray;
  n: Integer;
begin
  inherited Create;
  // (the inner filter is this one's only once it is made: a failure leaves it its caller's)
  FInner := AInner;
  n := 0;
  ASource.BeginRead;
  try
    t := ASource.Text;
    if t.Length = 0 then Exit;
    a := t.ParaOfPos(Math.Max(0, Math.Min(AFrom, t.Length - 1)));
    b := t.ParaOfPos(Math.Max(0, Math.Min(AFrom + ALen, t.Length - 1)));
    // (a copy takes the rows a range across cells meets whole: their pictures may come too)
    if (ASource.CellAt(a) <> nil) and ASource.TableParas(a, lo, hi) then a := lo;
    if (ASource.CellAt(b) <> nil) and ASource.TableParas(b, lo, hi) then b := hi;
    for k := a to b do
    begin
      runs := ASource.RunsOf(k);
      for j := 0 to High(runs) do
        if runs[j].Obj is TTyRichPicture then
        begin
          c := Length(FPics);
          if n >= c then SetLength(FPics, Math.Max(8, c * 2));
          FPics[n] := TTyRichPicture(runs[j].Obj);
          FPics[n].AddRef;
          Inc(n);
        end;
    end;
  finally
    SetLength(FPics, n);
    ASource.EndRead;
  end;
  FOwnsInner := True;
end;

destructor TTyRichSharedPictures.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(FPics) do FPics[i].Release;
  if FOwnsInner then FInner.Free;
  inherited Destroy;
end;

function TTyRichSharedPictures.KeepFragment(const AFragment: RawByteString;
  APara: Boolean): Boolean;
begin
  Result := (FInner = nil) or FInner.KeepFragment(AFragment, APara);
end;

function TTyRichSharedPictures.RowFormat(const ARaw: RawByteString): RawByteString;
begin
  if FInner = nil then Result := ARaw else Result := FInner.RowFormat(ARaw);
end;

function TTyRichSharedPictures.MapObject(AObj: TTyRichObject; out AText: UTF8String): TTyRichObject;
var
  got, src: TTyRichPicture;
  j: Integer;
  gd, sd: TBytes;
begin
  AText := '';
  if FInner = nil then Result := AObj else Result := FInner.MapObject(AObj, AText);
  if not (Result is TTyRichPicture) then Exit;
  got := TTyRichPicture(Result);
  gd := got.MakeImageData;
  for j := FNext to Math.Min(High(FPics), FNext + CRichSharedLookAhead - 1) do
  begin
    src := FPics[j];
    Inc(GSharedPictureCompares);
    if src.PictureFormat <> got.PictureFormat then Continue;
    // the same bytes where they are; else bytes of another length are not made to compare
    if (src.DataIdentity <> got.DataIdentity) or (src.DataIdentity = nil) then
    begin
      if src.ImageDataLength <> Length(gd) then Continue;
      // (one that could be equal: made once - of its file's bytes, a copy only for this look)
      sd := src.MakeImageData;
      if (Length(sd) > 0) and not CompareMem(@sd[0], @gd[0], Length(sd)) then Continue;
    end;
    FNext := j + 1;
    { the source's very bytes when it owns them; of its file's, the copy the one read back
      has (the target's own, equal to them: nothing of the source's file comes along) }
    if src.InFile then sd := gd else sd := src.MakeImageData;
    // (one the reader's filter made is no one's yet: it goes)
    Result := TTyRichPicture.Create(got.PictureFormat, sd, got.WidthTwips,
      got.HeightTwips, got.RawRtf, got.RawUc);
    if got <> AObj then got.Free;
    Exit;
  end;
  { None near: this one is the source's next, changed by the round trip - the next picture
    read back is held against the source's next (the order is the same on both sides). }
  if FNext <= High(FPics) then Inc(FNext);
end;

function TTyCustomRichEdit.DropFragmentFilter(AOffer: TTyRichDropOffer;
  AInner: TTyRichFragmentFilter): TTyRichFragmentFilter;
var
  f, n: TTyRichPos;
begin
  Result := AInner;
  // another rich edit's selection: its pictures' bytes are shared, not copied
  if (AOffer <> nil) and (AOffer.Source <> nil) and (AOffer.Source <> Self) and
    AOffer.SourceRange(f, n) then
    Result := TTyRichSharedPictures.Create(AInner, AOffer.Source.FDoc, f, n);
end;

procedure TTyCustomRichEdit.PasteFromClipboard(AAs: TTyRichPasteAs);
var
  have: TTyRichClipFlavours;
  s, n: TTyRichPos;
  offer: TTyRichClipboardOffer;

  function Wanted(AFlavour: TTyRichClipFlavour): Boolean;
  begin
    Result := (AFlavour in have) and ((AAs = rpaBest) or (Ord(AAs) = Ord(AFlavour) + 1));
  end;

begin
  EndOwedLoad;
  // the door of a user's edit: a composition goes in first
  EndCompositionForUser;
  if FReadOnly or not IsEnabled or ViewBehind then Exit;
  have := ClipboardFlavours;
  if not (Wanted(rcfRtf) or Wanted(rcfPicture) or Wanted(rcfText)) then Exit;
  s := GetSelStart;
  n := GetSelLength;
  offer := TTyRichClipboardOffer.Create(Self);
  try
    // a table (or tab-separated text) with the caret in a cell: cell by cell
    if PasteCells(offer, have, AAs, -1, rsRichUndoPaste) then Exit;
    { As typing over the selection asks: the document takes edits, no row that holds a nested
      table is in the way, the cells (may keep a selection's last separator), the cut of a
      paragraph too long to lay out (nothing goes in past what is shown). }
    if not EditAllowed(s, n, True, True) then Exit;
    if not UserRangeAllowed(s, n) then Exit;
    if LongParaRefused(s, 'x') then Exit;
    InsertOffer(offer, have, s, n, AAs, rsRichUndoPaste);
  finally
    offer.Free;
  end;
end;

function TTyCustomRichEdit.InsertOffer(AOffer: TTyRichDropOffer; AHave: TTyRichClipFlavours;
  AStart, ALen: TTyRichPos; AAs: TTyRichPasteAs; const AName: string;
  ASelect: Boolean): Boolean;
var
  life: TTyRichLife;
  r: Boolean;

  procedure Work;
  begin
    r := InsertOfferIn(AOffer, AHave, AStart, ALen, AAs, AName, ASelect, life);
  end;

begin
  r := False;
  // (a handler that frees the control: nothing of it is touched any more - the wait cursor too)
  Guard(life, @Work);
  Result := r and not life.Gone;
end;

function TTyCustomRichEdit.InsertOfferIn(AOffer: TTyRichDropOffer; AHave: TTyRichClipFlavours;
  AStart, ALen: TTyRichPos; AAs: TTyRichPasteAs; const AName: string; ASelect: Boolean;
  var ALife: TTyRichLife): Boolean;
var
  have: TTyRichClipFlavours;
  s, n: TTyRichPos;
  place: TTyRichEditPlace;
  rtf: RawByteString;
  raw: string;
  txt: UTF8String;
  bytes: TBytes;
  kind: TTyRichImageKind;
  picture: TTyRichPicture;
  src: TTyRichDocument;
  ends, flat, waiting, rows: Boolean;
  cmd: TTyRichCommand;
  comp: TTyRichCompositeCommand;
  fmt: TTyCharFormatId;
  i: Integer;
  flt, flt2: TTyRichFragmentFilter;

  function Wanted(AFlavour: TTyRichClipFlavour): Boolean;
  begin
    Result := (AFlavour in have) and ((AAs = rpaBest) or (Ord(AAs) = Ord(AFlavour) + 1));
  end;

  // the wait cursor once what was read is over the threshold (the copy's)
  procedure Wait(ASize: Int64);
  begin
    if waiting or (ASize <= FCopyWaitChars) then Exit;
    BeginWait;
    waiting := True;
  end;

begin
  Result := False;
  have := AHave;
  s := AStart;
  n := ALen;
  Settle;
  // a table goes into a table, or over a selection in one, as its text (no nested tables)
  FDoc.BeginRead;
  try
    flat := (FDoc.CellAt(FDoc.Text.ParaOfPos(s)) <> nil) or
      ((n > 0) and (FDoc.CellAt(FDoc.Text.ParaOfPos(s + n)) <> nil));
    rows := (n > 0) and WholeRows(s, s + n);
  finally
    FDoc.EndRead;
  end;
  // (a drop goes in at a place of its own: the format there, not the selection's)
  if ASelect then fmt := FDoc.TypingFormatAt(s) else fmt := TypingFormat;
  waiting := False;
  cmd := nil;
  try
    { Everything is read and made before the document changes: a flavour that cannot be read
      is the next one's turn; a lack of memory is a refusal of the control's own. }
    try
      { A plain text document: its formats and pictures cannot be saved, so a paste takes
        text only - the text flavour, else the RTF's text (no formats, no objects, a table's
        cells as paragraphs); a picture is refused, and so is an explicit RTF or picture. }
      if PlainTextDocument then
      begin
        if AAs in [rpaRtf, rpaPicture] then
        begin
          EditRefused(rsRichEditRefusedPlainPaste);
          Exit;
        end;
        if Wanted(rcfText) then
        begin
          raw := AOffer.ReadText;
          Wait(Length(raw));
          txt := PastedText(raw);
          raw := '';
        end;
        if (txt = '') and Wanted(rcfRtf) then
        begin
          rtf := AOffer.ReadRtf;
          Wait(Length(rtf));
          txt := PastedText(RtfAsText(rtf));
          rtf := '';
        end;
        if txt <> '' then
          cmd := TTyRichInsertText.Create(s, txt, fmt, False)
        else if rcfPicture in have then
        begin
          EditRefused(rsRichEditRefusedPlainPaste);
          Exit;
        end;
      end;
      { RTF cannot be used when it is no RTF (no signature), reading it - all of it - failed,
        or it holds no character and no paragraph mark: the next flavour then. }
      if (cmd = nil) and not PlainTextDocument and Wanted(rcfRtf) then
      begin
        rtf := AOffer.ReadRtf;
        Wait(Length(rtf));
        if rtf <> '' then
        begin
          bytes := nil;
          SetLength(bytes, Length(rtf));
          Move(rtf[1], bytes[0], Length(rtf));
          rtf := '';
          src := ReadRtfSource(bytes, ends);
          bytes := nil;
          try
            if (src <> nil) and not ReadWhole(src) then FreeAndNil(src);
          except
            // (out of memory: the refusal below)
            FreeAndNil(src);
            raise;
          end;
          { Rows over a selection of whole rows: refused - they would go into the next row's
            first cell, and rows put into the table instead would need the two tables'
            columns made one. }
          if (src <> nil) and rows and HoldsRows(src) then
          begin
            src.Free;
            EditRefused(rsRichEditRefusedPasteRows);
            Exit;
          end;
          { What the reader kept of the clipboard's file by number (styles, colours, fonts,
            lists inside formats, rows and objects) goes in as it is only where it means the
            same in this document's file - the entries its header defines the same (a copy
            out of this very file); the rest is left out or made again
            (TyRichFragmentFilterFor). }
          if (src <> nil) and ((src.Text.Length > 0) or ends) then
          begin
            // made first: the command takes src over only once it exists
            try
              flt := MakeFragmentFilter(src);
            except
              FreeAndNil(src);
              raise;
            end;
            // (the drop's own filter around it: when making that fails, it is not taken)
            try
              flt2 := DropFragmentFilter(AOffer, flt);
            except
              flt.Free;
              FreeAndNil(src);
              raise;
            end;
            flt := flt2;
            cmd := TTyRichInsertFragment.Create(s, src, ends, flat, flt);
          end
          else
            src.Free;
        end;
      end;
      { A picture cannot be used when its bytes do not decode: the next picture format is
        tried, then the next flavour; one too large is refused. }
      if (cmd = nil) and not PlainTextDocument and Wanted(rcfPicture) then
      begin
        i := 0;
        while (cmd = nil) and AOffer.ReadPicture(i, kind, bytes) do
        begin
          Inc(i);
          if bytes = nil then Continue;
          Wait(Length(bytes));
          case TyRichMakePicture(bytes, kind, PictureRoom(s), picture) of
            rpmMade: cmd := TTyRichInsertObject.Create(s, picture, fmt);
            rpmTooLarge:
              begin
                EditRefused(rsRichEditRefusedPicture);
                Exit;
              end;
          end;
          bytes := nil;
        end;
      end;
      if (cmd = nil) and not PlainTextDocument and Wanted(rcfText) then
      begin
        raw := AOffer.ReadText;
        Wait(Length(raw));
        txt := PastedText(raw);
        raw := '';
        if txt <> '' then cmd := TTyRichInsertText.Create(s, txt, fmt, False);
      end;
    except
      on EOutOfMemory do
      begin
        FreeAndNil(cmd);
        EditRefused(rsRichEditRefusedMemory);
        Exit;
      end;
    end;
    if cmd = nil then Exit;
    // one step: the selection's deletion and the paste, never merged with typing
    comp := TTyRichCompositeCommand.Create(AName);
    if n > 0 then comp.Add(TTyRichDelete.Create(s, n));
    comp.Add(cmd);
    cmd := nil;
    // behind what went in: the selection's end, moved by what the text grew
    place := Default(TTyRichEditPlace);
    place.Anchor := CRichPlaceChangeEnd;
    place.Caret := s + n;
    place.ByGrowth := True;
    // (a drop: what went in selected, from where the change began)
    if ASelect then place.Anchor := CRichPlaceChangeStart;
    Result := RunMade(comp, place, True);
  finally
    cmd.Free;
    if waiting and not ALife.Gone then EndWait;
  end;
end;

procedure TTyCustomRichEdit.RunHistory(ARedo, AUser: Boolean);
var
  life: TTyRichLife;

  procedure Work;
  begin
    RunHistoryIn(ARedo, AUser);
  end;

begin
  // (Undo, Redo and their keys: a handler that frees the control ends the call there)
  Guard(life, @Work);
end;

procedure TTyCustomRichEdit.RunHistoryIn(ARedo, AUser: Boolean);
var
  reason: string;
  c: TTyRichChange;
  marks: TTyRichStepMarks;
begin
  if ARedo then
  begin
    if FDoc.RedoDepth = 0 then Exit;
    marks := FDoc.RedoStep.Marks;
  end
  else if FDoc.UndoDepth = 0 then
    Exit
  else
    marks := FDoc.UndoStep.Marks;
  reason := RefusalReason;
  if reason <> '' then
  begin
    Refuse(reason, AUser);
    Exit;
  end;
  FEditHeard := False;
  FEditStep := nil;
  Inc(FEditing);
  try
    try
      if ARedo then FDoc.Redo else FDoc.Undo;
    except
      // a step the document could not take (it lets its history go then)
      on E: ETyRichModel do
      begin
        if not AUser then raise;
        reason := EngineRefusal(E);
      end;
    end;
  finally
    Dec(FEditing);
  end;
  // (told outside the bracket, as RunEdit tells it)
  if reason <> '' then
  begin
    EditRefused(reason);
    PayModifiedOwed;
    Exit;
  end;
  if not FEditHeard then
  begin
    PayModifiedOwed;
    Exit;
  end;
  { An undo puts the caret and the selection back as they were before the action, a redo
    leaves a plain caret where the action left it (measured in Windows' rich edit: a deleted or
    typed-over selection comes back selected, an undone Backspace has the caret after the
    character, an undone Delete before it, undone typing at its start) - from the marks the
    control kept with the step, never from the change's extent, which cannot tell a deleted
    selection from a character a key took. A step made by code has none: what it put back is
    selected after an undo, the caret at the end of what it changed after a redo. }
  if not ARedo and marks.HasBefore then
    FinishEdit(marks.Before.Anchor, marks.Before.Caret, marks.Before.AtLineEnd, True)
  else if ARedo and marks.HasAfter then
  begin
    { a resize redone: its object selected again, with its handles, as the drag left it; a
      move or a copy redone: the content selected where it went, as the drop left it }
    if (FDoc.UndoStep is TTyRichResizeObject) or (FDoc.UndoStep is TTyRichRangeTransfer) then
      FinishEdit(marks.After.Anchor, marks.After.Caret, marks.After.AtLineEnd)
    else
      FinishEdit(marks.After.Caret, marks.After.Caret, marks.After.AtLineEnd);
  end
  else
  begin
    c := FEditChange;
    if not ARedo and (c.NewLen > 0) then FinishEdit(c.Pos, c.Pos + c.NewLen)
    else FinishEdit(c.Pos + c.NewLen, c.Pos + c.NewLen);
  end;
end;

procedure TTyCustomRichEdit.Undo;
begin
  // a user's action in an application's hands (EndCompositionForUser's list)
  EndCompositionForUser;
  if FReadOnly or not IsEnabled or ViewBehind then Exit;
  RunHistory(False, True);
end;

procedure TTyCustomRichEdit.Redo;
begin
  EndCompositionForUser;
  if FReadOnly or not IsEnabled or ViewBehind then Exit;
  RunHistory(True, True);
end;

function TTyCustomRichEdit.CanUndo: Boolean;
begin
  Result := not FReadOnly and IsEnabled and FDoc.CanUndo;
end;

function TTyCustomRichEdit.CanRedo: Boolean;
begin
  Result := not FReadOnly and IsEnabled and FDoc.CanRedo;
end;

procedure TTyCustomRichEdit.ClearUndo;
var
  life: TTyRichLife;
begin
  LifeEnter(life);
  try
    try
      { A replace in the background keeps its one step in the history: it ends first, told
        (cancelled, what it did, the place to go on from), before its step goes. }
      if FFindKind = rfkReplace then EndFind(rfsCancelled, True);
      FDoc.ClearUndo;
    except
      on ETyRichGone do if TyRichGonePasses(life) then raise;
    end;
  finally
    if not life.Gone then LifeLeave(life);
  end;
end;

procedure TTyCustomRichEdit.SetSelText(const AValue: string);
var
  s: UTF8String;
begin
  s := AValue;
  TypeText(s, False, False);
end;

{ ---- the format API ----

  Both façades come here: a read asks the document's formats (RunsOf, ParaFormatOf), a write
  is one command through RunApiEdit - the door of a user's edit (RunMade, EditWith, RunEdit,
  FinishEdit: the selection's record kept with the step, one OnChange) without its ReadOnly
  question, refusals raised. Nothing here changes the model another way: a pending format is
  an id of the format pool, which only interns values. }

procedure TTyCustomRichEdit.DocModifiedChanged(Sender: TObject);
begin
  if [csLoading, csDestroying] * ComponentState <> [] then Exit;
  { Inside the control's own edit (a key, a façade's write, an undo): raised once the edit
    has placed the caret and made its OnChange - a handler that changes or loads the
    document there is not taken for this edit (as for EditRefused). }
  if FEditing > 0 then
  begin
    FModifiedOwed := True;
    Exit;
  end;
  if Assigned(FOnModifiedChange) then FOnModifiedChange(Self);
end;

procedure TTyCustomRichEdit.PayModifiedOwed;

  procedure Fire;
  begin
    FOnModifiedChange(Self);
  end;

begin
  if not FModifiedOwed or (FEditing > 0) then Exit;
  FModifiedOwed := False;
  if [csLoading, csDestroying] * ComponentState <> [] then Exit;
  if Assigned(FOnModifiedChange) then CallHandler(@Fire);
end;

procedure TTyCustomRichEdit.RunApiCommand(ACmd: TTyRichCommand; AChars: TTyRichPos);
begin
  RunApiEdit(ACmd, AChars);
end;

procedure TTyCustomRichEdit.BeginEdit;
begin
  if FEditBlock = 0 then
  begin
    EndCompositionForUser;
    FEditBlockMarks := Default(TTyRichStepMarks);
    FEditBlockMarks.HasBefore := True;
    FEditBlockMarks.Before.Anchor := FSelAnchor;
    FEditBlockMarks.Before.Caret := FCaret;
    FEditBlockMarks.Before.AtLineEnd := FCaretAtEnd;
    FDoc.BeginUpdate;
  end;
  Inc(FEditBlock);
end;

procedure TTyCustomRichEdit.EndEdit;
var
  life: TTyRichLife;

  procedure Work;
  begin
    EndEditIn(life);
  end;

begin
  // (the block's one report: a handler that frees the control ends the call there)
  Guard(life, @Work);
end;

procedure TTyCustomRichEdit.EndEditIn(var ALife: TTyRichLife);
var
  wasTop, step: TTyRichCommand;
  marks: TTyRichStepMarks;
begin
  if FEditBlock = 0 then raise ETyRichEdit.Create('EndEdit without BeginEdit');
  Dec(FEditBlock);
  if FEditBlock > 0 then Exit;
  wasTop := FDoc.UndoStep;
  FEditHeard := False;
  FEditStep := nil;
  // the block's one change is this edit's: the control reports it below, once
  Inc(FEditing);
  try
    FDoc.EndUpdate;
  finally
    Dec(FEditing);
  end;
  if not FEditHeard then
  begin
    // no change, but a selection set inside the block is reported now
    DoSelectionChange;
    PayModifiedOwed;
    Exit;
  end;
  step := FDoc.UndoStep;
  if (step <> nil) and (step <> wasTop) then
  begin
    // the step puts back the selection there was at BeginEdit
    marks := FEditBlockMarks;
    step.Marks := marks;
    FEditStep := step;
  end;
  // the selection stays where it is (as a façade's write leaves it), the view too
  Inc(FApiWrite);
  try
    FinishEdit(FSelAnchor, FCaret, FCaretAtEnd, True);
  finally
    // (a handler that freed the control: nothing of it is touched)
    if not ALife.Gone then Dec(FApiWrite);
  end;
end;

procedure TTyCustomRichEdit.SetSelAttributes(AValue: TTyRichTextAttributes);
begin
  FSelAttributes.Assign(AValue);
end;

procedure TTyCustomRichEdit.SetDefAttributes(AValue: TTyRichTextAttributes);
begin
  FDefAttributes.Assign(AValue);
end;

procedure TTyCustomRichEdit.SetParagraph(AValue: TTyRichParaAttributes);
begin
  FParagraph.Assign(AValue);
end;

procedure TTyCustomRichEdit.SetPlainTextState(AValue: Boolean);
begin
  // a state, not a change: the content and its formats stay as they are
  FPlainText := AValue;
  FPlainTextAsked := AValue;
end;

function TTyCustomRichEdit.BaseHalfPt(const AStyle: TTyStyleSet): Integer;
var
  size: Integer;
begin
  size := ResolveFontSize(AStyle);
  if TyFontSizeIsPx(size) then
    Result := Round(TyFontPxOf(size) * 72 / 96 * 2)
  else
    Result := size * 2;
  if Result < 1 then Result := 20;
end;

function TTyCustomRichEdit.BaseFontName(const AStyle: TTyStyleSet): string;
begin
  // the theme's, else the platform's fallback, else the Font's ('default': the system's)
  Result := TyEffectiveFontName(AStyle.FontName);
  if Result = '' then Result := Font.Name;
end;

procedure TTyCustomRichEdit.NameDocBase;
var
  s: TTyStyleSet;
begin
  s := CurrentStyle;
  FDoc.BaseFontName := TyEffectiveFontName(s.FontName);
  FDoc.BaseFontSizeHalfPt := BaseHalfPt(s);
end;

function TTyCustomRichEdit.BaseCharFormat: TTyCharFormat;
var
  s: TTyStyleSet;
begin
  // what the layouter is given (CheckLayoutParams) and the text colour the paint takes
  s := CurrentStyle;
  Result := TyDefaultCharFormat;
  Result.FontName := BaseFontName(s);
  Result.SizeHalfPt := BaseHalfPt(s);
  Result.Style := BaseFontStyle(s) - [fsStrikeOut];
  Result.Strike := fsStrikeOut in BaseFontStyle(s);
  if tpTextColor in s.Present then Result.Color := TyColorToLCL(s.TextColor);
  Result.Charset := Font.CharSet;
end;

procedure TTyCustomRichEdit.SetBaseCharFormat(AMask: TTyCharFormatMask;
  const AValue: TTyCharFormat);
var
  st: TFontStyles;
begin
  // the base has neither (an Assign from SelAttributes carries clNone and vaNone: nothing)
  if ((cffHighlight in AMask) and (AValue.HighlightColor <> clNone)) or
    ((cffVertAlign in AMask) and (AValue.VertAlign <> vaNone)) then
    raise ETyRichEdit.Create('DefAttributes has no background colour and no vertical position');
  // the control's Font is the base (TyApplyControlFont lays it over the theme): one truth
  Font.BeginUpdate;
  try
    // none of its own: LCL's default font, which the theme's font then stands for
    if cffFontName in AMask then
      if AValue.FontName = '' then Font.Name := 'default' else Font.Name := AValue.FontName;
    if cffSize in AMask then Font.Size := AValue.SizeHalfPt div 2;
    if AMask * CTyCharStyleMask <> [] then
    begin
      st := Font.Style;
      if cffBold in AMask then
        if fsBold in AValue.Style then Include(st, fsBold) else Exclude(st, fsBold);
      if cffItalic in AMask then
        if fsItalic in AValue.Style then Include(st, fsItalic) else Exclude(st, fsItalic);
      if cffUnderline in AMask then
        if fsUnderline in AValue.Style then Include(st, fsUnderline)
        else Exclude(st, fsUnderline);
      if cffStrike in AMask then
        if AValue.Strike or (fsStrikeOut in AValue.Style) then Include(st, fsStrikeOut)
        else Exclude(st, fsStrikeOut);
      Font.Style := st;
    end;
    if cffColor in AMask then Font.Color := AValue.Color;
    if cffCharset in AMask then Font.CharSet := AValue.Charset;
  finally
    Font.EndUpdate;
  end;
end;

function TTyCustomRichEdit.ResolvedFormat(const AFormat: TTyCharFormat): TTyCharFormat;
var
  s: TTyStyleSet;
begin
  Result := AFormat;
  if (Result.FontName <> '') and (Result.SizeHalfPt > 0) then Exit;
  s := CurrentStyle;
  if Result.FontName = '' then Result.FontName := BaseFontName(s);
  if Result.SizeHalfPt <= 0 then Result.SizeHalfPt := BaseHalfPt(s);
end;

function TTyCustomRichEdit.CharFormatIdAt(APos: TTyRichPos): TTyCharFormatId;
var
  t: TTyRichText;
  k, i: Integer;
  off: TTyRichPos;
  runs: TTyRunArray;
begin
  t := FDoc.Text;
  if (APos < 0) or (APos > t.Length) then Exit(-1);
  k := t.ParaOfPos(APos);
  off := APos - t.ParaStart(k);
  runs := FDoc.RunsOf(k);
  i := High(runs);
  while (i > 0) and (runs[i].Start > off) do Dec(i);
  Result := runs[i].Format;
end;

procedure TTyCustomRichEdit.ConsistencyAdd(AFormat: TTyCharFormatId);
begin
  if FConsHave and (AFormat = FConsBaseId) then Exit;
  if not FConsHave then
  begin
    FConsBaseId := AFormat;
    FConsBase := FDoc.Formats.CharFormat(AFormat);
    FConsHave := True;
    Exit;
  end;
  FConsMask := FConsMask - TyRichCharDiff(FConsBase, FDoc.Formats.CharFormat(AFormat));
end;

function TTyCustomRichEdit.ParsedSoFar: Int64;
var
  load: TTyRtfLoad;
begin
  load := TyRichRtfLoadOf(FDoc);
  if load = nil then Result := 0 else Result := load.ParsedBytes;
end;

procedure TTyCustomRichEdit.ConsistencyBegin;
begin
  Inc(FConsWalks);
  FConsSeen := 0;
  FConsCut := False;
  FConsParsed0 := ParsedSoFar;
end;

function TTyCustomRichEdit.ConsistencyGo(AUnparsed: Boolean): Boolean;
begin
  // (no unit left: the paragraph's first run would be past the budget)
  if FConsSeen >= FConsBudgetWork then FConsCut := True
  else if AUnparsed and (ParsedSoFar - FConsParsed0 >= FConsBudgetBytes) then FConsCut := True;
  Result := not FConsCut;
end;

function TTyCustomRichEdit.ConsistencyUnit: Boolean;
begin
  Inc(FConsSeen);
  if FConsSeen > FConsBudgetWork then FConsCut := True;
  Result := not FConsCut;
end;

procedure TTyCustomRichEdit.ConsistencyWalk(AIndex: Integer; AData: Pointer; ASrcOffset,
  ASrcBytes: Int64; var AContinue: Boolean);
var
  pf: TTyParaFormatId;
  runs: TTyRunArray;
  cell: TTyRichCell;
  i: Integer;
  parsed: Boolean;
begin
  if AIndex > FConsLast then
  begin
    AContinue := False;
    Exit;
  end;
  parsed := FDoc.ReadValue(AData, pf, runs, cell);
  // the budget: past it the walk stops and the answer is a lower bound
  if not ConsistencyGo(not parsed) then
  begin
    AContinue := False;
    Exit;
  end;
  // a whole paragraph: every run; one not parsed yet is read (parsed) by its index
  if not parsed then runs := FDoc.RunsOf(AIndex);
  for i := 0 to High(runs) do
  begin
    // each run a unit of the budget
    if not ConsistencyUnit then
    begin
      AContinue := False;
      Exit;
    end;
    ConsistencyAdd(runs[i].Format);
    if FConsMask = [] then Break;
  end;
  AContinue := FConsMask <> [];
end;

function TTyCustomRichEdit.RangeConsistency(AStart, ALen: TTyRichPos): TTyCharFormatMask;
var
  t: TTyRichText;
  e: TTyRichPos;
  first, last: Integer;

  // the part of paragraph AIndex in the range: the runs that hold its characters
  procedure Edge(AIndex: Integer);
  var
    ps, pl, a, b, rs, re: TTyRichPos;
    runs: TTyRunArray;
    i: Integer;
  begin
    ps := t.ParaStart(AIndex);
    pl := t.ParaLength(AIndex);
    a := Math.Max(AStart, ps) - ps;
    b := Math.Min(e, ps + pl) - ps;
    runs := FDoc.RunsOf(AIndex);
    for i := 0 to High(runs) do
    begin
      rs := runs[i].Start;
      if i < High(runs) then re := runs[i + 1].Start else re := pl;
      { An empty paragraph whose separator is in the range counts with its one run (a format
        write formats it, ApplyCharFormat's rule). }
      if pl = 0 then
      begin
        if i > 0 then Break;
      end
      else if (re <= a) or (rs >= b) or (re <= rs) then
        Continue;
      if not ConsistencyUnit then Exit;
      ConsistencyAdd(runs[i].Format);
      if FConsMask = [] then Exit;
    end;
  end;

begin
  Result := CAllCharFields;
  t := FDoc.Text;
  if ALen <= 0 then Exit;
  // the same selection over the same content: the answer is known
  if FCharConsValid and (FCharConsStart = AStart) and (FCharConsLen = ALen) and
    (FCharConsState = FDoc.ContentState) then Exit(FCharConsResult);
  e := AStart + ALen;
  ParasOfRange(AStart, ALen, first, last);
  FConsHave := False;
  FConsBaseId := -1;
  FConsMask := CAllCharFields;
  ConsistencyBegin;
  // (the first paragraph is always read: its parse is the read's least)
  ConsistencyGo(False);
  Edge(first);
  { The paragraphs between: one walk of the text (no lookup per paragraph), ended as soon as
    every field was found to differ - the rest of the selection is not read - or when the
    budget is spent. }
  if (FConsMask <> []) and (last > first + 1) then
  begin
    FConsLast := last - 1;
    t.WalkParas(first + 1, @ConsistencyWalk);
  end;
  if (FConsMask <> []) and (last > first) and not FConsCut and ConsistencyGo(True) then
    Edge(last);
  // cut short: what was not proven the same is reported as not (a lower bound)
  if FConsCut then Result := [] else Result := FConsMask;
  FCharConsValid := True;
  FCharConsStart := AStart;
  FCharConsLen := ALen;
  FCharConsState := FDoc.ContentState;
  FCharConsResult := Result;
end;

procedure TTyCustomRichEdit.ParaConsistencyWalk(AIndex: Integer; AData: Pointer; ASrcOffset,
  ASrcBytes: Int64; var AContinue: Boolean);
var
  pf: TTyParaFormatId;
  runs: TTyRunArray;
  cell: TTyRichCell;
  parsed: Boolean;
begin
  if AIndex > FConsLast then
  begin
    AContinue := False;
    Exit;
  end;
  parsed := FDoc.ReadValue(AData, pf, runs, cell);
  // the first paragraph is always read; past the budget the walk stops, a paragraph
  // a unit (its format alone is looked at)
  if FParaConsHave and (not ConsistencyGo(not parsed) or not ConsistencyUnit) then
  begin
    AContinue := False;
    Exit;
  end;
  if not parsed then pf := FDoc.ParaFormatOf(AIndex);
  if not FParaConsHave then
  begin
    FParaConsHave := True;
    FParaConsBaseId := pf;
    FParaConsBase := FDoc.Formats.ParaFormat(pf);
  end
  else if pf <> FParaConsBaseId then
    FParaConsMask := FParaConsMask - TyRichParaDiff(FParaConsBase, FDoc.Formats.ParaFormat(pf));
  AContinue := FParaConsMask <> [];
end;

function TTyCustomRichEdit.ParaConsistency(AStart, ALen: TTyRichPos): TTyRichConsistentParaAttributes;
const
  All = [Low(TTyRichConsistentParaAttribute)..High(TTyRichConsistentParaAttribute)];
var
  first, last: Integer;
begin
  Result := All;
  ParasOfRange(AStart, ALen, first, last);
  if last <= first then Exit;
  if FParaConsValid and (FParaConsStart = AStart) and (FParaConsLen = ALen) and
    (FParaConsState = FDoc.ContentState) then Exit(FParaConsResult);
  FParaConsHave := False;
  FParaConsMask := All;
  ConsistencyBegin;
  FConsLast := last;
  FDoc.Text.WalkParas(first, @ParaConsistencyWalk);
  if FConsCut then Result := [] else Result := FParaConsMask;
  FParaConsValid := True;
  FParaConsStart := AStart;
  FParaConsLen := ALen;
  FParaConsState := FDoc.ContentState;
  FParaConsResult := Result;
end;

function TTyCustomRichEdit.SelFormatId: TTyCharFormatId;
var
  t: TTyRichText;
  s, e: TTyRichPos;
  p: Integer;
begin
  if not HasSelection then Exit(TypingFormat);
  t := FDoc.Text;
  s := GetSelStart;
  e := s + GetSelLength;
  p := t.ParaOfPos(s);
  { At a paragraph's separator (Shift+Down from a line's end) a write formats nothing of that
    paragraph: the first character it formats is the next paragraph's (or that paragraph's
    one run when it is empty), when the selection reaches past its start. }
  if (t.ParaLength(p) > 0) and (s = t.ParaStart(p) + t.ParaLength(p)) and (s + 1 < e) then
    Inc(s);
  Result := CharFormatIdAt(s);
end;

function TTyCustomRichEdit.GetZoomFactor: Double;
begin
  Result := FZoom / 100;
end;

procedure TTyCustomRichEdit.SetZoomFactor(AValue: Double);
begin
  SetZoom(Round(AValue * 100));
end;

procedure TTyCustomRichEdit.ParasOfRange(AStart, ALen: TTyRichPos; out AFirst, ALast: Integer);
var
  t: TTyRichText;
begin
  t := FDoc.Text;
  AFirst := t.ParaOfPos(AStart);
  ALast := AFirst;
  if ALen <= 0 then Exit;
  ALast := t.ParaOfPos(AStart + ALen);
  if (ALast > AFirst) and (t.ParaStart(ALast) = AStart + ALen) then Dec(ALast);
end;

function TTyCustomRichEdit.ParaFormatAt(APos: TTyRichPos; out AFormat: TTyParaFormat): Boolean;
var
  t: TTyRichText;
begin
  t := FDoc.Text;
  Result := (APos >= 0) and (APos <= t.Length);
  if Result then AFormat := FDoc.Formats.ParaFormat(FDoc.ParaFormatOf(t.ParaOfPos(APos)))
  else AFormat := TyDefaultParaFormat;
end;

{ The façades' writes: one command, through the door of a user's edit but for its ReadOnly
  question, refusals raised (ETyRichEdit). AChars: how many characters it formats
  (the wait cursor's threshold). }
procedure TTyCustomRichEdit.RunApiEdit(ACmd: TTyRichCommand; AChars: TTyRichPos);
var
  life: TTyRichLife;

  procedure Work;
  begin
    RunApiEditIn(ACmd, AChars, life);
  end;

begin
  // (the format API, InDelText: a handler that frees the control ends the call there)
  Guard(life, @Work);
end;

function TTyCustomRichEdit.GetDocumentColor: TColor;
begin
  Result := FDoc.DocumentColor;
end;

procedure TTyCustomRichEdit.ApiSettings(const ASettings: TTyRichDocSettings);
var
  s: TTyRichDocSettings;
begin
  s := FDoc.Settings;
  if (s.PaperWidth = ASettings.PaperWidth) and (s.PaperHeight = ASettings.PaperHeight) and
     (s.MarginLeft = ASettings.MarginLeft) and (s.MarginRight = ASettings.MarginRight) and
     (s.Color = ASettings.Color) and s.CharFormat.Equals(ASettings.CharFormat) and
     s.ParaFormat.Equals(ASettings.ParaFormat) then
    Exit;
  // (the model's own check, told as the control tells a refusal: nothing changes)
  if (ASettings.PaperWidth <= 0) or (ASettings.MarginLeft < 0) or (ASettings.MarginRight < 0) or
     (Int64(ASettings.PaperWidth) - ASettings.MarginLeft - ASettings.MarginRight <= 0) then
    raise ETyRichEdit.Create(rsRichEditRefusedPage);
  RunApiEdit(TTyRichChangeSettings.Create(ASettings), 0);
end;

procedure TTyCustomRichEdit.SetDocumentColor(AValue: TColor);
var
  s: TTyRichDocSettings;
begin
  s := FDoc.Settings;
  if (AValue = clDefault) or (AValue = clWindow) then AValue := clNone;
  s.Color := AValue;
  ApiSettings(s);
end;

procedure TTyCustomRichEdit.SetPageSetup(AWidthTwips, ALeftTwips, ARightTwips: Integer);
var
  s: TTyRichDocSettings;
begin
  s := FDoc.Settings;
  s.PaperWidth := AWidthTwips;
  s.MarginLeft := ALeftTwips;
  s.MarginRight := ARightTwips;
  ApiSettings(s);
end;

procedure TTyCustomRichEdit.SetDefaultFormats(const AChar: TTyCharFormat;
  const APara: TTyParaFormat);
var
  s: TTyRichDocSettings;
begin
  s := FDoc.Settings;
  s.CharFormat := AChar;
  s.ParaFormat := APara;
  ApiSettings(s);
end;

{ ---- a display page ---- }

function TTyCustomRichEdit.CaretHidden: Boolean;
begin
  Result := FReadOnly and not FCaretWhenReadOnly;
end;

procedure TTyCustomRichEdit.SetCaretWhenReadOnly(AValue: Boolean);
begin
  if FCaretWhenReadOnly = AValue then Exit;
  FCaretWhenReadOnly := AValue;
  // the caret's place is blitted again: drawn now, or gone
  if not IsRectEmpty(FCaretDrawn) then InvalidateArea(FCaretDrawn);
  if HasCaretFocus and not ViewBehind and not (csDestroying in ComponentState) then
    InvalidateArea(CaretClientRect);
end;

procedure TTyCustomRichEdit.SetAllowSelection(AValue: Boolean);
begin
  if FAllowSelection = AValue then Exit;
  FAllowSelection := AValue;
  // a press waiting to drag the selection, a drag selecting: they end with nothing changed
  if not AValue then
  begin
    CancelSelectionDrag;
    FDragging := False;
  end;
  // the hand over a link comes for a plain click now (or goes)
  PointerKeysChanged(FPointerShift);
end;

procedure TTyCustomRichEdit.SetScrollBars(AValue: TScrollStyle);
begin
  if FScrollBars = AValue then Exit;
  FScrollBars := AValue;
  FViewValid := False;
  Invalidate;
end;

procedure TTyCustomRichEdit.SetAutoHeight(AValue: Boolean);
begin
  if FAutoHeight = AValue then Exit;
  FAutoHeight := AValue;
  // (no vertical bar while it is on: the text area changes)
  FViewValid := False;
  Invalidate;
  if [csLoading, csDestroying] * ComponentState = [] then CheckContentSize(False);
end;

function TTyCustomRichEdit.BarAllowed(AVertical: Boolean): Boolean;
begin
  if AVertical then
    Result := not FAutoHeight and (FScrollBars in [ssVertical, ssBoth, ssAutoVertical, ssAutoBoth])
  else
    Result := FScrollBars in [ssHorizontal, ssBoth, ssAutoHorizontal, ssAutoBoth];
end;

function TTyCustomRichEdit.ContentInsets(out AH, AV: Integer): Boolean;
var
  s: TTyStyleSet;
  ppi: Integer;
begin
  s := CurrentStyle;
  ppi := ViewPPI;
  // a bar lies over the padding on its side, as TextArea has it: the larger of the two
  if VBarShown then
    AH := MulDiv(s.Padding.Left, ppi, 96) + Math.Max(MulDiv(s.Padding.Right, ppi, 96),
      ScrollBarSize(ppi))
  else
    AH := MulDiv(s.Padding.Left, ppi, 96) + MulDiv(s.Padding.Right, ppi, 96);
  if HBarShown then
    AV := MulDiv(s.Padding.Top, ppi, 96) + Math.Max(MulDiv(s.Padding.Bottom, ppi, 96),
      ScrollBarSize(ppi))
  else
    AV := MulDiv(s.Padding.Top, ppi, 96) + MulDiv(s.Padding.Bottom, ppi, 96);
  Result := True;
end;

procedure TTyCustomRichEdit.MeasureContent;
var
  t: TTyRichText;
  n, i, k: Integer;
  b: TTyBlockLayout;
  h: array of Int64;
begin
  t := FDoc.Text;
  n := t.ParaCount;
  if (n > CRichContentExactParas) or FDoc.Loading or (FLayoutPPI <= 0) or ViewBehind then Exit;
  if t.MeasuredParaCount >= n then Exit;
  FDoc.BeginRead;
  try
    i := 0;
    while i < n do
    begin
      if t.ParaMeasured(i) then
      begin
        Inc(i);
        Continue;
      end;
      b := LayoutBlockAt(i);
      try
        h := nil;
        SetLength(h, b.LastPara - b.FirstPara + 1);
        for k := 0 to High(h) do h[k] := 0;
        h[0] := b.Height;
        t.SetParaHeights(b.FirstPara, h);
        NoteExtent(b);
        i := Math.Max(i + 1, b.LastPara + 1);
      finally
        b.Release;
      end;
    end;
  finally
    FDoc.EndRead;
  end;
end;

procedure TTyCustomRichEdit.EnsureContentMeasured;
var
  wide: Integer;
  total: Int64;
begin
  if ViewBehind or (csDestroying in ComponentState) then Exit;
  EnsureView(ViewPPI);
  wide := FWidestSeen;
  total := FDoc.Text.TotalHeight;
  MeasureContent;
  { What the view never laid out - a table wider than the window below it, heights past their
    estimate - may bring a bar or take one away, and a bar is in the content's size (its
    insets): the bars are decided again, as the next paint would, before the size is read. A
    bar that comes changes no height (horizontal) or makes them estimates at the new width
    (vertical): measured once more. }
  if (FWidestSeen <> wide) or (FDoc.Text.TotalHeight <> total) then
  begin
    EnsureView(ViewPPI);
    MeasureContent;
  end;
end;

function TTyCustomRichEdit.ContentHeight: Integer;
var
  ih, iv: Integer;
begin
  EnsureContentMeasured;
  ContentInsets(ih, iv);
  Result := Integer(Math.Min(FDoc.Text.TotalHeight div Math.Max(1, FScale), Int64(MaxInt div 2))) + iv;
end;

function TTyCustomRichEdit.ContentWidth: Integer;
var
  ih, iv: Integer;
begin
  EnsureContentMeasured;
  ContentInsets(ih, iv);
  Result := FWidestSeen div Math.Max(1, FScale) + ih;
end;

function TTyCustomRichEdit.ContentSizeIsEstimate: Boolean;
begin
  Result := FDoc.Loading or (FDoc.Text.MeasuredParaCount < FDoc.Text.ParaCount);
end;

// Align and both vertical anchors give the height to the parent: AutoHeight sets nothing then.
function TTyCustomRichEdit.AutoHeightApplies: Boolean;
begin
  Result := not (Align in [alClient, alLeft, alRight]) and
    not ((akTop in Anchors) and (akBottom in Anchors));
end;

{ The height AutoHeight gives for content AH pixels tall: within Constraints and never above
  CRichAutoHeightLimit. }
function TTyCustomRichEdit.AutoHeightFor(AH: Integer): Integer;
begin
  Result := Math.Min(Constraints.MinMaxHeight(AH), CRichAutoHeightLimit);
end;

function TTyCustomRichEdit.ContentSizeWanted: Boolean;
begin
  Result := FAutoHeight or Assigned(FOnContentSizeChange);
end;

procedure TTyCustomRichEdit.CheckContentSize(AQueue: Boolean);
var
  h, w: Integer;
  tries: Integer;
begin
  if not ContentSizeWanted or ([csDestroying, csLoading] * ComponentState <> []) then Exit;
  if AQueue or ViewBehind or FSizingSelf then
  begin
    { Queued only when something may differ: the heights as they stand against what was
      reported (an estimate in them, a size that moved) - a check that found it all the same
      queues nothing, so no turn of the loop ever queues the next for nothing. }
    if ViewBehind or FSizingSelf then
    begin
      ScheduleCall(FSizeCall);
      Exit;
    end;
    ContentInsets(w, h);
    h := Integer(Math.Min(FDoc.Text.TotalHeight div Math.Max(1, FScale), Int64(MaxInt div 2))) + h;
    w := FWidestSeen div Math.Max(1, FScale) + w;
    if (h <> FReportedH) or (w <> FReportedW) or (FAutoHeight and AutoHeightApplies and
       (AutoHeightFor(h) <> Height)) or (ContentSizeIsEstimate and not FDoc.Loading and
       (FDoc.Text.ParaCount <= CRichContentExactParas)) then
      ScheduleCall(FSizeCall);
    Exit;
  end;
  h := ContentHeight;
  { The height set, and the view made for it: a bar that comes or goes with it (the
    horizontal one: the text no longer fits, or fits again) changes what the content needs -
    the height follows it, a few times at most (the width never changes here, so the
    heights of the text stay). Not while the size is an estimate (a file still loading, or
    more paragraphs than are measured whole): the control keeps the height it has - a height
    from an estimate would make the view, and so the layout and the kept surface, the whole
    document's. And never above CRichAutoHeightLimit. }
  tries := 0;
  if FAutoHeight and AutoHeightApplies and not ContentSizeIsEstimate then
    while (AutoHeightFor(h) <> Height) and (tries < 3) do
    begin
      Inc(tries);
      FSizingSelf := True;
      try
        Height := AutoHeightFor(h);
      finally
        FSizingSelf := False;
      end;
      h := ContentHeight;
    end;
  w := ContentWidth;
  if (h = FReportedH) and (w = FReportedW) then Exit;
  FReportedH := h;
  FReportedW := w;
  if Assigned(FOnContentSizeChange) then FOnContentSizeChange(Self);
end;

function TTyCustomRichEdit.NewBuilder: TTyRichBuilder;
begin
  Result := TTyRichBuilder.CreateFor(FDoc.DefaultCharFormat,
    FDoc.Formats.ParaFormat(FDoc.DefaultParaFormatId), FDoc.TextWidthTwips);
end;

{ (one of the content's commands: refused, nothing more is done. The document owns ACmd from
  the call on, also when it refuses it: a caller hands what ACmd took over to it first.) }
procedure RunContent(ADoc: TTyRichDocument; ACmd: TTyRichCommand; const AReason: string);
begin
  if not ADoc.Execute(ACmd) then
    if AReason <> '' then raise ETyRichEdit.Create(AReason)
    else raise ETyRichEdit.Create(rsRichEditRefusedRange);
end;

procedure TTyCustomRichEdit.SetContent(ABuilder: TTyRichBuilder);
var
  src: TTyRichDocument;
  cmd: TTyRichCommand;
  s: TTyRichDocSettings;
  n: Integer;
begin
  if ABuilder = nil then raise ETyRichEdit.Create('SetContent: no builder');
  if FDoc.Saving then raise ETyRichEdit.Create(rsRichEditRefusedSaving);
  // (made first: a builder that raises changes nothing)
  if ABuilder.IsEmpty then src := nil else src := ABuilder.MakeDocument;
  try
    // a new content: the history, the loader, the document's own values go (Clear's)
    Clear;
    FDoc.BeginUpdate;
    try
      if ABuilder.HasPageSetup or ABuilder.HasDocumentColor then
      begin
        s := FDoc.Settings;
        if ABuilder.HasPageSetup then
        begin
          s.PaperWidth := ABuilder.PaperWidth;
          s.MarginLeft := ABuilder.MarginLeft;
          s.MarginRight := ABuilder.MarginRight;
        end;
        if ABuilder.HasDocumentColor then s.Color := ABuilder.DocumentColorValue;
        RunContent(FDoc, TTyRichChangeSettings.Create(s), RefusalReason);
      end;
      if src <> nil then
      begin
        // the command takes the content over: it is not this method's to free from here on
        cmd := TTyRichInsertFragment.Create(0, src, True);
        src := nil;
        RunContent(FDoc, cmd, RefusalReason);
        // the empty paragraph Clear left goes, unless a table ends the content
        n := FDoc.Text.ParaCount;
        if (n > 1) and (FDoc.Text.ParaLength(n - 1) = 0) and (FDoc.CellAt(n - 2) = nil) then
          RunContent(FDoc, TTyRichDelete.Create(FDoc.Text.Length - 1, 1), RefusalReason);
      end;
    finally
      FDoc.EndUpdate;
    end;
    { as a load: no history, the saved point here (the caret stays at the start Clear put it
      at: what goes in at a caret's place leaves it before it) }
    FDoc.ClearUndo;
    FDoc.Modified := False;
  finally
    src.Free;
  end;
end;

procedure TTyCustomRichEdit.AppendContent(ABuilder: TTyRichBuilder);
var
  src: TTyRichDocument;
  cmd: TTyRichCommand;
  n: Integer;
  state: Int64;
begin
  if ABuilder = nil then raise ETyRichEdit.Create('AppendContent: no builder');
  if ABuilder.IsEmpty then Exit;
  if RefusalReason <> '' then raise ETyRichEdit.Create(RefusalReason);
  src := ABuilder.MakeDocument;
  state := FDoc.ContentState;
  try
    FDoc.BeginUpdate(rsRichUndoInsertContent);
    try
      // a last paragraph that holds something stays: the content begins after it
      n := FDoc.Text.ParaCount;
      if FDoc.Text.ParaLength(n - 1) > 0 then
        RunContent(FDoc, TTyRichInsertText.Create(FDoc.Text.Length, #10, TyRichInheritFormat,
          False), RefusalReason);
      n := FDoc.Text.ParaCount;
      cmd := TTyRichInsertFragment.Create(FDoc.Text.ParaStart(n - 1), src, True);
      src := nil;
      RunContent(FDoc, cmd, RefusalReason);
      // the empty paragraph after it goes (unless a table ends the content)
      n := FDoc.Text.ParaCount;
      if (n > 1) and (FDoc.Text.ParaLength(n - 1) = 0) and (FDoc.CellAt(n - 2) = nil) then
        RunContent(FDoc, TTyRichDelete.Create(FDoc.Text.Length - 1, 1), RefusalReason);
    finally
      FDoc.EndUpdate;
    end;
  except
    src.Free;
    // refused part way (the paragraph mark went in, the content did not): nothing stays
    if (FDoc.ContentState <> state) and FDoc.CanUndo and not FDoc.Updating then FDoc.Undo;
    raise;
  end;
end;

procedure TTyCustomRichEdit.InsertContent(APos: TTyRichPos; ABuilder: TTyRichBuilder);
var
  src: TTyRichDocument;
  atStart: Boolean;
  s, n, len0: TTyRichPos;
begin
  if ABuilder = nil then raise ETyRichEdit.Create('InsertContent: no builder');
  if (APos < 0) or (APos > FDoc.Text.Length) then
    raise ETyRichEdit.CreateFmt('InsertContent: position %d is not in 0..%d',
      [APos, FDoc.Text.Length]);
  if ABuilder.IsEmpty then Exit;
  if RefusalReason <> '' then raise ETyRichEdit.Create(RefusalReason);
  atStart := FDoc.Text.ParaStart(FDoc.Text.ParaOfPos(APos)) = APos;
  s := GetSelStart;
  n := GetSelLength;
  len0 := FDoc.Text.Length;
  src := ABuilder.MakeDocument;
  // whole paragraphs before the one at a paragraph's start; in line elsewhere (the command
  // takes the content over, refused or not)
  RunContent(FDoc, TTyRichInsertFragment.Create(APos, src, atStart), RefusalReason);
  { At the selection's very start the selection does not take the content in: it covers what
    it covered, after it (an insert before it moves it, one inside it grows it). }
  if (n > 0) and (s = APos) and not FDoc.Updating then
  begin
    s := s + FDoc.Text.Length - len0;
    Select(s, s + n, False);
    CaretMoved;
    DoSelectionChange;
  end;
end;

function TTyCustomRichEdit.ApplyParagraphSpacing(ABeforePt, AAfterPt: Double): Boolean;
var
  f: TTyParaFormat;
begin
  f := TyDefaultParaFormat;
  // Word's bounds (0 .. 1584 pt)
  f.SpaceBefore := TyRichPtToTwips(Math.Min(Math.Max(ABeforePt, 0), 1584));
  f.SpaceAfter := TyRichPtToTwips(Math.Min(Math.Max(AAfterPt, 0), 1584));
  Result := ApplyParagraphFormat([pffSpaceBefore, pffSpaceAfter], f);
end;

procedure TTyCustomRichEdit.RunApiEditIn(ACmd: TTyRichCommand; AChars: TTyRichPos;
  var ALife: TTyRichLife);
var
  state: Int64;
  reason: string;
  cmd: TTyRichCommand;
  place: TTyRichEditPlace;
  wait: Boolean;
begin
  try
    // a user's action in an application's hands: what is being composed goes in first
    EndCompositionForUser;
    if ViewBehind then
    begin
      // a command of the document's own update: reported when the update ends, as code's
      cmd := ACmd;
      ACmd := nil;
      state := FDoc.ContentState;
      if not FDoc.Execute(cmd) then
      begin
        reason := RefusalReason;
        if reason = '' then reason := rsRichEditRefusedRange;
        raise ETyRichEdit.Create(reason);
      end;
      // (an edit among them - InDelText - moves the selection as outside an update)
      FollowBlockWrite(cmd, state);
      Exit;
    end;
    reason := RefusalReason;
    if reason <> '' then raise ETyRichEdit.Create(reason);
  except
    ACmd.Free;
    raise;
  end;
  // the selection stays (also in a hidden tail), and with it a pending format
  place := Default(TTyRichEditPlace);
  place.Anchor := CRichPlaceStays;
  place.Caret := CRichPlaceStays;
  place.AtLineEnd := FCaretAtEnd;
  wait := AChars > FCopyWaitChars;
  if wait then BeginWait;
  Inc(FApiWrite);
  try
    RunMade(ACmd, place, False);
  finally
    // (a handler that freed the control: nothing of it is touched)
    if not ALife.Gone then
    begin
      Dec(FApiWrite);
      if wait then EndWait;
    end;
  end;
end;

procedure TTyCustomRichEdit.ApiCharFormat(AStart, ALen: TTyRichPos; AMask: TTyCharFormatMask;
  const AValue: TTyCharFormat);
var
  f, base: TTyCharFormat;
  keep, m: TTyCharFormatMask;
begin
  if AMask = [] then Exit;
  { A name or a size written that is the one text without a name / size of its own is shown
    in (the base's: what Name and Size read there, so what a toolbar writes back): such text
    shows it already and keeps none of its own - the base's value is not frozen into it, a
    later DefAttributes change still reaches it. Decided run by run by the engine
    (AKeepNone), so it holds over any selection, however large. }
  keep := [];
  if AMask * [cffFontName, cffSize] <> [] then
  begin
    base := BaseCharFormat;
    if (cffFontName in AMask) and (AValue.FontName <> '') and (AValue.FontName = base.FontName) then
      Include(keep, cffFontName);
    if (cffSize in AMask) and (AValue.SizeHalfPt > 0) and (AValue.SizeHalfPt = base.SizeHalfPt) then
      Include(keep, cffSize);
  end;
  if ALen <= 0 then
  begin
    { Nothing selected at the caret: the format the next typed text gets (no command, no
      undo step, no OnChange), merged over what it would get now. }
    if (AStart = FCaret) and not HasSelection then
    begin
      f := FDoc.Formats.CharFormat(TypingFormat);
      m := AMask;
      if (cffFontName in keep) and (f.FontName = '') then Exclude(m, cffFontName);
      if (cffSize in keep) and (f.SizeHalfPt <= 0) then Exclude(m, cffSize);
      f := TyMergeCharFormat(f, m, AValue);
      FPendingFmt := FDoc.Formats.InternChar(f);
      FPendingAt := FCaret;
      FHasPendingFmt := True;
      // (no OnChange for it: the paragraph view's hearers - a toolbar's Bold - are told)
      ParagraphViewChanged;
    end;
    Exit;
  end;
  // cells selected: each cell's text
  if CellsAreTheSelection(AStart, ALen) then
  begin
    RunApiEdit(AreaCellCommand(CellArea, False, AMask, AValue, keep, [], Default(TTyParaFormat)), ALen);
    Exit;
  end;
  RunApiEdit(TTyRichSetCharFormat.Create(TyRichRange(AStart, ALen), AMask, AValue, keep), ALen);
end;

procedure TTyCustomRichEdit.ApiParaFormat(AStart, ALen: TTyRichPos; AMask: TTyParaFormatMask;
  const AValue: TTyParaFormat);
var
  first, last: Integer;
begin
  if AMask = [] then Exit;
  // cells selected: each cell's paragraphs
  if CellsAreTheSelection(AStart, ALen) then
  begin
    RunApiEdit(AreaCellCommand(CellArea, True, [], Default(TTyCharFormat), [], AMask, AValue), ALen);
    Exit;
  end;
  ParasOfRange(AStart, ALen, first, last);
  RunApiEdit(TTyRichSetParaFormat.Create(first, last, AMask, AValue), ALen);
end;

{ RichMemo's positions, clamped to the text (as its controls clamp them). }
procedure ClampRange(ALength: TTyRichPos; var AStart, ALen: TTyRichPos);
begin
  if AStart < 0 then AStart := 0;
  if AStart > ALength then AStart := ALength;
  if ALen < 0 then ALen := 0;
  if ALen > ALength - AStart then ALen := ALength - AStart;
end;

procedure TTyCustomRichEdit.SetTextAttributes(AStart, ALen: TTyRichPos;
  const AParams: TTyFontParams);
begin
  EndCompositionForUser;
  ClampRange(FDoc.Text.Length, AStart, ALen);
  ApiCharFormat(AStart, ALen, CTyFontParamsMask, TyRichCharFormatOf(AParams));
end;

procedure TTyCustomRichEdit.SetTextAttributes(AStart, ALen: TTyRichPos; AFont: TFont);
var
  f: TTyCharFormat;
begin
  EndCompositionForUser;
  // RichMemo's: nothing for no font
  if AFont = nil then Exit;
  ClampRange(FDoc.Text.Length, AStart, ALen);
  ApiCharFormat(AStart, ALen, CTyFontMask, TyRichCharFormatOfFont(AFont));
end;

function TTyCustomRichEdit.GetTextAttributes(APos: TTyRichPos; var AParams: TTyFontParams): Boolean;
var
  id: TTyCharFormatId;
begin
  id := CharFormatIdAt(APos);
  Result := id >= 0;
  if Result then AParams := TyRichFontParamsOf(ResolvedFormat(FDoc.Formats.CharFormat(id)));
end;

procedure TTyCustomRichEdit.SetRangeColor(AStart, ALen: TTyRichPos; AColor: TColor);
var
  f: TTyCharFormat;
begin
  EndCompositionForUser;
  ClampRange(FDoc.Text.Length, AStart, ALen);
  f := TyDefaultCharFormat;
  f.Color := TyRichTextColorIn(AColor);
  ApiCharFormat(AStart, ALen, [cffColor], f);
end;

procedure TTyCustomRichEdit.SetRangeParams(AStart, ALen: TTyRichPos;
  AModifyMask: TTyTextModifyMask; const AFontName: string; AFontSize: Integer;
  AFontColor: TColor; AAddFontStyle, ARemoveFontStyle: TFontStyles);
var
  p: TTyFontParams;
begin
  p := Default(TTyFontParams);
  p.Name := AFontName;
  p.Size := AFontSize;
  p.Color := AFontColor;
  p.BkColor := clNone;
  SetRangeParams(AStart, ALen, AModifyMask, p, AAddFontStyle, ARemoveFontStyle);
end;

procedure TTyCustomRichEdit.SetRangeParams(AStart, ALen: TTyRichPos;
  AModifyMask: TTyTextModifyMask; const AParams: TTyFontParams;
  AAddFontStyle, ARemoveFontStyle: TFontStyles);
const
  Fields: array[TFontStyle] of TTyCharFormatField = (cffBold, cffItalic, cffUnderline, cffStrike);
var
  f: TTyCharFormat;
  m: TTyCharFormatMask;
  st: TFontStyle;
begin
  EndCompositionForUser;
  ClampRange(FDoc.Text.Length, AStart, ALen);
  f := TyRichCharFormatOf(AParams);
  m := [];
  if tmm_Name in AModifyMask then Include(m, cffFontName);
  if tmm_Size in AModifyMask then Include(m, cffSize);
  if tmm_Color in AModifyMask then Include(m, cffColor);
  if tmm_BackColor in AModifyMask then Include(m, cffHighlight);
  f.Style := [];
  f.Strike := False;
  if tmm_Styles in AModifyMask then
    for st := Low(TFontStyle) to High(TFontStyle) do
      if st in AAddFontStyle + ARemoveFontStyle then
      begin
        { only the styles named change; one in both sets ends up off - RichMemo's own
          statement is "Style := Style + AddFontStyle - RemoveFontStyle" }
        Include(m, Fields[st]);
        if (st in AAddFontStyle) and not (st in ARemoveFontStyle) then
          if st = fsStrikeOut then f.Strike := True else Include(f.Style, st);
      end;
  ApiCharFormat(AStart, ALen, m, f);
end;

function TTyCustomRichEdit.GetStyleRange(APos: TTyRichPos; var ARangeStart,
  ARangeLen: TTyRichPos): Boolean;
var
  t: TTyRichText;
  k, i, lo, hi: Integer;
  ps, pl, off, e: TTyRichPos;
  runs: TTyRunArray;
begin
  t := FDoc.Text;
  Result := (APos >= 0) and (APos <= t.Length);
  if not Result then Exit;
  k := t.ParaOfPos(APos);
  ps := t.ParaStart(k);
  pl := t.ParaLength(k);
  off := APos - ps;
  runs := FDoc.RunsOf(k);
  i := High(runs);
  while (i > 0) and (runs[i].Start > off) do Dec(i);
  lo := i;
  while (lo > 0) and (runs[lo - 1].Format = runs[i].Format) do Dec(lo);
  hi := i;
  while (hi < High(runs)) and (runs[hi + 1].Format = runs[i].Format) do Inc(hi);
  if hi < High(runs) then e := runs[hi + 1].Start else e := pl;
  ARangeStart := ps + runs[lo].Start;
  ARangeLen := e - runs[lo].Start;
end;

function TTyCustomRichEdit.GetParaAlignment(APos: TTyRichPos; var AAlign: TTyParaAlignment): Boolean;
var
  f: TTyParaFormat;
begin
  Result := ParaFormatAt(APos, f);
  if Result then AAlign := TyRichParaAlignmentOf(f.Align);
end;

function TTyCustomRichEdit.GetParaAlignment(APos: TTyRichPos): TTyParaAlignment;
begin
  Result := TyRichParaAlignmentOf(paraLeft);
  GetParaAlignment(APos, Result);
end;

procedure TTyCustomRichEdit.SetParaAlignment(AStart, ALen: TTyRichPos; AAlign: TTyParaAlignment);
var
  f: TTyParaFormat;
begin
  EndCompositionForUser;
  ClampRange(FDoc.Text.Length, AStart, ALen);
  f := TyDefaultParaFormat;
  f.Align := TyRichParaAlignOf(AAlign);
  ApiParaFormat(AStart, ALen, [pffAlign], f);
end;

function TTyCustomRichEdit.GetParaRange(APos: TTyRichPos; var ARange: TTyParaRange): Boolean;
var
  t: TTyRichText;
  k: Integer;
begin
  t := FDoc.Text;
  Result := (APos >= 0) and (APos <= t.Length);
  if not Result then Exit;
  k := t.ParaOfPos(APos);
  ARange.start := t.ParaStart(k);
  ARange.lengthNoBr := t.ParaLength(k);
  ARange.length := ARange.lengthNoBr;
  if k < t.ParaCount - 1 then Inc(ARange.length);
end;

function TTyCustomRichEdit.GetParaRange(APos: TTyRichPos; var AStart, ALength: TTyRichPos): Boolean;
var
  r: TTyParaRange;
begin
  Result := GetParaRange(APos, r);
  if not Result then Exit;
  AStart := r.start;
  ALength := r.length;
end;

function TTyCustomRichEdit.GetParaMetric(APos: TTyRichPos; var AMetric: TTyParaMetric): Boolean;
var
  f: TTyParaFormat;
begin
  Result := ParaFormatAt(APos, f);
  if Result then AMetric := TyRichMetricOf(f);
end;

procedure TTyCustomRichEdit.SetParaMetric(AStart, ALen: TTyRichPos; const AMetric: TTyParaMetric);
begin
  SetRangeParaParams(AStart, ALen, [pmm_FirstLine, pmm_HeadIndent, pmm_TailIndent,
    pmm_SpaceBefore, pmm_SpaceAfter, pmm_LineSpacing], AMetric);
end;

procedure TTyCustomRichEdit.SetRangeParaParams(AStart, ALen: TTyRichPos;
  AModifyMask: TTyParaModifyMask; const AMetric: TTyParaMetric);
begin
  EndCompositionForUser;
  ClampRange(FDoc.Text.Length, AStart, ALen);
  ApiParaFormat(AStart, ALen, TyRichMetricMask(AModifyMask, AMetric),
    TyRichParaFormatOfMetric(AMetric));
end;

function TTyCustomRichEdit.GetParaNumbering(APos: TTyRichPos;
  var ANumber: TTyParaNumbering): Boolean;
var
  f: TTyParaFormat;
begin
  Result := ParaFormatAt(APos, f);
  if Result then ANumber := TyRichNumberingOf(f.List);
end;

procedure TTyCustomRichEdit.SetParaNumbering(AStart, ALen: TTyRichPos;
  const ANumber: TTyParaNumbering);
var
  f, cur: TTyParaFormat;
begin
  EndCompositionForUser;
  ClampRange(FDoc.Text.Length, AStart, ALen);
  ParaFormatAt(AStart, cur);
  { Paragraph.Numbering's rule: the default hanging indent on, the indents away off; with
    ForceNewNum the range's first item begins a new list at NumberStart, the others go on }
  ApiParaFormat(AStart, ALen, CTyListMask + [pffListStart, pffListRestart],
    TyRichListValue(TyRichListOf(ANumber, cur.List)));
end;

function TTyCustomRichEdit.GetParaTabs(APos: TTyRichPos; var AStopList: TTyTabStopList): Boolean;
var
  f: TTyParaFormat;
begin
  Result := ParaFormatAt(APos, f);
  if Result then AStopList := TyRichTabListOf(f.Tabs);
end;

procedure TTyCustomRichEdit.SetParaTabs(AStart, ALen: TTyRichPos; const AStopList: TTyTabStopList);
var
  f, cur: TTyParaFormat;
begin
  EndCompositionForUser;
  ClampRange(FDoc.Text.Length, AStart, ALen);
  ParaFormatAt(AStart, cur);
  f := TyDefaultParaFormat;
  f.Tabs := TyRichTabsOf(AStopList, cur.Tabs);
  ApiParaFormat(AStart, ALen, [pffTabs], f);
end;

function TTyCustomRichEdit.LoadRichText(AStream: TStream): Boolean;
begin
  try
    LoadFromStream(AStream, rfRtf);
    Result := True;
  except
    on E: EOutOfMemory do raise;
    on E: Exception do Result := False;
  end;
end;

function TTyCustomRichEdit.GetText(AStart, ALen: TTyRichPos): string;
begin
  ClampRange(FDoc.Text.Length, AStart, ALen);
  Result := RangeText(AStart, ALen);
end;

function TTyCustomRichEdit.GetUText(AStart, ALen: TTyRichPos): UnicodeString;
begin
  Result := UTF8Decode(GetText(AStart, ALen));
end;

function TTyCustomRichEdit.InDelText(const AText: string; AStart,
  AReplaceLen: TTyRichPos): TTyRichPos;
var
  comp: TTyRichCompositeCommand;
  fmt: TTyCharFormatId;
  len0: TTyRichPos;
begin
  Result := 0;
  EndCompositionForUser;
  ClampRange(FDoc.Text.Length, AStart, AReplaceLen);
  if (AText = '') and (AReplaceLen = 0) then Exit;
  if AReplaceLen > 0 then fmt := CharFormatIdAt(AStart) else fmt := FDoc.TypingFormatAt(AStart);
  len0 := FDoc.Text.Length;
  comp := TTyRichCompositeCommand.Create(rsRichUndoInsertText);
  if AReplaceLen > 0 then comp.Add(TTyRichDelete.Create(AStart, AReplaceLen));
  if AText <> '' then comp.Add(TTyRichInsertText.Create(AStart, AText, fmt, False));
  RunApiEdit(comp, AReplaceLen + Length(AText));
  Result := FDoc.Text.Length - len0 + AReplaceLen;
end;

function TTyCustomRichEdit.CharAtPos(X, Y: Integer): TTyRichPos;
begin
  Result := PositionAtPoint(X, Y);
end;

procedure TTyCustomRichEdit.SetSelLengthFor(const AText: string);
begin
  SetSelLength(UTF8Length(AText));
end;

function TTyCustomRichEdit.SaveRichText(AStream: TStream): Boolean;
begin
  try
    SaveToStream(AStream, rfRtf);
    Result := True;
  except
    on E: EOutOfMemory do raise;
    on E: Exception do Result := False;
  end;
end;

function TTyCustomRichEdit.IsEditKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  case AKey of
    VK_BACK, VK_DELETE: Result := True;
    // Enter with Ctrl or Alt is the form's (a default button's), and a viewer's Enter too
    VK_RETURN: Result := not FReadOnly and (AShift * [ssCtrl, ssAlt, ssMeta] = []);
    VK_TAB: Result := FWantTabs;
    VK_X, VK_Y, VK_Z: Result := TyIsShortcutShift(AShift);
  else
    Result := False;
  end;
end;

procedure TTyCustomRichEdit.TypeKey(const AKey: TUTF8Char);
var
  s: RawByteString;
begin
  EndOwedLoad;
  if FReadOnly or ViewBehind then Exit;
  // the key's bytes as they are (a short string has no code page to convert from)
  s := '';
  SetLength(s, Length(AKey));
  if Length(AKey) > 0 then Move(AKey[1], s[1], Length(AKey));
  SetCodePage(s, CP_UTF8, False);
  { Printable: no control character - C0, DEL (Ctrl+Backspace types one on Windows), C1 (the
    one filter an input method's commit passes too, ImeText) - and whole characters only: a
    key never puts half a sequence in the text. }
  if (s = '') or (ControlCodeLen(s, 1) > 0) or not TyRichIsUtf8(PByte(s), Length(s)) then Exit;
  // a key an input method let through while composing: the composition goes in first
  EndCompositionForUser;
  if FReadOnly or ViewBehind then Exit;
  Settle;
  TypeText(s, True, True);
end;

procedure TTyCustomRichEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
var
  imeFull: string;
begin
  if not IsEnabled or (csDesigning in ComponentState) then Exit;
  { GTK3: the backend cut an input method's commit to a TUTF8Char on its way here; the whole
    of it is still pending in the widgetset - that goes in instead, as one commit (the memo's
    way; '' on every other widgetset and when nothing was cut). }
  imeFull := TyImeTakeCommit(UTF8Key);
  if imeFull <> '' then
  begin
    CommitComposition(imeFull);
    UTF8Key := '';
    Exit;
  end;
  // OnUTF8KeyPress, then OnKeyPress, before the character goes in - ReadOnly too (the memo's #150)
  inherited UTF8KeyPress(UTF8Key);
  if not TyAskKeyPress(Self, UTF8Key) then Exit;
  { During a drag of the control's own the character goes nowhere, as its key does
    (OwnDragKey) - also one that comes with no key-down before it (a posted WM_CHAR). }
  if OwnDragRunning then
  begin
    UTF8Key := '';
    Exit;
  end;
  try
    TypeKey(UTF8Key);
  finally
    if TyKeyPressAsked(UTF8Key) then UTF8Key := '';
  end;
end;

{ Each flavour's bytes go to LCL's clipboard as they are (AddFormat with a buffer): no stream
  copy of them on our side - LCL's cache and the system's clipboard make their own. }
procedure TTyCustomRichEdit.WriteClipboard(const ARtf: RawByteString; const AText: string);
var
  n: Integer;
begin
  Clipboard.Open;
  try
    Clipboard.Clear;
    if ARtf <> '' then
      Clipboard.AddFormat(RegisterClipboardFormat(TyRichClipboardRtfName), PAnsiChar(ARtf)^,
        Length(ARtf));
    // the text as Clipboard.AsText puts it (which would clear the RTF put first); the NUL a
    // widgetset wants after it is the one every string has after its last character
    // (PAnsiChar of '' points at one too)
    n := Length(AText);
    if ClipboardFormatNeedsNullByte(pcfText) then Inc(n);
    Clipboard.AddFormat(PredefinedClipboardFormat(pcfText), PAnsiChar(AText)^, n);
  finally
    Clipboard.Close;
  end;
end;

{ The clipboard's picture formats, by widgetset, the most faithful first, and the kind of
  bytes each gives (see ClipboardFlavours). }
type
  TTyRichClipPicture = record
    Format: TClipboardFormat;
    Kind: TTyRichImageKind;
  end;
  TTyRichClipPictures = array of TTyRichClipPicture;

function ClipPictureFormats: TTyRichClipPictures;
begin
  Result := nil;
  // (the last one tried, LCL's own picture format, is ReadClipboardPicture's: it is asked for)
  {$IFDEF LCLWin32}
  SetLength(Result, 2);
  Result[0].Format := RegisterClipboardFormat('PNG');
  Result[0].Kind := rikPng;
  // CF_DIB: LCL-Win32 takes a format id as the system's own
  Result[1].Format := 8;
  Result[1].Kind := rikDib;
  {$ELSE}
  {$IFDEF LCLCocoa}
  SetLength(Result, 2);
  Result[0].Format := RegisterClipboardFormat('public.png');
  Result[0].Kind := rikPng;
  Result[1].Format := RegisterClipboardFormat('public.tiff');
  Result[1].Kind := rikTiff;
  {$ELSE}
  SetLength(Result, 1);
  Result[0].Format := RegisterClipboardFormat('image/png');
  Result[0].Kind := rikPng;
  {$ENDIF}
  {$ENDIF}
end;

function ReadClipFormat(AFormat: TClipboardFormat): RawByteString;
var
  st: TMemoryStream;
begin
  Result := '';
  st := TMemoryStream.Create;
  try
    if Clipboard.GetFormat(AFormat, st) and (st.Size > 0) then
    begin
      SetLength(Result, st.Size);
      Move(st.Memory^, Result[1], st.Size);
    end;
  finally
    st.Free;
  end;
end;

function TTyCustomRichEdit.ClipboardFormatList: TTyRichClipFormats;
var
  cnt, i: Integer;
  list: PClipboardFormat;
begin
  Result := nil;
  list := nil;
  cnt := 0;
  Clipboard.SupportedFormats(cnt, list);
  try
    SetLength(Result, cnt);
    for i := 0 to cnt - 1 do Result[i] := list[i];
  finally
    if list <> nil then FreeMem(list);
  end;
end;

function TTyCustomRichEdit.ClipboardFlavours: TTyRichClipFlavours;
var
  fm: TTyRichClipFormats;
  pics: TTyRichClipPictures;
  i, j: Integer;
  rtfId, textId: TClipboardFormat;
begin
  Result := [];
  // one enumeration answers all of it (each HasFormat would be one of its own)
  fm := ClipboardFormatList;
  if fm = nil then Exit;
  rtfId := RegisterClipboardFormat(TyRichClipboardRtfName);
  textId := PredefinedClipboardFormat(pcfText);
  pics := ClipPictureFormats;
  for i := 0 to High(fm) do
  begin
    if fm[i] = rtfId then Include(Result, rcfRtf);
    if fm[i] = textId then Include(Result, rcfText);
    for j := 0 to High(pics) do
      if fm[i] = pics[j].Format then Include(Result, rcfPicture);
    // what this application copied through LCL (a TImage's bitmap)
    if TPicture.SupportsClipboardFormat(fm[i]) then Include(Result, rcfPicture);
  end;
end;

function TTyCustomRichEdit.ReadClipboardRtf: RawByteString;
begin
  Result := ReadClipFormat(RegisterClipboardFormat(TyRichClipboardRtfName));
end;

function TTyCustomRichEdit.ReadClipboardPicture(AIndex: Integer; out AKind: TTyRichImageKind;
  out ABytes: TBytes): Boolean;
var
  pics: TTyRichClipPictures;
  id: TClipboardFormat;
  mime: string;
  s: RawByteString;
begin
  ABytes := nil;
  AKind := rikPng;
  pics := ClipPictureFormats;
  Result := AIndex <= Length(pics);
  if not Result or (AIndex < 0) then Exit;
  if AIndex < Length(pics) then
  begin
    id := pics[AIndex].Format;
    AKind := pics[AIndex].Kind;
    if not Clipboard.HasFormat(id) then Exit;
  end
  else
  begin
    // LCL's own: a stream of the image file its graphic class writes
    id := Clipboard.FindPictureFormatID;
    if id = 0 then Exit;
    mime := LowerCase(ClipboardFormatToMimeType(id));
    if (mime = 'image/bmp') or (mime = 'image/x-bmp') or (mime = 'image/x-ms-bmp') then AKind := rikBmp
    else if mime = 'image/png' then AKind := rikPng
    else if (mime = 'image/jpeg') or (mime = 'image/jpg') then AKind := rikJpeg
    else if mime = 'image/tiff' then AKind := rikTiff
    else Exit;
  end;
  s := ReadClipFormat(id);
  if s = '' then Exit;
  SetLength(ABytes, Length(s));
  Move(s[1], ABytes[0], Length(s));
end;

function TTyCustomRichEdit.MakeFragmentFilter(ASource: TTyRichDocument): TTyRichFragmentFilter;
begin
  Result := TyRichFragmentFilterFor(ASource, FDoc);
end;

function TTyCustomRichEdit.ReadRtfSource(const ABytes: TBytes;
  out AEndsWithParagraph: Boolean): TTyRichDocument;
begin
  Result := TyRichReadRtfFragment(ABytes, AEndsWithParagraph);
end;

function TTyCustomRichEdit.ReadClipboardText: string;
begin
  Result := Clipboard.AsText;
end;

procedure TTyCustomRichEdit.BeginWait;
begin
  FSavedCursor := Screen.Cursor;
  Screen.Cursor := crHourGlass;
end;

procedure TTyCustomRichEdit.EndWait;
begin
  Screen.Cursor := FSavedCursor;
end;

procedure TTyCustomRichEdit.ShowTextMenu(const APos: TPoint);
begin
  if FTextMenu = nil then FTextMenu := TTyTextEditMenu.Create(Self);
  FTextMenu.Popup(APos);
end;

procedure TTyCustomRichEdit.DoContextPopup(MousePos: TPoint; var Handled: Boolean);
begin
  // a right press that ended a drag of the control's own: no menu
  if FEatMenu then
  begin
    FEatMenu := False;
    Handled := True;
    Exit;
  end;
  // nor while one runs (the menu key, Shift+F10: a key that does nothing then, OwnDragKey)
  if OwnDragRunning then
  begin
    Handled := True;
    Exit;
  end;
  // as the memo: OnContextPopup first, then a user's PopupMenu (LCL shows it), else ours
  inherited DoContextPopup(MousePos, Handled);
  if Handled or (PopupMenu <> nil) then Exit;
  { A page with nothing to edit or select (ReadOnly, AllowSelection False): every item of
    the text menu would be grey - no menu of the control's own (the application's PopupMenu
    and OnContextPopup work as on any control). }
  if FReadOnly and not FAllowSelection then Exit;
  ShowTextMenu(MousePos);
  Handled := True;
end;

function TTyCustomRichEdit.TeControl: TControl;
begin
  Result := Self;
end;

function TTyCustomRichEdit.TeController: TTyCustomStyleController;
begin
  Result := ActiveController;
end;

// (the menu's actions are a user's: through EndCompositionForUser first)
procedure TTyCustomRichEdit.TeUndo;
begin
  Undo;
end;

procedure TTyCustomRichEdit.TeRedo;
begin
  Redo;
end;

procedure TTyCustomRichEdit.TeCut;
begin
  CutToClipboard;
end;

procedure TTyCustomRichEdit.TeCopy;
begin
  CopyToClipboard;
end;

procedure TTyCustomRichEdit.TePaste;
begin
  // (the door is PasteFromClipboard's first step as well)
  EndCompositionForUser;
  PasteFromClipboard;
end;

procedure TTyCustomRichEdit.TeSelectAll;
begin
  EndCompositionForUser;
  if FAllowSelection then SelectAll;
end;

function TTyCustomRichEdit.TeCanUndo: Boolean;
begin
  Result := not FReadOnly and FDoc.CanUndo;
end;

function TTyCustomRichEdit.TeCanRedo: Boolean;
begin
  Result := not FReadOnly and FDoc.CanRedo;
end;

function TTyCustomRichEdit.TeHasSelection: Boolean;
begin
  Result := HasSelection and FAllowSelection;
end;

function TTyCustomRichEdit.TeCanPaste: Boolean;
begin
  Result := CanPaste;
end;

function TTyCustomRichEdit.TeHasText: Boolean;
begin
  Result := (FDoc.Text.Length > 0) and FAllowSelection;
end;

function TTyCustomRichEdit.TeIsReadOnly: Boolean;
begin
  Result := FReadOnly;
end;

function TTyCustomRichEdit.ImeTargetControl: TWinControl;
begin
  Result := Self;
end;

function TTyCustomRichEdit.ImeIsReadOnly: Boolean;
begin
  // (in the form designer nothing is typed: a composition there goes as a read-only one's)
  Result := FReadOnly or not IsEnabled or (csDesigning in ComponentState);
end;

function TTyCustomRichEdit.ImeCaretBoundClient: TRect;
begin
  if HasCaretFocus then Result := CaretClientRect else Result := Rect(0, 0, 0, 0);
end;

function TTyCustomRichEdit.ImeCaretIndex: Integer;
begin
  if FCaret > High(Integer) then Result := High(Integer) else Result := Integer(FCaret);
end;

procedure TTyCustomRichEdit.ImeSessionBegin;
begin
  if csDestroying in ComponentState then Exit;
  Inc(FInBridge);
  try
    FCocoaSession := True;
    FCocoaSwallow := False;
    FImeRefused := False;
    BeginComposition;
    { The bridge counts from here (ImeCaretIndex, which it asks next): taken after the
      composition began, whose settle may have put the caret on a caret place. }
    FCocoaBase := ImeCaretIndex;
  finally
    Dec(FInBridge);
  end;
end;

procedure TTyCustomRichEdit.ImeSessionEnd;
begin
  if csDestroying in ComponentState then Exit;
  Inc(FInBridge);
  try
    FCocoaSession := False;
    { The control ended this session's composition itself (it went in, or was dropped, then):
      what Cocoa still had marked goes nowhere. }
    if FCocoaSwallow then
    begin
      FCocoaSwallow := False;
      Exit;
    end;
    // a cancel replaced the text with '' first; a commit replaced it with the final text
    if FImeRefused then
    begin
      FImeRefused := False;
      DropComposition;
      Exit;
    end;
    if FComposing then CommitComposition(FCompText);
  finally
    Dec(FInBridge);
  end;
end;

procedure TTyCustomRichEdit.ImeReplace(AStart, ALen: Integer; const AText: string);
var
  s, cur: UTF8String;
  n: Integer;
begin
  if (csDestroying in ComponentState) or FImeRefused or FCocoaSwallow then Exit;
  Inc(FInBridge);
  try
    if not FComposing then
    begin
      { No session: a dead key's text (Cocoa's insertText with a replacement and no marked
        text, which no session end follows) is a commit at once (the terminal's way). }
      if ALen = 0 then
      begin
        CommitComposition(AText);
        Exit;
      end;
      FCocoaBase := AStart;
      if not BeginComposition then Exit;
    end;
    // the bridge's positions: characters from where the session began
    cur := FCompText;
    n := UTF8Length(cur);
    AStart := Math.EnsureRange(AStart - FCocoaBase, 0, n);
    ALen := Math.EnsureRange(ALen, 0, n - AStart);
    s := UTF8Copy(cur, 1, AStart) + ImeText(AText) + UTF8Copy(cur, AStart + ALen + 1, MaxInt);
    UpdateComposition(s);
  finally
    Dec(FInBridge);
  end;
end;

{$IFDEF LCLCocoa}
procedure TTyCustomRichEdit.CocoaImComposition(var Message: TLMessage);
begin
  // WParam 0: LCL-Cocoa asks for the input method handler; 1 (a word's lookup) is not answered
  if Message.WParam = 0 then Message.Result := PtrInt(FCocoaIme) else Message.Result := 0;
end;
{$ENDIF}

{ ---- the input method ----

  How the package's memo takes an input method, and what of it is here (the memo itself is
  not changed by it):
  - win32: the memo leaves the composition to the system's composition window (placed at its
    caret, TySetImeCaretPos) and takes the commit as WM_CHAR typing. Here the composition is
    shown in the text: the messages are taken (Result 1, so neither the composition window nor
    WM_IME_CHAR comes), the composition is read with ImmGetCompositionStringW (GCS_COMPSTR, its
    caret GCS_CURSORPOS, the clause GCS_COMPATTR's target attributes) and the commit
    (GCS_RESULTSTR) goes in at once, whole - as SynEdit's full IME handler does.
  - Cocoa: the memo's bridge (TyCocoaNewImeHandler, answered from LM_IM_COMPOSITION) drives
    ITyImeEditable; the memo puts the marked text into its text inside one undo step. Here a
    session is a composition the document does not get until its end.
  - Qt5 / Qt6 / GTK2: the memo installs the package's hook (TyImeInstall) that hands it whole
    commits, places the candidate window from its caret query and (GTK2) follows the focus;
    GTK3: TyImeTakeCommit in UTF8KeyPress. The same here: those hooks give commits, not the
    composition, which their input methods show in their own window - the hooks are the
    shared units' and say no more (not inline on those widgetsets, see the report).
  The composition is not the document's: the layouter is given it for its paragraph
  (SetComposition) and lays it out with the paragraph's text - nothing is edited and undone.
  A composition update lays out its one paragraph again (RefreshComposed) - nothing
  proportional to the document. }

function TTyCustomRichEdit.ImeText(const AText: string): UTF8String;
var
  i, n, k: Integer;
  b: Char;
  s: RawByteString;
begin
  s := AText;
  Result := '';
  if (s = '') or not TyRichIsUtf8(PByte(s), Length(s)) then Exit;
  SetLength(Result, Length(s));
  n := 0;
  i := 1;
  while i <= Length(s) do
  begin
    b := s[i];
    if b = #13 then
    begin
      // CR LF and CR alone: one LF (a paragraph)
      Inc(n);
      Result[n] := #10;
      if (i < Length(s)) and (s[i + 1] = #10) then Inc(i);
      Inc(i);
      Continue;
    end;
    // tab, LF and U+000B are an input method's line breaks; no other control character goes in
    k := 0;
    if (b <> #9) and (b <> #10) and (b <> #11) then k := ControlCodeLen(s, i);
    if k > 0 then
    begin
      Inc(i, k);
      Continue;
    end;
    Inc(n);
    Result[n] := b;
    Inc(i);
  end;
  SetLength(Result, n);
end;

function TTyCustomRichEdit.BeginComposition: Boolean;
var
  s, n: TTyRichPos;
  f, l: Integer;
begin
  if FComposing then Exit(True);
  Result := False;
  FImeRefused := False;
  { A composition begins: a result still owed for the one the control ended (FCompPending) is
    not waited for any more - an input method sends it before its next start. }
  FCompPending := False;
  FCompBefore := False;
  // as a key: ReadOnly or disabled takes it and says nothing; inside the update it is dropped
  if (csDestroying in ComponentState) or ImeIsReadOnly or ViewBehind then Exit;
  { Never under a drag of the control's own, whose keys do nothing (OwnDragKey): refused, told
    nothing - win32's input method is told to drop what it began (WMImeStartComposition);
    Cocoa's session goes on, and what it sends goes nowhere until it ends. }
  if OwnDragRunning then
  begin
    FImeRefused := True;
    Exit;
  end;
  EndOwedLoad;
  Settle;
  { Cells selected: typing replaces the first one's content (TypeTextIn), so the composition
    is shown there - that content becomes the selection it replaces. }
  if (FCaret <> FSelAnchor) and TyRichCellsEditable(CellArea) and FirstAreaCell(CellArea, f, l) then
  begin
    Select(FDoc.Text.ParaStart(f), FDoc.Text.ParaStart(l) + FDoc.Text.ParaLength(l), False);
    CaretMoved;
    DoSelectionChange;
  end;
  { Only where a character typed may go in, asked as typing asks it (TypingAllowed: the
    document takes edits, no row that holds a nested table, not across cells, not at a cut
    paragraph's cut) - one character stands for the composition, which itself counts toward
    no limit while it is shown. }
  s := GetSelStart;
  n := GetSelLength;
  if not TypingAllowed(s, n, 'x', True) then
  begin
    // told once; the rest of the input method's session goes nowhere
    FImeRefused := True;
    Exit;
  end;
  FComposing := True;
  // the selection now is the one its commit replaces (FCompAnchor .. FCompPos)
  FCompPos := FCaret;
  FCompAnchor := FSelAnchor;
  FCompText := '';
  FCompCaret := 0;
  FCompClauseFrom := 0;
  FCompClauseTo := 0;
  FCompFormat := TypingFormat;
  FImePlaced := Rect(0, 0, 0, 0);
  Result := True;
end;

procedure TTyCustomRichEdit.UpdateComposition(const AText: string; ACaret: Integer;
  AClauseStart: Integer; AClauseLength: Integer);
var
  s: UTF8String;
  n: Integer;
begin
  if (csDestroying in ComponentState) or FImeRefused then Exit;
  if not FComposing and not BeginComposition then Exit;
  s := ImeText(AText);
  n := UTF8Length(s);
  FCompText := s;
  if (ACaret < 0) or (ACaret > n) then FCompCaret := n else FCompCaret := ACaret;
  FCompClauseFrom := Math.EnsureRange(AClauseStart, 0, n);
  FCompClauseTo := Math.EnsureRange(AClauseStart + Math.Max(0, AClauseLength), FCompClauseFrom, n);
  ShowComposition;
end;

procedure TTyCustomRichEdit.RefreshComposed(APara: Integer);
var
  c: TTyRichChange;
begin
  if (APara < 0) or (APara >= FDoc.Text.ParaCount) or ViewBehind then Exit;
  // as a change of that paragraph's text the view hears of: its block, and what moves below
  c := Default(TTyRichChange);
  c.Kinds := [rckText];
  c.Pos := FDoc.Text.ParaStart(APara);
  c.FirstPara := APara;
  c.OldParaCount := 1;
  c.NewParaCount := 1;
  ChangeInView(c);
end;

procedure TTyCustomRichEdit.ShowComposition;
var
  t: TTyRichText;
  was, p: Integer;
begin
  if not FComposing then Exit;
  t := FDoc.Text;
  FCompPos := Math.Max(Int64(0), Math.Min(FCompPos, t.Length));
  p := t.ParaOfPos(FCompPos);
  was := FLayouter.Composition.Para;
  if FCompText = '' then
    FLayouter.ClearComposition
  else
    FLayouter.SetComposition(p, Integer(FCompPos - t.ParaStart(p)), FCompText, FCompFormat,
      FCompCaret, FCompClauseFrom, FCompClauseTo);
  if (was >= 0) and (was <> p) then RefreshComposed(was);
  RefreshComposed(p);
  { Its caret kept in view as the caret is, on every update - down (a composition that wraps
    below the view's bottom edge) as across (no wrapping, past the right edge) - so that the
    rectangle the input method is told is on screen. }
  ScrollCaretIntoView;
  CaretMoved;
  PlaceImeWindows;
end;

function TTyCustomRichEdit.CompositionRaster(out ARect: TRect): Boolean;
var
  k: Integer;
  r: TRect;
begin
  ARect := Rect(0, 0, 0, 0);
  Result := False;
  if not FComposing then Exit;
  k := HeldBlockOf(FCompPos);
  if (k < 0) or not FBlocks[k].Layout.CompositionCaret(r) then Exit;
  ARect := Rect(r.Left - FScrollX,
    Integer(Math.Max(Int64(-MaxInt div 4), Math.Min(FBlocks[k].Top + r.Top, Int64(MaxInt div 4)))),
    r.Right - FScrollX,
    Integer(Math.Max(Int64(-MaxInt div 4), Math.Min(FBlocks[k].Top + r.Bottom, Int64(MaxInt div 4)))));
  Result := True;
end;

procedure TTyCustomRichEdit.DropComposition;
var
  p: Integer;
begin
  if not FComposing then Exit;
  p := FLayouter.Composition.Para;
  FComposing := False;
  FCompText := '';
  FLayouter.ClearComposition;
  RefreshComposed(p);
  CaretMoved;
  // a replace that waited for the composition goes on
  FindWake;
end;

procedure TTyCustomRichEdit.CommitComposition(const AText: string);
var
  life: TTyRichLife;

  procedure Work;
  begin
    CommitCompositionIn(AText, life);
  end;

begin
  // (a commit's report: a handler that frees the control ends the call there)
  Guard(life, @Work);
end;

procedure TTyCustomRichEdit.CommitCompositionIn(const AText: string; var ALife: TTyRichLife);
var
  s: UTF8String;
  was, late, before: Boolean;
  p: Integer;
  fmt: TTyCharFormatId;
  t: TTyRichText;
  ua, uc, st, len0, delta, removed, n, cp: TTyRichPos;

  // a position of before the commit, where it is after it
  function Mapped(APos: TTyRichPos): TTyRichPos;
  begin
    // a press at the composition's place, before it (FCompBefore): before what goes in
    if before and (APos = cp) then Result := st
    else if APos < st then Result := APos
    else if APos >= st + removed then Result := APos + delta
    else Result := st + n;
  end;

begin
  if csDestroying in ComponentState then Exit;
  was := FComposing;
  { A result the input method owed for the composition the control ended (a press, a user's
    action, the focus leaving: told to commit, it had not answered then) goes where that
    composition was shown - not to where the press has put the caret since. }
  late := not was and FCompPending;
  FCompPending := False;
  before := late and FCompBefore;
  FCompBefore := False;
  cp := -1;
  p := -1;
  if was then
  begin
    // what was shown goes first: the commit's edit lays the paragraph out again without it
    p := FLayouter.Composition.Para;
    FComposing := False;
    FCompText := '';
    FLayouter.ClearComposition;
    // committed from outside Cocoa's bridge: what it still has marked goes nowhere
    if FCocoaSession and (FInBridge = 0) then FCocoaSwallow := True;
  end;
  if FImeRefused then
  begin
    // the session was refused when it began (told then): its commit goes nowhere either
    FImeRefused := False;
    if was then RefreshComposed(p);
    Exit;
  end;
  { A commit with no composition (the Qt and GTK hooks', Cocoa's dead key) during a drag of
    the control's own goes nowhere, as a character typed then does. A result owed for a
    composition a press ended goes in: it is what the user saw before the press. }
  if not was and not late and OwnDragRunning then Exit;
  s := ImeText(AText);
  FEditHeard := False;
  if (s <> '') and not ImeIsReadOnly and not ViewBehind then
  begin
    EndOwedLoad;
    Settle;
    t := FDoc.Text;
    ua := FSelAnchor;
    uc := FCaret;
    fmt := Low(TTyCharFormatId);
    if was or late then
    begin
      { Over the selection there was when it began, not one made meanwhile (code, or a
        user's action the composition ended before: Ctrl+A then the late result must not
        replace everything), and in the format it was shown in. }
      FCompPos := Math.Max(Int64(0), Math.Min(FCompPos, t.Length));
      FCompAnchor := Math.Max(Int64(0), Math.Min(FCompAnchor, t.Length));
      cp := FCompPos;
      if (FSelAnchor <> FCompAnchor) or (FCaret <> FCompPos) then
        Select(FCompAnchor, FCompPos, False);
      fmt := FCompFormat;
    end;
    st := GetSelStart;
    len0 := t.Length;
    n := UTF8Length(s);
    // (Mapped's before: the press's place, the selection start when it was the selection's end)
    if before and (cp <> st) and (cp <> st + GetSelLength) then before := False;
    { The one routine of typing (TypeText): the same refusals (a cell's edge, the paragraph
      kept before a table, a cut paragraph's cut) and the same command. Deliberately merged
      as typing: the memo commits as typing (uskTyping), which merges with the typing next to
      it - the engine merges mergeable inserts by their kind, so a commit, the typing before
      it and the typing after it are one undo step, as in the memo. A commit with a line
      break makes a paragraph: a step of its own, as Enter is. Over a selection: one
      composite, a fresh step (as typing over one). The caret behind it, counted. }
    { A late result: the edit reports nothing itself and does not scroll (FEditQuiet) - the
      selection the user made meanwhile (the press's) stays, moved with the text, and the
      change and that selection are reported once, after it is put back. }
    FEditQuiet := late;
    try
      TypeText(s, (Pos(#10, s) = 0) and (Pos(#11, s) = 0), True, fmt, n);
    finally
      if not ALife.Gone then FEditQuiet := False;
    end;
    if late and FEditHeard then
    begin
      if (FDoc.Text = t) and not ViewBehind then
      begin
        delta := t.Length - len0;
        removed := n - delta;
        Select(Mapped(ua), Mapped(uc), False);
        CaretMoved;
      end;
      DoChange;
      DoSelectionChange;
    end;
  end;
  // nothing went in (refused, empty, read-only): the paragraph shows what it has
  if was and not FEditHeard then
  begin
    RefreshComposed(p);
    CaretMoved;
  end;
end;

procedure TTyCustomRichEdit.CancelComposition;
begin
  // ended by code while Cocoa's session goes on: what it still has marked goes nowhere
  if (FComposing or FImeRefused) and FCocoaSession and (FInBridge = 0) then FCocoaSwallow := True;
  FImeRefused := False;
  FCompPending := False;
  FCompBefore := False;
  DropComposition;
end;

procedure TTyCustomRichEdit.EndComposition(ACommit: Boolean);
begin
  // a cancel (a content reset, ReadOnly, disabled, the window going) drops an owed result too
  if not ACommit then
  begin
    FCompPending := False;
    FCompBefore := False;
  end;
  if not FComposing and not FImeRefused then Exit;
  { Cocoa: the control cannot make the input context drop its marked text - the session goes
    on, and what it sends until its end is swallowed (it went in, or was dropped, here). }
  if FCocoaSession and (FInBridge = 0) then FCocoaSwallow := True;
  if not ACommit then
  begin
    // put away first: what the input method sends while it drops it finds nothing
    DropComposition;
    FImeRefused := False;
    ImeEndOnWidgetset(False);
    Exit;
  end;
  if FImeRefused then
  begin
    // nothing of it was shown or goes in; the input method drops it
    FImeRefused := False;
    ImeEndOnWidgetset(False);
    Exit;
  end;
  { The input method commits: its result comes back through its messages while it is told
    (win32's CPS_COMPLETE, as SynEdit's FocusKilled). One that was told and had not answered
    when the call returns sends it later: the composition leaves the screen, and a result
    that comes before the input method's next start goes in where it was shown
    (FCompPending). With none to tell, the text shown goes in. }
  if ImeEndOnWidgetset(True) then
  begin
    if FComposing then
    begin
      FCompPending := True;
      DropComposition;
    end;
  end
  else if FComposing then
    CommitComposition(FCompText);
end;

{ The one door of a user's edit and action: a key's edit (KeyDown's edit keys, a character
  typed, Ctrl+A, Tab between cells), a press, the menu's actions, paste, the format actions
  and the table actions all come in through it. A composition open in the text
  ends first, committed as a press commits it (what the input method has goes in where it was
  shown), so that the action works on the document the user sees: never on the text under a
  composition, nor a commit on a selection the action made (Ctrl+A, then a commit replacing
  everything). Copying, moving the caret, scrolling and zooming do not end it.
  The public methods that are a user's actions in an application's hands - an action list's
  shortcut (the form takes it before KeyDown), a toolbar button that never takes the focus -
  come through it too: CutToClipboard, PasteFromClipboard, Undo, Redo, InsertTable ..
  DeleteTable. Not the
  ones that are code: SelText :=, SelectAll, the setters, Lines, the document's own API (a
  composition follows such a change, and its commit goes where it moved). }
procedure TTyCustomRichEdit.EndCompositionForUser;
begin
  if FComposing or FImeRefused then EndComposition(True);
end;

function TTyCustomRichEdit.PressBeforeComposition(X, Y: Integer): Boolean;
var
  r: TRect;
begin
  { The hit test gives the composition's place for a point just before it, on it and just
    behind it alike; the composition's start (the caret before it) tells them apart. }
  r := PositionRect(FCompPos, False);
  if r.Bottom <= r.Top then Exit(False);
  Result := (Y < r.Top) or ((Y < r.Bottom) and (X < r.Left));
end;

procedure TTyCustomRichEdit.PlaceImeWindows;
var
  r: TRect;
begin
  if not HasCaretFocus then Exit;
  r := CaretClientRect;
  if r.Bottom <= r.Top then Exit;
  if EqualRect(r, FImePlaced) then Exit;
  FImePlaced := r;
  ImePlaceCandidates(r);
end;

procedure TTyCustomRichEdit.HookCommit(const ACommitUtf8: string);
begin
  CommitComposition(ACommitUtf8);
end;

function TTyCustomRichEdit.HookCaretRect: TRect;
begin
  { Client pixels (the GTK hook translates them to its toplevel's, Qt answers them as the
    widget's own): the caret's while focused, nothing (the input method's own place) else. }
  Result := ImeCaretBoundClient;
end;

function TTyCustomRichEdit.ImeEndOnWidgetset(ACommit: Boolean): Boolean;
{$IFDEF LCLWin32}
var
  imc: THandle;
{$ENDIF}
begin
  Result := False;
  {$IFDEF LCLWin32}
  if not HandleAllocated then Exit;
  imc := ImmGetContext(Handle);
  if imc = 0 then Exit;
  try
    if ACommit then ImmNotifyIME(imc, NI_COMPOSITIONSTR, CPS_COMPLETE, 0)
    else ImmNotifyIME(imc, NI_COMPOSITIONSTR, CPS_CANCEL, 0);
    Result := True;
  finally
    ImmReleaseContext(Handle, imc);
  end;
  {$ENDIF}
end;

procedure TTyCustomRichEdit.ImePlaceCandidates(const ARect: TRect);
{$IFDEF LCLWin32}
var
  imc: THandle;
  cf: TTyImmCompositionForm;
  cand: TTyImmCandidateForm;
{$ENDIF}
begin
  {$IFDEF LCLWin32}
  if not HandleAllocated then Exit;
  imc := ImmGetContext(Handle);
  if imc = 0 then Exit;
  try
    // the composition form (what the memo sets: some input methods put their candidates by it)
    cf := Default(TTyImmCompositionForm);
    cf.dwStyle := CFS_POINT;
    cf.ptCurrentPos := ARect.TopLeft;
    ImmSetCompositionWindow(imc, @cf);
    // and the candidate form: below the caret, never over its line
    cand := Default(TTyImmCandidateForm);
    cand.dwIndex := 0;
    cand.dwStyle := CFS_EXCLUDE;
    cand.ptCurrentPos := Point(ARect.Left, ARect.Bottom);
    cand.rcArea := ARect;
    ImmSetCandidateWindow(imc, @cand);
  finally
    ImmReleaseContext(Handle, imc);
  end;
  {$ELSE}
  // Qt asks for the cursor rectangle once per composition unless it is told it moved
  TyImeUpdateCaret;
  {$ENDIF}
end;

function TTyCustomRichEdit.ImeReadComposition(AIndex: LongWord; out AData: RawByteString): LongInt;
{$IFDEF LCLWin32}
var
  imc: THandle;
  n: LongInt;
{$ENDIF}
begin
  AData := '';
  Result := 0;
  {$IFDEF LCLWin32}
  if not HandleAllocated then Exit;
  imc := ImmGetContext(Handle);
  if imc = 0 then Exit;
  try
    n := ImmGetCompositionStringW(imc, AIndex, nil, 0);
    Result := n;
    // GCS_CURSORPOS answers the position itself; the others their bytes' count
    if (AIndex <> GCS_CURSORPOS) and (n > 0) then
    begin
      SetLength(AData, n);
      Result := ImmGetCompositionStringW(imc, AIndex, @AData[1], n);
      if Result < 0 then AData := '' else SetLength(AData, Result);
    end;
  finally
    ImmReleaseContext(Handle, imc);
  end;
  {$ENDIF}
end;

function TTyCustomRichEdit.ImeSetContextDefault(AWParam, ALParam: PtrInt): PtrInt;
begin
  Result := 0;
  {$IFDEF LCLWin32}
  if HandleAllocated then Result := DefWindowProcW(Handle, WM_IME_SETCONTEXT, AWParam, ALParam);
  {$ENDIF}
end;

{$IFDEF LCLWin32}
{ UTF-16 bytes as UTF-8, and how many code points the first AUnits UTF-16 units of them make
  (a surrogate pair is one). }
function ImmUtf8(const AData: RawByteString): UTF8String;
var
  w: UnicodeString;
begin
  w := '';
  SetLength(w, Length(AData) div 2);
  if w <> '' then Move(AData[1], w[1], Length(w) * 2);
  Result := UTF8Encode(w);
end;

function ImmCodePoints(const AData: RawByteString; AUnits: Integer): Integer;
var
  i, n: Integer;
  u: Word;
begin
  Result := 0;
  n := Math.Min(AUnits, Length(AData) div 2);
  i := 0;
  while i < n do
  begin
    u := PWord(@AData[1 + 2 * i])^;
    // a high surrogate and its low one: one code point
    if (u >= $D800) and (u <= $DBFF) and (i + 1 < Length(AData) div 2) then Inc(i);
    Inc(Result);
    Inc(i);
  end;
end;

procedure TTyCustomRichEdit.WMImeStartComposition(var Message: TLMessage);
begin
  // the control going (its document freed): taken, nothing done
  if csDestroying in ComponentState then
  begin
    Message.Result := 1;
    Exit;
  end;
  // read-only: the system's composition window, its text dropped as typing is
  if ImeIsReadOnly then
  begin
    inherited;
    Exit;
  end;
  Message.Result := 1;
  if not FComposing and not BeginComposition and FImeRefused then
    // refused (told once): the input method drops what it began
    ImeEndOnWidgetset(False);
end;

procedure TTyCustomRichEdit.WMImeComposition(var Message: TLMessage);
var
  flags: PtrInt;
  data, attr: RawByteString;
  units, i, a, b: Integer;
  s: UTF8String;
  caret, cf, ct: Integer;
begin
  if csDestroying in ComponentState then
  begin
    Message.Result := 1;
    Exit;
  end;
  if ImeIsReadOnly then
  begin
    inherited;
    Exit;
  end;
  Message.Result := 1;
  if FImeRefused then Exit;
  flags := Message.LParam;
  // the commit first (a Japanese or Korean one may come with the next composition)
  if (flags and GCS_RESULTSTR) <> 0 then
  begin
    ImeReadComposition(GCS_RESULTSTR, data);
    { The commit passes the key-press events a typed character passes, character by
      character, as the memo's win32 commit does (it arrives there as WM_CHAR typing): a
      handler that clears a character keeps it out, and the rest is still one insert. On the
      other widgetsets the memo's commits - and these - raise no key-press event (the hooks
      and Cocoa's bridge hand the whole commit over): the difference between widgetsets is
      the memo's and LCL's, kept on purpose. }
    CommitComposition(AskCommitKeys(ImmUtf8(data)));
    if FImeRefused or (csDestroying in ComponentState) then Exit;
  end;
  { The composition, its caret and its clause are read together whenever any of the three
    is said to have changed: an input method may move its caret or its target clause alone
    (SynEdit reads each on its own flag), and what is drawn follows all three. lParam 0
    (some input methods' way to say the composition was emptied): what the context holds
    now is read as well - empty, or as it was. }
  if ((flags and (GCS_COMPSTR or GCS_CURSORPOS or GCS_COMPATTR)) <> 0) or (flags = 0) then
  begin
    ImeReadComposition(GCS_COMPSTR, data);
    s := ImmUtf8(data);
    units := Length(data) div 2;
    caret := ImmCodePoints(data, ImeReadComposition(GCS_CURSORPOS, attr) and $FFFF);
    // the clause the input method converts: its target characters
    cf := 0;
    ct := 0;
    ImeReadComposition(GCS_COMPATTR, attr);
    a := -1;
    b := -1;
    for i := 0 to Math.Min(Length(attr), units) - 1 do
      if Byte(attr[i + 1]) in [ATTR_TARGET_CONVERTED, ATTR_TARGET_NOTCONVERTED] then
      begin
        if a < 0 then a := i;
        b := i + 1;
      end;
    if a >= 0 then
    begin
      cf := ImmCodePoints(data, a);
      ct := ImmCodePoints(data, b);
    end;
    if s = '' then
    begin
      // an emptied composition (the input method's cancel): nothing shown, still composing
      if FComposing then UpdateComposition('');
    end
    else
      UpdateComposition(s, caret, cf, ct - cf);
  end;
end;

procedure TTyCustomRichEdit.WMImeEndComposition(var Message: TLMessage);
begin
  if csDestroying in ComponentState then
  begin
    Message.Result := 1;
    Exit;
  end;
  { What the input method did not commit is dropped (its cancel, Esc) - always, read-only
    and disabled too: nothing of the control's composition outlives the input method's. }
  FImeRefused := False;
  DropComposition;
  if ImeIsReadOnly then
  begin
    inherited;
    Exit;
  end;
  Message.Result := 1;
end;

procedure TTyCustomRichEdit.WMImeSetContext(var Message: TLMessage);
begin
  // what the activation asks to show, told again when ReadOnly changes (SetReadOnly)
  if Message.WParam <> 0 then FImeContextL := Message.LParam;
  if (csDestroying in ComponentState) or (Message.WParam = 0) or ImeIsReadOnly then
  begin
    // as it came (read-only: the system's window shows the composition, as the memo's does)
    inherited;
    Exit;
  end;
  { The window gets the input context. The composition is shown in the text, so the system's
    composition window is not wanted: also when the focus comes with a composition already
    open in the thread's context, or the input method opens its window here. LCL-win32 hands
    DefWindowProc the message's own parameters when Result stays 0 (win32callback.inc), not
    changed ones: the default handling runs here with ISC_SHOWUICOMPOSITIONWINDOW cleared
    (the candidate window's bits stay), and Result 1 keeps LCL from running it again. }
  ImeSetContextDefault(Message.WParam, Message.LParam and not ISC_SHOWUICOMPOSITIONWINDOW);
  Message.Result := 1;
end;

procedure TTyCustomRichEdit.WMKillFocus(var Message: TLMKillFocus);
begin
  { The composition ends here, while this window still has the thread's input context (one
    context serves every window of the thread: nothing in LCL or the package gives a window
    its own), so that the input method's result comes back to this window - as SynEdit
    (WMKillFocus) and the system's edit controls do. CM_EXIT (DoExit) comes from inside the
    new control's set-focus, after the context moved on, and never when the focus goes to
    another form or program. }
  if not (csDestroying in ComponentState) then EndComposition(True);
  inherited;
end;

procedure TTyCustomRichEdit.WMSetFocus(var Message: TLMSetFocus);
begin
  { Back from another window of the thread (another form, which DoEnter does not hear of):
    the candidate window was put there for its control - put again at the next paint. }
  FImePlaced := Rect(0, 0, 0, 0);
  inherited;
end;

procedure TTyCustomRichEdit.WMImeRequest(var Message: TLMessage);
var
  cp: PTyImmCharPosition;
  r: TRect;
begin
  if (Message.WParam <> IMR_QUERYCHARPOSITION) or (Message.LParam = 0) or not HandleAllocated or
    (csDestroying in ComponentState) then
  begin
    inherited;
    Exit;
  end;
  // where the input method's caret is (screen pixels) and the line's height: the candidates go there
  r := CaretClientRect;
  if r.Bottom <= r.Top then
  begin
    inherited;
    Exit;
  end;
  cp := PTyImmCharPosition(Message.LParam);
  cp^.pt := ClientToScreen(Point(r.Left, r.Top));
  cp^.cLineHeight := r.Bottom - r.Top;
  cp^.rcDocument.TopLeft := ClientToScreen(Point(0, 0));
  cp^.rcDocument.BottomRight := ClientToScreen(Point(ClientWidth, ClientHeight));
  Message.Result := 1;
end;
{$ENDIF}

{ ---- the view: blocks and heights ---- }

procedure TTyCustomRichEdit.ReleaseBlocks;
var
  i: Integer;
begin
  for i := 0 to FBlockCount - 1 do
    if FBlocks[i].Layout <> nil then FBlocks[i].Layout.Release;
  FBlocks := nil;
  FBlockCount := 0;
end;

procedure TTyCustomRichEdit.ClearPending;
var
  i: Integer;
begin
  for i := 0 to FPendingCount - 1 do FPending[i].Picture.Release;
  FPending := nil;
  FPendingCount := 0;
end;

procedure TTyCustomRichEdit.ClearFailed;
var
  i: Integer;
begin
  for i := 0 to FFailedCount - 1 do FFailed[i].Picture.Release;
  FFailed := nil;
  FFailedCount := 0;
end;

function TTyCustomRichEdit.FailedIndex(APicture: TTyRichPicture; AWidth, AHeight: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to FFailedCount - 1 do
    if (FFailed[i].Picture = APicture) and (FFailed[i].Width = AWidth) and
      (FFailed[i].Height = AHeight) then Exit(i);
  Result := -1;
end;

procedure TTyCustomRichEdit.ApplyAnchorShare(ABlock: TTyBlockLayout);
begin
  if FAnchorShareDen <= 0 then Exit;
  FAnchorOffset := FAnchorShareNum * ABlock.Height div FAnchorShareDen;
  FAnchorShareDen := 0;
end;

function TTyCustomRichEdit.AnchorY: Int64;
begin
  Result := FDoc.Text.ParaTop(FAnchorPara) + FAnchorOffset;
end;

procedure TTyCustomRichEdit.Settle;
begin
  if not FViewValid then EnsureView(ViewPPI);
  if FSnapPending then SnapAfterChange;
end;

procedure TTyCustomRichEdit.SnapAfterChange;
var
  c, a: TTyRichPos;
begin
  FSnapPending := False;
  c := SnapPos(FCaret);
  a := SnapPos(FSelAnchor);
  if (c = FCaret) and (a = FSelAnchor) then Exit;
  Select(a, c, False);
  CaretMoved;
  { Not reported here: this runs inside a paint, a blink, the input method's query, a public
    query or at the start of a key or a click, and a handler (one that loads a file, changes
    the document or frees the control) must not run in any of them. A user action reports
    the move with its own one report at its end; otherwise the queued call does, after
    (it reports nothing when that report came first). }
  ScheduleCall(FSelCall);
end;

function TTyCustomRichEdit.ViewBehind: Boolean;
begin
  Result := FDoc.Updating or (FDoc.Text <> FText);
end;

procedure TTyCustomRichEdit.AddBlock(var AList: array of TTyRichViewBlock; var ACount: Integer;
  ALayout: TTyBlockLayout; ATop: Int64);
begin
  AList[ACount].Layout := ALayout;
  AList[ACount].FirstPara := ALayout.FirstPara;
  AList[ACount].LastPara := ALayout.LastPara;
  AList[ACount].Top := ATop;
  AList[ACount].Height := ALayout.Height;
  Inc(ACount);
end;

procedure TTyCustomRichEdit.NoteExtent(ALayout: TTyBlockLayout);
var
  w: Integer;
begin
  { The widest content that does not wrap (a line, an object, a table row: the block's Width),
    never the wrap width itself - text that wraps to the window fits it at any zoom. A
    page wider than the window scrolls over the page's width. }
  w := ALayout.Width;
  if (FWrapMode = rwmPage) and (ALayout.LayoutWidth <> CRichNoWrap) and
    (ALayout.LayoutWidth > w) then
    w := ALayout.LayoutWidth;
  if w > FWidestSeen then FWidestSeen := w;
end;

procedure TTyCustomRichEdit.LayoutSpanHeights(const AFirsts, ALasts, AHeights: array of Integer;
  AWidth, APPI: Integer; AZoom: Single);
var
  g, k, n: Integer;
  h: array of Int64;
begin
  // (a layout for another width or scale - a print's - is no height of the view's)
  if (AWidth <> FLayoutWidth) or (APPI <> FLayoutPPI) or (AZoom <> FLayoutZoom) then Exit;
  n := FDoc.Text.ParaCount;
  for g := 0 to High(AFirsts) do
  begin
    if (AFirsts[g] < 0) or (ALasts[g] < AFirsts[g]) or (ALasts[g] >= n) then Continue;
    h := nil;
    SetLength(h, ALasts[g] - AFirsts[g] + 1);
    for k := 0 to High(h) do h[k] := 0;
    h[0] := AHeights[g];
    FDoc.Text.SetParaHeights(AFirsts[g], h);
  end;
end;

procedure TTyCustomRichEdit.LayoutSpanDropped(AFirst, ALast: Integer);
var
  n: Integer;
begin
  n := FDoc.Text.ParaCount;
  if AFirst < 0 then AFirst := 0;
  if ALast > n - 1 then ALast := n - 1;
  if AFirst <= ALast then FDoc.Text.UnmeasureParas(AFirst, ALast);
end;

{ The heights of view blocks AFrom .. ATo (which follow each other in the document) in one
  call: a block's height on its first paragraph, 0 on the others (a table row). }
procedure TTyCustomRichEdit.WriteHeights(AFrom, ATo: Integer);
var
  h: array of Int64;
  first, i, k: Integer;
begin
  if (AFrom > ATo) or (AFrom < 0) or (ATo >= FBlockCount) then Exit;
  first := FBlocks[AFrom].FirstPara;
  SetLength(h, FBlocks[ATo].LastPara - first + 1);
  for i := 0 to High(h) do h[i] := 0;
  for k := AFrom to ATo do
    h[FBlocks[k].FirstPara - first] := FBlocks[k].Height;
  FDoc.Text.SetParaHeights(first, h);
end;

function TTyCustomRichEdit.BaseFontStyle(const AStyle: TTyStyleSet): TFontStyles;
begin
  // the weight carries the control's Font.Style (italic, underline, strike-through as flags)
  if tpFontWeight in AStyle.Present then Result := TyFontStylesOf(AStyle.FontWeight)
  else Result := [];
end;

procedure TTyCustomRichEdit.CheckLayoutParams(APPI: Integer);
var
  s: TTyStyleSet;
  halfPt, w, est, k, rppi: Integer;
  z: Single;
  factor: Double;
  area: TRect;
  fontDiff: Boolean;
  style: TFontStyles;
begin
  if APPI <= 0 then APPI := 96;
  FViewPPI := APPI;
  s := CurrentStyle;
  halfPt := BaseHalfPt(s);
  style := BaseFontStyle(s);
  fontDiff := (s.FontName <> FLayoutFont) or (halfPt <> FLayoutFontSize) or
    (style <> FLayoutFontStyle);
  if fontDiff then
  begin
    FLayoutFont := s.FontName;
    FLayoutFontSize := halfPt;
    FLayoutFontStyle := style;
    // each setter empties the layouter's caches when it changes something
    FLayouter.BaseFontName := s.FontName;
    FLayouter.BaseFontSizeHalfPt := halfPt;
    FLayouter.BaseFontStyle := style;
  end;
  // the view in raster pixels: the layout is made for the device (PPI x scale)
  if FScale < 1 then FScale := 1;
  rppi := APPI * FScale;
  area := TextArea(Rect(0, 0, Width, Height), APPI);
  FViewW := Math.Max(0, area.Right - area.Left) * FScale;
  FViewH := Math.Max(0, area.Bottom - area.Top) * FScale;
  z := FZoom / 100;
  w := TyRichLayoutWidth(FWrapMode, Math.Max(1, FViewW), FDoc, rppi, z);
  est := FLayouter.EstimatedParaHeight(rppi, z);
  if est < 1 then est := 1;
  if fontDiff or (w <> FLayoutWidth) or (rppi <> FLayoutPPI) or (z <> FLayoutZoom) or
    (est <> FEstimate) then
  begin
    { Every height is stale: the measured ones go (no node is walked), the estimate is the
      new line's, and the anchor - a paragraph and an offset - stays where it is. A z or PPI
      change also changes every font, so the layouter starts afresh; a width change keeps the
      measured advances (its cached layouts are replaced as they are asked for). The offset
      is kept as a share of the anchor block's height: the same part of that block stays at
      the top once it is laid out again. }
    if FAnchorShareDen = 0 then
      for k := 0 to FBlockCount - 1 do
        if (FBlocks[k].FirstPara = FAnchorPara) and (FBlocks[k].Height > 0) then
        begin
          FAnchorShareNum := FAnchorOffset;
          FAnchorShareDen := FBlocks[k].Height;
          Break;
        end;
    if ((rppi <> FLayoutPPI) or (z <> FLayoutZoom)) and (FLayoutPPI > 0) and (FLayoutZoom > 0) then
    begin
      { Every font changes, no picture does: the layouts and measures go, the decoded pictures
        stay. What is wide is as much wider: the horizontal position keeps its fraction of the
        extent where there is still something to scroll (clamped to the new extent, 0 where
        there is none). The scaled extent only stands in for the bars' first decision: the
        next layout builds the extent again from what it lays out, so it can shrink. }
      FLayouter.ClearLayouts;
      factor := (z * rppi) / (FLayoutZoom * FLayoutPPI);
      FScrollX := Round(FScrollX * factor);
      FWidestSeen := Round(FWidestSeen * factor);
      FExtentStale := True;
    end
    else
      FWidestSeen := 0;
    if FLayoutPPI <> 0 then FDoc.Text.UnmeasureAll;
    ReleaseBlocks;
    { The pictures waiting were met at the old sizes, and one that failed there may not fail at
      another: what the view meets next is queued afresh. }
    ClearPending;
    ClearFailed;
    InvalidateSurface;
    FLayoutWidth := w;
    FLayoutPPI := rppi;
    FLayoutZoom := z;
    FEstimate := est;
    FViewValid := False;
    // the wished x is a raster x of the old layout (a zoom, a width, a scale): Up / Down
    // start again from where the caret is now
    FWishValid := False;
  end;
  if FDoc.Text.DefaultParaHeight <> FEstimate then FDoc.Text.DefaultParaHeight := FEstimate;
end;

procedure TTyCustomRichEdit.LayoutView;
var
  below, above, old: array of TTyRichViewBlock;
  nBelow, nAbove, nOld, i, j, next, k, paraCount: Integer;
  y, total, deficit, shift, topY: Int64;
  b: TTyBlockLayout;
  t: TTyRichText;
begin
  // what was held, to tell afterwards whether the text on screen moved
  old := Copy(FBlocks, 0, FBlockCount);
  nOld := FBlockCount;
  ReleaseBlocks;
  // the extent from what is laid out now (a zoom's stand-in goes)
  if FExtentStale then
  begin
    FWidestSeen := 0;
    FExtentStale := False;
  end;
  FViewValid := True;
  FViewShifted := nOld > 0;
  FMoveKnown := False;
  FMovedBy := 0;
  if FViewH <= 0 then Exit;
  t := FDoc.Text;
  paraCount := t.ParaCount;
  if FAnchorPara >= paraCount then
  begin
    // past the end (the content shrank): the last block, pulled up below to fill the view
    FAnchorPara := paraCount - 1;
    FAnchorOffset := 0;
  end;
  if FAnchorPara < 0 then FAnchorPara := 0;
  if FAnchorOffset < 0 then FAnchorOffset := 0;
  below := nil;
  above := nil;
  nBelow := 0;
  nAbove := 0;
  next := 0;
  total := 0;
  b := nil;
  FDoc.BeginRead;
  try
    try
      // the anchor's block: a paragraph inside a table row anchors the row
      b := LayoutBlockAt(FAnchorPara);
      if b.FirstPara <> FAnchorPara then
      begin
        topY := t.ParaTop(FAnchorPara) - t.ParaTop(b.FirstPara) + FAnchorOffset;
        FAnchorOffset := topY;
        FAnchorPara := b.FirstPara;
      end;
      ApplyAnchorShare(b);
      if FAnchorOffset >= b.Height then FAnchorOffset := Math.Max(0, b.Height - 1);
      // down: the view and a screen past it
      SetLength(below, 64);
      y := -FAnchorOffset;
      repeat
        if nBelow = Length(below) then SetLength(below, nBelow * 2);
        AddBlock(below, nBelow, b, y);
        b := nil;
        NoteExtent(below[nBelow - 1].Layout);
        Inc(y, below[nBelow - 1].Height);
        next := below[nBelow - 1].LastPara + 1;
        if (y >= 2 * FViewH) or (next >= paraCount) then Break;
        b := LayoutBlockAt(next);
      until False;
      // at the end of the document the last line stays at the bottom of the view
      deficit := 0;
      if (next >= paraCount) and (y < FViewH) then deficit := FViewH - y;
      // up: a screen above the view (and what the end needs to fill it)
      SetLength(above, 64);
      i := FAnchorPara - 1;
      while (i >= 0) and (total < FViewH + deficit) do
      begin
        b := LayoutBlockAt(i);
        if nAbove = Length(above) then SetLength(above, nAbove * 2);
        Inc(total, b.Height);
        AddBlock(above, nAbove, b, -FAnchorOffset - total);
        b := nil;
        NoteExtent(above[nAbove - 1].Layout);
        i := above[nAbove - 1].FirstPara - 1;
      end;
    except
      // a layout that raised: none of the references taken so far is kept
      if b <> nil then b.Release;
      for k := 0 to nBelow - 1 do below[k].Layout.Release;
      for k := 0 to nAbove - 1 do above[k].Layout.Release;
      FViewValid := False;
      raise;
    end;
  finally
    FDoc.EndRead;
  end;
  // the blocks in document order
  FBlockCount := nAbove + nBelow;
  SetLength(FBlocks, FBlockCount);
  for k := 0 to nAbove - 1 do FBlocks[k] := above[nAbove - 1 - k];
  for k := 0 to nBelow - 1 do FBlocks[nAbove + k] := below[k];
  if deficit > 0 then
  begin
    // the view moves up by what is missing below, as far as there is something above
    shift := Math.Min(deficit, total + FAnchorOffset);
    if shift > 0 then
    begin
      for k := 0 to FBlockCount - 1 do Inc(FBlocks[k].Top, shift);
      for k := 0 to FBlockCount - 1 do
        if (FBlocks[k].Top <= 0) and (FBlocks[k].Top + FBlocks[k].Height > 0) then
        begin
          FAnchorPara := FBlocks[k].FirstPara;
          FAnchorOffset := -FBlocks[k].Top;
          Break;
        end;
    end;
  end;
  { Did the text on screen move? The first block in the view, looked up among the blocks held
    before: there at the same top, nothing moved; at another top, the view moved by that much
    (a scroll, the end's pull-up); not there, it is all new. }
  if nOld > 0 then
    for k := 0 to FBlockCount - 1 do
      if FBlocks[k].Top + FBlocks[k].Height > 0 then
      begin
        for j := 0 to nOld - 1 do
          if (old[j].FirstPara = FBlocks[k].FirstPara) and (old[j].LastPara = FBlocks[k].LastPara) then
          begin
            FMoveKnown := True;
            FMovedBy := FBlocks[k].Top - old[j].Top;
            FViewShifted := FMovedBy <> 0;
            Break;
          end;
        Break;
      end;
  if nOld = 0 then
    // all new (the blocks were let go: whoever did invalidated the window)
    MarkTextDirty
  else if FViewShifted then
  begin
    // the text moved: on the surface too, and what it exposed is drawn
    if FMoveKnown then MoveSurfaceText(0, FMovedBy) else MarkTextDirty;
    // (inside a paint that blits the whole text area, a second paint would only blit again)
    if not FPaintCoversText then InvalidateArea(TextWindowRect);
  end;
  WriteHeights(0, FBlockCount - 1);
  QueuePicturesAhead;
end;

{ ---- the document changed ---- }

{ Where position APos is after AChange: a change that ends before it (or an insertion at it)
  moves it by what the text grew or shrank; a change that took away the text it was in puts it
  at the change's start; a change after it leaves it. }
procedure ShiftForChange(var APos: TTyRichPos; const AChange: TTyRichChange);
begin
  if APos < AChange.Pos then Exit;
  if (APos = AChange.Pos) and (AChange.OldLen = 0) then
    // an insertion at it: the new text comes after it (as text added to a viewer)
    Exit;
  if APos >= AChange.Pos + AChange.OldLen then
    Inc(APos, AChange.NewLen - AChange.OldLen)
  else
    APos := AChange.Pos;
end;

{ A place a press chose, through a change: before the change's start, or at it and not
  AAfter (the press was before what goes in there), it stays; past what the change replaced
  it moves by the difference; at the start with AAfter, or inside what was replaced, it goes
  behind what replaced it. }
procedure CarryForChange(var APos: TTyRichPos; AAfter: Boolean; const AChange: TTyRichChange);
begin
  if (APos < AChange.Pos) or ((APos = AChange.Pos) and not AAfter) then Exit;
  if APos >= AChange.Pos + AChange.OldLen then
    Inc(APos, AChange.NewLen - AChange.OldLen)
  else
    APos := AChange.Pos + AChange.NewLen;
end;

function TTyCustomRichEdit.FollowBlockWrite(ACmd: TTyRichCommand; AStateBefore: Int64): Boolean;
var
  c: TTyRichChange;
begin
  Result := False;
  // (an unchanged command was freed by Execute and took no state number)
  if not FDoc.Updating or (FDoc.ContentState = AStateBefore) then Exit;
  Result := True;
  c := ACmd.Change;
  if FEditing > 0 then
  begin
    FEditHeard := True;
    FEditChange := c;
  end;
  FollowBlockChange(c);
end;

procedure TTyCustomRichEdit.FollowBlockChange(const AChange: TTyRichChange);
var
  was: TTyRichPos;
begin
  // (outside an update DocChanged has already moved them over this change)
  if not FDoc.Updating or not (rckText in AChange.Kinds) then Exit;
  { From here on the update's one change at its end does not move the positions: they follow
    every write of the control's own as it is made. }
  FPosInUpdate := True;
  { A write wholly behind the selection moves neither end: the selection did not move, and an
    update that only appended (Lines.Add) costs no repaint of the text window at its end. }
  if AChange.Pos > Math.Max(FCaret, FSelAnchor) then Exit;
  // DocChanged's arithmetic, for this one write (the update's change will not move them again)
  was := FCaret;
  ShiftForChange(FCaret, AChange);
  ShiftForChange(FSelAnchor, AChange);
  FCaret := Math.Max(Int64(0), Math.Min(FCaret, FDoc.Text.Length));
  FSelAnchor := Math.Max(Int64(0), Math.Min(FSelAnchor, FDoc.Text.Length));
  if FCaret <> was then FCaretAtEnd := False;
  FSelInUpdate := True;
  FWishValid := False;
end;

procedure TTyCustomRichEdit.DocChanged(Sender: TObject; const AChange: TTyRichChange);
var
  was, wasAnchor: TTyRichPos;
  loadOwn: Boolean;
begin
  { The load's own change: one made while the step runs AND the document still loads. A
    slice is appended before the last step ends the loading; a command run from the last
    step's progress handler (the document no longer loads there) is an edit - for the
    layouter's trust, the caret and the anchor, and the change report alike. The
    notice a cancelled load gives that it stopped comes after the load state ended, and is
    the load's own all the same: it changes no text of the file. }
  loadOwn := (FInStep and FDoc.Loading) or FInCancel;
  // the bookmarks the view lists: kept, or built again when next asked
  if FBkmIndex <> nil then FBkmIndex.Changed(AChange);
  // a drag of a handle measured the object as it was: any change ends it, nothing done
  CancelResize;
  // so does a drag of the selection: its range and its place were of the text as it was
  CancelSelectionDrag;
  { A press whose wait this ended is still a click at its release: its place follows the text,
    as the caret does (an object it was on may be gone: a plain click there). }
  if FPressClickOwed and (rckText in AChange.Kinds) and not loadOwn then
  begin
    ShiftForChange(FPressPlace, AChange);
    FDragPressObj := -1;
  end;
  // (a background replace's place to go on from follows an edit it did not make)
  if not loadOwn and ((FFindKind = rfkReplace) or (FOwedKind = rfkReplace)) then
    ReplaceResumeFollows(AChange);
  { A composition shown while the document changes elsewhere (code, an undo from a handler)
    follows the text as the caret does; the layouter is told where before it hears of the
    change, which drops the block or moves it with what it laid out. So does the place of a
    result still owed (FCompPending), and the selection the commit replaces. }
  if (FComposing or FCompPending) and (FDoc.Text = FText) and (rckText in AChange.Kinds) and
    not loadOwn then
  begin
    ShiftForChange(FCompPos, AChange);
    ShiftForChange(FCompAnchor, AChange);
    FCompPos := Math.Max(Int64(0), Math.Min(FCompPos, FDoc.Text.Length));
    FCompAnchor := Math.Max(Int64(0), Math.Min(FCompAnchor, FDoc.Text.Length));
    if FComposing and (FLayouter.Composition.Para >= 0) then
      FLayouter.MoveComposition(FDoc.Text.ParaOfPos(FCompPos),
        Integer(FCompPos - FDoc.Text.ParaStart(FDoc.Text.ParaOfPos(FCompPos))));
  end;
  { A press made while composing (MouseDown): its place goes through the commit that ends the
    composition - text inserted at it goes after it when the press was before the
    composition, before it when on it or behind it; inside a range replaced: behind what
    replaced it. The object under it is that object, at its new place: text inserted at it
    goes before it; one inside the range the commit replaced (a picture selected, then
    composed over) is gone - the press selects no object then. }
  if FPressCarry and (rckText in AChange.Kinds) then
  begin
    if FDoc.Text <> FText then
      FPressCarry := False
    else
    begin
      CarryForChange(FPressPos, FPressAfter, AChange);
      if FPressObj >= 0 then
      begin
        if (FPressObj >= AChange.Pos) and (FPressObj < AChange.Pos + AChange.OldLen) then
          FPressObj := -1
        else
          CarryForChange(FPressObj, True, AChange);
      end;
    end;
  end;
  FLayouter.DocumentChanged(AChange, loadOwn);
  { The table kept for the Can... answers was found for the content as it was: let go (a
    table of an old content is not held alive). A load's own slices change no content. }
  if not loadOwn then ReleaseAskedTable;
  if FDoc.Text <> FText then
    ContentReplaced
  else
  begin
    { The caret and the anchor follow the text by arithmetic alone (no query: inside the
      document's update the view knows nothing yet); the next paint or settled query puts
      them on caret places (FSnapPending). A format change moves neither; the slices a lazy
      load appends come after everything.
      Inside BeginUpdate .. EndUpdate the view hears one merged change (the union of the
      ranges, their kinds together), so a caret between two edits of one update goes to the
      first edit's start, and a format change joined with an inserted character moves a
      caret anywhere in that range. Right for a change from elsewhere. An edit the control
      makes (FEditing) places the caret itself when the command has run (FinishEdit):
      here the positions only follow the text by the same arithmetic - so that what the
      edit's Select repaints of an old selection is in the text as it is now - and are
      neither snapped nor reported. }
    if (rckText in AChange.Kinds) and not loadOwn then
    begin
      was := FCaret;
      wasAnchor := FSelAnchor;
      { A selection set inside the update was set on the text as it was then, and positions
        that followed the control's own writes in it are already where those put them: the
        update's own change does not move them again; they are clamped to the final
        text. }
      if not FPosInUpdate then
      begin
        ShiftForChange(FCaret, AChange);
        ShiftForChange(FSelAnchor, AChange);
      end;
      FCaret := Math.Max(Int64(0), Math.Min(FCaret, FDoc.Text.Length));
      FSelAnchor := Math.Max(Int64(0), Math.Min(FSelAnchor, FDoc.Text.Length));
      if FCaret <> was then FCaretAtEnd := False;
      { Snapped later also when it did not move: text taken away right after it can leave it
        before a combining mark. }
      if (FEditing = 0) and ((FCaret <> was) or (FSelAnchor <> wasAnchor) or
        (AChange.Pos <= FCaret + 1) or (AChange.Pos <= FSelAnchor + 1)) then
        FSnapPending := True;
      FWishValid := False;
    end;
    { A slice a turn appends: its change of the bars may wait (UpdateBars). The end of a
      load (Loading False there) and anything that is not a slice reach them at once. }
    FBarsLazy := loadOwn and FInTurn and FDoc.Loading;
    try
      ChangeInView(AChange);
    finally
      FBarsLazy := False;
    end;
    { A paint that came while the document held this change back showed nothing new and left
      the window painted: the change's own bands are not all it missed (with no block held
      they are nothing). The window is painted again, whole, once. }
    if FSkippedPaint then
    begin
      FSkippedPaint := False;
      InvalidateArea(Rect(0, 0, Width, Height));
    end;
  end;
  if (FLines <> nil) and (FDoc.Text.Length > 0) then FLines.FEmptyLine := False;
  // the slices a lazy load adds are its progress, not changes of the content
  if loadOwn then Exit;
  // a change made elsewhere ends a pending format (the control's own edits place the caret)
  if FEditing = 0 then FHasPendingFmt := False;
  if FEditing > 0 then
  begin
    // the control's own edit: it places the caret and reports when the command has run
    FEditHeard := True;
    FEditChange := AChange;
    Exit;
  end;
  DoChange;
  DoSelectionChange;
end;

procedure TTyCustomRichEdit.DocUpdatingEnded(Sender: TObject);
begin
  // a replace that waited for the update's end goes on
  FindWake;
  // (raised only when Updating is False; a content not heard of yet is DocChanged's)
  if ViewBehind then Exit;
  FPosInUpdate := False;
  if FSelInUpdate then
  begin
    FSelInUpdate := False;
    FCaret := Math.Max(Int64(0), Math.Min(FCaret, FDoc.Text.Length));
    FSelAnchor := Math.Max(Int64(0), Math.Min(FSelAnchor, FDoc.Text.Length));
    // put on caret places by the next paint or settled query, reported after it
    FSnapPending := True;
    // where it was painted before is not known any more: the text window, once
    MarkTextDirty;
    InvalidateArea(TextWindowRect);
    CaretMoved;
  end;
  { A paint skipped while the document held its changes back is made good also for an
    update that ended with nothing to report: DocChanged made it good when there was a
    change. }
  if FSkippedPaint then
  begin
    FSkippedPaint := False;
    InvalidateArea(Rect(0, 0, Width, Height));
  end;
end;

procedure TTyCustomRichEdit.ReleaseAskedTable;
begin
  if FAskTbl <> nil then FAskTbl.Release;
  FAskTbl := nil;
end;

procedure TTyCustomRichEdit.ContentReplaced;
var
  composed: Boolean;
begin
  ReleaseAskedTable;
  { A find of the old content stops: its finder read the old text. Its event is owed to the
    public call that replaced the content (it is raised there, before that call returns;
    CheckReplaceable ended one that ran before it began), never raised from in here. }
  EndFind(rfsCancelled, False);
  // (a replace's end still to be told: the text it ran on is gone, nothing to go on from)
  if FOwedKind = rfkReplace then FOwedTally.ResumeAt := -1;
  { A composition has no text to go into any more: it goes (the whole view is drawn again
    below), and the input method is told to drop it. }
  composed := FComposing or FImeRefused;
  // (Cocoa's session goes on: what it still has marked goes nowhere)
  if composed and FCocoaSession and (FInBridge = 0) then FCocoaSwallow := True;
  FComposing := False;
  FCompText := '';
  FImeRefused := False;
  FCompPending := False;
  FCompBefore := False;
  FLayouter.ClearComposition;
  FText := FDoc.Text;
  FSnapPending := False;
  // (the whole window is invalidated below)
  FSkippedPaint := False;
  ReleaseBlocks;
  ClearPending;
  ClearFailed;
  // the old content's work and report go: LoadAs starts a new load's driver after this
  if not HasBackgroundWork then StopBackground;
  CancelCall(FSelCall);
  FSelInUpdate := False;
  FPosInUpdate := False;
  // told, not recognised: the layouter empties everything it kept
  FLayouter.Document := FDoc;
  FAnchorPara := 0;
  FAnchorOffset := 0;
  FAnchorShareDen := 0;
  FScrollX := 0;
  FWidestSeen := 0;
  FViewValid := False;
  // a new content: the caret at its start, nothing selected, no pending format
  FHasPendingFmt := False;
  FCaret := 0;
  FSelAnchor := 0;
  FCaretAtEnd := False;
  FWishValid := False;
  StopDrag;
  if FLines <> nil then FLines.FEmptyLine := False;
  // the new text has no heights: it gets the estimate before anything asks
  if FEstimate > 0 then FDoc.Text.DefaultParaHeight := FEstimate;
  // everything: the text, and the frame (a bar may come or go with the new content)
  InvalidateSurface;
  FHandleRect := Rect(0, 0, 0, 0);
  FPreviewRect := Rect(0, 0, 0, 0);
  FDropRect := Rect(0, 0, 0, 0);
  InvalidateArea(Rect(0, 0, Width, Height));
  if FViewPPI > 0 then UpdateBars(False);
  if composed then ImeEndOnWidgetset(False);
end;

{ Held blocks the layouter dropped (a list's numbers after a change: the layout's Stale) are laid
  out again: the same shape, only their band is painted again; another shape, the view is laid
  out again from there (above the view: the anchor below holds, only what is above goes). }
procedure TTyCustomRichEdit.RelayStale;
var
  k, m: Integer;
  b: TTyBlockLayout;
begin
  k := 0;
  while k < FBlockCount do
  begin
    if not FBlocks[k].Layout.Stale then
    begin
      Inc(k);
      Continue;
    end;
    if not FViewValid then
    begin
      // the next pass lays it out again: its band is what changes on screen
      InvalidateBand(FBlocks[k].Top, FBlocks[k].Top + FBlocks[k].Height);
      Inc(k);
      Continue;
    end;
    FDoc.BeginRead;
    try
      b := LayoutBlockAt(FBlocks[k].FirstPara);
    finally
      FDoc.EndRead;
    end;
    if (b.FirstPara = FBlocks[k].FirstPara) and (b.LastPara = FBlocks[k].LastPara) and
      (b.Height = FBlocks[k].Height) then
    begin
      FBlocks[k].Layout.Release;
      FBlocks[k].Layout := b;
      InvalidateBand(FBlocks[k].Top, FBlocks[k].Top + FBlocks[k].Height);
      Inc(k);
      Continue;
    end;
    b.Release;
    FViewValid := False;
    if FBlocks[k].Top + FBlocks[k].Height <= 0 then
    begin
      // above the view: it and what is above it go, the rest is kept
      for m := 0 to k do FBlocks[m].Layout.Release;
      for m := k + 1 to FBlockCount - 1 do FBlocks[m - k - 1] := FBlocks[m];
      FBlockCount := FBlockCount - k - 1;
      SetLength(FBlocks, FBlockCount);
      k := 0;
    end
    else
    begin
      InvalidateBand(FBlocks[k].Top, FViewH);
      for m := k to FBlockCount - 1 do FBlocks[m].Layout.Release;
      FBlockCount := k;
      SetLength(FBlocks, FBlockCount);
    end;
  end;
end;

procedure TTyCustomRichEdit.ChangeInView(const AChange: TTyRichChange);
var
  lo, hiOld, delta, k, k0, k1, i, n, p, stop, m: Integer;
  oldTop, oldBottom, y: Int64;
  fresh: array of TTyRichViewBlock;
  b: TTyBlockLayout;
  area: TRect;
  sameHeight, anchorMoved, cut: Boolean;
begin
  area := Rect(0, 0, 0, 0);
  lo := AChange.FirstPara;
  hiOld := lo + Math.Max(AChange.OldParaCount, 1) - 1;
  delta := AChange.NewParaCount - AChange.OldParaCount;
  { The anchor follows its paragraph. One the change took in goes to the change's start: the
    view is laid out again from there (what was on screen is no longer the same blocks) - but
    a change of formats only (the same paragraphs, their text as it was: a column's edge in
    every row of a long table) keeps it at its paragraph's top: that paragraph is still
    there, and the view does not jump to where the change began. }
  anchorMoved := False;
  if FAnchorPara > hiOld then
    Inc(FAnchorPara, delta)
  else if FAnchorPara > lo then
  begin
    if (delta <> 0) or (rckText in AChange.Kinds) then
      // its paragraph is gone: the view starts at the top of what replaced it
      FAnchorPara := lo;
    FAnchorOffset := 0;
    FAnchorShareDen := 0;
    anchorMoved := True;
  end;
  // pictures waiting in changed blocks go (a row's too); the others follow their paragraphs
  k := 0;
  for i := 0 to FPendingCount - 1 do
    if (FPending[i].LastPara >= lo) and (FPending[i].Para <= hiOld) then
      FPending[i].Picture.Release
    else
    begin
      FPending[k] := FPending[i];
      if FPending[k].Para > hiOld then
      begin
        Inc(FPending[k].Para, delta);
        Inc(FPending[k].LastPara, delta);
      end;
      Inc(k);
    end;
  FPendingCount := k;
  if FBlockCount = 0 then
  begin
    if FViewPPI > 0 then UpdateBars(False);
    Exit;
  end;
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  // the view's blocks the change touches
  k0 := -1;
  k1 := -1;
  for k := 0 to FBlockCount - 1 do
    if (FBlocks[k].LastPara >= lo) and (FBlocks[k].FirstPara <= hiOld) then
    begin
      if k0 < 0 then k0 := k;
      k1 := k;
    end;
  // the blocks after the change: their paragraphs move
  for k := 0 to FBlockCount - 1 do
    if FBlocks[k].FirstPara > hiOld then
    begin
      Inc(FBlocks[k].FirstPara, delta);
      Inc(FBlocks[k].LastPara, delta);
    end;
  if not FViewValid then
  begin
    { Laid out again by the next pass, which repaints only what moved: what this change
      touches on screen is painted now, from the first held block it meets down. A change
      above every held block leaves the anchor (and the screen) where it is; one below them
      is off screen. }
    if k0 >= 0 then
      InvalidateBand(FBlocks[k0].Top, FViewH)
    else if anchorMoved then
      InvalidateBand(0, FViewH);
    RelayStale;
    UpdateBars(False);
    Exit;
  end;
  if k0 < 0 then
  begin
    { Not in the view: above it, the blocks keep their places (the anchor holds); below it,
      nothing on screen changes - but numbers after it may have. The changed paragraphs'
      heights are estimates now (a row's: it sits on the row's first paragraph, which the
      change need not have touched) - measured again when laid out, so the scroll range and
      ContentHeight do not keep the height they had before. }
    p := lo;
    m := Math.Min(lo + Math.Max(AChange.NewParaCount, 1) - 1, FDoc.Text.ParaCount - 1);
    // (a load's own slice changes no height: its paragraphs are new, unmeasured)
    if (p >= 0) and (p <= m) and not ((FInStep and FDoc.Loading) or FInCancel) then
    begin
      FDoc.BeginRead;
      try
        if TyRichRowParas(FDoc, p, i, n) then p := i;
        if TyRichRowParas(FDoc, m, i, n) then m := n;
      finally
        FDoc.EndRead;
      end;
      FDoc.Text.UnmeasureParas(p, m);
    end;
    RelayStale;
    UpdateBars(False);
    Exit;
  end;
  if anchorMoved or (FBlocks[k0].FirstPara > lo) then
  begin
    // the change reaches above the blocks the view holds, or across its top: all again
    FViewValid := False;
    InvalidateBand(0, FViewH);
    UpdateBars(False);
    Exit;
  end;
  oldTop := FBlocks[k0].Top;
  oldBottom := FBlocks[k1].Top + FBlocks[k1].Height;
  if oldBottom <= 0 then
  begin
    { Wholly above the view: the anchor below it holds, so nothing on screen moves; the
      blocks down to the change go, and the next pass lays out what is above the view again. }
    for m := 0 to k1 do FBlocks[m].Layout.Release;
    for m := k1 + 1 to FBlockCount - 1 do FBlocks[m - k1 - 1] := FBlocks[m];
    FBlockCount := FBlockCount - k1 - 1;
    SetLength(FBlocks, FBlockCount);
    FViewValid := False;
    RelayStale;
    UpdateBars(False);
    Exit;
  end;
  { The changed blocks laid out again, from the first one's paragraph (it did not move) - as
    far as a screen below the view: a change of many paragraphs lays out no more than a view
    would. }
  p := FBlocks[k0].FirstPara;
  stop := FBlocks[k1].LastPara + delta;
  fresh := nil;
  n := 0;
  y := oldTop;
  cut := False;
  b := nil;
  FDoc.BeginRead;
  try
    try
      while (p <= stop) and (p < FDoc.Text.ParaCount) do
      begin
        if y >= 2 * FViewH then
        begin
          cut := True;
          Break;
        end;
        b := LayoutBlockAt(p);
        if n = Length(fresh) then SetLength(fresh, n * 2 + 4);
        AddBlock(fresh, n, b, y);
        b := nil;
        NoteExtent(fresh[n - 1].Layout);
        Inc(y, fresh[n - 1].Height);
        p := fresh[n - 1].LastPara + 1;
      end;
    except
      if b <> nil then b.Release;
      for k := 0 to n - 1 do fresh[k].Layout.Release;
      FViewValid := False;
      raise;
    end;
  finally
    FDoc.EndRead;
  end;
  sameHeight := not cut and (y = oldBottom) and (n > 0) and (fresh[n - 1].LastPara = stop);
  // the view's list: the blocks before, the fresh ones, the later ones at their new places
  for k := k0 to k1 do FBlocks[k].Layout.Release;
  if cut then
  begin
    // the rest is below what the view keeps: it goes, and the next pass ends the view
    for k := k1 + 1 to FBlockCount - 1 do FBlocks[k].Layout.Release;
    FBlockCount := k0 + n;
    SetLength(FBlocks, FBlockCount);
  end
  else if n <> k1 - k0 + 1 then
  begin
    if n > k1 - k0 + 1 then
    begin
      SetLength(FBlocks, FBlockCount + n - (k1 - k0 + 1));
      for k := FBlockCount - 1 downto k1 + 1 do FBlocks[k + n - (k1 - k0 + 1)] := FBlocks[k];
    end
    else
      for k := k1 + 1 to FBlockCount - 1 do FBlocks[k + n - (k1 - k0 + 1)] := FBlocks[k];
    FBlockCount := FBlockCount + n - (k1 - k0 + 1);
    SetLength(FBlocks, FBlockCount);
  end;
  for k := 0 to n - 1 do FBlocks[k0 + k] := fresh[k];
  if not cut then
    for k := k0 + n to FBlockCount - 1 do Inc(FBlocks[k].Top, y - oldBottom);
  if n > 0 then WriteHeights(k0, k0 + n - 1);
  if sameHeight then
  begin
    // only the changed blocks, as far as they are on screen
    InvalidateBand(oldTop, oldBottom);
  end
  else
  begin
    { The blocks below moved: the window from the change down; on the surface the changed
      blocks are drawn again and what lies below them is moved (a keystroke
      that makes its paragraph a line taller draws that paragraph, not every block under it) -
      and whatever the move does not fill from valid pixels is drawn (MoveSurfaceText's one
      rule: a shorter edit at the view's bottom edge too; a change that reached past the held
      blocks, whose old bottom is two screens down, has nothing on screen to move, and all
      from its new bottom down is drawn). One cut at two screens laid out only part: from the
      change's top down all is drawn again. The next pass lays out what comes. }
    if not cut then
    begin
      MoveSurfaceText(0, y - oldBottom, oldBottom);
      TextRectChanged(-High(Integer), oldTop, High(Integer), y, True, False);
      TextRectChanged(-High(Integer), oldTop, High(Integer), FViewH, False, True);
    end
    else
      InvalidateBand(oldTop, FViewH);
    FViewValid := False;
  end;
  RelayStale;
  UpdateBars(False);
end;

{ ---- scrolling ---- }

function TTyCustomRichEdit.GetScrollY: Int64;
begin
  if ViewBehind then Exit(-1);
  Settle;
  Result := AnchorY div FScale;
end;

procedure TTyCustomRichEdit.SetScrollY(AValue: Int64);
begin
  ScrollRasterTo(AValue * FScale);
  DropFollowPointer;
end;

procedure TTyCustomRichEdit.ScrollViewBy(ADeltaY: Integer);
begin
  ScrollRasterBy(Int64(ADeltaY) * FScale);
end;

procedure TTyCustomRichEdit.ScrollRasterTo(AValue: Int64);
var
  t: TTyRichText;
  i: Integer;
  off: Int64;
begin
  // inside the document's update: no scroll (the heights may be of paragraphs that went)
  if ViewBehind then Exit;
  CheckLayoutParams(ViewPPI);
  t := FDoc.Text;
  if AValue < 0 then AValue := 0;
  if AValue >= t.TotalHeight then
  begin
    ScrollToEnd;
    Exit;
  end;
  i := t.ParaAtHeight(AValue);
  off := AValue - t.ParaTop(i);
  if (i = FAnchorPara) and (off = FAnchorOffset) then Exit;
  FAnchorPara := i;
  FAnchorOffset := off;
  FAnchorShareDen := 0;
  ViewMoved;
end;

procedure TTyCustomRichEdit.ScrollRasterBy(ADeltaY: Int64);
var
  a, last, nSeen: Integer;
  off, maxTop, newY: Int64;
  b: TTyBlockLayout;
  t: TTyRichText;
  walked: array of TTyRichViewBlock;
  h: array of Int64;

  { The heights the walk measured, written once it is over (out of the read scope): the end's
    bound below counts them, not their estimates - after a zoom every height is one. }
  procedure NoteWalked(ABlock: TTyBlockLayout);
  begin
    if nSeen = Length(walked) then SetLength(walked, nSeen * 2 + 8);
    walked[nSeen].FirstPara := ABlock.FirstPara;
    walked[nSeen].LastPara := ABlock.LastPara;
    walked[nSeen].Height := ABlock.Height;
    Inc(nSeen);
  end;

  procedure WriteWalked;
  var
    i, j: Integer;
  begin
    for i := 0 to nSeen - 1 do
    begin
      SetLength(h, walked[i].LastPara - walked[i].FirstPara + 1);
      for j := 0 to High(h) do h[j] := 0;
      h[0] := walked[i].Height;
      t.SetParaHeights(walked[i].FirstPara, h);
    end;
    nSeen := 0;
  end;

begin
  if (ADeltaY = 0) or ViewBehind then Exit;
  // (a drag of a handle is measured in the view it began in)
  CancelResize;
  CheckLayoutParams(ViewPPI);
  t := FDoc.Text;
  walked := nil;
  h := nil;
  nSeen := 0;
  if FAnchorShareDen > 0 then
  begin
    { A zoom (a PPI, a width) since the last layout: the anchor's offset is a share of its
      block until it is laid out again - at the new parameters, here, before the walk starts
      from it (the share a zoom keeps, which the walk would otherwise drop). }
    FDoc.BeginRead;
    try
      b := LayoutBlockAt(Math.Min(FAnchorPara, t.ParaCount - 1));
      try
        if b.FirstPara <> FAnchorPara then
        begin
          FAnchorOffset := t.ParaTop(FAnchorPara) - t.ParaTop(b.FirstPara) + FAnchorOffset;
          FAnchorPara := b.FirstPara;
        end;
        // (its height: the walk below lays it out first and writes it)
        ApplyAnchorShare(b);
      finally
        b.Release;
      end;
    finally
      FDoc.EndRead;
    end;
  end;
  // a jump of many screens is a position, not a walk over every block between
  if Abs(ADeltaY) > 4 * Int64(Math.Max(FViewH, 1)) then
  begin
    ScrollRasterTo(AnchorY + ADeltaY);
    Exit;
  end;
  last := t.ParaCount - 1;
  a := Math.Min(FAnchorPara, last);
  off := FAnchorOffset + ADeltaY;
  FDoc.BeginRead;
  try
    if off >= 0 then
    begin
      // down, block by block (only the blocks passed over are laid out)
      repeat
        b := LayoutBlockAt(a);
        try
          if a <> b.FirstPara then
          begin
            Inc(off, t.ParaTop(a) - t.ParaTop(b.FirstPara));
            a := b.FirstPara;
          end;
          NoteWalked(b);
          if (off < b.Height) or (b.LastPara >= last) then Break;
          Dec(off, b.Height);
          a := b.LastPara + 1;
        finally
          b.Release;
        end;
      until False;
    end
    else
      while off < 0 do
      begin
        if a <= 0 then
        begin
          off := 0;
          Break;
        end;
        b := LayoutBlockAt(a - 1);
        try
          NoteWalked(b);
          a := b.FirstPara;
          Inc(off, b.Height);
        finally
          b.Release;
        end;
      end;
  finally
    FDoc.EndRead;
  end;
  WriteWalked;
  if ADeltaY > 0 then
  begin
    // against the end: no further than the last line at the bottom
    maxTop := Math.Max(Int64(0), t.TotalHeight - FViewH);
    newY := t.ParaTop(a) + off;
    if newY > maxTop then
    begin
      if AnchorY >= maxTop then Exit;
      a := t.ParaAtHeight(maxTop);
      off := maxTop - t.ParaTop(a);
    end;
  end;
  if (a = FAnchorPara) and (off = FAnchorOffset) then Exit;
  FAnchorPara := a;
  FAnchorOffset := off;
  FAnchorShareDen := 0;
  ViewMoved;
end;

procedure TTyCustomRichEdit.ScrollToTop;
begin
  if (FAnchorPara = 0) and (FAnchorOffset = 0) then Exit;
  FAnchorPara := 0;
  FAnchorOffset := 0;
  FAnchorShareDen := 0;
  ViewMoved;
  DropFollowPointer;
end;

procedure TTyCustomRichEdit.ScrollToEnd;
var
  t: TTyRichText;
  p, n, k, a, first: Integer;
  total, off: Int64;
  b: TTyBlockLayout;
  firsts, lasts, heights: array of Integer;
  h: array of Int64;
begin
  if ViewBehind then Exit;
  CheckLayoutParams(ViewPPI);
  t := FDoc.Text;
  { The last screen's blocks, from the end up: their heights are written, so the anchor found
    is exact - no marker waits for the next layout to say where the end is. }
  firsts := nil;
  lasts := nil;
  heights := nil;
  n := 0;
  total := 0;
  p := t.ParaCount - 1;
  FDoc.BeginRead;
  try
    while p >= 0 do
    begin
      b := LayoutBlockAt(p);
      if n = Length(firsts) then
      begin
        SetLength(firsts, n * 2 + 8);
        SetLength(lasts, n * 2 + 8);
        SetLength(heights, n * 2 + 8);
      end;
      firsts[n] := b.FirstPara;
      lasts[n] := b.LastPara;
      heights[n] := b.Height;
      Inc(n);
      Inc(total, b.Height);
      p := b.FirstPara - 1;
      b.Release;
      if total >= FViewH then Break;
    end;
  finally
    FDoc.EndRead;
  end;
  if n > 0 then
  begin
    first := firsts[n - 1];
    SetLength(h, lasts[0] - first + 1);
    for k := 0 to High(h) do h[k] := 0;
    for k := 0 to n - 1 do h[firsts[k] - first] := heights[k];
    t.SetParaHeights(first, h);
  end;
  if (n = 0) or (total <= FViewH) then
  begin
    // the whole document fits (or the view has no height): its top
    a := 0;
    off := 0;
    if (n > 0) and (p >= 0) then a := firsts[n - 1];
  end
  else
  begin
    a := firsts[n - 1];
    off := total - FViewH;
  end;
  if (a = FAnchorPara) and (off = FAnchorOffset) then Exit;
  FAnchorPara := a;
  FAnchorOffset := off;
  FAnchorShareDen := 0;
  ViewMoved;
end;

{ The view moves: the window's text is painted again; the surface is moved (or dirtied) by
  the layout pass, which knows by how much. }
procedure TTyCustomRichEdit.ViewMoved;
begin
  // (a drag of a handle is measured in the view it began in)
  CancelResize;
  FViewValid := False;
  if FViewPPI > 0 then
    InvalidateArea(TextWindowRect)
  else
    InvalidateArea(Rect(0, 0, Width, Height));
end;

procedure TTyCustomRichEdit.UpdateView;
begin
  if ViewBehind then Exit;
  EnsureView(Font.PixelsPerInch);
  // the application's call: what the content needs is reported now (OnContentSizeChange)
  CheckContentSize(False);
end;

procedure TTyCustomRichEdit.EnsureView(APPI: Integer);
var
  pass: Integer;
begin
  { The bars are decided first from the heights as they are (estimates included): a bar that
    came after the layout would change the width and have it all laid out a second time. A
    decision a layout made (measured heights) holds for the rest of this call: the width it
    changes makes the heights estimates again, and they must not take it back - a bar shown
    because the text overflowed stays, one hidden because it fits at the narrower width stays
    hidden (it fits wider too). So it settles in at most three layouts. }
  FLatchV := 0;
  FLatchH := 0;
  try
    for pass := 1 to 4 do
    begin
      CheckLayoutParams(APPI);
      if UpdateBars(False) then Continue;
      if FViewValid then Break;
      LayoutView;
      // what the layout found (a wide block, corrected heights) may still want a bar
      if not UpdateBars(True) then Break;
    end;
    if not FViewValid then
    begin
      CheckLayoutParams(APPI);
      LayoutView;
    end;
  finally
    FLatchV := 0;
    FLatchH := 0;
  end;
  ParagraphViewChanged;
  // (a paint's view among them: what the content now needs is looked at after it)
  CheckContentSize(True);
end;

procedure TTyCustomRichEdit.ClampScrollX;
var
  hMax: Integer;
begin
  hMax := Math.Max(0, FWidestSeen - FViewW);
  if FScrollX > hMax then FScrollX := hMax;
  if FScrollX < 0 then FScrollX := 0;
end;

{ ---- scroll bars ---- }

function TTyCustomRichEdit.ScrollBarSize(APPI: Integer): Integer;
begin
  Result := MulDiv(StyleMetric('--scrollbar-size', TyScrollbarSize), APPI, 96);
end;

function TTyCustomRichEdit.ViewPPI: Integer;
begin
  if FViewPPI > 0 then Result := FViewPPI else Result := Font.PixelsPerInch;
  if Result <= 0 then Result := 96;
end;

function TTyCustomRichEdit.VBarShown: Boolean;
begin
  Result := (FVBar <> nil) and FVBar.Visible;
end;

function TTyCustomRichEdit.HBarShown: Boolean;
begin
  Result := (FHBar <> nil) and FHBar.Visible;
end;

function TTyCustomRichEdit.TextArea(const ARect: TRect; APPI: Integer): TRect;
var
  s: TTyStyleSet;
  sbw: Integer;
begin
  s := CurrentStyle;
  Result := Rect(ARect.Left + MulDiv(s.Padding.Left, APPI, 96),
    ARect.Top + MulDiv(s.Padding.Top, APPI, 96),
    ARect.Right - MulDiv(s.Padding.Right, APPI, 96),
    ARect.Bottom - MulDiv(s.Padding.Bottom, APPI, 96));
  sbw := ScrollBarSize(APPI);
  if VBarShown then
  begin
    // a right-to-left control has its bar on the left (its text stays left to right)
    if IsRightToLeft then
      Result.Left := Math.Max(Result.Left, ARect.Left + sbw)
    else
      Result.Right := Math.Min(Result.Right, ARect.Right - sbw);
  end;
  if HBarShown then Result.Bottom := Math.Min(Result.Bottom, ARect.Bottom - sbw);
  if Result.Right < Result.Left then Result.Right := Result.Left;
  if Result.Bottom < Result.Top then Result.Bottom := Result.Top;
end;

procedure TTyCustomRichEdit.PlaceBars;
var
  sbw, vw, hh: Integer;
begin
  sbw := ScrollBarSize(ViewPPI);
  if VBarShown then vw := sbw else vw := 0;
  if HBarShown then hh := sbw else hh := 0;
  if VBarShown then
  begin
    if IsRightToLeft then FVBar.SetBounds(0, 0, sbw, Height - hh)
    else FVBar.SetBounds(Width - sbw, 0, sbw, Height - hh);
  end;
  if HBarShown then
  begin
    if IsRightToLeft then FHBar.SetBounds(vw, Height - sbw, Width - vw, sbw)
    else FHBar.SetBounds(0, Height - sbw, Width - vw, sbw);
  end;
end;

function NewBar(AOwner: TTyCustomRichEdit; AKind: TTyScrollBarKind; AOnChange: TNotifyEvent;
  AAutoHide: TTyScrollBarAutoHide): TTyScrollBar;
begin
  Result := TTyScrollBar.Create(AOwner);
  Result.Kind := AKind;
  Result.Align := alNone;
  // embedded: never takes the focus from the control it scrolls
  Result.TabStop := False;
  Result.AnimationsEnabled := False;
  Result.AutoHide := AAutoHide;
  Result.ControlStyle := Result.ControlStyle + [csNoDesignVisible];
  Result.Visible := False;
  Result.Parent := AOwner;
  Result.OnChange := AOnChange;
end;

{ Shows or hides the bars and sets their ranges. True when a bar came or went (the text area
  changed: the view must be laid out again). }
function TTyCustomRichEdit.UpdateBars(AMeasured: Boolean): Boolean;

  function Decide(ARaw: Boolean; var ALatch: Integer): Boolean;
  begin
    if AMeasured then
    begin
      // what a layout found: kept for the rest of the EnsureView (a shown bar for good)
      if ARaw then ALatch := 2
      else if ALatch <> 2 then ALatch := 1;
    end;
    case ALatch of
      1: Result := False;
      2: Result := True;
    else
      Result := ARaw;
    end;
  end;

var
  total, topY, maxTop, scale: Int64;
  wantV, wantH, showV, showH: Boolean;
  page, viewH: Integer;
begin
  wantV := Decide((FDoc.Text.TotalHeight > FViewH) or (AnchorY > 0), FLatchV);
  wantH := Decide(FWidestSeen > FViewW, FLatchH);
  // the bars count client pixels
  total := FDoc.Text.TotalHeight div FScale;
  topY := AnchorY div FScale;
  viewH := FViewH div FScale;
  // what may show (ScrollBars, AutoHeight); a hidden one's scrolling goes on all the same
  showV := wantV and BarAllowed(True);
  showH := wantH and BarAllowed(False);
  Result := (showV <> VBarShown) or (showH <> HBarShown);
  { A load's own slice (FBarsLazy) that brings no bar and takes none away: the widgets get its
    range at the end of a turn, at most once per CRichLoadBarsMs of the turns' clock
    (BackgroundTurn); CatchUpBars gives them the rest when the load ends, and any call of this
    that is not such a slice gives them everything at once. What the control works with - the
    document's height, the anchor, the clamps - is read from the document, never from a bar;
    FBarScale is the scale the vertical bar was last given, the one its positions are in. }
  if FBarsLazy and not Result then
  begin
    // the turn decides at its end (BackgroundTurn)
    FBarsBehind := True;
    // (the control's own value, as below)
    if wantH then ClampScrollX else FScrollX := 0;
    Exit;
  end;
  FBarsBehind := False;
  if showV and (FVBar = nil) then FVBar := NewBar(Self, sbVertical, @VBarChange, FScrollBarAutoHide);
  if showH and (FHBar = nil) then FHBar := NewBar(Self, sbHorizontal, @HBarChange, FScrollBarAutoHide);
  if FVBar <> nil then FVBar.Visible := showV;
  if FHBar <> nil then FHBar.Visible := showH;
  if Result then
  begin
    // the text area changed: the frame (its bands) and the text are drawn again
    FViewValid := False;
    InvalidateSurface;
    InvalidateArea(Rect(0, 0, Width, Height));
  end;
  PlaceBars;
  FSyncingBars := True;
  try
    if showV then
    begin
      FVBar.Controller := Controller;
      maxTop := Math.Max(Int64(0), total - viewH);
      { The bar's range is an Integer: a taller document is scrolled ScrollBarLimit units for
        its whole height, each unit FBarScale pixels; the last unit is the end, whatever the
        rounding. }
      scale := 1 + (maxTop + viewH) div ScrollBarLimit;
      FBarScale := scale;
      page := Math.Max(1, viewH div scale);
      FVBar.Min := 0;
      FVBar.Max := maxTop div scale;
      FVBar.PageSize := page;
      FVBar.SmallChange := Math.Max(1, FEstimate div FScale div scale);
      FVBar.LargeChange := page;
      if topY >= maxTop then FVBar.Position := FVBar.Max
      else FVBar.Position := topY div scale;
    end;
    if showH then
    begin
      FHBar.Controller := Controller;
      ClampScrollX;
      FHBar.Min := 0;
      FHBar.Max := Math.Max(0, FWidestSeen - FViewW) div FScale;
      FHBar.PageSize := Math.Max(1, FViewW div FScale);
      FHBar.SmallChange := Math.Max(1, FEstimate div FScale);
      FHBar.Position := FScrollX div FScale;
    end
    else if wantH then
      // no bar shown, something to scroll all the same (ScrollBars)
      ClampScrollX
    else
      FScrollX := 0;
  finally
    FSyncingBars := False;
  end;
end;

procedure TTyCustomRichEdit.VBarChange(Sender: TObject);
begin
  if FSyncingBars then Exit;
  if FVBar.Position >= FVBar.Max then
    ScrollToEnd
  else
    SetScrollY(Int64(FVBar.Position) * FBarScale);
  DropFollowPointer;
end;

procedure TTyCustomRichEdit.HBarChange(Sender: TObject);
var
  was: Integer;
begin
  if FSyncingBars then Exit;
  was := FScrollX;
  FScrollX := FHBar.Position * FScale;
  ClampScrollX;
  if FScrollX = was then Exit;
  CancelResize;
  MoveSurfaceText(was - FScrollX, 0);
  InvalidateArea(TextWindowRect);
  DropFollowPointer;
end;

{ ---- painting ---- }

procedure TTyCustomRichEdit.FillPaintStyle(var AStyle: TTyRichPaintStyle);
var
  s, part: TTyStyleSet;
  model: TTyStyleModel;
  states: TTyStateSet;
  c: TTyColor;
begin
  AStyle := TyRichDefaultPaintStyle;
  s := CurrentStyle;
  if tpTextColor in s.Present then AStyle.TextColor := TyColorToBGRA(s.TextColor);
  model := ActiveController.Model;
  if tysFocused in CurrentStates then states := [tysFocused] else states := [];
  part := model.ResolveStyle('TyRichEditSelection', StyleClass, states);
  if tpBackground in part.Present then AStyle.SelectionBack := TyColorToBGRA(part.Background.Color);
  if tpTextColor in part.Present then
    AStyle.SelectionText := TyColorToBGRA(part.TextColor)
  else
    AStyle.SelectionText := AStyle.TextColor;
  part := model.ResolveStyle('TyRichEditObject', StyleClass, []);
  if tpBorderColor in part.Present then AStyle.ObjectFrame := TyColorToBGRA(part.BorderColor);
  // the handles' fill
  if tpBackground in part.Present then
    AStyle.ObjectHandleFill := TyColorToBGRA(part.Background.Color);
  part := model.ResolveStyle('TyRichEditPlaceholder', StyleClass, []);
  if tpBackground in part.Present then
    AStyle.PlaceholderFill := TyColorToBGRA(part.Background.Color);
  if tpBorderColor in part.Present then
    AStyle.PlaceholderFrame := TyColorToBGRA(part.BorderColor);
  // an input method's composition: its underline (none in the theme: the text's colour)
  part := model.ResolveStyle('TyRichEditComposition', StyleClass, []);
  if tpBorderColor in part.Present then
    AStyle.CompositionLine := TyColorToBGRA(part.BorderColor);
  { #225: the parts are resolved from the theme; a '--' token the control's own StyleOverride
    sets for what their rules read reaches them too. }
  if OwnStyleColor('--on-surface', c) then AStyle.CompositionLine := TyColorToBGRA(c);
  if OwnStyleColor('--selection', c) then AStyle.SelectionBack := TyColorToBGRA(c);
  if OwnStyleColor('--accent', c) then AStyle.ObjectFrame := TyColorToBGRA(c);
  if OwnStyleColor('--surface', c) then AStyle.ObjectHandleFill := TyColorToBGRA(c);
  if OwnStyleColor('--surface-sunk', c) then AStyle.PlaceholderFill := TyColorToBGRA(c);
  if OwnStyleColor('--border', c) then AStyle.PlaceholderFrame := TyColorToBGRA(c);
  AStyle.TableBorder := AStyle.TextColor;
  // the document's own ground, drawn as it is: automatic text over it contrasts with it
  if FDoc.DocumentColor <> clNone then
  begin
    AStyle.HasGround := True;
    AStyle.Ground := FDoc.DocumentColor;
  end;
  { A link's automatic text: the package's link colour (the link label's key), a '--accent'
    of the control's own StyleOverride too; none in the theme: the text colour. }
  part := model.ResolveStyle('TyLinkLabelLink', StyleClass, []);
  if tpTextColor in part.Present then AStyle.LinkColor := TyColorToBGRA(part.TextColor);
  if OwnStyleColor('--accent', c) then AStyle.LinkColor := TyColorToBGRA(c);
end;

procedure TTyCustomRichEdit.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  PaintArea(ACanvas, ARect, ARect, APPI, False);
end;

procedure TTyCustomRichEdit.Paint;
begin
  PaintArea(Canvas, Rect(0, 0, Width, Height), Canvas.ClipRect, Font.PixelsPerInch, True);
  // over the blit: never on the surface, so a blink or a click costs no text drawn
  DrawCaret(Canvas);
  DrawGuideLine(Canvas);
end;

procedure TTyCustomRichEdit.PointerStateChanged;
begin
  { The base repaints the whole control for every press, release, hover and focus change.
    What a state changes on screen reaches FrameSignature through the style it resolves to:
    the same signature, nothing to paint (the selection colour that follows the focus is in it
    too). The surface itself notices a changed one at the next paint. }
  if FFrameSigValid and SurfaceUsable(CurrentStyle) and
    (FrameSignature(FFrameSigPPI) = FFrameSig) then Exit;
  inherited PointerStateChanged;
end;

procedure TTyCustomRichEdit.Resize;
begin
  inherited Resize;
  FViewValid := False;
  if FViewPPI > 0 then PlaceBars;
  DropFollowPointer;
end;

{ ---- points and positions ---- }

{ One implementation of point -> position and position -> rectangle: the control's own
  moves, clicks and caret go through these too (HitRaster, CaretRaster, with the affinity). }
function TTyCustomRichEdit.PositionAtPoint(X, Y: Integer): TTyRichPos;
var
  atEnd: Boolean;
begin
  Result := PositionAtPoint(X, Y, atEnd);
end;

function TTyCustomRichEdit.PositionAtPoint(X, Y: Integer; out AAtLineEnd: Boolean): TTyRichPos;
var
  area: TRect;
begin
  AAtLineEnd := False;
  if ViewBehind then Exit(-1);
  Settle;
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  Result := HitRaster((Int64(X) - area.Left) * FScale + FScrollX, (Int64(Y) - area.Top) * FScale,
    AAtLineEnd);
  // (anywhere in a span: the cell it starts with)
  if (Result >= 0) and CoveredPara(FDoc.Text.ParaOfPos(Result)) then
  begin
    Result := SpanOwnerPos(Result);
    AAtLineEnd := False;
  end;
end;

function TTyCustomRichEdit.PositionRect(APos: TTyRichPos; AAtLineEnd: Boolean): TRect;
var
  area, r: TRect;
begin
  Result := Rect(0, 0, 0, 0);
  if ViewBehind then Exit;
  Settle;
  if (APos < 0) or (APos > FDoc.Text.Length) then Exit;
  if not CaretRaster(APos, AAtLineEnd, r) then Exit;
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  Result := ClientOf(area, r.Left, r.Top, r.Right, r.Bottom);
end;

function TTyCustomRichEdit.ParagraphRect(AIndex: Integer): TRect;
var
  area: TRect;
  k: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if ViewBehind then Exit;
  Settle;
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  for k := 0 to FBlockCount - 1 do
    if (AIndex >= FBlocks[k].FirstPara) and (AIndex <= FBlocks[k].LastPara) then
    begin
      Result := ClientOf(area, 0, FBlocks[k].Top, 0, FBlocks[k].Top + FBlocks[k].Height);
      Result.Right := area.Right;
      Exit;
    end;
end;

{ ---- pictures made ready in the background ---- }

procedure TTyCustomRichEdit.QueuePicture(APicture: TTyRichPicture; AWidth, AHeight, APara,
  ALastPara: Integer; AHeld: Boolean);
var
  i: Integer;
begin
  { Once is enough (a view laid out again meets the same pictures, a picture may be in two
    places); and not a (picture, size) whose preparing raised. Nothing else needs keeping out:
    after PreparePicture the layouter calls the picture ready at that size - made ready, or
    known to be a placeholder - so a paint never meets it as not ready again unless the
    layouter let it go (a zoom there and back, the cache's trim), and then it must be queued. }
  if FailedIndex(APicture, AWidth, AHeight) >= 0 then
  begin
    if AHeld then APicture.Release;
    Exit;
  end;
  for i := 0 to FPendingCount - 1 do
    if (FPending[i].Picture = APicture) and (FPending[i].Width = AWidth) and
      (FPending[i].Height = AHeight) then
    begin
      if AHeld then APicture.Release;
      Exit;
    end;
  if FPendingCount = Length(FPending) then SetLength(FPending, FPendingCount * 2 + 8);
  if not AHeld then APicture.AddRef;
  FPending[FPendingCount].Picture := APicture;
  FPending[FPendingCount].Width := AWidth;
  FPending[FPendingCount].Height := AHeight;
  FPending[FPendingCount].Para := APara;
  FPending[FPendingCount].LastPara := ALastPara;
  Inc(FPendingCount);
end;

type
  TTyRichPictureVisit = procedure(APicture: TTyRichPicture; const ABox: TRect; ABlock: Integer)
    of object;

{ Every picture box of held block k, in the block's pixels. }
procedure VisitPictures(ALayout: TTyBlockLayout; ABlock: Integer; AVisit: TTyRichPictureVisit);

  procedure FromPara(L: TTyParaLayout; AX, AY: Integer);
  var
    i, j: Integer;
    ln: TTyRichLine;
    f: TTyRichFragment;
    pic: TTyRichPicture;
  begin
    for i := 0 to L.LineCount - 1 do
    begin
      ln := L.Lines[i];
      for j := ln.FirstFrag to ln.FirstFrag + ln.FragCount - 1 do
      begin
        f := L.Fragments[j];
        if f.Kind <> rfkObject then Continue;
        // a picture, or the one a block of kept RTF is shown as
        pic := TyRichShownPicture(f.Obj);
        if pic = nil then Continue;
        AVisit(pic, Rect(AX + f.X, AY + ln.Baseline - f.Ascent,
          AX + f.X + f.Width, AY + ln.Baseline + f.Descent), ABlock);
      end;
    end;
  end;

var
  i: Integer;
  row: TTyRowLayout;
begin
  if ALayout is TTyParaLayout then
    FromPara(TTyParaLayout(ALayout), 0, 0)
  else if ALayout is TTyRowLayout then
  begin
    row := TTyRowLayout(ALayout);
    for i := 0 to row.ItemCount - 1 do
      FromPara(row.Items[i].Layout, row.Items[i].X, row.Items[i].Y);
  end;
end;

type
  { The two walks over the held blocks' pictures. }
  TTyRichPictureWalk = class
    Owner: TTyCustomRichEdit;
    Picture: TTyRichPicture;
    Width, Height: Integer;
    procedure Ahead(APicture: TTyRichPicture; const ABox: TRect; ABlock: Integer);
    procedure Ready(APicture: TTyRichPicture; const ABox: TRect; ABlock: Integer);
  end;

procedure TTyRichPictureWalk.Ahead(APicture: TTyRichPicture; const ABox: TRect; ABlock: Integer);
var
  w, h: Integer;
begin
  w := ABox.Right - ABox.Left;
  h := ABox.Bottom - ABox.Top;
  if not Owner.FLayouter.PictureReady(APicture, w, h) then
    Owner.QueuePicture(APicture, w, h, Owner.FBlocks[ABlock].FirstPara,
      Owner.FBlocks[ABlock].LastPara, False);
end;

procedure TTyRichPictureWalk.Ready(APicture: TTyRichPicture; const ABox: TRect; ABlock: Integer);
var
  top: Int64;
begin
  if (APicture <> Picture) or (ABox.Right - ABox.Left <> Width) or
    (ABox.Bottom - ABox.Top <> Height) then Exit;
  top := Owner.FBlocks[ABlock].Top;
  Owner.InvalidateTextRect(ABox.Left - Owner.FScrollX, top + ABox.Top,
    ABox.Right - Owner.FScrollX, top + ABox.Bottom);
end;

{ The pictures of the blocks laid out off screen (a screen ahead and behind) that are not ready
  at their size: made ready in the background, so they are when they scroll in. }
procedure TTyCustomRichEdit.QueuePicturesAhead;
var
  k: Integer;
  walk: TTyRichPictureWalk;
begin
  walk := TTyRichPictureWalk.Create;
  try
    walk.Owner := Self;
    for k := 0 to FBlockCount - 1 do
    begin
      if (FBlocks[k].Top < FViewH) and (FBlocks[k].Top + FBlocks[k].Height > 0) then Continue;
      VisitPictures(FBlocks[k].Layout, k, @walk.Ahead);
    end;
  finally
    walk.Free;
  end;
  if FPendingCount > 0 then StartBackground;
end;

{ A picture made ready at a size: every box it has at that size in the view is painted again
  (a picture may be in two places), nothing else. }
procedure TTyCustomRichEdit.InvalidatePicture(APicture: TTyRichPicture; AWidth, AHeight: Integer);
var
  k: Integer;
  walk: TTyRichPictureWalk;
begin
  walk := TTyRichPictureWalk.Create;
  try
    walk.Owner := Self;
    walk.Picture := APicture;
    walk.Width := AWidth;
    walk.Height := AHeight;
    for k := 0 to FBlockCount - 1 do
      if (FBlocks[k].Top < FViewH) and (FBlocks[k].Top + FBlocks[k].Height > 0) then
        VisitPictures(FBlocks[k].Layout, k, @walk.Ready);
  finally
    walk.Free;
  end;
end;

function TTyCustomRichEdit.HasBackgroundWork: Boolean;
begin
  Result := (FPendingCount > 0) or (FDoc.Loading and (TyRichRtfLoadOf(FDoc) <> nil)) or
    ((FFindKind <> rfkNone) and not FindBlocked);
end;

function TTyCustomRichEdit.StepBackground: Boolean;
var
  load: TTyRtfLoad;
  pic: TTyRichPendingPicture;
  before: Int64;
begin
  Result := False;
  // re-entered from a progress handler (one that pumps messages): the step is running
  if FInStep or (FSaving > 0) then Exit;
  { A find goes before the load's slices: it searches what is indexed, and when it has reached
    that while the file still loads it waits (FindReady False), and the slices go on. }
  if (FFindKind <> rfkNone) and not FindBlocked then
  begin
    FindPiece;
    Exit(True);
  end;
  load := TyRichRtfLoadOf(FDoc);
  if FDoc.Loading and (load <> nil) then
  begin
    load.OnLoadProgress := @LoadProgress;
    before := load.BytesIndexed;
    FInStep := True;
    try
      load.Step(SliceBytes);
      if TyRichRtfLoadOf(FDoc) = load then Inc(FTurnBytes, load.BytesIndexed - before);
    except
      FInStep := False;
      { A slice that indexed nothing would raise the same again, every turn: the load
        stops there. One that got further raised in a handler of its progress or its change
        (the load's state is whole: what was indexed is appended first): it goes on. }
      if (TyRichRtfLoadOf(FDoc) = load) and FDoc.Loading and (load.BytesIndexed = before) then
        CancelLoad;
      raise;
    end;
    FInStep := False;
    // the load's end: the bars get what its last turns held back
    if not FDoc.Loading then CatchUpBars;
    if FCancelRequested then CancelLoad;
    Exit(True);
  end;
  if FPendingCount = 0 then Exit;
  pic := FPending[0];
  Dec(FPendingCount);
  if FPendingCount > 0 then Move(FPending[1], FPending[0], FPendingCount * SizeOf(FPending[0]));
  try
    if not FLayouter.PictureReady(pic.Picture, pic.Width, pic.Height) then
    begin
      { Noted as failed BEFORE the call: a fatal error out of it (out of memory, an access
        violation - the layouter lets those through) leaves the picture not ready, and a
        paint would queue it again and again. A call that returns takes the note back. The
        reference the queue held goes to the note. }
      if FFailedCount = Length(FFailed) then SetLength(FFailed, FFailedCount * 2 + 4);
      FFailed[FFailedCount] := pic;
      Inc(FFailedCount);
      pic.Picture := nil;
      FLayouter.PreparePicture(FFailed[FFailedCount - 1].Picture, pic.Width, pic.Height);
      Dec(FFailedCount);
      pic.Picture := FFailed[FFailedCount].Picture;
      // its boxes in the view: nothing else is painted again
      InvalidatePicture(pic.Picture, pic.Width, pic.Height);
    end;
  finally
    if pic.Picture <> nil then pic.Picture.Release;
  end;
  Result := True;
end;

{ The driver on. rtdIdle: the idle handler registered; when it was not, the first turn
  is queued too, because a start from code the idle step itself runs after the handlers (an
  action's update, a later idle handler) would otherwise wait for the next message - this is
  a start, not a turn queuing the next: inside a turn nothing is queued. rtdTimer: the timer
  enabled (made on the first start). }
procedure TTyCustomRichEdit.StartBackground;
var
  first: Boolean;
begin
  // a turn only for a control on screen: one without a window waits for FinishLoading or
  // its first paint (InitializeWnd starts it); in the form designer none at all (a form
  // file holds no content: nothing there loads)
  if not HandleAllocated or ([csDestroying, csDesigning] * ComponentState <> []) or
    SchedulingClosed then Exit;
  try
    if TurnDriver = rtdIdle then
    begin
      if FIdleOn then Exit;
      first := not FInTurn;
      FIdleOn := True;
      WatchIdle(True);
      if FBackstop = nil then
      begin
        FBackstop := TTimer.Create(nil);
        FBackstop.Enabled := False;
        FBackstop.Interval := CRichBackstopMs;
        FBackstop.OnTimer := @BackstopTick;
      end;
      FBackstopSeen := FTurnsRun;
      FBackstop.Enabled := True;
      if first then ScheduleCall(FStepCall);
    end
    else
    begin
      if FTurnTimer = nil then
      begin
        FTurnTimer := TTimer.Create(nil);
        FTurnTimer.Interval := 1;
        FTurnTimer.OnTimer := @TurnTimerTick;
      end;
      FTurnTimer.Enabled := True;
    end;
  except
    SchedulingFailed;
  end;
end;

{ What will not schedule ends the background work here; nothing escapes into the load, the turn
  or the idle step that asked. An application that shuts down: quietly, the document as far as
  it was read (Loading; FinishLoading reads the rest, a new window starts the driver again).
  Anything else (in practice: out of memory) would leave the load Loading with nothing to
  drive it: it ends as a cancel ends it - Incomplete, with the load's own notice.
  That cancel is not run here: this is reached from the end of a paint, the tail of a layout
  pass (QueuePicturesAhead) and InitializeWnd, where the view must not hear a document notice.
  It is owed (FLoadEndOwed), and EndOwedLoad runs it at the next entry point of the loop: the
  idle step (rtdIdle: the handler is registered again for it - a registration is no queued
  call), a turn, a key or a mouse press; LoadAs and the idle step, which are such entry points
  themselves, run it before they return. It runs under no handler of ours: an exception from a
  user's change handler reaches the caller as from a user's own cancel. }
procedure TTyCustomRichEdit.SchedulingFailed;
begin
  // the driver's own calls only (no user code): what fails here was failing already
  try
    StopBackground;
  except
  end;
  if SchedulingClosed or not FDoc.Loading or (TyRichRtfLoadOf(FDoc) = nil) then Exit;
  FLoadEndOwed := True;
  if (TurnDriver = rtdIdle) and not FIdleOn then
  try
    WatchIdle(True);
    FIdleOn := True;
  except
  end;
end;

procedure TTyCustomRichEdit.EndOwedLoad;
begin
  if not FLoadEndOwed then Exit;
  FLoadEndOwed := False;
  if FDoc.Loading and (TyRichRtfLoadOf(FDoc) <> nil) then CancelLoad;
end;

{ The bars get the range the load's turns held back. }
procedure TTyCustomRichEdit.CatchUpBars;
begin
  if not FBarsBehind then Exit;
  FBarsBehind := False;
  if FViewPPI > 0 then UpdateBars(False);
end;

procedure TTyCustomRichEdit.StopBackground;
begin
  if FIdleOn then
  begin
    FIdleOn := False;
    WatchIdle(False);
  end;
  CancelCall(FStepCall);
  if FTurnTimer <> nil then FTurnTimer.Enabled := False;
  if FBackstop <> nil then FBackstop.Enabled := False;
end;

function TTyCustomRichEdit.SchedulingClosed: Boolean;
begin
  { TApplication.Destroy sets AppDestroying first, frees its handler lists, then sets
    AppDoNotCallAsyncQueue (QueueAsyncCall and RemoveAsyncCalls raise from there on) and runs
    the queue one last time; a control the application does not own may get its turn there. }
  Result := (Application = nil) or
    ([AppDestroying, AppDoNotCallAsyncQueue] * Application.Flags <> []);
end;

function TTyCustomRichEdit.TurnDriver: TTyRichTurnDriver;
begin
  if WidgetSet = nil then Exit(rtdTimer);
  Result := TyRichTurnDriverFor(WidgetSet.LCLPlatform);
end;

procedure TTyCustomRichEdit.ScheduleCall(ACall: TTyRichQueuedCall);
begin
  // (the destructor frees the calls before the window goes; the form designer runs none)
  if (ACall = nil) or ACall.FQueued or ([csDestroying, csDesigning] * ComponentState <> []) or
    SchedulingClosed then
    Exit;
  ACall.FQueued := True;
  try
    PostCall(ACall);
  except
    { Nothing was queued; the error does not travel on into a paint, a turn or a step. The
      background work: see SchedulingFailed. A selection report: the next user action reports
      the move with its own report at its end (DoSelectionChange compares with what was last
      reported), as when no loop runs the queue. }
    ACall.FQueued := False;
    if ACall = FStepCall then SchedulingFailed;
  end;
end;

procedure TTyCustomRichEdit.CancelCall(ACall: TTyRichQueuedCall);
begin
  if (ACall = nil) or not ACall.FQueued then Exit;
  ACall.FQueued := False;
  RemovePostedCall(ACall);
end;

procedure TTyCustomRichEdit.PostCall(ACall: TTyRichQueuedCall);
begin
  if Application = nil then
  begin
    ACall.FQueued := False;
    Exit;
  end;
  Application.QueueAsyncCall(@ACall.Fire, 0);
end;

procedure TTyCustomRichEdit.RemovePostedCall(ACall: TTyRichQueuedCall);
begin
  // once the queue is shut down it removes nothing (it raises), and runs no call after that
  if (Application <> nil) and not (AppDoNotCallAsyncQueue in Application.Flags) then
    Application.RemoveAsyncCalls(ACall);
end;

procedure TTyCustomRichEdit.WatchIdle(AOn: Boolean);
begin
  if Application = nil then Exit;
  if AOn then
    // run before the handlers registered earlier: one of them that says "not done" stops the
    // walk over the rest
    Application.AddOnIdleHandler(@IdleStep, False)
  // the application frees its handler lists while it is destroyed
  else if not (AppDestroying in Application.Flags) then
    Application.RemoveOnIdleHandler(@IdleStep);
end;

procedure TTyCustomRichEdit.IdleStep(Sender: TObject; var Done: Boolean);
begin
  if FLoadEndOwed and not FInStep and (FSaving = 0) then
  begin
    // its own driver stays on only for pictures left (CancelLoad's tail)
    EndOwedLoad;
    Exit;
  end;
  if not HandleAllocated or not HasBackgroundWork then
  begin
    StopBackground;
    Exit;
  end;
  // inside a load step or a save (a handler that runs a modal loop): their end goes on
  if FInStep or (FSaving > 0) then Exit;
  ScheduleCall(FStepCall);
  // a call that could not be queued: the load ends now
  EndOwedLoad;
end;

procedure TTyCustomRichEdit.TurnTimerTick(Sender: TObject);
begin
  BackgroundTurn;
end;

procedure TTyCustomRichEdit.LifeEnter(var ALife: TTyRichLife; AHandler: Boolean);
begin
  ALife.Gone := False;
  ALife.Handler := AHandler;
  ALife.Depth := GRichAppDepth;
  ALife.Next := FLife;
  FLife := @ALife;
end;

{ A public call's frame caught ETyRichGone - a handler under it freed the control: does the
  unwinding go on past this frame? Only into the control's own code: when the frame below is
  another public call's (LoadFromFile around LoadFromStream), which called this one itself and
  must not go on either. With a handler's frame below - the application's handler made this
  call -, a frame of another depth below (another control's handler, the application's code,
  lies between them) or none, it ends here: the call returns its "nothing", no exception
  reaches the application's code; the frames below find the control gone when the call
  returns to them. (No method: the control is gone.) }
function TyRichGonePasses(const ALife: TTyRichLife): Boolean;
begin
  Result := not ALife.Gone or ((ALife.Next <> nil) and not ALife.Next^.Handler and
    (ALife.Next^.Depth = ALife.Depth));
end;

procedure TTyCustomRichEdit.LifeLeave(var ALife: TTyRichLife);
var
  p: ^PTyRichLife;
begin
  // (taken out wherever it is in the chain)
  p := @FLife;
  while (p^ <> nil) and (p^ <> @ALife) do p := @(p^^.Next);
  if p^ <> nil then p^ := ALife.Next;
end;

procedure TTyCustomRichEdit.BackstopTick(Sender: TObject);
begin
  // a turn ran since the last tick: the idle step drives the work
  if FTurnsRun <> FBackstopSeen then
  begin
    FBackstopSeen := FTurnsRun;
    Exit;
  end;
  if not HandleAllocated or not HasBackgroundWork then
  begin
    StopBackground;
    Exit;
  end;
  // inside a load step, a save or a turn (a handler that pumps messages): their end goes on
  if FInStep or (FSaving > 0) or FInTurn then Exit;
  { The one queued call, if it waits, is this turn: taken off, it does not run right after it.
    (Not run through the queue: in a flood of messages on gtk and qt the queue is run only by
    the idle step and ProcessMessages, which is what is starved.) }
  CancelCall(FStepCall);
  if not BackgroundTurn then Exit;
  FBackstopSeen := FTurnsRun;
end;

procedure TTyCustomRichEdit.CallFired(ACall: TTyRichQueuedCall);
begin
  if ACall = FStepCall then
  begin
    // the window went meanwhile (DestroyWnd takes the call off; this is the guard)
    if HandleAllocated then BackgroundTurn;
  end
  else if ACall = FSelCall then
    DoSelectionChange
  else if ACall = FSizeCall then
    CheckContentSize(False)
  else if ACall = FFindCall then
    try
      PayFindOwed;
    except
      // (its handler freed the control: nothing more of it)
      on ETyRichGone do ;
    end;
end;

{ A turn; False when a handler of the find's or the replace's events freed the control in it
  (nothing of it is touched after that). }
function TTyCustomRichEdit.BackgroundTurn: Boolean;
var
  life: TTyRichLife;
begin
  LifeEnter(life);
  try
    try
      TurnBody(life);
    except
      on ETyRichGone do
        if not life.Gone then raise;
    end;
  finally
    // (also when the turn raised: no frame of a turn that ended stays in the chain)
    if not life.Gone then LifeLeave(life);
  end;
  Result := not life.Gone;
end;

procedure TTyCustomRichEdit.TurnBody(var ALife: TTyRichLife);
var
  t0, tEnd: QWord;
  n: Integer;
  ms: Int64;
begin
  // inside a load step (a handler that pumps messages) or a save: their end starts it again
  if FInStep or (FSaving > 0) or FInTurn then Exit;
  if FLoadEndOwed then
  begin
    EndOwedLoad;
    Exit;
  end;
  { The clock (GetTickCount64) may advance in 15.6 ms steps (Windows' default): it only ends a
    turn early. What holds a turn near CRichIdleBudgetMs whatever the clock is the cap on its
    pieces: CRichIdleMaxSteps load slices or pictures. }
  FInTurn := True;
  Inc(FTurnsRun);
  FTurnBytes := 0;
  FFindTurnWork := 0;
  FHandlerMs := 0;
  try
    t0 := IdleTicks;
    n := 0;
    ms := 0;
    repeat
      if not StepBackground then Break;
      Inc(n);
      ms := Int64(IdleTicks - t0);
    until (n >= CRichIdleMaxSteps) or (ms >= CRichIdleBudgetMs);
    NoteTurn(ms);
    NoteFindTurn(ms);
    { The range the turn's slices held back reaches the bars, the turn's whole work at once,
      when none did for CRichLoadBarsMs (by the clock's last reading); the first turn of a load
      always. }
    tEnd := t0 + QWord(Math.Max(Int64(0), ms));
    if FBarsBehind and (not FBarsAtValid or (tEnd < FBarsAt) or
      (tEnd - FBarsAt >= CRichLoadBarsMs)) then
    begin
      FBarsAt := tEnd;
      FBarsAtValid := True;
      CatchUpBars;
    end;
  finally
    { The driver stays on while work is left, also after a piece raised: the work never
      strands. Nothing is queued from here: still inside the turn, a start only
      registers the idle handler, and the next idle step queues the next turn. A control a
      handler freed is not touched. }
    if not ALife.Gone then
      try
        if HasBackgroundWork then StartBackground else StopBackground;
      finally
        FInTurn := False;
      end;
  end;
  // the next turn could not be scheduled: the load ends here, out of the turn
  EndOwedLoad;
end;

function TTyCustomRichEdit.IdleTicks: QWord;
begin
  Result := GetTickCount64;
end;

{ A turn that indexed took AMs, of which the progress handler's time is not the file's. Its slice
  size is halved when the turn went over the budget (> CRichIdleBudgetMs), doubled when it was
  fast (< CRichIdleBudgetMs / 4), and kept in between. The last turn alone decides, one step at
  a time: a stall (a page fault, a debugger, the machine busy) costs one halving, and a few fast
  turns bring the size back. The band between the two thresholds is four times wide, so a
  steady rate settles rather than flips: a size doubled from a fast turn gives a turn of at
  most twice that time, still under the budget (a turn of three slices under 2 ms becomes one
  under 4 ms), and a size halved from a slow turn gives a turn no faster than the band's floor
  (a turn ends when it reaches the budget, so the halved one still takes 4 ms or more). On a
  clock that steps by 15.6 ms (Windows) the readings are 0 or 16: a turn is then judged fast
  or slow at random in proportion to its length, which holds turns around the budget. }
procedure TTyCustomRichEdit.NoteTurn(AMs: Int64);
var
  floor: Int64;
begin
  if FTurnBytes <= 0 then Exit;
  Dec(AMs, FHandlerMs);
  floor := Math.Min(CRichLoadMinStepBytes, FStepBytes);
  if AMs > CRichIdleBudgetMs then
    FSlice := Math.Max(floor, FSlice div 2)
  else if AMs < CRichIdleBudgetMs div 4 then
    FSlice := Math.Min(FStepBytes, FSlice * 2);
end;

function TTyCustomRichEdit.SliceBytes: Int64;
begin
  // a step by hand (not a turn) is not held to the budget
  if not FInTurn then Exit(FStepBytes);
  Result := Math.Max(FSlice, Math.Min(CRichLoadMinStepBytes, FStepBytes));
  if Result > FStepBytes then Result := FStepBytes;
end;

procedure TTyCustomRichEdit.InitializeWnd;
begin
  inherited InitializeWnd;
  if HasBackgroundWork then StartBackground;
  { The widgetset's own input method hook, as the memo installs it: Qt (whole commits, the
    candidate window's place), GTK2 (an input context of its own); nil elsewhere. }
  TyImeUninstall(FImeHook);
  // (none in the form designer, where nothing is typed)
  if not (csDesigning in ComponentState) then
    FImeHook := TyImeInstall(Self, @HookCommit, @HookCaretRect);
  // drops from other programs: the new window is registered (AcceptDrops; never in the designer)
  SyncDropRegistration;
end;

{ ---- finding and replacing ----

  The engine's finder (tyControls.RichEdit.Find) searches and its replace command replaces;
  here are the façades, the user's Find Next, and the find and the replace in the background,
  which run as pieces of the background work's turns beside the load's slices and the
  pictures (StepBackground). A background find stops at any change of the document it did not
  make itself: a position it found could be stale, and a finder keeps no place that follows an
  edit. Every find or replace started gets exactly one done-event (unless the control is
  destroyed); every start and every end raises FFindGen, so that a turn or a handler of an
  older one is never taken for the one running now. }

procedure TTyCustomRichEdit.EndTypingRun;
begin
  // (a replace's step merges with nothing: a break of the run never touches it)
  FDoc.BreakMerge;
end;

function TTyCustomRichEdit.GetFindRunning: Boolean;
begin
  Result := FFindKind <> rfkNone;
end;

function TTyCustomRichEdit.FindBlocked: Boolean;
begin
  Result := True;
  if FFindKind = rfkNone then Exit;
  if FFindKind = rfkFind then
  begin
    // a find that has searched what is indexed waits while the load goes on
    Result := (FFinder <> nil) and FFinder.Waiting and FDoc.Loading and
      (TyRichRtfLoadOf(FDoc) <> nil);
    Exit;
  end;
  { A replace waits for the load to have the whole text (a range to its end included). Its next part
    waits while an input method composes or the document holds its changes back (an update,
    a save) - and asks for no turn meanwhile: what it waits for wakes it (FindWake). }
  Result := FDoc.Loading or ((FReplaceCmd <> nil) and FReplaceCmd.Ready and
    (FComposing or FDoc.Updating or FDoc.Saving));
end;

procedure TTyCustomRichEdit.FindWake;
begin
  if (FFindKind <> rfkNone) and not FindBlocked and HasBackgroundWork then StartBackground;
end;

function TTyCustomRichEdit.SyncFind(const AText: string; AStart, ALen: TTyRichPos;
  AOptions: TTyRichFindOptions; out AFoundLen: TTyRichPos): TTyRichPos;
var
  f: TTyRichFinder;
  len, stop, span: TTyRichPos;
  wait: Boolean;
begin
  Result := -1;
  AFoundLen := 0;
  len := FDoc.Text.Length;
  if AStart < 0 then AStart := 0;
  if AStart > len then Exit;
  // (a range past the end: to the end - and of a document still loading, what is loaded)
  if (ALen < 0) or (ALen > len - AStart) then stop := -1 else stop := AStart + ALen;
  if stop < 0 then span := len - AStart else span := stop - AStart;
  wait := span > FCopyWaitChars;
  if wait then BeginWait;
  try
    f := TTyRichFinder.Create(FDoc, AText, AOptions - [rfoWrap], AStart, stop);
    try
      if f.Run = rfrFound then
      begin
        Result := f.MatchPos;
        AFoundLen := f.MatchLen;
      end;
      Inc(FFindBytesRead, f.TextBytes);
    finally
      f.Free;
    end;
  finally
    if wait then EndWait;
  end;
end;

function TTyCustomRichEdit.FindText(const SearchStr: string; StartPos, Length: TTyRichPos;
  Options: TTySearchTypes): TTyRichPos;
var
  o: TTyRichFindOptions;
  n: TTyRichPos;
begin
  o := [];
  if stMatchCase in Options then Include(o, rfoMatchCase);
  if stWholeWord in Options then Include(o, rfoWholeWord);
  Result := SyncFind(SearchStr, StartPos, Length, o, n);
end;

function TTyCustomRichEdit.Search(const ANiddle: string; Start, Len: TTyRichPos;
  const SearchOpt: TTySearchOptions): TTyRichPos;
var
  s, n: TTyRichPos;
begin
  s := -1;
  n := 0;
  if not Search(ANiddle, Start, Len, SearchOpt, s, n) then s := -1;
  Result := s;
end;

function TTyCustomRichEdit.Search(const ANiddle: string; Start, Len: TTyRichPos;
  const SearchOpt: TTySearchOptions; var ATextStart, ATextLength: TTyRichPos): Boolean;
var
  o: TTyRichFindOptions;
  p, n, from: TTyRichPos;
begin
  o := [];
  if soMatchCase in SearchOpt then Include(o, rfoMatchCase);
  if soWholeWord in SearchOpt then Include(o, rfoWholeWord);
  if soBackward in SearchOpt then
  begin
    { RichMemo's (its win32 back end): backward the search begins at Start and goes toward the
      text's beginning over Len characters - [Start - Len, Start], not below 0; a Len below 0
      down to 0. The match nearest Start, the whole of it in the range. }
    Include(o, rfoBackward);
    if Start < 0 then Start := 0;
    if Start > FDoc.Text.Length then Start := FDoc.Text.Length;
    if Len < 0 then from := 0 else from := Math.Max(Int64(0), Start - Len);
    p := SyncFind(ANiddle, from, Start - from, o, n);
  end
  else
    p := SyncFind(ANiddle, Start, Len, o, n);
  Result := p >= 0;
  if not Result then Exit;
  ATextStart := p;
  ATextLength := n;
end;

function TTyCustomRichEdit.Search(const ANiddle: string; Start, Len: TTyRichPos;
  const SearchOpt: TTySearchOptions; var ATextStart, ATextLength: Integer): Boolean;
var
  s, n: TTyRichPos;
begin
  s := ATextStart;
  n := ATextLength;
  Result := Search(ANiddle, Start, Len, SearchOpt, s, n);
  // (a match past MaxInt cannot be told in an Integer: as none, the variables left)
  if Result and ((s > MaxInt) or (n > MaxInt)) then Result := False;
  if not Result then Exit;
  ATextStart := Integer(s);
  ATextLength := Integer(n);
end;

{ The caret place at or after APos (SnapPos's other side): the end of a cluster a position
  inside it belongs to. }
function TTyCustomRichEdit.SnapPosAfter(APos: TTyRichPos): TTyRichPos;
var
  t: TTyRichText;
  b: TTyBlockLayout;
  start, r: TTyRichPos;
begin
  t := FDoc.Text;
  if APos < 0 then APos := 0;
  if APos > t.Length then APos := t.Length;
  Result := APos;
  EnsureParams;
  FDoc.BeginRead;
  try
    b := LayoutBlockAt(t.ParaOfPos(APos));
    try
      start := t.ParaStart(b.FirstPara);
      if APos <= start then Exit;
      // a cut paragraph's hidden tail: kept (as SnapPos keeps it)
      if (b is TTyParaLayout) and (APos - start > b.LastCaretPos) then Exit;
      // after an object of no width: the run's resting place (a step on would pass it whole)
      if b.UnseenEnd(APos - start, False) <> APos - start then
        Exit(start + b.RestPos(APos - start));
      // one step on from the character before: the caret place at or after APos
      r := b.NextCaretPos(APos - start - 1, True);
      if r >= 0 then Result := start + r;
    finally
      b.Release;
    end;
  finally
    FDoc.EndRead;
  end;
end;

{ A match found: selected as SelStart and SelLength place a selection (caret places; a place
  in a cut paragraph's hidden tail kept), never empty - its start goes back to the start of the
  cluster it is in, its end on to the end of the cluster it ends in (a letter of a letter with
  a combining mark, an emoji of one with a modifier: the whole cluster is selected, and the
  next search goes on after it) -, the caret at its end, in view, one report. }
procedure TTyCustomRichEdit.SelectFound(APos, ALen: TTyRichPos);
var
  a, c: TTyRichPos;
begin
  if ViewBehind then
    Select(APos, APos + ALen, False)
  else
  begin
    a := SnapPos(APos);
    c := SnapPosAfter(APos + ALen);
    if c <= a then c := SnapPosAfter(a + 1);
    Select(a, c, False);
  end;
  Moved(False);
end;

{ The needle's length in characters, as the finder counts it (a paragraph end one). }
function NeedleChars(const AText: string): TTyRichPos;
begin
  Result := Length(TyRichFindCodes(AText));
end;

function TTyCustomRichEdit.FindNext(const AText: string; AOptions: TTyRichFindOptions): Boolean;
var
  p, n, s, e, len: TTyRichPos;
  o: TTyRichFindOptions;
var
  life: TTyRichLife;
begin
  Result := False;
  { A handler of a find's or a replace's events may free the control in here: then this
    returns, touching nothing of it (inside another call of the control, that one does). }
  LifeEnter(life);
  try
    try
      Result := False;
      // a user's action: what is being composed goes in first; it edits nothing
      EndCompositionForUser;
      if FFindKind <> rfkNone then EndFind(rfsCancelled, True);
      o := AOptions - [rfoWrap];
      s := GetSelStart;
      e := s + GetSelLength;
      len := NeedleChars(AText);
      if rfoBackward in AOptions then
      begin
        p := SyncFind(AText, 0, s, o, n);
        // wrapped: from the end down to where it began - a match that ends past its start
        if (p < 0) and (rfoWrap in AOptions) then
          p := SyncFind(AText, Math.Max(Int64(0), s - len + 1), -1, o, n);
      end
      else
      begin
        p := SyncFind(AText, e, -1, o, n);
        // wrapped: from the start on to where it began - a match that starts before it
        if (p < 0) and (rfoWrap in AOptions) then
          p := SyncFind(AText, 0, e + len - 1, o, n);
      end;
      if p < 0 then Exit;
      SelectFound(p, n);
      Result := True;
    except
      on ETyRichGone do if TyRichGonePasses(life) then raise;
    end;
  finally
    if not life.Gone then LifeLeave(life);
  end;
end;

procedure TTyCustomRichEdit.StartFindLeg(AFrom, ATo: TTyRichPos);
begin
  FreeAndNil(FFinder);
  FFinder := TTyRichFinder.Create(FDoc, FFindText, FFindOpts - [rfoWrap], AFrom, ATo);
  FFindLegFrom := AFrom;
  FFindLegTo := ATo;
end;

procedure TTyCustomRichEdit.StartFind(AKind: TTyRichFindKind);
begin
  if FFindKind <> rfkNone then EndFind(rfsCancelled, True);
  // (an owed end of an older one is told first)
  PayFindOwed;
  Inc(FFindGen);
  FFindKind := AKind;
  FFindState := FDoc.ContentState;
  // its turns start small and find their size, as a load's do
  FFindSlice := CRichFindMinStepChars;
  FFindDone := 0;
  FFindTotal := 0;
  FFindLegBase := 0;
  FFindWrapLeft := False;
end;

procedure TTyCustomRichEdit.FindNextAsync(const AText: string; AOptions: TTyRichFindOptions);
var
  len, s, e: TTyRichPos;
var
  life: TTyRichLife;
begin
  { A handler of a find's or a replace's events may free the control in here: then this
    returns, touching nothing of it (inside another call of the control, that one does). }
  LifeEnter(life);
  try
    try
      EndCompositionForUser;
      StartFind(rfkFind);
      FFindText := AText;
      FFindOpts := AOptions;
      FFindWrapLeft := rfoWrap in AOptions;
      len := FDoc.Text.Length;
      s := GetSelStart;
      e := s + GetSelLength;
      FFindLen := NeedleChars(AText);
      if rfoBackward in AOptions then
      begin
        StartFindLeg(0, s);
        FFindTotal := s;
        FFindFrom := s;
      end
      else
      begin
        StartFindLeg(e, -1);
        FFindTotal := len - e;
        FFindFrom := e;
      end;
      // a wrapped search goes on to where it began (and a needle's length into it)
      if FFindWrapLeft then Inc(FFindTotal, len - FFindTotal + FFindLen);
      if HasBackgroundWork then StartBackground;
    except
      on ETyRichGone do if TyRichGonePasses(life) then raise;
    end;
  finally
    if not life.Gone then LifeLeave(life);
  end;
end;

function TTyCustomRichEdit.ReplaceAll(const AFind, AReplace: string;
  AOptions: TTyRichFindOptions): Integer;
var
  res: TTyRichReplaceResult;
begin
  Result := ReplaceAll(AFind, AReplace, AOptions, 0, -1, res);
end;

function TTyCustomRichEdit.ReplaceAll(const AFind, AReplace: string; AOptions: TTyRichFindOptions;
  out ASkipped: Integer): Integer;
var
  res: TTyRichReplaceResult;
begin
  Result := ReplaceAll(AFind, AReplace, AOptions, 0, -1, res);
  ASkipped := res.Skipped;
end;

{ The matches of a document that takes no change now (loading, incomplete, saving): counted,
  each one left. }
function TTyCustomRichEdit.CountMatches(const AFind: string; AOptions: TTyRichFindOptions;
  AStart, ALength: TTyRichPos): Integer;
var
  f: TTyRichFinder;
  stop: TTyRichPos;
begin
  if AStart < 0 then AStart := 0;
  if ALength < 0 then stop := -1 else stop := AStart + ALength;
  f := TTyRichFinder.Create(FDoc, AFind, AOptions - [rfoBackward, rfoWrap], AStart, stop);
  try
    f.Collect := True;
    f.Run;
    Result := f.MatchCount;
  finally
    f.Free;
  end;
end;

{ What a replace that ended tells (ATally: the command's; AStop: how it stopped). }
function ReplaceResultOf(AStop: TTyRichFindStop; const ATally: TTyRichReplaceTally):
  TTyRichReplaceResult;
begin
  Result.Replaced := ATally.Replaced;
  Result.Skipped := ATally.Skipped;
  if ATally.Failed then Result.Ending := rreFailed
  else if AStop = rfsCancelled then Result.Ending := rreCancelled
  else if ATally.Limited then Result.Ending := rreLimit
  else Result.Ending := rreDone;
  if Result.Ending = rreDone then
  begin
    Result.ResumeAt := -1;
    Result.ResumeLength := -1;
  end
  else
  begin
    Result.ResumeAt := ATally.ResumeAt;
    if Result.ResumeAt < 0 then Result.ResumeLength := -1
    else Result.ResumeLength := ATally.ResumeLength;
  end;
end;

function TTyCustomRichEdit.ReplaceAll(const AFind, AReplace: string; AOptions: TTyRichFindOptions;
  AStart, ALength: TTyRichPos; out AResult: TTyRichReplaceResult): Integer;
var
  sync: TTyRichSyncReplace;
  tally: TTyRichReplaceTally;
  wait, ran, complete: Boolean;
  marks: TTyRichStepMarks;
  load: TTyRtfLoad;
  len: TTyRichPos;
  state: Int64;
var
  life: TTyRichLife;
begin
  Result := 0;
  AResult := Default(TTyRichReplaceResult);
  AResult.Ending := rreCancelled;
  AResult.ResumeAt := -1;
  AResult.ResumeLength := -1;
  { A handler of a find's or a replace's events may free the control in here: then this
    returns, touching nothing of it (inside another call of the control, that one does). }
  LifeEnter(life);
  try
    try
      Result := 0;
      if FFindKind <> rfkNone then EndFind(rfsCancelled, True);
      EndCompositionForUser;
      len := FDoc.Text.Length;
      if AStart < 0 then AStart := 0;
      if AStart > len then AStart := len;
      if (ALength >= 0) and (ALength > len - AStart) then ALength := -1;
      tally := Default(TTyRichReplaceTally);
      tally.ResumeAt := AStart;
      tally.ResumeLength := ALength;
      // a document that takes no change: every match is left (and counted), nothing raised
      if FDoc.Loading or FDoc.Incomplete or FDoc.Saving then
      begin
        tally.Skipped := CountMatches(AFind, AOptions, AStart, ALength);
        AResult := ReplaceResultOf(rfsDone, tally);
        Exit;
      end;
      wait := FDoc.Text.Length > FCopyWaitChars;
      if wait then BeginWait;
      try
        { The command, referred to from this call's stack: it says when it is freed - by the
          document that refused it or found nothing to change, by a handler of a part's change
          that lets the history go - and the reference goes then (ReplaceCommandFreed). While
          sync.Cmd is not nil the command is alive. }
        sync.Cmd := TTyRichReplaceAllCommand.Create(FDoc, AFind, AReplace, AOptions, AStart, ALength);
        sync.Next := FSyncReplace;
        FSyncReplace := @sync;
        ran := False;
        try
          sync.Cmd.Tally := @tally;
          sync.Cmd.OnFreed := @ReplaceCommandFreed;
          // (on from where the last one stopped: what that one's walk saw before the place)
          sync.Cmd.StartBefore := ResumeBeforeFor(AFind, AReplace, AOptions - [rfoBackward, rfoWrap],
            AStart);
          tally.ResumeBefore := sync.Cmd.StartBefore;
          FResumeValid := False;
          marks := Default(TTyRichStepMarks);
          marks.HasBefore := True;
          marks.Before.Anchor := FSelAnchor;
          marks.Before.Caret := FCaret;
          marks.Before.AtLineEnd := FCaretAtEnd;
          sync.Cmd.Marks := marks;
          if ViewBehind then
          begin
            { Inside BeginEdit .. EndEdit the document gathers the block's commands into its one
              step: the replace runs whole, in one run, there. }
            sync.Cmd.AllAtOnce := True;
            // (the document owns it from here on, also when it says no)
            ran := True;
            RunApiCommand(sync.Cmd, 0);
            Result := tally.Replaced;
            AResult := ReplaceResultOf(rfsDone, tally);
            Exit;
          end;
          { The engine's parts, as the background runs them, in a loop: a range of paragraphs found,
            then replaced (Execute, then ExecutePart - one undo step), and between two a lazily read
            file's intervals go back to the loader's bound. The view hears each part; the
            application one change, at the end. }
          complete := False;
          FEditHeard := False;
          FEditStep := nil;
          state := FDoc.ContentState;
          Inc(FEditing);
          try
            repeat
              sync.Cmd.Prepare(-1);
              if not sync.Cmd.Ready then
              begin
                { Nothing more found: through the range, or a walk that failed - or one a
                  handler of the last part's change let go of (a step of its own put on top and
                  taken off again): that one is not through. }
                complete := sync.Cmd.Finished;
                Break;
              end;
              if not ran then
              begin
                // (the document owns it from here on, also when it says no)
                ran := True;
                if not FDoc.Execute(sync.Cmd) then Break;
              end
              else if not FDoc.ExecutePart(sync.Cmd) then Break;
              // (a handler of the part's change may have let the step go, or freed it)
              if (sync.Cmd = nil) or (FDoc.UndoStep <> sync.Cmd) then Break;
              state := FDoc.ContentState;
              load := TyRichRtfLoadOf(FDoc);
              if load <> nil then load.Trim;
              if sync.Cmd.Finished then complete := True;
            until complete;
          finally
            Dec(FEditing);
          end;
          Result := tally.Replaced;
          if complete then AResult := ReplaceResultOf(rfsDone, tally)
          else AResult := ReplaceResultOf(rfsCancelled, tally);
          // (stopped before its end: where it says to go on from, and what its walk saw there)
          RememberResume(AFind, AReplace, AOptions - [rfoBackward, rfoWrap], tally,
            (AResult.Ending in [rreCancelled, rreLimit]) and (FDoc.ContentState = state));
          if FEditHeard then
          begin
            // the step's selection after: where it stays (a document-API write keeps it)
            if (sync.Cmd <> nil) and (FDoc.UndoStep = sync.Cmd) then FEditStep := sync.Cmd;
            Inc(FApiWrite);
            try
              FinishEdit(FSelAnchor, FCaret, FCaretAtEnd, True);
            finally
              Dec(FApiWrite);
            end;
          end;
        finally
          { This call's reference ends here. A command still alive tells it nothing any more
            (its tally is on this stack) and will not go on; one the document never took is
            this call's to free. }
          if not life.Gone then FSyncReplace := sync.Next;
          if sync.Cmd <> nil then
          begin
            sync.Cmd.Tally := nil;
            sync.Cmd.OnFreed := nil;
            if ran then sync.Cmd.LetGo else sync.Cmd.Free;
          end;
        end;
      finally
        if wait then EndWait;
      end;
    except
      on ETyRichGone do if TyRichGonePasses(life) then raise;
    end;
  finally
    if not life.Gone then LifeLeave(life);
  end;
end;

procedure TTyCustomRichEdit.ReplaceAllAsync(const AFind, AReplace: string;
  AOptions: TTyRichFindOptions; AStart: TTyRichPos; ALength: TTyRichPos);
var
  marks: TTyRichStepMarks;
  len: TTyRichPos;
var
  life: TTyRichLife;
begin
  { A handler of a find's or a replace's events may free the control in here: then this
    returns, touching nothing of it (inside another call of the control, that one does). }
  LifeEnter(life);
  try
    try
      EndCompositionForUser;
      StartFind(rfkReplace);
      FFindText := AFind;
      FFindOpts := AOptions - [rfoBackward, rfoWrap];
      len := FDoc.Text.Length;
      if AStart < 0 then AStart := 0;
      if AStart > len then AStart := len;
      if (ALength >= 0) and (ALength > len - AStart) then ALength := -1;
      FReplaceFrom := AStart;
      FReplaceLength := ALength;
      FReplaceTally := Default(TTyRichReplaceTally);
      FReplaceTally.ResumeAt := AStart;
      FReplaceTally.ResumeLength := ALength;
      FReplaceFollows := False;
      FReplaceWith := AReplace;
      FReplaceCmd := TTyRichReplaceAllCommand.Create(FDoc, AFind, AReplace, FFindOpts, AStart,
        ALength);
      FReplaceCmd.Tally := @FReplaceTally;
      FReplaceCmd.OnFreed := @ReplaceCommandFreed;
      // (on from where the last one stopped: what that one's walk saw before the place)
      FReplaceCmd.StartBefore := ResumeBeforeFor(AFind, AReplace, FFindOpts, AStart);
      FReplaceTally.ResumeBefore := FReplaceCmd.StartBefore;
      FReplaceCmd.RangeChars := FFindSlice;
      FReplaceRan := False;
      marks := Default(TTyRichStepMarks);
      marks.HasBefore := True;
      marks.Before.Anchor := FSelAnchor;
      marks.Before.Caret := FCaret;
      marks.Before.AtLineEnd := FCaretAtEnd;
      FReplaceCmd.Marks := marks;
      if HasBackgroundWork then StartBackground;
    except
      on ETyRichGone do if TyRichGonePasses(life) then raise;
    end;
  finally
    if not life.Gone then LifeLeave(life);
  end;
end;

procedure TTyCustomRichEdit.CancelFind;
var
  life: TTyRichLife;
begin
  { A handler of a find's or a replace's events may free the control in here: then this
    returns, touching nothing of it (inside another call of the control, that one does). }
  LifeEnter(life);
  try
    try
      if FFindKind <> rfkNone then EndFind(rfsCancelled, True);
    except
      on ETyRichGone do if TyRichGonePasses(life) then raise;
    end;
  finally
    if not life.Gone then LifeLeave(life);
  end;
end;

{ The running find or replace ends, no event: its finder goes, a replace's command too unless
  it ran (then it is the history's). What it did is kept for the event (FEnded*). }
procedure TTyCustomRichEdit.StopFind;
var
  cmd: TTyRichReplaceAllCommand;
begin
  FEndedKind := FFindKind;
  if FFindKind = rfkNone then Exit;
  { What the command told is true of the content its last part left; with that content there
    again (an edit undone, its own step undone and redone) it is told as it is. Otherwise what
    followed the changes made since. }
  FEndedExact := (FDoc.Text = FText) and (FDoc.ContentState = FFindState);
  if FReplaceFollows and not FEndedExact then
    FEndedTally := FReplaceFollowed
  else
    FEndedTally := FReplaceTally;
  FReplaceFollows := False;
  FFindKind := rfkNone;
  Inc(FFindGen);
  FreeAndNil(FFinder);
  cmd := FReplaceCmd;
  FReplaceCmd := nil;
  if cmd <> nil then
  begin
    // (it tells this control nothing any more - not what it does, not that it is freed)
    cmd.Tally := nil;
    cmd.OnFreed := nil;
    if FReplaceRan then
      // the history's - wherever in it: it will not go on, only its undo record stays
      cmd.LetGo
    else
      cmd.Free;
  end;
  FReplaceRan := False;
end;

{ A replace's command this control refers to is freed (TTyRichCommand.OnFreed: by whatever
  frees it - the history cleared or trimmed, its redo side dropped, a new content, a run the
  document refused). The reference goes before the command does. A replace in the background
  ends with it, as cancelled, with what it did and - while the text is still there - the place
  to go on from; its event is owed (a queued call tells it, or the public call that is
  replacing the content): no handler of the application's runs inside what frees a step. }
procedure TTyCustomRichEdit.ReplaceCommandFreed(Sender: TObject);
var
  f: PTyRichSyncReplace;
begin
  f := FSyncReplace;
  while f <> nil do
  begin
    if f^.Cmd = Sender then f^.Cmd := nil;
    f := f^.Next;
  end;
  if Sender <> FReplaceCmd then Exit;
  FReplaceCmd := nil;
  FReplaceRan := False;
  // (freed inside its own run: the piece that ran it ends the replace when the run returns)
  if FInReplacePart or (FFindKind <> rfkReplace) then Exit;
  EndFind(rfsCancelled, False);
end;

{ What ended is told: the progress at its total first (also nothing found, cancelled, the
  limit), then the done-event. }
procedure TTyCustomRichEdit.TellFindEnd(AKind: TTyRichFindKind; AStop: TTyRichFindStop;
  APos, ALen: TTyRichPos; const ATally: TTyRichReplaceTally);
var
  total: Int64;
begin
  if [csDestroying, csLoading] * ComponentState <> [] then Exit;
  total := Math.Max(FFindTotal, FFindDone);
  if (total > FFindDone) or (total = 0) then ReportFindProgress(AKind, total, total);
  RaiseFindEnd(AKind, AStop, APos, ALen, ATally);
end;

{ A replace stopped before its end, and what it tells is true of the content as it is
  (AExact): where it said to go on from is remembered with what its walk saw there. Any other
  end forgets what was remembered. }
procedure TTyCustomRichEdit.RememberResume(const AFind, AReplace: UTF8String;
  AOptions: TTyRichFindOptions; const ATally: TTyRichReplaceTally; AExact: Boolean);
begin
  FResumeValid := AExact and (ATally.ResumeAt >= 0) and ATally.ResumeBefore.Known;
  if not FResumeValid then Exit;
  FResumeAt := ATally.ResumeAt;
  FResumeState := FDoc.ContentState;
  FResumeBefore := ATally.ResumeBefore;
  FResumeFind := AFind;
  FResumeRepl := AReplace;
  FResumeOpts := AOptions;
end;

{ What a replace that starts at AStart is told of the character before its start: what the
  replace that stopped exactly there saw - the same needle, replacement and options, the
  content unchanged since -, else nothing (the text as it is says). }
function TTyCustomRichEdit.ResumeBeforeFor(const AFind, AReplace: UTF8String;
  AOptions: TTyRichFindOptions; AStart: TTyRichPos): TTyRichBefore;
begin
  Result := Default(TTyRichBefore);
  if FResumeValid and (AStart = FResumeAt) and (FDoc.ContentState = FResumeState) and
    (AOptions = FResumeOpts) and (AFind = FResumeFind) and (AReplace = FResumeRepl) then
    Result := FResumeBefore;
end;

procedure TTyCustomRichEdit.EndFind(AStop: TTyRichFindStop; AEvent: Boolean);
begin
  if FFindKind = rfkNone then Exit;
  StopFind;
  if FEndedKind = rfkReplace then
    RememberResume(FFindText, FReplaceWith, FFindOpts, FEndedTally, FEndedExact and
      not FEndedTally.Failed and ((AStop = rfsCancelled) or FEndedTally.Limited));
  if not AEvent then
  begin
    { No handler is run where the content is torn down or a step is being freed: the event
      is owed - to the public call that replaced the content (PayFindOwed), else to a queued
      call. None from the destructor. (Where the content went, ContentReplaced takes the
      place to go on from out of what is owed: that text is gone.) }
    if not (csDestroying in ComponentState) then
    begin
      FOwedKind := FEndedKind;
      FOwedStop := AStop;
      FOwedTally := FEndedTally;
      ScheduleCall(FFindCall);
    end;
    Exit;
  end;
  TellFindEnd(FEndedKind, AStop, -1, 0, FEndedTally);
end;

procedure TTyCustomRichEdit.RaiseFindEnd(AKind: TTyRichFindKind; AStop: TTyRichFindStop;
  APos, ALen: TTyRichPos; const ATally: TTyRichReplaceTally);
var
  fin: TTyRichFindEnd;
  life: TTyRichLife;
begin
  if [csDestroying, csLoading] * ComponentState <> [] then Exit;
  { A handler may free the control (from any of these events): then nothing of it is touched
    after the handler - ETyRichGone, raised when the handler has returned, goes up to the turn,
    which ends quietly, or to the public call that ended the find, which returns. }
  LifeEnter(life, True);
  try
    if AKind = rfkFind then
    begin
      case AStop of
        rfsFound: fin := rfeFound;
        rfsCancelled: fin := rfeCancelled;
      else
        fin := rfeNotFound;
      end;
      if fin <> rfeFound then
      begin
        APos := -1;
        ALen := 0;
      end;
      if Assigned(FOnFindDone) then FOnFindDone(Self, fin, APos, ALen);
    end
    else if Assigned(FOnReplaceDone) then
      FOnReplaceDone(Self, ReplaceResultOf(AStop, ATally));
  finally
    if not life.Gone then LifeLeave(life);
  end;
  if life.Gone then raise ETyRichGone.Create('The control was freed by its handler');
end;

procedure TTyCustomRichEdit.PayFindOwed;
var
  kind: TTyRichFindKind;
begin
  if FOwedKind = rfkNone then Exit;
  kind := FOwedKind;
  FOwedKind := rfkNone;
  CancelCall(FFindCall);
  TellFindEnd(kind, FOwedStop, -1, 0, FOwedTally);
end;

{ A change of the text a background replace did not make (an edit, an undo): where it would go
  on from moves with the text, so that what it tells is a place in the text as it is then.
  Followed beside what the command told (FReplaceFollowed): that stays true of the content the
  replace's last part left, and is what is told when that content is there again. }
procedure TTyCustomRichEdit.ReplaceResumeFollows(const AChange: TTyRichChange);

  procedure Follow(var ATally: TTyRichReplaceTally);
  var
    at, stop: TTyRichPos;
  begin
    at := ATally.ResumeAt;
    if (at < 0) or (AChange.Pos >= at) then Exit;
    if AChange.Pos + AChange.OldLen <= at then
      Inc(at, AChange.NewLen - AChange.OldLen)
    else
      // inside what changed: from where the change began
      at := AChange.Pos;
    if ATally.ResumeLength >= 0 then
    begin
      stop := ATally.ResumeAt + ATally.ResumeLength;
      if AChange.Pos + AChange.OldLen <= stop then Inc(stop, AChange.NewLen - AChange.OldLen)
      else if AChange.Pos < stop then stop := AChange.Pos + AChange.NewLen;
      ATally.ResumeLength := Math.Max(Int64(0), stop - at);
    end;
    ATally.ResumeAt := at;
  end;

begin
  // (an end still to be told - its step was freed under it: its place follows until then)
  if FOwedKind = rfkReplace then Follow(FOwedTally);
  if (FFindKind <> rfkReplace) or FInReplacePart then Exit;
  if not FReplaceFollows then
  begin
    FReplaceFollows := True;
    FReplaceFollowed := FReplaceTally;
  end;
  if FReplaceRan and (FReplaceCmd <> nil) and (FDoc.RedoStep = FReplaceCmd) then
  begin
    { Its own step undone: nothing of what it did is left - it tells none replaced, and the
      range's start as the place to go on from. }
    FReplaceFollowed.Replaced := 0;
    FReplaceFollowed.Skipped := 0;
    FReplaceFollowed.ResumeAt := FReplaceFrom;
    FReplaceFollowed.ResumeLength := FReplaceLength;
    Exit;
  end;
  Follow(FReplaceFollowed);
end;

procedure TTyCustomRichEdit.ReportFindProgress(AKind: TTyRichFindKind; ADone, ATotal: Int64);
var
  life: TTyRichLife;
  cancel: Boolean;
  t0: QWord;
  task: TTyRichFindTask;
begin
  FFindDone := ADone;
  if not Assigned(FOnFindProgress) then Exit;
  cancel := False;
  if AKind = rfkReplace then task := rftReplace else task := rftFind;
  // the handler's time is the user's: the pieces are not sized by it
  t0 := IdleTicks;
  LifeEnter(life, True);
  try
    FOnFindProgress(Self, task, ADone, ATotal, cancel);
  finally
    if not life.Gone then
    begin
      LifeLeave(life);
      Inc(FHandlerMs, Int64(IdleTicks - t0));
    end;
  end;
  if life.Gone then raise ETyRichGone.Create('The control was freed by its handler');
  FFindCancel := cancel;
end;

procedure TTyCustomRichEdit.FindProgress;
var
  done, total, legEnd: Int64;
  gen: Int64;
begin
  if FFindKind = rfkNone then Exit;
  if (FFindKind = rfkReplace) and (FReplaceCmd = nil) then Exit;
  if FFindKind = rfkReplace then
    FReplaceCmd.Progress(done, total)
  else
  begin
    if rfoBackward in FFindOpts then
    begin
      legEnd := FFindLegTo;
      if legEnd < 0 then legEnd := FDoc.Text.Length;
      done := FFindLegBase + legEnd - FFinder.Reached;
    end
    else
      done := FFindLegBase + FFinder.Reached - FFindLegFrom;
    total := FFindTotal;
  end;
  // never back (a load may make a total grow)
  if done < FFindDone then done := FFindDone;
  if total < done then total := done;
  FFindTotal := total;
  gen := FFindGen;
  FFindCancel := False;
  ReportFindProgress(FFindKind, done, total);
  if FFindCancel and (FFindGen = gen) and (FFindKind <> rfkNone) then EndFind(rfsCancelled, True);
end;

procedure TTyCustomRichEdit.FindPiece;
var
  r: TTyRichFindResult;
  budget, len, p, n: TTyRichPos;
  gen: Int64;
begin
  gen := FFindGen;
  { A change the find did not make (an edit, an undo, a new content): what it found, and
    where it stands, may be stale. }
  if (FDoc.ContentState <> FFindState) or (FDoc.Text <> FText) then
  begin
    EndFind(rfsCancelled, True);
    Exit;
  end;
  if FFindKind = rfkReplace then
  begin
    ReplacePiece;
    Exit;
  end;
  budget := FFindSlice;
  if budget < 1 then budget := 1;
  r := FFinder.Step(budget);
  Inc(FFindTurnWork, budget);
  FindProgress;
  // (stopped from the progress handler, or another started there: that one's turn is its own)
  if FFindGen <> gen then Exit;
  case r of
    rfrFound:
      begin
        p := FFinder.MatchPos;
        n := FFinder.MatchLen;
        // the find ends, the match is selected and in view, then it is told
        StopFind;
        SelectFound(p, n);
        TellFindEnd(rfkFind, rfsFound, p, n, FEndedTally);
      end;
    rfrNotFound:
      if FFindWrapLeft then
      begin
        // on from the other end, to where it began (and a needle's length into that)
        FFindWrapLeft := False;
        len := FDoc.Text.Length;
        if rfoBackward in FFindOpts then
        begin
          Inc(FFindLegBase, FFindLegTo - FFindLegFrom);
          StartFindLeg(Math.Max(Int64(0), FFindFrom - FFindLen + 1), -1);
        end
        else
        begin
          Inc(FFindLegBase, len - FFindLegFrom);
          StartFindLeg(0, Math.Min(len, FFindFrom + FFindLen - 1));
        end;
      end
      else
        EndFind(rfsNotFound, True);
  end;
end;

procedure TTyCustomRichEdit.ReplacePiece;
var
  gen: Int64;
  ok: Boolean;
  step: TTyRichCommand;
  marks: TTyRichStepMarks;
  load: TTyRtfLoad;
  stop: TTyRichPos;
  r: TTyRichFindResult;
  done: Int64;
begin
  gen := FFindGen;
  { A document that takes no change (a load cancelled): every match is left, and counted - a
    piece of the find's size a turn, as a find reads. }
  if FDoc.Incomplete then
  begin
    if FFinder = nil then
    begin
      if FReplaceLength < 0 then stop := -1 else stop := FReplaceFrom + FReplaceLength;
      FFinder := TTyRichFinder.Create(FDoc, FFindText, FFindOpts, FReplaceFrom, stop);
      FFinder.Collect := True;
      // its own total: the characters of the range it counts in
      if stop < 0 then FFindTotal := FDoc.Text.Length - FReplaceFrom
      else FFindTotal := stop - FReplaceFrom;
    end;
    r := FFinder.Step(Math.Max(Int64(1), FFindSlice));
    Inc(FFindTurnWork, FFindSlice);
    Inc(FReplaceTally.Skipped, FFinder.MatchCount);
    FFinder.ClearMatches;
    if r <> rfrNotFound then
    begin
      // the progress on the way, as any piece's (its handler may cancel)
      done := FFinder.Reached - FReplaceFrom;
      if done < FFindDone then done := FFindDone;
      if done > FFindTotal then done := FFindTotal;
      FFindCancel := False;
      ReportFindProgress(rfkReplace, done, FFindTotal);
      if (FFindGen = gen) and FFindCancel then EndFind(rfsCancelled, True);
      Exit;
    end;
    EndFind(rfsDone, True);
    Exit;
  end;
  { Let go of since its last part, with the content that part left there again - a step put on
    top of its own and taken off (an edit and its undo), its own step undone and redone: its
    walk is gone, and it is not through its range. It ends as stopped, with what it did and
    the place to go on from. }
  if (FReplaceCmd = nil) or FReplaceCmd.Stopped then
  begin
    EndFind(rfsCancelled, True);
    Exit;
  end;
  // a part is a range of paragraphs of the find's piece's size (as the clock sizes it)
  FReplaceCmd.RangeChars := FFindSlice;
  if not FReplaceCmd.Ready then
  begin
    // the search for the next part: a piece of the find's size, in units of its steps
    FReplaceCmd.Prepare(FFindSlice);
    Inc(FFindTurnWork, FFindSlice);
    FindProgress;
    if FFindGen <> gen then Exit;
    if FReplaceCmd.Finished then EndFind(rfsDone, True);
    Exit;
  end;
  // the part: the range found, replaced
  Inc(FFindTurnWork, FFindSlice);
  try
    if not FReplaceRan then
    begin
      FReplaceRan := True;
      // (the document owns it from here on, also when it says no)
      FInReplacePart := True;
      try
        ok := FDoc.Execute(FReplaceCmd);
      finally
        FInReplacePart := False;
      end;
    end
    else
    begin
      ok := FDoc.UndoStep = FReplaceCmd;
      if ok then
      begin
        FInReplacePart := True;
        try
          ok := FDoc.ExecutePart(FReplaceCmd);
        finally
          FInReplacePart := False;
        end;
      end;
    end;
  except
    // (the document reverted the part; the step, if any, stays the history's)
    if FFindGen = gen then EndFind(rfsCancelled, True);
    raise;
  end;
  // (a handler of the part's change may have ended the replace, or started another)
  if FFindGen <> gen then Exit;
  if not ok or (FReplaceCmd = nil) or (FDoc.UndoStep <> FReplaceCmd) then
  begin
    { Refused (the document freed the command: the reference went with it), or the step is
      not the replace's any more (a handler let it go, or put a step of its own on it): what
      was done stays, and nothing of it is on the redo side. }
    EndFind(rfsCancelled, True);
    Exit;
  end;
  { A lazily read file: what the part parsed was kept while its command ran (a command is a
    read scope); out of it, the intervals beyond the loader's bound go back to unparsed. }
  load := TyRichRtfLoadOf(FDoc);
  if load <> nil then load.Trim;
  // undone, the step puts back the selection there was when the replace began
  step := FReplaceCmd;
  marks := step.Marks;
  marks.HasAfter := True;
  marks.After.Anchor := FSelAnchor;
  marks.After.Caret := FCaret;
  marks.After.AtLineEnd := FCaretAtEnd;
  step.Marks := marks;
  FFindState := FDoc.ContentState;
  FindProgress;
  if FFindGen <> gen then Exit;
  if FReplaceCmd.Finished then EndFind(rfsDone, True);
end;

{ A turn that found or replaced: its pieces are sized as the load's slices are (NoteTurn) -
  halved when the turn went over the budget, doubled when it was fast, kept in between. A
  replace's range of paragraphs is the same size. }
procedure TTyCustomRichEdit.NoteFindTurn(AMs: Int64);
begin
  if FFindTurnWork <= 0 then Exit;
  Dec(AMs, FHandlerMs);
  if AMs > CRichIdleBudgetMs then
    FFindSlice := Math.Max(Int64(CRichFindMinStepChars), FFindSlice div 2)
  else if AMs < CRichIdleBudgetMs div 4 then
    FFindSlice := Math.Min(Int64(CRichFindStepChars), FFindSlice * 2);
end;

{ ---- loading and saving ---- }

procedure TTyCustomRichEdit.LoadProgress(Sender: TObject; ADone, ATotal: Int64);
var
  cancel: Boolean;
  t0: QWord;
begin
  cancel := False;
  if Assigned(FOnLoadProgress) then
  begin
    // the handler's time is the user's: the slices are not sized by it
    t0 := IdleTicks;
    try
      FOnLoadProgress(Self, ADone, ATotal, cancel);
    finally
      Inc(FHandlerMs, Int64(IdleTicks - t0));
    end;
  end;
  // not inside the step: the load is cancelled when the step has returned
  if cancel then FCancelRequested := True;
end;

function TTyCustomRichEdit.SaveProgress(ADone, ATotal: Int64): Boolean;
var
  cancel: Boolean;
begin
  cancel := False;
  if Assigned(FOnSaveProgress) then FOnSaveProgress(Self, ADone, ATotal, cancel);
  Result := not cancel;
end;

function TTyCustomRichEdit.DetectFormat(AStream: TStream): TTyRichFormat;
const
  Sig: array[0..4] of Char = ('{', '\', 'r', 't', 'f');
var
  buf: array[0..255] of Byte;
  n, i: Integer;
  start: Int64;
begin
  Result := rfText;
  start := AStream.Position;
  n := AStream.Read(buf, SizeOf(buf));
  AStream.Position := start;
  i := 0;
  if (n >= 3) and (buf[0] = $EF) and (buf[1] = $BB) and (buf[2] = $BF) then i := 3;
  while (i < n) and (buf[i] in [9, 10, 13, 32]) do Inc(i);
  if (i + 5 <= n) and CompareMem(@buf[i], @Sig[0], 5) then Result := rfRtf;
end;

{ The bytes before the RTF signature - a UTF-8 BOM, then blanks - as they are, the stream left
  at the signature (where the reader starts); none, and the stream where it was, when the
  signature does not follow them. }
function ReadRtfPrefix(AStream: TStream): TBytes;
const
  Sig: array[0..4] of Char = ('{', '\', 'r', 't', 'f');
var
  buf: array[0..255] of Byte;
  n, i: Integer;
  start: Int64;
begin
  Result := nil;
  start := AStream.Position;
  n := AStream.Read(buf, SizeOf(buf));
  AStream.Position := start;
  i := 0;
  if (n >= 3) and (buf[0] = $EF) and (buf[1] = $BB) and (buf[2] = $BF) then i := 3;
  while (i < n) and (buf[i] in [9, 10, 13, 32]) do Inc(i);
  if (i = 0) or (i + 5 > n) or not CompareMem(@buf[i], @Sig[0], 5) then Exit;
  SetLength(Result, i);
  Move(buf[0], Result[0], i);
  AStream.Position := start + i;
end;

{ A load, a Lines replacement or Clear frees what a running step or save still uses. }
procedure TTyCustomRichEdit.CheckReplaceable;
begin
  if FInStep or (FSaving > 0) then raise ETyRichEdit.Create(rsRichEditBusy);
  { Inside BeginEdit .. EndEdit: the block is one undo step and a new content has none -
    refused before anything changes, with the control's own exception. }
  if FEditBlock > 0 then raise ETyRichEdit.Create(rsRichEditReplaceInEdit);
  { A find or a replace running ends here, told before anything of the content goes (its
    handler sees the old content); one started from that handler ends with the content, and
    is told when the content is in (PayFindOwed), before the call returns. }
  if FFindKind <> rfkNone then EndFind(rfsCancelled, True);
end;

procedure TTyCustomRichEdit.LoadAs(AStream: TStream; AFormat: TTyRichFormat;
  AByAsked: Boolean);
var
  load: TTyRtfLoad;
  prefix: TBytes;
var
  life: TTyRichLife;
begin
  { A handler of a find's or a replace's events may free the control in here: then this
    returns, touching nothing of it (inside another call of the control, that one does). }
  LifeEnter(life);
  try
    try
      CheckReplaceable;
      FCancelRequested := False;
      // a new file's turns start small and find their size; its first slice is not a turn
      FSlice := CRichLoadMinStepBytes;
      // its first turn's range reaches the bars at once; an end owed to the last is moot
      FBarsAtValid := False;
      FLoadEndOwed := False;
      if AFormat = rfRtf then
      begin
        prefix := ReadRtfPrefix(AStream);
        load := TyRichBeginLoadRtf(FDoc, AStream, FFirstSliceBytes);
        load.OnLoadProgress := @LoadProgress;
        FSourceFormat := rfRtf;
        FRtfPrefix := prefix;
      end
      else
      begin
        TyRichLoadText(FDoc, AStream, FTextEncoding, FTextCodePage);
        FSourceFormat := rfText;
        FRtfPrefix := nil;
      end;
      { The document follows the file: one of the two things that set PlainText. A state the
        file (or the caller's rfRtf) made is not one the application asked for: the next load
        without a format goes by its file again. A load read as text by the asked True itself or
        by the caller's rfText decided nothing from its file: the asking stays, and the next load
        is text too, as Delphi's PlainText, which never changes by itself. }
      FPlainText := AFormat <> rfRtf;
      if not AByAsked then FPlainTextAsked := False;
      FLinesStored := False;
      FSourceFile := '';
      if HasBackgroundWork then StartBackground;
      // a first turn that could not be queued: the load ends before this returns
      EndOwedLoad;
      PayFindOwed;
    except
      on ETyRichGone do if TyRichGonePasses(life) then raise;
    end;
  finally
    if not life.Gone then LifeLeave(life);
  end;
end;

procedure TTyCustomRichEdit.LoadFromStream(AStream: TStream; AFormat: TTyRichFormat);
var
  byAsked: Boolean;
begin
  { An explicit text load agrees with an asked PlainText and keeps the asking: only a load
    whose format came from the file, or one that makes the document rich, ends it. }
  byAsked := AFormat = rfText;
  if AFormat = rfAuto then
    if FPlainText and FPlainTextAsked then
    begin
      AFormat := rfText;
      byAsked := True;
    end
    else AFormat := DetectFormat(AStream);
  LoadAs(AStream, AFormat, byAsked);
end;

procedure TTyCustomRichEdit.LoadFromFile(const AFileName: string);
var
  fs: TFileStream;
var
  life: TTyRichLife;
begin
  { A handler of a find's or a replace's events may free the control in here: then this
    returns, touching nothing of it (inside another call of the control, that one does). }
  LifeEnter(life);
  try
    try
      CheckReplaceable;
      // the bytes are read to the end at once and nothing is kept: a writer elsewhere is no harm
      fs := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
      try
        LoadFromStream(fs, rfAuto);
      finally
        fs.Free;
      end;
      FSourceFile := ExpandFileName(AFileName);
    except
      on ETyRichGone do if TyRichGonePasses(life) then raise;
    end;
  finally
    if not life.Gone then LifeLeave(life);
  end;
end;

procedure TTyCustomRichEdit.SetPlainText(const AText: string);
var
  s: RawByteString;
  st: TBytesStream;
  n: Integer;
var
  life: TTyRichLife;
begin
  { A handler of a find's or a replace's events may free the control in here: then this
    returns, touching nothing of it (inside another call of the control, that one does). }
  LifeEnter(life);
  try
    try
      CheckReplaceable;
      s := AText;
      // as TStrings reads it: a line break at the end closes the last line, it adds none
      n := Length(s);
      if (n > 0) and (s[n] = #10) then Dec(n);
      if (n > 0) and (s[n] = #13) and ((n = Length(s)) or (s[n + 1] = #10)) then Dec(n);
      SetLength(s, n);
      st := TBytesStream.Create(BytesOf(s));
      try
        TyRichLoadText(FDoc, st, teUtf8, 0);
      finally
        st.Free;
      end;
      // a text of one line break is one empty line, no text at all is none
      FLines.FEmptyLine := (AText <> '') and (FDoc.Text.Length = 0);
      FRtfPrefix := nil;
      { Text set as lines leaves PlainText as it is: a rich control stays rich and saves
        RTF as it came, a plain one text. }
      if FPlainText then FSourceFormat := rfText else FSourceFormat := rfRtf;
      FSourceFile := '';
      FLinesStored := True;
      PayFindOwed;
    except
      on ETyRichGone do if TyRichGonePasses(life) then raise;
    end;
  finally
    if not life.Gone then LifeLeave(life);
  end;
end;

procedure TTyCustomRichEdit.FinishLoading;
var
  load: TTyRtfLoad;
begin
  if FInStep then Exit;
  { In slices, so that the progress event fires and a cancel acts; the load is asked for
    again after every step (a handler may have cancelled it), and the loop ends when the
    document is no longer loading. }
  while FDoc.Loading do
  begin
    load := TyRichRtfLoadOf(FDoc);
    if load = nil then Break;
    if FCancelRequested then
    begin
      CancelLoad;
      Break;
    end;
    load.OnLoadProgress := @LoadProgress;
    FInStep := True;
    try
      load.Step(CRichFinishStepBytes);
    finally
      FInStep := False;
    end;
  end;
  if FCancelRequested then CancelLoad;
  // (pictures may be left; a turn that came inside the step did nothing)
  if HasBackgroundWork then StartBackground else StopBackground;
end;

procedure TTyCustomRichEdit.CancelLoad;
var
  load: TTyRtfLoad;
begin
  // from a progress handler: the step is running, the load stops when it has returned
  if FInStep then
  begin
    FCancelRequested := True;
    Exit;
  end;
  FCancelRequested := False;
  load := TyRichRtfLoadOf(FDoc);
  if (load = nil) or not FDoc.Loading then Exit;
  FInStep := True;
  FInCancel := True;
  try
    load.Cancel;
  finally
    FInCancel := False;
    FInStep := False;
  end;
  // (its notice reached them already when it changed a view: then this does nothing)
  CatchUpBars;
  if HasBackgroundWork then StartBackground else StopBackground;
end;

procedure TTyCustomRichEdit.WriteTo(AStream: TStream; AFormat: TTyRichFormat);
var
  life: TTyRichLife;
begin
  { A handler of a find's or a replace's events may free the control in here: then this
    returns, touching nothing of it (inside another call of the control, that one does). }
  LifeEnter(life);
  try
    try
      // a save asked for from a load progress handler would save a document still loading
      if FInStep then raise ETyRichEdit.Create(rsRichEditBusy);
      { A replace in the background stops (with its event): the saved point a save may set would
        keep its next batch out of its one undo step. }
      if FFindKind = rfkReplace then EndFind(rfsCancelled, True);
      FinishLoading;
      if FDoc.Incomplete then raise ETyRichEdit.Create(rsRichEditIncomplete);
      // the document's state decides, not where the content came from
      if AFormat = rfAuto then
        if FPlainText then AFormat := rfText else AFormat := rfRtf;
      // a document of ours names the font its plain text is shown in (RtfWrite's \f0), and
      // its size
      NameDocBase;
      Inc(FSaving);
      try
        if AFormat = rfText then
          TyRichSaveText(FDoc, AStream, @SaveProgress)
        else
        begin
          // the file's own first bytes, before the signature, as they came
          if Length(FRtfPrefix) > 0 then AStream.WriteBuffer(FRtfPrefix[0], Length(FRtfPrefix));
          TyRichSaveRtf(FDoc, AStream, @SaveProgress);
        end;
      finally
        Dec(FSaving);
        // a turn that came during the save did nothing
        if (FSaving = 0) and HasBackgroundWork then StartBackground;
      end;
    except
      on ETyRichGone do if TyRichGonePasses(life) then raise;
    end;
  finally
    if not life.Gone then LifeLeave(life);
  end;
end;

procedure TTyCustomRichEdit.SaveToStream(AStream: TStream; AFormat: TTyRichFormat);
begin
  // an export: Modified, SourceFile and SourceFormat stay as they are
  WriteTo(AStream, AFormat);
end;

{$IFDEF MSWINDOWS}
const
  REPLACEFILE_IGNORE_MERGE_ERRORS = 2;
  FILE_ATTRIBUTE_READONLY = 1;
  INVALID_FILE_ATTRIBUTES = DWord($FFFFFFFF);

function ReplaceFileW(AReplaced, AReplacement, ABackup: PWideChar; AFlags: DWord;
  AExclude, AReserved: Pointer): LongBool; stdcall; external 'kernel32' name 'ReplaceFileW';
function GetFileAttributesW(AName: PWideChar): DWord; stdcall;
  external 'kernel32' name 'GetFileAttributesW';
{$ENDIF}

{ The file a save writes: a symbolic link is followed (its target is replaced, the link
  stays), up to 32 links deep. }
function RealTarget(const AFileName: string): string;
var
  n, a: Integer;
  next: RawByteString;
begin
  Result := AFileName;
  for n := 1 to 32 do
  begin
    a := FileGetAttr(Result);
    if (a = -1) or ((a and faSymLink) = 0) then Exit;
    if not FileGetSymLinkTarget(RawByteString(Result), next) or (next = '') then Exit;
    // a relative target is relative to the link's folder
    if (ExtractFileDrive(next) = '') and not (next[1] in AllowDirectorySeparators) then
      next := ExtractFilePath(Result) + next;
    Result := ExpandFileName(next);
  end;
end;

{ The user may not write ATarget (it exists, write-protected): refused before anything is
  written. }
function TargetWriteProtected(const ATarget: string): Boolean;
{$IFDEF MSWINDOWS}
var
  a: DWord;
begin
  a := GetFileAttributesW(PWideChar(UnicodeString(ATarget)));
  Result := (a <> INVALID_FILE_ATTRIBUTES) and ((a and FILE_ATTRIBUTE_READONLY) <> 0);
end;
{$ELSE}
begin
  Result := FileExists(ATarget) and (fpAccess(ATarget, W_OK) <> 0);
end;
{$ENDIF}

{ Puts ASource in ATarget's place (ATarget may exist). What ATarget was stays: on Windows
  ReplaceFileW keeps its ACL, attributes, streams and creation time; elsewhere the new file is
  given the target's mode (and owner, where the process may) before rename(2) puts it there. A
  new target gets the defaults. }
function ReplaceFile(const ASource, ATarget: string): Boolean;
{$IFNDEF MSWINDOWS}
var
  st: TStat;
{$ENDIF}
{$IFDEF MSWINDOWS}
const
  ERROR_ACCESS_DENIED = 5;
  ERROR_SHARING_VIOLATION = 32;
var
  err: Integer;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  if FileExists(ATarget) then
  begin
    Result := TyRichReplaceFileW(PWideChar(UnicodeString(ATarget)),
      PWideChar(UnicodeString(ASource)), nil, REPLACEFILE_IGNORE_MERGE_ERRORS, nil, nil);
    if not Result then
    begin
      { Refused for the target's sake (no right to it, someone holds it): so it stays. Any other
        failure may be a volume that does not do ReplaceFileW (some network shares): the plain
        replace, which keeps less of what the target was but saves. }
      err := GetLastOSError;
      if (err <> ERROR_ACCESS_DENIED) and (err <> ERROR_SHARING_VIOLATION) then
        Result := MoveFileExW(PWideChar(UnicodeString(ASource)), PWideChar(UnicodeString(ATarget)),
          MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH);
    end;
  end
  else
    Result := MoveFileExW(PWideChar(UnicodeString(ASource)), PWideChar(UnicodeString(ATarget)),
      MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH);
  {$ELSE}
  if fpStat(ATarget, st) = 0 then
  begin
    { Owner first, then mode: chown(2) clears the set-user-id and set-group-id bits, which
      chmod then puts back. Only root may give a file away; another user's file keeps our
      ownership then. }
    fpChown(ASource, st.st_uid, st.st_gid);
    fpChmod(ASource, st.st_mode and &7777);
  end;
  // rename(2) replaces the target in one step
  Result := fpRename(ASource, ATarget) = 0;
  {$ENDIF}
end;

procedure TTyCustomRichEdit.SaveToFile(const AFileName: string; AFormat: TTyRichFormat);
var
  full, tmp, ext: string;
  fs: TFileStream;
  g: TGUID;
  keeps: Boolean;
var
  life: TTyRichLife;
begin
  { A handler of a find's or a replace's events may free the control in here: then this
    returns, touching nothing of it (inside another call of the control, that one does). }
  LifeEnter(life);
  try
    try
      full := RealTarget(ExpandFileName(AFileName));
      FinishLoading;
      if FDoc.Incomplete then raise ETyRichEdit.Create(rsRichEditIncomplete);
      { One rule: text when the application asked for it (PlainText := True), else the
        extension, else the document's state - never where the content came from, so that a
        text file opened, formatted and saved under .rtf is RTF. }
      if (AFormat = rfAuto) and FPlainText and FPlainTextAsked then AFormat := rfText;
      if AFormat = rfAuto then
      begin
        ext := LowerCase(ExtractFileExt(full));
        if ext = '.rtf' then AFormat := rfRtf
        else if ext = '.txt' then AFormat := rfText
        else if FPlainText then AFormat := rfText
        else AFormat := rfRtf;
      end;
      if TargetWriteProtected(full) then raise ETyRichEdit.CreateFmt(rsRichEditCannotWrite, [full]);
      { Beside the target, so that putting it in the target's place is a rename on one volume;
        the target - perhaps the very file the document reads from - is untouched until then. A
        GUID names it: no other file has that name, nobody guesses it. }
      CreateGUID(g);
      tmp := ExtractFilePath(full) + '.' + ExtractFileName(full) + '.' +
        Copy(GUIDToString(g), 2, 36) + '.tmp';
      try
        fs := TFileStream.Create(tmp, fmCreate or fmShareExclusive);
      except
        on EStreamError do raise ETyRichEdit.CreateFmt(rsRichEditCannotWrite, [full]);
      end;
      try
        try
          WriteTo(fs, AFormat);
          // on the disk before it takes the target's place
          FileFlush(fs.Handle);
        finally
          fs.Free;
        end;
      except
        SysUtils.DeleteFile(tmp);
        raise;
      end;
      if not ReplaceFile(tmp, full) then
      begin
        SysUtils.DeleteFile(tmp);
        raise ETyRichEdit.CreateFmt(rsRichEditCannotReplace, [full]);
      end;
      { The same answer decides whether the file is now the document's: RTF keeps any
        content; text keeps a plain-text document's - the text is what such a document is, its
        formats included (the caller asked for text: an explicit .txt, rfText or PlainText, the
        application's choice); a rich document saved as text is an export and stays Modified. }
      keeps := (AFormat = rfRtf) or ((AFormat = rfText) and FPlainText);
      if keeps then
      begin
        FDoc.Modified := False;
        FSourceFile := full;
        FSourceFormat := AFormat;
      end;
    except
      on ETyRichGone do if TyRichGonePasses(life) then raise;
    end;
  finally
    if not life.Gone then LifeLeave(life);
  end;
end;

{ ---- the kept surface ----

  The control keeps one bitmap of what it shows, frame and text, at the canvas's device scale
  (FSurfScale raster pixels per client pixel; the view is laid out at that scale too, so the
  text is drawn for the device, not stretched). A paint brings the surface up to date and
  copies the clip's part of it to the canvas.

  What is out of date is a small set of rectangles (FDirty, raster pixels; at most
  CRichDirtyMax: a rectangle that touches another joins it, and past the bound the new one
  joins the one it grows least - two far-apart lines stay two rectangles), or everything
  (FAllDirty: the frame and the text). Within the text, a dirty rectangle is filled with the
  theme's ground and the blocks that meet it are painted into it, clipped; anything outside the
  text (a bar came, the content was replaced) or a change of what the frame looks like (theme,
  state, size, scale) draws everything.

  A scroll moves the text's rows (or columns) inside the surface by what the layout pass found
  the view moved by (LayoutView: the same block on top, elsewhere) and dirties only the band
  it exposed; a move of the view's height or more, or with a layout change, draws everything.
  The window is invalidated for the text area and the paint blits it (no window scroll: the
  blit of the text area is a copy of memory, and the frame, the bars and RTL stay out of it).

  Units: the view's geometry (anchor offset, block tops and heights, the height index, the
  layout width, picture boxes, FScrollX) is in raster pixels; everything public or LCL-facing
  (ScrollY, TopOffset, ScrollX, HorizontalExtent, PositionAtPoint, PositionRect, ParagraphRect,
  VisibleBlocks, bar positions, invalidation rectangles) is in client pixels, rounded outward
  for rectangles. A scale change is a PPI change of the layout (heights unmeasured, anchor
  kept); it is known from the canvas when a paint comes, 1 before.

  The surface is made when the first paint needs it and released when the window goes
  (DestroyWnd): client size x scale squared x 4 bytes, rounded up to CRichSurfaceBlock. A theme
  ground that is not an opaque colour, or an opacity (a disabled control dims), is painted the
  other way instead - the painter's layer over the canvas, everything each paint. }

function TTyCustomRichEdit.ClientOf(const AArea: TRect; AL, AT, AR, AB: Int64): TRect;
const
  Lim = MaxInt div 2;

  function Fit(V: Int64): Integer;
  begin
    if V < -Lim then V := -Lim;
    if V > Lim then V := Lim;
    Result := Integer(V);
  end;

var
  s: Integer;
begin
  s := Math.Max(1, FScale);
  Result := Rect(Fit(AArea.Left + FloorDiv(AL, s)), Fit(AArea.Top + FloorDiv(AT, s)),
    Fit(AArea.Left + CeilDiv(AR, s)), Fit(AArea.Top + CeilDiv(AB, s)));
end;

function TTyCustomRichEdit.TextClipOf(const ARect, AArea: TRect; APPI: Integer): TRect;
var
  s: TTyStyleSet;
  sc, rppi, w, h, bw, ow, off, d: Integer;
  cr: TTyCorners;
  dTop, dBottom: Int64;

  function Px(V: Integer): Integer;
  begin
    Result := MulDiv(V, rppi, 96);
  end;

  { How far from its side edge a point ADy from the top (or bottom) edge must be to be clear
    of a ring of outer radius AR and width AW whose box is AX0 in from both edges (raster
    pixels; the inner arc taken a pixel smaller for its antialiasing). }
  function ClearOf(ADy: Int64; AX0, AR, AW: Integer): Int64;
  var
    c, ri, dy: Double;
  begin
    Result := 0;
    if AR <= 0 then Exit;
    c := AX0 + AR;
    if ADy >= c then Exit;
    ri := AR - AW - 1;
    dy := c - ADy;
    if (ri <= 0) or (dy >= ri) then Result := Ceil(c)
    else Result := Ceil(c - Sqrt(ri * ri - dy * dy));
  end;

  { ... of the frame at a corner of radius ARadius (logical): its border and its ring. }
  function CornerNeed(ADy: Int64; ARadius: Integer): Int64;
  begin
    Result := ClearOf(ADy, 0, TyClampRadiusPx(Px(ARadius), w, h), bw);
    if ow > 0 then
      Result := Math.Max(Result, ClearOf(ADy, Math.Max(0, off),
        TyClampRadiusPx(Px(Math.Max(0, ARadius - s.OutlineOffset)), w - 2 * off, h - 2 * off), ow));
  end;

begin
  Result := AArea;
  s := CurrentStyle;
  { Text may reach into the left padding (a table row's \trleft is usually negative: Word
    puts its lines in the margin) - never into what the frame inks: the surface fills and
    moves what is inside this rectangle, the frame is drawn only outside it. What the
    frame inks, as the painter draws it at the device scale: the border (render-style's 2 px
    when a 3D look gives none), the focus ring (outline offset + width), the pixel their
    antialiasing takes, and at a rounded corner the arcs and what lies outside them (the
    parent's fill, a shadow) - there the edge goes in as far as the arc reaches at the clip's
    top or bottom row. }
  if not (VBarShown and IsRightToLeft) then
    Result.Left := AArea.Left - MulDiv(s.Padding.Left, APPI, 96);
  sc := Math.Max(1, FScale);
  rppi := APPI * sc;
  w := (ARect.Right - ARect.Left) * sc;
  h := (ARect.Bottom - ARect.Top) * sc;
  if (tpRenderStyle in s.Present) and (s.RenderStyle <> trsFlat) and
    not (tpBorderWidth in s.Present) then
    bw := Px(2)
  else
    bw := Px(Math.Max(0, s.BorderWidth));
  ow := 0;
  off := 0;
  if (tpOutline in s.Present) and (s.OutlineWidth > 0) then
  begin
    ow := Px(s.OutlineWidth);
    off := MulDiv(s.OutlineOffset, APPI, 96) * sc;
  end;
  d := Math.Max(bw, Math.Max(0, off + ow));
  d := Integer(CeilDiv(d, sc)) + 1;
  Result.Left := Math.Max(Result.Left, ARect.Left + d);
  Result.Top := Math.Max(Result.Top, ARect.Top + d);
  Result.Right := Math.Min(Result.Right, ARect.Right - d);
  Result.Bottom := Math.Min(Result.Bottom, ARect.Bottom - d);
  cr := TyEffectiveCorners(s);
  dTop := Int64(Result.Top - ARect.Top) * sc;
  dBottom := Int64(ARect.Bottom - Result.Bottom) * sc;
  Result.Left := Math.Max(Result.Left, ARect.Left +
    Integer(CeilDiv(Math.Max(CornerNeed(dTop, cr.TL), CornerNeed(dBottom, cr.BL)), sc)));
  Result.Right := Math.Min(Result.Right, ARect.Right -
    Integer(CeilDiv(Math.Max(CornerNeed(dTop, cr.TR), CornerNeed(dBottom, cr.BR)), sc)));
  if Result.Left > Result.Right then Result.Left := Result.Right;
  if Result.Top > Result.Bottom then Result.Top := Result.Bottom;
end;

function TTyCustomRichEdit.TextWindowRect: TRect;
var
  area: TRect;
begin
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  Result := TextClipOf(Rect(0, 0, Width, Height), area, ViewPPI);
end;

procedure TTyCustomRichEdit.InvalidateTextRect(AL, AT, AR, AB: Int64);
begin
  TextRectChanged(AL, AT, AR, AB, True, True);
end;

procedure TTyCustomRichEdit.TextRectChanged(AL, AT, AR, AB: Int64; ADirty, AWindow: Boolean);
var
  area, clip, r: TRect;
  s: Integer;
  cl, cr: Int64;
begin
  s := Math.Max(1, FScale);
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  clip := TextClipOf(Rect(0, 0, Width, Height), area, ViewPPI);
  // within the text clip and the view
  cl := Int64(clip.Left - area.Left) * s;
  cr := Int64(clip.Right - area.Left) * s;
  if AL < cl then AL := cl;
  if AR > cr then AR := cr;
  if AT < 0 then AT := 0;
  if AB > FViewH then AB := FViewH;
  if (AR <= AL) or (AB <= AT) then Exit;
  if ADirty then
    MarkDirty(Rect(Integer(area.Left * s + AL), Integer(area.Top * s + AT),
      Integer(area.Left * s + AR), Integer(area.Top * s + AB)));
  if AWindow then
  begin
    r := ClientOf(area, AL, AT, AR, AB);
    InvalidateArea(r);
  end;
end;

{ A band of the view, across the text (raster, relative to the text area's top). }
procedure TTyCustomRichEdit.InvalidateBand(ATop, ABottom: Int64);
begin
  InvalidateTextRect(-High(Integer), ATop, High(Integer), ABottom);
end;

procedure TTyCustomRichEdit.InvalidateContent(const ARect: TRect);
var
  s: Integer;
  r: TRect;
begin
  // clipped first, scaled after: nothing outside the text is content, and what is inside it
  // times the scale is in range whatever ARect was
  if not IntersectRect(r, ARect, TextWindowRect) then Exit;
  s := Math.Max(1, FScale);
  MarkDirty(Rect(r.Left * s, r.Top * s, r.Right * s, r.Bottom * s));
  InvalidateArea(r);
end;

procedure TTyCustomRichEdit.InvalidateArea(const ARect: TRect);
var
  r: TRect;
begin
  if not HandleAllocated then Exit;
  r := ARect;
  LCLIntf.InvalidateRect(Handle, @r, False);
end;

procedure TTyCustomRichEdit.InvalidateSurface;
begin
  FAllDirty := True;
  FDirtyCount := 0;
end;

procedure TTyCustomRichEdit.MarkDirty(const ARect: TRect);

  function Area(const R: TRect): Int64;
  begin
    Result := Int64(R.Right - R.Left) * (R.Bottom - R.Top);
  end;

var
  r, u: TRect;
  i, best: Integer;
  grow, bestGrow: Int64;
begin
  // no surface yet, or everything to draw anyway
  if (FSurface = nil) or FAllDirty then Exit;
  r := ARect;
  if (r.Right <= r.Left) or (r.Bottom <= r.Top) then Exit;
  // a rectangle that touches or overlaps the new one joins it (and so on, as it grows)
  i := 0;
  while i < FDirtyCount do
    if (r.Left <= FDirty[i].Right) and (FDirty[i].Left <= r.Right) and
      (r.Top <= FDirty[i].Bottom) and (FDirty[i].Top <= r.Bottom) then
    begin
      UnionRect(r, r, FDirty[i]);
      FDirty[i] := FDirty[FDirtyCount - 1];
      Dec(FDirtyCount);
      i := 0;
    end
    else
      Inc(i);
  if FDirtyCount = CRichDirtyMax then
  begin
    // full: the new one joins the rectangle it grows least
    best := 0;
    bestGrow := High(Int64);
    for i := 0 to FDirtyCount - 1 do
    begin
      UnionRect(u, r, FDirty[i]);
      grow := Area(u) - Area(FDirty[i]) - Area(r);
      if grow < bestGrow then
      begin
        bestGrow := grow;
        best := i;
      end;
    end;
    UnionRect(r, r, FDirty[best]);
    FDirty[best] := FDirty[FDirtyCount - 1];
    Dec(FDirtyCount);
  end;
  FDirty[FDirtyCount] := r;
  Inc(FDirtyCount);
end;

procedure TTyCustomRichEdit.MarkTextDirty;
var
  area, clip: TRect;
  s: Integer;
begin
  s := Math.Max(1, FScale);
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  clip := TextClipOf(Rect(0, 0, Width, Height), area, ViewPPI);
  MarkDirty(Rect(clip.Left * s, clip.Top * s, clip.Right * s, clip.Bottom * s));
end;

{ ARect (raster pixels of the view) where the pixels it covers go when the text on the surface
  moves ADX, ADY - all of it, or (AFrom) only from that row down: one that straddles that row is
  split by the move, so both its places are drawn again and it is known nowhere (empty). }
procedure TTyCustomRichEdit.MoveOverlay(var ARect: TRect; ADX, ADY, AFrom: Int64);
begin
  if IsRectEmpty(ARect) then Exit;
  if ADX <> 0 then Types.OffsetRect(ARect, Integer(ADX), 0);
  if ADY = 0 then Exit;
  if (AFrom = Low(Int64)) or (ARect.Top >= AFrom) then
    Types.OffsetRect(ARect, 0, Integer(ADY))
  else if ARect.Bottom > AFrom then
  begin
    InvalidateTextRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom);
    InvalidateTextRect(ARect.Left, ARect.Top + ADY, ARect.Right, ARect.Bottom + ADY);
    ARect := Rect(0, 0, 0, 0);
  end;
end;

procedure TTyCustomRichEdit.MoveSurfaceText(ADX, ADY: Int64; AFrom: Int64);
var
  area, clip, R, d: TRect;
  kept: array[0..2 * CRichDirtyMax - 1] of TRect;
  s, y, w, i, n, dx, dy, lo, hi, first, row0: Integer;
  top64, lo64, hi64, first64: Int64;
  pix: PBGRAPixel;
begin
  // the handles and the outline on the surface go with its pixels
  MoveOverlay(FHandleRect, ADX, ADY, AFrom);
  MoveOverlay(FPreviewRect, ADX, ADY, AFrom);
  MoveOverlay(FDropRect, ADX, ADY, AFrom);
  if (FSurface = nil) or FAllDirty then Exit;
  s := Math.Max(1, FScale);
  if (FSurfW <> Width) or (FSurfH <> Height) or (FSurfScale <> s) then
  begin
    InvalidateSurface;
    Exit;
  end;
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  clip := TextClipOf(Rect(0, 0, Width, Height), area, ViewPPI);
  R := Rect(clip.Left * s, clip.Top * s, clip.Right * s, clip.Bottom * s);
  if ADX <> 0 then
  begin
    // across: the whole text alone (a move both ways, or of a part of it, is drawn again)
    if (ADY <> 0) or (AFrom <> Low(Int64)) or (Abs(ADX) >= R.Right - R.Left) then
    begin
      MarkDirty(R);
      Exit;
    end;
    dx := Integer(ADX);
    w := R.Right - R.Left;
    for y := R.Top to R.Bottom - 1 do
    begin
      pix := FSurface.ScanLine[y] + R.Left;
      // Move copies overlapping ranges as memmove does
      if dx > 0 then Move(pix^, (pix + dx)^, (w - dx) * SizeOf(TBGRAPixel))
      else Move((pix - dx)^, pix^, (w + dx) * SizeOf(TBGRAPixel));
    end;
    FSurface.InvalidateBitmap;
    for i := 0 to FDirtyCount - 1 do
    begin
      Types.OffsetRect(FDirty[i], dx, 0);
      if not IntersectRect(FDirty[i], FDirty[i], R) then FDirty[i] := Rect(0, 0, 0, 0);
    end;
    FSurfScrollX := FScrollX;
    if dx > 0 then MarkDirty(Rect(R.Left, R.Top, R.Left + dx, R.Bottom))
    else MarkDirty(Rect(R.Right + dx, R.Top, R.Right, R.Bottom));
    Exit;
  end;
  if ADY = 0 then Exit;
  // the first surface row that moves (the clip's top for the whole text)
  if AFrom = Low(Int64) then top64 := R.Top else top64 := Int64(area.Top) * s + AFrom;
  { What may be stale from the move on: from where the moving part was or now begins, down.
    Above it nothing changes. Nothing of it in the clip: nothing on screen moves. }
  first64 := Math.Max(Int64(R.Top), Math.Min(top64, top64 + ADY));
  if first64 >= R.Bottom then Exit;
  first := Integer(first64);
  row0 := Integer(Math.Max(Int64(R.Top) - 1, Math.Min(top64, Int64(R.Bottom))));
  { The rows that get valid pixels: the moving part's rows that are in the clip, where they
    land in it. }
  lo64 := Math.Max(Math.Max(top64, Int64(R.Top)) + ADY, Int64(R.Top));
  hi64 := Math.Min(Int64(R.Bottom) + ADY, Int64(R.Bottom));
  if lo64 >= hi64 then
  begin
    // nothing of it lands in the clip: all is stale from first down
    lo := R.Bottom;
    hi := R.Bottom;
    dy := 0;
  end
  else
  begin
    lo := Integer(lo64);
    hi := Integer(hi64);
    dy := Integer(ADY);
    w := R.Right - R.Left;
    if dy > 0 then
      // down: from the bottom up, each row from dy above it
      for y := hi - 1 downto lo do
        Move((FSurface.ScanLine[y - dy] + R.Left)^, (FSurface.ScanLine[y] + R.Left)^,
          w * SizeOf(TBGRAPixel))
    else
      // up: from the top down, each row from -dy below it
      for y := lo to hi - 1 do
        Move((FSurface.ScanLine[y - dy] + R.Left)^, (FSurface.ScanLine[y] + R.Left)^,
          w * SizeOf(TBGRAPixel));
    FSurface.InvalidateBitmap;
  end;
  { The marks: above the moving part they stay; from it down they go where its pixels went
    (what lands outside the moved rows is in a stale band, marked below). A mark outside the
    text clip (the frame) is not the text's: it stays. }
  n := 0;
  for i := 0 to FDirtyCount - 1 do
  begin
    d := FDirty[i];
    if (d.Right <= d.Left) or (d.Bottom <= d.Top) then Continue;
    if (d.Left < R.Left) or (d.Right > R.Right) or (d.Top < R.Top) or (d.Bottom > R.Bottom) then
    begin
      kept[n] := d;
      Inc(n);
      Continue;
    end;
    if d.Top < row0 then
    begin
      kept[n] := d;
      if kept[n].Bottom > row0 then kept[n].Bottom := row0;
      Inc(n);
    end;
    if (d.Bottom > row0) and (lo < hi) then
    begin
      if d.Top < row0 then d.Top := row0;
      Types.OffsetRect(d, 0, dy);
      if IntersectRect(d, d, Rect(R.Left, lo, R.Right, hi)) then
      begin
        kept[n] := d;
        Inc(n);
      end;
    end;
  end;
  FDirtyCount := 0;
  for i := 0 to n - 1 do MarkDirty(kept[i]);
  // the rows the move left stale: above what it filled, and below it
  if lo > first then MarkDirty(Rect(R.Left, first, R.Right, lo));
  if hi < R.Bottom then MarkDirty(Rect(R.Left, Math.Max(hi, first), R.Right, R.Bottom));
end;

function TTyCustomRichEdit.SurfaceUsable(const AStyle: TTyStyleSet): Boolean;
begin
  // the ground the text is drawn on, and what a dirty rectangle is filled with
  Result := (tpBackground in AStyle.Present) and (AStyle.Background.Kind = tfkSolid) and
    (TyAlphaOf(AStyle.Background.Color) = 255) and not (tpOpacity in AStyle.Present);
end;

function TTyCustomRichEdit.FrameSignature(APPI: Integer): Cardinal;
var
  st: TTyStyleSet;
  h: Cardinal;
  p: TTyProp;
  ps: TTyRichPaintStyle;
  cr: TTyCorners;
  fill: TTyFill;
  k: Integer;

  procedure Mix(AValue: Cardinal);
  begin
    // (FNV-1a: the product wraps around by design)
    {$PUSH}{$Q-}{$R-}
    h := (h xor AValue) * 16777619;
    {$POP}
  end;

  procedure MixPx(const APx: TBGRAPixel);
  begin
    Mix(Cardinal(APx.red) or (Cardinal(APx.green) shl 8) or (Cardinal(APx.blue) shl 16) or
      (Cardinal(APx.alpha) shl 24));
  end;

begin
  { What the frame and the ground LOOK like - everything they are drawn from that may change
    without a layout change: the resolved style values (theme, StyleOverride, and through
    them the state: a hover or a focus that changes nothing of these changes nothing here),
    what lies outside a rounded corner (the parent's fill, and the control's place in it when
    it is not one colour), the paint style's colours (the selection follows the focus), the
    bars, the PPI. Never the states themselves: a press that looks like the normal
    state draws nothing. }
  st := CurrentStyle;
  h := 2166136261;
  for p := Low(TTyProp) to High(TTyProp) do
    if p in st.Present then Mix(Ord(p) + 1);
  Mix(Cardinal(st.Background.Color));
  Mix(Ord(st.Background.Kind));
  Mix(Cardinal(st.BorderColor));
  Mix(Cardinal(st.BorderWidth));
  Mix(Ord(st.BorderStyle));
  Mix(Ord(st.RenderStyle));
  Mix(Cardinal(st.BorderRadius));
  Mix(Cardinal(st.Radius.TL));
  Mix(Cardinal(st.Radius.TR));
  Mix(Cardinal(st.Radius.BR));
  Mix(Cardinal(st.Radius.BL));
  Mix(Cardinal(st.OutlineColor));
  Mix(Cardinal(st.OutlineWidth));
  Mix(Cardinal(st.OutlineOffset));
  Mix(Cardinal(st.ShadowColor));
  Mix(Cardinal(st.ShadowBlur));
  Mix(Cardinal(st.ShadowOffset.X));
  Mix(Cardinal(st.ShadowOffset.Y));
  if tpOpacity in st.Present then Mix(Cardinal(Round(st.Opacity * 1000)));
  Mix(Cardinal(st.Padding.Left));
  Mix(Cardinal(st.Padding.Top));
  Mix(Cardinal(st.Padding.Right));
  Mix(Cardinal(st.Padding.Bottom));
  { The base font the text is laid out in (CheckLayoutParams reads the current style, so a
    state's font-size or font-family takes effect): a state that changes it is a layout
    change, which the paint then does. }
  Mix(Cardinal(ResolveFontSize(st)));
  // (the weight and the style flags it carries: the base font's style)
  Mix(Cardinal(st.FontWeight));
  Mix(Cardinal(Length(st.FontName)));
  for k := 1 to Length(st.FontName) do Mix(Ord(st.FontName[k]));
  cr := TyEffectiveCorners(st);
  if (cr.TL > 0) or (cr.TR > 0) or (cr.BR > 0) or (cr.BL > 0) or (tpShadow in st.Present) then
  begin
    if TyResolveParentBgFill(Self, Rect(0, 0, Width, Height), fill) then
    begin
      Mix(Ord(fill.Kind));
      Mix(Cardinal(fill.Color));
      if fill.Kind <> tfkSolid then
      begin
        Mix(Cardinal(fill.GradFrom));
        Mix(Cardinal(fill.GradTo));
        for k := 0 to High(fill.GradStops) do Mix(Cardinal(fill.GradStops[k].Color));
        Mix(Cardinal(Round(fill.GradAngleDeg * 100)));
        Mix(Cardinal(Length(fill.ImagePath)));
        for k := 1 to Length(fill.ImagePath) do Mix(Ord(fill.ImagePath[k]));
        // a slice of a sweep or a picture: where the control is in it
        Mix(Cardinal(Left));
        Mix(Cardinal(Top));
      end;
    end
    else
      Mix($FFFF);
  end;
  ps := Default(TTyRichPaintStyle);
  FillPaintStyle(ps);
  MixPx(ps.TextColor);
  MixPx(ps.SelectionBack);
  MixPx(ps.SelectionText);
  MixPx(ps.ObjectFrame);
  MixPx(ps.ObjectHandleFill);
  MixPx(ps.PlaceholderFill);
  MixPx(ps.PlaceholderFrame);
  // the document's own ground replaces the theme's under the text
  Mix(Ord(ps.HasGround));
  if ps.HasGround then Mix(Cardinal(ps.Ground));
  Mix(Ord(VBarShown));
  Mix(Ord(HBarShown));
  Mix(Ord(IsRightToLeft));
  Mix(Cardinal(APPI));
  Result := h;
end;

procedure TTyCustomRichEdit.EnsureSurface(AW, AH, AScale: Integer);
var
  bw, bh: Integer;
begin
  // in blocks: a resize by a few pixels keeps the bitmap; never larger than a block past it
  bw := (Math.Max(1, AW) * AScale + CRichSurfaceBlock - 1) div CRichSurfaceBlock * CRichSurfaceBlock;
  bh := (Math.Max(1, AH) * AScale + CRichSurfaceBlock - 1) div CRichSurfaceBlock * CRichSurfaceBlock;
  if (FSurface = nil) or (FSurface.Width <> bw) or (FSurface.Height <> bh) or
    (AScale <> FSurfScale) then
  begin
    FreeAndNil(FSurface);
    FSurface := TBGRABitmap.Create(bw, bh);
    FSurfScale := AScale;
    InvalidateSurface;
  end;
  if (AW <> FSurfW) or (AH <> FSurfH) then
  begin
    FSurfW := AW;
    FSurfH := AH;
    InvalidateSurface;
  end;
end;

procedure TTyCustomRichEdit.DestroyWnd;
begin
  // the input method's composition and hook are the window's: they go before it
  EndComposition(False);
  TyImeUninstall(FImeHook);
  FImePlaced := Rect(0, 0, 0, 0);
  // the system lets go of the window before it goes (a new one is registered again)
  RevokeDropRegistration;
  inherited DestroyWnd;
  // the window is gone: what it showed is drawn again when it comes back, and the background
  // work waits for it (InitializeWnd starts it again) or for FinishLoading
  FreeAndNil(FSurface);
  InvalidateSurface;
  StopBackground;
  { A find or a replace in the background waits for the window, as the load does
    (InitializeWnd starts the driver again): RecreateWnd - a border style, a parent, BiDi -
    does not end it. }
  FreeAndNil(FTurnTimer);
  FreeAndNil(FBackstop);
  // the blink and a drag's scrolling are a window's (DoEnter starts the blink again)
  FreeAndNil(FBlinkTimer);
  StopDrag;
  FreeAndNil(FDragTimer);
  FCaretDrawn := Rect(0, 0, 0, 0);
end;

procedure TTyCustomRichEdit.PaintSurfaceFrame(APPI: Integer);
var
  P: TTyPainter;
  sc: TTyCanvasScale;
  s: TTyStyleSet;
  area, clip: TRect;
  bands: array[0..3] of TRect;
  i, k: Integer;
begin
  s := CurrentStyle;
  k := FSurfScale;
  area := TextArea(Rect(0, 0, FSurfW, FSurfH), APPI);
  clip := TextClipOf(Rect(0, 0, FSurfW, FSurfH), area, APPI);
  clip := Rect(clip.Left * k, clip.Top * k, clip.Right * k, clip.Bottom * k);
  { Inside the text clip the frame is its ground and nothing else (SurfaceUsable): filled at
    once. The frame itself is drawn only in the four bands around it - the painter fills
    the whole rectangle, and most of a full redraw's time went there. }
  FSurface.FillRect(clip.Left, clip.Top, clip.Right, clip.Bottom,
    TyColorToBGRA(s.Background.Color), dmSet);
  bands[0] := Rect(0, 0, FSurface.Width, clip.Top);
  bands[1] := Rect(0, clip.Bottom, FSurface.Width, FSurface.Height);
  bands[2] := Rect(0, clip.Top, clip.Left, clip.Bottom);
  bands[3] := Rect(clip.Right, clip.Top, FSurface.Width, clip.Bottom);
  for i := 0 to 3 do
  begin
    if (bands[i].Right <= bands[i].Left) or (bands[i].Bottom <= bands[i].Top) then Continue;
    FSurface.ClipRect := bands[i];
    FSurface.FillRect(bands[i], TyColorToBGRA(s.Background.Color), dmSet);
    P := TTyPainter.Create;
    try
      // no canvas: the frame is drawn on the surface at its scale, nothing is blitted
      sc.Scale := FSurfScale;
      sc.DeviceUnits := False;
      P.BeginPaintOnScaled(nil, Rect(0, 0, FSurfW, FSurfH), APPI, FSurface, sc);
      DrawFrame(P, Rect(0, 0, FSurfW, FSurfH), s);
      P.EndPaint;
    finally
      P.Free;
      FSurface.NoClip;
    end;
  end;
end;

procedure TTyCustomRichEdit.PaintBlock(ABitmap: TBGRABitmap; AIndex, AX, AY: Integer;
  const AClip: TRect; const AStyle: TTyRichPaintStyle);
var
  t: TTyRichText;
  start, stop, a, b: TTyRichPos;
  area: TTyRichCellArea;
  rl: TTyRowLayout;
  c: TTyRichCell;
  lit: array of Boolean;
  i: Integer;
begin
  // the block's part of the selection, block-relative (past its last place: its separator)
  a := 0;
  b := 0;
  // a row whose cells are selected: those cells whole, and no text selection in it
  if (FCaret <> FSelAnchor) and (FBlocks[AIndex].Layout is TTyRowLayout) then
  begin
    area := CellArea;
    if area.Range.InTable and (FBlocks[AIndex].FirstPara >= area.FirstPara) and
       (FBlocks[AIndex].LastPara <= area.LastPara) then
    begin
      rl := TTyRowLayout(FBlocks[AIndex].Layout);
      FDoc.BeginRead;
      try
        c := FDoc.CellAt(FBlocks[AIndex].FirstPara);
        lit := nil;
        SetLength(lit, rl.CellCount);
        for i := 0 to High(lit) do lit[i] := (c <> nil) and TyRichCellInArea(area, c.Row, i);
      finally
        FDoc.EndRead;
      end;
      Inc(FCellRowsPainted);
      rl.SetCellHighlight(lit);
      try
        rl.Paint(ABitmap, AX, AY, AClip, AStyle, 0, 0);
      finally
        rl.SetCellHighlight([]);
      end;
      Exit;
    end;
  end;
  if FCaret <> FSelAnchor then
  begin
    t := FDoc.Text;
    start := t.ParaStart(FBlocks[AIndex].FirstPara);
    stop := t.ParaStart(FBlocks[AIndex].LastPara) + t.ParaLength(FBlocks[AIndex].LastPara);
    a := Math.Max(GetSelStart - start, 0);
    b := Math.Min(GetSelStart + GetSelLength - start, stop - start + 1);
    { a row that shows a part of a cell merged from a row above: that cell's positions are
      before the row's own, the selection there too }
    if (FBlocks[AIndex].Layout is TTyRowLayout) and
       TTyRowLayout(FBlocks[AIndex].Layout).HasSpanSlices then
    begin
      a := GetSelStart - start;
      b := GetSelStart + GetSelLength - start;
    end;
    if b <= a then
    begin
      a := 0;
      b := 0;
    end;
  end;
  FBlocks[AIndex].Layout.Paint(ABitmap, AX, AY, AClip, AStyle, a, b);
end;

{ The pictures the last block painted passed over (a deferred paint): left for the background
  work. }
procedure TTyCustomRichEdit.QueueSkipped(ABlock: Integer);
var
  skipped: TTyRichSkippedPictures;
  j: Integer;
  box: TRect;
begin
  if FLayouter.SkippedPictureCount = 0 then Exit;
  skipped := FLayouter.TakeSkippedPictures;
  for j := 0 to High(skipped) do
  begin
    box := skipped[j].Box;
    QueuePicture(skipped[j].Picture, box.Right - box.Left, box.Bottom - box.Top,
      FBlocks[ABlock].FirstPara, FBlocks[ABlock].LastPara, True);
  end;
end;

procedure TTyCustomRichEdit.RedrawSurface(APPI: Integer; ADefer: Boolean);
var
  area, clip, rArea, rClip, R: TRect;
  regs: array of TRect;
  n, i, k, s, x, reach: Integer;
  y: Int64;
  full: Boolean;
  pst: TTyRichPaintStyle;
  ground: TBGRAPixel;
begin
  s := FSurfScale;
  area := TextArea(Rect(0, 0, FSurfW, FSurfH), APPI);
  clip := TextClipOf(Rect(0, 0, FSurfW, FSurfH), area, APPI);
  rArea := Rect(area.Left * s, area.Top * s, area.Right * s, area.Bottom * s);
  rClip := Rect(clip.Left * s, clip.Top * s, clip.Right * s, clip.Bottom * s);
  if FSurfScrollX <> FScrollX then MarkDirty(rClip);
  { The handles and a resize's outline where the view has them now: their old place and
    their new one are drawn again. }
  SyncObjectOverlay;
  full := FAllDirty;
  // a dirty part outside the text: the frame is drawn again, so is everything
  for i := 0 to FDirtyCount - 1 do
    if (FDirty[i].Right > FDirty[i].Left) and ((FDirty[i].Left < rClip.Left) or
      (FDirty[i].Top < rClip.Top) or (FDirty[i].Right > rClip.Right) or
      (FDirty[i].Bottom > rClip.Bottom)) then full := True;
  regs := nil;
  n := 0;
  if not full then
  begin
    SetLength(regs, FDirtyCount);
    for i := 0 to FDirtyCount - 1 do
      if IntersectRect(R, FDirty[i], rClip) then
      begin
        regs[n] := R;
        Inc(n);
      end;
  end;
  { The marks are cleared once what they mark is drawn: a drawing that raises (a block's paint,
    the frame's) leaves everything to be drawn again by the next paint - never stale
    pixels marked clean. }
  try
    if full then
    begin
      PaintSurfaceFrame(APPI);
      SetLength(regs, 1);
      regs[0] := rClip;
      n := 1;
    end;
    if n > 0 then
    begin
      FillPaintStyle(pst);
      pst.DeferPictures := ADefer;
      ground := TyColorToBGRA(CurrentStyle.Background.Color);
      // the document's own ground in place of the theme's, under the text (the frame stays)
      if pst.HasGround then
      begin
        ground := ColorToBGRA(ColorToRGB(pst.Ground));
        if full then FSurface.FillRect(rClip.Left, rClip.Top, rClip.Right, rClip.Bottom, ground,
          dmSet);
      end;
      { A block's ink may reach past its box (a descender, an italic, a picture frame): the
        blocks next to a region are painted into it too (clipped), as a full redraw would leave
        them. A paragraph spaced below one line inks outside its box (its glyphs are drawn
        whole over the lines next to it); the handles of a selected picture, which reach past its line, are drawn
        over all the blocks afterwards (PaintObjectOverlay). }
      reach := Math.Max(1, FEstimate);
      FLayouter.BeginPaintPass;
      x := rArea.Left - FScrollX;
      try
        for i := 0 to n - 1 do
        begin
          R := regs[i];
          if not full then FSurface.FillRect(R.Left, R.Top, R.Right, R.Bottom, ground, dmSet);
          FSurface.ClipRect := R;
          for k := 0 to FBlockCount - 1 do
          begin
            y := rArea.Top + FBlocks[k].Top;
            if (y >= R.Bottom + reach) or (y + FBlocks[k].Height <= R.Top - reach) then Continue;
            // it meets the region: its top is within a block's height of it, an Integer
            PaintBlock(FSurface, k, x, Integer(y), R, pst);
            if ADefer then QueueSkipped(k);
          end;
          // over every block: the handles reach past the object's line
          PaintObjectOverlay(FSurface, rArea.Left, rArea.Top, R, pst);
          PaintTableHandle(FSurface, rArea.Left, rArea.Top, R, pst);
          FSurface.NoClip;
        end;
      finally
        FSurface.NoClip;
      end;
    end;
  except
    InvalidateSurface;
    raise;
  end;
  FAllDirty := False;
  FDirtyCount := 0;
  FSurfScrollX := FScrollX;
end;

{$IFDEF LCLWin32}
type
  TTyRichDibHeader = packed record
    biSize: LongWord;
    biWidth, biHeight: LongInt;
    biPlanes, biBitCount: Word;
    biCompression, biSizeImage: LongWord;
    biXPelsPerMeter, biYPelsPerMeter: LongInt;
    biClrUsed, biClrImportant: LongWord;
  end;

function TyRichStretchDIBits(ADC: HDC; AXDest, AYDest, ADestW, ADestH, AXSrc, AYSrc, ASrcW,
  ASrcH: LongInt; ABits: Pointer; const AInfo: TTyRichDibHeader; AUsage, ARop: LongWord): LongInt;
  stdcall; external 'gdi32' name 'StretchDIBits';
function TyRichSetDIBitsToDevice(ADC: HDC; AXDest, AYDest: LongInt; AW, AH: LongWord;
  AXSrc, AYSrc: LongInt; AStartScan, AScanLines: LongWord; ABits: Pointer;
  const AInfo: TTyRichDibHeader; AUsage: LongWord): LongInt;
  stdcall; external 'gdi32' name 'SetDIBitsToDevice';
{$ENDIF}

{ The surface's APart (client pixels) to the canvas at (ADstX, ADstY), the Terminal's way: Win32
  straight from the bitmap's DIB with a source offset (no copy); elsewhere TyDrawOpaquePart (a
  Cocoa window: one copy handed to CG) or BGRA's DrawPart. 1:1 at scale 1 or on a canvas in
  device units; into the client rectangle on one in client units (a Retina window: the system
  puts each client pixel back on S device pixels). }
procedure TTyCustomRichEdit.BlitSurface(ACanvas: TCanvas; const APart: TRect; ADstX,
  ADstY: Integer; const AScale: TTyCanvasScale);
{$IFDEF LCLWin32}
const
  BI_RGB = 0;
  DIB_RGB_COLORS = 0;
  SRCCOPY = $00CC0020;
var
  info: TTyRichDibHeader;
  w, h, ySrc: Integer;
{$ELSE}
var
  piece: TBGRACustomBitmap;
{$ENDIF}
var
  s: Integer;
  src, dst: TRect;
begin
  s := Math.Max(1, FSurfScale);
  src := Rect(APart.Left * s, APart.Top * s, APart.Right * s, APart.Bottom * s);
  if (s = 1) or AScale.DeviceUnits then
    dst := Rect(ADstX * s, ADstY * s, ADstX * s + (src.Right - src.Left),
      ADstY * s + (src.Bottom - src.Top))
  else
    dst := Rect(ADstX, ADstY, ADstX + (APart.Right - APart.Left),
      ADstY + (APart.Bottom - APart.Top));
  {$IFDEF LCLWin32}
  w := src.Right - src.Left;
  h := src.Bottom - src.Top;
  if (w <= 0) or (h <= 0) then Exit;
  FillChar(info, SizeOf(info), 0);
  info.biSize := SizeOf(info);
  info.biWidth := FSurface.Width;
  info.biPlanes := 1;
  info.biBitCount := 32;
  info.biCompression := BI_RGB;
  if FSurface.LineOrder = riloBottomToTop then
  begin
    // a bottom-up DIB: the source rectangle's origin is its bottom left
    info.biHeight := FSurface.Height;
    ySrc := FSurface.Height - src.Bottom;
  end
  else
  begin
    info.biHeight := -FSurface.Height;
    ySrc := src.Top;
  end;
  if (dst.Right - dst.Left = w) and (dst.Bottom - dst.Top = h) then
    // 1:1: no stretch (measured faster than StretchDIBits for a whole screen)
    TyRichSetDIBitsToDevice(ACanvas.Handle, dst.Left, dst.Top, w, h, src.Left, ySrc, 0,
      FSurface.Height, FSurface.Data, info, DIB_RGB_COLORS)
  else
    TyRichStretchDIBits(ACanvas.Handle, dst.Left, dst.Top, dst.Right - dst.Left,
      dst.Bottom - dst.Top, src.Left, ySrc, w, h, FSurface.Data, info, DIB_RGB_COLORS, SRCCOPY);
  {$ELSE}
  if TyDrawOpaquePart(ACanvas, FSurface, src, dst) then Exit;
  if (dst.Right - dst.Left = src.Right - src.Left) and
    (dst.Bottom - dst.Top = src.Bottom - src.Top) then
    FSurface.DrawPart(src, ACanvas, dst.Left, dst.Top, True)
  else
  begin
    piece := FSurface.GetPart(src);
    try
      piece.Draw(ACanvas, dst, True);
    finally
      piece.Free;
    end;
  end;
  {$ENDIF}
end;

{ The other way, for a ground that is not an opaque colour or an opacity: the painter's layer for
  the clip, frame and text, everything each paint, laid over the canvas by EndPaint (which
  dims and blends). At the device scale too. }
procedure TTyCustomRichEdit.PaintLayer(ACanvas: TCanvas; const ARect, AClip: TRect;
  APPI: Integer; ADefer: Boolean; const AScale: TTyCanvasScale);
var
  P: TTyPainter;
  R, area, textClip, rClip: TRect;
  st: TTyRichPaintStyle;
  s, k, x, reach: Integer;
  y: Int64;
begin
  s := Math.Max(1, AScale.Scale);
  P := TTyPainter.Create;
  try
    P.BeginPaintScaled(ACanvas, AClip, APPI, AScale);
    R := Rect(ARect.Left - AClip.Left, ARect.Top - AClip.Top, ARect.Right - AClip.Left,
      ARect.Bottom - AClip.Top);
    DrawFrame(P, R, CurrentStyle);
    area := TextArea(R, APPI);
    textClip := TextClipOf(R, area, APPI);
    if IntersectRect(textClip, textClip, Rect(0, 0, AClip.Right - AClip.Left,
      AClip.Bottom - AClip.Top)) then
    begin
      rClip := Rect(textClip.Left * s, textClip.Top * s, textClip.Right * s, textClip.Bottom * s);
      P.PrepareTextGround(rClip);
      FillPaintStyle(st);
      st.DeferPictures := ADefer;
      if st.HasGround then
        P.Bitmap.FillRect(rClip.Left, rClip.Top, rClip.Right, rClip.Bottom,
          ColorToBGRA(ColorToRGB(st.Ground)), dmSet);
      P.Bitmap.ClipRect := rClip;
      reach := Math.Max(1, FEstimate);
      FLayouter.BeginPaintPass;
      try
        x := area.Left * s - FScrollX;
        for k := 0 to FBlockCount - 1 do
        begin
          y := Int64(area.Top) * s + FBlocks[k].Top;
          // the blocks next to the clip too: their ink may reach into it (see RedrawSurface)
          if (y >= rClip.Bottom + reach) or (y + FBlocks[k].Height <= rClip.Top - reach) then
            Continue;
          PaintBlock(P.Bitmap, k, x, Integer(y), rClip, st);
          if ADefer then QueueSkipped(k);
        end;
        PaintObjectOverlay(P.Bitmap, area.Left * s, area.Top * s, rClip, st);
        PaintTableHandle(P.Bitmap, area.Left * s, area.Top * s, rClip, st);
      finally
        P.Bitmap.NoClip;
      end;
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCustomRichEdit.PaintArea(ACanvas: TCanvas; const ARect, AClip: TRect;
  APPI: Integer; ADefer: Boolean);
var
  clip, tw: TRect;
  sc: TTyCanvasScale;
  sig: Cardinal;
begin
  if not IntersectRect(clip, AClip, ARect) then Exit;
  sc := TyCanvasDeviceScale(ACanvas);
  if sc.Scale < 1 then sc.Scale := 1;
  { Inside the document's update (the text changed, the view has not heard of it: its blocks
    may name paragraphs that are gone) nothing is laid out, drawn or asked: the paint shows
    the kept surface as it is - the last picture, which the change at EndUpdate brings up to
    date. With no surface yet (or one of another scale) it shows nothing. }
  if ViewBehind then
  begin
    // the window counts this paint as done: it is asked for again when the view hears
    if ADefer then FSkippedPaint := True;
    if (FSurface <> nil) and (FSurfScale = sc.Scale) and
      IntersectRect(clip, clip, Rect(ARect.Left, ARect.Top, ARect.Left + FSurfW,
      ARect.Top + FSurfH)) then
      BlitSurface(ACanvas, Rect(clip.Left - ARect.Left, clip.Top - ARect.Top,
        clip.Right - ARect.Left, clip.Bottom - ARect.Top), clip.Left, clip.Top, sc);
    Exit;
  end;
  // the layout follows the device: a new scale is a PPI change (CheckLayoutParams)
  FScale := sc.Scale;
  { A window paint (ADefer) whose clip holds the whole text area blits whatever the layout
    does to the view: no invalidation from inside it. A paint of a part, or RenderTo
    (which leaves the window as it was), still asks for the window's paint. }
  tw := TextWindowRect;
  FPaintCoversText := ADefer and (ARect.Left = 0) and (ARect.Top = 0) and
    (clip.Left <= tw.Left) and (clip.Top <= tw.Top) and (clip.Right >= tw.Right) and
    (clip.Bottom >= tw.Bottom);
  try
    EnsureView(APPI);
  finally
    FPaintCoversText := False;
  end;
  ClampScrollX;
  // a caret or an anchor a change moved: on a caret place before it is drawn
  if FSnapPending then SnapAfterChange;
  if not SurfaceUsable(CurrentStyle) then
  begin
    PaintLayer(ACanvas, ARect, clip, APPI, ADefer, sc);
    InvalidateSurface;
    { The kept frame signature is not this paint's: a state that leaves the layer path (a
      hover with an opacity ending) must paint again even when its look equals the one the
      surface was last drawn with. }
    FFrameSigValid := False;
  end
  else
  begin
    EnsureSurface(ARect.Right - ARect.Left, ARect.Bottom - ARect.Top, sc.Scale);
    sig := FrameSignature(APPI);
    if not FFrameSigValid or (sig <> FFrameSig) or (APPI <> FFrameSigPPI) then
    begin
      FFrameSig := sig;
      FFrameSigPPI := APPI;
      FFrameSigValid := True;
      InvalidateSurface;
    end;
    // RenderTo: a whole picture, its pictures decoded now
    if not ADefer then InvalidateSurface;
    RedrawSurface(APPI, ADefer);
    BlitSurface(ACanvas, Rect(clip.Left - ARect.Left, clip.Top - ARect.Top,
      clip.Right - ARect.Left, clip.Bottom - ARect.Top), clip.Left, clip.Top, sc);
  end;
  if FPendingCount > 0 then StartBackground;
end;

{ ---- cell selection ----

  Nothing but the anchor and the caret: tyControls.RichEdit.TableSel reads the cells off
  them (CellArea, kept until either moves or the document changes). }

const
  // the table zones TableZoneAt finds
  CZoneCell = 1;
  CZoneRow = 2;
  CZoneColumn = 3;
  CZoneTable = 4;

function TTyCustomRichEdit.SelectionAllowed: Boolean;
begin
  // a page whose text is not to be taken (AllowSelection False) shows no zone and no handle
  Result := FAllowSelection;
end;

function TTyCustomRichEdit.CellArea: TTyRichCellArea;
begin
  if not FCellAreaValid or (FCellAreaAnchor <> FSelAnchor) or (FCellAreaCaret <> FCaret) or
     (FCellAreaState <> FDoc.ContentState) then
  begin
    if ViewBehind or (FSelAnchor = FCaret) then FCellArea := Default(TTyRichCellArea)
    else FCellArea := TyRichCellArea(FDoc, FSelAnchor, FCaret);
    FCellAreaAnchor := FSelAnchor;
    FCellAreaCaret := FCaret;
    FCellAreaState := FDoc.ContentState;
    FCellAreaValid := True;
  end;
  Result := FCellArea;
end;

function TTyCustomRichEdit.SelectedCells: TTyRichCellRange;
var
  a: TTyRichCellArea;
begin
  a := CellArea;
  Result := a.Range;
  if Result.InTable then
  begin
    Result.LeftTwips := a.X0;
    Result.RightTwips := a.X1;
  end;
end;

function TTyCustomRichEdit.CaretCell(out ATablePos: TTyRichPos; out ARow, ACol: Integer): Boolean;
var
  k, n: Integer;
  c: TTyRichCell;
begin
  ATablePos := -1;
  ARow := -1;
  ACol := -1;
  if ViewBehind then Exit(False);
  k := CaretCellPara;
  FDoc.BeginRead;
  try
    c := FDoc.CellAt(k);
    if c = nil then Exit(False);
    ACol := c.Index;
  finally
    FDoc.EndRead;
  end;
  Result := FDoc.TableRowIndex(k, ARow, n);
  ATablePos := FDoc.Text.ParaStart(k);
end;

function TTyCustomRichEdit.TableGrid(ATablePos: TTyRichPos): TTyRichGrid;
begin
  Result := nil;
  if ViewBehind or (ATablePos < 0) or (ATablePos > FDoc.Text.Length) then Exit;
  Result := TyRichTableGrid(FDoc, ATablePos);
end;

{ The paragraph the caret's cell is read from - the table of this selection, the one every
  table door and its Can... answer go by: the caret's own, or - a selection running forward to
  a paragraph's start, as one of whole cells does (after the last cell's end mark) - the
  paragraph of the last selected character. When the selection is cells (a rectangle, whole
  rows, columns, the table, or rows reached from outside the table) a paragraph of those
  cells' rows: the caret's when it is one, else the last of them (a forward selection) or the
  first. }
function TTyCustomRichEdit.CanSelectCells: Boolean;
var
  k: Integer;
begin
  Result := False;
  if not SelectionAllowed or ViewBehind or not CaretParaRead then Exit;
  k := CaretCellPara;
  if (k < 0) or (k >= FDoc.Text.ParaCount) then Exit;
  FDoc.BeginRead;
  try
    Result := FDoc.CellAt(k) <> nil;
  finally
    FDoc.EndRead;
  end;
end;

function TTyCustomRichEdit.CanCut: Boolean;
var
  area: TTyRichCellArea;
begin
  Result := not FReadOnly and IsEnabled and not ViewBehind and (FSelAnchor <> FCaret);
  if not Result then Exit;
  area := CellArea;
  if area.Range.InTable and area.Outside then Result := False;
end;

function TTyCustomRichEdit.CanClearCells: Boolean;
begin
  Result := not FReadOnly and IsEnabled and not ViewBehind and TyRichCellsEditable(CellArea);
end;

function TTyCustomRichEdit.ClearCells: Boolean;
begin
  // the door of a user's edit: a composition goes in first
  EndCompositionForUser;
  Result := CanClearCells;
  if Result then ClearArea(CellArea);
end;

function TTyCustomRichEdit.CaretCellPara: Integer;
var
  t: TTyRichText;
  area: TTyRichCellArea;
  c: TTyRichCell;
begin
  t := FDoc.Text;
  Result := t.ParaOfPos(FCaret);
  if (FCaret > FSelAnchor) and (Result > 0) and (t.ParaStart(Result) = FCaret) then Dec(Result);
  if FCaret = FSelAnchor then Exit;
  area := CellArea;
  if not area.Range.InTable or (area.FirstPara < 0) then Exit;
  FDoc.BeginRead;
  try
    c := FDoc.CellAt(Result);
    if (c = nil) or (c.Table <> area.Table) or (Result < area.FirstPara) or
       (Result > area.LastPara) then
      if FCaret >= FSelAnchor then Result := area.LastPara else Result := area.FirstPara;
  finally
    FDoc.EndRead;
  end;
end;

// AKind: 0 the caret's cell, 1 its row, 2 its column, 3 its table
function TTyCustomRichEdit.SelectCells(AKind: Integer): Boolean;
var
  t: TTyRichText;
  k, f, l, rf, rl: Integer;
  c, d: TTyRichCell;
  info: TTyRichTableInfo;
  a, b: TTyRichPos;

  // the paragraphs of the cell of index ACol in the row paragraph APara is in (its last
  // cell when it has fewer)
  procedure CellOfRow(APara, ACol: Integer; out AF, AL: Integer);
  var
    p, q, j: Integer;
  begin
    TyRichRowParas(FDoc, APara, p, q);
    AF := -1;
    AL := -1;
    for j := p to q do
    begin
      d := FDoc.CellAt(j);
      if (d.Index = ACol) or ((AF < 0) and (j = q)) or ((AF < 0) and (d.Index > ACol)) then
      begin
        if AF < 0 then AF := j;
        if d.Index <> FDoc.CellAt(AF).Index then Break;
        AL := j;
      end;
    end;
  end;

begin
  Result := False;
  if not SelectionAllowed or ViewBehind then Exit;
  t := FDoc.Text;
  k := CaretCellPara;
  FDoc.BeginRead;
  try
    c := FDoc.CellAt(k);
    if c = nil then Exit;
    case AKind of
      0: TyRichCellParasOf(FDoc, k, f, l);
      1: TyRichRowParas(FDoc, k, f, l);
    else
      begin
        // a column or the whole table: the table's first and last row (one a loader gives
        // in parts, too large to be read whole, is not)
        if c.Table.Cut and (FDoc.TableEditRefusal(TyRichTableEdit(rtkInsertColumn, t.ParaStart(k),
          0)) = rtrNotWhole) then
        begin
          Refuse(rsRichEditRefusedSelectNotWhole, True);
          Exit;
        end;
        if not FDoc.TableInfoAt(k, info) then Exit;
        if AKind = 3 then
        begin
          f := info.First;
          l := info.Last;
        end
        else
        begin
          CellOfRow(info.First, c.Index, f, rl);
          CellOfRow(info.Last, c.Index, rf, l);
        end;
      end;
    end;
    if (f < 0) or (l < 0) then Exit;
    a := t.ParaStart(f);
    // after the last cell's end mark (the paragraph after it starts there)
    b := Math.Min(t.ParaStart(l) + t.ParaLength(l) + 1, t.Length);
  finally
    FDoc.EndRead;
  end;
  Select(a, b, False);
  FWishValid := False;
  CaretMoved;
  DoSelectionChange;
  Result := True;
end;

function TTyCustomRichEdit.SelectCell: Boolean;
begin
  Result := SelectCells(0);
end;

function TTyCustomRichEdit.SelectRow: Boolean;
begin
  Result := SelectCells(1);
end;

function TTyCustomRichEdit.SelectColumn: Boolean;
begin
  Result := SelectCells(2);
end;

function TTyCustomRichEdit.SelectTable: Boolean;
begin
  Result := SelectCells(3);
end;

{ The first cell of the area in reading order: its paragraphs. }
function TTyCustomRichEdit.FirstAreaCell(const AArea: TTyRichCellArea; out AFirst, ALast: Integer): Boolean;
var
  k, p, q: Integer;
  c: TTyRichCell;
begin
  AFirst := -1;
  ALast := -1;
  Result := False;
  if not AArea.Range.InTable then Exit;
  FDoc.BeginRead;
  try
    TyRichRowParas(FDoc, AArea.FirstPara, p, q);
    for k := p to q do
    begin
      c := FDoc.CellAt(k);
      if (c <> nil) and TyRichCellInArea(AArea, c.Row, c.Index) then
      begin
        if AFirst < 0 then AFirst := k
        else if FDoc.CellAt(AFirst) <> c then Break;
        ALast := k;
      end;
    end;
    Result := AFirst >= 0;
  finally
    FDoc.EndRead;
  end;
end;

// The rows of the area, and in each the cells in it, as calls of AVisit (cell paragraphs).
type
  TTyCellVisit = procedure(ARowNo, ACol, AFirst, ALast: Integer) of object;

{ Each cell of the area visited, row by row; the result: the rows left as they are because they
  hold a nested table. }
function VisitArea(ADoc: TTyRichDocument; const AArea: TTyRichCellArea; AVisit: TTyCellVisit): Integer;
var
  k, p, q, f, r: Integer;
  c, d: TTyRichCell;
begin
  Result := 0;
  k := AArea.FirstPara;
  r := 0;
  ADoc.BeginRead;
  try
    while (k >= 0) and (k <= AArea.LastPara) do
    begin
      TyRichRowParas(ADoc, k, p, q);
      c := ADoc.CellAt(p);
      // (a row that holds a nested table is its file's bytes: nothing of it changes)
      if c.Row.HoldsNestedTable then Inc(Result)
      else
      begin
        f := p;
        while f <= q do
        begin
          d := ADoc.CellAt(f);
          k := f;
          while (k < q) and (ADoc.CellAt(k + 1) = d) do Inc(k);
          if TyRichCellInArea(AArea, d.Row, d.Index) then AVisit(r, d.Index, f, k);
          f := k + 1;
        end;
      end;
      k := q + 1;
      Inc(r);
    end;
  finally
    ADoc.EndRead;
  end;
end;

type
  TTyCellSpan = record
    Row, Col: Integer;
    S, E: TTyRichPos;
  end;

  // what a walk over an area's cells gathers
  TTyCellGather = class
    Doc: TTyRichDocument;
    Edit: TTyRichCellsEdit;
    Comp: TTyRichCompositeCommand;
    Paras: Boolean;
    MaskC: TTyCharFormatMask;
    CharV: TTyCharFormat;
    Keep: TTyCharFormatMask;
    MaskP: TTyParaFormatMask;
    ParaV: TTyParaFormat;
    Cells: array of TTyCellSpan;
    procedure Clear(ARowNo, ACol, AFirst, ALast: Integer);
    procedure Format(ARowNo, ACol, AFirst, ALast: Integer);
    procedure Take(ARowNo, ACol, AFirst, ALast: Integer);
    procedure Span(ARowNo, ACol, AFirst, ALast: Integer);
  end;

procedure TTyCellGather.Span(ARowNo, ACol, AFirst, ALast: Integer);
begin
  SetLength(Cells, Length(Cells) + 1);
  Cells[High(Cells)].Row := AFirst;
  Cells[High(Cells)].Col := ALast;
end;

procedure TTyCustomRichEdit.AreaParaSpans(const AArea: TTyRichCellArea; out AFirst,
  ALast: TIntegerDynArray);
var
  g: TTyCellGather;
  i: Integer;
begin
  AFirst := nil;
  ALast := nil;
  g := TTyCellGather.Create;
  try
    g.Doc := FDoc;
    VisitArea(FDoc, AArea, @g.Span);
    SetLength(AFirst, Length(g.Cells));
    SetLength(ALast, Length(g.Cells));
    for i := 0 to High(g.Cells) do
    begin
      AFirst[i] := g.Cells[i].Row;
      ALast[i] := g.Cells[i].Col;
    end;
  finally
    g.Free;
  end;
end;

procedure TTyCellGather.Clear(ARowNo, ACol, AFirst, ALast: Integer);
begin
  Edit.AddClear(ARowNo, ACol);
end;

procedure TTyCellGather.Format(ARowNo, ACol, AFirst, ALast: Integer);
var
  s, e: TTyRichPos;
begin
  if Paras then
    Comp.Add(TTyRichSetParaFormat.Create(AFirst, ALast, MaskP, ParaV))
  else
  begin
    s := Doc.Text.ParaStart(AFirst);
    e := Doc.Text.ParaStart(ALast) + Doc.Text.ParaLength(ALast);
    if e > s then Comp.Add(TTyRichSetCharFormat.Create(TyRichRange(s, e - s), MaskC, CharV, Keep));
  end;
end;

procedure TTyCellGather.Take(ARowNo, ACol, AFirst, ALast: Integer);
var
  n: Integer;
begin
  n := Length(Cells);
  SetLength(Cells, n + 1);
  Cells[n].Row := ARowNo;
  Cells[n].Col := ACol;
  Cells[n].S := Doc.Text.ParaStart(AFirst);
  Cells[n].E := Doc.Text.ParaStart(ALast) + Doc.Text.ParaLength(ALast);
end;

function TTyCustomRichEdit.CellsAreTheSelection(AStart, ALen: TTyRichPos): Boolean;
begin
  Result := (ALen > 0) and (AStart = GetSelStart) and (ALen = GetSelLength) and
    TyRichCellsEditable(CellArea);
end;

function TTyCustomRichEdit.AreaCellCommand(const AArea: TTyRichCellArea; AParas: Boolean;
  AMaskC: TTyCharFormatMask; const AChar: TTyCharFormat; AKeep: TTyCharFormatMask;
  AMaskP: TTyParaFormatMask; const APara: TTyParaFormat): TTyRichCommand;
var
  g: TTyCellGather;
begin
  g := TTyCellGather.Create;
  try
    g.Doc := FDoc;
    g.Paras := AParas;
    g.MaskC := AMaskC;
    g.CharV := AChar;
    g.Keep := AKeep;
    g.MaskP := AMaskP;
    g.ParaV := APara;
    if AParas then g.Comp := TTyRichCompositeCommand.Create(rsRichUndoParaFormat)
    else g.Comp := TTyRichCompositeCommand.Create(rsRichUndoCharFormat);
    VisitArea(FDoc, AArea, @g.Format);
    Result := g.Comp;
  finally
    g.Free;
  end;
end;

procedure TTyCustomRichEdit.ClearArea(const AArea: TTyRichCellArea);
var
  g: TTyCellGather;
  place: TTyRichEditPlace;
  f, l, nested: Integer;
begin
  if not FirstAreaCell(AArea, f, l) then Exit;
  g := TTyCellGather.Create;
  try
    g.Doc := FDoc;
    g.Edit := TTyRichCellsEdit.Create(FDoc.Text.ParaStart(AArea.FirstPara), rsRichUndoDelete);
    nested := VisitArea(FDoc, AArea, @g.Clear);
    place := Default(TTyRichEditPlace);
    // the first cell's start: nothing before it moves
    place.Anchor := FDoc.Text.ParaStart(f);
    place.Caret := place.Anchor;
    RunMade(g.Edit, place, True);
  finally
    g.Free;
  end;
  // (rows that hold a nested table were left as they are: told once, as the format doors tell it)
  if nested > 0 then EditRefused(rsRichEditRefusedResizeNested);
end;

{ The area is whole columns: from the table's first row to its last. }
function TTyCustomRichEdit.AreaWholeColumns(const AArea: TTyRichCellArea): Boolean;
var
  info: TTyRichTableInfo;
begin
  Result := AArea.Range.InTable and not AArea.AllCells and (AArea.Range.Row0 = 0) and
    FDoc.TableInfoAt(AArea.FirstPara, info) and (AArea.Range.Row1 = info.RowCount - 1);
end;

function TTyCustomRichEdit.CellsKey(AForward: Boolean): Boolean;
var
  area: TTyRichCellArea;
begin
  area := CellArea;
  Result := TyRichCellsEditable(area);
  if not Result then Exit;
  if FReadOnly or not IsEnabled then Exit;
  if not AForward then
  begin
    { The rows go - and a bookmark one of whose marks goes with them loses its other mark too,
      in the same step: no lone mark is left. }
    if area.Range.WholeTable or TyRichAreaWholeRows(FDoc, area) then
    begin
      FTableThen := TyRichLoneMarksOutside(FDoc, area.FirstPara, area.LastPara);
      try
        if area.Range.WholeTable then DeleteTable else DeleteRow;
      finally
        FreeAndNil(FTableThen);
      end;
      Exit;
    end;
    // whole columns - every row of them: they go (Word's)
    if AreaWholeColumns(area) then
    begin
      DeleteColumn;
      Exit;
    end;
  end;
  ClearArea(area);
end;

{ The content [AStart, AStart + ALen) of this document as a document of its own (RTF there and
  back: formats, objects, fields - what a copy carries). }
function DocOfRange(ADoc: TTyRichDocument; AStart, ALen: TTyRichPos): TTyRichDocument;
var
  st: TBytesStream;
begin
  Result := TTyRichDocument.Create;
  st := TBytesStream.Create;
  try
    TyRichSaveRtfRange(ADoc, st, AStart, ALen);
    st.Position := 0;
    try
      TyRichLoadRtfFull(Result, st);
    except
      Result.Free;
      raise;
    end;
  finally
    st.Free;
  end;
end;

{ The merge the selection asks for (False: the selection is not cells of one table). }
function TTyCustomRichEdit.MergeEditOf(out AArea: TTyRichCellArea; out AEdit: TTyRichTableEdit): Boolean;
begin
  AArea := CellArea;
  AEdit := Default(TTyRichTableEdit);
  Result := TyRichCellsEditable(AArea);
  if not Result then Exit;
  AEdit := TyRichTableEdit(rtkMergeCells, FDoc.Text.ParaStart(AArea.FirstPara), AArea.Range.Row0);
  AEdit.Row0 := AArea.Range.Row0;
  AEdit.Row1 := AArea.Range.Row1;
  AEdit.X0 := Integer(AArea.X0);
  AEdit.X1 := Integer(AArea.X1);
end;

function TTyCustomRichEdit.CanMergeCells: Boolean;
var
  area: TTyRichCellArea;
  ed: TTyRichTableEdit;
  r: TTyRichTableRefusal;
begin
  Result := False;
  if not TableActionsOpen then Exit;
  if not MergeEditOf(area, ed) then Exit;
  // (the cells' content: the door moves it first)
  r := FDoc.TableEditRefusal(ed);
  Result := r in [rtrNone, rtrNotEmpty];
end;

function TTyCustomRichEdit.MergeCells: Boolean;
var
  area: TTyRichCellArea;
  ed: TTyRichTableEdit;
  r: TTyRichTableRefusal;
  g: TTyCellGather;
  i, filled: Integer;
  joined, part: TTyRichDocument;
  edit: TTyRichCellsEdit;
  comp: TTyRichCompositeCommand;
  place: TTyRichEditPlace;
  at: TTyRichPos;
begin
  Result := False;
  EndCompositionForUser;
  if not TableActionsOpen then Exit;
  if not MergeEditOf(area, ed) then
  begin
    // (a caret, a selection that reaches out of the table or over two tables: told)
    Refuse(rsRichEditRefusedMergeWhich, True);
    Exit;
  end;
  r := FDoc.TableEditRefusal(ed);
  if not (r in [rtrNone, rtrNotEmpty]) then
  begin
    Refuse(TableRefusalText(r, ed), True);
    Exit;
  end;
  NameDocBase;
  joined := nil;
  edit := nil;
  comp := TTyRichCompositeCommand.Create(rsRichUndoMergeCells);
  g := TTyCellGather.Create;
  try
    g.Doc := FDoc;
    VisitArea(FDoc, area, @g.Take);
    if Length(g.Cells) < 2 then Exit;
    { The content in reading order: the top-left cell's, then each other cell's that has
      any, as paragraphs after it (an empty cell adds nothing). }
    filled := 0;
    for i := 0 to High(g.Cells) do
      if g.Cells[i].E > g.Cells[i].S then
      begin
        part := DocOfRange(FDoc, g.Cells[i].S, g.Cells[i].E - g.Cells[i].S);
        if joined = nil then
          joined := part
        else
        begin
          joined.Execute(TTyRichInsertText.Create(joined.Text.Length, #13#10));
          joined.Execute(TTyRichInsertFragment.Create(joined.Text.Length, part, False));
        end;
        Inc(filled);
      end;
    // (only the top-left cell's own: nothing moves)
    if (filled > 1) or ((filled = 1) and (g.Cells[0].E <= g.Cells[0].S)) then
    begin
      edit := TTyRichCellsEdit.Create(FDoc.Text.ParaStart(area.FirstPara), rsRichUndoMergeCells);
      edit.AddContent(g.Cells[0].Row, g.Cells[0].Col, joined);
      joined := nil;
      for i := 1 to High(g.Cells) do
        if g.Cells[i].E > g.Cells[i].S then edit.AddClear(g.Cells[i].Row, g.Cells[i].Col);
      comp.Add(edit);
      edit := nil;
    end;
    at := g.Cells[0].S;
    comp.Add(TTyRichMergeCells.Create(FDoc.Text.ParaStart(area.FirstPara), ed.Row0, ed.Row1,
      ed.X0, ed.X1));
    { edges the merged cell now shares with its neighbours - one line each, as the row and
      column doors leave them (the rows it covers and those beside them) }
    comp.Add(TTyRichAgreeEdges.Create(FDoc.Text.ParaStart(area.FirstPara), ed.Row0 - 1, ed.Row1 + 1));
    place := Default(TTyRichEditPlace);
    place.Anchor := at;
    place.Caret := at;
    Result := RunMade(comp, place, True);
    comp := nil;
  finally
    g.Free;
    joined.Free;
    edit.Free;
    comp.Free;
  end;
end;

function TTyCustomRichEdit.MergedRowsOf(APara: Integer; out ASpan, ALastFirst,
  ALastLast: Integer): Boolean;
var
  t: TTyRichText;
  c, nc: TTyRichCell;
  f, l, o: Integer;
  lx, rx, lo, ro: Int64;
begin
  Result := False;
  ASpan := 1;
  ALastFirst := -1;
  ALastLast := -1;
  t := FDoc.Text;
  FDoc.BeginRead;
  try
    c := FDoc.CellAt(APara);
    if (c = nil) or not TyRichRowParas(FDoc, APara, f, l) then Exit;
    ALastFirst := f;
    ALastLast := l;
    if TyRichCellVMerge(c.Row, c.Index) <> rcmFirst then Exit;
    TyRichCellExtent(c.Row, c.Index, lx, rx);
    // down while the cell below continues it, at its extent (the grid's rule)
    while l + 1 < t.ParaCount do
    begin
      nc := FDoc.CellAt(l + 1);
      if (nc = nil) or (nc.Table <> c.Table) then Break;
      o := TyRichFacingCell(c.Row.CellEdges, c.Row.Format.Row.LeftTwips, c.Index,
        nc.Row.CellEdges, nc.Row.Format.Row.LeftTwips);
      if (o < 0) or (TyRichCellVMerge(nc.Row, o) <> rcmContinue) then Break;
      TyRichCellExtent(nc.Row, o, lo, ro);
      if (Abs(lo - lx) > CRichEdgeSlackTwips) or (Abs(ro - rx) > CRichEdgeSlackTwips) then Break;
      if not TyRichRowParas(FDoc, l + 1, f, l) then Break;
      Inc(ASpan);
      ALastFirst := f;
      ALastLast := l;
    end;
    Result := ASpan > 1;
  finally
    FDoc.EndRead;
  end;
end;

function TTyCustomRichEdit.SplitTarget(out ARow, ACell, ASpan, ALeft, ARight,
  ARowPara: Integer): Boolean;
var
  t: TTyRichText;
  area: TTyRichCellArea;
  k, f, l, n, o: Integer;
  c, nc: TTyRichCell;
  e: TTyRichEdges;
begin
  Result := False;
  ARow := -1;
  ACell := -1;
  ASpan := 1;
  t := FDoc.Text;
  // the caret's cell, or one cell selected whole
  if HasSelection then
  begin
    area := CellArea;
    if not TyRichCellsEditable(area) then Exit;
    k := t.ParaOfPos(GetSelStart);
  end
  else
    k := t.ParaOfPos(FCaret);
  FDoc.BeginRead;
  try
    c := FDoc.CellAt(k);
    if (c = nil) or CoveredPara(k) then Exit;
    if HasSelection then
    begin
      // (exactly that cell: the area's rows are its span's, every other cell outside it)
      if not TyRichCellParasOf(FDoc, k, f, l) then Exit;
      if (GetSelStart <> t.ParaStart(f)) or
         (GetSelStart + GetSelLength <> t.ParaStart(l) + t.ParaLength(l) + 1) then
        Exit;
    end;
    if not FDoc.TableRowIndex(k, ARow, n) then Exit;
    ACell := c.Index;
    e := c.Row.CellEdges;
    if ACell = 0 then ALeft := c.Row.Format.Row.LeftTwips else ALeft := e[ACell - 1];
    ARight := e[ACell];
    if not TyRichRowParas(FDoc, k, f, l) then Exit;
    ARowPara := f;
    // the rows it covers: down while the cell below continues it at its extent
    MergedRowsOf(k, ASpan, f, l);
    Result := True;
  finally
    FDoc.EndRead;
  end;
end;

function TTyCustomRichEdit.SplitEditOf(ACols, ARows: Integer; AGrid: Boolean;
  out AEdit: TTyRichTableEdit): Boolean;
var
  r, ci, span, xl, xr, rp, i, c0, cn: Integer;
  g: TTyRichGrid;
  gc: TTyRichGridCell;
  edges: TTyRichEdges;
begin
  AEdit := Default(TTyRichTableEdit);
  Result := SplitTarget(r, ci, span, xl, xr, rp);
  if not Result then Exit;
  edges := nil;
  if (ACols > 1) and AGrid then
  begin
    // over as many of the grid's columns as it splits into: their own edges back
    cn := 0;
    c0 := 0;
    g := TableGrid(FDoc.Text.ParaStart(rp));
    try
      if g <> nil then
      begin
        gc := g.CellOf(r, ci);
        cn := gc.ColSpan;
        c0 := gc.Col;
        if cn = ACols then
        begin
          SetLength(edges, ACols - 1);
          for i := 1 to ACols - 1 do edges[i - 1] := g.Edge(c0 + i);
        end;
      end;
    finally
      g.Free;
    end;
  end;
  // any other number of columns: the width in equal parts
  if (ACols > 1) and (Length(edges) = 0) then
  begin
    SetLength(edges, ACols - 1);
    for i := 1 to ACols - 1 do edges[i - 1] := xl + Int64(xr - xl) * i div ACols;
  end;
  AEdit := TyRichTableEdit(rtkSplitCell, FDoc.Text.ParaStart(rp), ci, ARows, ACols);
  AEdit.Row0 := r;
  AEdit.Row1 := r + span - 1;
  AEdit.SpanRows := span;
  AEdit.SplitEdges := edges;
end;

{ What is wrong with split AEdit's numbers, in the person's words: the rows that do not
  divide the cell's, a row that would pass the cells a row may have, a table that would pass
  its rows. }
function TTyCustomRichEdit.SplitRefusalText(const AEdit: TTyRichTableEdit): string;
var
  c: TTyRichCell;
  k, r, n: Integer;
begin
  Result := rsRichEditRefusedRange;
  if (AEdit.Cols < 1) or (AEdit.Rows < 1) then Exit(rsRichEditRefusedSplitNumbers);
  if (AEdit.SpanRows > 1) and (AEdit.SpanRows mod AEdit.Rows <> 0) then
    Exit(Format(rsRichEditRefusedSplitRows, [AEdit.SpanRows]));
  if AEdit.Cols > CRichMaxTableCols then Exit(Format(rsRichEditRefusedSplitCells, [CRichMaxTableCols]));
  FDoc.BeginRead;
  try
    k := FDoc.Text.ParaOfPos(AEdit.Pos);
    c := FDoc.CellAt(k);
    if (c <> nil) and (c.Row.CellCount - 1 + AEdit.Cols > CRichMaxTableCols) then
      Exit(Format(rsRichEditRefusedSplitCells, [CRichMaxTableCols]));
    if (AEdit.SpanRows <= 1) and (AEdit.Rows > 1) and FDoc.TableRowIndex(k, r, n) and
       (n + AEdit.Rows - 1 > CRichMaxTableRows) then
      Exit(Format(rsRichEditRefusedSplitTableRows, [CRichMaxTableRows]));
    // (another row the cell covers may have more cells)
    if AEdit.Cols > 1 then Result := Format(rsRichEditRefusedSplitCells, [CRichMaxTableCols]);
  finally
    FDoc.EndRead;
  end;
end;

function TTyCustomRichEdit.CaretCellSpan(out AColumns, ARows: Integer): Boolean;
var
  r, ci, span, xl, xr, rp: Integer;
  g: TTyRichGrid;
begin
  AColumns := 1;
  ARows := 1;
  Result := SplitTarget(r, ci, span, xl, xr, rp);
  if not Result then Exit;
  ARows := span;
  g := TableGrid(FDoc.Text.ParaStart(rp));
  try
    if g <> nil then AColumns := Math.Max(1, g.CellOf(r, ci).ColSpan);
  finally
    g.Free;
  end;
end;

function TTyCustomRichEdit.CanSplitCell: Boolean;
var
  ed: TTyRichTableEdit;
begin
  Result := False;
  if not TableActionsOpen then Exit;
  if SplitEditOf(2, 1, False, ed) and (FDoc.TableEditRefusal(ed) = rtrNone) then Exit(True);
  if SplitEditOf(1, 2, False, ed) and (FDoc.TableEditRefusal(ed) = rtrNone) then Exit(True);
end;

function TTyCustomRichEdit.SplitCell(ACols, ARows: Integer): Boolean;
var
  comp: TTyRichCompositeCommand;
  n: Integer;
  ed: TTyRichTableEdit;
  r: TTyRichTableRefusal;
  place: TTyRichEditPlace;
  at: TTyRichPos;
begin
  Result := False;
  EndCompositionForUser;
  if not TableActionsOpen then Exit;
  // (every refusal is told: numbers that make no split too)
  if (ACols < 1) or (ARows < 1) or ((ACols = 1) and (ARows = 1)) then
  begin
    Refuse(rsRichEditRefusedSplitNumbers, True);
    Exit;
  end;
  if not SplitEditOf(ACols, ARows, True, ed) then
  begin
    Refuse(rsRichEditRefusedSplitWhich, True);
    Exit;
  end;
  r := FDoc.TableEditRefusal(ed);
  if r <> rtrNone then
  begin
    Refuse(TableRefusalText(r, ed), True);
    Exit;
  end;
  // the caret at the split cell's start: where its content stays
  if HasSelection then at := GetSelStart else at := FCaret;
  at := FDoc.Text.ParaStart(FDoc.Text.ParaOfPos(at));
  place := Default(TTyRichEditPlace);
  place.Anchor := at;
  place.Caret := at;
  { the parts' edges that now meet their neighbours' - one line each (the rows the split
    covers, those it adds, and the rows beside them) }
  comp := TTyRichCompositeCommand.Create(rsRichUndoSplitCell);
  comp.Add(TTyRichSplitCell.Create(ed.Pos, ed.Row0, ed.Index, ed.SpanRows, ed.Cols,
    ed.Rows, ed.SplitEdges));
  if ed.SpanRows > 1 then n := ed.SpanRows else n := ed.Rows;
  comp.Add(TTyRichAgreeEdges.Create(ed.Pos, ed.Row0 - 1, ed.Row0 + n));
  Result := RunMade(comp, place, True);
end;

function TTyCustomRichEdit.SpanRowsDelete(ATablePos: TTyRichPos; AR1, AR2,
  AFirstPara: Integer): TTyRichCommand;
var
  rows: TTyRichRowList;
  first, count, r, i, o, f, l, rf, k: Integer;
  starts: array of Integer;
  row: TTyRichRow;
  any: Boolean;
  below: TTyRichRow;
  comp: TTyRichCompositeCommand;
  edit: TTyRichCellsEdit;
  part: TTyRichDocument;
  t: TTyRichText;

  // the paragraphs of cell ACell of row ARow (one of AR1 .. AR2: read from its first paragraph)
  function CellParas(ARow, ACell: Integer; out AF, AL: Integer): Boolean;
  var
    m: Integer;
    c: TTyRichCell;
  begin
    AF := -1;
    AL := -1;
    m := starts[ARow - AR1];
    row := FDoc.CellAt(m).Row;
    while m < t.ParaCount do
    begin
      c := FDoc.CellAt(m);
      if (c = nil) or (c.Row <> row) then Break;
      if c.Index = ACell then
      begin
        if AF < 0 then AF := m;
        AL := m;
      end;
      Inc(m);
    end;
    Result := AF >= 0;
  end;

begin
  Result := nil;
  t := FDoc.Text;
  FDoc.BeginRead;
  try
    // (read from the rows' own place: a table's start would read every row before them)
    if not FDoc.TableRowsAt(t.ParaStart(AFirstPara), AR1 - 1, AR2 + 1, rows, first, count) then Exit;
    any := False;
    for r := 0 to High(rows) do
      for i := 0 to rows[r].Format.CellCount - 1 do
        if rows[r].Format.Cells[i].VMerge <> rcmNone then any := True;
    if not any then Exit;
    if AR2 + 1 < count then below := rows[AR2 + 1 - first] else below := nil;
    // (the rows' first paragraphs, from the first one's: the rows that go, and no others)
    SetLength(starts, AR2 - AR1 + 1);
    k := AFirstPara;
    for r := AR1 to AR2 do
    begin
      starts[r - AR1] := k;
      row := FDoc.CellAt(k).Row;
      while (k < t.ParaCount) and (FDoc.CellAt(k) <> nil) and (FDoc.CellAt(k).Row = row) do Inc(k);
    end;
    comp := TTyRichCompositeCommand.Create(rsRichUndoDeleteRow);
    try
      for r := AR2 downto AR1 do
      begin
        { a merge that begins here and goes on below the rows that go: its content to the row
          that follows them then (row 1, counted from this one, when the rows below it went) }
        edit := nil;
        for i := 0 to rows[r - first].Format.CellCount - 1 do
        begin
          if rows[r - first].Format.Cells[i].VMerge <> rcmFirst then Continue;
          if below = nil then Continue;
          o := TyRichFacingCell(rows[r - first].CellEdges, rows[r - first].Format.Row.LeftTwips, i,
            below.CellEdges, below.Format.Row.LeftTwips);
          if (o < 0) or (o >= below.Format.CellCount) or (below.Format.Cells[o].VMerge <> rcmContinue) then
            Continue;
          if not CellParas(r, i, f, l) then Continue;
          if (f = l) and (t.ParaLength(f) = 0) then Continue;
          rf := starts[r - AR1];
          part := DocOfRange(FDoc, t.ParaStart(f), t.ParaStart(l) + t.ParaLength(l) - t.ParaStart(f));
          if edit = nil then edit := TTyRichCellsEdit.Create(t.ParaStart(rf), rsRichUndoDeleteRow);
          edit.AddContent(1, o, part);
          edit.AddClear(0, i);
        end;
        if edit <> nil then comp.Add(edit);
        // (named at its own first paragraph: the rows above it are where they were)
        comp.Add(TTyRichDeleteRow.Create(t.ParaStart(starts[r - AR1]), r));
      end;
      Result := comp;
      comp := nil;
    finally
      comp.Free;
    end;
  finally
    FDoc.EndRead;
  end;
end;

function TTyCustomRichEdit.GridColumnsEdit(ATablePos: TTyRichPos; AX0, AX1: Integer; AInsert,
  AAfter: Boolean; out AWhole: Boolean): TTyRichCommand;
var
  g: TTyRichGrid;
  r, i, c, n, x, w: Integer;
  plain: Boolean;
  gc: TTyRichGridCell;
  comp: TTyRichCompositeCommand;
begin
  Result := nil;
  AWhole := False;
  g := TableGrid(ATablePos);
  if g = nil then Exit;
  try
    // a plain grid: every row a cell a column, nothing merged
    plain := True;
    for r := 0 to g.RowCount - 1 do
    begin
      if g.CellCountOfRow(r) <> g.ColCount then plain := False;
      for i := 0 to g.CellCountOfRow(r) - 1 do
      begin
        gc := g.CellOf(r, i);
        if gc.Covered or (gc.ColSpan <> 1) or (gc.RowSpan <> 1) then plain := False;
      end;
      if not plain then Break;
    end;
    // the grid's columns AX0 .. AX1 covers
    n := 0;
    for c := 0 to g.ColCount - 1 do
      if (g.Edge(c) >= AX0 - CRichEdgeSlackTwips) and (g.Edge(c + 1) <= AX1 + CRichEdgeSlackTwips) then
        Inc(n);
    if n = 0 then n := 1;
    if not AInsert and (AX0 <= g.Edge(0) + CRichEdgeSlackTwips) and
       (AX1 >= g.Edge(g.ColCount) - CRichEdgeSlackTwips) then
    begin
      AWhole := True;
      Exit;
    end;
    if plain then Exit;
    if not AInsert then
    begin
      Result := TTyRichDeleteGridColumns.Create(ATablePos, Math.Max(AX0, g.Edge(0)),
        Math.Min(AX1, g.Edge(g.ColCount)));
      Exit;
    end;
    // at the right edge (after) or the left; as wide as the grid's column beside it
    if AAfter then x := Math.Min(AX1, g.Edge(g.ColCount)) else x := Math.Max(AX0, g.Edge(0));
    w := 0;
    for c := 0 to g.ColCount - 1 do
      if AAfter and (Abs(g.Edge(c + 1) - x) <= CRichEdgeSlackTwips) then w := g.ColWidth(c)
      else if not AAfter and (Abs(g.Edge(c) - x) <= CRichEdgeSlackTwips) then w := g.ColWidth(c);
    if w <= 0 then w := 1440;
    // (all of them in one edit: the table read and written once, whatever their number)
    Result := TTyRichInsertGridColumn.Create(ATablePos, x, w, n);
  finally
    g.Free;
  end;
end;

procedure TTyCustomRichEdit.CopyCells(const AArea: TTyRichCellArea);
var
  rtf: RawByteString;
  txt: string;
begin
  if CellsFlavours(AArea, rtf, txt) then WriteClipboard(rtf, txt);
end;

{ AFrom .. AFrom + ALen is cells a copy takes as a small table: both ends in one table, not
  whole rows (those copy as the file's rows). }
function TTyCustomRichEdit.RangeIsCells(AFrom, ALen: TTyRichPos; out AArea: TTyRichCellArea): Boolean;
begin
  AArea := TyRichCellArea(FDoc, AFrom, AFrom + ALen);
  Result := TyRichCellsEditable(AArea) and not TyRichAreaWholeRows(FDoc, AArea);
end;

{ What a copy of the cells writes: a small table (RTF) and their text, a row a line, the cells
  parted by tabs. False: no cell. }
function TTyCustomRichEdit.CellsFlavours(const AArea: TTyRichCellArea; out ARtf: RawByteString;
  out AText: string): Boolean;
var
  g: TTyCellGather;
  d: TTyRichDocument;
  edit: TTyRichCellsEdit;
  rows, cols, i, k: Integer;
  st: TBytesStream;
  rtf: RawByteString;
  txt, cellTxt: string;
  colOf: array of Integer;
  firstOfRow: array of Integer;
  gr: TTyRichGrid;
  gc: TTyRichGridCell;
  plain: Boolean;
  rowBase, colStart, c, rr, cc, rs, cs: Integer;
  placeRow, placeCol, spanRows, spanCols: array of Integer;
  drows: TTyRichRowList;
  dfirst, dcount: Integer;
  de: TTyRichEdges;
  dedges: array of Integer;
  places: array of string;
begin
  Result := False;
  ARtf := '';
  AText := '';
  gr := nil;
  // (each cell's content is written and read back: its text in the view's font and size)
  NameDocBase;
  g := TTyCellGather.Create;
  d := TTyRichDocument.Create;
  try
    g.Doc := FDoc;
    VisitArea(FDoc, AArea, @g.Take);
    if Length(g.Cells) = 0 then Exit;
    // the small table: as many rows as the area's, as many cells as its widest row
    rows := g.Cells[High(g.Cells)].Row + 1;
    SetLength(colOf, Length(g.Cells));
    SetLength(firstOfRow, rows);
    cols := 0;
    k := 0;
    for i := 0 to High(g.Cells) do
    begin
      if (i = 0) or (g.Cells[i].Row <> g.Cells[i - 1].Row) then k := 0;
      colOf[i] := k;
      Inc(k);
      if k > cols then cols := k;
    end;
    { Cells merged in the source: the copy is a table of the grid's columns under the area,
      each cell where the grid has it, merged as it is there (clipped to the area) - Word
      reads it merged the same way. }
    SetLength(placeRow, Length(g.Cells));
    SetLength(placeCol, Length(g.Cells));
    SetLength(spanRows, Length(g.Cells));
    SetLength(spanCols, Length(g.Cells));
    for i := 0 to High(g.Cells) do
    begin
      placeRow[i] := g.Cells[i].Row;
      placeCol[i] := colOf[i];
      spanRows[i] := 1;
      spanCols[i] := 1;
    end;
    gr := TableGrid(FDoc.Text.ParaStart(AArea.FirstPara));
    plain := True;
    if gr <> nil then
    begin
      rowBase := AArea.Range.Row0;
      for i := 0 to High(g.Cells) do
      begin
        gc := gr.CellOf(rowBase + g.Cells[i].Row, g.Cells[i].Col);
        if gc.Covered or (gc.RowSpan <> 1) or (gc.ColSpan <> 1) then plain := False;
      end;
      if not plain then
      begin
        colStart := 0;
        if not AArea.AllCells then
          while (colStart < gr.ColCount - 1) and (gr.Edge(colStart) < AArea.X0 - CRichEdgeSlackTwips) do
            Inc(colStart);
        cols := 0;
        for c := colStart to gr.ColCount - 1 do
          if AArea.AllCells or (gr.Edge(c + 1) <= AArea.X1 + CRichEdgeSlackTwips) then cols := c - colStart + 1;
        if cols < 1 then cols := 1;
        for i := 0 to High(g.Cells) do
        begin
          gc := gr.CellOf(rowBase + g.Cells[i].Row, g.Cells[i].Col);
          if gc.Covered then
          begin
            placeRow[i] := -1;
            Continue;
          end;
          placeRow[i] := gc.Row - rowBase;
          placeCol[i] := gc.Col - colStart;
          spanRows[i] := Math.Min(gc.RowSpan, rows - placeRow[i]);
          spanCols[i] := Math.Min(gc.ColSpan, cols - placeCol[i]);
          if (placeRow[i] < 0) or (placeCol[i] < 0) or (placeCol[i] >= cols) then placeRow[i] := -1;
        end;
      end;
    end;
    d.Execute(TTyRichInsertTable.Create(0, rows, cols));
    edit := TTyRichCellsEdit.Create(0, rsRichUndoPaste);
    txt := '';
    places := nil;
    if not plain then SetLength(places, rows * cols);
    for i := 0 to High(g.Cells) do
    begin
      if (g.Cells[i].E > g.Cells[i].S) and (placeRow[i] >= 0) then
        edit.AddContent(placeRow[i], placeCol[i], DocOfRange(FDoc, g.Cells[i].S,
          g.Cells[i].E - g.Cells[i].S));
      // the text: a row a line, its cells parted by tabs (a cell's own breaks are spaces)
      if (i > 0) and (g.Cells[i].Row <> g.Cells[i - 1].Row) then txt := txt + LineEnding
      else if i > 0 then txt := txt + #9;
      cellTxt := RangeText(g.Cells[i].S, g.Cells[i].E - g.Cells[i].S);
      cellTxt := StringReplace(StringReplace(cellTxt, #13#10, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
      cellTxt := StringReplace(StringReplace(cellTxt, #13, ' ', [rfReplaceAll]), #9, ' ', [rfReplaceAll]);
      txt := txt + cellTxt;
      if not plain and (placeRow[i] >= 0) then places[placeRow[i] * cols + placeCol[i]] := cellTxt;
    end;
    { (merged cells: a row a line of as many fields as the grid has columns under the area -
      a merged cell's text in its first place, an empty field for each place it covers) }
    if not plain then
    begin
      txt := '';
      for rr := 0 to rows - 1 do
      begin
        if rr > 0 then txt := txt + LineEnding;
        for cc := 0 to cols - 1 do
        begin
          if cc > 0 then txt := txt + #9;
          txt := txt + places[rr * cols + cc];
        end;
      end;
    end;
    d.Execute(edit);
    if not plain and d.TableRowsAt(0, 0, 0, drows, dfirst, dcount) and (Length(drows) > 0) then
    begin
      de := drows[0].CellEdges;
      SetLength(dedges, Length(de) + 1);
      dedges[0] := drows[0].Format.Row.LeftTwips;
      for c := 0 to High(de) do dedges[c + 1] := de[c];
      for i := 0 to High(g.Cells) do
      begin
        if placeRow[i] < 0 then Continue;
        rr := placeRow[i];
        cc := placeCol[i];
        rs := spanRows[i];
        cs := spanCols[i];
        if (rs <= 1) and (cs <= 1) then Continue;
        if cc + cs > High(dedges) then Continue;
        d.Execute(TTyRichMergeCells.Create(0, rr, rr + rs - 1, dedges[cc], dedges[cc + cs]));
      end;
    end;
    st := TBytesStream.Create;
    try
      TyRichSaveRtf(d, st);
      SetLength(rtf, st.Size);
      if st.Size > 0 then Move(st.Bytes[0], rtf[1], st.Size);
      SetCodePage(rtf, CP_NONE, False);
    finally
      st.Free;
    end;
    ARtf := rtf;
    AText := txt;
    Result := True;
  finally
    gr.Free;
    d.Free;
    g.Free;
  end;
end;

{ A table offered (RTF with a table, or text with tabs: a spreadsheet's) put cell by cell into
  the table at APos, or - APos -1, a paste - at the selected cells or the caret's cell; one
  step named AName. False: not that case (no table offered, no cell there) - the caller goes
  on with its own rules. }
function TTyCustomRichEdit.PasteCells(AOffer: TTyRichDropOffer; AHave: TTyRichClipFlavours;
  AAs: TTyRichPasteAs; APos: TTyRichPos; const AName: string): Boolean;
var
  edit: TTyRichCellsEdit;
  place: TTyRichEditPlace;
  at: TTyRichPos;
  k: Integer;
begin
  edit := MakeCellsPaste(AOffer, AHave, AAs, APos, AName, at);
  Result := edit <> nil;
  if not Result then Exit;
  place := Default(TTyRichEditPlace);
  place.Anchor := at;
  place.Caret := at;
  k := 0;
  if RunMade(edit, place, True) then k := edit.Dropped;
  if k > 0 then Refuse(rsRichEditPasteCellsDropped, True);
end;

{ PasteCells' command, not run (nil: not that case); ATarget: the start of the cell it fills
  first, where the caret goes. }
function TTyCustomRichEdit.MakeCellsPaste(AOffer: TTyRichDropOffer; AHave: TTyRichClipFlavours;
  AAs: TTyRichPasteAs; APos: TTyRichPos; const AName: string; out ATarget: TTyRichPos): TTyRichCellsEdit;
var
  t: TTyRichText;
  k, f, l, i, r, col, p, q, row0: Integer;
  c, d: TTyRichCell;
  area: TTyRichCellArea;
  src: TTyRichDocument;
  edit: TTyRichCellsEdit;
  rtf: RawByteString;
  txt: string;
  lns, cells: TStringList;
  st: TBytesStream;
  anyTable: Boolean;
  ri0, rn, sk: Integer;
  x0: Int64;
  xr: Int64;

  { The cell of the target's row ARow (counted from row0) that the source row's AK-th cell goes
    into, by the grid: the AK-th one, from the rectangle's left, that no merge covers (-1:
    none, past the row's end). A row past the table's last: as the rows added below are. }
  function TargetOf(ARow, AK: Integer): Integer;
  var
    rows: TTyRichRowList;
    first, count, i, n: Integer;
    row: TTyRichRow;
    l, r: Int64;
  begin
    Result := col + AK;
    FDoc.BeginRead;
    try
      if not FDoc.TableRowsAt(t.ParaStart(row0), ri0 + ARow, ri0 + ARow, rows, first, count) or
         (Length(rows) = 0) or (first <> ri0 + ARow) then
        Exit;
      row := rows[0];
      n := 0;
      for i := 0 to row.CellCount - 1 do
      begin
        TyRichCellExtent(row, i, l, r);
        if l < x0 - CRichEdgeSlackTwips then Continue;
        // (a covered place: the cell above, or the one before across, reaches over it)
        if (TyRichCellVMerge(row, i) = rcmContinue) or (TyRichCellHMerge(row, i) = rcmContinue) then
          Continue;
        if n = AK then Exit(i);
        Inc(n);
      end;
      Result := -1;
    finally
      FDoc.EndRead;
    end;
  end;

  procedure Fill(ARow, AK: Integer; ADoc: TTyRichDocument; const AText: string);
  var
    j: Integer;
  begin
    j := TargetOf(ARow, AK);
    if j < 0 then
    begin
      // (past the row's end: left out, as past the last column; told once)
      ADoc.Free;
      edit.AddClear(ARow, MaxInt div 2);
      Exit;
    end;
    if ADoc <> nil then edit.AddContent(ARow, j, ADoc) else edit.AddText(ARow, j, AText);
  end;

begin
  Result := nil;
  ATarget := -1;
  if FReadOnly or not IsEnabled or ViewBehind then Exit;
  t := FDoc.Text;
  // from the first selected cell, else the caret's cell
  area := CellArea;
  if APos >= 0 then
    k := t.ParaOfPos(Math.Min(APos, t.Length))
  else if area.Outside then
    Exit
  else if area.Range.InTable then
  begin
    if not FirstAreaCell(area, f, l) then Exit;
    k := f;
  end
  else
  begin
    // (a selection of text in a cell, or none: from the caret's cell)
    if HasSelection and (t.ParaOfPos(GetSelStart) <> t.ParaOfPos(GetSelStart + GetSelLength)) then
      Exit;
    k := t.ParaOfPos(FCaret);
  end;
  FDoc.BeginRead;
  try
    c := FDoc.CellAt(k);
    if (c = nil) or c.Row.HoldsNestedTable then Exit;
    col := c.Index;
    TyRichRowParas(FDoc, k, p, q);
    row0 := p;
    TyRichCellExtent(c.Row, col, x0, xr);
    if not FDoc.TableRowIndex(row0, ri0, rn) then ri0 := 0;
  finally
    FDoc.EndRead;
  end;
  edit := TTyRichCellsEdit.Create(t.ParaStart(row0), AName);
  try
    anyTable := False;
    if (rcfRtf in AHave) and ((AAs = rpaBest) or (AAs = rpaRtf)) then
    begin
      rtf := AOffer.ReadRtf;
      if rtf <> '' then
      begin
        src := TTyRichDocument.Create;
        try
          st := TBytesStream.Create;
          try
            st.WriteBuffer(rtf[1], Length(rtf));
            st.Position := 0;
            try
              TyRichLoadRtfFull(src, st);
            except
              FreeAndNil(src);
            end;
          finally
            st.Free;
          end;
          if src <> nil then
          begin
            // its first table, cell by cell
            k := 0;
            src.BeginRead;
            try
              while (k < src.Text.ParaCount) and (src.CellAt(k) = nil) do Inc(k);
              if k < src.Text.ParaCount then
              begin
                anyTable := True;
                r := -1;
                d := nil;
                sk := 0;
                while (k < src.Text.ParaCount) and (src.CellAt(k) <> nil) do
                begin
                  c := src.CellAt(k);
                  if (d = nil) or (c.Row <> d.Row) then
                  begin
                    Inc(r);
                    sk := 0;
                  end;
                  f := k;
                  while (k + 1 < src.Text.ParaCount) and (src.CellAt(k + 1) = c) do Inc(k);
                  // (the source's covered places are no cells to paste: the grid's k-th cell)
                  if (TyRichCellVMerge(c.Row, c.Index) <> rcmContinue) and
                     (TyRichCellHMerge(c.Row, c.Index) <> rcmContinue) then
                  begin
                    Fill(r, sk, DocOfRange(src, src.Text.ParaStart(f),
                      src.Text.ParaStart(k) + src.Text.ParaLength(k) - src.Text.ParaStart(f)), '');
                    Inc(sk);
                  end;
                  d := c;
                  Inc(k);
                end;
              end;
            finally
              src.EndRead;
            end;
          end;
        finally
          src.Free;
        end;
      end;
    end;
    if not anyTable and (rcfText in AHave) and ((AAs = rpaBest) or (AAs = rpaText)) then
    begin
      // tab-separated text (a spreadsheet's): a line a row, a tab between cells
      txt := AOffer.ReadText;
      if Pos(#9, txt) > 0 then
      begin
        anyTable := True;
        lns := TStringList.Create;
        cells := TStringList.Create;
        try
          lns.Text := txt;
          cells.Delimiter := #9;
          cells.StrictDelimiter := True;
          for r := 0 to lns.Count - 1 do
          begin
            if (r = lns.Count - 1) and (lns[r] = '') then Break;
            cells.DelimitedText := lns[r];
            for i := 0 to cells.Count - 1 do Fill(r, i, nil, cells[i]);
          end;
        finally
          cells.Free;
          lns.Free;
        end;
      end;
    end;
    if not anyTable or (edit.Count = 0) then Exit;
    FDoc.BeginRead;
    try
      TyRichRowParas(FDoc, row0, p, q);
      f := p;
      for i := p to q do
        if FDoc.CellAt(i).Index = col then
        begin
          f := i;
          Break;
        end;
    finally
      FDoc.EndRead;
    end;
    ATarget := t.ParaStart(f);
    Result := edit;
    edit := nil;
  finally
    edit.Free;
  end;
end;

// the least width of a row's or a column's zone: 6 device-independent pixels
function TTyCustomRichEdit.ZoneMinRaster: Int64;
begin
  Result := Int64(Math.Max(1, MulDiv(6, ViewPPI, 96))) * Math.Max(1, FScale);
end;

{ The zone left of a row: the table's left margin, from 3 zone widths and an edge band left of
  the table (never left of the view) to the band of the table's left edge. Where that leaves
  less than ZoneMinRaster - a table at the margin, Word's that starts left of it - the zone is
  that wide from its left end and reaches into the first cell (its left padding, the edge's
  band): it wins over them there. }
procedure TTyCustomRichEdit.RowZoneSpan(R: TTyRowLayout; out ALo, AHi: Int64);
var
  area: TRect;
  z, e, viewLo: Int64;
begin
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  viewLo := -Int64(area.Left) * FScale + FScrollX;
  z := Math.Max(2, MulDiv(4, ViewPPI, 96)) * FScale;
  e := EdgeBand;
  ALo := Math.Max(R.Cells[0].Left - 3 * z - e, viewLo);
  AHi := R.Cells[0].Left - e;
  if AHi - ALo < ZoneMinRaster then AHi := ALo + ZoneMinRaster;
end;

{ A table's zones under client point X, Y: just inside a cell's left edge (CZoneCell), the
  table's left margin beside a row (CZoneRow, RowZoneSpan), just above a column of the table's
  first row (CZoneColumn: at least ZoneMinRaster high, reaching into the row's top where there
  is less room above), the handle at the table's top-left corner (CZoneTable). APara: a
  paragraph of that cell, row or column (the first row's), or the table's first paragraph.
  Each zone a few device pixels wide - the text starts further in. }
function TTyCustomRichEdit.TableZoneAt(X, Y: Integer; out AZone, APara: Integer): Boolean;
var
  area: TRect;
  rx, ry, z, e: Int64;
  k, i, kb: Integer;
  r: TTyRowLayout;
  first: Boolean;
  c: TTyRichCell;
  hr: TRect;
  zlo, zhi, into, cl: Int64;
begin
  AZone := 0;
  APara := -1;
  Result := False;
  if ViewBehind or not SelectionAllowed or (FBlockCount = 0) or (csDesigning in ComponentState) then
    Exit;
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  rx := (Int64(X) - area.Left) * FScale + FScrollX;
  ry := (Int64(Y) - area.Top) * FScale;
  z := Math.Max(2, MulDiv(4, ViewPPI, 96)) * FScale;
  // (the band an edge takes, beside the zones: TableZoneAt's zones start past it)
  e := EdgeBand;
  // the handle
  if FHandlePara >= 0 then
    for k := 0 to FBlockCount - 1 do
      if (FBlocks[k].FirstPara = FHandlePara) and (FBlocks[k].Layout is TTyRowLayout) then
      begin
        hr := TableHandleRect(k);
        if (rx >= hr.Left) and (rx < hr.Right) and (ry >= hr.Top) and (ry < hr.Bottom) then
        begin
          AZone := CZoneTable;
          APara := FHandlePara;
          Exit(True);
        end;
      end;
  k := 0;
  while (k < FBlockCount - 1) and (ry >= FBlocks[k].Top + FBlocks[k].Height) do Inc(k);
  if (ry >= FBlocks[k].Top) and (ry < FBlocks[k].Top + FBlocks[k].Height) and
     (FBlocks[k].Layout is TTyRowLayout) then
  begin
    r := TTyRowLayout(FBlocks[k].Layout);
    // the row's zone first: where it reaches into the first cell it wins
    if r.CellCount > 0 then
    begin
      RowZoneSpan(r, zlo, zhi);
      if (rx >= zlo) and (rx < zhi) then
      begin
        AZone := CZoneRow;
        APara := FBlocks[k].FirstPara;
        Exit(True);
      end;
    end
    else
      zhi := Low(Int64);
    for i := 0 to r.CellCount - 1 do
    begin
      // (the first cell's zone starts where the row's ends)
      cl := r.Cells[i].Left;
      if (i = 0) and (zhi > cl) then cl := zhi;
      if not r.Cells[i].Hidden and (rx >= cl) and (rx < cl + z + e) and
         (rx < r.Cells[i].Right) and (r.Cells[i].ItemCount > 0) then
      begin
        AZone := CZoneCell;
        APara := FBlocks[k].FirstPara + r.Cells[i].FirstItem;
        Exit(True);
      end;
    end;
  end;
  // just above the table's first row - and into its top, to make the zone's least height
  into := Math.Max(0, ZoneMinRaster - z);
  kb := 0;
  while (kb < FBlockCount - 1) and (ry + z >= FBlocks[kb].Top + FBlocks[kb].Height) do Inc(kb);
  if (ry < FBlocks[kb].Top + into) and (ry + z >= FBlocks[kb].Top) and
     (FBlocks[kb].Layout is TTyRowLayout) then
  begin
    FDoc.BeginRead;
    try
      c := FDoc.CellAt(FBlocks[kb].FirstPara);
      first := (c <> nil) and ((FBlocks[kb].FirstPara = 0) or (FDoc.CellAt(FBlocks[kb].FirstPara - 1) = nil) or
        (FDoc.CellAt(FBlocks[kb].FirstPara - 1).Table <> c.Table));
    finally
      FDoc.EndRead;
    end;
    if first then
    begin
      r := TTyRowLayout(FBlocks[kb].Layout);
      for i := 0 to r.CellCount - 1 do
        if not r.Cells[i].Hidden and (rx >= r.Cells[i].Left) and (rx < r.Cells[i].Right) and
           (r.Cells[i].ItemCount > 0) then
        begin
          AZone := CZoneColumn;
          APara := FBlocks[kb].FirstPara + r.Cells[i].FirstItem;
          Exit(True);
        end;
    end;
  end;
end;

function TTyCustomRichEdit.TableZonePress(X, Y: Integer): Boolean;
var
  zone, p: Integer;
  info: TTyRichTableInfo;
begin
  Result := TableZoneAt(X, Y, zone, p);
  if not Result then Exit;
  // the zone's selection: as the methods make it from the caret
  Select(FDoc.Text.ParaStart(p), FDoc.Text.ParaStart(p), False);
  case zone of
    CZoneCell: SelectCell;
    CZoneRow: SelectRow;
    CZoneColumn: SelectColumn;
  else
    SelectTable;
  end;
  FCellDrag := zone;
  FCellDragPara := p;
  FCellDragLast := -1;
  if (zone = CZoneColumn) and FDoc.TableInfoAt(p, info) then FCellDragLast := info.Last;
end;

function TTyCustomRichEdit.TableZoneExtend(X, Y: Integer): Boolean;
var
  zone, p, ka, f, l: Integer;
  ca, cp: TTyRichCell;
  info: TTyRichTableInfo;
begin
  Result := False;
  if not TableZoneAt(X, Y, zone, p) or not (zone in [CZoneRow, CZoneColumn]) then Exit;
  ka := FDoc.Text.ParaOfPos(Math.Min(FSelAnchor, FDoc.Text.Length));
  FDoc.BeginRead;
  try
    ca := FDoc.CellAt(ka);
    cp := FDoc.CellAt(p);
    // (an anchor outside that table: the press as without Shift)
    if (ca = nil) or (cp = nil) or (ca.Table <> cp.Table) then Exit;
  finally
    FDoc.EndRead;
  end;
  if not FDoc.TableInfoAt(p, info) then Exit;
  FCellDrag := zone;
  FCellDragLast := -1;
  if zone = CZoneRow then
    FCellDragPara := ka
  else
  begin
    // the anchor's column, from the table's first row
    if not FDoc.TableCellParas(info.First, 0, ca.Index, f, l) then Exit;
    FCellDragPara := f;
    FCellDragLast := info.Last;
  end;
  TableZoneDragTo(p);
  Result := True;
end;

{ A press on a zone dragged to client X, Y: from the pressed row, column or cell to the one
  under the pointer. }
procedure TTyCustomRichEdit.TableZoneDrag(X, Y: Integer);
var
  q: TTyRichPos;
  atEnd: Boolean;
  t: TTyRichText;
begin
  if (FCellDrag = 0) or (FCellDrag = CZoneTable) then Exit;
  t := FDoc.Text;
  q := HitClient(X, Y, atEnd);
  if q < 0 then Exit;
  TableZoneDragTo(t.ParaOfPos(Math.Min(q, t.Length)));
end;

// the zone drag's selection: from the pressed row, column or cell to those of paragraph APara
procedure TTyCustomRichEdit.TableZoneDragTo(APara: Integer);
var
  a, b: TTyRichPos;
  k, f0, l0, f1, l1, c0, c1: Integer;
  c: TTyRichCell;
  t: TTyRichText;

  // the paragraphs of cell ACol in the row of paragraph APara
  procedure CellIn(APara, ACol: Integer; out AF, AL: Integer);
  var
    p, s, j: Integer;
  begin
    TyRichRowParas(FDoc, APara, p, s);
    AF := -1;
    AL := -1;
    for j := p to s do
      if FDoc.CellAt(j).Index = ACol then
      begin
        if AF < 0 then AF := j;
        AL := j;
      end;
    if AF < 0 then
    begin
      AF := s;
      AL := s;
    end;
  end;

begin
  if (FCellDrag = 0) or (FCellDrag = CZoneTable) then Exit;
  t := FDoc.Text;
  k := APara;
  FDoc.BeginRead;
  try
    c := FDoc.CellAt(k);
    if (c = nil) or (FDoc.CellAt(FCellDragPara) = nil) or
       (c.Table <> FDoc.CellAt(FCellDragPara).Table) then
      Exit;
    case FCellDrag of
      CZoneRow:
        begin
          TyRichRowParas(FDoc, FCellDragPara, f0, l0);
          TyRichRowParas(FDoc, k, f1, l1);
        end;
      CZoneColumn:
        begin
          if FCellDragLast < 0 then Exit;
          c0 := FDoc.CellAt(FCellDragPara).Index;
          c1 := c.Index;
          CellIn(FCellDragPara, c0, f0, l0);
          CellIn(FCellDragLast, c1, f1, l1);
        end;
    else
      begin
        TyRichCellParasOf(FDoc, FCellDragPara, f0, l0);
        TyRichCellParasOf(FDoc, k, f1, l1);
      end;
    end;
    if (FCellDrag <> CZoneColumn) and (f1 < f0) then
    begin
      // upward: from the end of the pressed one back to the start of this one
      a := Math.Min(t.ParaStart(l0) + t.ParaLength(l0) + 1, t.Length);
      b := t.ParaStart(f1);
    end
    else
    begin
      a := t.ParaStart(f0);
      b := Math.Min(t.ParaStart(l1) + t.ParaLength(l1) + 1, t.Length);
    end;
  finally
    FDoc.EndRead;
  end;
  if (a = FSelAnchor) and (b = FCaret) then Exit;
  Select(a, b, False);
  FWishValid := False;
  CaretMoved;
  DoSelectionChange;
end;

{ The handle of the table under the pointer shows (when that table's first row is in view). }
procedure TTyCustomRichEdit.TableHandleHover(X, Y: Integer);
var
  area: TRect;
  ry: Int64;
  k, j, was: Integer;
  t: TTyRichTable;
  c: TTyRichCell;
  zone, zp: Integer;
begin
  was := FHandlePara;
  // (a viewer shows no handle: it would move nothing)
  if ViewBehind or not SelectionAllowed or FReadOnly or (FBlockCount = 0) then
    FHandlePara := -1
  else if TableZoneAt(X, Y, zone, zp) and (zone = CZoneTable) then
    // (on the handle itself: it stays)
  else
  begin
    FHandlePara := -1;
    area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
    ry := (Int64(Y) - area.Top) * FScale;
    k := 0;
    while (k < FBlockCount - 1) and (ry >= FBlocks[k].Top + FBlocks[k].Height) do Inc(k);
    if (ry >= FBlocks[k].Top) and (ry < FBlocks[k].Top + FBlocks[k].Height) and
       (FBlocks[k].Layout is TTyRowLayout) then
    begin
      FDoc.BeginRead;
      try
        t := FDoc.TableAt(FBlocks[k].FirstPara);
        // its first row among the blocks in view
        for j := 0 to FBlockCount - 1 do
          if (FBlocks[j].Layout is TTyRowLayout) and (FDoc.TableAt(FBlocks[j].FirstPara) = t) then
          begin
            c := nil;
            if FBlocks[j].FirstPara > 0 then c := FDoc.CellAt(FBlocks[j].FirstPara - 1);
            if (c = nil) or (c.Table <> t) then
            begin
              FHandlePara := FBlocks[j].FirstPara;
              Break;
            end;
          end;
      finally
        FDoc.EndRead;
      end;
    end;
  end;
  if FHandlePara <> was then
  begin
    InvalidateSurface;
    Invalidate;
  end;
end;

{ The handle of the table whose first row is block ABlock, in the view's raster (x with the
  scroll in it, as TableZoneAt reads a point): a square of 9 scaled pixels on the table's
  top-left corner - centred on it across (half left into the control's padding, half over the
  first cell's padding), a third of it above (into the bottom of the line above, where only
  descenders reach: half would touch a letter's foot at 150 %) - so it covers no letter. Where the view does not reach that far left (the
  table scrolled out to the left) it stays at the view's left edge; at the top, at the view's
  top. The one rectangle both the paint and the hit test use. }
function TTyCustomRichEdit.TableHandleRect(ABlock: Integer): TRect;
var
  hz, x0, y0, lim: Integer;
  area, clip: TRect;
begin
  hz := Math.Max(5, MulDiv(9, ViewPPI, 96)) * FScale;
  // the left edge of what the surface draws (the clip reaches into the left padding)
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  clip := TextClipOf(Rect(0, 0, Width, Height), area, ViewPPI);
  lim := FScrollX - (area.Left - clip.Left) * FScale;
  x0 := Math.Max(TTyRowLayout(FBlocks[ABlock].Layout).Cells[0].Left - hz div 2, lim);
  // a third above the corner: less than a line's descent, at every scale
  y0 := Math.Max(FBlocks[ABlock].Top - hz div 3, 0);
  Result := Rect(x0, y0, x0 + hz, y0 + hz);
end;

{ The handle of the table under the pointer: a small framed square on the top-left corner
  (TableHandleRect) in the colours of an object's handles - its fill half see-through and
  its cross thin, so what lies under it (a descender, the corner's lines) stays readable. }
procedure TTyCustomRichEdit.PaintTableHandle(ABitmap: TBGRABitmap; AX, AY: Integer;
  const AClip: TRect; const AStyle: TTyRichPaintStyle);
var
  k, hz, x0, y0, m: Integer;
  hr, old: TRect;
  fill: TBGRAPixel;
begin
  if (FHandlePara < 0) or not SelectionAllowed then Exit;
  for k := 0 to FBlockCount - 1 do
    if (FBlocks[k].FirstPara = FHandlePara) and (FBlocks[k].Layout is TTyRowLayout) then
    begin
      hr := TableHandleRect(k);
      hz := hr.Right - hr.Left;
      x0 := AX - FScrollX + hr.Left;
      y0 := AY + hr.Top;
      old := ABitmap.ClipRect;
      ABitmap.ClipRect := AClip;
      try
        fill := AStyle.ObjectHandleFill;
        fill.alpha := fill.alpha div 2;
        ABitmap.FillRect(x0 + 1, y0 + 1, x0 + hz - 1, y0 + hz - 1, fill, dmDrawWithTransparency);
        ABitmap.Rectangle(x0, y0, x0 + hz, y0 + hz, AStyle.ObjectFrame, dmSet);
        // a cross: the four ways it moves the table's selection
        m := hz div 2;
        ABitmap.FillRect(x0 + 2, y0 + m, x0 + hz - 2, y0 + m + 1, AStyle.ObjectFrame, dmSet);
        ABitmap.FillRect(x0 + m, y0 + 2, x0 + m + 1, y0 + hz - 2, AStyle.ObjectFrame, dmSet);
      finally
        ABitmap.ClipRect := old;
      end;
      Exit;
    end;
end;

{ A / B rounded down (B > 0). }
function EdgeFloorDiv(A: Int64; B: Integer): Int64;
begin
  Result := A div B;
  if (A mod B <> 0) and (A < 0) then Dec(Result);
end;

{ ---- column widths and row heights ---- }

function TTyCustomRichEdit.EdgeBand: Integer;
begin
  Result := Math.Max(1, MulDiv(2, ViewPPI, 96)) * Math.Max(1, FScale);
end;

function TTyCustomRichEdit.RasterOfTwips(ATwips: Int64): Int64;
begin
  if (FLayoutPPI <= 0) or (FLayoutZoom <= 0) then Exit(0);
  Result := Round(ATwips * FLayoutPPI * Double(FLayoutZoom) / 1440);
end;

function TTyCustomRichEdit.TwipsOfRaster(ARaster: Int64): Integer;
var
  d: Double;
begin
  Result := 0;
  if (FLayoutPPI <= 0) or (FLayoutZoom <= 0) then Exit;
  d := ARaster * 1440.0 / (FLayoutPPI * Double(FLayoutZoom));
  if d > MaxInt div 2 then d := MaxInt div 2;
  if d < -(MaxInt div 2) then d := -(MaxInt div 2);
  Result := Round(d);
end;

{ A row the view holds whose edges a person may move: a row of a table, laid out, not one that
  holds a nested table (the file's bytes), in a control that edits. }
function TTyCustomRichEdit.EdgeRowOf(ABlock: Integer): TTyRichRow;
var
  c: TTyRichCell;
begin
  Result := nil;
  if (ABlock < 0) or (ABlock >= FBlockCount) or not (FBlocks[ABlock].Layout is TTyRowLayout) then
    Exit;
  FDoc.BeginRead;
  try
    c := FDoc.CellAt(FBlocks[ABlock].FirstPara);
    if (c <> nil) and not c.Row.HoldsNestedTable then Result := c.Row;
  finally
    FDoc.EndRead;
  end;
end;

function TTyCustomRichEdit.EdgesOpen: Boolean;
begin
  // (a page whose text is not to be taken shows no resize cursor either: AllowSelection)
  Result := not FReadOnly and FAllowSelection and IsEnabled and not ViewBehind and
    (FBlockCount > 0) and not (csDesigning in ComponentState) and not PlainTextDocument;
end;

{ An edge under client point X, Y of the rows the view holds: a column's (AKind CEdgeColumn;
  AIndex -1 the row's left, else the cell whose right edge it is) - the line between two cells
  that are not one merged box - or a row's bottom (CEdgeRow), within EdgeBand of it. Only the
  laid-out rows are asked: nothing is read for it. }
function TTyCustomRichEdit.EdgeAt(X, Y: Integer; out AKind, ABlock, AIndex: Integer): Boolean;
var
  area: TRect;
  rx, ry, e, best, d, zlo, zhi: Int64;
  k, i, n: Integer;
  r: TTyRowLayout;
begin
  AKind := CEdgeNone;
  ABlock := -1;
  AIndex := 0;
  Result := False;
  if not EdgesOpen then Exit;
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  rx := (Int64(X) - area.Left) * FScale + FScrollX;
  ry := (Int64(Y) - area.Top) * FScale;
  e := EdgeBand;
  k := 0;
  while (k < FBlockCount - 1) and (ry >= FBlocks[k].Top + FBlocks[k].Height) do Inc(k);
  // a column's edge in the row under the point
  if (ry >= FBlocks[k].Top) and (ry < FBlocks[k].Top + FBlocks[k].Height) and
     (EdgeRowOf(k) <> nil) then
  begin
    r := TTyRowLayout(FBlocks[k].Layout);
    n := r.CellCount;
    best := e + 1;
    // (the left edge's band gives way to the row's zone where that reaches over it)
    if n > 0 then RowZoneSpan(r, zlo, zhi);
    if (n > 0) and (Abs(rx - r.Cells[0].Left) < best) and SelectionAllowed and (rx >= zhi) then
    begin
      best := Abs(rx - r.Cells[0].Left);
      AIndex := -1;
    end;
    for i := 0 to n - 1 do
    begin
      // inside a merged box: no edge there
      if (i < n - 1) and r.Cells[i + 1].Hidden then Continue;
      d := Abs(rx - r.Cells[i].Right);
      if d < best then
      begin
        best := d;
        AIndex := i;
      end;
    end;
    if best <= e then
    begin
      AKind := CEdgeColumn;
      ABlock := k;
      Exit(True);
    end;
  end;
  // a row's bottom: the row it ends (the one above when the point is just below it)
  for i := Math.Max(0, k - 1) to Math.Min(FBlockCount - 1, k + 1) do
    if (Abs(ry - (FBlocks[i].Top + FBlocks[i].Height)) <= e) and (EdgeRowOf(i) <> nil) then
    begin
      r := TTyRowLayout(FBlocks[i].Layout);
      // (not inside a cell merged over rows: the row's bottom there is no line)
      if (r.CellCount > 0) and (rx >= r.Cells[0].Left - e) and
         (rx <= r.Cells[r.CellCount - 1].Right + e) and not r.BottomInSpanAt(Integer(rx)) then
      begin
        AKind := CEdgeRow;
        ABlock := i;
        AIndex := 0;
        Exit(True);
      end;
    end;
end;

{ The narrowest a cell may be: its padding on both sides and one average character of the
  default font (half its size). }
function TTyCustomRichEdit.MinCellTwips(ARow: TTyRichRow; ACell: Integer): Integer;
var
  p: TTyRichCellProps;
  edges: TTyRichEdges;
  w: Integer;
begin
  edges := ARow.CellEdges;
  if (ACell < 0) or (ACell >= Length(edges)) then Exit(1);
  if ACell = 0 then w := edges[0] - ARow.Format.Row.LeftTwips else w := edges[ACell] - edges[ACell - 1];
  p := TyRichEffectiveCellProps(ARow.Format, ACell, w);
  // (the default font's size as it is shown: the theme's when the document sets none)
  Result := Math.Max(0, p.Pad[rcsLeft]) + Math.Max(0, p.Pad[rcsRight]) +
    Math.Max(20, ResolvedFormat(FDoc.DefaultCharFormat).SizeHalfPt * 5);
end;

{ The limits of row ARow's edge AIndex (-1 its left), in twips: kept as they are (ALo, AHi) and
  with the rest of the row following (AShiftLo, AShiftHi). }
{ The limits of a drag of the edge at FEdgeTwips narrowed to what every row the drag moves
  allows there (the selected cells' rows, else the table's): the edge moves by one amount in
  every row that has it, so no row's cell beside it goes below its narrowest while another
  row's could - the rows stay one table. }
function TTyCustomRichEdit.EdgeMovedRows(ARow: TTyRichRow; APara: Integer): TTyRichRowList;
var
  area: TTyRichCellArea;
  first, count, r0, r1: Integer;
  t: TTyRichTable;
  k: Integer;
begin
  Result := nil;
  r0 := 0;
  r1 := MaxInt;
  area := CellArea;
  if area.Range.InTable and (area.Table = ARow.Table) then
  begin
    r0 := area.Range.Row0;
    r1 := area.Range.Row1;
  end;
  t := ARow.Table;
  if not t.Cut and (ARow.Index >= 0) and (ARow.Index < t.RowCount) and (t.Rows[ARow.Index] = ARow) then
  begin
    // (the table's rows as it knows them: no walk of its paragraphs)
    if r1 > t.RowCount - 1 then r1 := t.RowCount - 1;
    if r0 < 0 then r0 := 0;
    if r1 < r0 then Exit;
    SetLength(Result, r1 - r0 + 1);
    for k := r0 to r1 do Result[k - r0] := t.Rows[k];
    Exit;
  end;
  if not FDoc.TableRowsAt(FDoc.Text.ParaStart(APara), r0, r1, Result, first, count) then Result := nil;
end;

procedure TTyCustomRichEdit.SharedEdgeLimits(ARow: TTyRichRow; const ARows: TTyRichRowList;
  AEdgeTwips: Integer; var ALo, AHi, AShiftLo, AShiftHi: Integer);
var
  j, m: Integer;
  fmt: TTyRichRowFormat;
  same: Boolean;
  e: TTyRichEdges;
  lo, hi, slo, shi: Integer;
begin
  fmt := ARow.Format;
  for j := 0 to High(ARows) do
  begin
    if ARows[j] = ARow then Continue;
    // (a row of the same format and edges as ARow's: its limits are ARow's)
    if (ARows[j].Format = fmt) and (ARows[j].BoundaryCount = ARow.BoundaryCount) then
    begin
      same := True;
      for m := 0 to ARow.BoundaryCount - 1 do
        if ARows[j].Boundaries[m] <> ARow.Boundaries[m] then
        begin
          same := False;
          Break;
        end;
      if same then Continue;
    end;
    e := ARows[j].CellEdges;
    for m := 0 to High(e) do
      if Abs(e[m] - AEdgeTwips) <= CRichSharedEdgeTwips then
      begin
        EdgeLimits(ARows[j], m, lo, hi, slo, shi);
        ALo := Math.Max(ALo, lo);
        AHi := Math.Min(AHi, hi);
        AShiftLo := Math.Max(AShiftLo, slo);
        AShiftHi := Math.Min(AShiftHi, shi);
        Break;
      end;
  end;
  if AHi < ALo then AHi := ALo;
  if AShiftHi < AShiftLo then AShiftHi := AShiftLo;
end;

procedure TTyCustomRichEdit.EdgeLimits(ARow: TTyRichRow; AIndex: Integer; out ALo, AHi,
  AShiftLo, AShiftHi: Integer);
var
  edges: TTyRichEdges;
  lft, n, at, right: Integer;
begin
  edges := ARow.CellEdges;
  lft := ARow.Format.Row.LeftTwips;
  n := Length(edges);
  if n > 0 then right := edges[n - 1] else right := lft;
  { (the table no wider than a table may be made - Word's 22 inches -, and no cell narrower
    than its narrowest, the rest following or not) }
  if AIndex < 0 then
  begin
    ALo := Math.Max(lft - CEdgeFar, right - CRichMaxTableTwips);
    if n > 0 then AHi := edges[0] - MinCellTwips(ARow, 0) else AHi := lft;
    AShiftLo := lft - CEdgeFar;
    AShiftHi := lft + CEdgeFar;
    Exit;
  end;
  at := edges[AIndex];
  if AIndex = 0 then ALo := lft + MinCellTwips(ARow, 0)
  else ALo := edges[AIndex - 1] + MinCellTwips(ARow, AIndex);
  AShiftLo := ALo;
  AShiftHi := at + Math.Max(0, lft + CRichMaxTableTwips - right);
  if AIndex < n - 1 then AHi := edges[AIndex + 1] - MinCellTwips(ARow, AIndex + 1)
  else AHi := Math.Max(at, lft + CRichMaxTableTwips);
  if AHi < ALo then AHi := ALo;
  if AShiftHi < AShiftLo then AShiftHi := AShiftLo;
end;

{ The rows an edge change of the row paragraph APara is in takes: the selected cells' rows
  when cells of its table are selected, else - AWhole - every row of its table (refused and
  told for a table a reader gives in parts), or its own row. }
function TTyCustomRichEdit.EdgeRows(APara: Integer; AWhole: Boolean; out ATablePos: TTyRichPos;
  out ARow0, ARow1: Integer): Boolean;
var
  area: TTyRichCellArea;
  c: TTyRichCell;
  ri, n: Integer;
  cut: Boolean;
begin
  Result := False;
  cut := False;
  ATablePos := FDoc.Text.ParaStart(APara);
  ARow0 := 0;
  ARow1 := -1;
  FDoc.BeginRead;
  try
    c := FDoc.CellAt(APara);
    if c = nil then Exit;
    area := CellArea;
    { The selected rows when APara's row is one of them (Word's); an edge dragged anywhere
      else moves for the rows that share it, as with nothing selected }
    if area.Range.InTable and (area.Table = c.Table) and (APara >= area.FirstPara) and
       (APara <= area.LastPara) then
    begin
      ATablePos := area.Range.TablePos;
      ARow0 := area.Range.Row0;
      ARow1 := area.Range.Row1;
      Exit(True);
    end;
    cut := AWhole and c.Table.Cut;
  finally
    FDoc.EndRead;
  end;
  // (told once the read scope is closed: a handler may load another document)
  if cut then
  begin
    EditRefused(rsRichEditRefusedResizeNotWhole);
    Exit;
  end;
  if not FDoc.TableRowIndex(APara, ri, n) then Exit;
  if AWhole then
  begin
    ARow0 := 0;
    ARow1 := n - 1;
  end
  else
  begin
    ARow0 := ri;
    ARow1 := ri;
  end;
  Result := True;
end;

{ A table edge command run as the user's: refused (told once, with the reason that fits a
  resize: PropsRefusalText) or one step; the selection stays. }
function TTyCustomRichEdit.PropsRefusalText(AWhy: TTyRichTableRefusal;
  const AEdit: TTyRichPropEdit): string;
begin
  // a resize's own words where it has them
  if AEdit.OfRows and ((AEdit.EdgeKind <> rekNone) or (rrpHeight in AEdit.Row.Valid)) then
    case AWhy of
      rtrNestedTable: Exit(rsRichEditRefusedResizeNested);
      rtrMergedCells: Exit(rsRichEditRefusedDistributeMerged);
      rtrNotWhole: Exit(rsRichEditRefusedResizeNotWhole);
    end;
  Result := TableRefusalText(AWhy, TyRichTableEdit(rtkInsertColumn, AEdit.Pos, 0));
end;

{ AParts as one step (ADescription), the agreement of facing sides after them over their rows
  and the neighbours (see RunEdgeCommand); taken over. }
function TTyCustomRichEdit.RunEdgeParts(const AParts: array of TTyRichTablePropsCommand;
  const ADescription: string): Boolean;
var
  comp: TTyRichCompositeCommand;
  i, r0, r1: Integer;
  place: TTyRichEditPlace;
  keep: Boolean;
begin
  Result := False;
  if Length(AParts) = 1 then Exit(RunEdgeCommand(AParts[0]));
  if FReadOnly or not IsEnabled or ViewBehind then
  begin
    for i := 0 to High(AParts) do AParts[i].Free;
    Exit;
  end;
  comp := TTyRichCompositeCommand.Create(ADescription);
  r0 := MaxInt;
  r1 := -1;
  for i := 0 to High(AParts) do
  begin
    comp.Add(AParts[i]);
    r0 := Math.Min(r0, AParts[i].Edit.Row0);
    r1 := Math.Max(r1, AParts[i].Edit.Row1);
  end;
  comp.Add(TTyRichAgreeEdges.Create(AParts[0].Edit.Pos, r0 - 1, r1 + 1));
  place := Default(TTyRichEditPlace);
  place.Anchor := CRichPlaceStays;
  place.Caret := CRichPlaceStays;
  keep := FNoEditScroll;
  FNoEditScroll := True;
  FDoc.PropsSkipped := 0;
  try
    Result := RunMade(comp, place, True);
  finally
    FNoEditScroll := keep;
  end;
  TellSkipped;
end;

function TTyCustomRichEdit.RunEdgeCommand(ACmd: TTyRichTablePropsCommand): Boolean;
var
  place: TTyRichEditPlace;
  keep: Boolean;
  cmd: TTyRichCommand;
  comp: TTyRichCompositeCommand;
begin
  Result := False;
  if FReadOnly or not IsEnabled or ViewBehind then
  begin
    ACmd.Free;
    Exit;
  end;
  // (refused: the reason is asked then, and told once - RunEdit)
  place := Default(TTyRichEditPlace);
  place.Anchor := CRichPlaceStays;
  place.Caret := CRichPlaceStays;
  { The view stays where it is: the edge or the row the person moved is where they look, and
    the rows above it may have changed their heights (a scroll to the caret would lay the
    screen out once for the old place and again for the new one). }
  keep := FNoEditScroll;
  FNoEditScroll := True;
  FDoc.PropsSkipped := 0;
  { Edges that moved may line cells of two rows up again (or part them): the sides that now
    face each other agree in the same step, by the rule the insert and delete keep - the line
    drawn there stays (TTyRichAgreeEdges), over the rows moved and their neighbours. }
  cmd := ACmd;
  if not ACmd.Edit.OfRows or (ACmd.Edit.EdgeKind <> rekNone) then
  begin
    comp := TTyRichCompositeCommand.Create(ACmd.Description);
    comp.Add(ACmd);
    comp.Add(TTyRichAgreeEdges.Create(ACmd.Edit.Pos, ACmd.Edit.Row0 - 1, ACmd.Edit.Row1 + 1));
    cmd := comp;
  end;
  try
    Result := RunMade(cmd, place, True);
  finally
    FNoEditScroll := keep;
  end;
  TellSkipped;
end;

{ The horizontal guide of a row drag: a line across the text at client y AValue (-1: none),
  drawn as the column guide is (over the blit). }
procedure TTyCustomRichEdit.SetGuideRow(AValue: Integer);
var
  r: TRect;
begin
  if AValue < 0 then
  begin
    if not FGuideRowOn then Exit;
  end
  else if FGuideRowOn and (AValue = FGuideY) then Exit;
  r := GuideRowRect;
  if not IsRectEmpty(r) then InvalidateArea(r);
  FGuideRowOn := AValue >= 0;
  if FGuideRowOn then FGuideY := AValue;
  r := GuideRowRect;
  if not IsRectEmpty(r) then InvalidateArea(r);
end;

function TTyCustomRichEdit.GuideRowRect: TRect;
var
  tw: TRect;
begin
  Result := Rect(0, 0, 0, 0);
  if not FGuideRowOn then Exit;
  tw := TextWindowRect;
  Result := Rect(tw.Left, FGuideY, tw.Right, FGuideY + Math.Max(1, MulDiv(1, ViewPPI, 96)));
  if not IntersectRect(Result, Result, tw) then Result := Rect(0, 0, 0, 0);
end;

function TTyCustomRichEdit.EdgeDragging: Boolean;
begin
  Result := FEdgeDrag <> CEdgeNone;
end;

{ A press on an edge: a drag begins (the guide shows where the edge is), or - a double click on
  a column's edge - the column left of it takes its content's width. }
function TTyCustomRichEdit.EdgePress(X, Y: Integer; AShift: TShiftState): Boolean;
var
  kind, k, idx: Integer;
  row: TTyRichRow;
  area: TRect;
  edges: TTyRichEdges;
  r: TTyRowLayout;
  lo, hi, slo, shi: Integer;
begin
  Result := EdgeAt(X, Y, kind, k, idx);
  if not Result then Exit;
  row := EdgeRowOf(k);
  if row = nil then Exit(False);
  r := TTyRowLayout(FBlocks[k].Layout);
  if (ssDouble in AShift) and (kind = CEdgeColumn) then
  begin
    if idx >= 0 then FitColumnAt(FBlocks[k].FirstPara, idx);
    Exit;
  end;
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  FEdgeDrag := kind;
  FEdgePara := FBlocks[k].FirstPara;
  FEdgeIndex := idx;
  FEdgeShift := ssShift in AShift;
  FDoc.BeginRead;
  try
    edges := row.CellEdges;
    if kind = CEdgeColumn then
    begin
      if idx < 0 then
      begin
        FEdgeTwips := row.Format.Row.LeftTwips;
        FEdgeRaster := r.Cells[0].Left;
      end
      else
      begin
        FEdgeTwips := edges[idx];
        FEdgeRaster := r.Cells[idx].Right;
      end;
      EdgeLimits(row, idx, lo, hi, slo, shi);
      if idx >= 0 then SharedEdgeLimits(row, EdgeMovedRows(row, FEdgePara), FEdgeTwips, lo, hi, slo, shi);
      FEdgeLo := FEdgeRaster + RasterOfTwips(Int64(lo) - FEdgeTwips);
      FEdgeHi := FEdgeRaster + RasterOfTwips(Int64(hi) - FEdgeTwips);
      FEdgeShiftLo := FEdgeRaster + RasterOfTwips(Int64(slo) - FEdgeTwips);
      FEdgeShiftHi := FEdgeRaster + RasterOfTwips(Int64(shi) - FEdgeTwips);
    end
    else
    begin
      // a row's bottom: never above its content's own height
      FEdgeTop := FBlocks[k].Top;
      FEdgeRaster := FBlocks[k].Top + FBlocks[k].Height;
      FEdgeLo := FBlocks[k].Top + r.NaturalHeight;
      FEdgeHi := FEdgeRaster + RasterOfTwips(CEdgeFar);
      FEdgeShiftLo := FEdgeLo;
      FEdgeShiftHi := FEdgeHi;
    end;
  finally
    FDoc.EndRead;
  end;
  FEdgeNow := FEdgeRaster;
  { (pressed beside the line, within its band: a release there moves nothing, a move takes the
    edge as far as the pointer went) }
  if kind = CEdgeColumn then FEdgeGrab := (Int64(X) - area.Left) * FScale + FScrollX - FEdgeRaster
  else FEdgeGrab := (Int64(Y) - area.Top) * FScale - FEdgeRaster;
  ShowEdgeGuide;
end;

procedure TTyCustomRichEdit.ShowEdgeGuide;
var
  area: TRect;
  s: Integer;
begin
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  s := Math.Max(1, FScale);
  if FEdgeDrag = CEdgeColumn then
    SetGuideLine(Math.Max(0, area.Left + Integer(EdgeFloorDiv(FEdgeNow - FScrollX, s))))
  else if FEdgeDrag = CEdgeRow then
    SetGuideRow(Math.Max(0, area.Top + Integer(EdgeFloorDiv(FEdgeNow, s))));
end;

{ A drag's move: the edge follows the pointer within its limits (those with the rest following
  while Shift is held); only the guide is drawn - nothing is laid out. }
procedure TTyCustomRichEdit.EdgeMove(X, Y: Integer; AShift: TShiftState);
var
  area: TRect;
  v, lo, hi: Int64;
begin
  if FEdgeDrag = CEdgeNone then Exit;
  FEdgeShift := ssShift in AShift;
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  if FEdgeDrag = CEdgeColumn then v := (Int64(X) - area.Left) * FScale + FScrollX - FEdgeGrab
  else v := (Int64(Y) - area.Top) * FScale - FEdgeGrab;
  if FEdgeShift then
  begin
    lo := FEdgeShiftLo;
    hi := FEdgeShiftHi;
  end
  else
  begin
    lo := FEdgeLo;
    hi := FEdgeHi;
  end;
  if v < lo then v := lo;
  if v > hi then v := hi;
  FEdgeNow := v;
  ShowEdgeGuide;
end;

procedure TTyCustomRichEdit.CancelEdgeDrag;
begin
  if FEdgeDrag = CEdgeNone then Exit;
  FEdgeDrag := CEdgeNone;
  SetGuideLine(-1);
  SetGuideRow(-1);
end;

{ The release: ONE command where the edge moved, nothing where it did not. }
procedure TTyCustomRichEdit.EdgeRelease(X, Y: Integer; AShift: TShiftState);
var
  kind, r0, r1, h: Integer;
  pos: TTyRichPos;
  d: Int64;
  rp: TTyRichRowProps;
begin
  if FEdgeDrag = CEdgeNone then Exit;
  EdgeMove(X, Y, AShift);
  kind := FEdgeDrag;
  CancelEdgeDrag;
  d := FEdgeNow - FEdgeRaster;
  if d = 0 then Exit;
  if kind = CEdgeColumn then
  begin
    if not EdgeRows(FEdgePara, True, pos, r0, r1) then Exit;
    RunEdgeCommand(TTyRichSetColumnEdge.Create(pos, FEdgeTwips, FEdgeTwips + TwipsOfRaster(d),
      r0, r1, FEdgeShift));
  end
  else
  begin
    if not EdgeRows(FEdgePara, False, pos, r0, r1) then Exit;
    h := Math.Max(1, TwipsOfRaster(FEdgeNow - FEdgeTop));
    rp := Default(TTyRichRowProps);
    rp.Valid := [rrpHeight];
    rp.HeightTwips := h;
    RunEdgeCommand(TTyRichSetRowHeight.Create(pos, r0, r1, rp));
  end;
end;

{ The widest unbreakable run of paragraph APara (raster pixels): its fragments laid out on one
  line, the widths between spaces, tabs and breaks added up. }
function TTyCustomRichEdit.WidestRun(APara: Integer): Integer;
var
  L: TTyParaLayout;
  i, run: Integer;
  f: TTyRichFragment;
begin
  Result := 0;
  L := FLayouter.LayoutPara(FDoc, APara, CRichNoWrap, FLayoutPPI, FLayoutZoom);
  try
    run := 0;
    for i := 0 to L.FragmentCount - 1 do
    begin
      f := L.Fragments[i];
      if f.Kind in [rfkSpace, rfkTab, rfkBreak] then run := 0
      else
      begin
        Inc(run, f.Natural);
        if run > Result then Result := run;
      end;
    end;
  finally
    L.Release;
  end;
end;

{ The column of cell ACell of the row paragraph APara is in takes the width of its widest
  content - the longest unbreakable run of its cells (in the selected rows, else every row)
  and their padding, at most the text's width - and the columns right of it shift. One step. }
function TTyCustomRichEdit.FitColumnAt(APara, ACell: Integer): Boolean;
var
  w: Integer;
begin
  Result := False;
  if not FitWidthOf(APara, ACell, w) then Exit;
  Result := SetColumnWidths(APara, ACell, [w], True);
end;

{ The width column ACell's widest content asks in the rows a width door takes there (its
  padding included, no less than the narrowest a cell may be, no more than the view). }
function TTyCustomRichEdit.FitWidthOf(APara, ACell: Integer; out AWidth: Integer): Boolean;
var
  info: TTyRichTableInfo;
  pos: TTyRichPos;
  r0, r1, k, ri, n, w, widest, lft, cap: Integer;
  c, rc: TTyRichCell;
  row, cur: TTyRichRow;
  edges: TTyRichEdges;
  p: TTyRichCellProps;
begin
  Result := False;
  AWidth := 0;
  if not EdgesOpen or (FLayoutPPI <= 0) then Exit;
  if not EdgeRows(APara, True, pos, r0, r1) then Exit;
  if not FDoc.TableInfoAt(APara, info) then Exit;
  widest := 0;
  FDoc.BeginRead;
  try
    row := FDoc.CellAt(APara).Row;
    edges := row.CellEdges;
    if (ACell < 0) or (ACell >= Length(edges)) then Exit;
    // the rows r0 .. r1 of the table, counted as its paragraphs go
    ri := -1;
    cur := nil;
    for k := info.First to info.Last do
    begin
      rc := FDoc.CellAt(k);
      if rc = nil then Continue;
      if rc.Row <> cur then
      begin
        cur := rc.Row;
        Inc(ri);
      end;
      if ri < r0 then Continue;
      if ri > r1 then Break;
      if rc.Index <> ACell then Continue;
      w := WidestRun(k);
      if ACell = 0 then n := cur.CellEdges[0] - cur.Format.Row.LeftTwips
      else if ACell < cur.CellCount then n := cur.CellEdges[ACell] - cur.CellEdges[ACell - 1]
      else n := 1;
      p := TyRichEffectiveCellProps(cur.Format, Math.Min(ACell, cur.CellCount - 1), n);
      w := TwipsOfRaster(w) + Math.Max(0, p.Pad[rcsLeft]) + Math.Max(0, p.Pad[rcsRight]);
      if w > widest then widest := w;
    end;
    if ACell = 0 then lft := row.Format.Row.LeftTwips else lft := edges[ACell - 1];
    widest := Math.Max(widest, MinCellTwips(row, ACell));
    cap := TwipsOfRaster(Math.Max(1, FLayoutWidth));
    if (FLayoutWidth > 0) and (widest > cap) then widest := cap;
    c := FDoc.CellAt(APara);
    n := edges[ACell];
  finally
    FDoc.EndRead;
  end;
  if c = nil then Exit;
  AWidth := widest;
  Result := True;
end;

{ ---- the user's doors ---- }

{ The caret's cell (its paragraph, its index) for a door that resizes: False - told once,
  ATell - when the caret is in no table, or in a row that holds a nested table. }
function TTyCustomRichEdit.CaretEdgePara(out APara, ACell: Integer; ATell: Boolean): Boolean;
var
  c: TTyRichCell;
  why: string;
begin
  Result := False;
  APara := CaretCellPara;
  ACell := -1;
  why := '';
  FDoc.BeginRead;
  try
    c := FDoc.CellAt(APara);
    if c = nil then why := rsRichEditRefusedNoTable
    else if c.Row.HoldsNestedTable then why := rsRichEditRefusedResizeNested
    else ACell := c.Index;
  finally
    FDoc.EndRead;
  end;
  if why <> '' then
  begin
    if ATell then EditRefused(why);
    Exit;
  end;
  Result := True;
end;

{ The caret's paragraph is read already (a file read on demand gives its paragraphs only when
  asked): what the Can... queries of the table formats go by - nothing is read just to
  answer them (an action's update after Select All in 100 MB). }
function TTyCustomRichEdit.CaretParaRead: Boolean;
var
  k: Integer;
begin
  k := CaretCellPara;
  Result := (FDoc.Loader = nil) or (k < 0) or (k >= FDoc.Text.ParaCount) or
    (FDoc.Text.ParaData[k] <> nil);
end;

function TTyCustomRichEdit.CanResizeColumns: Boolean;
var
  p, c: Integer;
begin
  Result := TableActionsOpen and CaretParaRead and CaretEdgePara(p, c, False);
end;

function TTyCustomRichEdit.CanResizeRows: Boolean;
var
  p, c: Integer;
begin
  Result := TableActionsOpen and CaretParaRead and CaretEdgePara(p, c, False);
end;

function TTyCustomRichEdit.UserTableDoorOpen: Boolean;
begin
  Result := False;
  EndOwedLoad;
  EndCompositionForUser;
  if not IsEnabled or ViewBehind or FReadOnly then Exit;
  if PlainTextDocument then
  begin
    EditRefused(rsRichEditRefusedPlainTable);
    Exit;
  end;
  Result := True;
end;

function TTyCustomRichEdit.SetColumnWidth(AWidthTwips: Integer): Boolean;
var
  p, c, c0, c1, k: Integer;
  widths: array of Integer;
begin
  Result := False;
  if not UserTableDoorOpen then Exit;
  if not CaretEdgePara(p, c, True) then Exit;
  if AWidthTwips < 1 then
  begin
    EditRefused(rsRichEditRefusedRange);
    Exit;
  end;
  // (every column the selection covers, as Word gives them the width)
  WidthColumns(p, c, c0, c1);
  widths := nil;
  SetLength(widths, c1 - c0 + 1);
  for k := 0 to High(widths) do widths[k] := AWidthTwips;
  Result := SetColumnWidths(p, c0, widths);
end;

procedure TTyCustomRichEdit.WidthColumns(APara, ACell: Integer; out ACol0, ACol1: Integer);
var
  area: TTyRichCellArea;
  c: TTyRichCell;
begin
  ACol0 := ACell;
  ACol1 := ACell;
  area := CellArea;
  if not area.Range.InTable then Exit;
  FDoc.BeginRead;
  try
    c := FDoc.CellAt(APara);
    if (c = nil) or (c.Table <> area.Table) then Exit;
    ACol0 := area.Range.Col0;
    ACol1 := Math.Min(area.Range.Col1, c.Row.CellCount - 1);
    if area.AllCells then
    begin
      ACol0 := 0;
      ACol1 := c.Row.CellCount - 1;
    end;
  finally
    FDoc.EndRead;
  end;
end;

function TTyCustomRichEdit.SetColumnWidths(APara, ACol0: Integer; const AWidths: array of Integer;
  AKeepContent: Boolean): Boolean;
var
  pos: TTyRichPos;
  r0, r1, i, c, lft, w, shift, old, nw: Integer;
  row: TTyRichRow;
  edges: TTyRichEdges;
  parts: array of TTyRichTablePropsCommand;
  rows: TTyRichRowList;
  first, count: Integer;
  info: TTyRichTableInfo;
  haveInfo: Boolean;
  widest: Integer;

  { The leftmost the edge at AOld (as the rows had it) may go, moved by AShift already where
    the rows before it moved: the cell that ends there in each row r0 .. r1 that has it keeps
    its narrowest - and its content's width, AKeepContent }
  function Floor(AOld, AShift: Integer): Integer;
  var
    r, j, l, k, ri, wc, n: Integer;
    e: TTyRichEdges;
    rc: TTyRichCell;
    cur: TTyRichRow;
    p: TTyRichCellProps;
  begin
    Result := -MaxInt;
    for r := 0 to High(rows) do
    begin
      e := rows[r].CellEdges;
      for j := 0 to High(e) do
        if Abs(e[j] - AOld) <= CRichSharedEdgeTwips then
        begin
          if j = 0 then l := rows[r].Format.Row.LeftTwips else l := e[j - 1] + AShift;
          Result := Math.Max(Result, l + MinCellTwips(rows[r], j));
          Break;
        end;
    end;
    if not AKeepContent or not haveInfo then Exit;
    // (the content of each such cell: the table's paragraphs of rows r0 .. r1)
    ri := -1;
    cur := nil;
    for k := info.First to info.Last do
    begin
      rc := FDoc.CellAt(k);
      if rc = nil then Continue;
      if rc.Row <> cur then
      begin
        cur := rc.Row;
        Inc(ri);
      end;
      if ri < r0 then Continue;
      if ri > r1 then Break;
      e := cur.CellEdges;
      j := rc.Index;
      if (j > High(e)) or (Abs(e[j] - AOld) > CRichSharedEdgeTwips) then Continue;
      if FDoc.Text.ParaLength(k) = 0 then Continue;
      if j = 0 then l := cur.Format.Row.LeftTwips else l := e[j - 1];
      n := e[j] - l;
      if j > 0 then Inc(l, AShift);
      p := TyRichEffectiveCellProps(cur.Format, j, Math.Max(1, n));
      wc := TwipsOfRaster(WidestRun(k)) + Math.Max(0, p.Pad[rcsLeft]) + Math.Max(0, p.Pad[rcsRight]);
      Result := Math.Max(Result, l + wc);
    end;
  end;

begin
  Result := False;
  if not EdgeRows(APara, True, pos, r0, r1) then Exit;
  haveInfo := AKeepContent and FDoc.TableInfoAt(APara, info);
  parts := nil;
  FDoc.BeginRead;
  try
    row := FDoc.CellAt(APara).Row;
    edges := row.CellEdges;
    if not FDoc.TableRowsAt(pos, r0, r1, rows, first, count) then rows := nil;
    widest := 0;
    for i := 0 to High(rows) do
      if rows[i].CellCount > 0 then widest := Math.Max(widest, rows[i].CellEdges[rows[i].CellCount - 1]);
    if widest = 0 then widest := edges[High(edges)];
    { each edge in turn, the rest of the row following it: an edge after one that moved has
      moved by as much (shift) }
    shift := 0;
    for i := 0 to High(AWidths) do
    begin
      c := ACol0 + i;
      if (c < 0) or (c > High(edges)) then Break;
      if c = 0 then lft := row.Format.Row.LeftTwips else lft := edges[c - 1] + shift;
      w := Math.Max(AWidths[i], MinCellTwips(row, c));
      old := edges[c] + shift;
      nw := lft + w;
      // (one floor for every row that has the edge: they all move by as much)
      if Length(rows) > 0 then nw := Math.Max(nw, Floor(edges[c], shift));
      // (and the widest row no wider than a table may be made: the rest follows)
      if (widest > 0) and (widest + shift + (nw - old) > row.Format.Row.LeftTwips + CRichMaxTableTwips) then
        nw := Math.Max(old, row.Format.Row.LeftTwips + CRichMaxTableTwips - widest - shift + old);
      if nw = old then Continue;
      SetLength(parts, Length(parts) + 1);
      parts[High(parts)] := TTyRichSetColumnEdge.Create(pos, old, nw, r0, r1, True);
      Inc(shift, nw - old);
    end;
  finally
    FDoc.EndRead;
  end;
  if Length(parts) = 0 then Exit(True);
  Result := RunEdgeParts(parts, rsRichUndoColumnWidth);
end;

function TTyCustomRichEdit.SetRowHeight(ATwips: Integer; AExact: Boolean): Boolean;
var
  p, c, r0, r1: Integer;
  pos: TTyRichPos;
  rp: TTyRichRowProps;
begin
  Result := False;
  if not UserTableDoorOpen then Exit;
  if not CaretEdgePara(p, c, True) then Exit;
  if (ATwips < 0) or (AExact and (ATwips = 0)) then
  begin
    EditRefused(rsRichEditRefusedRange);
    Exit;
  end;
  if not EdgeRows(p, False, pos, r0, r1) then Exit;
  rp := Default(TTyRichRowProps);
  rp.Valid := [rrpHeight];
  if AExact then rp.HeightTwips := -ATwips else rp.HeightTwips := ATwips;
  Result := RunEdgeCommand(TTyRichSetRowHeight.Create(pos, r0, r1, rp));
end;

function TTyCustomRichEdit.AutoFitColumn: Boolean;
var
  p, c, c0, c1, k: Integer;
  widths: array of Integer;
begin
  Result := False;
  if not UserTableDoorOpen then Exit;
  if not CaretEdgePara(p, c, True) then Exit;
  // every column the selection covers, each to its own content
  WidthColumns(p, c, c0, c1);
  widths := nil;
  SetLength(widths, c1 - c0 + 1);
  for k := 0 to High(widths) do
    if not FitWidthOf(p, c0 + k, widths[k]) then Exit;
  Result := SetColumnWidths(p, c0, widths, True);
end;

function TTyCustomRichEdit.DistributeColumns: Boolean;
var
  p, c, r0, r1, i, ca, cb, n: Integer;
  pos: TTyRichPos;
  g: TTyRichGrid;
  gc: TTyRichGridCell;
  plain: Boolean;
  area: TTyRichCellArea;
  newE: array of Integer;
  comp: TTyRichCompositeCommand;
  place: TTyRichEditPlace;
  keep: Boolean;
  x0, x1: Int64;
begin
  Result := False;
  if not UserTableDoorOpen then Exit;
  if not CaretEdgePara(p, c, True) then Exit;
  if not EdgeRows(p, True, pos, r0, r1) then Exit;
  { A table that is no plain grid (merged cells, rows of different cells): by the grid - its
    columns under the selection (else all) as wide as each other, each edge moved in the rows
    that have it, so every cell keeps the grid's columns it covered. }
  g := TableGrid(pos);
  try
    plain := g = nil;
    if g <> nil then
    begin
      plain := True;
      for i := 0 to g.RowCount - 1 do
      begin
        if g.CellCountOfRow(i) <> g.ColCount then plain := False;
        for c := 0 to g.CellCountOfRow(i) - 1 do
        begin
          gc := g.CellOf(i, c);
          if gc.Covered or (gc.ColSpan <> 1) or (gc.RowSpan <> 1) then plain := False;
        end;
      end;
    end;
    if plain then
    begin
      Result := RunEdgeCommand(TTyRichSetRowWidths.CreateDistribute(pos, r0, r1));
      Exit;
    end;
    area := CellArea;
    ca := 0;
    cb := g.ColCount - 1;
    if TyRichCellsEditable(area) and not area.AllCells then
    begin
      x0 := area.X0;
      x1 := area.X1;
      while (ca < cb) and (g.Edge(ca) < x0 - CRichEdgeSlackTwips) do Inc(ca);
      while (cb > ca) and (g.Edge(cb + 1) > x1 + CRichEdgeSlackTwips) do Dec(cb);
    end;
    n := cb - ca + 1;
    if n < 2 then Exit;
    SetLength(newE, g.ColCount + 1);
    for i := 0 to g.ColCount do newE[i] := g.Edge(i);
    for i := ca + 1 to cb do
      newE[i] := g.Edge(ca) + Int64(g.Edge(cb + 1) - g.Edge(ca)) * (i - ca) div n;
    comp := TTyRichCompositeCommand.Create(rsRichUndoColumnWidth);
    // (those that go right from the right, then those that go left from the left: none crosses)
    for i := cb downto ca + 1 do
      if newE[i] > g.Edge(i) then comp.Add(TTyRichSetColumnEdge.Create(pos, g.Edge(i), newE[i], r0, r1, False));
    for i := ca + 1 to cb do
      if newE[i] < g.Edge(i) then comp.Add(TTyRichSetColumnEdge.Create(pos, g.Edge(i), newE[i], r0, r1, False));
  finally
    g.Free;
  end;
  if comp.Count = 0 then
  begin
    comp.Free;
    Exit;
  end;
  comp.Add(TTyRichAgreeEdges.Create(pos, r0 - 1, r1 + 1));
  place := Default(TTyRichEditPlace);
  place.Anchor := CRichPlaceStays;
  place.Caret := CRichPlaceStays;
  keep := FNoEditScroll;
  FNoEditScroll := True;
  try
    Result := RunMade(comp, place, True);
  finally
    FNoEditScroll := keep;
  end;
end;

{ The rows (selected, else the table's) as high as their average now, each at least that.
  Synchronous: every row in range is laid out to read its height - about 0.5 s for a table of
  10,000 rows of three cells, to the end of the paint after it (the performance suite's line,
  460 - 500 ms). Above the threshold the control's other long synchronous work
  uses (CopyWaitChars, a laid-out paragraph counted as CRichLayoutParaChars characters) the
  wait cursor shows meanwhile. }
function TTyCustomRichEdit.DistributeRows: Boolean;
var
  p, c, r0, r1, k, ri, cnt: Integer;
  pos: TTyRichPos;
  info: TTyRichTableInfo;
  rc: TTyRichCell;
  cur: TTyRichRow;
  b: TTyBlockLayout;
  total: Int64;
  rp: TTyRichRowProps;
  wait: Boolean;
begin
  Result := False;
  if not UserTableDoorOpen then Exit;
  if not CaretEdgePara(p, c, True) then Exit;
  if not EdgeRows(p, True, pos, r0, r1) then Exit;
  if (FLayoutPPI <= 0) or not FDoc.TableInfoAt(p, info) then Exit;
  total := 0;
  cnt := 0;
  ri := -1;
  cur := nil;
  wait := Int64(info.Last - info.First + 1) * CRichLayoutParaChars > FCopyWaitChars;
  if wait then BeginWait;
  try
  k := info.First;
  while k <= info.Last do
  begin
    FDoc.BeginRead;
    try
      rc := FDoc.CellAt(k);
    finally
      FDoc.EndRead;
    end;
    if (rc <> nil) and (rc.Row <> cur) then
    begin
      cur := rc.Row;
      Inc(ri);
      if ri > r1 then Break;
      if ri >= r0 then
      begin
        b := FLayouter.LayoutBlock(FDoc, k, FLayoutWidth, FLayoutPPI, FLayoutZoom);
        try
          Inc(total, b.Height);
          Inc(cnt);
          k := b.LastPara + 1;
        finally
          b.Release;
        end;
        Continue;
      end;
    end;
    Inc(k);
  end;
  finally
    if wait then EndWait;
  end;
  if cnt = 0 then Exit;
  rp := Default(TTyRichRowProps);
  rp.Valid := [rrpHeight];
  rp.HeightTwips := Math.Max(1, TwipsOfRaster(total div cnt));
  Result := RunEdgeCommand(TTyRichSetRowHeight.Create(pos, r0, r1, rp));
end;

function TTyCustomRichEdit.FitTableToWindow: Boolean;
var
  p, c, r0, r1: Integer;
  pos: TTyRichPos;
begin
  Result := False;
  if not UserTableDoorOpen then Exit;
  if not CaretEdgePara(p, c, True) then Exit;
  if (FLayoutPPI <= 0) or (FLayoutWidth <= 0) then Exit;
  if not EdgeRows(p, True, pos, r0, r1) then Exit;
  Result := RunEdgeCommand(TTyRichSetRowWidths.CreateFit(pos, r0, r1, TwipsOfRaster(FLayoutWidth)));
end;

{ ---- for a ruler ---- }

function TTyCustomRichEdit.CaretRowEdges(out AEdges: TTyRichColumnEdges): Boolean;
var
  v: TTyRichParaView;
  k, i, n, lo, hi, slo, shi, x: Integer;
  row: TTyRichRow;
  r: TTyRowLayout;
  item: TTyRichRowItem;
  edges: TTyRichEdges;
  t: TTyRichText;
  caret: TTyRichPos;
  zero: Int64;
begin
  AEdges := nil;
  Result := False;
  if not ParagraphView(v) or not v.InCell then Exit;
  t := FDoc.Text;
  caret := t.ParaStart(v.Para);
  k := HeldBlockOf(caret);
  row := EdgeRowOf(k);
  if row = nil then Exit;
  r := TTyRowLayout(FBlocks[k].Layout);
  i := r.ItemAt(caret - t.ParaStart(FBlocks[k].FirstPara));
  if i < 0 then Exit;
  item := r.Items[i];
  zero := item.X;
  FDoc.BeginRead;
  try
    edges := row.CellEdges;
    n := Length(edges);
    SetLength(AEdges, n + 1);
    for i := -1 to n - 1 do
    begin
      if i < 0 then x := r.Cells[0].Left else x := r.Cells[i].Right;
      AEdges[i + 1].Index := i;
      AEdges[i + 1].Offset := TwipsOfRaster(x - zero);
      if i < 0 then AEdges[i + 1].Twips := row.Format.Row.LeftTwips
      else AEdges[i + 1].Twips := edges[i];
      AEdges[i + 1].Hidden := (i < n - 1) and (i + 1 < r.CellCount) and r.Cells[i + 1].Hidden;
      EdgeLimits(row, i, lo, hi, slo, shi);
      AEdges[i + 1].MinOffset := AEdges[i + 1].Offset + (lo - AEdges[i + 1].Twips);
      AEdges[i + 1].MaxOffset := AEdges[i + 1].Offset + (hi - AEdges[i + 1].Twips);
      AEdges[i + 1].ShiftMinOffset := AEdges[i + 1].Offset + (slo - AEdges[i + 1].Twips);
      AEdges[i + 1].ShiftMaxOffset := AEdges[i + 1].Offset + (shi - AEdges[i + 1].Twips);
    end;
  finally
    FDoc.EndRead;
  end;
  Result := True;
end;

function TTyCustomRichEdit.MoveCaretRowEdge(AIndex, AOffsetTwips: Integer; AShiftRest: Boolean): Boolean;
var
  e: TTyRichColumnEdges;
  i, v, r0, r1, lo, hi, slo, shi: Integer;
  row: TTyRichRow;
  pos: TTyRichPos;
  pv: TTyRichParaView;
begin
  Result := False;
  if not UserTableDoorOpen then Exit;
  if not CaretRowEdges(e) then
  begin
    EditRefused(rsRichEditRefusedNoTable);
    Exit;
  end;
  for i := 0 to High(e) do
    if e[i].Index = AIndex then
    begin
      { (the limits of every row the move takes, as a drag has them: the rows are read here,
        for the one edge that moves - not for every edge CaretRowEdges gives) }
      ParagraphView(pv);
      FDoc.BeginRead;
      try
        row := FDoc.CellAt(pv.Para).Row;
        EdgeLimits(row, AIndex, lo, hi, slo, shi);
        if AIndex >= 0 then SharedEdgeLimits(row, EdgeMovedRows(row, pv.Para), e[i].Twips, lo, hi, slo, shi);
      finally
        FDoc.EndRead;
      end;
      e[i].MinOffset := Math.Max(e[i].MinOffset, e[i].Offset + (lo - e[i].Twips));
      e[i].MaxOffset := Math.Min(e[i].MaxOffset, e[i].Offset + (hi - e[i].Twips));
      e[i].ShiftMinOffset := Math.Max(e[i].ShiftMinOffset, e[i].Offset + (slo - e[i].Twips));
      e[i].ShiftMaxOffset := Math.Min(e[i].ShiftMaxOffset, e[i].Offset + (shi - e[i].Twips));
      if AShiftRest then
        v := Math.Min(Math.Max(AOffsetTwips, e[i].ShiftMinOffset), e[i].ShiftMaxOffset)
      else
        v := Math.Min(Math.Max(AOffsetTwips, e[i].MinOffset), e[i].MaxOffset);
      if v = e[i].Offset then Exit;
      ParagraphView(pv);
      if not EdgeRows(pv.Para, True, pos, r0, r1) then Exit;
      Result := RunEdgeCommand(TTyRichSetColumnEdge.Create(pos, e[i].Twips,
        e[i].Twips + (v - e[i].Offset), r0, r1, AShiftRest));
      Exit;
    end;
end;

{ ---- cell formats: shading, borders, padding, alignment ---- }

{ The cells a format door changes: the selected cells (both ends of the selection in one
  table), else the caret's cell. False (told once, ATell) in no table or in a row that holds a
  nested table. }
function TTyCustomRichEdit.CellTarget(out ATablePos: TTyRichPos; out ARow0, ACol0, ARow1,
  ACol1: Integer; ATell: Boolean): Boolean;
var
  area: TTyRichCellArea;
  p, c, n, f, l: Integer;
begin
  Result := False;
  ATablePos := -1;
  ARow0 := 0;
  ACol0 := 0;
  ARow1 := -1;
  ACol1 := -1;
  area := CellArea;
  { The cells selected - also rows reached from outside the table: what is highlighted, every
    cell of them, is what the doors take }
  if area.Range.InTable then
  begin
    ATablePos := area.Range.TablePos;
    ARow0 := area.Range.Row0;
    ARow1 := area.Range.Row1;
    ACol0 := area.Range.Col0;
    ACol1 := area.Range.Col1;
    if area.AllCells then ACol1 := CRichAllCells;
    Exit(True);
  end;
  if not CaretEdgePara(p, c, ATell) then Exit;
  if not CaretCell(ATablePos, ARow0, ACol0) then Exit;
  ARow1 := ARow0;
  ACol1 := ACol0;
  { A caret in a cell merged down stands for the cell: its rows' cells of it, as a selection
    of the cell has them }
  if MergedRowsOf(CaretCellPara, n, f, l) and TyRichCellParasOf(FDoc, CaretCellPara, f, l) then
  begin
    area := TyRichCellArea(FDoc, FDoc.Text.ParaStart(f),
      FDoc.Text.ParaStart(l) + FDoc.Text.ParaLength(l) + 1);
    if area.Range.InTable then
    begin
      ARow0 := area.Range.Row0;
      ARow1 := area.Range.Row1;
      ACol0 := area.Range.Col0;
      ACol1 := area.Range.Col1;
    end;
  end;
  Result := True;
end;

function TTyCustomRichEdit.CanFormatCells: Boolean;
var
  pos: TTyRichPos;
  r0, c0, r1, c1: Integer;
begin
  Result := TableActionsOpen and CaretParaRead and CellTarget(pos, r0, c0, r1, c1, False);
end;

{ ACmd run as a table properties edit; ASkipped: rows its maker left as they are already (they
  hold a nested table) - told once with those the edit leaves, when it ran. }
function TTyCustomRichEdit.RunCellProps(ACmd: TTyRichCommand; ASkipped: Integer): Boolean;
var
  place: TTyRichEditPlace;
  keep: Boolean;
begin
  Result := False;
  if FReadOnly or not IsEnabled or ViewBehind then
  begin
    ACmd.Free;
    Exit;
  end;
  place := Default(TTyRichEditPlace);
  place.Anchor := CRichPlaceStays;
  place.Caret := CRichPlaceStays;
  keep := FNoEditScroll;
  FNoEditScroll := True;
  FDoc.PropsSkipped := ASkipped;
  try
    Result := RunMade(ACmd, place, True);
  finally
    FNoEditScroll := keep;
  end;
  if Result then TellSkipped else FDoc.PropsSkipped := 0;
end;

{ Rows the last table properties edit left as they were (they hold a nested table): told once. }
procedure TTyCustomRichEdit.TellSkipped;
begin
  if FDoc.PropsSkipped > 0 then
  begin
    FDoc.PropsSkipped := 0;
    EditRefused(rsRichEditRefusedResizeNested);
  end;
end;

function TTyCustomRichEdit.SetCellShading(AColor: TColor): Boolean;
var
  pos: TTyRichPos;
  r0, c0, r1, c1: Integer;
  p: TTyRichCellProps;
begin
  Result := False;
  if not UserTableDoorOpen then Exit;
  if not CellTarget(pos, r0, c0, r1, c1, True) then Exit;
  p := Default(TTyRichCellProps);
  p.Valid := [rcpShading];
  p.Shading := AColor;
  Result := RunCellProps(TTyRichSetCellProps.Create(pos, r0, c0, r1, c1, p));
end;

function TTyCustomRichEdit.SetCellBorders(APreset: TTyRichBorderPreset;
  const ABorder: TTyRichBorder): Boolean;
var
  pos: TTyRichPos;
  r0, c0, r1, c1, skipped: Integer;
  comp: TTyRichCompositeCommand;
  b: TTyRichBorder;
  plan: TTyRichBorderPlan;

  { The lines ALines of the selected cells get the border - and the facing side of the cell
    beside each of their sides (TTyRichBorderPlan: one line two cells share has one
    definition, as Word keeps it); each row's last cell in the selection is its right edge }
  procedure MarkLines(ALines: TTyRichCellLines);
  begin
    plan.MarkLines(r0, c0, r1, c1, ALines);
  end;

begin
  Result := False;
  if not UserTableDoorOpen then Exit;
  if not CellTarget(pos, r0, c0, r1, c1, True) then Exit;
  b := ABorder;
  if APreset = rbpNone then b := TyRichBorder(rbsNone, 0);
  if b.Style = rbsNone then
  begin
    b.WidthTwips := 0;
    b.Color := clDefault;
  end;
  skipped := 0;
  comp := TTyRichCompositeCommand.Create(rsRichUndoCellBorders);
  plan := nil;
  try
    plan := TTyRichBorderPlan.Create(FDoc, pos, r0, r1);
    case APreset of
      rbpAll, rbpNone: MarkLines([rclLeft, rclTop, rclRight, rclBottom, rclInsideH, rclInsideV]);
      rbpOutside: MarkLines([rclLeft, rclTop, rclRight, rclBottom]);
      rbpInside: MarkLines([rclInsideH, rclInsideV]);
      rbpTop: MarkLines([rclTop]);
      rbpBottom: MarkLines([rclBottom]);
      rbpLeft: MarkLines([rclLeft]);
      rbpRight: MarkLines([rclRight]);
      rbpInsideH: MarkLines([rclInsideH]);
      rbpInsideV: MarkLines([rclInsideV]);
    end;
    plan.AddParts(comp, b, skipped);
  except
    plan.Free;
    comp.Free;
    raise;
  end;
  plan.Free;
  // (inside lines of one cell: there are none - nothing to do)
  if comp.Count = 0 then
  begin
    comp.Free;
    if skipped > 0 then EditRefused(rsRichEditRefusedResizeNested);
    Exit(skipped = 0);
  end;
  Result := RunCellProps(comp, skipped);
end;

function TTyCustomRichEdit.SetCellPadding(ALeft, ATop, ARight, ABottom: Integer): Boolean;
var
  pos: TTyRichPos;
  r0, c0, r1, c1: Integer;
  p: TTyRichCellProps;
begin
  Result := False;
  if not UserTableDoorOpen then Exit;
  if not CellTarget(pos, r0, c0, r1, c1, True) then Exit;
  p := Default(TTyRichCellProps);
  if ALeft >= 0 then
  begin
    Include(p.Valid, rcpPadLeft);
    p.Pad[rcsLeft] := ALeft;
  end;
  if ATop >= 0 then
  begin
    Include(p.Valid, rcpPadTop);
    p.Pad[rcsTop] := ATop;
  end;
  if ARight >= 0 then
  begin
    Include(p.Valid, rcpPadRight);
    p.Pad[rcsRight] := ARight;
  end;
  if ABottom >= 0 then
  begin
    Include(p.Valid, rcpPadBottom);
    p.Pad[rcsBottom] := ABottom;
  end;
  if p.Valid = [] then Exit(True);
  Result := RunCellProps(TTyRichSetCellProps.Create(pos, r0, c0, r1, c1, p));
end;

function TTyCustomRichEdit.SetCellVAlign(AAlign: TTyRowCellVAlign): Boolean;
var
  pos: TTyRichPos;
  r0, c0, r1, c1: Integer;
  p: TTyRichCellProps;
begin
  Result := False;
  if not UserTableDoorOpen then Exit;
  if not CellTarget(pos, r0, c0, r1, c1, True) then Exit;
  p := Default(TTyRichCellProps);
  p.Valid := [rcpVAlign];
  p.VAlign := AAlign;
  Result := RunCellProps(TTyRichSetCellProps.Create(pos, r0, c0, r1, c1, p));
end;

{ Every row of the caret's table: aligned left, centred or right, AIndentTwips its start
  (Word's indent from the margin; only when it is another than the first row's: a table with
  merged cells keeps its start). }
function TTyCustomRichEdit.SetTableAlign(AAlign: TTyRowAlign): Boolean;
begin
  Result := TableAlignDoor(AAlign, 0, False);
end;

function TTyCustomRichEdit.SetTableAlign(AAlign: TTyRowAlign; AIndentTwips: Integer): Boolean;
begin
  Result := TableAlignDoor(AAlign, AIndentTwips, True);
end;

function TTyCustomRichEdit.TableAlignDoor(AAlign: TTyRowAlign; AIndentTwips: Integer;
  ASetIndent: Boolean): Boolean;
var
  p, c, r0, r1: Integer;
  pos: TTyRichPos;
  rp: TTyRichRowProps;
  lft: Integer;
begin
  Result := False;
  if not UserTableDoorOpen then Exit;
  if not CaretEdgePara(p, c, True) then Exit;
  // the whole table: never only the selected rows
  FDoc.BeginRead;
  try
    lft := FDoc.CellAt(p).Row.Format.Row.LeftTwips;
  finally
    FDoc.EndRead;
  end;
  if not EdgeRowsWhole(p, pos, r0, r1) then Exit;
  rp := Default(TTyRichRowProps);
  rp.Valid := [rrpAlign];
  rp.Align := AAlign;
  if ASetIndent and (AIndentTwips <> lft) then
  begin
    Include(rp.Valid, rrpLeft);
    rp.LeftTwips := AIndentTwips;
  end;
  Result := RunCellProps(TTyRichSetRowProps.Create(pos, r0, r1, rp));
end;

{ Every row of the table paragraph APara is in (refused and told for a table a reader gives in
  parts). }
function TTyCustomRichEdit.EdgeRowsWhole(APara: Integer; out ATablePos: TTyRichPos;
  out ARow0, ARow1: Integer): Boolean;
var
  c: TTyRichCell;
  cut: Boolean;
  ri, n: Integer;
begin
  Result := False;
  ATablePos := FDoc.Text.ParaStart(APara);
  ARow0 := 0;
  ARow1 := -1;
  FDoc.BeginRead;
  try
    c := FDoc.CellAt(APara);
    if c = nil then Exit;
    cut := c.Table.Cut;
  finally
    FDoc.EndRead;
  end;
  if cut then
  begin
    EditRefused(rsRichEditRefusedFormatNotWhole);
    Exit;
  end;
  if not FDoc.TableRowIndex(APara, ri, n) then Exit;
  ARow1 := n - 1;
  Result := True;
end;

{ The table properties as one step: the row height of the selected rows (else the caret's), the
  caret cell's column width (the columns right of it shifting), the table's alignment, the
  selected cells' padding, alignment and shading. }
function TTyCustomRichEdit.ApplyTableProperties(const AProps: TTyRichTableProperties): Boolean;
const
  CLineField: array[TTyRichCellLine] of TTyRichTablePropField = (tpfLineLeft, tpfLineTop,
    tpfLineRight, tpfLineBottom, tpfLineInsideH, tpfLineInsideV);
var
  ln: TTyRichCellLine;
  b: TTyRichBorder;
  plan: TTyRichBorderPlan;
  skipped: Integer;
  comp: TTyRichCompositeCommand;
  p, c, r0, c0, r1, c1, wr0, wr1, lft: Integer;
  pos, wpos: TTyRichPos;
  rp: TTyRichRowProps;
  cp: TTyRichCellProps;
  row: TTyRichRow;
  edges: TTyRichEdges;
  w: Integer;
begin
  Result := False;
  skipped := 0;
  // nothing changed: nothing to do, no undo step
  if AProps.Changed = [] then Exit(True);
  if not UserTableDoorOpen then Exit;
  if not CellTarget(pos, r0, c0, r1, c1, True) then Exit;
  if not CaretEdgePara(p, c, True) then Exit;
  comp := TTyRichCompositeCommand.Create(rsRichUndoTableProps);
  try
    if tpfRowHeight in AProps.Changed then
    begin
      rp := Default(TTyRichRowProps);
      rp.Valid := [rrpHeight];
      if AProps.RowExact and (AProps.RowHeight > 0) then rp.HeightTwips := -AProps.RowHeight
      else rp.HeightTwips := Math.Max(0, AProps.RowHeight);
      comp.Add(TTyRichSetRowHeight.Create(pos, r0, r1, rp));
    end;
    if (tpfColumnWidth in AProps.Changed) and (AProps.ColumnWidth > 0) then
    begin
      if not EdgeRows(p, True, wpos, wr0, wr1) then
      begin
        comp.Free;
        Exit;
      end;
      FDoc.BeginRead;
      try
        row := FDoc.CellAt(p).Row;
        edges := row.CellEdges;
        if c = 0 then lft := row.Format.Row.LeftTwips else lft := edges[c - 1];
        w := Math.Max(AProps.ColumnWidth, MinCellTwips(row, c));
      finally
        FDoc.EndRead;
      end;
      if lft + w <> edges[c] then
        comp.Add(TTyRichSetColumnEdge.Create(wpos, edges[c], lft + w, wr0, wr1, True));
    end;
    if (tpfAlign in AProps.Changed) or (tpfIndent in AProps.Changed) then
    begin
      if not EdgeRowsWhole(p, wpos, wr0, wr1) then
      begin
        comp.Free;
        Exit;
      end;
      rp := Default(TTyRichRowProps);
      if tpfAlign in AProps.Changed then
      begin
        Include(rp.Valid, rrpAlign);
        rp.Align := AProps.Align;
      end;
      FDoc.BeginRead;
      try
        lft := FDoc.CellAt(p).Row.Format.Row.LeftTwips;
      finally
        FDoc.EndRead;
      end;
      if (tpfIndent in AProps.Changed) and (AProps.Indent <> lft) then
      begin
        Include(rp.Valid, rrpLeft);
        rp.LeftTwips := AProps.Indent;
      end;
      if rp.Valid <> [] then comp.Add(TTyRichSetRowProps.Create(wpos, wr0, wr1, rp));
    end;
    cp := Default(TTyRichCellProps);
    if tpfPadding in AProps.Changed then
    begin
      if AProps.Pad[rcsLeft] >= 0 then Include(cp.Valid, rcpPadLeft);
      if AProps.Pad[rcsTop] >= 0 then Include(cp.Valid, rcpPadTop);
      if AProps.Pad[rcsRight] >= 0 then Include(cp.Valid, rcpPadRight);
      if AProps.Pad[rcsBottom] >= 0 then Include(cp.Valid, rcpPadBottom);
      cp.Pad := AProps.Pad;
    end;
    if tpfVAlign in AProps.Changed then
    begin
      Include(cp.Valid, rcpVAlign);
      cp.VAlign := AProps.VAlign;
    end;
    if tpfShading in AProps.Changed then
    begin
      Include(cp.Valid, rcpShading);
      cp.Shading := AProps.Shading;
    end;
    if cp.Valid <> [] then comp.Add(TTyRichSetCellProps.Create(pos, r0, c0, r1, c1, cp));
    // the lines: each through the border plan (the facing sides of the cells beside too)
    for ln := Low(TTyRichCellLine) to High(TTyRichCellLine) do
      if CLineField[ln] in AProps.Changed then
      begin
        b := AProps.Lines[ln];
        if b.Style = rbsNone then
        begin
          b.WidthTwips := 0;
          b.Color := clDefault;
        end;
        plan := TTyRichBorderPlan.Create(FDoc, pos, r0, r1);
        try
          plan.MarkLines(r0, c0, r1, c1, [ln]);
          plan.AddParts(comp, b, skipped);
        finally
          plan.Free;
        end;
      end;
  except
    comp.Free;
    raise;
  end;
  if comp.Count = 0 then
  begin
    comp.Free;
    Exit(True);
  end;
  Result := RunCellProps(comp);
end;

{ The values of the selected cells (else the caret's), their rows and their table, and which
  of them are alike over all. }
function TTyCustomRichEdit.GetTableProperties(out AProps: TTyRichTableProperties): Boolean;
var
  pos: TTyRichPos;
  r0, c0, r1, c1, r, c: Integer;
  cp, cp0: TTyRichCellProps;
  rp, rp0: TTyRichRowProps;
  first: Boolean;
  sd: TTyRowCellSide;
  u: TTyRichTablePropFields;
  seen: array[TTyRichCellLine] of Boolean;
  ln: TTyRichCellLine;
  last: Integer;

  // a cell side that makes line ALine: the first its value, another unlike it makes it mixed
  procedure Take(ALine: TTyRichCellLine; const B: TTyRichBorder);
  const
    Field: array[TTyRichCellLine] of TTyRichTablePropField = (tpfLineLeft, tpfLineTop,
      tpfLineRight, tpfLineBottom, tpfLineInsideH, tpfLineInsideV);
  begin
    if not seen[ALine] then
    begin
      seen[ALine] := True;
      AProps.Lines[ALine] := B;
    end
    else if not TyRichSameBorder(AProps.Lines[ALine], B) then
      Exclude(u, Field[ALine]);
  end;

begin
  AProps := Default(TTyRichTableProperties);
  for ln := Low(TTyRichCellLine) to High(TTyRichCellLine) do seen[ln] := False;
  Result := False;
  if not CellTarget(pos, r0, c0, r1, c1, False) then Exit;
  u := [Low(TTyRichTablePropField)..High(TTyRichTablePropField)];
  first := True;
  cp0 := Default(TTyRichCellProps);
  rp0 := Default(TTyRichRowProps);
  for r := r0 to r1 do
  begin
    rp := FDoc.RowProps(pos, r);
    if rp.Valid = [] then Continue;
    // the row's last cell in the selection: where the outline's right side is
    last := c0;
    while (last + 1 <= c1) and (FDoc.CellProps(pos, r, last + 1).Valid <> []) do Inc(last);
    c := c0;
    while c <= c1 do
    begin
      cp := FDoc.CellProps(pos, r, c);
      // (past the row's last cell)
      if cp.Valid = [] then Break;
      if c = c0 then Take(rclLeft, cp.Borders[rcsLeft]);
      if c = last then Take(rclRight, cp.Borders[rcsRight]) else Take(rclInsideV, cp.Borders[rcsRight]);
      if r = r0 then Take(rclTop, cp.Borders[rcsTop]);
      if r = r1 then Take(rclBottom, cp.Borders[rcsBottom]) else Take(rclInsideH, cp.Borders[rcsBottom]);
      if first then
      begin
        cp0 := cp;
        rp0 := rp;
        first := False;
      end
      else
      begin
        if (rp.HeightTwips <> rp0.HeightTwips) then Exclude(u, tpfRowHeight);
        if cp.WidthTwips <> cp0.WidthTwips then Exclude(u, tpfColumnWidth);
        if rp.Align <> rp0.Align then Exclude(u, tpfAlign);
        if rp.LeftTwips <> rp0.LeftTwips then Exclude(u, tpfIndent);
        for sd := Low(TTyRowCellSide) to High(TTyRowCellSide) do
          if cp.Pad[sd] <> cp0.Pad[sd] then Exclude(u, tpfPadding);
        if cp.VAlign <> cp0.VAlign then Exclude(u, tpfVAlign);
        if cp.Shading <> cp0.Shading then Exclude(u, tpfShading);
      end;
      Inc(c);
    end;
  end;
  if first then Exit;
  // (a line the selection does not have is not alike: there is none)
  if not seen[rclInsideH] then Exclude(u, tpfLineInsideH);
  if not seen[rclInsideV] then Exclude(u, tpfLineInsideV);
  AProps.Uniform := u;
  AProps.Changed := [];
  AProps.RowHeight := Abs(rp0.HeightTwips);
  AProps.RowExact := rp0.HeightTwips < 0;
  AProps.ColumnWidth := cp0.WidthTwips;
  AProps.Align := rp0.Align;
  AProps.Indent := rp0.LeftTwips;
  for sd := Low(TTyRowCellSide) to High(TTyRowCellSide) do AProps.Pad[sd] := cp0.Pad[sd];
  AProps.VAlign := cp0.VAlign;
  AProps.Shading := cp0.Shading;
  Result := True;
end;

{ ---- keyboard and wheel ---- }

procedure TTyCustomRichEdit.KeyDown(var Key: Word; Shift: TShiftState);
var
  ext, byWord, toDoc: Boolean;
  q: TTyRichPos;
begin
  // the form designer's keys are the designer's: nothing is edited or moved there
  if csDesigning in ComponentState then Exit;
  // (a key lets the menu come again: see FEatMenu)
  FEatMenu := False;
  // Ctrl down with the pointer still: the hand over a link comes
  if (Key = VK_CONTROL) or (Key = VK_LCONTROL) or (Key = VK_RCONTROL) then
    PointerKeysChanged(Shift + [ssCtrl]);
  inherited KeyDown(Key, Shift);
  // a user action is an entry point of the loop (see SchedulingFailed)
  EndOwedLoad;
  if (Key = 0) or not IsEnabled then Exit;
  { A drag of the control's own (a handle's, the selection's, or a press inside the selection
    waiting for one) has the keys (OwnDragKey): Esc ends it, the modifiers keep their meaning,
    every other key is taken and does nothing - the drag goes on. }
  if OwnDragKey(Key) then Exit;
  { Inside the document's update a key that moves or copies does nothing: the view does not
    know the text yet. The viewer's keys are still taken - they never go on to the form. }
  if ViewBehind then
  begin
    if (Key in [VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN, VK_HOME, VK_END, VK_PRIOR, VK_NEXT]) or
      (TyIsShortcutShift(Shift) and (Key in [VK_A, VK_C, VK_V])) or
      ((Key = VK_INSERT) and ((Shift = [ssCtrl]) or (Shift = [ssShift]))) or
      IsEditKey(Key, Shift) then
      Key := 0;
    Exit;
  end;
  // (no selection of the user's: Shift moves as the plain key does)
  ext := (ssShift in Shift) and FAllowSelection;
  // Ctrl a word (Option on a Mac, as its text views); Ctrl or Cmd the document's ends
  byWord := (ssCtrl in Shift) {$IFDEF DARWIN}or (ssAlt in Shift){$ENDIF};
  toDoc := (ssCtrl in Shift) or (ssMeta in Shift);
  { A key an input method lets through while composing that edits or selects all: the
    composition goes in first (EndCompositionForUser, the one door) - never the action under
    it, nor the commit over what Ctrl+A selected. }
  if TyIsShortcutShift(Shift) and (Key = VK_A) then
  begin
    EndCompositionForUser;
    if FAllowSelection then SelectAll;
    Key := 0;
    Exit;
  end;
  // as the memo: Ctrl+C (Cmd+C), and Ctrl+Insert
  if (TyIsShortcutShift(Shift) and (Key = VK_C)) or ((Key = VK_INSERT) and (Shift = [ssCtrl])) then
  begin
    CopyToClipboard;
    Key := 0;
    Exit;
  end;
  { Ctrl+V (Cmd+V), and Shift+Insert as the memo: a paste, which ends a composition first
    and does nothing with ReadOnly (both inside it); taken either way. }
  if (TyIsShortcutShift(Shift) and (Key = VK_V)) or ((Key = VK_INSERT) and (Shift = [ssShift])) then
  begin
    PasteFromClipboard;
    Key := 0;
    Exit;
  end;
  { Tab and Shift+Tab in a table go from cell to cell (Word's way) - with ReadOnly too: they
    move; only a new row is an edit. Ctrl+Tab, and Tab outside a table, are the edit key's. }
  if (Key = VK_TAB) and FWantTabs and (Shift * [ssCtrl, ssAlt, ssMeta] = []) then
  begin
    EndCompositionForUser;
    if not ViewBehind then
    begin
      Settle;
      if TableTab(not (ssShift in Shift)) then
      begin
        Key := 0;
        Exit;
      end;
      // at a list item's start (or over whole items): a level deeper, Shift+Tab shallower
      if ListTab(not (ssShift in Shift)) then
      begin
        Key := 0;
        Exit;
      end;
    end;
  end;
  if IsEditKey(Key, Shift) then
  begin
    EndCompositionForUser;
    // with ReadOnly taken, and nothing changes (the memo's way)
    if not FReadOnly and not ViewBehind then
    begin
      Settle;
      case Key of
        VK_BACK: DeleteKey(False, byWord);
        VK_DELETE:
          // as the memo: Shift+Delete cuts
          if Shift = [ssShift] then CutSelection(True) else DeleteKey(True, byWord);
        VK_RETURN:
          { Shift+Enter: a line break in the paragraph - in a plain text document a paragraph,
            as Enter (a text file has no line break inside a line: a stored U+000B would be
            saved as the byte 0B) }
          if (ssShift in Shift) and not PlainTextDocument then TypeText(#11, False, True)
          else ParagraphKey;
        VK_TAB: TypeText(#9, True, True);
        VK_X: CutSelection(True);
        // Ctrl+Shift+Z redoes, as Ctrl+Y
        VK_Z: RunHistory(ssShift in Shift, True);
        VK_Y: RunHistory(True, True);
      end;
    end;
    Key := 0;
    Exit;
  end;
  case Key of
    VK_LEFT, VK_RIGHT:
      begin
        Settle;
        if HasSelection and not ext and not byWord then
        begin
          // a selection collapses to the side the arrow points at (shown at a cut, if past it)
          if Key = VK_RIGHT then q := GetSelStart + GetSelLength else q := GetSelStart;
          q := OutOfTail(q, False);
          // onto the caret itself: it stays where it is drawn, at a line's end too
          if q = FCaret then Select(q, q, FCaretAtEnd) else Select(q, q, False);
        end
        else
        begin
          if byWord then q := WordStep(FCaret, Key = VK_RIGHT)
          else q := CaretStep(FCaret, Key = VK_RIGHT);
          // (a covered cell takes no caret: passed over)
          q := PastCovered(q, Key = VK_RIGHT);
          if ext then Select(FSelAnchor, q, False) else Select(q, q, False);
        end;
        Moved(False);
      end;
    VK_UP, VK_DOWN:
      begin
        MoveVertical(Key = VK_DOWN, ext);
        Moved(True);
      end;
    VK_HOME, VK_END:
      begin
        Settle;
        if toDoc then
        begin
          if Key = VK_HOME then q := 0 else q := OutOfTail(FDoc.Text.Length, False);
          if ext then Select(FSelAnchor, q, False) else Select(q, q, False);
        end
        else
          MoveInLine(Key = VK_END, ext);
        Moved(False);
      end;
    VK_PRIOR, VK_NEXT:
      begin
        MovePage(Key = VK_NEXT, ext);
        Moved(True);
      end;
  else
    // not the control's: Esc, Tab without WantTabs, a viewer's Enter go on to the form
    Exit;
  end;
  Key := 0;
end;

function TTyCustomRichEdit.WheelScrolls(AVertical: Boolean): Boolean;
begin
  { A direction the control can scroll: its bar may show there (ScrollBars, and AutoHeight
    leaves the vertical one out) and the content does not fit, or the view is off its start.
    Not "at its end": a control that can scroll keeps the wheel there too. }
  if not BarAllowed(AVertical) then Exit(False);
  if AVertical then
    Result := (FDoc.Text.TotalHeight > FViewH) or (AnchorY > 0)
  else
    Result := (FWidestSeen > FViewW) or (FScrollX > 0);
end;

function TTyCustomRichEdit.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  notches, perNotch: Integer;
begin
  if not IsEnabled then Exit(False);
  if inherited DoMouseWheel(Shift, WheelDelta, MousePos) then Exit(True);
  Result := True;
  // inside the document's update: taken, nothing done
  if ViewBehind then Exit;
  if ssCtrl in Shift then
  begin
    // Ctrl + wheel zooms, a notch at a time (always on: the zoom is the control's own)
    Inc(FZoomWheelRest, WheelDelta);
    notches := FZoomWheelRest div 120;
    Dec(FZoomWheelRest, notches * 120);
    if notches <> 0 then Zoom := FZoom + notches * CRichZoomStep;
    Exit;
  end;
  { Nothing to scroll this way (the content fits, ScrollBars leaves the direction out,
    AutoHeight): not taken, so the parent scrolls - a home page in a scroll box. }
  CheckLayoutParams(ViewPPI);
  if not WheelScrolls(True) then Exit(False);
  Inc(FWheelRest, WheelDelta);
  notches := FWheelRest div 120;
  Dec(FWheelRest, notches * 120);
  if notches = 0 then Exit;
  perNotch := Mouse.WheelScrollLines;
  if perNotch <= 0 then
    ScrollRasterBy(-notches * Int64(Math.Max(FEstimate, FViewH - FEstimate)))
  else
    ScrollRasterBy(-notches * Int64(perNotch) * Math.Max(1, FEstimate));
  // a drop goes on: what came under the pointer
  DropFollowPointer;
end;

function TTyCustomRichEdit.DoMouseWheelHorz(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  notches, was: Integer;
begin
  if not IsEnabled then Exit(False);
  if inherited DoMouseWheelHorz(Shift, WheelDelta, MousePos) then Exit(True);
  Result := True;
  if ViewBehind then Exit;
  // nothing to scroll sideways: the parent's
  CheckLayoutParams(ViewPPI);
  if not WheelScrolls(False) then Exit(False);
  Inc(FWheelHRest, WheelDelta);
  notches := FWheelHRest div 120;
  Dec(FWheelHRest, notches * 120);
  if notches = 0 then Exit;
  was := FScrollX;
  FScrollX := FScrollX + notches * 3 * Math.Max(1, FEstimate);
  ClampScrollX;
  if FScrollX = was then Exit;
  // a range a load's turns held back first: the position is in the range the bar has
  CatchUpBars;
  if HBarShown then
  begin
    FSyncingBars := True;
    try
      FHBar.Position := FScrollX div FScale;
    finally
      FSyncingBars := False;
    end;
  end;
  MoveSurfaceText(was - FScrollX, 0);
  InvalidateArea(TextWindowRect);
  DropFollowPointer;
end;

procedure TTyCustomRichEdit.MouseEnter;
begin
  inherited MouseEnter;
  if FVBar <> nil then FVBar.SetHostHovered(True);
  if FHBar <> nil then FHBar.SetHostHovered(True);
end;

procedure TTyCustomRichEdit.MouseLeave;
begin
  { Where the pointer comes back in is not known: the arrow is not answered over the text
    until a move over the padding says so again. }
  FOverPadding := False;
  FPointerKnown := False;
  inherited MouseLeave;
  if FVBar <> nil then FVBar.SetHostHovered(False);
  if FHBar <> nil then FHBar.SetHostHovered(False);
end;

{ ---- the paragraph view ---- }

{ Who hears it (a ruler) asks ParagraphView again; inside the document's update the view
  has not heard of the change yet, and the update's end tells. }
procedure TTyCustomRichEdit.ParagraphViewChanged;
begin
  if (FParaViewHandlers = nil) or (csDestroying in ComponentState) or ViewBehind then Exit;
  FParaViewHandlers.CallNotifyEvents(Self);
end;

function TTyCustomRichEdit.ParagraphView(out AView: TTyRichParaView): Boolean;
var
  t: TTyRichText;
  area, clip: TRect;
  k, i, last: Integer;
  row: TTyRowLayout;
  item: TTyRichRowItem;
  caret: TTyRichPos;
begin
  AView := Default(TTyRichParaView);
  Result := False;
  // (never laid out, or the view has not heard of the document's update yet)
  if (FLayoutPPI <= 0) or ViewBehind then Exit;
  t := FDoc.Text;
  // the paragraph a paragraph format change begins at (ApplyParagraphFormat's ParasOfRange)
  ParasOfRange(GetSelStart, GetSelLength, k, last);
  AView.Para := k;
  caret := t.ParaStart(k);
  AView.Format := FDoc.Formats.ParaFormat(FDoc.ParaFormatOf(AView.Para));
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  clip := TextWindowRect;
  AView.Origin := area.Left;
  AView.Scale := Math.Max(1, FScale);
  AView.PPI := FLayoutPPI;
  AView.Zoom := FLayoutZoom;
  AView.ViewRaster := FViewW;
  AView.ZeroRaster := -FScrollX;
  AView.TextWidthRaster := FLayoutWidth;
  AView.ClipLeft := clip.Left;
  AView.ClipTop := clip.Top;
  AView.ClipRight := clip.Right;
  AView.ClipBottom := clip.Bottom;
  AView.InCell := FDoc.CellAt(AView.Para) <> nil;
  if AView.InCell then
  begin
    { The cell's paragraph is laid out in its row at the cell's text width, its left edge at
      the item's place in the row (the row's own indent and the cell's half gap in it). A row
      that is not held (scrolled away) cannot tell: nothing to show. }
    k := HeldBlockOf(caret);
    if (k < 0) or not (FBlocks[k].Layout is TTyRowLayout) then Exit;
    row := TTyRowLayout(FBlocks[k].Layout);
    if row.ItemCount = 0 then Exit;
    i := row.ItemAt(caret - t.ParaStart(FBlocks[k].FirstPara));
    item := row.Items[i];
    if item.Layout = nil then Exit;
    AView.ZeroRaster := Int64(item.X) - FScrollX;
    AView.TextWidthRaster := item.Layout.LayoutWidth;
  end;
  // what ApplyParagraphFormat asks before it makes its command, the place too
  AView.Editable := CanFormatParagraphs;
  Result := True;
end;

procedure TTyCustomRichEdit.AddHandlerOnParagraphView(const AHandler: TNotifyEvent);
begin
  if FParaViewHandlers = nil then FParaViewHandlers := TMethodList.Create;
  FParaViewHandlers.Add(TMethod(AHandler));
  WatchParents;
end;

type
  { Hears the Enabled of every parent of a rich edit (LCL tells a child nothing when its parent
    is disabled, though IsEnabled follows it) and tells the rich edit's paragraph view hearers.
    Owned by the rich edit; FreeNotification on each parent, so a parent that goes is let go. }
  TTyRichParentWatch = class(TComponent)
  private
    FEdit: TTyCustomRichEdit;
    FParents: TFPList;
    procedure Heard(Sender: TObject);
    procedure Unhook;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor CreateFor(AEdit: TTyCustomRichEdit);
    destructor Destroy; override;
    procedure Hook;
  end;

constructor TTyRichParentWatch.CreateFor(AEdit: TTyCustomRichEdit);
begin
  inherited Create(AEdit);
  FEdit := AEdit;
  FParents := TFPList.Create;
end;

destructor TTyRichParentWatch.Destroy;
begin
  Unhook;
  FreeAndNil(FParents);
  inherited Destroy;
end;

procedure TTyRichParentWatch.Unhook;
var
  i: Integer;
  w: TWinControl;
begin
  if FParents = nil then Exit;
  for i := 0 to FParents.Count - 1 do
  begin
    w := TWinControl(FParents[i]);
    w.RemoveHandlerOnEnabledChanged(@Heard);
    w.RemoveFreeNotification(Self);
  end;
  FParents.Clear;
end;

procedure TTyRichParentWatch.Hook;
var
  w: TWinControl;
begin
  Unhook;
  w := FEdit.Parent;
  while w <> nil do
  begin
    FParents.Add(w);
    w.AddHandlerOnEnabledChanged(@Heard);
    w.FreeNotification(Self);
    w := w.Parent;
  end;
end;

procedure TTyRichParentWatch.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FParents <> nil) and (FParents.IndexOf(AComponent) >= 0) then
  begin
    // a parent going: none of them is touched any more (the chain is hooked again on a move)
    TWinControl(AComponent).RemoveHandlerOnEnabledChanged(@Heard);
    FParents.Remove(AComponent);
  end;
end;

procedure TTyRichParentWatch.Heard(Sender: TObject);
begin
  FEdit.ParagraphViewChanged;
end;

procedure TTyCustomRichEdit.WatchParents;
begin
  if (FParaViewHandlers = nil) or (csDestroying in ComponentState) then Exit;
  if FParentWatch = nil then FParentWatch := TTyRichParentWatch.CreateFor(Self);
  TTyRichParentWatch(FParentWatch).Hook;
end;

procedure TTyCustomRichEdit.SetParent(NewParent: TWinControl);
begin
  inherited SetParent(NewParent);
  // the parents whose Enabled IsEnabled follows are others now
  if FParentWatch <> nil then WatchParents;
end;

procedure TTyCustomRichEdit.RemoveHandlerOnParagraphView(const AHandler: TNotifyEvent);
begin
  if FParaViewHandlers <> nil then FParaViewHandlers.Remove(TMethod(AHandler));
end;

function TTyCustomRichEdit.GetGuideLine: Integer;
begin
  if FGuideOn then Result := FGuideX else Result := -1;
end;

procedure TTyCustomRichEdit.SetGuideLine(AValue: Integer);
var
  r: TRect;
begin
  if AValue < 0 then
  begin
    if not FGuideOn then Exit;
  end
  else if FGuideOn and (AValue = FGuideX) then Exit;
  // the old place blitted again (the line is not on the surface), then the new one
  r := GuideLineRect;
  if not IsRectEmpty(r) then InvalidateArea(r);
  FGuideOn := AValue >= 0;
  if FGuideOn then FGuideX := AValue;
  r := GuideLineRect;
  if not IsRectEmpty(r) then InvalidateArea(r);
end;

function TTyCustomRichEdit.GuideLineRect: TRect;
var
  tw: TRect;
begin
  Result := Rect(0, 0, 0, 0);
  if not FGuideOn then Exit;
  tw := TextWindowRect;
  Result := Rect(FGuideX, tw.Top, FGuideX + Math.Max(1, MulDiv(1, ViewPPI, 96)), tw.Bottom);
  if not IntersectRect(Result, Result, tw) then Result := Rect(0, 0, 0, 0);
end;

procedure TTyCustomRichEdit.DrawGuideLine(ACanvas: TCanvas);
var
  r: TRect;
begin
  // over the blit, as the caret: the theme's text colour
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := TyColorToLCL(CurrentStyle.TextColor);
  r := GuideLineRect;
  if not IsRectEmpty(r) then ACanvas.FillRect(r);
  r := GuideRowRect;
  if not IsRectEmpty(r) then ACanvas.FillRect(r);
end;

function TTyCustomRichEdit.ApplyParagraphFormat(AMask: TTyParaFormatMask;
  const AValue: TTyParaFormat): Boolean;
var
  life: TTyRichLife;
  r: Boolean;
  first, last: Integer;
  place: TTyRichEditPlace;
  reason: string;

  procedure Work;
  begin
    // as the façades' writes: the selection kept (with a pending format), no scroll
    Inc(FApiWrite);
    try
      r := RunMade(TTyRichSetParaFormat.Create(first, last, AMask, AValue), place, True);
    finally
      if not life.Gone then Dec(FApiWrite);
    end;
  end;

begin
  Result := False;
  if (AMask = []) or (csDesigning in ComponentState) then Exit;
  // a user's action: a viewer, a disabled control and an update take nothing and tell nothing
  if FReadOnly or not IsEnabled or ViewBehind then Exit;
  // the paragraphs of the selection as it is once what is being composed went in
  EndCompositionForUser;
  if FReadOnly or not IsEnabled or ViewBehind then Exit;
  // where every paragraph would be passed over (CanFormatParagraphs' no): told, no empty step
  if RefusalReason = '' then
  begin
    reason := FormatPlaceRefusal(True);
    if reason <> '' then
    begin
      EditRefused(reason);
      Exit;
    end;
  end;
  ParasOfRange(GetSelStart, GetSelLength, first, last);
  place := Default(TTyRichEditPlace);
  place.Anchor := CRichPlaceStays;
  place.Caret := CRichPlaceStays;
  place.AtLineEnd := FCaretAtEnd;
  r := False;
  Guard(life, @Work);
  Result := r and not life.Gone;
end;

function TTyCustomRichEdit.ChangeListLevel(ADelta: Integer): Boolean;
var
  life: TTyRichLife;
  first, last, k, i: Integer;
  place: TTyRichEditPlace;
  reason: string;
  area: TTyRichCellArea;
  fs, ls: TIntegerDynArray;
  comp: TTyRichCompositeCommand;

  procedure Work;
  var
    j: Integer;
  begin
    Inc(FApiWrite);
    try
      if Length(fs) = 0 then
        RunMade(TTyRichChangeListLevel.Create(first, last, ADelta), place, True)
      else
      begin
        // the selected cells' paragraphs, each cell's a part: one step
        comp := TTyRichCompositeCommand.Create;
        for j := 0 to High(fs) do comp.Add(TTyRichChangeListLevel.Create(fs[j], ls[j], ADelta));
        RunMade(comp, place, True);
      end;
    finally
      if not life.Gone then Dec(FApiWrite);
    end;
  end;

begin
  Result := False;
  if (ADelta = 0) or (csDesigning in ComponentState) then Exit;
  if FReadOnly or not IsEnabled or ViewBehind then Exit;
  EndCompositionForUser;
  if FReadOnly or not IsEnabled or ViewBehind then Exit;
  { every paragraph of the selection a list item (what the selection reads, as a format does:
    selected cells are their own paragraphs, the rectangle's, as the paragraph formats take
    them) }
  fs := nil;
  ls := nil;
  area := CellArea;
  if TyRichCellsEditable(area) then
  begin
    AreaParaSpans(area, fs, ls);
    if Length(fs) = 0 then Exit;
    FDoc.BeginRead;
    try
      for i := 0 to High(fs) do
        for k := fs[i] to ls[i] do
          if FDoc.Formats.ParaFormat(FDoc.ParaFormatOf(k)).List.Kind = lkNone then Exit;
    finally
      FDoc.EndRead;
    end;
  end
  else
  begin
    ParasOfRange(GetSelStart, GetSelLength, first, last);
    FDoc.BeginRead;
    try
      for k := first to last do
        if FDoc.Formats.ParaFormat(FDoc.ParaFormatOf(k)).List.Kind = lkNone then Exit;
    finally
      FDoc.EndRead;
    end;
  end;
  Result := True;
  if RefusalReason = '' then
  begin
    reason := FormatPlaceRefusal(True);
    if reason <> '' then
    begin
      EditRefused(reason);
      Exit;
    end;
  end;
  place := Default(TTyRichEditPlace);
  place.Anchor := CRichPlaceStays;
  place.Caret := CRichPlaceStays;
  place.AtLineEnd := FCaretAtEnd;
  Guard(life, @Work);
end;

function TTyCustomRichEdit.ListTab(ADeeper: Boolean): Boolean;
var
  s, e: TTyRichPos;
  first, last: Integer;
  t: TTyRichText;
begin
  // (read-only: ChangeListLevel does nothing, and the key does nothing either)
  Result := False;
  t := FDoc.Text;
  s := GetSelStart;
  e := s + GetSelLength;
  first := t.ParaOfPos(s);
  // at the very start of an item's text, or a selection from an item's start over whole items
  if s <> t.ParaStart(first) then Exit;
  if e > s then
  begin
    last := t.ParaOfPos(e);
    // (a selection that ends at the next paragraph's start ends with the one before it)
    if (last > first) and (e = t.ParaStart(last)) then Dec(last)
    else if e < t.ParaStart(last) + t.ParaLength(last) then Exit;
  end
  else
    last := first;
  // in a table, Tab goes from cell to cell (TableTab): not here
  if (FDoc.CellAt(first) <> nil) or (FDoc.CellAt(last) <> nil) then Exit;
  if ADeeper then Result := ChangeListLevel(1) else Result := ChangeListLevel(-1);
end;

function TTyCustomRichEdit.FormatPlaceRefusal(AParagraphs: Boolean): string;
var
  t: TTyRichText;
  s, n, ps, a, b: TTyRichPos;
  first, last, k: Integer;
  field, fixed: Boolean;

  // a row that holds a nested table: the format writes pass its paragraphs over
  function FixedRow(AIndex: Integer): Boolean;
  var
    c: TTyRichCell;
  begin
    c := FDoc.CellAt(AIndex);
    Result := (c <> nil) and c.Row.HoldsNestedTable;
  end;

begin
  Result := '';
  t := FDoc.Text;
  s := GetSelStart;
  n := GetSelLength;
  field := False;
  fixed := False;
  if AParagraphs then
  begin
    // ApplyParaFormat's rule: a paragraph that ends in a result, or in such a row, is passed over
    ParasOfRange(s, n, first, last);
    for k := first to last do
    begin
      if k - first >= CRichFormatQueryParas then Exit;
      if FixedRow(k) then fixed := True
      else if FDoc.ParaEndsInField(k) then field := True
      else Exit;
    end;
  end
  else if n <= 0 then
    // the format the next typed text gets: refused where that typing would be
    case FDoc.ChangeRefusal(s, 0) of
      rcrField: field := True;
      rcrFixedRow: fixed := True;
    else
      Exit;
    end
  else
  begin
    // ApplyCharFormat's: the characters of a result, and such a row's, are passed over
    first := t.ParaOfPos(s);
    last := t.ParaOfPos(s + n - 1);
    for k := first to last do
    begin
      if k - first >= CRichFormatQueryParas then Exit;
      if FixedRow(k) then
      begin
        fixed := True;
        Continue;
      end;
      ps := t.ParaStart(k);
      a := Math.Max(s, ps);
      // (the paragraph's separator with it, when the range takes it)
      b := Math.Min(Math.Min(s + n, ps + t.ParaLength(k) + 1), t.Length);
      if (b > a) and not FDoc.FieldOnly(a, b - a) then Exit;
      field := True;
    end;
  end;
  if field then Result := rsRichEditRefusedField
  else if fixed then Result := rsRichEditRefusedFixedRow;
end;

function TTyCustomRichEdit.CanFormatCharacters: Boolean;
begin
  Result := not FReadOnly and IsEnabled and not ViewBehind and
    not (csDesigning in ComponentState) and (RefusalReason = '') and
    (FormatPlaceRefusal(False) = '');
end;

function TTyCustomRichEdit.CanFormatParagraphs: Boolean;
begin
  Result := not FReadOnly and IsEnabled and not ViewBehind and
    not (csDesigning in ComponentState) and (RefusalReason = '') and
    (FormatPlaceRefusal(True) = '');
end;

function TTyCustomRichEdit.ApplyCharacterFormat(AMask: TTyCharFormatMask;
  const AValue: TTyCharFormat): Boolean;
var
  life: TTyRichLife;
  r: Boolean;
  s, n: TTyRichPos;
  reason: string;
  base: TTyCharFormat;
  keep: TTyCharFormatMask;
  place: TTyRichEditPlace;

  procedure Work;
  begin
    // as the façades' writes: the selection kept, no scroll
    Inc(FApiWrite);
    try
      r := RunMade(TTyRichSetCharFormat.Create(TyRichRange(s, n), AMask, AValue, keep), place, True);
    finally
      if not life.Gone then Dec(FApiWrite);
    end;
  end;

begin
  Result := False;
  if (AMask = []) or (csDesigning in ComponentState) then Exit;
  // a user's action: a viewer, a disabled control and an update take nothing and tell nothing
  if FReadOnly or not IsEnabled or ViewBehind then Exit;
  EndCompositionForUser;
  if FReadOnly or not IsEnabled or ViewBehind then Exit;
  reason := RefusalReason;
  if reason = '' then reason := FormatPlaceRefusal(False);
  if reason <> '' then
  begin
    EditRefused(reason);
    Exit;
  end;
  s := GetSelStart;
  n := GetSelLength;
  if n <= 0 then
  begin
    // the format the next typed text gets (no command), as the format API sets it
    ApiCharFormat(FCaret, 0, AMask, AValue);
    Exit(True);
  end;
  // a name or a size that is the base's: the text keeps none of its own (ApiCharFormat's rule)
  keep := [];
  if AMask * [cffFontName, cffSize] <> [] then
  begin
    base := BaseCharFormat;
    if (cffFontName in AMask) and (AValue.FontName <> '') and (AValue.FontName = base.FontName) then
      Include(keep, cffFontName);
    if (cffSize in AMask) and (AValue.SizeHalfPt > 0) and (AValue.SizeHalfPt = base.SizeHalfPt) then
      Include(keep, cffSize);
  end;
  place := Default(TTyRichEditPlace);
  place.Anchor := CRichPlaceStays;
  place.Caret := CRichPlaceStays;
  place.AtLineEnd := FCaretAtEnd;
  r := False;
  Guard(life, @Work);
  Result := r and not life.Gone;
end;

initialization
  {$IFDEF MSWINDOWS}
  TyRichReplaceFileW := @ReplaceFileW;
  {$ENDIF}
  TyTryRegisterTypeKeyParent('TyRichEdit', 'TyMemo');

finalization
  TyUnregisterTypeKeyParent('TyRichEdit');

end.
