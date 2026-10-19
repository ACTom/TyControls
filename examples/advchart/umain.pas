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
  both of them, in order, on one chart. A page that keeps updating itself on
  a timer (bar-race, the gauges, dynamic-data) was recorded the same way --
  the first thirty updates, on the seeded random numbers -- and plays once.

  WHAT A PAGE DOES IN JAVASCRIPT IS DONE HERE IN PASCAL. A custom series'
  renderItem is a function upstream and a named handler here: the harvest
  writes `renderItem: '@<example id>'`, and urenderitems.pas registers a
  transcription of every one the gallery uses. Five examples compute their
  data (half a million bars, a million points); the gallery ships them
  without it and ugenerated.pas makes it from the page's own generator before
  the option is set. Three that load a large file ship it gzipped.

  WHAT CANNOT BE DRAWN SAYS SO, ON THE CHART. A map the demo does not ship,
  a Baidu map, a projection from a script on a CDN, a file too large to
  ship: the reason is shown over the chart (the chart's own loading mask,
  without the spinner) rather than an empty frame. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Forms, Controls, ExtCtrls, fpjson, jsonparser,
  zstream,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.Button, tyControls.ComboBox, tyControls.ToggleSwitch,
  tyControls.TyLabel, tyControls.Memo, tyControls.ListBox,
  tyControls.TabSet, tyControls.AdvanceChart, tyControls.AdvChart.Diagnose,
  umaps, urenderitems, ugenerated;

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
    { the file the option is in: <id>.json, or <id>.json.gz for the three
      large ones shipped compressed }
    FileName: string;
    { the data is made by ugenerated.pas (index.json `generated`) }
    Generated: Boolean;
    { converted, but too large to ship (and the size, in MB, as the harvest
      wrote it); it draws on Baidu Map }
    TooBig, Bmap: Boolean;
    SizeText: string;
    { what the harvest could not carry ('canvas': a picture the page drew) }
    Lost: string;
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
    { AN OPTION TOO LONG FOR THE EDITOR (the gzipped ones, several MB): the
      memo shows its start and this holds the whole, which Apply sets while
      the memo still shows what it was given }
    FFullText, FShownText: string;
    procedure SetMemoOption(const AText: string);
    function MemoOption: string;
    { The reason the shown example draws nothing (or only part), '' for
      none: shown over the chart. }
    function NoticeFor(const AText: string): string;
    procedure ShowNotice(const ANotice: string);
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
  { over the chart when an example cannot be drawn here }
  rsNoticeTooBig = 'This example is converted, but its option is %s MB -- too '
    + 'large to ship with the demo.';
  rsNoticeBmap = 'This example draws on Baidu Map (bmap), which needs the online '
    + 'Baidu Maps API. TTyAdvanceChart has no bmap coordinate system.';
  rsNoticeUnlicensedSvg = 'This example draws on the SVG map %s from the '
    + 'ECharts examples site, which has no recorded licence, so the demo does '
    + 'not include it. Save the SVG under the map''s name in %s (for instance '
    + 'flight-seats.svg) to see the example.';
  rsNoticeProjection = 'This example projects its map with d3-geo''s Albers USA '
    + 'projection, which the page loads from a CDN; the demo has no Pascal port '
    + 'of it. Register handlers under the names %s with '
    + 'TyChartRegisterGeoProjection to draw it.';
  rsNoticeNotConverted = 'This example could not be converted: %s';
  { under the notes }
  rsNoteLostCanvas = 'The page draws a picture of its own on a canvas (here the '
    + 'background pattern); the harvest cannot carry it, so it is left out.';
  rsNoteGenerated = 'The data of this example is made by ugenerated.pas, from the '
    + 'page''s own code and random numbers; the editor shows the option without '
    + 'it.';
  rsNoteShortened = 'The option is %s MB; the editor shows its beginning, and '
    + 'Apply sets the whole of it while that is unchanged.';
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

{ A gallery file: .json as text, .json.gz unzipped. }
function ReadGalleryFile(const AName: string): string;
var
  gz: TGZFileStream;
  buf: array[0..65535] of Byte;
  n: Integer;
  ss: TStringStream;
begin
  if not AnsiEndsText('.gz', AName) then Exit(ReadTextFile(AName));
  ss := TStringStream.Create('');
  try
    gz := TGZFileStream.Create(AName, gzOpenRead);
    try
      repeat
        n := gz.Read(buf, SizeOf(buf));
        if n > 0 then ss.WriteBuffer(buf, n);
      until n <= 0;
    finally
      gz.Free;
    end;
    Result := ss.DataString;
  finally
    ss.Free;
  end;
end;

{ Text broken into lines of about AWidth columns, at spaces (a wide
  character -- CJK -- counts two and may be broken after), for the notice
  over the chart, which does not wrap. }
function WrapForNotice(const AText: string; AWidth: Integer): string;
var
  i, col, lastSpace, cpLen: Integer;
  line: string;
begin
  Result := '';
  line := '';
  col := 0;
  lastSpace := 0;
  i := 1;
  while i <= Length(AText) do
  begin
    cpLen := 1;
    if Ord(AText[i]) >= $F0 then cpLen := 4
    else if Ord(AText[i]) >= $E0 then cpLen := 3
    else if Ord(AText[i]) >= $C0 then cpLen := 2;
    line := line + Copy(AText, i, cpLen);
    if cpLen >= 3 then Inc(col, 2) else Inc(col);
    if AText[i] = ' ' then lastSpace := Length(line);
    Inc(i, cpLen);
    if col >= AWidth then
    begin
      if (lastSpace > 0) and (cpLen < 3) then
      begin
        Result := Result + TrimRight(Copy(line, 1, lastSpace)) + LineEnding;
        line := Copy(line, lastSpace + 1, MaxInt);
      end
      else
      begin
        Result := Result + line + LineEnding;
        line := '';
      end;
      col := Length(line);
      lastSpace := 0;
    end;
  end;
  Result := Result + line;
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
      FEntries[n].FileName := obj.Get('file', FEntries[n].Id + '.json');
      FEntries[n].Generated := obj.Find('generated') is TJSONObject;
      FEntries[n].TooBig := obj.Get('tooBig', False);
      FEntries[n].Bmap := Pos('bmap', obj.Get('reason', '')) > 0;
      FEntries[n].SizeText := '';
      if FEntries[n].TooBig then
      begin
        k := Pos('but ', FEntries[n].Reason);
        if k > 0 then
          FEntries[n].SizeText := Trim(Copy(FEntries[n].Reason, k + 4,
            Pos(' MB', FEntries[n].Reason) - k - 4));
      end;
      FEntries[n].Lost := '';
      if obj.Find('lost') is TJSONArray then
        FEntries[n].Lost := TJSONArray(obj.Find('lost')).AsJSON;
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
    SetMemoOption('');
    Chart.Option := '';
    LblStatus.Caption := Format(rsNotConverted, [FEntries[slot].Reason]);
    ShowNotice(NoticeFor(''));
    Exit;
  end;

  fn := FGalleryDir + FEntries[slot].FileName;
  if not FileExists(fn) then
  begin
    LblStatus.Caption := Format(rsNotConverted, [fn]);
    Exit;
  end;
  SetMemoOption(ReadGalleryFile(fn));
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

procedure TMainForm.SetMemoOption(const AText: string);
const
  cMemoMax = 1536 * 1024;
  cShown = 256 * 1024;
begin
  FFullText := AText;
  if Length(AText) > cMemoMax then
    FShownText := Copy(AText, 1, cShown) + LineEnding + '...'
  else
    FShownText := AText;
  OptionMemo.Text := FShownText;
  { the memo gives its text back with its own line ends: compare with that }
  FShownText := OptionMemo.Text;
end;

function TMainForm.MemoOption: string;
begin
  Result := OptionMemo.Text;
  if (FFullText <> '') and (Result = FShownText) then Result := FFullText;
end;

procedure TMainForm.Apply;
var opt, filled: string;
begin
  opt := MemoOption;
  { THE PAGE'S OWN registerMap. An ECharts example fetches its GeoJSON before
    it sets the option; the harvest kept only the map's name. }
  RegisterGalleryMapsFor(opt, FMapsDir);
  { THE PAGE'S OWN DATA, for the five that compute it: the arrays the
    harvest left empty are filled where they stand }
  if (FShownSlot >= 0) and (FShownSlot <= High(FEntries))
    and FEntries[FShownSlot].Generated
    and GalleryFillGenerated(FEntries[FShownSlot].Id, opt, filled) then
    Chart.Option := filled
  else
    Chart.Option := opt;
  if Chart.OptionError <> '' then
  begin
    LblStatus.Caption := Chart.OptionError;
    ShowNotice('');
    Exit;
  end;
  ShowNotes(opt);
end;

function TMainForm.NoticeFor(const AText: string): string;
var
  e: Integer;
  names: string;
begin
  Result := '';
  e := FShownSlot;
  if (e < 0) or (e > High(FEntries)) then Exit;
  if not FEntries[e].Ok then
  begin
    if FEntries[e].Bmap then Result := rsNoticeBmap
    else if FEntries[e].TooBig then Result := Format(rsNoticeTooBig, [FEntries[e].SizeText])
    else Result := Format(rsNoticeNotConverted, [FEntries[e].Reason]);
    Exit;
  end;
  if AText = '' then Exit;
  { a Baidu map: the option's own bmap component }
  if Pos('"bmap"', AText) > 0 then Exit(rsNoticeBmap);
  { a map the demo does not ship (each check parses the option: only when
    the option names a map at all) }
  if Pos('"map"', AText) > 0 then
  begin
    names := BorderMapsMissing(AText, FMapsDir);
    if names <> '' then Exit(Format(rsBorderMapNotShipped, [names, FMapsDir]));
    names := UnlicensedMapsMissing(AText, FMapsDir);
    if names <> '' then Exit(Format(rsNoticeUnlicensedSvg, [names, FMapsDir]));
  end;
  names := ProjectionsMissing(AText);
  if names <> '' then Exit(Format(rsNoticeProjection, [names]));
end;

procedure TMainForm.ShowNotice(const ANotice: string);
var cfg: TJSONObject;
begin
  if ANotice = '' then
  begin
    Chart.HideLoading;
    Exit;
  end;
  { THE CHART'S OWN LOADING MASK, without the spinner: the reason sits in
    the chart's frame, in the chart's theme }
  cfg := TJSONObject.Create(['text', WrapForNotice(ANotice, 64),
    'showSpinner', False, 'fontSize', 13]);
  try
    Chart.ShowLoading(cfg.AsJSON);
  finally
    cfg.Free;
  end;
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
  if (FShownSlot >= 0) and (FShownSlot <= High(FEntries)) then
  begin
    if FEntries[FShownSlot].Generated then s := s + LineEnding + rsNoteGenerated;
    if Pos('canvas', FEntries[FShownSlot].Lost) > 0 then
      s := s + LineEnding + rsNoteLostCanvas;
    if Length(FFullText) <> Length(FShownText) then
      s := s + LineEnding + Format(rsNoteShortened,
        [FormatFloat('0.0', Length(FFullText) / 1048576)]);
  end;
  ShowNotice(NoticeFor(AText));
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
  SetMemoOption(ReadGalleryFile(fn));
  RegisterGalleryMapsFor(FFullText, FMapsDir);
  if FEntries[e].StepOpts[k] = '' then
    Chart.SetOption(FFullText, False)
  else
    Chart.SetOption(FFullText, FEntries[e].StepOpts[k]);
  if Chart.OptionError <> '' then
  begin
    LblStatus.Caption := Chart.OptionError;
    Exit;
  end;
  { THE NOTES ARE THE CHART'S, NOT THE STEP FILE'S. A step merged into the
    chart is often a fragment -- `{"series":[{"symbol":...}]}` names no type
    and no grid -- and diagnosed on its own it reads as a broken option ("has
    no type yet", "names an axis that does not exist"). What the chart now
    holds is the merged option, so that is what is diagnosed. }
  ShowNotes(Chart.GetOptionJson);
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
begin
  FCategories := TStringList.Create;
  FShownSlot := -1;
  { the gallery's renderItem functions, transcribed (urenderitems.pas) }
  RegisterGalleryRenderItems;
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
