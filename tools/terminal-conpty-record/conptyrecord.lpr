program conptyrecord;

{ Records one program's output through the terminal example's ConPTY session
  (examples/terminal/uptysession + uptywin) for the oracle: Windows only, no LCL.

    conptyrecord OUT.raw COLS ROWS COMMAND...
    conptyrecord OUT.raw COLS ROWS @FILE      (the command line in FILE, UTF-8)

  Each block the session's reader hands over becomes one line "SECONDS BASE64" in
  OUT.raw (seconds from the start, six decimals; the bytes as ConPTY sent them).
  tools/terminal-oracle/conpty-cast.py turns that into asciicast v2 the way
  wsl-record-pipe.py writes it, and refuses anything that names this machine. The
  recording ends when the program does (at most 20 s).

  Built by hand, like tools/terminal-ptytest:

    cd tools/terminal-conpty-record && mkdir -p lib && \
      fpc -Mobjfpc -Sh -FUlib -Fu../../examples/terminal conptyrecord.lpr }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, SyncObjs, base64, uptysession, uptywin;

type
  TWaker = class
  public
    Event: TEvent;
    constructor Create;
    destructor Destroy; override;
    procedure Wake(Sender: TObject);
  end;

constructor TWaker.Create;
begin
  inherited Create;
  Event := TEvent.Create(nil, False, False, '');
end;

destructor TWaker.Destroy;
begin
  Event.Free;
  inherited Destroy;
end;

procedure TWaker.Wake(Sender: TObject);
begin
  Event.SetEvent;
end;

var
  waker: TWaker;
  s: TPtySession;
  outFile: TStringList;
  cmd, err: string;
  data: RawByteString;
  exited: Boolean;
  code: Int64;
  t0: Int64;
  i, cols, rows: Integer;
  fs: TFormatSettings;

function Seconds: Double;
begin
  Result := (GetTickCount64 - QWord(t0)) / 1000;
end;

begin
  if ParamCount < 4 then
  begin
    WriteLn('conptyrecord OUT.raw COLS ROWS COMMAND...');
    Halt(2);
  end;
  cols := StrToInt(ParamStr(2));
  rows := StrToInt(ParamStr(3));
  cmd := ParamStr(4);
  for i := 5 to ParamCount do
    cmd := cmd + ' ' + ParamStr(i);
  { @FILE: the command line from FILE (UTF-8, first line) -- quotes and non-ASCII
    survive that, not every shell's argument passing }
  if Copy(cmd, 1, 1) = '@' then
    with TStringList.Create do
    try
      LoadFromFile(Copy(cmd, 2, MaxInt));
      cmd := Strings[0];
    finally
      Free;
    end;
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  outFile := TStringList.Create;
  waker := TWaker.Create;
  s := TPtySession.Create(TConPtyBackend.Create);
  try
    s.OnWake := @waker.Wake;
    t0 := GetTickCount64;
    if not s.Start(cmd, cols, rows, err) then
    begin
      WriteLn('not started: ', err);
      Halt(1);
    end;
    code := -2;
    while Seconds < 20 do
    begin
      waker.Event.WaitFor(100);
      if s.Pump(data, exited, code) then
      begin
        if data <> '' then
          outFile.Add(FormatFloat('0.000000', Seconds, fs) + ' ' + EncodeStringBase64(data));
        s.Delivered(Length(data));
        if exited then Break;
      end;
    end;
    outFile.SaveToFile(ParamStr(1));
    WriteLn(Format('%d blocks, exit code %d', [outFile.Count, code]));
  finally
    s.Free;
    PtyWaitForFinishers(PtyExitWaitMs);
    waker.Free;
    outFile.Free;
  end;
end.
