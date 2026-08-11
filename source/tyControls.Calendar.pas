unit tyControls.Calendar;
{$mode objfpc}{$H+}
interface
uses
  { Windows comes FIRST on purpose: it declares RECT as a type, which shadows the
    Rect(l,t,r,b) constructor this unit uses everywhere if it is listed later. }
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Classes, SysUtils, Types, DateUtils, Controls, Graphics, LCLType,
  BGRABitmap,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller;

type
  { Raised by Date/DateTime when the assigned day falls outside MinDate..MaxDate.
    LCL declares the same guard as EInvalidDate (C:/lazarus/lcl/calendar.pp:74,
    raised from CheckRange :293-304); the alias below lets `except on EInvalidDate`
    from a ported form compile unchanged. Ty-prefixed as the primary name so the two
    can coexist in a unit that still uses the LCL Calendar as well. }
  ETyInvalidDate = class(Exception);
  EInvalidDate   = ETyInvalidDate;

  { wdLocaleDefault is LCL's dowDefault (C:/lazarus/lcl/calendar.pp:71): "start the week
    where the OS says this locale starts it". It is APPENDED, not inserted, so every
    existing ordinal and every .lfm that names a weekday keeps its meaning. Resolve it
    with TyResolveFirstDayOfWeek before doing arithmetic on the ordinal -- 7 is not a
    weekday and `Ord(x) mod 7` would silently answer Sunday. }
  TTyWeekDay = (wdSunday, wdMonday, wdTuesday, wdWednesday, wdThursday,
                wdFriday, wdSaturday, wdLocaleDefault);
  TTyCalView  = (cvmDays, cvmMonths, cvmYears, cvmDecades);
  TTyDateGrid = array[0..41] of TDateTime;   // 6 rows x 7 cols

  { Which pieces of calendar chrome are drawn. LCL spells this TDisplaySetting with the
    same four member names (C:/lazarus/lcl/calendar.pp:37-46), so a ported .lfm line
    `DisplaySettings = [dsShowHeadings, dsShowDayNames]` streams in unchanged.
    Ty-prefixed as the primary type name so a unit that also uses the LCL Calendar can
    name both; the unprefixed aliases below are what ported code says. }
  TTyCalDisplaySetting = (
    dsShowHeadings,      // the [<] Month YYYY [>] band
    dsShowDayNames,      // the Su/Mo/Tu... row
    dsNoMonthChange,     // clicking a spill-over day does NOT page to its month
    dsShowWeekNumbers);  // the ISO week column
  TTyCalDisplaySettings = set of TTyCalDisplaySetting;
  TDisplaySetting  = TTyCalDisplaySetting;
  TDisplaySettings = TTyCalDisplaySettings;

  { Which region of the calendar a point falls in. LCL's TCalendarPart
    (C:/lazarus/lcl/calendar.pp:49-57), member for member. }
  TTyCalendarPart = (
    cpNoWhere,      // outside everything interesting
    cpDate,         // a grid cell (a day, or a month/year/decade in a drill-down view)
    cpWeekNumber,   // the ISO week-number column
    cpTitle,        // the title band, but not on the text or a button
    cpTitleBtn,     // one of the two navigation arrows
    cpTitleMonth,   // the month name inside the title
    cpTitleYear);   // the year inside the title
  TCalendarPart = TTyCalendarPart;

  { The drill-down level, named the way LCL names it: after the PAGE the grid shows,
    not after the cell. LCL's TCalendarView (C:/lazarus/lcl/calendar.pp:62-67).
    Note the off-by-one-level trap this exists to remove: LCL's cvMonth ("a grid of the
    days in one month") is our cvmDays, NOT our cvmMonths. }
  TTyCalendarView = (cvMonth, cvYear, cvDecade, cvCentury);
  TCalendarView   = TTyCalendarView;

const
  { LCL's DefaultDisplaySettings (C:/lazarus/lcl/calendar.pp:46) verbatim. }
  TyDefaultDisplaySettings = [dsShowHeadings, dsShowDayNames];
  DefaultDisplaySettings   = TyDefaultDisplaySettings;

  { LCL's TCalDayOfWeek member names, so `Cal.FirstDayOfWeek := dowMonday` from a ported
    unit compiles here. They are our own enum's members under LCL's spelling -- not a
    second type -- so there is nothing to keep in sync. }
  dowMonday    = wdMonday;
  dowTuesday   = wdTuesday;
  dowWednesday = wdWednesday;
  dowThursday  = wdThursday;
  dowFriday    = wdFriday;
  dowSaturday  = wdSaturday;
  dowSunday    = wdSunday;
  dowDefault   = wdLocaleDefault;

var
  { The weekday the OS says a week starts on, read once at unit start. A variable and
    not a function so a test can pin it (the answer differs per machine, and a grid
    geometry assertion that moves with the developer's Control Panel is worthless). }
  TyLocaleFirstDayOfWeek: TTyWeekDay = wdSunday;

{ Resolves wdLocaleDefault to the OS's answer; every other value passes through.
  Everything that indexes by weekday must go through this -- wdLocaleDefault has
  ordinal 7 and is not a column. }
function TyResolveFirstDayOfWeek(AValue: TTyWeekDay): TTyWeekDay;

type
  { Where the calendar and the date-time picker take their month & weekday names
    from. The two sources can legitimately disagree -- the OS locale is the
    MACHINE's language, a loaded catalogue is the APP's -- and 3.0's bug was
    picking the machine unconditionally: an app translated to English still
    titled its calendar 八月 on a Chinese-locale Windows.

      dnAuto         names follow a loaded translation when one is loaded,
                     the OS locale otherwise (the default; see TyDateTimeNames)
      dnLocale       always DefaultFormatSettings -- the pre-3.0 behaviour
      dnTranslation  always the library resourcestrings (compile-time English
                     until a catalogue patches them)

    An app that wants names NEITHER source has (say, its own abbreviations)
    already holds both pens: write DefaultFormatSettings and force dnLocale, or
    ship a tycontrols catalogue and let dnAuto see it. There is deliberately no
    third name store to keep in sync with those two. }
  TTyDateTimeNameSource = (dnAuto, dnLocale, dnTranslation);

var
  { The app's explicit choice -- tier 1 of the precedence, set once at startup
    (or on a language switch; the controls re-resolve on every paint). A global
    and not a property because the app's language is one fact, not 40 per-form
    facts -- same shape as TyLocaleFirstDayOfWeek above and TyFallbackFontName. }
  TyDateTimeNameSource: TTyDateTimeNameSource = dnAuto;

const
  { rsTyDateTimeNamesLang's COMPILE-TIME value, for comparing against its current
    one. The comparison is the whole load-detector, so the two literals must stay
    identical -- test.calendar pins them. Public so tests and diagnostic code name
    the marker instead of repeating the string. }
  TyDateTimeNamesUntranslatedMark = '__locale__';

{ True when TyDateTimeNames will take the names from the resourcestrings rather
  than from DefaultFormatSettings. Under dnAuto this is "has any catalogue been
  loaded": every shipped tycontrols catalogue (including the English one, whose
  name entries equal their msgids) translates the rsTyDateTimeNamesLang sentinel
  to its language code, so the sentinel differing from its compile-time value is
  proof of a deliberate load. It cannot false-positive -- nothing else in the
  process writes resourcestrings -- and a hand-rolled catalogue that omits the
  sentinel keeps OS-locale names, which is the documented opt-out. }
function TyDateTimeNamesTranslated: Boolean;

{ The format settings the calendar and the picker RENDER with: the process
  DefaultFormatSettings, with the month/weekday names replaced from the library
  resourcestrings when TyDateTimeNamesTranslated says so. Everything that is a
  CONVENTION rather than a language -- separators, date order, the short-date
  pattern an empty DateFormat falls back to -- always stays the locale's: a
  Chinese-locale machine forced to English still writes 2026/8/7, it just says
  'August' where a name is asked for. Resolved at call time, never cached, so a
  catalogue loaded (or switched) after startup is honoured by the next paint. }
function TyDateTimeNames: TFormatSettings;

type
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
    FDisplaySettings: TTyCalDisplaySettings;
    FShowToday: Boolean;
    FReadOnly: Boolean;
    FViewYear: Word;
    FViewMonth: Word;
    FViewMode: TTyCalView;           // transient UI state, not published
    FOnChange: TNotifyEvent;
    FOnAccept: TNotifyEvent;
    FOnViewChange: TNotifyEvent;
    FOnDayChanged: TNotifyEvent;
    FOnMonthChanged: TNotifyEvent;
    FOnYearChanged: TNotifyEvent;
    procedure SetDate(AValue: TDateTime);
    { The only writer of FDate outside the user-gesture path. Takes the date AS GIVEN
      (no range check, no clamp) and re-anchors the view on it. Split out of SetDate so
      the three callers that must NOT raise -- streaming, SetDateClamped, and a
      MinDate/MaxDate move -- can store a value without going back through the guard
      that would reject the very thing they just computed. }
    procedure StoreDate(AValue: TDateTime);
    procedure SetMinDate(AValue: TDateTime);
    procedure SetMaxDate(AValue: TDateTime);
    procedure SetFirstDayOfWeek(AValue: TTyWeekDay);
    function  GetWeekNumbers: Boolean;
    procedure SetWeekNumbers(AValue: Boolean);
    procedure SetDisplaySettings(AValue: TTyCalDisplaySettings);
    procedure SetShowToday(AValue: Boolean);
    procedure SetReadOnly(AValue: Boolean);
    { Moves the view to a different month, clamping to valid year/month range.
      Fires OnMonthChanged / OnYearChanged for whichever component moved. }
    procedure SetViewMonth(AYear: Integer; AMonth: Integer);
    { Selects a cell date (used by keyboard AND the mouse), fires the per-component
      events then OnChange, in LCL's order (calendar.pp LMChanged :443-453). }
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
    { "Get as close as you can" -- the pre-3.0 behaviour of Date :=, now under a name
      that says so. Moves the selection to the nearest day inside MinDate..MaxDate and
      never raises. Use this where an out-of-range value is EXPECTED and harmless (a
      spin control walking off the end, a value seeded from a wider source); use Date :=
      where it would be a bug. Having both is the point: the caller states which one it
      meant, and the reader can see it. }
    procedure SetDateClamped(AValue: TDateTime);
    { Which region of the calendar APoint (client coords) falls in. The private layout
      maths is the only thing that can answer this, so without a public entry point a
      host wanting a per-region context menu or tooltip had to guess. LCL's
      TCustomCalendar.HitTest (C:/lazarus/lcl/calendar.pp:121, :219-225). }
    function HitTest(APoint: TPoint): TTyCalendarPart;
    { The drill-down level under LCL's name and PAGE-granularity spelling
      (C:/lazarus/lcl/calendar.pp:122). ViewMode is the same state named after the
      cell; both exist so neither reading is a guess. }
    function GetCalendarView: TTyCalendarView;
    { Expose RenderTo publicly for tests and embedding. }
    procedure RenderToPublic(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { Current drill-down view (transient UI state, not published). }
    property ViewMode: TTyCalView read FViewMode;
    { Current view anchor month (1-12, transient UI state). }
    property ViewMonth: Word read FViewMonth;
    { Current view anchor year (transient UI state). }
    property ViewYear: Word read FViewYear;
  published
    { NOTE the type. LCL's TCustomCalendar.Date is a STRING (calendar.pp) and its
      TDateTime twin is called DateTime -- which is the one TCalendar publishes. So
      `Cal.Date := Now` compiles here and fails there, and `Cal.DateTime` compiles
      there and fails here: the same name means different types on the two controls,
      which is the worst shape a difference can take. DateTime below is the alias that
      lets code written against either one compile against this.
      RANGE: writing a day outside MinDate..MaxDate RAISES ETyInvalidDate. It used to
      clamp in silence, which meant `Cal.Date := FromTheDatabase` could store a day the
      caller never chose and nothing anywhere said so. SetDateClamped is the clamping
      entry point for callers that want it. }
    property Date: TDateTime read FDate write SetDate;
    { LCL's name for the TDateTime accessor. Same storage as Date -- an alias, so a
      form ported from Lazarus needs no edit and neither does one written here. Not
      streamed (no stored flag would make sense for two names on one field): Date is
      the persisted one. }
    property DateTime: TDateTime read FDate write SetDate stored False;
    property MinDate: TDateTime read FMinDate write SetMinDate;
    property MaxDate: TDateTime read FMaxDate write SetMaxDate;
    { DEFAULT CHANGED in 3.0: was wdSunday, is now "ask the OS". A Monday-first locale
      -- most of Europe and Asia -- used to get a US week layout out of the box and had
      no value to set that meant "follow the system", only a hardcoded wdMonday that
      then stayed wrong if the app was relocalised. LCL has had dowDefault as its
      default all along (calendar.pp:127). Pin wdSunday explicitly if you relied on it. }
    property FirstDayOfWeek: TTyWeekDay read FFirstDayOfWeek write SetFirstDayOfWeek default wdLocaleDefault;
    { The whole chrome switch, LCL-shaped (calendar.pp:125-126). }
    property DisplaySettings: TTyCalDisplaySettings read FDisplaySettings
      write SetDisplaySettings default [dsShowHeadings, dsShowDayNames];
    { The week-number column under its old Boolean name. It is now a view onto
      DisplaySettings' dsShowWeekNumbers rather than a second copy of the same fact --
      one storage, so the two can never disagree. Not streamed (DisplaySettings is the
      persisted form); an .lfm that still carries `WeekNumbers = True` loads unchanged. }
    property WeekNumbers: Boolean read GetWeekNumbers write SetWeekNumbers stored False;
    property ShowToday: Boolean read FShowToday write SetShowToday default True;
    property ReadOnly: Boolean read FReadOnly write SetReadOnly default False;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    { The three per-component events LCL fires alongside OnChange (calendar.pp:131-133,
      fired from LMChanged :443-453). OnChange alone cannot answer "did the DAY move?"
      because we never passed the previous value, so every handler that cared had to
      keep its own shadow copy. Selection changes fire year, then month, then day, then
      OnChange -- LCL's order. Paging the header arrows fires the month/year pair too:
      that is the "load this month's appointments" hook, and it used to fire nothing. }
    property OnDayChanged: TNotifyEvent read FOnDayChanged write FOnDayChanged;
    property OnMonthChanged: TNotifyEvent read FOnMonthChanged write FOnMonthChanged;
    property OnYearChanged: TNotifyEvent read FOnYearChanged write FOnYearChanged;
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

uses
  { Only for the name resourcestrings + the load sentinel; kept out of the
    interface uses so the dependency stays one-way and invisible to hosts. }
  tyControls.StrConsts;

{ TyDateTimeNamesTranslated }

function TyDateTimeNamesTranslated: Boolean;
begin
  case TyDateTimeNameSource of
    dnLocale:      Result := False;
    dnTranslation: Result := True;
  else // dnAuto
    { Read the resourcestring EVERY time, never a copy taken at unit init:
      catalogues load from the program body, long after this unit initialised,
      and an init-time copy would freeze the English default forever. }
    Result := rsTyDateTimeNamesLang <> TyDateTimeNamesUntranslatedMark;
  end;
end;

{ TyDateTimeNames }

function TyDateTimeNames: TFormatSettings;
begin
  Result := DefaultFormatSettings;
  if not TyDateTimeNamesTranslated then Exit;
  Result.LongMonthNames[1]   := rsTyLongMonth1;
  Result.LongMonthNames[2]   := rsTyLongMonth2;
  Result.LongMonthNames[3]   := rsTyLongMonth3;
  Result.LongMonthNames[4]   := rsTyLongMonth4;
  Result.LongMonthNames[5]   := rsTyLongMonth5;
  Result.LongMonthNames[6]   := rsTyLongMonth6;
  Result.LongMonthNames[7]   := rsTyLongMonth7;
  Result.LongMonthNames[8]   := rsTyLongMonth8;
  Result.LongMonthNames[9]   := rsTyLongMonth9;
  Result.LongMonthNames[10]  := rsTyLongMonth10;
  Result.LongMonthNames[11]  := rsTyLongMonth11;
  Result.LongMonthNames[12]  := rsTyLongMonth12;
  Result.ShortMonthNames[1]  := rsTyShortMonth1;
  Result.ShortMonthNames[2]  := rsTyShortMonth2;
  Result.ShortMonthNames[3]  := rsTyShortMonth3;
  Result.ShortMonthNames[4]  := rsTyShortMonth4;
  Result.ShortMonthNames[5]  := rsTyShortMonth5;
  Result.ShortMonthNames[6]  := rsTyShortMonth6;
  Result.ShortMonthNames[7]  := rsTyShortMonth7;
  Result.ShortMonthNames[8]  := rsTyShortMonth8;
  Result.ShortMonthNames[9]  := rsTyShortMonth9;
  Result.ShortMonthNames[10] := rsTyShortMonth10;
  Result.ShortMonthNames[11] := rsTyShortMonth11;
  Result.ShortMonthNames[12] := rsTyShortMonth12;
  Result.LongDayNames[1]     := rsTyLongDay1;
  Result.LongDayNames[2]     := rsTyLongDay2;
  Result.LongDayNames[3]     := rsTyLongDay3;
  Result.LongDayNames[4]     := rsTyLongDay4;
  Result.LongDayNames[5]     := rsTyLongDay5;
  Result.LongDayNames[6]     := rsTyLongDay6;
  Result.LongDayNames[7]     := rsTyLongDay7;
  Result.ShortDayNames[1]    := rsTyShortDay1;
  Result.ShortDayNames[2]    := rsTyShortDay2;
  Result.ShortDayNames[3]    := rsTyShortDay3;
  Result.ShortDayNames[4]    := rsTyShortDay4;
  Result.ShortDayNames[5]    := rsTyShortDay5;
  Result.ShortDayNames[6]    := rsTyShortDay6;
  Result.ShortDayNames[7]    := rsTyShortDay7;
end;

{ TyResolveFirstDayOfWeek }

function TyResolveFirstDayOfWeek(AValue: TTyWeekDay): TTyWeekDay;
begin
  if AValue = wdLocaleDefault then
    Result := TyLocaleFirstDayOfWeek
  else
    Result := AValue;
end;

{ TyWeekdayOrder }

function TyWeekdayOrder(AFirst: TTyWeekDay): TTyWeekdayOrderArray;
var
  i: Integer;
  First: TTyWeekDay;
begin
  { Resolve here as well as at the call sites: this is a public helper, and a caller
    that passes wdLocaleDefault straight through would otherwise get Sunday's column
    order from Ord(7) mod 7 with nothing to say it had been ignored. }
  First := TyResolveFirstDayOfWeek(AFirst);
  for i := 0 to 6 do
    Result[i] := (Ord(First) + i) mod 7;
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
  AFirst := TyResolveFirstDayOfWeek(AFirst);
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

{ How a bound reads inside the ETyInvalidDate message. 0 is this unit's "unbounded"
  marker everywhere else, and printing it as a date would put "30-12-1899" in front of a
  developer who never set a MinDate and send them hunting for it. }
function TyCalendarBoundText(ABound: TDateTime): string;
begin
  if ABound = 0 then
    Result := '(no limit)'
  else
    Result := DateToStr(DateOf(ABound));
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
  FFirstDayOfWeek := wdLocaleDefault;
  FDisplaySettings := TyDefaultDisplaySettings;
  FShowToday    := True;
  FReadOnly     := False;
  FViewMode     := cvmDays;
  TabStop       := True;
  Width         := 240;
  { Classic keeps the 220px default verbatim. Modern derives the height from the same
    density tokens the layout uses -- header (--control-height) + weekday row
    (--item-height) + 6 day rows (--row-height) -- so the day grid grows roomier
    instead of squeezing 6 taller-font rows into a classic-sized box. }
  if ActiveController.Density = tdModern then
    Height := TyDensityMetric(ActiveController, 28, '--control-height')
            + TyDensityMetric(ActiveController, 20, '--item-height')
            + 6 * TyDensityMetric(ActiveController, 29, '--row-height')
  else
    Height := 220;
  DecodeDate(FDate, dy, dm, dd);
  FViewYear  := dy;
  FViewMonth := dm;
end;

function TTyCalendar.GetStyleTypeKey: string;
begin
  Result := 'TyCalendar';
end;

procedure TTyCalendar.StoreDate(AValue: TDateTime);
var
  d: TDateTime;
  dy, dm, dd: Word;
begin
  d := DateOf(AValue);
  if DateOf(FDate) = d then Exit;
  FDate := d;
  DecodeDate(FDate, dy, dm, dd);
  FViewYear  := dy;
  FViewMonth := dm;
  Invalidate;
end;

{ An out-of-range write used to be clamped in SILENCE: the caller read Date back and got
  a day it never asked for, so nothing distinguished "accepted" from "quietly corrected"
  -- the whole point of MinDate/MaxDate is to reject, and it was rejecting invisibly.
  LCL raises instead (CheckRange, C:/lazarus/lcl/calendar.pp:293-304, called from
  SetDateTime :329-332) and so do we now.

  Two paths deliberately do NOT raise, and both would be bugs if they did:

  * csLoading. A .lfm carrying a date outside its own MinDate/MaxDate must still open
    the form -- one drifted date is not worth failing an entire window over, and the
    exception would surface as an unhelpful EReadError far from the cause. The IDE
    happens to stream Date BEFORE the bounds (declaration order), so the date arrives
    while the calendar is still unbounded and the bounds re-clamp it afterwards; a
    hand-edited or reordered .lfm would take the other path, and this clamp is what
    keeps both of them loading.

  * MinDate/MaxDate moves. Tightening a bound past the standing date is the caller
    changing the RULES, not passing a bad value, so those setters call StoreDate with an
    already-clamped date and never re-enter this guard. LCL clamps there too
    (ApplyLimits, calendar.pp:353-361).

  User gestures are unaffected: SelectDate still refuses an out-of-range cell in silence,
  which is what a click on a disabled day should do. }
procedure TTyCalendar.SetDate(AValue: TDateTime);
begin
  if csLoading in ComponentState then
  begin
    StoreDate(TyCalendarClampDate(AValue, FMinDate, FMaxDate));
    Exit;
  end;
  if not TyCalendarInRange(AValue, FMinDate, FMaxDate) then
    { Name the offending date AND both bounds, as LCL's rsInvalidDateRangeHint does --
      "invalid date" alone costs the developer the same round trip the silent clamp did.
      An unset bound prints as its own "no limit" marker rather than 30-Dec-1899. }
    raise ETyInvalidDate.CreateFmt('Invalid Date: %s. Must be between %s and %s',
      [DateToStr(DateOf(AValue)), TyCalendarBoundText(FMinDate),
       TyCalendarBoundText(FMaxDate)]);
  StoreDate(AValue);
end;

procedure TTyCalendar.SetDateClamped(AValue: TDateTime);
begin
  StoreDate(TyCalendarClampDate(AValue, FMinDate, FMaxDate));
end;

{ Moving a bound past the standing date is the caller changing the rules, not passing a
  bad value, so it CLAMPS -- LCL does the same in ApplyLimits (calendar.pp:353-361).
  Note the call goes to StoreDate, not SetDate: routing the re-clamp back through the
  property setter would raise ETyInvalidDate on the very date this line exists to fix,
  and MinDate/MaxDate would be unusable at run time. }
procedure TTyCalendar.SetMinDate(AValue: TDateTime);
begin
  if FMinDate = AValue then Exit;
  FMinDate := AValue;
  StoreDate(TyCalendarClampDate(FDate, FMinDate, FMaxDate));
  Invalidate;       // always repaint: enabled/disabled cell appearance changed
end;

procedure TTyCalendar.SetMaxDate(AValue: TDateTime);
begin
  if FMaxDate = AValue then Exit;
  FMaxDate := AValue;
  StoreDate(TyCalendarClampDate(FDate, FMinDate, FMaxDate));
  Invalidate;       // always repaint: enabled/disabled cell appearance changed
end;

procedure TTyCalendar.SetFirstDayOfWeek(AValue: TTyWeekDay);
begin
  if FFirstDayOfWeek = AValue then Exit;
  FFirstDayOfWeek := AValue;
  Invalidate;
end;

function TTyCalendar.GetWeekNumbers: Boolean;
begin
  Result := dsShowWeekNumbers in FDisplaySettings;
end;

procedure TTyCalendar.SetWeekNumbers(AValue: Boolean);
begin
  if AValue then
    DisplaySettings := FDisplaySettings + [dsShowWeekNumbers]
  else
    DisplaySettings := FDisplaySettings - [dsShowWeekNumbers];
end;

procedure TTyCalendar.SetDisplaySettings(AValue: TTyCalDisplaySettings);
begin
  if FDisplaySettings = AValue then Exit;
  FDisplaySettings := AValue;
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

{ Paging the view is the "the user is now looking at a different month" signal, and it
  used to raise nothing at all -- the header arrows only clamped and repainted, so the
  common "fetch this month's appointments" wiring had no hook. LCL fires the same pair
  from its LMMonthChanged/LMYearChanged handlers (calendar.pp:458-478). }
procedure TTyCalendar.SetViewMonth(AYear: Integer; AMonth: Integer);
var
  oldY, oldM: Word;
begin
  while AMonth < 1  do begin Dec(AYear); Inc(AMonth, 12); end;
  while AMonth > 12 do begin Inc(AYear); Dec(AMonth, 12); end;
  if AYear < 1    then AYear := 1;
  if AYear > 9999 then AYear := 9999;
  oldY := FViewYear;
  oldM := FViewMonth;
  FViewYear  := AYear;
  FViewMonth := AMonth;
  Invalidate;
  if (Word(AYear) <> oldY) and Assigned(FOnYearChanged) then FOnYearChanged(Self);
  if (Word(AMonth) <> oldM) and Assigned(FOnMonthChanged) then FOnMonthChanged(Self);
end;

procedure TTyCalendar.SelectDate(ANewDate: TDateTime);
var
  d: TDateTime;
  dy, dm, dd: Word;
  oy, om, od: Word;
  oldDate: TDateTime;
begin
  if FReadOnly then Exit;
  d := DateOf(ANewDate);
  if not TyCalendarInRange(d, FMinDate, FMaxDate) then Exit;
  oldDate := DateOf(FDate);
  if oldDate = d then Exit;
  DecodeDate(oldDate, oy, om, od);
  FDate := d;
  DecodeDate(FDate, dy, dm, dd);
  FViewYear  := dy;
  FViewMonth := dm;
  Invalidate;
  { LCL's order, from LMChanged (calendar.pp:443-453): year, month, day, then OnChange.
    A handler chain that reloads on OnMonthChanged and then reads Date in OnChange
    depends on it, so it is not an arbitrary sequence. }
  if (oy <> dy) and Assigned(FOnYearChanged)  then FOnYearChanged(Self);
  if (om <> dm) and Assigned(FOnMonthChanged) then FOnMonthChanged(Self);
  if (od <> dd) and Assigned(FOnDayChanged)   then FOnDayChanged(Self);
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
  { Header band follows --control-height under modern density; classic keeps 28 verbatim.
    dsShowHeadings out of DisplaySettings zeroes it, and the grid takes the space back. }
  if dsShowHeadings in FDisplaySettings then
    HeaderH := MulDiv(TyDensityHeight(ActiveController, 28), APPI, 96)
  else
    HeaderH := 0;
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
  Names: TFormatSettings;
begin
  W      := ARect.Right - ARect.Left;
  ArrowW := HeaderH;
  FontSz := ResolveFontSize(S);
  FontWt := S.FontWeight;
  Names  := TyDateTimeNames;   // app language > loaded catalogue > OS locale

  // Header: [←] [YYYY] [→]
  ArrowLeftRect  := Rect(0, 0, ArrowW, HeaderH);
  ArrowRightRect := Rect(W - ArrowW, 0, W, HeaderH);
  TitleRect      := Rect(ArrowW, 0, W - ArrowW, HeaderH);

  { HeaderH is 0 when dsShowHeadings is out; nothing may be drawn into the collapsed
    band, and a 0x0 glyph rect is not something the painter should be asked to scale. }
  if HeaderH > 0 then
  begin
    P.DrawGlyph(ArrowLeftRect,  tgChevronLeft,  S.TextColor, 1);
    P.DrawGlyph(ArrowRightRect, tgChevronRight, S.TextColor, 1);
  end;

  TitleText := IntToStr(FViewYear);
  CellStyle := ActiveController.Model.ResolveStyle('TyCalendarTitle', '', [tysNormal]);
  if not (tpTextColor in CellStyle.Present) then CellStyle.TextColor := S.TextColor;
  if CellStyle.FontSize <= 0 then CellStyle.FontSize := FontSz;
  P.DrawText(TitleRect, TitleText, CellStyle.FontName, ResolveFontSize(CellStyle),
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

    P.DrawText(CellRect, Names.ShortMonthNames[i + 1],
      CellStyle.FontName, ResolveFontSize(CellStyle),
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

  { HeaderH is 0 when dsShowHeadings is out; nothing may be drawn into the collapsed
    band, and a 0x0 glyph rect is not something the painter should be asked to scale. }
  if HeaderH > 0 then
  begin
    P.DrawGlyph(ArrowLeftRect,  tgChevronLeft,  S.TextColor, 1);
    P.DrawGlyph(ArrowRightRect, tgChevronRight, S.TextColor, 1);
  end;

  TitleText := IntToStr(DS) + '–' + IntToStr(DS + 9);
  CellStyle := ActiveController.Model.ResolveStyle('TyCalendarTitle', '', [tysNormal]);
  if not (tpTextColor in CellStyle.Present) then CellStyle.TextColor := S.TextColor;
  if CellStyle.FontSize <= 0 then CellStyle.FontSize := FontSz;
  P.DrawText(TitleRect, TitleText, CellStyle.FontName, ResolveFontSize(CellStyle),
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
      CellStyle.FontName, ResolveFontSize(CellStyle),
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

  { HeaderH is 0 when dsShowHeadings is out; nothing may be drawn into the collapsed
    band, and a 0x0 glyph rect is not something the painter should be asked to scale. }
  if HeaderH > 0 then
  begin
    P.DrawGlyph(ArrowLeftRect,  tgChevronLeft,  S.TextColor, 1);
    P.DrawGlyph(ArrowRightRect, tgChevronRight, S.TextColor, 1);
  end;

  TitleText := IntToStr(CentStart) + '–' + IntToStr(CentStart + 99);
  CellStyle := ActiveController.Model.ResolveStyle('TyCalendarTitle', '', [tysNormal]);
  if not (tpTextColor in CellStyle.Present) then CellStyle.TextColor := S.TextColor;
  if CellStyle.FontSize <= 0 then CellStyle.FontSize := FontSz;
  P.DrawText(TitleRect, TitleText, CellStyle.FontName, ResolveFontSize(CellStyle),
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
      CellStyle.FontName, ResolveFontSize(CellStyle),
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
  { Density-aware bands: header ~ --control-height, weekday-names row ~ --item-height.
    Classic returns the original constants verbatim (byte-identical); only modern density
    reads the roomier tokens. WkNumW stays a fixed classic width (no density token).
    Each band collapses to 0 when its DisplaySettings flag is out, and the day rows
    divide up whatever is left -- suppressing chrome must GIVE the space to the grid,
    not leave a hole where the band was. }
  if dsShowHeadings in FDisplaySettings then
    HeaderH := MulDiv(TyDensityHeight(ActiveController, 28), APPI, 96)
  else
    HeaderH := 0;
  if not (dsShowDayNames in FDisplaySettings) then
    WeekdayH := 0
  else if ActiveController.Density = tdModern then
    WeekdayH := MulDiv(TyDensityMetric(ActiveController, 20, '--item-height'), APPI, 96)
  else
    WeekdayH := MulDiv(20, APPI, 96);
  if dsShowWeekNumbers in FDisplaySettings then
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
  Names: TFormatSettings;
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
    Names  := TyDateTimeNames;   // app language > loaded catalogue > OS locale

    CalcLayout(ARect, APPI, HeaderH, WeekdayH, WkNumW, ColW, RowH, GridRect);

    // Header band: [←] [Month YYYY] [→]   (suppressed by dsShowHeadings)
    if HeaderH > 0 then
    begin
      ArrowW         := HeaderH;
      ArrowLeftRect  := Rect(0, 0, ArrowW, HeaderH);
      ArrowRightRect := Rect(W - ArrowW, 0, W, HeaderH);
      TitleRect      := Rect(ArrowW, 0, W - ArrowW, HeaderH);

      P.DrawGlyph(ArrowLeftRect,  tgChevronLeft,  S.TextColor, 1);
      P.DrawGlyph(ArrowRightRect, tgChevronRight, S.TextColor, 1);

      { Title text. The month name goes through TyDateTimeNames, NOT the bare
        DefaultFormatSettings: the app's language wins over the machine's.
        HitTest measures this same string with the same settings -- change one,
        change the other, or the month/year click split drifts off the glyphs. }
      TitleText := FormatDateTime('mmmm yyyy',
        EncodeDate(FViewYear, FViewMonth, 1), Names);
      CellStyle := ActiveController.Model.ResolveStyle('TyCalendarTitle', '', [tysNormal]);
      if not (tpTextColor in CellStyle.Present) then
        CellStyle.TextColor := S.TextColor;
      if CellStyle.FontSize <= 0 then
        CellStyle.FontSize := FontSz;
      P.DrawText(TitleRect, TitleText, CellStyle.FontName, ResolveFontSize(CellStyle),
        FontWt, CellStyle.TextColor, taCenter, tlCenter, False);
    end;

    // Weekday name row   (suppressed by dsShowDayNames)
    WeekOrderArr := TyWeekdayOrder(FFirstDayOfWeek);
    CellStyle := ActiveController.Model.ResolveStyle('TyCalendarWeekday', '', [tysNormal]);
    if not (tpTextColor in CellStyle.Present) then
      CellStyle.TextColor := S.TextColor;
    if CellStyle.FontSize <= 0 then
      CellStyle.FontSize := FontSz;

    if WeekdayH > 0 then
    begin
      // Week number header label (blank area above week-number column)
      if WkNumW > 0 then
      begin
        WkNumRect := Rect(0, HeaderH, WkNumW, HeaderH + WeekdayH);
        P.DrawText(WkNumRect, '#', CellStyle.FontName, ResolveFontSize(CellStyle),
          FontWt, CellStyle.TextColor, taCenter, tlCenter, False);
      end;

      for col := 0 to 6 do
      begin
        // ShortDayNames: 1=Sunday .. 7=Saturday, TFormatSettings order
        DayName  := Names.ShortDayNames[WeekOrderArr[col] + 1];
        CellRect := Rect(
          GridRect.Left + col * ColW,
          HeaderH,
          GridRect.Left + (col + 1) * ColW,
          HeaderH + WeekdayH);
        P.DrawText(CellRect, DayName, CellStyle.FontName, ResolveFontSize(CellStyle),
          FontWt, CellStyle.TextColor, taCenter, tlCenter, False);
      end;
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
      P.DrawText(CellRect, IntToStr(CellD), CellStyle.FontName, ResolveFontSize(CellStyle),
        FontWt, CellStyle.TextColor, taCenter, tlCenter, False);

      // Week number (leftmost column only)
      if (WkNumW > 0) and (col = 0) then
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
        P.DrawText(WkNumRect, IntToStr(wkNum), CellStyle.FontName, ResolveFontSize(CellStyle),
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

function TTyCalendar.GetCalendarView: TTyCalendarView;
begin
  { Deliberately a straight positional map and not a cast: the two enums count the same
    four levels but name them one level apart (LCL's cvMonth = "a grid of days in one
    month" = our cvmDays), and a cast would silently answer one level out. }
  case FViewMode of
    cvmDays:    Result := cvMonth;
    cvmMonths:  Result := cvYear;
    cvmYears:   Result := cvDecade;
    cvmDecades: Result := cvCentury;
  else
    Result := cvMonth;
  end;
end;

function TTyCalendar.HitTest(APoint: TPoint): TTyCalendarPart;
{ The header split is measured, not guessed: the title is drawn centred, so the month
  name's pixel span depends on the resolved font and on the locale's month names, and
  the only honest way to say "you clicked the year" is to measure the same string the
  renderer draws. }
var
  HeaderH, WeekdayH, WkNumW, ColW, RowH, ArrowW, W, PPI: Integer;
  GridRect, GridRect4: TRect;
  HdrH4, ColW4, RowH4: Integer;
  S: TTyStyleSet;
  TitleStyle: TTyStyleSet;
  TitleText, MonthPart: string;
  SpacePos, FullW, MonthW, TitleLeft, TitleW: Integer;
  Bmp: TBGRABitmap;
begin
  Result := cpNoWhere;
  W   := ClientWidth;
  PPI := Font.PixelsPerInch;

  if FViewMode <> cvmDays then
  begin
    CalcLayout4x3(ClientRect, PPI, HdrH4, ColW4, RowH4, GridRect4);
    if (HdrH4 > 0) and (APoint.Y >= 0) and (APoint.Y < HdrH4) then
    begin
      if (APoint.X < HdrH4) or (APoint.X >= W - HdrH4) then
        Result := cpTitleBtn
      else
        Result := cpTitle;
      Exit;
    end;
    if TyCalendarHitCell(GridRect4, 4, 3, APoint.X, APoint.Y) >= 0 then
      Result := cpDate;
    Exit;
  end;

  CalcLayout(ClientRect, PPI, HeaderH, WeekdayH, WkNumW, ColW, RowH, GridRect);
  ArrowW := HeaderH;

  if (HeaderH > 0) and (APoint.Y >= 0) and (APoint.Y < HeaderH) then
  begin
    if (APoint.X < ArrowW) or (APoint.X >= W - ArrowW) then
      Exit(cpTitleBtn);
    { The SAME string RenderTo draws, from the SAME name source -- measuring the
      locale's 八月 while the renderer drew 'August' would put the month/year
      split at the wrong pixel, which is the exact drift this measure exists
      to prevent. }
    TitleText  := FormatDateTime('mmmm yyyy',
      EncodeDate(FViewYear, FViewMonth, 1), TyDateTimeNames);
    S          := CurrentStyle;
    TitleStyle := ActiveController.Model.ResolveStyle('TyCalendarTitle', '', [tysNormal]);
    if TitleStyle.FontSize <= 0 then TitleStyle.FontSize := ResolveFontSize(S);
    SpacePos := Pos(' ', TitleText);
    Result   := cpTitle;
    if SpacePos > 0 then
    begin
      MonthPart := Copy(TitleText, 1, SpacePos - 1);
      Bmp := TBGRABitmap.Create(1, 1);
      try
        TyConfigureTextFont(Bmp, TitleStyle.FontName, ResolveFontSize(TitleStyle),
          S.FontWeight, PPI);
        FullW  := Bmp.TextSize(TitleText).cx;
        MonthW := Bmp.TextSize(MonthPart).cx;
      finally
        Bmp.Free;
      end;
      TitleW    := W - 2 * ArrowW;
      TitleLeft := ArrowW + (TitleW - FullW) div 2;    // taCenter, as RenderTo draws it
      if (APoint.X >= TitleLeft) and (APoint.X < TitleLeft + FullW) then
      begin
        if APoint.X < TitleLeft + MonthW then
          Result := cpTitleMonth
        else
          Result := cpTitleYear;
      end;
    end;
    Exit;
  end;

  { The week-number column runs beside the day rows only -- the strip beside the
    weekday-name row is the '#' caption, which is chrome, not a week number. }
  if (WkNumW > 0) and (APoint.X >= 0) and (APoint.X < WkNumW) and
     (APoint.Y >= GridRect.Top) and (APoint.Y < GridRect.Bottom) then
    Exit(cpWeekNumber);

  if TyCalendarHitCell(GridRect, 7, 6, APoint.X, APoint.Y) >= 0 then
    Result := cpDate;
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

    { The whole band is gone when dsShowHeadings is out; skip its three hit-tests
      rather than let them match at y=0 against a zero-height rect. }
    if HdrH4 > 0 then
    begin
      // Left arrow.  Routed through SetViewMonth (not a raw FViewYear write) so the
      // year move announces itself through OnYearChanged like every other one does.
      if (X >= 0) and (X < ArrowW) and (Y >= 0) and (Y < HdrH4) then
      begin
        case FViewMode of
          cvmMonths:  SetViewMonth(FViewYear - 1,   FViewMonth);   // ∓1 year
          cvmYears:   SetViewMonth(FViewYear - 10,  FViewMonth);   // ∓10 years (decade)
          cvmDecades: SetViewMonth(FViewYear - 100, FViewMonth);   // ∓100 years (century)
        end;
        Exit;
      end;

      // Right arrow
      if (X >= W - ArrowW) and (X < W) and (Y >= 0) and (Y < HdrH4) then
      begin
        case FViewMode of
          cvmMonths:  SetViewMonth(FViewYear + 1,   FViewMonth);
          cvmYears:   SetViewMonth(FViewYear + 10,  FViewMonth);
          cvmDecades: SetViewMonth(FViewYear + 100, FViewMonth);
        end;
        Exit;
      end;

      // Title click: zoom out another level
      if (X >= ArrowW) and (X < W - ArrowW) and (Y >= 0) and (Y < HdrH4) then
      begin
        ChangeViewMode(TyCalendarZoomOut(FViewMode));
        Exit;
      end;
    end;

    // Grid cell click: pick and zoom in
    cellIdx := TyCalendarHitCell(GridRect4, 4, 3, X, Y);
    if cellIdx < 0 then Exit;

    case FViewMode of
      { All three go through SetViewMonth rather than writing FViewYear/FViewMonth by
        hand: drilling in IS a view move, and a host listening for "which month are we
        looking at now" must not have to special-case the way the user got there. }
      cvmMonths:
        begin
          // Pick the month; zoom to Days of that month
          cellMonth  := cellIdx + 1;   // 1..12
          SetViewMonth(FViewYear, cellMonth);
          ChangeViewMode(TyCalendarZoomIn(FViewMode));
        end;
      cvmYears:
        begin
          // Pick the year (spill layout: cell 0 = DS-1)
          DS       := TyDecadeStart(FViewYear);
          cellYear := DS - 1 + cellIdx;
          SetViewMonth(cellYear, FViewMonth);
          ChangeViewMode(TyCalendarZoomIn(FViewMode));
        end;
      cvmDecades:
        begin
          // Pick a decade (spill layout: cell 0 = CentStart-10)
          CentStart   := (Integer(FViewYear) div 100) * 100;
          cellDecade  := CentStart - 10 + cellIdx * 10;
          SetViewMonth(cellDecade, FViewMonth);   // that decade's start year
          ChangeViewMode(TyCalendarZoomIn(FViewMode));
        end;
    end;
    Exit;
  end;

  // === Days view (existing logic) ===

  CalcLayout(ClientRect, Font.PixelsPerInch,
    HeaderH, WeekdayH, WkNumW, ColW, RowH, GridRect);
  ArrowW := HeaderH;

  if HeaderH > 0 then
  begin
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
  end;

  // Grid cell
  cellIdx := TyCalendarHitCell(GridRect, 7, 6, X, Y);
  if cellIdx < 0 then Exit;

  Grid     := TyCalendarMonthGrid(FViewYear, FViewMonth, FFirstDayOfWeek);
  CellDate := Grid[cellIdx];
  DecodeDate(CellDate, CellY, CellM, dummy);

  { A spill-over day (a greyed cell from the previous/next month) used to be dropped
    on the floor: the click did nothing and nothing said why. LCL pages to that day's
    month instead, and only refuses when dsNoMonthChange is IN DisplaySettings -- which
    it is not by default (calendar.pp:46). So the default here now matches: the click
    selects the day and SelectDate re-anchors the view onto its month.
    BEHAVIOUR CHANGE: pass dsNoMonthChange to get the old refusal back. }
  if ((CellM <> FViewMonth) or (CellY <> FViewYear)) and
     (dsNoMonthChange in FDisplaySettings) then Exit;
  if not TyCalendarInRange(CellDate, FMinDate, FMaxDate) then Exit;
  if FReadOnly then Exit;

  { SelectDate is the single writer: it re-anchors the view, fires the per-component
    events and OnChange, and no-ops when the date did not move. Duplicating that here
    is what let the mouse path drift away from the keyboard path in the first place. }
  SelectDate(DateOf(CellDate));

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

{ Reads the OS's "first day of week" once, at unit start, into TyLocaleFirstDayOfWeek.
  Win32 API and not a widgetset call, so the gate is WINDOWS, not LCLWin32. Elsewhere
  the seeded wdSunday stands: the RTL exposes no first-day-of-week and inventing one
  from the language would be a guess, so a host on those platforms sets the variable. }
procedure TyInitLocaleFirstDayOfWeek;
{$IFDEF WINDOWS}
var
  Buf: array[0..7] of WideChar;
  v: Integer;
{$ENDIF}
begin
{$IFDEF WINDOWS}
  { LOCALE_IFIRSTDAYOFWEEK is 0 = Monday .. 6 = Sunday -- a different origin from
    TTyWeekDay's 0 = Sunday, hence the rotation rather than a straight cast. }
  if GetLocaleInfoW(LOCALE_USER_DEFAULT, LOCALE_IFIRSTDAYOFWEEK, @Buf[0], Length(Buf)) > 0 then
  begin
    v := StrToIntDef(string(WideString(PWideChar(@Buf[0]))), -1);
    if (v >= 0) and (v <= 6) then
      TyLocaleFirstDayOfWeek := TTyWeekDay((v + 1) mod 7);
  end;
{$ENDIF}
end;

initialization
  TyInitLocaleFirstDayOfWeek;

end.
