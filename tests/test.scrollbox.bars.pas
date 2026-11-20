unit test.scrollbox.bars;
{$mode objfpc}{$H+}

{ #239: --scrollbox-bars says which scroll bars a scroll box may show -- both (the default),
  vertical, horizontal or none. A bar that is left out is never shown and takes no room, and
  its axis scrolls all the same: from code, by the wheel, and to bring a child into view.

  Every test here reads geometry the box writes itself (the bars' bounds, the offset, the
  three layout hooks). None asserts where an ALIGNED child ends up: the LCL align engine does
  not run for a form that is never shown, so such an assertion is green on broken code too
  (see test.scrollbox). What a layout pass would do is stood in for by TBarsBox.SpreadOnPass. }

interface

uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.Panel,
  tyControls.ScrollBar, tyControls.ScrollBox, tyControls.ScrollContent,
  tyControls.ScrollPanel;

type
  TBarsBox = class(TTyScrollBox)
  public
    { How many layout passes were asked for through the box, and a stand-in for one: a real
      pass spreads out rows that were stacked at the fold once the layout area has room for
      them, and not before. }
    Asked: Integer;
    SpreadOnPass: TControl;
    SpreadTo: Integer;
    procedure AdjustSize; override;
    function VBar: TTyScrollBar;
    function HBar: TTyScrollBar;
    function VShown: Boolean;
    function HShown: Boolean;
    function Frame: Integer;
    function ChildArea: TRect;
    procedure Wheel(ADelta: Integer);
  end;

  TScrollBoxBarsTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FChild: TControl;           // the content of the box NewBox made last
    FViewport: TTyScrollContent;
    function NewBox(const ABars: string; AChildW, AChildH: Integer;
      AWithViewport: Boolean = False; ARtl: Boolean = False): TBarsBox;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { the token }
    procedure TheTokenNamesTheBarsThatMayShow;
    procedure AnEmptyOrUnknownValueMeansBoth;
    { a bar that is left out }
    procedure ABarLeftOutIsNotShown;
    procedure ABarLeftOutTakesNoRoom;
    procedure TheBarInViewRunsToTheCornerTheOtherLeft;
    procedure ABarOutOfViewDoesNotCallUpTheOther;
    procedure AViewportTakesTheRoomOfABarOutOfView;
    procedure RightToLeftNoGutterIsKeptForAVerticalBarOutOfView;
    procedure AScrollPanelFollowsTheTokenToo;
    { where the token comes from, and when }
    procedure TheTokenIsFollowedTheMomentItChanges;
    procedure AThemeCanSetItAndABoxCanSayOtherwise;
    { its axis scrolls all the same }
    procedure AnAxisWithoutItsBarScrollsFromCode;
    procedure AnAxisWithoutItsBarScrollsSideways;
    procedure TheWheelScrollsAnAxisWithoutItsBar;
    procedure TheWheelGoesSidewaysWhenOnlyThatOverflows;
    procedure TheWheelKeepsToTheVerticalAxisWhenOnlyItsBarIsOutOfView;
    procedure ScrollInViewReachesAChildDownAnAxisWithoutItsBar;
    procedure TheBarInViewFollowsAScrollOnBothAxes;
    procedure TheLayoutAreaGrowsToTheContentAlongAnAxisWithoutItsBar;
    { a box without the token }
    procedure WithNoTokenTheHorizontalAxisScrollsAsItDid;
    { the layout pass }
    procedure AnAxisThatStartsOrStopsScrollingOutOfViewAsksForALayoutPass;
    procedure ABarComingIntoViewIsItsOwnRequest;
    procedure TheBoxMeasuresAgainAfterThePassItAskedFor;
  end;

implementation

const
  cTheme = 'TyScrollBox { background: #FFFFFF; border-width: 1px; border-color: #808080; }';

function BarOf(ABox: TWinControl; AKind: TTyScrollBarKind): TTyScrollBar;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to ABox.ControlCount - 1 do
    if (ABox.Controls[i] is TTyScrollBar)
       and (TTyScrollBar(ABox.Controls[i]).Kind = AKind) then
      Exit(TTyScrollBar(ABox.Controls[i]));
end;

function Shown(ABar: TTyScrollBar): Boolean;
begin
  Result := (ABar <> nil) and ABar.Visible;
end;

{ TBarsBox }

procedure TBarsBox.AdjustSize;
var
  c: TControl;
  area: TRect;
begin
  Inc(Asked);
  inherited AdjustSize;
  if SpreadOnPass = nil then Exit;
  area := ChildArea;
  if area.Bottom - area.Top <= ClientHeight then Exit;   // no room yet: the rows stay stacked
  c := SpreadOnPass;
  SpreadOnPass := nil;
  c.Height := SpreadTo;
end;

function TBarsBox.VBar: TTyScrollBar;
begin
  Result := BarOf(Self, sbVertical);
end;

function TBarsBox.HBar: TTyScrollBar;
begin
  Result := BarOf(Self, sbHorizontal);
end;

function TBarsBox.VShown: Boolean;
begin
  Result := Shown(VBar);
end;

function TBarsBox.HShown: Boolean;
begin
  Result := Shown(HBar);
end;

function TBarsBox.Frame: Integer;
begin
  Result := FrameInset;
end;

{ What the LCL lays children out in: TWinControl.AlignControl takes GetLogicalClientRect and
  TWinControl.AlignControls passes it through AdjustClientRect. }
function TBarsBox.ChildArea: TRect;
begin
  Result := GetLogicalClientRect;
  AdjustClientRect(Result);
end;

procedure TBarsBox.Wheel(ADelta: Integer);
begin
  DoMouseWheel([], ADelta, Point(0, 0));
end;

{ TScrollBoxBarsTest }

procedure TScrollBoxBarsTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(cTheme);
  FForm := TForm.CreateNew(nil);
end;

procedure TScrollBoxBarsTest.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

{ A 300 x 200 box with one child of the given size at its origin, measured. ABars is the
  value of the token in the box's own StyleOverride; '' leaves the token unset. }
function TScrollBoxBarsTest.NewBox(const ABars: string; AChildW, AChildH: Integer;
  AWithViewport, ARtl: Boolean): TBarsBox;
var
  host: TWinControl;
begin
  Result := TBarsBox.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 300, 200);
  if ARtl then Result.BiDiMode := bdRightToLeft;
  if ABars <> '' then Result.StyleOverride := '--scrollbox-bars: ' + ABars + ';';
  FViewport := nil;
  host := Result;
  if AWithViewport then
  begin
    FViewport := TTyScrollContent.Create(Result);
    FViewport.Parent := Result;
    host := FViewport;
  end;
  FChild := TTyPanel.Create(host);
  FChild.Parent := host;
  FChild.SetBounds(0, 0, AChildW, AChildH);
  Result.UpdateScrollRange;
end;

{ --- the token ---------------------------------------------------------------------- }

procedure TScrollBoxBarsTest.TheTokenNamesTheBarsThatMayShow;
var
  v, h: Boolean;
begin
  TyScrollBoxBars('both', v, h);
  AssertTrue('both: vertical', v);
  AssertTrue('both: horizontal', h);
  TyScrollBoxBars('vertical', v, h);
  AssertTrue('vertical: vertical', v);
  AssertFalse('vertical: horizontal', h);
  TyScrollBoxBars('horizontal', v, h);
  AssertFalse('horizontal: vertical', v);
  AssertTrue('horizontal: horizontal', h);
  TyScrollBoxBars('none', v, h);
  AssertFalse('none: vertical', v);
  AssertFalse('none: horizontal', h);
  TyScrollBoxBars('  None ', v, h);
  AssertFalse('case and blanks do not matter: vertical', v);
  AssertFalse('case and blanks do not matter: horizontal', h);
  TyScrollBoxBars('VERTICAL', v, h);
  AssertTrue('upper case: vertical', v);
  AssertFalse('upper case: horizontal', h);
end;

procedure TScrollBoxBarsTest.AnEmptyOrUnknownValueMeansBoth;
var
  v, h: Boolean;
begin
  { A value the box does not know must not cost a form its scroll bars. }
  v := False; h := False;
  TyScrollBoxBars('', v, h);
  AssertTrue('empty: vertical', v);
  AssertTrue('empty: horizontal', h);
  v := False; h := False;
  TyScrollBoxBars('hidden', v, h);
  AssertTrue('unknown: vertical', v);
  AssertTrue('unknown: horizontal', h);
end;

{ --- a bar that is left out --------------------------------------------------------- }

procedure TScrollBoxBarsTest.ABarLeftOutIsNotShown;
var
  B: TBarsBox;
begin
  B := NewBox('both', 800, 600);
  AssertTrue('precondition: this content calls for both bars', B.VShown and B.HShown);
  B := NewBox('vertical', 800, 600);
  AssertTrue('vertical: the vertical bar', B.VShown);
  AssertFalse('vertical: no horizontal bar', B.HShown);
  B := NewBox('horizontal', 800, 600);
  AssertFalse('horizontal: no vertical bar', B.VShown);
  AssertTrue('horizontal: the horizontal bar', B.HShown);
  B := NewBox('none', 800, 600);
  AssertFalse('none: no vertical bar', B.VShown);
  AssertFalse('none: no horizontal bar', B.HShown);
end;

procedure TScrollBoxBarsTest.ABarLeftOutTakesNoRoom;
var
  B, R: TBarsBox;
begin
  R := NewBox('both', 100, 600);
  AssertEquals('precondition: a vertical bar in view costs its width',
    300 - R.VBar.Width, R.ClientWidth);
  B := NewBox('none', 100, 600);
  AssertEquals('out of view, the viewport is the whole width', 300, B.ClientWidth);
  AssertEquals('and children are laid out across it, less the frame',
    300 - 2 * B.Frame, B.ChildArea.Right - B.ChildArea.Left);

  R := NewBox('both', 800, 80);
  AssertEquals('precondition: a horizontal bar in view costs its height',
    200 - R.HBar.Height, R.ClientHeight);
  B := NewBox('none', 800, 80);
  AssertEquals('out of view, the viewport is the whole height', 200, B.ClientHeight);
  AssertEquals('and children are laid out down it, less the frame',
    200 - 2 * B.Frame, B.ChildArea.Bottom - B.ChildArea.Top);
end;

procedure TScrollBoxBarsTest.TheBarInViewRunsToTheCornerTheOtherLeft;
var
  B, R: TBarsBox;
begin
  R := NewBox('both', 800, 600);
  AssertEquals('precondition: with both in view the vertical bar stops short of the corner',
    200 - 2 * R.Frame - R.HBar.Height, R.VBar.Height);
  AssertEquals('precondition: and so does the horizontal one',
    300 - 2 * R.Frame - R.VBar.Width, R.HBar.Width);

  B := NewBox('vertical', 800, 600);
  AssertEquals('alone, the vertical bar has the whole edge', 200 - 2 * B.Frame, B.VBar.Height);
  AssertEquals('and its range is taken from the whole height',
    600 - (200 - 2 * B.Frame), B.VBar.Max);

  B := NewBox('horizontal', 800, 600);
  AssertEquals('alone, the horizontal bar has the whole edge', 300 - 2 * B.Frame, B.HBar.Width);
  AssertEquals('and its range is taken from the whole width',
    800 - (300 - 2 * B.Frame), B.HBar.Max);
end;

procedure TScrollBoxBarsTest.ABarOutOfViewDoesNotCallUpTheOther;
var
  B, R: TBarsBox;
begin
  { 290 px of content fits a 300 px box until a vertical bar takes its gutter. }
  R := NewBox('both', 290, 600);
  AssertTrue('precondition: the vertical bar''s gutter is what calls up the horizontal one',
    R.VShown and R.HShown);
  B := NewBox('horizontal', 290, 600);
  AssertFalse('no vertical bar, no gutter, nothing overflows sideways', B.HShown);
  B.ScrollByDelta(50, 0);
  AssertEquals('and that axis has nowhere to scroll to', 0, B.ScrollX);

  { The same the other way round: 190 px fits a 200 px box until a horizontal bar is under it. }
  R := NewBox('both', 600, 190);
  AssertTrue('precondition: the horizontal bar''s gutter is what calls up the vertical one',
    R.VShown and R.HShown);
  B := NewBox('vertical', 600, 190);
  AssertFalse('no horizontal bar, no gutter, nothing overflows downwards', B.VShown);
  B.ScrollByDelta(0, 50);
  AssertEquals('and that axis has nowhere to scroll to', 0, B.ScrollY);
end;

procedure TScrollBoxBarsTest.AViewportTakesTheRoomOfABarOutOfView;
var
  B, R: TBarsBox;
begin
  R := NewBox('both', 100, 600, True);
  AssertEquals('precondition: the viewport stops at the bar',
    300 - 2 * R.Frame - R.VBar.Width, FViewport.Width);
  B := NewBox('none', 100, 600, True);
  AssertEquals('with the bar out of view the viewport runs to the frame',
    300 - 2 * B.Frame, FViewport.Width);
  B.ScrollByDelta(0, 100);
  AssertEquals('and its content scrolls inside it', -100, FChild.Top);
end;

procedure TScrollBoxBarsTest.RightToLeftNoGutterIsKeptForAVerticalBarOutOfView;
var
  B, R: TBarsBox;
begin
  R := NewBox('both', 800, 600, False, True);
  AssertEquals('precondition: right to left, the horizontal bar starts past the vertical one',
    R.Frame + R.VBar.Width, R.HBar.Left);
  B := NewBox('horizontal', 800, 600, False, True);
  AssertEquals('with the vertical bar out of view it starts at the frame', B.Frame, B.HBar.Left);
  AssertEquals('and so does the content', B.Frame, B.ChildArea.Left);

  R := NewBox('both', 100, 600, True, True);
  AssertEquals('precondition: the viewport starts past the mirrored bar',
    R.Frame + R.VBar.Width, FViewport.Left);
  B := NewBox('none', 100, 600, True, True);
  AssertEquals('and at the frame when the bar is out of view', B.Frame, FViewport.Left);
end;

procedure TScrollBoxBarsTest.AScrollPanelFollowsTheTokenToo;
var
  P: TTyScrollPanel;
  c: TTyPanel;
begin
  P := TTyScrollPanel.Create(FForm);
  P.Parent := FForm;
  P.Controller := FCtl;
  P.Font.PixelsPerInch := 96;
  P.SetBounds(0, 0, 300, 200);
  c := TTyPanel.Create(P);
  c.Parent := P;
  c.SetBounds(0, 0, 100, 600);
  P.UpdateScrollRange;
  AssertTrue('precondition: no token, the panel shows its bar', Shown(BarOf(P, sbVertical)));
  P.StyleOverride := '--scrollbox-bars: none;';
  AssertFalse('the bar is out of view', Shown(BarOf(P, sbVertical)));
  P.ScrollByDelta(0, 100);
  AssertEquals('and the panel still scrolls', 100, P.ScrollY);
end;

{ --- where the token comes from, and when ------------------------------------------- }

procedure TScrollBoxBarsTest.TheTokenIsFollowedTheMomentItChanges;
var
  B: TBarsBox;
begin
  B := NewBox('', 100, 600);
  AssertTrue('precondition: no token, the bar shows', B.VShown);
  B.ScrollByDelta(0, 100);

  B.StyleOverride := '--scrollbox-bars: none;';
  AssertFalse('out of view, with no call to measure again', B.VShown);
  AssertEquals('its room is given back', 300, B.ClientWidth);
  AssertEquals('and the view stays where it was', 100, B.ScrollY);

  B.StyleOverride := '';
  AssertTrue('the token gone, the bar is back', B.VShown);
  AssertEquals('with its gutter', 300 - B.VBar.Width, B.ClientWidth);
  AssertEquals('docked at the right edge, inside the frame',
    300 - B.Frame, B.VBar.Left + B.VBar.Width);
  AssertEquals('and its thumb where the view is', 100, B.VBar.Position);
end;

procedure TScrollBoxBarsTest.AThemeCanSetItAndABoxCanSayOtherwise;
var
  B, Own: TBarsBox;
begin
  FCtl.LoadThemeCss(':root { --scrollbox-bars: none; } ' + cTheme);
  B := NewBox('', 100, 600);
  AssertFalse('the theme''s value is followed', B.VShown);
  Own := NewBox('both', 100, 600);
  AssertTrue('a box''s own StyleOverride comes first', Own.VShown);

  FCtl.LoadThemeCss(cTheme);
  AssertTrue('and a theme without the token brings the bar back', B.VShown);
end;

{ --- its axis scrolls all the same -------------------------------------------------- }

procedure TScrollBoxBarsTest.AnAxisWithoutItsBarScrollsFromCode;
var
  B: TBarsBox;
begin
  B := NewBox('none', 100, 600);
  AssertFalse('precondition: the bar is out of view', B.VShown);
  AssertTrue('precondition: a frame for the viewport to stay inside', B.Frame > 0);
  B.ScrollByDelta(0, 100);
  AssertEquals('ScrollByDelta moves the view', 100, B.ScrollY);
  AssertEquals('and the content with it', -100, FChild.Top);
  B.ScrollTo(0, 30);
  AssertEquals('ScrollTo', 30, B.ScrollY);
  B.ScrollBy(0, -50);
  AssertEquals('ScrollBy, in the LCL''s sign', 80, B.ScrollY);
  B.ScrollByDelta(0, 100000);
  AssertEquals('and it stops where the content ends', 600 - (200 - 2 * B.Frame), B.ScrollY);
  B.ScrollByDelta(0, -100000);
  AssertEquals('and where it starts', 0, B.ScrollY);
end;

procedure TScrollBoxBarsTest.AnAxisWithoutItsBarScrollsSideways;
var
  B: TBarsBox;
begin
  B := NewBox('none', 800, 80);
  AssertFalse('precondition: the bar is out of view', B.HShown);
  B.ScrollByDelta(100, 0);
  AssertEquals('ScrollByDelta moves the view', 100, B.ScrollX);
  AssertEquals('and the content with it', -100, FChild.Left);
  B.ScrollByDelta(100000, 0);
  AssertEquals('and it stops where the content ends', 800 - (300 - 2 * B.Frame), B.ScrollX);
  AssertEquals('the axis that fits stays put', 0, B.ScrollY);
end;

procedure TScrollBoxBarsTest.TheWheelScrollsAnAxisWithoutItsBar;
var
  B: TBarsBox;
begin
  B := NewBox('none', 100, 600);
  AssertFalse('precondition: the bar is out of view', B.VShown);
  B.Wheel(-120);
  AssertTrue('the wheel down moves the view down', B.ScrollY > 0);
  B.Wheel(120);
  AssertEquals('and up again', 0, B.ScrollY);
end;

procedure TScrollBoxBarsTest.TheWheelGoesSidewaysWhenOnlyThatOverflows;
var
  B: TBarsBox;
begin
  B := NewBox('none', 800, 80);
  AssertFalse('precondition: the bar is out of view', B.HShown);
  B.Wheel(-120);
  AssertTrue('nothing overflows downwards, so the wheel scrolls sideways', B.ScrollX > 0);
  AssertEquals('the vertical axis stays put', 0, B.ScrollY);
end;

procedure TScrollBoxBarsTest.TheWheelKeepsToTheVerticalAxisWhenOnlyItsBarIsOutOfView;
var
  B: TBarsBox;
begin
  { The wheel goes to the vertical axis whenever that overflows. Taking away its bar must not
    send the wheel sideways just because the horizontal bar is the one left in view. }
  B := NewBox('horizontal', 800, 600);
  AssertTrue('precondition: only the horizontal bar is in view', B.HShown and not B.VShown);
  B.Wheel(-120);
  AssertTrue('the wheel scrolls down', B.ScrollY > 0);
  AssertEquals('not sideways', 0, B.ScrollX);
end;

procedure TScrollBoxBarsTest.ScrollInViewReachesAChildDownAnAxisWithoutItsBar;
var
  B: TBarsBox;
  target: TTyPanel;
begin
  B := NewBox('none', 100, 50);
  target := TTyPanel.Create(B);
  target.Parent := B;
  target.SetBounds(0, 500, 100, 40);
  B.UpdateScrollRange;
  AssertFalse('precondition: the bar is out of view', B.VShown);
  B.ScrollInView(target);
  AssertEquals('the view moves just far enough to show the whole child',
    540 - B.ClientHeight, B.ScrollY);
  AssertEquals('whose bottom edge is now the viewport''s', B.ClientHeight,
    target.Top + target.Height);
end;

procedure TScrollBoxBarsTest.TheBarInViewFollowsAScrollOnBothAxes;
var
  B: TBarsBox;
begin
  B := NewBox('vertical', 800, 600);
  AssertTrue('precondition: only the vertical bar is in view', B.VShown and not B.HShown);
  B.ScrollByDelta(50, 70);
  AssertEquals('the view moved sideways', 50, B.ScrollX);
  AssertEquals('and down', 70, B.ScrollY);
  AssertEquals('the thumb in view is where the view is', 70, B.VBar.Position);
  AssertEquals('and the bar is still on its gutter', 300 - B.Frame,
    B.VBar.Left + B.VBar.Width);
end;

procedure TScrollBoxBarsTest.TheLayoutAreaGrowsToTheContentAlongAnAxisWithoutItsBar;
var
  B: TBarsBox;
  area: TRect;
begin
  { Without this an alTop column past the fold is stacked onto the last row in view: DoAlign
    clamps to the bottom of this rect. }
  B := NewBox('none', 100, 600);
  AssertFalse('precondition: the bar is out of view', B.VShown);
  area := B.ChildArea;
  AssertEquals('down the axis that scrolls: the content', 600, area.Bottom - area.Top);
  AssertEquals('across the one that does not: the viewport, less the frame',
    300 - 2 * B.Frame, area.Right - area.Left);

  B := NewBox('none', 800, 80);
  area := B.ChildArea;
  AssertEquals('along the axis that scrolls: the content', 800, area.Right - area.Left);
  AssertEquals('down the one that does not: the viewport, less the frame',
    200 - 2 * B.Frame, area.Bottom - area.Top);
end;

{ --- a box without the token -------------------------------------------------------- }

procedure TScrollBoxBarsTest.WithNoTokenTheHorizontalAxisScrollsAsItDid;
var
  B: TBarsBox;
  area: TRect;
begin
  { What reads "this axis scrolls" used to read the bar's Visible. test.scrollbox pins that
    for the vertical axis of a box with no token; this is the horizontal one. }
  B := NewBox('', 800, 80);
  AssertTrue('precondition: only the horizontal bar is in view', B.HShown and not B.VShown);
  area := B.ChildArea;
  AssertEquals('the layout area grows to the content along it', 800, area.Right - area.Left);
  B.Wheel(-120);
  AssertTrue('the wheel scrolls sideways, nothing overflowing downwards', B.ScrollX > 0);
  AssertEquals('and the thumb follows', B.ScrollX, B.HBar.Position);
end;

{ --- the layout pass ---------------------------------------------------------------- }

procedure TScrollBoxBarsTest.AnAxisThatStartsOrStopsScrollingOutOfViewAsksForALayoutPass;
var
  B: TBarsBox;
  n: Integer;
begin
  { A bar coming into view re-lays the children out by itself (its Visible changing does).
    With the bar out of view nothing does, and the layout area has changed all the same. }
  B := NewBox('none', 100, 100);
  FChild.Height := 600;
  n := B.Asked;
  B.UpdateScrollRange;
  AssertFalse('precondition: the bar stays out of view', B.VShown);
  AssertTrue('the axis starts to scroll: a pass is asked for', B.Asked > n);
  n := B.Asked;
  B.UpdateScrollRange;
  AssertEquals('nothing changed: nothing asked', n, B.Asked);
  FChild.Height := 100;
  n := B.Asked;
  B.UpdateScrollRange;
  AssertTrue('the axis stops scrolling: a pass is asked for', B.Asked > n);

  B := NewBox('none', 100, 100);
  FChild.Width := 800;
  n := B.Asked;
  B.UpdateScrollRange;
  AssertFalse('precondition: the horizontal bar stays out of view', B.HShown);
  AssertTrue('sideways too: a pass is asked for', B.Asked > n);
  n := B.Asked;
  B.UpdateScrollRange;
  AssertEquals('sideways, nothing changed: nothing asked', n, B.Asked);
  FChild.Width := 100;
  n := B.Asked;
  B.UpdateScrollRange;
  AssertTrue('sideways, the axis stops scrolling: a pass is asked for', B.Asked > n);
end;

procedure TScrollBoxBarsTest.ABarComingIntoViewIsItsOwnRequest;
var
  B: TBarsBox;
  n, byTheBox, byHand: Integer;
begin
  { The default box must not pay for a second pass each time a bar shows: the bar's Visible
    changing asks for one already. How many requests that makes is the LCL's business, so it
    is counted here by showing the same bar by hand, not written down. }
  B := NewBox('', 100, 100);
  FChild.Height := 600;
  n := B.Asked;
  B.UpdateScrollRange;
  byTheBox := B.Asked - n;
  AssertTrue('precondition: the bar came into view', B.VShown);

  B.VBar.Visible := False;
  n := B.Asked;
  B.VBar.Visible := True;
  byHand := B.Asked - n;
  AssertTrue('precondition: a bar coming into view asks for a pass by itself', byHand > 0);
  AssertEquals('and the box asked for nothing beyond that', byHand, byTheBox);
end;

procedure TScrollBoxBarsTest.TheBoxMeasuresAgainAfterThePassItAskedFor;
var
  B: TBarsBox;
begin
  { The pass can change the content (rows that were stacked at the fold spread out), so the
    range has to be taken again after it. The content here does not change by itself -- the
    box getting lower is what starts the axis scrolling -- so only the pass can be the reason
    for the second measure. }
  B := NewBox('none', 100, 150);
  AssertEquals('precondition: the content as given', 150, B.ContentHeight);
  B.SpreadOnPass := FChild;
  B.SpreadTo := 900;
  B.Height := 100;
  AssertNull('precondition: a pass ran once the layout area had room', B.SpreadOnPass);
  AssertEquals('the range is taken from what the pass left', 900, B.ContentHeight);
end;

initialization
  RegisterTest(TScrollBoxBarsTest);
end.
