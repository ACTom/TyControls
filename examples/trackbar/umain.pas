unit umain;

{ TTyTrackBar demo, in two columns.

  Left, one thumb (TTyTrackBar):
  - Horizontal track bar (0..100), OnChange updates the status label live
  - Custom-range track bar (-50..50, shows a negative range)
  - Vertical track bar (Orientation = toVertical) with ticks, tick labels and its own readout
  - Fine-stepping track bar (PageSize / Frequency demo, its own range and readout)
  - ShowValue: the bar paints its own number (right end horizontal, under the track vertical)
  - LineSize: a bar whose arrow-key / wheel step is 5 instead of 1
  - AnimationsEnabled toggled from code (it is public, not published, so no .lfm can set it)

  Right, several thumbs (TTyRangeTrackBar / TTyMultiTrackBar / TTyGradientTrackBar), with the
  bars' own adding, removing and dragging switched on in umain.lfm:
  - Two ranges, MinGap = 5, tick labels; a click on the bare track adds a range there
    (AllowUserRanges), a range's highlight drags the whole range (DraggableRanges), an end
    dragged off the track removes its range
  - Gradient stops (TTyGradientTrackBar): a click on the track adds a stop in the colour the
    gradient has there, a double-click on a stop changes its colour, a stop dragged off the
    track goes; the first and last stops are pinned where they are but stay selectable
    (OnThumbChanging) and cannot be removed (OnThumbRemoving), and a TTyPaintPanel below
    paints the same gradient from GradientFill
  - Three thresholds, the stretches between them coloured by segment class; a dragged thumb
    pushes its neighbours along (Pushable)
  - A range of months: the tick labels 1..12 become month names (OnFormatTickLabel)

  Whatever a handler here does, it runs before the bar's own behaviour and can stop it: a stop
  refused in OnThumbRemoving stays, a move refused in OnThumbChanging does not happen.

  The main form (a TTyForm + TTyTitleBar), the column headings, every track bar and the live theme
  switcher are designed in umain.lfm; the code here is event handlers + theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics, Forms, Controls,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.Form,
  tyControls.BuiltinThemes, tyControls.TrackBar, tyControls.MultiTrackBar, tyControls.TyLabel,
  tyControls.ComboBox, tyControls.ToggleSwitch, tyControls.Divider, tyControls.PaintPanel;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    DivSingle: TTyDivider;
    LblVolume: TTyLabel;
    Track1: TTyTrackBar;
    LblBalance: TTyLabel;
    Track2: TTyTrackBar;
    LblBrightness: TTyLabel;
    Track4: TTyTrackBar;
    LblVertical: TTyLabel;
    Track3: TTyTrackBar;
    LblStatus: TTyLabel;
    LblShowValueHint: TTyLabel;
    LblVerticalHint: TTyLabel;
    LblLineSize: TTyLabel;
    Track5: TTyTrackBar;
    AnimSwitch: TTyToggleSwitch;
    LblAnimHint: TTyLabel;
    LblKeysTitle: TTyLabel;
    LblKeys1: TTyLabel;
    LblKeys2: TTyLabel;
    LblKeys3: TTyLabel;
    DivMulti: TTyDivider;
    LblRange: TTyLabel;
    Range1: TTyRangeTrackBar;
    LblRangeHint: TTyLabel;
    LblRangeHint2: TTyLabel;
    LblRangeHint3: TTyLabel;
    LblStops: TTyLabel;
    Stops: TTyGradientTrackBar;
    StopsPreview: TTyPaintPanel;
    LblStopsHint: TTyLabel;
    LblStopsHint2: TTyLabel;
    LblMulti: TTyLabel;
    Multi1: TTyMultiTrackBar;
    LblMultiHint: TTyLabel;
    LblMultiHint2: TTyLabel;
    LblMonths: TTyLabel;
    Months: TTyRangeTrackBar;
    LblMultiStatus: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure Track1Change(Sender: TObject);
    procedure Track2Change(Sender: TObject);
    procedure Track3Change(Sender: TObject);
    procedure Track4Change(Sender: TObject);
    procedure Track5Change(Sender: TObject);
    procedure AnimSwitchChange(Sender: TObject);
    procedure Range1Change(Sender: TObject);
    procedure StopsChange(Sender: TObject);
    procedure StopsPreviewPaint(Sender: TObject; APainter: TTyPainter; const AContent: TRect);
    procedure StopsThumbChanging(Sender: TObject; AIndex: Integer; var AValue: Integer;
      var AAllow: Boolean);
    procedure StopsThumbRemoving(Sender: TObject; AIndex: Integer; var AAllow: Boolean);
    procedure Multi1Change(Sender: TObject);
    procedure MonthsChange(Sender: TObject);
    procedure MonthsFormatTickLabel(Sender: TObject; AValue: Integer; var AText: string);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  { Status texts composed at run time, so they live here rather than in the .lfm. }
  rsVolumeFmt     = 'Volume: %d';
  rsBalanceFmt    = 'Balance: %d';
  rsVerticalFmt   = 'Vertical: %d';
  rsBrightnessFmt = 'Brightness: %d';
  rsFineFmt       = 'Fine: %d';
  rsAnimOn  = 'AnimationsEnabled = True (thumb eases)';
  rsAnimOff = 'AnimationsEnabled = False (thumb jumps)';
  rsRangesFmt     = 'Ranges: %s';
  rsThresholdsFmt = 'Thresholds: %d / %d / %d';
  rsStopsFmt      = 'Gradient stops: %d';
  rsMonthsFmt     = 'Months: %s to %s';
  { The month names on the months bar, January first, comma-separated. }
  rsShortMonths   = 'Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec';

{ Month AValue (1..12) by the translated rsShortMonths; the number itself if the list is short. }
function MonthName(AValue: Integer): string;
var
  rest: string;
  i, p: Integer;
begin
  Result := IntToStr(AValue);
  if AValue < 1 then Exit;
  rest := rsShortMonths + ',';
  for i := 1 to AValue - 1 do
  begin
    p := Pos(',', rest);
    if p = 0 then Exit;
    Delete(rest, 1, p);
  end;
  p := Pos(',', rest);
  if p > 1 then Result := Trim(Copy(rest, 1, p - 1));
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
begin
  // Built-in themes are compiled in, so the switcher works without locating a themes/ folder.
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);   // theme the window chrome + background
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);   // re-theme the shell on every skin change
end;

procedure TMainForm.DarkSwitchChange(Sender: TObject);
begin
  // Flip the light/dark @mode axis (independent of which theme ThemeCombo picked).
  if DarkSwitch.Checked then
    TyDefaultController.Mode := 'dark'
  else
    TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.Track1Change(Sender: TObject);
begin
  LblStatus.Caption := Format(rsVolumeFmt, [(Sender as TTyTrackBar).Position]);
end;

procedure TMainForm.Track2Change(Sender: TObject);
begin
  LblStatus.Caption := Format(rsBalanceFmt, [(Sender as TTyTrackBar).Position]);
end;

procedure TMainForm.Track3Change(Sender: TObject);
begin
  LblStatus.Caption := Format(rsVerticalFmt, [(Sender as TTyTrackBar).Position]);
end;

procedure TMainForm.Track4Change(Sender: TObject);
begin
  LblStatus.Caption := Format(rsBrightnessFmt, [(Sender as TTyTrackBar).Position]);
end;

{ LineSize = 5: every arrow key and every wheel notch moves this bar by 5, while
  PageUp/PageDown still move by PageSize (25). }
procedure TMainForm.Track5Change(Sender: TObject);
begin
  LblStatus.Caption := Format(rsFineFmt, [(Sender as TTyTrackBar).Position]);
end;

{ AnimationsEnabled is PUBLIC, not published, so no .lfm can reach it -- only code.
  On (the default) the thumb eases ~120 ms to a keyboard/wheel change; off it jumps.
  A live drag always tracks the mouse exactly, either way. }
procedure TMainForm.AnimSwitchChange(Sender: TObject);
begin
  Track1.AnimationsEnabled := AnimSwitch.Checked;
  Track2.AnimationsEnabled := AnimSwitch.Checked;
  Track3.AnimationsEnabled := AnimSwitch.Checked;
  Track4.AnimationsEnabled := AnimSwitch.Checked;
  Track5.AnimationsEnabled := AnimSwitch.Checked;
  if AnimSwitch.Checked then
    LblStatus.Caption := rsAnimOn
  else
    LblStatus.Caption := rsAnimOff;
end;

{ The thumbs run Low0, High0, Low1, High1, ..., and each item reads what its thumbs show. A
  range the user adds, drags or removes fires OnChange as a moved end does. }
procedure TMainForm.Range1Change(Sender: TObject);
var
  s: string;
  i: Integer;
begin
  s := '';
  for i := 0 to Range1.Ranges.Count - 1 do
  begin
    if i > 0 then s := s + ', ';
    s := s + Format('%d..%d', [Range1.Ranges[i].Low, Range1.Ranges[i].High]);
  end;
  LblMultiStatus.Caption := Format(rsRangesFmt, [s]);
end;

{ A stop added, moved, removed or given another colour. }
procedure TMainForm.StopsChange(Sender: TObject);
begin
  LblMultiStatus.Caption := Format(rsStopsFmt, [Stops.ThumbCount]);
  StopsPreview.Invalidate;
end;

{ The very gradient the bar's track shows, Min at the left. }
procedure TMainForm.StopsPreviewPaint(Sender: TObject; APainter: TTyPainter;
  const AContent: TRect);
begin
  APainter.FillBackground(AContent, Stops.GradientFill(0), 0);
end;

{ The first and last stops say where the gradient starts and ends: they stay where they are.
  Refusing the move (rather than Thumbs[i].Enabled := False) keeps them selectable -- they can
  still be clicked, tabbed to and given another colour. }
procedure TMainForm.StopsThumbChanging(Sender: TObject; AIndex: Integer; var AValue: Integer;
  var AAllow: Boolean);
begin
  if (AIndex = 0) or (AIndex = Stops.ThumbCount - 1) then
    AAllow := False;
end;

{ Nor can they be dragged off or deleted with the Delete key. }
procedure TMainForm.StopsThumbRemoving(Sender: TObject; AIndex: Integer; var AAllow: Boolean);
begin
  if (AIndex = 0) or (AIndex = Stops.ThumbCount - 1) then
    AAllow := False;
end;

procedure TMainForm.Multi1Change(Sender: TObject);
begin
  if Multi1.ThumbCount < 3 then Exit;
  LblMultiStatus.Caption := Format(rsThresholdsFmt, [Multi1.ThumbValues[0],
    Multi1.ThumbValues[1], Multi1.ThumbValues[2]]);
end;

procedure TMainForm.MonthsChange(Sender: TObject);
begin
  LblMultiStatus.Caption := Format(rsMonthsFmt, [MonthName(Months.LowValue),
    MonthName(Months.HighValue)]);
end;

procedure TMainForm.MonthsFormatTickLabel(Sender: TObject; AValue: Integer; var AText: string);
begin
  AText := MonthName(AValue);
end;

end.
