unit test.toolbar.display;
{$mode objfpc}{$H+}

{ How a tool bar's buttons are sized and shown in each display mode:

    #228  an icon-only button is as wide as its icon, not as its hidden caption;
    #229  an icon stacked above its caption leaves room for the caption;
    #230  ButtonHeight sizes the buttons and the separators, not only the row;
    #231  --toolbar-icon-size gives every icon button on a bar one icon size;
    #232  a caption that is not drawn serves as the hint.

  The icon is a painter glyph (GlyphKind), so no test here depends on a font. Sizes are read
  through the measuring methods the paint uses: LCL's AutoSize does nothing while the form
  has no handle, and the headless runner never makes one. }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, LCLType, LMessages, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.Painter,
  tyControls.Button, tyControls.GlyphButtons, tyControls.ToolBar, tyControls.ToolBarEx,
  tyControls.Edit, BGRABitmap, BGRABitmapTypes;

type
  TToolbarDisplayTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FBar: TTyToolBar;
    function NewBar: TTyToolBar;
    function NewEx(AWidth: Integer): TTyToolBarEx;
    function AddTool(const ACaption: string; AWithIcon: Boolean = True;
      ABar: TTyCustomToolBar = nil): TTyToolButton;
    function IconBox(B: TTyGlyphButtonBase; AHeight: Integer = 0; AWidth: Integer = 0): TRect;
    function BoxText(const R: TRect): string;
    procedure Layout(ABar: TTyCustomToolBar = nil);
    function PrefW(B: TTyGlyphButtonBase): Integer;
    function Slot(B: TTyGlyphButtonBase): Integer;
    function Floor(B: TTyGlyphButtonBase): Integer;
    function PadX(B: TTyGlyphButtonBase): Integer;
    function PadY(B: TTyGlyphButtonBase): Integer;
    function HintOf(B: TControl; const AStart: string = ''): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { #228 }
    procedure AnIconOnlyButtonIsAsWideAsItsIcon;
    procedure TheBarsShowCaptionsMovesAToolsWidth;
    procedure AButtonWithNoIconKeepsItsCaptionsWidth;
    procedure AnIconOnlyStackedButtonAsksNoRoomForACaption;
    { #229 }
    procedure AStackedIconLeavesRoomForItsCaption;
    procedure AStackedIconIsNeverUnderSixteen;
    procedure ATallStackedButtonDrawsALargerIcon;
    procedure TheRowGrowsForAStackedIconAndItsCaption;
    procedure AStackedButtonWithoutACaptionFillsItsBox;
    procedure AnIconBesideItsCaptionIsSizedAsBefore;
    procedure AnIconUnderItsCaptionFollowsTheSameRule;
    procedure TheLeastStackedIconScalesWithThePPI;
    procedure AStackedIconIsDrawnAtTheSizeMeasured;
    procedure InABoxTooShortTheStackedIconIsStillDrawn;
    procedure InABoxTooNarrowTheStackedIconKeepsToItsWidth;
    { #230 }
    procedure ButtonHeightSizesTheButtons;
    procedure ASeparatorTakesTheRowsHeight;
    procedure AnEditKeepsItsHeightAndIsCentred;
    procedure AnEditTallerThanTheRowIsHeldToIt;
    procedure AToolThatNeedsMoreStillMakesTheRowTaller;
    { #231 }
    procedure WithoutTheTokenAnIconIsSizedFromItsButton;
    procedure TheBarsIconSizeReachesEveryIconButton;
    procedure AButtonsOwnGlyphSizeWins;
    procedure OneBarSetsItsOwnIconSize;
    procedure AButtonOffTheBarIsNotTouched;
    procedure AStackedRowGrowsWithTheIconSize;
    procedure ANewIconSizeIsMeasuredAgain;
    procedure ANewIconSizeMovesTheToolsFloorAtOnce;
    procedure ANegativeIconSizeIsNoIconSize;
    procedure TheBarsIconSizeIsTheSizeDrawn;
    procedure ALargeIconBesideItsCaptionMakesTheRowTaller;
    procedure ALargeIconAloneMakesTheRowTaller;
    procedure AnIconNoTallerThanTheCaptionLeavesTheRowAlone;
    procedure SmallIconsWithNoCaptionsLetTheRowBeLow;
    procedure AButtonsOwnSizeBesideItsCaptionAsksNoHeight;
    procedure OnTheOverflowBarALargeIconMakesTheRowTaller;
    procedure TheOverflowChevronIsNotGivenTheIconSize;
    procedure AToolInTheOverflowFlyoutKeepsTheBarsIconSize;
    { #232 }
    procedure ACaptionThatIsNotDrawnIsTheHint;
    procedure AWrittenHintIsKept;
    procedure ACaptionThatIsDrawnAddsNoHint;
    procedure AButtonWithNoIconAddsNoHint;
  end;

implementation

type
  { reach the protected measuring methods and the bar's layout }
  TGlyphCrack = class(TTyGlyphButtonBase);
  TBarCrack = class(TTyCustomToolBar);
  TExCrack = class(TTyToolBarEx);

{ ---- fixture ---- }

procedure TToolbarDisplayTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(-4000, -4000, 800, 400);
  FBar := NewBar;
end;

procedure TToolbarDisplayTest.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

function TToolbarDisplayTest.NewBar: TTyToolBar;
begin
  Result := TTyToolBar.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.Align := alNone;   // the layout under test, not the form's
  Result.SetBounds(0, 0, 700, 200);
end;

function TToolbarDisplayTest.NewEx(AWidth: Integer): TTyToolBarEx;
begin
  Result := TTyToolBarEx.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.Align := alNone;
  Result.SetBounds(0, 0, AWidth, 200);
end;

function TToolbarDisplayTest.AddTool(const ACaption: string; AWithIcon: Boolean;
  ABar: TTyCustomToolBar): TTyToolButton;
begin
  if ABar = nil then ABar := FBar;
  Result := TTyToolButton.Create(FForm);
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.Caption := ACaption;
  if AWithIcon then Result.GlyphKind := tgCheck;
  Result.Width := 60;
  Result.Parent := ABar;
end;

{ Where the icon is DRAWN: the button is painted with a red icon into a picture of its own
  size (or of the size given), and the red pixels are boxed. Empty when no icon was drawn. }
function TToolbarDisplayTest.IconBox(B: TTyGlyphButtonBase; AHeight, AWidth: Integer): TRect;
var
  bmp: TBitmap;
  img: TBGRABitmap;
  x, y: Integer;
  p: TBGRAPixel;
begin
  if AHeight <= 0 then AHeight := B.Height;
  if AWidth <= 0 then AWidth := B.Width;
  Result := Rect(MaxInt, MaxInt, -1, -1);
  B.GlyphColor := TyRGB(255, 0, 0);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(AWidth, AHeight);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, AWidth, AHeight);
    TGlyphCrack(B).RenderTo(bmp.Canvas, Rect(0, 0, AWidth, AHeight), 96);
    img := TBGRABitmap.Create(bmp);
    try
      for y := 0 to img.Height - 1 do
        for x := 0 to img.Width - 1 do
        begin
          p := img.GetPixel(x, y);
          if (p.red > 150) and (p.green < 110) and (p.blue < 110) then
          begin
            if x < Result.Left then Result.Left := x;
            if y < Result.Top then Result.Top := y;
            if x + 1 > Result.Right then Result.Right := x + 1;
            if y + 1 > Result.Bottom then Result.Bottom := y + 1;
          end;
        end;
    finally
      img.Free;
    end;
  finally
    bmp.Free;
  end;
  if Result.Right < 0 then Result := Rect(0, 0, 0, 0);
end;

function TToolbarDisplayTest.BoxText(const R: TRect): string;
begin
  Result := Format('%d,%d-%d,%d', [R.Left, R.Top, R.Right, R.Bottom]);
end;

procedure TToolbarDisplayTest.Layout(ABar: TTyCustomToolBar);
var
  r: TRect;
begin
  if ABar = nil then ABar := FBar;
  r := Rect(0, 0, ABar.Width, ABar.Height);
  TBarCrack(ABar).AlignControls(nil, r);   // headless: no message pump lays it out
end;

function TToolbarDisplayTest.PrefW(B: TTyGlyphButtonBase): Integer;
var
  h: Integer;
begin
  Result := 0;
  h := 0;
  TGlyphCrack(B).CalculatePreferredSize(Result, h, True);
end;

function TToolbarDisplayTest.Slot(B: TTyGlyphButtonBase): Integer;
begin
  Result := TGlyphCrack(B).MeasureGlyphSlot(96, TGlyphCrack(B).CurrentStyle);
end;

function TToolbarDisplayTest.Floor(B: TTyGlyphButtonBase): Integer;
begin
  Result := TGlyphCrack(B).MeasureContentHeight(96);
end;

function TToolbarDisplayTest.PadX(B: TTyGlyphButtonBase): Integer;
var
  s: TTyStyleSet;
begin
  s := TGlyphCrack(B).CurrentStyle;
  Result := s.Padding.Left + s.Padding.Right;
end;

function TToolbarDisplayTest.PadY(B: TTyGlyphButtonBase): Integer;
var
  s: TTyStyleSet;
begin
  s := TGlyphCrack(B).CurrentStyle;
  Result := s.Padding.Top + s.Padding.Bottom;
end;

{ What LCL would show: it fills HintStr from the control's Hint, then lets the control have
  the last word through CM_HINTSHOW. }
function TToolbarDisplayTest.HintOf(B: TControl; const AStart: string): string;
var
  info: THintInfo;
begin
  info := Default(THintInfo);
  info.HintControl := B;
  info.HintStr := AStart;
  B.Perform(CM_HINTSHOW, 0, LParam(PtrUInt(@info)));
  Result := info.HintStr;
end;

{ ---- #228: the width of an icon-only button ---- }

procedure TToolbarDisplayTest.AnIconOnlyButtonIsAsWideAsItsIcon;
var
  b: TTyToolButton;
  withCaption: Integer;
begin
  b := AddTool('Save all changes');
  b.Height := 24;
  b.ShowCaption := True;
  withCaption := PrefW(b);
  b.ShowCaption := False;
  AssertEquals('the icon and the padding, nothing for the caption', Slot(b) + PadX(b), PrefW(b));
  AssertTrue(Format('narrower than with its caption (%d against %d)', [PrefW(b), withCaption]),
    PrefW(b) + 40 < withCaption);
end;

procedure TToolbarDisplayTest.TheBarsShowCaptionsMovesAToolsWidth;
var
  b: TTyToolButton;
  iconOnly, withCaption: Integer;
begin
  b := AddTool('Save all changes');
  b.Height := 24;
  FBar.ShowCaptions := False;
  iconOnly := PrefW(b);
  FBar.ShowCaptions := True;
  withCaption := PrefW(b);
  AssertTrue(Format('captions on: wider (%d against %d)', [withCaption, iconOnly]),
    withCaption > iconOnly + 40);
  FBar.ShowCaptions := False;
  AssertEquals('captions off again: back to the icon', iconOnly, PrefW(b));
end;

procedure TToolbarDisplayTest.AButtonWithNoIconKeepsItsCaptionsWidth;
var
  plain, hidden: TTyToolButton;
begin
  plain := AddTool('Save all changes', False);
  hidden := AddTool('Save all changes', False);
  hidden.ShowCaption := False;   // nothing to show in its place: the caption is still drawn
  AssertEquals('its caption is drawn, so its width is the caption''s', PrefW(plain), PrefW(hidden));
end;

procedure TToolbarDisplayTest.AnIconOnlyStackedButtonAsksNoRoomForACaption;
var
  b: TTyToolButton;
  withCaption: Integer;
begin
  b := AddTool('Save');
  b.GlyphLayout := glTop;
  b.GlyphSize := 24;
  b.ShowCaption := True;
  withCaption := Floor(b);
  b.ShowCaption := False;
  AssertEquals('only the icon', 24, Floor(b));
  AssertTrue('less than with the caption under it', Floor(b) < withCaption);
end;

{ ---- #229: an icon above its caption ---- }

procedure TToolbarDisplayTest.AStackedIconLeavesRoomForItsCaption;
var
  b: TTyToolButton;
  box, line, gap: Integer;
begin
  b := AddTool('Save');
  b.ShowCaption := True;
  b.GlyphLayout := glTop;
  b.Height := 60;
  box := b.ClientHeight - PadY(b);
  b.GlyphLayout := glLeft;
  line := Floor(b);                       // beside the caption the floor is the caption's line
  b.GlyphLayout := glTop;
  gap := TGlyphCrack(b).EffectiveGapPx(96);
  AssertTrue('setup: the box holds an icon over 16', box - gap - line > 16);
  AssertEquals('the icon takes what the caption and the gap leave', box - gap - line, Slot(b));
end;

procedure TToolbarDisplayTest.AStackedIconIsNeverUnderSixteen;
var
  b: TTyToolButton;
begin
  b := AddTool('Save');
  b.ShowCaption := True;
  b.GlyphLayout := glTop;
  b.Height := 24;   // no room for both
  AssertEquals('the least an icon above a caption is', 16, Slot(b));
end;

procedure TToolbarDisplayTest.ATallStackedButtonDrawsALargerIcon;
var
  b: TTyToolButton;
  small: Integer;
begin
  b := AddTool('Save');
  b.ShowCaption := True;
  b.GlyphLayout := glTop;
  b.Height := 60;
  small := Slot(b);
  b.Height := 80;
  AssertEquals('twenty more of height, twenty more of icon', small + 20, Slot(b));
end;

procedure TToolbarDisplayTest.TheRowGrowsForAStackedIconAndItsCaption;
var
  b: TTyToolButton;
  line, gap: Integer;
begin
  b := AddTool('Save');
  line := Floor(b);
  gap := TGlyphCrack(b).EffectiveGapPx(96);
  FBar.ShowCaptions := True;
  FBar.List := False;      // icon above caption, and no GlyphSize on the tool
  Layout;
  AssertEquals('the floor: sixteen of icon, the gap, the caption''s line', 16 + gap + line, Floor(b));
  AssertTrue(Format('the tool is tall enough for both (%d)', [b.Height]),
    b.Height >= 16 + gap + line + PadY(b));
end;

procedure TToolbarDisplayTest.AStackedButtonWithoutACaptionFillsItsBox;
var
  b: TTyToolButton;
begin
  b := AddTool('');
  b.GlyphLayout := glTop;
  b.SetBounds(0, 0, 60, 40);
  AssertEquals('no caption: the icon is the box', b.ClientHeight - PadY(b), Slot(b));
  b.Caption := 'Save';
  b.ShowCaption := False;
  AssertEquals('a hidden caption: the same', b.ClientHeight - PadY(b), Slot(b));
end;

procedure TToolbarDisplayTest.AnIconBesideItsCaptionIsSizedAsBefore;
var
  b: TTyToolButton;
begin
  b := AddTool('Save');
  b.ShowCaption := True;
  b.GlyphLayout := glLeft;
  b.Height := 40;
  AssertEquals('beside the caption: the box''s height', b.ClientHeight - PadY(b), Slot(b));
end;

{ ---- #230: ButtonHeight ---- }

procedure TToolbarDisplayTest.ButtonHeightSizesTheButtons;
var
  tool: TTyToolButton;
  plain: TTyButton;
  speed: TTySpeedButton;
begin
  tool := AddTool('One');
  plain := TTyButton.Create(FForm);
  plain.Controller := FCtl;
  plain.Font.PixelsPerInch := 96;
  plain.Caption := 'Two';
  plain.Parent := FBar;
  speed := TTySpeedButton.Create(FForm);
  speed.Controller := FCtl;
  speed.Font.PixelsPerInch := 96;
  speed.GlyphKind := tgCheck;
  speed.Parent := FBar;

  FBar.ButtonHeight := 44;
  Layout;
  AssertEquals('a tool button', 44, tool.Height);
  AssertEquals('a plain button', 44, plain.Height);
  AssertEquals('a speed button', 44, speed.Height);
  AssertEquals('all on one line', tool.Top, speed.Top);

  FBar.ButtonHeight := 30;
  Layout;
  AssertEquals('and down again', 30, tool.Height);
  AssertEquals('a plain button too', 30, plain.Height);
end;

procedure TToolbarDisplayTest.ASeparatorTakesTheRowsHeight;
var
  tool, sepTool: TTyToolButton;
  sep: TTyToolSeparator;
begin
  tool := AddTool('One');
  sep := TTyToolSeparator.Create(FForm);
  sep.Controller := FCtl;
  sep.Parent := FBar;
  sepTool := AddTool('', False);
  sepTool.Style := tbsSeparator;

  FBar.ButtonHeight := 44;
  Layout;
  AssertEquals('setup: the tool', 44, tool.Height);
  AssertEquals('a separator control', 44, sep.Height);
  AssertEquals('a separator tool button', 44, sepTool.Height);
  AssertEquals('at the row''s top', tool.Top, sep.Top);
end;

procedure TToolbarDisplayTest.AnEditKeepsItsHeightAndIsCentred;
var
  tool: TTyToolButton;
  ed: TTyEdit;
  h: Integer;
begin
  tool := AddTool('One');
  ed := TTyEdit.Create(FForm);
  ed.Controller := FCtl;
  ed.Font.PixelsPerInch := 96;
  ed.Parent := FBar;
  ed.Width := 100;
  FBar.ButtonHeight := 24;
  Layout;
  h := ed.Height;   // what it is in a row no taller than itself

  FBar.ButtonHeight := h + 30;
  Layout;
  AssertEquals('setup: the button fills the row', h + 30, tool.Height);
  AssertEquals('an edit keeps its own height', h, ed.Height);
  AssertEquals('centred in the row', tool.Top + 15, ed.Top);
end;

procedure TToolbarDisplayTest.AnEditTallerThanTheRowIsHeldToIt;
var
  tool: TTyToolButton;
  ed: TTyEdit;
begin
  tool := AddTool('One');
  ed := TTyEdit.Create(FForm);
  ed.Controller := FCtl;
  ed.Font.PixelsPerInch := 96;
  ed.Parent := FBar;
  ed.Width := 100;
  FBar.ButtonHeight := 40;
  ed.Height := 90;
  AssertTrue('setup: the edit is taller than the row', ed.Height > 40);
  Layout;
  AssertEquals('setup: the row is forty', 40, tool.Height);
  AssertEquals('as tall as the row, no more', 40, ed.Height);
  AssertEquals('and on it', tool.Top, ed.Top);
end;

procedure TToolbarDisplayTest.AToolThatNeedsMoreStillMakesTheRowTaller;
var
  low, high: TTyToolButton;
begin
  low := AddTool('One');
  high := AddTool('Two');
  high.ShowCaption := True;
  high.GlyphLayout := glTop;
  high.GlyphSize := 32;       // needs far more than the row asks for
  FBar.ButtonHeight := 24;
  Layout;
  AssertTrue(Format('setup: the row grew (%d)', [high.Height]), high.Height > 40);
  AssertEquals('and its neighbour grew with it', high.Height, low.Height);
end;

procedure TToolbarDisplayTest.AnIconUnderItsCaptionFollowsTheSameRule;
var
  b: TTyToolButton;
  above, floorAbove: Integer;
begin
  b := AddTool('Save');
  b.ShowCaption := True;
  b.GlyphLayout := glTop;
  b.Height := 60;
  above := Slot(b);
  floorAbove := Floor(b);
  AssertTrue('setup: the caption took its share', above < b.ClientHeight - PadY(b));
  b.GlyphLayout := glBottom;
  AssertEquals('the same icon', above, Slot(b));
  AssertEquals('and the same floor', floorAbove, Floor(b));
end;

{ Sixteen is logical px. Read at 150% it is twenty-four, in the slot and in the floor. }
procedure TToolbarDisplayTest.TheLeastStackedIconScalesWithThePPI;
var
  b: TTyToolButton;
  line, gap: Integer;
begin
  b := AddTool('Save');
  b.ShowCaption := True;
  b.GlyphLayout := glLeft;
  line := TGlyphCrack(b).MeasureContentHeight(144);
  b.GlyphLayout := glTop;
  gap := TGlyphCrack(b).EffectiveGapPx(144);
  AssertTrue('setup: at 150% this box holds no icon over the least',
    b.ClientHeight - MulDiv(PadY(b), 144, 96) - gap - line < 24);
  AssertEquals('the least icon at 150%', 24,
    TGlyphCrack(b).MeasureGlyphSlot(144, TGlyphCrack(b).CurrentStyle));
  AssertEquals('and the floor counts it in the same px', 24 + gap + line,
    TGlyphCrack(b).MeasureContentHeight(144));
end;

{ The measurement and the paint are two pieces of code. A twin that is GIVEN the measured
  size has its icon in the same place, so the paint drew what was measured. }
procedure TToolbarDisplayTest.AStackedIconIsDrawnAtTheSizeMeasured;
var
  b, twin: TTyToolButton;
  box, twinBox: TRect;
begin
  b := AddTool('Save');
  b.ShowCaption := True;
  b.GlyphLayout := glTop;
  b.SetBounds(0, 0, 70, 64);
  AssertTrue('setup: over the least', Slot(b) > 16);
  twin := AddTool('Save');
  twin.ShowCaption := True;
  twin.GlyphLayout := glTop;
  twin.GlyphSize := Slot(b);
  twin.SetBounds(0, 0, 70, 64);
  AssertEquals('setup: the twin is as wide', b.Width, twin.Width);
  AssertEquals('setup: and as tall', b.Height, twin.Height);
  box := IconBox(b);
  twinBox := IconBox(twin);
  AssertTrue('setup: an icon was drawn', box.Right > box.Left);
  AssertEquals('drawn where a button given that size draws it', BoxText(twinBox), BoxText(box));
end;

{ Nothing holds a caller of RenderTo to the size floor. In a box with no room for both, the
  icon is drawn at its least and the caption is what gives way. }
procedure TToolbarDisplayTest.InABoxTooShortTheStackedIconIsStillDrawn;
var
  b, twin: TTyToolButton;
  box, twinBox: TRect;
begin
  b := AddTool('Save');
  b.ShowCaption := True;
  b.GlyphLayout := glTop;
  b.SetBounds(0, 0, 70, 64);
  twin := AddTool('Save');
  twin.ShowCaption := True;
  twin.GlyphLayout := glTop;
  twin.GlyphSize := 16;
  twin.SetBounds(0, 0, 70, 64);
  AssertEquals('setup: the twin is as wide', b.Width, twin.Width);
  box := IconBox(b, 24);
  twinBox := IconBox(twin, 24);
  AssertTrue('the icon is drawn', box.Right > box.Left);
  AssertEquals('at sixteen', BoxText(twinBox), BoxText(box));
end;

{ The same for the width: the icon is a square, and it is no wider than its box. }
procedure TToolbarDisplayTest.InABoxTooNarrowTheStackedIconKeepsToItsWidth;
var
  b, twin: TTyToolButton;
  cw: Integer;
  box, twinBox: TRect;
begin
  b := AddTool('Save');
  b.ShowCaption := True;
  b.GlyphLayout := glTop;
  b.SetBounds(0, 0, 90, 90);
  cw := 50 - PadX(b);                      // the content box of a picture fifty wide
  AssertTrue(Format('setup: a box narrower than the icon would be (%d)', [cw]),
    (cw > 4) and (cw < Slot(b)));
  twin := AddTool('Save');
  twin.ShowCaption := True;
  twin.GlyphLayout := glTop;
  twin.GlyphSize := cw;
  twin.SetBounds(0, 0, 90, 90);
  box := IconBox(b, 90, 50);
  twinBox := IconBox(twin, 90, 50);
  AssertTrue('the icon is drawn', box.Right > box.Left);
  AssertEquals('as wide as the box, and placed as an icon of that size', BoxText(twinBox), BoxText(box));
end;

{ ---- #231: --toolbar-icon-size ---- }

procedure TToolbarDisplayTest.WithoutTheTokenAnIconIsSizedFromItsButton;
var
  b: TTyToolButton;
begin
  b := AddTool('Save');
  b.ShowCaption := False;
  b.Height := 40;
  AssertEquals('auto: the box', b.ClientHeight - PadY(b), Slot(b));
  b.Height := 30;
  AssertEquals('and it follows the button', b.ClientHeight - PadY(b), Slot(b));
end;

procedure TToolbarDisplayTest.TheBarsIconSizeReachesEveryIconButton;
var
  tool: TTyToolButton;
  speed: TTySpeedButton;
  glyph: TTyGlyphButton;
begin
  tool := AddTool('One');
  speed := TTySpeedButton.Create(FForm);
  speed.Controller := FCtl;
  speed.GlyphKind := tgCheck;
  speed.Parent := FBar;
  glyph := TTyGlyphButton.Create(FForm);
  glyph.Controller := FCtl;
  glyph.GlyphKind := tgCheck;
  glyph.Caption := 'Three';
  glyph.Parent := FBar;

  FCtl.StyleOverride := ':root { --toolbar-icon-size: 20px; }';
  tool.Height := 40;
  speed.Height := 40;
  glyph.Height := 40;
  AssertEquals('a tool button', 20, Slot(tool));
  AssertEquals('a speed button', 20, Slot(speed));
  AssertEquals('a glyph button', 20, Slot(glyph));
  tool.Height := 60;
  AssertEquals('whatever the button''s height', 20, Slot(tool));
  AssertEquals('and it is counted in the width', 20 + PadX(speed), PrefW(speed));
end;

procedure TToolbarDisplayTest.AButtonsOwnGlyphSizeWins;
var
  own, other: TTyToolButton;
begin
  own := AddTool('One');
  other := AddTool('Two');
  own.GlyphSize := 12;
  FCtl.StyleOverride := ':root { --toolbar-icon-size: 20px; }';
  AssertEquals('the size the button was given', 12, Slot(own));
  AssertEquals('its neighbour takes the bar''s', 20, Slot(other));
end;

procedure TToolbarDisplayTest.OneBarSetsItsOwnIconSize;
var
  here, there: TTyToolButton;
  second: TTyToolBar;
begin
  here := AddTool('One');
  second := NewBar;
  there := TTyToolButton.Create(FForm);
  there.Controller := FCtl;
  there.GlyphKind := tgCheck;
  there.Parent := second;
  FCtl.StyleOverride := ':root { --toolbar-icon-size: 20px; }';
  FBar.StyleOverride := '--toolbar-icon-size: 28px;';
  AssertEquals('the bar that says so', 28, Slot(here));
  AssertEquals('the other bar keeps the theme''s', 20, Slot(there));
  FBar.StyleOverride := '';
  AssertEquals('taken away: the theme''s again', 20, Slot(here));
end;

procedure TToolbarDisplayTest.AButtonOffTheBarIsNotTouched;
var
  b: TTyGlyphButton;
begin
  FCtl.StyleOverride := ':root { --toolbar-icon-size: 20px; }';
  b := TTyGlyphButton.Create(FForm);
  b.Controller := FCtl;
  b.Font.PixelsPerInch := 96;
  b.GlyphKind := tgCheck;
  b.Parent := FForm;
  b.SetBounds(0, 220, 80, 40);
  AssertEquals('a button on a form: sized from its box', b.ClientHeight - PadY(b), Slot(b));
end;

procedure TToolbarDisplayTest.AStackedRowGrowsWithTheIconSize;
var
  b: TTyToolButton;
  line, gap: Integer;
begin
  b := AddTool('Save');
  line := Floor(b);
  gap := TGlyphCrack(b).EffectiveGapPx(96);
  FCtl.StyleOverride := ':root { --toolbar-icon-size: 32px; }';
  FBar.ShowCaptions := True;
  FBar.List := False;
  Layout;
  AssertEquals('the icon the bar asks for', 32, Slot(b));
  AssertEquals('the floor holds it with its caption', 32 + gap + line, Floor(b));
  AssertTrue(Format('and the tool is that tall (%d)', [b.Height]),
    b.Height >= 32 + gap + line + PadY(b));
end;

{ GetPreferredSize keeps its answer until the control is told it is stale. A bar whose icon
  size changes has to tell its buttons. }
procedure TToolbarDisplayTest.ANewIconSizeIsMeasuredAgain;
var
  b: TTyToolButton;
  w, h, w2: Integer;
begin
  b := AddTool('Save');
  b.ShowCaption := False;
  FBar.StyleOverride := '--toolbar-icon-size: 16px;';
  w := 0; h := 0;
  b.GetPreferredSize(w, h, True);
  AssertEquals('setup: sixteen and the padding', 16 + PadX(b), w);
  FBar.StyleOverride := '--toolbar-icon-size: 28px;';
  w2 := 0; h := 0;
  b.GetPreferredSize(w2, h, True);
  AssertEquals('the new size, not the one remembered', 28 + PadX(b), w2);
end;

{ The layout reads each tool's Constraints.MinHeight. A new icon size has to be in there
  before the bar lays out again, not after the tool happens to be repainted. }
procedure TToolbarDisplayTest.ANewIconSizeMovesTheToolsFloorAtOnce;
var
  b: TTyToolButton;
begin
  b := AddTool('Save');
  FBar.StyleOverride := '--toolbar-icon-size: 16px;';
  AssertTrue('setup: a floor under forty', b.Constraints.MinHeight < 40);
  FBar.StyleOverride := '--toolbar-icon-size: 40px;';
  AssertEquals('the floor the layout will read', 40 + PadY(b), b.Constraints.MinHeight);
end;

procedure TToolbarDisplayTest.ANegativeIconSizeIsNoIconSize;
begin
  FBar.StyleOverride := '--toolbar-icon-size: 12px;';
  AssertEquals('setup: the token is read', 12, FBar.HostGlyphSize(nil));
  FBar.StyleOverride := '--toolbar-icon-size: -12px;';
  AssertEquals('nothing to give', 0, FBar.HostGlyphSize(nil));
end;

procedure TToolbarDisplayTest.TheBarsIconSizeIsTheSizeDrawn;
var
  other: TTyToolBar;
  b, twin, auto: TTyToolButton;
  box, twinBox, autoBox: TRect;
begin
  b := AddTool('Save');                       // icon only, the bar's default
  FBar.StyleOverride := '--toolbar-icon-size: 20px;';
  other := NewBar;                            // a bar with no icon size
  twin := AddTool('Save', True, other);
  twin.GlyphSize := 20;
  auto := AddTool('Save', True, other);
  b.SetBounds(0, 0, 60, 48);
  twin.SetBounds(0, 0, 60, 48);
  auto.SetBounds(0, 0, 60, 48);
  box := IconBox(b);
  twinBox := IconBox(twin);
  autoBox := IconBox(auto);
  AssertTrue('setup: an icon was drawn', box.Right > box.Left);
  AssertEquals('drawn as on a button given twenty itself', BoxText(twinBox), BoxText(box));
  AssertTrue(Format('and smaller than one sized from this box (%s against %s)',
    [BoxText(box), BoxText(autoBox)]),
    (autoBox.Right - autoBox.Left) > (box.Right - box.Left) + 6);
end;

{ "Large icons" has to make the row tall enough for them: an icon fitted into the old row
  is not a larger icon. }
procedure TToolbarDisplayTest.ALargeIconBesideItsCaptionMakesTheRowTaller;
var
  b: TTyToolButton;
  line: Integer;
  box: TRect;
begin
  b := AddTool('Save');
  FBar.ShowCaptions := True;
  line := Floor(b);
  AssertTrue('setup: the caption''s line is under forty', line < 40);
  FBar.StyleOverride := '--toolbar-icon-size: 40px;';
  Layout;
  AssertEquals('the floor is the icon', 40, Floor(b));
  AssertTrue(Format('the tool is tall enough for it (%d)', [b.Height]),
    b.Height >= 40 + PadY(b));
  box := IconBox(b);
  AssertTrue(Format('and it is drawn that large (%s)', [BoxText(box)]),
    box.Bottom - box.Top > 30);
end;

procedure TToolbarDisplayTest.ALargeIconAloneMakesTheRowTaller;
var
  b: TTyToolButton;
begin
  b := AddTool('Save');
  FBar.ShowCaptions := False;
  FBar.StyleOverride := '--toolbar-icon-size: 40px;';
  Layout;
  AssertEquals('the floor is the icon', 40, Floor(b));
  AssertTrue(Format('the tool is tall enough for it (%d)', [b.Height]),
    b.Height >= 40 + PadY(b));
  AssertEquals('and as wide as the icon and the padding', 40 + PadX(b), PrefW(b));
end;

procedure TToolbarDisplayTest.AnIconNoTallerThanTheCaptionLeavesTheRowAlone;
var
  b: TTyToolButton;
  line: Integer;
begin
  b := AddTool('Save');
  FBar.ShowCaptions := True;
  line := Floor(b);
  FBar.StyleOverride := '--toolbar-icon-size: 8px;';
  AssertTrue('setup: the caption''s line is over eight', line > 8);
  AssertEquals('the floor is still the caption''s line', line, Floor(b));
end;

{ "Small icons", captions off, a low ButtonHeight: the compact bar. The line of a caption
  that is not drawn must not hold the row up. }
procedure TToolbarDisplayTest.SmallIconsWithNoCaptionsLetTheRowBeLow;
var
  b: TTyToolButton;
  line: Integer;
begin
  b := AddTool('Save');
  FBar.ShowCaptions := False;
  line := Floor(b);
  AssertTrue(Format('setup: the caption''s line is over six (%d)', [line]), line > 6);
  FBar.StyleOverride := '--toolbar-icon-size: 6px;';
  FBar.ButtonHeight := 4;
  Layout;
  AssertEquals('the floor is the icon', 6, Floor(b));
  AssertEquals('and the tool is the icon and its padding', 6 + PadY(b), b.Height);
  b.ShowCaption := True;       // this one tool shows its caption after all
  AssertEquals('a caption that is drawn has its line', line, Floor(b));
end;

{ A button's own GlyphSize beside its caption was always fitted into the box the form gave
  the button. It still is: a form that sets one does not find its buttons grown. }
procedure TToolbarDisplayTest.AButtonsOwnSizeBesideItsCaptionAsksNoHeight;
var
  b: TTyToolButton;
  line: Integer;
begin
  b := AddTool('Save');
  b.ShowCaption := True;
  line := Floor(b);
  b.GlyphSize := 40;
  AssertEquals('the floor is the caption''s line, as before', line, Floor(b));
end;

procedure TToolbarDisplayTest.OnTheOverflowBarALargeIconMakesTheRowTaller;
var
  ex: TTyToolBarEx;
  b: TTyToolButton;
begin
  ex := NewEx(700);
  b := AddTool('Save', True, ex);
  ex.StyleOverride := '--toolbar-icon-size: 40px;';
  Layout(ex);
  AssertEquals('the icon the bar asks for', 40, Slot(b));
  AssertTrue(Format('the tool is tall enough for it (%d)', [b.Height]),
    b.Height >= 40 + PadY(b));
end;

{ The overflow chevron is a glyph button on the bar too, but it is a part of the bar, not one
  of its tools. }
procedure TToolbarDisplayTest.TheOverflowChevronIsNotGivenTheIconSize;
var
  ex: TTyToolBarEx;
  first: TTyToolButton;
  chevron: TTyGlyphButtonBase;
  i: Integer;
begin
  ex := NewEx(130);
  first := AddTool('One', True, ex);
  for i := 2 to 5 do AddTool('Tool', True, ex);
  ex.StyleOverride := '--toolbar-icon-size: 40px;';
  Layout(ex);
  AssertTrue('setup: the bar overflows', ex.OverflowVisible);
  chevron := nil;
  for i := 0 to ex.ControlCount - 1 do
    if ex.Controls[i] is TTyGlyphButton then chevron := TTyGlyphButtonBase(ex.Controls[i]);
  AssertNotNull('setup: the chevron', chevron);
  AssertEquals('a tool takes the bar''s size', 40, TGlyphCrack(first).GivenGlyphSize);
  AssertEquals('the chevron is given none, and is sized from its cell', 0,
    TGlyphCrack(chevron).GivenGlyphSize);
end;

{ An overflowed tool is moved into the flyout while that is open. It is the bar's tool
  there too. }
procedure TToolbarDisplayTest.AToolInTheOverflowFlyoutKeepsTheBarsIconSize;
var
  ex: TTyToolBarEx;
  b: TTyToolButton;
begin
  ex := NewEx(700);
  b := AddTool('Save', True, ex);
  ex.StyleOverride := '--toolbar-icon-size: 28px;';
  AssertEquals('on the bar', 28, Slot(b));
  b.Parent := TExCrack(ex).EnsureFlyout;   // what opening the flyout does to an overflowed tool
  try
    AssertEquals('in the flyout', 28, Slot(b));
  finally
    b.Parent := ex;
  end;
end;

{ ---- #232: the hint of an icon-only button ---- }

procedure TToolbarDisplayTest.ACaptionThatIsNotDrawnIsTheHint;
var
  b: TTyToolButton;
begin
  b := AddTool('&Save');
  b.ShowCaption := False;
  AssertEquals('the caption, without its accelerator mark', 'Save', HintOf(b));
end;

procedure TToolbarDisplayTest.AWrittenHintIsKept;
var
  b: TTyToolButton;
begin
  b := AddTool('&Save');
  b.ShowCaption := False;
  b.Hint := 'Save the file';
  AssertEquals('the application''s own hint', 'Save the file', HintOf(b, 'Save the file'));
end;

procedure TToolbarDisplayTest.ACaptionThatIsDrawnAddsNoHint;
var
  b: TTyToolButton;
begin
  b := AddTool('&Save');
  b.ShowCaption := True;
  AssertEquals('the caption is on the button already', '', HintOf(b));
end;

procedure TToolbarDisplayTest.AButtonWithNoIconAddsNoHint;
var
  b: TTyToolButton;
begin
  b := AddTool('&Save', False);
  b.ShowCaption := False;   // no icon: the caption is drawn regardless
  AssertEquals('its caption is drawn, so it is no hint', '', HintOf(b));
end;

initialization
  RegisterTest(TToolbarDisplayTest);
end.
