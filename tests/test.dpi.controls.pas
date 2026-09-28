unit test.dpi.controls;
{ Single controls that got ONE number wrong at a scaling other than 100%.
                                                                  (ACTom/TyControls#2)

  The measuring font and the PPI a control is born with (tests/test.dpi.measurefont) were
  wrong everywhere at once. These were wrong in one place each, and were found by LOOKING:
  every example form was read, taken through LCL's DPI pass to 175% and painted
  (tests/test.dpi.snapshot), and the picture was laid beside the 100% one scaled up.

    - a gauge's figure was the right fraction of the dial, and then scaled again;
    - a shell list shared its pane out among the columns in device px and stored the
      shares in a property that is logical px;
    - an auto-sized control kept its 96-PPI size along the axis AutoSize does not decide.

  The gauge's was one of a KIND, and the rest of the kind was found by reading the source
  for it rather than by looking: a number the painter scales (a border width, a corner
  radius, a glyph's thickness, a font size) handed over already scaled. Nine more places,
  each one a line that is twice as thick at 175% as its neighbours. The last test here is
  that reading, kept.

  REGISTERS NO SCREEN SIMULATION of its own: nothing here depends on the screen, only on
  the PPI a control is given. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, StrUtils, Types, Math, Controls, Forms, Graphics, LCLType, LMessages,
  IntfGraphics, FPimage, FileUtil,
  fpcunit, testregistry,
  test.dpi.support,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.Columns,
  tyControls.Button, tyControls.CheckBox, tyControls.TyLabel, tyControls.Gauge,
  tyControls.CircularProgress, tyControls.ShellListView, tyControls.ComboBox,
  tyControls.Edit, tyControls.TextMenu, tyControls.HtmlLabel;

type
  TShellListResizeProbe = class(TTyShellListView)
  public
    procedure CallResize;
  end;

  { A graphic control that fits its WIDTH and has no opinion about its height. }
  TWidthOnlyGraphic = class(TTyGraphicControl)
  protected
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
  end;

  TTyControlDpiTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    function S(AValue, APPI: Integer): Integer;
    { Rows of AControl's picture that change when AToggle is flipped: how TALL the thing
      the toggle draws is, whatever else is in the picture. }
    function FigureHeight(AControl: TControl; APPI, ASidePx: Integer;
      AShow, AHide: TNotifyEvent): Integer;
    procedure GaugeShow(Sender: TObject);
    procedure GaugeHide(Sender: TObject);
    procedure CircShow(Sender: TObject);
    procedure CircHide(Sender: TObject);
    procedure Cross(APPI: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestGaugeFigureFollowsThePPI;
    procedure TestCircularProgressFigureFollowsThePPI;
    procedure TestShellListColumnsFillThePaneAtAnyPPI;
    procedure TestAnAutoSizedButtonStillScalesItsHeight;
    procedure TestAnAutoSizedCheckBoxStillScalesItsHeight;
    procedure TestAnAutoSizedWrappingLabelStillScalesItsWidth;
    procedure TestAnAutoSizedWrappingHtmlLabelStillScalesItsWidth;
    procedure TestAnAutoSizedGraphicControlStillScalesTheAxisItDoesNotFit;
    procedure TestAControlThatIsNotAutoSizedScalesBothAsBefore;
    procedure TestAnEditableCombosFieldFollowsItThroughThePass;
    procedure TestTheMultiClickSlopIsLogicalPx;
    procedure TestNothingScaledIsHandedToAParameterThatScales;
  end;

implementation

const
  HI = 168;      // 175%

procedure TShellListResizeProbe.CallResize;
begin
  Resize;
end;

procedure TWidthOnlyGraphic.CalculatePreferredSize(var PreferredWidth,
  PreferredHeight: Integer; WithThemeSpace: Boolean);
begin
  if WithThemeSpace then ;
  PreferredWidth := MulDiv(90, Font.PixelsPerInch, 96);
  PreferredHeight := 0;
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

{ A graphic control paints on whatever DC its paint message carries. }
function PaintGraphic(AControl: TControl; AW, AH: Integer): TLongWordDynArray;
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(AW, AH);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, AW, AH);
    AControl.Perform(LM_PAINT, WPARAM(bmp.Canvas.Handle), 0);
    Result := Snapshot(bmp);
  finally
    bmp.Free;
  end;
end;

{ ===== harness ============================================================== }

procedure TTyControlDpiTest.SetUp;
begin
  inherited SetUp;
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(':root { --font-size-base: 9; --line-height: 14; --control-height: 24; }');
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(40, 40, 900, 700);
  FForm.Font.PixelsPerInch := 96;
  FForm.Font.Size := 9;       // see TControlDpiRoundTripTest.Build for why the FORM is pinned
end;

procedure TTyControlDpiTest.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

function TTyControlDpiTest.S(AValue, APPI: Integer): Integer;
begin
  Result := MulDiv(AValue, APPI, 96);
end;

procedure TTyControlDpiTest.Cross(APPI: Integer);
begin
  { Exactly what TCustomForm.AfterConstruction does for a form designed at 96. }
  FForm.AutoAdjustLayout(lapAutoAdjustForDPI, 96, APPI,
    FForm.Width, MulDiv(FForm.Width, APPI, 96));
end;

function TTyControlDpiTest.FigureHeight(AControl: TControl; APPI, ASidePx: Integer;
  AShow, AHide: TNotifyEvent): Integer;
var
  withFig, without: TLongWordDynArray;
  x, y, first, last: Integer;
begin
  AControl.Font.PixelsPerInch := APPI;
  AControl.SetBounds(0, 0, ASidePx, ASidePx);
  AShow(AControl);
  withFig := PaintGraphic(AControl, ASidePx, ASidePx);
  AHide(AControl);
  without := PaintGraphic(AControl, ASidePx, ASidePx);
  first := -1;
  last := -1;
  for y := 0 to ASidePx - 1 do
    for x := 0 to ASidePx - 1 do
      if withFig[y * ASidePx + x] <> without[y * ASidePx + x] then
      begin
        if first < 0 then first := y;
        last := y;
        Break;
      end;
  if first < 0 then Exit(0);
  Result := last - first + 1;
end;

procedure TTyControlDpiTest.GaugeShow(Sender: TObject);
begin
  TTyGauge(Sender).ShowValue := True;
end;

procedure TTyControlDpiTest.GaugeHide(Sender: TObject);
begin
  TTyGauge(Sender).ShowValue := False;
end;

procedure TTyControlDpiTest.CircShow(Sender: TObject);
begin
  TTyCircularProgress(Sender).ShowValue := True;
end;

procedure TTyControlDpiTest.CircHide(Sender: TObject);
begin
  TTyCircularProgress(Sender).ShowValue := False;
end;

{ ===== a figure sized from the dial ========================================= }

procedure TTyControlDpiTest.TestGaugeFigureFollowsThePPI;
{ The figure is a sixth of the dial. The dial is device px; the painter takes a LOGICAL
  font size and scales it. Handed the device number it scaled a size that was already
  scaled, and the figure came out 1.75x too tall at 175% -- out of the ring, in the demo. }
var
  g: TTyGauge;
  lo, hi_: Integer;
begin
  g := TTyGauge.Create(FForm);
  g.Controller := FCtl;
  g.Parent := FForm;
  g.AnimationsEnabled := False;
  g.Style := gsRing;
  g.Value := 62;
  lo := FigureHeight(g, 96, 140, @GaugeShow, @GaugeHide);
  hi_ := FigureHeight(g, HI, S(140, HI), @GaugeShow, @GaugeHide);
  AssertTrue('precondition: the figure was found in the 96-PPI picture', lo > 4);
  AssertTrue(Format('the figure is %d px tall in a 140 px dial at 96 PPI, so about %d in'
    + ' the same dial at 168 PPI -- but it is %d', [lo, S(lo, HI), hi_]),
    Abs(hi_ - S(lo, HI)) <= Max(3, S(lo, HI) div 5));
end;

procedure TTyControlDpiTest.TestCircularProgressFigureFollowsThePPI;
var
  c: TTyCircularProgress;
  lo, hi_: Integer;
begin
  c := TTyCircularProgress.Create(FForm);
  c.Controller := FCtl;
  c.Parent := FForm;
  c.AnimationsEnabled := False;
  c.Position := 68;
  lo := FigureHeight(c, 96, 140, @CircShow, @CircHide);
  hi_ := FigureHeight(c, HI, S(140, HI), @CircShow, @CircHide);
  AssertTrue('precondition: the figure was found in the 96-PPI picture', lo > 4);
  AssertTrue(Format('the figure is %d px tall in a 140 px ring at 96 PPI, so about %d in'
    + ' the same ring at 168 PPI -- but it is %d', [lo, S(lo, HI), hi_]),
    Abs(hi_ - S(lo, HI)) <= Max(3, S(lo, HI) div 5));
end;

{ ===== columns shared out of a pane ========================================= }

procedure TTyControlDpiTest.TestShellListColumnsFillThePaneAtAnyPPI;
{ A column's Width is LOGICAL px: the list scales it where the columns are laid out. The
  auto-size shared the pane out in DEVICE px and stored the shares as they were, so the
  columns were scaled once more when they were used -- at 175% the first column took most
  of the pane and the last two were pushed out of it. }

  function Overrun(APPI: Integer): Integer;
  var
    lv: TShellListResizeProbe;
    i, total: Integer;
  begin
    lv := TShellListResizeProbe.Create(FForm);
    lv.Controller := FCtl;
    lv.Parent := FForm;
    lv.Font.PixelsPerInch := APPI;
    AssertTrue('precondition: auto-sized columns are the default', lv.AutoSizeColumns);
    lv.SetBounds(0, 0, S(700, APPI), S(300, APPI));
    lv.CallResize;
    AssertTrue('precondition: the list has columns to share the pane among',
      lv.Header.Columns.Count >= 2);
    total := 0;
    for i := 0 to lv.Header.Columns.Count - 1 do
      Inc(total, MulDiv(TTyColumn(lv.Header.Columns.Items[i]).Width, APPI, 96));
    Result := total - lv.ClientWidth;
    lv.Free;
  end;

var
  d: Integer;
begin
  d := Overrun(96);
  AssertTrue(Format('precondition: at 96 PPI the columns fill the pane (off by %d px)', [d]),
    Abs(d) <= 1);
  d := Overrun(HI);
  { A pixel a column at most: each width is rounded on its way to device px. }
  AssertTrue(Format('at 168 PPI the columns, AS THEY ARE DRAWN, must fill the pane and no'
    + ' more -- they run %d px past it', [d]), Abs(d) <= 4);
end;

{ ===== the axis AutoSize does not decide ==================================== }

procedure TTyControlDpiTest.TestAnAutoSizedButtonStillScalesItsHeight;
{ A push button proposes a WIDTH and answers 0 for the height -- the height belongs to
  whoever lays the row out. LCL's DPI pass skips both axes of an AutoSize control, so the
  height nobody re-fits was never scaled: at 175% the button stayed at its 96-PPI height,
  pushed up only as far as its own floor. }
var
  b: TTyButton;
begin
  b := TTyButton.Create(FForm);
  b.Controller := FCtl;
  b.Parent := FForm;
  b.Caption := 'Save';
  b.AutoSize := True;
  b.SetBounds(10, 10, 100, 40);
  AssertEquals('precondition: designed 40 px tall', 40, b.Height);

  Cross(HI);

  AssertTrue(Format('an auto-sized button designed 40 px tall is %d px tall at 168 PPI,'
    + ' and it is %d (floor %d)', [S(40, HI), b.Height, b.Constraints.MinHeight]),
    Abs(b.Height - S(40, HI)) <= 1);
end;

procedure TTyControlDpiTest.TestAnAutoSizedCheckBoxStillScalesItsHeight;
var
  c: TTyCheckBox;
begin
  c := TTyCheckBox.Create(FForm);
  c.Controller := FCtl;
  c.Parent := FForm;
  c.Caption := 'Remember me';
  c.AutoSize := True;
  c.SetBounds(10, 60, 160, 36);

  Cross(HI);

  AssertTrue(Format('an auto-sized check box designed 36 px tall is %d px tall at 168 PPI,'
    + ' and it is %d', [S(36, HI), c.Height]), Abs(c.Height - S(36, HI)) <= 1);
end;

procedure TTyControlDpiTest.TestAnAutoSizedWrappingLabelStillScalesItsWidth;
{ A WRAPPING label takes its width as given -- the width is where the text wraps. With
  AutoSize on, LCL skipped it; the label kept its 96-PPI width at 175%, broke the same text
  into twice the lines and ran into whatever stood below it. }
var
  l: TTyLabel;
begin
  l := TTyLabel.Create(FForm);
  l.Controller := FCtl;
  l.Parent := FForm;
  l.WordWrap := True;
  l.AutoSize := True;
  l.Caption := 'The label keeps its width and grows its height to fit however many lines'
    + ' the text needs.';
  l.Width := 260;
  AssertEquals('precondition: designed 260 px wide', 260, l.Width);

  Cross(HI);

  AssertTrue(Format('an auto-sized wrapping label designed 260 px wide is %d px wide at'
    + ' 168 PPI, and it is %d', [S(260, HI), l.Width]), Abs(l.Width - S(260, HI)) <= 1);
end;

procedure TTyControlDpiTest.TestAnAutoSizedWrappingHtmlLabelStillScalesItsWidth;
{ The HTML label wraps at its width too, and has the rule of its own. }
var
  l: TTyHtmlLabel;
begin
  l := TTyHtmlLabel.Create(FForm);
  l.Controller := FCtl;
  l.Parent := FForm;
  l.WordWrap := True;
  l.AutoSize := True;
  l.Html := 'The label keeps its <b>width</b> and grows its height to fit however many'
    + ' lines the text needs.';
  l.Width := 260;
  AssertEquals('precondition: designed 260 px wide', 260, l.Width);

  Cross(HI);

  AssertTrue(Format('an auto-sized wrapping HTML label designed 260 px wide is %d px wide at'
    + ' 168 PPI, and it is %d', [S(260, HI), l.Width]), Abs(l.Width - S(260, HI)) <= 1);
end;

procedure TTyControlDpiTest.TestAnAutoSizedGraphicControlStillScalesTheAxisItDoesNotFit;
{ The rule lives in both base classes. The windowed one is asked through the button and the
  check box; this is the graphic one, through a control that answers a width and nothing
  else. }
var
  g: TWidthOnlyGraphic;
begin
  g := TWidthOnlyGraphic.Create(FForm);
  g.Controller := FCtl;
  g.Parent := FForm;
  g.AutoSize := True;
  g.SetBounds(10, 10, 90, 40);
  AssertEquals('precondition: designed 40 px tall', 40, g.Height);

  Cross(HI);

  AssertTrue(Format('the height nobody fits is scaled: %d px, wanted %d',
    [g.Height, S(40, HI)]), Abs(g.Height - S(40, HI)) <= 1);
end;

procedure TTyControlDpiTest.TestAControlThatIsNotAutoSizedScalesBothAsBefore;
{ The other side of the rule: nothing changed for a control whose AutoSize is off. }
var
  b: TTyButton;
begin
  b := TTyButton.Create(FForm);
  b.Controller := FCtl;
  b.Parent := FForm;
  b.Caption := 'Save';
  b.SetBounds(10, 10, 100, 40);

  Cross(HI);

  AssertTrue(Format('width %d, wanted %d', [b.Width, S(100, HI)]),
    Abs(b.Width - S(100, HI)) <= 1);
  AssertTrue(Format('height %d, wanted %d', [b.Height, S(40, HI)]),
    Abs(b.Height - S(40, HI)) <= 1);
end;

{ ===== a control inside a control ============================================ }

procedure TTyControlDpiTest.TestAnEditableCombosFieldFollowsItThroughThePass;
{ An editable combo is a frame, a chevron zone and a real edit between the two. LCL's pass
  scales the edit like any other child -- and the combo then lays it out again from its own
  size. Both have to land on the same rectangle, or the field covers the chevron. }
var
  c: TTyComboBox;
  e: TControl;
  i, left96, zone96, zone: Integer;
begin
  c := TTyComboBox.Create(FForm);
  c.Controller := FCtl;
  c.Parent := FForm;
  c.Style := csDropDown;
  c.SetBounds(10, 10, 190, 28);
  e := nil;
  for i := 0 to c.ControlCount - 1 do
    if c.Controls[i] is TTyEdit then e := c.Controls[i];
  AssertNotNull('precondition: an editable combo has a field', e);
  AssertTrue('precondition: and shows it', e.Visible);
  left96 := e.Left;
  zone96 := c.ClientWidth - (e.Left + e.Width);
  AssertTrue(Format('precondition: the field leaves the chevron its zone at 96 PPI (%d px)',
    [zone96]), zone96 >= 12);

  Cross(HI);

  zone := c.ClientWidth - (e.Left + e.Width);
  AssertTrue(Format('the field starts %d px in at 96 PPI, so %d at 168 -- it starts at %d',
    [left96, S(left96, HI), e.Left]), Abs(e.Left - S(left96, HI)) <= 2);
  AssertTrue(Format('the chevron zone is %d px at 96 PPI, so %d at 168 -- the field leaves'
    + ' it %d', [zone96, S(zone96, HI), zone]), Abs(zone - S(zone96, HI)) <= 2);
  AssertTrue(Format('and the field is as tall as the combo lets it be: %d of %d px',
    [e.Height, c.ClientHeight]), (e.Height > 0) and (e.Top + e.Height <= c.ClientHeight));
end;

{ ===== a distance the hand decides =========================================== }

procedure TTyControlDpiTest.TestTheMultiClickSlopIsLogicalPx;
{ The third press of a triple click counts when it lands within 4 px of the second. That
  is a distance on the DESK, so it is 4 logical px: 7 on a 168-PPI screen. As 4 device px
  a triple click -- select the line -- took a steadier hand at 175% than at 100%. }

  function ThirdPress(APPI, AAway: Integer): Integer;
  var
    lx, ly, n: Integer;
    tick: QWord;
  begin
    lx := 0;
    ly := 0;
    n := 0;
    tick := 0;
    TyMultiClickCount(False, 100, 100, lx, ly, tick, n, APPI);
    TyMultiClickCount(True, 100, 100, lx, ly, tick, n, APPI);       // the double
    Result := TyMultiClickCount(False, 100 + AAway, 100, lx, ly, tick, n, APPI);
  end;

begin
  AssertEquals('precondition: 4 px away is the triple at 96 PPI', 3, ThirdPress(96, 4));
  AssertEquals('precondition: 6 px away is a new click', 1, ThirdPress(96, 6));
  AssertEquals('6 px on a 168-PPI screen is within 4 logical px', 3, ThirdPress(168, 6));
  AssertEquals('and 8 px is not', 1, ThirdPress(168, 8));
  AssertEquals('a caller that names no PPI gets the 96-PPI answer', 1,
    ThirdPress(0, 6));
end;

{ ===== what the painter scales must not arrive scaled ======================= }

type
  TLogicalCallee = record
    Name: string;                  // lower case
    { 0-based positions of the parameters that are LOGICAL px; -1 unused;
      100 the last argument, 101 the one before it. }
    P: array[0..3] of Integer;
    Font: Integer;                 // which of them is a FONT SIZE, -1 none
  end;

const
  CLogical: array[0..17] of TLogicalCallee = (
    (Name: 'strokeborder';               P: (1, 2, -1, -1);   Font: -1),
    (Name: 'fillbackground';             P: (2, -1, -1, -1);  Font: -1),
    (Name: 'drawedge';                   P: (1, -1, -1, -1);  Font: -1),
    (Name: 'dropshadow';                 P: (1, 3, 4, -1);    Font: -1),
    (Name: 'drawtext';                   P: (3, 12, -1, -1);  Font: 3),
    (Name: 'measuretext';                P: (2, -1, -1, -1);  Font: 2),
    (Name: 'drawglyph';                  P: (3, 4, -1, -1);   Font: -1),
    (Name: 'tydrawglyph';                P: (100, 101, -1, -1); Font: -1),
    (Name: 'drawdropchevron';            P: (2, -1, -1, -1);  Font: -1),
    (Name: 'fillpointershape';           P: (9, -1, -1, -1);  Font: -1),
    (Name: 'drawimagefill';              P: (3, -1, -1, -1);  Font: -1),
    (Name: 'tyuniformcorners';           P: (0, -1, -1, -1);  Font: -1),
    (Name: 'tycorners';                  P: (0, 1, 2, 3);     Font: -1),
    (Name: 'tymeasuretextblock';         P: (2, 6, -1, -1);   Font: 2),
    (Name: 'tymeasurerenderedtextwidth'; P: (2, -1, -1, -1);  Font: 2),
    (Name: 'tyconfiguretextfont';        P: (2, -1, -1, -1);  Font: 2),
    (Name: 'tyconfiguremeasurefont';     P: (2, -1, -1, -1);  Font: 2),
    (Name: 'tyfontheightpx';             P: (0, -1, -1, -1);  Font: 0));

function IsIdentChar(c: Char): Boolean;
begin
  Result := c in ['a'..'z', 'A'..'Z', '0'..'9', '_'];
end;

{ Is there a CALL of AName in S: the whole name, then '(' ? }
function HasCall(const S, AName: string): Boolean;
var
  p, q, n: Integer;
begin
  Result := False;
  n := Length(S);
  p := 1;
  while p <= n do
  begin
    p := Pos(AName, S, p);
    if p = 0 then Exit;
    q := p + Length(AName);
    if ((p = 1) or not IsIdentChar(S[p - 1])) then
    begin
      while (q <= n) and (S[q] in [' ', #9, #13, #10]) do Inc(q);
      if (q <= n) and (S[q] = '(') then Exit(True);
    end;
    Inc(p);
  end;
end;

{ Is there anything in S that is measured in DEVICE px: the size of a control or a side of
  a rectangle. A style's Padding.Left is a side too, and logical -- so the owner is asked. }
function HasGeometry(const S: string): Boolean;
const
  CSides: array[0..3] of string = ('.left', '.top', '.right', '.bottom');
  CSizes: array[0..3] of string = ('clientwidth', 'clientheight', 'width', 'height');
var
  k, p, q, n: Integer;
  owner: string;
begin
  Result := False;
  n := Length(S);
  for k := 0 to High(CSizes) do
  begin
    p := 1;
    while p <= n do
    begin
      p := Pos(CSizes[k], S, p);
      if p = 0 then Break;
      q := p + Length(CSizes[k]);
      if ((p = 1) or not IsIdentChar(S[p - 1])) and ((q > n) or not IsIdentChar(S[q])) then
        Exit(True);
      Inc(p);
    end;
  end;
  for k := 0 to High(CSides) do
  begin
    p := 1;
    while p <= n do
    begin
      p := Pos(CSides[k], S, p);
      if p = 0 then Break;
      q := p + Length(CSides[k]);
      if (q > n) or not IsIdentChar(S[q]) then
      begin
        q := p - 1;
        while (q >= 1) and IsIdentChar(S[q]) do Dec(q);
        owner := Copy(S, q + 1, p - q - 1);
        if (Pos('padding', owner) = 0) and (Pos('margin', owner) = 0)
           and (Pos('inset', owner) = 0) and (Pos('offset', owner) = 0)
           and (owner <> 'pad') and (owner <> 'hpad') then
          Exit(True);
      end;
      Inc(p);
    end;
  end;
end;

{ Is AExpr (lower case) a value in DEVICE px? }
function IsDeviceValue(const AExpr: string; AFont: Boolean): Boolean;
var
  packed_: string;
begin
  { Taken back to logical on the way: P.Unscale(x), MulDiv(x, 96, PPI). }
  if Pos('unscale', AExpr) > 0 then Exit(False);
  packed_ := StringReplace(AExpr, ' ', '', [rfReplaceAll]);
  if Pos(',96,', packed_) > 0 then Exit(False);
  Result := HasCall(AExpr, 'scale') or HasCall(AExpr, 'scalei') or HasCall(AExpr, 'scalepx')
    or HasCall(AExpr, 'px') or HasCall(AExpr, 'dp') or HasCall(AExpr, 'muldiv');
  { A font size worked out from the size of something is device px whoever scaled it. }
  if (not Result) and AFont then Result := HasGeometry(AExpr);
end;

{ The arguments of the call whose '(' is at AOpen. False when it is not a complete call. }
function SplitArguments(const S: string; AOpen: Integer; AArgs: TStrings): Boolean;
var
  i, n, depth, from: Integer;
begin
  Result := False;
  AArgs.Clear;
  n := Length(S);
  depth := 0;
  from := AOpen + 1;
  i := AOpen;
  while i <= n do
  begin
    case S[i] of
      '(', '[': Inc(depth);
      ')', ']':
        begin
          Dec(depth);
          if depth = 0 then
          begin
            AArgs.Add(Trim(Copy(S, from, i - from)));
            Exit(True);
          end;
        end;
      ',':
        if depth = 1 then
        begin
          AArgs.Add(Trim(Copy(S, from, i - from)));
          from := i + 1;
        end;
      ';':
        if depth <= 1 then Exit;
    end;
    Inc(i);
  end;
end;

{ Where the routine that contains APos starts. }
function RoutineStart(const S: string; APos: Integer): Integer;
const
  CHeads: array[0..3] of string = ('procedure ', 'function ', 'constructor ', 'destructor ');
var
  k, p, best: Integer;
begin
  best := 1;
  for k := 0 to High(CHeads) do
  begin
    p := RPosEx(#10 + CHeads[k], S, APos);
    if p > best then best := p;
  end;
  Result := best;
end;

{ What AIdent was given, between AFrom and ATo: the right-hand side of each `AIdent := ...;`
  that is a device value, or ''. }
function DeviceAssignment(const S, AIdent: string; AFrom, ATo: Integer; AFont: Boolean): string;
var
  p, q, e: Integer;
  rhs: string;
begin
  Result := '';
  p := AFrom;
  while True do
  begin
    p := Pos(AIdent, S, p);
    if (p = 0) or (p >= ATo) then Exit;
    q := p + Length(AIdent);
    if ((p = 1) or not (IsIdentChar(S[p - 1]) or (S[p - 1] = '.')))
       and (q <= Length(S)) and not IsIdentChar(S[q]) then
    begin
      while (q <= Length(S)) and (S[q] in [' ', #9, #13, #10]) do Inc(q);
      if Copy(S, q, 2) = ':=' then
      begin
        e := Pos(';', S, q);
        if e = 0 then e := Length(S) + 1;
        rhs := Trim(Copy(S, q + 2, e - q - 2));
        { `for i := a to b do` is not a value. }
        if (Pos(' to ', rhs) = 0) and (Pos(' downto ', rhs) = 0)
           and IsDeviceValue(rhs, AFont) then
          Exit(rhs);
      end;
    end;
    Inc(p);
  end;
end;

{ Every place in ACode where a device value is handed to a parameter that is logical,
  one line each in AOut. ACode: comments and literals already blanked. }
procedure FindScaledArguments(const ACode, AUnit: string; AOut: TStrings);
var
  lc, arg, rhs, head: string;
  args: TStringList;
  k, a, p, q, n, idx, ls, i: Integer;
  simple, font: Boolean;
begin
  lc := LowerCase(ACode);
  n := Length(lc);
  args := TStringList.Create;
  try
    for k := 0 to High(CLogical) do
    begin
      p := 1;
      while p <= n do
      begin
        p := Pos(CLogical[k].Name, lc, p);
        if p = 0 then Break;
        q := p + Length(CLogical[k].Name);
        Inc(p);
        if (p > 2) and IsIdentChar(lc[p - 2]) then Continue;
        while (q <= n) and (lc[q] in [' ', #9, #13, #10]) do Inc(q);
        if (q > n) or (lc[q] <> '(') then Continue;
        { A declaration has the same shape as a call. }
        ls := RPosEx(#10, lc, p - 1);
        head := TrimLeft(Copy(lc, ls + 1, p - 1 - ls - 1));
        if (Copy(head, 1, 9) = 'procedure') or (Copy(head, 1, 8) = 'function') then Continue;
        if not SplitArguments(lc, q, args) then Continue;
        for a := 0 to High(CLogical[k].P) do
        begin
          idx := CLogical[k].P[a];
          if idx < 0 then Continue;
          font := (CLogical[k].Font = idx);
          if idx >= 100 then idx := args.Count - 1 - (idx - 100);
          if (idx < 0) or (idx >= args.Count) then Continue;
          arg := args[idx];
          if arg = '' then Continue;
          if IsDeviceValue(arg, font) then
          begin
            AOut.Add(Format('%s: %s(... %s ...)', [AUnit, CLogical[k].Name, arg]));
            Continue;
          end;
          simple := not (arg[1] in ['0'..'9']);
          for i := 1 to Length(arg) do
            if not IsIdentChar(arg[i]) then simple := False;
          if not simple then Continue;
          rhs := DeviceAssignment(lc, arg, RoutineStart(lc, p), p, font);
          if rhs <> '' then
            AOut.Add(Format('%s: %s(... %s ...)  where  %s := %s', [AUnit, CLogical[k].Name,
              arg, arg, rhs]));
        end;
      end;
    end;
  finally
    args.Free;
  end;
end;

procedure TTyControlDpiTest.TestNothingScaledIsHandedToAParameterThatScales;
{ The painter takes a border width, a corner radius, a glyph's thickness and pad, a font
  size, a line height and a shadow's blur in LOGICAL px and scales them itself; its
  rectangles are device px. So `P.StrokeBorder(R, 0, P.Scale(2), c)` scales the 2 twice,
  and reads perfectly well. Ten places did, the gauge's figure among them: each was right
  at 100% and 1.75x too thick, too round or too tall at 175%.

  A rule about the SOURCE, because nothing else finds a line that is 7 px where it should
  be 4: no picture test looks that closely at every control. }

  function Count(const ASource: string): Integer;
  var
    sl: TStringList;
  begin
    sl := TStringList.Create;
    try
      FindScaledArguments(TyTestCodeOnly(ASource), 'sample', sl);
      Result := sl.Count;
    finally
      sl.Free;
    end;
  end;

var
  files, sl, bad: TStringList;
  i: Integer;
begin
  AssertEquals('a scaled width', 1, Count('begin P.StrokeBorder(R, 0, P.Scale(2), c); end;'));
  AssertEquals('a scaled radius', 1, Count('begin P.FillBackground(R, fill, ScaleI(3)); end;'));
  AssertEquals('a width that was scaled two lines earlier', 1, Count(#10'procedure A;'#10
    + 'begin w := Max(1, P.Scale(1)); P.StrokeBorder(R, 0, w, c); end;'));
  AssertEquals('a font size taken from the size of the thing', 1, Count(#10'procedure A;'#10
    + 'begin fs := (R.Bottom - R.Top) div 6;'
    + ' P.DrawText(R, s, n, fs, 400, c, taCenter, tlCenter, False); end;'));
  AssertEquals('the thickness of a glyph, through the wrapper', 1,
    Count('begin TyDrawGlyph(P, ctl, R, tgCheck, c, P.Scale(2), 1); end;'));
  AssertEquals('...and what is right: a literal, a style field, a rectangle built from'
    + ' scaled numbers, a value taken back to logical, a declaration', 0,
    Count(#10'procedure TTyPainter.StrokeBorder(const ARect: TRect; ARadiusLogical,'
      + ' AWidthLogical: Integer; AColor: TTyColor);'#10
      + 'begin P.StrokeBorder(R, S.BorderRadius, 2, c);'
      + ' P.FillBackground(Rect(a, b, a + P.Scale(8), b + P.Scale(8)), fill, 3);'
      + ' P.StrokeBorder(R, P.Unscale(h) div 2, 1, c);'
      + ' P.DrawText(R, s, n, Max(9, MulDiv(h div 6, 96, P.PPI)), 400, c, a, l, False);'
      + ' P.DrawText(R, s, n, S.FontSize, 400, c, a, l, False);'
      + ' for i := 0 to Scale(3) do P.DrawEdge(R, i, c, c); end;'));

  files := FindAllFiles(TyTestRepoRoot + 'source', '*.pas', False);
  sl := TStringList.Create;
  bad := TStringList.Create;
  try
    AssertTrue('the library''s units were found', files.Count > 100);
    files.Sort;
    for i := 0 to files.Count - 1 do
    begin
      sl.LoadFromFile(files[i]);
      FindScaledArguments(TyTestCodeOnly(sl.Text), ExtractFileName(files[i]), bad);
    end;
    AssertEquals('a value that is already device px is handed to a parameter the callee'
      + ' scales. Pass the LOGICAL number (or P.Unscale the device one):' + LineEnding
      + bad.Text, 0, bad.Count);
  finally
    bad.Free;
    sl.Free;
    files.Free;
  end;
end;

initialization
  RegisterTest(TTyControlDpiTest);

end.
