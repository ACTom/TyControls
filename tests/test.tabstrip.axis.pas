unit test.tabstrip.axis;
{ TTyCustomTabStrip: TabPosition (the band's edge) and tab icons.

  The point of this unit is not that four positions render -- it is that they render
  through the SAME transform the hit test, the drag-reorder midpoint and the scroll offset
  go through. §3.11 of plans/2026-08-04-rtl-mirroring-scope.md unified those four x-axis
  consumers onto one source; TabPosition is exactly the change that tempts a second
  geometry path, so most of what is asserted below is agreement BETWEEN consumers rather
  than any one consumer's answer:

    * PaintAndHitTestAgree*   -- the pixels the paint filled are the rect the hit test names
    * DragMidpointFollows*    -- the drop slot flips at the midpoint the paint actually drew
    * ScrollMoves*            -- one offset moves the paint and the hit test together

  Every probe is aimed at an EDGE (one pixel inside a boundary, one pixel either side of a
  midpoint). A probe at a tab's centre passes for any transform that is merely in the right
  neighbourhood, which is the failure mode these guards exist to catch. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes, ComCtrls,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.ImageCollection,
  tyControls.TabStrip, tyControls.PageControl, tyControls.TabSheet, tyControls.TabSet,
  test.tabstrip;
type
  { RenderTo is protected on the header engine; reach it without touching visibility.
    Derived from test.tabstrip's TStripAccess so the caption list and the mouse/key
    forwarders come for free (the RTL suite does the same). }
  TAxisStrip = class(TStripAccess)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TAxisPager = class(TTyPageControl)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TTabAxisTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FStrip: TAxisStrip;
    FColl: TTyImageCollection;
    FList: TTyVirtualImageList;
    procedure Build(APos: TTabPosition; ACount: Integer = 4;
                    AW: Integer = 400; AH: Integer = 300;
                    AClosable: Boolean = False; ARtl: Boolean = False);
    procedure MakeImages(AIconColor: TBGRAPixel);
    function  Shot: TBGRABitmap;
    { A device-px point on the band at main-axis coordinate AMain, placed at the band's
      CROSS centre so the probe is unambiguously on the band. }
    function  AtMain(AMain: Integer): TPoint;
    function  MainLo(const R: TRect): Integer;
    function  MainHi(const R: TRect): Integer;
    { Bounding box of every pixel of AColor, or an empty rect when there are none. }
    function  BoundsOfColor(bmp: TBGRABitmap; AColor: TBGRAPixel): TRect;
    procedure CheckDragFollowsPaint(APos: TTabPosition; ARtl: Boolean);
  protected
    procedure TearDown; override;
  published
    { --- the default shape must not have moved ------------------------------------- }
    procedure DefaultIsTopAndTheTransformIsTheIdentity;
    procedure NoImageListMeasuresExactlyAsBefore;
    { --- one source: paint / hit test / drag / scroll -------------------------------- }
    procedure PaintAndHitTestAgreeAtEveryPosition;
    procedure DragMidpointFollowsThePaintAtEveryPosition;
    procedure DragMidpointFollowsThePaintWhenMirrored;
    procedure ScrollMovesPaintAndHitTestTogetherAtEveryPosition;
    { --- band placement -------------------------------------------------------------- }
    procedure BottomBandSitsUnderTheBody;
    procedure SideBandIsAsThickAsItsWidestCaption;
    procedure SideBandRowsAreUniformAndStack;
    procedure RightBandInsetsTheTrailingEdge;
    procedure TabHeightZeroStillMeansNoBandAtEveryPosition;
    procedure MirroringMovesASideBandToTheOtherEdge;
    procedure PaintFillsTheBandOnTheChosenEdge;
    { --- keyboard / overflow --------------------------------------------------------- }
    procedure UpAndDownStepOnlyOnASideBand;
    procedure MirroringDoesNotReverseASideBand;
    procedure SideBandArrowsScrollAlongTheSideBand;
    { --- icons ----------------------------------------------------------------------- }
    procedure AnIconWidensItsTabByTheReservedSlot;
    procedure IconSitsInsideItsTabAtTheLeadingEdge;
    procedure MirroringPutsTheIconOnTheTrailingSide;
    procedure ImagesWidthPinsTheIconSize;
    procedure IconIsActuallyDrawnIntoItsSlot;
    procedure IconTravelsWithItsTabAtEveryPosition;
    procedure FreeingTheImageListDropsTheReference;
    { --- icons on a real pager -------------------------------------------------------- }
    procedure PageImageIndexIsWhatTheStripReads;
    procedure OnGetImageIndexHasTheLastWord;
    procedure ReorderingCarriesTheIconWithItsPage;
  end;

implementation

const
  { A distinct colour per role so a bitmap scan can tell them apart with no tolerance.
    Border radius 0 and border width 0 keep the fills rectangular, so a bounding box IS
    the rect the painter was handed. }
  AxisCss =
    'TyTabControl  { background: #FFFFFF; border-width: 0px; border-radius: 0px; }' +
    'TyPageControl { background: #FFFFFF; border-width: 0px; border-radius: 0px; }' +
    'TyTabSet      { background: #FFFFFF; border-width: 0px; border-radius: 0px; }' +
    'TyTabSheet    { background: #FFFFFF; border-width: 0px; border-radius: 0px; }' +
    'TyTab         { background: #FFFFFF; color: #101010; font-size: 12px; ' +
                    'border-width: 0px; border-radius: 0px; }' +
    'TyTab:active  { background: #FF0000; color: #101010; }';
  ActiveRed: TBGRAPixel = (blue: 0; green: 0; red: 255; alpha: 255);
  IconBlue:  TBGRAPixel = (blue: 255; green: 0; red: 0; alpha: 255);
  AllPositions: array[0..3] of TTabPosition = (tpTop, tpBottom, tpLeft, tpRight);

function PosName(P: TTabPosition): string;
begin
  case P of
    tpTop:    Result := 'tpTop';
    tpBottom: Result := 'tpBottom';
    tpLeft:   Result := 'tpLeft';
  else        Result := 'tpRight';
  end;
end;

procedure TAxisStrip.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TAxisPager.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

{ ---------------------------------------------------------------------------------- }

procedure TTabAxisTest.Build(APos: TTabPosition; ACount, AW, AH: Integer;
  AClosable, ARtl: Boolean);
var
  i: Integer;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 640, 480);
  FCtl := TTyStyleController.Create(FForm);
  FCtl.LoadThemeCss(AxisCss);
  FStrip := TAxisStrip.Create(FForm);
  FStrip.Parent := FForm;
  FStrip.Controller := FCtl;
  FStrip.Font.PixelsPerInch := 96;
  FStrip.TabHeight := 28;              // pin it: the fixture must not follow density
  FStrip.SetBounds(0, 0, AW, AH);
  FStrip.TabsClosable := AClosable;
  for i := 1 to ACount do FStrip.AddCap('Tab ' + IntToStr(i));
  if ARtl then FStrip.BiDiMode := bdRightToLeft;
  FStrip.TabPosition := APos;
end;

procedure TTabAxisTest.MakeImages(AIconColor: TBGRAPixel);
var
  b: TBGRABitmap;
begin
  FColl := TTyImageCollection.Create(FForm);
  b := TBGRABitmap.Create(16, 16, AIconColor);
  try
    FColl.AddBitmap('dot', b);
  finally
    b.Free;
  end;
  FList := TTyVirtualImageList.Create(FForm);
  FList.Collection := FColl;
  FList.Names.Add('dot');
end;

procedure TTabAxisTest.TearDown;
begin
  if FForm <> nil then FForm.Free;
  FForm := nil; FStrip := nil; FCtl := nil; FColl := nil; FList := nil;
end;

function TTabAxisTest.Shot: TBGRABitmap;
var
  host: TBitmap;
begin
  host := TBitmap.Create;
  try
    host.PixelFormat := pf32bit;
    host.SetSize(FStrip.Width, FStrip.Height);
    host.Canvas.Brush.Color := clWhite;
    host.Canvas.FillRect(0, 0, FStrip.Width, FStrip.Height);
    FStrip.Render(host.Canvas, Rect(0, 0, FStrip.Width, FStrip.Height), 96);
    Result := TBGRABitmap.Create(host);
  finally
    host.Free;
  end;
end;

function TTabAxisTest.AtMain(AMain: Integer): TPoint;
var
  b: TRect;
begin
  b := FStrip.BandRect;
  if FStrip.BandIsVertical then
    Result := Point((b.Left + b.Right) div 2, AMain)
  else
    Result := Point(AMain, (b.Top + b.Bottom) div 2);
end;

function TTabAxisTest.MainLo(const R: TRect): Integer;
begin
  if FStrip.BandIsVertical then Result := R.Top else Result := R.Left;
end;

function TTabAxisTest.MainHi(const R: TRect): Integer;
begin
  if FStrip.BandIsVertical then Result := R.Bottom else Result := R.Right;
end;

function TTabAxisTest.BoundsOfColor(bmp: TBGRABitmap; AColor: TBGRAPixel): TRect;
var
  x, y: Integer;
  p: TBGRAPixel;
  found: Boolean;
begin
  Result := Rect(0, 0, 0, 0);
  found := False;
  for y := 0 to bmp.Height - 1 do
    for x := 0 to bmp.Width - 1 do
    begin
      p := bmp.GetPixel(x, y);
      if (p.red = AColor.red) and (p.green = AColor.green) and (p.blue = AColor.blue) then
      begin
        if not found then
        begin
          Result := Rect(x, y, x + 1, y + 1);
          found := True;
        end
        else
        begin
          if x < Result.Left then Result.Left := x;
          if y < Result.Top then Result.Top := y;
          if x + 1 > Result.Right then Result.Right := x + 1;
          if y + 1 > Result.Bottom then Result.Bottom := y + 1;
        end;
      end;
    end;
end;

{ === the default shape must not have moved ======================================== }

{ tpTop is the shipped default and the suite is full of pixel tests taken at it, so the
  transform has to reduce to the identity there: no band origin to add, nothing to embed,
  nothing to reflect. Asserted on the transform itself rather than on a screenshot, because
  a screenshot can only say "the same as last time" and this says WHY. }
procedure TTabAxisTest.DefaultIsTopAndTheTransformIsTheIdentity;
var
  r, s: TRect;
  i: Integer;
begin
  Build(tpTop);
  AssertEquals('a strip that was never told still starts at the top',
    Ord(tpTop), Ord(FStrip.TabPosition));
  AssertFalse('a top band does not run vertically', FStrip.BandIsVertical);
  AssertEquals('a top band is exactly one tab-height thick',
    28, FStrip.BandThicknessPx);
  AssertEquals('the band starts at the control origin', 0, FStrip.BandRect.Top);
  AssertEquals('the band spans the control width', FStrip.Width, FStrip.BandRect.Right);

  { The four tabs fit, so there is no scroll and no arrow inset: content space and screen
    space must be the same space, rect for rect. }
  for i := 0 to FStrip.TabCount - 1 do
  begin
    r := FStrip.TyTabHeaderRect(i);
    s := FStrip.ToScreenRect(r);
    AssertEquals('tab ' + IntToStr(i) + ' left moved', r.Left, s.Left);
    AssertEquals('tab ' + IntToStr(i) + ' top moved', r.Top, s.Top);
    AssertEquals('tab ' + IntToStr(i) + ' right moved', r.Right, s.Right);
    AssertEquals('tab ' + IntToStr(i) + ' bottom moved', r.Bottom, s.Bottom);
    AssertEquals('TabRect is still the shifted header rect',
      r.Left, FStrip.TabRect(i).Left);
    AssertEquals('a top band still runs from y=0', 0, r.Top);
    AssertEquals('a top band is still TabHeight tall', 28, r.Bottom);
  end;

  { The body still starts below the band and keeps the full width. }
  s := FStrip.DisplayRect;
  AssertEquals('body top', 28, s.Top);
  AssertEquals('body left', 0, s.Left);
  AssertEquals('body right', FStrip.Width, s.Right);
  AssertEquals('body bottom', FStrip.Height, s.Bottom);
end;

{ Icons must be free when there is no list: the slot is reserved off IconPx, which answers
  0 without one, so every measurement below must land on the pre-icon number. }
procedure TTabAxisTest.NoImageListMeasuresExactlyAsBefore;
var
  bare: array of Integer;
  i: Integer;
begin
  Build(tpTop);
  SetLength(bare, FStrip.TabCount);
  for i := 0 to FStrip.TabCount - 1 do
    bare[i] := FStrip.TyTabHeaderRect(i).Right - FStrip.TyTabHeaderRect(i).Left;

  { A list is present but no tab claims an index -> still no slot anywhere. }
  MakeImages(IconBlue);
  FStrip.Images := FList;
  for i := 0 to FStrip.TabCount - 1 do
  begin
    AssertEquals('tab ' + IntToStr(i) + ' widened without an ImageIndex',
      bare[i], FStrip.TyTabHeaderRect(i).Right - FStrip.TyTabHeaderRect(i).Left);
    AssertEquals('a tab with no index reports no icon', -1, FStrip.TabImageIndex(i));
    AssertTrue('a tab with no index reserves no icon slot',
      FStrip.TabImageRect(i).Right <= FStrip.TabImageRect(i).Left);
  end;
end;

{ === one source: paint / hit test / drag / scroll ================================== }

{ The pixels the paint filled ARE the rect the hit test names -- at every position, and
  probed one pixel inside each of the active tab's four boundaries rather than at its
  centre. A transform that is right to within half a tab passes a centre probe. }
procedure TTabAxisTest.PaintAndHitTestAgreeAtEveryPosition;
var
  pi, i: Integer;
  bmp: TBGRABitmap;
  box: TRect;
begin
  for pi := 0 to High(AllPositions) do
  begin
    Build(AllPositions[pi]);
    try
      for i := 0 to FStrip.TabCount - 1 do
      begin
        FStrip.TabIndex := i;
        bmp := Shot;
        try
          box := BoundsOfColor(bmp, ActiveRed);
          AssertTrue(PosName(AllPositions[pi]) + ': the active tab painted nothing',
            (box.Right > box.Left) and (box.Bottom > box.Top));
          AssertEquals(PosName(AllPositions[pi]) + ': painted left <> TabRect left, tab ' +
            IntToStr(i), FStrip.TabRect(i).Left, box.Left);
          AssertEquals(PosName(AllPositions[pi]) + ': painted top <> TabRect top, tab ' +
            IntToStr(i), FStrip.TabRect(i).Top, box.Top);
          AssertEquals(PosName(AllPositions[pi]) + ': painted right <> TabRect right, tab ' +
            IntToStr(i), FStrip.TabRect(i).Right, box.Right);
          AssertEquals(PosName(AllPositions[pi]) + ': painted bottom <> TabRect bottom, tab ' +
            IntToStr(i), FStrip.TabRect(i).Bottom, box.Bottom);
          { one pixel inside each corner of what was actually painted }
          AssertEquals(PosName(AllPositions[pi]) +
            ': the hit test misses the pixel the paint filled (leading), tab ' + IntToStr(i),
            i, FStrip.IndexOfTabAt(box.Left + 1, box.Top + 1));
          AssertEquals(PosName(AllPositions[pi]) +
            ': the hit test misses the pixel the paint filled (trailing), tab ' + IntToStr(i),
            i, FStrip.IndexOfTabAt(box.Right - 1, box.Bottom - 1));
        finally
          bmp.Free;
        end;
      end;
    finally
      TearDown;
    end;
  end;
end;

{ The silent failure this control is most prone to: the paint moves and the drag-reorder
  midpoint does not. The header and the body have come apart here before.

  One rule, all eight shapes. Let FORWARD be the direction along the band's main SCREEN
  axis in which the collection advances -- down the page on a side band always, and to the
  right on a top/bottom band unless the strip is mirrored. Then for every tab i, taking its
  midpoint AS DRAWN:

      one pixel BACK from it   -> drops into i
      one pixel FORWARD of it  -> drops into i+1 (or stays on i at the last tab)

  Anything that mirrors or moves the paint without taking the drop resolver with it breaks
  this by a whole slot, not by a pixel -- and a probe at a tab's centre would not have
  noticed either way. }
procedure TTabAxisTest.CheckDragFollowsPaint(APos: TTabPosition; ARtl: Boolean);
var
  i, mid, fwd: Integer;
  r: TRect;
  who: string;
begin
  Build(APos, 4, 400, 300, False, ARtl);
  who := PosName(APos);
  if ARtl then who := who + '+rtl';
  try
    if FStrip.BandIsVertical or not ARtl then fwd := 1 else fwd := -1;
    for i := 0 to FStrip.TabCount - 1 do
    begin
      r := FStrip.TabRect(i);
      mid := (MainLo(r) + MainHi(r)) div 2;
      AssertEquals(who + ': one pixel BACK from tab ' + IntToStr(i) +
        '''s drawn midpoint must drop into tab ' + IntToStr(i),
        i, FStrip.TyDropIndexAtPoint(AtMain(mid - fwd), 96));
      if i < FStrip.TabCount - 1 then
        AssertEquals(who + ': one pixel FORWARD of tab ' + IntToStr(i) +
          '''s drawn midpoint must drop into tab ' + IntToStr(i + 1),
          i + 1, FStrip.TyDropIndexAtPoint(AtMain(mid + fwd), 96))
      else
        AssertEquals(who + ': forward of the LAST drawn midpoint must stay on the last tab',
          i, FStrip.TyDropIndexAtPoint(AtMain(mid + fwd), 96));
    end;
  finally
    TearDown;
  end;
end;

procedure TTabAxisTest.DragMidpointFollowsThePaintAtEveryPosition;
var
  pi: Integer;
begin
  for pi := 0 to High(AllPositions) do
    CheckDragFollowsPaint(AllPositions[pi], False);
end;

{ The same rule with the reflection switched on. A mirror applied to the paint but not to
  the drop resolver reverses the answer, so this fails by a whole slot. }
procedure TTabAxisTest.DragMidpointFollowsThePaintWhenMirrored;
var
  pi: Integer;
begin
  for pi := 0 to High(AllPositions) do
    CheckDragFollowsPaint(AllPositions[pi], True);
end;

{ One offset, two consumers. After a scroll the painted tab and the hit-tested tab have to
  have moved by the same amount along the same axis -- an offset applied to the paint but
  measured against the other axis leaves them apart by the whole band. }
procedure TTabAxisTest.ScrollMovesPaintAndHitTestTogetherAtEveryPosition;
var
  pi, before, after, delta, visible: Integer;
  r: TRect;
  who: string;
begin
  for pi := 0 to High(AllPositions) do
  begin
    { Many tabs and a DELIBERATELY non-square control, so "measured against the wrong
      axis" is a different number rather than the same one by luck. }
    Build(AllPositions[pi], 12, 220, 150);
    who := PosName(AllPositions[pi]);
    try
      AssertTrue(who + ': the fixture was supposed to overflow',
        FStrip.TyMaxHeaderScroll > 0);
      if FStrip.BandIsVertical then visible := FStrip.Height else visible := FStrip.Width;
      { --tab-arrow-band is 16, reserved at BOTH ends once the run overflows. }
      AssertEquals(who + ': the overflow was measured against the wrong axis',
        FStrip.TyHeaderStripWidth - (visible - 2 * 16), FStrip.TyMaxHeaderScroll);
      r := FStrip.TabRect(0);
      before := MainLo(r);
      FStrip.SetHeaderScroll(30);
      AssertEquals(who + ': the scroll did not take', 30, FStrip.HeaderScroll);
      r := FStrip.TabRect(0);
      after := MainLo(r);
      delta := before - after;
      AssertEquals(who + ': the paint did not move by the scroll offset', 30, delta);
      { and the hit test moved with it: the pixel just inside tab 0's new leading edge
        still names tab 0, and the pixel just before it does not. }
      AssertEquals(who + ': the hit test did not follow the scroll',
        0, FStrip.IndexOfTabAt(AtMain(MainLo(r) + 1).x, AtMain(MainLo(r) + 1).y));
    finally
      TearDown;
    end;
  end;
end;

{ === band placement =============================================================== }

procedure TTabAxisTest.BottomBandSitsUnderTheBody;
var
  d: TRect;
begin
  Build(tpBottom);
  AssertFalse('a bottom band does not run vertically', FStrip.BandIsVertical);
  AssertEquals('a bottom band is still one tab-height thick', 28, FStrip.BandThicknessPx);
  AssertEquals('the band starts one tab-height above the bottom',
    FStrip.Height - 28, FStrip.BandRect.Top);
  AssertEquals('the band reaches the bottom edge', FStrip.Height, FStrip.BandRect.Bottom);
  AssertEquals('tab 0 is drawn on the bottom band',
    FStrip.Height - 28, FStrip.TabRect(0).Top);
  d := FStrip.DisplayRect;
  AssertEquals('the body starts at the top', 0, d.Top);
  AssertEquals('the body stops above the band', FStrip.Height - 28, d.Bottom);
end;

{ A side band cannot be a tab-height wide: the captions are upright, so the band has to
  hold the longest one. That is the single axis-dependent line in RebuildLayout. }
procedure TTabAxisTest.SideBandIsAsThickAsItsWidestCaption;
var
  widest, i, w, thick: Integer;
begin
  Build(tpTop);
  widest := 0;
  for i := 0 to FStrip.TabCount - 1 do
  begin
    w := FStrip.TyTabHeaderRect(i).Right - FStrip.TyTabHeaderRect(i).Left;
    if w > widest then widest := w;
  end;
  FStrip.TabPosition := tpLeft;
  thick := FStrip.BandThicknessPx;
  AssertEquals('a side band is as thick as the widest caption box it has to hold',
    widest, thick);
  AssertTrue('and therefore wider than one tab height', thick > 28);
  AssertEquals('the body starts after the band', thick, FStrip.DisplayRect.Left);
  AssertEquals('the body keeps the full height', FStrip.Height,
    FStrip.DisplayRect.Bottom);
end;

procedure TTabAxisTest.SideBandRowsAreUniformAndStack;
var
  i: Integer;
  r, prev: TRect;
begin
  Build(tpLeft);
  prev := Rect(0, 0, 0, 0);
  for i := 0 to FStrip.TabCount - 1 do
  begin
    r := FStrip.TabRect(i);
    AssertEquals('row ' + IntToStr(i) + ' is not one tab-height tall',
      28, r.Bottom - r.Top);
    AssertEquals('row ' + IntToStr(i) + ' is not the band''s full width',
      FStrip.BandThicknessPx, r.Right - r.Left);
    AssertEquals('row ' + IntToStr(i) + ' starts at the band''s leading edge',
      0, r.Left);
    if i > 0 then
      AssertEquals('row ' + IntToStr(i) + ' does not sit directly under row ' +
        IntToStr(i - 1), prev.Bottom, r.Top);
    prev := r;
  end;
end;

procedure TTabAxisTest.RightBandInsetsTheTrailingEdge;
var
  thick: Integer;
begin
  Build(tpRight);
  thick := FStrip.BandThicknessPx;
  AssertTrue('a right band runs vertically', FStrip.BandIsVertical);
  AssertEquals('the band starts one thickness in from the right',
    FStrip.Width - thick, FStrip.BandRect.Left);
  AssertEquals('the band reaches the right edge', FStrip.Width, FStrip.BandRect.Right);
  AssertEquals('tab 0 is drawn on the right band',
    FStrip.Width - thick, FStrip.TabRect(0).Left);
  AssertEquals('the body starts at the left', 0, FStrip.DisplayRect.Left);
  AssertEquals('the body stops before the band',
    FStrip.Width - thick, FStrip.DisplayRect.Right);
end;

{ TabHeight = 0 means NO band -- a shipped capability (TyTabHeightAuto's doc comment turns
  on it). Moving the band to another edge must not resurrect it. }
procedure TTabAxisTest.TabHeightZeroStillMeansNoBandAtEveryPosition;
var
  pi: Integer;
  who: string;
begin
  for pi := 0 to High(AllPositions) do
  begin
    Build(AllPositions[pi]);
    who := PosName(AllPositions[pi]);
    try
      FStrip.TabHeight := 0;
      AssertEquals(who + ': a hidden band still has thickness',
        0, FStrip.BandThicknessPx);
      AssertEquals(who + ': a hidden band still eats the body (left)',
        0, FStrip.DisplayRect.Left);
      AssertEquals(who + ': a hidden band still eats the body (top)',
        0, FStrip.DisplayRect.Top);
      AssertEquals(who + ': a hidden band still eats the body (right)',
        FStrip.Width, FStrip.DisplayRect.Right);
      AssertEquals(who + ': a hidden band still eats the body (bottom)',
        FStrip.Height, FStrip.DisplayRect.Bottom);
      AssertEquals(who + ': a hidden band is still hit-testable',
        -1, FStrip.IndexOfTabAt(4, 4));
    finally
      TearDown;
    end;
  end;
end;

{ The reflection is applied to the finished SCREEN rect, so on a side band it moves the
  band across rather than reversing the tab order. }
procedure TTabAxisTest.MirroringMovesASideBandToTheOtherEdge;
var
  thick: Integer;
begin
  Build(tpLeft, 4, 400, 300, False, True);
  thick := FStrip.BandThicknessPx;
  AssertEquals('a mirrored tpLeft band did not move to the right edge',
    FStrip.Width - thick, FStrip.BandRect.Left);
  AssertEquals('and does not reach the right edge', FStrip.Width, FStrip.BandRect.Right);
  AssertEquals('tab 0 is drawn on the mirrored band',
    FStrip.Width - thick, FStrip.TabRect(0).Left);
  AssertEquals('the body should now be inset on the RIGHT',
    FStrip.Width - thick, FStrip.DisplayRect.Right);
  AssertEquals('and flush to the left', 0, FStrip.DisplayRect.Left);
end;

{ Where the INK actually lands, asserted against the control's own box and not against
  BandRect -- a paint that ignored TabPosition would agree with a BandRect that ignored it
  too, and the pair would pass each other. So each case names the half of the control the
  active tab's fill has to be in, and the half it must be nowhere near. }
procedure TTabAxisTest.PaintFillsTheBandOnTheChosenEdge;
var
  pi: Integer;
  bmp: TBGRABitmap;
  box, band: TRect;
  who: string;
  midX, midY: Integer;
begin
  for pi := 0 to High(AllPositions) do
  begin
    Build(AllPositions[pi]);
    who := PosName(AllPositions[pi]);
    try
      FStrip.TabIndex := 0;
      bmp := Shot;
      try
        box  := BoundsOfColor(bmp, ActiveRed);
        band := FStrip.BandRect;
        midX := FStrip.Width div 2;
        midY := FStrip.Height div 2;
        AssertTrue(who + ': nothing was painted for the active tab',
          (box.Right > box.Left) and (box.Bottom > box.Top));
        case AllPositions[pi] of
          tpTop:
            AssertTrue(who + ': the ink should be in the control''s TOP half',
              box.Bottom <= midY);
          tpBottom:
            AssertTrue(who + ': the ink should be in the control''s BOTTOM half',
              box.Top >= midY);
          tpLeft:
            AssertTrue(who + ': the ink should be in the control''s LEFT half',
              box.Right <= midX);
        else
          AssertTrue(who + ': the ink should be in the control''s RIGHT half',
            box.Left >= midX);
        end;
        { and it must still be inside the band the geometry reports, so the two agree }
        AssertTrue(who + ': the active tab was painted outside the band (left)',
          box.Left >= band.Left);
        AssertTrue(who + ': the active tab was painted outside the band (top)',
          box.Top >= band.Top);
        AssertTrue(who + ': the active tab was painted outside the band (right)',
          box.Right <= band.Right);
        AssertTrue(who + ': the active tab was painted outside the band (bottom)',
          box.Bottom <= band.Bottom);
      finally
        bmp.Free;
      end;
    finally
      TearDown;
    end;
  end;
end;

{ === keyboard / overflow ========================================================== }

{ Up/Down move the selection only where the run is vertical. On a top band they must fall
  through untouched, or a host that routes them to the page content stops receiving them. }
procedure TTabAxisTest.UpAndDownStepOnlyOnASideBand;
var
  k: Word;
begin
  Build(tpTop);
  FStrip.TabIndex := 1;
  k := VK_DOWN; FStrip.CallKeyDown(k);
  AssertEquals('a top band must not swallow VK_DOWN', VK_DOWN, k);
  AssertEquals('a top band must not move on VK_DOWN', 1, FStrip.TabIndex);
  k := VK_UP; FStrip.CallKeyDown(k);
  AssertEquals('a top band must not swallow VK_UP', VK_UP, k);
  AssertEquals('a top band must not move on VK_UP', 1, FStrip.TabIndex);

  FStrip.TabPosition := tpLeft;
  k := VK_DOWN; FStrip.CallKeyDown(k);
  AssertEquals('a side band must consume VK_DOWN', 0, k);
  AssertEquals('VK_DOWN steps to the next tab down', 2, FStrip.TabIndex);
  k := VK_UP; FStrip.CallKeyDown(k);
  AssertEquals('a side band must consume VK_UP', 0, k);
  AssertEquals('VK_UP steps back up', 1, FStrip.TabIndex);
end;

{ Reflecting the x axis cannot reverse a run that goes down the page. The arrow keys on a
  mirrored SIDE band therefore keep their meaning, where on a mirrored top band they trade
  (which test.rtl.pas already pins). }
procedure TTabAxisTest.MirroringDoesNotReverseASideBand;
var
  k: Word;
begin
  Build(tpLeft, 4, 400, 300, False, True);
  FStrip.TabIndex := 1;
  k := VK_DOWN; FStrip.CallKeyDown(k);
  AssertEquals('a mirrored side band reversed VK_DOWN', 2, FStrip.TabIndex);
  k := VK_UP; FStrip.CallKeyDown(k);
  AssertEquals('a mirrored side band reversed VK_UP', 1, FStrip.TabIndex);
end;

{ Asserted on the SCROLL DIRECTION a click produces, never on the field name: the two
  arrow rects keep their left/right names on every band (the plan rules a rename out,
  §6.3.6), so on a side band "FScrollLeftRect" is simply the one at the top. }
procedure TTabAxisTest.SideBandArrowsScrollAlongTheSideBand;
var
  back, fwd: TRect;
begin
  Build(tpLeft, 14, 200, 160);
  AssertTrue('the fixture was supposed to overflow', FStrip.TyMaxHeaderScroll > 0);
  back := FStrip.TyTabScrollLeftRect;
  fwd  := FStrip.TyTabScrollRightRect;
  AssertTrue('the back arrow should sit at the TOP of a side band', back.Top < fwd.Top);
  AssertEquals('the back arrow should span the band''s width',
    FStrip.BandRect.Right - FStrip.BandRect.Left, back.Right - back.Left);
  AssertEquals('a fresh strip starts unscrolled', 0, FStrip.HeaderScroll);
  FStrip.CallMouseDown(mbLeft, (fwd.Left + fwd.Right) div 2, (fwd.Top + fwd.Bottom) div 2);
  AssertTrue('clicking the forward arrow must scroll forward',
    FStrip.HeaderScroll > 0);
  FStrip.CallMouseDown(mbLeft, (back.Left + back.Right) div 2,
    (back.Top + back.Bottom) div 2);
  AssertEquals('clicking the back arrow must scroll back', 0, FStrip.HeaderScroll);
end;

{ === icons ======================================================================== }

{ The slot is reserved in the MEASURING pass, so an icon must widen exactly its own tab and
  exactly by icon + gap -- not the neighbours, and not by some rounded-up approximation. }
procedure TTabAxisTest.AnIconWidensItsTabByTheReservedSlot;
var
  pager: TAxisPager;
  bare0, bare1, wide1: Integer;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 640, 480);
  FCtl := TTyStyleController.Create(FForm);
  FCtl.LoadThemeCss(AxisCss);
  MakeImages(IconBlue);
  pager := TAxisPager.Create(FForm);
  pager.Parent := FForm;
  pager.Controller := FCtl;
  pager.Font.PixelsPerInch := 96;
  pager.TabHeight := 28;
  pager.SetBounds(0, 0, 400, 300);
  pager.AddPage('Alpha');
  pager.AddPage('Beta');
  pager.Images := FList;
  pager.ImagesWidth := 16;

  bare0 := pager.TyTabHeaderRect(0).Right - pager.TyTabHeaderRect(0).Left;
  bare1 := pager.TyTabHeaderRect(1).Right - pager.TyTabHeaderRect(1).Left;
  AssertTrue('an assigned list with no indexes must reserve nothing',
    pager.TabImageRect(1).Right = pager.TabImageRect(1).Left);

  pager.Pages[1].ImageIndex := 0;
  wide1 := pager.TyTabHeaderRect(1).Right - pager.TyTabHeaderRect(1).Left;
  { --tab-icon-gap defaults to 6, so the reserved slot is 16 + 6. }
  AssertEquals('the tab did not widen by exactly the reserved icon slot',
    16 + 6, wide1 - bare1);
  AssertEquals('the tab NEXT to it must not have moved a pixel',
    bare0, pager.TyTabHeaderRect(0).Right - pager.TyTabHeaderRect(0).Left);
  AssertEquals('and tab 1 must still start where tab 0 ends',
    pager.TyTabHeaderRect(0).Right, pager.TyTabHeaderRect(1).Left);
end;

procedure TTabAxisTest.IconSitsInsideItsTabAtTheLeadingEdge;
var
  pager: TAxisPager;
  hdr, ico: TRect;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 640, 480);
  FCtl := TTyStyleController.Create(FForm);
  FCtl.LoadThemeCss(AxisCss);
  MakeImages(IconBlue);
  pager := TAxisPager.Create(FForm);
  pager.Parent := FForm;
  pager.Controller := FCtl;
  pager.Font.PixelsPerInch := 96;
  pager.TabHeight := 28;
  pager.SetBounds(0, 0, 400, 300);
  pager.AddPage('Alpha');
  pager.AddPage('Beta');
  pager.Images := FList;
  pager.ImagesWidth := 16;
  pager.Pages[1].ImageIndex := 0;

  hdr := pager.TabRect(1);
  ico := pager.TabImageRect(1);
  AssertTrue('a page with an ImageIndex must reserve an icon slot',
    ico.Right > ico.Left);
  AssertEquals('the icon slot is the pinned size', 16, ico.Right - ico.Left);
  AssertEquals('the icon slot is square', 16, ico.Bottom - ico.Top);
  AssertTrue('the icon slot escaped its tab on the left', ico.Left >= hdr.Left);
  AssertTrue('the icon slot escaped its tab on the right', ico.Right <= hdr.Right);
  AssertTrue('the icon is not vertically centred in its tab',
    Abs(((ico.Top + ico.Bottom) div 2) - ((hdr.Top + hdr.Bottom) div 2)) <= 1);
  AssertTrue('the icon should hug the tab''s LEADING edge, not its middle',
    ico.Left - hdr.Left < (hdr.Right - hdr.Left) div 2);
  AssertEquals('a page without an ImageIndex must reserve nothing',
    0, pager.TabImageRect(0).Right - pager.TabImageRect(0).Left);
end;

procedure TTabAxisTest.MirroringPutsTheIconOnTheTrailingSide;
var
  pager: TAxisPager;
  hdr, ico: TRect;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 640, 480);
  FCtl := TTyStyleController.Create(FForm);
  FCtl.LoadThemeCss(AxisCss);
  MakeImages(IconBlue);
  pager := TAxisPager.Create(FForm);
  pager.Parent := FForm;
  pager.Controller := FCtl;
  pager.Font.PixelsPerInch := 96;
  pager.TabHeight := 28;
  pager.SetBounds(0, 0, 400, 300);
  pager.AddPage('Alpha');
  pager.AddPage('Beta');
  pager.Images := FList;
  pager.ImagesWidth := 16;
  pager.Pages[1].ImageIndex := 0;
  pager.BiDiMode := bdRightToLeft;

  hdr := pager.TabRect(1);
  ico := pager.TabImageRect(1);
  AssertTrue('the icon slot escaped its mirrored tab (left)', ico.Left >= hdr.Left);
  AssertTrue('the icon slot escaped its mirrored tab (right)', ico.Right <= hdr.Right);
  AssertTrue('a mirrored tab''s icon must hug the RIGHT edge -- the reflection moved the ' +
    'leading edge there and the icon has to have gone with it',
    hdr.Right - ico.Right < (hdr.Right - hdr.Left) div 2);
end;

procedure TTabAxisTest.ImagesWidthPinsTheIconSize;
var
  pager: TAxisPager;
  w24, w16: Integer;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 640, 480);
  FCtl := TTyStyleController.Create(FForm);
  FCtl.LoadThemeCss(AxisCss);
  MakeImages(IconBlue);
  pager := TAxisPager.Create(FForm);
  pager.Parent := FForm;
  pager.Controller := FCtl;
  pager.Font.PixelsPerInch := 96;
  pager.TabHeight := 40;
  pager.SetBounds(0, 0, 400, 300);
  pager.AddPage('Alpha');
  pager.Images := FList;
  pager.Pages[0].ImageIndex := 0;

  AssertEquals('ImagesWidth defaults to 0 (= follow the theme token)', 0, pager.ImagesWidth);
  AssertEquals('the token default is 16', 16,
    pager.TabImageRect(0).Right - pager.TabImageRect(0).Left);
  w16 := pager.TabRect(0).Right - pager.TabRect(0).Left;

  pager.ImagesWidth := 24;
  AssertEquals('a pinned ImagesWidth must win over the token', 24,
    pager.TabImageRect(0).Right - pager.TabImageRect(0).Left);
  w24 := pager.TabRect(0).Right - pager.TabRect(0).Left;
  AssertEquals('the tab must widen by exactly the extra icon width', 8, w24 - w16);

  pager.ImagesWidth := -5;
  AssertEquals('a negative ImagesWidth is not a size; it clamps back to the token',
    0, pager.ImagesWidth);
end;

procedure TTabAxisTest.IconIsActuallyDrawnIntoItsSlot;
var
  pager: TAxisPager;
  host: TBitmap;
  bmp: TBGRABitmap;
  ico, painted: TRect;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 640, 480);
  FCtl := TTyStyleController.Create(FForm);
  FCtl.LoadThemeCss(AxisCss);
  MakeImages(IconBlue);
  pager := TAxisPager.Create(FForm);
  pager.Parent := FForm;
  pager.Controller := FCtl;
  pager.Font.PixelsPerInch := 96;
  pager.TabHeight := 28;
  pager.SetBounds(0, 0, 400, 200);
  pager.AddPage('Alpha');
  pager.AddPage('Beta');
  pager.Images := FList;
  pager.ImagesWidth := 16;
  pager.Pages[1].ImageIndex := 0;
  ico := pager.TabImageRect(1);

  host := TBitmap.Create;
  bmp := nil;
  try
    host.PixelFormat := pf32bit;
    host.SetSize(400, 200);
    host.Canvas.Brush.Color := clWhite;
    host.Canvas.FillRect(0, 0, 400, 200);
    pager.Render(host.Canvas, Rect(0, 0, 400, 200), 96);
    bmp := TBGRABitmap.Create(host);
    painted := BoundsOfColor(bmp, IconBlue);
    AssertTrue('the icon was never drawn', (painted.Right > painted.Left));
    AssertEquals('the icon was drawn somewhere other than its slot (left)',
      ico.Left, painted.Left);
    AssertEquals('the icon was drawn somewhere other than its slot (top)',
      ico.Top, painted.Top);
    AssertEquals('the icon was drawn somewhere other than its slot (right)',
      ico.Right, painted.Right);
    AssertEquals('the icon was drawn somewhere other than its slot (bottom)',
      ico.Bottom, painted.Bottom);
  finally
    bmp.Free;
    host.Free;
  end;
end;

{ The icon slot goes through the same ToScreenRect the header does, so it has to land
  inside its own tab on every band -- including the side bands, where the slot is measured
  along the CROSS axis and the row down the main one. }
procedure TTabAxisTest.IconTravelsWithItsTabAtEveryPosition;
var
  pi: Integer;
  pager: TAxisPager;
  hdr, ico: TRect;
  who: string;
begin
  for pi := 0 to High(AllPositions) do
  begin
    FForm := TForm.CreateNew(nil);
    who := PosName(AllPositions[pi]);
    try
      FForm.SetBounds(0, 0, 640, 480);
      FCtl := TTyStyleController.Create(FForm);
      FCtl.LoadThemeCss(AxisCss);
      MakeImages(IconBlue);
      pager := TAxisPager.Create(FForm);
      pager.Parent := FForm;
      pager.Controller := FCtl;
      pager.Font.PixelsPerInch := 96;
      pager.TabHeight := 28;
      pager.SetBounds(0, 0, 400, 300);
      pager.AddPage('Alpha');
      pager.AddPage('Beta');
      pager.Images := FList;
      pager.ImagesWidth := 16;
      pager.Pages[1].ImageIndex := 0;
      pager.TabPosition := AllPositions[pi];

      hdr := pager.TabRect(1);
      ico := pager.TabImageRect(1);
      AssertTrue(who + ': the icon slot vanished', ico.Right > ico.Left);
      AssertTrue(who + ': the icon escaped its tab (left)',   ico.Left   >= hdr.Left);
      AssertTrue(who + ': the icon escaped its tab (top)',    ico.Top    >= hdr.Top);
      AssertTrue(who + ': the icon escaped its tab (right)',  ico.Right  <= hdr.Right);
      AssertTrue(who + ': the icon escaped its tab (bottom)', ico.Bottom <= hdr.Bottom);
      { Vertically centred in its tab at EVERY position -- and that is one statement, not
        four: on a top/bottom band the icon is centred across the band, and on a side band
        it is centred down its own row, which lands on the same screen axis. A slot placed
        with the other axis's formula still fits inside the tab (the numbers are close
        enough) and only this catches it. }
      AssertTrue(who + ': the icon is not vertically centred in its tab',
        Abs(((ico.Top + ico.Bottom) div 2) - ((hdr.Top + hdr.Bottom) div 2)) <= 1);
    finally
      TearDown;
    end;
  end;
end;

procedure TTabAxisTest.FreeingTheImageListDropsTheReference;
var
  pager: TAxisPager;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 640, 480);
  FCtl := TTyStyleController.Create(FForm);
  FCtl.LoadThemeCss(AxisCss);
  { Owner = nil on purpose: the whole reason for the FreeNotification is a list that our
    owner would never tell us about. }
  FColl := TTyImageCollection.Create(nil);
  FList := TTyVirtualImageList.Create(nil);
  FList.Collection := FColl;
  pager := TAxisPager.Create(FForm);
  pager.Parent := FForm;
  pager.Controller := FCtl;
  pager.Font.PixelsPerInch := 96;
  pager.SetBounds(0, 0, 400, 300);
  pager.AddPage('Alpha');
  pager.Images := FList;
  AssertTrue('the list did not take', pager.Images <> nil);
  FreeAndNil(FList);
  AssertTrue('a freed image list left a dangling reference behind',
    pager.Images = nil);
  { and the strip still measures without raising }
  AssertTrue('the strip could not lay out after losing its list',
    pager.TabRect(0).Right > 0);
  FreeAndNil(FColl);
end;

{ === icons on a real pager ======================================================== }

procedure TTabAxisTest.PageImageIndexIsWhatTheStripReads;
var
  pager: TAxisPager;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 640, 480);
  FCtl := TTyStyleController.Create(FForm);
  FCtl.LoadThemeCss(AxisCss);
  MakeImages(IconBlue);
  pager := TAxisPager.Create(FForm);
  pager.Parent := FForm;
  pager.Controller := FCtl;
  pager.Font.PixelsPerInch := 96;
  pager.SetBounds(0, 0, 400, 300);
  pager.AddPage('Alpha');
  pager.AddPage('Beta');
  pager.Images := FList;
  AssertEquals('a fresh page carries no icon', -1, pager.Pages[0].ImageIndex);
  AssertEquals('and the strip agrees', -1, pager.TabImageIndex(0));
  pager.Pages[0].ImageIndex := 0;
  AssertEquals('the strip must read the icon off the PAGE', 0, pager.TabImageIndex(0));
  pager.Pages[0].ImageIndex := -9;
  AssertEquals('anything below -1 is just "no icon"', -1, pager.Pages[0].ImageIndex);
end;

type
  { A handler that always answers 1, so "the event won" is unambiguous. }
  TImgOverride = class
  public
    Seen: Integer;
    constructor Create;
    procedure Handle(Sender: TObject; AIndex: Integer; var AImageIndex: Integer);
  end;

constructor TImgOverride.Create;
begin
  inherited Create;
  Seen := -99;
end;

procedure TImgOverride.Handle(Sender: TObject; AIndex: Integer; var AImageIndex: Integer);
begin
  if AIndex = 0 then
  begin
    Seen := AImageIndex;      // what the per-page half handed over
    AImageIndex := 1;         // and the event overrides it
  end;
end;

procedure TTabAxisTest.OnGetImageIndexHasTheLastWord;
var
  pager: TAxisPager;
  h: TImgOverride;
  b2: TBGRABitmap;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 640, 480);
  FCtl := TTyStyleController.Create(FForm);
  FCtl.LoadThemeCss(AxisCss);
  MakeImages(IconBlue);
  b2 := TBGRABitmap.Create(16, 16, ActiveRed);
  try
    FColl.AddBitmap('dot2', b2);   // AddBitmap copies; we still own b2
  finally
    b2.Free;
  end;
  FList.Names.Add('dot2');
  h := TImgOverride.Create;
  try
    pager := TAxisPager.Create(FForm);
    pager.Parent := FForm;
    pager.Controller := FCtl;
    pager.Font.PixelsPerInch := 96;
    pager.SetBounds(0, 0, 400, 300);
    pager.AddPage('Alpha');
    pager.AddPage('Beta');
    pager.Images := FList;
    pager.Pages[0].ImageIndex := 0;
    pager.OnGetImageIndex := @h.Handle;

    AssertEquals('the event must win over the page''s own index',
      1, pager.TabImageIndex(0));
    AssertEquals('the event must be SEEDED with the page''s index, not with -1',
      0, h.Seen);
    AssertEquals('a tab the handler ignores keeps the page''s answer',
      -1, pager.TabImageIndex(1));
  finally
    h.Free;
  end;
end;

{ The icon lives on the page, so a reorder has to carry it. A parallel array indexed by
  position would hand the moved slot's icon to whatever slid into it. }
procedure TTabAxisTest.ReorderingCarriesTheIconWithItsPage;
var
  pager: TAxisPager;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 640, 480);
  FCtl := TTyStyleController.Create(FForm);
  FCtl.LoadThemeCss(AxisCss);
  MakeImages(IconBlue);
  pager := TAxisPager.Create(FForm);
  pager.Parent := FForm;
  pager.Controller := FCtl;
  pager.Font.PixelsPerInch := 96;
  pager.SetBounds(0, 0, 400, 300);
  pager.AddPage('Alpha');
  pager.AddPage('Beta');
  pager.AddPage('Gamma');
  pager.Images := FList;
  pager.Pages[0].ImageIndex := 0;

  AssertEquals('before the move, slot 0 has the icon', 0, pager.TabImageIndex(0));
  AssertEquals('and slot 2 does not', -1, pager.TabImageIndex(2));
  pager.MovePage(0, 2);
  AssertEquals('the icon stayed behind on the slot instead of travelling with its page',
    0, pager.TabImageIndex(2));
  AssertEquals('and the slot it left must not have inherited it',
    -1, pager.TabImageIndex(0));
  AssertEquals('sanity: the caption travelled too', 'Alpha', pager.TabCaption(2));
end;

initialization
  RegisterTest(TTabAxisTest);
end.
