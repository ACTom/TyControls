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
    FOnChange: TNotifyEvent;
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
    { Computes layout metrics given current size + APPI.
      HeaderH   = arrow+title band height (device px)
      WeekdayH  = weekday-names row height (device px)
      WkNumW    = week-number column width (device px; 0 if WeekNumbers=False)
      ColW      = cell width (device px)
      RowH      = cell row height (device px)
      GridRect  = full 6x7 grid area in ARect-local coords }
    procedure CalcLayout(const ARect: TRect; APPI: Integer;
      out HeaderH, WeekdayH, WkNumW, ColW, RowH: Integer; out GridRect: TRect);
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
  published
    property Date: TDateTime read FDate write SetDate;
    property MinDate: TDateTime read FMinDate write SetMinDate;
    property MaxDate: TDateTime read FMaxDate write SetMaxDate;
    property FirstDayOfWeek: TTyWeekDay read FFirstDayOfWeek write SetFirstDayOfWeek default wdSunday;
    property WeekNumbers: Boolean read FWeekNumbers write SetWeekNumbers default False;
    property ShowToday: Boolean read FShowToday write SetShowToday default True;
    property ReadOnly: Boolean read FReadOnly write SetReadOnly default False;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
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
  Invalidate;
end;

procedure TTyCalendar.SetMaxDate(AValue: TDateTime);
begin
  if FMaxDate = AValue then Exit;
  FMaxDate := AValue;
  Invalidate;
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

procedure TTyCalendar.CalcLayout(const ARect: TRect; APPI: Integer;
  out HeaderH, WeekdayH, WkNumW, ColW, RowH: Integer; out GridRect: TRect);
var
  W, H, gridLeft: Integer;
begin
  W := ARect.Right  - ARect.Left;
  H := ARect.Bottom - ARect.Top;
  HeaderH  := MulDiv(28, APPI, 96);
  WeekdayH := MulDiv(20, APPI, 96);
  if FWeekNumbers then
    WkNumW := MulDiv(24, APPI, 96)
  else
    WkNumW := 0;
  gridLeft := ARect.Left + WkNumW;
  ColW := (W - WkNumW) div 7;
  if ColW < 1 then ColW := 1;
  RowH := (H - HeaderH - WeekdayH) div 6;
  if RowH < 1 then RowH := 1;
  GridRect := Rect(
    gridLeft,
    ARect.Top + HeaderH + WeekdayH,
    gridLeft + 7 * ColW,
    ARect.Top + HeaderH + WeekdayH + 6 * RowH);
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
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    W := ARect.Right - ARect.Left;
    H := ARect.Bottom - ARect.Top;

    // Frame (outer border + background)
    DrawFrame(P, Rect(0, 0, W, H), S);

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
        ARect.Top + HeaderH,
        GridRect.Left + (col + 1) * ColW,
        ARect.Top + HeaderH + WeekdayH);
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

      // Today highlight (outline ring)
      if FShowToday and (DateOf(CellDate) = TodayDate) and not IsSelected then
        P.StrokeBorder(CellRect, 0, 1, S.TextColor);

      // Day number
      P.DrawText(CellRect, IntToStr(CellD), CellStyle.FontName, CellStyle.FontSize,
        FontWt, CellStyle.TextColor, taCenter, tlCenter, False);

      // Week number (leftmost column only)
      if FWeekNumbers and (col = 0) then
      begin
        wkNum := TyISOWeekNumber(CellDate);
        WkNumRect := Rect(
          ARect.Left,
          GridRect.Top + row * RowH,
          ARect.Left + WkNumW,
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
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;

  W := ClientWidth;
  CalcLayout(ClientRect, Font.PixelsPerInch,
    HeaderH, WeekdayH, WkNumW, ColW, RowH, GridRect);
  ArrowW := HeaderH;

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
  if newDate = oldDate then Exit;

  FDate := newDate;
  DecodeDate(FDate, dy, dm, dd);
  FViewYear  := dy;
  FViewMonth := dm;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
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
        SetViewMonth(FViewYear, Integer(FViewMonth) - 1);
        // Move selected date back by 1 month
        DecodeDate(curDate, dy, dm, dd);
        nm := Integer(dm) - 1;
        ny := Integer(dy);
        if nm < 1 then begin Dec(ny); Inc(nm, 12); end;
        maxd := MonthDays[IsLeapYear(ny), nm];
        if dd > maxd then dd := maxd;
        newDate := TyCalendarClampDate(EncodeDate(ny, nm, dd), FMinDate, FMaxDate);
        if DateOf(FDate) <> DateOf(newDate) then
          SelectDate(newDate);
        Key := 0;
      end;

    VK_NEXT:  // PageDown = next month
      begin
        SetViewMonth(FViewYear, Integer(FViewMonth) + 1);
        DecodeDate(curDate, dy, dm, dd);
        nm := Integer(dm) + 1;
        ny := Integer(dy);
        if nm > 12 then begin Inc(ny); Dec(nm, 12); end;
        maxd := MonthDays[IsLeapYear(ny), nm];
        if dd > maxd then dd := maxd;
        newDate := TyCalendarClampDate(EncodeDate(ny, nm, dd), FMinDate, FMaxDate);
        if DateOf(FDate) <> DateOf(newDate) then
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
        // Commit: fire OnChange for the currently selected date
        if Assigned(FOnChange) then FOnChange(Self);
        Key := 0;
      end;

  end;
end;

end.
