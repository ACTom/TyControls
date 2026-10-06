unit test.db.image;
{$mode objfpc}{$H+}

{ The data-aware image (issue #34, plan Task 7): TTyDBImage through the shared C1-C8 run of
  test.db.edits plus what only a picture in a blob has -- the bytes in the field, LCL's extension
  header both ways, the two application hooks, NULL, AutoDisplay.

  An image takes no focus and no keys, so its user is the program acting for the person in
  front of it: an Open or Paste command loads the picture, a Clear command clears it. That is
  the path every test here takes (Picture.LoadFromStream, Picture.Clear); it is a change of the
  picture outside a load, which is exactly what the control has to take for an edit. Escape (C5)
  does not exist for it; the base run checks that the change simply stays.

  A picture is compared pixel for pixel (Signature: the size and every pixel's RGB), never by
  its bytes, so a test cannot pass on a blob nobody can read back. }

interface

uses
  Classes, SysUtils, Controls, Graphics, DB, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes, FPImage, FPWritePNG,
  dbfixtures, test.db.edits, tyControls.DB.Image;

type
  TDBImageTest = class(TDBControlTestBase)
  protected
    FReads, FWrites: Integer;
    FWrittenExt: string;
    { What OnDBImageRead names the format as, after reading the 4-byte 'TYIM' header. }
    FReadAs: string;
    function NewControl: TControl; override;
    function FieldName: string; override;
    function Shown: string; override;
    function ExpectedShown(ARow: Integer): string; override;
    function OtherFieldName: string; override;
    function OtherShown: string; override;
    function EscapeRestores: Boolean; override;
    { The program, for the user: an Open command loads a picture. }
    procedure UserEdit; override;
    { ...and a Clear command clears it. }
    procedure UserEditUnguarded; override;
    procedure Commit; override;
    procedure AssertFieldHoldsEdit; override;
    function Img: TTyDBImage;
    procedure ReadOwnHeader(Sender: TObject; S: TStream; var GraphExt: string);
    procedure WriteOwnHeader(Sender: TObject; S: TStream; GraphExt: string);
    function BlobBytes: TBytes;
    procedure PutBlob(const ABytes: TBytes);
    { What the field holds, decoded the way a reader that knows LCL's header would. }
    function FieldSignature: string;
  published
    procedure TestPngWrittenReadsBackPixelForPixel;
    procedure TestBlobWithLclsHeaderIsRead;
    procedure TestHeaderNamingTheWrongFormatFallsBackToTheData;
    procedure TestWriteHeaderWritesLclsHeaderOrNone;
    procedure TestEachWriteHeaderSettingReadsTheOther;
    procedure TestOnDBImageWriteWritesTheHeader;
    procedure TestOnDBImageReadNamesTheFormat;
    procedure TestOnDBImageReadUnknownFormatFallsBackToTheData;
    procedure TestClearedPictureWritesNull;
    procedure TestAutoDisplayOffDoesNotLoad;
    procedure TestBlobThatIsNoPictureShowsNothing;
    procedure TestNonBlobFieldTakesNoPicture;
    procedure TestTransparentSetFromCodeIsNotAnEdit;
  end;

{ A PNG of AW x AH whose pixels all differ: (x, y) is RGB(ASeed + 40x, 30y, 255 - ASeed). }
function PatternPng(AW, AH: Integer; ASeed: Byte): TBytes;
{ The signature of that PNG, as Signature gives it. }
function PatternSignature(AW, AH: Integer; ASeed: Byte): string;
{ Size and every pixel's RGB of a picture; '' when it has none. }
function Signature(APicture: TPicture): string;

implementation

function Hex3(R, G, B: Byte): string;
begin
  Result := Format(' %.2x%.2x%.2x', [R, G, B]);
end;

function PatternPng(AW, AH: Integer; ASeed: Byte): TBytes;
var
  img: TFPMemoryImage;
  w: TFPWriterPNG;
  ms: TMemoryStream;
  x, y: Integer;
  c: TFPColor;
begin
  Result := nil;
  img := TFPMemoryImage.Create(AW, AH);
  w := TFPWriterPNG.Create;
  ms := TMemoryStream.Create;
  try
    for y := 0 to AH - 1 do
      for x := 0 to AW - 1 do
      begin
        c.Red := Byte(ASeed + 40 * x) * $101;
        c.Green := Byte(30 * y) * $101;
        c.Blue := Byte(255 - ASeed) * $101;
        c.Alpha := alphaOpaque;
        img.Colors[x, y] := c;
      end;
    img.SaveToStream(ms, w);
    SetLength(Result, ms.Size);
    Move(ms.Memory^, Result[0], ms.Size);
  finally
    ms.Free;
    w.Free;
    img.Free;
  end;
end;

function PatternSignature(AW, AH: Integer; ASeed: Byte): string;
var
  x, y: Integer;
begin
  Result := Format('%dx%d', [AW, AH]);
  for y := 0 to AH - 1 do
    for x := 0 to AW - 1 do
      Result := Result + Hex3(Byte(ASeed + 40 * x), Byte(30 * y), Byte(255 - ASeed));
end;

function UniformSignature(AW, AH: Integer; R, G, B: Byte): string;
var
  i: Integer;
begin
  Result := Format('%dx%d', [AW, AH]);
  for i := 1 to AW * AH do Result := Result + Hex3(R, G, B);
end;

function Signature(APicture: TPicture): string;
var
  bmp: TBitmap;
  bgra: TBGRABitmap;
  x, y: Integer;
  c: TBGRAPixel;
begin
  if (APicture.Graphic = nil) or APicture.Graphic.Empty then Exit('');
  { Through copies: reading Picture.Bitmap of a PNG would replace the picture's graphic. }
  bmp := TBitmap.Create;
  try
    bmp.Assign(APicture.Graphic);
    bgra := TBGRABitmap.Create(bmp);
    try
      Result := Format('%dx%d', [bgra.Width, bgra.Height]);
      for y := 0 to bgra.Height - 1 do
        for x := 0 to bgra.Width - 1 do
        begin
          c := bgra.GetPixel(x, y);
          Result := Result + Hex3(c.red, c.green, c.blue);
        end;
    finally
      bgra.Free;
    end;
  finally
    bmp.Free;
  end;
end;

function BytesStream(const ABytes: TBytes): TMemoryStream;
begin
  Result := TMemoryStream.Create;
  if Length(ABytes) > 0 then Result.WriteBuffer(ABytes[0], Length(ABytes));
  Result.Position := 0;
end;

function StreamBytes(AStream: TMemoryStream): TBytes;
begin
  Result := nil;
  SetLength(Result, AStream.Size);
  if AStream.Size > 0 then Move(AStream.Memory^, Result[0], AStream.Size);
end;

{ LCL's header in front of a graphic: TStream.WriteAnsiString(AExt), then the data. }
function WithLclHeader(const AExt: string; const AData: TBytes): TBytes;
var
  ms: TMemoryStream;
begin
  ms := TMemoryStream.Create;
  try
    ms.WriteAnsiString(AExt);
    ms.WriteBuffer(AData[0], Length(AData));
    Result := StreamBytes(ms);
  finally
    ms.Free;
  end;
end;

function StartsWith(const ABytes: TBytes; const APrefix: array of Byte): Boolean;
var
  i: Integer;
begin
  Result := Length(ABytes) >= Length(APrefix);
  if Result then
    for i := 0 to High(APrefix) do
      if ABytes[i] <> APrefix[i] then Exit(False);
end;

const
  CPngMagic: array[0..3] of Byte = ($89, Ord('P'), Ord('N'), Ord('G'));
  CLclPngHeader: array[0..10] of Byte = (3, 0, 0, 0, Ord('p'), Ord('n'), Ord('g'),
    $89, Ord('P'), Ord('N'), Ord('G'));

{ ===================================================================== TDBImageTest ======= }

function TDBImageTest.NewControl: TControl;
begin
  Result := TTyDBImage.Create(FForm);
end;

function TDBImageTest.Img: TTyDBImage;
begin
  Result := TTyDBImage(FCtl);
end;

function TDBImageTest.FieldName: string;
begin
  Result := 'Pic';
end;

function TDBImageTest.Shown: string;
begin
  Result := Signature(Img.Picture);
end;

function TDBImageTest.ExpectedShown(ARow: Integer): string;
begin
  case ARow of
    1: Result := UniformSignature(2, 2, $FF, 0, 0);   // dbfixtures: row 1, 2x2 red
    2: Result := UniformSignature(3, 1, 0, 0, $FF);   // row 2, 3x1 blue
  else
    Result := '';                                     // NULL: no picture (D5)
  end;
end;

{ A memo is a blob too; its text is no picture. Before the switch the control shows row 1's
  red square, so an unchanged control cannot pass for one that loaded the new field. }
function TDBImageTest.OtherFieldName: string;
begin
  Result := 'Note';
end;

function TDBImageTest.OtherShown: string;
begin
  Result := '';
end;

function TDBImageTest.EscapeRestores: Boolean;
begin
  Result := False;
end;

procedure TDBImageTest.UserEdit;
var
  ms: TMemoryStream;
begin
  ms := BytesStream(PatternPng(4, 3, 7));
  try
    Img.Picture.LoadFromStream(ms);
  finally
    ms.Free;
  end;
end;

procedure TDBImageTest.UserEditUnguarded;
begin
  Img.Picture.Clear;
end;

procedure TDBImageTest.Commit;
begin
  { Nothing: the picture is in the record as soon as it changes, and C4 checks just that. }
end;

procedure TDBImageTest.AssertFieldHoldsEdit;
begin
  AssertEquals('the field holds the picture', PatternSignature(4, 3, 7), FieldSignature);
end;

procedure TDBImageTest.ReadOwnHeader(Sender: TObject; S: TStream; var GraphExt: string);
var
  tag: array[0..3] of Char;
begin
  Inc(FReads);
  AssertSame('the image asks', FCtl, Sender);
  S.ReadBuffer(tag, SizeOf(tag));
  AssertEquals('the application''s own header', 'TYIM', string(tag));
  GraphExt := FReadAs;
end;

procedure TDBImageTest.WriteOwnHeader(Sender: TObject; S: TStream; GraphExt: string);
const
  CTag: array[0..3] of Char = 'TYIM';
begin
  Inc(FWrites);
  AssertSame('the image asks', FCtl, Sender);
  FWrittenExt := GraphExt;
  S.WriteBuffer(CTag, SizeOf(CTag));
end;

function TDBImageTest.BlobBytes: TBytes;
var
  ms: TMemoryStream;
begin
  ms := TMemoryStream.Create;
  try
    TBlobField(BoundField).SaveToStream(ms);
    Result := StreamBytes(ms);
  finally
    ms.Free;
  end;
end;

procedure TDBImageTest.PutBlob(const ABytes: TBytes);
var
  ms: TMemoryStream;
begin
  ms := BytesStream(ABytes);
  try
    FFix.DS.Edit;
    TBlobField(BoundField).LoadFromStream(ms);
    FFix.DS.Post;
  finally
    ms.Free;
  end;
end;

function TDBImageTest.FieldSignature: string;
var
  ms: TMemoryStream;
  pic: TPicture;
  len: LongInt;
begin
  if BoundField.IsNull then Exit('');
  ms := BytesStream(BlobBytes);
  pic := TPicture.Create;
  try
    len := 0;
    ms.ReadBuffer(len, SizeOf(len));
    if (len >= 1) and (len <= 16) then
      ms.Position := SizeOf(len) + len   // LCL's header: skip it
    else
      ms.Position := 0;
    pic.LoadFromStream(ms);
    Result := Signature(pic);
  finally
    pic.Free;
    ms.Free;
  end;
end;

{ Written, posted, scrolled away and back: the picture read from the field is the one put in,
  every pixel of it. }
procedure TDBImageTest.TestPngWrittenReadsBackPixelForPixel;
begin
  Bind('Pic');
  UserEdit;
  FFix.DS.Post;
  GoRow(2);
  AssertEquals('row 2', ExpectedShown(2), Shown);
  GoRow(1);
  AssertEquals('read back', PatternSignature(4, 3, 7), Shown);
  AssertBrowsing('reading it back');
end;

{ A blob as LCL's TDBImage writes it, built here by hand in LCL's format. }
procedure TDBImageTest.TestBlobWithLclsHeaderIsRead;
begin
  PutBlob(WithLclHeader('png', PatternPng(3, 2, 50)));
  Bind('Pic');
  AssertEquals('LCL''s blob', PatternSignature(3, 2, 50), Shown);
  AssertBrowsing('reading a headed blob');
end;

{ A header that names a format the data is not in (here 'bmp' over a PNG) is not the last
  word: the data says what it is. }
procedure TDBImageTest.TestHeaderNamingTheWrongFormatFallsBackToTheData;
begin
  PutBlob(WithLclHeader('bmp', PatternPng(2, 2, 200)));
  Bind('Pic');
  AssertEquals('told from the data', PatternSignature(2, 2, 200), Shown);
  AssertBrowsing('reading a mislabelled blob');
end;

procedure TDBImageTest.TestWriteHeaderWritesLclsHeaderOrNone;
begin
  Bind('Pic');
  AssertTrue('WriteHeader is on by default, as in LCL', Img.WriteHeader);
  UserEdit;
  AssertTrue('LCL''s header: length 3, "png", then the PNG itself',
    StartsWith(BlobBytes, CLclPngHeader));
  Img.WriteHeader := False;
  UserEdit;
  AssertTrue('no header: the PNG from its first byte', StartsWith(BlobBytes, CPngMagic));
end;

{ A blob written under either setting reads under the other: reading never depends on it. }
procedure TDBImageTest.TestEachWriteHeaderSettingReadsTheOther;
begin
  Bind('Pic');
  Img.WriteHeader := True;
  UserEdit;
  FFix.DS.Post;
  Img.WriteHeader := False;
  GoRow(2);
  GoRow(1);
  AssertEquals('headed, read without writing headers', PatternSignature(4, 3, 7), Shown);
  FFix.DS.Edit;
  Img.Picture.Clear;   // a different blob next, so the read below cannot be the old one
  FFix.DS.Post;
  AssertTrue('cleared', BoundField.IsNull);
  UserEdit;
  FFix.DS.Post;
  AssertTrue('written bare', StartsWith(BlobBytes, CPngMagic));
  Img.WriteHeader := True;
  GoRow(2);
  GoRow(1);
  AssertEquals('bare, read while writing headers', PatternSignature(4, 3, 7), Shown);
end;

procedure TDBImageTest.TestOnDBImageWriteWritesTheHeader;
var
  b: TBytes;
begin
  Bind('Pic');
  Img.OnDBImageWrite := @WriteOwnHeader;
  UserEdit;
  AssertEquals('called once', 1, FWrites);
  AssertEquals('told the format', 'png', FWrittenExt);
  b := BlobBytes;
  AssertTrue('its header, then the PNG (no LCL header besides)', StartsWith(b,
    [Ord('T'), Ord('Y'), Ord('I'), Ord('M'), $89, Ord('P'), Ord('N'), Ord('G')]));
end;

procedure TDBImageTest.TestOnDBImageReadNamesTheFormat;
var
  data: TBytes;
  b: TBytes;
begin
  data := PatternPng(2, 3, 90);
  SetLength(b, 4 + Length(data));
  b[0] := Ord('T'); b[1] := Ord('Y'); b[2] := Ord('I'); b[3] := Ord('M');
  Move(data[0], b[4], Length(data));
  PutBlob(b);
  FReadAs := 'png';
  Img.OnDBImageRead := @ReadOwnHeader;
  Bind('Pic');
  AssertEquals('called', 1, FReads);
  AssertEquals('the picture after the application''s header', PatternSignature(2, 3, 90), Shown);
end;

{ LCL's rule: a name no graphic class answers to leaves the format to the data after the
  application's header. }
procedure TDBImageTest.TestOnDBImageReadUnknownFormatFallsBackToTheData;
var
  data: TBytes;
  b: TBytes;
begin
  data := PatternPng(2, 2, 120);
  SetLength(b, 4 + Length(data));
  b[0] := Ord('T'); b[1] := Ord('Y'); b[2] := Ord('I'); b[3] := Ord('M');
  Move(data[0], b[4], Length(data));
  PutBlob(b);
  FReadAs := 'no-such-format';
  Img.OnDBImageRead := @ReadOwnHeader;
  Bind('Pic');
  AssertEquals('called', 1, FReads);
  AssertEquals('told from the data', PatternSignature(2, 2, 120), Shown);
end;

{ D5: the program clearing the picture writes NULL, at once. }
procedure TDBImageTest.TestClearedPictureWritesNull;
begin
  Bind('Pic');
  Img.Picture.Clear;
  AssertTrue('an edit', FFix.DS.State = dsEdit);
  AssertTrue('NULL already in the record', BoundField.IsNull);
  FFix.DS.Post;
  AssertTrue('NULL posted', BoundField.IsNull);
  AssertEquals('nothing shown', '', Shown);
end;

procedure TDBImageTest.TestAutoDisplayOffDoesNotLoad;
begin
  Img.AutoDisplay := False;
  Bind('Pic');
  AssertEquals('bound, not loaded', '', Shown);
  AssertFalse('PictureLoaded', Img.PictureLoaded);
  GoRow(2);
  AssertEquals('another row, not loaded either', '', Shown);
  Img.LoadPicture;
  AssertTrue('loaded on request', Img.PictureLoaded);
  AssertEquals('LoadPicture reads the row', ExpectedShown(2), Shown);
  AssertBrowsing('loading on request');
  GoRow(1);
  AssertEquals('the next row waits again', '', Shown);
  Img.AutoDisplay := True;
  AssertEquals('AutoDisplay on loads it', ExpectedShown(1), Shown);
  AssertBrowsing('AutoDisplay switched on');
end;

{ Bytes that are no picture: the memo's text, and a four-byte "length" of a million in front of
  three letters -- LCL's ReadAnsiString would believe it. Nothing shows, nothing raises, and the
  record is not touched. }
procedure TDBImageTest.TestBlobThatIsNoPictureShowsNothing;
const
  CBogus: array[0..6] of Byte = ($40, $42, $0F, $00, Ord('p'), Ord('n'), Ord('g'));
var
  b: TBytes;
begin
  b := nil;
  SetLength(b, Length(CBogus));
  Move(CBogus[0], b[0], Length(CBogus));
  PutBlob(b);
  Bind('Pic');
  AssertEquals('a bogus length', '', Shown);
  AssertBrowsing('reading a bogus blob');
  Img.DataField := 'Note';
  AssertEquals('a memo''s text', '', Shown);
  AssertBrowsing('reading a memo');
end;

{ A picture has nowhere to go in a text field: the program's picture is refused and the field
  shown again (nothing, since a text field holds no picture). }
procedure TDBImageTest.TestNonBlobFieldTakesNoPicture;
begin
  Bind('Name');
  AssertEquals('a text field shows no picture', '', Shown);
  UserEdit;
  AssertEquals('refused', '', Shown);
  AssertBrowsing('a picture for a text field');
  AssertEquals('the field untouched', CFixNames[1], FFix.DS.FieldByName('Name').AsString);
end;

{ Transparent re-masks the graphic, and the graphic reports that as a change of the picture:
  the program's doing, not an edit. The picture must be the field's afterwards, and the dataset
  never in dsEdit. }
procedure TDBImageTest.TestTransparentSetFromCodeIsNotAnEdit;
begin
  Bind('Pic');
  Img.Transparent := True;
  AssertTrue('set', Img.Transparent);
  AssertBrowsing('Transparent on');
  Img.Transparent := False;
  AssertBrowsing('Transparent off');
  AssertEquals('still the field''s picture', ExpectedShown(1), Shown);
end;

initialization
  RegisterTest(TDBImageTest);
end.
