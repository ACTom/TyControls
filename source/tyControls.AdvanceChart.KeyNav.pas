unit tyControls.AdvanceChart.KeyNav;
{$mode objfpc}{$H+}
{ THE CHART'S KEYBOARD [Batch 144]: which key does what, and where a key
  moves the keyboard focus item. Upstream ECharts has no keyboard at all --
  its accessibility is the aria description and the decals -- so this is the
  port's own design, kept small and predictable:

    Left / Right       the previous / next item of the series, in data order
                       (the view's rows, after any dataZoom filter); no wrap
    Up / Down          the previous / next series that has items, at the
                       same row (clamped to the series' last row)
    Home / End         the series' first / last item
    PageUp / PageDown  a step of a tenth of the series back / forward
                       (at least one), clamped to its ends
    Enter / Space      activate: the item's select (see the control)
    Escape             clear the focus item
    Tab / Shift+Tab    the chart's next / previous focus stop (below); off
                       the last (first) stop they leave the control

  With no focus item, any of the moving keys lands on the first series'
  first item (End on its last). A key with Ctrl, Alt or Shift held is not
  the chart's. [F5] A graph's edges are a list of their own, after the
  graph's nodes: Up / Down reach them as they reach the next series.

  [F5] THE FOCUS STOPS. Inside the control the keyboard has stops, in this
  order -- the data items (the walk above), the markers, each geo's
  regions, each legend, each visualMap (a continuous one with handles is
  two stops, one per handle, as a two-thumb slider is), each dataZoom
  (slider or inside), the timeline, each toolbox, each brush -- the ones
  the chart has. Tab moves to the next stop and Shift+Tab to the previous,
  as in a composite control; past the last (before the first) the key is
  left to the form and the focus leaves. A component stop's parts (a
  legend's items, a toolbox's icons, ...) are walked with the arrows
  (TyKbPartMove); what a key does on a component is the control's.

  PURE: LCLType for the key codes, Classes for TShiftState. }
interface

uses
  Classes, LCLType;

type
  TTyKbCommand = (kbcNone, kbcPrev, kbcNext, kbcPrevSeries, kbcNextSeries,
    kbcFirst, kbcLast, kbcPagePrev, kbcPageNext, kbcActivate, kbcClear,
    { [F5] a component's Shift keys: Shift+Left / Down shrinks, Shift+Right
      / Up grows, Shift+Home grows to the start, Shift+End to the end }
    kbcShrink, kbcGrow, kbcGrowStart, kbcGrowEnd);

  { a navigable series: its index among the option's series, and how many
    rows its view has }
  TTyKbSeries = record
    SeriesIndex: Integer;
    Count: Integer;
    { [F5] the entry is a graph's edge list, not its nodes }
    Edge: Boolean;
  end;
  TTyKbSeriesArray = array of TTyKbSeries;

  { [F5] THE FOCUS STOPS, in Tab order }
  TTyKbStopKind = (ksItems, ksMarkers, ksGeo, ksLegend, ksVisualMap,
    ksDataZoom, ksTimeline, ksToolbox, ksBrush);
  { a stop: its kind, the component's index (0 for the items, the markers
    and the timeline), and a sub-stop (a continuous visualMap's handle) }
  TTyKbStop = record
    Kind: TTyKbStopKind;
    Index: Integer;
    Sub: Integer;
  end;
  TTyKbStopArray = array of TTyKbStop;

{ the command a key is, kbcNone for a key the chart does not use }
function TyKbCommandOf(AKey: Word; AShift: TShiftState): TTyKbCommand;

{ whether the command moves the focus item (the arrows, Home / End and the
  page keys) -- the keys a focused chart always takes, even with nothing to
  move to, so that they never fall through to the form's focus navigation }
function TyKbIsMove(ACmd: TTyKbCommand): Boolean;

{ a tenth of ACount, rounded up, at least 1 }
function TyKbPageStep(ACount: Integer): Integer;

{ The item a moving command leads to from (APos, ARow) -- APos the position
  in ASeries, -1 for no focus item. True, with APos and ARow the new item,
  when there is one and it differs from where the focus was; False and both
  unchanged otherwise. Series with no rows are skipped. }
function TyKbMove(const ASeries: TTyKbSeriesArray; ACmd: TTyKbCommand;
  var APos, ARow: Integer): Boolean;

{ ==== [F5] the focus stops and the components ==== }

function TyKbStop(AKind: TTyKbStopKind; AIndex, ASub: Integer): TTyKbStop;
function TyKbSameStop(const A, B: TTyKbStop): Boolean;
{ where AStop is in AStops; -1 when it is not there }
function TyKbStopPos(const AStops: TTyKbStopArray; const AStop: TTyKbStop): Integer;

{ whether the key is the chart's Tab: Tab with nothing but Shift held }
function TyKbIsTab(AKey: Word; AShift: TShiftState): Boolean;

{ Tab (Shift+Tab with ABackward) from the stop at APos of ACount: True and
  ANext the stop it moves to, False when it leaves the control -- past the
  last stop, before the first, or with no stops at all. A position that is
  no stop's (-1) counts as the first. }
function TyKbTab(ACount, APos: Integer; ABackward: Boolean; out ANext: Integer): Boolean;

{ the command a key is on a component stop: TyKbCommandOf's, Up / Down
  included, and the Shift keys (kbcShrink ...); Space and Enter are both
  kbcActivate here too -- the control tells them apart where it must }
function TyKbComponentCommandOf(AKey: Word; AShift: TShiftState): TTyKbCommand;

{ whether a key is one a focused chart always takes on a component stop,
  acted on or not: the arrows, Home / End and the page keys, with or
  without Shift -- left over, LCL's DoArrowKey would hand the focus to a
  sibling }
function TyKbIsComponentMove(ACmd: TTyKbCommand): Boolean;

{ A component's parts in a row: Left / Up the previous, Right / Down the
  next, Home / End the first / last, the page keys a tenth (at least one);
  no wrap. APart -1 (none yet) lands on the first part (End on the last).
  True, APart the new part, when it moved. }
function TyKbPartMove(ACount: Integer; ACmd: TTyKbCommand; var APart: Integer): Boolean;

implementation

function TyKbCommandOf(AKey: Word; AShift: TShiftState): TTyKbCommand;
begin
  Result := kbcNone;
  if AShift * [ssCtrl, ssAlt, ssShift, ssMeta] <> [] then Exit;
  case AKey of
    VK_LEFT: Result := kbcPrev;
    VK_RIGHT: Result := kbcNext;
    VK_UP: Result := kbcPrevSeries;
    VK_DOWN: Result := kbcNextSeries;
    VK_HOME: Result := kbcFirst;
    VK_END: Result := kbcLast;
    VK_PRIOR: Result := kbcPagePrev;
    VK_NEXT: Result := kbcPageNext;
    VK_RETURN, VK_SPACE: Result := kbcActivate;
    VK_ESCAPE: Result := kbcClear;
  end;
end;

function TyKbIsMove(ACmd: TTyKbCommand): Boolean;
begin
  Result := ACmd in [kbcPrev, kbcNext, kbcPrevSeries, kbcNextSeries,
    kbcFirst, kbcLast, kbcPagePrev, kbcPageNext];
end;

function TyKbPageStep(ACount: Integer): Integer;
begin
  Result := (ACount + 9) div 10;
  if Result < 1 then Result := 1;
end;

function TyKbMove(const ASeries: TTyKbSeriesArray; ACmd: TTyKbCommand;
  var APos, ARow: Integer): Boolean;
var
  p, r, n, i: Integer;
begin
  Result := False;
  if not TyKbIsMove(ACmd) then Exit;
  { NO FOCUS ITEM YET, or one that no longer exists: the first series that
    has rows, at its first row -- or its last for End }
  if (APos < 0) or (APos > High(ASeries)) or (ASeries[APos].Count <= 0)
    or (ARow < 0) or (ARow >= ASeries[APos].Count) then
  begin
    for i := 0 to High(ASeries) do
      if ASeries[i].Count > 0 then
      begin
        APos := i;
        if ACmd = kbcLast then ARow := ASeries[i].Count - 1 else ARow := 0;
        Exit(True);
      end;
    Exit;
  end;
  p := APos;
  r := ARow;
  n := ASeries[p].Count;
  case ACmd of
    kbcPrev: if r > 0 then Dec(r);
    kbcNext: if r < n - 1 then Inc(r);
    kbcFirst: r := 0;
    kbcLast: r := n - 1;
    kbcPagePrev:
      begin
        Dec(r, TyKbPageStep(n));
        if r < 0 then r := 0;
      end;
    kbcPageNext:
      begin
        Inc(r, TyKbPageStep(n));
        if r > n - 1 then r := n - 1;
      end;
    kbcPrevSeries:
      begin
        i := p - 1;
        while (i >= 0) and (ASeries[i].Count <= 0) do Dec(i);
        if i >= 0 then p := i;
      end;
    kbcNextSeries:
      begin
        i := p + 1;
        while (i <= High(ASeries)) and (ASeries[i].Count <= 0) do Inc(i);
        if i <= High(ASeries) then p := i;
      end;
  end;
  if p <> APos then
    if r > ASeries[p].Count - 1 then r := ASeries[p].Count - 1;
  if (p = APos) and (r = ARow) then Exit;
  APos := p;
  ARow := r;
  Result := True;
end;

function TyKbStop(AKind: TTyKbStopKind; AIndex, ASub: Integer): TTyKbStop;
begin
  Result.Kind := AKind;
  Result.Index := AIndex;
  Result.Sub := ASub;
end;

function TyKbSameStop(const A, B: TTyKbStop): Boolean;
begin
  Result := (A.Kind = B.Kind) and (A.Index = B.Index) and (A.Sub = B.Sub);
end;

function TyKbStopPos(const AStops: TTyKbStopArray; const AStop: TTyKbStop): Integer;
var i: Integer;
begin
  for i := 0 to High(AStops) do
    if TyKbSameStop(AStops[i], AStop) then Exit(i);
  Result := -1;
end;

function TyKbIsTab(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := (AKey = VK_TAB) and (AShift * [ssCtrl, ssAlt, ssMeta] = []);
end;

function TyKbTab(ACount, APos: Integer; ABackward: Boolean; out ANext: Integer): Boolean;
var p: Integer;
begin
  ANext := -1;
  Result := False;
  if ACount <= 0 then Exit;
  p := APos;
  if (p < 0) or (p >= ACount) then p := 0;
  if ABackward then
  begin
    if p = 0 then Exit;
    ANext := p - 1;
  end
  else
  begin
    if p >= ACount - 1 then Exit;
    ANext := p + 1;
  end;
  Result := True;
end;

function TyKbComponentCommandOf(AKey: Word; AShift: TShiftState): TTyKbCommand;
begin
  Result := kbcNone;
  if AShift * [ssCtrl, ssAlt, ssMeta] <> [] then Exit;
  if ssShift in AShift then
  begin
    case AKey of
      VK_LEFT, VK_DOWN: Result := kbcShrink;
      VK_RIGHT, VK_UP: Result := kbcGrow;
      VK_HOME: Result := kbcGrowStart;
      VK_END: Result := kbcGrowEnd;
    end;
    Exit;
  end;
  Result := TyKbCommandOf(AKey, AShift);
end;

function TyKbIsComponentMove(ACmd: TTyKbCommand): Boolean;
begin
  Result := TyKbIsMove(ACmd) or (ACmd in [kbcShrink, kbcGrow, kbcGrowStart, kbcGrowEnd]);
end;

function TyKbPartMove(ACount: Integer; ACmd: TTyKbCommand; var APart: Integer): Boolean;
var p: Integer;
begin
  Result := False;
  if (ACount <= 0) or not TyKbIsMove(ACmd) then Exit;
  if (APart < 0) or (APart >= ACount) then
  begin
    if ACmd = kbcLast then APart := ACount - 1 else APart := 0;
    Exit(True);
  end;
  p := APart;
  case ACmd of
    kbcPrev, kbcPrevSeries: if p > 0 then Dec(p);
    kbcNext, kbcNextSeries: if p < ACount - 1 then Inc(p);
    kbcFirst: p := 0;
    kbcLast: p := ACount - 1;
    kbcPagePrev:
      begin
        Dec(p, TyKbPageStep(ACount));
        if p < 0 then p := 0;
      end;
    kbcPageNext:
      begin
        Inc(p, TyKbPageStep(ACount));
        if p > ACount - 1 then p := ACount - 1;
      end;
  end;
  if p = APart then Exit;
  APart := p;
  Result := True;
end;

end.
