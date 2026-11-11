unit test.themedcolor;
{$mode objfpc}{$H+}

{ A themed container keeps its LCL Color equal to what is behind its children.

  A plain LCL control with ParentColor paints its parent's LCL Color, and a TyControls
  control on such a plain control fills the corners outside its shape with that colour
  (TyResolveParentBgFill's plain-parent branch, GetColorResolvingParent). Both were clBtnFace
  on every themed container but the form, whose Color ApplyChromeTheme sets. So at run time
  a container that accepts controls carries the colour itself: its own background when that
  is solid, composited over what is behind it when it is translucent, what is behind it when
  it has none, the centre of a gradient.

  The subject of every assertion is the PLAIN child's colour or what a TyControls control on
  it resolves -- the two things an application sees -- and never a field of the container. }

interface

uses
  Classes, SysUtils, Types, Graphics, Controls, Forms, ExtCtrls, LCLType, LResources,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.StyleModel,
  tyControls.Panel, tyControls.Button, tyControls.GroupBox, tyControls.Frame;

type
  { Counts the colours the container is given, and publishes what a third party's
    container might: the two properties a themed colour must stay out of. }
  TCountingPanel = class(TTyCustomPanel)
  protected
    procedure SetColor(Value: TColor); override;
  public
    Assignments: Integer;
    procedure Designing;
    procedure Hover;
  published
    property Color;
    property ParentColor;
  end;

  TThemedColorFrame = class(TTyFrame)
  public
    procedure Designing;
  end;

  TThemedContainerColorTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FHost: TCountingPanel;
    FPlain: TPanel;
    procedure MakeFixture(const ACss: string);
    function Lcl(AR, AG, AB: Byte): TColor;
    procedure AssertLcl(const AMsg: string; AR, AG, AB: Byte; AGot: TColor);
    function StreamedText(AComponent: TComponent): string;
  protected
    procedure TearDown; override;
  published
    procedure TestAPlainPanelTakesTheContainersThemedColour;
    procedure TestATyControlOnThePlainPanelResolvesIt;
    procedure TestStyleOverrideStyleClassAndControllerAreFollowed;
    procedure TestAContainerWithoutABackgroundShowsWhatIsBehindIt;
    procedure TestReparentingIsFollowed;
    procedure TestATranslucentBackgroundIsCompositedOverWhatIsBehind;
    procedure TestAGradientGivesItsCentre;
    procedure TestTheColourIsAssignedOncePerChange;
    procedure TestDesignTimeLeavesColorAlone;
    procedure TestAColourTheApplicationSetIsLeftAlone;
    procedure TestAControlThatTakesNoChildrenIsLeftAlone;
    procedure TestTheThemedColourIsNotStreamed;
    procedure TestAContainerReadFromAStreamIsThemed;
    procedure TestAPlainFrameOnAThemedContainer;
    procedure TestATyFrameWithItsOwnBackground;
    procedure TestATyFrameWithoutABackgroundKeepsParentColor;
    procedure TestATranslucentTyFrameFollowsItsHost;
    procedure TestATyFrameReadFromAStreamIsThemed;
    procedure TestATyFrameIsLeftAloneInTheDesigner;
  end;

implementation

const
  cFlat = 'border-width: 0px; border-radius: 0px; padding: 0px; ';
  cBlueHost = 'TyPanel { background: #204060; ' + cFlat + '}';
  cRustHost = 'TyPanel { background: #A03010; ' + cFlat + '}';

type
  TControlAccess = class(TControl);

function NoFormFile(Instance: TComponent; RootAncestor: TClass): Boolean;
begin
  Result := Instance.ClassType = TThemedColorFrame;
end;

{ TCountingPanel }

procedure TCountingPanel.SetColor(Value: TColor);
begin
  if Value <> Color then Inc(Assignments);
  inherited SetColor(Value);
end;

procedure TCountingPanel.Designing;
begin
  SetDesigning(True);
end;

procedure TCountingPanel.Hover;
begin
  MouseEnter;
end;

{ TThemedColorFrame }

procedure TThemedColorFrame.Designing;
begin
  SetDesigning(True);
end;

{ TThemedContainerColorTest }

procedure TThemedContainerColorTest.MakeFixture(const ACss: string);
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(ACss);
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 640, 480);
  FForm.Color := clYellow;   // so "what is behind" a container on the form is a known colour
  FHost := TCountingPanel.Create(FForm);
  FHost.Controller := FCtl;
  FHost.Parent := FForm;
  FHost.SetBounds(0, 0, 400, 300);
  FPlain := TPanel.Create(FForm);
  FPlain.Parent := FHost;
  FPlain.SetBounds(20, 20, 200, 120);
end;

procedure TThemedContainerColorTest.TearDown;
begin
  FreeAndNil(FForm);   // owns the host and the plain panel
  FreeAndNil(FCtl);
end;

function TThemedContainerColorTest.Lcl(AR, AG, AB: Byte): TColor;
begin
  Result := RGBToColor(AR, AG, AB);
end;

procedure TThemedContainerColorTest.AssertLcl(const AMsg: string; AR, AG, AB: Byte;
  AGot: TColor);
var
  r, g, b: Byte;
begin
  RedGreenBlue(ColorToRGB(AGot), r, g, b);
  AssertTrue(Format('%s (want #%.2x%.2x%.2x, got #%.2x%.2x%.2x)', [AMsg, AR, AG, AB, r, g, b]),
    (Abs(r - AR) <= 1) and (Abs(g - AG) <= 1) and (Abs(b - AB) <= 1));
end;

function TThemedContainerColorTest.StreamedText(AComponent: TComponent): string;
var
  ms: TMemoryStream;
begin
  ms := TMemoryStream.Create;
  try
    WriteComponentAsTextToStream(ms, AComponent);
    Result := '';
    SetLength(Result, ms.Size);
    if ms.Size > 0 then Move(ms.Memory^, Result[1], ms.Size);
  finally
    ms.Free;
  end;
end;

procedure TThemedContainerColorTest.TestAPlainPanelTakesTheContainersThemedColour;
begin
  MakeFixture(cBlueHost);
  AssertTrue('precondition: the plain panel follows its parent', FPlain.ParentColor);
  AssertLcl('a plain panel on a themed container paints the themed colour',
    $20, $40, $60, FPlain.GetColorResolvingParent);
  FCtl.LoadThemeCss(cRustHost);
  AssertLcl('and the new one after a theme switch', $A0, $30, $10,
    FPlain.GetColorResolvingParent);
  AssertTrue('still by ParentColor: nothing was written into the plain panel',
    FPlain.ParentColor);
end;

procedure TThemedContainerColorTest.TestATyControlOnThePlainPanelResolvesIt;
var
  btn: TTyButton;
  c: TTyColor;
begin
  MakeFixture(cBlueHost);
  btn := TTyButton.Create(FForm);
  btn.Controller := FCtl;
  btn.Parent := FPlain;
  btn.SetBounds(10, 10, 80, 30);
  c := 0;
  AssertTrue('resolved', TyResolveParentBg(btn, c));
  AssertLcl('the button''s corners take the container''s themed colour', $20, $40, $60,
    TyColorToLCL(c));
  FCtl.LoadThemeCss(cRustHost);
  AssertTrue('resolved', TyResolveParentBg(btn, c));
  AssertLcl('and follow a theme switch', $A0, $30, $10, TyColorToLCL(c));
end;

procedure TThemedContainerColorTest.TestStyleOverrideStyleClassAndControllerAreFollowed;
var
  other: TTyStyleController;
begin
  MakeFixture(cBlueHost + 'TyPanel.side { background: #00C000; }');
  FHost.StyleOverride := 'background: #C000C0;';
  AssertLcl('StyleOverride', $C0, 0, $C0, FPlain.GetColorResolvingParent);
  FHost.StyleOverride := '';
  AssertLcl('StyleOverride cleared', $20, $40, $60, FPlain.GetColorResolvingParent);
  FHost.StyleClass := 'side';
  AssertLcl('StyleClass', 0, $C0, 0, FPlain.GetColorResolvingParent);
  FHost.StyleClass := '';
  other := TTyStyleController.Create(nil);
  try
    other.LoadThemeCss(cRustHost);
    FHost.Controller := other;
    AssertLcl('another controller', $A0, $30, $10, FPlain.GetColorResolvingParent);
  finally
    FHost.Controller := FCtl;
    other.Free;
  end;
  AssertLcl('and back', $20, $40, $60, FPlain.GetColorResolvingParent);
end;

procedure TThemedContainerColorTest.TestAContainerWithoutABackgroundShowsWhatIsBehindIt;
var
  box: TTyGroupBox;
  inner: TPanel;
  st: TTyStyleSet;
begin
  { a group box has no background of its own: behind its children is its parent's }
  MakeFixture(cBlueHost);
  st := FCtl.Model.ResolveStyle('TyGroupBox', '', [tysNormal]);
  AssertTrue('precondition: the group box is transparent in this theme',
    not (tpBackground in st.Present) or ((st.Background.Kind = tfkSolid)
    and (TyAlphaOf(st.Background.Color) = 0)));
  box := TTyGroupBox.Create(FForm);
  box.Controller := FCtl;
  box.Parent := FHost;
  box.SetBounds(240, 20, 140, 120);
  inner := TPanel.Create(FForm);
  inner.Parent := box;
  AssertLcl('the plain panel in the group box shows the outer container',
    $20, $40, $60, inner.GetColorResolvingParent);
  { the OUTER container alone changes; the group box hears of it through its parent colour }
  FHost.StyleOverride := 'background: #C000C0;';
  AssertLcl('and follows it when only the outer container changes',
    $C0, 0, $C0, inner.GetColorResolvingParent);
  { what is behind it is read at rest as well: a hovered outer container does not lend the
    group box its hover colour }
  FHost.StyleOverride := '';
  FCtl.LoadThemeCss(cBlueHost + 'TyPanel:hover { background: #FFFFFF; }');
  FHost.Hover;
  box.StyleClass := 'anything';   // the group box works its colour out again
  AssertLcl('under a hovered outer container the group box still shows its rest colour',
    $20, $40, $60, inner.GetColorResolvingParent);
end;

procedure TThemedContainerColorTest.TestReparentingIsFollowed;
var
  second: TTyPanel;
  box: TTyGroupBox;
  inner: TPanel;
begin
  MakeFixture(cBlueHost);
  second := TTyPanel.Create(FForm);
  second.Controller := FCtl;
  second.StyleOverride := 'background: #00C000;';
  second.Parent := FForm;
  second.SetBounds(0, 310, 400, 150);
  box := TTyGroupBox.Create(FForm);
  box.Controller := FCtl;
  box.Parent := FHost;
  inner := TPanel.Create(FForm);
  inner.Parent := box;
  AssertLcl('on the first container', $20, $40, $60, inner.GetColorResolvingParent);
  box.Parent := second;
  AssertLcl('moved to the second, its children see the second', 0, $C0, 0,
    inner.GetColorResolvingParent);
  { and a plain panel moved between two themed containers }
  FPlain.Parent := second;
  AssertLcl('a plain panel takes its new parent''s colour', 0, $C0, 0,
    FPlain.GetColorResolvingParent);
end;

procedure TThemedContainerColorTest.TestATranslucentBackgroundIsCompositedOverWhatIsBehind;
begin
  { half red over the form's yellow (#FFFF00): #FF8000, give or take the alpha's rounding }
  MakeFixture('TyPanel { background: rgba(255, 0, 0, 0.5); ' + cFlat + '}');
  AssertLcl('the tint over the plain form''s colour', $FF, $7F, 0,
    FPlain.GetColorResolvingParent);
  FForm.Color := clBlue;
  AssertLcl('and over the colour the form changes to', $7F + 1, 0, $7F,
    FPlain.GetColorResolvingParent);
end;

procedure TThemedContainerColorTest.TestAGradientGivesItsCentre;
begin
  MakeFixture('TyPanel { background: linear-gradient(90deg, #FF0000, #0000FF); ' + cFlat + '}');
  AssertLcl('halfway down a red-to-blue sweep', $80, 0, $80, FPlain.GetColorResolvingParent);
  FCtl.LoadThemeCss('TyPanel { background: linear-gradient(90deg, #00FF00, #000000); ' + cFlat + '}');
  AssertLcl('and of the sweep it changes to', 0, $80, 0, FPlain.GetColorResolvingParent);
end;

procedure TThemedContainerColorTest.TestTheColourIsAssignedOncePerChange;
var
  n: Integer;
begin
  MakeFixture(cBlueHost);
  n := FHost.Assignments;
  AssertTrue('the fixture gave the container its colour', n >= 1);
  FHost.Invalidate;
  FHost.Invalidate;
  FHost.Hover;
  AssertEquals('repaints and a hover assign nothing', n, FHost.Assignments);
  FCtl.LoadThemeCss(cBlueHost + 'TyButton { background: #FFFFFF; }');
  AssertEquals('nor does a theme change that leaves the colour as it was', n, FHost.Assignments);
  FCtl.LoadThemeCss(cRustHost);
  AssertEquals('a theme change that moves it assigns once', n + 1, FHost.Assignments);
  { a hover background is a state, not the rest look the children sit on }
  FCtl.LoadThemeCss(cBlueHost + 'TyPanel:hover { background: #FFFFFF; }');
  n := FHost.Assignments;
  FHost.Invalidate;
  AssertLcl('hovered, the container keeps its rest colour', $20, $40, $60,
    FPlain.GetColorResolvingParent);
  AssertEquals('and assigns nothing', n, FHost.Assignments);
end;

procedure TThemedContainerColorTest.TestDesignTimeLeavesColorAlone;
var
  d: TCountingPanel;
  n: Integer;
begin
  MakeFixture(cBlueHost);
  d := TCountingPanel.Create(FForm);
  d.Designing;
  d.Controller := FCtl;
  d.Parent := FForm;   // LCL hands it the form's colour here, as to any ParentColor control
  n := d.Assignments;
  d.StyleOverride := 'background: #C000C0;';
  FCtl.LoadThemeCss(cRustHost);
  AssertEquals('in the designer nothing is assigned: Color would be saved with the form',
    n, d.Assignments);
  AssertTrue('and it still follows its parent', d.ParentColor);
end;

procedure TThemedContainerColorTest.TestAColourTheApplicationSetIsLeftAlone;
begin
  MakeFixture(cBlueHost);
  FHost.Color := clLime;
  FCtl.LoadThemeCss(cRustHost);
  FHost.StyleOverride := 'background: #C000C0;';
  AssertTrue('a colour the application gave the container stays', FHost.Color = clLime);
  AssertTrue('and the plain panel shows it', FPlain.GetColorResolvingParent = clLime);
  { handing it back: ParentColor again, as for any LCL control }
  FHost.ParentColor := True;
  AssertLcl('back on ParentColor the container is themed again', $C0, 0, $C0,
    FPlain.GetColorResolvingParent);
  { or clDefault, which is all a control that does not publish ParentColor offers }
  FHost.Color := clLime;
  AssertTrue('set again, it stays', FPlain.GetColorResolvingParent = clLime);
  FHost.Color := clDefault;
  AssertLcl('set to clDefault the container is themed again', $C0, 0, $C0,
    FPlain.GetColorResolvingParent);
end;

procedure TThemedContainerColorTest.TestAControlThatTakesNoChildrenIsLeftAlone;
var
  btn: TTyButton;
begin
  MakeFixture(cBlueHost + 'TyButton { background: #C000C0; }');
  btn := TTyButton.Create(FForm);
  btn.Controller := FCtl;
  btn.Parent := FHost;
  FCtl.LoadThemeCss(cRustHost + 'TyButton { background: #C000C0; }');
  AssertTrue('a button is no container: it keeps following its parent',
    TControlAccess(btn).ParentColor);
  AssertLcl('so its LCL colour is the parent''s, not its own background', $A0, $30, $10,
    btn.Color);
end;

procedure TThemedContainerColorTest.TestTheThemedColourIsNotStreamed;
var
  txt: string;
begin
  MakeFixture(cBlueHost);
  FHost.Name := 'Host1';
  AssertLcl('precondition: the container carries the themed colour', $20, $40, $60, FHost.Color);
  txt := StreamedText(FHost);
  AssertTrue('the container streams', Pos('Host1', txt) > 0);
  AssertEquals('a themed colour is not written, even where Color is published',
    0, Pos(' Color = ', txt));
  AssertEquals('nor the ParentColor = False that comes with one', 0, Pos('ParentColor', txt));
  { the contrast: a colour the application set is }
  FHost.Color := clLime;
  txt := StreamedText(FHost);
  AssertTrue('a colour the application set is written', Pos('Color = clLime', txt) > 0);
  AssertTrue('with ParentColor = False', Pos('ParentColor = False', txt) > 0);
end;

procedure TThemedContainerColorTest.TestAContainerReadFromAStreamIsThemed;
var
  src, dst: TForm;
  p: TTyPanel;
  plain: TPanel;
  ms: TMemoryStream;
  st: TTyStyleSet;
  r, g, b: Byte;
  i: Integer;
begin
  RegisterClasses([TTyPanel, TPanel]);
  st := TyDefaultController.Model.ResolveStyle('TyPanel', '', [tysNormal]);
  AssertTrue('precondition: the default theme gives TyPanel a solid opaque background',
    (tpBackground in st.Present) and (st.Background.Kind = tfkSolid)
    and (TyAlphaOf(st.Background.Color) = 255));
  src := TForm.CreateNew(nil);
  dst := TForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  try
    p := TTyPanel.Create(src);
    p.Name := 'ReadPanel';
    p.Parent := src;
    plain := TPanel.Create(src);
    plain.Name := 'ReadPlain';
    plain.Parent := p;
    ms.WriteComponent(src);
    ms.Position := 0;
    ms.ReadComponent(dst);
    plain := nil;
    for i := 0 to dst.ComponentCount - 1 do
      if dst.Components[i].Name = 'ReadPlain' then plain := TPanel(dst.Components[i]);
    AssertNotNull('the plain panel was read', plain);
    AssertTrue('onto the themed panel', plain.Parent is TTyPanel);
    RedGreenBlue(ColorToRGB(TyColorToLCL(st.Background.Color)), r, g, b);
    AssertLcl('a container read from a form file is themed once it is loaded',
      r, g, b, plain.GetColorResolvingParent);
  finally
    ms.Free;
    dst.Free;
    src.Free;
  end;
end;

procedure TThemedContainerColorTest.TestAPlainFrameOnAThemedContainer;
var
  fr: TFrame;
  btn: TTyButton;
  c: TTyColor;
begin
  { the reported case: a designed TFrame on a themed host, a TyControls control on the frame }
  MakeFixture(cBlueHost);
  fr := TFrame.Create(FForm);
  fr.Parent := FHost;
  fr.SetBounds(230, 20, 150, 100);
  btn := TTyButton.Create(FForm);
  btn.Controller := FCtl;
  btn.Parent := fr;
  btn.SetBounds(8, 8, 80, 30);
  c := 0;
  AssertTrue('resolved', TyResolveParentBg(btn, c));
  AssertLcl('a control on a plain frame takes the host''s themed colour', $20, $40, $60,
    TyColorToLCL(c));
  FCtl.LoadThemeCss(cRustHost);
  AssertTrue('resolved', TyResolveParentBg(btn, c));
  AssertLcl('in the other theme too', $A0, $30, $10, TyColorToLCL(c));
end;

procedure TThemedContainerColorTest.TestATyFrameWithItsOwnBackground;
var
  fr: TThemedColorFrame;
  inner: TPanel;
  txt: string;
begin
  MakeFixture(cBlueHost);
  fr := TThemedColorFrame.Create(FForm);
  fr.Name := 'View1';
  fr.Controller := FCtl;
  fr.Parent := FHost;
  inner := TPanel.Create(FForm);
  inner.Parent := fr;
  fr.StyleOverride := 'background: #C000C0;';
  AssertLcl('a plain panel on a frame with a background shows that background',
    $C0, 0, $C0, inner.GetColorResolvingParent);
  FCtl.LoadThemeCss(cBlueHost + 'TyFrame { background: #00C000; }');
  fr.StyleOverride := '';
  AssertLcl('and the theme''s rule for the frame after a theme switch', 0, $C0, 0,
    inner.GetColorResolvingParent);
  txt := StreamedText(fr);
  AssertTrue('the frame streams', Pos('View1', txt) > 0);
  AssertEquals('without the themed colour, though TFrame publishes Color',
    0, Pos(' Color = ', txt));
  AssertEquals('nor the ParentColor = False that comes with one', 0, Pos('ParentColor', txt));
  AssertEquals('nor what LCL switches off along with a colour', 0, Pos('ParentBackground', txt));
  fr.Color := clLime;
  AssertTrue('a colour the application set is written',
    Pos('Color = clLime', StreamedText(fr)) > 0);
  FCtl.LoadThemeCss(cBlueHost + 'TyFrame { background: #C00000; }');
  AssertTrue('and stays through a theme switch', inner.GetColorResolvingParent = clLime);
  fr.Color := clDefault;
  AssertLcl('set to clDefault the frame is themed again', $C0, 0, 0,
    inner.GetColorResolvingParent);
end;

procedure TThemedContainerColorTest.TestATyFrameWithoutABackgroundKeepsParentColor;
var
  fr: TThemedColorFrame;
  inner: TPanel;
  txt: string;
begin
  MakeFixture(cBlueHost);
  fr := TThemedColorFrame.Create(FForm);
  fr.Controller := FCtl;
  fr.Parent := FHost;
  inner := TPanel.Create(FForm);
  inner.Parent := fr;
  AssertLcl('a plain panel on a frame without a background shows the host', $20, $40, $60,
    inner.GetColorResolvingParent);
  AssertTrue('the frame got there by ParentColor: its host carries the colour',
    fr.ParentColor);
  FCtl.LoadThemeCss(cRustHost);
  AssertLcl('in the other theme too', $A0, $30, $10, inner.GetColorResolvingParent);
  fr.Name := 'View2';
  txt := StreamedText(fr);
  AssertTrue('the frame streams', Pos('View2', txt) > 0);
  AssertEquals('and whichever way it got its colour, none of it is written',
    0, Pos(' Color = ', txt) + Pos('ParentColor', txt) + Pos('ParentBackground', txt));
end;

procedure TThemedContainerColorTest.TestATranslucentTyFrameFollowsItsHost;
var
  fr: TThemedColorFrame;
  inner: TPanel;
begin
  MakeFixture(cBlueHost);
  fr := TThemedColorFrame.Create(FForm);
  fr.Controller := FCtl;
  fr.StyleOverride := 'background: rgba(255, 255, 255, 0.5);';
  fr.Parent := FHost;
  inner := TPanel.Create(FForm);
  inner.Parent := fr;
  { half white over #204060 }
  AssertLcl('the frame''s tint over its host', $90, $A0, $B0, inner.GetColorResolvingParent);
  { the HOST alone changes: the frame owns its colour and hears of it by the parent's }
  FHost.StyleOverride := 'background: #000000;';
  AssertLcl('and over the colour the host changes to', $80, $80, $80,
    inner.GetColorResolvingParent);
end;

procedure TThemedContainerColorTest.TestATyFrameReadFromAStreamIsThemed;
var
  src, dst: TForm;
  fr: TThemedColorFrame;
  ms: TMemoryStream;
  i: Integer;
begin
  { a frame placed on a form in the designer is read with the form: it is given its parent
    while reading, when LCL sends no parent-colour message }
  RegisterClasses([TThemedColorFrame]);
  src := TForm.CreateNew(nil);
  dst := TForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  try
    fr := TThemedColorFrame.Create(src);
    fr.Name := 'ReadView';
    fr.Parent := src;
    fr.StyleOverride := 'background: #C000C0;';
    ms.WriteComponent(src);
    ms.Position := 0;
    ms.ReadComponent(dst);
    fr := nil;
    for i := 0 to dst.ComponentCount - 1 do
      if dst.Components[i].Name = 'ReadView' then fr := TThemedColorFrame(dst.Components[i]);
    AssertNotNull('the frame was read', fr);
    AssertEquals('with its override', 'background: #C000C0;', fr.StyleOverride);
    AssertLcl('a frame read with its form carries its background once it is loaded',
      $C0, 0, $C0, fr.Color);
  finally
    ms.Free;
    dst.Free;
    src.Free;
  end;
end;

procedure TThemedContainerColorTest.TestATyFrameIsLeftAloneInTheDesigner;
var
  fr: TThemedColorFrame;
begin
  MakeFixture(cBlueHost);
  fr := TThemedColorFrame.Create(FForm);
  fr.Designing;
  fr.Controller := FCtl;
  fr.Parent := FForm;
  fr.StyleOverride := 'background: #C000C0;';
  FCtl.LoadThemeCss(cRustHost);
  AssertTrue('in the designer the frame keeps ParentColor: its Color is saved with it',
    fr.ParentColor);
  AssertTrue('and the colour it has is its parent''s', fr.Color = FForm.Color);
end;

initialization
  RegisterInitComponentHandler(TThemedColorFrame, @NoFormFile);
  RegisterTest(TThemedContainerColorTest);

end.
