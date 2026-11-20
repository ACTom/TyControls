unit test.multitrackbar.frame;
{$mode objfpc}{$H+}

{ The multi-thumb bars lay their parts out where TTyTrackBar does (#236, #237): inside the
  focus ring and the style's padding, with the thumb the three --track-thumb- tokens describe.

  As in test.multitrackbar, the reference is a TTyTrackBar of the same size, theme and
  StyleOverride: a thumb at V is the track bar's thumb at Position = V, a press lands where
  that thumb is drawn, and a bar with one thumb draws the very pixels the track bar does. The
  theme here has a focus ring, and both bars carry a padding that differs on all four edges. }

interface

uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.TrackBar,
  tyControls.MultiTrackBar, test.multitrackbar;

type
  TTyMultiTrackFrameTest = class(TMultiTrackInputBase)
  private
    { Both bars to one orientation and direction, 200 long and 48 across. }
    procedure Lay(AOri: TTyTrackOrientation; ARev: Boolean);
    procedure Both(const AOverride: string);
    function Where(AOri: TTyTrackOrientation; ARev: Boolean): string;
    { How many pixels of the bar's picture differ from the reference's. }
    function Differing: Integer;
    { The main-axis extent of the pixels of colour (R, G, B) in the bar's picture; (0, 0) when
      there are none. }
    function InkSpan(R, G, B: Byte): TPoint;
    function MainOf(const P: TPoint): Integer;
  protected
    procedure SetUp; override;
  published
    procedure TestOneThumbDrawsWhatTheTrackBarDrawsInsideItsFrame;
    procedure TestThumbRectsAreTheTrackBarsInsideTheFrame;
    procedure TestAPressLandsWhereTheThumbIsDrawn;
    procedure TestADragFollowsThePointerInsideTheFrame;
    procedure TestSegmentsRunBetweenTheThumbsCentres;
    procedure TestTheHintsGapStopsAtTheFrame;
    procedure TestTheThumbTokensReachEveryThumb;
    procedure TestOneThumbWithTheTokensDrawsWhatTheTrackBarDraws;
    procedure TestARadiusOfNoughtSquaresTheThumbs;
    procedure TestAThemeWithNoFrameLaysTheBarOutAsBefore;
  end;

implementation

const
  { test.multitrackbar's paint theme with a focus ring. The ring is orange: the pictures
    start magenta. }
  CFrameCss =
    'TyTrackBar { color: #000000; border-width: 0px; border-radius: 0px; padding: 0px; }' +
    'TyTrackBar:focus { outline: 2px #FF8000; }' +
    'TyTrackGroove { background: #606060; border-radius: 0px; }' +
    'TyTrackSegment { border-radius: 0px; }' +
    'TyTrackSegment.go { background: #00C000; }' +
    'TyTrackThumb { background: #3B82F6; border-radius: 0px; }';
  CRoundCss =
    'TyTrackBar { color: #000000; border-width: 0px; border-radius: 0px; padding: 0px; }' +
    'TyTrackBar:focus { outline: 2px #FF8000; }' +
    'TyTrackGroove { background: #606060; border-radius: 0px; }' +
    'TyTrackThumb { background: #3B82F6; border-radius: 99px; }';
  CNoFrameCss =
    'TyTrackBar { color: #000000; border-width: 0px; border-radius: 0px; padding: 0px; }' +
    'TyTrackGroove { background: #606060; border-radius: 0px; }' +
    'TyTrackThumb { background: #3B82F6; border-radius: 0px; }';
  CPad = 'padding: 3px 9px 5px 6px;';     // top right bottom left
  CTokens = ' --track-thumb-length: 20px; --track-thumb-thickness: 10px; --track-thumb-radius: 5px;';
  CRing = 2;
  CAlong = 200;
  CAcross = 48;

procedure TTyMultiTrackFrameTest.SetUp;
begin
  inherited SetUp;
  FCtl.LoadThemeCss(CFrameCss);
  Both(CPad);
  Lay(toHorizontal, False);
end;

procedure TTyMultiTrackFrameTest.Lay(AOri: TTyTrackOrientation; ARev: Boolean);
begin
  Configure(AOri, ARev);
  if AOri = toVertical then
  begin
    FBar.SetBounds(0, 0, CAcross, CAlong);
    FRef.SetBounds(0, 0, CAcross, CAlong);
  end
  else
  begin
    FBar.SetBounds(0, 0, CAlong, CAcross);
    FRef.SetBounds(0, 0, CAlong, CAcross);
  end;
end;

procedure TTyMultiTrackFrameTest.Both(const AOverride: string);
begin
  FBar.StyleOverride := AOverride;
  FRef.StyleOverride := AOverride;
end;

function TTyMultiTrackFrameTest.Where(AOri: TTyTrackOrientation; ARev: Boolean): string;
begin
  Result := Format('ori=%d rev=%s', [Ord(AOri), BoolToStr(ARev, True)]);
end;

function TTyMultiTrackFrameTest.Differing: Integer;
var
  a, b: TBGRABitmap;
  x, y: Integer;
begin
  Result := 0;
  { Twice: the readout's strip is measured by the first paint. }
  Shot(False).Free;
  Shot(True).Free;
  a := Shot(False);
  b := Shot(True);
  try
    for y := 0 to H - 1 do
      for x := 0 to W - 1 do
        if a.GetPixel(x, y) <> b.GetPixel(x, y) then Inc(Result);
  finally
    a.Free;
    b.Free;
  end;
end;

function TTyMultiTrackFrameTest.InkSpan(R, G, B: Byte): TPoint;
var
  img: TBGRABitmap;
  x, y, m, lo, hi: Integer;
  p: TBGRAPixel;
begin
  lo := MaxInt;
  hi := -1;
  img := Shot(False);
  try
    for y := 0 to H - 1 do
      for x := 0 to W - 1 do
      begin
        p := img.GetPixel(x, y);
        if (p.red <> R) or (p.green <> G) or (p.blue <> B) then Continue;
        if FBar.Orientation = toVertical then m := y else m := x;
        if m < lo then lo := m;
        if m + 1 > hi then hi := m + 1;
      end;
  finally
    img.Free;
  end;
  if hi < 0 then Result := Point(0, 0) else Result := Point(lo, hi);
end;

function TTyMultiTrackFrameTest.MainOf(const P: TPoint): Integer;
begin
  if FBar.Orientation = toVertical then Result := P.Y else Result := P.X;
end;

{ The whole picture: the ring, the groove inside it and the padding, the thumb, the ticks on
  both sides, their labels and the readout. And with it where a press lands and what AutoSize
  asks for. }
procedure TTyMultiTrackFrameTest.TestOneThumbDrawsWhatTheTrackBarDrawsInsideItsFrame;
var
  ori: TTyTrackOrientation;
  rev, focus: Boolean;
  ra, rb: TRect;
  aw, ah, bw, bh: Integer;
  w0: string;
begin
  FBar.Put([30]);
  FRef.Position := 30;
  FBar.Frequency := 10;
  FRef.Frequency := 10;
  FBar.TickMarks := ttmBoth;
  FRef.TickMarks := ttmBoth;
  FBar.ShowValue := True;
  FRef.ShowValue := True;
  for ori := toHorizontal to toVertical do
    for rev := False to True do
      for focus := False to True do
      begin
        Lay(ori, rev);
        FBar.FakeFocus := focus;
        FRef.FakeFocus := focus;
        w0 := Where(ori, rev) + ' focus=' + BoolToStr(focus, True);
        AssertEquals(w0 + ': pixels that differ from TTyTrackBar', 0, Differing);
        ra := FBar.ThumbRect(0);
        rb := FRef.ThumbRect;
        AssertEquals(w0 + ': thumb Left', rb.Left, ra.Left);
        AssertEquals(w0 + ': thumb Top', rb.Top, ra.Top);
        AssertEquals(w0 + ': thumb Right', rb.Right, ra.Right);
        AssertEquals(w0 + ': thumb Bottom', rb.Bottom, ra.Bottom);
        FBar.PreferredSize(aw, ah);
        FRef.PreferredSize(bw, bh);
        AssertEquals(w0 + ': preferred width', bw, aw);
        AssertEquals(w0 + ': preferred height', bh, ah);
      end;
end;

procedure TTyMultiTrackFrameTest.TestThumbRectsAreTheTrackBarsInsideTheFrame;
const
  Vals: array[0..4] of Integer = (0, 1, 37, 99, 100);
var
  ori: TTyTrackOrientation;
  rev: Boolean;
  i: Integer;
  ra, rb: TRect;
  w0: string;
begin
  for ori := toHorizontal to toVertical do
    for rev := False to True do
    begin
      Lay(ori, rev);
      for i := 0 to High(Vals) do
      begin
        w0 := Format('%s v=%d', [Where(ori, rev), Vals[i]]);
        FBar.Put([Vals[i]]);
        ra := FBar.ThumbRect(0);
        rb := RefThumbRect(Vals[i]);
        AssertEquals(w0 + ': Left', rb.Left, ra.Left);
        AssertEquals(w0 + ': Top', rb.Top, ra.Top);
        AssertEquals(w0 + ': Right', rb.Right, ra.Right);
        AssertEquals(w0 + ': Bottom', rb.Bottom, ra.Bottom);
      end;
    end;
  { And the frame is really there: the thumb at Min starts after the ring and the padding. }
  Lay(toHorizontal, False);
  FBar.Put([0]);
  AssertEquals('the ring and the left padding', CRing + 6, FBar.ThumbRect(0).Left);
  FBar.Put([100]);
  AssertEquals('the right padding and the ring', CAlong - CRing - 9, FBar.ThumbRect(0).Right);
end;

procedure TTyMultiTrackFrameTest.TestAPressLandsWhereTheThumbIsDrawn;
var
  ori: TTyTrackOrientation;
  rev: Boolean;
  p: TPoint;
  v: Integer;
  w0: string;
begin
  { A thumb longer than the default one: where its middle is counts in every answer. }
  Both(CPad + ' --track-thumb-length: 20px;');
  for ori := toHorizontal to toVertical do
    for rev := False to True do
    begin
      Lay(ori, rev);
      w0 := Where(ori, rev);
      for v := 0 to 10 do
      begin
        p := At(v * 10);
        AssertEquals(Format('%s: the value under the reference''s thumb at %d', [w0, v * 10]),
          v * 10, FBar.ValueAtPoint(p.X, p.Y));
      end;
      { A press on the groove brings the nearest thumb there. }
      FBar.Put([20, 80]);
      p := At(60);
      FBar.Press(p.X, p.Y);
      FBar.Release(p.X, p.Y);
      AssertEquals(w0 + ': the nearer thumb came to the press', '20,60', Values);
      { A press on a thumb takes that thumb and moves nothing. }
      p := At(20);
      FBar.Press(p.X, p.Y);
      FBar.Release(p.X, p.Y);
      AssertEquals(w0 + ': a press on a thumb moves nothing', '20,60', Values);
      AssertEquals(w0 + ': and the thumb under the point is that one', 0, FBar.ThumbAtPoint(p.X, p.Y));
    end;
end;

procedure TTyMultiTrackFrameTest.TestADragFollowsThePointerInsideTheFrame;
var
  ori: TTyTrackOrientation;
  rev: Boolean;
  p, q: TPoint;
  w0: string;
begin
  Both(CPad + ' --track-thumb-length: 20px;');
  for ori := toHorizontal to toVertical do
    for rev := False to True do
    begin
      Lay(ori, rev);
      w0 := Where(ori, rev);
      FBar.Put([20, 80]);
      p := At(80);
      q := At(45);
      FBar.Press(p.X, p.Y);
      FBar.Drag(q.X, q.Y);
      FBar.Release(q.X, q.Y);
      AssertEquals(w0 + ': the thumb is where the pointer left it', '20,45', Values);
    end;
end;

procedure TTyMultiTrackFrameTest.TestSegmentsRunBetweenTheThumbsCentres;
var
  ori: TTyTrackOrientation;
  rev: Boolean;
  lo, hi, a, b, t: Integer;
  ink: TPoint;
  r20, r80: TRect;
  w0: string;
begin
  { With a thumb longer than the default one: the centres are those of the thumbs drawn. }
  Both(CPad + ' --track-thumb-length: 20px;');
  SetLength(FBar.SegKey, 3);
  SetLength(FBar.SegCls, 3);
  FBar.SegKey[1] := 'TyTrackSegment';
  FBar.SegCls[1] := 'go';
  for ori := toHorizontal to toVertical do
    for rev := False to True do
    begin
      Lay(ori, rev);
      w0 := Where(ori, rev);
      FBar.Put([20, 80]);
      a := RefCentre(20);
      b := RefCentre(80);
      if a > b then begin t := a; a := b; b := t; end;
      AssertTrue(w0 + ': the span is there', FBar.SegmentSpan(1, 96, lo, hi));
      AssertEquals(w0 + ': it starts at one thumb''s centre, in client px', a, lo);
      AssertEquals(w0 + ': and ends at the other''s', b, hi);
      { Drawn: what shows of it is the stretch between the two thumbs. }
      r20 := RefThumbRect(20);
      r80 := RefThumbRect(80);
      if ori = toVertical then
      begin
        a := r20.Bottom; b := r80.Top;
        if r80.Bottom <= r20.Top then begin a := r80.Bottom; b := r20.Top; end;
      end
      else
      begin
        a := r20.Right; b := r80.Left;
        if r80.Right <= r20.Left then begin a := r80.Right; b := r20.Left; end;
      end;
      ink := InkSpan($00, $C0, $00);
      AssertEquals(w0 + ': the fill starts where the first thumb ends', a, ink.X);
      AssertEquals(w0 + ': and ends where the second begins', b, ink.Y);
    end;
end;

{ Between two thumbs, and outside the outermost, the hint asks again once the pointer reaches
  a thumb. At the two ends of the track that stretch stops at the frame. }
procedure TTyMultiTrackFrameTest.TestTheHintsGapStopsAtTheFrame;
var
  r: TRect;
  p: TPoint;
begin
  FBar.Put([20, 80]);
  SetLength(FBar.Hints, 2);
  FBar.Hints[0] := 'low';
  FBar.Hints[1] := 'high';
  p := At(5);
  FBar.HintAt(p.X, p.Y, r);
  AssertEquals('before the first thumb: from the start of the track', RefThumbRect(0).Left, r.Left);
  AssertEquals('to that thumb', FBar.ThumbRect(0).Left, r.Right);
  p := At(50);
  FBar.HintAt(p.X, p.Y, r);
  AssertEquals('between them: from the first', FBar.ThumbRect(0).Right, r.Left);
  AssertEquals('to the second', FBar.ThumbRect(1).Left, r.Right);
  p := At(95);
  FBar.HintAt(p.X, p.Y, r);
  AssertEquals('after the last thumb: from it', FBar.ThumbRect(1).Right, r.Left);
  AssertEquals('to the end of the track', RefThumbRect(100).Right, r.Right);
end;

procedure TTyMultiTrackFrameTest.TestTheThumbTokensReachEveryThumb;
var
  i: Integer;
  r: TRect;
  ink: TPoint;
begin
  { The length alone: square corners, so a thumb's rectangle is exactly its pixels. }
  Both(CPad + ' --track-thumb-length: 20px;');
  FBar.Put([10, 50, 90]);
  for i := 0 to 2 do
  begin
    r := FBar.ThumbRect(i);
    AssertEquals(Format('thumb %d is as long as the token says', [i]), 20, r.Right - r.Left);
  end;
  AssertEquals('and stands where the track bar''s would', RefThumbRect(50).Left, FBar.ThumbRect(1).Left);
  { Drawn: from the first thumb's start to the last one's end. }
  ink := InkSpan($3B, $82, $F6);
  AssertEquals('the first thumb is drawn from its hit rectangle''s start', FBar.ThumbRect(0).Left, ink.X);
  AssertEquals('the last one to its end', FBar.ThumbRect(2).Right, ink.Y);
end;

{ Length, thickness and corner radius at once, on the whole picture. }
procedure TTyMultiTrackFrameTest.TestOneThumbWithTheTokensDrawsWhatTheTrackBarDraws;
var
  ori: TTyTrackOrientation;
  rev: Boolean;
  aw, ah, bw, bh: Integer;
  plain: Integer;
begin
  FBar.Put([30]);
  FRef.Position := 30;
  for ori := toHorizontal to toVertical do
    for rev := False to True do
    begin
      Lay(ori, rev);
      Both(CPad);
      FBar.PreferredSize(aw, ah);
      plain := aw + ah;
      Both(CPad + CTokens);
      AssertEquals(Where(ori, rev) + ': pixels that differ from TTyTrackBar', 0, Differing);
      FBar.PreferredSize(aw, ah);
      FRef.PreferredSize(bw, bh);
      AssertEquals(Where(ori, rev) + ': preferred width', bw, aw);
      AssertEquals(Where(ori, rev) + ': preferred height', bh, ah);
      AssertTrue(Where(ori, rev) + ': a thinner thumb asks for less', aw + ah < plain);
    end;
end;

{ 0 is a radius like any other: on a theme of round thumbs it squares them. }
procedure TTyMultiTrackFrameTest.TestARadiusOfNoughtSquaresTheThumbs;
var
  round, square: TBGRABitmap;
  x, y, moved: Integer;
begin
  FCtl.LoadThemeCss(CRoundCss);
  FBar.Put([30]);
  FRef.Position := 30;
  Both(CPad);
  AssertEquals('setup: round thumbs, as the track bar draws them', 0, Differing);
  round := Shot(False);
  Both(CPad + ' --track-thumb-radius: 0px;');
  square := Shot(False);
  try
    moved := 0;
    for y := 0 to H - 1 do
      for x := 0 to W - 1 do
        if round.GetPixel(x, y) <> square.GetPixel(x, y) then Inc(moved);
    AssertTrue('the corners are filled in', moved > 0);
  finally
    round.Free;
    square.Free;
  end;
  AssertEquals('and the picture is the track bar''s', 0, Differing);
end;

{ No ring, no border, no padding: nothing is kept, and the track is the whole control. }
procedure TTyMultiTrackFrameTest.TestAThemeWithNoFrameLaysTheBarOutAsBefore;
var
  r: TRect;
begin
  FCtl.LoadThemeCss(CNoFrameCss);
  Both('');
  Lay(toHorizontal, False);
  FBar.Put([0]);
  r := FBar.ThumbRect(0);
  AssertEquals('the thumb at Min starts at the edge', 0, r.Left);
  AssertEquals('and its hit rectangle is the whole control across', CAcross, r.Bottom - r.Top);
  FBar.Put([100]);
  AssertEquals('the thumb at Max ends at the far edge', CAlong, FBar.ThumbRect(0).Right);
end;

initialization
  RegisterTest(TTyMultiTrackFrameTest);
end.
