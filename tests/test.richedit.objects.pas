unit test.richedit.objects;

{ Pictures in TTyRichEdit: inserted from code (a file, a stream, a TGraphic), the eight handles
  of a selected picture - their size, place, colours, cursors and hit test at every zoom and
  PPI -, resizing by a handle's drag (the outline's arithmetic for every handle, with and
  without Shift, at the bounds; one command, its undo and redo; Esc, a lost capture, a change
  meanwhile; OnObjectResize), what the history keeps of a resized picture, what a resize keeps
  of a file's picture (a metafile too) and what it repaints.

  Headless, on the editor's probe (TEditProbe of test.richedit.edit: the test device, the
  counters). No window, no system clipboard, no file dialog, no input method: the picture
  files a test needs are made in a temporary folder it removes. Every bound is a count, never
  a time (the times are the performance suite's). The unit is ASCII. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, fpcunit, testregistry, Controls, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.StrConsts,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite, tyControls.RichEdit.Layout,
  tyControls.RichEdit, test.richedit.control, test.richedit.edit, test.richedit.msftedit;

type
  { The editor's probe with the handles' seams. }
  TObjProbe = class(TEditProbe)
  public
    function Handles(out ARects: TTyRichHandleRects): Boolean;
    function HandleAt(X, Y: Integer; out AHandle: TTyRichHandle): Boolean;
    function Outline(out ARect: TRect; out AW, AH: Integer): Boolean;
    function InResize: Boolean;
    procedure MoveWith(X, Y: Integer; AShift: TShiftState);
    procedure ReleaseWith(X, Y: Integer; AShift: TShiftState);
    procedure LoseCapture;
  end;

  TTyRichObjectsTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TObjProbe;
    FTemp: string;
    FResizeCalls: Integer;
    FResizeAllow: Boolean;
    FResizeSetW, FResizeSetH: Integer;
    FResizeSeen: TTyRichObject;
    FResizeSeenW, FResizeSeenH: Integer;
    function NewProbe: TObjProbe;
    procedure PaintAll;
    procedure LoadRtf(const S: RawByteString);
    function SaveRtf: TBytes;
    function TempDir: string;
    function TempFile(const AName: string; const ABytes: TBytes): string;
    { 'ab' + a picture of AW x AH pixels (96 dpi: 15 twips a pixel) + 'cd' after a first
      paragraph 'first line', the picture selected; its position. }
    function PictureDoc(AW, AH: Integer): TTyRichPos;
    procedure SelectAt(APos: TTyRichPos);
    function PictureAt(APos: TTyRichPos): TTyRichPicture;
    function Centre(const R: TRect): TPoint;
    procedure Drag(AHandle: TTyRichHandle; ADX, ADY: Integer; AShift: TShiftState = []);
    procedure CheckRefused(const AWhat: string; AResult: Boolean; const AReason: string);
    procedure CheckSilent(const AWhat: string; AResult: Boolean);
    procedure OnResize(Sender: TObject; AObject: TTyRichObject; var AWidthTwips,
      AHeightTwips: Integer; var AAllow: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestResizeIsOneCommandAndKeepsAspectOnCorners;
    procedure TestMetafileShowsPlaceholderAndRoundTrips;
    // the handles
    procedure TestHandlesFollowTheScreenNotTheZoom;
    procedure TestHandlesAreDrawnOverWhatIsBesideThePicture;
    procedure TestAPressOnAHandleResizesAndNeverSelects;
    procedure TestNoHandlesWhereNothingCanBeResized;
    procedure TestTwoPicturesSideBySide;
    procedure TestAPictureInACellAndAsTheOnlyContent;
    procedure TestTheHandlesRepaintOnlyTheirPlace;
    // resizing
    procedure TestTheOutlineOfEveryHandle;
    procedure TestTheBoundsOfAResize;
    procedure TestEscALostCaptureAndAChangeEndADragWithNothingDone;
    procedure TestOnObjectResizeConstrainsOrVetoes;
    procedure TestTheResizeCommandInTheDocument;
    procedure TestAResizeKeepsNoSecondCopyInTheHistory;
    procedure TestAResizedPictureShowsItsDecodedPixels;
    procedure TestAResizedFilePictureIsWrittenAtItsNewSize;
    // inserting
    procedure TestInsertFromEachDoorAndFormat;
    procedure TestInsertRefusals;
  end;

implementation

const
  BS = '\';

{ ---- helpers ---- }

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

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

function FixtureFile(const AName: string): TBytes;
var
  f: TFileStream;
begin
  Result := nil;
  f := TFileStream.Create(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim +
    'fixtures' + PathDelim + 'rtf' + PathDelim + AName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, f.Size);
    if f.Size > 0 then f.ReadBuffer(Result[0], f.Size);
  finally
    f.Free;
  end;
end;

function ImageBytes(AW, AH: Integer; AColor: TBGRAPixel; AFormat: TBGRAImageFormat): TBytes;
var
  b: TBGRABitmap;
  st: TBytesStream;
begin
  b := TBGRABitmap.Create(AW, AH, AColor);
  st := TBytesStream.Create;
  try
    b.SaveToStreamAs(st, AFormat);
    Result := Copy(st.Bytes, 0, st.Size);
  finally
    st.Free;
    b.Free;
  end;
end;

function PngOf(AW, AH: Integer): TBytes;
begin
  Result := ImageBytes(AW, AH, BGRA(200, 30, 30, 255), ifPng);
end;

{ A PNG whose bytes do not compress: about AW x AH x 4 bytes. }
function NoisePng(AW, AH: Integer): TBytes;
var
  b: TBGRABitmap;
  st: TBytesStream;
  p: PBGRAPixel;
  i: Integer;
  seed: Cardinal;
begin
  b := TBGRABitmap.Create(AW, AH);
  st := TBytesStream.Create;
  try
    seed := 12345;
    p := b.Data;
    for i := 0 to AW * AH - 1 do
    begin
      seed := seed * 1103515245 + 12345;
      p^.red := (seed shr 8) and $FF;
      p^.green := (seed shr 16) and $FF;
      p^.blue := (seed shr 24) and $FF;
      p^.alpha := 255;
      Inc(p);
    end;
    b.InvalidateBitmap;
    b.SaveToStreamAs(st, ifPng);
    Result := Copy(st.Bytes, 0, st.Size);
  finally
    st.Free;
    b.Free;
  end;
end;

// the smallest GIF: one white pixel
function GifBytes: TBytes;
const
  G: array[0..42] of Byte = ($47, $49, $46, $38, $39, $61, $01, $00, $01, $00, $80, $00, $00,
    $FF, $FF, $FF, $00, $00, $00, $21, $F9, $04, $01, $00, $00, $00, $00, $2C, $00, $00, $00,
    $00, $01, $00, $01, $00, $00, $02, $02, $44, $01, $00, $3B);
begin
  Result := nil;
  SetLength(Result, Length(G));
  Move(G[0], Result[0], Length(G));
end;

// an icon of 2 x 2 red pixels (32 bits, its AND mask after them)
function IcoBytes: TBytes;
const
  I: array[0..85] of Byte = (
    0, 0, 1, 0, 1, 0,
    2, 2, 0, 0, 1, 0, 32, 0, 64, 0, 0, 0, 22, 0, 0, 0,
    40, 0, 0, 0, 2, 0, 0, 0, 4, 0, 0, 0, 1, 0, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255,
    0, 0, 0, 0, 0, 0, 0, 0);
begin
  Result := nil;
  SetLength(Result, Length(I));
  Move(I[0], Result[0], Length(I));
end;

{ A metafile nothing here draws (a rectangle and a line: no bitmap), and an EMF header. }
function WmfDrawing: TBytes;
const
  W: array[0..53] of Byte = (
    $01, $00, $09, $00, $00, $03, $1B, $00, $00, $00, $00, $00, $07, $00, $00, $00, $00, $00,
    $07, $00, $00, $00, $1B, $04, $10, $00, $20, $00, $00, $00, $00, $00,
    $05, $00, $00, $00, $13, $02, $30, $00, $40, $00,
    $03, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00);
begin
  Result := nil;
  SetLength(Result, Length(W));
  Move(W[0], Result[0], Length(W));
end;

function EmfHeader: TBytes;
var
  i: Integer;
begin
  Result := nil;
  SetLength(Result, 108);
  for i := 0 to High(Result) do Result[i] := 0;
  Result[0] := 1;
  Result[4] := 108;
  Result[40] := $20;
  Result[41] := $45;
  Result[42] := $4D;
  Result[43] := $46;
end;

function HexOf(const ABytes: TBytes): RawByteString;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(ABytes) do Result := Result + LowerCase(IntToHex(ABytes[i], 2));
end;

function Head: RawByteString;
begin
  Result := '{' + BS + 'rtf1' + BS + 'ansi' + BS + 'deff0{' + BS + 'fonttbl{' + BS +
    'f0 Arial;}}' + #13#10;
end;

{ An RTF file whose second paragraph holds the metafile AData (AWord: wmetafile8 or emfblip)
  between 'a' and 'b'. }
function MetafileRtf(const AWord: RawByteString; const AData: TBytes): RawByteString;
begin
  Result := Head + BS + 'pard' + BS + 'f0 first' + BS + 'par' + #13#10 + 'a{' + BS + 'pict' + BS +
    AWord + BS + 'picw2540' + BS + 'pich1270' + BS + 'picwgoal1440' + BS + 'pichgoal720 ' +
    HexOf(AData) + '}b' + BS + 'par' + #13#10 + '}';
end;

function LoadDoc(const ABytes: TBytes): TTyRichDocument;
var
  st: TBytesStream;
begin
  Result := TTyRichDocument.Create;
  st := TBytesStream.Create(ABytes);
  try
    TyRichLoadRtf(Result, st);
  finally
    st.Free;
  end;
end;

function SamePx(const A, B: TBGRAPixel): Boolean;
begin
  Result := (A.red = B.red) and (A.green = B.green) and (A.blue = B.blue) and (A.alpha = B.alpha);
end;

{ ---- the probe ---- }

function TObjProbe.Handles(out ARects: TTyRichHandleRects): Boolean;
begin
  Result := ObjectHandleRects(ARects);
end;

function TObjProbe.HandleAt(X, Y: Integer; out AHandle: TTyRichHandle): Boolean;
begin
  Result := ObjectHandleAt(X, Y, AHandle);
end;

function TObjProbe.Outline(out ARect: TRect; out AW, AH: Integer): Boolean;
begin
  Result := ResizeOutline(ARect, AW, AH);
end;

function TObjProbe.InResize: Boolean;
begin
  Result := Resizing;
end;

procedure TObjProbe.MoveWith(X, Y: Integer; AShift: TShiftState);
begin
  MouseMove(AShift + [ssLeft], X, Y);
end;

procedure TObjProbe.ReleaseWith(X, Y: Integer; AShift: TShiftState);
begin
  MouseUp(mbLeft, AShift, X, Y);
end;

procedure TObjProbe.LoseCapture;
begin
  CaptureChanged;
end;

{ ---- fixture ---- }

procedure TTyRichObjectsTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FRich := NewProbe;
  FTemp := '';
  FResizeCalls := 0;
  FResizeAllow := True;
  FResizeSetW := 0;
  FResizeSetH := 0;
end;

procedure TTyRichObjectsTest.TearDown;
var
  sr: TSearchRec;
begin
  FreeAndNil(FRich);
  FreeAndNil(FCtl);
  if (FTemp <> '') and DirectoryExists(FTemp) then
  begin
    if FindFirst(FTemp + '*', faAnyFile, sr) = 0 then
    try
      repeat
        if (sr.Attr and faDirectory) = 0 then DeleteFile(FTemp + sr.Name);
      until FindNext(sr) <> 0;
    finally
      FindClose(sr);
    end;
    RemoveDir(FTemp);
  end;
end;

function TTyRichObjectsTest.NewProbe: TObjProbe;
begin
  Result := TObjProbe.Create(nil);
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 300);
  Result.ResetCounts;
end;

procedure TTyRichObjectsTest.PaintAll;
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width, FRich.Height);
    FRich.PaintPart(bmp.Canvas, Rect(0, 0, FRich.Width, FRich.Height), True);
  finally
    bmp.Free;
  end;
end;

procedure TTyRichObjectsTest.LoadRtf(const S: RawByteString);
var
  st: TBytesStream;
begin
  st := TBytesStream.Create(RawBytes(S));
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
  FRich.UpdateView;
end;

function TTyRichObjectsTest.SaveRtf: TBytes;
var
  st: TBytesStream;
begin
  st := TBytesStream.Create;
  try
    FRich.SaveToStream(st, rfRtf);
    Result := Copy(st.Bytes, 0, st.Size);
  finally
    st.Free;
  end;
end;

function TTyRichObjectsTest.TempDir: string;
begin
  if FTemp = '' then
  begin
    FTemp := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'tyrichobjects' +
      IntToStr(GetProcessID) + PathDelim;
    ForceDirectories(FTemp);
  end;
  Result := FTemp;
end;

function TTyRichObjectsTest.TempFile(const AName: string; const ABytes: TBytes): string;
var
  f: TFileStream;
begin
  Result := TempDir + AName;
  f := TFileStream.Create(Result, fmCreate);
  try
    if Length(ABytes) > 0 then f.WriteBuffer(ABytes[0], Length(ABytes));
  finally
    f.Free;
  end;
end;

function TTyRichObjectsTest.PictureDoc(AW, AH: Integer): TTyRichPos;
var
  pic: TTyRichPicture;
begin
  FRich.Lines.Text := 'first line'#13#10'abcd';
  Result := FRich.Document.Text.ParaStart(1) + 2;
  pic := TTyRichPicture.Create(rpfPng, PngOf(AW, AH), AW * 15, AH * 15);
  AssertTrue('the picture goes in', FRich.Document.Execute(TTyRichInsertObject.Create(Result, pic)));
  FRich.Document.ClearUndo;
  FRich.Modified := False;
  FRich.UpdateView;
  SelectAt(Result);
  PaintAll;
end;

procedure TTyRichObjectsTest.SelectAt(APos: TTyRichPos);
begin
  FRich.SelStart := APos;
  FRich.SelLength := 1;
  FRich.UpdateView;
end;

function TTyRichObjectsTest.PictureAt(APos: TTyRichPos): TTyRichPicture;
var
  o: TTyRichObject;
begin
  o := FRich.Document.ObjectAt(APos);
  AssertTrue('a picture there', o is TTyRichPicture);
  Result := TTyRichPicture(o);
end;

function TTyRichObjectsTest.Centre(const R: TRect): TPoint;
begin
  Result := Point((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
end;

{ A press on AHandle's centre, a move by ADX, ADY pixels and the release there. }
procedure TTyRichObjectsTest.Drag(AHandle: TTyRichHandle; ADX, ADY: Integer; AShift: TShiftState);
var
  rs: TTyRichHandleRects;
  c: TPoint;
begin
  AssertTrue('handles to drag', FRich.Handles(rs));
  c := Centre(rs[AHandle]);
  FRich.PressAt(c.X, c.Y, AShift);
  AssertTrue('a resize began', FRich.InResize);
  FRich.MoveWith(c.X + ADX, c.Y + ADY, AShift);
  FRich.ReleaseWith(c.X + ADX, c.Y + ADY, AShift);
  AssertFalse('the resize ended', FRich.InResize);
end;

procedure TTyRichObjectsTest.CheckRefused(const AWhat: string; AResult: Boolean;
  const AReason: string);
begin
  AssertFalse(AWhat + ': not done', AResult);
  AssertEquals(AWhat + ': told once', 1, FRich.Refused);
  AssertEquals(AWhat + ': why', AReason, FRich.LastReason);
  FRich.Refused := 0;
  FRich.LastReason := '';
end;

procedure TTyRichObjectsTest.CheckSilent(const AWhat: string; AResult: Boolean);
begin
  AssertFalse(AWhat + ': not done', AResult);
  AssertEquals(AWhat + ': nothing told', 0, FRich.Refused);
end;

procedure TTyRichObjectsTest.OnResize(Sender: TObject; AObject: TTyRichObject;
  var AWidthTwips, AHeightTwips: Integer; var AAllow: Boolean);
begin
  Inc(FResizeCalls);
  FResizeSeen := AObject;
  FResizeSeenW := AWidthTwips;
  FResizeSeenH := AHeightTwips;
  AAllow := FResizeAllow;
  if FResizeSetW > 0 then AWidthTwips := FResizeSetW;
  if FResizeSetH > 0 then AHeightTwips := FResizeSetH;
end;

{ ---- the tests ---- }

{ A corner keeps the shape the picture is shown in, Shift lets it go, a side's middle changes
  that side; the release is one command, one undo step with its name; undo puts the very
  object and the selection back, redo the new one; the object stays selected with handles. }
procedure TTyRichObjectsTest.TestResizeIsOneCommandAndKeepsAspectOnCorners;
var
  p: TTyRichPos;
  old, nw: TTyRichPicture;
  rs: TTyRichHandleRects;
begin
  p := PictureDoc(100, 50);
  old := PictureAt(p);
  // bottom right, 30 right and 10 down: the width changed more (30 %) and decides
  Drag(rhBottomRight, 30, 10);
  AssertEquals('one undo step', 1, FRich.Document.UndoDepth);
  AssertEquals('its name', rsRichUndoResizeObject, FRich.Document.UndoDescription);
  nw := PictureAt(p);
  AssertTrue('a new object', nw <> old);
  AssertEquals('the width', 1950, nw.WidthTwips);
  AssertEquals('the height follows the shape', 975, nw.HeightTwips);
  AssertTrue('the same bytes, shared', Pointer(nw.Data) = Pointer(old.Data));
  AssertTrue('the same format', nw.PictureFormat = old.PictureFormat);
  AssertEquals('no raw RTF', '', nw.RawRtf);
  AssertEquals('selected again: start', p, FRich.SelStart);
  AssertEquals('selected again: length', 1, FRich.SelLength);
  PaintAll;
  AssertTrue('with its handles', FRich.Handles(rs));
  AssertTrue('Modified', FRich.Modified);
  // undo: the very object, the selection as it was
  FRich.SelStart := 0;
  FRich.Undo;
  AssertTrue('undo: the old object itself', FRich.Document.ObjectAt(p) = old);
  AssertEquals('undo: the selection back', p, FRich.SelStart);
  AssertEquals('undo: one character', 1, FRich.SelLength);
  AssertFalse('undo: not Modified', FRich.Modified);
  FRich.Redo;
  AssertTrue('redo: the new object itself', FRich.Document.ObjectAt(p) = nw);
  AssertEquals('redo: selected', p, FRich.SelStart);
  AssertEquals('redo: the object', 1, FRich.SelLength);
  // with Shift a corner does not keep the shape
  FRich.Document.ClearUndo;
  PaintAll;
  Drag(rhBottomRight, 30, 10, [ssShift]);
  AssertEquals('Shift: the width', 1950 + 450, PictureAt(p).WidthTwips);
  AssertEquals('Shift: the height on its own', 975 + 150, PictureAt(p).HeightTwips);
  // a side's middle: that side only (a corner's move across)
  PaintAll;
  Drag(rhRight, -20, 40);
  AssertEquals('the right middle: the width', 2400 - 300, PictureAt(p).WidthTwips);
  AssertEquals('the right middle: the height stays', 1125, PictureAt(p).HeightTwips);
  PaintAll;
  Drag(rhTop, 30, -10);
  AssertEquals('the top middle: the width stays', 2100, PictureAt(p).WidthTwips);
  AssertEquals('the top middle: the height', 1125 + 150, PictureAt(p).HeightTwips);
  AssertEquals('three steps', 3, FRich.Document.UndoDepth);
  // the top left corner, the shape kept: up and left grow it
  PaintAll;
  Drag(rhTopLeft, -21, -1);
  AssertEquals('the top left: the width', 2100 + 315, PictureAt(p).WidthTwips);
  AssertEquals('the top left: the height in the shape',
    Round(1275 * (2415 / 2100)), PictureAt(p).HeightTwips);
end;

{ A metafile nothing here draws shows the placeholder, is selected by a click, shows handles
  and is resized; saved without a resize its group is the file's, byte for byte; after a
  resize its data bytes and format are the file's and it reads back at the new size; a resize
  undone saves the file. A WordPad picture (\wmetafile8) stays that metafile. }
procedure TTyRichObjectsTest.TestMetafileShowsPlaceholderAndRoundTrips;
var
  rtf: RawByteString;
  p: TTyRichPos;
  pic, back: TTyRichPicture;
  fmt: TTyRichPictureFormat;
  st0, n0: Integer;
  rs: TTyRichHandleRects;
  saved, again: TBytes;
  c: TPoint;
  kind: Integer;
  file0: TBytes;
  d: TTyRichDocument;
  k: Integer;
begin
  for kind := 0 to 1 do
  begin
    if kind = 0 then rtf := MetafileRtf('wmetafile8', WmfDrawing)
    else rtf := MetafileRtf('emfblip', EmfHeader);
    file0 := RawBytes(rtf);
    FreeAndNil(FRich);
    FRich := NewProbe;
    LoadRtf(rtf);
    p := FRich.Document.Text.ParaStart(1) + 1;
    pic := PictureAt(p);
    AssertFalse(IntToStr(kind) + ': nothing draws it', pic.DisplayData(fmt, st0, n0));
    AssertTrue(IntToStr(kind) + ': a placeholder: it can be resized', pic.CanResize);
    // saved as it is: the file's bytes
    AssertTrue(IntToStr(kind) + ': open and save is the file', SameBytes(file0, SaveRtf));
    // a click on it selects it, and it shows handles
    PaintAll;
    c := Centre(FRich.PositionRect(p));
    c.X := FRich.PositionRect(p).Left + 20;
    FRich.PressAt(c.X, c.Y);
    FRich.ReleaseAt(c.X, c.Y);
    AssertEquals(IntToStr(kind) + ': the click selects it', p, FRich.SelStart);
    AssertEquals(IntToStr(kind) + ': one character', 1, FRich.SelLength);
    PaintAll;
    AssertTrue(IntToStr(kind) + ': handles', FRich.Handles(rs));
    // 96 x 48 pixels (1440 x 720 twips): the right middle 24 pixels on
    Drag(rhRight, 24, 0);
    back := PictureAt(p);
    AssertEquals(IntToStr(kind) + ': the new width', 1440 + 360, back.WidthTwips);
    AssertEquals(IntToStr(kind) + ': the height', 720, back.HeightTwips);
    AssertTrue(IntToStr(kind) + ': the data shared', Pointer(back.Data) = Pointer(pic.Data));
    saved := SaveRtf;
    // read back: the same bytes and format, the new size
    d := LoadDoc(saved);
    try
      d.BeginRead;
      try
        k := d.Text.ParaStart(1) + 1;
        AssertTrue(IntToStr(kind) + ': read back a picture', d.ObjectAt(k) is TTyRichPicture);
        back := TTyRichPicture(d.ObjectAt(k));
        AssertTrue(IntToStr(kind) + ': the format', back.PictureFormat = pic.PictureFormat);
        AssertTrue(IntToStr(kind) + ': the bytes', SameBytes(back.Data, pic.Data));
        AssertEquals(IntToStr(kind) + ': the width read back', 1800, back.WidthTwips);
        AssertEquals(IntToStr(kind) + ': the height read back', 720, back.HeightTwips);
      finally
        d.EndRead;
      end;
    finally
      d.Free;
    end;
    // the resize undone: the file again
    FRich.Undo;
    again := SaveRtf;
    AssertTrue(IntToStr(kind) + ': resize, undo, save is the file', SameBytes(file0, again));
  end;
  // WordPad's own: a \wmetafile8 of one bitmap stays that metafile, its bytes the file's
  FreeAndNil(FRich);
  FRich := NewProbe;
  file0 := FixtureFile('wp-zh-picture.rtf');
  LoadRtf(StrOfBytes(file0));
  p := -1;
  for k := 0 to FRich.Document.Text.Length - 1 do
    if FRich.Document.ObjectAt(k) is TTyRichPicture then
    begin
      p := k;
      Break;
    end;
  AssertTrue('WordPad: a picture', p >= 0);
  pic := PictureAt(p);
  AssertTrue('WordPad: a WMF', pic.PictureFormat = rpfWmf);
  SelectAt(p);
  PaintAll;
  Drag(rhBottomRight, 10, 10);
  back := PictureAt(p);
  AssertTrue('WordPad: still the WMF', back.PictureFormat = rpfWmf);
  AssertTrue('WordPad: its bytes', SameBytes(back.Data, pic.Data));
  saved := SaveRtf;
  AssertTrue('WordPad: written as a metafile',
    Pos(BS + 'wmetafile8', StrOfBytes(saved)) > 0);
  AssertTrue('WordPad: at the new width',
    Pos(BS + 'picwgoal' + IntToStr(back.WidthTwips), StrOfBytes(saved)) > 0);
  FRich.Undo;
  AssertTrue('WordPad: resize, undo, save is the file', SameBytes(file0, SaveRtf));
end;

{ The handle's side follows the screen's PPI - 7 at 96, 11 at 144, 15 at 192 - and never the
  zoom; the frame's box follows both; the handles sit centred on the frame's pixels; the hit
  test finds each handle on its pixels and nothing just outside. }
procedure TTyRichObjectsTest.TestHandlesFollowTheScreenNotTheZoom;
const
  PPIs: array[0..2] of Integer = (96, 144, 192);
  Sides: array[0..2] of Integer = (7, 11, 15);
  Zooms: array[0..2] of Integer = (50, 100, 200);
var
  i, j, w, hgt: Integer;
  rs: TTyRichHandleRects;
  h, got: TTyRichHandle;
  c: TPoint;
  p: TTyRichPos;
begin
  for i := 0 to 2 do
    for j := 0 to 2 do
    begin
      FreeAndNil(FRich);
      FRich := NewProbe;
      FRich.Font.PixelsPerInch := PPIs[i];
      FRich.SetBounds(0, 0, 900, 700);
      FRich.Zoom := Zooms[j];
      p := PictureDoc(100, 50);
      AssertTrue(Format('%d/%d: handles', [PPIs[i], Zooms[j]]), FRich.Handles(rs));
      for h := Low(TTyRichHandle) to High(TTyRichHandle) do
      begin
        AssertEquals(Format('%d/%d: handle %d wide', [PPIs[i], Zooms[j], Ord(h)]), Sides[i],
          rs[h].Right - rs[h].Left);
        AssertEquals(Format('%d/%d: handle %d high', [PPIs[i], Zooms[j], Ord(h)]), Sides[i],
          rs[h].Bottom - rs[h].Top);
        c := Centre(rs[h]);
        AssertTrue(Format('%d/%d: hit %d', [PPIs[i], Zooms[j], Ord(h)]), FRich.HandleAt(c.X, c.Y, got));
        AssertEquals(Format('%d/%d: the handle %d', [PPIs[i], Zooms[j], Ord(h)]), Ord(h), Ord(got));
        AssertTrue(Format('%d/%d: its corner pixel %d', [PPIs[i], Zooms[j], Ord(h)]),
          FRich.HandleAt(rs[h].Right - 1, rs[h].Bottom - 1, got) and (got = h));
      end;
      // the box between the corner handles' centres: the picture at that PPI and zoom
      w := Centre(rs[rhTopRight]).X - Centre(rs[rhTopLeft]).X + 1;
      hgt := Centre(rs[rhBottomLeft]).Y - Centre(rs[rhTopLeft]).Y + 1;
      AssertEquals(Format('%d/%d: the box''s width', [PPIs[i], Zooms[j]]),
        TyRichTwipsToPx(1500, PPIs[i], Zooms[j] / 100), w);
      AssertEquals(Format('%d/%d: the box''s height', [PPIs[i], Zooms[j]]),
        TyRichTwipsToPx(750, PPIs[i], Zooms[j] / 100), hgt);
      // the middles in the middle
      AssertEquals('the top middle between the corners', (Centre(rs[rhTopLeft]).X +
        Centre(rs[rhTopRight]).X) div 2, Centre(rs[rhTop]).X);
      AssertEquals('the left middle between the corners', (Centre(rs[rhTopLeft]).Y +
        Centre(rs[rhBottomLeft]).Y) div 2, Centre(rs[rhLeft]).Y);
      // just outside a handle (left of the top left one, beside the box's middle): none
      AssertFalse(Format('%d/%d: left of the top left handle', [PPIs[i], Zooms[j]]),
        FRich.HandleAt(rs[rhTopLeft].Left - 1, rs[rhTopLeft].Top, got));
      AssertFalse(Format('%d/%d: inside the box, off the handles', [PPIs[i], Zooms[j]]),
        FRich.HandleAt(Centre(rs[rhTopLeft]).X + Sides[i], Centre(rs[rhLeft]).Y - Sides[i], got));
      // the cursors: the diagonals as the handles lie, the sides straight
      c := Centre(rs[rhTopLeft]);
      AssertEquals('top left: NW-SE', Ord(crSizeNWSE), Ord(FRich.CursorFor(c.X, c.Y)));
      c := Centre(rs[rhBottomRight]);
      AssertEquals('bottom right: NW-SE', Ord(crSizeNWSE), Ord(FRich.CursorFor(c.X, c.Y)));
      c := Centre(rs[rhTopRight]);
      AssertEquals('top right: NE-SW', Ord(crSizeNESW), Ord(FRich.CursorFor(c.X, c.Y)));
      c := Centre(rs[rhBottomLeft]);
      AssertEquals('bottom left: NE-SW', Ord(crSizeNESW), Ord(FRich.CursorFor(c.X, c.Y)));
      c := Centre(rs[rhTop]);
      AssertEquals('top: N-S', Ord(crSizeNS), Ord(FRich.CursorFor(c.X, c.Y)));
      c := Centre(rs[rhLeft]);
      AssertEquals('left: W-E', Ord(crSizeWE), Ord(FRich.CursorFor(c.X, c.Y)));
      // a handle's side left of the box: the text before it, when the text reaches that far
      c := Point(Centre(rs[rhLeft]).X - Sides[i] - 1, Centre(rs[rhLeft]).Y);
      if c.X >= FRich.Area.Left then
        AssertEquals('the text beside: the I-beam', Ord(crIBeam), Ord(FRich.CursorFor(c.X, c.Y)));
    end;
end;

{ The handles are drawn after every block - over the line above the picture's and the text
  beside it -, filled with TyRichEditObject's background and outlined in its border-color (the
  control's StyleOverride tokens reach both), and change no layout. }
procedure TTyRichObjectsTest.TestHandlesAreDrawnOverWhatIsBesideThePicture;
var
  p: TTyRichPos;
  rs: TTyRichHandleRects;
  st: TTyRichPaintStyle;
  c: TPoint;
  line0: TRect;
  hBefore, hAfter: Integer;
begin
  FRich.StyleOverride := 'background: #FFFFFF; --surface: #10E010; --accent: #E01010;';
  p := PictureDoc(100, 50);
  st := FRich.Style;
  AssertTrue('the fill from --surface', SamePx(BGRA($10, $E0, $10, 255), st.ObjectHandleFill));
  AssertTrue('the outline from --accent', SamePx(BGRA($E0, $10, $10, 255), st.ObjectFrame));
  AssertTrue('handles', FRich.Handles(rs));
  // the top middle handle reaches above the picture's line, into the first paragraph's
  line0 := FRich.ParagraphRect(0);
  AssertTrue('the handle reaches into the line above', rs[rhTop].Top < line0.Bottom);
  c := Centre(rs[rhTop]);
  AssertTrue('its middle is filled', SamePx(st.ObjectHandleFill, FRich.Surf.GetPixel(c.X, c.Y)));
  AssertTrue('its top row is outlined (in the line above)',
    SamePx(st.ObjectFrame, FRich.Surf.GetPixel(c.X, rs[rhTop].Top)));
  // the left middle handle reaches over the text before the picture
  c := Centre(rs[rhLeft]);
  AssertTrue('left of the box: the handle''s outline over the text',
    SamePx(st.ObjectFrame, FRich.Surf.GetPixel(rs[rhLeft].Left, c.Y)));
  // no layout change: the paragraph is as tall with or without the selection
  hBefore := FRich.ParagraphRect(1).Bottom - FRich.ParagraphRect(1).Top;
  FRich.SelStart := 0;
  PaintAll;
  AssertTrue('nothing selected: no handles', not FRich.Handles(rs));
  hAfter := FRich.ParagraphRect(1).Bottom - FRich.ParagraphRect(1).Top;
  AssertEquals('the line keeps its height', hBefore, hAfter);
  c := Centre(rs[rhTop]);
  AssertFalse('the handle went from the line above',
    SamePx(st.ObjectHandleFill, FRich.Surf.GetPixel(c.X, c.Y)));
end;

{ A press on a handle begins a resize and selects nothing - also on a handle's part that lies
  over the text beside the picture; the document does not change before the release (no
  layout per move); the release lays out the picture's paragraph alone. }
procedure TTyRichObjectsTest.TestAPressOnAHandleResizesAndNeverSelects;
var
  p: TTyRichPos;
  rs: TTyRichHandleRects;
  c: TPoint;
  r: TRect;
  w, h, laid: Integer;
  steps: Int64;
begin
  p := PictureDoc(100, 50);
  AssertTrue('handles', FRich.Handles(rs));
  // the left handle's leftmost column: over the 'b' before the picture
  c := Point(rs[rhLeft].Left, Centre(rs[rhLeft]).Y);
  AssertTrue('the point is left of the picture''s box', c.X < Centre(rs[rhLeft]).X);
  FRich.PressAt(c.X, c.Y);
  AssertTrue('a resize', FRich.InResize);
  AssertEquals('the selection stays: start', p, FRich.SelStart);
  AssertEquals('the selection stays: length', 1, FRich.SelLength);
  steps := FRich.Document.UndoDepth;
  FRich.ResetCounts;
  FRich.MoveWith(c.X - 30, c.Y + 7, []);
  AssertTrue('an outline', FRich.Outline(r, w, h));
  AssertEquals('its width: 30 more', 1500 + 450, w);
  AssertEquals('its height: the left middle leaves it', 750, h);
  AssertEquals('the outline''s left moved', Centre(rs[rhLeft]).X - 30, r.Left);
  AssertEquals('its right stays', Centre(rs[rhRight]).X + 1, r.Right);
  FRich.MoveWith(c.X - 40, c.Y, []);
  PaintAll;
  AssertEquals('no step before the release', steps, FRich.Document.UndoDepth);
  AssertEquals('nothing laid out per move', 0, FRich.LaidParas);
  AssertEquals('the picture as it was', 1500, PictureAt(p).WidthTwips);
  FRich.ResetCounts;
  FRich.ReleaseWith(c.X - 40, c.Y, []);
  AssertEquals('the release: one step', steps + 1, FRich.Document.UndoDepth);
  AssertEquals('the new width', 1500 + 600, PictureAt(p).WidthTwips);
  PaintAll;
  AssertTrue('the paragraph laid out again', FRich.LaidParas >= 1);
  AssertTrue('only around the picture', FRich.LaidParas <= 2);
end;

{ An object that cannot be resized shows its frame and no handles; so does a picture of a
  read-only or disabled control, and of a document that takes no edit; a press there selects
  as before. }
procedure TTyRichObjectsTest.TestNoHandlesWhereNothingCanBeResized;
var
  p: TTyRichPos;
  rs: TTyRichHandleRects;
  got: TTyRichHandle;
  c: TPoint;
  st: TTyRichPaintStyle;
  box: TRect;
begin
  p := PictureDoc(100, 50);
  AssertTrue('editable: handles', FRich.Handles(rs));
  c := Centre(rs[rhTopLeft]);
  FRich.ReadOnly := True;
  PaintAll;
  AssertFalse('read-only: no handles', FRich.Handles(rs));
  AssertFalse('read-only: no hit', FRich.HandleAt(c.X, c.Y, got));
  // the frame stays: a selected picture's box is framed
  st := FRich.Style;
  box := FRich.PositionRect(p);
  AssertTrue('read-only: the frame', SamePx(st.ObjectFrame, FRich.Surf.GetPixel(box.Left,
    Centre(rs[rhLeft]).Y)));
  AssertFalse('read-only: no fill at the handle', SamePx(st.ObjectHandleFill,
    FRich.Surf.GetPixel(c.X - 2, c.Y - 2)));
  FRich.PressAt(c.X + 4, c.Y + 4);
  FRich.ReleaseAt(c.X + 4, c.Y + 4);
  AssertFalse('read-only: a press resizes nothing', FRich.InResize);
  FRich.ReadOnly := False;
  SelectAt(p);
  PaintAll;
  AssertTrue('editable again: handles', FRich.Handles(rs));
  FRich.Enabled := False;
  AssertFalse('disabled: no handles', FRich.Handles(rs));
  FRich.Enabled := True;
  // an object of RTF kept as it was read: a frame-less block, never handles
  FRich.Lines.Text := 'xy';
  AssertTrue('an opaque object', FRich.Document.Execute(TTyRichInsertObject.Create(1,
    TTyRichOpaque.Create('{' + BS + 'object x}', 'OBJ'))));
  SelectAt(1);
  PaintAll;
  AssertFalse('it cannot be resized', FRich.Document.ObjectAt(1).CanResize);
  AssertFalse('no handles for it', FRich.Handles(rs));
  AssertTrue('its command is refused', not TTyRichResizeObject.Create(1, 500, 500).CanExecute(
    FRich.Document));
end;

{ Two pictures side by side: the handles of the selected one reach over the other; a press
  there resizes the selected one and does not select the other. }
procedure TTyRichObjectsTest.TestTwoPicturesSideBySide;
var
  p: TTyRichPos;
  pic2: TTyRichPicture;
  rs: TTyRichHandleRects;
  c: TPoint;
  w0: Integer;
begin
  p := PictureDoc(100, 50);
  pic2 := TTyRichPicture.Create(rpfPng, PngOf(80, 50), 1200, 750);
  AssertTrue('a second picture right after it', FRich.Document.Execute(
    TTyRichInsertObject.Create(p + 1, pic2)));
  FRich.Document.ClearUndo;
  SelectAt(p);
  PaintAll;
  AssertTrue('handles', FRich.Handles(rs));
  // the right middle handle's rightmost column lies over the second picture
  c := Point(rs[rhRight].Right - 1, Centre(rs[rhRight]).Y);
  AssertTrue('over the second picture', FRich.Document.ObjectAt(p + 1) = pic2);
  w0 := PictureAt(p).WidthTwips;
  FRich.PressAt(c.X, c.Y);
  AssertTrue('a resize of the first', FRich.InResize);
  AssertEquals('the first stays selected', p, FRich.SelStart);
  FRich.MoveWith(c.X - 20, c.Y, []);
  FRich.ReleaseWith(c.X - 20, c.Y, []);
  AssertEquals('the first is narrower', w0 - 300, PictureAt(p).WidthTwips);
  AssertEquals('the second as it was', 1200, PictureAt(p + 1).WidthTwips);
  // the second one selected: its own handles
  SelectAt(p + 1);
  PaintAll;
  AssertTrue('the second''s handles', FRich.Handles(rs));
  Drag(rhLeft, -10, 0);
  AssertEquals('the second wider', 1200 + 150, PictureAt(p + 1).WidthTwips);
end;

{ In a table cell the width is held to the cell's room; a picture that is the whole content
  is resized and undone as anywhere. }
procedure TTyRichObjectsTest.TestAPictureInACellAndAsTheOnlyContent;
var
  rtf: RawByteString;
  p, k: TTyRichPos;
  pic: TTyRichPicture;
  r: TRect;
  w, h: Integer;
  rs: TTyRichHandleRects;
  c: TPoint;
begin
  // a 2-cell row, the first cell 2000 twips wide with a 1200 x 600 picture
  rtf := Head + BS + 'trowd' + BS + 'trgaph100' + BS + 'cellx2000' + BS + 'cellx4000' + BS +
    'pard' + BS + 'intbl{' + BS + 'pict' + BS + 'pngblip' + BS + 'picwgoal1200' + BS +
    'pichgoal600 ' + HexOf(PngOf(80, 40)) + '}' + BS + 'cell b' + BS + 'cell' + BS + 'row' +
    #13#10 + BS + 'pard after' + BS + 'par}';
  LoadRtf(rtf);
  p := -1;
  for k := 0 to FRich.Document.Text.Length - 1 do
    if FRich.Document.ObjectAt(k) is TTyRichPicture then p := k;
  AssertTrue('a picture in the cell', (p >= 0) and (FRich.Document.CellAt(
    FRich.Document.Text.ParaOfPos(p)) <> nil));
  SelectAt(p);
  PaintAll;
  AssertTrue('handles in the cell', FRich.Handles(rs));
  c := Centre(rs[rhRight]);
  FRich.PressAt(c.X, c.Y);
  FRich.MoveWith(c.X + 300, c.Y, [ssShift]);
  AssertTrue('the outline', FRich.Outline(r, w, h));
  // the cell's room: its width less the half gaps
  AssertEquals('held to the cell', 2000 - 200, w);
  FRich.ReleaseWith(c.X + 300, c.Y, [ssShift]);
  pic := PictureAt(p);
  AssertEquals('the picture as wide as the cell lets it', 1800, pic.WidthTwips);
  AssertTrue('still in its cell', FRich.Document.CellAt(FRich.Document.Text.ParaOfPos(p)) <> nil);
  FRich.Undo;
  AssertEquals('undone', 1200, PictureAt(p).WidthTwips);
  // a picture alone
  FreeAndNil(FRich);
  FRich := NewProbe;
  FRich.Lines.Text := '';
  AssertTrue('the only content', FRich.Document.Execute(TTyRichInsertObject.Create(0,
    TTyRichPicture.Create(rpfPng, PngOf(60, 30), 900, 450))));
  FRich.Document.ClearUndo;
  SelectAt(0);
  PaintAll;
  Drag(rhBottom, 0, 20);
  AssertEquals('alone: taller', 450 + 300, PictureAt(0).HeightTwips);
  FRich.Undo;
  AssertEquals('alone: undone', 450, PictureAt(0).HeightTwips);
  FRich.Redo;
  AssertEquals('alone: redone', 750, PictureAt(0).HeightTwips);
end;

{ Showing the handles repaints the line's band and the handles' place - never the whole view,
  never the caret's path; a move of the outline repaints its old and new rectangle; the
  release repaints the picture's paragraph and the handles. }
procedure TTyRichObjectsTest.TestTheHandlesRepaintOnlyTheirPlace;
var
  p: TTyRichPos;
  rs: TTyRichHandleRects;
  i: Integer;
  tw, u, r1: TRect;
  c: TPoint;
  w, h: Integer;

  function Union: TRect;
  var
    k: Integer;
  begin
    Result := Rect(0, 0, 0, 0);
    for k := 0 to High(FRich.Invalidated) do
      if IsRectEmpty(Result) then Result := FRich.Invalidated[k]
      else UnionRect(Result, Result, FRich.Invalidated[k]);
  end;

begin
  p := PictureDoc(100, 50);
  FRich.SelStart := 0;
  PaintAll;
  FRich.ResetCounts;
  tw := FRich.TextWindow;
  SelectAt(p);
  AssertTrue('handles', FRich.Handles(rs));
  AssertTrue('something repainted', Length(FRich.Invalidated) > 0);
  u := Union;
  // the handles' place (they reach a half handle past the box) and the lines
  AssertTrue('the top handle is in it', u.Top <= rs[rhTop].Top);
  AssertTrue('the bottom handle is in it', u.Bottom >= rs[rhBottom].Bottom);
  AssertTrue('not the whole view', (u.Bottom - u.Top) < (tw.Bottom - tw.Top) div 2);
  for i := 0 to High(FRich.Invalidated) do
    AssertTrue('nothing far from the picture', FRich.Invalidated[i].Top >= rs[rhTop].Top - 1);
  PaintAll;
  // the outline: its old and its new place
  c := Centre(rs[rhBottomRight]);
  FRich.PressAt(c.X, c.Y);
  FRich.MoveWith(c.X + 10, c.Y + 5, []);
  PaintAll;
  FRich.ResetCounts;
  AssertTrue('an outline', FRich.Outline(r1, w, h));
  FRich.MoveWith(c.X + 20, c.Y + 10, []);
  AssertEquals('a move: the old outline and the new', 2, Length(FRich.Invalidated));
  u := Union;
  AssertTrue('within the new outline''s reach', u.Right <= c.X + 22);
  FRich.ResetCounts;
  FRich.MoveWith(c.X + 20, c.Y + 10, []);
  AssertEquals('the same place: nothing', 0, Length(FRich.Invalidated));
  FRich.ReleaseWith(c.X + 20, c.Y + 10, []);
  PaintAll;
  u := Union;
  AssertTrue('the release: something repainted', Length(FRich.Invalidated) > 0);
  AssertTrue('the release: below the first line', u.Top >= FRich.ParagraphRect(0).Top);
end;

{ The outline of every handle, with and without Shift: which sides move, the opposite side
  still, the shape kept on a corner without Shift (the larger relative change decides). }
procedure TTyRichObjectsTest.TestTheOutlineOfEveryHandle;
type
  TCase = record
    H: TTyRichHandle;
    DX, DY: Integer;
    W, Hh, WS, HS: Integer;   // twips: no Shift, Shift
  end;
const
  // a 100 x 50 pixel picture (1500 x 750 twips), 15 twips a pixel
  Cases: array[0..7] of TCase = (
    (H: rhTopLeft; DX: -20; DY: -5; W: 1800; Hh: 900; WS: 1800; HS: 825),
    (H: rhTop; DX: 13; DY: -10; W: 1500; Hh: 900; WS: 1500; HS: 900),
    (H: rhTopRight; DX: 10; DY: -20; W: 2100; Hh: 1050; WS: 1650; HS: 1050),
    (H: rhRight; DX: 25; DY: 7; W: 1875; Hh: 750; WS: 1875; HS: 750),
    (H: rhBottomRight; DX: -30; DY: -5; W: 1050; Hh: 525; WS: 1050; HS: 675),
    (H: rhBottom; DX: -9; DY: 12; W: 1500; Hh: 930; WS: 1500; HS: 930),
    (H: rhBottomLeft; DX: 10; DY: 15; W: 1950; Hh: 975; WS: 1350; HS: 975),
    (H: rhLeft; DX: 18; DY: -3; W: 1230; Hh: 750; WS: 1230; HS: 750));
var
  i, s, w, h: Integer;
  rs: TTyRichHandleRects;
  c: TPoint;
  r: TRect;
  box: TRect;
  shift: TShiftState;
  ew, eh: Integer;
begin
  PictureDoc(100, 50);
  AssertTrue('handles', FRich.Handles(rs));
  box := Rect(Centre(rs[rhTopLeft]).X, Centre(rs[rhTopLeft]).Y, Centre(rs[rhBottomRight]).X + 1,
    Centre(rs[rhBottomRight]).Y + 1);
  for i := 0 to High(Cases) do
    for s := 0 to 1 do
    begin
      if s = 1 then shift := [ssShift] else shift := [];
      c := Centre(rs[Cases[i].H]);
      FRich.PressAt(c.X, c.Y, shift);
      FRich.MoveWith(c.X + Cases[i].DX, c.Y + Cases[i].DY, shift);
      AssertTrue(Format('%d/%d: an outline', [i, s]), FRich.Outline(r, w, h));
      if s = 0 then
      begin
        ew := Cases[i].W;
        eh := Cases[i].Hh;
      end
      else
      begin
        ew := Cases[i].WS;
        eh := Cases[i].HS;
      end;
      AssertEquals(Format('%d/%d: the width', [i, s]), ew, w);
      AssertEquals(Format('%d/%d: the height', [i, s]), eh, h);
      AssertEquals(Format('%d/%d: the outline''s width', [i, s]), ew div 15, r.Right - r.Left);
      AssertEquals(Format('%d/%d: the outline''s height', [i, s]), eh div 15, r.Bottom - r.Top);
      // the side opposite the handle stays where it was
      if Cases[i].H in [rhTopLeft, rhLeft, rhBottomLeft] then
        AssertEquals(Format('%d/%d: the right side stays', [i, s]), box.Right, r.Right)
      else
        AssertEquals(Format('%d/%d: the left side stays', [i, s]), box.Left, r.Left);
      if Cases[i].H in [rhTopLeft, rhTop, rhTopRight] then
        AssertEquals(Format('%d/%d: the bottom stays', [i, s]), box.Bottom, r.Bottom)
      else
        AssertEquals(Format('%d/%d: the top stays', [i, s]), box.Top, r.Top);
      // Esc: the next case starts from the same picture
      FRich.Press(VK_ESCAPE, []);
      AssertFalse(Format('%d/%d: Esc ended it', [i, s]), FRich.InResize);
      FRich.ReleaseWith(c.X, c.Y, shift);
      AssertEquals(Format('%d/%d: nothing done', [i, s]), 0, FRich.Document.UndoDepth);
    end;
end;

{ The bounds: no side under CRichObjectMinTwips, the width at most the room (the window's
  text width here), the height at most 22 inches; a shape kept is kept inside them. }
procedure TTyRichObjectsTest.TestTheBoundsOfAResize;
var
  w, h, room: Integer;
  rs: TTyRichHandleRects;
  c: TPoint;
  r: TRect;
begin
  // the routine itself
  TyRichResizedSize(rhRight, 1500, 750, -5000, 0, False, 300, 9000, 31680, w, h);
  AssertEquals('at the least', 300, w);
  AssertEquals('the other side stays', 750, h);
  TyRichResizedSize(rhBottom, 1500, 750, 0, 100000, False, 300, 9000, 31680, w, h);
  AssertEquals('22 inches at most', 31680, h);
  TyRichResizedSize(rhRight, 1500, 750, 100000, 0, False, 300, 9000, 31680, w, h);
  AssertEquals('the room at most', 9000, w);
  // the shape kept within the bounds: the width's bound holds both
  TyRichResizedSize(rhBottomRight, 1500, 750, 100000, 0, True, 300, 9000, 31680, w, h);
  AssertEquals('kept shape: the width at its bound', 9000, w);
  AssertEquals('kept shape: the height in the shape', 4500, h);
  TyRichResizedSize(rhTopLeft, 1500, 750, 100000, 100000, True, 300, 9000, 31680, w, h);
  AssertEquals('kept shape: the least on the shorter side', 300, h);
  AssertEquals('kept shape: the width in the shape', 600, w);
  // through the control: the room is the text width at the window
  PictureDoc(100, 50);
  AssertTrue('handles', FRich.Handles(rs));
  room := (FRich.TextWindow.Right - FRich.TextWindow.Left);
  c := Centre(rs[rhRight]);
  FRich.PressAt(c.X, c.Y);
  FRich.MoveWith(c.X + 2000, c.Y, []);
  AssertTrue('an outline', FRich.Outline(r, w, h));
  AssertTrue('no wider than the text', r.Right - r.Left <= room);
  FRich.MoveWith(c.X - 2000, c.Y, []);
  AssertTrue('an outline', FRich.Outline(r, w, h));
  AssertEquals('at least the least', CRichObjectMinTwips, w);
  FRich.ReleaseWith(c.X - 2000, c.Y, []);
  AssertEquals('released at the least', CRichObjectMinTwips, PictureAt(FRich.SelStart).WidthTwips);
end;

{ Esc, the capture lost, a change of the document, a new content and a view moved during a
  drag: the outline goes and nothing changes; a release where the drag began: nothing either. }
procedure TTyRichObjectsTest.TestEscALostCaptureAndAChangeEndADragWithNothingDone;
var
  p: TTyRichPos;
  rs: TTyRichHandleRects;
  c: TPoint;
  r: TRect;
  w, h, kind: Integer;
  old: TTyRichPicture;
begin
  for kind := 0 to 4 do
  begin
    FreeAndNil(FRich);
    FRich := NewProbe;
    p := PictureDoc(100, 50);
    old := PictureAt(p);
    AssertTrue('handles', FRich.Handles(rs));
    c := Centre(rs[rhBottomRight]);
    FRich.PressAt(c.X, c.Y);
    FRich.MoveWith(c.X + 30, c.Y + 30, []);
    AssertTrue(IntToStr(kind) + ': an outline', FRich.Outline(r, w, h));
    case kind of
      0: FRich.Press(VK_ESCAPE, []);
      1: FRich.LoseCapture;
      2: FRich.Document.Execute(TTyRichInsertText.Create(0, 'x'));
      3: FRich.ScrollViewBy(1);
    else
      FRich.Lines.Text := 'another content';
    end;
    AssertFalse(IntToStr(kind) + ': the drag ended', FRich.InResize);
    AssertFalse(IntToStr(kind) + ': no outline', FRich.Outline(r, w, h));
    FRich.ReleaseWith(c.X + 30, c.Y + 30, []);
    if kind < 4 then
    begin
      AssertTrue(IntToStr(kind) + ': the picture as it was', FRich.Document.ObjectAt(
        FRich.Document.Text.ParaStart(1) + 2) = old);
      AssertEquals(IntToStr(kind) + ': its width', 1500, old.WidthTwips);
    end;
    AssertEquals(IntToStr(kind) + ': no resize step', Ord(kind = 2), FRich.Document.UndoDepth);
  end;
  // a release at the size it had
  FreeAndNil(FRich);
  FRich := NewProbe;
  p := PictureDoc(100, 50);
  AssertTrue('handles', FRich.Handles(rs));
  c := Centre(rs[rhTopRight]);
  FRich.PressAt(c.X, c.Y);
  FRich.MoveWith(c.X + 40, c.Y, []);
  FRich.MoveWith(c.X, c.Y, []);
  FRich.ReleaseWith(c.X, c.Y, []);
  AssertEquals('the size it had: no step', 0, FRich.Document.UndoDepth);
  AssertFalse('not Modified', FRich.Modified);
end;

{ OnObjectResize is asked once, with the object and the size; it may change the size or say
  no. }
procedure TTyRichObjectsTest.TestOnObjectResizeConstrainsOrVetoes;
var
  p: TTyRichPos;
  old: TTyRichPicture;
begin
  p := PictureDoc(100, 50);
  old := PictureAt(p);
  FRich.OnObjectResize := @OnResize;
  FResizeAllow := False;
  Drag(rhRight, 20, 0);
  AssertEquals('asked once', 1, FResizeCalls);
  AssertTrue('of the object', FResizeSeen = old);
  AssertEquals('with the width', 1800, FResizeSeenW);
  AssertEquals('and the height', 750, FResizeSeenH);
  AssertEquals('vetoed: no step', 0, FRich.Document.UndoDepth);
  AssertTrue('vetoed: the old object', PictureAt(p) = old);
  FResizeAllow := True;
  FResizeSetW := 1000;
  FResizeSetH := 400;
  PaintAll;
  Drag(rhRight, 20, 0);
  AssertEquals('asked again', 2, FResizeCalls);
  AssertEquals('constrained: the width', 1000, PictureAt(p).WidthTwips);
  AssertEquals('constrained: the height', 400, PictureAt(p).HeightTwips);
  // a size the handler makes the old one: nothing
  FResizeSetW := 1000;
  FResizeSetH := 400;
  PaintAll;
  Drag(rhRight, 20, 0);
  AssertEquals('back to its size: no step', 1, FRich.Document.UndoDepth);
end;

{ The command in the document: refused without an object, for an object that cannot be
  resized, for a size not positive and where the row cannot change; the same size changes
  nothing; undo and redo give the very objects back. }
procedure TTyRichObjectsTest.TestTheResizeCommandInTheDocument;
var
  d: TTyRichDocument;
  pic, nw: TTyRichPicture;
  cmd: TTyRichResizeObject;
begin
  d := TTyRichDocument.Create;
  try
    AssertTrue('text', d.Execute(TTyRichInsertText.Create(0, 'ab')));
    pic := TTyRichPicture.Create(rpfJpeg, ImageBytes(20, 10, BGRA(1, 2, 3, 255), ifJpeg), 300, 150);
    AssertTrue('a picture', d.Execute(TTyRichInsertObject.Create(1, pic)));
    AssertTrue('an opaque', d.Execute(TTyRichInsertObject.Create(0, TTyRichOpaque.Create('{x}'))));
    d.ClearUndo;
    d.Modified := False;
    // the picture is at 2 now, the opaque at 0
    AssertFalse('no object at 1', d.Execute(TTyRichResizeObject.Create(1, 400, 200)));
    AssertFalse('an opaque cannot', d.Execute(TTyRichResizeObject.Create(0, 400, 200)));
    AssertFalse('a width of 0', d.Execute(TTyRichResizeObject.Create(2, 0, 200)));
    AssertFalse('a height below 0', d.Execute(TTyRichResizeObject.Create(2, 400, -1)));
    AssertFalse('outside the text', d.Execute(TTyRichResizeObject.Create(9, 400, 200)));
    AssertTrue('the same size: runs', d.Execute(TTyRichResizeObject.Create(2, 300, 150)));
    AssertEquals('the same size: no step', 0, d.UndoDepth);
    AssertTrue('the same size: the same object', d.ObjectAt(2) = pic);
    AssertFalse('the same size: not Modified', d.Modified);
    cmd := TTyRichResizeObject.Create(2, 600, 300);
    AssertTrue('resized', d.Execute(cmd));
    nw := TTyRichPicture(d.ObjectAt(2));
    AssertTrue('the command''s object', cmd.NewObject = nw);
    AssertEquals('the new width', 600, nw.WidthTwips);
    AssertTrue('a JPEG still', nw.PictureFormat = rpfJpeg);
    AssertTrue('the very bytes', Pointer(nw.Data) = Pointer(pic.Data));
    AssertEquals('the text the same', 'b', d.Text.GetText(3, 1));
    d.Undo;
    AssertTrue('undo: the object itself', d.ObjectAt(2) = pic);
    d.Redo;
    AssertTrue('redo: the new one itself', d.ObjectAt(2) = nw);
  finally
    d.Free;
  end;
end;

{ A 20 MB picture resized 20 times under the default MaxUndoBytes: every step is still there,
  and the history counts the picture's bytes once - two objects that share bytes count them
  once too. }
procedure TTyRichObjectsTest.TestAResizeKeepsNoSecondCopyInTheHistory;
var
  d: TTyRichDocument;
  data: TBytes;
  pic: TTyRichPicture;
  i: Integer;
  one, after: Int64;
begin
  data := nil;
  SetLength(data, 20 * 1024 * 1024);
  FillChar(data[0], Length(data), 7);
  d := TTyRichDocument.Create;
  try
    AssertTrue('text', d.Execute(TTyRichInsertText.Create(0, 'ab')));
    d.ClearUndo;
    pic := TTyRichPicture.Create(rpfPng, data, 1500, 750);
    AssertTrue('the picture', d.Execute(TTyRichInsertObject.Create(1, pic)));
    one := d.HistoryBytes;
    AssertTrue('the step counts the picture', one >= Length(data));
    for i := 1 to 20 do
      AssertTrue(Format('resize %d', [i]), d.Execute(TTyRichResizeObject.Create(1, 1500 + 15 * i,
        750)));
    AssertEquals('every step kept', 21, d.UndoDepth);
    after := d.HistoryBytes;
    AssertTrue(Format('the bytes once: %d against %d', [after, one]), after < one + 64 * 1024);
    AssertTrue('under the limit', after <= d.MaxUndoBytes);
    // undone all the way, then let go: back to nothing
    for i := 1 to 21 do d.Undo;
    AssertEquals('all undone', 1500, 1500);
    d.ClearUndo;
    AssertEquals('nothing held', 0, d.HistoryBytes);
    // two pictures that share their bytes, each inserted as a step of its own
    pic := TTyRichPicture.Create(rpfPng, data, 100, 100);
    AssertTrue('one', d.Execute(TTyRichInsertObject.Create(0, pic)));
    one := d.HistoryBytes;
    AssertTrue('another of the same bytes', d.Execute(TTyRichInsertObject.Create(0,
      TTyRichPicture.Create(rpfPng, data, 200, 200))));
    AssertTrue('the shared bytes once', d.HistoryBytes < one + 64 * 1024);
    d.Undo;
    d.ClearUndo;
    AssertEquals('let go: nothing', 0, d.HistoryBytes);
  finally
    d.Free;
  end;
end;

{ The resized picture shows the pixels the old one had decoded: no decode, no empty box at the
  release's paint; a smaller size is made from the reduced copy kept, with no decode. }
procedure TTyRichObjectsTest.TestAResizedPictureShowsItsDecodedPixels;
var
  p: TTyRichPos;
  decodes, standIns: Int64;
  rs: TTyRichHandleRects;
  c: TPoint;
  st: TTyRichPaintStyle;
begin
  p := PictureDoc(100, 50);
  // decoded for its box by the background work
  while FRich.Step do;
  PaintAll;
  decodes := FRich.Layouter.PictureDecodes;
  AssertTrue('decoded once', decodes >= 1);
  // larger: drawn from the full image kept (shown at its own size), no decode
  Drag(rhBottomRight, 40, 20);
  PaintAll;
  AssertEquals('no decode for the resize', decodes, FRich.Layouter.PictureDecodes);
  // what is shown in the new box is the picture's red, not the empty box
  st := FRich.Style;
  AssertTrue('handles', FRich.Handles(rs));
  c := Point(Centre(rs[rhBottomRight]).X - 20, Centre(rs[rhBottomRight]).Y - 20);
  AssertFalse('no empty box', SamePx(st.PlaceholderFill, FRich.Surf.GetPixel(c.X, c.Y)));
  AssertEquals('the picture''s red', 200, FRich.Surf.GetPixel(c.X, c.Y).red);
  while FRich.Step do;
  PaintAll;
  AssertEquals('an enlargement: drawn from the full image, no decode', decodes,
    FRich.Layouter.PictureDecodes);
  // smaller: from the reduced copy, no decode
  FreeAndNil(FRich);
  FRich := NewProbe;
  p := PictureDoc(200, 100);
  FRich.Zoom := 50;
  SelectAt(p);
  PaintAll;
  while FRich.Step do;
  PaintAll;
  decodes := FRich.Layouter.PictureDecodes;
  standIns := FRich.Layouter.PictureStandIns;
  Drag(rhBottomRight, -20, -10);
  PaintAll;
  // the reduced copy kept stands in at once (no empty box), then is reduced again
  AssertTrue('smaller: the old pixels stood in', FRich.Layouter.PictureStandIns > standIns);
  AssertTrue('smaller: waiting for its size', FRich.Pending > 0);
  st := FRich.Style;
  AssertTrue('handles', FRich.Handles(rs));
  c := Point(Centre(rs[rhBottomRight]).X - 10, Centre(rs[rhBottomRight]).Y - 10);
  AssertFalse('smaller: no empty box', SamePx(st.PlaceholderFill, FRich.Surf.GetPixel(c.X, c.Y)));
  while FRich.Step do;
  PaintAll;
  AssertEquals('smaller: no decode', decodes, FRich.Layouter.PictureDecodes);
  AssertTrue('smaller: the picture', PictureAt(p).WidthTwips < 3000);
end;

{ A file's PNG and JPEG resized: written from the model at the new size (the file's group is
  not kept), with its bytes; another program (Windows' rich edit) still finds the picture. }
procedure TTyRichObjectsTest.TestAResizedFilePictureIsWrittenAtItsNewSize;
var
  file0, saved: TBytes;
  jpg: TBytes;
  rtf, s: RawByteString;
  p, k: TTyRichPos;
  pic: TTyRichPicture;
  d: TTyRichDocument;
  {$IFDEF WINDOWS}
  text: RawByteString;
  {$ENDIF}
begin
  jpg := ImageBytes(40, 20, BGRA(10, 200, 10, 255), ifJpeg);
  rtf := Head + BS + 'pard' + BS + 'f0 x{' + BS + 'pict{' + BS + '*' + BS + 'picprop}' + BS +
    'jpegblip' + BS + 'picscalex50' + BS + 'picwgoal1200' + BS + 'pichgoal600 ' + HexOf(jpg) +
    '}y' + BS + 'par}';
  file0 := RawBytes(rtf);
  LoadRtf(rtf);
  p := 1;
  pic := PictureAt(p);
  AssertTrue('a JPEG', pic.PictureFormat = rpfJpeg);
  AssertTrue('its bytes', SameBytes(pic.Data, jpg));
  AssertTrue('its group kept', pic.RawRtf <> '');
  SelectAt(p);
  PaintAll;
  Drag(rhBottomRight, 10, 0);
  pic := PictureAt(p);
  saved := SaveRtf;
  s := StrOfBytes(saved);
  AssertTrue('written from the model: no \picprop', Pos(BS + 'picprop', s) = 0);
  AssertTrue('no \picscalex', Pos(BS + 'picscalex', s) = 0);
  AssertTrue('the new width', Pos(BS + 'picwgoal' + IntToStr(pic.WidthTwips), s) > 0);
  AssertTrue('the new height', Pos(BS + 'pichgoal' + IntToStr(pic.HeightTwips), s) > 0);
  AssertTrue('the JPEG''s bytes', Pos(HexOf(jpg), StringReplace(StringReplace(s, #13, '',
    [rfReplaceAll]), #10, '', [rfReplaceAll])) > 0);
  d := LoadDoc(saved);
  try
    d.BeginRead;
    try
      AssertTrue('read back: a picture', d.ObjectAt(1) is TTyRichPicture);
      AssertTrue('read back: the bytes', SameBytes(TTyRichPicture(d.ObjectAt(1)).Data, jpg));
      AssertEquals('read back: the width', pic.WidthTwips, TTyRichPicture(d.ObjectAt(1)).WidthTwips);
    finally
      d.EndRead;
    end;
  finally
    d.Free;
  end;
  {$IFDEF WINDOWS}
  if RichEditText(saved, text) then
    AssertTrue('Windows'' rich edit finds the picture',
      Pos(RawByteString(#$EF#$BF#$BC), text) > 0);
  {$ENDIF}
  FRich.Undo;
  AssertTrue('undone: the file', SameBytes(file0, SaveRtf));
  // a PNG of the re-zh sample, resized
  FreeAndNil(FRich);
  FRich := NewProbe;
  file0 := FixtureFile('re-zh-picture.rtf');
  LoadRtf(StrOfBytes(file0));
  p := -1;
  for k := 0 to FRich.Document.Text.Length - 1 do
    if (p < 0) and (FRich.Document.ObjectAt(k) is TTyRichPicture) then p := k;
  AssertTrue('a PNG there', (p >= 0) and (PictureAt(p).PictureFormat = rpfPng));
  pic := PictureAt(p);
  SelectAt(p);
  PaintAll;
  Drag(rhRight, 12, 0);
  AssertTrue('the PNG''s bytes', Pointer(PictureAt(p).Data) = Pointer(pic.Data));
  saved := SaveRtf;
  {$IFDEF WINDOWS}
  if RichEditText(saved, text) then
    AssertTrue('Windows'' rich edit finds the PNG', Pos(RawByteString(#$EF#$BF#$BC), text) > 0);
  {$ENDIF}
  FRich.Undo;
  AssertTrue('undone: the file', SameBytes(file0, SaveRtf));
end;

{ Every door and format: a PNG or JPEG file goes in with its own bytes; a BMP, a GIF and an
  icon are decoded and kept as PNG; a stream as a file; a TGraphic - PNG as PNG,
  JPEG as JPEG, a bitmap as PNG. The picture replaces the selection in one step named Insert
  picture, the caret behind it; its size its pixels at 96 dpi, scaled to the room. }
procedure TTyRichObjectsTest.TestInsertFromEachDoorAndFormat;
var
  png, jpg, bmp: TBytes;
  pic: TTyRichPicture;
  st: TBytesStream;
  g: TPortableNetworkGraphic;
  j: TJPEGImage;
  b: TBitmap;
  w: Integer;
begin
  png := PngOf(40, 20);
  jpg := ImageBytes(40, 20, BGRA(10, 20, 200, 255), ifJpeg);
  bmp := ImageBytes(30, 10, BGRA(10, 20, 200, 255), ifBmp);
  FRich.Lines.Text := 'abcd';
  FRich.Document.ClearUndo;
  // a PNG file over the selection 'bc'
  FRich.SelStart := 1;
  FRich.SelLength := 2;
  AssertTrue('a PNG file', FRich.InsertPictureFromFile(TempFile('a.png', png)));
  AssertEquals('the selection went', 'a' + TyRichObjectChar + 'd', FRich.Document.Text.GetText(0, 3));
  pic := PictureAt(1);
  AssertTrue('PNG', pic.PictureFormat = rpfPng);
  AssertTrue('its own bytes', SameBytes(pic.Data, png));
  AssertEquals('40 pixels at 96 dpi', 600, pic.WidthTwips);
  AssertEquals('20 pixels', 300, pic.HeightTwips);
  AssertEquals('one step', 1, FRich.Document.UndoDepth);
  AssertEquals('its name', rsRichUndoInsertPicture, FRich.Document.UndoDescription);
  AssertEquals('the caret behind it', 2, FRich.CaretIndex);
  AssertEquals('nothing selected', 0, FRich.SelLength);
  FRich.Undo;
  AssertEquals('undo: the text back', 'abcd', FRich.Document.Text.GetText(0, 4));
  AssertEquals('undo: the selection back', 1, FRich.SelStart);
  AssertEquals('undo: its length', 2, FRich.SelLength);
  // a JPEG file
  FRich.SelStart := 0;
  AssertTrue('a JPEG file', FRich.InsertPictureFromFile(TempFile('b.jpg', jpg)));
  pic := PictureAt(0);
  AssertTrue('JPEG', pic.PictureFormat = rpfJpeg);
  AssertTrue('the file''s bytes', SameBytes(pic.Data, jpg));
  // a BMP, a GIF, an icon: PNG
  FRich.SelStart := 0;
  AssertTrue('a BMP file', FRich.InsertPictureFromFile(TempFile('c.bmp', bmp)));
  AssertTrue('BMP kept as PNG', PictureAt(0).PictureFormat = rpfPng);
  AssertEquals('BMP: its width', 450, PictureAt(0).WidthTwips);
  FRich.SelStart := 0;
  AssertTrue('a GIF file', FRich.InsertPictureFromFile(TempFile('d.gif', GifBytes)));
  AssertTrue('GIF kept as PNG', PictureAt(0).PictureFormat = rpfPng);
  AssertEquals('GIF: one pixel', 15, PictureAt(0).WidthTwips);
  FRich.SelStart := 0;
  AssertTrue('an icon file', FRich.InsertPictureFromFile(TempFile('e.ico', IcoBytes)));
  AssertTrue('icon kept as PNG', PictureAt(0).PictureFormat = rpfPng);
  AssertEquals('icon: 2 pixels', 30, PictureAt(0).WidthTwips);
  // a stream
  st := TBytesStream.Create(jpg);
  try
    FRich.SelStart := 0;
    AssertTrue('a stream', FRich.InsertPictureFromStream(st));
  finally
    st.Free;
  end;
  AssertTrue('stream: the JPEG''s bytes', SameBytes(PictureAt(0).Data, jpg));
  // TGraphic: PNG, JPEG, a bitmap
  g := TPortableNetworkGraphic.Create;
  j := TJPEGImage.Create;
  b := TBitmap.Create;
  try
    st := TBytesStream.Create(png);
    try
      g.LoadFromStream(st);
    finally
      st.Free;
    end;
    FRich.SelStart := 0;
    AssertTrue('a TPortableNetworkGraphic', FRich.InsertPicture(g));
    AssertTrue('as PNG', PictureAt(0).PictureFormat = rpfPng);
    AssertEquals('its width', 600, PictureAt(0).WidthTwips);
    st := TBytesStream.Create(jpg);
    try
      j.LoadFromStream(st);
    finally
      st.Free;
    end;
    FRich.SelStart := 0;
    AssertTrue('a TJPEGImage', FRich.InsertPicture(j));
    AssertTrue('as JPEG', PictureAt(0).PictureFormat = rpfJpeg);
    b.SetSize(12, 6);
    b.Canvas.Brush.Color := clRed;
    b.Canvas.FillRect(0, 0, 12, 6);
    FRich.SelStart := 0;
    AssertTrue('a TBitmap', FRich.InsertPicture(b));
    AssertTrue('as PNG', PictureAt(0).PictureFormat = rpfPng);
    AssertEquals('12 pixels', 180, PictureAt(0).WidthTwips);
  finally
    b.Free;
    j.Free;
    g.Free;
  end;
  // wider than the room: scaled down, the shape kept
  FRich.SelStart := 0;
  AssertTrue('a wide PNG', FRich.InsertPictureFromFile(TempFile('w.png', PngOf(2000, 100))));
  w := PictureAt(0).WidthTwips;
  AssertTrue('held to the room', w < 2000 * 15);
  AssertEquals('the shape kept', Round(w / 20), PictureAt(0).HeightTwips);
  AssertEquals('one step a picture (the first undone)', 9, FRich.Document.UndoDepth);
end;

{ What is refused, and how it is told: a missing file (the system's words), a metafile by its
  name and by its bytes, bytes that are no picture, nil and an empty graphic, a picture over
  the bounds (the paste's reason), a plain text document; ReadOnly and disabled silently; a
  place a paste could not go; CanInsertPicture answers as the inserts. }
procedure TTyRichObjectsTest.TestInsertRefusals;
var
  big: TBytes;
  b: TBitmap;
  missing: string;
begin
  FRich.Lines.Text := 'abcd';
  FRich.Document.ClearUndo;
  AssertTrue('Can: yes', FRich.CanInsertPicture);
  missing := TempDir + 'none.png';
  AssertFalse('a missing file: not done', FRich.InsertPictureFromFile(missing));
  AssertEquals('a missing file: told once', 1, FRich.Refused);
  AssertTrue('a missing file: the reason', Pos(Format(rsRichEditRefusedPictureFile, ['']),
    FRich.LastReason) = 1);
  AssertTrue('a missing file: the system''s words name it', Pos('none.png', FRich.LastReason) > 0);
  FRich.Refused := 0;
  CheckRefused('a .wmf', FRich.InsertPictureFromFile(TempFile('m.wmf', PngOf(4, 4))),
    rsRichEditRefusedMetafile);
  CheckRefused('an .emf', FRich.InsertPictureFromFile(TempFile('m.emf', PngOf(4, 4))),
    rsRichEditRefusedMetafile);
  CheckRefused('a WMF named .png', FRich.InsertPictureFromFile(TempFile('mw.png', WmfDrawing)),
    rsRichEditRefusedMetafile);
  CheckRefused('an EMF named .dat', FRich.InsertPictureFromFile(TempFile('me.dat', EmfHeader)),
    rsRichEditRefusedMetafile);
  CheckRefused('no picture', FRich.InsertPictureFromFile(TempFile('t.png', RawBytes('hello'))),
    rsRichEditRefusedNoPicture);
  CheckRefused('a PNG that does not decode', FRich.InsertPictureFromFile(TempFile('h.png',
    Copy(PngOf(20, 20), 0, 40))), rsRichEditRefusedNoPicture);
  CheckRefused('nil', FRich.InsertPicture(nil), rsRichEditRefusedNoPicture);
  b := TBitmap.Create;
  try
    CheckRefused('an empty graphic', FRich.InsertPicture(b), rsRichEditRefusedNoPicture);
  finally
    b.Free;
  end;
  CheckRefused('no stream', FRich.InsertPictureFromStream(nil), rsRichEditRefusedNoPicture);
  // a PNG whose header promises more pixels than a picture may have
  big := PngOf(4, 4);
  big[16] := $00; big[17] := $01; big[18] := $00; big[19] := $00;
  big[20] := $00; big[21] := $01; big[22] := $00; big[23] := $00;
  CheckRefused('over the bounds', FRich.InsertPictureFromFile(TempFile('big.png', big)),
    rsRichEditRefusedPicture);
  AssertEquals('nothing went in', 'abcd', FRich.Document.Text.GetText(0, 4));
  AssertEquals('no step', 0, FRich.Document.UndoDepth);
  // read-only and disabled: nothing, nothing told
  FRich.ReadOnly := True;
  CheckSilent('read-only', FRich.InsertPictureFromFile(TempFile('r.png', PngOf(4, 4))));
  AssertFalse('Can: read-only', FRich.CanInsertPicture);
  FRich.ReadOnly := False;
  FRich.Enabled := False;
  CheckSilent('disabled', FRich.InsertPicture(nil));
  AssertFalse('Can: disabled', FRich.CanInsertPicture);
  FRich.Enabled := True;
  // a plain text document
  FRich.PlainText := True;
  CheckRefused('plain text', FRich.InsertPictureFromFile(TempFile('p.png', PngOf(4, 4))),
    rsRichEditRefusedPlainPicture);
  AssertFalse('Can: plain text', FRich.CanInsertPicture);
  FRich.PlainText := False;
  // inside the document's update: nothing
  FRich.Document.BeginUpdate;
  try
    CheckSilent('in an update', FRich.InsertPictureFromFile(TempFile('u.png', PngOf(4, 4))));
    AssertFalse('Can: in an update', FRich.CanInsertPicture);
  finally
    FRich.Document.EndUpdate;
  end;
  AssertTrue('Can: yes again', FRich.CanInsertPicture);
  AssertTrue('and it goes in', FRich.InsertPictureFromFile(TempFile('ok.png', PngOf(4, 4))));
end;

initialization
  RegisterTest(TTyRichObjectsTest);
end.
