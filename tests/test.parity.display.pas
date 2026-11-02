unit test.parity.display;
{$mode objfpc}{$H+}
{ #181: what the display controls show -- gauges, meters, the sparkline, the chart's legend,
  labels, images, badges and ratings -- agrees with what they were told. }
interface
uses
  Classes, SysUtils, Types, Graphics, Controls, Forms, LMessages, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Gauge, tyControls.Meter, tyControls.LevelMeter,
  tyControls.Sparkline, tyControls.Chart, tyControls.TyLabel, tyControls.HtmlLabel,
  tyControls.GlowLabel, tyControls.ShadowLabel, tyControls.Image, tyControls.ImageCollection,
  tyControls.ImageView, tyControls.Badge, tyControls.LinkLabel, tyControls.Rating;

type
  TDisplay181Test = class(TTestCase)
  private
    FForm: TForm;
    FChanges: Integer;
    procedure Changed(Sender: TObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheGaugesKeepValueInRange;
    procedure TestALevelMeterFitsItsSegments;
    procedure TestTheLastDotSitsOnTheLastBar;
    procedure TestAPieLegendListsTheSlices;
    procedure TestAnOpaqueLabelCoversWhatIsUnder;
    procedure TestCJKTextWraps;
    procedure TestTheGlowHasRoomOnTheLeft;
    procedure TestANegativeShadowHasRoomOnTheLeft;
    procedure TestListIconsScaleWithTheDPI;
    procedure TestTheImageViewKeepsPictureCurrent;
    procedure TestTheImageViewTellsEveryZoom;
    procedure TestABadgeHidesWithItsTarget;
    procedure TestAnEmptyBadgeTakesNoClicks;
    procedure TestTheUnderlineFollowsTheLayout;
    procedure TestARatingSnapsAndTells;
  end;

implementation

uses
  test.dpi.support;

type
  TChart181 = class(TTyChart);
  TLabel181 = class(TTyLabel);
  THtml181 = class(TTyHtmlLabel);
  TGlow181 = class(TTyGlowLabel);
  TShadow181 = class(TTyShadowLabel);
  TImage181 = class(TTyImage);
  TView181 = class(TTyImageView);
  TLink181 = class(TTyLinkLabel);

const
  CSentinel: TColor = $00FF00FF;   // magenta: nothing in a theme paints it

function NewGround(W, H: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf32bit;
  Result.SetSize(W, H);
  Result.Canvas.Brush.Color := CSentinel;
  Result.Canvas.FillRect(0, 0, W, H);
end;

{ Pixels in R that are not the sentinel ground. }
function InkIn(B: TBitmap; const R: TRect): Integer;
var
  x, y: Integer;
begin
  Result := 0;
  for y := R.Top to R.Bottom - 1 do
    for x := R.Left to R.Right - 1 do
      if B.Canvas.Pixels[x, y] <> CSentinel then Inc(Result);
end;

{ The leftmost column with any ink, or -1. }
function LeftmostInk(B: TBitmap): Integer;
var
  x, y: Integer;
begin
  for x := 0 to B.Width - 1 do
    for y := 0 to B.Height - 1 do
      if B.Canvas.Pixels[x, y] <> CSentinel then Exit(x);
  Result := -1;
end;

procedure TDisplay181Test.Changed(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TDisplay181Test.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 300);
  FChanges := 0;
end;

procedure TDisplay181Test.TearDown;
begin
  FreeAndNil(FForm);
end;

procedure TDisplay181Test.TestTheGaugesKeepValueInRange;
var g: TTyGauge; m: TTyMeter; lm: TTyLevelMeter;
begin
  g := TTyGauge.Create(FForm);
  g.Max := 100; g.Value := 80; g.Max := 50;
  AssertEquals('a gauge''s lower Max brings Value down', 50, g.Value, 0.0001);
  g.Value := 10; g.Min := 20;
  AssertEquals('a higher Min brings it up', 20, g.Value, 0.0001);
  m := TTyMeter.Create(FForm);
  m.Max := 100; m.Value := 80; m.Max := 50;
  AssertEquals('a meter''s too', 50, m.Value, 0.0001);
  m.Value := 10; m.Min := 20;
  AssertEquals('both ways', 20, m.Value, 0.0001);
  lm := TTyLevelMeter.Create(FForm);
  lm.Max := 100; lm.Value := 80; lm.Max := 50;
  AssertEquals('a level meter''s too', 50, lm.Value, 0.0001);
  lm.Value := 10; lm.Min := 20;
  AssertEquals('both ways', 20, lm.Value, 0.0001);
end;

procedure TDisplay181Test.TestALevelMeterFitsItsSegments;
var lm: TTyLevelMeter; off, half: TBitmap; x, y, lit: Integer;
begin
  lm := TTyLevelMeter.Create(FForm);
  lm.Parent := FForm;
  lm.SetBounds(0, 0, 64, 16);
  lm.Segments := 100;
  lm.Value := 0;
  off := NewGround(64, 16);
  half := NewGround(64, 16);
  try
    TyTestPaintTree(lm, off, nil);
    lm.Value := 50;
    TyTestPaintTree(lm, half, nil);
    lit := 0;
    for x := 0 to 20 do
      for y := 0 to 15 do
        if off.Canvas.Pixels[x, y] <> half.Canvas.Pixels[x, y] then Inc(lit);
    AssertTrue('setup: the first part of the track is lit at half', lit > 0);
    lit := 0;
    for x := 44 to 63 do
      for y := 0 to 15 do
        if off.Canvas.Pixels[x, y] <> half.Canvas.Pixels[x, y] then Inc(lit);
    AssertEquals('at half the last part is not: the segments fit the track', 0, lit);
  finally
    off.Free;
    half.Free;
  end;
end;

procedure TDisplay181Test.TestTheLastDotSitsOnTheLastBar;
var sp: TTySparkline; a, b: TBitmap; x, y, n: Integer; sum: Double;
begin
  sp := TTySparkline.Create(FForm);
  sp.Parent := FForm;
  sp.SetBounds(0, 0, 100, 40);
  sp.Style := ssBar;
  sp.SetValues([1, 2, 3, 2]);
  sp.ShowLast := False;
  a := NewGround(100, 40);
  b := NewGround(100, 40);
  try
    TyTestPaintTree(sp, a, nil);
    sp.ShowLast := True;
    TyTestPaintTree(sp, b, nil);
    n := 0; sum := 0;
    for x := 0 to 99 do
      for y := 0 to 39 do
        if a.Canvas.Pixels[x, y] <> b.Canvas.Pixels[x, y] then
        begin
          Inc(n);
          sum := sum + x;
        end;
    AssertTrue('setup: the dot draws', n > 0);
    { The band is 4..96 at 96 PPI, four slots of 23 px: the last bar spans 74..95. }
    AssertEquals('the dot is on the middle of the last bar', 84.5, sum / n, 2.5);
  finally
    a.Free;
    b.Free;
  end;
end;

procedure TDisplay181Test.TestAPieLegendListsTheSlices;
var c: TChart181; l: TStringList;
begin
  c := TChart181.Create(FForm);
  c.ChartType := ctPie;
  c.Categories.Add('North');
  c.Categories.Add('South');
  c.Series.Add.Values := '3,0,5,7';
  l := TStringList.Create;
  try
    c.LegendEntries(True, l);
    AssertEquals('one entry for each slice drawn (the 0 is not)', 3, l.Count);
    AssertEquals('named by its category', 'North', l[0]);
    AssertEquals('or its number past the categories', '3', l[1]);
    AssertEquals('', '4', l[2]);
    AssertTrue('each slice keeps its own colour', l.Objects[1] <> l.Objects[2]);
    c.ChartType := ctBar;
    c.Series.Items[0].Name := 'Sales';
    c.LegendEntries(False, l);
    AssertEquals('an axes chart lists the series', 1, l.Count);
    AssertEquals('', 'Sales', l[0]);
  finally
    l.Free;
  end;
end;

procedure TDisplay181Test.TestAnOpaqueLabelCoversWhatIsUnder;
var lb: TLabel181; b: TBitmap;
begin
  lb := TLabel181.Create(FForm);
  lb.Parent := FForm;
  lb.SetBounds(0, 0, 80, 24);
  lb.Caption := '';
  b := NewGround(80, 24);
  try
    lb.RenderTo(b.Canvas, Rect(0, 0, 80, 24), 96);
    AssertEquals('setup: a transparent label leaves the ground', 0, InkIn(b, Rect(0, 0, 80, 24)));
    lb.Transparent := False;
    lb.RenderTo(b.Canvas, Rect(0, 0, 80, 24), 96);
    AssertEquals('an opaque one covers all of it', 80 * 24, InkIn(b, Rect(0, 0, 80, 24)));
  finally
    b.Free;
  end;
end;

procedure TDisplay181Test.TestCJKTextWraps;
var h: THtml181; w1, h1, w2, h2: Integer;
begin
  h := THtml181.Create(FForm);
  h.Parent := FForm;
  h.WordWrap := True;
  h.SetBounds(0, 0, 80, 20);
  h.Html := '中';
  w1 := 0; h1 := 0;
  h.CalculatePreferredSize(w1, h1, False);
  h.Html := '中文的句子没有空格也要折行才能放得下';
  w2 := 0; h2 := 0;
  h.CalculatePreferredSize(w2, h2, False);
  AssertTrue(Format('a CJK run wraps at the glyphs (%d against one line''s %d)', [h2, h1]),
    h2 >= 2 * h1);
end;

procedure TDisplay181Test.TestTheGlowHasRoomOnTheLeft;
var g: TGlow181; w, h, glowRun: Integer; b: TBitmap;
begin
  g := TGlow181.Create(FForm);
  g.Parent := FForm;
  g.Caption := 'Glow';
  g.GlowRadius := 8;
  g.GlowColor := TyRGBA(0, 0, 0, 0);   // only the crisp text, to find where it starts
  w := 0; h := 0;
  g.CalculatePreferredSize(w, h, False);
  g.SetBounds(0, 0, w, 30);
  glowRun := 8;
  b := NewGround(w, 30);
  try
    g.RenderTo(b.Canvas, Rect(0, 0, w, 30), 96);
    AssertTrue(Format('the text starts a radius in, where the halo has room (%d)', [LeftmostInk(b)]),
      LeftmostInk(b) >= glowRun - 1);
  finally
    b.Free;
  end;
end;

procedure TDisplay181Test.TestANegativeShadowHasRoomOnTheLeft;
var s: TShadow181; w, h: Integer; b: TBitmap;
begin
  s := TShadow181.Create(FForm);
  s.Parent := FForm;
  s.Caption := 'Shade';
  s.ShadowOffsetX := -5;
  s.ShadowColor := TyRGBA(0, 0, 0, 0);   // only the crisp text
  w := 0; h := 0;
  s.CalculatePreferredSize(w, h, False);
  s.SetBounds(0, 0, w, 30);
  b := NewGround(w, 30);
  try
    s.RenderTo(b.Canvas, Rect(0, 0, w, 30), 96);
    AssertTrue(Format('the text keeps the shadow''s run clear on the left (%d)', [LeftmostInk(b)]),
      LeftmostInk(b) >= 4);
  finally
    b.Free;
  end;
end;

procedure TDisplay181Test.TestListIconsScaleWithTheDPI;
var im: TImage181; col: TTyImageCollection; vl: TTyVirtualImageList; red: TBGRABitmap;
  b: TBitmap; x, n, w, h: Integer;
begin
  col := TTyImageCollection.Create(nil);
  vl := TTyVirtualImageList.Create(nil);
  red := TBGRABitmap.Create(16, 16, BGRA(255, 0, 0, 255));
  im := TImage181.Create(nil);
  try
    col.AddBitmap('red', red);
    vl.Collection := col;
    vl.Names.Text := 'red';
    vl.DefaultSize := 16;
    im.Images := vl;
    im.ImageIndex := 0;
    AssertEquals('setup: 16 at 96 PPI', 16, im.ImageSize);
    im.Font.PixelsPerInch := 144;
    AssertEquals('the edge scales with the DPI', 24, im.ImageSize);
    w := 0; h := 0;
    im.CalculatePreferredSize(w, h, False);
    AssertEquals('and AutoSize asks for it', 24, w);
    im.SetBounds(0, 0, 48, 48);
    b := NewGround(48, 48);
    try
      im.RenderTo(b.Canvas, Rect(0, 0, 48, 48), 144);
      n := 0;
      for x := 0 to 47 do
        if b.Canvas.Pixels[x, 4] and $FFFFFF = clRed then Inc(n);
      AssertTrue(Format('it draws that big (%d)', [n]), (n >= 22) and (n <= 24));
    finally
      b.Free;
    end;
  finally
    im.Free;
    red.Free;
    vl.Free;
    col.Free;
  end;
end;

procedure TDisplay181Test.TestTheImageViewKeepsPictureCurrent;
var v: TTyImageView; bmp: TBGRABitmap; fn: string;
begin
  v := TTyImageView.Create(FForm);
  bmp := TBGRABitmap.Create(4, 3, BGRA(255, 0, 0, 255));
  try
    v.AssignBitmap(bmp);
    AssertEquals('AssignBitmap: Picture holds it', 4, v.Picture.Width);
    AssertEquals('', 3, v.Picture.Height);
    AssertEquals('its pixels too', clRed, v.Picture.Bitmap.Canvas.Pixels[1, 1]);
    v.Clear;
    AssertTrue('Clear: Picture is empty', (v.Picture.Graphic = nil) or v.Picture.Graphic.Empty);
    fn := GetTempDir + 'ty181view.png';
    bmp.SetSize(7, 5);
    bmp.Fill(BGRA(0, 0, 255, 255));
    bmp.SaveToFile(fn);
    try
      v.LoadFromFile(fn);
      AssertEquals('LoadFromFile: Picture holds it', 7, v.Picture.Width);
      AssertEquals('', 5, v.Picture.Height);
    finally
      DeleteFile(fn);
    end;
  finally
    bmp.Free;
  end;
end;

procedure TDisplay181Test.TestTheImageViewTellsEveryZoom;
var v: TView181; bmp: TBGRABitmap;
begin
  v := TView181.Create(FForm);
  v.Parent := FForm;
  v.SetBounds(0, 0, 200, 200);
  v.OnZoomChange := @Changed;
  bmp := TBGRABitmap.Create(400, 400, BGRA(0, 128, 0, 255));
  try
    v.AssignBitmap(bmp);
  finally
    bmp.Free;
  end;
  FChanges := 0;
  v.SetBounds(0, 0, 100, 100);
  v.Resize;
  AssertTrue('an AutoFit resize moves the zoom, and says so', FChanges > 0);
  FChanges := 0;
  v.Resize;
  AssertEquals('a layout pass that moves nothing is quiet', 0, FChanges);
  v.Clear;
  AssertEquals('Clear goes back to 100 %, and says so', 1, FChanges);
end;

procedure TDisplay181Test.TestABadgeHidesWithItsTarget;
var bd: TTyBadge; lb: TTyLabel;
begin
  lb := TTyLabel.Create(FForm);
  lb.Parent := FForm;
  lb.SetBounds(10, 10, 60, 20);
  bd := TTyBadge.Create(FForm);
  bd.Value := 3;
  bd.Target := lb;
  AssertTrue('setup: it shows on its target', bd.IsShowing);
  lb.Visible := False;
  AssertFalse('a hidden windowless target takes its badge with it', bd.IsShowing);
  lb.Visible := True;
  AssertTrue('and brings it back', bd.IsShowing);
end;

procedure TDisplay181Test.TestAnEmptyBadgeTakesNoClicks;
var bd: TTyBadge;
begin
  bd := TTyBadge.Create(FForm);
  bd.Parent := FForm;
  bd.SetBounds(10, 10, 20, 20);
  bd.Value := 3;
  AssertTrue('setup: a standalone badge with a count is clickable', bd.Perform(CM_HITTEST, 0, 0) <> 0);
  bd.Value := 0;
  AssertEquals('one with nothing to show is not', 0, bd.Perform(CM_HITTEST, 0, 0));
  bd.ShowZero := True;
  AssertTrue('unless it shows its 0', bd.Perform(CM_HITTEST, 0, 0) <> 0);
end;

procedure TDisplay181Test.TestTheUnderlineFollowsTheLayout;
var lk: TLink181; b: TBitmap;
begin
  lk := TLink181.Create(FForm);
  lk.Parent := FForm;
  lk.Caption := 'Open the site';
  lk.SetBounds(0, 0, 140, 60);
  lk.Layout := tlTop;
  b := NewGround(140, 60);
  try
    lk.RenderTo(b.Canvas, Rect(0, 0, 140, 60), 96);
    AssertTrue('setup: the text is at the top', InkIn(b, Rect(0, 0, 140, 25)) > 0);
    AssertEquals('and so is its underline -- nothing near the bottom', 0, InkIn(b, Rect(0, 35, 140, 60)));
  finally
    b.Free;
  end;
  lk.Layout := tlBottom;
  b := NewGround(140, 60);
  try
    lk.RenderTo(b.Canvas, Rect(0, 0, 140, 60), 96);
    AssertEquals('at the bottom, nothing near the top', 0, InkIn(b, Rect(0, 0, 140, 25)));
  finally
    b.Free;
  end;
end;

procedure TDisplay181Test.TestARatingSnapsAndTells;
var r: TTyRating;
begin
  r := TTyRating.Create(FForm);
  r.Count := 5;
  r.Value := 3.7;
  AssertEquals('whole stars: 3.7 is 4', 4, r.Value, 0.0001);
  r.AllowHalf := True;
  r.Value := 3.7;
  AssertEquals('halves: 3.7 is 3.5', 3.5, r.Value, 0.0001);
  r.OnChange := @Changed;
  r.Count := 2;
  AssertEquals('fewer stars cut Value down', 2, r.Value, 0.0001);
  AssertEquals('and say so', 1, FChanges);
  r.Value := 1.5;
  FChanges := 0;
  r.AllowHalf := False;
  AssertEquals('no halves any more: 1.5 is 2', 2, r.Value, 0.0001);
  AssertEquals('told', 1, FChanges);
end;

initialization
  RegisterTest(TDisplay181Test);
end.
