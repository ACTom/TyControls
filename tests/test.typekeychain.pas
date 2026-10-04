unit test.typekeychain;
{ #14 -- the type key chain. A control subclass reports its own typeKey ('TagButton') and
  registers a parent ('TyButton'); ResolveStyle resolves the parent completely (base layer,
  user layer, variants, states) and then lays the child's own rules over it, per property.
  A typeKey that nobody registered resolves exactly as before -- the golden files in
  test.themes are the byte-level guard for that; this suite pins the chain itself.

  Every test that registers a key undoes it in TearDown (the registry is process-wide), so
  nothing here leaks into another suite. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Graphics,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.StyleModel, tyControls.Css.Parser, tyControls.Css.Catalog,
  tyControls.Css.Complete, tyControls.Controller, tyControls.Button;

type
  { The third-party subclass the issue is about: it reports its own key and nothing else. }
  TTestTagButton = class(TTyCustomButton)
  protected
    function GetStyleTypeKey: string; override;
  end;

  TTypeKeyChainTest = class(TTestCase)
  private
    FBefore: TStringList;   // keys registered before the test; TearDown keeps exactly these
    function Dump(const S: TTyStyleSet): string;
    function Render(B: TTyCustomButton): TBGRABitmap;
    function SamePixels(A, B: TBGRABitmap): Boolean;
    procedure AssertRaisesWith(const AMsg, ASub, AChild, AParent: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestUnregisteredKeyGetsNothing;
    procedure TestChainWithoutChildRulesEqualsParent;
    procedure TestChildRuleOverridesOnlyItsProperties;
    procedure TestChildVariantAndStateRules;
    procedure TestChildBaseRuleYieldsToParentState;
    procedure TestChildBaseRuleYieldsToBuiltinHover;
    procedure TestChildStateBeatsParentSameState;
    procedure TestParentDisabledBeatsChildHover;
    procedure TestChildVariantBeatsParentVariantNotParentState;
    procedure TestParentVariantBeatsChildBase;
    procedure TestThreeLevelInterleave;
    procedure TestSubFieldDeclarationYieldsWithItsField;
    procedure TestPlainChildRuleYieldsOnlyChildBase;
    procedure TestThreeLevelChain;
    procedure TestCycleRaisesAndLeavesRegistryIntact;
    procedure TestSelfParentRaises;
    procedure TestTooDeepRaises;
    procedure TestConflictingParentRaises;
    procedure TestInvalidNamesRaise;
    procedure TestCacheFollowsRegistration;
    procedure TestCaseInsensitiveChain;
    procedure TestNoChainIsByteIdentical;
    procedure TestPropertyCascadeFollowsChain;
    procedure TestVariantsFollowChain;
    procedure TestCompletionOffersRegisteredKeys;
    procedure TestTagButtonRendersLikeButton;
    procedure TestUnregisteredTagButtonRendersBare;
    procedure TestTagButtonRuleChangesOnlyThatProperty;
  end;

implementation

type
  TButtonHack = class(TTyCustomButton);   // reach the protected RenderTo of any button

function TTestTagButton.GetStyleTypeKey: string;
begin
  Result := 'TagButton';
end;

const
  cStateCombos: array[0..3] of TTyStateSet =
    ([tysNormal], [tysHover], [tysDisabled], [tysSelected, tysHover]);
  cClasses: array[0..2] of string = ('', 'primary', 'ghost');

procedure TTypeKeyChainTest.SetUp;
begin
  FBefore := TStringList.Create;
  TyGetRegisteredTypeKeys(FBefore);
end;

procedure TTypeKeyChainTest.TearDown;
var
  now_: TStringList;
  i: Integer;
begin
  now_ := TStringList.Create;
  try
    TyGetRegisteredTypeKeys(now_);
    for i := 0 to now_.Count - 1 do
      if FBefore.IndexOf(now_[i]) < 0 then
        TyUnregisterTypeKeyParent(now_[i]);
  finally
    now_.Free;
    FBefore.Free;
  end;
end;

{ Every field of a resolved style, so two styles compare equal only when they are. }
function TTypeKeyChainTest.Dump(const S: TTyStyleSet): string;
var
  p: TTyProp;
  i: Integer;
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := 'pres=';
  for p := Low(TTyProp) to High(TTyProp) do
    if p in S.Present then Result := Result + IntToStr(Ord(p)) + ',';
  with S.Background do
  begin
    Result := Result + Format(' bg=%d/%x/%x/%x/%.3f/%s/%d,%d,%d,%d/%d/%d/%d/%d/%x',
      [Ord(Kind), Color, GradFrom, GradTo, GradAngleDeg, ImagePath,
       SliceInsets.Left, SliceInsets.Top, SliceInsets.Right, SliceInsets.Bottom,
       Ord(SliceRepeat), Ord(ImageMode), Blur, GlassBlur, GlassTint], fs);
    for i := 0 to High(GradStops) do
      Result := Result + Format(' stop=%x@%.3f', [GradStops[i].Color, GradStops[i].Pos], fs);
  end;
  Result := Result + Format(' ut=%d ws=%d txt=%x bd=%x/%d/%d rs=%d rad=%d/%d,%d,%d,%d' +
    ' pad=%d,%d,%d,%d fnt=%s/%d/%d op=%.3f sh=%x/%d/%d,%d ol=%x/%d/%d',
    [Ord(S.BackgroundUnderTitlebar), Ord(S.WindowShadow), S.TextColor, S.BorderColor,
     S.BorderWidth, Ord(S.BorderStyle), Ord(S.RenderStyle), S.BorderRadius,
     S.Radius.TL, S.Radius.TR, S.Radius.BR, S.Radius.BL,
     S.Padding.Left, S.Padding.Top, S.Padding.Right, S.Padding.Bottom,
     S.FontName, S.FontSize, S.FontWeight, S.Opacity,
     S.ShadowColor, S.ShadowBlur, S.ShadowOffset.X, S.ShadowOffset.Y,
     S.OutlineColor, S.OutlineWidth, S.OutlineOffset], fs);
end;

function TTypeKeyChainTest.Render(B: TTyCustomButton): TBGRABitmap;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(96, 30);
    Bmp.Canvas.Brush.Color := clBlack;   // a ground no button colour equals
    Bmp.Canvas.FillRect(0, 0, 96, 30);
    TButtonHack(B).RenderTo(Bmp.Canvas, Rect(0, 0, 96, 30), 96);
    Result := TBGRABitmap.Create(Bmp);
  finally
    Bmp.Free;
  end;
end;

function TTypeKeyChainTest.SamePixels(A, B: TBGRABitmap): Boolean;
var
  x, y: Integer;
begin
  Result := (A.Width = B.Width) and (A.Height = B.Height);
  if not Result then Exit;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
      if A.GetPixel(x, y) <> B.GetPixel(x, y) then
        Exit(False);
end;

procedure TTypeKeyChainTest.AssertRaisesWith(const AMsg, ASub, AChild, AParent: string);
var
  raised: Boolean;
begin
  raised := False;
  try
    TyRegisterTypeKeyParent(AChild, AParent);
  except
    on E: ETyCssError do
    begin
      raised := True;
      AssertTrue(AMsg + ': message names the problem (' + E.Message + ')',
        Pos(ASub, LowerCase(E.Message)) > 0);
    end;
  end;
  AssertTrue(AMsg + ': raises ETyCssError', raised);
end;

{ ── resolution ──────────────────────────────────────────────────────────────── }

procedure TTypeKeyChainTest.TestUnregisteredKeyGetsNothing;
var m: TTyStyleModel;
begin
  // Today's behaviour, and still the behaviour for a key nobody registered.
  m := TTyStyleModel.Create;
  try
    AssertTrue('an unknown key resolves to an empty style',
      m.ResolveStyle('TagButton', '', [tysNormal]).Present = []);
  finally
    m.Free;
  end;
end;

procedure TTypeKeyChainTest.TestChainWithoutChildRulesEqualsParent;
var
  m: TTyStyleModel;
  ci, si: Integer;
begin
  TyRegisterTypeKeyParent('TagButton', 'TyButton');
  m := TTyStyleModel.Create;
  try
    for ci := 0 to High(cClasses) do
      for si := 0 to High(cStateCombos) do
        AssertEquals('TagButton = TyButton for class "' + cClasses[ci] + '" combo ' + IntToStr(si),
          Dump(m.ResolveStyle('TyButton', cClasses[ci], cStateCombos[si])),
          Dump(m.ResolveStyle('TagButton', cClasses[ci], cStateCombos[si])));
    AssertTrue('the parent really has a style', tpBackground in
      m.ResolveStyle('TagButton', '', [tysNormal]).Present);
  finally
    m.Free;
  end;
end;

procedure TTypeKeyChainTest.TestChildRuleOverridesOnlyItsProperties;
var
  m: TTyStyleModel;
  t, p, plain: TTyStyleSet;
begin
  TyRegisterTypeKeyParent('TagButton', 'TyButton');
  m := TTyStyleModel.Create;
  try
    plain := m.ResolveStyle('TyButton', '', [tysNormal]);
    m.LoadFromCss('TagButton { border-color: #FF0000; }');
    t := m.ResolveStyle('TagButton', '', [tysNormal]);
    p := m.ResolveStyle('TyButton', '', [tysNormal]);
    AssertEquals('the parent is untouched by a child rule', Dump(plain), Dump(p));
    AssertEquals('child border red: R', 255, TyRedOf(t.BorderColor));
    AssertEquals('child border red: G', 0, TyGreenOf(t.BorderColor));
    AssertEquals('child border red: B', 0, TyBlueOf(t.BorderColor));
    t.BorderColor := p.BorderColor;
    AssertEquals('every other property comes from the parent', Dump(p), Dump(t));
  finally
    m.Free;
  end;
end;

procedure TTypeKeyChainTest.TestChildVariantAndStateRules;
var
  m: TTyStyleModel;
  hit, plain: TTyStyleSet;
begin
  TyRegisterTypeKeyParent('TagButton', 'TyButton');
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('TagButton.primary:hover { color: #00FF00; }');
    hit := m.ResolveStyle('TagButton', 'primary', [tysHover]);
    AssertEquals('primary+hover picks the child rule', 255, TyGreenOf(hit.TextColor));
    AssertEquals('primary+hover picks the child rule (R)', 0, TyRedOf(hit.TextColor));
    plain := m.ResolveStyle('TyButton', 'primary', [tysHover]);
    hit.TextColor := plain.TextColor;
    AssertEquals('primary+hover: everything but the colour is the parent''s primary:hover',
      Dump(plain), Dump(hit));
    plain := m.ResolveStyle('TagButton', 'primary', [tysNormal]);
    AssertEquals('primary at rest is the parent''s primary',
      Dump(m.ResolveStyle('TyButton', 'primary', [tysNormal])), Dump(plain));
    AssertEquals('hover without primary is the parent''s hover',
      Dump(m.ResolveStyle('TyButton', '', [tysHover])),
      Dump(m.ResolveStyle('TagButton', '', [tysHover])));
  finally
    m.Free;
  end;
end;

{ D2 (stage interleave, the coordinator's ruling): a child rule beats what its parent wrote
  at the same or an earlier stage, and loses to what the parent wrote at a later one. }

procedure TTypeKeyChainTest.TestChildBaseRuleYieldsToParentState;
var
  m: TTyStyleModel;
  s: TTyStyleSet;
begin
  TyRegisterTypeKeyParent('TagButton', 'TyButton');
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('TyButton:hover { background: #0000FF; } TagButton { background: #00FF00; }');
    s := m.ResolveStyle('TagButton', '', [tysNormal]);
    AssertEquals('at rest the child is green', 255, TyGreenOf(s.Background.Color));
    s := m.ResolveStyle('TagButton', '', [tysHover]);
    AssertEquals('hovered: the parent''s :hover wins (B)', 255, TyBlueOf(s.Background.Color));
    AssertEquals('hovered: the parent''s :hover wins (G)', 0, TyGreenOf(s.Background.Color));
  finally
    m.Free;
  end;
end;

procedure TTypeKeyChainTest.TestChildBaseRuleYieldsToBuiltinHover;
var
  m: TTyStyleModel;
  s, b: TTyStyleSet;
begin
  { The usual case: the theme never touches TyButton, so its :hover comes from the built-in
    layer; the theme gives TagButton a background. Hovering must still show the hover fill. }
  TyRegisterTypeKeyParent('TagButton', 'TyButton');
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('TagButton { background: #00FF00; }');
    b := m.ResolveStyle('TyButton', '', [tysHover]);
    s := m.ResolveStyle('TagButton', '', [tysHover]);
    AssertEquals('hovered child = hovered button', Dump(b), Dump(s));
    s := m.ResolveStyle('TagButton', '', [tysNormal]);
    AssertEquals('at rest the child is green', 255, TyGreenOf(s.Background.Color));
    AssertEquals('at rest the child is green (R)', 0, TyRedOf(s.Background.Color));
  finally
    m.Free;
  end;
end;

procedure TTypeKeyChainTest.TestChildStateBeatsParentSameState;
var
  m: TTyStyleModel;
  s: TTyStyleSet;
begin
  TyRegisterTypeKeyParent('TagButton', 'TyButton');
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('TyButton:hover { background: #0000FF; } TagButton:hover { background: #00FF00; }');
    s := m.ResolveStyle('TagButton', '', [tysHover]);
    AssertEquals('same stage: the child wins (G)', 255, TyGreenOf(s.Background.Color));
    AssertEquals('same stage: the child wins (B)', 0, TyBlueOf(s.Background.Color));
  finally
    m.Free;
  end;
end;

procedure TTypeKeyChainTest.TestParentDisabledBeatsChildHover;
var
  m: TTyStyleModel;
  s, b: TTyStyleSet;
begin
  { :disabled is a later stage than :hover, so the parent's disabled opacity stands. }
  TyRegisterTypeKeyParent('TagButton', 'TyButton');
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('TagButton:hover { opacity: 0.25; }');
    b := m.ResolveStyle('TyButton', '', [tysHover, tysDisabled]);
    AssertTrue('fixture: the parent dims when disabled', tpOpacity in b.Present);
    s := m.ResolveStyle('TagButton', '', [tysHover, tysDisabled]);
    AssertEquals('disabled+hover: the parent''s disabled opacity', Dump(b), Dump(s));
    s := m.ResolveStyle('TagButton', '', [tysHover]);
    AssertEquals('hover alone: the child''s opacity', 0.25, s.Opacity, 0.001);
  finally
    m.Free;
  end;
end;

procedure TTypeKeyChainTest.TestChildVariantBeatsParentVariantNotParentState;
var
  m: TTyStyleModel;
  s: TTyStyleSet;
begin
  TyRegisterTypeKeyParent('TagButton', 'TyButton');
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('TagButton.primary { background: #00FF00; border-color: #00FF00; }');
    s := m.ResolveStyle('TagButton', 'primary', [tysNormal]);
    AssertEquals('child .primary beats parent .primary: background', 255, TyGreenOf(s.Background.Color));
    AssertEquals('child .primary beats parent .primary: background (R)', 0, TyRedOf(s.Background.Color));
    AssertEquals('child .primary beats parent .primary: border', 255, TyGreenOf(s.BorderColor));
    { TyButton:hover and TyButton.primary:hover (built-in) write background and border-color
      at a later stage than any .primary rule. }
    AssertEquals('hovered: the parent''s states win over the child variant',
      Dump(m.ResolveStyle('TyButton', 'primary', [tysHover])),
      Dump(m.ResolveStyle('TagButton', 'primary', [tysHover])));
  finally
    m.Free;
  end;
end;

procedure TTypeKeyChainTest.TestParentVariantBeatsChildBase;
var
  m: TTyStyleModel;
  s, b: TTyStyleSet;
begin
  TyRegisterTypeKeyParent('TagButton', 'TyButton');
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('TagButton { color: #FF0000; }');
    s := m.ResolveStyle('TagButton', '', [tysNormal]);
    AssertEquals('no class: the child colour', 255, TyRedOf(s.TextColor));
    b := m.ResolveStyle('TyButton', 'primary', [tysNormal]);
    s := m.ResolveStyle('TagButton', 'primary', [tysNormal]);
    AssertEquals('.primary (built-in) beats the plain child colour', Dump(b), Dump(s));
  finally
    m.Free;
  end;
end;

procedure TTypeKeyChainTest.TestThreeLevelInterleave;
var
  m: TTyStyleModel;
  s: TTyStyleSet;
begin
  TyRegisterTypeKeyParent('TagButton', 'TyButton');
  TyRegisterTypeKeyParent('FancyTag', 'TagButton');
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('TagButton:hover { color: #222222; } FancyTag { color: #333333; }');
    s := m.ResolveStyle('FancyTag', '', [tysNormal]);
    AssertEquals('at rest: the grandchild colour', $33, TyRedOf(s.TextColor));
    s := m.ResolveStyle('FancyTag', '', [tysHover]);
    AssertEquals('hovered: the middle key''s :hover beats the grandchild''s plain rule',
      $22, TyRedOf(s.TextColor));
    m.LoadFromCss('TagButton:hover { color: #222222; } FancyTag:hover { color: #444444; }');
    s := m.ResolveStyle('FancyTag', '', [tysHover]);
    AssertEquals('same stage: the leaf wins', $44, TyRedOf(s.TextColor));
  finally
    m.Free;
  end;
end;

procedure TTypeKeyChainTest.TestPlainChildRuleYieldsOnlyChildBase;
var
  m, ref: TTyStyleModel;
  s, btn, tagBase: TTyStyleSet;
begin
  { D3. A built-in key stands in for the child because only built-in keys have base-layer
    rules. A plain user rule for the CHILD silences the child's own base rules -- and only
    those: the parent's base layer still applies underneath. }
  ref := TTyStyleModel.Create;
  m := TTyStyleModel.Create;
  try
    tagBase := ref.ResolveStyle('TyTag', '', [tysNormal]);
    TyRegisterTypeKeyParent('TyTag', 'TyButton');
    m.LoadFromCss('TyTag { color: #123456; }');
    s := m.ResolveStyle('TyTag', '', [tysNormal]);
    btn := m.ResolveStyle('TyButton', '', [tysNormal]);
    AssertTrue('the button base has a background', tpBackground in btn.Present);
    AssertTrue('fixture: the tag base background differs from the button''s',
      tagBase.Background.Color <> btn.Background.Color);
    AssertEquals('background comes from the parent''s base layer',
      btn.Background.Color, s.Background.Color);
    AssertEquals('radius comes from the parent''s base layer, not the tag''s pill',
      btn.BorderRadius, s.BorderRadius);
    AssertEquals('colour from the child''s user rule', $12, TyRedOf(s.TextColor));
    AssertEquals('colour from the child''s user rule (B)', $56, TyBlueOf(s.TextColor));
  finally
    m.Free;
    ref.Free;
  end;
end;

procedure TTypeKeyChainTest.TestThreeLevelChain;
var
  m: TTyStyleModel;
  chain: TStringArray;
  f, t, b: TTyStyleSet;
begin
  TyRegisterTypeKeyParent('TagButton', 'TyButton');
  TyRegisterTypeKeyParent('FancyTag', 'TagButton');
  chain := TyTypeKeyChain('FancyTag');
  AssertEquals('chain length', 3, Length(chain));
  AssertEquals('chain[0]', 'FancyTag', chain[0]);
  AssertEquals('chain[1]', 'TagButton', chain[1]);
  AssertEquals('chain[2]', 'TyButton', chain[2]);
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('TagButton { color: #111111; border-color: #222222; } FancyTag { color: #333333; }');
    f := m.ResolveStyle('FancyTag', '', [tysNormal]);
    t := m.ResolveStyle('TagButton', '', [tysNormal]);
    b := m.ResolveStyle('TyButton', '', [tysNormal]);
    AssertEquals('grandchild colour wins', $33, TyRedOf(f.TextColor));
    AssertEquals('child border carries down', $22, TyRedOf(f.BorderColor));
    AssertEquals('parent background carries down', b.Background.Color, f.Background.Color);
    AssertEquals('the child keeps its own colour', $11, TyRedOf(t.TextColor));
  finally
    m.Free;
  end;
end;

procedure TTypeKeyChainTest.TestSubFieldDeclarationYieldsWithItsField;
var
  m: TTyStyleModel;
begin
  { background-size writes a Background field without raising tpBackground. It still belongs
    to the background, so it yields with it when the parent's :hover replaces the fill. }
  TyRegisterTypeKeyParent('TagButton', 'TyButton');
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('TagButton { background-size: stretch; }');
    AssertEquals('hovered child = hovered button',
      Dump(m.ResolveStyle('TyButton', '', [tysHover])),
      Dump(m.ResolveStyle('TagButton', '', [tysHover])));
    AssertTrue('at rest the child''s background-size stands',
      m.ResolveStyle('TagButton', '', [tysNormal]).Background.ImageMode = timStretch);
  finally
    m.Free;
  end;
end;

{ ── registry rules ──────────────────────────────────────────────────────────── }

procedure TTypeKeyChainTest.TestCycleRaisesAndLeavesRegistryIntact;
var m: TTyStyleModel;
begin
  TyRegisterTypeKeyParent('ChainA', 'ChainB');
  AssertRaisesWith('B -> A closes a loop', 'cycle', 'ChainB', 'ChainA');
  AssertEquals('B stays unregistered', '', TyTypeKeyParent('ChainB'));
  AssertEquals('A keeps its parent', 'ChainB', TyTypeKeyParent('ChainA'));
  TyRegisterTypeKeyParent('ChainB', 'ChainC');   // A -> B -> C
  AssertRaisesWith('a longer loop: C -> A', 'cycle', 'ChainC', 'ChainA');
  AssertEquals('C stays a root', '', TyTypeKeyParent('ChainC'));
  m := TTyStyleModel.Create;
  try
    AssertTrue('resolving A still terminates', m.ResolveStyle('ChainA', '', []).Present = []);
  finally
    m.Free;
  end;
end;

procedure TTypeKeyChainTest.TestSelfParentRaises;
begin
  AssertRaisesWith('a key cannot be its own parent', 'cycle', 'ChainSelf', 'ChainSelf');
  AssertRaisesWith('not even in another case', 'cycle', 'ChainSelf', 'chainself');
  AssertEquals('nothing registered', '', TyTypeKeyParent('ChainSelf'));
end;

procedure TTypeKeyChainTest.TestTooDeepRaises;
var i: Integer;
begin
  // K8 -> K7 -> ... -> K1 is eight keys: the most a chain may have.
  for i := 2 to TyMaxTypeKeyChain do
    TyRegisterTypeKeyParent('DeepK' + IntToStr(i), 'DeepK' + IntToStr(i - 1));
  AssertEquals('eight keys fit', TyMaxTypeKeyChain, Length(TyTypeKeyChain('DeepK8')));
  AssertRaisesWith('a ninth key', 'deep', 'DeepK9', 'DeepK8');
  AssertEquals('the ninth stays unregistered', '', TyTypeKeyParent('DeepK9'));
  // Lengthening the chain from the ROOT end pushes an existing descendant over too.
  AssertRaisesWith('a new root under an eight-key chain', 'deep', 'DeepK1', 'DeepRoot');
  AssertEquals('the root link was withdrawn', '', TyTypeKeyParent('DeepK1'));
  AssertEquals('the chain is as it was', TyMaxTypeKeyChain, Length(TyTypeKeyChain('DeepK8')));
end;

procedure TTypeKeyChainTest.TestConflictingParentRaises;
begin
  TyRegisterTypeKeyParent('TagButton', 'TyButton');
  TyRegisterTypeKeyParent('TagButton', 'TyButton');   // same link again: fine
  TyRegisterTypeKeyParent('tagbutton', 'tybutton');   // same link, other case: fine
  AssertRaisesWith('another parent for the same key', 'already', 'TagButton', 'TyEdit');
  AssertEquals('the first parent stays', 'TyButton', TyTypeKeyParent('TagButton'));
end;

procedure TTypeKeyChainTest.TestInvalidNamesRaise;
begin
  AssertRaisesWith('empty child', 'invalid', '', 'TyButton');
  AssertRaisesWith('empty parent', 'invalid', 'TagButton', '');
  AssertRaisesWith('leading digit', 'invalid', '1Tag', 'TyButton');
  AssertRaisesWith('a space', 'invalid', 'Tag Button', 'TyButton');
  AssertRaisesWith('a separator char', 'invalid', 'Tag=Button', 'TyButton');
  AssertEquals('nothing registered', '', TyTypeKeyParent('TagButton'));
end;

procedure TTypeKeyChainTest.TestCacheFollowsRegistration;
var m: TTyStyleModel;
begin
  m := TTyStyleModel.Create;
  try
    AssertTrue('before: empty (and now memoised)',
      m.ResolveStyle('TagButton', '', [tysNormal]).Present = []);
    TyRegisterTypeKeyParent('TagButton', 'TyButton');
    AssertEquals('after registering: the parent''s style, not the memoised empty one',
      Dump(m.ResolveStyle('TyButton', '', [tysNormal])),
      Dump(m.ResolveStyle('TagButton', '', [tysNormal])));
    TyUnregisterTypeKeyParent('TagButton');
    AssertTrue('after unregistering: empty again',
      m.ResolveStyle('TagButton', '', [tysNormal]).Present = []);
  finally
    m.Free;
  end;
end;

procedure TTypeKeyChainTest.TestCaseInsensitiveChain;
var m: TTyStyleModel;
begin
  // Rules match their type name case-insensitively; the chain must too.
  TyRegisterTypeKeyParent('TagButton', 'TyButton');
  m := TTyStyleModel.Create;
  try
    AssertEquals('tagbutton follows the TagButton chain',
      Dump(m.ResolveStyle('TyButton', '', [tysNormal])),
      Dump(m.ResolveStyle('tagbutton', '', [tysNormal])));
  finally
    m.Free;
  end;
end;

procedure TTypeKeyChainTest.TestNoChainIsByteIdentical;
var
  m: TTyStyleModel;
  before: TStringList;
  i, si, n: Integer;
begin
  { Registering keys must not move any key that is not in a chain. }
  m := TTyStyleModel.Create;
  before := TStringList.Create;
  try
    for i := 0 to High(TyCatalogTypeKeys) do
      for si := 0 to High(cStateCombos) do
        before.Add(Dump(m.ResolveStyle(TyCatalogTypeKeys[i], 'primary', cStateCombos[si])));
    for i := 1 to 20 do
      TyRegisterTypeKeyParent('Unrelated' + IntToStr(i), 'TyButton');
    n := 0;
    for i := 0 to High(TyCatalogTypeKeys) do
      for si := 0 to High(cStateCombos) do
      begin
        AssertEquals(TyCatalogTypeKeys[i] + ' combo ' + IntToStr(si), before[n],
          Dump(m.ResolveStyle(TyCatalogTypeKeys[i], 'primary', cStateCombos[si])));
        Inc(n);
      end;
  finally
    before.Free;
    m.Free;
  end;
end;

procedure TTypeKeyChainTest.TestPropertyCascadeFollowsChain;
var
  m: TTyStyleModel;
  s, b: TTyStyleSet;
begin
  TyRegisterTypeKeyParent('TagButton', 'TyButton');
  m := TTyStyleModel.Create;
  try
    m.PropertyCascade := True;
    m.LoadFromCss('TagButton { color: #123456; }');
    s := m.ResolveStyle('TagButton', '', [tysNormal]);
    b := m.ResolveStyle('TyButton', '', [tysNormal]);
    AssertTrue('cascade on: the parent background is there', tpBackground in s.Present);
    AssertEquals('cascade on: background from the parent', b.Background.Color, s.Background.Color);
    AssertEquals('cascade on: colour from the child', $34, TyGreenOf(s.TextColor));
  finally
    m.Free;
  end;
end;

procedure TTypeKeyChainTest.TestVariantsFollowChain;
var
  m: TTyStyleModel;
  l: TStringList;
begin
  m := TTyStyleModel.Create;
  l := TStringList.Create;
  try
    m.GetVariantsForType('TagButton', l);
    AssertEquals('unregistered: no variants', 0, l.Count);
    TyRegisterTypeKeyParent('TagButton', 'TyButton');
    m.GetVariantsForType('TagButton', l);
    AssertTrue('primary', l.IndexOf('primary') >= 0);
    AssertTrue('danger', l.IndexOf('danger') >= 0);
    AssertTrue('ghost', l.IndexOf('ghost') >= 0);
  finally
    l.Free;
    m.Free;
  end;
end;

procedure TTypeKeyChainTest.TestCompletionOffersRegisteredKeys;
var l: TStringList;
begin
  l := TStringList.Create;
  try
    TyCssCompletionItems('', True, l);
    AssertTrue('not offered before registering', l.IndexOf('TagButton') < 0);
    TyRegisterTypeKeyParent('TagButton', 'TyButton');
    l.Clear;
    TyCssCompletionItems('', True, l);
    AssertTrue('offered once registered', l.IndexOf('TagButton') >= 0);
    AssertTrue('the catalogue is still there', l.IndexOf('TyButton') >= 0);
    l.Clear;
    TyCssCompletionItems('', False, l);
    AssertTrue('a control-level block has no selectors to complete', l.IndexOf('TagButton') < 0);
    { The list the design-time reference panel shows: the same keys, a catalogue key that is
      also registered as a child listed once. }
    TyRegisterTypeKeyParent('TyTag', 'TyButton');
    l.Clear;
    TyCssSelectorTypeKeys(l);
    AssertTrue('panel list has the registered key', l.IndexOf('TagButton') >= 0);
    AssertEquals('panel list: catalogue + new registered keys only',
      Length(TyCatalogTypeKeys) + 1, l.Count);
  finally
    l.Free;
  end;
end;

{ ── end to end: a third-party subclass ─────────────────────────────────────── }

procedure TTypeKeyChainTest.TestTagButtonRendersLikeButton;
var
  Ctl: TTyStyleController;
  Tag: TTestTagButton;
  Btn: TTyButton;
  A, B: TBGRABitmap;
begin
  TyRegisterTypeKeyParent('TagButton', 'TyButton');
  Ctl := TTyStyleController.Create(nil);   // fresh = built-in light, isolated from the global one
  Tag := TTestTagButton.Create(nil);
  Btn := TTyButton.Create(nil);
  A := nil; B := nil;
  try
    Tag.Controller := Ctl;  Btn.Controller := Ctl;
    Tag.Caption := 'Tag';   Btn.Caption := 'Tag';
    Tag.Font.PixelsPerInch := 96;  Btn.Font.PixelsPerInch := 96;
    A := Render(Tag);
    B := Render(Btn);
    AssertTrue('a theme without TagButton rules draws it exactly like a button', SamePixels(A, B));
  finally
    A.Free; B.Free; Tag.Free; Btn.Free; Ctl.Free;
  end;
end;

procedure TTypeKeyChainTest.TestUnregisteredTagButtonRendersBare;
var
  Ctl: TTyStyleController;
  Tag: TTestTagButton;
  Btn: TTyButton;
  A, B: TBGRABitmap;
begin
  // Without the chain the subclass gets no style at all -- so the test above can tell.
  Ctl := TTyStyleController.Create(nil);
  Tag := TTestTagButton.Create(nil);
  Btn := TTyButton.Create(nil);
  A := nil; B := nil;
  try
    Tag.Controller := Ctl;  Btn.Controller := Ctl;
    Tag.Caption := 'Tag';   Btn.Caption := 'Tag';
    Tag.Font.PixelsPerInch := 96;  Btn.Font.PixelsPerInch := 96;
    A := Render(Tag);
    B := Render(Btn);
    AssertFalse('unregistered: not drawn like a button', SamePixels(A, B));
  finally
    A.Free; B.Free; Tag.Free; Btn.Free; Ctl.Free;
  end;
end;

procedure TTypeKeyChainTest.TestTagButtonRuleChangesOnlyThatProperty;
var
  Ctl: TTyStyleController;
  Tag: TTestTagButton;
  Red, Plain: TTyButton;
  A, B, C: TBGRABitmap;
begin
  TyRegisterTypeKeyParent('TagButton', 'TyButton');
  Ctl := TTyStyleController.Create(nil);
  Tag := TTestTagButton.Create(nil);
  Red := TTyButton.Create(nil);
  Plain := TTyButton.Create(nil);
  A := nil; B := nil; C := nil;
  try
    Ctl.LoadThemeCss('TagButton { border-color: #FF0000; }');
    Tag.Controller := Ctl;  Red.Controller := Ctl;  Plain.Controller := Ctl;
    Tag.Caption := 'Tag';   Red.Caption := 'Tag';   Plain.Caption := 'Tag';
    Tag.Font.PixelsPerInch := 96;  Red.Font.PixelsPerInch := 96;  Plain.Font.PixelsPerInch := 96;
    Red.StyleOverride := 'border-color: #FF0000;';
    A := Render(Tag);
    B := Render(Red);
    C := Render(Plain);
    AssertTrue('TagButton = a button with only its border recoloured', SamePixels(A, B));
    AssertFalse('and the rule did change something', SamePixels(A, C));
  finally
    A.Free; B.Free; C.Free; Tag.Free; Red.Free; Plain.Free; Ctl.Free;
  end;
end;

initialization
  RegisterTest(TTypeKeyChainTest);
end.
