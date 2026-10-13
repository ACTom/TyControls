unit test.trackbar.ticklabels;
{$mode objfpc}{$H+}
{$Q-}{$R-}

{ Tick labels on TTyTrackBar (#36, step 1) and the tick band pulled out into
  TyDrawTrackTicks.

  TickLabels = False must leave the bar exactly as it was. That is pinned against a fixture
  captured from the code BEFORE the tick drawing moved out of RenderTo
  (tests/fixtures/trackbar/ticks-off.txt): per configuration, a hash of the rendered pixels,
  the hit rect of the thumb and the preferred size. A refactor that drops a branch, moves a
  tick by one pixel or reserves a strip it should not shows up as a changed line. Rewrite the
  fixture with TY_WRITE_TRACKBAR_FIXTURE=1 -- only when a change is MEANT to move pixels.

  The configurations with the readout draw text, and text rendering belongs to the machine; those
  lines are compared only where the fixture's environment line matches. The rest are rectangles
  in fixed theme colours and are compared everywhere. }

interface

uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, InterfaceBase, LCLPlatformDef,
  TypInfo, fpcunit, testregistry, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Painter, tyControls.TrackBar;

type
  TTickProbe = class(TTyTrackBar)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure PreferredSize(out AW, AH: Integer);
    { The font the control resolves from its style -- what the labels are drawn in. }
    procedure LabelFont(out AName: string; out ASize, AWeight: Integer);
  end;

  TTyTrackBarTicksOffFixtureTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    { Every configuration of the matrix as `key hash thumb=... pref=...`, readout ones flagged. }
    procedure BuildLines(ALines, AReadout: TStrings);
    procedure Compare(AReadout: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTicksOffMatchTheFixtureWithoutReadout;
    procedure TestTicksOffMatchTheFixtureWithReadout;
  end;

  { TickLabels on. The bar is painted white on white except for the ticks and the labels (black),
    so every dark pixel is one of the two; where a label is expected comes from
    TyLayoutTrackTicks fed the bar's own inputs, and the checks are about where the ink lands. }
  TTyTrackBarTickLabelTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FBar: TTickProbe;
    FBmp: TBitmap;
    FSuffix: string;
    FDropAll: Boolean;
    procedure FormatLabel(Sender: TObject; AValue: Integer; var AText: string);
    procedure MakeBar(AOri: TTyTrackOrientation; AMarks: TTyTrackTickMark; AW, AH, AMax: Integer);
    procedure Render;
    function Ink(X, Y: Integer): Boolean;
    { The layout the bar's own inputs produce (what RenderTo hands TyLayoutTrackTicks). }
    function Layout: TTyTrackTicks;
    { Ink at main-axis offset AMain and depth ADepth from the labelled edge. }
    function InkAt(AMain, ADepth: Integer; ATopLeft: Boolean): Boolean;
    { Every placement check for the side ATopLeft names. }
    procedure CheckPlacement(const T: TTyTrackTicks; ATopLeft: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDefaultsOffAndPublishedOnTheFinalClass;
    procedure TestEveryTickGetsItsLabelOutsideTheTicksHorizontal;
    procedure TestLabelsAboveWhenTicksAreAbove;
    procedure TestVerticalLabelsBesideTheTicks;
    procedure TestBothSidesGetLabels;
    procedure TestFormatterChangesTheText;
    procedure TestEmptyTextDropsTheLabelAndTheStrip;
    procedure TestCrowdedLabelsKeepTheEndsAndDoNotOverlap;
    procedure TestPreferredCrossSizeGrowsByTheStrip;
    procedure TestVerticalStripIsTheWidestLabel;
  end;

function TrackFixtureEnv: string;

implementation

const
  CFixtureCss =
    'TyTrackBar { background: #FFFFFF; color: #000000; border-width: 0px; border-radius: 0px; }' +
    'TyTrackGroove { background: #606060; border-radius: 2px; }' +
    'TyTrackThumb { background: #3B82F6; border-radius: 3px; }';

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + 'trackbar' + PathDelim
    + 'ticks-off.txt';
end;

function TrackFixtureEnv: string;
begin
  Result := {$I %FPCTARGETOS%} + '-' + LCLPlatformDirNames[WidgetSet.LCLPlatform]
    + '-ppi' + IntToStr(Screen.PixelsPerInch);
end;

function PixelHash(ABmp: TBitmap): string;
var
  re: TBGRABitmap;
  x, y: Integer;
  px: TBGRAPixel;
  h: QWord;

  procedure Mix(B: Byte);
  begin
    h := (h xor B) * QWord($100000001B3);
  end;

begin
  re := TBGRABitmap.Create(ABmp);
  try
    h := QWord($CBF29CE484222325);
    for y := 0 to re.Height - 1 do
      for x := 0 to re.Width - 1 do
      begin
        px := re.GetPixel(x, y);
        Mix(px.red);
        Mix(px.green);
        Mix(px.blue);
      end;
  finally
    re.Free;
  end;
  Result := IntToHex(h, 16);
end;

{ TTickProbe }

procedure TTickProbe.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TTickProbe.PreferredSize(out AW, AH: Integer);
begin
  AW := 0;
  AH := 0;
  CalculatePreferredSize(AW, AH, False);
end;

procedure TTickProbe.LabelFont(out AName: string; out ASize, AWeight: Integer);
var
  S: TTyStyleSet;
begin
  S := CurrentStyle;
  AName := S.FontName;
  ASize := ResolveFontSize(S);
  AWeight := S.FontWeight;
end;

{ TTyTrackBarTicksOffFixtureTest }

procedure TTyTrackBarTicksOffFixtureTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(CFixtureCss);
  FForm := TForm.CreateNew(nil);
end;

procedure TTyTrackBarTicksOffFixtureTest.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

procedure TTyTrackBarTicksOffFixtureTest.BuildLines(ALines, AReadout: TStrings);
const
  COri: array[TTyTrackOrientation] of string = ('h', 'v');
  CMarks: array[TTyTrackTickMark] of string = ('br', 'tl', 'both');
  CStyle: array[TTyTrackTickStyle] of string = ('none', 'auto', 'manual');
var
  o: TTyTrackOrientation;
  m: TTyTrackTickMark;
  s: TTyTrackTickStyle;
  sv, rv: Boolean;
  bar: TTickProbe;
  bmp: TBitmap;
  w, h, pw, ph: Integer;
  key: string;
  tr: TRect;
begin
  for o := Low(o) to High(o) do
    for m := Low(m) to High(m) do
      for s := Low(s) to High(s) do
        for sv := False to True do
          for rv := False to True do
          begin
            if o = toVertical then begin w := 40; h := 200; end
            else begin w := 200; h := 40; end;
            bar := TTickProbe.Create(FForm);
            bmp := TBitmap.Create;
            try
              bar.Parent := FForm;
              bar.Controller := FCtl;
              bar.Font.PixelsPerInch := 96;
              bar.Orientation := o;
              bar.SetBounds(0, 0, w, h);
              bar.Min := 0;
              bar.Max := 100;
              bar.Position := 30;
              bar.Frequency := 10;
              bar.SetTick(10);
              bar.SetTick(55);
              bar.SetTick(90);
              bar.TickMarks := m;
              bar.TickStyle := s;
              bar.ShowValue := sv;
              bar.Reversed := rv;
              bmp.PixelFormat := pf32bit;
              bmp.SetSize(w, h);
              { Sentinel ground: anything the bar leaves unpainted stays magenta. }
              bmp.Canvas.Brush.Color := RGBToColor(255, 0, 255);
              bmp.Canvas.FillRect(0, 0, w, h);
              bar.RenderTo(bmp.Canvas, Rect(0, 0, w, h), 96);
              tr := bar.ThumbRect;
              bar.PreferredSize(pw, ph);
              key := Format('%s-%s-%s-val%d-rev%d', [COri[o], CMarks[m], CStyle[s], Ord(sv), Ord(rv)]);
              ALines.Add(Format('%s %s thumb=%d,%d,%d,%d pref=%d,%d',
                [key, PixelHash(bmp), tr.Left, tr.Top, tr.Right, tr.Bottom, pw, ph]));
              if sv then AReadout.Add(key);
            finally
              bmp.Free;
              bar.Free;
            end;
          end;
end;

procedure TTyTrackBarTicksOffFixtureTest.Compare(AReadout: Boolean);
var
  cur, readout, gold: TStringList;
  i, j, compared, diffs: Integer;
  key, env, first: string;
begin
  cur := TStringList.Create;
  readout := TStringList.Create;
  gold := TStringList.Create;
  try
    BuildLines(cur, readout);
    AssertEquals('anti-vacuity: the matrix is 2 x 3 x 3 x 2 x 2', 72, cur.Count);
    if GetEnvironmentVariable('TY_WRITE_TRACKBAR_FIXTURE') = '1' then
    begin
      ForceDirectories(ExtractFilePath(FixturePath));
      cur.Insert(0, '# env ' + TrackFixtureEnv);
      cur.SaveToFile(FixturePath);
      Exit;
    end;
    AssertTrue('fixture missing: ' + FixturePath + ' (written with TY_WRITE_TRACKBAR_FIXTURE=1)',
      FileExists(FixturePath));
    gold.LoadFromFile(FixturePath);
    env := '';
    if (gold.Count > 0) and (Copy(gold[0], 1, 6) = '# env ') then
    begin
      env := Copy(gold[0], 7, MaxInt);
      gold.Delete(0);
    end;
    if AReadout and (env <> TrackFixtureEnv) then
      Ignore('the readout configurations draw text; the fixture was captured on ' + env
        + ', this is ' + TrackFixtureEnv);
    AssertEquals('fixture line count', cur.Count, gold.Count);
    compared := 0;
    diffs := 0;
    first := '';
    for i := 0 to cur.Count - 1 do
    begin
      j := Pos(' ', cur[i]);
      key := Copy(cur[i], 1, j - 1);
      if (readout.IndexOf(key) >= 0) <> AReadout then Continue;
      Inc(compared);
      if cur[i] <> gold[i] then
      begin
        Inc(diffs);
        if first = '' then first := #10'  fixture: ' + gold[i] + #10'  now:     ' + cur[i];
      end;
    end;
    AssertEquals('anti-vacuity: half the matrix is compared', 36, compared);
    AssertEquals(IntToStr(diffs) + ' configuration(s) render differently with TickLabels off;'
      + ' first:' + first, 0, diffs);
  finally
    gold.Free;
    readout.Free;
    cur.Free;
  end;
end;

procedure TTyTrackBarTicksOffFixtureTest.TestTicksOffMatchTheFixtureWithoutReadout;
begin
  Compare(False);
end;

procedure TTyTrackBarTicksOffFixtureTest.TestTicksOffMatchTheFixtureWithReadout;
begin
  Compare(True);
end;

{ TTyTrackBarTickLabelTest }

const
  CLabelCss =
    'TyTrackBar { background: #FFFFFF; color: #000000; border-width: 0px; border-radius: 0px; }' +
    'TyTrackGroove { background: #FFFFFF; border-radius: 0px; }' +
    'TyTrackThumb { background: #FFFFFF; border-radius: 0px; }';
  CTickLen = 4;   // a tick's length at 96 PPI

procedure TTyTrackBarTickLabelTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(CLabelCss);
  FForm := TForm.CreateNew(nil);
  FBmp := TBitmap.Create;
  FBmp.PixelFormat := pf32bit;
  FSuffix := '';
  FDropAll := False;
end;

procedure TTyTrackBarTickLabelTest.TearDown;
begin
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
end;

procedure TTyTrackBarTickLabelTest.FormatLabel(Sender: TObject; AValue: Integer; var AText: string);
begin
  AssertSame('the sender is the bar', FBar, Sender);
  AssertEquals('the text starts as the value', IntToStr(AValue), AText);
  if FDropAll then AText := ''
  else AText := AText + FSuffix;
end;

procedure TTyTrackBarTickLabelTest.MakeBar(AOri: TTyTrackOrientation; AMarks: TTyTrackTickMark;
  AW, AH, AMax: Integer);
begin
  FBar := TTickProbe.Create(FForm);
  FBar.Parent := FForm;
  FBar.Controller := FCtl;
  FBar.Font.PixelsPerInch := 96;
  FBar.Orientation := AOri;
  FBar.SetBounds(0, 0, AW, AH);
  FBar.Min := 0;
  FBar.Max := AMax;
  FBar.Frequency := 1;
  FBar.TickMarks := AMarks;
  FBar.Position := 0;
  FBar.TickLabels := True;
  FBmp.SetSize(AW, AH);
end;

procedure TTyTrackBarTickLabelTest.Render;
begin
  FBmp.Canvas.Brush.Color := clWhite;
  FBmp.Canvas.FillRect(0, 0, FBmp.Width, FBmp.Height);
  FBar.RenderTo(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
end;

function TTyTrackBarTickLabelTest.Ink(X, Y: Integer): Boolean;
var
  c: TColor;
begin
  if (X < 0) or (Y < 0) or (X >= FBmp.Width) or (Y >= FBmp.Height) then Exit(False);
  c := ColorToRGB(FBmp.Canvas.Pixels[X, Y]);
  Result := (Red(c) < 200) or (Green(c) < 200) or (Blue(c) < 200);
end;

function TTyTrackBarTickLabelTest.Layout: TTyTrackTicks;
var
  P: TTyPainter;
  bmp: TBitmap;
begin
  Result := Default(TTyTrackTicks);
  Result.Orientation := FBar.Orientation;
  Result.TickMarks := FBar.TickMarks;
  Result.TickStyle := FBar.TickStyle;
  Result.Frequency := FBar.Frequency;
  Result.Min := FBar.Min;
  Result.Max := FBar.Max;
  Result.Invert := (FBar.Orientation = toVertical) xor FBar.Reversed;
  if FBar.Orientation = toVertical then Result.MainLen := FBar.ClientHeight
  else Result.MainLen := FBar.ClientWidth;
  Result.ThumbLen := 12;
  Result.Labels := True;
  FBar.LabelFont(Result.FontName, Result.FontSize, Result.FontWeight);
  Result.Sender := FBar;
  Result.OnFormatLabel := FBar.OnFormatTickLabel;
  P := TTyPainter.Create;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(8, 8);
    P.BeginPaint(bmp.Canvas, Rect(0, 0, 8, 8), 96);
    TyLayoutTrackTicks(P, Result);
    P.EndPaint;
  finally
    bmp.Free;
    P.Free;
  end;
end;

function TTyTrackBarTickLabelTest.InkAt(AMain, ADepth: Integer; ATopLeft: Boolean): Boolean;
begin
  if FBar.Orientation = toVertical then
  begin
    if ATopLeft then Result := Ink(ADepth, AMain)
    else Result := Ink(FBmp.Width - 1 - ADepth, AMain);
  end
  else
  begin
    if ATopLeft then Result := Ink(AMain, ADepth)
    else Result := Ink(AMain, FBmp.Height - 1 - ADepth);
  end;
end;

procedure TTyTrackBarTickLabelTest.CheckPlacement(const T: TTyTrackTicks; ATopLeft: Boolean);
var
  mainLen, depthLen, m, d, i, along, inkCount, centre: Integer;
  covered: Boolean;
  L: TTyTrackTickLabel;
begin
  if FBar.Orientation = toVertical then
  begin
    mainLen := FBmp.Height;
    depthLen := FBmp.Width;
  end
  else
  begin
    mainLen := FBmp.Width;
    depthLen := FBmp.Height;
  end;
  AssertTrue('the label strip has a thickness', T.LabelBand > 0);
  AssertTrue('some label is shown', Length(T.Shown) > 0);
  { Each kept label has ink in the strip at its place along the track, and its tick sits just
    inside the strip: ink on the tick's centre line at both ends of its length. }
  for i := 0 to High(T.Shown) do
  begin
    L := T.Shown[i];
    if FBar.Orientation = toVertical then along := L.Size.cy else along := L.Size.cx;
    inkCount := 0;
    for m := L.Lead to L.Lead + along - 1 do
      for d := 0 to T.LabelBand - 1 do
        if InkAt(m, d, ATopLeft) then Inc(inkCount);
    AssertTrue(Format('label "%s" has ink in the strip along %d..%d',
      [L.Text, L.Lead, L.Lead + along]), inkCount > 0);
    centre := TyTrackThumbOffset(T.MainLen, T.ThumbLen, T.Min, T.Max, L.Value, T.Invert)
      + T.ThumbLen div 2;
    AssertTrue(Format('the tick of %d starts right inside the label strip', [L.Value]),
      InkAt(centre, T.LabelBand, ATopLeft));
    AssertTrue(Format('the tick of %d runs %d px in from there', [L.Value, CTickLen]),
      InkAt(centre, T.LabelBand + CTickLen - 1, ATopLeft));
  end;
  for m := 0 to mainLen - 1 do
    for d := 0 to depthLen - 1 do
    begin
      if not InkAt(m, d, ATopLeft) then Continue;
      { Nothing between the ticks and the groove: the labels are OUTSIDE the ticks. (With ticks
        on both sides the far side's marks are deep from this edge, so the check is one-sided.) }
      if FBar.TickMarks <> ttmBoth then
        AssertTrue(Format('ink at main %d, depth %d lies inside the ticks', [m, d]),
          d < T.LabelBand + CTickLen);
      { Ink in the strip belongs to a kept label: a skipped one leaves none. }
      if d < T.LabelBand then
      begin
        covered := False;
        for i := 0 to High(T.Shown) do
        begin
          L := T.Shown[i];
          if FBar.Orientation = toVertical then along := L.Size.cy else along := L.Size.cx;
          if (m >= L.Lead - 1) and (m <= L.Lead + along) then covered := True;
        end;
        AssertTrue(Format('ink in the label strip at main %d, depth %d belongs to no kept label',
          [m, d]), covered);
      end;
    end;
end;

procedure TTyTrackBarTickLabelTest.TestDefaultsOffAndPublishedOnTheFinalClass;
var
  bar: TTyTrackBar;
begin
  bar := TTyTrackBar.Create(nil);
  try
    AssertFalse('TickLabels defaults off', bar.TickLabels);
    AssertFalse('no formatter by default', Assigned(bar.OnFormatTickLabel));
  finally
    bar.Free;
  end;
  AssertTrue(IsPublishedProp(TTyTrackBar, 'TickLabels'));
  AssertTrue(IsPublishedProp(TTyTrackBar, 'OnFormatTickLabel'));
  AssertFalse('the custom class publishes neither',
    IsPublishedProp(TTyCustomTrackBar, 'TickLabels')
    or IsPublishedProp(TTyCustomTrackBar, 'OnFormatTickLabel'));
end;

procedure TTyTrackBarTickLabelTest.TestEveryTickGetsItsLabelOutsideTheTicksHorizontal;
var
  T: TTyTrackTicks;
  i: Integer;
begin
  MakeBar(toHorizontal, ttmBottomRight, 300, 60, 4);
  Render;
  T := Layout;
  AssertEquals('room for all five labels', 5, Length(T.Shown));
  for i := 0 to 4 do
    AssertEquals('label value in track order', i, T.Shown[i].Value);
  CheckPlacement(T, False);
end;

procedure TTyTrackBarTickLabelTest.TestLabelsAboveWhenTicksAreAbove;
var
  T: TTyTrackTicks;
begin
  MakeBar(toHorizontal, ttmTopLeft, 300, 60, 4);
  Render;
  T := Layout;
  AssertEquals(5, Length(T.Shown));
  CheckPlacement(T, True);
end;

procedure TTyTrackBarTickLabelTest.TestVerticalLabelsBesideTheTicks;
var
  T: TTyTrackTicks;
begin
  MakeBar(toVertical, ttmBottomRight, 60, 300, 4);
  Render;
  T := Layout;
  AssertEquals(5, Length(T.Shown));
  AssertEquals('vertical: the top label is Max', 4, T.Shown[0].Value);
  CheckPlacement(T, False);
  FBar.Free;
  MakeBar(toVertical, ttmTopLeft, 60, 300, 4);
  Render;
  T := Layout;
  AssertEquals(5, Length(T.Shown));
  CheckPlacement(T, True);
end;

procedure TTyTrackBarTickLabelTest.TestBothSidesGetLabels;
var
  T: TTyTrackTicks;
begin
  MakeBar(toHorizontal, ttmBoth, 300, 80, 4);
  Render;
  T := Layout;
  CheckPlacement(T, False);
  CheckPlacement(T, True);
end;

procedure TTyTrackBarTickLabelTest.TestFormatterChangesTheText;
var
  T: TTyTrackTicks;
  plainInk, fmtInk, plainRight, fmtRight: Integer;

  { Ink in the label strip; ARight = the furthest inked column left of x = 115, which is past
    the label of 1 (centred at 78) and short of the label of 2 (centred at 150). }
  procedure Count(out AInk, ARight: Integer);
  var
    x, y: Integer;
  begin
    AInk := 0;
    ARight := -1;
    for y := FBmp.Height - T.LabelBand to FBmp.Height - 1 do
      for x := 0 to FBmp.Width - 1 do
        if Ink(x, y) then
        begin
          Inc(AInk);
          if (x < 115) and (x > ARight) then ARight := x;
        end;
  end;

begin
  MakeBar(toHorizontal, ttmBottomRight, 300, 60, 4);
  Render;
  T := Layout;
  Count(plainInk, plainRight);
  FSuffix := ' mo';
  FBar.OnFormatTickLabel := @FormatLabel;
  Render;
  T := Layout;
  AssertEquals('the formatter''s text is what is laid out', '2 mo', T.Shown[2].Text);
  Count(fmtInk, fmtRight);
  AssertTrue(Format('"1 mo" inks more than "1" (%d -> %d)', [plainInk, fmtInk]), fmtInk > plainInk);
  AssertTrue(Format('and reaches further along the track (%d -> %d)', [plainRight, fmtRight]),
    fmtRight > plainRight);
  CheckPlacement(T, False);
end;

procedure TTyTrackBarTickLabelTest.TestEmptyTextDropsTheLabelAndTheStrip;
var
  wOff, hOff, w, h, x, y: Integer;
begin
  MakeBar(toHorizontal, ttmBottomRight, 300, 60, 4);
  FBar.TickLabels := False;
  Render;
  FBar.PreferredSize(wOff, hOff);
  FBar.TickLabels := True;
  FDropAll := True;
  FBar.OnFormatTickLabel := @FormatLabel;
  Render;
  FBar.PreferredSize(w, h);
  AssertEquals('every label dropped', 0, Length(Layout.Shown));
  AssertEquals('so no strip is added', hOff, h);
  { The ticks are back against the edge: nothing above their CTickLen rows. }
  for y := 0 to FBmp.Height - CTickLen - 1 do
    for x := 0 to FBmp.Width - 1 do
      AssertFalse(Format('no ink above the ticks (%d,%d)', [x, y]), Ink(x, y));
  AssertTrue('the ticks themselves are drawn', Ink(6, FBmp.Height - 1));
end;

procedure TTyTrackBarTickLabelTest.TestCrowdedLabelsKeepTheEndsAndDoNotOverlap;
var
  T: TTyTrackTicks;
  i, n: Integer;
begin
  MakeBar(toHorizontal, ttmBottomRight, 200, 60, 100);   // 101 ticks on 188 px of travel
  Render;
  T := Layout;
  n := Length(T.Shown);
  AssertTrue(Format('labels were skipped (%d of 101 kept)', [n]), n < 101);
  AssertTrue(Format('some middle ones stay (%d kept)', [n]), n >= 3);
  AssertEquals('the first label stays', 0, T.Shown[0].Value);
  AssertEquals('the last label stays', 100, T.Shown[n - 1].Value);
  for i := 1 to n - 1 do
    AssertTrue(Format('label %s ends before %s begins', [T.Shown[i - 1].Text, T.Shown[i].Text]),
      T.Shown[i - 1].Lead + T.Shown[i - 1].Size.cx < T.Shown[i].Lead);
  CheckPlacement(T, False);
end;

procedure TTyTrackBarTickLabelTest.TestPreferredCrossSizeGrowsByTheStrip;
var
  T: TTyTrackTicks;
  wOff, hOff, wOn, hOn: Integer;
begin
  MakeBar(toHorizontal, ttmBottomRight, 300, 60, 4);
  FBar.TickLabels := False;
  Render;
  FBar.PreferredSize(wOff, hOff);
  FBar.TickLabels := True;
  Render;
  FBar.PreferredSize(wOn, hOn);
  T := Layout;
  AssertTrue('the strip has a thickness', T.LabelBand > 0);
  AssertEquals('the cross size grows by exactly the strip', hOff + T.LabelBand, hOn);
  AssertEquals('the length stays the form''s call', 0, wOn);
  FBar.TickMarks := ttmBoth;
  Render;
  FBar.PreferredSize(wOn, hOn);
  AssertEquals('one strip per tick side', hOff + 2 * T.LabelBand, hOn);
end;

procedure TTyTrackBarTickLabelTest.TestVerticalStripIsTheWidestLabel;
var
  T: TTyTrackTicks;
  i, widest, wOff, hOff, wOn, hOn: Integer;
begin
  MakeBar(toVertical, ttmBottomRight, 60, 300, 1000);
  FBar.Frequency := 250;
  FBar.TickLabels := False;
  Render;
  FBar.PreferredSize(wOff, hOff);
  FBar.TickLabels := True;
  Render;
  FBar.PreferredSize(wOn, hOn);
  T := Layout;
  AssertEquals('"1000" is the top label', '1000', T.Shown[0].Text);
  widest := 0;
  for i := 0 to High(T.Shown) do
    if T.Shown[i].Size.cx > widest then widest := T.Shown[i].Size.cx;
  AssertEquals('"1000" is the widest', T.Shown[0].Size.cx, widest);
  AssertTrue('the strip is wider than the widest label', T.LabelBand > widest);
  AssertEquals('vertical: the cross size grows by the strip', wOff + T.LabelBand, wOn);
  CheckPlacement(T, False);
end;

initialization
  RegisterTest(TTyTrackBarTicksOffFixtureTest);
  RegisterTest(TTyTrackBarTickLabelTest);
end.
