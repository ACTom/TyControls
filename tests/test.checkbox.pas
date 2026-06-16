unit test.checkbox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Forms, Controls, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.CheckBox;
type
  TTyCheckBoxAccess = class(TTyCheckBox)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure DoKeyDown(var Key: Word; Shift: TShiftState);
    function States: TTyStateSet;
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
implementation

procedure TTyCheckBoxAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
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

initialization
  RegisterTest(TCheckBoxTest);
end.
