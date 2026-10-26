unit test.miscprops;
{ #128: a status bar with no panels shows SimpleText, and the application hint goes there; a
  cool band's Width and Visible, set before it had a control, go over to the control; a list
  group panel's HeaderHeight / ItemHeight win over the theme's token once set; and an image
  view's ZoomMin / ZoomMax re-clamp the zoom, ZoomToActual included. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Types, Controls, Graphics, fpcunit, testregistry, BGRABitmap,
  tyControls.Controller, tyControls.StatusBar, tyControls.CoolBar, tyControls.Button,
  tyControls.ListGroupPanel, tyControls.ImageView;

type
  TBarProbe = class(TTyStatusBar)
  public
    function Shows: Boolean;   // anything drawn past the empty bar
    function Hint(const S: string): Boolean;
  end;

  TGroupProbe = class(TTyListGroupPanel)
  public
    procedure Click(X, Y: Integer);
  end;

  TMiscPropsTest = class(TTestCase)
  published
    procedure TestAStatusBarWithNoPanelsShowsSimpleText;
    procedure TestTheHintGoesToSimpleTextWithNoPanels;
    procedure TestACoolBandHandsItsWidthAndVisibleToItsControl;
    procedure TestItemHeightWinsOverTheThemeOnceSet;
    procedure TestZoomMaxReclampsTheZoom;
    procedure TestZoomToActualStaysInsideTheLimits;
  end;

implementation

function TBarProbe.Shows: Boolean;
var
  a, b: TBitmap;
  x, y: Integer;
  keep: string;
begin
  Result := False;
  a := TBitmap.Create;
  b := TBitmap.Create;
  try
    a.PixelFormat := pf32bit; a.SetSize(200, 24);
    b.PixelFormat := pf32bit; b.SetSize(200, 24);
    RenderTo(a.Canvas, Rect(0, 0, 200, 24), 96);
    keep := SimpleText;
    SimpleText := '';
    RenderTo(b.Canvas, Rect(0, 0, 200, 24), 96);
    SimpleText := keep;
    for y := 0 to 23 do
      for x := 0 to 199 do
        if a.Canvas.Pixels[x, y] <> b.Canvas.Pixels[x, y] then Exit(True);
  finally
    a.Free;
    b.Free;
  end;
end;

function TBarProbe.Hint(const S: string): Boolean;
begin
  Result := DoSetApplicationHint(S);
end;

procedure TGroupProbe.Click(X, Y: Integer);
begin
  MouseDown(mbLeft, [ssLeft], X, Y);
  MouseUp(mbLeft, [], X, Y);
end;

procedure TMiscPropsTest.TestAStatusBarWithNoPanelsShowsSimpleText;
var
  s: TBarProbe;
begin
  s := TBarProbe.Create(nil);
  try
    s.SimpleText := 'Ready';
    AssertTrue('the text is drawn', s.Shows);
  finally
    s.Free;
  end;
end;

procedure TMiscPropsTest.TestTheHintGoesToSimpleTextWithNoPanels;
var
  s: TBarProbe;
begin
  s := TBarProbe.Create(nil);
  try
    s.Hint('Saves the file');
    AssertEquals('where the bar shows it', 'Saves the file', s.SimpleText);
  finally
    s.Free;
  end;
end;

procedure TMiscPropsTest.TestACoolBandHandsItsWidthAndVisibleToItsControl;
var
  bar: TTyCoolBar;
  band: TTyCoolBand;
  btn: TTyButton;
begin
  bar := TTyCoolBar.Create(nil);
  try
    bar.Font.PixelsPerInch := 96;
    btn := TTyButton.Create(bar);
    band := bar.Bands.Add as TTyCoolBand;
    band.Width := 150;
    band.Visible := False;
    band.Control := btn;
    AssertEquals('the width', 150, btn.Width);
    AssertFalse('and Visible', btn.Visible);
  finally
    bar.Free;
  end;
end;

procedure TMiscPropsTest.TestItemHeightWinsOverTheThemeOnceSet;
var
  ctl: TTyStyleController;
  g: TGroupProbe;
begin
  ctl := TTyStyleController.Create(nil);
  g := TGroupProbe.Create(nil);
  try
    ctl.LoadThemeCss(':root { --listgroup-header-height: 26px; --listgroup-item-height: 40px; }');
    g.Controller := ctl;
    g.Font.PixelsPerInch := 96;
    g.SetBounds(0, 0, 200, 300);
    g.AddGroup('G');
    g.AddItem(0, 'a');
    g.AddItem(0, 'b');
    g.ToggleGroup(0);   // groups start closed
    g.ItemHeight := 30;
    g.Click(20, 26 + 30 + 5);   // inside the second row, if rows are 30 tall
    AssertEquals('the rows are as tall as ItemHeight, not the token', 1, g.SelectedItem);
  finally
    g.Free;
    ctl.Free;
  end;
end;

procedure TMiscPropsTest.TestZoomMaxReclampsTheZoom;
var
  v: TTyImageView;
  bmp: TBGRABitmap;
begin
  v := TTyImageView.Create(nil);
  bmp := TBGRABitmap.Create(100, 100);
  try
    v.SetBounds(0, 0, 200, 200);
    v.AutoFit := False;
    v.AssignBitmap(bmp);
    v.ZoomToActual;
    AssertEquals('setup: 100%', 1.0, v.Zoom, 1e-9);
    v.ZoomMax := 0.5;
    AssertEquals('the zoom comes back inside', 0.5, v.Zoom, 1e-9);
  finally
    bmp.Free;
    v.Free;
  end;
end;

procedure TMiscPropsTest.TestZoomToActualStaysInsideTheLimits;
var
  v: TTyImageView;
  bmp: TBGRABitmap;
begin
  v := TTyImageView.Create(nil);
  bmp := TBGRABitmap.Create(100, 100);
  try
    v.SetBounds(0, 0, 200, 200);
    v.AutoFit := False;
    v.AssignBitmap(bmp);
    v.ZoomMin := 2;
    AssertEquals('the zoom comes up to the new floor', 2.0, v.Zoom, 1e-9);
    v.ZoomToActual;
    AssertEquals('as near 100% as the limits allow', 2.0, v.Zoom, 1e-9);
  finally
    bmp.Free;
    v.Free;
  end;
end;

initialization
  RegisterTest(TMiscPropsTest);
end.
