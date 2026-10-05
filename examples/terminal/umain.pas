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
  every scheme in it that loads, each name once (importing a file again adds nothing new).

  ZMODEM (phase 7). With "ZModem" ticked, a remote sz or rz in the shell is spotted in the
  output (uzmodemterm: a stream handler on the core, ZMODEM written for the example):
  sz asks where to save (every time; the folder picked last is offered first), rz asks
  which files to send. The dialogs are shown from a queued call -- the request comes in
  the middle of the core's parse. A line in the terminal shows the progress and then a
  summary; the bar at the bottom shows the file and has "Cancel" (five Ctrl+X in the
  terminal do the same). Received files never overwrite one: "name (1).ext". On Windows
  ConPTY drops every byte from $80 up, so ZModem needs "Pipe": the command then runs on
  two plain pipes -- binary safe, but a pipe is no terminal: nothing turns the CR of
  Enter into LF, echoes, turns LF into CR LF or passes the window's size. So with "Pipe"
  the list offers commands that open a terminal on the far side: WSL, one entry per
  distribution, the default first (uwslpipe: a PTY in Linux through script, or python3
  where there is no script; the grid at the start from %COLS% / %ROWS%), and ssh -tt. A
  distribution with neither ends at once, and the example says what to install. cmd and
  PowerShell are not listed: on a pipe they have no line editing, no echo and no width,
  and write in the OEM code page. The pipe carries data only: for the WSL entries a later
  size goes to the PTY in Linux through a short side process (uwslresize, about half a
  second); ssh -tt keeps the size it started with. Behind ConPTY the terminal says so and
  stops sz / rz.

  CURSOR. "Cursor", "Blink" and "Unfocused" set the terminal's own cursor (CursorStyle,
  CursorBlink, CursorInactiveStyle). A program can ask for another shape for a while --
  vim's insert mode asks for a bar with DECSCUSR -- and CSI 0 SP q (or a reset) brings back
  the one picked here.

  The window, the terminal and every control are designed in umain.lfm (a TTyForm +
  TTyTitleBar); the code here is event handlers, the player and theme setup. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, ExtCtrls, LazUTF8, LCLIntf, Dialogs,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes, tyControls.Panel,
  tyControls.TyLabel, tyControls.Button, tyControls.ComboBox, tyControls.FontComboBox,
  tyControls.CheckBox,
  tyControls.ToggleSwitch, tyControls.SpinEdit, tyControls.Memo, tyControls.Splitter,
  tyControls.StatusBar, tyControls.Dialogs, tyControls.Dialogs.FileDialog,
  tyControls.Dialogs.SelectPath, tyControls.ProgressBar,
  tyControls.Unicode.Width, tyControls.Terminal.Buffer, tyControls.Terminal.Core,
  tyControls.Terminal.ColorScheme, tyControls.Terminal,
  uasciicast, uptysession, uptywin, uptyunix, ushell, uzmodemsession, uzmodemterm, uwslresize,
  uwslpipe;

const
  { The commands "Pipe" lists (Windows). A plain pipe has no line discipline: nobody turns
    the terminal's CR into LF, echoes, turns LF into CR LF or tells the program the window's
    size -- cmd waits for an LF that never comes, PowerShell lays out 120 columns, bash on a
    pipe is not interactive. So these open a terminal on the far side:
    - WSL (uwslpipe's PipeWslCommand, one per distribution: WslPipeCommandFor): the login
      shell on a PTY of Linux, through script (util-linux / bsdutils) or else a python3
      PTY helper; the PTY gets the grid the terminal has at the start (%COLS% / %ROWS%, see
      ExpandGridSize). WSL sets $SHELL from the user's passwd entry under wsl.exe -e too.
      The shell's PID and PTY go into %TTYFILE%: later sizes get there through a side
      process (uwslresize).
    - ssh -tt: the remote side opens a PTY although our end is a pipe (-T would not). Its
      size stays the one at the start: a real SSH client sends a new one in the SSH
      protocol's window-change message, and on a pipe we have the byte stream only. }
  PipeSshCommand = 'ssh -tt user@host';

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
    ChkZmodem: TTyCheckBox;
    ChkPipe: TTyCheckBox;
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
    LblCursor: TTyLabel;
    CmbCursor: TTyComboBox;
    ChkCursorBlink: TTyCheckBox;
    LblCursorInactive: TTyLabel;
    CmbCursorInactive: TTyComboBox;
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
    CmbFont: TTyFontComboBox;
    SpnFontSize: TTySpinEdit;
    Tools6: TTyPanel;
    LblTransfer: TTyLabel;
    BtnCancelTransfer: TTyButton;
    BarTransfer: TTyProgressBar;
    Status: TTyStatusBar;
    Keys: TTyMemo;
    Split: TTySplitter;
    Term: TTyTerminalView;
    DlgOpen: TTyOpenDialog;
    Player: TTimer;
    DlgUpload: TTyOpenDialog;
    DlgDownloadDir: TTySelectPathDialog;
    ZmTimer: TTimer;
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
    procedure FontNameChange(Sender: TObject);
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
    procedure CursorStyleChange(Sender: TObject);
    procedure CursorBlinkClick(Sender: TObject);
    procedure CursorInactiveChange(Sender: TObject);
    procedure TermLinkActivate(Sender: TObject; const AUri: string; AFromOsc8: Boolean);
    procedure TermOsc52(Sender: TObject; AWrite: Boolean; const ASelection: string;
      var AText: string; var AAllow: Boolean);
    procedure TermClaimedInput(Sender: TObject; const AData: RawByteString);
    procedure ZmodemChange(Sender: TObject);
    procedure PipeChange(Sender: TObject);
    procedure CancelTransferClick(Sender: TObject);
    procedure ZmTimerTimer(Sender: TObject);
  private
    FShell: TTerminalShell;
    FLastDownloadDir: string;
    FLogged: Integer;
    FLastZmProgressMs: Double;
    FZmProgressShown: Integer;
    { this shell runs on the pipes; the first bytes it wrote (a WSL entry that found
      neither script nor python3 says so there) }
    FShellPiped: Boolean;
    FOutputHead: RawByteString;
    procedure ZmDownloadRequest(Sender: TObject);
    procedure ZmUploadRequest(Sender: TObject);
    procedure AskDownloadDir(Data: PtrInt);
    procedure AskUploadFiles(Data: PtrInt);
    procedure ZmProgress(Sender: TObject; const AName: string; AFileDone, AFileSize, ATotalDone: Int64);
    procedure ZmFinished(Sender: TObject; AResult: TZmResult; const AMessage: string);
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
    FColorError: Boolean;     { the status bar shows a colour scheme error }
    function AddColorChoice(const ACaption: string; ATextIndex: Integer;
      const ALight, ADark: string; APaired: Boolean): Integer;
    function SchemeEntry(const ACaption: string): Integer;
    procedure FillColors;
    procedure ColorsFailed(const AMessage: string);
    procedure ColorsDone;
  public
    { "Import...": every scheme in the file that loads is in the list once (a name already
      there now reads from this file) and the first one is picked; a file with none says why
      in the status bar and changes nothing }
    procedure ImportColorsFrom(const AFileName: string);
  public
    { FOR THE TESTS: not empty = the download folder, no dialog }
    class var ZmodemAnswerForTest: string;
    { FOR THE TESTS: the next shell runs on this backend (taken over, then cleared) }
    class var ShellBackendForTest: TPtyBackend;
    { FOR THE TESTS: the transfer bar's clock (nil = TyTermDefaultClock) }
    class var ZmClockForTest: TTyTerminalClock;
    { FOR THE TESTS (pure query): progress events the transfer bar showed }
    property ZmProgressShown: Integer read FZmProgressShown;
  end;

var
  MainForm: TMainForm;

{ %COLS% and %ROWS% in a command line -> the grid's columns and rows (every one of them;
  a command without them comes back as it is) }
function ExpandGridSize(const ACommand: string; ACols, ARows: Integer): string;

{ the shell's backend: Windows -- ConPTY, or with APipe the pipes (and for the WSL entry
  the side channel for the size); elsewhere the PTY }
function NewShellBackend(APipe: Boolean): TPtyBackend;

implementation

function NewShellBackend(APipe: Boolean): TPtyBackend;
begin
  {$IFDEF MSWINDOWS}
  if APipe then
    Result := TWslPipeBackend.Create(True)
  else
    Result := TConPtyBackend.Create;
  {$ELSE}
  Result := TUnixPtyBackend.Create;
  {$ENDIF}
end;

function ExpandGridSize(const ACommand: string; ACols, ARows: Integer): string;
begin
  Result := StringReplace(ACommand, '%COLS%', IntToStr(ACols), [rfReplaceAll]);
  Result := StringReplace(Result, '%ROWS%', IntToStr(ARows), [rfReplaceAll]);
end;

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
  rsCursorBlock = 'Block';
  rsCursorUnderline = 'Underline';
  rsCursorBar = 'Bar';
  rsCursorOutline = 'Outline';
  rsCursorNone = 'None';
  rsPipeNextStart = 'Pipe mode takes effect at the next start';
  rsPipeNeedsPtyHelper = 'Pipe mode needs script or python3 in the WSL distribution. '
    + 'Debian / Ubuntu: sudo apt install bsdutils. '
    + 'Fedora: sudo dnf install /usr/bin/script (util-linux-script from Fedora 42 on, util-linux before)';
  rsClaimedKey = '(claimed) %s';

const
  { the key panel keeps the last this many lines }
  KeyLinesMax = 1000;
  { "Log PTY output" lists at most this many bytes of one session }
  PtyLogMax = 4096;

  { the first bytes of a pipe shell's output kept for its exit (IsWslNoPtyHelperExit) }
  OutputHeadMax = 1024;

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

  { The font box starts on nothing chosen (its hint says "Theme font"): until the user picks a
    family the terminal keeps the one its theme gives it. Wired here, not in the .lfm, so that
    filling the list while the form loads does not pick a font for the user. }
  CmbFont.ItemIndex := -1;
  CmbFont.OnChange := @FontNameChange;

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
  CmbCursor.Items[0] := rsCursorBlock;
  CmbCursor.Items[1] := rsCursorUnderline;
  CmbCursor.Items[2] := rsCursorBar;
  CmbCursorInactive.Items[0] := rsCursorOutline;
  CmbCursorInactive.Items[1] := rsCursorBlock;
  CmbCursorInactive.Items[2] := rsCursorBar;
  CmbCursorInactive.Items[3] := rsCursorUnderline;
  CmbCursorInactive.Items[4] := rsCursorNone;
  { the cursor settings show what the terminal has (its defaults, or what the .lfm set) }
  CmbCursor.ItemIndex := Ord(Term.CursorStyle);
  ChkCursorBlink.Checked := Term.CursorBlink;
  CmbCursorInactive.ItemIndex := Ord(Term.CursorInactiveStyle);
  BtnStart.Caption := rsStart;
  { a pipe instead of ConPTY is a Windows matter: elsewhere the PTY is binary safe }
  {$IFNDEF MSWINDOWS}
  ChkPipe.Visible := False;
  {$ENDIF}
  FillCommands;
  FColorTexts := TStringList.Create;
  FillColors;
  AddKeyLine(rsReadOnlyHint);
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  ZmTimer.Enabled := False;
  { the dialogs a transfer queued must not run on a form that is going }
  Application.RemoveAsyncCalls(Self);
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

procedure TMainForm.FontNameChange(Sender: TObject);
begin
  if CmbFont.ItemIndex < 0 then Exit;
  { like the size: an explicit Font beats the theme's family }
  Term.ParentFont := False;
  Term.Font.Name := CmbFont.SelectedFont;
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

{ Windows: %COMSPEC% first (always there, starts fastest), then PowerShell, and pwsh /
  wsl where the PATH has them; with "Pipe" ticked the commands that open a terminal on the
  far side instead: where the PATH has wsl.exe one WSL entry per distribution, the default
  first (asked of wsl.exe the first time, uwslpipe; the entry without -d when that fails),
  then PipeSshCommand. Elsewhere: the login shell. }
procedure TMainForm.FillCommands;
var
  sh: string;
  {$IFDEF MSWINDOWS}
  distros: TStringArray;
  i: Integer;
  {$ENDIF}
begin
  CmbCommand.Items.Clear;
  {$IFDEF MSWINDOWS}
  if ChkPipe.Checked then
  begin
    { no cmd / PowerShell here: on a pipe they have no line editing, no echo, no width }
    if FileSearch('wsl.exe', GetEnvironmentVariable('PATH')) <> '' then
    begin
      distros := WslPipeDistros;
      for i := 0 to High(distros) do
        CmbCommand.Items.Add(WslPipeCommandFor(distros[i]));
      if Length(distros) = 0 then
        CmbCommand.Items.Add(PipeWslCommand);
    end;
    CmbCommand.Items.Add(PipeSshCommand);
    CmbCommand.ItemIndex := 0;
    CmbCommand.Text := CmbCommand.Items[0];
    Exit;
  end;
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
  Application.RemoveAsyncCalls(Self);
  ZmTimer.Enabled := False;
  Tools6.Visible := False;
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
  err, cmd: string;
begin
  { a transfer's queued dialog belongs to the shell that goes now }
  Application.RemoveAsyncCalls(Self);
  Tools6.Visible := False;
  FreeAndNil(FShell);
  backend := NewShellBackend(ChkPipe.Checked);
  if ShellBackendForTest <> nil then
  begin
    backend.Free;
    backend := ShellBackendForTest;
    ShellBackendForTest := nil;
  end;
  FShell := TTerminalShell.Create(Term, backend, 1048576, 262144, True);
  FShell.Zmodem.Enabled := ChkZmodem.Checked;
  FShell.Zmodem.OnDownloadRequest := @ZmDownloadRequest;
  FShell.Zmodem.OnUploadRequest := @ZmUploadRequest;
  FShell.Zmodem.OnProgress := @ZmProgress;
  FShell.Zmodem.OnFinished := @ZmFinished;
  ZmTimer.Enabled := True;
  FShell.OnData := @ShellData;
  FShell.OnOutput := @ShellOutput;
  FShell.OnExit := @ShellExit;
  FLogged := 0;
  FShellPiped := ChkPipe.Checked;
  FOutputHead := '';
  cmd := CmbCommand.Text;
  {$IFDEF MSWINDOWS}
  { the grid reaches the far side of a pipe once, now (stty in the WSL entry) }
  if ChkPipe.Checked then
    cmd := ExpandGridSize(cmd, Term.Cols, Term.Rows);
  {$ENDIF}
  if not FShell.Start(cmd, err) then
  begin
    FreeAndNil(FShell);
    Status.Panels[0].Text := Format(rsShellFailedFmt, [err]);
    CmbMode.ItemIndex := 0;
    EnterReplay;
    Exit;
  end;
  Status.Panels[0].Text := cmd;
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
  if FShellPiped and (Length(FOutputHead) < OutputHeadMax) then
    FOutputHead := FOutputHead + Copy(AData, 1, OutputHeadMax - Length(FOutputHead));
  if not ChkLogPty.Checked or (FLogged >= PtyLogMax) then Exit;
  n := Length(AData);
  if n > PtyLogMax - FLogged then n := PtyLogMax - FLogged;
  AddKeyLine('< ' + Describe(Copy(AData, 1, n)));
  Inc(FLogged, n);
  if FLogged >= PtyLogMax then
    AddKeyLine(rsLogStopped);
end;

{ a WSL entry whose distribution has neither script nor python3 wrote one English line
  and ended with 127 at once: say what to install, in the terminal and the status bar }
procedure TMainForm.ShellExit(Sender: TObject);
begin
  if FShellPiped and IsWslNoPtyHelperExit(FShell.ExitCode, FOutputHead) then
  begin
    Term.WriteSync(#27'[1m' + rsPipeNeedsPtyHelper + #27'[0m'#13#10);
    Status.Panels[0].Text := rsPipeNeedsPtyHelper;
  end
  else
    Status.Panels[0].Text := Format(rsShellExitedStatusFmt, [FShell.ExitCode]);
  BtnStart.Caption := rsRestart;
end;

{ ---- ZModem (phase 7) ---------------------------------------------------------------- }

{ the requests come in the middle of the core's parse (the handler's Feed): the dialog
  is shown from the message loop, never from here }
procedure TMainForm.ZmDownloadRequest(Sender: TObject);
begin
  Application.QueueAsyncCall(@AskDownloadDir, 0);
end;

procedure TMainForm.ZmUploadRequest(Sender: TObject);
begin
  Application.QueueAsyncCall(@AskUploadFiles, 0);
end;

{ every download asks where (the answer is the confirmation); the folder picked last
  is offered first, the user's Downloads the first time }
procedure TMainForm.AskDownloadDir(Data: PtrInt);
var
  dir: string;
begin
  if (FShell = nil) or (FShell.Zmodem = nil) or (FShell.Zmodem.State <> zsAskDownload) then Exit;
  if ZmodemAnswerForTest <> '' then
  begin
    FShell.Zmodem.AcceptDownload(ZmodemAnswerForTest);
    Exit;
  end;
  dir := FLastDownloadDir;
  if dir = '' then
  begin
    dir := IncludeTrailingPathDelimiter(GetUserDir) + 'Downloads';
    if not DirectoryExists(dir) then
      dir := GetUserDir;
  end;
  DlgDownloadDir.Directory := dir;
  { the shell may have gone while the dialog was up }
  if DlgDownloadDir.Execute then
  begin
    FLastDownloadDir := DlgDownloadDir.Directory;
    if (FShell <> nil) and (FShell.Zmodem <> nil) then
      FShell.Zmodem.AcceptDownload(FLastDownloadDir);
  end
  else if (FShell <> nil) and (FShell.Zmodem <> nil) then
    FShell.Zmodem.Decline;
  FocusTerm;
end;

procedure TMainForm.AskUploadFiles(Data: PtrInt);
begin
  if (FShell = nil) or (FShell.Zmodem = nil) or (FShell.Zmodem.State <> zsAskUpload) then Exit;
  if DlgUpload.Execute and (DlgUpload.Files.Count > 0) then
  begin
    if (FShell <> nil) and (FShell.Zmodem <> nil) then
      FShell.Zmodem.StartUpload(DlgUpload.Files);
  end
  else if (FShell <> nil) and (FShell.Zmodem <> nil) then
    FShell.Zmodem.Decline;
  FocusTerm;
end;

{ an event comes for every KB: the bar follows at most every 150 ms -- the first, a new
  file and a file's end always }
procedure TMainForm.ZmProgress(Sender: TObject; const AName: string; AFileDone, AFileSize, ATotalDone: Int64);
const
  EveryMs = 150;
var
  now: Double;
begin
  if Assigned(ZmClockForTest) then
    now := ZmClockForTest()
  else
    now := TyTermDefaultClock;
  if Tools6.Visible and (AName = LblTransfer.Caption) and (AFileDone < AFileSize)
    and (now - FLastZmProgressMs < EveryMs) then
    Exit;
  FLastZmProgressMs := now;
  Inc(FZmProgressShown);
  if not Tools6.Visible then
  begin
    { above the status bar: same-side aligned siblings go by Top }
    Tools6.Top := Status.Top - 1;
    Tools6.Visible := True;
  end;
  LblTransfer.Caption := AName;
  if AFileSize > 0 then
    BarTransfer.Position := Integer(AFileDone * 1000 div AFileSize)
  else
    BarTransfer.Position := 1000;
end;

procedure TMainForm.ZmFinished(Sender: TObject; AResult: TZmResult; const AMessage: string);
begin
  Tools6.Visible := False;
  if (FShell <> nil) and (FShell.Zmodem <> nil) then
    Status.Panels[0].Text := FShell.Zmodem.LastSummary;
end;

procedure TMainForm.CancelTransferClick(Sender: TObject);
begin
  if (FShell <> nil) and (FShell.Zmodem <> nil) then
    FShell.Zmodem.Cancel;
  FocusTerm;
end;

{ runs while a shell does, so a transfer can be switched off (and on) mid-session }
procedure TMainForm.ZmodemChange(Sender: TObject);
begin
  if (FShell <> nil) and (FShell.Zmodem <> nil) then
    FShell.Zmodem.Enabled := ChkZmodem.Checked;
end;

{ the list follows the tick (what is in it works only one way); a running shell keeps
  its backend until the next start }
procedure TMainForm.PipeChange(Sender: TObject);
begin
  FillCommands;
  if FShell <> nil then
    Status.Panels[0].Text := rsPipeNextStart;
end;

procedure TMainForm.ZmTimerTimer(Sender: TObject);
begin
  if (FShell <> nil) and (FShell.Zmodem <> nil) then
    FShell.Zmodem.Tick(TyTermDefaultClock);
end;

{ while a transfer holds the stream: keys go to the handler (five Ctrl+X cancel) and
  into the key panel, marked }
procedure TMainForm.TermClaimedInput(Sender: TObject; const AData: RawByteString);
begin
  AddKeyLine(Format(rsClaimedKey, [Describe(AData)]));
  if (FShell <> nil) and (FShell.Zmodem <> nil) then
    FShell.Zmodem.UserInput(AData);
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
        ColorsFailed(E.Message);
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

{ an entry for a single scheme (not "Follow theme", not a pair) with this caption, or -1 }
function TMainForm.SchemeEntry(const ACaption: string): Integer;
var
  k: Integer;
begin
  for k := 0 to High(FColorChoices) do
    if (FColorChoices[k].TextIndex >= 0) and not FColorChoices[k].Paired
      and (k < CmbColors.Items.Count) and (CmbColors.Items[k] = ACaption) then
      Exit(k);
  Result := -1;
end;

procedure TMainForm.ColorsFailed(const AMessage: string);
begin
  Status.Panels[0].Text := Format(rsColorsImportFailedFmt, [AMessage]);
  FColorError := True;
end;

{ a pick or an import that worked: an earlier "Could not import" no longer applies }
procedure TMainForm.ColorsDone;
begin
  if not FColorError then Exit;
  FColorError := False;
  Status.Panels[0].Text := '';
end;

procedure TMainForm.ColorsChange(Sender: TObject);
var
  i: Integer;
  err, txt: string;
  light, dark: TTyTerminalColorScheme;
begin
  i := CmbColors.ItemIndex;
  if (i < 0) or (i > High(FColorChoices)) then Exit;
  if FColorChoices[i].TextIndex < 0 then
  begin
    Term.ColorSource := tsrcTheme;
    ColorsDone;
    Exit;
  end;
  { both read before anything is set: a pair whose second half does not load leaves the
    terminal exactly as it was }
  txt := FColorTexts[FColorChoices[i].TextIndex];
  light := TTyTerminalColorScheme.Create;
  dark := TTyTerminalColorScheme.Create;
  try
    if not light.TryLoadFromText(txt, FColorChoices[i].LightName, err)
      or (FColorChoices[i].Paired and not dark.TryLoadFromText(txt, FColorChoices[i].DarkName, err)) then
    begin
      ColorsFailed(err);
      Exit;
    end;
    { several settings in a row: the terminal tells the program about the new colours once }
    Term.ColorScheme := light;
    if FColorChoices[i].Paired then
      Term.DarkColorScheme := dark;
    Term.ColorSchemePaired := FColorChoices[i].Paired;
    Term.ColorSource := tsrcScheme;
    ColorsDone;
  finally
    dark.Free;
    light.Free;
  end;
end;

procedure TMainForm.ImportColorsClick(Sender: TObject);
begin
  if DlgColors.Execute then
    ImportColorsFrom(DlgColors.FileName);
end;

procedure TMainForm.ImportColorsFrom(const AFileName: string);
var
  txt, err, shown: string;
  names: TStringArray;
  i, k, t, first: Integer;
begin
  try
    txt := ReadWholeFile(AFileName);
  except
    on E: Exception do
    begin
      ColorsFailed(E.Message);
      Exit;
    end;
  end;
  { one parse: the schemes in the file that load, each name once; none says why }
  if not TyTermSchemeImportPlan(txt, names, err) then
  begin
    ColorsFailed(err);
    Exit;
  end;
  t := FColorTexts.Add(txt);
  first := -1;
  for i := 0 to High(names) do
  begin
    { a scheme without a name (a single scheme file) is listed under the file's name }
    shown := names[i];
    if shown = '' then shown := ExtractFileName(AFileName);
    { a name already in the list -- one of the example's, or imported before -- stays one
      entry, which now reads from this file }
    k := SchemeEntry(shown);
    if k < 0 then
      k := AddColorChoice(shown, t, names[i], names[i], False)
    else
    begin
      FColorChoices[k].TextIndex := t;
      FColorChoices[k].LightName := names[i];
      FColorChoices[k].DarkName := names[i];
    end;
    if first < 0 then first := k;
  end;
  CmbColors.ItemIndex := first;
  ColorsChange(CmbColors);
end;

{ ---- cursor ---- }

{ The terminal's own cursor: what it draws when the program does not ask. A program may ask
  for another shape with DECSCUSR (vim's insert mode asks for a bar); CSI 0 SP q, and a
  reset, go back to these. }
procedure TMainForm.CursorStyleChange(Sender: TObject);
begin
  if CmbCursor.ItemIndex >= 0 then
    Term.CursorStyle := TTyTerminalCursorStyle(CmbCursor.ItemIndex);
end;

procedure TMainForm.CursorBlinkClick(Sender: TObject);
begin
  Term.CursorBlink := ChkCursorBlink.Checked;
end;

procedure TMainForm.CursorInactiveChange(Sender: TObject);
begin
  if CmbCursorInactive.ItemIndex >= 0 then
    Term.CursorInactiveStyle := TTyTerminalCursorInactiveStyle(CmbCursorInactive.ItemIndex);
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
