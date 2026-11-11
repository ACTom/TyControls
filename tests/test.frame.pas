unit test.frame;
{$mode objfpc}{$H+}

{ TTyFrame: the designer base class for an embeddable view.

  What these pin, each from the paint or the resolver's output and not from a getter:
    * with no background of its own the frame paints what is behind it -- the host's themed
      background, as the SLICE the frame covers, so a gradient host shows no seam;
    * a theme rule, a StyleClass or a StyleOverride gives it a background of its own;
    * a control on the frame resolves "what is behind me" through it, the same way;
    * as the designer's root it has no host and paints the TyForm background;
    * a descendant is built from its form file like any frame, the bare class without one.

  A frame class other than TFrame is built from a form file (TCustomFrame.Create), so the
  access class below registers an init handler that says it has none. }

interface

uses
  Classes, SysUtils, Types, Graphics, Controls, Forms, LCLType, LResources, TypInfo,
  BGRABitmap, BGRABitmapTypes,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Base, tyControls.Painter, tyControls.Controller,
  tyControls.StyleModel, tyControls.BuiltinThemes, tyControls.Panel, tyControls.Button,
  tyControls.Form, tyControls.Frame;

type
  TFrameAccess = class(TTyFrame)
  public
    Renders: Integer;
    Invalidates: Integer;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); override;
    procedure Invalidate; override;
    { The real route: what TWinControl.PaintHandler calls with the window's DC. }
    procedure PaintOn(ADC: HDC);
    procedure Designing;
    property OnPaint;
  end;

  { A frame as an application writes one: its own class, a form file, a published field. }
  TDesignedView = class(TTyFrame)
  published
    Ctl1: TTyStyleController;
    Btn: TTyButton;
  end;

  { A descendant with no form file and no handler: LCL's rule for it stands. }
  TViewWithoutFormFile = class(TTyFrame);

  TTyFrameTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FPanel: TTyPanel;
    FFrame: TFrameAccess;
    FOnPaints: Integer;
    procedure CountOnPaint(Sender: TObject);
    procedure MakeFixture(const ACss: string);
    { RenderTo over the frame's own size, on a magenta ground a frame that paints nothing
      leaves showing. }
    function Shot: TBGRABitmap;
    function PaintShot: TBGRABitmap;
    function PixelAt(AX, AY: Integer): TBGRAPixel;
    { AFill laid over AW x AH by the painter, at (AX, AY): what a seamless slice must match. }
    function OracleAt(const AFill: TTyFill; AW, AH, AX, AY: Integer): TBGRAPixel;
    procedure AssertPx(const AMsg: string; AWant: TBGRAPixel; AGot: TBGRAPixel);
    procedure AssertRgb(const AMsg: string; AR, AG, AB: Byte; AGot: TBGRAPixel);
    procedure AssertColor(const AMsg: string; AR, AG, AB: Byte; AGot: TTyColor);
  protected
    procedure TearDown; override;
  published
    procedure TestBareFrameIsBuiltWithoutAFormFile;
    procedure TestADescendantIsBuiltFromItsFormFile;
    procedure TestNoBuiltinThemeGivesTheFrameABackground;
    procedure TestWithoutABackgroundItPaintsTheHostsColour;
    procedure TestOnAGradientHostItPaintsItsOwnSlice;
    procedure TestOnAPlainParentItPaintsTheParentsColour;
    procedure TestAThemeRuleAStyleClassAndAStyleOverrideGiveItABackground;
    procedure TestItsOwnGradientRunsOverTheFrame;
    procedure TestAChildSeesTheHostThroughABackgroundlessFrame;
    procedure TestAChildOnAGradientHostGetsTheSliceWhereItSits;
    procedure TestAChildSeesTheFramesOwnBackground;
    procedure TestAChildOnATranslucentFrameSeesItOverTheHost;
    procedure TestThemedBgColorAnswersOnlyASolidColour;
    procedure TestAThemeChangeReachesTheFrame;
    procedure TestAFrameNeverGivenAControllerFollowsTheDefault;
    procedure TestAFreedFrameIsForgottenByItsController;
    procedure TestADisabledFrameTakesTheDisabledRule;
    procedure TestPaintStillFiresOnPaint;
    procedure TestTheFrameFollowsItsOwnController;
    procedure TestFreeingTheControllerLeavesTheFrameOnTheDefault;
    procedure TestStyleClassAndStyleOverrideRepaint;
    procedure TestPublishedPropertiesReadAndStream;
    procedure TestAsTheDesignersRootItPaintsTheFormBackground;
    procedure TestADesignedInFrameStillPaintsItsHost;
    procedure TestChildDamageDoesNotRenderAgain;
    procedure TestAHostThatChangedIsPaintedAgain;
    procedure TestTheDesignerPaintsWithoutTheCache;
  end;

  { The design-time half cannot be linked into the tests (it uses IDEIntf); these read it. }
  TTyFrameDesignTest = class(TTestCase)
  private
    function NewItemsSource: string;
    function Squeezed(const S: string): string;
  published
    procedure TestTheFrameIsADesignerBaseClass;
    procedure TestTheNewItemTemplateDescribesAFrame;
    procedure TestTheTemplateTextsAreTranslated;
  end;

implementation

uses
  test.designregistry;

const
  cTol = 4;   // scanner dithering, as the drawframe gradient guards allow
  cFlat = 'border-width: 0px; border-radius: 0px; padding: 0px; ';
  cSolidHost = 'TyPanel { background: #204060; ' + cFlat + '}';
  { 90deg is the vertical axis: red at the top of the panel, blue at the bottom. }
  cGradientHost = 'TyPanel { background: linear-gradient(90deg, #FF0000, #0000FF); ' + cFlat + '}';
  cPanelW = 400;
  cPanelH = 300;

function NoFormFile(Instance: TComponent; RootAncestor: TClass): Boolean;
begin
  Result := Instance.ClassType = TFrameAccess;
end;

{ TFrameAccess }

procedure TFrameAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  Inc(Renders);
  inherited RenderTo(ACanvas, ARect, APPI);
end;

var
  { Counted outside the instance: a controller that still holds a freed frame calls into it. }
  GFrameInvalidates: Integer = 0;

procedure TFrameAccess.Invalidate;
begin
  Inc(Invalidates);
  Inc(GFrameInvalidates);
  inherited Invalidate;
end;

procedure TFrameAccess.PaintOn(ADC: HDC);
begin
  PaintWindow(ADC);
end;

procedure TFrameAccess.Designing;
begin
  SetDesigning(True);
end;

{ TTyFrameTest }

procedure TTyFrameTest.MakeFixture(const ACss: string);
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(ACss);
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 640, 480);
  FPanel := TTyPanel.Create(FForm);
  FPanel.Parent := FForm;
  FPanel.Controller := FCtl;
  FPanel.SetBounds(0, 0, cPanelW, cPanelH);
  FFrame := TFrameAccess.Create(nil);
  FFrame.Controller := FCtl;
  FFrame.Parent := FPanel;
  FFrame.SetBounds(40, 60, 200, 120);
end;

procedure TTyFrameTest.TearDown;
begin
  FreeAndNil(FFrame);
  FreeAndNil(FForm);   // owns the panel
  FreeAndNil(FCtl);
end;

function TTyFrameTest.Shot: TBGRABitmap;
var
  b: TBitmap;
begin
  b := TBitmap.Create;
  try
    b.PixelFormat := pf32bit;
    b.SetSize(FFrame.Width, FFrame.Height);
    b.Canvas.Brush.Color := clFuchsia;
    b.Canvas.FillRect(0, 0, b.Width, b.Height);
    FFrame.RenderTo(b.Canvas, Rect(0, 0, b.Width, b.Height), 96);
    Result := TBGRABitmap.Create(b);
  finally
    b.Free;
  end;
end;

function TTyFrameTest.PaintShot: TBGRABitmap;
var
  b: TBitmap;
begin
  b := TBitmap.Create;
  try
    b.PixelFormat := pf32bit;
    b.SetSize(FFrame.Width, FFrame.Height);
    b.Canvas.Brush.Color := clFuchsia;
    b.Canvas.FillRect(0, 0, b.Width, b.Height);
    FFrame.PaintOn(b.Canvas.Handle);
    Result := TBGRABitmap.Create(b);
  finally
    b.Free;
  end;
end;

function TTyFrameTest.PixelAt(AX, AY: Integer): TBGRAPixel;
var
  s: TBGRABitmap;
begin
  s := Shot;
  try
    Result := s.GetPixel(AX, AY);
  finally
    s.Free;
  end;
end;

function TTyFrameTest.OracleAt(const AFill: TTyFill; AW, AH, AX, AY: Integer): TBGRAPixel;
var
  p: TTyPainter;
  host: TBitmap;
  img: TBGRABitmap;
begin
  host := TBitmap.Create;
  try
    host.PixelFormat := pf32bit;
    host.SetSize(AW, AH);
    p := TTyPainter.Create;
    try
      p.BeginPaint(host.Canvas, Rect(0, 0, AW, AH), 96);
      p.FillBackground(Rect(0, 0, AW, AH), AFill, 0);
      p.EndPaint;
    finally
      p.Free;
    end;
    img := TBGRABitmap.Create(host);
    try
      Result := img.GetPixel(AX, AY);
    finally
      img.Free;
    end;
  finally
    host.Free;
  end;
end;

procedure TTyFrameTest.AssertPx(const AMsg: string; AWant: TBGRAPixel; AGot: TBGRAPixel);
begin
  AssertTrue(Format('%s (want #%.2x%.2x%.2x, got #%.2x%.2x%.2x)',
    [AMsg, AWant.red, AWant.green, AWant.blue, AGot.red, AGot.green, AGot.blue]),
    (Abs(AGot.red - AWant.red) <= cTol) and (Abs(AGot.green - AWant.green) <= cTol)
    and (Abs(AGot.blue - AWant.blue) <= cTol));
end;

procedure TTyFrameTest.AssertRgb(const AMsg: string; AR, AG, AB: Byte; AGot: TBGRAPixel);
begin
  AssertPx(AMsg, BGRA(AR, AG, AB), AGot);
end;

procedure TTyFrameTest.AssertColor(const AMsg: string; AR, AG, AB: Byte; AGot: TTyColor);
begin
  AssertPx(AMsg, BGRA(AR, AG, AB), BGRA(TyRedOf(AGot), TyGreenOf(AGot), TyBlueOf(AGot)));
end;

procedure TTyFrameTest.TestBareFrameIsBuiltWithoutAFormFile;
var
  f: TTyFrame;
  raised: Boolean;
begin
  f := TTyFrame.Create(nil);
  try
    AssertEquals('a frame''s default width', 320, f.Width);
    AssertEquals('a frame''s default height', 240, f.Height);
  finally
    f.Free;
  end;
  { Only the class itself: a view somebody wrote and forgot the form file of still says so. }
  raised := False;
  try
    TViewWithoutFormFile.Create(nil).Free;
  except
    on E: EResNotFound do raised := True;
  end;
  AssertTrue('a descendant without a form file raises as any frame does', raised);
end;

const
  cDesignedLfm =
    'object DesignedView: TDesignedView'#10 +
    '  Left = 0'#10 +
    '  Height = 150'#10 +
    '  Top = 0'#10 +
    '  Width = 260'#10 +
    '  Controller = Ctl1'#10 +
    '  StyleClass = ''side'''#10 +
    '  StyleOverride = ''background: #102030;'''#10 +
    '  object Btn: TTyButton'#10 +
    '    Left = 8'#10 +
    '    Height = 30'#10 +
    '    Top = 12'#10 +
    '    Width = 90'#10 +
    '  end'#10 +
    '  object Ctl1: TTyStyleController'#10 +
    '    Left = 120'#10 +
    '    Top = 40'#10 +
    '  end'#10 +
    'end'#10;

var
  GDesignedViewRegistered: Boolean = False;

procedure NeedDesignedViewFormFile;
var
  txt: TStringStream;
  bin: TMemoryStream;
  s: AnsiString;
begin
  if GDesignedViewRegistered then Exit;
  GDesignedViewRegistered := True;
  RegisterClasses([TTyButton, TTyStyleController]);
  txt := TStringStream.Create(cDesignedLfm);
  bin := TMemoryStream.Create;
  try
    LRSObjectTextToBinary(txt, bin);
    s := '';
    SetLength(s, bin.Size);
    Move(bin.Memory^, s[1], bin.Size);
    LazarusResources.Add('TDesignedView', 'FORMDATA', s);
  finally
    bin.Free;
    txt.Free;
  end;
end;

procedure TTyFrameTest.TestADescendantIsBuiltFromItsFormFile;
var
  v: TDesignedView;
  host: TForm;
  c: TTyColor;
begin
  NeedDesignedViewFormFile;
  v := TDesignedView.Create(nil);
  host := TForm.CreateNew(nil);
  try
    AssertEquals('bounds come from the form file', 260, v.Width);
    AssertEquals('StyleClass is read', 'side', v.StyleClass);
    AssertEquals('StyleOverride is read', 'background: #102030;', v.StyleOverride);
    AssertNotNull('the published field is bound', v.Btn);
    AssertSame('the button sits on the frame', v, v.Btn.Parent);
    AssertNotNull('the controller on the frame is bound', v.Ctl1);
    AssertSame('Controller = Ctl1 is resolved', v.Ctl1, v.Controller);
    { and the frame listens to THAT controller, though it was assigned while loading }
    v.Parent := host;
    v.Btn.Controller := v.Ctl1;
    c := 0;
    AssertTrue(TyResolveParentBg(v.Btn, c));
    AssertColor('the button sees the override''s background', $10, $20, $30, c);
    v.Ctl1.LoadThemeCss('TyFrame.side { background: #AA0000; }');
    v.StyleOverride := '';
    AssertTrue(TyResolveParentBg(v.Btn, c));
    AssertColor('and the loaded StyleClass picks its rule on the loaded controller',
      $AA, 0, 0, c);
  finally
    v.Free;
    host.Free;
  end;
end;

{ A frame is scaffolding: shipped themes leave 'TyFrame' without a background, so it takes
  the look of whatever hosts it. A theme that wants a surface defines the key. }
procedure TTyFrameTest.TestNoBuiltinThemeGivesTheFrameABackground;
var
  c: TTyStyleController;
  names: TStringArray;
  i: Integer;
  st: TTyStyleSet;
begin
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  try
    names := TyBuiltinThemeNames;
    AssertTrue('the built-in themes are listed', Length(names) > 5);
    for i := 0 to High(names) do
    begin
      c.ThemeName := names[i];
      st := c.Model.ResolveStyle('TyFrame', '', []);
      AssertFalse('theme ' + names[i] + ' must not give TyFrame a background',
        tpBackground in st.Present);
    end;
    { the contrast: the resolver does not answer empty for every key }
    c.ThemeName := 'default';
    st := c.Model.ResolveStyle('TyPanel', '', []);
    AssertTrue('TyPanel has a background (contrast)', tpBackground in st.Present);
    c.LoadThemeCss('TyFrame { background: #FF0000; }');
    st := c.Model.ResolveStyle('TyFrame', '', []);
    AssertTrue('and a theme can opt in', tpBackground in st.Present);
  finally
    c.Free;
  end;
end;

procedure TTyFrameTest.TestWithoutABackgroundItPaintsTheHostsColour;
begin
  MakeFixture(cSolidHost);
  AssertRgb('the host''s colour in the middle', $20, $40, $60, PixelAt(100, 60));
  AssertRgb('and in the corner', $20, $40, $60, PixelAt(0, 0));
  FCtl.LoadThemeCss('TyPanel { background: #A03010; ' + cFlat + '}');
  AssertRgb('and the new one after a theme change', $A0, $30, $10, PixelAt(100, 60));
end;

procedure TTyFrameTest.TestOnAGradientHostItPaintsItsOwnSlice;
var
  host: TTyStyleSet;
  s: TBGRABitmap;
  top, bottom, wantTop, wantBottom: TBGRAPixel;
begin
  MakeFixture(cGradientHost);
  host := FCtl.Model.ResolveStyle('TyPanel', '', []);
  s := Shot;
  try
    top := s.GetPixel(100, 2);
    bottom := s.GetPixel(100, FFrame.Height - 3);
  finally
    s.Free;
  end;
  wantTop := OracleAt(host.Background, cPanelW, cPanelH, FFrame.Left + 100, FFrame.Top + 2);
  wantBottom := OracleAt(host.Background, cPanelW, cPanelH, FFrame.Left + 100,
    FFrame.Top + FFrame.Height - 3);
  AssertTrue('the host really varies over the frame''s rows',
    Abs(wantTop.red - wantBottom.red) > 60);
  AssertPx('the frame''s top row is the host''s row there', wantTop, top);
  AssertPx('the frame''s bottom row is the host''s row there', wantBottom, bottom);
  { moved down the ramp, it paints the rows it now covers }
  FFrame.Top := 150;
  wantTop := OracleAt(host.Background, cPanelW, cPanelH, FFrame.Left + 100, 152);
  AssertPx('after a move, the rows it now covers', wantTop, PixelAt(100, 2));
end;

procedure TTyFrameTest.TestOnAPlainParentItPaintsTheParentsColour;
begin
  MakeFixture(cSolidHost);
  FFrame.Parent := FForm;
  FForm.Color := TColor($0000C0);   // LCL colour: BGR, so red C0
  AssertRgb('a plain parent''s colour', $C0, 0, 0, PixelAt(50, 50));
  FForm.Color := TColor($00C000);
  AssertRgb('and the one it changes to', 0, $C0, 0, PixelAt(50, 50));
end;

procedure TTyFrameTest.TestAThemeRuleAStyleClassAndAStyleOverrideGiveItABackground;
begin
  MakeFixture(cSolidHost + 'TyFrame.side { background: #00C000; }');
  AssertRgb('no rule: the host', $20, $40, $60, PixelAt(100, 60));
  FFrame.StyleClass := 'side';
  AssertRgb('StyleClass picks the variant''s background', 0, $C0, 0, PixelAt(100, 60));
  FFrame.StyleOverride := 'background: #0000C0;';
  AssertRgb('StyleOverride wins over it', 0, 0, $C0, PixelAt(100, 60));
  FFrame.StyleOverride := '';
  FFrame.StyleClass := '';
  FCtl.LoadThemeCss(cSolidHost + 'TyFrame { background: #C00000; }');
  AssertRgb('a theme rule for the key', $C0, 0, 0, PixelAt(100, 60));
end;

procedure TTyFrameTest.TestItsOwnGradientRunsOverTheFrame;
var
  st: TTyStyleSet;
  s: TBGRABitmap;
begin
  { 0deg runs left to right }
  MakeFixture(cSolidHost + 'TyFrame { background: linear-gradient(0deg, #FF0000, #0000FF); }');
  st := FCtl.Model.ResolveStyle('TyFrame', '', []);
  s := Shot;
  try
    AssertPx('left edge', OracleAt(st.Background, FFrame.Width, FFrame.Height, 3, 60),
      s.GetPixel(3, 60));
    AssertPx('right edge', OracleAt(st.Background, FFrame.Width, FFrame.Height,
      FFrame.Width - 4, 60), s.GetPixel(FFrame.Width - 4, 60));
    AssertTrue('red on the left, blue on the right',
      (s.GetPixel(3, 60).red > 200) and (s.GetPixel(FFrame.Width - 4, 60).blue > 200));
  finally
    s.Free;
  end;
end;

procedure TTyFrameTest.TestAChildSeesTheHostThroughABackgroundlessFrame;
var
  btn: TTyButton;
  c: TTyColor;
begin
  MakeFixture(cSolidHost);
  btn := TTyButton.Create(FFrame);
  btn.Parent := FFrame;
  btn.Controller := FCtl;
  btn.SetBounds(10, 20, 80, 30);
  c := 0;
  AssertTrue('resolved', TyResolveParentBg(btn, c));
  AssertColor('the host''s themed colour, not the frame''s LCL colour', $20, $40, $60, c);
  FCtl.LoadThemeCss('TyPanel { background: #A03010; ' + cFlat + '}');
  AssertTrue('resolved', TyResolveParentBg(btn, c));
  AssertColor('and the new one after a theme change', $A0, $30, $10, c);
end;

procedure TTyFrameTest.TestAChildOnAGradientHostGetsTheSliceWhereItSits;
var
  btn: TTyButton;
  host: TTyStyleSet;
  f: TTyFill;
  r: TRect;
  want: TBGRAPixel;
  c: TTyColor;
begin
  MakeFixture(cGradientHost);
  host := FCtl.Model.ResolveStyle('TyPanel', '', []);
  btn := TTyButton.Create(FFrame);
  btn.Parent := FFrame;
  btn.Controller := FCtl;
  btn.SetBounds(10, 20, 80, 30);
  r := Rect(0, 0, btn.Width, btn.Height);
  AssertTrue('resolved', TyResolveParentBgFill(btn, r, f));
  AssertTrue('still a gradient, not one flat colour', f.Kind = tfkLinearGradient);
  { the slice's ends are the host's rows at the button's top and bottom, through TWO offsets }
  want := OracleAt(host.Background, cPanelW, cPanelH, 100, FFrame.Top + btn.Top);
  AssertColor('the slice starts at the host''s row under the button''s top',
    want.red, want.green, want.blue, f.GradFrom);
  want := OracleAt(host.Background, cPanelW, cPanelH, 100, FFrame.Top + btn.Top + btn.Height);
  AssertColor('and ends at the row under its bottom', want.red, want.green, want.blue, f.GradTo);
  { the frame's own offset counts: moved, the same button answers another slice }
  FFrame.Top := 150;
  c := 0;
  AssertTrue('resolved', TyResolveParentBg(btn, c));
  want := OracleAt(host.Background, cPanelW, cPanelH, 100, 150 + btn.Top + btn.Height div 2);
  AssertColor('after the frame moved, the row under the button''s centre',
    want.red, want.green, want.blue, c);
end;

procedure TTyFrameTest.TestAChildSeesTheFramesOwnBackground;
var
  btn: TTyButton;
  c: TTyColor;
  f: TTyFill;
  st: TTyStyleSet;
  want: TBGRAPixel;
begin
  MakeFixture(cSolidHost);
  btn := TTyButton.Create(FFrame);
  btn.Parent := FFrame;
  btn.Controller := FCtl;
  btn.SetBounds(120, 20, 60, 30);
  FFrame.StyleOverride := 'background: #0000C0;';
  c := 0;
  AssertTrue('resolved', TyResolveParentBg(btn, c));
  AssertColor('the frame''s own solid background', 0, 0, $C0, c);
  { its own gradient, rebased to where the button sits: 0deg runs left to right }
  FFrame.StyleOverride := 'background: linear-gradient(0deg, #FF0000, #0000FF);';
  AssertTrue('resolved', TyResolveParentBgFill(btn, Rect(0, 0, btn.Width, btn.Height), f));
  AssertTrue('a gradient slice', f.Kind = tfkLinearGradient);
  st := FCtl.Model.ResolveOverride(FFrame.StyleOverride);
  want := OracleAt(st.Background, FFrame.Width, FFrame.Height, btn.Left, 30);
  AssertColor('the slice starts at the frame''s column under the button''s left edge',
    want.red, want.green, want.blue, f.GradFrom);
  want := OracleAt(st.Background, FFrame.Width, FFrame.Height, btn.Left + btn.Width - 1, 30);
  AssertColor('and ends at the column under its right edge',
    want.red, want.green, want.blue, f.GradTo);
end;

procedure TTyFrameTest.TestAChildOnATranslucentFrameSeesItOverTheHost;
var
  btn: TTyButton;
  c: TTyColor;
begin
  MakeFixture(cSolidHost);
  btn := TTyButton.Create(FFrame);
  btn.Parent := FFrame;
  btn.Controller := FCtl;
  btn.SetBounds(10, 20, 80, 30);
  { half red over #204060: (255 + 0x20) / 2, 0x40 / 2, 0x60 / 2 }
  FFrame.StyleOverride := 'background: rgba(255, 0, 0, 0.5);';
  c := 0;
  AssertTrue('resolved', TyResolveParentBg(btn, c));
  AssertEquals('the promise is an opaque colour', 255, TyAlphaOf(c));
  AssertColor('the frame''s tint over the host', $8F, $20, $30, c);
  { fully transparent is no background at all }
  FFrame.StyleOverride := 'background: rgba(255, 0, 0, 0);';
  AssertTrue('resolved', TyResolveParentBg(btn, c));
  AssertColor('a transparent background shows the host', $20, $40, $60, c);
end;

procedure TTyFrameTest.TestThemedBgColorAnswersOnlyASolidColour;
var
  tb: ITyThemedBackground;
  c: TTyColor;
begin
  MakeFixture(cSolidHost);
  AssertTrue('the frame answers ITyThemedBackground', Supports(FFrame, ITyThemedBackground, tb));
  c := 0;
  AssertTrue('a solid host is a solid answer', tb.ThemedBgColor(c));
  AssertColor('the host''s colour', $20, $40, $60, c);
  FFrame.StyleOverride := 'background: #0000C0;';
  AssertTrue('its own solid background is one too', tb.ThemedBgColor(c));
  AssertColor('its own colour', 0, 0, $C0, c);
  FFrame.StyleOverride := 'background: linear-gradient(0deg, #FF0000, #0000FF);';
  AssertFalse('its own gradient is not one colour', tb.ThemedBgColor(c));
  FFrame.StyleOverride := '';
  FCtl.LoadThemeCss(cGradientHost);
  AssertFalse('nor is a gradient host', tb.ThemedBgColor(c));
  tb := nil;
end;

procedure TTyFrameTest.TestAThemeChangeReachesTheFrame;
var
  n: Integer;
begin
  MakeFixture(cSolidHost);
  n := FFrame.Invalidates;
  FCtl.LoadThemeCss(cGradientHost);
  AssertTrue('a theme loaded into its controller invalidates the frame',
    FFrame.Invalidates > n);
end;

procedure TTyFrameTest.TestAFrameNeverGivenAControllerFollowsTheDefault;
var
  f: TFrameAccess;
  n: Integer;
begin
  { the common case: no Controller property set anywhere, the application themes the
    default controller }
  f := TFrameAccess.Create(nil);
  try
    AssertNull('no controller of its own', f.Controller);
    n := f.Invalidates;
    TyDefaultController.Changed;
    AssertTrue('a change of the default controller''s theme invalidates it',
      f.Invalidates > n);
  finally
    f.Free;
  end;
  { and once it is gone the controller no longer holds it }
  TyDefaultController.Changed;
end;

procedure TTyFrameTest.TestAFreedFrameIsForgottenByItsController;
var
  f: TFrameAccess;
  own: TTyStyleController;
  n: Integer;
begin
  { on the default controller }
  f := TFrameAccess.Create(nil);
  f.Free;
  n := GFrameInvalidates;
  TyDefaultController.Changed;
  AssertEquals('the default controller does not call a frame that is gone',
    n, GFrameInvalidates);
  { on a controller of its own }
  own := TTyStyleController.Create(nil);
  try
    f := TFrameAccess.Create(nil);
    f.Controller := own;
    f.Free;
    n := GFrameInvalidates;
    own.Changed;
    AssertEquals('nor does its own controller', n, GFrameInvalidates);
  finally
    own.Free;
  end;
end;

procedure TTyFrameTest.TestADisabledFrameTakesTheDisabledRule;
begin
  MakeFixture(cSolidHost + 'TyFrame:disabled { background: #808080; }');
  AssertRgb('enabled: no rule, the host', $20, $40, $60, PixelAt(100, 60));
  FFrame.Enabled := False;
  AssertRgb('disabled: the :disabled rule', $80, $80, $80, PixelAt(100, 60));
  FFrame.Enabled := True;
  FPanel.Enabled := False;
  AssertRgb('and on a disabled host too, as every control looks disabled there',
    $80, $80, $80, PixelAt(100, 60));
end;

procedure TTyFrameTest.CountOnPaint(Sender: TObject);
begin
  Inc(FOnPaints);
end;

procedure TTyFrameTest.TestPaintStillFiresOnPaint;
begin
  MakeFixture(cSolidHost);
  FFrame.OnPaint := @CountOnPaint;
  FOnPaints := 0;
  PaintShot.Free;
  AssertEquals('a rendered paint fires OnPaint', 1, FOnPaints);
  PaintShot.Free;
  AssertEquals('and so does one that only shows the kept frame', 2, FOnPaints);
end;

procedure TTyFrameTest.TestTheFrameFollowsItsOwnController;
var
  other: TTyStyleController;
  n: Integer;
begin
  MakeFixture(cSolidHost + 'TyFrame { background: #C00000; }');
  other := TTyStyleController.Create(nil);
  try
    other.LoadThemeCss('TyFrame { background: #00C000; }');
    AssertRgb('the first controller''s rule', $C0, 0, 0, PixelAt(100, 60));
    FFrame.Controller := other;
    AssertRgb('the second controller''s rule', 0, $C0, 0, PixelAt(100, 60));
    n := FFrame.Invalidates;
    FCtl.LoadThemeCss(cSolidHost);
    AssertEquals('the controller it left no longer invalidates it', n, FFrame.Invalidates);
    other.LoadThemeCss('TyFrame { background: #0000C0; }');
    AssertTrue('the one it took does', FFrame.Invalidates > n);
    { unset: the default controller, whose theme gives the key nothing }
    FFrame.Controller := nil;
    AssertRgb('without a controller, the default theme: the host', $20, $40, $60,
      PixelAt(100, 60));
    n := FFrame.Invalidates;
    TyDefaultController.Changed;
    AssertTrue('and the default controller invalidates it', FFrame.Invalidates > n);
  finally
    FFrame.Controller := nil;
    other.Free;
  end;
end;

procedure TTyFrameTest.TestFreeingTheControllerLeavesTheFrameOnTheDefault;
var
  other: TTyStyleController;
  n: Integer;
begin
  MakeFixture(cSolidHost);
  other := TTyStyleController.Create(nil);
  other.LoadThemeCss('TyFrame { background: #00C000; }');
  FFrame.Controller := other;
  AssertRgb('the controller''s rule', 0, $C0, 0, PixelAt(100, 60));
  other.Free;
  AssertNull('the reference is dropped with the controller', FFrame.Controller);
  AssertRgb('and the frame paints on: the host', $20, $40, $60, PixelAt(100, 60));
  n := FFrame.Invalidates;
  TyDefaultController.Changed;
  AssertTrue('listening to the default controller from then on', FFrame.Invalidates > n);
end;

procedure TTyFrameTest.TestStyleClassAndStyleOverrideRepaint;
var
  n: Integer;
begin
  MakeFixture(cSolidHost);
  n := FFrame.Invalidates;
  FFrame.StyleClass := 'side';
  AssertTrue('a new StyleClass invalidates', FFrame.Invalidates > n);
  n := FFrame.Invalidates;
  FFrame.StyleClass := 'side';
  AssertEquals('the same one does not', n, FFrame.Invalidates);
  FFrame.StyleOverride := 'background: #0000C0;';
  AssertTrue('a new StyleOverride invalidates', FFrame.Invalidates > n);
  n := FFrame.Invalidates;
  FFrame.StyleOverride := 'background: #0000C0;';
  AssertEquals('the same one does not', n, FFrame.Invalidates);
end;

procedure TTyFrameTest.TestPublishedPropertiesReadAndStream;
var
  f: TTyFrame;
  pi: PPropInfo;
  ms: TMemoryStream;
  txt: string;

  function Streamed: string;
  begin
    ms.Clear;
    WriteComponentAsTextToStream(ms, f);
    Result := '';
    SetLength(Result, ms.Size);
    if ms.Size > 0 then Move(ms.Memory^, Result[1], ms.Size);
  end;

begin
  f := TTyFrame.Create(nil);
  ms := TMemoryStream.Create;
  try
    f.Name := 'View1';
    { the inspector reads every published property: each needs a getter }
    pi := GetPropInfo(f, 'Controller');
    AssertTrue('Controller is published and readable', (pi <> nil) and (pi^.GetProc <> nil));
    pi := GetPropInfo(f, 'StyleClass');
    AssertTrue('StyleClass is published and readable', (pi <> nil) and (pi^.GetProc <> nil));
    pi := GetPropInfo(f, 'StyleOverride');
    AssertTrue('StyleOverride is published and readable', (pi <> nil) and (pi^.GetProc <> nil));
    pi := GetPropInfo(f, 'Version');
    AssertTrue('Version is published and readable', (pi <> nil) and (pi^.GetProc <> nil));
    AssertTrue('Version has no setter, so it is never written to a form file',
      pi^.SetProc = nil);
    AssertEquals('Version reports the library''s', TyVersion, GetStrProp(f, 'Version'));
    txt := Streamed;
    AssertTrue('the frame streams', Pos('View1', txt) > 0);
    AssertEquals('a fresh frame writes no StyleClass', 0, Pos('StyleClass', txt));
    AssertEquals('nor a StyleOverride', 0, Pos('StyleOverride', txt));
    AssertEquals('nor a Controller', 0, Pos('Controller', txt));
    { '  Version', not 'Version': Lazarus 3.0 writes TFrame's own LCLVersion here }
    AssertEquals('nor a Version', 0, Pos('  Version =', txt));
    f.StyleClass := 'side';
    f.StyleOverride := 'background: #102030;';
    txt := Streamed;
    AssertTrue('StyleClass is written once set', Pos('StyleClass = ''side''', txt) > 0);
    AssertTrue('StyleOverride is written once set',
      Pos('StyleOverride = ''background: #102030;''', txt) > 0);
  finally
    ms.Free;
    f.Free;
  end;
end;

procedure TTyFrameTest.TestAsTheDesignersRootItPaintsTheFormBackground;
var
  btn: TTyButton;
  c: TTyColor;
begin
  MakeFixture(cSolidHost + 'TyForm { background: #405060; }');
  { the designer's root: designing, owned by nobody, on the designer's own plain window }
  FFrame.Parent := FForm;
  FForm.Color := TColor($0000C0);
  AssertRgb('at run time a plain parent''s colour', $C0, 0, 0, PixelAt(50, 50));
  FFrame.Designing;
  AssertRgb('as the designer''s root, the form background it will sit on', $40, $50, $60,
    PixelAt(50, 50));
  btn := TTyButton.Create(FFrame);
  btn.Parent := FFrame;
  btn.Controller := FCtl;
  btn.SetBounds(10, 20, 80, 30);
  c := 0;
  AssertTrue('resolved', TyResolveParentBg(btn, c));
  AssertColor('and the controls on it see the same', $40, $50, $60, c);
  FCtl.LoadThemeCss('TyForm { background: #607080; }');
  AssertRgb('it follows the theme', $60, $70, $80, PixelAt(50, 50));
  FFrame.StyleOverride := 'background: #0000C0;';
  AssertRgb('its own background still wins', 0, 0, $C0, PixelAt(50, 50));
end;

procedure TTyFrameTest.TestADesignedInFrameStillPaintsItsHost;
var
  owner: TComponent;
  f: TFrameAccess;
begin
  { a frame placed on a form in the designer has an owner: it is not the root }
  MakeFixture(cSolidHost + 'TyForm { background: #405060; }');
  owner := TComponent.Create(nil);
  try
    f := TFrameAccess.Create(owner);
    f.Controller := FCtl;
    f.Parent := FPanel;
    f.SetBounds(40, 60, 200, 120);
    f.Designing;
    FreeAndNil(FFrame);
    FFrame := f;
    AssertRgb('placed on a host in the designer, it shows the host', $20, $40, $60,
      PixelAt(50, 50));
  finally
    FFrame := nil;
    owner.Free;   // frees f
  end;
end;

procedure TTyFrameTest.TestChildDamageDoesNotRenderAgain;
var
  s: TBGRABitmap;
begin
  MakeFixture(cSolidHost);
  FFrame.Renders := 0;
  s := PaintShot;
  try
    AssertRgb('the paint message draws the host''s colour', $20, $40, $60, s.GetPixel(100, 60));
  finally
    s.Free;
  end;
  AssertEquals('the first paint renders', 1, FFrame.Renders);
  s := PaintShot;
  try
    AssertRgb('the second paint shows the same', $20, $40, $60, s.GetPixel(100, 60));
  finally
    s.Free;
  end;
  AssertEquals('a paint nothing asked for (a child''s damage) does not render again',
    1, FFrame.Renders);
  FFrame.Invalidate;
  PaintShot.Free;
  AssertEquals('one that follows an Invalidate does', 2, FFrame.Renders);
end;

procedure TTyFrameTest.TestAHostThatChangedIsPaintedAgain;
var
  s: TBGRABitmap;
  host: TTyStyleSet;
  before, want: TBGRAPixel;
  n: Integer;
begin
  { What is behind the frame can change without the frame being told. A host that is
    resized lays its gradient over another height: the frame, which did not move, now
    covers other colours of it. }
  MakeFixture(cGradientHost);
  host := FCtl.Model.ResolveStyle('TyPanel', '', []);
  s := PaintShot;
  try
    before := s.GetPixel(100, 60);
  finally
    s.Free;
  end;
  n := FFrame.Invalidates;
  FPanel.SetBounds(0, 0, cPanelW, 200);
  AssertEquals('precondition: resizing the host did not invalidate the frame',
    n, FFrame.Invalidates);
  want := OracleAt(host.Background, cPanelW, 200, FFrame.Left + 100, FFrame.Top + 60);
  AssertTrue('precondition: the host''s row under the probe moved',
    Abs(want.red - before.red) > 30);
  s := PaintShot;
  try
    AssertPx('the next paint shows the host as it is now', want, s.GetPixel(100, 60));
  finally
    s.Free;
  end;
end;

procedure TTyFrameTest.TestTheDesignerPaintsWithoutTheCache;
begin
  MakeFixture(cSolidHost);
  FFrame.Designing;
  FFrame.Renders := 0;
  PaintShot.Free;
  PaintShot.Free;
  AssertEquals('the designer renders every paint', 2, FFrame.Renders);
end;

{ TTyFrameDesignTest }

function TTyFrameDesignTest.NewItemsSource: string;
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(RepoRoot + 'designtime' + PathDelim + 'tyControls.Design.NewItems.pas');
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

function TTyFrameDesignTest.Squeezed(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    if not (S[i] in [' ', #9, #10, #13]) then Result := Result + S[i];
end;

procedure TTyFrameDesignTest.TestTheFrameIsADesignerBaseClass;
var
  names: TStringList;
begin
  names := TStringList.Create;
  try
    CollectDesignerBaseClassNames(names);
    AssertTrue('the parse still finds TTyForm', names.IndexOf('TTyForm') >= 0);
    AssertTrue('TTyFrame is registered with RegisterDesignerBaseClass: without it the designer'
      + ' opens class(TTyFrame) as a plain TFrame', names.IndexOf('TTyFrame') >= 0);
  finally
    names.Free;
  end;
end;

procedure TTyFrameDesignTest.TestTheNewItemTemplateDescribesAFrame;
var
  src, body: string;
  a, b: Integer;
begin
  src := NewItemsSource;
  a := Pos('constructor TTyFrameFileDescriptor.Create;', src);
  AssertTrue('the frame template has a constructor', a > 0);
  b := Pos('end;', Copy(src, a, MaxInt));
  body := Squeezed(Copy(src, a, b));
  AssertTrue('its class descends from TTyFrame', Pos('ResourceClass:=TTyFrame;', body) > 0);
  AssertTrue('a frame is not auto-created', Pos('UseCreateFormStatements:=False;', body) > 0);
  AssertTrue('nor given a global variable', Pos('DeclareClassVariable:=False;', body) > 0);
  AssertTrue('the project gets the runtime package',
    Pos('RequiredPackages:=''tycontrols'';', body) > 0);
  AssertTrue('the unit uses tyControls.Frame', Pos('tyControls.Frame', src) > 0);
  AssertTrue('and the template is registered with the IDE',
    Pos('RegisterProjectFileDescriptor(TTyFrameFileDescriptor.Create)', Squeezed(src)) > 0);
end;

procedure TTyFrameDesignTest.TestTheTemplateTextsAreTranslated;
var
  sl: TStringList;
  po: string;

  function Translated(const AId: string): Boolean;
  var
    i: Integer;
  begin
    Result := False;
    for i := 0 to sl.Count - 3 do
      if Trim(sl[i]) = '#: ' + AId then
        Exit((Copy(sl[i + 2], 1, 8) = 'msgstr "') and (Length(Trim(sl[i + 2])) > 9));
  end;

begin
  sl := TStringList.Create;
  try
    po := RepoRoot + 'languages' + PathDelim + 'tycontrols.design.newitems.zh_CN.po';
    sl.LoadFromFile(po);
    AssertTrue('the dialog''s name is translated (the parse works)',
      Translated('tycontrols.design.newitems.rsdtdialogname'));
    AssertTrue('the frame template''s name has a zh_CN text',
      Translated('tycontrols.design.newitems.rsdtframename'));
    AssertTrue('and its description',
      Translated('tycontrols.design.newitems.rsdtframedescription'));
    sl.LoadFromFile(RepoRoot + 'languages' + PathDelim + 'tyControls.Design.NewItems.pot');
    AssertTrue('the template lists the name',
      sl.IndexOf('#: tycontrols.design.newitems.rsdtframename') >= 0);
    AssertTrue('and the description',
      sl.IndexOf('#: tycontrols.design.newitems.rsdtframedescription') >= 0);
  finally
    sl.Free;
  end;
end;

initialization
  RegisterInitComponentHandler(TFrameAccess, @NoFormFile);
  RegisterTest(TTyFrameTest);
  RegisterTest(TTyFrameDesignTest);

end.
