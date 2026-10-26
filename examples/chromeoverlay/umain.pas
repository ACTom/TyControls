unit umain;

{ A container's chrome stays whole on top of its children (ITyChromeHost). The first page's
  cards have children placed ON their frames, across their corners and across the hairlines
  under their titles and over their actions rails -- the places where a child used to cut
  the line; the second page does the same to a panel, a group box (over its caption), a
  scroll box and an expandable panel, and the page control's own frame now shows over its
  pages. The switch (TyChromeOverlayEnabled) turns the overlay off for a before/after look,
  and Measure redraws the window both ways to show what keeping the frame on top costs;
  `--measure <file>` does the same once the window is up, writes the figures to the file and
  closes. Hover a card: its frame changes colour, and the part over the children follows.
  The window, the cards and every child are designed in umain.lfm; the code here is handlers
  and theme setup. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, ExtCtrls, LCLType, LCLIntf,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes, tyControls.Base,
  tyControls.Button, tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch,
  tyControls.Card, tyControls.Panel, tyControls.Edit, tyControls.ListBox, tyControls.Memo,
  tyControls.PageControl, tyControls.TabSheet, tyControls.GroupBox, tyControls.ScrollBox,
  tyControls.ExPanel;

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
    Pages: TTyPageControl;
    PageCards: TTyTabSheet;
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
    PageOthers: TTyTabSheet;
    PnlFlush: TTyPanel;
    PnlFill: TTyPanel;
    GrpCaption: TTyGroupBox;
    BtnOverCaption: TTyButton;
    BtnGroupEdge: TTyButton;
    Scr: TTyScrollBox;
    PnlScrollEdge: TTyPanel;
    BtnScrollFar: TTyButton;
    ExP: TTyExPanel;
    PnlExFill: TTyPanel;
    LblOthers: TTyLabel;
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
  rsRoundsFmt = 'Each time is the fastest of %d runs of %d redraws, the two ways taking turns.';
  rsWayOn = 'Frame on top';
  rsWayOff = 'Without';
  rsWayLineFmt = '%s: %.1f ms per redraw (runs from %.1f to %.1f)';
  rsCostFmt = 'Keeping the frame on top costs %.1f ms of a redraw.';
  rsSkippedFmt = '%d runs left out: the window was minimised or hidden while they ran.';
  rsNotShowing = 'Nothing measured: the window is not on screen.';

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

{ RUNS runs of ROUNDS redraws each way, the frame on top and not, the two taking turns so that
  whatever else the machine is doing falls on both alike; a way's time is its fastest run. A
  minimised window paints nothing and redraws in no time, so a run counts only if the window
  was up from its start to its end; one that was not is tried again a moment later, up to
  MAX_TRIES. }
procedure TMainForm.Measure;
const
  RUNS = 5;
  MAX_TRIES = 20;
  ROUNDS = 20;
var
  keepOn, ok: Boolean;
  done, tries, skipped, way, i: Integer;
  best, worst, ms: array[0..1] of Double;
  t0: QWord;

  function Showing: Boolean;
  begin
    Result := HandleAllocated and IsWindowVisible(Handle) and not IsIconic(Handle);
  end;

  function OneRun(AOn: Boolean): Double;
  var
    r: Integer;
    s: QWord;
  begin
    TyChromeOverlayEnabled := AOn;
    RedrawAll;   // not counted: the first redraw after a switch may build what the rest reuse
    s := GetTickCount64;
    for r := 1 to ROUNDS do
      RedrawAll;
    Result := (GetTickCount64 - s) / ROUNDS;
  end;

begin
  keepOn := TyChromeOverlayEnabled;
  FillChar(best, SizeOf(best), 0);
  FillChar(worst, SizeOf(worst), 0);
  done := 0;
  tries := 0;
  skipped := 0;
  BtnMeasure.Enabled := False;   // the waits below let messages through
  try
    while (done < RUNS) and (tries < MAX_TRIES) do
    begin
      Inc(tries);
      ok := Showing;
      for way := 0 to 1 do
        ms[way] := OneRun(way = 0);
      ok := ok and Showing;
      if ok then
      begin
        Inc(done);
        for way := 0 to 1 do
        begin
          if (done = 1) or (ms[way] < best[way]) then best[way] := ms[way];
          if (done = 1) or (ms[way] > worst[way]) then worst[way] := ms[way];
        end;
      end
      else
      begin
        Inc(skipped);
        t0 := GetTickCount64;   // a moment for the window to come back before trying again
        while GetTickCount64 - t0 < 2000 do
        begin
          Application.ProcessMessages;
          Sleep(50);
        end;
      end;
    end;
  finally
    TyChromeOverlayEnabled := keepOn;
    BtnMeasure.Enabled := True;
    RedrawAll;
  end;

  Results.Lines.BeginUpdate;
  try
    Results.Lines.Clear;
    if done = 0 then
    begin
      Results.Lines.Add(rsNotShowing);
      LblMeasure.Caption := rsNotShowing;
      Exit;
    end;
    Results.Lines.Add(Format(rsRoundsFmt, [done, ROUNDS]));
    if skipped > 0 then
      Results.Lines.Add(Format(rsSkippedFmt, [skipped]));
    Results.Lines.Add(Format(rsWayLineFmt, [rsWayOn, best[0], best[0], worst[0]]));
    Results.Lines.Add(Format(rsWayLineFmt, [rsWayOff, best[1], best[1], worst[1]]));
    Results.Lines.Add(Format(rsCostFmt, [best[0] - best[1]]));
  finally
    Results.Lines.EndUpdate;
  end;
  LblMeasure.Caption := Format(rsMeasureFmt, [best[0], best[1]]);
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
