unit umain;

{ TTyTerminalView demo: replaying asciicast recordings.

  What a host does with the terminal is three things, and all three are here:
    - Term.Write(bytes)        feed it a program's output (here: the recording's "o"
                               events, at their own pace, faster, all at once or one
                               at a time);
    - Term.OnData              the bytes it wants to send back -- key presses, pastes,
                               replies to the program's queries. A real host writes
                               them to the PTY; here they go into the key panel, and
                               with "Local echo" back into the terminal;
    - Term.OnGridResize        the grid changed size -- a real host resizes its PTY
                               (the status bar shows it here).
  Phase 4 of the terminal adds a PTY example; this one needs no process at all.

  "Fit to recording" asks the terminal how big a client area the recording's grid
  needs (SizeForGrid) and grows or shrinks the window by the difference. Read-only is
  on at start: the recordings are output only, and a key typed into them goes nowhere;
  switch it off and every key's bytes show in the panel on the right.

  The window, the terminal and every control are designed in umain.lfm (a TTyForm +
  TTyTitleBar); the code here is event handlers, the player and theme setup. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, ExtCtrls, LazUTF8,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes, tyControls.Panel,
  tyControls.TyLabel, tyControls.Button, tyControls.ComboBox, tyControls.CheckBox,
  tyControls.ToggleSwitch, tyControls.SpinEdit, tyControls.Memo, tyControls.Splitter,
  tyControls.StatusBar, tyControls.Dialogs, tyControls.Dialogs.FileDialog,
  tyControls.Unicode.Width, tyControls.Terminal.Core, tyControls.Terminal, uasciicast;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    Tools1: TTyPanel;
    LblRecording: TTyLabel;
    CmbRecording: TTyComboBox;
    BtnOpen: TTyButton;
    BtnPlay: TTyButton;
    BtnStep: TTyButton;
    LblSpeed: TTyLabel;
    CmbSpeed: TTyComboBox;
    BtnFit: TTyButton;
    Tools2: TTyPanel;
    ChkReadOnly: TTyCheckBox;
    ChkEcho: TTyCheckBox;
    LblUnicode: TTyLabel;
    CmbUnicode: TTyComboBox;
    ChkAmbiguous: TTyCheckBox;
    LblFontSize: TTyLabel;
    SpnFontSize: TTySpinEdit;
    Status: TTyStatusBar;
    Keys: TTyMemo;
    Split: TTySplitter;
    Term: TTyTerminalView;
    DlgOpen: TTyOpenDialog;
    Player: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure RecordingChange(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure PlayClick(Sender: TObject);
    procedure StepClick(Sender: TObject);
    procedure FitClick(Sender: TObject);
    procedure PlayerTimer(Sender: TObject);
    procedure ReadOnlyClick(Sender: TObject);
    procedure UnicodeChange(Sender: TObject);
    procedure AmbiguousClick(Sender: TObject);
    procedure FontSizeChange(Sender: TObject);
    procedure TermData(Sender: TObject; const AData: RawByteString);
    procedure TermTitleChange(Sender: TObject; const AText: string);
    procedure TermGridResize(Sender: TObject; ACols, ARows: Integer);
  private
    FCast: TAsciicast;
    FFiles: TStringList;
    FNext: Integer;           { the next event to write }
    FPlayedMs: Double;        { recording time reached }
    FLastTick: Double;
    procedure LoadCast(const AFileName: string);
    procedure StopPlaying;
    procedure WriteNext;
    function Speed: Double;
    procedure UpdateProgress;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  rsPlay = 'Play';
  rsPause = 'Pause';
  rsProgressFmt = 'Event %d / %d · %.1f s';
  rsGridFmt = '%d x %d';
  rsNoRecording = 'No recording';
  rsReadOnlyHint = 'Switch read-only off to see the bytes of each key here.';
  rsRecordingSizeFmt = '%s: recorded at %d x %d';

function RecordingsDir: string;
var
  Dir: string;
  i: Integer;
begin
  { next to the executable, or up the tree (lib/<target>/ builds) }
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'recordings') then Exit(Dir + 'recordings' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'recordings' + PathDelim;
end;

{ '1B 5B 41  ESC [ A': the bytes, then a readable spelling }
function Describe(const AData: RawByteString): string;
var
  hex, text: string;
  i: Integer;
  b: Byte;
begin
  hex := '';
  text := '';
  for i := 1 to Length(AData) do
  begin
    b := Ord(AData[i]);
    if hex <> '' then hex := hex + ' ';
    hex := hex + IntToHex(b, 2);
    case b of
      27: text := text + 'ESC ';
      127: text := text + 'DEL ';
      0..26, 28..31: text := text + '^' + Chr(b + 64) + ' ';
    else
      text := text + Chr(b);
    end;
  end;
  Result := hex + '  ' + text;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  sr: TSearchRec;
  i: Integer;
begin
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);

  FCast := TAsciicast.Create;
  FFiles := TStringList.Create;
  FFiles.Sorted := True;
  if FindFirst(RecordingsDir + '*.cast', faAnyFile, sr) = 0 then
  try
    repeat
      FFiles.Add(sr.Name);
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
  CmbRecording.Items.Assign(FFiles);
  if FFiles.Count > 0 then
  begin
    CmbRecording.ItemIndex := 0;
    LoadCast(RecordingsDir + FFiles[0]);
  end
  else
    Status.Panels[0].Text := rsNoRecording;
  BtnPlay.Caption := rsPlay;
  Keys.Lines.Add(rsReadOnlyHint);
  ActiveControl := Term;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  Player.Enabled := False;
  FFiles.Free;
  FCast.Free;
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

procedure TMainForm.LoadCast(const AFileName: string);
begin
  StopPlaying;
  try
    FCast.LoadFromFile(AFileName);
  except
    on E: Exception do
    begin
      TyShowMessage(E.Message);
      Exit;
    end;
  end;
  { a fresh screen and no scrollback, then wait at the start }
  Term.Reset;
  Term.Clear;
  Term.WriteSync(#27'[H'#27'[2J');
  FNext := 0;
  FPlayedMs := 0;
  Keys.Lines.Add(Format(rsRecordingSizeFmt, [ExtractFileName(AFileName), FCast.Width, FCast.Height]));
  UpdateProgress;
end;

procedure TMainForm.RecordingChange(Sender: TObject);
begin
  if CmbRecording.ItemIndex < 0 then Exit;
  LoadCast(RecordingsDir + CmbRecording.Items[CmbRecording.ItemIndex]);
  Term.SetFocus;
end;

procedure TMainForm.OpenClick(Sender: TObject);
begin
  DlgOpen.InitialDir := RecordingsDir;
  if DlgOpen.Execute then
    LoadCast(DlgOpen.FileName);
end;

function TMainForm.Speed: Double;
begin
  case CmbSpeed.ItemIndex of
    0: Result := 0.5;
    2: Result := 2;
    3: Result := 4;
    4: Result := -1;            { all at once }
  else
    Result := 1;
  end;
end;

procedure TMainForm.StopPlaying;
begin
  Player.Enabled := False;
  BtnPlay.Caption := rsPlay;
end;

procedure TMainForm.PlayClick(Sender: TObject);
begin
  if Player.Enabled then
  begin
    StopPlaying;
    Exit;
  end;
  if FNext >= FCast.Count then
    LoadCast(FCast.FileName);
  FLastTick := TyTermDefaultClock;
  Player.Enabled := True;
  BtnPlay.Caption := rsPause;
  Term.SetFocus;
end;

procedure TMainForm.WriteNext;
begin
  { Write only queues: the terminal parses in slices from the message loop, so a big
    recording never blocks the window }
  Term.Write(FCast[FNext].Data);
  FPlayedMs := FCast[FNext].Time * 1000;
  Inc(FNext);
end;

procedure TMainForm.StepClick(Sender: TObject);
begin
  StopPlaying;
  if FNext < FCast.Count then
    WriteNext;
  UpdateProgress;
end;

procedure TMainForm.PlayerTimer(Sender: TObject);
var
  now_, s: Double;
begin
  now_ := TyTermDefaultClock;
  s := Speed;
  if s < 0 then
    while FNext < FCast.Count do WriteNext
  else
  begin
    FPlayedMs := FPlayedMs + (now_ - FLastTick) * s;
    while (FNext < FCast.Count) and (FCast[FNext].Time * 1000 <= FPlayedMs) do
    begin
      Term.Write(FCast[FNext].Data);
      Inc(FNext);
    end;
  end;
  FLastTick := now_;
  if FNext >= FCast.Count then StopPlaying;
  UpdateProgress;
end;

procedure TMainForm.FitClick(Sender: TObject);
var
  sz: TSize;
  dw, dh: Integer;
begin
  { the client area the recording's grid needs; the window grows or shrinks by the
    difference (a SetBounds to the same rectangle would do nothing) }
  sz := Term.SizeForGrid(FCast.Width, FCast.Height);
  dw := sz.cx - Term.ClientWidth;
  dh := sz.cy - Term.ClientHeight;
  if (dw <> 0) or (dh <> 0) then
    SetBounds(Left, Top, Width + dw, Height + dh);
end;

procedure TMainForm.ReadOnlyClick(Sender: TObject);
begin
  Term.ReadOnly := ChkReadOnly.Checked;
  if Term.ReadOnly then Keys.Lines.Add(rsReadOnlyHint);
  Term.SetFocus;
end;

procedure TMainForm.UnicodeChange(Sender: TObject);
begin
  { the combo lists TTyUnicodeVersion in declaration order: 6, 11, 15, 15-graphemes }
  if CmbUnicode.ItemIndex >= 0 then
    Term.UnicodeVersion := TTyUnicodeVersion(CmbUnicode.ItemIndex);
end;

procedure TMainForm.AmbiguousClick(Sender: TObject);
begin
  Term.AmbiguousWide := ChkAmbiguous.Checked;
end;

procedure TMainForm.FontSizeChange(Sender: TObject);
begin
  { an explicit Font beats the theme's size (StyleOverride would beat both) }
  Term.ParentFont := False;
  Term.Font.Size := SpnFontSize.Value;
end;

procedure TMainForm.TermData(Sender: TObject; const AData: RawByteString);
begin
  Keys.Lines.Add(Describe(AData));
  Keys.CaretPos := MaxInt;
  if ChkEcho.Checked then
    Term.Write(AData);
end;

procedure TMainForm.TermTitleChange(Sender: TObject; const AText: string);
begin
  Status.Panels[2].Text := AText;
end;

procedure TMainForm.TermGridResize(Sender: TObject; ACols, ARows: Integer);
begin
  Status.Panels[1].Text := Format(rsGridFmt, [ACols, ARows]);
end;

procedure TMainForm.UpdateProgress;
var
  t: Double;
begin
  if FNext > 0 then t := FCast[FNext - 1].Time else t := 0;
  Status.Panels[0].Text := Format(rsProgressFmt, [FNext, FCast.Count, t]);
end;

end.
