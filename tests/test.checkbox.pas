unit test.checkbox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, StdCtrls, TypInfo, fpcunit, testregistry, Forms, Controls, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.CheckBox,
  tyControls.ToolBar;
type
  TTyCheckBoxAccess = class(TTyCheckBox)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure DoKeyDown(var Key: Word; Shift: TShiftState);
    function States: TTyStateSet;
    { CalculatePreferredSize is protected; the AutoSize tests must ask it DIRECTLY.
      Going through Width would measure nothing: LCL's AutoSizeDelayed suppresses every
      auto-size while the parent form has no handle, and the headless runner never
      realises one. }
    procedure CallPreferred(out AW, AH: Integer);
    { Expose the protected caption measurement the size floor is derived from. }
    procedure CallMeasure(APPI: Integer; out AW, AH: Integer);
  end;

  TTyRadioAccess = class(TTyRadioButton)
  public
    procedure CallPreferred(out AW, AH: Integer);
    procedure CallMeasure(APPI: Integer; out AW, AH: Integer);
  end;

  TCheckBoxFontAccess = class(TTyCheckBox)
  public
    function RFS: Integer;        // ResolveFontSize(CurrentStyle)
    function StyleFontSize: Integer; // CurrentStyle.FontSize
  end;

  TCheckBoxTest = class(TTestCase)
  private
    FChangeCount: Integer;       // generic OnChange counter (checkbox)
    FRadioACount: Integer;       // radio A OnChange counter
    FRadioBCount: Integer;       // radio B OnChange counter
    procedure HChange(Sender: TObject);
    procedure HRadioA(Sender: TObject);
    procedure HRadioB(Sender: TObject);
  published
    procedure TestTypeKey;
    procedure TestDefaultSize;
    procedure TestClickTogglesChecked;
    procedure TestPaintSmoke;
    procedure TestDrawFrameOpacityApplied;
    procedure TestDisabledClickIgnored;
    procedure TestCheckBoxShadowLocalRectAtOffset;
    procedure TestSpaceTogglesChecked;
    procedure TestDisabledSpaceNoToggle;
    procedure TestFontSizeResolvesReadableWhenThemeOmitsIt;
    procedure TestFontSizeHonorsControlFontWhenThemeOmitsIt;
    procedure TestCheckedEntersActiveState;
    procedure TestCheckedBoxAccentWhiteGlyphCaptionNormal;
    procedure TestBoxPaddingShiftsBoxRight;
    procedure TestCheckBoxOnChangeFires;
    procedure TestRadioOnChangeAndSiblings;
  end;

  TCheckBoxTriStateTest = class(TTestCase)
  private
    FChangeCount: Integer;
    procedure HChange(Sender: TObject);
  published
    procedure TestClickCycleNoGrayed;
    procedure TestClickCycleAllowGrayed;
    procedure TestCheckedDerivedFromState;
    procedure TestSetCheckedMapsState;
    procedure TestGrayedEntersActiveState;
    procedure TestOnChangeFiresOnDirectStateSet;
    procedure TestGrayedRendersIndeterminateGlyph;
    procedure TestAllowGrayedFalseStillAllowsProgrammaticGrayed;
  end;

  { A skin may legitimately change the font AND the padding, and the checkbox/radio
    indicator size and caption gap are themable metrics too — so a control whose Width
    was hand-fitted to one skin clips its caption under another. These cover the way
    out: AutoSize + a preferred width that mirrors what RenderTo actually lays out. }
  TCheckBoxAutoSizeTest = class(TTestCase)
  published
    procedure TestAutoSizeIsPublished;
    procedure TestPreferredWidthGrowsWithCaption;
    procedure TestPreferredWidthIncludesIndicatorAndGap;
    procedure TestRoomierThemeWidensPreferredWidth;
    procedure TestBiggerIndicatorMetricWidensPreferredWidth;
    procedure TestPreferredHeightIsAlwaysZero;
    procedure TestMnemonicMarkerAddsNoWidth;
    procedure TestRadioPreferredWidthGrowsWithCaption;
    procedure TestRadioPreferredWidthIncludesDotAndGap;
    procedure TestRadioRoomierThemeWidensPreferredWidth;
    procedure TestRadioUsesItsOwnIndicatorMetrics;
    procedure TestRadioPreferredHeightIsAlwaysZero;
  end;

  { A hand-set Height and the theme's --control-height are REQUESTS; what is actually
    possible is decided by the font, the padding and the indicator size, and only the control
    knows all three. On Linux/Qt6 the same 9pt CJK caption resolves a fallback face whose ink
    is taller than Windows', and RenderTo draws the caption tlCenter WITH clipping — so a box
    shorter than the ink loses the BOTTOM of it, which is exactly what the demo's toolbar did
    to 新建/打开. These cover the floor the control publishes so that cannot happen. }
  TCheckBoxSizeFloorTest = class(TTestCase)
  published
    procedure TestMinimumHeightFitsTheCaption;
    procedure TestMinimumWidthIsThePreferredWidth;
    procedure TestMinimumCoversTheIndicatorToo;
    procedure TestMinimumSurvivesAHeightPinningParent;
    procedure TestSmallerFontAndPaddingLowerTheMinimum;
    procedure TestRadioMinimumHeightFitsTheCaption;
    procedure TestRadioMinimumSurvivesAHeightPinningParent;
  end;
implementation

procedure TTyCheckBoxAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyCheckBoxAccess.CallPreferred(out AW, AH: Integer);
begin
  AW := 0; AH := 0;
  CalculatePreferredSize(AW, AH, True);
end;

procedure TTyCheckBoxAccess.CallMeasure(APPI: Integer; out AW, AH: Integer);
begin
  MeasureCaption(APPI, AW, AH);
end;

procedure TTyRadioAccess.CallPreferred(out AW, AH: Integer);
begin
  AW := 0; AH := 0;
  CalculatePreferredSize(AW, AH, True);
end;

procedure TTyRadioAccess.CallMeasure(APPI: Integer; out AW, AH: Integer);
begin
  MeasureCaption(APPI, AW, AH);
end;

procedure TTyCheckBoxAccess.DoKeyDown(var Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;

function TTyCheckBoxAccess.States: TTyStateSet;
begin
  Result := CurrentStates;
end;

function TCheckBoxFontAccess.RFS: Integer; begin Result := ResolveFontSize(CurrentStyle); end;
function TCheckBoxFontAccess.StyleFontSize: Integer; begin Result := CurrentStyle.FontSize; end;

procedure TCheckBoxTest.HChange(Sender: TObject); begin Inc(FChangeCount); end;
procedure TCheckBoxTest.HRadioA(Sender: TObject); begin Inc(FRadioACount); end;
procedure TCheckBoxTest.HRadioB(Sender: TObject); begin Inc(FRadioBCount); end;

procedure TCheckBoxTest.TestTypeKey;
var
  C: TTyCheckBox;
begin
  C := TTyCheckBox.Create(nil);
  try
    AssertEquals('TyCheckBox', (C as ITyStyleable).GetStyleTypeKey);
  finally
    C.Free;
  end;
end;

procedure TCheckBoxTest.TestClickTogglesChecked;
var
  F: TCustomForm;
  C: TTyCheckBox;
begin
  F := TCustomForm.CreateNew(nil);
  try
    C := TTyCheckBox.Create(F);
    C.Parent := F;
    AssertFalse('starts unchecked', C.Checked);
    C.Click;
    AssertTrue('checked after first click', C.Checked);
    C.Click;
    AssertFalse('unchecked after second click', C.Checked);
  finally
    F.Free;
  end;
end;

procedure TCheckBoxTest.TestPaintSmoke;
var
  F: TCustomForm;
  C: TTyCheckBoxAccess;
  Bmp: TBitmap;
begin
  F := TCustomForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    C := TTyCheckBoxAccess.Create(F);
    C.Parent := F;
    C.Caption := 'Accept';
    C.Checked := True;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 22);
    C.RenderTo(Bmp.Canvas, Rect(0, 0, 120, 22), 96);
    AssertTrue('checkbox RenderTo executed without exception', True);
  finally
    Bmp.Free;
    F.Free;
  end;
end;

procedure TCheckBoxTest.TestDrawFrameOpacityApplied;
{ Stylesheet: background #FF0000, opacity 0.5. Render over white.
  The theme background styles the BOX (not the whole control), so:
  - a BOX-interior pixel must be a ~50% blend of red over white
    (G and B between 100 and 160 — opacity applied via DrawFrame);
  - a CAPTION-area pixel must stay pure white (no control-wide fill —
    guards the regression where DrawFrame painted S.Background full-width).
  If DrawFrame was not called at all, opacity would not apply and the
  box pixel would be full red (G=0, B=0). }
var
  Ctl: TTyStyleController;
  C: TTyCheckBoxAccess;
  Form: TForm;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  // The control composites onto its parent's background, so the parent must match
  // the white backdrop we render over (in a real app they're the same surface).
  Form.Color := clWhite;
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyCheckBox { opacity: 0.5; background: #FF0000; border-width: 0px; }');
    C := TTyCheckBoxAccess.Create(Form);
    C.Parent := Form;
    C.Controller := Ctl;
    C.Caption := '';
    C.Checked := False;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 22);
    // White backdrop
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 120, 22);
    C.RenderTo(Bmp.Canvas, Rect(0, 0, 120, 22), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Box interior: box is 16px @96ppi at the left edge, vertically
      // centered in 22px -> spans (0,3)-(16,19); probe its middle.
      Px := Reread.GetPixel(8, 11);
      AssertTrue('box opacity: green > 100 (white bleeds through)',  Px.green > 100);
      AssertTrue('box opacity: green < 160 (not fully white)',       Px.green < 160);
      AssertTrue('box opacity: blue > 100 (white bleeds through)',   Px.blue > 100);
      AssertTrue('box opacity: blue < 160 (not fully white)',        Px.blue < 160);
      // Caption area: must remain untouched white (no control-wide fill).
      Px := Reread.GetPixel(60, 11);
      AssertTrue('caption area stays white (R)', Px.red >= 250);
      AssertTrue('caption area stays white (G)', Px.green >= 250);
      AssertTrue('caption area stays white (B)', Px.blue >= 250);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TCheckBoxTest.TestDisabledClickIgnored;
var
  C: TTyCheckBox;
  R: TTyRadioButton;
begin
  C := TTyCheckBox.Create(nil);
  try
    C.Enabled := False;
    C.Click;
    AssertFalse('disabled checkbox click ignored', C.Checked);
  finally
    C.Free;
  end;
  R := TTyRadioButton.Create(nil);
  try
    R.Enabled := False;
    R.Click;
    AssertFalse('disabled radiobutton click ignored', R.Checked);
  finally
    R.Free;
  end;
end;

procedure TCheckBoxTest.TestCheckBoxShadowLocalRectAtOffset;
{ Offset-origin regression: RenderTo must pass a (0,0)-local rect to DrawFrame,
  not the caller's absolute ARect. The painter builds a (W x H) bitmap and blits
  it at ARect.Left/Top; if DrawFrame receives the absolute rect, the shadow is
  drawn at (ARect.Left, ARect.Top) inside the W x H bitmap, shifting it off the
  control and clipping it.

  Theme: zero-blur, zero-offset, opaque red shadow that fills the rounded box
  rect; background fully transparent and border-width 0 (so only the shadow
  paints). Render an 80x28 checkbox at Rect(20,5,100,33) into a 120x40 white
  bitmap.
  - With the bug: shadow shifted by (20,5) and clipped, so the control's local
    interior (host pixels just inside (20,5)) stays white.
  - With the fix: shadow fills the local box rect, so those pixels are red. }
var
  Ctl: TTyStyleController;
  C: TTyCheckBoxAccess;
  Form: TForm;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  X, Y, MaxRedInside: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyCheckBox { shadow: 0px 0px 0px #FF0000FF; border-width: 0px; ' +
      'background: alpha(#000000, 0); }');
    C := TTyCheckBoxAccess.Create(Form);
    C.Parent := Form;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.Caption := '';
    C.Checked := False;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 40);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 120, 40);
    { Render an 80x28 control at a non-zero origin. }
    C.RenderTo(Bmp.Canvas, Rect(20, 5, 100, 33), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      { The 16px box sits at the control's left edge, vertically centred in 28px.
        Probe a host pixel 4px inside the control origin -> (24, 9). The shadow
        fills the box rect, so with the fix this is red; with the bug it is the
        white backdrop. }
      Px := Reread.GetPixel(24, 9);
      AssertTrue('local box interior must be red-dominant (shadow at local rect)',
        (Px.red > 200) and (Px.green < 80) and (Px.blue < 80));

      { Robustness: scan the control rect's interior for the maximum red and
        assert a clearly-red pixel exists somewhere inside the box area. }
      MaxRedInside := 0;
      for Y := 6 to 31 do
        for X := 21 to 99 do
        begin
          Px := Reread.GetPixel(X, Y);
          if (Px.green < 80) and (Px.blue < 80) and (Px.red > MaxRedInside) then
            MaxRedInside := Px.red;
        end;
      AssertTrue('max red intensity inside the control rect > 200', MaxRedInside > 200);

      { The shadow must NOT be translated past the control's right/bottom edge:
        no red pixels should appear beyond x=100 or y=33 (the control's extent),
        which is where a shifted-and-clipped shadow could never reach anyway, but
        more importantly the fill stays within the local box, not pushed outside. }
      AssertTrue('no red leak below the control (host y=37)',
        not ((Reread.GetPixel(24, 37).red > 200) and
             (Reread.GetPixel(24, 37).green < 80)));
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TCheckBoxTest.TestSpaceTogglesChecked;
var F: TCustomForm; C: TTyCheckBoxAccess; K: Word;
begin
  F := TCustomForm.CreateNew(nil);
  try
    C := TTyCheckBoxAccess.Create(F); C.Parent := F;
    AssertFalse('starts unchecked', C.Checked);
    K := VK_SPACE; C.DoKeyDown(K, []);
    AssertTrue('space checked it', C.Checked);
    AssertEquals('space consumed', 0, Integer(K));
  finally F.Free; end;
end;

procedure TCheckBoxTest.TestDisabledSpaceNoToggle;
var F: TCustomForm; C: TTyCheckBoxAccess; K: Word;
begin
  F := TCustomForm.CreateNew(nil);
  try
    C := TTyCheckBoxAccess.Create(F); C.Parent := F; C.Enabled := False;
    K := VK_SPACE; C.DoKeyDown(K, []);
    AssertFalse('disabled: not toggled', C.Checked);
  finally F.Free; end;
end;

procedure TCheckBoxTest.TestFontSizeResolvesReadableWhenThemeOmitsIt;
var C: TCheckBoxFontAccess;
begin
  C := TCheckBoxFontAccess.Create(nil);
  try
    C.Font.PixelsPerInch := 96;
    // Built-in/default skin has no font-size for TyCheckBox -> style size 0 (the bug source).
    AssertEquals('default skin TyCheckBox font-size is 0', 0, C.StyleFontSize);
    // The control must NOT draw with size 0 -> resolves a readable size.
    AssertTrue('effective font size is readable (>0)', C.RFS > 0);
  finally C.Free; end;
end;

procedure TCheckBoxTest.TestFontSizeHonorsControlFontWhenThemeOmitsIt;
var C: TCheckBoxFontAccess;
begin
  C := TCheckBoxFontAccess.Create(nil);
  try
    C.Font.Size := 14;   // OI-set font, theme has no font-size for checkbox
    AssertEquals('control Font.Size honored when theme omits font-size', 14, C.RFS);
  finally C.Free; end;
end;

procedure TCheckBoxTest.TestCheckedEntersActiveState;
{ A checked checkbox must enter tysActive so the theme's :active rule
  (accent fill + white glyph) actually resolves. Unchecked: no active. }
var
  F: TCustomForm;
  C: TTyCheckBoxAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    C := TTyCheckBoxAccess.Create(F); C.Parent := F;
    AssertFalse('unchecked: not active', tysActive in C.States);
    C.Checked := True;
    AssertTrue('checked: enters active', tysActive in C.States);
    C.Checked := False;
    AssertFalse('unchecked again: not active', tysActive in C.States);
  finally
    F.Free;
  end;
end;

procedure TCheckBoxTest.TestCheckedBoxAccentWhiteGlyphCaptionNormal;
{ Stylesheet gives TyCheckBox a known base (white box, dark caption text) and
  :active accent fill + white glyph (mirrors the shipped theme). When checked,
  the :active state must dye ONLY the box:
  - box interior fill -> accent (#3B82F6);
  - check glyph inside the box -> a near-white pixel exists;
  - the CAPTION text colour stays DARK (NOT white) and the CAPTION background
    stays the white backdrop (NOT accent) -> proves box-only. }
var
  Ctl: TTyStyleController;
  C: TTyCheckBoxAccess;
  Form: TForm;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  X, Y: Integer;
  WhiteGlyphFound, DarkCaptionInkFound: Boolean;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    // Base: white box, dark (#101010) caption/glyph ink, no padding, no border.
    // :active: accent (#3B82F6) box fill + white glyph.
    Ctl.LoadThemeCss(
      'TyCheckBox { background: #FFFFFF; color: #101010; border-width: 0px; padding: 0px; font-size: 12px; }' +
      'TyCheckBox:active { background: #3B82F6; color: #FFFFFF; }');
    C := TTyCheckBoxAccess.Create(Form);
    C.Parent := Form;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.Caption := 'XXXX';
    C.Checked := True;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 22);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 120, 22);
    C.RenderTo(Bmp.Canvas, Rect(0, 0, 120, 22), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Box is 16px @96ppi at the left edge, vertically centered in 22px ->
      // spans (0,3)-(16,19). Probe near a corner that the glyph does not cover.
      Px := Reread.GetPixel(2, 5);
      AssertTrue('box fill is accent: blue-dominant',
        (Px.blue > 180) and (Px.red < 120) and (Px.green > 100) and (Px.green < 200));
      AssertEquals('box fill red = accent #3B', $3B, Px.red);
      AssertEquals('box fill green = accent #82', $82, Px.green);
      AssertEquals('box fill blue = accent #F6', $F6, Px.blue);

      // White glyph: somewhere inside the box there must be a near-white pixel
      // (the check mark), which only exists if the glyph ink is white-on-accent.
      WhiteGlyphFound := False;
      for Y := 4 to 18 do
        for X := 2 to 14 do
        begin
          Px := Reread.GetPixel(X, Y);
          if (Px.red > 230) and (Px.green > 230) and (Px.blue > 230) then
            WhiteGlyphFound := True;
        end;
      AssertTrue('white check glyph present inside accent box', WhiteGlyphFound);

      // Caption area (x >= box.Right + gap). The caption background must stay
      // the white backdrop (NOT accent) and the caption text ink must stay DARK
      // (NOT white) -> :active did not bleed into the caption.
      for X := 24 to 119 do
        for Y := 0 to 21 do
        begin
          Px := Reread.GetPixel(X, Y);
          // No accent-blue fill anywhere in the caption strip.
          AssertFalse('caption strip free of accent fill',
            (Px.blue > 180) and (Px.red < 120) and (Px.green < 200) and (Px.green > 100));
        end;
      // The dark caption ink must still render (text not whitened away).
      DarkCaptionInkFound := False;
      for X := 24 to 119 do
        for Y := 0 to 21 do
        begin
          Px := Reread.GetPixel(X, Y);
          if (Px.red < 80) and (Px.green < 80) and (Px.blue < 80) then
            DarkCaptionInkFound := True;
        end;
      AssertTrue('dark caption text ink present (caption NOT whitened)', DarkCaptionInkFound);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TCheckBoxTest.TestBoxPaddingShiftsBoxRight;
{ padding:4px must inset the box's left edge by ~Scale(4). With a coloured box
  fill and a transparent left margin, the leftmost coloured column moves from
  x=0 (no padding) to x=4 (padding:4px @96ppi). }
var
  Ctl: TTyStyleController;
  C: TTyCheckBoxAccess;
  Form: TForm;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  X, Y, FirstFillX: Integer;
  RowHasFill: Boolean;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    // Solid accent box (checked -> :active fill), padding 4px, no border.
    Ctl.LoadThemeCss(
      'TyCheckBox { background: #FFFFFF; color: #101010; border-width: 0px; padding: 4px; }' +
      'TyCheckBox:active { background: #3B82F6; color: #FFFFFF; }');
    C := TTyCheckBoxAccess.Create(Form);
    C.Parent := Form;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.Caption := '';
    C.Checked := True;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 30);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 120, 30);
    C.RenderTo(Bmp.Canvas, Rect(0, 0, 120, 30), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Find the leftmost column that contains any accent-blue fill pixel.
      FirstFillX := -1;
      for X := 0 to 40 do
      begin
        RowHasFill := False;
        for Y := 0 to 29 do
        begin
          Px := Reread.GetPixel(X, Y);
          if (Px.blue > 180) and (Px.red < 120) then
            RowHasFill := True;
        end;
        if RowHasFill then
        begin
          FirstFillX := X;
          Break;
        end;
      end;
      AssertTrue('box fill found', FirstFillX >= 0);
      // padding:4px @96ppi -> box left inset ~4 (allow 1px AA tolerance).
      AssertTrue('box left edge shifted right by ~Scale(4)',
        (FirstFillX >= 3) and (FirstFillX <= 5));
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TCheckBoxTest.TestCheckBoxOnChangeFires;
{ OnChange fires once when Checked actually changes; setting the SAME value does
  NOT fire (the early-out guard); Click toggles and fires. }
var
  F: TCustomForm;
  C: TTyCheckBox;
begin
  F := TCustomForm.CreateNew(nil);
  try
    C := TTyCheckBox.Create(F);
    C.Parent := F;
    C.OnChange := @HChange;        // fails to compile until OnChange is published

    FChangeCount := 0;
    C.Checked := True;
    AssertEquals('Checked:=True fires once', 1, FChangeCount);

    FChangeCount := 0;
    C.Checked := True;             // same value -> no change, no fire
    AssertEquals('Checked:=True again (same) does not fire', 0, FChangeCount);

    FChangeCount := 0;
    C.Click;                       // True -> False, fires once
    AssertEquals('Click toggled off fires once', 1, FChangeCount);
    AssertFalse('Click toggled it off', C.Checked);
  finally
    F.Free;
  end;
end;

procedure TCheckBoxTest.TestRadioOnChangeAndSiblings;
{ Checking radio B fires B.OnChange AND the previously-checked sibling A fires its
  own OnChange (it became unchecked via UncheckSiblings). }
var
  F: TCustomForm;
  A, B: TTyRadioButton;
begin
  F := TCustomForm.CreateNew(nil);
  try
    A := TTyRadioButton.Create(F); A.Parent := F;
    B := TTyRadioButton.Create(F); B.Parent := F;
    A.OnChange := @HRadioA;        // fails to compile until OnChange is published
    B.OnChange := @HRadioB;

    FRadioACount := 0;
    A.Checked := True;
    AssertEquals('A checked fires A.OnChange once', 1, FRadioACount);

    FRadioACount := 0;
    FRadioBCount := 0;
    B.Checked := True;             // checks B, unchecks A
    AssertTrue('A unchecked by B', not A.Checked);
    AssertTrue('B checked', B.Checked);
    AssertEquals('B checked fires B.OnChange once', 1, FRadioBCount);
    AssertEquals('A unchecked (sibling) fires A.OnChange once', 1, FRadioACount);
  finally
    F.Free;
  end;
end;

procedure TCheckBoxTest.TestDefaultSize;
var C: TTyCheckBox;
begin
  C := TTyCheckBox.Create(nil);
  try
    AssertEquals('default width', 130, C.Width);
    AssertEquals('default height', 22, C.Height);
  finally
    C.Free;
  end;
end;

procedure TCheckBoxTriStateTest.TestClickCycleNoGrayed;
var cb: TTyCheckBox;
begin
  cb := TTyCheckBox.Create(nil);
  try
    cb.AllowGrayed := False;
    AssertEquals('init', Ord(cbUnchecked), Ord(cb.State));
    cb.Click; AssertEquals('->checked', Ord(cbChecked), Ord(cb.State));
    cb.Click; AssertEquals('->unchecked', Ord(cbUnchecked), Ord(cb.State));
  finally cb.Free; end;
end;

procedure TCheckBoxTriStateTest.TestClickCycleAllowGrayed;
var cb: TTyCheckBox;
begin
  cb := TTyCheckBox.Create(nil);
  try
    cb.AllowGrayed := True;
    cb.Click; AssertEquals('->checked', Ord(cbChecked), Ord(cb.State));
    cb.Click; AssertEquals('->grayed', Ord(cbGrayed), Ord(cb.State));
    cb.Click; AssertEquals('->unchecked', Ord(cbUnchecked), Ord(cb.State));
  finally cb.Free; end;
end;

procedure TCheckBoxTriStateTest.TestCheckedDerivedFromState;
var cb: TTyCheckBox;
begin
  cb := TTyCheckBox.Create(nil);
  try
    cb.State := cbChecked;   AssertTrue('checked', cb.Checked);
    cb.State := cbGrayed;    AssertFalse('grayed not Checked', cb.Checked);
    cb.State := cbUnchecked; AssertFalse('unchecked', cb.Checked);
  finally cb.Free; end;
end;

procedure TCheckBoxTriStateTest.TestSetCheckedMapsState;
var cb: TTyCheckBox;
begin
  cb := TTyCheckBox.Create(nil);
  try
    cb.Checked := True;  AssertEquals('True->cbChecked', Ord(cbChecked), Ord(cb.State));
    cb.Checked := False; AssertEquals('False->cbUnchecked', Ord(cbUnchecked), Ord(cb.State));
  finally cb.Free; end;
end;

procedure TCheckBoxTriStateTest.HChange(Sender: TObject); begin Inc(FChangeCount); end;

procedure TCheckBoxTriStateTest.TestGrayedEntersActiveState;
{ Mirrors TestCheckedEntersActiveState: a grayed checkbox must also enter
  tysActive (CurrentStates branches on FState in [cbChecked, cbGrayed]). }
var
  F: TCustomForm;
  C: TTyCheckBoxAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    C := TTyCheckBoxAccess.Create(F); C.Parent := F;
    AssertFalse('unchecked: not active', tysActive in C.States);
    C.State := cbGrayed;
    AssertTrue('grayed: enters active', tysActive in C.States);
    C.State := cbUnchecked;
    AssertFalse('unchecked again: not active', tysActive in C.States);
  finally
    F.Free;
  end;
end;

procedure TCheckBoxTriStateTest.TestOnChangeFiresOnDirectStateSet;
{ OnChange must fire when State is set directly (SetState is the notify point);
  the existing OnChange test only exercised the Checked-setter path. Setting the
  same State value must NOT fire (early-out guard). }
var
  F: TCustomForm;
  C: TTyCheckBox;
begin
  F := TCustomForm.CreateNew(nil);
  try
    C := TTyCheckBox.Create(F); C.Parent := F;
    C.OnChange := @HChange;

    FChangeCount := 0;
    C.State := cbGrayed;
    AssertEquals('State:=cbGrayed fires once', 1, FChangeCount);

    FChangeCount := 0;
    C.State := cbGrayed;             // same value -> no change, no fire
    AssertEquals('State:=cbGrayed again (same) does not fire', 0, FChangeCount);
  finally
    F.Free;
  end;
end;

procedure TCheckBoxTriStateTest.TestGrayedRendersIndeterminateGlyph;
{ A cbGrayed checkbox must draw the indeterminate glyph into the box, so its
  box region must differ from a cbUnchecked one (which draws no glyph). Mirrors
  the pixel-sampling render tests: RenderTo into a TBitmap, reread via
  TBGRABitmap, and compare ink inside the 16px box region (0,3)-(16,19). }
var
  F: TCustomForm;
  C: TTyCheckBoxAccess;
  BmpG, BmpU: TBitmap;
  RG, RU: TBGRABitmap;
  X, Y: Integer;
  DiffFound, GrayedHasInk: Boolean;
  PgPx, PuPx: TBGRAPixel;
begin
  F := TCustomForm.CreateNew(nil);
  BmpG := TBitmap.Create;
  BmpU := TBitmap.Create;
  try
    C := TTyCheckBoxAccess.Create(F);
    C.Parent := F;
    C.Font.PixelsPerInch := 96;
    C.Caption := '';

    BmpG.PixelFormat := pf32bit; BmpG.SetSize(120, 22);
    BmpG.Canvas.Brush.Color := clWhite; BmpG.Canvas.FillRect(0, 0, 120, 22);
    C.State := cbGrayed;
    C.RenderTo(BmpG.Canvas, Rect(0, 0, 120, 22), 96);

    BmpU.PixelFormat := pf32bit; BmpU.SetSize(120, 22);
    BmpU.Canvas.Brush.Color := clWhite; BmpU.Canvas.FillRect(0, 0, 120, 22);
    C.State := cbUnchecked;
    C.RenderTo(BmpU.Canvas, Rect(0, 0, 120, 22), 96);

    RG := TBGRABitmap.Create(BmpG);
    RU := TBGRABitmap.Create(BmpU);
    try
      // Scan the box region: the grayed render must have at least one pixel that
      // differs from the unchecked render (the glyph), and non-background ink.
      DiffFound := False;
      GrayedHasInk := False;
      for Y := 3 to 18 do
        for X := 0 to 15 do
        begin
          PgPx := RG.GetPixel(X, Y);
          PuPx := RU.GetPixel(X, Y);
          if (PgPx.red <> PuPx.red) or (PgPx.green <> PuPx.green) or
             (PgPx.blue <> PuPx.blue) then
            DiffFound := True;
          if (PgPx.red < 230) or (PgPx.green < 230) or (PgPx.blue < 230) then
            GrayedHasInk := True;
        end;
      AssertTrue('grayed box differs from unchecked box (glyph drawn)', DiffFound);
      AssertTrue('grayed box region has ink (not blank white)', GrayedHasInk);
    finally
      RG.Free;
      RU.Free;
    end;
  finally
    BmpG.Free;
    BmpU.Free;
    F.Free;
  end;
end;

procedure TCheckBoxTriStateTest.TestAllowGrayedFalseStillAllowsProgrammaticGrayed;
{ LCL parity: AllowGrayed only gates the Click cycle, not programmatic State
  assignment. cbGrayed must stick even with AllowGrayed=False. }
var cb: TTyCheckBox;
begin
  cb := TTyCheckBox.Create(nil);
  try
    cb.AllowGrayed := False;
    cb.State := cbGrayed;
    AssertEquals('programmatic cbGrayed sticks', Ord(cbGrayed), Ord(cb.State));
  finally cb.Free; end;
end;

{ TCheckBoxAutoSizeTest }

const
  { A fully-specified skin so the numbers below are exact: no padding, a known font size,
    and the two indicator metrics pinned to their built-in values. }
  cCbTightCss =
    ':root { --checkbox-size: 16px; --checkbox-gap: 6px; }' +
    'TyCheckBox { background: #FFFFFF; color: #000000; border-width: 0px; padding: 0px; font-size: 12px; }';
  cRbTightCss =
    ':root { --radio-size: 16px; --radio-gap: 6px; }' +
    'TyRadioButton { background: #FFFFFF; color: #000000; border-width: 0px; padding: 0px; font-size: 12px; }';

procedure TCheckBoxAutoSizeTest.TestAutoSizeIsPublished;
{ AutoSize must be PUBLISHED on both, or it cannot be switched on from a .lfm or the
  object inspector — which is the whole point of the opt-in. }
var
  C: TTyCheckBox;
  R: TTyRadioButton;
begin
  C := TTyCheckBox.Create(nil);
  try
    AssertTrue('TTyCheckBox.AutoSize is published', IsPublishedProp(C, 'AutoSize'));
    AssertFalse('and still defaults to False (purely additive)', C.AutoSize);
  finally C.Free; end;
  R := TTyRadioButton.Create(nil);
  try
    AssertTrue('TTyRadioButton.AutoSize is published', IsPublishedProp(R, 'AutoSize'));
    AssertFalse('and still defaults to False (purely additive)', R.AutoSize);
  finally R.Free; end;
end;

procedure TCheckBoxAutoSizeTest.TestPreferredWidthGrowsWithCaption;
{ The reported case: a caption swapped at RUNTIME (a longer translation pushed in after the
  .lfm sized the control) must make the checkbox want more width, not get ellipsised. }
var
  Ctl: TTyStyleController;
  C: TTyCheckBoxAccess;
  short, long, h1, h2: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(cCbTightCss);
    C := TTyCheckBoxAccess.Create(nil);
    try
      C.Controller := Ctl;
      C.Font.PixelsPerInch := 96;
      C.AutoSize := True;
      C.Caption := 'On';
      C.CallPreferred(short, h1);
      C.Caption := 'Send me the whole newsletter every single morning';
      C.CallPreferred(long, h2);
      AssertTrue(Format('a longer caption wants more width (%d -> %d)', [short, long]),
        long > short);
      AssertEquals('and never proposes a height', 0, h2);
    finally C.Free; end;
  finally Ctl.Free; end;
end;

procedure TCheckBoxAutoSizeTest.TestPreferredWidthIncludesIndicatorAndGap;
{ The preferred width must cover the control's OWN slots, not just the text: RenderTo lays
  out padding | box | gap | caption, so with zero padding and an empty caption the width is
  exactly box + gap. A preferred size that forgot the box would make AutoSize lie and the
  caption would still clip. }
var
  Ctl: TTyStyleController;
  C: TTyCheckBoxAccess;
  wEmpty, wText, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(cCbTightCss);
    C := TTyCheckBoxAccess.Create(nil);
    try
      C.Controller := Ctl;
      C.Font.PixelsPerInch := 96;
      C.Caption := '';
      C.CallPreferred(wEmpty, h);
      AssertEquals('empty caption still reserves box(16) + gap(6)', 22, wEmpty);
      // And the caption is added on top of that slot, never instead of it.
      C.Caption := 'Yes';
      C.CallPreferred(wText, h);
      AssertTrue(Format('a caption adds to the slot (%d -> %d)', [wEmpty, wText]),
        wText > wEmpty);
    finally C.Free; end;
  finally Ctl.Free; end;
end;

procedure TCheckBoxAutoSizeTest.TestRoomierThemeWidensPreferredWidth;
{ THE ACTUAL BUG. The 'xp' skin asks for padding 5px 12px where the default asks 6px, so a
  control hand-fitted to one skin clips under the other. Same control, same caption, two
  themes through one controller: the roomier padding must yield a wider preferred width,
  and the delta must be exactly the extra padding (nothing else changed). }
var
  Ctl: TTyStyleController;
  C: TTyCheckBoxAccess;
  tight, roomy, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    C := TTyCheckBoxAccess.Create(nil);
    try
      C.Controller := Ctl;
      C.Font.PixelsPerInch := 96;
      C.AutoSize := True;
      C.Caption := 'Remember me';

      Ctl.LoadThemeCss(':root { --checkbox-size: 16px; --checkbox-gap: 6px; }' +
        'TyCheckBox { background: #FFFFFF; color: #000000; border-width: 0px; padding: 4px 4px; font-size: 12px; }');
      C.CallPreferred(tight, h);

      Ctl.LoadThemeCss(':root { --checkbox-size: 16px; --checkbox-gap: 6px; }' +
        'TyCheckBox { background: #FFFFFF; color: #000000; border-width: 0px; padding: 4px 30px; font-size: 12px; }');
      C.CallPreferred(roomy, h);

      AssertTrue(Format('a roomier theme widens the checkbox (%d -> %d)', [tight, roomy]),
        roomy > tight);
      // 26px more padding per side = 52px more width.
      AssertEquals('the extra width is exactly the extra padding', tight + 52, roomy);
    finally C.Free; end;
  finally Ctl.Free; end;
end;

procedure TCheckBoxAutoSizeTest.TestBiggerIndicatorMetricWidensPreferredWidth;
{ The box and the gap are skin-tunable (--checkbox-size / --checkbox-gap), so a skin that
  enlarges them must enlarge the preferred width by the same amount — proof the measure
  reads the SAME metrics the paint does instead of the built-in constants. }
var
  Ctl: TTyStyleController;
  C: TTyCheckBoxAccess;
  small, big, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    C := TTyCheckBoxAccess.Create(nil);
    try
      C.Controller := Ctl;
      C.Font.PixelsPerInch := 96;
      C.Caption := 'Enable';

      Ctl.LoadThemeCss(cCbTightCss);
      C.CallPreferred(small, h);

      // box 16 -> 30 (+14), gap 6 -> 10 (+4) = +18, caption untouched.
      Ctl.LoadThemeCss(':root { --checkbox-size: 30px; --checkbox-gap: 10px; }' +
        'TyCheckBox { background: #FFFFFF; color: #000000; border-width: 0px; padding: 0px; font-size: 12px; }');
      C.CallPreferred(big, h);

      AssertEquals('a bigger indicator + gap widens by exactly their delta', small + 18, big);
    finally C.Free; end;
  finally Ctl.Free; end;
end;

procedure TCheckBoxAutoSizeTest.TestPreferredHeightIsAlwaysZero;
{ WIDTH ONLY. 0 is LCL's "no preference on this axis"; proposing a height makes the control
  fight any container that pins one (that is what aborted the demo with
  "TControl.ChangeBounds loop detected"). }
var
  Ctl: TTyStyleController;
  C: TTyCheckBoxAccess;
  w, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(cCbTightCss);
    C := TTyCheckBoxAccess.Create(nil);
    try
      C.Controller := Ctl;
      C.Font.PixelsPerInch := 96;
      C.Caption := '';
      C.CallPreferred(w, h);
      AssertEquals('empty caption: no height preference', 0, h);
      C.Caption := 'A rather long caption indeed';
      C.CallPreferred(w, h);
      AssertEquals('long caption: still no height preference', 0, h);
      // A vertically-padded theme must not start proposing one either.
      Ctl.LoadThemeCss('TyCheckBox { background: #FFFFFF; color: #000000; padding: 20px 4px; font-size: 12px; }');
      C.CallPreferred(w, h);
      AssertEquals('tall padding: still no height preference', 0, h);
    finally C.Free; end;
  finally Ctl.Free; end;
end;

procedure TCheckBoxAutoSizeTest.TestMnemonicMarkerAddsNoWidth;
{ '&' is drawn as an underline, not as a character, so measuring it would over-reserve. }
var
  Ctl: TTyStyleController;
  C: TTyCheckBoxAccess;
  R: TTyRadioAccess;
  plain, marked, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(
      ':root { --checkbox-size: 16px; --checkbox-gap: 6px; --radio-size: 16px; --radio-gap: 6px; }' +
      'TyCheckBox { background: #FFFFFF; color: #000000; border-width: 0px; padding: 0px; font-size: 12px; }' +
      'TyRadioButton { background: #FFFFFF; color: #000000; border-width: 0px; padding: 0px; font-size: 12px; }');
    C := TTyCheckBoxAccess.Create(nil);
    try
      C.Controller := Ctl;
      C.Font.PixelsPerInch := 96;
      C.Caption := 'Save';
      C.CallPreferred(plain, h);
      C.Caption := '&Save';
      C.CallPreferred(marked, h);
      AssertEquals('checkbox: a mnemonic marker adds no width', plain, marked);
    finally C.Free; end;
    R := TTyRadioAccess.Create(nil);
    try
      R.Controller := Ctl;
      R.Font.PixelsPerInch := 96;
      R.Caption := 'Save';
      R.CallPreferred(plain, h);
      R.Caption := '&Save';
      R.CallPreferred(marked, h);
      AssertEquals('radio: a mnemonic marker adds no width', plain, marked);
    finally R.Free; end;
  finally Ctl.Free; end;
end;

procedure TCheckBoxAutoSizeTest.TestRadioPreferredWidthGrowsWithCaption;
var
  Ctl: TTyStyleController;
  R: TTyRadioAccess;
  short, long, h1, h2: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(cRbTightCss);
    R := TTyRadioAccess.Create(nil);
    try
      R.Controller := Ctl;
      R.Font.PixelsPerInch := 96;
      R.AutoSize := True;
      R.Caption := 'A';
      R.CallPreferred(short, h1);
      R.Caption := 'Deliver on the first working day of every month';
      R.CallPreferred(long, h2);
      AssertTrue(Format('a longer caption wants more width (%d -> %d)', [short, long]),
        long > short);
      AssertEquals('and never proposes a height', 0, h2);
    finally R.Free; end;
  finally Ctl.Free; end;
end;

procedure TCheckBoxAutoSizeTest.TestRadioPreferredWidthIncludesDotAndGap;
{ Same slot rule as the checkbox: padding | dot | gap | caption. }
var
  Ctl: TTyStyleController;
  R: TTyRadioAccess;
  wEmpty, wText, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(cRbTightCss);
    R := TTyRadioAccess.Create(nil);
    try
      R.Controller := Ctl;
      R.Font.PixelsPerInch := 96;
      R.Caption := '';
      R.CallPreferred(wEmpty, h);
      AssertEquals('empty caption still reserves dot(16) + gap(6)', 22, wEmpty);
      R.Caption := 'Yes';
      R.CallPreferred(wText, h);
      AssertTrue(Format('a caption adds to the slot (%d -> %d)', [wEmpty, wText]),
        wText > wEmpty);
    finally R.Free; end;
  finally Ctl.Free; end;
end;

procedure TCheckBoxAutoSizeTest.TestRadioRoomierThemeWidensPreferredWidth;
var
  Ctl: TTyStyleController;
  R: TTyRadioAccess;
  tight, roomy, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    R := TTyRadioAccess.Create(nil);
    try
      R.Controller := Ctl;
      R.Font.PixelsPerInch := 96;
      R.AutoSize := True;
      R.Caption := 'Monthly';

      Ctl.LoadThemeCss(':root { --radio-size: 16px; --radio-gap: 6px; }' +
        'TyRadioButton { background: #FFFFFF; color: #000000; border-width: 0px; padding: 4px 4px; font-size: 12px; }');
      R.CallPreferred(tight, h);

      Ctl.LoadThemeCss(':root { --radio-size: 16px; --radio-gap: 6px; }' +
        'TyRadioButton { background: #FFFFFF; color: #000000; border-width: 0px; padding: 4px 30px; font-size: 12px; }');
      R.CallPreferred(roomy, h);

      AssertTrue(Format('a roomier theme widens the radio (%d -> %d)', [tight, roomy]),
        roomy > tight);
      AssertEquals('the extra width is exactly the extra padding', tight + 52, roomy);
    finally R.Free; end;
  finally Ctl.Free; end;
end;

procedure TCheckBoxAutoSizeTest.TestRadioUsesItsOwnIndicatorMetrics;
{ The radio has its OWN tokens (--radio-size / --radio-gap); it must not borrow the
  checkbox's. Bumping only the checkbox tokens must leave the radio's width alone,
  and bumping the radio tokens must move it. }
var
  Ctl: TTyStyleController;
  R: TTyRadioAccess;
  base, cbOnly, rbBig, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    R := TTyRadioAccess.Create(nil);
    try
      R.Controller := Ctl;
      R.Font.PixelsPerInch := 96;
      R.Caption := 'Weekly';

      Ctl.LoadThemeCss(cRbTightCss);
      R.CallPreferred(base, h);

      // Only the CHECKBOX tokens move -> the radio must be unaffected.
      Ctl.LoadThemeCss(':root { --radio-size: 16px; --radio-gap: 6px; --checkbox-size: 40px; --checkbox-gap: 20px; }' +
        'TyRadioButton { background: #FFFFFF; color: #000000; border-width: 0px; padding: 0px; font-size: 12px; }');
      R.CallPreferred(cbOnly, h);
      AssertEquals('checkbox metrics do not move the radio', base, cbOnly);

      // dot 16 -> 30 (+14), gap 6 -> 10 (+4) = +18.
      Ctl.LoadThemeCss(':root { --radio-size: 30px; --radio-gap: 10px; }' +
        'TyRadioButton { background: #FFFFFF; color: #000000; border-width: 0px; padding: 0px; font-size: 12px; }');
      R.CallPreferred(rbBig, h);
      AssertEquals('its own metrics widen it by exactly their delta', base + 18, rbBig);
    finally R.Free; end;
  finally Ctl.Free; end;
end;

procedure TCheckBoxAutoSizeTest.TestRadioPreferredHeightIsAlwaysZero;
var
  Ctl: TTyStyleController;
  R: TTyRadioAccess;
  w, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(cRbTightCss);
    R := TTyRadioAccess.Create(nil);
    try
      R.Controller := Ctl;
      R.Font.PixelsPerInch := 96;
      R.Caption := '';
      R.CallPreferred(w, h);
      AssertEquals('empty caption: no height preference', 0, h);
      R.Caption := 'A rather long caption indeed';
      R.CallPreferred(w, h);
      AssertEquals('long caption: still no height preference', 0, h);
      Ctl.LoadThemeCss('TyRadioButton { background: #FFFFFF; color: #000000; padding: 20px 4px; font-size: 12px; }');
      R.CallPreferred(w, h);
      AssertEquals('tall padding: still no height preference', 0, h);
    finally R.Free; end;
  finally Ctl.Free; end;
end;

{ TCheckBoxSizeFloorTest }

procedure TCheckBoxSizeFloorTest.TestMinimumHeightFitsTheCaption;
{ The floor covers the ink, and an impossible request is clamped up instead of silently
  cutting the bottom off the caption. }
var
  F: TForm;
  C: TTyCheckBoxAccess;
  tw, th: Integer;
begin
  F := TForm.CreateNew(nil);
  try
    C := TTyCheckBoxAccess.Create(F);
    C.Parent := F;
    C.Font.PixelsPerInch := 96;
    C.Caption := '新建';
    C.CallMeasure(96, tw, th);

    AssertTrue('the height floor covers the measured caption',
      C.Constraints.MinHeight >= th);
    AssertTrue('the width floor covers it too', C.Constraints.MinWidth >= tw);

    { Ask for something impossible; the clamp must win. }
    C.Height := 4;
    C.Width := 4;
    AssertTrue('a too-short request is clamped up', C.Height >= th);
    AssertTrue('a too-narrow request is clamped up', C.Width >= tw);
  finally
    F.Free;
  end;
end;

procedure TCheckBoxSizeFloorTest.TestMinimumWidthIsThePreferredWidth;
{ The floor must REUSE the preferred width rather than re-derive it: two copies of
  "padding + indicator + gap + caption" are two things that can drift apart, and the drift
  would show up as a caption clipped by exactly the term one of them forgot. }
var
  Ctl: TTyStyleController;
  C: TTyCheckBoxAccess;
  pw, ph: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    C := TTyCheckBoxAccess.Create(nil);
    try
      C.Controller := Ctl;
      C.Font.PixelsPerInch := 96;
      Ctl.LoadThemeCss(cCbTightCss);
      C.Caption := 'Enable background sync';
      C.Invalidate;                       // the seam a theme switch arrives on
      C.CallPreferred(pw, ph);
      AssertEquals('the width floor IS the preferred width', pw, C.Constraints.MinWidth);
    finally C.Free; end;
  finally Ctl.Free; end;
end;

procedure TCheckBoxSizeFloorTest.TestMinimumCoversTheIndicatorToo;
{ A checkbox draws a box as well as a caption, and the box is centred on the control — so a
  control shorter than the box clips the box. With the caption's ink deliberately tiny, the
  indicator metric is what has to hold the floor up, and it is a THEME metric, so growing it
  must grow the floor. }
var
  Ctl: TTyStyleController;
  C: TTyCheckBox;
  small, big: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    C := TTyCheckBox.Create(nil);
    try
      C.Controller := Ctl;
      C.Font.PixelsPerInch := 96;
      C.Caption := 'x';
      Ctl.LoadThemeCss(':root { --checkbox-size: 16px; }' +
        'TyCheckBox { background: #FFFFFF; color: #000000; padding: 0px; font-size: 6px; }');
      C.Invalidate;
      small := C.Constraints.MinHeight;
      AssertTrue(Format('the box (16) holds the floor up when the text is tiny (%d)', [small]),
        small >= 16);

      Ctl.LoadThemeCss(':root { --checkbox-size: 40px; }' +
        'TyCheckBox { background: #FFFFFF; color: #000000; padding: 0px; font-size: 6px; }');
      C.Invalidate;
      big := C.Constraints.MinHeight;
      AssertTrue(Format('a bigger indicator raises the floor (%d -> %d)', [small, big]),
        big > small);
    finally C.Free; end;
  finally Ctl.Free; end;
end;

procedure TCheckBoxSizeFloorTest.TestMinimumSurvivesAHeightPinningParent;
{ The floor must NOT reopen the fight that a proposed HEIGHT once started: a child on a
  TTyToolBar proposed its own height, the bar pinned its ButtonHeight back, and LCL aborted
  with "ChangeBounds loop detected" — the demo died at startup. Constraints clamp inside
  SetBounds with no negotiation, so the bar keeps owning the height whenever the height it
  asks for is possible at all. Reaching the end of this test IS the assertion. }
var
  F: TForm;
  Bar: TTyToolBar;
  C: TTyCheckBox;
begin
  F := TForm.CreateNew(nil);
  try
    Bar := TTyToolBar.Create(F);
    Bar.Parent := F;
    Bar.ButtonHeight := 40;            // comfortably above any caption's needs
    C := TTyCheckBox.Create(Bar);
    C.Parent := Bar;
    C.Caption := '新建';
    C.AutoSize := True;
    Bar.ButtonHeight := 41;            // a loop would abort the process here
    AssertTrue('the bar asks for a height the floor can honour',
      C.Constraints.MinHeight <= 40);
  finally
    F.Free;
  end;
end;

procedure TCheckBoxSizeFloorTest.TestSmallerFontAndPaddingLowerTheMinimum;
{ The floor is DERIVED, not a wall: shrink the font, the padding and the indicator and the
  minimum shrinks with them. That is what makes "override the CSS if you want a smaller
  checkbox" a coherent answer instead of a refusal. }
var
  F: TForm;
  Ctl: TTyStyleController;
  C: TTyCheckBox;
  big, small: Integer;
begin
  F := TForm.CreateNew(nil);
  Ctl := TTyStyleController.Create(nil);
  try
    C := TTyCheckBox.Create(F);
    C.Parent := F;
    C.Controller := Ctl;
    C.Caption := '新建';

    Ctl.LoadThemeCss(':root { --checkbox-size: 30px; }' +
      'TyCheckBox { font-size: 20px; padding: 8px; }');
    C.Invalidate;                      // the seam a theme switch arrives on
    big := C.Constraints.MinHeight;

    Ctl.LoadThemeCss(':root { --checkbox-size: 4px; }' +
      'TyCheckBox { font-size: 8px; padding: 1px; }');
    C.Invalidate;
    small := C.Constraints.MinHeight;

    AssertTrue(Format('a smaller font + padding + indicator lowers the floor (%d -> %d)',
      [big, small]), small < big);
  finally
    Ctl.Free;
    F.Free;
  end;
end;

procedure TCheckBoxSizeFloorTest.TestRadioMinimumHeightFitsTheCaption;
{ Same story on the radio button, whose indicator reads its own --radio-* metrics. }
var
  F: TForm;
  R: TTyRadioAccess;
  tw, th: Integer;
begin
  F := TForm.CreateNew(nil);
  try
    R := TTyRadioAccess.Create(F);
    R.Parent := F;
    R.Font.PixelsPerInch := 96;
    R.Caption := '新建';
    R.CallMeasure(96, tw, th);

    AssertTrue('the height floor covers the measured caption',
      R.Constraints.MinHeight >= th);
    R.Height := 4;
    R.Width := 4;
    AssertTrue('a too-short request is clamped up', R.Height >= th);
    AssertTrue('a too-narrow request is clamped up', R.Width >= tw);
  finally
    F.Free;
  end;
end;

procedure TCheckBoxSizeFloorTest.TestRadioMinimumSurvivesAHeightPinningParent;
{ See TestMinimumSurvivesAHeightPinningParent: reaching the end is the assertion. }
var
  F: TForm;
  Bar: TTyToolBar;
  R: TTyRadioButton;
begin
  F := TForm.CreateNew(nil);
  try
    Bar := TTyToolBar.Create(F);
    Bar.Parent := F;
    Bar.ButtonHeight := 40;
    R := TTyRadioButton.Create(Bar);
    R.Parent := Bar;
    R.Caption := '新建';
    R.AutoSize := True;
    Bar.ButtonHeight := 41;
    AssertTrue('the bar asks for a height the floor can honour',
      R.Constraints.MinHeight <= 40);
  finally
    F.Free;
  end;
end;

initialization
  RegisterTest(TCheckBoxTest);
  RegisterTest(TCheckBoxTriStateTest);
  RegisterTest(TCheckBoxAutoSizeTest);
  RegisterTest(TCheckBoxSizeFloorTest);
end.
