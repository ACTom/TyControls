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
  switch it off and every key's bytes show in the panel on the right ("Paste" sends
  the clipboard the way a paste shortcut does).

  The player (uasciicast) writes with flow control -- one chunk in the terminal's queue
  at a time, the next when the terminal's write callback says the last is parsed -- so
  "All at once" on a big recording neither freezes the window nor overflows the queue.
  Switching recordings drops what the old one still had queued (Core.DiscardPending)
  instead of parsing it first.

  SHELL MODE. Pick "Shell" and the terminal runs a real program: cmd (or PowerShell,
  pwsh, wsl where they are found) through ConPTY on Windows, the login shell elsewhere.
  The three things a host does are the same three, in ushell: keys go to the PTY on a
  writer thread, the PTY's output is read on a reader thread and written into the
  terminal with a callback that holds a fast program back (flow control), and the grid
  size goes to the PTY. The PTY units -- uptysession, uptywin, uptyunix, ushell -- live
  here in the example, not in the library (spec 12.2). "Log PTY output" lists the first
  4 KB the PTY sends in the panel, in hex: what ConPTY asks the terminal for at start.
  Ctrl+click (Cmd+click) a web address or an OSC 8 link: the example asks before it
  opens a browser, and opens only http and https. OSC 52 is off unless picked; a
  program may then set the clipboard, and must ask before reading it.

  COLOUR SCHEMES. "Colours" switches the terminal from the theme to a colour scheme of
  its own (ColorSource / ColorScheme). The seven listed are Windows Terminal's own, copied
  as they are from its defaults.json into colorschemes/windows-terminal.json (MIT; see
  THIRD-PARTY-NOTICES.md); the three "(light / dark)" entries pair two of them
  (ColorSchemePaired / DarkColorScheme), and the dark-mode switch in the title bar then
  swaps them. "Import..." reads any Windows Terminal scheme file or settings.json and adds
  every scheme in it that loads.

  The window, the terminal and every control are designed in umain.lfm (a TTyForm +
  TTyTitleBar); the code here is event handlers, the player and theme setup. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, ExtCtrls, LazUTF8, LCLIntf, Dialogs,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes, tyControls.Panel,
  tyControls.TyLabel, tyControls.Button, tyControls.ComboBox, tyControls.CheckBox,
  tyControls.ToggleSwitch, tyControls.SpinEdit, tyControls.Memo, tyControls.Splitter,
  tyControls.StatusBar, tyControls.Dialogs, tyControls.Dialogs.FileDialog,
  tyControls.Unicode.Width, tyControls.Terminal.Buffer, tyControls.Terminal.Core, tyControls.Terminal,
  uasciicast, uptysession, uptywin, uptyunix, ushell;

type
  { one entry of the colour list: which scheme file text (FColorTexts; -1 = follow the
    theme) and the names to load -- a pair has a light and a dark one }
  TColorChoice = record
    TextIndex: Integer;
    LightName, DarkName: string;
    Paired: Boolean;
  end;

  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    Tools1: TTyPanel;
    CmbMode: TTyComboBox;
    Tools3: TTyPanel;
    LblCommand: TTyLabel;
    CmbCommand: TTyComboBox;
    BtnStart: TTyButton;
    ChkLogPty: TTyCheckBox;
    Tools4: TTyPanel;
    ChkCopyOnSelect: TTyCheckBox;
    ChkDetectUrls: TTyCheckBox;
    LblOsc52: TTyLabel;
    CmbOsc52: TTyComboBox;
    LblContrast: TTyLabel;
    CmbContrast: TTyComboBox;
    Tools5: TTyPanel;
    LblColors: TTyLabel;
    CmbColors: TTyComboBox;
    BtnImportColors: TTyButton;
    DlgColors: TTyOpenDialog;
    LblRecording: TTyLabel;
    CmbRecording: TTyComboBox;
    BtnOpen: TTyButton;
    BtnPlay: TTyButton;
    BtnStep: TTyButton;
    LblSpeed: TTyLabel;
    CmbSpeed: TTyComboBox;
    BtnFit: TTyButton;
    BtnPaste: TTyButton;
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
    procedure PasteClick(Sender: TObject);
    procedure PlayerTimer(Sender: TObject);
    procedure ReadOnlyClick(Sender: TObject);
    procedure UnicodeChange(Sender: TObject);
    procedure AmbiguousClick(Sender: TObject);
    procedure FontSizeChange(Sender: TObject);
    procedure TermData(Sender: TObject; const AData: RawByteString);
    procedure TermTitleChange(Sender: TObject; const AText: string);
    procedure TermGridResize(Sender: TObject; ACols, ARows: Integer);
    procedure ModeChange(Sender: TObject);
    procedure StartClick(Sender: TObject);
    procedure CopyOnSelectClick(Sender: TObject);
    procedure DetectUrlsClick(Sender: TObject);
    procedure Osc52Change(Sender: TObject);
    procedure ContrastChange(Sender: TObject);
    procedure ColorsChange(Sender: TObject);
    procedure ImportColorsClick(Sender: TObject);
    procedure TermLinkActivate(Sender: TObject; const AUri: string; AFromOsc8: Boolean);
    procedure TermOsc52(Sender: TObject; AWrite: Boolean; const ASelection: string;
      var AText: string; var AAllow: Boolean);
  private
    FShell: TTerminalShell;
    FLogged: Integer;
    procedure FillCommands;
    procedure FocusTerm;
    procedure EnterReplay;
    procedure StartShell;
    procedure ShellData(Sender: TObject; const AData: RawByteString);
    procedure ShellOutput(Sender: TObject; const AData: RawByteString);
    procedure ShellExit(Sender: TObject);
  private
    FCast: TAsciicast;
    FPlayer: TAsciicastPlayer;
    FFiles: TStringList;
    FLastTick: Double;
    FFailed: Boolean;         { a write failed: stop, and say so once }
    procedure LoadCast(const AFileName: string);
    procedure StopPlaying;
    procedure PlayerWrite(Sender: TObject; const AData: RawByteString; ATag: PtrInt);
    procedure TermWriteDone(Sender: TObject; ATag: PtrInt);
    function Speed: Double;
    procedure UpdateProgress;
    procedure AddKeyLine(const S: string);
  private
    { the colour list: one entry per item of CmbColors; a scheme file's text is kept once
      in FColorTexts and the entries point at it (-1 = follow the theme) }
    FColorTexts: TStringList;
    FColorChoices: array of TColorChoice;
    function AddColorChoice(const ACaption: string; ATextIndex: Integer;
      const ALight, ADark: string; APaired: Boolean): Integer;
    procedure FillColors;
  public
    { "Import...": every scheme in the file that loads joins the list and the first one is
      picked; a file with none says why in the status bar and changes nothing }
    procedure ImportColorsFrom(const AFileName: string);
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
  rsSpeedAllAtOnce = 'All at once';
  rsWriteFailedFmt = 'Playback stopped: %s';
  rsModeReplay = 'Replay';
  rsModeShell = 'Shell';
  rsStart = 'Start';
  rsRestart = 'Restart';
  rsLogStopped = '(stopped logging: 4 KB shown)';
  rsOsc52Off = 'Off';
  rsOsc52Write = 'Write only';
  rsOsc52ReadWrite = 'Read and write';
  rsOpenLinkFmt = 'Open %s?';
  rsLinkNotOpenedFmt = 'Not opened (only http and https): %s';
  rsClipboardSetFmt = 'The program set the clipboard (%d characters)';
  rsAllowClipboardRead = 'The program asks to read the clipboard. Allow it?';
  rsShellExitedStatusFmt = 'Shell exited (%d)';
  rsShellFailedFmt = 'Could not start: %s';
  rsColorsFollowTheme = 'Follow theme';
  rsColorsPairFmt = '%s (light / dark)';
  rsColorsImportFailedFmt = 'Could not import: %s';

const
  { the key panel keeps the last this many lines }
  KeyLinesMax = 1000;
  { "Log PTY output" lists at most this many bytes of one session }
  PtyLogMax = 4096;

{ a folder of the example's: next to the executable, or up the tree (lib/<target>/ builds) }
function ExampleDir(const ASub: string): string;
var
  Dir: string;
  i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + ASub) then Exit(Dir + ASub + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := ASub + PathDelim;
end;

function RecordingsDir: string;
begin
  Result := ExampleDir('recordings');
end;

{ a whole file as it is (a colour scheme file: UTF-8, maybe with a BOM the reader drops) }
function ReadWholeFile(const AFileName: string): string;
var
  fs: TFileStream;
begin
  Result := '';
  fs := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, fs.Size);
    if Length(Result) > 0 then
      fs.ReadBuffer(Result[1], Length(Result));
  finally
    fs.Free;
  end;
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
  FPlayer := TAsciicastPlayer.Create(FCast);
  FPlayer.OnWrite := @PlayerWrite;
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
  { the combos' items live in the .lfm; the ones that are words are translated here }
  CmbSpeed.Items[4] := rsSpeedAllAtOnce;
  CmbMode.Items[0] := rsModeReplay;
  CmbMode.Items[1] := rsModeShell;
  CmbOsc52.Items[0] := rsOsc52Off;
  CmbOsc52.Items[1] := rsOsc52Write;
  CmbOsc52.Items[2] := rsOsc52ReadWrite;
  BtnStart.Caption := rsStart;
  FillCommands;
  FColorTexts := TStringList.Create;
  FillColors;
  AddKeyLine(rsReadOnlyHint);
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  { the shell first: its pending pumps go before anything they touch. Freeing it
    returns at once; its program is taken down on a thread of its own, which the
    example waits for here, once and bounded, before it exits }
  FreeAndNil(FShell);
  PtyWaitForFinishers(PtyExitWaitMs);
  Player.Enabled := False;
  FFiles.Free;
  FPlayer.Free;
  FCast.Free;
  FColorTexts.Free;
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
  { what the old recording still has queued is dropped, not parsed first; its write
    callback would carry the old tag and is ignored after the Rewind }
  Term.Core.DiscardPending;
  try
    FCast.LoadFromFile(AFileName);        { a file that does not load leaves FCast as it was }
  except
    on E: Exception do
    begin
      FPlayer.Rewind;
      TyShowMessage(E.Message);
      Exit;
    end;
  end;
  FPlayer.Rewind;
  FFailed := False;
  { a fresh screen and no scrollback, then wait at the start }
  Term.Reset;
  Term.Clear;
  Term.WriteSync(#27'[H'#27'[2J');
  AddKeyLine(Format(rsRecordingSizeFmt, [ExtractFileName(AFileName), FCast.Width, FCast.Height]));
  UpdateProgress;
end;

procedure TMainForm.RecordingChange(Sender: TObject);
begin
  if CmbRecording.ItemIndex < 0 then Exit;
  LoadCast(RecordingsDir + CmbRecording.Items[CmbRecording.ItemIndex]);
  FocusTerm;
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
  if FPlayer.Finished then
    LoadCast(FCast.FileName);
  FFailed := False;
  FLastTick := TyTermDefaultClock;
  Player.Enabled := True;
  BtnPlay.Caption := rsPause;
  FocusTerm;
end;

{ The player's chunk: Write only queues (the terminal parses in slices from the message
  loop, so a big recording never blocks the window); the callback hands the tag back to
  the player, which then writes the next chunk. A write that fails (the queue is full,
  a handler raised) stops the playback and is reported once. }
procedure TMainForm.PlayerWrite(Sender: TObject; const AData: RawByteString; ATag: PtrInt);
begin
  try
    Term.Write(AData, @TermWriteDone, ATag);
  except
    on E: Exception do
    begin
      StopPlaying;
      if not FFailed then
      begin
        FFailed := True;
        TyShowMessage(Format(rsWriteFailedFmt, [E.Message]));
      end;
    end;
  end;
end;

procedure TMainForm.TermWriteDone(Sender: TObject; ATag: PtrInt);
begin
  FPlayer.ChunkDone(ATag);
end;

procedure TMainForm.StepClick(Sender: TObject);
begin
  StopPlaying;
  FPlayer.Step;
  UpdateProgress;
end;

procedure TMainForm.PlayerTimer(Sender: TObject);
var
  now_: Double;
begin
  now_ := TyTermDefaultClock;
  FPlayer.Advance(now_ - FLastTick, Speed);
  FLastTick := now_;
  if FPlayer.Finished and not FPlayer.InFlight then StopPlaying;
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

procedure TMainForm.PasteClick(Sender: TObject);
begin
  { the same path as Ctrl+Shift+V: bracketed when the program asked for it, then out
    through OnData (the key panel) }
  Term.PasteFromClipboard;
  FocusTerm;
end;

procedure TMainForm.ReadOnlyClick(Sender: TObject);
begin
  Term.ReadOnly := ChkReadOnly.Checked;
  if Term.ReadOnly then AddKeyLine(rsReadOnlyHint);
  FocusTerm;
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

procedure TMainForm.AddKeyLine(const S: string);
var
  i: Integer;
begin
  { a bounded panel: holding a key down for a minute must not grow it without end }
  if Keys.Lines.Count >= KeyLinesMax then
  begin
    Keys.Lines.BeginUpdate;
    try
      for i := 1 to KeyLinesMax div 5 do
        Keys.Lines.Delete(0);
    finally
      Keys.Lines.EndUpdate;
    end;
  end;
  Keys.Lines.Add(S);
  Keys.CaretPos := MaxInt;
end;

procedure TMainForm.TermData(Sender: TObject; const AData: RawByteString);
begin
  AddKeyLine(Describe(AData));
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

{ ---- Shell mode ---------------------------------------------------------------------- }

{ Windows: %COMSPEC% first (always there, starts fastest), then PowerShell, and pwsh /
  wsl where the PATH has them. Elsewhere: the login shell. }
{ Handlers that end by giving the terminal the keyboard also run while the form is
  being built: FormCreate selects the first recording, which fires RecordingChange.
  A form that is not showing yet cannot take focus, and SetFocus raises there.
  CanSetFocus, not CanFocus: CanFocus stops at the form and never asks whether the
  form itself is showing. }
procedure TMainForm.FocusTerm;
begin
  if Term.CanSetFocus then
    Term.SetFocus;
end;

procedure TMainForm.FillCommands;
var
  sh: string;
begin
  CmbCommand.Items.Clear;
  {$IFDEF MSWINDOWS}
  sh := GetEnvironmentVariable('COMSPEC');
  if sh = '' then sh := 'cmd.exe';
  CmbCommand.Items.Add(sh);
  CmbCommand.Items.Add('powershell.exe');
  if FileSearch('pwsh.exe', GetEnvironmentVariable('PATH')) <> '' then
    CmbCommand.Items.Add('pwsh.exe');
  if FileSearch('wsl.exe', GetEnvironmentVariable('PATH')) <> '' then
    CmbCommand.Items.Add('wsl.exe');
  {$ELSE}
  sh := GetEnvironmentVariable('SHELL');
  if sh = '' then sh := '/bin/sh';
  CmbCommand.Items.Add(sh + ' -l');
  {$ENDIF}
  CmbCommand.ItemIndex := 0;
  CmbCommand.Text := CmbCommand.Items[0];
end;

procedure TMainForm.ModeChange(Sender: TObject);
begin
  if CmbMode.ItemIndex = 1 then
  begin
    StopPlaying;
    Term.Core.DiscardPending;
    Term.Reset;
    { right under Tools2 and above Tools4: same-side aligned siblings go by Top }
    Tools3.Top := Tools4.Top - 1;
    Tools3.Visible := True;
    StartShell;
  end
  else
    EnterReplay;
end;

procedure TMainForm.EnterReplay;
var
  none: TTyTerminalWindowsPty;
begin
  FreeAndNil(FShell);
  Tools3.Visible := False;
  Term.ReadOnly := ChkReadOnly.Checked;
  none.Backend := twpNone;
  none.BuildNumber := 0;
  Term.Core.WindowsPty := none;
  BtnStart.Caption := rsStart;
  if FCast.FileName <> '' then
    LoadCast(FCast.FileName);
end;

procedure TMainForm.StartShell;
var
  backend: TPtyBackend;
  err: string;
begin
  FreeAndNil(FShell);
  {$IFDEF MSWINDOWS}
  backend := TConPtyBackend.Create;
  {$ELSE}
  backend := TUnixPtyBackend.Create;
  {$ENDIF}
  FShell := TTerminalShell.Create(Term, backend);
  FShell.OnData := @ShellData;
  FShell.OnOutput := @ShellOutput;
  FShell.OnExit := @ShellExit;
  FLogged := 0;
  if not FShell.Start(CmbCommand.Text, err) then
  begin
    FreeAndNil(FShell);
    Status.Panels[0].Text := Format(rsShellFailedFmt, [err]);
    CmbMode.ItemIndex := 0;
    EnterReplay;
    Exit;
  end;
  Status.Panels[0].Text := CmbCommand.Text;
  BtnStart.Caption := rsRestart;
  FocusTerm;
end;

procedure TMainForm.StartClick(Sender: TObject);
begin
  Term.Core.DiscardPending;
  Term.Reset;
  StartShell;
end;

procedure TMainForm.ShellData(Sender: TObject; const AData: RawByteString);
begin
  AddKeyLine(Describe(AData));
end;

{ the first 4 KB of what the PTY sends, in hex (what ConPTY asks for at start) }
procedure TMainForm.ShellOutput(Sender: TObject; const AData: RawByteString);
var
  n: Integer;
begin
  if not ChkLogPty.Checked or (FLogged >= PtyLogMax) then Exit;
  n := Length(AData);
  if n > PtyLogMax - FLogged then n := PtyLogMax - FLogged;
  AddKeyLine('< ' + Describe(Copy(AData, 1, n)));
  Inc(FLogged, n);
  if FLogged >= PtyLogMax then
    AddKeyLine(rsLogStopped);
end;

procedure TMainForm.ShellExit(Sender: TObject);
begin
  Status.Panels[0].Text := Format(rsShellExitedStatusFmt, [FShell.ExitCode]);
  BtnStart.Caption := rsRestart;
end;

procedure TMainForm.CopyOnSelectClick(Sender: TObject);
begin
  Term.CopyOnSelect := ChkCopyOnSelect.Checked;
end;

procedure TMainForm.DetectUrlsClick(Sender: TObject);
begin
  Term.DetectUrls := ChkDetectUrls.Checked;
end;

procedure TMainForm.Osc52Change(Sender: TObject);
begin
  if CmbOsc52.ItemIndex >= 0 then
    Term.Osc52 := TTyTerminalOsc52Policy(CmbOsc52.ItemIndex);
end;

{ 1 = off; 4.5 is WCAG AA for text. The items are numbers with a point, read the same
  whatever the system's decimal separator. }
procedure TMainForm.ContrastChange(Sender: TObject);
var
  fs: TFormatSettings;
begin
  if CmbContrast.ItemIndex < 0 then Exit;
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Term.MinimumContrastRatio := StrToFloatDef(CmbContrast.Items[CmbContrast.ItemIndex], 1, fs);
end;

{ ---- colour schemes ---- }

function TMainForm.AddColorChoice(const ACaption: string; ATextIndex: Integer;
  const ALight, ADark: string; APaired: Boolean): Integer;
begin
  Result := CmbColors.Items.Add(ACaption);
  if Length(FColorChoices) <= Result then
    SetLength(FColorChoices, Result + 1);
  FColorChoices[Result].TextIndex := ATextIndex;
  FColorChoices[Result].LightName := ALight;
  FColorChoices[Result].DarkName := ADark;
  FColorChoices[Result].Paired := APaired;
end;

procedure TMainForm.FillColors;
const
  Pairs: array[0..2, 0..2] of string = (
    ('One Half', 'One Half Light', 'One Half Dark'),
    ('Solarized', 'Solarized Light', 'Solarized Dark'),
    ('Tango', 'Tango Light', 'Tango Dark'));
var
  fn, txt: string;
  names: TStringArray;
  i, t: Integer;

  function Listed(const AName: string): Boolean;
  var
    k: Integer;
  begin
    for k := 0 to High(names) do
      if names[k] = AName then Exit(True);
    Result := False;
  end;

begin
  CmbColors.Items.Clear;
  FColorChoices := nil;
  AddColorChoice(rsColorsFollowTheme, -1, '', '', False);
  fn := ExampleDir('colorschemes') + 'windows-terminal.json';
  if FileExists(fn) then
  begin
    txt := '';
    try
      txt := ReadWholeFile(fn);
    except
      on E: Exception do
        Status.Panels[0].Text := Format(rsColorsImportFailedFmt, [E.Message]);
    end;
    names := TTyTerminalColorScheme.ListSchemeNames(txt);
    if Length(names) > 0 then
    begin
      t := FColorTexts.Add(txt);
      for i := 0 to High(names) do
        AddColorChoice(names[i], t, names[i], names[i], False);
      for i := 0 to High(Pairs) do
        if Listed(Pairs[i, 1]) and Listed(Pairs[i, 2]) then
          AddColorChoice(Format(rsColorsPairFmt, [Pairs[i, 0]]), t, Pairs[i, 1], Pairs[i, 2], True);
    end;
  end;
  CmbColors.ItemIndex := 0;
end;

procedure TMainForm.ColorsChange(Sender: TObject);
var
  i: Integer;
  err: string;
begin
  i := CmbColors.ItemIndex;
  if (i < 0) or (i > High(FColorChoices)) then Exit;
  if FColorChoices[i].TextIndex < 0 then
  begin
    Term.ColorSource := tsrcTheme;
    Exit;
  end;
  { several settings in a row: the terminal tells the program about the new colours once }
  if not Term.ColorScheme.TryLoadFromText(FColorTexts[FColorChoices[i].TextIndex],
    FColorChoices[i].LightName, err) then
  begin
    Status.Panels[0].Text := Format(rsColorsImportFailedFmt, [err]);
    Exit;
  end;
  if FColorChoices[i].Paired and not Term.DarkColorScheme.TryLoadFromText(
    FColorTexts[FColorChoices[i].TextIndex], FColorChoices[i].DarkName, err) then
  begin
    Status.Panels[0].Text := Format(rsColorsImportFailedFmt, [err]);
    Exit;
  end;
  Term.ColorSchemePaired := FColorChoices[i].Paired;
  Term.ColorSource := tsrcScheme;
end;

procedure TMainForm.ImportColorsClick(Sender: TObject);
begin
  if DlgColors.Execute then
    ImportColorsFrom(DlgColors.FileName);
end;

procedure TMainForm.ImportColorsFrom(const AFileName: string);
var
  txt, err, shown: string;
  names, added: TStringArray;
  probe: TTyTerminalColorScheme;
  i, k, t, first, n: Integer;
  dup: Boolean;
begin
  try
    txt := ReadWholeFile(AFileName);
  except
    on E: Exception do
    begin
      Status.Panels[0].Text := Format(rsColorsImportFailedFmt, [E.Message]);
      Exit;
    end;
  end;
  names := TTyTerminalColorScheme.ListSchemeNames(txt);
  added := nil;
  first := -1;
  t := -1;
  err := '';
  probe := TTyTerminalColorScheme.Create;
  try
    for i := 0 to High(names) do
    begin
      { a name twice in a settings.json: only its first scheme is ever read }
      dup := False;
      for k := 0 to High(added) do
        if added[k] = names[i] then dup := True;
      if dup then Continue;
      if not probe.TryLoadFromText(txt, names[i], err) then Continue;
      if t < 0 then t := FColorTexts.Add(txt);
      n := Length(added);
      SetLength(added, n + 1);
      added[n] := names[i];
      shown := names[i];
      if shown = '' then shown := ExtractFileName(AFileName);
      k := AddColorChoice(shown, t, names[i], names[i], False);
      if first < 0 then first := k;
    end;
    if first < 0 then
    begin
      { nothing loads: say why (a text with no scheme at all gets the reader's own reason) }
      if err = '' then probe.TryLoadFromText(txt, '', err);
      Status.Panels[0].Text := Format(rsColorsImportFailedFmt, [err]);
      Exit;
    end;
  finally
    probe.Free;
  end;
  CmbColors.ItemIndex := first;
  ColorsChange(CmbColors);
end;

{ The control opens nothing: the host decides. Here, like xterm.js's own OSC 8 default:
  ask first, and only http and https. }
procedure TMainForm.TermLinkActivate(Sender: TObject; const AUri: string; AFromOsc8: Boolean);
var
  lower: string;
begin
  lower := LowerCase(AUri);
  if (Copy(lower, 1, 7) = 'http://') or (Copy(lower, 1, 8) = 'https://') then
  begin
    if TyMessageDlg(Format(rsOpenLinkFmt, [AUri]), mtConfirmation, [mbYes, mbNo]) = mrYes then
      OpenURL(AUri);
  end
  else
    Status.Panels[0].Text := Format(rsLinkNotOpenedFmt, [AUri]);
end;

{ OSC 52: a write is let through and shown; a read needs a yes. This runs in the middle
  of parsing: a modal dialog is fine, freeing the terminal (or switching modes, which
  frees the shell) is not. }
procedure TMainForm.TermOsc52(Sender: TObject; AWrite: Boolean; const ASelection: string;
  var AText: string; var AAllow: Boolean);
begin
  if AWrite then
  begin
    AAllow := True;
    Status.Panels[0].Text := Format(rsClipboardSetFmt, [UTF8Length(AText)]);
  end
  else
    AAllow := TyMessageDlg(rsAllowClipboardRead, mtConfirmation, [mbYes, mbNo]) = mrYes;
end;

procedure TMainForm.UpdateProgress;
var
  t: Double;
begin
  if FPlayer.Next > 0 then t := FCast[FPlayer.Next - 1].Time else t := 0;
  Status.Panels[0].Text := Format(rsProgressFmt, [FPlayer.Next, FCast.Count, t]);
end;

end.
