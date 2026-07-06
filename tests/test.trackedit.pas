unit test.trackedit;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.TrackEdit;
type
  TAccessTrack = class(TTyTrackEdit)
  public
    function Reserve(APPI: Integer): Integer;
  end;

  TTrackEditTest = class(TTestCase)
  published
    procedure TestValueAt;
    procedure TestThumbX;
    procedure TestReserveAndValue;
  end;

implementation

function TAccessTrack.Reserve(APPI: Integer): Integer;
begin
  Result := RightReserve(APPI);
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

initialization
  RegisterTest(TTrackEditTest);
end.
