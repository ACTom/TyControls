unit test.richedit.api;

{ TTyRichEdit's format API (Task 11a): the Delphi-style façade (SelAttributes, DefAttributes,
  Paragraph, PlainText) and the RichMemo-style one (SetTextAttributes .. SaveRichText), both
  thin layers over the engine's commands; the pending typing format; Modified with its saved
  point; the user's actions against the document API (R66); the events.

  Headless, on the edit suite's probe (TEditProbe: the test device, the clipboard double, the
  counters). No window, no clipboard, no input method, no message loop. Every bound is a
  count, never a time. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, TypInfo, fpcunit, testregistry, Controls, Graphics, LCLType,
  Forms, BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.Painter, tyControls.StrConsts,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.Layout, tyControls.RichEdit.Attrs, tyControls.RichEdit,
  test.richedit.control, test.richedit.edit;

type
  TTyRichEditApiTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TEditProbe;
    FChanges, FSelChanges, FModChanges: Integer;
    FPaintScale: Integer;
    FTemp: string;
    // what a save's progress handler did (TestTheTwoKindsWhileSaving)
    FSaveCalls, FSaveRaised, FSaveTold: Integer;
    FSaveWhat: Integer;
    procedure Changed(Sender: TObject);
    procedure SelChanged(Sender: TObject);
    procedure ModChanged(Sender: TObject);
    procedure ActWhileSaving(Sender: TObject; ADone, ATotal: Int64; var ACancel: Boolean);
    function NewProbe: TEditProbe;
    procedure ResetEvents;
    procedure SetText(const S: string);
    procedure LoadBytes(const B: TBytes; AFinish: Boolean = True);
    procedure Sel(AStart, ALen: TTyRichPos);
    procedure Chars(const S: RawByteString);
    function Fmt(APos: TTyRichPos): TTyCharFormat;
    function PFmt(AIndex: Integer): TTyParaFormat;
    function Dump(AParas: Integer = MaxInt; AHistory: Boolean = False): string;
    function SavedRtf: TBytes;
    function TempDir: string;
    procedure PaintAll;
    procedure CheckSurface(const AWhat: string);
    procedure MixedRuns;
    procedure RepaintCase(AScale: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // the brief's
    procedure TestBothFacadesGoThroughCommands;
    procedure TestSelAttributesReflectsMixedSelection;
    // one per rule
    procedure TestEachCharAttributeAloneLeavesTheOthers;
    procedure TestTheRichMemoCharMethods;
    procedure TestHeightAndSizeUnits;
    procedure TestParagraphInDelphisUnits;
    procedure TestTheRichMemoParagraphMethods;
    procedure TestAParagraphWriteWithNothingSelected;
    procedure TestDefAttributesIsTheControlsFont;
    procedure TestPlainTextBothWaysWithLoadAndSave;
    procedure TestPlainTextAndThePaste;
    procedure TestThePendingFormat;
    procedure TestEachWayThePendingFormatEnds;
    procedure TestThePendingFormatWithACompositionAndAPaste;
    procedure TestAFormatWriteIsOneStepThatPutsTheSelectionBack;
    procedure TestALazyParagraphFormattedAndUndoneSavesTheFile;
    procedure TestOneChangeAndNoSelectionChange;
    procedure TestRefusalsOfTheDocument;
    procedure TestRowsCellsAndTheHiddenTail;
    procedure TestTheSavedPointThroughTheControl;
    procedure TestTheUserActionsRespectReadOnly;
    procedure TestTheTwoKindsWhileSaving;
    procedure TestClearSelectionDeletes;
    procedure TestTheRepaintAfterAHeightChange;
    procedure TestTheEventsArePublished;
    procedure TestTheWaitCursorOverTheThreshold;
  end;

implementation

const
  BS = #92;

function RawBytes(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[0], Length(S));
end;

function StrOf(const B: TBytes): RawByteString;
begin
  Result := '';
  SetLength(Result, Length(B));
  if Length(B) > 0 then Move(B[0], Result[1], Length(B));
end;

function FileBytes(const APath: string): TBytes;
var
  f: TFileStream;
begin
  Result := nil;
  f := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, f.Size);
    if f.Size > 0 then f.ReadBuffer(Result[0], f.Size);
  finally
    f.Free;
  end;
end;

function FixtureFile(const AName: string): TBytes;
begin
  Result := FileBytes(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim +
    'fixtures' + PathDelim + 'rtf' + PathDelim + AName);
end;

{ An RTF file of AParas plain paragraphs (read lazily: each parsed when it is first read). }
function PlainRtf(AParas: Integer): TBytes;
var
  s: RawByteString;
  i: Integer;
begin
  s := '{' + BS + 'rtf1' + BS + 'ansi' + BS + 'deff0{' + BS + 'fonttbl{' + BS + 'f0 Arial;}}' +
    #13#10;
  for i := 0 to AParas - 1 do
    s := s + BS + 'pard' + BS + 'f0 Paragraph ' + IntToStr(i) + ' of the file.' + BS + 'par' +
      #13#10;
  s := s + '}';
  Result := RawBytes(s);
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

{ ---- the suite ---- }

procedure TTyRichEditApiTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FPaintScale := 1;
  FTemp := '';
  FRich := NewProbe;
  ResetEvents;
end;

procedure TTyRichEditApiTest.TearDown;
var
  sr: TSearchRec;
begin
  TyForceDeviceScaleForTest(0, False);
  FreeAndNil(FRich);
  FreeAndNil(FCtl);
  if (FTemp <> '') and DirectoryExists(FTemp) then
  begin
    if FindFirst(FTemp + '*', faAnyFile, sr) = 0 then
    try
      repeat
        if (sr.Attr and faDirectory) = 0 then DeleteFile(FTemp + sr.Name);
      until FindNext(sr) <> 0;
    finally
      FindClose(sr);
    end;
    RemoveDir(FTemp);
  end;
end;

function TTyRichEditApiTest.NewProbe: TEditProbe;
begin
  Result := TEditProbe.Create(nil);
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 300);
  Result.OnChange := @Changed;
  Result.OnSelectionChange := @SelChanged;
  Result.OnModifiedChange := @ModChanged;
  Result.ResetCounts;
end;

procedure TTyRichEditApiTest.Changed(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TTyRichEditApiTest.SelChanged(Sender: TObject);
begin
  Inc(FSelChanges);
end;

procedure TTyRichEditApiTest.ModChanged(Sender: TObject);
begin
  Inc(FModChanges);
end;

procedure TTyRichEditApiTest.ResetEvents;
begin
  FChanges := 0;
  FSelChanges := 0;
  FModChanges := 0;
  if FRich <> nil then
  begin
    FRich.Refused := 0;
    FRich.LastReason := '';
  end;
end;

procedure TTyRichEditApiTest.SetText(const S: string);
begin
  FRich.Lines.Text := S;
  FRich.UpdateView;
  ResetEvents;
end;

procedure TTyRichEditApiTest.LoadBytes(const B: TBytes; AFinish: Boolean);
var
  st: TBytesStream;
begin
  st := TBytesStream.Create(B);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  if AFinish then FRich.FinishLoading;
  FRich.UpdateView;
  ResetEvents;
end;

procedure TTyRichEditApiTest.Sel(AStart, ALen: TTyRichPos);
begin
  FRich.SelStart := AStart;
  FRich.SelLength := ALen;
end;

procedure TTyRichEditApiTest.Chars(const S: RawByteString);
var
  i: Integer;
begin
  for i := 1 to Length(S) do FRich.Key8(S[i]);
end;

function TTyRichEditApiTest.Fmt(APos: TTyRichPos): TTyCharFormat;
var
  d: TTyRichDocument;
  p, i, k: Integer;
  runs: TTyRunArray;
  o: TTyRichPos;
begin
  d := FRich.Document;
  p := d.Text.ParaOfPos(APos);
  o := APos - d.Text.ParaStart(p);
  runs := d.RunsOf(p);
  k := 0;
  for i := 0 to High(runs) do
    if runs[i].Start <= o then k := i;
  Result := d.Formats.CharFormat(runs[k].Format);
end;

function TTyRichEditApiTest.PFmt(AIndex: Integer): TTyParaFormat;
begin
  Result := FRich.Document.Formats.ParaFormat(FRich.Document.ParaFormatOf(AIndex));
end;

{ The document as its paragraphs' text, format ids and runs: equal formats have equal ids. }
function TTyRichEditApiTest.Dump(AParas: Integer; AHistory: Boolean): string;
var
  d: TTyRichDocument;
  k, i: Integer;
  runs: TTyRunArray;
begin
  d := FRich.Document;
  Result := IntToStr(d.Text.Length);
  if AHistory then Result := Result + '/' + IntToStr(d.UndoDepth) + '/' + IntToStr(d.RedoDepth);
  for k := 0 to Math.Min(AParas, d.Text.ParaCount) - 1 do
  begin
    Result := Result + '[' + FRich.Lines[k] + '|' + IntToStr(d.ParaFormatOf(k));
    runs := d.RunsOf(k);
    for i := 0 to High(runs) do
      Result := Result + ' ' + IntToStr(runs[i].Start) + ':' + IntToStr(runs[i].Format);
    Result := Result + ']';
  end;
end;

function TTyRichEditApiTest.SavedRtf: TBytes;
var
  st: TMemoryStream;
begin
  st := TMemoryStream.Create;
  try
    FRich.SaveToStream(st, rfRtf);
    Result := nil;
    SetLength(Result, st.Size);
    if st.Size > 0 then Move(st.Memory^, Result[0], st.Size);
  finally
    st.Free;
  end;
end;

function TTyRichEditApiTest.TempDir: string;
begin
  if FTemp = '' then
  begin
    FTemp := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'tyrichedit11a-' +
      IntToStr(GetProcessID) + '-' + IntToHex(Random($7FFFFFFF), 8) + PathDelim;
    ForceDirectories(FTemp);
  end;
  Result := FTemp;
end;

procedure TTyRichEditApiTest.PaintAll;
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width * FPaintScale, FRich.Height * FPaintScale);
    FRich.PaintPart(bmp.Canvas, Rect(0, 0, FRich.Width, FRich.Height), True);
  finally
    bmp.Free;
  end;
end;

{ The kept surface after a paint equals the surface a full redraw makes. }
procedure TTyRichEditApiTest.CheckSurface(const AWhat: string);
var
  kept: TBGRABitmap;
  x, y, diff: Integer;
  a, b: PBGRAPixel;
begin
  PaintAll;
  AssertTrue(AWhat + ': a surface', FRich.Surf <> nil);
  kept := FRich.Surf.Duplicate as TBGRABitmap;
  try
    FRich.RedrawAll;
    PaintAll;
    diff := 0;
    for y := 0 to FRich.Height * FRich.Scale - 1 do
    begin
      a := kept.ScanLine[y];
      b := FRich.Surf.ScanLine[y];
      for x := 0 to FRich.Width * FRich.Scale - 1 do
      begin
        if (a^.red <> b^.red) or (a^.green <> b^.green) or (a^.blue <> b^.blue) or
          (a^.alpha <> b^.alpha) then Inc(diff);
        Inc(a);
        Inc(b);
      end;
    end;
    AssertEquals(AWhat + ': pixels that differ from a full redraw', 0, diff);
  finally
    kept.Free;
  end;
end;

{ 'abcdef': italic over 'abc', red over 'def', 14 pt over 'cd' - three attributes that vary. }
procedure TTyRichEditApiTest.MixedRuns;
var
  f: TTyCharFormat;
  d: TTyRichDocument;
begin
  SetText('abcdef');
  d := FRich.Document;
  f := TyDefaultCharFormat;
  f.Style := [fsItalic];
  d.Execute(TTyRichSetCharFormat.Create(TyRichRange(0, 3), [cffItalic], f));
  f.Color := clRed;
  d.Execute(TTyRichSetCharFormat.Create(TyRichRange(3, 3), [cffColor], f));
  f.SizeHalfPt := 28;
  d.Execute(TTyRichSetCharFormat.Create(TyRichRange(2, 2), [cffSize], f));
  d.ClearUndo;
  ResetEvents;
end;

{ ---- the brief's ---- }

{ The same format set through either façade gives equal documents; each is one command
  (TTyRichSetCharFormat / TTyRichSetParaFormat) of the history, and undone gives the document
  as it was. }
procedure TTyRichEditApiTest.TestBothFacadesGoThroughCommands;
var
  before, viaDelphi, viaMemo: string;
  p: TTyFontParams;
  depth: Integer;
begin
  SetText('abcdef'#10'second line');
  before := Dump;
  depth := FRich.Document.UndoDepth;
  // bold over 'bcd'
  Sel(1, 3);
  FRich.SelAttributes.Style := [fsBold];
  viaDelphi := Dump;
  AssertTrue('Delphi''s: a change', viaDelphi <> before);
  AssertEquals('Delphi''s: one step', depth + 1, FRich.Document.UndoDepth);
  AssertTrue('Delphi''s: a character format command',
    FRich.Document.UndoStep is TTyRichSetCharFormat);
  FRich.Undo;
  AssertEquals('Delphi''s undone', before, Dump);
  FRich.SetRangeParams(1, 3, [tmm_Styles], '', 0, clDefault, [fsBold], []);
  viaMemo := Dump;
  AssertEquals('the same document either way', viaDelphi, viaMemo);
  AssertTrue('RichMemo''s: a character format command',
    FRich.Document.UndoStep is TTyRichSetCharFormat);
  FRich.Undo;
  AssertEquals('RichMemo''s undone', before, Dump);
  // a whole font, both ways
  Sel(0, 4);
  FRich.SelAttributes.Name := 'Courier New';
  FRich.SelAttributes.Size := 15;
  viaDelphi := Dump;
  FRich.Undo;
  FRich.Undo;
  AssertEquals('two writes, two steps', before, Dump);
  FRich.SetRangeParams(0, 4, [tmm_Name, tmm_Size], 'Courier New', 15, clDefault, [], []);
  AssertEquals('the font either way', viaDelphi, Dump);
  FRich.Undo;
  FRich.SetRangeColor(0, 4, clBlue);
  viaMemo := Dump;
  FRich.Undo;
  AssertEquals('SetRangeColor undone', before, Dump);
  Sel(0, 4);
  FRich.SelAttributes.Color := clBlue;
  AssertEquals('the colour either way', viaMemo, Dump);
  FRich.Undo;
  // SetTextAttributes: the same fields as an Assign of a whole font through SelAttributes
  p := Default(TTyFontParams);
  p.Name := 'Arial';
  p.Size := 13;
  p.Color := clGreen;
  p.Style := [fsItalic];
  FRich.SetTextAttributes(0, 4, p);
  viaMemo := Dump;
  FRich.Undo;
  AssertEquals('SetTextAttributes undone', before, Dump);
  Sel(0, 4);
  FRich.SelAttributes.Name := 'Arial';
  FRich.SelAttributes.Size := 13;
  FRich.SelAttributes.Color := clGreen;
  FRich.SelAttributes.Style := [fsItalic];
  FRich.SelAttributes.BackColor := clNone;
  FRich.SelAttributes.VertAlign := vaNone;
  AssertEquals('a whole font either way', viaMemo, Dump);
  FRich.Undo;
  FRich.Undo;
  FRich.Undo;
  FRich.Undo;
  FRich.Undo;
  FRich.Undo;
  // the paragraph, both ways
  Sel(2, 9);
  FRich.Paragraph.Alignment := paraCenter;
  viaDelphi := Dump;
  AssertTrue('a paragraph format command', FRich.Document.UndoStep is TTyRichSetParaFormat);
  FRich.Undo;
  AssertEquals('the paragraphs undone', before, Dump);
  FRich.SetParaAlignment(2, 9, paraCenter);
  AssertEquals('the paragraphs either way', viaDelphi, Dump);
  AssertTrue('RichMemo''s: a paragraph format command',
    FRich.Document.UndoStep is TTyRichSetParaFormat);
  FRich.Undo;
  AssertEquals('RichMemo''s paragraphs undone', before, Dump);
end;

{ A selection that mixes bold and regular reports bold as not consistent (Delphi's caBold
  absent from ConsistentAttributes) - and so for every attribute; the value read is the
  selection's first character's. }
procedure TTyRichEditApiTest.TestSelAttributesReflectsMixedSelection;
type
  TCase = record
    Field: TTyCharFormatField;
    Attr: TTyRichConsistentAttribute;
  end;
const
  Cases: array[0..9] of TCase = (
    (Field: cffBold; Attr: caBold), (Field: cffItalic; Attr: caItalic),
    (Field: cffUnderline; Attr: caUnderline), (Field: cffStrike; Attr: caStrikeOut),
    (Field: cffFontName; Attr: caFace), (Field: cffSize; Attr: caSize),
    (Field: cffColor; Attr: caColor), (Field: cffCharset; Attr: caCharset),
    (Field: cffHighlight; Attr: caBackColor), (Field: cffVertAlign; Attr: caVertAlign));
  All = [Low(TTyRichConsistentAttribute)..High(TTyRichConsistentAttribute)];
var
  i: Integer;
  f: TTyCharFormat;
  ca: TTyRichConsistentAttributes;
begin
  // the brief's: bold and regular
  SetText('abcdef');
  f := TyDefaultCharFormat;
  f.Style := [fsBold];
  FRich.Document.Execute(TTyRichSetCharFormat.Create(TyRichRange(0, 3), [cffBold], f));
  Sel(1, 4);
  ca := FRich.SelAttributes.ConsistentAttributes;
  AssertFalse('mixed: bold not consistent', caBold in ca);
  AssertTrue('mixed: the rest consistent', ca = All - [caBold]);
  AssertTrue('the first character''s: bold', fsBold in FRich.SelAttributes.Style);
  Sel(3, 3);
  AssertTrue('all regular: consistent', caBold in FRich.SelAttributes.ConsistentAttributes);
  AssertFalse('all regular: not bold', fsBold in FRich.SelAttributes.Style);
  Sel(0, 3);
  AssertTrue('all bold: consistent', caBold in FRich.SelAttributes.ConsistentAttributes);
  AssertTrue('all bold: bold', fsBold in FRich.SelAttributes.Style);
  Sel(2, 0);
  AssertTrue('nothing selected: everything consistent',
    FRich.SelAttributes.ConsistentAttributes = All);
  // every attribute, one at a time
  for i := 0 to High(Cases) do
  begin
    SetText('abcdef');
    f := TyDefaultCharFormat;
    f.Style := [fsBold, fsItalic, fsUnderline];
    f.Strike := True;
    f.FontName := 'Courier New';
    f.SizeHalfPt := 30;
    f.Color := clRed;
    f.Charset := 134;
    f.HighlightColor := clYellow;
    f.VertAlign := vaSuper;
    FRich.Document.Execute(TTyRichSetCharFormat.Create(TyRichRange(2, 2), [Cases[i].Field], f));
    Sel(0, 6);
    ca := FRich.SelAttributes.ConsistentAttributes;
    AssertTrue(Format('field %d: that one differs, nothing else', [i]),
      ca = All - [Cases[i].Attr]);
    Sel(2, 2);
    AssertTrue(Format('field %d: consistent inside the run', [i]),
      FRich.SelAttributes.ConsistentAttributes = All);
    // the run alone at the end of the selection, and at its start
    Sel(3, 3);
    AssertFalse(Format('field %d: a run at the start differs from the rest', [i]),
      Cases[i].Attr in FRich.SelAttributes.ConsistentAttributes);
  end;
  // over paragraphs: an empty paragraph counts with its one run
  SetText('ab'#10#10'cd');
  f := TyDefaultCharFormat;
  f.Style := [fsBold];
  FRich.Document.Execute(TTyRichSetCharFormat.Create(TyRichRange(0, 6), [cffBold], f));
  Sel(0, 6);
  AssertTrue('all bold over three paragraphs', caBold in FRich.SelAttributes.ConsistentAttributes);
  FRich.Document.Execute(TTyRichSetCharFormat.Create(TyRichRange(4, 2), [cffBold],
    TyDefaultCharFormat));
  AssertFalse('the last paragraph regular', caBold in FRich.SelAttributes.ConsistentAttributes);
end;

{ ---- the character façades ---- }

{ Each attribute written over a selection of mixed runs changes that attribute only: the
  italic, the colour and the size each run had stay. }
procedure TTyRichEditApiTest.TestEachCharAttributeAloneLeavesTheOthers;

  procedure CheckOthers(const AWhat: string; ANot: TTyCharFormatMask);
  begin
    if not (cffItalic in ANot) then
    begin
      AssertTrue(AWhat + ': a keeps italic', fsItalic in Fmt(0).Style);
      AssertFalse(AWhat + ': e stays upright', fsItalic in Fmt(4).Style);
    end;
    if not (cffColor in ANot) then
    begin
      AssertEquals(AWhat + ': a keeps its colour', clDefault, Fmt(0).Color);
      AssertEquals(AWhat + ': e keeps red', clRed, Fmt(4).Color);
    end;
    if not (cffSize in ANot) then
    begin
      AssertEquals(AWhat + ': a keeps its size', 0, Fmt(0).SizeHalfPt);
      AssertEquals(AWhat + ': c keeps 14 pt', 28, Fmt(2).SizeHalfPt);
    end;
  end;

var
  i: Integer;
  fnt: TFont;
begin
  MixedRuns;
  Sel(0, 6);
  FRich.SelAttributes.Name := 'Courier New';
  for i := 0 to 5 do AssertEquals('the name everywhere', 'Courier New', Fmt(i).FontName);
  AssertEquals('read back', 'Courier New', FRich.SelAttributes.Name);
  CheckOthers('Name', []);
  MixedRuns;
  Sel(0, 6);
  FRich.SelAttributes.Size := 9;
  for i := 0 to 5 do AssertEquals('the size everywhere', 18, Fmt(i).SizeHalfPt);
  AssertEquals('read back', 9, FRich.SelAttributes.Size);
  CheckOthers('Size', [cffSize]);
  MixedRuns;
  Sel(0, 6);
  FRich.SelAttributes.Style := [fsBold, fsStrikeOut];
  for i := 0 to 5 do
  begin
    AssertTrue('bold everywhere', fsBold in Fmt(i).Style);
    AssertTrue('struck out everywhere', Fmt(i).Strike);
    AssertFalse('Style is all four: italic goes', fsItalic in Fmt(i).Style);
  end;
  AssertTrue('read back', FRich.SelAttributes.Style = [fsBold, fsStrikeOut]);
  CheckOthers('Style', [cffItalic]);
  MixedRuns;
  Sel(0, 6);
  FRich.SelAttributes.Color := clGreen;
  for i := 0 to 5 do AssertEquals('green everywhere', clGreen, Fmt(i).Color);
  AssertEquals('read back', clGreen, FRich.SelAttributes.Color);
  CheckOthers('Color', [cffColor]);
  MixedRuns;
  Sel(0, 6);
  FRich.SelAttributes.Charset := 134;
  for i := 0 to 5 do AssertEquals('the charset everywhere', 134, Fmt(i).Charset);
  AssertEquals('read back', 134, FRich.SelAttributes.Charset);
  CheckOthers('Charset', []);
  MixedRuns;
  Sel(0, 6);
  FRich.SelAttributes.BackColor := clYellow;
  for i := 0 to 5 do AssertEquals('highlighted everywhere', clYellow, Fmt(i).HighlightColor);
  AssertEquals('read back', clYellow, FRich.SelAttributes.BackColor);
  CheckOthers('BackColor', []);
  MixedRuns;
  Sel(0, 6);
  FRich.SelAttributes.VertAlign := vaSub;
  for i := 0 to 5 do AssertTrue('subscript everywhere', Fmt(i).VertAlign = vaSub);
  AssertTrue('read back', FRich.SelAttributes.VertAlign = vaSub);
  CheckOthers('VertAlign', []);
  // Assign from a TFont: name, size, styles, colour, charset at once - one step
  MixedRuns;
  Sel(0, 6);
  FRich.SelAttributes.Assign(FRich.DefAttributes);
  AssertEquals('Assign from DefAttributes: one step', 1, FRich.Document.UndoDepth);
  MixedRuns;
  Sel(0, 6);
  fnt := TFont.Create;
  try
    fnt.Name := 'Arial';
    fnt.Size := 11;
    fnt.Style := [fsUnderline];
    fnt.Color := clMaroon;
    FRich.SelAttributes.Assign(fnt);
  finally
    fnt.Free;
  end;
  AssertEquals('Assign(TFont): one step', 1, FRich.Document.UndoDepth);
  AssertEquals('its name', 'Arial', Fmt(4).FontName);
  AssertEquals('its size', 22, Fmt(0).SizeHalfPt);
  AssertTrue('its style (italic gone)', Fmt(0).Style = [fsUnderline]);
  AssertEquals('its colour', clMaroon, Fmt(5).Color);
  // AssignTo a TFont
  fnt := TFont.Create;
  try
    fnt.Assign(FRich.SelAttributes);
    AssertEquals('AssignTo: the name', 'Arial', fnt.Name);
    AssertEquals('AssignTo: the size', 11, fnt.Size);
    AssertTrue('AssignTo: the style', fnt.Style = [fsUnderline]);
    AssertEquals('AssignTo: the colour', clMaroon, fnt.Color);
  finally
    fnt.Free;
  end;
end;

{ RichMemo's character methods: SetTextAttributes writes all its fields, GetTextAttributes
  reads one character's, SetRangeParams only what its mask names, the styles added and taken
  off one by one, SetRangeColor the colour. }
procedure TTyRichEditApiTest.TestTheRichMemoCharMethods;
var
  p, q: TTyFontParams;
  fnt: TFont;
begin
  MixedRuns;
  p := Default(TTyFontParams);
  p.Name := 'Courier New';
  p.Size := 16;
  p.Color := clNavy;
  p.Style := [fsBold, fsUnderline];
  p.HasBkClr := True;
  p.BkColor := clAqua;
  p.VScriptPos := vpSuperScript;
  FRich.SetTextAttributes(1, 2, p);
  q := Default(TTyFontParams);
  AssertTrue('read', FRich.GetTextAttributes(1, q));
  AssertEquals('name', 'Courier New', q.Name);
  AssertEquals('size', 16, q.Size);
  AssertEquals('colour', clNavy, q.Color);
  AssertTrue('styles', q.Style = [fsBold, fsUnderline]);
  AssertTrue('a highlight', q.HasBkClr);
  AssertEquals('its colour', clAqua, q.BkColor);
  AssertTrue('superscript', q.VScriptPos = vpSuperScript);
  AssertTrue('the character before: not touched', FRich.GetTextAttributes(0, q));
  AssertTrue('italic still', fsItalic in q.Style);
  AssertFalse('no highlight', q.HasBkClr);
  AssertTrue('a name of its own resolved: the base''s', q.Name <> '');
  AssertTrue('a size resolved', q.Size > 0);
  AssertFalse('outside the text', FRich.GetTextAttributes(100, q));
  AssertFalse('before it', FRich.GetTextAttributes(-1, q));
  // at a paragraph's end: its last run's
  AssertTrue('at the end', FRich.GetTextAttributes(6, q));
  AssertEquals('the last run''s colour', clRed, q.Color);
  // SetRangeParams: the mask's fields only
  MixedRuns;
  FRich.SetRangeParams(0, 6, [tmm_Styles], 'Ignored', 99, clLime, [fsBold], [fsItalic]);
  AssertTrue('bold added', fsBold in Fmt(0).Style);
  AssertFalse('italic taken off', fsItalic in Fmt(0).Style);
  AssertEquals('the name not touched', '', Fmt(0).FontName);
  AssertEquals('the colour not touched', clRed, Fmt(4).Color);
  AssertEquals('the size not touched', 28, Fmt(2).SizeHalfPt);
  MixedRuns;
  FRich.SetRangeParams(0, 6, [tmm_Styles], '', 0, clDefault, [fsUnderline], []);
  AssertTrue('underline added', fsUnderline in Fmt(0).Style);
  AssertTrue('italic kept (not named)', fsItalic in Fmt(0).Style);
  MixedRuns;
  FRich.SetRangeParams(0, 6, [tmm_Name, tmm_Size], 'Arial', 20, clLime, [fsBold], []);
  AssertEquals('the name', 'Arial', Fmt(5).FontName);
  AssertEquals('the size', 40, Fmt(5).SizeHalfPt);
  AssertFalse('no styles asked: none changed', fsBold in Fmt(0).Style);
  AssertEquals('no colour asked', clRed, Fmt(5).Color);
  MixedRuns;
  q := Default(TTyFontParams);
  q.HasBkClr := True;
  q.BkColor := clYellow;
  FRich.SetRangeParams(0, 6, [tmm_BackColor, tmm_Color], q, [], []);
  AssertEquals('highlight', clYellow, Fmt(0).HighlightColor);
  AssertEquals('the colour of the record', q.Color, Fmt(4).Color);
  MixedRuns;
  FRich.SetRangeColor(1, 4, clPurple);
  AssertEquals('coloured', clPurple, Fmt(4).Color);
  AssertEquals('outside: as it was', clRed, Fmt(5).Color);
  AssertTrue('italic kept', fsItalic in Fmt(1).Style);
  // a range past the text is clamped
  MixedRuns;
  FRich.SetRangeColor(4, 100, clTeal);
  AssertEquals('clamped: the last', clTeal, Fmt(5).Color);
  // a TFont
  MixedRuns;
  fnt := TFont.Create;
  try
    fnt.Name := 'Arial';
    fnt.Size := 11;
    fnt.Style := [fsUnderline];
    fnt.Color := clMaroon;
    FRich.SetTextAttributes(0, 6, fnt);
  finally
    fnt.Free;
  end;
  AssertEquals('the font''s name', 'Arial', Fmt(0).FontName);
  AssertEquals('the font''s size', 22, Fmt(3).SizeHalfPt);
  AssertTrue('the font''s style', Fmt(0).Style = [fsUnderline]);
  AssertEquals('the font''s colour', clMaroon, Fmt(5).Color);
  AssertEquals('one step', 1, FRich.Document.UndoDepth);
end;

{ Size in points of the engine's half points; Height in pixels at the control's PPI. }
procedure TTyRichEditApiTest.TestHeightAndSizeUnits;
begin
  SetText('abc');
  Sel(0, 3);
  FRich.SelAttributes.Size := 12;
  AssertEquals('12 pt: 24 half points', 24, Fmt(0).SizeHalfPt);
  AssertEquals('Height at 96 PPI', 16, FRich.SelAttributes.Height);
  FRich.SelAttributes.Height := 32;
  AssertEquals('32 px: 24 pt', 48, Fmt(1).SizeHalfPt);
  AssertEquals('read in points', 24, FRich.SelAttributes.Size);
  FRich.Font.PixelsPerInch := 192;
  AssertEquals('Height at 192 PPI', 64, FRich.SelAttributes.Height);
  // 10.5 pt reads 10, as Delphi's
  FRich.Document.Execute(TTyRichSetCharFormat.Create(TyRichRange(0, 3), [cffSize],
    TyRichCharFormatOf(Default(TTyFontParams))));
  AssertTrue('a size of none: the base''s', FRich.SelAttributes.Size > 0);
end;

{ Paragraph in Delphi's units and meanings: FirstIndent where the first line starts, LeftIndent
  the other lines from it, points; the engine keeps twips (\li, \fi). }
procedure TTyRichEditApiTest.TestParagraphInDelphisUnits;
var
  f: TTyParaFormat;
begin
  SetText('one'#10'two'#10'three');
  Sel(1, 5);
  FRich.Paragraph.FirstIndent := 36;
  f := PFmt(0);
  AssertEquals('first line at 36 pt: li', 720, f.LeftIndent);
  AssertEquals('fi none', 0, f.FirstIndent);
  AssertEquals('the second paragraph too', 720, PFmt(1).LeftIndent);
  AssertEquals('the third not touched', 0, PFmt(2).LeftIndent);
  FRich.Paragraph.LeftIndent := -18;
  f := PFmt(0);
  AssertEquals('a hanging indent: the first line stays', 720, f.LeftIndent + f.FirstIndent);
  AssertEquals('the others 18 pt left of it', 360, f.LeftIndent);
  AssertEquals('FirstIndent read', 36, FRich.Paragraph.FirstIndent);
  AssertEquals('LeftIndent read', -18, FRich.Paragraph.LeftIndent);
  FRich.Paragraph.FirstIndent := 72;
  f := PFmt(1);
  AssertEquals('moved whole: the first line', 1440, f.LeftIndent + f.FirstIndent);
  AssertEquals('the others keep their offset', -18, FRich.Paragraph.LeftIndent);
  FRich.Paragraph.RightIndent := 9;
  AssertEquals('right', 180, PFmt(0).RightIndent);
  AssertEquals('right read', 9, FRich.Paragraph.RightIndent);
  FRich.Paragraph.SpaceBefore := 6;
  FRich.Paragraph.SpaceAfter := 12;
  AssertEquals('before', 120, PFmt(1).SpaceBefore);
  AssertEquals('after', 240, PFmt(1).SpaceAfter);
  AssertEquals('before read', 6, FRich.Paragraph.SpaceBefore);
  AssertEquals('after read', 12, FRich.Paragraph.SpaceAfter);
  FRich.Paragraph.LineSpacingRule := ls15;
  AssertTrue('one and a half', PFmt(0).LineSpacing = ls15);
  AssertEquals('no height for a multiple', 0, FRich.Paragraph.LineSpacing);
  FRich.Paragraph.LineSpacing := 20;
  AssertTrue('a height: at least', PFmt(0).LineSpacing = lsAtLeast);
  AssertEquals('its twips', 400, PFmt(0).LineSpacingValue);
  AssertEquals('read', 20, FRich.Paragraph.LineSpacing);
  FRich.Paragraph.LineSpacingRule := lsExact;
  AssertEquals('exactly: the height kept', 400, PFmt(1).LineSpacingValue);
  FRich.Paragraph.Alignment := paraRight;
  AssertTrue('right-aligned', PFmt(1).Align = paraRight);
  AssertTrue('read', FRich.Paragraph.Alignment = paraRight);
  FRich.Paragraph.Numbering := lkUpperRoman;
  AssertTrue('a list', PFmt(0).List.Kind = lkUpperRoman);
  AssertEquals('it starts at 1', 1, FRich.Paragraph.NumberingStart);
  FRich.Paragraph.NumberingStart := 4;
  AssertEquals('from 4', 4, PFmt(1).List.StartAt);
  AssertTrue('the kind kept', FRich.Paragraph.Numbering = lkUpperRoman);
  // tabs
  AssertEquals('no tabs', 0, FRich.Paragraph.TabCount);
  FRich.Paragraph.Tab[1] := 72;
  AssertEquals('two stops (the first at 0)', 2, Length(PFmt(0).Tabs));
  AssertEquals('the second at 1 inch', 1440, PFmt(0).Tabs[1].Position);
  FRich.Paragraph.Tab[0] := 36;
  AssertEquals('read', 36, FRich.Paragraph.Tab[0]);
  AssertEquals('count', 2, FRich.Paragraph.TabCount);
  FRich.Paragraph.TabCount := 1;
  AssertEquals('cut to one', 1, Length(PFmt(1).Tabs));
  AssertEquals('the first kept', 720, PFmt(1).Tabs[0].Position);
  try
    FRich.Paragraph.TabCount := 5;
    Fail('more stops than there are');
  except
    on EListError do ;
  end;
  // rounding of twips to points: half a point away from zero
  FRich.Document.Execute(TTyRichSetParaFormat.Create(0, 0, [pffRightIndent],
    TyRichParaFormatOfMetric(Default(TTyParaMetric))));
  AssertEquals('twips to points', 1, TyRichTwipsToPt(10));
  AssertEquals('twips to points, negative', -1, TyRichTwipsToPt(-10));
  AssertEquals('twips to points, below half', 0, TyRichTwipsToPt(9));
end;

{ RichMemo's paragraph methods, in points as Doubles (exact to the twip). }
procedure TTyRichEditApiTest.TestTheRichMemoParagraphMethods;
var
  m: TTyParaMetric;
  n: TTyParaNumbering;
  tl: TTyTabStopList;
  al: TTyParaAlign;
  f: TTyParaFormat;
begin
  SetText('one'#10'two'#10'three');
  m := Default(TTyParaMetric);
  m.FirstLine := 36;
  m.HeadIndent := 18;
  m.TailIndent := 9.5;
  m.SpaceBefore := 1.5;
  m.SpaceAfter := 3;
  m.LineSpacing := 2.0;
  FRich.SetParaMetric(0, 5, m);
  f := PFmt(1);
  AssertEquals('head: li', 360, f.LeftIndent);
  AssertEquals('first line: li + fi', 720, f.LeftIndent + f.FirstIndent);
  AssertEquals('tail', 190, f.RightIndent);
  AssertEquals('before', 30, f.SpaceBefore);
  AssertEquals('after', 60, f.SpaceAfter);
  AssertTrue('double', f.LineSpacing = lsDouble);
  AssertEquals('the third untouched', 0, PFmt(2).LeftIndent);
  m := Default(TTyParaMetric);
  AssertTrue('read', FRich.GetParaMetric(4, m));
  AssertEquals('first line read', 36.0, m.FirstLine, 0.0001);
  AssertEquals('head read', 18.0, m.HeadIndent, 0.0001);
  AssertEquals('tail read', 9.5, m.TailIndent, 0.0001);
  AssertEquals('before read', 1.5, m.SpaceBefore, 0.0001);
  AssertEquals('spacing read', 2.0, m.LineSpacing, 0.0001);
  AssertFalse('outside', FRich.GetParaMetric(1000, m));
  m.LineSpacing := 1.2;
  FRich.SetParaMetric(0, 0, m);
  AssertTrue('1.2: the nearest of the rules', PFmt(0).LineSpacing = ls115);
  // alignment
  FRich.SetParaAlignment(4, 0, paraJustify);
  AssertTrue('justified', PFmt(1).Align = paraJustify);
  AssertTrue('the first not', PFmt(0).Align = paraLeft);
  al := paraLeft;
  AssertTrue('read', FRich.GetParaAlignment(5, al));
  AssertTrue('its value', al = paraJustify);
  AssertTrue('the function', FRich.GetParaAlignment(5) = paraJustify);
  // numbering
  n := Default(TTyParaNumbering);
  n.Style := pnLowLetter;
  n.NumberStart := 3;
  FRich.SetParaNumbering(0, 100, n);
  AssertTrue('lettered', PFmt(2).List.Kind = lkLowerAlpha);
  AssertEquals('from 3', 3, PFmt(2).List.StartAt);
  n := Default(TTyParaNumbering);
  AssertTrue('read', FRich.GetParaNumbering(0, n));
  AssertTrue('its style', n.Style = pnLowLetter);
  AssertEquals('its start', 3, n.NumberStart);
  n.Style := pnCustomChar;
  FRich.SetParaNumbering(0, 0, n);
  AssertTrue('a custom character: a bullet', PFmt(0).List.Kind = lkBullet);
  // tabs
  tl := Default(TTyTabStopList);
  tl.Count := 2;
  SetLength(tl.Tabs, 2);
  tl.Tabs[0].Offset := 36;
  tl.Tabs[0].Align := ttaCenter;
  tl.Tabs[1].Offset := 72.5;
  tl.Tabs[1].Align := ttaDecimal;
  FRich.SetParaTabs(0, 0, tl);
  AssertEquals('two stops', 2, Length(PFmt(0).Tabs));
  AssertEquals('the second', 1450, PFmt(0).Tabs[1].Position);
  AssertTrue('its alignment', PFmt(0).Tabs[1].Align = ttaDecimal);
  AssertEquals('the next paragraph none', 0, Length(PFmt(1).Tabs));
  tl := Default(TTyTabStopList);
  AssertTrue('read', FRich.GetParaTabs(1, tl));
  AssertEquals('count', 2, tl.Count);
  AssertEquals('offset', 72.5, tl.Tabs[1].Offset, 0.0001);
  AssertTrue('alignment', tl.Tabs[0].Align = ttaCenter);
end;

{ A paragraph write with nothing selected changes the caret's paragraph at once: a command,
  one step, one OnChange. }
procedure TTyRichEditApiTest.TestAParagraphWriteWithNothingSelected;
var
  depth: Integer;
begin
  SetText('one'#10'two'#10'three');
  FRich.SelStart := 5;
  depth := FRich.Document.UndoDepth;
  FRich.Paragraph.Alignment := paraCenter;
  AssertTrue('the caret''s paragraph', PFmt(1).Align = paraCenter);
  AssertTrue('only it', (PFmt(0).Align = paraLeft) and (PFmt(2).Align = paraLeft));
  AssertEquals('a step', depth + 1, FRich.Document.UndoDepth);
  AssertEquals('one OnChange', 1, FChanges);
  // a selection that ends at a paragraph's very start does not touch that paragraph
  Sel(0, 4);
  FRich.Paragraph.Alignment := paraRight;
  AssertTrue('the first', PFmt(0).Align = paraRight);
  AssertTrue('not the second', PFmt(1).Align = paraCenter);
end;

{ DefAttributes is the control's Font over the theme: one truth. Writing it sets the Font
  (no command, no undo step, not Modified) and the text without a format of its own shows
  in it; reading it gives the base as resolved. }
procedure TTyRichEditApiTest.TestDefAttributesIsTheControlsFont;
var
  depth: Integer;
  f: TTyCharFormat;
begin
  SetText('plain text');
  FRich.Modified := False;
  depth := FRich.Document.UndoDepth;
  AssertTrue('a name before anything is set (the theme''s)', FRich.DefAttributes.Name <> '');
  FRich.DefAttributes.Name := 'Courier New';
  AssertEquals('the Font', 'Courier New', FRich.Font.Name);
  AssertEquals('read back', 'Courier New', FRich.DefAttributes.Name);
  FRich.UpdateView;
  AssertEquals('the layout''s base', 'Courier New', FRich.Layouter.BaseFontName);
  Sel(0, 3);
  AssertEquals('plain text reads it', 'Courier New', FRich.SelAttributes.Name);
  FRich.DefAttributes.Size := 14;
  AssertEquals('the Font''s size', 14, FRich.Font.Size);
  AssertEquals('read back', 14, FRich.DefAttributes.Size);
  FRich.UpdateView;
  AssertEquals('the layout''s size', 28, FRich.Layouter.BaseFontSizeHalfPt);
  AssertEquals('plain text''s size', 14, FRich.SelAttributes.Size);
  FRich.DefAttributes.Style := [fsBold];
  AssertTrue('the Font''s style', fsBold in FRich.Font.Style);
  AssertTrue('read back', fsBold in FRich.DefAttributes.Style);
  FRich.DefAttributes.Color := clRed;
  AssertEquals('the Font''s colour', clRed, FRich.Font.Color);
  AssertEquals('read back', clRed, FRich.DefAttributes.Color);
  AssertEquals('the paint''s text colour', 255, FRich.Style.TextColor.red);
  AssertEquals('no undo step', depth, FRich.Document.UndoDepth);
  AssertFalse('not a change of the content', FRich.Modified);
  AssertTrue('every attribute consistent', FRich.DefAttributes.ConsistentAttributes =
    [Low(TTyRichConsistentAttribute)..High(TTyRichConsistentAttribute)]);
  try
    FRich.DefAttributes.BackColor := clYellow;
    Fail('the base has no highlight');
  except
    on ETyRichEdit do ;
  end;
  try
    FRich.DefAttributes.VertAlign := vaSuper;
    Fail('the base has no vertical position');
  except
    on ETyRichEdit do ;
  end;
  // an Assign of SelAttributes (clNone, vaNone) is fine
  f := FRich.Document.Formats.CharFormat(FRich.Document.DefaultCharFormatId);
  AssertEquals('the document''s default has no name of its own', '', f.FontName);
  FRich.DefAttributes.Assign(FRich.SelAttributes);
  AssertEquals('assigned', 'Courier New', FRich.Font.Name);
end;

{ PlainText both ways (R65): only a load and the property set it; Lines.Text, SelText leave
  it; True - the saves without a format write text, the loads read text when it was set by
  code; False - by the file; setting it strips nothing. }
procedure TTyRichEditApiTest.TestPlainTextBothWaysWithLoadAndSave;
var
  st: TMemoryStream;
  s: RawByteString;
  path: string;
  b: TBytes;
begin
  AssertFalse('a new control is rich', FRich.PlainText);
  SetText('one'#10'two');
  AssertFalse('Lines.Text: still rich', FRich.PlainText);
  FRich.SelStart := 0;
  FRich.SelText := 'x';
  AssertFalse('SelText: still rich', FRich.PlainText);
  Sel(0, 2);
  FRich.SelAttributes.Style := [fsBold];
  // a rich document saves RTF
  s := StrOf(SavedRtf);
  st := TMemoryStream.Create;
  try
    FRich.SaveToStream(st);
    SetLength(s, st.Size);
    Move(st.Memory^, s[1], st.Size);
  finally
    st.Free;
  end;
  AssertEquals('rich: RTF', '{' + BS + 'rtf1', Copy(s, 1, 6));
  // made plain: nothing stripped, the save is text
  FRich.PlainText := True;
  AssertTrue('the bold stays', fsBold in Fmt(0).Style);
  st := TMemoryStream.Create;
  try
    FRich.SaveToStream(st);
    SetLength(s, st.Size);
    Move(st.Memory^, s[1], st.Size);
  finally
    st.Free;
  end;
  AssertEquals('plain: the characters only (the line break the text has)', 'xone'#10'two', s);
  FRich.Lines.Text := 'new';
  AssertTrue('Lines.Text: still plain', FRich.PlainText);
  // a load decides: RTF read as text while it was set by code
  LoadBytes(PlainRtf(2));
  AssertTrue('set by code: an RTF file read as text', FRich.PlainText);
  AssertEquals('its signature is text', '{' + BS + 'rtf1' + BS + 'ansi' + BS + 'deff0{' + BS +
    'fonttbl{' + BS + 'f0 Arial;}}', FRich.Lines[0]);
  FRich.PlainText := False;
  LoadBytes(PlainRtf(2));
  AssertFalse('an RTF file: rich', FRich.PlainText);
  AssertEquals('read as RTF', 'Paragraph 0 of the file.', FRich.Lines[0]);
  LoadBytes(RawBytes('a text file'));
  AssertTrue('a text file: plain', FRich.PlainText);
  LoadBytes(PlainRtf(2));
  AssertFalse('the next RTF file goes by the file', FRich.PlainText);
  // Lines' load and save are the control's
  st := TMemoryStream.Create;
  try
    FRich.Lines.SaveToStream(st);
    SetLength(s, st.Size);
    Move(st.Memory^, s[1], st.Size);
  finally
    st.Free;
  end;
  AssertEquals('Lines.SaveToStream of a rich document: RTF', '{' + BS + 'rtf1', Copy(s, 1, 6));
  path := TempDir + 'lines.rtf';
  FRich.Lines.SaveToFile(path);
  SetText('');
  FRich.Lines.LoadFromFile(path);
  AssertFalse('Lines.LoadFromFile of an RTF file: rich', FRich.PlainText);
  AssertEquals('read as RTF', 'Paragraph 1 of the file.', FRich.Lines[1]);
  // SaveToFile without a format: plain text whatever the extension
  FRich.PlainText := True;
  path := TempDir + 'plain.rtf';
  FRich.SaveToFile(path);
  b := FileBytes(path);
  AssertEquals('plain: text in a .rtf', 'Paragraph 0 of the file.', Copy(StrOf(b), 1, 24));
  AssertFalse('a plain save keeps the content: not Modified', FRich.Modified);
  FRich.PlainText := False;
  path := TempDir + 'rich.txt';
  FRich.SaveToFile(path, rfRtf);
  AssertEquals('an explicit format wins', '{' + BS + 'rtf1', Copy(StrOf(FileBytes(path)), 1, 6));
end;

{ A plain-text document pastes text only and makes a paragraph of Shift+Enter (R60); a rich
  one filled through Lines pastes RTF (R65: the probe seam W13 needed is gone). }
procedure TTyRichEditApiTest.TestPlainTextAndThePaste;
const
  Bold = '{' + BS + 'rtf1' + BS + 'ansi{' + BS + 'b bold}}';
begin
  SetText('ab');
  FRich.SelStart := 1;
  FRich.ClipReset;
  FRich.ClipRtf := Bold;
  FRich.ClipText := 'bold';
  FRich.PasteFromClipboard;
  AssertTrue('rich through Lines: the RTF went in bold', fsBold in Fmt(1).Style);
  SetText('ab');
  FRich.PlainText := True;
  FRich.SelStart := 1;
  FRich.PasteFromClipboard;
  AssertEquals('plain: the text', 'aboldb', FRich.Lines[0]);
  AssertFalse('plain: not bold', fsBold in Fmt(1).Style);
end;

{ ---- the pending format ---- }

{ With nothing selected a write sets the format the next typed text gets: no text changes, no
  command, no undo step, no OnChange; SelAttributes shows it; typing uses it and the typed
  text carries it on. }
procedure TTyRichEditApiTest.TestThePendingFormat;
var
  depth: Integer;
  p: TTyFontParams;
begin
  SetText('ab');
  FRich.SelStart := 1;
  depth := FRich.Document.UndoDepth;
  ResetEvents;
  FRich.SelAttributes.Style := [fsBold];
  FRich.SelAttributes.Color := clRed;
  AssertEquals('no text changed', 'ab', FRich.Lines[0]);
  AssertEquals('no undo step', depth, FRich.Document.UndoDepth);
  AssertEquals('no OnChange', 0, FChanges);
  AssertEquals('no selection change', 0, FSelChanges);
  AssertFalse('not Modified', FRich.Modified);
  AssertTrue('shown: bold', fsBold in FRich.SelAttributes.Style);
  AssertEquals('shown: red (both writes)', clRed, FRich.SelAttributes.Color);
  AssertFalse('the text before it is not', fsBold in Fmt(0).Style);
  Chars('x');
  AssertEquals('typed', 'axb', FRich.Lines[0]);
  AssertTrue('typed bold', fsBold in Fmt(1).Style);
  AssertEquals('typed red', clRed, Fmt(1).Color);
  AssertFalse('b not', fsBold in Fmt(2).Style);
  Chars('y');
  AssertTrue('the next typed carries it', fsBold in Fmt(2).Style);
  AssertEquals('one typing step', depth + 1, FRich.Document.UndoDepth);
  // RichMemo's: length 0 at the caret; elsewhere nothing
  FRich.SelStart := 0;
  p := Default(TTyFontParams);
  p.Name := 'Courier New';
  p.Size := 20;
  FRich.SetTextAttributes(0, 0, p);
  AssertEquals('pending through RichMemo''s', 'Courier New', FRich.SelAttributes.Name);
  Chars('q');
  AssertEquals('typed in it', 'Courier New', Fmt(0).FontName);
  AssertEquals('its size', 40, Fmt(0).SizeHalfPt);
  FRich.SelStart := 2;
  FRich.SetTextAttributes(4, 0, p);
  AssertTrue('length 0 away from the caret: nothing',
    FRich.SelAttributes.Name <> 'Courier New');
  FRich.SetRangeColor(2, 0, clGreen);
  AssertEquals('SetRangeColor at the caret: pending', clGreen, FRich.SelAttributes.Color);
end;

{ Each way a pending format ends: the selection set again (even to the same place), a key's
  move, an edit other than typing, a change from code, an undo, a new content. }
procedure TTyRichEditApiTest.TestEachWayThePendingFormatEnds;

  procedure Pend;
  begin
    FRich.SelAttributes.Style := [fsBold];
    AssertTrue('pending', fsBold in FRich.SelAttributes.Style);
  end;

begin
  SetText('abcd');
  FRich.SelStart := 2;
  Pend;
  FRich.SelStart := 2;
  AssertFalse('the same place set again: gone', fsBold in FRich.SelAttributes.Style);
  Chars('x');
  AssertFalse('typed regular', fsBold in Fmt(2).Style);
  FRich.SelStart := 2;
  Pend;
  FRich.Press(VK_RIGHT, []);
  FRich.Press(VK_LEFT, []);
  AssertFalse('a key''s move', fsBold in FRich.SelAttributes.Style);
  Pend;
  FRich.Press(VK_BACK, []);
  AssertFalse('Backspace', fsBold in FRich.SelAttributes.Style);
  Pend;
  FRich.Document.Execute(TTyRichInsertText.Create(4, 'z'));
  AssertFalse('a change from code', fsBold in FRich.SelAttributes.Style);
  FRich.SelStart := 1;
  Pend;
  FRich.Undo;
  AssertFalse('an undo', fsBold in FRich.SelAttributes.Style);
  Pend;
  FRich.Lines.Text := 'new';
  AssertFalse('a new content', fsBold in FRich.SelAttributes.Style);
  // a paragraph write keeps it
  FRich.SelStart := 1;
  Pend;
  FRich.Paragraph.Alignment := paraCenter;
  AssertTrue('a paragraph write keeps it', fsBold in FRich.SelAttributes.Style);
  Chars('k');
  AssertTrue('typed bold after it', fsBold in Fmt(1).Style);
  // a selection, then a write: no pending, a command
  Sel(0, 1);
  FRich.SelAttributes.Style := [fsItalic];
  FRich.SelStart := 1;
  AssertFalse('the caret after an italic character: no pending',
    fsBold in FRich.SelAttributes.Style);
end;

{ The pending format with a composition (shown and committed in it) and with a paste of plain
  text. }
procedure TTyRichEditApiTest.TestThePendingFormatWithACompositionAndAPaste;
begin
  SetText('ab');
  FRich.SelStart := 1;
  FRich.SelAttributes.Style := [fsBold];
  FRich.UpdateComposition('zh');
  AssertTrue('composing', FRich.Composing);
  FRich.CommitComposition('zh');
  AssertEquals('committed', 'azhb', FRich.Lines[0]);
  AssertTrue('in the pending format', fsBold in Fmt(1).Style);
  AssertTrue('both characters', fsBold in Fmt(2).Style);
  // a write while composing ends the composition first, then applies
  SetText('ab');
  FRich.SelStart := 1;
  FRich.UpdateComposition('q');
  FRich.SelAttributes.Style := [fsItalic];
  AssertFalse('the composition ended', FRich.Composing);
  AssertEquals('committed first', 'aqb', FRich.Lines[0]);
  Chars('r');
  AssertTrue('the pending format after the commit', fsItalic in Fmt(2).Style);
  AssertFalse('the commit not', fsItalic in Fmt(1).Style);
  // a paste of plain text
  SetText('ab');
  FRich.SelStart := 1;
  FRich.SelAttributes.Color := clRed;
  FRich.ClipReset;
  FRich.ClipRtf := '';
  FRich.ClipText := 'zz';
  FRich.PasteFromClipboard;
  AssertEquals('pasted', 'azzb', FRich.Lines[0]);
  AssertEquals('in the pending format', clRed, Fmt(2).Color);
  AssertFalse('b not', Fmt(3).Color = clRed);
  FRich.SelStart := 4;
  AssertFalse('used once: gone', FRich.SelAttributes.Color = clRed);
end;

{ ---- commands, the history, the events ---- }

{ A format write is one step; its undo puts the selection back as it was before the step (R55),
  its redo where the write left it. }
procedure TTyRichEditApiTest.TestAFormatWriteIsOneStepThatPutsTheSelectionBack;
begin
  SetText('abcdef');
  FRich.SelStart := 5;
  FRich.SelStart := 4;
  FRich.SelLength := -3;
  FRich.SelAttributes.Style := [fsBold];
  AssertEquals('the selection stays: start', Int64(1), FRich.SelStart);
  AssertEquals('the selection stays: length', Int64(3), FRich.SelLength);
  AssertEquals('the caret stays where it was', Int64(1), FRich.CaretPos);
  FRich.SelStart := 0;
  FRich.Undo;
  AssertFalse('undone', fsBold in Fmt(2).Style);
  AssertEquals('the selection back: start', Int64(1), FRich.SelStart);
  AssertEquals('the selection back: length', Int64(3), FRich.SelLength);
  AssertEquals('its caret', Int64(1), FRich.CaretPos);
  FRich.SelStart := 6;
  FRich.Redo;
  AssertTrue('redone', fsBold in Fmt(2).Style);
  AssertEquals('the caret where the write left it', Int64(1), FRich.CaretPos);
  // a merged run of typing does not take the format write in
  FRich.SelStart := 6;
  Chars('x');
  Sel(0, 1);
  FRich.SelAttributes.Size := 20;
  FRich.SelStart := 7;
  Chars('y');
  FRich.Undo;
  AssertEquals('the typing after it undone alone', 'abcdefx', FRich.Lines[0]);
  AssertEquals('the format still there', 40, Fmt(0).SizeHalfPt);
end;

{ R56 for format commands: a paragraph of a lazily read RTF formatted (through either façade)
  and undone is saved as the file's bytes. }
procedure TTyRichEditApiTest.TestALazyParagraphFormattedAndUndoneSavesTheFile;

  procedure Check(const AName: string; const AOrig: TBytes);
  var
    t: TTyRichText;
    p: Integer;
    ps: TTyRichPos;
    pr: TTyFontParams;
  begin
    LoadBytes(AOrig);
    t := FRich.Document.Text;
    p := 0;
    while (p < t.ParaCount - 1) and ((t.ParaLength(p) < 3) or
      (FRich.Document.CellAt(p) <> nil)) do Inc(p);
    ps := t.ParaStart(p);
    Sel(ps + 1, 2);
    FRich.SelAttributes.Style := [fsBold];
    FRich.Undo;
    AssertTrue(AName + ': SelAttributes, undone: the file', SameBytes(AOrig, SavedRtf));
    FRich.SetRangeColor(ps, 2, clRed);
    FRich.Undo;
    AssertTrue(AName + ': SetRangeColor, undone: the file', SameBytes(AOrig, SavedRtf));
    Sel(ps, 0);
    FRich.Paragraph.Alignment := paraCenter;
    FRich.Undo;
    AssertTrue(AName + ': a paragraph, undone: the file', SameBytes(AOrig, SavedRtf));
    pr := Default(TTyFontParams);
    pr.Name := 'Arial';
    pr.Size := 30;
    FRich.SetTextAttributes(0, t.Length, pr);
    FRich.Undo;
    AssertTrue(AName + ': everything, undone: the file', SameBytes(AOrig, SavedRtf));
  end;

begin
  Check('plain', PlainRtf(40));
  Check('re-zh-mixed.rtf', FixtureFile('re-zh-mixed.rtf'));
  Check('re-zh-table.rtf', FixtureFile('re-zh-table.rtf'));
end;

{ One OnChange per write, OnSelectionChange only when the selection changed; ReadOnly does not
  stop a write (R53) and the write raises nothing. }
procedure TTyRichEditApiTest.TestOneChangeAndNoSelectionChange;
begin
  SetText('abcdef'#10'gh');
  Sel(1, 3);
  ResetEvents;
  FRich.SelAttributes.Style := [fsBold];
  AssertEquals('one OnChange', 1, FChanges);
  AssertEquals('no OnSelectionChange', 0, FSelChanges);
  FRich.Paragraph.Alignment := paraCenter;
  AssertEquals('one more', 2, FChanges);
  FRich.SetRangeColor(0, 8, clRed);
  AssertEquals('RichMemo''s: one more', 3, FChanges);
  AssertEquals('still no OnSelectionChange', 0, FSelChanges);
  FRich.ReadOnly := True;
  FRich.SelAttributes.Size := 20;
  AssertEquals('ReadOnly: written', 40, Fmt(2).SizeHalfPt);
  AssertEquals('ReadOnly: one OnChange', 4, FChanges);
  FRich.SetParaAlignment(0, 0, paraRight);
  AssertTrue('ReadOnly: RichMemo''s written', PFmt(0).Align = paraRight);
  // a composition open: it goes in first, which moves the selection
  FRich.ReadOnly := False;
  FRich.SelStart := 1;
  FRich.UpdateComposition('zz');
  ResetEvents;
  FRich.Paragraph.Alignment := paraLeft;
  AssertEquals('the composition went in', 'azzbcdef', FRich.Lines[0]);
  AssertTrue('the selection moved: reported', FSelChanges >= 1);
end;

{ Requirement 6: the document that takes no edit (loading, incomplete) refuses a write - from
  code it raises ETyRichEdit with the reason; nothing changes. A pending format is no edit. }
procedure TTyRichEditApiTest.TestRefusalsOfTheDocument;
var
  raised: string;

  procedure Try_(const AWhat: string; AWay: Integer);
  begin
    raised := '';
    try
      case AWay of
        0: FRich.SelAttributes.Style := [fsBold];
        1: FRich.Paragraph.Alignment := paraCenter;
        2: FRich.SetRangeColor(0, 3, clRed);
        3: FRich.SetParaAlignment(0, 3, paraRight);
      end;
    except
      on E: ETyRichEdit do raised := E.Message;
    end;
    AssertTrue(AWhat + ': raised', raised <> '');
  end;

var
  w, depth: Integer;
begin
  FRich.Slices(2048, 2048);
  LoadBytes(PlainRtf(3000), False);
  AssertTrue('loading', FRich.Loading);
  Sel(0, 5);
  depth := FRich.Document.UndoDepth;
  for w := 0 to 3 do
  begin
    Try_(Format('loading %d', [w]), w);
    AssertEquals(Format('loading %d: why', [w]), rsRichEditRefusedLoading, raised);
  end;
  AssertEquals('nothing kept', depth, FRich.Document.UndoDepth);
  AssertFalse('nothing changed', fsBold in Fmt(1).Style);
  FRich.SelStart := 1;
  FRich.SelAttributes.Style := [fsBold];
  AssertTrue('a pending format is no edit', fsBold in FRich.SelAttributes.Style);
  FRich.CancelLoad;
  AssertTrue('incomplete', FRich.Incomplete);
  Sel(0, 5);
  for w := 0 to 3 do
  begin
    Try_(Format('incomplete %d', [w]), w);
    AssertEquals(Format('incomplete %d: why', [w]), rsRichEditRefusedIncomplete, raised);
  end;
end;

{ Requirement 6: a row that holds a nested table is passed over (the rest formatted); a range
  across cells formats every cell's text; a cut paragraph's hidden tail is formatted, and the
  selection that reaches into it stays. }
procedure TTyRichEditApiTest.TestRowsCellsAndTheHiddenTail;
var
  d: TTyRichDocument;
  k, nested, plain: Integer;
  c: TTyRichCell;
  len: TTyRichPos;
begin
  LoadBytes(FixtureFile('word-table-merged.rtf'));
  d := FRich.Document;
  FRich.SelectAll;
  FRich.SelAttributes.Color := clRed;
  nested := 0;
  plain := 0;
  for k := 0 to d.Text.ParaCount - 1 do
  begin
    if d.Text.ParaLength(k) = 0 then Continue;
    c := d.CellAt(k);
    if (c <> nil) and c.Row.HoldsNestedTable then
    begin
      Inc(nested);
      AssertTrue(Format('paragraph %d of a nested row: passed over', [k]),
        Fmt(d.Text.ParaStart(k)).Color <> clRed);
    end
    else
    begin
      Inc(plain);
      AssertEquals(Format('paragraph %d: formatted', [k]), clRed, Fmt(d.Text.ParaStart(k)).Color);
    end;
  end;
  AssertTrue('the fixture has nested rows', nested > 0);
  AssertTrue('and other text', plain > 0);
  // across cells
  LoadBytes(FixtureFile('re-zh-table.rtf'));
  d := FRich.Document;
  FRich.SelectAll;
  FRich.SelAttributes.Style := [fsBold];
  for k := 0 to d.Text.ParaCount - 1 do
    if d.Text.ParaLength(k) > 0 then
      AssertTrue(Format('cell or not, paragraph %d bold', [k]),
        fsBold in Fmt(d.Text.ParaStart(k)).Style);
  // a cut paragraph's hidden tail
  SetText(StringOfChar('a', CRichMaxParaLayoutChars + 50));
  FRich.SelectAll;
  len := FRich.SelLength;
  FRich.SelAttributes.Style := [fsItalic];
  AssertTrue('the tail formatted', fsItalic in Fmt(CRichMaxParaLayoutChars + 40).Style);
  AssertEquals('the selection kept whole', len, FRich.SelLength);
  FRich.Undo;
  AssertEquals('undone: the selection whole', len, FRich.SelLength);
end;

{ Modified through the control (R59): a write makes it True, an undo back to the saved point
  False, a redo True; a save as RTF sets the point; SaveToStream does not; OnModifiedChange at
  each turn and OnChange never for Modified alone. }
procedure TTyRichEditApiTest.TestTheSavedPointThroughTheControl;
var
  path: string;
begin
  SetText('abc');
  FRich.Modified := False;
  ResetEvents;
  Sel(0, 2);
  FRich.SelAttributes.Style := [fsBold];
  AssertTrue('a write', FRich.Modified);
  AssertEquals('turned once', 1, FModChanges);
  FRich.Undo;
  AssertFalse('undone to the saved point', FRich.Modified);
  AssertEquals('turned back', 2, FModChanges);
  FRich.Redo;
  AssertTrue('redone', FRich.Modified);
  FChanges := 0;
  FRich.Modified := False;
  AssertEquals('Modified alone raises no OnChange', 0, FChanges);
  AssertEquals('it turned', 4, FModChanges);
  FRich.Undo;
  AssertTrue('undone past the new saved point', FRich.Modified);
  FRich.Redo;
  path := TempDir + 'saved.rtf';
  FRich.Undo;
  FRich.SaveToFile(path);
  AssertFalse('saved', FRich.Modified);
  FRich.Redo;
  AssertTrue('redone past the save', FRich.Modified);
  FRich.Undo;
  AssertFalse('back to the save', FRich.Modified);
  FRich.Redo;
  SavedRtf;
  AssertTrue('a stream is no save', FRich.Modified);
  FRich.ClearUndo;
  FRich.Undo;
  AssertTrue('cleared away from it: for good', FRich.Modified);
end;

{ R66: the user's actions do nothing on a read-only (or disabled) control and raise nothing;
  CopyToClipboard and SelectAll work; the document API edits a read-only control. }
procedure TTyRichEditApiTest.TestTheUserActionsRespectReadOnly;
var
  d: TTyRichDocument;
begin
  SetText('abcdef');
  d := FRich.Document;
  Sel(0, 1);
  FRich.SelText := 'X';
  FRich.ReadOnly := True;
  FRich.ClipReset;
  FRich.ClipRtf := '';
  FRich.ClipText := 'pasted';
  FRich.ClipWrites := 0;
  Sel(1, 2);
  ResetEvents;
  FRich.CutToClipboard;
  AssertEquals('Cut: nothing', 'Xbcdef', FRich.Lines[0]);
  AssertEquals('Cut: nothing copied', 0, FRich.ClipWrites);
  FRich.PasteFromClipboard;
  AssertEquals('Paste: nothing', 'Xbcdef', FRich.Lines[0]);
  FRich.ClearSelection;
  AssertEquals('ClearSelection: nothing', 'Xbcdef', FRich.Lines[0]);
  FRich.Undo;
  AssertEquals('Undo: nothing', 'Xbcdef', FRich.Lines[0]);
  AssertEquals('Undo: the step kept', 1, d.UndoDepth);
  AssertEquals('nothing told', 0, FRich.Refused);
  AssertEquals('no OnChange', 0, FChanges);
  FRich.CopyToClipboard;
  AssertEquals('Copy works', 1, FRich.ClipWrites);
  FRich.SelectAll;
  AssertEquals('Select All works', Int64(6), FRich.SelLength);
  // the document API edits regardless
  FRich.SelStart := 0;
  FRich.SelText := 'Q';
  AssertEquals('SelText', 'QXbcdef', FRich.Lines[0]);
  FRich.Lines.Add('more');
  AssertEquals('Lines', 2, FRich.Lines.Count);
  d.Undo;
  FRich.ReadOnly := False;
  FRich.Undo;
  AssertEquals('editable: Undo', 'Xbcdef', FRich.Lines[0]);
  FRich.Redo;
  AssertEquals('editable: Redo', 'QXbcdef', FRich.Lines[0]);
  FRich.ReadOnly := True;
  FRich.Undo;
  FRich.Redo;
  AssertEquals('ReadOnly: no Redo', 'QXbcdef', FRich.Lines[0]);
  // disabled
  FRich.ReadOnly := False;
  FRich.Enabled := False;
  Sel(0, 2);
  FRich.ClearSelection;
  FRich.CutToClipboard;
  FRich.Undo;
  AssertEquals('disabled: nothing', 'QXbcdef', FRich.Lines[0]);
  FRich.Enabled := True;
end;

procedure TTyRichEditApiTest.ActWhileSaving(Sender: TObject; ADone, ATotal: Int64;
  var ACancel: Boolean);
var
  told: Integer;
begin
  Inc(FSaveCalls);
  if FSaveCalls > 1 then Exit;
  told := FRich.Refused;
  try
    case FSaveWhat of
      0: FRich.Undo;
      1: FRich.Redo;
      2: FRich.CutToClipboard;
      3: FRich.PasteFromClipboard;
      4: FRich.ClearSelection;
      5: FRich.SelAttributes.Style := [fsBold];
      6: FRich.SetRangeColor(0, 2, clRed);
      7: FRich.SelText := 'x';
    end;
  except
    on ETyRichEdit do Inc(FSaveRaised);
  end;
  FSaveTold := FRich.Refused - told;
end;

{ While the document is being saved: a user's action is told (EditRefused, the saving reason)
  and raises nothing; a write of the document API raises ETyRichEdit. Nothing changes. }
procedure TTyRichEditApiTest.TestTheTwoKindsWhileSaving;
var
  w, k: Integer;
  before: string;
  st: TMemoryStream;
  sl: TStringList;
begin
  for w := 0 to 7 do
  begin
    // long enough for the text save to report its progress
    sl := TStringList.Create;
    try
      sl.Add('abc');
      sl.Add('def');
      sl.Add('ghi');
      for k := 0 to 39999 do sl.Add('A line of text that the save writes out: ' + IntToStr(k));
      FRich.Lines := sl;
    finally
      sl.Free;
    end;
    FRich.UpdateView;
    ResetEvents;
    FRich.SelStart := 9;
    Chars('k');
    FRich.Undo;
    FRich.Redo;
    if w = 1 then FRich.Undo;
    FRich.ClipReset;
    FRich.ClipRtf := '';
    FRich.ClipText := 'p';
    Sel(0, 2);
    before := Dump(4, True);
    FSaveCalls := 0;
    FSaveRaised := 0;
    FSaveTold := 0;
    FSaveWhat := w;
    FRich.OnSaveProgress := @ActWhileSaving;
    st := TMemoryStream.Create;
    try
      FRich.SaveToStream(st, rfText);
    finally
      st.Free;
      FRich.OnSaveProgress := nil;
    end;
    AssertTrue(Format('way %d: the handler ran', [w]), FSaveCalls > 0);
    if w <= 4 then
    begin
      AssertEquals(Format('way %d (a user''s action): nothing raised', [w]), 0, FSaveRaised);
      AssertEquals(Format('way %d: told once', [w]), 1, FSaveTold);
      AssertEquals(Format('way %d: why', [w]), rsRichEditRefusedSaving, FRich.LastReason);
    end
    else
      AssertEquals(Format('way %d (the document API): raised', [w]), 1, FSaveRaised);
    AssertEquals(Format('way %d: nothing changed', [w]), before, Dump(4, True));
  end;
end;

{ ClearSelection deletes the selection (Delphi's and LCL's meaning), one step; CollapseSelection
  keeps the text. }
procedure TTyRichEditApiTest.TestClearSelectionDeletes;
var
  depth: Integer;
begin
  SetText('abcdef');
  Sel(1, 2);
  depth := FRich.Document.UndoDepth;
  FRich.ClearSelection;
  AssertEquals('deleted', 'adef', FRich.Lines[0]);
  AssertEquals('one step', depth + 1, FRich.Document.UndoDepth);
  AssertEquals('the caret at the join', Int64(1), FRich.CaretPos);
  FRich.ClearSelection;
  AssertEquals('nothing selected: nothing', 'adef', FRich.Lines[0]);
  Sel(1, 2);
  FRich.CollapseSelection;
  AssertEquals('collapsed: the text stays', 'adef', FRich.Lines[0]);
  AssertFalse('nothing selected', FRich.HasSelection);
end;

procedure TTyRichEditApiTest.RepaintCase(AScale: Integer);
var
  sl: TStringList;
  i: Integer;
  t: TTyRichText;
  what: string;
begin
  what := Format('scale %d', [AScale]);
  FreeAndNil(FRich);
  if AScale > 1 then TyForceDeviceScaleForTest(AScale, True, False)
  else TyForceDeviceScaleForTest(0, False);
  FPaintScale := AScale;
  FRich := NewProbe;
  sl := TStringList.Create;
  try
    for i := 0 to 59 do sl.Add('Line ' + IntToStr(i) + StringOfChar('x', (i * 5) mod 13));
    FRich.Lines := sl;
  finally
    sl.Free;
  end;
  FRich.UpdateView;
  t := FRich.Document.Text;
  PaintAll;
  // taller
  Sel(t.ParaStart(3), 4);
  FRich.SelAttributes.Size := 30;
  CheckSurface(what + ': a line made taller');
  // shorter again, over two paragraphs
  Sel(t.ParaStart(3), t.ParaStart(5) - t.ParaStart(3));
  FRich.SelAttributes.Size := 6;
  CheckSurface(what + ': lines made shorter');
  FRich.Paragraph.SpaceBefore := 24;
  CheckSurface(what + ': space before');
  FRich.Undo;
  CheckSurface(what + ': undone');
  // a write that changes no height
  Sel(t.ParaStart(8), 3);
  FRich.SelAttributes.Color := clRed;
  CheckSurface(what + ': a colour');
end;

{ The view after a format write that changes heights repaints what changed and moves the
  kept surface below it as an edit does (W11's routine): pixel equal to a full redraw, at
  device scale 1 and 2. }
procedure TTyRichEditApiTest.TestTheRepaintAfterAHeightChange;
begin
  RepaintCase(1);
  RepaintCase(2);
end;

{ The events' final shape: published on TTyRichEdit with the names and types the brief gives
  (OnFindProgress is 11b's), PlainText published. }
procedure TTyRichEditApiTest.TestTheEventsArePublished;

  procedure Has(const AName, AType: string);
  var
    pi: PPropInfo;
  begin
    pi := GetPropInfo(TTyRichEdit, AName);
    AssertTrue(AName + ': published', pi <> nil);
    AssertEquals(AName + ': its type', AType, pi^.PropType^.Name);
  end;

begin
  Has('OnChange', 'TNotifyEvent');
  Has('OnSelectionChange', 'TNotifyEvent');
  Has('OnModifiedChange', 'TNotifyEvent');
  Has('OnLoadProgress', 'TTyRichProgressEvent');
  Has('OnSaveProgress', 'TTyRichProgressEvent');
  Has('OnEditRefused', 'TTyRichEditRefusedEvent');
  Has('PlainText', 'Boolean');
end;

{ A write over more characters than CopyWaitChars shows the wait cursor meanwhile; a small one
  does not. }
procedure TTyRichEditApiTest.TestTheWaitCursorOverTheThreshold;
begin
  SetText('abcdefghij');
  FRich.SetCopyWait(5);
  FRich.ClipReset;
  Sel(0, 4);
  FRich.SelAttributes.Style := [fsBold];
  AssertEquals('small: no wait', 0, FRich.Waits);
  Sel(0, 8);
  FRich.SelAttributes.Style := [fsItalic];
  AssertEquals('large: the wait cursor', 1, FRich.Waits);
  AssertEquals('and its end', 1, FRich.WaitEnds);
  FRich.SetParaAlignment(0, 10, paraCenter);
  AssertEquals('RichMemo''s too', 2, FRich.Waits);
end;

initialization
  RegisterTest(TTyRichEditApiTest);

end.
