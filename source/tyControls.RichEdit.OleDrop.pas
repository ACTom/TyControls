unit tyControls.RichEdit.OleDrop;
{$mode objfpc}{$H+}

{ Drops from other programs into TTyRichEdit on the Windows widgetset: the control's window is
  registered with OLE as a drop target (RegisterDragDrop), and what the system's drag brings
  over it is handed to the control's receiving side (TTyCustomRichEdit.DropEnter .. DropOn) as
  an offer - the data object read in the flavours a paste takes, in the paste's order: rich
  text (the "Rich Text Format" clipboard format), a picture (the "PNG" format, then CF_DIB,
  then CF_DIBV5), plain text (CF_UNICODETEXT, else CF_TEXT in the code page of its CF_LOCALE,
  or the system's ANSI code page when none comes with it); a list of files (CF_HDROP) when
  none of the first two comes with it. A data object is not the clipboard: nothing is made
  from another format by the system, so each of these is asked for by name. Nothing is read
  before the drop but what the formats are, and the file names.

  The whole unit is gated on the LCLWin32 define (the widgetset, not the system): under another
  widgetset - also on Windows, where a control's handle is then no window of the system's - it
  is an EMPTY unit, and tyControls.RichEdit names it only under the same define (the isolation
  pattern of tyControls.Win32WS).

  OLE: the LCL's Windows widgetset calls OleInitialize(nil) in TWin32WidgetSet.AppInit
  (Application.Initialize) and OleUninitialize in AppTerminate. A window made before that, or
  on a thread that never initialised OLE, cannot be registered (RegisterDragDrop answers
  CO_E_NOTINITIALIZED): the control then registers nothing and takes no drop from other
  programs - nothing is raised; it tries again when its window is made again, or when
  AcceptDrops is set off and on.

  The target object belongs to the control for its life (TTyCustomRichEdit.OleDropTarget); OLE
  holds a reference while the window is registered and while a drag is over it. When the
  control goes, it revokes its window and detaches the target (TyRichOleDetach): what OLE still
  calls on it then does nothing and answers DROPEFFECT_NONE. }

interface

{$IFDEF LCLWin32}
uses
  Windows, ActiveX, Classes, SysUtils, Types, tyControls.RichEdit;

var
  { How a window is registered with the system as a drop target and revoked: ole32's
    RegisterDragDrop / RevokeDragDrop. A test runner puts its own in their place, so that no
    window of its own is ever registered with the system (and counts the calls). }
  TyRichOleRegisterDragDrop: function(AWnd: HWND; const ATarget: IDropTarget): HRESULT;
  TyRichOleRevokeDragDrop: function(AWnd: HWND): HRESULT;

{ A new drop target feeding AControl (an IDropTarget). }
function TyRichOleNewTarget(AControl: TTyCustomRichEdit): IUnknown;
{ The control lets go of ATarget: it feeds nothing any more. }
procedure TyRichOleDetach(const ATarget: IUnknown);
{ AWnd registered with ATarget (one of TyRichOleNewTarget's); False when the system refused. }
function TyRichOleRegisterWindow(AWnd: HWND; const ATarget: IUnknown): Boolean;
procedure TyRichOleRevokeWindow(AWnd: HWND);
{ AStream read whole into ABytes, from its start (a stream may be handed over at its end): its
  size as Stat tells it, else grown by doubling; a short read (S_FALSE) keeps what it gave. }
function TyRichOleReadStream(const AStream: IStream; out ABytes: RawByteString): Boolean;
{ The keys of an OLE key state (MK_*) as the LCL's shift state. }
function TyRichOleShift(AKeys: DWORD): TShiftState;
{ An effect as OLE says it (DROPEFFECT_*), and back. }
function TyRichOleEffect(AEffect: TTyRichDropEffect): DWORD;
function TyRichOleEffects(AEffects: DWORD): TTyRichDropEffects;
{$ENDIF}

implementation

{$IFDEF LCLWin32}
uses
  ShellApi;

const
  // (MK_ALT is OLE's: the Windows unit does not declare it)
  CMkAlt = $20;
  // a device-independent bitmap with a BITMAPV5HEADER (the Windows unit does not declare it)
  CCfDibV5 = 17;
  // DROPFILES: its size, where its names begin, whether they are wide
  CDropFilesSize = 20;

type
  ITyRichOleTarget = interface
    ['{6C1E8E0B-3B7A-4F47-9D1B-6E2C1A9B5F31}']
    procedure Detach;
  end;

  { The data object as a drop offers it. The formats are asked once, when the drag comes in;
    the content is read only when the control takes the drop. }
  TTyRichOleOffer = class(TTyRichDropOffer)
  private
    FData: IDataObject;
    FAllowed: TTyRichDropEffects;
    FFlavours: TTyRichClipFlavours;
    FFiles: TStringArray;
    FRtfFormat, FPngFormat: Word;
    function Has(AFormat: Word): Boolean;
    function ReadFormat(AFormat: Word; out ABytes: RawByteString): Boolean;
    procedure ReadFiles;
  public
    constructor Create(const AData: IDataObject; AEffects: DWORD);
    procedure SetAllowed(AEffects: DWORD);
    function Flavours: TTyRichClipFlavours; override;
    function ReadRtf: RawByteString; override;
    function ReadPicture(AIndex: Integer; out AKind: TTyRichImageKind;
      out ABytes: TBytes): Boolean; override;
    function ReadText: string; override;
    function ReadAnsiText: string;
    function Files: TStringArray; override;
    function Allowed: TTyRichDropEffects; override;
    function FromOtherProgram: Boolean; override;
  end;

  TTyRichOleTarget = class(TInterfacedObject, IDropTarget, ITyRichOleTarget)
  private
    FOwner: TTyCustomRichEdit;
    FOffer: TTyRichOleOffer;
    // a call into the control is under way: a detach lets the offer live until it returns
    FBusy: Integer;
    procedure EndSession;
    function Feed(AKeys: DWORD; const APt: TPoint; AEnter: Boolean): TTyRichDropEffect;
  public
    constructor Create(AOwner: TTyCustomRichEdit);
    destructor Destroy; override;
    function DragEnter(const dataObj: IDataObject; grfKeyState: DWORD; pt: TPoint;
      var dwEffect: DWORD): HResult; stdcall;
    function DragOver(grfKeyState: DWORD; pt: TPoint; var dwEffect: DWORD): HResult; stdcall;
    function DragLeave: HResult; stdcall;
    function Drop(const dataObj: IDataObject; grfKeyState: DWORD; pt: TPoint;
      var dwEffect: DWORD): HResult; stdcall;
    procedure Detach;
  end;

  // the control's protected members the target reads
  TTyRichEditOleAccess = class(TTyCustomRichEdit);

function TyRichOleShift(AKeys: DWORD): TShiftState;
begin
  Result := [];
  if AKeys and MK_SHIFT <> 0 then Include(Result, ssShift);
  if AKeys and MK_CONTROL <> 0 then Include(Result, ssCtrl);
  if AKeys and CMkAlt <> 0 then Include(Result, ssAlt);
  if AKeys and MK_LBUTTON <> 0 then Include(Result, ssLeft);
  if AKeys and MK_RBUTTON <> 0 then Include(Result, ssRight);
  if AKeys and MK_MBUTTON <> 0 then Include(Result, ssMiddle);
end;

function TyRichOleEffect(AEffect: TTyRichDropEffect): DWORD;
begin
  case AEffect of
    rdeMove: Result := DROPEFFECT_MOVE;
    rdeCopy: Result := DROPEFFECT_COPY;
  else
    Result := DROPEFFECT_NONE;
  end;
end;

function TyRichOleEffects(AEffects: DWORD): TTyRichDropEffects;
begin
  Result := [];
  if AEffects and DROPEFFECT_MOVE <> 0 then Include(Result, rdeMove);
  if AEffects and DROPEFFECT_COPY <> 0 then Include(Result, rdeCopy);
end;

function FormatEtc(AFormat: Word; ATymed: DWORD): TFormatEtc;
begin
  Result.cfFormat := AFormat;
  Result.ptd := nil;
  Result.dwAspect := DVASPECT_CONTENT;
  Result.lindex := -1;
  Result.tymed := ATymed;
end;

{ ---- the offer ---- }

constructor TTyRichOleOffer.Create(const AData: IDataObject; AEffects: DWORD);
begin
  inherited Create;
  FData := AData;
  FAllowed := TyRichOleEffects(AEffects);
  FRtfFormat := Windows.RegisterClipboardFormat('Rich Text Format');
  FPngFormat := Windows.RegisterClipboardFormat('PNG');
  FFlavours := [];
  if FData = nil then Exit;
  if Has(FRtfFormat) then Include(FFlavours, rcfRtf);
  if Has(FPngFormat) or Has(CF_DIB) or Has(CCfDibV5) then Include(FFlavours, rcfPicture);
  if Has(CF_UNICODETEXT) or Has(CF_TEXT) then Include(FFlavours, rcfText);
  // a file list where no rich text and no picture comes (what Explorer's drag is)
  if (FFlavours * [rcfRtf, rcfPicture] = []) and Has(CF_HDROP) then ReadFiles;
end;

procedure TTyRichOleOffer.SetAllowed(AEffects: DWORD);
begin
  FAllowed := TyRichOleEffects(AEffects);
end;

function TTyRichOleOffer.Has(AFormat: Word): Boolean;
var
  fe: TFormatEtc;
begin
  fe := FormatEtc(AFormat, TYMED_HGLOBAL or TYMED_ISTREAM);
  Result := (AFormat <> 0) and (FData <> nil) and (FData.QueryGetData(fe) = S_OK);
end;

function TTyRichOleOffer.ReadFormat(AFormat: Word; out ABytes: RawByteString): Boolean;
var
  fe: TFormatEtc;
  med: TStgMedium;
  p: Pointer;
  n: PtrUInt;
  stm: IStream;
begin
  ABytes := '';
  Result := False;
  if (FData = nil) or (AFormat = 0) then Exit;
  fe := FormatEtc(AFormat, TYMED_HGLOBAL or TYMED_ISTREAM);
  FillChar(med, SizeOf(med), 0);
  if FData.GetData(fe, med) <> S_OK then Exit;
  try
    if med.Tymed = TYMED_HGLOBAL then
    begin
      // the data's own block, read once into the string the paste would read it into
      n := GlobalSize(med.HGLOBAL);
      p := GlobalLock(med.HGLOBAL);
      if p = nil then Exit;
      try
        SetLength(ABytes, n);
        if n > 0 then Move(p^, ABytes[1], n);
      finally
        GlobalUnlock(med.HGLOBAL);
      end;
      Result := True;
    end
    else if med.Tymed = TYMED_ISTREAM then
    begin
      stm := IStream(med.pstm);
      Result := TyRichOleReadStream(stm, ABytes);
      stm := nil;
    end;
  finally
    ReleaseStgMedium(med);
  end;
end;

{ The block holds a DROPFILES whose names begin inside it and whose list ends inside it (two
  zeros): what the shell then reads stays in the block. }
function WholeDropFiles(H: HGLOBAL): Boolean;
var
  p: PByte;
  size, at: PtrUInt;
  wide: Boolean;
begin
  Result := False;
  size := GlobalSize(H);
  if size < CDropFilesSize then Exit;
  p := GlobalLock(H);
  if p = nil then Exit;
  try
    at := PLongWord(p)^;
    wide := PLongWord(p + 16)^ <> 0;
    if (at < CDropFilesSize) or (at >= size) then Exit;
    if wide then
    begin
      while at + 3 < size do
      begin
        if (PWord(p + at)^ = 0) and (PWord(p + at + 2)^ = 0) then Exit(True);
        Inc(at, 2);
      end;
      // (a list of no name is its two zeros alone)
      Result := (at + 1 < size) and (at = PLongWord(p)^) and (PWord(p + at)^ = 0);
    end
    else
      while at + 1 < size do
      begin
        if (p[at] = 0) and (p[at + 1] = 0) then Exit(True);
        Inc(at);
      end;
  finally
    GlobalUnlock(H);
  end;
end;

procedure TTyRichOleOffer.ReadFiles;
var
  fe: TFormatEtc;
  med: TStgMedium;
  cnt, i, len: UINT;
  w: UnicodeString;
begin
  FFiles := nil;
  fe := FormatEtc(CF_HDROP, TYMED_HGLOBAL);
  FillChar(med, SizeOf(med), 0);
  if FData.GetData(fe, med) <> S_OK then Exit;
  try
    if (med.Tymed <> TYMED_HGLOBAL) or not WholeDropFiles(med.HGLOBAL) then Exit;
    cnt := DragQueryFileW(HDROP(med.HGLOBAL), $FFFFFFFF, nil, 0);
    // (no name: nothing usable)
    if cnt = 0 then Exit;
    SetLength(FFiles, cnt);
    for i := 0 to cnt - 1 do
    begin
      len := DragQueryFileW(HDROP(med.HGLOBAL), i, nil, 0);
      SetLength(w, len);
      if len > 0 then DragQueryFileW(HDROP(med.HGLOBAL), i, PWideChar(w), len + 1);
      FFiles[i] := UTF8Encode(w);
    end;
  finally
    ReleaseStgMedium(med);
  end;
end;

function TTyRichOleOffer.Flavours: TTyRichClipFlavours;
begin
  Result := FFlavours;
end;

function TTyRichOleOffer.ReadRtf: RawByteString;
begin
  if not ReadFormat(FRtfFormat, Result) then Result := '';
  SetCodePage(Result, CP_NONE, False);
end;

function TTyRichOleOffer.ReadPicture(AIndex: Integer; out AKind: TTyRichImageKind;
  out ABytes: TBytes): Boolean;
var
  s: RawByteString;
  f: Word;
begin
  ABytes := nil;
  AKind := rikPng;
  // the paste's order: PNG, then a device-independent bitmap (with either header)
  Result := (AIndex >= 0) and (AIndex <= 2);
  if not Result then Exit;
  case AIndex of
    0: f := FPngFormat;
    1: f := CF_DIB;
  else
    f := CCfDibV5;
  end;
  if AIndex > 0 then AKind := rikDib;
  if not Has(f) or not ReadFormat(f, s) or (s = '') then Exit;
  SetLength(ABytes, Length(s));
  Move(s[1], ABytes[0], Length(s));
end;

function TTyRichOleOffer.ReadText: string;
var
  s: RawByteString;
  n, i: PtrInt;
  w: UnicodeString;
  p: PWideChar;
begin
  Result := '';
  if not Has(CF_UNICODETEXT) or not ReadFormat(CF_UNICODETEXT, s) then
  begin
    Result := ReadAnsiText;
    Exit;
  end;
  // UTF-16 up to its terminating zero (the block may be longer)
  n := Length(s) div 2;
  if n = 0 then Exit;
  p := PWideChar(@s[1]);
  i := 0;
  while (i < n) and (p[i] <> #0) do Inc(i);
  SetString(w, p, i);
  Result := UTF8Encode(w);
end;

function TTyRichOleOffer.ReadAnsiText: string;
var
  s, loc: RawByteString;
  cp: UINT;
  i, k: Integer;
  w: UnicodeString;
  buf: array[0..15] of WideChar;
begin
  Result := '';
  if not Has(CF_TEXT) or not ReadFormat(CF_TEXT, s) then Exit;
  i := 0;
  while (i < Length(s)) and (s[i + 1] <> #0) do Inc(i);
  if i = 0 then Exit;
  { the code page of the locale the text comes with (CF_LOCALE), else the system's ANSI one -
    what the system's own conversion of CF_TEXT on the clipboard takes }
  cp := CP_ACP;
  if Has(CF_LOCALE) and ReadFormat(CF_LOCALE, loc) and (Length(loc) >= 4) then
    if GetLocaleInfoW(PLongWord(@loc[1])^, LOCALE_IDEFAULTANSICODEPAGE, @buf[0],
      Length(buf)) > 0 then
      cp := StrToIntDef(UTF8Encode(UnicodeString(PWideChar(@buf[0]))), CP_ACP);
  k := MultiByteToWideChar(cp, 0, @s[1], i, nil, 0);
  if k <= 0 then Exit;
  SetLength(w, k);
  MultiByteToWideChar(cp, 0, @s[1], i, PWideChar(w), k);
  Result := UTF8Encode(w);
end;

function TTyRichOleOffer.Files: TStringArray;
begin
  Result := FFiles;
end;

function TTyRichOleOffer.Allowed: TTyRichDropEffects;
begin
  Result := FAllowed;
end;

function TTyRichOleOffer.FromOtherProgram: Boolean;
begin
  Result := True;
end;

function TyRichOleReadStream(const AStream: IStream; out ABytes: RawByteString): Boolean;
var
  st: TStatStg;
  got, cap: PtrUInt;
  k: LongWord;
  at: LargeUInt;
  more: array[0..4095] of Byte;
begin
  ABytes := '';
  Result := False;
  if AStream = nil then Exit;
  // (a stream that cannot seek is read from where it is)
  AStream.Seek(0, STREAM_SEEK_SET, at);
  cap := 0;
  FillChar(st, SizeOf(st), 0);
  if AStream.Stat(st, STATFLAG_NONAME) = S_OK then cap := st.cbSize;
  if cap = 0 then cap := 64 * 1024;
  SetLength(ABytes, cap);
  got := 0;
  repeat
    k := 0;
    if got < cap then
    begin
      // (S_FALSE: fewer bytes than asked - the stream's end - but those it gave are good)
      if Failed(AStream.Read(@ABytes[got + 1], cap - got, @k)) then k := 0;
    end
    else
    begin
      // full: asked for more in a small buffer first - a size told right costs no growth
      if Failed(AStream.Read(@more[0], SizeOf(more), @k)) then k := 0;
      if k > 0 then
      begin
        cap := cap * 2;
        SetLength(ABytes, cap);
        Move(more[0], ABytes[got + 1], k);
      end;
    end;
    Inc(got, k);
  until k = 0;
  SetLength(ABytes, got);
  Result := True;
end;

{ ---- the target ---- }

constructor TTyRichOleTarget.Create(AOwner: TTyCustomRichEdit);
begin
  inherited Create;
  FOwner := AOwner;
end;

destructor TTyRichOleTarget.Destroy;
begin
  FreeAndNil(FOffer);
  inherited Destroy;
end;

procedure TTyRichOleTarget.Detach;
begin
  FOwner := nil;
  if FBusy = 0 then FreeAndNil(FOffer);
end;

procedure TTyRichOleTarget.EndSession;
begin
  if (FOwner <> nil) and (FOffer <> nil) and
    (TTyRichEditOleAccess(FOwner).DropOffer = FOffer) then
    FOwner.DropLeave;
  if FBusy = 0 then FreeAndNil(FOffer);
end;

function TTyRichOleTarget.Feed(AKeys: DWORD; const APt: TPoint; AEnter: Boolean): TTyRichDropEffect;
var
  p: TPoint;
begin
  Result := rdeNone;
  if (FOwner = nil) or (FOffer = nil) or not FOwner.AcceptDrops then Exit;
  p := TTyRichEditOleAccess(FOwner).DropPointOf(APt);
  Inc(FBusy);
  try
    // (the control's session may have ended meanwhile - its content replaced: a new one)
    if AEnter or (TTyRichEditOleAccess(FOwner).DropOffer <> FOffer) then
      Result := FOwner.DropEnter(FOffer, p.X, p.Y, TyRichOleShift(AKeys))
    else
      Result := FOwner.DropOver(p.X, p.Y, TyRichOleShift(AKeys));
  finally
    Dec(FBusy);
  end;
end;

function TTyRichOleTarget.DragEnter(const dataObj: IDataObject; grfKeyState: DWORD;
  pt: TPoint; var dwEffect: DWORD): HResult; stdcall;
begin
  Result := S_OK;
  try
    EndSession;
    if (FOwner = nil) or not FOwner.AcceptDrops or (dataObj = nil) then
    begin
      dwEffect := DROPEFFECT_NONE;
      Exit;
    end;
    FOffer := TTyRichOleOffer.Create(dataObj, dwEffect);
    dwEffect := TyRichOleEffect(Feed(grfKeyState, pt, True));
  except
    // nothing of the control's may reach the system's drag: the drop is "nothing"
    try
      EndSession;
    except
    end;
    dwEffect := DROPEFFECT_NONE;
    Result := E_UNEXPECTED;
  end;
end;

function TTyRichOleTarget.DragOver(grfKeyState: DWORD; pt: TPoint;
  var dwEffect: DWORD): HResult; stdcall;
begin
  Result := S_OK;
  try
    if FOffer = nil then
    begin
      dwEffect := DROPEFFECT_NONE;
      Exit;
    end;
    // what the source allows may change with its keys (OLE asks at each move)
    FOffer.SetAllowed(dwEffect);
    dwEffect := TyRichOleEffect(Feed(grfKeyState, pt, False));
  except
    try
      EndSession;
    except
    end;
    dwEffect := DROPEFFECT_NONE;
    Result := E_UNEXPECTED;
  end;
end;

function TTyRichOleTarget.DragLeave: HResult; stdcall;
begin
  Result := S_OK;
  try
    EndSession;
  except
    FreeAndNil(FOffer);
    Result := E_UNEXPECTED;
  end;
end;

function TTyRichOleTarget.Drop(const dataObj: IDataObject; grfKeyState: DWORD; pt: TPoint;
  var dwEffect: DWORD): HResult; stdcall;
var
  e: TTyRichDropEffect;
  p: TPoint;
begin
  Result := S_OK;
  e := rdeNone;
  try
    try
      if (FOwner <> nil) and FOwner.AcceptDrops and (dataObj <> nil) then
      begin
        // (a drop with no drag over before it: its offer now)
        if FOffer = nil then FOffer := TTyRichOleOffer.Create(dataObj, dwEffect)
        else FOffer.SetAllowed(dwEffect);
        p := TTyRichEditOleAccess(FOwner).DropPointOf(pt);
        Inc(FBusy);
        try
          if TTyRichEditOleAccess(FOwner).DropOffer <> FOffer then
            FOwner.DropEnter(FOffer, p.X, p.Y, TyRichOleShift(grfKeyState));
          // what really happened: rdeNone for a drop refused or failed (the source keeps its data)
          if (FOwner <> nil) and (TTyRichEditOleAccess(FOwner).DropOffer = FOffer) then
            e := FOwner.DropOn(p.X, p.Y, TyRichOleShift(grfKeyState));
        finally
          Dec(FBusy);
        end;
      end;
    finally
      EndSession;
    end;
  except
    e := rdeNone;
    Result := E_UNEXPECTED;
  end;
  dwEffect := TyRichOleEffect(e);
end;

{ ---- the unit's calls ---- }

function TyRichOleNewTarget(AControl: TTyCustomRichEdit): IUnknown;
begin
  Result := TTyRichOleTarget.Create(AControl) as IDropTarget;
end;

procedure TyRichOleDetach(const ATarget: IUnknown);
var
  t: ITyRichOleTarget;
begin
  if Supports(ATarget, ITyRichOleTarget, t) then t.Detach;
end;

function TyRichOleRegisterWindow(AWnd: HWND; const ATarget: IUnknown): Boolean;
var
  t: IDropTarget;
begin
  Result := False;
  if (AWnd = 0) or not Supports(ATarget, IDropTarget, t) then Exit;
  Result := TyRichOleRegisterDragDrop(AWnd, t) = S_OK;
end;

procedure TyRichOleRevokeWindow(AWnd: HWND);
begin
  if AWnd <> 0 then TyRichOleRevokeDragDrop(AWnd);
end;

function SystemRegister(AWnd: HWND; const ATarget: IDropTarget): HRESULT;
begin
  Result := ActiveX.RegisterDragDrop(AWnd, ATarget);
end;

function SystemRevoke(AWnd: HWND): HRESULT;
begin
  Result := ActiveX.RevokeDragDrop(AWnd);
end;

initialization
  TyRichOleRegisterDragDrop := @SystemRegister;
  TyRichOleRevokeDragDrop := @SystemRevoke;
{$ENDIF}

end.
