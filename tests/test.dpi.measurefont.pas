unit test.dpi.measurefont;
{ The measuring font and the SCREEN's PPI.                       (ACTom/TyControls#2)

  WHAT WENT WRONG. A caption is DRAWN on a TBGRABitmap whose FontHeight is a pixel count,
  MulDiv(Round(size * 96 / 72), APPI, 96). It used to be MEASURED on an LCL TBitmap canvas
  configured with `Font.Size := MulDiv(size, APPI, 96)` -- POINTS -- and an LCL TFont turns
  points into pixels with its OWN PixelsPerInch, which for a freshly created font is the
  screen's (font.inc, TFont.Create). So the measuring font carried the PPI twice:

      screen PPI   drawn   measured
          96         12       12      they agree, which is what hid it
         144         18       28      the reporter: line pitch and wrap width 1.5x too large
         168         21       37      175%: every size floor 1.75x too large, buttons swell
          72         12        9      THIS console runner: every floor 25% too small

  Everything that is sized from a caption inherited the error: the size floor of every
  button, check box and label, the width of every tab, the gap a group box erases behind its
  caption, the line pitch and the wrap points of a wrapping label.

  WHY THE SUITE NEVER SAW IT. The defect is a function of the SCREEN, and a test process
  has exactly one. Worse, this runner never initialises the widgetset's screen info, so it
  sits at the LCL default of 72 and measured too SMALL -- a third answer, matching neither
  a 96-PPI desktop nor a HiDPI one. Every pinned floor in the suite was taken under it.

  HOW THESE TESTS SEE IT. ScreenInfo (unit Graphics) is the variable TFont.Create reads, and
  it is a plain writable global. SimulateScreen sets it, so a scratch bitmap made afterwards
  carries the font a machine at that scaling would have given it. Nothing else is faked: the
  control PPI is set the way LCL's own DPI pass sets it, through Font.PixelsPerInch.
  TestASimulatedScreenReachesAFreshCanvasFont is the CONTROL GROUP that keeps that honest --
  if LCL ever stops seeding fonts from ScreenInfo, it fails, and says that every comparison
  in this unit has started comparing a value with itself.

  THE INVARIANT, stated once: what a control measures is a function of (caption, theme,
  the CONTROL's PPI) and of nothing else. The screen is not an input. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Forms, Graphics, LCLType,
  IntfGraphics, FPimage, FileUtil, TypInfo,
  fpcunit, testregistry, BGRABitmap, BGRABitmapTypes,
  test.designregistry, test.version, test.dpi.support,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.BuiltinThemes,
  tyControls.Base, tyControls.Button, tyControls.CheckBox, tyControls.ToggleSwitch,
  tyControls.GroupBox, tyControls.TabStrip, tyControls.TabSet, tyControls.TyLabel;

type
  { RenderTo is protected on each of these, and it is the path that measures INSIDE the
    paint: the group box measures its caption to size the gap it erases, the tab strip
    measures every caption to lay the tabs out, the label measures to wrap. }
  TGroupBoxPaintProbe = class(TTyGroupBox)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TTabSetPaintProbe = class(TTyTabSet)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TLabelPaintProbe = class(TTyLabel)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  { ParentFont is protected on TControl. }
  TParentFontProbe = class(TControl);

  { What a control says about its own size. The floor is what clamps a designed Width /
    Height (the swollen buttons of the 175% screenshot); the preferred size is what AutoSize
    obeys. }
  TSizeFacts = record
    W, H, MinW, MinH, PrefW, PrefH: Integer;
    { Which sides the PARENT decides. An aligned control's long axis is whatever its parent
      is wide or tall, and LCL's DPI pass rightly leaves it alone -- so it is not a fact
      about the control, and this runner has no align engine to stretch it anyway. }
    Align: TAlign;
  end;

  { How the control came to be on its form. Both happen, and they differ in the one thing
    this unit is about -- which PPI the control's font carries while its box is still in
    the designer's 96-PPI numbers:
      bwDesigned   read from a form file. LCL puts every font back at the design PPI when
                   the read completes (TCustomForm.Loaded, FixDesignFontsPPIWithChildren).
      bwCodeBuilt  created by code, in FormCreate or by a dialog builder. Nothing repairs
                   the font; a ParentFont child takes its parent's PPI when it is parented
                   (CM_PARENTFONTCHANGED) and anything else keeps the screen's. }
  TBirth = (bwDesigned, bwCodeBuilt);

  TTyMeasureFontDpiTest = class(TTestCase)
  private
    FSaveX, FSaveY: Integer;
    FSaveFontSize: Integer;
    FSaveFontName: string;
    FCtl: TTyStyleController;
    procedure SimulateScreen(APPI: Integer);
    function NewScratch: TBitmap;
    procedure MeasureOn(AScreen, APPI, ASize: Integer; out ATextH, ATextW: Integer);
    function FactsOf(ACls: TControlClass; AScreen, APPI: Integer; ABirth: TBirth;
      out AFacts: TSizeFacts; out AError: string): Boolean;
    function Painted(AKind, AScreen, APPI: Integer): TLongWordDynArray;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // --- the control group ---------------------------------------------------
    procedure TestASimulatedScreenReachesAFreshCanvasFont;
    // --- the one function both sides now share ------------------------------
    procedure TestTheMeasuringFontIsAPixelHeight;
    procedure TestMeasureAndDrawAskForTheSameFont;
    // --- the consequence: a measurement does not follow the screen -----------
    procedure TestMeasuredTextDoesNotFollowTheScreen;
    procedure TestAWrappedBlockDoesNotFollowTheScreen;
    procedure TestTheCanvasAndTheRendererAgreeOnAWidth;
    // --- which PPI a control is born at, and when it learns better -----------
    procedure TestAControlIsBornInTheDesignSpace;
    procedure TestAChildWithATouchedFontTakesItsParentsPPI;
    // --- the library, end to end ---------------------------------------------
    procedure TestSizeFloorsFollowTheControlPPIOnly;
    procedure TestNoRegisteredControlSizesItselfFromTheScreen;
    procedure TestEveryRegisteredControlScalesItsSizeWithThePPI;
    procedure TestPaintedLayoutDoesNotFollowTheScreen;
    procedure TestAFormDesignedAt96LoadsAtItsDesignedSizeOnAHiDpiDesktop;
    // --- and it must stay one function --------------------------------------
    procedure TestNoUnitSizesAFontByItself;
  end;

implementation

const
  { Long enough that a wrong font is a difference of tens of pixels, ASCII so it measures
    the same way on every widgetset. }
  CSample = 'Hold Alt to reveal the mnemonic underlines';
  CParagraph = 'A wrapping label breaks where the measured words stop fitting, so a '
    + 'measuring font that is too large breaks early and stacks the lines too far apart.';
  CCaption = 'Sample Ag';

  KIND_GROUPBOX = 0;
  KIND_TABSET   = 1;
  KIND_LABEL    = 2;

procedure TGroupBoxPaintProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TTabSetPaintProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TLabelPaintProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

{ ===== harness ============================================================== }

procedure TTyMeasureFontDpiTest.SetUp;
begin
  inherited SetUp;
  FSaveX := ScreenInfo.PixelsPerInchX;
  FSaveY := ScreenInfo.PixelsPerInchY;
  { Applying a theme rewrites TyFallbackFontSize from --font-size-base; put both fallbacks
    back afterwards so this suite cannot change what a later one measures. }
  FSaveFontSize := TyFallbackFontSize;
  FSaveFontName := TyFallbackFontName;
  { The shipped default theme and a controller of this suite's own: the floors below are
    built from a real theme's padding and font, and not from whatever an earlier test left
    on TyDefaultController. }
  TyRegisterBuiltinThemes;
  FCtl := TTyStyleController.Create(nil);
  FCtl.ThemeName := 'default';
end;

procedure TTyMeasureFontDpiTest.TearDown;
begin
  FreeAndNil(FCtl);
  ScreenInfo.PixelsPerInchX := FSaveX;
  ScreenInfo.PixelsPerInchY := FSaveY;
  Screen.UpdateScreen;
  TyFallbackFontSize := FSaveFontSize;
  TyFallbackFontName := FSaveFontName;
  { Nothing measured under a simulated screen may outlive the simulation. }
  TyInvalidateTextMeasureCache;
  inherited TearDown;
end;

procedure TTyMeasureFontDpiTest.SimulateScreen(APPI: Integer);
begin
  ScreenInfo.PixelsPerInchX := APPI;
  ScreenInfo.PixelsPerInchY := APPI;
  { Screen.PixelsPerInch is a COPY of it, taken when the Screen object was made. Refreshed
    so that anything asking the screen is told the same story as anything creating a font. }
  Screen.UpdateScreen;
  { THE LINE THAT MAKES EVERY COMPARISON BELOW REAL. The measurement memo is keyed on the
    control PPI and not on the screen (rightly -- the screen is not supposed to be an
    input), so without this the second screen would be answered from the first one's
    entries and each test would compare a number with itself. }
  TyInvalidateTextMeasureCache;
end;

function TTyMeasureFontDpiTest.NewScratch: TBitmap;
begin
  Result := TBitmap.Create;
  Result.SetSize(1, 1);
end;

procedure TTyMeasureFontDpiTest.MeasureOn(AScreen, APPI, ASize: Integer;
  out ATextH, ATextW: Integer);
var
  bmp: TBitmap;
begin
  SimulateScreen(AScreen);
  bmp := NewScratch;
  try
    TyConfigureMeasureFont(bmp.Canvas, '', ASize, 400, APPI);
    ATextH := bmp.Canvas.TextHeight('Ag');
    ATextW := bmp.Canvas.TextWidth(CSample);
  finally
    bmp.Free;
  end;
end;

{ Give a freshly built control something to measure, through RTTI so that the sweep needs
  no per-class knowledge: a caption, and three entries in whichever string list it
  publishes. A control that accepts neither is measured empty, which is still a fact. }
procedure SeedContent(AControl: TControl);
const
  CLists: array[0..2] of string = ('Items', 'Tabs', 'Lines');
var
  pi: PPropInfo;
  o: TObject;
  i: Integer;
begin
  pi := GetPropInfo(AControl, 'Caption');
  if (pi <> nil) and (pi^.SetProc <> nil)
     and (pi^.PropType^.Kind in [tkSString, tkLString, tkAString]) then
    try
      SetStrProp(AControl, pi, CCaption);
    except
      { a control that vetoes this caption keeps the one it has }
    end;
  for i := 0 to High(CLists) do
  begin
    pi := GetPropInfo(AControl, CLists[i]);
    if (pi = nil) or (pi^.PropType^.Kind <> tkClass) then Continue;
    o := GetObjectProp(AControl, pi);
    if not (o is TStrings) then Continue;
    try
      { Two, not more: enough for a tab strip or a radio group to have something to lay
        out, few enough that no list is anywhere near needing its scroll bar -- whether a
        bar appears is decided by a rounding at the boundary, and that is not what is
        being compared. }
      TStrings(o).Add('First Ag');
      TStrings(o).Add('Second entry');
    except
      { a list that refuses free-form entries stays as it was }
    end;
  end;
end;

{ LCL's DPI pass hands the monitor PPI to EVERY control, the internal ones included
  (TWinControl.AutoAdjustLayout recurses). Used by the paint probes, which render at a PPI
  without a form journey of their own. }
procedure PinPPI(AControl: TControl; APPI: Integer);
var
  i: Integer;
begin
  AControl.Font.PixelsPerInch := APPI;
  if AControl is TWinControl then
    for i := 0 to TWinControl(AControl).ControlCount - 1 do
      PinPPI(TWinControl(AControl).Controls[i], APPI);
end;

function TTyMeasureFontDpiTest.FactsOf(ACls: TControlClass; AScreen, APPI: Integer;
  ABirth: TBirth; out AFacts: TSizeFacts; out AError: string): Boolean;
{ ONE CONTROL, THE WAY IT REALLY GETS TO A HiDPI SCREEN. Nothing here sets a PPI on the
  control: the form is put in its 96-PPI design space, the control is born under the
  simulated screen and parented, and then LCL's own pass takes the form to APPI. What the
  control's font says at each step is whatever LCL and the library make it say. }
var
  frm: TForm;
  c: TControl;
begin
  Result := False;
  AError := '';
  AFacts := Default(TSizeFacts);
  frm := nil;
  SimulateScreen(AScreen);
  try
    try
      frm := TForm.CreateNew(nil);
      { What TCustomDesignControl.Create does in a scaled application. }
      frm.Font.PixelsPerInch := 96;
      { An explicit size on the FORM, for the reason TControlDpiRoundTripTest.Build gives at
        length: left unset, LCL's pass writes one into it (DoScaleFontPPI) worked out against
        Screen.PixelsPerInch -- which in this console runner is 72 and cannot be simulated --
        so every ParentFont child would inherit an 11 pt font the real machine never sees. }
      frm.Font.Size := 9;
      frm.SetBounds(40, 40, 1200, 900);
      c := ACls.Create(frm);
      if c is TTyCustomControl then
        TTyCustomControl(c).Controller := FCtl
      else if c is TTyGraphicControl then
        TTyGraphicControl(c).Controller := FCtl;
      c.Parent := frm;
      SeedContent(c);
      if ABirth = bwDesigned then
        frm.FixDesignFontsPPIWithChildren(96);
      if APPI <> 96 then
        frm.AutoAdjustLayout(lapAutoAdjustForDPI, 96, APPI,
          frm.Width, MulDiv(frm.Width, APPI, 96));
      c.InvalidatePreferredSize;
      AFacts.Align := c.Align;
      AFacts.MinW := c.Constraints.MinWidth;
      AFacts.MinH := c.Constraints.MinHeight;
      { The box as LCL will have it: a floor is applied the next time the bounds are set,
        and in a 96-PPI form nothing may have set them since the caption arrived. }
      AFacts.W := Max(c.Width, AFacts.MinW);
      AFacts.H := Max(c.Height, AFacts.MinH);
      c.GetPreferredSize(AFacts.PrefW, AFacts.PrefH, True, False);
      Result := True;
    except
      on E: Exception do
        AError := E.ClassName + ': ' + E.Message;
    end;
  finally
    FreeAndNil(frm);
  end;
end;

function FactsText(const F: TSizeFacts): string;
begin
  Result := Format('size %dx%d, floor %dx%d, preferred %dx%d',
    [F.W, F.H, F.MinW, F.MinH, F.PrefW, F.PrefH]);
end;

function SameFacts(const A, B: TSizeFacts): Boolean;
begin
  Result := (A.W = B.W) and (A.H = B.H) and (A.MinW = B.MinW) and (A.MinH = B.MinH)
    and (A.PrefW = B.PrefW) and (A.PrefH = B.PrefH);
end;

function BirthText(ABirth: TBirth): string;
begin
  if ABirth = bwDesigned then Result := 'designed' else Result := 'code-built';
end;

function Snapshot(ABmp: TBitmap): TLongWordDynArray;
var
  img: TLazIntfImage;
  x, y: Integer;
  c: TFPColor;
begin
  Result := nil;
  img := ABmp.CreateIntfImage;
  try
    SetLength(Result, img.Width * img.Height);
    for y := 0 to img.Height - 1 do
      for x := 0 to img.Width - 1 do
      begin
        c := img.Colors[x, y];
        Result[y * img.Width + x] := (LongWord(c.red shr 8) shl 16)
          or (LongWord(c.green shr 8) shl 8) or LongWord(c.blue shr 8);
      end;
  finally
    img.Free;
  end;
end;

function TTyMeasureFontDpiTest.Painted(AKind, AScreen, APPI: Integer): TLongWordDynArray;
var
  frm: TForm;
  bmp: TBitmap;
  w, h: Integer;
  gb: TGroupBoxPaintProbe;
  ts: TTabSetPaintProbe;
  lb: TLabelPaintProbe;
begin
  Result := nil;
  SimulateScreen(AScreen);
  w := MulDiv(320, APPI, 96);
  h := MulDiv(110, APPI, 96);
  frm := TForm.CreateNew(nil);
  bmp := TBitmap.Create;
  try
    frm.SetBounds(40, 40, 1200, 900);
    frm.Font.PixelsPerInch := APPI;
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(w, h);
    { A ground no theme paints, so an area the control left alone is recognisable. }
    bmp.Canvas.Brush.Color := TColor($00FF00FF);
    bmp.Canvas.FillRect(0, 0, w, h);
    case AKind of
      KIND_GROUPBOX:
        begin
          gb := TGroupBoxPaintProbe.Create(frm);
          gb.Controller := FCtl;
          gb.Parent := frm;
          gb.SetBounds(0, 0, w, h);
          gb.Caption := 'Group caption Ag';
          PinPPI(gb, APPI);
          gb.Render(bmp.Canvas, Rect(0, 0, w, h), APPI);
        end;
      KIND_TABSET:
        begin
          ts := TTabSetPaintProbe.Create(frm);
          ts.Controller := FCtl;
          ts.Parent := frm;
          ts.SetBounds(0, 0, w, h);
          ts.Tabs.Add('General');
          ts.Tabs.Add('Advanced settings');
          ts.Tabs.Add('About');
          ts.TabIndex := 1;
          PinPPI(ts, APPI);
          ts.Render(bmp.Canvas, Rect(0, 0, w, h), APPI);
        end;
      KIND_LABEL:
        begin
          lb := TLabelPaintProbe.Create(frm);
          lb.Controller := FCtl;
          lb.Parent := frm;
          lb.AutoSize := False;
          lb.WordWrap := True;
          lb.SetBounds(0, 0, w, h);
          lb.Caption := CParagraph;
          PinPPI(lb, APPI);
          lb.Render(bmp.Canvas, Rect(0, 0, w, h), APPI);
        end;
    end;
    Result := Snapshot(bmp);
  finally
    bmp.Free;
    frm.Free;
  end;
end;

{ ===== the control group ==================================================== }

procedure TTyMeasureFontDpiTest.TestASimulatedScreenReachesAFreshCanvasFont;
{ Proves the simulation is the real mechanism and not a variable nobody reads. Both halves
  are LCL behaviour, asserted so that a change in LCL fails HERE, by name, instead of turning
  every other test in this unit into a comparison of a value with itself. }
var
  bmp: TBitmap;
begin
  SimulateScreen(168);
  bmp := NewScratch;
  try
    AssertEquals('a scratch bitmap''s font is born at the SCREEN''s PPI -- that is the'
      + ' channel a 175% desktop reaches a measurement through', 168,
      bmp.Canvas.Font.PixelsPerInch);
    bmp.Canvas.Font.Size := 9;
    AssertEquals('...and LCL converts POINTS with that PPI, so a size in points is a'
      + ' different pixel height on every screen', -MulDiv(9, 168, 72),
      bmp.Canvas.Font.Height);
  finally
    bmp.Free;
  end;

  SimulateScreen(96);
  bmp := NewScratch;
  try
    bmp.Canvas.Font.Size := 9;
    AssertEquals('the same 9 points on a 96-PPI screen', -12, bmp.Canvas.Font.Height);
  finally
    bmp.Free;
  end;
end;

{ ===== the one function both sides share ==================================== }

procedure TTyMeasureFontDpiTest.TestTheMeasuringFontIsAPixelHeight;
const
  CScreens: array[0..3] of Integer = (72, 96, 144, 168);
  CPPIs: array[0..4] of Integer = (96, 120, 144, 168, 192);
var
  s, p: Integer;
  bmp: TBitmap;
begin
  { The numbers of the table in the header, pinned as numbers: these are what BGRA draws. }
  AssertEquals('theme font-size 9 at 96 PPI', 12, TyFontHeightPx(9, 96));
  AssertEquals('theme font-size 9 at 144 PPI', 18, TyFontHeightPx(9, 144));
  AssertEquals('theme font-size 9 at 168 PPI', 21, TyFontHeightPx(9, 168));
  AssertEquals('theme font-size 14 at 168 PPI', 33, TyFontHeightPx(14, 168));
  AssertTrue('never 0: an LCL Font.Height of 0 means "the default size"',
    TyFontHeightPx(0, 96) >= 1);

  for s := 0 to High(CScreens) do
    for p := 0 to High(CPPIs) do
    begin
      SimulateScreen(CScreens[s]);
      bmp := NewScratch;
      try
        AssertEquals('precondition: the scratch font was born at the simulated screen',
          CScreens[s], bmp.Canvas.Font.PixelsPerInch);
        TyConfigureMeasureFont(bmp.Canvas, '', 9, 400, CPPIs[p]);
        AssertEquals(Format('screen %d PPI, control %d PPI: the measuring font must be the'
          + ' DRAWN pixel height. Anything else means the size went in as points and the'
          + ' screen''s PPI was applied on top of the control''s',
          [CScreens[s], CPPIs[p]]),
          -TyFontHeightPx(9, CPPIs[p]), bmp.Canvas.Font.Height);
      finally
        bmp.Free;
      end;
    end;
end;

procedure TTyMeasureFontDpiTest.TestMeasureAndDrawAskForTheSameFont;
const
  CSizes: array[0..5] of Integer = (8, 9, 10, 12, 14, 18);
  CPPIs: array[0..4] of Integer = (96, 120, 144, 168, 240);
  CWeights: array[0..2] of Integer = (400, 600, 700);
var
  i, p, w: Integer;
  b: TBGRABitmap;
  bmp: TBitmap;
begin
  SimulateScreen(168);
  b := TBGRABitmap.Create(4, 4);
  bmp := NewScratch;
  try
    for i := 0 to High(CSizes) do
      for p := 0 to High(CPPIs) do
        for w := 0 to High(CWeights) do
        begin
          TyConfigureTextFont(b, '', CSizes[i], CWeights[w], CPPIs[p]);
          TyConfigureMeasureFont(bmp.Canvas, '', CSizes[i], CWeights[w], CPPIs[p]);
          AssertEquals(Format('size %d at %d PPI: the height that is measured must be the'
            + ' height that is drawn', [CSizes[i], CPPIs[p]]),
            b.FontHeight, -bmp.Canvas.Font.Height);
          AssertEquals(Format('size %d weight %d: bold on one side means bold on the other',
            [CSizes[i], CWeights[w]]),
            fsBold in b.FontStyle, fsBold in bmp.Canvas.Font.Style);
        end;
    { The missing-size fallback is the same on both sides too. }
    TyConfigureTextFont(b, '', 0, 400, 144);
    TyConfigureMeasureFont(bmp.Canvas, '', 0, 400, 144);
    AssertEquals('an unset font-size falls back to the same height on both sides',
      b.FontHeight, -bmp.Canvas.Font.Height);
  finally
    bmp.Free;
    b.Free;
  end;
end;

{ ===== a measurement does not follow the screen ============================= }

procedure TTyMeasureFontDpiTest.TestMeasuredTextDoesNotFollowTheScreen;

  procedure Check(AScreenA, AScreenB, APPI: Integer);
  var
    ha, wa, hb, wb: Integer;
  begin
    MeasureOn(AScreenA, APPI, 9, ha, wa);
    MeasureOn(AScreenB, APPI, 9, hb, wb);
    AssertTrue('precondition: something was measured', (ha > 0) and (wa > 0));
    AssertEquals(Format('line height at control PPI %d, measured on a %d-PPI screen and on'
      + ' a %d-PPI one', [APPI, AScreenA, AScreenB]), ha, hb);
    AssertEquals(Format('caption width at control PPI %d, measured on a %d-PPI screen and'
      + ' on a %d-PPI one', [APPI, AScreenA, AScreenB]), wa, wb);
  end;

begin
  Check(96, 168, 168);     // 175%, the maintainer's screenshot
  Check(96, 144, 144);     // 150%, the reporter's
  Check(96, 72, 96);       // this console runner against a real 100% desktop
end;

procedure TTyMeasureFontDpiTest.TestAWrappedBlockDoesNotFollowTheScreen;
{ The issue as reported: a wrapping label on a 144-PPI desktop, "too much whitespace between
  lines". The block's height is line count x line pitch, and both came from the measuring
  font -- it wrapped early AND stacked the lines too far apart. }
var
  wrap, w1, h1, w2, h2, wFlat, hFlat: Integer;
begin
  wrap := MulDiv(260, 144, 96);

  SimulateScreen(96);
  TyMeasureTextBlock(CParagraph, '', 9, 400, 144, wrap, 0, w1, h1);
  TyMeasureTextBlock(CParagraph, '', 9, 400, 144, 0, 0, wFlat, hFlat);
  AssertTrue('precondition: the paragraph really wraps at this width, so the line COUNT is'
    + ' part of what is compared', h1 >= 2 * hFlat);

  SimulateScreen(144);
  TyMeasureTextBlock(CParagraph, '', 9, 400, 144, wrap, 0, w2, h2);

  AssertEquals('a block wrapped at 144 PPI must be as TALL on a 144-PPI desktop as on a'
    + ' 96-PPI one: same number of lines, same pitch', h1, h2);
  AssertEquals('...and as wide', w1, w2);
end;

procedure TTyMeasureFontDpiTest.TestTheCanvasAndTheRendererAgreeOnAWidth;
{ An oracle this library does not own. The renderer (BGRA) has always taken a pixel height,
  so its answer never depended on the screen; the canvas is the side that did. The two are
  different rasterisers and differ by a pixel or two per word -- hence a tolerance -- but a
  measuring font that is 1.75x too large, or 25% too small, is nowhere near it.
  Note the 72-PPI row: that is this runner's own screen, so the old code failed this test
  with no simulation at all. }
const
  CScreens: array[0..2] of Integer = (72, 96, 168);
  CPPIs: array[0..3] of Integer = (96, 144, 168, 240);
var
  s, p, w, h, r, tol: Integer;
begin
  for s := 0 to High(CScreens) do
    for p := 0 to High(CPPIs) do
    begin
      SimulateScreen(CScreens[s]);
      TyMeasureTextBlock(CSample, '', 9, 400, CPPIs[p], 0, 0, w, h);
      r := TyMeasureRenderedTextWidth(CSample, '', 9, 400, CPPIs[p]);
      AssertTrue('precondition: the renderer measured something', r > 0);
      tol := Max(3, r div 20);
      AssertTrue(Format('screen %d PPI, control %d PPI: the canvas measured %d px and the'
        + ' renderer %d px (tolerance %d). They are measuring different fonts',
        [CScreens[s], CPPIs[p], w, r, tol]), Abs(w - r) <= tol);
    end;
end;

{ ===== which PPI a control is born at ======================================= }

procedure TTyMeasureFontDpiTest.TestAControlIsBornInTheDesignSpace;
{ Both bases, because they share no ancestor below TControl and the line exists twice. And
  SILENTLY: a font that announced the change would clear ParentFont on every control this
  library creates, and a control that has stopped following its parent's font is a
  different control. }
var
  btn: TTyButton;
  lbl: TTyLabel;
  plain: TControl;
begin
  SimulateScreen(168);
  plain := TControl.Create(nil);
  btn := TTyButton.Create(nil);
  lbl := TTyLabel.Create(nil);
  try
    AssertEquals('the control group: a plain LCL control IS born at the screen''s PPI, so'
      + ' there is something here to correct', 168, plain.Font.PixelsPerInch);
    AssertEquals('a windowed ty control is born at the design PPI', TyDesignPPI,
      btn.Font.PixelsPerInch);
    AssertEquals('a graphic ty control is born at the design PPI', TyDesignPPI,
      lbl.Font.PixelsPerInch);
    AssertTrue('...and still follows its parent''s font (windowed)',
      TParentFontProbe(btn).ParentFont);
    AssertTrue('...and still follows its parent''s font (graphic)',
      TParentFontProbe(lbl).ParentFont);
    AssertEquals('...with no size chosen', 0, btn.Font.Height);
    AssertTrue(Format('so the floor its constructor worked out belongs to the box its'
      + ' constructor made: %d px tall with a floor of %d',
      [btn.Height, btn.Constraints.MinHeight]), btn.Height >= btn.Constraints.MinHeight);
  finally
    lbl.Free;
    btn.Free;
    plain.Free;
  end;
end;

procedure TTyMeasureFontDpiTest.TestAChildWithATouchedFontTakesItsParentsPPI;
{ The other half of the rule. A ParentFont child is given its parent's PPI by LCL when it
  is parented; one whose font was touched is given nothing by anybody, and being born at 96
  would leave it at 96 on a form that was scaled long ago -- drawn at 100% among neighbours
  at 175%. }
var
  frm: TForm;
  own, follows: TTyButton;
  lbl: TTyLabel;
begin
  SimulateScreen(168);
  frm := TForm.CreateNew(nil);
  try
    frm.Font.PixelsPerInch := 168;      // a form the DPI pass has been over
    frm.Font.Size := 9;

    follows := TTyButton.Create(frm);
    follows.Parent := frm;
    AssertEquals('the control group: LCL hands a ParentFont child its parent''s PPI', 168,
      follows.Font.PixelsPerInch);

    own := TTyButton.Create(frm);
    own.Font.Style := [fsBold];
    AssertFalse('precondition: touching the font stopped it following the parent',
      TParentFontProbe(own).ParentFont);
    AssertEquals('precondition: still in the design space', TyDesignPPI,
      own.Font.PixelsPerInch);
    own.Parent := frm;
    AssertEquals('a windowed child with a font of its own takes the parent''s PPI', 168,
      own.Font.PixelsPerInch);
    AssertTrue('...and keeps the font it was given', fsBold in own.Font.Style);
    AssertFalse('...and its independence', TParentFontProbe(own).ParentFont);

    lbl := TTyLabel.Create(frm);
    lbl.Font.Style := [fsItalic];
    lbl.Parent := frm;
    AssertEquals('a graphic child with a font of its own takes the parent''s PPI', 168,
      lbl.Font.PixelsPerInch);
  finally
    frm.Free;
  end;
end;

{ ===== the library, end to end ============================================== }

procedure TTyMeasureFontDpiTest.TestSizeFloorsFollowTheControlPPIOnly;
{ The 175% screenshot, as numbers. A floor at 168 PPI is the floor at 96 PPI scaled by
  168/96 -- give or take the rounding of each addend and the font's own hinting -- and it
  was nowhere near: the caption was measured with a 37 px font while a 21 px one was drawn,
  so a button's height floor outgrew the button and LCL clamped the bounds up to it. }

  procedure Check(ACls: TControlClass; ABirth: TBirth);
  var
    f96, f168: TSizeFacts;
    err, who: string;
    ok: Boolean;

    procedure Scales(const AWhat: string; A96, A168: Integer);
    var
      want, tol: Integer;
    begin
      want := MulDiv(A96, 168, 96);
      tol := Max(4, want div 10);
      AssertTrue(Format('%s %s: %d at 96 PPI, so about %d at 168 PPI (tolerance %d), but'
        + ' it is %d', [who, AWhat, A96, want, tol, A168]),
        Abs(A168 - want) <= tol);
    end;

  begin
    who := ACls.ClassName + ' (' + BirthText(ABirth) + ')';
    ok := FactsOf(ACls, 96, 96, ABirth, f96, err);
    AssertTrue(who + ' could not be built at 96 PPI: ' + err, ok);
    ok := FactsOf(ACls, 168, 168, ABirth, f168, err);
    AssertTrue(who + ' could not be built at 168 PPI: ' + err, ok);
    AssertTrue(who + ': precondition, it owns a height floor', f96.MinH > 0);
    Scales('height', f96.H, f168.H);
    Scales('width', f96.W, f168.W);
    Scales('height floor', f96.MinH, f168.MinH);
    if f96.MinW > 0 then Scales('width floor', f96.MinW, f168.MinW);
    if f96.PrefH > 0 then Scales('preferred height', f96.PrefH, f168.PrefH);
    if f96.PrefW > 0 then Scales('preferred width', f96.PrefW, f168.PrefW);
  end;

var
  birth: TBirth;
begin
  for birth := Low(TBirth) to High(TBirth) do
  begin
    Check(TTyButton, birth);
    Check(TTyCheckBox, birth);
    Check(TTyRadioButton, birth);
    Check(TTyToggleSwitch, birth);
    Check(TTyLabel, birth);
  end;
end;

procedure TTyMeasureFontDpiTest.TestNoRegisteredControlSizesItselfFromTheScreen;
{ EVERY control the palette offers, not the ones somebody remembered. The population is
  parsed out of designtime/tyControls.Design.pas by test.designregistry -- the file a control
  has to be edited into to reach the palette at all -- so a control added tomorrow is swept
  tomorrow.

  Each makes the journey to the SAME PPI on two different screens, and has to come out the
  same size with the same floor both times. Two pairs: a form shown at 168 PPI on a 96 and
  on a 168 desktop, and a plain 96-PPI form on this runner's 72 against a real 96. }
var
  names, differ, unbuilt: TStringList;
  i, swept, withFloor: Integer;
  cls: TPersistentClass;
  a, b: TSizeFacts;
  err: string;
  birth: TBirth;

  procedure Pair(AScreenA, AScreenB, APPI: Integer);
  begin
    if not FactsOf(TControlClass(cls), AScreenA, APPI, birth, a, err) then
    begin
      if unbuilt.IndexOf(names[i] + ' -- ' + err) < 0 then
        unbuilt.Add(names[i] + ' -- ' + err);
      Exit;
    end;
    if not FactsOf(TControlClass(cls), AScreenB, APPI, birth, b, err) then
    begin
      if unbuilt.IndexOf(names[i] + ' -- ' + err) < 0 then
        unbuilt.Add(names[i] + ' -- ' + err);
      Exit;
    end;
    if not SameFacts(a, b) then
      differ.Add(Format('%s (%s) at %d PPI: on a %d-PPI screen %s; on a %d-PPI screen %s',
        [names[i], BirthText(birth), APPI, AScreenA, FactsText(a), AScreenB, FactsText(b)]));
    if (a.MinW > 0) or (a.MinH > 0) or (a.PrefW > 0) or (a.PrefH > 0) then
      Inc(withFloor);
  end;

begin
  names := TStringList.Create;
  differ := TStringList.Create;
  unbuilt := TStringList.Create;
  try
    CollectRegisteredClassNames(names);
    AssertTrue('the design-registry parser found the palette', names.IndexOf('TTyButton') >= 0);
    swept := 0;
    withFloor := 0;
    for i := 0 to names.Count - 1 do
    begin
      cls := GetClass(names[i]);
      { An unresolvable name is test.version's to report. Forms size themselves through the
        chrome engine and are not dropped on a form; components are not controls. }
      if cls = nil then Continue;
      if not cls.InheritsFrom(TControl) then Continue;
      if cls.InheritsFrom(TCustomForm) then Continue;
      Inc(swept);
      for birth := Low(TBirth) to High(TBirth) do
      begin
        Pair(96, 168, 168);
        Pair(72, 96, 96);
      end;
    end;

    AssertTrue(Format('the sweep must cover the palette, and it covered %d classes', [swept]),
      swept > 100);
    { Most controls own neither a floor nor a preferred size -- a list or a panel is as big
      as it is told to be -- so the comparison bites hardest on the captioned ones. Enough
      of them have to be in the population for "nothing differs" to mean something. }
    AssertTrue(Format('...and enough of them must have had a floor to compare: %d of %d'
      + ' pairs did', [withFloor, 4 * swept]), withFloor >= 100);
    AssertEquals('controls that could not be built for the sweep (each one is a control'
      + ' this guard does NOT cover):' + LineEnding + unbuilt.Text, 0, unbuilt.Count);
    AssertEquals('controls whose size depends on the SCREEN''s PPI and not only on their'
      + ' own. Something in them measures text with a font sized in points, reads the'
      + ' screen directly, or settled its size while its font still carried the screen''s'
      + ' PPI:' + LineEnding + differ.Text, 0, differ.Count);
  finally
    unbuilt.Free;
    differ.Free;
    names.Free;
  end;
end;

procedure TTyMeasureFontDpiTest.TestEveryRegisteredControlScalesItsSizeWithThePPI;
{ The same population, asked the other question: not "does the screen leak in" but "does
  the size FOLLOW the PPI". A form shown at 192 PPI on a 192-PPI desktop has to give every
  control twice the box, and twice the floor, of its 96-PPI twin -- an addend that was never
  scaled leaves it short, an addend scaled twice leaves it long.

  The tolerance is deliberately not tight. A measured caption is not exactly proportional to
  the PPI (hinting, and the rounding of each addend), so this catches a size that is out by
  a row height or a whole font -- which is what the defects of this family look like -- and
  not one that is out by a pixel. }
var
  names, bad, unbuilt: TStringList;
  i, swept: Integer;
  cls: TPersistentClass;
  lo, hi: TSizeFacts;
  err: string;
  birth: TBirth;

  procedure Scales(const AWhat: string; ALo, AHi: Integer);
  var
    want, tol: Integer;
  begin
    if (ALo <= 0) and (AHi <= 0) then Exit;
    want := 2 * ALo;
    tol := Max(4, want div 10);
    if Abs(AHi - want) > tol then
      bad.Add(Format('%s (%s) %s: %d at 96 PPI, so about %d at 192 PPI, but it is %d',
        [names[i], BirthText(birth), AWhat, ALo, want, AHi]));
  end;

begin
  names := TStringList.Create;
  bad := TStringList.Create;
  unbuilt := TStringList.Create;
  try
    CollectRegisteredClassNames(names);
    swept := 0;
    for i := 0 to names.Count - 1 do
    begin
      cls := GetClass(names[i]);
      if cls = nil then Continue;
      if not cls.InheritsFrom(TControl) then Continue;
      if cls.InheritsFrom(TCustomForm) then Continue;
      Inc(swept);
      for birth := Low(TBirth) to High(TBirth) do
      begin
        if not FactsOf(TControlClass(cls), 96, 96, birth, lo, err) then
        begin
          unbuilt.Add(names[i] + ' -- ' + err);
          Continue;
        end;
        if not FactsOf(TControlClass(cls), 192, 192, birth, hi, err) then
        begin
          unbuilt.Add(names[i] + ' -- ' + err);
          Continue;
        end;
        { An aligned control's long axis belongs to its parent: LCL's pass leaves it alone,
          and what the control would prefer along it is built on that same length. }
        if not (lo.Align in [alTop, alBottom, alClient]) then
        begin
          Scales('width', lo.W, hi.W);
          Scales('width floor', lo.MinW, hi.MinW);
          Scales('preferred width', lo.PrefW, hi.PrefW);
        end;
        if not (lo.Align in [alLeft, alRight, alClient]) then
        begin
          Scales('height', lo.H, hi.H);
          Scales('height floor', lo.MinH, hi.MinH);
          Scales('preferred height', lo.PrefH, hi.PrefH);
        end;
      end;
    end;
    AssertTrue(Format('the sweep must cover the palette, and it covered %d classes', [swept]),
      swept > 100);
    AssertEquals('controls that could not be built for the sweep:' + LineEnding
      + unbuilt.Text, 0, unbuilt.Count);
    AssertEquals('controls whose size does not follow their PPI:' + LineEnding + bad.Text,
      0, bad.Count);
  finally
    unbuilt.Free;
    bad.Free;
    names.Free;
  end;
end;

procedure TTyMeasureFontDpiTest.TestPaintedLayoutDoesNotFollowTheScreen;
{ The three places that measure INSIDE the paint, where no size floor can see them: the gap
  a group box erases behind its caption, the tab widths of a tab strip, the wrap points and
  line pitch of a wrapping label. Painted at one control PPI on two screens; the pixels have
  to be the same pixels. }
const
  CNames: array[KIND_GROUPBOX..KIND_LABEL] of string =
    ('TTyGroupBox', 'TTyTabSet', 'TTyLabel (WordWrap)');
var
  k, i, firstDiff, distinct: Integer;
  a, b, lo: TLongWordDynArray;
begin
  for k := KIND_GROUPBOX to KIND_LABEL do
  begin
    a := Painted(k, 96, 168);
    b := Painted(k, 168, 168);
    AssertTrue(CNames[k] + ': precondition, something was painted', Length(a) > 0);
    AssertEquals(CNames[k] + ': both renders are the same size', Length(a), Length(b));

    distinct := 0;
    for i := 1 to High(a) do
      if a[i] <> a[0] then begin distinct := 1; Break; end;
    AssertEquals(CNames[k] + ': precondition, the render is not one flat colour', 1, distinct);

    { And the control PPI IS an input -- otherwise "identical" would prove nothing about
      a harness that ignores every PPI it is given. }
    lo := Painted(k, 96, 96);
    AssertTrue(CNames[k] + ': precondition, the control PPI changes the render',
      Length(lo) <> Length(a));

    firstDiff := -1;
    for i := 0 to High(a) do
      if a[i] <> b[i] then begin firstDiff := i; Break; end;
    AssertEquals(CNames[k] + ': painted at 168 PPI on a 96-PPI screen and on a 168-PPI one,'
      + ' the two must be the same pixels; the first difference is at pixel index',
      -1, firstDiff);
  end;
end;

procedure TTyMeasureFontDpiTest.TestAFormDesignedAt96LoadsAtItsDesignedSizeOnAHiDpiDesktop;
{ THE WHOLE JOURNEY, which is what the 175% screenshot was a picture of. A form is drawn on
  a 96-PPI machine, streamed, and read back on a 168-PPI one -- through a real TReader, so
  csLoading and Loaded are the real ones -- and then LCL's own DPI pass runs, exactly as
  TCustomForm.AfterConstruction runs it.

  What makes this different from every "born at that PPI" test: while the form is being
  READ, a control's font already carries the SCREEN's PPI (a TFont is born with it) but its
  bounds are still the designer's 96-PPI numbers. Whatever a control concludes about its
  size in that window is concluded from two numbers that do not belong together. }
const
  CDesignW = 640;
  CDesignH = 480;
var
  src, dst: TForm;
  ms: TMemoryStream;
  i: Integer;
  savedScaled: Boolean;
  bad: TStringList;
  c: TControl;
  wantW, wantH: Integer;

  procedure Put(ACls: TControlClass; const AName: string; ATop, AW, AH: Integer);
  var
    ctl: TControl;
    pi: PPropInfo;
  begin
    ctl := ACls.Create(src);
    ctl.Name := AName;
    ctl.Parent := src;
    ctl.SetBounds(10, ATop, AW, AH);
    pi := GetPropInfo(ctl, 'Caption');
    if pi <> nil then SetStrProp(ctl, pi, 'Caption ' + AName);
  end;

begin
  savedScaled := Application.Scaled;
  bad := TStringList.Create;
  ms := TMemoryStream.Create;
  src := nil;
  dst := nil;
  try
    { Off while the two forms are CREATED: with it on, TCustomForm.AfterConstruction runs a
      DPI pass of its own towards Monitor.PixelsPerInch, on a form that is still empty, and
      leaves PixelsPerInch at whatever this headless process calls a monitor. A real
      application reads the form INSIDE the constructor, so its pass sees the designed
      form; here the read comes after, and the pass is run by hand below. }
    Application.Scaled := False;

    { The design machine. }
    SimulateScreen(96);
    src := TForm.CreateNew(nil);
    src.Font.PixelsPerInch := 96;
    src.SetBounds(0, 0, CDesignW, CDesignH);
    Put(TTyButton,       'Btn',    10, 100, 30);
    Put(TTyCheckBox,     'Chk',    50, 140, 26);
    Put(TTyRadioButton,  'Rad',    90, 140, 26);
    Put(TTyToggleSwitch, 'Tog',   130, 160, 26);
    Put(TTyLabel,        'Lbl',   170, 140, 24);
    Put(TTyGroupBox,     'Grp',   210, 200, 80);
    ms.WriteComponent(src);

    { The user's machine. }
    SimulateScreen(168);
    dst := TForm.CreateNew(nil);
    { What TCustomDesignControl.Create does for a scaled application: the FORM's font is
      put at the design PPI. The controls' fonts are not -- they are born at the screen's. }
    dst.Font.PixelsPerInch := 96;
    AssertEquals('precondition: the form is in its 96-PPI design space', 96,
      dst.PixelsPerInch);
    { On from here: TCustomForm.Loaded only repairs the design fonts of a scaled form. }
    Application.Scaled := True;
    ms.Position := 0;
    ms.ReadComponent(dst);
    AssertEquals('precondition: every designed control came back', src.ControlCount,
      dst.ControlCount);
    AssertEquals('precondition: the form itself was read at its design size', CDesignW,
      dst.Width);

    { TCustomForm.AfterConstruction, with the monitor's PPI written in. }
    dst.AutoAdjustLayout(lapAutoAdjustForDPI, 96, 168,
      dst.Width, MulDiv(dst.Width, 168, 96));

    for i := 0 to dst.ControlCount - 1 do
    begin
      c := dst.Controls[i];
      wantW := MulDiv(src.Controls[i].Width, 168, 96);
      wantH := MulDiv(src.Controls[i].Height, 168, 96);
      if c.Font.PixelsPerInch <> 168 then
        bad.Add(Format('%s: font PPI %d after the pass, expected 168',
          [c.Name, c.Font.PixelsPerInch]));
      if (Abs(c.Width - wantW) > 1) or (Abs(c.Height - wantH) > 1) then
        bad.Add(Format('%s: designed %dx%d, so %dx%d at 168 PPI, but it is %dx%d'
          + ' (floor %dx%d)',
          [c.Name, src.Controls[i].Width, src.Controls[i].Height, wantW, wantH,
           c.Width, c.Height, c.Constraints.MinWidth, c.Constraints.MinHeight]));
    end;
    AssertEquals('a form designed at 96 PPI and loaded on a 168-PPI desktop must come out'
      + ' at its designed size times 1.75:' + LineEnding + bad.Text, 0, bad.Count);
  finally
    Application.Scaled := savedScaled;
    dst.Free;
    src.Free;
    ms.Free;
    bad.Free;
  end;
end;

{ ===== and it must stay one function ======================================== }

{ Comments and literals blanked out: prose ABOUT a construct is not the construct. The
  scanner is shared with the other source guards (test.dpi.support). }
function CodeOnly(const S: string): string;
begin
  Result := TyTestCodeOnly(S);
end;

{ How many times ACode ASSIGNS the Size or the Height of something whose name ends in Font:
  `X.Font.Size := ...`, `AFont.Height := ...`, `FFont.Size:=...`. Whitespace-tolerant and
  case-blind, because Pascal is. }
function CountFontSizeWrites(const ACode: string): Integer;
var
  lc: string;
  i, j, n: Integer;

  procedure SkipBlanks;
  begin
    while (j <= n) and (lc[j] in [' ', #9, #13, #10]) do Inc(j);
  end;

begin
  Result := 0;
  lc := LowerCase(ACode);
  n := Length(lc);
  i := 1;
  while i <= n - 3 do
  begin
    if (lc[i] = 'f') and (Copy(lc, i, 4) = 'font') then
    begin
      j := i + 4;
      SkipBlanks;
      if (j <= n) and (lc[j] = '.') then
      begin
        Inc(j);
        SkipBlanks;
        if Copy(lc, j, 4) = 'size' then Inc(j, 4)
        else if Copy(lc, j, 6) = 'height' then Inc(j, 6)
        else j := 0;
        if (j > 0) and ((j > n) or not (lc[j] in ['a'..'z', '0'..'9', '_'])) then
        begin
          SkipBlanks;
          if Copy(lc, j, 2) = ':=' then Inc(Result);
        end;
      end;
    end;
    Inc(i);
  end;
end;

procedure TTyMeasureFontDpiTest.TestNoUnitSizesAFontByItself;
{ The defect was a COPY. TyConfigureMeasureFont existed and was right about everything
  except the one line, and fifteen sites in twelve units carried their own version of its
  three lines -- so the measuring font had sixteen definitions, and fixing one would have
  left fifteen.

  So: a unit under source/ that assigns a font's Size or Height is either on this list,
  with the reason it is not a measurement, or it is a copy coming back. The count is part
  of the contract -- a new write in a listed unit has to be looked at too. }
type
  TAllowed = record
    Name: string;
    Count: Integer;
  end;
const
  CAllowed: array[0..3] of TAllowed = (
    { TyConfigureMeasureFont itself: a pixel Height, the only measuring font there is. }
    (Name: 'tyControls.Painter.pas'; Count: 1),
    { ScaleFontsPPI, once per base class: puts "no size chosen" (Height 0) back after
      LCL's DPI pass latched a height into it. See test.dpi.fontlatch. }
    (Name: 'tyControls.Base.pas'; Count: 2),
    { The font DIALOG writing its result into the TFont the application handed it. }
    (Name: 'tyControls.Dialogs.Font.pas'; Count: 2),
    { The value list editor parsing a font VALUE the user typed into a cell. }
    (Name: 'tyControls.ValueListEditor.pas'; Count: 2));
var
  files, sl, bad: TStringList;
  i, k, n, want, seen: Integer;
  nm: string;
begin
  AssertEquals('the scanner counts what it is meant to count', 3,
    CountFontSizeWrites('A.Font.Size := 1; b.font . height:=2; FFont.Size := 3;'
      + ' x := Font.Size; Font.SizeHint := 4; y := Font.Height;'));
  AssertEquals('...and nothing inside a comment or a literal', 0,
    CountFontSizeWrites(CodeOnly('{ Font.Size := 1 { nested } Font.Size := 2 }'
      + ' // Font.Size := 3' + LineEnding + ' s := ''Font.Size := 4''; (* Font.Size := 5 *)')));

  files := FindAllFiles(RepoRoot + 'source', '*.pas', False);
  sl := TStringList.Create;
  bad := TStringList.Create;
  try
    AssertTrue('the library''s units were found', files.Count > 100);
    seen := 0;
    for i := 0 to files.Count - 1 do
    begin
      sl.LoadFromFile(files[i]);
      n := CountFontSizeWrites(CodeOnly(sl.Text));
      nm := ExtractFileName(files[i]);
      want := 0;
      for k := 0 to High(CAllowed) do
        if SameText(CAllowed[k].Name, nm) then
        begin
          want := CAllowed[k].Count;
          Inc(seen);
        end;
      if n <> want then
        bad.Add(Format('%s assigns a font Size / Height %d time(s), %d accounted for',
          [nm, n, want]));
    end;
    AssertEquals('every unit on the allow-list still exists', Length(CAllowed), seen);
    AssertEquals('a font is sized in ONE place, TyConfigureMeasureFont. A unit that writes'
      + ' Font.Size or Font.Height itself is measuring with a font of its own, which is how'
      + ' the measured caption and the drawn one came apart at every PPI but 96. Call'
      + ' TyConfigureMeasureFont; if the write is not a measurement, account for it in'
      + ' CAllowed:' + LineEnding + bad.Text, 0, bad.Count);
  finally
    bad.Free;
    sl.Free;
    files.Free;
  end;
end;

initialization
  RegisterTest(TTyMeasureFontDpiTest);

end.
