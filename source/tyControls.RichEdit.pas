unit tyControls.RichEdit;

{ TTyRichEdit: a rich text editor, drawn by the package itself on every platform. It shows a
  document - txt or RTF, of any size - scrolls, zooms and wraps it, and edits it by keyboard:
  typing, Backspace, Delete, Enter, Tab, undo and redo, cut (Task 10a), an input method's
  composition shown in the text and committed as typing (10b), paste (10c). Every
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

  Bidirectional text is not laid out (spec 6.1); a right-to-left control puts its vertical
  scroll bar on the left and keeps the text left to right. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Controls, Graphics, Forms, ExtCtrls, LCLType, LCLIntf,
  LMessages, LCLPlatformDef, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.StyleModel, tyControls.Painter, tyControls.Base,
  tyControls.ScrollBar, tyControls.TextMenu, tyControls.Controller,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.TextIO, tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite,
  tyControls.RichEdit.Layout;

const
  CRichZoomMin = 10;
  CRichZoomMax = 500;
  { Ctrl + one wheel notch. }
  CRichZoomStep = 10;
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
    turns are fast, halve them while they are slow (TTyCustomRichEdit.SliceBytes; L-6, N-3,
    N-4). }
  CRichLoadMinStepBytes = 16 * 1024;
  { rtdIdle's backstop (N-2): while there is work, a timer of this period runs one turn when no
    turn ran since its last tick - for an application whose idle step never comes or never
    reaches the idle handlers (an Application.OnIdle that sets Done := False, a flood of
    messages). In the normal case a tick costs one comparison. }
  CRichBackstopMs = 50;
  { While a load runs, what its own turns change of the scroll bars reaches the bars at most
    once in this many milliseconds (by the turns' clock), and always when the load ends (P-1):
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
  { The most bytes of image a picture is made from (a paste, TyRichMakePicture): 128 MB. With
    CRichPictureMaxPixels (32 Mi pixels: the most the layouter decodes - a bigger picture
    would only ever show as a placeholder - and 128 MB once decoded) it bounds what one paste
    makes the process hold: the bytes, their decoded pixels while a PNG is made of them, and
    the picture the document and its undo step keep. }
  CRichPictureMaxBytes = 128 * 1024 * 1024;

type
  ETyRichEdit = class(Exception);

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

  { The clipboard's flavours a paste takes, in the order it takes them. HTML is none of them:
    a clipboard with HTML and text pastes the text (spec goal 10). }
  TTyRichClipFlavour = (rcfRtf, rcfPicture, rcfText);
  TTyRichClipFlavours = set of TTyRichClipFlavour;
  { What PasteFromClipboard takes: rpaBest the first flavour there that can be used (RTF, a
    picture, text); the others that one alone ("paste as plain text"). }
  TTyRichPasteAs = (rpaBest, rpaRtf, rpaPicture, rpaText);
  { The bytes of an image as they come: a PNG, JPEG or TIFF file, a BMP file, a DIB (a BMP
    without its file header, Windows' CF_DIB). }
  TTyRichImageKind = (rikPng, rikDib, rikBmp, rikTiff, rikJpeg);
  { TyRichMakePicture's answer: made; the bytes are no image it can decode; the image is over
    the bounds (CRichPictureMaxBytes, CRichPictureMaxPixels). }
  TTyRichPictureMade = (rpmMade, rpmNoImage, rpmTooLarge);

  TTyCustomRichEdit = class;

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

  { What drives the background work's turns (R49), chosen per widgetset by what was measured
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
    FUpdating: Boolean;
    { An empty document is no lines or one empty line: TStrings tells them apart, the text
      cannot. Set by Add('') / Insert on no lines, by a delete that leaves one empty line and
      by a replacement with one empty line; cleared by Clear, by any other replacement and
      when the document is no longer empty. }
    FEmptyLine: Boolean;
    procedure Run(ACmd: TTyRichCommand);
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

  { A picture waiting to be decoded or scaled: the size it is to be drawn at and the paragraphs
    of the block it was met in. Holds a reference to the picture. }
  TTyRichPendingPicture = record
    Picture: TTyRichPicture;
    Width, Height: Integer;
    Para, LastPara: Integer;
  end;

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
      read: written first whenever the content is saved as RTF (R40). A load of anything else
      and a Lines replacement forget it. }
    FRtfPrefix: TBytes;
    // the view
    FAnchorPara: Integer;
    FAnchorOffset: Int64;
    { A layout parameter changed: the anchor block's offset as a share of its height then, so
      that the same share of it is above the view once it is laid out again (H-M3). }
    FAnchorShareNum, FAnchorShareDen: Int64;
    { What the last LayoutView did to the view: the held blocks' tops moved (by FMovedBy when
      FMoveKnown: the same paragraph is on top, somewhere else). }
    FViewShifted: Boolean;
    FMoveKnown: Boolean;
    FMovedBy: Int64;
    { A bar decision a layout made in this EnsureView: 0 none, 1 hidden, 2 shown. }
    FLatchV, FLatchH: Integer;
    FScrollX: Integer;              // raster pixels
    { The kept surface (R39): what the control shows, frame and text, at FSurfScale device
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
      it lays out (K-2). }
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
    { The driver's state (R49): the idle handler is registered (rtdIdle), the turn timer
      (rtdTimer; made on the first start, freed with the window), a turn is running. }
    FIdleOn: Boolean;
    FTurnTimer: TTimer;
    FInTurn: Boolean;
    { rtdIdle's backstop timer (N-2; made on the first start, freed with the window), the
      turns run so far and how many of them its last tick had seen. }
    FBackstop: TTimer;
    FTurnsRun, FBackstopSeen: Int64;
    { The size of a turn's load slices (N-3, N-4: see SliceBytes), and within a turn the bytes
      it indexed and the progress handler's milliseconds so far. }
    FSlice, FTurnBytes, FHandlerMs: Int64;
    { P-1: inside a load's own change made in a turn (DocChanged); the bars' widgets are behind
      the control's values; the turn clock at which a turn last gave them its range (valid:
      since the load began). }
    FBarsLazy, FBarsBehind, FBarsAtValid: Boolean;
    FBarsAt: QWord;
    { P-2: a load whose next turn could not be scheduled ends at the next entry point of the
      loop (see SchedulingFailed). }
    FLoadEndOwed: Boolean;
    FPending: array of TTyRichPendingPicture;
    FPendingCount: Integer;
    { The (picture, size) pairs whose PreparePicture raised (a fatal error: out of memory, an
      access violation), with a reference each: not queued again until the content or the
      layout parameters change. Every other outcome the layouter records itself - after
      PreparePicture the picture is ready or known to be a placeholder (H-I7). }
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
      settled query puts them on caret places (S-M10). }
    FSnapPending: Boolean;
    { A window paint came while the document held its changes back and drew nothing new (it
      blitted the old surface, or nothing): the window is asked to paint again, whole, when
      the view hears of the change (K-11). }
    FSkippedPaint: Boolean;
    { The pointer was last seen over the padding (MouseMove; GetCursor answers the arrow);
      cleared when it leaves the control. }
    FOverPadding: Boolean;
    { The selection was set while the document held its changes back (L-4): the positions
      are the text's as it was then, not moved by the update's own change; the update's end
      clamps them to the final text and paints the selection. }
    FSelInUpdate: Boolean;
    // editing (Task 10a)
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
    FOnEditRefused: TTyRichEditRefusedEvent;
    { The input method (Task 10b). A composition goes in at FCompPos (the caret when it began)
      and is not the document's: the layouter shows FCompText there (SetComposition), in
      FCompFormat (the typing format then), the input method's caret and clause in it
      (characters of FCompText). FImeRefused: the input method's session was refused (the
      document took no edit when it began): what it sends goes nowhere until it ends. }
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
    { Fix wave W12. FCompAnchor: the selection's anchor when the composition began (FCompPos
      its caret) - the commit replaces that selection, the one the user saw, not one made
      meanwhile; both follow the text as the caret does. FCompPending: the control ended the
      composition and told the input method to commit, and it had not answered while told -
      a result it sends before its next start goes in there (FCompPos, FCompAnchor,
      FCompFormat kept). }
    FCompAnchor: TTyRichPos;
    FCompPending: Boolean;
    { Cocoa's bridge: its session is open (ImeSessionBegin .. ImeSessionEnd), one of its calls
      runs (FInBridge), the control ended the session's composition itself (FCocoaSwallow:
      Cocoa keeps its marked text, so what the bridge sends until the session's end goes
      nowhere - it went in, or was dropped, when the control ended it). }
    FCocoaSession, FCocoaSwallow: Boolean;
    FInBridge: Integer;
    // events
    FOnSelectionChange: TNotifyEvent;
    FOnChange: TNotifyEvent;
    FOnZoomChange: TNotifyEvent;
    FOnLoadProgress: TTyRichProgressEvent;
    FOnSaveProgress: TTyRichProgressEvent;
    procedure DocChanged(Sender: TObject; const AChange: TTyRichChange);
    { The document stopped holding its changes back (TTyRichDocument.OnUpdatingEnd), after
      the change, if any, was reported: what was put off while it held them is done now - a
      skipped paint made good (K-11 / L-3), a selection set meanwhile painted (L-4). }
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
      change recorded (H-M3): its offset becomes that share of its new height. }
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
    procedure SetSelStart(AValue: TTyRichPos);
    procedure SetSelLength(AValue: TTyRichPos);
    procedure SetCaretPos(AValue: TTyRichPos);
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
    { The caret and the anchor a document change moved, put on caret places (S-M10). It calls
      no user code: a move is reported by the user action it runs in (its one report at its
      end), else by a queued call after it (K-10). }
    procedure SnapAfterChange;
    { The document holds back changes the view has not heard of (TTyRichDocument.Updating, or
      a content the view was not told of yet): the view's blocks may name paragraphs that are
      gone. The one door every entry that needs the layout asks first - the paint and the
      caret, the blink and the drag ticks, keys, the wheel, the mouse, the input method's
      query, the public settled queries and the selection (Select, the selection setters):
      input does nothing (a key the viewer takes is still taken), a query answers "not
      available" (K-9), a selection is kept and painted when the update ends (L-4). }
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
    procedure ParaRangeAt(APos: TTyRichPos; out AFrom, ATo: TTyRichPos);
    { The object character whose box client point (X, Y) is on, near hit position APos; -1
      when the point is on none. }
    function ObjectAt(X, Y: Integer; APos: TTyRichPos): TTyRichPos;
    { The selection becomes AAnchor .. ACaret: what changed its selected state is painted again
      (only those lines' bands); nothing else - the caller scrolls, blinks and reports. }
    procedure Select(AAnchor, ACaret: TTyRichPos; AAtEnd: Boolean);
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
    procedure SetScrollXRaster(AValue: Integer);
    function GetSelText: string;
    procedure SetSelText(const AValue: string);
    // editing (Task 10a)
    { Why the document takes no edit now ('' when it does): loading, incomplete, saving. }
    function RefusalReason: string;
    { AUser (a key, the menu): EditRefused; otherwise (code) ETyRichEdit is raised. }
    procedure Refuse(const AReason: string; AUser: Boolean);
    function EngineRefusal(E: Exception): string;
    { A user's insert of AText at APos would put its end past the cut of a paragraph too long
      to lay out whole: refused (told), True. }
    function LongParaRefused(APos: TTyRichPos; const AText: UTF8String): Boolean;
    { A user's edit that deletes or replaces [AStart, AStart + ALen): a selection that ends at
      a table's first row and begins before it keeps its last separator (ALen one less); one
      that crosses a cell's or a row's edge is refused (told, False) unless it is whole rows. }
    function UserRangeAllowed(var AStart, ALen: TTyRichPos): Boolean;
    { [AFrom, ATo) is whole rows of one table: from a row's first paragraph's start to the
      start of the paragraph after a row (or the text's end). Inside a read scope. }
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
    { Runs ACmd (the document owns it from here) as the control's own edit: True when it ran
      and changed something - FEditChange is what it changed, the caret has not been placed.
      The step it became carries the selection before it (its marks; the selection after it
      is FinishEdit's). Refused by the engine (CanExecute, an ETyRichModel the command
      reverted): the caret, the selection and Modified stay as they were, and Refuse. }
    function RunEdit(ACmd: TTyRichCommand; AUser: Boolean): Boolean;
    { After an edit of the control's own: the selection AAnchor .. ACaret (put on caret places,
      never in a cut paragraph's hidden tail, AAtEnd the caret's affinity where it stays put,
      the wished x forgotten), scrolled into view, the caret shown, then the one OnChange and
      the one OnSelectionChange of the action. ARestore: a selection an undo puts back as it
      was before its step, taken as it is (a hidden tail too - Select All had it). }
    procedure FinishEdit(AAnchor, ACaret: TTyRichPos; AAtEnd: Boolean = False;
      ARestore: Boolean = False);
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
    { A clipboard's text made fit to insert (see PasteFromClipboard). }
    function PastedText(const AText: RawByteString): UTF8String;
    { The width a picture pasted at APos may take, in twips: the view's text width (0 when
      nothing wraps) less the paragraph's indents, or its cell's width. }
    function PictureRoom(APos: TTyRichPos): Integer;
    { An undo (ARedo False) or a redo step and where it leaves the caret. }
    procedure RunHistory(ARedo, AUser: Boolean);
    { A key the editor takes (it edits, or would: ReadOnly takes it and does nothing, as the
      memo does). }
    function IsEditKey(AKey: Word; AShift: TShiftState): Boolean;
    { A character typed: inserted when it is printable and whole (not with ReadOnly, not
      inside the document's update). }
    procedure TypeKey(const AKey: TUTF8Char);
    // the input method (Task 10b)
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
    { The one door of a user's edit and action (fix wave W12): a composition open in the text
      ends first, committed as a press commits it - see the body for who comes through it. }
    procedure EndCompositionForUser;
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
    { win32 (fix wave W12): the system's composition window kept away when the window gets the
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
  protected
    function GetStyleTypeKey: string; override;
    { The parts a descendant may make its own: the document (called once, from the
      constructor), the device the layout measures and draws with, the layouter. }
    function CreateDocument: TTyRichDocument; virtual;
    function CreateDevice: TTyRichTextDevice; virtual;
    function CreateLayouter: TTyRichLayouter; virtual;
    { The block paragraph AIndex is in, laid out for the view (with a reference for the
      caller). Every layout the view makes goes through here. }
    function LayoutBlockAt(AIndex: Integer): TTyBlockLayout; virtual;
    { The colours the text is painted with, from the theme: TyRichEdit's text colour, the
      selection (TyRichEditSelection, :focus while focused), a selected picture's frame
      (TyRichEditObject), a picture that cannot be shown (TyRichEditPlaceholder); table lines in
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
      what is drawn over the blit after it - 9b's caret blinks through here alone (a test
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
    { Lays the document's bytes from the stream into it as AFormat (rfRtf / rfText). }
    procedure LoadAs(AStream: TStream; AFormat: TTyRichFormat);
    { The content replaced with AText as plain text (Lines); not refused by ReadOnly. }
    procedure SetPlainText(const AText: string);
    { What the stream holds, by its first bytes (the position is left where it was). }
    function DetectFormat(AStream: TStream): TTyRichFormat;
    { One piece of the background work: a load slice, else one picture made ready. False when
      there was nothing to do. What a turn runs, a few milliseconds a turn. A load slice that
      raises without having indexed a byte would raise again: the load is cancelled (the
      document keeps what was read, Incomplete) and the error goes on; one that got further
      (a handler of its progress or change raised) leaves the load to go on (K-4). }
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
    procedure BackgroundTurn;
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
      then, its idle handler lists go): nothing is queued or registered (L-2). }
    function SchedulingClosed: Boolean; virtual;
    { rtdIdle's idle handler: queues the one call that runs the next turn; with no work (or
      no window) left it takes itself away. Done is left as it is (the idle step still runs
      the actions' updates). }
    procedure IdleStep(Sender: TObject; var Done: Boolean); virtual;
    { rtdIdle's backstop tick (N-2): when no turn ran since the last tick (the idle step is
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
    { The blink: the caret's half period passed - its rectangle is blitted again, nothing on
      the surface is drawn. }
    procedure BlinkTick(Sender: TObject);
    { A drag held outside the text: the view scrolls, faster the further out the pointer is,
      and the selection follows (what the drag timer runs). }
    procedure DragScrollTick(Sender: TObject);
    { The cursor at client point (X, Y): the I-beam over the text, the arrow over the padding
      (the scroll bars have their own). }
    function CursorAt(X, Y: Integer): TCursor;
    { OnSelectionChange, when the caret or the anchor moved since it was last raised. }
    procedure DoSelectionChange; virtual;
    { A copy's two flavours to the clipboard, in one Open .. Close of LCL's Clipboard: the RTF
      under the platform's name for it (TyRichClipboardRtfName; left out when ARtf is ''),
      then the text. The seam a test stands in for: no test reaches the system's clipboard. }
    procedure WriteClipboard(const ARtf: RawByteString; const AText: string); virtual;
    { The paste's side of the clipboard, the seam a test stands in for. ClipboardFlavours: the
      flavours there, asked of LCL's Clipboard by format (HasFormat) - nothing is read, so the
      menu can ask on every popup. The reads: the RTF's bytes ('' none), the picture's bytes
      and their kind (nil none), the text (UTF-8 as LCL gives it, '' none). By widgetset (the
      names LCL hands the system): RTF under TyRichClipboardRtfName; a picture - LCL-Win32
      the registered "PNG" first, then CF_DIB (a raw format id: LCL-Win32 passes it to the
      system as it is); LCL-Cocoa public.png, then public.tiff (LCL's Cocoa clipboard maps no
      such name, so each is the pasteboard type of that very name); elsewhere (GTK, Qt)
      image/png, the MIME type those toolkits offer an image as; the text LCL's own. }
    function ClipboardFlavours: TTyRichClipFlavours; virtual;
    function ReadClipboardRtf: RawByteString; virtual;
    function ReadClipboardPicture(out AKind: TTyRichImageKind): TBytes; virtual;
    function ReadClipboardText: string; virtual;
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
      or Alt, and Tab without WantTabs are left to the form. }
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    { A printable character typed (any Unicode): it replaces the selection, else goes in at
      the caret, in TypingFormat; consecutive typing is one undo step (the engine merges it)
      until the caret is moved by the user, another command runs, Enter is pressed or the
      focus leaves - a space does not end it (as the memo's). OnUTF8KeyPress and OnKeyPress
      come first and may stop it (TyAskKeyPress), also with ReadOnly. }
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    { The character format the next typed text gets: with a selection, its first
      character's (it is typed over); else the character's before the caret in its paragraph,
      at a paragraph's start the one's after it (TTyRichDocument.TypingFormatAt). The one
      place a pending format (a format chosen with nothing selected, Task 11) comes in. }
    function TypingFormat: TTyCharFormatId; virtual;
    { The document is plain text - read from a text file, set as text (Lines), or saved as one
      - where a key makes no line break inside a paragraph (Shift+Enter makes a paragraph). The
      seam for the PlainText state Task 11 publishes. }
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
      (see NoteTurn). A file that indexes slowly gets smaller slices, not longer turns (L-6),
      its first turn too (N-3); one stalled turn costs one halving (N-4). Outside a turn (a
      step by hand): StepBytes. A test seam (it records what the loader was asked). }
    function SliceBytes: Int64; virtual;
    property PendingPictureCount: Integer read FPendingCount;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { RTF or text, by the content (an RTF signature), opened shared for reading. }
    procedure LoadFromFile(const AFileName: string);
    { From the stream's position to its end, read here (nothing keeps the stream). }
    procedure LoadFromStream(AStream: TStream; AFormat: TTyRichFormat = rfAuto);
    { rfAuto: by the extension (.rtf, .txt), else as the content came. Written to a temporary
      file beside AFileName first, which takes AFileName's place only when the save completed:
      a cancelled or failed save leaves the file as it was. Refused for an incomplete document
      (a cancelled load). A load still going on is finished first. }
    procedure SaveToFile(const AFileName: string; AFormat: TTyRichFormat = rfAuto);
    { rfAuto: as the content came (RTF for a new document). A load still going on is finished
      first; an incomplete document is refused. }
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
      Written inside the document's BeginUpdate .. EndUpdate (and so CaretPos, SelectAll,
      ClearSelection): the positions are stored, clamped to the text as it is at that moment,
      and nothing is laid out, scrolled or painted. Edits made later in the same update do not
      move them; when the update ends they are clamped to the final text (and to a caret place)
      and the selection is painted. }
    property SelStart: TTyRichPos read GetSelStart write SetSelStart;
    property SelLength: TTyRichPos read GetSelLength write SetSelLength;
    { The caret: SelStart's end or the other (the end a Shift move moves); writing it collapses
      the selection there. Inside an update: as SelStart. }
    property CaretPos: TTyRichPos read FCaret write SetCaretPos;
    { The caret's affinity: it stands at the end of a wrapped line rather than at the start of
      the line below (End, a click past a line's end). }
    property CaretAtLineEnd: Boolean read FCaretAtEnd;
    function HasSelection: Boolean;
    { Everything, the last paragraph's whole text (a cut paragraph too); the view does not
      move. Nothing is laid out or walked: only what is on screen is painted again. Inside an
      update: as SelStart (the end is the text's end at that moment, clamped when it ends). }
    procedure SelectAll;
    { The selection collapses onto the caret. }
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
    { Copy, then the selection goes: one undo step. Nothing selected: nothing. An edit from
      code (ReadOnly does not stop it; a refusal raises ETyRichEdit, before anything is
      copied). }
    procedure CutToClipboard;
    { Ctrl+V, Shift+Insert and the menu's Paste: the user's paste, and an application's (its
      own menu item, "paste as plain text" with rpaText). A user's action from any of them:
      an open composition ends first (EndCompositionForUser); with ReadOnly nothing happens
      (the clipboard is not read); a refusal - the document loading, incomplete or being
      saved, a row that holds a nested table, a selection across cells (R57), the caret at
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
      wait cursor meanwhile (BeginWait); the paste runs at once and lets no message in. }
    procedure PasteFromClipboard(AAs: TTyRichPasteAs = rpaBest);
    { The control can be edited by the user now (not ReadOnly, enabled, the document taking
      edits) and the clipboard holds a flavour it takes. Reads nothing (ClipboardFlavours). }
    function CanPaste: Boolean;
    { One step of the document's history back / forward (Ctrl+Z, Ctrl+Y). After an undo the
      text the step put back is selected (an undone deletion, a typing over a selection) or,
      when it put back none (an undone insertion), the caret is where that text was; after a
      redo the caret is at the end of what the step changed. Nothing to undo / redo: nothing.
      From code: not refused by ReadOnly; while the document is being saved (or is loading,
      or incomplete) it raises ETyRichEdit. }
    procedure Undo;
    procedure Redo;
    { The document's: there is a step to undo / redo now. }
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    { The history goes (TTyRichDocument.ClearUndo); the text stays. }
    procedure ClearUndo;
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
    { The input method's composition (Task 10b), what each widgetset's input method is turned
      into (win32's messages, Cocoa's bridge, the Qt / GTK hooks' commits). A composition is
      shown where it goes in - at the caret when it began, in the typing format, underlined
      (TyRichEditComposition), laid out with its paragraph - and is not the document's: no
      command, no undo step, no OnChange, not Modified, not in the text, SelText, Lines, a copy
      or a save. A selection stays shown and is replaced at the commit.
      BeginComposition: False when none can begin - ReadOnly or disabled (nothing is told, as
      for a key), where typing would be refused (the document taking no edit, a row that holds
      a nested table, a selection across cells, a cut paragraph's cut: EditRefused once; what
      the input method sends then goes nowhere until its session ends), inside the
      document's update.
      UpdateComposition: the composition's text now (begun when it was not), ACaret its caret
      (characters of AText; -1: at its end), the clause the input method works on.
      CommitComposition: the text goes in as typing does (TypeText: one command, the selection
      replaced in one undo step, merged with the typing before it as the memo's, the caret
      behind it, one OnChange and one OnSelectionChange) - where the composition was shown,
      over the selection there was when it began, in the format it was shown in; also with no
      composition (a commit straight from the input method: at the caret, in the typing
      format); '' commits nothing. A refused one: EditRefused once.
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
    { Cleared by SaveToFile in a format that keeps the content (RTF; text for a text
      document); an RTF document saved as text is an export and stays Modified, with its
      SourceFile and SourceFormat. SaveToStream never touches Modified, SourceFile or
      SourceFormat. }
    property Modified: Boolean read GetModified write SetModified;
    { The file the content was loaded from or last saved to ('' when none). }
    property SourceFile: string read FSourceFile;
    property SourceFormat: TTyRichFormat read FSourceFormat;
    { Fonts tried for a character the font in effect has no glyph for (the layouter's). }
    property FallbackFonts: TStrings read GetFallbackFonts;
    property WrapMode: TTyRichWrapMode read FWrapMode write SetWrapMode default rwmWindow;
    property Zoom: Integer read FZoom write SetZoom default 100;
    { The user's editing, only: with True no key, no menu item, no input method and no paste
      (PasteFromClipboard, as TTyMemo's) changes the document - setting it cancels a
      composition; the caret, the selection and copying work as in a viewer. Code is not stopped by it, as TMemo.ReadOnly does not stop
      Lines.Add: the document's commands (Document.Execute), Lines, SelText, CutToClipboard,
      Undo and Redo change the document with ReadOnly True. }
    property ReadOnly: Boolean read FReadOnly write SetReadOnly default False;
    { True: Tab inserts a tab character (Shift+Tab and Ctrl+Tab too, as the memo). False (the
      default, as the memo): Tab is left to the form, which moves the focus. }
    property WantTabs: Boolean read FWantTabs write FWantTabs default False;
    property Lines: TStrings read GetLines write SetLines stored IsLinesStored;
    { A txt file is read in this encoding (teAuto: found out) and, for teAnsi, code page. }
    property TextEncoding: TTyTextEncoding read FTextEncoding write FTextEncoding default teAuto;
    property TextCodePage: Integer read FTextCodePage write FTextCodePage default 0;
    property ScrollBarAutoHide: TTyScrollBarAutoHide read FScrollBarAutoHide
      write SetScrollBarAutoHide default sbahDefault;
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
    { The constructor's values (R31): a fresh control stores neither, and a Cursor of crDefault
      set in the designer is stored. }
    property TabStop default True;
    { ITyScrollBarFrameHost }
    function ScrollBarFrameStyle: TTyStyleSet;
    function EmbedsScrollBar(ABar: TTyScrollBar): Boolean;
  published
    { TControl publishes Cursor and a redeclaration cannot unpublish it (the memo's #108). }
    property Cursor default crIBeam;
  end;

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
    property StyleClass;
    property StyleOverride;
    property Controller;
    property Lines;
    property WrapMode;
    property Zoom;
    property ReadOnly;
    property WantTabs;
    property TextEncoding;
    property TextCodePage;
    property ScrollBarAutoHide;
    property OnChange;
    property OnSelectionChange;
    property OnZoomChange;
    property OnEditRefused;
    property OnLoadProgress;
    property OnSaveProgress;
    property OnFallbackFont;
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
    property OnContextPopup;
    property OnResize;
  end;

{ The name a copy's RTF goes to the clipboard under: Windows' registered "Rich Text Format";
  on a Mac (LCL's Cocoa clipboard keeps a name it has no mapping of as the pasteboard type
  itself) the type public.rtf, NSPasteboardTypeRTF's; elsewhere the MIME type text/rtf.
  Chosen by platform, not by widgetset: LCL's Qt clipboard hands the name to Qt as a MIME type
  and GTK's makes an atom of it, and how Qt on Windows or Qt / GTK on a Mac map such a name to
  the system's rich-text type is the toolkit's, not LCL's - those pairs are not verified. }
function TyRichClipboardRtfName: string;

{ A picture object made from an image's bytes (what a paste makes of a clipboard's picture;
  inserting a picture from a file can make its own the same way). PNG and JPEG keep their
  bytes; a DIB, a BMP or a TIFF is decoded and stored as PNG (with its alpha when a pixel is
  not opaque; a 32-bit bitmap whose alpha is 0 everywhere is opaque, as Windows' bitmaps
  without alpha are). The image is decoded in any case: bytes that do not decode are no
  image (rpmNoImage). Its size: its pixels at its own resolution (a PNG's pHYs, a bitmap's
  pixels per metre) or at 96 dpi, scaled down keeping the ratio to AMaxWidthTwips when wider
  (0: no bound). Over CRichPictureMaxBytes bytes or CRichPictureMaxPixels pixels (asked of the
  header before anything is decoded where the format says it there - PNG, BMP, DIB):
  rpmTooLarge. APicture is the caller's (no reference taken) when rpmMade, else nil. }
function TyRichMakePicture(const ABytes: TBytes; AKind: TTyRichImageKind;
  AMaxWidthTwips: Integer; out APicture: TTyRichPicture): TTyRichPictureMade;

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

implementation

uses
  {$IFDEF UNIX}BaseUnix,{$ENDIF}
  RTLConsts, Clipbrd, InterfaceBase, LazUTF8, FPImage, BGRAReadPng, BGRAReadBMP, BGRAReadTiff,
  BGRAReadJpeg, BGRAWritePNG, tyControls.StrConsts, tyControls.FontUnits,
  tyControls.PlatformWS, tyControls.Animation
  {$IFDEF LCLCocoa}, tyControls.CocoaWS{$ENDIF};

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
  ISC_SHOWUICOMPOSITIONWINDOW = PtrInt($80000000);

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
  inherited Destroy;
end;

procedure TTyRichEditLines.Run(ACmd: TTyRichCommand);
begin
  if not FOwner.FDoc.Execute(ACmd) then
    raise ETyRichEdit.Create(rsRichEditCannotChange);
  FOwner.FLinesStored := True;
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
end;

procedure TTyRichEditLines.Put(Index: Integer; const S: string);
var
  t: TTyRichText;
  d: TTyRichDocument;
  start, len: TTyRichPos;
begin
  if FBatch <> nil then
  begin
    FBatch[Index] := S;
    Exit;
  end;
  if (Index < 0) or (Index >= GetCount) then Error(SListIndexError, Index);
  d := FOwner.FDoc;
  t := d.Text;
  start := t.ParaStart(Index);
  len := t.ParaLength(Index);
  { Never half done (review C-10a, Minor 2): what could refuse is asked before anything
    changes - the row the line is in - and the insert goes first, behind the old text in the
    format it would have got at the line's start, so that one the engine refuses (a text that
    ends inside a UTF-8 sequence) leaves the line, the history and OnChange as they were. }
  if not d.CanChange(start, len) or not d.CanChange(start + len, 0) then
    raise ETyRichEdit.Create(rsRichEditCannotChange);
  d.BeginUpdate;
  try
    if S <> '' then
      Run(TTyRichInsertText.Create(start + len, S, d.TypingFormatAt(start), False));
    if len > 0 then Run(TTyRichDelete.Create(start, len));
  finally
    d.EndUpdate;
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
    FBatch.Text := Value;
    Exit;
  end;
  FOwner.SetPlainText(Value);
end;

procedure TTyRichEditLines.SetUpdateState(Updating: Boolean);
var
  s: string;
begin
  FUpdating := Updating;
  if Updating then
  begin
    // the commands of a batch (AddStrings) are one undo step
    FOwner.FDoc.BeginUpdate;
    Exit;
  end;
  // closed before a gathered replacement: the content is not replaced inside an update
  FOwner.FDoc.EndUpdate;
  if FBatch <> nil then
  begin
    s := FBatch.Text;
    FreeAndNil(FBatch);
    FOwner.SetPlainText(s);
  end;
end;

{ ---- the control ---- }

constructor TTyCustomRichEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle - [csSetCaption];
  TabStop := True;
  FZoom := 100;
  FWrapMode := rwmWindow;
  FReadOnly := False;
  FWantTabs := False;
  FTextEncoding := teAuto;
  FTextCodePage := 0;
  FScrollBarAutoHide := sbahDefault;
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
  FText := FDoc.Text;
  FDoc.OnChange := @DocChanged;
  FDoc.OnUpdatingEnd := @DocUpdatingEnded;
  FLayouter := CreateLayouter;
  FLayouter.Document := FDoc;
  // the layouter empties its caches when the list changes; the view must drop its blocks too
  FFallbackListChange := FLayouter.FallbackFonts.OnChange;
  FLayouter.FallbackFonts.OnChange := @FallbackListChanged;
  FLines := TTyRichEditLines.Create(Self);
  FCaretShown := True;
  FCopyWaitChars := CRichCopyWaitChars;
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
begin
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
  FCocoaSession := False;
  FCocoaSwallow := False;
  TyImeUninstall(FImeHook);
  FreeAndNil(FCocoaIme);
  // nothing queued, registered or timed may come back into a freed control
  StopBackground;
  if FSelCall <> nil then CancelCall(FSelCall);
  FreeAndNil(FTurnTimer);
  FreeAndNil(FBackstop);
  FreeAndNil(FStepCall);
  FreeAndNil(FSelCall);
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
  end;
  if FLayouter <> nil then FLayouter.FallbackFonts.OnChange := FFallbackListChange;
  FreeAndNil(FLayouter);
  FreeAndNil(FDoc);
  FreeAndNil(FLines);
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
  DoZoomChange;
end;

procedure TTyCustomRichEdit.SetWrapMode(AValue: TTyRichWrapMode);
begin
  if AValue = FWrapMode then Exit;
  FWrapMode := AValue;
  FScrollX := 0;
  FWidestSeen := 0;
  ViewMoved;
end;

procedure TTyCustomRichEdit.SetReadOnly(AValue: Boolean);
begin
  if FReadOnly = AValue then Exit;
  FReadOnly := AValue;
  // the run of typing ends: what is typed after it being editable again is a step of its own
  FDoc.BreakMerge;
  // what is being composed cannot go in any more: it goes, and the input method drops it
  if AValue then EndComposition(False);
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
begin
  // a form file's Lines while streaming, the document going with the control: no event
  if [csLoading, csDestroying] * ComponentState <> [] then Exit;
  if Assigned(FOnChange) then FOnChange(Self);
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
  case C of
    $FFFC: Result := 2;
    9, 11, 32, $A0, 33..47, 58..64, 91..94, 96, 123..126: Result := 0;
  else
    Result := 1;
  end;
end;

function TTyCustomRichEdit.GetSelStart: TTyRichPos;
begin
  Result := Math.Min(FCaret, FSelAnchor);
end;

function TTyCustomRichEdit.GetSelLength: TTyRichPos;
begin
  Result := Abs(FCaret - FSelAnchor);
end;

function TTyCustomRichEdit.HasSelection: Boolean;
begin
  Result := FCaret <> FSelAnchor;
end;

{ Inside the document's update (ViewBehind) the setters ask the layout nothing (SnapPos would
  look a block up by a paragraph index the layouter has not heard of): Select keeps the
  positions, the update's end puts them on caret places (L-4). }
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

procedure TTyCustomRichEdit.SetCaretPos(AValue: TTyRichPos);
begin
  SetSelStart(AValue);
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

procedure TTyCustomRichEdit.ClearSelection;
begin
  Select(FCaret, FCaret, FCaretAtEnd);
  CaretMoved;
  DoSelectionChange;
end;

procedure TTyCustomRichEdit.DoSelectionChange;
begin
  if (FCaret = FReportedCaret) and (FSelAnchor = FReportedAnchor) then Exit;
  FReportedCaret := FCaret;
  FReportedAnchor := FSelAnchor;
  if [csLoading, csDestroying] * ComponentState <> [] then Exit;
  if Assigned(FOnSelectionChange) then FOnSelectionChange(Self);
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
    one after it unheld: that one is laid out here (S-I3), and the move scrolls to it. }
  if (ADown and (k < FBlockCount - 1)) or (not ADown and (k > 0)) then
  begin
    if ADown then y := FBlocks[k].Top + FBlocks[k].Height else y := FBlocks[k].Top - 1;
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
  paragraph's end go through here. SelectAll and the setters (SelStart, SelLength, CaretPos)
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

procedure TTyCustomRichEdit.WordAt(APos: TTyRichPos; out AFrom, ATo: TTyRichPos);
var
  a, ps, pe: TTyRichPos;
  codes: TTyRichCodes;
  i, s, e, n, cls: Integer;
begin
  AFrom := APos;
  ATo := APos;
  WordWindow(FDoc.Text, APos, a, ps, pe, codes);
  n := Length(codes);
  if n = 0 then Exit;
  // the character after APos - at the paragraph's end the one before - and its run
  i := Integer(APos - a);
  if i >= n then i := n - 1;
  cls := WordClass(codes[i]);
  if cls = 2 then
  begin
    AFrom := a + i;
    ATo := a + i + 1;
    Exit;
  end;
  s := i;
  while (s > 0) and (WordClass(codes[s - 1]) = cls) do Dec(s);
  e := i + 1;
  while (e < n) and (WordClass(codes[e]) = cls) do Inc(e);
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
  n := Length(codes);
  i := Integer(APos - a);
  if AForward then
  begin
    { The paragraph's end: the next caret place - the next paragraph's start, or in a row the
      next cell shown (a cell merged away is passed over, as Right passes it). }
    if APos >= pe then
    begin
      Result := CaretStep(APos, True);
      Exit;
    end;
    // as the memo: past this word (an object is one by itself), then past what is no word
    if (i < n) and (WordClass(codes[i]) = 2) then Inc(i)
    else
      while (i < n) and (WordClass(codes[i]) = 1) do Inc(i);
    while (i < n) and (WordClass(codes[i]) = 0) do Inc(i);
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
      i := Integer(APos - a);
    end;
    while (i > 0) and (WordClass(codes[i - 1]) = 0) do Dec(i);
    if (i > 0) and (WordClass(codes[i - 1]) = 2) then Dec(i)
    else
      while (i > 0) and (WordClass(codes[i - 1]) = 1) do Dec(i);
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
  a0 := Math.Min(FSelAnchor, FCaret);
  a1 := Math.Max(FSelAnchor, FCaret);
  { The caret or the anchor moved by anything but an edit of the control's own (a key, a
    click, a setter, a change from elsewhere): the next typing is an undo step of its own, as
    the memo's caret moves end its run (S-M9's place: the edits place the caret themselves). }
  if (FEditing = 0) and ((AAnchor <> FSelAnchor) or (ACaret <> FCaret)) then FDoc.BreakMerge;
  FSelAnchor := AAnchor;
  FCaret := ACaret;
  FCaretAtEnd := AAtEnd;
  { The door (K-9, L-4): while the document holds its changes back the held blocks may name
    paragraphs that are gone - the positions are kept (clamped to the text as it is now) and
    nothing is painted; the update's end paints the selection (DocUpdatingEnded). }
  if ViewBehind then
  begin
    FSelInUpdate := True;
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
    inside, against the edge (S-I1). The same at the left edge. }
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
  // a range a load's turns held back first: the position is in the range the bar has (P-1)
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
  q: TTyRichPos;
  atEnd: Boolean;
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

procedure TTyCustomRichEdit.DrawCaret(ACanvas: TCanvas);
var
  r: TRect;
begin
  FCaretDrawn := Rect(0, 0, 0, 0);
  // (inside the document's update the view knows nothing of the change yet: no query)
  if not HasCaretFocus or (csDesigning in ComponentState) or ViewBehind then Exit;
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
    EndUpdate) the blocks may name paragraphs that are gone: the blink waits (S-M11). }
  if ViewBehind then Exit;
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
  if not HandleAllocated then Exit;
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
  FDoc.BreakMerge;
  if FBlinkTimer <> nil then FBlinkTimer.Enabled := False;
  FCaretShown := True;
  StopDrag;
  if not IsRectEmpty(FCaretDrawn) then InvalidateArea(FCaretDrawn);
end;

function TTyCustomRichEdit.CursorAt(X, Y: Integer): TCursor;
begin
  if PtInRect(TextArea(Rect(0, 0, Width, Height), ViewPPI), Point(X, Y)) then
    Result := crIBeam
  else
    Result := crDefault;
end;

function TTyCustomRichEdit.GetCursor: TCursor;
begin
  Result := inherited GetCursor;
  if FOverPadding and (Result = crIBeam) and
    ([csDesigning, csWriting] * ComponentState = []) then
    Result := crArrow;
end;

procedure TTyCustomRichEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  q, a, b, o: TTyRichPos;
  atEnd: Boolean;
  clicks: Integer;
begin
  if not IsEnabled then Exit;
  { A press in the text ends a composition first: it goes in where it was shown, then the
    press places the caret (Cocoa's input method commits on the press before it gets here).
    An input method that answers later sends its result to where the composition was
    (FCompPending), the caret staying where the press put it. }
  EndCompositionForUser;
  inherited MouseDown(Button, Shift, X, Y);
  // a user action is an entry point of the loop (P-2: see SchedulingFailed)
  EndOwedLoad;
  if (Button <> mbLeft) and (Button <> mbRight) then Exit;
  try
    if CanFocus and not Focused then SetFocus;
  except
    // no focus to be had (a form not shown): the caret is placed all the same
  end;
  // inside the document's update a press places nothing (K-9)
  if ViewBehind then Exit;
  q := HitClient(X, Y, atEnd);
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
      // the object under the pointer is the word (on its right half too: S-M3)
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
      { A click on an object selects it (its handles come with editing). The object is the
        pressed unit, as a word is after a double click: it stays selected while the pointer
        moves on it, and a drag extends from it (S-I2). }
      o := ObjectAt(X, Y, q);
      if o >= 0 then
      begin
        Select(o, o + 1, False);
        FDragUnit := 4;
      end
      else
        Select(q, q, atEnd);
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
          start, leftwards it goes to its end - as a word's does (K-12). }
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

procedure TTyCustomRichEdit.StartDragTimer;
begin
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
  FDragging := False;
  if FDragTimer <> nil then FDragTimer.Enabled := False;
  if MouseCapture then MouseCapture := False;
end;

procedure TTyCustomRichEdit.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  area: TRect;
begin
  if not IsEnabled then Exit;
  inherited MouseMove(Shift, X, Y);
  { The arrow over the padding (a cursor set by the user is left alone): GetCursor answers it
    from where the pointer was last seen, which is what LCL-Win32 shows on the window's
    set-cursor message. GTK, Qt and Cocoa set a window's cursor only when told: the
    temporary cursor tells them now (on Windows it sends that message, which asks GetCursor
    again). }
  FOverPadding := CursorAt(X, Y) <> crIBeam;
  if inherited GetCursor = crIBeam then SetTempCursor(Cursor);
  if not FDragging then Exit;
  // inside the document's update the drag waits (K-9)
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
  if not FDragging or not IsEnabled or not IsVisible then
  begin
    StopDrag;
    Exit;
  end;
  // inside the document's update: no query, the drag waits (S-M11)
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
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then StopDrag;
end;

procedure TTyCustomRichEdit.CaptureChanged;
begin
  inherited CaptureChanged;
  // the capture went elsewhere (a menu, another window): the drag is over
  if FDragging and not MouseCapture then StopDrag;
end;

procedure TTyCustomRichEdit.EnabledChanged;
begin
  inherited EnabledChanged;
  StopDrag;
  // disabled: what is being composed cannot go in any more - as ReadOnly set, it is dropped
  if not IsEnabled then EndComposition(False);
end;

procedure TTyCustomRichEdit.VisibleChanged;
begin
  inherited VisibleChanged;
  StopDrag;
end;

{ ---- copying, the menu, the input method ---- }

function TyRichClipboardRtfName: string;
begin
  {$IFDEF MSWINDOWS}
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
    if (used > 0) and (used <= 256) then pal := used else pal := Int64(1) shl bits;
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
  w, h, xppm, yppm, base, hs, i, len: Int64;
  st: TMemoryStream;
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
        if hs = 12 then
        begin
          w := PicLE16(ABytes, base + 4);
          h := PicLE16(ABytes, base + 6);
        end
        else if (hs >= 40) and (hs <= 1024) then
        begin
          w := PicLE32(ABytes, base + 4);
          h := Abs(PicLE32(ABytes, base + 8));
          xppm := PicLE32(ABytes, base + 24);
          yppm := PicLE32(ABytes, base + 28);
        end
        else
          Exit;
      end;
  end;
  if (w = 0) or (h = 0) or (w < -1) or (h < -1) then Exit;
  if (w > 0) and (h > 0) and (w > CRichPictureMaxPixels div h) then Exit(rpmTooLarge);
  st := TMemoryStream.Create;
  bmp := TBGRABitmap.Create;
  rd := nil;
  try
    if AKind = rikDib then WriteDibFileHeader(st, ABytes);
    st.WriteBuffer(ABytes[0], Length(ABytes));
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
          data := ABytes;
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
var
  s, n: TTyRichPos;
  rtf: RawByteString;
  txt: string;
  st: TTyRichStringOut;
  wait: Boolean;
begin
  // nothing selected: nothing put there, the clipboard keeps what it had
  if not HasSelection then Exit;
  s := GetSelStart;
  n := GetSelLength;
  wait := n > FCopyWaitChars;
  if wait then BeginWait;
  try
    txt := RangeText(s, n);
    rtf := '';
    FDoc.BaseFontName := TyEffectiveFontName(CurrentStyle.FontName);
    st := TTyRichStringOut.Create;
    try
      try
        TyRichSaveRtfRange(FDoc, st, s, n);
        rtf := st.Take;
      except
        // a range the RTF writer refuses (a changed row holding a nested table): the text alone
        on ETyRichRtfWrite do rtf := '';
      end;
    finally
      st.Free;
    end;
    WriteClipboard(rtf, txt);
  finally
    if wait then EndWait;
  end;
end;

{ ---- editing (Task 10a) ----

  Every edit is a command run by the document (TTyRichDocument.Execute), so the history holds
  all of it; the control never changes the text another way. An edit of the control's own
  goes: EditAllowed (the document takes edits now, no row that holds a nested table is in the
  way) - RunEdit (the command, the document's one OnChange heard but held: FEditing) -
  FinishEdit (the caret placed where the edit leaves it, scrolled into view, then the
  action's one OnChange and one OnSelectionChange). The caret's new place is read off what
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
  else Result := rsRichEditRefusedRange;
end;

procedure TTyCustomRichEdit.Refuse(const AReason: string; AUser: Boolean);
begin
  if AUser then EditRefused(AReason) else raise ETyRichEdit.Create(AReason);
end;

procedure TTyCustomRichEdit.EditRefused(const AReason: string);
begin
  if Assigned(FOnEditRefused) then FOnEditRefused(Self, AReason);
end;

function TTyCustomRichEdit.EditAllowed(APos, ALen: TTyRichPos; AInsert, AUser: Boolean): Boolean;
var
  reason: string;
begin
  reason := RefusalReason;
  { Asked before the command is made: a composite (a selection typed over) that the engine
    refused half way would be reverted, but would have reported a change and set Modified on
    the way (RunEdit puts Modified back, as a backstop). }
  if (reason = '') and (((ALen > 0) and not FDoc.CanChange(APos, ALen)) or
    (AInsert and not FDoc.CanChange(APos, 0))) then
    reason := rsRichEditRefusedFixedRow;
  Result := reason = '';
  if not Result then Refuse(reason, AUser);
end;

function TTyCustomRichEdit.RunEdit(ACmd: TTyRichCommand; AUser: Boolean): Boolean;
var
  c, a: TTyRichPos;
  atEnd, wasModified, ok: Boolean;
  marks: TTyRichStepMarks;
  refusal: string;
begin
  Result := False;
  refusal := '';
  c := FCaret;
  a := FSelAnchor;
  atEnd := FCaretAtEnd;
  wasModified := FDoc.Modified;
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
  Inc(FEditing);
  try
    try
      ok := FDoc.Execute(ACmd);
    except
      on E: ETyRichModel do
      begin
        // the engine reverted what the command did: as if it had not run
        FCaret := c;
        FSelAnchor := a;
        FCaretAtEnd := atEnd;
        FDoc.Modified := wasModified;
        if not AUser then raise;
        refusal := EngineRefusal(E);
      end;
    end;
  finally
    Dec(FEditing);
  end;
  { Told once the edit's bracket is closed: a handler that changes or loads the document is
    heard as a change from elsewhere (its OnChange), not taken for this edit's. }
  if refusal <> '' then
  begin
    EditRefused(refusal);
    Exit;
  end;
  if not ok then
  begin
    // CanExecute said no: the built-in commands ask CanChange, a row that holds a nested table
    Refuse(rsRichEditRefusedFixedRow, AUser);
    Exit;
  end;
  // (a command that changed nothing is not kept and reported nothing: the caret stays)
  Result := FEditHeard;
  { The step it became - its own, or the run of typing it merged into: the newest of the
    history (inside the document's update it went into the update's block: no step yet). }
  if Result and not FDoc.Updating then FEditStep := FDoc.UndoStep;
end;

procedure TTyCustomRichEdit.FinishEdit(AAnchor, ACaret: TTyRichPos; AAtEnd: Boolean;
  ARestore: Boolean);
var
  q: TTyRichPos;
  marks: TTyRichStepMarks;
begin
  { The caret and the anchor an edit leaves obey the rule of a user's move: never in a cut
    paragraph's hidden tail (back to the cut). A selection an undo puts back is taken as it was. }
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
  ScrollCaretIntoView;
  CaretMoved;
  DoChange;
  DoSelectionChange;
end;

function TTyCustomRichEdit.TypingFormat: TTyCharFormatId;
var
  t: TTyRichText;
  s: TTyRichPos;
  p: Integer;
begin
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
  s, n, q: TTyRichPos;
  fmt: TTyCharFormatId;
  cmd: TTyRichCommand;
  comp: TTyRichCompositeCommand;
begin
  s := GetSelStart;
  n := GetSelLength;
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
  if RunEdit(cmd, AUser) then
  begin
    // behind what went in (a paragraph separator is one character: after Enter, the new
    // paragraph's start) - a commit counts its own text (its change may be a composite's)
    if ACaretChars >= 0 then q := s + ACaretChars
    else q := FEditChange.Pos + FEditChange.NewLen;
    FinishEdit(q, q);
  end;
end;

procedure TTyCustomRichEdit.DeleteText(AFrom, ATo: TTyRichPos; AUser: Boolean);
begin
  if ATo <= AFrom then Exit;
  if not EditAllowed(AFrom, ATo - AFrom, False, AUser) then Exit;
  if RunEdit(TTyRichDelete.Create(AFrom, ATo - AFrom), AUser) then
    FinishEdit(FEditChange.Pos, FEditChange.Pos);
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
  ps, pe, a, b, s, n: TTyRichPos;
  codes: TTyRichCodes;
begin
  if HasSelection then
  begin
    s := GetSelStart;
    n := GetSelLength;
    if not EditAllowed(s, n, False, True) or not UserRangeAllowed(s, n) then Exit;
    DeleteText(s, s + n, True);
    Exit;
  end;
  t := FDoc.Text;
  p := t.ParaOfPos(FCaret);
  ps := t.ParaStart(p);
  pe := ps + t.ParaLength(p);
  { Backspace at the start of a list item (empty or not) takes its numbering first, as
    msftedit and Word do (R55 c); the next Backspace joins it with the paragraph before. }
  if not AForward and (FCaret = ps) and
    (FDoc.Formats.ParaFormat(FDoc.ParaFormatOf(p)).List.Kind <> lkNone) then
  begin
    LeaveList(p);
    Exit;
  end;
  if AForward then
  begin
    // at the document's end nothing happens, and nothing goes on the history
    if FCaret >= t.Length then Exit;
    a := FCaret;
    // at a paragraph's end (Ctrl too, as the memo): the separator, the next paragraph joins
    if FCaret >= pe then b := pe + 1
    else if AWord then b := WordStep(FCaret, True)
    else b := CaretStep(FCaret, True);
    { A step that leaves the paragraph before its end is the cut of a paragraph too long to
      lay out whole: what lies past it is not shown, and a key does not take it. }
    if (b > pe + 1) or ((b > pe) and (FCaret < pe)) then Exit;
  end
  else
  begin
    if FCaret <= 0 then Exit;
    b := FCaret;
    // at a paragraph's start (Ctrl too, as the memo): the separator before it
    if FCaret <= ps then a := ps - 1
    else if AWord then a := WordStep(FCaret, False)
    else
    begin
      codes := RichCodes(t.GetText(FCaret - 1, 1));
      if (Length(codes) = 1) and BackspaceTakesOne(codes[0]) then a := FCaret - 1
      else a := CaretStep(FCaret, False);
    end;
  end;
  if (a < b) and KeyDeleteAllowed(a, b) then DeleteText(a, b, True);
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
        paragraph, nothing is added (Word's way; msftedit adds one, R55 c), the caret stays. }
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
  Result := FSourceFormat = rfText;
end;

function TTyCustomRichEdit.LongParaRefused(APos: TTyRichPos; const AText: UTF8String): Boolean;
var
  t: TTyRichText;
begin
  Result := False;
  // a paragraph break puts the caret at the next paragraph's start, which is shown
  if (AText = '') or (Pos(#10, AText) > 0) then Exit;
  t := FDoc.Text;
  { Past the cut the text would go in unseen, with the caret: the user is told instead (R52's
    way) - the paragraph is too long to edit there. }
  if APos - t.ParaStart(t.ParaOfPos(APos)) + UTF8Length(AText) <= CRichMaxParaLayoutChars then
    Exit;
  Result := True;
  Refuse(rsRichEditRefusedLongPara, True);
end;

function TTyCustomRichEdit.WholeRows(AFrom, ATo: TTyRichPos): Boolean;
var
  t: TTyRichText;
  k, m: Integer;
  ck, cl, cn: TTyRichCell;
begin
  t := FDoc.Text;
  Result := False;
  k := t.ParaOfPos(AFrom);
  ck := FDoc.CellAt(k);
  if (ck = nil) or (AFrom <> t.ParaStart(k)) then Exit;
  // from a row's first paragraph
  if (k > 0) and (FDoc.CellAt(k - 1) <> nil) and (FDoc.CellAt(k - 1).Row = ck.Row) then Exit;
  // to the start of the paragraph after a row of the same table (or the text's end)
  if ATo >= t.Length then
    m := t.ParaCount
  else
  begin
    m := t.ParaOfPos(ATo);
    if (m = 0) or (ATo <> t.ParaStart(m)) then Exit;
  end;
  cl := FDoc.CellAt(m - 1);
  if (cl = nil) or (cl.Row.Table <> ck.Row.Table) then Exit;
  if m < t.ParaCount then
  begin
    cn := FDoc.CellAt(m);
    if (cn <> nil) and (cn.Row = cl.Row) then Exit;
  end;
  Result := True;
end;

function TTyCustomRichEdit.UserRangeAllowed(var AStart, ALen: TTyRichPos): Boolean;
var
  t: TTyRichText;
  k, m: Integer;
  ck, cm, cp: TTyRichCell;
begin
  Result := True;
  if ALen <= 0 then Exit;
  t := FDoc.Text;
  // (the cells are compared inside one read: a document that parses on demand keeps them)
  FDoc.BeginRead;
  try
    k := t.ParaOfPos(AStart);
    m := t.ParaOfPos(AStart + ALen);
    if m = k then Exit;
    ck := FDoc.CellAt(k);
    cm := FDoc.CellAt(m);
    { Until Task 12 (R57). A selection that begins outside a table and ends exactly where its
      first row starts keeps its last separator: the text goes, the paragraph before the
      table stays (Word's way) - the engine would merge it into the first cell. }
    if (cm <> nil) and (AStart + ALen = t.ParaStart(m)) and
      ((ck = nil) or (ck.Row.Table <> cm.Row.Table)) then
    begin
      cp := FDoc.CellAt(m - 1);
      if (cp = nil) or (cp.Row.Table <> cm.Row.Table) then
      begin
        Dec(ALen);
        m := t.ParaOfPos(AStart + ALen);
        if m = k then Exit;
        cm := FDoc.CellAt(m);
      end;
    end;
    { One that crosses a cell's or a row's edge is refused: the engine would merge paragraphs
      of two cells and leave a cell with no paragraph, no place for the caret. Whole rows,
      from a row's start to a row's end, the engine deletes cleanly. }
    if (ck <> cm) and not WholeRows(AStart, AStart + ALen) then
    begin
      Result := False;
      Refuse(rsRichEditRefusedCells, True);
    end;
  finally
    FDoc.EndRead;
  end;
end;

procedure TTyCustomRichEdit.LeaveList(AIndex: Integer);
begin
  if not EditAllowed(FDoc.Text.ParaStart(AIndex), 0, True, True) then Exit;
  if RunEdit(TTyRichSetParaFormat.Create(AIndex, AIndex, [pffList, pffLeftIndent,
    pffFirstIndent], TyDefaultParaFormat), True) then
    FinishEdit(FCaret, FCaret, FCaretAtEnd);
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
  CopyToClipboard;
  if n = 0 then Exit;
  if RunEdit(TTyRichDelete.Create(s, n), AUser) then FinishEdit(FEditChange.Pos, FEditChange.Pos);
end;

procedure TTyCustomRichEdit.CutToClipboard;
begin
  CutSelection(False);
end;

{ ---- pasting (Task 10c) ---- }

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
        TyRichLoadText(d, st);
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
          // a line break; a text document has none inside a line (W11's Shift+Enter)
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
  k: Integer;
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
      if (l >= 0) and (r > l) then Exit(Integer(Min(r - l, Int64(High(Integer)))));
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

function TTyCustomRichEdit.CanPaste: Boolean;
begin
  Result := not FReadOnly and IsEnabled and (RefusalReason = '') and (ClipboardFlavours <> []);
end;

procedure TTyCustomRichEdit.PasteFromClipboard(AAs: TTyRichPasteAs);
var
  have: TTyRichClipFlavours;
  s, n, q, lenBefore: TTyRichPos;
  rtf: RawByteString;
  raw: string;
  txt: UTF8String;
  bytes: TBytes;
  kind: TTyRichImageKind;
  picture: TTyRichPicture;
  src: TTyRichDocument;
  ends, flat, waiting: Boolean;
  cmd: TTyRichCommand;
  comp: TTyRichCompositeCommand;
  fmt: TTyCharFormatId;

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
  EndOwedLoad;
  // the door of a user's edit: a composition goes in first (W12)
  EndCompositionForUser;
  if FReadOnly or not IsEnabled or ViewBehind then Exit;
  have := ClipboardFlavours;
  if not (Wanted(rcfRtf) or Wanted(rcfPicture) or Wanted(rcfText)) then Exit;
  s := GetSelStart;
  n := GetSelLength;
  { As typing over the selection asks: the document takes edits, no row that holds a nested
    table is in the way, the cells (R57: may keep a selection's last separator), the cut of a
    paragraph too long to lay out (nothing goes in past what is shown). }
  if not EditAllowed(s, n, True, True) then Exit;
  if not UserRangeAllowed(s, n) then Exit;
  if LongParaRefused(s, 'x') then Exit;
  Settle;
  // a table goes into a table, or over a selection in one, as its text (no nested tables)
  FDoc.BeginRead;
  try
    flat := (FDoc.CellAt(FDoc.Text.ParaOfPos(s)) <> nil) or
      ((n > 0) and (FDoc.CellAt(FDoc.Text.ParaOfPos(s + n)) <> nil));
  finally
    FDoc.EndRead;
  end;
  fmt := TypingFormat;
  waiting := False;
  cmd := nil;
  try
    { RTF cannot be used when it is no RTF (no signature), reading it raised, or it holds no
      character and no paragraph mark: the next flavour then. }
    if Wanted(rcfRtf) then
    begin
      rtf := ReadClipboardRtf;
      Wait(Length(rtf));
      if rtf <> '' then
      begin
        bytes := nil;
        SetLength(bytes, Length(rtf));
        Move(rtf[1], bytes[0], Length(rtf));
        rtf := '';
        src := TyRichReadRtfFragment(bytes, ends);
        bytes := nil;
        if (src <> nil) and ((src.Text.Length > 0) or ends) then
          cmd := TTyRichInsertFragment.Create(s, src, ends, flat)
        else
          src.Free;
      end;
    end;
    { A picture cannot be used when its bytes do not decode; one too large is refused. }
    if (cmd = nil) and Wanted(rcfPicture) then
    begin
      bytes := ReadClipboardPicture(kind);
      Wait(Length(bytes));
      if bytes <> nil then
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
    if (cmd = nil) and Wanted(rcfText) then
    begin
      raw := ReadClipboardText;
      Wait(Length(raw));
      txt := PastedText(raw);
      raw := '';
      if txt <> '' then cmd := TTyRichInsertText.Create(s, txt, fmt, False);
    end;
    if cmd = nil then Exit;
    // one step: the selection's deletion and the paste, never merged with typing
    comp := TTyRichCompositeCommand.Create(rsRichUndoPaste);
    if n > 0 then comp.Add(TTyRichDelete.Create(s, n));
    comp.Add(cmd);
    cmd := nil;
    lenBefore := FDoc.Text.Length;
    if RunEdit(comp, True) then
    begin
      // behind what went in
      q := s + FDoc.Text.Length - (lenBefore - n);
      FinishEdit(q, q);
    end;
  finally
    cmd.Free;
    if waiting then EndWait;
  end;
end;

procedure TTyCustomRichEdit.RunHistory(ARedo, AUser: Boolean);
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
    Exit;
  end;
  if not FEditHeard then Exit;
  { An undo puts the caret and the selection back as they were before the action, a redo
    leaves a plain caret where the action left it (measured in msftedit, R55: a deleted or
    typed-over selection comes back selected, an undone Backspace has the caret after the
    character, an undone Delete before it, undone typing at its start) - from the marks the
    control kept with the step, never from the change's extent, which cannot tell a deleted
    selection from a character a key took. A step made by code has none: what it put back is
    selected after an undo, the caret at the end of what it changed after a redo. }
  if not ARedo and marks.HasBefore then
    FinishEdit(marks.Before.Anchor, marks.Before.Caret, marks.Before.AtLineEnd, True)
  else if ARedo and marks.HasAfter then
    FinishEdit(marks.After.Caret, marks.After.Caret, marks.After.AtLineEnd)
  else
  begin
    c := FEditChange;
    if not ARedo and (c.NewLen > 0) then FinishEdit(c.Pos, c.Pos + c.NewLen)
    else FinishEdit(c.Pos + c.NewLen, c.Pos + c.NewLen);
  end;
end;

procedure TTyCustomRichEdit.Undo;
begin
  RunHistory(False, False);
end;

procedure TTyCustomRichEdit.Redo;
begin
  RunHistory(True, False);
end;

function TTyCustomRichEdit.CanUndo: Boolean;
begin
  Result := FDoc.CanUndo;
end;

function TTyCustomRichEdit.CanRedo: Boolean;
begin
  Result := FDoc.CanRedo;
end;

procedure TTyCustomRichEdit.ClearUndo;
begin
  FDoc.ClearUndo;
end;

procedure TTyCustomRichEdit.SetSelText(const AValue: string);
var
  s: UTF8String;
begin
  s := AValue;
  TypeText(s, False, False);
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
  if not IsEnabled then Exit;
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

function TTyCustomRichEdit.ClipboardFlavours: TTyRichClipFlavours;
var
  pics: TTyRichClipPictures;
  i: Integer;
begin
  Result := [];
  if Clipboard.HasFormat(RegisterClipboardFormat(TyRichClipboardRtfName)) then Include(Result, rcfRtf);
  pics := ClipPictureFormats;
  for i := 0 to High(pics) do
    if Clipboard.HasFormat(pics[i].Format) then
    begin
      Include(Result, rcfPicture);
      Break;
    end;
  if Clipboard.HasFormat(PredefinedClipboardFormat(pcfText)) then Include(Result, rcfText);
end;

function TTyCustomRichEdit.ReadClipboardRtf: RawByteString;
begin
  Result := ReadClipFormat(RegisterClipboardFormat(TyRichClipboardRtfName));
end;

function TTyCustomRichEdit.ReadClipboardPicture(out AKind: TTyRichImageKind): TBytes;
var
  pics: TTyRichClipPictures;
  i: Integer;
  s: RawByteString;
begin
  Result := nil;
  AKind := rikPng;
  pics := ClipPictureFormats;
  for i := 0 to High(pics) do
    if Clipboard.HasFormat(pics[i].Format) then
    begin
      s := ReadClipFormat(pics[i].Format);
      if s = '' then Continue;
      AKind := pics[i].Kind;
      SetLength(Result, Length(s));
      Move(s[1], Result[0], Length(s));
      Exit;
    end;
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
  // as the memo: OnContextPopup first, then a user's PopupMenu (LCL shows it), else ours
  inherited DoContextPopup(MousePos, Handled);
  if Handled or (PopupMenu <> nil) then Exit;
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
  EndCompositionForUser;
  if not FReadOnly then RunHistory(False, True);
end;

procedure TTyCustomRichEdit.TeRedo;
begin
  EndCompositionForUser;
  if not FReadOnly then RunHistory(True, True);
end;

procedure TTyCustomRichEdit.TeCut;
begin
  EndCompositionForUser;
  if not FReadOnly then CutSelection(True);
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
  SelectAll;
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
  Result := HasSelection;
end;

function TTyCustomRichEdit.TeCanPaste: Boolean;
begin
  Result := CanPaste;
end;

function TTyCustomRichEdit.TeHasText: Boolean;
begin
  Result := FDoc.Text.Length > 0;
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
  Result := FReadOnly or not IsEnabled;
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

{ ---- the input method (Task 10b) ----

  How the package's memo takes an input method, and what of it is here (phase 1 changes
  nothing in the memo):
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
begin
  if FComposing then Exit(True);
  Result := False;
  FImeRefused := False;
  { A composition begins: a result still owed for the one the control ended (FCompPending) is
    not waited for any more - an input method sends it before its next start. }
  FCompPending := False;
  // as a key: ReadOnly or disabled takes it and says nothing; inside the update it is dropped
  if (csDestroying in ComponentState) or ImeIsReadOnly or ViewBehind then Exit;
  EndOwedLoad;
  Settle;
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
end;

procedure TTyCustomRichEdit.CommitComposition(const AText: string);
var
  s: UTF8String;
  was, late: Boolean;
  p: Integer;
  fmt: TTyCharFormatId;
  t: TTyRichText;
  ua, uc, st, len0, delta, removed, n: TTyRichPos;

  // a position of before the commit, where it is after it
  function Mapped(APos: TTyRichPos): TTyRichPos;
  begin
    if APos < st then Result := APos
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
      if (FSelAnchor <> FCompAnchor) or (FCaret <> FCompPos) then
        Select(FCompAnchor, FCompPos, False);
      fmt := FCompFormat;
    end;
    st := GetSelStart;
    len0 := t.Length;
    n := UTF8Length(s);
    { The one routine of typing (TypeText): the same refusals (a cell's edge, the paragraph
      kept before a table, a cut paragraph's cut) and the same command. Deliberately merged
      as typing: the memo commits as typing (uskTyping), which merges with the typing next to
      it - the engine merges mergeable inserts by their kind, so a commit, the typing before
      it and the typing after it are one undo step, as in the memo. A commit with a line
      break makes a paragraph: a step of its own, as Enter is. Over a selection: one
      composite, a fresh step (as typing over one). The caret behind it, counted. }
    TypeText(s, (Pos(#10, s) = 0) and (Pos(#11, s) = 0), True, fmt, n);
    if late and FEditHeard and (FDoc.Text = t) and not ViewBehind then
    begin
      // the selection the user made meanwhile (the press's) stays, moved with the text
      delta := t.Length - len0;
      removed := n - delta;
      Select(Mapped(ua), Mapped(uc), False);
      CaretMoved;
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
  DropComposition;
end;

procedure TTyCustomRichEdit.EndComposition(ACommit: Boolean);
begin
  // a cancel (a content reset, ReadOnly, disabled, the window going) drops an owed result too
  if not ACommit then FCompPending := False;
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
  typed, Ctrl+A), a press, the menu's actions - and paste (Task 10c), the format actions and
  table editing (Tasks 11, 12) must come in through it as well. A composition open in the text
  ends first, committed as a press commits it (what the input method has goes in where it was
  shown), so that the action works on the document the user sees: never on the text under a
  composition, nor a commit on a selection the action made (Ctrl+A, then a commit replacing
  everything). Copying, moving the caret, scrolling and zooming do not end it. }
procedure TTyCustomRichEdit.EndCompositionForUser;
begin
  if FComposing or FImeRefused then EndComposition(True);
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
  // read-only: the system's composition window, its text dropped as typing is (batch B's)
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
    never the wrap width itself - text that wraps to the window fits it at any zoom (K-2). A
    page wider than the window scrolls over the page's width. }
  w := ALayout.Width;
  if (FWrapMode = rwmPage) and (ALayout.LayoutWidth <> CRichNoWrap) and
    (ALayout.LayoutWidth > w) then
    w := ALayout.LayoutWidth;
  if w > FWidestSeen then FWidestSeen := w;
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
  size, halfPt, w, est, k, rppi: Integer;
  z: Single;
  factor: Double;
  area: TRect;
  fontDiff: Boolean;
  style: TFontStyles;
begin
  if APPI <= 0 then APPI := 96;
  FViewPPI := APPI;
  s := CurrentStyle;
  size := ResolveFontSize(s);
  if TyFontSizeIsPx(size) then
    halfPt := Round(TyFontPxOf(size) * 72 / 96 * 2)
  else
    halfPt := size * 2;
  if halfPt < 1 then halfPt := 20;
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
        next layout builds the extent again from what it lays out, so it can shrink (K-2). }
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
    // start again from where the caret is now (S-M5)
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

procedure TTyCustomRichEdit.DocChanged(Sender: TObject; const AChange: TTyRichChange);
var
  was, wasAnchor: TTyRichPos;
  loadOwn: Boolean;
begin
  { The load's own change: one made while the step runs AND the document still loads. A
    slice is appended before the last step ends the loading; a command run from the last
    step's progress handler (the document no longer loads there) is an edit - for the
    layouter's trust, the caret and the anchor, and the change report alike (S-X1). The
    notice a cancelled load gives that it stopped comes after the load state ended, and is
    the load's own all the same: it changes no text of the file (K-6). }
  loadOwn := (FInStep and FDoc.Loading) or FInCancel;
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
  FLayouter.DocumentChanged(AChange, loadOwn);
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
      makes (FEditing) places the caret itself when the command has run (S-M9, FinishEdit):
      here the positions only follow the text by the same arithmetic - so that what the
      edit's Select repaints of an old selection is in the text as it is now - and are
      neither snapped nor reported. }
    if (rckText in AChange.Kinds) and not loadOwn then
    begin
      was := FCaret;
      wasAnchor := FSelAnchor;
      { A selection set inside the update was set on the text as it was then: the update's
        own change does not move it again (L-4); it is clamped to the final text. }
      if not FSelInUpdate then
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
    { A slice a turn appends: its change of the bars may wait (UpdateBars, P-1). The end of a
      load (Loading False there) and anything that is not a slice reach them at once. }
    FBarsLazy := loadOwn and FInTurn and FDoc.Loading;
    try
      ChangeInView(AChange);
    finally
      FBarsLazy := False;
    end;
    { A paint that came while the document held this change back showed nothing new and left
      the window painted: the change's own bands are not all it missed (with no block held
      they are nothing). The window is painted again, whole, once (K-11). }
    if FSkippedPaint then
    begin
      FSkippedPaint := False;
      InvalidateArea(Rect(0, 0, Width, Height));
    end;
  end;
  if (FLines <> nil) and (FDoc.Text.Length > 0) then FLines.FEmptyLine := False;
  // the slices a lazy load adds are its progress, not changes of the content
  if loadOwn then Exit;
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
  // (raised only when Updating is False; a content not heard of yet is DocChanged's)
  if ViewBehind then Exit;
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
  { K-11 for an update that ended with nothing to report (L-3): DocChanged made a skipped
    paint good when there was a change. }
  if FSkippedPaint then
  begin
    FSkippedPaint := False;
    InvalidateArea(Rect(0, 0, Width, Height));
  end;
end;

procedure TTyCustomRichEdit.ContentReplaced;
var
  composed: Boolean;
begin
  { A composition has no text to go into any more: it goes (the whole view is drawn again
    below), and the input method is told to drop it. }
  composed := FComposing or FImeRefused;
  // (Cocoa's session goes on: what it still has marked goes nowhere)
  if composed and FCocoaSession and (FInBridge = 0) then FCocoaSwallow := True;
  FComposing := False;
  FCompText := '';
  FImeRefused := False;
  FCompPending := False;
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
  // told, not recognised: the layouter empties everything it kept
  FLayouter.Document := FDoc;
  FAnchorPara := 0;
  FAnchorOffset := 0;
  FAnchorShareDen := 0;
  FScrollX := 0;
  FWidestSeen := 0;
  FViewValid := False;
  // a new content: the caret at its start, nothing selected
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
  InvalidateArea(Rect(0, 0, Width, Height));
  if FViewPPI > 0 then UpdateBars(False);
  if composed then ImeEndOnWidgetset(False);
end;

{ Held blocks the layouter dropped (a list's numbers after a change, F-M1's Stale) are laid
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
    view is laid out again from there (what was on screen is no longer the same blocks). }
  anchorMoved := False;
  if FAnchorPara > hiOld then
    Inc(FAnchorPara, delta)
  else if FAnchorPara > lo then
  begin
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
      nothing on screen changes - but numbers after it may have. }
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
      blocks are drawn again and what lies below them is moved (rule 10 of 10a: a keystroke
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
  CheckLayoutParams(ViewPPI);
  t := FDoc.Text;
  walked := nil;
  h := nil;
  nSeen := 0;
  if FAnchorShareDen > 0 then
  begin
    { A zoom (a PPI, a width) since the last layout: the anchor's offset is a share of its
      block until it is laid out again - at the new parameters, here, before the walk starts
      from it (H-M3's share, which the walk would otherwise drop). }
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
    hidden (it fits wider too). So it settles in at most three layouts (H-C1). }
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
  wantV, wantH: Boolean;
  page, viewH: Integer;
begin
  wantV := Decide((FDoc.Text.TotalHeight > FViewH) or (AnchorY > 0), FLatchV);
  wantH := Decide(FWidestSeen > FViewW, FLatchH);
  // the bars count client pixels
  total := FDoc.Text.TotalHeight div FScale;
  topY := AnchorY div FScale;
  viewH := FViewH div FScale;
  Result := (wantV <> VBarShown) or (wantH <> HBarShown);
  { A load's own slice (FBarsLazy) that brings no bar and takes none away: the widgets get its
    range at the end of a turn, at most once per CRichLoadBarsMs of the turns' clock
    (BackgroundTurn); CatchUpBars gives them the rest when the load ends, and any call of this
    that is not such a slice gives them everything at once. What the control works with - the
    document's height, the anchor, the clamps - is read from the document, never from a bar;
    FBarScale is the scale the vertical bar was last given, the one its positions are in
    (P-1). }
  if FBarsLazy and not Result then
  begin
    // the turn decides at its end (BackgroundTurn)
    FBarsBehind := True;
    // (the control's own value, as below)
    if wantH then ClampScrollX else FScrollX := 0;
    Exit;
  end;
  FBarsBehind := False;
  if wantV and (FVBar = nil) then FVBar := NewBar(Self, sbVertical, @VBarChange, FScrollBarAutoHide);
  if wantH and (FHBar = nil) then FHBar := NewBar(Self, sbHorizontal, @HBarChange, FScrollBarAutoHide);
  if FVBar <> nil then FVBar.Visible := wantV;
  if FHBar <> nil then FHBar.Visible := wantH;
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
    if wantV then
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
    if wantH then
    begin
      FHBar.Controller := Controller;
      ClampScrollX;
      FHBar.Min := 0;
      FHBar.Max := Math.Max(0, FWidestSeen - FViewW) div FScale;
      FHBar.PageSize := Math.Max(1, FViewW div FScale);
      FHBar.SmallChange := Math.Max(1, FEstimate div FScale);
      FHBar.Position := FScrollX div FScale;
    end
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
  MoveSurfaceText(was - FScrollX, 0);
  InvalidateArea(TextWindowRect);
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
  if OwnStyleColor('--surface-sunk', c) then AStyle.PlaceholderFill := TyColorToBGRA(c);
  if OwnStyleColor('--border', c) then AStyle.PlaceholderFrame := TyColorToBGRA(c);
  AStyle.TableBorder := AStyle.TextColor;
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
end;

{ ---- points and positions ---- }

{ One implementation of point -> position and position -> rectangle (S-M8): the control's own
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
  begin
    for i := 0 to L.LineCount - 1 do
    begin
      ln := L.Lines[i];
      for j := ln.FirstFrag to ln.FirstFrag + ln.FragCount - 1 do
      begin
        f := L.Fragments[j];
        if (f.Kind <> rfkObject) or not (f.Obj is TTyRichPicture) then Continue;
        AVisit(TTyRichPicture(f.Obj), Rect(AX + f.X, AY + ln.Baseline - f.Ascent,
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
  Result := (FPendingCount > 0) or (FDoc.Loading and (TyRichRtfLoadOf(FDoc) <> nil));
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
      { (K-4) A slice that indexed nothing would raise the same again, every turn: the load
        stops there. One that got further raised in a handler of its progress or its change
        (the load's state is whole: what was indexed is appended first): it goes on. }
      if (TyRichRtfLoadOf(FDoc) = load) and FDoc.Loading and (load.BytesIndexed = before) then
        CancelLoad;
      raise;
    end;
    FInStep := False;
    // the load's end: the bars get what its last turns held back (P-1)
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

{ The driver on (R49). rtdIdle: the idle handler registered; when it was not, the first turn
  is queued too, because a start from code the idle step itself runs after the handlers (an
  action's update, a later idle handler) would otherwise wait for the next message - this is
  a start, not a turn queuing the next: inside a turn nothing is queued. rtdTimer: the timer
  enabled (made on the first start). }
procedure TTyCustomRichEdit.StartBackground;
var
  first: Boolean;
begin
  // a turn only for a control on screen: one without a window waits for FinishLoading or
  // its first paint (InitializeWnd starts it)
  if not HandleAllocated or (csDestroying in ComponentState) or SchedulingClosed then Exit;
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
  it was read (Loading; FinishLoading reads the rest, a new window starts the driver again)
  (L-2). Anything else (in practice: out of memory) would leave the load Loading with nothing to
  drive it: it ends as a cancel ends it - Incomplete, with the load's own notice (N-5).
  That cancel is not run here: this is reached from the end of a paint, the tail of a layout
  pass (QueuePicturesAhead) and InitializeWnd, where the view must not hear a document notice.
  It is owed (FLoadEndOwed), and EndOwedLoad runs it at the next entry point of the loop: the
  idle step (rtdIdle: the handler is registered again for it - a registration is no queued
  call), a turn, a key or a mouse press; LoadAs and the idle step, which are such entry points
  themselves, run it before they return. It runs under no handler of ours: an exception from a
  user's change handler reaches the caller as from a user's own cancel (P-2). }
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

{ The bars get the range the load's turns held back (P-1). }
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
  // (the destructor frees the calls before the window goes)
  if (ACall = nil) or ACall.FQueued or (csDestroying in ComponentState) or SchedulingClosed then
    Exit;
  ACall.FQueued := True;
  try
    PostCall(ACall);
  except
    { Nothing was queued; the error does not travel on into a paint, a turn or a step (L-2). The
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
    // (P-2) its own driver stays on only for pictures left (CancelLoad's tail)
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
  // a call that could not be queued: the load ends now (P-2)
  EndOwedLoad;
end;

procedure TTyCustomRichEdit.TurnTimerTick(Sender: TObject);
begin
  BackgroundTurn;
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
  BackgroundTurn;
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
    DoSelectionChange;
end;

procedure TTyCustomRichEdit.BackgroundTurn;
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
    { The range the turn's slices held back reaches the bars, the turn's whole work at once,
      when none did for CRichLoadBarsMs (by the clock's last reading); the first turn of a load
      always (P-1). }
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
      strands (K-4). Nothing is queued from here (R49): still inside the turn, a start only
      registers the idle handler, and the next idle step queues the next turn. }
    try
      if HasBackgroundWork then StartBackground else StopBackground;
    finally
      FInTurn := False;
    end;
  end;
  // (P-2) the next turn could not be scheduled: the load ends here, out of the turn
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
  turns bring the size back (N-4). The band between the two thresholds is four times wide, so a
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
  FImeHook := TyImeInstall(Self, @HookCommit, @HookCaretRect);
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
end;

procedure TTyCustomRichEdit.LoadAs(AStream: TStream; AFormat: TTyRichFormat);
var
  load: TTyRtfLoad;
  prefix: TBytes;
begin
  CheckReplaceable;
  FCancelRequested := False;
  // a new file's turns start small and find their size (N-3); its first slice is not a turn
  FSlice := CRichLoadMinStepBytes;
  // its first turn's range reaches the bars at once (P-1); an end owed to the last is moot
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
  FLinesStored := False;
  FSourceFile := '';
  if HasBackgroundWork then StartBackground;
  // a first turn that could not be queued: the load ends before this returns (P-2)
  EndOwedLoad;
end;

procedure TTyCustomRichEdit.LoadFromStream(AStream: TStream; AFormat: TTyRichFormat);
begin
  if AFormat = rfAuto then AFormat := DetectFormat(AStream);
  LoadAs(AStream, AFormat);
end;

procedure TTyCustomRichEdit.LoadFromFile(const AFileName: string);
var
  fs: TFileStream;
begin
  CheckReplaceable;
  // the bytes are read to the end at once and nothing is kept: a writer elsewhere is no harm
  fs := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    LoadAs(fs, DetectFormat(fs));
  finally
    fs.Free;
  end;
  FSourceFile := ExpandFileName(AFileName);
end;

procedure TTyCustomRichEdit.SetPlainText(const AText: string);
var
  s: RawByteString;
  st: TBytesStream;
  n: Integer;
begin
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
  FSourceFormat := rfText;
  FSourceFile := '';
  FLinesStored := True;
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
  // (its notice reached them already when it changed a view: then this does nothing; P-1)
  CatchUpBars;
  if HasBackgroundWork then StartBackground else StopBackground;
end;

procedure TTyCustomRichEdit.WriteTo(AStream: TStream; AFormat: TTyRichFormat);
begin
  // a save asked for from a load progress handler would save a document still loading
  if FInStep then raise ETyRichEdit.Create(rsRichEditBusy);
  FinishLoading;
  if FDoc.Incomplete then raise ETyRichEdit.Create(rsRichEditIncomplete);
  if AFormat = rfAuto then AFormat := FSourceFormat;
  // a document of ours names the font its plain text is shown in (RtfWrite's \f0)
  FDoc.BaseFontName := TyEffectiveFontName(CurrentStyle.FontName);
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
begin
  full := RealTarget(ExpandFileName(AFileName));
  FinishLoading;
  if FDoc.Incomplete then raise ETyRichEdit.Create(rsRichEditIncomplete);
  if AFormat = rfAuto then
  begin
    ext := LowerCase(ExtractFileExt(full));
    if ext = '.rtf' then AFormat := rfRtf
    else if ext = '.txt' then AFormat := rfText
    else AFormat := FSourceFormat;
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
  // RTF keeps the content; text keeps a text document's: an RTF document saved as text is an export
  keeps := (AFormat = rfRtf) or (FSourceFormat = rfText);
  if keeps then
  begin
    FDoc.Modified := False;
    FSourceFile := full;
    FSourceFormat := AFormat;
  end;
end;

{ ---- the kept surface (R39) ----

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
  9a way instead - the painter's layer over the canvas, everything each paint. }

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
    moves what is inside this rectangle, the frame is drawn only outside it (H2-I3). What the
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

procedure TTyCustomRichEdit.MoveSurfaceText(ADX, ADY: Int64; AFrom: Int64);
var
  area, clip, R, d: TRect;
  kept: array[0..2 * CRichDirtyMax - 1] of TRect;
  s, y, w, i, n, dx, dy, lo, hi, first, row0: Integer;
  top64, lo64, hi64, first64: Int64;
  pix: PBGRAPixel;
begin
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
    h := (h xor AValue) * 16777619;
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
    bars, the PPI. Never the states themselves (H2-M2): a press that looks like the normal
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
    change, which the paint then does (A3-M2). }
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
  MixPx(ps.PlaceholderFill);
  MixPx(ps.PlaceholderFrame);
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
  inherited DestroyWnd;
  // the window is gone: what it showed is drawn again when it comes back, and the background
  // work waits for it (InitializeWnd starts it again) or for FinishLoading
  FreeAndNil(FSurface);
  InvalidateSurface;
  StopBackground;
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
begin
  // the block's part of the selection, block-relative (past its last place: its separator)
  a := 0;
  b := 0;
  if FCaret <> FSelAnchor then
  begin
    t := FDoc.Text;
    start := t.ParaStart(FBlocks[AIndex].FirstPara);
    stop := t.ParaStart(FBlocks[AIndex].LastPara) + t.ParaLength(FBlocks[AIndex].LastPara);
    a := Math.Max(GetSelStart - start, 0);
    b := Math.Min(GetSelStart + GetSelLength - start, stop - start + 1);
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
    the frame's) leaves everything to be drawn again by the next paint (H2-M3) - never stale
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
      { A block's ink may reach past its box (a descender, an italic, a picture frame): the
        blocks next to a region are painted into it too (clipped), as a full redraw would leave
        them. No block of today's layouts inks outside its box (A10: equivalent now); 9b's
        handles of a selected picture will, and this is what keeps them whole. }
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

{ The 9a way, for a ground that is not an opaque colour or an opacity: the painter's layer for
  the clip, frame and text, everything each paint, laid over the canvas by EndPaint (which
  dims and blends). At the device scale too. }
procedure TTyCustomRichEdit.PaintLayer(ACanvas: TCanvas; const ARect, AClip: TRect;
  APPI: Integer; ADefer: Boolean; const AScale: TTyCanvasScale);
var
  P: TTyPainter;
  R, area, textClip, rClip: TRect;
  st: TTyRichPaintStyle;
  s, k, x: Integer;
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
      P.Bitmap.ClipRect := rClip;
      FLayouter.BeginPaintPass;
      try
        x := area.Left * s - FScrollX;
        for k := 0 to FBlockCount - 1 do
        begin
          y := Int64(area.Top) * s + FBlocks[k].Top;
          if (y >= rClip.Bottom) or (y + FBlocks[k].Height <= rClip.Top) then Continue;
          PaintBlock(P.Bitmap, k, x, Integer(y), rClip, st);
          if ADefer then QueueSkipped(k);
        end;
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
    date. With no surface yet (or one of another scale) it shows nothing (S-M11). }
  if ViewBehind then
  begin
    // the window counts this paint as done: it is asked for again when the view hears (K-11)
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
    does to the view: no invalidation from inside it (H2-M6). A paint of a part, or RenderTo
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
  // a caret or an anchor a change moved: on a caret place before it is drawn (S-M10)
  if FSnapPending then SnapAfterChange;
  if not SurfaceUsable(CurrentStyle) then
  begin
    PaintLayer(ACanvas, ARect, clip, APPI, ADefer, sc);
    InvalidateSurface;
    { The kept frame signature is not this paint's: a state that leaves the layer path (a
      hover with an opacity ending) must paint again even when its look equals the one the
      surface was last drawn with (A3-M1). }
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

{ ---- keyboard and wheel ---- }

procedure TTyCustomRichEdit.KeyDown(var Key: Word; Shift: TShiftState);
var
  ext, byWord, toDoc: Boolean;
  q: TTyRichPos;
begin
  inherited KeyDown(Key, Shift);
  // a user action is an entry point of the loop (P-2: see SchedulingFailed)
  EndOwedLoad;
  if (Key = 0) or not IsEnabled then Exit;
  { Inside the document's update a key that moves or copies does nothing: the view does not
    know the text yet (K-9). The viewer's keys are still taken - they never go on to the form. }
  if ViewBehind then
  begin
    if (Key in [VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN, VK_HOME, VK_END, VK_PRIOR, VK_NEXT]) or
      (TyIsShortcutShift(Shift) and (Key in [VK_A, VK_C, VK_V])) or
      ((Key = VK_INSERT) and ((Shift = [ssCtrl]) or (Shift = [ssShift]))) or
      IsEditKey(Key, Shift) then
      Key := 0;
    Exit;
  end;
  ext := ssShift in Shift;
  // Ctrl a word (Option on a Mac, as its text views); Ctrl or Cmd the document's ends
  byWord := (ssCtrl in Shift) {$IFDEF DARWIN}or (ssAlt in Shift){$ENDIF};
  toDoc := (ssCtrl in Shift) or (ssMeta in Shift);
  { A key an input method lets through while composing that edits or selects all: the
    composition goes in first (EndCompositionForUser, the one door) - never the action under
    it, nor the commit over what Ctrl+A selected. }
  if TyIsShortcutShift(Shift) and (Key = VK_A) then
  begin
    EndCompositionForUser;
    SelectAll;
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
          // onto the caret itself: it stays where it is drawn, at a line's end too (S-M4)
          if q = FCaret then Select(q, q, FCaretAtEnd) else Select(q, q, False);
        end
        else
        begin
          if byWord then q := WordStep(FCaret, Key = VK_RIGHT)
          else q := CaretStep(FCaret, Key = VK_RIGHT);
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

function TTyCustomRichEdit.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  notches, perNotch: Integer;
begin
  if not IsEnabled then Exit(False);
  if inherited DoMouseWheel(Shift, WheelDelta, MousePos) then Exit(True);
  Result := True;
  // inside the document's update: taken, nothing done (K-9)
  if ViewBehind then Exit;
  if ssCtrl in Shift then
  begin
    // Ctrl + wheel zooms, a notch at a time
    Inc(FZoomWheelRest, WheelDelta);
    notches := FZoomWheelRest div 120;
    Dec(FZoomWheelRest, notches * 120);
    if notches <> 0 then Zoom := FZoom + notches * CRichZoomStep;
    Exit;
  end;
  Inc(FWheelRest, WheelDelta);
  notches := FWheelRest div 120;
  Dec(FWheelRest, notches * 120);
  if notches = 0 then Exit;
  perNotch := Mouse.WheelScrollLines;
  if perNotch <= 0 then
    ScrollRasterBy(-notches * Int64(Math.Max(FEstimate, FViewH - FEstimate)))
  else
    ScrollRasterBy(-notches * Int64(perNotch) * Math.Max(1, FEstimate));
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
  Inc(FWheelHRest, WheelDelta);
  notches := FWheelHRest div 120;
  Dec(FWheelHRest, notches * 120);
  if notches = 0 then Exit;
  was := FScrollX;
  FScrollX := FScrollX + notches * 3 * Math.Max(1, FEstimate);
  ClampScrollX;
  if FScrollX = was then Exit;
  // a range a load's turns held back first: the position is in the range the bar has (P-1)
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

procedure TTyCustomRichEdit.MouseEnter;
begin
  inherited MouseEnter;
  if FVBar <> nil then FVBar.SetHostHovered(True);
  if FHBar <> nil then FHBar.SetHostHovered(True);
end;

procedure TTyCustomRichEdit.MouseLeave;
begin
  { Where the pointer comes back in is not known: the arrow is not answered over the text
    until a move over the padding says so again (L-5). }
  FOverPadding := False;
  inherited MouseLeave;
  if FVBar <> nil then FVBar.SetHostHovered(False);
  if FHBar <> nil then FHBar.SetHostHovered(False);
end;

initialization
  {$IFDEF MSWINDOWS}
  TyRichReplaceFileW := @ReplaceFileW;
  {$ENDIF}
  TyTryRegisterTypeKeyParent('TyRichEdit', 'TyMemo');

finalization
  TyUnregisterTypeKeyParent('TyRichEdit');

end.
