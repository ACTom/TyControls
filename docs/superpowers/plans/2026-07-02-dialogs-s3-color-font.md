# Dialogs S3 Picker Dialogs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A themed Color picker (`TySelectColor` + `TTyColorDialog`) and Font dialog (`TyFontDialog` + `TTyFontDialog`) on the S1/S2 `TTyDialog` foundation, plus the pure color-math they need.

**Architecture:** New `tyControls.ColorMath.pas` (pure, unit-tested: RGB↔HSV, RGB↔CMYK, hex, TColor interop, HSV/hue coordinate maps). New `tyControls.Dialogs.Color.pas`: a single-`FColor`-model dialog with guarded multi-view sync (HSV square + hue bar as `TTyTrackBar`-style windowed child controls; hex/RGB/CMYK/Alpha edits; preview). New `tyControls.Dialogs.Font.pas`: family/size/style/color/preview → LCL `TFont`, reusing `TySelectColor`. Pure logic is headless-tested; per-pixel paint + drag + preview are GUI (real-machine eyeball) — the S2 SelectPath precedent.

**Tech Stack:** Lazarus/FPC, LCL (`TColor`/`TFont`/`TFontStyles`/`Screen.Fonts`), BGRABitmap; builds on `tyControls.Dialogs` (S1/S2), `tyControls.Painter`, `tyControls.Types`, `tyControls.Base` (`TTyCustomControl`), `tyControls.TrackBar` (pattern), and `TTyEdit`/`TTySpinEdit`/`TTyCheckBox`/`TTyListBox`/`TTyButton`/`TTyLabel`. Headless fpcunit.

**Branch:** `feat/dialogs-s3` (checked out). **Spec:** `docs/superpowers/specs/2026-07-02-dialogs-s3-color-font-design.md`.

**Build/test (git-bash, repo root):**
- Lib: `lazbuild tycontrols.lpk 2>&1 | grep -iE "error|fatal"; echo exit ${PIPESTATUS[0]}`
- DT: `lazbuild tycontrols_dt.lpk 2>&1 | grep -iE "error|fatal"; echo exit ${PIPESTATUS[0]}`
- Tests: `lazbuild tests/tytests.lpi >/dev/null 2>&1 && ./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of (run|failures|errors)"`
- **Baseline (S2 merged): 1580 run / 0 failures / 11 errors.** Keep failures 0, errors 11.

## Verified facts (trust these — from code map + adversarial spec verification)
- `TTyColor = type Cardinal` ($AARRGGBB, `tyControls.Types.pas`); `TyRGB`/`TyRGBA`/`TyAlphaOf`/`TyRedOf`/`TyGreenOf`/`TyBlueOf`/`TyColorToLCL`. `TyParseColor` (`tyControls.Css.Values.pas`) parses `#rgb`/`#rrggbb`/`#rrggbbaa` (alpha LAST → top byte). **No HSV/CMYK/hex-format/TColor→TTyColor yet.**
- **No `TTyPointF`** — use RTL `TPointF` (record X,Y: Single) from unit `Types`.
- LCL `Red/Green/Blue` do NOT resolve system colors → `TyColorFromLCL` MUST `RedGreenBlue(ColorToRGB(AColor), r,g,b)` (`Graphics`).
- `TTyCustomControl` (`tyControls.Base.pas`): subclass overrides `function GetStyleTypeKey: string;` + paints by overriding `Paint` → `RenderTo(Canvas, ClientRect, Font.PixelsPerInch)`; in `RenderTo` create `P := TTyPainter.Create; P.BeginPaint(ACanvas, ARect, APPI); …draw via P (incl. per-pixel `P.Bitmap`)… P.EndPaint; P.Free;`. `P.Bitmap: TBGRABitmap` is live ONLY between BeginPaint/EndPaint (EndPaint blits + frees it). `CurrentStyle`/`DrawFrame(P,R,S)` available for themed frame.
- `TTyTrackBar` (`tyControls.TrackBar.pas`) drag: `FDragging: Boolean`; `MouseDown`(mbLeft→FDragging:=True + map + Invalidate), `MouseMove`(if FDragging→map+Invalidate), `MouseUp`(FDragging:=False); LCL auto-captures — no `MouseCapture` call. `OnChange: TNotifyEvent` fired from the value setter.
- `TTySpinEdit`: `Value/MinValue/MaxValue/Increment: Integer`; `OnChange: TNotifyEvent` **fires on programmatic `Value` set if the clamped value changed** (guard needed). `Create(AOwner)`.
- `TTyCheckBox`: `Checked: Boolean`; `OnChange: TNotifyEvent` fires on programmatic change; `Caption`; `Create(AOwner)`.
- `TTyListBox`: `Items: TStringList`; `ItemIndex: Integer`; `OnChange`; `OnDblClick` (inherited).
- Font preview: `TyConfigureTextFont(bmp, name, sizeLogical, weight, ppi)` (public, `tyControls.Painter`) sets name/height/bold — then set `P.Bitmap.FontStyle := P.Bitmap.FontStyle + [fsItalic, fsUnderline, fsStrikeOut]` and draw `P.Bitmap.TextRect(...)`. LCL enum is `fsStrikeOut` (capital O). `TFontStyles = set of (fsBold,fsItalic,fsUnderline,fsStrikeOut)`.

## HARD RULES (S1/S2 lessons)
- NEVER `ShowModal`/`SetDesigning` in a test. Construct-only: build → assert → `Free`. Show→free globals use `try…finally`. `mrOK` casing. Reuse `TyDlgPad`/`TyPlacePrompt`.

---

### Task 1: `tyControls.ColorMath.pas` — pure color math + coordinate maps

**Files:** Create `source/tyControls.ColorMath.pas`; add to `tycontrols.lpk`; Create `tests/test.colormath.pas`; add to `tests/tytests.lpr`.

- [ ] **Step 1: Write the failing test.** Create `tests/test.colormath.pas`:
```pascal
unit test.colormath;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Graphics, fpcunit, testregistry, tyControls.Types, tyControls.ColorMath;
type
  TColorMathTest = class(TTestCase)
  private
    procedure AssertChan(const AMsg: string; AExpected, AActual: Byte; ATol: Integer);
  published
    procedure TestHSVAnchorsExact;
    procedure TestHSVRoundTripSpread;
    procedure TestCMYKRoundTrip;
    procedure TestHexRoundTrip;
    procedure TestColorFromLCLSystemColor;
    procedure TestAreaAndHueMaps;
  end;
implementation

procedure TColorMathTest.AssertChan(const AMsg: string; AExpected, AActual: Byte; ATol: Integer);
begin
  AssertTrue(AMsg + Format(' exp=%d act=%d tol=%d', [AExpected, AActual, ATol]),
    Abs(Integer(AExpected) - Integer(AActual)) <= ATol);
end;

procedure TColorMathTest.TestHSVAnchorsExact;
var h,s,v: Single; c: TTyColor;
begin
  // pure red -> H0 S1 V1 -> byte-exact back
  TyRGBToHSV(TyRGB(255,0,0), h,s,v);
  AssertEquals('red H', 0.0, h, 0.5); AssertEquals('red S', 1.0, s, 0.001); AssertEquals('red V', 1.0, v, 0.001);
  c := TyHSVToRGB(0, 1, 1);
  AssertEquals('red r', 255, TyRedOf(c)); AssertEquals('red g', 0, TyGreenOf(c)); AssertEquals('red b', 0, TyBlueOf(c));
  // green anchor
  c := TyHSVToRGB(120, 1, 1); AssertEquals('grn', Integer(TyRGB(0,255,0)) and $FFFFFF, Integer(c) and $FFFFFF);
  // blue anchor
  c := TyHSVToRGB(240, 1, 1); AssertEquals('blu', Integer(TyRGB(0,0,255)) and $FFFFFF, Integer(c) and $FFFFFF);
  // gray/white/black
  c := TyHSVToRGB(0, 0, 1); AssertEquals('white', $FFFFFF, Integer(c) and $FFFFFF);
  c := TyHSVToRGB(0, 0, 0); AssertEquals('black', $000000, Integer(c) and $FFFFFF);
end;

procedure TColorMathTest.TestHSVRoundTripSpread;
var i: Integer; c, c2: TTyColor; h,s,v: Single;
const SAMPLES: array[0..5] of TTyColor = ($FF3399CC, $FF808080, $FF12A4E7, $FFDE2A5B, $FF7F00FF, $FF00C864);
begin
  for i := 0 to High(SAMPLES) do
  begin
    c := SAMPLES[i];
    TyRGBToHSV(c, h, s, v);
    c2 := TyHSVToRGB(h, s, v);
    AssertChan('r', TyRedOf(c), TyRedOf(c2), 1);
    AssertChan('g', TyGreenOf(c), TyGreenOf(c2), 1);
    AssertChan('b', TyBlueOf(c), TyBlueOf(c2), 1);
  end;
end;

procedure TColorMathTest.TestCMYKRoundTrip;
var cc,mm,yy,kk: Single; c, c2: TTyColor;
begin
  c := TyRGB(31,122,224);
  TyRGBToCMYK(c, cc,mm,yy,kk);
  c2 := TyCMYKToRGB(cc,mm,yy,kk);
  AssertChan('r', 31, TyRedOf(c2), 1); AssertChan('g', 122, TyGreenOf(c2), 1); AssertChan('b', 224, TyBlueOf(c2), 1);
  // black edge: K=1
  TyRGBToCMYK(TyRGB(0,0,0), cc,mm,yy,kk);
  AssertEquals('K=1', 1.0, kk, 0.001); AssertEquals('C0', 0.0, cc, 0.001);
end;

procedure TColorMathTest.TestHexRoundTrip;
begin
  AssertEquals('rgb', '#3399cc', LowerCase(TyColorToHex(TyRGB($33,$99,$CC), False)));
  // RGBA order: alpha LAST, must round-trip through TyParseColor
  AssertEquals('rgba->color', Integer(TyRGBA($33,$99,$CC,$80)),
    Integer(TyParseColor(TyColorToHex(TyRGBA($33,$99,$CC,$80), True))));
end;

procedure TColorMathTest.TestColorFromLCLSystemColor;
var c: TTyColor;
begin
  // a system color must resolve (not garbage) — clWindowText is TFont.Color's default family
  c := TyColorFromLCL(clWindowText, 255);
  AssertEquals('alpha', 255, TyAlphaOf(c));  // resolves without raising; alpha applied
  // a concrete color round-trips through TyColorToLCL
  AssertEquals('rt', Integer(clRed), Integer(TyColorToLCL(TyColorFromLCL(clRed, 255))));
end;

procedure TColorMathTest.TestAreaAndHueMaps;
var sv: TPointF; r: TRect;
begin
  r := Rect(0,0,100,100);
  sv := TyHSVAreaToSV(Point(0,0), r);     AssertEquals('S@topleft',0.0,sv.X,0.001); AssertEquals('V@topleft',1.0,sv.Y,0.001);
  sv := TyHSVAreaToSV(Point(100,100), r); AssertEquals('S@botright',1.0,sv.X,0.001); AssertEquals('V@botright',0.0,sv.Y,0.001);
  AssertEquals('hue top', 0.0, TyHueBarToH(0, r), 0.5);
  AssertEquals('hue bottom', 360.0, TyHueBarToH(100, r), 0.5);
end;

initialization
  RegisterTest(TColorMathTest);
end.
```
Create `source/tyControls.ColorMath.pas` with signatures + stub bodies (compiles, tests fail):
```pascal
unit tyControls.ColorMath;
{$mode objfpc}{$H+}
interface
uses SysUtils, Types, Graphics, tyControls.Types;
procedure TyRGBToHSV(AColor: TTyColor; out H, S, V: Single);
function  TyHSVToRGB(H, S, V: Single; AAlpha: Byte = 255): TTyColor;
procedure TyRGBToCMYK(AColor: TTyColor; out C, M, Y, K: Single);
function  TyCMYKToRGB(C, M, Y, K: Single; AAlpha: Byte = 255): TTyColor;
function  TyColorToHex(AColor: TTyColor; AIncludeAlpha: Boolean = True): string;
function  TyColorFromLCL(AColor: TColor; AAlpha: Byte = 255): TTyColor;
function  TyHSVAreaToSV(const APoint: TPoint; const ARect: TRect): TPointF;
function  TyHueBarToH(AY: Integer; const ARect: TRect): Single;
implementation
procedure TyRGBToHSV(AColor: TTyColor; out H, S, V: Single); begin H:=0;S:=0;V:=0; end;
function  TyHSVToRGB(H, S, V: Single; AAlpha: Byte): TTyColor; begin Result:=TyRGBA(0,0,0,AAlpha); end;
procedure TyRGBToCMYK(AColor: TTyColor; out C, M, Y, K: Single); begin C:=0;M:=0;Y:=0;K:=0; end;
function  TyCMYKToRGB(C, M, Y, K: Single; AAlpha: Byte): TTyColor; begin Result:=TyRGBA(0,0,0,AAlpha); end;
function  TyColorToHex(AColor: TTyColor; AIncludeAlpha: Boolean): string; begin Result:=''; end;
function  TyColorFromLCL(AColor: TColor; AAlpha: Byte): TTyColor; begin Result:=TyRGBA(0,0,0,AAlpha); end;
function  TyHSVAreaToSV(const APoint: TPoint; const ARect: TRect): TPointF; begin Result:=PointF(0,0); end;
function  TyHueBarToH(AY: Integer; const ARect: TRect): Single; begin Result:=0; end;
end.
```
Add the unit to `tycontrols.lpk` (copy a runtime `<Item>`, set Filename/UnitName). Add `test.colormath` to `tests/tytests.lpr` uses.

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement.** Add `Math` to `uses`. Replace the stub bodies:
```pascal
function ClampF(X, Lo, Hi: Single): Single; begin if X<Lo then Result:=Lo else if X>Hi then Result:=Hi else Result:=X; end;

procedure TyRGBToHSV(AColor: TTyColor; out H, S, V: Single);
var r,g,b,mx,mn,d: Single;
begin
  r := TyRedOf(AColor)/255; g := TyGreenOf(AColor)/255; b := TyBlueOf(AColor)/255;
  mx := Max(r, Max(g,b)); mn := Min(r, Min(g,b)); d := mx - mn;
  V := mx;
  if mx = 0 then S := 0 else S := d/mx;
  if d = 0 then H := 0
  else begin
    if mx = r then H := 60 * ((g-b)/d)
    else if mx = g then H := 60 * (((b-r)/d) + 2)
    else H := 60 * (((r-g)/d) + 4);
    if H < 0 then H := H + 360;
  end;
end;

function TyHSVToRGB(H, S, V: Single; AAlpha: Byte): TTyColor;
var c,x,m,r1,g1,b1: Single; seg: Integer;
begin
  H := H - Floor(H/360)*360;   // normalize [0,360)
  S := ClampF(S,0,1); V := ClampF(V,0,1);
  c := V*S; x := c * (1 - Abs(Frac(H/120)*2 - 1));   // (H/60 mod 2 - 1) simplified
  x := c * (1 - Abs((H/60) - 2*Floor(H/120) - 1));    // robust: (H/60) mod 2
  m := V - c; seg := Trunc(H/60) mod 6;
  case seg of
    0: begin r1:=c; g1:=x; b1:=0; end;
    1: begin r1:=x; g1:=c; b1:=0; end;
    2: begin r1:=0; g1:=c; b1:=x; end;
    3: begin r1:=0; g1:=x; b1:=c; end;
    4: begin r1:=x; g1:=0; b1:=c; end;
  else begin r1:=c; g1:=0; b1:=x; end;
  end;
  Result := TyRGBA(Round((r1+m)*255), Round((g1+m)*255), Round((b1+m)*255), AAlpha);
end;

procedure TyRGBToCMYK(AColor: TTyColor; out C, M, Y, K: Single);
var r,g,b: Single;
begin
  r := TyRedOf(AColor)/255; g := TyGreenOf(AColor)/255; b := TyBlueOf(AColor)/255;
  K := 1 - Max(r, Max(g,b));
  if K >= 1 then begin C:=0; M:=0; Y:=0; end
  else begin C := (1-r-K)/(1-K); M := (1-g-K)/(1-K); Y := (1-b-K)/(1-K); end;
end;

function TyCMYKToRGB(C, M, Y, K: Single; AAlpha: Byte): TTyColor;
begin
  Result := TyRGBA(Round(255*(1-ClampF(C,0,1))*(1-ClampF(K,0,1))),
                   Round(255*(1-ClampF(M,0,1))*(1-ClampF(K,0,1))),
                   Round(255*(1-ClampF(Y,0,1))*(1-ClampF(K,0,1))), AAlpha);
end;

function TyColorToHex(AColor: TTyColor; AIncludeAlpha: Boolean): string;
begin  // RGBA order (alpha LAST) — matches TyParseColor, NOT internal $AARRGGBB
  if AIncludeAlpha then
    Result := Format('#%.2x%.2x%.2x%.2x', [TyRedOf(AColor),TyGreenOf(AColor),TyBlueOf(AColor),TyAlphaOf(AColor)])
  else
    Result := Format('#%.2x%.2x%.2x', [TyRedOf(AColor),TyGreenOf(AColor),TyBlueOf(AColor)]);
end;

function TyColorFromLCL(AColor: TColor; AAlpha: Byte): TTyColor;
var r,g,b: Byte;
begin
  RedGreenBlue(ColorToRGB(AColor), r, g, b);   // ColorToRGB resolves system colors first
  Result := TyRGBA(r, g, b, AAlpha);
end;

function TyHSVAreaToSV(const APoint: TPoint; const ARect: TRect): TPointF;
var w,h: Integer;
begin
  w := ARect.Right-ARect.Left; h := ARect.Bottom-ARect.Top;
  if w<=0 then Result.X:=0 else Result.X := ClampF((APoint.X-ARect.Left)/w, 0, 1);
  if h<=0 then Result.Y:=0 else Result.Y := ClampF(1 - (APoint.Y-ARect.Top)/h, 0, 1);
end;

function TyHueBarToH(AY: Integer; const ARect: TRect): Single;
var h: Integer;
begin
  h := ARect.Bottom-ARect.Top;
  if h<=0 then Result:=0 else Result := ClampF((AY-ARect.Top)/h, 0, 1) * 360;
end;
```
(The `x` computation: keep the second, robust line — `x := c * (1 - Abs((H/60) - 2*Floor(H/120) - 1));` — and delete the first `x :=` line; it was shown twice to make the intent explicit. If unsure, the standard `hh := H/60; x := c*(1 - Abs(FMod(hh,2)-1))` with `Math.FMod` is equivalent.)

- [ ] **Step 4: Run, verify pass.** Expected **run 1586 (1580 + 6), failures 0, errors 11.** Lib exit 0, no new warnings (init `out` params + Result to satisfy 5091/5093 if flagged).

- [ ] **Step 5: Commit.**
```bash
git add source/tyControls.ColorMath.pas tests/test.colormath.pas tycontrols.lpk tests/tytests.lpr
git commit -m "$(printf 'feat(dialogs): tyControls.ColorMath — RGB<->HSV/CMYK, hex, TColor interop, HSV/hue maps\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 2: HSV-square + hue-bar child controls — `source/tyControls.Dialogs.Color.pas`

**Files:** Create `source/tyControls.Dialogs.Color.pas`; add to `tycontrols.lpk`; Create `tests/test.dialogs.color.pas`; add to `tests/tytests.lpr`.

These two `TTyCustomControl` subclasses live in the Color dialog unit's INTERFACE (so the form can hold them + tests can construct them). Modeled on `TTyTrackBar`.

- [ ] **Step 1: Write the failing test.** Create `tests/test.dialogs.color.pas`:
```pascal
unit test.dialogs.color;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Graphics, Controls, fpcunit, testregistry,
  tyControls.Types, tyControls.ColorMath, tyControls.Dialogs.Color;
type
  TColorControlsTest = class(TTestCase)
  published
    procedure TestSquareHueRoundTrip;
  end;
implementation
procedure TColorControlsTest.TestSquareHueRoundTrip;
var sq: TTyHSVSquare; hb: TTyHueBar;
begin
  sq := TTyHSVSquare.Create(nil);   // parentless construct-only (TTyCustomControl)
  try
    sq.SetHSV(210, 0.5, 0.8);
    AssertEquals('H', 210.0, sq.Hue, 0.5);
    AssertEquals('S', 0.5, sq.Sat, 0.01);
    AssertEquals('V', 0.8, sq.Val, 0.01);
  finally sq.Free; end;
  hb := TTyHueBar.Create(nil);
  try
    hb.Hue := 300;
    AssertEquals('huebar', 300.0, hb.Hue, 0.5);
  finally hb.Free; end;
end;
initialization
  RegisterTest(TColorControlsTest);
end.
```
(The controls are `TTyCustomControl`s — `Create(nil)` (parentless) is the right ctor; keep them constructible without a parent for the test.)

Create `source/tyControls.Dialogs.Color.pas` with the two control classes (stub paint) so it compiles + the test fails on behavior:
```pascal
unit tyControls.Dialogs.Color;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Graphics, Controls,
  tyControls.Types, tyControls.Base, tyControls.Painter, tyControls.ColorMath;
type
  TTyHSVSquare = class(TTyCustomControl)
  private
    FHue, FSat, FVal: Single;
    FOnChange: TNotifyEvent;
    FDragging: Boolean;
    procedure DoChange;
  protected
    function GetStyleTypeKey: string; override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetHSV(H, S, V: Single);
    property Hue: Single read FHue write FHue;
    property Sat: Single read FSat;
    property Val: Single read FVal;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;
  TTyHueBar = class(TTyCustomControl)
  private
    FHue: Single;
    FOnChange: TNotifyEvent;
    FDragging: Boolean;
    procedure SetHue(AValue: Single);
    procedure DoChange;
  protected
    function GetStyleTypeKey: string; override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    property Hue: Single read FHue write SetHue;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;
implementation
{ stubs — Step 3 fills in }
constructor TTyHSVSquare.Create(AOwner: TComponent); begin inherited Create(AOwner); Width:=180; Height:=180; end;
function TTyHSVSquare.GetStyleTypeKey: string; begin Result := 'TyColorArea'; end;
procedure TTyHSVSquare.DoChange; begin if Assigned(FOnChange) then FOnChange(Self); end;
procedure TTyHSVSquare.SetHSV(H,S,V: Single); begin FHue:=H; FSat:=S; FVal:=V; Invalidate; end;
procedure TTyHSVSquare.Paint; begin end;
procedure TTyHSVSquare.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); begin inherited; end;
procedure TTyHSVSquare.MouseMove(Shift: TShiftState; X,Y: Integer); begin inherited; end;
procedure TTyHSVSquare.MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); begin inherited; end;
constructor TTyHueBar.Create(AOwner: TComponent); begin inherited Create(AOwner); Width:=18; Height:=180; end;
function TTyHueBar.GetStyleTypeKey: string; begin Result := 'TyColorArea'; end;
procedure TTyHueBar.SetHue(AValue: Single); begin if FHue<>AValue then begin FHue:=AValue; Invalidate; DoChange; end; end;
procedure TTyHueBar.DoChange; begin if Assigned(FOnChange) then FOnChange(Self); end;
procedure TTyHueBar.Paint; begin end;
procedure TTyHueBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); begin inherited; end;
procedure TTyHueBar.MouseMove(Shift: TShiftState; X,Y: Integer); begin inherited; end;
procedure TTyHueBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); begin inherited; end;
end.
```
Add the unit to `tycontrols.lpk` + `test.dialogs.color` to `tytests.lpr`.

- [ ] **Step 2: Run, verify fail** (SetHSV works via stub, but the hue-bar `Hue` write + square `SetHSV` are already trivially passing in the stub — so make Step-1 test also assert paint-driven behavior isn't needed; the real Step-3 work is the paint + mouse). NOTE: the property round-trip may already pass on the stub — that's fine; Step 3 adds the real paint/mouse (GUI, untested). Keep this test as the construct + property gate.

- [ ] **Step 3: Implement paint + mouse.** Replace the stub `Paint`/mouse with the TrackBar-style bodies:
```pascal
procedure TTyHSVSquare.Paint;
var P: TTyPainter; bmp: TBGRABitmap; xx,yy,w,h: Integer; s,v: Single; col: TTyColor; ix,iy: Integer;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    bmp := P.Bitmap; w := bmp.Width; h := bmp.Height;
    for yy := 0 to h-1 do
      for xx := 0 to w-1 do
      begin
        s := xx/Max(1,w-1); v := 1 - yy/Max(1,h-1);
        col := TyHSVToRGB(FHue, s, v);
        bmp.SetPixel(xx, yy, TyColorToBGRA(col));   // TyColorToBGRA: see note
      end;
    // indicator ring at (S,V)
    ix := Round(FSat*(w-1)); iy := Round((1-FVal)*(h-1));
    P.StrokeBorder(Rect(ix-5,iy-5,ix+6,iy+6), 6, 2, TyRGB(255,255,255));
    P.EndPaint;
  finally P.Free; end;
end;

procedure TTyHSVSquare.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin inherited MouseDown(Button,Shift,X,Y);
  if Button=mbLeft then begin FDragging:=True; ApplyXY(X,Y); end; end;
procedure TTyHSVSquare.MouseMove(Shift: TShiftState; X,Y: Integer);
begin inherited MouseMove(Shift,X,Y); if FDragging then ApplyXY(X,Y); end;
procedure TTyHSVSquare.MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin inherited MouseUp(Button,Shift,X,Y); if Button=mbLeft then FDragging:=False; end;
// add private ApplyXY:
procedure TTyHSVSquare.ApplyXY(X,Y: Integer);
var sv: TPointF;
begin sv := TyHSVAreaToSV(Point(X,Y), ClientRect); FSat:=sv.X; FVal:=sv.Y; Invalidate; DoChange; end;
```
Hue bar `Paint`: per-pixel rows `bmp.SetPixel(x, y, TyColorToBGRA(TyHSVToRGB(TyHueBarToH(y, ClientRect),1,1)))` + a horizontal indicator at `Round(FHue/360*(h-1))`. Hue bar mouse: `SetHue(TyHueBarToH(Y, ClientRect))` on down/drag.
**`TyColorToBGRA` note:** convert `TTyColor` ($AARRGGBB) to BGRABitmap's `TBGRAPixel` — check `tyControls.Painter`/BGRABitmap for an existing helper (e.g. the painter already converts TTyColor→TBGRAPixel internally); if none is public, add a tiny local `function TyColorToBGRA(c: TTyColor): TBGRAPixel; begin Result := BGRA(TyRedOf(c),TyGreenOf(c),TyBlueOf(c),TyAlphaOf(c)); end;` (uses `BGRABitmapTypes`). VERIFY the exact BGRA constructor + unit.

- [ ] **Step 4: Run, verify pass** (the construct/property test; paint/mouse are GUI). Lib exit 0. Expected **run 1587 (+1)**, failures 0, errors 11.

- [ ] **Step 5: Commit.**
```bash
git add source/tyControls.Dialogs.Color.pas tests/test.dialogs.color.pas tycontrols.lpk tests/tytests.lpr
git commit -m "$(printf 'feat(dialogs): HSV-square + hue-bar child controls (TTyTrackBar-style per-pixel paint + drag)\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 3: `TyColorDialog` — single-model multi-view sync + globals + component

**Files:** Modify `source/tyControls.Dialogs.Color.pas`; Test `tests/test.dialogs.color.pas`.

- [ ] **Step 1: Write the failing test.** Add:
```pascal
  TColorDialogTest = class(TTestCase)
  published
    procedure TestSyncHexToChannels;
    procedure TestSyncRGBToHex;
    procedure TestComponentTwoWay;
  end;
```
```pascal
procedure TColorDialogTest.TestSyncHexToChannels;
var d: TTyColorForm;
begin
  d := TyBuildColorDialog('Pick', TyRGB(0,0,0));
  try
    d.ApplyHexText('#3399CC');
    AssertEquals('R', $33, TyRedOf(d.CurrentColor));
    AssertEquals('G', $99, TyGreenOf(d.CurrentColor));
    AssertEquals('B', $CC, TyBlueOf(d.CurrentColor));
  finally d.Free; end;
end;
procedure TColorDialogTest.TestSyncRGBToHex;
var d: TTyColorForm;
begin
  d := TyBuildColorDialog('Pick', TyRGB(0,0,0));
  try
    d.SetColor(TyRGB($12,$34,$56));
    AssertEquals('hex', '#123456', LowerCase(d.HexText));
  finally d.Free; end;
end;
procedure TColorDialogTest.TestComponentTwoWay;
var comp: TTyColorDialog;
begin
  comp := TTyColorDialog.Create(nil);
  try
    comp.Color := TyRGBA($10,$20,$30,$80);
    AssertEquals('lcl rt', Integer(TyColorToLCL(TyRGB($10,$20,$30))), Integer(comp.LCLColor));
    AssertEquals('alpha', $80, comp.Alpha);
    comp.Alpha := $FF;
    AssertEquals('alpha2', $FF, TyAlphaOf(comp.Color));
    comp.LCLColor := clRed;   // sets RGB, preserves alpha
    AssertEquals('lcl set keeps alpha', $FF, TyAlphaOf(comp.Color));
  finally comp.Free; end;
end;
```
Add `RegisterTest(TColorDialogTest);`.

- [ ] **Step 2: Run, verify fail** (`TTyColorForm`/`TyBuildColorDialog`/`TTyColorDialog` undefined).

- [ ] **Step 3: Implement.** Add to `uses`: `tyControls.Dialogs, tyControls.Edit, tyControls.SpinEdit, tyControls.TyLabel, tyControls.StrConsts`. Also add these resourcestrings to `source/tyControls.StrConsts.pas` (used for the section labels; RGB/CMYK single-letter captions stay literal) and reference them: `rsDlgHex = 'Hex'; rsDlgAlpha = 'Alpha'; rsDlgPreview = 'Preview';`. Then add the form + builder + globals + component. Key shape (the sync is the crux):
```pascal
type
  TTyColorForm = class(TTyDialog)
  private
    FColor: TTyColor;
    FUpdating: Boolean;
    FSquare: TTyHSVSquare; FHue: TTyHueBar;
    FHex: TTyEdit; FR,FG,FB,FA: TTySpinEdit; FC,FM,FY,FK: TTySpinEdit;
    procedure SyncViewsFromColor;       // FColor -> all editors (guarded)
    procedure PickerChanged(Sender: TObject);   // square/hue -> FColor
    procedure ChannelChanged(Sender: TObject);  // any RGB/CMYK/Alpha spin -> FColor
    procedure HexChanged(Sender: TObject);
  public
    function CurrentColor: TTyColor;
    function HexText: string;
    procedure SetColor(AColor: TTyColor);       // public seam (tests)
    procedure ApplyHexText(const AHex: string); // public seam (tests)
  end;
function TyBuildColorDialog(const ACaption: string; ASeed: TTyColor): TTyColorForm;
function TySelectColor(const ACaption: string; var AColor: TTyColor): Boolean; overload;
function TySelectColor(const ACaption: string; var AColor: TColor; var AAlpha: Byte): Boolean; overload;
type
  TTyColorDialog = class(TComponent)
  private
    FColor: TTyColor; FCaption: string;
    function GetLCL: TColor; procedure SetLCL(v: TColor);
    function GetAlpha: Byte; procedure SetAlpha(v: Byte);
  public
    constructor Create(AOwner: TComponent); override;
    function Execute: Boolean;
    property LCLColor: TColor read GetLCL write SetLCL;
  published
    property Caption: string read FCaption write FCaption;
    property Color: TTyColor read FColor write FColor default $FF000000;
    property Alpha: Byte read GetAlpha write SetAlpha default $FF;
  end;
```
Implementation notes for the implementer:
- `SetColor(c)`: `FColor := c; SyncViewsFromColor;`
- `SyncViewsFromColor`: `FUpdating := True; try` set `FR.Value:=TyRedOf(FColor)` … `FA.Value:=TyAlphaOf(FColor)`; compute CMYK via `TyRGBToCMYK` → `FC/FM/FY/FK.Value := Round(x*100)`; `FHex.Text := TyColorToHex(FColor,True)`; `FSquare.SetHSV(...)` from `TyRGBToHSV(FColor)`; `FHue.Hue := H`; update preview `Invalidate`; `finally FUpdating := False; end;`
- Each handler starts `if FUpdating then Exit;` then recomputes `FColor` from its source and calls `SyncViewsFromColor`: `ChannelChanged` reads the RGB spins (or CMYK spins) → `TyRGB`/`TyCMYKToRGB` keeping `FA.Value` as alpha; `HexChanged` → `TyParseColor(FHex.Text)` (ignore if invalid — guard by checking the parse succeeded/nonempty); `PickerChanged` → `TyHSVToRGB(FHue.Hue, FSquare.Sat, FSquare.Val, FA.Value)`.
- Wire `FSquare.OnChange`/`FHue.OnChange`/each spin `OnChange`/`FHex.OnChange` to the handlers in the builder AFTER seeding, and seed via `SetColor(ASeed)`.
- The RGB vs CMYK ambiguity: have RGB spins + CMYK spins each drive `FColor` from their own set on edit (a CMYK edit computes RGB via `TyCMYKToRGB`; an RGB edit via `TyRGB`). `SyncViewsFromColor` refreshes both from `FColor`. This is standard for multi-model pickers.
- `TySelectColor` overloads: build → `ShowModal` (try/finally free) → on mrOK map back (overload 1: `AColor := d.CurrentColor`; overload 2: `AColor := TyColorToLCL(d.CurrentColor); AAlpha := TyAlphaOf(d.CurrentColor)`); seed overload 2 from `TyColorFromLCL(AColor, AAlpha)`.
- Component: `GetLCL := TyColorToLCL(FColor)`; `SetLCL(v)`: `FColor := TyColorFromLCL(v, TyAlphaOf(FColor))`; `GetAlpha := TyAlphaOf(FColor)`; `SetAlpha(v)`: `FColor := TyRGBA(TyRedOf(FColor),TyGreenOf(FColor),TyBlueOf(FColor), v)`; ctor `FColor := $FF000000`; `Execute := TySelectColor(overload1 on FColor)`.
- Lay the editors out in the content area (square + hue at top, then hex, RGB row, CMYK row, Alpha, preview) via `SetBounds`; `AddButton(rsMsgBtnOK, mrOK, True, False)` + Cancel; `AutoSizeToContent`.

- [ ] **Step 4: Run, verify pass.** Expected **run 1590 (+3)**, failures 0, errors 11. Lib exit 0.

- [ ] **Step 5: Commit.**
```bash
git add source/tyControls.Dialogs.Color.pas source/tyControls.StrConsts.pas tests/test.dialogs.color.pas
git commit -m "$(printf 'feat(dialogs): TyColorDialog — single-model multi-view sync + TySelectColor x2 + TTyColorDialog\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 4: Font style maps — pure, tested (in `source/tyControls.Dialogs.Font.pas`)

**Files:** Create `source/tyControls.Dialogs.Font.pas`; add to `tycontrols.lpk`; Create `tests/test.dialogs.font.pas`; add to `tests/tytests.lpr`.

- [ ] **Step 1: Write the failing test.** Create `tests/test.dialogs.font.pas`:
```pascal
unit test.dialogs.font;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Graphics, fpcunit, testregistry, tyControls.Dialogs.Font;
type
  TFontMapTest = class(TTestCase)
  published
    procedure TestStyleRoundTrip;
  end;
implementation
procedure TFontMapTest.TestStyleRoundTrip;
var i: Integer; st, st2: TFontStyles; ch: TTyFontChecks;
begin
  for i := 0 to 15 do
  begin
    st := [];
    if (i and 1)<>0 then Include(st, fsBold);
    if (i and 2)<>0 then Include(st, fsItalic);
    if (i and 4)<>0 then Include(st, fsUnderline);
    if (i and 8)<>0 then Include(st, fsStrikeOut);
    ch := TyFontStyleToChecks(st);
    st2 := TyChecksToFontStyle(ch);
    AssertTrue('rt '+IntToStr(i), st = st2);
  end;
end;
initialization
  RegisterTest(TFontMapTest);
end.
```
Create `source/tyControls.Dialogs.Font.pas` with the record + maps (stub):
```pascal
unit tyControls.Dialogs.Font;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Graphics;
type
  TTyFontChecks = record Bold, Italic, Underline, Strikeout: Boolean; end;
function TyFontStyleToChecks(AStyle: TFontStyles): TTyFontChecks;
function TyChecksToFontStyle(const AChecks: TTyFontChecks): TFontStyles;
implementation
function TyFontStyleToChecks(AStyle: TFontStyles): TTyFontChecks;
begin Result.Bold:=False; Result.Italic:=False; Result.Underline:=False; Result.Strikeout:=False; end;
function TyChecksToFontStyle(const AChecks: TTyFontChecks): TFontStyles;
begin Result := []; end;
end.
```
Add unit to `tycontrols.lpk` + `test.dialogs.font` to `tytests.lpr`.

- [ ] **Step 2: Run, verify fail** (round-trip fails on the stub).

- [ ] **Step 3: Implement the maps** (note `fsStrikeOut` capital O):
```pascal
function TyFontStyleToChecks(AStyle: TFontStyles): TTyFontChecks;
begin
  Result.Bold := fsBold in AStyle; Result.Italic := fsItalic in AStyle;
  Result.Underline := fsUnderline in AStyle; Result.Strikeout := fsStrikeOut in AStyle;
end;
function TyChecksToFontStyle(const AChecks: TTyFontChecks): TFontStyles;
begin
  Result := [];
  if AChecks.Bold then Include(Result, fsBold);
  if AChecks.Italic then Include(Result, fsItalic);
  if AChecks.Underline then Include(Result, fsUnderline);
  if AChecks.Strikeout then Include(Result, fsStrikeOut);
end;
```

- [ ] **Step 4: Run, verify pass.** Expected **run 1591 (+1)**, failures 0, errors 11. Lib exit 0.

- [ ] **Step 5: Commit.**
```bash
git add source/tyControls.Dialogs.Font.pas tests/test.dialogs.font.pas tycontrols.lpk tests/tytests.lpr
git commit -m "$(printf 'feat(dialogs): font style<->checks pure maps (Bold/Italic/Underline/Strikeout)\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 5: `TyFontDialog` — form + globals + component

**Files:** Modify `source/tyControls.Dialogs.Font.pas`; Test `tests/test.dialogs.font.pas`.

- [ ] **Step 1: Write the failing test.** Add:
```pascal
  TFontDialogTest = class(TTestCase)
  published
    procedure TestBuildSeedsChecksAndList;
  end;
```
```pascal
procedure TFontDialogTest.TestBuildSeedsChecksAndList;
var f: TFont; d: TTyFontForm; fams: TStringList;
begin
  f := TFont.Create;
  fams := TStringList.Create;
  try
    f.Name := 'Courier New'; f.Size := 14; f.Style := [fsBold, fsItalic];
    fams.Add('Arial'); fams.Add('Courier New'); fams.Add('Segoe UI');
    d := TyBuildFontDialog('Font', f, fams);   // families injected (no Screen.Fonts dependence)
    try
      AssertEquals('size seeded', 14, d.SizeValue);
      AssertTrue('bold seeded', d.BoldChecked);
      AssertTrue('italic seeded', d.ItalicChecked);
      AssertFalse('underline', d.UnderlineChecked);
      AssertEquals('family count', 3, d.FamilyCount);
      AssertEquals('family selected', 'Courier New', d.SelectedFamily);
    finally d.Free; end;
  finally f.Free; fams.Free; end;
end;
```
Add `RegisterTest(TFontDialogTest);`.

- [ ] **Step 2: Run, verify fail** (`TTyFontForm`/`TyBuildFontDialog` undefined).

- [ ] **Step 3: Implement.** Add to `uses`: `Types, Controls, tyControls.Dialogs, tyControls.ListBox, tyControls.SpinEdit, tyControls.CheckBox, tyControls.Button, tyControls.TyLabel, tyControls.Painter, tyControls.ColorMath, tyControls.Dialogs.Color, tyControls.StrConsts`. Also add these resourcestrings to `source/tyControls.StrConsts.pas` and reference them: `rsDlgFontFamily='Family'; rsDlgFontSize='Size'; rsDlgFontBold='Bold'; rsDlgFontItalic='Italic'; rsDlgFontUnderline='Underline'; rsDlgFontStrike='Strikeout'; rsDlgFontColor='Color'; rsDlgFontSample='AaBbYyZz 0123';`. Then add:
```pascal
type
  TTyFontForm = class(TTyDialog)
  private
    FFont: TFont;                      // working copy (owned)
    FList: TTyListBox; FSize: TTySpinEdit;
    FBold, FItalic, FUnderline, FStrike: TTyCheckBox;
    FColorBtn: TTyButton; FColorValue: TColor;
    procedure ColorBtnClick(Sender: TObject);
  protected
    procedure LayoutContent; override;
    procedure Paint; override;         // draws the preview area
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    destructor Destroy; override;
    procedure SeedFrom(AFont: TFont; AFamilies: TStrings);
    procedure WriteTo(AFont: TFont);   // apply list/size/checks/color -> AFont
    // test seams:
    function SizeValue: Integer; function BoldChecked: Boolean; function ItalicChecked: Boolean;
    function UnderlineChecked: Boolean; function FamilyCount: Integer; function SelectedFamily: string;
  end;
function TyBuildFontDialog(const ACaption: string; AFont: TFont; AFamilies: TStrings): TTyFontForm;
function TyFontDialog(AFont: TFont): Boolean;
type
  TTyFontDialog = class(TComponent)
  private
    FFont: TFont; FCaption: string;
    procedure SetFont(AValue: TFont);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Execute: Boolean;
  published
    property Caption: string read FCaption write FCaption;
    property Font: TFont read FFont write SetFont;
  end;
```
Implementation notes:
- `TyBuildFontDialog`: create `TTyFontForm.CreateNew(Application)`; `Resizable:=True`; `SeedFrom(AFont, AFamilies)`; add OK/Cancel; `AutoSizeToContent`; `LayoutContent`.
- `SeedFrom`: `FList.Items.Assign(AFamilies)`; select `AFont.Name` (ItemIndex); `FSize.Value := AFont.Size` (guard 1..999); seed the four checks from `TyFontStyleToChecks(AFont.Style)`; `FColorValue := AFont.Color`; keep a working `FFont.Assign(AFont)`.
- `WriteTo`: `AFont.Name := SelectedFamily` (if any); `AFont.Size := FSize.Value`; `AFont.Style := TyChecksToFontStyle(<checks>)`; `AFont.Color := FColorValue`.
- `ColorBtnClick`: `var a: Byte; c: TColor; a:=255; c:=FColorValue;` `if TySelectColor(rsDlgFontColor, c, a) then begin FColorValue := c; Invalidate; end;` (reuses the color dialog).
- `Paint`: `inherited Paint;` then draw the preview text in a reserved rect via a `TTyPainter` (BeginPaint → `TyConfigureTextFont(P.Bitmap, SelectedFamily, FSize.Value, IfThen(FBold.Checked,700,400), Font.PixelsPerInch)` → `P.Bitmap.FontStyle := P.Bitmap.FontStyle + <italic/underline/strike from checks>` → `P.Bitmap.TextRect(previewRect, x, y, rsDlgFontSample, ...)` in `FColorValue` → EndPaint). GUI-only (real-machine).
- `LayoutContent`: stretch `FList` + the preview rect to `ContentRect` on resize.
- `TyFontDialog(AFont)`: build (families from `Screen.Fonts`), `ShowModal` try/finally free, on mrOK `d.WriteTo(AFont)`; result = (mr=mrOK).
- Component: `FFont := TFont.Create` in ctor; `SetFont` Assigns; dtor frees; `Execute := TyFontDialog(FFont)`.
- Test seams return the widget values.

- [ ] **Step 4: Run, verify pass.** Expected **run 1592 (+1)**, failures 0, errors 11. Lib exit 0.

- [ ] **Step 5: Commit.**
```bash
git add source/tyControls.Dialogs.Font.pas source/tyControls.StrConsts.pas tests/test.dialogs.font.pas
git commit -m "$(printf 'feat(dialogs): TyFontDialog — family/size/style/color/preview -> TFont + TTyFontDialog\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 6: Design-time registration

**Files:** Modify `designtime/tyControls.Design.pas`.

- [ ] **Step 1: Register.** Add `tyControls.Dialogs.Color, tyControls.Dialogs.Font` to the `uses` clause. Extend the `RegisterComponents('TyControls Dialogs', [...])` call to append `TTyColorDialog, TTyFontDialog`.

- [ ] **Step 2: Build dt.** `lazbuild tycontrols_dt.lpk 2>&1 | grep -iE "error|fatal"; echo exit ${PIPESTATUS[0]}` → exit 0. Runtime suite unchanged (1592/0/11).

- [ ] **Step 3: Commit.**
```bash
git add designtime/tyControls.Design.pas
git commit -m "$(printf 'feat(design): register TTyColorDialog + TTyFontDialog in the TyControls Dialogs palette\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 7: i18n + docs + README + final verify

**Files:** `source/tyControls.StrConsts.pas`, `languages/*`, `docs/controls/dialogs.md`, `README.md`, `README.en.md`.

- [ ] **Step 1: Regenerate .pot.** The `rsDlg*` resourcestrings were already added to `tyControls.StrConsts.pas` in Tasks 3 (`rsDlgHex`/`rsDlgAlpha`/`rsDlgPreview`) and 5 (`rsDlgFontFamily`/`rsDlgFontSize`/`rsDlgFontBold`/`rsDlgFontItalic`/`rsDlgFontUnderline`/`rsDlgFontStrike`/`rsDlgFontColor`/`rsDlgFontSample`). Build both packages; ensure `languages/tyControls.StrConsts.pot` has all 11 new keys (if `lazbuild` doesn't auto-regenerate, add them manually in the existing format — S2 precedent).

- [ ] **Step 2: Add zh_CN .po entries.** Append to `languages/tycontrols.strconsts.zh_CN.po`:
```
#: tycontrols.strconsts.rsdlghex
msgid "Hex"
msgstr "十六进制"
```
(…and: Alpha→"透明度", Preview→"预览", Family→"字体", Size→"字号", Bold→"粗体", Italic→"斜体", Underline→"下划线", Strikeout→"删除线", Color→"颜色", and rsDlgFontSample keep as `AaBbYyZz 0123` — a glyph sample, msgstr = same.)

- [ ] **Step 3: Docs.** Add `## 9. 拾取器对话框（S3）` to `docs/controls/dialogs.md` (Chinese, sibling style): `TySelectColor` (both overloads, HSV+RGB+CMYK+Alpha, `TTyColorDialog` with Color/LCLColor/Alpha) + `TyFontDialog` (`TTyFontDialog`, TFont result). Short code example each.

- [ ] **Step 4: README.** Extend the existing Dialogs bullet in `README.md` + `README.en.md` to mention the color + font pickers (`TySelectColor`/`TyFontDialog`).

- [ ] **Step 5: Final sweep.**
```bash
lazbuild tycontrols.lpk 2>&1 | grep -iE "error|fatal"; echo lib ${PIPESTATUS[0]}
lazbuild tycontrols_dt.lpk 2>&1 | grep -iE "error|fatal"; echo dt ${PIPESTATUS[0]}
lazbuild tests/tytests.lpi >/dev/null 2>&1 && ./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of (run|failures|errors)"
```
Expected: lib/dt exit 0; failures 0; errors 11; run ~1592.

- [ ] **Step 6: Commit.**
```bash
git add languages/ docs/controls/dialogs.md README.md README.en.md
git commit -m "$(printf 'docs+i18n(dialogs): S3 pickers — docs, README, zh_CN catalogs\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

- [ ] **Step 7: Finish the branch.** Use superpowers:finishing-a-development-branch (pre-merge checklist done here). Then a final whole-branch adversarial review before merge.

---

## Notes for the implementer
- **Never `ShowModal`/`SetDesigning` in tests.** Pure math (Task 1) + style maps (Task 4) + the sync seams (`SetColor`/`ApplyHexText`, Task 3) + construct-only builders are the headless-tested surface. Per-pixel paint, mouse drag, live preview, and the font-color launch are GUI — real-machine eyeball (note them at finish, like S2 SelectPath).
- **`TyColorToBGRA`**: verify how the painter converts `TTyColor`→`TBGRAPixel`; reuse the existing helper if public, else a 1-line `BGRA(r,g,b,a)` from `BGRABitmapTypes`. Confirm the unit before using.
- **Re-entrancy guard is load-bearing**: `TTySpinEdit`/`TTyCheckBox`/`TTyEdit` all fire `OnChange` on programmatic set — `SyncViewsFromColor` MUST set `FUpdating:=True` around all the assignments or the handlers recurse.
- **`fsStrikeOut`** — capital O (LCL enum), even though the record field/label is `Strikeout`.
- **Hex hygiene**: `HexChanged` must ignore an unparseable/partial hex (keep last valid `FColor`); `TyParseColor` on a bad string — check it returns a sentinel or guard on length before applying.
- **Baseline** 1580/0/11; cumulative expected run ≈ 1592 (+6/+1/+3/+1/+1). Keep failures 0, errors 11.
