unit test.terminal.links;
{$mode objfpc}{$H+}
{ tyControls.Terminal.Links -- held to xterm.js 6.0.0.

  TTyTerminalLinksOracleTests read tests/fixtures/terminal-links.json
  (tools/terminal-oracle/url-cases.js): the URL prefix isUrl compares with (node's
  WHATWG URL), web addresses in one line of a 300-column terminal
  (LinkComputer.computeLink with the addon's own regex), and scenes of several rows
  with OSC 8 links, the overlap removal and the hit test.

  TTyTerminalLinksTests pin what the fixture leaves out on purpose: hosts that would
  go through IDNA (design spec 15). }

interface

uses
  Classes, SysUtils, Types, fpcunit, testregistry, fpjson,
  tyControls.Terminal.Buffer, tyControls.Terminal.Core, tyControls.Terminal.Selection,
  tyControls.Terminal.Links, test.terminal.oracle;

type
  TTyTerminalLinksOracleTests = class(TTestCase)
  published
    procedure TestUrlPrefixes;
    procedure TestUrlsInALine;
    procedure TestLinesAndProviders;
  end;

  TTyTerminalLinksTests = class(TTestCase)
  published
    procedure TestNonAsciiHostIsNotAWebLink;
    procedure TestXnLabelsAreNotChecked;
    procedure TestTheScannerTable;
  end;

implementation

function BoolText(B: Boolean): string;
begin
  if B then Result := 'true' else Result := 'false';
end;

function LinkText(const ALink: TTyTermLink): string;
begin
  Result := Format('%s %d,%d,%d,%d', [ALink.Text, ALink.Range.StartX, ALink.Range.StartY,
    ALink.Range.EndX, ALink.Range.EndY]);
end;

function JsonLinkText(AObj: TJSONObject): string;
var
  r: TJSONArray;
begin
  r := AObj.Arrays['range'];
  Result := Format('%s %d,%d,%d,%d', [TyTermBase64Bytes(AObj.Strings['text']), r.Integers[0],
    r.Integers[1], r.Integers[2], r.Integers[3]]);
end;

function LinksText(const ALinks: TTyTermLinks): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(ALinks) do
  begin
    if i > 0 then Result := Result + ' | ';
    Result := Result + LinkText(ALinks[i]);
  end;
end;

function JsonLinksText(AArr: TJSONArray): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to AArr.Count - 1 do
  begin
    if i > 0 then Result := Result + ' | ';
    Result := Result + JsonLinkText(AArr.Objects[i]);
  end;
end;

{ ---- TTyTerminalLinksOracleTests --------------------------------------------------- }

procedure TTyTerminalLinksOracleTests.TestUrlPrefixes;
var
  miss: TTyTermMisses;
  fx: TTyTermFixtures;
  arr: TJSONArray;
  o: TJSONObject;
  i: Integer;
  text, base: UnicodeString;
  ok, isHttp, wantHttp: Boolean;
  n: Int64;
begin
  miss := TTyTermMisses.Create;
  try
    fx := TyTermLoadFixtures('links', miss);
    try
      arr := fx[0].Arrays['prefix'];
      n := 0;
      for i := 0 to arr.Count - 1 do
      begin
        o := arr.Objects[i];
        text := UTF8Decode(o.Strings['text']);
        ok := TyTermParseUrlPrefix(text, base, isHttp);
        Inc(n);
        miss.AddCompared;
        if ok <> o.Booleans['ok'] then
          miss.Add(o.Strings['text'], 'parses', BoolText(o.Booleans['ok']), BoolText(ok));
        if ok and o.Booleans['ok'] then
        begin
          wantHttp := (o.Strings['protocol'] = 'http:') or (o.Strings['protocol'] = 'https:');
          Inc(n);
          miss.AddCompared;
          if isHttp <> wantHttp then
            miss.Add(o.Strings['text'], 'http(s)', BoolText(wantHttp), BoolText(isHttp));
          if wantHttp and isHttp then
          begin
            Inc(n);
            miss.AddCompared;
            if UTF8Encode(base) <> o.Strings['base'] then
              miss.Add(o.Strings['text'], 'base', o.Strings['base'], UTF8Encode(base));
          end;
        end;
        { isUrl only ever sees what the regex matched: http and https }
        if not o.Booleans['ok'] or (o.Strings['protocol'] = 'http:') or (o.Strings['protocol'] = 'https:') then
        begin
          Inc(n);
          miss.AddCompared;
          if TyTermIsUrl(text) <> o.Booleans['isUrl'] then
            miss.Add(o.Strings['text'], 'isUrl', BoolText(o.Booleans['isUrl']), BoolText(TyTermIsUrl(text)));
        end;
      end;
      AssertEquals(miss.Text, 0, miss.Count);
      AssertTrue('prefixes read', arr.Count > 100);
      AssertEquals('comparisons', n, miss.Compared);
    finally
      TyTermFreeFixtures(fx);
    end;
  finally
    miss.Free;
  end;
end;

procedure TTyTerminalLinksOracleTests.TestUrlsInALine;
var
  miss: TTyTermMisses;
  fx: TTyTermFixtures;
  arr: TJSONArray;
  o: TJSONObject;
  i: Integer;
  core: TTyTerminalCore;
  links: TTyTermLinks;
  text: string;
begin
  miss := TTyTermMisses.Create;
  core := TTyTerminalCore.Create(300, 3);
  try
    core.Scrollback := 0;
    fx := TyTermLoadFixtures('links', miss);
    try
      arr := fx[0].Arrays['urls'];
      for i := 0 to arr.Count - 1 do
      begin
        o := arr.Objects[i];
        text := TyTermBase64Bytes(o.Strings['text']);
        core.Reset;
        core.WriteSync(text);
        links := TyTermComputeUrlLinks(core.Buffer, 1);
        miss.AddCompared;
        if JsonLinksText(o.Arrays['links']) <> LinksText(links) then
          miss.Add(text, 'links', JsonLinksText(o.Arrays['links']), LinksText(links));
      end;
      AssertEquals(miss.Text, 0, miss.Count);
      AssertTrue('lines read', arr.Count > 150);
      AssertEquals('comparisons', arr.Count, miss.Compared);
    finally
      TyTermFreeFixtures(fx);
    end;
  finally
    core.Free;
    miss.Free;
  end;
end;

procedure TTyTerminalLinksOracleTests.TestLinesAndProviders;
var
  miss: TTyTermMisses;
  fx: TTyTermFixtures;
  scenes, queries, hits, keptArr: TJSONArray;
  scene, q: TJSONObject;
  i, k, x, y, j, idx, cols: Integer;
  core: TTyTerminalCore;
  web, osc, oscAll: TTyTermLinks;
  replies: array[0..1] of TTyTermLinks;
  flat: TTyTermLinks;
  found: TTyTermLink;
  id, want, got: string;
  wp: TTyTerminalWindowsPty;
begin
  miss := TTyTermMisses.Create;
  try
    fx := TyTermLoadFixtures('links', miss);
    try
      scenes := fx[0].Arrays['lines'];
      for i := 0 to scenes.Count - 1 do
      begin
        scene := scenes.Objects[i];
        cols := scene.Integers['cols'];
        core := TTyTerminalCore.Create(cols, scene.Integers['rows']);
        try
          core.Scrollback := 0;
          if scene.Find('windowsPty') <> nil then
          begin
            wp.Backend := twpNone;
            if scene.Objects['windowsPty'].Get('backend', '') = 'conpty' then wp.Backend := twpConPty
            else if scene.Objects['windowsPty'].Get('backend', '') = 'winpty' then wp.Backend := twpWinPty;
            wp.BuildNumber := scene.Objects['windowsPty'].Get('buildNumber', 0);
            core.WindowsPty := wp;
          end;
          core.WriteSync(TyTermBase64Bytes(scene.Strings['write']));
          { phase 5: resized after the write (rewrapped, or longer than the grid) }
          if scene.Find('resize') <> nil then
          begin
            core.Resize(scene.Arrays['resize'].Integers[0], scene.Arrays['resize'].Integers[1]);
            cols := core.Cols;
          end;
          queries := scene.Arrays['queries'];
          for k := 0 to queries.Count - 1 do
          begin
            q := queries.Objects[k];
            y := q.Integers['y'];
            id := Format('%s y %d', [scene.Strings['id'], y]);
            web := TyTermComputeUrlLinks(core.Buffer, y);
            osc := TyTermComputeOsc8Links(core.Buffer, core.Links, y, False);
            oscAll := TyTermComputeOsc8Links(core.Buffer, core.Links, y, True);
            miss.AddCompared(3);
            if JsonLinksText(q.Arrays['web']) <> LinksText(web) then
              miss.Add(id, 'web', JsonLinksText(q.Arrays['web']), LinksText(web));
            if JsonLinksText(q.Arrays['osc']) <> LinksText(osc) then
              miss.Add(id, 'osc', JsonLinksText(q.Arrays['osc']), LinksText(osc));
            if JsonLinksText(q.Arrays['oscAll']) <> LinksText(oscAll) then
              miss.Add(id, 'oscAll', JsonLinksText(q.Arrays['oscAll']), LinksText(oscAll));
            replies[0] := Copy(osc);
            replies[1] := Copy(web);
            TyTermRemoveIntersectingLinks(y, cols, replies);
            keptArr := q.Arrays['kept'];
            miss.AddCompared(2);
            if JsonLinksText(keptArr.Arrays[0]) <> LinksText(replies[0]) then
              miss.Add(id, 'kept osc', JsonLinksText(keptArr.Arrays[0]), LinksText(replies[0]));
            if JsonLinksText(keptArr.Arrays[1]) <> LinksText(replies[1]) then
              miss.Add(id, 'kept web', JsonLinksText(keptArr.Arrays[1]), LinksText(replies[1]));
            { the hit test through the control's entry point }
            flat := nil;
            SetLength(flat, Length(replies[0]) + Length(replies[1]));
            for j := 0 to High(replies[0]) do
              flat[j] := replies[0][j];
            for j := 0 to High(replies[1]) do
              flat[Length(replies[0]) + j] := replies[1][j];
            hits := q.Arrays['hits'];
            want := '';
            got := '';
            for x := 1 to cols do
            begin
              want := want + IntToStr(hits.Integers[x - 1]) + ' ';
              idx := -1;
              if TyTermFindLinkAt(core.Buffer, core.Links, x - 1, y - 1, cols, True, False, found) then
              begin
                idx := -2;                 { found, but not among the kept ones }
                for j := 0 to High(flat) do
                  if TyTermLinkEquals(flat[j], found) and (flat[j].Source = found.Source) then
                  begin
                    idx := j;
                    Break;
                  end;
              end;
              got := got + IntToStr(idx) + ' ';
            end;
            miss.AddCompared;
            if want <> got then
              miss.Add(id, 'hits', want, got);
          end;
        finally
          core.Free;
        end;
      end;
      AssertEquals(miss.Text, 0, miss.Count);
      AssertTrue('scenes read', scenes.Count > 20);
      k := 0;
      for i := 0 to scenes.Count - 1 do
        Inc(k, scenes.Objects[i].Arrays['queries'].Count);
      AssertEquals('comparisons = queries x 6', Int64(k) * 6, miss.Compared);
    finally
      TyTermFreeFixtures(fx);
    end;
  finally
    miss.Free;
  end;
end;

{ ---- TTyTerminalLinksTests --------------------------------------------------------- }

procedure TTyTerminalLinksTests.TestNonAsciiHostIsNotAWebLink;
var
  base: UnicodeString;
  isHttp: Boolean;
begin
  AssertFalse('a CJK host is no web address', TyTermIsUrl(UTF8Decode('http://'#$E4#$BE#$8B#$E5#$AD#$90'.'#$E6#$B5#$8B#$E8#$AF#$95'/')));
  AssertFalse('an umlaut host neither', TyTermIsUrl(UTF8Decode('http://m'#$C3#$BC'nchen.de')));
  AssertTrue('OSC 8 takes it as http', TyTermParseUrlPrefix(
    UTF8Decode('http://'#$E4#$BE#$8B#$E5#$AD#$90'.'#$E6#$B5#$8B#$E8#$AF#$95'/'), base, isHttp));
  AssertTrue('http', isHttp);
  AssertTrue('percent-encoded non-ASCII is non-ASCII too', TyTermParseUrlPrefix('http://%C3%BC.de', base, isHttp));
  AssertFalse('and no web address', TyTermIsUrl('http://%C3%BC.de'));
end;

procedure TTyTerminalLinksTests.TestXnLabelsAreNotChecked;
begin
  { upstream: not valid punycode, new URL throws; we do not decode punycode (spec 15) }
  AssertTrue(TyTermIsUrl('http://xn--zz.com'));
  AssertTrue(TyTermIsUrl('http://xn--mnchen-3ya.de/x'));
end;

procedure TTyTerminalLinksTests.TestTheScannerTable;

  function M(const S: UnicodeString): string;
  var
    a, n: Integer;
  begin
    if TyTermNextUrlMatch(S, 0, a, n) then
      Result := UTF8Encode(Copy(S, a + 1, n))
    else
      Result := '';
  end;

begin
  AssertEquals('plain', 'http://a.com', M('see http://a.com now'));
  AssertEquals('a full stop ends it', 'http://a.com', M('see http://a.com.'));
  AssertEquals('a star after the body', 'http://a.com*', M('http://a.com**'));
  AssertEquals('U+3000', 'http://a.com/x', M(UTF8Decode('http://a.com/x'#$E3#$80#$80'y')));
  AssertEquals('Http is not the scheme', '', M('Http://a.com'));
  AssertEquals('HTTPs neither', '', M('HTTPs://a.com'));
  AssertEquals('found after a letter', 'http://a.com', M('xhttp://a.com'));
  AssertEquals('https', 'https://a.com', M('https://a.com'));
  AssertEquals('nothing after the slashes', '', M('http:// x'));
end;

initialization
  RegisterTest(TTyTerminalLinksOracleTests);
  RegisterTest(TTyTerminalLinksTests);
end.
