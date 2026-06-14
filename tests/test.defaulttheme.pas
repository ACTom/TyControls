unit test.defaulttheme;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel, tyControls.DefaultTheme,
  Controls, Graphics, BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.Base, tyControls.Button;
type
  TBuiltinThemeTest = class(TTestCase)
  private
    function NormalizeCss(const S: string): string;
  published
    procedure TestBuiltinMatchesLightTheme;
    procedure TestBuiltinCoversAllTypeKeys;
    procedure TestEmptyModelFallsBackToBuiltin;
    procedure TestUserTypeKeySuppressesBuiltinNoBleed;
    procedure TestUnstyledTypeKeyStillGetsBuiltin;
    procedure TestControlVisibleWithoutTheme;
    procedure TestBuiltinTitleBarTopRoundedTab;
    procedure TestBuiltinFocusRingOnButton;
  end;

  TTyButtonRenderAccess = class(TTyButton)
  public
    procedure DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;
implementation

procedure TTyButtonRenderAccess.DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TBuiltinThemeTest.NormalizeCss(const S: string): string;
{ Robust to line-ending and trailing-whitespace differences. }
var sl: TStringList; i: Integer;
begin
  sl := TStringList.Create;
  try
    sl.Text := S;
    for i := 0 to sl.Count - 1 do
      sl[i] := TrimRight(sl[i]);
    Result := Trim(sl.Text);
  finally
    sl.Free;
  end;
end;

procedure TBuiltinThemeTest.TestBuiltinMatchesLightTheme;
{ The embedded built-in skin must stay identical to themes/light.tycss. }
var
  path: string;
  fileText: TStringList;
begin
  path := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes'
    + PathDelim + 'light.tycss';
  AssertTrue('light.tycss must exist for sync check', FileExists(path));
  fileText := TStringList.Create;
  try
    fileText.LoadFromFile(path);
    AssertEquals('built-in skin must equal themes/light.tycss',
      NormalizeCss(fileText.Text), NormalizeCss(TyBuiltinThemeCss));
  finally
    fileText.Free;
  end;
end;

procedure TBuiltinThemeTest.TestBuiltinCoversAllTypeKeys;
{ Parsing the built-in CSS into a model's user layer must resolve every styled
  typeKey with its key property present. }
var
  m: TTyStyleModel;
  procedure AssertBg(const Key: string; AStates: TTyStateSet);
  begin
    AssertTrue(Key + ' must set Background',
      tpBackground in m.ResolveStyle(Key, '', AStates).Present);
  end;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(TyBuiltinThemeCss);
    AssertBg('TyButton', []);
    AssertBg('TyEdit', []);
    AssertBg('TyCheckBox', []);
    AssertBg('TyRadioButton', []);
    AssertBg('TyPanel', []);
    AssertBg('TyComboBox', []);
    AssertBg('TyScrollBar', []);
    AssertBg('TyTitleBar', []);
    AssertBg('TyListBox', []);
    AssertBg('TyListItem', [tysActive]);
    AssertBg('TyProgressBar', []);
    AssertBg('TyProgressFill', []);
    AssertBg('TyToggleSwitch', [tysActive]);
    AssertBg('TyTrackBar', []);
    AssertBg('TyTrackThumb', []);
    AssertBg('TyTabControl', []);
    AssertBg('TyTab', [tysActive]);
    AssertTrue('TyGroupBox must set BorderColor',
      tpBorderColor in m.ResolveStyle('TyGroupBox', '', []).Present);
    AssertTrue('TyLabel must set TextColor',
      tpTextColor in m.ResolveStyle('TyLabel', '', []).Present);
  finally
    m.Free;
  end;
end;

procedure TBuiltinThemeTest.TestEmptyModelFallsBackToBuiltin;
{ A fresh model with NO theme loaded must resolve the built-in default skin
  (the core fix: controls are visible with zero configuration). }
var
  m: TTyStyleModel;
  s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    s := m.ResolveStyle('TyButton', '', []);
    AssertTrue('empty model: TyButton Background present (built-in)',
      tpBackground in s.Present);
    AssertTrue('empty model: TyButton TextColor present (built-in)',
      tpTextColor in s.Present);
    AssertTrue('empty model: solid background', s.Background.Kind = tfkSolid);
    AssertEquals('built-in surface red', $FF, TyRedOf(s.Background.Color));
    AssertEquals('built-in surface green', $FF, TyGreenOf(s.Background.Color));
    AssertEquals('built-in surface blue', $FF, TyBlueOf(s.Background.Color));
  finally
    m.Free;
  end;
end;

procedure TBuiltinThemeTest.TestUserTypeKeySuppressesBuiltinNoBleed;
{ When the user theme defines ANY rule for a typeKey, the built-in layer for
  that typeKey is suppressed entirely — no property bleeds through. }
var
  m: TTyStyleModel;
  s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('TyButton { background: #FF0000; }');
    s := m.ResolveStyle('TyButton', '', []);
    AssertTrue('user background present', tpBackground in s.Present);
    AssertEquals('user red wins', $FF, TyRedOf(s.Background.Color));
    AssertEquals('user red wins (green 0)', $00, TyGreenOf(s.Background.Color));
    AssertFalse('no built-in border-width bleed', tpBorderWidth in s.Present);
    AssertFalse('no built-in padding bleed', tpPadding in s.Present);
    AssertFalse('no built-in font-size bleed', tpFontSize in s.Present);
  finally
    m.Free;
  end;
end;

procedure TBuiltinThemeTest.TestUnstyledTypeKeyStillGetsBuiltin;
{ A partial theme that styles only TyButton must still leave OTHER controls
  with the built-in default look (robustness for partial themes). }
var
  m: TTyStyleModel;
  s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('TyButton { background: #FF0000; }');
    s := m.ResolveStyle('TyLabel', '', []);
    AssertTrue('unstyled TyLabel still gets built-in TextColor',
      tpTextColor in s.Present);
    s := m.ResolveStyle('TyPanel', '', []);
    AssertTrue('unstyled TyPanel still gets built-in Background',
      tpBackground in s.Present);
  finally
    m.Free;
  end;
end;

procedure TBuiltinThemeTest.TestControlVisibleWithoutTheme;
{ End-to-end fix for the reported bug: a control whose controller has NO theme
  loaded must still render its background (built-in skin), not blank. Mirrors
  what the Lazarus designer does (Paint -> RenderTo, no LoadTheme ever run). }
var
  Ctl: TTyStyleController;
  Btn: TTyButtonRenderAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil); // deliberately NO LoadTheme
  Bmp := TBitmap.Create;
  try
    Btn := TTyButtonRenderAccess.Create(nil);
    try
      Btn.Controller := Ctl;
      Btn.Caption := '';                 // no glyph at center
      Btn.Font.PixelsPerInch := 96;      // pin PPI (macOS defaults to 72)
      Bmp.PixelFormat := pf32bit;
      Bmp.SetSize(100, 40);
      { Distinct magenta backdrop so an unpainted control stays detectable. }
      Bmp.Canvas.Brush.Color := TColor($FF00FF);
      Bmp.Canvas.FillRect(0, 0, 100, 40);
      Btn.DoRenderTo(Bmp.Canvas, Rect(0, 0, 100, 40), 96);

      Reread := TBGRABitmap.Create(Bmp);
      try
        Px := Reread.GetPixel(50, 20);   // center: built-in surface = white
        AssertTrue('center painted white-ish (built-in bg drawn), not backdrop: R',
          Px.red > 240);
        AssertTrue('center painted white-ish (built-in bg drawn): G', Px.green > 240);
        AssertTrue('center painted white-ish (built-in bg drawn): B', Px.blue > 240);
      finally
        Reread.Free;
      end;
    finally
      Btn.Free;
    end;
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

procedure TBuiltinThemeTest.TestBuiltinTitleBarTopRoundedTab;
var m: TTyStyleModel; sTitle, sTab: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(TyBuiltinThemeCss);
    sTitle := m.ResolveStyle('TyTitleBar', '', []);
    AssertTrue('titlebar tl rounded', sTitle.Radius.TL > 0);
    AssertEquals('titlebar bl square', 0, sTitle.Radius.BL);
    sTab := m.ResolveStyle('TyTab', '', []);
    AssertTrue('tab tr rounded', sTab.Radius.TR > 0);
    AssertEquals('tab br square', 0, sTab.Radius.BR);
  finally m.Free; end;
end;

procedure TBuiltinThemeTest.TestBuiltinFocusRingOnButton;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(TyBuiltinThemeCss);
    s := m.ResolveStyle('TyButton', '', [tysFocused]);
    AssertTrue('button focus outline present', tpOutline in s.Present);
    AssertTrue('focus outline width > 0', s.OutlineWidth > 0);
  finally m.Free; end;
end;

initialization
  RegisterTest(TBuiltinThemeTest);
end.
