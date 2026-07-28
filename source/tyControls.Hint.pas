unit tyControls.Hint;
{$mode objfpc}{$H+}

{ TTyHint — a non-visual component that replaces the native LCL tooltip with a
  themed, rounded hint window (TTyHintWindow) app-wide, by installing it as LCL's
  global HintWindowClass while Active (and not at design time). The hint window
  resolves the 'TyHint' style from the active default controller and paints its
  surface + text via TTyPainter, so every tooltip matches the current .tycss theme.

  Multiple TTyHint instances refcount the install so the original class is only
  restored once the last one is gone.

  Only the pure size geometry (TyHintContentRect) is unit-testable headlessly; the
  on-screen rendering needs a real GUI — verify the look on a real machine. }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, LCLType, LCLIntf,
  tyControls.Types, tyControls.Component, tyControls.Painter, tyControls.Controller;

type
  { The themed hint window. LCL instantiates it via HintWindowClass, so it takes
    no configuration and reads the app-wide default theme (TyDefaultController). }
  TTyHintWindow = class(THintWindow)
  private
    procedure ApplyRoundRegion;
  protected
    procedure Paint; override;
  public
    function CalcHintRect(MaxWidth: Integer; const AHint: string;
      AData: Pointer): TRect; override;
  end;

  { Non-visual installer. Drop one on a form (or create at runtime); while Active
    and not designing, every control's hint uses TTyHintWindow. }
  TTyHint = class(TTyComponent)
  private
    FActive: Boolean;
    FInstalled: Boolean;
    FController: TTyStyleController;
    procedure SetActive(AValue: Boolean);
    procedure Apply;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    { When True (default) the themed hint window is installed app-wide. }
    property Active: Boolean read FActive write SetActive default True;
    { Documentary only — the hint window always resolves via the active default
      controller (LCL owns the window's instantiation, so a per-instance controller
      cannot be threaded through). Kept for design-time clarity. }
    property Controller: TTyStyleController read FController write FController;
  end;

{ Pure geometry: the hint box for text of (ATextW x ATextH) device px, padded by
  the four themed padding sides (already device px). Headless-testable. }
function TyHintContentRect(ATextW, ATextH, APadL, APadT, APadR, APadB: Integer): TRect;

implementation

uses
  tyControls.QtWS, tyControls.PlatformWS;

var
  USavedHintClass: THintWindowClass = nil;
  UInstallCount: Integer = 0;

procedure InstallHintWindow;
begin
  if UInstallCount = 0 then
    USavedHintClass := HintWindowClass;
  Inc(UInstallCount);
  HintWindowClass := TTyHintWindow;
end;

procedure UninstallHintWindow;
begin
  if UInstallCount = 0 then Exit;
  Dec(UInstallCount);
  if UInstallCount = 0 then
  begin
    HintWindowClass := USavedHintClass;
    USavedHintClass := nil;
  end;
end;

// ---------------------------------------------------------------------------
// Pure geometry
// ---------------------------------------------------------------------------
function TyHintContentRect(ATextW, ATextH, APadL, APadT, APadR, APadB: Integer): TRect;
begin
  Result := Rect(0, 0, ATextW + APadL + APadR, ATextH + APadT + APadB);
end;

// ---------------------------------------------------------------------------
// Shared measurement: split AHint on line breaks; report widest line px, total
// height px, and line height, measured with the themed font at APPI.
// ---------------------------------------------------------------------------
procedure MeasureHint(const AHint: string; const AStyle: TTyStyleSet; APPI: Integer;
  ALines: TStrings; out AWidthPx, AHeightPx, ALineHPx: Integer);
var
  Meas: TBitmap;
  i, w, fs: Integer;
begin
  ALines.Text := AHint;              // splits on CR/LF
  if ALines.Count = 0 then ALines.Add('');
  fs := AStyle.FontSize; if fs <= 0 then fs := 9;
  AWidthPx := 0;
  Meas := TBitmap.Create;
  try
    Meas.SetSize(1, 1);
    Meas.Canvas.Font.Name := TyEffectiveFontName(AStyle.FontName);
    Meas.Canvas.Font.Size := MulDiv(fs, APPI, 96);
    if AStyle.FontWeight >= 600 then
      Meas.Canvas.Font.Style := [fsBold]
    else
      Meas.Canvas.Font.Style := [];
    ALineHPx := Meas.Canvas.TextHeight('Ag');
    if ALineHPx < 1 then ALineHPx := 1;
    for i := 0 to ALines.Count - 1 do
    begin
      w := Meas.Canvas.TextWidth(ALines[i]);
      if w > AWidthPx then AWidthPx := w;
    end;
  finally
    Meas.Free;
  end;
  AHeightPx := ALines.Count * ALineHPx;
end;

function HintStyle: TTyStyleSet;
begin
  Result := TyDefaultController.Model.ResolveStyle('TyHint', '', []);
end;

// ---------------------------------------------------------------------------
// TTyHintWindow
// ---------------------------------------------------------------------------
function TTyHintWindow.CalcHintRect(MaxWidth: Integer; const AHint: string;
  AData: Pointer): TRect;
var
  S: TTyStyleSet;
  Lines: TStringList;
  ppi, tw, th, lh: Integer;
begin
  S := HintStyle;
  ppi := Font.PixelsPerInch; if ppi <= 0 then ppi := 96;
  Lines := TStringList.Create;
  try
    MeasureHint(AHint, S, ppi, Lines, tw, th, lh);
  finally
    Lines.Free;
  end;
  Result := TyHintContentRect(tw, th,
    MulDiv(S.Padding.Left,   ppi, 96), MulDiv(S.Padding.Top,    ppi, 96),
    MulDiv(S.Padding.Right,  ppi, 96), MulDiv(S.Padding.Bottom, ppi, 96));
end;

procedure TTyHintWindow.Paint;
var
  P: TTyPainter;
  S: TTyStyleSet;
  Lines: TStringList;
  R, LineRect: TRect;
  ppi, fs, tw, th, lh, i, cW, cH, yOff: Integer;
begin
  S := HintStyle;
  ppi := Font.PixelsPerInch; if ppi <= 0 then ppi := 96;
  fs := S.FontSize; if fs <= 0 then fs := 9;
  R := ClientRect;
  cW := R.Right - R.Left;
  cH := R.Bottom - R.Top;
  // Blend corner gaps outside the rounded fill (and Wayland, where the region is
  // a no-op) with the surface color instead of the default form Color.
  if S.Background.Kind = tfkSolid then
    Color := TyColorToLCL(S.Background.Color);
  P := TTyPainter.Create;
  Lines := TStringList.Create;
  try
    P.BeginPaint(Canvas, R, ppi);
    if tpBackground in S.Present then
      P.FillBackground(Rect(0, 0, cW, cH), S.Background, S.BorderRadius);
    if (tpBorderColor in S.Present) and (S.BorderWidth > 0) then
      P.StrokeBorder(Rect(0, 0, cW, cH), S.BorderRadius, S.BorderWidth, S.BorderColor);
    MeasureHint(Caption, S, ppi, Lines, tw, th, lh);
    yOff := P.Scale(S.Padding.Top);
    for i := 0 to Lines.Count - 1 do
    begin
      LineRect := Rect(P.Scale(S.Padding.Left), yOff + i * lh,
        cW - P.Scale(S.Padding.Right), yOff + (i + 1) * lh);
      P.DrawText(LineRect, Lines[i], S.FontName, fs, S.FontWeight, S.TextColor,
        taLeftJustify, tlCenter, False);
    end;
    P.EndPaint;
  finally
    Lines.Free;
    P.Free;
  end;
  ApplyRoundRegion;
end;

{ Shape the hint window with a rounded region matching the themed radius (scaled
  to device PPI). Re-applied on every Paint so it follows size/PPI/theme changes
  (a hint window is tiny and short-lived, so the redundant re-apply is cheap and
  avoids a stale shape after a theme switch). No-op on Wayland (no XShape) — the
  surface-colored Color keeps square corners clean. }
procedure TTyHintWindow.ApplyRoundRegion;
var
  S: TTyStyleSet;
  d: Integer;
  Rgn: HRGN;
begin
  if not HandleAllocated then Exit;
  if TyIsWayland then Exit;
  S := HintStyle;
  d := MulDiv(S.BorderRadius, Font.PixelsPerInch, 96) * 2;
  if d <= 0 then
  begin
    SetWindowRgn(Handle, 0, True);
    Exit;
  end;
  // +1: CreateRoundRectRgn right/bottom are exclusive. SetWindowRgn takes ownership.
  Rgn := CreateRoundRectRgn(0, 0, Width + 1, Height + 1, d, d);
  SetWindowRgn(Handle, Rgn, True);
end;

// ---------------------------------------------------------------------------
// TTyHint
// ---------------------------------------------------------------------------
constructor TTyHint.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FActive := True;
  FInstalled := False;
  // Runtime-created (not streamed): install now. Streamed instances install in Loaded.
  if not (csLoading in ComponentState) then
    Apply;
end;

destructor TTyHint.Destroy;
begin
  if FInstalled then
  begin
    UninstallHintWindow;
    FInstalled := False;
  end;
  inherited Destroy;
end;

procedure TTyHint.Loaded;
begin
  inherited Loaded;
  Apply;
end;

procedure TTyHint.Apply;
var
  want: Boolean;
begin
  want := FActive and not (csDesigning in ComponentState);
  if want = FInstalled then Exit;
  if want then
    InstallHintWindow
  else
    UninstallHintWindow;
  FInstalled := want;
end;

procedure TTyHint.SetActive(AValue: Boolean);
begin
  if FActive = AValue then Exit;
  FActive := AValue;
  Apply;
end;

end.
