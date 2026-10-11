unit test.trackbar.selrange;
{$mode objfpc}{$H+}

{ LCL's selection range on TTyTrackBar (#37): SelStart, SelEnd, ShowSelRange.

  The span is checked against where the THUMB sits at each end value, not against the formula
  that computes it: a selection from 20 to 60 must run from the thumb's centre at Position 20 to
  its centre at Position 60, whichever way the bar runs. The pixel test then checks that the
  painted band is exactly that span and nothing else. }

interface

uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, TypInfo, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.TrackBar, test.trackbar;

type
  TTyTrackBarSelRangeTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FBar: TTyTrackBarProbe;
    { The thumb's centre on the main axis with Position = AValue. }
    function ThumbCentreAt(AValue: Integer): Integer;
    { Red pixels on the groove's centre line, split into inside [ALo, AHi) and outside it. }
    procedure CountRed(ALo, AHi: Integer; out AInside, AOutside: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDefaultsAreLcls;
    procedure TestTheThreeArePublished;
    procedure TestSpanRunsBetweenTheThumbCentres;
    procedure TestReversedMirrorsTheSpan;
    procedure TestVerticalSpanFollowsTheThumb;
    procedure TestNothingWhenShowSelRangeIsOff;
    procedure TestNothingWhenBothAreZero;
    procedure TestNothingWhenStartIsAfterEnd;
    procedure TestEndsAreClampedToMinAndMax;
    procedure TestPaintFillsExactlyTheSpan;
    procedure TestPaintShowsNothingWhenOff;
  end;

implementation

const
  BarW = 200;
  BarH = 24;

procedure TTyTrackBarSelRangeTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  { Distinct colours per part: the selection is the only red thing on the bar. }
  FCtl.LoadThemeCss(
    'TyTrackBar { background: #202020; border-width: 0px; border-radius: 0px; }' +
    'TyTrackGroove { background: #606060; border-radius: 0px; }' +
    'TyTrackSelection { background: #FF0000; border-radius: 0px; }' +
    'TyTrackThumb { background: #3B82F6; border-radius: 0px; }');
  FForm := TForm.CreateNew(nil);
  FBar := TTyTrackBarProbe.Create(FForm);
  FBar.Parent := FForm;
  FBar.Controller := FCtl;
  FBar.Font.PixelsPerInch := 96;
  FBar.SetBounds(0, 0, BarW, BarH);
  FBar.TickStyle := ttsNone;
  FBar.Min := 0;
  FBar.Max := 100;
end;

procedure TTyTrackBarSelRangeTest.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

function TTyTrackBarSelRangeTest.ThumbCentreAt(AValue: Integer): Integer;
var
  r: TRect;
begin
  FBar.Position := AValue;
  r := FBar.ThumbRect;
  if FBar.Orientation = toVertical then
    Result := r.Top + (r.Bottom - r.Top) div 2
  else
    Result := r.Left + (r.Right - r.Left) div 2;
end;

procedure TTyTrackBarSelRangeTest.CountRed(ALo, AHi: Integer; out AInside, AOutside: Integer);
var
  bmp: TBitmap;
  re: TBGRABitmap;
  x: Integer;
  px: TBGRAPixel;
begin
  AInside := 0;
  AOutside := 0;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(BarW, BarH);
    FBar.RenderTo(bmp.Canvas, Rect(0, 0, BarW, BarH), 96);
    re := TBGRABitmap.Create(bmp);
    try
      for x := 0 to BarW - 1 do
      begin
        px := re.GetPixel(x, BarH div 2);
        if (px.red > 200) and (px.green < 60) and (px.blue < 60) then
          if (x >= ALo) and (x < AHi) then Inc(AInside) else Inc(AOutside);
      end;
    finally
      re.Free;
    end;
  finally
    bmp.Free;
  end;
end;

procedure TTyTrackBarSelRangeTest.TestDefaultsAreLcls;
var
  lo, hi: Integer;
begin
  AssertEquals('SelStart', 0, FBar.SelStart);
  AssertEquals('SelEnd', 0, FBar.SelEnd);
  AssertTrue('ShowSelRange defaults on, as LCL', FBar.ShowSelRange);
  AssertFalse('a fresh bar shows no selection (0..0 is LCL''s "none")',
    FBar.SelRangeSpan(96, lo, hi));
end;

procedure TTyTrackBarSelRangeTest.TestTheThreeArePublished;
begin
  AssertTrue(IsPublishedProp(TTyTrackBar, 'SelStart'));
  AssertTrue(IsPublishedProp(TTyTrackBar, 'SelEnd'));
  AssertTrue(IsPublishedProp(TTyTrackBar, 'ShowSelRange'));
  AssertFalse('the custom class publishes none of them',
    IsPublishedProp(TTyCustomTrackBar, 'SelStart'));
end;

procedure TTyTrackBarSelRangeTest.TestSpanRunsBetweenTheThumbCentres;
var
  lo, hi, c20, c60: Integer;
begin
  c20 := ThumbCentreAt(20);
  c60 := ThumbCentreAt(60);
  FBar.SelStart := 20;
  FBar.SelEnd := 60;
  AssertTrue(FBar.SelRangeSpan(96, lo, hi));
  AssertEquals('starts under the thumb at 20', c20, lo);
  AssertEquals('ends under the thumb at 60', c60, hi);
end;

procedure TTyTrackBarSelRangeTest.TestReversedMirrorsTheSpan;
var
  lo, hi, c20, c60: Integer;
begin
  FBar.Reversed := True;
  c20 := ThumbCentreAt(20);
  c60 := ThumbCentreAt(60);
  AssertTrue('reversed: 60 sits left of 20', c60 < c20);
  FBar.SelStart := 20;
  FBar.SelEnd := 60;
  AssertTrue(FBar.SelRangeSpan(96, lo, hi));
  AssertEquals('the low end is the thumb at 60', c60, lo);
  AssertEquals('the high end is the thumb at 20', c20, hi);
end;

procedure TTyTrackBarSelRangeTest.TestVerticalSpanFollowsTheThumb;
var
  lo, hi, c20, c60: Integer;
begin
  FBar.Orientation := toVertical;
  FBar.SetBounds(0, 0, BarH, BarW);
  c20 := ThumbCentreAt(20);
  c60 := ThumbCentreAt(60);
  FBar.SelStart := 20;
  FBar.SelEnd := 60;
  AssertTrue(FBar.SelRangeSpan(96, lo, hi));
  if c20 < c60 then
  begin
    AssertEquals(c20, lo);
    AssertEquals(c60, hi);
  end
  else
  begin
    AssertEquals(c60, lo);
    AssertEquals(c20, hi);
  end;
end;

procedure TTyTrackBarSelRangeTest.TestNothingWhenShowSelRangeIsOff;
var
  lo, hi: Integer;
begin
  FBar.SelStart := 20;
  FBar.SelEnd := 60;
  FBar.ShowSelRange := False;
  AssertFalse(FBar.SelRangeSpan(96, lo, hi));
end;

procedure TTyTrackBarSelRangeTest.TestNothingWhenBothAreZero;
var
  lo, hi: Integer;
begin
  FBar.Min := -50;            // 0..0 is "no selection" even where 0 is inside the range
  FBar.SelStart := 0;
  FBar.SelEnd := 0;
  AssertFalse(FBar.SelRangeSpan(96, lo, hi));
  FBar.SelEnd := 10;
  AssertTrue('0..10 is a selection', FBar.SelRangeSpan(96, lo, hi));
end;

procedure TTyTrackBarSelRangeTest.TestNothingWhenStartIsAfterEnd;
var
  lo, hi: Integer;
begin
  FBar.SelStart := 60;
  FBar.SelEnd := 20;
  AssertFalse(FBar.SelRangeSpan(96, lo, hi));
end;

procedure TTyTrackBarSelRangeTest.TestEndsAreClampedToMinAndMax;
var
  lo, hi, cMin, cMax: Integer;
begin
  cMin := ThumbCentreAt(0);
  cMax := ThumbCentreAt(100);
  FBar.SelStart := -40;
  FBar.SelEnd := 500;
  AssertTrue(FBar.SelRangeSpan(96, lo, hi));
  AssertEquals('clamped to Min', cMin, lo);
  AssertEquals('clamped to Max', cMax, hi);
end;

procedure TTyTrackBarSelRangeTest.TestPaintFillsExactlyTheSpan;
var
  lo, hi, inside, outside: Integer;
begin
  FBar.Position := 100;       // the thumb parked clear of the span
  FBar.SelStart := 20;
  FBar.SelEnd := 60;
  AssertTrue(FBar.SelRangeSpan(96, lo, hi));
  CountRed(lo, hi, inside, outside);
  AssertEquals('every pixel of the span is the selection colour', hi - lo, inside);
  AssertEquals('nothing outside the span is', 0, outside);
end;

procedure TTyTrackBarSelRangeTest.TestPaintShowsNothingWhenOff;
var
  inside, outside: Integer;
begin
  FBar.Position := 100;
  FBar.SelStart := 20;
  FBar.SelEnd := 60;
  FBar.ShowSelRange := False;
  CountRed(0, BarW, inside, outside);
  AssertEquals('ShowSelRange off paints no selection', 0, inside + outside);
end;

initialization
  RegisterTest(TTyTrackBarSelRangeTest);
end.
