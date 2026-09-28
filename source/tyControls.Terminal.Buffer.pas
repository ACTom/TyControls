unit tyControls.Terminal.Buffer;
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

{ The terminal's screen memory: cells, lines, the ring of lines, the normal and
  alternate buffers with their cursor, margins and tab stops, markers, the buffer
  service that scrolls and resizes, and the OSC 8 link table. No LCL.

  PORTED FROM xterm.js 6.0.0, commit c58ea3637f39:
    src/common/buffer/Constants.ts      the cell bit layout
    src/common/buffer/AttributeData.ts  TTyTerminalAttrData, TTyTerminalExtAttrs
    src/common/buffer/CellData.ts       TTyTerminalCellData
    src/common/buffer/BufferLine.ts     TTyTerminalLine
    src/common/CircularList.ts          TTyTerminalLineList
    src/common/buffer/Marker.ts         TTyTerminalMarker
    src/common/buffer/Buffer.ts         TTyTerminalBuffer (reflow not yet, see below)
    src/common/buffer/BufferSet.ts      TTyTerminalBufferSet
    src/common/services/BufferService.ts   TTyTerminalBufferService
    src/common/services/OscLinkService.ts  TTyTerminalOscLinks

    Copyright (c) 2017-2019, The xterm.js authors (https://github.com/xtermjs/xterm.js)
    Copyright (c) 2014-2016, SourceLair Private Company (https://www.sourcelair.com)
    Copyright (c) 2012-2013, Christopher Jeffrey (https://github.com/chjj/)
  MIT; the full text is in THIRD-PARTY-NOTICES.md.

  WHAT DIFFERS IN SHAPE (never in result):

  - Extended attributes are values. Upstream shares ExtendedAttrs objects between
    cells but clones before every change, so a record copy behaves the same.
  - Lines are reference counted (AddRef / Release, freed at zero; not atomic, the
    core is main-thread only). Every ring slot and the buffer service's cached blank
    line hold one reference; a line that is still needed across a change of the
    ring is pinned with AddRef. A new line starts at 1 and belongs to whoever made
    it: after handing it to the ring (Push / SetItem / Splice) that owner releases
    its own reference -- the *Owned helpers do both.
    Pinned in this unit: BufferService.Scroll's blank line (the service's cache).
    Buffer.Resize only touches lines between ring changes, and the link table holds
    markers, not lines. Pinned in tyControls.Terminal.Core: print's current and old
    row, and the cursor row that ClearScrollback moves to the top.
  - Markers are reference counted too: the buffer holds one while a marker is live,
    the link table one per marker it lists; a marker disposed is dropped by both.
  - Reflow is phase 5: IsReflowEnabled is always False, so the buffer resizes the
    way xterm.js does for an old ConPTY -- narrower columns keep the longer lines,
    wider ones pad them, nothing is rewrapped.
  - BufferService lives here, not in the core, so the buffer layer can be held to
    upstream on its own (the core owns one).

  The combined text and the extended attributes of a line are small arrays sorted by
  column, read only when the cell's flag says so -- like upstream's sparse objects,
  an entry can outlive its cell and is simply never read. }

interface

uses
  SysUtils, Classes, Types, tyControls.Unicode.Width;

const  { buffer/Constants.ts:36-157, names upper-camel with a TyTerm prefix, values identical }
  TyTermContentCodepointMask = $1FFFFF;
  TyTermContentIsCombinedMask = $200000;
  TyTermContentHasContentMask = $3FFFFF;
  TyTermContentWidthMask = $C00000;
  TyTermContentWidthShift = 22;
  TyTermAttrCmMask = $3000000;
  TyTermAttrCmDefault = 0;
  TyTermAttrCmP16 = $1000000;
  TyTermAttrCmP256 = $2000000;
  TyTermAttrCmRgb = $3000000;
  TyTermAttrRgbMask = $FFFFFF;
  TyTermAttrPColorMask = $FF;
  TyTermFgInverse = $4000000;
  TyTermFgBold = $8000000;
  TyTermFgUnderline = $10000000;
  TyTermFgBlink = $20000000;
  TyTermFgInvisible = $40000000;
  TyTermFgStrikethrough = $80000000;
  TyTermBgItalic = $4000000;
  TyTermBgDim = $8000000;
  TyTermBgHasExtended = $10000000;
  TyTermBgProtected = $20000000;
  TyTermBgOverline = $40000000;
  TyTermExtUnderlineStyle = $1C000000;
  TyTermExtVariantOffset = $E0000000;
  TyTermNullCellCode = 0;
  TyTermNullCellWidth = 1;
  TyTermWhitespaceCellCode = 32;
  TyTermMaxBufferSize = 4294967295;        { Buffer.ts:20 }
  TyTermMinimumCols = 2;                   { BufferService.ts MINIMUM_COLS }
  TyTermMinimumRows = 1;

type
  TTyTermUnderlineStyle = (tusNone, tusSingle, tusDouble, tusCurly, tusDotted, tusDashed);

  { ExtendedAttrs, AttributeData.ts:140-213 -- a value (unit header). Upstream's
    payload field is only used by the image addon and is not ported. }
  TTyTerminalExtAttrs = record
    RawExt: Cardinal;                      { upstream _ext }
    UrlId: Integer;
    function Ext: Cardinal;                { the getter: DASHED forced while UrlId <> 0 }
    function UnderlineStyle: Integer;
    procedure SetUnderlineStyle(AValue: Integer);
    function UnderlineColor: Cardinal;
    procedure SetUnderlineColor(AValue: Integer);   { -1 stores $3FFFFFF, as upstream }
    function UnderlineVariantOffset: Integer;
    procedure SetUnderlineVariantOffset(AValue: Integer);
    function IsEmpty: Boolean;
  end;

  { AttributeData; the getters keep upstream's names (is/get prefixes included). }
  TTyTerminalAttrData = record
    Fg, Bg: Cardinal;
    Extended: TTyTerminalExtAttrs;
    function IsInverse: Boolean;
    function IsBold: Boolean;
    function IsUnderline: Boolean;
    function IsBlink: Boolean;
    function IsInvisible: Boolean;
    function IsItalic: Boolean;
    function IsDim: Boolean;
    function IsStrikethrough: Boolean;
    function IsProtected: Boolean;
    function IsOverline: Boolean;
    function GetFgColorMode: Cardinal;
    function GetBgColorMode: Cardinal;
    function IsFgRGB: Boolean;
    function IsBgRGB: Boolean;
    function IsFgPalette: Boolean;
    function IsBgPalette: Boolean;
    function IsFgDefault: Boolean;
    function IsBgDefault: Boolean;
    function IsAttributeDefault: Boolean;
    function GetFgColor: Integer;           { -1 = default }
    function GetBgColor: Integer;
    function HasExtendedAttrs: Boolean;
    procedure UpdateExtended;
    function GetUnderlineColor: Integer;
    function GetUnderlineColorMode: Cardinal;
    function GetUnderlineStyle: Integer;
    function GetUnderlineVariantOffset: Integer;
  end;

  { CellData (design spec 6.3); Combined is UTF-8. }
  TTyTerminalCellData = record
    Content, Fg, Bg: Cardinal;
    Ext: TTyTerminalExtAttrs;
    Combined: string;
    function Width: Integer;
    function IsCombined: Boolean;
    function Chars: string;
    function AsAttr: TTyTerminalAttrData;
  end;

  TTyTermComboEntry = record
    Col: Integer;
    Text: string;                          { UTF-8 }
  end;
  TTyTermExtEntry = record
    Col: Integer;
    Ext: TTyTerminalExtAttrs;
  end;

  { BufferLine, BufferLine.ts:69-618; reference counted (unit header). }
  TTyTerminalLine = class
  private
    class var GLiveCount: Integer;
  private
    FData: array of Cardinal;              { the whole allocation: upstream's ArrayBuffer }
    FLength: Integer;                      { cells in use: _data is FLength * 3 of it }
    FCombined: array of TTyTermComboEntry;
    FCombinedCount: Integer;
    FExtended: array of TTyTermExtEntry;
    FExtendedCount: Integer;
    FIsWrapped: Boolean;
    FRefCount: Integer;
    FCacheValid, FCacheTrimmed: Boolean;   { translateToString's cache: observable }
    FCache: string;
    function CombinedIndex(ACol: Integer; out AIndex: Integer): Boolean;
    function ExtendedIndex(ACol: Integer; out AIndex: Integer): Boolean;
    procedure PutCombined(ACol: Integer; const AText: string);
    procedure PutExtended(ACol: Integer; const AExt: TTyTerminalExtAttrs);
    procedure ClearSparse;
    procedure CopyCellMapsFrom(ASrc: TTyTerminalLine; ASrcCol, ADestCol: Integer);
    procedure CopySparseMapsFrom(ALine: TTyTerminalLine);
    procedure PutCp(ACol: Integer; ACodepoint: Cardinal; AWidth: Integer; AFg, ABg: Cardinal;
      const AExt: TTyTerminalExtAttrs);
    function Word0(ACol: Integer): Cardinal; inline;
  public
    constructor Create(ACols: Integer; const AFill: TTyTerminalCellData; AIsWrapped: Boolean = False);
    constructor CreateDefault(ACols: Integer; AIsWrapped: Boolean = False);   { NULL cells }
    destructor Destroy; override;
    procedure AddRef;
    procedure Release;                     { frees at zero }
    class function LiveCount: Integer;     { pure query, leak guard }
    function GetWidth(ACol: Integer): Integer;
    function HasWidth(ACol: Integer): Boolean;
    function GetFg(ACol: Integer): Cardinal;
    function GetBg(ACol: Integer): Cardinal;
    function GetContent(ACol: Integer): Cardinal;
    function HasContent(ACol: Integer): Boolean;
    { A combined cell answers the last UTF-16 unit of its text, as upstream (a low
      surrogate for a trailing astral code point). }
    function GetCodePoint(ACol: Integer): Cardinal;
    function IsCombined(ACol: Integer): Boolean;
    function GetChars(ACol: Integer): string;          { getString, UTF-8 }
    function IsProtected(ACol: Integer): Boolean;
    { The combined text of ACol if the table has an entry (flag or not). }
    function CombinedEntry(ACol: Integer; out AText: string): Boolean;
    function ExtendedEntry(ACol: Integer; out AExt: TTyTerminalExtAttrs): Boolean;
    procedure LoadCell(ACol: Integer; var ACell: TTyTerminalCellData);
    function GetExtended(ACol: Integer): TTyTerminalExtAttrs;
    procedure SetCell(ACol: Integer; const ACell: TTyTerminalCellData);
    procedure SetCellFromCodepoint(ACol: Integer; ACodepoint: Cardinal; AWidth: Integer;
      const AAttrs: TTyTerminalAttrData);
    procedure AddCodepointToCell(ACol: Integer; ACodepoint: Cardinal; AWidth: Integer);
    procedure InsertCells(APos: Integer; ACount: Int64; const AFill: TTyTerminalCellData);
    procedure DeleteCells(APos: Integer; ACount: Int64; const AFill: TTyTerminalCellData);
    procedure ReplaceCells(AStart: Integer; AEnd: Int64; const AFill: TTyTerminalCellData;
      ARespectProtect: Boolean = False);
    function Resize(ACols: Integer; const AFill: TTyTerminalCellData): Boolean;
    procedure Fill(const AFill: TTyTerminalCellData; ARespectProtect: Boolean = False);
    procedure CopyFrom(ALine: TTyTerminalLine; ABlank: Boolean = False);
    function Clone(ABlank: Boolean = False): TTyTerminalLine;   { refcount 1, owned by caller }
    function GetTrimmedLength: Integer;
    function GetNoBgTrimmedLength: Integer;
    procedure CopyCellsFrom(ASrc: TTyTerminalLine; ASrcCol, ADestCol, ALength: Integer;
      AApplyInReverse: Boolean);
    { AStartCol 0 and AEndCol -1 (upstream: undefined) is the canonical request that
      goes through the cache. }
    function TranslateToString(ATrimRight: Boolean = False; AStartCol: Integer = 0;
      AEndCol: Integer = -1): string;
    property IsWrapped: Boolean read FIsWrapped write FIsWrapped;
    property Length: Integer read FLength;
    property RefCount: Integer read FRefCount;
  end;

{ The cell constructors of CellData / Buffer.getNullCell / getWhitespaceCell. }
function TyTermCellFromCodepoint(ACode: Cardinal; AWidth: Integer; const AAttr: TTyTerminalAttrData): TTyTerminalCellData;
function TyTermNullCell(const AAttr: TTyTerminalAttrData): TTyTerminalCellData;
function TyTermWhitespaceCell(const AAttr: TTyTerminalAttrData): TTyTerminalCellData;
{ UTF-8 -> code points (the decoder's input is valid UTF-8; nothing else reaches it). }
function TyTermUtf8Codepoints(const S: string): TIntegerDynArray;
{ JavaScript's String.prototype.trimEnd over UTF-8. }
function TyTermJsTrimEnd(const S: string): string;

const
  TyTermDefaultAttr: TTyTerminalAttrData = (Fg: 0; Bg: 0; Extended: (RawExt: 0; UrlId: 0));

implementation

{ ---- small helpers ---------------------------------------------------------------- }

function CpToUtf8(c: Cardinal): string;
begin
  if c < $80 then
    Result := Chr(c)
  else if c < $800 then
    Result := Chr($C0 or (c shr 6)) + Chr($80 or (c and $3F))
  else if c < $10000 then
    Result := Chr($E0 or (c shr 12)) + Chr($80 or ((c shr 6) and $3F)) + Chr($80 or (c and $3F))
  else
    Result := Chr($F0 or (c shr 18)) + Chr($80 or ((c shr 12) and $3F))
      + Chr($80 or ((c shr 6) and $3F)) + Chr($80 or (c and $3F));
end;

function TyTermUtf8Codepoints(const S: string): TIntegerDynArray;
var
  i, n, len, k: Integer;
  b: Byte;
  c: Cardinal;
begin
  Result := nil;
  SetLength(Result, System.Length(S));
  n := 0;
  i := 1;
  len := System.Length(S);
  while i <= len do
  begin
    b := Ord(S[i]);
    if b < $80 then begin c := b; k := 0; end
    else if b and $E0 = $C0 then begin c := b and $1F; k := 1; end
    else if b and $F0 = $E0 then begin c := b and $0F; k := 2; end
    else begin c := b and $07; k := 3; end;
    Inc(i);
    while (k > 0) and (i <= len) do
    begin
      c := (c shl 6) or (Ord(S[i]) and $3F);
      Inc(i);
      Dec(k);
    end;
    Result[n] := Integer(c);
    Inc(n);
  end;
  SetLength(Result, n);
end;

{ ECMAScript WhiteSpace + LineTerminator }
function IsJsWhitespace(c: Cardinal): Boolean;
begin
  case c of
    $09..$0D, $20, $A0, $1680, $2000..$200A, $2028, $2029, $202F, $205F, $3000, $FEFF:
      Result := True;
  else
    Result := False;
  end;
end;

function TyTermJsTrimEnd(const S: string): string;
var
  e, p: Integer;
  c: Cardinal;
  b: Byte;
begin
  e := System.Length(S);
  while e > 0 do
  begin
    { the start of the last code point }
    p := e;
    while (p > 1) and (Ord(S[p]) and $C0 = $80) do
      Dec(p);
    b := Ord(S[p]);
    if b < $80 then c := b
    else if b and $E0 = $C0 then c := b and $1F
    else if b and $F0 = $E0 then c := b and $0F
    else c := b and $07;
    Inc(p);
    while p <= e do
    begin
      c := (c shl 6) or (Ord(S[p]) and $3F);
      Inc(p);
    end;
    if not IsJsWhitespace(c) then
      Break;
    { step back over that code point }
    p := e;
    while (p > 1) and (Ord(S[p]) and $C0 = $80) do
      Dec(p);
    e := p - 1;
  end;
  Result := Copy(S, 1, e);
end;

{ ---- TTyTerminalExtAttrs (AttributeData.ts:140-213) ------------------------------ }

function TTyTerminalExtAttrs.Ext: Cardinal;
begin
  if UrlId <> 0 then
    Result := (RawExt and not Cardinal(TyTermExtUnderlineStyle)) or (Cardinal(UnderlineStyle) shl 26)
  else
    Result := RawExt;
end;

function TTyTerminalExtAttrs.UnderlineStyle: Integer;
begin
  if UrlId <> 0 then
    Exit(Ord(tusDashed));                  { always the URL style }
  Result := (RawExt and TyTermExtUnderlineStyle) shr 26;
end;

procedure TTyTerminalExtAttrs.SetUnderlineStyle(AValue: Integer);
begin
  RawExt := (RawExt and not Cardinal(TyTermExtUnderlineStyle))
    or ((Cardinal(AValue) shl 26) and TyTermExtUnderlineStyle);
end;

function TTyTerminalExtAttrs.UnderlineColor: Cardinal;
begin
  Result := RawExt and (TyTermAttrCmMask or TyTermAttrRgbMask);
end;

procedure TTyTerminalExtAttrs.SetUnderlineColor(AValue: Integer);
begin
  RawExt := (RawExt and not Cardinal(TyTermAttrCmMask or TyTermAttrRgbMask))
    or (Cardinal(AValue) and (TyTermAttrCmMask or TyTermAttrRgbMask));
end;

{ (_ext & 0xE0000000) >> 29 is a signed shift upstream: -4..-1 for the high values,
  then ^ 0xFFFFFFF8 (as int32, -8) turns them back into 4..7 }
function TTyTerminalExtAttrs.UnderlineVariantOffset: Integer;
begin
  Result := SarLongint(Integer(RawExt and TyTermExtVariantOffset), 29);
  if Result < 0 then
    Result := Result xor Integer($FFFFFFF8);
end;

procedure TTyTerminalExtAttrs.SetUnderlineVariantOffset(AValue: Integer);
begin
  RawExt := (RawExt and not Cardinal(TyTermExtVariantOffset))
    or ((Cardinal(AValue) shl 29) and TyTermExtVariantOffset);
end;

function TTyTerminalExtAttrs.IsEmpty: Boolean;
begin
  Result := (UnderlineStyle = Ord(tusNone)) and (UrlId = 0);
end;

{ ---- TTyTerminalAttrData (AttributeData.ts:10-133) -------------------------------- }

function TTyTerminalAttrData.IsInverse: Boolean;
begin
  Result := Fg and TyTermFgInverse <> 0;
end;

function TTyTerminalAttrData.IsBold: Boolean;
begin
  Result := Fg and TyTermFgBold <> 0;
end;

function TTyTerminalAttrData.IsUnderline: Boolean;
begin
  if HasExtendedAttrs and (Extended.UnderlineStyle <> Ord(tusNone)) then
    Exit(True);
  Result := Fg and TyTermFgUnderline <> 0;
end;

function TTyTerminalAttrData.IsBlink: Boolean;
begin
  Result := Fg and TyTermFgBlink <> 0;
end;

function TTyTerminalAttrData.IsInvisible: Boolean;
begin
  Result := Fg and TyTermFgInvisible <> 0;
end;

function TTyTerminalAttrData.IsItalic: Boolean;
begin
  Result := Bg and TyTermBgItalic <> 0;
end;

function TTyTerminalAttrData.IsDim: Boolean;
begin
  Result := Bg and TyTermBgDim <> 0;
end;

function TTyTerminalAttrData.IsStrikethrough: Boolean;
begin
  Result := Fg and TyTermFgStrikethrough <> 0;
end;

function TTyTerminalAttrData.IsProtected: Boolean;
begin
  Result := Bg and TyTermBgProtected <> 0;
end;

function TTyTerminalAttrData.IsOverline: Boolean;
begin
  Result := Bg and TyTermBgOverline <> 0;
end;

function TTyTerminalAttrData.GetFgColorMode: Cardinal;
begin
  Result := Fg and TyTermAttrCmMask;
end;

function TTyTerminalAttrData.GetBgColorMode: Cardinal;
begin
  Result := Bg and TyTermAttrCmMask;
end;

function TTyTerminalAttrData.IsFgRGB: Boolean;
begin
  Result := Fg and TyTermAttrCmMask = TyTermAttrCmRgb;
end;

function TTyTerminalAttrData.IsBgRGB: Boolean;
begin
  Result := Bg and TyTermAttrCmMask = TyTermAttrCmRgb;
end;

function TTyTerminalAttrData.IsFgPalette: Boolean;
begin
  Result := (Fg and TyTermAttrCmMask = TyTermAttrCmP16) or (Fg and TyTermAttrCmMask = TyTermAttrCmP256);
end;

function TTyTerminalAttrData.IsBgPalette: Boolean;
begin
  Result := (Bg and TyTermAttrCmMask = TyTermAttrCmP16) or (Bg and TyTermAttrCmMask = TyTermAttrCmP256);
end;

function TTyTerminalAttrData.IsFgDefault: Boolean;
begin
  Result := Fg and TyTermAttrCmMask = 0;
end;

function TTyTerminalAttrData.IsBgDefault: Boolean;
begin
  Result := Bg and TyTermAttrCmMask = 0;
end;

function TTyTerminalAttrData.IsAttributeDefault: Boolean;
begin
  Result := (Fg = 0) and (Bg = 0);
end;

function TTyTerminalAttrData.GetFgColor: Integer;
begin
  case Fg and TyTermAttrCmMask of
    TyTermAttrCmP16, TyTermAttrCmP256: Result := Fg and TyTermAttrPColorMask;
    TyTermAttrCmRgb: Result := Fg and TyTermAttrRgbMask;
  else
    Result := -1;
  end;
end;

function TTyTerminalAttrData.GetBgColor: Integer;
begin
  case Bg and TyTermAttrCmMask of
    TyTermAttrCmP16, TyTermAttrCmP256: Result := Bg and TyTermAttrPColorMask;
    TyTermAttrCmRgb: Result := Bg and TyTermAttrRgbMask;
  else
    Result := -1;
  end;
end;

function TTyTerminalAttrData.HasExtendedAttrs: Boolean;
begin
  Result := Bg and TyTermBgHasExtended <> 0;
end;

procedure TTyTerminalAttrData.UpdateExtended;
begin
  if Extended.IsEmpty then
    Bg := Bg and not Cardinal(TyTermBgHasExtended)
  else
    Bg := Bg or TyTermBgHasExtended;
end;

{ ~underlineColor: anything but all bits set counts }
function TTyTerminalAttrData.GetUnderlineColor: Integer;
begin
  if HasExtendedAttrs and (Extended.UnderlineColor <> $FFFFFFFF) then
    case Extended.UnderlineColor and TyTermAttrCmMask of
      TyTermAttrCmP16, TyTermAttrCmP256: Exit(Extended.UnderlineColor and TyTermAttrPColorMask);
      TyTermAttrCmRgb: Exit(Extended.UnderlineColor and TyTermAttrRgbMask);
    else
      Exit(GetFgColor);
    end;
  Result := GetFgColor;
end;

function TTyTerminalAttrData.GetUnderlineColorMode: Cardinal;
begin
  if HasExtendedAttrs and (Extended.UnderlineColor <> $FFFFFFFF) then
    Result := Extended.UnderlineColor and TyTermAttrCmMask
  else
    Result := GetFgColorMode;
end;

function TTyTerminalAttrData.GetUnderlineStyle: Integer;
begin
  if Fg and TyTermFgUnderline <> 0 then
  begin
    if HasExtendedAttrs then
      Result := Extended.UnderlineStyle
    else
      Result := Ord(tusSingle);
  end
  else
    Result := Ord(tusNone);
end;

function TTyTerminalAttrData.GetUnderlineVariantOffset: Integer;
begin
  Result := Extended.UnderlineVariantOffset;
end;

{ ---- TTyTerminalCellData (CellData.ts) -------------------------------------------- }

function TTyTerminalCellData.Width: Integer;
begin
  Result := Content shr TyTermContentWidthShift;
end;

function TTyTerminalCellData.IsCombined: Boolean;
begin
  Result := Content and TyTermContentIsCombinedMask <> 0;
end;

function TTyTerminalCellData.Chars: string;
begin
  if IsCombined then
    Exit(Combined);
  if Content and TyTermContentCodepointMask <> 0 then
    Exit(CpToUtf8(Content and TyTermContentCodepointMask));
  Result := '';
end;

function TTyTerminalCellData.AsAttr: TTyTerminalAttrData;
begin
  Result.Fg := Fg;
  Result.Bg := Bg;
  Result.Extended := Ext;
end;

function TyTermCellFromCodepoint(ACode: Cardinal; AWidth: Integer; const AAttr: TTyTerminalAttrData): TTyTerminalCellData;
begin
  Result.Content := ACode or (Cardinal(AWidth) shl TyTermContentWidthShift);
  Result.Fg := AAttr.Fg;
  Result.Bg := AAttr.Bg;
  Result.Ext := AAttr.Extended;
  Result.Combined := '';
end;

function TyTermNullCell(const AAttr: TTyTerminalAttrData): TTyTerminalCellData;
begin
  Result := TyTermCellFromCodepoint(TyTermNullCellCode, TyTermNullCellWidth, AAttr);
end;

function TyTermWhitespaceCell(const AAttr: TTyTerminalAttrData): TTyTerminalCellData;
begin
  Result := TyTermCellFromCodepoint(TyTermWhitespaceCellCode, 1, AAttr);
end;

{ ---- TTyTerminalLine (BufferLine.ts) ---------------------------------------------- }

constructor TTyTerminalLine.Create(ACols: Integer; const AFill: TTyTerminalCellData; AIsWrapped: Boolean);
var
  i: Integer;
begin                                                                        { :82-93 }
  inherited Create;
  Inc(GLiveCount);
  FRefCount := 1;
  FIsWrapped := AIsWrapped;
  if ACols < 0 then
    ACols := 0;
  SetLength(FData, ACols * 3);
  FLength := ACols;
  for i := 0 to ACols - 1 do
    SetCell(i, AFill);
end;

constructor TTyTerminalLine.CreateDefault(ACols: Integer; AIsWrapped: Boolean);
begin
  Create(ACols, TyTermNullCell(TyTermDefaultAttr), AIsWrapped);
end;

destructor TTyTerminalLine.Destroy;
begin
  Dec(GLiveCount);
  inherited Destroy;
end;

procedure TTyTerminalLine.AddRef;
begin
  Inc(FRefCount);
end;

procedure TTyTerminalLine.Release;
begin
  Dec(FRefCount);
  if FRefCount <= 0 then
    Free;
end;

class function TTyTerminalLine.LiveCount: Integer;
begin
  Result := GLiveCount;
end;

function TTyTerminalLine.Word0(ACol: Integer): Cardinal;
begin
  { outside the view a typed array reads undefined, which every caller turns into 0 }
  if (ACol < 0) or (ACol >= FLength) then
    Result := 0
  else
    Result := FData[ACol * 3];
end;

function TTyTerminalLine.CombinedIndex(ACol: Integer; out AIndex: Integer): Boolean;
var
  lo, hi, mid: Integer;
begin
  lo := 0;
  hi := FCombinedCount - 1;
  while lo <= hi do
  begin
    mid := (lo + hi) shr 1;
    if FCombined[mid].Col = ACol then
    begin
      AIndex := mid;
      Exit(True);
    end;
    if FCombined[mid].Col < ACol then lo := mid + 1 else hi := mid - 1;
  end;
  AIndex := lo;
  Result := False;
end;

function TTyTerminalLine.ExtendedIndex(ACol: Integer; out AIndex: Integer): Boolean;
var
  lo, hi, mid: Integer;
begin
  lo := 0;
  hi := FExtendedCount - 1;
  while lo <= hi do
  begin
    mid := (lo + hi) shr 1;
    if FExtended[mid].Col = ACol then
    begin
      AIndex := mid;
      Exit(True);
    end;
    if FExtended[mid].Col < ACol then lo := mid + 1 else hi := mid - 1;
  end;
  AIndex := lo;
  Result := False;
end;

procedure TTyTerminalLine.PutCombined(ACol: Integer; const AText: string);
var
  i, k: Integer;
begin
  if not CombinedIndex(ACol, i) then
  begin
    if FCombinedCount = System.Length(FCombined) then
      SetLength(FCombined, FCombinedCount * 2 + 2);
    for k := FCombinedCount downto i + 1 do
      FCombined[k] := FCombined[k - 1];
    FCombined[i].Col := ACol;
    Inc(FCombinedCount);
  end;
  FCombined[i].Text := AText;
end;

procedure TTyTerminalLine.PutExtended(ACol: Integer; const AExt: TTyTerminalExtAttrs);
var
  i, k: Integer;
begin
  if not ExtendedIndex(ACol, i) then
  begin
    if FExtendedCount = System.Length(FExtended) then
      SetLength(FExtended, FExtendedCount * 2 + 2);
    for k := FExtendedCount downto i + 1 do
      FExtended[k] := FExtended[k - 1];
    FExtended[i].Col := ACol;
    Inc(FExtendedCount);
  end;
  FExtended[i].Ext := AExt;
end;

procedure TTyTerminalLine.ClearSparse;
begin
  FCombined := nil;
  FCombinedCount := 0;
  FExtended := nil;
  FExtendedCount := 0;
end;

function TTyTerminalLine.CombinedEntry(ACol: Integer; out AText: string): Boolean;
var
  i: Integer;
begin
  Result := CombinedIndex(ACol, i);
  if Result then
    AText := FCombined[i].Text
  else
    AText := '';
end;

function TTyTerminalLine.ExtendedEntry(ACol: Integer; out AExt: TTyTerminalExtAttrs): Boolean;
var
  i: Integer;
begin
  Result := ExtendedIndex(ACol, i);
  if Result then
    AExt := FExtended[i].Ext
  else
  begin
    AExt.RawExt := 0;
    AExt.UrlId := 0;
  end;
end;

function TTyTerminalLine.GetWidth(ACol: Integer): Integer;
begin
  Result := Word0(ACol) shr TyTermContentWidthShift;
end;

function TTyTerminalLine.HasWidth(ACol: Integer): Boolean;
begin
  Result := Word0(ACol) and TyTermContentWidthMask <> 0;
end;

function TTyTerminalLine.GetFg(ACol: Integer): Cardinal;
begin
  if (ACol < 0) or (ACol >= FLength) then Exit(0);
  Result := FData[ACol * 3 + 1];
end;

function TTyTerminalLine.GetBg(ACol: Integer): Cardinal;
begin
  if (ACol < 0) or (ACol >= FLength) then Exit(0);
  Result := FData[ACol * 3 + 2];
end;

function TTyTerminalLine.GetContent(ACol: Integer): Cardinal;
begin
  Result := Word0(ACol);
end;

function TTyTerminalLine.HasContent(ACol: Integer): Boolean;
begin
  Result := Word0(ACol) and TyTermContentHasContentMask <> 0;
end;

function TTyTerminalLine.GetCodePoint(ACol: Integer): Cardinal;              { :166-172 }
var
  s: string;
  cps: TIntegerDynArray;
  c: Cardinal;
begin
  if Word0(ACol) and TyTermContentIsCombinedMask <> 0 then
  begin
    CombinedEntry(ACol, s);
    cps := TyTermUtf8Codepoints(s);
    if System.Length(cps) = 0 then
      Exit(0);
    c := Cardinal(cps[High(cps)]);
    if c > $FFFF then                      { charCodeAt(length - 1): the low surrogate }
      c := $DC00 + ((c - $10000) and $3FF);
    Exit(c);
  end;
  Result := Word0(ACol) and TyTermContentCodepointMask;
end;

function TTyTerminalLine.IsCombined(ACol: Integer): Boolean;
begin
  Result := Word0(ACol) and TyTermContentIsCombinedMask <> 0;
end;

function TTyTerminalLine.GetChars(ACol: Integer): string;                    { :180-190 }
var
  content: Cardinal;
begin
  content := Word0(ACol);
  if content and TyTermContentIsCombinedMask <> 0 then
  begin
    CombinedEntry(ACol, Result);
    Exit;
  end;
  if content and TyTermContentCodepointMask <> 0 then
    Exit(CpToUtf8(content and TyTermContentCodepointMask));
  Result := '';
end;

function TTyTerminalLine.IsProtected(ACol: Integer): Boolean;
begin
  Result := GetBg(ACol) and TyTermBgProtected <> 0;
end;

procedure TTyTerminalLine.LoadCell(ACol: Integer; var ACell: TTyTerminalCellData);
begin                                                                        { :201-213 }
  ACell.Content := Word0(ACol);
  ACell.Fg := GetFg(ACol);
  ACell.Bg := GetBg(ACol);
  if ACell.Content and TyTermContentIsCombinedMask <> 0 then
    CombinedEntry(ACol, ACell.Combined)
  else
    ACell.Combined := '';
  ACell.Ext := GetExtended(ACol);
end;

function TTyTerminalLine.GetExtended(ACol: Integer): TTyTerminalExtAttrs;   { :215-228 }
begin
  if GetBg(ACol) and TyTermBgHasExtended <> 0 then
    ExtendedEntry(ACol, Result)
  else
  begin
    Result.RawExt := 0;
    Result.UrlId := 0;
  end;
end;

procedure TTyTerminalLine.SetCell(ACol: Integer; const ACell: TTyTerminalCellData);
begin                                                                        { :233-244 }
  FCacheValid := False;
  if (ACol < 0) or (ACol >= FLength) then
    Exit;                                  { a typed array ignores the write }
  if ACell.Content and TyTermContentIsCombinedMask <> 0 then
    PutCombined(ACol, ACell.Combined);
  if ACell.Bg and TyTermBgHasExtended <> 0 then
    PutExtended(ACol, ACell.Ext);
  FData[ACol * 3] := ACell.Content;
  FData[ACol * 3 + 1] := ACell.Fg;
  FData[ACol * 3 + 2] := ACell.Bg;
end;

procedure TTyTerminalLine.PutCp(ACol: Integer; ACodepoint: Cardinal; AWidth: Integer;
  AFg, ABg: Cardinal; const AExt: TTyTerminalExtAttrs);
begin                                                                        { :251-260 }
  FCacheValid := False;
  if (ACol < 0) or (ACol >= FLength) then
    Exit;
  if ABg and TyTermBgHasExtended <> 0 then
    PutExtended(ACol, AExt);
  FData[ACol * 3] := ACodepoint or (Cardinal(AWidth) shl TyTermContentWidthShift);
  FData[ACol * 3 + 1] := AFg;
  FData[ACol * 3 + 2] := ABg;
end;

procedure TTyTerminalLine.SetCellFromCodepoint(ACol: Integer; ACodepoint: Cardinal; AWidth: Integer;
  const AAttrs: TTyTerminalAttrData);
begin
  PutCp(ACol, ACodepoint, AWidth, AAttrs.Fg, AAttrs.Bg, AAttrs.Extended);
end;

procedure TTyTerminalLine.AddCodepointToCell(ACol: Integer; ACodepoint: Cardinal; AWidth: Integer);
var
  content: Cardinal;
  s: string;
begin                                                                        { :268-293 }
  FCacheValid := False;
  if (ACol < 0) or (ACol >= FLength) then
    Exit;
  content := FData[ACol * 3];
  if content and TyTermContentIsCombinedMask <> 0 then
  begin
    { already combined: append }
    CombinedEntry(ACol, s);
    PutCombined(ACol, s + CpToUtf8(ACodepoint));
  end
  else
  begin
    if content and TyTermContentCodepointMask <> 0 then
    begin
      { the leading character and the new one become the combined text }
      PutCombined(ACol, CpToUtf8(content and TyTermContentCodepointMask) + CpToUtf8(ACodepoint));
      content := content and not Cardinal(TyTermContentCodepointMask);
      content := content or TyTermContentIsCombinedMask;
    end
    else
      { should not happen upstream: an empty cell, taken with width 1 }
      content := ACodepoint or (Cardinal(1) shl TyTermContentWidthShift);
  end;
  if AWidth <> 0 then
  begin
    content := content and not Cardinal(TyTermContentWidthMask);
    content := content or (Cardinal(AWidth) shl TyTermContentWidthShift);
  end;
  FData[ACol * 3] := content;
end;

procedure TTyTerminalLine.InsertCells(APos: Integer; ACount: Int64; const AFill: TTyTerminalCellData);
var
  i: Integer;
  n: Integer;
  cell: TTyTerminalCellData;
begin                                                                        { :295-321 }
  FCacheValid := False;
  if FLength = 0 then
    Exit;                                  { pos % 0 is NaN upstream: nothing is written }
  APos := APos mod FLength;
  { pos on the second cell of a wide character: reset the first }
  if (APos <> 0) and (GetWidth(APos - 1) = 2) then
    PutCp(APos - 1, 0, 1, AFill.Fg, AFill.Bg, AFill.Ext);
  if ACount < Int64(FLength) - APos then
  begin
    n := Integer(ACount);
    for i := FLength - APos - n - 1 downto 0 do
    begin
      LoadCell(APos + i, cell);
      SetCell(APos + n + i, cell);
    end;
    for i := 0 to n - 1 do
      SetCell(APos + i, AFill);
  end
  else
    for i := APos to FLength - 1 do
      SetCell(i, AFill);
  { a wide character pushed into the last cell cannot stay }
  if GetWidth(FLength - 1) = 2 then
    PutCp(FLength - 1, 0, 1, AFill.Fg, AFill.Bg, AFill.Ext);
end;

procedure TTyTerminalLine.DeleteCells(APos: Integer; ACount: Int64; const AFill: TTyTerminalCellData);
var
  i, n: Integer;
  cell: TTyTerminalCellData;
begin                                                                        { :323-348 }
  FCacheValid := False;
  if FLength = 0 then
    Exit;
  APos := APos mod FLength;
  if ACount < Int64(FLength) - APos then
  begin
    n := Integer(ACount);
    for i := 0 to FLength - APos - n - 1 do
    begin
      LoadCell(APos + n + i, cell);
      SetCell(APos + i, cell);
    end;
    for i := FLength - n to FLength - 1 do
      SetCell(i, AFill);
  end
  else
    for i := APos to FLength - 1 do
      SetCell(i, AFill);
  { pos - 1 left as the first half of a wide character, pos as a lone second half }
  if (APos <> 0) and (GetWidth(APos - 1) = 2) then
    PutCp(APos - 1, 0, 1, AFill.Fg, AFill.Bg, AFill.Ext);
  if (GetWidth(APos) = 0) and not HasContent(APos) then
    PutCp(APos, 0, 1, AFill.Fg, AFill.Bg, AFill.Ext);
end;

procedure TTyTerminalLine.ReplaceCells(AStart: Integer; AEnd: Int64; const AFill: TTyTerminalCellData;
  ARespectProtect: Boolean);
begin                                                                        { :350-381 }
  FCacheValid := False;
  if ARespectProtect then
  begin
    if (AStart <> 0) and (GetWidth(AStart - 1) = 2) and not IsProtected(AStart - 1) then
      PutCp(AStart - 1, 0, 1, AFill.Fg, AFill.Bg, AFill.Ext);
    if (AEnd < FLength) and (GetWidth(Integer(AEnd) - 1) = 2) and not IsProtected(Integer(AEnd)) then
      PutCp(Integer(AEnd), 0, 1, AFill.Fg, AFill.Bg, AFill.Ext);
    while (AStart < AEnd) and (AStart < FLength) do
    begin
      if not IsProtected(AStart) then
        SetCell(AStart, AFill);
      Inc(AStart);
    end;
    Exit;
  end;
  { start on the second half of a wide character: reset the first }
  if (AStart <> 0) and (GetWidth(AStart - 1) = 2) then
    PutCp(AStart - 1, 0, 1, AFill.Fg, AFill.Bg, AFill.Ext);
  { end on the second half of a wide character: reset that half }
  if (AEnd < FLength) and (GetWidth(Integer(AEnd) - 1) = 2) then
    PutCp(Integer(AEnd), 0, 1, AFill.Fg, AFill.Bg, AFill.Ext);
  while (AStart < AEnd) and (AStart < FLength) do
  begin
    SetCell(AStart, AFill);
    Inc(AStart);
  end;
end;

{ The answer is upstream's "would cleanupMemory free anything" over the size of the
  allocation (its ArrayBuffer): a shrink keeps the allocation, a grow reuses it when
  it is big enough. Upstream schedules a clean-up from it (_memoryCleanupQueue);
  that is a memory optimisation with nothing observable and is not ported. }
function TTyTerminalLine.Resize(ACols: Integer; const AFill: TTyTerminalCellData): Boolean;
var
  cells, i, k, oldLength: Integer;
begin                                                                        { :390-431 }
  FCacheValid := False;
  if ACols = FLength then
    Exit(Int64(FLength) * 3 * 4 * 2 < Int64(System.Length(FData)) * 4);
  cells := ACols * 3;
  if ACols > FLength then
  begin
    if System.Length(FData) < cells then
      SetLength(FData, cells);             { the slow path: a new allocation, data copied }
    oldLength := FLength;
    FLength := ACols;
    for i := oldLength to ACols - 1 do
      SetCell(i, AFill);
  end
  else
  begin
    FLength := ACols;
    { drop cut-off combined text and extended attributes }
    k := 0;
    for i := 0 to FCombinedCount - 1 do
      if FCombined[i].Col < ACols then
      begin
        FCombined[k] := FCombined[i];
        Inc(k);
      end;
    for i := k to FCombinedCount - 1 do
      FCombined[i].Text := '';
    FCombinedCount := k;
    k := 0;
    for i := 0 to FExtendedCount - 1 do
      if FExtended[i].Col < ACols then
      begin
        FExtended[k] := FExtended[i];
        Inc(k);
      end;
    FExtendedCount := k;
  end;
  Result := Int64(cells) * 4 * 2 < Int64(System.Length(FData)) * 4;
end;

procedure TTyTerminalLine.Fill(const AFill: TTyTerminalCellData; ARespectProtect: Boolean);
var
  i: Integer;
begin                                                                        { :450-466 }
  FCacheValid := False;
  if ARespectProtect then
  begin
    for i := 0 to FLength - 1 do
      if not IsProtected(i) then
        SetCell(i, AFill);
    Exit;
  end;
  ClearSparse;
  for i := 0 to FLength - 1 do
    SetCell(i, AFill);
end;

procedure TTyTerminalLine.CopyCellMapsFrom(ASrc: TTyTerminalLine; ASrcCol, ADestCol: Integer);
var
  s: string;
  e: TTyTerminalExtAttrs;
begin                                                                        { :600-608 }
  if ASrc.Word0(ASrcCol) and TyTermContentIsCombinedMask <> 0 then
  begin
    ASrc.CombinedEntry(ASrcCol, s);
    PutCombined(ADestCol, s);
  end;
  if ASrc.GetBg(ASrcCol) and TyTermBgHasExtended <> 0 then
  begin
    ASrc.ExtendedEntry(ASrcCol, e);
    PutExtended(ADestCol, e);
  end;
end;

procedure TTyTerminalLine.CopySparseMapsFrom(ALine: TTyTerminalLine);
var
  i: Integer;
begin                                                                        { :611-617 }
  ClearSparse;
  for i := 0 to ALine.FLength - 1 do
    CopyCellMapsFrom(ALine, i, i);
end;

procedure TTyTerminalLine.CopyFrom(ALine: TTyTerminalLine; ABlank: Boolean);
begin                                                                        { :469-488 }
  if ALine = Self then
  begin
    { upstream empties its maps before copying them from the line -- itself -- so
      they end up empty either way }
    ClearSparse;
    FCache := '';
    FCacheValid := False;
    Exit;
  end;
  if FLength <> ALine.FLength then
    FData := Copy(ALine.FData, 0, ALine.FLength * 3)     { a new allocation of that size }
  else if FLength > 0 then
    Move(ALine.FData[0], FData[0], FLength * 3 * SizeOf(Cardinal));
  FLength := ALine.FLength;
  if ABlank then
    ClearSparse                            { a blank line never holds either }
  else
    CopySparseMapsFrom(ALine);
  FCache := '';
  FCacheValid := False;
  FIsWrapped := ALine.FIsWrapped;
end;

function TTyTerminalLine.Clone(ABlank: Boolean): TTyTerminalLine;
begin                                                                        { :491-502 }
  Result := TTyTerminalLine.CreateDefault(0);
  Result.FData := Copy(FData, 0, FLength * 3);
  Result.FLength := FLength;
  if not ABlank then
    Result.CopySparseMapsFrom(Self);
  Result.FIsWrapped := FIsWrapped;
end;

function TTyTerminalLine.GetTrimmedLength: Integer;
var
  i: Integer;
begin                                                                        { :504-511 }
  for i := FLength - 1 downto 0 do
    if FData[i * 3] and TyTermContentHasContentMask <> 0 then
      Exit(i + Integer(FData[i * 3] shr TyTermContentWidthShift));
  Result := 0;
end;

function TTyTerminalLine.GetNoBgTrimmedLength: Integer;
var
  i: Integer;
begin                                                                        { :513-520 }
  for i := FLength - 1 downto 0 do
    if (FData[i * 3] and TyTermContentHasContentMask <> 0) or (FData[i * 3 + 2] and TyTermAttrCmMask <> 0) then
      Exit(i + Integer(FData[i * 3] shr TyTermContentWidthShift));
  Result := 0;
end;

procedure TTyTerminalLine.CopyCellsFrom(ASrc: TTyTerminalLine; ASrcCol, ADestCol, ALength: Integer;
  AApplyInReverse: Boolean);

  procedure One(ACell: Integer);
  var
    k, s, d: Integer;
  begin
    for k := 0 to 2 do
    begin
      d := (ADestCol + ACell) * 3 + k;
      s := (ASrcCol + ACell) * 3 + k;
      if (d >= 0) and (d < FLength * 3) then
      begin
        if (s >= 0) and (s < ASrc.FLength * 3) then
          FData[d] := ASrc.FData[s]
        else
          FData[d] := 0;
      end;
    end;
    CopyCellMapsFrom(ASrc, ASrcCol + ACell, ADestCol + ACell);
  end;

var
  c: Integer;
begin                                                                        { :522-540 }
  FCacheValid := False;
  if AApplyInReverse then
    for c := ALength - 1 downto 0 do
      One(c)
  else
    for c := 0 to ALength - 1 do
      One(c);
end;

{ :556-597. The cache is ported: a canonical call with trimRight after an untrimmed
  one answers the cached text through trimEnd(), which also drops written spaces and
  other JavaScript whitespace -- a different answer from the trimmed-length path. }
function TTyTerminalLine.TranslateToString(ATrimRight: Boolean; AStartCol, AEndCol: Integer): string;
var
  isCanonical: Boolean;
  content, cp: Cardinal;
  w: Integer;
  s: string;
begin
  isCanonical := (AStartCol = 0) and (AEndCol = -1);
  if isCanonical and FCacheValid then
  begin
    if ATrimRight then
    begin
      if FCacheTrimmed then Exit(FCache) else Exit(TyTermJsTrimEnd(FCache));
    end;
    if not FCacheTrimmed then
      Exit(FCache);
  end;
  if AEndCol = -1 then
    AEndCol := FLength;
  if ATrimRight and (GetTrimmedLength < AEndCol) then
    AEndCol := GetTrimmedLength;
  Result := '';
  while AStartCol < AEndCol do
  begin
    content := Word0(AStartCol);
    cp := content and TyTermContentCodepointMask;
    if content and TyTermContentIsCombinedMask <> 0 then
    begin
      CombinedEntry(AStartCol, s);
      Result := Result + s;
    end
    else if cp <> 0 then
      Result := Result + CpToUtf8(cp)
    else
      Result := Result + ' ';
    w := content shr TyTermContentWidthShift;
    if w = 0 then
      w := 1;                              { always advance by at least 1 }
    Inc(AStartCol, w);
  end;
  if isCanonical then
  begin
    FCache := Result;
    FCacheValid := True;
    FCacheTrimmed := ATrimRight;
  end;
end;

end.
