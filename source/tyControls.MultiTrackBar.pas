unit tyControls.MultiTrackBar;
{$mode objfpc}{$H+}

{ Track bars with more than one thumb (#36): the ordered thumb model shared by TTyRangeTrackBar
  (one or more ranges) and TTyMultiTrackBar (several values).

  TTyCustomMultiTrackBar sits BESIDE TTyCustomTrackBar rather than under it: that class is built
  around a single Position. What the two share is the geometry (TyTrackThumbOffset /
  TyTrackPosFromOffset, TyTrackThumbLen, TyTrackSlideRect, TyTrackGrooveRect) and the tick band
  (TyLayoutTrackTicks / TyDrawTrackTicks), all unit-level in tyControls.TrackBar -- so a
  multi-thumb bar with one thumb at V draws exactly what a TTyTrackBar at Position V draws. }

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller,
  tyControls.TrackBar;

const
  { The theme keys of the parts a multi-thumb bar draws on top of TTyTrackBar's groove and
    thumb. A range's span is LCL's selection range, so it is #37's key; a styled stretch
    between two thumbs of TTyMultiTrackBar is resolved as TyTrackSegment.<its StyleClass>. }
  TyTrackSelectionKey = 'TyTrackSelection';
  TyTrackSegmentKey = 'TyTrackSegment';

type
  { A thumb moved, or was selected; AIndex is its place in ThumbValues (-1 = none selected). }
  TTyTrackThumbEvent = procedure(Sender: TObject; AIndex: Integer) of object;

  { THE MODEL. The thumbs are an ordered array of integers, FValues, that always holds:

      ascending, FValues[i+1] - FValues[i] >= MinGap, every value within Min..Max.

    SetThumbValue is the one way a single thumb moves, from code, the mouse or the keyboard: it
    clamps the value between its neighbours (each +/- MinGap) and Min..Max, and fires
    OnThumbChange(Self, AIndex) and OnChange only when the value actually changed.

    Normalize puts an arbitrary array back into that shape -- sorted, then pushed apart left to
    right and, where that runs past Max, back from the right. It runs when Min, Max or MinGap
    change and when a form has been read (Loaded); while a form is being read nothing is
    clamped and no event fires, so the order the .lfm lists the values in does not matter.

    A MinGap the range cannot hold -- (ThumbCount - 1) * MinGap > Max - Min -- does not raise and
    is not rewritten: the thumbs are placed with (Max - Min) div (ThumbCount - 1) between them
    instead, and MinGap keeps the value it was given, so widening the range later brings the
    full gap back.

    THE PICTURE. Back to front: the groove (TyTrackGroove), the segments -- the stretches of
    groove between two thumbs that SegmentStyle names a theme key for -- then the thumbs
    (TyTrackThumb, each with its own hover / active state, StyleClass and Color), then the
    ticks and their labels. Segment I runs from the centre of thumb I - 1 to the centre of thumb
    I; segment 0 starts at the Min end of the groove and segment ThumbCount ends at its Max end.

    What each thumb and segment looks like, and whether a thumb takes part in the interaction,
    is the final class's data (its collection items): the protected virtual Thumb* and
    SegmentStyle functions below are where it hands that over. Here every thumb is enabled,
    follows the theme and has no hint, and no segment is drawn.

    No right-to-left mirroring, as TTyTrackBar: the value axis runs by Orientation and Reversed
    only. }
  TTyCustomMultiTrackBar = class(TTyCustomControl)
  private
    FValues: array of Integer;
    FMin, FMax, FMinGap: Integer;
    FSelectedThumb: Integer;
    FOrientation: TTyTrackOrientation;
    FReversed: Boolean;
    FTickMarks: TTyTrackTickMark;
    FTickStyle: TTyTrackTickStyle;
    FManualTicks: array of Integer;
    FFrequency: Integer;
    FTickLabels: Boolean;
    { The label strip's thickness on one tick side, measured at paint time and cached for
      CalculatePreferredSize (as TTyTrackBar does). }
    FTickLabelPx: Integer;
    FOnFormatTickLabel: TTyTrackTickLabelEvent;
    FOnThumbChange: TTyTrackThumbEvent;
    FOnThumbSelect: TTyTrackThumbEvent;
    FOnChange: TNotifyEvent;
    function GetThumbCount: Integer;
    function GetThumbValue(AIndex: Integer): Integer;
    procedure SetMin(const AValue: Integer);
    procedure SetMax(const AValue: Integer);
    procedure SetMinGap(const AValue: Integer);
    procedure SetSelectedThumb(AValue: Integer);
    procedure SetOrientation(const AValue: TTyTrackOrientation);
    procedure SetReversed(const AValue: Boolean);
    procedure SetTickMarks(const AValue: TTyTrackTickMark);
    procedure SetTickStyle(const AValue: TTyTrackTickStyle);
    procedure SetFrequency(const AValue: Integer);
    procedure SetTickLabels(const AValue: Boolean);
    procedure SetOnFormatTickLabel(const AValue: TTyTrackTickLabelEvent);
    procedure CheckIndex(AIndex: Integer);
  protected
    { The thumb under a press (drawn active) and under the pointer (drawn hover); -1 = none. }
    FDragThumb: Integer;
    FHoverThumb: Integer;
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
    procedure DoThumbSelect(AIndex: Integer); virtual;
    procedure DoChange; virtual;
    procedure Loaded; override;

    { ---- The final classes' data, per thumb and per segment. ---- }
    { False: the thumb is drawn as usual but cannot be pressed, dragged, selected or moved from
      the keyboard -- a press on it does nothing at all. }
    function ThumbEnabled(AIndex: Integer): Boolean; virtual;
    { clDefault = the theme's colour. Anything else replaces the background the theme resolves
      for that thumb (in every state): a thumb's colour is data, like a colour picker's value. }
    function ThumbColor(AIndex: Integer): TColor; virtual;
    { Resolved as TyTrackThumb.<class>; '' = plain TyTrackThumb. }
    function ThumbStyleClass(AIndex: Integer): string; virtual;
    { What the control's hint says while the pointer is over this thumb; '' = the control's own. }
    function ThumbHint(AIndex: Integer): string; virtual;
    { Segment AIndex (0..ThumbCount, see the class comment) is filled when this returns True,
      with the background ATypeKey.AStyleClass resolves to. }
    function SegmentStyle(AIndex: Integer; out ATypeKey, AStyleClass: string): Boolean; virtual;

    { The value axis runs the other way: vertical (Max at the top, as TTyTrackBar) xor Reversed. }
    function Inverted: Boolean;
    { Device px of the track along the main axis -- what TyTrackThumbOffset calls AMainLen. }
    function MainLen: Integer;
    { Where thumb AIndex's thumb starts along the track, device px from the track's start. }
    function ThumbOffset(AIndex: Integer): Integer;
    { The thumb's centre along the track, device px from the track's start. }
    function ThumbCentre(AIndex: Integer): Integer;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    { Cross axis only, as TTyTrackBar: the thumb, the ticks and their labels. }
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    { Move one thumb; see the class comment. Out-of-range AIndex raises EListError. }
    procedure SetThumbValue(AIndex, AValue: Integer);
    { Thumb AIndex's HIT rectangle in client coordinates: its length along the track, the whole
      control across it -- the same rectangle TTyTrackBar.ThumbRect gives at Position = its
      value, so a pointer anywhere in the thumb's column grabs it. }
    function ThumbRect(AIndex: Integer): TRect;
    { Segment AIndex's span along the track at APPI, in client coordinates of the main axis
      (low..high whichever way the bar runs). False for an index outside 0..ThumbCount. Says
      nothing about whether the segment is drawn -- that is SegmentStyle's call. }
    function SegmentSpan(AIndex, APPI: Integer; out ALow, AHigh: Integer): Boolean;
    { Place / drop hand-placed ticks, drawn while TickStyle = ttsManual; as TTyTrackBar. }
    procedure SetTick(AValue: Integer);
    procedure ClearTicks;
    function TickCount: Integer;
    property ThumbCount: Integer read GetThumbCount;
    { Read-only here: a thumb moves through SetThumbValue or the final class's collection. }
    property ThumbValues[AIndex: Integer]: Integer read GetThumbValue;
    { The thumb the keyboard acts on; -1 = none. Kept within 0..ThumbCount - 1. A change fires
      OnThumbSelect. }
    property SelectedThumb: Integer read FSelectedThumb write SetSelectedThumb default -1;
    property MinGap: Integer read FMinGap write SetMinGap default 0;
    property Min: Integer read FMin write SetMin default 0;
    property Max: Integer read FMax write SetMax default 100;
    property Orientation: TTyTrackOrientation read FOrientation write SetOrientation default toHorizontal;
    property Reversed: Boolean read FReversed write SetReversed default False;
    property TickMarks: TTyTrackTickMark read FTickMarks write SetTickMarks default ttmBottomRight;
    property TickStyle: TTyTrackTickStyle read FTickStyle write SetTickStyle default ttsAuto;
    property Frequency: Integer read FFrequency write SetFrequency default 1;
    property TickLabels: Boolean read FTickLabels write SetTickLabels default False;
    property OnFormatTickLabel: TTyTrackTickLabelEvent read FOnFormatTickLabel write SetOnFormatTickLabel;
    property TabStop default True;
    property OnThumbChange: TTyTrackThumbEvent read FOnThumbChange write FOnThumbChange;
    property OnThumbSelect: TTyTrackThumbEvent read FOnThumbSelect write FOnThumbSelect;
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
  FDragThumb := -1;
  FHoverThumb := -1;
  FOrientation := toHorizontal;
  FTickMarks := ttmBottomRight;
  FTickStyle := ttsAuto;
  FFrequency := 1;
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
  if FDragThumb >= Length(FValues) then FDragThumb := -1;
  if FHoverThumb >= Length(FValues) then FHoverThumb := -1;
  if FSelectedThumb >= Length(FValues) then
  begin
    if csLoading in ComponentState then FSelectedThumb := -1
    else SetSelectedThumb(-1);
  end;
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

procedure TTyCustomMultiTrackBar.DoThumbSelect(AIndex: Integer);
begin
  if Assigned(FOnThumbSelect) then FOnThumbSelect(Self, AIndex);
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
  if not (csLoading in ComponentState) then DoThumbSelect(AValue);
end;

procedure TTyCustomMultiTrackBar.SetOrientation(const AValue: TTyTrackOrientation);
var
  w, h: Integer;
begin
  if FOrientation = AValue then Exit;
  FOrientation := AValue;
  { Swap the axis with the orientation, as TTyTrackBar (and LCL) do; not while reading a form,
    whose explicit bounds must win. }
  if not (csLoading in ComponentState) then
  begin
    w := Width; h := Height;
    if ((AValue = toVertical) and (w > h)) or ((AValue = toHorizontal) and (h > w)) then
      SetBounds(Left, Top, h, w);
  end;
  Invalidate;
end;

procedure TTyCustomMultiTrackBar.SetReversed(const AValue: Boolean);
begin
  if FReversed = AValue then Exit;
  FReversed := AValue;
  Invalidate;
end;

procedure TTyCustomMultiTrackBar.SetTickMarks(const AValue: TTyTrackTickMark);
begin
  if FTickMarks = AValue then Exit;
  FTickMarks := AValue;
  Invalidate;
end;

procedure TTyCustomMultiTrackBar.SetTickStyle(const AValue: TTyTrackTickStyle);
begin
  if FTickStyle = AValue then Exit;
  FTickStyle := AValue;
  Invalidate;
end;

procedure TTyCustomMultiTrackBar.SetFrequency(const AValue: Integer);
var
  f: Integer;
begin
  if AValue < 0 then f := 0 else f := AValue;
  if FFrequency = f then Exit;
  FFrequency := f;
  Invalidate;
end;

procedure TTyCustomMultiTrackBar.SetTickLabels(const AValue: Boolean);
begin
  if FTickLabels = AValue then Exit;
  FTickLabels := AValue;
  if not FTickLabels then FTickLabelPx := 0;
  Invalidate;
end;

procedure TTyCustomMultiTrackBar.SetOnFormatTickLabel(const AValue: TTyTrackTickLabelEvent);
begin
  FOnFormatTickLabel := AValue;
  if FTickLabels then Invalidate;
end;

procedure TTyCustomMultiTrackBar.SetTick(AValue: Integer);
var
  i: Integer;
begin
  if (AValue < FMin) or (AValue > FMax) then Exit;
  for i := 0 to High(FManualTicks) do
    if FManualTicks[i] = AValue then Exit;
  SetLength(FManualTicks, Length(FManualTicks) + 1);
  FManualTicks[High(FManualTicks)] := AValue;
  if FTickStyle = ttsManual then Invalidate;
end;

procedure TTyCustomMultiTrackBar.ClearTicks;
begin
  if Length(FManualTicks) = 0 then Exit;
  SetLength(FManualTicks, 0);
  if FTickStyle = ttsManual then Invalidate;
end;

function TTyCustomMultiTrackBar.TickCount: Integer;
begin
  Result := Length(FManualTicks);
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

function TTyCustomMultiTrackBar.ThumbEnabled(AIndex: Integer): Boolean;
begin
  Result := True;
end;

function TTyCustomMultiTrackBar.ThumbColor(AIndex: Integer): TColor;
begin
  Result := clDefault;
end;

function TTyCustomMultiTrackBar.ThumbStyleClass(AIndex: Integer): string;
begin
  Result := '';
end;

function TTyCustomMultiTrackBar.ThumbHint(AIndex: Integer): string;
begin
  Result := '';
end;

function TTyCustomMultiTrackBar.SegmentStyle(AIndex: Integer; out ATypeKey,
  AStyleClass: string): Boolean;
begin
  ATypeKey := '';
  AStyleClass := '';
  Result := False;
end;

function TTyCustomMultiTrackBar.Inverted: Boolean;
begin
  Result := (FOrientation = toVertical) xor FReversed;
end;

function TTyCustomMultiTrackBar.MainLen: Integer;
begin
  if FOrientation = toVertical then Result := ClientHeight
  else Result := ClientWidth;
  if Result < 1 then Result := 1;
end;

function TTyCustomMultiTrackBar.ThumbOffset(AIndex: Integer): Integer;
begin
  CheckIndex(AIndex);
  Result := TyTrackThumbOffset(MainLen, TyTrackThumbLen(Font.PixelsPerInch), FMin, FMax,
    FValues[AIndex], Inverted);
end;

function TTyCustomMultiTrackBar.ThumbCentre(AIndex: Integer): Integer;
begin
  Result := ThumbOffset(AIndex) + TyTrackThumbLen(Font.PixelsPerInch) div 2;
end;

function TTyCustomMultiTrackBar.ThumbRect(AIndex: Integer): TRect;
var
  TW, Off: Integer;
begin
  TW := TyTrackThumbLen(Font.PixelsPerInch);
  Off := ThumbOffset(AIndex);
  if FOrientation = toVertical then
    Result := Rect(0, Off, ClientWidth, Off + TW)
  else
    Result := Rect(Off, 0, Off + TW, ClientHeight);
end;

function TTyCustomMultiTrackBar.SegmentSpan(AIndex, APPI: Integer; out ALow,
  AHigh: Integer): Boolean;
var
  TW, MLen, a, b, n: Integer;
begin
  ALow := 0;
  AHigh := 0;
  n := Length(FValues);
  Result := (AIndex >= 0) and (AIndex <= n);
  if not Result then Exit;
  TW := TyTrackThumbLen(APPI);
  MLen := MainLen;
  { Each end is a thumb's centre; segment 0 starts and segment n ends at the groove's end on
    the Min / Max side, whichever end of the control that is. }
  if AIndex = 0 then
  begin
    if Inverted then a := MLen else a := 0;
  end
  else
    a := TyTrackThumbOffset(MLen, TW, FMin, FMax, FValues[AIndex - 1], Inverted) + TW div 2;
  if AIndex = n then
  begin
    if Inverted then b := 0 else b := MLen;
  end
  else
    b := TyTrackThumbOffset(MLen, TW, FMin, FMax, FValues[AIndex], Inverted) + TW div 2;
  if a <= b then begin ALow := a; AHigh := b; end
  else begin ALow := b; AHigh := a; end;
end;

procedure TTyCustomMultiTrackBar.CalculatePreferredSize(var PreferredWidth,
  PreferredHeight: Integer; WithThemeSpace: Boolean);
var
  S: TTyStyleSet;
  ppi, cross: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  { TTyTrackBar's sum, term by term: thumb, tick, label strip(s), padding. }
  cross := TyTrackThumbLen(ppi) + MulDiv(4, ppi, 96);
  if FTickLabels and (FTickLabelPx > 0) then
    if FTickMarks = ttmBoth then Inc(cross, 2 * FTickLabelPx)
    else Inc(cross, FTickLabelPx);
  Inc(cross, MulDiv(S.Padding.Top + S.Padding.Bottom, ppi, 96));
  if cross < 1 then cross := 1;
  if FOrientation = toVertical then
  begin
    PreferredWidth := cross;
    PreferredHeight := 0;
  end
  else
  begin
    PreferredWidth := 0;
    PreferredHeight := cross;
  end;
end;

procedure TTyCustomMultiTrackBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, St: TTyStyleSet;
  R, SlideR, GrooveR, SegR, ThumbR: TRect;
  Ticks: TTyTrackTicks;
  TW, MLen, Off, i, n, lo, hi, topIdx: Integer;
  key, cls: string;
  c: TColor;

  procedure DrawThumb(AIndex: Integer);
  var
    States: TTyStateSet;
  begin
    Off := TyTrackThumbOffset(MLen, TW, FMin, FMax, FValues[AIndex], Inverted);
    if FOrientation = toVertical then
      ThumbR := Rect(SlideR.Left, SlideR.Top + Off, SlideR.Right, SlideR.Top + Off + TW)
    else
      ThumbR := Rect(SlideR.Left + Off, SlideR.Top, SlideR.Left + Off + TW, SlideR.Bottom);
    States := [];
    if AIndex = FDragThumb then Include(States, tysActive)
    else if AIndex = FHoverThumb then Include(States, tysHover)
    else Include(States, tysNormal);
    { The thumb the keyboard drives, while the control has the focus: a theme can mark it. }
    if Focused and (AIndex = FSelectedThumb) then Include(States, tysFocused);
    St := ActiveController.Model.ResolveStyle('TyTrackThumb', ThumbStyleClass(AIndex), States);
    c := ThumbColor(AIndex);
    if c <> clDefault then
    begin
      c := ColorToRGB(c);
      St.Background := Default(TTyFill);
      St.Background.Kind := tfkSolid;
      St.Background.Color := TyRGB(Red(c), Green(c), Blue(c));
      Include(St.Present, tpBackground);
    end;
    if tpBackground in St.Present then
      P.FillBackground(ThumbR, St.Background, St.BorderRadius);
  end;

begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);

    TW := TyTrackThumbLen(APPI);
    if FOrientation = toVertical then MLen := R.Bottom - R.Top
    else MLen := R.Right - R.Left;
    if MLen < 1 then MLen := 1;

    { The tick band: the same inputs TTyTrackBar hands the shared layout. }
    Ticks := Default(TTyTrackTicks);
    Ticks.Orientation := FOrientation;
    Ticks.TickMarks := FTickMarks;
    Ticks.TickStyle := FTickStyle;
    Ticks.Frequency := FFrequency;
    Ticks.Manual := FManualTicks;
    Ticks.Min := FMin;
    Ticks.Max := FMax;
    Ticks.Invert := Inverted;
    Ticks.MainLen := MLen;
    Ticks.ThumbLen := TW;
    Ticks.Labels := FTickLabels;
    Ticks.FontName := S.FontName;
    Ticks.FontSize := ResolveFontSize(S);
    Ticks.FontWeight := S.FontWeight;
    Ticks.Color := S.TextColor;
    Ticks.Sender := Self;
    Ticks.OnFormatLabel := FOnFormatTickLabel;
    TyLayoutTrackTicks(P, Ticks);
    FTickLabelPx := Ticks.LabelBand;
    SlideR := TyTrackSlideRect(R, FOrientation, FTickMarks, Ticks.TickBand + Ticks.LabelBand, 0);

    St := ActiveController.Model.ResolveStyle('TyTrackGroove', '', []);
    GrooveR := TyTrackGrooveRect(SlideR, FOrientation, MLen,
      TyTrackGrooveThickness(P, ActiveController));
    if tpBackground in St.Present then
      P.FillBackground(GrooveR, St.Background, St.BorderRadius);

    { The segments the final class names a style for, groove-thick, centre to centre. }
    n := Length(FValues);
    for i := 0 to n do
    begin
      if not SegmentStyle(i, key, cls) or (key = '') then Continue;
      SegmentSpan(i, APPI, lo, hi);
      if hi <= lo then Continue;
      St := ActiveController.Model.ResolveStyle(key, cls, []);
      if not (tpBackground in St.Present) then Continue;
      if FOrientation = toVertical then
        SegR := Rect(GrooveR.Left, SlideR.Top + lo, GrooveR.Right, SlideR.Top + hi)
      else
        SegR := Rect(SlideR.Left + lo, GrooveR.Top, SlideR.Left + hi, GrooveR.Bottom);
      P.FillBackground(SegR, St.Background, St.BorderRadius);
    end;

    { The thumbs in order, the one being dragged (else the selected one) last so it stays on
      top where two overlap. }
    topIdx := FDragThumb;
    if (topIdx < 0) or (topIdx >= n) then topIdx := FSelectedThumb;
    if topIdx >= n then topIdx := -1;
    for i := 0 to n - 1 do
      if i <> topIdx then DrawThumb(i);
    if topIdx >= 0 then DrawThumb(topIdx);

    TyDrawTrackTicks(P, R, Ticks);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCustomMultiTrackBar.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
