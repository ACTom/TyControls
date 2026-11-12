unit test.richedit.model;

{ The document model under TTyRichEdit: interned formats, paragraphs of runs hung on the text
  storage's paragraph slots, objects, tables, on-demand parsing, and the primitives commands
  are built from - each must be revertible exactly, also after the deleted paragraphs' values
  have spent several edits in an undo record. The primitives are protected; TDocAccess
  reaches them. }

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, Graphics, fpcunit, testregistry,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model;

type
  TDocAccess = class(TTyRichDocument)
  end;

  TCountedOpaque = class(TTyRichOpaque)
  public
    class var Live: Integer;
    constructor Create(const ABytes: RawByteString);
    destructor Destroy; override;
  end;

  TCountedTable = class(TTyRichTable)
  public
    class var Live: Integer;
    constructor Create(const AColBoundaries: array of Integer);
    destructor Destroy; override;
  end;

  { Gives every paragraph it parses ParaFmt and one run in CharFmt, records which paragraphs
    it was asked for, and with AlsoNext parses the following paragraph as well. }
  TFakeLoader = class(TTyRichParaLoader)
  public
    Calls: TStringList;
    ParaFmt: TTyParaFormatId;
    CharFmt: TTyCharFormatId;
    AlsoNext: Boolean;
    LeavePlain: Integer;
    NextWasSet: Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure LoadParagraph(ADoc: TTyRichDocument; AIndex: Integer); override;
  end;

  TTyRichModelTest = class(TTestCase)
  private
    FChanges: array of TTyRichChange;
    procedure DocChanged(Sender: TObject; const AChange: TTyRichChange);
    function NewDoc(const AText: UTF8String): TDocAccess;
    function NewSample: TDocAccess;
    function ColorId(ADoc: TTyRichDocument; AColor: TColor): TTyCharFormatId;
    function AlignId(ADoc: TTyRichDocument; AAlign: TTyParaAlign): TTyParaFormatId;
    procedure Paint(ADoc: TDocAccess; APos, ALen: TTyRichPos; AColor: TColor);
    procedure Align(ADoc: TDocAccess; AFirst, ALast: Integer; AAlign: TTyParaAlign);
    function RunsStr(ADoc: TTyRichDocument; AIndex: Integer): string;
    function SampleRuns(ADoc: TTyRichDocument; const AFmt: string;
      const AColors: array of TColor): string;
    function ParaText(ADoc: TTyRichDocument; AIndex: Integer): UTF8String;
    function Dump(ADoc: TTyRichDocument): string;
    function UndoScenario(ACycles: Integer): string;
    procedure CheckTable(ADoc: TDocAccess; AT1, AT2: TTyRichTable; AFirst: Integer;
      ASplitCell: Boolean; const AWhen: string);
    procedure CheckChange(const AWhat: string; AIndex: Integer; AKinds: TTyRichChangeKinds;
      APos, AOldLen, ANewLen: TTyRichPos; AFirstPara, AOldCount, ANewCount: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEqualFormatsShareAnId;
    procedure TestPlainParagraphsAllocateNothing;
    procedure TestRunsFollowEditsInsideTheParagraph;
    procedure TestObjectIsOneCharacter;
    procedure TestCharFormatChangesOnlyTheMaskedFields;
    procedure TestRevertGivesBackRunsFormatsAndObjects;
    procedure TestLoaderParsesOnlyWhatIsAsked;
    procedure TestTableSurvivesEditsBeforeIt;
    procedure TestChangesAreReported;
    procedure TestDocumentDefaults;
    procedure TestEditsThroughTextKeepRunsInside;
    procedure TestTableIndexesAndEmptyTablesAreRefused;
  end;

implementation

function Bytes(const S: UTF8String): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if Length(S) > 0 then Move(S[1], Result[0], Length(S));
end;

{ ---- helpers ---- }

constructor TCountedOpaque.Create(const ABytes: RawByteString);
begin
  inherited Create(ABytes);
  Inc(Live);
end;

destructor TCountedOpaque.Destroy;
begin
  Dec(Live);
  inherited Destroy;
end;

constructor TCountedTable.Create(const AColBoundaries: array of Integer);
begin
  inherited Create(AColBoundaries);
  Inc(Live);
end;

destructor TCountedTable.Destroy;
begin
  Dec(Live);
  inherited Destroy;
end;

constructor TFakeLoader.Create;
begin
  inherited Create;
  Calls := TStringList.Create;
  LeavePlain := -1;
end;

destructor TFakeLoader.Destroy;
begin
  Calls.Free;
  inherited Destroy;
end;

procedure TFakeLoader.LoadParagraph(ADoc: TTyRichDocument; AIndex: Integer);
var
  runs: TTyRunArray;
begin
  Calls.Add(IntToStr(AIndex));
  if AIndex = LeavePlain then Exit;
  runs := nil;
  SetLength(runs, 1);
  runs[0].Start := 0;
  runs[0].Format := CharFmt;
  runs[0].Obj := nil;
  SetParagraph(ADoc, AIndex, ParaFmt, runs);
  NextWasSet := False;
  if AlsoNext and (AIndex + 1 < ADoc.Text.ParaCount) then
    NextWasSet := SetParagraph(ADoc, AIndex + 1, ParaFmt, runs);
end;

procedure TTyRichModelTest.SetUp;
begin
  FChanges := nil;
  TCountedOpaque.Live := 0;
  TCountedTable.Live := 0;
end;

procedure TTyRichModelTest.TearDown;
begin
  FChanges := nil;
end;

procedure TTyRichModelTest.DocChanged(Sender: TObject; const AChange: TTyRichChange);
begin
  SetLength(FChanges, Length(FChanges) + 1);
  FChanges[High(FChanges)] := AChange;
end;

function TTyRichModelTest.NewDoc(const AText: UTF8String): TDocAccess;
begin
  Result := TDocAccess.CreateFromUtf8(Bytes(AText));
end;

function TTyRichModelTest.ColorId(ADoc: TTyRichDocument; AColor: TColor): TTyCharFormatId;
var
  f: TTyCharFormat;
begin
  f := ADoc.DefaultCharFormat;
  f.Color := AColor;
  Result := ADoc.Formats.InternChar(f);
end;

function TTyRichModelTest.AlignId(ADoc: TTyRichDocument; AAlign: TTyParaAlign): TTyParaFormatId;
var
  f: TTyParaFormat;
begin
  f := TyDefaultParaFormat;
  f.Align := AAlign;
  Result := ADoc.Formats.InternPara(f);
end;

procedure TTyRichModelTest.Paint(ADoc: TDocAccess; APos, ALen: TTyRichPos; AColor: TColor);
var
  f: TTyCharFormat;
  u: TTyRichUndoData;
begin
  f := TyDefaultCharFormat;
  f.Color := AColor;
  u := ADoc.ApplyCharFormat(APos, ALen, [cffColor], f);
  u.Free;
end;

procedure TTyRichModelTest.Align(ADoc: TDocAccess; AFirst, ALast: Integer; AAlign: TTyParaAlign);
var
  f: TTyParaFormat;
  u: TTyRichUndoData;
begin
  f := TyDefaultParaFormat;
  f.Align := AAlign;
  u := ADoc.ApplyParaFormat(AFirst, ALast, [pffAlign], f);
  u.Free;
end;

function TTyRichModelTest.RunsStr(ADoc: TTyRichDocument; AIndex: Integer): string;
var
  r: TTyRunArray;
  i: Integer;
begin
  r := ADoc.RunsOf(AIndex);
  Result := '';
  for i := 0 to High(r) do
  begin
    if i > 0 then Result := Result + ' ';
    Result := Result + IntToStr(r[i].Start) + ':' + IntToStr(r[i].Format);
    if r[i].Obj <> nil then Result := Result + '@' + IntToHex(PtrUInt(r[i].Obj), 1);
  end;
end;

{ AFmt with %d where the colours' ids go, e.g. '0:%d 3:%d'. }
function TTyRichModelTest.SampleRuns(ADoc: TTyRichDocument; const AFmt: string;
  const AColors: array of TColor): string;
var
  ids: array of TVarRec;
  vals: array of Integer;
  i: Integer;
begin
  vals := nil;
  ids := nil;
  SetLength(vals, Length(AColors));
  SetLength(ids, Length(AColors));
  for i := 0 to High(AColors) do
  begin
    if AColors[i] = clDefault then vals[i] := ADoc.DefaultCharFormatId
    else vals[i] := ColorId(ADoc, AColors[i]);
    ids[i].VType := vtInteger;
    ids[i].VInteger := vals[i];
  end;
  Result := Format(AFmt, ids);
end;

function TTyRichModelTest.ParaText(ADoc: TTyRichDocument; AIndex: Integer): UTF8String;
begin
  Result := ADoc.Text.GetText(ADoc.Text.ParaStart(AIndex), ADoc.Text.ParaLength(AIndex));
end;

function TTyRichModelTest.Dump(ADoc: TTyRichDocument): string;
var
  i: Integer;
  t: TTyRichTable;
begin
  Result := '';
  for i := 0 to ADoc.Text.ParaCount - 1 do
  begin
    t := ADoc.TableAt(i);
    Result := Result + Format('[%s] P%d {%s}', [ParaText(ADoc, i), ADoc.ParaFormatOf(i),
      RunsStr(ADoc, i)]);
    if t <> nil then Result := Result + ' T' + IntToHex(PtrUInt(t), 1);
    Result := Result + LineEnding;
  end;
end;

{ The sample: three paragraphs, 'aaabbbccc' red/green/blue centred, 'dddeee' blue/yellow
  right-aligned, 'fff' plain justified. p0 is 0..8, its separator 9; p1 10..15, separator 16;
  p2 17..19. }
function TTyRichModelTest.NewSample: TDocAccess;
begin
  Result := NewDoc('aaabbbccc'#13#10'dddeee'#13#10'fff');
  Paint(Result, 0, 3, clRed);
  Paint(Result, 3, 3, clGreen);
  Paint(Result, 6, 3, clBlue);
  Paint(Result, 10, 3, clBlue);
  Paint(Result, 13, 3, clYellow);
  Align(Result, 0, 0, paraCenter);
  Align(Result, 1, 1, paraRight);
  Align(Result, 2, 2, paraJustify);
  Result.Modified := False;
end;

procedure TTyRichModelTest.CheckChange(const AWhat: string; AIndex: Integer;
  AKinds: TTyRichChangeKinds; APos, AOldLen, ANewLen: TTyRichPos; AFirstPara, AOldCount,
  ANewCount: Integer);
var
  c: TTyRichChange;
begin
  AssertTrue(AWhat + ': change reported', AIndex <= High(FChanges));
  c := FChanges[AIndex];
  AssertTrue(AWhat + ': kinds', c.Kinds = AKinds);
  AssertEquals(AWhat + ': pos', APos, c.Pos);
  AssertEquals(AWhat + ': old length', AOldLen, c.OldLen);
  AssertEquals(AWhat + ': new length', ANewLen, c.NewLen);
  AssertEquals(AWhat + ': first paragraph', AFirstPara, c.FirstPara);
  AssertEquals(AWhat + ': old paragraphs', AOldCount, c.OldParaCount);
  AssertEquals(AWhat + ': new paragraphs', ANewCount, c.NewParaCount);
end;

{ ---- formats ---- }

procedure TTyRichModelTest.TestEqualFormatsShareAnId;
var
  pool: TTyFormatPool;
  a, b: TTyCharFormat;
  p, q: TTyParaFormat;
  ida, idp, i, id: Integer;
begin
  pool := TTyFormatPool.Create;
  try
    a := TyDefaultCharFormat;
    a.FontName := '宋体';
    a.Charset := 134;
    a.SizeHalfPt := 24;
    a.Style := [fsBold];
    a.Color := clRed;
    a.Extra.Add('\expnd2');
    ida := pool.InternChar(a);
    b := a;
    AssertEquals('the same value, the same id', ida, pool.InternChar(b));
    b := TyDefaultCharFormat;
    b.FontName := '宋' + '体';
    b.Charset := 134;
    b.SizeHalfPt := 24;
    b.Style := [fsBold];
    b.Color := clRed;
    b.Extra.Add('\exp' + 'nd2');
    AssertTrue('equal values built apart are equal', a.Equals(b));
    AssertEquals('equal values built apart share the id', ida, pool.InternChar(b));
    AssertTrue('the pool gives the value back', pool.CharFormat(ida).Equals(a));
    for i := 0 to 9 do
    begin
      b := a;
      case i of
        0: b.FontName := 'SimSun';
        1: b.Charset := 0;
        2: b.SizeHalfPt := 22;
        3: b.Style := [fsBold, fsItalic];
        4: b.Strike := True;
        5: b.VertAlign := vaSuper;
        6: b.Color := clBlue;
        7: b.HighlightColor := clYellow;
        8: b.Extra.Add('\kerning1');
        9: begin b.Extra.Clear; b.Extra.Add('\expnd3'); end;
      end;
      AssertFalse(Format('char field %d: not equal', [i]), b.Equals(a));
      AssertFalse(Format('char field %d: not equal the other way', [i]), a.Equals(b));
      id := pool.InternChar(b);
      AssertTrue(Format('char field %d: a new id', [i]), id <> ida);
      AssertEquals(Format('char field %d: stable', [i]), id, pool.InternChar(b));
    end;
    b := a;
    b.Style := [fsBold, fsStrikeOut];
    a.Strike := True;
    AssertEquals('strike-through in Style is Strike', pool.InternChar(a), pool.InternChar(b));

    p := TyDefaultParaFormat;
    p.Align := paraCenter;
    p.LeftIndent := 720;
    SetLength(p.Tabs, 2);
    p.Tabs[0].Position := 1440;
    p.Tabs[1].Position := 2880;
    p.Tabs[1].Align := ttaDecimal;
    p.List.Kind := lkDecimal;
    p.List.StartAt := 3;
    p.Extra.Add('\keepn');
    idp := pool.InternPara(p);
    q := p;
    q.Tabs := Copy(p.Tabs);
    AssertEquals('the same paragraph format, the same id', idp, pool.InternPara(q));
    for i := 0 to 17 do
    begin
      q := p;
      q.Tabs := Copy(p.Tabs);
      case i of
        0: q.Align := paraJustify;
        1: q.LeftIndent := 360;
        2: q.RightIndent := 100;
        3: q.FirstIndent := -360;
        4: q.SpaceBefore := 120;
        5: q.SpaceAfter := 240;
        6: q.LineSpacing := lsDouble;
        7: q.LineSpacingValue := 300;
        8: q.Tabs[0].Position := 1000;
        9: q.Tabs[0].Align := ttaRight;
        10: q.Tabs[1].Leader := ttlDot;
        11: SetLength(q.Tabs, 1);
        12: q.List.Kind := lkBullet;
        13: q.List.Level := 1;
        14: q.List.StartAt := 1;
        15: q.RtlPar := True;
        16: q.Extra.Add('\keep');
        17: q.Extra.Clear;
      end;
      AssertFalse(Format('para field %d: not equal', [i]), q.Equals(p));
      AssertFalse(Format('para field %d: not equal the other way', [i]), p.Equals(q));
      id := pool.InternPara(q);
      AssertTrue(Format('para field %d: a new id', [i]), id <> idp);
      AssertEquals(Format('para field %d: stable', [i]), id, pool.InternPara(q));
    end;
    q := pool.ParaFormat(idp);
    q.Tabs[0].Position := 1;
    AssertEquals('changing a returned format leaves the pool alone', 1440,
      pool.ParaFormat(idp).Tabs[0].Position);
    p.Tabs[0].Position := 7;
    AssertEquals('changing the interned value leaves the pool alone', 1440,
      pool.ParaFormat(idp).Tabs[0].Position);
  finally
    pool.Free;
  end;
end;

{ ---- plain paragraphs ---- }

procedure TTyRichModelTest.TestPlainParagraphsAllocateNothing;
const
  Count = 2000000;
  Line: UTF8String = 'plain 中文'#13#10;
var
  buf: TBytes;
  i, sum, defId: Integer;
  t: TTyRichText;
  d: TDocAccess;
  u: TTyRichUndoData;
  h0, textBytes, docBytes: Int64;
begin
  buf := nil;
  SetLength(buf, Count * Length(Line));
  for i := 0 to Count - 1 do Move(Line[1], buf[i * Length(Line)], Length(Line));
  h0 := GetFPCHeapStatus.CurrHeapUsed;
  t := TTyRichText.CreateFromUtf8(buf);
  textBytes := GetFPCHeapStatus.CurrHeapUsed - h0;
  t.Free;
  h0 := GetFPCHeapStatus.CurrHeapUsed;
  d := TDocAccess.CreateFromUtf8(buf);
  try
    AssertEquals('paragraphs', Count + 1, d.Text.ParaCount);
    defId := d.DefaultParaFormatId;
    sum := 0;
    for i := 0 to d.Text.ParaCount - 1 do
      if d.ParaFormatOf(i) <> defId then Inc(sum);
    AssertEquals('every paragraph is in the default format', 0, sum);
    i := 0;
    while i < d.Text.ParaCount do
    begin
      if (Length(d.RunsOf(i)) <> 1) or (d.TableAt(i) <> nil) then Inc(sum);
      Inc(i, 97);
    end;
    AssertEquals('one default run, no table', 0, sum);
    // plain edits keep plain paragraphs plain
    u := d.InsertText(d.Text.ParaStart(1000) + 2, 'typed');
    u.Free;
    u := d.InsertText(d.Text.ParaStart(1500), 'new'#13#10'lines'#13#10);
    u.Free;
    u := d.DeleteRange(d.Text.ParaStart(2000) + 3, 30);
    u.Free;
    docBytes := GetFPCHeapStatus.CurrHeapUsed - h0;
    AssertEquals('no paragraph value was made', 0, d.LiveParaData);
    AssertTrue(Format('the document allocated %d bytes beyond the text''s %d',
      [docBytes - textBytes, textBytes]), docBytes - textBytes <= 2 * 1024 * 1024);
  finally
    d.Free;
  end;
end;

{ ---- runs ---- }

procedure TTyRichModelTest.TestRunsFollowEditsInsideTheParagraph;
var
  d: TDocAccess;
  u: TTyRichUndoData;
begin
  // typing inside a run: the runs after it move right
  d := NewSample;
  try
    u := d.InsertText(4, 'XY');
    u.Free;
    AssertEquals('text', 'aaabXYbbccc', ParaText(d, 0));
    AssertEquals('runs after the insert move right',
      SampleRuns(d, '0:%d 3:%d 8:%d', [clRed, clGreen, clBlue]), RunsStr(d, 0));
    AssertEquals('the next paragraph is untouched',
      SampleRuns(d, '0:%d 3:%d', [clBlue, clYellow]), RunsStr(d, 1));
  finally
    d.Free;
  end;
  // at a run boundary the character before gives the format
  d := NewSample;
  try
    u := d.InsertText(3, 'Q');
    u.Free;
    AssertEquals('boundary: the run before grows',
      SampleRuns(d, '0:%d 4:%d 7:%d', [clRed, clGreen, clBlue]), RunsStr(d, 0));
  finally
    d.Free;
  end;
  // at the paragraph's start the character after does
  d := NewSample;
  try
    u := d.InsertText(10, 'Z');
    u.Free;
    AssertEquals('paragraph start: the first run grows',
      SampleRuns(d, '0:%d 4:%d', [clBlue, clYellow]), RunsStr(d, 1));
  finally
    d.Free;
  end;
  // an explicit format makes a run of its own
  d := NewSample;
  try
    u := d.InsertText(4, 'W', ColorId(d, clYellow));
    u.Free;
    AssertEquals('explicit format',
      SampleRuns(d, '0:%d 3:%d 4:%d 5:%d 7:%d', [clRed, clGreen, clYellow, clGreen, clBlue]),
      RunsStr(d, 0));
  finally
    d.Free;
  end;
  // a split gives both parts the paragraph's format; the runs split at the position
  d := NewSample;
  try
    u := d.InsertText(4, #13#10);
    u.Free;
    AssertEquals('split: paragraphs', 4, d.Text.ParaCount);
    AssertEquals('split: first part', 'aaab', ParaText(d, 0));
    AssertEquals('split: second part', 'bbccc', ParaText(d, 1));
    AssertEquals('split: first part runs', SampleRuns(d, '0:%d 3:%d', [clRed, clGreen]),
      RunsStr(d, 0));
    AssertEquals('split: second part runs', SampleRuns(d, '0:%d 2:%d', [clGreen, clBlue]),
      RunsStr(d, 1));
    AssertEquals('split: first part format', AlignId(d, paraCenter), d.ParaFormatOf(0));
    AssertEquals('split: second part format', AlignId(d, paraCenter), d.ParaFormatOf(1));
    AssertEquals('split: the next paragraph keeps its own', AlignId(d, paraRight),
      d.ParaFormatOf(2));
  finally
    d.Free;
  end;
  // Enter at the very start: the new empty paragraph is like the one it came from
  d := NewSample;
  try
    u := d.InsertText(10, #13#10);
    u.Free;
    AssertEquals('split at start: empty first part', '', ParaText(d, 1));
    AssertEquals('split at start: its format', AlignId(d, paraRight), d.ParaFormatOf(1));
    AssertEquals('split at start: its run takes the character after',
      SampleRuns(d, '0:%d', [clBlue]), RunsStr(d, 1));
    AssertEquals('split at start: the paragraph keeps its format', AlignId(d, paraRight),
      d.ParaFormatOf(2));
    AssertEquals('split at start: and its runs', SampleRuns(d, '0:%d 3:%d', [clBlue, clYellow]),
      RunsStr(d, 2));
  finally
    d.Free;
  end;
  // pasted lines: the ones in between take the inherited format too
  d := NewSample;
  try
    u := d.InsertText(4, 'x'#13#10'y'#13#10'z');
    u.Free;
    AssertEquals('paste: first', SampleRuns(d, '0:%d 3:%d', [clRed, clGreen]), RunsStr(d, 0));
    AssertEquals('paste: middle', SampleRuns(d, '0:%d', [clGreen]), RunsStr(d, 1));
    AssertEquals('paste: middle format', AlignId(d, paraCenter), d.ParaFormatOf(1));
    AssertEquals('paste: last', 'zbbccc', ParaText(d, 2));
    AssertEquals('paste: last runs', SampleRuns(d, '0:%d 3:%d', [clGreen, clBlue]),
      RunsStr(d, 2));
  finally
    d.Free;
  end;
  // one separator deleted: the paragraph before gives the format; equal runs merge
  d := NewSample;
  try
    u := d.DeleteRange(9, 1);
    u.Free;
    AssertEquals('join: paragraphs', 2, d.Text.ParaCount);
    AssertEquals('join: text', 'aaabbbcccdddeee', ParaText(d, 0));
    AssertEquals('join: the blue runs are one',
      SampleRuns(d, '0:%d 3:%d 6:%d 12:%d', [clRed, clGreen, clBlue, clYellow]), RunsStr(d, 0));
    AssertEquals('join: the first paragraph''s format', AlignId(d, paraCenter),
      d.ParaFormatOf(0));
  finally
    d.Free;
  end;
  // the separator and a character after it: the paragraph the range ends in gives it
  d := NewSample;
  try
    u := d.DeleteRange(9, 2);
    u.Free;
    AssertEquals('separator+1: text', 'aaabbbcccddeee', ParaText(d, 0));
    AssertEquals('separator+1: runs',
      SampleRuns(d, '0:%d 3:%d 6:%d 11:%d', [clRed, clGreen, clBlue, clYellow]), RunsStr(d, 0));
    AssertEquals('separator+1: the last paragraph''s format', AlignId(d, paraRight),
      d.ParaFormatOf(0));
  finally
    d.Free;
  end;
  // middle to middle
  d := NewSample;
  try
    u := d.DeleteRange(4, 8);
    u.Free;
    AssertEquals('middle to middle: text', 'aaabdeee', ParaText(d, 0));
    AssertEquals('middle to middle: runs',
      SampleRuns(d, '0:%d 3:%d 4:%d 5:%d', [clRed, clGreen, clBlue, clYellow]), RunsStr(d, 0));
    AssertEquals('middle to middle: the last paragraph''s format', AlignId(d, paraRight),
      d.ParaFormatOf(0));
    AssertEquals('middle to middle: paragraphs', 2, d.Text.ParaCount);
  finally
    d.Free;
  end;
  // middle of the first to the start of the third
  d := NewSample;
  try
    u := d.DeleteRange(4, 13);
    u.Free;
    AssertEquals('to a start: text', 'aaabfff', ParaText(d, 0));
    AssertEquals('to a start: runs',
      SampleRuns(d, '0:%d 3:%d 4:%d', [clRed, clGreen, clDefault]), RunsStr(d, 0));
    AssertEquals('to a start: that paragraph''s format', AlignId(d, paraJustify),
      d.ParaFormatOf(0));
  finally
    d.Free;
  end;
  // a whole paragraph with its separator: the next one stays as it was
  d := NewSample;
  try
    u := d.DeleteRange(0, 10);
    u.Free;
    AssertEquals('whole paragraph: text', 'dddeee', ParaText(d, 0));
    AssertEquals('whole paragraph: runs', SampleRuns(d, '0:%d 3:%d', [clBlue, clYellow]),
      RunsStr(d, 0));
    AssertEquals('whole paragraph: its own format', AlignId(d, paraRight), d.ParaFormatOf(0));
  finally
    d.Free;
  end;
  // the separator of an EMPTY paragraph (a blank line above a centred title, Backspace at
  // the title's start): the empty paragraph goes, what follows keeps its format and runs
  d := NewDoc(#13#10'bbb');
  try
    Align(d, 0, 0, paraCenter);
    Align(d, 1, 1, paraRight);
    Paint(d, 1, 3, clBlue);
    u := d.DeleteRange(0, 1);
    AssertEquals('empty before: paragraphs', 1, d.Text.ParaCount);
    AssertEquals('empty before: text', 'bbb', ParaText(d, 0));
    AssertEquals('empty before: the following paragraph''s format', AlignId(d, paraRight),
      d.ParaFormatOf(0));
    AssertEquals('empty before: and its runs', SampleRuns(d, '0:%d', [clBlue]), RunsStr(d, 0));
    d.Revert(u);
    AssertEquals('empty before, undone: paragraphs', 2, d.Text.ParaCount);
    AssertEquals('empty before, undone: the empty one is centred again',
      AlignId(d, paraCenter), d.ParaFormatOf(0));
    AssertEquals('empty before, undone: the other is right', AlignId(d, paraRight),
      d.ParaFormatOf(1));
  finally
    d.Free;
  end;
  // two empty paragraphs: the first one's separator goes, the second one's format stays
  d := NewDoc(#13#10#13#10'ccc');
  try
    Align(d, 0, 0, paraCenter);
    Align(d, 1, 1, paraRight);
    Align(d, 2, 2, paraJustify);
    u := d.DeleteRange(0, 1);
    u.Free;
    AssertEquals('two empty: paragraphs', 2, d.Text.ParaCount);
    AssertEquals('two empty: the second one''s format', AlignId(d, paraRight), d.ParaFormatOf(0));
    AssertEquals('two empty: the text after keeps its own', AlignId(d, paraJustify),
      d.ParaFormatOf(1));
  finally
    d.Free;
  end;
  // the paragraph BEFORE the separator is not empty, the one after is: the one before gives it
  d := NewDoc('aaa'#13#10#13#10'ccc');
  try
    Align(d, 0, 0, paraCenter);
    Align(d, 1, 1, paraRight);
    Align(d, 2, 2, paraJustify);
    u := d.DeleteRange(3, 1);
    u.Free;
    AssertEquals('empty after: paragraphs', 2, d.Text.ParaCount);
    AssertEquals('empty after: text', 'aaa', ParaText(d, 0));
    AssertEquals('empty after: the paragraph before gives the format', AlignId(d, paraCenter),
      d.ParaFormatOf(0));
    AssertEquals('empty after: the text after keeps its own', AlignId(d, paraJustify),
      d.ParaFormatOf(1));
  finally
    d.Free;
  end;
  // inside one paragraph: the runs after the range move left, an emptied run goes
  d := NewSample;
  try
    u := d.DeleteRange(2, 5);
    u.Free;
    AssertEquals('inside: text', 'aacc', ParaText(d, 0));
    AssertEquals('inside: runs', SampleRuns(d, '0:%d 2:%d', [clRed, clBlue]), RunsStr(d, 0));
    u := d.DeleteRange(0, 4);
    u.Free;
    AssertEquals('emptied: the first deleted character''s format stays',
      SampleRuns(d, '0:%d', [clRed]), RunsStr(d, 0));
  finally
    d.Free;
  end;
end;

{ ---- objects ---- }

procedure TTyRichModelTest.TestObjectIsOneCharacter;
var
  d: TDocAccess;
  pic: TTyRichPicture;
  op: TCountedOpaque;
  u, u2: TTyRichUndoData;
  data: TBytes;
  r: TTyRunArray;
begin
  d := NewDoc('ab'#13#10'cd');
  try
    data := Bytes('PNG-bytes');
    pic := TTyRichPicture.Create(rpfPng, data, 1440, 720, '{\pict\pngblip 89}');
    u := d.InsertObject(1, pic);
    AssertEquals('one character more', 6, d.Text.Length);
    AssertTrue('the character is U+FFFC', d.Text.GetText(1, 1) = TyRichObjectChar);
    AssertEquals('U+FFFC in UTF-8', 3, Length(d.Text.GetText(1, 1)));
    AssertEquals('paragraph length', 3, d.Text.ParaLength(0));
    r := d.RunsOf(0);
    AssertEquals('three runs', 3, Length(r));
    AssertEquals('the object run starts at the character', 1, r[1].Start);
    AssertTrue('the object rides on its run', r[1].Obj = pic);
    AssertEquals('the next run starts after it', 2, r[2].Start);
    AssertTrue('only that run has it', (r[0].Obj = nil) and (r[2].Obj = nil));
    AssertEquals('the document holds the picture', 1, pic.RefCount);
    AssertEquals('picture size', 1440, pic.WidthTwips);
    // deleting the character takes the run; reverting brings the very object back
    u2 := d.DeleteRange(1, 1);
    AssertEquals('deleted: runs', IntToStr(0) + ':' + IntToStr(d.DefaultCharFormatId),
      RunsStr(d, 0));
    AssertEquals('the undo record keeps it alive', 1, pic.RefCount);
    d.Revert(u2);
    AssertTrue('the same object is back', d.RunsOf(0)[1].Obj = pic);
    d.Revert(u);
    AssertEquals('reverted', 'ab', ParaText(d, 0));

    op := TCountedOpaque.Create('{\*\unknown x}');
    u := d.InsertObject(d.Text.ParaStart(1) + 2, op);
    u.Free;
    AssertEquals('an opaque object is one character too', 3, d.Text.ParaLength(1));
    AssertTrue('at the paragraph''s end', d.RunsOf(1)[1].Obj = op);
    AssertEquals('alive', 1, TCountedOpaque.Live);
  finally
    d.Free;
  end;
  AssertEquals('the document frees its objects', 0, TCountedOpaque.Live);
end;

procedure TTyRichModelTest.TestCharFormatChangesOnlyTheMaskedFields;
var
  d: TDocAccess;
  f: TTyCharFormat;
  u: TTyRichUndoData;
  r: TTyRunArray;
begin
  d := NewDoc('abcdef'#13#10#13#10'gh');
  try
    Paint(d, 0, 6, clRed);
    // italic first: setting bold afterwards must leave it alone
    f := TyDefaultCharFormat;
    f.Style := [fsItalic];
    u := d.ApplyCharFormat(2, 4, [cffItalic], f);
    u.Free;
    f.Style := [fsBold];
    u := d.ApplyCharFormat(0, 4, [cffBold], f);
    u.Free;
    r := d.RunsOf(0);
    AssertEquals('three runs', 3, Length(r));
    AssertTrue('bold', d.Formats.CharFormat(r[0].Format).Style = [fsBold]);
    AssertTrue('bold and italic', d.Formats.CharFormat(r[1].Format).Style = [fsBold, fsItalic]);
    AssertTrue('italic', d.Formats.CharFormat(r[2].Format).Style = [fsItalic]);
    AssertEquals('the colour stays', clRed, d.Formats.CharFormat(r[1].Format).Color);
    AssertEquals('starts', '0 2 4', Format('%d %d %d', [r[0].Start, r[1].Start, r[2].Start]));
    // a range over an empty paragraph's separator formats its one run
    f.Style := [fsUnderline];
    u := d.ApplyCharFormat(5, 4, [cffUnderline], f);
    u.Free;
    AssertTrue('the empty paragraph''s run',
      d.Formats.CharFormat(d.RunsOf(1)[0].Format).Style = [fsUnderline]);
    AssertTrue('the last paragraph''s first character',
      d.Formats.CharFormat(d.RunsOf(2)[0].Format).Style = [fsUnderline]);
    AssertEquals('only its first character', 1, d.RunsOf(2)[1].Start);
  finally
    d.Free;
  end;
end;

{ ---- undo: values held by undo records survive edits ---- }

function TTyRichModelTest.UndoScenario(ACycles: Integer): string;
var
  d: TDocAccess;
  o1, o2, o3: TCountedOpaque;
  dump0, dumpAfter, s: string;
  u: array[1..6] of TTyRichUndoData;
  p1, p2: Pointer;
  live0, cycle, i: Integer;
  f: TTyCharFormat;
  pf: TTyParaFormat;

  procedure Fail(const AMsg: string);
  begin
    if Result = '' then Result := AMsg;
  end;

  procedure Run;
  begin
    u[1] := d.DeleteRange(3, 15);
    u[2] := d.InsertText(1, 'XX'#13#10'YY');
    u[3] := d.ApplyCharFormat(0, 6, [cffItalic], f);
    u[4] := d.ApplyParaFormat(0, 1, [pffAlign, pffLeftIndent], pf);
    u[5] := d.DeleteRange(2, 4);
    u[6] := d.InsertObject(0, o3);
  end;

  procedure RevertAll;
  var
    j: Integer;
  begin
    for j := 6 downto 1 do d.Revert(u[j]);
  end;

begin
  Result := '';
  f := TyDefaultCharFormat;
  f.Style := [fsItalic];
  pf := TyDefaultParaFormat;
  pf.Align := paraRight;
  pf.LeftIndent := 360;
  d := NewDoc('alpha'#13#10'beta'#13#10'gamma'#13#10'delta');
  o3 := TCountedOpaque.Create('{\*\three}');
  o3.AddRef;   // as a command would, to insert it again on redo
  try
    o1 := TCountedOpaque.Create('{\*\one}');
    d.InsertObject(8, o1).Free;            // be|ta
    o2 := TCountedOpaque.Create('{\*\two}');
    d.InsertObject(15, o2).Free;           // gam|ma
    Paint(d, 0, 3, clRed);
    Paint(d, 7, 4, clGreen);
    Paint(d, 13, 3, clBlue);
    Align(d, 1, 1, paraRight);
    Align(d, 2, 2, paraCenter);
    Align(d, 3, 3, paraJustify);
    dump0 := Dump(d);
    live0 := d.LiveParaData;
    p1 := d.ParaDataOf(1);
    p2 := d.ParaDataOf(2);
    for cycle := 1 to ACycles do
    begin
      Run;
      s := Dump(d);
      if cycle = 1 then dumpAfter := s
      else if s <> dumpAfter then Fail(Format('cycle %d: redo differs:%s%s', [cycle, LineEnding, s]));
      if TCountedOpaque.Live <> 3 then
        Fail(Format('cycle %d: %d objects alive while deleted', [cycle, TCountedOpaque.Live]));
      if not d.IsLiveParaData(p1) or not d.IsLiveParaData(p2) then
        Fail(Format('cycle %d: a deleted paragraph''s value is gone', [cycle]));
      RevertAll;
      s := Dump(d);
      if s <> dump0 then
        Fail(Format('cycle %d: reverted differs:%s%s%sexpected:%s%s', [cycle, LineEnding, s,
          LineEnding, LineEnding, dump0]));
      for i := 1 to 6 do
        if u[i] <> nil then Fail('Revert leaves its record');
      if d.LiveParaData <> live0 then
        Fail(Format('cycle %d: %d paragraph values alive, %d before', [cycle, d.LiveParaData,
          live0]));
      if (d.ParaDataOf(1) <> p1) or (d.ParaDataOf(2) <> p2) then
        Fail(Format('cycle %d: not the very values back', [cycle]));
      if d.Text.CheckIntegrity <> '' then Fail(d.Text.CheckIntegrity);
    end;
    if TCountedOpaque.Live <> 3 then
      Fail(Format('%d objects alive after reverting', [TCountedOpaque.Live]));
  finally
    d.Free;
    o3.Release;
  end;
  if TCountedOpaque.Live <> 0 then
    Fail(Format('%d objects leaked', [TCountedOpaque.Live]));
end;

procedure TTyRichModelTest.TestRevertGivesBackRunsFormatsAndObjects;
var
  first, second: string;
  h0, h1: Int64;
begin
  first := UndoScenario(5);
  AssertEquals('', '', first);
  h0 := GetFPCHeapStatus.CurrHeapUsed;
  second := UndoScenario(3);
  h1 := GetFPCHeapStatus.CurrHeapUsed;
  AssertEquals('second run', '', second);
  AssertEquals('nothing leaks: heap in use before and after', h0, h1);
end;

{ ---- on-demand parsing ---- }

procedure TTyRichModelTest.TestLoaderParsesOnlyWhatIsAsked;
var
  d: TDocAccess;
  ld: TFakeLoader;
  u: TTyRichUndoData;
  p3: Pointer;
begin
  d := NewDoc('p0'#13#10'p1'#13#10'p2'#13#10'p3'#13#10'p4'#13#10'p5'#13#10'p6'#13#10'p7'#13#10'p8'#13#10'p9');
  try
    ld := TFakeLoader.Create;
    ld.ParaFmt := AlignId(d, paraCenter);
    ld.CharFmt := ColorId(d, clRed);
    d.InstallLoader(ld, True);
    d.OnChange := @DocChanged;
    AssertEquals('nothing parsed up front', '', ld.Calls.CommaText);
    AssertEquals('format from the loader', AlignId(d, paraCenter), d.ParaFormatOf(3));
    AssertEquals('asked for 3', '3', ld.Calls.CommaText);
    AssertEquals('runs from the loader', SampleRuns(d, '0:%d', [clRed]), RunsStr(d, 3));
    AssertTrue('no table', d.TableAt(3) = nil);
    AssertTrue('no cell', d.CellAt(3) = nil);
    d.EnsureParsed(3);
    AssertEquals('asked once', '3', ld.Calls.CommaText);
    p3 := d.ParaDataOf(3);
    ld.AlsoNext := True;
    AssertEquals('5', SampleRuns(d, '0:%d', [clRed]), RunsStr(d, 5));
    AssertEquals('a neighbour parsed along', AlignId(d, paraCenter), d.ParaFormatOf(6));
    AssertEquals('6 came with 5', '3,5', ld.Calls.CommaText);
    d.ParaFormatOf(2);
    AssertEquals('asked for 2', '3,5,2', ld.Calls.CommaText);
    AssertFalse('the loader does not overwrite a parsed paragraph', ld.NextWasSet);
    AssertTrue('3 keeps its value', d.ParaDataOf(3) = p3);
    ld.AlsoNext := False;
    ld.LeavePlain := 8;
    AssertEquals('a paragraph the loader leaves is plain', d.DefaultParaFormatId,
      d.ParaFormatOf(8));
    AssertEquals('plain runs', SampleRuns(d, '0:%d', [clDefault]), RunsStr(d, 8));
    AssertEquals('and is not asked about again', '3,5,2,8', ld.Calls.CommaText);
    AssertFalse('loading is not a modification', d.Modified);
    AssertEquals('loading reports no change', 0, Length(FChanges));
    // an edit parses the paragraph it touches
    u := d.InsertText(d.Text.ParaStart(1) + 2, 'x');
    AssertEquals('the edited paragraph was parsed first', '3,5,2,8,1', ld.Calls.CommaText);
    AssertEquals('its runs', SampleRuns(d, '0:%d', [clRed]), RunsStr(d, 1));
    d.Revert(u);
    // a split in a loader document leaves no unparsed part behind
    u := d.InsertText(d.Text.ParaStart(3) + 1, #13#10#13#10);
    AssertEquals('split parts are parsed', AlignId(d, paraCenter), d.ParaFormatOf(4));
    AssertEquals('all of them', AlignId(d, paraCenter), d.ParaFormatOf(5));
    AssertEquals('no new questions', '3,5,2,8,1', ld.Calls.CommaText);
    d.Revert(u);
    AssertEquals('0, 4, 7 and 9 were never asked about', '3,5,2,8,1', ld.Calls.CommaText);
  finally
    d.Free;
  end;
end;

{ ---- tables ---- }

procedure TTyRichModelTest.CheckTable(ADoc: TDocAccess; AT1, AT2: TTyRichTable;
  AFirst: Integer; ASplitCell: Boolean; const AWhen: string);
var
  f, l, x: Integer;
  w: string;

  procedure Cell(ARow, ACol, AFrom, ATo: Integer; const AText: UTF8String);
  var
    c: TTyRichCell;
  begin
    c := AT1.Rows[ARow].Cells[ACol];
    AssertTrue(w + Format('cell %d,%d found', [ARow, ACol]), ADoc.CellParas(AFirst + 2, c, f, l));
    AssertEquals(w + Format('cell %d,%d first', [ARow, ACol]), AFirst + AFrom, f);
    AssertEquals(w + Format('cell %d,%d last', [ARow, ACol]), AFirst + ATo, l);
    AssertEquals(w + Format('cell %d,%d text', [ARow, ACol]), AText, ParaText(ADoc, f));
    AssertTrue(w + Format('cell %d,%d is its paragraphs'' cell', [ARow, ACol]), ADoc.CellAt(l) = c);
  end;

begin
  w := AWhen + ': ';
  if ASplitCell then x := 1 else x := 0;
  AssertTrue(w + 'before the table', ADoc.TableAt(AFirst - 1) = nil);
  AssertTrue(w + 'the table', ADoc.TableAt(AFirst) = AT1);
  Cell(0, 0, 0, 0, 'p3');
  Cell(0, 1, 1, 2, 'p4');
  AssertEquals(w + 'second paragraph of cell 0,1', 'p5', ParaText(ADoc, AFirst + 2));
  Cell(1, 0, 3, 3 + x, 'p6');
  Cell(1, 1, 4 + x, 4 + x, 'p7');
  AssertTrue(w + 'table range', ADoc.TableParas(AFirst + 1, f, l));
  AssertEquals(w + 'table first', AFirst, f);
  AssertEquals(w + 'table last', AFirst + 4 + x, l);
  AssertTrue(w + 'the adjacent table', ADoc.TableAt(AFirst + 5 + x) = AT2);
  AssertTrue(w + 'its range', ADoc.TableParas(AFirst + 5 + x, f, l));
  AssertEquals(w + 'adjacent table first', AFirst + 5 + x, f);
  AssertEquals(w + 'adjacent table last', AFirst + 5 + x, l);
  AssertTrue(w + 'its cell', ADoc.CellParas(AFirst + 5 + x, AT2.Rows[0].Cells[0], f, l));
  AssertEquals(w + 'its text', 'p8', ParaText(ADoc, f));
  AssertTrue(w + 'after the tables', ADoc.TableAt(AFirst + 6 + x) = nil);
  AssertFalse(w + 'no table there', ADoc.TableParas(AFirst - 1, f, l));
end;

procedure TTyRichModelTest.TestTableSurvivesEditsBeforeIt;
var
  d: TDocAccess;
  t1, t2: TTyRichTable;
  u: array[0..6] of TTyRichUndoData;
  i: Integer;
begin
  d := NewDoc('p0'#13#10'p1'#13#10'p2'#13#10'p3'#13#10'p4'#13#10'p5'#13#10'p6'#13#10'p7'#13#10'p8'#13#10'p9');
  t1 := TCountedTable.Create([1440, 2880]);
  t1.AddRef;   // kept, as a command would, to mark it again on redo
  try
    t1.AddRow(2, '\trowd\cellx1440\cellx2880');
    t1.AddRow(2, '\trowd\cellx1440\cellx2880');
    t2 := TCountedTable.Create([1000]);
    t2.AddRow(1);
    u[0] := d.MarkTable(3, t1, [1, 2, 1, 1]);
    u[1] := d.MarkTable(8, t2, [1]);
    AssertEquals('the table has its rows', 2, t1.RowCount);
    AssertEquals('raw row format', '\trowd\cellx1440\cellx2880', t1.Rows[0].RawFormat);
    AssertEquals('column boundaries', 2880, t1.ColBoundaries[1]);
    CheckTable(d, t1, t2, 3, False, 'built');
    try
      t1.AddRow(1);
      Fail('a table in use cannot grow');
    except
      on ETyRichModel do ;
    end;
    u[2] := d.InsertText(0, 'n1'#13#10'n2'#13#10);
    CheckTable(d, t1, t2, 5, False, 'two paragraphs inserted before');
    u[3] := d.DeleteRange(0, d.Text.ParaStart(3));
    CheckTable(d, t1, t2, 2, False, 'three deleted before');
    u[4] := d.InsertText(d.Text.ParaStart(1) + 2, #13#10'q');
    CheckTable(d, t1, t2, 3, False, 'one more before');
    // Enter in a cell: the new paragraph is in the same cell
    u[5] := d.InsertText(d.Text.ParaStart(6) + 2, #13#10'p6b');
    CheckTable(d, t1, t2, 3, True, 'a cell got a paragraph');
    AssertEquals('the cell''s new paragraph', 'p6b', ParaText(d, 7));
    for i := 5 downto 2 do d.Revert(u[i]);
    CheckTable(d, t1, t2, 3, False, 'reverted');
    d.Revert(u[1]);
    d.Revert(u[0]);
    for i := 0 to d.Text.ParaCount - 1 do
      AssertTrue(Format('no table at %d after revert', [i]), d.TableAt(i) = nil);
    AssertEquals('the unreferenced table is gone, the held one stays', 1, TCountedTable.Live);
    u[0] := d.MarkTable(3, t1, [1, 2, 1, 1]);
    AssertTrue('marked again', d.TableAt(7) = t1);
    u[0].Free;
  finally
    d.Free;
    t1.Release;
  end;
  AssertEquals('no table leaks', 0, TCountedTable.Live);
end;

{ ---- notification ---- }

procedure TTyRichModelTest.TestChangesAreReported;
var
  d: TDocAccess;
  u: array[1..6] of TTyRichUndoData;
  f: TTyCharFormat;
  pf: TTyParaFormat;
begin
  d := NewDoc('abc'#13#10'def');
  try
    d.OnChange := @DocChanged;
    AssertFalse('a new document is not modified', d.Modified);
    u[1] := d.InsertText(1, 'X');
    AssertTrue('modified', d.Modified);
    CheckChange('typing', 0, [rckText], 1, 0, 1, 0, 1, 1);
    u[2] := d.InsertText(2, #13#10);
    CheckChange('enter', 1, [rckText, rckStructure], 2, 0, 1, 0, 1, 2);
    u[3] := d.DeleteRange(1, 3);
    CheckChange('delete across', 2, [rckText, rckStructure], 1, 3, 0, 0, 2, 1);
    f := TyDefaultCharFormat;
    f.Style := [fsBold];
    u[4] := d.ApplyCharFormat(0, 2, [cffBold], f);
    CheckChange('bold', 3, [rckFormat], 0, 2, 2, 0, 1, 1);
    pf := TyDefaultParaFormat;
    pf.Align := paraCenter;
    u[5] := d.ApplyParaFormat(0, 1, [pffAlign], pf);
    CheckChange('centre', 4, [rckFormat], 0, 6, 6, 0, 2, 2);
    u[6] := d.InsertText(0, '');
    AssertEquals('a no-op reports nothing', 5, Length(FChanges));
    d.Modified := False;
    d.Revert(u[6]);
    AssertEquals('reverting a no-op reports nothing', 5, Length(FChanges));
    d.Revert(u[5]);
    CheckChange('revert centre', 5, [rckFormat], 0, 6, 6, 0, 2, 2);
    AssertTrue('reverting is a change', d.Modified);
    d.Revert(u[4]);
    d.Revert(u[3]);
    CheckChange('revert delete', 7, [rckText, rckStructure], 1, 0, 3, 0, 1, 2);
    d.Revert(u[2]);
    CheckChange('revert enter', 8, [rckText, rckStructure], 2, 1, 0, 0, 2, 1);
    d.Revert(u[1]);
    CheckChange('revert typing', 9, [rckText], 1, 1, 0, 0, 1, 1);
    AssertEquals('back', 'abc'#13#10'def', d.Text.GetText(0, d.Text.Length));
  finally
    d.Free;
  end;
end;

procedure TTyRichModelTest.TestDocumentDefaults;
var
  d: TDocAccess;
  f: TTyCharFormat;
begin
  d := TDocAccess.Create;
  try
    AssertEquals('paper width', 12240, d.PaperWidth);
    AssertEquals('paper height', 15840, d.PaperHeight);
    AssertEquals('left margin', 1800, d.MarginLeft);
    AssertEquals('right margin', 1800, d.MarginRight);
    f := d.DefaultCharFormat;
    AssertEquals('the theme''s font', '', f.FontName);
    AssertEquals('the theme''s size', 0, f.SizeHalfPt);
    AssertEquals('the theme''s colour', clDefault, f.Color);
    AssertTrue('no styles', (f.Style = []) and not f.Strike and (f.VertAlign = vaNone));
    AssertEquals('no highlight', clNone, f.HighlightColor);
    AssertTrue('the default id is that format',
      d.Formats.CharFormat(d.DefaultCharFormatId).Equals(f));
    AssertTrue('default paragraph format',
      d.Formats.ParaFormat(d.DefaultParaFormatId).Equals(TyDefaultParaFormat));
    AssertEquals('one empty paragraph', 1, d.Text.ParaCount);
    AssertEquals('its run', SampleRuns(d, '0:%d', [clDefault]), RunsStr(d, 0));
    AssertEquals('typing format', d.DefaultCharFormatId, d.TypingFormatAt(0));
  finally
    d.Free;
  end;
end;

procedure TTyRichModelTest.TestEditsThroughTextKeepRunsInside;
var
  d: TDocAccess;
begin
  d := NewDoc('abcdef');
  try
    Paint(d, 0, 3, clRed);
    Paint(d, 3, 3, clGreen);
    d.Modified := False;
    d.Text.Delete(2, 4);
    AssertEquals('the runs are clipped to the text', SampleRuns(d, '0:%d', [clRed]),
      RunsStr(d, 0));
    AssertTrue('it is a modification', d.Modified);
  finally
    d.Free;
  end;
end;

procedure TTyRichModelTest.TestTableIndexesAndEmptyTablesAreRefused;
var
  d: TDocAccess;
  t: TTyRichTable;
  row: TTyRichRow;
  before: string;

  procedure Refused(const AWhat: string; AKind: Integer);
  var
    raised: Boolean;
  begin
    raised := False;
    try
      case AKind of
        0: t.ColBoundaries[2];
        1: t.ColBoundaries[-1];
        2: row.Boundaries[3];
        3: row.Boundaries[-1];
        4: d.MarkTable(0, t, []).Free;
        5: d.MarkTable(2, t, []).Free;
      end;
    except
      on ETyRichModel do raised := True;
    end;
    AssertTrue(AWhat + ' must raise ETyRichModel', raised);
  end;

begin
  d := NewDoc('p0'#13#10'p1'#13#10'p2');
  t := TCountedTable.Create([1440, 2880]);
  t.AddRef;
  try
    // a table without a row has no cell to give a paragraph to
    before := Dump(d);
    Refused('marking an empty table at the start', 4);
    Refused('marking an empty table further down', 5);
    AssertEquals('the document is as it was', before, Dump(d));
    AssertFalse('and not modified', d.Modified);
    row := t.AddRow(2, '', [0, 1440, 2880]);
    AssertEquals('the last column boundary', 2880, t.ColBoundaries[1]);
    AssertEquals('the last row boundary', 2880, row.Boundaries[2]);
    Refused('a column boundary past the last', 0);
    Refused('a column boundary before the first', 1);
    Refused('a row boundary past the last', 2);
    Refused('a row boundary before the first', 3);
  finally
    t.Release;
    d.Free;
  end;
end;

initialization
  RegisterTest(TTyRichModelTest);
end.
