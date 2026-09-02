unit tyControls.AdvChart.Types;
{$mode objfpc}{$H+}
{ TTyAdvanceChart — shared geometry primitives.

  DOUBLE, not Single. The whole geometry layer is double precision because a
  coordinate round trip (value -> px -> value) has to survive data ranges that
  span many decades; Single loses that at about seven digits, and the round-trip
  tolerance this layer promises is half a pixel on any extent. Rounding to device
  integers is the PAINTER's job, at the last moment.

  This unit is PURE: SysUtils and Math only. No Controls, no Graphics, no LCL, no
  BGRA, no handle. Everything below is headless-testable by construction. }
interface
uses SysUtils, Math;

type
  TTyDoubleArray = array of Double;

  { A point in device px, relative to the control's top-left. }
  TTyPointF = record X, Y: Double; end;

  { A rect in device px. Left<=Right and Top<=Bottom is an INVARIANT that
    TyRectFIsValid checks — it is deliberately NOT enforced by the constructor,
    because a reversed rect is a real signal (an axis whose band collapsed) that
    callers must be able to see rather than have silently normalised away. }
  TTyRectF = record Left, Top, Right, Bottom: Double; end;

  { A closed value range. TyRange DOES normalise, because a reversed VALUE range
    is always a caller mistake — an inverse axis is expressed by the PIXEL extent
    being reversed, never by the value extent. }
  TTyRange = record Start, Stop: Double; end;

  { An object that implements interfaces WITHOUT reference counting; lifetime is
    owned by whoever created it, exactly as TComponent does it.

    The chart's coordinate systems are owned by the chart, while the things that
    hold a reference to them (a box container, a series' axis binding) are
    short-lived temporaries. Under refcounting, the last temporary to go out of
    scope would free a live coordinate system. Containers and mappers, which
    genuinely are owned by their references, stay on TInterfacedObject. }
  TTyNonRefCountedObject = class(TObject, IUnknown)
  protected
    function QueryInterface({$IFDEF FPC_HAS_CONSTREF}constref{$ELSE}const{$ENDIF} IID: TGUID; out Obj): HResult;
      {$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
    function _AddRef: Integer; {$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
    function _Release: Integer; {$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
  end;

  { Where a text box sits on the anchor it is placed at. Deliberately NOT LCL's
    TAlignment/TTextLayout: those live in Classes/Graphics, and pulling either in
    would end this unit's independence from the LCL. The bridge that talks to the
    painter converts. }
  TTyTextAnchorH = (tahLeft, tahCentre, tahRight);
  TTyTextAnchorV = (tavTop, tavMiddle, tavBottom);

  { One line of text measured, DEVICE px, UNROTATED.

    Injected rather than called directly, for two reasons. It keeps this layer
    free of the painter, and so of the LCL. And -- the one that actually matters
    -- it makes axis layout testable against a DETERMINISTIC measurer: real font
    metrics differ by machine and by widgetset, so an axis test written against
    them asserts the local font as much as it asserts the algorithm. }
  ITyTextMeasurer = interface
    ['{4C7E2A19-6B03-4F5D-9E81-2D6A08C3B45F}']
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
  end;

  TTyStringArray = array of string;
  TTyIntegerArray = array of Integer;

  { Which edge of a plot rect an axis draws on. Lives here rather than in
    Layout, where it started, because Coord needs it too and Layout already
    uses Coord -- naming it upward would be a cycle. A bare enum with no
    dependencies is exactly what this unit is for; TTyTextAnchorH is here for
    the same reason. }
  TTyAxisSide = (asLeft, asRight, asTop, asBottom);

function TyPointF(AX, AY: Double): TTyPointF;
function TyRectF(ALeft, ATop, ARight, ABottom: Double): TTyRectF;
function TyRange(AStart, AStop: Double): TTyRange;

function TyRectFWidth(const AR: TTyRectF): Double;
function TyRectFHeight(const AR: TTyRectF): Double;
{ Valid = no NaN on any edge AND non-reversed. A zero-area rect IS valid. }
function TyRectFIsValid(const AR: TTyRectF): Boolean;
{ Half-open on Right/Bottom so two adjacent bands never both claim a pixel.
  NOTE this is the DATUM-CELL rule. "Is this point in the plot area" is a
  different question with a different answer — see TTyCartesian2D.ContainPoint,
  which closes the far edges on purpose. }
function TyRectFContains(const AR: TTyRectF; const AP: TTyPointF): Boolean;

function TyRangeSpan(const AR: TTyRange): Double;
{ Closed on both ends — an axis extent's endpoints belong to the axis. }
function TyRangeContains(const AR: TTyRange; AValue: Double): Boolean;

{ The single spelling of "no answer". Never return an empty/zero rect for this:
  a zero rect at the origin is indistinguishable from a legitimately collapsed
  band, and that ambiguity is exactly what TyChartNoHit had to exist to avoid. }
function TyInvalidPointF: TTyPointF;
function TyInvalidRectF: TTyRectF;

implementation

{ ==================== TTyNonRefCountedObject ==================== }

function TTyNonRefCountedObject.QueryInterface(
  {$IFDEF FPC_HAS_CONSTREF}constref{$ELSE}const{$ENDIF} IID: TGUID; out Obj): HResult;
  {$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
begin
  if GetInterface(IID, Obj) then
    Result := S_OK
  else
    Result := HResult($80004002);   // E_NOINTERFACE
end;

function TTyNonRefCountedObject._AddRef: Integer; {$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
begin
  Result := -1;
end;

function TTyNonRefCountedObject._Release: Integer; {$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
begin
  Result := -1;
end;

{ ==================== constructors ==================== }

function TyPointF(AX, AY: Double): TTyPointF;
begin
  Result.X := AX;
  Result.Y := AY;
end;

function TyRectF(ALeft, ATop, ARight, ABottom: Double): TTyRectF;
begin
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Right := ARight;
  Result.Bottom := ABottom;
end;

function TyRange(AStart, AStop: Double): TTyRange;
begin
  if AStop < AStart then
  begin
    Result.Start := AStop;
    Result.Stop := AStart;
  end
  else
  begin
    Result.Start := AStart;
    Result.Stop := AStop;
  end;
end;

{ ==================== queries ==================== }

function TyRectFWidth(const AR: TTyRectF): Double;
begin
  Result := AR.Right - AR.Left;
end;

function TyRectFHeight(const AR: TTyRectF): Double;
begin
  Result := AR.Bottom - AR.Top;
end;

function TyRectFIsValid(const AR: TTyRectF): Boolean;
begin
  Result := (not IsNan(AR.Left)) and (not IsNan(AR.Top))
        and (not IsNan(AR.Right)) and (not IsNan(AR.Bottom))
        and (AR.Right >= AR.Left) and (AR.Bottom >= AR.Top);
end;

function TyRectFContains(const AR: TTyRectF; const AP: TTyPointF): Boolean;
begin
  { NaN first, and not as politeness: FPC compiles an ordered comparison to
    COMISD, which SIGNALS on a quiet NaN, so `NaN >= x` raises EInvalidOp rather
    than answering False. TyInvalidPointF is NaN on both axes and is this
    library's own spelling of "no answer", so a hit test on one would crash
    instead of missing. }
  if IsNan(AP.X) or IsNan(AP.Y) then Exit(False);
  Result := (AP.X >= AR.Left) and (AP.X < AR.Right)
        and (AP.Y >= AR.Top) and (AP.Y < AR.Bottom);
end;

function TyRangeSpan(const AR: TTyRange): Double;
begin
  Result := Abs(AR.Stop - AR.Start);
end;

function TyRangeContains(const AR: TTyRange; AValue: Double): Boolean;
begin
  { Same reason as TyRectFContains: an ordered comparison against NaN raises
    rather than answering False. NaN is this layer's no-data value, so asking
    whether a missing value is on an axis is an ordinary question with an
    ordinary answer -- no. }
  if IsNan(AValue) then Exit(False);
  Result := (AValue >= AR.Start) and (AValue <= AR.Stop);
end;

function TyInvalidPointF: TTyPointF;
begin
  Result.X := NaN;
  Result.Y := NaN;
end;

function TyInvalidRectF: TTyRectF;
begin
  Result.Left := NaN;
  Result.Top := NaN;
  Result.Right := NaN;
  Result.Bottom := NaN;
end;

end.
