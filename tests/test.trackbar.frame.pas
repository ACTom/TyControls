unit test.trackbar.frame;
{$mode objfpc}{$H+}

{ Where a track bar lays its parts out, and what its thumb looks like:

    #236  the groove, the thumb, the ticks and the value stay clear of the focus ring, and
          the style's padding moves them in;
    #237  --track-thumb-length, --track-thumb-thickness and --track-thumb-radius.

  The theme below gives every part a colour of its own, so a picture can be read part by
  part: the ring magenta, the groove green, the thumb red, the ticks and the value blue. }

interface

uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.TrackBar;

type
  TPartInk = (piRing, piGroove, piThumb, piBlue);

  TFrameBar = class(TTyTrackBar)
  public
    Focus: Boolean;
    function CurrentStates: TTyStateSet; override;
    procedure Shot(ACanvas: TCanvas; const R: TRect; APPI: Integer);
    function PrefCross: Integer;
  end;

  TTrackBarFrameTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    function NewBar(AVertical: Boolean = False; AWithRing: Boolean = True): TFrameBar;
    function NewBarOn(const ACss: string; AVertical: Boolean = False): TFrameBar;
    function Picture(B: TFrameBar): TBGRABitmap;
    function IsInk(const P: TBGRAPixel; AInk: TPartInk): Boolean;
    function Box(B: TFrameBar; AInk: TPartInk; AFromX: Integer = 0): TRect;
    function RingHoles(B: TFrameBar; AWidth: Integer = 2): Integer;
    function BoxText(const R: TRect): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { #236 }
    procedure TheRingIsWholeAtEveryPosition;
    procedure TheRingIsWholeOnAVerticalBar;
    procedure TheTrackDoesNotMoveWhenTheBarGetsTheFocus;
    procedure ABarWithNoRingKeepsItsWholeWidth;
    procedure PaddingMovesThePartsIn;
    procedure TheValueHasRoomAfterIt;
    procedure AClickLandsWhereTheThumbIsDrawn;
    procedure AClickLandsWhereTheThumbIsDrawnOnAVerticalBar;
    procedure AutoSizeAsksForTheFrameAsWell;
    procedure ABarTooSmallForItsFrameStillDrawsItsThumb;
    procedure ABorderIsKeptClearToo;
    procedure TheWiderOfTheBorderAndTheRingIsKept;
    procedure ARingSetInFromTheEdgeIsKeptClear;
    procedure TheValueOfAVerticalBarIsAboveTheRing;
    procedure ATickStandsAtTheMiddleOfTheThumb;
    { #237 }
    procedure TheThumbIsTwelveLongByDefault;
    procedure TheLengthTokenSetsTheThumbsLength;
    procedure TheThumbStillTravelsFromEndToEnd;
    procedure TheThicknessTokenSetsTheThumbsThickness;
    procedure TheThicknessIsHeldToTheBand;
    procedure AThumbAsLongAsItIsThickIsRound;
    procedure TheRadiusTokenSquaresTheThumb;
    procedure TheTokensTurnWithAVerticalBar;
    procedure TheThemeSetsTheThumbForEveryBarAndABarForItself;
    procedure AutoSizeFollowsTheThumbsThickness;
  end;

implementation

const
  cRing = 2;
  cThemeRing =
    'TyTrackBar { color: #0000FF; padding: 0px; border-width: 0px; }' +
    'TyTrackBar:focus { outline: 2px #FF00FF; }' +
    'TyTrackGroove { background: #00FF00; border-radius: 0px; }' +
    'TyTrackThumb { background: #FF0000; border-radius: 99px; }';
  cThemeNoRing =
    'TyTrackBar { color: #0000FF; padding: 0px; border-width: 0px; }' +
    'TyTrackGroove { background: #00FF00; border-radius: 0px; }' +
    'TyTrackThumb { background: #FF0000; border-radius: 99px; }';

{ TFrameBar }

function TFrameBar.CurrentStates: TTyStateSet;
begin
  Result := inherited CurrentStates;
  if Focus then Include(Result, tysFocused);
end;

procedure TFrameBar.Shot(ACanvas: TCanvas; const R: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, R, APPI);
end;

function TFrameBar.PrefCross: Integer;
var
  w, h: Integer;
begin
  w := 0;
  h := 0;
  CalculatePreferredSize(w, h, True);
  if Orientation = toVertical then Result := w else Result := h;
end;

{ fixture }

procedure TTrackBarFrameTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(-4000, -4000, 600, 400);
end;

procedure TTrackBarFrameTest.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

function TTrackBarFrameTest.NewBar(AVertical, AWithRing: Boolean): TFrameBar;
begin
  if AWithRing then Result := NewBarOn(cThemeRing, AVertical)
  else Result := NewBarOn(cThemeNoRing, AVertical);
end;

function TTrackBarFrameTest.NewBarOn(const ACss: string; AVertical: Boolean): TFrameBar;
begin
  FCtl.LoadThemeCss(ACss);
  Result := TFrameBar.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.AnimationsEnabled := False;
  if AVertical then
  begin
    Result.Orientation := toVertical;
    Result.SetBounds(0, 0, 40, 200);
  end
  else
    Result.SetBounds(0, 0, 200, 40);
end;

{ The bar painted on light grey. Twice: the value strip is measured by the first paint. }
function TTrackBarFrameTest.Picture(B: TFrameBar): TBGRABitmap;
var
  bmp: TBitmap;
  r: TRect;
begin
  r := Rect(0, 0, B.Width, B.Height);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(B.Width, B.Height);
    bmp.Canvas.Brush.Color := TColor($F0F0F0);
    bmp.Canvas.FillRect(r);
    B.Shot(bmp.Canvas, r, 96);
    bmp.Canvas.FillRect(r);
    B.Shot(bmp.Canvas, r, 96);
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
  end;
end;

function TTrackBarFrameTest.IsInk(const P: TBGRAPixel; AInk: TPartInk): Boolean;
begin
  case AInk of
    piRing:   Result := (P.red > 200) and (P.green < 60) and (P.blue > 200);
    piGroove: Result := (P.red < 60) and (P.green > 200) and (P.blue < 60);
    piThumb:  Result := (P.red > 200) and (P.green < 60) and (P.blue < 60);
  else
    Result := (P.red < 60) and (P.green < 60) and (P.blue > 200);
  end;
end;

{ The box of one part's ink, looked for from column AFromX on. Empty when there is none. }
function TTrackBarFrameTest.Box(B: TFrameBar; AInk: TPartInk; AFromX: Integer): TRect;
var
  img: TBGRABitmap;
  x, y: Integer;
begin
  Result := Rect(MaxInt, MaxInt, -1, -1);
  img := Picture(B);
  try
    for y := 0 to img.Height - 1 do
      for x := AFromX to img.Width - 1 do
        if IsInk(img.GetPixel(x, y), AInk) then
        begin
          if x < Result.Left then Result.Left := x;
          if y < Result.Top then Result.Top := y;
          if x + 1 > Result.Right then Result.Right := x + 1;
          if y + 1 > Result.Bottom then Result.Bottom := y + 1;
        end;
  finally
    img.Free;
  end;
  if Result.Right < 0 then Result := Rect(0, 0, 0, 0);
end;

{ How many pixels of the two outermost rows and columns are NOT the ring's colour. }
function TTrackBarFrameTest.RingHoles(B: TFrameBar; AWidth: Integer): Integer;
var
  img: TBGRABitmap;
  x, y: Integer;
begin
  Result := 0;
  img := Picture(B);
  try
    for y := 0 to img.Height - 1 do
      for x := 0 to img.Width - 1 do
        if (x < AWidth) or (y < AWidth) or (x >= img.Width - AWidth) or (y >= img.Height - AWidth) then
          if not IsInk(img.GetPixel(x, y), piRing) then Inc(Result);
  finally
    img.Free;
  end;
end;

function TTrackBarFrameTest.BoxText(const R: TRect): string;
begin
  Result := Format('%d,%d-%d,%d', [R.Left, R.Top, R.Right, R.Bottom]);
end;

{ ---- #236: the parts and the frame ---- }

procedure TTrackBarFrameTest.TheRingIsWholeAtEveryPosition;
var
  b: TFrameBar;
begin
  b := NewBar;
  b.ShowValue := True;
  b.TickMarks := ttmBoth;      // ticks along the top edge as well as the bottom one
  b.Focus := True;
  b.Position := 0;
  AssertEquals('at Min, where the thumb sat on the ring''s left side', 0, RingHoles(b));
  b.Position := 36;
  AssertEquals('in the middle: the thumb above and below, the ticks, the groove''s end', 0, RingHoles(b));
  b.Position := 100;
  AssertEquals('at Max, with the largest value beside it', 0, RingHoles(b));
  b.Focus := False;
  AssertTrue('setup: without the focus there is no ring to see', RingHoles(b) > 100);
end;

procedure TTrackBarFrameTest.TheRingIsWholeOnAVerticalBar;
var
  b: TFrameBar;
begin
  b := NewBar(True);
  b.ShowValue := True;
  b.TickMarks := ttmBoth;
  b.Focus := True;
  b.Position := 0;
  AssertEquals('at Min', 0, RingHoles(b));
  b.Position := 100;
  AssertEquals('at Max', 0, RingHoles(b));
end;

{ The room for the ring is kept whether the bar has the focus or not: a track that jumped
  when it was focused would be worse than a ring that is drawn over. }
procedure TTrackBarFrameTest.TheTrackDoesNotMoveWhenTheBarGetsTheFocus;
var
  b: TFrameBar;
  thumb, groove: TRect;
begin
  b := NewBar;
  b.Position := 40;
  thumb := Box(b, piThumb);
  groove := Box(b, piGroove);
  AssertTrue('setup: a thumb was drawn', thumb.Right > thumb.Left);
  b.Focus := True;
  AssertEquals('the thumb is where it was', BoxText(thumb), BoxText(Box(b, piThumb)));
  AssertEquals('and so is the groove', BoxText(groove), BoxText(Box(b, piGroove)));
  AssertEquals('the groove starts inside the ring', cRing, groove.Left);
end;

{ No ring and no border in the theme: nothing is kept, and the bar is laid out as it always
  was. }
procedure TTrackBarFrameTest.ABarWithNoRingKeepsItsWholeWidth;
var
  b: TFrameBar;
  thumb: TRect;
begin
  b := NewBar(False, False);
  b.TickStyle := ttsNone;
  b.Position := 0;
  thumb := Box(b, piThumb);
  AssertEquals('the thumb starts at the edge', 0, thumb.Left);
  AssertEquals('and is as tall as the bar', b.Height, thumb.Bottom - thumb.Top);
  AssertEquals('the groove runs on to the far edge', 200, Box(b, piGroove).Right);
  AssertEquals('ThumbRect agrees', 0, b.ThumbRect.Left);
  b.Position := 100;
  AssertEquals('and the groove starts at the near one', 0, Box(b, piGroove).Left);
  AssertEquals('with the thumb at the far one', 200, Box(b, piThumb).Right);
end;

procedure TTrackBarFrameTest.PaddingMovesThePartsIn;
var
  b: TFrameBar;
  groove, thumb, ticks: TRect;
begin
  b := NewBar;
  b.StyleOverride := 'padding: 3px 10px 5px 7px;';   // top right bottom left
  b.Position := 50;                                  // the thumb off both ends of the groove
  groove := Box(b, piGroove);
  b.Position := 0;
  thumb := Box(b, piThumb);
  ticks := Box(b, piBlue);
  AssertEquals('the groove starts after the ring and the left padding', cRing + 7, groove.Left);
  AssertEquals('and ends before the right padding and the ring', 200 - cRing - 10, groove.Right);
  AssertEquals('the thumb starts with the groove', cRing + 7, thumb.Left);
  AssertEquals('and below the ring and the top padding', cRing + 3, thumb.Top);
  AssertEquals('the ticks end above the bottom padding and the ring', 40 - cRing - 5, ticks.Bottom);
end;

procedure TTrackBarFrameTest.TheValueHasRoomAfterIt;
var
  b: TFrameBar;
  groove, text: TRect;
begin
  b := NewBar;
  b.TickStyle := ttsNone;
  b.ShowValue := True;
  b.Focus := True;
  b.Max := 888;                // the widest value is the one shown: the strip is exactly full
  b.Position := 0;
  groove := Box(b, piGroove);  // the thumb is at the near end, so this is the track's far end
  b.Position := 888;
  text := Box(b, piBlue, groove.Right);
  AssertTrue('setup: the value was drawn', text.Right > text.Left);
  AssertTrue(Format('two px between the number and the ring (it ends at %d)', [text.Right]),
    text.Right <= 200 - cRing - 2);
  AssertTrue(Format('and still clear of the track (it starts at %d, the groove ends at %d)',
    [text.Left, groove.Right]), text.Left >= groove.Right + 3);
end;

{ The paint and the hit test are two pieces of code. A press on the middle of the thumb as it
  is DRAWN must leave the position alone -- with the parts moved in and the hit test not,
  every press would nudge it. }
procedure TTrackBarFrameTest.AClickLandsWhereTheThumbIsDrawn;
const
  Ps: array[0..4] of Integer = (0, 1, 36, 99, 100);
var
  b: TFrameBar;
  thumb: TRect;
  i: Integer;
begin
  b := NewBar;
  b.ShowValue := True;
  b.StyleOverride := 'padding: 0px 9px;';
  for i := 0 to High(Ps) do
  begin
    b.Position := Ps[i];
    thumb := Box(b, piThumb);
    AssertEquals(Format('at %d the hit rect is the drawn thumb, left', [Ps[i]]), thumb.Left, b.ThumbRect.Left);
    AssertEquals(Format('at %d, right', [Ps[i]]), thumb.Right, b.ThumbRect.Right);
    b.DragTo((thumb.Left + thumb.Right) div 2);
    AssertEquals(Format('a press on the middle of the thumb at %d', [Ps[i]]), Ps[i], b.Position);
  end;
  b.DragTo(0);
  AssertEquals('a press on the ring at the left is Min', 0, b.Position);
  b.DragTo(199);
  AssertEquals('a press at the far right is Max', 100, b.Position);
end;

procedure TTrackBarFrameTest.AClickLandsWhereTheThumbIsDrawnOnAVerticalBar;
const
  Ps: array[0..2] of Integer = (0, 36, 100);
var
  b: TFrameBar;
  thumb: TRect;
  i: Integer;
begin
  b := NewBar(True);
  b.ShowValue := True;
  b.StyleOverride := 'padding: 6px 0px 11px 0px;';
  for i := 0 to High(Ps) do
  begin
    b.Position := Ps[i];
    thumb := Box(b, piThumb);
    AssertEquals(Format('at %d the hit rect is the drawn thumb, top', [Ps[i]]), thumb.Top, b.ThumbRect.Top);
    AssertEquals(Format('at %d, bottom', [Ps[i]]), thumb.Bottom, b.ThumbRect.Bottom);
    b.DragTo((thumb.Top + thumb.Bottom) div 2);
    AssertEquals(Format('a press on the middle of the thumb at %d', [Ps[i]]), Ps[i], b.Position);
  end;
end;

procedure TTrackBarFrameTest.AutoSizeAsksForTheFrameAsWell;
var
  plain, ringed: TFrameBar;
  bare: Integer;
begin
  plain := NewBar(False, False);
  bare := plain.PrefCross;
  ringed := NewBar(False, True);
  AssertEquals('the ring above and below', bare + 2 * cRing, ringed.PrefCross);
  ringed.StyleOverride := 'padding: 3px 0px 5px 0px;';
  AssertEquals('and the padding', bare + 2 * cRing + 8, ringed.PrefCross);
  ringed.Orientation := toVertical;
  ringed.StyleOverride := 'padding: 0px 4px 0px 6px;';
  AssertEquals('across a vertical bar it is left and right', bare + 2 * cRing + 10, ringed.PrefCross);
end;

procedure TTrackBarFrameTest.ABarTooSmallForItsFrameStillDrawsItsThumb;
var
  b: TFrameBar;
  thumb: TRect;
begin
  b := NewBar;
  b.TickStyle := ttsNone;
  b.Position := 0;
  b.StyleOverride := 'padding: 30px 0px;';   // more padding than the bar is tall
  thumb := Box(b, piThumb);
  AssertEquals('too low for its frame: the thumb has the whole height', BoxText(Rect(cRing, 0, cRing + 12, 40)),
    BoxText(thumb));
  b.StyleOverride := 'padding: 0px 150px;';  // and more than it is wide
  thumb := Box(b, piThumb);
  AssertEquals('too narrow for it: the track has the whole width', BoxText(Rect(0, cRing, 12, 40 - cRing)),
    BoxText(thumb));
  AssertEquals('and the hit rect agrees', 0, b.ThumbRect.Left);
end;

{ The ticks are measured along the SAME track as the thumb: the tick of a value stands where
  the middle of the thumb is when the bar is at that value. }
procedure TTrackBarFrameTest.ATickStandsAtTheMiddleOfTheThumb;
var
  b: TFrameBar;
  thumb, tick: TRect;
begin
  b := NewBar;
  b.TickStyle := ttsManual;
  b.SetTick(30);
  b.Position := 30;
  b.StyleOverride := 'padding: 0px 0px 0px 25px;';
  thumb := Box(b, piThumb);
  tick := Box(b, piBlue);
  AssertEquals('setup: one tick, one px wide', 1, tick.Right - tick.Left);
  AssertEquals('under the middle of the thumb', thumb.Left + 6, tick.Left);

  b := NewBar(True);
  b.TickStyle := ttsManual;
  b.SetTick(30);
  b.Position := 30;
  b.StyleOverride := 'padding: 25px 0px 0px 0px;';
  thumb := Box(b, piThumb);
  tick := Box(b, piBlue);
  AssertEquals('setup: one tick, one px high', 1, tick.Bottom - tick.Top);
  AssertEquals('beside the middle of the thumb', thumb.Top + 6, tick.Top);
end;

{ A theme that frames the bar with a BORDER instead of a focus ring: the same room, for the
  border. }
procedure TTrackBarFrameTest.ABorderIsKeptClearToo;
var
  b: TFrameBar;
begin
  b := NewBarOn(
    'TyTrackBar { color: #0000FF; padding: 0px; border-width: 3px; border-color: #FF00FF; }' +
    'TyTrackGroove { background: #00FF00; border-radius: 0px; }' +
    'TyTrackThumb { background: #FF0000; border-radius: 0px; }');
  b.ShowValue := True;
  b.Position := 0;
  AssertEquals('the border is whole at Min', 0, RingHoles(b, 3));
  b.Position := 100;
  AssertEquals('and at Max', 0, RingHoles(b, 3));
  b.Position := 0;
  AssertEquals('the track starts inside it', 3, b.ThumbRect.Left);
end;

procedure TTrackBarFrameTest.TheWiderOfTheBorderAndTheRingIsKept;
var
  b: TFrameBar;
begin
  b := NewBarOn(
    'TyTrackBar { color: #0000FF; padding: 0px; border-width: 5px; border-color: #FF00FF; }' +
    'TyTrackBar:focus { outline: 2px #FF00FF; }' +
    'TyTrackGroove { background: #00FF00; border-radius: 0px; }' +
    'TyTrackThumb { background: #FF0000; border-radius: 0px; }');
  b.Position := 0;
  AssertEquals('five of border, not two of ring', 5, b.ThumbRect.Left);
  b := NewBarOn(
    'TyTrackBar { color: #0000FF; padding: 0px; border-width: 1px; border-color: #FF00FF; }' +
    'TyTrackBar:focus { outline: 4px #FF00FF; }' +
    'TyTrackGroove { background: #00FF00; border-radius: 0px; }' +
    'TyTrackThumb { background: #FF0000; border-radius: 0px; }');
  b.Position := 0;
  AssertEquals('four of ring, not one of border', 4, b.ThumbRect.Left);
end;

procedure TTrackBarFrameTest.ARingSetInFromTheEdgeIsKeptClear;
var
  b: TFrameBar;
  thumb: TRect;
begin
  b := NewBarOn(
    'TyTrackBar { color: #0000FF; padding: 0px; border-width: 0px; }' +
    'TyTrackBar:focus { outline: 2px #FF00FF; outline-offset: 3px; }' +
    'TyTrackGroove { background: #00FF00; border-radius: 0px; }' +
    'TyTrackThumb { background: #FF0000; border-radius: 0px; }');
  b.TickStyle := ttsNone;
  b.Focus := True;
  b.Position := 0;
  thumb := Box(b, piThumb);
  AssertEquals('the thumb starts after the offset and the ring', 5, thumb.Left);
  AssertEquals('and below them', 5, thumb.Top);
end;

procedure TTrackBarFrameTest.TheValueOfAVerticalBarIsAboveTheRing;
var
  b: TFrameBar;
  text: TRect;
  img: TBGRABitmap;
  x, y, lowest: Integer;
begin
  b := NewBar(True);
  b.TickStyle := ttsNone;
  b.ShowValue := True;
  b.Focus := True;
  b.StyleOverride := 'padding: 0px 0px 9px 0px;';
  b.Position := 50;
  lowest := -1;
  img := Picture(b);
  try
    for y := 0 to img.Height - 1 do
      for x := 0 to img.Width - 1 do
        if IsInk(img.GetPixel(x, y), piBlue) and (y > lowest) then lowest := y;
  finally
    img.Free;
  end;
  text := Rect(0, 0, 0, lowest + 1);
  AssertTrue('setup: the value was drawn', lowest > 100);
  AssertTrue(Format('the number ends above the bottom padding and the ring (at %d)', [text.Bottom]),
    text.Bottom <= 200 - cRing - 9);
end;

{ ---- #237: the thumb's size and corners ---- }

procedure TTrackBarFrameTest.TheThumbIsTwelveLongByDefault;
var
  b: TFrameBar;
  thumb: TRect;
begin
  b := NewBar;
  b.TickStyle := ttsNone;
  b.Position := 50;
  thumb := Box(b, piThumb);
  AssertEquals('twelve along the track', 12, thumb.Right - thumb.Left);
  AssertEquals('and as thick as the band inside the ring', 40 - 2 * cRing, thumb.Bottom - thumb.Top);
end;

procedure TTrackBarFrameTest.TheLengthTokenSetsTheThumbsLength;
var
  b: TFrameBar;
  thumb: TRect;
begin
  b := NewBar;
  b.TickStyle := ttsNone;
  b.Position := 50;
  b.StyleOverride := '--track-thumb-length: 24px;';
  thumb := Box(b, piThumb);
  AssertEquals('drawn twenty-four long', 24, thumb.Right - thumb.Left);
  AssertEquals('and the hit rect with it', 24, b.ThumbRect.Right - b.ThumbRect.Left);
end;

procedure TTrackBarFrameTest.TheThumbStillTravelsFromEndToEnd;
var
  b: TFrameBar;
  groove, thumb: TRect;
begin
  b := NewBar;
  b.TickStyle := ttsNone;
  b.StyleOverride := '--track-thumb-length: 30px;';
  b.Position := 0;
  groove := Box(b, piGroove);
  thumb := Box(b, piThumb);
  AssertEquals('at Min it starts where the track starts', cRing, thumb.Left);
  b.Position := 100;
  thumb := Box(b, piThumb);
  AssertEquals('at Max it ends where the track ends', 200 - cRing, thumb.Right);
  AssertEquals('setup: the groove under it is hidden up to its end', 200 - cRing - 30, Box(b, piGroove).Right);
  AssertTrue('setup: the groove was found at Min', groove.Right > groove.Left);
end;

procedure TTrackBarFrameTest.TheThicknessTokenSetsTheThumbsThickness;
var
  b: TFrameBar;
  groove, thumb: TRect;
begin
  b := NewBar;
  b.TickStyle := ttsNone;
  b.Position := 100;
  groove := Box(b, piGroove);
  b.StyleOverride := '--track-thumb-thickness: 14px;';
  thumb := Box(b, piThumb);
  AssertEquals('fourteen across the track', 14, thumb.Bottom - thumb.Top);
  AssertEquals('centred on the groove', (groove.Top + groove.Bottom) div 2, (thumb.Top + thumb.Bottom) div 2);
  AssertEquals('still twelve long', 12, thumb.Right - thumb.Left);
end;

procedure TTrackBarFrameTest.TheThicknessIsHeldToTheBand;
var
  b: TFrameBar;
  thumb: TRect;
begin
  b := NewBar;
  b.TickStyle := ttsNone;
  b.Position := 50;
  b.StyleOverride := '--track-thumb-thickness: 300px;';
  thumb := Box(b, piThumb);
  AssertEquals('no thicker than the band', 40 - 2 * cRing, thumb.Bottom - thumb.Top);
  AssertEquals('and inside the ring', cRing, thumb.Top);
end;

procedure TTrackBarFrameTest.AThumbAsLongAsItIsThickIsRound;
var
  b: TFrameBar;
  thumb: TRect;
  img: TBGRABitmap;
begin
  b := NewBar;
  b.TickStyle := ttsNone;
  b.Position := 50;
  b.StyleOverride := '--track-thumb-length: 20px; --track-thumb-thickness: 20px;';
  thumb := Box(b, piThumb);
  AssertEquals('twenty wide', 20, thumb.Right - thumb.Left);
  AssertEquals('twenty high', 20, thumb.Bottom - thumb.Top);
  img := Picture(b);
  try
    AssertTrue('its middle is thumb', IsInk(img.GetPixel(thumb.Left + 10, thumb.Top + 10), piThumb));
    AssertFalse('its corner is not: the pill radius of the theme makes it a circle',
      IsInk(img.GetPixel(thumb.Left + 1, thumb.Top + 1), piThumb));
  finally
    img.Free;
  end;
end;

procedure TTrackBarFrameTest.TheRadiusTokenSquaresTheThumb;
var
  b: TFrameBar;
  thumb: TRect;
  img: TBGRABitmap;
begin
  b := NewBar;
  b.TickStyle := ttsNone;
  b.Position := 50;
  b.StyleOverride := '--track-thumb-length: 20px; --track-thumb-thickness: 20px; --track-thumb-radius: 0px;';
  thumb := Box(b, piThumb);
  img := Picture(b);
  try
    AssertTrue('the corner is thumb too', IsInk(img.GetPixel(thumb.Left, thumb.Top), piThumb));
    AssertTrue('all four of them', IsInk(img.GetPixel(thumb.Right - 1, thumb.Bottom - 1), piThumb));
  finally
    img.Free;
  end;
  b.StyleOverride := '--track-thumb-length: 20px; --track-thumb-thickness: 20px; --track-thumb-radius: 4px;';
  thumb := Box(b, piThumb);
  img := Picture(b);
  try
    AssertFalse('a radius of four takes the very corner', IsInk(img.GetPixel(thumb.Left, thumb.Top), piThumb));
    AssertTrue('and leaves what a circle would not', IsInk(img.GetPixel(thumb.Left + 3, thumb.Top + 3), piThumb));
  finally
    img.Free;
  end;
end;

procedure TTrackBarFrameTest.TheTokensTurnWithAVerticalBar;
var
  b: TFrameBar;
  thumb: TRect;
begin
  b := NewBar(True);
  b.TickStyle := ttsNone;
  b.Position := 50;
  b.StyleOverride := '--track-thumb-length: 24px; --track-thumb-thickness: 16px;';
  thumb := Box(b, piThumb);
  AssertEquals('the length runs down the track', 24, thumb.Bottom - thumb.Top);
  AssertEquals('the thickness across it', 16, thumb.Right - thumb.Left);
  AssertEquals('and the hit rect is as long', 24, b.ThumbRect.Bottom - b.ThumbRect.Top);
end;

procedure TTrackBarFrameTest.TheThemeSetsTheThumbForEveryBarAndABarForItself;
var
  a, b: TFrameBar;
begin
  a := NewBar;
  b := NewBar;
  a.TickStyle := ttsNone;
  b.TickStyle := ttsNone;
  FCtl.StyleOverride := ':root { --track-thumb-length: 18px; }';
  AssertEquals('the controller''s token reaches a bar', 18, a.ThumbRect.Right - a.ThumbRect.Left);
  b.StyleOverride := '--track-thumb-length: 26px;';
  AssertEquals('a bar''s own wins', 26, b.ThumbRect.Right - b.ThumbRect.Left);
  AssertEquals('and leaves the other alone', 18, a.ThumbRect.Right - a.ThumbRect.Left);
end;

procedure TTrackBarFrameTest.AutoSizeFollowsTheThumbsThickness;
var
  b: TFrameBar;
  bare: Integer;
begin
  b := NewBar;
  bare := b.PrefCross;
  b.StyleOverride := '--track-thumb-thickness: 30px;';
  AssertEquals('eighteen more than the twelve it asks by default', bare + 18, b.PrefCross);
end;

initialization
  RegisterTest(TTrackBarFrameTest);
end.
