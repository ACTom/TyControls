unit test.tabset;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, LCLProc, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.TabStrip, tyControls.TabSet,
  tyControls.PageControl, ComCtrls;
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
    procedure TestDesignTimeSwitchTellsTheDesigner;
    procedure TestTabIndexSurvivesStreaming;
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

type
  { SetDesigning is protected on TComponent. }
  TTabSetDesign = class(TTyTabSet)
  public
    procedure MarkDesigning;
  end;

procedure TTabSetDesign.MarkDesigning;
begin
  SetDesigning(True);
end;

var
  DesignerPings: Integer;
  RefreshPings: Integer;

procedure CountDesignerModified(AComponent: TComponent);
begin
  Inc(DesignerPings);
end;

procedure CountRefresh;
begin
  Inc(RefreshPings);
end;

type
  THostForm = class(TForm)
  published
    TS: TTyTabSet;
  end;

procedure TTabSetTest.TestTabIndexSurvivesStreaming;
var
  Src, Dst: THostForm;
  MS: TMemoryStream;
  DstTS: TTyTabSet;
begin
  { SetTabIndex captures a csLoading write into FPendingTabIndex "to apply later" --
    and only TTyPageControl's Loaded ever applied it. A designed TTyTabSet.TabIndex
    therefore vanished on load (real-machine report: the OI says 2, the built
    application selects nothing). The apply now lives in the BASE Loaded. }
  Src := THostForm.CreateNew(nil);
  Dst := THostForm.CreateNew(nil);
  MS := TMemoryStream.Create;
  try
    Src.Name := 'HostForm3';
    Src.TS := TTyTabSet.Create(Src);
    Src.TS.Name := 'TS';
    Src.TS.Parent := Src;
    Src.TS.Tabs.AddStrings(['A', 'B', 'C']);
    Src.TS.TabIndex := 2;
    MS.WriteComponent(Src);

    MS.Position := 0;
    MS.ReadComponent(Dst);
    DstTS := Dst.FindComponent('TS') as TTyTabSet;
    AssertEquals('the tabs streamed', 3, DstTS.Tabs.Count);
    AssertEquals('the designed selection survived the load', 2, DstTS.TabIndex);
  finally
    MS.Free;
    Dst.Free;
    Src.Free;
  end;
end;

procedure TTabSetTest.TestDesignTimeSwitchTellsTheDesigner;
var
  t: TTabSetDesign;
  r: TTyTabSet;
  saved: TOwnerFormDesignerModifiedProc;
begin
  { A design-time tab switch (a designer tab click, a component-editor verb) changes
    ActivePageIndex/TabIndex behind the IDE's back. TWO pings, because the IDE splits
    the concerns: OwnerFormDesignerModified only marks the unit dirty
    (TMainIDE.DesignerModified never touches the OI), while the Object Inspector
    re-reads values ONLY on GlobalDesignHook.RefreshPropertyValues -- which the
    designtime package bridges into TyDesignerRefreshValuesProc (real-machine
    feedback, second round: the value still showed stale with the dirty ping alone). }
  saved := OwnerFormDesignerModifiedProc;
  OwnerFormDesignerModifiedProc := @CountDesignerModified;
  TyDesignerRefreshValuesProc := @CountRefresh;
  DesignerPings := 0;
  RefreshPings := 0;
  t := TTabSetDesign.Create(nil);
  try
    t.Tabs.AddStrings(['A', 'B']);
    t.MarkDesigning;
    t.TabIndex := 1;
    AssertEquals('the designer heard the switch', 1, DesignerPings);
    AssertEquals('and the OI was told to re-read', 1, RefreshPings);
    t.TabIndex := 1;
    AssertEquals('a same-value write stays silent', 1, DesignerPings);
    AssertEquals('for the OI too', 1, RefreshPings);

    r := TTyTabSet.Create(nil);   // no csDesigning: a RUNTIME switch never pings
    try
      r.Tabs.AddStrings(['A', 'B']);
      r.TabIndex := 1;
      AssertEquals('runtime switches stay silent', 1, DesignerPings);
      AssertEquals('for the OI too', 1, RefreshPings);
    finally
      r.Free;
    end;
  finally
    OwnerFormDesignerModifiedProc := saved;
    TyDesignerRefreshValuesProc := nil;
    t.Free;
  end;
end;

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
    { #173: the index is the same, the tab is another -- a change of the selection. }
    AssertTrue('OnChange fired', FChanged);
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


type
  { #173: the tab set keeps its selection on its tab across Tabs edits, a drag and a close, and
    tells when the selected tab goes; AutoSize follows TabPosition and MultiLine. }
  TTabSet173Test = class(TTestCase)
  private
    FT: TTyTabSet;
    FChanges: Integer;
    procedure Changed(Sender: TObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheSelectionStaysOnItsTabAcrossAnEdit;
    procedure TestTheSelectedTabDeletedIsTold;
    procedure TestTheSelectedTabClosedIsTold;
    procedure TestADragKeepsTheSelectedTab;
    procedure TestAutoSizeFollowsASideBand;
    procedure TestAutoSizeFollowsFoldedRows;
    procedure TestTheAskedSizeIsAskedAgainWhenTheBandChanges;
  end;

  TTabSet173Access = class(TTyTabSet);

procedure TTabSet173Test.Changed(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TTabSet173Test.SetUp;
begin
  FT := TTyTabSet.Create(nil);
  FT.Tabs.AddStrings(['A', 'B', 'C']);
  FChanges := 0;
end;

procedure TTabSet173Test.TearDown;
begin
  FreeAndNil(FT);
end;

procedure TTabSet173Test.TestTheSelectionStaysOnItsTabAcrossAnEdit;
begin
  FT.TabIndex := 2;
  FT.OnChange := @Changed;
  FT.Tabs[2] := 'C2';
  AssertEquals('a rename keeps it', 2, FT.TabIndex);
  AssertEquals('silently', 0, FChanges);
  FT.Tabs.Delete(0);
  AssertEquals('a delete before it: the selection stays on C2', 1, FT.TabIndex);
  AssertEquals('setup: that tab', 'C2', FT.Tabs[FT.TabIndex]);
  AssertEquals('TabIndex moved, which is told', 1, FChanges);
  FT.Tabs.Insert(0, 'Z');
  AssertEquals('an insert before it', 'C2', FT.Tabs[FT.TabIndex]);
end;

procedure TTabSet173Test.TestTheSelectedTabDeletedIsTold;
begin
  FT.TabIndex := 1;
  FT.OnChange := @Changed;
  FT.Tabs.Delete(1);
  AssertEquals('the one now at its place is selected', 1, FT.TabIndex);
  AssertEquals('which is C', 'C', FT.Tabs[FT.TabIndex]);
  AssertEquals('and that is told', 1, FChanges);
  FT.Tabs.Delete(1);
  AssertEquals('the last gone: the one before', 0, FT.TabIndex);
  AssertEquals('told again', 2, FChanges);
  FT.Tabs.Clear;
  AssertEquals('none left', -1, FT.TabIndex);
  AssertEquals('told', 3, FChanges);
end;

procedure TTabSet173Test.TestTheSelectedTabClosedIsTold;
begin
  FT.TabIndex := 1;
  FT.OnChange := @Changed;
  FT.RemoveTabForTest(1);
  AssertEquals('the next one takes the index', 1, FT.TabIndex);
  AssertEquals('another tab selected is told', 1, FChanges);
end;

procedure TTabSet173Test.TestADragKeepsTheSelectedTab;
begin
  FT.TabIndex := 0;
  FT.OnChange := @Changed;
  TTabSet173Access(FT).DoReorderTabs(0, 2);
  AssertEquals('the dragged selected tab stays selected', 2, FT.TabIndex);
  AssertEquals('it is A', 'A', FT.Tabs[FT.TabIndex]);
  TTabSet173Access(FT).DoReorderTabs(0, 2);
  AssertEquals('another tab dragged past it: A moves over', 1, FT.TabIndex);
  AssertEquals('still A', 'A', FT.Tabs[FT.TabIndex]);
  AssertEquals('the same tab, nothing to tell', 0, FChanges);
  FT.Tabs[0] := FT.Tabs[0] + '2';
  AssertEquals('an edit after the drag still finds A', 'A', FT.Tabs[FT.TabIndex]);
  AssertEquals('silently', 0, FChanges);
end;

procedure TTabSet173Test.TestAutoSizeFollowsASideBand;
var w, h: Integer;
begin
  FT.Tabs.Add('A much longer caption');
  FT.TabPosition := tpLeft;
  w := 0; h := 0;
  TTabSet173Access(FT).CalculatePreferredSize(w, h, True);
  AssertTrue(Format('a side band asks for its width (%d)', [w]), w > 0);
  AssertEquals('the band is the widest tab', FT.BandThicknessPx, w);
  AssertEquals('and leaves the height alone', 0, h);
end;

procedure TTabSet173Test.TestTheAskedSizeIsAskedAgainWhenTheBandChanges;
var w, h, one: Integer;
begin
  FT.Width := 120;
  FT.Tabs.AddStrings(['Delta', 'Echo', 'Foxtrot', 'Golf', 'Hotel']);
  w := 0; one := 0;
  FT.GetPreferredSize(w, one);      // asked once: LCL keeps the answer
  FT.MultiLine := True;
  w := 0; h := 0;
  FT.GetPreferredSize(w, h);
  AssertTrue(Format('a parent asking again gets the folded height (%d > %d)', [h, one]), h > one);
end;

procedure TTabSet173Test.TestAutoSizeFollowsFoldedRows;
var w, h, one: Integer;
begin
  FT.Width := 120;
  w := 0; one := 0;
  TTabSet173Access(FT).CalculatePreferredSize(w, one, True);
  FT.Tabs.AddStrings(['Delta', 'Echo', 'Foxtrot', 'Golf', 'Hotel']);
  FT.MultiLine := True;
  AssertTrue('setup: folded', FT.RowCount > 1);
  w := 0; h := 0;
  TTabSet173Access(FT).CalculatePreferredSize(w, h, True);
  AssertTrue(Format('folded rows ask for all of them (%d > %d)', [h, one]), h > one);
end;

initialization
  RegisterClasses([TTyTabSet]);   // the streaming reader instantiates by class name
  RegisterTest(TTabSet173Test);
  RegisterTest(TTabSetTest);
  RegisterTest(TTabSetBodyTest);
end.
