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

  Children flow LEFT -> RIGHT. The simplest robust arrangement is to let each
  child button carry Align=alLeft: the LCL alignment engine then packs them
  against the left edge in child order, and no custom AlignControls is needed.
  The convenience AddButton helper does exactly this (creates a TTyGlyphButton,
  parents it, and sets Align=alLeft), so populating the QAT in code is a
  one-liner. Callers may of course parent any small TTy control themselves and
  give it Align=alLeft.

  A pure helper TyQatContentWidth computes the total packed width of a set of
  left-aligned items (indent + item widths + inter-item spacing) so a host can
  size the strip; it is headless-unit-tested with concrete numbers. }

interface

uses
  Classes, SysUtils, Types, Controls, Graphics,
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
  protected
    function GetStyleTypeKey: string; override;   // 'TyRibbon' — reuse the ribbon band token
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    { Create a compact TTyGlyphButton, parent it to this QAT, set Align=alLeft
      (so it packs against the left edge, flowing after any earlier children),
      and return it. Grows ControlCount by one. The returned button is owned by
      Self's Owner (this control), so it is freed with the QAT. }
    function AddButton(const ACaption: string): TTyGlyphButton;
  published
    { Left/top inset before the first item (logical px). Purely advisory for a
      host that sizes the strip via TyQatContentWidth; child Align=alLeft packs
      flush to the client edge, so Indent does not itself move the buttons. }
    property Indent: Integer read FIndent write SetIndent default 3;
    { Advisory inter-item spacing (logical px) used by TyQatContentWidth when a
      host measures the packed width. }
    property Spacing: Integer read FSpacing write SetSpacing default 2;
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
  // Default alNone: a title-bar strip is positioned by the app, not docked.
  Align := alNone;
  Width := TyQatDefaultWidth;
  Height := TyQatDefaultHeight;
end;

function TTyRibbonQuickAccess.GetStyleTypeKey: string;
begin
  // Reuse the ribbon band surface token — the QAT sits on the ribbon/title band.
  Result := 'TyRibbon';
end;

procedure TTyRibbonQuickAccess.SetIndent(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FIndent = AValue then Exit;
  FIndent := AValue;
  Invalidate;
end;

procedure TTyRibbonQuickAccess.SetSpacing(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FSpacing = AValue then Exit;
  FSpacing := AValue;
  Invalidate;
end;

function TTyRibbonQuickAccess.AddButton(const ACaption: string): TTyGlyphButton;
begin
  Result := TTyGlyphButton.Create(Self);
  Result.Parent := Self;
  Result.Caption := ACaption;
  // Left-to-right flow: LCL packs alLeft children against the left edge in
  // child order, so each AddButton lands after the previous one automatically.
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
    S := CurrentStyle;
    W := ARect.Right - ARect.Left;
    H := ARect.Bottom - ARect.Top;
    // Lay the form's photo down first so an alpha() background tints the photo
    // (glass), like TTyPanel/TTyToolBar. No-op (False) off-image and headless.
    FillSharpBackdrop(P, Rect(0, 0, W, H));
    // Draw the themed strip (background + any border/radius) via the shared
    // DrawFrame with the resolved ribbon-band style. Safe with 0 children.
    DrawFrame(P, Rect(0, 0, W, H), S);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
