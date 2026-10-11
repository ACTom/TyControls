unit tyControls.MultiTrackBar;
{$mode objfpc}{$H+}

{ Track bars with more than one thumb (#36): the ordered thumb model shared by TTyRangeTrackBar
  (one or more ranges) and TTyMultiTrackBar (several values).

  TTyCustomMultiTrackBar sits BESIDE TTyCustomTrackBar rather than under it: that class is built
  around a single Position. What the two share is the geometry (TyTrackThumbOffset /
  TyTrackPosFromOffset) and the tick band (TyDrawTrackTicks), all unit-level in
  tyControls.TrackBar. }

interface

uses
  Classes, SysUtils, Controls,
  tyControls.Base, tyControls.Controller;

type
  { A thumb moved; AIndex is its place in ThumbValues. }
  TTyTrackThumbEvent = procedure(Sender: TObject; AIndex: Integer) of object;

  { THE MODEL. The thumbs are an ordered array of integers, FValues, that always holds:

      ascending, FValues[i+1] - FValues[i] >= MinGap, every value within Min..Max.

    SetThumbValue is the one way a single thumb moves, from code or (later) from the mouse and
    the keyboard: it clamps the value between its neighbours (each +/- MinGap) and Min..Max, and
    fires OnThumbChange(Self, AIndex) and OnChange only when the value actually changed.

    Normalize puts an arbitrary array back into that shape -- sorted, then pushed apart left to
    right and, where that runs past Max, back from the right. It runs when Min, Max or MinGap
    change and when a form has been read (Loaded); while a form is being read nothing is
    clamped and no event fires, so the order the .lfm lists the values in does not matter.

    A MinGap the range cannot hold -- (ThumbCount - 1) * MinGap > Max - Min -- does not raise and
    is not rewritten: the thumbs are placed with (Max - Min) div (ThumbCount - 1) between them
    instead, and MinGap keeps the value it was given, so widening the range later brings the
    full gap back. }
  TTyCustomMultiTrackBar = class(TTyCustomControl)
  private
    FValues: array of Integer;
    FMin, FMax, FMinGap: Integer;
    FSelectedThumb: Integer;
    FOnThumbChange: TTyTrackThumbEvent;
    FOnChange: TNotifyEvent;
    function GetThumbCount: Integer;
    function GetThumbValue(AIndex: Integer): Integer;
    procedure SetMin(const AValue: Integer);
    procedure SetMax(const AValue: Integer);
    procedure SetMinGap(const AValue: Integer);
    procedure SetSelectedThumb(AValue: Integer);
    procedure CheckIndex(AIndex: Integer);
  protected
    function GetStyleTypeKey: string; override;
    { The gap the thumbs are actually placed with: MinGap, or the most the range can hold. }
    function EffectiveGap: Integer;
    { Bring FValues back to the invariant. AFire: report each thumb that moved
      (OnThumbChange) and then OnChange once; False while settling a freshly read form. }
    procedure Normalize(AFire: Boolean);
    { Replace the whole set of thumbs (the final classes' collections). Stored as given while the
      form is being read; otherwise normalized at once, and OnChange fires if the result differs
      from what was there. }
    procedure SetThumbValues(const AValues: array of Integer);
    procedure DoThumbChange(AIndex: Integer); virtual;
    procedure DoChange; virtual;
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    { Move one thumb; see the class comment. Out-of-range AIndex raises EListError. }
    procedure SetThumbValue(AIndex, AValue: Integer);
    property ThumbCount: Integer read GetThumbCount;
    { Read-only here: a thumb moves through SetThumbValue or the final class's collection. }
    property ThumbValues[AIndex: Integer]: Integer read GetThumbValue;
    { The thumb the keyboard acts on; -1 = none. Kept within 0..ThumbCount - 1. }
    property SelectedThumb: Integer read FSelectedThumb write SetSelectedThumb default -1;
    property MinGap: Integer read FMinGap write SetMinGap default 0;
    property Min: Integer read FMin write SetMin default 0;
    property Max: Integer read FMax write SetMax default 100;
    property TabStop default True;
    property OnThumbChange: TTyTrackThumbEvent read FOnThumbChange write FOnThumbChange;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

implementation

{ TTyCustomMultiTrackBar }

constructor TTyCustomMultiTrackBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  FMin := 0;
  FMax := 100;
  FMinGap := 0;
  FSelectedThumb := -1;
  Width := 160;
  Height := TyDensityHeight(ActiveController, 24);
end;

function TTyCustomMultiTrackBar.GetStyleTypeKey: string;
begin
  { The final classes get keys of their own, parented to this one. }
  Result := 'TyTrackBar';
end;

function TTyCustomMultiTrackBar.GetThumbCount: Integer;
begin
  Result := Length(FValues);
end;

procedure TTyCustomMultiTrackBar.CheckIndex(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= Length(FValues)) then
    raise EListError.CreateFmt('%s: thumb index %d out of bounds (%d thumbs)',
      [ClassName, AIndex, Length(FValues)]);
end;

function TTyCustomMultiTrackBar.GetThumbValue(AIndex: Integer): Integer;
begin
  CheckIndex(AIndex);
  Result := FValues[AIndex];
end;

function TTyCustomMultiTrackBar.EffectiveGap: Integer;
var
  n: Integer;
  span: Int64;
begin
  Result := FMinGap;
  n := Length(FValues);
  if n < 2 then Exit;
  span := Int64(FMax) - FMin;
  if span < 0 then span := 0;
  if Int64(n - 1) * FMinGap > span then
    Result := span div (n - 1);
end;

procedure TTyCustomMultiTrackBar.Normalize(AFire: Boolean);
var
  v, old: array of Integer;
  n, i, j, k, gap, lo, hi: Integer;
  moved: Boolean;
begin
  n := Length(FValues);
  if n = 0 then Exit;
  old := Copy(FValues);
  v := Copy(FValues);
  lo := FMin;
  hi := FMax;
  if hi < lo then hi := lo;       // a range set inside out holds every thumb at Min
  { Sorted: insertion sort, stable, linear on what is already in order. }
  for i := 1 to n - 1 do
  begin
    k := v[i];
    j := i - 1;
    while (j >= 0) and (v[j] > k) do
    begin
      v[j + 1] := v[j];
      Dec(j);
    end;
    v[j + 1] := k;
  end;
  gap := EffectiveGap;
  for i := 0 to n - 1 do
  begin
    if v[i] < lo then v[i] := lo;
    if v[i] > hi then v[i] := hi;
  end;
  { Pushed apart left to right ... }
  for i := 1 to n - 1 do
    if v[i] < v[i - 1] + gap then v[i] := v[i - 1] + gap;
  { ... and back from Max where that ran past it. (n - 1) * gap <= hi - lo, so the first thumb
    cannot be pushed below Min. }
  if v[n - 1] > hi then v[n - 1] := hi;
  for i := n - 2 downto 0 do
    if v[i] > v[i + 1] - gap then v[i] := v[i + 1] - gap;
  FValues := v;
  if not AFire then Exit;
  moved := False;
  for i := 0 to n - 1 do
    if v[i] <> old[i] then
    begin
      moved := True;
      DoThumbChange(i);
    end;
  if moved then
  begin
    Invalidate;
    DoChange;
  end;
end;

procedure TTyCustomMultiTrackBar.SetThumbValues(const AValues: array of Integer);
var
  old: array of Integer;
  i: Integer;
  same: Boolean;
begin
  old := Copy(FValues);
  SetLength(FValues, Length(AValues));
  for i := 0 to High(AValues) do
    FValues[i] := AValues[i];
  if FSelectedThumb >= Length(FValues) then FSelectedThumb := -1;
  if csLoading in ComponentState then Exit;
  Normalize(False);
  same := Length(old) = Length(FValues);
  if same then
    for i := 0 to High(old) do
      if old[i] <> FValues[i] then
      begin
        same := False;
        Break;
      end;
  if same then Exit;
  Invalidate;
  DoChange;
end;

procedure TTyCustomMultiTrackBar.SetThumbValue(AIndex, AValue: Integer);
var
  lo, hi, gap, n: Integer;
begin
  CheckIndex(AIndex);
  { Reading a form: keep the value as listed; Loaded sorts it out. }
  if csLoading in ComponentState then
  begin
    FValues[AIndex] := AValue;
    Exit;
  end;
  n := Length(FValues);
  gap := EffectiveGap;
  lo := FMin;
  hi := FMax;
  if hi < lo then hi := lo;
  { Between both neighbours, each kept MinGap away. }
  if (AIndex > 0) and (FValues[AIndex - 1] + gap > lo) then lo := FValues[AIndex - 1] + gap;
  if (AIndex < n - 1) and (FValues[AIndex + 1] - gap < hi) then hi := FValues[AIndex + 1] - gap;
  if AValue > hi then AValue := hi;
  if AValue < lo then AValue := lo;
  if FValues[AIndex] = AValue then Exit;
  FValues[AIndex] := AValue;
  Invalidate;
  DoThumbChange(AIndex);
  DoChange;
end;

procedure TTyCustomMultiTrackBar.DoThumbChange(AIndex: Integer);
begin
  if Assigned(FOnThumbChange) then FOnThumbChange(Self, AIndex);
end;

procedure TTyCustomMultiTrackBar.DoChange;
begin
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyCustomMultiTrackBar.SetMin(const AValue: Integer);
begin
  if FMin = AValue then Exit;
  FMin := AValue;
  if csLoading in ComponentState then Exit;
  Normalize(True);
  Invalidate;
end;

procedure TTyCustomMultiTrackBar.SetMax(const AValue: Integer);
begin
  if FMax = AValue then Exit;
  FMax := AValue;
  if csLoading in ComponentState then Exit;
  Normalize(True);
  Invalidate;
end;

procedure TTyCustomMultiTrackBar.SetMinGap(const AValue: Integer);
var
  g: Integer;
begin
  if AValue < 0 then g := 0 else g := AValue;
  if FMinGap = g then Exit;
  FMinGap := g;
  if csLoading in ComponentState then Exit;
  Normalize(True);
  Invalidate;
end;

procedure TTyCustomMultiTrackBar.SetSelectedThumb(AValue: Integer);
begin
  if (AValue < 0) or (AValue >= Length(FValues)) then AValue := -1;
  if FSelectedThumb = AValue then Exit;
  FSelectedThumb := AValue;
  Invalidate;
end;

procedure TTyCustomMultiTrackBar.Loaded;
begin
  inherited Loaded;
  { The values arrive in whatever order the form file lists them, possibly before Min and Max:
    settle them now, silently -- reading a form is not the user moving a thumb. }
  Normalize(False);
  if FSelectedThumb >= Length(FValues) then FSelectedThumb := -1;
  Invalidate;
end;

end.
