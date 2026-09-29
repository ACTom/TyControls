unit test.terminal.selection;
{$mode objfpc}{$H+}
{ tyControls.Terminal.Selection -- held to xterm.js 6.0.0.

  TTyTerminalSelectionOracleTests read tests/fixtures/terminal-selection.json
  (tools/terminal-oracle/selection-cases.js: upstream's SelectionService on a headless
  terminal). Every case runs on a new core with its own TTyTermSelection; each step
  does what the script did upstream -- the press routing of handleMouseDown (a right
  press keeps a selection, other buttons do nothing, a press while a program has the
  mouse selects only with Shift) is written out here, as the control writes it -- and
  after every step all twelve exported fields are compared. Lines trimmed off the top
  reach the selection the way the control passes them on: by the difference of the
  buffer's TrimmedLines after the step.

  TTyTerminalSelectionTests: the pixel rounding and drag-scroll speed against
  terminal-mouse-events.json, the same as readable tables, and OSC 52 against
  terminal-osc52.json (tools/terminal-oracle/clipboard-cases.js). }

interface

uses
  Classes, SysUtils, Types, fpcunit, testregistry, fpjson, sha1,
  tyControls.Terminal.Buffer, tyControls.Terminal.Core, tyControls.Terminal.Selection,
  test.terminal.oracle;

type
  TTyTerminalSelectionOracleTests = class(TTestCase)
  published
    procedure TestFixturesComeFromThePinnedUpstream;
    procedure TestEveryStepMatches;
    procedure TestAfterResetToo;
  end;

  TTyTerminalSelectionTests = class(TTestCase)
  published
    procedure TestSelectionPointsMatchGetCoords;
    procedure TestReportCellsMatchGetCoords;
    procedure TestDragAmountMatchesUpstream;
    procedure TestPixelTables;
    procedure TestOsc52Oracle;
    procedure TestOsc52Table;
  end;

{ JSON as compact text: null, true / false, integers, [a,b,...] }
function TySelCanon(AData: TJSONData): string;

implementation

const
  FieldCount = 12;

function TySelCanon(AData: TJSONData): string;
var
  i: Integer;
  a: TJSONArray;
begin
  if AData = nil then
    Exit('null');
  case AData.JSONType of
    jtNull: Result := 'null';
    jtBoolean: if AData.AsBoolean then Result := 'true' else Result := 'false';
    jtNumber: Result := IntToStr(AData.AsInt64);
    jtString: Result := '"' + AData.AsString + '"';
    jtArray:
      begin
        a := TJSONArray(AData);
        Result := '[';
        for i := 0 to a.Count - 1 do
        begin
          if i > 0 then Result := Result + ',';
          Result := Result + TySelCanon(a.Items[i]);
        end;
        Result := Result + ']';
      end;
  else
    Result := '?';
  end;
end;

function PointText(AHas: Boolean; const P: TTyTermSelPoint): string;
begin
  if not AHas then
    Result := 'null'
  else
    Result := Format('[%d,%d]', [P.Col, P.Row]);
end;

function BoolText(B: Boolean): string;
begin
  if B then Result := 'true' else Result := 'false';
end;

function Quoted(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    if (Ord(S[i]) < 32) or (S[i] = '\') then
      Result := Result + Format('\x%.2x', [Ord(S[i])])
    else
      Result := Result + S[i];
  Result := '"' + Result + '"';
end;

type
  { One case: a core, its selection, and what the harness keeps between steps. }
  TSelRun = class
  public
    Core: TTyTerminalCore;
    Sel: TTyTermSelection;
    Changes: Integer;
    TrimBase: Int64;
    Enabled: Boolean;
    HasLink: Boolean;
    Link: TTyTermLinkRange;
    CellH, Threshold: Integer;
    constructor Create(ACase: TJSONObject; ACellH, AThreshold: Integer);
    destructor Destroy; override;
    procedure OnChange(Sender: TObject);
    procedure OnActivate(Sender: TObject);
    procedure OnUser(Sender: TObject);
    procedure ResetHarness;
    { runs one step; the trimmed lines it saw }
    function Step(AStep: TJSONObject): Int64;
    { compares the state after a step with the fixture's `after` }
    procedure Compare(AAfter: TJSONObject; ATrimmed: Int64; const AId, APath: string;
      AMisses: TTyTermMisses; ASkipDrag: Boolean);
  end;

constructor TSelRun.Create(ACase: TJSONObject; ACellH, AThreshold: Integer);
begin
  inherited Create;
  Core := TTyTerminalCore.Create(ACase.Integers['cols'], ACase.Integers['rows']);
  Core.Scrollback := ACase.Integers['scrollback'];
  Sel := TTyTermSelection.Create(Core.BufferService);
  if ACase.Find('wordSeparator') <> nil then
    Sel.WordSeparators := UTF8Decode(ACase.Strings['wordSeparator']);
  Sel.OnChange := @OnChange;
  Core.OnBufferActivate := @OnActivate;
  Core.OnUserInput := @OnUser;
  CellH := ACellH;
  Threshold := AThreshold;
  ResetHarness;
end;

destructor TSelRun.Destroy;
begin
  Sel.Free;
  Core.Free;
  inherited Destroy;
end;

procedure TSelRun.OnChange(Sender: TObject);
begin
  Inc(Changes);
end;

{ SelectionService._handleBufferActivate :778-785: clear, listen to the new ring }
procedure TSelRun.OnActivate(Sender: TObject);
begin
  Sel.Clear;
  TrimBase := Core.Buffer.TrimmedLines;
end;

{ :139-143 }
procedure TSelRun.OnUser(Sender: TObject);
begin
  if Sel.HasSelection then
    Sel.Clear;
end;

procedure TSelRun.ResetHarness;
begin
  Enabled := True;
  HasLink := False;
  TrimBase := Core.Buffer.TrimmedLines;
end;

function Pt(ARun: TSelRun; AAt: TJSONArray): TTyTermSelPoint;
begin
  Result.Col := AAt.Integers[0];
  Result.Row := AAt.Integers[1] + ARun.Core.Buffer.YDisp;
end;

function TSelRun.Step(AStep: TJSONObject): Int64;
var
  p: TJSONObject;
  a: TJSONArray;
  button, detail, oldRows, n: Integer;
  shift, alt, en: Boolean;
  link: PTyTermLinkRange;
begin
  if HasLink then link := @Link else link := nil;
  if AStep.Find('write') <> nil then
    Core.WriteSync(TyTermBase64Bytes(AStep.Strings['write']))
  else if AStep.Find('resize') <> nil then
  begin
    a := AStep.Arrays['resize'];
    oldRows := Core.Rows;
    Core.Resize(a.Integers[0], a.Integers[1]);
    { :158-162: a new row count clears }
    if Core.Rows <> oldRows then
      Sel.Clear;
  end
  else if AStep.Find('scroll') <> nil then
    Core.ScrollLines(AStep.Integers['scroll'])
  else if AStep.Find('press') <> nil then
  begin
    p := AStep.Objects['press'];
    button := p.Integers['button'];
    detail := p.Integers['detail'];
    shift := p.Booleans['shift'];
    alt := p.Booleans['alt'];
    en := p.Booleans['enabled'];
    { enable() / disable() when the program's mouse state changed; disable clears }
    if en <> Enabled then
    begin
      if not en then
        Sel.Clear;
      Enabled := en;
    end;
    { handleMouseDown :457-478 }
    if (button = 2) and Sel.HasSelection then
    else if button <> 0 then
    else if not Enabled and not shift then
    else
      Sel.Press(Pt(Self, p.Arrays['at']), detail, Enabled and shift, alt, link);
  end
  else if AStep.Find('move') <> nil then
  begin
    p := AStep.Objects['move'];
    Sel.DragTo(Pt(Self, p.Arrays['at']),
      TyTermDragScrollAmount(p.Integers['py'], Core.Rows * CellH, Threshold));
  end
  else if AStep.Find('dragScroll') <> nil then
  begin
    n := Sel.DragScrollAmount;
    if n <> 0 then
      Core.ScrollLines(n);
    Sel.AfterDragScroll;
  end
  else if AStep.Find('release') <> nil then
    Sel.Release
  else if AStep.Find('rightClick') <> nil then
    Sel.RightClickSelect(Pt(Self, AStep.Objects['rightClick'].Arrays['at']), link)
  else if AStep.Find('link') <> nil then
  begin
    if AStep.Items[AStep.IndexOfName('link')].JSONType = jtNull then
      HasLink := False
    else
    begin
      a := AStep.Arrays['link'];
      Link.StartX := a.Integers[0];
      Link.StartY := a.Integers[1];
      Link.EndX := a.Integers[2];
      Link.EndY := a.Integers[3];
      HasLink := True;
    end;
  end
  else if AStep.Find('selectAll') <> nil then
    Sel.SelectAll
  else if AStep.Find('selectLines') <> nil then
    Sel.SelectLines(AStep.Arrays['selectLines'].Integers[0], AStep.Arrays['selectLines'].Integers[1])
  else if AStep.Find('setSelection') <> nil then
  begin
    a := AStep.Arrays['setSelection'];
    Sel.SetSelection(a.Integers[0], a.Integers[1], a.Integers[2]);
  end
  else if AStep.Find('clear') <> nil then
    Sel.Clear
  else if AStep.Find('userInput') <> nil then
    Core.Input('x', True)
  else
    raise Exception.Create('unknown step ' + AStep.AsJSON);
  { the lines trimmed off the top, passed on by their difference }
  Result := Core.Buffer.TrimmedLines - TrimBase;
  if Result > 0 then
    Sel.HandleTrim(Result);
  TrimBase := Core.Buffer.TrimmedLines;
end;

procedure TSelRun.Compare(AAfter: TJSONObject; ATrimmed: Int64; const AId, APath: string;
  AMisses: TTyTermMisses; ASkipDrag: Boolean);
var
  s, e: TTyTermSelPoint;
  hs, he: Boolean;
  got, want: string;
  r, a, b: Integer;
  m: TTyTermSelectionModel;

  procedure Check(const AField, AWant, AGot: string);
  begin
    AMisses.AddCompared;
    if AWant <> AGot then
      AMisses.Add(AId, APath + ' ' + AField, AWant, AGot);
  end;

begin
  hs := Sel.FinalStart(s);
  he := Sel.FinalEnd(e);
  Check('start', TySelCanon(AAfter.Find('start')), PointText(hs, s));
  Check('end', TySelCanon(AAfter.Find('end')), PointText(he, e));
  m := Sel.Model;
  got := '[' + PointText(m.HasStart, m.Start) + ',' + PointText(m.HasEnd, m.Finish) + ','
    + IntToStr(m.StartLength) + ',' + BoolText(m.IsSelectAllActive) + ']';
  Check('raw', TySelCanon(AAfter.Find('raw')), got);
  Check('mode', IntToStr(AAfter.Integers['mode']), IntToStr(Ord(Sel.Mode)));
  Check('has', BoolText(AAfter.Booleans['has']), BoolText(Sel.HasSelection));
  Check('text', Quoted(TyTermBase64Bytes(AAfter.Strings['text'])), Quoted(Sel.Text(#10)));
  Check('changes', IntToStr(AAfter.Integers['changes']), IntToStr(Changes));
  if ASkipDrag then
    AMisses.AddCompared
  else
    Check('dragAmount', IntToStr(AAfter.Integers['dragAmount']), IntToStr(Sel.DragAmount));
  Check('ydisp', IntToStr(AAfter.Integers['ydisp']), IntToStr(Core.Buffer.YDisp));
  Check('ybase', IntToStr(AAfter.Integers['ybase']), IntToStr(Core.Buffer.YBase));
  Check('trimmed', IntToStr(AAfter.Integers['trimmed']), IntToStr(ATrimmed));
  want := TySelCanon(AAfter.Find('spans'));
  got := '[';
  for r := 0 to Core.Rows - 1 do
  begin
    if r > 0 then got := got + ',';
    if Sel.RowSpan(Core.Buffer.YDisp + r, a, b) then
      got := got + Format('[%d,%d]', [a, b])
    else
      got := got + 'null';
  end;
  got := got + ']';
  Check('spans', want, got);
end;

{ ---- TTyTerminalSelectionOracleTests ---------------------------------------------- }

procedure TTyTerminalSelectionOracleTests.TestFixturesComeFromThePinnedUpstream;
const
  Kinds: array[0..3] of string = ('selection', 'links', 'osc52', 'mouse-events');
var
  miss: TTyTermMisses;
  fx: TTyTermFixtures;
  k, i: Integer;
begin
  miss := TTyTermMisses.Create;
  try
    for k := 0 to High(Kinds) do
    begin
      fx := TyTermLoadFixtures(Kinds[k], miss);
      try
        for i := 0 to High(fx) do
          TyTermCheckUpstream(fx[i], Kinds[k], miss);
        AssertEquals(Kinds[k] + ' parts', 1, Length(fx));
      finally
        TyTermFreeFixtures(fx);
      end;
    end;
    AssertEquals(miss.Text, 0, miss.Count);
    AssertEquals('comparisons', 8, miss.Compared);
  finally
    miss.Free;
  end;
end;

procedure TTyTerminalSelectionOracleTests.TestEveryStepMatches;
var
  miss: TTyTermMisses;
  fx: TTyTermFixtures;
  cases: TFPList;
  c: TJSONObject;
  steps: TJSONArray;
  run: TSelRun;
  i, k: Integer;
  total: Int64;
  trimmed: Int64;
begin
  miss := TTyTermMisses.Create;
  try
    fx := TyTermLoadFixtures('selection', miss);
    cases := TyTermAllCases(fx);
    try
      AssertEquals(miss.Text, 0, miss.Count);
      total := 0;
      for i := 0 to cases.Count - 1 do
      begin
        c := TJSONObject(cases[i]);
        steps := c.Arrays['steps'];
        run := TSelRun.Create(c, fx[0].Integers['cellHeight'], fx[0].Integers['dragThreshold']);
        try
          for k := 0 to steps.Count - 1 do
          begin
            run.Changes := 0;
            trimmed := run.Step(steps.Objects[k]);
            run.Compare(steps.Objects[k].Objects['after'], trimmed, c.Strings['id'],
              Format('step %d', [k]), miss, False);
            Inc(total);
          end;
        finally
          run.Free;
        end;
      end;
      AssertEquals(miss.Text, 0, miss.Count);
      AssertTrue('cases read', cases.Count > 100);
      AssertEquals('comparisons = steps x fields', total * FieldCount, miss.Compared);
    finally
      cases.Free;
      TyTermFreeFixtures(fx);
    end;
  finally
    miss.Free;
  end;
end;

{ The same selection object after the core's Reset runs the first three steps again
  and answers as a new one did. dragAmount is left out: upstream keeps the last drag's
  amount until the next press as well, so a used service differs from a new one there
  by design. }
procedure TTyTerminalSelectionOracleTests.TestAfterResetToo;
var
  miss: TTyTermMisses;
  fx: TTyTermFixtures;
  cases: TFPList;
  c: TJSONObject;
  steps: TJSONArray;
  run: TSelRun;
  i, k, n: Integer;
  total, trimmed: Int64;
begin
  miss := TTyTermMisses.Create;
  try
    fx := TyTermLoadFixtures('selection', miss);
    cases := TyTermAllCases(fx);
    try
      total := 0;
      for i := 0 to cases.Count - 1 do
      begin
        c := TJSONObject(cases[i]);
        steps := c.Arrays['steps'];
        run := TSelRun.Create(c, fx[0].Integers['cellHeight'], fx[0].Integers['dragThreshold']);
        try
          for k := 0 to steps.Count - 1 do
            run.Step(steps.Objects[k]);
          if (run.Core.Cols <> c.Integers['cols']) or (run.Core.Rows <> c.Integers['rows']) then
            run.Core.Resize(c.Integers['cols'], c.Integers['rows']);
          run.Core.Reset;
          run.ResetHarness;
          n := steps.Count;
          if n > 3 then n := 3;
          for k := 0 to n - 1 do
          begin
            run.Changes := 0;
            trimmed := run.Step(steps.Objects[k]);
            run.Compare(steps.Objects[k].Objects['after'], trimmed, c.Strings['id'],
              Format('after reset, step %d', [k]), miss, True);
            Inc(total);
          end;
        finally
          run.Free;
        end;
      end;
      AssertEquals(miss.Text, 0, miss.Count);
      AssertTrue('steps compared', total > 100);
      AssertEquals('comparisons = steps x fields', total * FieldCount, miss.Compared);
    finally
      cases.Free;
      TyTermFreeFixtures(fx);
    end;
  finally
    miss.Free;
  end;
end;

{ ---- TTyTerminalSelectionTests ---------------------------------------------------- }

procedure TTyTerminalSelectionTests.TestSelectionPointsMatchGetCoords;
var
  miss: TTyTermMisses;
  fx: TTyTermFixtures;
  rows: TJSONArray;
  r: TJSONArray;
  i, cols, nrows: Integer;
  p: TPoint;
  n: Int64;
begin
  miss := TTyTermMisses.Create;
  try
    fx := TyTermLoadFixtures('mouse-events', miss);
    try
      cols := fx[0].Integers['cols'];
      nrows := fx[0].Integers['rows'];
      rows := fx[0].Arrays['coords'];
      n := 0;
      for i := 0 to rows.Count - 1 do
      begin
        r := rows.Arrays[i];
        if r.Integers[2] <> 1 then
          Continue;
        p := TyTermSelectionPointAt(r.Integers[3], r.Integers[4], r.Integers[0], r.Integers[1], cols, nrows);
        miss.AddCompared;
        Inc(n);
        if (p.X <> r.Integers[5] - 1) or (p.Y <> r.Integers[6] - 1) then
          miss.Add(Format('cell %dx%d px %d py %d', [r.Integers[0], r.Integers[1], r.Integers[3], r.Integers[4]]),
            'point', Format('%d,%d', [r.Integers[5] - 1, r.Integers[6] - 1]), Format('%d,%d', [p.X, p.Y]));
      end;
      AssertEquals(miss.Text, 0, miss.Count);
      AssertTrue('rows read', n > 1000);
      AssertEquals('comparisons', n, miss.Compared);
    finally
      TyTermFreeFixtures(fx);
    end;
  finally
    miss.Free;
  end;
end;

{ Phase 3's cell rule (the control's CellAt: floor, clamped) is upstream's reporting
  rule: held here with the same formula, so a change of the rule upstream shows. }
procedure TTyTerminalSelectionTests.TestReportCellsMatchGetCoords;
var
  miss: TTyTermMisses;
  fx: TTyTermFixtures;
  rows, r: TJSONArray;
  i, cols, nrows, x, y, cw, ch, px, py: Integer;
  n: Int64;
begin
  miss := TTyTermMisses.Create;
  try
    fx := TyTermLoadFixtures('mouse-events', miss);
    try
      cols := fx[0].Integers['cols'];
      nrows := fx[0].Integers['rows'];
      rows := fx[0].Arrays['coords'];
      n := 0;
      for i := 0 to rows.Count - 1 do
      begin
        r := rows.Arrays[i];
        if r.Integers[2] <> 0 then
          Continue;
        cw := r.Integers[0];
        ch := r.Integers[1];
        px := r.Integers[3];
        py := r.Integers[4];
        if px < 0 then x := 0 else x := px div cw;
        if py < 0 then y := 0 else y := py div ch;
        if x > cols - 1 then x := cols - 1;
        if y > nrows - 1 then y := nrows - 1;
        miss.AddCompared;
        Inc(n);
        if (x <> r.Integers[5] - 1) or (y <> r.Integers[6] - 1) then
          miss.Add(Format('cell %dx%d px %d py %d', [cw, ch, px, py]), 'cell',
            Format('%d,%d', [r.Integers[5] - 1, r.Integers[6] - 1]), Format('%d,%d', [x, y]));
      end;
      AssertEquals(miss.Text, 0, miss.Count);
      AssertTrue('rows read', n > 1000);
      AssertEquals('comparisons', n, miss.Compared);
    finally
      TyTermFreeFixtures(fx);
    end;
  finally
    miss.Free;
  end;
end;

procedure TTyTerminalSelectionTests.TestDragAmountMatchesUpstream;
var
  miss: TTyTermMisses;
  fx: TTyTermFixtures;
  rows, r: TJSONArray;
  i, got: Integer;
begin
  miss := TTyTermMisses.Create;
  try
    fx := TyTermLoadFixtures('mouse-events', miss);
    try
      rows := fx[0].Arrays['dragAmount'];
      for i := 0 to rows.Count - 1 do
      begin
        r := rows.Arrays[i];
        got := TyTermDragScrollAmount(r.Integers[1], r.Integers[0], TyTermDragScrollMaxThreshold);
        miss.AddCompared;
        if got <> r.Integers[2] then
          miss.Add(Format('H %d py %d', [r.Integers[0], r.Integers[1]]), 'amount', IntToStr(r.Integers[2]),
            IntToStr(got));
      end;
      AssertEquals(miss.Text, 0, miss.Count);
      AssertTrue('rows read', rows.Count > 500);
      AssertEquals('comparisons', rows.Count, miss.Compared);
      { the threshold is the parameter, not a constant: at 75 the full speed is 75 out }
      AssertEquals('threshold 75, 75 below', 15, TyTermDragScrollAmount(140 + 75, 140, 75));
      AssertEquals('threshold 75, 50 below', 10, TyTermDragScrollAmount(140 + 50, 140, 75));
    finally
      TyTermFreeFixtures(fx);
    end;
  finally
    miss.Free;
  end;
end;

procedure TTyTerminalSelectionTests.TestPixelTables;
const
  Px: array[0..8] of Integer = (-4, -1, 0, 3, 4, 10, 11, 69, 100);
  WantX: array[0..8] of Integer = (0, 0, 0, 0, 1, 1, 2, 10, 10);
  Py: array[0..5] of Integer = (-1, 0, 13, 14, 69, 70);
  WantY: array[0..5] of Integer = (0, 0, 0, 1, 4, 4);
  Dy: array[0..9] of Integer = (-100, -26, -1, 0, 70, 139, 140, 141, 165, 300);
  WantD: array[0..9] of Integer = (-15, -8, -1, 0, 0, 0, 1, 1, 8, 15);
var
  i: Integer;
begin
  for i := 0 to High(Px) do
    AssertEquals(Format('x at px %d', [Px[i]]), WantX[i], TyTermSelectionPointAt(Px[i], 0, 7, 14, 10, 5).X);
  for i := 0 to High(Py) do
    AssertEquals(Format('y at py %d', [Py[i]]), WantY[i], TyTermSelectionPointAt(0, Py[i], 7, 14, 10, 5).Y);
  for i := 0 to High(Dy) do
    AssertEquals(Format('speed at %d', [Dy[i]]), WantD[i], TyTermDragScrollAmount(Dy[i], 140, 50));
end;

{ mulberry32 bytes (lib-term.js prng; clipboard-cases.js bigData): a byte is the top 8
  bits of the 32-bit output }
function PrngBytes(ASeed: Cardinal; ACount: Integer): RawByteString;
var
  a, t: Cardinal;
  i: Integer;
begin
  SetLength(Result, ACount);
  a := ASeed;
  {$push}{$Q-}{$R-}
  for i := 1 to ACount do
  begin
    a := a + $6D2B79F5;
    t := a;
    t := (t xor (t shr 15)) * (t or 1);
    t := t xor (t + (t xor (t shr 7)) * (t or 61));
    t := t xor (t shr 14);
    Result[i] := Chr(t shr 24);
  end;
  {$pop}
end;

function Sha1Hex(const S: RawByteString): string;
begin
  Result := LowerCase(SHA1Print(SHA1String(S)));
end;

procedure TTyTerminalSelectionTests.TestOsc52Oracle;
var
  miss: TTyTermMisses;
  fx: TTyTermFixtures;
  cases: TFPList;
  c, big: TJSONObject;
  writes, replies: TJSONArray;
  i: Integer;
  data, pc, pd, readText, got, want: string;
  wantWrites, gotWrites, wantReplies, gotReplies: string;
begin
  miss := TTyTermMisses.Create;
  try
    fx := TyTermLoadFixtures('osc52', miss);
    cases := TyTermAllCases(fx);
    try
      readText := TyTermBase64Bytes(fx[0].Strings['readText']);
      for i := 0 to cases.Count - 1 do
      begin
        c := TJSONObject(cases[i]);
        writes := c.Arrays['writes'];
        replies := c.Arrays['replies'];
        if c.Find('data') = nil then
        begin
          { the long one: rebuilt from its seed, hashed }
          big := c;
          data := 'c;' + TyTermBase64Encode(PrngBytes(big.Integers['seed'], big.Integers['bytes']));
          miss.AddCompared;
          if (Length(data) <> big.Integers['dataLength']) or (Sha1Hex(data) <> big.Strings['dataSha1']) then
            miss.Add('long', 'data', 'the seed''s data', 'other data');
          AssertTrue('split', TyTermOsc52Split(data, pc, pd));
          got := TyTermOsc52Decode(pd);
          miss.AddCompared;
          want := Format('%d %s', [writes.Arrays[0].Objects[1].Integers['length'], writes.Arrays[0].Objects[1].Strings['sha1']]);
          if want <> Format('%d %s', [Length(got), Sha1Hex(got)]) then
            miss.Add('long', 'write', want, Format('%d %s', [Length(got), Sha1Hex(got)]));
          Continue;
        end;
        data := c.Strings['data'];
        wantWrites := '';
        if writes.Count > 0 then
          wantWrites := writes.Arrays[0].Strings[0] + '|' + Quoted(TyTermBase64Bytes(writes.Arrays[0].Strings[1]));
        wantReplies := '';
        if replies.Count > 0 then
          wantReplies := Quoted(TyTermBase64Bytes(replies.Arrays[0].Strings[0])) + ' '
            + BoolText(replies.Arrays[0].Booleans[1]);
        gotWrites := '';
        gotReplies := '';
        if TyTermOsc52Split(data, pc, pd) then
        begin
          if pd = '?' then
            gotReplies := Quoted(TyTermOsc52Reply(pc, readText)) + ' false'
          else
            gotWrites := pc + '|' + Quoted(TyTermOsc52Decode(pd));
        end;
        miss.AddCompared(2);
        if (writes.Count > 1) or (replies.Count > 1) then
          miss.Add(Quoted(data), 'count', 'at most one each', 'more');
        if wantWrites <> gotWrites then
          miss.Add(Quoted(data), 'write', wantWrites, gotWrites);
        if wantReplies <> gotReplies then
          miss.Add(Quoted(data), 'reply', wantReplies, gotReplies);
      end;
      AssertEquals(miss.Text, 0, miss.Count);
      AssertTrue('cases read', cases.Count > 40);
      AssertEquals('comparisons', Int64(cases.Count - 1) * 2 + 2, miss.Compared);
    finally
      cases.Free;
      TyTermFreeFixtures(fx);
    end;
  finally
    miss.Free;
  end;
end;

procedure TTyTerminalSelectionTests.TestOsc52Table;
var
  pc, pd: string;
begin
  AssertEquals('empty text', #27']52;c;'#7, TyTermOsc52Reply('c', ''));
  AssertEquals('hi', #27']52;c;aGk='#7, TyTermOsc52Reply('c', 'hi'));
  AssertEquals('a CJK character', #27']52;p;5Lit'#7, TyTermOsc52Reply('p', #$E4#$B8#$AD));
  AssertFalse('one field', TyTermOsc52Split('c', pc, pd));
  AssertTrue('two', TyTermOsc52Split('c;aGk=;x', pc, pd));
  AssertEquals('Pc', 'c', pc);
  AssertEquals('Pd stops at the next ;', 'aGk=', pd);
  AssertEquals('decoded', 'hi', TyTermOsc52Decode('aGk'));
  AssertEquals('not base64', '', TyTermOsc52Decode('a$'));
end;

initialization
  RegisterTest(TTyTerminalSelectionOracleTests);
  RegisterTest(TTyTerminalSelectionTests);
end.
