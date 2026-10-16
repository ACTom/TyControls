unit test.trackedit;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, fpcunit, testregistry, tyControls.TrackEdit;
type
  TAccessTrack = class(TTyTrackEdit)
  public
    function Reserve(APPI: Integer): Integer;
    function Zone(APPI: Integer): TRect;
    procedure DoPress(X, Y: Integer);
  end;

  TTrackEditTest = class(TTestCase)
  private
    function MakeTrack: TAccessTrack;
  published
    procedure TestValueAt;
    procedure TestThumbX;
    procedure TestReserveAndValue;
    { #85: the slider zone's width is SliderWidth logical px -- 74 by default, the width it
      always had, so an existing form neither looks different nor stores the property. }
    procedure TestSliderWidthDefaultsTo74AndIsNotStored;
    procedure TestSliderWidthSizesTheZoneAtEveryPPI;
    { The width is not just painted: a click the wider zone covers drives the slider, where
      the default zone would have put the caret in the number. }
    procedure TestAWiderSliderTakesTheClick;
    { 0 leaves a plain numeric edit (no zone, the click goes to the text); below 0 reads as 0. }
    procedure TestZeroHidesTheSlider;
    procedure TestSliderWidthRoundTripsThroughTheStream;
  end;

implementation

function TAccessTrack.Reserve(APPI: Integer): Integer;
begin
  Result := RightReserve(APPI);
end;

function TAccessTrack.Zone(APPI: Integer): TRect;
begin
  Result := TrailingZone(APPI);
end;

procedure TAccessTrack.DoPress(X, Y: Integer);
begin
  MouseDown(mbLeft, [ssLeft], X, Y);
  MouseUp(mbLeft, [], X, Y);
end;

function TTrackEditTest.MakeTrack: TAccessTrack;
begin
  Result := TAccessTrack.Create(nil);
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 240, 28);
end;

function StreamText(AComp: TComponent): string;
var
  bin: TMemoryStream;
  txt: TStringStream;
begin
  bin := TMemoryStream.Create;
  txt := TStringStream.Create('');
  try
    bin.WriteComponent(AComp);
    bin.Position := 0;
    ObjectBinaryToText(bin, txt);
    Result := txt.DataString;
  finally
    txt.Free;
    bin.Free;
  end;
end;

procedure TTrackEditTest.TestValueAt;
begin
  AssertEquals('midpoint', 50.0, TyTrackEditValueAt(50, 0, 100, 0, 100), 1e-9);
  AssertEquals('left end', 0.0, TyTrackEditValueAt(0, 0, 100, 0, 100), 1e-9);
  AssertEquals('right end', 100.0, TyTrackEditValueAt(100, 0, 100, 0, 100), 1e-9);
  AssertEquals('clamp below', 0.0, TyTrackEditValueAt(-20, 0, 100, 0, 100), 1e-9);
  AssertEquals('clamp above', 100.0, TyTrackEditValueAt(200, 0, 100, 0, 100), 1e-9);
  AssertEquals('degenerate range', 5.0, TyTrackEditValueAt(50, 0, 100, 5, 5), 1e-9);
end;

procedure TTrackEditTest.TestThumbX;
begin
  AssertEquals('midpoint', 50, TyTrackEditThumbX(50, 0, 100, 0, 100));
  AssertEquals('left end', 0, TyTrackEditThumbX(0, 0, 100, 0, 100));
  AssertEquals('right end', 100, TyTrackEditThumbX(100, 0, 100, 0, 100));
  AssertEquals('clamped value', 100, TyTrackEditThumbX(999, 0, 100, 0, 100));
  AssertEquals('degenerate range', 10, TyTrackEditThumbX(50, 5, 5, 10, 90));
end;

procedure TTrackEditTest.TestReserveAndValue;
var c: TAccessTrack;
begin
  c := TAccessTrack.Create(nil);
  try
    AssertTrue('reserves a slider zone', c.Reserve(96) > 0);
    // Inherits NumericEdit.Value; default range 0..100 set in the constructor.
    c.Value := 50;
    AssertEquals('value set', 50.0, c.Value, 1e-9);
    c.Value := 999;   // clamps to MaxValue=100
    AssertEquals('value clamped', 100.0, c.Value, 1e-9);
  finally c.Free; end;
end;

procedure TTrackEditTest.TestSliderWidthDefaultsTo74AndIsNotStored;
var c: TAccessTrack;
begin
  c := MakeTrack;
  try
    AssertEquals('the default is the width the slider always had', 74, c.SliderWidth);
    AssertEquals('and it is what the zone reserves', 74, c.Reserve(96));
    AssertEquals('a form that never touched it does not store it', 0,
      Pos('SliderWidth', StreamText(c)));
  finally c.Free; end;
end;

procedure TTrackEditTest.TestSliderWidthSizesTheZoneAtEveryPPI;
var c: TAccessTrack; z: TRect;
begin
  c := MakeTrack;
  try
    c.SliderWidth := 120;
    AssertEquals('120 logical px at 96 PPI', 120, c.Reserve(96));
    AssertEquals('logical px: twice as many device px at 192 PPI', 240, c.Reserve(192));
    z := c.Zone(96);
    AssertEquals('the zone the clicks are tested against is that wide', 120, z.Right - z.Left);
  finally c.Free; end;
end;

procedure TTrackEditTest.TestAWiderSliderTakesTheClick;
var c: TAccessTrack; z74, z: TRect; x, y: Integer;
begin
  c := MakeTrack;
  try
    z74 := c.Zone(96);
    c.SliderWidth := 160;
    z := c.Zone(96);
    x := z.Left + 10;   // in the wide zone's track span (8 px margin), well left of the default one
    y := (z.Top + z.Bottom) div 2;
    AssertTrue('precondition: the point is outside the default zone', x < z74.Left);

    c.SliderWidth := 74;
    c.Value := 50;
    c.DoPress(x, y);
    AssertEquals('default width: a click there is a click on the number', 50.0, c.Value, 1e-9);

    c.SliderWidth := 160;
    c.Value := 50;
    c.DoPress(x, y);
    AssertTrue('wide slider: the same click drives the slider to near its left end, got ' +
      FloatToStr(c.Value), c.Value < 10);
  finally c.Free; end;
end;

procedure TTrackEditTest.TestZeroHidesTheSlider;
var c: TAccessTrack;
begin
  c := MakeTrack;
  try
    c.SliderWidth := 0;
    AssertEquals('0 reserves nothing', 0, c.Reserve(96));
    c.Value := 50;
    c.DoPress(c.Width - 4, c.Height div 2);
    AssertEquals('a click at the right edge goes to the text', 50.0, c.Value, 1e-9);
    c.SliderWidth := -5;
    AssertEquals('below 0 reads as 0', 0, c.SliderWidth);
  finally c.Free; end;
end;

procedure TTrackEditTest.TestSliderWidthRoundTripsThroughTheStream;
var c, d: TAccessTrack; bin: TMemoryStream;
begin
  c := MakeTrack;
  d := TAccessTrack.Create(nil);
  bin := TMemoryStream.Create;
  try
    c.SliderWidth := 120;
    AssertTrue('a changed width is stored', Pos('SliderWidth = 120', StreamText(c)) > 0);
    bin.WriteComponent(c);
    bin.Position := 0;
    bin.ReadComponent(d);
    AssertEquals('and read back', 120, d.SliderWidth);
  finally
    bin.Free; d.Free; c.Free;
  end;
end;

initialization
  RegisterTest(TTrackEditTest);
end.
