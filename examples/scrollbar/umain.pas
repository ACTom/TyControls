unit umain;

{ TTyScrollBar example:
  - a vertical scroll bar (Kind=sbVertical) and a horizontal one (Kind=sbHorizontal)
  - demonstrates Min / Max / Position / PageSize / SmallChange
  - OnChange live-aggregates both bars' Position into a TTyLabel status line
  UI is built purely in code (no .lfm); the main window is TTyForm + TTyTitleBar. }

{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.ScrollBar, tyControls.TyLabel;
type
  TMainForm = class(TTyForm)
  private
    FVBar: TTyScrollBar;      // vertical scroll bar
    FHBar: TTyScrollBar;      // horizontal scroll bar
    FStatus: TTyLabel;        // OnChange status readout
    procedure BarChange(Sender: TObject);
    procedure UpdateStatus;
  public
    constructor Create(AOwner: TComponent); override;
  end;
var
  MainForm: TMainForm;
implementation
{ up-search for the repo themes/ dir from the exe location }
function ThemesDir: string;
var Dir: string; i: Integer;
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

procedure TMainForm.UpdateStatus;
begin
  FStatus.Caption := Format(
    '垂直:  Position = %d   (Min %d / Max %d / PageSize %d / SmallChange %d)' + LineEnding +
    LineEnding +
    '水平:  Position = %d   (Min %d / Max %d / PageSize %d / SmallChange %d)',
    [FVBar.Position, FVBar.Min, FVBar.Max, FVBar.PageSize, FVBar.SmallChange,
     FHBar.Position, FHBar.Min, FHBar.Max, FHBar.PageSize, FHBar.SmallChange]);
end;

procedure TMainForm.BarChange(Sender: TObject);
begin
  UpdateStatus;   // refresh the status line whenever either bar changes
end;

constructor TMainForm.Create(AOwner: TComponent);
var Bar: TTyTitleBar; Tip: TTyLabel;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm: borderless + persistent engine
  Caption := '滚动条 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 480, 360);
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // load theme FIRST
  Bar := TTyTitleBar.Create(Self);         // Owner=Self -> auto-associates as TTyForm.TitleBar
  Bar.Parent := Self; Bar.Align := alTop; Bar.Height := 34;
  Bar.Caption := 'ScrollBar  · TyControls';

  { hint text }
  Tip := TTyLabel.Create(Self);
  Tip.Parent := Self;
  Tip.Caption := '拖动滑块、点击轨道/箭头，或用方向键/PageUp/PageDown 滚动';
  Tip.SetBounds(24, 48, 432, 20);

  { ==== vertical scroll bar: range 0..200, PageSize 20, SmallChange 5, starts centered ==== }
  FVBar := TTyScrollBar.Create(Self);
  FVBar.Parent := Self;
  FVBar.Kind := sbVertical;
  FVBar.Min := 0;
  FVBar.Max := 200;
  FVBar.PageSize := 20;
  FVBar.SmallChange := 5;
  FVBar.Position := 100;
  FVBar.SetBounds(28, 80, 18, 236);
  FVBar.OnChange := @BarChange;

  { ==== horizontal scroll bar: range 0..100, PageSize 10, SmallChange 2 ==== }
  FHBar := TTyScrollBar.Create(Self);
  FHBar.Parent := Self;
  FHBar.Kind := sbHorizontal;
  FHBar.Min := 0;
  FHBar.Max := 100;
  FHBar.PageSize := 10;
  FHBar.SmallChange := 2;
  FHBar.Position := 25;
  FHBar.SetBounds(80, 298, 372, 18);
  FHBar.OnChange := @BarChange;

  { ==== status label: reflects both bars' Position and their parameters ==== }
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.WordWrap := True;
  FStatus.SetBounds(80, 96, 372, 90);

  UpdateStatus;                            // initial readout

  ApplyChromeTheme(TyDefaultController);   // theme the whole chrome + form bg LAST
end;

end.
