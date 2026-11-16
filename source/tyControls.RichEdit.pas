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
    InvalidateContent is the one place every invalidation goes through (a test records them
    there). A paint draws only the blocks that meet its clip rectangle, on the painter's bitmap
    for that rectangle.
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

type
  ETyRichEdit = class(Exception);

  { What a stream holds: rfAuto finds out (RTF when it starts with the RTF signature, after an
    optional UTF-8 BOM and white space; anything else is text). }
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
    { BeginUpdate .. EndUpdate bracket the document's (AddStrings is one undo step); around a
      Clear (what Assign and a form file do) the lines gather here and become the content
      once, at the end. }
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
    FScrollX: Integer;
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
    { The (picture, size) pairs made ready lately, with a reference each: never queued again
      (a picture the layouter cannot make ready at a size would otherwise come back every
      paint, H-I7). }
    FPrepared: array of TTyRichPendingPicture;
    FPreparedCount: Integer;
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
    procedure ClearPrepared;
    procedure AddBlock(var AList: array of TTyRichViewBlock; var ACount: Integer;
      ALayout: TTyBlockLayout; ATop: Int64);
    procedure WriteHeights(AFrom, ATo: Integer);
    procedure NoteExtent(ALayout: TTyBlockLayout);
    procedure QueuePicturesAhead;
    procedure QueuePicture(APicture: TTyRichPicture; AWidth, AHeight, APara, ALastPara: Integer;
      AHeld: Boolean);
    function WasPrepared(APicture: TTyRichPicture; AWidth, AHeight: Integer): Boolean;
    procedure NotePrepared(APicture: TTyRichPicture; AWidth, AHeight: Integer);
    procedure InvalidatePicture(APicture: TTyRichPicture; AWidth, AHeight: Integer);
    procedure LayoutParamsChanged;
    procedure FallbackListChanged(Sender: TObject);
    procedure CheckReplaceable;
    { The view's top in pixels of the heights, as the anchor says (no settling). }
    function AnchorY: Int64;
    { Lays the view out if something left it invalid: what the queries call first. }
    procedure Settle;
    { Rectangles handed to LCL: a block's top may be far outside an Integer's range. }
    function ViewRect(ALeft: Integer; ATop, ABottom: Int64; ARight: Integer): TRect;
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
    procedure TimerTick(Sender: TObject);
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
    { Every invalidation of the control's text goes through here (client pixels). }
    procedure InvalidateContent(const ARect: TRect); virtual;
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
    { What the stream holds, by its first bytes (the position is left where the RTF signature
      starts, or where it was). }
    function DetectFormat(AStream: TStream): TTyRichFormat;
    { One piece of the background work: a load slice, else one picture made ready. False when
      there was nothing to do. What the timer runs, a few milliseconds a turn. }
    function StepBackground: Boolean;
    function HasBackgroundWork: Boolean;
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
    property VisibleBlocks[AIndex: Integer]: TTyRichViewBlock read GetVisibleBlock;
    property Document: TTyRichDocument read FDoc;
    property Layouter: TTyRichLayouter read FLayouter;
    { The view's top in pixels of the document's heights (measured and estimated). }
    property ScrollY: Int64 read GetScrollY write SetScrollY;
    property ScrollX: Integer read FScrollX;
    { The widest block laid out so far: the horizontal extent (never measured over the
      document). }
    property HorizontalExtent: Integer read FWidestSeen;
    { The block at the view's top, and how many of its pixels are above the view. }
    property TopParagraph: Integer read FAnchorPara;
    property TopOffset: Int64 read FAnchorOffset;
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
  RTLConsts, tyControls.StrConsts, tyControls.FontUnits;

{$IFDEF MSWINDOWS}
const
  MOVEFILE_REPLACE_EXISTING = 1;
  MOVEFILE_WRITE_THROUGH = 8;

// kernel32 itself: the Windows unit's RECT type would hide Types.Rect in this unit
function MoveFileExW(AExisting, ANew: PWideChar; AFlags: DWord): LongBool; stdcall;
  external 'kernel32' name 'MoveFileExW';
{$ENDIF}

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
  ClearPrepared;
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
  ViewMoved;
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

procedure TTyCustomRichEdit.ClearPrepared;
var
  i: Integer;
begin
  for i := 0 to FPreparedCount - 1 do FPrepared[i].Picture.Release;
  FPrepared := nil;
  FPreparedCount := 0;
end;

function TTyCustomRichEdit.WasPrepared(APicture: TTyRichPicture; AWidth, AHeight: Integer): Boolean;
var
  i: Integer;
begin
  for i := 0 to FPreparedCount - 1 do
    if (FPrepared[i].Picture = APicture) and (FPrepared[i].Width = AWidth) and
      (FPrepared[i].Height = AHeight) then Exit(True);
  Result := False;
end;

const
  { How many prepared (picture, size) pairs the control remembers; the oldest goes first. }
  CRichPreparedKept = 64;

procedure TTyCustomRichEdit.NotePrepared(APicture: TTyRichPicture; AWidth, AHeight: Integer);
begin
  if WasPrepared(APicture, AWidth, AHeight) then Exit;
  if FPreparedCount = CRichPreparedKept then
  begin
    FPrepared[0].Picture.Release;
    Move(FPrepared[1], FPrepared[0], (FPreparedCount - 1) * SizeOf(FPrepared[0]));
    Dec(FPreparedCount);
  end;
  if FPreparedCount = Length(FPrepared) then SetLength(FPrepared, FPreparedCount * 2 + 8);
  APicture.AddRef;
  FPrepared[FPreparedCount].Picture := APicture;
  FPrepared[FPreparedCount].Width := AWidth;
  FPrepared[FPreparedCount].Height := AHeight;
  Inc(FPreparedCount);
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

function TTyCustomRichEdit.ViewRect(ALeft: Integer; ATop, ABottom: Int64; ARight: Integer): TRect;
const
  Lim = MaxInt div 2;
begin
  if ATop < -Lim then ATop := -Lim;
  if ATop > Lim then ATop := Lim;
  if ABottom < -Lim then ABottom := -Lim;
  if ABottom > Lim then ABottom := Lim;
  Result := Rect(ALeft, Integer(ATop), ARight, Integer(ABottom));
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
  size, halfPt, w, est, k: Integer;
  z: Single;
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
  area := TextArea(Rect(0, 0, Width, Height), APPI);
  FViewW := Math.Max(0, area.Right - area.Left);
  FViewH := Math.Max(0, area.Bottom - area.Top);
  z := FZoom / 100;
  w := TyRichLayoutWidth(FWrapMode, Math.Max(1, FViewW), FDoc, APPI, z);
  est := FLayouter.EstimatedParaHeight(APPI, z);
  if est < 1 then est := 1;
  if fontDiff or (w <> FLayoutWidth) or (APPI <> FLayoutPPI) or (z <> FLayoutZoom) or
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
    if (APPI <> FLayoutPPI) or (z <> FLayoutZoom) then FLayouter.Clear;
    if FLayoutPPI <> 0 then FDoc.Text.UnmeasureAll;
    ReleaseBlocks;
    FLayoutWidth := w;
    FLayoutPPI := APPI;
    FLayoutZoom := z;
    FEstimate := est;
    FWidestSeen := 0;
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
      if FAnchorShareDen > 0 then
      begin
        FAnchorOffset := FAnchorShareNum * b.Height div FAnchorShareDen;
        FAnchorShareDen := 0;
      end;
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
  if FViewShifted then
    InvalidateContent(TextArea(Rect(0, 0, Width, Height), ViewPPI));
  WriteHeights(0, FBlockCount - 1);
  QueuePicturesAhead;
end;

{ ---- the document changed ---- }

procedure TTyCustomRichEdit.DocChanged(Sender: TObject; const AChange: TTyRichChange);
begin
  FLayouter.DocumentChanged(AChange);
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
  ClearPrepared;
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
  InvalidateContent(Rect(0, 0, Width, Height));
  if FViewPPI > 0 then UpdateBars(False);
end;

{ Held blocks the layouter dropped (a list's numbers after a change, F-M1's Stale) are laid
  out again: the same shape, only their band is painted again; another shape, the view is laid
  out again from there (above the view: the anchor below holds, only what is above goes). }
procedure TTyCustomRichEdit.RelayStale;
var
  k, m: Integer;
  b: TTyBlockLayout;
  area: TRect;
begin
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
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
      if (FBlocks[k].Top < FViewH) and (FBlocks[k].Top + FBlocks[k].Height > 0) then
        InvalidateContent(ViewRect(area.Left, area.Top + Math.Max(FBlocks[k].Top, 0),
          area.Top + Math.Min(FBlocks[k].Top + FBlocks[k].Height, FViewH), area.Right));
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
      if (FBlocks[k].Top < FViewH) and (FBlocks[k].Top + FBlocks[k].Height > 0) then
        InvalidateContent(ViewRect(area.Left, area.Top + Math.Max(FBlocks[k].Top, 0),
          area.Top + Math.Min(FBlocks[k].Top + FBlocks[k].Height, FViewH), area.Right));
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
      if FBlocks[k].Top < FViewH then
        InvalidateContent(ViewRect(area.Left, area.Top + Math.Max(FBlocks[k].Top, 0),
          area.Bottom, area.Right));
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
    FAnchorPara := lo;
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
    if (k0 >= 0) and (FBlocks[k0].Top < FViewH) then
      InvalidateContent(ViewRect(area.Left, area.Top + Math.Max(FBlocks[k0].Top, 0),
        area.Bottom, area.Right))
    else if (k0 < 0) and anchorMoved then
      InvalidateContent(area);
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
    InvalidateContent(area);
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
    if oldTop < FViewH then
      InvalidateContent(ViewRect(area.Left, area.Top + Math.Max(oldTop, 0),
        area.Top + Math.Min(oldBottom, FViewH), area.Right));
  end
  else
  begin
    // the blocks below moved: from the change down; the next pass fills what the move left
    if oldTop < FViewH then
      InvalidateContent(ViewRect(area.Left, area.Top + Math.Max(oldTop, 0), area.Bottom,
        area.Right));
    FViewValid := False;
  end;
  RelayStale;
  UpdateBars(False);
end;

{ ---- scrolling ---- }

function TTyCustomRichEdit.GetScrollY: Int64;
begin
  Settle;
  Result := AnchorY;
end;

procedure TTyCustomRichEdit.SetScrollY(AValue: Int64);
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

procedure TTyCustomRichEdit.ScrollViewBy(ADeltaY: Integer);
var
  a, last: Integer;
  off, maxTop, newY: Int64;
  b: TTyBlockLayout;
  t: TTyRichText;
begin
  if ADeltaY = 0 then Exit;
  CheckLayoutParams(ViewPPI);
  t := FDoc.Text;
  // a jump of many screens is a position, not a walk over every block between
  if Abs(Int64(ADeltaY)) > 4 * Int64(Math.Max(FViewH, 1)) then
  begin
    SetScrollY(AnchorY + ADeltaY);
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
          a := b.FirstPara;
          Inc(off, b.Height);
        finally
          b.Release;
        end;
      end;
  finally
    FDoc.EndRead;
  end;
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

procedure TTyCustomRichEdit.ViewMoved;
begin
  FViewValid := False;
  if FViewPPI > 0 then
    InvalidateContent(TextArea(Rect(0, 0, Width, Height), ViewPPI))
  else
    InvalidateContent(Rect(0, 0, Width, Height));
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
  page: Integer;
begin
  total := FDoc.Text.TotalHeight;
  topY := AnchorY;
  wantV := Decide((total > FViewH) or (topY > 0), FLatchV);
  wantH := Decide(FWidestSeen > FViewW, FLatchH);
  Result := (wantV <> VBarShown) or (wantH <> HBarShown);
  if wantV and (FVBar = nil) then FVBar := NewBar(Self, sbVertical, @VBarChange, FScrollBarAutoHide);
  if wantH and (FHBar = nil) then FHBar := NewBar(Self, sbHorizontal, @HBarChange, FScrollBarAutoHide);
  if FVBar <> nil then FVBar.Visible := wantV;
  if FHBar <> nil then FHBar.Visible := wantH;
  if Result then
  begin
    FViewValid := False;
    InvalidateContent(Rect(0, 0, Width, Height));
  end;
  PlaceBars;
  FSyncingBars := True;
  try
    if wantV then
    begin
      FVBar.Controller := Controller;
      maxTop := Math.Max(Int64(0), total - FViewH);
      { The bar's range is an Integer: a taller document is scrolled ScrollBarLimit units for
        its whole height, each unit FBarScale pixels; the last unit is the end, whatever the
        rounding. }
      scale := 1 + (maxTop + FViewH) div ScrollBarLimit;
      FBarScale := scale;
      page := Math.Max(1, FViewH div scale);
      FVBar.Min := 0;
      FVBar.Max := maxTop div scale;
      FVBar.PageSize := page;
      FVBar.SmallChange := Math.Max(1, FEstimate div scale);
      FVBar.LargeChange := page;
      if topY >= maxTop then FVBar.Position := FVBar.Max
      else FVBar.Position := topY div scale;
    end;
    if wantH then
    begin
      FHBar.Controller := Controller;
      ClampScrollX;
      FHBar.Min := 0;
      FHBar.Max := Math.Max(0, FWidestSeen - FViewW);
      FHBar.PageSize := Math.Max(1, FViewW);
      FHBar.SmallChange := Math.Max(1, FEstimate);
      FHBar.Position := FScrollX;
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
begin
  if FSyncingBars then Exit;
  FScrollX := FHBar.Position;
  ClampScrollX;
  InvalidateContent(TextArea(Rect(0, 0, Width, Height), ViewPPI));
end;

{ ---- painting ---- }

procedure TTyCustomRichEdit.InvalidateContent(const ARect: TRect);
var
  r: TRect;
begin
  if not HandleAllocated then Exit;
  r := ARect;
  LCLIntf.InvalidateRect(Handle, @r, False);
end;

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

procedure TTyCustomRichEdit.PaintArea(ACanvas: TCanvas; const ARect, AClip: TRect;
  APPI: Integer; ADefer: Boolean);
var
  P: TTyPainter;
  sc: TTyCanvasScale;
  clip, R, area, textClip, box: TRect;
  st: TTyRichPaintStyle;
  s: TTyStyleSet;
  k, j, x, y, padLeft: Integer;
  skipped: TTyRichSkippedPictures;
begin
  if not IntersectRect(clip, AClip, ARect) then Exit;
  EnsureView(APPI);
  ClampScrollX;
  { One layer for the clip: what the paint does not ask for costs nothing. The layout is in
    layout pixels at APPI, so the layer is drawn at one device pixel per layout pixel (on a
    scaled window the system stretches it; sharp text there is a later step). }
  sc := TyCanvasDeviceScale(ACanvas);
  if not sc.DeviceUnits then sc.Scale := 1;
  P := TTyPainter.Create;
  try
    P.BeginPaintScaled(ACanvas, clip, APPI, sc);
    R := Rect(ARect.Left - clip.Left, ARect.Top - clip.Top, ARect.Right - clip.Left,
      ARect.Bottom - clip.Top);
    s := CurrentStyle;
    DrawFrame(P, R, s);
    area := TextArea(R, APPI);
    { Text may reach into the left padding (a table row's \trleft is usually negative: Word
      puts its lines in the margin); never over the frame. }
    padLeft := MulDiv(s.Padding.Left, APPI, 96);
    textClip := area;
    if not (VBarShown and IsRightToLeft) then
      textClip.Left := Math.Max(R.Left + BorderInsetPx, area.Left - padLeft);
    if IntersectRect(textClip, textClip, Rect(0, 0, clip.Right - clip.Left,
      clip.Bottom - clip.Top)) then
    begin
      P.PrepareTextGround(textClip);
      FillPaintStyle(st);
      st.DeferPictures := ADefer;
      P.Bitmap.ClipRect := textClip;
      FLayouter.BeginPaintPass;
      try
        x := area.Left - FScrollX;
        for k := 0 to FBlockCount - 1 do
        begin
          if (area.Top + FBlocks[k].Top >= textClip.Bottom) or
            (area.Top + FBlocks[k].Top + FBlocks[k].Height <= textClip.Top) then Continue;
          // it meets the clip: its top is within a block's height of the view
          y := Integer(area.Top + FBlocks[k].Top);
          FBlocks[k].Layout.Paint(P.Bitmap, x, y, textClip, st, 0, 0);
          if ADefer and (FLayouter.SkippedPictureCount > 0) then
          begin
            skipped := FLayouter.TakeSkippedPictures;
            for j := 0 to High(skipped) do
            begin
              box := skipped[j].Box;
              QueuePicture(skipped[j].Picture, box.Right - box.Left, box.Bottom - box.Top,
                FBlocks[k].FirstPara, FBlocks[k].LastPara, True);
            end;
          end;
        end;
      finally
        P.Bitmap.NoClip;
      end;
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
  if FPendingCount > 0 then StartBackground;
end;

procedure TTyCustomRichEdit.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  PaintArea(ACanvas, ARect, ARect, APPI, False);
end;

procedure TTyCustomRichEdit.Paint;
begin
  PaintArea(Canvas, Rect(0, 0, Width, Height), Canvas.ClipRect, Font.PixelsPerInch, True);
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
  vy := Y - area.Top;
  k := 0;
  while (k < FBlockCount - 1) and (vy >= FBlocks[k].Top + FBlocks[k].Height) do Inc(k);
  // inside the block (or just outside it): within its height, an Integer
  by := Math.Max(Int64(-1), Math.Min(vy - FBlocks[k].Top, Int64(FBlocks[k].Height)));
  Result := FDoc.Text.ParaStart(FBlocks[k].FirstPara) +
    FBlocks[k].Layout.PosAtPoint(X - area.Left + FScrollX, Integer(by));
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
      Result := ViewRect(r.Left + area.Left - FScrollX, area.Top + FBlocks[k].Top + r.Top,
        area.Top + FBlocks[k].Top + r.Bottom, r.Right + area.Left - FScrollX);
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
      Exit(ViewRect(area.Left, area.Top + FBlocks[k].Top,
        area.Top + FBlocks[k].Top + FBlocks[k].Height, area.Right));
end;

{ ---- pictures made ready in the background ---- }

procedure TTyCustomRichEdit.QueuePicture(APicture: TTyRichPicture; AWidth, AHeight, APara,
  ALastPara: Integer; AHeld: Boolean);
var
  i: Integer;
begin
  { Once is enough (a view laid out again meets the same pictures, a picture may be in two
    places); and never again a (picture, size) just made ready: what the layouter could not
    make ready at that size it would not make ready a second time either. }
  if WasPrepared(APicture, AWidth, AHeight) then
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
    Area: TRect;
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
  r: TRect;
  top: Int64;
begin
  if (APicture <> Picture) or (ABox.Right - ABox.Left <> Width) or
    (ABox.Bottom - ABox.Top <> Height) then Exit;
  top := Area.Top + Owner.FBlocks[ABlock].Top;
  r := Owner.ViewRect(Area.Left - Owner.FScrollX + ABox.Left, top + ABox.Top, top + ABox.Bottom,
    Area.Left - Owner.FScrollX + ABox.Right);
  if IntersectRect(r, r, Area) then Owner.InvalidateContent(r);
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
    walk.Area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
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
      FLayouter.PreparePicture(pic.Picture, pic.Width, pic.Height);
      // its boxes in the view: nothing else is painted again
      InvalidatePicture(pic.Picture, pic.Width, pic.Height);
    end;
    NotePrepared(pic.Picture, pic.Width, pic.Height);
  finally
    pic.Picture.Release;
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
  t0 := GetTickCount64;
  n := 0;
  repeat
    if not StepBackground then Break;
    Inc(n);
  until (n >= CRichIdleMaxSteps) or (GetTickCount64 - t0 >= CRichIdleBudgetMs);
  if not HasBackgroundWork then StopBackground;
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
  if (i + 5 <= n) and CompareMem(@buf[i], @Sig[0], 5) then
  begin
    Result := rfRtf;
    // the reader starts at the signature
    AStream.Position := start + i;
  end;
end;

{ A load, a Lines replacement or Clear frees what a running step or save still uses. }
procedure TTyCustomRichEdit.CheckReplaceable;
begin
  if FInStep or (FSaving > 0) then raise ETyRichEdit.Create(rsRichEditBusy);
end;

procedure TTyCustomRichEdit.LoadAs(AStream: TStream; AFormat: TTyRichFormat);
var
  load: TTyRtfLoad;
begin
  CheckReplaceable;
  FCancelRequested := False;
  if AFormat = rfRtf then
  begin
    load := TyRichBeginLoadRtf(FDoc, AStream, FFirstSliceBytes);
    load.OnLoadProgress := @LoadProgress;
    FSourceFormat := rfRtf;
  end
  else
  begin
    TyRichLoadText(FDoc, AStream, FTextEncoding, FTextCodePage);
    FSourceFormat := rfText;
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
      TyRichSaveRtf(FDoc, AStream, @SaveProgress);
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
begin
  {$IFDEF MSWINDOWS}
  if FileExists(ATarget) then
    Result := ReplaceFileW(PWideChar(UnicodeString(ATarget)), PWideChar(UnicodeString(ASource)),
      nil, REPLACEFILE_IGNORE_MERGE_ERRORS, nil, nil)
  else
    Result := MoveFileExW(PWideChar(UnicodeString(ASource)), PWideChar(UnicodeString(ATarget)),
      MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH);
  {$ELSE}
  if fpStat(ATarget, st) = 0 then
  begin
    fpChmod(ASource, st.st_mode and &7777);
    // only root may give a file away; another user's file keeps our ownership then
    fpChown(ASource, st.st_uid, st.st_gid);
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
        ScrollViewBy(page);
        Key := 0;
      end;
    VK_PRIOR:
      begin
        ScrollViewBy(-page);
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
    ScrollViewBy(-notches * Math.Max(FEstimate, FViewH - FEstimate))
  else
    ScrollViewBy(-notches * perNotch * Math.Max(1, FEstimate));
end;

function TTyCustomRichEdit.DoMouseWheelHorz(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  notches: Integer;
begin
  if not IsEnabled then Exit(False);
  if inherited DoMouseWheelHorz(Shift, WheelDelta, MousePos) then Exit(True);
  Result := True;
  Inc(FWheelHRest, WheelDelta);
  notches := FWheelHRest div 120;
  Dec(FWheelHRest, notches * 120);
  if notches = 0 then Exit;
  FScrollX := FScrollX + notches * 3 * Math.Max(1, FEstimate);
  ClampScrollX;
  if HBarShown then
  begin
    FSyncingBars := True;
    try
      FHBar.Position := FScrollX;
    finally
      FSyncingBars := False;
    end;
  end;
  InvalidateContent(TextArea(Rect(0, 0, Width, Height), ViewPPI));
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
