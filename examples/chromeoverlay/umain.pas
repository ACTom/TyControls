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
  rsRoundsFmt = 'Times per redraw are the fastest of %d runs of %d redraws, the four ways '
    + 'taking turns; the parts are averages over all runs.';
  rsModeOff = 'Off';
  rsMode0 = 'Each band draws the frame afresh';
  rsMode1 = 'The same, but bands on a straight edge skip the corners';
  rsMode2 = 'Each card keeps a frame layer, and bands copy from it';
  rsOffLineFmt = '%s: %.1f ms per redraw (runs from %.1f to %.1f)';
  rsModeLineFmt = '%s: %.1f ms per redraw (runs from %.1f to %.1f), %.1f ms more than off; '
    + '%d passes, %d bands';
  rsDrawPartsFmt = '    in the overlay %.2f ms: set-up %.2f, drawing %.2f (corners %.2f, '
    + 'frame %.2f, separators %.2f), the band onto the window %.2f, the signature %.2f, '
    + 'the free area %.2f, the rest %.2f';
  rsCachePartsFmt = '    in the overlay %.2f ms: set-up %.2f, the kept layer %.2f (its key '
    + '%.2f), copying from it %.2f, the band onto the window %.2f, the signature %.2f, '
    + 'the free area %.2f, the rest %.2f';
  rsCacheBuiltFmt = '    frame layers: %d built on the first redraw, %.2f ms each; %.1f KB kept';
  rsCacheNoneFmt = '    frame layers: none built; %.1f KB kept';

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

{ RUNS runs of ROUNDS redraws in each of the four ways (off, then TyChromeMode 0, 1, 2), the
  ways taking turns so that whatever else the machine is doing falls on all of them alike; a
  way's time is its fastest run. Each run starts with one redraw that is not counted; the
  first of them in mode 2 rebuilds every frame layer, which is what a build costs. "The rest"
  is the part of the overlay none of the named parts covers: walking up the parents, working
  out the bands, the painters coming and going. }
procedure TMainForm.Measure;
const
  RUNS = 5;
  ROUNDS = 20;
var
  keepOn: Boolean;
  keepMode, r, m, i: Integer;
  best, worst: array[-1..2] of Double;
  sums: array[-1..2] of TTyChromeStats;
  ms, rest: Double;
  t0, held, builds, buildUs: Int64;
  st: TTyChromeStats;
  what: string;

  function PerRedraw(AUs: Int64): Double;
  begin
    Result := AUs / 1000 / (RUNS * ROUNDS);
  end;

begin
  keepOn := TyChromeOverlayEnabled;
  keepMode := TyChromeMode;
  FillChar(sums, SizeOf(sums), 0);
  builds := 0;
  buildUs := 0;
  for m := -1 to 2 do
  begin
    best[m] := 0;
    worst[m] := 0;
  end;
  try
    for r := 1 to RUNS do
      for m := -1 to 2 do
      begin
        TyChromeOverlayEnabled := m >= 0;
        if m >= 0 then TyChromeMode := m;
        if (r = 1) and (m = 2) then
        begin
          Inc(TyChromeCacheEpoch);   // every kept layer is stale: the next redraw builds them
          t0 := TyChromeStats.CacheBuilds;
          held := TyChromeStats.CacheBuildUs;
          RedrawAll;
          builds := TyChromeStats.CacheBuilds - t0;
          buildUs := TyChromeStats.CacheBuildUs - held;
        end
        else
          RedrawAll;
        { this way's sums go on from where its last run left them; CacheBytes is what is kept
          now, not a sum, so it is carried over as it stands }
        held := TyChromeStats.CacheBytes;
        TyChromeStats := sums[m];
        TyChromeStats.CacheBytes := held;
        t0 := TyChromeClockUs;
        for i := 1 to ROUNDS do
          RedrawAll;
        ms := (TyChromeClockUs - t0) / 1000 / ROUNDS;
        sums[m] := TyChromeStats;
        if (r = 1) or (ms < best[m]) then best[m] := ms;
        if (r = 1) or (ms > worst[m]) then worst[m] := ms;
      end;
  finally
    TyChromeOverlayEnabled := keepOn;
    TyChromeMode := keepMode;
    RedrawAll;
  end;

  Results.Lines.BeginUpdate;
  try
    Results.Lines.Clear;
    Results.Lines.Add(Format(rsRoundsFmt, [RUNS, ROUNDS]));
    Results.Lines.Add(Format(rsOffLineFmt, [rsModeOff, best[-1], best[-1], worst[-1]]));
    for m := 0 to 2 do
    begin
      st := sums[m];
      case m of
        0: what := rsMode0;
        1: what := rsMode1;
      else
        what := rsMode2;
      end;
      Results.Lines.Add(Format(rsModeLineFmt, [what, best[m], best[m], worst[m],
        best[m] - best[-1], st.Passes div (RUNS * ROUNDS), st.Bands div (RUNS * ROUNDS)]));
      rest := PerRedraw(st.HookUs - st.SetupUs - st.LayerUs - st.FetchUs - st.CopyUs
        - st.BlitUs - st.SignatureUs - st.FreeRectUs);
      if m < 2 then
        Results.Lines.Add(Format(rsDrawPartsFmt, [PerRedraw(st.HookUs), PerRedraw(st.SetupUs),
          PerRedraw(st.LayerUs), PerRedraw(st.CornerUs), PerRedraw(st.FrameUs),
          PerRedraw(st.SeparatorUs), PerRedraw(st.BlitUs), PerRedraw(st.SignatureUs),
          PerRedraw(st.FreeRectUs), rest]))
      else
      begin
        Results.Lines.Add(Format(rsCachePartsFmt, [PerRedraw(st.HookUs), PerRedraw(st.SetupUs),
          PerRedraw(st.FetchUs), PerRedraw(st.KeyUs), PerRedraw(st.CopyUs),
          PerRedraw(st.BlitUs), PerRedraw(st.SignatureUs), PerRedraw(st.FreeRectUs), rest]));
        if builds > 0 then
          Results.Lines.Add(Format(rsCacheBuiltFmt, [Integer(builds), buildUs / 1000 / builds,
            TyChromeStats.CacheBytes / 1024]))
        else
          Results.Lines.Add(Format(rsCacheNoneFmt, [TyChromeStats.CacheBytes / 1024]));
      end;
    end;
  finally
    Results.Lines.EndUpdate;
  end;
  LblMeasure.Caption := Format(rsMeasureFmt, [best[2], best[-1]]);
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
