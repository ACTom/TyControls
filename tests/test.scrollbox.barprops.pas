unit test.scrollbox.barprops;
{$mode objfpc}{$H+}

{ #240: HorzScrollBar.Visible and VertScrollBar.Visible on a scroll box, as the LCL names them.

  They are a view of the token --scrollbox-bars (#239) in the box's own StyleOverride: reading
  one reads what the box may show, writing one rewrites the token, nothing else is stored. A
  form saved from an LCL TScrollBox may carry the other properties of TControlScrollBar
  (Increment, Page, Position, Range, Smooth, Tracking); they are read and let go, so such a
  form loads as it is. }

interface

uses
  Classes, SysUtils, Types, TypInfo, Graphics, Forms, Controls, LCLType, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.Panel,
  tyControls.ScrollBar, tyControls.ScrollBox, tyControls.ScrollPanel, test.scrollbox.bars;

type
  TScrollBoxBarPropsTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FBox: TBarsBox;
    FChild: TControl;
    function LoadForm(const ABody: string): TForm;
    function FormText(AForm: TComponent): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure BothBarsAreVisibleUntilSaidOtherwise;
    procedure VisibleReadsTheToken;
    procedure VisibleReadsTheThemesTokenToo;
    procedure HidingABarWritesTheToken;
    procedure AHiddenBarIsLeftOutAtOnce;
    procedure TheRestOfTheOverrideIsKept;
    procedure SettingVisibleToWhatItShowsChangesNothing;
    procedure ABarTheThemeHidesCanBeShownHere;
    procedure TheSubObjectsArePublishedAndStoreNothing;
    procedure AFormSavedByThisVersionStoresTheOverrideOnly;
    procedure AFormFromAnLclScrollBoxLoads;
    procedure AssigningCopiesVisible;
    procedure AScrollPanelHasThemToo;
  end;

implementation

procedure TScrollBoxBarPropsTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(-4000, -4000, 600, 400);
  FBox := TBarsBox.Create(FForm);
  FBox.Parent := FForm;
  FBox.Controller := FCtl;
  FBox.Font.PixelsPerInch := 96;
  FBox.SetBounds(0, 0, 300, 200);
  FChild := TTyPanel.Create(FBox);
  FChild.Parent := FBox;
  FChild.SetBounds(0, 0, 900, 700);   // overflows both ways
  FBox.UpdateScrollRange;
end;

procedure TScrollBoxBarPropsTest.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

function TScrollBoxBarPropsTest.LoadForm(const ABody: string): TForm;
var
  txt: TStringStream;
  bin: TMemoryStream;
begin
  Result := TForm.CreateNew(nil);
  txt := TStringStream.Create('object F: TForm'#10 + ABody + 'end'#10);
  bin := TMemoryStream.Create;
  try
    ObjectTextToBinary(txt, bin);
    bin.Position := 0;
    bin.ReadComponent(Result);
  finally
    bin.Free;
    txt.Free;
  end;
end;

function TScrollBoxBarPropsTest.FormText(AForm: TComponent): string;
var
  bin: TMemoryStream;
  txt: TStringStream;
begin
  bin := TMemoryStream.Create;
  txt := TStringStream.Create('');
  try
    bin.WriteComponent(AForm);
    bin.Position := 0;
    ObjectBinaryToText(bin, txt);
    Result := txt.DataString;
  finally
    txt.Free;
    bin.Free;
  end;
end;

procedure TScrollBoxBarPropsTest.BothBarsAreVisibleUntilSaidOtherwise;
begin
  AssertTrue('HorzScrollBar', FBox.HorzScrollBar.Visible);
  AssertTrue('VertScrollBar', FBox.VertScrollBar.Visible);
  AssertEquals('and nothing was written to say so', '', FBox.StyleOverride);
end;

procedure TScrollBoxBarPropsTest.VisibleReadsTheToken;
begin
  FBox.StyleOverride := '--scrollbox-bars: vertical;';
  AssertTrue('vertical: the vertical bar', FBox.VertScrollBar.Visible);
  AssertFalse('vertical: not the horizontal one', FBox.HorzScrollBar.Visible);
  FBox.StyleOverride := '--scrollbox-bars: horizontal;';
  AssertFalse('horizontal: not the vertical bar', FBox.VertScrollBar.Visible);
  AssertTrue('horizontal: the horizontal one', FBox.HorzScrollBar.Visible);
  FBox.StyleOverride := '--scrollbox-bars: none;';
  AssertFalse('none: vertical', FBox.VertScrollBar.Visible);
  AssertFalse('none: horizontal', FBox.HorzScrollBar.Visible);
end;

{ Visible answers what the box may show, wherever that was said: code ported from the LCL
  asks `if Box.VertScrollBar.Visible`, and the answer has to be the true one. }
procedure TScrollBoxBarPropsTest.VisibleReadsTheThemesTokenToo;
begin
  FCtl.StyleOverride := ':root { --scrollbox-bars: horizontal; }';
  AssertFalse('the theme leaves the vertical bar out', FBox.VertScrollBar.Visible);
  AssertTrue('and keeps the horizontal one', FBox.HorzScrollBar.Visible);
end;

procedure TScrollBoxBarPropsTest.HidingABarWritesTheToken;
begin
  FBox.HorzScrollBar.Visible := False;
  AssertEquals('--scrollbox-bars: vertical;', FBox.StyleOverride);
  FBox.VertScrollBar.Visible := False;
  AssertEquals('--scrollbox-bars: none;', FBox.StyleOverride);
  FBox.HorzScrollBar.Visible := True;
  AssertEquals('--scrollbox-bars: horizontal;', FBox.StyleOverride);
  FBox.VertScrollBar.Visible := True;
  AssertEquals('both again, which is what the theme gives: nothing of its own is left', '',
    FBox.StyleOverride);
end;

procedure TScrollBoxBarPropsTest.AHiddenBarIsLeftOutAtOnce;
begin
  AssertTrue('setup: the content overflows both ways', FBox.VShown and FBox.HShown);
  FBox.HorzScrollBar.Visible := False;
  AssertFalse('the horizontal bar is gone', FBox.HShown);
  AssertTrue('the vertical one stays', FBox.VShown);
  FBox.HorzScrollBar.Visible := True;
  AssertTrue('and it is back', FBox.HShown);
end;

procedure TScrollBoxBarPropsTest.TheRestOfTheOverrideIsKept;
begin
  FBox.StyleOverride := 'background: #FF0000;';
  FBox.VertScrollBar.Visible := False;
  AssertEquals('background: #FF0000; --scrollbox-bars: horizontal;', FBox.StyleOverride);
  FBox.VertScrollBar.Visible := True;
  AssertEquals('background: #FF0000;', FBox.StyleOverride);
end;

{ The Object Inspector, a copy and Assign all set a property to the value it already shows.
  That must not rewrite what was written by hand. }
procedure TScrollBoxBarPropsTest.SettingVisibleToWhatItShowsChangesNothing;
const
  S = '--scrollbox-bars:  VERTICAL ;';
begin
  FBox.StyleOverride := S;
  FBox.HorzScrollBar.Visible := False;
  FBox.VertScrollBar.Visible := True;
  AssertEquals(S, FBox.StyleOverride);
end;

procedure TScrollBoxBarPropsTest.ABarTheThemeHidesCanBeShownHere;
begin
  FCtl.StyleOverride := ':root { --scrollbox-bars: none; }';
  FBox.VertScrollBar.Visible := True;
  AssertEquals('this box says so itself', '--scrollbox-bars: vertical;', FBox.StyleOverride);
  AssertTrue(FBox.VertScrollBar.Visible);
  AssertFalse('the other bar is still the theme''s to hide', FBox.HorzScrollBar.Visible);
  FBox.VertScrollBar.Visible := False;
  AssertEquals('back to what the theme gives: nothing of its own is left', '', FBox.StyleOverride);
end;

procedure TScrollBoxBarPropsTest.TheSubObjectsArePublishedAndStoreNothing;
begin
  AssertNotNull('TTyScrollBox.HorzScrollBar', GetPropInfo(TTyScrollBox, 'HorzScrollBar'));
  AssertNotNull('TTyScrollBox.VertScrollBar', GetPropInfo(TTyScrollBox, 'VertScrollBar'));
  AssertNotNull('TTyScrollPanel.HorzScrollBar', GetPropInfo(TTyScrollPanel, 'HorzScrollBar'));
  AssertNotNull('TTyScrollPanel.VertScrollBar', GetPropInfo(TTyScrollPanel, 'VertScrollBar'));
  AssertNotNull('Visible', GetPropInfo(FBox.HorzScrollBar, 'Visible'));
  FBox.HorzScrollBar.Visible := False;
  AssertFalse('only StyleOverride goes into the form file',
    IsStoredProp(FBox.HorzScrollBar, 'Visible'));
end;

procedure TScrollBoxBarPropsTest.AFormSavedByThisVersionStoresTheOverrideOnly;
var
  txt: string;
begin
  FBox.Name := 'Box';
  FBox.HorzScrollBar.Visible := False;
  txt := FormText(FBox);
  AssertTrue('the override is there: ' + txt, Pos('--scrollbox-bars: vertical;', txt) > 0);
  AssertEquals('and no scroll bar property beside it', 0, Pos('ScrollBar.', txt));
end;

procedure TScrollBoxBarPropsTest.AFormFromAnLclScrollBoxLoads;
var
  f: TForm;
  box: TTyScrollBox;
begin
  f := LoadForm(
    '  object Box: TTyScrollBox'#10 +
    '    Left = 0'#10 +
    '    Height = 200'#10 +
    '    Top = 0'#10 +
    '    Width = 300'#10 +
    '    HorzScrollBar.Increment = 30'#10 +
    '    HorzScrollBar.Page = 80'#10 +
    '    HorzScrollBar.Range = 640'#10 +
    '    HorzScrollBar.Smooth = True'#10 +
    '    HorzScrollBar.Tracking = True'#10 +
    '    HorzScrollBar.Visible = False'#10 +
    '    VertScrollBar.Increment = 20'#10 +
    '    VertScrollBar.Page = 1'#10 +
    '    VertScrollBar.Position = 12'#10 +
    '    VertScrollBar.Range = 900'#10 +
    '    VertScrollBar.Tracking = True'#10 +
    '  end'#10);
  try
    box := f.FindComponent('Box') as TTyScrollBox;
    AssertNotNull('the box was read', box);
    AssertFalse('HorzScrollBar.Visible = False was taken', box.HorzScrollBar.Visible);
    AssertTrue('the vertical bar, which the form did not hide, may show', box.VertScrollBar.Visible);
    AssertEquals('as the token', '--scrollbox-bars: vertical;', box.StyleOverride);
  finally
    f.Free;
  end;
end;

procedure TScrollBoxBarPropsTest.AssigningCopiesVisible;
var
  other: TBarsBox;
begin
  other := TBarsBox.Create(FForm);
  other.Parent := FForm;
  other.Controller := FCtl;
  FBox.HorzScrollBar.Visible := False;
  other.HorzScrollBar := FBox.HorzScrollBar;
  other.VertScrollBar := FBox.VertScrollBar;
  AssertFalse('the horizontal bar, hidden there, is hidden here', other.HorzScrollBar.Visible);
  AssertTrue('the vertical one may show, as there', other.VertScrollBar.Visible);
  AssertEquals('--scrollbox-bars: vertical;', other.StyleOverride);
end;

procedure TScrollBoxBarPropsTest.AScrollPanelHasThemToo;
var
  p: TTyScrollPanel;
begin
  p := TTyScrollPanel.Create(FForm);
  p.Parent := FForm;
  p.Controller := FCtl;
  p.VertScrollBar.Visible := False;
  AssertEquals('--scrollbox-bars: horizontal;', p.StyleOverride);
  AssertFalse(p.VertScrollBar.Visible);
  AssertTrue(p.HorzScrollBar.Visible);
end;

initialization
  RegisterTest(TScrollBoxBarPropsTest);
  { the .lfm text of AFormFromAnLclScrollBoxLoads names it }
  RegisterClasses([TTyScrollBox]);
end.
