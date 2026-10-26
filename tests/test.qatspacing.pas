unit test.qatspacing;
{ #117: the quick access toolbar's Indent and Spacing place its buttons -- before, only a
  measuring helper read them, and the buttons packed flush against the edge and each other. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Controls, Forms, fpcunit, testregistry,
  tyControls.Base, tyControls.RibbonQuickAccess, tyControls.GlyphButtons;

type
  TQatSpacingTest = class(TTestCase)
  private
    FForm: TForm;
    FQat: TTyRibbonQuickAccess;
    FA, FB: TTyGlyphButton;
    procedure Realign;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheFirstButtonStartsAtTheIndent;
    procedure TestTheButtonsAreSpacingApart;
    procedure TestBothScaleWithThePPI;
    procedure TestChildSizingIsNotWrittenToTheForm;
  end;

implementation

type
  TWinAcc = class(TWinControl);

procedure TQatSpacingTest.Realign;
var
  r: TRect;
begin
  r := FQat.ClientRect;
  TWinAcc(FQat).AlignControls(nil, r);
end;

procedure TQatSpacingTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FQat := TTyRibbonQuickAccess.Create(FForm);
  FQat.Parent := FForm;
  FQat.Font.PixelsPerInch := 96;
  FQat.SetBounds(0, 0, 200, 26);
  FA := FQat.AddButton('A');
  FB := FQat.AddButton('B');
  Realign;
end;

procedure TQatSpacingTest.TearDown;
begin
  FreeAndNil(FForm);
end;

procedure TQatSpacingTest.TestTheFirstButtonStartsAtTheIndent;
begin
  AssertEquals('the default indent', 3, FA.Left);
  FQat.Indent := 10;
  Realign;
  AssertEquals('a set indent', 10, FA.Left);
end;

procedure TQatSpacingTest.TestTheButtonsAreSpacingApart;
begin
  AssertEquals('the default spacing', FA.Left + FA.Width + 2, FB.Left);
  FQat.Spacing := 8;
  Realign;
  AssertEquals('a set spacing', FA.Left + FA.Width + 8, FB.Left);
end;

procedure TQatSpacingTest.TestBothScaleWithThePPI;
begin
  FQat.Indent := 5;
  FQat.Spacing := 4;
  { LCL's own DPI pass, as a move to a 200% monitor runs it; it does not scale ChildSizing. }
  FQat.AutoAdjustLayout(lapAutoAdjustForDPI, 96, 192, 0, 0);
  Realign;
  AssertEquals('logical px: the indent doubles at 200%', 10, FA.Left);
  AssertEquals('and so does the spacing', FA.Left + FA.Width + 8, FB.Left);
end;

procedure TQatSpacingTest.TestChildSizingIsNotWrittenToTheForm;
var
  ms: TMemoryStream;
  s: string;
begin
  if GetClass('TTyRibbonQuickAccess') = nil then RegisterClass(TTyRibbonQuickAccess);
  if GetClass('TTyGlyphButton') = nil then RegisterClass(TTyGlyphButton);
  FQat.Name := 'Qat';
  ms := TMemoryStream.Create;
  try
    ms.WriteComponent(FQat);
    SetLength(s, ms.Size);
    if ms.Size > 0 then Move(ms.Memory^, s[1], ms.Size);
    AssertEquals('Indent and Spacing own the spacing; ChildSizing is not stored', 0,
      Pos('LeftRightSpacing', s) + Pos('HorizontalSpacing', s));
  finally
    ms.Free;
  end;
end;

initialization
  RegisterTest(TQatSpacingTest);
end.
