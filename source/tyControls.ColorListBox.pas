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
  TTyCustomColorListBox = class(TTyCustomListBox)
  private
    FPaletteStyle:        TTyColorBoxStyle;
    { Selected as a form file gave it, held for Loaded: see SetSelected. }
    FStreamedSelected:    TColor;
    FSelectedWaits:       Boolean;
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

  { TTyColorListBox publishes TTyCustomColorListBox's properties; everything lives in TTyCustomColorListBox. }
  TTyColorListBox = class(TTyCustomColorListBox)
  published
    property Version;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
    property TabOrder;
    property TabStop;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseWheel;
    property OnMouseWheelUp;
    property OnMouseWheelDown;
    property OnContextPopup;
    property OnResize;
    property OnChangeBounds;
    property AutoSize;
    property BorderWidth;
    property ChildSizing;
    property DragMode;
    property DragKind;
    property DragCursor;
    property OnDragOver;
    property OnDragDrop;
    property OnStartDrag;
    property OnEndDrag;
    property OnMouseWheelHorz;
    property OnMouseWheelLeft;
    property OnMouseWheelRight;
    property OnShowHint;
    property PopupMenu;
    property Constraints;
    property BorderSpacing;
    property ParentShowHint;
    property Action;
    property OnPaint;
    property OnKeyDown;
    property OnKeyUp;
    property OnKeyPress;
    property OnUTF8KeyPress;
    property OnEnter;
    property OnExit;
    property OnEditingDone;
    property StyleClass;
    property StyleOverride;
    property Controller;
    property Items;
    property ItemIndex;
    property MultiSelect;
    property ExtendedSelect;
    property Sorted;
    property ItemHeight;
    property ScrollWidth;
    property ScrollBarAutoHide;
    property TopIndex;
    property OnChange;
    property OnSelectionChange;
    property Align;
    property Anchors;
    property Selected;
    property Style;
    property ColorRectWidth;
    property ColorRectOffset;
    property DefaultColorColor;
    property NoneColorColor;
    property OnGetColors;
  end;

implementation

constructor TTyCustomColorListBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPaletteStyle      := TyDefaultColorBoxStyle;
  FDefaultColorColor := clBlack;
  FNoneColorColor    := clBlack;
  FColorRectWidth    := 0;
  FColorRectOffset   := 0;
  { Built from Style, never authored: a form file cannot carry the colours, so Items is not
    written (see Loaded). }
  FItemsStreamed     := False;
  SetColorList;
  if Items.Count > 0 then ItemIndex := 0;
end;

procedure TTyCustomColorListBox.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
begin
  { The swatch changes ends with the row, through the shared draw's own flag rather than a
    copy of its geometry here. Safe to mirror because this control hit-tests rows on Y only
    (TTyListBox.RowAtY) -- there is no x-axis click target that could be left behind on the
    old side, and a swatch is not one. Its sibling TTyColorBox's popup list draws through the
    same function and does NOT pass the flag yet; see docs/rtl.md. }
  TyDrawColorRow(P, ARowRect, SwatchColorFor(TyColorOfItem(Items, AIndex)), Items[AIndex],
    AStyle, ResolveFontSize(AStyle), EffectiveRectWidth, EffectiveRectOffset, RtlRowLayout);
end;

procedure TTyCustomColorListBox.SetPaletteStyle(const AValue: TTyColorBoxStyle);
begin
  if FPaletteStyle = AValue then Exit;
  FPaletteStyle := AValue;
  { Streaming order is not ours to choose: a .lfm may set Style before or after anything else,
    so while one is read the rebuild waits for Loaded, which always rebuilds. (It used to rebuild
    only when Style had been read, to keep "a hand-populated Items list"; that list never had
    colours to keep -- see Loaded.) }
  if not (csLoading in ComponentState) then
    SetColorList;
end;

procedure TTyCustomColorListBox.Loaded;
begin
  inherited Loaded;
  { ALWAYS rebuild from Style, as LCL does (colorbox.pas Loaded). Items cannot carry the colours:
    a form file stores a TStrings as its strings alone, so a list read back from one is names over
    black swatches. 3.0.0 wrote Items for every box, and on a form that left Style at its default
    nothing rebuilt it -- every swatch came back black and the selection was lost. Items is no
    longer written (FItemsStreamed), but forms saved before still carry it, and this is what reads
    them right. A palette of one's own is cbCustomColors + OnGetColors, or AddColor at run time. }
  SetColorList;              // a Selected the form file held is found in the rebuilt palette
  FSelectedWaits := False;   // and from here on the box's own selection is what survives
end;

procedure TTyCustomColorListBox.SetColorList;
var
  keep: TColor;
begin
  if FSelectedWaits then
    keep := FStreamedSelected             // Loaded, with a streamed colour still to find
  else
    keep := GetSelected;                  // the COLOUR survives; its row index does not
  TyBuildColorPalette(Items, FPaletteStyle);
  if cbCustomColors in FPaletteStyle then
    DoGetColors;
  ItemIndex := TySelectColorIndexIn(Items, keep, FPaletteStyle);
  Invalidate;
end;

procedure TTyCustomColorListBox.DoGetColors;
begin
  if Assigned(FOnGetColors) then FOnGetColors(Self, Items);
end;

function TTyCustomColorListBox.SwatchColorFor(AColor: TColor): TColor;
begin
  if AColor = clNone then Result := FNoneColorColor
  else if AColor = clDefault then Result := FDefaultColorColor
  else Result := AColor;
end;

function TTyCustomColorListBox.EffectiveRectWidth: Integer;
begin
  if FColorRectWidth > 0 then Result := FColorRectWidth
  else Result := ActiveController.Metric('--color-swatch-width', 0);
end;

function TTyCustomColorListBox.EffectiveRectOffset: Integer;
begin
  if FColorRectOffset > 0 then Result := FColorRectOffset
  else Result := ActiveController.Metric('--color-swatch-offset', 0);
end;

procedure TTyCustomColorListBox.SetColorRectWidth(const AValue: Integer);
begin
  if FColorRectWidth = AValue then Exit;
  FColorRectWidth := AValue;
  Invalidate;
end;

procedure TTyCustomColorListBox.SetColorRectOffset(const AValue: Integer);
begin
  if FColorRectOffset = AValue then Exit;
  FColorRectOffset := AValue;
  Invalidate;
end;

procedure TTyCustomColorListBox.SetDefaultColorColor(const AValue: TColor);
begin
  if FDefaultColorColor = AValue then Exit;
  FDefaultColorColor := AValue;
  Invalidate;
end;

procedure TTyCustomColorListBox.SetNoneColorColor(const AValue: TColor);
begin
  if FNoneColorColor = AValue then Exit;
  FNoneColorColor := AValue;
  Invalidate;
end;

procedure TTyCustomColorListBox.ClearColors;
begin
  Items.Clear;
end;

procedure TTyCustomColorListBox.AddColor(const AName: string; AColor: TColor);
begin
  TyAddColorItem(Items, AName, AColor);
end;

function TTyCustomColorListBox.ColorAt(AIndex: Integer): TColor;
begin
  Result := TyColorOfItem(Items, AIndex);
end;

function TTyCustomColorListBox.GetColors(AIndex: Integer): TColor;
begin
  Result := TyColorOfItem(Items, AIndex);
end;

procedure TTyCustomColorListBox.SetColors(AIndex: Integer; const AValue: TColor);
begin
  if (AIndex < 0) or (AIndex >= Items.Count) then Exit;
  Items.Objects[AIndex] := TObject(PtrInt(AValue));
  Invalidate;
end;

function TTyCustomColorListBox.GetColorName(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < Items.Count) then Result := Items[AIndex]
  else Result := '';
end;

function TTyCustomColorListBox.GetSelected: TColor;
begin
  Result := ColorAt(ItemIndex);
end;

procedure TTyCustomColorListBox.SetSelected(const AValue: TColor);
begin
  { While a form file is read the palette is not final yet: Style only rebuilds it in Loaded,
    and a form file may hold Selected before Style or Items (TTyColorListBox publishes it
    ahead of Style; a third party's TTyCustomColorBox / TTyCustomColorListBox may put it
    anywhere). Looked up then, a colour from the extended or system palette is not there yet
    and the selection came back as nothing. So the colour waits for Loaded, which looks it up
    in the finished palette. LCL keeps the colour itself (FSelected) for the same reason
    (colorbox.pas:871-878, applied in Loaded at :1058-1062). }
  if csLoading in ComponentState then
  begin
    FStreamedSelected := AValue;
    FSelectedWaits := True;
    Exit;
  end;
  // Matches, else the cbCustomColor slot, else -1 -- never a silently-grown palette.
  ItemIndex := TySelectColorIndexIn(Items, AValue, FPaletteStyle);
end;

end.
