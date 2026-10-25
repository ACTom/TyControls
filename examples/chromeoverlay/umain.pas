unit umain;

{ Pilot: a container's chrome stays whole on top of its children (ITyChromeHost, TTyCard for
  now). Each card here has children placed ON its frame, across its corners and across the
  hairlines under its title and over its actions rail -- the places where a child used to cut
  the line. The switch turns the overlay off for a before/after look. Measure redraws the
  whole window with the overlay off and in each of the pilot's three ways of drawing it, and
  lists where the time goes (TyChromeStats); `--measure <file>` does the same once the window
  is up, writes the list to the file and closes. Hover a card: its frame changes colour, and
  the part over the children follows. The window, the cards and every child are designed in
  umain.lfm; the code here is handlers and theme setup. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, ExtCtrls, LCLType, LCLIntf,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes, tyControls.Base,
  tyControls.Button, tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch,
  tyControls.Card, tyControls.Panel, tyControls.Edit, tyControls.ListBox, tyControls.Memo;

type

  { TMainForm }

  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;
    Surface: TTyFormSurface;
    OverlaySwitch: TTyToggleSwitch;
    BtnMeasure: TTyButton;
    LblMeasure: TTyLabel;
    CardEdges: TTyCard;
    BtnLeftEdge: TTyButton;
    PnlHeaderLine: TTyPanel;
    LblRightEdge: TTyLabel;
    EdtCorner: TTyEdit;
    BtnOptedOut: TTyButton;
    CardNested: TTyCard;
    PnlInner: TTyPanel;
    BtnInnerEdge: TTyButton;
    LstCorner: TTyListBox;
    CardActions: TTyCard;
    BtnAcrossActions: TTyButton;
    BtnActionsCorner: TTyButton;
    LblHint: TTyLabel;
    Results: TTyMemo;
    MeasureTimer: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure OverlaySwitchChange(Sender: TObject);
    procedure BtnMeasureClick(Sender: TObject);
    procedure MeasureTimerTimer(Sender: TObject);
  private
    FMeasureFile: string;
    procedure RedrawAll;
    procedure Measure;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  rsMeasureFmt = 'One redraw of this window: %.1f ms with the frame on top, %.1f ms without';
  rsItem = 'Item %d';
  rsRoundsFmt = 'Each figure is an average over %d redraws of the whole window.';
  rsModeOff = 'Off';
  rsMode0 = 'Each band draws the frame afresh';
  rsMode1 = 'The same, but bands on a straight edge skip the corners';
  rsMode2 = 'Each card keeps a frame layer, and bands copy from it';
  rsOffLineFmt = '%s: %.1f ms per redraw';
  rsModeLineFmt = '%s: %.1f ms per redraw, %.1f ms more than off; %d passes, %d bands';
  rsDrawPartsFmt = '    set-up %.2f, drawing %.2f (corners %.2f, frame %.2f, separators %.2f), '
    + 'the band onto the window %.2f, the rest %.2f ms';
  rsCachePartsFmt = '    set-up %.2f, finding the frame layer %.2f, copying from it %.2f, '
    + 'the band onto the window %.2f, the rest %.2f ms';
  rsCacheBuiltFmt = '    frame layers: %d built on the first redraw, %.2f ms each; %.1f KB kept';
  rsCacheReusedFmt = '    frame layers: none built, the ones kept before still fit; %.1f KB kept';

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
  for i := 1 to 6 do
    LstCorner.Items.Add(Format(rsItem, [i]));
  OverlaySwitch.Checked := TyChromeOverlayEnabled;
  for i := 1 to ParamCount - 1 do
    if ParamStr(i) = '--measure' then
      FMeasureFile := ParamStr(i + 1);
  MeasureTimer.Enabled := FMeasureFile <> '';
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

{ Every window, children included, painted again now: the overlay is drawn by each child
  over itself, so turning it on or off has to reach all of them. }
procedure TMainForm.RedrawAll;
begin
  if not HandleAllocated then Exit;   // FormCreate sets the switch before there is a window
  RedrawWindow(Handle, nil, 0, RDW_INVALIDATE or RDW_ERASE or RDW_ALLCHILDREN or RDW_UPDATENOW);
end;

procedure TMainForm.OverlaySwitchChange(Sender: TObject);
begin
  TyChromeOverlayEnabled := OverlaySwitch.Checked;
  RedrawAll;
end;

{ The window redrawn ROUNDS times with the overlay off, then in each TyChromeMode, after one
  redraw to warm up (with frame layers kept, that one builds them). "The rest" is what the
  overlay adds that none of the timed parts covers: walking up the parents, working out the
  bands, checking each card's signature. }
procedure TMainForm.Measure;
const
  ROUNDS = 40;
var
  keepOn: Boolean;
  keepMode, m, i: Integer;
  offMs, ms, rest: Double;
  t0, builds, buildUs: Int64;
  st: TTyChromeStats;
  what: string;

  procedure ResetStats;
  var
    held: Int64;
  begin
    held := TyChromeStats.CacheBytes;   // what is kept now, not a sum: it stays
    FillChar(TyChromeStats, SizeOf(TyChromeStats), 0);
    TyChromeStats.CacheBytes := held;
  end;

  function PerRedraw(AUs: Int64): Double;
  begin
    Result := AUs / 1000 / ROUNDS;
  end;

begin
  keepOn := TyChromeOverlayEnabled;
  keepMode := TyChromeMode;
  offMs := 0;
  ms := 0;
  Results.Lines.BeginUpdate;
  try
    Results.Lines.Clear;
    Results.Lines.Add(Format(rsRoundsFmt, [ROUNDS]));
    for m := -1 to 2 do
    begin
      TyChromeOverlayEnabled := m >= 0;
      if m >= 0 then TyChromeMode := m;
      ResetStats;
      RedrawAll;
      builds := TyChromeStats.CacheBuilds;
      buildUs := TyChromeStats.CacheBuildUs;
      ResetStats;
      t0 := TyChromeClockUs;
      for i := 1 to ROUNDS do
        RedrawAll;
      ms := PerRedraw(TyChromeClockUs - t0);
      st := TyChromeStats;
      case m of
        -1: what := rsModeOff;
        0: what := rsMode0;
        1: what := rsMode1;
      else
        what := rsMode2;
      end;
      if m < 0 then
      begin
        offMs := ms;
        Results.Lines.Add(Format(rsOffLineFmt, [what, ms]));
        Continue;
      end;
      Results.Lines.Add(Format(rsModeLineFmt, [what, ms, ms - offMs,
        st.Passes div ROUNDS, st.Bands div ROUNDS]));
      rest := (ms - offMs) - PerRedraw(st.SetupUs + st.LayerUs + st.FetchUs + st.CopyUs
        + st.BlitUs);
      if m < 2 then
        Results.Lines.Add(Format(rsDrawPartsFmt, [PerRedraw(st.SetupUs), PerRedraw(st.LayerUs),
          PerRedraw(st.CornerUs), PerRedraw(st.FrameUs), PerRedraw(st.SeparatorUs),
          PerRedraw(st.BlitUs), rest]))
      else
      begin
        Results.Lines.Add(Format(rsCachePartsFmt, [PerRedraw(st.SetupUs), PerRedraw(st.FetchUs),
          PerRedraw(st.CopyUs), PerRedraw(st.BlitUs), rest]));
        if builds > 0 then
          Results.Lines.Add(Format(rsCacheBuiltFmt, [Integer(builds),
            buildUs / 1000 / builds, st.CacheBytes / 1024]))
        else
          Results.Lines.Add(Format(rsCacheReusedFmt, [st.CacheBytes / 1024]));
      end;
    end;
  finally
    Results.Lines.EndUpdate;
    TyChromeOverlayEnabled := keepOn;
    TyChromeMode := keepMode;
    RedrawAll;
  end;
  LblMeasure.Caption := Format(rsMeasureFmt, [ms, offMs]);
end;

procedure TMainForm.BtnMeasureClick(Sender: TObject);
begin
  Measure;
end;

{ --measure <file>: once the window is up, measure, write the list to the file and close, so a
  script gets the figures without anyone clicking. An error goes into the file too, never into
  a dialog nobody is there to close. }
procedure TMainForm.MeasureTimerTimer(Sender: TObject);
begin
  MeasureTimer.Enabled := False;
  try
    Measure;
  except
    on E: Exception do
      Results.Lines.Add(E.ClassName + ': ' + E.Message);
  end;
  try
    Results.Lines.SaveToFile(FMeasureFile);
  except
    // nowhere to say it; the missing file says it
  end;
  Close;
end;

end.
