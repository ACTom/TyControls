unit test.glyph;
{ Theme-system v3 · Phase C5: icon-font glyph override. A theme maps a glyph slot to an
  icon-font codepoint via '--glyph-check: "Family" "\e5ca"'; the control renders that glyph
  instead of the built-in vector. Headless-solid coverage: the token PARSE and the icon-vs-
  vector DISPATCH (proven font-independently with a space codepoint, which is blank in every
  font, so a set override erases the vector checkmark). The visual of a real icon glyph is
  font/platform-dependent and needs a real-machine eyeball. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, StdCtrls, BGRABitmap, BGRABitmapTypes,
  fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel, tyControls.Controller,
  tyControls.IconFont, tyControls.CheckBox;
type
  TCbProbe = class(TTyCheckBox)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TGlyphTest = class(TTestCase)
  private
    function BoxInkPixels(const AThemeCss: string): Integer;
  published
    procedure TestParseFamilyAndCodepointBackslash;
    procedure TestParseCodepointNoBackslash;
    procedure TestParseMalformedFails;
    procedure TestParseOnlyFamilyFails;
    procedure TestParseBadCodepointFails;
    procedure TestRawVarReadsToken;
    procedure TestOverrideBypassesVectorGlyph;
  end;

implementation

procedure TCbProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TGlyphTest.TestParseFamilyAndCodepointBackslash;
var fam: string; cp: Cardinal;
begin
  AssertTrue('parses', TyParseGlyphToken('"Segoe MDL2 Assets" "\e73e"', fam, cp));
  AssertEquals('family', 'Segoe MDL2 Assets', fam);
  AssertEquals('codepoint 0xE73E', Integer($E73E), Integer(cp));
end;

procedure TGlyphTest.TestParseCodepointNoBackslash;
var fam: string; cp: Cardinal;
begin
  AssertTrue('parses without a leading backslash', TyParseGlyphToken('"IconFont" "e5ca"', fam, cp));
  AssertEquals('codepoint 0xE5CA', Integer($E5CA), Integer(cp));
end;

procedure TGlyphTest.TestParseMalformedFails;
var fam: string; cp: Cardinal;
begin
  AssertFalse('no quotes -> fail', TyParseGlyphToken('garbage', fam, cp));
end;

procedure TGlyphTest.TestParseOnlyFamilyFails;
var fam: string; cp: Cardinal;
begin
  AssertFalse('one quoted part -> fail', TyParseGlyphToken('"OnlyFamily"', fam, cp));
end;

procedure TGlyphTest.TestParseBadCodepointFails;
var fam: string; cp: Cardinal;
begin
  AssertFalse('non-hex codepoint -> fail', TyParseGlyphToken('"Fam" "\zz"', fam, cp));
end;

procedure TGlyphTest.TestRawVarReadsToken;
var m: TTyStyleModel;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(':root { --glyph-check: "Arial" "\41"; } TyButton { background: #FFFFFF; }');
    AssertEquals('RawVar returns the raw glyph token', '"Arial" "\41"', m.RawVar('--glyph-check'));
    AssertEquals('unset -> empty', '', m.RawVar('--glyph-radio'));
  finally
    m.Free;
  end;
end;

function TGlyphTest.BoxInkPixels(const AThemeCss: string): Integer;
var
  ctrl: TTyStyleController;
  cb: TCbProbe;
  bmp: TBitmap;
  reread: TBGRABitmap;
  px: TBGRAPixel;
  x, y: Integer;
begin
  Result := 0;
  ctrl := TTyStyleController.Create(nil);
  cb := TCbProbe.Create(nil);
  bmp := TBitmap.Create;
  try
    ctrl.LoadThemeCss(AThemeCss);
    cb.Controller := ctrl;
    cb.State := cbChecked;
    cb.Caption := '';
    bmp.SetSize(60, 40);
    cb.Render(bmp.Canvas, Rect(0, 0, 60, 40), 96);
    reread := TBGRABitmap.Create(bmp);
    try
      // The box is filled a distinct colour (red) with a BLACK glyph, so black pixels inside
      // the box interior are the glyph ink only. Box = 16px, left-aligned, vertically centred
      // in the 40-tall control (y 12..28); scan well inside it.
      for y := 15 to 25 do
        for x := 3 to 13 do
        begin
          px := reread.GetPixel(x, y);
          if (px.alpha > 128) and (px.red < 60) and (px.green < 60) and (px.blue < 60) then
            Inc(Result);
        end;
    finally
      reread.Free;
    end;
  finally
    bmp.Free;
    cb.Free;
    ctrl.Free;
  end;
end;

procedure TGlyphTest.TestOverrideBypassesVectorGlyph;
const
  CB = 'TyCheckBox { background: #FF0000; border-width: 0; padding: 0; color: #000000; }';
var inkVector, inkOverride: Integer;
begin
  // No override: the black VECTOR checkmark is drawn -> dark ink pixels in the box.
  inkVector := BoxInkPixels(CB);
  // With a valid override to a SPACE codepoint (blank in every font), the icon path is taken
  // and draws nothing -> the vector checkmark is bypassed, so there is NO ink. This proves
  // the dispatch chose the icon path (font-independently).
  inkOverride := BoxInkPixels(':root { --glyph-check: "Arial" "\20"; } ' + CB);
  AssertTrue('vector checkmark draws ink', inkVector > 0);
  AssertTrue('override bypasses the vector glyph (no ink)', inkOverride < inkVector);
  AssertEquals('override glyph (space) leaves the box empty', 0, inkOverride);
end;

initialization
  RegisterTest(TGlyphTest);
end.
