program tbcurlwsl;

{ The theme builder's AI transport over libcurl (phase 3): tytests runs on Windows and only
  ever reaches WinHTTP, so the Linux path -- the function table loaded at run time, the
  variadic setopt, the callbacks, cancelling, the idle timeout, the key file's 0600 -- is
  run here, in WSL, against the same local server (tests/tbfakehttp) and with the same
  checks (tests/tbaichecks) as the Windows suites. No LCL. Built and run in WSL:

    cd tools/themebuilder-curl-wsl && mkdir -p lib && \
      fpc -Mobjfpc -Sh -FUlib -Fu../themebuilder/ai -Fu../../tests tbcurlwsl.lpr && ./tbcurlwsl

  THEMEBUILDER_LIBCURL=libcurl-gnutls.so.4 ./tbcurlwsl runs them on the other library.
  ./tbcurlwsl --expect-missing (with THEMEBUILDER_LIBCURL pointing at nothing) checks only
  that a missing libcurl is reported, naming what was tried. --proxy-check is the child
  W10 starts with a proxy in its environment.

  Prints the library it loaded, PASS / FAIL per check and, last,
  "tbcurlwsl: N passed, M failed"; the exit code is M. }

{$mode objfpc}{$H+}

uses
  cthreads, Classes, SysUtils, BaseUnix, Unix, tbhttp, tbhttpcurl, tbfakehttp, tbaichecks;

type
  TCheckFn = function(out AWhy: string): Boolean;

var
  Passed, Failed: Integer;

procedure Check(const AName: string; AOk: Boolean; const AWhy: string);
begin
  if AOk then
  begin
    Inc(Passed);
    WriteLn('PASS ', AName);
  end
  else
  begin
    Inc(Failed);
    WriteLn('FAIL ', AName, ': ', AWhy);
  end;
end;

procedure Run(const AName: string; AFn: TCheckFn);
var
  why: string;
  ok: Boolean;
begin
  why := '';
  try
    ok := AFn(why);
  except
    on E: Exception do
    begin
      ok := False;
      why := 'raised ' + E.ClassName + ': ' + E.Message;
    end;
  end;
  Check(AName, ok, why);
end;

function Check401(out AWhy: string): Boolean;
begin
  Result := HttpCheckStatus(401, AWhy);
end;

{ W10: in a child process whose environment sends everything through a proxy on port 9
  (where nothing listens), a request to the local server still gets through }
function CheckProxyBypass(out AWhy: string): Boolean;
var
  status: cint;
begin
  status := fpSystem('http_proxy=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 ' +
    'HTTP_PROXY=http://127.0.0.1:9 ./tbcurlwsl --proxy-check');
  Result := status = 0;
  if not Result then
    AWhy := Format('the child with a proxy set failed (status %d)', [status]);
end;

{ W11 }
function CheckLoadedName(out AWhy: string): Boolean;
var
  cands: TStringArray;
  i: Integer;
begin
  Result := False;
  cands := TbCurlCandidates;
  for i := 0 to High(cands) do
    if cands[i] = TbCurlLoadedName then
      Exit(True);
  AWhy := 'loaded "' + TbCurlLoadedName + '", not a candidate';
end;

var
  reason, why: string;
  ok: Boolean;
begin
  { the samples and the sentences are UTF-8; so is every string here }
  DefaultSystemCodePage := CP_UTF8;
  fpSignal(SIGPIPE, SignalHandler(SIG_IGN));
  TbAiFixtureDir := ExpandFileName('../../tests/fixtures/themebuilder/ai') + PathDelim;
  { libcurl notices a cancel in its progress callback, about once a second }
  TbCancelGraceMs := 2500;

  if ParamStr(1) = '--expect-missing' then
  begin
    ok := not TbTransportAvailable(reason);
    if ok and (Pos(GetEnvironmentVariable('THEMEBUILDER_LIBCURL'), reason) = 0) then
      ok := False;
    if (GetEnvironmentVariable('THEMEBUILDER_LIBCURL') = '') then
      ok := False;
    Check('missing libcurl is reported', ok, 'available: ' + BoolToStr(not ok, True) +
      ', reason: ' + reason);
    WriteLn('reason: ', reason);
    WriteLn(Format('tbcurlwsl: %d passed, %d failed', [Passed, Failed]));
    Halt(Failed);
  end;

  if ParamStr(1) = '--proxy-check' then
  begin
    ok := HttpCheckPlain(why);
    if not ok then
      WriteLn('proxy-check: ', why);
    if ok then Halt(0) else Halt(1);
  end;

  if not TbTransportAvailable(reason) then
  begin
    WriteLn('library: none -- ', reason);
    Check('libcurl loads', False, reason);
    WriteLn(Format('tbcurlwsl: %d passed, %d failed', [Passed, Failed]));
    Halt(Failed);
  end;
  WriteLn('library: ', TbCurlLoadedName);

  Run('W1 plain reply (H1)', @HttpCheckPlain);
  Run('W2 streamed (H2)', @HttpCheckStreamed);
  Run('W3 401 is a status (H3)', @Check401);
  Run('W4 cut off is broken (H5)', @HttpCheckBroken);
  Run('W5 idle timeout (H6)', @HttpCheckIdleTimeout);
  Run('W6 dead port (H7)', @HttpCheckCannotConnect);
  Run('W7 cancel (H8)', @HttpCheckCancel);
  Run('W8 refusing data stops (H9)', @HttpCheckRefuseData);
  Run('W9 localhost (H10)', @HttpCheckLocalhost);
  Run('W10 a local address skips the proxy', @CheckProxyBypass);
  Run('W11 the loaded library is a candidate', @CheckLoadedName);
  Run('W12 a large body arrives (H13)', @HttpCheckBigBody);

  Run('C1@curl an OpenAI stream, cut anywhere', @AiCheckOpenAIStream);
  Run('C3@curl the key is scrubbed from a 401', @AiCheckKeyIsScrubbed);
  Run('C7@curl a broken stream', @AiCheckBroken);
  Run('C9@curl silence times out', @AiCheckTimeout);
  Run('C13@curl a reply not streamed', @AiCheckNotStreamed);
  Run('C15@curl stop', @AiCheckCancel);

  WriteLn(Format('tbcurlwsl: %d passed, %d failed', [Passed, Failed]));
  Halt(Failed);
end.
