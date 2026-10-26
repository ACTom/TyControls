unit test.fontprecedence;
{ #112: a font set on a control, or on a container below the form, wins over the theme -- its
  size included -- and StyleOverride still wins over both; a font that only came down from the
  form leaves the theme in charge. Run headless on the built-in theme: the theme's own values
  are read off an untouched control, so the numbers do not depend on which theme it is. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Controls, Graphics, Forms, fpcunit, testregistry,
  tyControls.Types, tyControls.Base, tyControls.Edit, tyControls.TyLabel, tyControls.Panel;

type
  TFontEditProbe = class(TTyEdit)
  public
    Invalidations: Integer;
    function Style: TTyStyleSet;
    function Size: Integer;
    function OwnFont: Boolean;
    procedure Invalidate; override;
  end;

  TFontLabelProbe = class(TTyLabel)
  public
    function Style: TTyStyleSet;
    function Size: Integer;
  end;

  TFontPrecedenceTest = class(TTestCase)
  private
    FForm: TForm;
    FPanel: TTyPanel;
    FEdit: TFontEditProbe;
    FLabel: TFontLabelProbe;
    FRef: TFontEditProbe;
    function ThemeSize: Integer;
    function Red(const S: TTyStyleSet): Integer;
    function Blue(const S: TTyStyleSet): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAnExplicitSizeBeatsTheTheme;
    procedure TestOnlyTheColourSetLeavesTheSizeToTheTheme;
    procedure TestAContainersFontReachesItsChildren;
    procedure TestTheFormsFontLeavesTheThemeAlone;
    procedure TestStyleOverrideStillWins;
    procedure TestPuttingTheContainersFontBackRestoresTheTheme;
    procedure TestAnUnparentedControlCountsItsOwnFont;
    procedure TestAContainersFontChangeRepaintsAChildWithItsOwnFont;
  end;

implementation

{ TFontEditProbe }

function TFontEditProbe.Style: TTyStyleSet;
begin
  Result := CurrentStyle;
end;

function TFontEditProbe.Size: Integer;
begin
  Result := ResolveFontSize(CurrentStyle);
end;

function TFontEditProbe.OwnFont: Boolean;
begin
  Result := not ParentFont;
end;

procedure TFontEditProbe.Invalidate;
begin
  Inc(Invalidations);
  inherited Invalidate;
end;

{ TFontLabelProbe }

function TFontLabelProbe.Style: TTyStyleSet;
begin
  Result := CurrentStyle;
end;

function TFontLabelProbe.Size: Integer;
begin
  Result := TyResolveFontSize(CurrentStyle, ParentFont, Font.Size, ActiveController);
end;

{ TFontPrecedenceTest }

procedure TFontPrecedenceTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FPanel := TTyPanel.Create(FForm);
  FPanel.Parent := FForm;
  FEdit := TFontEditProbe.Create(FForm);
  FEdit.Parent := FPanel;
  FLabel := TFontLabelProbe.Create(FForm);
  FLabel.Parent := FPanel;
  FRef := TFontEditProbe.Create(FForm);   // never touched: what the theme says
  FRef.Parent := FForm;
end;

procedure TFontPrecedenceTest.TearDown;
begin
  FreeAndNil(FForm);
end;

function TFontPrecedenceTest.ThemeSize: Integer;
begin
  Result := FRef.Size;
end;

function TFontPrecedenceTest.Red(const S: TTyStyleSet): Integer;
begin
  Result := TyRedOf(S.TextColor);
end;

function TFontPrecedenceTest.Blue(const S: TTyStyleSet): Integer;
begin
  Result := TyBlueOf(S.TextColor);
end;

procedure TFontPrecedenceTest.TestAnExplicitSizeBeatsTheTheme;
begin
  AssertTrue('precondition: the theme gives the edit a size', ThemeSize > 0);
  FEdit.Font.Size := ThemeSize + 7;
  AssertEquals('the edit''s own size', ThemeSize + 7, FEdit.Size);
  FLabel.Font.Size := ThemeSize + 7;
  AssertEquals('the label''s own size', ThemeSize + 7, FLabel.Size);
end;

procedure TFontPrecedenceTest.TestOnlyTheColourSetLeavesTheSizeToTheTheme;
var
  base: Integer;
begin
  base := ThemeSize;
  FForm.Font.Size := base + 3;   // reaches the edit as a copy, through the panel
  FEdit.Font.Color := clRed;
  AssertTrue('precondition: the edit now keeps its own font', FEdit.OwnFont);
  AssertEquals('the size it was handed is the form''s, so the theme''s stays', base, FEdit.Size);
  AssertEquals('the colour it was given counts', 255, Red(FEdit.Style));
end;

procedure TFontPrecedenceTest.TestAContainersFontReachesItsChildren;
var
  base: Integer;
begin
  base := ThemeSize;
  FPanel.Font.Size := base + 5;
  FPanel.Font.Color := clBlue;
  AssertFalse('precondition: the edit still takes its parent''s font', FEdit.OwnFont);
  AssertEquals('the edit takes the panel''s size', base + 5, FEdit.Size);
  AssertEquals('and its colour', 255, Blue(FEdit.Style));
  AssertEquals('so does the label', base + 5, FLabel.Size);
  AssertEquals('the label''s colour', 255, Blue(FLabel.Style));
end;

procedure TFontPrecedenceTest.TestTheFormsFontLeavesTheThemeAlone;
var
  base: Integer;
  face: string;
begin
  base := ThemeSize;
  face := FRef.Style.FontName;
  FForm.Font.Size := base + 5;
  FForm.Font.Name := 'Courier New';
  AssertEquals('size: the theme''s', base, FEdit.Size);
  AssertEquals('face: the theme''s', face, FEdit.Style.FontName);
  AssertEquals('a control right on the form too', base, FRef.Size);
end;

procedure TFontPrecedenceTest.TestStyleOverrideStillWins;
begin
  FEdit.Font.Size := ThemeSize + 7;
  FEdit.StyleOverride := 'font-size: 6px;';
  AssertEquals('StyleOverride over the control''s own size', 6, FEdit.Size);
end;

procedure TFontPrecedenceTest.TestPuttingTheContainersFontBackRestoresTheTheme;
var
  base, was: Integer;
begin
  base := ThemeSize;
  was := FPanel.Font.Size;
  FPanel.Font.Size := base + 5;
  AssertEquals('precondition: the child follows the panel', base + 5, FEdit.Size);
  FPanel.Font.Size := was;   // the form's again
  AssertEquals('back to the theme''s size', base, FEdit.Size);
end;

procedure TFontPrecedenceTest.TestAnUnparentedControlCountsItsOwnFont;
var
  e: TFontEditProbe;
  base: Integer;
begin
  base := ThemeSize;
  e := TFontEditProbe.Create(nil);
  try
    e.Font.Size := base + 4;
    AssertEquals('no parent: its own size counts', base + 4, e.Size);
  finally
    e.Free;
  end;
end;

procedure TFontPrecedenceTest.TestAContainersFontChangeRepaintsAChildWithItsOwnFont;
begin
  FEdit.Font.Color := clRed;   // keeps its own font from here on: no copy will reach it
  FEdit.Invalidations := 0;
  FPanel.Font.Size := ThemeSize + 5;
  AssertTrue('the child repaints: what of its font counts has changed',
    FEdit.Invalidations > 0);
end;

initialization
  RegisterTest(TFontPrecedenceTest);
end.
