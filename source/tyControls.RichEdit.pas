unit tyControls.RichEdit;

{ TTyRichEdit: a rich text viewer and (from Task 10 on) editor, drawn by the package itself on
  every platform. This first form shows a document - txt or RTF, of any size - and scrolls,
  zooms and wraps it; it is read-only to the user (ReadOnly is True and stays so for now), while
  code may change the document through its commands (Document.Execute) and Lines.

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
    an RTF file is indexed in slices (TTyRtfLoad.Step) from a timer, a few milliseconds a turn,
    the document readable meanwhile (Loading); FinishLoading runs the rest at once. Pictures are
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
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.StyleModel, tyControls.Painter, tyControls.Base,
  tyControls.ScrollBar,
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
  { The background work (load slices, pictures) a timer turn does at most, in milliseconds. }
  CRichIdleBudgetMs = 8;
  { ... and at most this many pieces of it (load slices, pictures): a cap that holds whatever
    the clock's resolution is. }
  CRichIdleMaxSteps = 3;
  { One load slice: bytes of RTF indexed per step. }
  CRichLoadStepBytes = 256 * 1024;
  { FinishLoading's slice: the progress event fires and a cancel acts every this many bytes. }
  CRichFinishStepBytes = 4 * 1024 * 1024;
  { The kept surface is made in blocks of this many raster pixels: a resize does not make it
    again at every pixel. }
  CRichSurfaceBlock = 64;
  { The most rectangles the surface keeps as dirty; more are merged (see MarkDirty). }
  CRichDirtyMax = 8;

type
  ETyRichEdit = class(Exception);

  { What a stream holds: rfAuto finds out (RTF when it starts with the RTF signature, after an
    optional UTF-8 BOM and white space; anything else is text). RTF, found or named, may have
    such bytes before its signature: they are kept and saved back in front of it. }
  TTyRichFormat = (rfAuto, rfRtf, rfText);

  { Loading: bytes of the file indexed; saving: paragraphs written. ACancel True stops it. }
  TTyRichProgressEvent = procedure(Sender: TObject; ADone, ATotal: Int64;
    var ACancel: Boolean) of object;

  TTyCustomRichEdit = class;

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

  TTyCustomRichEdit = class(TTyCustomControl, ITyScrollBarFrameHost)
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
    FTimer: TTimer;
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
    // events
    FOnChange: TNotifyEvent;
    FOnZoomChange: TNotifyEvent;
    FOnLoadProgress: TTyRichProgressEvent;
    FOnSaveProgress: TTyRichProgressEvent;
    procedure DocChanged(Sender: TObject; const AChange: TTyRichChange);
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
    procedure InvalidateBand(ATop, ABottom: Int64);
    function TextWindowRect: TRect;
    procedure MarkDirty(const ARect: TRect);
    procedure MarkTextDirty;
    procedure MoveSurfaceText(ADX, ADY: Int64);
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
      there was nothing to do. What the timer runs, a few milliseconds a turn. }
    function StepBackground: Boolean;
    function HasBackgroundWork: Boolean;
    { One turn of the timer: pieces of the background work until CRichIdleMaxSteps of them or
      CRichIdleBudgetMs by IdleTicks, whichever comes first. }
    procedure TimerTick(Sender: TObject);
    { The clock a timer turn is measured by, in milliseconds (GetTickCount64; a test seam). }
    function IdleTicks: QWord; virtual;
    { The background work's timer: made when there is work and a window, gone with the
      window. }
    property BackgroundTimer: TTimer read FTimer;
    { A press, a release, a hover or the focus changed: the control is painted again only
      when what its frame looks like changed (FrameSignature); the text is not touched. }
    procedure PointerStateChanged; override;
    procedure Paint; override;
    procedure Resize; override;
    procedure InitializeWnd; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
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

      The document position at client point (X, Y) of the view, through the visible blocks: the
      nearest caret place of the block under Y (the first or last visible one above or below
      them). -1 when nothing is laid out. }
    function PositionAtPoint(X, Y: Integer): TTyRichPos;
    { The caret rectangle of document position APos in client pixels; an empty rectangle when
      APos is in no visible block. }
    function PositionRect(APos: TTyRichPos): TRect;
    { The client rectangle of the visible block paragraph AIndex is in (as wide as the text
      area); empty when it is not laid out in the view. }
    function ParagraphRect(AIndex: Integer): TRect;
    function VisibleBlockCount: Integer;
    { Top and Height are client pixels (from the text area's top), rounded outward: above
      device scale 1 two neighbouring blocks may overlap by a pixel. Everything read off
      Layout is in raster pixels - client pixels times DeviceScale. }
    property VisibleBlocks[AIndex: Integer]: TTyRichViewBlock read GetVisibleBlock;
    property Document: TTyRichDocument read FDoc;
    property Layouter: TTyRichLayouter read FLayouter;
    { The view's top in pixels of the document's heights (measured and estimated). }
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
    { Fixed at True in this version: the user cannot change the text; code can (Document,
      Lines). Setting False is ignored. }
    property ReadOnly: Boolean read FReadOnly write SetReadOnly default True;
    property Lines: TStrings read GetLines write SetLines stored IsLinesStored;
    { A txt file is read in this encoding (teAuto: found out) and, for teAnsi, code page. }
    property TextEncoding: TTyTextEncoding read FTextEncoding write FTextEncoding default teAuto;
    property TextCodePage: Integer read FTextCodePage write FTextCodePage default 0;
    property ScrollBarAutoHide: TTyScrollBarAutoHide read FScrollBarAutoHide
      write SetScrollBarAutoHide default sbahDefault;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnZoomChange: TNotifyEvent read FOnZoomChange write FOnZoomChange;
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
    property TextEncoding;
    property TextCodePage;
    property ScrollBarAutoHide;
    property OnChange;
    property OnZoomChange;
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

implementation

uses
  {$IFDEF UNIX}BaseUnix,{$ENDIF}
  RTLConsts, tyControls.StrConsts, tyControls.FontUnits, tyControls.PlatformWS;

{$IFDEF MSWINDOWS}
const
  MOVEFILE_REPLACE_EXISTING = 1;
  MOVEFILE_WRITE_THROUGH = 8;

// kernel32 itself: the Windows unit's RECT type would hide Types.Rect in this unit
function MoveFileExW(AExisting, ANew: PWideChar; AFlags: DWord): LongBool; stdcall;
  external 'kernel32' name 'MoveFileExW';
{$ENDIF}

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
  d.BeginUpdate;
  try
    if len > 0 then Run(TTyRichDelete.Create(start, len));
    if S <> '' then Run(TTyRichInsertText.Create(start, S, TyRichInheritFormat, False));
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
  FReadOnly := True;
  FTextEncoding := teAuto;
  FTextCodePage := 0;
  FScrollBarAutoHide := sbahDefault;
  FSourceFormat := rfRtf;
  FFirstSliceBytes := CRtfFirstSliceBytes;
  FStepBytes := CRichLoadStepBytes;
  FBarScale := 1;
  FScale := 1;
  FSurfScale := 1;
  FLayoutPPI := 0;
  FViewPPI := 0;
  FDoc := CreateDocument;
  FText := FDoc.Text;
  FDoc.OnChange := @DocChanged;
  FLayouter := CreateLayouter;
  FLayouter.Document := FDoc;
  // the layouter empties its caches when the list changes; the view must drop its blocks too
  FFallbackListChange := FLayouter.FallbackFonts.OnChange;
  FLayouter.FallbackFonts.OnChange := @FallbackListChanged;
  FLines := TTyRichEditLines.Create(Self);
  Cursor := crIBeam;
  AccessibleRole := larTextEditorMultiline;
  Width := 320;
  Height := 240;
end;

destructor TTyCustomRichEdit.Destroy;
begin
  StopBackground;
  FreeAndNil(FTimer);
  ReleaseBlocks;
  ClearPending;
  ClearFailed;
  FreeAndNil(FSurface);
  if FDoc <> nil then FDoc.OnChange := nil;
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
  { Editing comes with Task 10: until then the user interface stays read-only. Code changes
    the document through Document.Execute and Lines either way. }
  if AValue then FReadOnly := True;
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
  Settle;
  if (AIndex < 0) or (AIndex >= FBlockCount) then
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
  if FViewValid then Exit;
  EnsureView(ViewPPI);
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
  w := ALayout.Width;
  // a page narrower or wider than the window scrolls over the page's width
  if (ALayout.LayoutWidth <> CRichNoWrap) and (ALayout.LayoutWidth > w) then
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

procedure TTyCustomRichEdit.CheckLayoutParams(APPI: Integer);
var
  s: TTyStyleSet;
  size, halfPt, w, est, k, rppi: Integer;
  z: Single;
  factor: Double;
  area: TRect;
  fontDiff: Boolean;
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
  fontDiff := (s.FontName <> FLayoutFont) or (halfPt <> FLayoutFontSize);
  if fontDiff then
  begin
    FLayoutFont := s.FontName;
    FLayoutFontSize := halfPt;
    // either setter empties the layouter's caches when it changes something
    FLayouter.BaseFontName := s.FontName;
    FLayouter.BaseFontSizeHalfPt := halfPt;
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
        extent (the extent seen is scaled the same way until blocks are laid out again). }
      FLayouter.ClearLayouts;
      factor := (z * rppi) / (FLayoutZoom * FLayoutPPI);
      FScrollX := Round(FScrollX * factor);
      FWidestSeen := Round(FWidestSeen * factor);
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

procedure TTyCustomRichEdit.DocChanged(Sender: TObject; const AChange: TTyRichChange);
begin
  FLayouter.DocumentChanged(AChange, FInStep);
  if FDoc.Text <> FText then
    ContentReplaced
  else
    ChangeInView(AChange);
  if (FLines <> nil) and (FDoc.Text.Length > 0) then FLines.FEmptyLine := False;
  // the slices a lazy load adds are its progress, not changes of the content
  if not FInStep then DoChange;
end;

procedure TTyCustomRichEdit.ContentReplaced;
begin
  FText := FDoc.Text;
  ReleaseBlocks;
  ClearPending;
  ClearFailed;
  // told, not recognised: the layouter empties everything it kept
  FLayouter.Document := FDoc;
  FAnchorPara := 0;
  FAnchorOffset := 0;
  FAnchorShareDen := 0;
  FScrollX := 0;
  FWidestSeen := 0;
  FViewValid := False;
  if FLines <> nil then FLines.FEmptyLine := False;
  // the new text has no heights: it gets the estimate before anything asks
  if FEstimate > 0 then FDoc.Text.DefaultParaHeight := FEstimate;
  // everything: the text, and the frame (a bar may come or go with the new content)
  InvalidateSurface;
  InvalidateArea(Rect(0, 0, Width, Height));
  if FViewPPI > 0 then UpdateBars(False);
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
    // the blocks below moved: from the change down; the next pass fills what the move left
    InvalidateBand(oldTop, FViewH);
    FViewValid := False;
  end;
  RelayStale;
  UpdateBars(False);
end;

{ ---- scrolling ---- }

function TTyCustomRichEdit.GetScrollY: Int64;
begin
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
  if ADeltaY = 0 then Exit;
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
  { #225: the parts are resolved from the theme; a '--' token the control's own StyleOverride
    sets for what their rules read reaches them too. }
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

function TTyCustomRichEdit.PositionAtPoint(X, Y: Integer): TTyRichPos;
var
  area: TRect;
  k: Integer;
  vy, by: Int64;
begin
  Settle;
  Result := -1;
  if FBlockCount = 0 then Exit;
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  vy := (Int64(Y) - area.Top) * FScale;
  k := 0;
  while (k < FBlockCount - 1) and (vy >= FBlocks[k].Top + FBlocks[k].Height) do Inc(k);
  // inside the block (or just outside it): within its height, an Integer
  by := Math.Max(Int64(-1), Math.Min(vy - FBlocks[k].Top, Int64(FBlocks[k].Height)));
  Result := FDoc.Text.ParaStart(FBlocks[k].FirstPara) +
    FBlocks[k].Layout.PosAtPoint((X - area.Left) * FScale + FScrollX, Integer(by));
end;

function TTyCustomRichEdit.PositionRect(APos: TTyRichPos): TRect;
var
  area: TRect;
  k: Integer;
  start, stop: TTyRichPos;
  t: TTyRichText;
  r: TRect;
begin
  Settle;
  Result := Rect(0, 0, 0, 0);
  t := FDoc.Text;
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  for k := 0 to FBlockCount - 1 do
  begin
    start := t.ParaStart(FBlocks[k].FirstPara);
    stop := t.ParaStart(FBlocks[k].LastPara) + t.ParaLength(FBlocks[k].LastPara);
    if (APos >= start) and (APos <= stop) then
    begin
      r := FBlocks[k].Layout.CaretRect(APos - start);
      Result := ClientOf(area, r.Left - FScrollX, FBlocks[k].Top + r.Top, r.Right - FScrollX,
        FBlocks[k].Top + r.Bottom);
      Exit;
    end;
  end;
end;

function TTyCustomRichEdit.ParagraphRect(AIndex: Integer): TRect;
var
  area: TRect;
  k: Integer;
begin
  Settle;
  Result := Rect(0, 0, 0, 0);
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
begin
  Result := False;
  // re-entered from a progress handler (one that pumps messages): the step is running
  if FInStep or (FSaving > 0) then Exit;
  load := TyRichRtfLoadOf(FDoc);
  if FDoc.Loading and (load <> nil) then
  begin
    load.OnLoadProgress := @LoadProgress;
    FInStep := True;
    try
      load.Step(FStepBytes);
    finally
      FInStep := False;
    end;
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

procedure TTyCustomRichEdit.StartBackground;
begin
  // a timer only for a control on screen: one without a window waits for FinishLoading or
  // its first paint
  if not HandleAllocated then Exit;
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(nil);
    FTimer.Interval := 1;
    FTimer.OnTimer := @TimerTick;
  end;
  FTimer.Enabled := True;
end;

procedure TTyCustomRichEdit.StopBackground;
begin
  if FTimer <> nil then FTimer.Enabled := False;
end;

procedure TTyCustomRichEdit.TimerTick(Sender: TObject);
var
  t0: QWord;
  n: Integer;
begin
  if FInStep or (FSaving > 0) then Exit;
  { The clock (GetTickCount64) may advance in 15.6 ms steps (Windows' default): it only ends a
    turn early. What holds a turn near CRichIdleBudgetMs whatever the clock is the cap on its
    pieces: CRichIdleMaxSteps load slices or pictures. }
  t0 := IdleTicks;
  n := 0;
  repeat
    if not StepBackground then Break;
    Inc(n);
  until (n >= CRichIdleMaxSteps) or (IdleTicks - t0 >= CRichIdleBudgetMs);
  if not HasBackgroundWork then StopBackground;
end;

function TTyCustomRichEdit.IdleTicks: QWord;
begin
  Result := GetTickCount64;
end;

procedure TTyCustomRichEdit.InitializeWnd;
begin
  inherited InitializeWnd;
  if HasBackgroundWork then StartBackground;
end;

{ ---- loading and saving ---- }

procedure TTyCustomRichEdit.LoadProgress(Sender: TObject; ADone, ATotal: Int64);
var
  cancel: Boolean;
begin
  cancel := False;
  if Assigned(FOnLoadProgress) then FOnLoadProgress(Self, ADone, ATotal, cancel);
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
  if not HasBackgroundWork then StopBackground;
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
  try
    load.Cancel;
  finally
    FInStep := False;
  end;
  if not HasBackgroundWork then StopBackground;
end;

procedure TTyCustomRichEdit.WriteTo(AStream: TStream; AFormat: TTyRichFormat);
begin
  // a save asked for from a load progress handler would save a document still loading
  if FInStep then raise ETyRichEdit.Create(rsRichEditBusy);
  FinishLoading;
  if FDoc.Incomplete then raise ETyRichEdit.Create(rsRichEditIncomplete);
  if AFormat = rfAuto then AFormat := FSourceFormat;
  Inc(FSaving);
  try
    if AFormat = rfText then
      TyRichSaveText(FDoc, AStream)
    else
    begin
      // the file's own first bytes, before the signature, as they came
      if Length(FRtfPrefix) > 0 then AStream.WriteBuffer(FRtfPrefix[0], Length(FRtfPrefix));
      TyRichSaveRtf(FDoc, AStream, @SaveProgress);
    end;
  finally
    Dec(FSaving);
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
    Result := ReplaceFileW(PWideChar(UnicodeString(ATarget)), PWideChar(UnicodeString(ASource)),
      nil, REPLACEFILE_IGNORE_MERGE_ERRORS, nil, nil);
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
  MarkDirty(Rect(Integer(area.Left * s + AL), Integer(area.Top * s + AT),
    Integer(area.Left * s + AR), Integer(area.Top * s + AB)));
  r := ClientOf(area, AL, AT, AR, AB);
  InvalidateArea(r);
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

{ The text on the surface moved by ADX, ADY raster pixels (the content goes right / down for
  positive values): its rows or columns are moved inside the text clip and only the band it
  exposed is dirty. }
procedure TTyCustomRichEdit.MoveSurfaceText(ADX, ADY: Int64);
var
  area, clip, R: TRect;
  s, y, w, i: Integer;
  dx, dy: Integer;
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
  if ((ADX <> 0) and (ADY <> 0)) or (Abs(ADY) >= R.Bottom - R.Top) or
    (Abs(ADX) >= R.Right - R.Left) then
  begin
    MarkDirty(R);
    Exit;
  end;
  dx := Integer(ADX);
  dy := Integer(ADY);
  w := R.Right - R.Left;
  if dy > 0 then
  begin
    // down: from the bottom up, each row from dy above it
    for y := R.Bottom - 1 downto R.Top + dy do
      Move((FSurface.ScanLine[y - dy] + R.Left)^, (FSurface.ScanLine[y] + R.Left)^,
        w * SizeOf(TBGRAPixel));
  end
  else if dy < 0 then
  begin
    for y := R.Top to R.Bottom - 1 + dy do
      Move((FSurface.ScanLine[y - dy] + R.Left)^, (FSurface.ScanLine[y] + R.Left)^,
        w * SizeOf(TBGRAPixel));
  end
  else if dx <> 0 then
    for y := R.Top to R.Bottom - 1 do
    begin
      pix := FSurface.ScanLine[y] + R.Left;
      // Move copies overlapping ranges as memmove does
      if dx > 0 then Move(pix^, (pix + dx)^, (w - dx) * SizeOf(TBGRAPixel))
      else Move((pix - dx)^, pix^, (w + dx) * SizeOf(TBGRAPixel));
    end;
  FSurface.InvalidateBitmap;
  // what was dirty moved with the text
  for i := 0 to FDirtyCount - 1 do
  begin
    Types.OffsetRect(FDirty[i], dx, dy);
    if not IntersectRect(FDirty[i], FDirty[i], R) then FDirty[i] := Rect(0, 0, 0, 0);
  end;
  FSurfScrollX := FScrollX;
  if dy > 0 then MarkDirty(Rect(R.Left, R.Top, R.Right, R.Top + dy))
  else if dy < 0 then MarkDirty(Rect(R.Left, R.Bottom + dy, R.Right, R.Bottom))
  else if dx > 0 then MarkDirty(Rect(R.Left, R.Top, R.Left + dx, R.Bottom))
  else if dx < 0 then MarkDirty(Rect(R.Right + dx, R.Top, R.Right, R.Bottom));
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
  inherited DestroyWnd;
  // the window is gone: what it showed is drawn again when it comes back, and the background
  // work waits for it (InitializeWnd starts it again) or for FinishLoading
  FreeAndNil(FSurface);
  InvalidateSurface;
  FreeAndNil(FTimer);
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
begin
  FBlocks[AIndex].Layout.Paint(ABitmap, AX, AY, AClip, AStyle, 0, 0);
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
  if not SurfaceUsable(CurrentStyle) then
  begin
    PaintLayer(ACanvas, ARect, clip, APPI, ADefer, sc);
    InvalidateSurface;
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
  page: Integer;
begin
  inherited KeyDown(Key, Shift);
  if (Key = 0) or not IsEnabled then Exit;
  page := Math.Max(FEstimate, FViewH - FEstimate);
  case Key of
    VK_NEXT:
      begin
        ScrollRasterBy(page);
        Key := 0;
      end;
    VK_PRIOR:
      begin
        ScrollRasterBy(-page);
        Key := 0;
      end;
    VK_HOME:
      if ssCtrl in Shift then
      begin
        ScrollToTop;
        Key := 0;
      end;
    VK_END:
      if ssCtrl in Shift then
      begin
        ScrollToEnd;
        Key := 0;
      end;
  end;
end;

function TTyCustomRichEdit.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  notches, perNotch: Integer;
begin
  if not IsEnabled then Exit(False);
  if inherited DoMouseWheel(Shift, WheelDelta, MousePos) then Exit(True);
  Result := True;
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
  Inc(FWheelHRest, WheelDelta);
  notches := FWheelHRest div 120;
  Dec(FWheelHRest, notches * 120);
  if notches = 0 then Exit;
  was := FScrollX;
  FScrollX := FScrollX + notches * 3 * Math.Max(1, FEstimate);
  ClampScrollX;
  if FScrollX = was then Exit;
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
  inherited MouseLeave;
  if FVBar <> nil then FVBar.SetHostHovered(False);
  if FHBar <> nil then FHBar.SetHostHovered(False);
end;

initialization
  TyTryRegisterTypeKeyParent('TyRichEdit', 'TyMemo');

finalization
  TyUnregisterTypeKeyParent('TyRichEdit');

end.
