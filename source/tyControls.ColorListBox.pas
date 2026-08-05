unit tyControls.ColorListBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.ListBox, tyControls.ColorBox;

type
  { A list box of named colours: each row shows a colour swatch + name (via the
    TTyListBox.PaintItemContent hook). The colour lives in Items.Objects[i], intrinsically
    aligned with the name (survives Sorted / Delete). WHICH colours the palette holds is
    Style; individual rows come and go through AddColor / ClearColors / Colors[]; Selected
    is the chosen TColor. The list-box sibling of TTyColorBox, and it carries the same
    palette surface for the same reason -- a fix that lands on one of the pair and not the
    other is half a fix. }
  TTyColorListBox = class(TTyListBox)
  private
    FPaletteStyle:        TTyColorBoxStyle;
    FPaletteStylePending: Boolean;   { Style arrived during .lfm load; rebuild in Loaded }
    FDefaultColorColor:   TColor;
    FNoneColorColor:      TColor;
    FColorRectWidth:      Integer;
    FColorRectOffset:     Integer;
    FOnGetColors:         TTyGetColorsEvent;
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
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
    procedure Loaded; override;
    { Rebuild Items from Style, then fire OnGetColors when cbCustomColors asks for it.
      Keeps the selected COLOUR (not its row) across the rebuild. LCL: SetColorList,
      colorbox.pas:669-688. }
    procedure SetColorList; virtual;
    procedure DoGetColors; virtual;
    { The colour a pseudo-row's swatch is actually painted with. }
    function SwatchColorFor(AColor: TColor): TColor;
    { Resolved swatch geometry in LOGICAL px: the property when set, else the theme. }
    function EffectiveRectWidth: Integer;
    function EffectiveRectOffset: Integer;
  public
    constructor Create(AOwner: TComponent); override;
    procedure ClearColors;
    procedure AddColor(const AName: string; AColor: TColor);
    function ColorAt(AIndex: Integer): TColor;
    { LCL's indexed palette accessors (colorbox.pas:211-212). Colors is read/write, so
      recolouring one row after the user edits it no longer means rebuilding the palette;
      an out-of-range write is ignored. }
    property Colors[AIndex: Integer]: TColor read GetColors write SetColors;
    property ColorNames[AIndex: Integer]: string read GetColorName;
  published
    { PUBLISHED, as TColorListBox does. It was public-only, so the control's headline
      property could not be set in the designer or streamed. }
    property Selected: TColor read GetSelected write SetSelected;
    { WHICH colours the palette is made of -- see TTyColorBoxStyle. The default composes
      exactly the curated pretty-named 16 this control has always shown, so a form that
      never mentions Style is unchanged. }
    property Style: TTyColorBoxStyle read FPaletteStyle write SetPaletteStyle
      default TyDefaultColorBoxStyle;
    { Swatch geometry in LOGICAL px; 0 = follow the theme ('--color-swatch-width' /
      '--color-swatch-offset'), whose fallback is the height-derived square and the 4px
      inset drawn since day one. LCL: ColorRectWidth / ColorRectOffset. }
    property ColorRectWidth: Integer read FColorRectWidth write SetColorRectWidth default 0;
    property ColorRectOffset: Integer read FColorRectOffset write SetColorRectOffset default 0;
    { What the cbIncludeDefault / cbIncludeNone rows are PAINTED with; they carry no colour
      of their own. LCL colorbox.pas:214-215, both clBlack. }
    property DefaultColorColor: TColor read FDefaultColorColor write SetDefaultColorColor default clBlack;
    property NoneColorColor: TColor read FNoneColorColor write SetNoneColorColor default clBlack;
    property OnGetColors: TTyGetColorsEvent read FOnGetColors write FOnGetColors;
  end;

implementation

constructor TTyColorListBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPaletteStyle      := TyDefaultColorBoxStyle;
  FDefaultColorColor := clBlack;
  FNoneColorColor    := clBlack;
  FColorRectWidth    := 0;
  FColorRectOffset   := 0;
  SetColorList;
  if Items.Count > 0 then ItemIndex := 0;
end;

procedure TTyColorListBox.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
begin
  { The swatch changes ends with the row, through the shared draw's own flag rather than a
    copy of its geometry here. Safe to mirror because this control hit-tests rows on Y only
    (TTyListBox.RowAtY) -- there is no x-axis click target that could be left behind on the
    old side, and a swatch is not one. Its sibling TTyColorBox's popup list draws through the
    same function and does NOT pass the flag yet; see docs/KNOWN_GAPS.md. }
  TyDrawColorRow(P, ARowRect, SwatchColorFor(TyColorOfItem(Items, AIndex)), Items[AIndex],
    AStyle, ResolveFontSize(AStyle), EffectiveRectWidth, EffectiveRectOffset, RtlRowLayout);
end;

procedure TTyColorListBox.SetPaletteStyle(const AValue: TTyColorBoxStyle);
begin
  if FPaletteStyle = AValue then Exit;
  FPaletteStyle := AValue;
  // Deferred while streaming: a .lfm may set Style before or after Items, and a rebuild
  // mid-load would wipe whichever arrived first.
  if csLoading in ComponentState then
    FPaletteStylePending := True
  else
    SetColorList;
end;

procedure TTyColorListBox.Loaded;
begin
  inherited Loaded;
  if FPaletteStylePending then
  begin
    FPaletteStylePending := False;
    SetColorList;
  end;
end;

procedure TTyColorListBox.SetColorList;
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

procedure TTyColorListBox.DoGetColors;
begin
  if Assigned(FOnGetColors) then FOnGetColors(Self, Items);
end;

function TTyColorListBox.SwatchColorFor(AColor: TColor): TColor;
begin
  if AColor = clNone then Result := FNoneColorColor
  else if AColor = clDefault then Result := FDefaultColorColor
  else Result := AColor;
end;

function TTyColorListBox.EffectiveRectWidth: Integer;
begin
  if FColorRectWidth > 0 then Result := FColorRectWidth
  else Result := ActiveController.Metric('--color-swatch-width', 0);
end;

function TTyColorListBox.EffectiveRectOffset: Integer;
begin
  if FColorRectOffset > 0 then Result := FColorRectOffset
  else Result := ActiveController.Metric('--color-swatch-offset', 0);
end;

procedure TTyColorListBox.SetColorRectWidth(const AValue: Integer);
begin
  if FColorRectWidth = AValue then Exit;
  FColorRectWidth := AValue;
  Invalidate;
end;

procedure TTyColorListBox.SetColorRectOffset(const AValue: Integer);
begin
  if FColorRectOffset = AValue then Exit;
  FColorRectOffset := AValue;
  Invalidate;
end;

procedure TTyColorListBox.SetDefaultColorColor(const AValue: TColor);
begin
  if FDefaultColorColor = AValue then Exit;
  FDefaultColorColor := AValue;
  Invalidate;
end;

procedure TTyColorListBox.SetNoneColorColor(const AValue: TColor);
begin
  if FNoneColorColor = AValue then Exit;
  FNoneColorColor := AValue;
  Invalidate;
end;

procedure TTyColorListBox.ClearColors;
begin
  Items.Clear;
end;

procedure TTyColorListBox.AddColor(const AName: string; AColor: TColor);
begin
  TyAddColorItem(Items, AName, AColor);
end;

function TTyColorListBox.ColorAt(AIndex: Integer): TColor;
begin
  Result := TyColorOfItem(Items, AIndex);
end;

function TTyColorListBox.GetColors(AIndex: Integer): TColor;
begin
  Result := TyColorOfItem(Items, AIndex);
end;

procedure TTyColorListBox.SetColors(AIndex: Integer; const AValue: TColor);
begin
  if (AIndex < 0) or (AIndex >= Items.Count) then Exit;
  Items.Objects[AIndex] := TObject(PtrInt(AValue));
  Invalidate;
end;

function TTyColorListBox.GetColorName(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < Items.Count) then Result := Items[AIndex]
  else Result := '';
end;

function TTyColorListBox.GetSelected: TColor;
begin
  Result := ColorAt(ItemIndex);
end;

procedure TTyColorListBox.SetSelected(const AValue: TColor);
begin
  // Matches, else the cbCustomColor slot, else -1 -- never a silently-grown palette.
  ItemIndex := TySelectColorIndexIn(Items, AValue, FPaletteStyle);
end;

end.
