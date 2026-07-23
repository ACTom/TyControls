unit test.tabset;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.TabStrip, tyControls.TabSet,
  tyControls.PageControl;
type
  TTabSetTest = class(TTestCase)
  private
    FChanged: Boolean;
    procedure OnChangeHandler(Sender: TObject);
    procedure OnChangingVeto(Sender: TObject; ANewIndex: Integer; var AllowChange: Boolean);
  published
    procedure TestTabCountFromTabs;
    procedure TestSelectFiresOnChange;
    procedure TestRemoveClampsIndex;
    procedure TestStyleTypeKey;
    procedure TestRemoveBeforeSelected;
    procedure TestRemoveAfterSelected;
    procedure TestRemoveOnlyTab;
    procedure TestRemoveSelectedNotLast;
    procedure TestRemoveVetoedKeepsIndexInRange;
  end;

  { A caption-only strip must not paint a page container. TTyTabSet hosts no pages,
    so the area under the tabs belongs to the HOST (in the AntD example an ordinary
    panel a few px lower) — framing it drew a small empty box between the two, which
    is what these tests pin down. Rendering, not logic: only pixels can show it. }
  TTabSetBodyTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestStripPaintsNoPageBodyBelowTheTabs;
    procedure TestStripKeepsTheBaselineUnderTheTabs;
    procedure TestPageControlStillFramesItsBody;
  end;
implementation

procedure TTabSetTest.OnChangeHandler(Sender: TObject); begin FChanged := True; end;

procedure TTabSetTest.OnChangingVeto(Sender: TObject; ANewIndex: Integer; var AllowChange: Boolean);
begin
  AllowChange := False;   // always veto the selection change
end;

procedure TTabSetTest.TestTabCountFromTabs;
var t: TTyTabSet;
begin
  t := TTyTabSet.Create(nil);
  try
    t.Tabs.AddStrings(['One','Two','Three']);
    AssertEquals('count', 3, t.TabCountForTest);
    AssertEquals('caption', 'Two', t.TabCaptionForTest(1));
  finally t.Free; end;
end;

procedure TTabSetTest.TestSelectFiresOnChange;
var t: TTyTabSet;
begin
  FChanged := False;
  t := TTyTabSet.Create(nil);
  try
    t.Tabs.AddStrings(['A','B']);
    t.OnChange := @OnChangeHandler;
    t.TabIndex := 1;
    AssertEquals('index', 1, t.TabIndex);
    AssertTrue('OnChange fired', FChanged);
  finally t.Free; end;
end;

procedure TTabSetTest.TestRemoveClampsIndex;
var t: TTyTabSet;
begin
  t := TTyTabSet.Create(nil);
  try
    t.Tabs.AddStrings(['A','B','C']);
    t.TabIndex := 2;
    t.RemoveTabForTest(2);
    AssertEquals('tabs', 2, t.Tabs.Count);
    AssertEquals('clamped', 1, t.TabIndex);
  finally t.Free; end;
end;

procedure TTabSetTest.TestStyleTypeKey;
var t: TTyTabSet;
begin
  t := TTyTabSet.Create(nil);
  try AssertEquals('TyTabSet', t.StyleTypeKeyForTest); finally t.Free; end;
end;

procedure TTabSetTest.TestRemoveBeforeSelected;
var t: TTyTabSet;
begin
  t := TTyTabSet.Create(nil);
  try
    t.Tabs.AddStrings(['A','B','C']);
    t.TabIndex := 2;
    t.OnChange := @OnChangeHandler;
    FChanged := False;
    t.RemoveTabForTest(0);
    AssertEquals('tabs', 2, t.Tabs.Count);
    AssertEquals('decremented', 1, t.TabIndex);
    AssertTrue('OnChange fired', FChanged);
  finally t.Free; end;
end;

procedure TTabSetTest.TestRemoveAfterSelected;
var t: TTyTabSet;
begin
  t := TTyTabSet.Create(nil);
  try
    t.Tabs.AddStrings(['A','B','C']);
    t.TabIndex := 0;
    t.OnChange := @OnChangeHandler;
    FChanged := False;
    t.RemoveTabForTest(2);
    AssertEquals('tabs', 2, t.Tabs.Count);
    AssertEquals('unchanged', 0, t.TabIndex);
    AssertFalse('OnChange did not fire', FChanged);
  finally t.Free; end;
end;

procedure TTabSetTest.TestRemoveOnlyTab;
var t: TTyTabSet;
begin
  t := TTyTabSet.Create(nil);
  try
    t.Tabs.AddStrings(['A']);
    t.TabIndex := 0;
    t.RemoveTabForTest(0);
    AssertEquals('tabs', 0, t.Tabs.Count);
    AssertEquals('none', -1, t.TabIndex);
  finally t.Free; end;
end;

procedure TTabSetTest.TestRemoveSelectedNotLast;
var t: TTyTabSet;
begin
  t := TTyTabSet.Create(nil);
  try
    t.Tabs.AddStrings(['A','B','C']);
    t.TabIndex := 1;
    t.OnChange := @OnChangeHandler;
    FChanged := False;
    t.RemoveTabForTest(1);
    AssertEquals('tabs', 2, t.Tabs.Count);
    AssertEquals('numerically unchanged', 1, t.TabIndex);
    AssertFalse('OnChange did not fire (deliberate no-notify)', FChanged);
  finally t.Free; end;
end;

procedure TTabSetTest.TestRemoveVetoedKeepsIndexInRange;
var t: TTyTabSet;
begin
  t := TTyTabSet.Create(nil);
  try
    t.Tabs.AddStrings(['A','B','C']);
    t.TabIndex := 2;
    t.OnChanging := @OnChangingVeto;   // a veto makes SetTabIndex return early
    t.RemoveTabForTest(2);             // close the selected (last) tab
    AssertEquals('tabs', 2, t.Tabs.Count);
    AssertTrue('TabIndex stays in range after vetoed close', t.TabIndex <= t.Tabs.Count - 1);
  finally t.Free; end;
end;

{ TTabSetBodyTest }

type
  { RenderTo is protected on the header engine — reach it without touching visibility. }
  TSetAccess = class(TTyTabSet)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TPagerAccess = class(TTyPageControl)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

procedure TSetAccess.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TPagerAccess.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

const
  { Loud, unmistakable body colours: the page container is LIME with a RED border, so
    "did a body get painted?" is a colour search, not a fuzzy diff. Square corners keep
    the baseline row a straight line to sample. The border is deliberately 3px, not 1px:
    StrokeBorder is antialiased and a hairline lands as a ~50% blend no tolerance can
    tell from its backdrop — 3px guarantees an opaque core pixel to find. }
  BodyCss =
    'TyTabControl, TyTabSet { background: #00FF00; border: 3px solid #FF0000; border-radius: 0px; }' +
    'TyPageControl { background: #00FF00; border: 3px solid #FF0000; border-radius: 0px; }' +
    'TyTab { background: #DDDDDD; color: #000000; font-size: 12px; padding: 0px 8px; }';
  STRIP_W  = 200;
  STRIP_H  = 60;   { deliberately much taller than the band — that gap is the bug }
  STRIP_TH = 20;
  STRIP_BW = 3;    { must match the border-width above }

{ Loose match: StrokeBorder is antialiased, so a 1px frame edge lands as a BLEND of the
  border colour and what is under it — an exact compare would miss the very box these
  tests are hunting for. The palette is far enough apart (lime / red / white / #DDD)
  that a generous per-channel tolerance still cannot confuse two of them. }
function IsNear(const p, AColor: TBGRAPixel): Boolean;
const TOL = 60;
begin
  Result := (Abs(Integer(p.red)   - Integer(AColor.red))   <= TOL)
        and (Abs(Integer(p.green) - Integer(AColor.green)) <= TOL)
        and (Abs(Integer(p.blue)  - Integer(AColor.blue))  <= TOL);
end;

{ Rows [ATop, ABottom) hold no pixel of AColor. }
function BandIsFreeOf(ABmp: TBGRABitmap; ATop, ABottom: Integer;
  const AColor: TBGRAPixel): Boolean;
var
  x, y: Integer;
begin
  Result := True;
  for y := ATop to ABottom - 1 do
    for x := 0 to ABmp.Width - 1 do
      if IsNear(ABmp.GetPixel(x, y), AColor) then
        Exit(False);
end;

function RowHasColor(ABmp: TBGRABitmap; AY: Integer; const AColor: TBGRAPixel): Boolean;
var
  x: Integer;
begin
  Result := False;
  for x := 0 to ABmp.Width - 1 do
    if IsNear(ABmp.GetPixel(x, AY), AColor) then
      Exit(True);
end;

procedure TTabSetBodyTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(BodyCss);
  FForm := TForm.CreateNew(nil);
end;

procedure TTabSetBodyTest.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

procedure TTabSetBodyTest.TestStripPaintsNoPageBodyBelowTheTabs;
var
  t: TSetAccess;
  bmp: TBitmap;
  img: TBGRABitmap;
begin
  t := TSetAccess.Create(FForm);
  bmp := TBitmap.Create;
  img := nil;
  try
    t.Parent := FForm;
    t.Controller := FCtl;
    t.Font.PixelsPerInch := 96;
    t.Tabs.AddStrings(['One', 'Two', 'Three']);
    t.TabIndex := 0;
    t.TabHeight := STRIP_TH;
    t.SetBounds(0, 0, STRIP_W, STRIP_H);

    bmp.PixelFormat := pf32bit;
    bmp.SetSize(STRIP_W, STRIP_H);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, STRIP_W, STRIP_H);
    t.Render(bmp.Canvas, Rect(0, 0, STRIP_W, STRIP_H), 96);
    img := TBGRABitmap.Create(bmp);

    { The page container's FILL must be nowhere on a strip that hosts no pages. }
    AssertTrue('a caption-only strip painted a page-body fill',
      BandIsFreeOf(img, 0, STRIP_H, BGRA(0, 255, 0)));
    { Nor its box: past the baseline there is no border left, right or bottom. }
    AssertTrue('a caption-only strip painted a page-body frame under the tabs',
      BandIsFreeOf(img, STRIP_TH + STRIP_BW, STRIP_H, BGRA(255, 0, 0)));
  finally
    img.Free;
    bmp.Free;
    t.Free;
  end;
end;

procedure TTabSetBodyTest.TestStripKeepsTheBaselineUnderTheTabs;
var
  t: TSetAccess;
  bmp: TBitmap;
  img: TBGRABitmap;
begin
  t := TSetAccess.Create(FForm);
  bmp := TBitmap.Create;
  img := nil;
  try
    t.Parent := FForm;
    t.Controller := FCtl;
    t.Font.PixelsPerInch := 96;
    t.Tabs.AddStrings(['One', 'Two', 'Three']);
    t.TabIndex := 0;
    t.TabHeight := STRIP_TH;
    t.SetBounds(0, 0, STRIP_W, STRIP_H);

    bmp.PixelFormat := pf32bit;
    bmp.SetSize(STRIP_W, STRIP_H);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, STRIP_W, STRIP_H);
    t.Render(bmp.Canvas, Rect(0, 0, STRIP_W, STRIP_H), 96);
    img := TBGRABitmap.Create(bmp);

    { Dropping the box must not drop the rail the tabs sit on: it stays on exactly the
      row the box's top border used to occupy (TabHeight - 1). }
    AssertTrue('the tab baseline went missing with the body frame',
      RowHasColor(img, STRIP_TH - 1, BGRA(255, 0, 0)));
  finally
    img.Free;
    bmp.Free;
    t.Free;
  end;
end;

procedure TTabSetBodyTest.TestPageControlStillFramesItsBody;
var
  p: TPagerAccess;
  bmp: TBitmap;
  img: TBGRABitmap;
begin
  { Contrast case — proves the two tests above are not vacuously green: a control that
    DOES host pages must keep painting its container. }
  p := TPagerAccess.Create(FForm);
  bmp := TBitmap.Create;
  img := nil;
  try
    p.Parent := FForm;
    p.Controller := FCtl;
    p.Font.PixelsPerInch := 96;
    p.TabHeight := STRIP_TH;
    p.SetBounds(0, 0, STRIP_W, STRIP_H);

    bmp.PixelFormat := pf32bit;
    bmp.SetSize(STRIP_W, STRIP_H);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, STRIP_W, STRIP_H);
    p.Render(bmp.Canvas, Rect(0, 0, STRIP_W, STRIP_H), 96);
    img := TBGRABitmap.Create(bmp);

    AssertFalse('a pager lost its page-container fill',
      BandIsFreeOf(img, STRIP_TH, STRIP_H, BGRA(0, 255, 0)));
    AssertFalse('a pager lost its page-container frame',
      BandIsFreeOf(img, STRIP_TH + STRIP_BW, STRIP_H, BGRA(255, 0, 0)));
  finally
    img.Free;
    bmp.Free;
    p.Free;
  end;
end;

initialization
  RegisterTest(TTabSetTest);
  RegisterTest(TTabSetBodyTest);
end.
