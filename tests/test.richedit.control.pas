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
  tyControls.RichEdit, test.richedit.layoutdevice;

type
  TRichProbe = class(TTyRichEdit)
  private
    FLaidParas: Integer;
    FLaidMin, FLaidMax: Integer;
  protected
    function CreateDevice: TTyRichTextDevice; override;
    function LayoutBlockAt(AIndex: Integer): TTyBlockLayout; override;
    procedure InvalidateContent(const ARect: TRect); override;
    function ScrollBarLimit: Integer; override;
  public
    Invalidated: array of TRect;
    BarLimit: Integer;
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
    property LaidParas: Integer read FLaidParas;
    property LaidMin: Integer read FLaidMin;
    property LaidMax: Integer read FLaidMax;
  end;

  TTyRichEditControlTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TRichProbe;
    FTemp: string;
    FChanges, FZooms, FLoadCalls, FCancelAt: Integer;
    procedure Changed(Sender: TObject);
    procedure Zoomed(Sender: TObject);
    procedure LoadCalled(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    procedure SaveCancel(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    function NewProbe: TRichProbe;
    procedure LoadBig;
    function ScreenLines: Integer;
    function TempFile(const AName: string; const ABytes: TBytes): string;
    function InView(APara: Integer): Boolean;
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

function TRichProbe.LayoutBlockAt(AIndex: Integer): TTyBlockLayout;
var
  before: Int64;
begin
  before := Layouter.CacheMisses;
  Result := inherited LayoutBlockAt(AIndex);
  if Layouter.CacheMisses > before then
  begin
    Inc(FLaidParas, Result.LastPara - Result.FirstPara + 1);
    if Result.FirstPara < FLaidMin then FLaidMin := Result.FirstPara;
    if Result.LastPara > FLaidMax then FLaidMax := Result.LastPara;
  end;
end;

procedure TRichProbe.InvalidateContent(const ARect: TRect);
begin
  SetLength(Invalidated, Length(Invalidated) + 1);
  Invalidated[High(Invalidated)] := ARect;
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
end;

procedure TTyRichEditControlTest.TearDown;
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
    FTemp := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'tyrichedit9a-' +
      IntToHex(Random($7FFFFFFF), 8) + PathDelim;
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
  before := FRich.ScrollY;
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
  AssertTrue('the paragraph''s', EqualRect(r5, FRich.Invalidated[0]));
  AssertEquals('one block laid out again', 1, FRich.LaidParas);
  // a taller paragraph moves what is below it
  r7 := FRich.ParagraphRect(7);
  a := FRich.Area;
  FRich.ResetCounts;
  f.SizeHalfPt := 48;
  AssertTrue('a size from code', FRich.Document.Execute(TTyRichSetCharFormat.Create(
    TyRichRange(t.ParaStart(7), t.ParaLength(7)), [cffSize], f)));
  AssertEquals('one rectangle', 1, Length(FRich.Invalidated));
  AssertTrue('from the paragraph to the bottom', EqualRect(Rect(a.Left, r7.Top, a.Right,
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
    FRich.PaintPart(bmp.Canvas, FRich.ParagraphRect(5), False);
    AssertEquals('one paragraph''s clip draws its one line', 1, FRich.Device.DrawCalls);
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

initialization
  RegisterTest(TTyRichEditControlTest);

end.
