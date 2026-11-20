unit test.toolbar.display;
{$mode objfpc}{$H+}

{ How a tool bar's buttons are sized and shown in each display mode:

    #228  an icon-only button is as wide as its icon, not as its hidden caption;
    #229  an icon stacked above its caption leaves room for the caption;
    #230  ButtonHeight sizes the buttons and the separators, not only the row;
    #231  --toolbar-icon-size gives every icon button on a bar one icon size;
    #232  a caption that is not drawn serves as the hint;
    #234  --toolbar-display and the Display property: icons, text, or both, for a bar or
          for every bar, and text only;
    #235  the IconSize property is the bar's own --toolbar-icon-size;
    #238  on a bar that stacks icons over captions, a tool with no caption drawn has an
          icon of its neighbours' size.

  The icon is a painter glyph (GlyphKind), so no test here depends on a font. Sizes are read
  through the measuring methods the paint uses: LCL's AutoSize does nothing while the form
  has no handle, and the headless runner never makes one. }

interface

uses
  Classes, SysUtils, Types, Math, TypInfo, Controls, Forms, Graphics, ActnList, LCLType, LMessages,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.Painter, tyControls.IconFont,
  tyControls.Button, tyControls.GlyphButtons, tyControls.ToolBar, tyControls.ToolBarEx,
  tyControls.Edit, tyControls.ComboBox, BGRABitmap, BGRABitmapTypes;

type
  TToolbarDisplayTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FBar: TTyToolBar;
    FFloorCalls: Integer;
    function NewBar: TTyToolBar;
    function NewEx(AWidth: Integer): TTyToolBarEx;
    function AddTool(const ACaption: string; AWithIcon: Boolean = True;
      ABar: TTyCustomToolBar = nil): TTyToolButton;
    function IconBox(B: TTyGlyphButtonBase; AHeight: Integer = 0; AWidth: Integer = 0): TRect;
    function BoxText(const R: TRect): string;
    function LoadActionBar(AActionsFirst: Boolean; out AButton: TTySpeedButton): TForm;
    procedure LayoutOfTheBar(Sender: TObject);
    procedure CountFloor(Sender: TObject);
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
    procedure ACaptionDoesNotWidenAnIconOnlyButtonsFloor;
    procedure AnIconOnlyButtonOnAnActionLoadsAtItsOwnWidth;
    procedure AnIconOnlyButtonLoadsAtItsOwnWidthWhenTheActionComesLater;
    procedure AFixedWidthToolWidensForItsCaptionAndComesBack;
    procedure ASpeedButtonOfAFixedWidthDoesTheSame;
    procedure AWidthTheHostWritesMeanwhileIsKept;
    procedure AToolComesBackWhenTheIconSizeIsTakenAway;
    procedure OnTheOverflowBarAToolComesBackToo;
    procedure TheToolWhoseChangeRanThePassComesBackToo;
    procedure AWidthTheFloorClampedBetweenPassesIsStillTheBars;
    procedure AToolWiderThanItsIconComesBackToThatWidth;
    procedure ASteadyBarMeasuresNothingAgain;
    procedure AToolIsNotLeftWiderThanItWasBuilt;
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
    procedure AComboOnTheSecondRowIsCentredInItsRow;
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
    { #234 }
    procedure TextOnlyDrawsTheCaptionAndNoIcon;
    procedure TextOnlyAsksNoRoomForTheIcon;
    procedure UnderTextOnlyAToolWithoutACaptionKeepsItsIcon;
    procedure UnderTextOnlyAToolToldToHideItsCaptionKeepsItsIcon;
    procedure IconOnlyHidesTheCaptionsWhateverShowCaptionsSays;
    procedure TextBesideIconSetsBothWhateverListSays;
    procedure TextUnderIconStacksTheTools;
    procedure TheThemesDisplayReachesEveryBarAndABarsOwnWins;
    procedure AWordTheTokenDoesNotKnowIsNoDisplay;
    procedure TheDisplayWordIsReadWhateverItsCase;
    procedure AToolsOwnLayoutIsKeptUnderTheDisplay;
    procedure ASpeedButtonFollowsTextOnlyButKeepsItsLayout;
    procedure AToolJoiningLaterTakesTheDisplay;
    procedure AToolTakenOffATextOnlyBarShowsItsIconAgain;
    procedure AToolInTheOverflowFlyoutStaysTextOnly;
    procedure TheOverflowChevronKeepsItsIcon;
    procedure UnderTextOnlyTheBarsIconSizeAsksNoHeight;
    procedure TheHintFollowsTheDisplay;
    procedure AFixedWidthToolFollowsTheDisplayAndComesBack;
    procedure TextUnderIconMakesTheRowTallEnough;
    procedure DisplayFollowsTheThemeUntilSet;
    procedure SettingDisplayWritesTheBarsOwnOverride;
    procedure DisplayReadsWhatWasWrittenByHand;
    procedure SettingDisplayToWhatItShowsChangesNothing;
    procedure DisplayBackToTheThemeTakesTheDeclarationOut;
    procedure DisplayIsPublishedAndNotStored;
    { #235 }
    procedure IconSizeFollowsTheThemeUntilSet;
    procedure SettingIconSizeWritesTheBarsOwnOverride;
    procedure IconSizeNoughtSizesIconsFromTheirButtons;
    procedure IconSizeReadsWhatWasWrittenByHand;
    procedure SettingIconSizeToWhatItShowsChangesNothing;
    procedure IconSizeIsPublishedAndNotStored;
    { #238 }
    procedure OnAStackedBarAToolWithoutACaptionHasItsNeighboursIconSize;
    procedure OnAStackedBarEveryIconIsDrawnAtTheSamePlace;
    procedure OnAStackedBarAToolWithoutACaptionKeepsTheRowsHeight;
    procedure OnAnIconOnlyBarStackedIconsStillFillTheirButtons;
    procedure BesideTheirCaptionsAToolWithoutOneIsSizedAsBefore;
    procedure TheStackedRowIsToldAgainWhenTheBarChanges;
    procedure UnderTheDisplayTokenTheStackedRowIsTheSame;
    procedure OnAStackedBarAGivenIconSizeIsAnchoredAlike;
    procedure BesideItsCaptionAnIconStaysAtTheStart;
    procedure AToolWithALookOfItsOwnIsToldTheRowAtOnce;
  end;

implementation

type
  { reach the protected measuring methods and the bar's layout }
  TGlyphCrack = class(TTyGlyphButtonBase);

  { A tool whose floor update runs a layout pass of its bar on the spot -- what LCL does in a
    real window as soon as a control's constraints move. The headless runner never does. }
  TRealignTool = class(TTyToolButton)
  public
    AfterFloor: TNotifyEvent;
  protected
    procedure DoUpdateSizeConstraints; override;
  end;
  TBarCrack = class(TTyCustomToolBar);
  TExCrack = class(TTyToolBarEx);

procedure TRealignTool.DoUpdateSizeConstraints;
begin
  inherited DoUpdateSizeConstraints;
  if Assigned(AfterFloor) then AfterFloor(Self);
end;

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

{ The floor (Constraints.MinWidth) is the same measurement, and it is what overrules the
  Width a form wrote: an icon-only button that takes a long caption -- from an action, most
  often -- was pushed out to the caption's width. }
procedure TToolbarDisplayTest.ACaptionDoesNotWidenAnIconOnlyButtonsFloor;
var
  icons: TTyIconFont;
  b: TTySpeedButton;
  none, longer: Integer;
begin
  icons := TTyIconFont.Create(FForm);
  b := TTySpeedButton.Create(FForm);
  b.Controller := FCtl;
  b.Font.PixelsPerInch := 96;
  b.IconFont := icons;
  b.GlyphName := 'save';
  b.GlyphSize := 16;
  b.ShowCaption := False;
  b.Caption := '';
  b.Parent := FBar;
  b.Invalidate;
  none := b.Constraints.MinWidth;
  b.Caption := 'A rather long caption';
  longer := b.Constraints.MinWidth;
  AssertEquals('the caption does not widen an icon-only button', none, longer);
  AssertEquals('the icon and the padding', 16 + PadX(b), longer);
  b.ShowCaption := True;
  AssertTrue('with its caption shown it is wider again', b.Constraints.MinWidth > longer + 40);
  b.ShowCaption := False;
  AssertEquals('and narrow again without it', none, b.Constraints.MinWidth);
end;

{ A form as the designer writes it: an icon-only speed button, 28 wide, linked to an action
  with a long caption, on a tool bar. The properties arrive one at a time, and for a while
  the button has a caption and no icon yet, or an icon and its caption showing. None of
  those passing states may leave the button wider than the form says. }
function TToolbarDisplayTest.LoadActionBar(AActionsFirst: Boolean; out AButton: TTySpeedButton): TForm;
const
  cActions =
    '  object Acts: TActionList'#10 +
    '    object ActSave: TAction'#10 +
    '      Caption = ''Save the whole document now'''#10 +
    '    end'#10 +
    '  end'#10;
  cBar =
    '  object Icons: TTyIconFont'#10 +
    '  end'#10 +
    '  object Tools: TTyToolBar'#10 +
    '    Left = 0'#10 +
    '    Height = 36'#10 +
    '    Top = 0'#10 +
    '    Width = 600'#10 +
    '    ButtonHeight = 28'#10 +
    '    object BtnSave: TTySpeedButton'#10 +
    '      Left = 6'#10 +
    '      Height = 28'#10 +
    '      Top = 4'#10 +
    '      Width = 28'#10 +
    '      Action = ActSave'#10 +
    '      StyleClass = ''ghost'''#10 +
    '      IconFont = Icons'#10 +
    '      GlyphName = ''save'''#10 +
    '      GlyphSize = 16'#10 +
    '      ShowCaption = False'#10 +
    '    end'#10 +
    '  end'#10;
var
  txt: TStringStream;
  bin: TMemoryStream;
  body: string;
begin
  if AActionsFirst then body := cActions + cBar else body := cBar + cActions;
  Result := TForm.CreateNew(nil);
  txt := TStringStream.Create('object F: TForm'#10 + body + 'end'#10);
  bin := TMemoryStream.Create;
  try
    ObjectTextToBinary(txt, bin);
    bin.Position := 0;
    bin.ReadComponent(Result);
  finally
    bin.Free;
    txt.Free;
  end;
  AButton := Result.FindComponent('BtnSave') as TTySpeedButton;
end;

procedure TToolbarDisplayTest.AnIconOnlyButtonOnAnActionLoadsAtItsOwnWidth;
var
  f: TForm;
  b: TTySpeedButton;
begin
  f := LoadActionBar(True, b);
  try
    AssertEquals('setup: the action gave its caption', 'Save the whole document now', b.Caption);
    AssertFalse('setup: and the caption is not shown', b.ShowCaption);
    Layout(f.FindComponent('Tools') as TTyToolBar);   // what showing the form does
    AssertEquals('the width the form says, or the icon and its padding if that is more',
      Max(28, 16 + PadX(b)), b.Width);
  finally
    f.Free;
  end;
end;

procedure TToolbarDisplayTest.AnIconOnlyButtonLoadsAtItsOwnWidthWhenTheActionComesLater;
var
  f: TForm;
  b: TTySpeedButton;
begin
  f := LoadActionBar(False, b);
  try
    AssertEquals('setup: the action gave its caption', 'Save the whole document now', b.Caption);
    Layout(f.FindComponent('Tools') as TTyToolBar);   // what showing the form does
    AssertEquals('the width the form says, or the icon and its padding if that is more',
      Max(28, 16 + PadX(b)), b.Width);
  finally
    f.Free;
  end;
end;

{ A tool that is not auto-sized has the width the form gave it, and no less than what it has
  to draw. LCL applies a control's constraints only when its bounds change: with captions
  switched on over icon-only tools the floor rose and the width did not, so the captions
  were cut off -- and a width the floor had pushed up never came back down. The bar lays
  such a tool out at its floor and remembers the width it had. }
procedure TToolbarDisplayTest.AFixedWidthToolWidensForItsCaptionAndComesBack;
var
  b: TTyToolButton;
  narrow: Integer;
begin
  b := AddTool('Save all changes');
  b.Width := 10;
  Layout;
  narrow := b.Width;
  AssertEquals('setup: icon only, as wide as its floor', b.Constraints.MinWidth, narrow);
  FBar.ShowCaptions := True;
  Layout;
  AssertTrue(Format('wider for its caption (%d against %d)', [b.Width, narrow]),
    b.Width > narrow + 40);
  AssertEquals('exactly what it has to draw', b.Constraints.MinWidth, b.Width);
  FBar.ShowCaptions := False;
  Layout;
  AssertEquals('and back to the width it had', narrow, b.Width);
end;

procedure TToolbarDisplayTest.ASpeedButtonOfAFixedWidthDoesTheSame;
var
  s: TTySpeedButton;
  narrow: Integer;
begin
  s := TTySpeedButton.Create(FForm);
  s.Controller := FCtl;
  s.Font.PixelsPerInch := 96;
  s.GlyphKind := tgCheck;
  s.Parent := FBar;             // the bar's ShowCaptions = False reaches it here
  s.Caption := 'Save all changes';
  s.Width := 10;
  Layout;
  narrow := s.Width;
  AssertTrue(Format('setup: icon only, a narrow button (%d)', [narrow]), narrow < 50);
  FBar.ShowCaptions := True;
  Layout;
  AssertTrue(Format('wider for its caption (%d against %d)', [s.Width, narrow]),
    s.Width > narrow + 40);
  AssertEquals('exactly what it has to draw', s.Constraints.MinWidth, s.Width);
  FBar.ShowCaptions := False;
  Layout;
  AssertEquals('and back to the width it had', narrow, s.Width);
  FBar.ShowCaptions := True;
  Layout;
  s.Parent := nil;              // taken off the bar while it is wide: nothing is remembered
  s.Parent := FBar;
  FBar.ShowCaptions := False;
  Layout;
  AssertTrue('a button that left the bar keeps the width it left with', s.Width > narrow + 40);
end;

{ The bar re-derives a width only while it is still the one the bar lent. A width the host
  writes meanwhile is the host's, and stays. }
procedure TToolbarDisplayTest.AWidthTheHostWritesMeanwhileIsKept;
var
  b: TTyToolButton;
  s: TTySpeedButton;
begin
  b := AddTool('Save all changes');
  b.Width := 10;
  s := TTySpeedButton.Create(FForm);
  s.Controller := FCtl;
  s.Font.PixelsPerInch := 96;
  s.GlyphKind := tgCheck;
  s.Parent := FBar;
  s.Caption := 'Save all changes';
  s.Width := 10;
  Layout;
  FBar.ShowCaptions := True;
  Layout;
  b.Width := 300;
  s.Width := 310;
  FBar.ShowCaptions := False;
  Layout;
  AssertEquals('the tool keeps the width the host wrote', 300, b.Width);
  AssertEquals('and so does the speed button', 310, s.Width);
end;

{ An icon nobody sized is as tall as its box, so the width floor follows the HEIGHT. A row
  that grew for a large icon and shrank again must not leave its tools with the floor of
  the tall row. }
procedure TToolbarDisplayTest.AToolComesBackWhenTheIconSizeIsTakenAway;
var
  b: TTyToolButton;
  w, h: Integer;
begin
  b := AddTool('Save');
  b.Width := 10;
  Layout;
  w := b.Width;
  h := b.Height;
  FBar.StyleOverride := '--toolbar-icon-size: 40px;';
  Layout;
  AssertTrue(Format('setup: wider and taller for the icon (%dx%d against %dx%d)',
    [b.Width, b.Height, w, h]), (b.Width > w + 10) and (b.Height > h + 10));
  FBar.StyleOverride := '';
  Layout;
  AssertEquals('as tall as before', h, b.Height);
  AssertEquals('and as wide as before', w, b.Width);
end;

procedure TToolbarDisplayTest.OnTheOverflowBarAToolComesBackToo;
var
  ex: TTyToolBarEx;
  b: TTyToolButton;
  w, h: Integer;
begin
  ex := NewEx(700);
  b := AddTool('Save', True, ex);
  b.Width := 10;
  Layout(ex);
  w := b.Width;
  h := b.Height;
  ex.StyleOverride := '--toolbar-icon-size: 40px;';
  Layout(ex);
  AssertTrue('setup: wider and taller for the icon', (b.Width > w + 10) and (b.Height > h + 10));
  ex.StyleOverride := '';
  Layout(ex);
  AssertEquals('as tall as before', h, b.Height);
  AssertEquals('and as wide as before', w, b.Width);
  ex.ShowCaptions := True;
  Layout(ex);
  AssertEquals('wide enough for its caption', b.Constraints.MinWidth, b.Width);
  ex.ShowCaptions := False;
  Layout(ex);
  AssertEquals('and back', w, b.Width);
end;

procedure TToolbarDisplayTest.LayoutOfTheBar(Sender: TObject);
begin
  Layout;
end;

procedure TToolbarDisplayTest.CountFloor(Sender: TObject);
begin
  Inc(FFloorCalls);
end;

{ LCL applies a control's constraints whenever its bounds change, for whatever reason. A floor
  that rose is then applied by LCL before the bar's next pass -- in a real window, in the
  very pass where the row grows -- and the bar finds the button already wide. That width is
  the floor's doing, not the host's: when the floor falls the button comes back. }
procedure TToolbarDisplayTest.AWidthTheFloorClampedBetweenPassesIsStillTheBars;
var
  b: TTyToolButton;
  s: TTySpeedButton;
  wb, ws: Integer;
begin
  b := AddTool('Save all changes');
  b.Width := 10;
  s := TTySpeedButton.Create(FForm);
  s.Controller := FCtl;
  s.Font.PixelsPerInch := 96;
  s.GlyphKind := tgCheck;
  s.Parent := FBar;
  s.Caption := 'Save all changes';
  s.Width := 10;
  Layout;
  wb := b.Width;
  ws := s.Width;
  FBar.ShowCaptions := True;                              // the floors rise ...
  b.SetBounds(b.Left, b.Top + 1, b.Width, b.Height);      // ... and any change of bounds applies them
  s.SetBounds(s.Left, s.Top + 1, s.Width, s.Height);
  AssertEquals('setup: LCL clamped the tool up to its floor', b.Constraints.MinWidth, b.Width);
  AssertEquals('setup: and the speed button', s.Constraints.MinWidth, s.Width);
  AssertTrue('setup: both wider than they were', (b.Width > wb + 40) and (s.Width > ws + 40));
  Layout;
  FBar.ShowCaptions := False;
  Layout;
  AssertEquals('the tool is back at the width it had', wb, b.Width);
  AssertEquals('and so is the speed button', ws, s.Width);
end;

procedure TToolbarDisplayTest.AToolWiderThanItsIconComesBackToThatWidth;
var
  b: TTyToolButton;
begin
  b := AddTool('Save all changes and then some more');
  b.Width := 70;
  Layout;
  AssertEquals('setup: the width the form gave it, wider than its icon', 70, b.Width);
  AssertTrue('setup: its floor is under that', b.Constraints.MinWidth < 70);
  FBar.ShowCaptions := True;
  Layout;
  AssertTrue(Format('setup: wider for its caption (%d)', [b.Width]), b.Width > 110);
  FBar.ShowCaptions := False;
  Layout;
  AssertEquals('back at seventy, not at its floor', 70, b.Width);
end;

{ A tool as the constructor makes it is 23 wide; its caption and icon arrive afterwards and
  raise its floor over that without moving it. The first pass that gives it the row's height
  must not let LCL push it up to the floor unrecorded -- 23 is the width it was built with,
  and it is the width to come back to. }
procedure TToolbarDisplayTest.AToolIsNotLeftWiderThanItWasBuilt;
var
  b: TTyToolButton;
begin
  b := TTyToolButton.Create(FForm);
  b.Controller := FCtl;
  b.Font.PixelsPerInch := 96;
  b.Parent := FBar;
  b.Caption := 'Save';
  b.GlyphKind := tgCheck;
  AssertEquals('setup: still as wide as it was built', 23, b.Width);
  AssertTrue('setup: under its floor', b.Constraints.MinWidth > 23);
  FBar.ButtonHeight := 60;            // the first pass changes its height
  Layout;
  AssertEquals('setup: laid out at its floor', b.Constraints.MinWidth, b.Width);
  FBar.StyleOverride := '--toolbar-icon-size: 4px;';   // a floor under 23
  Layout;
  AssertTrue('setup: the floor is under what it was built with', b.Constraints.MinWidth < 23);
  AssertEquals('back at the width it was built with', 23, b.Width);
end;

{ Settling the row's height and measuring again is for a pass in which something moved. A
  pass over a bar that has not changed must not touch its tools: a measure invalidates, an
  invalidate lays out, and the bar would never come to rest. }
procedure TToolbarDisplayTest.ASteadyBarMeasuresNothingAgain;
var
  b: TRealignTool;
begin
  b := TRealignTool.Create(FForm);
  b.Controller := FCtl;
  b.Font.PixelsPerInch := 96;
  b.Caption := 'Save';
  b.GlyphKind := tgCheck;
  b.Parent := FBar;
  AddTool('Other');
  FBar.StyleOverride := '--toolbar-icon-size: 40px;';   // a row taller than ButtonHeight
  Layout;
  Layout;
  FFloorCalls := 0;
  b.AfterFloor := @CountFloor;
  Layout;
  b.AfterFloor := nil;
  AssertEquals('nothing changed, nothing is measured', 0, FFloorCalls);
end;

{ In a real window the pass that shrinks the row runs INSIDE the Invalidate of the tool whose
  floor just moved. That tool was measured for the tall row a moment before, and while its own
  Invalidate is under way a second one does nothing -- so it has to be measured for the new
  height some other way, or it alone stays as wide as the large icon made it. }
procedure TToolbarDisplayTest.TheToolWhoseChangeRanThePassComesBackToo;
var
  b: TRealignTool;
  w, h: Integer;
begin
  b := TRealignTool.Create(FForm);
  b.Controller := FCtl;
  b.Font.PixelsPerInch := 96;
  b.Caption := 'Save';
  b.GlyphKind := tgCheck;
  b.Parent := FBar;              // icon only from here on, as the bar says
  b.Width := 10;
  Layout;
  w := b.Width;
  h := b.Height;
  FBar.StyleOverride := '--toolbar-icon-size: 40px;';
  Layout;
  AssertTrue(Format('setup: wider and taller for the icon (%dx%d against %dx%d)',
    [b.Width, b.Height, w, h]), (b.Width > w + 10) and (b.Height > h + 10));
  b.AfterFloor := @LayoutOfTheBar;
  FBar.StyleOverride := '';      // the bar tells the tool; the tool's floor moves; the pass runs
  b.AfterFloor := nil;
  AssertEquals('as tall as before', h, b.Height);
  AssertEquals('and as wide as before', w, b.Width);
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

{ The same on a bar that wraps: a combo box on the second row keeps its own height and sits
  on that row's centre line, beside a button that fills the row. }
procedure TToolbarDisplayTest.AComboOnTheSecondRowIsCentredInItsRow;
var
  first, last, beside: TTyToolButton;
  combo: TTyComboBox;
  h: Integer;
begin
  first := AddTool('One');
  last := AddTool('Two');
  last.Wrap := True;                 // the row ends after this tool
  combo := TTyComboBox.Create(FForm);
  combo.Controller := FCtl;
  combo.Font.PixelsPerInch := 96;
  combo.Parent := FBar;
  combo.Width := 90;
  beside := AddTool('Three');
  FBar.ButtonHeight := 24;
  Layout;
  h := combo.Height;                 // what it is in a row no taller than itself

  FBar.ButtonHeight := h + 20;
  Layout;
  AssertTrue('setup: the combo is on a second row', combo.Top > first.Top + first.Height);
  AssertEquals('setup: with a button beside it', combo.Top - 10, beside.Top);
  AssertEquals('the button fills the row', h + 20, beside.Height);
  AssertEquals('the combo keeps its own height', h, combo.Height);
  AssertEquals('both rows are as tall', first.Height, beside.Height);
  AssertEquals('and the second row starts a row and the spacing below the first',
    first.Top + first.Height + FBar.ButtonSpacing, beside.Top);
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

{ ---- #234: one display for a bar (--toolbar-display, Display), and text only ---- }

procedure TToolbarDisplayTest.TextOnlyDrawsTheCaptionAndNoIcon;
var
  b: TTyToolButton;
begin
  b := AddTool('Save');
  b.Height := 24;
  AssertFalse('setup: the icon is drawn', IsRectEmpty(IconBox(b)));
  FBar.StyleOverride := '--toolbar-display: text;';
  AssertTrue('no icon is drawn: ' + BoxText(IconBox(b)), IsRectEmpty(IconBox(b)));
  AssertTrue('the caption shows, though ShowCaptions is off', b.ShowCaption);
  AssertFalse('and ShowCaptions itself was not written', FBar.ShowCaptions);
end;

procedure TToolbarDisplayTest.TextOnlyAsksNoRoomForTheIcon;
var
  b, plain: TTyToolButton;
begin
  b := AddTool('Save all changes');
  plain := AddTool('Save all changes', False);
  b.Height := 24;
  plain.Height := 24;
  FBar.ShowCaptions := True;
  AssertTrue('setup: the icon is paid for', PrefW(b) > PrefW(plain));
  FBar.StyleOverride := '--toolbar-display: text;';
  AssertEquals('as wide as a tool that never had an icon', PrefW(plain), PrefW(b));
end;

{ Text only trades an icon for a caption. With no caption to show there is nothing to trade
  it for, and the tool would be an empty box. }
procedure TToolbarDisplayTest.UnderTextOnlyAToolWithoutACaptionKeepsItsIcon;
var
  b: TTyToolButton;
begin
  b := AddTool('');
  b.Height := 24;
  FBar.StyleOverride := '--toolbar-display: text;';
  AssertFalse('nothing else to show: the icon stays', IsRectEmpty(IconBox(b)));
end;

procedure TToolbarDisplayTest.UnderTextOnlyAToolToldToHideItsCaptionKeepsItsIcon;
var
  told, other: TTyToolButton;
begin
  told := AddTool('Save');
  other := AddTool('Open');
  told.Height := 24;
  other.Height := 24;
  told.ShowCaption := False;   // the host's own word for this tool
  FBar.StyleOverride := '--toolbar-display: text;';
  AssertFalse('the tool keeps what it was told', told.ShowCaption);
  AssertFalse('and so stays an icon', IsRectEmpty(IconBox(told)));
  AssertTrue('its neighbour is text only', IsRectEmpty(IconBox(other)));
end;

procedure TToolbarDisplayTest.IconOnlyHidesTheCaptionsWhateverShowCaptionsSays;
var
  b: TTyToolButton;
begin
  b := AddTool('Save');
  b.Height := 24;
  FBar.ShowCaptions := True;
  AssertTrue('setup: the caption shows', b.ShowCaption);
  FBar.StyleOverride := '--toolbar-display: icon;';
  AssertFalse('the token decides', b.ShowCaption);
  AssertTrue('the property keeps what it was given', FBar.ShowCaptions);
  AssertFalse('the icon is drawn', IsRectEmpty(IconBox(b)));
  FBar.StyleOverride := '';
  AssertTrue('taken away: ShowCaptions decides again', b.ShowCaption);
end;

procedure TToolbarDisplayTest.TextBesideIconSetsBothWhateverListSays;
var
  b: TTyToolButton;
begin
  b := AddTool('Save');
  b.Height := 24;
  FBar.List := False;
  AssertEquals('setup: stacked', Ord(glTop), Ord(b.GlyphLayout));
  AssertFalse('setup: no caption', b.ShowCaption);
  FBar.StyleOverride := '--toolbar-display: text-beside-icon;';
  AssertTrue('the caption shows', b.ShowCaption);
  AssertEquals('beside its icon', Ord(glLeft), Ord(b.GlyphLayout));
  AssertFalse('which is drawn', IsRectEmpty(IconBox(b)));
  AssertFalse('List keeps what it was given', FBar.List);
  FBar.StyleOverride := '';
  AssertFalse('taken away: ShowCaptions', b.ShowCaption);
  AssertEquals('and List', Ord(glTop), Ord(b.GlyphLayout));
end;

procedure TToolbarDisplayTest.TextUnderIconStacksTheTools;
var
  b: TTyToolButton;
begin
  b := AddTool('Save');
  AssertEquals('setup: beside', Ord(glLeft), Ord(b.GlyphLayout));
  FBar.StyleOverride := '--toolbar-display: text-under-icon;';
  AssertTrue('the caption shows', b.ShowCaption);
  AssertEquals('under its icon', Ord(glTop), Ord(b.GlyphLayout));
  b.Height := 48;
  AssertFalse('which is drawn', IsRectEmpty(IconBox(b)));
  AssertTrue('List keeps what it was given', FBar.List);
end;

procedure TToolbarDisplayTest.TheThemesDisplayReachesEveryBarAndABarsOwnWins;
var
  here, there: TTyToolButton;
  second: TTyToolBar;
begin
  here := AddTool('One');
  second := NewBar;
  there := AddTool('Two', True, second);
  FCtl.StyleOverride := ':root { --toolbar-display: text-under-icon; }';
  AssertTrue('this bar', here.ShowCaption);
  AssertEquals('this bar, stacked', Ord(glTop), Ord(here.GlyphLayout));
  AssertTrue('the other bar', there.ShowCaption);
  AssertEquals('the other bar, stacked', Ord(glTop), Ord(there.GlyphLayout));
  FBar.StyleOverride := '--toolbar-display: icon;';
  AssertFalse('the bar that says so', here.ShowCaption);
  AssertTrue('the other bar keeps the theme''s', there.ShowCaption);
  FBar.StyleOverride := '';
  AssertTrue('taken away: the theme''s again', here.ShowCaption);
  FCtl.StyleOverride := '';
  AssertFalse('no token anywhere: ShowCaptions', here.ShowCaption);
  AssertEquals('and List', Ord(glLeft), Ord(here.GlyphLayout));
end;

procedure TToolbarDisplayTest.AWordTheTokenDoesNotKnowIsNoDisplay;
var
  b: TTyToolButton;
begin
  b := AddTool('Save');
  b.Height := 24;
  FBar.ShowCaptions := True;
  FBar.StyleOverride := '--toolbar-display: sideways;';
  AssertTrue('ShowCaptions still decides', b.ShowCaption);
  AssertFalse('and the icon is drawn', IsRectEmpty(IconBox(b)));
  AssertEquals('the property shows no display', Ord(tbdTheme), Ord(FBar.Display));
end;

procedure TToolbarDisplayTest.TheDisplayWordIsReadWhateverItsCase;
var
  b: TTyToolButton;
begin
  b := AddTool('Save');
  b.Height := 24;
  FBar.StyleOverride := '--toolbar-display:  TEXT ;';
  AssertTrue('text only', IsRectEmpty(IconBox(b)));
  FBar.StyleOverride := '--toolbar-display: Text-Under-Icon;';
  AssertEquals('stacked', Ord(glTop), Ord(b.GlyphLayout));
end;

procedure TToolbarDisplayTest.AToolsOwnLayoutIsKeptUnderTheDisplay;
var
  own, other: TTyToolButton;
begin
  own := AddTool('One');
  other := AddTool('Two');
  own.GlyphLayout := glRight;
  FBar.StyleOverride := '--toolbar-display: text-under-icon;';
  AssertEquals('the layout the tool was given', Ord(glRight), Ord(own.GlyphLayout));
  AssertEquals('its neighbour takes the bar''s', Ord(glTop), Ord(other.GlyphLayout));
end;

{ Beside or under reaches tool buttons only, as List does. Whether the icon and the caption
  show reaches every icon button on the bar. }
procedure TToolbarDisplayTest.ASpeedButtonFollowsTextOnlyButKeepsItsLayout;
var
  speed: TTySpeedButton;
  before: TTyGlyphLayout;
begin
  speed := TTySpeedButton.Create(FForm);
  speed.Controller := FCtl;
  speed.Font.PixelsPerInch := 96;
  speed.GlyphKind := tgCheck;
  TGlyphCrack(speed).Caption := 'Go';
  speed.SetBounds(0, 0, 60, 24);
  speed.Parent := FBar;
  before := TGlyphCrack(speed).GlyphLayout;
  AssertFalse('setup: the layout a stacked bar would not give', before = glTop);
  FBar.StyleOverride := '--toolbar-display: text-under-icon;';
  AssertTrue('captions reach it', TGlyphCrack(speed).ShowCaption);
  AssertEquals('its layout is its own', Ord(before), Ord(TGlyphCrack(speed).GlyphLayout));
  AssertFalse('setup: its icon is drawn', IsRectEmpty(IconBox(speed)));
  FBar.StyleOverride := '--toolbar-display: text;';
  AssertTrue('text only reaches it', IsRectEmpty(IconBox(speed)));
end;

procedure TToolbarDisplayTest.AToolJoiningLaterTakesTheDisplay;
var
  b: TTyToolButton;
begin
  FBar.StyleOverride := '--toolbar-display: text;';
  b := AddTool('Save');
  b.Height := 24;
  AssertTrue('its caption shows', b.ShowCaption);
  AssertTrue('and no icon', IsRectEmpty(IconBox(b)));
end;

procedure TToolbarDisplayTest.AToolTakenOffATextOnlyBarShowsItsIconAgain;
var
  b: TTyToolButton;
begin
  FBar.StyleOverride := '--toolbar-display: text;';
  b := AddTool('Save');
  b.Height := 24;
  AssertTrue('setup: text only on the bar', IsRectEmpty(IconBox(b)));
  b.Parent := FForm;
  AssertFalse('on the form it is an icon button again', IsRectEmpty(IconBox(b)));
end;

procedure TToolbarDisplayTest.AToolInTheOverflowFlyoutStaysTextOnly;
var
  ex: TTyToolBarEx;
  b: TTyToolButton;
begin
  ex := NewEx(700);
  b := AddTool('Save', True, ex);
  b.Height := 24;
  ex.StyleOverride := '--toolbar-display: text;';
  AssertTrue('on the bar', IsRectEmpty(IconBox(b)));
  b.Parent := TExCrack(ex).EnsureFlyout;   // what opening the flyout does to an overflowed tool
  try
    AssertTrue('in the flyout', IsRectEmpty(IconBox(b)));
  finally
    b.Parent := ex;
  end;
end;

procedure TToolbarDisplayTest.TheOverflowChevronKeepsItsIcon;
var
  ex: TTyToolBarEx;
  chevron: TTyGlyphButtonBase;
  i: Integer;
begin
  ex := NewEx(130);
  for i := 1 to 5 do AddTool('Tool', True, ex);
  ex.StyleOverride := '--toolbar-display: text;';
  Layout(ex);
  AssertTrue('setup: the bar overflows', ex.OverflowVisible);
  chevron := nil;
  for i := 0 to ex.ControlCount - 1 do
    if ex.Controls[i] is TTyGlyphButton then chevron := TTyGlyphButtonBase(ex.Controls[i]);
  AssertNotNull('setup: the chevron', chevron);
  AssertFalse('the chevron is still drawn', IsRectEmpty(IconBox(chevron)));
end;

procedure TToolbarDisplayTest.UnderTextOnlyTheBarsIconSizeAsksNoHeight;
var
  b, plain: TTyToolButton;
begin
  b := AddTool('Save');
  plain := AddTool('Save', False);
  FBar.StyleOverride := '--toolbar-icon-size: 40px;';
  AssertTrue('setup: a large icon makes its tool taller', Floor(b) > Floor(plain));
  FBar.StyleOverride := '--toolbar-icon-size: 40px; --toolbar-display: text;';
  AssertEquals('an icon that is not drawn asks for nothing', Floor(plain), Floor(b));
end;

procedure TToolbarDisplayTest.TheHintFollowsTheDisplay;
var
  b: TTyToolButton;
begin
  b := AddTool('&Save');
  FBar.ShowCaptions := True;
  AssertEquals('setup: the caption is on the button', '', HintOf(b));
  FBar.StyleOverride := '--toolbar-display: icon;';
  AssertEquals('icons only: the caption is the hint', 'Save', HintOf(b));
  FBar.StyleOverride := '--toolbar-display: text;';
  AssertEquals('text only: it is on the button', '', HintOf(b));
end;

{ The display goes through the bar's layout the way ShowCaptions does: a tool of a fixed
  width is laid out as wide as what it now draws, and comes back to its own width. }
procedure TToolbarDisplayTest.AFixedWidthToolFollowsTheDisplayAndComesBack;
var
  b, plain: TTyToolButton;
  narrow: Integer;
begin
  b := AddTool('Save all changes');
  plain := AddTool('Save all changes', False);
  b.Width := 10;
  plain.Width := 10;
  Layout;
  narrow := b.Width;
  AssertEquals('setup: icon only, as wide as its floor', b.Constraints.MinWidth, narrow);
  FBar.Display := tbdTextBesideIcon;
  Layout;
  AssertTrue(Format('wider for its caption (%d against %d)', [b.Width, narrow]),
    b.Width > narrow + 40);
  AssertTrue(Format('and the icon beside it is paid for (%d against %d)', [b.Width, plain.Width]),
    b.Width > plain.Width);
  FBar.Display := tbdTextOnly;
  Layout;
  AssertEquals('text only: as wide as the tool that has no icon', plain.Width, b.Width);
  FBar.Display := tbdTheme;
  Layout;
  AssertEquals('and back to the width it had', narrow, b.Width);
end;

procedure TToolbarDisplayTest.TextUnderIconMakesTheRowTallEnough;
var
  b: TTyToolButton;
  low: Integer;
begin
  b := AddTool('Save');
  Layout;
  low := b.Height;
  FBar.Display := tbdTextUnderIcon;
  Layout;
  AssertTrue(Format('the row grew for the icon over its caption (%d against %d)', [b.Height, low]),
    b.Height > low);
  AssertTrue('to what the tool has to draw', b.Height >= Floor(b) + PadY(b));
  FBar.Display := tbdTheme;
  Layout;
  AssertEquals('and back', low, b.Height);
end;

{ ---- #234: the Display property is the bar's own --toolbar-display ---- }

procedure TToolbarDisplayTest.DisplayFollowsTheThemeUntilSet;
begin
  AssertEquals('a new bar', Ord(tbdTheme), Ord(FBar.Display));
  FCtl.StyleOverride := ':root { --toolbar-display: text; }';
  AssertEquals('the theme''s word is not this bar''s own', Ord(tbdTheme), Ord(FBar.Display));
end;

procedure TToolbarDisplayTest.SettingDisplayWritesTheBarsOwnOverride;
var
  b: TTyToolButton;
begin
  b := AddTool('Save');
  b.Height := 24;
  FBar.StyleOverride := 'color: #FF0000;';
  FBar.Display := tbdTextOnly;
  AssertEquals('color: #FF0000; --toolbar-display: text;', FBar.StyleOverride);
  AssertTrue('and the tools follow', IsRectEmpty(IconBox(b)));
  FBar.Display := tbdIconOnly;
  AssertEquals('color: #FF0000; --toolbar-display: icon;', FBar.StyleOverride);
  AssertFalse('icon only', b.ShowCaption);
  FBar.Display := tbdTextBesideIcon;
  AssertEquals('color: #FF0000; --toolbar-display: text-beside-icon;', FBar.StyleOverride);
  FBar.Display := tbdTextUnderIcon;
  AssertEquals('color: #FF0000; --toolbar-display: text-under-icon;', FBar.StyleOverride);
  AssertEquals('stacked', Ord(glTop), Ord(b.GlyphLayout));
end;

procedure TToolbarDisplayTest.DisplayReadsWhatWasWrittenByHand;
begin
  FBar.StyleOverride := '--toolbar-display: icon;';
  AssertEquals('icon', Ord(tbdIconOnly), Ord(FBar.Display));
  FBar.StyleOverride := '--toolbar-display: text;';
  AssertEquals('text', Ord(tbdTextOnly), Ord(FBar.Display));
  FBar.StyleOverride := '--toolbar-display: text-beside-icon;';
  AssertEquals('text-beside-icon', Ord(tbdTextBesideIcon), Ord(FBar.Display));
  FBar.StyleOverride := '--toolbar-display: text-under-icon;';
  AssertEquals('text-under-icon', Ord(tbdTextUnderIcon), Ord(FBar.Display));
  FCtl.StyleOverride := ':root { --mode: text; }';
  FBar.StyleOverride := '--toolbar-display: var(--mode);';
  AssertEquals('through a var()', Ord(tbdTextOnly), Ord(FBar.Display));
end;

{ The Object Inspector, a copy and Assign all set a property to the value it already shows.
  That must not rewrite what was written by hand. }
procedure TToolbarDisplayTest.SettingDisplayToWhatItShowsChangesNothing;
const
  S = '--toolbar-display:  TEXT ;';
begin
  FBar.StyleOverride := S;
  FBar.Display := tbdTextOnly;
  AssertEquals(S, FBar.StyleOverride);
end;

procedure TToolbarDisplayTest.DisplayBackToTheThemeTakesTheDeclarationOut;
begin
  FBar.StyleOverride := 'color: #FF0000; --toolbar-display: text;';
  FBar.Display := tbdTheme;
  AssertEquals('color: #FF0000;', FBar.StyleOverride);
  AssertEquals(Ord(tbdTheme), Ord(FBar.Display));
end;

procedure TToolbarDisplayTest.DisplayIsPublishedAndNotStored;
var
  ex: TTyToolBarEx;
begin
  AssertNotNull('TTyToolBar', GetPropInfo(FBar, 'Display'));
  FBar.Display := tbdTextOnly;
  AssertFalse('only StyleOverride goes into the form file', IsStoredProp(FBar, 'Display'));
  ex := NewEx(300);
  AssertNotNull('TTyToolBarEx', GetPropInfo(ex, 'Display'));
  ex.Display := tbdTextOnly;
  AssertFalse('nor on the overflow bar', IsStoredProp(ex, 'Display'));
end;

{ ---- #235: the IconSize property is the bar's own --toolbar-icon-size ---- }

procedure TToolbarDisplayTest.IconSizeFollowsTheThemeUntilSet;
begin
  AssertEquals('a new bar', -1, FBar.IconSize);
  FCtl.StyleOverride := ':root { --toolbar-icon-size: 20px; }';
  AssertEquals('the theme''s size is not this bar''s own', -1, FBar.IconSize);
end;

procedure TToolbarDisplayTest.SettingIconSizeWritesTheBarsOwnOverride;
var
  b: TTyToolButton;
begin
  b := AddTool('Save');
  b.Height := 40;
  FBar.IconSize := 24;
  AssertEquals('--toolbar-icon-size: 24px;', FBar.StyleOverride);
  AssertEquals('and the tools follow', 24, Slot(b));
  AssertEquals(24, FBar.IconSize);
  FBar.IconSize := -1;
  AssertEquals('taken out', '', FBar.StyleOverride);
  FBar.IconSize := 24;
  FBar.IconSize := -7;
  AssertEquals('any negative number takes it out', '', FBar.StyleOverride);
  AssertEquals(-1, FBar.IconSize);
end;

{ 0 is a size of its own: this bar's icons are sized from their buttons, whatever the theme
  gives the other bars. }
procedure TToolbarDisplayTest.IconSizeNoughtSizesIconsFromTheirButtons;
var
  b: TTyToolButton;
begin
  b := AddTool('Save');
  b.ShowCaption := False;
  b.Height := 40;
  FCtl.StyleOverride := ':root { --toolbar-icon-size: 20px; }';
  AssertEquals('setup: the theme''s size', 20, Slot(b));
  FBar.IconSize := 0;
  AssertEquals('--toolbar-icon-size: 0px;', FBar.StyleOverride);
  AssertEquals('the box again', b.ClientHeight - PadY(b), Slot(b));
  AssertEquals(0, FBar.IconSize);
end;

procedure TToolbarDisplayTest.IconSizeReadsWhatWasWrittenByHand;
begin
  FBar.StyleOverride := '--toolbar-icon-size: 28px;';
  AssertEquals(28, FBar.IconSize);
  FCtl.StyleOverride := ':root { --big: 32px; }';
  FBar.StyleOverride := '--toolbar-icon-size: var(--big);';
  AssertEquals('through a var()', 32, FBar.IconSize);
end;

procedure TToolbarDisplayTest.SettingIconSizeToWhatItShowsChangesNothing;
const
  S = '--toolbar-icon-size:var(--big);';
begin
  FCtl.StyleOverride := ':root { --big: 32px; }';
  FBar.StyleOverride := S;
  FBar.IconSize := 32;
  AssertEquals(S, FBar.StyleOverride);
end;

procedure TToolbarDisplayTest.IconSizeIsPublishedAndNotStored;
var
  ex: TTyToolBarEx;
begin
  AssertNotNull('TTyToolBar', GetPropInfo(FBar, 'IconSize'));
  FBar.IconSize := 24;
  AssertFalse('only StyleOverride goes into the form file', IsStoredProp(FBar, 'IconSize'));
  ex := NewEx(300);
  AssertNotNull('TTyToolBarEx', GetPropInfo(ex, 'IconSize'));
  ex.IconSize := 24;
  AssertFalse('nor on the overflow bar', IsStoredProp(ex, 'IconSize'));
end;

{ ---- #238: on a bar that stacks icons over captions, every icon is one size ---- }

procedure TToolbarDisplayTest.OnAStackedBarAToolWithoutACaptionHasItsNeighboursIconSize;
var
  a, none, hidden: TTyToolButton;
begin
  FBar.ShowCaptions := True;
  FBar.List := False;
  FBar.ButtonHeight := 70;
  a := AddTool('Save');
  none := AddTool('');
  hidden := AddTool('Pin');
  hidden.ShowCaption := False;   // the host's own word for this tool
  Layout;
  AssertTrue('setup: the row holds more than the least icon', Slot(a) > TyGlyphStackedMin);
  AssertTrue('setup: and less than the whole button', Slot(a) < a.ClientHeight - PadY(a));
  AssertEquals('a tool with no caption', Slot(a), Slot(none));
  AssertEquals('a tool whose caption its host hid', Slot(a), Slot(hidden));
end;

procedure TToolbarDisplayTest.OnAStackedBarEveryIconIsDrawnAtTheSamePlace;
var
  a, none, hidden: TTyToolButton;
  boxA, boxNone, boxHidden: TRect;
begin
  FBar.ShowCaptions := True;
  FBar.List := False;
  FBar.ButtonHeight := 70;
  a := AddTool('Save');
  none := AddTool('');
  hidden := AddTool('Pin');
  hidden.ShowCaption := False;
  Layout;
  boxA := IconBox(a);
  boxNone := IconBox(none);
  boxHidden := IconBox(hidden);
  AssertFalse('setup: an icon is drawn', IsRectEmpty(boxA));
  AssertEquals('no caption: as tall as its neighbour''s', boxA.Bottom - boxA.Top,
    boxNone.Bottom - boxNone.Top);
  AssertEquals('no caption: at the same height in the row', boxA.Top, boxNone.Top);
  AssertEquals('hidden caption: as tall', boxA.Bottom - boxA.Top, boxHidden.Bottom - boxHidden.Top);
  AssertEquals('hidden caption: at the same height', boxA.Top, boxHidden.Top);
end;

{ The caption's line is kept for a tool that has no caption, so a row of such tools is as
  tall as one with captions and the icons do not move when a caption comes or goes. }
procedure TToolbarDisplayTest.OnAStackedBarAToolWithoutACaptionKeepsTheRowsHeight;
var
  a, none: TTyToolButton;
begin
  FBar.ShowCaptions := True;
  FBar.List := False;
  a := AddTool('Save');
  none := AddTool('');
  AssertEquals(Floor(a), Floor(none));
end;

procedure TToolbarDisplayTest.OnAnIconOnlyBarStackedIconsStillFillTheirButtons;
var
  b: TTyToolButton;
  beside: Integer;
begin
  FBar.ShowCaptions := False;
  b := AddTool('Save');
  b.Height := 40;
  beside := Floor(b);
  FBar.List := False;
  b.Height := 40;
  AssertEquals('setup: the tool is stacked', Ord(glTop), Ord(b.GlyphLayout));
  AssertEquals('stacked, but no captions on the bar: the icon is the box',
    b.ClientHeight - PadY(b), Slot(b));
  AssertEquals('and it owes no caption line: the floor it had', beside, Floor(b));
end;

procedure TToolbarDisplayTest.BesideTheirCaptionsAToolWithoutOneIsSizedAsBefore;
var
  none: TTyToolButton;
begin
  FBar.ShowCaptions := True;   // List stays True: beside
  none := AddTool('');
  none.GlyphLayout := glTop;   // stacked by its own choice, on a bar that is not
  none.Height := 40;
  AssertEquals('the icon is the box', none.ClientHeight - PadY(none), Slot(none));
end;

procedure TToolbarDisplayTest.TheStackedRowIsToldAgainWhenTheBarChanges;
var
  a, none: TTyToolButton;
begin
  a := AddTool('Save');
  none := AddTool('');
  none.Height := 70;
  AssertEquals('setup: icons only, the icon is the box', none.ClientHeight - PadY(none), Slot(none));
  FBar.ShowCaptions := True;
  FBar.List := False;
  a.Height := 70;
  none.Height := 70;
  AssertEquals('stacked over captions: its neighbour''s size', Slot(a), Slot(none));
  FBar.List := True;
  none.Height := 70;
  AssertEquals('beside again: the box', none.ClientHeight - PadY(none), Slot(none));
  FBar.List := False;
  FBar.ShowCaptions := False;
  none.Height := 70;
  AssertEquals('captions off again: the box', none.ClientHeight - PadY(none), Slot(none));
end;

procedure TToolbarDisplayTest.UnderTheDisplayTokenTheStackedRowIsTheSame;
var
  a, none: TTyToolButton;
begin
  a := AddTool('Save');
  none := AddTool('');
  FBar.Display := tbdTextUnderIcon;
  a.Height := 70;
  none.Height := 70;
  AssertTrue('setup: less than the whole button', Slot(a) < a.ClientHeight - PadY(a));
  AssertEquals('text under icon: its neighbour''s size', Slot(a), Slot(none));
  FBar.Display := tbdTextBesideIcon;
  none.Height := 70;
  AssertEquals('text beside icon: the box', none.ClientHeight - PadY(none), Slot(none));
  FBar.Display := tbdTextUnderIcon;
  FBar.Display := tbdIconOnly;
  none.Height := 70;
  AssertEquals('icons only: the box', none.ClientHeight - PadY(none), Slot(none));
end;

{ A size that was given is the size; what the stacked row adds is the place: over where the
  caption would be, as on its neighbours, not in the middle of the button. }
procedure TToolbarDisplayTest.OnAStackedBarAGivenIconSizeIsAnchoredAlike;
var
  a, hidden: TTyToolButton;
begin
  FBar.ShowCaptions := True;
  FBar.List := False;
  FBar.StyleOverride := '--toolbar-icon-size: 20px;';
  a := AddTool('Save');
  hidden := AddTool('Pin');
  hidden.ShowCaption := False;
  Layout;
  AssertEquals('the given size', 20, Slot(hidden));
  AssertEquals('at its neighbour''s height in the row', IconBox(a).Top, IconBox(hidden).Top);
end;

{ The split of #238 is for stacked buttons. Beside its caption an icon stays at the side the
  caption starts at, and is not centred as on an icon-only button. }
procedure TToolbarDisplayTest.BesideItsCaptionAnIconStaysAtTheStart;
var
  t: TTyToolButton;
  box: TRect;
begin
  FBar.ShowCaptions := True;
  t := AddTool('Save');
  t.SetBounds(0, 0, 200, 30);
  box := IconBox(t);
  AssertFalse('setup: an icon is drawn', IsRectEmpty(box));
  AssertTrue(Format('in the first quarter of the button (%s)', [BoxText(box)]), box.Right < 50);
end;

{ A tool that wrote its own ShowCaption and GlyphLayout takes neither from the bar, so the
  row flag is the ONLY thing that reaches it when the bar turns its captions on. Its floor
  has to move then and there: the bar lays out by it, and nothing else will repaint the tool. }
procedure TToolbarDisplayTest.AToolWithALookOfItsOwnIsToldTheRowAtOnce;
var
  b: TTyToolButton;
  alone: Integer;
begin
  FBar.List := False;
  b := AddTool('Save');
  b.GlyphLayout := glTop;
  b.ShowCaption := False;
  alone := b.Constraints.MinHeight;
  FBar.ShowCaptions := True;
  AssertTrue(Format('the caption''s line is in its floor at once (%d against %d)',
    [b.Constraints.MinHeight, alone]), b.Constraints.MinHeight > alone + 8);
  FBar.ShowCaptions := False;
  AssertEquals('and out of it again', alone, b.Constraints.MinHeight);
end;

initialization
  RegisterTest(TToolbarDisplayTest);
  { the .lfm text of LoadActionBar names these }
  RegisterClasses([TTyToolBar, TTySpeedButton, TTyIconFont, TActionList, TAction]);
end.
