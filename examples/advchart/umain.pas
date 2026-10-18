unit umain;

{ TTyAdvanceChart demo -- the Apache ECharts example gallery, unmodified.

  The option tree IS the API, so the strongest demonstration is not a chart this
  repository wrote: it is 244 option trees written for ECharts, fed in as they
  stand and drawn by this control. Tabs are the gallery's own categories; the
  list is the examples in one; the text on the right is the option itself, and
  it is editable, because "paste an option from the web and it draws" is the
  claim being made.

  IT IS ALSO A SCOREBOARD, and deliberately an honest one. Whatever the chart
  has to say about an option -- a key it does not know, a value outside its
  list, a series it cannot place -- is shown underneath. The saying is not
  written here: it comes from TyOptDiagnose, the same diagnostics the option
  editor shows, so the demo cannot flatter the library by wording things more
  kindly than the library does.

  WHY TyOptDiagnose AND NOT Chart.DiagnosticCount. The control's own
  diagnostics come from its build, and the build is only made during a PAINT --
  so reading them straight after assigning Option gives the PREVIOUS chart's
  answer. TyOptDiagnose parses the text itself and is independent of when the
  control last drew.

  The theme switcher earns its place twice over for a chart: the axis domain
  resolves eight theme keys, so switching a skin is what proves the chart is
  drawn IN the theme rather than pasted on top of one.

  A SEQUENCE IS PLAYED AS THE PAGE PLAYS IT. The universal-transition examples
  switch between options on a timer (map to bar, treemap to sunburst); the
  harvester recorded those setOption calls, and here they are replayed -- each
  with the options the page passed (notMerge or a plain merge) at the page's
  interval, and by hand with Next step. That is the manual check for
  universalTransition: the morph between two options can only be seen with
  both of them, in order, on one chart. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, ExtCtrls, fpjson, jsonparser,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.Button, tyControls.ComboBox, tyControls.ToggleSwitch,
  tyControls.TyLabel, tyControls.Memo, tyControls.ListBox,
  tyControls.TabSet, tyControls.AdvanceChart, tyControls.AdvChart.Diagnose,
  umaps;

type
  { One row of gallery/index.json. `Ok` false means the harvester could not
    reduce that example to static JSON, and `Reason` says why -- kept in the
    list rather than dropped, because a gallery that quietly showed 244 of 273
    would look complete and be misleading. }
  TGalleryEntry = record
    Id: string;
    Title: string;
    Category: string;
    Reason: string;
    Ok: Boolean;
    { The page's own setOption sequence, empty for a single option: each
      step's file and the options it was set with, as JSON text ('' for a
      plain merge); the step the loop goes back to (-1: it stops at the end);
      the page's interval in ms (0: by hand only). }
    StepFiles, StepOpts: array of string;
    LoopTo, Interval: Integer;
  end;

  TMainForm = class(TTyForm)
    Surface: TTyFormSurface;
    TitleBar1: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;
    CatTabs: TTyTabSet;
    ExampleList: TTyListBox;
    OptionMemo: TTyMemo;
    Chart: TTyAdvanceChart;
    BtnApply: TTyButton;
    BtnShot: TTyButton;
    BtnNext: TTyButton;
    LblStatus: TTyLabel;
    SeqTimer: TTimer;

    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure CatTabsChange(Sender: TObject);
    procedure ExampleListChange(Sender: TObject);
    procedure BtnApplyClick(Sender: TObject);
    procedure BtnShotClick(Sender: TObject);
    procedure BtnNextClick(Sender: TObject);
    procedure SeqTimerTimer(Sender: TObject);
  private
    FEntries: array of TGalleryEntry;
    FCategories: TStringList;
    FGalleryDir: string;
    { maps/ beside gallery/: the GeoJSON the geo examples register }
    FMapsDir: string;
    { The gallery slot the memo and chart now hold, -1 for none. Picking a row
      in code fires the list's change event as well, so without it one click on
      a tab loaded the same option two or three times. }
    FShownSlot: Integer;
    { the step of the shown entry's sequence the chart now holds }
    FStep: Integer;
    procedure LoadIndex;
    procedure FillCategories;
    procedure FillList;
    procedure ShowSelected;
    { Select an example by its gallery id, wherever it lives. Answers False when
      there is no such id or it was never converted. }
    function SelectById(const AId: string): Boolean;
    procedure Apply;
    { What the library says about AText, under the status line. }
    procedure ShowNotes(const AText: string);
    { Start (or stop, for a single option) the shown entry's sequence. }
    procedure StartSequence;
    procedure NextStep;
  public
    destructor Destroy; override;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  rsNoGallery = 'The gallery was not found. Run tools/advchart-gallery/harvest.js '
    + 'to build examples/advchart/gallery.';
  rsOptionOk = 'The option parsed and this chart draws.';
  rsDiagnostics = '%d note(s) on this option:';
  rsNotConverted = 'Not converted: %s';
  rsPickOne = 'Pick an example on the left.';
  rsSavedTo = 'Saved to %s';
  rsCounts = '%s — %d example(s)';
  { above the notes while a setOption sequence plays: step, of how many }
  rsStep = 'Step %d of %d of the page''s setOption sequence.';
  { said under the notes when an example needs a border map the demo does not
    ship: %s the map name(s), %s the maps folder }
  rsBorderMapNotShipped = 'This example needs the map %s, which the demo does '
    + 'not include. Borders between countries are disputed, and some places '
    + 'require published maps to be reviewed, so neither TyControls nor this demo '
    + 'ships a map that draws them. To see the example, save a GeoJSON file under '
    + 'the map''s name in %s (for instance china.json), or register one in code '
    + 'with TyChartRegisterMap. Natural Earth (naturalearthdata.com) offers '
    + 'public-domain country data.';

{ The gallery sits beside the .lpi, and the binary sits in
  lib/<cpu>-<os>/ under it -- so the same upward walk the .lpr uses to find
  languages/ finds it. Written out rather than assumed, because an example that
  only runs from one working directory is an example that does not run. }
function FindGalleryDir: string;
var
  dir: string;
  i: Integer;
begin
  dir := ExtractFilePath(ParamStr(0));
  for i := 0 to 8 do
  begin
    if FileExists(dir + 'gallery' + PathDelim + 'index.json') then
      Exit(dir + 'gallery' + PathDelim);
    dir := ExtractFilePath(ExcludeTrailingPathDelimiter(dir));
    if dir = '' then Break;
  end;
  Result := '';
end;

{ Read a UTF-8 file into a string, the way everything else in this repository
  does it. No TFileStream, no encoding parameter: fpjson takes the bytes. }
function ReadTextFile(const AName: string): string;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(AName);
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

{ The gallery's own category strings, normalised. Several examples carry a
  combined label -- 'bar, rich', 'calendar, heatmap' -- and taking the part
  before the comma gives back the 25 categories the gallery actually has
  instead of 53 mostly-singleton ones. }
function PrimaryCategory(const AText: string): string;
var p: Integer;
begin
  Result := Trim(AText);
  if (Result <> '') and (Result[1] in ['''', '"']) then
    Delete(Result, 1, 1);
  p := Pos(',', Result);
  if p > 0 then Result := Copy(Result, 1, p - 1);
  Result := Trim(Result);
  if (Result <> '') and (Result[Length(Result)] in ['''', '"']) then
    Delete(Result, Length(Result), 1);
end;

destructor TMainForm.Destroy;
begin
  FCategories.Free;
  inherited Destroy;
end;

procedure TMainForm.LoadIndex;
var
  root: TJSONData;
  arr, steps: TJSONArray;
  obj, seq: TJSONObject;
  i, k, n: Integer;
begin
  SetLength(FEntries, 0);
  if FGalleryDir = '' then Exit;
  root := GetJSON(ReadTextFile(FGalleryDir + 'index.json'));
  try
    if not (root is TJSONObject) then Exit;
    if not (TJSONObject(root).Find('entries') is TJSONArray) then Exit;
    arr := TJSONArray(TJSONObject(root).Find('entries'));
    SetLength(FEntries, arr.Count);
    n := 0;
    for i := 0 to arr.Count - 1 do
    begin
      if not (arr.Items[i] is TJSONObject) then Continue;
      obj := TJSONObject(arr.Items[i]);
      FEntries[n].Id := obj.Get('id', '');
      FEntries[n].Title := obj.Get('title', FEntries[n].Id);
      FEntries[n].Category := PrimaryCategory(obj.Get('category', ''));
      FEntries[n].Ok := obj.Get('ok', False);
      FEntries[n].Reason := obj.Get('reason', '');
      FEntries[n].LoopTo := -1;
      if obj.Find('sequence') is TJSONObject then
      begin
        seq := TJSONObject(obj.Find('sequence'));
        if seq.Find('steps') is TJSONArray then
        begin
          steps := TJSONArray(seq.Find('steps'));
          SetLength(FEntries[n].StepFiles, steps.Count);
          SetLength(FEntries[n].StepOpts, steps.Count);
          for k := 0 to steps.Count - 1 do
            if steps.Items[k] is TJSONObject then
            begin
              FEntries[n].StepFiles[k] := TJSONObject(steps.Items[k]).Get('file', '');
              if TJSONObject(steps.Items[k]).Find('opts') is TJSONObject then
                FEntries[n].StepOpts[k] := TJSONObject(steps.Items[k]).Find('opts').AsJSON;
            end;
          FEntries[n].LoopTo := seq.Get('loopTo', -1);
          FEntries[n].Interval := seq.Get('interval', 0);
        end;
      end;
      Inc(n);
    end;
    SetLength(FEntries, n);
  finally
    root.Free;
  end;
end;

procedure TMainForm.FillCategories;
var i: Integer;
begin
  FCategories.Clear;
  FCategories.Sorted := True;
  FCategories.Duplicates := dupIgnore;
  for i := 0 to High(FEntries) do
    if FEntries[i].Category <> '' then
      FCategories.Add(FEntries[i].Category);
  CatTabs.Tabs.Assign(FCategories);
  if FCategories.Count > 0 then CatTabs.TabIndex := 0;
end;

procedure TMainForm.FillList;
var
  i: Integer;
  cat, cap: string;
begin
  ExampleList.Items.BeginUpdate;
  try
    ExampleList.Items.Clear;
    if (CatTabs.TabIndex < 0) or (CatTabs.TabIndex >= FCategories.Count) then Exit;
    cat := FCategories[CatTabs.TabIndex];
    for i := 0 to High(FEntries) do
      if FEntries[i].Category = cat then
      begin
        cap := FEntries[i].Title;
        { An example the harvester could not reduce is still listed, marked. }
        if not FEntries[i].Ok then cap := '× ' + cap;
        ExampleList.Items.AddObject(cap, TObject(PtrInt(i)));
      end;
  finally
    ExampleList.Items.EndUpdate;
  end;
  LblStatus.Caption := Format(rsCounts, [cat, ExampleList.Items.Count]);
  if ExampleList.Items.Count > 0 then
    ExampleList.ItemIndex := 0;
  ShowSelected;
end;

procedure TMainForm.ShowSelected;
var
  slot: Integer;
  fn: string;
begin
  if (ExampleList.ItemIndex < 0)
    or (ExampleList.ItemIndex >= ExampleList.Items.Count) then
  begin
    LblStatus.Caption := rsPickOne;
    Exit;
  end;
  slot := PtrInt(ExampleList.Items.Objects[ExampleList.ItemIndex]);
  if (slot < 0) or (slot > High(FEntries)) then Exit;
  if slot = FShownSlot then Exit;
  FShownSlot := slot;
  StartSequence;

  if not FEntries[slot].Ok then
  begin
    OptionMemo.Text := '';
    Chart.Option := '';
    LblStatus.Caption := Format(rsNotConverted, [FEntries[slot].Reason]);
    Exit;
  end;

  fn := FGalleryDir + FEntries[slot].Id + '.json';
  if not FileExists(fn) then
  begin
    LblStatus.Caption := Format(rsNotConverted, [fn]);
    Exit;
  end;
  OptionMemo.Text := ReadTextFile(fn);
  Apply;
end;

function TMainForm.SelectById(const AId: string): Boolean;
var
  i, k: Integer;
begin
  Result := False;
  for i := 0 to High(FEntries) do
    if (FEntries[i].Id = AId) and FEntries[i].Ok then
    begin
      k := FCategories.IndexOf(FEntries[i].Category);
      if k >= 0 then
      begin
        CatTabs.TabIndex := k;
        FillList;
      end;
      for k := 0 to ExampleList.Items.Count - 1 do
        if PtrInt(ExampleList.Items.Objects[k]) = i then
        begin
          ExampleList.ItemIndex := k;
          ShowSelected;
          Exit(True);
        end;
    end;
end;

procedure TMainForm.Apply;
begin
  { THE PAGE'S OWN registerMap. An ECharts example fetches its GeoJSON before
    it sets the option; the harvest kept only the map's name. }
  RegisterGalleryMapsFor(OptionMemo.Text, FMapsDir);
  Chart.Option := OptionMemo.Text;
  if Chart.OptionError <> '' then
  begin
    LblStatus.Caption := Chart.OptionError;
    Exit;
  end;
  ShowNotes(OptionMemo.Text);
end;

procedure TMainForm.ShowNotes(const AText: string);
var
  diags: TTyOptDiagArray;
  i, notes: Integer;
  s, border: string;
begin
  { THE LIBRARY'S OWN WORDS. Asking TyOptDiagnose rather than the control keeps
    two things honest at once: the answer is current (the control's build is
    only made during a paint), and the demo cannot describe a gap more kindly
    than the option editor does. }
  diags := TyOptDiagnose(AText);
  { ONLY REAL NOTES ARE COUNTED. The all-clear row says the option is
    understood; counting it under the header announced one thing the chart
    "could not honour" above a single line saying nothing was wrong. When it is the only kind of row there
    is, it is shown on its own, without a header. The header itself says
    "note", not "failure": an option the catalog does not know is often one the
    chart simply has no use for.

    A LONG LIST IS CUT, and its last row says how many were left out. That row
    is not a note of its own; what it hides is counted instead, so the header
    gives the real total rather than the hundred rows that fit. }
  notes := 0;
  s := '';
  for i := 0 to High(diags) do
    case diags[i].Kind of
      odkAllClear: ;
      odkTruncated: Inc(notes, diags[i].Hidden);
    else
      Inc(notes);
    end;
  if Length(diags) = 0 then
    s := rsOptionOk
  else if notes = 0 then
  begin
    for i := 0 to High(diags) do
    begin
      if s <> '' then s := s + LineEnding;
      s := s + diags[i].Text;
    end;
  end
  else
  begin
    s := Format(rsDiagnostics, [notes]);
    for i := 0 to High(diags) do
      if diags[i].Kind <> odkAllClear then
        s := s + LineEnding + '• ' + diags[i].Text;
  end;
  { A MAP THE DEMO DOES NOT SHIP. The library only says the map is not
    registered; the demo, which chose not to ship it, says why and what to do. }
  border := BorderMapsMissing(AText, FMapsDir);
  if border <> '' then
    s := s + LineEnding + LineEnding + Format(rsBorderMapNotShipped, [border, FMapsDir]);
  if (FShownSlot >= 0) and (FShownSlot <= High(FEntries))
    and (Length(FEntries[FShownSlot].StepFiles) > 1) then
    s := Format(rsStep, [FStep + 1, Length(FEntries[FShownSlot].StepFiles)])
      + LineEnding + s;
  LblStatus.Caption := s;
end;

procedure TMainForm.StartSequence;
var playing: Boolean;
begin
  SeqTimer.Enabled := False;
  FStep := 0;
  playing := (FShownSlot >= 0) and (FShownSlot <= High(FEntries))
    and FEntries[FShownSlot].Ok
    and (Length(FEntries[FShownSlot].StepFiles) > 1);
  BtnNext.Visible := playing;
  if playing and (FEntries[FShownSlot].Interval > 0) then
  begin
    SeqTimer.Interval := FEntries[FShownSlot].Interval;
    SeqTimer.Enabled := True;
  end;
end;

{ The next setOption of the page, with the options it was made with: the chart
  is not reset between steps, which is what lets universalTransition morph
  one option into the next. }
procedure TMainForm.NextStep;
var
  e, k: Integer;
  fn: string;
begin
  e := FShownSlot;
  if (e < 0) or (e > High(FEntries)) then Exit;
  if Length(FEntries[e].StepFiles) < 2 then Exit;
  k := FStep + 1;
  if k > High(FEntries[e].StepFiles) then
  begin
    if FEntries[e].LoopTo < 0 then
    begin
      SeqTimer.Enabled := False;
      Exit;
    end;
    k := FEntries[e].LoopTo;
  end;
  fn := FGalleryDir + FEntries[e].StepFiles[k];
  if not FileExists(fn) then
  begin
    SeqTimer.Enabled := False;
    LblStatus.Caption := Format(rsNotConverted, [fn]);
    Exit;
  end;
  FStep := k;
  OptionMemo.Text := ReadTextFile(fn);
  RegisterGalleryMapsFor(OptionMemo.Text, FMapsDir);
  if FEntries[e].StepOpts[k] = '' then
    Chart.SetOption(OptionMemo.Text, False)
  else
    Chart.SetOption(OptionMemo.Text, FEntries[e].StepOpts[k]);
  if Chart.OptionError <> '' then
  begin
    LblStatus.Caption := Chart.OptionError;
    Exit;
  end;
  ShowNotes(OptionMemo.Text);
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
begin
  FCategories := TStringList.Create;
  FShownSlot := -1;
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);

  FGalleryDir := FindGalleryDir;
  if FGalleryDir = '' then
    LblStatus.Caption := rsNoGallery
  else
  begin
    FMapsDir := ExtractFilePath(ExcludeTrailingPathDelimiter(FGalleryDir))
      + 'maps' + PathDelim;
    LoadIndex;
    FillCategories;
    FillList;
  end;

  { --shot <file> [theme] [dark]: draw once and quit. That is how a real-machine
    render gets captured on a desktop that will not let a background process take
    the foreground -- the pixels come from the running control with a real handle,
    not from a screen grab of whatever happened to be in front. The optional theme
    and mode are what make "the axis follows the skin" checkable rather than
    merely asserted. }
  { `--example <id>` picks one out of the gallery before the shot, so the whole
    corpus can be rendered one file at a time. Scanned rather than positional,
    to leave --shot's existing argument order alone. }
  for i := 1 to ParamCount - 1 do
    if ParamStr(i) = '--example' then
    begin
      if not SelectById(ParamStr(i + 1)) then
        LblStatus.Caption := Format(rsNotConverted, [ParamStr(i + 1)]);
      Break;
    end;
  if (ParamCount >= 2) and (ParamStr(1) = '--shot') then
  begin
    if (ParamCount >= 3) and (ParamStr(3) <> '--example') then
    begin
      TyDefaultController.ThemeName := ParamStr(3);
      if (ParamCount >= 4) and (ParamStr(4) <> '--example') then
        TyDefaultController.Mode := ParamStr(4);
      ApplyChromeTheme(TyDefaultController);
    end;
    Chart.SaveToPng(ParamStr(2));
    Application.Terminate;
  end;
end;

procedure TMainForm.CatTabsChange(Sender: TObject);
begin
  FillList;
end;

procedure TMainForm.ExampleListChange(Sender: TObject);
begin
  ShowSelected;
end;

procedure TMainForm.BtnApplyClick(Sender: TObject);
begin
  { an edited option is not overwritten by the next step of the sequence }
  SeqTimer.Enabled := False;
  Apply;
end;

procedure TMainForm.BtnNextClick(Sender: TObject);
begin
  NextStep;
  { the page's rhythm restarts from the step just shown }
  if SeqTimer.Enabled then
  begin
    SeqTimer.Enabled := False;
    SeqTimer.Enabled := True;
  end;
end;

procedure TMainForm.SeqTimerTimer(Sender: TObject);
begin
  NextStep;
end;

procedure TMainForm.BtnShotClick(Sender: TObject);
var fn: string;
begin
  fn := ExtractFilePath(ParamStr(0)) + 'chart.png';
  Chart.SaveToPng(fn);
  LblStatus.Caption := Format(rsSavedTo, [fn]);
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.DarkSwitchChange(Sender: TObject);
begin
  if DarkSwitch.Checked then
    TyDefaultController.Mode := 'dark'
  else
    TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
end;

end.
