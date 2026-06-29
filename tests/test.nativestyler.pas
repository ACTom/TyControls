unit test.nativestyler;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Graphics, Controls, StdCtrls, ExtCtrls, Forms, ComCtrls, fpcunit, testregistry,
  tyControls.Controller, tyControls.NativeStyler;
type
  TNativeStylerTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FStyler: TTyNativeStyler;
    FSkipName: string;
    procedure SkipByName(Sender: TObject; AControl: TControl; var AHandled: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEditGetsBackgroundAndFont;
    procedure TestButtonGetsFontButNotBackground;
    procedure TestOnStyleControlCanSkip;
    procedure TestRegisterDenyBlocksBackground;
    procedure TestUnmappedFallsBackToPanel;
    procedure TestTreeViewGetsThemed;
  end;

implementation

const
  // distinct colours per token so assertions are unambiguous
  CSS =
    'TyEdit  { background: #112233; color: #445566; }' + LineEnding +
    'TyButton{ background: #102030; color: #405060; }' + LineEnding +
    'TyPanel { background: #778899; color: #AABBCC; }' + LineEnding;

procedure TNativeStylerTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(CSS);
  FStyler := TTyNativeStyler.Create(nil);
  FStyler.Controller := FCtl;
end;

procedure TNativeStylerTest.TearDown;
begin
  FStyler.Free;
  FCtl.Free;
end;

procedure TNativeStylerTest.SkipByName(Sender: TObject; AControl: TControl; var AHandled: Boolean);
begin
  if AControl.Name = FSkipName then AHandled := True;
end;

procedure TNativeStylerTest.TestEditGetsBackgroundAndFont;
var e: TEdit;
begin
  e := TEdit.Create(nil);
  try
    FStyler.StyleControl(e);
    AssertEquals('edit background = TyEdit bg', Integer(RGBToColor($11, $22, $33)), Integer(e.Color));
    AssertEquals('edit font = TyEdit color', Integer(RGBToColor($44, $55, $66)), Integer(e.Font.Color));
    AssertFalse('ParentColor cleared', e.ParentColor);
    AssertFalse('ParentFont cleared', e.ParentFont);
  finally
    e.Free;
  end;
end;

procedure TNativeStylerTest.TestButtonGetsFontButNotBackground;
var b: TButton;
begin
  b := TButton.Create(nil);
  try
    b.Color := clBtnFace;                       // a sentinel we expect to remain
    FStyler.StyleControl(b);
    AssertEquals('button font = TyButton color', Integer(RGBToColor($40, $50, $60)), Integer(b.Font.Color));
    AssertEquals('button background untouched (OS-drawn -> denied)', Integer(clBtnFace), Integer(b.Color));
  finally
    b.Free;
  end;
end;

procedure TNativeStylerTest.TestOnStyleControlCanSkip;
var e: TEdit;
begin
  e := TEdit.Create(nil);
  try
    e.Name := 'SkipMe';
    e.Color := clWindow;                        // sentinel
    FSkipName := 'SkipMe';
    FStyler.OnStyleControl := @SkipByName;
    FStyler.StyleControl(e);
    AssertEquals('opted-out control untouched', Integer(clWindow), Integer(e.Color));
  finally
    e.Free;
  end;
end;

procedure TNativeStylerTest.TestRegisterDenyBlocksBackground;
var p: TPanel;
begin
  // TPanel maps to TyPanel and is NOT denied by default -> it normally gets a bg. Deny its class.
  TTyNativeStyler.RegisterDeny(TPanel);
  p := TPanel.Create(nil);
  try
    p.Color := clBtnFace;                       // sentinel
    FStyler.StyleControl(p);
    AssertEquals('font still applied', Integer(RGBToColor($AA, $BB, $CC)), Integer(p.Font.Color));
    AssertEquals('background blocked by RegisterDeny', Integer(clBtnFace), Integer(p.Color));
  finally
    p.Free;
  end;
end;

procedure TNativeStylerTest.TestUnmappedFallsBackToPanel;
var sb: TScrollBox;   // no Ty analog in the map -> TyPanel
begin
  sb := TScrollBox.Create(nil);
  try
    FStyler.StyleControl(sb);
    AssertEquals('unmapped control borrows TyPanel bg', Integer(RGBToColor($77, $88, $99)), Integer(sb.Color));
  finally
    sb.Free;
  end;
end;

procedure TNativeStylerTest.TestTreeViewGetsThemed;
var tv: TTreeView;
begin
  tv := TTreeView.Create(nil);
  try
    FStyler.StyleControl(tv);
    AssertEquals('treeview bg = TyPanel bg (unmapped)', Integer(RGBToColor($77, $88, $99)), Integer(tv.Color));
    AssertEquals('treeview font = TyPanel color', Integer(RGBToColor($AA, $BB, $CC)), Integer(tv.Font.Color));
    AssertFalse('tvoThemedDraw cleared so Font.Color drives node text (not OS-themed black)',
      tvoThemedDraw in tv.Options);
  finally
    tv.Free;
  end;
end;

initialization
  RegisterTest(TNativeStylerTest);
end.
