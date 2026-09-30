unit test.terminal.example;
{$mode objfpc}{$H+}
{ The terminal example's reader and player (examples/terminal/uasciicast.pas, on the
  test project's unit path): a recording that fails to load leaves the one before it
  untouched; the grid in the header is clamped; idle_time_limit shortens the pauses;
  the player keeps one chunk in the terminal's queue at a time, ignores a callback from
  before a rewind, and so plays a recording far bigger than the queue's chunk limit
  "all at once" into a real TTyTerminalView without an overflow. }

interface

uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  Forms, FileUtil,
  tyControls.Types, tyControls.StyleModel, tyControls.Controller,
  tyControls.Terminal.Core, tyControls.Terminal, uasciicast, uptysession, ushell, umain, uwslresize,
  {$IFDEF MSWINDOWS}uptywin,{$ENDIF} test.terminal.view, test.terminal.pty, test.terminal.oracle;

type
  TTyTerminalExampleTests = class(TTestCase)
  private
    FChunks: TStringList;
    FTags: array of PtrInt;
    FDone: Integer;
    FPlayer: TAsciicastPlayer;
    FTermData: RawByteString;
    procedure Collect(Sender: TObject; const AData: RawByteString; ATag: PtrInt);
    procedure TermData(Sender: TObject; const AData: RawByteString);
    procedure ToView(Sender: TObject; const AData: RawByteString; ATag: PtrInt);
    procedure ViewDone(Sender: TObject; ATag: PtrInt);
    function Cast(const ALines: array of string): TStringList;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAFailedLoadKeepsTheRecordingBefore;
    procedure TestTheGridIsClamped;
    procedure TestIdleTimeLimitShortensPauses;
    procedure TestOneChunkInFlight;
    procedure TestACallbackFromBeforeARewindIsIgnored;
    procedure TestAllAtOnceIntoARealTerminal;
    procedure TestTheShellUnitsCompileInTheTests;
    procedure TestTheExampleProjectListsItsUnits;
    procedure TestTheMainFormBuildsWithARecording;
    { 6 期:配色 }
    procedure TestTheColourListOffersSevenAndThreePairs;
    procedure TestAPairThatDoesNotLoadChangesNothing;
    { 7 期:ZModem }
    procedure TestAZmodemDownloadInTheExample;               { X2 }
    procedure TestZmodemCanBeSwitchedOff;                    { X3 }
    procedure TestTheTransferBarIsThrottled;
    { 7 期验收反馈:管道模式的命令 }
    procedure TestPipeModeListsCommandsWithATerminalOfTheirOwn;
    procedure TestTheGridSizeGoesIntoAPipeCommand;
    procedure TestTheWslResizeCommands;
    procedure TestTheWslResizeQueue;
    procedure TestThePipeModeBackendResizesWsl;
  end;

implementation

var
  View: TTyTermViewFixture;

procedure TTyTerminalExampleTests.SetUp;
begin
  FChunks := TStringList.Create;
  FTags := nil;
  FDone := 0;
end;

procedure TTyTerminalExampleTests.TearDown;
begin
  FChunks.Free;
end;

procedure TTyTerminalExampleTests.Collect(Sender: TObject; const AData: RawByteString; ATag: PtrInt);
begin
  FChunks.Add(AData);
  SetLength(FTags, Length(FTags) + 1);
  FTags[High(FTags)] := ATag;
end;

procedure TTyTerminalExampleTests.ToView(Sender: TObject; const AData: RawByteString; ATag: PtrInt);
begin
  FChunks.Add(IntToStr(Length(AData)));
  View.View.Write(AData, @ViewDone, ATag);
end;

procedure TTyTerminalExampleTests.ViewDone(Sender: TObject; ATag: PtrInt);
begin
  Inc(FDone);
  FPlayer.ChunkDone(ATag);
end;

function TTyTerminalExampleTests.Cast(const ALines: array of string): TStringList;
var
  i: Integer;
begin
  Result := TStringList.Create;
  for i := 0 to High(ALines) do
    Result.Add(ALines[i]);
end;

procedure TTyTerminalExampleTests.TestAFailedLoadKeepsTheRecordingBefore;
var
  c: TAsciicast;
  good, bad: TStringList;
  raised: Boolean;
begin
  c := TAsciicast.Create;
  good := Cast(['{"version": 2, "width": 30, "height": 7}', '[0.5, "o", "one"]', '[1.0, "o", "two"]']);
  { a good header, then a broken line half-way through }
  bad := Cast(['{"version": 2, "width": 90, "height": 40}', '[0.1, "o", "x"]', '[0.2, "o", "y', '[0.3, "o", "z"]']);
  try
    c.LoadFromStrings(good, 'good.cast');
    AssertEquals('loaded', 2, c.Count);
    raised := False;
    try
      c.LoadFromStrings(bad, 'bad.cast');
    except
      on E: Exception do
      begin
        raised := True;
        AssertTrue('names the file: ' + E.Message, Pos('bad.cast', E.Message) > 0);
      end;
    end;
    AssertTrue('the broken file raised', raised);
    AssertEquals('the events before are kept', 2, c.Count);
    AssertEquals('their data', 'two', c[1].Data);
    AssertEquals('the width before', 30, c.Width);
    AssertEquals('the height before', 7, c.Height);
    AssertEquals('the file name before', 'good.cast', c.FileName);
  finally
    good.Free;
    bad.Free;
    c.Free;
  end;
end;

procedure TTyTerminalExampleTests.TestTheGridIsClamped;
var
  c: TAsciicast;
  l: TStringList;
begin
  c := TAsciicast.Create;
  l := Cast(['{"version": 2, "width": 100000, "height": -5}']);
  try
    c.LoadFromStrings(l, 'x.cast');
    AssertEquals('width', AsciicastMaxWidth, c.Width);
    AssertEquals('height', AsciicastMinHeight, c.Height);
  finally
    l.Free;
    c.Free;
  end;
end;

procedure TTyTerminalExampleTests.TestIdleTimeLimitShortensPauses;
var
  c: TAsciicast;
  l: TStringList;
begin
  c := TAsciicast.Create;
  l := Cast(['{"version": 2, "width": 20, "height": 5, "idle_time_limit": 2}',
    '[1.0, "o", "a"]', '[11.0, "o", "b"]', '[11.5, "i", "k"]', '[20.0, "o", "c"]']);
  try
    c.LoadFromStrings(l, 'x.cast');
    AssertEquals('three output events', 3, c.Count);
    AssertEquals('the first as recorded', 1.0, c[0].Time, 1e-9);
    AssertEquals('ten idle seconds play as two', 3.0, c[1].Time, 1e-9);
    { 11.5 (an input event: activity) to 20 is 8.5 idle seconds, played as 2 }
    AssertEquals('the shift carries on, the input event counts as activity', 5.5, c[2].Time, 1e-9);
    AssertEquals('the limit', 2.0, c.IdleTimeLimit, 1e-9);
  finally
    l.Free;
    c.Free;
  end;
end;

procedure TTyTerminalExampleTests.TestOneChunkInFlight;
var
  c: TAsciicast;
  l: TStringList;
  i: Integer;
begin
  c := TAsciicast.Create;
  l := TStringList.Create;
  FPlayer := TAsciicastPlayer.Create(c);
  try
    l.Add('{"version": 2, "width": 20, "height": 5}');
    for i := 1 to 50 do
      l.Add(Format('[%d.0, "o", "%s"]', [i, StringOfChar('x', 10)]));
    c.LoadFromStrings(l, 'x.cast');
    FPlayer.MaxChunkBytes := 100;
    FPlayer.OnWrite := @Collect;
    FPlayer.Rewind;
    FPlayer.Advance(0, -1);
    AssertEquals('all at once: one chunk out', 1, FChunks.Count);
    AssertEquals('cut at the chunk size', 100, Length(FChunks[0]));
    FPlayer.Advance(0, -1);
    FPlayer.Advance(0, -1);
    AssertEquals('nothing more until the terminal is done with it', 1, FChunks.Count);
    FPlayer.ChunkDone(FTags[0]);
    FPlayer.Advance(0, -1);
    AssertEquals('then the next', 2, FChunks.Count);
    { as recorded: the events that fall due while a chunk is in flight wait for it }
    FPlayer.Rewind;
    FChunks.Clear;
    FTags := nil;
    FPlayer.Advance(2500, 1);
    AssertEquals('two events due', 1, FChunks.Count);
    AssertEquals('both in the one chunk', 20, Length(FChunks[0]));
    FPlayer.Advance(2000, 1);
    AssertEquals('in flight: the two that fell due wait', 1, FChunks.Count);
    FPlayer.ChunkDone(FTags[0]);
    FPlayer.Advance(0, 1);
    AssertEquals('then they go together', 2, FChunks.Count);
    AssertEquals('both', 20, Length(FChunks[1]));
  finally
    FreeAndNil(FPlayer);
    l.Free;
    c.Free;
  end;
end;

procedure TTyTerminalExampleTests.TestACallbackFromBeforeARewindIsIgnored;
var
  c: TAsciicast;
  l: TStringList;
  old: PtrInt;
begin
  c := TAsciicast.Create;
  l := Cast(['{"version": 2, "width": 20, "height": 5}', '[0.1, "o", "a"]', '[0.2, "o", "b"]']);
  FPlayer := TAsciicastPlayer.Create(c);
  try
    c.LoadFromStrings(l, 'x.cast');
    FPlayer.OnWrite := @Collect;
    FPlayer.MaxChunkBytes := 1;
    FPlayer.Rewind;
    FPlayer.Advance(0, -1);
    old := FTags[0];
    FPlayer.Rewind;
    FPlayer.Advance(0, -1);
    AssertEquals('a rewind starts over at once', 2, FChunks.Count);
    FPlayer.ChunkDone(old);
    AssertTrue('the old chunk''s callback does not release the new one', FPlayer.InFlight);
    FPlayer.ChunkDone(FTags[1]);
    AssertFalse('its own does', FPlayer.InFlight);
  finally
    FreeAndNil(FPlayer);
    l.Free;
    c.Free;
  end;
end;

procedure TTyTerminalExampleTests.TestAllAtOnceIntoARealTerminal;
var
  c: TAsciicast;
  l: TStringList;
  i, k, guard: Integer;
  mb: string;
begin
  { 60 MB "all at once", more than the terminal's queue holds (50 MB): the timer ticks
    faster than the terminal parses (five ticks to a slice here), so a player that wrote
    on every tick would overflow the queue; this one keeps one chunk in it. The bytes
    are one long OSC payload, which the parser skips through quickly. }
  c := TAsciicast.Create;
  l := TStringList.Create;
  View := TTyTermViewFixture.Create;
  FPlayer := TAsciicastPlayer.Create(c);
  try
    View.SizeTo(40, 10);
    mb := StringOfChar('a', 1024 * 1024);
    l.Add('{"version": 2, "width": 40, "height": 10}');
    l.Add('[0.001, "o", "\u001b]7;"]');
    for i := 1 to 60 do
      l.Add('[0.002, "o", "' + mb + '"]');
    l.Add('[0.003, "o", "\u0007done"]');
    c.LoadFromStrings(l, 'big.cast');
    l.Clear;
    AssertEquals('events', 62, c.Count);
    FPlayer.OnWrite := @ToView;
    FPlayer.Rewind;
    guard := 0;
    repeat
      for k := 1 to 5 do
        FPlayer.Advance(15, -1);                     { the example's timer ticks }
      View.View.Core.ProcessPending;                 { a slice from the message loop }
      Inc(guard);
    until (FPlayer.Finished and not FPlayer.InFlight) or (guard > 100000);
    AssertTrue('played to the end', FPlayer.Finished and not FPlayer.InFlight);
    AssertEquals('every chunk came back', FChunks.Count, FDone);
    AssertEquals('nothing left queued', 0, View.View.Core.PendingBytes);
    AssertEquals('the text after the payload', 'done', View.RowText(0));
  finally
    FreeAndNil(FPlayer);
    FreeAndNil(View);
    l.Free;
    c.Free;
  end;
end;

{ the Shell mode's units are on the test project's path and build with it }
procedure TTyTerminalExampleTests.TestTheShellUnitsCompileInTheTests;
var
  fx: TTyTermViewFixture;
  sh: TTerminalShell;
  s: TPtySession;
begin
  fx := TTyTermViewFixture.Create;
  try
    sh := TTerminalShell.Create(fx.View, TFakePty.Create);
    try
      AssertTrue('a shell has a session', sh.Session <> nil);
      AssertFalse('not running before Start', sh.Running);
    finally
      sh.Free;
    end;
    s := TPtySession.Create(TFakePty.Create);
    s.Free;
  finally
    fx.Free;
  end;
  AssertTrue('the exit line takes the code', Pos('%d', rsShellExited) > 0);
end;

{ terminal_example.lpi lists the four PTY units (an example built by lazbuild only
  compiles what the project names or its units use) }
procedure TTyTerminalExampleTests.TestTheExampleProjectListsItsUnits;
const
  Units: array[0..7] of string = ('ushell.pas', 'uptysession.pas', 'uptywin.pas', 'uptyunix.pas',
    'uzmodem.pas', 'uzmodemsession.pas', 'uzmodemterm.pas', 'uwslresize.pas');
var
  l: TStringList;
  i: Integer;
begin
  l := TStringList.Create;
  try
    l.LoadFromFile(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'examples' + PathDelim + 'terminal'
      + PathDelim + 'terminal_example.lpi');
    for i := 0 to High(Units) do
      AssertTrue(Units[i] + ' is in the project', Pos('<Filename Value="' + Units[i] + '"/>', l.Text) > 0);
  finally
    l.Free;
  end;
end;

{ The example looks for colorschemes/ (and recordings/) beside its executable and then up
  to 8 folders above it (ExampleDir in umain, so that a build under lib/<target>/ finds the
  example's own folders). Here the executable is the test runner, and nothing guarantees
  what lies above it: a folder left by a run that crashed, or one somebody keeps above the
  checkout, would be picked up and change what the colour list offers. So the tests look
  first and name what they find, instead of assuming there is nothing and failing later on
  a count that means nothing; they then add their own folder beside the runner (where the
  example looks first) and remove it -- only it -- in a finally, and check it is gone.
  Answers the folders named ASub on that path, joined with '; ' ('' = none). }
function FoldersOnTheExamplePath(const ASub: string; ALevels: Integer = 8): string;
var
  dir: string;
  i: Integer;
begin
  Result := '';
  dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to ALevels do
  begin
    if DirectoryExists(dir + ASub) then
    begin
      if Result <> '' then Result := Result + '; ';
      Result := Result + dir + ASub;
    end;
    dir := ExtractFilePath(ExcludeTrailingPathDelimiter(dir));
    if dir = '' then Break;
  end;
end;

function CountOf(AItems: TStrings; const S: string): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to AItems.Count - 1 do
    if AItems[i] = S then Inc(Result);
end;

{ The example's own main form, built the way the program builds it, with a recording
  where RecordingsDir looks (next to the executable). FormCreate selects the first
  recording, which fires RecordingChange while the form is not showing yet; a SetFocus
  there raised "Can not focus", FormCreate stopped half way, and the shell command list
  stayed empty -- so Shell could never start and the mode fell back to Replay. }
procedure TTyTerminalExampleTests.TestTheMainFormBuildsWithARecording;
var
  dir, src: string;
  f: TMainForm;
begin
  dir := ExtractFilePath(ExpandFileName(ParamStr(0))) + 'recordings' + PathDelim;
  src := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'examples' + PathDelim + 'terminal'
    + PathDelim + 'recordings' + PathDelim + 'cat-cjk-emoji.cast';
  AssertEquals('no recordings folder beside the test runner beforehand', '',
    FoldersOnTheExamplePath('recordings', 1));
  { the colour list below counts on no scheme file anywhere the example looks }
  AssertEquals('no colorschemes folder where the example looks (the runner and 8 above)', '',
    FoldersOnTheExamplePath('colorschemes'));
  AssertTrue('made the recordings folder', ForceDirectories(dir));
  try
    AssertTrue('copied a recording', CopyFile(src, dir + 'cat-cjk-emoji.cast'));
    f := TMainForm.Create(nil);
    try
      AssertEquals('the first recording is selected', 0, f.CmbRecording.ItemIndex);
      AssertTrue('FormCreate ran to the end: the shell commands are listed',
        f.CmbCommand.Items.Count > 0);
      AssertEquals('both modes are offered', 2, f.CmbMode.Items.Count);
      { 7 期 (X1): the transfer bar waits hidden, ZModem is on, Pipe is offered on Windows
        only, the transfer timer runs with a shell only }
      AssertFalse('the transfer bar is hidden', f.Tools6.Visible);
      AssertTrue('ZModem on', f.ChkZmodem.Checked);
      AssertFalse('Pipe off', f.ChkPipe.Checked);
      {$IFDEF MSWINDOWS}
      AssertTrue('Pipe offered on Windows', f.ChkPipe.Visible);
      {$ELSE}
      AssertFalse('no Pipe elsewhere', f.ChkPipe.Visible);
      {$ENDIF}
      AssertFalse('no transfer timer without a shell', f.ZmTimer.Enabled);
      { no colorschemes/ beside the test runner or above it: only "Follow theme", and
        "Import..." still works }
      AssertEquals('no scheme file: the colour list has one entry', 1, f.CmbColors.Items.Count);
      AssertEquals('and it is "Follow theme"', 'Follow theme', f.CmbColors.Items[0]);
      AssertEquals('picked', 0, f.CmbColors.ItemIndex);
      AssertEquals('and no error about a scheme file that is not there', 0,
        Pos('Could not import', f.Status.Panels[0].Text));
      f.ImportColorsFrom(TyTermFixturePath('terminal-wt-defaults.json'));
      AssertEquals('importing Windows Terminal''s defaults.json adds its 16', 17, f.CmbColors.Items.Count);
      AssertEquals('and picks the first', 1, f.CmbColors.ItemIndex);
      AssertTrue('the terminal took it', f.Term.ColorSource = tsrcScheme);
      AssertEquals('Dimidium', 'Dimidium', f.Term.ColorScheme.Name);
      f.ImportColorsFrom(TyTermFixturePath('terminal-wt-defaults.json'));
      AssertEquals('importing it again adds nothing', 17, f.CmbColors.Items.Count);
      AssertEquals('Dimidium is there once', 1, CountOf(f.CmbColors.Items, 'Dimidium'));
      { the cursor settings: FormCreate filled them from the terminal, and they set it }
      AssertEquals('three cursor shapes', 3, f.CmbCursor.Items.Count);
      AssertEquals('the terminal''s shape is picked', Ord(f.Term.CursorStyle), f.CmbCursor.ItemIndex);
      AssertEquals('five unfocused cursors', 5, f.CmbCursorInactive.Items.Count);
      AssertEquals('the terminal''s unfocused cursor is picked', Ord(f.Term.CursorInactiveStyle),
        f.CmbCursorInactive.ItemIndex);
      AssertEquals('blink as the terminal has it', f.Term.CursorBlink, f.ChkCursorBlink.Checked);
      AssertEquals('the shapes are words, in order', 'Bar', f.CmbCursor.Items[2]);
      f.CmbCursor.ItemIndex := 2;
      f.CursorStyleChange(f.CmbCursor);
      AssertTrue('Bar sets the terminal''s shape', f.Term.CursorStyle = tcsBar);
      f.CmbCursor.ItemIndex := 1;
      f.CursorStyleChange(f.CmbCursor);
      AssertTrue('Underline', f.Term.CursorStyle = tcsUnderline);
      f.ChkCursorBlink.Checked := not f.Term.CursorBlink;
      f.CursorBlinkClick(f.ChkCursorBlink);
      AssertEquals('Blink sets blinking', f.ChkCursorBlink.Checked, f.Term.CursorBlink);
      f.CmbCursorInactive.ItemIndex := 4;
      f.CursorInactiveChange(f.CmbCursorInactive);
      AssertTrue('None', f.Term.CursorInactiveStyle = tcisNone);
      f.CmbCursorInactive.ItemIndex := 3;
      f.CursorInactiveChange(f.CmbCursorInactive);
      AssertTrue('Underline, unfocused', f.Term.CursorInactiveStyle = tcisUnderline);
    finally
      f.Free;
    end;
  finally
    DeleteDirectory(dir, False);
    AssertFalse('the recordings folder the test made is gone', DirectoryExists(dir));
  end;
end;

procedure TTyTerminalExampleTests.TermData(Sender: TObject; const AData: RawByteString);
begin
  FTermData := FTermData + AData;
end;

function Reports(const AData: RawByteString): Integer;
var
  s: RawByteString;
  p: Integer;
begin
  Result := 0;
  s := AData;
  p := Pos(#27'[?997;', s);
  while p > 0 do
  begin
    Inc(Result);
    Delete(s, 1, p + 5);
    p := Pos(#27'[?997;', s);
  end;
end;

procedure PumpMessages;
var
  i: Integer;
begin
  for i := 1 to 5 do
    Application.ProcessMessages;
end;

{ The example's colour list, from its own colorschemes/windows-terminal.json put where
  the example looks (beside the executable): Follow theme, the seven, the three pairs.
  Picking one sets the terminal's colours; a pair follows the dark-mode switch; each pick
  is one 2031 report; a file that does not import changes nothing. }
procedure TTyTerminalExampleTests.TestTheColourListOffersSevenAndThreePairs;
const
  Want: array[0..10] of string = ('Follow theme', 'Campbell', 'One Half Dark', 'One Half Light',
    'Solarized Dark', 'Solarized Light', 'Tango Dark', 'Tango Light',
    'One Half (light / dark)', 'Solarized (light / dark)', 'Tango (light / dark)');
var
  dir, src, bad: string;
  f: TMainForm;
  i: Integer;
  oldMode: string;
  st: TTyStyleSet;
  sl: TStringList;
  before: Cardinal;

  procedure Pick(const AName: string);
  begin
    f.CmbColors.ItemIndex := f.CmbColors.Items.IndexOf(AName);
    AssertTrue('listed: ' + AName, f.CmbColors.ItemIndex >= 0);
    f.ColorsChange(f.CmbColors);
  end;

  procedure Dark(AOn: Boolean);
  begin
    f.DarkSwitch.Checked := AOn;
    f.DarkSwitchChange(f.DarkSwitch);
  end;

begin
  TyTermNeedWidgetSet;
  dir := ExtractFilePath(ExpandFileName(ParamStr(0))) + 'colorschemes' + PathDelim;
  src := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'examples' + PathDelim + 'terminal'
    + PathDelim + 'colorschemes' + PathDelim + 'windows-terminal.json';
  { the example takes the first colorschemes/ it finds, beside the runner before any above:
    only that one has to be absent }
  AssertEquals('no colorschemes folder beside the test runner beforehand', '',
    FoldersOnTheExamplePath('colorschemes', 1));
  oldMode := TyDefaultController.Mode;
  AssertTrue('made the colorschemes folder', ForceDirectories(dir));
  try
    AssertTrue('copied the scheme file', CopyFile(src, dir + 'windows-terminal.json'));
    f := TMainForm.Create(nil);
    try
      AssertEquals('Follow theme, seven schemes, three pairs', Length(Want), f.CmbColors.Items.Count);
      for i := 0 to High(Want) do
        AssertEquals('entry ' + IntToStr(i), Want[i], f.CmbColors.Items[i]);
      Dark(False);
      f.Term.ReadOnly := False;
      f.Term.OnData := @TermData;
      f.Term.WriteSync(#27'[?2031h');
      PumpMessages;
      FTermData := '';
      Pick('Solarized Dark');
      AssertTrue('a scheme', f.Term.ColorSource = tsrcScheme);
      AssertFalse('not paired', f.Term.ColorSchemePaired);
      AssertEquals('Solarized Dark''s ground', IntToHex($002B36, 6), IntToHex(f.Term.Core.ResolveColor(257), 6));
      PumpMessages;
      AssertEquals('theme -> a scheme: one report', 1, Reports(FTermData));
      FTermData := '';
      Pick('Tango (light / dark)');
      AssertTrue('paired', f.Term.ColorSchemePaired);
      AssertEquals('the light one', 'Tango Light', f.Term.ColorScheme.Name);
      AssertEquals('the dark one', 'Tango Dark', f.Term.DarkColorScheme.Name);
      AssertEquals('light mode: Tango Light''s ground', IntToHex($FFFFFF, 6), IntToHex(f.Term.Core.ResolveColor(257), 6));
      PumpMessages;
      AssertEquals('a scheme -> a pair: one report', 1, Reports(FTermData));
      Dark(True);
      AssertEquals('dark mode: Tango Dark''s ground', IntToHex($000000, 6), IntToHex(f.Term.Core.ResolveColor(257), 6));
      Dark(False);
      AssertEquals('light again: Tango Light''s ground', IntToHex($FFFFFF, 6), IntToHex(f.Term.Core.ResolveColor(257), 6));
      Pick('Follow theme');
      AssertTrue('the theme again', f.Term.ColorSource = tsrcTheme);
      st := TyDefaultController.Model.ResolveStyle('TyTerminal', '', []);
      AssertEquals('the theme''s ground', IntToHex(Cardinal(st.Background.Color) and $FFFFFF, 6),
        IntToHex(f.Term.Core.ResolveColor(257), 6));
      { a file that imports nothing: the list, the colours stay; the status bar says why }
      Pick('Campbell');
      before := f.Term.Core.ResolveColor(257);
      bad := GetTempDir(False) + 'tyterm-example-bad-scheme.json';
      sl := TStringList.Create;
      try
        sl.Text := '{"name": "Broken", "black": "#000000"}';
        sl.SaveToFile(bad);
      finally
        sl.Free;
      end;
      try
        f.ImportColorsFrom(bad);
      finally
        DeleteFile(bad);
      end;
      AssertEquals('nothing added', Length(Want), f.CmbColors.Items.Count);
      AssertTrue('the status bar says so: ' + f.Status.Panels[0].Text,
        Pos('Could not import', f.Status.Panels[0].Text) > 0);
      AssertEquals('the colours are as they were', IntToHex(before, 6), IntToHex(f.Term.Core.ResolveColor(257), 6));
      { the next pick that works takes the error away }
      Pick('Solarized Light');
      AssertEquals('a pick that works clears the error: ' + f.Status.Panels[0].Text, 0,
        Pos('Could not import', f.Status.Panels[0].Text));
      { Windows Terminal's defaults.json: its 16 names, the seven already listed once each }
      f.ImportColorsFrom(TyTermFixturePath('terminal-wt-defaults.json'));
      AssertEquals('the nine new ones join', Length(Want) + 9, f.CmbColors.Items.Count);
      for i := 1 to 7 do
        AssertEquals(Want[i] + ' once', 1, CountOf(f.CmbColors.Items, Want[i]));
      AssertEquals('picks its first', 'Dimidium', f.CmbColors.Items[f.CmbColors.ItemIndex]);
      f.ImportColorsFrom(TyTermFixturePath('terminal-wt-defaults.json'));
      AssertEquals('again: nothing new', Length(Want) + 9, f.CmbColors.Items.Count);
      Pick('Campbell');
      AssertEquals('Campbell still loads', 'Campbell', f.Term.ColorScheme.Name);
    finally
      f.Free;
    end;
  finally
    TyDefaultController.Mode := oldMode;
    DeleteDirectory(dir, False);
    AssertFalse('the colorschemes folder the test made is gone', DirectoryExists(dir));
  end;
end;

{ A pair is two schemes: when the second does not load, nothing is set -- not even the first
  one, which would otherwise change the terminal's ColorScheme behind a status bar error. }
procedure TTyTerminalExampleTests.TestAPairThatDoesNotLoadChangesNothing;
const
  Keys: array[0..15] of string = ('black', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'white',
    'brightBlack', 'brightRed', 'brightGreen', 'brightYellow', 'brightBlue', 'brightPurple', 'brightCyan',
    'brightWhite');
var
  dir: string;
  f: TMainForm;
  sl: TStringList;
  i: Integer;
  colours, bad: string;
begin
  TyTermNeedWidgetSet;
  dir := ExtractFilePath(ExpandFileName(ParamStr(0))) + 'colorschemes' + PathDelim;
  AssertEquals('no colorschemes folder beside the test runner beforehand', '',
    FoldersOnTheExamplePath('colorschemes', 1));
  colours := '';
  bad := '';
  for i := 0 to 15 do
  begin
    colours := colours + ', "' + Keys[i] + '": "#' + IntToHex(i * 16 + 1, 6) + '"';
    if i = 1 then
      bad := bad + ', "red": "not a colour"'
    else
      bad := bad + ', "' + Keys[i] + '": "#' + IntToHex(i * 16 + 2, 6) + '"';
  end;
  AssertTrue('made the colorschemes folder', ForceDirectories(dir));
  try
    sl := TStringList.Create;
    try
      sl.Text := '{"schemes": [{"name": "Tango Light", "background": "#FFFFFF"' + colours
        + '}, {"name": "Tango Dark", "background": "#000000"' + bad + '}]}';
      sl.SaveToFile(dir + 'windows-terminal.json');
    finally
      sl.Free;
    end;
    f := TMainForm.Create(nil);
    try
      AssertTrue('the pair is offered (both names are there)',
        f.CmbColors.Items.IndexOf('Tango (light / dark)') >= 0);
      AssertTrue('following the theme', f.Term.ColorSource = tsrcTheme);
      f.CmbColors.ItemIndex := f.CmbColors.Items.IndexOf('Tango (light / dark)');
      f.ColorsChange(f.CmbColors);
      AssertTrue('the status bar says why: ' + f.Status.Panels[0].Text,
        Pos('Could not import', f.Status.Panels[0].Text) > 0);
      AssertTrue('the light half was not set either', f.Term.ColorScheme.IsEmpty);
      AssertEquals('nor its name', '', f.Term.ColorScheme.Name);
      AssertTrue('the dark one is untouched', f.Term.DarkColorScheme.IsEmpty);
      AssertFalse('not paired', f.Term.ColorSchemePaired);
      AssertTrue('still following the theme', f.Term.ColorSource = tsrcTheme);
      { the light one alone loads, and takes the error away }
      f.CmbColors.ItemIndex := f.CmbColors.Items.IndexOf('Tango Light');
      f.ColorsChange(f.CmbColors);
      AssertEquals('Tango Light alone', 'Tango Light', f.Term.ColorScheme.Name);
      AssertEquals('the error is gone', 0, Pos('Could not import', f.Status.Panels[0].Text));
    finally
      f.Free;
    end;
  finally
    DeleteDirectory(dir, False);
    AssertFalse('the colorschemes folder the test made is gone', DirectoryExists(dir));
  end;
end;

{ ---- 7 期: ZModem in the example ---------------------------------------------------------- }

function ZmFixtureBytes(const AName: string): RawByteString;
var
  fs: TFileStream;
begin
  fs := TFileStream.Create(TyTermFixturePath('terminal-zmodem' + PathDelim + AName), fmOpenRead or fmShareDenyWrite);
  try
    Result := '';
    SetLength(Result, fs.Size);
    if fs.Size > 0 then
      fs.ReadBuffer(Result[1], fs.Size);
  finally
    fs.Free;
  end;
end;

{ the example's main form in shell mode on a fake PTY whose output is lrzsz's sz
  recording; the download folder answered by the test seam (no dialog) }
function ShellOnAFake(out AFake: TFakePty): TMainForm;
begin
  AFake := TFakePty.Create;
  TMainForm.ShellBackendForTest := AFake;
  Result := TMainForm.Create(nil);
  { the combo's OnChange starts the shell (and takes the fake); a second ModeChange
    would start another one on a real backend and free the fake with the first }
  Result.CmbMode.ItemIndex := 1;
  if TMainForm.ShellBackendForTest <> nil then
    Result.ModeChange(Result.CmbMode);
end;

{ X2. Mutation: the form not wiring OnDownloadRequest. }
procedure TTyTerminalExampleTests.TestAZmodemDownloadInTheExample;
var
  f: TMainForm;
  fake: TFakePty;
  dir: string;
  t0: QWord;
  got: RawByteString;
begin
  dir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'tyzm-example-' + IntToStr(GetTickCount64);
  AssertTrue(ForceDirectories(dir));
  TMainForm.ZmodemAnswerForTest := dir;
  f := nil;
  try
    f := ShellOnAFake(fake);
    AssertTrue('a shell with ZModem', f.ZmTimer.Enabled);
    fake.Feed(ZmFixtureBytes('one-small.sz.bin'));
    t0 := GetTickCount64;
    while not FileExists(dir + PathDelim + 'one-small.bin') or f.Term.StreamClaimed do
    begin
      Application.ProcessMessages;
      Sleep(5);
      if GetTickCount64 - t0 > 10000 then
        Fail('no download within 10 s; status: ' + f.Status.Panels[0].Text);
    end;
    PumpMessages;
    got := '';
    with TFileStream.Create(dir + PathDelim + 'one-small.bin', fmOpenRead or fmShareDenyWrite) do
    try
      SetLength(got, Size);
      if Size > 0 then ReadBuffer(got[1], Size);
    finally
      Free;
    end;
    AssertTrue('the file, byte for byte', got = ZmFixtureBytes('one-small.1.src'));
    AssertFalse('the transfer bar went again', f.Tools6.Visible);
    AssertTrue('the summary in the status bar: ' + f.Status.Panels[0].Text,
      Pos('Received 1 file(s)', f.Status.Panels[0].Text) > 0);
    AssertTrue('the answers went to the program', Length(fake.Written) > 0);
  finally
    TMainForm.ZmodemAnswerForTest := '';
    f.Free;
    DeleteDirectory(dir, False);
  end;
end;

function ScreenOf(ATerm: TTyTerminalView): string;
var
  y: Integer;
begin
  Result := '';
  for y := 0 to ATerm.Core.Buffer.Lines.Length - 1 do
    Result := Result + ATerm.Core.Buffer.TranslateBufferLineToString(y, True) + #10;
end;

{ X3. Mutation: ChkZmodem's OnChange not wired. }
procedure TTyTerminalExampleTests.TestZmodemCanBeSwitchedOff;
var
  f: TMainForm;
  fake: TFakePty;
  dir: string;
  t0: QWord;
begin
  dir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'tyzm-example-off-' + IntToStr(GetTickCount64);
  AssertTrue(ForceDirectories(dir));
  TMainForm.ZmodemAnswerForTest := dir;
  f := nil;
  try
    f := ShellOnAFake(fake);
    f.ChkZmodem.Checked := False;
    fake.Feed(ZmFixtureBytes('one-small.sz.bin'));
    t0 := GetTickCount64;
    { sz's bytes as text: the file information block ('one-small.bin', its size) is
      printed like any output -- a claimed stream would never show it }
    while Pos('one-small.bin', ScreenOf(f.Term)) = 0 do
    begin
      Application.ProcessMessages;
      Sleep(5);
      if GetTickCount64 - t0 > 10000 then
        Fail('the output did not arrive within 10 s: ' + ScreenOf(f.Term));
    end;
    PumpMessages;
    AssertFalse('not claimed', f.Term.StreamClaimed);
    AssertFalse('no file', FileExists(dir + PathDelim + 'one-small.bin'));
    AssertEquals('no ZRINIT went back', 0, Pos('**'#$18'B01', fake.Written));
  finally
    TMainForm.ZmodemAnswerForTest := '';
    f.Free;
    DeleteDirectory(dir, False);
  end;
end;

type
  TFrozenClock = class
  public
    function Now_: Double;
  end;

function TFrozenClock.Now_: Double;
begin
  Result := 1000;
end;

{ The transfer bar follows the progress events (one a KB) at most every 150 ms -- with
  the clock frozen: the first one and the file's end only, so the bar ends full and
  named. Mutation: every event shown (about twenty for a 20 KB file). }
procedure TTyTerminalExampleTests.TestTheTransferBarIsThrottled;
var
  f: TMainForm;
  fake: TFakePty;
  dir: string;
  t0: QWord;
  clk: TFrozenClock;
begin
  dir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'tyzm-example-bar-' + IntToStr(GetTickCount64);
  AssertTrue(ForceDirectories(dir));
  TMainForm.ZmodemAnswerForTest := dir;
  clk := TFrozenClock.Create;
  TMainForm.ZmClockForTest := @clk.Now_;
  f := nil;
  try
    f := ShellOnAFake(fake);
    fake.Feed(ZmFixtureBytes('window.sz.bin'));
    t0 := GetTickCount64;
    while not FileExists(dir + PathDelim + 'window.bin') or f.Term.StreamClaimed do
    begin
      Application.ProcessMessages;
      Sleep(5);
      if GetTickCount64 - t0 > 10000 then
        Fail('no download within 10 s; status: ' + f.Status.Panels[0].Text);
    end;
    PumpMessages;
    AssertTrue('some progress', f.ZmProgressShown > 0);
    AssertEquals('the first and the end only', 2, f.ZmProgressShown);
    AssertEquals('the bar ended full', 1000, f.BarTransfer.Position);
    AssertEquals('and named', 'window.bin', f.LblTransfer.Caption);
  finally
    TMainForm.ZmodemAnswerForTest := '';
    TMainForm.ZmClockForTest := nil;
    f.Free;
    clk.Free;
    DeleteDirectory(dir, False);
  end;
end;

{ ---- 7 期验收反馈: the commands of the pipe mode ---------------------------------------- }

{ A plain pipe has no line discipline: nobody turns the terminal's CR into LF, echoes, turns
  LF into CR LF or tells the program the window's size -- cmd waits for an LF that never
  comes, PowerShell lays out 120 columns, bash on a pipe is not interactive. So with "Pipe"
  ticked the list offers commands that open a terminal on the far side: WSL through
  script (a PTY in Linux, the size set by stty), and ssh -tt; cmd / PowerShell are not
  listed. Unticked, the ConPTY list is back. Mutations: PipeChange not refilling the list;
  FillCommands ignoring the tick. }
procedure TTyTerminalExampleTests.TestPipeModeListsCommandsWithATerminalOfTheirOwn;
{$IFDEF MSWINDOWS}
var
  f: TMainForm;
  shell: string;
  hasWsl: Boolean;
begin
  hasWsl := FileSearch('wsl.exe', GetEnvironmentVariable('PATH')) <> '';
  AssertEquals('the WSL entry of the pipe mode',
    'wsl.exe -e script -qfc "stty cols %COLS% rows %ROWS%; echo $$ $(tty) > %TTYFILE%; exec $SHELL -il" /dev/null',
    PipeWslCommand);
  AssertEquals('the ssh entry asks the far side for a terminal', 'ssh -tt user@host', PipeSshCommand);
  f := TMainForm.Create(nil);
  try
    AssertFalse('Pipe off at start', f.ChkPipe.Checked);
    shell := f.CmbCommand.Items[0];
    AssertTrue('ConPTY: %COMSPEC% first: ' + shell, Pos('cmd', LowerCase(shell)) > 0);
    AssertTrue('ConPTY: PowerShell listed', f.CmbCommand.Items.IndexOf('powershell.exe') >= 0);
    AssertEquals('ConPTY: no pipe entry', -1, f.CmbCommand.Items.IndexOf(PipeSshCommand));
    f.ChkPipe.Checked := True;
    AssertEquals('Pipe: no cmd', -1, f.CmbCommand.Items.IndexOf(shell));
    AssertEquals('Pipe: no PowerShell', -1, f.CmbCommand.Items.IndexOf('powershell.exe'));
    AssertEquals('Pipe: no pwsh', -1, f.CmbCommand.Items.IndexOf('pwsh.exe'));
    AssertEquals('Pipe: no bare wsl.exe', -1, f.CmbCommand.Items.IndexOf('wsl.exe'));
    AssertTrue('Pipe: ssh -tt listed', f.CmbCommand.Items.IndexOf(PipeSshCommand) >= 0);
    if hasWsl then
    begin
      AssertEquals('Pipe: WSL through script, first', PipeWslCommand, f.CmbCommand.Items[0]);
      AssertEquals('Pipe: two entries', 2, f.CmbCommand.Items.Count);
    end
    else
    begin
      AssertEquals('Pipe, no wsl.exe: ssh only', 1, f.CmbCommand.Items.Count);
      AssertEquals('no WSL entry without wsl.exe', -1, f.CmbCommand.Items.IndexOf(PipeWslCommand));
    end;
    AssertEquals('the first one is picked', f.CmbCommand.Items[0], f.CmbCommand.Text);
    f.ChkPipe.Checked := False;
    AssertEquals('unticked: %COMSPEC% first again', shell, f.CmbCommand.Items[0]);
    AssertEquals('and picked', shell, f.CmbCommand.Text);
    AssertTrue('unticked: PowerShell again', f.CmbCommand.Items.IndexOf('powershell.exe') >= 0);
    AssertEquals('unticked: no pipe entry', -1, f.CmbCommand.Items.IndexOf(PipeSshCommand));
    AssertEquals('unticked: no script entry', -1, f.CmbCommand.Items.IndexOf(PipeWslCommand));
  finally
    f.Free;
  end;
end;
{$ELSE}
begin
  Ignore('the pipe mode is Windows only');
end;
{$ENDIF}

{ %COLS% / %ROWS% in the command become the terminal's grid when the shell starts in pipe
  mode -- the only time the size can reach the far side (stty in the WSL entry): a pipe
  carries no resize. Mutation: StartShell handing the command over as typed. }
procedure TTyTerminalExampleTests.TestTheGridSizeGoesIntoAPipeCommand;
{$IFDEF MSWINDOWS}
var
  f: TMainForm;
  fake: TFakePty;
{$ENDIF}
begin
  AssertEquals('both, every time', 'a 97 b 31 c 97x31', ExpandGridSize('a %COLS% b %ROWS% c %COLS%x%ROWS%', 97, 31));
  AssertEquals('none: as it is', 'ssh -tt user@host', ExpandGridSize('ssh -tt user@host', 97, 31));
  AssertEquals('the WSL entry (the file is the backend''s)',
    'wsl.exe -e script -qfc "stty cols 120 rows 40; echo $$ $(tty) > %TTYFILE%; exec $SHELL -il" /dev/null',
    ExpandGridSize(PipeWslCommand, 120, 40));
  {$IFDEF MSWINDOWS}
  fake := TFakePty.Create;
  TMainForm.ShellBackendForTest := fake;
  f := TMainForm.Create(nil);
  try
    f.ChkPipe.Checked := True;
    f.CmbCommand.Text := 'probe %COLS%x%ROWS%';
    f.CmbMode.ItemIndex := 1;
    if TMainForm.ShellBackendForTest <> nil then
      f.ModeChange(f.CmbMode);
    AssertTrue('a grid', (f.Term.Cols > 0) and (f.Term.Rows > 0));
    AssertEquals('the shell got the grid', Format('probe %dx%d', [f.Term.Cols, f.Term.Rows]), fake.Command);
  finally
    { not taken (the shell never started): the test's to free }
    FreeAndNil(TMainForm.ShellBackendForTest);
    f.Free;
  end;
  {$ENDIF}
end;

{ The pipe mode's side channel for WSL's size (uwslresize): which commands have it (the WSL
  entry: wsl.exe and %TTYFILE%; the same distribution and user), the file the wrapper
  writes, the side process that sets the PTY's size -- only while the shell that wrote the
  file still has that terminal as its input -- and the one that removes the file. }
procedure TTyTerminalExampleTests.TestTheWslResizeCommands;
var
  exe, opts: string;
begin
  AssertEquals('the file', '/tmp/tyterm-1234-5.tty', WslTtyFileName(1234, 5));
  AssertTrue('the WSL entry', WslResizeTarget(ExpandGridSize(PipeWslCommand, 80, 24), exe, opts));
  AssertEquals('its wsl.exe', 'wsl.exe', exe);
  AssertEquals('no options: the default distribution', '', opts);
  AssertTrue('a distribution, a user; --cd is not for the side process',
    WslResizeTarget('C:\Windows\System32\WSL.EXE -d Ubuntu --cd "C:\a b" --user root -e script -qfc "tty > %TTYFILE%" /dev/null',
      exe, opts));
  AssertEquals('the program as given', 'C:\Windows\System32\WSL.EXE', exe);
  AssertEquals('-d and --user kept', ' -d Ubuntu --user root', opts);
  AssertTrue('a quoted distribution name', WslResizeTarget('wsl --distribution "My Distro" -- script %TTYFILE%', exe, opts));
  AssertEquals('quoted again', ' --distribution "My Distro"', opts);
  AssertFalse('wsl.exe without %TTYFILE%: no side channel', WslResizeTarget('wsl.exe -e bash -il', exe, opts));
  AssertFalse('ssh: no side channel (no window-change message on a pipe)',
    WslResizeTarget('ssh -tt user@host %TTYFILE%', exe, opts));
  AssertFalse('an options-only look-alike', WslResizeTarget('notwsl.exe %TTYFILE%', exe, opts));
  AssertEquals('the side process',
    'wsl.exe -d Ubuntu -e sh -c "read p t < /tmp/tyterm-1-2.tty && [ $(readlink /proc/$p/fd/0) = $t ] && stty -F $t cols 77 rows 20"',
    WslResizeCommand('wsl.exe', ' -d Ubuntu', '/tmp/tyterm-1-2.tty', 77, 20));
  AssertEquals('the cleanup', 'wsl.exe -d Ubuntu -e rm -f /tmp/tyterm-1-2.tty',
    WslCleanupCommand('wsl.exe', ' -d Ubuntu', '/tmp/tyterm-1-2.tty'));
end;

{ The side process takes about half a second: sizes are sent 250 ms after the last change,
  one process at a time, the latest after it; a failure is tried again twice, a second
  apart; after Stop nothing. Mutations: sending at once (no debounce); a second process
  while one runs; the failure dropped (no retry). }
procedure TTyTerminalExampleTests.TestTheWslResizeQueue;
var
  q: TWslResizeQueue;
  c, r: Integer;
begin
  q := TWslResizeQueue.Create(100, 30);
  try
    AssertFalse('nothing at the start', q.Next(1000, c, r));
    q.SizeChanged(90, 30, 1000);
    q.SizeChanged(80, 25, 1100);
    AssertFalse('100 ms after the last change: not yet', q.Next(1200, c, r));
    AssertFalse('249 ms: not yet', q.Next(1349, c, r));
    AssertTrue('250 ms: the last size', q.Next(1350, c, r));
    AssertEquals(80, c);
    AssertEquals(25, r);
    AssertTrue('in flight', q.Busy);
    q.SizeChanged(70, 20, 1400);
    AssertFalse('one at a time', q.Next(2000, c, r));
    q.Done(True, 2000);
    AssertTrue('then the latest', q.Next(2000, c, r));
    AssertEquals(70, c);
    AssertEquals(20, r);
    q.Done(True, 2400);
    AssertFalse('sent: nothing more', q.Next(5000, c, r));
    { back to what was sent before it went: nothing to send }
    q.SizeChanged(71, 20, 6000);
    q.SizeChanged(70, 20, 6100);
    AssertFalse('the size it has', q.Next(7000, c, r));
    { a failure: again a second later, three tries in all }
    q.SizeChanged(60, 15, 8000);
    AssertTrue(q.Next(8250, c, r));
    q.Done(False, 8700);
    AssertFalse('not at once after a failure', q.Next(8800, c, r));
    AssertTrue('a second later', q.Next(9700, c, r));
    AssertEquals(60, c);
    q.Done(False, 10100);
    AssertTrue('the third try', q.Next(11100, c, r));
    q.Done(False, 11500);
    AssertFalse('three failures: given up', q.Next(20000, c, r));
    AssertTrue(q.GaveUp);
    q.SizeChanged(61, 15, 21000);
    AssertFalse('a new size tries again', q.GaveUp);
    AssertTrue(q.Next(21250, c, r));
    q.Done(True, 21700);
    q.SizeChanged(50, 10, 22000);
    q.Stop;
    AssertFalse('stopped: nothing', q.Next(30000, c, r));
    q.SizeChanged(40, 10, 30000);
    AssertFalse('stopped: a change is not taken', q.Next(40000, c, r));
  finally
    q.Free;
  end;
end;

{ Pipe mode starts its commands on the backend that has the side channel (ConPTY and
  Unix keep theirs). Mutation: StartShell making a plain TProcessPipeBackend. }
procedure TTyTerminalExampleTests.TestThePipeModeBackendResizesWsl;
var
  b: TPtyBackend;
begin
  {$IFDEF MSWINDOWS}
  b := NewShellBackend(True);
  try
    AssertTrue('pipe: ' + b.ClassName, b is TWslPipeBackend);
  finally
    b.Free;
  end;
  b := NewShellBackend(False);
  try
    AssertTrue('ConPTY: ' + b.ClassName, b is TConPtyBackend);
  finally
    b.Free;
  end;
  {$ELSE}
  b := NewShellBackend(True);
  try
    AssertEquals('elsewhere the PTY', 'TUnixPtyBackend', b.ClassName);
  finally
    b.Free;
  end;
  {$ENDIF}
end;

initialization
  RegisterTest(TTyTerminalExampleTests);
end.
