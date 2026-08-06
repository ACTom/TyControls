unit test.parity.splitter;
{ LCL parity for TTySplitter.ResizeStyle.

  The control publishes the whole TResizeStyle set but for a long time only rsUpdate
  did anything: rsLine applied on release with no feedback, and rsPattern/rsNone were
  dead -- you could drag forever and nothing ever moved. These tests pin the three
  deferred styles: no resize while the button is held, the clamped resize on release,
  and the feedback band that rsLine/rsPattern show meanwhile (and rsNone must not). }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, TypInfo, Controls, Graphics, Forms, ExtCtrls, LCLType,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller,
  tyControls.Splitter;
type
  { Drives the protected mouse handlers, and re-exposes the protected drag band. }
  TSplitterDriver = class(TTySplitter)
  public
    procedure Press(X, Y: Integer);
    procedure DragTo(X, Y: Integer);
    procedure Release(X, Y: Integer);
    procedure LoseButton(X, Y: Integer);   // a move with the button already up
    property DragBand;                     // promoted from protected for the guards
  end;

  { OnCanResize handler object: rejects every proposed size. }
  TSplitterVeto = class
  public
    procedure Reject(Sender: TObject; var ANewSize: Integer; var AAccept: Boolean);
  end;

  TSplitterDeferredTest = class(TTestCase)
  private
    FForm: TForm;
    FPane: TPanel;
    FSplit: TSplitterDriver;
    procedure Build(AStyle: TResizeStyle);
  protected
    procedure TearDown; override;
  published
    procedure TestLineDefersUntilRelease;
    procedure TestPatternDefersUntilRelease;
    procedure TestNoneDefersUntilRelease;
    procedure TestDeferredHonoursMinSize;
    procedure TestDeferredHonoursCanResizeVeto;
    procedure TestAbandonedDragNeverResizes;
  end;

  { The bar geometry of TySplitterBarOffset, and the feedback band that rides on it. }
  TSplitterBandTest = class(TTestCase)
  private
    FForm: TForm;
    FPane: TPanel;
    FSplit: TSplitterDriver;
    procedure BuildLeft(AStyle: TResizeStyle);
    procedure BuildRight(AStyle: TResizeStyle);
    procedure BuildTop(AStyle: TResizeStyle);
  protected
    procedure TearDown; override;
  published
    procedure TestBarOffsetSigns;
    procedure TestLineShowsBandAtDragStart;
    procedure TestBandFollowsPointer;
    procedure TestBandStopsAtMinSize;
    procedure TestBandTravelsRightForAlRight;
    procedure TestBandTravelsDownForAlTop;
    procedure TestPatternBandIsPatterned;
    procedure TestNoneShowsNoBand;
    procedure TestUpdateShowsNoBand;
    procedure TestBandGoneAfterRelease;
    procedure TestBandGoneAfterAbandonedDrag;
  end;

  { The band's paint: colour comes from the theme, and rsPattern is not rsLine. }
  TSplitterBandPixelTest = class(TTestCase)
  private
    function BlueRowCount(APatterned: Boolean; out ARows: Integer): Integer;
  published
    procedure TestLineBandIsSolidThemeColour;
    procedure TestPatternBandHasGaps;
  end;

implementation

{ TSplitterVeto }

procedure TSplitterVeto.Reject(Sender: TObject; var ANewSize: Integer; var AAccept: Boolean);
begin
  AAccept := False;
end;

{ TSplitterDriver }

procedure TSplitterDriver.Press(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
end;

procedure TSplitterDriver.DragTo(X, Y: Integer);
begin
  MouseMove([ssLeft], X, Y);
end;

procedure TSplitterDriver.Release(X, Y: Integer);
begin
  MouseUp(mbLeft, [], X, Y);
end;

procedure TSplitterDriver.LoseButton(X, Y: Integer);
begin
  MouseMove([], X, Y);
end;

{ TSplitterDeferredTest }

{ Align=alNone + explicit bounds on both controls so LCL's auto-alignment engine
  never repositions them mid-test (headless it does not run at all, and when it does
  it would move the alLeft splitter to Left=0 and FindResizeTarget would find nothing).
  The splitter's Align is set LAST so Vertical() is True and the Width axis is used. }
procedure TSplitterDeferredTest.Build(AStyle: TResizeStyle);
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 200);

  FPane := TPanel.Create(FForm);
  FPane.Parent := FForm;
  FPane.Align := alNone;
  FPane.SetBounds(0, 0, 100, 200);

  FSplit := TSplitterDriver.Create(FForm);
  FSplit.Parent := FForm;
  FSplit.Align := alNone;
  FSplit.SetBounds(100, 0, 5, 200);
  FSplit.Align := alLeft;
  FSplit.Left := 100;
  FSplit.MinSize := 40;
  FSplit.ResizeStyle := AStyle;
end;

procedure TSplitterDeferredTest.TearDown;
begin
  FreeAndNil(FForm);
  inherited TearDown;
end;

procedure TSplitterDeferredTest.TestLineDefersUntilRelease;
begin
  Build(rsLine);
  FSplit.Press(0, 100);
  FSplit.DragTo(60, 100);
  AssertEquals('rsLine must not resize while the button is held', 100, FPane.Width);
  FSplit.Release(60, 100);
  AssertEquals('rsLine must apply the drag on release', 160, FPane.Width);
end;

procedure TSplitterDeferredTest.TestPatternDefersUntilRelease;
begin
  Build(rsPattern);
  FSplit.Press(0, 100);
  FSplit.DragTo(60, 100);
  AssertEquals('rsPattern must not resize while the button is held', 100, FPane.Width);
  FSplit.Release(60, 100);
  AssertEquals('rsPattern must apply the drag on release', 160, FPane.Width);
end;

procedure TSplitterDeferredTest.TestNoneDefersUntilRelease;
begin
  Build(rsNone);
  FSplit.Press(0, 100);
  FSplit.DragTo(60, 100);
  AssertEquals('rsNone must not resize while the button is held', 100, FPane.Width);
  FSplit.Release(60, 100);
  AssertEquals('rsNone must apply the drag on release', 160, FPane.Width);
end;

{ The deferred path must clamp exactly like the live one -- it shares ApplySize. }
{ The deferred path must reach the SAME clamp the live path uses -- including AutoSnap,
  which is on by default. So a drag far past MinSize closes the pane, and turning AutoSnap
  off makes the identical drag stop at MinSize instead. Asserting only one of the two
  would pass while the preview and the commit disagreed about the other. }
procedure TSplitterDeferredTest.TestDeferredHonoursMinSize;
begin
  Build(rsPattern);
  FSplit.Press(0, 100);
  FSplit.DragTo(-1000, 100);
  FSplit.Release(-1000, 100);
  AssertEquals('AutoSnap on (the default): a drag past MinSize closes the pane',
    0, FPane.Width);

  FPane.Width := 100;
  FSplit.AutoSnap := False;
  FSplit.Press(0, 100);
  FSplit.DragTo(-1000, 100);
  FSplit.Release(-1000, 100);
  AssertEquals('AutoSnap off: the same drag floors at MinSize', 40, FPane.Width);
end;

procedure TSplitterDeferredTest.TestDeferredHonoursCanResizeVeto;
var
  Veto: TSplitterVeto;
begin
  Build(rsNone);
  Veto := TSplitterVeto.Create;
  try
    FSplit.OnCanResize := @Veto.Reject;
    FSplit.Press(0, 100);
    FSplit.DragTo(60, 100);
    FSplit.Release(60, 100);
    AssertEquals('a vetoing OnCanResize blocks the deferred resize too', 100, FPane.Width);
  finally
    FSplit.OnCanResize := nil;
    Veto.Free;
  end;
end;

{ Capture theft / Alt+Tab / a modal dialog can swallow the MouseUp. The live path
  already bails out on the first button-less move; the deferred path must not then
  commit a resize when a stray MouseUp finally arrives. }
procedure TSplitterDeferredTest.TestAbandonedDragNeverResizes;
begin
  Build(rsLine);
  FSplit.Press(0, 100);
  FSplit.DragTo(60, 100);
  FSplit.LoseButton(60, 100);
  FSplit.Release(60, 100);
  AssertEquals('an abandoned drag must not resize on a late MouseUp', 100, FPane.Width);
end;

{ TSplitterBandTest }

procedure TSplitterBandTest.BuildLeft(AStyle: TResizeStyle);
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 200);

  FPane := TPanel.Create(FForm);
  FPane.Parent := FForm;
  FPane.Align := alNone;
  FPane.SetBounds(0, 0, 100, 200);

  FSplit := TSplitterDriver.Create(FForm);
  FSplit.Parent := FForm;
  FSplit.Align := alNone;
  FSplit.SetBounds(100, 0, 5, 200);
  FSplit.Align := alLeft;
  FSplit.Left := 100;
  FSplit.MinSize := 40;
  FSplit.ResizeStyle := AStyle;
end;

{ Mirror image: the pane sits AFTER the bar, so it grows when the pointer goes left. }
procedure TSplitterBandTest.BuildRight(AStyle: TResizeStyle);
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 200);

  FSplit := TSplitterDriver.Create(FForm);
  FSplit.Parent := FForm;
  FSplit.Align := alNone;
  FSplit.SetBounds(100, 0, 5, 200);

  FPane := TPanel.Create(FForm);
  FPane.Parent := FForm;
  FPane.Align := alNone;
  FPane.SetBounds(105, 0, 100, 200);

  FSplit.Align := alRight;
  FSplit.Left := 100;
  FSplit.MinSize := 40;
  FSplit.ResizeStyle := AStyle;
end;

procedure TSplitterBandTest.BuildTop(AStyle: TResizeStyle);
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 300);

  FPane := TPanel.Create(FForm);
  FPane.Parent := FForm;
  FPane.Align := alNone;
  FPane.SetBounds(0, 0, 400, 100);

  FSplit := TSplitterDriver.Create(FForm);
  FSplit.Parent := FForm;
  FSplit.Align := alNone;
  FSplit.SetBounds(0, 100, 400, 5);
  FSplit.Align := alTop;
  FSplit.Top := 100;
  FSplit.MinSize := 40;
  FSplit.ResizeStyle := AStyle;
end;

procedure TSplitterBandTest.TearDown;
begin
  FreeAndNil(FForm);
  inherited TearDown;
end;

procedure TSplitterBandTest.TestBarOffsetSigns;
begin
  // alLeft/alTop: the pane precedes the bar, so pane growth IS the bar's travel.
  AssertEquals('alLeft grew 20', 20, TySplitterBarOffset(alLeft, 100, 120));
  AssertEquals('alTop shrank 20', -20, TySplitterBarOffset(alTop, 100, 80));
  // alRight/alBottom: the pane grows away from the pointer, so the signs invert.
  AssertEquals('alRight shrank 20 -> bar moved +20', 20, TySplitterBarOffset(alRight, 100, 80));
  AssertEquals('alBottom grew 20 -> bar moved -20', -20, TySplitterBarOffset(alBottom, 100, 120));
  // Fed an already-clamped size, the travel is clamped with it. AutoSnap decides WHERE
  // the clamp lands, so both settings are pinned -- the band has to follow whichever the
  // release will actually commit.
  AssertEquals('AutoSnap on: the pane closes, so the bar travels all the way', -100,
    TySplitterBarOffset(alLeft, 100, TySplitterNewSize(alLeft, 100, -1000, 40, 1000, True)));
  AssertEquals('AutoSnap off: the bar stops where MinSize stops the pane', -60,
    TySplitterBarOffset(alLeft, 100, TySplitterNewSize(alLeft, 100, -1000, 40, 1000, False)));
end;

procedure TSplitterBandTest.TestLineShowsBandAtDragStart;
begin
  BuildLeft(rsLine);
  AssertNull('no band before the drag', FSplit.DragBand);
  FSplit.Press(0, 100);
  AssertNotNull('rsLine must show a band while the button is held', FSplit.DragBand);
  AssertEquals('band starts on the bar', 100, FSplit.DragBand.BoundsRect.Left);
  AssertEquals('band is the bar''s width', 5, FSplit.DragBand.Width);
  AssertEquals('band is the bar''s height', 200, FSplit.DragBand.Height);
  AssertSame('band is a sibling of the bar', FSplit.Parent, FSplit.DragBand.Parent);
end;

procedure TSplitterBandTest.TestBandFollowsPointer;
begin
  BuildLeft(rsLine);
  FSplit.Press(0, 100);
  FSplit.DragTo(60, 100);
  AssertNotNull('band still up mid-drag', FSplit.DragBand);
  AssertEquals('band tracks the pointer 1:1', 160, FSplit.DragBand.BoundsRect.Left);
  AssertEquals('the bar itself has not moved yet', 100, FSplit.Left);
end;

{ Without this the band keeps sliding while the mouse does, then the release lands the
  pane at MinSize somewhere the band never was. }
{ The band previews what the release will commit, so it follows the SAME clamp -- with
  AutoSnap on that is a closed pane, with it off that is MinSize. A band that stopped at
  MinSize while the release closed the pane would be a preview that lies. }
procedure TSplitterBandTest.TestBandStopsAtMinSize;
begin
  BuildLeft(rsLine);
  FSplit.AutoSnap := False;
  FSplit.Press(0, 100);
  FSplit.DragTo(-1000, 100);
  AssertNotNull('band still up mid-drag', FSplit.DragBand);
  AssertEquals('AutoSnap off: band stops where MinSize stops the pane',
    40, FSplit.DragBand.BoundsRect.Left);
  FSplit.Release(-1000, 100);

  BuildLeft(rsLine);
  FSplit.Press(0, 100);
  FSplit.DragTo(-1000, 100);
  AssertNotNull('band still up mid-drag', FSplit.DragBand);
  AssertEquals('AutoSnap on: it follows the pane all the way shut',
    0, FSplit.DragBand.BoundsRect.Left);
end;

procedure TSplitterBandTest.TestBandTravelsRightForAlRight;
begin
  BuildRight(rsLine);
  FSplit.Press(0, 100);
  FSplit.DragTo(60, 100);
  AssertNotNull('band still up mid-drag', FSplit.DragBand);
  AssertEquals('an alRight band follows the pointer, not the pane', 160,
    FSplit.DragBand.BoundsRect.Left);
  AssertEquals('alRight defers the shrink to release', 100, FPane.Width);
  FSplit.Release(60, 100);
  AssertEquals('alRight pane shrinks by the drag', 40, FPane.Width);
end;

procedure TSplitterBandTest.TestBandTravelsDownForAlTop;
begin
  BuildTop(rsPattern);
  FSplit.Press(200, 0);
  FSplit.DragTo(200, 60);
  AssertNotNull('band still up mid-drag', FSplit.DragBand);
  AssertEquals('a horizontal bar moves in Y', 160, FSplit.DragBand.BoundsRect.Top);
  AssertEquals('and not in X', 0, FSplit.DragBand.BoundsRect.Left);
  AssertFalse('a wide bar dashes along X', FSplit.DragBand.AlongY);
  FSplit.Release(200, 60);
  AssertEquals('height applied on release', 160, FPane.Height);
end;

procedure TSplitterBandTest.TestPatternBandIsPatterned;
begin
  BuildLeft(rsPattern);
  FSplit.Press(0, 100);
  AssertNotNull('rsPattern must show a band too', FSplit.DragBand);
  AssertTrue('rsPattern draws the dotted band', FSplit.DragBand.Patterned);
  AssertTrue('a tall bar dashes along Y', FSplit.DragBand.AlongY);
end;

procedure TSplitterBandTest.TestNoneShowsNoBand;
begin
  BuildLeft(rsNone);
  FSplit.Press(0, 100);
  AssertNull('rsNone means NO feedback', FSplit.DragBand);
  FSplit.DragTo(60, 100);
  AssertNull('rsNone stays silent through the drag', FSplit.DragBand);
end;

procedure TSplitterBandTest.TestUpdateShowsNoBand;
begin
  BuildLeft(rsUpdate);
  FSplit.Press(0, 100);
  FSplit.DragTo(60, 100);
  AssertNull('rsUpdate resizes live and needs no band', FSplit.DragBand);
  AssertEquals('rsUpdate is still live', 160, FPane.Width);
end;

procedure TSplitterBandTest.TestBandGoneAfterRelease;
begin
  BuildLeft(rsLine);
  FSplit.Press(0, 100);
  FSplit.DragTo(60, 100);
  FSplit.Release(60, 100);
  AssertNull('the band must not outlive the drag', FSplit.DragBand);
end;

{ A stolen MouseUp (capture theft, modal, Alt+Tab) must not strand the band on the
  layout, where it would sit over the panes until the next drag. }
procedure TSplitterBandTest.TestBandGoneAfterAbandonedDrag;
begin
  BuildLeft(rsPattern);
  FSplit.Press(0, 100);
  FSplit.DragTo(60, 100);
  FSplit.LoseButton(60, 100);
  AssertNull('an abandoned drag takes the band with it', FSplit.DragBand);
end;

{ TSplitterBandPixelTest }

{ Renders the live band of a themed splitter and counts how many rows of its centre
  column came out blue. Theme: TySplitter { color: #3B82F6 } -- the same token the grip
  dots use, so a band painted in a hard-coded colour counts zero. }
function TSplitterBandPixelTest.BlueRowCount(APatterned: Boolean; out ARows: Integer): Integer;
var
  Ctl: TTyStyleController;
  Form: TForm;
  Pane: TPanel;
  Split: TSplitterDriver;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  y: Integer;
  px: TBGRAPixel;
begin
  Result := 0;
  ARows := 60;
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss('TySplitter { color: #3B82F6; }');

    Pane := TPanel.Create(Form);
    Pane.Parent := Form;
    Pane.Align := alNone;
    Pane.SetBounds(0, 0, 100, ARows);

    Split := TSplitterDriver.Create(Form);
    Split.Parent := Form;
    Split.Align := alNone;
    Split.SetBounds(100, 0, 5, ARows);
    Split.Align := alLeft;
    Split.Left := 100;
    Split.Controller := Ctl;
    if APatterned then Split.ResizeStyle := rsPattern else Split.ResizeStyle := rsLine;

    Split.Press(0, 10);
    AssertNotNull('the drag must have produced a band to render', Split.DragBand);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(5, ARows);
    Bmp.Canvas.Brush.Color := clWhite;   // so blue stands out against the untouched gaps
    Bmp.Canvas.FillRect(0, 0, 5, ARows);
    Split.DragBand.RenderTo(Bmp.Canvas, Rect(0, 0, 5, ARows), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      for y := 0 to ARows - 1 do
      begin
        px := Reread.GetPixel(2, y);
        if px.blue > px.red + 50 then Inc(Result);
      end;
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TSplitterBandPixelTest.TestLineBandIsSolidThemeColour;
var
  blue, rows: Integer;
begin
  blue := BlueRowCount(False, rows);
  AssertEquals('rsLine paints a solid bar in the theme colour', rows, blue);
end;

procedure TSplitterBandPixelTest.TestPatternBandHasGaps;
var
  blue, rows: Integer;
begin
  blue := BlueRowCount(True, rows);
  AssertTrue('rsPattern paints in the theme colour too', blue > 0);
  AssertTrue('rsPattern is dashed, not solid — it must leave gaps', blue < rows);
end;

{ ------------------------------------------------ ResizeAnchor: a REFUSAL, pinned ------- }

{ LCL's TCustomSplitter.ResizeAnchor (extctrls.pp:430) reads like a small property that says
  which neighbour a drag resizes. It is not. It is the SWITCH BETWEEN THE CLASS'S TWO MODES,
  and we only implement one of them.

  The class comment spells the two out (extctrls.pp:361-369):
    1. Align mode   -- Align := alLeft/alRight/alTop/alBottom; the adjacent sibling is resized.
                       This is everything TTySplitter does.
    2. Anchored     -- Align := alNone + AnchorSides + ResizeAnchor.

  The two setters clamp each other, so at rest the pair CANNOT disagree:
    SetAlign        (customsplitter.inc:770-775) derives FResizeAnchor from Align;
    SetResizeAnchor (:515-525) sets it and then, outside csLoading, forces Align := alNone.
  In other words "assigning ResizeAnchor" MEANS "leave Align mode". That is the whole property,
  and it is why the target lookup forks (GetResizeControl, :127-133): FindAlignControl in Align
  mode, AnchorSide[ResizeAnchor].Control in anchored mode -- and we have no anchored mode at all
  (FindResizeTarget requires Align in [alLeft..alBottom] by construction).

  So publishing a ResizeAnchor that merely picks a neighbour INSIDE Align mode would ship a
  public member whose NAME is LCL's and whose MEANING is not -- the exact defect this parity
  pass exists to remove, and one this codebase has already been bitten by twice on one class
  (Values[] by row vs by key, VisibleRowCount data vs viewport; see test.parity.valuelist.pas).
  Ported code would compile and quietly do something else.

  Hence: either anchored mode gets built, or the NAME does not ship. This guard pins the second
  choice, so a later half-version has to come through here and read the reasoning first.
  docs/controls/splitter.md §8 carries the full specification, including why the blocker is
  VERIFICATION rather than code volume: anchored resizing is produced entirely by LCL's
  align/anchor engine, which AutoSizeDelayed suppresses while the parent form has no handle,
  so every headless guard over it would be fake-green. }
type
  TSplitterResizeAnchorRefusalTest = class(TTestCase)
  published
    procedure TestResizeAnchorStaysUnpublishedUntilAnchoredModeExists;
  end;

procedure TSplitterResizeAnchorRefusalTest.TestResizeAnchorStaysUnpublishedUntilAnchoredModeExists;
begin
  AssertTrue('ResizeAnchor must not ship while anchored mode does not exist -- see the note above',
    GetPropInfo(TTySplitter, 'ResizeAnchor') = nil);
  { The other half of the same refusal: these three are LCL's anchored-mode API, and one of them
    appearing alone would mean the mode had been half-built. }
  AssertTrue('nor ResizeControl, which is anchored mode''s target accessor',
    GetPropInfo(TTySplitter, 'ResizeControl') = nil);
  AssertTrue('nor OnCanOffset -- anchored mode negotiates an OFFSET, not a size',
    GetPropInfo(TTySplitter, 'OnCanOffset') = nil);
end;

initialization
  RegisterTest(TSplitterDeferredTest);
  RegisterTest(TSplitterBandTest);
  RegisterTest(TSplitterBandPixelTest);
  RegisterTest(TSplitterResizeAnchorRefusalTest);
end.
</content>
</invoke>
