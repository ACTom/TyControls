unit test.richedit.links;

{ TTyRichEdit's links made, changed and removed: the commands (a link the model owns, a
  HYPERLINK field around text), the user's methods (InsertLink, SetLink, RemoveLink and their
  Can... queries), the two looks (Word's blue, written into the text; the theme's, painted at
  paint time over the automatic colour) and the two actions.

  Headless, on the probe of test.richedit.fieldctl (the test device: a glyph is a box filled
  in its ink). No window, no clipboard, no dialog. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, fpcunit, testregistry, Controls, Graphics, LCLType, Forms,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.BuiltinThemes, tyControls.StyleModel, tyControls.StrConsts,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Commands,
  tyControls.RichEdit.Layout, tyControls.RichEdit, tyControls.RichEdit.Actions,
  test.richedit.fieldctl;

type
  TTyRichLinksTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FRich: TFieldProbe;
    FClicks: Integer;
    FClickURL: string;
    FAskURL, FAskText: string;
    FAsked: Integer;
    FAnswerURL, FAnswerText: string;
    procedure LinkClicked(Sender: TObject; const AURL: string; AButton: TMouseButton);
    procedure GetLink(Sender: TObject; var AURL, AText: string; var AAllow: Boolean);
    procedure Load(const S: RawByteString);
    function SaveRtf: RawByteString;
    function Doc: TTyRichDocument;
    function AllText: RawByteString;
    function TextOf(APos, ALen: TTyRichPos): RawByteString;
    function Snap: RawByteString;
    function CharFmt(APos: TTyRichPos): TTyCharFormat;
    function OpenMark(APos: TTyRichPos): TTyRichFieldMark;
    function Select(AStart, ALen: TTyRichPos): Boolean;
    function UrlAt(APos: TTyRichPos): string;
    function Instruction(APos: TTyRichPos): string;
    procedure Reload(const S: RawByteString);
    function Ink(AChar: TTyRichPos; out APx: TBGRAPixel): Boolean;
    function LinkInk: TBGRAPixel;
    function TextInkOfTheme: TBGRAPixel;
    procedure CheckRefused(const AWhat: string; ACan: Boolean; ADid: Boolean;
      const AReason: string; const ABefore: RawByteString; ADepth: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestInsertLinkWrapsTheSelection;
    procedure TestInsertLinkWithTextAtTheCaret;
    procedure TestSetLinkReplacesTargetAndText;
    procedure TestRemoveLinkKeepsTheText;
    procedure TestRemoveLinkTakesTheLinksLookAway;
    procedure TestBookmarkAndMixedTargets;
    procedure TestRefusedWhereALinkCannotGo;
    procedure TestThemeLookFollowsTheSkin;
    procedure TestWordBlueIsExplicit;
    procedure TestALinkOnAShadedGroundIsTheLinkColour;
    procedure TestClickFiresOnAnInsertedLink;
    procedure TestTheActionsAskAndRun;
  end;

implementation

const
  BS = #92;
  HeadNoColour = '{|rtf1|ansi|deff0{|fonttbl{|f0 Arial;}}|pard|f0 ';
  Head = '{|rtf1|ansi|deff0{|fonttbl{|f0 Arial;}}{|colortbl;|red0|green0|blue255;}|pard|f0 ';

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

function U(const S: UTF8String): RawByteString;
begin
  Result := S;
  SetCodePage(Result, CP_NONE, False);
end;

// a string's bytes (a literal of this unit is UTF-8), so that comparisons never convert
function Raw(const S: string): RawByteString;
begin
  Result := S;
  SetCodePage(Result, CP_NONE, False);
end;

function SamePx(const A, B: TBGRAPixel): Boolean;
begin
  Result := (A.red = B.red) and (A.green = B.green) and (A.blue = B.blue);
end;

function PxText(const A: TBGRAPixel): string;
begin
  Result := Format('(%d, %d, %d)', [A.red, A.green, A.blue]);
end;

{ ab link cd: a plain paragraph, "link" at 3..6. }
function PlainDoc: RawByteString;
begin
  Result := Rtf(HeadNoColour + 'ab link cd|par second|par}');
end;

{ ab [link] cd: a link read from the file, open mark at 3, close at 8. }
function FileLinkDoc: RawByteString;
begin
  Result := Rtf(Head + 'ab {|field{|*|fldinst HYPERLINK "http://x.test/a"}{|fldrslt {|ul|cf1 link}}} cd|par}');
end;

{ ---- the suite ---- }

procedure TTyRichLinksTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FRich := TFieldProbe.Create(nil);
  FRich.Controller := FCtl;
  FRich.Font.PixelsPerInch := 96;
  FRich.SetBounds(0, 0, 600, 400);
  FRich.OnLinkClick := @LinkClicked;
  FClicks := 0;
  FClickURL := '';
  FAsked := 0;
end;

procedure TTyRichLinksTest.TearDown;
begin
  FreeAndNil(FRich);
  FreeAndNil(FCtl);
end;

procedure TTyRichLinksTest.LinkClicked(Sender: TObject; const AURL: string;
  AButton: TMouseButton);
begin
  Inc(FClicks);
  FClickURL := AURL;
end;

procedure TTyRichLinksTest.GetLink(Sender: TObject; var AURL, AText: string;
  var AAllow: Boolean);
begin
  Inc(FAsked);
  FAskURL := AURL;
  FAskText := AText;
  AURL := FAnswerURL;
  if FAnswerText <> #0 then AText := FAnswerText;
  AAllow := FAnswerURL <> '';
end;

procedure TTyRichLinksTest.Load(const S: RawByteString);
var
  st: TBytesStream;
  b: TBytes;
begin
  b := nil;
  SetLength(b, Length(S));
  if S <> '' then Move(S[1], b[0], Length(S));
  st := TBytesStream.Create(b);
  try
    FRich.LoadFromStream(st);
  finally
    st.Free;
  end;
  FRich.FinishLoading;
  FRich.UpdateView;
  FRich.Refused := 0;
  FRich.LastReason := '';
end;

procedure TTyRichLinksTest.Reload(const S: RawByteString);
begin
  Load(S);
end;

function TTyRichLinksTest.SaveRtf: RawByteString;
var
  st: TBytesStream;
begin
  st := TBytesStream.Create;
  try
    FRich.SaveToStream(st, rfRtf);
    Result := '';
    SetLength(Result, st.Size);
    if st.Size > 0 then Move(st.Bytes[0], Result[1], st.Size);
    SetCodePage(Result, CP_NONE, False);
  finally
    st.Free;
  end;
end;

function TTyRichLinksTest.Doc: TTyRichDocument;
begin
  Result := FRich.Document;
end;

function TTyRichLinksTest.AllText: RawByteString;
begin
  Result := Doc.Text.GetText(0, Doc.Text.Length);
  SetCodePage(Result, CP_NONE, False);
end;

function TTyRichLinksTest.TextOf(APos, ALen: TTyRichPos): RawByteString;
begin
  Result := Doc.Text.GetText(APos, ALen);
  SetCodePage(Result, CP_NONE, False);
end;

// what a refusal must leave as it was: the saved file (a plain text document: its text)
function TTyRichLinksTest.Snap: RawByteString;
begin
  if FRich.PlainText then Result := AllText else Result := SaveRtf;
end;

function TTyRichLinksTest.CharFmt(APos: TTyRichPos): TTyCharFormat;
var
  p, i, k: Integer;
  runs: TTyRunArray;
  o: TTyRichPos;
begin
  p := Doc.Text.ParaOfPos(APos);
  o := APos - Doc.Text.ParaStart(p);
  runs := Doc.RunsOf(p);
  k := 0;
  for i := 0 to High(runs) do
    if runs[i].Start <= o then k := i;
  Result := Doc.Formats.CharFormat(runs[k].Format);
end;

function TTyRichLinksTest.OpenMark(APos: TTyRichPos): TTyRichFieldMark;
var
  o: TTyRichObject;
begin
  Result := nil;
  o := Doc.ObjectAt(APos);
  if (o is TTyRichFieldMark) and (TTyRichFieldMark(o).Kind = rfmOpen) then
    Result := TTyRichFieldMark(o);
end;

function TTyRichLinksTest.Select(AStart, ALen: TTyRichPos): Boolean;
begin
  FRich.SelStart := AStart;
  FRich.SelLength := ALen;
  Result := (FRich.SelStart = AStart) and (FRich.SelLength = ALen);
end;

{ The link's target as OnLinkClick gives it, of the link whose result holds APos. }
function TTyRichLinksTest.UrlAt(APos: TTyRichPos): string;
var
  s, n: TTyRichPos;
begin
  Result := '';
  FRich.SelStart := APos;
  s := -1;
  n := 0;
  if not FRich.LinkAtSelection(s, n, Result) then Result := '<none>';
end;

function TTyRichLinksTest.Instruction(APos: TTyRichPos): string;
var
  s, n: TTyRichPos;
begin
  Result := '';
  s := -1;
  n := 0;
  if not FRich.GetFieldRange(APos, s, n, Result) then Result := '<none>';
end;

{ The ink in the middle of character AChar's glyph, the whole control rendered at 96 PPI. }
function TTyRichLinksTest.Ink(AChar: TTyRichPos; out APx: TBGRAPixel): Boolean;
var
  bmp: TBitmap;
  r, r2: TRect;
  x, y: Integer;
begin
  r := FRich.PositionRect(AChar);
  r2 := FRich.PositionRect(AChar + 1, True);
  Result := (r.Bottom > r.Top) and (r2.Left > r.Left);
  APx := BGRAPixelTransparent;
  if not Result then Exit;
  x := (r.Left + r2.Left) div 2;
  y := r.Top + (r.Bottom - r.Top) * 2 div 5;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FRich.Width, FRich.Height);
    FRich.PaintPart(bmp.Canvas, Rect(0, 0, FRich.Width, FRich.Height), False);
  finally
    bmp.Free;
  end;
  Result := FRich.Surf <> nil;
  if Result then APx := FRich.Surf.GetPixel(x * FRich.Scale, y * FRich.Scale);
end;

function TTyRichLinksTest.LinkInk: TBGRAPixel;
var
  s: TTyStyleSet;
begin
  s := FCtl.Model.ResolveStyle('TyLinkLabelLink', '', []);
  AssertTrue('the theme has a link colour', tpTextColor in s.Present);
  Result := TyColorToBGRA(s.TextColor);
end;

function TTyRichLinksTest.TextInkOfTheme: TBGRAPixel;
begin
  Result := FRich.Style.TextColor;
end;

procedure TTyRichLinksTest.CheckRefused(const AWhat: string; ACan: Boolean; ADid: Boolean;
  const AReason: string; const ABefore: RawByteString; ADepth: Integer);
begin
  AssertFalse(AWhat + ': Can... is False', ACan);
  AssertFalse(AWhat + ': not done', ADid);
  AssertEquals(AWhat + ': told once', 1, FRich.Refused);
  AssertEquals(AWhat + ': the reason', AReason, FRich.LastReason);
  AssertTrue(AWhat + ': nothing changed', Snap = ABefore);
  AssertEquals(AWhat + ': no step', ADepth, Doc.UndoDepth);
  FRich.Refused := 0;
  FRich.LastReason := '';
end;

{ A selection becomes a link's text as it is: one step; the marks around it, the field the
  model's own with the instruction; the look Word gives a link; read back from the saved file
  it is a HYPERLINK field with the same instruction and the same text; typing in it is
  refused; undo gives the file's bytes back. }
procedure TTyRichLinksTest.TestInsertLinkWrapsTheSelection;
var
  before, saved: RawByteString;
  depth: Integer;
  m: TTyRichFieldMark;
  f: TTyCharFormat;
begin
  Load(PlainDoc);
  before := SaveRtf;
  AssertTrue('the plain file saves as it came', before = PlainDoc);
  depth := Doc.UndoDepth;
  AssertTrue('selected', Select(3, 4));
  AssertTrue('can', FRich.CanInsertLink);
  AssertTrue('made', FRich.InsertLink('http://x.test/'));
  AssertEquals('one step', depth + 1, Doc.UndoDepth);
  AssertEquals('nothing told', 0, FRich.Refused);
  m := OpenMark(3);
  AssertTrue('an open mark before the text', m <> nil);
  AssertTrue('the model''s own', m.Owned);
  AssertEquals('its instruction', 'HYPERLINK "http://x.test/"', m.Instruction);
  AssertEquals('the close mark after it', 8, Doc.FieldPartner(3));
  AssertTrue('the text kept', TextOf(4, 4) = 'link');
  f := CharFmt(4);
  AssertTrue('underlined', fsUnderline in f.Style);
  AssertEquals('Word''s blue', CTyRichLinkWordBlue, f.Color);
  AssertTrue('the text before untouched', not (fsUnderline in CharFmt(1).Style));
  AssertEquals('the caret behind the link', 9, FRich.SelStart);
  AssertTrue('right behind the link: it is the link', FRich.CanEditLink);
  FRich.SelStart := 3;
  AssertEquals('the caret rests before it', 3, FRich.SelStart);
  AssertTrue('right before the link: it is the link', FRich.CanEditLink);
  AssertEquals('its target', 'http://x.test/', UrlAt(5));
  // read-only text: a key inside it is refused
  FRich.SelStart := 5;
  FRich.Key8('z');
  AssertEquals('typing in the link refused', 1, FRich.Refused);
  AssertEquals('with the field reason', rsRichEditRefusedField, FRich.LastReason);
  saved := SaveRtf;
  AssertTrue('written as a field', Pos(U('{' + BS + 'field'), saved) > 0);
  Reload(saved);
  AssertTrue('read back: a field', OpenMark(3) <> nil);
  AssertEquals('read back: its instruction', 'HYPERLINK "http://x.test/"', Instruction(5));
  AssertEquals('read back: its target', 'http://x.test/', UrlAt(5));
  AssertTrue('read back: its text', TextOf(4, 4) = 'link');
  AssertTrue('read back: the look', fsUnderline in CharFmt(4).Style);
  AssertEquals('read back: the blue', CTyRichLinkWordBlue, CharFmt(4).Color);
  // undo is the file again
  Load(PlainDoc);
  Select(3, 4);
  FRich.InsertLink('http://x.test/');
  FRich.Undo;
  AssertTrue('undone: the file''s bytes', SaveRtf = before);
  FRich.Redo;
  AssertEquals('redone', 'http://x.test/', UrlAt(5));
  AssertTrue('redone: the same output', SaveRtf = saved);
end;

{ With no selection the text given goes in at the caret, in the format typed there with the
  look; with no text either, the address is the text. }
procedure TTyRichLinksTest.TestInsertLinkWithTextAtTheCaret;
var
  before: RawByteString;
  depth: Integer;
  m: TTyRichFieldMark;
begin
  Load(PlainDoc);
  before := SaveRtf;
  depth := Doc.UndoDepth;
  FRich.SelStart := 3;
  AssertTrue('made', FRich.InsertLink('https://example.com/', '文档'));
  AssertEquals('one step', depth + 1, Doc.UndoDepth);
  m := OpenMark(3);
  AssertTrue('a field at the caret', m <> nil);
  AssertEquals('around the text', 6, Doc.FieldPartner(3));
  AssertTrue('the text', TextOf(4, 2) = Raw('文档'));
  AssertTrue('the look', fsUnderline in CharFmt(4).Style);
  AssertEquals('the blue', CTyRichLinkWordBlue, CharFmt(4).Color);
  AssertTrue('the text after it as it was', TextOf(7, 4) = 'link');
  AssertEquals('the caret behind it', 7, FRich.SelStart);
  // typed behind it: outside the link, not in its look
  FRich.Key8('q');
  AssertEquals('typed outside', 6, Doc.FieldPartner(3));
  AssertFalse('not underlined', fsUnderline in CharFmt(7).Style);
  FRich.Undo;
  FRich.Undo;
  AssertTrue('undone: the file''s bytes', SaveRtf = before);
  // no text: the address
  FRich.SelStart := 0;
  AssertTrue('made with no text', FRich.InsertLink('http://a.test'));
  AssertTrue('the address is its text', TextOf(1, 13) = 'http://a.test');
  AssertEquals('around it', 14, Doc.FieldPartner(0));
  // a selection with a text: the text in its place
  Load(PlainDoc);
  Select(3, 4);
  AssertTrue('made over a selection with a text', FRich.InsertLink('http://b.test', 'new'));
  AssertTrue('the text in the selection''s place', TextOf(0, 3) = 'ab ');
  AssertTrue('the new text', TextOf(4, 3) = 'new');
  AssertEquals('around it', 7, Doc.FieldPartner(3));
  AssertTrue('the rest', TextOf(8, 3) = ' cd');
end;

{ SetLink: the target alone (the text and its look stay; the marks are new), then the target
  and the text (the text in the look the link's text had); each one step, undone exactly. }
procedure TTyRichLinksTest.TestSetLinkReplacesTargetAndText;
var
  before, mid: RawByteString;
  depth: Integer;
  m: TTyRichFieldMark;
  f: TTyCharFormat;
begin
  Load(FileLinkDoc);
  before := SaveRtf;
  AssertTrue('the file saves as it came', before = FileLinkDoc);
  depth := Doc.UndoDepth;
  FRich.SelStart := 5;
  AssertTrue('a link to change', FRich.CanEditLink);
  AssertTrue('changed', FRich.SetLink('http://y.test/'));
  AssertEquals('one step', depth + 1, Doc.UndoDepth);
  m := OpenMark(3);
  AssertTrue('a new open mark', (m <> nil) and m.Owned);
  AssertEquals('its instruction', 'HYPERLINK "http://y.test/"', m.Instruction);
  AssertEquals('the text as it was', 8, Doc.FieldPartner(3));
  AssertTrue('the text', TextOf(4, 4) = 'link');
  f := CharFmt(4);
  AssertTrue('its look kept', (fsUnderline in f.Style) and (f.Color = RGBToColor(0, 0, 255)));
  mid := SaveRtf;
  Reload(mid);
  AssertEquals('read back: the new target', 'http://y.test/', UrlAt(5));
  AssertTrue('read back: the text', TextOf(4, 4) = 'link');
  Load(FileLinkDoc);
  FRich.SelStart := 5;
  FRich.SetLink('http://y.test/');
  FRich.Undo;
  AssertTrue('undone: the file''s bytes', SaveRtf = before);
  // the target and the text
  FRich.SelStart := 5;
  AssertTrue('changed with a text', FRich.SetLink('http://z.test/', '新的文字'));
  AssertEquals('one step', depth + 1, Doc.UndoDepth);
  AssertEquals('the new target', 'http://z.test/', UrlAt(5));
  AssertTrue('the new text', TextOf(4, 4) = Raw('新的文字'));
  AssertEquals('around it', 8, Doc.FieldPartner(3));
  f := CharFmt(4);
  AssertTrue('in the look the old text had', (fsUnderline in f.Style) and
    (f.Color = RGBToColor(0, 0, 255)));
  AssertTrue('the text after it', TextOf(9, 3) = ' cd');
  FRich.Undo;
  AssertTrue('undone: the file''s bytes', SaveRtf = before);
  // a whole link selected counts as the link
  Select(3, 6);
  AssertTrue('the selected link changed', FRich.SetLink('http://w.test/'));
  AssertEquals('its target', 'http://w.test/', UrlAt(5));
end;

{ RemoveLink: the marks go, the text stays, selected, without the link's look; one step,
  undone to the file's bytes; a link over two paragraphs too (its second paragraph out of every field). }
procedure TTyRichLinksTest.TestRemoveLinkKeepsTheText;
var
  before, two: RawByteString;
  depth: Integer;
  f: TTyCharFormat;
begin
  Load(FileLinkDoc);
  before := SaveRtf;
  depth := Doc.UndoDepth;
  FRich.SelStart := 5;
  AssertTrue('removed', FRich.RemoveLink);
  AssertEquals('one step', depth + 1, Doc.UndoDepth);
  AssertTrue('no mark left', OpenMark(3) = nil);
  AssertTrue('the text', AllText = U('ab link cd'));
  f := CharFmt(3);
  AssertFalse('no underline', fsUnderline in f.Style);
  AssertEquals('the link blue back to automatic', clDefault, f.Color);
  AssertEquals('the text selected: from', 3, FRich.SelStart);
  AssertEquals('the text selected: length', 4, FRich.SelLength);
  AssertEquals('no link there now', '<none>', UrlAt(4));
  Reload(SaveRtf);
  AssertTrue('read back: no field', Pos(U('field'), SaveRtf) = 0);
  AssertTrue('read back: the text', AllText = U('ab link cd'));
  Load(FileLinkDoc);
  FRich.SelStart := 5;
  FRich.RemoveLink;
  FRich.Undo;
  AssertTrue('undone: the file''s bytes', SaveRtf = before);
  // a link whose text holds a paragraph's end
  two := Rtf(Head + 'x {|field{|*|fldinst HYPERLINK "http://two.test"}{|fldrslt first|par second}} y|par}');
  Load(two);
  AssertEquals('two paragraphs in it', 2, Doc.Text.ParaCount);
  AssertEquals('the second starts in it', 1, Doc.ParaFieldDepth(1));
  FRich.SelStart := Doc.Text.ParaStart(1) + 2;
  AssertEquals('the link around the second paragraph', 'http://two.test', UrlAt(Doc.Text.ParaStart(1) + 2));
  FRich.SelStart := Doc.Text.ParaStart(1) + 2;
  AssertTrue('removed', FRich.RemoveLink);
  AssertEquals('the second paragraph out of it', 0, Doc.ParaFieldDepth(1));
  AssertEquals('no field depth left', 0, Doc.FieldDepthAt(Doc.Text.Length));
  AssertTrue('the text', TextOf(Doc.Text.ParaStart(1), 8) = 'second y');
  AssertTrue('the first paragraph', TextOf(0, 7) = 'x first');
  Reload(SaveRtf);
  AssertEquals('read back: two paragraphs', 2, Doc.Text.ParaCount);
  AssertEquals('read back: no field', 0, Doc.ParaFieldDepth(1));
  Load(two);
  FRich.SelStart := 4;
  FRich.RemoveLink;
  FRich.Undo;
  AssertEquals('undone: in the field again', 1, Doc.ParaFieldDepth(1));
  AssertTrue('undone: the file''s bytes', SaveRtf = two);
end;

{ The look a link is given goes with it, and nothing else: each look made here, a link of
  Word's own file (its Hyperlink style, its theme's link colour), a link whose text was made
  red and bold (red and bold stay); one step with the removal, undone exactly. }
procedure TTyRichLinksTest.TestRemoveLinkTakesTheLinksLookAway;
var
  look: TTyRichLinkLook;
  f: TTyCharFormat;
  before: RawByteString;
  st: TFileStream;
  b: TBytes;
  p, depth, i: Integer;
  styled: Boolean;
begin
  for look := Low(TTyRichLinkLook) to High(TTyRichLinkLook) do
  begin
    Load(PlainDoc);
    before := SaveRtf;
    AssertTrue('made', Doc.Execute(TTyRichInsertLink.Create(3, 4, 'http://x.test/', '', look)));
    depth := Doc.UndoDepth;
    FRich.SelStart := 5;
    AssertTrue('removed', FRich.RemoveLink);
    AssertEquals('one step with the look', depth + 1, Doc.UndoDepth);
    f := CharFmt(3);
    AssertFalse('no underline', fsUnderline in f.Style);
    AssertEquals('the automatic colour', clDefault, f.Color);
    AssertTrue('the text before it untouched', CharFmt(1).Color = clDefault);
    FRich.Undo;
    AssertTrue('undone: the link and its look', fsUnderline in CharFmt(4).Style);
    FRich.Undo;
    AssertTrue('the file again', SaveRtf = before);
  end;
  // red and bold made by the user: they stay
  Load(PlainDoc);
  Select(3, 4);
  FRich.SelAttributes.Color := clRed;
  FRich.SelAttributes.Bold := True;
  Select(3, 4);
  AssertTrue('made', FRich.InsertLink('http://x.test/'));
  f := CharFmt(4);
  AssertTrue('the link underlined', fsUnderline in f.Style);
  AssertEquals('its own red kept by the look', clRed, f.Color);
  FRich.SelStart := 5;
  AssertTrue('removed', FRich.RemoveLink);
  f := CharFmt(3);
  AssertFalse('no underline', fsUnderline in f.Style);
  AssertTrue('bold stays', fsBold in f.Style);
  AssertEquals('red stays', clRed, f.Color);
  Load(Rtf('{|rtf1|ansi|deff0{|fonttbl{|f0 Arial;}}{|colortbl;|red255|green0|blue0;}|pard|f0 ' +
    'ab {|field{|*|fldinst HYPERLINK "http://r.test"}{|fldrslt {|ul|b|cf1 red}}} cd|par}'));
  FRich.SelStart := 5;
  AssertTrue('removed', FRich.RemoveLink);
  f := CharFmt(3);
  AssertFalse('the red link: no underline', fsUnderline in f.Style);
  AssertTrue('its bold stays', fsBold in f.Style);
  AssertEquals('its red stays', clRed, f.Color);
  // Word's own links
  st := TFileStream.Create(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim +
    'fixtures' + PathDelim + 'rtf' + PathDelim + 'word-toc.rtf', fmOpenRead or fmShareDenyWrite);
  try
    b := nil;
    SetLength(b, st.Size);
    if st.Size > 0 then st.ReadBuffer(b[0], st.Size);
  finally
    st.Free;
  end;
  before := '';
  SetLength(before, Length(b));
  if Length(b) > 0 then Move(b[0], before[1], Length(b));
  SetCodePage(before, CP_NONE, False);
  Load(before);
  p := FRich.FindText('中文网址', 0, -1, []);
  AssertTrue('Word''s link is there', p > 0);
  f := CharFmt(p);
  AssertTrue('Word''s link: underlined', fsUnderline in f.Style);
  AssertTrue('Word''s link: its theme''s link colour', TyRichIsLinkColor(f.Color));
  styled := False;
  for i := 0 to f.Extra.Count - 1 do
    if Copy(f.Extra.Item(i), 1, 3) = BS + 'cs' then styled := True;
  AssertTrue('Word''s link: its Hyperlink style', styled);
  depth := Doc.UndoDepth;
  FRich.SelStart := p + 1;
  AssertEquals('Word''s link', 'https://example.com/文档?q=中文', UrlAt(p + 1));
  FRich.SelStart := p + 1;
  AssertTrue('Word''s link removed', FRich.RemoveLink);
  AssertEquals('one step', depth + 1, Doc.UndoDepth);
  f := CharFmt(p - 1);
  AssertFalse('no underline', fsUnderline in f.Style);
  AssertEquals('the automatic colour', clDefault, f.Color);
  styled := False;
  for i := 0 to f.Extra.Count - 1 do
    if Copy(f.Extra.Item(i), 1, 3) = BS + 'cs' then styled := True;
  AssertFalse('no Hyperlink style', styled);
  FRich.Undo;
  AssertTrue('undone: Word''s file byte for byte', SaveRtf = before);
end;

{ A place in the document (#name) and a place in a target (target#name) are written as Word
  writes them, the address in two parts; Chinese in the target and the text is written as
  Unicode; read back, each link's target is what was given. }
procedure TTyRichLinksTest.TestBookmarkAndMixedTargets;
var
  saved: RawByteString;
  i: Integer;
begin
  Load(Rtf(HeadNoColour + 'one two three|par}'));
  FRich.SelStart := Doc.Text.Length;
  AssertTrue('a place of the document', FRich.InsertLink('#a', 'A'));
  AssertEquals('its instruction', 'HYPERLINK ' + BS + 'l "a"', OpenMark(13).Instruction);
  FRich.SelStart := Doc.Text.Length;
  AssertTrue('a place in a target', FRich.InsertLink('http://x#a', 'B'));
  AssertEquals('in two parts', 'HYPERLINK "http://x" ' + BS + 'l "a"', OpenMark(16).Instruction);
  FRich.SelStart := Doc.Text.Length;
  AssertTrue('Chinese', FRich.InsertLink('https://例子.test/文档?q=中文#第二节', '中文'));
  FRich.SelStart := Doc.Text.Length;
  AssertTrue('a quote and a backslash', FRich.InsertLink('http://q.test/a"b' + BS + 'c', 'Q'));
  AssertEquals('escaped', 'HYPERLINK "http://q.test/a' + BS + '"b' + BS + BS + 'c"',
    OpenMark(23).Instruction);
  AssertEquals('#a', '#a', UrlAt(14));
  AssertEquals('http://x#a', 'http://x#a', UrlAt(17));
  AssertEquals('Chinese', 'https://例子.test/文档?q=中文#第二节', UrlAt(20));
  AssertEquals('quoted', 'http://q.test/a"b' + BS + 'c', UrlAt(24));
  saved := SaveRtf;
  AssertTrue('the place written as Word writes it', Pos(U('HYPERLINK ' + BS + BS + 'l "a"'), saved) > 0);
  AssertTrue('two parts', Pos(U('HYPERLINK "http://x" ' + BS + BS + 'l "a"'), saved) > 0);
  for i := 1 to Length(saved) do
    AssertTrue('only ASCII written (Chinese as \u)', Ord(saved[i]) < 128);
  AssertTrue('the Chinese as \u', Pos(U(BS + 'u20013'), saved) > 0);
  Reload(saved);
  AssertEquals('read back: #a', '#a', UrlAt(14));
  AssertEquals('read back: http://x#a', 'http://x#a', UrlAt(17));
  AssertEquals('read back: Chinese', 'https://例子.test/文档?q=中文#第二节', UrlAt(20));
  AssertEquals('read back: quoted', 'http://q.test/a"b' + BS + 'c', UrlAt(24));
  AssertTrue('read back: the Chinese text', TextOf(20, 2) = Raw('中文'));
end;

{ Where a link cannot go nothing changes, Can... says so, and the user is told once: inside a
  link's text, a selection across paragraphs or cells, one that cuts a link, one that holds a
  link, an empty address, a plain text document; SetLink and RemoveLink with no link, and for a
  link inside a table of contents. ReadOnly: the door is closed (nothing done, nothing told). }
procedure TTyRichLinksTest.TestRefusedWhereALinkCannotGo;
var
  before: RawByteString;
  depth: Integer;
  ok: Boolean;
begin
  Load(FileLinkDoc);
  before := SaveRtf;
  depth := Doc.UndoDepth;
  // read-only
  FRich.ReadOnly := True;
  Select(0, 2);
  AssertFalse('read-only: Can... False', FRich.CanInsertLink);
  AssertFalse('read-only: not done', FRich.InsertLink('http://r'));
  AssertFalse('read-only: SetLink not done', FRich.SetLink('http://r'));
  AssertEquals('read-only: nothing told', 0, FRich.Refused);
  AssertTrue('read-only: nothing changed', SaveRtf = before);
  FRich.ReadOnly := False;
  // in a link's text
  FRich.SelStart := 5;
  ok := FRich.CanInsertLink;
  CheckRefused('in a link', ok, FRich.InsertLink('http://r'), rsRichEditRefusedField, before, depth);
  // a selection that cuts the link
  Select(1, 4);
  ok := FRich.CanInsertLink;
  CheckRefused('cutting a link', ok, FRich.InsertLink('http://r'), rsRichEditRefusedField, before, depth);
  // one that holds it whole
  Select(0, 11);
  ok := FRich.CanInsertLink;
  CheckRefused('holding a link', ok, FRich.InsertLink('http://r'),
    rsRichEditRefusedLinkAroundField, before, depth);
  // an empty address
  Select(0, 2);
  AssertTrue('a good place', FRich.CanInsertLink);
  // the command itself: around a link, past a paragraph's end, in a result
  AssertFalse('the command around a link',
    Doc.Execute(TTyRichInsertLink.Create(0, 11, 'http://r', '', rllTheme)));
  AssertFalse('the command in a result',
    Doc.Execute(TTyRichInsertLink.Create(5, 1, 'http://r', '', rllTheme)));
  AssertFalse('the command past the paragraph',
    Doc.Execute(TTyRichInsertLink.Create(10, 3, 'http://r', '', rllTheme)));
  AssertFalse('the command with no address',
    Doc.Execute(TTyRichInsertLink.Create(0, 2, '', '', rllTheme)));
  AssertFalse('SetLink''s command where no field is',
    Doc.Execute(TTyRichSetLink.Create(0, 'http://r', '')));
  AssertFalse('RemoveLink''s command where no field is',
    Doc.Execute(TTyRichRemoveLink.Create(1)));
  AssertTrue('the commands changed nothing', SaveRtf = before);
  AssertEquals('the commands kept no step', depth, Doc.UndoDepth);
  CheckRefused('an empty address', False, FRich.InsertLink(''), rsRichEditRefusedLinkAddress,
    before, depth);
  // across paragraphs
  Load(Rtf(HeadNoColour + 'one|par two|par}'));
  before := SaveRtf;
  depth := Doc.UndoDepth;
  Select(1, 4);
  ok := FRich.CanInsertLink;
  CheckRefused('across paragraphs', ok, FRich.InsertLink('http://r'),
    rsRichEditRefusedLinkParagraphs, before, depth);
  // the paragraph's end with it
  Select(0, 4);
  ok := FRich.CanInsertLink;
  CheckRefused('with the paragraph''s end', ok, FRich.InsertLink('http://r'),
    rsRichEditRefusedLinkParagraphs, before, depth);
  // no link for SetLink and RemoveLink
  FRich.SelStart := 1;
  AssertFalse('no link: CanEditLink', FRich.CanEditLink);
  CheckRefused('SetLink with no link', False, FRich.SetLink('http://r'), rsRichEditRefusedNoLink,
    before, depth);
  CheckRefused('RemoveLink with no link', False, FRich.RemoveLink, rsRichEditRefusedNoLink,
    before, depth);
  // across table cells
  Load(Rtf(HeadNoColour + '|trowd|cellx2000|cellx4000|pard|intbl a1|cell b1|cell|row |pard after|par}'));
  before := SaveRtf;
  depth := Doc.UndoDepth;
  Select(1, 3);
  ok := FRich.CanInsertLink;
  CheckRefused('across cells', ok, FRich.InsertLink('http://r'), rsRichEditRefusedLinkParagraphs,
    before, depth);
  Select(0, 2);
  AssertTrue('inside one cell it can', FRich.CanInsertLink);
  // a link of a table of contents
  Load(Rtf(HeadNoColour + '{|field{|*|fldinst TOC ||o "1-3" ||h}{|fldrslt ' +
    '{|field{|*|fldinst HYPERLINK ||l "_Toc1"}{|fldrslt Chapter 1}}|par}} after|par}'));
  before := SaveRtf;
  depth := Doc.UndoDepth;
  FRich.SelStart := 4;
  AssertEquals('in the entry''s link', '#_Toc1', UrlAt(4));
  FRich.SelStart := 4;
  ok := FRich.CanEditLink;
  CheckRefused('SetLink in a contents', ok, FRich.SetLink('http://r'), rsRichEditRefusedField,
    before, depth);
  FRich.SelStart := 4;
  CheckRefused('RemoveLink in a contents', False, FRich.RemoveLink, rsRichEditRefusedField,
    before, depth);
  // a plain text document
  FRich.PlainText := True;
  FRich.Text := 'plain';
  FRich.Refused := 0;
  before := Snap;
  depth := Doc.UndoDepth;
  Select(0, 2);
  ok := FRich.CanInsertLink;
  CheckRefused('plain text', ok, FRich.InsertLink('http://r'), rsRichEditRefusedPlainLink,
    before, depth);
end;

{ The theme's look: a link made with it is underlined in the automatic colour - nothing of a
  colour in the file - and painted in the theme's link colour, in the light and the dark mode
  each its own; so is a file's link whose text has no colour, also in its second paragraph; a
  colour of the text's own is painted as it is; text outside links in the text colour. }
procedure TTyRichLinksTest.TestThemeLookFollowsTheSkin;
var
  px: TBGRAPixel;
  m: Integer;
  saved: RawByteString;
  p2: TTyRichPos;
begin
  Load(Rtf(HeadNoColour + 'ab link cd {|field{|*|fldinst HYPERLINK "http://f.test"}{|fldrslt auto|par next}} e|par}'));
  AssertTrue('made with the theme''s look',
    Doc.Execute(TTyRichInsertLink.Create(3, 4, 'http://t.test', '', rllTheme)));
  AssertEquals('the automatic colour', clDefault, CharFmt(4).Color);
  AssertTrue('underlined', fsUnderline in CharFmt(4).Style);
  AssertTrue('a text made a link with the theme''s look', Doc.Execute(
    TTyRichInsertLink.Create(Doc.Text.Length, 0, 'http://u.test', 'go', rllTheme)));
  AssertEquals('its text in the automatic colour', clDefault, CharFmt(Doc.Text.Length - 2).Color);
  AssertTrue('its text underlined', fsUnderline in CharFmt(Doc.Text.Length - 2).Style);
  saved := SaveRtf;
  AssertEquals('no colour written', 0, Pos(U(BS + 'cf'), saved));
  AssertEquals('no colour table', 0, Pos(U('colortbl'), saved));
  FRich.SelStart := Doc.Text.Length;
  FRich.UpdateView;
  p2 := Doc.Text.ParaStart(1);
  for m := 0 to 1 do
  begin
    if m = 0 then FCtl.Mode := 'light' else FCtl.Mode := 'dark';
    AssertFalse(FCtl.Mode + ': the link colour is not the text colour',
      SamePx(LinkInk, TextInkOfTheme));
    AssertTrue(FCtl.Mode + ': a glyph', Ink(5, px));
    AssertTrue(FCtl.Mode + ': the made link in the link colour ' + PxText(px),
      SamePx(px, LinkInk));
    AssertTrue(FCtl.Mode + ': a glyph before it', Ink(1, px));
    AssertTrue(FCtl.Mode + ': the text in the text colour ' + PxText(px),
      SamePx(px, TextInkOfTheme));
    AssertTrue(FCtl.Mode + ': a glyph of the file''s link', Ink(14, px));
    AssertTrue(FCtl.Mode + ': the file''s link in the link colour ' + PxText(px),
      SamePx(px, LinkInk));
    AssertTrue(FCtl.Mode + ': a glyph of its second paragraph', Ink(p2 + 1, px));
    AssertTrue(FCtl.Mode + ': its second paragraph in the link colour ' + PxText(px),
      SamePx(px, LinkInk));
    AssertTrue(FCtl.Mode + ': a glyph after it', Ink(p2 + 6, px));
    AssertTrue(FCtl.Mode + ': after it in the text colour ' + PxText(px),
      SamePx(px, TextInkOfTheme));
  end;
  // a colour of the text's own
  FCtl.Mode := 'dark';
  Load(FileLinkDoc);
  AssertTrue('a glyph of the blue link', Ink(5, px));
  AssertTrue('its own blue ' + PxText(px), SamePx(px, BGRA(0, 0, 255)));
end;

{ The editor's look is Word's: underlined in RGB 05 63 C1, a colour of the text's own - in
  the file's colour table, and painted so in the dark mode too. }
procedure TTyRichLinksTest.TestWordBlueIsExplicit;
var
  px: TBGRAPixel;
  saved: RawByteString;
begin
  Load(PlainDoc);
  Select(3, 4);
  AssertTrue('made', FRich.InsertLink('http://x.test/'));
  AssertEquals('the colour', CTyRichLinkWordBlue, CharFmt(4).Color);
  AssertEquals('RGB 05 63 C1', RGBToColor($05, $63, $C1), CTyRichLinkWordBlue);
  saved := SaveRtf;
  AssertTrue('in the colour table', Pos(U(BS + 'red5' + BS + 'green99' + BS + 'blue193'), saved) > 0);
  AssertTrue('underlined', Pos(U(BS + 'ul'), saved) > 0);
  FCtl.Mode := 'dark';
  FRich.SelStart := 0;
  FRich.UpdateView;
  AssertTrue('a glyph', Ink(5, px));
  AssertTrue('painted in it ' + PxText(px), SamePx(px, BGRA($05, $63, $C1)));
end;

{ A link's automatic text keeps the theme's link colour over a paragraph's shading and over
  the document's own ground (a link stays the colour the theme gives links); the automatic
  text beside it on that ground takes the contrasting colour, as any. }
procedure TTyRichLinksTest.TestALinkOnAShadedGroundIsTheLinkColour;
var
  px: TBGRAPixel;
  mode: Integer;
begin
  // a skin with a dark mode of its own (light text): the contrast over yellow is dark
  TyRegisterBuiltinThemes;
  FCtl.ThemeName := 'default';
  for mode := 0 to 1 do
  begin
    Load(PlainDoc);
    if mode = 0 then
    begin
      FRich.SelStart := 0;
      FRich.Paragraph.Shading := clYellow;
    end
    else
      FRich.DocumentColor := clYellow;
    AssertTrue('made', Doc.Execute(TTyRichInsertLink.Create(3, 4, 'http://t.test', '', rllTheme)));
    FCtl.Mode := 'dark';
    FRich.SelStart := Doc.Text.Length;
    FRich.UpdateView;
    AssertTrue('a glyph of the link', Ink(5, px));
    AssertTrue(Format('%d: the link colour, not the contrast %s', [mode, PxText(px)]),
      SamePx(px, LinkInk));
    AssertTrue('a glyph beside it', Ink(1, px));
    AssertFalse(Format('%d: the text beside it contrasts with the yellow %s', [mode, PxText(px)]),
      SamePx(px, TextInkOfTheme));
    AssertFalse(Format('%d: the text beside it is no link %s', [mode, PxText(px)]),
      SamePx(px, LinkInk));
  end;
end;

{ A link made in the control is a link to the user: a click on it in a read-only control
  gives its target. }
procedure TTyRichLinksTest.TestClickFiresOnAnInsertedLink;
var
  r, r2: TRect;
  p: TPoint;
begin
  Load(PlainDoc);
  Select(3, 4);
  AssertTrue('made', FRich.InsertLink('https://例子.test/#b'));
  FRich.ReadOnly := True;
  FRich.UpdateView;
  r := FRich.PositionRect(5);
  r2 := FRich.PositionRect(6, True);
  p := Point((r.Left + r2.Left) div 2, (r.Top + r.Bottom) div 2);
  FRich.MDown(mbLeft, [ssLeft], p.X, p.Y);
  FRich.MUp(mbLeft, [], p.X, p.Y);
  AssertEquals('one click', 1, FClicks);
  AssertEquals('its target', 'https://例子.test/#b', FClickURL);
end;

{ Insert link asks for the address and the text (the selection's; a link's own when the caret
  is in one) and makes or changes the link; a text left as given keeps the text as it is;
  AAllow False does nothing. Remove link is enabled in a link only. }
procedure TTyRichLinksTest.TestTheActionsAskAndRun;
var
  ins: TTyRichEditInsertLink;
  rem: TTyRichEditRemoveLink;
  depth: Integer;
begin
  Load(Rtf(HeadNoColour + 'ab {|b li}nk cd|par}'));
  ins := TTyRichEditInsertLink.Create(nil);
  rem := TTyRichEditRemoveLink.Create(nil);
  try
    ins.RichEdit := FRich;
    rem.RichEdit := FRich;
    ins.OnGetLink := @GetLink;
    Select(3, 4);
    TTyRichEditActionState.Find(FRich).Changed;
    ins.Update;
    rem.Update;
    AssertTrue('insert enabled', ins.Enabled);
    AssertFalse('remove disabled', rem.Enabled);
    // declined
    FAnswerURL := '';
    FAnswerText := #0;
    depth := Doc.UndoDepth;
    ins.Execute;
    AssertEquals('asked', 1, FAsked);
    AssertEquals('no address given yet', '', FAskURL);
    AssertEquals('the selection''s text given', 'link', FAskText);
    AssertEquals('declined: nothing', depth, Doc.UndoDepth);
    // made, the text left as it was
    FAnswerURL := 'http://act.test';
    ins.Execute;
    AssertEquals('made', 'http://act.test', UrlAt(5));
    AssertTrue('its text as it was', TextOf(4, 4) = 'link');
    AssertTrue('its formats as they were', (fsBold in CharFmt(4).Style) and
      not (fsBold in CharFmt(6).Style));
    // in the link: its own address and text, changed
    FRich.SelStart := 5;
    TTyRichEditActionState.Find(FRich).Changed;
    ins.Update;
    rem.Update;
    AssertTrue('insert enabled in a link', ins.Enabled);
    AssertTrue('remove enabled in a link', rem.Enabled);
    FAnswerURL := 'http://act2.test';
    FAnswerText := 'other';
    ins.Execute;
    AssertEquals('its address given', 'http://act.test', FAskURL);
    AssertEquals('its text given', 'link', FAskText);
    AssertEquals('changed', 'http://act2.test', UrlAt(5));
    AssertTrue('its new text', TextOf(4, 5) = 'other');
    FRich.SelStart := 5;
    TTyRichEditActionState.Find(FRich).Changed;
    rem.Update;
    rem.Execute;
    AssertEquals('removed', '<none>', UrlAt(5));
    AssertTrue('the text kept', TextOf(3, 5) = 'other');
  finally
    rem.Free;
    ins.Free;
  end;
end;

initialization
  RegisterTest(TTyRichLinksTest);
end.
