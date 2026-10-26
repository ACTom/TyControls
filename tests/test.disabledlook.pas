unit test.disabledlook;
{ #118: a disabled control looks disabled -- a container's caption greys, a self-drawn surface
  dims, a tree's nodes take their :disabled rule, a skin that dresses the labels keeps their
  disabled look -- and so does everything inside a disabled container, as LCL's TLabel and
  TSpeedButton grey through IsEnabled. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Controls, Graphics, Forms, fpcunit, testregistry, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.Panel, tyControls.Edit,
  tyControls.TyLabel, tyControls.TreeView, tyControls.Gauge, tyControls.Button, test.dpi.support;

type
  TDisabledLookTest = class(TTestCase)
  private
    FForm: TForm;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestADisabledPanelsCaptionGreys;
    procedure TestTheChildrenOfADisabledPanelLookDisabled;
    procedure TestDisablingAPanelRepaintsItsWindowedChildren;
    procedure TestADisabledTreesNodesGrey;
    procedure TestADisabledGaugeArcDims;
    procedure TestASkinThatDressesLabelsStillGreysThem;
    procedure TestAPressedButtonInADisabledPanelLooksDisabled;
  end;

implementation

type
  TPanelAcc = class(TTyPanel);
  TTreeAcc = class(TTyTreeView);
  TEditAcc = class(TTyEdit)
  public
    Invalidations: Integer;
    function Style: TTyStyleSet;
    procedure Invalidate; override;
  end;
  TLabelAcc = class(TTyLabel)
  public
    function Style: TTyStyleSet;
  end;
  TButtonAcc = class(TTyButton)
  public
    function States: TTyStateSet;
  end;

function TButtonAcc.States: TTyStateSet;
begin
  Result := CurrentStates;
end;

function TEditAcc.Style: TTyStyleSet;
begin
  Result := CurrentStyle;
end;

procedure TEditAcc.Invalidate;
begin
  Inc(Invalidations);
  inherited Invalidate;
end;

function TLabelAcc.Style: TTyStyleSet;
begin
  Result := CurrentStyle;
end;

{ The darkest pixel in R: 0 is black ink, 255 none at all. }
function Darkest(B: TBGRABitmap; const R: TRect): Integer;
var
  x, y, v: Integer;
  px: TBGRAPixel;
begin
  Result := 255;
  for y := R.Top to R.Bottom - 1 do
    for x := R.Left to R.Right - 1 do
    begin
      px := B.GetPixel(x, y);
      v := (px.red + px.green + px.blue) div 3;
      if v < Result then Result := v;
    end;
end;

function Snap(AControl: TControl; W, H: Integer): TBGRABitmap;
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(W, H);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, W, H);
    if AControl is TTyPanel then TPanelAcc(AControl).RenderTo(bmp.Canvas, Rect(0, 0, W, H), 96)
    else if AControl is TTyTreeView then TTreeAcc(AControl).RenderTo(bmp.Canvas, Rect(0, 0, W, H), 96)
    else
    begin
      AControl.SetBounds(0, 0, W, H);
      TyTestPaintTree(AControl, bmp, nil);
    end;
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
  end;
end;

procedure TDisabledLookTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
end;

procedure TDisabledLookTest.TearDown;
begin
  FreeAndNil(FForm);
end;

procedure TDisabledLookTest.TestADisabledPanelsCaptionGreys;
var
  p: TTyPanel;
  b: TBGRABitmap;
  live, off: Integer;
begin
  p := TTyPanel.Create(nil);
  try
    p.SetBounds(0, 0, 200, 50);
    p.Caption := 'MMMM WWWW';
    b := Snap(p, 200, 50);
    try live := Darkest(b, Rect(10, 10, 190, 40)); finally b.Free; end;
    p.Enabled := False;
    b := Snap(p, 200, 50);
    try off := Darkest(b, Rect(10, 10, 190, 40)); finally b.Free; end;
    AssertTrue(Format('the caption greys (darkest %d -> %d)', [live, off]), off > live + 30);
  finally
    p.Free;
  end;
end;

procedure TDisabledLookTest.TestTheChildrenOfADisabledPanelLookDisabled;
var
  p: TTyPanel;
  e: TEditAcc;
  l: TLabelAcc;
begin
  p := TTyPanel.Create(FForm);
  p.Parent := FForm;
  e := TEditAcc.Create(FForm);
  e.Parent := p;
  l := TLabelAcc.Create(FForm);
  l.Parent := p;
  AssertFalse('precondition: an enabled edit is not dimmed', tpOpacity in e.Style.Present);
  p.Enabled := False;
  AssertTrue('the edit is still Enabled itself', e.Enabled);
  AssertTrue('but dims with its panel', tpOpacity in e.Style.Present);
  AssertTrue('and so does a label', tpOpacity in l.Style.Present);
end;

procedure TDisabledLookTest.TestDisablingAPanelRepaintsItsWindowedChildren;
var
  p: TTyPanel;
  e: TEditAcc;
begin
  p := TTyPanel.Create(FForm);
  p.Parent := FForm;
  e := TEditAcc.Create(FForm);
  e.Parent := p;
  e.Invalidations := 0;
  p.Enabled := False;
  AssertTrue('the edit repaints: its look changed with its parent', e.Invalidations > 0);
end;

procedure TDisabledLookTest.TestADisabledTreesNodesGrey;
var
  t: TTyTreeView;
  b: TBGRABitmap;
  live, off: Integer;
begin
  t := TTyTreeView.Create(nil);
  try
    t.SetBounds(0, 0, 200, 60);
    t.Items.Add(nil, 'MMMM WWWW');
    b := Snap(t, 200, 60);
    try live := Darkest(b, Rect(20, 2, 190, 26)); finally b.Free; end;
    t.Enabled := False;
    b := Snap(t, 200, 60);
    try off := Darkest(b, Rect(20, 2, 190, 26)); finally b.Free; end;
    AssertTrue(Format('the node greys (darkest %d -> %d)', [live, off]), off > live + 30);
  finally
    t.Free;
  end;
end;

procedure TDisabledLookTest.TestADisabledGaugeArcDims;
var
  g: TTyGauge;
  b: TBGRABitmap;
  live, off: Integer;
begin
  g := TTyGauge.Create(FForm);
  g.Parent := FForm;
  g.Value := 70;
  b := Snap(g, 120, 120);
  try live := Darkest(b, Rect(0, 0, 120, 120)); finally b.Free; end;
  g.Enabled := False;
  b := Snap(g, 120, 120);
  try off := Darkest(b, Rect(0, 0, 120, 120)); finally b.Free; end;
  AssertTrue(Format('the arc dims (darkest %d -> %d)', [live, off]), off > live + 20);
end;

procedure TDisabledLookTest.TestASkinThatDressesLabelsStillGreysThem;
var
  ctl: TTyStyleController;
  l: TLabelAcc;
begin
  ctl := TTyStyleController.Create(nil);
  try
    ctl.ThemeName := 'adwaita';
    l := TLabelAcc.Create(FForm);
    l.Controller := ctl;
    l.Parent := FForm;
    l.Enabled := False;
    AssertTrue('a disabled label dims under a skin that dresses labels', tpOpacity in l.Style.Present);
  finally
    FreeAndNil(FForm);   // the label goes before its controller
    ctl.Free;
  end;
end;

procedure TDisabledLookTest.TestAPressedButtonInADisabledPanelLooksDisabled;
var
  p: TTyPanel;
  b: TButtonAcc;
begin
  p := TTyPanel.Create(FForm);
  p.Parent := FForm;
  b := TButtonAcc.Create(FForm);
  b.Parent := p;
  b.Down := True;
  p.Enabled := False;
  AssertTrue('disabled with its panel', tysDisabled in b.States);
  AssertFalse('and not drawn pressed on top of it', tysSelected in b.States);
end;

initialization
  RegisterTest(TDisabledLookTest);
end.
