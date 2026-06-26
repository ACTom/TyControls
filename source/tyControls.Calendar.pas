unit tyControls.Calendar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, DateUtils, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base;

type
  TTyWeekDay = (wdSunday, wdMonday, wdTuesday, wdWednesday, wdThursday,
                wdFriday, wdSaturday);
  TTyCalView  = (cvmDays, cvmMonths, cvmYears, cvmDecades);
  TTyDateGrid = array[0..41] of TDateTime;   // 6 rows x 7 cols

  { Array of 7 day-of-week indices (0=Sunday .. 6=Saturday) in display order
    starting at AFirst. }
  TTyWeekdayOrderArray = array[0..6] of Integer;

{ Returns the 7 day-of-week indices in display order starting at AFirst.
  Result[i] = (Ord(AFirst) + i) mod 7. }
function TyWeekdayOrder(AFirst: TTyWeekDay): TTyWeekdayOrderArray;

{ Builds a 42-cell (6x7) month grid for AYear/AMonth, column 0 = AFirst weekday.
  Cells before the 1st and after the last day are filled with dates from the
  adjacent months so the grid is always exactly 42 consecutive days. }
function TyCalendarMonthGrid(AYear, AMonth: Word;
  AFirst: TTyWeekDay): TTyDateGrid;

{ Returns True when DateOf(ADate) is within [AMin, AMax].
  AMin=0 means no lower bound; AMax=0 means no upper bound. }
function TyCalendarInRange(ADate, AMin, AMax: TDateTime): Boolean;

{ Clamps ADate into [AMin, AMax].
  AMin=0 / AMax=0 mean unbounded on that side. }
function TyCalendarClampDate(ADate, AMin, AMax: TDateTime): TDateTime;

{ Returns the start year of the decade containing AYear. }
function TyDecadeStart(AYear: Integer): Integer;

{ Returns the ISO 8601 week number of ADate. }
function TyISOWeekNumber(ADate: TDateTime): Integer;

{ Pure hit-test helper: returns the 0-based cell index at (X,Y) within AGridRect,
  or -1 outside. ACols=7, ARows=6 for a standard month grid. }
function TyCalendarHitCell(const AGridRect: TRect; ACols, ARows, X, Y: Integer): Integer;

{ Zoom-out: Days→Months→Years→Decades (capped at Decades). }
function TyCalendarZoomOut(AView: TTyCalView): TTyCalView;

{ Zoom-in: Decades→Years→Months→Days (capped at Days). }
function TyCalendarZoomIn(AView: TTyCalView): TTyCalView;

type
  TTyCalendar = class(TTyCustomControl)
  private
    FDate: TDateTime;
    FMinDate: TDateTime;
    FMaxDate: TDateTime;
    FFirstDayOfWeek: TTyWeekDay;
    FWeekNumbers: Boolean;
    FShowToday: Boolean;
    FReadOnly: Boolean;
    FViewYear: Word;
    FViewMonth: Word;
    FViewMode: TTyCalView;           // transient UI state, not published
    FOnChange: TNotifyEvent;
    FOnAccept: TNotifyEvent;
    FOnViewChange: TNotifyEvent;
    procedure SetDate(AValue: TDateTime);
    procedure SetMinDate(AValue: TDateTime);
    procedure SetMaxDate(AValue: TDateTime);
    procedure SetFirstDayOfWeek(AValue: TTyWeekDay);
    procedure SetWeekNumbers(AValue: Boolean);
    procedure SetShowToday(AValue: Boolean);
    procedure SetReadOnly(AValue: Boolean);
    { Moves the view to a different month, clamping to valid year/month range. }
    procedure SetViewMonth(AYear: Integer; AMonth: Integer);
    { Selects a cell date (used by keyboard), fires OnChange if changed. }
    procedure SelectDate(ANewDate: TDateTime);
    { Changes ViewMode and fires OnViewChange. }
    procedure ChangeViewMode(ANewMode: TTyCalView);
    { Computes layout metrics given current size + APPI.
      HeaderH   = arrow+title band height (device px)
      WeekdayH  = weekday-names row height (device px)
      WkNumW    = week-number column width (device px; 0 if WeekNumbers=False)
      ColW      = cell width (device px)
      RowH      = cell row height (device px)
      GridRect  = full 6x7 grid area in ARect-local coords }
    procedure CalcLayout(const ARect: TRect; APPI: Integer;
      out HeaderH, WeekdayH, WkNumW, ColW, RowH: Integer; out GridRect: TRect);
    { Computes a 4x3 grid rect for drill-down views (Months/Years/Decades).
      Returns the grid rect that occupies the area below the header. }
    procedure CalcLayout4x3(const ARect: TRect; APPI: Integer;
      out HeaderH, ColW, RowH: Integer; out GridRect: TRect);
    { Render the Months view. }
    procedure RenderMonthsView(P: TTyPainter; const ARect: TRect; APPI: Integer;
      const S: TTyStyleSet; HeaderH, ColW, RowH: Integer; const GridRect: TRect);
    { Render the Years view. }
    procedure RenderYearsView(P: TTyPainter; const ARect: TRect; APPI: Integer;
      const S: TTyStyleSet; HeaderH, ColW, RowH: Integer; const GridRect: TRect);
    { Render the Decades view. }
    procedure RenderDecadesView(P: TTyPainter; const ARect: TRect; APPI: Integer;
      const S: TTyStyleSet; HeaderH, ColW, RowH: Integer; const GridRect: TRect);
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    { Expose RenderTo publicly for tests and embedding. }
    procedure RenderToPublic(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { Current drill-down view (transient UI state, not published). }
    property ViewMode: TTyCalView read FViewMode;
    { Current view anchor month (1-12, transient UI state). }
    property ViewMonth: Word read FViewMonth;
    { Current view anchor year (transient UI state). }
    property ViewYear: Word read FViewYear;
  published
    property Date: TDateTime read FDate write SetDate;
    property MinDate: TDateTime read FMinDate write SetMinDate;
    property MaxDate: TDateTime read FMaxDate write SetMaxDate;
    property FirstDayOfWeek: TTyWeekDay read FFirstDayOfWeek write SetFirstDayOfWeek default wdSunday;
    property WeekNumbers: Boolean read FWeekNumbers write SetWeekNumbers default False;
    property ShowToday: Boolean read FShowToday write SetShowToday default True;
    property ReadOnly: Boolean read FReadOnly write SetReadOnly default False;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    { Fires when the user definitively accepts the current date (Enter/Space key
      or a day-cell mouse click). A hosting popup should close on this event, not
      on OnChange, so arrow-navigation inside the dropdown does not close it. }
    property OnAccept: TNotifyEvent read FOnAccept write FOnAccept;
    { Fires when ViewMode changes (zoom in/out). }
    property OnViewChange: TNotifyEvent read FOnViewChange write FOnViewChange;
    property Align;
    property Anchors;
    property Font;
    property StyleClass;
    property Controller;
    property TabStop default True;
  end;

implementation

{ TyWeekdayOrder }

function TyWeekdayOrder(AFirst: TTyWeekDay): TTyWeekdayOrderArray;
var
  i: Integer;
begin
  for i := 0 to 6 do
    Result[i] := (Ord(AFirst) + i) mod 7;
end;

{ TyCalendarMonthGrid }

function TyCalendarMonthGrid(AYear, AMonth: Word;
  AFirst: TTyWeekDay): TTyDateGrid;
var
  FirstOfMonth: TDateTime;
  DowFirst: Integer;
  LeadCells: Integer;
  StartDate: TDateTime;
  i: Integer;
begin
  FirstOfMonth := EncodeDate(AYear, AMonth, 1);
  // DayOfWeek: 1=Sun..7=Sat  ->  0=Sun..6=Sat
  DowFirst := DayOfWeek(FirstOfMonth) - 1;
  LeadCells := (DowFirst - Ord(AFirst) + 7) mod 7;
  StartDate := IncDay(FirstOfMonth, -LeadCells);
  for i := 0 to 41 do
    Result[i] := IncDay(StartDate, i);
end;

{ TyCalendarInRange }

function TyCalendarInRange(ADate, AMin, AMax: TDateTime): Boolean;
var
  D: TDateTime;
begin
  D := DateOf(ADate);
  Result :=
    ((AMin = 0) or (D >= DateOf(AMin))) and
    ((AMax = 0) or (D <= DateOf(AMax)));
end;

{ TyCalendarClampDate }

function TyCalendarClampDate(ADate, AMin, AMax: TDateTime): TDateTime;
begin
  Result := ADate;
  if (AMin <> 0) and (DateOf(Result) < DateOf(AMin)) then
    Result := AMin;
  if (AMax <> 0) and (DateOf(Result) > DateOf(AMax)) then
    Result := AMax;
end;

{ TyDecadeStart }

function TyDecadeStart(AYear: Integer): Integer;
begin
  Result := (AYear div 10) * 10;
end;

{ TyISOWeekNumber }

function TyISOWeekNumber(ADate: TDateTime): Integer;
begin
  Result := WeekOfTheYear(ADate);
end;

{ TyCalendarZoomOut }

function TyCalendarZoomOut(AView: TTyCalView): TTyCalView;
begin
  case AView of
    cvmDays:    Result := cvmMonths;
    cvmMonths:  Result := cvmYears;
    cvmYears:   Result := cvmDecades;
    cvmDecades: Result := cvmDecades;   // already at the top — cap
  else
    Result := cvmDecades;
  end;
end;

{ TyCalendarZoomIn }

function TyCalendarZoomIn(AView: TTyCalView): TTyCalView;
begin
  case AView of
    cvmDecades: Result := cvmYears;
    cvmYears:   Result := cvmMonths;
    cvmMonths:  Result := cvmDays;
    cvmDays:    Result := cvmDays;      // already at the bottom — cap
  else
    Result := cvmDays;
  end;
end;

{ TyCalendarHitCell }

function TyCalendarHitCell(const AGridRect: TRect; ACols, ARows, X, Y: Integer): Integer;
var
  gw, gh, col, row: Integer;
begin
  Result := -1;
  if (ACols <= 0) or (ARows <= 0) then Exit;
  gw := AGridRect.Right  - AGridRect.Left;
  gh := AGridRect.Bottom - AGridRect.Top;
  if (gw <= 0) or (gh <= 0) then Exit;
  if (X < AGridRect.Left) or (X >= AGridRect.Right) or
     (Y < AGridRect.Top)  or (Y >= AGridRect.Bottom) then Exit;
  col := (X - AGridRect.Left) * ACols div gw;
  row := (Y - AGridRect.Top)  * ARows div gh;
  if (col < 0) or (col >= ACols) or (row < 0) or (row >= ARows) then Exit;
  Result := row * ACols + col;
end;

{ TTyCalendar }

constructor TTyCalendar.Create(AOwner: TComponent);
var
  dy, dm, dd: Word;
begin
  inherited Create(AOwner);
  FDate         := DateOf(Now);
  FMinDate      := 0;
  FMaxDate      := 0;
  FFirstDayOfWeek := wdSunday;
  FWeekNumbers  := False;
  FShowToday    := True;
  FReadOnly     := False;
  FViewMode     := cvmDays;
  TabStop       := True;
  Width         := 240;
  Height        := 220;
  DecodeDate(FDate, dy, dm, dd);
  FViewYear  := dy;
  FViewMonth := dm;
end;

function TTyCalendar.GetStyleTypeKey: string;
begin
  Result := 'TyCalendar';
end;

procedure TTyCalendar.SetDate(AValue: TDateTime);
var
  clamped: TDateTime;
  dy, dm, dd: Word;
begin
  clamped := DateOf(TyCalendarClampDate(AValue, FMinDate, FMaxDate));
  if DateOf(FDate) = clamped then Exit;
  FDate := clamped;
  DecodeDate(FDate, dy, dm, dd);
  FViewYear  := dy;
  FViewMonth := dm;
  Invalidate;
end;

procedure TTyCalendar.SetMinDate(AValue: TDateTime);
begin
  if FMinDate = AValue then Exit;
  FMinDate := AValue;
  SetDate(FDate);   // re-clamp to new bounds (SetDate clamps + invalidates if date changed)
  Invalidate;       // always repaint: enabled/disabled cell appearance changed
end;

procedure TTyCalendar.SetMaxDate(AValue: TDateTime);
begin
  if FMaxDate = AValue then Exit;
  FMaxDate := AValue;
  SetDate(FDate);   // re-clamp to new bounds (SetDate clamps + invalidates if date changed)
  Invalidate;       // always repaint: enabled/disabled cell appearance changed
end;

procedure TTyCalendar.SetFirstDayOfWeek(AValue: TTyWeekDay);
begin
  if FFirstDayOfWeek = AValue then Exit;
  FFirstDayOfWeek := AValue;
  Invalidate;
end;

procedure TTyCalendar.SetWeekNumbers(AValue: Boolean);
begin
  if FWeekNumbers = AValue then Exit;
  FWeekNumbers := AValue;
  Invalidate;
end;

procedure TTyCalendar.SetShowToday(AValue: Boolean);
begin
  if FShowToday = AValue then Exit;
  FShowToday := AValue;
  Invalidate;
end;

procedure TTyCalendar.SetReadOnly(AValue: Boolean);
begin
  if FReadOnly = AValue then Exit;
  FReadOnly := AValue;
  Invalidate;
end;

procedure TTyCalendar.SetViewMonth(AYear: Integer; AMonth: Integer);
begin
  while AMonth < 1  do begin Dec(AYear); Inc(AMonth, 12); end;
  while AMonth > 12 do begin Inc(AYear); Dec(AMonth, 12); end;
  if AYear < 1    then AYear := 1;
  if AYear > 9999 then AYear := 9999;
  FViewYear  := AYear;
  FViewMonth := AMonth;
  Invalidate;
end;

procedure TTyCalendar.SelectDate(ANewDate: TDateTime);
var
  d: TDateTime;
  dy, dm, dd: Word;
  oldDate: TDateTime;
begin
  if FReadOnly then Exit;
  d := DateOf(ANewDate);
  if not TyCalendarInRange(d, FMinDate, FMaxDate) then Exit;
  oldDate := DateOf(FDate);
  if oldDate = d then Exit;
  FDate := d;
  DecodeDate(FDate, dy, dm, dd);
  FViewYear  := dy;
  FViewMonth := dm;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyCalendar.ChangeViewMode(ANewMode: TTyCalView);
begin
  if FViewMode = ANewMode then Exit;
  FViewMode := ANewMode;
  Invalidate;
  if Assigned(FOnViewChange) then FOnViewChange(Self);
end;

procedure TTyCalendar.CalcLayout4x3(const ARect: TRect; APPI: Integer;
  out HeaderH, ColW, RowH: Integer; out GridRect: TRect);
var
  W, H: Integer;
begin
  W := ARect.Right  - ARect.Left;
  H := ARect.Bottom - ARect.Top;
  HeaderH := MulDiv(28, APPI, 96);
  ColW    := (W) div 4;
  if ColW < 1 then ColW := 1;
  RowH    := (H - HeaderH) div 3;
  if RowH < 1 then RowH := 1;
  GridRect := Rect(0, HeaderH, 4 * ColW, HeaderH + 3 * RowH);
end;

procedure TTyCalendar.RenderMonthsView(P: TTyPainter; const ARect: TRect; APPI: Integer;
  const S: TTyStyleSet; HeaderH, ColW, RowH: Integer; const GridRect: TRect);
var
  W: Integer;
  ArrowW: Integer;
  TitleRect, ArrowLeftRect, ArrowRightRect: TRect;
  TitleText: string;
  CellStyle: TTyStyleSet;
  FontSz, FontWt: Integer;
  i, col, row: Integer;
  CellRect: TRect;
  CellStates: TTyStateSet;
  DateY, DateM, DateD: Word;
begin
  W      := ARect.Right - ARect.Left;
  ArrowW := HeaderH;
  FontSz := ResolveFontSize(S);
  FontWt := S.FontWeight;

  // Header: [←] [YYYY] [→]
  ArrowLeftRect  := Rect(0, 0, ArrowW, HeaderH);
  ArrowRightRect := Rect(W - ArrowW, 0, W, HeaderH);
  TitleRect      := Rect(ArrowW, 0, W - ArrowW, HeaderH);

  P.DrawGlyph(ArrowLeftRect,  tgArrowLeft,  S.TextColor, 1);
  P.DrawGlyph(ArrowRightRect, tgArrowRight, S.TextColor, 1);

  TitleText := IntToStr(FViewYear);
  CellStyle := ActiveController.Model.ResolveStyle('TyCalendarTitle', '', [tysNormal]);
  if not (tpTextColor in CellStyle.Present) then CellStyle.TextColor := S.TextColor;
  if CellStyle.FontSize <= 0 then CellStyle.FontSize := FontSz;
  P.DrawText(TitleRect, TitleText, CellStyle.FontName, CellStyle.FontSize,
    FontWt, CellStyle.TextColor, taCenter, tlCenter, False);

  // 4x3 month grid
  DecodeDate(FDate, DateY, DateM, DateD);
  for i := 0 to 11 do
  begin
    col := i mod 4;
    row := i div 4;
    CellRect := Rect(
      GridRect.Left + col * ColW,
      GridRect.Top  + row * RowH,
      GridRect.Left + (col + 1) * ColW,
      GridRect.Top  + (row + 1) * RowH);

    // Selected = the month of FDate when view year matches
    if (FViewYear = DateY) and (Word(i + 1) = DateM) then
      CellStates := [tysSelected]
    else
      CellStates := [tysNormal];

    CellStyle := ActiveController.Model.ResolveStyle('TyCalendarCell', '', CellStates);
    if CellStyle.FontSize <= 0 then CellStyle.FontSize := FontSz;
    if not (tpTextColor in CellStyle.Present) then CellStyle.TextColor := S.TextColor;

    if tpBackground in CellStyle.Present then
      P.FillBackground(CellRect, CellStyle.Background, 0);

    P.DrawText(CellRect, DefaultFormatSettings.ShortMonthNames[i + 1],
      CellStyle.FontName, CellStyle.FontSize,
      FontWt, CellStyle.TextColor, taCenter, tlCenter, False);
  end;
end;

procedure TTyCalendar.RenderYearsView(P: TTyPainter; const ARect: TRect; APPI: Integer;
  const S: TTyStyleSet; HeaderH, ColW, RowH: Integer; const GridRect: TRect);
{ Layout: 4x3 = 12 cells showing decadeStart-1 .. decadeStart+10 (spill layout).
  The leading and trailing cells display years outside the decade in a muted style. }
var
  W: Integer;
  ArrowW: Integer;
  TitleRect, ArrowLeftRect, ArrowRightRect: TRect;
  TitleText: string;
  CellStyle: TTyStyleSet;
  FontSz, FontWt: Integer;
  i, col, row, cellYear: Integer;
  CellRect: TRect;
  CellStates: TTyStateSet;
  DS: Integer;           // decadeStart
  DateY, DateM, DateD: Word;
  IsSpill: Boolean;
  MutedColor: TTyColor;
begin
  W      := ARect.Right - ARect.Left;
  ArrowW := HeaderH;
  FontSz := ResolveFontSize(S);
  FontWt := S.FontWeight;
  DS     := TyDecadeStart(FViewYear);

  // Muted color for spill years
  MutedColor := TyRGBA(TyRedOf(S.TextColor), TyGreenOf(S.TextColor),
                       TyBlueOf(S.TextColor), 100);

  // Header: [←] [DS–DS+9] [→]
  ArrowLeftRect  := Rect(0, 0, ArrowW, HeaderH);
  ArrowRightRect := Rect(W - ArrowW, 0, W, HeaderH);
  TitleRect      := Rect(ArrowW, 0, W - ArrowW, HeaderH);

  P.DrawGlyph(ArrowLeftRect,  tgArrowLeft,  S.TextColor, 1);
  P.DrawGlyph(ArrowRightRect, tgArrowRight, S.TextColor, 1);

  TitleText := IntToStr(DS) + '–' + IntToStr(DS + 9);
  CellStyle := ActiveController.Model.ResolveStyle('TyCalendarTitle', '', [tysNormal]);
  if not (tpTextColor in CellStyle.Present) then CellStyle.TextColor := S.TextColor;
  if CellStyle.FontSize <= 0 then CellStyle.FontSize := FontSz;
  P.DrawText(TitleRect, TitleText, CellStyle.FontName, CellStyle.FontSize,
    FontWt, CellStyle.TextColor, taCenter, tlCenter, False);

  // 4x3 grid: cells 0..11 = years (DS-1) .. (DS+10)
  DecodeDate(FDate, DateY, DateM, DateD);
  for i := 0 to 11 do
  begin
    col      := i mod 4;
    row      := i div 4;
    cellYear := DS - 1 + i;   // spill: leading (DS-1) and trailing (DS+10)
    IsSpill  := (cellYear < DS) or (cellYear > DS + 9);

    CellRect := Rect(
      GridRect.Left + col * ColW,
      GridRect.Top  + row * RowH,
      GridRect.Left + (col + 1) * ColW,
      GridRect.Top  + (row + 1) * RowH);

    if cellYear = Integer(DateY) then
      CellStates := [tysSelected]
    else if IsSpill then
      CellStates := [tysDisabled]
    else
      CellStates := [tysNormal];

    CellStyle := ActiveController.Model.ResolveStyle('TyCalendarCell', '', CellStates);
    if CellStyle.FontSize <= 0 then CellStyle.FontSize := FontSz;
    if not (tpTextColor in CellStyle.Present) then
    begin
      if IsSpill then
        CellStyle.TextColor := MutedColor
      else
        CellStyle.TextColor := S.TextColor;
    end;

    if tpBackground in CellStyle.Present then
      P.FillBackground(CellRect, CellStyle.Background, 0);

    P.DrawText(CellRect, IntToStr(cellYear),
      CellStyle.FontName, CellStyle.FontSize,
      FontWt, CellStyle.TextColor, taCenter, tlCenter, False);
  end;
end;

procedure TTyCalendar.RenderDecadesView(P: TTyPainter; const ARect: TRect; APPI: Integer;
  const S: TTyStyleSet; HeaderH, ColW, RowH: Integer; const GridRect: TRect);
{ 4x3 grid of 12 decades for the century containing FViewYear.
  centStart = (FViewYear div 100) * 100.
  Cells: decades centStart-10 .. centStart+100 (spill layout, same as years view). }
var
  W: Integer;
  ArrowW: Integer;
  TitleRect, ArrowLeftRect, ArrowRightRect: TRect;
  TitleText: string;
  CellStyle: TTyStyleSet;
  FontSz, FontWt: Integer;
  i, col, row, cellDecade: Integer;
  CellRect: TRect;
  CellStates: TTyStateSet;
  CentStart: Integer;
  DateY, DateM, DateD: Word;
  IsSpill: Boolean;
  MutedColor: TTyColor;
  DateDecade: Integer;
begin
  W      := ARect.Right - ARect.Left;
  ArrowW := HeaderH;
  FontSz := ResolveFontSize(S);
  FontWt := S.FontWeight;
  CentStart := (Integer(FViewYear) div 100) * 100;

  // Muted color for spill decades
  MutedColor := TyRGBA(TyRedOf(S.TextColor), TyGreenOf(S.TextColor),
                       TyBlueOf(S.TextColor), 100);

  // Header: [←] [centStart–centStart+99] [→]
  ArrowLeftRect  := Rect(0, 0, ArrowW, HeaderH);
  ArrowRightRect := Rect(W - ArrowW, 0, W, HeaderH);
  TitleRect      := Rect(ArrowW, 0, W - ArrowW, HeaderH);

  P.DrawGlyph(ArrowLeftRect,  tgArrowLeft,  S.TextColor, 1);
  P.DrawGlyph(ArrowRightRect, tgArrowRight, S.TextColor, 1);

  TitleText := IntToStr(CentStart) + '–' + IntToStr(CentStart + 99);
  CellStyle := ActiveController.Model.ResolveStyle('TyCalendarTitle', '', [tysNormal]);
  if not (tpTextColor in CellStyle.Present) then CellStyle.TextColor := S.TextColor;
  if CellStyle.FontSize <= 0 then CellStyle.FontSize := FontSz;
  P.DrawText(TitleRect, TitleText, CellStyle.FontName, CellStyle.FontSize,
    FontWt, CellStyle.TextColor, taCenter, tlCenter, False);

  // 4x3 grid: cells 0..11 = decades (CentStart-10) .. (CentStart+100) — spill layout
  DecodeDate(FDate, DateY, DateM, DateD);
  DateDecade := TyDecadeStart(DateY);
  for i := 0 to 11 do
  begin
    col         := i mod 4;
    row         := i div 4;
    cellDecade  := CentStart - 10 + i * 10;
    IsSpill     := (cellDecade < CentStart) or (cellDecade > CentStart + 90);

    CellRect := Rect(
      GridRect.Left + col * ColW,
      GridRect.Top  + row * RowH,
      GridRect.Left + (col + 1) * ColW,
      GridRect.Top  + (row + 1) * RowH);

    if cellDecade = DateDecade then
      CellStates := [tysSelected]
    else if IsSpill then
      CellStates := [tysDisabled]
    else
      CellStates := [tysNormal];

    CellStyle := ActiveController.Model.ResolveStyle('TyCalendarCell', '', CellStates);
    if CellStyle.FontSize <= 0 then CellStyle.FontSize := FontSz;
    if not (tpTextColor in CellStyle.Present) then
    begin
      if IsSpill then
        CellStyle.TextColor := MutedColor
      else
        CellStyle.TextColor := S.TextColor;
    end;

    if tpBackground in CellStyle.Present then
      P.FillBackground(CellRect, CellStyle.Background, 0);

    P.DrawText(CellRect, IntToStr(cellDecade),
      CellStyle.FontName, CellStyle.FontSize,
      FontWt, CellStyle.TextColor, taCenter, tlCenter, False);
  end;
end;

procedure TTyCalendar.CalcLayout(const ARect: TRect; APPI: Integer;
  out HeaderH, WeekdayH, WkNumW, ColW, RowH: Integer; out GridRect: TRect);
var
  W, H: Integer;
begin
  { All rects are 0-origin (relative to ARect's top-left = (0,0)).
    Paint calls P.BeginPaint with ARect so it draws 0-based.
    MouseDown receives ClientRect which is also 0-origin. }
  W := ARect.Right  - ARect.Left;
  H := ARect.Bottom - ARect.Top;
  HeaderH  := MulDiv(28, APPI, 96);
  WeekdayH := MulDiv(20, APPI, 96);
  if FWeekNumbers then
    WkNumW := MulDiv(24, APPI, 96)
  else
    WkNumW := 0;
  ColW := (W - WkNumW) div 7;
  if ColW < 1 then ColW := 1;
  RowH := (H - HeaderH - WeekdayH) div 6;
  if RowH < 1 then RowH := 1;
  GridRect := Rect(
    WkNumW,
    HeaderH + WeekdayH,
    WkNumW + 7 * ColW,
    HeaderH + WeekdayH + 6 * RowH);
end;

procedure TTyCalendar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, CellStyle: TTyStyleSet;
  W, H: Integer;
  HeaderH, WeekdayH, WkNumW, ColW, RowH: Integer;
  GridRect: TRect;
  ArrowW: Integer;
  TitleRect, ArrowLeftRect, ArrowRightRect: TRect;
  i, col, row, wkNum: Integer;
  Grid: TTyDateGrid;
  CellRect, WkNumRect: TRect;
  CellDate: TDateTime;
  CellY, CellM, CellD: Word;
  SelDate, TodayDate: TDateTime;
  IsSelected, IsOtherMonth, IsInRange: Boolean;
  CellStates: TTyStateSet;
  WeekOrderArr: TTyWeekdayOrderArray;
  DayName, TitleText: string;
  FontSz, FontWt: Integer;
  MutedColor: TTyColor;
  TodayRingStyle: TTyStyleSet;
  TodayRingW: Integer;
  TodayRingColor: TTyColor;
  // drill-down views
  HdrH4, ColW4, RowH4: Integer;
  GridRect4: TRect;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    W := ARect.Right - ARect.Left;
    H := ARect.Bottom - ARect.Top;

    // Frame (outer border + background)
    DrawFrame(P, Rect(0, 0, W, H), S);

    // Branch on ViewMode
    if FViewMode <> cvmDays then
    begin
      CalcLayout4x3(ARect, APPI, HdrH4, ColW4, RowH4, GridRect4);
      case FViewMode of
        cvmMonths:
          RenderMonthsView(P, ARect, APPI, S, HdrH4, ColW4, RowH4, GridRect4);
        cvmYears:
          RenderYearsView(P, ARect, APPI, S, HdrH4, ColW4, RowH4, GridRect4);
        cvmDecades:
          RenderDecadesView(P, ARect, APPI, S, HdrH4, ColW4, RowH4, GridRect4);
      end;
      P.EndPaint;
      Exit;
    end;

    FontSz := ResolveFontSize(S);
    FontWt := S.FontWeight;

    CalcLayout(ARect, APPI, HeaderH, WeekdayH, WkNumW, ColW, RowH, GridRect);

    // Header band: [←] [Month YYYY] [→]
    ArrowW         := HeaderH;
    ArrowLeftRect  := Rect(0, 0, ArrowW, HeaderH);
    ArrowRightRect := Rect(W - ArrowW, 0, W, HeaderH);
    TitleRect      := Rect(ArrowW, 0, W - ArrowW, HeaderH);

    P.DrawGlyph(ArrowLeftRect,  tgArrowLeft,  S.TextColor, 1);
    P.DrawGlyph(ArrowRightRect, tgArrowRight, S.TextColor, 1);

    // Title text
    TitleText := FormatDateTime('mmmm yyyy', EncodeDate(FViewYear, FViewMonth, 1));
    CellStyle := ActiveController.Model.ResolveStyle('TyCalendarTitle', '', [tysNormal]);
    if not (tpTextColor in CellStyle.Present) then
      CellStyle.TextColor := S.TextColor;
    if CellStyle.FontSize <= 0 then
      CellStyle.FontSize := FontSz;
    P.DrawText(TitleRect, TitleText, CellStyle.FontName, CellStyle.FontSize,
      FontWt, CellStyle.TextColor, taCenter, tlCenter, False);

    // Weekday name row
    WeekOrderArr := TyWeekdayOrder(FFirstDayOfWeek);
    CellStyle := ActiveController.Model.ResolveStyle('TyCalendarWeekday', '', [tysNormal]);
    if not (tpTextColor in CellStyle.Present) then
      CellStyle.TextColor := S.TextColor;
    if CellStyle.FontSize <= 0 then
      CellStyle.FontSize := FontSz;

    // Week number header label (blank area above week-number column)
    if FWeekNumbers then
    begin
      WkNumRect := Rect(0, HeaderH, WkNumW, HeaderH + WeekdayH);
      P.DrawText(WkNumRect, '#', CellStyle.FontName, CellStyle.FontSize,
        FontWt, CellStyle.TextColor, taCenter, tlCenter, False);
    end;

    for col := 0 to 6 do
    begin
      // ShortDayNames: 1=Sunday .. 7=Saturday in FPC/Delphi DefaultFormatSettings
      DayName  := DefaultFormatSettings.ShortDayNames[WeekOrderArr[col] + 1];
      CellRect := Rect(
        GridRect.Left + col * ColW,
        HeaderH,
        GridRect.Left + (col + 1) * ColW,
        HeaderH + WeekdayH);
      P.DrawText(CellRect, DayName, CellStyle.FontName, CellStyle.FontSize,
        FontWt, CellStyle.TextColor, taCenter, tlCenter, False);
    end;

    // Day grid (6 rows x 7 cols)
    Grid      := TyCalendarMonthGrid(FViewYear, FViewMonth, FFirstDayOfWeek);
    SelDate   := DateOf(FDate);
    TodayDate := DateOf(Now);

    // Muted color for other-month / out-of-range cells
    MutedColor := TyRGBA(TyRedOf(S.TextColor), TyGreenOf(S.TextColor),
                         TyBlueOf(S.TextColor), 100);

    for i := 0 to 41 do
    begin
      CellDate := Grid[i];
      DecodeDate(CellDate, CellY, CellM, CellD);
      row := i div 7;
      col := i mod 7;

      IsOtherMonth := (CellM <> FViewMonth) or (CellY <> FViewYear);
      IsInRange    := TyCalendarInRange(CellDate, FMinDate, FMaxDate);
      IsSelected   := (DateOf(CellDate) = SelDate);

      if IsSelected then
        CellStates := [tysSelected]
      else if IsOtherMonth or not IsInRange then
        CellStates := [tysDisabled]
      else
        CellStates := [tysNormal];

      CellStyle := ActiveController.Model.ResolveStyle('TyCalendarCell', '', CellStates);
      if CellStyle.FontSize <= 0 then
        CellStyle.FontSize := FontSz;
      if not (tpTextColor in CellStyle.Present) then
      begin
        if IsOtherMonth or not IsInRange then
          CellStyle.TextColor := MutedColor
        else
          CellStyle.TextColor := S.TextColor;
      end;

      CellRect := Rect(
        GridRect.Left + col * ColW,
        GridRect.Top  + row * RowH,
        GridRect.Left + (col + 1) * ColW,
        GridRect.Top  + (row + 1) * RowH);

      // Background
      if tpBackground in CellStyle.Present then
        P.FillBackground(CellRect, CellStyle.Background, 0);

      // Today highlight (outline ring).
      // Color reuses the selected-state accent (var(--accent) via :selected background).
      // Width is a scaled hairline (P.Scale(1), floored to 1) for consistency with other hairlines.
      if FShowToday and (DateOf(CellDate) = TodayDate) and not IsSelected then
      begin
        TodayRingStyle := ActiveController.Model.ResolveStyle('TyCalendarCell', '', [tysSelected]);
        if tpBackground in TodayRingStyle.Present then
          TodayRingColor := TodayRingStyle.Background.Color
        else
          TodayRingColor := S.TextColor;
        TodayRingW := P.Scale(1);
        if TodayRingW < 1 then TodayRingW := 1;
        P.StrokeBorder(CellRect, 0, TodayRingW, TodayRingColor);
      end;

      // Day number
      P.DrawText(CellRect, IntToStr(CellD), CellStyle.FontName, CellStyle.FontSize,
        FontWt, CellStyle.TextColor, taCenter, tlCenter, False);

      // Week number (leftmost column only)
      if FWeekNumbers and (col = 0) then
      begin
        wkNum := TyISOWeekNumber(CellDate);
        WkNumRect := Rect(
          0,
          GridRect.Top + row * RowH,
          WkNumW,
          GridRect.Top + (row + 1) * RowH);
        CellStyle := ActiveController.Model.ResolveStyle('TyCalendarWeekday', '', [tysNormal]);
        if not (tpTextColor in CellStyle.Present) then
          CellStyle.TextColor := S.TextColor;
        if CellStyle.FontSize <= 0 then
          CellStyle.FontSize := FontSz;
        P.DrawText(WkNumRect, IntToStr(wkNum), CellStyle.FontName, CellStyle.FontSize,
          FontWt, CellStyle.TextColor, taCenter, tlCenter, False);
      end;
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCalendar.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTyCalendar.RenderToPublic(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyCalendar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  HeaderH, WeekdayH, WkNumW, ColW, RowH: Integer;
  GridRect: TRect;
  ArrowW, cellIdx: Integer;
  W: Integer;
  Grid: TTyDateGrid;
  CellDate: TDateTime;
  CellY, CellM, dummy: Word;
  oldDate, newDate: TDateTime;
  dy, dm, dd: Word;
  // drill-down
  HdrH4, ColW4, RowH4: Integer;
  GridRect4: TRect;
  DS, CentStart, cellYear, cellMonth, cellDecade: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;

  W := ClientWidth;

  // Handle non-Days views
  if FViewMode <> cvmDays then
  begin
    CalcLayout4x3(ClientRect, Font.PixelsPerInch, HdrH4, ColW4, RowH4, GridRect4);
    ArrowW := HdrH4;

    // Left arrow
    if (X >= 0) and (X < ArrowW) and (Y >= 0) and (Y < HdrH4) then
    begin
      case FViewMode of
        cvmMonths:  FViewYear := FViewYear - 1;          // ∓1 year
        cvmYears:   FViewYear := FViewYear - 10;         // ∓10 years (decade)
        cvmDecades: FViewYear := FViewYear - 100;        // ∓100 years (century)
      end;
      if FViewYear < 1    then FViewYear := 1;
      if FViewYear > 9999 then FViewYear := 9999;
      Invalidate;
      Exit;
    end;

    // Right arrow
    if (X >= W - ArrowW) and (X < W) and (Y >= 0) and (Y < HdrH4) then
    begin
      case FViewMode of
        cvmMonths:  FViewYear := FViewYear + 1;
        cvmYears:   FViewYear := FViewYear + 10;
        cvmDecades: FViewYear := FViewYear + 100;
      end;
      if FViewYear < 1    then FViewYear := 1;
      if FViewYear > 9999 then FViewYear := 9999;
      Invalidate;
      Exit;
    end;

    // Title click: zoom out another level
    if (X >= ArrowW) and (X < W - ArrowW) and (Y >= 0) and (Y < HdrH4) then
    begin
      ChangeViewMode(TyCalendarZoomOut(FViewMode));
      Exit;
    end;

    // Grid cell click: pick and zoom in
    cellIdx := TyCalendarHitCell(GridRect4, 4, 3, X, Y);
    if cellIdx < 0 then Exit;

    case FViewMode of
      cvmMonths:
        begin
          // Pick the month; zoom to Days of that month
          cellMonth  := cellIdx + 1;   // 1..12
          FViewMonth := Word(cellMonth);
          // FViewYear already set (the displayed year)
          ChangeViewMode(TyCalendarZoomIn(FViewMode));
        end;
      cvmYears:
        begin
          // Pick the year (spill layout: cell 0 = DS-1)
          DS       := TyDecadeStart(FViewYear);
          cellYear := DS - 1 + cellIdx;
          FViewYear := cellYear;
          ChangeViewMode(TyCalendarZoomIn(FViewMode));
        end;
      cvmDecades:
        begin
          // Pick a decade (spill layout: cell 0 = CentStart-10)
          CentStart   := (Integer(FViewYear) div 100) * 100;
          cellDecade  := CentStart - 10 + cellIdx * 10;
          FViewYear   := cellDecade;   // navigate to that decade's start year
          ChangeViewMode(TyCalendarZoomIn(FViewMode));
        end;
    end;
    Exit;
  end;

  // === Days view (existing logic) ===

  CalcLayout(ClientRect, Font.PixelsPerInch,
    HeaderH, WeekdayH, WkNumW, ColW, RowH, GridRect);
  ArrowW := HeaderH;

  // Title click in Days view: zoom out to Months
  if (X >= ArrowW) and (X < W - ArrowW) and (Y >= 0) and (Y < HeaderH) then
  begin
    ChangeViewMode(TyCalendarZoomOut(FViewMode));
    Exit;
  end;

  // Left arrow (prev month)
  if (X >= 0) and (X < ArrowW) and (Y >= 0) and (Y < HeaderH) then
  begin
    SetViewMonth(FViewYear, Integer(FViewMonth) - 1);
    Exit;
  end;

  // Right arrow (next month)
  if (X >= W - ArrowW) and (X < W) and (Y >= 0) and (Y < HeaderH) then
  begin
    SetViewMonth(FViewYear, Integer(FViewMonth) + 1);
    Exit;
  end;

  // Grid cell
  cellIdx := TyCalendarHitCell(GridRect, 7, 6, X, Y);
  if cellIdx < 0 then Exit;

  Grid     := TyCalendarMonthGrid(FViewYear, FViewMonth, FFirstDayOfWeek);
  CellDate := Grid[cellIdx];
  DecodeDate(CellDate, CellY, CellM, dummy);

  // Only accept current-view-month cells that are in range
  if (CellM <> FViewMonth) or (CellY <> FViewYear) then Exit;
  if not TyCalendarInRange(CellDate, FMinDate, FMaxDate) then Exit;
  if FReadOnly then Exit;

  newDate := DateOf(CellDate);
  oldDate := DateOf(FDate);

  if newDate <> oldDate then
  begin
    FDate := newDate;
    DecodeDate(FDate, dy, dm, dd);
    FViewYear  := dy;
    FViewMonth := dm;
    Invalidate;
    if Assigned(FOnChange) then FOnChange(Self);
  end;

  // A day-cell click is a definitive-select gesture: always fire OnAccept
  // (even when the date didn't change, the user confirmed this date).
  if Assigned(FOnAccept) then FOnAccept(Self);
end;

procedure TTyCalendar.KeyDown(var Key: Word; Shift: TShiftState);
var
  curDate, newDate: TDateTime;
  dy, dm, dd: Word;
  nm, ny: Integer;
  maxd: Byte;
  Grid: TTyDateGrid;
  i: Integer;
  firstDay, lastDay: TDateTime;
  gy, gm, gd: Word;
begin
  inherited KeyDown(Key, Shift);
  if FReadOnly then Exit;

  curDate := DateOf(FDate);
  newDate := curDate;

  case Key of

    VK_LEFT:
      begin
        newDate := IncDay(curDate, -1);
        newDate := TyCalendarClampDate(newDate, FMinDate, FMaxDate);
        SelectDate(newDate);
        Key := 0;
      end;

    VK_RIGHT:
      begin
        newDate := IncDay(curDate, 1);
        newDate := TyCalendarClampDate(newDate, FMinDate, FMaxDate);
        SelectDate(newDate);
        Key := 0;
      end;

    VK_UP:
      begin
        newDate := IncDay(curDate, -7);
        newDate := TyCalendarClampDate(newDate, FMinDate, FMaxDate);
        SelectDate(newDate);
        Key := 0;
      end;

    VK_DOWN:
      begin
        newDate := IncDay(curDate, 7);
        newDate := TyCalendarClampDate(newDate, FMinDate, FMaxDate);
        SelectDate(newDate);
        Key := 0;
      end;

    VK_PRIOR:  // PageUp = previous month
      begin
        // Compute target date directly; let SelectDate set the view (no flicker).
        DecodeDate(curDate, dy, dm, dd);
        nm := Integer(dm) - 1;
        ny := Integer(dy);
        if nm < 1 then begin Dec(ny); Inc(nm, 12); end;
        maxd := MonthDays[IsLeapYear(ny), nm];
        if dd > maxd then dd := maxd;
        newDate := TyCalendarClampDate(EncodeDate(ny, nm, dd), FMinDate, FMaxDate);
        SelectDate(newDate);
        Key := 0;
      end;

    VK_NEXT:  // PageDown = next month
      begin
        // Compute target date directly; let SelectDate set the view (no flicker).
        DecodeDate(curDate, dy, dm, dd);
        nm := Integer(dm) + 1;
        ny := Integer(dy);
        if nm > 12 then begin Inc(ny); Dec(nm, 12); end;
        maxd := MonthDays[IsLeapYear(ny), nm];
        if dd > maxd then dd := maxd;
        newDate := TyCalendarClampDate(EncodeDate(ny, nm, dd), FMinDate, FMaxDate);
        SelectDate(newDate);
        Key := 0;
      end;

    VK_HOME:
      begin
        // First enabled day of the view month
        Grid     := TyCalendarMonthGrid(FViewYear, FViewMonth, FFirstDayOfWeek);
        firstDay := 0;
        for i := 0 to 41 do
        begin
          DecodeDate(Grid[i], gy, gm, gd);
          if (gm = FViewMonth) and (gy = FViewYear) and
             TyCalendarInRange(Grid[i], FMinDate, FMaxDate) then
          begin
            firstDay := Grid[i];
            Break;
          end;
        end;
        if firstDay <> 0 then SelectDate(firstDay);
        Key := 0;
      end;

    VK_END:
      begin
        // Last enabled day of the view month
        Grid    := TyCalendarMonthGrid(FViewYear, FViewMonth, FFirstDayOfWeek);
        lastDay := 0;
        for i := 41 downto 0 do
        begin
          DecodeDate(Grid[i], gy, gm, gd);
          if (gm = FViewMonth) and (gy = FViewYear) and
             TyCalendarInRange(Grid[i], FMinDate, FMaxDate) then
          begin
            lastDay := Grid[i];
            Break;
          end;
        end;
        if lastDay <> 0 then SelectDate(lastDay);
        Key := 0;
      end;

    VK_RETURN, VK_SPACE:
      begin
        // Accept: fire OnAccept (for a popup to commit+close).
        // Do NOT re-fire OnChange here — the date was already changed (and
        // OnChange already fired) by the arrow-navigation that got here.
        // (ReadOnly is already guarded at the top of KeyDown.)
        if Assigned(FOnAccept) then FOnAccept(Self);
        Key := 0;
      end;

  end;
end;

end.
