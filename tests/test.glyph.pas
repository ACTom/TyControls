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
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.StyleModel, tyControls.Controller,
  tyControls.IconFont, tyControls.CheckBox, tyControls.Form, tyControls.SpinEdit,
  tyControls.TreeView;
type
  TCbProbe = class(TTyCheckBox)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TCaptionProbe = class(TTyCaptionButton)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TSpinProbe = class(TTySpinEdit)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TGlyphTest = class(TTestCase)
  private
    function BoxInkPixels(const AThemeCss: string): Integer;
    function CaptionCloseInk(const AThemeCss: string): Integer;
    function SpinUpArrowInk(const AThemeCss: string): Integer;
  published
    procedure TestParseFamilyAndCodepointBackslash;
    procedure TestParseCodepointNoBackslash;
    procedure TestParseMalformedFails;
    procedure TestParseOnlyFamilyFails;
    procedure TestParseBadCodepointFails;
    procedure TestRawVarReadsToken;
    procedure TestOverrideBypassesVectorGlyph;
    procedure TestCaptionGlyphOverrideBypassesVector;
    procedure TestGlyphKindTokenMapping;
    procedure TestSpinEditArrowOverrideBypassesVector;
    procedure TestTheThemeIsWalkedOncePerGlyphToken;
    procedure TestAModelNobodyElseReadsReadsANewGlyphAgain;
    procedure TestARawReadIsNotTheFollowedOne;
    procedure TestATreeRepaintWalksNoneOfTheThemesVariables;
  end;

implementation

procedure TCbProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TCaptionProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TSpinProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
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

function TGlyphTest.CaptionCloseInk(const AThemeCss: string): Integer;
var
  ctrl: TTyStyleController;
  cb: TCaptionProbe;
  bmp: TBitmap;
  reread: TBGRABitmap;
  px: TBGRAPixel;
  x, y: Integer;
begin
  Result := 0;
  ctrl := TTyStyleController.Create(nil);
  cb := TCaptionProbe.Create(nil);
  bmp := TBitmap.Create;
  try
    ctrl.LoadThemeCss(AThemeCss);
    cb.Controller := ctrl;
    cb.Kind := cbkClose;
    bmp.SetSize(46, 32);
    cb.Render(bmp.Canvas, Rect(0, 0, 46, 32), 96);
    reread := TBGRABitmap.Create(bmp);
    try
      // The glyph is centred (18px box in a 46x32 button); count black ink in its core.
      for y := 9 to 23 do
        for x := 16 to 30 do
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

procedure TGlyphTest.TestCaptionGlyphOverrideBypassesVector;
const
  CB = 'TyCaptionButton { background: #FF0000; color: #000000; border-width: 0; }';
var inkVec, inkOv: Integer;
begin
  // Same font-independent dispatch proof for the title-bar close button: a "\20" (space)
  // override erases the vector × glyph.
  inkVec := CaptionCloseInk(CB);
  inkOv := CaptionCloseInk(':root { --glyph-close: "Arial" "\20"; } ' + CB);
  AssertTrue('vector close (x) glyph draws ink', inkVec > 0);
  AssertEquals('override (space) leaves the close button glyphless', 0, inkOv);
end;

procedure TGlyphTest.TestGlyphKindTokenMapping;
begin
  // The derived TyDrawGlyph overload maps each kind to a canonical --glyph-<kind> token.
  AssertEquals('arrow-up',     '--glyph-arrow-up',     TyGlyphKindToken(tgArrowUp));
  AssertEquals('arrow-down',   '--glyph-arrow-down',   TyGlyphKindToken(tgArrowDown));
  AssertEquals('arrow-left',   '--glyph-arrow-left',   TyGlyphKindToken(tgArrowLeft));
  AssertEquals('arrow-right',  '--glyph-arrow-right',  TyGlyphKindToken(tgArrowRight));
  AssertEquals('triangle-up',    '--glyph-triangle-up',    TyGlyphKindToken(tgTriangleUp));
  AssertEquals('triangle-down',  '--glyph-triangle-down',  TyGlyphKindToken(tgTriangleDown));
  AssertEquals('triangle-left',  '--glyph-triangle-left',  TyGlyphKindToken(tgTriangleLeft));
  AssertEquals('triangle-right', '--glyph-triangle-right', TyGlyphKindToken(tgTriangleRight));
  AssertEquals('chevron-down', '--glyph-chevron-down', TyGlyphKindToken(tgChevronDown));
  AssertEquals('check',        '--glyph-check',        TyGlyphKindToken(tgCheck));
  AssertEquals('close',        '--glyph-close',        TyGlyphKindToken(tgClose));
  // Status marks (TTyAlert / TTyNotification) are icon-font-overridable like every other kind.
  AssertEquals('info',         '--glyph-info',         TyGlyphKindToken(tgInfo));
  AssertEquals('success',      '--glyph-success',      TyGlyphKindToken(tgSuccess));
  AssertEquals('warning',      '--glyph-warning',      TyGlyphKindToken(tgWarning));
  AssertEquals('error',        '--glyph-error',        TyGlyphKindToken(tgError));
end;

function TGlyphTest.SpinUpArrowInk(const AThemeCss: string): Integer;
var
  ctrl: TTyStyleController;
  sp: TSpinProbe;
  bmp: TBitmap;
  reread: TBGRABitmap;
  px: TBGRAPixel;
  x, y: Integer;
begin
  Result := 0;
  ctrl := TTyStyleController.Create(nil);
  sp := TSpinProbe.Create(nil);
  bmp := TBitmap.Create;
  try
    ctrl.LoadThemeCss(AThemeCss);
    sp.Controller := ctrl;
    bmp.SetSize(140, 28);
    sp.Render(bmp.Canvas, Rect(0, 0, 140, 28), 96);
    reread := TBGRABitmap.Create(bmp);
    try
      // Up/down arrows live in the ~18px button zone at the right edge; count black ink there.
      for y := 2 to 26 do
        for x := 122 to 139 do
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
    sp.Free;
    ctrl.Free;
  end;
end;

procedure TGlyphTest.TestSpinEditArrowOverrideBypassesVector;
const
  SP = 'TySpinEdit { background: #FF0000; color: #000000; border-width: 0; } ' +
       'TyEdit { background: #FF0000; color: #000000; border-width: 0; }';
var inkVec, inkOv: Integer;
begin
  // Proves the derived TyDrawGlyph overload is wired in a real control: overriding both spin
  // arrows to a space codepoint erases the vector arrows (font-independent dispatch proof).
  inkVec := SpinUpArrowInk(SP);
  //
  // The TOKEN NAMES matter and this test is the only thing that pins them for a real control.
  // A spin button draws tgTriangleUp/Down, so its tokens are --glyph-triangle-*; it drew
  // tgArrowUp/Down until the spinner family moved onto the filled triangle Windows itself
  // uses, and --glyph-arrow-* now reaches nothing here. No shipped theme sets either (the
  // only --glyph-* in themes/ is --glyph-button-gap), so nothing in the tree broke -- but a
  // theme author who HAD overridden --glyph-arrow-up would silently stop being heard, which
  // is why the rename is called out in the changelog.
  inkOv := SpinUpArrowInk(':root { --glyph-triangle-up: "Arial" "\20"; --glyph-triangle-down: "Arial" "\20"; } ' + SP);
  AssertTrue('vector spin arrows draw ink', inkVec > 0);
  AssertEquals('override (space) leaves the spin arrows glyphless', 0, inkOv);
end;

{ #204. Every chevron, check mark and sort mark asks the theme whether an icon-font glyph replaces
  it, and the theme's answer is found once, not on every ask. Finding it walks every variable of
  the theme, about 0.2 ms with the built-in themes, and none of them sets a glyph, so the walk
  always ran to the end. }
procedure TGlyphTest.TestTheThemeIsWalkedOncePerGlyphToken;
var
  m: TTyStyleModel;
  before, i: Integer;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(':root { --glyph-check: "Arial" "\41"; }');
    before := m.TokenLookupsForTest;
    for i := 1 to 10 do
    begin
      AssertEquals('a token the theme sets', '"Arial" "\41"', m.RawVar('--glyph-check'));
      AssertEquals('one it does not', '', m.RawVar('--glyph-radio'));
    end;
    AssertEquals('the theme''s variables are walked once for each token, set or not', 2,
      m.TokenLookupsForTest - before);
    AssertEquals('spelt without the dashes, the same answer', '"Arial" "\41"', m.RawVar('glyph-check'));
  finally
    m.Free;
  end;
end;

{ #204: what was found is the theme's, so a new theme or mode is asked again. With no control in
  between: under a controller, a new theme makes its controls resolve their styles, which drops
  every memo before the test asks for a glyph, and RawVar's own check of the theme version went
  unwatched (#203 had a mutant live that way). Here RawVar is the first read after each change. }
procedure TGlyphTest.TestAModelNobodyElseReadsReadsANewGlyphAgain;
var
  m: TTyStyleModel;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(':root { --glyph-check: "Arial" "\41"; }');
    AssertEquals('"Arial" "\41"', m.RawVar('--glyph-check'));
    AssertEquals('', m.RawVar('--glyph-radio'));
    m.LoadFromCss(':root { --glyph-check: "Arial" "\42"; --glyph-radio: "Arial" "\43"; }');
    AssertEquals('a new theme''s glyph, not the one read before', '"Arial" "\42"',
      m.RawVar('--glyph-check'));
    AssertEquals('one the old theme did not set', '"Arial" "\43"', m.RawVar('--glyph-radio'));
    m.LoadFromCss('@mode light { :root { --glyph-check: "Arial" "\44"; } }' + LineEnding +
                  '@mode dark  { :root { --glyph-check: "Arial" "\45"; } }');
    m.Mode := 'light';
    AssertEquals('the light mode''s glyph', '"Arial" "\44"', m.RawVar('--glyph-check'));
    m.Mode := 'dark';
    AssertEquals('another mode''s glyph', '"Arial" "\45"', m.RawVar('--glyph-check'));
    m.LoadFromCss('TyButton { background: #FFFFFF; }');
    AssertEquals('a theme that sets none: no glyph', '', m.RawVar('--glyph-check'));
  finally
    m.Free;
  end;
end;

{ #204: RawVar answers the text as the theme wrote it, the word token reader (ResolveToken) the
  text a reference leads to. Their answers are kept apart, whichever is asked first. }
procedure TGlyphTest.TestARawReadIsNotTheFollowedOne;
var
  m: TTyStyleModel;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(':root { --icon-a: "Arial" "\41"; --glyph-check: var(--icon-a); ' +
      '--glyph-radio: var(--icon-a); }');
    AssertEquals('precondition: the word token follows the reference', '"Arial" "\41"',
      m.ResolveToken('--glyph-check'));
    AssertEquals('the raw read after it is still the text the theme wrote', 'var(--icon-a)',
      m.RawVar('--glyph-check'));
    AssertEquals('the raw read first', 'var(--icon-a)', m.RawVar('--glyph-radio'));
    AssertEquals('and the word token after it still follows', '"Arial" "\41"',
      m.ResolveToken('--glyph-radio'));
  finally
    m.Free;
  end;
end;

{ #204. A tree draws an expander on every row that has children, and each one asked the theme for
  its glyph override: with the built-in theme, a 400x800 tree whose every row is a parent spent
  8 ms of each paint on it. Nothing on screen changes, so no pixel test can see it. Once a paint
  has asked, the next one walks none of the theme's variables. }
procedure TGlyphTest.TestATreeRepaintWalksNoneOfTheThemesVariables;
var
  ctl: TTyStyleController;
  host: TTyForm;
  tv: TTyTreeView;
  nd: TTyTreeNodeItem;
  bmp: TBitmap;
  i, walks: Integer;
begin
  ctl := TTyStyleController.Create(nil);
  host := TTyForm.CreateNew(nil);
  bmp := TBitmap.Create;
  try
    tv := TTyTreeView.Create(host);
    tv.Parent := host;
    tv.Controller := ctl;
    tv.Font.PixelsPerInch := 96;
    tv.SetBounds(0, 0, 200, 400);
    for i := 0 to 9 do
    begin
      nd := tv.Items.Add(nil, Format('Expanded %d', [i]));
      tv.Items.AddChild(nd, 'child');
      nd.Expanded := True;
      nd := tv.Items.Add(nil, Format('Collapsed %d', [i]));
      tv.Items.AddChild(nd, 'child');
    end;
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(200, 400);
    tv.RenderTo(bmp.Canvas, Rect(0, 0, 200, 400), 96);

    walks := ctl.Model.TokenLookupsForTest;
    tv.RenderTo(bmp.Canvas, Rect(0, 0, 200, 400), 96);
    AssertEquals('a repaint walks none of the theme''s variables', 0,
      ctl.Model.TokenLookupsForTest - walks);
  finally
    bmp.Free;
    host.Free;
    ctl.Free;
  end;
end;

initialization
  RegisterTest(TGlyphTest);
end.
