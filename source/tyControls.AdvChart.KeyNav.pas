unit tyControls.AdvChart.KeyNav;
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
    Tab / Shift+Tab    not the chart's: they leave the control

  With no focus item, any of the moving keys lands on the first series'
  first item (End on its last). A key with Ctrl, Alt or Shift held is not
  the chart's.

  PURE: LCLType for the key codes, Classes for TShiftState. }
interface

uses
  Classes, LCLType;

type
  TTyKbCommand = (kbcNone, kbcPrev, kbcNext, kbcPrevSeries, kbcNextSeries,
    kbcFirst, kbcLast, kbcPagePrev, kbcPageNext, kbcActivate, kbcClear);

  { a navigable series: its index among the option's series, and how many
    rows its view has }
  TTyKbSeries = record
    SeriesIndex: Integer;
    Count: Integer;
  end;
  TTyKbSeriesArray = array of TTyKbSeries;

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

end.
