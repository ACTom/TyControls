unit test.multitrackbar;
{$mode objfpc}{$H+}

{ TTyCustomMultiTrackBar (#36). This step: the ordered thumb model -- SetThumbValue clamping
  between the neighbours and Min..Max, the events, Normalize, a MinGap the range cannot hold,
  Min / Max / MinGap changes, and a form being read. }

interface

uses
  Classes, SysUtils, Forms, Controls, fpcunit, testregistry,
  tyControls.MultiTrackBar;

type
  { Opens the protected seams: the whole-set setter, Normalize and the read-a-form pair. }
  TMultiProbe = class(TTyCustomMultiTrackBar)
  public
    procedure Put(const AValues: array of Integer);
    procedure BeginReading;
    procedure EndReading;
  end;

  TTyMultiTrackModelTest = class(TTestCase)
  private
    FForm: TForm;
    FBar: TMultiProbe;
    FLog: string;
    procedure ThumbChanged(Sender: TObject; AIndex: Integer);
    procedure Changed(Sender: TObject);
    function Values: string;
    procedure CheckInvariant(const AWhere: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDefaults;
    procedure TestSetThumbValueStopsAtTheLeftNeighbour;
    procedure TestSetThumbValueStopsAtTheRightNeighbour;
    procedure TestSetThumbValueStaysWithinMinAndMax;
    procedure TestEventsCarryTheIndexAndFireOnlyOnARealChange;
    procedure TestNormalizeSortsAndPushesApart;
    procedure TestNormalizePushesBackFromMax;
    procedure TestAGapTheRangeCannotHoldShrinksThePlacementNotTheProperty;
    procedure TestMinMaxAndMinGapChangesRestoreTheInvariant;
    procedure TestReadingAFormSettlesOnLoadedWithoutEvents;
    procedure TestSetThumbValuesReportsOnlyARealChange;
    procedure TestSelectedThumbStaysInRange;
    procedure TestOutOfRangeIndexRaises;
    procedure TestRandomEditsKeepTheInvariant;
  end;

implementation

{ TMultiProbe }

procedure TMultiProbe.Put(const AValues: array of Integer);
begin
  SetThumbValues(AValues);
end;

procedure TMultiProbe.BeginReading;
begin
  Loading;
end;

procedure TMultiProbe.EndReading;
begin
  Loaded;
end;

{ TTyMultiTrackModelTest }

procedure TTyMultiTrackModelTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FBar := TMultiProbe.Create(FForm);
  FBar.Parent := FForm;
  FLog := '';
end;

procedure TTyMultiTrackModelTest.TearDown;
begin
  FForm.Free;
end;

procedure TTyMultiTrackModelTest.ThumbChanged(Sender: TObject; AIndex: Integer);
begin
  AssertSame(FBar, Sender);
  FLog := FLog + 'T' + IntToStr(AIndex) + ' ';
end;

procedure TTyMultiTrackModelTest.Changed(Sender: TObject);
begin
  AssertSame(FBar, Sender);
  FLog := FLog + 'C ';
end;

function TTyMultiTrackModelTest.Values: string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to FBar.ThumbCount - 1 do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + IntToStr(FBar.ThumbValues[i]);
  end;
end;

procedure TTyMultiTrackModelTest.CheckInvariant(const AWhere: string);
var
  i, gap: Integer;
begin
  { A range set inside out holds every thumb at Min, as TTyTrackBar holds its Position. }
  if FBar.Max < FBar.Min then
  begin
    for i := 0 to FBar.ThumbCount - 1 do
      AssertEquals(Format('%s: inside-out range, thumb %d sits at Min [%s]', [AWhere, i, Values]),
        FBar.Min, FBar.ThumbValues[i]);
    Exit;
  end;
  gap := FBar.MinGap;
  if (FBar.ThumbCount > 1) and (Int64(FBar.ThumbCount - 1) * gap > FBar.Max - FBar.Min) then
    gap := (FBar.Max - FBar.Min) div (FBar.ThumbCount - 1);
  for i := 0 to FBar.ThumbCount - 1 do
  begin
    AssertTrue(Format('%s: thumb %d (%d) below Min %d [%s]', [AWhere, i, FBar.ThumbValues[i],
      FBar.Min, Values]), FBar.ThumbValues[i] >= FBar.Min);
    AssertTrue(Format('%s: thumb %d (%d) above Max %d [%s]', [AWhere, i, FBar.ThumbValues[i],
      FBar.Max, Values]), FBar.ThumbValues[i] <= FBar.Max);
    if i > 0 then
      AssertTrue(Format('%s: thumbs %d and %d closer than %d [%s]', [AWhere, i - 1, i, gap, Values]),
        FBar.ThumbValues[i] - FBar.ThumbValues[i - 1] >= gap);
  end;
end;

procedure TTyMultiTrackModelTest.TestDefaults;
begin
  AssertEquals('Min', 0, FBar.Min);
  AssertEquals('Max', 100, FBar.Max);
  AssertEquals('MinGap', 0, FBar.MinGap);
  AssertEquals('no thumb selected', -1, FBar.SelectedThumb);
  AssertEquals('the custom class seeds no thumbs', 0, FBar.ThumbCount);
  AssertTrue('focusable, like TTyTrackBar', FBar.TabStop);
end;

procedure TTyMultiTrackModelTest.TestSetThumbValueStopsAtTheLeftNeighbour;
begin
  FBar.MinGap := 5;
  FBar.Put([20, 50, 80]);
  FBar.SetThumbValue(1, 10);
  AssertEquals('the middle thumb stops MinGap right of the first', '20,25,80', Values);
  FBar.SetThumbValue(2, 0);
  AssertEquals('the last stops MinGap right of the middle', '20,25,30', Values);
end;

procedure TTyMultiTrackModelTest.TestSetThumbValueStopsAtTheRightNeighbour;
begin
  FBar.MinGap := 5;
  FBar.Put([20, 50, 80]);
  FBar.SetThumbValue(1, 95);
  AssertEquals('the middle thumb stops MinGap left of the last', '20,75,80', Values);
  FBar.SetThumbValue(0, 99);
  AssertEquals('the first stops MinGap left of the middle', '70,75,80', Values);
end;

procedure TTyMultiTrackModelTest.TestSetThumbValueStaysWithinMinAndMax;
begin
  FBar.Min := -10;
  FBar.Max := 10;
  FBar.Put([0, 5]);
  FBar.SetThumbValue(0, -500);
  FBar.SetThumbValue(1, 500);
  AssertEquals('-10,10', Values);
end;

procedure TTyMultiTrackModelTest.TestEventsCarryTheIndexAndFireOnlyOnARealChange;
begin
  FBar.MinGap := 5;
  FBar.Put([20, 50, 100]);
  FBar.OnThumbChange := @ThumbChanged;
  FBar.OnChange := @Changed;
  FBar.SetThumbValue(1, 50);
  AssertEquals('the same value fires nothing', '', FLog);
  FBar.SetThumbValue(1, 60);
  AssertEquals('a move reports its thumb, then OnChange', 'T1 C ', FLog);
  FLog := '';
  FBar.SetThumbValue(2, 500);
  AssertEquals('clamped back onto where it was: nothing', '', FLog);
  FBar.SetThumbValue(0, 70);
  AssertEquals('clamped to a new place is a change', 'T0 C ', FLog);
  AssertEquals('55,60,100', Values);
end;

procedure TTyMultiTrackModelTest.TestNormalizeSortsAndPushesApart;
begin
  FBar.MinGap := 5;
  FBar.Put([70, 10, 12, 40]);
  AssertEquals('sorted, and 12 pushed to MinGap from 10', '10,15,40,70', Values);
  FBar.Put([30, 30, 30]);
  AssertEquals('coinciding values pushed apart left to right', '30,35,40', Values);
end;

procedure TTyMultiTrackModelTest.TestNormalizePushesBackFromMax;
begin
  FBar.MinGap := 5;
  FBar.Put([100, 99, 98]);
  AssertEquals('pushed apart, then back from Max', '90,95,100', Values);
  FBar.Put([-50, 200]);
  AssertEquals('clamped into Min..Max', '0,100', Values);
end;

procedure TTyMultiTrackModelTest.TestAGapTheRangeCannotHoldShrinksThePlacementNotTheProperty;
begin
  FBar.Max := 10;
  FBar.MinGap := 5;
  FBar.Put([5, 5, 5, 5]);    // 3 x 5 = 15 > 10: placed (10 - 0) div 3 = 3 apart
  AssertEquals('1,4,7,10', Values);
  AssertEquals('MinGap keeps the value it was given', 5, FBar.MinGap);
  FBar.SetThumbValue(1, 0);
  AssertEquals('a move honours the shrunk gap', '1,4,7,10', Values);
  FBar.Max := 100;
  AssertEquals('room again: the full gap comes back', '1,6,11,16', Values);
  CheckInvariant('after widening');
end;

procedure TTyMultiTrackModelTest.TestMinMaxAndMinGapChangesRestoreTheInvariant;
begin
  FBar.Put([20, 50, 80]);
  FBar.OnThumbChange := @ThumbChanged;
  FBar.OnChange := @Changed;
  FBar.Min := 60;
  AssertEquals('60,60,80', Values);
  AssertEquals('each thumb that moved is reported, then OnChange once', 'T0 T1 C ', FLog);
  FLog := '';
  FBar.MinGap := 5;
  AssertEquals('60,65,80', Values);
  FBar.Max := 66;
  AssertEquals('56 would be below Min: placed 3 apart instead', '60,63,66', Values);
  CheckInvariant('after Max');
  FLog := '';
  FBar.Max := 66;
  AssertEquals('setting the same Max again fires nothing', '', FLog);
end;

procedure TTyMultiTrackModelTest.TestReadingAFormSettlesOnLoadedWithoutEvents;
begin
  FBar.OnThumbChange := @ThumbChanged;
  FBar.OnChange := @Changed;
  FBar.BeginReading;
  FBar.Put([90, 10, 50]);
  FBar.SetThumbValue(0, 300);
  AssertEquals('while reading, values are kept as listed', '300,10,50', Values);
  FBar.Min := 20;
  FBar.Max := 80;
  FBar.MinGap := 5;
  AssertEquals('nor do Min / Max / MinGap settle them yet', '300,10,50', Values);
  FBar.EndReading;
  AssertEquals('Loaded sorts and clamps', '20,50,80', Values);
  CheckInvariant('after Loaded');
  AssertEquals('reading a form fires no thumb or change event', '', FLog);
end;

procedure TTyMultiTrackModelTest.TestSetThumbValuesReportsOnlyARealChange;
begin
  FBar.OnThumbChange := @ThumbChanged;
  FBar.OnChange := @Changed;
  FBar.Put([10, 20]);
  AssertEquals('a new set is a change', 'C ', FLog);
  FLog := '';
  FBar.Put([20, 10]);
  AssertEquals('the same set in another order normalizes to what was there', '', FLog);
  FBar.Put([10, 20, 30]);
  AssertEquals('a thumb more is a change', 'C ', FLog);
end;

procedure TTyMultiTrackModelTest.TestSelectedThumbStaysInRange;
begin
  FBar.Put([10, 20, 30]);
  FBar.SelectedThumb := 2;
  AssertEquals(2, FBar.SelectedThumb);
  FBar.SelectedThumb := 3;
  AssertEquals('past the last thumb is none', -1, FBar.SelectedThumb);
  FBar.SelectedThumb := 2;
  FBar.Put([10]);
  AssertEquals('a selected thumb that went away is none', -1, FBar.SelectedThumb);
end;

procedure TTyMultiTrackModelTest.TestOutOfRangeIndexRaises;
var
  raised: Boolean;
begin
  FBar.Put([10, 20]);
  raised := False;
  try
    FBar.SetThumbValue(2, 5);
  except
    on EListError do raised := True;
  end;
  AssertTrue('SetThumbValue past the last thumb raises EListError', raised);
  raised := False;
  try
    FBar.ThumbValues[-1];
  except
    on EListError do raised := True;
  end;
  AssertTrue('ThumbValues[-1] raises EListError', raised);
end;

procedure TTyMultiTrackModelTest.TestRandomEditsKeepTheInvariant;
var
  step, op: Integer;
begin
  RandSeed := 36;
  FBar.Put([5, 25, 45, 65, 85]);
  for step := 1 to 2000 do
  begin
    op := Random(10);
    case op of
      0: FBar.Min := Random(60) - 20;
      1: FBar.Max := FBar.Min + Random(120);
      2: FBar.MinGap := Random(30);
    else
      FBar.SetThumbValue(Random(FBar.ThumbCount), Random(200) - 50);
    end;
    CheckInvariant('step ' + IntToStr(step) + ' op ' + IntToStr(op));
  end;
end;

initialization
  RegisterTest(TTyMultiTrackModelTest);
end.
