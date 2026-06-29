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
    procedure TestBuiltinTitleBarFlatTabRounded;
    procedure TestBuiltinFocusRingOnButton;
    procedure TestDisabledOpacityParity;
    procedure TestStateRuleParity;
    procedure TestBatch4Tokens;
    procedure TestBatch4ThumbKnobTypeKeys;
    procedure TestGhostAndBadge;
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
    AssertBg('TyStatusBar', []);
    AssertBg('TyToolBar', []);
    AssertBg('TyCalendar', []);
    AssertBg('TyDateTimePicker', []);
    AssertBg('TyDateTimeButton', []);
    AssertBg('TyTreeView', []);
    AssertBg('TyTreeHeader', []);
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

procedure TBuiltinThemeTest.TestBuiltinTitleBarFlatTabRounded;
var m: TTyStyleModel; sTitle, sTab: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(TyBuiltinThemeCss);
    // The title bar is a flat chrome band: no border, no rounded corners.
    sTitle := m.ResolveStyle('TyTitleBar', '', []);
    AssertEquals('titlebar tl square (flat band)', 0, sTitle.Radius.TL);
    AssertEquals('titlebar bl square', 0, sTitle.Radius.BL);
    // Tabs keep their top-rounded shape.
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

procedure TBuiltinThemeTest.TestDisabledOpacityParity;
var m: TTyStyleModel; s: TTyStyleSet;
  procedure Chk(const K: string);
  begin
    s := m.ResolveStyle(K, '', [tysDisabled]);
    AssertTrue(K + ' has opacity flag', tpOpacity in s.Present);
    AssertTrue(K + ' opacity < 1', s.Opacity < 0.99);
  end;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(TyBuiltinThemeCss);
    Chk('TyScrollBar'); Chk('TyTrackBar'); Chk('TyTabControl'); Chk('TyProgressBar');
  finally m.Free; end;
end;

procedure TBuiltinThemeTest.TestStateRuleParity;
var m: TTyStyleModel; tog0, togH, edH, lbH, btnH, sbF, tcF: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(TyBuiltinThemeCss);
    tog0 := m.ResolveStyle('TyToggleSwitch','',[]);
    togH := m.ResolveStyle('TyToggleSwitch','',[tysHover]);
    AssertTrue('toggle hover differs from normal', togH.Background.Color <> tog0.Background.Color);
    sbF := m.ResolveStyle('TyScrollBar','',[tysFocused]);
    AssertTrue('scrollbar focus has outline', (tpOutline in sbF.Present) and (sbF.OutlineWidth > 0));
    tcF := m.ResolveStyle('TyTabControl','',[tysFocused]);
    AssertTrue('tabcontrol focus sets border-color', tpBorderColor in tcF.Present);
    edH := m.ResolveStyle('TyEdit','',[tysHover]);
    lbH := m.ResolveStyle('TyListBox','',[tysHover]);
    btnH := m.ResolveStyle('TyButton','',[tysHover]);
    AssertTrue('listbox hover border = input hover border', lbH.BorderColor = edH.BorderColor);
    AssertTrue('button hover border = input hover border', btnH.BorderColor = edH.BorderColor);
  finally m.Free; end;
end;

procedure TBuiltinThemeTest.TestBatch4Tokens;
var m: TTyStyleModel; sel, hint, tab, item: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(TyBuiltinThemeCss);
    sel := m.ResolveStyle('TyTextSelection','',[]);
    AssertTrue('TyTextSelection has background', tpBackground in sel.Present);
    // selection = alpha(accent,0.30): RGB ~ #3B82F6, alpha < opaque
    AssertTrue('selection alpha < 255', TyAlphaOf(sel.Background.Color) < 250);
    hint := m.ResolveStyle('TyTextHint','',[]);
    AssertTrue('TyTextHint has text color', tpTextColor in hint.Present);
    AssertTrue('hint alpha < 255 (muted)', TyAlphaOf(hint.TextColor) < 250);
    tab := m.ResolveStyle('TyTabClose','',[]);
    AssertTrue('TyTabClose has background', tpBackground in tab.Present);
    AssertTrue('TyTabClose has radius', tpBorderRadius in tab.Present);
    // Batch4 Task 6: TyListItem rows carry a border-radius token so the
    // selected/hover fill rounds instead of filling hard squares.
    item := m.ResolveStyle('TyListItem','',[]);
    AssertTrue('TyListItem has radius', tpBorderRadius in item.Present);
    AssertTrue('TyListItem radius > 0', item.BorderRadius > 0);
  finally m.Free; end;
end;

procedure TBuiltinThemeTest.TestBatch4ThumbKnobTypeKeys;
{ Batch4 Task 9: sub-element color typeKeys. The scrollbar thumb and toggle
  knob borrow no longer the parent's TextColor — they resolve dedicated
  typeKeys whose DEFAULTS equal today's borrowed colors (zero visual change).
    TyScrollThumb       background = var(--border)  = #D1D5DB
    TyScrollThumb:active background = var(--accent)  = #3B82F6
    TyToggleKnob        background = #FFFFFF }
var
  m: TTyStyleModel;
  st0, stA, kn: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(TyBuiltinThemeCss);
    st0 := m.ResolveStyle('TyScrollThumb', '', []);
    AssertTrue('TyScrollThumb has background', tpBackground in st0.Present);
    AssertEquals('scroll thumb default R = --border $D1', $D1, TyRedOf(st0.Background.Color));
    AssertEquals('scroll thumb default G = --border $D5', $D5, TyGreenOf(st0.Background.Color));
    AssertEquals('scroll thumb default B = --border $DB', $DB, TyBlueOf(st0.Background.Color));

    stA := m.ResolveStyle('TyScrollThumb', '', [tysActive]);
    AssertEquals('scroll thumb active R = --accent $3B', $3B, TyRedOf(stA.Background.Color));
    AssertEquals('scroll thumb active G = --accent $82', $82, TyGreenOf(stA.Background.Color));
    AssertEquals('scroll thumb active B = --accent $F6', $F6, TyBlueOf(stA.Background.Color));

    kn := m.ResolveStyle('TyToggleKnob', '', []);
    AssertTrue('TyToggleKnob has background', tpBackground in kn.Present);
    AssertEquals('toggle knob R = white', $FF, TyRedOf(kn.Background.Color));
    AssertEquals('toggle knob G = white', $FF, TyGreenOf(kn.Background.Color));
    AssertEquals('toggle knob B = white', $FF, TyBlueOf(kn.Background.Color));
  finally m.Free; end;
end;

procedure TBuiltinThemeTest.TestGhostAndBadge;
var m: TTyStyleModel; g, gh, b: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(TyBuiltinThemeCss);
    // ghost 基态:透明纯色底(alpha=0),但仍是 solid
    g := m.ResolveStyle('TyButton', 'ghost', []);
    AssertTrue('ghost has background', tpBackground in g.Present);
    AssertTrue('ghost base is solid', g.Background.Kind = tfkSolid);
    AssertTrue('ghost base transparent (alpha 0)', TyAlphaOf(g.Background.Color) = 0);
    // ghost hover:不透明底 + 边框
    gh := m.ResolveStyle('TyButton', 'ghost', [tysHover]);
    AssertTrue('ghost hover background present', tpBackground in gh.Present);
    AssertTrue('ghost hover bg opaque-ish', TyAlphaOf(gh.Background.Color) > 200);
    // ghost selected:有边框色
    gh := m.ResolveStyle('TyButton', 'ghost', [tysSelected]);
    AssertTrue('ghost selected sets border-color', tpBorderColor in gh.Present);
    // TyBadge:有背景与文字色
    b := m.ResolveStyle('TyBadge', '', []);
    AssertTrue('badge has background', tpBackground in b.Present);
    AssertTrue('badge has text color', tpTextColor in b.Present);
  finally m.Free; end;
end;

initialization
  RegisterTest(TBuiltinThemeTest);
end.
