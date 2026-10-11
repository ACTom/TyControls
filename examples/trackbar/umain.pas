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

  Right, several thumbs (TTyRangeTrackBar / TTyMultiTrackBar), each extra built from the bars'
  events and public geometry, none of it inside the controls:
  - Two ranges, MinGap = 5, tick labels; a click on the bare track adds a range there
    (OnTrackClick)
  - Gradient stops: each thumb's Color is a stop, the stretches between them painted as
    gradients (OnDrawSegment), a click on the track adds a stop in the colour mixed from its
    neighbours, and a TTyPaintPanel below shows the whole gradient
  - Three thresholds, the stretches between them coloured by segment class
  - A range of months: the tick labels 1..12 become month names (OnFormatTickLabel)

  The main form (a TTyForm + TTyTitleBar), the column headings, every track bar and the live theme
  switcher are designed in umain.lfm; the code here is event handlers + theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Graphics, Forms, Controls,
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
    LblStops: TTyLabel;
    Stops: TTyMultiTrackBar;
    StopsPreview: TTyPaintPanel;
    LblStopsHint: TTyLabel;
    LblMulti: TTyLabel;
    Multi1: TTyMultiTrackBar;
    LblMultiHint: TTyLabel;
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
    procedure Range1TrackClick(Sender: TObject; AValue: Integer; var AHandled: Boolean);
    procedure StopsChange(Sender: TObject);
    procedure StopsTrackClick(Sender: TObject; AValue: Integer; var AHandled: Boolean);
    procedure StopsDrawSegment(Sender: TObject; APainter: TTyPainter; AIndex: Integer;
      const ARect: TRect; var ADefaultDraw: Boolean);
    procedure StopsPreviewPaint(Sender: TObject; APainter: TTyPainter; const AContent: TRect);
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

function ToTyColor(AColor: TColor): TTyColor;
var
  c: TColor;
begin
  c := ColorToRGB(AColor);
  Result := TyRGB(Red(c), Green(c), Blue(c));
end;

function MixColor(A, B: TColor; T: Double): TColor;
begin
  A := ColorToRGB(A);
  B := ColorToRGB(B);
  Result := RGBToColor(Round(Red(A) + (Red(B) - Red(A)) * T),
    Round(Green(A) + (Green(B) - Green(A)) * T), Round(Blue(A) + (Blue(B) - Blue(A)) * T));
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

{ The thumbs run Low0, High0, Low1, High1, ..., and each item reads what its thumbs show. }
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

{ A click between two ranges adds a range 10 wide there, kept MinGap clear of its neighbours;
  a click inside a range is left to the bar (the nearest end comes to the pointer). }
procedure TMainForm.Range1TrackClick(Sender: TObject; AValue: Integer; var AHandled: Boolean);
var
  i, lo, hi, gap: Integer;
  r: TTyTrackRange;
begin
  gap := Range1.MinGap;
  lo := Range1.Min;
  hi := Range1.Max;
  // The ranges are always in order: the free stretch is between the High of the range on the
  // left and the Low of the range on the right, MinGap in from each.
  for i := 0 to Range1.Ranges.Count - 1 do
  begin
    r := Range1.Ranges[i];
    if (AValue >= r.Low) and (AValue <= r.High) then Exit;
    if r.High < AValue then lo := Math.Max(lo, r.High + gap)
    else hi := Math.Min(hi, r.Low - gap);
  end;
  AHandled := True;                       // added or not, no end jumps here
  lo := Math.Max(lo, AValue - 5);
  hi := Math.Min(hi, AValue + 5);
  if (hi <= lo) or (hi - lo < gap) then Exit;     // no room
  // Held until EndUpdate: a range added at the end would otherwise be stopped by its
  // neighbour while its ends are set one at a time.
  Range1.Ranges.BeginUpdate;
  try
    r := Range1.Ranges.Add;
    r.Low := lo;
    r.High := hi;
  finally
    Range1.Ranges.EndUpdate;
  end;
end;

procedure TMainForm.StopsChange(Sender: TObject);
begin
  LblMultiStatus.Caption := Format(rsStopsFmt, [Stops.ThumbCount]);
  StopsPreview.Invalidate;
end;

{ A click on the bare track adds a stop there, its colour mixed from the stops either side by
  where it falls between them. }
procedure TMainForm.StopsTrackClick(Sender: TObject; AValue: Integer; var AHandled: Boolean);
var
  i: Integer;
  c: TColor;
  t: TTyTrackThumbItem;
begin
  i := 0;
  while (i < Stops.ThumbCount) and (Stops.ThumbValues[i] < AValue) do Inc(i);
  if Stops.ThumbCount = 0 then c := clGray
  else if i = 0 then c := Stops.Thumbs[0].Color
  else if i = Stops.ThumbCount then c := Stops.Thumbs[i - 1].Color
  else c := MixColor(Stops.Thumbs[i - 1].Color, Stops.Thumbs[i].Color,
    (AValue - Stops.ThumbValues[i - 1]) / (Stops.ThumbValues[i] - Stops.ThumbValues[i - 1]));
  Stops.Thumbs.BeginUpdate;
  try
    t := Stops.Thumbs.Add;
    t.Value := AValue;
    t.Color := c;
  finally
    Stops.Thumbs.EndUpdate;
  end;
  Stops.SelectedThumb := t.Index;   // EndUpdate put the items in order: item index = thumb index
  AHandled := True;
end;

{ Segment I runs from thumb I - 1 to thumb I: painted from the one's colour to the other's.
  The two end segments (before the first stop, after the last) keep the bare groove. }
procedure TMainForm.StopsDrawSegment(Sender: TObject; APainter: TTyPainter; AIndex: Integer;
  const ARect: TRect; var ADefaultDraw: Boolean);
var
  f: TTyFill;
begin
  if (AIndex = 0) or (AIndex >= Stops.ThumbCount) then Exit;
  f := Default(TTyFill);
  f.Kind := tfkLinearGradient;
  f.GradFrom := ToTyColor(Stops.Thumbs[AIndex - 1].Color);
  f.GradTo := ToTyColor(Stops.Thumbs[AIndex].Color);
  f.GradAngleDeg := 0;              // left to right, Min to Max
  APainter.FillBackground(ARect, f, 0);
  ADefaultDraw := False;
end;

{ The whole gradient the stops make, each stop at its value's place across the panel. }
procedure TMainForm.StopsPreviewPaint(Sender: TObject; APainter: TTyPainter;
  const AContent: TRect);
var
  f: TTyFill;
  i, n, span: Integer;
begin
  n := Stops.ThumbCount;
  if n = 0 then Exit;
  f := Default(TTyFill);
  if n = 1 then
  begin
    f.Kind := tfkSolid;
    f.Color := ToTyColor(Stops.Thumbs[0].Color);
  end
  else
  begin
    span := Math.Max(1, Stops.Max - Stops.Min);
    f.Kind := tfkLinearGradient;
    SetLength(f.GradStops, n);
    for i := 0 to n - 1 do
    begin
      f.GradStops[i].Color := ToTyColor(Stops.Thumbs[i].Color);
      f.GradStops[i].Pos := (Stops.ThumbValues[i] - Stops.Min) / span;
    end;
    f.GradFrom := f.GradStops[0].Color;
    f.GradTo := f.GradStops[n - 1].Color;
    f.GradAngleDeg := 0;
  end;
  APainter.FillBackground(AContent, f, 0);
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
