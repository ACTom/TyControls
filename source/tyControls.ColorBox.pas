unit tyControls.ColorBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Controls, LCLType, LCLStrConsts,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.ListBox, tyControls.ComboBox;

type
  { WHICH colours a colour control's palette is made of. Mirrors LCL's
    TColorBoxStyles / TColorBoxStyle (colorbox.pas:35-43) member for member, so a
    `Style := [cbStandardColors, cbSystemColors]` lifted out of a TColorBox form compiles
    here unedited.

      cbStandardColors  the 16 VGA colours (clBlack..clWhite)
      cbExtendedColors  the 4 extended ones (clMoneyGreen, clSkyBlue, clCream, clMedGray)
      cbSystemColors    the OS palette (clBtnFace, clWindow, clHighlight, ...)
      cbIncludeNone     a clNone row
      cbIncludeDefault  a clDefault row
      cbCustomColor     row 0 is a writable slot: a colour the palette does not contain
                        lands THERE instead of clearing the selection
      cbPrettyNames     'Button Face' instead of 'clBtnFace'
      cbCustomColors    fire OnGetColors after everything else, so the host can append

    Every member does something here; none is declared for looks. What we do NOT copy is
    LCL's habit of opening an OS TColorDialog from the cbCustomColor row — that is
    TTyColorComboBox's job (it opens the themed TTyColorDialog), and this library does not
    link native dialog components. }
  TTyColorBoxStyles = (cbStandardColors, cbExtendedColors, cbSystemColors,
                       cbIncludeNone, cbIncludeDefault, cbCustomColor,
                       cbPrettyNames, cbCustomColors);
  TTyColorBoxStyle  = set of TTyColorBoxStyles;

  { Fired while the palette is being (re)built, when cbCustomColors is in Style. The
    handler appends into the Items it is handed (use TyAddColorItem). LCL:
    TGetColorsEvent / TLBGetColorsEvent, colorbox.pas:44 / :168 -- one type here because
    the two controls differ only in which Sender they pass. }
  TTyGetColorsEvent = procedure(Sender: TObject; AItems: TStrings) of object;

const
  { The palette a ty-controls colour control shows when nothing says otherwise.
    DELIBERATELY not LCL's [cbStandardColors, cbExtendedColors, cbSystemColors]: this
    library has always shown the curated, pretty-named 16, and a published property's
    `default` is what every existing .lfm that omits the line is read as. Changing it
    would silently re-compose every colour box already in the field -- different count,
    different order, different names -- so the default is the value that reproduces
    today's palette exactly, and LCL's composition is one assignment away. }
  TyDefaultColorBoxStyle = [cbStandardColors, cbPrettyNames];

{ TColor -> TTyColor ($AARRGGBB, opaque). Resolves system (clXxx) colours. Pure. }
function TyTColorToTy(AColor: TColor): TTyColor;
{ The colour carried in AItems.Objects[AIndex] (clNone if out of range). }
function TyColorOfItem(AItems: TStrings; AIndex: Integer): TColor;
{ Append (AName, AColor) to AItems, storing the colour intrinsically in Objects[]. }
procedure TyAddColorItem(AItems: TStrings; const AName: string; AColor: TColor);
{ Fill AItems with the classic 16-colour VGA palette (via TyAddColorItem). }
procedure TyAddDefaultColorPalette(AItems: TStrings);
{ Index to select for AColor: the matching item, or a freshly-appended '#RRGGBB' item;
  -1 for clNone (clear). The caller assigns the result to its ItemIndex. Shared by the
  colour combo + list so the (review-hardened) select-or-append logic lives in one place. }
{ AAppendIfMissing: when the colour is not one of AItems, either add a hex-named entry
  for it (what an EDITOR wants -- the cell's current value has to be showable) or report
  -1 and leave the list alone (what a colour PICKER wants: LCL's TColorBox.Selected sets
  ItemIndex := -1 rather than growing its palette, and a setter that silently extends the
  list makes `Selected := X` non-idempotent -- twenty writes, twenty new rows). }
function TySelectColorIndex(AItems: TStrings; AColor: TColor;
  AAppendIfMissing: Boolean = True): Integer;
{ The palette-aware form of TySelectColorIndex: the row holding AColor, or -- when
  cbCustomColor is in APaletteStyle -- row 0, whose stored colour is REWRITTEN to AColor.
  That rewrite is the whole point of the custom row: a colour the palette does not contain
  still has somewhere to live instead of clearing the selection. Mirrors LCL's
  SetIndexOnColor (colorbox.pas:576-598), including its habit of skipping row 0 while
  scanning so the custom slot is only ever a fallback. -1 when there is no match and no
  custom row; -1 for clNone unless the palette actually carries a clNone row. }
function TySelectColorIndexIn(AItems: TStrings; AColor: TColor;
  APaletteStyle: TTyColorBoxStyle): Integer;
{ The display name for a colour IDENTIFIER: 'clBtnFace' -> 'Button Face'. Reads LCL's own
  rs*ColorCaption resourcestrings, so the names arrive already translated wherever LCL is.
  Unknown identifiers fall back to dropping the 'cl' prefix, exactly as LCL's
  GetPrettyColorName does (colorbox.pas:298-377). }
function TyPrettyColorName(const AColorName: string): string;
{ Rebuild AItems as the palette APaletteStyle composes: clears it, then appends every
  colour identifier the style admits (name in Items[i], TColor in Objects[i]). Does NOT
  fire OnGetColors -- that carries a Sender, so the control owns it. Pure apart from
  AItems. }
procedure TyBuildColorPalette(AItems: TStrings; APaletteStyle: TTyColorBoxStyle);
{ Draw a colour swatch (left) + name (right) into ARect; AFontSize is the caller's resolved
  size. Shared by the colour combo field, its popup list, and TTyColorListBox.
  AColorRectWidth / AColorRectOffset are LOGICAL px and both mean "decide for me" at 0:
  a 0 width keeps the height-derived square this has always drawn (so the swatch tracks
  row height / density), a 0 offset keeps the 4px inset. LCL's counterparts are
  ColorRectWidth / ColorRectOffset (colorbox.pas:82-83).

  ARightToLeft mirrors the row: the swatch takes the RIGHT end and the name reads toward it.
  Defaulted False so every caller that has not been through the RTL audit keeps the exact
  pixels it had -- only TTyColorListBox passes it today (see the note there). }
procedure TyDrawColorRow(P: TTyPainter; const ARect: TRect; AColor: TColor;
  const AName: string; const AStyle: TTyStyleSet; AFontSize: Integer;
  AColorRectWidth: Integer = 0; AColorRectOffset: Integer = 0;
  ARightToLeft: Boolean = False);

type
  { Drop-down list for TTyColorBox: draws a colour swatch + name per row via the
    TTyListBox.PaintItemContent hook. The colour is carried in each item's Objects[] entry
    (the combo copies its Items — including Objects — into this list), so there is no side
    array that could desync from the names. }
  TTyColorPopupList = class(TTyComboPopupList)
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
  end;

  { A combo of named colours: the field and the drop-down each show a colour swatch beside
    the name. Subclasses TTyComboBox, injecting a swatch-drawing popup list (CreatePopupList)
    and a swatch field (PaintFieldContent). The colour lives in Items.Objects[i], so it stays
    intrinsically aligned with the name through Sorted / Delete / direct edits (no parallel
    array). Locked to csDropDownList (pick-only): a filtered editable popup would break the
    swatch↔name mapping. Manage colours via AddColor / ClearColors; Selected is the TColor. }
  TTyColorBox = class(TTyComboBox)
  private
    FPaletteStyle:      TTyColorBoxStyle;
    FPaletteStylePending: Boolean;   { Style arrived during .lfm load; rebuild in Loaded }
    FDefaultColorColor: TColor;
    FNoneColorColor:    TColor;
    FColorRectWidth:    Integer;
    FColorRectOffset:   Integer;
    FOnGetColors:       TTyGetColorsEvent;
    function GetSelected: TColor;
    procedure SetSelected(const AValue: TColor);
    function GetColors(AIndex: Integer): TColor;
    procedure SetColors(AIndex: Integer; const AValue: TColor);
    function GetColorName(AIndex: Integer): string;
    procedure SetPaletteStyle(const AValue: TTyColorBoxStyle);
    procedure SetColorRectWidth(const AValue: Integer);
    procedure SetColorRectOffset(const AValue: Integer);
    procedure SetDefaultColorColor(const AValue: TColor);
    procedure SetNoneColorColor(const AValue: TColor);
    { Resolved swatch geometry in LOGICAL px: the property when set, else the theme. }
    function EffectiveRectWidth: Integer;
    function EffectiveRectOffset: Integer;
  protected
    function CreatePopupList: TTyListBox; override;
    procedure PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet); override;
    procedure SetStyle(AValue: TTyComboBoxStyle); override;
    procedure Loaded; override;
    { Rebuild Items from Style, then fire OnGetColors when cbCustomColors asks for it.
      Keeps the currently-selected COLOUR (not its index) across the rebuild, because the
      row a colour sits in moves whenever the composition changes. LCL: SetColorList,
      colorbox.pas:669-688. }
    procedure SetColorList; virtual;
    procedure DoGetColors; virtual;
    { What the swatch is actually painted with for a pseudo-row: the clNone and clDefault
      entries have no colour of their own. }
    function SwatchColorFor(AColor: TColor): TColor;
  public
    constructor Create(AOwner: TComponent); override;
    procedure ClearColors;
    procedure AddColor(const AName: string; AColor: TColor);
    // Colour of item AIndex (clNone if out of range).
    function ColorAt(AIndex: Integer): TColor;
    { LCL's indexed palette accessors (colorbox.pas:86-87). Colors is read/write here where
      TCustomColorBox's is read-only: recolouring one row in place is the same operation on
      a combo as on a list, and the asymmetry only ever cost a caller a rebuild. Writing an
      out-of-range index is ignored. }
    property Colors[AIndex: Integer]: TColor read GetColors write SetColors;
    property ColorNames[AIndex: Integer]: string read GetColorName;
  published
    { PUBLISHED, as TColorBox does -- it is the control's headline property and it was
      public-only, so the one thing a colour box is for could not be set in the designer
      or streamed to the .lfm. Reading returns the current item's colour (clNone if none);
      writing selects the matching item, or reports clNone when the colour is not in the
      palette (unless cbCustomColor gives it a slot). }
    property Selected: TColor read GetSelected write SetSelected;
    { WHICH colours the palette is made of. This name used to reach TTyComboBox's dropdown
      mode, which this class overrides to force csDropDownList -- so the Object Inspector
      offered a Style whose every value was discarded on write. It now carries what Style
      means on a colour box everywhere else (LCL colorbox.pas:84-85 reintroduces it over
      the combo's for the same reason). The combo mode is still locked and still reachable
      as TTyComboBox(Box).Style. }
    property Style: TTyColorBoxStyle read FPaletteStyle write SetPaletteStyle
      default TyDefaultColorBoxStyle;
    { Swatch geometry in LOGICAL px; 0 = follow the theme ('--color-swatch-width' /
      '--color-swatch-offset'), whose own fallback is the height-derived square and the
      4px inset drawn since day one. LCL: ColorRectWidth / ColorRectOffset. }
    property ColorRectWidth: Integer read FColorRectWidth write SetColorRectWidth default 0;
    property ColorRectOffset: Integer read FColorRectOffset write SetColorRectOffset default 0;
    { The colour the swatch is PAINTED with for the cbIncludeDefault / cbIncludeNone rows,
      which carry no colour of their own. Raw TColors rather than theme tokens because they
      are palette DATA -- "what does None look like" -- not control chrome; LCL declares
      them the same way (colorbox.pas:88-89) and defaults both to clBlack. }
    property DefaultColorColor: TColor read FDefaultColorColor write SetDefaultColorColor default clBlack;
    property NoneColorColor: TColor read FNoneColorColor write SetNoneColorColor default clBlack;
    property OnGetColors: TTyGetColorsEvent read FOnGetColors write FOnGetColors;
  end;

implementation

function TyTColorToTy(AColor: TColor): TTyColor;
var rgb: LongInt;
begin
  rgb := ColorToRGB(AColor);
  Result := TTyColor($FF000000) or (TTyColor(Red(rgb)) shl 16)
    or (TTyColor(Green(rgb)) shl 8) or TTyColor(Blue(rgb));
end;

function TyColorOfItem(AItems: TStrings; AIndex: Integer): TColor;
begin
  if (AIndex >= 0) and (AIndex < AItems.Count) then
    Result := TColor(PtrInt(AItems.Objects[AIndex]))
  else
    Result := clNone;
end;

procedure TyAddColorItem(AItems: TStrings; const AName: string; AColor: TColor);
begin
  AItems.AddObject(AName, TObject(PtrInt(AColor)));
end;

procedure TyAddDefaultColorPalette(AItems: TStrings);
begin
  TyAddColorItem(AItems, 'Black',   clBlack);
  TyAddColorItem(AItems, 'Maroon',  clMaroon);
  TyAddColorItem(AItems, 'Green',   clGreen);
  TyAddColorItem(AItems, 'Olive',   clOlive);
  TyAddColorItem(AItems, 'Navy',    clNavy);
  TyAddColorItem(AItems, 'Purple',  clPurple);
  TyAddColorItem(AItems, 'Teal',    clTeal);
  TyAddColorItem(AItems, 'Gray',    clGray);
  TyAddColorItem(AItems, 'Silver',  clSilver);
  TyAddColorItem(AItems, 'Red',     clRed);
  TyAddColorItem(AItems, 'Lime',    clLime);
  TyAddColorItem(AItems, 'Yellow',  clYellow);
  TyAddColorItem(AItems, 'Blue',    clBlue);
  TyAddColorItem(AItems, 'Fuchsia', clFuchsia);
  TyAddColorItem(AItems, 'Aqua',    clAqua);
  TyAddColorItem(AItems, 'White',   clWhite);
end;

function TySelectColorIndex(AItems: TStrings; AColor: TColor; AAppendIfMissing: Boolean): Integer;
var
  i: Integer;
  target: LongInt;
begin
  if AColor = clNone then Exit(-1);   // clear
  target := ColorToRGB(AColor);
  for i := 0 to AItems.Count - 1 do
    if ColorToRGB(TyColorOfItem(AItems, i)) = target then Exit(i);
  if not AAppendIfMissing then Exit(-1);
  // Not present: append a hex-named item and select it.
  TyAddColorItem(AItems, Format('#%.2x%.2x%.2x', [Red(target), Green(target), Blue(target)]), AColor);
  Result := AItems.Count - 1;
end;

function TySelectColorIndexIn(AItems: TStrings; AColor: TColor;
  APaletteStyle: TTyColorBoxStyle): Integer;
var
  i, first: Integer;
begin
  // Match on the STORED value first, so the clNone / clDefault rows a palette may carry
  // are selectable by name. ColorToRGB would flatten both to a real RGB and hand the
  // selection to whichever ordinary colour happened to share it.
  first := Ord(cbCustomColor in APaletteStyle);   // row 0 is the fallback, never a match
  for i := first to AItems.Count - 1 do
    if TyColorOfItem(AItems, i) = AColor then Exit(i);
  if AColor = clNone then Exit(-1);               // "no colour" clears when unrepresented
  for i := first to AItems.Count - 1 do
    if ColorToRGB(TyColorOfItem(AItems, i)) = ColorToRGB(AColor) then Exit(i);
  if (cbCustomColor in APaletteStyle) and (AItems.Count > 0) then
  begin
    AItems.Objects[0] := TObject(PtrInt(AColor));   // the custom slot takes it
    Exit(0);
  end;
  Result := -1;
end;

function TyPrettyColorName(const AColorName: string): string;
var
  c: LongInt;
begin
  Result := '';
  if IdentToColor(AColorName, c) then
    // Copied case-for-case from LCL's GetPrettyColorName (colorbox.pas:298-377) so the
    // captions are the ones a user of TColorBox already reads -- and, because these are
    // LCL's own resourcestrings, they are translated wherever the LCL is.
    case TColor(c) of
      clBlack:                   Result := rsBlackColorCaption;
      clMaroon:                  Result := rsMaroonColorCaption;
      clGreen:                   Result := rsGreenColorCaption;
      clOlive:                   Result := rsOliveColorCaption;
      clNavy:                    Result := rsNavyColorCaption;
      clPurple:                  Result := rsPurpleColorCaption;
      clTeal:                    Result := rsTealColorCaption;
      clGray:                    Result := rsGrayColorCaption;
      clSilver:                  Result := rsSilverColorCaption;
      clRed:                     Result := rsRedColorCaption;
      clLime:                    Result := rsLimeColorCaption;
      clYellow:                  Result := rsYellowColorCaption;
      clBlue:                    Result := rsBlueColorCaption;
      clFuchsia:                 Result := rsFuchsiaColorCaption;
      clAqua:                    Result := rsAquaColorCaption;
      clWhite:                   Result := rsWhiteColorCaption;
      clMoneyGreen:              Result := rsMoneyGreenColorCaption;
      clSkyBlue:                 Result := rsSkyBlueColorCaption;
      clCream:                   Result := rsCreamColorCaption;
      clMedGray:                 Result := rsMedGrayColorCaption;
      clNone:                    Result := rsNoneColorCaption;
      clDefault:                 Result := rsDefaultColorCaption;
      clScrollBar:               Result := rsScrollBarColorCaption;
      clBackground:              Result := rsBackgroundColorCaption;
      clActiveCaption:           Result := rsActiveCaptionColorCaption;
      clInactiveCaption:         Result := rsInactiveCaptionColorCaption;
      clMenu:                    Result := rsMenuColorCaption;
      clWindow:                  Result := rsWindowColorCaption;
      clWindowFrame:             Result := rsWindowFrameColorCaption;
      clMenuText:                Result := rsMenuTextColorCaption;
      clWindowText:              Result := rsWindowTextColorCaption;
      clCaptionText:             Result := rsCaptionTextColorCaption;
      clActiveBorder:            Result := rsActiveBorderColorCaption;
      clInactiveBorder:          Result := rsInactiveBorderColorCaption;
      clAppWorkspace:            Result := rsAppWorkspaceColorCaption;
      clHighlight:               Result := rsHighlightColorCaption;
      clHighlightText:           Result := rsHighlightTextColorCaption;
      clBtnFace:                 Result := rsBtnFaceColorCaption;
      clBtnShadow:               Result := rsBtnShadowColorCaption;
      clGrayText:                Result := rsGrayTextColorCaption;
      clBtnText:                 Result := rsBtnTextColorCaption;
      clInactiveCaptionText:     Result := rsInactiveCaptionText;
      clBtnHighlight:            Result := rsBtnHighlightColorCaption;
      cl3DDkShadow:              Result := rs3DDkShadowColorCaption;
      cl3DLight:                 Result := rs3DLightColorCaption;
      clInfoText:                Result := rsInfoTextColorCaption;
      clInfoBk:                  Result := rsInfoBkColorCaption;
      clHotLight:                Result := rsHotLightColorCaption;
      clGradientActiveCaption:   Result := rsGradientActiveCaptionColorCaption;
      clGradientInactiveCaption: Result := rsGradientInactiveCaptionColorCaption;
      clMenuHighlight:           Result := rsMenuHighlightColorCaption;
      clMenuBar:                 Result := rsMenuBarColorCaption;
      clForm:                    Result := rsFormColorCaption;
    end;
  if Result <> '' then Exit;
  Result := AColorName;
  if (Length(Result) > 2) and (Result[1] = 'c') and (Result[2] = 'l') then
    Delete(Result, 1, 2);
end;

type
  { Collects one colour per GetColorValues callback. A method is required: GetColorValues
    takes a TGetColorStringProc, which is `of object`. LCL does the same with a private
    ColorProc (colorbox.pas:517). }
  TTyColorPaletteBuilder = class
  private
    FItems: TStrings;
    FStyle: TTyColorBoxStyle;
    procedure Accept(const AName: AnsiString);
  end;

procedure TTyColorPaletteBuilder.Accept(const AName: AnsiString);
var
  c: LongInt;
  idx: Integer;
begin
  if not IdentToColor(AName, c) then Exit;
  if not (cbIncludeDefault in FStyle) and (TColor(c) = clDefault) then Exit;
  if not (cbIncludeNone in FStyle) and (TColor(c) = clNone) then Exit;
  if not (cbSystemColors in FStyle) and ((c and LongInt(SYS_COLOR_BASE)) <> 0) then Exit;
  if ([cbStandardColors, cbExtendedColors] * FStyle <> [cbStandardColors, cbExtendedColors])
     and ColorIndex(c, idx) then
  begin
    if not (cbStandardColors in FStyle) and (idx < StandardColorsCount) then Exit;
    if not (cbExtendedColors in FStyle)
       and (idx >= StandardColorsCount)
       and (idx < StandardColorsCount + ExtendedColorCount) then Exit;
  end;
  if cbPrettyNames in FStyle then
    TyAddColorItem(FItems, TyPrettyColorName(AName), TColor(c))
  else
    TyAddColorItem(FItems, AName, TColor(c));
end;

procedure TyBuildColorPalette(AItems: TStrings; APaletteStyle: TTyColorBoxStyle);
var
  b: TTyColorPaletteBuilder;
begin
  AItems.Clear;
  // The custom slot is row 0 and is seeded black, exactly as LCL does; the first colour a
  // host cannot find in the palette overwrites it (see TySelectColorIndexIn).
  if cbCustomColor in APaletteStyle then
    TyAddColorItem(AItems, rsCustomColorCaption, clBlack);
  b := TTyColorPaletteBuilder.Create;
  try
    b.FItems := AItems;
    b.FStyle := APaletteStyle;
    GetColorValues(@b.Accept);
  finally
    b.Free;
  end;
end;

{ Shared swatch-row draw: a square colour swatch on the left + the name to its right.
  AFontSize is the caller's resolved size (list rows differ from the field). }
procedure TyDrawColorRow(P: TTyPainter; const ARect: TRect; AColor: TColor;
  const AName: string; const AStyle: TTyStyleSet; AFontSize: Integer;
  AColorRectWidth: Integer; AColorRectOffset: Integer; ARightToLeft: Boolean);
var
  pad, sw, sh, maxSw, top: Integer;
  swR, txR: TRect;
  f: TTyFill;
begin
  if AColorRectOffset > 0 then pad := P.Scale(AColorRectOffset)
                          else pad := P.Scale(4);
  if AColorRectWidth > 0 then
    sw := P.Scale(AColorRectWidth)              // pinned width: a colour BAR, not a square
  else
    sw := (ARect.Bottom - ARect.Top) - 2 * pad; // square swatch, height-derived
  if sw < 4 then sw := 4;
  maxSw := (ARect.Right - ARect.Left) - 2 * pad;
  if sw > maxSw then sw := maxSw;
  if sw < 1 then Exit;
  if AColorRectWidth > 0 then
  begin
    // Height stays height-derived when the WIDTH is pinned, so a wide ColorRectWidth gives
    // a colour BAR rather than a square that overflows the row.
    sh := (ARect.Bottom - ARect.Top) - 2 * pad;
    if sh < 1 then sh := 1;
  end
  else
    sh := sw;   // auto: the square this has always drawn, clamps included
  top := ARect.Top + ((ARect.Bottom - ARect.Top) - sh) div 2;
  { The swatch sits at the LEADING edge and the name fills what is left, whichever way the
    row reads. Both the slot and the alignment have to move together: leave the alignment
    behind and the name detaches from its swatch and hugs the far edge instead. }
  if ARightToLeft then
    swR := Rect(ARect.Right - pad - sw, top, ARect.Right - pad, top + sh)
  else
    swR := Rect(ARect.Left + pad, top, ARect.Left + pad + sw, top + sh);
  f := Default(TTyFill);
  f.Kind := tfkSolid;
  f.Color := TyTColorToTy(AColor);
  P.FillBackground(swR, f, 2);
  P.StrokeBorder(swR, 2, 1, AStyle.TextColor);   // theme-driven outline so light swatches show
  if ARightToLeft then
    txR := Rect(ARect.Left + pad, ARect.Top, swR.Left - pad, ARect.Bottom)
  else
    txR := Rect(swR.Right + pad, ARect.Top, ARect.Right - pad, ARect.Bottom);
  P.DrawText(txR, AName, AStyle.FontName, AFontSize, AStyle.FontWeight,
    AStyle.TextColor, BidiFlipAlignment(taLeftJustify, ARightToLeft), tlCenter, True);
end;

{ TTyColorPopupList }

procedure TTyColorPopupList.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
var
  host: TTyColorBox;
  c: TColor;
  w, off: Integer;
begin
  { Owner-draw first: the swatch branch below replaces the whole row, so an inherited call
    would be too late. Inert unless the combo has both an owner-draw Style and a handler --
    which on a colour box means TTyComboBox(Box).Style, since Style on this class is the
    palette composition. }
  if TyComboCollectRowOwnerDraw(Self, ARowRect, AIndex) then Exit;
  c := TyColorOfItem(Items, AIndex);
  w := 0; off := 0;
  // The popup is created by the combo (Create(Self)), so its owner is the control whose
  // swatch geometry and pseudo-row colours the rows must match. Without this the dropdown
  // drew clNone/clDefault as raw sentinel values and ignored ColorRectWidth entirely.
  if Owner is TTyColorBox then
  begin
    host := TTyColorBox(Owner);
    c   := host.SwatchColorFor(c);
    w   := host.EffectiveRectWidth;
    off := host.EffectiveRectOffset;
  end;
  TyDrawColorRow(P, ARowRect, c, Items[AIndex], AStyle, ResolveFontSize(AStyle), w, off);
end;

{ TTyColorBox }

constructor TTyColorBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPaletteStyle      := TyDefaultColorBoxStyle;
  FDefaultColorColor := clBlack;
  FNoneColorColor    := clBlack;
  FColorRectWidth    := 0;
  FColorRectOffset   := 0;
  // The curated pretty-named 16 -- which is exactly what TyDefaultColorBoxStyle composes.
  // Users can ClearColors + AddColor, or re-compose declaratively through Style.
  SetColorList;
  if Items.Count > 0 then ItemIndex := 0;
end;

procedure TTyColorBox.SetStyle(AValue: TTyComboBoxStyle);
begin
  { A colour box is always PICK-ONLY: the editable csDropDown popup is prefix-FILTERED,
    which would map row indices to the wrong swatches. But pick-only is the only thing this
    class needs to insist on, and flattening every value to csDropDownList took the
    ORTHOGONAL choice down with it -- owner-draw, which has nothing to do with filtering,
    became unreachable. TyComboStylePickOnly takes off exactly the edit box, the way LCL's
    SetEditBox(False) does, so csOwnerDrawFixed and csOwnerDrawVariable get through and the
    editable spellings of them land on their pick-only twins.
    (Reachable only as TTyComboBox(Box).Style -- `Style` on this class is the palette.) }
  inherited SetStyle(TyComboStylePickOnly(AValue));
end;

procedure TTyColorBox.SetPaletteStyle(const AValue: TTyColorBoxStyle);
begin
  if FPaletteStyle = AValue then Exit;
  FPaletteStyle := AValue;
  // Streaming order is not ours to choose: a .lfm may set Style before or after anything
  // else, so defer the rebuild to Loaded. A form that never mentions Style never rebuilds,
  // which is what keeps a hand-populated Items list from being wiped on load.
  if csLoading in ComponentState then
    FPaletteStylePending := True
  else
    SetColorList;
end;

procedure TTyColorBox.Loaded;
begin
  inherited Loaded;
  if FPaletteStylePending then
  begin
    FPaletteStylePending := False;
    SetColorList;
  end;
end;

procedure TTyColorBox.SetColorList;
var
  keep: TColor;
begin
  keep := GetSelected;                    // the COLOUR survives; its row index does not
  TyBuildColorPalette(Items, FPaletteStyle);
  if cbCustomColors in FPaletteStyle then
    DoGetColors;
  ItemIndex := TySelectColorIndexIn(Items, keep, FPaletteStyle);
  Invalidate;
end;

procedure TTyColorBox.DoGetColors;
begin
  if Assigned(FOnGetColors) then FOnGetColors(Self, Items);
end;

function TTyColorBox.SwatchColorFor(AColor: TColor): TColor;
begin
  // clNone / clDefault are sentinels, not colours: painting them raw gives whatever
  // $1FFFFFFF happens to look like. LCL asks the same two properties (colorbox.pas:88-89).
  if AColor = clNone then Result := FNoneColorColor
  else if AColor = clDefault then Result := FDefaultColorColor
  else Result := AColor;
end;

function TTyColorBox.EffectiveRectWidth: Integer;
begin
  if FColorRectWidth > 0 then Result := FColorRectWidth
  else Result := ActiveController.Metric('--color-swatch-width', 0);
end;

function TTyColorBox.EffectiveRectOffset: Integer;
begin
  if FColorRectOffset > 0 then Result := FColorRectOffset
  else Result := ActiveController.Metric('--color-swatch-offset', 0);
end;

procedure TTyColorBox.SetColorRectWidth(const AValue: Integer);
begin
  if FColorRectWidth = AValue then Exit;
  FColorRectWidth := AValue;
  Invalidate;
end;

procedure TTyColorBox.SetColorRectOffset(const AValue: Integer);
begin
  if FColorRectOffset = AValue then Exit;
  FColorRectOffset := AValue;
  Invalidate;
end;

procedure TTyColorBox.SetDefaultColorColor(const AValue: TColor);
begin
  if FDefaultColorColor = AValue then Exit;
  FDefaultColorColor := AValue;
  Invalidate;
end;

procedure TTyColorBox.SetNoneColorColor(const AValue: TColor);
begin
  if FNoneColorColor = AValue then Exit;
  FNoneColorColor := AValue;
  Invalidate;
end;

function TTyColorBox.GetColors(AIndex: Integer): TColor;
begin
  Result := TyColorOfItem(Items, AIndex);
end;

procedure TTyColorBox.SetColors(AIndex: Integer; const AValue: TColor);
begin
  if (AIndex < 0) or (AIndex >= Items.Count) then Exit;
  Items.Objects[AIndex] := TObject(PtrInt(AValue));
  Invalidate;
end;

function TTyColorBox.GetColorName(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < Items.Count) then Result := Items[AIndex]
  else Result := '';
end;

procedure TTyColorBox.ClearColors;
begin
  Items.Clear;
end;

procedure TTyColorBox.AddColor(const AName: string; AColor: TColor);
begin
  // Store the colour in the item's Objects[] so it can never desync from the name.
  TyAddColorItem(Items, AName, AColor);
end;

function TTyColorBox.ColorAt(AIndex: Integer): TColor;
begin
  Result := TyColorOfItem(Items, AIndex);
end;

function TTyColorBox.GetSelected: TColor;
begin
  Result := ColorAt(ItemIndex);
end;

procedure TTyColorBox.SetSelected(const AValue: TColor);
begin
  // Matches, else the cbCustomColor slot, else -1. Never grows the palette: a picker that
  // added a row per write made `Selected := X` non-idempotent.
  ItemIndex := TySelectColorIndexIn(Items, AValue, FPaletteStyle);
end;

function TTyColorBox.CreatePopupList: TTyListBox;
begin
  Result := TTyColorPopupList.Create(Self);
end;

procedure TTyColorBox.PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet);
begin
  if (ItemIndex >= 0) and (ItemIndex < Items.Count) then
    TyDrawColorRow(P, ATextRect, SwatchColorFor(ColorAt(ItemIndex)), Items[ItemIndex],
      AStyle, ResolveFontSize(AStyle), EffectiveRectWidth, EffectiveRectOffset)
  else
    inherited PaintFieldContent(P, ATextRect, AStyle);
end;

end.
