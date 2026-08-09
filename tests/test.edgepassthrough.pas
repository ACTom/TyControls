unit test.edgepassthrough;
{$mode objfpc}{$H+}

{ The content host's edge passthrough -- what makes a window-shadow:false window mouse-resizable.

  WHY IT EXISTS. `window-shadow: false` puts the NC strategy into full-frame-eat: WM_NCCALCSIZE
  hands the client the WHOLE window rect, because anything less lets Windows legacy-paint a pale
  classic ring over the left/right/bottom bands once DWMWA_NCRENDERING_POLICY is DISABLED
  (measured on Win10 19044: scanning inward from the left edge gives 1px white then 5px of
  180-grey, in both activation states). The cost of eating the frame is that the alClient
  TTyFormSurface then covers every pixel of the window, and mouse messages go to the innermost
  child -- so the FORM is never hit-tested and the zone mapper that reports HTLEFT..HTBOTTOMRIGHT
  never runs. Measured, hovering the bottom-right corner: 13 WM_NCHITTEST + 13
  WM_NCMOUSEMOVE(HTBOTTOMRIGHT) with the shadow on, 0 of each with it off. That was the forum
  report "resizing the form via mouse only works once".

  The host now answers HTTRANSPARENT inside the band, so the system keeps looking and asks the
  form. Nothing is moved or inset, so the mode looks exactly as it did (verified pixel-wise:
  the edge scan is unchanged at 240-grey all the way out).

  WHAT THESE PIN. The band predicate is pure, so the part that can be tested headlessly is
  tested headlessly -- the rest (that HTTRANSPARENT really makes Windows re-ask the parent) is a
  live-window fact and is recorded in the measurements above, not asserted here. }

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Types,
  tyControls.Form;

type
  TEdgePassthroughTest = class(TTestCase)
  private
    { A 200x120 host at a non-zero origin -- the real caller passes SCREEN coordinates, and a
      rect at 0,0 would hide an origin bug completely. }
    function Host: TRect;
    function Pass(AX, AY: Integer; AZone: Integer = 6; AEnabled: Boolean = True): Boolean;
  published
    procedure DisabledNeverPassesAnythingThrough;
    procedure AZoneOfZeroNeverPassesThrough;
    procedure TheInteriorIsNeverPassedThrough;
    procedure EachEdgeBandPassesThrough;
    procedure TheBandIsMeasuredFromTheHostsOwnOrigin;
    procedure TheFarEdgesAreInclusiveOfTheirLastPixel;
    procedure ACornerBelongsToTheBand;
    procedure AHostSmallerThanTwoZonesIsAllBand;
  end;

implementation

function TEdgePassthroughTest.Host: TRect;
begin
  Result := Rect(300, 260, 500, 380);   // 200 x 120 at 300,260
end;

function TEdgePassthroughTest.Pass(AX, AY: Integer; AZone: Integer; AEnabled: Boolean): Boolean;
begin
  Result := TyEdgePassthrough(Host, Point(AX, AY), AZone, AEnabled);
end;

procedure TEdgePassthroughTest.DisabledNeverPassesAnythingThrough;
begin
  { Shadow on, fixed size, or maximized: the host must behave exactly as it always did, or every
    click in the outer 6px of every ordinary form would start falling through to the form. }
  AssertFalse('top-left corner', Pass(300, 260, 6, False));
  AssertFalse('bottom-right corner', Pass(499, 379, 6, False));
  AssertFalse('middle', Pass(400, 320, 6, False));
end;

procedure TEdgePassthroughTest.AZoneOfZeroNeverPassesThrough;
begin
  { A zero zone is "no band", not "everything is band" -- with >= comparisons on the far edges a
    careless implementation turns 0 into the whole rect. }
  AssertFalse('left edge with no zone', Pass(300, 320, 0));
  AssertFalse('right edge with no zone', Pass(499, 320, 0));
  AssertFalse('negative zone', Pass(300, 320, -4));
end;

procedure TEdgePassthroughTest.TheInteriorIsNeverPassedThrough;
begin
  { The half that keeps ordinary use working: everything the user actually clicks stays with the
    host. Measured on the live window as "middle = 0 NC mouse-moves reaching the form". }
  AssertFalse('centre', Pass(400, 320));
  AssertFalse('just inside the left band', Pass(306, 320));
  AssertFalse('just inside the top band', Pass(400, 266));
  AssertFalse('just inside the right band', Pass(493, 320));
  AssertFalse('just inside the bottom band', Pass(400, 373));
end;

procedure TEdgePassthroughTest.EachEdgeBandPassesThrough;
begin
  AssertTrue('left', Pass(300, 320));
  AssertTrue('left, last band pixel', Pass(305, 320));
  AssertTrue('top', Pass(400, 260));
  AssertTrue('top, last band pixel', Pass(400, 265));
  AssertTrue('right', Pass(499, 320));
  AssertTrue('right, first band pixel', Pass(494, 320));
  AssertTrue('bottom', Pass(400, 379));
  AssertTrue('bottom, first band pixel', Pass(400, 374));
end;

procedure TEdgePassthroughTest.TheBandIsMeasuredFromTheHostsOwnOrigin;
var
  r: TRect;
begin
  { The caller hands screen coordinates. An implementation that compared against 0..Width would
    pass here only by accident at the origin, and would treat the whole window as band once it
    moved right or down -- swallowing every click on the form. }
  r := Rect(1000, 700, 1200, 820);
  AssertFalse('a point that is INSIDE this host, but < zone in absolute terms',
    TyEdgePassthrough(r, Point(1100, 760), 6, True));
  AssertTrue('this host''s own left band', TyEdgePassthrough(r, Point(1002, 760), 6, True));
end;

procedure TEdgePassthroughTest.TheFarEdgesAreInclusiveOfTheirLastPixel;
begin
  { Right/Bottom are EXCLUSIVE in a TRect, so the last pixel of a 300..500 host is 499. Getting
    this off by one leaves a 1px dead strip at exactly the corner the user aims for. }
  AssertTrue('the very last horizontal pixel', Pass(499, 320));
  AssertTrue('the very last vertical pixel', Pass(400, 379));
end;

procedure TEdgePassthroughTest.ACornerBelongsToTheBand;
begin
  { Diagonal resize is the common gesture, and a corner satisfies two edge tests at once -- an
    implementation using AND instead of OR would fail exactly here and nowhere else. }
  AssertTrue('top-left', Pass(301, 261));
  AssertTrue('top-right', Pass(498, 261));
  AssertTrue('bottom-left', Pass(301, 378));
  AssertTrue('bottom-right', Pass(498, 378));
end;

procedure TEdgePassthroughTest.AHostSmallerThanTwoZonesIsAllBand;
var
  tiny: TRect;
begin
  { Deliberate, and the same thing the OS does: a window shrunk to its sizing frame is all
    sizing frame. Pinned so nobody "fixes" it into a gap that would make a tiny window
    unresizable. }
  tiny := Rect(10, 10, 18, 18);   // 8x8, zone 6
  AssertTrue('centre of a host narrower than two zones',
    TyEdgePassthrough(tiny, Point(14, 14), 6, True));
end;

initialization
  RegisterTest(TEdgePassthroughTest);

end.
