unit test.button.lowheight;
{$mode objfpc}{$H+}

{ #241: a button may be lower than one line of text plus the padding.

  Two heights where there was one. The COMFORTABLE height is a line of content plus the
  style's vertical padding: what a tool bar, a flow panel and a dialog size their rows by.
  The FLOOR is a line of content plus the border: what Constraints.MinHeight holds, so a
  height stored below the comfortable one is kept. In a box lower than the comfortable
  height the padding gives way and the caption stays whole and centred.

  The theme here: a 1 px border, 6 px above and below the caption, black ink. }

interface

uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, ExtCtrls, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.Painter,
  tyControls.Button, tyControls.GlyphButtons, tyControls.ToolBar, tyControls.ToolBarEx,
  tyControls.ToolGroupPanel, tyControls.ColorButton, tyControls.Transfer, tyControls.Grid,
  tyControls.Panel, tyControls.BuiltinThemes, tyControls.Dialogs, tyControls.Dialogs.Color;

type
  TLowButton = class(TTyButton)
  public
    function Line: Integer;
    procedure Shot(ACanvas: TCanvas; const R: TRect; APPI: Integer);
  end;

  TLowGlyph = class(TTyGlyphButton)
  public
    function Line: Integer;
    function Slot: Integer;
    procedure Shot(ACanvas: TCanvas; const R: TRect; APPI: Integer);
  end;

  TLowColor = class(TTyColorButton)
  public
    function PrefW: Integer;
    function Line: Integer;
    procedure Shot(ACanvas: TCanvas; const R: TRect; APPI: Integer);
  end;

  TLowArrow = class(TTyTransferArrowButton)
  public
    procedure Shot(ACanvas: TCanvas; const R: TRect; APPI: Integer);
  end;

  TFilterGrid = class(TTyStringGrid)
  public
    function FilterPanel: TTyPanel;
  end;

  TButtonLowHeightTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FB: TLowButton;
    function NewButton(const ACaption: string): TLowButton;
    { The box of the dark pixels (the caption's ink) of the button painted H tall. }
    function CaptionInk(B: TLowButton; H: Integer): TRect;
    function RedInk(B: TLowGlyph; H: Integer): TRect;
    procedure LayOut(AParent: TWinControl);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TheComfortableHeightIsALineAndThePadding;
    procedure TheFloorIsALineAndTheBorder;
    procedure WithNoBorderTheFloorIsTheLine;
    procedure AHeightBelowTheComfortableOneIsKept;
    procedure TheComfortableHeightFollowsThePadding;
    procedure InALowBoxTheCaptionIsWholeAndCentred;
    procedure AtItsComfortableHeightAButtonIsPaintedAsBefore;
    procedure AToolBarsRowIsStillTheComfortableHeight;
    procedure AnOverflowBarsRowIsStillTheComfortableHeight;
    procedure AFlowPanelsRowIsStillTheComfortableHeight;
    procedure AnotherControlsComfortableHeightIsItsFloor;
    procedure AGlyphBesideItsCaptionFitsTheLowBox;
    procedure InABoxLowerThanALineNothingLeavesTheBox;
    procedure AColourButtonsSwatchFitsTheLowBox;
    procedure ATransferArrowIsCentredInALowBox;
    procedure TheGridsFilterButtonsStayComfortable;
    procedure AnOverflowFlyoutsItemsAreComfortable;
    procedure TheColourDialogsButtonsStayComfortable;
  end;

implementation

const
  CCss =
    'TyButton { color: #000000; background: #E0E0E0; border-width: 1px; border-color: #909090;' +
    ' border-radius: 0px; padding: 6px 12px; }' +
    'TyToolBar { background: #FFFFFF; }';
  CPadV = 12;
  CBorderV = 2;

type
  TBarAccess = class(TTyCustomToolBar);
  TPanelAccess = class(TTyCustomToolGroupPanel);

function TLowButton.Line: Integer;
begin
  Result := MeasureContentHeight(96);
end;

procedure TLowButton.Shot(ACanvas: TCanvas; const R: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, R, APPI);
end;

function TLowColor.PrefW: Integer;
var
  h: Integer;
begin
  Result := 0;
  h := 0;
  CalculatePreferredSize(Result, h, True);
end;

function TLowColor.Line: Integer;
begin
  Result := MeasureContentHeight(96);
end;

procedure TLowColor.Shot(ACanvas: TCanvas; const R: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, R, APPI);
end;

procedure TLowArrow.Shot(ACanvas: TCanvas; const R: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, R, APPI);
end;

function TFilterGrid.FilterPanel: TTyPanel;
begin
  EnsureFilterDropDown;
  Result := FilterDropDownPanel;
end;

function TLowGlyph.Line: Integer;
begin
  Result := MeasureContentHeight(96);
end;

function TLowGlyph.Slot: Integer;
begin
  Result := MeasureGlyphSlot(96, CurrentStyle);
end;

procedure TLowGlyph.Shot(ACanvas: TCanvas; const R: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, R, APPI);
end;

procedure TButtonLowHeightTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(CCss);
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(-4000, -4000, 800, 400);
  FB := NewButton('Save');
end;

procedure TButtonLowHeightTest.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

function TButtonLowHeightTest.NewButton(const ACaption: string): TLowButton;
begin
  Result := TLowButton.Create(FForm);
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.Caption := ACaption;
  Result.Parent := FForm;
  Result.SetBounds(0, 0, 100, 40);
end;

function TButtonLowHeightTest.CaptionInk(B: TLowButton; H: Integer): TRect;
var
  bmp: TBitmap;
  img: TBGRABitmap;
  x, y: Integer;
  p: TBGRAPixel;
begin
  Result := Rect(MaxInt, MaxInt, -1, -1);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(100, H);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, 100, H);
    B.Shot(bmp.Canvas, Rect(0, 0, 100, H), 96);
    img := TBGRABitmap.Create(bmp);
    try
      for y := 0 to img.Height - 1 do
        for x := 0 to img.Width - 1 do
        begin
          p := img.GetPixel(x, y);
          if (p.red > 70) or (p.green > 70) or (p.blue > 70) then Continue;
          if x < Result.Left then Result.Left := x;
          if y < Result.Top then Result.Top := y;
          if x + 1 > Result.Right then Result.Right := x + 1;
          if y + 1 > Result.Bottom then Result.Bottom := y + 1;
        end;
    finally
      img.Free;
    end;
  finally
    bmp.Free;
  end;
  if Result.Right < 0 then Result := Rect(0, 0, 0, 0);
end;

function TButtonLowHeightTest.RedInk(B: TLowGlyph; H: Integer): TRect;
var
  bmp: TBitmap;
  img: TBGRABitmap;
  x, y: Integer;
  p: TBGRAPixel;
begin
  Result := Rect(MaxInt, MaxInt, -1, -1);
  B.GlyphColor := TyRGB(255, 0, 0);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(B.Width, H);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, B.Width, H);
    B.Shot(bmp.Canvas, Rect(0, 0, B.Width, H), 96);
    img := TBGRABitmap.Create(bmp);
    try
      for y := 0 to img.Height - 1 do
        for x := 0 to img.Width - 1 do
        begin
          p := img.GetPixel(x, y);
          if not ((p.red > 150) and (p.green < 110) and (p.blue < 110)) then Continue;
          if x < Result.Left then Result.Left := x;
          if y < Result.Top then Result.Top := y;
          if x + 1 > Result.Right then Result.Right := x + 1;
          if y + 1 > Result.Bottom then Result.Bottom := y + 1;
        end;
    finally
      img.Free;
    end;
  finally
    bmp.Free;
  end;
  if Result.Right < 0 then Result := Rect(0, 0, 0, 0);
end;

procedure TButtonLowHeightTest.LayOut(AParent: TWinControl);
var
  r: TRect;
begin
  r := Rect(0, 0, AParent.Width, AParent.Height);
  if AParent is TTyCustomToolBar then TBarAccess(AParent).AlignControls(nil, r)
  else TPanelAccess(AParent).AlignControls(nil, r);
end;

procedure TButtonLowHeightTest.TheComfortableHeightIsALineAndThePadding;
begin
  AssertTrue('setup: a line was measured', FB.Line > 8);
  AssertEquals(FB.Line + CPadV, FB.ComfortableHeight);
end;

procedure TButtonLowHeightTest.TheFloorIsALineAndTheBorder;
begin
  AssertEquals('what the constraint holds', FB.Line + CBorderV, FB.Constraints.MinHeight);
  FB.Height := 5;
  AssertEquals('and so what a height of 5 comes to', FB.Line + CBorderV, FB.Height);
end;

procedure TButtonLowHeightTest.WithNoBorderTheFloorIsTheLine;
begin
  FB.StyleOverride := 'border-width: 0px;';
  AssertEquals(FB.Line, FB.Constraints.MinHeight);
end;

{ What the issue is for: LCL's TButton is 25 px high, and a form ported from it stores 25. }
procedure TButtonLowHeightTest.AHeightBelowTheComfortableOneIsKept;
var
  low: Integer;
begin
  low := FB.ComfortableHeight - 4;
  AssertTrue('setup: between the floor and the comfortable height', low > FB.Constraints.MinHeight);
  FB.Height := low;
  AssertEquals(low, FB.Height);
end;

procedure TButtonLowHeightTest.TheComfortableHeightFollowsThePadding;
var
  floor: Integer;
begin
  floor := FB.Constraints.MinHeight;
  FB.StyleOverride := 'padding: 10px 12px;';
  AssertEquals('more padding: more comfortable', FB.Line + 20, FB.ComfortableHeight);
  AssertEquals('the floor has no padding in it', floor, FB.Constraints.MinHeight);
end;

procedure TButtonLowHeightTest.InALowBoxTheCaptionIsWholeAndCentred;
var
  roomy, tight: TRect;
  low: Integer;
begin
  roomy := CaptionInk(FB, FB.ComfortableHeight + 10);
  AssertTrue('setup: the caption is drawn', roomy.Bottom > roomy.Top);
  low := FB.Line + 4;          // well under the comfortable height, over the floor
  tight := CaptionInk(FB, low);
  AssertEquals('every row of the caption''s ink is still there', roomy.Bottom - roomy.Top,
    tight.Bottom - tight.Top);
  AssertEquals('and as wide', roomy.Right - roomy.Left, tight.Right - tight.Left);
  AssertTrue(Format('it sits in the middle of the box (%d above, %d below)',
    [tight.Top, low - tight.Bottom]), Abs(tight.Top - (low - tight.Bottom)) <= 2);
end;

{ The padding gives way only when it has to: at the comfortable height the caption is where
  the full padding puts it, and it is there in a taller box too. }
procedure TButtonLowHeightTest.AtItsComfortableHeightAButtonIsPaintedAsBefore;
var
  at, above: TRect;
  h: Integer;
begin
  h := FB.ComfortableHeight;
  at := CaptionInk(FB, h);
  above := CaptionInk(FB, h + 10);
  AssertEquals('ten px taller: the caption five px lower', at.Top + 5, above.Top);
  AssertTrue(Format('at the comfortable height the ink starts below the top padding (%d)', [at.Top]),
    at.Top >= 6);
end;

procedure TButtonLowHeightTest.AToolBarsRowIsStillTheComfortableHeight;
var
  bar: TTyToolBar;
  b: TLowButton;
begin
  bar := TTyToolBar.Create(FForm);
  bar.Parent := FForm;
  bar.Controller := FCtl;
  bar.Font.PixelsPerInch := 96;
  bar.Align := alNone;
  bar.SetBounds(0, 100, 400, 120);
  bar.ButtonHeight := 10;        // asks for less than any button is comfortable at
  b := NewButton('Save');
  b.Parent := bar;
  LayOut(bar);
  AssertTrue('setup: the floor is lower', b.Constraints.MinHeight < b.ComfortableHeight);
  AssertEquals(b.ComfortableHeight, b.Height);
end;

procedure TButtonLowHeightTest.AnOverflowBarsRowIsStillTheComfortableHeight;
var
  bar: TTyToolBarEx;
  b: TLowButton;
begin
  bar := TTyToolBarEx.Create(FForm);
  bar.Parent := FForm;
  bar.Controller := FCtl;
  bar.Font.PixelsPerInch := 96;
  bar.Align := alNone;
  bar.SetBounds(0, 100, 400, 120);
  bar.ButtonHeight := 10;
  b := NewButton('Save');
  b.Parent := bar;
  LayOut(bar);
  AssertEquals(b.ComfortableHeight, b.Height);
end;

procedure TButtonLowHeightTest.AFlowPanelsRowIsStillTheComfortableHeight;
var
  panel: TTyToolGroupPanel;
  b: TLowButton;
begin
  panel := TTyToolGroupPanel.Create(FForm);
  panel.Parent := FForm;
  panel.Controller := FCtl;
  panel.Font.PixelsPerInch := 96;
  panel.SetBounds(0, 100, 400, 160);
  panel.ButtonHeight := 10;
  b := NewButton('Save');
  b.Parent := panel;
  LayOut(panel);
  AssertEquals(b.ComfortableHeight, b.Height);
end;

procedure TButtonLowHeightTest.AnotherControlsComfortableHeightIsItsFloor;
var
  p: TPanel;
begin
  p := TPanel.Create(FForm);
  p.Parent := FForm;
  p.Constraints.MinHeight := 17;
  AssertEquals('not a button: the floor it has', 17, TyComfortableHeight(p));
  AssertEquals('a button: its comfortable height', FB.ComfortableHeight, TyComfortableHeight(FB));
end;

{ An icon nobody sized, beside its caption, is as tall as the content box. In a low box that
  box is the line the padding left: the icon measured and the icon drawn are that. }
procedure TButtonLowHeightTest.AGlyphBesideItsCaptionFitsTheLowBox;
var
  g: TLowGlyph;
  low: Integer;
  ink: TRect;
begin
  g := TLowGlyph.Create(FForm);
  g.Controller := FCtl;
  g.Font.PixelsPerInch := 96;
  g.Caption := 'Go';
  g.GlyphKind := tgCheck;
  g.Parent := FForm;
  low := g.Line + 4;
  g.SetBounds(0, 200, 100, low);
  AssertEquals('setup: the low height is kept', low, g.Height);
  AssertEquals('the slot is the line, not the box less a padding it no longer has', g.Line, g.Slot);
  ink := RedInk(g, low);
  AssertTrue('the icon is drawn', ink.Bottom > ink.Top);
  AssertTrue(Format('inside the box (%d..%d of %d)', [ink.Top, ink.Bottom, low]),
    (ink.Top >= 0) and (ink.Bottom <= low));
  AssertTrue(Format('and no taller than the slot (%d against %d)', [ink.Bottom - ink.Top, g.Slot]),
    ink.Bottom - ink.Top <= g.Slot);
end;

{ A box lower than the content itself -- nothing a constraint allows, but RenderTo can be
  handed one. The insets stop at nothing; they do not go negative and push the content
  box out past the button. }
procedure TButtonLowHeightTest.InABoxLowerThanALineNothingLeavesTheBox;
var
  g: TLowGlyph;
  low: Integer;
  ink: TRect;
begin
  g := TLowGlyph.Create(FForm);
  g.Controller := FCtl;
  g.Font.PixelsPerInch := 96;
  g.Caption := 'Go';
  g.GlyphKind := tgCheck;
  g.Parent := FForm;
  g.SetBounds(0, 200, 100, 40);
  low := g.Line - 6;
  AssertTrue('setup: a box of some height', low > 4);
  ink := RedInk(g, low);
  AssertTrue('the icon is still drawn', ink.Bottom > ink.Top);
  AssertTrue(Format('and no taller than the box (%d of %d)', [ink.Bottom - ink.Top, low]),
    ink.Bottom - ink.Top <= low);
  AssertTrue(Format('nor wider: it was fitted to the box, not cut off by it (%d of %d)',
    [ink.Right - ink.Left, low]), ink.Right - ink.Left <= low);
end;

{ The swatch is a square as tall as the content box. In a low box that is what the padding
  left, and the width the button asks for is measured from the same square. }
procedure TButtonLowHeightTest.AColourButtonsSwatchFitsTheLowBox;
var
  c: TLowColor;
  roomy, tight, low: Integer;
begin
  c := TLowColor.Create(FForm);
  c.Controller := FCtl;
  c.Font.PixelsPerInch := 96;
  c.ShowText := True;
  c.Parent := FForm;
  c.SetBounds(0, 240, 140, 30);
  AssertTrue('setup: the hex line is lower than the 18 px the padding leaves of 30', c.Line < 18);
  roomy := c.PrefW;                      // a swatch of 30 - 12 = 18
  low := c.Line + 4;                     // under the comfortable height
  c.Height := low;
  AssertEquals('setup: the low height is kept', low, c.Height);
  tight := c.PrefW;
  AssertEquals('the swatch is as tall as the line the padding left',
    roomy - (18 - c.Line), tight);
end;

{ The arrow button paints in its whole face, not in the content box: it adds the padding
  back. In a low box it has to add back what was really taken. }
procedure TButtonLowHeightTest.ATransferArrowIsCentredInALowBox;

  function ArrowInk(B: TLowArrow; H: Integer): TRect;
  var
    bmp: TBitmap;
    img: TBGRABitmap;
    x, y: Integer;
    p: TBGRAPixel;
  begin
    Result := Rect(MaxInt, MaxInt, -1, -1);
    bmp := TBitmap.Create;
    try
      bmp.PixelFormat := pf32bit;
      bmp.SetSize(40, H);
      bmp.Canvas.Brush.Color := clWhite;
      bmp.Canvas.FillRect(0, 0, 40, H);
      B.Shot(bmp.Canvas, Rect(0, 0, 40, H), 96);
      img := TBGRABitmap.Create(bmp);
      try
        for y := 2 to img.Height - 3 do          // inside the border
          for x := 2 to img.Width - 3 do
          begin
            p := img.GetPixel(x, y);
            if (p.red > 125) or (p.green > 125) or (p.blue > 125) then Continue;   // under the border's 144
            if x < Result.Left then Result.Left := x;
            if y < Result.Top then Result.Top := y;
            if x + 1 > Result.Right then Result.Right := x + 1;
            if y + 1 > Result.Bottom then Result.Bottom := y + 1;
          end;
      finally
        img.Free;
      end;
    finally
      bmp.Free;
    end;
    if Result.Right < 0 then Result := Rect(0, 0, 0, 0);
  end;

var
  a: TLowArrow;
  roomy, tight: TRect;
  low: Integer;
begin
  a := TLowArrow.Create(FForm);
  a.Controller := FCtl;
  a.Font.PixelsPerInch := 96;
  a.Move := tmMoveRight;
  a.Parent := FForm;
  a.SetBounds(0, 280, 40, 40);
  roomy := ArrowInk(a, 40);
  AssertTrue('setup: the arrow is drawn', roomy.Bottom > roomy.Top);
  low := a.Constraints.MinHeight;        // the floor: all the padding but the border's share
  tight := ArrowInk(a, low);
  AssertTrue('the arrow is drawn in the low box', tight.Bottom > tight.Top);
  AssertTrue(Format('in the middle of it (%d above, %d below)', [tight.Top, low - tight.Bottom]),
    Abs(tight.Top - (low - tight.Bottom)) <= 1);
end;

{ The filter panel hands its two buttons a literal 26 px. They came out at their comfortable
  height while that was their floor, and still do. }
procedure TButtonLowHeightTest.TheGridsFilterButtonsStayComfortable;
var
  g: TFilterGrid;
  panel: TTyPanel;
  i, seen: Integer;
  b: TTyCustomButton;
  theme: string;
begin
  { The panel is not parented until the popup shows, so its buttons read the default
    controller: the roomy padding goes there, and is taken away again at the end. }
  TyRegisterBuiltinThemes;
  theme := TyDefaultController.ThemeName;
  TyDefaultController.LoadThemeCssAdditive('TyButton { padding: 14px 12px; }');
  try
  g := TFilterGrid.Create(FForm);
  g.Controller := FCtl;
  g.Font.PixelsPerInch := 96;
  g.Parent := FForm;
  panel := g.FilterPanel;
  seen := 0;
  for i := 0 to panel.ControlCount - 1 do
    if panel.Controls[i] is TTyCustomButton then
    begin
      b := TTyCustomButton(panel.Controls[i]);
      Inc(seen);
      AssertTrue(Format('setup: comfortable (%d) is over the 26 the panel hands out', [b.ComfortableHeight]),
        b.ComfortableHeight > 26);
      AssertEquals(b.Caption + ' is as high as it is comfortable', b.ComfortableHeight, b.Height);
      AssertTrue(b.Caption + ' is inside the panel', b.Top + b.Height <= panel.Height);
    end;
  AssertEquals('setup: OK and Cancel', 2, seen);
  finally
    TyDefaultController.ThemeName := theme;   // a REPLACE load: drops the additive layer
  end;
end;

procedure TButtonLowHeightTest.AnOverflowFlyoutsItemsAreComfortable;
var
  bar: TTyToolBarEx;
  b: TLowButton;
  i: Integer;
begin
  bar := TTyToolBarEx.Create(FForm);
  bar.Parent := FForm;
  bar.Controller := FCtl;
  bar.Font.PixelsPerInch := 96;
  bar.Align := alNone;
  bar.SetBounds(0, 100, 130, 120);
  bar.ButtonHeight := 10;
  b := nil;
  for i := 1 to 5 do
  begin
    b := NewButton('Tool');
    b.Width := 60;
    b.Parent := bar;
  end;
  LayOut(bar);
  AssertTrue('setup: tools went into the overflow', bar.OverflowCount > 0);
  AssertTrue('setup: the floor is lower', b.Constraints.MinHeight < b.ComfortableHeight);
  AssertEquals(b.ComfortableHeight, bar.FlyoutItemHeight);
end;

{ The colour dialog hands its "add to custom colours" button the height of an edit. Under a
  theme roomier than any built in, that is less than the button is comfortable at. }
procedure TButtonLowHeightTest.TheColourDialogsButtonsStayComfortable;
var
  theme: string;
  d: TTyColorForm;
  custom: TStringList;
  seen: Integer;

  procedure Walk(AParent: TWinControl);
  var
    i: Integer;
    c: TControl;
  begin
    for i := 0 to AParent.ControlCount - 1 do
    begin
      c := AParent.Controls[i];
      if (c is TTyButton) and c.Visible then
      begin
        Inc(seen);
        AssertTrue(Format('"%s" is %d high, its comfortable height is %d',
          [TTyButton(c).Caption, c.Height, TTyButton(c).ComfortableHeight]),
          c.Height >= TTyButton(c).ComfortableHeight);
      end;
      if c is TWinControl then Walk(TWinControl(c));
    end;
  end;

begin
  TyRegisterBuiltinThemes;
  theme := TyDefaultController.ThemeName;
  TyDefaultController.LoadThemeCssAdditive('TyButton { padding: 14px 12px; }');
  try
    d := TyBuildColorDialog('Colour', TyRGB($33, $66, $99));
    custom := TStringList.Create;
    try
      custom.Add('ColorA=FF8000');   // LCL's TColorDialog.CustomColors format; an empty list builds nothing
      d.SetCustomColors(custom);     // what TTyColorDialog.Execute does: the custom row and its button
      seen := 0;
      Walk(d);
      AssertTrue(Format('setup: OK, Cancel and the add button (%d seen)', [seen]), seen >= 3);
    finally
      custom.Free;
      d.Free;
    end;
  finally
    TyDefaultController.ThemeName := theme;
  end;
end;

initialization
  RegisterTest(TButtonLowHeightTest);
end.
