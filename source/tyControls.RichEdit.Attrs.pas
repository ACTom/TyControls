unit tyControls.RichEdit.Attrs;

{ The format API of TTyRichEdit in Delphi's style: TTyRichTextAttributes
  - the SelAttributes and DefAttributes of Vcl.ComCtrls.TRichEdit - and TTyRichParaAttributes -
  its Paragraph -, and the records of the RichMemo style (TTyFontParams, TTyParaMetric, ...).
  Names and meanings are the originals' wherever the engine can mean the same; this control's
  richer values have names of their own beside them (ParaAlign, NumberingStart, SpaceBefore ..).
  They hold nothing: every read asks the control, every write is one command of the document
  run by the control (tyControls.RichEdit), so these classes only translate units and names.
  The control makes its own subclasses of them; an application never creates one.

  Units: sizes in points (the engine keeps half points); indents, spaces and tab positions in
  points as Delphi has them (the engine keeps twips: a read rounds to the nearest point, a
  write is exact); the RichMemo records in points as Doubles (exact both ways, 1/20 point). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, tyControls.RichEdit.Text, tyControls.RichEdit.Model;

type
  { Which attributes are the same over the whole selection: Delphi's TConsistentAttribute
    without the members the engine cannot answer (caProtected, caDisabled, caHidden, caLink,
    caOffset, caRevAuthor, caWeight - the engine holds none of them). The ordinals differ
    from Delphi's; the names mean the same. }
  TTyRichConsistentAttribute = (caBold, caColor, caFace, caItalic, caSize, caStrikeOut,
    caUnderline, caBackColor, caCharset, caSubscript);
  TTyRichConsistentAttributes = set of TTyRichConsistentAttribute;

  { Delphi's TSubscriptType. }
  TTySubscriptType = (sstNone, sstSubscript, sstSuperscript);

  { Delphi's TConsistentParaAttribute: which paragraph attributes are the same over every
    paragraph the selection touches. }
  TTyRichConsistentParaAttribute = (cpaAlignment, cpaNumbering, cpaFirstIndent, cpaLeftIndent,
    cpaRightIndent, cpaTabStops);
  TTyRichConsistentParaAttributes = set of TTyRichConsistentParaAttribute;

const
  { Delphi's TNumberingStyle values as the engine's list kinds: Paragraph.Numbering :=
    nsBullet compiles and means Delphi's, and the numbered kinds (lkDecimal ..) stay
    reachable through the same property. }
  nsNone = lkNone;
  nsBullet = lkBullet;
  { The hanging indent a paragraph that becomes a list item gets when it has no indent
    (WordPad's \fi-360\li720, as Windows' rich edit writes it), twips. }
  CTyListLeftIndent = 720;
  CTyListFirstIndent = -360;
  { A list written as the user's list button writes it: the list record and the indents that
    go with it (pffListIndents) - one rule with leaving a list by Enter or Backspace. }
  CTyListMask = [pffList, pffListIndents];
  { At most this many stops a TabCount write makes (Delphi's MAX_TAB_STOPS). }
  CTyMaxTabStops = 32;

type
  { A tab stop's alignment and leader for Paragraph.SetTab: the engine's own kinds under
    names of this control's layer. }
  TTyRichTabAlign = TTyTabAlign;
  TTyRichTabLeader = TTyTabLeader;

const
  rtaLeft = ttaLeft;
  rtaCenter = ttaCenter;
  rtaRight = ttaRight;
  rtaDecimal = ttaDecimal;
  rtlNone = ttlNone;
  rtlDot = ttlDot;
  rtlHyphen = ttlHyphen;
  rtlUnderline = ttlUnderline;
  rtlThick = ttlThick;
  rtlEqual = ttlEqual;

type
  { Delphi's TNumberingStyle as the same type as Numbering's: Delphi's classic cast
    Paragraph.Numbering := TNumberingStyle(BulletsButton.Down) compiles and gives nsNone /
    nsBullet. }
  TNumberingStyle = TTyListKind;

  { The character format of the selection (SelAttributes) or the control's base
    (DefAttributes) - see the control's properties for what each answers for. Reading a value
    of a selection whose characters differ gives the value of the first character a write
    would format (ConsistentAttributes says which differ). Each write changes that one
    attribute and leaves the others as each character has them: one command (one undo
    step), or - with nothing selected - the format the next typed text gets. Assign takes a
    TFont or another TTyRichTextAttributes (all of their attributes, one write); AssignTo
    fills a TFont. }
  TTyRichTextAttributes = class(TPersistent)
  protected
    { The format the reads answer with: FontName and SizeHalfPt resolved (never '' or 0). }
    function GetFormat: TTyCharFormat; virtual; abstract;
    { The format as the text has it: '' and 0 where it has no name or size of its own (what
      an Assign between two selections copies). GetFormat unless overridden. }
    function GetRawFormat: TTyCharFormat; virtual;
    { This is the base (DefAttributes): an assignment from it is "reset to default" - it
      writes the engine's "none of its own" for everything the base supplies; one to
      it takes the source's values as shown. }
    function IsBase: Boolean; virtual;
    { The fields an assignment writes here (the base has no highlight and no vertical
      position: an assignment leaves them out, only a direct write of them raises). }
    function AssignMask: TTyCharFormatMask; virtual;
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
    function GetSizeF: Double;
    procedure SetSizeF(AValue: Double);
    function GetHeight: Integer;
    procedure SetHeight(AValue: Integer);
    function GetStyle: TFontStyles;
    procedure SetStyle(AValue: TFontStyles);
    function GetStyleFlag(AIndex: Integer): Boolean;
    procedure SetStyleFlag(AIndex: Integer; AValue: Boolean);
    function GetColor: TColor;
    procedure SetColor(AValue: TColor);
    function GetCharset: TFontCharset;
    procedure SetCharset(AValue: TFontCharset);
    function GetBackColor: TColor;
    procedure SetBackColor(AValue: TColor);
    function GetSubscript: TTySubscriptType;
    procedure SetSubscript(AValue: TTySubscriptType);
    function GetConsistentAttributes: TTyRichConsistentAttributes;
  public
    procedure Assign(Source: TPersistent); override;
    { The font's name - read: the one the text is shown in (the base's for text without a
      name of its own); written: a name LCL takes for its default font ('default', '';
      IsFontNameDefault) is "none of its own" - the text follows the base; the name
      the base shows leaves the text that has none of its own without one (it shows it
      already), and is written to the rest. }
    property Name: TFontName read GetName write SetName;
    { Points (the engine's half points: a read of 10.5 pt says 10, as Delphi's) - read: the
      size the text is shown in; written 0: none of its own; written the base's size, text
      without a size of its own keeps none (as Name). }
    property Size: Integer read GetSize write SetSize;
    { Points to the half point, as the engine keeps them (10.5 reads 10.5; a write rounds to
      the nearest half point) - Size's meanings otherwise: 0 none of its own, the base's
      size leaves text without one of its own as it is. }
    property SizeF: Double read GetSizeF write SetSizeF;
    { Pixels at the control's PPI: Size * PPI / 72, as Delphi's; a negative height (a
      TFont's character height) is taken as its absolute value. }
    property Height: Integer read GetHeight write SetHeight;
    { Bold, italic, underline, strike-through (fsStrikeOut is the engine's Strike). A write
      sets all four. }
    property Style: TFontStyles read GetStyle write SetStyle;
    { Delphi's one-style properties: a write changes that one style and leaves the others as
      each character has them (what a toolbar's Bold button wants). }
    property Bold: Boolean index 0 read GetStyleFlag write SetStyleFlag;
    property Italic: Boolean index 1 read GetStyleFlag write SetStyleFlag;
    property Underline: Boolean index 2 read GetStyleFlag write SetStyleFlag;
    property Strikeout: Boolean index 3 read GetStyleFlag write SetStyleFlag;
    { The automatic colour - the base's, which follows the theme - reads clDefault (Delphi
      reads clWindowText); writing clDefault or clWindowText makes the text automatic again
      (Delphi's clWindowText), any other colour is the text's own. DefAttributes reads
      clDefault too unless the application gave it a colour of its own, so
      SelAttributes.Color = DefAttributes.Color holds for automatic text. }
    property Color: TColor read GetColor write SetColor;
    property Charset: TFontCharset read GetCharset write SetCharset;
    { The text's highlight: none reads clNone (Delphi reads clWindow); writing clNone,
      clDefault or clWindow (Delphi's way) takes it away. }
    property BackColor: TColor read GetBackColor write SetBackColor;
    { Delphi's Subscript: superscript, subscript or neither. }
    property Subscript: TTySubscriptType read GetSubscript write SetSubscript;
    { The attributes that are the same over the whole selection (everything for an empty
      selection; DefAttributes: none, as Delphi's). Remembered for the selection and the
      content (a repeated read is free) and BOUNDED: the walk reads at most the control's
      budget (CRichConsistWork runs - a paragraph at least one - and CRichConsistParseBytes
      bytes of a lazily read file not parsed yet, about 30 ms); over a larger selection the answer is a lower bound -
      every attribute not proven the same within the budget is reported as not consistent
      ("mixed", the safe answer for a toolbar). }
    property ConsistentAttributes: TTyRichConsistentAttributes read GetConsistentAttributes;
  end;

  { The paragraph format of the paragraphs the selection touches (Delphi's Paragraph): reads
    answer for the first of them, each write is one command over all of them (the caret's
    paragraph when nothing is selected; a selection that ends at a paragraph's very start
    does not touch that paragraph) that changes the one attribute written and leaves the
    others as each paragraph has them. Units: points. }
  TTyRichParaAttributes = class(TPersistent)
  protected
    function GetFormat: TTyParaFormat; virtual; abstract;
    procedure SetFormat(AMask: TTyParaFormatMask; const AValue: TTyParaFormat); virtual; abstract;
    function GetConsistentPara: TTyRichConsistentParaAttributes; virtual; abstract;
  private
    function GetAlignment: TAlignment;
    procedure SetAlignment(AValue: TAlignment);
    function GetParaAlign: TTyParaAlign;
    procedure SetParaAlign(AValue: TTyParaAlign);
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
    procedure SetTab(AIndex: Byte; AValue: Integer); overload;
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
    function GetConsistentAttributes: TTyRichConsistentParaAttributes;
    function GetListLevel: Integer;
    procedure SetListLevel(AValue: Integer);
    function GetBulletText: string;
    procedure SetBulletText(const AValue: string);
    function GetShading: TColor;
    procedure SetShading(AValue: TColor);
    function GetLineSpacingMultiple: Double;
    procedure SetLineSpacingMultiple(AValue: Double);
  public
    procedure Assign(Source: TPersistent); override;
    { Tab stop AIndex (0-based) at APosPt points from the left indent's origin, aligned
      AAlign, its leader ALeader - one write (Tab's rules for an index past the count, and
      for one of CTyMaxTabStops or more: ignored). }
    procedure SetTab(AIndex: Integer; APosPt: Double; AAlign: TTyRichTabAlign;
      ALeader: TTyRichTabLeader); overload;
    { The list item's level, 0 the outermost (the other parts of each paragraph's list as
      they are; a paragraph that is no item keeps none). }
    property ListLevel: Integer read GetListLevel write SetListLevel;
    { The number the list starts at: NumberingStart. }
    property ListStart: Integer read GetNumberingStart write SetNumberingStart;
    { A bullet's own text in place of the round bullet - written, it makes each paragraph a
      bullet item (the default hanging indent for one with none, as Numbering); '' the round
      bullet again. }
    property BulletText: string read GetBulletText write SetBulletText;
    { The paragraph's ground, a colour of the document's (the theme does not change it):
      clNone none (clDefault and clWindow written mean none too). }
    property Shading: TColor read GetShading write SetShading;
    { The lines' height as a multiple of their own (1, 1.15, 1.5, 2 or any other, to a 240th);
      0 when the spacing is exactly or at least a height (LineSpacing). A write sets the rule
      to that multiple; 0 or less is single. }
    property LineSpacingMultiple: Double read GetLineSpacingMultiple write SetLineSpacingMultiple;
    { Delphi's TAlignment (taLeftJustify, taRightJustify, taCenter); a justified paragraph
      reads taLeftJustify here - ParaAlign has all four. }
    property Alignment: TAlignment read GetAlignment write SetAlignment;
    { The engine's four alignments: paraLeft, paraCenter, paraRight, paraJustify. }
    property ParaAlign: TTyParaAlign read GetParaAlign write SetParaAlign;
    { As Delphi's: FirstIndent is where the first line starts, from the left margin
      (dxStartIndent); LeftIndent is where the other lines start, from the first line's start
      (dxOffset; negative: they start left of it); RightIndent from the right margin. Points.
      In the engine's terms (\li the other lines, \fi the first line's offset from them):
      FirstIndent = li + fi, LeftIndent = -fi. A write moves its one meaning per paragraph and
      keeps the other: FirstIndent moves each whole paragraph, each keeping its own offset
      (pffStartIndent); LeftIndent moves the other lines, each first line staying where it
      is (pffOffset). }
    property FirstIndent: Integer read GetFirstIndent write SetFirstIndent;
    property LeftIndent: Integer read GetLeftIndent write SetLeftIndent;
    property RightIndent: Integer read GetRightIndent write SetRightIndent;
    { nsNone / nsBullet as Delphi's, or one of the numbered kinds (lkDecimal ..). Turning a
      list on gives each paragraph that has no indent the default hanging indent (WordPad's
      \fi-360\li720; Delphi: at least 10 pt of offset); turning it off takes its indents
      back to 0 and the list record to its default, so a plain paragraph is plain again -
      the rule Enter and Backspace on an empty item follow (CTyListMask). }
    property Numbering: TTyListKind read GetNumbering write SetNumbering;
    { The number the list starts at. }
    property NumberingStart: Integer read GetNumberingStart write SetNumberingStart;
    { Tab stop AIndex (0-based), points from the left indent's origin. A read past the count
      gives 0 (as Delphi's); a write past the last adds left-aligned stops at 0 up to it, so
      the stop written counts (Delphi's sets the count to AIndex: the stop written counts
      only once TabCount is raised); an index of CTyMaxTabStops or more is ignored (Delphi's
      record has 32 stops). TabCount := N sets the count as Delphi's: a larger count
      appends stops at 0, to be set next (at most CTyMaxTabStops); a smaller one removes the
      last. The stops stay as written in the paragraph's format; where they are used they
      are taken in order of position: the layout takes the first stop right of the pen (a
      stop at 0 or left of the margin only serves a first line that starts left of it, with
      a negative indent), and a file written gets every stop but one at exactly 0 (the
      TabCount placeholder). }
    property Tab[AIndex: Byte]: Integer read GetTab write SetTab;
    property TabCount: Integer read GetTabCount write SetTabCount;
    property SpaceBefore: Integer read GetSpaceBefore write SetSpaceBefore;
    property SpaceAfter: Integer read GetSpaceAfter write SetSpaceAfter;
    { The rule (single, 1.15, 1.5, double, exactly, at least, another multiple - its number:
      LineSpacingMultiple) and, for exactly and at least, the line's height in points
      (LineSpacing; 0 for the other rules). The rule lsMultiple written keeps a paragraph's
      own multiple (single's 1 for one with a height). }
    property LineSpacingRule: TTyLineSpacing read GetLineSpacingRule write SetLineSpacingRule;
    property LineSpacing: Integer read GetLineSpacing write SetLineSpacing;
    { Delphi's: the attributes every paragraph the selection touches shares (alignment as
      ParaAlign, numbering, first and left indent, right indent, tab stops). Remembered and
      bounded as SelAttributes.ConsistentAttributes is (a lower bound over a selection larger
      than the budget). }
    property ConsistentAttributes: TTyRichConsistentParaAttributes read GetConsistentAttributes;
  end;

  { ---- RichMemo's records (TFontParams, TParaMetric, ...), in points; type names prefixed,
    member names RichMemo's ---- }

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

  { RichMemo's TParaAlignment, its order. }
  TTyParaAlignment = (paLeft, paRight, paCenter, paJustify);

  { Delphi's TSearchType (TCustomRichEdit.FindText), its names and order. }
  TTySearchType = (stWholeWord, stMatchCase);
  TTySearchTypes = set of TTySearchType;

  { RichMemo's TSearchOption (TCustomRichMemo.Search), its names and order. FPC's StrUtils has
    a TStringSearchOption with soMatchCase and soWholeWord too: in a unit that uses both, the
    unit used last decides what a bare soMatchCase means - qualify the name there. }
  TTySearchOption = (soMatchCase, soWholeWord, soBackward);
  TTySearchOptions = set of TTySearchOption;

  { RichMemo's TParaMetric, points: FirstLine where the first line starts, HeadIndent where
    the other lines start (both from the left margin), TailIndent from the right margin;
    LineSpacing RichMemo's multiplier, on its scale: SingleLineSpacing (DefLineSpacing, 1.2)
    is single, OneHalfLineSpacing 1.8, DoubleLineSpacing 2.4 (the engine's 1.15 reads 1.38).
    A write takes the nearest of the engine's four named multiples (any other multiple is
    Paragraph.LineSpacingMultiple's); 0 or less leaves the
    paragraphs' spacing as it is. An exact or at-least spacing reads 0 - so that GetParaMetric,
    one field changed, SetParaMetric leaves it as it was. }
  TTyParaMetric = record
    FirstLine: Double;
    TailIndent: Double;
    HeadIndent: Double;
    SpaceBefore: Double;
    SpaceAfter: Double;
    LineSpacing: Double;
  end;

  TTyParaModifyMaskItem = (pmm_FirstLine, pmm_HeadIndent, pmm_TailIndent, pmm_SpaceBefore,
    pmm_SpaceAfter, pmm_LineSpacing);
  TTyParaModifyMask = set of TTyParaModifyMaskItem;

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

  { RichMemo's TTabAlignment; the engine has no bar tab: tabWordBar is written as a left
    stop. }
  TTyTabAlignment = (tabLeft, tabCenter, tabRight, tabDecimal, tabWordBar);

  { RichMemo's TTabStop (the name TTyTabStop is the engine's). }
  TTyRichTabStop = record
    Offset: Double;          // points from the left indent's origin
    Align: TTyTabAlignment;
  end;

  TTyTabStopList = record
    Count: Integer;
    Tabs: array of TTyRichTabStop;
  end;

  { RichMemo's TParaRange, in this control's positions: the paragraph's first character, its
    length without its separator and with it (the last paragraph has none: equal). }
  TTyParaRange = record
    start: TTyRichPos;
    lengthNoBr: TTyRichPos;
    length: TTyRichPos;
  end;

const
  { RichMemo's line spacing scale. }
  DefLineSpacing = Double(1.2);
  SingleLineSpacing = DefLineSpacing;
  OneHalfLineSpacing = Double(1.8);
  DoubleLineSpacing = Double(2.4);

  CTyCharStyleMask = [cffBold, cffItalic, cffUnderline, cffStrike];
  { What RichMemo's SetTextAttributes and an Assign from a TFont write. }
  CTyFontParamsMask = [cffFontName, cffSize, cffBold, cffItalic, cffUnderline, cffStrike,
    cffColor, cffHighlight, cffVertAlign];
  CTyFontMask = [cffFontName, cffSize, cffBold, cffItalic, cffUnderline, cffStrike, cffColor,
    cffCharset];

{ RichMemo's Init routines: the record zeroed (InitParaMetric: LineSpacing DefLineSpacing). }
procedure InitFontParams(out AParams: TTyFontParams);
procedure InitParaMetric(out AMetric: TTyParaMetric);
procedure InitParaNumbering(out ANumbering: TTyParaNumbering);
procedure InitTabStopList(out AList: TTyTabStopList);

{ Points and twips (the engine's unit for indents, spaces and tabs). }
function TyRichPtToTwips(APoints: Double): Integer;
function TyRichTwipsToPt(ATwips: Integer): Integer;
{ The fields of the two formats that differ (Style flag by flag; Strike and fsStrikeOut as
  one). }
function TyRichCharDiff(const A, B: TTyCharFormat): TTyCharFormatMask;
function TyRichConsistentOf(AMask: TTyCharFormatMask): TTyRichConsistentAttributes;
{ Delphi's paragraph attributes in which A and B differ. }
function TyRichParaDiff(const A, B: TTyParaFormat): TTyRichConsistentParaAttributes;
{ The colours and names Delphi's and LCL's "default" idioms use, as the engine's "none of its
  own": clWindowText and clDefault are the automatic text colour (clDefault);
  clWindow, clDefault and clNone no highlight (clNone); a name IsFontNameDefault holds for
  is no name (''). }
function TyRichTextColorIn(AColor: TColor): TColor;
function TyRichBackColorIn(AColor: TColor): TColor;
function TyRichFontNameIn(const AName: string): string;
{ Alignment between the engine, Delphi (a justified paragraph is taLeftJustify) and
  RichMemo. }
function TyRichAlignmentOf(AAlign: TTyParaAlign): TAlignment;
function TyRichParaAlignOfAlignment(AAlign: TAlignment): TTyParaAlign;
function TyRichParaAlignmentOf(AAlign: TTyParaAlign): TTyParaAlignment;
function TyRichParaAlignOf(AAlign: TTyParaAlignment): TTyParaAlign;
{ RichMemo's records to and from the engine's formats. }
function TyRichFontParamsOf(const AFormat: TTyCharFormat): TTyFontParams;
function TyRichCharFormatOf(const AParams: TTyFontParams): TTyCharFormat;
{ A TFont's name, size, styles, colour and charset (Delphi's and RichMemo's Assign / TFont
  overloads), the default idioms translated (TyRichFontNameIn, TyRichTextColorIn). }
function TyRichCharFormatOfFont(AFont: TFont): TTyCharFormat;
function TyRichMetricOf(const AFormat: TTyParaFormat): TTyParaMetric;
{ AMetric in the engine's terms (LeftIndent the head indent, FirstIndent the first line's
  offset from it), and the fields AModify names as TyMergeParaFormat's mask: FirstLine and
  HeadIndent each alone move that one per paragraph (pffFirstLine, pffHeadIndent); a line
  spacing of 0 or less is left out. }
function TyRichParaFormatOfMetric(const AMetric: TTyParaMetric): TTyParaFormat;
function TyRichMetricMask(AModify: TTyParaModifyMask; const AMetric: TTyParaMetric): TTyParaFormatMask;
function TyRichNumberingOf(const AList: TTyListFormat): TTyParaNumbering;
function TyRichListOf(const ANumbering: TTyParaNumbering; const AOld: TTyListFormat): TTyListFormat;
{ A paragraph format value for CTyListMask: AList and the default hanging indent. }
function TyRichListValue(const AList: TTyListFormat): TTyParaFormat;
function TyRichTabListOf(const ATabs: TTyTabStops): TTyTabStopList;
function TyRichTabsOf(const AList: TTyTabStopList; const AOld: TTyTabStops): TTyTabStops;

implementation

uses
  Math, LCLProc;

procedure InitFontParams(out AParams: TTyFontParams);
begin
  AParams := Default(TTyFontParams);
end;

procedure InitParaMetric(out AMetric: TTyParaMetric);
begin
  AMetric := Default(TTyParaMetric);
  AMetric.LineSpacing := DefLineSpacing;
end;

procedure InitParaNumbering(out ANumbering: TTyParaNumbering);
begin
  ANumbering := Default(TTyParaNumbering);
end;

procedure InitTabStopList(out AList: TTyTabStopList);
begin
  AList := Default(TTyTabStopList);
end;

function TyRichTextColorIn(AColor: TColor): TColor;
begin
  if (AColor = clWindowText) or (AColor = clDefault) then Result := clDefault
  else Result := AColor;
end;

function TyRichBackColorIn(AColor: TColor): TColor;
begin
  if (AColor = clWindow) or (AColor = clDefault) or (AColor = clNone) then Result := clNone
  else Result := AColor;
end;

function TyRichFontNameIn(const AName: string): string;
begin
  if IsFontNameDefault(AName) then Result := '' else Result := AName;
end;

function TyRichAlignmentOf(AAlign: TTyParaAlign): TAlignment;
begin
  case AAlign of
    paraCenter: Result := taCenter;
    paraRight: Result := taRightJustify;
  else
    Result := taLeftJustify;
  end;
end;

function TyRichParaAlignOfAlignment(AAlign: TAlignment): TTyParaAlign;
begin
  case AAlign of
    taCenter: Result := paraCenter;
    taRightJustify: Result := paraRight;
  else
    Result := paraLeft;
  end;
end;

function TyRichParaAlignmentOf(AAlign: TTyParaAlign): TTyParaAlignment;
begin
  case AAlign of
    paraCenter: Result := paCenter;
    paraRight: Result := paRight;
    paraJustify: Result := paJustify;
  else
    Result := paLeft;
  end;
end;

function TyRichParaAlignOf(AAlign: TTyParaAlignment): TTyParaAlign;
begin
  case AAlign of
    paCenter: Result := paraCenter;
    paRight: Result := paraRight;
    paJustify: Result := paraJustify;
  else
    Result := paraLeft;
  end;
end;

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
  if cffVertAlign in AMask then Include(Result, caSubscript);
end;

function SameTabs(const A, B: TTyTabStops): Boolean;
var
  i: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
    for i := 0 to High(A) do
      if (A[i].Position <> B[i].Position) or (A[i].Align <> B[i].Align) or
        (A[i].Leader <> B[i].Leader) then Exit(False);
end;

function TyRichParaDiff(const A, B: TTyParaFormat): TTyRichConsistentParaAttributes;
begin
  Result := [];
  if A.Align <> B.Align then Include(Result, cpaAlignment);
  if (A.List.Kind <> B.List.Kind) or ((A.List.Kind <> lkNone) and
    (A.List.StartAt <> B.List.StartAt)) then Include(Result, cpaNumbering);
  if A.LeftIndent + A.FirstIndent <> B.LeftIndent + B.FirstIndent then
    Include(Result, cpaFirstIndent);
  if A.FirstIndent <> B.FirstIndent then Include(Result, cpaLeftIndent);
  if A.RightIndent <> B.RightIndent then Include(Result, cpaRightIndent);
  if not SameTabs(A.Tabs, B.Tabs) then Include(Result, cpaTabStops);
end;

{ ---- TTyRichTextAttributes ---- }

function TTyRichTextAttributes.GetRawFormat: TTyCharFormat;
begin
  Result := GetFormat;
end;

function TTyRichTextAttributes.IsBase: Boolean;
begin
  Result := False;
end;

function TTyRichTextAttributes.AssignMask: TTyCharFormatMask;
begin
  Result := CTyFontMask + [cffHighlight, cffVertAlign];
end;

function TTyRichTextAttributes.GetName: TFontName;
begin
  Result := GetFormat.FontName;
end;

procedure TTyRichTextAttributes.SetName(const AValue: TFontName);
var
  f: TTyCharFormat;
begin
  { Written back as read (a toolbar echoing OnSelectionChange) over text without a name of
    its own, the base's name is not frozen into it: the control's write leaves such text
    without one wherever the name written is the one it shows (run by run). }
  f := TyDefaultCharFormat;
  f.FontName := TyRichFontNameIn(AValue);
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
  { Name and Size read what the text is shown in: written back unchanged (a toolbar echoing
    OnSelectionChange) they would freeze the base's value into text that has none of its
    own. The control's write leaves such text without one wherever the size written is the
    one it shows - run by run, over any selection; text whose own size differs takes
    it, and a selection where nothing is left to change is no step. }
  f.SizeHalfPt := AValue * 2;
  SetFormat([cffSize], f);
end;

function TTyRichTextAttributes.GetSizeF: Double;
begin
  Result := GetFormat.SizeHalfPt / 2;
end;

procedure TTyRichTextAttributes.SetSizeF(AValue: Double);
var
  f: TTyCharFormat;
begin
  f := TyDefaultCharFormat;
  if AValue < 0 then AValue := 0;
  // Word's largest size (and the largest an Integer of half points cannot overflow from)
  if AValue > 1638 then AValue := 1638;
  // half points, as Size's whole ones (its KeepNone rule is the control's write)
  f.SizeHalfPt := Round(AValue * 2);
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
  // a TFont's Height is negative for a character height: the same size either way
  AValue := Abs(AValue);
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

const
  CFlagStyles: array[0..3] of TFontStyle = (fsBold, fsItalic, fsUnderline, fsStrikeOut);
  CFlagFields: array[0..3] of TTyCharFormatField = (cffBold, cffItalic, cffUnderline, cffStrike);

function TTyRichTextAttributes.GetStyleFlag(AIndex: Integer): Boolean;
begin
  Result := CFlagStyles[AIndex] in GetStyle;
end;

procedure TTyRichTextAttributes.SetStyleFlag(AIndex: Integer; AValue: Boolean);
var
  f: TTyCharFormat;
begin
  f := TyDefaultCharFormat;
  if AValue then
    if CFlagStyles[AIndex] = fsStrikeOut then f.Strike := True
    else Include(f.Style, CFlagStyles[AIndex]);
  SetFormat([CFlagFields[AIndex]], f);
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
  f.Color := TyRichTextColorIn(AValue);
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
  f.HighlightColor := TyRichBackColorIn(AValue);
  SetFormat([cffHighlight], f);
end;

function TTyRichTextAttributes.GetSubscript: TTySubscriptType;
begin
  case GetFormat.VertAlign of
    vaSuper: Result := sstSuperscript;
    vaSub: Result := sstSubscript;
  else
    Result := sstNone;
  end;
end;

procedure TTyRichTextAttributes.SetSubscript(AValue: TTySubscriptType);
var
  f: TTyCharFormat;
begin
  f := TyDefaultCharFormat;
  case AValue of
    sstSuperscript: f.VertAlign := vaSuper;
    sstSubscript: f.VertAlign := vaSub;
  else
    f.VertAlign := vaNone;
  end;
  SetFormat([cffVertAlign], f);
end;

function TTyRichTextAttributes.GetConsistentAttributes: TTyRichConsistentAttributes;
begin
  Result := TyRichConsistentOf(GetConsistent);
end;

procedure TTyRichTextAttributes.Assign(Source: TPersistent);
var
  f: TTyCharFormat;
  src: TTyRichTextAttributes;
begin
  if Source is TFont then
    SetFormat(CTyFontMask * AssignMask, TyRichCharFormatOfFont(TFont(Source)))
  else if Source is TTyRichTextAttributes then
  begin
    src := TTyRichTextAttributes(Source);
    if src = Self then Exit;
    if IsBase then
      // the base takes what the source shows
      f := src.GetFormat
    else if src.IsBase then
    begin
      { Delphi's "reset to default": none of its own for everything the base supplies -
        name, size, styles, colour, highlight, position; the text follows the base and the
        theme again, nothing of them is frozen into it. }
      SetFormat(AssignMask - [cffCharset], TyDefaultCharFormat);
      Exit;
    end
    else
      // between selections: as the text has it (no name or size of its own stays none)
      f := src.GetRawFormat;
    SetFormat(AssignMask, f);
  end
  else
    inherited Assign(Source);
end;

procedure TTyRichTextAttributes.AssignTo(Dest: TPersistent);
var
  destFont: TFont;
begin
  if Dest is TFont then
  begin
    // the application's TFont (a font dialog's): its values, nothing measured with it
    destFont := TFont(Dest);
    destFont.Name := Name;
    destFont.Size := Size;
    destFont.Style := Style;
    destFont.Color := Color;
    destFont.CharSet := Charset;
  end
  else
    inherited AssignTo(Dest);
end;

{ ---- TTyRichParaAttributes ---- }

function TTyRichParaAttributes.GetAlignment: TAlignment;
begin
  Result := TyRichAlignmentOf(GetFormat.Align);
end;

procedure TTyRichParaAttributes.SetAlignment(AValue: TAlignment);
begin
  SetParaAlign(TyRichParaAlignOfAlignment(AValue));
end;

function TTyRichParaAttributes.GetParaAlign: TTyParaAlign;
begin
  Result := GetFormat.Align;
end;

procedure TTyRichParaAttributes.SetParaAlign(AValue: TTyParaAlign);
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
  f: TTyParaFormat;
begin
  // each paragraph's first line at AValue, its other lines keeping their offset from it
  f := TyDefaultParaFormat;
  f.LeftIndent := TyRichPtToTwips(AValue);
  f.FirstIndent := 0;
  SetFormat([pffStartIndent], f);
end;

function TTyRichParaAttributes.GetLeftIndent: Integer;
begin
  Result := TyRichTwipsToPt(-GetFormat.FirstIndent);
end;

procedure TTyRichParaAttributes.SetLeftIndent(AValue: Integer);
var
  f: TTyParaFormat;
begin
  // each paragraph's other lines AValue from its first line, which stays where it is
  f := TyDefaultParaFormat;
  f.FirstIndent := -TyRichPtToTwips(AValue);
  SetFormat([pffOffset], f);
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

function TyRichListValue(const AList: TTyListFormat): TTyParaFormat;
begin
  Result := TyDefaultParaFormat;
  Result.List := AList;
  Result.LeftIndent := CTyListLeftIndent;
  Result.FirstIndent := CTyListFirstIndent;
end;

procedure TTyRichParaAttributes.SetNumbering(AValue: TTyListKind);
var
  l: TTyListFormat;
begin
  { The kind only: each paragraph keeps its own start; lkNone takes the
    list record back to its default - a paragraph that was plain is plain again. }
  l := TyDefaultParaFormat.List;
  l.Kind := AValue;
  SetFormat([pffListKind, pffListIndents], TyRichListValue(l));
end;

function TTyRichParaAttributes.GetNumberingStart: Integer;
begin
  Result := GetFormat.List.StartAt;
end;

procedure TTyRichParaAttributes.SetNumberingStart(AValue: Integer);
var
  f: TTyParaFormat;
begin
  // the start only: a plain paragraph stays plain, an item keeps its kind
  f := TyDefaultParaFormat;
  f.List.StartAt := AValue;
  SetFormat([pffListStart], f);
end;

function TTyRichParaAttributes.GetTab(AIndex: Byte): Integer;
var
  f: TTyParaFormat;
begin
  f := GetFormat;
  // past the count: 0, as Delphi's (its Assign reads all 32)
  if AIndex >= Length(f.Tabs) then Exit(0);
  Result := TyRichTwipsToPt(f.Tabs[AIndex].Position);
end;

procedure TTyRichParaAttributes.SetTab(AIndex: Byte; AValue: Integer);
var
  f: TTyParaFormat;
  i, n: Integer;
begin
  { At or past Delphi's MAX_TAB_STOPS: ignored. The VCL checks nothing - its record holds 32
    stops and a larger index writes past them, with no error raised (range checks off) -
    and the system's rich edit keeps at most 32. }
  if AIndex >= CTyMaxTabStops then Exit;
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
  i, n: Integer;
begin
  f := TyDefaultParaFormat;
  f.Tabs := Copy(GetFormat.Tabs);
  n := Length(f.Tabs);
  if AValue < 0 then AValue := 0;
  // more: stops at 0, to be set next (Delphi's idiom: TabCount := N, then Tab[0..N-1])
  if AValue > n then AValue := Min(AValue, Max(n, CTyMaxTabStops));
  SetLength(f.Tabs, AValue);
  for i := n to AValue - 1 do
  begin
    f.Tabs[i].Position := 0;
    f.Tabs[i].Align := ttaLeft;
    f.Tabs[i].Leader := ttlNone;
  end;
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
  { The rule only: a height (exactly, at least) stays each paragraph's own; one without a
    height takes the first paragraph's. }
  if AValue in [lsExact, lsAtLeast] then f.LineSpacingValue := cur.LineSpacingValue
  else if AValue = lsMultiple then
  begin
    // the first paragraph's multiple (single for a height), named when it has a name
    if TyRichLineMultiple(cur) > 0 then TyRichSetLineMultiple(f, TyRichLineMultiple(cur))
    else TyRichSetLineMultiple(f, 1);
  end
  else f.LineSpacingValue := 0;
  SetFormat([pffSpacingRule], f);
end;

function TTyRichParaAttributes.GetLineSpacingMultiple: Double;
begin
  Result := TyRichLineMultiple(GetFormat);
end;

procedure TTyRichParaAttributes.SetLineSpacingMultiple(AValue: Double);
var
  f: TTyParaFormat;
begin
  f := TyDefaultParaFormat;
  TyRichSetLineMultiple(f, AValue);
  SetFormat([pffSpacingRule], f);
end;

function TTyRichParaAttributes.GetListLevel: Integer;
begin
  Result := GetFormat.List.Level;
end;

procedure TTyRichParaAttributes.SetListLevel(AValue: Integer);
var
  f: TTyParaFormat;
begin
  f := TyDefaultParaFormat;
  f.List.Level := AValue;
  SetFormat([pffListLevel], f);
end;

function TTyRichParaAttributes.GetBulletText: string;
begin
  Result := GetFormat.List.Bullet;
end;

procedure TTyRichParaAttributes.SetBulletText(const AValue: string);
var
  l: TTyListFormat;
begin
  if AValue = '' then
  begin
    // the round bullet again: the kind and the rest as they are
    l := TyDefaultParaFormat.List;
    SetFormat([pffListBullet], TyRichListValue(l));
    Exit;
  end;
  l := TyDefaultParaFormat.List;
  l.Kind := lkBullet;
  l.Bullet := AValue;
  SetFormat([pffListKind, pffListBullet, pffListIndents], TyRichListValue(l));
end;

function TTyRichParaAttributes.GetShading: TColor;
begin
  Result := GetFormat.Shading;
end;

procedure TTyRichParaAttributes.SetShading(AValue: TColor);
var
  f: TTyParaFormat;
begin
  f := TyDefaultParaFormat;
  f.Shading := TyRichBackColorIn(AValue);
  SetFormat([pffShading], f);
end;

procedure TTyRichParaAttributes.SetTab(AIndex: Integer; APosPt: Double;
  AAlign: TTyRichTabAlign; ALeader: TTyRichTabLeader);
var
  f: TTyParaFormat;
  i, n: Integer;
begin
  // Tab's rules: at or past Delphi's MAX_TAB_STOPS (or below 0) ignored
  if (AIndex < 0) or (AIndex >= CTyMaxTabStops) then Exit;
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
  f.Tabs[AIndex].Position := TyRichPtToTwips(APosPt);
  f.Tabs[AIndex].Align := AAlign;
  f.Tabs[AIndex].Leader := ALeader;
  SetFormat([pffTabs], f);
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
  f: TTyParaFormat;
begin
  { The height only, each paragraph keeping its rule where it is exactly or at least; one
    with a multiple gets at least that height (Word's way) - per paragraph. }
  f := TyDefaultParaFormat;
  f.LineSpacingValue := TyRichPtToTwips(AValue);
  SetFormat([pffSpacingHeight], f);
end;

function TTyRichParaAttributes.GetConsistentAttributes: TTyRichConsistentParaAttributes;
begin
  Result := GetConsistentPara;
end;

procedure TTyRichParaAttributes.Assign(Source: TPersistent);
var
  f: TTyParaFormat;
begin
  if Source is TTyRichParaAttributes then
  begin
    f := TTyRichParaAttributes(Source).GetFormat;
    SetFormat([pffAlign, pffLeftIndent, pffRightIndent, pffFirstIndent, pffSpaceBefore,
      pffSpaceAfter, pffLineSpacing, pffTabs, pffList, pffShading], f);
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
  Result.FontName := TyRichFontNameIn(AParams.Name);
  Result.SizeHalfPt := Max(0, AParams.Size) * 2;
  Result.Color := TyRichTextColorIn(AParams.Color);
  Result.Style := AParams.Style - [fsStrikeOut];
  Result.Strike := fsStrikeOut in AParams.Style;
  if AParams.HasBkClr then Result.HighlightColor := TyRichBackColorIn(AParams.BkColor)
  else Result.HighlightColor := clNone;
  case AParams.VScriptPos of
    vpSuperScript: Result.VertAlign := vaSuper;
    vpSubScript: Result.VertAlign := vaSub;
  else
    Result.VertAlign := vaNone;
  end;
end;

function TyRichCharFormatOfFont(AFont: TFont): TTyCharFormat;
begin
  Result := TyDefaultCharFormat;
  Result.FontName := TyRichFontNameIn(AFont.Name);
  Result.SizeHalfPt := Max(0, AFont.Size) * 2;
  Result.Style := AFont.Style - [fsStrikeOut];
  Result.Strike := fsStrikeOut in AFont.Style;
  Result.Color := TyRichTextColorIn(AFont.Color);
  Result.Charset := AFont.CharSet;
end;

const
  { The engine's multiples on RichMemo's scale (single is DefLineSpacing). }
  CSpacingRules: array[lsSingle..lsDouble] of Double = (1.2, 1.38, 1.8, 2.4);

function TyRichMetricOf(const AFormat: TTyParaFormat): TTyParaMetric;
begin
  Result := Default(TTyParaMetric);
  Result.FirstLine := (AFormat.LeftIndent + AFormat.FirstIndent) / 20;
  Result.HeadIndent := AFormat.LeftIndent / 20;
  Result.TailIndent := AFormat.RightIndent / 20;
  Result.SpaceBefore := AFormat.SpaceBefore / 20;
  Result.SpaceAfter := AFormat.SpaceAfter / 20;
  // exactly / at least: 0, which written back leaves the spacing as it is
  if AFormat.LineSpacing in [lsSingle..lsDouble] then
    Result.LineSpacing := CSpacingRules[AFormat.LineSpacing]
  else if AFormat.LineSpacing = lsMultiple then
    Result.LineSpacing := DefLineSpacing * TyRichLineMultiple(AFormat)
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
  // the nearest of the engine's multiples on RichMemo's scale
  best := lsSingle;
  for r := lsSingle to lsDouble do
    if Abs(CSpacingRules[r] - AMetric.LineSpacing) < Abs(CSpacingRules[best] - AMetric.LineSpacing) then
      best := r;
  Result.LineSpacing := best;
end;

function TyRichMetricMask(AModify: TTyParaModifyMask; const AMetric: TTyParaMetric): TTyParaFormatMask;
begin
  Result := [];
  if pmm_FirstLine in AModify then Include(Result, pffFirstLine);
  if pmm_HeadIndent in AModify then Include(Result, pffHeadIndent);
  if pmm_TailIndent in AModify then Include(Result, pffRightIndent);
  if pmm_SpaceBefore in AModify then Include(Result, pffSpaceBefore);
  if pmm_SpaceAfter in AModify then Include(Result, pffSpaceAfter);
  if (pmm_LineSpacing in AModify) and (AMetric.LineSpacing > 0) then
    Include(Result, pffLineSpacing);
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
  if Result.Kind = lkNone then Exit(TyDefaultParaFormat.List);
  Result.StartAt := ANumbering.NumberStart;
  if Result.StartAt <= 0 then Result.StartAt := 1;
end;

const
  CTabAligns: array[TTyTabAlign] of TTyTabAlignment = (tabLeft, tabCenter, tabRight, tabDecimal);
  CTabAlignsBack: array[TTyTabAlignment] of TTyTabAlign = (ttaLeft, ttaCenter, ttaRight,
    ttaDecimal, ttaLeft);

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
    Result.Tabs[i].Align := CTabAligns[ATabs[i].Align];
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
    Result[i].Align := CTabAlignsBack[AList.Tabs[i].Align];
    // a stop that was there keeps its leader (RichMemo's records have none)
    if i < Length(AOld) then Result[i].Leader := AOld[i].Leader else Result[i].Leader := ttlNone;
  end;
end;

end.
