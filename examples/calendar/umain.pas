unit umain;
{$mode objfpc}{$H+}

{ TTyCalendar demo: a TTyForm + TTyTitleBar shell showcasing the calendar's key features:
  - Date: initially selected date; OnChange echoes the picked date
  - OnAccept: confirmed on clicking a day cell / pressing Enter (echoes "confirmed")
  - OnViewChange: click the header to drill down day->month->year->decade, echoing the current view level
  - MinDate/MaxDate: constrain the selectable date range; out-of-range dates are greyed out and unselectable
  - FirstDayOfWeek: first day of the week (here wdMonday, Monday start)
  - WeekNumbers: show the ISO week-number column
  - ShowToday: outline highlight on today
  - Second calendar: ReadOnly=True, read-only display
  UI is created purely in code (no .lfm); controls with no explicit Controller automatically use the global TyDefaultController. }

interface

uses
  Classes, SysUtils, DateUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.Calendar, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FCal: TTyCalendar;
    FPicked: TTyLabel;
    FAccepted: TTyLabel;
    FView: TTyLabel;
    procedure CalChange(Sender: TObject);
    procedure CalAccept(Sender: TObject);
    procedure CalViewChange(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ Walk up from the exe's directory to find the repo's themes/ directory }
function ThemesDir: string;
var
  Dir: string;
  i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim;
end;

function ViewName(AView: TTyCalView): string;
begin
  case AView of
    cvmMonths:  Result := '月视图 (cvmMonths)';
    cvmYears:   Result := '年视图 (cvmYears)';
    cvmDecades: Result := '十年视图 (cvmDecades)';
  else
    Result := '日视图 (cvmDays)';
  end;
end;

procedure TMainForm.CalChange(Sender: TObject);
begin
  FPicked.Caption := '已选日期：' + FormatDateTime('yyyy-mm-dd', FCal.Date);
end;

procedure TMainForm.CalAccept(Sender: TObject);
begin
  FAccepted.Caption := '已确认：' + FormatDateTime('yyyy-mm-dd', FCal.Date) +
    '（点击日期格 / 回车触发 OnAccept）';
end;

procedure TMainForm.CalViewChange(Sender: TObject);
begin
  FView.Caption := '当前视图：' + ViewName(FCal.ViewMode) +
    '（点标题下钻，点日期格上钻）';
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
  Lbl: TTyLabel;
  RO: TTyCalendar;
  Today: TDateTime;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm: borderless + persistent engine
  Caption := 'Calendar 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 720, 590);
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // load theme FIRST

  Bar := TTyTitleBar.Create(Self);         // Owner=Self -> auto-associates as TTyForm.TitleBar
  Bar.Parent := Self; Bar.Align := alTop; Bar.Height := 34;
  Bar.Caption := 'Calendar  · TyControls';

  Today := DateOf(Now);

  { ---- Main calendar: interactive, demonstrates most features ---- }
  Lbl := TTyLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.SetBounds(20, 48, 320, 22);
  Lbl.Caption := '可交互日历（周一起始 · 显示周数 · 今日高亮）：';

  FCal := TTyCalendar.Create(Self);
  FCal.Parent := Self;
  FCal.SetBounds(20, 74, 320, 300);
  FCal.Date := Today;                       // initially select today
  FCal.FirstDayOfWeek := wdMonday;          // Monday is the first day of the week
  FCal.WeekNumbers := True;                 // show the ISO week-number column on the left
  FCal.ShowToday := True;                   // outline highlight on today
  { Constrain the selectable range: 20 days either side of today; out-of-range dates are greyed out and unselectable }
  FCal.MinDate := IncDay(Today, -20);
  FCal.MaxDate := IncDay(Today, 20);
  FCal.OnChange := @CalChange;
  FCal.OnAccept := @CalAccept;
  FCal.OnViewChange := @CalViewChange;

  { ---- Status echo ---- }
  FPicked := TTyLabel.Create(Self);
  FPicked.Parent := Self;
  FPicked.SetBounds(360, 74, 340, 22);

  FAccepted := TTyLabel.Create(Self);
  FAccepted.Parent := Self;
  FAccepted.SetBounds(360, 100, 340, 44);

  FView := TTyLabel.Create(Self);
  FView.Parent := Self;
  FView.SetBounds(360, 150, 340, 44);

  Lbl := TTyLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.SetBounds(360, 206, 340, 88);
  Lbl.Caption := '可选区间：' +
    FormatDateTime('yyyy-mm-dd', FCal.MinDate) + ' ~ ' +
    FormatDateTime('yyyy-mm-dd', FCal.MaxDate) + sLineBreak +
    '键盘：方向键移动，PageUp/Down 换月，Home/End 月首末。';

  { ---- Read-only calendar: ReadOnly=True, demonstrates selection being disabled ---- }
  Lbl := TTyLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.SetBounds(360, 300, 340, 22);
  Lbl.Caption := '只读日历 (ReadOnly=True · 周日起始)：';

  RO := TTyCalendar.Create(Self);
  RO.Parent := Self;
  RO.SetBounds(360, 326, 320, 230);
  RO.Date := Today;
  RO.FirstDayOfWeek := wdSunday;
  RO.ReadOnly := True;

  // initialize the status echo
  CalChange(nil);
  CalViewChange(nil);
  FAccepted.Caption := '尚未确认（点击一个日期格或按回车）';

  ApplyChromeTheme(TyDefaultController);   // theme the whole chrome + form bg LAST
end;

end.
