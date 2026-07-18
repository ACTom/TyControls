unit test.expanel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType,
  fpcunit, testregistry,
  tyControls.Controller, tyControls.Base,
  tyControls.Panel, tyControls.ExPanel;
type
  TTyExPanelTest = class(TTestCase)
  private
    FForm: TForm;
    FPanel: TTyExPanel;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // typeKey / defaults
    procedure TestTypeKeyIsTyPanel;
    procedure TestDefaults;
    procedure TestIsContainer;
    // pure geometry
    procedure TestHeaderRectSpansTop;
    procedure TestHeaderRectClampsToClient;
    procedure TestChevronPointsDownWhenExpanded;
    procedure TestChevronPointsRightWhenCollapsed;
    procedure TestHeightAtEndpoints;
    procedure TestHeightAtMidpoint;
    // collapse / expand behaviour (headless snaps)
    procedure TestCollapseSnapsHeightToHeader;
    procedure TestExpandRestoresExpandedHeight;
    procedure TestCollapseRemembersCurrentHeight;
    procedure TestSetCollapsedSameValueNoOp;
    procedure TestZeroDurationSnaps;
    // events
    procedure TestOnCollapseFires;
    procedure TestOnExpandFires;
    procedure TestEventsFireOnlyOnChange;
    // client rect / header hit-test
    procedure TestAdjustClientRectInsetsBelowHeader;
    procedure TestBodyClearsTheBorder;
    procedure TestHeaderClickToggles;
    procedure TestBodyClickDoesNotToggle;
    procedure TestDisabledHeaderClickIgnored;
    // scaling
    procedure TestHeaderHeightScalesWithDPI;
  end;

implementation

type
  TExPanelAccess = class(TTyExPanel)
  public
    function StyleTypeKey: string;
    procedure ClickAt(X, Y: Integer);
    function ClientTopInset: Integer;
    function AdjustedClient: TRect;
  end;

  TEventProbe = class
  public
    ExpandCount, CollapseCount: Integer;
    procedure OnExpand(Sender: TObject);
    procedure OnCollapse(Sender: TObject);
  end;

function TExPanelAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TExPanelAccess.ClickAt(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
end;

function TExPanelAccess.AdjustedClient: TRect;
begin
  Result := Rect(0, 0, Width, Height);
  AdjustClientRect(Result);
end;

function TExPanelAccess.ClientTopInset: Integer;
var
  r: TRect;
begin
  r := Rect(0, 0, Width, Height);
  AdjustClientRect(r);
  Result := r.Top;
end;

procedure TEventProbe.OnExpand(Sender: TObject);
begin
  Inc(ExpandCount);
end;

procedure TEventProbe.OnCollapse(Sender: TObject);
begin
  Inc(CollapseCount);
end;

{ TTyExPanelTest }

procedure TTyExPanelTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FPanel := TTyExPanel.Create(FForm);
  FPanel.Parent := FForm;
  // Pin PPI (macOS defaults to 72) so header-height scaling is 1:1 in the tests.
  FPanel.Font.PixelsPerInch := 96;
end;

procedure TTyExPanelTest.TearDown;
begin
  FForm.Free;
end;

procedure TTyExPanelTest.TestTypeKeyIsTyPanel;
var
  Acc: TExPanelAccess;
begin
  Acc := TExPanelAccess.Create(FForm);
  Acc.Parent := FForm;
  try
    // Reuses the base TyPanel typeKey — no new .tycss.
    AssertEquals('TyPanel', Acc.StyleTypeKey);
  finally
    Acc.Free;
  end;
end;

procedure TTyExPanelTest.TestDefaults;
begin
  AssertFalse('not collapsed by default', FPanel.Collapsed);
  AssertEquals('default header height', TyExPanelDefaultHeaderHeight, FPanel.HeaderHeight);
  AssertTrue('ExpandedHeight seeded from initial Height', FPanel.ExpandedHeight > 0);
end;

procedure TTyExPanelTest.TestIsContainer;
begin
  // Real container: accepts dropped child controls (inherited from TTyPanel).
  AssertTrue('csAcceptsControls', csAcceptsControls in FPanel.ControlStyle);
end;

procedure TTyExPanelTest.TestHeaderRectSpansTop;
var
  hdr: TRect;
begin
  hdr := TyExPanelHeaderRect(Rect(0, 0, 200, 140), 26);
  AssertEquals('header left', 0, hdr.Left);
  AssertEquals('header top', 0, hdr.Top);
  AssertEquals('header right = full width', 200, hdr.Right);
  AssertEquals('header bottom = header height', 26, hdr.Bottom);
end;

procedure TTyExPanelTest.TestHeaderRectClampsToClient;
var
  hdr: TRect;
begin
  // A header taller than the client clamps to the client height.
  hdr := TyExPanelHeaderRect(Rect(0, 0, 200, 20), 26);
  AssertEquals('header clamps to client height', 20, hdr.Bottom);
end;

procedure TTyExPanelTest.TestChevronPointsDownWhenExpanded;
var
  hdr: TRect;
  tri: TTyTriangle;
  apexY, baseY: Integer;
begin
  hdr := TyExPanelHeaderRect(Rect(0, 0, 200, 26), 26);
  tri := TyExPanelChevronPoints(hdr, True);   // expanded -> down
  // Two points share the (higher) base Y; the third (apex) is BELOW them.
  baseY := tri[0].Y;
  AssertEquals('two base points share Y', baseY, tri[1].Y);
  apexY := tri[2].Y;
  AssertTrue('apex is below the base (points down)', apexY > baseY);
end;

procedure TTyExPanelTest.TestChevronPointsRightWhenCollapsed;
var
  hdr: TRect;
  tri: TTyTriangle;
  baseX, apexX: Integer;
begin
  hdr := TyExPanelHeaderRect(Rect(0, 0, 200, 26), 26);
  tri := TyExPanelChevronPoints(hdr, False);   // collapsed -> right
  // Two points share the (left) base X; the apex is to the RIGHT of them.
  baseX := tri[0].X;
  AssertEquals('two base points share X', baseX, tri[1].X);
  apexX := tri[2].X;
  AssertTrue('apex is right of the base (points right)', apexX > baseX);
end;

procedure TTyExPanelTest.TestHeightAtEndpoints;
begin
  AssertEquals('t=0 -> collapsed height', 26, TyExPanelHeightAt(26, 140, 0.0));
  AssertEquals('t=1 -> expanded height', 140, TyExPanelHeightAt(26, 140, 1.0));
end;

procedure TTyExPanelTest.TestHeightAtMidpoint;
begin
  // Linear in t (caller passes an eased t): halfway = 26 + (140-26)/2 = 83.
  AssertEquals('t=0.5 -> midpoint', 83, TyExPanelHeightAt(26, 140, 0.5));
end;

procedure TTyExPanelTest.TestCollapseSnapsHeightToHeader;
begin
  FPanel.SetBounds(0, 0, 200, 140);
  FPanel.HeaderHeight := 30;
  FPanel.Collapsed := True;
  // Headless (no handle) -> Height snaps to the scaled header height immediately.
  AssertEquals('collapsed Height == header height', 30, FPanel.Height);
end;

procedure TTyExPanelTest.TestExpandRestoresExpandedHeight;
begin
  FPanel.SetBounds(0, 0, 200, 150);
  FPanel.HeaderHeight := 26;
  FPanel.Collapsed := True;
  AssertEquals('collapsed to header', 26, FPanel.Height);
  FPanel.Collapsed := False;
  AssertEquals('expanded restores the remembered full height', 150, FPanel.Height);
end;

procedure TTyExPanelTest.TestCollapseRemembersCurrentHeight;
begin
  // The height at collapse time is what expand restores (not the create-time size).
  FPanel.SetBounds(0, 0, 200, 200);
  FPanel.Collapsed := True;
  AssertEquals('ExpandedHeight captured at collapse', 200, FPanel.ExpandedHeight);
  FPanel.Collapsed := False;
  AssertEquals('restores 200', 200, FPanel.Height);
end;

procedure TTyExPanelTest.TestSetCollapsedSameValueNoOp;
var
  Probe: TEventProbe;
begin
  FPanel.SetBounds(0, 0, 200, 140);
  Probe := TEventProbe.Create;
  try
    FPanel.OnCollapse := @Probe.OnCollapse;
    FPanel.OnExpand := @Probe.OnExpand;
    FPanel.Collapsed := False;   // already False -> no-op
    AssertEquals('no collapse event on no-op', 0, Probe.CollapseCount);
    AssertEquals('no expand event on no-op', 0, Probe.ExpandCount);
  finally
    Probe.Free;
  end;
end;

procedure TTyExPanelTest.TestZeroDurationSnaps;
begin
  FPanel.SetBounds(0, 0, 200, 140);
  FPanel.AnimationDuration := 0;
  FPanel.Collapsed := True;
  AssertEquals('zero-duration collapse snaps', FPanel.HeaderHeight, FPanel.Height);
end;

procedure TTyExPanelTest.TestOnCollapseFires;
var
  Probe: TEventProbe;
begin
  FPanel.SetBounds(0, 0, 200, 140);
  Probe := TEventProbe.Create;
  try
    FPanel.OnCollapse := @Probe.OnCollapse;
    FPanel.Collapsed := True;
    AssertEquals('OnCollapse fired once', 1, Probe.CollapseCount);
  finally
    Probe.Free;
  end;
end;

procedure TTyExPanelTest.TestOnExpandFires;
var
  Probe: TEventProbe;
begin
  FPanel.SetBounds(0, 0, 200, 140);
  FPanel.Collapsed := True;
  Probe := TEventProbe.Create;
  try
    FPanel.OnExpand := @Probe.OnExpand;
    FPanel.Collapsed := False;
    AssertEquals('OnExpand fired once', 1, Probe.ExpandCount);
  finally
    Probe.Free;
  end;
end;

procedure TTyExPanelTest.TestEventsFireOnlyOnChange;
var
  Probe: TEventProbe;
begin
  FPanel.SetBounds(0, 0, 200, 140);
  Probe := TEventProbe.Create;
  try
    FPanel.OnCollapse := @Probe.OnCollapse;
    FPanel.OnExpand := @Probe.OnExpand;
    FPanel.Collapsed := True;
    FPanel.Collapsed := True;    // no-op
    FPanel.Collapsed := False;
    FPanel.Collapsed := False;   // no-op
    AssertEquals('collapse fired exactly once', 1, Probe.CollapseCount);
    AssertEquals('expand fired exactly once', 1, Probe.ExpandCount);
  finally
    Probe.Free;
  end;
end;

procedure TTyExPanelTest.TestAdjustClientRectInsetsBelowHeader;
var
  Acc: TExPanelAccess;
begin
  Acc := TExPanelAccess.Create(FForm);
  Acc.Parent := FForm;
  Acc.Font.PixelsPerInch := 96;
  try
    Acc.SetBounds(0, 0, 200, 140);
    Acc.HeaderHeight := 26;
    // The body's top begins one header height below the client top.
    AssertEquals('client top inset by header height', 26, Acc.ClientTopInset);
  finally
    Acc.Free;
  end;
end;

procedure TTyExPanelTest.TestHeaderClickToggles;
var
  Acc: TExPanelAccess;
begin
  Acc := TExPanelAccess.Create(FForm);
  Acc.Parent := FForm;
  Acc.Font.PixelsPerInch := 96;
  try
    Acc.SetBounds(0, 0, 200, 140);
    Acc.HeaderHeight := 26;
    AssertFalse('starts expanded', Acc.Collapsed);
    Acc.ClickAt(20, 13);   // inside the header band
    AssertTrue('header click collapses', Acc.Collapsed);
    Acc.ClickAt(20, 13);   // header band is still the top 26px of the (now short) control
    AssertFalse('second header click expands', Acc.Collapsed);
  finally
    Acc.Free;
  end;
end;

procedure TTyExPanelTest.TestBodyClickDoesNotToggle;
var
  Acc: TExPanelAccess;
begin
  Acc := TExPanelAccess.Create(FForm);
  Acc.Parent := FForm;
  Acc.Font.PixelsPerInch := 96;
  try
    Acc.SetBounds(0, 0, 200, 140);
    Acc.HeaderHeight := 26;
    Acc.ClickAt(20, 80);   // well below the header, in the body
    AssertFalse('body click does not toggle', Acc.Collapsed);
  finally
    Acc.Free;
  end;
end;

procedure TTyExPanelTest.TestDisabledHeaderClickIgnored;
var
  Acc: TExPanelAccess;
begin
  Acc := TExPanelAccess.Create(FForm);
  Acc.Parent := FForm;
  Acc.Font.PixelsPerInch := 96;
  try
    Acc.SetBounds(0, 0, 200, 140);
    Acc.HeaderHeight := 26;
    Acc.Enabled := False;
    Acc.ClickAt(20, 13);
    AssertFalse('disabled header click ignored', Acc.Collapsed);
  finally
    Acc.Free;
  end;
end;

procedure TTyExPanelTest.TestHeaderHeightScalesWithDPI;
var
  Acc: TExPanelAccess;
begin
  Acc := TExPanelAccess.Create(FForm);
  Acc.Parent := FForm;
  try
    Acc.SetBounds(0, 0, 200, 300);
    Acc.HeaderHeight := 26;
    // At 192 ppi the client inset is MulDiv(26, 192, 96) = 52.
    Acc.Font.PixelsPerInch := 192;
    AssertEquals('header inset scales with DPI', 52, Acc.ClientTopInset);
  finally
    Acc.Free;
  end;
end;

{ The body must not sit ON the panel's own border: DrawFrame strokes the border INSIDE the
  control's rect, so an un-inset alClient child starts at x=0, paints over the border line, and
  reads as content spilling out of the panel. (Reported from a real run: "折叠面板,内容区超出
  了边界".) The header band already covers the top edge, so only the other three are checked. }
procedure TTyExPanelTest.TestBodyClearsTheBorder;
var
  Ctl: TTyStyleController;
  Acc: TExPanelAccess;
  r: TRect;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    // A 3px border, so an off-by-one cannot pass by accident.
    Ctl.LoadThemeCss('TyPanel { background: #FFFFFF; color: #111111; '
      + 'border-color: #808080; border-width: 3px; }');
    Acc := TExPanelAccess.Create(FForm);
    Acc.Parent := FForm;
    Acc.Controller := Ctl;
    Acc.Font.PixelsPerInch := 96;
    try
      Acc.SetBounds(0, 0, 200, 140);
      Acc.HeaderHeight := 26;
      r := Acc.AdjustedClient;
      AssertEquals('left clears the border', 3, r.Left);
      AssertEquals('right clears the border', 200 - 3, r.Right);
      AssertEquals('bottom clears the border', 140 - 3, r.Bottom);
      AssertEquals('top is still the header band (which covers the top border)', 26, r.Top);
    finally
      Acc.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TTyExPanelTest);
end.
