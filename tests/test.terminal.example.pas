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
  tyControls.Terminal.Core, tyControls.Terminal, uasciicast, uptysession, ushell, test.terminal.view,
  test.terminal.pty;

type
  TTyTerminalExampleTests = class(TTestCase)
  private
    FChunks: TStringList;
    FTags: array of PtrInt;
    FDone: Integer;
    FPlayer: TAsciicastPlayer;
    procedure Collect(Sender: TObject; const AData: RawByteString; ATag: PtrInt);
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
  Units: array[0..3] of string = ('ushell.pas', 'uptysession.pas', 'uptywin.pas', 'uptyunix.pas');
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

initialization
  RegisterTest(TTyTerminalExampleTests);
end.
