unit test.richedit.objevents;

{ TTyRichEdit's objects under the mouse: OnObjectClick on the release of a click on one,
  OnObjectDblClick on the second press before the default, ObjectAtPoint, and a picture
  handed over as an image at its own size (AssignTo a TPicture or a TBitmap) or as its file's
  bytes (SaveImageToStream).

  Headless, on the probe of test.richedit.fieldctl. No window, no clipboard, no dialog. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, fpcunit, testregistry, Controls, Graphics, LCLType, Forms,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.RichEdit.Text, tyControls.RichEdit.Model,
  tyControls.RichEdit, test.richedit.fieldctl;

type
  TTyRichObjEventsTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TFieldProbe;
    FClicks, FDbls, FLinks: Integer;
    FObj: TTyRichObject;
    FObjPos: TTyRichPos;
    FButton: TMouseButton;
    FShift: TShiftState;
    FPoint: TPoint;
    FBounds: TRect;
    FInPicture: TPoint;
    FHandle: Boolean;
    FDo: Integer;            // 0 nothing, 1 free the control, 2 load another document
    FPicW, FPicH: Integer;   // what AssignTo gave, inside the handler
    FAssign: Boolean;
    procedure Click(Sender: TObject; const AClick: TTyRichObjectClick; var AHandled: Boolean);
    procedure Dbl(Sender: TObject; const AClick: TTyRichObjectClick; var AHandled: Boolean);
    procedure Note(const AClick: TTyRichObjectClick);
    procedure LinkClicked(Sender: TObject; const AURL: string; AButton: TMouseButton);
    procedure Act;
    procedure Load(const S: RawByteString);
    function Centre(APos: TTyRichPos): TPoint;
    procedure DoubleClickAt(const P: TPoint);
    procedure ClickAt(const P: TPoint; AButton: TMouseButton = mbLeft);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDoubleClickOnAPictureGivesThePicture;
    procedure TestHandledStopsTheDefault;
    procedure TestObjectAtPointForPicturesAndKeptBlocks;
    procedure TestTheHandlerMayFreeTheControl;
    procedure TestNoEventOnPlainText;
    procedure TestAPictureInALinkIsTheLinksClick;
    procedure TestAClickWithNoSelectionAndOtherButtons;
    procedure TestTheClickTellsThePointAndTheBox;
    procedure TestAReleaseOfAnotherButtonIsNoClick;
  end;

implementation

const
  BS = #92;

function Rtf(const S: RawByteString): RawByteString;
var
  i: Integer;
begin
  Result := S;
  UniqueString(Result);
  for i := 1 to Length(Result) do
    if Result[i] = '|' then Result[i] := BS;
  SetCodePage(Result, CP_NONE, False);
end;

function BytesOf(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[0], Length(S));
end;

function HexOf(const B: TBytes): RawByteString;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(B) do Result := Result + LowerCase(IntToHex(B[i], 2));
end;

function PngBytes(AW, AH: Integer): TBytes;
var
  b: TBGRABitmap;
  st: TBytesStream;
begin
  b := TBGRABitmap.Create(AW, AH, BGRA(200, 30, 30, 255));
  st := TBytesStream.Create;
  try
    b.SaveToStreamAsPng(st);
    Result := Copy(st.Bytes, 0, st.Size);
  finally
    st.Free;
    b.Free;
  end;
end;

function JpegBytes(AW, AH: Integer): TBytes;
var
  bmp: TBitmap;
  j: TJPEGImage;
  st: TBytesStream;
begin
  bmp := TBitmap.Create;
  j := TJPEGImage.Create;
  st := TBytesStream.Create;
  try
    bmp.SetSize(AW, AH);
    bmp.Canvas.Brush.Color := clGreen;
    bmp.Canvas.FillRect(0, 0, AW, AH);
    j.Assign(bmp);
    j.SaveToStream(st);
    Result := Copy(st.Bytes, 0, st.Size);
  finally
    st.Free;
    j.Free;
    bmp.Free;
  end;
end;

procedure Put16(var B: TBytes; AValue: Integer);
var
  n: Integer;
begin
  n := Length(B);
  SetLength(B, n + 2);
  B[n] := Byte(AValue);
  B[n + 1] := Byte(AValue shr 8);
end;

procedure Put32(var B: TBytes; AValue: Cardinal);
begin
  Put16(B, Integer(AValue and $FFFF));
  Put16(B, Integer(AValue shr 16));
end;

procedure PutBytes(var B: TBytes; const AMore: TBytes);
var
  n: Integer;
begin
  n := Length(B);
  SetLength(B, n + Length(AMore));
  if Length(AMore) > 0 then Move(AMore[0], B[n], Length(AMore));
end;

{ A 2 x 2 bitmap of 24 bits: BITMAPINFOHEADER and two rows of 8 bytes. }
function SmallDib: TBytes;
var
  i: Integer;
begin
  Result := nil;
  Put32(Result, 40);
  Put32(Result, 2);
  Put32(Result, 2);
  Put16(Result, 1);
  Put16(Result, 24);
  for i := 1 to 6 do Put32(Result, 0);
  for i := 1 to 8 do Put16(Result, $7F7F);
end;

procedure PutRecord(var B: TBytes; AFunction: Integer; const AParams: TBytes);
begin
  Put32(B, Cardinal(3 + Length(AParams) div 2));
  Put16(B, AFunction);
  PutBytes(B, AParams);
end;

{ A metafile that draws the 2 x 2 bitmap (META_STRETCHDIB); with ALine a line too. }
function WmfBytes(ALine: Boolean): TBytes;
var
  p, two: TBytes;
  i: Integer;
begin
  Result := nil;
  Put16(Result, 1);
  Put16(Result, 9);
  Put16(Result, $0300);
  Put32(Result, 0);
  Put16(Result, 0);
  Put32(Result, 0);
  Put16(Result, 0);
  two := nil;
  Put16(two, 2);
  Put16(two, 2);
  PutRecord(Result, $020C, two);
  if ALine then
  begin
    two := nil;
    Put16(two, 1);
    Put16(two, 1);
    PutRecord(Result, $0213, two);
  end;
  p := nil;
  Put32(p, $00CC0020);
  Put16(p, 0);
  Put16(p, 2);
  Put16(p, 2);
  Put16(p, 0);
  Put16(p, 0);
  for i := 1 to 4 do Put16(p, 2);
  PutBytes(p, SmallDib);
  PutRecord(Result, $0F43, p);
  PutRecord(Result, 0, nil);
end;

{ "ab", the picture shown 900 x 600 twips (60 x 40 pixels), "cd": the picture at 2. }
function PictDoc(const AKind: RawByteString; const ABytes: TBytes): RawByteString;
begin
  Result := Rtf('{|rtf1|ansi|deff0{|fonttbl{|f0 Arial;}}|pard|f0 ab{|pict|' + AKind +
    '|picw2|pich2|picwgoal900|pichgoal600 ' + HexOf(ABytes) + '}cd|par}');
end;

{ ---- the suite ---- }

procedure TTyRichObjEventsTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FRich := TFieldProbe.Create(nil);
  FRich.Controller := FCtl;
  FRich.Font.PixelsPerInch := 96;
  FRich.SetBounds(0, 0, 600, 300);
  FRich.OnObjectClick := @Click;
  FRich.OnObjectDblClick := @Dbl;
  FRich.OnLinkClick := @LinkClicked;
  FClicks := 0;
  FDbls := 0;
  FLinks := 0;
  FObj := nil;
  FObjPos := -1;
  FHandle := False;
  FDo := 0;
  FAssign := False;
end;

procedure TTyRichObjEventsTest.TearDown;
begin
  FreeAndNil(FRich);
  FreeAndNil(FCtl);
end;

procedure TTyRichObjEventsTest.Act;
var
  p: TPicture;
begin
  if FAssign then
  begin
    p := TPicture.Create;
    try
      p.Assign(FObj);
      FPicW := p.Width;
      FPicH := p.Height;
    finally
      p.Free;
    end;
  end;
  case FDo of
    1: FreeAndNil(FRich);
    2: Load(Rtf('{|rtf1|ansi|deff0{|fonttbl{|f0 Arial;}}|pard|f0 another|par}'));
  end;
end;

procedure TTyRichObjEventsTest.Note(const AClick: TTyRichObjectClick);
begin
  FObj := AClick.RichObject;
  FObjPos := AClick.Pos;
  FButton := AClick.Button;
  FShift := AClick.Shift;
  FPoint := AClick.Point;
  FBounds := AClick.Bounds;
  FInPicture := AClick.PointInPicture(60, 40);
end;

procedure TTyRichObjEventsTest.Click(Sender: TObject; const AClick: TTyRichObjectClick;
  var AHandled: Boolean);
begin
  Inc(FClicks);
  Note(AClick);
  AHandled := FHandle;
  Act;
end;

procedure TTyRichObjEventsTest.Dbl(Sender: TObject; const AClick: TTyRichObjectClick;
  var AHandled: Boolean);
begin
  Inc(FDbls);
  Note(AClick);
  AHandled := FHandle;
  Act;
end;

procedure TTyRichObjEventsTest.LinkClicked(Sender: TObject; const AURL: string;
  AButton: TMouseButton);
begin
  Inc(FLinks);
end;

procedure TTyRichObjEventsTest.Load(const S: RawByteString);
var
  st: TBytesStream;
begin
  st := TBytesStream.Create(BytesOf(S));
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
  FRich.UpdateView;
end;

function TTyRichObjEventsTest.Centre(APos: TTyRichPos): TPoint;
var
  r, r2: TRect;
begin
  FRich.UpdateView;
  r := FRich.PositionRect(APos);
  r2 := FRich.PositionRect(APos + 1, True);
  AssertTrue('in view', r.Bottom > r.Top);
  Result := Point((r.Left + r2.Left) div 2, (r.Top + r.Bottom) div 2);
end;

procedure TTyRichObjEventsTest.ClickAt(const P: TPoint; AButton: TMouseButton);
var
  held: TShiftState;
begin
  case AButton of
    mbRight: held := [ssRight];
    mbMiddle: held := [ssMiddle];
  else
    held := [ssLeft];
  end;
  FRich.MDown(AButton, held, P.X, P.Y);
  if FRich <> nil then FRich.MUp(AButton, [], P.X, P.Y);
end;

procedure TTyRichObjEventsTest.DoubleClickAt(const P: TPoint);
begin
  ClickAt(P);
  if FRich = nil then Exit;
  FRich.MDown(mbLeft, [ssLeft, ssDouble], P.X, P.Y);
  if FRich <> nil then FRich.MUp(mbLeft, [ssDouble], P.X, P.Y);
end;

{ A double click on a picture hands its handler the picture: assigned to a TPicture it is the
  image at its own pixel size (not the 60 x 40 it is shown at) - a PNG, a JPEG, a bitmap, a
  metafile that is one bitmap; SaveImageToStream gives the image file's bytes. A metafile
  that draws more (the control's placeholder) raises EInvalidGraphic. }
procedure TTyRichObjEventsTest.TestDoubleClickOnAPictureGivesThePicture;
var
  png, jpg: TBytes;
  st: TBytesStream;
  pos: TTyRichPos;
  o: TTyRichObject;
  bmp: TBitmap;
  raised: Boolean;

  procedure Check(const AWhat, AKind: RawByteString; const AB: TBytes; AW, AH: Integer);
  begin
    Load(PictDoc(AKind, AB));
    FDbls := 0;
    FClicks := 0;
    FAssign := True;
    DoubleClickAt(Centre(2));
    AssertEquals(AWhat + ': one double click', 1, FDbls);
    AssertEquals(AWhat + ': the first click only (the second press is the double click)', 1, FClicks);
    AssertEquals(AWhat + ': at its place', 2, FObjPos);
    AssertTrue(AWhat + ': a picture', FObj is TTyRichPicture);
    AssertEquals(AWhat + ': its own width', AW, FPicW);
    AssertEquals(AWhat + ': its own height', AH, FPicH);
  end;

begin
  png := PngBytes(3, 2);
  Check('PNG', 'pngblip', png, 3, 2);
  st := TBytesStream.Create;
  try
    TTyRichPicture(FRich.ObjectAtPoint(Centre(2).X, Centre(2).Y, pos)).SaveImageToStream(st);
    AssertEquals('the file''s bytes', Length(png), st.Size);
    AssertTrue('the very bytes', CompareMem(@png[0], @st.Bytes[0], Length(png)));
  finally
    st.Free;
  end;
  jpg := JpegBytes(5, 4);
  Check('JPEG', 'jpegblip', jpg, 5, 4);
  Check('a bitmap', 'dibitmap0', SmallDib, 2, 2);
  Check('a metafile of one bitmap', 'wmetafile8', WmfBytes(False), 2, 2);
  // a TBitmap takes it too
  o := FRich.ObjectAtPoint(Centre(2).X, Centre(2).Y, pos);
  bmp := TBitmap.Create;
  try
    bmp.Assign(o);
    AssertEquals('a bitmap of it', 2, bmp.Width);
  finally
    bmp.Free;
  end;
  // a metafile the control shows as a placeholder
  Load(PictDoc('wmetafile8', WmfBytes(True)));
  o := FRich.ObjectAtPoint(Centre(2).X, Centre(2).Y, pos);
  AssertTrue('a picture', o is TTyRichPicture);
  raised := False;
  bmp := TBitmap.Create;
  try
    try
      bmp.Assign(o);
    except
      on E: EInvalidGraphic do raised := True;
    end;
  finally
    bmp.Free;
  end;
  AssertTrue('refused with EInvalidGraphic', raised);
end;

{ The double click's event comes before what a double click does: handled, nothing happens
  (the selection stays); not handled, the object is selected as a word. A handled right
  click: no menu. }
procedure TTyRichObjEventsTest.TestHandledStopsTheDefault;
var
  p: TPoint;
  menus: Integer;
begin
  Load(PictDoc('pngblip', PngBytes(3, 2)));
  p := Centre(2);
  ClickAt(p);
  FRich.SelStart := 0;
  FHandle := True;
  FRich.MDown(mbLeft, [ssLeft, ssDouble], p.X, p.Y);
  FRich.MUp(mbLeft, [ssDouble], p.X, p.Y);
  AssertEquals('handled: the double click', 1, FDbls);
  AssertEquals('handled: the selection stays', 0, FRich.SelStart);
  AssertEquals('handled: nothing selected', 0, FRich.SelLength);
  ClickAt(p);
  FRich.SelStart := 0;
  FHandle := False;
  FRich.MDown(mbLeft, [ssLeft, ssDouble], p.X, p.Y);
  FRich.MUp(mbLeft, [ssDouble], p.X, p.Y);
  AssertEquals('not handled: the double click', 2, FDbls);
  AssertEquals('not handled: the object selected', 2, FRich.SelStart);
  AssertEquals('not handled: as a word', 1, FRich.SelLength);
  // the right button: a handled click has no menu, one not handled has
  menus := FRich.MenuShows;
  FHandle := True;
  FClicks := 0;
  ClickAt(p, mbRight);
  AssertEquals('the right click reported', 1, FClicks);
  AssertEquals('with its button', Ord(mbRight), Ord(FButton));
  AssertTrue('handled: the menu is eaten', FRich.PopupAt(p.X, p.Y));
  AssertEquals('no menu', menus, FRich.MenuShows);
  FHandle := False;
  ClickAt(p, mbRight);
  FRich.PopupAt(p.X, p.Y);
  AssertEquals('not handled: the menu', menus + 1, FRich.MenuShows);
end;

{ ObjectAtPoint: a picture and a kept block that shows a picture are objects; text, a
  link's text, the place of a bookmark's ends and a field's marks are not. }
procedure TTyRichObjEventsTest.TestObjectAtPointForPicturesAndKeptBlocks;
var
  pos: TTyRichPos;
  o: TTyRichObject;
  p: TPoint;
begin
  Load(Rtf('{|rtf1|ansi|deff0{|fonttbl{|f0 Arial;}}|pard|f0 ab{|pict|pngblip|picw3|pich2|picwgoal900|pichgoal600 ' +
    HexOf(PngBytes(3, 2)) + '}cd {|object|objemb{|*|objclass Paint}{|*|objdata 0100}{|result{|pict|pngblip|picw3|pich2|picwgoal600|pichgoal600 ' +
    HexOf(PngBytes(4, 4)) + '}}} x{|*|bkmkstart m}{|*|bkmkend m}y ' +
    '{|field{|*|fldinst HYPERLINK "http://x"}{|fldrslt link}}|par}'));
  p := Centre(2);
  o := FRich.ObjectAtPoint(p.X, p.Y, pos);
  AssertTrue('the picture', o is TTyRichPicture);
  AssertEquals('its place', 2, pos);
  p := Centre(6);
  o := FRich.ObjectAtPoint(p.X, p.Y, pos);
  AssertTrue('the kept block', (o is TTyRichOpaque) and (TTyRichOpaque(o).DisplayPicture <> nil));
  AssertEquals('its place', 6, pos);
  p := Centre(0);
  AssertNull('text', FRich.ObjectAtPoint(p.X, p.Y, pos));
  AssertEquals('no place', -1, pos);
  p := Centre(8);
  AssertNull('beside the bookmark''s ends', FRich.ObjectAtPoint(p.X, p.Y, pos));
  p := Centre(14);
  AssertNull('a link''s text', FRich.ObjectAtPoint(p.X, p.Y, pos));
  AssertNull('outside the text', FRich.ObjectAtPoint(590, 290, pos));
  // a kept block's picture handed over
  p := Centre(6);
  o := FRich.ObjectAtPoint(p.X, p.Y, pos);
  FAssign := True;
  FDbls := 0;
  DoubleClickAt(p);
  AssertEquals('its double click', 1, FDbls);
  AssertEquals('of the block', 6, FObjPos);
  AssertEquals('its picture at its own size', 4, FPicW);
end;

{ The handlers may free the control or load another document: nothing of it is touched. }
procedure TTyRichObjEventsTest.TestTheHandlerMayFreeTheControl;
var
  p: TPoint;
begin
  Load(PictDoc('pngblip', PngBytes(3, 2)));
  p := Centre(2);
  FDo := 2;
  ClickAt(p);
  AssertEquals('the click', 1, FClicks);
  AssertTrue('another document', Pos('another', FRich.Document.Text.GetText(0, 7)) = 1);
  Load(PictDoc('pngblip', PngBytes(3, 2)));
  FDo := 1;
  ClickAt(Centre(2));
  AssertNull('freed by the click''s handler', FRich);
  FRich := TFieldProbe.Create(nil);
  FRich.Controller := FCtl;
  FRich.Font.PixelsPerInch := 96;
  FRich.SetBounds(0, 0, 600, 300);
  FRich.OnObjectDblClick := @Dbl;
  Load(PictDoc('pngblip', PngBytes(3, 2)));
  p := Centre(2);
  ClickAt(p);
  FRich.MDown(mbLeft, [ssLeft, ssDouble], p.X, p.Y);
  AssertNull('freed by the double click''s handler', FRich);
end;

{ Text, and a press that drags: no event. }
procedure TTyRichObjEventsTest.TestNoEventOnPlainText;
var
  p, p2: TPoint;
  r, r2: TRect;
  y: Integer;
begin
  Load(PictDoc('pngblip', PngBytes(3, 2)));
  p := Centre(0);
  DoubleClickAt(p);
  AssertEquals('no click on text', 0, FClicks);
  AssertEquals('no double click on text', 0, FDbls);
  p := Centre(2);
  p2 := Centre(4);
  FRich.MDown(mbLeft, [ssLeft], p.X, p.Y);
  FRich.MMove([ssLeft], p2.X, p2.Y);
  FRich.MUp(mbLeft, [], p2.X, p2.Y);
  AssertEquals('a drag from it: no click', 0, FClicks);
  // a drag inside the picture itself, from its left to its right: no click either
  r := FRich.PositionRect(2);
  r2 := FRich.PositionRect(3, True);
  y := (r.Top + r.Bottom) div 2;
  FRich.MDown(mbLeft, [ssLeft], r.Left + 4, y);
  FRich.MMove([ssLeft], r2.Left - 4, y);
  FRich.MUp(mbLeft, [], r2.Left - 4, y);
  AssertEquals('a drag across it: no click', 0, FClicks);
end;

{ A picture in a link: a click that is the link's is no object's click. }
procedure TTyRichObjEventsTest.TestAPictureInALinkIsTheLinksClick;
var
  p: TPoint;
begin
  Load(Rtf('{|rtf1|ansi|deff0{|fonttbl{|f0 Arial;}}|pard|f0 ab{|field{|*|fldinst HYPERLINK "http://x"}{|fldrslt ' +
    '{|pict|pngblip|picw3|pich2|picwgoal900|pichgoal600 ' + HexOf(PngBytes(3, 2)) + '}}}cd|par}'));
  FRich.ReadOnly := True;
  p := Centre(3);
  ClickAt(p);
  AssertEquals('the link''s click', 1, FLinks);
  AssertEquals('no object''s click', 0, FClicks);
  // editable, a plain click is no link's: the picture's
  FRich.ReadOnly := False;
  ClickAt(p);
  AssertEquals('no link click', 1, FLinks);
  AssertEquals('the object''s click', 1, FClicks);
end;

{ With AllowSelection False (a home page) the click still comes and nothing is selected; the
  middle button is reported too. }
procedure TTyRichObjEventsTest.TestAClickWithNoSelectionAndOtherButtons;
var
  p: TPoint;
begin
  Load(PictDoc('pngblip', PngBytes(3, 2)));
  FRich.ReadOnly := True;
  FRich.AllowSelection := False;
  p := Centre(2);
  FRich.SelStart := 0;
  ClickAt(p);
  AssertEquals('the click', 1, FClicks);
  AssertEquals('nothing selected', 0, FRich.SelLength);
  DoubleClickAt(p);
  AssertEquals('the double click', 1, FDbls);
  AssertEquals('still nothing selected', 0, FRich.SelLength);
  ClickAt(p, mbMiddle);
  AssertEquals('the middle button', Ord(mbMiddle), Ord(FButton));
end;

{ The event tells where: Point is the press's (the release's for a click) in client pixels,
  Bounds the picture's box (60 x 40 pixels here) with Point inside it, and PointInPicture
  maps the point into a picture of a given size - an image map. A click and a double click
  alike; the keys held come along. }
procedure TTyRichObjEventsTest.TestTheClickTellsThePointAndTheBox;
var
  c, p: TPoint;
begin
  Load(PictDoc('pngblip', PngBytes(8, 8)));
  c := Centre(2);
  // a point in the picture's upper left quarter
  p := Point(c.X - 15, c.Y - 10);
  ClickAt(p);
  AssertEquals('a click', 1, FClicks);
  AssertEquals('the point x', p.X, FPoint.X);
  AssertEquals('the point y', p.Y, FPoint.Y);
  AssertEquals('the box is the picture''s width', 60, FBounds.Right - FBounds.Left);
  AssertEquals('and its height', 40, FBounds.Bottom - FBounds.Top);
  AssertTrue('the point is in the box', PtInRect(FBounds, p));
  AssertEquals('in the picture: x as far in as in the box', p.X - FBounds.Left, FInPicture.X);
  AssertEquals('y the same', p.Y - FBounds.Top, FInPicture.Y);
  // the box is where the picture is drawn: its centre is the character's
  AssertEquals('the box around the centre', c.X, (FBounds.Left + FBounds.Right) div 2, 1);
  // a double click with Shift: the second press's point and the keys
  FRich.MDown(mbLeft, [ssLeft, ssDouble, ssShift], c.X, c.Y);
  FRich.MUp(mbLeft, [ssDouble, ssShift], c.X, c.Y);
  AssertEquals('a double click', 1, FDbls);
  AssertEquals('its point', c.X, FPoint.X);
  AssertTrue('the keys', ssShift in FShift);
end;

{ A press of one button on an object released with another: no click (the release must be
  the press's own button). }
procedure TTyRichObjEventsTest.TestAReleaseOfAnotherButtonIsNoClick;
var
  c: TPoint;
begin
  Load(PictDoc('pngblip', PngBytes(8, 8)));
  c := Centre(2);
  FRich.MDown(mbMiddle, [ssMiddle], c.X, c.Y);
  FRich.MUp(mbLeft, [], c.X, c.Y);
  AssertEquals('a middle press, a left release: no click', 0, FClicks);
  FRich.MDown(mbMiddle, [ssMiddle], c.X, c.Y);
  FRich.MUp(mbMiddle, [], c.X, c.Y);
  AssertEquals('a middle press and release: the click', 1, FClicks);
  AssertTrue('of the middle button', FButton = mbMiddle);
end;

initialization
  RegisterTest(TTyRichObjEventsTest);

end.
