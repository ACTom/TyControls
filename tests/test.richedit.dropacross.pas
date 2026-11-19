unit test.richedit.dropacross;

{ Drops into TTyRichEdit from elsewhere: the selection of one rich edit dragged into another
  of the same application (every widgetset: the control finds the one under the pointer
  through the LCL and feeds its receiving side; no clipboard, no system drag), and - on the
  Windows widgetset - another program's drop through the control's OLE drop target, which the
  tests call directly with a data object of their own (no real drag, no system clipboard, no
  window shown; the system's RegisterDragDrop / RevokeDragDrop are never called: this unit
  puts counting stand-ins in their place for the whole test run).

  Headless, on the drag suite's probe. Every bound is a count, never a time. The unit is ASCII. }

{$mode objfpc}{$H+}

interface

uses
  {$IFDEF LCLWin32}Windows, ActiveX,{$ENDIF}
  Classes, SysUtils, Types, Math, fpcunit, testregistry, Controls, Graphics, LCLType, Forms,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.StrConsts,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.TextIO,
  tyControls.RichEdit{$IFDEF LCLWin32}, tyControls.RichEdit.OleDrop{$ENDIF},
  test.richedit.control, test.richedit.edit, test.richedit.drag;

type
  { The drag suite's probe, with another probe beside it: the "screen" is this probe's client
    pixels, the other one sits at OtherAt there. }
  TAcrossProbe = class(TDragProbe)
  protected
    function DropTargetAt(X, Y: Integer; out ATargetX, ATargetY: Integer): TTyCustomRichEdit; override;
    function DropPointOf(const AScreen: TPoint): TPoint; override;
    procedure FocusAfterDrop; override;
    function ReadRtfSource(const ABytes: TBytes; out AEndsWithParagraph: Boolean): TTyRichDocument; override;
    function DropEffectAt(AOffer: TTyRichDropOffer; APos: TTyRichPos;
      AShift: TShiftState): TTyRichDropEffect; override;
    function DropModalForm: TCustomForm; override;
    function DropFilesArePictures(const AFiles: TStringArray): Boolean; override;
    function MakeFragmentFilter(ASource: TTyRichDocument): TTyRichFragmentFilter; override;
    function DropFragmentFilter(AOffer: TTyRichDropOffer;
      AInner: TTyRichFragmentFilter): TTyRichFragmentFilter; override;
  public
    { the modal form as this probe sees it (UseModal: ModalForm, else the application's) }
    UseModal: Boolean;
    ModalForm: TCustomForm;
    // the names DropFilesArePictures looked at
    NameChecks: Integer;
    { the reader's filter counted alive (CountInner), its pictures read back with other bytes
      (ChangePictures); the drop's own filter failing to be made (FailFilter) }
    CountInner, ChangePictures, FailFilter: Boolean;
    Other: TAcrossProbe;
    OtherAt: TPoint;
    FocusCalls, TargetAsks: Integer;
    { run where the real focus change would run the application's handlers (the target's
      OnEnter, the source's OnExit, a form's OnActivate) }
    OnFocusAfter: TNotifyEvent;
    { reading a dropped RTF runs out of memory; the verdict raises }
    FailRead, RaiseInVerdict: Boolean;
    {$IFDEF LCLWin32}
    function Target: IDropTarget;
    {$ENDIF}
  end;

  {$IFDEF LCLWin32}
  { Another program's data object, in this process: the formats it offers, each read counted. }
  TTestData = class(TInterfacedObject, IDataObject)
  public
    class var Alive: Integer;
  public
    Rtf: RawByteString;
    HasRtf: Boolean;
    Png, Dib: TBytes;
    Text: UnicodeString;
    HasText: Boolean;
    FileNames: array of UnicodeString;
    // a format no paste takes (HTML)
    Html: Boolean;
    // the RTF as a stream (TYMED_ISTREAM) instead of a block of memory
    Streamed: Boolean;
    { the stream: at most StreamChunk bytes a read (0: all asked), handed over at its end,
      no size told }
    StreamChunk: Integer;
    StreamAtEnd, StreamNoStat: Boolean;
    // a file list with no name; a DROPFILES block given as it is
    HasFiles: Boolean;
    RawDrop: RawByteString;
    // GetData fails although QueryGetData says the format is there
    FailGet: Boolean;
    // ANSI text (CF_TEXT) and the locale it is in (CF_LOCALE; 0: none); a BITMAPV5 DIB
    Ansi: RawByteString;
    HasAnsi: Boolean;
    Locale: LongWord;
    DibV5: TBytes;
    Gets, Queries: Integer;
    RtfGets: Integer;
    constructor Create;
    destructor Destroy; override;
    function GetData(const formatetcIn: FORMATETC; out medium: STGMEDIUM): HRESULT; stdcall;
    function GetDataHere(const pformatetc: FormatETC; out medium: STGMEDIUM): HRESULT; stdcall;
    function QueryGetData(const pformatetc: FORMATETC): HRESULT; stdcall;
    function GetCanonicalFormatEtc(const pformatetcIn: FORMATETC;
      out pformatetcOut: FORMATETC): HResult; stdcall;
    function SetData(const pformatetc: FORMATETC; var medium: STGMEDIUM;
      FRelease: BOOL): HRESULT; stdcall;
    function EnumFormatEtc(dwDirection: DWord; out enumformatetcpara: IENUMFORMATETC): HRESULT; stdcall;
    function DAdvise(const formatetc: FORMATETC; advf: DWORD; const AdvSink: IAdviseSink;
      out dwConnection: DWORD): HRESULT; stdcall;
    function DUnadvise(dwconnection: DWord): HRESULT; stdcall;
    function EnumDAdvise(out enumAdvise: IEnumStatData): HResult; stdcall;
  end;

  { A stream as another program may hand one over: read in pieces, given at its end, its size
    not told. }
  TTestStream = class(TInterfacedObject, IStream)
  public
    Data: RawByteString;
    Position: Int64;
    Chunk: Integer;
    NoStat: Boolean;
    function Read(pv: Pointer; cb: DWORD; pcbRead: PDWORD): HRESULT; stdcall;
    function Write(pv: Pointer; cb: DWORD; pcbWritten: PDWORD): HRESULT; stdcall;
    function Seek(dlibMove: LargeInt; dwOrigin: DWORD; out libNewPosition: LargeUInt): HResult; stdcall;
    function SetSize(libNewSize: LargeUInt): HRESULT; stdcall;
    function CopyTo(stm: IStream; cb: LargeUInt; out cbRead: LargeUInt;
      out cbWritten: LargeUInt): HRESULT; stdcall;
    function Commit(grfCommitFlags: DWORD): HRESULT; stdcall;
    function Revert: HRESULT; stdcall;
    function LockRegion(libOffset: LargeUInt; cb: LargeUInt; dwLockType: DWORD): HRESULT; stdcall;
    function UnlockRegion(libOffset: LargeUInt; cb: LargeUInt; dwLockType: DWORD): HRESULT; stdcall;
    function Stat(out statstg: TStatStg; grfStatFlag: DWORD): HRESULT; stdcall;
    function Clone(out stm: IStream): HRESULT; stdcall;
  end;

  { The registration stand-ins' record (the whole run's). }
  TOleCalls = class
  public
    class var Registers, Revokes: Integer;
    class var LastRegistered, LastRevoked: HWND;
    class var LastTarget: IDropTarget;
    class var Refuse: Boolean;
    // the target is kept only while this suite's test runs (no other suite's window is held)
    class var Keeping: Boolean;
  end;
  {$ENDIF}

  { The reader's filter as a counted one: alive while it lives; with Change, every picture goes
    on as one of the same size whose bytes differ (a round trip that changed them). }
  TCountedFilter = class(TTyRichFragmentFilter)
  public
    class var Live: Integer;
  public
    Inner: TTyRichFragmentFilter;
    Change: Boolean;
    constructor Create(AInner: TTyRichFragmentFilter);
    destructor Destroy; override;
    function KeepFragment(const AFragment: RawByteString; APara: Boolean): Boolean; override;
    function RowFormat(const ARaw: RawByteString): RawByteString; override;
    function MapObject(AObj: TTyRichObject; out AText: UTF8String): TTyRichObject; override;
  end;

  TTyRichDropAcrossTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FA, FB: TAcrossProbe;
    FNames: array of string;
    FHandle, FEvents: Integer;
    procedure DroppedFiles(Sender: TObject; const AFileNames: array of string;
      var AHandled: Boolean);
  private
    { FDoomed freed from the application's handler that runs these (and forgotten here) }
    FDoomed: TAcrossProbe;
    FSrcEdit: Integer;
    procedure FreeDoomed;
    procedure DoomOnNotify(Sender: TObject);
    procedure DoomOnRefused(Sender: TObject; const AReason: string);
    procedure DoomOnFiles(Sender: TObject; const AFileNames: array of string;
      var AHandled: Boolean);
    // the source's document changed from the target's OnChange (FSrcEdit: 1 an edit, 2 a new text)
    procedure EditTheSource(Sender: TObject);
    function CursorOf(AEffect: TTyRichDropEffect): TCursor;
    function NewProbe: TAcrossProbe;
    procedure Load(ARich: TAcrossProbe; const S: string);
    procedure LoadRtf(ARich: TAcrossProbe; const S: RawByteString);
    function SaveRtf(ARich: TAcrossProbe): RawByteString;
    function TextOf(ARich: TAcrossProbe): string;
    function Pt(ARich: TAcrossProbe; APos: TTyRichPos): TPoint;
    function Mid(ARich: TAcrossProbe; APos: TTyRichPos): TPoint;
    // a point of FB in FA's pixels
    function InB(const P: TPoint): TPoint;
    { FA's selection pressed at AFrom (FA's pixels), the drag begun, moved to ATo (FA's pixels). }
    procedure StartDrag(const AFrom, ATo: TPoint; AShift: TShiftState = []);
    procedure CheckNoClipboard(ARich: TAcrossProbe; const AWhat: string);
    {$IFDEF LCLWin32}
    function Enter(ARich: TAcrossProbe; AData: TTestData; const P: TPoint; AKeys: DWORD;
      AAllowed: DWORD): DWORD;
    function DropAt(ARich: TAcrossProbe; AData: TTestData; const P: TPoint; AKeys: DWORD;
      AAllowed: DWORD): DWORD;
    function TempFile(const AName: string; const ABytes: TBytes): string;
    {$ENDIF}
  private
    FTemp: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestADragIntoAnotherControlMovesOrCopies;
    procedure TestARefusedOrFailedDropKeepsTheSource;
    procedure TestAReadOnlySourceIsCopiedOut;
    procedure TestPicturesAndRowsGoAcrossAsAPasteTakesThem;
    procedure TestAPlainTextTargetTakesTheText;
    procedure TestTheSessionThereFollowsThePointerAndEnds;
    procedure TestKeysAndEdgeScrollingOverAnotherControl;
    procedure TestAMoveLeavesTheSourceAsItIsWhenItChanged;
    procedure TestATargetFreedByItsHandlersStopsTheDrop;
    procedure TestASourceFreedDuringTheDropStopsThere;
    procedure TestASourceFreedByItsOwnHandlersStopsThere;
    procedure TestTheTwoSwitchesAreIndependent;
    procedure TestAMoveIsACutAndAPaste;
    procedure TestTheTargetsTickChangesTheCursorHere;
    procedure TestTheDropsFilterLeaksNothingAndStaysLinear;
    procedure TestAFormThatTakesNoInputIsNoTarget;
    {$IFDEF LCLWin32}
    procedure TestEveryPictureFileIsSizedForTheDropPlace;
    procedure TestAControlFreedDuringAnOleDropStopsThere;
    procedure TestWhatADataObjectMayGive;
    procedure TestDragOverFollowsTheAllowedEffects;
    procedure TestFileNamesAreLookedAtOncePerOffer;
    procedure TestAStreamIsReadWholeInFewSteps;
    procedure TestAnOleDropTakesWhatAPasteTakes;
    procedure TestTheEffectIsWhatHappened;
    procedure TestARefusedOleDropReportsNothing;
    procedure TestDroppedFiles;
    procedure TestRegistrationFollowsTheWindow;
    procedure TestTheControlGoesDuringAnOleDrag;
    procedure TestTheOleKeysAndAStreamedMedium;
    {$ENDIF}
  end;

{$IFDEF LCLWin32}
{ For the performance suite: a data object offering ARtf; another program's drag of it over
  ATarget (a control's drop target) at P, coming in (DragEnter) and dropped (Drop) - each the
  effect answered (DROPEFFECT_*), a copy allowed. }
function NewRtfData(const ARtf: RawByteString): TTestData;
function OleEnterWith(const ATarget: IUnknown; AData: TTestData; const P: TPoint): LongWord;
function OleDropWith(const ATarget: IUnknown; AData: TTestData; const P: TPoint): LongWord;
{$ENDIF}

implementation

{ ---- helpers ---- }

var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Application.Initialize;
  WidgetSetReady := True;
end;

function RawBytes(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[0], Length(S));
end;

function StrOfBytes(const B: TBytes): RawByteString;
begin
  Result := '';
  SetLength(Result, Length(B));
  if Length(B) > 0 then Move(B[0], Result[1], Length(B));
end;

function PngOf(AW, AH: Integer): TBytes;
var
  b: TBGRABitmap;
  st: TBytesStream;
begin
  b := TBGRABitmap.Create(AW, AH, BGRA(30, 120, 200, 255));
  st := TBytesStream.Create;
  try
    b.SaveToStreamAs(st, ifPng);
    Result := Copy(st.Bytes, 0, st.Size);
  finally
    st.Free;
    b.Free;
  end;
end;

{ A 2x2 bottom-up 24-bit DIB (CF_DIB's bytes: the header and the pixels). }
function DibOf: TBytes;
var
  i: Integer;
begin
  Result := nil;
  SetLength(Result, 40 + 16);
  FillChar(Result[0], Length(Result), 0);
  Result[0] := 40;
  Result[4] := 2;
  Result[8] := 2;
  Result[12] := 1;
  Result[14] := 24;
  for i := 40 to High(Result) do Result[i] := $80;
end;

function Head: RawByteString;
begin
  Result := '{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}{\f1 Courier New;}}' +
    '{\colortbl ;\red200\green0\blue0;}' + #13#10;
end;

function TableRtf(ARows: Integer): RawByteString;
var
  k: Integer;
begin
  Result := Head + '\pard\f0\fs20 before the table\par' + #13#10;
  for k := 0 to ARows - 1 do
    Result := Result + '\trowd\trgaph108\cellx2400\cellx4800\cellx7200' + #13#10 +
      '\pard\intbl r' + IntToStr(k) + ' a\cell r' + IntToStr(k) + ' \b b\b0\cell r' +
      IntToStr(k) + ' c\cell\row' + #13#10;
  Result := Result + '\pard after the table\par' + #13#10 + '}';
end;

{ ---- the probe ---- }

function TAcrossProbe.DropTargetAt(X, Y: Integer; out ATargetX,
  ATargetY: Integer): TTyCustomRichEdit;
begin
  Inc(TargetAsks);
  Result := nil;
  ATargetX := 0;
  ATargetY := 0;
  if Other = nil then Exit;
  if (X < OtherAt.X) or (Y < OtherAt.Y) or (X >= OtherAt.X + Other.Width) or
    (Y >= OtherAt.Y + Other.Height) then Exit;
  // (the control's own rule for the one found)
  if not DropTargetTakesInput(Other) then Exit;
  Result := Other;
  ATargetX := X - OtherAt.X;
  ATargetY := Y - OtherAt.Y;
end;

function TAcrossProbe.DropModalForm: TCustomForm;
begin
  if UseModal then Result := ModalForm else Result := inherited DropModalForm;
end;

function TAcrossProbe.DropFilesArePictures(const AFiles: TStringArray): Boolean;
begin
  Inc(NameChecks, Length(AFiles));
  Result := inherited DropFilesArePictures(AFiles);
end;

function TAcrossProbe.MakeFragmentFilter(ASource: TTyRichDocument): TTyRichFragmentFilter;
var
  c: TCountedFilter;
begin
  Result := inherited MakeFragmentFilter(ASource);
  if not (CountInner or ChangePictures) then Exit;
  c := TCountedFilter.Create(Result);
  c.Change := ChangePictures;
  Result := c;
end;

function TAcrossProbe.DropFragmentFilter(AOffer: TTyRichDropOffer;
  AInner: TTyRichFragmentFilter): TTyRichFragmentFilter;
begin
  if FailFilter then raise EOutOfMemory.Create('the test''s failing filter');
  Result := inherited DropFragmentFilter(AOffer, AInner);
end;

constructor TCountedFilter.Create(AInner: TTyRichFragmentFilter);
begin
  inherited Create;
  Inner := AInner;
  Inc(Live);
end;

destructor TCountedFilter.Destroy;
begin
  Dec(Live);
  Inner.Free;
  inherited Destroy;
end;

function TCountedFilter.KeepFragment(const AFragment: RawByteString; APara: Boolean): Boolean;
begin
  Result := Inner.KeepFragment(AFragment, APara);
end;

function TCountedFilter.RowFormat(const ARaw: RawByteString): RawByteString;
begin
  Result := Inner.RowFormat(ARaw);
end;

function TCountedFilter.MapObject(AObj: TTyRichObject; out AText: UTF8String): TTyRichObject;
var
  p: TTyRichPicture;
  b: TBytes;
begin
  Result := Inner.MapObject(AObj, AText);
  if not Change or not (Result is TTyRichPicture) then Exit;
  p := TTyRichPicture(Result);
  b := Copy(p.Data, 0, Length(p.Data));
  if Length(b) > 0 then b[High(b)] := b[High(b)] xor $FF;
  Result := TTyRichPicture.Create(p.PictureFormat, b, p.WidthTwips, p.HeightTwips);
  if p <> AObj then p.Free;
end;

function TAcrossProbe.DropPointOf(const AScreen: TPoint): TPoint;
begin
  // (no window: the screen is the client's pixels)
  Result := AScreen;
end;

procedure TAcrossProbe.FocusAfterDrop;
begin
  // (never the real focus or the foreground in a test)
  Inc(FocusCalls);
  if Assigned(OnFocusAfter) then OnFocusAfter(Self);
end;

function TAcrossProbe.ReadRtfSource(const ABytes: TBytes;
  out AEndsWithParagraph: Boolean): TTyRichDocument;
begin
  if FailRead then raise EOutOfMemory.Create('the test''s failing read');
  Result := inherited ReadRtfSource(ABytes, AEndsWithParagraph);
end;

function TAcrossProbe.DropEffectAt(AOffer: TTyRichDropOffer; APos: TTyRichPos;
  AShift: TShiftState): TTyRichDropEffect;
begin
  if RaiseInVerdict then raise Exception.Create('the test''s failing verdict');
  Result := inherited DropEffectAt(AOffer, APos, AShift);
end;

{$IFDEF LCLWin32}
function TAcrossProbe.Target: IDropTarget;
begin
  Result := OleDropTarget as IDropTarget;
end;

{ ---- the data object ---- }

var
  RtfFormat, PngFormat, HtmlFormat: Word;

procedure NeedFormats;
begin
  if RtfFormat <> 0 then Exit;
  RtfFormat := Windows.RegisterClipboardFormat('Rich Text Format');
  PngFormat := Windows.RegisterClipboardFormat('PNG');
  HtmlFormat := Windows.RegisterClipboardFormat('HTML Format');
end;

constructor TTestData.Create;
begin
  inherited Create;
  NeedFormats;
  Inc(Alive);
end;

destructor TTestData.Destroy;
begin
  Dec(Alive);
  inherited Destroy;
end;

function GlobalOf(P: Pointer; N: PtrUInt): HGLOBAL;
var
  q: Pointer;
begin
  Result := GlobalAlloc(GMEM_MOVEABLE, Math.Max(N, 1));
  q := GlobalLock(Result);
  if N > 0 then Move(P^, q^, N);
  GlobalUnlock(Result);
end;

function TTestData.QueryGetData(const pformatetc: FORMATETC): HRESULT; stdcall;
var
  f: Word;
  have: Boolean;
begin
  Inc(Queries);
  if pformatetc.tymed and (TYMED_HGLOBAL or TYMED_ISTREAM) = 0 then Exit(DV_E_TYMED);
  f := pformatetc.cfFormat;
  have := ((f = RtfFormat) and HasRtf) or ((f = PngFormat) and (Png <> nil)) or
    ((f = CF_DIB) and (Dib <> nil)) or ((f = CF_UNICODETEXT) and HasText) or
    ((f = CF_HDROP) and ((FileNames <> nil) or HasFiles or (RawDrop <> ''))) or
    ((f = HtmlFormat) and Html) or ((f = CF_TEXT) and HasAnsi) or
    ((f = CF_LOCALE) and (Locale <> 0)) or ((f = 17) and (DibV5 <> nil));
  if have then Result := S_OK else Result := DV_E_FORMATETC;
end;

function TTestData.GetData(const formatetcIn: FORMATETC; out medium: STGMEDIUM): HRESULT; stdcall;
var
  f: Word;
  b: RawByteString;
  w: UnicodeString;
  i: Integer;
  h: HGLOBAL;
  stm: IStream;
  ts: TTestStream;
begin
  FillChar(medium, SizeOf(medium), 0);
  Result := QueryGetData(formatetcIn);
  Dec(Queries);
  if Result <> S_OK then Exit;
  Inc(Gets);
  if FailGet then Exit(E_FAIL);
  f := formatetcIn.cfFormat;
  b := '';
  if f = RtfFormat then
  begin
    Inc(RtfGets);
    b := Rtf;
  end
  else if f = PngFormat then b := StrOfBytes(Png)
  else if f = CF_DIB then b := StrOfBytes(Dib)
  else if f = CF_UNICODETEXT then
  begin
    w := Text + #0;
    SetLength(b, Length(w) * 2);
    Move(w[1], b[1], Length(b));
  end
  else if f = CF_TEXT then b := Ansi + #0
  else if f = CF_LOCALE then
  begin
    SetLength(b, 4);
    Move(Locale, b[1], 4);
  end
  else if f = 17 then b := StrOfBytes(DibV5)
  else if (f = CF_HDROP) and (RawDrop <> '') then b := RawDrop
  else if f = CF_HDROP then
  begin
    // DROPFILES: the names start after the 20-byte header; wide; each ends with a zero
    w := '';
    for i := 0 to High(FileNames) do w := w + FileNames[i] + #0;
    w := w + #0;
    SetLength(b, 20 + Length(w) * 2);
    FillChar(b[1], 20, 0);
    b[1] := #20;
    b[17] := #1;
    Move(w[1], b[21], Length(w) * 2);
  end;
  if (f = RtfFormat) and Streamed and ((StreamChunk > 0) or StreamAtEnd or StreamNoStat) then
  begin
    ts := TTestStream.Create;
    ts.Data := b;
    ts.Chunk := StreamChunk;
    ts.NoStat := StreamNoStat;
    if StreamAtEnd then ts.Position := Length(b);
    stm := ts;
    medium.Tymed := TYMED_ISTREAM;
    stm._AddRef;
    medium.pstm := Pointer(stm);
    medium.PUnkForRelease := nil;
    Exit;
  end;
  h := GlobalOf(PChar(b), Length(b));
  if (f = RtfFormat) and Streamed and (formatetcIn.tymed and TYMED_ISTREAM <> 0) then
  begin
    if CreateStreamOnHGlobal(h, True, stm) <> S_OK then Exit(E_FAIL);
    // (the stream's size: the data, not the block's rounding)
    stm.SetSize(Length(b));
    medium.Tymed := TYMED_ISTREAM;
    stm._AddRef;
    medium.pstm := Pointer(stm);
  end
  else
  begin
    medium.Tymed := TYMED_HGLOBAL;
    medium.HGLOBAL := h;
  end;
  medium.PUnkForRelease := nil;
end;

function TTestData.GetDataHere(const pformatetc: FormatETC; out medium: STGMEDIUM): HRESULT; stdcall;
begin
  FillChar(medium, SizeOf(medium), 0);
  Result := E_NOTIMPL;
end;

function TTestData.GetCanonicalFormatEtc(const pformatetcIn: FORMATETC;
  out pformatetcOut: FORMATETC): HResult; stdcall;
begin
  pformatetcOut := pformatetcIn;
  pformatetcOut.ptd := nil;
  Result := DATA_S_SAMEFORMATETC;
end;

function TTestData.SetData(const pformatetc: FORMATETC; var medium: STGMEDIUM;
  FRelease: BOOL): HRESULT; stdcall;
begin
  Result := E_NOTIMPL;
end;

function TTestData.EnumFormatEtc(dwDirection: DWord;
  out enumformatetcpara: IENUMFORMATETC): HRESULT; stdcall;
begin
  enumformatetcpara := nil;
  Result := E_NOTIMPL;
end;

function TTestData.DAdvise(const formatetc: FORMATETC; advf: DWORD; const AdvSink: IAdviseSink;
  out dwConnection: DWORD): HRESULT; stdcall;
begin
  dwConnection := 0;
  Result := OLE_E_ADVISENOTSUPPORTED;
end;

function TTestData.DUnadvise(dwconnection: DWord): HRESULT; stdcall;
begin
  Result := OLE_E_ADVISENOTSUPPORTED;
end;

function TTestData.EnumDAdvise(out enumAdvise: IEnumStatData): HResult; stdcall;
begin
  enumAdvise := nil;
  Result := OLE_E_ADVISENOTSUPPORTED;
end;

function TTestStream.Read(pv: Pointer; cb: DWORD; pcbRead: PDWORD): HRESULT; stdcall;
var
  n: Int64;
begin
  n := Length(Data) - Position;
  if n < 0 then n := 0;
  if n > cb then n := cb;
  if (Chunk > 0) and (n > Chunk) then n := Chunk;
  if n > 0 then Move(Data[Position + 1], pv^, n);
  Inc(Position, n);
  if pcbRead <> nil then pcbRead^ := n;
  if n < cb then Result := S_FALSE else Result := S_OK;
end;

function TTestStream.Write(pv: Pointer; cb: DWORD; pcbWritten: PDWORD): HRESULT; stdcall;
begin
  if pcbWritten <> nil then pcbWritten^ := 0;
  Result := STG_E_ACCESSDENIED;
end;

function TTestStream.Seek(dlibMove: LargeInt; dwOrigin: DWORD;
  out libNewPosition: LargeUInt): HResult; stdcall;
begin
  case dwOrigin of
    0: Position := dlibMove;
    1: Position := Position + dlibMove;
  else
    Position := Length(Data) + dlibMove;
  end;
  libNewPosition := Position;
  Result := S_OK;
end;

function TTestStream.SetSize(libNewSize: LargeUInt): HRESULT; stdcall;
begin
  Result := E_NOTIMPL;
end;

function TTestStream.CopyTo(stm: IStream; cb: LargeUInt; out cbRead: LargeUInt;
  out cbWritten: LargeUInt): HRESULT; stdcall;
begin
  cbRead := 0;
  cbWritten := 0;
  Result := E_NOTIMPL;
end;

function TTestStream.Commit(grfCommitFlags: DWORD): HRESULT; stdcall;
begin
  Result := S_OK;
end;

function TTestStream.Revert: HRESULT; stdcall;
begin
  Result := S_OK;
end;

function TTestStream.LockRegion(libOffset: LargeUInt; cb: LargeUInt; dwLockType: DWORD): HRESULT; stdcall;
begin
  Result := E_NOTIMPL;
end;

function TTestStream.UnlockRegion(libOffset: LargeUInt; cb: LargeUInt; dwLockType: DWORD): HRESULT; stdcall;
begin
  Result := E_NOTIMPL;
end;

function TTestStream.Stat(out statstg: TStatStg; grfStatFlag: DWORD): HRESULT; stdcall;
begin
  FillChar(statstg, SizeOf(statstg), 0);
  if NoStat then Exit(E_NOTIMPL);
  statstg.cbSize := Length(Data);
  Result := S_OK;
end;

function TTestStream.Clone(out stm: IStream): HRESULT; stdcall;
begin
  stm := nil;
  Result := E_NOTIMPL;
end;

function NewRtfData(const ARtf: RawByteString): TTestData;
begin
  Result := TTestData.Create;
  Result.Rtf := ARtf;
  Result.HasRtf := True;
end;

function OleEnterWith(const ATarget: IUnknown; AData: TTestData; const P: TPoint): LongWord;
var
  e: DWORD;
begin
  e := DROPEFFECT_COPY;
  (ATarget as IDropTarget).DragEnter(AData as IDataObject, MK_LBUTTON, P, e);
  Result := e;
end;

function OleDropWith(const ATarget: IUnknown; AData: TTestData; const P: TPoint): LongWord;
var
  e: DWORD;
begin
  e := DROPEFFECT_COPY;
  (ATarget as IDropTarget).Drop(AData as IDataObject, 0, P, e);
  Result := e;
end;

{ ---- the registration's stand-ins (the whole run's: no window is registered with the system) ---- }

function FakeRegister(AWnd: HWND; const ATarget: IDropTarget): HRESULT;
begin
  Inc(TOleCalls.Registers);
  TOleCalls.LastRegistered := AWnd;
  if TOleCalls.Keeping then TOleCalls.LastTarget := ATarget;
  if TOleCalls.Refuse then Result := CO_E_NOTINITIALIZED else Result := S_OK;
end;

function FakeRevoke(AWnd: HWND): HRESULT;
begin
  Inc(TOleCalls.Revokes);
  TOleCalls.LastRevoked := AWnd;
  Result := S_OK;
end;
{$ENDIF}

{ ---- fixture ---- }

procedure TTyRichDropAcrossTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FA := NewProbe;
  FB := NewProbe;
  FA.Other := FB;
  FA.OtherAt := Point(500, 0);
  FNames := nil;
  FHandle := 0;
  FEvents := 0;
  FTemp := '';
  {$IFDEF LCLWin32}
  TOleCalls.Registers := 0;
  TOleCalls.Revokes := 0;
  TOleCalls.LastTarget := nil;
  TOleCalls.Refuse := False;
  TOleCalls.Keeping := True;
  {$ENDIF}
  FDoomed := nil;
  FSrcEdit := 0;
end;

procedure TTyRichDropAcrossTest.TearDown;
var
  sr: TSearchRec;
begin
  FreeAndNil(FA);
  FreeAndNil(FB);
  FreeAndNil(FCtl);
  {$IFDEF LCLWin32}
  TOleCalls.LastTarget := nil;
  TOleCalls.Refuse := False;
  TOleCalls.Keeping := False;
  {$ENDIF}
  if (FTemp <> '') and DirectoryExists(FTemp) then
  begin
    if FindFirst(FTemp + PathDelim + '*', faAnyFile, sr) = 0 then
    try
      repeat
        if (sr.Attr and faDirectory) = 0 then DeleteFile(FTemp + PathDelim + sr.Name);
      until FindNext(sr) <> 0;
    finally
      FindClose(sr);
    end;
    RemoveDir(FTemp);
  end;
end;

function TTyRichDropAcrossTest.NewProbe: TAcrossProbe;
begin
  Result := TAcrossProbe.Create(nil);
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 300);
  Result.ResetCounts;
end;

procedure PaintAll(ARich: TAcrossProbe);
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(ARich.Width, ARich.Height);
    ARich.PaintPart(bmp.Canvas, Rect(0, 0, ARich.Width, ARich.Height), False);
  finally
    bmp.Free;
  end;
end;

procedure TTyRichDropAcrossTest.Load(ARich: TAcrossProbe; const S: string);
begin
  ARich.Lines.Text := S;
  ARich.Document.ClearUndo;
  ARich.Modified := False;
  ARich.UpdateView;
  PaintAll(ARich);
end;

procedure TTyRichDropAcrossTest.LoadRtf(ARich: TAcrossProbe; const S: RawByteString);
var
  st: TBytesStream;
begin
  st := TBytesStream.Create(RawBytes(S));
  try
    ARich.LoadFromStream(st);
  finally
    st.Free;
  end;
  ARich.FinishLoading;
  ARich.Document.ClearUndo;
  ARich.UpdateView;
  PaintAll(ARich);
end;

function TTyRichDropAcrossTest.SaveRtf(ARich: TAcrossProbe): RawByteString;
var
  st: TBytesStream;
begin
  st := TBytesStream.Create;
  try
    ARich.SaveToStream(st, rfRtf);
    Result := StrOfBytes(Copy(st.Bytes, 0, st.Size));
  finally
    st.Free;
  end;
end;

function TTyRichDropAcrossTest.TextOf(ARich: TAcrossProbe): string;
begin
  Result := StringReplace(ARich.Document.Text.GetText(0, ARich.Document.Text.Length), #13, '',
    [rfReplaceAll]);
end;

function TTyRichDropAcrossTest.Pt(ARich: TAcrossProbe; APos: TTyRichPos): TPoint;
var
  r: TRect;
begin
  r := ARich.PositionRect(APos);
  Result := Point(r.Left + 1, (r.Top + r.Bottom) div 2);
end;

function TTyRichDropAcrossTest.Mid(ARich: TAcrossProbe; APos: TTyRichPos): TPoint;
var
  r, r2: TRect;
begin
  r := ARich.PositionRect(APos);
  r2 := ARich.PositionRect(APos + 1);
  if (r2.Top = r.Top) and (r2.Left > r.Left + 2) then Result.X := (r.Left + r2.Left) div 2
  else Result.X := r.Left + 2;
  Result.Y := (r.Top + r.Bottom) div 2;
end;

function TTyRichDropAcrossTest.InB(const P: TPoint): TPoint;
begin
  Result := Point(P.X + FA.OtherAt.X, P.Y + FA.OtherAt.Y);
end;

procedure TTyRichDropAcrossTest.StartDrag(const AFrom, ATo: TPoint; AShift: TShiftState);
begin
  FA.PressAt(AFrom.X, AFrom.Y);
  AssertTrue('the press waits for a drag', FA.Pending);
  FA.MoveWith(AFrom.X, AFrom.Y + FA.Threshold + 1, AShift);
  AssertTrue('the drag began', FA.OwnDrag);
  FA.MoveWith(ATo.X, ATo.Y, AShift);
end;

procedure TTyRichDropAcrossTest.CheckNoClipboard(ARich: TAcrossProbe; const AWhat: string);
begin
  AssertEquals(AWhat + ': nothing written to the clipboard', 0, ARich.ClipWrites);
  AssertEquals(AWhat + ': its flavours never asked', 0, ARich.FlavourAsks);
  AssertEquals(AWhat + ': its formats never listed', 0, ARich.FormatAsks);
  AssertEquals(AWhat + ': no RTF read', 0, ARich.RtfReads);
  AssertEquals(AWhat + ': no text read', 0, ARich.TextReads);
  AssertEquals(AWhat + ': no picture read', 0, ARich.PictureReads);
end;

procedure TTyRichDropAcrossTest.DroppedFiles(Sender: TObject;
  const AFileNames: array of string; var AHandled: Boolean);
var
  i: Integer;
begin
  Inc(FEvents);
  SetLength(FNames, Length(AFileNames));
  for i := 0 to High(AFileNames) do FNames[i] := AFileNames[i];
  AHandled := FHandle <> 0;
end;

{ ---- between two controls ---- }

{ The selection dragged out of one control and released over another moves it there: the
  other control's mark and verdict while over it, none here; one step in each document (the
  target's insert, the source's removal - two histories, each undone on its own), the content
  selected there, the target focused; with Ctrl a copy - the source as it was. No clipboard. }
procedure TTyRichDropAcrossTest.TestADragIntoAnotherControlMovesOrCopies;
var
  m: TRect;
  p: TPoint;
begin
  Load(FA, 'one two three');
  Load(FB, 'alpha beta');
  FA.SelStart := 4;
  FA.SelLength := 3;
  p := InB(Pt(FB, 6));
  StartDrag(Mid(FA, 5), p);
  AssertTrue('a session there', FB.DropActive);
  AssertTrue('its mark there', FB.Mark(m));
  AssertFalse('no mark here', FA.Mark(m));
  AssertTrue('the verdict there: a move', FB.Effect = rdeMove);
  AssertTrue('the cursor here says it', FA.CursorFor(p.X, p.Y) = crDrag);
  AssertTrue('found through the lookup', FA.TargetAsks > 0);
  AssertEquals('nothing changed before the drop', 0, FA.Document.UndoDepth + FB.Document.UndoDepth);
  FA.ReleaseWith(p.X, p.Y, []);
  AssertFalse('the drag ended', FA.OwnDrag);
  AssertFalse('the session there ended', FB.DropActive);
  AssertEquals('there: the text', 'alpha twobeta', TextOf(FB));
  AssertEquals('here: the text', 'one  three', TextOf(FA));
  AssertEquals('there: one step', 1, FB.Document.UndoDepth);
  AssertEquals('there: named Move', rsRichUndoMove, FB.Document.UndoDescription);
  AssertEquals('here: one step', 1, FA.Document.UndoDepth);
  AssertEquals('here: named Move', rsRichUndoMove, FA.Document.UndoDescription);
  AssertEquals('there: what went in selected', Int64(6), FB.SelStart);
  AssertEquals('there: its length', Int64(3), FB.SelLength);
  AssertEquals('here: the caret where it was', Int64(4), FA.SelStart);
  AssertEquals('here: nothing selected', Int64(0), FA.SelLength);
  AssertEquals('the target takes the focus', 1, FB.FocusCalls);
  AssertEquals('the source does not', 0, FA.FocusCalls);
  // two histories: each undone on its own
  FB.Undo;
  AssertEquals('undo there', 'alpha beta', TextOf(FB));
  AssertEquals('undo there leaves this', 'one  three', TextOf(FA));
  FA.Undo;
  AssertEquals('undo here', 'one two three', TextOf(FA));
  AssertEquals('undo here: the selection', Int64(4), FA.SelStart);
  AssertEquals('undo here: its length', Int64(3), FA.SelLength);
  // with Ctrl: a copy, the source as it was
  FA.Document.ClearUndo;
  FB.Document.ClearUndo;
  FA.SelStart := 4;
  FA.SelLength := 3;
  p := InB(Pt(FB, 0));
  StartDrag(Mid(FA, 5), p, [ssCtrl]);
  AssertTrue('Ctrl: a copy there', FB.Effect = rdeCopy);
  AssertTrue('Ctrl: the cursor says it', FA.CursorFor(p.X, p.Y) = crMultiDrag);
  FA.ReleaseWith(p.X, p.Y, [ssCtrl]);
  AssertEquals('copied there', 'twoalpha beta', TextOf(FB));
  AssertEquals('copied there: named Copy', rsRichUndoCopy, FB.Document.UndoDescription);
  AssertEquals('the source as it was', 'one two three', TextOf(FA));
  AssertEquals('the source: no step', 0, FA.Document.UndoDepth);
  AssertEquals('the source: its selection', Int64(3), FA.SelLength);
  CheckNoClipboard(FA, 'the source');
  CheckNoClipboard(FB, 'the target');
end;

{ What the target does not take leaves the source as it was: a read-only target, one with
  DragDropEditing off or disabled (not here: no session, "not here"); one whose document takes
  no edit, and an insert that fails (memory) - told once there, nothing done anywhere. }
procedure TTyRichDropAcrossTest.TestARefusedOrFailedDropKeepsTheSource;
var
  i: Integer;
  p: TPoint;
  what: string;
begin
  for i := 0 to 4 do
  begin
    Load(FA, 'one two three');
    Load(FB, 'alpha beta');
    FB.Refused := 0;
    case i of
      0: FB.ReadOnly := True;
      1: FB.DragDropEditing := False;
      2: FB.Enabled := False;
      3: TDragLoadState.Put(FB.Document, True);
      4: FB.FailRead := True;
    end;
    what := Format('case %d', [i]);
    FA.SelStart := 4;
    FA.SelLength := 3;
    p := InB(Pt(FB, 6));
    StartDrag(Mid(FA, 5), p);
    if i < 3 then
    begin
      AssertFalse(what + ': no session there', FB.DropActive);
      AssertTrue(what + ': not here', FA.Effect = rdeNone);
      AssertTrue(what + ': the cursor', FA.CursorFor(p.X, p.Y) = crNoDrop);
    end
    else if i = 3 then
      AssertTrue(what + ': not here', FA.Effect = rdeNone)
    else
      AssertTrue(what + ': a move there', FA.Effect = rdeMove);
    FA.ReleaseWith(p.X, p.Y, []);
    AssertEquals(what + ': the source as it was', 'one two three', TextOf(FA));
    AssertEquals(what + ': the source, no step', 0, FA.Document.UndoDepth);
    AssertEquals(what + ': the source''s selection', Int64(4), FA.SelStart);
    AssertEquals(what + ': its length', Int64(3), FA.SelLength);
    AssertEquals(what + ': the target as it was', 'alpha beta', TextOf(FB));
    AssertEquals(what + ': the target, no step', 0, FB.Document.UndoDepth);
    AssertEquals(what + ': no focus taken', 0, FB.FocusCalls);
    case i of
      0, 1, 2: AssertEquals(what + ': nothing told', 0, FB.Refused);
      3:
        begin
          AssertEquals(what + ': told once', 1, FB.Refused);
          AssertEquals(what + ': why', rsRichEditRefusedIncomplete, FB.LastReason);
        end;
      4:
        begin
          AssertEquals(what + ': told once', 1, FB.Refused);
          AssertEquals(what + ': why', rsRichEditRefusedMemory, FB.LastReason);
        end;
    end;
    FB.ReadOnly := False;
    FB.DragDropEditing := True;
    FB.Enabled := True;
    FB.FailRead := False;
    TDragLoadState.Put(FB.Document, False);
  end;
end;

{ A read-only control's selection can be dragged out, as a copy (the cursor says so, Ctrl or
  not); inside it nothing is a place. A selection the source's cut would refuse (across
  cells) goes out as a copy too. }
procedure TTyRichDropAcrossTest.TestAReadOnlySourceIsCopiedOut;
var
  p, q: TPoint;
  m: TRect;
  t: TTyRichText;
begin
  Load(FA, 'one two three');
  Load(FB, 'alpha beta');
  FA.ReadOnly := True;
  FA.SelStart := 4;
  FA.SelLength := 3;
  q := Pt(FA, 11);
  StartDrag(Mid(FA, 5), q);
  AssertTrue('inside a read-only control: not here', FA.Effect = rdeNone);
  AssertFalse('inside it: no mark', FA.Mark(m));
  AssertTrue('inside it: the cursor', FA.CursorFor(q.X, q.Y) = crNoDrop);
  FA.ReleaseWith(q.X, q.Y, []);
  AssertEquals('released inside: the text', 'one two three', TextOf(FA));
  AssertEquals('released inside: the selection', Int64(3), FA.SelLength);
  p := InB(Pt(FB, 6));
  StartDrag(Mid(FA, 5), p);
  AssertTrue('there without Ctrl: a copy', FB.Effect = rdeCopy);
  AssertTrue('the cursor says a copy', FA.CursorFor(p.X, p.Y) = crMultiDrag);
  FA.ReleaseWith(p.X, p.Y, []);
  AssertEquals('copied there', 'alpha twobeta', TextOf(FB));
  AssertEquals('named Copy', rsRichUndoCopy, FB.Document.UndoDescription);
  AssertEquals('the source as it was', 'one two three', TextOf(FA));
  AssertEquals('the source: no step', 0, FA.Document.UndoDepth);
  // a selection across cells: its cut refuses it - a copy there
  FA.ReadOnly := False;
  LoadRtf(FA, TableRtf(2));
  Load(FB, 'alpha beta');
  t := FA.Document.Text;
  FA.SelStart := t.ParaStart(1) + 1;
  FA.SelLength := 6;
  p := InB(Pt(FB, 6));
  StartDrag(Mid(FA, t.ParaStart(1) + 2), p);
  AssertTrue('across cells: a copy there', FB.Effect = rdeCopy);
  FA.ReleaseWith(p.X, p.Y, []);
  AssertEquals('across cells: the source, no step', 0, FA.Document.UndoDepth);
  AssertEquals('across cells: one step there', 1, FB.Document.UndoDepth);
  AssertEquals('across cells: named Copy', rsRichUndoCopy, FB.Document.UndoDescription);
end;

{ A picture moved into another document: the target's own object (not the source's - which
  stays in the source's history: undo there gives the very one back), with the source's very
  bytes; the target saves what a copy and a paste of the same selection give there. Whole rows
  go in as rows of a table of the target's own. }
procedure TTyRichDropAcrossTest.TestPicturesAndRowsGoAcrossAsAPasteTakesThem;
var
  pic, got: TTyRichPicture;
  r: TRect;
  p: TPoint;
  c: TAcrossProbe;
  t: TTyRichText;
  k: Integer;
  dropped, pasted: RawByteString;
begin
  Load(FA, 'first line'#13#10'abcd');
  Load(FB, 'alpha beta');
  pic := TTyRichPicture.Create(rpfPng, PngOf(40, 30), 600, 450);
  AssertTrue('a picture', FA.Document.Execute(TTyRichInsertObject.Create(13, pic)));
  FA.Document.ClearUndo;
  FA.UpdateView;
  PaintAll(FA);
  FA.SelStart := 13;
  FA.SelLength := 1;
  r := FA.PositionRect(13);
  p := InB(Pt(FB, 6));
  StartDrag(Point(r.Left + 12, (r.Top + r.Bottom) div 2), p);
  FA.ReleaseWith(p.X, p.Y, []);
  got := TTyRichPicture(FB.Document.ObjectAt(6));
  AssertTrue('a picture there', (got <> nil) and (got is TTyRichPicture));
  AssertTrue('the target''s own object', got <> pic);
  AssertTrue('the source''s very bytes', Pointer(got.Data) = Pointer(pic.Data));
  AssertTrue('gone from the source', FA.Document.ObjectAt(13) = nil);
  FA.Undo;
  AssertTrue('undo there: the very object back', FA.Document.ObjectAt(13) = pic);
  // what a copy and a paste of it give there
  dropped := SaveRtf(FB);
  c := NewProbe;
  try
    Load(c, 'alpha beta');
    FA.SelStart := 13;
    FA.SelLength := 1;
    FA.CopyToClipboard;
    c.ClipRtf := FA.ClipRtf;
    c.ClipText := FA.ClipText;
    c.SelStart := 6;
    c.PasteFromClipboard;
    pasted := SaveRtf(c);
  finally
    c.Free;
  end;
  AssertEquals('the picture: what a paste gives there', pasted, dropped);
  // whole rows, into a place in no table: rows of a table of the target's own
  LoadRtf(FA, TableRtf(2));
  Load(FB, 'alpha beta');
  t := FA.Document.Text;
  FA.SelStart := t.ParaStart(1);
  FA.SelLength := t.ParaStart(4) - t.ParaStart(1);
  PaintAll(FA);
  p := InB(Pt(FB, 6));
  StartDrag(Mid(FA, t.ParaStart(1) + 1), p);
  FA.ReleaseWith(p.X, p.Y, []);
  AssertEquals('rows: one step there', 1, FB.Document.UndoDepth);
  AssertEquals('rows: one step here', 1, FA.Document.UndoDepth);
  k := -1;
  for k := 0 to FB.Document.Text.ParaCount - 1 do
    if FB.Document.CellAt(k) <> nil then Break;
  AssertTrue('rows: a table there', (k >= 0) and (k < FB.Document.Text.ParaCount) and
    (FB.Document.CellAt(k) <> nil));
  AssertTrue('rows: the target''s own table', FB.Document.CellAt(k).Table <>
    FA.Document.CellAt(1).Table);
  AssertTrue('rows: gone from the source', Pos('r0 a', TextOf(FA)) = 0);
  dropped := SaveRtf(FB);
  FA.Undo;
  c := NewProbe;
  try
    Load(c, 'alpha beta');
    FA.SelStart := t.ParaStart(1);
    FA.SelLength := t.ParaStart(4) - t.ParaStart(1);
    FA.CopyToClipboard;
    c.ClipRtf := FA.ClipRtf;
    c.ClipText := FA.ClipText;
    c.SelStart := 6;
    c.PasteFromClipboard;
    pasted := SaveRtf(c);
  finally
    c.Free;
  end;
  AssertEquals('rows: what a paste gives there', pasted, dropped);
end;

{ A plain text target takes the text, as its paste does: no formats. }
procedure TTyRichDropAcrossTest.TestAPlainTextTargetTakesTheText;
var
  p: TPoint;
  runs: TTyRunArray;
begin
  LoadRtf(FA, Head + '\pard\f0 one \b two\b0  three\par' + #13#10 + '}');
  Load(FB, 'alpha beta');
  FB.PlainText := True;
  FA.SelStart := 4;
  FA.SelLength := 3;
  PaintAll(FA);
  p := InB(Pt(FB, 6));
  StartDrag(Mid(FA, 5), p);
  AssertTrue('plain text: a move', FB.Effect = rdeMove);
  FA.ReleaseWith(p.X, p.Y, []);
  AssertEquals('plain text: the text there', 'alpha twobeta', TextOf(FB));
  runs := FB.Document.RunsOf(0);
  AssertEquals('plain text: one run, no format', 1, Length(runs));
  AssertEquals('plain text: moved', 'one  three', TextOf(FA));
end;

{ The other control's session follows the pointer: it ends when the pointer comes back, goes
  outside both, the drag ends (Esc); a content replaced there ends it (a new one at the next
  move, over the new content); a target freed during the drag is let go; a source freed during
  it ends the target's session. }
procedure TTyRichDropAcrossTest.TestTheSessionThereFollowsThePointerAndEnds;
var
  m: TRect;
  p: TPoint;
begin
  Load(FA, 'one two three');
  Load(FB, 'alpha beta');
  FA.SelStart := 4;
  FA.SelLength := 3;
  p := InB(Pt(FB, 6));
  StartDrag(Mid(FA, 5), p);
  AssertTrue('over it: a session', FB.DropActive);
  FA.MoveWith(Pt(FA, 11).X, Pt(FA, 11).Y, []);
  AssertFalse('back here: none there', FB.DropActive);
  AssertFalse('back here: no mark there', FB.Mark(m));
  AssertTrue('back here: the mark here', FA.Mark(m));
  FA.MoveWith(450, 10, []);
  AssertFalse('between them: none there', FB.DropActive);
  AssertFalse('between them: no mark here', FA.Mark(m));
  AssertTrue('between them: not here', FA.Effect = rdeNone);
  FA.MoveWith(p.X, p.Y, []);
  AssertTrue('over it again', FB.DropActive);
  FA.Press(VK_ESCAPE, []);
  AssertFalse('Esc: the drag ended', FA.OwnDrag);
  AssertFalse('Esc: the session there too', FB.DropActive);
  // the content replaced there
  StartDrag(Mid(FA, 5), p);
  AssertTrue('again over it', FB.DropActive);
  FB.Lines.Text := 'new text';
  FB.UpdateView;
  PaintAll(FB);
  AssertFalse('the content replaced: the session ended', FB.DropActive);
  AssertTrue('the drag goes on', FA.OwnDrag);
  AssertTrue('the content replaced: not here until the next move', FA.Effect = rdeNone);
  AssertTrue('the content replaced: the cursor says it', FA.CursorFor(p.X, p.Y) = crNoDrop);
  FA.MoveWith(InB(Pt(FB, 4)).X, InB(Pt(FB, 4)).Y, []);
  AssertTrue('the next move: a session over the new content', FB.DropActive);
  FA.ReleaseWith(InB(Pt(FB, 4)).X, InB(Pt(FB, 4)).Y, []);
  AssertEquals('dropped into the new content', 'new twotext', TextOf(FB));
  // the target freed during the drag
  FA.Undo;
  FA.SelStart := 4;
  FA.SelLength := 3;
  StartDrag(Mid(FA, 5), InB(Pt(FB, 2)));
  AssertTrue('over it once more', FB.DropActive);
  FA.Other := nil;
  FreeAndNil(FB);
  AssertTrue('the target gone: not here', FA.Effect = rdeNone);
  AssertTrue('the target gone: the cursor', FA.CursorFor(p.X, p.Y) = crNoDrop);
  FA.ReleaseWith(p.X, p.Y, []);
  AssertEquals('the target gone: the source as it was', 'one two three', TextOf(FA));
  AssertEquals('the target gone: the source, no step', 1, FA.Document.RedoDepth);
  // the source freed during the drag
  FB := NewProbe;
  Load(FB, 'alpha beta');
  FA.Other := FB;
  FA.SelStart := 4;
  FA.SelLength := 3;
  StartDrag(Mid(FA, 5), p);
  AssertTrue('a session over the new target', FB.DropActive);
  FreeAndNil(FA);
  AssertFalse('the source gone: the session there ended', FB.DropActive);
  AssertFalse('the source gone: no mark there', FB.Mark(m));
end;

{ Ctrl down and up during a drag over the other control: its verdict follows at once. Its own
  edge scrolling: its view scrolls near its edge, and the place, its mark and the cursor here
  follow the text that came. }
procedure TTyRichDropAcrossTest.TestKeysAndEdgeScrollingOverAnotherControl;
var
  s: string;
  i: Integer;
  p: TPoint;
  m, m2: TRect;
  y0: Int64;
begin
  Load(FA, 'one two three');
  s := 'line 0';
  for i := 1 to 60 do s := s + #13#10'line ' + IntToStr(i);
  Load(FB, s);
  FA.SelStart := 4;
  FA.SelLength := 3;
  p := InB(Pt(FB, 2));
  StartDrag(Mid(FA, 5), p);
  AssertTrue('a move there', FB.Effect = rdeMove);
  FA.Press(VK_CONTROL, [ssCtrl]);
  AssertTrue('Ctrl down: a copy there', FB.Effect = rdeCopy);
  AssertTrue('Ctrl down: the cursor here', FA.CursorFor(p.X, p.Y) = crMultiDrag);
  FA.KeyUpOf(VK_CONTROL, []);
  AssertTrue('Ctrl up: a move again', FB.Effect = rdeMove);
  AssertTrue('Ctrl up: the cursor here', FA.CursorFor(p.X, p.Y) = crDrag);
  // the other's lower edge: its own edge band, its own scrolling
  p := Point(FA.OtherAt.X + 100, FA.OtherAt.Y + FB.Height - 2);
  FA.MoveWith(p.X, p.Y, []);
  AssertTrue('near its edge: a mark there', FB.Mark(m));
  y0 := FB.ScrollY;
  FB.DragTick;
  PaintAll(FB);
  AssertTrue('its view scrolled', FB.ScrollY > y0);
  AssertTrue('the mark at the place under the pointer', FB.Mark(m2));
  AssertTrue('the session there goes on', FB.DropActive);
  AssertTrue('the cursor here: a move', FA.CursorFor(p.X, p.Y) = crDrag);
  FA.ReleaseWith(p.X, p.Y, []);
  AssertEquals('dropped there: one step', 1, FB.Document.UndoDepth);
  AssertEquals('removed here: one step', 1, FA.Document.UndoDepth);
  AssertTrue('dropped there, below what was shown at first',
    Pos('two', TextOf(FB)) > Pos('line 9', TextOf(FB)));
end;

{ ---- what the application's handlers may do during a drop ---- }

procedure TTyRichDropAcrossTest.FreeDoomed;
var
  o: TAcrossProbe;
begin
  o := FDoomed;
  if o = nil then Exit;
  FDoomed := nil;
  if o = FA then FA := nil;
  if o = FB then FB := nil;
  if (FA <> nil) and (FA.Other = o) then FA.Other := nil;
  o.Free;
end;

procedure TTyRichDropAcrossTest.DoomOnNotify(Sender: TObject);
begin
  FreeDoomed;
end;

procedure TTyRichDropAcrossTest.DoomOnRefused(Sender: TObject; const AReason: string);
begin
  FreeDoomed;
end;

procedure TTyRichDropAcrossTest.DoomOnFiles(Sender: TObject; const AFileNames: array of string;
  var AHandled: Boolean);
begin
  Inc(FEvents);
  AHandled := FHandle <> 0;
  FreeDoomed;
end;

procedure TTyRichDropAcrossTest.EditTheSource(Sender: TObject);
var
  k: Integer;
begin
  k := FSrcEdit;
  FSrcEdit := 0;
  case k of
    1: FA.Document.Execute(TTyRichInsertText.Create(0, 'ZZ', FA.Document.TypingFormatAt(0),
         False));
    2: FA.Lines.Text := 'replaced text';
  end;
end;

function TTyRichDropAcrossTest.CursorOf(AEffect: TTyRichDropEffect): TCursor;
begin
  case AEffect of
    rdeMove: Result := crDrag;
    rdeCopy: Result := crMultiDrag;
  else
    Result := crNoDrop;
  end;
end;

{ The target's OnChange changes the source while it takes the content (an edit there, a new
  text): the source removes nothing - the content is in both, never lost, and nothing is told.
  Unchanged, it moves. }
procedure TTyRichDropAcrossTest.TestAMoveLeavesTheSourceAsItIsWhenItChanged;
var
  i: Integer;
  p: TPoint;
  what: string;
begin
  for i := 0 to 2 do
  begin
    what := Format('case %d', [i]);
    Load(FA, 'one two three');
    Load(FB, 'alpha beta');
    FA.Refused := 0;
    FB.OnChange := @EditTheSource;
    FSrcEdit := i;
    FA.SelStart := 4;
    FA.SelLength := 3;
    p := InB(Pt(FB, 6));
    StartDrag(Mid(FA, 5), p);
    FA.ReleaseWith(p.X, p.Y, []);
    FB.OnChange := nil;
    AssertEquals(what + ': the target took it', 'alpha twobeta', TextOf(FB));
    case i of
      0:
        begin
          AssertEquals(what + ': unchanged, it moved', 'one  three', TextOf(FA));
          AssertEquals(what + ': its step', rsRichUndoMove, FA.Document.UndoDescription);
        end;
      1:
        begin
          AssertEquals(what + ': changed, nothing removed', 'ZZone two three', TextOf(FA));
          AssertEquals(what + ': only the change''s step', 1, FA.Document.UndoDepth);
        end;
      2: AssertEquals(what + ': a new text, nothing removed', 'replaced text', TextOf(FA));
    end;
    AssertEquals(what + ': nothing told', 0, FA.Refused);
  end;
end;

{ The target freed by its own handler while it takes the content (OnChange, OnSelectionChange,
  OnEditRefused, or one the focus change runs): nothing of it is touched after (freed memory
  is poisoned), the source keeps its content, the drag is over. }
procedure TTyRichDropAcrossTest.TestATargetFreedByItsHandlersStopsTheDrop;
var
  i: Integer;
  p: TPoint;
  what: string;
begin
  for i := 0 to 3 do
  begin
    what := Format('case %d', [i]);
    if FB = nil then
    begin
      FB := NewProbe;
      FA.Other := FB;
    end;
    Load(FA, 'one two three');
    Load(FB, 'alpha beta');
    case i of
      0: FB.OnChange := @DoomOnNotify;
      1: FB.OnSelectionChange := @DoomOnNotify;
      2:
        begin
          FB.FailRead := True;
          FB.OnEditRefused := @DoomOnRefused;
        end;
      3: FB.OnFocusAfter := @DoomOnNotify;
    end;
    FA.SelStart := 4;
    FA.SelLength := 3;
    p := InB(Pt(FB, 6));
    StartDrag(Mid(FA, 5), p);
    FDoomed := FB;
    PoisonFreedMemory(True);
    try
      FA.ReleaseWith(p.X, p.Y, []);
    finally
      PoisonFreedMemory(False);
    end;
    AssertTrue(what + ': freed by its handler', FB = nil);
    AssertEquals(what + ': the source keeps its content', 'one two three', TextOf(FA));
    AssertEquals(what + ': the source, no step', 0, FA.Document.UndoDepth);
    AssertFalse(what + ': the drag is over', FA.OwnDrag);
  end;
end;

{ The source freed by a handler run on the target's side during the drop (the target's
  OnChange, OnSelectionChange, OnEditRefused, one the focus change runs), the release by the
  button-up or by the capture's end: the source's drop and its caller stop there (freed memory
  poisoned); the target has what it took, its session is over. }
procedure TTyRichDropAcrossTest.TestASourceFreedDuringTheDropStopsThere;
var
  i: Integer;
  p: TPoint;
  what: string;
begin
  for i := 0 to 4 do
  begin
    what := Format('case %d', [i]);
    if FA = nil then
    begin
      FA := NewProbe;
      FA.Other := FB;
      FA.OtherAt := Point(500, 0);
    end;
    Load(FA, 'one two three');
    Load(FB, 'alpha beta');
    FB.OnChange := nil;
    FB.OnSelectionChange := nil;
    FB.OnEditRefused := nil;
    FB.OnFocusAfter := nil;
    FB.FailRead := False;
    case i of
      0, 4: FB.OnChange := @DoomOnNotify;
      1: FB.OnSelectionChange := @DoomOnNotify;
      2:
        begin
          FB.FailRead := True;
          FB.OnEditRefused := @DoomOnRefused;
        end;
      3: FB.OnFocusAfter := @DoomOnNotify;
    end;
    FA.SelStart := 4;
    FA.SelLength := 3;
    p := InB(Pt(FB, 6));
    StartDrag(Mid(FA, 5), p);
    FDoomed := FA;
    PoisonFreedMemory(True);
    try
      if i = 4 then
      begin
        FA.ButtonUp := True;
        FA.LoseCapture;
      end
      else
        FA.ReleaseWith(p.X, p.Y, []);
    finally
      PoisonFreedMemory(False);
    end;
    AssertTrue(what + ': the source freed', FA = nil);
    if i = 2 then AssertEquals(what + ': nothing there', 'alpha beta', TextOf(FB))
    else AssertEquals(what + ': what the target took', 'alpha twobeta', TextOf(FB));
    AssertFalse(what + ': no session there', FB.DropActive);
  end;
  FB.OnChange := nil;
  FB.OnSelectionChange := nil;
  FB.OnEditRefused := nil;
  FB.OnFocusAfter := nil;
end;

{ The source freed by its own OnChange / OnSelectionChange, run by the removal of what moved;
  a control freed by its own OnChange during a drop inside it: each stops there. }
procedure TTyRichDropAcrossTest.TestASourceFreedByItsOwnHandlersStopsThere;
var
  i: Integer;
  p: TPoint;
  what: string;
begin
  for i := 0 to 2 do
  begin
    what := Format('case %d', [i]);
    if FA = nil then
    begin
      FA := NewProbe;
      FA.Other := FB;
      FA.OtherAt := Point(500, 0);
    end;
    Load(FA, 'one two three');
    Load(FB, 'alpha beta');
    FA.SelStart := 4;
    FA.SelLength := 3;
    if i < 2 then p := InB(Pt(FB, 6)) else p := Pt(FA, 13);
    StartDrag(Mid(FA, 5), p);
    if i = 1 then FA.OnSelectionChange := @DoomOnNotify else FA.OnChange := @DoomOnNotify;
    FDoomed := FA;
    PoisonFreedMemory(True);
    try
      FA.ReleaseWith(p.X, p.Y, []);
    finally
      PoisonFreedMemory(False);
    end;
    AssertTrue(what + ': freed by its own handler', FA = nil);
    if i < 2 then
    begin
      AssertEquals(what + ': the target has it', 'alpha twobeta', TextOf(FB));
      AssertFalse(what + ': no session there', FB.DropActive);
    end;
  end;
end;

{ AcceptDrops governs another program's drops alone; DragDropEditing the control's own drag and
  drags between controls (as source and as target) and an offer an application feeds through
  the receiving side. Every combination, every path; a session from another program outlives
  DragDropEditing set off, and ends with AcceptDrops set off. }
procedure TTyRichDropAcrossTest.TestTheTwoSwitchesAreIndependent;
var
  k: Integer;
  dde, ad: Boolean;
  p: TPoint;
  what: string;
  offer: TTestOffer;
  {$IFDEF LCLWin32}
  d: TTestData;
  di: IDataObject;
  e: DWORD;
  {$ENDIF}
begin
  for k := 0 to 3 do
  begin
    dde := k mod 2 = 0;
    ad := k < 2;
    what := Format('DragDropEditing %s, AcceptDrops %s', [BoolToStr(dde, True), BoolToStr(ad, True)]);
    // the control's own drag
    Load(FA, 'one two three');
    FA.DragDropEditing := dde;
    FA.AcceptDrops := ad;
    FA.SelStart := 4;
    FA.SelLength := 3;
    p := Mid(FA, 5);
    FA.PressAt(p.X, p.Y);
    AssertEquals(what + ': its own drag waits', dde, FA.Pending);
    FA.ReleaseAt(p.X, p.Y);
    FA.DragDropEditing := True;
    FA.AcceptDrops := True;
    // from another control
    Load(FA, 'one two three');
    Load(FB, 'alpha beta');
    FB.DragDropEditing := dde;
    FB.AcceptDrops := ad;
    FA.SelStart := 4;
    FA.SelLength := 3;
    p := InB(Pt(FB, 6));
    StartDrag(Mid(FA, 5), p);
    AssertEquals(what + ': another control''s drag there', dde, FB.DropActive);
    FA.ReleaseWith(p.X, p.Y, []);
    if dde then AssertEquals(what + ': taken from another control', 'alpha twobeta', TextOf(FB))
    else AssertEquals(what + ': not taken from another control', 'alpha beta', TextOf(FB));
    // an application's offer through the receiving side
    Load(FB, 'alpha beta');
    offer := TTestOffer.Create;
    try
      offer.Text := 'x';
      if dde then
        AssertTrue(what + ': an application''s offer', FB.DropEnter(offer, Pt(FB, 2).X, Pt(FB, 2).Y,
          []) = rdeCopy)
      else
        AssertTrue(what + ': no application''s offer', FB.DropEnter(offer, Pt(FB, 2).X,
          Pt(FB, 2).Y, []) = rdeNone);
      FB.DropLeave;
    finally
      offer.Free;
    end;
    {$IFDEF LCLWin32}
    // from another program
    d := TTestData.Create;
    di := d;
    d.Text := 'NEW';
    d.HasText := True;
    p := Pt(FB, 6);
    e := Enter(FB, d, p, MK_LBUTTON, DROPEFFECT_COPY);
    if ad then AssertEquals(what + ': another program''s drop', DROPEFFECT_COPY, e)
    else AssertEquals(what + ': no drop of another program''s', DROPEFFECT_NONE, e);
    e := DropAt(FB, d, p, 0, DROPEFFECT_COPY);
    if ad then AssertEquals(what + ': another program''s content', 'alpha NEWbeta', TextOf(FB))
    else AssertEquals(what + ': nothing of another program''s', 'alpha beta', TextOf(FB));
    di := nil;
    {$ENDIF}
    FB.DragDropEditing := True;
    FB.AcceptDrops := True;
  end;
  {$IFDEF LCLWin32}
  // a session from another program: DragDropEditing set off leaves it, AcceptDrops off ends it
  Load(FB, 'alpha beta');
  d := TTestData.Create;
  di := d;
  d.Text := 'NEW';
  d.HasText := True;
  p := Pt(FB, 6);
  Enter(FB, d, p, MK_LBUTTON, DROPEFFECT_COPY);
  FB.DragDropEditing := False;
  AssertTrue('DragDropEditing off: the session goes on', FB.DropActive);
  FB.AcceptDrops := False;
  AssertFalse('AcceptDrops off: the session ended', FB.DropActive);
  e := DROPEFFECT_COPY;
  FB.Target.DragOver(MK_LBUTTON, p, e);
  AssertEquals('AcceptDrops off: not here any more', DROPEFFECT_NONE, e);
  AssertEquals('AcceptDrops off: nothing dropped', DROPEFFECT_NONE, DropAt(FB, d, p, 0,
    DROPEFFECT_COPY));
  AssertEquals('AcceptDrops off: the text', 'alpha beta', TextOf(FB));
  di := nil;
  {$ENDIF}
end;

{ A move into another control is a cut in the source and a paste in the target, a copy a copy
  and a paste - also of a range ending at the paragraph end the cut keeps before a table: both
  documents' bytes as those give them. }
procedure TTyRichDropAcrossTest.TestAMoveIsACutAndAPaste;
var
  rtf: RawByteString;
  c, t: TAcrossProbe;
  p: TPoint;
  i: Integer;
  sh: TShiftState;
  what: string;
begin
  rtf := Head + '\pard\f0 abc\par' + #13#10 +
    '\trowd\trgaph108\cellx2400\cellx4800' + #13#10 + '\pard\intbl x\cell y\cell\row' + #13#10 +
    '\pard end\par' + #13#10 + '}';
  for i := 0 to 1 do
  begin
    if i = 0 then sh := [] else sh := [ssCtrl];
    if i = 0 then what := 'a move' else what := 'a copy';
    LoadRtf(FA, rtf);
    Load(FB, 'alpha beta');
    FA.SelStart := 0;
    FA.SelLength := 4;
    PaintAll(FA);
    p := InB(Pt(FB, 6));
    StartDrag(Mid(FA, 1), p, sh);
    FA.ReleaseWith(p.X, p.Y, sh);
    c := NewProbe;
    t := NewProbe;
    try
      LoadRtf(c, rtf);
      Load(t, 'alpha beta');
      c.SelStart := 0;
      c.SelLength := 4;
      if i = 0 then c.CutToClipboard else c.CopyToClipboard;
      t.ClipRtf := c.ClipRtf;
      t.ClipText := c.ClipText;
      t.SelStart := 6;
      t.SelLength := 0;
      t.PasteFromClipboard;
      AssertEquals(what + ': the target as a paste leaves it', SaveRtf(t), SaveRtf(FB));
      AssertEquals(what + ': the source as the cut leaves it', SaveRtf(c), SaveRtf(FA));
    finally
      t.Free;
      c.Free;
    end;
  end;
end;

{ The target's own edge scrolling brings places under the pointer that take the content and
  places that take nothing (a row holding a nested table): after every tick the cursor here
  says the target's verdict there. }
procedure TTyRichDropAcrossTest.TestTheTargetsTickChangesTheCursorHere;
var
  s: string;
  i: Integer;
  p: TPoint;
  y0: Int64;
  seenMove, seenNone: Boolean;
  f: TFileStream;
  b: RawByteString;
begin
  Load(FA, 'one two three');
  f := TFileStream.Create(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim +
    'fixtures' + PathDelim + 'rtf' + PathDelim + 'word-table-merged.rtf', fmOpenRead or
    fmShareDenyWrite);
  try
    SetLength(b, f.Size);
    f.ReadBuffer(b[1], f.Size);
  finally
    f.Free;
  end;
  LoadRtf(FB, b);
  s := '';
  for i := 1 to 30 do s := s + 'line ' + IntToStr(i) + LineEnding;
  FB.SelStart := 0;
  FB.SelLength := 0;
  FB.SelText := s;
  FB.Document.ClearUndo;
  FB.UpdateView;
  PaintAll(FB);
  FA.SelStart := 4;
  FA.SelLength := 3;
  p := Point(FA.OtherAt.X + 40, FA.OtherAt.Y + FB.Height - 2);
  StartDrag(Mid(FA, 5), p);
  seenMove := False;
  seenNone := False;
  for i := 1 to 600 do
  begin
    if FB.Effect = rdeMove then seenMove := True;
    if FB.Effect = rdeNone then seenNone := True;
    AssertTrue(Format('tick %d: the cursor here says the verdict there', [i]),
      FA.CursorFor(p.X, p.Y) = CursorOf(FB.Effect));
    if seenMove and seenNone then Break;
    y0 := FB.ScrollY;
    FB.DragTick;
    PaintAll(FB);
    if FB.ScrollY = y0 then Break;
  end;
  AssertTrue('a place that takes it came', seenMove);
  AssertTrue('and one that takes nothing', seenNone);
  FA.Press(VK_ESCAPE, []);
end;

{ The drop's own filter around the reader's: when it cannot be made (memory), the reader's goes
  too - nothing alive -, the drop is refused with the memory's reason, the source keeps its
  content. Pictures the round trip changed match none of the source's: the source's pictures
  looked at stay a few for each, whatever their number (500 here). }
procedure TTyRichDropAcrossTest.TestTheDropsFilterLeaksNothingAndStaysLinear;
var
  offer: TTyRichSelectionOffer;
  p: TPoint;
  i, n: Integer;
  pic: TTyRichPicture;
  b: TBGRABitmap;
  st: TBytesStream;
  c0: Int64;
  got: TTyRichPicture;
begin
  Load(FA, 'one two three');
  Load(FB, 'alpha beta');
  FB.CountInner := True;
  FB.FailFilter := True;
  FB.Refused := 0;
  TCountedFilter.Live := 0;
  FA.SelStart := 4;
  FA.SelLength := 3;
  p := InB(Pt(FB, 6));
  StartDrag(Mid(FA, 5), p);
  FA.ReleaseWith(p.X, p.Y, []);
  AssertEquals('no filter left alive', 0, TCountedFilter.Live);
  AssertEquals('told once', 1, FB.Refused);
  AssertEquals('why', rsRichEditRefusedMemory, FB.LastReason);
  AssertEquals('the source as it was', 'one two three', TextOf(FA));
  AssertEquals('the target as it was', 'alpha beta', TextOf(FB));
  FB.FailFilter := False;
  FB.CountInner := False;
  // 500 pictures whose bytes the round trip changed
  Load(FA, 'x');
  n := 500;
  for i := 0 to n - 1 do
  begin
    b := TBGRABitmap.Create(1 + i mod 23, 1 + i div 23, BGRA(i mod 256, 40, 90, 255));
    st := TBytesStream.Create;
    try
      b.SaveToStreamAs(st, ifPng);
      pic := TTyRichPicture.Create(rpfPng, Copy(st.Bytes, 0, st.Size), 300, 300);
    finally
      st.Free;
      b.Free;
    end;
    AssertTrue('a picture', FA.Document.Execute(TTyRichInsertObject.Create(1 + i, pic)));
  end;
  FA.Document.ClearUndo;
  FA.UpdateView;
  Load(FB, 'alpha beta');
  FB.ChangePictures := True;
  c0 := TyRichDropPictureCompares;
  offer := TTyRichSelectionOffer.Create(FA, 0, FA.Document.Text.Length);
  try
    p := Pt(FB, 6);
    AssertTrue('a copy there', FB.DropEnter(offer, p.X, p.Y, [ssCtrl]) = rdeCopy);
    AssertTrue('copied', FB.DropOn(p.X, p.Y, [ssCtrl]) = rdeCopy);
  finally
    offer.Free;
  end;
  FB.ChangePictures := False;
  AssertTrue(Format('the source''s pictures looked at: a few for each (%d for %d)',
    [TyRichDropPictureCompares - c0, n]), TyRichDropPictureCompares - c0 <= 8 * n);
  got := nil;
  for i := 0 to FB.Document.Text.Length - 1 do
    if FB.Document.ObjectAt(i) is TTyRichPicture then
    begin
      got := TTyRichPicture(FB.Document.ObjectAt(i));
      Break;
    end;
  AssertTrue('the pictures went in', got <> nil);
  AssertTrue('with bytes of their own (none matched)',
    Pointer(got.Data) <> Pointer(TTyRichPicture(FA.Document.ObjectAt(1)).Data));
end;

{ A rich edit on a form that takes no input now is no target: another form is the modal one,
  or its form is disabled; on the modal form itself, or with no modal form, it is. }
procedure TTyRichDropAcrossTest.TestAFormThatTakesNoInputIsNoTarget;
var
  formA, formB: TForm;
  p: TPoint;
  i: Integer;
  what: string;
begin
  NeedWidgetSet;
  formA := TForm.CreateNew(nil);
  formB := TForm.CreateNew(nil);
  try
    FA.Parent := formA;
    FB.Parent := formB;
    for i := 0 to 3 do
    begin
      what := Format('case %d', [i]);
      Load(FA, 'one two three');
      Load(FB, 'alpha beta');
      FA.UseModal := True;
      FA.ModalForm := nil;
      formB.Enabled := True;
      case i of
        1: FA.ModalForm := formA;
        2: FA.ModalForm := formB;
        3: formB.Enabled := False;
      end;
      FA.SelStart := 4;
      FA.SelLength := 3;
      p := InB(Pt(FB, 6));
      StartDrag(Mid(FA, 5), p);
      if i in [0, 2] then
      begin
        AssertTrue(what + ': a target', FB.DropActive);
        AssertTrue(what + ': a move there', FA.CursorFor(p.X, p.Y) = crDrag);
      end
      else
      begin
        AssertFalse(what + ': no target', FB.DropActive);
        AssertTrue(what + ': not here', FA.CursorFor(p.X, p.Y) = crNoDrop);
      end;
      FA.Press(VK_ESCAPE, []);
    end;
  finally
    formB.Enabled := True;
    FA.Parent := nil;
    FB.Parent := nil;
    formB.Free;
    formA.Free;
  end;
end;

{$IFDEF LCLWin32}
{ ---- from other programs ---- }

function TTyRichDropAcrossTest.Enter(ARich: TAcrossProbe; AData: TTestData; const P: TPoint;
  AKeys: DWORD; AAllowed: DWORD): DWORD;
begin
  Result := AAllowed;
  AssertEquals('DragEnter answers', S_OK, ARich.Target.DragEnter(AData, AKeys, P, Result));
end;

function TTyRichDropAcrossTest.DropAt(ARich: TAcrossProbe; AData: TTestData; const P: TPoint;
  AKeys: DWORD; AAllowed: DWORD): DWORD;
begin
  Result := AAllowed;
  AssertEquals('Drop answers', S_OK, ARich.Target.Drop(AData, AKeys, P, Result));
end;

function TTyRichDropAcrossTest.TempFile(const AName: string; const ABytes: TBytes): string;
var
  f: TFileStream;
begin
  if FTemp = '' then
  begin
    FTemp := GetTempDir(False) + 'tyrichdrop' + IntToStr(GetProcessID) + '_' +
      IntToStr(Random(1000000));
    ForceDirectories(FTemp);
  end;
  Result := FTemp + PathDelim + AName;
  f := TFileStream.Create(Result, fmCreate);
  try
    if Length(ABytes) > 0 then f.WriteBuffer(ABytes[0], Length(ABytes));
  finally
    f.Free;
  end;
end;

{ Each flavour as a paste takes it, in the paste's order: RTF (with its formats), a picture
  (PNG, then a bitmap), text; all three offered: the RTF. The formats are asked when the drag
  comes in, the content read once, at the drop. One step; what went in selected; the control
  focused. A data object with nothing a paste takes: "nothing". }
procedure TTyRichDropAcrossTest.TestAnOleDropTakesWhatAPasteTakes;
var
  d: TTestData;
  di: IDataObject;
  p: TPoint;
  e: DWORD;
  m: TRect;
  i: Integer;
  what: string;
begin
  for i := 0 to 6 do
  begin
    Load(FA, 'one two three');
    FA.FocusCalls := 0;
    d := TTestData.Create;
    di := d;
    case i of
      0:
        begin
          d.Rtf := Head + '\pard\f0 \b NEW\b0}';
          d.HasRtf := True;
        end;
      1:
        begin
          d.Text := 'NEW';
          d.HasText := True;
        end;
      2: d.Png := PngOf(8, 6);
      3: d.Dib := DibOf;
      4:
        begin
          d.Rtf := Head + '\pard\f0 RTF}';
          d.HasRtf := True;
          d.Text := 'PLAIN';
          d.HasText := True;
          d.Png := PngOf(8, 6);
        end;
      5: d.Html := True;
      6:
        begin
          // both pictures: the PNG first, kept as it is
          d.Png := PngOf(8, 6);
          d.Dib := DibOf;
        end;
    end;
    what := Format('case %d', [i]);
    p := Pt(FA, 4);
    e := Enter(FA, d, p, MK_LBUTTON, DROPEFFECT_COPY);
    if i = 5 then
    begin
      AssertEquals(what + ': nothing a paste takes: nothing', DROPEFFECT_NONE, e);
      e := DropAt(FA, d, p, 0, DROPEFFECT_COPY);
      AssertEquals(what + ': dropped: nothing', DROPEFFECT_NONE, e);
      AssertEquals(what + ': the text', 'one two three', TextOf(FA));
      AssertEquals(what + ': no step', 0, FA.Document.UndoDepth);
      di := nil;
      Continue;
    end;
    AssertEquals(what + ': a copy', DROPEFFECT_COPY, e);
    AssertTrue(what + ': a mark', FA.Mark(m));
    AssertEquals(what + ': nothing read yet', 0, d.Gets);
    e := DROPEFFECT_COPY;
    AssertEquals(what + ': DragOver answers', S_OK, FA.Target.DragOver(MK_LBUTTON, Pt(FA, 8), e));
    AssertEquals(what + ': over: a copy', DROPEFFECT_COPY, e);
    e := DropAt(FA, d, p, 0, DROPEFFECT_COPY);
    AssertEquals(what + ': dropped: a copy', DROPEFFECT_COPY, e);
    AssertFalse(what + ': the session ended', FA.DropActive);
    AssertEquals(what + ': one step', 1, FA.Document.UndoDepth);
    AssertEquals(what + ': named Copy', rsRichUndoCopy, FA.Document.UndoDescription);
    AssertEquals(what + ': what went in selected', Int64(4), FA.SelStart);
    AssertEquals(what + ': focused', 1, FA.FocusCalls);
    case i of
      0:
        begin
          AssertEquals(what + ': the RTF''s text', 'one NEWtwo three', TextOf(FA));
          AssertTrue(what + ': its format', FA.Document.TypingFormatAt(5) <>
            FA.Document.TypingFormatAt(1));
          AssertEquals(what + ': read once', 1, d.RtfGets);
        end;
      1: AssertEquals(what + ': the text', 'one NEWtwo three', TextOf(FA));
      2, 3:
        begin
          AssertTrue(what + ': a picture', FA.Document.ObjectAt(4) is TTyRichPicture);
          AssertEquals(what + ': stored as PNG', Ord(rpfPng),
            Ord(TTyRichPicture(FA.Document.ObjectAt(4)).PictureFormat));
        end;
      6:
        begin
          AssertTrue(what + ': a picture', FA.Document.ObjectAt(4) is TTyRichPicture);
          AssertTrue(what + ': the PNG''s own bytes', StrOfBytes(TTyRichPicture(
            FA.Document.ObjectAt(4)).Data) = StrOfBytes(d.Png));
        end;
      4:
        begin
          AssertEquals(what + ': the RTF first', 'one RTFtwo three', TextOf(FA));
          AssertEquals(what + ': only the RTF read', 1, d.Gets);
        end;
    end;
    FA.Undo;
    AssertEquals(what + ': undo', 'one two three', TextOf(FA));
    di := nil;
  end;
  AssertEquals('every data object let go', 0, TTestData.Alive);
  CheckNoClipboard(FA, 'drops');
end;

{ The effect follows the system's convention, and is what was done: Ctrl a copy; otherwise a
  move when the source allows it (the step named Move), else a copy; a file list is never a
  move. }
procedure TTyRichDropAcrossTest.TestTheEffectIsWhatHappened;
const
  Allow: array[0..4] of DWORD = (DROPEFFECT_COPY or DROPEFFECT_MOVE, DROPEFFECT_COPY or
    DROPEFFECT_MOVE, DROPEFFECT_MOVE, DROPEFFECT_MOVE, DROPEFFECT_COPY);
  Keys: array[0..4] of DWORD = (0, MK_CONTROL, MK_CONTROL, 0, MK_CONTROL);
  Want: array[0..4] of DWORD = (DROPEFFECT_MOVE, DROPEFFECT_COPY, DROPEFFECT_MOVE,
    DROPEFFECT_MOVE, DROPEFFECT_COPY);
var
  d: TTestData;
  di: IDataObject;
  i: Integer;
  e: DWORD;
  p: TPoint;
  what: string;
begin
  for i := 0 to High(Allow) do
  begin
    Load(FA, 'one two three');
    d := TTestData.Create;
    di := d;
    d.Text := 'NEW';
    d.HasText := True;
    what := Format('case %d', [i]);
    p := Pt(FA, 4);
    e := Enter(FA, d, p, MK_LBUTTON or Keys[i], Allow[i]);
    AssertEquals(what + ': the verdict', Want[i], e);
    e := DropAt(FA, d, p, Keys[i], Allow[i]);
    AssertEquals(what + ': what was done', Want[i], e);
    if Want[i] = DROPEFFECT_MOVE then
      AssertEquals(what + ': named Move', rsRichUndoMove, FA.Document.UndoDescription)
    else
      AssertEquals(what + ': named Copy', rsRichUndoCopy, FA.Document.UndoDescription);
    di := nil;
  end;
end;

{ What is refused reports "nothing" (the source keeps its data), told once with the paste's
  reason: read-only, disabled, AcceptDrops off (no session at all); a picture alone
  into a plain text document; a document that takes no edit; an insert that fails. Nothing is
  read for a drop that is not taken; every data object is let go. }
procedure TTyRichDropAcrossTest.TestARefusedOleDropReportsNothing;
var
  d: TTestData;
  di: IDataObject;
  i: Integer;
  e: DWORD;
  p: TPoint;
  what: string;
begin
  for i := 0 to 5 do
  begin
    Load(FA, 'one two three');
    FA.Refused := 0;
    d := TTestData.Create;
    di := d;
    d.Rtf := Head + '\pard\f0 NEW}';
    d.HasRtf := i <> 3;
    if i = 3 then d.Png := PngOf(4, 4);
    case i of
      0: FA.ReadOnly := True;
      1: FA.Enabled := False;
      2: FA.AcceptDrops := False;
      3: FA.PlainText := True;
      4: TDragLoadState.Put(FA.Document, True);
      5: FA.FailRead := True;
    end;
    what := Format('case %d', [i]);
    p := Pt(FA, 4);
    e := Enter(FA, d, p, MK_LBUTTON, DROPEFFECT_COPY or DROPEFFECT_MOVE);
    if i < 5 then AssertEquals(what + ': not here', DROPEFFECT_NONE, e);
    if i < 3 then AssertFalse(what + ': no session', FA.DropActive);
    e := DropAt(FA, d, p, 0, DROPEFFECT_COPY or DROPEFFECT_MOVE);
    AssertEquals(what + ': nothing done', DROPEFFECT_NONE, e);
    AssertEquals(what + ': the text', 'one two three', TextOf(FA));
    AssertEquals(what + ': no step', 0, FA.Document.UndoDepth);
    AssertFalse(what + ': no session left', FA.DropActive);
    case i of
      0, 1, 2:
        begin
          AssertEquals(what + ': nothing told', 0, FA.Refused);
          AssertEquals(what + ': nothing read', 0, d.Gets);
        end;
      3:
        begin
          AssertEquals(what + ': told once', 1, FA.Refused);
          AssertEquals(what + ': why', rsRichEditRefusedPlainPaste, FA.LastReason);
        end;
      4:
        begin
          AssertEquals(what + ': told once', 1, FA.Refused);
          AssertEquals(what + ': why', rsRichEditRefusedIncomplete, FA.LastReason);
        end;
      5:
        begin
          AssertEquals(what + ': told once', 1, FA.Refused);
          AssertEquals(what + ': why', rsRichEditRefusedMemory, FA.LastReason);
        end;
    end;
    FA.ReadOnly := False;
    FA.Enabled := True;
    FA.AcceptDrops := True;
    FA.PlainText := False;
    FA.FailRead := False;
    TDragLoadState.Put(FA.Document, False);
    di := nil;
  end;
  AssertEquals('every data object let go', 0, TTestData.Alive);
end;

{ A list of files: OnDropFiles first, with the names in order (AHandled: taken, a copy,
  nothing inserted - also in a read-only control); else pictures, each as
  InsertPictureFromFile takes it, in the order given, one step, selected - a copy also where
  a move is allowed; a list with anything else, not taken and nothing told; a picture's name
  whose file is no picture: told once, nothing in; a file list that comes with RTF: the RTF. }
procedure TTyRichDropAcrossTest.TestDroppedFiles;
var
  d: TTestData;
  di: IDataObject;
  a, b, txt, bad: string;
  pa, pb: TBytes;
  e: DWORD;
  p: TPoint;
  got: TTyRichPicture;

  function Files(const ANames: array of string): TTestData;
  var
    i: Integer;
  begin
    Result := TTestData.Create;
    SetLength(Result.FileNames, Length(ANames));
    for i := 0 to High(ANames) do Result.FileNames[i] := UTF8Decode(ANames[i]);
  end;

begin
  pa := PngOf(10, 8);
  pb := PngOf(6, 4);
  a := TempFile('a.png', pa);
  b := TempFile('b.png', pb);
  txt := TempFile('c.txt', RawBytes('some text'));
  bad := TempFile('bad.png', RawBytes('this is no picture'));
  Load(FA, 'one two three');
  p := Pt(FA, 4);
  // pictures: both, in order, one step, a copy where a move is allowed too
  d := Files([a, b]);
  di := d;
  e := Enter(FA, d, p, MK_LBUTTON, DROPEFFECT_COPY or DROPEFFECT_MOVE);
  AssertEquals('pictures: a copy', DROPEFFECT_COPY, e);
  e := DropAt(FA, d, p, 0, DROPEFFECT_COPY or DROPEFFECT_MOVE);
  AssertEquals('pictures: copied', DROPEFFECT_COPY, e);
  got := TTyRichPicture(FA.Document.ObjectAt(4));
  AssertTrue('the first file first', (got <> nil) and (Length(got.Data) = Length(pa)) and
    CompareMem(@got.Data[0], @pa[0], Length(pa)));
  got := TTyRichPicture(FA.Document.ObjectAt(5));
  AssertTrue('the second after it', (got <> nil) and (Length(got.Data) = Length(pb)) and
    CompareMem(@got.Data[0], @pb[0], Length(pb)));
  AssertEquals('one step', 1, FA.Document.UndoDepth);
  AssertEquals('named as an inserted picture', rsRichUndoInsertPicture,
    FA.Document.UndoDescription);
  AssertEquals('both selected', Int64(4), FA.SelStart);
  AssertEquals('both selected: the length', Int64(2), FA.SelLength);
  AssertEquals('focused', 1, FA.FocusCalls);
  di := nil;
  FA.Undo;
  // anything else in the list: not taken, nothing told
  FA.Refused := 0;
  d := Files([a, txt]);
  di := d;
  AssertEquals('with a text file: not here', DROPEFFECT_NONE,
    Enter(FA, d, p, MK_LBUTTON, DROPEFFECT_COPY));
  AssertEquals('with a text file: nothing', DROPEFFECT_NONE, DropAt(FA, d, p, 0, DROPEFFECT_COPY));
  AssertEquals('with a text file: the text', 'one two three', TextOf(FA));
  AssertEquals('with a text file: nothing told', 0, FA.Refused);
  di := nil;
  // a picture's name, no picture: told once, nothing in
  d := Files([a, bad]);
  di := d;
  AssertEquals('a false picture: a copy by its name', DROPEFFECT_COPY,
    Enter(FA, d, p, MK_LBUTTON, DROPEFFECT_COPY));
  AssertEquals('a false picture: nothing done', DROPEFFECT_NONE,
    DropAt(FA, d, p, 0, DROPEFFECT_COPY));
  AssertEquals('a false picture: nothing in', 'one two three', TextOf(FA));
  AssertEquals('a false picture: no step', 0, FA.Document.UndoDepth);
  AssertEquals('a false picture: told once', 1, FA.Refused);
  AssertEquals('a false picture: why', rsRichEditRefusedNoPicture, FA.LastReason);
  di := nil;
  // the application's: the names in order, handled - nothing inserted
  FA.OnDropFiles := @DroppedFiles;
  FHandle := 1;
  d := Files([txt, a]);
  di := d;
  AssertEquals('the application''s: a copy', DROPEFFECT_COPY,
    Enter(FA, d, p, MK_LBUTTON, DROPEFFECT_COPY or DROPEFFECT_MOVE));
  AssertEquals('the application''s: not asked before the drop', 0, FEvents);
  AssertEquals('the application''s: taken', DROPEFFECT_COPY,
    DropAt(FA, d, p, 0, DROPEFFECT_COPY or DROPEFFECT_MOVE));
  AssertEquals('asked once', 1, FEvents);
  AssertEquals('the names', 2, Length(FNames));
  AssertEquals('the first name', txt, FNames[0]);
  AssertEquals('the second name', a, FNames[1]);
  AssertEquals('handled: nothing inserted', 'one two three', TextOf(FA));
  di := nil;
  // not handled: the pictures after it
  FHandle := 0;
  FEvents := 0;
  d := Files([b]);
  di := d;
  Enter(FA, d, p, MK_LBUTTON, DROPEFFECT_COPY);
  AssertEquals('not handled: the picture', DROPEFFECT_COPY, DropAt(FA, d, p, 0, DROPEFFECT_COPY));
  AssertEquals('not handled: asked first', 1, FEvents);
  AssertTrue('not handled: the picture went in', FA.Document.ObjectAt(4) <> nil);
  di := nil;
  FA.Undo;
  // read-only: the application's still, the control's not
  FA.ReadOnly := True;
  FHandle := 1;
  FEvents := 0;
  d := Files([a]);
  di := d;
  AssertEquals('read-only, the application''s: a copy', DROPEFFECT_COPY,
    Enter(FA, d, p, MK_LBUTTON, DROPEFFECT_COPY));
  AssertEquals('read-only, the application''s: taken', DROPEFFECT_COPY,
    DropAt(FA, d, p, 0, DROPEFFECT_COPY));
  AssertEquals('read-only, the application''s: asked', 1, FEvents);
  di := nil;
  FA.OnDropFiles := nil;
  d := Files([a]);
  di := d;
  AssertEquals('read-only alone: not here', DROPEFFECT_NONE,
    Enter(FA, d, p, MK_LBUTTON, DROPEFFECT_COPY));
  AssertEquals('read-only alone: nothing', DROPEFFECT_NONE, DropAt(FA, d, p, 0, DROPEFFECT_COPY));
  di := nil;
  FA.ReadOnly := False;
  // a plain text document: pictures are not here, told at the drop
  FA.PlainText := True;
  FA.Refused := 0;
  d := Files([a]);
  di := d;
  AssertEquals('plain text: not here', DROPEFFECT_NONE, Enter(FA, d, p, MK_LBUTTON, DROPEFFECT_COPY));
  AssertEquals('plain text: nothing', DROPEFFECT_NONE, DropAt(FA, d, p, 0, DROPEFFECT_COPY));
  AssertEquals('plain text: told once', 1, FA.Refused);
  AssertEquals('plain text: why', rsRichEditRefusedPlainPicture, FA.LastReason);
  di := nil;
  FA.PlainText := False;
  // files with RTF: the RTF (no event)
  FA.OnDropFiles := @DroppedFiles;
  FEvents := 0;
  d := Files([a]);
  di := d;
  d.Rtf := Head + '\pard\f0 NEW}';
  d.HasRtf := True;
  Enter(FA, d, p, MK_LBUTTON, DROPEFFECT_COPY);
  AssertEquals('with RTF: a copy', DROPEFFECT_COPY, DropAt(FA, d, p, 0, DROPEFFECT_COPY));
  AssertEquals('with RTF: the RTF', 'one NEWtwo three', TextOf(FA));
  AssertEquals('with RTF: no event', 0, FEvents);
  di := nil;
  AssertEquals('every data object let go', 0, TTestData.Alive);
end;

{ The window is registered when its handle is made, revoked before it goes, registered again
  with a new one; AcceptDrops False revokes it and True registers it again; nothing in the
  designer; a refused registration is not revoked; the control's end revokes it, and its
  target answers nothing after. The system's calls are this unit's stand-ins. }
procedure TTyRichDropAcrossTest.TestRegistrationFollowsTheWindow;
var
  form: TForm;
  w: HWND;
  t: IDropTarget;
  e: DWORD;
  d: TTestData;
  di: IDataObject;
begin
  AssertTrue('the stand-ins are in place', Pointer(TyRichOleRegisterDragDrop) = Pointer(@FakeRegister));
  AssertTrue('the stand-ins are in place: revoke', Pointer(TyRichOleRevokeDragDrop) = Pointer(@FakeRevoke));
  NeedWidgetSet;
  form := TForm.CreateNew(nil);
  try
    FA.Parent := form;
    AssertEquals('no window: nothing registered', 0, TOleCalls.Registers);
    form.HandleNeeded;
    FA.HandleNeeded;
    w := FA.Handle;
    AssertEquals('the window made: registered', 1, TOleCalls.Registers);
    AssertTrue('its window', TOleCalls.LastRegistered = w);
    AssertTrue('with the control''s target', TOleCalls.LastTarget = FA.Target);
    FA.AcceptDrops := False;
    AssertEquals('AcceptDrops off: revoked', 1, TOleCalls.Revokes);
    AssertTrue('revoked: its window', TOleCalls.LastRevoked = w);
    FA.AcceptDrops := False;
    AssertEquals('off again: nothing more', 1, TOleCalls.Revokes);
    FA.AcceptDrops := True;
    AssertEquals('on: registered again', 2, TOleCalls.Registers);
    FA.DropHandle;
    AssertEquals('the window gone: revoked', 2, TOleCalls.Revokes);
    AssertTrue('the window gone: its window', TOleCalls.LastRevoked = w);
    FA.HandleNeeded;
    AssertEquals('a new window: registered', 3, TOleCalls.Registers);
    AssertTrue('the new window', TOleCalls.LastRegistered = FA.Handle);
    AssertTrue('the same target', TOleCalls.LastTarget = FA.Target);
    // refused (OLE not initialised): nothing to revoke
    FA.DropHandle;
    TOleCalls.Refuse := True;
    FA.HandleNeeded;
    AssertEquals('refused: asked', 4, TOleCalls.Registers);
    FA.DropHandle;
    AssertEquals('refused: nothing revoked', 3, TOleCalls.Revokes);
    TOleCalls.Refuse := False;
    // the designer: nothing
    FB.Designing;
    FB.Parent := form;
    FB.HandleNeeded;
    AssertEquals('in the designer: nothing registered', 4, TOleCalls.Registers);
    FB.Parent := nil;
    // the control's end: revoked, its target answers nothing
    FA.HandleNeeded;
    AssertEquals('registered once more', 5, TOleCalls.Registers);
    t := FA.Target;
    FreeAndNil(FA);
    AssertEquals('the control gone: revoked', 4, TOleCalls.Revokes);
    d := TTestData.Create;
    di := d;
    d.Text := 'x';
    d.HasText := True;
    e := DROPEFFECT_COPY;
    AssertEquals('after the control: DragEnter', S_OK, t.DragEnter(di, MK_LBUTTON, Point(5, 5), e));
    AssertEquals('after the control: nothing', DROPEFFECT_NONE, e);
    e := DROPEFFECT_COPY;
    t.Drop(di, 0, Point(5, 5), e);
    AssertEquals('after the control: no drop', DROPEFFECT_NONE, e);
    di := nil;
    t := nil;
    TOleCalls.LastTarget := nil;
  finally
    FreeAndNil(FA);
    form.Free;
  end;
  AssertEquals('every data object let go', 0, TTestData.Alive);
end;

{ The control freed during a drag over it: what OLE calls after does nothing ("nothing", no
  failure) and the data object is let go. Its content replaced: the session ends, the next
  move begins one over the new content. A failure inside: "nothing", no session left. }
procedure TTyRichDropAcrossTest.TestTheControlGoesDuringAnOleDrag;
var
  t: IDropTarget;
  d: TTestData;
  di: IDataObject;
  e: DWORD;
  p: TPoint;
  m: TRect;
begin
  Load(FA, 'one two three');
  d := TTestData.Create;
  di := d;
  d.Text := 'NEW';
  d.HasText := True;
  p := Pt(FA, 4);
  AssertEquals('a copy', DROPEFFECT_COPY, Enter(FA, d, p, MK_LBUTTON, DROPEFFECT_COPY));
  // the content replaced
  FA.Lines.Text := 'other words';
  FA.UpdateView;
  PaintAll(FA);
  AssertFalse('replaced: the session ended', FA.DropActive);
  AssertFalse('replaced: no mark', FA.Mark(m));
  e := DROPEFFECT_COPY;
  FA.Target.DragOver(MK_LBUTTON, Pt(FA, 6), e);
  AssertTrue('the next move: a session again', FA.DropActive);
  AssertEquals('over the new content: a copy', DROPEFFECT_COPY, e);
  AssertEquals('dropped', DROPEFFECT_COPY, DropAt(FA, d, Pt(FA, 6), 0, DROPEFFECT_COPY));
  AssertEquals('into the new content', 'other NEWwords', TextOf(FA));
  // a failure inside: nothing, no session left
  FA.RaiseInVerdict := True;
  e := DROPEFFECT_COPY;
  AssertTrue('a failure: not S_OK', FA.Target.DragEnter(di, MK_LBUTTON, p, e) <> S_OK);
  AssertEquals('a failure: nothing', DROPEFFECT_NONE, e);
  AssertFalse('a failure: no session left', FA.DropActive);
  FA.RaiseInVerdict := False;
  // the control freed during the drag
  t := FA.Target;
  AssertEquals('again a copy', DROPEFFECT_COPY, Enter(FA, d, p, MK_LBUTTON, DROPEFFECT_COPY));
  FreeAndNil(FA);
  e := DROPEFFECT_COPY;
  AssertEquals('gone: DragOver answers', S_OK, t.DragOver(MK_LBUTTON, p, e));
  AssertEquals('gone: nothing', DROPEFFECT_NONE, e);
  e := DROPEFFECT_COPY;
  AssertEquals('gone: Drop answers', S_OK, t.Drop(di, 0, p, e));
  AssertEquals('gone: no drop', DROPEFFECT_NONE, e);
  AssertEquals('gone: DragLeave answers', S_OK, t.DragLeave);
  t := nil;
  di := nil;
  AssertEquals('the data object let go', 0, TTestData.Alive);
end;

{ The keys of an OLE key state, the effects both ways; an RTF given as a stream goes in as one
  given as a block; DragLeave takes the mark away and reads nothing. }
procedure TTyRichDropAcrossTest.TestTheOleKeysAndAStreamedMedium;
var
  d: TTestData;
  di: IDataObject;
  p: TPoint;
  m: TRect;
begin
  AssertTrue('Ctrl', TyRichOleShift(MK_CONTROL) = [ssCtrl]);
  AssertTrue('Shift and the left button', TyRichOleShift(MK_SHIFT or MK_LBUTTON) = [ssShift, ssLeft]);
  AssertTrue('Alt', TyRichOleShift($20) = [ssAlt]);
  AssertTrue('the right and middle buttons', TyRichOleShift(MK_RBUTTON or MK_MBUTTON) =
    [ssRight, ssMiddle]);
  AssertEquals('a move', DROPEFFECT_MOVE, TyRichOleEffect(rdeMove));
  AssertEquals('a copy', DROPEFFECT_COPY, TyRichOleEffect(rdeCopy));
  AssertEquals('nothing', DROPEFFECT_NONE, TyRichOleEffect(rdeNone));
  AssertTrue('allowed both', TyRichOleEffects(DROPEFFECT_MOVE or DROPEFFECT_COPY or 4) =
    [rdeMove, rdeCopy]);
  AssertTrue('a link alone allows nothing here', TyRichOleEffects(4) = []);
  Load(FA, 'one two three');
  d := TTestData.Create;
  di := d;
  d.Rtf := Head + '\pard\f0 NEW}';
  d.HasRtf := True;
  d.Streamed := True;
  p := Pt(FA, 4);
  Enter(FA, d, p, MK_LBUTTON, DROPEFFECT_COPY);
  AssertTrue('a mark', FA.Mark(m));
  AssertEquals('DragLeave answers', S_OK, FA.Target.DragLeave);
  AssertFalse('left: no mark', FA.Mark(m));
  AssertFalse('left: no session', FA.DropActive);
  AssertEquals('left: nothing read', 0, d.Gets);
  Enter(FA, d, p, MK_LBUTTON, DROPEFFECT_COPY);
  AssertEquals('a stream: a copy', DROPEFFECT_COPY, DropAt(FA, d, p, 0, DROPEFFECT_COPY));
  AssertEquals('a stream: its text', 'one NEWtwo three', TextOf(FA));
  di := nil;
  AssertEquals('the data object let go', 0, TTestData.Alive);
end;

{ Picture files dropped at the end of a document, into an empty one, in a paragraph's middle,
  in a table's cell, before a table: all go in, in the order given, one step, all selected,
  each sized as InsertPictureFromFile at that place sizes it. }
procedure TTyRichDropAcrossTest.TestEveryPictureFileIsSizedForTheDropPlace;
var
  files: array[0..2] of string;
  table: RawByteString;
  i: Integer;

  procedure Check(const AWhat: string; ARtf: Boolean; const AContent: RawByteString;
    APlace: TTyRichPos; ACount: Integer);
  var
    c: TAcrossProbe;
    d: TTestData;
    di: IDataObject;
    j: Integer;
    got, want: TTyRichPicture;
    e: DWORD;
    p: TPoint;
    bytes: TBytes;
    f: TFileStream;
  begin
    if ARtf then LoadRtf(FA, AContent) else Load(FA, AContent);
    d := TTestData.Create;
    di := d;
    SetLength(d.FileNames, ACount);
    for j := 0 to ACount - 1 do d.FileNames[j] := UTF8Decode(files[j]);
    p := Pt(FA, APlace);
    AssertEquals(AWhat + ': the place under the point', APlace, FA.PositionAtPoint(p.X, p.Y));
    e := Enter(FA, d, p, MK_LBUTTON, DROPEFFECT_COPY);
    AssertEquals(AWhat + ': a copy', DROPEFFECT_COPY, e);
    e := DropAt(FA, d, p, 0, DROPEFFECT_COPY);
    AssertEquals(AWhat + ': dropped', DROPEFFECT_COPY, e);
    di := nil;
    AssertEquals(AWhat + ': one step', 1, FA.Document.UndoDepth);
    AssertEquals(AWhat + ': all selected, from the place', Int64(APlace), FA.SelStart);
    AssertEquals(AWhat + ': all selected', Int64(ACount), FA.SelLength);
    c := NewProbe;
    try
      if ARtf then LoadRtf(c, AContent) else Load(c, AContent);
      for j := 0 to ACount - 1 do
      begin
        c.SelStart := APlace + j;
        c.SelLength := 0;
        AssertTrue(AWhat + ': the yardstick''s insert', c.InsertPictureFromFile(files[j]));
      end;
      for j := 0 to ACount - 1 do
      begin
        got := TTyRichPicture(FA.Document.ObjectAt(APlace + j));
        want := TTyRichPicture(c.Document.ObjectAt(APlace + j));
        AssertTrue(Format('%s: picture %d there', [AWhat, j]), (got <> nil) and (want <> nil));
        f := TFileStream.Create(files[j], fmOpenRead or fmShareDenyWrite);
        try
          SetLength(bytes, f.Size);
          f.ReadBuffer(bytes[0], f.Size);
        finally
          f.Free;
        end;
        AssertTrue(Format('%s: picture %d is file %d', [AWhat, j, j]),
          StrOfBytes(got.Data) = StrOfBytes(bytes));
        AssertEquals(Format('%s: picture %d''s width', [AWhat, j]), want.WidthTwips, got.WidthTwips);
        AssertEquals(Format('%s: picture %d''s height', [AWhat, j]), want.HeightTwips,
          got.HeightTwips);
      end;
    finally
      c.Free;
    end;
  end;

begin
  files[0] := TempFile('w1.png', PngOf(1500, 20));
  files[1] := TempFile('w2.png', PngOf(1400, 30));
  files[2] := TempFile('w3.png', PngOf(12, 9));
  table := Head + '\pard\f0 abc\par' + #13#10 + '\trowd\cellx1200\cellx2400' + #13#10 +
    '\pard\intbl x\cell y\cell\row' + #13#10 + '\pard end\par' + #13#10 + '}';
  for i := 2 to 3 do
    Check(Format('%d at the end', [i]), False, 'one two three', 13, i);
  Check('2 into an empty control', False, '', 0, 2);
  Check('3 in a paragraph''s middle', False, 'one two three', 4, 3);
  LoadRtf(FA, table);
  Check('2 in a cell', True, table, FA.Document.Text.ParaStart(1) + 1, 2);
  Check('2 before a table', True, table, 3, 2);
end;

{ The control freed by its own handler during another program's drop - OnChange (text, RTF,
  files), OnSelectionChange, OnEditRefused, one the focus change runs: the target's Drop answers
  S_OK and "nothing" (the content is gone with the control), nothing of it is touched (freed
  memory poisoned). OnDropFiles freeing it: "nothing" unless it set AHandled. }
procedure TTyRichDropAcrossTest.TestAControlFreedDuringAnOleDropStopsThere;
var
  i: Integer;
  t: IDropTarget;
  d: TTestData;
  di: IDataObject;
  e: DWORD;
  r: HRESULT;
  p: TPoint;
  png: string;
  what: string;
begin
  png := TempFile('f.png', PngOf(10, 8));
  for i := 0 to 7 do
  begin
    what := Format('case %d', [i]);
    if FA = nil then
    begin
      FA := NewProbe;
      FA.Other := FB;
      FA.OtherAt := Point(500, 0);
    end;
    Load(FA, 'one two three');
    d := TTestData.Create;
    di := d;
    case i of
      0, 3, 5:
        begin
          d.Text := 'NEW';
          d.HasText := True;
        end;
      1, 4:
        begin
          d.Rtf := Head + '\pard\f0 NEW}';
          d.HasRtf := True;
        end;
      2, 6, 7:
        begin
          SetLength(d.FileNames, 1);
          d.FileNames[0] := UTF8Decode(png);
        end;
    end;
    case i of
      0, 1, 2: FA.OnChange := @DoomOnNotify;
      3: FA.OnSelectionChange := @DoomOnNotify;
      4:
        begin
          FA.FailRead := True;
          FA.OnEditRefused := @DoomOnRefused;
        end;
      5: FA.OnFocusAfter := @DoomOnNotify;
      6, 7:
        begin
          FA.OnDropFiles := @DoomOnFiles;
          FHandle := Ord(i = 7);
        end;
    end;
    p := Pt(FA, 4);
    t := FA.Target;
    AssertEquals(what + ': a copy', DROPEFFECT_COPY, Enter(FA, d, p, MK_LBUTTON, DROPEFFECT_COPY));
    FDoomed := FA;
    PoisonFreedMemory(True);
    try
      e := DROPEFFECT_COPY;
      r := t.Drop(di, 0, p, e);
    finally
      PoisonFreedMemory(False);
    end;
    AssertTrue(what + ': freed by its handler', FA = nil);
    AssertEquals(what + ': Drop answers', S_OK, r);
    if i = 7 then AssertEquals(what + ': handled: a copy', DROPEFFECT_COPY, e)
    else AssertEquals(what + ': nothing', DROPEFFECT_NONE, e);
    e := DROPEFFECT_COPY;
    AssertEquals(what + ': afterwards DragOver answers', S_OK, t.DragOver(MK_LBUTTON, p, e));
    AssertEquals(what + ': afterwards nothing', DROPEFFECT_NONE, e);
    t := nil;
    di := nil;
  end;
  FHandle := 0;
  AssertEquals('every data object let go', 0, TTestData.Alive);
end;

{ What a data object may give: a file list with no name, or a DROPFILES block shorter than its
  header ("nothing usable", no failure); GetData failing where QueryGetData said yes (nothing,
  nothing told); bytes after the RTF's terminating zero (ignored); a stream read in short
  pieces, one handed over at its end, one that tells no size (read whole, from its start); ANSI
  text alone, in the system's code page or the one its locale says; a BITMAPV5 DIB alone. }
procedure TTyRichDropAcrossTest.TestWhatADataObjectMayGive;
var
  d: TTestData;
  di: IDataObject;
  e: DWORD;
  i, j: Integer;
  p: TPoint;
  what: string;
  zhong: string;
begin
  zhong := UTF8Encode(UnicodeString(WideChar($4E2D)));
  for i := 0 to 9 do
  begin
    what := Format('case %d', [i]);
    Load(FA, 'one two three');
    FA.Refused := 0;
    d := TTestData.Create;
    di := d;
    case i of
      0: d.HasFiles := True;
      1: d.RawDrop := #8#0#0#0#0#0#0#0;
      2:
        begin
          d.Rtf := Head + '\pard\f0 NEW}';
          d.HasRtf := True;
          d.Text := 'NEW';
          d.HasText := True;
          d.FailGet := True;
        end;
      3:
        begin
          d.Rtf := Head + '\pard\f0 NEW}' + #0 + 'garbage after the end{\rtf1 X}';
          d.HasRtf := True;
        end;
      4, 5, 6:
        begin
          d.Rtf := Head + '\pard\f0 NEW}';
          d.HasRtf := True;
          d.Streamed := True;
          case i of
            4: d.StreamChunk := 3;
            5: d.StreamAtEnd := True;
            6:
              begin
                d.StreamNoStat := True;
                // longer than one read, size untold
                d.Rtf := Head + '\pard\f0 NEW';
                for j := 1 to 20000 do d.Rtf := d.Rtf + '{}';
                d.Rtf := d.Rtf + '}';
              end;
          end;
        end;
      7:
        begin
          d.Ansi := 'NEW';
          d.HasAnsi := True;
        end;
      8:
        begin
          d.Ansi := #$D6#$D0;
          d.HasAnsi := True;
          d.Locale := $0804;
        end;
      9:
        begin
          SetLength(d.DibV5, 124 + 16);
          FillChar(d.DibV5[0], Length(d.DibV5), 0);
          d.DibV5[0] := 124;
          d.DibV5[4] := 2;
          d.DibV5[8] := 2;
          d.DibV5[12] := 1;
          d.DibV5[14] := 24;
          for j := 124 to High(d.DibV5) do d.DibV5[j] := $40;
        end;
    end;
    p := Pt(FA, 4);
    e := DROPEFFECT_COPY;
    AssertEquals(what + ': DragEnter answers', S_OK, FA.Target.DragEnter(di, MK_LBUTTON, p, e));
    if i < 3 then
    begin
      if i < 2 then AssertEquals(what + ': nothing usable', DROPEFFECT_NONE, e);
      e := DROPEFFECT_COPY;
      AssertEquals(what + ': Drop answers', S_OK, FA.Target.Drop(di, 0, p, e));
      AssertEquals(what + ': nothing', DROPEFFECT_NONE, e);
      AssertEquals(what + ': the text', 'one two three', TextOf(FA));
      AssertEquals(what + ': nothing told', 0, FA.Refused);
    end
    else
    begin
      AssertEquals(what + ': a copy', DROPEFFECT_COPY, e);
      e := DROPEFFECT_COPY;
      AssertEquals(what + ': Drop answers', S_OK, FA.Target.Drop(di, 0, p, e));
      AssertEquals(what + ': taken', DROPEFFECT_COPY, e);
      case i of
        3, 4, 5, 6, 7: AssertEquals(what + ': the text', 'one NEWtwo three', TextOf(FA));
        8: AssertEquals(what + ': in its locale''s code page', 'one ' + zhong + 'two three',
             TextOf(FA));
        9: AssertTrue(what + ': a picture', FA.Document.ObjectAt(4) is TTyRichPicture);
      end;
    end;
    di := nil;
  end;
  AssertEquals('every data object let go', 0, TTestData.Alive);
end;

{ What the other program allows may change during its drag: each DragOver takes it, and the
  drop reports - and names its step - by what was allowed last. }
procedure TTyRichDropAcrossTest.TestDragOverFollowsTheAllowedEffects;
var
  d: TTestData;
  di: IDataObject;
  e: DWORD;
  p: TPoint;
begin
  Load(FA, 'one two three');
  d := TTestData.Create;
  di := d;
  d.Text := 'NEW';
  d.HasText := True;
  p := Pt(FA, 4);
  AssertEquals('move and copy allowed: a move', DROPEFFECT_MOVE,
    Enter(FA, d, p, MK_LBUTTON, DROPEFFECT_MOVE or DROPEFFECT_COPY));
  e := DROPEFFECT_COPY;
  FA.Target.DragOver(MK_LBUTTON, p, e);
  AssertEquals('then a copy only: a copy', DROPEFFECT_COPY, e);
  e := DROPEFFECT_MOVE or DROPEFFECT_COPY;
  FA.Target.DragOver(MK_LBUTTON, p, e);
  AssertEquals('then both again: a move', DROPEFFECT_MOVE, e);
  e := DROPEFFECT_COPY;
  FA.Target.DragOver(MK_LBUTTON, p, e);
  AssertEquals('dropped with a copy allowed: a copy', DROPEFFECT_COPY, DropAt(FA, d, p, 0,
    DROPEFFECT_COPY));
  AssertEquals('named Copy', rsRichUndoCopy, FA.Document.UndoDescription);
  di := nil;
end;

{ A list of 50 picture names: they are looked at once for the offer, not at each of 100 moves. }
procedure TTyRichDropAcrossTest.TestFileNamesAreLookedAtOncePerOffer;
var
  d: TTestData;
  di: IDataObject;
  e: DWORD;
  i, first: Integer;
  p: TPoint;
begin
  Load(FA, 'one two three');
  d := TTestData.Create;
  di := d;
  SetLength(d.FileNames, 50);
  for i := 0 to 49 do d.FileNames[i] := UnicodeString('C:\pictures\p' + IntToStr(i) + '.png');
  p := Pt(FA, 4);
  FA.NameChecks := 0;
  AssertEquals('a copy', DROPEFFECT_COPY, Enter(FA, d, p, MK_LBUTTON, DROPEFFECT_COPY));
  first := FA.NameChecks;
  AssertEquals('the names looked at once', 50, first);
  for i := 1 to 100 do
  begin
    e := DROPEFFECT_COPY;
    FA.Target.DragOver(MK_LBUTTON, Pt(FA, 1 + i mod 10), e);
    AssertEquals('over: a copy', DROPEFFECT_COPY, e);
  end;
  AssertEquals('100 moves look at them no more', first, FA.NameChecks);
  FA.Target.DragLeave;
  di := nil;
end;

var
  GReallocs: Integer;
  GCountOld: TMemoryManager;

function CountReAllocMem(var P: Pointer; Size: PtrUInt): Pointer;
begin
  Inc(GReallocs);
  Result := GCountOld.ReAllocMem(P, Size);
end;

{ A stream is read whole from its start - one handed over at its end too -, in short pieces as
  it gives them, and one that tells no size grows by doubling: a 4 MB stream read in 64 KB
  pieces costs a few reallocations, not one a piece. }
procedure TTyRichDropAcrossTest.TestAStreamIsReadWholeInFewSteps;
var
  ts: TTestStream;
  stm: IStream;
  got: RawByteString;
  data: RawByteString;
  i: Integer;
  mm: TMemoryManager;
begin
  SetLength(data, 4 * 1024 * 1024);
  for i := 1 to Length(data) do data[i] := Chr(i mod 251);
  // handed over at its end, its size told
  ts := TTestStream.Create;
  stm := ts;
  ts.Data := 'abcdefghij';
  ts.Position := 10;
  AssertTrue('read', TyRichOleReadStream(stm, got));
  AssertEquals('from its start', 'abcdefghij', got);
  // short pieces (S_FALSE)
  ts.Position := 0;
  ts.Chunk := 3;
  AssertTrue('read in pieces', TyRichOleReadStream(stm, got));
  AssertEquals('whole', 'abcdefghij', got);
  // no size told: grown by doubling
  ts.Chunk := 64 * 1024;
  ts.NoStat := True;
  ts.Data := data;
  ts.Position := 0;
  GetMemoryManager(GCountOld);
  mm := GCountOld;
  mm.ReAllocMem := @CountReAllocMem;
  GReallocs := 0;
  SetMemoryManager(mm);
  try
    AssertTrue('read with no size', TyRichOleReadStream(stm, got));
  finally
    SetMemoryManager(GCountOld);
  end;
  AssertTrue('whole', got = data);
  AssertTrue(Format('a few reallocations (%d), not one a piece (64)', [GReallocs]),
    GReallocs <= 12);
  stm := nil;
end;
{$ENDIF}

initialization
  RegisterTest(TTyRichDropAcrossTest);
  {$IFDEF LCLWin32}
  // no window of the test run is ever registered with the system
  TyRichOleRegisterDragDrop := @FakeRegister;
  TyRichOleRevokeDragDrop := @FakeRevoke;
  {$ENDIF}
end.
