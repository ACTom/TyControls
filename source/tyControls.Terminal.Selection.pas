unit tyControls.Terminal.Selection;
{$mode objfpc}{$H+}

{ The terminal's selection without the mouse plumbing: where a click, a double or
  triple click and a drag put the selection, how it follows lines trimmed off the top
  of the buffer, which cells of a row it covers and what text it holds. Also the
  pixel-to-boundary rounding a selection uses, the drag-scroll speed and the OSC 52
  argument and base64 rules. No LCL: the control turns its mouse events into the
  points and flags these take.

  PORTED FROM xterm.js 6.0.0, commit c58ea3637f39:
    src/browser/selection/SelectionModel.ts        TTyTermSelectionModel
    src/browser/services/SelectionService.ts       TTyTermSelection (the parts that do
                                                   not touch the DOM)
    src/browser/renderer/dom/DomRendererRowFactory.ts:534-552   RowSpan
    src/browser/input/Mouse.ts:40-49               TyTermSelectionPointAt's rounding
    src/common/buffer/BufferRange.ts               getRangeLength
    Copyright (c) 2017-2019, The xterm.js authors (https://github.com/xtermjs/xterm.js)
    Copyright (c) 2014-2016, SourceLair Private Company (https://www.sourcelair.com)
    Copyright (c) 2012-2013, Christopher Jeffrey (https://github.com/chjj/)
    addons/addon-clipboard/src/ClipboardAddon.ts   TyTermOsc52Split / Decode / Reply
    Copyright (c) 2023, The xterm.js authors (https://github.com/xtermjs/xterm.js)
  MIT; the full text is in THIRD-PARTY-NOTICES.md.

  WHAT DIFFERS IN SHAPE (never in result):

  - Upstream's handlers read the mouse themselves; here Press / DragTo / Release take
    the selection point (a column BOUNDARY 0..Cols and a buffer row) and the flags
    the control worked out (clicks, Shift extension, column mode, the link under the
    pointer). Which press becomes a selection at all is the control's business.
  - _dragScroll is split in two -- DragScrollAmount, then the control scrolls, then
    AfterDragScroll -- because the scrolling belongs to the control.
  - Upstream remembers the start and end it last reported by keeping the model's own
    arrays, which the model then changes in place (lines trimmed off the top, a drag
    scrolling, a click stepping over the second half of a wide character). Those
    changes show in the remembered values too and decide whether the next release
    reports a change. Points are values here, so the remembered ones note which live
    point they stand for and take the same in-place changes (FOld*Alias).
  - Word boundaries are found in UTF-16 indices, as upstream counts them
    (translateBufferLineToString into a UnicodeString; a cell's text length in
    UTF-16 units). A cell never written has the empty text, and the empty string is a
    word separator (indexOf('') is 0) -- kept.
  - OSC 52's base64 is the WHATWG forgiving-base64 decode that atob does, and its
    UTF-8 is the WHATWG decoder TextDecoder uses (a leading BOM dropped, a bad
    sequence replaced by U+FFFD per maximal subpart) -- what the addon does in node
    and in browsers without Uint8Array.fromBase64. }

interface

uses
  SysUtils, Classes, Types, Math, tyControls.Unicode.Width, tyControls.Terminal.Buffer;

type
  { A selection point: Col is a boundary 0..Cols (not a cell), Row a buffer row
    (0 = the oldest line of the scrollback). }
  TTyTermSelPoint = record
    Col, Row: Integer;
  end;
  TTyTermSelMode = (tsmNormal, tsmWord, tsmLine, tsmColumn);   { SelectionService.ts:56-61 }

  { SelectionModel.ts:12-145 }
  TTyTermSelectionModel = class
  private
    FBuffers: TTyTerminalBufferService;
  public
    IsSelectAllActive: Boolean;
    StartLength: Integer;
    HasStart, HasEnd: Boolean;
    Start, Finish: TTyTermSelPoint;             { selectionStart / selectionEnd }
    constructor Create(ABuffers: TTyTerminalBufferService);
    procedure Clear;
    function FinalStart(out P: TTyTermSelPoint): Boolean;   { False = undefined }
    function FinalEnd(out P: TTyTermSelPoint): Boolean;
    function AreReversed: Boolean;
    function HandleTrim(AAmount: Integer): Boolean;          { True = redraw }
  end;

  { A link's range as the Linkifier has it (IBufferRange: 1-based, inclusive, buffer
    rows); a double click selects it. The links unit uses it. }
  TTyTermLinkRange = record
    StartX, StartY, EndX, EndY: Integer;
  end;
  PTyTermLinkRange = ^TTyTermLinkRange;

  TTyTermOldAlias = (toaNone, toaStart, toaEnd);

  { SelectionService.ts without the DOM (unit header). }
  TTyTermSelection = class
  private
    FBuffers: TTyTerminalBufferService;
    FModel: TTyTermSelectionModel;
    FMode: TTyTermSelMode;
    FDragScrollAmount: Integer;
    FDragging: Boolean;
    FSeparators: UnicodeString;
    { _oldHasSelection / _oldSelectionStart / _oldSelectionEnd (unit header) }
    FOldHas: Boolean;
    FOldHasStart, FOldHasEnd: Boolean;
    FOldStart, FOldEnd: TTyTermSelPoint;
    FOldStartAlias, FOldEndAlias: TTyTermOldAlias;
    FOnChange, FOnRedraw: TNotifyEvent;
    FTextBuilds: Integer;
    function Cols: Integer;
    function Buffer: TTyTerminalBuffer;
    procedure Redraw;
    procedure Changed;
    { the live points: a new value breaks what the remembered ones share with it;
      a change in place reaches them }
    procedure Detach(AWhich: TTyTermOldAlias);
    procedure PutStart(const P: TTyTermSelPoint);
    procedure PutEnd(const P: TTyTermSelPoint);
    procedure DropEnd;
    procedure ClearModel;
    procedure NudgeStartCol(ADelta: Integer);
    procedure SetEndInPlace(ACol, ARow: Integer; ASetCol: Boolean);
    function FinalStartAlias(out P: TTyTermSelPoint; out AAlias: TTyTermOldAlias): Boolean;
    function FinalEndAlias(out P: TTyTermSelPoint; out AAlias: TTyTermOldAlias): Boolean;
    procedure FireOnSelectionChange(AHasStart: Boolean; const AStart: TTyTermSelPoint;
      AStartAlias: TTyTermOldAlias; AHasEnd: Boolean; const AEnd: TTyTermSelPoint;
      AEndAlias: TTyTermOldAlias; AHas: Boolean);
    procedure FireEventIfSelectionChanged;
    function AreCoordsInSelection(const P, S, E: TTyTermSelPoint): Boolean;
    function IsClickInSelection(const P: TTyTermSelPoint): Boolean;
    function IsCharWordSeparator(ALine: TTyTerminalLine; ACol: Integer): Boolean;
    function ConvertViewportColToCharacterIndex(ALine: TTyTerminalLine; AX: Integer): Integer;
    { _getWordAt without its two recursions: the word on this row only }
    function GetWordAtRow(const P: TTyTermSelPoint; AAllowWhitespaceOnly: Boolean;
      out AStart, ALength: Integer): Boolean;
    function GetWordAt(const P: TTyTermSelPoint; AAllowWhitespaceOnly, AFollowAbove,
      AFollowBelow: Boolean; out AStart, ALength: Integer): Boolean;
    procedure SelectWordAt(const P: TTyTermSelPoint; AAllowWhitespaceOnly: Boolean);
    procedure SelectToWordAt(const P: TTyTermSelPoint);
    function SelectWordAtCursor(const P: TTyTermSelPoint; AAllowWhitespaceOnly: Boolean;
      ALink: PTyTermLinkRange): Boolean;
    procedure SelectLineAt(ARow: Integer);
    procedure SingleClick(const P: TTyTermSelPoint; AColumn: Boolean);
    procedure IncrementalClick(const P: TTyTermSelPoint);
  public
    constructor Create(ABuffers: TTyTerminalBufferService);
    destructor Destroy; override;
    { A press that is a selection: AClicks 1..3; AIncremental = Shift extends (only
      when no program has the mouse); AColumn = column selection; ALink = the link
      under the pointer for a double click (nil = none). handleMouseDown :483-499. }
    procedure Press(const APoint: TTyTermSelPoint; AClicks: Integer; AIncremental, AColumn: Boolean;
      ALink: PTyTermLinkRange = nil);
    { A drag to APoint; AScrollAmount from TyTermDragScrollAmount. _handleMouseMove :619-686 }
    procedure DragTo(const APoint: TTyTermSelPoint; AScrollAmount: Integer);
    { One tick of the drag scroll: the lines to scroll (0 = none); the control scrolls
      and then calls AfterDragScroll. _dragScroll :692-716 }
    function DragScrollAmount: Integer;
    procedure AfterDragScroll;
    { The button came up: _handleMouseUp without the Alt+click cursor move :722-744 }
    procedure Release;
    { The macOS right click: rightClickSelect :820-827 }
    procedure RightClickSelect(const APoint: TTyTermSelPoint; ALink: PTyTermLinkRange = nil);
    procedure SelectAll;                                      { :366-370 }
    procedure SelectLines(AFirst, ALast: Integer);            { :372-380 }
    procedure SetSelection(ACol, ARow, ALength: Integer);     { :811-818 }
    procedure Clear;                                          { clearSelection :267-272 }
    procedure HandleTrim(AAmount: Integer);                   { :386-391 }
    function HasSelection: Boolean;                           { :191-198 }
    { selectionText :203-262, rows joined with ALineSep, NBSP as a space; UTF-8 }
    function Text(const ALineSep: string): string;
    { Drawing: the columns [AFrom, ATo) of buffer row AAbsRow the selection covers;
      False = none (DomRendererRowFactory.ts:534-552). }
    function RowSpan(AAbsRow: Integer; out AFrom, ATo: Integer): Boolean;
    function FinalStart(out P: TTyTermSelPoint): Boolean;
    function FinalEnd(out P: TTyTermSelPoint): Boolean;
    property Mode: TTyTermSelMode read FMode;
    { between a press and its release (upstream's mousemove listener is attached) }
    property Dragging: Boolean read FDragging;
    property DragAmount: Integer read FDragScrollAmount;
    property WordSeparators: UnicodeString read FSeparators write FSeparators;
    { every onSelectionChange }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    { every refresh() }
    property OnRedraw: TNotifyEvent read FOnRedraw write FOnRedraw;
    { FOR THE TESTS }
    property Model: TTyTermSelectionModel read FModel;
    { how many times Text built the selection's text }
    property TextBuilds: Integer read FTextBuilds;
  end;

const
  { options.wordSeparator's default (OptionsService.ts:55) }
  TyTermDefaultWordSeparators = ' ()[]{}'',"`';
  { SelectionService.ts:21-39 }
  TyTermDragScrollMaxThreshold = 50;
  TyTermDragScrollMaxSpeed = 15;
  TyTermDragScrollInterval = 50;

{ A device pixel (relative to the grid's top-left) to a selection point's column
  boundary and viewport row: the pointer at the pixel's centre, a click on a cell's
  right half starting at the next boundary (Mouse.ts:40-49 with isSelection).
  X in 0..ACols, Y in 0..ARows - 1. }
function TyTermSelectionPointAt(APx, APy, ACellW, ACellH, ACols, ARows: Integer): TPoint;
{ The drag-scroll speed: AOffsetY device pixels from the grid's top (negative above),
  AHeight the grid's height, AThreshold the distance of full speed (50 at 96 PPI).
  0 inside. _getMouseEventScrollAmount :417-430, Math.round as upstream's. }
function TyTermDragScrollAmount(AOffsetY, AHeight, AThreshold: Integer): Integer;
{ OSC 52 (ClipboardAddon.ts:32-39): Pc and Pd, the first two ';'-separated fields;
  False when there are fewer than two. }
function TyTermOsc52Split(const AData: string; out APc, APd: string): Boolean;
{ Pd to the text it carries (UTF-8); '' when it is not base64 (unit header). }
function TyTermOsc52Decode(const APd: string): string;
{ The answer to a read: ESC ] 52 ; Pc ; base64(AText) BEL }
function TyTermOsc52Reply(const APc, AText: string): RawByteString;
{ Standard base64 with padding (btoa). }
function TyTermBase64Encode(const ABytes: RawByteString): string;

implementation

{ ---- small helpers ---------------------------------------------------------------- }

function SelPoint(ACol, ARow: Integer): TTyTermSelPoint; inline;
begin
  Result.Col := ACol;
  Result.Row := ARow;
end;

function SamePoint(const A, B: TTyTermSelPoint): Boolean; inline;
begin
  Result := (A.Col = B.Col) and (A.Row = B.Row);
end;

{ A UTF-8 string's length in UTF-16 units (a four-byte sequence is two). }
function Utf16Len(const S: string): Integer;
var
  i: Integer;
  b: Byte;
begin
  Result := 0;
  for i := 1 to Length(S) do
  begin
    b := Ord(S[i]);
    if (b and $C0) <> $80 then
    begin
      Inc(Result);
      if b >= $F0 then Inc(Result);
    end;
  end;
end;

{ JavaScript's charAt: '' outside the string, which is never ' '. 0-based. }
function IsSpaceAt(const S: UnicodeString; AIndex: Integer): Boolean; inline;
begin
  Result := (AIndex >= 0) and (AIndex < Length(S)) and (S[AIndex + 1] = ' ');
end;

{ line.slice(a, b).trim() === '' -- slice's negative indices count from the end }
function SliceIsBlank(const S: UnicodeString; AFrom, ATo: Integer): Boolean;
var
  n, i: Integer;
begin
  n := Length(S);
  if AFrom < 0 then AFrom := n + AFrom;
  if AFrom < 0 then AFrom := 0;
  if AFrom > n then AFrom := n;
  if ATo < 0 then ATo := n + ATo;
  if ATo < 0 then ATo := 0;
  if ATo > n then ATo := n;
  for i := AFrom to ATo - 1 do
    if not TyTermIsJsWhitespace(Ord(S[i + 1])) then
      Exit(False);
  Result := True;
end;

{ BufferRange.ts:8-13 }
function RangeLength(const R: TTyTermLinkRange; ACols: Integer): Integer;
begin
  Result := ACols * (R.EndY - R.StartY) + (R.EndX - R.StartX + 1);
end;

{ ---- TTyTermSelectionModel ---------------------------------------------------------- }

constructor TTyTermSelectionModel.Create(ABuffers: TTyTerminalBufferService);
begin
  inherited Create;
  FBuffers := ABuffers;
end;

procedure TTyTermSelectionModel.Clear;                                      { :43-48 }
begin
  HasStart := False;
  HasEnd := False;
  IsSelectAllActive := False;
  StartLength := 0;
end;

function TTyTermSelectionModel.FinalStart(out P: TTyTermSelPoint): Boolean;  { :53-63 }
begin
  P := SelPoint(0, 0);
  if IsSelectAllActive then
    Exit(True);
  if not HasEnd or not HasStart then
  begin
    if HasStart then P := Start;
    Exit(HasStart);
  end;
  if AreReversed then P := Finish else P := Start;
  Result := True;
end;

function TTyTermSelectionModel.FinalEnd(out P: TTyTermSelPoint): Boolean;    { :69-104 }
var
  cols, spl: Integer;
begin
  P := SelPoint(0, 0);
  cols := FBuffers.Cols;
  if IsSelectAllActive then
  begin
    P := SelPoint(cols, FBuffers.Buffer.YBase + FBuffers.Rows - 1);
    Exit(True);
  end;
  if not HasStart then
    Exit(False);
  Result := True;
  { the start plus its length when there is no end, or the two are reversed }
  if not HasEnd or AreReversed then
  begin
    spl := Start.Col + StartLength;
    if spl > cols then
    begin
      { a selection ending on the right edge does not take the next line's start }
      if spl mod cols = 0 then
        P := SelPoint(cols, Start.Row + spl div cols - 1)
      else
        P := SelPoint(spl mod cols, Start.Row + spl div cols);
      Exit;
    end;
    P := SelPoint(spl, Start.Row);
    Exit;
  end;
  { a double or triple click's word or line stays selected }
  if (StartLength <> 0) and (Finish.Row = Start.Row) then
  begin
    spl := Start.Col + StartLength;
    if spl > cols then
    begin
      P := SelPoint(spl mod cols, Start.Row + spl div cols);
      Exit;
    end;
    if spl > Finish.Col then
      P := SelPoint(spl, Finish.Row)
    else
      P := Finish;
    Exit;
  end;
  P := Finish;
end;

function TTyTermSelectionModel.AreReversed: Boolean;                        { :109-116 }
begin
  if not HasStart or not HasEnd then
    Exit(False);
  Result := (Start.Row > Finish.Row) or ((Start.Row = Finish.Row) and (Start.Col > Finish.Col));
end;

function TTyTermSelectionModel.HandleTrim(AAmount: Integer): Boolean;       { :123-144 }
begin
  if HasStart then
    Dec(Start.Row, AAmount);
  if HasEnd then
    Dec(Finish.Row, AAmount);
  { moved off the buffer: gone }
  if HasEnd and (Finish.Row < 0) then
  begin
    Clear;
    Exit(True);
  end;
  { the start row trimmed away: the buffer's origin }
  if HasStart and (Start.Row < 0) then
  begin
    Start := SelPoint(0, 0);
    Exit(True);
  end;
  Result := False;
end;

{ ---- TTyTermSelection ------------------------------------------------------------- }

constructor TTyTermSelection.Create(ABuffers: TTyTerminalBufferService);
begin
  inherited Create;
  FBuffers := ABuffers;
  FModel := TTyTermSelectionModel.Create(ABuffers);
  FMode := tsmNormal;
  FSeparators := UnicodeString(TyTermDefaultWordSeparators);
end;

destructor TTyTermSelection.Destroy;
begin
  FModel.Free;
  inherited Destroy;
end;

function TTyTermSelection.Cols: Integer;
begin
  Result := FBuffers.Cols;
end;

function TTyTermSelection.Buffer: TTyTerminalBuffer;
begin
  Result := FBuffers.Buffer;
end;

procedure TTyTermSelection.Redraw;
begin
  if Assigned(FOnRedraw) then
    FOnRedraw(Self);
end;

procedure TTyTermSelection.Changed;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TTyTermSelection.Detach(AWhich: TTyTermOldAlias);
begin
  if FOldStartAlias = AWhich then FOldStartAlias := toaNone;
  if FOldEndAlias = AWhich then FOldEndAlias := toaNone;
end;

procedure TTyTermSelection.PutStart(const P: TTyTermSelPoint);
begin
  Detach(toaStart);
  FModel.Start := P;
  FModel.HasStart := True;
end;

procedure TTyTermSelection.PutEnd(const P: TTyTermSelPoint);
begin
  Detach(toaEnd);
  FModel.Finish := P;
  FModel.HasEnd := True;
end;

procedure TTyTermSelection.DropEnd;
begin
  Detach(toaEnd);
  FModel.HasEnd := False;
end;

procedure TTyTermSelection.ClearModel;
begin
  Detach(toaStart);
  Detach(toaEnd);
  FModel.Clear;
end;

procedure TTyTermSelection.NudgeStartCol(ADelta: Integer);
begin
  Inc(FModel.Start.Col, ADelta);
  if FOldStartAlias = toaStart then Inc(FOldStart.Col, ADelta);
  if FOldEndAlias = toaStart then Inc(FOldEnd.Col, ADelta);
end;

procedure TTyTermSelection.SetEndInPlace(ACol, ARow: Integer; ASetCol: Boolean);
begin
  if ASetCol then FModel.Finish.Col := ACol;
  FModel.Finish.Row := ARow;
  if FOldStartAlias = toaEnd then
  begin
    if ASetCol then FOldStart.Col := ACol;
    FOldStart.Row := ARow;
  end;
  if FOldEndAlias = toaEnd then
  begin
    if ASetCol then FOldEnd.Col := ACol;
    FOldEnd.Row := ARow;
  end;
end;

function TTyTermSelection.FinalStartAlias(out P: TTyTermSelPoint; out AAlias: TTyTermOldAlias): Boolean;
begin
  Result := FModel.FinalStart(P);
  AAlias := toaNone;
  if not Result or FModel.IsSelectAllActive then
    Exit;
  if FModel.HasEnd and FModel.AreReversed then
    AAlias := toaEnd
  else
    AAlias := toaStart;
end;

function TTyTermSelection.FinalEndAlias(out P: TTyTermSelPoint; out AAlias: TTyTermOldAlias): Boolean;
begin
  Result := FModel.FinalEnd(P);
  AAlias := toaNone;
  if not Result or FModel.IsSelectAllActive then
    Exit;
  { finalSelectionEnd answers the model's own array only on its last line (:103) }
  if FModel.HasEnd and not FModel.AreReversed
    and not ((FModel.StartLength <> 0) and (FModel.Finish.Row = FModel.Start.Row)) then
    AAlias := toaEnd;
end;

procedure TTyTermSelection.FireOnSelectionChange(AHasStart: Boolean; const AStart: TTyTermSelPoint;
  AStartAlias: TTyTermOldAlias; AHasEnd: Boolean; const AEnd: TTyTermSelPoint;
  AEndAlias: TTyTermOldAlias; AHas: Boolean);
begin                                                                        { :771-776 }
  FOldHasStart := AHasStart;
  FOldStart := AStart;
  FOldStartAlias := AStartAlias;
  FOldHasEnd := AHasEnd;
  FOldEnd := AEnd;
  FOldEndAlias := AEndAlias;
  FOldHas := AHas;
  Changed;
end;

procedure TTyTermSelection.FireEventIfSelectionChanged;                     { :746-769 }
var
  s, e: TTyTermSelPoint;
  hs, he, has: Boolean;
  sa, ea: TTyTermOldAlias;
begin
  hs := FinalStartAlias(s, sa);
  he := FinalEndAlias(e, ea);
  has := hs and he and not SamePoint(s, e);
  if not has then
  begin
    if FOldHas then
      FireOnSelectionChange(hs, s, sa, he, e, ea, has);
    Exit;
  end;
  if not FOldHasStart or not FOldHasEnd or not SamePoint(s, FOldStart) or not SamePoint(e, FOldEnd) then
    FireOnSelectionChange(hs, s, sa, he, e, ea, has);
end;

function TTyTermSelection.HasSelection: Boolean;
var
  s, e: TTyTermSelPoint;
begin
  if not FModel.FinalStart(s) or not FModel.FinalEnd(e) then
    Exit(False);
  Result := not SamePoint(s, e);
end;

function TTyTermSelection.FinalStart(out P: TTyTermSelPoint): Boolean;
begin
  Result := FModel.FinalStart(P);
end;

function TTyTermSelection.FinalEnd(out P: TTyTermSelPoint): Boolean;
begin
  Result := FModel.FinalEnd(P);
end;

function TTyTermSelection.Text(const ALineSep: string): string;
var
  s, e: TTyTermSelPoint;
  pieces: array of string;
  joins: array of Boolean;
  n, i, startCol, endCol, firstEnd, total, at: Integer;
  line: TTyTerminalLine;

  { one row's piece; AJoin: a wrapped row goes on the one before it, no separator }
  procedure Add(const AText: string; AJoin: Boolean);
  begin
    if n = Length(pieces) then
    begin
      SetLength(pieces, n * 2 + 16);
      SetLength(joins, n * 2 + 16);
    end;
    { NBSP as a space: a piece is whole UTF-8, so piece by piece is the same as on the
      joined text }
    if Pos(#$C2#$A0, AText) > 0 then
      pieces[n] := StringReplace(AText, #$C2#$A0, ' ', [rfReplaceAll])
    else
      pieces[n] := AText;
    joins[n] := AJoin and (n > 0);
    Inc(n);
  end;

begin                                                                        { :203-262 }
  Inc(FTextBuilds);
  if not FModel.FinalStart(s) or not FModel.FinalEnd(e) then
    Exit('');
  n := 0;
  pieces := nil;
  joins := nil;
  if FMode = tsmColumn then
  begin
    { a zero-width column is nothing }
    if s.Col = e.Col then
      Exit('');
    if s.Col < e.Col then
    begin
      startCol := s.Col;
      endCol := e.Col;
    end
    else
    begin
      startCol := e.Col;
      endCol := s.Col;
    end;
    for i := s.Row to e.Row do
      Add(Buffer.TranslateBufferLineToString(i, True, startCol, endCol), False);
  end
  else
  begin
    if s.Row = e.Row then firstEnd := e.Col else firstEnd := -1;
    Add(Buffer.TranslateBufferLineToString(s.Row, True, s.Col, firstEnd), False);
    for i := s.Row + 1 to e.Row - 1 do
    begin
      line := Buffer.Lines.Get(i);
      Add(Buffer.TranslateBufferLineToString(i, True), (line <> nil) and line.IsWrapped);
    end;
    if s.Row <> e.Row then
    begin
      line := Buffer.Lines.Get(e.Row);
      Add(Buffer.TranslateBufferLineToString(e.Row, True, 0, e.Col), (line <> nil) and line.IsWrapped);
    end;
  end;
  { two passes: the length first, then one string filled in (a ten-thousand-row
    selection would otherwise be rebuilt row by row) }
  total := 0;
  for i := 0 to n - 1 do
  begin
    Inc(total, Length(pieces[i]));
    if (i > 0) and not joins[i] then
      Inc(total, Length(ALineSep));
  end;
  SetLength(Result, total);
  at := 1;
  for i := 0 to n - 1 do
  begin
    if (i > 0) and not joins[i] and (ALineSep <> '') then
    begin
      Move(ALineSep[1], Result[at], Length(ALineSep));
      Inc(at, Length(ALineSep));
    end;
    if pieces[i] <> '' then
    begin
      Move(pieces[i][1], Result[at], Length(pieces[i]));
      Inc(at, Length(pieces[i]));
    end;
  end;
end;

function TTyTermSelection.RowSpan(AAbsRow: Integer; out AFrom, ATo: Integer): Boolean;
var
  s, e: TTyTermSelPoint;
  c: Integer;
begin                                                   { DomRendererRowFactory.ts:534-552 }
  AFrom := 0;
  ATo := 0;
  if not FModel.FinalStart(s) or not FModel.FinalEnd(e) then
    Exit(False);
  c := Cols;
  if FMode = tsmColumn then
  begin
    if (AAbsRow < s.Row) or (AAbsRow > e.Row) then
      Exit(False);
    if s.Col <= e.Col then
    begin
      AFrom := s.Col;
      ATo := e.Col;
    end
    else
    begin
      AFrom := e.Col;
      ATo := s.Col;
    end;
  end
  else if (AAbsRow > s.Row) and (AAbsRow < e.Row) then
  begin
    AFrom := 0;
    ATo := c;
  end
  else if (s.Row = e.Row) and (AAbsRow = s.Row) then
  begin
    AFrom := s.Col;
    ATo := e.Col;
  end
  else if (s.Row < e.Row) and (AAbsRow = e.Row) then
  begin
    AFrom := 0;
    ATo := e.Col;
  end
  else if (s.Row < e.Row) and (AAbsRow = s.Row) then
  begin
    AFrom := s.Col;
    ATo := c;
  end
  else
    Exit(False);
  if AFrom < 0 then AFrom := 0;
  if ATo > c then ATo := c;
  Result := AFrom < ATo;
  if not Result then
  begin
    AFrom := 0;
    ATo := 0;
  end;
end;

function TTyTermSelection.AreCoordsInSelection(const P, S, E: TTyTermSelPoint): Boolean;
begin                                                                        { :333-338 }
  Result := ((P.Row > S.Row) and (P.Row < E.Row))
    or ((S.Row = E.Row) and (P.Row = S.Row) and (P.Col >= S.Col) and (P.Col < E.Col))
    or ((S.Row < E.Row) and (P.Row = E.Row) and (P.Col < E.Col))
    or ((S.Row < E.Row) and (P.Row = S.Row) and (P.Col >= S.Col));
end;

function TTyTermSelection.IsClickInSelection(const P: TTyTermSelPoint): Boolean;
var
  s, e: TTyTermSelPoint;
begin                                                                        { :312-322 }
  if not FModel.FinalStart(s) or not FModel.FinalEnd(e) then
    Exit(False);
  Result := AreCoordsInSelection(P, s, e);
end;

{ _isCharWordSeparator :1034-1041. A width-0 cell (a wide character's second half)
  never is; otherwise wordSeparator.indexOf(chars) >= 0, and indexOf('') is 0: a cell
  never written IS one. }
function TTyTermSelection.IsCharWordSeparator(ALine: TTyTerminalLine; ACol: Integer): Boolean;
var
  chars: string;
begin
  if ALine.GetWidth(ACol) = 0 then
    Exit(False);
  chars := ALine.GetChars(ACol);
  if chars = '' then
    Exit(True);
  Result := Pos(UTF8Decode(chars), FSeparators) > 0;
end;

{ :793-809 }
function TTyTermSelection.ConvertViewportColToCharacterIndex(ALine: TTyTerminalLine; AX: Integer): Integer;
var
  i, len: Integer;
begin
  Result := AX;
  i := 0;
  while AX >= i do
  begin
    len := Utf16Len(ALine.GetChars(i));
    if ALine.GetWidth(i) = 0 then
      { a wide character's second half is not in the string: back onto the character }
      Dec(Result)
    else if (len > 1) and (AX <> i) then
      { a string longer than one unit (an emoji) left of the column }
      Inc(Result, len - 1);
    Inc(i);
  end;
end;

{ _getWordAt :833-950, the row itself }
function TTyTermSelection.GetWordAtRow(const P: TTyTermSelPoint; AAllowWhitespaceOnly: Boolean;
  out AStart, ALength: Integer): Boolean;
var
  line: TTyTerminalLine;
  s: UnicodeString;
  startIndex, endIndex, charOffset, leftWide, rightWide, leftLong, rightLong: Integer;
  startCol, endCol, len, c: Integer;
begin
  AStart := 0;
  ALength := 0;
  c := Cols;
  { within the viewport (not on a scroll bar) }
  if P.Col >= c then
    Exit(False);
  line := Buffer.Lines.Get(P.Row);
  if line = nil then
    Exit(False);
  s := UTF8Decode(Buffer.TranslateBufferLineToString(P.Row, False));

  startIndex := ConvertViewportColToCharacterIndex(line, P.Col);
  endIndex := startIndex;
  charOffset := P.Col - startIndex;
  leftWide := 0;
  rightWide := 0;
  leftLong := 0;
  rightLong := 0;

  if IsSpaceAt(s, startIndex) then
  begin
    { a run of spaces }
    while (startIndex > 0) and IsSpaceAt(s, startIndex - 1) do
      Dec(startIndex);
    while (endIndex < Length(s)) and IsSpaceAt(s, endIndex + 1) do
      Inc(endIndex);
  end
  else
  begin
    { out to the separators, keeping the string index and the column in step }
    startCol := P.Col;
    endCol := P.Col;
    if line.GetWidth(startCol) = 0 then
    begin
      Inc(leftWide);
      Dec(startCol);
    end;
    if line.GetWidth(endCol) = 2 then
    begin
      Inc(rightWide);
      Inc(endCol);
    end;
    len := Utf16Len(line.GetChars(endCol));
    if len > 1 then
    begin
      Inc(rightLong, len - 1);
      Inc(endIndex, len - 1);
    end;
    while (startCol > 0) and (startIndex > 0) and not IsCharWordSeparator(line, startCol - 1) do
    begin
      len := Utf16Len(line.GetChars(startCol - 1));
      if line.GetWidth(startCol - 1) = 0 then
      begin
        Inc(leftWide);
        Dec(startCol);
      end
      else if len > 1 then
      begin
        Inc(leftLong, len - 1);
        Dec(startIndex, len - 1);
      end;
      Dec(startIndex);
      Dec(startCol);
    end;
    while (endCol < line.Length) and (endIndex + 1 < Length(s)) and not IsCharWordSeparator(line, endCol + 1) do
    begin
      len := Utf16Len(line.GetChars(endCol + 1));
      if line.GetWidth(endCol + 1) = 2 then
      begin
        Inc(rightWide);
        Inc(endCol);
      end
      else if len > 1 then
      begin
        Inc(rightLong, len - 1);
        Inc(endIndex, len - 1);
      end;
      Inc(endIndex);
      Inc(endCol);
    end;
  end;

  { to the start of the next character }
  Inc(endIndex);

  { string indices back to columns }
  AStart := startIndex + charOffset - leftWide + leftLong;
  ALength := endIndex - startIndex + leftWide + rightWide - leftLong - rightLong;
  if ALength > c then
    ALength := c;

  if not AAllowWhitespaceOnly and SliceIsBlank(s, startIndex, endIndex) then
    Exit(False);
  Result := True;
end;

{ _getWordAt :833-981. Upstream recurses once per wrapped row the word runs across
  (:952-978: upwards with followAbove only, downwards with followBelow only); a word
  wrapped over thousands of rows would take as deep a stack, so the two chains are
  walked in loops here. The sums are the same: each row above adds (cols - its word's
  start), each row below its word's length, and a row is followed on only while its
  own word (before any following) touches the edge. }
function TTyTermSelection.GetWordAt(const P: TTyTermSelPoint; AAllowWhitespaceOnly, AFollowAbove,
  AFollowBelow: Boolean; out AStart, ALength: Integer): Boolean;
var
  line, other: TTyTerminalLine;
  c, row, ws, wl, wordStart, wordEnd, grow: Integer;
begin
  Result := GetWordAtRow(P, AAllowWhitespaceOnly, AStart, ALength);
  if not Result then
    Exit;
  c := Cols;
  { the word ends where the row's own word ends, whatever is added above }
  wordEnd := AStart + ALength;

  { the word runs on from the wrapped line above }
  if AFollowAbove then
  begin
    grow := 0;
    row := P.Row;
    wordStart := AStart;
    line := Buffer.Lines.Get(row);
    while (line <> nil) and (wordStart = 0) and (line.GetCodePoint(0) <> 32) do
    begin
      other := Buffer.Lines.Get(row - 1);
      if (other = nil) or not line.IsWrapped or (other.GetCodePoint(c - 1) = 32) then Break;
      if not GetWordAtRow(SelPoint(c - 1, row - 1), False, ws, wl) then Break;
      Inc(grow, c - ws);
      Dec(row);
      line := other;
      wordStart := ws;
    end;
    Dec(AStart, grow);
    Inc(ALength, grow);
  end;

  { ... and on into the wrapped line below }
  if AFollowBelow then
  begin
    row := P.Row;
    line := Buffer.Lines.Get(row);
    while (line <> nil) and (wordEnd = c) and (line.GetCodePoint(c - 1) <> 32) do
    begin
      other := Buffer.Lines.Get(row + 1);
      if (other = nil) or not other.IsWrapped or (other.GetCodePoint(0) = 32) then Break;
      if not GetWordAtRow(SelPoint(0, row + 1), False, ws, wl) then Break;
      Inc(ALength, wl);
      Inc(row);
      line := other;
      wordEnd := ws + wl;
    end;
  end;
end;

procedure TTyTermSelection.SelectWordAt(const P: TTyTermSelPoint; AAllowWhitespaceOnly: Boolean);
var
  st, len, row: Integer;
begin                                                                        { :988-999 }
  if GetWordAt(P, AAllowWhitespaceOnly, True, True, st, len) then
  begin
    row := P.Row;
    while st < 0 do
    begin
      Inc(st, Cols);
      Dec(row);
    end;
    PutStart(SelPoint(st, row));
    FModel.StartLength := len;
  end;
end;

procedure TTyTermSelection.SelectToWordAt(const P: TTyTermSelPoint);
var
  st, len, endRow: Integer;
begin                                                                        { :1005-1027 }
  if GetWordAt(P, True, True, True, st, len) then
  begin
    endRow := P.Row;
    while st < 0 do
    begin
      Inc(st, Cols);
      Dec(endRow);
    end;
    { only a forward selection wants the word's end, which may wrap }
    if not FModel.AreReversed then
      while st + len > Cols do
      begin
        Dec(len, Cols);
        Inc(endRow);
      end;
    if FModel.AreReversed then
      PutEnd(SelPoint(st, endRow))
    else
      PutEnd(SelPoint(st + len, endRow));
  end;
end;

function TTyTermSelection.SelectWordAtCursor(const P: TTyTermSelPoint; AAllowWhitespaceOnly: Boolean;
  ALink: PTyTermLinkRange): Boolean;
begin                                                                        { :344-361 }
  { a link under the pointer is taken whole }
  if ALink <> nil then
  begin
    PutStart(SelPoint(ALink^.StartX - 1, ALink^.StartY - 1));
    FModel.StartLength := RangeLength(ALink^, Cols);
    DropEnd;
    Exit(True);
  end;
  SelectWordAt(P, AAllowWhitespaceOnly);
  DropEnd;
  Result := True;
end;

procedure TTyTermSelection.SelectLineAt(ARow: Integer);
var
  first, last: Integer;
  r: TTyTermLinkRange;
begin                                                                       { :1047-1056 }
  Buffer.GetWrappedRangeForLine(ARow, first, last);
  r.StartX := 0;
  r.StartY := first;
  r.EndX := Cols - 1;
  r.EndY := last;
  PutStart(SelPoint(0, first));
  DropEnd;
  FModel.StartLength := RangeLength(r, Cols);
end;

procedure TTyTermSelection.SingleClick(const P: TTyTermSelPoint; AColumn: Boolean);
var
  hadSelection: Boolean;
  line: TTyTerminalLine;
  s, e: TTyTermSelPoint;
  hs, he: Boolean;
  sa, ea: TTyTermOldAlias;
begin                                                                        { :542-578 }
  hadSelection := HasSelection;
  FModel.StartLength := 0;
  FModel.IsSelectAllActive := False;
  if AColumn then FMode := tsmColumn else FMode := tsmNormal;
  PutStart(P);
  DropEnd;
  { a selection went away }
  if hadSelection then
  begin
    hs := FinalStartAlias(s, sa);
    he := FinalEndAlias(e, ea);
    FireOnSelectionChange(hs, s, sa, he, e, ea, False);
  end;
  line := Buffer.Lines.Get(FModel.Start.Row);
  if line = nil then
    Exit;
  { off the buffer (on the right edge) }
  if line.Length = FModel.Start.Col then
    Exit;
  { on a wide character's second half: take the whole character }
  if not line.HasWidth(FModel.Start.Col) then
    NudgeStartCol(1);
end;

procedure TTyTermSelection.IncrementalClick(const P: TTyTermSelPoint);
begin                                                                        { :531-535 }
  if FModel.HasStart then
    PutEnd(P);
end;

procedure TTyTermSelection.Press(const APoint: TTyTermSelPoint; AClicks: Integer;
  AIncremental, AColumn: Boolean; ALink: PTyTermLinkRange);
begin                                                                        { :483-499 }
  FDragScrollAmount := 0;
  if AIncremental then
    IncrementalClick(APoint)
  else
    case AClicks of
      1: SingleClick(APoint, AColumn);
      2: if SelectWordAtCursor(APoint, True, ALink) then FMode := tsmWord;       { :584-588 }
      3:
        begin                                                                    { :595-601 }
          FMode := tsmLine;
          SelectLineAt(APoint.Row);
        end;
    end;
  FDragging := True;
  Redraw;
end;

procedure TTyTermSelection.DragTo(const APoint: TTyTermSelPoint; AScrollAmount: Integer);
var
  hadEnd: Boolean;
  prev: TTyTermSelPoint;
  line: TTyTerminalLine;
  c: Integer;
begin                                                                        { :619-686 }
  { no start: the first click was an extension }
  if not FModel.HasStart then
    Exit;
  hadEnd := FModel.HasEnd;
  prev := FModel.Finish;
  c := Cols;
  PutEnd(APoint);
  if FMode = tsmLine then
  begin
    if FModel.Finish.Row < FModel.Start.Row then
      FModel.Finish.Col := 0
    else
      FModel.Finish.Col := c;
  end
  else if FMode = tsmWord then
    SelectToWordAt(FModel.Finish);
  FDragScrollAmount := AScrollAmount;
  { dragged above or below the viewport: its first or last column }
  if FMode <> tsmColumn then
  begin
    if FDragScrollAmount > 0 then
      FModel.Finish.Col := c
    else if FDragScrollAmount < 0 then
      FModel.Finish.Col := 0;
  end;
  { a wide character takes the cell to its right too }
  if FModel.Finish.Row < Buffer.Lines.Length then
  begin
    line := Buffer.Lines.Get(FModel.Finish.Row);
    if (line <> nil) and not line.HasWidth(FModel.Finish.Col) and (FModel.Finish.Col < c) then
      Inc(FModel.Finish.Col);
  end;
  if not hadEnd or not SamePoint(prev, FModel.Finish) then
    Redraw;
end;

function TTyTermSelection.DragScrollAmount: Integer;
begin                                                                        { :693-696 }
  if not FModel.HasEnd or not FModel.HasStart then
    Exit(0);
  Result := FDragScrollAmount;
end;

procedure TTyTermSelection.AfterDragScroll;
var
  buf: TTyTerminalBuffer;
  row: Integer;
begin                                                                        { :698-715 }
  if not FModel.HasEnd or not FModel.HasStart or (FDragScrollAmount = 0) then
    Exit;
  buf := Buffer;
  if FDragScrollAmount > 0 then
  begin
    row := buf.YDisp + FBuffers.Rows - 1;
    if row > buf.Lines.Length - 1 then
      row := buf.Lines.Length - 1;
    SetEndInPlace(Cols, row, FMode <> tsmColumn);
  end
  else
    SetEndInPlace(0, buf.YDisp, FMode <> tsmColumn);
  Redraw;
end;

procedure TTyTermSelection.Release;
begin                                                                        { :722-744 }
  FDragging := False;
  FireEventIfSelectionChanged;
end;

procedure TTyTermSelection.RightClickSelect(const APoint: TTyTermSelPoint; ALink: PTyTermLinkRange);
begin                                                                        { :820-827 }
  if not IsClickInSelection(APoint) then
  begin
    if SelectWordAtCursor(APoint, False, ALink) then
      Redraw;
    FireEventIfSelectionChanged;
  end;
end;

procedure TTyTermSelection.SelectAll;
begin
  FModel.IsSelectAllActive := True;
  Redraw;
  Changed;
end;

procedure TTyTermSelection.SelectLines(AFirst, ALast: Integer);
begin
  ClearModel;
  if AFirst < 0 then AFirst := 0;
  if ALast > Buffer.Lines.Length - 1 then ALast := Buffer.Lines.Length - 1;
  PutStart(SelPoint(0, AFirst));
  PutEnd(SelPoint(Cols, ALast));
  Redraw;
  Changed;
end;

procedure TTyTermSelection.SetSelection(ACol, ARow, ALength: Integer);
begin
  ClearModel;
  FDragging := False;
  PutStart(SelPoint(ACol, ARow));
  FModel.StartLength := ALength;
  Redraw;
  FireEventIfSelectionChanged;
end;

procedure TTyTermSelection.Clear;
begin
  ClearModel;
  FDragging := False;
  Redraw;
  Changed;
end;

procedure TTyTermSelection.HandleTrim(AAmount: Integer);
begin
  { the live points move in place: what shares them moves too (unit header) }
  if FModel.HasStart then
  begin
    if FOldStartAlias = toaStart then Dec(FOldStart.Row, AAmount);
    if FOldEndAlias = toaStart then Dec(FOldEnd.Row, AAmount);
  end;
  if FModel.HasEnd then
  begin
    if FOldStartAlias = toaEnd then Dec(FOldStart.Row, AAmount);
    if FOldEndAlias = toaEnd then Dec(FOldEnd.Row, AAmount);
  end;
  if FModel.HandleTrim(AAmount) then
  begin
    { cleared, or a new start at the origin }
    if not FModel.HasStart then
    begin
      Detach(toaStart);
      Detach(toaEnd);
    end
    else
      Detach(toaStart);
    Redraw;
  end;
end;

{ ---- geometry -------------------------------------------------------------------- }

function TyTermSelectionPointAt(APx, APy, ACellW, ACellH, ACols, ARows: Integer): TPoint;
begin
  { upstream: ceil((px + 0.5 + w / 2) / w) - 1 and ceil((py + 0.5) / h) - 1, which for
    whole pixels are these; a negative pixel clamps to 0 either way }
  if (ACellW <= 0) or (ACellH <= 0) then
    Exit(Point(0, 0));
  if APx < 0 then
    Result.X := 0
  else
    Result.X := (2 * APx + ACellW) div (2 * ACellW);
  if APy < 0 then
    Result.Y := 0
  else
    Result.Y := APy div ACellH;
  if Result.X > ACols then Result.X := ACols;
  if Result.X < 0 then Result.X := 0;
  if Result.Y > ARows - 1 then Result.Y := ARows - 1;
  if Result.Y < 0 then Result.Y := 0;
end;

function TyTermDragScrollAmount(AOffsetY, AHeight, AThreshold: Integer): Integer;
var
  offset, t: Double;
begin
  offset := AOffsetY + 0.5;                  { the pixel's centre }
  if (offset >= 0) and (offset <= AHeight) then
    Exit(0);
  if offset > AHeight then
    offset := offset - AHeight;
  if AThreshold < 1 then
    AThreshold := 1;
  t := AThreshold;
  if offset < -t then offset := -t;
  if offset > t then offset := t;
  offset := offset / t;
  { offset / |offset| + Math.round(offset * 14); Math.round is floor(x + 0.5) }
  if offset < 0 then
    Result := -1
  else
    Result := 1;
  Result := Result + Floor(offset * (TyTermDragScrollMaxSpeed - 1) + 0.5);
end;

{ ---- OSC 52 ------------------------------------------------------------------------ }

function TyTermOsc52Split(const AData: string; out APc, APd: string): Boolean;
var
  p, q: Integer;
begin
  APc := '';
  APd := '';
  p := Pos(';', AData);
  if p = 0 then
    Exit(False);
  APc := Copy(AData, 1, p - 1);
  q := Pos(';', AData, p + 1);
  if q = 0 then
    APd := Copy(AData, p + 1, MaxInt)
  else
    APd := Copy(AData, p + 1, q - p - 1);
  Result := True;
end;

function B64Value(c: Char): Integer; inline;
begin
  case c of
    'A'..'Z': Result := Ord(c) - Ord('A');
    'a'..'z': Result := Ord(c) - Ord('a') + 26;
    '0'..'9': Result := Ord(c) - Ord('0') + 52;
    '+': Result := 62;
    '/': Result := 63;
  else
    Result := -1;
  end;
end;

{ WHATWG forgiving-base64 decode (what atob does); False on failure }
function ForgivingBase64(const S: string; out ABytes: RawByteString): Boolean;
var
  t: string;
  i, n, v, bits, acc, o: Integer;
begin
  ABytes := '';
  SetLength(t, Length(S));
  n := 0;
  for i := 1 to Length(S) do
    if not (S[i] in [#9, #10, #12, #13, #32]) then
    begin
      Inc(n);
      t[n] := S[i];
    end;
  SetLength(t, n);
  if (n mod 4 = 0) and (n > 0) and (t[n] = '=') then
  begin
    Dec(n);
    if (n > 0) and (t[n] = '=') then
      Dec(n);
    SetLength(t, n);
  end;
  if n mod 4 = 1 then
    Exit(False);
  for i := 1 to n do
    if B64Value(t[i]) < 0 then
      Exit(False);
  SetLength(ABytes, (n * 6) div 8);
  o := 0;
  acc := 0;
  bits := 0;
  for i := 1 to n do
  begin
    v := B64Value(t[i]);
    acc := (acc shl 6) or v;
    Inc(bits, 6);
    if bits >= 8 then
    begin
      Dec(bits, 8);
      Inc(o);
      ABytes[o] := Chr((acc shr bits) and $FF);
      acc := acc and ((1 shl bits) - 1);
    end;
  end;
  SetLength(ABytes, o);
  Result := True;
end;

procedure AppendCp(var R: string; var N: Integer; c: Cardinal);
begin
  if N + 4 > Length(R) then
    SetLength(R, Length(R) * 2 + 16);
  if c < $80 then
  begin
    Inc(N); R[N] := Chr(c);
  end
  else if c < $800 then
  begin
    Inc(N); R[N] := Chr($C0 or (c shr 6));
    Inc(N); R[N] := Chr($80 or (c and $3F));
  end
  else if c < $10000 then
  begin
    Inc(N); R[N] := Chr($E0 or (c shr 12));
    Inc(N); R[N] := Chr($80 or ((c shr 6) and $3F));
    Inc(N); R[N] := Chr($80 or (c and $3F));
  end
  else
  begin
    Inc(N); R[N] := Chr($F0 or (c shr 18));
    Inc(N); R[N] := Chr($80 or ((c shr 12) and $3F));
    Inc(N); R[N] := Chr($80 or ((c shr 6) and $3F));
    Inc(N); R[N] := Chr($80 or (c and $3F));
  end;
end;

{ The WHATWG UTF-8 decoder (TextDecoder, BOM not ignored): the text as UTF-8 again,
  every bad sequence one U+FFFD per maximal subpart, a leading U+FEFF dropped. }
function WhatwgUtf8(const ABytes: RawByteString): string;
var
  i, n, needed, seen: Integer;
  cp, lower, upper, b: Cardinal;
  first: Boolean;
  r: string;

  procedure Emit(c: Cardinal);
  begin
    if first then
    begin
      first := False;
      if c = $FEFF then
        Exit;
    end;
    AppendCp(r, n, c);
  end;

begin
  r := '';
  SetLength(r, Length(ABytes) + 16);
  n := 0;
  needed := 0;
  seen := 0;
  cp := 0;
  lower := $80;
  upper := $BF;
  first := True;
  i := 1;
  while i <= Length(ABytes) do
  begin
    b := Ord(ABytes[i]);
    if needed = 0 then
    begin
      case b of
        $00..$7F: Emit(b);
        $C2..$DF:
          begin
            needed := 1;
            cp := b and $1F;
          end;
        $E0..$EF:
          begin
            if b = $E0 then lower := $A0;
            if b = $ED then upper := $9F;
            needed := 2;
            cp := b and $F;
          end;
        $F0..$F4:
          begin
            if b = $F0 then lower := $90;
            if b = $F4 then upper := $8F;
            needed := 3;
            cp := b and 7;
          end;
      else
        Emit($FFFD);
      end;
      Inc(i);
      Continue;
    end;
    if (b < lower) or (b > upper) then
    begin
      { the byte starts over (prepended to the stream) }
      cp := 0;
      needed := 0;
      seen := 0;
      lower := $80;
      upper := $BF;
      Emit($FFFD);
      Continue;
    end;
    lower := $80;
    upper := $BF;
    cp := (cp shl 6) or (b and $3F);
    Inc(seen);
    Inc(i);
    if seen = needed then
    begin
      Emit(cp);
      cp := 0;
      needed := 0;
      seen := 0;
    end;
  end;
  if needed <> 0 then
    Emit($FFFD);
  SetLength(r, n);
  Result := r;
end;

function TyTermOsc52Decode(const APd: string): string;
var
  bytes: RawByteString;
begin
  if not ForgivingBase64(APd, bytes) then
    Exit('');
  Result := WhatwgUtf8(bytes);
end;

function TyTermBase64Encode(const ABytes: RawByteString): string;
const
  Alphabet: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
var
  i, n, o: Integer;
  v: Cardinal;
begin
  n := Length(ABytes);
  SetLength(Result, ((n + 2) div 3) * 4);
  o := 0;
  i := 1;
  while i <= n do
  begin
    v := Cardinal(Ord(ABytes[i])) shl 16;
    if i + 1 <= n then v := v or (Cardinal(Ord(ABytes[i + 1])) shl 8);
    if i + 2 <= n then v := v or Cardinal(Ord(ABytes[i + 2]));
    Result[o + 1] := Alphabet[((v shr 18) and $3F) + 1];
    Result[o + 2] := Alphabet[((v shr 12) and $3F) + 1];
    if i + 1 <= n then
      Result[o + 3] := Alphabet[((v shr 6) and $3F) + 1]
    else
      Result[o + 3] := '=';
    if i + 2 <= n then
      Result[o + 4] := Alphabet[(v and $3F) + 1]
    else
      Result[o + 4] := '=';
    Inc(o, 4);
    Inc(i, 3);
  end;
end;

function TyTermOsc52Reply(const APc, AText: string): RawByteString;
begin                                                            { ClipboardAddon.ts:27-30 }
  Result := #27']52;' + APc + ';' + TyTermBase64Encode(AText) + #7;
end;

end.
