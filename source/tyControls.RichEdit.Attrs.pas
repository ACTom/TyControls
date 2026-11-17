unit tyControls.RichEdit.Attrs;

{ The format API of TTyRichEdit in Delphi's style (Task 11a): TTyRichTextAttributes - the
  SelAttributes and DefAttributes of Vcl.ComCtrls.TRichEdit - and TTyRichParaAttributes - its
  Paragraph -, and the records of the RichMemo style (TTyFontParams, TTyParaMetric, ...). They
  hold nothing: every read asks the control, every write is one command of the document run
  by the control (tyControls.RichEdit), so these classes only translate units and names. The
  control makes its own subclasses of them; an application never creates one.

  Units: sizes in points (the engine keeps half points); indents, spaces and tab positions in
  points as Delphi has them (the engine keeps twips: a read rounds to the nearest point, a
  write is exact); the RichMemo records in points as Doubles (exact both ways, 1/20 point). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, tyControls.RichEdit.Text, tyControls.RichEdit.Model;

type
  { Which attributes are the same over the whole selection (Delphi's TConsistentAttribute,
    with the engine's three more: charset, background and vertical position). Delphi's
    caProtected has no counterpart: the engine holds no protected text. }
  TTyRichConsistentAttribute = (caBold, caColor, caFace, caItalic, caSize, caStrikeOut,
    caUnderline, caCharset, caBackColor, caVertAlign);
  TTyRichConsistentAttributes = set of TTyRichConsistentAttribute;

  { The character format of the selection (SelAttributes) or the control's base
    (DefAttributes) - see the control's properties for what each answers for. Reading a value
    of a selection whose characters differ gives the selection's first character's
    (ConsistentAttributes says which differ). Each write changes that one attribute and
    leaves the others as each character has them: one command (one undo step), or - with
    nothing selected - the format the next typed text gets. Assign takes a TFont or another
    TTyRichTextAttributes (all of their attributes, one write); AssignTo fills a TFont. }
  TTyRichTextAttributes = class(TPersistent)
  protected
    { The format the reads answer with: FontName and SizeHalfPt resolved (never '' or 0). }
    function GetFormat: TTyCharFormat; virtual; abstract;
    function GetConsistent: TTyCharFormatMask; virtual; abstract;
    procedure SetFormat(AMask: TTyCharFormatMask; const AValue: TTyCharFormat); virtual; abstract;
    { The pixels per inch Height counts with (the control's font's). }
    function GetPPI: Integer; virtual; abstract;
    procedure AssignTo(Dest: TPersistent); override;
  private
    function GetName: TFontName;
    procedure SetName(const AValue: TFontName);
    function GetSize: Integer;
    procedure SetSize(AValue: Integer);
    function GetHeight: Integer;
    procedure SetHeight(AValue: Integer);
    function GetStyle: TFontStyles;
    procedure SetStyle(AValue: TFontStyles);
    function GetColor: TColor;
    procedure SetColor(AValue: TColor);
    function GetCharset: TFontCharset;
    procedure SetCharset(AValue: TFontCharset);
    function GetBackColor: TColor;
    procedure SetBackColor(AValue: TColor);
    function GetVertAlign: TTyVertAlign;
    procedure SetVertAlign(AValue: TTyVertAlign);
    function GetConsistentAttributes: TTyRichConsistentAttributes;
  public
    procedure Assign(Source: TPersistent); override;
    { The font's name. }
    property Name: TFontName read GetName write SetName;
    { Points (the engine's half points: a read of 10.5 pt says 10, as Delphi's). }
    property Size: Integer read GetSize write SetSize;
    { Pixels at the control's PPI: Size * PPI / 72, as Delphi's. }
    property Height: Integer read GetHeight write SetHeight;
    { Bold, italic, underline, strike-through (fsStrikeOut is the engine's Strike). }
    property Style: TFontStyles read GetStyle write SetStyle;
    { clDefault: the theme's text colour (Delphi's "auto" colour). }
    property Color: TColor read GetColor write SetColor;
    property Charset: TFontCharset read GetCharset write SetCharset;
    { The text's highlight; clNone: none. }
    property BackColor: TColor read GetBackColor write SetBackColor;
    { Superscript, subscript or neither. }
    property VertAlign: TTyVertAlign read GetVertAlign write SetVertAlign;
    { The attributes that are the same over the whole selection: walks the selection's
      paragraphs until every attribute was found to differ (a cost in proportion to the
      selection, at most). Everything for an empty selection. }
    property ConsistentAttributes: TTyRichConsistentAttributes read GetConsistentAttributes;
  end;

  { The paragraph format of the paragraphs the selection touches (Delphi's Paragraph): reads
    answer for the first of them, each write is one command over all of them (the caret's
    paragraph when nothing is selected; a selection that ends at a paragraph's very start
    does not touch that paragraph). Units: points. }
  TTyRichParaAttributes = class(TPersistent)
  protected
    function GetFormat: TTyParaFormat; virtual; abstract;
    procedure SetFormat(AMask: TTyParaFormatMask; const AValue: TTyParaFormat); virtual; abstract;
  private
    function GetAlignment: TTyParaAlign;
    procedure SetAlignment(AValue: TTyParaAlign);
    function GetFirstIndent: Integer;
    procedure SetFirstIndent(AValue: Integer);
    function GetLeftIndent: Integer;
    procedure SetLeftIndent(AValue: Integer);
    function GetRightIndent: Integer;
    procedure SetRightIndent(AValue: Integer);
    function GetNumbering: TTyListKind;
    procedure SetNumbering(AValue: TTyListKind);
    function GetNumberingStart: Integer;
    procedure SetNumberingStart(AValue: Integer);
    function GetTab(AIndex: Byte): Integer;
    procedure SetTab(AIndex: Byte; AValue: Integer);
    function GetTabCount: Integer;
    procedure SetTabCount(AValue: Integer);
    function GetSpaceBefore: Integer;
    procedure SetSpaceBefore(AValue: Integer);
    function GetSpaceAfter: Integer;
    procedure SetSpaceAfter(AValue: Integer);
    function GetLineSpacingRule: TTyLineSpacing;
    procedure SetLineSpacingRule(AValue: TTyLineSpacing);
    function GetLineSpacing: Integer;
    procedure SetLineSpacing(AValue: Integer);
  public
    procedure Assign(Source: TPersistent); override;
    property Alignment: TTyParaAlign read GetAlignment write SetAlignment;
    { As Delphi's: FirstIndent is where the first line starts, from the left margin;
      LeftIndent is where the other lines start, from the first line's start (negative:
      a hanging indent); RightIndent from the right margin. Points. A write keeps the other
      two meanings: FirstIndent moves the whole paragraph (the other lines keep their offset
      from the first), LeftIndent moves the other lines only. }
    property FirstIndent: Integer read GetFirstIndent write SetFirstIndent;
    property LeftIndent: Integer read GetLeftIndent write SetLeftIndent;
    property RightIndent: Integer read GetRightIndent write SetRightIndent;
    { None, bullets or one of the numbered kinds the engine holds. }
    property Numbering: TTyListKind read GetNumbering write SetNumbering;
    { The number the list starts at. }
    property NumberingStart: Integer read GetNumberingStart write SetNumberingStart;
    { Tab stop AIndex (0-based), points from the left indent's origin; a write past the last
      adds left-aligned stops up to it. TabCount := N keeps the first N (more: new ones at 0
      are not added - a write of TabCount above the count raises EListError, as no position
      for them is known). }
    property Tab[AIndex: Byte]: Integer read GetTab write SetTab;
    property TabCount: Integer read GetTabCount write SetTabCount;
    property SpaceBefore: Integer read GetSpaceBefore write SetSpaceBefore;
    property SpaceAfter: Integer read GetSpaceAfter write SetSpaceAfter;
    { The rule (single, 1.15, 1.5, double, exactly, at least) and, for exactly and at least,
      the line's height in points (LineSpacing; 0 for the other rules). }
    property LineSpacingRule: TTyLineSpacing read GetLineSpacingRule write SetLineSpacingRule;
    property LineSpacing: Integer read GetLineSpacing write SetLineSpacing;
  end;

  { ---- RichMemo's records (TFontParams, TParaMetric, ...), in points ---- }

  TTyVScriptPos = (vpNormal, vpSubScript, vpSuperScript);

  { RichMemo's TFontParams: Size in points, HasBkClr False - no highlight. }
  TTyFontParams = record
    Name: string;
    Size: Integer;
    Color: TColor;
    Style: TFontStyles;
    HasBkClr: Boolean;
    BkColor: TColor;
    VScriptPos: TTyVScriptPos;
  end;

  TTyTextModifyMaskItem = (tmm_Color, tmm_Name, tmm_Size, tmm_Styles, tmm_BackColor);
  TTyTextModifyMask = set of TTyTextModifyMaskItem;

  { RichMemo's TParaMetric, points: FirstLine where the first line starts, HeadIndent where
    the other lines start (both from the left margin), TailIndent from the right margin;
    LineSpacing a multiple of a single line (1.0, 1.15, 1.5, 2.0: the engine's rules; a
    read of an exact or at-least spacing says 0). }
  TTyParaMetric = record
    FirstLine: Double;
    TailIndent: Double;
    HeadIndent: Double;
    SpaceBefore: Double;
    SpaceAfter: Double;
    LineSpacing: Double;
  end;

  TTyParaNumStyle = (pnNone, pnBullet, pnNumber, pnLowLetter, pnLowRoman, pnUpLetter,
    pnUpRoman, pnCustomChar);

  { RichMemo's TParaNumbering. The engine holds the style and the start: Indent, CustomChar,
    SepChar and ForceNewNum are not kept (a write ignores them, a read gives 0, #0, #0,
    False); pnCustomChar is written as a bullet. }
  TTyParaNumbering = record
    Style: TTyParaNumStyle;
    Indent: Double;
    CustomChar: WideChar;
    NumberStart: Integer;
    SepChar: WideChar;
    ForceNewNum: Boolean;
  end;

  TTyRichTabStop = record
    Offset: Double;          // points from the left indent's origin
    Align: TTyTabAlign;
  end;

  TTyTabStopList = record
    Count: Integer;
    Tabs: array of TTyRichTabStop;
  end;

const
  CTyCharStyleMask = [cffBold, cffItalic, cffUnderline, cffStrike];
  { What RichMemo's SetTextAttributes and an Assign from a TFont write. }
  CTyFontParamsMask = [cffFontName, cffSize, cffBold, cffItalic, cffUnderline, cffStrike,
    cffColor, cffHighlight, cffVertAlign];
  CTyFontMask = [cffFontName, cffSize, cffBold, cffItalic, cffUnderline, cffStrike, cffColor,
    cffCharset];

{ Points and twips (the engine's unit for indents, spaces and tabs). }
function TyRichPtToTwips(APoints: Double): Integer;
function TyRichTwipsToPt(ATwips: Integer): Integer;
{ The fields of the two formats that differ (Style flag by flag; Strike and fsStrikeOut as
  one). }
function TyRichCharDiff(const A, B: TTyCharFormat): TTyCharFormatMask;
function TyRichConsistentOf(AMask: TTyCharFormatMask): TTyRichConsistentAttributes;
{ RichMemo's records to and from the engine's formats. }
function TyRichFontParamsOf(const AFormat: TTyCharFormat): TTyFontParams;
function TyRichCharFormatOf(const AParams: TTyFontParams): TTyCharFormat;
function TyRichMetricOf(const AFormat: TTyParaFormat): TTyParaMetric;
function TyRichParaFormatOfMetric(const AMetric: TTyParaMetric): TTyParaFormat;
function TyRichNumberingOf(const AList: TTyListFormat): TTyParaNumbering;
function TyRichListOf(const ANumbering: TTyParaNumbering; const AOld: TTyListFormat): TTyListFormat;
function TyRichTabListOf(const ATabs: TTyTabStops): TTyTabStopList;
function TyRichTabsOf(const AList: TTyTabStopList; const AOld: TTyTabStops): TTyTabStops;

implementation

uses
  Math;

function TyRichPtToTwips(APoints: Double): Integer;
begin
  Result := Round(APoints * 20);
end;

function TyRichTwipsToPt(ATwips: Integer): Integer;
begin
  // half a point away from zero: 10 twips is 1 point (Round's banker's rule would say 0)
  if ATwips >= 0 then Result := (ATwips + 10) div 20 else Result := -((-ATwips + 10) div 20);
end;

function TyRichCharDiff(const A, B: TTyCharFormat): TTyCharFormatMask;
begin
  Result := [];
  if A.FontName <> B.FontName then Include(Result, cffFontName);
  if A.Charset <> B.Charset then Include(Result, cffCharset);
  if A.SizeHalfPt <> B.SizeHalfPt then Include(Result, cffSize);
  if (fsBold in A.Style) <> (fsBold in B.Style) then Include(Result, cffBold);
  if (fsItalic in A.Style) <> (fsItalic in B.Style) then Include(Result, cffItalic);
  if (fsUnderline in A.Style) <> (fsUnderline in B.Style) then Include(Result, cffUnderline);
  if (A.Strike or (fsStrikeOut in A.Style)) <> (B.Strike or (fsStrikeOut in B.Style)) then
    Include(Result, cffStrike);
  if A.VertAlign <> B.VertAlign then Include(Result, cffVertAlign);
  if A.Color <> B.Color then Include(Result, cffColor);
  if A.HighlightColor <> B.HighlightColor then Include(Result, cffHighlight);
end;

function TyRichConsistentOf(AMask: TTyCharFormatMask): TTyRichConsistentAttributes;
begin
  Result := [];
  if cffBold in AMask then Include(Result, caBold);
  if cffColor in AMask then Include(Result, caColor);
  if cffFontName in AMask then Include(Result, caFace);
  if cffItalic in AMask then Include(Result, caItalic);
  if cffSize in AMask then Include(Result, caSize);
  if cffStrike in AMask then Include(Result, caStrikeOut);
  if cffUnderline in AMask then Include(Result, caUnderline);
  if cffCharset in AMask then Include(Result, caCharset);
  if cffHighlight in AMask then Include(Result, caBackColor);
  if cffVertAlign in AMask then Include(Result, caVertAlign);
end;

{ ---- TTyRichTextAttributes ---- }

function TTyRichTextAttributes.GetName: TFontName;
begin
  Result := GetFormat.FontName;
end;

procedure TTyRichTextAttributes.SetName(const AValue: TFontName);
var
  f: TTyCharFormat;
begin
  f := TyDefaultCharFormat;
  f.FontName := AValue;
  SetFormat([cffFontName], f);
end;

function TTyRichTextAttributes.GetSize: Integer;
begin
  Result := GetFormat.SizeHalfPt div 2;
end;

procedure TTyRichTextAttributes.SetSize(AValue: Integer);
var
  f: TTyCharFormat;
begin
  f := TyDefaultCharFormat;
  if AValue < 0 then AValue := 0;
  f.SizeHalfPt := AValue * 2;
  SetFormat([cffSize], f);
end;

function TTyRichTextAttributes.GetHeight: Integer;
begin
  Result := Round(GetFormat.SizeHalfPt * Int64(GetPPI) / 144);
end;

procedure TTyRichTextAttributes.SetHeight(AValue: Integer);
var
  f: TTyCharFormat;
begin
  f := TyDefaultCharFormat;
  if AValue < 0 then AValue := 0;
  // to whole points, as Size counts them
  f.SizeHalfPt := Round(AValue * Int64(72) / GetPPI) * 2;
  SetFormat([cffSize], f);
end;

function TTyRichTextAttributes.GetStyle: TFontStyles;
var
  f: TTyCharFormat;
begin
  f := GetFormat;
  Result := f.Style;
  if f.Strike then Include(Result, fsStrikeOut);
end;

procedure TTyRichTextAttributes.SetStyle(AValue: TFontStyles);
var
  f: TTyCharFormat;
begin
  f := TyDefaultCharFormat;
  f.Style := AValue - [fsStrikeOut];
  f.Strike := fsStrikeOut in AValue;
  SetFormat(CTyCharStyleMask, f);
end;

function TTyRichTextAttributes.GetColor: TColor;
begin
  Result := GetFormat.Color;
end;

procedure TTyRichTextAttributes.SetColor(AValue: TColor);
var
  f: TTyCharFormat;
begin
  f := TyDefaultCharFormat;
  f.Color := AValue;
  SetFormat([cffColor], f);
end;

function TTyRichTextAttributes.GetCharset: TFontCharset;
begin
  Result := TFontCharset(GetFormat.Charset);
end;

procedure TTyRichTextAttributes.SetCharset(AValue: TFontCharset);
var
  f: TTyCharFormat;
begin
  f := TyDefaultCharFormat;
  f.Charset := AValue;
  SetFormat([cffCharset], f);
end;

function TTyRichTextAttributes.GetBackColor: TColor;
begin
  Result := GetFormat.HighlightColor;
end;

procedure TTyRichTextAttributes.SetBackColor(AValue: TColor);
var
  f: TTyCharFormat;
begin
  f := TyDefaultCharFormat;
  f.HighlightColor := AValue;
  SetFormat([cffHighlight], f);
end;

function TTyRichTextAttributes.GetVertAlign: TTyVertAlign;
begin
  Result := GetFormat.VertAlign;
end;

procedure TTyRichTextAttributes.SetVertAlign(AValue: TTyVertAlign);
var
  f: TTyCharFormat;
begin
  f := TyDefaultCharFormat;
  f.VertAlign := AValue;
  SetFormat([cffVertAlign], f);
end;

function TTyRichTextAttributes.GetConsistentAttributes: TTyRichConsistentAttributes;
begin
  Result := TyRichConsistentOf(GetConsistent);
end;

procedure TTyRichTextAttributes.Assign(Source: TPersistent);
var
  f: TTyCharFormat;
  fnt: TFont;
begin
  if Source is TFont then
  begin
    fnt := TFont(Source);
    f := TyDefaultCharFormat;
    f.FontName := fnt.Name;
    f.SizeHalfPt := Max(0, fnt.Size) * 2;
    f.Style := fnt.Style - [fsStrikeOut];
    f.Strike := fsStrikeOut in fnt.Style;
    f.Color := fnt.Color;
    f.Charset := fnt.CharSet;
    SetFormat(CTyFontMask, f);
  end
  else if Source is TTyRichTextAttributes then
  begin
    f := TTyRichTextAttributes(Source).GetFormat;
    SetFormat(CTyFontMask + [cffHighlight, cffVertAlign], f);
  end
  else
    inherited Assign(Source);
end;

procedure TTyRichTextAttributes.AssignTo(Dest: TPersistent);
var
  fnt: TFont;
begin
  if Dest is TFont then
  begin
    fnt := TFont(Dest);
    fnt.Name := Name;
    fnt.Size := Size;
    fnt.Style := Style;
    fnt.Color := Color;
    fnt.CharSet := Charset;
  end
  else
    inherited AssignTo(Dest);
end;

{ ---- TTyRichParaAttributes ---- }

function TTyRichParaAttributes.GetAlignment: TTyParaAlign;
begin
  Result := GetFormat.Align;
end;

procedure TTyRichParaAttributes.SetAlignment(AValue: TTyParaAlign);
var
  f: TTyParaFormat;
begin
  f := TyDefaultParaFormat;
  f.Align := AValue;
  SetFormat([pffAlign], f);
end;

function TTyRichParaAttributes.GetFirstIndent: Integer;
var
  f: TTyParaFormat;
begin
  f := GetFormat;
  Result := TyRichTwipsToPt(f.LeftIndent + f.FirstIndent);
end;

procedure TTyRichParaAttributes.SetFirstIndent(AValue: Integer);
var
  f, cur: TTyParaFormat;
begin
  // the first line at AValue, the other lines keeping their offset from it: the engine's
  // first-line offset stays, its left indent moves
  cur := GetFormat;
  f := TyDefaultParaFormat;
  f.LeftIndent := TyRichPtToTwips(AValue) - cur.FirstIndent;
  SetFormat([pffLeftIndent], f);
end;

function TTyRichParaAttributes.GetLeftIndent: Integer;
begin
  Result := TyRichTwipsToPt(-GetFormat.FirstIndent);
end;

procedure TTyRichParaAttributes.SetLeftIndent(AValue: Integer);
var
  f, cur: TTyParaFormat;
  first: Integer;
begin
  // the first line stays where it is, the other lines go AValue from it
  cur := GetFormat;
  first := cur.LeftIndent + cur.FirstIndent;
  f := TyDefaultParaFormat;
  f.FirstIndent := -TyRichPtToTwips(AValue);
  f.LeftIndent := first - f.FirstIndent;
  SetFormat([pffLeftIndent, pffFirstIndent], f);
end;

function TTyRichParaAttributes.GetRightIndent: Integer;
begin
  Result := TyRichTwipsToPt(GetFormat.RightIndent);
end;

procedure TTyRichParaAttributes.SetRightIndent(AValue: Integer);
var
  f: TTyParaFormat;
begin
  f := TyDefaultParaFormat;
  f.RightIndent := TyRichPtToTwips(AValue);
  SetFormat([pffRightIndent], f);
end;

function TTyRichParaAttributes.GetNumbering: TTyListKind;
begin
  Result := GetFormat.List.Kind;
end;

procedure TTyRichParaAttributes.SetNumbering(AValue: TTyListKind);
var
  f: TTyParaFormat;
begin
  f := TyDefaultParaFormat;
  f.List := GetFormat.List;
  f.List.Kind := AValue;
  if (AValue <> lkNone) and (f.List.StartAt <= 0) then f.List.StartAt := 1;
  SetFormat([pffList], f);
end;

function TTyRichParaAttributes.GetNumberingStart: Integer;
begin
  Result := GetFormat.List.StartAt;
end;

procedure TTyRichParaAttributes.SetNumberingStart(AValue: Integer);
var
  f: TTyParaFormat;
begin
  f := TyDefaultParaFormat;
  f.List := GetFormat.List;
  f.List.StartAt := AValue;
  SetFormat([pffList], f);
end;

function TTyRichParaAttributes.GetTab(AIndex: Byte): Integer;
var
  f: TTyParaFormat;
begin
  f := GetFormat;
  if AIndex >= Length(f.Tabs) then
    raise EListError.CreateFmt('Tab index %d out of 0..%d', [AIndex, Length(f.Tabs) - 1]);
  Result := TyRichTwipsToPt(f.Tabs[AIndex].Position);
end;

procedure TTyRichParaAttributes.SetTab(AIndex: Byte; AValue: Integer);
var
  f: TTyParaFormat;
  i, n: Integer;
begin
  f := TyDefaultParaFormat;
  f.Tabs := Copy(GetFormat.Tabs);
  n := Length(f.Tabs);
  if AIndex >= n then
  begin
    SetLength(f.Tabs, AIndex + 1);
    for i := n to AIndex do
    begin
      f.Tabs[i].Position := 0;
      f.Tabs[i].Align := ttaLeft;
      f.Tabs[i].Leader := ttlNone;
    end;
  end;
  f.Tabs[AIndex].Position := TyRichPtToTwips(AValue);
  SetFormat([pffTabs], f);
end;

function TTyRichParaAttributes.GetTabCount: Integer;
begin
  Result := Length(GetFormat.Tabs);
end;

procedure TTyRichParaAttributes.SetTabCount(AValue: Integer);
var
  f: TTyParaFormat;
begin
  f := TyDefaultParaFormat;
  f.Tabs := Copy(GetFormat.Tabs);
  if (AValue < 0) or (AValue > Length(f.Tabs)) then
    raise EListError.CreateFmt('Tab count %d out of 0..%d', [AValue, Length(f.Tabs)]);
  SetLength(f.Tabs, AValue);
  SetFormat([pffTabs], f);
end;

function TTyRichParaAttributes.GetSpaceBefore: Integer;
begin
  Result := TyRichTwipsToPt(GetFormat.SpaceBefore);
end;

procedure TTyRichParaAttributes.SetSpaceBefore(AValue: Integer);
var
  f: TTyParaFormat;
begin
  f := TyDefaultParaFormat;
  f.SpaceBefore := TyRichPtToTwips(AValue);
  SetFormat([pffSpaceBefore], f);
end;

function TTyRichParaAttributes.GetSpaceAfter: Integer;
begin
  Result := TyRichTwipsToPt(GetFormat.SpaceAfter);
end;

procedure TTyRichParaAttributes.SetSpaceAfter(AValue: Integer);
var
  f: TTyParaFormat;
begin
  f := TyDefaultParaFormat;
  f.SpaceAfter := TyRichPtToTwips(AValue);
  SetFormat([pffSpaceAfter], f);
end;

function TTyRichParaAttributes.GetLineSpacingRule: TTyLineSpacing;
begin
  Result := GetFormat.LineSpacing;
end;

procedure TTyRichParaAttributes.SetLineSpacingRule(AValue: TTyLineSpacing);
var
  f, cur: TTyParaFormat;
begin
  cur := GetFormat;
  f := TyDefaultParaFormat;
  f.LineSpacing := AValue;
  // a height only means something for exactly and at least: kept from the first paragraph
  if AValue in [lsExact, lsAtLeast] then f.LineSpacingValue := cur.LineSpacingValue
  else f.LineSpacingValue := 0;
  SetFormat([pffLineSpacing], f);
end;

function TTyRichParaAttributes.GetLineSpacing: Integer;
var
  f: TTyParaFormat;
begin
  f := GetFormat;
  if f.LineSpacing in [lsExact, lsAtLeast] then Result := TyRichTwipsToPt(f.LineSpacingValue)
  else Result := 0;
end;

procedure TTyRichParaAttributes.SetLineSpacing(AValue: Integer);
var
  f, cur: TTyParaFormat;
begin
  cur := GetFormat;
  f := TyDefaultParaFormat;
  // a height given to a paragraph with a multiple: at least that height (Word's way)
  if cur.LineSpacing in [lsExact, lsAtLeast] then f.LineSpacing := cur.LineSpacing
  else f.LineSpacing := lsAtLeast;
  f.LineSpacingValue := TyRichPtToTwips(AValue);
  SetFormat([pffLineSpacing], f);
end;

procedure TTyRichParaAttributes.Assign(Source: TPersistent);
var
  f: TTyParaFormat;
begin
  if Source is TTyRichParaAttributes then
  begin
    f := TTyRichParaAttributes(Source).GetFormat;
    SetFormat([pffAlign, pffLeftIndent, pffRightIndent, pffFirstIndent, pffSpaceBefore,
      pffSpaceAfter, pffLineSpacing, pffTabs, pffList], f);
  end
  else
    inherited Assign(Source);
end;

{ ---- RichMemo's records ---- }

function TyRichFontParamsOf(const AFormat: TTyCharFormat): TTyFontParams;
begin
  Result := Default(TTyFontParams);
  Result.Name := AFormat.FontName;
  Result.Size := AFormat.SizeHalfPt div 2;
  Result.Color := AFormat.Color;
  Result.Style := AFormat.Style - [fsStrikeOut];
  if AFormat.Strike then Include(Result.Style, fsStrikeOut);
  Result.HasBkClr := AFormat.HighlightColor <> clNone;
  if Result.HasBkClr then Result.BkColor := AFormat.HighlightColor else Result.BkColor := clNone;
  case AFormat.VertAlign of
    vaSuper: Result.VScriptPos := vpSuperScript;
    vaSub: Result.VScriptPos := vpSubScript;
  else
    Result.VScriptPos := vpNormal;
  end;
end;

function TyRichCharFormatOf(const AParams: TTyFontParams): TTyCharFormat;
begin
  Result := TyDefaultCharFormat;
  Result.FontName := AParams.Name;
  Result.SizeHalfPt := Max(0, AParams.Size) * 2;
  Result.Color := AParams.Color;
  Result.Style := AParams.Style - [fsStrikeOut];
  Result.Strike := fsStrikeOut in AParams.Style;
  if AParams.HasBkClr then Result.HighlightColor := AParams.BkColor
  else Result.HighlightColor := clNone;
  case AParams.VScriptPos of
    vpSuperScript: Result.VertAlign := vaSuper;
    vpSubScript: Result.VertAlign := vaSub;
  else
    Result.VertAlign := vaNone;
  end;
end;

const
  CSpacingRules: array[lsSingle..lsDouble] of Double = (1.0, 1.15, 1.5, 2.0);

function TyRichMetricOf(const AFormat: TTyParaFormat): TTyParaMetric;
begin
  Result := Default(TTyParaMetric);
  Result.FirstLine := (AFormat.LeftIndent + AFormat.FirstIndent) / 20;
  Result.HeadIndent := AFormat.LeftIndent / 20;
  Result.TailIndent := AFormat.RightIndent / 20;
  Result.SpaceBefore := AFormat.SpaceBefore / 20;
  Result.SpaceAfter := AFormat.SpaceAfter / 20;
  if AFormat.LineSpacing in [lsSingle..lsDouble] then
    Result.LineSpacing := CSpacingRules[AFormat.LineSpacing]
  else
    Result.LineSpacing := 0;
end;

function TyRichParaFormatOfMetric(const AMetric: TTyParaMetric): TTyParaFormat;
var
  r, best: TTyLineSpacing;
begin
  Result := TyDefaultParaFormat;
  Result.LeftIndent := TyRichPtToTwips(AMetric.HeadIndent);
  Result.FirstIndent := TyRichPtToTwips(AMetric.FirstLine) - Result.LeftIndent;
  Result.RightIndent := TyRichPtToTwips(AMetric.TailIndent);
  Result.SpaceBefore := TyRichPtToTwips(AMetric.SpaceBefore);
  Result.SpaceAfter := TyRichPtToTwips(AMetric.SpaceAfter);
  // the nearest of the engine's multiples (0 or less: single)
  best := lsSingle;
  for r := lsSingle to lsDouble do
    if Abs(CSpacingRules[r] - AMetric.LineSpacing) < Abs(CSpacingRules[best] - AMetric.LineSpacing) then
      best := r;
  Result.LineSpacing := best;
end;

function TyRichNumberingOf(const AList: TTyListFormat): TTyParaNumbering;
begin
  Result := Default(TTyParaNumbering);
  case AList.Kind of
    lkBullet: Result.Style := pnBullet;
    lkDecimal: Result.Style := pnNumber;
    lkLowerAlpha: Result.Style := pnLowLetter;
    lkUpperAlpha: Result.Style := pnUpLetter;
    lkLowerRoman: Result.Style := pnLowRoman;
    lkUpperRoman: Result.Style := pnUpRoman;
  else
    Result.Style := pnNone;
  end;
  Result.NumberStart := AList.StartAt;
end;

function TyRichListOf(const ANumbering: TTyParaNumbering; const AOld: TTyListFormat): TTyListFormat;
begin
  Result := AOld;
  case ANumbering.Style of
    pnBullet, pnCustomChar: Result.Kind := lkBullet;
    pnNumber: Result.Kind := lkDecimal;
    pnLowLetter: Result.Kind := lkLowerAlpha;
    pnUpLetter: Result.Kind := lkUpperAlpha;
    pnLowRoman: Result.Kind := lkLowerRoman;
    pnUpRoman: Result.Kind := lkUpperRoman;
  else
    Result.Kind := lkNone;
  end;
  Result.StartAt := ANumbering.NumberStart;
  if (Result.Kind <> lkNone) and (Result.StartAt <= 0) then Result.StartAt := 1;
end;

function TyRichTabListOf(const ATabs: TTyTabStops): TTyTabStopList;
var
  i: Integer;
begin
  Result := Default(TTyTabStopList);
  Result.Count := Length(ATabs);
  SetLength(Result.Tabs, Result.Count);
  for i := 0 to Result.Count - 1 do
  begin
    Result.Tabs[i].Offset := ATabs[i].Position / 20;
    Result.Tabs[i].Align := ATabs[i].Align;
  end;
end;

function TyRichTabsOf(const AList: TTyTabStopList; const AOld: TTyTabStops): TTyTabStops;
var
  i, n: Integer;
begin
  n := Max(0, Min(AList.Count, Length(AList.Tabs)));
  Result := nil;
  SetLength(Result, n);
  for i := 0 to n - 1 do
  begin
    Result[i].Position := TyRichPtToTwips(AList.Tabs[i].Offset);
    Result[i].Align := AList.Tabs[i].Align;
    // a stop that was there keeps its leader (RichMemo's records have none)
    if i < Length(AOld) then Result[i].Leader := AOld[i].Leader else Result[i].Leader := ttlNone;
  end;
end;

end.
