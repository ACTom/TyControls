unit tyControls.GroupBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, LCLType, LMessages,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Accel;
type
  TTyGroupBox = class(TTyCustomControl)
  private
    FCaption: TCaption;
    FAlignment: TAlignment;
    procedure SetCaption(const AValue: TCaption);
    procedure SetAlignment(AValue: TAlignment);
    { Shared caption-band height: 16 logical px scaled to APPI.
      Used by both RenderTo and AdjustClientRect so they stay in sync. }
    function CapHAtPPI(APPI: Integer): Integer;
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure AdjustClientRect(var ARect: TRect); override;
    function DialogChar(var Message: TLMKey): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Caption: TCaption read FCaption write SetCaption;
    { NOTE: this is the CAPTION's alignment in the band, and it has no LCL counterpart --
      TGroupBox/TRadioGroup/TCheckGroup publish no Alignment at all. It is emphatically NOT
      TCustomCheckBox.Alignment, which is a TLeftRight naming the side the INDICATOR sits on
      (see TTyCheckBox.Alignment). Same word, two subjects; recorded so nobody unifies them. }
    property Alignment: TAlignment read FAlignment write SetAlignment default taLeftJustify;
    { AutoSize is NOT republished here, and that is not an oversight: TTyCustomControl
      already publishes it (tyControls.Base.pas), so it has always been in the Object
      Inspector for this control and every other one. The audit claim that a ty group box
      "cannot be made to hug its contents" was wrong on the facts -- TWinControl computes a
      container's preferred size from its children, and AdjustClientRect above already
      reserves the caption band plus the themed padding, so the whole path was live.
      Restating the publication would have looked like a fix and changed nothing. }
    { The size of the space INSIDE the frame. On a group box the client and the outer bounds
      differ by the caption band and the themed padding, which is exactly what makes "I need
      this much room inside" the natural thing to say -- and it was unsayable in the designer
      and dropped from any ported .lfm that pinned it (LCL: stdctrls.pp:193-194). }
    property ClientWidth;
    property ClientHeight;
    { Docking, republished exactly as TGroupBox does and for the same reason TTyPanel does
      it (tyControls.Panel.pas): every member here is TWinControl's or TControl's own, and
      the dock manager that drives them is LCL code we do not touch.

      It really is republish and not re-implementation, and that is measured rather than
      assumed -- a real drag (mouse_event into the system input queue, hit-tested by
      Windows, dispatched through LCL's DragManager) docks a control into a ty group box
      with no source change at all, and the same probe with DockSite:=False refuses it.
      The findings are in plans/2026-08-04-parity-remaining-programs.md. TTyFormSurface
      does not get in the dock manager's way either; the site's Parent was the surface.

      DockSite/UseDockManager/OnDockDrop/OnDockOver/OnUnDock are public on TWinControl;
      OnGetSiteInfo/OnGetDockCaption and OnStartDock/OnEndDock are PROTECTED, so before
      this no route reached those four -- not the designer, and not hand-written code
      either. }
    property DockSite;
    property UseDockManager;
    property OnDockDrop;
    property OnDockOver;
    property OnUnDock;
    property OnGetSiteInfo;
    property OnGetDockCaption;
    property OnStartDock;
    property OnEndDock;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

{ TyGroupRowPitch — PURE, and the shared row-pitch rule of every item-grid group that hosts
  real child controls (TTyRadioGroup, TTyCheckGroup). Both arguments are DEVICE pixels.

  AThemeRowH is what the theme asks for (--row-height, already scaled to the control's ppi).
  AItemMinH is what one hosted item's own Constraints.MinHeight demands -- itself entirely
  theme-derived (caption line + --pad-control, floored at --radio-size / --checkbox-size).

  The larger wins, and that is not a preference. LCL clamps EVERY SetBounds up to
  Constraints.MinHeight, so laying rows AThemeRowH apart while each row is drawn AItemMinH
  tall does not produce shorter rows -- it produces OVERLAPPING ones, and the lower row is a
  later sibling and therefore higher in the child z-order, so it paints over the bottom of
  the row above it. The 2px :focus ring lives exactly at that edge, which is how "the focus
  ring's bottom edge is cut off" was reported. On the default light theme at 96ppi the
  numbers were 22 and 25: three pixels of overlap, and the whole bottom of the ring.

  Pure and unit-level ON PURPOSE. A console test process measures the caption font at 9px
  where a GUI process measures 17, so the hosted item's own minimum comes out at 17 instead
  of 25 there and the overlap never arises in the test runner at all -- an assertion made on
  those ambient numbers is permanently, falsely green (measured: it was, and it let a mutant
  that deleted this whole rule survive). Stating the rule as a function of its two inputs is
  the only form of it a headless test can actually hold. }
function TyGroupRowPitch(AThemeRowH, AItemMinH: Integer): Integer;

const
  { The fallback for --row-height, used ONLY when a theme defines no such token. Not a
    layout constant: every theme in the tree defines it, so this value never reaches a
    real skin. }
  TyGroupDefaultRowH = 22;

implementation

function TyGroupRowPitch(AThemeRowH, AItemMinH: Integer): Integer;
begin
  Result := AThemeRowH;
  if AItemMinH > Result then Result := AItemMinH;
  if Result < 1 then Result := 1;   // a zero pitch would stack every row on row 0
end;

{ TTyGroupBox }

function TTyGroupBox.CapHAtPPI(APPI: Integer): Integer;
begin
  // v3/C2: caption-band height is a skin-tunable metric (default 16 logical px).
  Result := MulDiv(ActiveController.Metric('--groupbox-caption-height', 16), APPI, 96);
  if Result < 1 then Result := 1;
end;

procedure TTyGroupBox.AdjustClientRect(var ARect: TRect);
var
  S: TTyStyleSet;
  ppi: Integer;
begin
  inherited AdjustClientRect(ARect);
  ppi := Font.PixelsPerInch;
  S := CurrentStyle;
  // Reserve the caption band (Top) AND the themed content padding on every side, so children
  // never paint over the frame's left/right/bottom border. Padding is theme-token-driven
  // (TyGroupBox) — matching how TTyPanel insets its content.
  // Top: the caption band ONLY (it already separates content from the caption; adding padding.Top
  // would double-space). Left/Right/Bottom: the themed padding, so children clear the frame border.
  Inc(ARect.Left,   MulDiv(S.Padding.Left, ppi, 96));
  Inc(ARect.Top,    CapHAtPPI(ppi));
  Dec(ARect.Right,  MulDiv(S.Padding.Right, ppi, 96));
  Dec(ARect.Bottom, MulDiv(S.Padding.Bottom, ppi, 96));
  if ARect.Right < ARect.Left then ARect.Right := ARect.Left;
  if ARect.Bottom < ARect.Top then ARect.Bottom := ARect.Top;
end;

constructor TTyGroupBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TyAccelRegister(Self);
  // Designer container: the IDE drops child controls INTO the box; they lay out below
  // the caption band carved by AdjustClientRect.
  ControlStyle := ControlStyle + [csAcceptsControls];
  FCaption := '';
  FAlignment := taLeftJustify;
  Width := 185;
  Height := 105;
end;

destructor TTyGroupBox.Destroy;
begin
  TyAccelUnregister(Self);
  inherited Destroy;
end;

function TTyGroupBox.DialogChar(var Message: TLMKey): Boolean;
var pf: TCustomForm;
begin
  if Enabled and TyIsAccelKey(Message, FCaption) then
  begin
    pf := GetParentForm(Self);
    if pf <> nil then pf.SelectNext(Self, True, True);   // focus the first child after the group box
    Exit(True);
  end;
  Result := inherited DialogChar(Message);
end;

function TTyGroupBox.GetStyleTypeKey: string;
begin
  Result := 'TyGroupBox';
end;

procedure TTyGroupBox.SetCaption(const AValue: TCaption);
begin
  if FCaption = AValue then Exit;
  FCaption := AValue;
  Invalidate;
end;

procedure TTyGroupBox.SetAlignment(AValue: TAlignment);
begin
  if FAlignment = AValue then Exit;
  FAlignment := AValue;
  Invalidate;
end;

procedure TTyGroupBox.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  W, H, CapH: Integer;
  FrameRect, BandRect, TextRect: TRect;
  TextW, BandLeft: Integer;
  MeasBmp: TBitmap;
  disp: string;
  mp: Integer;
  BandAlign: TAlignment;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI, IsRightToLeft);
    { MIRRORING: the caption band moves to the other end of the top border. That is the
      whole visible change -- the frame is symmetric and AdjustClientRect insets left and
      right by their own themed paddings, so a mirrored group box only differs there if a
      skin gave it asymmetric padding, and swapping those would put our containers out of
      step with LCL's for no visible gain. Children are laid out by the align engine, which
      does not mirror (see TTyPanel.RenderTo). No internal hit test. }
    BandAlign := BidiFlipAlignment(FAlignment, IsRightToLeft);
    S := CurrentStyle;

    W := ARect.Right - ARect.Left;
    H := ARect.Bottom - ARect.Top;

    // Caption band height: 16 logical pixels (matches AdjustClientRect inset)
    CapH := CapHAtPPI(APPI);
    if CapH < 1 then CapH := 1;

    // Draw the frame rect inset from caption mid-line
    FrameRect := Rect(0, CapH div 2, W, H);
    DrawFrame(P, FrameRect, S);

    // The caption band strip sits ABOVE the frame, so DrawFrame never paints it.
    // On an image theme fill it with the form's photo; off-image fill it with the
    // OPAQUE resolved parent background so it is not a transparent gap (which the
    // Win10 DWM glass would show as white on deactivate).
    if not FillSharpBackdrop(P, Rect(0, 0, W, CapH div 2)) then
      TyFillParentBg(Self, P, Rect(0, 0, W, CapH div 2), S);

    // Draw caption text with a background band behind it
    if FCaption <> '' then
    begin
      TyParseMnemonic(FCaption, disp, mp);
      // Measure actual text width using a scratch bitmap canvas so CJK and
      // variable-width fonts are handled correctly (avoids byte-Length * 8).
      MeasBmp := TBitmap.Create;
      try
        MeasBmp.SetSize(1, 1);
        MeasBmp.Canvas.Font.Name := TyEffectiveFontName(S.FontName);
        // Measure with the same effective size the caption is drawn at, so the
        // erased band matches the now-readable text (ResolveFontSize fallback).
        MeasBmp.Canvas.Font.Size := MulDiv(ResolveFontSize(S), APPI, 96);
        TextW := MeasBmp.Canvas.TextWidth(disp);
      finally
        MeasBmp.Free;
      end;
      if TextW < 1 then TextW := 1;

      // Position the erase band AND the text from the SAME BandLeft per
      // Alignment, so the erased gap stays centered on the caption ink.
      // BandAlign, not FAlignment: this is a physical x, and the two differ under mirroring.
      case BandAlign of
        taCenter:      BandLeft := (W - (TextW + P.Scale(16))) div 2;
        taRightJustify:BandLeft := W - (TextW + P.Scale(16)) - P.Scale(4);
      else             BandLeft := P.Scale(4);   // taLeftJustify (current look: band starts ~Scale(8))
      end;
      if BandLeft < 0 then BandLeft := 0;

      // Break the top border behind the caption. On an image theme show the
      // form's photo through the gap; otherwise fill the OPAQUE resolved parent
      // background (not a transparent erase — the Win10 DWM glass shows an erased
      // gap as white on deactivate).
      BandRect := Rect(BandLeft, 0, BandLeft + TextW + P.Scale(16), CapH);
      if not FillSharpBackdrop(P, BandRect) then
        TyFillParentBg(Self, P, BandRect, S);

      // Draw caption text within the band, aligned per FAlignment.
      TextRect := Rect(BandLeft + P.Scale(4), 0, BandLeft + P.Scale(4) + TextW + P.Scale(8), CapH);
      P.DrawText(TextRect, disp, S.FontName, ResolveFontSize(S), S.FontWeight,
        S.TextColor, FAlignment, tlCenter, True, TyAccelGatePos(mp));
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyGroupBox.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
