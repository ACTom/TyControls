unit test.terminal.buffer;
{$mode objfpc}{$H+}
{ Cells, lines, the line ring, the buffers and the OSC 8 link table -- held to
  xterm.js 6.0.0 itself, without the parser.

  tools/terminal-oracle/buffer-cases.js drives upstream's own BufferLine,
  CircularList and BufferService with operation scripts and records the return value
  and the whole state after every step (terminal-buffer-ops.json): wide-character
  repairs, protected cells, combining, line resizes and copies, the text cache, ring
  trims and shifts with their events, the three scroll paths, row resizes, the
  alternate screen, tab stops, markers and links. This suite replays each script on
  the port and compares every step; the counts are asserted so an empty fixture
  cannot pass. TTyTerminalBufferTests are direct tables, not from the fixture. }

interface

uses
  Classes, SysUtils, Types, fpcunit, testregistry, fpjson,
  tyControls.Terminal.Buffer, test.terminal.oracle;

type
  TTyTerminalBufferOracleTests = class(TTestCase)
  published
    procedure TestFixturesComeFromThePinnedUpstream;
    procedure TestLineOps;
    procedure TestListOps;
    procedure TestBufferOps;
  end;

  TTyTerminalBufferTests = class(TTestCase)
  published
    procedure TestExtAttrsAccessors;
    procedure TestLinesAreFreedWhenTheirOwnersGo;
    procedure TestTabStopsKeepStaleKeys;
  end;

implementation

function LoadCases(AMisses: TTyTermMisses; out AFixtures: TTyTermFixtures): TFPList;
begin
  AFixtures := TyTermLoadFixtures('buffer-ops', AMisses);
  Result := TyTermAllCases(AFixtures);
end;

function StepPath(AStep: Integer; AOp: TJSONArray): string;
begin
  Result := Format('step #%d %s', [AStep, AOp.AsJSON]);
end;

{ ---- line scripts ------------------------------------------------------------------ }

type
  TNamedLines = class
  public
    Names: TStringList;
    constructor Create;
    destructor Destroy; override;
    function Line(const AName: string): TTyTerminalLine;
    procedure Put(const AName: string; ALine: TTyTerminalLine);   { takes ownership }
  end;

constructor TNamedLines.Create;
begin
  inherited Create;
  Names := TStringList.Create;
  Names.Sorted := True;
  Names.CaseSensitive := True;
end;

destructor TNamedLines.Destroy;
var
  i: Integer;
begin
  for i := 0 to Names.Count - 1 do
    TTyTerminalLine(Names.Objects[i]).Release;
  Names.Free;
  inherited Destroy;
end;

function TNamedLines.Line(const AName: string): TTyTerminalLine;
var
  i: Integer;
begin
  i := Names.IndexOf(AName);
  if i < 0 then
    raise Exception.Create('no line ' + AName);
  Result := TTyTerminalLine(Names.Objects[i]);
end;

procedure TNamedLines.Put(const AName: string; ALine: TTyTerminalLine);
var
  i: Integer;
begin
  i := Names.IndexOf(AName);
  if i >= 0 then
  begin
    TTyTerminalLine(Names.Objects[i]).Release;
    Names.Objects[i] := ALine;
  end
  else
    Names.AddObject(AName, ALine);
end;

function BoolJson(AValue: Boolean): TJSONBoolean;
begin
  Result := TJSONBoolean.Create(AValue);
end;

function LoadJson(ALine: TTyTerminalLine; ACol: Integer): TJSONObject;
var
  c: TTyTerminalCellData;
begin
  ALine.LoadCell(ACol, c);
  Result := TJSONObject.Create;
  Result.Add('content', Int64(c.Content));
  Result.Add('fg', Int64(c.Fg));
  Result.Add('bg', Int64(c.Bg));
  Result.Add('ext', TyTermExtQuadJson(c.Ext));
  if c.Content and TyTermContentIsCombinedMask <> 0 then
    Result.Add('comb', TyTermCpsJson(TyTermUtf8ToCps(c.Combined)));
end;

function RunLineCase(ACase: TJSONObject; AMisses: TTyTermMisses): Integer;
var
  lines: TNamedLines;
  init, spec, st, stLine: TJSONObject;
  ops, a, stLines: TJSONArray;
  after: TJSONArray;
  i, k, col: Integer;
  name, id: string;
  ln: TTyTerminalLine;
  got: TJSONData;
  startCol, endCol: Integer;
begin
  id := ACase.Strings['id'];
  lines := TNamedLines.Create;
  try
    init := ACase.Objects['init'].Objects['lines'];
    for i := 0 to init.Count - 1 do
    begin
      spec := init.Objects[init.Names[i]];
      if spec.Find('fill') <> nil then
        lines.Put(init.Names[i], TTyTerminalLine.Create(spec.Integers['cols'], TyTermCellFromJson(spec.Objects['fill'])))
      else
        lines.Put(init.Names[i], TTyTerminalLine.CreateDefault(spec.Integers['cols']));
    end;
    ops := ACase.Arrays['ops'];
    after := ACase.Arrays['after'];
    for i := 0 to ops.Count - 1 do
    begin
      a := ops.Arrays[i];
      name := a.Strings[0];
      got := nil;
      if name = 'clone' then
        ln := nil
      else
        ln := lines.Line(a.Strings[1]);
      try
        if name = 'setCellFromCodepoint' then
          ln.SetCellFromCodepoint(a.Integers[2], Cardinal(a.Int64s[3]), a.Integers[4], TyTermAttrFromJson(a.Objects[5]))
        else if name = 'addCodepointToCell' then
          ln.AddCodepointToCell(a.Integers[2], Cardinal(a.Int64s[3]), a.Integers[4])
        else if name = 'setCell' then
          ln.SetCell(a.Integers[2], TyTermCellFromJson(a.Objects[3]))
        else if name = 'insertCells' then
          ln.InsertCells(a.Integers[2], a.Int64s[3], TyTermCellFromJson(a.Objects[4]))
        else if name = 'deleteCells' then
          ln.DeleteCells(a.Integers[2], a.Int64s[3], TyTermCellFromJson(a.Objects[4]))
        else if name = 'replaceCells' then
          ln.ReplaceCells(a.Integers[2], a.Int64s[3], TyTermCellFromJson(a.Objects[4]), a.Booleans[5])
        else if name = 'resize' then
          got := BoolJson(ln.Resize(a.Integers[2], TyTermCellFromJson(a.Objects[3])))
        else if name = 'fill' then
          ln.Fill(TyTermCellFromJson(a.Objects[2]), a.Booleans[3])
        else if name = 'copyFrom' then
          ln.CopyFrom(lines.Line(a.Strings[2]), a.Booleans[3])
        else if name = 'clone' then
          lines.Put(a.Strings[1], lines.Line(a.Strings[2]).Clone(a.Booleans[3]))
        else if name = 'copyCellsFrom' then
          ln.CopyCellsFrom(lines.Line(a.Strings[2]), a.Integers[3], a.Integers[4], a.Integers[5], a.Booleans[6])
        else if name = 'setWrapped' then
          ln.IsWrapped := a.Booleans[2]
        else if name = 'translate' then
        begin
          if a.Items[3].JSONType = jtNull then startCol := 0 else startCol := a.Integers[3];
          if a.Items[4].JSONType = jtNull then endCol := -1 else endCol := a.Integers[4];
          got := TyTermDigestableJson(ln.TranslateToString(a.Booleans[2], startCol, endCol));
        end
        else if name = 'trimmed' then
          got := TJSONIntegerNumber.Create(ln.GetTrimmedLength)
        else if name = 'noBgTrimmed' then
          got := TJSONIntegerNumber.Create(ln.GetNoBgTrimmedLength)
        else if name = 'probe' then
        begin
          col := a.Integers[2];
          got := TJSONArray.Create;
          TJSONArray(got).Add(ln.GetWidth(col));
          TJSONArray(got).Add(ln.HasWidth(col));
          TJSONArray(got).Add(ln.HasContent(col));
          TJSONArray(got).Add(Int64(ln.GetCodePoint(col)));
          TJSONArray(got).Add(ln.IsCombined(col));
          TJSONArray(got).Add(TyTermDigestableJson(ln.GetChars(col)));
          TJSONArray(got).Add(ln.IsProtected(col));
        end
        else if name = 'load' then
          got := LoadJson(ln, a.Integers[2])
        else
          raise Exception.Create('unknown line op ' + name);

        st := after.Objects[i];
        if st.Find('ret') <> nil then
          TyTermCompareJson(st.Find('ret'), got, id, StepPath(i, a) + ' / ret', AMisses)
        else if got <> nil then
          AMisses.Add(id, StepPath(i, a) + ' / ret', '(none)', got.AsJSON);
      finally
        got.Free;
      end;
      stLines := st.Objects['state'].Arrays['lines'];
      AMisses.AddCompared;
      if stLines.Count <> lines.Names.Count then
        AMisses.Add(id, StepPath(i, a) + ' / line names', IntToStr(stLines.Count), IntToStr(lines.Names.Count));
      for k := 0 to stLines.Count - 1 do
      begin
        stLine := stLines.Objects[k];
        if lines.Names.IndexOf(stLine.Strings['name']) < 0 then
          AMisses.Add(id, StepPath(i, a), 'line ' + stLine.Strings['name'], 'none')
        else
          TyTermCompareLine(lines.Line(stLine.Strings['name']), stLine, -1, id,
            StepPath(i, a) + ' / line ' + stLine.Strings['name'], AMisses);
      end;
    end;
    Result := ops.Count;
  finally
    lines.Free;
  end;
end;

{ ---- list scripts ------------------------------------------------------------------ }

type
  TListRec = class
  public
    Events: TJSONArray;
    procedure OnInsert(AIndex, AAmount: Integer);
    procedure OnDelete(AIndex, AAmount: Integer);
    procedure OnTrim(AAmount: Integer);
  end;

procedure TListRec.OnInsert(AIndex, AAmount: Integer);
begin
  Events.Add(TJSONArray.Create(['insert', AIndex, AAmount]));
end;

procedure TListRec.OnDelete(AIndex, AAmount: Integer);
begin
  Events.Add(TJSONArray.Create(['delete', AIndex, AAmount]));
end;

procedure TListRec.OnTrim(AAmount: Integer);
begin
  Events.Add(TJSONArray.Create(['trim', AAmount]));
end;

function TagLine(ATag: Integer): TTyTerminalLine;
begin
  Result := TTyTerminalLine.CreateDefault(1);
  Result.SetCellFromCodepoint(0, Cardinal(ATag), 1, TyTermDefaultAttr);
end;

function TagJson(ALine: TTyTerminalLine): TJSONData;
begin
  if ALine = nil then
    Result := TJSONNull.Create
  else
    Result := TJSONIntegerNumber.Create(Integer(ALine.GetCodePoint(0)));
end;

function RunListCase(ACase: TJSONObject; AMisses: TTyTermMisses): Integer;
var
  list: TTyTerminalLineList;
  rec: TListRec;
  ops, a, tags, items: TJSONArray;
  after: TJSONArray;
  st, state: TJSONObject;
  i, k: Integer;
  name, id: string;
  got: TJSONData;
  newLines: array of TTyTerminalLine;
begin
  id := ACase.Strings['id'];
  list := TTyTerminalLineList.Create(ACase.Objects['init'].Integers['max']);
  rec := TListRec.Create;
  list.OnInsert := @rec.OnInsert;
  list.OnDelete := @rec.OnDelete;
  list.OnTrim := @rec.OnTrim;
  try
    ops := ACase.Arrays['ops'];
    after := ACase.Arrays['after'];
    for i := 0 to ops.Count - 1 do
    begin
      a := ops.Arrays[i];
      name := a.Strings[0];
      rec.Events := TJSONArray.Create;
      got := nil;
      try
        try
          if name = 'push' then
            list.PushOwned(TagLine(a.Integers[1]))
          else if name = 'set' then
            list.SetItemOwned(a.Integers[1], TagLine(a.Integers[2]))
          else if name = 'splice' then
          begin
            tags := a.Arrays[3];
            newLines := nil;
            SetLength(newLines, tags.Count);
            for k := 0 to tags.Count - 1 do
              newLines[k] := TagLine(tags.Integers[k]);
            list.Splice(a.Integers[1], a.Integers[2], newLines);
            for k := 0 to High(newLines) do
              newLines[k].Release;
          end
          else if name = 'trimStart' then
            list.TrimStart(a.Integers[1])
          else if name = 'setMax' then
            list.MaxLength := a.Integers[1]
          else if name = 'setLength' then
            list.Length := a.Integers[1]
          else if name = 'recycle' then
            got := TagJson(list.Recycle)
          else if name = 'pop' then
            got := TagJson(list.Pop)
          else if name = 'get' then
            got := TagJson(list.Get(a.Integers[1]))
          else if name = 'shift' then
            list.ShiftElements(a.Integers[1], a.Integers[2], a.Integers[3])
          else
            raise EAbort.Create('unknown list op ' + name);
        except
          on E: EAbort do raise;
          on E: Exception do
          begin
            got.Free;
            got := TJSONString.Create('throws');
          end;
        end;
        st := after.Objects[i];
        if st.Find('ret') <> nil then
          TyTermCompareJson(st.Find('ret'), got, id, StepPath(i, a) + ' / ret', AMisses)
        else if got <> nil then
          AMisses.Add(id, StepPath(i, a) + ' / ret', '(none)', got.AsJSON);
        state := st.Objects['state'];
        items := TJSONArray.Create;
        try
          items.Add(list.Length);
          items.Add(list.MaxLength);
          items.Add(list.IsFull);
          TyTermCompareJson(state.Find('length'), items.Items[0], id, StepPath(i, a) + ' / length', AMisses);
          TyTermCompareJson(state.Find('maxLength'), items.Items[1], id, StepPath(i, a) + ' / maxLength', AMisses);
          TyTermCompareJson(state.Find('isFull'), items.Items[2], id, StepPath(i, a) + ' / isFull', AMisses);
          items.Clear;
          for k := 0 to list.Length - 1 do
            items.Add(TagJson(list.Get(k)));
          TyTermCompareJson(state.Find('items'), items, id, StepPath(i, a) + ' / items', AMisses);
          TyTermCompareJson(state.Find('events'), rec.Events, id, StepPath(i, a) + ' / events', AMisses);
        finally
          items.Free;
        end;
      finally
        got.Free;
        FreeAndNil(rec.Events);
      end;
    end;
    Result := ops.Count;
  finally
    list.Free;
    rec.Free;
  end;
end;

{ ---- buffer scripts ---------------------------------------------------------------- }

type
  TScrollRec = class
  public
    Scrolls: TJSONArray;
    procedure OnScroll(AYDisp: Integer);
  end;

procedure TScrollRec.OnScroll(AYDisp: Integer);
begin
  if Scrolls <> nil then
    Scrolls.Add(AYDisp);
end;

function WindowsPtyOf(AObj: TJSONObject): TTyTerminalWindowsPty;
begin
  Result.Backend := twpNone;
  Result.BuildNumber := 0;
  if (AObj = nil) then
    Exit;
  if AObj.Get('backend', '') = 'conpty' then
    Result.Backend := twpConPty
  else if AObj.Get('backend', '') = 'winpty' then
    Result.Backend := twpWinPty;
  Result.BuildNumber := AObj.Get('buildNumber', 0);
end;

function RunBuffersCase(ACase: TJSONObject; AMisses: TTyTermMisses): Integer;
var
  opts: TTyTerminalOptions;
  svc: TTyTerminalBufferService;
  links: TTyTerminalOscLinks;
  markers: TFPList;
  rec: TScrollRec;
  init, o, state, st: TJSONObject;
  ops, a, arr: TJSONArray;
  after: TJSONArray;
  i, k, first, last, col: Integer;
  name, id, path: string;
  got: TJSONData;
  buf: TTyTerminalBuffer;
  m: TTyTerminalMarker;
  ld: TTyTerminalLinkData;
  s: string;
begin
  id := ACase.Strings['id'];
  init := ACase.Objects['init'];
  o := nil;
  if init.Find('options') <> nil then
    o := init.Objects['options'];
  opts := TTyTerminalOptions.Create;
  if o <> nil then
  begin
    opts.Scrollback := o.Get('scrollback', 1000);
    opts.TabStopWidth := o.Get('tabStopWidth', 8);
    if o.Find('windowsPty') <> nil then
      opts.WindowsPty := WindowsPtyOf(o.Objects['windowsPty']);
  end;
  svc := TTyTerminalBufferService.Create(opts, init.Integers['cols'], init.Integers['rows']);
  links := TTyTerminalOscLinks.Create(svc);
  markers := TFPList.Create;
  rec := TScrollRec.Create;
  svc.OnScroll := @rec.OnScroll;
  try
    ops := ACase.Arrays['ops'];
    after := ACase.Arrays['after'];
    for i := 0 to ops.Count - 1 do
    begin
      a := ops.Arrays[i];
      name := a.Strings[0];
      path := StepPath(i, a);
      rec.Scrolls := TJSONArray.Create;
      got := nil;
      buf := svc.Buffer;
      try
        if name = 'scroll' then
          svc.Scroll(TyTermAttrFromJson(a.Objects[1]), a.Booleans[2])
        else if name = 'scrollLines' then
          svc.ScrollLines(a.Integers[1])
        else if name = 'resize' then
          svc.Resize(a.Integers[1], a.Integers[2])
        else if name = 'reset' then
          svc.Reset
        else if name = 'activateAlt' then
        begin
          if a.Items[1].JSONType = jtNull then
            svc.Buffers.ActivateAltBuffer
          else
            svc.Buffers.ActivateAltBuffer(TyTermAttrFromJson(a.Objects[1]));
        end
        else if name = 'activateNormal' then
          svc.Buffers.ActivateNormalBuffer
        else if name = 'setXY' then
        begin
          buf.X := a.Integers[1];
          buf.Y := a.Integers[2];
        end
        else if name = 'setMargins' then
        begin
          buf.ScrollTop := a.Integers[1];
          buf.ScrollBottom := a.Integers[2];
        end
        else if name = 'setYdisp' then
          buf.YDisp := a.Integers[1]
        else if name = 'saveX' then
          buf.SavedX := a.Integers[1]
        else if name = 'saveY' then
          buf.SavedY := a.Integers[1]
        else if name = 'text' then
        begin
          s := a.Strings[3];
          col := a.Integers[2];
          for k := 1 to Length(s) do
          begin
            buf.Lines.Get(a.Integers[1]).SetCellFromCodepoint(col, Ord(s[k]), 1, TyTermDefaultAttr);
            Inc(col);
          end;
        end
        else if name = 'setWrapped' then
          buf.Lines.Get(a.Integers[1]).IsWrapped := a.Booleans[2]
        else if name = 'setupTabStops' then
        begin
          if a.Items[1].JSONType = jtNull then buf.SetupTabStops else buf.SetupTabStops(a.Integers[1]);
        end
        else if name = 'tabSet' then
          buf.SetTab(a.Integers[1], True)
        else if name = 'tabClear' then
          buf.SetTab(a.Integers[1], False)
        else if name = 'tabClearAll' then
          buf.ClearAllTabs
        else if name = 'nextStop' then
        begin
          if a.Items[1].JSONType = jtNull then k := buf.NextStop else k := buf.NextStop(a.Integers[1]);
          got := TJSONIntegerNumber.Create(k);
        end
        else if name = 'prevStop' then
        begin
          if a.Items[1].JSONType = jtNull then k := buf.PrevStop else k := buf.PrevStop(a.Integers[1]);
          got := TJSONIntegerNumber.Create(k);
        end
        else if name = 'addMarker' then
        begin
          m := buf.AddMarker(a.Integers[1]);
          m.AddRef;
          markers.Add(m);
          got := TJSONIntegerNumber.Create(markers.Count - 1);
        end
        else if name = 'disposeMarker' then
          TTyTerminalMarker(markers[a.Integers[1]]).Dispose
        else if name = 'clearMarkers' then
          buf.ClearMarkers(a.Integers[1])
        else if name = 'clearAllMarkers' then
          buf.ClearAllMarkers
        else if name = 'wrappedRange' then
        begin
          buf.GetWrappedRangeForLine(a.Integers[1], first, last);
          got := TJSONArray.Create([first, last]);
        end
        else if name = 'setOption' then
        begin
          if a.Strings[1] = 'scrollback' then
          begin
            if opts.Scrollback <> a.Integers[2] then
            begin
              opts.Scrollback := a.Integers[2];
              svc.ScrollbackChanged;
            end;
          end
          else if a.Strings[1] = 'tabStopWidth' then
          begin
            if opts.TabStopWidth <> a.Integers[2] then
            begin
              opts.TabStopWidth := a.Integers[2];
              svc.TabStopWidthChanged;
            end;
          end
          else
            raise Exception.Create('unknown option ' + a.Strings[1]);
        end
        else if name = 'fillViewport' then
        begin
          if a.Items[1].JSONType = jtNull then buf.FillViewportRows else buf.FillViewportRows(TyTermAttrFromJson(a.Objects[1]));
        end
        else if name = 'clear' then
          buf.Clear
        else if name = 'registerLink' then
        begin
          ld.HasId := a.Items[1].JSONType <> jtNull;
          if ld.HasId then ld.Id := a.Strings[1] else ld.Id := '';
          ld.Uri := a.Strings[2];
          got := TJSONInt64Number.Create(links.RegisterLink(ld));
        end
        else if name = 'addLineToLink' then
          links.AddLineToLink(a.Integers[1], a.Integers[2])
        else if name = 'getLinkData' then
        begin
          if links.GetLinkData(a.Integers[1], ld) then
          begin
            arr := TJSONArray.Create;
            if ld.HasId then arr.Add(ld.Id) else arr.Add(TJSONNull.Create);
            arr.Add(ld.Uri);
            got := arr;
          end
          else
            got := TJSONNull.Create;
        end
        else
          raise Exception.Create('unknown buffers op ' + name);

        st := after.Objects[i];
        if st.Find('ret') <> nil then
          TyTermCompareJson(st.Find('ret'), got, id, path + ' / ret', AMisses)
        else if got <> nil then
          AMisses.Add(id, path + ' / ret', '(none)', got.AsJSON);
        state := st.Objects['state'];
        if svc.Buffers.IsAlt then s := 'alt' else s := 'normal';
        AMisses.AddCompared;
        if state.Strings['active'] <> s then
          AMisses.Add(id, path + ' / active', state.Strings['active'], s);
        AMisses.AddCompared;
        if state.Booleans['isUserScrolling'] <> svc.IsUserScrolling then
          AMisses.Add(id, path + ' / isUserScrolling', BoolToStr(state.Booleans['isUserScrolling'], True), BoolToStr(svc.IsUserScrolling, True));
        TyTermCompareJson(state.Find('scrolls'), rec.Scrolls, id, path + ' / scrolls', AMisses);
        TyTermCompareBuffer(svc.Buffers.Normal, state.Objects['buffers'].Objects['normal'], svc.Cols, id, path + ' / normal', AMisses);
        TyTermCompareBuffer(svc.Buffers.Alt, state.Objects['buffers'].Objects['alt'], svc.Cols, id, path + ' / alt', AMisses);
        arr := TJSONArray.Create;
        try
          for k := 0 to markers.Count - 1 do
            arr.Add(TJSONArray.Create([TTyTerminalMarker(markers[k]).Line, TTyTerminalMarker(markers[k]).IsDisposed]));
          TyTermCompareJson(state.Find('markers'), arr, id, path + ' / case markers', AMisses);
        finally
          arr.Free;
        end;
        arr := TyTermLinksJson(links);
        try
          TyTermCompareJson(state.Find('links'), arr, id, path + ' / links', AMisses);
        finally
          arr.Free;
        end;
      finally
        got.Free;
        FreeAndNil(rec.Scrolls);
      end;
    end;
    Result := ops.Count;
  finally
    svc.OnScroll := nil;
    svc.Free;
    links.Free;
    for k := 0 to markers.Count - 1 do
      TTyTerminalMarker(markers[k]).Release;
    markers.Free;
    rec.Free;
    opts.Free;
  end;
end;

{ ---- TTyTerminalBufferOracleTests -------------------------------------------------- }

procedure TTyTerminalBufferOracleTests.TestFixturesComeFromThePinnedUpstream;
var
  m: TTyTermMisses;
  fx: TTyTermFixtures;
  k: Integer;
begin
  m := TTyTermMisses.Create;
  try
    fx := TyTermLoadFixtures('buffer-ops', m);
    try
      for k := 0 to High(fx) do
        TyTermCheckUpstream(fx[k], 'buffer-ops', m);
    finally
      TyTermFreeFixtures(fx);
    end;
    AssertEquals(m.Text, 0, m.Count);
    AssertTrue('checked', m.Compared >= 2);
  finally
    m.Free;
  end;
end;

type
  TRunner = function(ACase: TJSONObject; AMisses: TTyTermMisses): Integer;

procedure RunTarget(ATest: TTestCase; const ATarget: string; ARunner: TRunner; AMinCases: Integer);
var
  m: TTyTermMisses;
  fx: TTyTermFixtures;
  cases: TFPList;
  c: TJSONObject;
  i, n, steps: Integer;
begin
  m := TTyTermMisses.Create;
  n := 0;
  steps := 0;
  try
    cases := LoadCases(m, fx);
    try
      for i := 0 to cases.Count - 1 do
      begin
        c := TJSONObject(cases[i]);
        if c.Strings['target'] <> ATarget then
          Continue;
        Inc(steps, ARunner(c, m));
        Inc(n);
      end;
    finally
      cases.Free;
      TyTermFreeFixtures(fx);
    end;
    TAssert.AssertEquals(m.Text, 0, m.Count);
    TAssert.AssertTrue(ATarget + ' cases read', n >= AMinCases);
    { at least one comparison per step, and more: every cell of every state }
    TAssert.AssertTrue(ATarget + ' comparisons', m.Compared > 2 * steps);
  finally
    m.Free;
  end;
end;

procedure TTyTerminalBufferOracleTests.TestLineOps;
begin
  RunTarget(Self, 'line', @RunLineCase, 20);
end;

procedure TTyTerminalBufferOracleTests.TestListOps;
begin
  RunTarget(Self, 'list', @RunListCase, 12);
end;

procedure TTyTerminalBufferOracleTests.TestBufferOps;
begin
  RunTarget(Self, 'buffers', @RunBuffersCase, 30);
end;

{ ---- TTyTerminalBufferTests --------------------------------------------------------- }

procedure TTyTerminalBufferTests.TestExtAttrsAccessors;

  procedure Check(const AWhat: string; const E: TTyTerminalExtAttrs; AExt: Cardinal; AStyle: Integer;
    AColor: Cardinal; AVariant: Integer; AEmpty: Boolean);
  begin
    AssertEquals(AWhat + ' Ext', Int64(AExt), Int64(E.Ext));
    AssertEquals(AWhat + ' UnderlineStyle', AStyle, E.UnderlineStyle);
    AssertEquals(AWhat + ' UnderlineColor', Int64(AColor), Int64(E.UnderlineColor));
    AssertEquals(AWhat + ' UnderlineVariantOffset', AVariant, E.UnderlineVariantOffset);
    AssertEquals(AWhat + ' IsEmpty', AEmpty, E.IsEmpty);
  end;

var
  e: TTyTerminalExtAttrs;
begin
  e := Default(TTyTerminalExtAttrs);
  Check('zero', e, 0, 0, 0, 0, True);
  e := Default(TTyTerminalExtAttrs);
  e.SetUnderlineStyle(3);
  Check('style 3', e, $0C000000, 3, 0, 0, False);
  e.UrlId := 5;
  Check('style 3 with a link', e, $14000000, 5, 0, 0, False);
  e := Default(TTyTerminalExtAttrs);
  e.SetUnderlineColor(-1);
  Check('colour -1', e, $03FFFFFF, 0, $03FFFFFF, 0, True);
  e := Default(TTyTerminalExtAttrs);
  e.SetUnderlineVariantOffset(3);
  Check('variant 3', e, $60000000, 0, 0, 3, True);
  e := Default(TTyTerminalExtAttrs);
  e.SetUnderlineVariantOffset(7);
  Check('variant 7 (negative path)', e, $E0000000, 0, 0, 7, True);
end;

{ distinct lines held by the ring's slots }
function DistinctSlotLines(AList: TTyTerminalLineList): Integer;
var
  seen: TFPList;
  i: Integer;
  ln: TTyTerminalLine;
begin
  seen := TFPList.Create;
  try
    for i := 0 to AList.MaxLength - 1 do
    begin
      ln := AList.SlotLine(i);
      if (ln <> nil) and (seen.IndexOf(ln) < 0) then
        seen.Add(ln);
    end;
    Result := seen.Count;
  finally
    seen.Free;
  end;
end;

procedure TTyTerminalBufferTests.TestLinesAreFreedWhenTheirOwnersGo;
var
  base, i: Integer;
  opts: TTyTerminalOptions;
  svc: TTyTerminalBufferService;
  list: TTyTerminalLineList;
  a, b: TTyTerminalLine;
begin
  base := TTyTerminalLine.LiveCount;
  opts := TTyTerminalOptions.Create;
  opts.Scrollback := 5;
  svc := TTyTerminalBufferService.Create(opts, 10, 3);
  try
    AssertEquals('the normal screen only', base + 3, TTyTerminalLine.LiveCount);
    svc.Buffer.Y := 2;
    for i := 1 to 100 do
      svc.Scroll(TyTermDefaultAttr);
    AssertEquals('ring lines', 8, svc.Buffers.Normal.Lines.Length);
    AssertEquals('ring + cached blank line', base + 8 + 1, TTyTerminalLine.LiveCount);
    svc.Buffers.ActivateAltBuffer;
    AssertEquals('alt screen filled', base + 8 + 1 + 3, TTyTerminalLine.LiveCount);
    svc.Buffers.ActivateNormalBuffer;
    AssertEquals('alt screen cleared', base + 8 + 1, TTyTerminalLine.LiveCount);
  finally
    svc.Free;
    opts.Free;
  end;
  AssertEquals('all freed with the service', base, TTyTerminalLine.LiveCount);

  list := TTyTerminalLineList.Create(4);
  try
    a := TTyTerminalLine.CreateDefault(2);
    b := TTyTerminalLine.CreateDefault(2);
    list.Push(a);
    list.Push(a);
    list.Push(b);
    AssertEquals('two lines, both still held by the test', base + 2, TTyTerminalLine.LiveCount);
    list.ShiftElements(0, 2, 1);
    { [a, a, b] shifted right by one from 0: every slot now holds a }
    AssertEquals('aliases after a shift', 1, DistinctSlotLines(list));
    a.Release;
    b.Release;
    AssertEquals('the ring keeps them', base + DistinctSlotLines(list), TTyTerminalLine.LiveCount);
    list.Splice(0, 2, []);
    AssertEquals('after a splice', base + DistinctSlotLines(list), TTyTerminalLine.LiveCount);
    list.MaxLength := 1;
    AssertEquals('after the ring shrank', base + DistinctSlotLines(list), TTyTerminalLine.LiveCount);
  finally
    list.Free;
  end;
  AssertEquals('all freed with the ring', base, TTyTerminalLine.LiveCount);
end;

procedure TTyTerminalBufferTests.TestTabStopsKeepStaleKeys;
var
  opts: TTyTerminalOptions;
  svc: TTyTerminalBufferService;
  tabs: TIntegerDynArray;

  function Text(const A: TIntegerDynArray): string;
  var
    i: Integer;
  begin
    Result := '';
    for i := 0 to High(A) do
    begin
      if i > 0 then Result := Result + ',';
      Result := Result + IntToStr(A[i]);
    end;
  end;

begin
  opts := TTyTerminalOptions.Create;
  opts.WindowsPty.Backend := twpConPty;
  opts.WindowsPty.BuildNumber := 19044;
  svc := TTyTerminalBufferService.Create(opts, 12, 3);
  try
    svc.Resize(7, 3);
    svc.Resize(20, 3);
    tabs := svc.Buffer.TabStops;
    AssertEquals('0,8,16', Text(tabs));
    svc.Buffer.SetTab(12, True);
    svc.Resize(10, 3);
    tabs := svc.Buffer.TabStops;
    AssertEquals('stale keys kept', '0,8,12,16', Text(tabs));
  finally
    svc.Free;
    opts.Free;
  end;
end;

initialization
  RegisterTest(TTyTerminalBufferOracleTests);
  RegisterTest(TTyTerminalBufferTests);
end.
