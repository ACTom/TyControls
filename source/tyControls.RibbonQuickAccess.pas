unit tyControls.RibbonQuickAccess;
{$mode objfpc}{$H+}

{ TTyRibbonQuickAccess — the ribbon Quick Access Toolbar (QAT).

  A compact horizontal strip that hosts a few SMALL command controls (the
  Batch-C button family: TTyGlyphButton / TTySpeedButton) and paints a themed
  strip background behind them. It is meant to sit in the ribbon's TITLE-BAR
  ROW, to the right of the app button and to the left of the window caption —
  pairing with TTyRibbon below it.

  It is a themed windowed CONTAINER, modelled directly on TTyToolBar:
    - ControlStyle + [csAcceptsControls] so child controls parent into it;
    - RenderTo paints a compact strip via DrawFrame with the resolved style
      (headless-safe, never raises with 0 children);
    - GetStyleTypeKey = 'TyRibbon' — it REUSES the existing ribbon band token
      (the QAT sits on the ribbon/title band, so it should read as that
      surface). No new .tycss rule is introduced.

  Children flow LEFT -> RIGHT. Each child button carries Align=alLeft and the
  LCL alignment engine packs them against the left edge, ordered by their Left:
  siblings that all sit at Left 0 come out in REVERSE creation order, so the
  Left is what decides (#51). The convenience AddButton helper creates a
  TTyGlyphButton, starts it past the children already there and sets
  Align=alLeft, so populating the QAT in code is a one-liner and the buttons
  read in the order they were added. A caller that parents its own controls
  with Align=alLeft has to give them increasing Lefts the same way.

  A pure helper TyQatContentWidth computes the total packed width of a set of
  left-aligned items (indent + item widths + inter-item spacing) so a host can
  size the strip; it is headless-unit-tested with concrete numbers. }

interface

uses
  Classes, SysUtils, Types, LCLType, Controls, Graphics,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.GlyphButtons;

const
  { Default compact strip height (logical px) — sized to sit in a title-bar row
    and host small ~22px command buttons. }
  TyQatDefaultHeight = 26;
  { Default strip width (logical px) — the app repositions/resizes it. }
  TyQatDefaultWidth = 120;

type
  TTyRibbonQuickAccess = class(TTyCustomControl)
  private
    FIndent: Integer;
    FSpacing: Integer;
    procedure SetIndent(AValue: Integer);
    procedure SetSpacing(AValue: Integer);
    { Indent and Spacing, in device px at APPI, into ChildSizing -- which LCL's align pass
      already honours for aligned children: LeftRightSpacing from the edge, HorizontalSpacing
      between neighbours (#117). }
    procedure SyncSpacing(APPI: Integer);
  protected
    procedure Loaded; override;
    procedure ScaleFontsPPI(const AToPPI: Integer; const AProportion: Double); override;
    function GetStyleTypeKey: string; override;   // 'TyRibbon' — reuse the ribbon band token
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    { Create a compact TTyGlyphButton, parent it to this QAT, set Align=alLeft
      (so it packs against the left edge, after every earlier child), and return
      it. Grows ControlCount by one. The returned button is owned by this
      control, so it is freed with the QAT. }
    function AddButton(const ACaption: string): TTyGlyphButton;
  published
    { The inset before the first button (logical px). It used to be advisory only -- read by
      TyQatContentWidth and by nothing that placed a button -- and moves the buttons now
      (#117). }
    property Indent: Integer read FIndent write SetIndent default 3;
    { The gap between buttons (logical px), likewise. }
    property Spacing: Integer read FSpacing write SetSpacing default 2;
    { Indent and Spacing own it on this strip, so it is not written to the form. }
    property ChildSizing stored False;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

{ Pure helper: total packed width (device/logical px, caller-consistent) of
  Length(AItemWidths) items laid out left-to-right — AIndent leading inset, each
  item width, and ASpacing between adjacent items (never before the first, never
  after the last). Zero items -> just AIndent (a leading inset with nothing in
  it). Negative inputs are floored at 0. Headless-testable. }
function TyQatContentWidth(const AItemWidths: array of Integer; AIndent, ASpacing: Integer): Integer;

implementation

function TyQatContentWidth(const AItemWidths: array of Integer; AIndent, ASpacing: Integer): Integer;
var
  i, w: Integer;
begin
  if AIndent < 0 then AIndent := 0;
  if ASpacing < 0 then ASpacing := 0;
  Result := AIndent;
  for i := 0 to High(AItemWidths) do
  begin
    w := AItemWidths[i];
    if w < 0 then w := 0;
    if i > 0 then Inc(Result, ASpacing);
    Inc(Result, w);
  end;
end;

{ TTyRibbonQuickAccess }

constructor TTyRibbonQuickAccess.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls];   // hosts the small command controls
  FIndent := 3;
  FSpacing := 2;
  SyncSpacing(Font.PixelsPerInch);
  // Default alNone: a title-bar strip is positioned by the app, not docked.
  Align := alNone;
  Width := ActiveController.Metric('--qat-width', TyQatDefaultWidth);
  Height := ActiveController.Metric('--qat-height', TyQatDefaultHeight);
end;

function TTyRibbonQuickAccess.GetStyleTypeKey: string;
begin
  { Own key rather than the borrowed 'TyTitleBar': the QAT is not the title bar; borrowing it meant the QAT inherited the window chrome's shadow, radius and border stroke.
    Added to 'TyTitleBar's rule block as an extra selector, so every resolved value is
    unchanged — this opens a hook, it does not restyle anything. }
  Result := 'TyRibbonQuickAccess';
end;

procedure TTyRibbonQuickAccess.SetIndent(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FIndent = AValue then Exit;
  FIndent := AValue;
  SyncSpacing(Font.PixelsPerInch);
  Invalidate;
end;

procedure TTyRibbonQuickAccess.SetSpacing(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FSpacing = AValue then Exit;
  FSpacing := AValue;
  SyncSpacing(Font.PixelsPerInch);
  Invalidate;
end;

procedure TTyRibbonQuickAccess.SyncSpacing(APPI: Integer);
begin
  if APPI <= 0 then APPI := 96;
  ChildSizing.LeftRightSpacing := MulDiv(FIndent, APPI, 96);
  ChildSizing.HorizontalSpacing := MulDiv(FSpacing, APPI, 96);
end;

procedure TTyRibbonQuickAccess.Loaded;
begin
  inherited Loaded;
  SyncSpacing(Font.PixelsPerInch);
end;

procedure TTyRibbonQuickAccess.ScaleFontsPPI(const AToPPI: Integer; const AProportion: Double);
begin
  inherited ScaleFontsPPI(AToPPI, AProportion);
  SyncSpacing(AToPPI);   // LCL does not scale ChildSizing itself
end;

function TTyRibbonQuickAccess.AddButton(const ACaption: string): TTyGlyphButton;
var
  i, x: Integer;
begin
  { The align engine orders alLeft siblings by Left, and with every Left at 0 it packs them in
    REVERSE creation order (#51). So start the new button past every child already here: the
    number is only a sort key, the engine places it flush on its first pass. }
  x := 0;
  for i := 0 to ControlCount - 1 do
    if Controls[i].Left + Controls[i].Width > x then
      x := Controls[i].Left + Controls[i].Width;
  Result := TTyGlyphButton.Create(Self);
  Result.Left := x;
  Result.Parent := Self;
  Result.Caption := ACaption;
  Result.Align := alLeft;
end;

procedure TTyRibbonQuickAccess.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTyRibbonQuickAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  W, H: Integer;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    // GetStyleTypeKey='TyTitleBar' -> CurrentStyle is the title-bar surface, so the strip
    // blends with the caption bar instead of drawing a white ribbon-body strip.
    S := CurrentStyle;
    W := ARect.Right - ARect.Left;
    H := ARect.Bottom - ARect.Top;
    // Lay the form's photo down first so an alpha() background tints the photo
    // (glass), like TTyPanel/TTyToolBar. No-op (False) off-image and headless.
    FillSharpBackdrop(P, Rect(0, 0, W, H));
    // Draw the themed strip (background + any border/radius) via the shared
    // DrawFrame with the resolved title-bar style. Safe with 0 children.
    DrawFrame(P, Rect(0, 0, W, H), S);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
