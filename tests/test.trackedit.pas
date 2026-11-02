unit test.trackedit;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, fpcunit, testregistry, tyControls.TrackEdit;
type
  TAccessTrack = class(TTyTrackEdit)
  public
    function Reserve(APPI: Integer): Integer;
    { A point in the slider zone, AFrac of the way along it. }
    function At(AFrac: Double): TPoint;
    procedure Press(const P: TPoint);
    procedure Drag(const P: TPoint);
    procedure Release(const P: TPoint);
  end;

  TTrackEditTest = class(TTestCase)
  private
    FChanges: Integer;
    procedure CountChange(Sender: TObject);
  published
    procedure TestValueAt;
    procedure TestThumbX;
    procedure TestReserveAndValue;
    procedure TestTheSliderIsTheUsersEditAndReadOnlyStopsIt;
  end;

implementation

function TAccessTrack.Reserve(APPI: Integer): Integer;
begin
  Result := RightReserve(APPI);
end;

function TAccessTrack.At(AFrac: Double): TPoint;
var z: TRect;
begin
  z := TrailingZone(Font.PixelsPerInch);
  Result := Point(z.Left + Round((z.Right - z.Left) * AFrac), (z.Top + z.Bottom) div 2);
end;

procedure TAccessTrack.Press(const P: TPoint);
begin
  MouseDown(mbLeft, [], P.X, P.Y);
end;

procedure TAccessTrack.Drag(const P: TPoint);
begin
  MouseMove([ssLeft], P.X, P.Y);
end;

procedure TAccessTrack.Release(const P: TPoint);
begin
  MouseUp(mbLeft, [], P.X, P.Y);
end;

procedure TTrackEditTest.CountChange(Sender: TObject);
begin
  Inc(FChanges);
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

{ #159: the slider is the user editing the value -- Modified, OnChange when the value moves, and
  one undo step for the whole drag -- and with ReadOnly it does not move it at all. }
procedure TTrackEditTest.TestTheSliderIsTheUsersEditAndReadOnlyStopsIt;
var
  c: TAccessTrack;
  before: string;
begin
  c := TAccessTrack.Create(nil);
  try
    c.Font.PixelsPerInch := 96;
    c.SetBounds(0, 0, 240, 26);
    c.Value := 0;
    before := c.Text;
    c.OnChange := @CountChange;
    FChanges := 0;
    c.ReadOnly := True;
    c.Press(c.At(0.5));
    c.Release(c.At(0.5));
    AssertEquals('read-only, the slider does not move the value', 0.0, c.Value, 1e-9);
    AssertEquals('nor change anything', 0, FChanges);
    c.ReadOnly := False;
    c.Press(c.At(0.25));
    c.Drag(c.At(0.5));
    c.Drag(c.At(0.75));
    c.Release(c.At(0.75));
    AssertTrue('setup: the drag moved the value', c.Value > 50);
    AssertTrue('the user changed it', c.Modified);
    AssertTrue('and it said so', FChanges > 0);
    c.Undo;
    AssertEquals('one undo takes the whole drag back', before, c.Text);
  finally c.Free; end;
end;

initialization
  RegisterTest(TTrackEditTest);
end.
