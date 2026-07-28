unit tyControls.BalloonHint;
{$mode objfpc}{$H+}

{ TTyBalloonHint — a themed balloon callout (title + description + optional icon,
  with a pointer to a target control), drawn entirely by TTyPainter using the
  'TyHint' style so it matches the current .tycss theme. Unlike TTyHint (which
  replaces the passive tooltip app-wide) a balloon is shown explicitly via
  ShowFor / ShowAt and auto-hides after HideInterval ms.

  The window is shaped (rounded body + pointer triangle) with a combined region;
  on Wayland (no XShape) it degrades to a plain rounded body (the pointer strip is
  still painted, just not cut to shape).

  Only the pure placement geometry (TyBalloonPlacement) is unit-testable
  headlessly — verify the rendered look on a real machine. }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, LCLType, LCLIntf, ExtCtrls,
  tyControls.Types, tyControls.Component, tyControls.Painter, tyControls.Controller,
  tyControls.StyleModel;

type
  TTyBalloonIcon = (biNone, biInfo, biWarning, biError);

  { Where the balloon body sits relative to its target and where its pointer tip
    touches the target edge (all screen coordinates). }
  TTyBalloonPlacement = record
    Body: TRect;           // rounded body rect (excludes the pointer strip)
    Below: Boolean;        // True: body is below the target, pointer on its top edge
    TipX, TipY: Integer;   // pointer tip (on the target's near edge)
  end;

  TTyBalloonHint = class;

  { Internal borderless popup that paints the balloon. Owned by the component. }
  TTyBalloonWindow = class(TForm)
  private
    FOwnerHint: TTyBalloonHint;
    FPlacement: TTyBalloonPlacement;
    FPointerH: Integer;    // device px
    procedure ApplyShape;
  protected
    procedure Paint; override;
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); reintroduce;
  end;

  { The balloon component. }
  TTyBalloonHint = class(TTyComponent)
  private
    FTitle: TCaption;
    FDescription: string;
    FIcon: TTyBalloonIcon;
    FHideInterval: Integer;
    FController: TTyStyleController;
    FWin: TTyBalloonWindow;
    FTimer: TTimer;
    procedure TimerFire(Sender: TObject);
    function ActiveModel: TTyStyleModel;
    { Measure the body content (icon + title + description) in device px at APPI. }
    procedure MeasureBody(APPI: Integer; out ABodyW, ABodyH: Integer);
  protected
    { The wedge's half-base AND height in LOGICAL px, from the active theme. Protected so a
      headless test can read what a theme resolved to without putting a window up. }
    function ArrowSizeLogical: Integer;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Show the balloon pointing at AControl (uses its on-screen rectangle). }
    procedure ShowFor(AControl: TControl);
    { Show the balloon pointing at an arbitrary target rectangle (screen coords). }
    procedure ShowAt(const ATargetScreen: TRect);
    { Hide immediately (also called by the auto-hide timer). }
    procedure HideHint;
  published
    property Title: TCaption read FTitle write FTitle;
    property Description: string read FDescription write FDescription;
    property Icon: TTyBalloonIcon read FIcon write FIcon default biNone;
    { Auto-hide delay in ms (0 = stay until HideHint). Default 4000. }
    property HideInterval: Integer read FHideInterval write FHideInterval default 4000;
    property Controller: TTyStyleController read FController write FController;
  end;

{ Pure placement: given the target rect and body/pointer sizes + screen, decide
  below vs above, the body rect, and the pointer tip. Prefers below; flips above
  only when there's no room below but there is above; clamps the body to screen
  and the tip within the body. Headless-testable. }
function TyBalloonPlacement(const ATargetScreen: TRect;
  ABodyW, ABodyH, APointerH, AScreenW, AScreenH: Integer): TTyBalloonPlacement;

const
  { The pointer's HALF-BASE and its height in one number, logical px -- so the wedge is always
    a right-angled 45 degree one, which is what makes it read as the body's own corner pulled
    out. This is only the FALLBACK for the metric token beside it; a theme retunes it, and the
    modern density pack already does (matching --popover-arrow-size, since the two wedges sit
    side by side in the same UI and a reader cannot see why they would differ). }
  TyBalloonArrowSize    = 8;
  TyBalloonArrowSizeVar = '--balloon-arrow-size';

implementation

uses
  Math, BGRABitmapTypes, BGRACanvas2D, tyControls.QtWS;

const
  CGapLogical     = 3;   // gap between title and description, logical px
  CIconLogical    = 16;  // icon box, logical px

// ---------------------------------------------------------------------------
// Pure placement geometry
// ---------------------------------------------------------------------------
function TyBalloonPlacement(const ATargetScreen: TRect;
  ABodyW, ABodyH, APointerH, AScreenW, AScreenH: Integer): TTyBalloonPlacement;
var
  cx, bodyLeft, belowTop, roomBelow: Integer;
begin
  cx := (ATargetScreen.Left + ATargetScreen.Right) div 2;
  belowTop := ATargetScreen.Bottom + APointerH;
  roomBelow := AScreenH - belowTop;
  // Prefer below; flip above only when below doesn't fit but above does.
  Result.Below := (roomBelow >= ABodyH) or (ATargetScreen.Top - APointerH - ABodyH < 0);

  bodyLeft := cx - ABodyW div 2;
  if bodyLeft + ABodyW > AScreenW then bodyLeft := AScreenW - ABodyW;
  if bodyLeft < 0 then bodyLeft := 0;

  if Result.Below then
  begin
    Result.Body := Rect(bodyLeft, belowTop, bodyLeft + ABodyW, belowTop + ABodyH);
    Result.TipX := cx;
    Result.TipY := ATargetScreen.Bottom;
  end
  else
  begin
    Result.Body := Rect(bodyLeft, ATargetScreen.Top - APointerH - ABodyH,
      bodyLeft + ABodyW, ATargetScreen.Top - APointerH);
    Result.TipX := cx;
    Result.TipY := ATargetScreen.Top;
  end;

  // Keep the pointer base on the body edge (leave a pointer-width margin).
  if Result.TipX < Result.Body.Left + APointerH then
    Result.TipX := Result.Body.Left + APointerH;
  if Result.TipX > Result.Body.Right - APointerH then
    Result.TipX := Result.Body.Right - APointerH;
end;

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------
function BalloonStyle: TTyStyleSet;
begin
  Result := TyDefaultController.Model.ResolveStyle('TyHint', '', []);
end;

function BalloonAccent(const AClass: string): TTyColor;
begin
  Result := TyDefaultController.Model.ResolveStyle('TyButton', AClass, []).Background.Color;
end;

function MeasureLineH(AFontSizeLogical, AWeight, APPI: Integer; const AFontName: string): Integer;
var
  Meas: TBitmap;
begin
  Meas := TBitmap.Create;
  try
    Meas.SetSize(1, 1);
    Meas.Canvas.Font.Name := TyEffectiveFontName(AFontName);
    Meas.Canvas.Font.Size := MulDiv(AFontSizeLogical, APPI, 96);
    if AWeight >= 600 then Meas.Canvas.Font.Style := [fsBold]
    else Meas.Canvas.Font.Style := [];
    Result := Meas.Canvas.TextHeight('Ag');
    if Result < 1 then Result := 1;
  finally
    Meas.Free;
  end;
end;

// ---------------------------------------------------------------------------
// TTyBalloonWindow
// ---------------------------------------------------------------------------
constructor TTyBalloonWindow.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  BorderStyle := bsNone;
  ShowInTaskBar := stNever;
  FormStyle := fsStayOnTop;
  FPointerH := 8;
end;

procedure TTyBalloonWindow.Paint;
var
  P: TTyPainter;
  S: TTyStyleSet;
  ctx: TBGRACanvas2D;
  Lines: TStringList;
  bodyRect, contentRect: TRect;
  cW, cH, ppi, fs, iconPx, padL, padT, padR, tx, lh, tipX, i, bw: Integer;
  pside: TTyPointerSide;
  bodyCol, disc: TTyColor;
  glyph: string;
begin
  if FOwnerHint = nil then Exit;
  S := BalloonStyle;
  ppi := Font.PixelsPerInch; if ppi <= 0 then ppi := 96;
  fs := S.FontSize; if fs <= 0 then fs := 9;
  cW := ClientWidth; cH := ClientHeight;
  if S.Background.Kind = tfkSolid then
  begin
    bodyCol := S.Background.Color;
    Color := TyColorToLCL(bodyCol);
  end
  else
    bodyCol := S.TextColor;

  tipX := FPlacement.TipX - FPlacement.Body.Left;

  P := TTyPainter.Create;
  Lines := TStringList.Create;
  try
    P.BeginPaint(Canvas, ClientRect, ppi);
    ctx := P.Bitmap.Canvas2D;

    if FPlacement.Below then
      bodyRect := Rect(0, FPointerH, cW, cH)
    else
      bodyRect := Rect(0, 0, cW, cH - FPointerH);

    { Body and pointer are ONE closed path. Drawn as two shapes -- a rounded rect, then a
      triangle on top of it -- the body's own border ran straight across the pointer's base,
      so the wedge read as a grey sliver stuck onto a closed box instead of the balloon
      pointing at anything. One outline has no interior edge to stroke, and the pointer's two
      slanted sides pick up the border they never had.

      Only a SOLID body can do this: the wedge is the body's fill carried past its edge, and a
      gradient / image body has no one colour to carry out there. Such a theme keeps the old
      two-step (and, as before, no wedge colour to speak of). }
    bw := 0;
    if (tpBorderColor in S.Present) and (S.BorderWidth > 0) then bw := S.BorderWidth;
    if S.Background.Kind = tfkSolid then
    begin
      if FPlacement.Below then pside := tpsTop else pside := tpsBottom;
      P.FillPointerShape(bodyRect, TyUniformCorners(S.BorderRadius), pside,
        tipX, FPointerH, FPointerH, S.Background.Color, S.BorderColor, bw);
    end
    else
    begin
      if tpBackground in S.Present then
        P.FillBackground(bodyRect, S.Background, S.BorderRadius);
      if bw > 0 then
        P.StrokeBorder(bodyRect, S.BorderRadius, bw, S.BorderColor);
    end;

    // Content layout.
    padL := P.Scale(S.Padding.Left);
    padT := P.Scale(S.Padding.Top);
    padR := P.Scale(S.Padding.Right);
    iconPx := 0;
    if FOwnerHint.FIcon <> biNone then
      iconPx := P.Scale(CIconLogical) + P.Scale(6);

    // Icon disc + glyph.
    if FOwnerHint.FIcon <> biNone then
    begin
      case FOwnerHint.FIcon of
        biInfo:    disc := BalloonAccent('primary');
        biWarning: disc := BalloonAccent('primary');
        biError:   disc := BalloonAccent('danger');
      else
        disc := S.TextColor;
      end;
      case FOwnerHint.FIcon of
        biInfo:    glyph := 'i';
        biWarning: glyph := '!';
        biError:   glyph := '\';   // rendered as a cross-ish mark; replaced below
      else
        glyph := '';
      end;
      if FOwnerHint.FIcon = biError then glyph := 'x';
      ctx.beginPath;
      ctx.arc(bodyRect.Left + padL + P.Scale(CIconLogical) div 2,
        bodyRect.Top + padT + P.Scale(CIconLogical) div 2,
        P.Scale(CIconLogical) div 2, 0, 2 * Pi, False);
      ctx.fillStyle(TyColorToBGRA(disc));
      ctx.fill;
      P.DrawText(Rect(bodyRect.Left + padL, bodyRect.Top + padT,
        bodyRect.Left + padL + P.Scale(CIconLogical),
        bodyRect.Top + padT + P.Scale(CIconLogical)),
        glyph, S.FontName, fs, 700, TyRGB(255, 255, 255), taCenter, tlCenter, False);
    end;

    contentRect := Rect(bodyRect.Left + padL + iconPx, bodyRect.Top + padT,
      bodyRect.Right - padR, bodyRect.Bottom - P.Scale(S.Padding.Bottom));
    tx := contentRect.Top;

    if FOwnerHint.FTitle <> '' then
    begin
      lh := MeasureLineH(fs + 1, 700, ppi, S.FontName);
      P.DrawText(Rect(contentRect.Left, tx, contentRect.Right, tx + lh),
        FOwnerHint.FTitle, S.FontName, fs + 1, 700, S.TextColor,
        taLeftJustify, tlCenter, False);
      Inc(tx, lh + P.Scale(CGapLogical));
    end;
    if FOwnerHint.FDescription <> '' then
    begin
      lh := MeasureLineH(fs, S.FontWeight, ppi, S.FontName);
      Lines.Text := FOwnerHint.FDescription;
      for i := 0 to Lines.Count - 1 do
      begin
        P.DrawText(Rect(contentRect.Left, tx, contentRect.Right, tx + lh),
          Lines[i], S.FontName, fs, S.FontWeight, S.TextColor,
          taLeftJustify, tlCenter, False);
        Inc(tx, lh);
      end;
    end;

    P.EndPaint;
  finally
    Lines.Free;
    P.Free;
  end;
  ApplyShape;
end;

{ Shape the window: rounded body region OR-combined with the pointer triangle.
  No-op on Wayland (no XShape). }
procedure TTyBalloonWindow.ApplyShape;
var
  S: TTyStyleSet;
  d, cW, cH, bodyTop, bodyBot, tipX: Integer;
  bodyRgn, triRgn: HRGN;
  pts: array[0..2] of TPoint;
begin
  if not HandleAllocated then Exit;
  if TyQtIsWayland then Exit;
  cW := ClientWidth; cH := ClientHeight;
  S := BalloonStyle;
  d := MulDiv(S.BorderRadius, Font.PixelsPerInch, 96) * 2;
  tipX := FPlacement.TipX - FPlacement.Body.Left;

  if FPlacement.Below then
  begin
    bodyTop := FPointerH; bodyBot := cH;
    pts[0] := Point(tipX, 0);
    pts[1] := Point(tipX - FPointerH, FPointerH + 1);
    pts[2] := Point(tipX + FPointerH, FPointerH + 1);
  end
  else
  begin
    bodyTop := 0; bodyBot := cH - FPointerH;
    pts[0] := Point(tipX, cH);
    pts[1] := Point(tipX - FPointerH, cH - FPointerH - 1);
    pts[2] := Point(tipX + FPointerH, cH - FPointerH - 1);
  end;

  if d > 0 then
    bodyRgn := CreateRoundRectRgn(0, bodyTop, cW + 1, bodyBot + 1, d, d)
  else
    bodyRgn := CreateRectRgn(0, bodyTop, cW + 1, bodyBot + 1);
  triRgn := CreatePolygonRgn(pts, 3, LCLType.WINDING);
  CombineRgn(bodyRgn, bodyRgn, triRgn, RGN_OR);
  DeleteObject(triRgn);
  SetWindowRgn(Handle, bodyRgn, True);   // takes ownership of bodyRgn
end;

// ---------------------------------------------------------------------------
// TTyBalloonHint
// ---------------------------------------------------------------------------
constructor TTyBalloonHint.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FIcon := biNone;
  FHideInterval := 4000;
end;

destructor TTyBalloonHint.Destroy;
begin
  HideHint;
  if FTimer <> nil then
    FTimer.OnTimer := nil;   // detach before free so no queued tick re-enters us
  FreeAndNil(FTimer);
  FreeAndNil(FWin);
  inherited Destroy;
end;

function TTyBalloonHint.ActiveModel: TTyStyleModel;
begin
  if FController <> nil then
    Result := FController.Model
  else
    Result := TyDefaultController.Model;
end;

function TTyBalloonHint.ArrowSizeLogical: Integer;
begin
  { Read from the controller that MEASURED this balloon, not from the default one: a hint
    wired to its own controller would otherwise size its wedge off a different theme than the
    body it hangs on. Negative is meaningless -- a theme that sets one gets no wedge, not an
    inverted one. }
  if FController <> nil then
    Result := FController.Metric(TyBalloonArrowSizeVar, TyBalloonArrowSize)
  else
    Result := TyDefaultController.Metric(TyBalloonArrowSizeVar, TyBalloonArrowSize);
  if Result < 0 then Result := 0;
end;

procedure TTyBalloonHint.MeasureBody(APPI: Integer; out ABodyW, ABodyH: Integer);
var
  S: TTyStyleSet;
  Meas: TBitmap;
  fs, titleH, descH, w, maxW, i, iconPx, lh: Integer;
  Lines: TStringList;
begin
  S := ActiveModel.ResolveStyle('TyHint', '', []);
  fs := S.FontSize; if fs <= 0 then fs := 9;
  maxW := 0; titleH := 0; descH := 0;
  Meas := TBitmap.Create;
  Lines := TStringList.Create;
  try
    Meas.SetSize(1, 1);
    Meas.Canvas.Font.Name := TyEffectiveFontName(S.FontName);
    if FTitle <> '' then
    begin
      Meas.Canvas.Font.Size := MulDiv(fs + 1, APPI, 96);
      Meas.Canvas.Font.Style := [fsBold];
      w := Meas.Canvas.TextWidth(FTitle);
      if w > maxW then maxW := w;
      titleH := Meas.Canvas.TextHeight('Ag') + MulDiv(CGapLogical, APPI, 96);
    end;
    if FDescription <> '' then
    begin
      Meas.Canvas.Font.Size := MulDiv(fs, APPI, 96);
      if S.FontWeight >= 600 then Meas.Canvas.Font.Style := [fsBold]
      else Meas.Canvas.Font.Style := [];
      lh := Meas.Canvas.TextHeight('Ag');
      Lines.Text := FDescription;
      if Lines.Count = 0 then Lines.Add('');
      for i := 0 to Lines.Count - 1 do
      begin
        w := Meas.Canvas.TextWidth(Lines[i]);
        if w > maxW then maxW := w;
      end;
      descH := Lines.Count * lh;
    end;
  finally
    Lines.Free;
    Meas.Free;
  end;
  iconPx := 0;
  if FIcon <> biNone then
    iconPx := MulDiv(CIconLogical + 6, APPI, 96);
  ABodyW := maxW + iconPx + MulDiv(S.Padding.Left + S.Padding.Right, APPI, 96);
  ABodyH := titleH + descH + MulDiv(S.Padding.Top + S.Padding.Bottom, APPI, 96);
  if FIcon <> biNone then
    ABodyH := Max(ABodyH, MulDiv(CIconLogical, APPI, 96)
      + MulDiv(S.Padding.Top + S.Padding.Bottom, APPI, 96));
end;

procedure TTyBalloonHint.ShowFor(AControl: TControl);
var
  tl: TPoint;
begin
  tl := AControl.ClientToScreen(Point(0, 0));
  ShowAt(Rect(tl.X, tl.Y, tl.X + AControl.Width, tl.Y + AControl.Height));
end;

procedure TTyBalloonHint.ShowAt(const ATargetScreen: TRect);
var
  ppi, bodyW, bodyH, pointerPx: Integer;
  pl: TTyBalloonPlacement;
  winRect: TRect;
begin
  if FWin = nil then
    FWin := TTyBalloonWindow.CreateNew(nil);
  FWin.FOwnerHint := Self;

  ppi := Screen.PixelsPerInch; if ppi <= 0 then ppi := 96;
  MeasureBody(ppi, bodyW, bodyH);
  pointerPx := MulDiv(ArrowSizeLogical, ppi, 96);
  FWin.FPointerH := pointerPx;

  pl := TyBalloonPlacement(ATargetScreen, bodyW, bodyH, pointerPx,
    Screen.Width, Screen.Height);
  FWin.FPlacement := pl;

  // Window rect = body plus the pointer strip on the pointer side.
  if pl.Below then
    winRect := Rect(pl.Body.Left, pl.Body.Top - pointerPx, pl.Body.Right, pl.Body.Bottom)
  else
    winRect := Rect(pl.Body.Left, pl.Body.Top, pl.Body.Right, pl.Body.Bottom + pointerPx);

  FWin.SetBounds(winRect.Left, winRect.Top,
    winRect.Right - winRect.Left, winRect.Bottom - winRect.Top);
  FWin.Show;
  FWin.SetBounds(winRect.Left, winRect.Top,
    winRect.Right - winRect.Left, winRect.Bottom - winRect.Top);
  FWin.Invalidate;

  if FHideInterval > 0 then
  begin
    if FTimer = nil then
    begin
      FTimer := TTimer.Create(nil);
      FTimer.OnTimer := @TimerFire;
    end;
    FTimer.Enabled := False;
    FTimer.Interval := FHideInterval;
    FTimer.Enabled := True;
  end;
end;

procedure TTyBalloonHint.HideHint;
begin
  if FTimer <> nil then FTimer.Enabled := False;
  if (FWin <> nil) and FWin.Visible then
    FWin.Hide;
end;

procedure TTyBalloonHint.TimerFire(Sender: TObject);
begin
  HideHint;
end;

end.
