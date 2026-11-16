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
  { One load slice: bytes of RTF indexed per step. }
  CRichLoadStepBytes = 256 * 1024;

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
    procedure Run(ACmd: TTyRichCommand);
  protected
    function Get(Index: Integer): string; override;
    function GetCount: Integer; override;
    procedure Put(Index: Integer; const S: string); override;
    procedure SetTextStr(const Value: string); override;
    { BeginUpdate .. EndUpdate around a Clear (what Assign and a form file do): the lines
      gather here and become the content once, at the end. }
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
    in pixels from the view's top. }
  TTyRichViewBlock = record
    Layout: TTyBlockLayout;
    FirstPara: Integer;
    LastPara: Integer;
    Top: Integer;
    Height: Integer;
  end;

  { A picture waiting to be decoded or scaled: the size it is to be drawn at, the block it is in
    (its first paragraph) and its box in that block. Holds a reference to the picture. }
  TTyRichPendingPicture = record
    Picture: TTyRichPicture;
    Width, Height: Integer;
    Para: Integer;
    Box: TRect;
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
    FAnchorOffset: Integer;
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
    FCancelRequested: Boolean;
    FTimer: TTimer;
    FPending: array of TTyRichPendingPicture;
    FPendingCount: Integer;
    // events
    FOnChange: TNotifyEvent;
    FOnZoomChange: TNotifyEvent;
    FOnLoadProgress: TTyRichProgressEvent;
    FOnSaveProgress: TTyRichProgressEvent;
    procedure DocChanged(Sender: TObject; const AChange: TTyRichChange);
    procedure ContentReplaced;
    procedure ChangeInView(const AChange: TTyRichChange);
    procedure ReleaseBlocks;
    procedure ClearPending;
    procedure AddBlock(var AList: array of TTyRichViewBlock; var ACount: Integer;
      ALayout: TTyBlockLayout; ATop: Integer);
    procedure WriteHeights(AFrom, ATo: Integer);
    procedure NoteExtent(ALayout: TTyBlockLayout);
    procedure QueuePicturesAhead;
    procedure QueuePicture(APicture: TTyRichPicture; AWidth, AHeight, APara: Integer;
      const ABox: TRect; AHeld: Boolean);
    function ScrollBarSize(APPI: Integer): Integer;
    { The PPI the view was last laid out at; the control's before that. }
    function ViewPPI: Integer;
    function VBarShown: Boolean;
    function HBarShown: Boolean;
    function UpdateBars: Boolean;
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
    { Paints the whole control into ACanvas at ARect, pictures decoded now (a preview, a test). }
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure ScrollViewBy(ADeltaY: Integer);
    procedure ScrollToTop;
    procedure ScrollToEnd;
    { The document position at client point (X, Y) of the view, through the visible blocks: the
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
    property TopOffset: Integer read FAnchorOffset;
    property Loading: Boolean read GetLoading;
    property Incomplete: Boolean read GetIncomplete;
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
    property OnLoadProgress: TTyRichProgressEvent read FOnLoadProgress write FOnLoadProgress;
    property OnSaveProgress: TTyRichProgressEvent read FOnSaveProgress write FOnSaveProgress;
    property OnFallbackFont: TTyRichFallbackEvent read GetOnFallbackFont write SetOnFallbackFont;
    { ITyScrollBarFrameHost }
    function ScrollBarFrameStyle: TTyStyleSet;
    function EmbedsScrollBar(ABar: TTyScrollBar): Boolean;
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
  if (Result = 1) and (t.Length = 0) then Result := 0;
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
    if S = '' then
      Run(TTyRichInsertText.Create(0, #10, TyRichInheritFormat, False))
    else
      Run(TTyRichInsertText.Create(0, S, TyRichInheritFormat, False));
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
  end
  else if Index = n - 1 then
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
  if not Updating and (FBatch <> nil) then
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
  if FDoc <> nil then FDoc.OnChange := nil;
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
begin
  FLayouter.OnFallbackFont := AValue;
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
  if (AIndex < 0) or (AIndex >= FBlockCount) then
    raise ETyRichEdit.CreateFmt('Visible block %d out of range', [AIndex]);
  Result := FBlocks[AIndex];
end;

function TTyCustomRichEdit.VisibleBlockCount: Integer;
begin
  Result := FBlockCount;
end;

procedure TTyCustomRichEdit.DoChange;
begin
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

procedure TTyCustomRichEdit.AddBlock(var AList: array of TTyRichViewBlock; var ACount: Integer;
  ALayout: TTyBlockLayout; ATop: Integer);
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
  size, halfPt, w, est: Integer;
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
      measured advances (its cached layouts are replaced as they are asked for). }
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
  below, above: array of TTyRichViewBlock;
  nBelow, nAbove, i, y, total, next, deficit, shift, k: Integer;
  b: TTyBlockLayout;
  paraCount: Integer;
  t: TTyRichText;
  topY: Int64;
begin
  ReleaseBlocks;
  FViewValid := True;
  if FViewH <= 0 then Exit;
  t := FDoc.Text;
  paraCount := t.ParaCount;
  if FAnchorPara >= paraCount then
  begin
    FAnchorPara := paraCount - 1;
    FAnchorOffset := MaxInt div 2;
  end;
  if FAnchorPara < 0 then FAnchorPara := 0;
  if FAnchorOffset < 0 then FAnchorOffset := 0;
  below := nil;
  above := nil;
  nBelow := 0;
  nAbove := 0;
  FDoc.BeginRead;
  try
    // the anchor's block: a paragraph inside a table row anchors the row
    b := LayoutBlockAt(FAnchorPara);
    if b.FirstPara <> FAnchorPara then
    begin
      topY := t.ParaTop(FAnchorPara) - t.ParaTop(b.FirstPara) + FAnchorOffset;
      if topY > MaxInt div 2 then topY := MaxInt div 2;
      FAnchorOffset := Integer(topY);
      FAnchorPara := b.FirstPara;
    end;
    if FAnchorOffset >= b.Height then FAnchorOffset := Math.Max(0, b.Height - 1);
    // down: the view and a screen past it
    SetLength(below, 64);
    y := -FAnchorOffset;
    repeat
      if nBelow = Length(below) then SetLength(below, nBelow * 2);
      AddBlock(below, nBelow, b, y);
      NoteExtent(b);
      Inc(y, b.Height);
      next := b.LastPara + 1;
      if (y >= 2 * FViewH) or (next >= paraCount) then Break;
      b := LayoutBlockAt(next);
    until False;
    // at the end of the document the last line stays at the bottom of the view
    deficit := 0;
    if (next >= paraCount) and (y < FViewH) then deficit := FViewH - y;
    // up: a screen above the view (and what the end needs to fill it)
    SetLength(above, 64);
    total := 0;
    i := FAnchorPara - 1;
    while (i >= 0) and (total < FViewH + deficit) do
    begin
      b := LayoutBlockAt(i);
      Inc(total, b.Height);
      if nAbove = Length(above) then SetLength(above, nAbove * 2);
      AddBlock(above, nAbove, b, -FAnchorOffset - total);
      NoteExtent(b);
      i := b.FirstPara - 1;
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
  // the slices a lazy load adds are its progress, not changes of the content
  if not FInStep then DoChange;
end;

procedure TTyCustomRichEdit.ContentReplaced;
begin
  FText := FDoc.Text;
  ReleaseBlocks;
  ClearPending;
  // told, not recognised: the layouter empties everything it kept
  FLayouter.Document := FDoc;
  FAnchorPara := 0;
  FAnchorOffset := 0;
  FScrollX := 0;
  FWidestSeen := 0;
  FViewValid := False;
  // the new text has no heights: it gets the estimate before anything asks
  if FEstimate > 0 then FDoc.Text.DefaultParaHeight := FEstimate;
  InvalidateContent(Rect(0, 0, Width, Height));
  if FViewPPI > 0 then UpdateBars;
end;

procedure TTyCustomRichEdit.ChangeInView(const AChange: TTyRichChange);
var
  lo, hiOld, delta, k, k0, k1, i, oldTop, oldBottom, y, n, p, stop: Integer;
  fresh: array of TTyRichViewBlock;
  b: TTyBlockLayout;
  area, r: TRect;
  sameHeight, anchorMoved: Boolean;
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
  // pictures waiting in changed blocks go; the others follow their paragraphs
  k := 0;
  for i := 0 to FPendingCount - 1 do
    if (FPending[i].Para >= lo) and (FPending[i].Para <= hiOld) then
      FPending[i].Picture.Release
    else
    begin
      FPending[k] := FPending[i];
      if FPending[k].Para > hiOld then Inc(FPending[k].Para, delta);
      Inc(k);
    end;
  FPendingCount := k;
  if not FViewValid or (FBlockCount = 0) then
  begin
    if FViewPPI > 0 then UpdateBars;
    Exit;
  end;
  // the view's blocks the change touches
  k0 := -1;
  k1 := -1;
  for k := 0 to FBlockCount - 1 do
    if (FBlocks[k].LastPara >= lo) and (FBlocks[k].FirstPara <= hiOld) then
    begin
      if k0 < 0 then k0 := k;
      k1 := k;
    end;
  if k0 < 0 then
  begin
    { Not in the view: above it, the blocks keep their places (the anchor holds) and their
      paragraphs move; below it, nothing on screen changes. }
    for k := 0 to FBlockCount - 1 do
      if FBlocks[k].FirstPara > hiOld then
      begin
        Inc(FBlocks[k].FirstPara, delta);
        Inc(FBlocks[k].LastPara, delta);
      end;
    UpdateBars;
    Exit;
  end;
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  if anchorMoved or (FBlocks[k0].FirstPara > lo) then
  begin
    // the change reaches above the blocks the view holds, or across its top: all again
    FViewValid := False;
    InvalidateContent(area);
    UpdateBars;
    Exit;
  end;
  oldTop := FBlocks[k0].Top;
  oldBottom := FBlocks[k1].Top + FBlocks[k1].Height;
  // the changed blocks laid out again, from the first one's paragraph (it did not move)
  p := FBlocks[k0].FirstPara;
  stop := FBlocks[k1].LastPara + delta;
  fresh := nil;
  n := 0;
  y := oldTop;
  FDoc.BeginRead;
  try
    while (p <= stop) and (p < FDoc.Text.ParaCount) do
    begin
      b := LayoutBlockAt(p);
      if n = Length(fresh) then SetLength(fresh, n * 2 + 4);
      AddBlock(fresh, n, b, y);
      NoteExtent(b);
      Inc(y, b.Height);
      p := b.LastPara + 1;
    end;
  finally
    FDoc.EndRead;
  end;
  sameHeight := (y = oldBottom) and (n > 0) and (fresh[n - 1].LastPara = stop);
  // the view's list: the blocks before, the fresh ones, the later ones at their new indexes
  for k := k0 to k1 do FBlocks[k].Layout.Release;
  if n <> k1 - k0 + 1 then
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
  for k := k0 + n to FBlockCount - 1 do
  begin
    Inc(FBlocks[k].FirstPara, delta);
    Inc(FBlocks[k].LastPara, delta);
    Inc(FBlocks[k].Top, y - oldBottom);
  end;
  if n > 0 then WriteHeights(k0, k0 + n - 1);
  if sameHeight then
  begin
    // only the changed blocks, as far as they are on screen
    r := Rect(area.Left, area.Top + Math.Max(oldTop, 0), area.Right,
      area.Top + Math.Min(oldBottom, FViewH));
    if r.Bottom > r.Top then InvalidateContent(r);
  end
  else
  begin
    { The blocks below moved: from the change down. A change wholly above the view moves
      nothing on screen (the anchor below it holds). }
    if (oldBottom > 0) and (oldTop < FViewH) then
      InvalidateContent(Rect(area.Left, area.Top + Math.Max(oldTop, 0), area.Right,
        area.Bottom));
    // the next pass fills what the move left (above the view nothing moves: the anchor holds)
    FViewValid := False;
  end;
  UpdateBars;
end;

{ ---- scrolling ---- }

function TTyCustomRichEdit.GetScrollY: Int64;
begin
  Result := FDoc.Text.ParaTop(FAnchorPara) + FAnchorOffset;
end;

procedure TTyCustomRichEdit.SetScrollY(AValue: Int64);
var
  t: TTyRichText;
  i: Integer;
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
  FAnchorPara := i;
  FAnchorOffset := Integer(AValue - t.ParaTop(i));
  ViewMoved;
end;

procedure TTyCustomRichEdit.ScrollViewBy(ADeltaY: Integer);
var
  off, a, last: Integer;
  b: TTyBlockLayout;
begin
  if ADeltaY = 0 then Exit;
  CheckLayoutParams(ViewPPI);
  last := FDoc.Text.ParaCount - 1;
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
            Inc(off, Integer(FDoc.Text.ParaTop(a) - FDoc.Text.ParaTop(b.FirstPara)));
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
  FAnchorPara := a;
  FAnchorOffset := off;
  ViewMoved;
end;

procedure TTyCustomRichEdit.ScrollToTop;
begin
  FAnchorPara := 0;
  FAnchorOffset := 0;
  ViewMoved;
end;

procedure TTyCustomRichEdit.ScrollToEnd;
begin
  // the last block at the top, past its end: the layout pass pulls the view up to fill it
  FAnchorPara := FDoc.Text.ParaCount - 1;
  FAnchorOffset := MaxInt div 2;
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
  for pass := 1 to 4 do
  begin
    CheckLayoutParams(APPI);
    { The bars first, from the heights as they are (estimates included): a bar that came
      after the layout would change the width and have it all laid out a second time. }
    if UpdateBars then Continue;
    if FViewValid then Break;
    LayoutView;
    // what the layout found (a wide block, corrected heights) may still want a bar
    if not UpdateBars then Break;
  end;
  if not FViewValid then
  begin
    CheckLayoutParams(APPI);
    LayoutView;
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
function TTyCustomRichEdit.UpdateBars: Boolean;
var
  total, topY, maxTop, scale: Int64;
  wantV, wantH: Boolean;
  page: Integer;
begin
  total := FDoc.Text.TotalHeight;
  topY := GetScrollY;
  wantV := (total > FViewH) or (topY > 0);
  wantH := FWidestSeen > FViewW;
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
          y := area.Top + FBlocks[k].Top;
          if (y >= textClip.Bottom) or (y + FBlocks[k].Height <= textClip.Top) then Continue;
          FBlocks[k].Layout.Paint(P.Bitmap, x, y, textClip, st, 0, 0);
          if ADefer and (FLayouter.SkippedPictureCount > 0) then
          begin
            skipped := FLayouter.TakeSkippedPictures;
            for j := 0 to High(skipped) do
            begin
              box := skipped[j].Box;
              Types.OffsetRect(box, -x, -y);
              QueuePicture(skipped[j].Picture, box.Right - box.Left, box.Bottom - box.Top,
                FBlocks[k].FirstPara, box, True);
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
  k, vy: Integer;
begin
  Result := -1;
  if FBlockCount = 0 then Exit;
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  vy := Y - area.Top;
  k := 0;
  while (k < FBlockCount - 1) and (vy >= FBlocks[k].Top + FBlocks[k].Height) do Inc(k);
  Result := FDoc.Text.ParaStart(FBlocks[k].FirstPara) +
    FBlocks[k].Layout.PosAtPoint(X - area.Left + FScrollX, vy - FBlocks[k].Top);
end;

function TTyCustomRichEdit.PositionRect(APos: TTyRichPos): TRect;
var
  area: TRect;
  k: Integer;
  start, stop: TTyRichPos;
  t: TTyRichText;
begin
  Result := Rect(0, 0, 0, 0);
  t := FDoc.Text;
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  for k := 0 to FBlockCount - 1 do
  begin
    start := t.ParaStart(FBlocks[k].FirstPara);
    stop := t.ParaStart(FBlocks[k].LastPara) + t.ParaLength(FBlocks[k].LastPara);
    if (APos >= start) and (APos <= stop) then
    begin
      Result := FBlocks[k].Layout.CaretRect(APos - start);
      Types.OffsetRect(Result, area.Left - FScrollX, area.Top + FBlocks[k].Top);
      Exit;
    end;
  end;
end;

function TTyCustomRichEdit.ParagraphRect(AIndex: Integer): TRect;
var
  area: TRect;
  k: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
  for k := 0 to FBlockCount - 1 do
    if (AIndex >= FBlocks[k].FirstPara) and (AIndex <= FBlocks[k].LastPara) then
      Exit(Rect(area.Left, area.Top + FBlocks[k].Top, area.Right,
        area.Top + FBlocks[k].Top + FBlocks[k].Height));
end;

{ ---- pictures made ready in the background ---- }

procedure TTyCustomRichEdit.QueuePicture(APicture: TTyRichPicture; AWidth, AHeight,
  APara: Integer; const ABox: TRect; AHeld: Boolean);
var
  i: Integer;
begin
  // once is enough (a view laid out again meets the same pictures)
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
  FPending[FPendingCount].Box := ABox;
  Inc(FPendingCount);
end;

{ The pictures of the blocks laid out off screen (a screen ahead and behind) that are not ready
  at their size: made ready in the background, so they are when they scroll in. }
procedure TTyCustomRichEdit.QueuePicturesAhead;

  procedure FromPara(L: TTyParaLayout; AX, AY, APara: Integer);
  var
    i, j: Integer;
    ln: TTyRichLine;
    f: TTyRichFragment;
    box: TRect;
  begin
    for i := 0 to L.LineCount - 1 do
    begin
      ln := L.Lines[i];
      for j := ln.FirstFrag to ln.FirstFrag + ln.FragCount - 1 do
      begin
        f := L.Fragments[j];
        if (f.Kind <> rfkObject) or not (f.Obj is TTyRichPicture) then Continue;
        box := Rect(AX + f.X, AY + ln.Baseline - f.Ascent, AX + f.X + f.Width,
          AY + ln.Baseline + f.Descent);
        if not FLayouter.PictureReady(TTyRichPicture(f.Obj), box.Right - box.Left,
          box.Bottom - box.Top) then
          QueuePicture(TTyRichPicture(f.Obj), box.Right - box.Left, box.Bottom - box.Top,
            APara, box, False);
      end;
    end;
  end;

var
  k, i: Integer;
  row: TTyRowLayout;
begin
  for k := 0 to FBlockCount - 1 do
  begin
    if (FBlocks[k].Top < FViewH) and (FBlocks[k].Top + FBlocks[k].Height > 0) then Continue;
    if FBlocks[k].Layout is TTyParaLayout then
      FromPara(TTyParaLayout(FBlocks[k].Layout), 0, 0, FBlocks[k].FirstPara)
    else if FBlocks[k].Layout is TTyRowLayout then
    begin
      row := TTyRowLayout(FBlocks[k].Layout);
      for i := 0 to row.ItemCount - 1 do
        FromPara(row.Items[i].Layout, row.Items[i].X, row.Items[i].Y, FBlocks[k].FirstPara);
    end;
  end;
  if FPendingCount > 0 then StartBackground;
end;

function TTyCustomRichEdit.HasBackgroundWork: Boolean;
begin
  Result := (FPendingCount > 0) or (FDoc.Loading and (TyRichRtfLoadOf(FDoc) <> nil));
end;

function TTyCustomRichEdit.StepBackground: Boolean;
var
  load: TTyRtfLoad;
  pic: TTyRichPendingPicture;
  k: Integer;
  area, r: TRect;
begin
  Result := False;
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
      // its box, if its block is in the view: nothing else is painted again
      area := TextArea(Rect(0, 0, Width, Height), ViewPPI);
      for k := 0 to FBlockCount - 1 do
        if FBlocks[k].FirstPara = pic.Para then
        begin
          r := pic.Box;
          Types.OffsetRect(r, area.Left - FScrollX, area.Top + FBlocks[k].Top);
          if IntersectRect(r, r, area) then InvalidateContent(r);
          Break;
        end;
    end;
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
begin
  t0 := GetTickCount64;
  repeat
    if not StepBackground then Break;
  until GetTickCount64 - t0 >= CRichIdleBudgetMs;
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

procedure TTyCustomRichEdit.LoadAs(AStream: TStream; AFormat: TTyRichFormat);
var
  load: TTyRtfLoad;
begin
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
  fs := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
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
  FSourceFormat := rfText;
  FSourceFile := '';
  FLinesStored := True;
end;

procedure TTyCustomRichEdit.FinishLoading;
var
  load: TTyRtfLoad;
begin
  load := TyRichRtfLoadOf(FDoc);
  if (load = nil) or not FDoc.Loading then Exit;
  load.OnLoadProgress := @LoadProgress;
  FInStep := True;
  try
    while not FCancelRequested and not load.Step(High(Int64) div 4) do ;
  finally
    FInStep := False;
  end;
  if FCancelRequested then CancelLoad;
  if not HasBackgroundWork then StopBackground;
end;

procedure TTyCustomRichEdit.CancelLoad;
var
  load: TTyRtfLoad;
begin
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
  FinishLoading;
  if FDoc.Incomplete then raise ETyRichEdit.Create(rsRichEditIncomplete);
  if AFormat = rfAuto then AFormat := FSourceFormat;
  if AFormat = rfText then
    TyRichSaveText(FDoc, AStream)
  else
    TyRichSaveRtf(FDoc, AStream, @SaveProgress);
end;

procedure TTyCustomRichEdit.SaveToStream(AStream: TStream; AFormat: TTyRichFormat);
begin
  WriteTo(AStream, AFormat);
  FDoc.Modified := False;
end;

{ Puts ASource in ATarget's place (ATarget may exist). }
function ReplaceFile(const ASource, ATarget: string): Boolean;
begin
  {$IFDEF MSWINDOWS}
  Result := MoveFileExW(PWideChar(UnicodeString(ASource)), PWideChar(UnicodeString(ATarget)),
    MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH);
  {$ELSE}
  // rename(2) replaces the target in one step
  Result := RenameFile(ASource, ATarget);
  {$ENDIF}
end;

procedure TTyCustomRichEdit.SaveToFile(const AFileName: string; AFormat: TTyRichFormat);
var
  full, tmp, ext: string;
  fs: TFileStream;
  n: Integer;
begin
  full := ExpandFileName(AFileName);
  FinishLoading;
  if FDoc.Incomplete then raise ETyRichEdit.Create(rsRichEditIncomplete);
  if AFormat = rfAuto then
  begin
    ext := LowerCase(ExtractFileExt(full));
    if ext = '.rtf' then AFormat := rfRtf
    else if ext = '.txt' then AFormat := rfText
    else AFormat := FSourceFormat;
  end;
  { Beside the target, so that putting it in the target's place is a rename on one volume;
    the target - perhaps the very file the document reads from - is untouched until then. }
  n := 0;
  repeat
    tmp := ExtractFilePath(full) + '.' + ExtractFileName(full) + '.' +
      IntToHex(Random($7FFFFFFF), 8) + '.tmp';
    Inc(n);
  until not FileExists(tmp) or (n > 100);
  fs := TFileStream.Create(tmp, fmCreate);
  try
    try
      WriteTo(fs, AFormat);
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
  FDoc.Modified := False;
  FSourceFile := full;
  FSourceFormat := AFormat;
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
