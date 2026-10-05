unit test.themebuilder.http;
{ The AI page's HTTP transport (phase 3), on Windows: WinHTTP driven against a local server
  (tbfakehttp) through a plain reply, a streamed one, a refused key, a reply cut off, a
  stalled one, a dead port, a cancel. The checks themselves live in tbaichecks: the WSL
  console program runs the very same ones over libcurl. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry;

type
  TTbHttpTests = class(TTestCase)
  protected
    procedure SetUp; override;
  published
    procedure TestAPlainReply;              { H1 }
    procedure TestAReplyIsStreamed;         { H2 }
    procedure TestA401IsAStatus;            { H3 }
    procedure TestA429IsAStatus;            { H4 }
    procedure TestACutOffReplyIsBroken;     { H5 }
    procedure TestSilenceTimesOut;          { H6 }
    procedure TestADeadPortCannotConnect;   { H7 }
    procedure TestCancelStopsAtOnce;        { H8 }
    procedure TestRefusingDataStops;        { H9 }
    procedure TestLocalhostReachesIPv4;     { H10 }
    procedure TestTheUrlIsSplit;            { H11 }
    procedure TestLoopbackHosts;            { H12 }
    procedure TestALargeBodyArrives;        { H13 }
    { after the phase 3 reviews }
    procedure TestTlsIsOneTwoOrThree;       { H14 }
  end;

implementation

uses
  tbhttp, tbaichecks, tbfakehttp{$IFDEF MSWINDOWS}, tbhttpwin{$ENDIF};

procedure TTbHttpTests.SetUp;
begin
  TbCancelGraceMs := 1000;
end;

procedure TTbHttpTests.TestAPlainReply;
var
  why: string;
  ok: Boolean;
begin
  ok := HttpCheckPlain(why);
  AssertTrue('H1: ' + why, ok);
end;

procedure TTbHttpTests.TestAReplyIsStreamed;
var
  why: string;
  ok: Boolean;
begin
  ok := HttpCheckStreamed(why);
  AssertTrue('H2: ' + why, ok);
end;

procedure TTbHttpTests.TestA401IsAStatus;
var
  why: string;
  ok: Boolean;
begin
  ok := HttpCheckStatus(401, why);
  AssertTrue('H3: ' + why, ok);
end;

procedure TTbHttpTests.TestA429IsAStatus;
var
  why: string;
  ok: Boolean;
begin
  ok := HttpCheckStatus(429, why);
  AssertTrue('H4: ' + why, ok);
end;

procedure TTbHttpTests.TestACutOffReplyIsBroken;
var
  why: string;
  ok: Boolean;
begin
  ok := HttpCheckBroken(why);
  AssertTrue('H5: ' + why, ok);
end;

procedure TTbHttpTests.TestSilenceTimesOut;
var
  why: string;
  ok: Boolean;
begin
  ok := HttpCheckIdleTimeout(why);
  AssertTrue('H6: ' + why, ok);
end;

procedure TTbHttpTests.TestADeadPortCannotConnect;
var
  why: string;
  ok: Boolean;
begin
  ok := HttpCheckCannotConnect(why);
  AssertTrue('H7: ' + why, ok);
end;

procedure TTbHttpTests.TestCancelStopsAtOnce;
var
  why: string;
  ok: Boolean;
begin
  ok := HttpCheckCancel(why);
  AssertTrue('H8: ' + why, ok);
end;

procedure TTbHttpTests.TestRefusingDataStops;
var
  why: string;
  ok: Boolean;
begin
  ok := HttpCheckRefuseData(why);
  AssertTrue('H9: ' + why, ok);
end;

procedure TTbHttpTests.TestLocalhostReachesIPv4;
var
  why: string;
  ok: Boolean;
begin
  ok := HttpCheckLocalhost(why);
  AssertTrue('H10: ' + why, ok);
end;

procedure TTbHttpTests.TestTheUrlIsSplit;

  procedure Good(const AUrl: string; ASecure: Boolean; const AHost: string; APort: Integer;
    const APath: string);
  var
    p: TTbUrlParts;
  begin
    AssertTrue('H11: splits ' + AUrl, TbSplitUrl(AUrl, p));
    AssertEquals('H11: secure ' + AUrl, ASecure, p.Secure);
    AssertEquals('H11: host ' + AUrl, AHost, p.Host);
    AssertEquals('H11: port ' + AUrl, APort, p.Port);
    AssertEquals('H11: path ' + AUrl, APath, p.Path);
  end;

  procedure Bad(const AUrl: string);
  var
    p: TTbUrlParts;
  begin
    AssertFalse('H11: refuses ' + AUrl, TbSplitUrl(AUrl, p));
  end;

begin
  Good('https://api.openai.com/v1', True, 'api.openai.com', 443, '/v1');
  Good('http://localhost:11434/v1/chat/completions?x=1#f', False, 'localhost', 11434,
    '/v1/chat/completions?x=1');
  Good('http://[::1]:8080', False, '::1', 8080, '/');
  Good('HTTP://A', False, 'A', 80, '/');
  Good('https://h?q', True, 'h', 443, '/?q');
  Bad('ftp://x');
  Bad('http://');
  Bad('http://h:0');
  Bad('http://h:70000');
  Bad('http://h:12a');
  Bad('http://h:');
  Bad('api.openai.com/v1');
end;

procedure TTbHttpTests.TestLoopbackHosts;
const
  cYes: array[0..4] of string = ('localhost', 'LOCALHOST', '127.0.0.1', '127.1.2.3', '::1');
  cNo: array[0..4] of string = ('localhost.example.com', '127.0.0.1.nip.io', '10.0.0.1', '', '127.');
var
  i: Integer;
begin
  for i := 0 to High(cYes) do
    AssertTrue('H12: loopback ' + cYes[i], TbIsLoopbackHost(cYes[i]));
  for i := 0 to High(cNo) do
    AssertFalse('H12: not loopback "' + cNo[i] + '"', TbIsLoopbackHost(cNo[i]));
end;

procedure TTbHttpTests.TestALargeBodyArrives;
var
  why: string;
  ok: Boolean;
begin
  ok := HttpCheckBigBody(why);
  AssertTrue('H13: ' + why, ok);
end;

{ H14 (WinHTTP): an https request is limited to TLS 1.2 and 1.3 (1.2 alone where the system
  does not know 1.3); plain http sets nothing. Against a dead port on this computer: the
  protocols are set before the connection is tried }
procedure TTbHttpTests.TestTlsIsOneTwoOrThree;
{$IFDEF MSWINDOWS}
const
  cTls12 = $00000800;
  cTls13 = $00002000;
var
  t: TTbWinHttpTransport;
  req: TTbHttpRequest;
  r: TTbHttpResult;
begin
  req := Default(TTbHttpRequest);
  req.Url := 'https://127.0.0.1:' + IntToStr(FakeDeadPort) + '/v1';
  req.IdleTimeoutMs := 5000;
  t := TTbWinHttpTransport.Create;
  try
    r := t.Execute(req, nil, nil);
    AssertTrue('H14: nothing listens there', r.Error <> hekNone);
    AssertTrue(Format('H14: TLS 1.2 and 1.3, or 1.2 alone (%x)', [t.SecureProtocols]),
      (t.SecureProtocols = cTls12 or cTls13) or (t.SecureProtocols = cTls12));
  finally
    t.Free;
  end;
  req.Url := 'http://127.0.0.1:' + IntToStr(FakeDeadPort) + '/v1';
  t := TTbWinHttpTransport.Create;
  try
    t.Execute(req, nil, nil);
    AssertEquals('H14: plain http sets nothing', 0, t.SecureProtocols);
  finally
    t.Free;
  end;
end;
{$ELSE}
begin
  { libcurl takes the system's TLS settings }
end;
{$ENDIF}

initialization
  RegisterTest(TTbHttpTests);
end.
