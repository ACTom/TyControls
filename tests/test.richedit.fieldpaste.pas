unit test.richedit.fieldpaste;

{ A field - a link, a table of contents, a page number - stays a field through the clipboard
  and a drag: copied and pasted into the same document, into a document with other font and
  colour tables, into a new empty one, or dropped from another control, it is a field again
  with its instruction and its content (text, formats, paragraphs), and so it reads back after a
  save. Into another document it is the model's own field, written as a group built there
  around its content.

  Headless, on the probe of test.richedit.fieldctl (the clipboard is the suite's stand-in, never
  the system's). Expected values come from the source document: the field's instruction and its
  content's characters and formats, compared field by field. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, fpcunit, testregistry, Controls, Graphics, LCLType, Forms,
  tyControls.Controller, tyControls.StrConsts,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.RtfRead, tyControls.RichEdit.RtfWrite,
  tyControls.RichEdit, test.richedit.control, test.richedit.fieldctl;

type
  TTyRichFieldPasteTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FProbes: TFPList;
    function NewProbe: TFieldProbe;
    function Loaded(const ARtf: RawByteString): TFieldProbe;
    function SaveOf(ARich: TFieldProbe): RawByteString;
    function ReadBack(const ABytes: RawByteString): TTyRichDocument;
    procedure CopyAll(ARich: TFieldProbe);
    procedure PasteAt(ARich: TFieldProbe; APos: TTyRichPos; const ARtf: RawByteString);
    procedure CheckBalanced(const AWhat: string; const ABytes: RawByteString);
    procedure CheckLikeSource(const AWhat: string; ASource, ATarget: TTyRichDocument);
    procedure CheckCase(const AWhat, ABody: RawByteString);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEachKindOfFieldPastedStaysAField;
    procedure TestWordsOwnFieldsPastedStayFields;
    procedure TestTheOutputIsBalancedAndStable;
    procedure TestADropFromAnotherControl;
    procedure TestTheTargetsFontsAndAFieldOfItsOwnBeside;
    procedure TestAContentsOfFiveThousandEntries;
    procedure TestAPastedFieldIsAFieldToTheUser;
    procedure TestAnInstructionThatIsNotTextAndTheStateWords;
    procedure TestAPartOfAFieldAndAWholeOneInsideACutOne;
    procedure TestAFieldOverParagraphsGoesIntoACellAsItsContent;
  end;

{ The fields of ADoc, each as its instruction and its content: one line a field (nested ones
  after the one around them), every character between and with its marks - a mark as O:(the
  instruction) or C, a paragraph's end as P, any other character with its font, size, colour,
  bold and underline. }
function FieldSignatures(ADoc: TTyRichDocument): string;

implementation

const
  BS = #92;

function Rtf(const S: RawByteString): RawByteString;
var
  i: Integer;
begin
  Result := S;
  UniqueString(Result);
  for i := 1 to Length(Result) do
    if Result[i] = '|' then Result[i] := BS;
  SetCodePage(Result, CP_NONE, False);
end;

function RawBytes(const S: RawByteString): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[0], Length(S));
end;

function Hex(const S: RawByteString): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do Result := Result + IntToHex(Ord(S[i]), 2);
end;

function CountOf(const ANeedle, AHay: RawByteString): Integer;
var
  p: Integer;
  h: RawByteString;
begin
  Result := 0;
  h := AHay;
  p := Pos(ANeedle, h);
  while p > 0 do
  begin
    Inc(Result);
    System.Delete(h, 1, p + Length(ANeedle) - 1);
    p := Pos(ANeedle, h);
  end;
end;

// the group of S's first field, with its braces
function FirstFieldGroup(const S: RawByteString): RawByteString;
var
  i, j, d: Integer;
begin
  Result := '';
  i := Pos('{' + BS + 'field', S);
  if i = 0 then Exit;
  d := 0;
  j := i;
  while j <= Length(S) do
  begin
    case S[j] of
      '\': Inc(j);
      '{': Inc(d);
      '}':
        begin
          Dec(d);
          if d = 0 then Exit(Copy(S, i, j - i + 1));
        end;
    end;
    Inc(j);
  end;
end;

const
  // the source's tables: Arial, SimSun, Times; red, blue
  HeadX = '{|rtf1|ansi|ansicpg936|deff0{|fonttbl{|f0|fswiss|fcharset0 Arial;}{|f1|fnil|fcharset134 SimSun;}' +
    '{|f2|froman|fcharset0 Times New Roman;}}{|colortbl;|red255|green0|blue0;|red0|green0|blue255;}' +
    '|pard|f0|fs20 ';
  // another file's: Courier New, Georgia; green
  HeadY = '{|rtf1|ansi|ansicpg1252|deff0{|fonttbl{|f0|fmodern|fcharset0 Courier New;}' +
    '{|f1|froman|fcharset0 Georgia;}}{|colortbl;|red0|green128|blue0;}|pard|f0|fs24 ';
  BodyY = 'its own text|par and a link of its own {|field{|*|fldinst HYPERLINK "http://y.test/"}' +
    '{|fldrslt {|ul|cf1 here}}} end|par}';

  Link = '{|field{|*|fldinst HYPERLINK "http://x.test/a"}{|fldrslt {|ul|cf2 a link}}}';
  ChineseLink = '{|field{|*|fldinst HYPERLINK "http://x.test/|u25991?|u26723?"}{|fldrslt ' +
    '{|f1|b|cf2 |u38142?|u25509?|u25991?}}}';
  PlaceLink = '{|field{|*|fldinst HYPERLINK ||l "mark1"}{|fldrslt {|i to the mark}}}';
  Entry = '{|field{|*|fldinst HYPERLINK ||l "_Toc1"}{|fldrslt {|f2|fs22 Chapter 1|tab ' +
    '{|field{|*|fldinst PAGEREF _Toc1 ||h}{|fldrslt 3}}}}}';

function Toc(ACount: Integer): RawByteString;
var
  i: Integer;
begin
  Result := '{|field|fldedit{|*|fldinst TOC ||o "1-3" ||h}{|fldrslt ';
  for i := 1 to ACount do
  begin
    Result := Result + '{|field{|*|fldinst HYPERLINK ||l "_Toc' + IntToStr(i) + '"}{|fldrslt ' +
      '{|cf2 Entry ' + IntToStr(i) + '|tab {|field{|*|fldinst PAGEREF _Toc' + IntToStr(i) +
      ' ||h}{|fldrslt ' + IntToStr(i + 2) + '}}}}}';
    if i < ACount then Result := Result + '|par ';
  end;
  Result := Result + '}}';
end;

function FieldSignatures(ADoc: TTyRichDocument): string;
var
  t: TTyRichText;
  k, i, j: Integer;
  runs: TTyRunArray;
  o, c, q, ps: TTyRichPos;
  m: TTyRichObject;
  cf: TTyCharFormat;
  ch: RawByteString;
  line: string;
begin
  Result := '';
  t := ADoc.Text;
  for k := 0 to t.ParaCount - 1 do
  begin
    runs := ADoc.RunsOf(k);
    ps := t.ParaStart(k);
    for i := 0 to High(runs) do
    begin
      if not ((runs[i].Obj is TTyRichFieldMark) and
        (TTyRichFieldMark(runs[i].Obj).Kind = rfmOpen)) then
        Continue;
      o := ps + runs[i].Start;
      c := ADoc.FieldPartner(o);
      line := '';
      q := o;
      while (q <= c) and (q < t.Length) do
      begin
        m := ADoc.ObjectAt(q);
        if m is TTyRichFieldMark then
        begin
          if TTyRichFieldMark(m).Kind = rfmOpen then
            line := line + 'O:(' + TyRichFieldInstruction(ADoc, TTyRichFieldMark(m)) + ')'
          else
            line := line + 'C';
        end
        else if t.ParaStart(t.ParaOfPos(q)) + t.ParaLength(t.ParaOfPos(q)) = q then
          line := line + 'P'
        else
        begin
          ch := t.GetText(q, 1);
          cf := ADoc.Formats.CharFormat(ADoc.TypingFormatAt(q + 1));
          line := line + '[' + Hex(ch) + ' ' + cf.FontName + ' ' + IntToStr(cf.SizeHalfPt) + ' ' +
            IntToHex(cf.Color, 6) + ' ' + BoolToStr(fsBold in cf.Style, 'b', '-') +
            BoolToStr(fsUnderline in cf.Style, 'u', '-') + BoolToStr(fsItalic in cf.Style, 'i', '-') + ']';
        end;
        Inc(q);
      end;
      j := 0;
      Result := Result + line + LineEnding;
      if j < 0 then Break;
    end;
  end;
end;

{ ---- the suite ---- }

procedure TTyRichFieldPasteTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FProbes := TFPList.Create;
end;

procedure TTyRichFieldPasteTest.TearDown;
var
  i: Integer;
begin
  for i := 0 to FProbes.Count - 1 do TObject(FProbes[i]).Free;
  FreeAndNil(FProbes);
  FreeAndNil(FCtl);
end;

function TTyRichFieldPasteTest.NewProbe: TFieldProbe;
begin
  Result := TFieldProbe.Create(nil);
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 600, 400);
  Result.ResetCounts;
  FProbes.Add(Result);
end;

function TTyRichFieldPasteTest.Loaded(const ARtf: RawByteString): TFieldProbe;
var
  st: TBytesStream;
begin
  Result := NewProbe;
  st := TBytesStream.Create(RawBytes(ARtf));
  try
    Result.LoadFromStream(st);
  finally
    st.Free;
  end;
  Result.FinishLoading;
  Result.UpdateView;
end;

function TTyRichFieldPasteTest.SaveOf(ARich: TFieldProbe): RawByteString;
var
  st: TBytesStream;
begin
  st := TBytesStream.Create;
  try
    ARich.SaveToStream(st, rfRtf);
    Result := '';
    SetLength(Result, st.Size);
    if st.Size > 0 then Move(st.Bytes[0], Result[1], st.Size);
    SetCodePage(Result, CP_NONE, False);
  finally
    st.Free;
  end;
end;

function TTyRichFieldPasteTest.ReadBack(const ABytes: RawByteString): TTyRichDocument;
var
  st: TBytesStream;
begin
  Result := TTyRichDocument.Create;
  st := TBytesStream.Create(RawBytes(ABytes));
  try
    TyRichLoadRtfFull(Result, st);
  finally
    st.Free;
  end;
end;

procedure TTyRichFieldPasteTest.CopyAll(ARich: TFieldProbe);
begin
  ARich.SelStart := 0;
  ARich.SelLength := ARich.Document.Text.Length;
  ARich.ClipRtf := '';
  ARich.CopyToClipboard;
  AssertTrue('copied', ARich.ClipRtf <> '');
end;

procedure TTyRichFieldPasteTest.PasteAt(ARich: TFieldProbe; APos: TTyRichPos;
  const ARtf: RawByteString);
begin
  ARich.ClipRtf := ARtf;
  ARich.ClipText := '';
  ARich.SelStart := APos;
  ARich.Refused := 0;
  ARich.PasteFromClipboard;
  AssertEquals('the paste not refused', 0, ARich.Refused);
end;

// the groups of ABytes balance: never below zero, zero at the end
procedure TTyRichFieldPasteTest.CheckBalanced(const AWhat: string; const ABytes: RawByteString);
var
  i, d: Integer;
begin
  d := 0;
  i := 1;
  while i <= Length(ABytes) do
  begin
    case ABytes[i] of
      '\': Inc(i);
      '{': Inc(d);
      '}':
        begin
          Dec(d);
          AssertTrue(AWhat + ': no group closed that was not open', d >= 0);
        end;
    end;
    Inc(i);
  end;
  AssertEquals(AWhat + ': every group closed', 0, d);
end;

// ATarget holds ASource's fields, each with its instruction and its content
procedure TTyRichFieldPasteTest.CheckLikeSource(const AWhat: string; ASource,
  ATarget: TTyRichDocument);
var
  want, got: string;
begin
  want := FieldSignatures(ASource);
  got := FieldSignatures(ATarget);
  AssertTrue(AWhat + ': the source has fields', want <> '');
  AssertEquals(AWhat + ': the fields, their instructions and their content', want, got);
end;

{ ABody copied whole from a document of its own and pasted (1) into that same document, (2)
  into another file whose tables are others, (3) into a new empty document; each saved and
  read back. }
procedure TTyRichFieldPasteTest.CheckCase(const AWhat, ABody: RawByteString);
var
  x, y, n: TFieldProbe;
  clip, saved: RawByteString;
  back, src: TTyRichDocument;
  nx: Integer;
begin
  x := Loaded(Rtf(HeadX + ABody + '|par}'));
  nx := Length(FieldSignatures(x.Document));
  CopyAll(x);
  clip := x.ClipRtf;
  // (1) into the same document: the fields keep their file's bytes, both copies saved as them
  PasteAt(x, x.Document.Text.Length, clip);
  saved := SaveOf(x);
  CheckBalanced(AWhat + ', the same document', saved);
  AssertTrue(AWhat + ', the same document: the field''s bytes twice',
    CountOf(FirstFieldGroup(Rtf(ABody)), saved) >= 2);
  back := ReadBack(saved);
  try
    AssertEquals(AWhat + ', the same document: every field twice', 2 * nx,
      Length(FieldSignatures(back)));
  finally
    back.Free;
  end;
  // (2) into another file
  y := Loaded(Rtf(HeadY + BodyY));
  PasteAt(y, 0, clip);
  saved := SaveOf(y);
  CheckBalanced(AWhat + ', another file', saved);
  AssertTrue(AWhat + ', another file: its own field as its bytes',
    Pos(Rtf('{|field{|*|fldinst HYPERLINK "http://y.test/"}{|fldrslt {|ul|cf1 here}}}'), saved) > 0);
  back := ReadBack(saved);
  src := ReadBack(Rtf(HeadX + ABody + '|par}'));
  try
    // (the file's own link after them)
    AssertTrue(AWhat + ', another file: the fields, their instructions and their content',
      Pos(FieldSignatures(src), FieldSignatures(back)) = 1);
  finally
    back.Free;
    src.Free;
  end;
  // (3) into a new empty document
  n := NewProbe;
  PasteAt(n, 0, clip);
  saved := SaveOf(n);
  CheckBalanced(AWhat + ', a new document', saved);
  back := ReadBack(saved);
  src := ReadBack(Rtf(HeadX + ABody + '|par}'));
  try
    CheckLikeSource(AWhat + ', a new document', src, back);
  finally
    back.Free;
    src.Free;
  end;
  // saved again: the same bytes; read and saved: the same bytes
  AssertTrue(AWhat + ', a new document: saved twice alike', SaveOf(n) = saved);
end;

procedure TTyRichFieldPasteTest.TestEachKindOfFieldPastedStaysAField;
begin
  CheckCase('a link', 'see ' + Link + ' here');
  CheckCase('a link in Chinese', 'see ' + ChineseLink + ' here');
  CheckCase('a link to a place', 'go ' + PlaceLink + ' now');
  CheckCase('an entry of a contents', Entry);
  CheckCase('a contents', 'Contents: ' + Toc(4) + ' after');
  CheckCase('a field in a cell', '|trowd|cellx2000|cellx4000|pard|intbl ' + Link + '|cell |pard|intbl two|cell |row |pard after');
  CheckCase('two fields touching', Link + PlaceLink);
end;

{ RTF as Word writes it - its own table of contents, its links (one with Chinese in its
  target), a REF, the fields in a table - pasted into a new document and into another file,
  saved and read back: the same fields. }
procedure TTyRichFieldPasteTest.TestWordsOwnFieldsPastedStayFields;
const
  Files: array[0..2] of string = ('word-toc.rtf', 'hand-word-unknown.rtf', 'word-unknown.rtf');
var
  f: Integer;
  bytes: TBytes;
  raw, saved: RawByteString;
  src, back: TTyRichDocument;
  n, y: TFieldProbe;
  fs: TFileStream;
  st: TBytesStream;
begin
  for f := 0 to High(Files) do
  begin
    fs := TFileStream.Create(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim +
      'fixtures' + PathDelim + 'rtf' + PathDelim + Files[f], fmOpenRead or fmShareDenyWrite);
    try
      bytes := nil;
      SetLength(bytes, fs.Size);
      fs.ReadBuffer(bytes[0], fs.Size);
    finally
      fs.Free;
    end;
    raw := '';
    SetLength(raw, Length(bytes));
    Move(bytes[0], raw[1], Length(bytes));
    SetCodePage(raw, CP_NONE, False);
    src := TTyRichDocument.Create;
    st := TBytesStream.Create(bytes);
    try
      TyRichLoadRtfFull(src, st);
    finally
      st.Free;
    end;
    try
      n := NewProbe;
      PasteAt(n, 0, raw);
      saved := SaveOf(n);
      CheckBalanced(Files[f] + ', a new document', saved);
      back := ReadBack(saved);
      try
        CheckLikeSource(Files[f] + ', a new document', src, back);
      finally
        back.Free;
      end;
      y := Loaded(Rtf(HeadY + BodyY));
      PasteAt(y, 0, raw);
      saved := SaveOf(y);
      CheckBalanced(Files[f] + ', another file', saved);
      back := ReadBack(saved);
      try
        // (another file's own link comes after them)
        AssertTrue(Files[f] + ', another file: the fields', Pos(FieldSignatures(src),
          FieldSignatures(back)) = 1);
      finally
        back.Free;
      end;
    finally
      src.Free;
    end;
  end;
end;

{ A document holding fields the model owns: saved twice, the same bytes; read back and saved,
  the same bytes; an edit away from them changes nothing of their output. }
procedure TTyRichFieldPasteTest.TestTheOutputIsBalancedAndStable;
var
  x, n: TFieldProbe;
  s1, s2, s3, shell: RawByteString;
  back: TTyRichDocument;
  st: TBytesStream;
  i, j: Integer;
begin
  x := Loaded(Rtf(HeadX + 'a ' + Link + ' and ' + Toc(3) + ' b|par}'));
  CopyAll(x);
  n := NewProbe;
  PasteAt(n, 0, x.ClipRtf);
  s1 := SaveOf(n);
  s2 := SaveOf(n);
  AssertTrue('saved twice: the same bytes', s1 = s2);
  back := ReadBack(s1);
  try
    st := TBytesStream.Create;
    try
      TyRichSaveRtf(back, st);
      s3 := '';
      SetLength(s3, st.Size);
      Move(st.Bytes[0], s3[1], st.Size);
      SetCodePage(s3, CP_NONE, False);
    finally
      st.Free;
    end;
  finally
    back.Free;
  end;
  AssertTrue('read back and saved: the same bytes', s3 = s1);
  // the link's group as written
  i := Pos(Rtf('{|field{|*|fldinst HYPERLINK "http://x.test/a"}'), s1);
  AssertTrue('the link written as a field', i > 0);
  j := i;
  while (j < Length(s1)) and (Copy(s1, j, 2) <> '}}') do Inc(j);
  shell := Copy(s1, i, j - i + 2);
  n.SelStart := n.Document.Text.Length;
  n.Key8('z');
  s2 := SaveOf(n);
  AssertTrue('an edit after it: the link''s group as it was', Pos(shell, s2) > 0);
  CheckBalanced('after the edit', s2);
end;

{ Dropped from another control (its selection offered), as a copy and as a move: a field. }
procedure TTyRichFieldPasteTest.TestADropFromAnotherControl;
var
  x, y: TFieldProbe;
  offer: TTyRichSelectionOffer;
  r: TRect;
  e: TTyRichDropEffect;
  k: Integer;
  back, src: TTyRichDocument;
begin
  for k := 0 to 1 do
  begin
    x := Loaded(Rtf(HeadX + 'a ' + Link + ' b|par}'));
    y := Loaded(Rtf(HeadY + BodyY));
    offer := TTyRichSelectionOffer.Create(x, 0, x.Document.Text.Length);
    try
      r := y.PositionRect(0);
      if k = 0 then
      begin
        y.DropEnter(offer, r.Left + 1, (r.Top + r.Bottom) div 2, [ssCtrl]);
        e := y.DropOn(r.Left + 1, (r.Top + r.Bottom) div 2, [ssCtrl]);
      end
      else
      begin
        y.DropEnter(offer, r.Left + 1, (r.Top + r.Bottom) div 2, []);
        e := y.DropOn(r.Left + 1, (r.Top + r.Bottom) div 2, []);
      end;
      AssertTrue(Format('drop %d: it went in', [k]), e <> rdeNone);
    finally
      offer.Free;
    end;
    back := ReadBack(SaveOf(y));
    src := ReadBack(Rtf(HeadX + 'a ' + Link + ' b|par}'));
    try
      AssertTrue(Format('drop %d: the link a field', [k]),
        Pos(FieldSignatures(src), FieldSignatures(back)) = 1);
    finally
      back.Free;
      src.Free;
    end;
  end;
end;

{ A field of several paragraphs in a font the target lacks, pasted beside a field of the
  target's own copied inside it: saved and read back, the fonts, the charsets and the target's
  field as its bytes. }
procedure TTyRichFieldPasteTest.TestTheTargetsFontsAndAFieldOfItsOwnBeside;
var
  x, y: TFieldProbe;
  saved: RawByteString;
  back: TTyRichDocument;
  k: Integer;
  found: Boolean;
  cf: TTyCharFormat;
begin
  // (its middle paragraph, wholly inside it, in a font that names no charset: the save settles
  // it from the text)
  x := Loaded(Rtf(StringReplace(HeadX, 'Times New Roman;}}', 'Times New Roman;}{|f3|fnil KaiTi;}}', []) +
    '{|field{|*|fldinst HYPERLINK "http://x.test/m"}{|fldrslt {|f1 ' +
    '|u20013?|u25991?|par {|f3 |u23383?|u31526?}|par |u26411?}}} tail|par}'));
  CopyAll(x);
  y := Loaded(Rtf(HeadY + BodyY));
  // the target's own field copied inside it, at its start
  y.SelStart := 0;
  y.SelLength := y.Document.Text.Length;
  y.CopyToClipboard;
  PasteAt(y, 0, y.ClipRtf);
  PasteAt(y, 0, x.ClipRtf);
  saved := SaveOf(y);
  CheckBalanced('the fonts', saved);
  AssertEquals('the target''s field twice as its bytes', 2,
    CountOf(Rtf('{|field{|*|fldinst HYPERLINK "http://y.test/"}{|fldrslt {|ul|cf1 here}}}'), saved));
  back := ReadBack(saved);
  try
    found := False;
    for k := 0 to back.Text.Length - 1 do
      if Hex(back.Text.GetText(k, 1)) = 'E5AD97' then
      begin
        cf := back.Formats.CharFormat(back.TypingFormatAt(k + 1));
        AssertEquals('the pasted field''s font', 'KaiTi', cf.FontName);
        AssertEquals('... its charset, settled from its text', 134, cf.Charset);
        found := True;
      end;
    AssertTrue('the text of its second paragraph read back', found);
    AssertTrue('the pasted field first, its content alike',
      Pos(FieldSignatures(x.Document), FieldSignatures(back)) = 1);
  finally
    back.Free;
  end;
end;

{ A contents of 5,000 entries pasted into a new document: a key beside it, the save writes it
  whole and right. }
procedure TTyRichFieldPasteTest.TestAContentsOfFiveThousandEntries;
var
  x, n: TFieldProbe;
  saved: RawByteString;
  back: TTyRichDocument;
  want, got: string;
begin
  x := Loaded(Rtf(HeadX + 'Contents: ' + Toc(5000) + ' after|par}'));
  CopyAll(x);
  n := NewProbe;
  PasteAt(n, 0, x.ClipRtf);
  n.SelStart := n.Document.Text.Length;
  n.Key8('k');
  saved := SaveOf(n);
  CheckBalanced('five thousand', saved);
  back := ReadBack(saved);
  try
    want := FieldSignatures(x.Document);
    got := FieldSignatures(back);
    AssertEquals('every field and its content', Length(want), Length(got));
    AssertTrue('alike', want = got);
    // (a copy of all ends with a paragraph's end: the new document's own paragraph after it)
    AssertEquals('the paragraphs', x.Document.Text.ParaCount + 1, back.Text.ParaCount);
  finally
    back.Free;
  end;
end;

{ To the user a pasted field is a field as one read from the file: the paste one step, undone
  and redone; its link's click; a key inside its result refused with the field's reason; the
  whole field deleted, and back with the undo. }
procedure TTyRichFieldPasteTest.TestAPastedFieldIsAFieldToTheUser;
var
  x, n: TFieldProbe;
  sig, url: string;
  depth: Integer;
  o: TTyRichPos;
  r1, r2: TRect;
begin
  x := Loaded(Rtf(HeadX + 'a ' + Link + ' b|par}'));
  CopyAll(x);
  n := Loaded(Rtf(HeadY + BodyY));
  depth := n.Document.UndoDepth;
  sig := FieldSignatures(n.Document);
  PasteAt(n, 0, x.ClipRtf);
  AssertEquals('one step', depth + 1, n.Document.UndoDepth);
  n.Undo;
  AssertEquals('undone', sig, FieldSignatures(n.Document));
  n.Redo;
  AssertTrue('redone: the link a field', Pos('O:(HYPERLINK "http://x.test/a")', FieldSignatures(n.Document)) = 1);
  // its click: the link under the pointer
  o := 2;
  while not (n.Document.ObjectAt(o) is TTyRichFieldMark) do Inc(o);
  r1 := n.PositionRect(o + 2);
  AssertTrue('a link under the pointer', n.LinkAtPoint(r1.Left + 1, (r1.Top + r1.Bottom) div 2, url));
  AssertEquals('its target', 'http://x.test/a', url);
  // a key inside its result
  n.SelStart := o + 2;
  n.Refused := 0;
  n.Key8('q');
  AssertEquals('a key inside: refused', 1, n.Refused);
  AssertEquals('... the field''s reason', rsRichEditRefusedField, n.LastReason);
  // the whole field deleted, and back
  r2 := n.PositionRect(o);
  n.SelStart := o;
  n.SelLength := n.Document.FieldPartner(o) + 1 - o;
  depth := n.Document.UndoDepth;
  n.Press(VK_DELETE, []);
  AssertEquals('deleted: one step', depth + 1, n.Document.UndoDepth);
  AssertFalse('no field there', n.Document.ObjectAt(o) is TTyRichFieldMark);
  n.Undo;
  AssertTrue('back', n.Document.ObjectAt(o) is TTyRichFieldMark);
  AssertTrue('a field again', n.LinkAtPoint(r1.Left + 1, (r1.Top + r1.Bottom) div 2, url));
  AssertTrue('(the caret there)', r2.Bottom >= r2.Top);
end;

{ A field whose instruction holds another field goes as its content with no marks - a field in
  its result is still one; a field's own state words go along, its instruction's data does not. }
procedure TTyRichFieldPasteTest.TestAnInstructionThatIsNotTextAndTheStateWords;
var
  x, n: TFieldProbe;
  saved, sig: RawByteString;
  back: TTyRichDocument;
begin
  x := Loaded(Rtf(HeadX + 'a {|field{|*|fldinst IF {|field{|*|fldinst PAGE}{|fldrslt 1}} = 1 ' +
    '"yes" "no"}{|fldrslt {|field{|*|fldinst HYPERLINK "http://in.test/"}{|fldrslt yes}}}} b|par}'));
  CopyAll(x);
  n := NewProbe;
  PasteAt(n, 0, x.ClipRtf);
  sig := FieldSignatures(n.Document);
  AssertEquals('only the link in its result is a field',
    'O:(HYPERLINK "http://in.test/")', Copy(sig, 1, Length('O:(HYPERLINK "http://in.test/")')));
  AssertEquals('one field', 1, CountOf('O:(', sig));
  AssertEquals('its text', 'a yes b', StringReplace(n.Lines[0], #$EF#$BF#$BC, '', [rfReplaceAll]));
  // the state words; the data
  x := Loaded(Rtf(HeadX + 'a {|field|fldlock|flddirty{|*|fldinst {HYPERLINK "http://s.test/"}' +
    '{|*|datafield 00ff00ff}}{|fldrslt kept}} b|par}'));
  CopyAll(x);
  n := NewProbe;
  PasteAt(n, 0, x.ClipRtf);
  saved := SaveOf(n);
  AssertTrue('its state words: ' + saved, Pos(Rtf('{|field|flddirty|fldlock{|*|fldinst HYPERLINK "http://s.test/"}'),
    saved) > 0);
  AssertEquals('not its data', 0, Pos('datafield', saved));
  back := ReadBack(saved);
  try
    AssertTrue('read back a field', Pos('O:(HYPERLINK "http://s.test/")', FieldSignatures(back)) = 1);
  finally
    back.Free;
  end;
end;

{ A part of a field copied goes as formatted text with no field; a field wholly inside a copied
  range that cuts a field around it is a whole field and stays one. }
procedure TTyRichFieldPasteTest.TestAPartOfAFieldAndAWholeOneInsideACutOne;
var
  x, n: TFieldProbe;
  sig: string;
begin
  x := Loaded(Rtf(HeadX + 'a ' + Link + ' b|par}'));
  // 'a li': into the link and out of it
  x.SelStart := 0;
  x.SelLength := 6;
  x.CopyToClipboard;
  n := NewProbe;
  PasteAt(n, 0, x.ClipRtf);
  AssertEquals('a part: no field', '', FieldSignatures(n.Document));
  AssertEquals('a part: its text', 'a a l', n.Lines[0]);
  // the same of a field the model owns (one pasted from elsewhere)
  x.SelStart := 0;
  x.SelLength := x.Document.Text.Length;
  x.CopyToClipboard;
  n := NewProbe;
  PasteAt(n, 0, x.ClipRtf);
  AssertTrue('pasted: a field', FieldSignatures(n.Document) <> '');
  n.SelStart := 0;
  n.SelLength := 6;
  n.ClipRtf := '';
  n.CopyToClipboard;
  CheckBalanced('a part of a field the model owns', n.ClipRtf);
  x := NewProbe;
  PasteAt(x, 0, n.ClipRtf);
  AssertEquals('a part of a field the model owns: no field', '', FieldSignatures(x.Document));
  AssertEquals('... its text', 'a a l', x.Lines[0]);
  // the page number field whole, its entry's link cut
  x := Loaded(Rtf(HeadX + Entry + '|par}'));
  // from inside the entry's text to the end
  x.SelStart := 4;
  x.SelLength := x.Document.Text.Length - 4;
  x.CopyToClipboard;
  n := NewProbe;
  PasteAt(n, 0, x.ClipRtf);
  sig := FieldSignatures(n.Document);
  AssertEquals('the page number a field', 1, CountOf('O:(', sig));
  AssertEquals('... its instruction', 1, CountOf('O:(PAGEREF _Toc1 ' + BS + 'h)', sig));
end;

const
  // a table whose first cell holds "a"
  TableDoc = '{|rtf1|ansi|deff0{|fonttbl{|f0 Times New Roman;}{|f1 Courier New;}}|pard|f1 target text|par' +
    '|trowd|cellx2000|cellx4000|pard|intbl a|cell b|cell|row|pard tail|par}';
  // a contents of two paragraphs before a table of the same document
  TwoParaDoc = '{|rtf1|ansi|deff0{|fonttbl{|f0 Arial;}}|pard|f0 x {|field{|*|fldinst TOC ||o "1-3" ||h}' +
    '{|fldrslt one|par two}} y|par|trowd|cellx2000|cellx4000|pard|intbl a|cell b|cell|row|pard tail|par}';

// the place after "a" in the cell that holds it
function AfterCellA(ADoc: TTyRichDocument): TTyRichPos;
var
  k: Integer;
  t: TTyRichText;
begin
  t := ADoc.Text;
  for k := 0 to t.ParaCount - 1 do
    if (ADoc.CellAt(k) <> nil) and (t.GetText(t.ParaStart(k), t.ParaLength(k)) = 'a') then
      Exit(t.ParaStart(k) + 1);
  raise Exception.Create('no cell "a"');
end;

{ The document as shown: each paragraph (in a cell or not), each character with its format, a
  field's mark as O:(its instruction) or C. }
function ShownOf(ADoc: TTyRichDocument): string;
var
  t: TTyRichText;
  k: Integer;
  q, e: TTyRichPos;
  m: TTyRichObject;
  cf: TTyCharFormat;
begin
  Result := '';
  t := ADoc.Text;
  for k := 0 to t.ParaCount - 1 do
  begin
    if ADoc.CellAt(k) <> nil then Result := Result + LineEnding + 'cell: '
    else Result := Result + LineEnding + 'para: ';
    q := t.ParaStart(k);
    e := q + t.ParaLength(k);
    while q < e do
    begin
      m := ADoc.ObjectAt(q);
      if m is TTyRichFieldMark then
      begin
        if TTyRichFieldMark(m).Kind = rfmOpen then
          Result := Result + 'O:(' + TyRichFieldInstruction(ADoc, TTyRichFieldMark(m)) + ')'
        else
          Result := Result + 'C';
      end
      else
      begin
        cf := ADoc.Formats.CharFormat(ADoc.TypingFormatAt(q + 1));
        Result := Result + '[' + Hex(t.GetText(q, 1)) + ' ' + cf.FontName + ' ' +
          IntToStr(cf.SizeHalfPt) + ' ' + IntToHex(cf.Color, 6) + ' ' +
          BoolToStr(fsBold in cf.Style, 'b', '-') + BoolToStr(fsUnderline in cf.Style, 'u', '-') + ']';
      end;
      Inc(q);
    end;
  end;
end;

// no field in a cell holds a paragraph's end: every cell paragraph's marks pair inside it
function FieldsWholeInCells(ADoc: TTyRichDocument): Boolean;
var
  k, i, d: Integer;
  runs: TTyRunArray;
begin
  for k := 0 to ADoc.Text.ParaCount - 1 do
  begin
    if ADoc.CellAt(k) = nil then Continue;
    runs := ADoc.RunsOf(k);
    d := 0;
    for i := 0 to High(runs) do
      if runs[i].Obj is TTyRichFieldMark then
      begin
        if TTyRichFieldMark(runs[i].Obj).Kind = rfmOpen then Inc(d) else Dec(d);
        if d < 0 then Exit(False);
      end;
    if d <> 0 then Exit(False);
  end;
  Result := True;
end;

// the fields opened in [AFrom, ATo) whose instruction starts with APrefix
function OpensIn(ADoc: TTyRichDocument; AFrom, ATo: TTyRichPos; const APrefix: string): Integer;
var
  q: TTyRichPos;
  m: TTyRichObject;
begin
  Result := 0;
  for q := AFrom to ATo - 1 do
  begin
    m := ADoc.ObjectAt(q);
    if (m is TTyRichFieldMark) and (TTyRichFieldMark(m).Kind = rfmOpen) and
      (Copy(TyRichFieldInstruction(ADoc, TTyRichFieldMark(m)), 1, Length(APrefix)) = APrefix) then
      Inc(Result);
  end;
end;

// the text of [AFrom, ATo) without the marks' characters
function BareText(ADoc: TTyRichDocument; AFrom, ATo: TTyRichPos): string;
begin
  Result := StringReplace(ADoc.Text.GetText(AFrom, ATo - AFrom), #$EF#$BF#$BC, '', [rfReplaceAll]);
end;

{ A field whose result holds a paragraph's end never stands in a table cell (the reader would
  not show it there: it keeps such a field in a cell as one object). Pasted, copied or moved
  into a cell, it goes in as its content without its own marks; the fields inside it that fit
  in a cell (a contents' entries, each a link with its page number) stay fields. Shown so,
  saved and read back the same; undone exactly, redone the same. }
procedure TTyRichFieldPasteTest.TestAFieldOverParagraphsGoesIntoACellAsItsContent;
var
  x, y: TFieldProbe;
  o, cl, at: TTyRichPos;
  links: Integer;
  src: string;
  bytes: TBytes;
  raw: RawByteString;
  fs: TFileStream;
  cmd: TTyRichRangeTransfer;
  k: Integer;
  before: string;
  back: TTyRichDocument;

  function TocOpen(ADoc: TTyRichDocument): TTyRichPos;
  begin
    Result := 0;
    while not ((ADoc.ObjectAt(Result) is TTyRichFieldMark) and
      (TTyRichFieldMark(ADoc.ObjectAt(Result)).Kind = rfmOpen) and
      (Copy(TyRichFieldInstruction(ADoc, TTyRichFieldMark(ADoc.ObjectAt(Result))), 1, 3) = 'TOC')) do
      Inc(Result);
  end;

  // the entries' links of the field at AOpen: those opened and closed in one paragraph
  function LinksInside(ADoc: TTyRichDocument; AOpen, AClose: TTyRichPos): Integer;
  var
    q: TTyRichPos;
    m: TTyRichObject;
  begin
    Result := 0;
    for q := AOpen + 1 to AClose - 1 do
    begin
      m := ADoc.ObjectAt(q);
      if (m is TTyRichFieldMark) and (TTyRichFieldMark(m).Kind = rfmOpen) and
        (ADoc.Text.ParaOfPos(q) = ADoc.Text.ParaOfPos(ADoc.FieldPartner(q))) then
        Inc(Result);
    end;
  end;

  { What went in at [AFrom, ATo) of ARich: the content, no mark of the field itself, its
    entries' links; the document read back from its save as shown; undone to ABefore, redone
    to what it was. }
  procedure CheckIn(const AWhat: string; ARich: TFieldProbe; AFrom, ATo: TTyRichPos;
    const ABefore, AText: string; ALinks: Integer);
  var
    after: string;
    back: TTyRichDocument;
  begin
    AssertTrue(AWhat + ': no field over a paragraph''s end in a cell', FieldsWholeInCells(ARich.Document));
    AssertEquals(AWhat + ': the field itself is gone', 0, OpensIn(ARich.Document, AFrom, ATo, 'TOC'));
    AssertEquals(AWhat + ': its content', AText, BareText(ARich.Document, AFrom, ATo));
    AssertEquals(AWhat + ': the fields inside it that fit in a cell', ALinks,
      OpensIn(ARich.Document, AFrom, ATo, ''));
    after := ShownOf(ARich.Document);
    back := ReadBack(SaveOf(ARich));
    try
      AssertEquals(AWhat + ': read back as shown', after, ShownOf(back));
    finally
      back.Free;
    end;
    ARich.Undo;
    AssertEquals(AWhat + ': undone', ABefore, ShownOf(ARich.Document));
    ARich.Redo;
    AssertEquals(AWhat + ': redone', after, ShownOf(ARich.Document));
    back := ReadBack(SaveOf(ARich));
    try
      AssertEquals(AWhat + ': redone, read back as shown', after, ShownOf(back));
    finally
      back.Free;
    end;
  end;

  procedure PasteInCell(const AWhat: string; ASrc: TFieldProbe; ATarget: TFieldProbe);
  var
    before: string;
    n0: TTyRichPos;
  begin
    o := TocOpen(ASrc.Document);
    cl := ASrc.Document.FieldPartner(o);
    links := LinksInside(ASrc.Document, o, cl);
    AssertTrue(AWhat + ': the source''s entries are links', links > 0);
    src := BareText(ASrc.Document, o, cl + 1);
    ASrc.SelStart := o;
    ASrc.SelLength := cl + 1 - o;
    ASrc.ClipRtf := '';
    ASrc.CopyToClipboard;
    at := AfterCellA(ATarget.Document);
    before := ShownOf(ATarget.Document);
    n0 := ATarget.Document.Text.Length;
    PasteAt(ATarget, at, ASrc.ClipRtf);
    CheckIn(AWhat, ATarget, at, at + ATarget.Document.Text.Length - n0, before, src, links);
  end;

begin
  // Word's contents pasted into another document's cell
  fs := TFileStream.Create(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim +
    'fixtures' + PathDelim + 'rtf' + PathDelim + 'word-toc.rtf', fmOpenRead or fmShareDenyWrite);
  try
    bytes := nil;
    SetLength(bytes, fs.Size);
    fs.ReadBuffer(bytes[0], fs.Size);
  finally
    fs.Free;
  end;
  raw := '';
  SetLength(raw, Length(bytes));
  Move(bytes[0], raw[1], Length(bytes));
  SetCodePage(raw, CP_NONE, False);
  x := Loaded(raw);
  PasteInCell('Word''s contents into another document''s cell', x, Loaded(Rtf(TableDoc)));
  // a field of two paragraphs (no link inside: its content only), inside its own document,
  // where it keeps its file's bytes: pasted
  y := Loaded(Rtf(TwoParaDoc));
  o := TocOpen(y.Document);
  cl := y.Document.FieldPartner(o);
  AssertTrue('(its two paragraphs)', y.Document.Text.ParaOfPos(o) <> y.Document.Text.ParaOfPos(cl));
  src := BareText(y.Document, o, cl + 1);
  y.SelStart := o;
  y.SelLength := cl + 1 - o;
  y.ClipRtf := '';
  y.CopyToClipboard;
  at := AfterCellA(y.Document);
  raw := y.ClipRtf;
  k := y.Document.Text.Length;
  before := ShownOf(y.Document);
  PasteAt(y, at, raw);
  CheckIn('two paragraphs pasted into a cell of the same document', y, at,
    at + y.Document.Text.Length - k, before, src, 0);
  // copied and moved there as a drag does (one command each)
  for k := 0 to 1 do
  begin
    y := Loaded(Rtf(TwoParaDoc));
    o := TocOpen(y.Document);
    cl := y.Document.FieldPartner(o);
    at := AfterCellA(y.Document);
    before := ShownOf(y.Document);
    src := BareText(y.Document, o, cl + 1);
    if k = 0 then cmd := TTyRichCopy.Create(o, cl + 1 - o, at)
    else cmd := TTyRichMove.Create(o, cl + 1 - o, at);
    AssertTrue(Format('drag %d: done', [k]), y.Document.Execute(cmd));
    CheckIn(Format('two paragraphs dragged into a cell (%d)', [k]), y, cmd.Placed.Pos,
      cmd.Placed.Pos + cmd.Placed.Len, before, src, 0);
  end;
  // pasted over a selection of both cells
  y := Loaded(Rtf(TwoParaDoc));
  o := TocOpen(y.Document);
  cl := y.Document.FieldPartner(o);
  y.SelStart := o;
  y.SelLength := cl + 1 - o;
  y.ClipRtf := '';
  y.CopyToClipboard;
  raw := y.ClipRtf;
  at := AfterCellA(y.Document) - 1;
  y.SelStart := at;
  y.SelLength := 3;
  y.ClipText := '';
  y.ClipRtf := raw;
  y.PasteFromClipboard;
  AssertTrue('over a selection of cells: no field over a paragraph''s end in a cell',
    FieldsWholeInCells(y.Document));
  src := ShownOf(y.Document);
  back := ReadBack(SaveOf(y));
  try
    AssertEquals('over a selection of cells: read back as shown', src, ShownOf(back));
  finally
    back.Free;
  end;
end;

initialization
  RegisterTest(TTyRichFieldPasteTest);

end.
