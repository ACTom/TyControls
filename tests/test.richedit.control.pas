unit test.richedit.control;

{ TTyRichEdit, the viewer (Task 9a): loading and saving through the control, scrolling on the
  height index (only what is seen is laid out, the view stays anchored while estimates are
  corrected), partial invalidation, painting only what the clip meets, pictures left for the
  background, zoom, wrap, Lines, the theme keys.

  Headless: the layout measures with the test device (test.richedit.layoutdevice: every advance
  worked out by rule), no window is made, invalidations are recorded by the probe's
  InvalidateContent, the background work is stepped by hand (StepBackground, FinishLoading) -
  no timer, no message loop. Every bound is a count (blocks laid out, draw calls, node visits,
  bytes on the heap), never a time. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, fpcunit, testregistry, Controls, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.StyleModel, tyControls.Controller, tyControls.BuiltinThemes,
  tyControls.ScrollBar, tyControls.Painter,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite, tyControls.RichEdit.Layout,
  tyControls.RichEdit, test.richedit.layoutdevice, test.devicescale.support;

type
  { A layouter whose resampling can be made to fail (a test seam of W2's). }
  TProbeLayouter = class(TTyRichLayouter)
  protected
    function ScaleImage(AImage: TBGRABitmap; AWidth, AHeight: Integer): TBGRABitmap; override;
  public
    FailScale: Boolean;
  end;

  TRichProbe = class(TTyRichEdit)
  private
    FLaidParas: Integer;
    FLaidMin, FLaidMax: Integer;
    FBlockPaints, FFramePaints: Integer;
  protected
    function CreateDevice: TTyRichTextDevice; override;
    function CreateLayouter: TTyRichLayouter; override;
    function LayoutBlockAt(AIndex: Integer): TTyBlockLayout; override;
    procedure InvalidateArea(const ARect: TRect); override;
    procedure PaintBlock(ABitmap: TBGRABitmap; AIndex, AX, AY: Integer; const AClip: TRect;
      const AStyle: TTyRichPaintStyle); override;
    procedure PaintSurfaceFrame(APPI: Integer); override;
    function ScrollBarLimit: Integer; override;
  public
    Invalidated: array of TRect;
    BarLimit: Integer;
    { LayoutBlockAt raises after this many more layouts (0: never); the layouts it gave. }
    RaiseAfter: Integer;
    Given: array of TTyBlockLayout;
    procedure ResetCounts;
    procedure PaintPart(ACanvas: TCanvas; const AClip: TRect; ADefer: Boolean);
    function Step: Boolean;
    function Pending: Integer;
    function VBar: TTyScrollBar;
    function HBar: TTyScrollBar;
    function TypeKey: string;
    function Style: TTyRichPaintStyle;
    function Area: TRect;
    procedure Slices(AFirst, AStep: Int64);
    procedure Press(AKey: Word; AShift: TShiftState);
    procedure Wheel(ADelta: Integer; AShift: TShiftState);
    function Device: TTyRichTestDevice;
    function Lay: TProbeLayouter;
    function Surf: TBGRABitmap;
    function Scale: Integer;
    procedure RedrawAll;
    procedure InvalidatePart(const ARect: TRect);
    procedure WheelH(ADelta: Integer);
    procedure Hover(AOn: Boolean);
    property BlockPaints: Integer read FBlockPaints;
    property FramePaints: Integer read FFramePaints;
    property LaidParas: Integer read FLaidParas;
    property LaidMin: Integer read FLaidMin;
    property LaidMax: Integer read FLaidMax;
  end;

  TTyRichEditControlTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TRichProbe;
    FTemp: string;
    FChanges, FZooms, FLoadCalls, FCancelAt, FRefused: Integer;
    FOther: TStream;
    procedure Changed(Sender: TObject);
    procedure Zoomed(Sender: TObject);
    procedure LoadCalled(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    procedure SaveCancel(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    function NewProbe: TRichProbe;
    procedure LoadBig;
    function ScreenLines: Integer;
    function TempFile(const AName: string; const ABytes: TBytes): string;
    function InView(APara: Integer): Boolean;
    procedure SetLinesOf(ACount: Integer; const APrefix: string);
    function Covered(const ARect: TRect): Boolean;
    procedure PaintAll(ADefer: Boolean);
    procedure ReplaceInHandler(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    procedure CancelInHandler(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    procedure SaveReplace(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    procedure NoFallback(Sender: TObject; const ABaseFont: string; ACode: Cardinal;
      var AFontName: string);
    procedure PictureCase(const AWhat: string; APngW, APngH: Integer; AFail: Boolean;
      AZoomAfter: Integer);
    function FileCount: Integer;
    procedure CheckClearAdd(const AList: array of string);
    procedure CheckSurface(const AWhat: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestLoadShowsTheFirstScreenWithoutLayingOutTheRest;
    procedure TestScrollingToTheMiddleLaysOutOnlyNearby;
    procedure TestScrollPositionStaysPutWhenEstimatesAreCorrected;
    procedure TestPartialRepaintCoversOnlyTheChangedParagraph;
    procedure TestZoomChangesDisplayOnly;
    procedure TestTheTypeKeyHangsUnderTheMemo;
    procedure TestSelectionColoursResolveInEveryBuiltinTheme;
    procedure TestALazyRtfPaintsItsFirstScreenWhileLoading;
    procedure TestACancelledLoadIsIncompleteAndNotSavedOverItsFile;
    procedure TestEveryFixtureSavesBackByteForByte;
    procedure TestACancelledSaveLeavesTheFileAsItWas;
    procedure TestAWidthOrZoomChangeLaysOutOnlyTheViewAgain;
    procedure TestARowsHeightGoesOnItsFirstParagraph;
    procedure TestNoWrapExtentGrowsWithWhatWasSeen;
    procedure TestLinesReadTheDocumentWithoutCopyingIt;
    procedure TestAssigningLinesReplacesTheContent;
    procedure TestLinesGoIntoTheFormFileOnlyWhenSetThroughThem;
    procedure TestATallDocumentScrollsToItsLastLine;
    procedure TestAPaintDrawsOnlyTheBlocksInItsClip;
    procedure TestADeferredPaintLeavesPicturesForLater;
    procedure TestKeysAndWheelScrollAndZoom;
    procedure TestReadOnlyStaysOnAndCodeStillChanges;
    // 9a2: the review of 9a
    procedure TestAShortWrappedDocumentSettlesItsScrollBar;
    procedure TestAChangeWhileTheViewIsInvalidIsPainted;
    procedure TestALayoutThatMovesTheViewRepaintsIt;
    procedure TestAChangeOfManyParagraphsLaysOutOnlyTheView;
    procedure TestNumbersAfterAChangedItemAreRepainted;
    procedure TestQueriesSettleTheViewFirst;
    procedure TestProgressHandlersCannotReplaceTheContent;
    procedure TestAPictureIsQueuedOnceAndEveryBoxRepainted;
    procedure TestASaveKeepsWhatTheTargetWas;
    procedure TestAFileOpenForWritingLoads;
    procedure TestPublishedDefaultsAreTheConstructedValues;
    procedure TestLinesTellNoLinesFromOneEmptyLine;
    procedure TestFinishLoadingGoesInSlices;
    procedure TestScrollingAgainstAnEndDoesNothing;
    procedure TestAZoomKeepsThePartOfTheBlockAtTheTop;
    procedure TestAFarScrollIsAJump;
    procedure TestSavingAsTextIsAnExport;
    procedure TestASaveThatCannotWriteNamesTheTarget;
    procedure TestALayoutThatRaisesKeepsNoReference;
    procedure TestStreamingRaisesNoChangeAndABatchIsOneStep;
    procedure TestStyleOverrideTokensReachTheParts;
    procedure TestAChangeInARowDropsItsPendingPicture;
    procedure TestAFallbackFontChangeLaysTheViewOutAgain;
    procedure TestHugeBlocksKeepTheArithmeticInRange;
    // R40
    procedure TestTheBytesBeforeTheRtfAreKept;
    // R39
    procedure TestTheSurfaceEqualsAFullRedraw;
    procedure TestAScrollPaintsOnlyWhatItExposes;
    procedure TestTheSurfaceIsTheClientsSize;
    procedure TestDeviceScaleTwo;
  end;

implementation

const
  BigLines = 2000000;

var
  GBig: TBytes;

function Sentinel: TBGRAPixel;
begin
  Result := BGRA(255, 0, 255, 255);
end;

function SamePx(const A, B: TBGRAPixel): Boolean;
begin
  Result := (A.red = B.red) and (A.green = B.green) and (A.blue = B.blue) and
    (A.alpha = B.alpha);
end;

{ 'Line 1' .. 'Line 2000000', one a paragraph (LF), made once. }
function BigText: TBytes;
var
  ms: TMemoryStream;
  i: Integer;
  s: RawByteString;
begin
  if GBig = nil then
  begin
    ms := TMemoryStream.Create;
    try
      ms.Size := 30 * BigLines;
      ms.Position := 0;
      for i := 1 to BigLines do
      begin
        s := 'Line ' + IntToStr(i);
        if i < BigLines then s := s + #10;
        ms.WriteBuffer(s[1], Length(s));
      end;
      SetLength(GBig, ms.Position);
      Move(ms.Memory^, GBig[0], ms.Position);
    finally
      ms.Free;
    end;
  end;
  Result := GBig;
end;

{ An RTF file of about ATarget bytes: one font, paragraphs of words. AParas: how many. }
function GeneratedRtf(ATarget: Int64; out AParas: Integer): TBytes;
var
  s: RawByteString;
  ms: TMemoryStream;
begin
  ms := TMemoryStream.Create;
  try
    s := '{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fswiss Arial;}}' + #13#10 + '\pard\f0\fs20 ';
    ms.WriteBuffer(s[1], Length(s));
    AParas := 0;
    while ms.Size < ATarget do
    begin
      s := 'Paragraph ' + IntToStr(AParas) + ' of the generated file, with \b some\b0  words.\par' +
        #13#10;
      ms.WriteBuffer(s[1], Length(s));
      Inc(AParas);
    end;
    s := '}' + #13#10;
    ms.WriteBuffer(s[1], Length(s));
    // (a \par that ends the document ends its last paragraph: no empty one follows)
    Result := nil;
    SetLength(Result, ms.Size);
    Move(ms.Memory^, Result[0], ms.Size);
  finally
    ms.Free;
  end;
end;

function PngBytes(AW, AH: Integer; AColor: TBGRAPixel): TBytes;
var
  b: TBGRABitmap;
  st: TBytesStream;
begin
  b := TBGRABitmap.Create(AW, AH, AColor);
  st := TBytesStream.Create;
  try
    b.SaveToStreamAsPng(st);
    Result := Copy(st.Bytes, 0, st.Size);
  finally
    st.Free;
    b.Free;
  end;
end;

function FileBytes(const APath: string): TBytes;
var
  f: TFileStream;
begin
  Result := nil;
  f := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, f.Size);
    if f.Size > 0 then f.ReadBuffer(Result[0], f.Size);
  finally
    f.Free;
  end;
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

function StreamBytes(AStream: TMemoryStream): TBytes;
begin
  Result := nil;
  SetLength(Result, AStream.Size);
  if AStream.Size > 0 then Move(AStream.Memory^, Result[0], AStream.Size);
end;

function FixtureDir(const ASub: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim + 'fixtures' +
    PathDelim + ASub + PathDelim;
end;

{ ---- the probe ---- }

function TRichProbe.CreateDevice: TTyRichTextDevice;
begin
  Result := TTyRichTestDevice.Create;
end;

function TProbeLayouter.ScaleImage(AImage: TBGRABitmap; AWidth, AHeight: Integer): TBGRABitmap;
begin
  if FailScale then raise EInvalidOperation.Create('the test''s failing resample');
  Result := inherited ScaleImage(AImage, AWidth, AHeight);
end;

function TRichProbe.CreateLayouter: TTyRichLayouter;
begin
  Result := TProbeLayouter.Create(CreateDevice, True);
end;

function TRichProbe.Lay: TProbeLayouter;
begin
  Result := Layouter as TProbeLayouter;
end;

function TRichProbe.LayoutBlockAt(AIndex: Integer): TTyBlockLayout;
var
  before: Int64;
begin
  if RaiseAfter > 0 then
  begin
    Dec(RaiseAfter);
    if RaiseAfter = 0 then raise EInvalidOperation.Create('the test''s failing layout');
  end;
  before := Layouter.CacheMisses;
  Result := inherited LayoutBlockAt(AIndex);
  SetLength(Given, Length(Given) + 1);
  Given[High(Given)] := Result;
  if Layouter.CacheMisses > before then
  begin
    Inc(FLaidParas, Result.LastPara - Result.FirstPara + 1);
    if Result.FirstPara < FLaidMin then FLaidMin := Result.FirstPara;
    if Result.LastPara > FLaidMax then FLaidMax := Result.LastPara;
  end;
end;

procedure TRichProbe.InvalidateArea(const ARect: TRect);
begin
  SetLength(Invalidated, Length(Invalidated) + 1);
  Invalidated[High(Invalidated)] := ARect;
  inherited InvalidateArea(ARect);
end;

procedure TRichProbe.PaintBlock(ABitmap: TBGRABitmap; AIndex, AX, AY: Integer;
  const AClip: TRect; const AStyle: TTyRichPaintStyle);
begin
  Inc(FBlockPaints);
  inherited PaintBlock(ABitmap, AIndex, AX, AY, AClip, AStyle);
end;

procedure TRichProbe.PaintSurfaceFrame(APPI: Integer);
begin
  Inc(FFramePaints);
  inherited PaintSurfaceFrame(APPI);
end;

function TRichProbe.Surf: TBGRABitmap;
begin
  Result := Surface;
end;

function TRichProbe.Scale: Integer;
begin
  Result := DeviceScale;
end;

procedure TRichProbe.RedrawAll;
begin
  InvalidateSurface;
end;

procedure TRichProbe.InvalidatePart(const ARect: TRect);
begin
  InvalidateContent(ARect);
end;

procedure TRichProbe.WheelH(ADelta: Integer);
begin
  DoMouseWheelHorz([], ADelta, Point(10, 10));
end;

procedure TRichProbe.Hover(AOn: Boolean);
begin
  if AOn then MouseEnter else MouseLeave;
end;

function TRichProbe.ScrollBarLimit: Integer;
begin
  if BarLimit > 0 then Result := BarLimit else Result := inherited ScrollBarLimit;
end;

procedure TRichProbe.ResetCounts;
begin
  FLaidParas := 0;
  FLaidMin := MaxInt;
  FLaidMax := -1;
  Invalidated := nil;
  Given := nil;
  FBlockPaints := 0;
  FFramePaints := 0;
  if Layouter <> nil then Device.ResetCounters;
end;

procedure TRichProbe.PaintPart(ACanvas: TCanvas; const AClip: TRect; ADefer: Boolean);
begin
  PaintArea(ACanvas, Rect(0, 0, Width, Height), AClip, Font.PixelsPerInch, ADefer);
end;

function TRichProbe.Step: Boolean;
begin
  Result := StepBackground;
end;

function TRichProbe.Pending: Integer;
begin
  Result := PendingPictureCount;
end;

function TRichProbe.VBar: TTyScrollBar;
begin
  Result := VerticalBar;
end;

function TRichProbe.HBar: TTyScrollBar;
begin
  Result := HorizontalBar;
end;

function TRichProbe.TypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

function TRichProbe.Style: TTyRichPaintStyle;
begin
  Result := Default(TTyRichPaintStyle);
  FillPaintStyle(Result);
end;

function TRichProbe.Area: TRect;
begin
  Result := TextArea(Rect(0, 0, Width, Height), Font.PixelsPerInch);
end;

procedure TRichProbe.Slices(AFirst, AStep: Int64);
begin
  FirstSliceBytes := AFirst;
  StepBytes := AStep;
end;

procedure TRichProbe.Press(AKey: Word; AShift: TShiftState);
begin
  KeyDown(AKey, AShift);
end;

procedure TRichProbe.Wheel(ADelta: Integer; AShift: TShiftState);
begin
  DoMouseWheel(AShift, ADelta, Point(10, 10));
end;

function TRichProbe.Device: TTyRichTestDevice;
begin
  Result := Layouter.Device as TTyRichTestDevice;
end;

{ ---- the suite ---- }

procedure TTyRichEditControlTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FRich := NewProbe;
  FTemp := '';
  FChanges := 0;
  FZooms := 0;
  FLoadCalls := 0;
  FCancelAt := 0;
  FRefused := 0;
end;

procedure TTyRichEditControlTest.TearDown;
var
  sr: TSearchRec;
begin
  TyForceDeviceScaleForTest(0, False);
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

function TTyRichEditControlTest.NewProbe: TRichProbe;
begin
  Result := TRichProbe.Create(nil);
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 300);
  Result.ResetCounts;
end;

procedure TTyRichEditControlTest.Changed(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TTyRichEditControlTest.Zoomed(Sender: TObject);
begin
  Inc(FZooms);
end;

procedure TTyRichEditControlTest.LoadCalled(Sender: TObject; ADone, ATotal: Int64;
  var ACancel: Boolean);
begin
  Inc(FLoadCalls);
  if (FCancelAt > 0) and (FLoadCalls >= FCancelAt) then ACancel := True;
end;

procedure TTyRichEditControlTest.SaveCancel(Sender: TObject; ADone, ATotal: Int64;
  var ACancel: Boolean);
begin
  Inc(FLoadCalls);
  ACancel := True;
end;

procedure TTyRichEditControlTest.LoadBig;
var
  st: TBytesStream;
begin
  st := TBytesStream.Create(BigText);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
end;

{ Lines of the base font the text area holds. }
function TTyRichEditControlTest.ScreenLines: Integer;
var
  a: TRect;
begin
  a := FRich.Area;
  Result := (a.Bottom - a.Top) div FRich.Layouter.EstimatedParaHeight(96, FRich.Zoom / 100) + 1;
end;

function TTyRichEditControlTest.TempFile(const AName: string; const ABytes: TBytes): string;
var
  f: TFileStream;
begin
  if FTemp = '' then
  begin
    // the process id: two runs of this suite at once (mutation shards) have folders of their own
    FTemp := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'tyrichedit9a-' +
      IntToStr(GetProcessID) + '-' + IntToHex(Random($7FFFFFFF), 8) + PathDelim;
    ForceDirectories(FTemp);
  end;
  Result := FTemp + AName;
  f := TFileStream.Create(Result, fmCreate);
  try
    if Length(ABytes) > 0 then f.WriteBuffer(ABytes[0], Length(ABytes));
  finally
    f.Free;
  end;
end;

{ ABand is AWant's rows, as wide as the text and reaching into its left padding. }
function SameBand(const AWant, ABand: TRect): Boolean;
begin
  Result := (ABand.Top = AWant.Top) and (ABand.Bottom = AWant.Bottom) and
    (ABand.Right = AWant.Right) and (ABand.Left <= AWant.Left) and (ABand.Left >= 0);
end;

function TTyRichEditControlTest.InView(APara: Integer): Boolean;
var
  r, a: TRect;
begin
  r := FRich.ParagraphRect(APara);
  a := FRich.Area;
  Result := (r.Bottom > r.Top) and (r.Bottom > a.Top) and (r.Top < a.Bottom);
end;

{ The plan's: a 2,000,000-line txt loaded and its first screen painted lays out no more than
  the visible lines and two screens. }
procedure TTyRichEditControlTest.TestLoadShowsTheFirstScreenWithoutLayingOutTheRest;
var
  bmp: TBitmap;
  n: Integer;
begin
  LoadBig;
  AssertEquals('all the lines', BigLines, FRich.Document.Text.ParaCount);
  FRich.ResetCounts;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(400, 300);
    FRich.RenderTo(bmp.Canvas, Rect(0, 0, 400, 300), 96);
  finally
    bmp.Free;
  end;
  n := ScreenLines;
  AssertTrue(Format('laid out %d paragraphs, a screen is %d lines', [FRich.LaidParas, n]),
    (FRich.LaidParas > 0) and (FRich.LaidParas <= 3 * n + 2));
  AssertEquals('from the top', 0, FRich.LaidMin);
  AssertTrue('the first line is on screen', InView(0));
  AssertTrue('the scroll bar spans the document',
    (FRich.VBar <> nil) and FRich.VBar.Visible and (FRich.VBar.Max > 100 * n));
end;

{ The plan's: the scroll position set to the middle lays out only around it. }
procedure TTyRichEditControlTest.TestScrollingToTheMiddleLaysOutOnlyNearby;
var
  n, mid: Integer;
begin
  LoadBig;
  FRich.UpdateView;
  FRich.ResetCounts;
  FRich.ScrollY := FRich.Document.Text.TotalHeight div 2;
  FRich.UpdateView;
  n := ScreenLines;
  mid := BigLines div 2;
  AssertTrue(Format('the view is at the middle (top %d)', [FRich.TopParagraph]),
    Abs(FRich.TopParagraph - mid) <= 2);
  AssertTrue(Format('laid out %d .. %d', [FRich.LaidMin, FRich.LaidMax]),
    (FRich.LaidMin >= mid - 2 * n) and (FRich.LaidMax <= mid + 3 * n));
  AssertTrue(Format('%d paragraphs laid out', [FRich.LaidParas]), FRich.LaidParas <= 3 * n + 2);
end;

{ The plan's: laying out the paragraphs above (taller than their estimates) does not move the
  first line on screen; the scroll position (the sum of the heights above) moves instead. }
procedure TTyRichEditControlTest.TestScrollPositionStaysPutWhenEstimatesAreCorrected;
var
  s: string;
  i, est: Integer;
  sl: TStringList;
  before: Int64;
begin
  sl := TStringList.Create;
  try
    s := '';
    for i := 1 to 50 do s := s + 'word' + IntToStr(i mod 7) + ' ';
    for i := 0 to 399 do sl.Add(IntToStr(i) + ' ' + s);
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  // nothing is laid out yet: a position is the estimates' sum
  FRich.ScrollY := 1;
  est := FRich.Layouter.EstimatedParaHeight(96, 1);
  AssertEquals('nothing measured', 0, FRich.Document.Text.MeasuredParaCount);
  FRich.ScrollY := Int64(200) * est;
  AssertEquals('at paragraph 200', 200, FRich.TopParagraph);
  AssertEquals('at its top', 0, FRich.TopOffset);
  // the anchor's position as the estimates put it (ScrollY would lay the view out first)
  before := FRich.Document.Text.ParaTop(FRich.TopParagraph) + FRich.TopOffset;
  FRich.UpdateView;
  AssertTrue('the paragraphs above were laid out taller than estimated',
    FRich.ScrollY > before + 4 * est);
  AssertEquals('the first line stays paragraph 200', 200, FRich.TopParagraph);
  AssertEquals('at the same offset', 0, FRich.TopOffset);
  AssertEquals('on the screen''s top', FRich.Area.Top, FRich.ParagraphRect(200).Top);
  // inside a block too
  FRich.ScrollViewBy(est + 3);
  FRich.UpdateView;
  AssertEquals('scrolled into it', 200, FRich.TopParagraph);
  AssertEquals('by that much', est + 3, FRich.TopOffset);
  AssertEquals('its top above the screen by it', FRich.Area.Top - est - 3,
    FRich.ParagraphRect(200).Top);
end;

{ The plan's: a format changed by code invalidates the changed paragraph's rectangle only; a
  change of its height, it and what is below it. }
procedure TTyRichEditControlTest.TestPartialRepaintCoversOnlyTheChangedParagraph;
var
  sl: TStringList;
  i: Integer;
  f: TTyCharFormat;
  r5, r7, a: TRect;
  t: TTyRichText;
begin
  sl := TStringList.Create;
  try
    for i := 0 to 199 do sl.Add('Line ' + IntToStr(i));
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.UpdateView;
  t := FRich.Document.Text;
  r5 := FRich.ParagraphRect(5);
  AssertTrue('paragraph 5 is on screen', r5.Bottom > r5.Top);
  FRich.ResetCounts;
  f := TyDefaultCharFormat;
  f.Color := clRed;
  AssertTrue('a colour from code', FRich.Document.Execute(TTyRichSetCharFormat.Create(
    TyRichRange(t.ParaStart(5), t.ParaLength(5)), [cffColor], f)));
  AssertEquals('one rectangle', 1, Length(FRich.Invalidated));
  AssertTrue('the paragraph''s', SameBand(r5, FRich.Invalidated[0]));
  AssertEquals('one block laid out again', 1, FRich.LaidParas);
  // a taller paragraph moves what is below it
  r7 := FRich.ParagraphRect(7);
  a := FRich.Area;
  FRich.ResetCounts;
  f.SizeHalfPt := 48;
  AssertTrue('a size from code', FRich.Document.Execute(TTyRichSetCharFormat.Create(
    TyRichRange(t.ParaStart(7), t.ParaLength(7)), [cffSize], f)));
  AssertEquals('one rectangle', 1, Length(FRich.Invalidated));
  AssertTrue('from the paragraph to the bottom', SameBand(Rect(a.Left, r7.Top, a.Right,
    a.Bottom), FRich.Invalidated[0]));
  // a change below the view and the blocks it holds invalidates nothing
  FRich.UpdateView;
  FRich.ResetCounts;
  AssertTrue('far below', FRich.Document.Execute(TTyRichSetCharFormat.Create(
    TyRichRange(t.ParaStart(190), t.ParaLength(190)), [cffSize], f)));
  FRich.UpdateView;
  AssertEquals('nothing on screen changed', 0, Length(FRich.Invalidated));
  // nor does a taller paragraph above the view: the first line on screen holds
  FRich.ScrollY := FRich.Document.Text.ParaTop(120);
  FRich.UpdateView;
  r5 := FRich.ParagraphRect(120);
  AssertTrue('paragraph 115 is laid out above the view', FRich.ParagraphRect(115).Bottom <= a.Top);
  FRich.ResetCounts;
  AssertTrue('above', FRich.Document.Execute(TTyRichSetCharFormat.Create(
    TyRichRange(t.ParaStart(115), t.ParaLength(115)), [cffSize], f)));
  FRich.UpdateView;
  AssertEquals('nothing on screen moved', 0, Length(FRich.Invalidated));
  AssertEquals('the same first paragraph', 120, FRich.TopParagraph);
  AssertTrue('in the same place', EqualRect(r5, FRich.ParagraphRect(120)));
end;

{ The plan's: zooming changes what is shown, not the document - no OnChange - and the page's
  layout width scales with it; the zoom is clamped to 10 .. 500 and reports itself. }
procedure TTyRichEditControlTest.TestZoomChangesDisplayOnly;
var
  w100, w200: Integer;
begin
  FRich.Lines.Text := 'One paragraph'#13#10'and another';
  FRich.OnChange := @Changed;
  FRich.OnZoomChange := @Zoomed;
  FRich.WrapMode := rwmPage;
  FRich.UpdateView;
  w100 := FRich.VisibleBlocks[0].Layout.LayoutWidth;
  FRich.Zoom := 200;
  FRich.UpdateView;
  w200 := FRich.VisibleBlocks[0].Layout.LayoutWidth;
  AssertTrue(Format('the page twice as wide (%d, %d)', [w100, w200]), Abs(w200 - 2 * w100) <= 1);
  AssertEquals('no document change', 0, FChanges);
  AssertFalse('not modified', FRich.Modified);
  AssertEquals('one zoom change', 1, FZooms);
  FRich.Zoom := 1000;
  AssertEquals('at most 500', 500, FRich.Zoom);
  FRich.Zoom := 1;
  AssertEquals('at least 10', 10, FRich.Zoom);
  AssertEquals('each reported', 3, FZooms);
  FRich.Zoom := 10;
  AssertEquals('no change, no report', 3, FZooms);
  AssertEquals('still no document change', 0, FChanges);
end;

procedure TTyRichEditControlTest.TestTheTypeKeyHangsUnderTheMemo;
var
  s: TTyStyleSet;
begin
  AssertEquals('its own key', 'TyRichEdit', FRich.TypeKey);
  AssertEquals('under the memo''s', 'TyMemo', TyTypeKeyParent('TyRichEdit'));
  FCtl.LoadThemeCss('TyMemo { background: #123456; color: #654321; padding: 7px; }');
  s := FRich.ScrollBarFrameStyle;
  AssertTrue('the memo''s background', (tpBackground in s.Present) and
    (TyRedOf(s.Background.Color) = $12) and (TyBlueOf(s.Background.Color) = $56));
  AssertEquals('the memo''s padding', 7, FRich.Area.Left);
  AssertTrue('the memo''s text colour', SamePx(BGRA($65, $43, $21, 255), FRich.Style.TextColor));
end;

procedure TTyRichEditControlTest.TestSelectionColoursResolveInEveryBuiltinTheme;
var
  c: TTyStyleController;
  names: TStringArray;
  i, m, k: Integer;
  mode, who: string;
  ground, sel: TTyStyleSet;
  st: TTyRichPaintStyle;
  g, p: TBGRAPixel;
begin
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  AssertTrue('the built-in themes', Length(names) >= 17);
  c := TTyStyleController.Create(nil);
  try
    for i := 0 to High(names) do
      for m := 0 to 1 do
      begin
        if m = 0 then mode := 'light' else mode := 'dark';
        c.ThemeName := names[i];
        c.Mode := mode;
        ground := c.Model.ResolveStyle('TyRichEdit', '', []);
        AssertTrue(names[i] + '/' + mode + ': a ground', tpBackground in ground.Present);
        g := TyColorToBGRA(ground.Background.Color);
        for k := 0 to 1 do
        begin
          if k = 0 then sel := c.Model.ResolveStyle('TyRichEditSelection', '', [])
          else sel := c.Model.ResolveStyle('TyRichEditSelection', '', [tysFocused]);
          who := Format('%s/%s selection %d', [names[i], mode, k]);
          AssertTrue(who + ': resolves', tpBackground in sel.Present);
          p := TyColorToBGRA(sel.Background.Color);
          AssertTrue(who + ': not transparent', p.alpha > 0);
          // laid over the ground it shows
          AssertTrue(who + ': differs from the ground',
            (Abs(p.red - g.red) + Abs(p.green - g.green) + Abs(p.blue - g.blue)) * p.alpha >
            8 * 255);
        end;
      end;
  finally
    c.Free;
  end;
  // the control paints with what its theme says
  FCtl.LoadThemeCss('TyRichEditSelection { background: #FF0000; }' +
    'TyRichEditObject { border-color: #00FF00; }' +
    'TyRichEditPlaceholder { background: #0000FF; border-color: #FFFF00; }');
  st := FRich.Style;
  AssertTrue('selection', SamePx(BGRA(255, 0, 0, 255), st.SelectionBack));
  AssertTrue('object frame', SamePx(BGRA(0, 255, 0, 255), st.ObjectFrame));
  AssertTrue('placeholder fill', SamePx(BGRA(0, 0, 255, 255), st.PlaceholderFill));
  AssertTrue('placeholder frame', SamePx(BGRA(255, 255, 0, 255), st.PlaceholderFrame));
end;

procedure TTyRichEditControlTest.TestALazyRtfPaintsItsFirstScreenWhileLoading;
var
  b: TBytes;
  paras, first, n, steps, x, y, ink: Integer;
  st: TBytesStream;
  bmp: TBitmap;
  bg: TBGRABitmap;
  a: TRect;
begin
  b := GeneratedRtf(2 * 1024 * 1024, paras);
  FRich.Slices(64 * 1024, 64 * 1024);
  FRich.OnChange := @Changed;
  FRich.OnLoadProgress := @LoadCalled;
  st := TBytesStream.Create(b);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  AssertTrue('still loading', FRich.Loading);
  AssertEquals('the load is one change', 1, FChanges);
  first := FRich.Document.Text.ParaCount;
  AssertTrue(Format('a part (%d of %d)', [first, paras]), (first > 10) and (first < paras div 4));
  FRich.ResetCounts;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(400, 300);
    bmp.Canvas.Brush.Color := RGBToColor(255, 0, 255);
    bmp.Canvas.FillRect(0, 0, 400, 300);
    FRich.RenderTo(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    bg := TBGRABitmap.Create(bmp);
    try
      a := FRich.Area;
      ink := 0;
      for y := a.Top to a.Bottom - 1 do
        for x := a.Left to a.Right - 1 do
          if not SamePx(bg.GetPixel(x, y), FRich.Style.TextColor) then Continue else Inc(ink);
    finally
      bg.Free;
    end;
  finally
    bmp.Free;
  end;
  AssertTrue('the first screen is painted', ink > 50);
  AssertTrue('while still loading', FRich.Loading);
  n := ScreenLines;
  AssertTrue(Format('only the first blocks laid out (%d)', [FRich.LaidParas]),
    (FRich.LaidParas <= 3 * n + 2) and (FRich.LaidMax <= 3 * n + 2));
  steps := 0;
  while FRich.Loading and (steps < 3) do
  begin
    AssertTrue('a step', FRich.Step);
    Inc(steps);
  end;
  AssertTrue('progress reported', FLoadCalls >= 3);
  AssertTrue('the document grew', FRich.Document.Text.ParaCount > first);
  AssertEquals('slices are no changes of the content', 1, FChanges);
  FRich.FinishLoading;
  AssertFalse('loaded', FRich.Loading);
  AssertFalse('complete', FRich.Incomplete);
  AssertEquals('every paragraph', paras, FRich.Document.Text.ParaCount);
  AssertEquals('still one change', 1, FChanges);
end;

procedure TTyRichEditControlTest.TestACancelledLoadIsIncompleteAndNotSavedOverItsFile;
var
  b: TBytes;
  paras: Integer;
  path: string;
  raised: Boolean;
  ms: TMemoryStream;
begin
  b := GeneratedRtf(2 * 1024 * 1024, paras);
  path := TempFile('big.rtf', b);
  FRich.Slices(64 * 1024, 64 * 1024);
  FRich.OnLoadProgress := @LoadCalled;
  FCancelAt := 2;
  FRich.LoadFromFile(path);
  AssertTrue('loading', FRich.Loading);
  while FRich.Loading and FRich.Step do ;
  AssertFalse('stopped', FRich.Loading);
  AssertTrue('incomplete', FRich.Incomplete);
  AssertTrue('a part', FRich.Document.Text.ParaCount < paras);
  AssertEquals('cancelled where it was asked to', 2, FLoadCalls);
  raised := False;
  try
    FRich.SaveToFile(path);
  except
    on E: ETyRichEdit do raised := True;
  end;
  AssertTrue('not saved over its file', raised);
  AssertTrue('the file is as it was', SameBytes(b, FileBytes(path)));
  raised := False;
  ms := TMemoryStream.Create;
  try
    try
      FRich.SaveToStream(ms);
    except
      on E: ETyRichEdit do raised := True;
    end;
    AssertTrue('nor anywhere', raised);
    AssertEquals('nothing written', 0, ms.Size);
  finally
    ms.Free;
  end;
  // still readable
  FRich.UpdateView;
  AssertTrue('shows its part', FRich.VisibleBlockCount > 0);
end;

{ Loaded through the control, saved through the control: the same bytes - also saved over the
  very file the document reads from, after which it still reads (saved again: the same). }
procedure TTyRichEditControlTest.TestEveryFixtureSavesBackByteForByte;
var
  sr: TSearchRec;
  dirs: array[0..1] of string;
  d, count: Integer;
  orig: TBytes;
  path: string;
  ms: TMemoryStream;
begin
  dirs[0] := 'rtf';
  dirs[1] := 'txt';
  count := 0;
  for d := 0 to 1 do
    if FindFirst(FixtureDir(dirs[d]) + '*', faAnyFile, sr) = 0 then
    try
      repeat
        if (sr.Attr and faDirectory) <> 0 then Continue;
        orig := FileBytes(FixtureDir(dirs[d]) + sr.Name);
        path := TempFile(sr.Name, orig);
        FreeAndNil(FRich);
        FRich := NewProbe;
        FRich.LoadFromFile(path);
        FRich.UpdateView;
        ms := TMemoryStream.Create;
        try
          FRich.SaveToStream(ms);
          AssertTrue(sr.Name + ': saved as it came', SameBytes(orig, StreamBytes(ms)));
          FRich.SaveToFile(path);
          AssertTrue(sr.Name + ': saved over its file', SameBytes(orig, FileBytes(path)));
          ms.Clear;
          FRich.UpdateView;
          FRich.ScrollToEnd;
          FRich.UpdateView;
          FRich.SaveToStream(ms);
          AssertTrue(sr.Name + ': and still reads', SameBytes(orig, StreamBytes(ms)));
        finally
          ms.Free;
        end;
        Inc(count);
      until FindNext(sr) <> 0;
    finally
      FindClose(sr);
    end;
  AssertTrue(Format('the fixtures (%d)', [count]), count >= 50);
end;

procedure TTyRichEditControlTest.TestACancelledSaveLeavesTheFileAsItWas;
var
  b: TBytes;
  paras: Integer;
  path: string;
  raised: Boolean;
  sr: TSearchRec;
  files: Integer;
begin
  b := GeneratedRtf(2 * 1024 * 1024, paras);
  path := TempFile('save.rtf', b);
  FRich.LoadFromFile(path);
  FRich.FinishLoading;
  AssertTrue('changed', FRich.Document.Execute(TTyRichInsertText.Create(0, 'New ')));
  AssertTrue('modified', FRich.Modified);
  FRich.OnSaveProgress := @SaveCancel;
  raised := False;
  try
    FRich.SaveToFile(path);
  except
    on E: ETyRichSaveCancelled do raised := True;
  end;
  AssertTrue('the save was cancelled', raised);
  AssertTrue('asked', FLoadCalls > 0);
  AssertTrue('the file is as it was', SameBytes(b, FileBytes(path)));
  AssertTrue('still modified', FRich.Modified);
  files := 0;
  if FindFirst(FTemp + '*', faAnyFile, sr) = 0 then
  try
    repeat
      if (sr.Attr and faDirectory) = 0 then Inc(files);
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
  AssertEquals('no temporary file left', 1, files);
  // a save that completes replaces it
  FRich.OnSaveProgress := nil;
  FRich.SaveToFile(path);
  AssertFalse('saved', FRich.Modified);
  AssertFalse('the new content', SameBytes(b, FileBytes(path)));
end;

{ A width change and a zoom change make every height an estimate again, lay out only the view
  again, and keep its first paragraph on screen. }
procedure TTyRichEditControlTest.TestAWidthOrZoomChangeLaysOutOnlyTheViewAgain;
var
  sl: TStringList;
  i, n, anchor: Integer;
  s: string;
begin
  sl := TStringList.Create;
  try
    s := '';
    for i := 1 to 12 do s := s + 'text' + IntToStr(i) + ' ';
    for i := 0 to 2999 do sl.Add(IntToStr(i) + ' ' + s);
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.UpdateView;
  FRich.ScrollY := FRich.Document.Text.TotalHeight div 2;
  FRich.UpdateView;
  anchor := FRich.TopParagraph;
  AssertTrue('in the middle', (anchor > 1000) and (anchor < 2000));
  n := ScreenLines;
  FRich.ResetCounts;
  FRich.Width := 300;
  FRich.UpdateView;
  AssertTrue(Format('a width change lays out %d', [FRich.LaidParas]),
    (FRich.LaidParas > 0) and (FRich.LaidParas <= 3 * n + 2));
  AssertEquals('the same first paragraph', anchor, FRich.TopParagraph);
  AssertTrue('on screen', InView(anchor));
  FRich.ResetCounts;
  FRich.Zoom := 150;
  FRich.UpdateView;
  n := ScreenLines;
  AssertTrue(Format('a zoom change lays out %d', [FRich.LaidParas]),
    (FRich.LaidParas > 0) and (FRich.LaidParas <= 3 * n + 2));
  AssertEquals('the same first paragraph again', anchor, FRich.TopParagraph);
  AssertTrue('on screen again', InView(anchor));
  AssertTrue('measured only around it', FRich.Document.Text.MeasuredParaCount <= 3 * n + 2);
end;

procedure TTyRichEditControlTest.TestARowsHeightGoesOnItsFirstParagraph;
var
  k, p, rows: Integer;
  blk: TTyRichViewBlock;
  t: TTyRichText;
begin
  FRich.LoadFromFile(FixtureDir('rtf') + 're-zh-table.rtf');
  FRich.UpdateView;
  t := FRich.Document.Text;
  rows := 0;
  for k := 0 to FRich.VisibleBlockCount - 1 do
  begin
    blk := FRich.VisibleBlocks[k];
    if not (blk.Layout is TTyRowLayout) or (blk.LastPara = blk.FirstPara) then Continue;
    Inc(rows);
    AssertTrue('the row''s first paragraph is measured', t.ParaMeasured(blk.FirstPara));
    AssertEquals('with the row''s height', Int64(blk.Height), t.ParaHeight(blk.FirstPara));
    for p := blk.FirstPara + 1 to blk.LastPara do
    begin
      AssertTrue('the others are measured', t.ParaMeasured(p));
      AssertEquals('as nothing', Int64(0), t.ParaHeight(p));
    end;
  end;
  AssertTrue('rows of several paragraphs seen', rows > 0);
end;

procedure TTyRichEditControlTest.TestNoWrapExtentGrowsWithWhatWasSeen;
var
  sl: TStringList;
  i, e1: Integer;
begin
  sl := TStringList.Create;
  try
    for i := 0 to 299 do
      if i = 150 then sl.Add(StringOfChar('x', 200)) else sl.Add('short');
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.WrapMode := rwmNone;
  FRich.UpdateView;
  e1 := FRich.HorizontalExtent;
  AssertTrue(Format('the extent is what was seen (%d)', [e1]), (e1 > 0) and (e1 < 100));
  AssertTrue('no horizontal bar', (FRich.HBar = nil) or not FRich.HBar.Visible);
  FRich.ScrollY := FRich.Document.Text.ParaTop(150);
  FRich.UpdateView;
  AssertTrue(Format('it grew with the long line (%d)', [FRich.HorizontalExtent]),
    FRich.HorizontalExtent >= 1200);
  AssertTrue('a horizontal bar', (FRich.HBar <> nil) and FRich.HBar.Visible);
  AssertEquals('its range', FRich.HorizontalExtent - (FRich.Area.Right - FRich.Area.Left),
    FRich.HBar.Max);
  FRich.ScrollToTop;
  FRich.UpdateView;
  AssertTrue('it does not shrink', FRich.HorizontalExtent >= 1200);
end;

procedure TTyRichEditControlTest.TestLinesReadTheDocumentWithoutCopyingIt;
var
  heap0, heap1: PtrUInt;
  visits: Int64;
  n: Integer;
  s, last: string;
begin
  LoadBig;
  visits := FRich.Document.Text.NodeVisits;
  heap0 := GetFPCHeapStatus.CurrHeapUsed;
  n := FRich.Lines.Count;
  s := FRich.Lines[1000000];
  last := FRich.Lines[n - 1];
  heap1 := GetFPCHeapStatus.CurrHeapUsed;
  AssertEquals('a line a paragraph', BigLines, n);
  AssertEquals('the middle line', 'Line 1000001', s);
  AssertEquals('the last line', 'Line 2000000', last);
  AssertTrue(Format('no copy of the lines (%d bytes)', [Int64(heap1) - Int64(heap0)]),
    Int64(heap1) - Int64(heap0) < 4096);
  AssertTrue(Format('a few descents (%d nodes)', [FRich.Document.Text.NodeVisits - visits]),
    FRich.Document.Text.NodeVisits - visits < 200);
end;

procedure TTyRichEditControlTest.TestAssigningLinesReplacesTheContent;
begin
  AssertEquals('an empty control has no lines', 0, FRich.Lines.Count);
  FRich.Lines.Text := 'first'#13#10'second'#13#10;
  AssertEquals('two lines', 2, FRich.Lines.Count);
  AssertEquals('two paragraphs', 2, FRich.Document.Text.ParaCount);
  AssertEquals('the second', 'second', FRich.Lines[1]);
  AssertTrue('read-only to the user', FRich.ReadOnly);
  FRich.Lines.Add('third');
  AssertEquals('added', 3, FRich.Lines.Count);
  AssertEquals('at the end', 'third', FRich.Lines[2]);
  AssertTrue('a command: it can be undone', FRich.Document.CanUndo);
  FRich.Lines.Insert(0, 'zero');
  AssertEquals('inserted', 'zero', FRich.Lines[0]);
  FRich.Lines[1] := 'FIRST';
  AssertEquals('replaced', 'FIRST', FRich.Lines[1]);
  FRich.Lines.Delete(3);
  AssertEquals('deleted the last', 3, FRich.Lines.Count);
  AssertEquals('the text', 'zero'#10'FIRST'#10'second', StringReplace(
    StringReplace(FRich.Document.Text.GetText(0, FRich.Document.Text.Length), #13#10, #10,
    [rfReplaceAll]), #13, #10, [rfReplaceAll]));
  FRich.Lines.Text := 'only';
  AssertEquals('assigning replaces', 1, FRich.Lines.Count);
  AssertFalse('a replacement is no undo step', FRich.Document.CanUndo);
  FRich.Lines.Clear;
  AssertEquals('cleared', 0, FRich.Lines.Count);
end;

procedure TTyRichEditControlTest.TestLinesGoIntoTheFormFileOnlyWhenSetThroughThem;
var
  a, b: TTyRichEdit;
  ms, txt: TMemoryStream;
  st: TBytesStream;
  text: string;
begin
  a := TTyRichEdit.Create(nil);
  b := TTyRichEdit.Create(nil);
  ms := TMemoryStream.Create;
  txt := TMemoryStream.Create;
  try
    a.Lines.Text := 'first'#13#10'second';
    ms.WriteComponent(a);
    ms.Position := 0;
    ObjectBinaryToText(ms, txt);
    SetString(text, PChar(txt.Memory), txt.Size);
    AssertTrue('the lines are in the form file', Pos('Lines.Strings', text) > 0);
    ms.Position := 0;
    ms.ReadComponent(b);
    AssertEquals('read back', 2, b.Lines.Count);
    AssertEquals('the first', 'first', b.Lines[0]);
    AssertEquals('the second', 'second', b.Lines[1]);
    AssertFalse('read as one replacement, not line by line as commands', b.Document.CanUndo);
    // a file loaded at run time is not stored
    st := TBytesStream.Create(BytesOf('loaded'#13#10'text'));
    try
      a.LoadFromStream(st);
    finally
      st.Free;
    end;
    ms.Clear;
    txt.Clear;
    ms.WriteComponent(a);
    ms.Position := 0;
    ObjectBinaryToText(ms, txt);
    SetString(text, PChar(txt.Memory), txt.Size);
    AssertFalse('a loaded file is not', Pos('Lines.Strings', text) > 0);
    // nor an empty control
    a.Lines.Clear;
    ms.Clear;
    txt.Clear;
    ms.WriteComponent(a);
    ms.Position := 0;
    ObjectBinaryToText(ms, txt);
    SetString(text, PChar(txt.Memory), txt.Size);
    AssertFalse('nor no lines', Pos('Lines', text) > 0);
  finally
    txt.Free;
    ms.Free;
    b.Free;
    a.Free;
  end;
end;

{ A document taller than the scroll bar's range is scrolled in steps of several pixels, and the
  bar's end is the last line. }
procedure TTyRichEditControlTest.TestATallDocumentScrollsToItsLastLine;
var
  sl: TStringList;
  i, last: Integer;
begin
  FRich.BarLimit := 1000;
  sl := TStringList.Create;
  try
    for i := 0 to 4999 do sl.Add('Line ' + IntToStr(i));
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.UpdateView;
  AssertTrue('within the range', (FRich.VBar.Max > 0) and (FRich.VBar.Max <= 1000));
  FRich.VBar.Position := FRich.VBar.Max div 2;
  FRich.UpdateView;
  AssertTrue(Format('the middle (%d)', [FRich.TopParagraph]),
    Abs(FRich.TopParagraph - 2500) < 50);
  FRich.VBar.Position := FRich.VBar.Max;
  FRich.UpdateView;
  AssertTrue('the last line is on screen', InView(4999));
  AssertTrue('at the bottom', FRich.ParagraphRect(4999).Bottom <= FRich.Area.Bottom);
  AssertEquals('the bar at its end', FRich.VBar.Max, FRich.VBar.Position);
  // two million lines at 500 %
  FreeAndNil(FRich);
  FRich := NewProbe;
  LoadBig;
  FRich.Zoom := 500;
  FRich.UpdateView;
  last := BigLines - 1;
  FRich.VBar.Position := FRich.VBar.Max;
  FRich.UpdateView;
  AssertTrue('the last of two million lines is on screen', InView(last));
  FRich.VBar.Position := 0;
  FRich.UpdateView;
  AssertEquals('and back to the first', 0, FRich.TopParagraph);
end;

procedure TTyRichEditControlTest.TestAPaintDrawsOnlyTheBlocksInItsClip;
var
  sl: TStringList;
  i, all: Integer;
  bmp: TBitmap;
begin
  sl := TStringList.Create;
  try
    for i := 0 to 99 do sl.Add('Line ' + IntToStr(i));
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.UpdateView;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(400, 300);
    FRich.Device.ResetCounters;
    FRich.PaintPart(bmp.Canvas, Rect(0, 0, 400, 300), False);
    all := FRich.Device.DrawCalls;
    AssertTrue(Format('a screen of lines (%d)', [all]), all >= ScreenLines - 2);
    FRich.Device.ResetCounters;
    FRich.PaintPart(bmp.Canvas, Rect(0, 0, 400, 300), True);
    AssertEquals('nothing dirty draws nothing', 0, FRich.Device.DrawCalls);
    FRich.InvalidatePart(FRich.ParagraphRect(5));
    FRich.PaintPart(bmp.Canvas, Rect(0, 0, 400, 300), True);
    AssertEquals('one paragraph dirty draws its one line', 1, FRich.Device.DrawCalls);
  finally
    bmp.Free;
  end;
end;

{ R35: a paint while scrolling decodes no picture: it leaves an empty box and the picture to
  the background work, which makes it ready and invalidates only its box. Pictures in the
  blocks laid out ahead of the view wait there too. }
procedure TTyRichEditControlTest.TestADeferredPaintLeavesPicturesForLater;
var
  d: TTyRichDocument;
  lo: TTyRichLayouter;
  L: TTyBlockLayout;
  st: TTyRichPaintStyle;
  bmp: TBGRABitmap;
  sk: TTyRichSkippedPictures;
  pic: TTyRichPicture;
  box: TRect;
  sl: TStringList;
  i, decodes: Integer;
  canvasBmp: TBitmap;
  t: TTyRichText;
begin
  // the layouter by itself
  d := TTyRichDocument.CreateFromUtf8(BytesOf('a b'));
  lo := TTyRichLayouter.Create(TTyRichTestDevice.Create, True);
  bmp := TBGRABitmap.Create(200, 100, Sentinel);
  try
    pic := TTyRichPicture.Create(rpfPng, PngBytes(20, 10, BGRA(0, 200, 0, 255)), 600, 300);
    AssertTrue('a picture', d.Execute(TTyRichInsertObject.Create(1, pic)));
    L := lo.LayoutBlock(d, 0, 200, 96, 1);
    try
      st := TyRichDefaultPaintStyle;
      st.PlaceholderFill := BGRA(10, 20, 30, 255);
      st.DeferPictures := True;
      L.Paint(bmp, 0, 0, Rect(0, 0, 200, 100), st, 0, 0);
      AssertEquals('nothing decoded', 0, lo.PictureDecodes);
      AssertEquals('one passed over', 1, lo.SkippedPictureCount);
      sk := lo.TakeSkippedPictures;
      AssertEquals('reported', 1, Length(sk));
      box := sk[0].Box;
      AssertEquals('its box (40 x 20 at 96 PPI)', 40, box.Right - box.Left);
      AssertTrue('an empty box there', SamePx(st.PlaceholderFill,
        bmp.GetPixel(box.Left + 5, box.Top + 5)));
      AssertFalse('not ready', lo.PictureReady(sk[0].Picture, 40, 20));
      lo.PreparePicture(sk[0].Picture, 40, 20);
      AssertEquals('decoded when prepared', 1, lo.PictureDecodes);
      AssertTrue('ready', lo.PictureReady(sk[0].Picture, 40, 20));
      sk[0].Picture.Release;
      L.Paint(bmp, 0, 0, Rect(0, 0, 200, 100), st, 0, 0);
      AssertEquals('none passed over now', 0, lo.SkippedPictureCount);
      AssertEquals('no second decode', 1, lo.PictureDecodes);
      AssertTrue('the picture drawn', SamePx(BGRA(0, 200, 0, 255),
        bmp.GetPixel(box.Left + 5, box.Top + 5)));
    finally
      L.Release;
    end;
  finally
    bmp.Free;
    lo.Free;
    d.Free;
  end;
  // the control: a paint of the window leaves it to the background work
  sl := TStringList.Create;
  try
    for i := 0 to 199 do sl.Add('Line ' + IntToStr(i));
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  t := FRich.Document.Text;
  pic := TTyRichPicture.Create(rpfPng, PngBytes(20, 10, BGRA(0, 0, 200, 255)), 600, 300);
  AssertTrue('a picture on screen', FRich.Document.Execute(TTyRichInsertObject.Create(
    t.ParaStart(2), pic)));
  pic := TTyRichPicture.Create(rpfPng, PngBytes(20, 10, BGRA(200, 0, 0, 255)), 600, 300);
  AssertTrue('one a screen below', FRich.Document.Execute(TTyRichInsertObject.Create(
    t.ParaStart(ScreenLines + 10), pic)));
  FRich.UpdateView;
  AssertEquals('the one ahead waits before any paint', 1, FRich.Pending);
  canvasBmp := TBitmap.Create;
  try
    canvasBmp.PixelFormat := pf32bit;
    canvasBmp.SetSize(400, 300);
    FRich.PaintPart(canvasBmp.Canvas, Rect(0, 0, 400, 300), True);
    AssertEquals('the paint decoded nothing', 0, FRich.Layouter.PictureDecodes);
    AssertEquals('and left the one it met', 2, FRich.Pending);
    FRich.ResetCounts;
    AssertTrue('one piece of work', FRich.Step);
    AssertEquals('one decoded', 1, FRich.Layouter.PictureDecodes);
    AssertEquals('the one ahead invalidates nothing on screen', 0, Length(FRich.Invalidated));
    AssertTrue('the next', FRich.Step);
    AssertEquals('both decoded', 2, FRich.Layouter.PictureDecodes);
    AssertEquals('its box invalidated', 1, Length(FRich.Invalidated));
    AssertEquals('only its box', 20, FRich.Invalidated[0].Bottom - FRich.Invalidated[0].Top);
    AssertFalse('nothing left', FRich.Step);
    FRich.PaintPart(canvasBmp.Canvas, Rect(0, 0, 400, 300), True);
    AssertEquals('drawn now, nothing left over', 0, FRich.Pending);
    // a zoom makes it not ready at its new size: the same way again
    decodes := FRich.Layouter.PictureDecodes;
    FRich.Zoom := 200;
    FRich.PaintPart(canvasBmp.Canvas, Rect(0, 0, 400, 300), True);
    AssertTrue('waiting at the new size', FRich.Pending >= 1);
    AssertEquals('nothing decoded by the paint', decodes, FRich.Layouter.PictureDecodes);
  finally
    canvasBmp.Free;
  end;
end;

procedure TTyRichEditControlTest.TestKeysAndWheelScrollAndZoom;
var
  sl: TStringList;
  i, est, perNotch: Integer;
  y0: Int64;
begin
  sl := TStringList.Create;
  try
    for i := 0 to 999 do sl.Add('Line ' + IntToStr(i));
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.UpdateView;
  est := FRich.Layouter.EstimatedParaHeight(96, 1);
  FRich.Press(VK_NEXT, []);
  FRich.UpdateView;
  AssertTrue('page down', FRich.ScrollY >= FRich.Area.Bottom - FRich.Area.Top - 2 * est);
  y0 := FRich.ScrollY;
  FRich.Press(VK_PRIOR, []);
  FRich.UpdateView;
  AssertEquals('page up', Int64(0), FRich.ScrollY);
  FRich.Press(VK_END, [ssCtrl]);
  FRich.UpdateView;
  AssertTrue('Ctrl+End: the last line', InView(999));
  FRich.Press(VK_HOME, [ssCtrl]);
  FRich.UpdateView;
  AssertEquals('Ctrl+Home: the first', Int64(0), FRich.ScrollY);
  FRich.Wheel(-120, []);
  FRich.UpdateView;
  perNotch := Mouse.WheelScrollLines;
  if perNotch > 0 then
    AssertEquals('a notch down', Int64(perNotch * est), FRich.ScrollY)
  else
    AssertTrue('a notch down', FRich.ScrollY > 0);
  AssertTrue('paging moved further than a notch', y0 > 0);
  FRich.Wheel(120, [ssCtrl]);
  AssertEquals('Ctrl+wheel zooms in', 110, FRich.Zoom);
  FRich.Wheel(-240, [ssCtrl]);
  AssertEquals('and out, a notch a step', 90, FRich.Zoom);
end;

procedure TTyRichEditControlTest.TestReadOnlyStaysOnAndCodeStillChanges;
begin
  FRich.Lines.Text := 'text';
  AssertTrue('read-only', FRich.ReadOnly);
  FRich.ReadOnly := False;
  AssertTrue('stays read-only in this version', FRich.ReadOnly);
  AssertTrue('code still changes the document',
    FRich.Document.Execute(TTyRichInsertText.Create(0, 'more ')));
  AssertEquals('changed', 'more text', FRich.Lines[0]);
end;

{ ---- Task 9a2: the review of 9a (reviewB-H1) ---- }

procedure TTyRichEditControlTest.SetLinesOf(ACount: Integer; const APrefix: string);
var
  sl: TStringList;
  i: Integer;
begin
  sl := TStringList.Create;
  try
    for i := 0 to ACount - 1 do sl.Add(APrefix + IntToStr(i));
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
end;

{ Every pixel of ARect lies in one of the rectangles invalidated since the last ResetCounts. }
function TTyRichEditControlTest.Covered(const ARect: TRect): Boolean;
var
  x, y, i: Integer;
  hit: Boolean;
begin
  Result := False;
  if (ARect.Right <= ARect.Left) or (ARect.Bottom <= ARect.Top) then Exit;
  y := ARect.Top;
  while y < ARect.Bottom do
  begin
    x := ARect.Left;
    while x < ARect.Right do
    begin
      hit := False;
      for i := 0 to High(FRich.Invalidated) do
        if PtInRect(FRich.Invalidated[i], Point(x, y)) then
        begin
          hit := True;
          Break;
        end;
      if not hit then Exit;
      Inc(x, Math.Max(1, (ARect.Right - ARect.Left) div 7));
    end;
    Inc(y);
  end;
  Result := True;
end;

procedure TTyRichEditControlTest.PaintAll(ADefer: Boolean);
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width, FRich.Height);
    FRich.PaintPart(bmp.Canvas, Rect(0, 0, FRich.Width, FRich.Height), ADefer);
  finally
    bmp.Free;
  end;
end;

procedure TTyRichEditControlTest.ReplaceInHandler(Sender: TObject; ADone, ATotal: Int64;
  var ACancel: Boolean);
begin
  Inc(FLoadCalls);
  try
    FRich.Lines.Text := 'another document';
  except
    on E: ETyRichEdit do Inc(FRefused);
  end;
  try
    FRich.LoadFromStream(FOther);
  except
    on E: ETyRichEdit do Inc(FRefused);
  end;
end;

procedure TTyRichEditControlTest.CancelInHandler(Sender: TObject; ADone, ATotal: Int64;
  var ACancel: Boolean);
begin
  Inc(FLoadCalls);
  FRich.CancelLoad;
end;

procedure TTyRichEditControlTest.NoFallback(Sender: TObject; const ABaseFont: string;
  ACode: Cardinal; var AFontName: string);
begin
end;

{ H-C1: five paragraphs of 60 words - one line each by the estimate, taller than the view
  laid out. The bar comes and stays; a second pass does nothing. A document that fits has
  none; one that fits only without the bar settles without it. }
procedure TTyRichEditControlTest.TestAShortWrappedDocumentSettlesItsScrollBar;
var
  sl: TStringList;
  s, txt: string;
  i, k, barW, wide, narrow, lineH, m: Integer;
  lo: TTyRichLayouter;
  d: TTyRichDocument;
  L1, L2: TTyBlockLayout;
  found: Boolean;
begin
  sl := TStringList.Create;
  try
    s := '';
    for i := 1 to 60 do s := s + 'word' + IntToStr(i mod 7) + ' ';
    for i := 0 to 4 do sl.Add(IntToStr(i) + ' ' + s);
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  AssertTrue('the estimate fits the view', 5 * FRich.Layouter.EstimatedParaHeight(96, 1) <
    FRich.Area.Bottom - FRich.Area.Top);
  FRich.UpdateView;
  AssertTrue('the bar is shown', (FRich.VBar <> nil) and FRich.VBar.Visible);
  AssertTrue('the text is taller than the view',
    FRich.Document.Text.TotalHeight > FRich.Area.Bottom - FRich.Area.Top);
  barW := FRich.VBar.Width;
  FRich.ResetCounts;
  FRich.UpdateView;
  AssertEquals('settled: nothing invalidated', 0, Length(FRich.Invalidated));
  AssertEquals('settled: nothing laid out', 0, FRich.LaidParas);
  AssertTrue('the bar stays', FRich.VBar.Visible);
  // a document that fits
  FRich.Lines.Text := 'one'#13#10'two';
  FRich.UpdateView;
  AssertFalse('no bar', FRich.VBar.Visible);
  FRich.ResetCounts;
  FRich.UpdateView;
  AssertEquals('nothing invalidated again', 0, Length(FRich.Invalidated));
  AssertEquals('nothing laid out again', 0, FRich.LaidParas);
  { One that fits only without the bar: paragraphs of one line at the full width that wrap
    at the width the bar leaves, as many as the view holds at one line each. }
  wide := TyRichLayoutWidth(rwmWindow, FRich.Area.Right - FRich.Area.Left, FRich.Document, 96, 1);
  narrow := TyRichLayoutWidth(rwmWindow, FRich.Area.Right - FRich.Area.Left - barW,
    FRich.Document, 96, 1);
  lo := TTyRichLayouter.Create(TTyRichTestDevice.Create, True);
  try
    txt := '';
    found := False;
    lineH := 0;
    for k := 1 to 300 do
    begin
      txt := txt + 'ab ';
      d := TTyRichDocument.CreateFromUtf8(BytesOf(txt));
      try
        L1 := lo.LayoutBlock(d, 0, wide, 96, 1);
        L2 := lo.LayoutBlock(d, 0, narrow, 96, 1);
        try
          found := (TTyParaLayout(L1).LineCount = 1) and (TTyParaLayout(L2).LineCount = 2);
          lineH := L1.Height;
        finally
          L1.Release;
          L2.Release;
        end;
      finally
        lo.Document := nil;
        d.Free;
      end;
      if found then Break;
    end;
  finally
    lo.Free;
  end;
  AssertTrue('a text that wraps only at the narrower width', found);
  m := (FRich.Area.Bottom - FRich.Area.Top) div lineH;
  sl := TStringList.Create;
  try
    for i := 1 to m do sl.Add(txt);
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.UpdateView;
  AssertFalse('it fits at the full width: it settles without the bar', FRich.VBar.Visible);
  AssertEquals('every line on screen', m - 1, FRich.VisibleBlocks[FRich.VisibleBlockCount - 1].LastPara);
  FRich.ResetCounts;
  FRich.UpdateView;
  AssertEquals('and stays so: nothing invalidated', 0, Length(FRich.Invalidated));
  AssertEquals('nothing laid out', 0, FRich.LaidParas);
end;

{ H-I1: a change made while the view waits for its next layout is painted too. }
procedure TTyRichEditControlTest.TestAChangeWhileTheViewIsInvalidIsPainted;
var
  f: TTyCharFormat;
  t: TTyRichText;
  r3, r5: TRect;
begin
  SetLinesOf(200, 'Line ');
  FRich.UpdateView;
  t := FRich.Document.Text;
  r3 := FRich.ParagraphRect(3);
  FRich.ResetCounts;
  f := TyDefaultCharFormat;
  f.SizeHalfPt := 48;
  AssertTrue('a taller paragraph 7', FRich.Document.Execute(TTyRichSetCharFormat.Create(
    TyRichRange(t.ParaStart(7), t.ParaLength(7)), [cffSize], f)));
  f.Color := clRed;
  AssertTrue('then a colour in paragraph 3', FRich.Document.Execute(TTyRichSetCharFormat.Create(
    TyRichRange(t.ParaStart(3), t.ParaLength(3)), [cffColor], f)));
  AssertTrue('paragraph 3 is painted again', Covered(r3));
  { A paragraph added above while the view still waits: the held blocks below it moved down
    (their layouts are not stale), so they are painted again too. }
  FRich.UpdateView;
  r5 := FRich.ParagraphRect(5);
  FRich.ResetCounts;
  AssertTrue('a taller paragraph 9', FRich.Document.Execute(TTyRichSetCharFormat.Create(
    TyRichRange(t.ParaStart(9), t.ParaLength(9)), [cffSize], f)));
  FRich.Lines.Insert(3, 'new');
  AssertTrue('what moved down is painted again', Covered(r5));
end;

{ H-I2: the end's pull-up moves every block: the whole text area is painted again. }
procedure TTyRichEditControlTest.TestALayoutThatMovesTheViewRepaintsIt;
var
  sl: TStringList;
  i: Integer;
  s: string;
  t: TTyRichText;
  r0: TRect;
begin
  sl := TStringList.Create;
  try
    for i := 0 to 198 do sl.Add('Line ' + IntToStr(i));
    s := '';
    for i := 1 to 60 do s := s + 'word' + IntToStr(i mod 7) + ' ';
    sl.Add(s);
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.UpdateView;
  FRich.ScrollToEnd;
  FRich.UpdateView;
  t := FRich.Document.Text;
  r0 := FRich.ParagraphRect(195);
  FRich.ResetCounts;
  AssertTrue('the last paragraph cut to a line', FRich.Document.Execute(TTyRichDelete.Create(
    t.ParaStart(199) + 5, t.ParaLength(199) - 5)));
  FRich.UpdateView;
  AssertTrue('the text moved down', FRich.ParagraphRect(195).Top > r0.Top);
  AssertTrue('the whole text area is painted again', Covered(FRich.Area));
end;

{ H-I3: one change of 20,000 paragraphs into the view, and a load step that appends many
  below a short first slice, lay out no more than the view and two screens. }
procedure TTyRichEditControlTest.TestAChangeOfManyParagraphsLaysOutOnlyTheView;
var
  s: UTF8String;
  i, n, laid, first, paras: Integer;
  t: TTyRichText;
  b: TBytes;
  st: TBytesStream;
begin
  FRich.Lines.Text := 'one'#10'two'#10'three';
  FRich.UpdateView;
  t := FRich.Document.Text;
  s := '';
  for i := 1 to 20000 do s := s + 'x'#10;
  FRich.ResetCounts;
  AssertTrue('inserted', FRich.Document.Execute(TTyRichInsertText.Create(t.ParaStart(1), s)));
  n := ScreenLines;
  laid := FRich.LaidParas;
  AssertTrue(Format('laid out inside the change: %d (a screen is %d lines)', [laid, n]),
    laid <= 3 * n + 2);
  // (the bar the change brings narrows the text: the next pass lays the view out afresh)
  FRich.ResetCounts;
  AssertTrue(Format('held: %d', [FRich.VisibleBlockCount]), FRich.VisibleBlockCount <= 3 * n + 2);
  AssertTrue(Format('and the view after: %d', [FRich.LaidParas]), FRich.LaidParas <= 3 * n + 2);
  // a lazy load: a first slice of a few paragraphs, a step of many
  FreeAndNil(FRich);
  FRich := NewProbe;
  b := GeneratedRtf(512 * 1024, paras);
  FRich.Slices(300, 128 * 1024);
  st := TBytesStream.Create(b);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.UpdateView;
  first := FRich.Document.Text.ParaCount;
  AssertTrue(Format('a short first slice (%d)', [first]), first < 10);
  FRich.ResetCounts;
  AssertTrue('a step', FRich.Step);
  n := ScreenLines;
  AssertTrue(Format('the step brought many (%d)', [FRich.Document.Text.ParaCount]),
    FRich.Document.Text.ParaCount > first + 10 * n);
  AssertTrue(Format('laid out in the step: %d', [FRich.LaidParas]), FRich.LaidParas <= 3 * n + 2);
end;

{ H-I4: an item of a numbered list loses its number: the items after it, numbered again by the
  layouter, are laid out again and painted. }
procedure TTyRichEditControlTest.TestNumbersAfterAChangedItemAreRepainted;
var
  pf: TTyParaFormat;
  r: array[0..9] of TRect;
  i, k: Integer;
begin
  SetLinesOf(10, 'Item ');
  pf := TyDefaultParaFormat;
  pf.List.Kind := lkDecimal;
  pf.List.Level := 0;
  pf.List.StartAt := 1;
  AssertTrue('numbered', FRich.Document.Execute(TTyRichSetParaFormat.Create(0, 9, [pffList], pf)));
  FRich.UpdateView;
  for i := 0 to 9 do r[i] := FRich.ParagraphRect(i);
  FRich.ResetCounts;
  pf.List.Kind := lkNone;
  AssertTrue('item 2 unnumbered', FRich.Document.Execute(TTyRichSetParaFormat.Create(2, 2,
    [pffList], pf)));
  for i := 3 to 9 do
    AssertTrue(Format('item %d painted again', [i]), Covered(r[i]));
  for k := 0 to FRich.VisibleBlockCount - 1 do
    AssertFalse(Format('block %d is current', [k]), FRich.VisibleBlocks[k].Layout.Stale);
end;

{ H-I5: the queries lay the view out first; ScrollToEnd puts the anchor where the end is. }
procedure TTyRichEditControlTest.TestQueriesSettleTheViewFirst;
var
  a, b, c: TTyRichPos;
  y0: Int64;
  f: TTyCharFormat;
  t: TTyRichText;
  r: TRect;
  h, i: Integer;
  sl: TStringList;
  s: string;
begin
  SetLinesOf(1000, 'Line ');
  FRich.UpdateView;
  h := FRich.Area.Bottom - FRich.Area.Top;
  a := FRich.PositionAtPoint(20, 20);
  FRich.ScrollViewBy(1000);
  b := FRich.PositionAtPoint(20, 20);
  FRich.UpdateView;
  c := FRich.PositionAtPoint(20, 20);
  AssertTrue('moved', b > a);
  AssertEquals('right after the scroll as after a layout', c, b);
  FRich.ScrollToEnd;
  AssertEquals('ScrollY at the end, as the heights say', FRich.Document.Text.TotalHeight - h,
    FRich.ScrollY);
  FRich.ScrollToEnd;
  y0 := FRich.ScrollY;
  FRich.ScrollToEnd;
  FRich.ScrollViewBy(-100);
  AssertEquals('Ctrl+End then up before a paint moves', y0 - 100, FRich.ScrollY);
  // a taller paragraph above the view: hit tests and rectangles follow before any paint
  FRich.ScrollY := FRich.Document.Text.ParaTop(500);
  FRich.UpdateView;
  r := FRich.ParagraphRect(500);
  t := FRich.Document.Text;
  f := TyDefaultCharFormat;
  f.SizeHalfPt := 48;
  AssertTrue('above', FRich.Document.Execute(TTyRichSetCharFormat.Create(
    TyRichRange(t.ParaStart(495), t.ParaLength(495)), [cffSize], f)));
  AssertTrue('the first line stays where it was', EqualRect(r, FRich.ParagraphRect(500)));
  AssertEquals('and is what a point there hits', t.ParaStart(500),
    FRich.PositionAtPoint(FRich.Area.Left, r.Top + 1));
  { ScrollY after a jump into paragraphs taller than their estimates: what the laid out view
    says at once, not the estimates' sum. }
  sl := TStringList.Create;
  try
    s := '';
    for i := 1 to 50 do s := s + 'word' + IntToStr(i mod 7) + ' ';
    for i := 0 to 399 do sl.Add(IntToStr(i) + ' ' + s);
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.ScrollY := Int64(200) * FRich.Layouter.EstimatedParaHeight(96, 1);
  y0 := FRich.ScrollY;
  FRich.UpdateView;
  AssertEquals('ScrollY is the laid out view''s', FRich.ScrollY, y0);
end;

{ H-I6: a progress handler that replaces the content is refused; one that cancels stops the
  load cleanly; a save's handler cannot replace the content either. }
procedure TTyRichEditControlTest.TestProgressHandlersCannotReplaceTheContent;
var
  b: TBytes;
  paras: Integer;
  st: TBytesStream;
  ms: TMemoryStream;
begin
  b := GeneratedRtf(2 * 1024 * 1024, paras);
  FOther := TBytesStream.Create(BytesOf('other'));
  try
    FRich.Slices(64 * 1024, 64 * 1024);
    FRich.OnLoadProgress := @ReplaceInHandler;
    st := TBytesStream.Create(b);
    try
      FRich.LoadFromStream(st);
    finally
      st.Free;
    end;
    AssertTrue('a step', FRich.Step);
    FRich.FinishLoading;
    AssertTrue('the handler ran', FLoadCalls > 0);
    AssertEquals('every replacement refused', 2 * FLoadCalls, FRefused);
    AssertFalse('the load completed', FRich.Loading);
    AssertFalse('complete', FRich.Incomplete);
    AssertEquals('every paragraph of it', paras, FRich.Document.Text.ParaCount);
    // a handler that cancels
    FreeAndNil(FRich);
    FRich := NewProbe;
    FLoadCalls := 0;
    FRich.Slices(64 * 1024, 64 * 1024);
    FRich.OnLoadProgress := @CancelInHandler;
    st := TBytesStream.Create(b);
    try
      FRich.LoadFromStream(st);
    finally
      st.Free;
    end;
    AssertTrue('a step', FRich.Step);
    AssertEquals('asked once', 1, FLoadCalls);
    AssertFalse('stopped', FRich.Loading);
    AssertTrue('incomplete', FRich.Incomplete);
    FRich.UpdateView;
    AssertTrue('still shown', FRich.VisibleBlockCount > 0);
    // a save's handler
    FreeAndNil(FRich);
    FRich := NewProbe;
    FRefused := 0;
    FLoadCalls := 0;
    // the writer asks every 256 KB
    SetLinesOf(30000, 'kept ');
    FRich.OnSaveProgress := @SaveReplace;
    ms := TMemoryStream.Create;
    try
      FRich.SaveToStream(ms, rfRtf);
      AssertTrue('saved', ms.Size > 0);
    finally
      ms.Free;
    end;
    AssertTrue('the handler ran', FLoadCalls > 0);
    AssertEquals('refused', FLoadCalls, FRefused);
    AssertEquals('the content stays', 'kept 0', FRich.Lines[0]);
  finally
    FreeAndNil(FOther);
  end;
end;

procedure TTyRichEditControlTest.SaveReplace(Sender: TObject; ADone, ATotal: Int64;
  var ACancel: Boolean);
begin
  Inc(FLoadCalls);
  try
    FRich.Lines.Text := 'replaced';
  except
    on E: ETyRichEdit do Inc(FRefused);
  end;
end;

{ One picture in the view of 'a b': painted (deferred), made ready, painted again. }
procedure TTyRichEditControlTest.PictureCase(const AWhat: string; APngW, APngH: Integer;
  AFail: Boolean; AZoomAfter: Integer);
var
  pic: TTyRichPicture;
  steps: Integer;
begin
  FreeAndNil(FRich);
  FRich := NewProbe;
  FRich.Lay.FailScale := AFail;
  FRich.Lines.Text := 'a b';
  pic := TTyRichPicture.Create(rpfPng, PngBytes(APngW, APngH, BGRA(0, 0, 200, 255)), 600, 300);
  AssertTrue(AWhat + ': a picture', FRich.Document.Execute(TTyRichInsertObject.Create(1, pic)));
  PaintAll(True);
  AssertEquals(AWhat + ': left for later', 1, FRich.Pending);
  steps := 0;
  while FRich.Step and (steps < 10) do Inc(steps);
  AssertEquals(AWhat + ': made ready once', 1, steps);
  PaintAll(True);
  AssertEquals(AWhat + ': nothing waits after the paint', 0, FRich.Pending);
  if AZoomAfter > 0 then
  begin
    FRich.Zoom := AZoomAfter;
    PaintAll(True);
    AssertTrue(AWhat + ': at the new size at most once', FRich.Pending <= 1);
    steps := 0;
    while FRich.Step and (steps < 10) do Inc(steps);
    AssertTrue(AWhat + ': made ready once more at most', steps <= 1);
    PaintAll(True);
    AssertEquals(AWhat + ': nothing waits at the new size', 0, FRich.Pending);
  end;
end;

{ H-I7 / H-M10: a picture that cannot be reduced, an enlargement, one reduced and then zoomed:
  each queued at most once a size, and nothing waits afterwards. One picture in two places
  has both its boxes painted when it is ready. }
procedure TTyRichEditControlTest.TestAPictureIsQueuedOnceAndEveryBoxRepainted;
var
  pic: TTyRichPicture;
begin
  PictureCase('a failing reduction', 200, 100, True, 0);
  PictureCase('an enlargement', 20, 10, False, 0);
  PictureCase('reduced then zoomed', 200, 100, False, 500);
  FreeAndNil(FRich);
  FRich := NewProbe;
  SetLinesOf(20, 'Line ');
  pic := TTyRichPicture.Create(rpfPng, PngBytes(20, 10, BGRA(0, 0, 200, 255)), 600, 300);
  pic.AddRef;
  AssertTrue('once', FRich.Document.Execute(TTyRichInsertObject.Create(
    FRich.Document.Text.ParaStart(2), pic)));
  AssertTrue('twice', FRich.Document.Execute(TTyRichInsertObject.Create(
    FRich.Document.Text.ParaStart(5), pic)));
  PaintAll(True);
  AssertEquals('one picture, one size: queued once', 1, FRich.Pending);
  FRich.ResetCounts;
  AssertTrue('made ready', FRich.Step);
  AssertEquals('both its boxes', 2, Length(FRich.Invalidated));
  AssertEquals('a box each', 20, FRich.Invalidated[1].Bottom - FRich.Invalidated[1].Top);
  AssertTrue('in two places', FRich.Invalidated[0].Top <> FRich.Invalidated[1].Top);
end;

{$IFDEF MSWINDOWS}
function ReadStream(const APath: string): string;
var
  f: TFileStream;
begin
  Result := '';
  f := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, f.Size);
    if f.Size > 0 then f.ReadBuffer(Result[1], f.Size);
  finally
    f.Free;
  end;
end;
{$ENDIF}

function TTyRichEditControlTest.FileCount: Integer;
var
  sr: TSearchRec;
begin
  Result := 0;
  if FindFirst(FTemp + '*', faAnyFile, sr) = 0 then
  try
    repeat
      if (sr.Attr and faDirectory) = 0 then Inc(Result);
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
end;

{ H-I8: a write-protected target is refused before anything is written; a save keeps the
  target's attributes and alternate streams (Windows: ReplaceFileW). The Unix path (mode,
  owner, rename) is compile-checked only. }
procedure TTyRichEditControlTest.TestASaveKeepsWhatTheTargetWas;
{$IFDEF MSWINDOWS}
var
  path: string;
  orig: TBytes;
  raised: Boolean;
  f: TFileStream;
  s: string;
begin
  orig := BytesOf('{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}\pard\f0 Saved text.\par}');
  path := TempFile('keep.rtf', orig);
  FRich.LoadFromFile(path);
  AssertTrue('changed', FRich.Document.Execute(TTyRichInsertText.Create(0, 'New ')));
  FileSetAttr(path, faReadOnly);
  try
    raised := False;
    try
      FRich.SaveToFile(path);
    except
      on E: ETyRichEdit do raised := Pos('keep.rtf', E.Message) > 0;
    end;
  finally
    FileSetAttr(path, 0);
  end;
  AssertTrue('a write-protected file is refused, by its name', raised);
  AssertTrue('and is as it was', SameBytes(orig, FileBytes(path)));
  AssertEquals('no temporary file left', 1, FileCount);
  AssertTrue('still modified', FRich.Modified);
  // hidden, with a stream of its own
  f := TFileStream.Create(path + ':note', fmCreate);
  try
    s := 'kept';
    f.WriteBuffer(s[1], Length(s));
  finally
    f.Free;
  end;
  FileSetAttr(path, faHidden);
  try
    FRich.SaveToFile(path);
    AssertFalse('saved', FRich.Modified);
    AssertFalse('the new content', SameBytes(orig, FileBytes(path)));
    AssertTrue('still hidden', (FileGetAttr(path) and faHidden) <> 0);
    AssertEquals('its stream kept', 'kept', ReadStream(path + ':note'));
    AssertEquals('no temporary file left', 1, FileCount);
  finally
    FileSetAttr(path, 0);
  end;
end;
{$ELSE}
begin
  Ignore('Windows only (ReplaceFileW); the Unix path is compile-checked');
end;
{$ENDIF}

{ H-I9: a file another handle holds open for writing (a log being written) loads. }
procedure TTyRichEditControlTest.TestAFileOpenForWritingLoads;
var
  path: string;
  w: TFileStream;
begin
  path := TempFile('busy.txt', BytesOf('busy text'));
  w := TFileStream.Create(path, fmOpenReadWrite or fmShareDenyNone);
  try
    FRich.LoadFromFile(path);
    AssertEquals('loaded', 'busy text', FRich.Lines[0]);
  finally
    w.Free;
  end;
end;

function FormText(AComp: TComponent): string;
var
  ms, txt: TMemoryStream;
begin
  ms := TMemoryStream.Create;
  txt := TMemoryStream.Create;
  try
    ms.WriteComponent(AComp);
    ms.Position := 0;
    ObjectBinaryToText(ms, txt);
    SetString(Result, PChar(txt.Memory), txt.Size);
  finally
    txt.Free;
    ms.Free;
  end;
end;

{ H-I10: TabStop and Cursor have the constructor's values as defaults. }
procedure TTyRichEditControlTest.TestPublishedDefaultsAreTheConstructedValues;
var
  a, b: TTyRichEdit;
  ms: TMemoryStream;
begin
  a := TTyRichEdit.Create(nil);
  b := TTyRichEdit.Create(nil);
  ms := TMemoryStream.Create;
  try
    AssertFalse('a fresh control stores no TabStop', Pos('TabStop', FormText(a)) > 0);
    AssertFalse('nor a Cursor', Pos('Cursor', FormText(a)) > 0);
    a.Cursor := crDefault;
    AssertTrue('crDefault is stored', Pos('Cursor', FormText(a)) > 0);
    ms.WriteComponent(a);
    ms.Position := 0;
    ms.ReadComponent(b);
    AssertEquals('and read back', Ord(crDefault), Ord(b.Cursor));
  finally
    ms.Free;
    b.Free;
    a.Free;
  end;
end;

procedure TTyRichEditControlTest.CheckClearAdd(const AList: array of string);
var
  i: Integer;
begin
  FRich.Lines.Clear;
  for i := 0 to High(AList) do FRich.Lines.Add(AList[i]);
  AssertEquals(Format('%d lines', [Length(AList)]), Length(AList), FRich.Lines.Count);
  for i := 0 to High(AList) do AssertEquals(Format('line %d', [i]), AList[i], FRich.Lines[i]);
end;

{ H-I11: no lines and one empty line are told apart. }
procedure TTyRichEditControlTest.TestLinesTellNoLinesFromOneEmptyLine;
var
  a, b: TTyRichEdit;
  ms: TMemoryStream;
begin
  FRich.Lines.Add('');
  AssertEquals('one empty line', 1, FRich.Lines.Count);
  AssertEquals('one paragraph', 1, FRich.Document.Text.ParaCount);
  FRich.Lines.Add('x');
  AssertEquals('two lines', 2, FRich.Lines.Count);
  AssertEquals('the first empty', '', FRich.Lines[0]);
  AssertEquals('the second', 'x', FRich.Lines[1]);
  FRich.Lines.Clear;
  AssertEquals('none', 0, FRich.Lines.Count);
  FRich.Lines.Add('a');
  FRich.Lines.Add('');
  AssertEquals('[a, '''']', 2, FRich.Lines.Count);
  FRich.Lines.Delete(0);
  AssertEquals('the empty line is left', 1, FRich.Lines.Count);
  FRich.Lines.Delete(0);
  AssertEquals('and goes', 0, FRich.Lines.Count);
  CheckClearAdd(['', 'b']);
  CheckClearAdd(['a', '']);
  CheckClearAdd(['']);
  CheckClearAdd(['', '', 'c', '']);
  a := TTyRichEdit.Create(nil);
  b := TTyRichEdit.Create(nil);
  ms := TMemoryStream.Create;
  try
    a.Lines.Add('');
    AssertTrue('[''''] is stored', Pos('Lines.Strings', FormText(a)) > 0);
    ms.WriteComponent(a);
    ms.Position := 0;
    ms.ReadComponent(b);
    AssertEquals('and read back as one empty line', 1, b.Lines.Count);
    AssertEquals('empty', '', b.Lines[0]);
  finally
    ms.Free;
    b.Free;
    a.Free;
  end;
end;

{ H-M1: FinishLoading reports its progress in slices, and a cancel there acts. }
procedure TTyRichEditControlTest.TestFinishLoadingGoesInSlices;
var
  b: TBytes;
  paras: Integer;
  st: TBytesStream;
begin
  b := GeneratedRtf(10 * 1024 * 1024, paras);
  FRich.Slices(64 * 1024, 64 * 1024);
  FRich.OnLoadProgress := @LoadCalled;
  st := TBytesStream.Create(b);
  try
    FRich.LoadFromStream(st);
    FLoadCalls := 0;
    FRich.FinishLoading;
    AssertTrue(Format('progress during it (%d)', [FLoadCalls]), FLoadCalls >= 2);
    AssertFalse('loaded', FRich.Loading);
    AssertEquals('all', paras, FRich.Document.Text.ParaCount);
    FreeAndNil(FRich);
    FRich := NewProbe;
    FRich.Slices(64 * 1024, 64 * 1024);
    FRich.OnLoadProgress := @LoadCalled;
    st.Position := 0;
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FLoadCalls := 0;
  FCancelAt := 1;
  FRich.FinishLoading;
  AssertEquals('cancelled at the first report', 1, FLoadCalls);
  AssertFalse('stopped', FRich.Loading);
  AssertTrue('incomplete', FRich.Incomplete);
end;

{ H-M2: a wheel notch on a document that fits, a scroll up at the top: nothing happens. }
procedure TTyRichEditControlTest.TestScrollingAgainstAnEndDoesNothing;
begin
  FRich.Lines.Text := 'one'#10'two'#10'three';
  FRich.UpdateView;
  FRich.ResetCounts;
  FRich.Wheel(-120, []);
  FRich.ScrollViewBy(-50);
  FRich.ScrollToTop;
  AssertEquals('nothing invalidated', 0, Length(FRich.Invalidated));
  FRich.UpdateView;
  AssertEquals('nothing laid out', 0, FRich.LaidParas);
  AssertEquals('nor invalidated after', 0, Length(FRich.Invalidated));
  AssertTrue('no bar', (FRich.VBar = nil) or not FRich.VBar.Visible);
  AssertEquals('at the top', Int64(0), FRich.ScrollY);
end;

{ H-M3: a zoom keeps the same share of the top block above the view. }
procedure TTyRichEditControlTest.TestAZoomKeepsThePartOfTheBlockAtTheTop;
var
  sl: TStringList;
  s: string;
  i, h, h2: Integer;
  off: Int64;
begin
  sl := TStringList.Create;
  try
    s := '';
    for i := 1 to 2000 do s := s + 'word' + IntToStr(i mod 7) + ' ';
    sl.Add(s);
    for i := 1 to 20 do sl.Add('Line ' + IntToStr(i));
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.UpdateView;
  h := FRich.VisibleBlocks[0].Height;
  AssertTrue('a block taller than the view', h > 3 * (FRich.Area.Bottom - FRich.Area.Top));
  FRich.ScrollViewBy(h div 2);
  FRich.UpdateView;
  AssertEquals('half of it above', 0, FRich.TopParagraph);
  off := FRich.TopOffset;
  FRich.Zoom := 200;
  FRich.UpdateView;
  AssertEquals('the same block on top', 0, FRich.TopParagraph);
  h2 := FRich.VisibleBlocks[0].Height;
  AssertTrue(Format('the same share (%d of %d, was %d of %d)', [FRich.TopOffset, h2, off, h]),
    Abs(FRich.TopOffset - off * h2 div h) <= 1);
end;

{ H-M4: a scroll of a hundred screens is a jump: only around its target is laid out. }
procedure TTyRichEditControlTest.TestAFarScrollIsAJump;
var
  n: Integer;
begin
  LoadBig;
  FRich.UpdateView;
  FRich.ResetCounts;
  FRich.ScrollViewBy(100 * (FRich.Area.Bottom - FRich.Area.Top));
  FRich.UpdateView;
  n := ScreenLines;
  AssertTrue(Format('laid out %d', [FRich.LaidParas]), FRich.LaidParas <= 3 * n + 2);
  AssertTrue(Format('about a hundred screens down (%d)', [FRich.TopParagraph]),
    FRich.TopParagraph > 90 * n);
end;

{ H-M6: saving to a stream changes nothing; saving an RTF document as text is an export. }
procedure TTyRichEditControlTest.TestSavingAsTextIsAnExport;
var
  path: string;
  ms: TMemoryStream;
begin
  path := TempFile('doc.rtf', BytesOf('{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}\pard\f0 Text.\par}'));
  FRich.LoadFromFile(path);
  AssertTrue('changed', FRich.Document.Execute(TTyRichInsertText.Create(0, 'New ')));
  ms := TMemoryStream.Create;
  try
    FRich.SaveToStream(ms);
    AssertTrue('written', ms.Size > 0);
  finally
    ms.Free;
  end;
  AssertTrue('a stream changes nothing', FRich.Modified);
  FRich.SaveToFile(FTemp + 'out.txt');
  AssertTrue('as text: still modified', FRich.Modified);
  AssertTrue('still an RTF document', FRich.SourceFormat = rfRtf);
  AssertEquals('from its file', ExpandFileName(path), FRich.SourceFile);
  FRich.SaveToFile(path);
  AssertFalse('as RTF: saved', FRich.Modified);
end;

{ H-M7: a save that cannot create its file says which file it was to write. }
procedure TTyRichEditControlTest.TestASaveThatCannotWriteNamesTheTarget;
var
  msg: string;
begin
  TempFile('x', nil);
  FRich.Lines.Text := 'text';
  msg := '';
  try
    FRich.SaveToFile(FTemp + 'missing' + PathDelim + 'target.rtf');
  except
    on E: ETyRichEdit do msg := E.Message;
  end;
  AssertTrue('refused, by the target''s name: ' + msg, Pos('target.rtf', msg) > 0);
  AssertFalse('no temporary name in it', Pos('.tmp', msg) > 0);
end;

{ H-M9: a layout that raises in the middle of a pass leaves no reference behind. }
procedure TTyRichEditControlTest.TestALayoutThatRaisesKeepsNoReference;
var
  raised: Boolean;
  base, i: Integer;
  L: TTyBlockLayout;
begin
  SetLinesOf(400, 'Line ');
  FRich.UpdateView;
  L := FRich.Layouter.LayoutBlock(FRich.Document, 399, FRich.VisibleBlocks[0].Layout.LayoutWidth,
    96, 1);
  // what a layout the view does not hold has: the cache's own (read before letting ours go)
  base := L.RefCount - 1;
  L.Release;
  FRich.ScrollY := FRich.Document.Text.ParaTop(200);
  FRich.ResetCounts;
  FRich.RaiseAfter := 30;
  raised := False;
  try
    FRich.UpdateView;
  except
    on E: EInvalidOperation do raised := True;
  end;
  FRich.RaiseAfter := 0;
  AssertTrue('the layout raised', raised);
  AssertTrue('some were given', Length(FRich.Given) > 10);
  for i := 0 to High(FRich.Given) do
    AssertEquals(Format('layout %d is the cache''s only', [i]), base, FRich.Given[i].RefCount);
  FRich.UpdateView;
  AssertTrue('the view comes back', FRich.VisibleBlockCount > 0);
end;

{ H-M11: no OnChange while a form file is read; AddStrings is one undo step. }
procedure TTyRichEditControlTest.TestStreamingRaisesNoChangeAndABatchIsOneStep;
var
  a, b: TTyRichEdit;
  ms: TMemoryStream;
  sl: TStringList;
begin
  a := TTyRichEdit.Create(nil);
  b := TTyRichEdit.Create(nil);
  ms := TMemoryStream.Create;
  try
    a.Lines.Text := 'first'#13#10'second';
    ms.WriteComponent(a);
    ms.Position := 0;
    b.OnChange := @Changed;
    ms.ReadComponent(b);
    AssertEquals('read', 2, b.Lines.Count);
    AssertEquals('no change reported while streaming', 0, FChanges);
  finally
    ms.Free;
    b.Free;
    a.Free;
  end;
  FRich.Lines.Text := 'a';
  sl := TStringList.Create;
  try
    sl.Add('b');
    sl.Add('c');
    sl.Add('d');
    FRich.Lines.AddStrings(sl);
  finally
    sl.Free;
  end;
  AssertEquals('added', 4, FRich.Lines.Count);
  FRich.Document.Undo;
  AssertEquals('one undo takes them all back', 1, FRich.Lines.Count);
  AssertFalse('nothing more to undo', FRich.Document.CanUndo);
end;

{ H-M12: the control's own StyleOverride tokens reach the selection, object and placeholder. }
procedure TTyRichEditControlTest.TestStyleOverrideTokensReachTheParts;
var
  st: TTyRichPaintStyle;
begin
  FRich.StyleOverride := '--selection: #FF0000; --accent: #00FF00; --surface-sunk: #0000FF; ' +
    '--border: #FFFF00;';
  st := FRich.Style;
  AssertTrue('selection', SamePx(BGRA(255, 0, 0, 255), st.SelectionBack));
  AssertTrue('object frame', SamePx(BGRA(0, 255, 0, 255), st.ObjectFrame));
  AssertTrue('placeholder fill', SamePx(BGRA(0, 0, 255, 255), st.PlaceholderFill));
  AssertTrue('placeholder frame', SamePx(BGRA(255, 255, 0, 255), st.PlaceholderFrame));
end;

function HexOf(const ABytes: TBytes): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(ABytes) do Result := Result + LowerCase(IntToHex(ABytes[i], 2));
end;

{ H-M13: a change in a row's later paragraph drops the row's waiting picture. }
procedure TTyRichEditControlTest.TestAChangeInARowDropsItsPendingPicture;
var
  rtf: string;
  st: TBytesStream;
  f: TTyCharFormat;
  t: TTyRichText;
  p: Integer;
begin
  rtf := '{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}' +
    '\trowd\cellx3000\cellx6000\pard\intbl a\cell\pard\intbl b {\pict\pngblip\picw200\pich100' +
    '\picwgoal600\pichgoal300 ' + HexOf(PngBytes(200, 100, BGRA(0, 0, 200, 255))) +
    '}\cell\row\pard after\par}';
  st := TBytesStream.Create(BytesOf(rtf));
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
  FRich.UpdateView;
  AssertTrue('a row first', FRich.VisibleBlocks[0].Layout is TTyRowLayout);
  AssertTrue('of two paragraphs', FRich.VisibleBlocks[0].LastPara > FRich.VisibleBlocks[0].FirstPara);
  PaintAll(True);
  AssertEquals('its picture waits', 1, FRich.Pending);
  t := FRich.Document.Text;
  p := FRich.VisibleBlocks[0].LastPara;
  f := TyDefaultCharFormat;
  f.Color := clRed;
  AssertTrue('the second cell''s text changed', FRich.Document.Execute(TTyRichSetCharFormat.Create(
    TyRichRange(t.ParaStart(p), 1), [cffColor], f)));
  AssertEquals('the row''s picture no longer waits', 0, FRich.Pending);
end;

{ W1r-O1: another fallback font: the view is laid out again like after a font change. }
procedure TTyRichEditControlTest.TestAFallbackFontChangeLaysTheViewOutAgain;
begin
  SetLinesOf(200, 'Line ');
  FRich.UpdateView;
  AssertTrue('measured', FRich.Document.Text.MeasuredParaCount > 0);
  FRich.ResetCounts;
  FRich.OnFallbackFont := @NoFallback;
  AssertEquals('every height an estimate again', 0, FRich.Document.Text.MeasuredParaCount);
  AssertTrue('the text painted again', Covered(FRich.Area));
  FRich.UpdateView;
  AssertTrue('laid out again', FRich.LaidParas > 0);
  FRich.ResetCounts;
  FRich.FallbackFonts.Add('Arial');
  AssertEquals('the list too', 0, FRich.Document.Text.MeasuredParaCount);
  AssertTrue('painted again', Covered(FRich.Area));
  FRich.UpdateView;
  AssertTrue('laid out again', FRich.LaidParas > 0);
end;

{ W1r-O2: blocks of CRichMaxBlockPx: tops and positions past an Integer's range. }
procedure TTyRichEditControlTest.TestHugeBlocksKeepTheArithmeticInRange;
var
  sl: TStringList;
  big: string;
  i, k, h: Integer;
  pf: TTyParaFormat;
  r: TRect;
  pos: TTyRichPos;
  t: TTyRichText;
begin
  big := '';
  for i := 1 to 16500 do big := big + 'x'#11;
  sl := TStringList.Create;
  try
    sl.Add('first');
    for i := 1 to 5 do sl.Add(big);
    sl.Add('last');
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  pf := TyDefaultParaFormat;
  pf.LineSpacing := lsExact;
  pf.LineSpacingValue := 2000000000;
  AssertTrue('exact lines', FRich.Document.Execute(TTyRichSetParaFormat.Create(1, 5,
    [pffLineSpacing], pf)));
  t := FRich.Document.Text;
  h := FRich.Area.Bottom - FRich.Area.Top;
  // each huge paragraph laid out once: their heights are measured
  for k := 1 to 5 do
  begin
    FRich.ScrollY := t.ParaTop(k);
    FRich.UpdateView;
  end;
  AssertEquals('measured', Int64(CRichMaxBlockPx), t.ParaHeight(3));
  FRich.ScrollToEnd;
  AssertEquals('ScrollY past an Integer', t.TotalHeight - h, FRich.ScrollY);
  AssertTrue(Format('it is (%d; paragraph 1 is %d high, %d paragraphs)', [FRich.ScrollY,
    t.ParaHeight(1), t.ParaCount]), FRich.ScrollY > MaxInt);
  AssertTrue('the last line on screen', InView(6));
  FRich.ScrollY := t.ParaTop(2) + 1000;
  for k := 1 to FRich.VisibleBlockCount - 1 do
    AssertEquals(Format('block %d follows the one before', [k]),
      FRich.VisibleBlocks[k - 1].Top + FRich.VisibleBlocks[k - 1].Height, FRich.VisibleBlocks[k].Top);
  AssertEquals('a huge block on top', CRichMaxBlockPx, FRich.VisibleBlocks[1].Height);
  r := FRich.ParagraphRect(2);
  AssertTrue('its rectangle in range', (r.Top < FRich.Area.Top) and (r.Bottom > FRich.Area.Bottom)
    and (r.Top > -MaxInt) and (r.Bottom < MaxInt));
  pos := FRich.PositionAtPoint(FRich.Area.Left + 2, FRich.Area.Top + 2);
  AssertTrue(Format('a point in it is in it (%d)', [pos]), (pos >= t.ParaStart(2)) and
    (pos <= t.ParaStart(2) + t.ParaLength(2)));
end;

{ R40: the bytes before the RTF signature (a UTF-8 BOM, blank lines, spaces) are the file's:
  saved back as they were, to a stream and over the file, after an edit too; rfRtf takes such a
  file as rfAuto does; a text file's BOM is the text reader's and is written once. }
procedure TTyRichEditControlTest.TestTheBytesBeforeTheRtfAreKept;
const
  Body = '{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}\pard\f0 Some text.\par}';
var
  prefixes: array[0..2] of RawByteString;
  i: Integer;
  orig, saved: TBytes;
  path: string;
  ms: TMemoryStream;
  st: TBytesStream;
  s: RawByteString;
begin
  prefixes[0] := #$EF#$BB#$BF;
  prefixes[1] := #13#10'   ';
  prefixes[2] := #$EF#$BB#$BF#13#10#9' '#10;
  for i := 0 to 2 do
  begin
    orig := BytesOf(prefixes[i] + Body);
    path := TempFile(Format('prefix%d.rtf', [i]), orig);
    FreeAndNil(FRich);
    FRich := NewProbe;
    FRich.LoadFromFile(path);
    AssertTrue(Format('%d: read as RTF', [i]), FRich.SourceFormat = rfRtf);
    ms := TMemoryStream.Create;
    try
      FRich.SaveToStream(ms);
      AssertTrue(Format('%d: to a stream as it came', [i]), SameBytes(orig, StreamBytes(ms)));
    finally
      ms.Free;
    end;
    FRich.SaveToFile(path);
    AssertTrue(Format('%d: over its file', [i]), SameBytes(orig, FileBytes(path)));
    // after an edit the prefix still comes first
    AssertTrue('changed', FRich.Document.Execute(TTyRichInsertText.Create(0, 'New ')));
    FRich.SaveToFile(path);
    saved := FileBytes(path);
    AssertTrue(Format('%d: an edited save starts with it', [i]),
      (Length(saved) > Length(prefixes[i]) + 5) and
      CompareMem(@saved[0], @prefixes[i][1], Length(prefixes[i])) and
      (saved[Length(prefixes[i])] = Ord('{')));
    // the explicit format reads the same bytes the same way
    FreeAndNil(FRich);
    FRich := NewProbe;
    st := TBytesStream.Create(orig);
    try
      FRich.LoadFromStream(st, rfRtf);
    finally
      st.Free;
    end;
    AssertEquals(Format('%d: rfRtf reads it', [i]), 'Some text.', FRich.Lines[0]);
    ms := TMemoryStream.Create;
    try
      FRich.SaveToStream(ms);
      AssertTrue(Format('%d: and keeps it', [i]), SameBytes(orig, StreamBytes(ms)));
      // saved as text: no prefix
      ms.Clear;
      FRich.SaveToStream(ms, rfText);
      SetString(s, PChar(ms.Memory), ms.Size);
      AssertEquals(Format('%d: as text, the text first', [i]), 1, Pos('Some text.', s));
    finally
      ms.Free;
    end;
    // a replacement forgets it
    FRich.Lines.Text := 'plain';
    ms := TMemoryStream.Create;
    try
      FRich.SaveToStream(ms, rfRtf);
      AssertEquals(Format('%d: a new content has none', [i]), Ord('{'), PByte(ms.Memory)^);
    finally
      ms.Free;
    end;
  end;
  // a text file that starts with a BOM: written once
  orig := BytesOf(#$EF#$BB#$BF'just text'#13#10'two');
  path := TempFile('bom.txt', orig);
  FreeAndNil(FRich);
  FRich := NewProbe;
  FRich.LoadFromFile(FTemp + 'prefix0.rtf');
  FRich.LoadFromFile(path);
  AssertTrue('read as text', FRich.SourceFormat = rfText);
  ms := TMemoryStream.Create;
  try
    FRich.SaveToStream(ms);
    AssertTrue('its BOM written once', SameBytes(orig, StreamBytes(ms)));
    ms.Clear;
    FRich.SaveToStream(ms, rfRtf);
    AssertEquals('the RTF before it is forgotten', Ord('{'), PByte(ms.Memory)^);
  finally
    ms.Free;
  end;
end;

{ ---- R39: the kept surface ---- }

{ The surface as it is, drawn again from nothing at the same position: the same pixels. }
procedure TTyRichEditControlTest.CheckSurface(const AWhat: string);
var
  kept: TBGRABitmap;
  x, y, diff, dx0, dy0, dx1, dy1: Integer;
  a, b: PBGRAPixel;
begin
  PaintAll(True);
  AssertTrue(AWhat + ': a surface', FRich.Surf <> nil);
  kept := FRich.Surf.Duplicate as TBGRABitmap;
  try
    FRich.RedrawAll;
    PaintAll(True);
    diff := 0;
    dx0 := 0; dy0 := 0; dx1 := 0; dy1 := 0;
    for y := 0 to FRich.Height * FRich.Scale - 1 do
    begin
      a := kept.ScanLine[y];
      b := FRich.Surf.ScanLine[y];
      for x := 0 to FRich.Width * FRich.Scale - 1 do
      begin
        if (a^.red <> b^.red) or (a^.green <> b^.green) or (a^.blue <> b^.blue) or
          (a^.alpha <> b^.alpha) then
        begin
          if diff = 0 then
          begin
            dx0 := x; dy0 := y; dx1 := x; dy1 := y;
          end;
          Inc(diff);
          dx0 := Math.Min(dx0, x); dx1 := Math.Max(dx1, x);
          dy0 := Math.Min(dy0, y); dy1 := Math.Max(dy1, y);
        end;
        Inc(a);
        Inc(b);
      end;
    end;
    AssertEquals(Format('%s: pixels that differ from a full redraw (in %d,%d..%d,%d; area %d,%d,%d,%d)',
      [AWhat + Format(' kept %x new %x / kept %x new %x', [PCardinal(kept.ScanLine[dy0] + dx0)^,
      PCardinal(FRich.Surf.ScanLine[dy0] + dx0)^, PCardinal(kept.ScanLine[dy1] + dx1)^,
      PCardinal(FRich.Surf.ScanLine[dy1] + dx1)^]), dx0, dy0, dx1, dy1, FRich.Area.Left, FRich.Area.Top, FRich.Area.Right,
      FRich.Area.Bottom]), 0, diff);
  finally
    kept.Free;
  end;
end;

{ A document of lines, wrapped paragraphs, one paragraph taller than the view, a table row and
  a picture, as RTF. }
function MixedRtf: string;
var
  i, k: Integer;
  s: string;
begin
  Result := '{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}';
  for i := 0 to 59 do
  begin
    s := 'Line ' + IntToStr(i);
    if i mod 7 = 3 then
      for k := 1 to 40 do s := s + ' word' + IntToStr(k mod 5);
    if i = 20 then
      for k := 1 to 1500 do s := s + ' tall' + IntToStr(k mod 9);
    Result := Result + '\pard ' + s + '\par' + #13#10;
    if i = 12 then
      Result := Result + '\trowd\cellx2500\cellx5000\pard\intbl cell one\cell\pard\intbl cell two' +
        ' with more words in it\cell\row' + #13#10;
    if i = 30 then
      Result := Result + '\pard {\pict\pngblip\picw40\pich20\picwgoal900\pichgoal450 ' +
        HexOf(PngBytes(40, 20, BGRA(30, 160, 60, 255))) + '}\par' + #13#10;
  end;
  Result := Result + '\pard The last line.\par}';
end;

{ After scrolls by a line, a part of a line, a page, to the end and back, a horizontal scroll,
  invalidations and changes of the document, the kept surface is what a full redraw at the
  same position draws, pixel for pixel. }
procedure TTyRichEditControlTest.TestTheSurfaceEqualsAFullRedraw;
var
  st: TBytesStream;
  est, i: Integer;
  f: TTyCharFormat;
  t: TTyRichText;
begin
  st := TBytesStream.Create(BytesOf(MixedRtf));
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
  est := FRich.Layouter.EstimatedParaHeight(96, 1);
  CheckSurface('first');
  FRich.ScrollViewBy(est);
  CheckSurface('a line down');
  FRich.ScrollViewBy(-est);
  CheckSurface('a line up');
  FRich.ScrollViewBy(est div 2 + 1);
  CheckSurface('part of a line');
  for i := 1 to 12 do
  begin
    FRich.ScrollViewBy(est * 3);
    CheckSurface(Format('a notch %d (rows, a picture, the tall paragraph)', [i]));
  end;
  FRich.ScrollViewBy(FRich.Area.Bottom - FRich.Area.Top - est);
  CheckSurface('a page');
  FRich.ScrollViewBy(-7);
  CheckSurface('seven pixels up inside the tall paragraph');
  FRich.ScrollToEnd;
  CheckSurface('the end');
  FRich.ScrollViewBy(-est);
  CheckSurface('a line above the end');
  FRich.ScrollViewBy(est * 5);
  CheckSurface('against the end');
  FRich.ScrollToTop;
  CheckSurface('the top');
  FRich.ScrollViewBy(est * 2);
  FRich.ScrollViewBy(est);
  CheckSurface('two scrolls before a paint');
  // a part invalidated, nothing changed
  FRich.InvalidatePart(Rect(10, 20, 200, 41));
  CheckSurface('an invalidated part');
  // the document changes: a colour, a height, a paragraph added on screen
  t := FRich.Document.Text;
  f := TyDefaultCharFormat;
  f.Color := clRed;
  AssertTrue('a colour', FRich.Document.Execute(TTyRichSetCharFormat.Create(
    TyRichRange(t.ParaStart(FRich.TopParagraph + 2), 4), [cffColor], f)));
  CheckSurface('a colour');
  f.SizeHalfPt := 40;
  AssertTrue('a size', FRich.Document.Execute(TTyRichSetCharFormat.Create(
    TyRichRange(t.ParaStart(FRich.TopParagraph + 3), 4), [cffSize], f)));
  FRich.ScrollViewBy(est);
  CheckSurface('a size and a scroll');
  AssertTrue('a paragraph', FRich.Document.Execute(TTyRichInsertText.Create(
    t.ParaStart(FRich.TopParagraph + 1), 'new line'#10)));
  CheckSurface('a paragraph');
  // no wrap: a horizontal scroll moves columns
  FRich.WrapMode := rwmNone;
  CheckSurface('no wrap');
  FRich.WheelH(120);
  CheckSurface('a horizontal notch');
  FRich.WheelH(-120);
  CheckSurface('and back');
end;

{ A scroll by a line paints only the blocks the exposed band meets, and lays out nothing that
  was held; a paint with nothing dirty paints no block and no frame; a hover (a state that
  changes the frame) paints the frame and lays out nothing. }
procedure TTyRichEditControlTest.TestAScrollPaintsOnlyWhatItExposes;
var
  est: Integer;
begin
  SetLinesOf(1000, 'Line ');
  FCtl.LoadThemeCss('TyRichEdit:hover { border-color: #FF0000; }');
  PaintAll(True);
  est := FRich.Layouter.EstimatedParaHeight(96, 1);
  FRich.ResetCounts;
  FRich.ScrollViewBy(est);
  PaintAll(True);
  AssertTrue(Format('blocks painted for a line: %d', [FRich.BlockPaints]),
    (FRich.BlockPaints >= 1) and (FRich.BlockPaints <= 4));
  AssertEquals('no frame', 0, FRich.FramePaints);
  AssertTrue(Format('laid out: %d', [FRich.LaidParas]), FRich.LaidParas <= 1);
  FRich.ScrollViewBy(5 * est);
  PaintAll(True);
  FRich.ResetCounts;
  FRich.ScrollViewBy(-3 * est);
  PaintAll(True);
  AssertTrue(Format('blocks painted for three lines up: %d', [FRich.BlockPaints]),
    (FRich.BlockPaints >= 3) and (FRich.BlockPaints <= 6));
  AssertEquals('nothing laid out going back', 0, FRich.LaidParas);
  FRich.ResetCounts;
  PaintAll(True);
  AssertEquals('nothing dirty: no block', 0, FRich.BlockPaints);
  AssertEquals('nothing dirty: no frame', 0, FRich.FramePaints);
  FRich.Hover(True);
  PaintAll(True);
  AssertEquals('a hover: the frame', 1, FRich.FramePaints);
  AssertEquals('a hover lays out nothing', 0, FRich.LaidParas);
  // one paragraph changed: its block only
  FRich.ResetCounts;
  FRich.InvalidatePart(FRich.ParagraphRect(FRich.TopParagraph + 5));
  PaintAll(True);
  // its block, and its neighbours for their ink that may reach into it (clipped)
  AssertTrue(Format('one paragraph: %d blocks', [FRich.BlockPaints]),
    (FRich.BlockPaints >= 1) and (FRich.BlockPaints <= 3));
  AssertEquals('one paragraph: one line drawn', 1, FRich.Device.DrawCalls);
end;

{ The surface follows the client: in blocks, never more than a block past it, made again
  when the size changes by more. }
procedure TTyRichEditControlTest.TestTheSurfaceIsTheClientsSize;
begin
  SetLinesOf(50, 'Line ');
  PaintAll(True);
  AssertEquals('wide', 448, FRich.Surf.Width);
  AssertEquals('high', 320, FRich.Surf.Height);
  // the frame is on it all round: its left border as its top one (the text never covers it)
  AssertTrue('a left border', SamePx(FRich.Surf.GetPixel(0, 150), FRich.Surf.GetPixel(200, 0)));
  AssertFalse('not the ground', SamePx(FRich.Surf.GetPixel(0, 150), FRich.Surf.GetPixel(200, 150)));
  FRich.SetBounds(0, 0, 200, 100);
  PaintAll(True);
  AssertEquals('narrower', 256, FRich.Surf.Width);
  AssertEquals('lower', 128, FRich.Surf.Height);
end;

{ At device scale 2 the surface is twice the client, the text is laid out at twice the PPI,
  and what is public stays in client pixels; the picture averaged down is the scale 1 one. }
procedure TTyRichEditControlTest.TestDeviceScaleTwo;
var
  one: TRichProbe;
  bmp1, bmp2: TBitmap;
  b1, b2, half: TBGRABitmap;
  p1, p2: TTyRichPos;
  h1, h2, mismatch: Integer;
  y1, y2: Int64;
begin
  one := NewProbe;
  bmp1 := TBitmap.Create;
  bmp2 := TBitmap.Create;
  try
    SetLinesOf(300, 'Line of text ');
    one.Lines := FRich.Lines;
    bmp1.PixelFormat := pf32bit;
    bmp1.SetSize(400, 300);
    one.PaintPart(bmp1.Canvas, Rect(0, 0, 400, 300), True);
    h1 := one.VisibleBlocks[0].Layout.Height;
    TyForceDeviceScaleForTest(2, True, False);
    try
      bmp2.PixelFormat := pf32bit;
      bmp2.SetSize(800, 600);
      FRich.PaintPart(bmp2.Canvas, Rect(0, 0, 400, 300), True);
      AssertEquals('laid out at scale 2', 2, FRich.Scale);
      AssertTrue('the surface twice the client', (FRich.Surf.Width >= 800) and
        (FRich.Surf.Height >= 600) and (FRich.Surf.Width < 800 + 64) and
        (FRich.Surf.Height < 600 + 64));
      h2 := FRich.VisibleBlocks[0].Layout.Height;
      AssertEquals('a line laid out twice as tall', 2 * h1, h2);
      AssertEquals('in client pixels the same', one.VisibleBlocks[0].Height,
        FRich.VisibleBlocks[0].Height);
      p1 := one.PositionAtPoint(60, 50);
      p2 := FRich.PositionAtPoint(60, 50);
      AssertEquals('a client point hits the same position', p1, p2);
      one.ScrollY := one.Document.Text.ParaTop(100);
      FRich.ScrollY := one.ScrollY;
      AssertEquals('the same paragraph on top', one.TopParagraph, FRich.TopParagraph);
      y1 := one.ScrollY;
      y2 := FRich.ScrollY;
      AssertTrue(Format('ScrollY in client pixels (%d, %d)', [y1, y2]), Abs(y1 - y2) <= 1);
      AssertTrue('the paragraph''s rectangle', EqualRect(one.ParagraphRect(101),
        FRich.ParagraphRect(101)));
      FRich.PaintPart(bmp2.Canvas, Rect(0, 0, 400, 300), True);
    finally
      TyForceDeviceScaleForTest(0, False);
    end;
    one.PaintPart(bmp1.Canvas, Rect(0, 0, 400, 300), True);
    b1 := TBGRABitmap.Create(bmp1);
    b2 := TBGRABitmap.Create(bmp2);
    half := TyHalve(b2);
    try
      mismatch := TyInkMismatch(half, b1);
      AssertTrue(Format('averaged down, it is the scale 1 picture (%d)', [mismatch]),
        mismatch <= CMaxMismatch);
    finally
      half.Free;
      b2.Free;
      b1.Free;
    end;
  finally
    bmp2.Free;
    bmp1.Free;
    one.Free;
  end;
end;

initialization
  RegisterTest(TTyRichEditControlTest);

end.
