unit test.fontcascade;
{ Diagnostic + regression for the "skins look font-enlarged" bug. Hypothesis: a skin that
  declares its own TyButton{} rule suppresses the ENTIRE built-in base TyButton layer under
  the default all-or-nothing property cascade — INCLUDING the base's font-size — so the skin
  resolves FontSize=0 and the control falls back to the OS/LCL font (bigger). The base
  --font-size-base var, however, survives (vars merge separately), so a control CAN recover
  the intended size from it. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel, tyControls.Controller, tyControls.Base;
type
  { Exposes the protected ResolveFontSize so the control-level fix can be tested. }
  TFontProbe = class(TTyCustomControl)
  public
    function CallFS(const AStyle: TTyStyleSet): Integer;
  end;

  TFontCascadeTest = class(TTestCase)
  private
    function ThemePath(const AName: string): string;
  published
    procedure TestBaseButtonHasFontSize;
    procedure TestSkinButtonSuppressesBaseFontSize;
    procedure TestSkinStillResolvesFontSizeBaseVar;
    procedure TestControlRecoversBaseFontUnderSkin;
    procedure TestExplicitControlFontStillWins;
  end;

implementation

function TFontProbe.CallFS(const AStyle: TTyStyleSet): Integer;
begin
  Result := ResolveFontSize(AStyle);
end;

function TFontCascadeTest.ThemePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim + AName;
end;

procedure TFontCascadeTest.TestBaseButtonHasFontSize;
{ Pure built-in base (what the app's 'default' theme resolves to): TyButton carries
  font-size: var(--font-size-base) = 9. }
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.SetMode('light');
    s := m.ResolveStyle('TyButton', '', []);
    AssertEquals('base TyButton font-size', 9, s.FontSize);
  finally m.Free; end;
end;

procedure TFontCascadeTest.TestSkinButtonSuppressesBaseFontSize;
{ A file skin (breeze) declares TyButton{} with no font-size → under all-or-nothing cascade
  the base font-size is suppressed → resolved FontSize = 0 (the bug's mechanism). }
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromFile(ThemePath('breeze.tycss'));
    m.SetMode('light');
    s := m.ResolveStyle('TyButton', '', []);
    AssertEquals('skin TyButton font-size (suppressed base)', 0, s.FontSize);
  finally m.Free; end;
end;

procedure TFontCascadeTest.TestSkinStillResolvesFontSizeBaseVar;
{ The recovery path: even though the typeKey rule suppressed font-size, the base
  --font-size-base var survives the skin load, so a control can fall back to it. }
var m: TTyStyleModel;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromFile(ThemePath('breeze.tycss'));
    m.SetMode('light');
    AssertEquals('--font-size-base survives skin load', 9, m.ResolveMetric('--font-size-base', 0));
  finally m.Free; end;
end;

procedure TFontCascadeTest.TestControlRecoversBaseFontUnderSkin;
{ The FIX: with the skin's typeKey rule suppressing font-size (AStyle.FontSize=0) AND an INHERITED
  big OS/system font (ParentFont=True — simulated by a parent with Font.Size 20, which headless is
  0 for a rootless control, hence the parent), the control must recover the theme's --font-size-base
  (9), NOT the inherited 20. OLD behaviour returned 20 (the visible "enlarged" bug); FIXED returns 9.
  A faithfulness guard asserts the inheritance actually took (else the test would be fake-green). }
var c: TTyStyleController; parent, p: TFontProbe; empty: TTyStyleSet;
begin
  c := TTyStyleController.Create(nil);
  parent := TFontProbe.Create(nil);
  try
    c.ThemeFile := ThemePath('breeze.tycss');
    c.Mode := 'light';
    parent.Font.Size := 20;            // the form/system font a real machine carries
    p := TFontProbe.Create(parent);
    p.Parent := parent;               // p inherits the big font, ParentFont stays True (not explicit)
    p.Controller := c;
    empty := Default(TTyStyleSet);     // FontSize = 0 (skin suppressed the base font-size)
    AssertTrue('probe font is inherited (ParentFont)', p.ParentFont);
    AssertEquals('probe inherited the big system font (sim faithful)', 20, p.Font.Size);
    AssertEquals('inherited OS font ignored; theme base font used', 9, p.CallFS(empty));
  finally
    parent.Free;                       // frees the owned child p too
    c.Free;
  end;
end;

procedure TFontCascadeTest.TestExplicitControlFontStillWins;
{ Contract preserved: an EXPLICITLY-set control Font.Size (ParentFont becomes False) still wins
  over the theme base var when the theme omits a font-size for that typeKey. }
var c: TTyStyleController; p: TFontProbe; empty: TTyStyleSet;
begin
  c := TTyStyleController.Create(nil);
  p := TFontProbe.Create(nil);
  try
    c.ThemeFile := ThemePath('breeze.tycss');
    c.Mode := 'light';
    p.Controller := c;
    p.Font.Size := 14;                 // explicit override → ParentFont False
    empty := Default(TTyStyleSet);
    AssertFalse('explicit font clears ParentFont', p.ParentFont);
    AssertEquals('explicit control Font.Size honoured', 14, p.CallFS(empty));
  finally
    p.Free;
    c.Free;
  end;
end;

initialization
  RegisterTest(TFontCascadeTest);
end.
