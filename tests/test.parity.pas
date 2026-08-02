unit test.parity;
{$mode objfpc}{$H+}
{ Guards for the semantic gaps found by diffing each control against its Delphi/LCL
  counterpart. Each test names the finding it pins, and each one was watched go RED
  against the code as it shipped -- a guard nobody saw fail guards nothing.

  What they have in common: every one of these is a method that ran, returned, and did
  nothing, or did it to the wrong object. None of them raised, none of them logged, and
  none of them would show up in a screenshot. That is why they survived so long. }
interface
uses
  Classes, SysUtils, TypInfo, Types, Graphics, Controls, StdCtrls, Menus, LCLType, LCLProc,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Button, tyControls.GlyphButtons, tyControls.ListBox,
  tyControls.CheckGroup, tyControls.ToolBar, tyControls.StatusBar,
  tyControls.ColorBox, tyControls.SpinEdit, tyControls.CheckBox, tyControls.Menu,
  tyControls.UpDown, tyControls.TrackBar, tyControls.Base, tyControls.Panel,
  tyControls.MaskEdit, tyControls.Calendar, tyControls.ColorButton,
  tyControls.HeaderControl, tyControls.ComboBox, tyControls.Edit, tyControls.Memo,
  tyControls.DateTimePicker, tyControls.Splitter,
  tyControls.ShellTreeView, tyControls.ShellListView, tyControls.TreeView,
  tyControls.Image, tyControls.TabSheet, tyControls.Divider, tyControls.Gauge,
  tyControls.PageControl, tyControls.ColorListBox, tyControls.RadioGroup,
  tyControls.ScrollBox;

type
  { Probes: ApplyToButton and the hosted checkboxes are protected, because the owning
    control manages both. A descendant is the sanctioned way in. }
  TToolBarProbe = class(TTyToolBar)
  public
    procedure ProbeApply(B: TTyButton);
  end;

  TCheckGroupProbe = class(TTyCheckGroup)
  public
    { Do to the child exactly what a mouse click does -- go through its own Checked. }
    procedure ProbeClick(AIndex: Integer; AValue: Boolean);
  end;

  TMaskProbe = class(TTyMaskEdit)
  public
    { The exact path a Ctrl+V takes: InjectStringAt -> FilterInsert. }
    procedure ProbePaste(const S: string);
  end;

  { TControl.Text is protected, and it is exactly the string these tests are about: the
    one TControl itself, action links and accessibility read. A descendant is the way in. }
  TPanelTextProbe = class(TTyPanel)
  public
    function ProbeText: string;
    procedure SetProbeText(const S: string);
  end;

  TTabTextProbe = class(TTyTabSheet)
  public
    function ProbeText: string;
  end;

  TDividerTextProbe = class(TTyDivider)
  public
    function ProbeText: string;
  end;

  { ContentHost is protected: the viewport is the box's own business, and content is
    parented to it deliberately (the TTyPageControl shape). A probe is how a test reaches it. }
  TScrollBoxProbe = class(TTyScrollBox)
  public
    function ProbeHost: TWinControl;
  end;

  TShellTreeProbe = class(TTyShellTreeView)
  public
    { GetNodeSearchText is protected -- it is the main-column text obtained exactly the
      way the caption is, so it is what "what does this node display" means here. }
    function ProbeText(Node: PTyTreeNode): string;
  end;

  TDtpProbe = class(TTyDateTimePicker)
  public
    procedure ProbeChar(C: Char);
    procedure ProbeKey(K: Word);
  end;

  TUpDownProbe = class(TTyUpDown)
  public
    procedure ProbeDown(X, Y: Integer);
    procedure ProbeUp(X, Y: Integer);
  end;

  TParityTest = class(TTestCase)
  private
    FItemEvents: Integer;
    FPopups: Integer;
    FArrows: string;
    FTopClicks: Integer;
    FGetTextCalls: Integer;
    FColourChanges: Integer;
    procedure CountColourChange(Sender: TObject);
    procedure CountTopClick(Sender: TObject);
    procedure CountGetText(Sender: TTyTreeView; Node: PTyTreeNode; var AText: string);
    procedure CountItemChange(Sender: TObject; AIndex: Integer);
    procedure CountPopup(Sender: TObject);
    procedure RecordArrow(Sender: TObject; AButton: TTyUpDownButton);
  published
    { A2 }
    procedure SpeedButtonDownFromCodeReleasesSiblings;
    procedure SpeedButtonRadioCannotBeReleasedByHand;
    { A14 }
    procedure ListBoxSelectedFalseDeselectsInSingleMode;
    procedure ListBoxClearSelectionWorksInSingleMode;
    { A22 }
    procedure CheckGroupProgrammaticWriteIsSilent;
    procedure CheckGroupUserClickStillFires;
    { A24 }
    procedure ToolBarKeepsACallersStyleClass;
    procedure ToolBarStillGhostsAnUnstyledButton;
    { A25 }
    procedure StatusBarLastPanelReachesTheEdge;
    { A34 }
    procedure ColorBoxUnknownColourDoesNotGrowTheList;
    procedure ColorBoxKnownColourStillSelects;
    { A10 }
    procedure SpinEditEmptyRangeMeansUnbounded;
    procedure SpinEditRealRangeStillClamps;
    { A32 }
    procedure PopupMenuFiresOnPopup;
    procedure PopupMenuRecordsThePopupPoint;
    { A4 }
    procedure UpDownArrowClickSaysWhichArrow;
    { A27 }
    procedure TrackBarShowsTicksOutOfTheBox;
    { B1 }
    procedure VisibleIsPublishedOnBothBaseClasses;
    { A7 }
    procedure MaskEditPasteGoesThroughTheMask;
    procedure MaskEditPasteKeepsOnlyWhatFits;
    { A31 }
    procedure CalendarAcceptsTheLclPropertyName;
    { A8 }
    procedure MaskEditAcceptsTheLclPropertyName;
    { A1 }
    procedure ColorButtonPaintsItsCaption;
    procedure ColorButtonCaptionOutranksTheHex;
    { A18 }
    procedure HeaderEffectiveWidthTellsTheTruthAboutTheLastSection;
    { B2 -- the family-wide drag / tilt-wheel surface }
    procedure DragAndWheelSurfaceIsPublishedOnBothBaseClasses;
    { B3 -- the control-level list API }
    procedure ListBoxClearTakesTheSelectionDownWithIt;
    procedure ListBoxItemRectIsTheInverseOfTheHitTest;
    procedure ListBoxDeleteSelectedGoesBackToFront;
    procedure ListBoxSelectRangeAndSelectedText;
    procedure ComboBoxClearAlsoBlanksTheText;
    procedure EditAndMemoHaveTheirLclOneLiners;
    { B4 -- geometry the designer could not reach }
    procedure AutoSizeAndContainerGeometryArePublished;
    procedure LyingPropertiesStayUnpublished;
    { P0 -- semantic mismatches }
    procedure DateTimePickerAmPmKeysSetTheMeridiem;
    procedure DateTimePickerSpaceTogglesTheCheckBox;
    procedure DateTimePickerSeparatorAdvancesTheField;
    procedure SpeedButtonAllowAllUpOffRestoresTheInvariant;
    procedure SplitterDisabledShowsNoResizeCursor;
    procedure MenuBarChildlessTopFiresItsOnClick;
    procedure MenuBarDisabledTopCannotBeOpened;
    procedure EditClearSelectionDeletesTheSelectedText;
    procedure ShellControlsLeaveTheirEventSlotsToTheApp;
    procedure ShellListRefreshMeansRepaintAgain;
    procedure ShellTreeAppHandlerActuallyRuns;
    procedure ImageTransparentReachesTheGraphicMask;
    procedure CaptionAndTextAreOneString;
    procedure GaugeDoesNotOfferACaptionItIgnores;
    procedure UpDownWrapCarriesTheOvershoot;
    procedure TrackBarOrientationSwapsTheAxis;
    procedure HeadlinePropertiesArePublished;
    procedure ColorButtonFiresOnAnyColourChange;
    procedure RadioGroupIsOneTabStop;
    procedure RadioGroupOnClickFiresOnSelection;
    procedure MenuRowsCarryHintAndCheckability;
    procedure ScrollBoxExposesTheViewScroll;
    procedure MenuBarRightJustifiesFromTheRightEdge;
  end;

implementation

{ Hour of the day 0..23 -- the meridiem assertions read this rather than a formatted
  string, so a locale change cannot make them pass for the wrong reason. }
function HourOf(AValue: TDateTime): Integer;
var
  h, m, sec, ms: Word;
begin
  DecodeTime(AValue, h, m, sec, ms);
  Result := h;
end;

procedure TToolBarProbe.ProbeApply(B: TTyButton);
begin
  ApplyToButton(B);
end;

procedure TMaskProbe.ProbePaste(const S: string);
begin
  InjectStringAt(S);
end;

function TPanelTextProbe.ProbeText: string;
begin
  Result := Text;
end;

procedure TPanelTextProbe.SetProbeText(const S: string);
begin
  Text := S;
end;

function TTabTextProbe.ProbeText: string;
begin
  Result := Text;
end;

function TDividerTextProbe.ProbeText: string;
begin
  Result := Text;
end;

function TScrollBoxProbe.ProbeHost: TWinControl;
begin
  Result := ContentHost;
end;

function TShellTreeProbe.ProbeText(Node: PTyTreeNode): string;
begin
  Result := GetNodeSearchText(Node);
end;

procedure TDtpProbe.ProbeChar(C: Char);
var
  k: TUTF8Char;
begin
  k := C;
  UTF8KeyPress(k);
end;

procedure TDtpProbe.ProbeKey(K: Word);
var
  w: Word;
begin
  w := K;
  KeyDown(w, []);
end;

procedure TUpDownProbe.ProbeDown(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
end;

procedure TUpDownProbe.ProbeUp(X, Y: Integer);
begin
  MouseUp(mbLeft, [], X, Y);
end;

procedure TCheckGroupProbe.ProbeClick(AIndex: Integer; AValue: Boolean);
var
  cb: TTyCheckBox;
begin
  cb := CheckBoxAt(AIndex);
  if cb <> nil then cb.Checked := AValue;
end;

{ ---------------------------------------------------------------- A2 ------- }

{ Grouping used to live only in Click, so this -- the way you restore a saved toolbar
  mode on startup -- left every button in the group pressed at once. }
procedure TParityTest.SpeedButtonDownFromCodeReleasesSiblings;
var
  Host: TCustomControl;
  A, B: TTySpeedButton;
begin
  Host := TCustomControl.Create(nil);
  try
    A := TTySpeedButton.Create(Host); A.Parent := Host; A.GroupIndex := 1;
    B := TTySpeedButton.Create(Host); B.Parent := Host; B.GroupIndex := 1;
    A.Down := True;
    AssertTrue('A down', A.Down);
    B.Down := True;                         { no click anywhere -- pure code }
    AssertTrue('B down', B.Down);
    AssertFalse('A must have been released by the group', A.Down);
  finally
    Host.Free;
  end;
end;

{ AllowAllUp = False means a radio group always has exactly one pressed member, so
  releasing the pressed one directly is refused -- only pressing a sibling moves it. }
procedure TParityTest.SpeedButtonRadioCannotBeReleasedByHand;
var
  Host: TCustomControl;
  A: TTySpeedButton;
begin
  Host := TCustomControl.Create(nil);
  try
    A := TTySpeedButton.Create(Host); A.Parent := Host; A.GroupIndex := 1;
    A.Down := True;
    A.Down := False;
    AssertTrue('AllowAllUp=False: the group cannot go all-up', A.Down);
    A.AllowAllUp := True;
    A.Down := False;
    AssertFalse('AllowAllUp=True: it can', A.Down);
  finally
    Host.Free;
  end;
end;

{ --------------------------------------------------------------- A14 ------- }

procedure TParityTest.ListBoxSelectedFalseDeselectsInSingleMode;
var
  L: TTyListBox;
begin
  L := TTyListBox.Create(nil);
  try
    L.Items.Add('a'); L.Items.Add('b');
    L.ItemIndex := 1;
    L.Selected[1] := False;
    AssertEquals('Selected[i] := False must deselect, not no-op', -1, L.ItemIndex);
  finally
    L.Free;
  end;
end;

procedure TParityTest.ListBoxClearSelectionWorksInSingleMode;
var
  L: TTyListBox;
begin
  L := TTyListBox.Create(nil);
  try
    L.Items.Add('a'); L.Items.Add('b');
    L.ItemIndex := 1;
    L.ClearSelection;
    AssertEquals('ClearSelection returned early unless MultiSelect happened to be on',
      -1, L.ItemIndex);
    AssertEquals('and nothing is selected', 0, L.SelCount);
  finally
    L.Free;
  end;
end;

{ --------------------------------------------------------------- A22 ------- }

procedure TParityTest.CountItemChange(Sender: TObject; AIndex: Integer);
begin
  Inc(FItemEvents);
end;

{ OnItemChange reports what the user did. Firing it for a programmatic write makes a
  handler that writes back re-enter itself. }
procedure TParityTest.CheckGroupProgrammaticWriteIsSilent;
var
  G: TCheckGroupProbe;
begin
  G := TCheckGroupProbe.Create(nil);
  try
    G.Items.Add('a'); G.Items.Add('b');
    FItemEvents := 0;
    G.OnItemChange := @CountItemChange;
    G.Checked[0] := True;
    AssertTrue('the write itself must land', G.Checked[0]);
    AssertEquals('a programmatic write must not fire OnItemChange', 0, FItemEvents);
  finally
    G.Free;
  end;
end;

{ ...and suppressing it must be scoped to the one write, not left off. }
procedure TParityTest.CheckGroupUserClickStillFires;
var
  G: TCheckGroupProbe;
begin
  G := TCheckGroupProbe.Create(nil);
  try
    G.Items.Add('a');
    G.OnItemChange := @CountItemChange;
    G.Checked[0] := True;
    FItemEvents := 0;
    G.ProbeClick(0, False);                { as a click would }
    AssertEquals('the event must be back on afterwards', 1, FItemEvents);
  finally
    G.Free;
  end;
end;

{ --------------------------------------------------------------- A24 ------- }

procedure TParityTest.ToolBarKeepsACallersStyleClass;
var
  T: TToolBarProbe;
  B: TTyButton;
begin
  T := TToolBarProbe.Create(nil);
  try
    T.Flat := True;
    B := TTyButton.Create(T); B.Parent := T;
    B.StyleClass := 'primary';
    T.ProbeApply(B);                    { what every relayout does }
    AssertEquals('the bar wiped a class it did not put there', 'primary', B.StyleClass);
  finally
    T.Free;
  end;
end;

procedure TParityTest.ToolBarStillGhostsAnUnstyledButton;
var
  T: TToolBarProbe;
  B: TTyButton;
begin
  T := TToolBarProbe.Create(nil);
  try
    T.Flat := True;
    B := TTyButton.Create(T); B.Parent := T;
    T.ProbeApply(B);
    AssertEquals('flat bar ghosts its own buttons', 'ghost', B.StyleClass);
    T.Flat := False;
    T.ProbeApply(B);
    AssertEquals('and takes it back off', '', B.StyleClass);
  finally
    T.Free;
  end;
end;

{ --------------------------------------------------------------- A25 ------- }

{ The native bar runs its last panel to the right edge (win32wscomctrls writes -1 as the
  final right). Without it, widths that do not happen to sum to the client width leave a
  strip of bare parent showing between the last panel and the frame. }
procedure TParityTest.StatusBarLastPanelReachesTheEdge;
var
  R: TTyRectArray;
begin
  R := TyStatusPanelRects([60, 60], 400, 2);
  AssertEquals('last panel must reach the right edge', 398, R[1].Right);
  AssertEquals('and the ones before it keep their widths', 62, R[0].Right);
end;

{ --------------------------------------------------------------- A34 ------- }

procedure TParityTest.ColorBoxUnknownColourDoesNotGrowTheList;
var
  C: TTyColorBox;
  N: Integer;
begin
  C := TTyColorBox.Create(nil);
  try
    N := C.Items.Count;
    C.Selected := TColor($123456);         { not in the 16-colour palette }
    AssertEquals('a picker must not grow its own palette', N, C.Items.Count);
    AssertEquals('and reports "not one of mine"', -1, C.ItemIndex);
  finally
    C.Free;
  end;
end;

procedure TParityTest.ColorBoxKnownColourStillSelects;
var
  C: TTyColorBox;
  N: Integer;
begin
  C := TTyColorBox.Create(nil);
  try
    N := C.Items.Count;
    C.Selected := clRed;
    AssertTrue('a palette colour still selects', C.ItemIndex >= 0);
    AssertEquals('without touching the list', N, C.Items.Count);
    AssertEquals('and reads back', clRed, C.Selected);
  finally
    C.Free;
  end;
end;

{ --------------------------------------------------------------- A10 ------- }

{ Max <= Min is how you say "no limit". The unconditional clamp turned it into
  "pin everything to Min", so a 0/0 spin edit could never hold anything but 0. }
procedure TParityTest.SpinEditEmptyRangeMeansUnbounded;
var
  S: TTySpinEdit;
begin
  S := TTySpinEdit.Create(nil);
  try
    S.MinValue := 0;
    S.MaxValue := 0;
    S.Value := 5000;
    AssertEquals('an empty range must not clamp', 5000, S.Value);
    S.Value := -5000;
    AssertEquals('in either direction', -5000, S.Value);
  finally
    S.Free;
  end;
end;

procedure TParityTest.SpinEditRealRangeStillClamps;
var
  S: TTySpinEdit;
begin
  S := TTySpinEdit.Create(nil);
  try
    S.MinValue := 10;
    S.MaxValue := 20;
    S.Value := 99;
    AssertEquals('a real range still clamps high', 20, S.Value);
    S.Value := 1;
    AssertEquals('and low', 10, S.Value);
  finally
    S.Free;
  end;
end;

{ --------------------------------------------------------------- A32 ------- }

procedure TParityTest.CountPopup(Sender: TObject);
begin
  Inc(FPopups);
end;

{ PopUp was EnsureRenderer + show, and nothing else -- so OnPopup never fired. That is
  the event a context menu exists for: it is where you build the menu from whatever is
  under the cursor. An empty menu is used here because LCL bails right after DoPopup
  when there are no items, which keeps the test off the window-showing path. }
procedure TParityTest.PopupMenuFiresOnPopup;
var
  M: TTyPopupMenu;
begin
  M := TTyPopupMenu.Create(nil);
  try
    FPopups := 0;
    M.OnPopup := @CountPopup;
    M.PopUp(10, 20);
    AssertEquals('OnPopup must fire', 1, FPopups);
  finally
    M.Free;
  end;
end;

procedure TParityTest.PopupMenuRecordsThePopupPoint;
var
  M: TTyPopupMenu;
begin
  M := TTyPopupMenu.Create(nil);
  try
    M.PopUp(37, 91);
    AssertEquals('PopupPoint.X', 37, M.PopupPoint.X);
    AssertEquals('PopupPoint.Y', 91, M.PopupPoint.Y);
  finally
    M.Free;
  end;
end;

{ ---------------------------------------------------------------- A4 ------- }

procedure TParityTest.RecordArrow(Sender: TObject; AButton: TTyUpDownButton);
begin
  if AButton = udbNext then FArrows := FArrows + 'N' else FArrows := FArrows + 'P';
end;

{ TTyUpDown inherits a plain TNotifyEvent OnClick under the same name LCL gives to a
  direction-carrying one, so ported code assigns a handler and is silently told nothing. }
procedure TParityTest.UpDownArrowClickSaysWhichArrow;
var
  U: TUpDownProbe;
begin
  U := TUpDownProbe.Create(nil);
  try
    U.SetBounds(0, 0, 20, 40);
    U.Min := 0; U.Max := 10; U.Position := 5;
    FArrows := '';
    U.OnArrowClick := @RecordArrow;
    U.ProbeDown(5, 5);    { top half = up }
    U.ProbeUp(5, 5);
    U.ProbeDown(5, 35);   { bottom half = down }
    U.ProbeUp(5, 35);
    AssertEquals('one event per press, carrying the direction', 'NP', FArrows);
    AssertEquals('and the value moved with it', 5, U.Position);
  finally
    U.Free;
  end;
end;

{ --------------------------------------------------------------- A27 ------- }

{ Frequency = 0 means "no ticks", so the shipped default made a fresh track bar look
  like tick marks were unimplemented rather than switched off. }
procedure TParityTest.TrackBarShowsTicksOutOfTheBox;
var
  T: TTyTrackBar;
begin
  T := TTyTrackBar.Create(nil);
  try
    AssertEquals('LCL ships Frequency = 1', 1, T.Frequency);
  finally
    T.Free;
  end;
end;

{ ---------------------------------------------------------------- B1 ------- }

{ Visible was published on neither base class, so no TTy control could be hidden from
  the designer or a .lfm -- only from code. TControl.Visible being public is what hid
  it: it works everywhere except where you look for it. }
procedure TParityTest.VisibleIsPublishedOnBothBaseClasses;
begin
  AssertTrue('graphic base publishes Visible (TTyUpDown is a TTyGraphicControl)',
    GetPropInfo(TTyUpDown, 'Visible') <> nil);
  AssertTrue('windowed base publishes Visible (TTyPanel is a TTyCustomControl)',
    GetPropInfo(TTyPanel, 'Visible') <> nil);
end;

{ ---------------------------------------------------------------- A7 ------- }

{ Typing was masked because UTF8KeyPress is overridden. Paste is not typing -- it goes
  through InjectStringAt -> FilterInsert, which TTyMaskEdit never overrode. So Ctrl+V
  put arbitrary text into a masked field, and IsComplete then answered about a string
  the mask had never approved. }
procedure TParityTest.MaskEditPasteGoesThroughTheMask;
var
  M: TMaskProbe;
begin
  M := TMaskProbe.Create(nil);
  try
    M.Mask := '###-###';
    M.ProbePaste('hello world');
    AssertEquals('nothing the mask rejects may land', '', M.Text);
    AssertFalse('and it is certainly not complete', M.IsComplete);
  finally
    M.Free;
  end;
end;

{ Literals in the pasted text are dropped rather than matched -- TyMaskApply re-inserts
  them itself, so a pasted "123-456" and a pasted "123456" both land the same. }
procedure TParityTest.MaskEditPasteKeepsOnlyWhatFits;
var
  M: TMaskProbe;
begin
  M := TMaskProbe.Create(nil);
  try
    M.Mask := '###-###';
    M.ProbePaste('12a3-45x6789');
    AssertEquals('digits laid into slots, literals rebuilt', '123-456', M.Text);
    AssertTrue('all slots filled', M.IsComplete);
  finally
    M.Free;
  end;
end;

{ --------------------------------------------------------------- A31 ------- }

{ LCL's TCustomCalendar.Date is a STRING and its TDateTime twin is DateTime -- the one
  TCalendar publishes. Same name, different type on the two controls, which is the worst
  shape a difference can take: it compiles on one side and not the other. }
procedure TParityTest.CalendarAcceptsTheLclPropertyName;
var
  C: TTyCalendar;
begin
  C := TTyCalendar.Create(nil);
  try
    C.DateTime := EncodeDate(2026, 7, 30);
    AssertEquals('DateTime and Date are one field', C.Date, C.DateTime);
    AssertEquals('and it took', EncodeDate(2026, 7, 30), C.DateTime);
  finally
    C.Free;
  end;
end;

{ ---------------------------------------------------------------- A8 ------- }

procedure TParityTest.MaskEditAcceptsTheLclPropertyName;
var
  M: TTyMaskEdit;
begin
  M := TTyMaskEdit.Create(nil);
  try
    M.EditMask := '###';          { LCL and Delphi both call it this }
    AssertEquals('EditMask is an alias on the same field', '###', M.Mask);
  finally
    M.Free;
  end;
end;

{ ---------------------------------------------------------------- A1 ------- }

{ Caption is published, settable in the designer, and documented as behaving like
  TTyButton's -- and DrawContent never called the base, so it drew zero pixels of it.
  No error, no warning: you set a Caption, you see a swatch, you go looking for a bug
  in your own code. The measurement has to agree, or AutoSize clips the one property
  the user actually filled in. }
procedure TParityTest.ColorButtonPaintsItsCaption;
var
  B: TTyColorButton;
begin
  B := TTyColorButton.Create(nil);
  try
    AssertEquals('nothing set: no text at all', '', B.ContentText);
    B.Caption := 'Pick...';
    AssertEquals('a Caption is what gets drawn', 'Pick...', B.ContentText);
  finally
    B.Free;
  end;
end;

procedure TParityTest.ColorButtonCaptionOutranksTheHex;
var
  B: TTyColorButton;
begin
  B := TTyColorButton.Create(nil);
  try
    B.ShowText := True;
    AssertTrue('no Caption -> the hex, as before', Pos('#', B.ContentText) = 1);
    B.Caption := 'Border';
    AssertEquals('one text slot, and an explicit Caption owns it', 'Border', B.ContentText);
    B.Caption := '';
    AssertTrue('clearing it hands the slot back', Pos('#', B.ContentText) = 1);
  finally
    B.Free;
  end;
end;

{ --------------------------------------------------------------- A18 ------- }

{ The last section absorbs any leftover client width -- deliberate, so the strip spans
  the control -- but SectionWidth kept returning what you SET. Set 100, 250 gets painted,
  read it back and it says 100, so anything laid out against it (a grid under the header,
  a total-width sum) was wrong about the last column and only the last column. }
procedure TParityTest.HeaderEffectiveWidthTellsTheTruthAboutTheLastSection;
var
  H: TTyHeaderControl;
begin
  H := TTyHeaderControl.Create(nil);
  try
    H.Font.PixelsPerInch := 96;
    H.SetBounds(0, 0, 400, 26);
    H.AddSection('A', 100);
    H.AddSection('B', 100);
    AssertEquals('SectionWidth still reports what was set', 100, H.SectionWidth[1]);
    AssertEquals('a non-last section paints at its own width', 100, H.EffectiveSectionWidth[0]);
    AssertEquals('the last one paints wider, and now says so',
      300, H.EffectiveSectionWidth[1]);
  finally
    H.Free;
  end;
end;

{ ---------------------------------------------------------------- B2 ------- }

{ Drag-and-drop and the horizontal wheel are TControl members whose dispatch the LCL
  already implements -- they work on a self-drawn control exactly as on a native one,
  because dragging is decided above the paint layer. Neither base class republished them,
  so no control here could be made a drag source or drop target from the designer or a
  .lfm. Same shape of gap as Visible: public on TControl, so code always compiled; it was
  the Object Inspector and the streamed form that had nothing. }
procedure TParityTest.DragAndWheelSurfaceIsPublishedOnBothBaseClasses;
const
  NAMES: array[0..10] of string = (
    'DragMode', 'DragKind', 'DragCursor', 'OnDragOver', 'OnDragDrop', 'OnStartDrag',
    'OnEndDrag', 'OnMouseWheelHorz', 'OnMouseWheelLeft', 'OnMouseWheelRight', 'OnShowHint');
var
  i: Integer;
begin
  for i := Low(NAMES) to High(NAMES) do
  begin
    AssertTrue('graphic base must publish ' + NAMES[i],
      GetPropInfo(TTyUpDown, NAMES[i]) <> nil);
    AssertTrue('windowed base must publish ' + NAMES[i],
      GetPropInfo(TTyPanel, NAMES[i]) <> nil);
  end;
end;

{ ---------------------------------------------------------------- B3 ------- }

{ Clear is not Items.Clear: emptying the list has to bring the selection down with it, or
  ItemIndex keeps pointing at a row that no longer exists. }
procedure TParityTest.ListBoxClearTakesTheSelectionDownWithIt;
var
  L: TTyListBox;
begin
  L := TTyListBox.Create(nil);
  try
    L.AddItem('a', nil); L.AddItem('b', TObject(Self));
    AssertEquals('AddItem appends', 2, L.Count);
    AssertTrue('and carries the object', L.Items.Objects[1] = TObject(Self));
    L.ItemIndex := 1;
    L.Clear;
    AssertEquals('list empty', 0, L.Count);
    AssertEquals('and nothing is selected any more', -1, L.ItemIndex);
  finally
    L.Free;
  end;
end;

{ ItemRect and the hit-test must be one formula, or an editor placed over a row lands
  somewhere the row is not. }
procedure TParityTest.ListBoxItemRectIsTheInverseOfTheHitTest;
var
  L: TTyListBox;
  r: TRect;
begin
  L := TTyListBox.Create(nil);
  try
    L.Font.PixelsPerInch := 96;
    L.SetBounds(0, 0, 160, 240);
    L.Items.Add('0'); L.Items.Add('1'); L.Items.Add('2');
    r := L.ItemRect(1);
    AssertTrue('row 1 has a rect', r.Bottom > r.Top);
    AssertEquals('and hit-testing its middle gives row 1 back',
      1, L.GetIndexAtY((r.Top + r.Bottom) div 2));
    AssertTrue('an out-of-range row has no rect', L.ItemRect(99).Bottom = 0);
  finally
    L.Free;
  end;
end;

{ Back to front: deleting row i shifts every row after it, so forward iteration removes
  the wrong rows the moment it removes the first one. }
procedure TParityTest.ListBoxDeleteSelectedGoesBackToFront;
var
  L: TTyListBox;
begin
  L := TTyListBox.Create(nil);
  try
    L.Items.Add('0'); L.Items.Add('1'); L.Items.Add('2'); L.Items.Add('3');
    L.MultiSelect := True;
    L.Selected[0] := True;
    L.Selected[2] := True;
    AssertEquals('two removed', 2, L.DeleteSelected);
    AssertEquals('two left', 2, L.Count);
    AssertEquals('and they are the RIGHT two', '1', L.Items[0]);
    AssertEquals('', '3', L.Items[1]);
  finally
    L.Free;
  end;
end;

procedure TParityTest.ListBoxSelectRangeAndSelectedText;
var
  L: TTyListBox;
begin
  L := TTyListBox.Create(nil);
  try
    L.Items.Add('a'); L.Items.Add('b'); L.Items.Add('c'); L.Items.Add('d');
    L.MultiSelect := True;
    L.SelectRange(2, 1, True);            { reversed bounds are still a range }
    AssertEquals('two selected', 2, L.SelCount);
    AssertEquals('and read back in list order', 'b' + LineEnding + 'c', L.GetSelectedText);
    L.SelectRange(0, 3, False);
    AssertEquals('cleared', 0, L.SelCount);
  finally
    L.Free;
  end;
end;

{ Clearing only Items leaves the field displaying an item that is no longer in the list --
  which is the bug you get from calling Items.Clear by hand. }
procedure TParityTest.ComboBoxClearAlsoBlanksTheText;
var
  C: TTyComboBox;
begin
  C := TTyComboBox.Create(nil);
  try
    C.AddItem('one', nil); C.AddItem('two', nil);
    AssertEquals('two items', 2, C.Count);
    C.ItemIndex := 1;
    AssertEquals('text follows the selection', 'two', C.Text);
    C.Clear;
    AssertEquals('list empty', 0, C.Count);
    AssertEquals('and the field is blank, not showing a vanished item', '', C.Text);
    AssertEquals('nothing selected', -1, C.ItemIndex);

    { The mode that matters. Items.Clear alone blanks the text ONLY in csDropDownList --
      ResyncIndexFromText leaves an editable field's free text deliberately alone, since
      there it need not be a list member. So csDropDown is where Clear has real work to
      do, and testing only the default mode would have proved nothing. }
    C.Style := csDropDown;
    C.AddItem('three', nil);
    C.ItemIndex := 0;
    AssertEquals('editable field shows it', 'three', C.Text);
    C.Clear;
    AssertEquals('editable list empty', 0, C.Count);
    AssertEquals('and the editable field is blank too', '', C.Text);
  finally
    C.Free;
  end;
end;

procedure TParityTest.EditAndMemoHaveTheirLclOneLiners;
var
  E: TTyEdit;
  M: TTyMemo;
begin
  E := TTyEdit.Create(nil);
  try
    E.Text := 'xyz';
    E.Clear;
    AssertEquals('Edit.Clear empties it', '', E.Text);
  finally
    E.Free;
  end;
  M := TTyMemo.Create(nil);
  try
    M.Append('one');
    M.Append('two');
    AssertEquals('Memo.Append appends', 2, M.Lines.Count);
    AssertEquals('', 'two', M.Lines[1]);
    M.Clear;
    AssertEquals('Memo.Clear empties it', 0, M.Lines.Count);
  finally
    M.Free;
  end;
end;

{ ---------------------------------------------------------------- B4 ------- }

{ 21 controls here override CalculatePreferredSize -- whose entire purpose is to answer
  "how big do I want to be" -- and TControl.AutoSize is what asks. It was reachable from
  code and absent from the designer, so the measurement work was done and could not be
  switched on where forms are actually built. BorderWidth and ChildSizing are the
  windowed base's container geometry, both fully implemented by TWinControl's align pass. }
procedure TParityTest.AutoSizeAndContainerGeometryArePublished;
begin
  AssertTrue('graphic base publishes AutoSize',
    GetPropInfo(TTyUpDown, 'AutoSize') <> nil);
  AssertTrue('windowed base publishes AutoSize',
    GetPropInfo(TTyPanel, 'AutoSize') <> nil);
  AssertTrue('windowed base publishes BorderWidth',
    GetPropInfo(TTyPanel, 'BorderWidth') <> nil);
  AssertTrue('windowed base publishes ChildSizing',
    GetPropInfo(TTyPanel, 'ChildSizing') <> nil);
  { Container geometry is meaningless on a graphic control -- it hosts nothing. }
  AssertTrue('graphic base does NOT publish ChildSizing',
    GetPropInfo(TTyUpDown, 'ChildSizing') = nil);
end;

{ The counterpart guard, and the more important one. BiDiMode and OnPaint are also
  TControl members that "work from code", and the same batch nearly republished them.
  Neither may be published while the paint path ignores it: grep finds ZERO references to
  BiDiMode/RightToLeft in tyControls.Painter.pas or tyControls.Base.pas, and there is no
  OnPaint hook anywhere in the paint chain. Publishing either would manufacture exactly
  the defect this whole pass has been removing -- a property the Object Inspector offers
  and the control silently ignores, which is how TTyColorButton.Caption came to exist.
  When the paint honours them, delete this test. Until then it is the thing stopping a
  well-meaning "just republish the rest" commit. }
procedure TParityTest.LyingPropertiesStayUnpublished;
begin
  AssertTrue('BiDiMode must not be published until the painter honours it',
    GetPropInfo(TTyPanel, 'BiDiMode') = nil);
  AssertTrue('OnPaint must not be published until the paint chain calls it',
    GetPropInfo(TTyPanel, 'OnPaint') = nil);
end;

{ ---------------------------------------------------------------- P0 ------- }

procedure TParityTest.CountTopClick(Sender: TObject);
begin
  Inc(FTopClicks);
end;

{ A childless top-level item is a COMMAND BUTTON, not a dead cell. OpenTop returned early
  on Count = 0, so a bar with a bare "Help" top did nothing at all -- and there was no way
  to tell that from a menu whose items had failed to load. }
procedure TParityTest.MenuBarChildlessTopFiresItsOnClick;
var
  B: TTyMenuBar;
  M: TMainMenu;
  Top: TMenuItem;
begin
  B := TTyMenuBar.Create(nil);
  M := TMainMenu.Create(B);
  try
    Top := TMenuItem.Create(M);
    Top.Caption := 'Help';
    Top.OnClick := @CountTopClick;
    M.Items.Add(Top);
    B.Menu := M;
    FTopClicks := 0;
    B.OpenTopForTest(0);
    AssertEquals('a childless top fires OnClick', 1, FTopClicks);
  finally
    B.Free;
  end;
end;

{ Disabled must block all three routes into a top -- click, hover-switch and Alt mnemonic --
  which is why the check sits in OpenTop rather than in MouseDown. }
procedure TParityTest.MenuBarDisabledTopCannotBeOpened;
var
  B: TTyMenuBar;
  M: TMainMenu;
  Top, Kid: TMenuItem;
begin
  B := TTyMenuBar.Create(nil);
  M := TMainMenu.Create(B);
  try
    Top := TMenuItem.Create(M);
    Top.Caption := 'File';
    Top.OnClick := @CountTopClick;
    M.Items.Add(Top);
    { A child, deliberately: a disabled CHILDLESS top proves nothing, because
      TMenuItem.Click already no-ops when disabled -- LCL guards that path for us. The
      case that needs our guard is a disabled top WITH children, whose dropdown would
      otherwise open. }
    Kid := TMenuItem.Create(M);
    Kid.Caption := 'Open';
    Top.Add(Kid);
    Top.Enabled := False;
    B.Menu := M;
    AssertFalse('the bar reports it disabled', B.TopEnabledForTest(0));
    FTopClicks := 0;
    B.OpenTopForTest(0);
    AssertEquals('a disabled top must not open its dropdown', -1, B.OpenIndexForTest);
    AssertEquals('and fires nothing', 0, FTopClicks);

    Top.Enabled := True;
    B.OpenTopForTest(0);
    AssertEquals('enabled, it opens', 0, B.OpenIndexForTest);
  finally
    B.Free;
  end;
end;

{ BREAKING and deliberate. LCL's and Delphi's ClearSelection DELETE the selected text; ours
  collapsed the highlight and left it, so ported code asked for a removal, got none, and was
  told nothing. CollapseSelection is the old behaviour, kept and named. }
procedure TParityTest.EditClearSelectionDeletesTheSelectedText;
var
  E: TTyEdit;
begin
  E := TTyEdit.Create(nil);
  try
    E.Text := 'abcdef';
    E.SelStart := 1;
    E.SelLength := 3;                 { 'bcd' }
    E.ClearSelection;
    AssertEquals('ClearSelection removes it', 'aef', E.Text);

    E.Text := 'abcdef';
    E.SelStart := 1;
    E.SelLength := 3;
    E.CollapseSelection;
    AssertEquals('CollapseSelection keeps it', 'abcdef', E.Text);
    AssertEquals('and just drops the highlight', 0, E.SelLength);
  finally
    E.Free;
  end;
end;

{ With the meridiem field selected, A and P used to do nothing: UTF8KeyPress accepted only
  '0'..'9'. So a user typing a time left to right hit a dead stop at the last field and had
  to reach for the arrow key. Set, not toggle -- pressing A twice must still read AM. }
procedure TParityTest.DateTimePickerAmPmKeysSetTheMeridiem;
var
  D: TDtpProbe;
  i: Integer;
begin
  D := TDtpProbe.Create(nil);
  try
    D.Kind := dtkTime;
    D.TimeFormat := 'hh:nn AM/PM';
    D.DateTime := EncodeTime(9, 30, 0, 0);          { 09:30 AM }
    { VK_END parks on the last segment, which for this format is the meridiem. }
    D.ProbeKey(VK_END);
    i := D.ActiveSeg;
    AssertTrue('the last field is the meridiem', (i >= 0) and (i <= High(D.Segments))
      and (D.Segments[i].Kind = skAMPM));
    D.ProbeChar('P');
    AssertEquals('P moves it to PM', 21, HourOf(D.DateTime));
    D.ProbeChar('P');
    AssertEquals('and pressing P again leaves it there', 21, HourOf(D.DateTime));
    D.ProbeChar('a');
    AssertEquals('lower-case a moves it back to AM', 9, HourOf(D.DateTime));
  finally
    D.Free;
  end;
end;

{ The checkbox was mouse-only on a ~12px target, and with ShowCheckBox on an unchecked
  picker refuses every edit path (IsInert). So a keyboard user could reach the control and
  had no way to switch it on. }
procedure TParityTest.DateTimePickerSpaceTogglesTheCheckBox;
var
  D: TDtpProbe;
begin
  D := TDtpProbe.Create(nil);
  try
    D.ShowCheckBox := True;
    D.Checked := False;
    D.ProbeKey(VK_SPACE);
    AssertTrue('Space switches it on', D.Checked);
    D.ProbeKey(VK_SPACE);
    AssertFalse('and off again', D.Checked);
  finally
    D.Free;
  end;
end;

{ Typing a separator commits the field and moves on, so 1/2/2026 goes straight through.
  Before, advance happened only when a field FILLED, so a single-digit month parked. }
procedure TParityTest.DateTimePickerSeparatorAdvancesTheField;
var
  D: TDtpProbe;
  before: Integer;
begin
  D := TDtpProbe.Create(nil);
  try
    D.Kind := dtkDate;
    D.ProbeKey(VK_HOME);
    before := D.ActiveSeg;
    D.ProbeChar('/');
    AssertEquals('the separator moved to the next field', before + 1, D.ActiveSeg);
  finally
    D.Free;
  end;
end;

{ AllowAllUp was a raw field write, so turning it OFF on a group that happens to be all-up
  left an exclusive group with nothing selected until the user clicked. }
procedure TParityTest.SpeedButtonAllowAllUpOffRestoresTheInvariant;
var
  Host: TCustomControl;
  A, B: TTySpeedButton;
begin
  Host := TCustomControl.Create(nil);
  try
    A := TTySpeedButton.Create(Host); A.Parent := Host;
    B := TTySpeedButton.Create(Host); B.Parent := Host;
    A.AllowAllUp := True; B.AllowAllUp := True;
    A.GroupIndex := 1;    B.GroupIndex := 1;
    AssertFalse('group starts all-up', A.Down or B.Down);
    A.AllowAllUp := False;
    AssertTrue('turning it off must leave the group with a selection', A.Down or B.Down);
  finally
    Host.Free;
  end;
end;

{ A disabled splitter kept advertising the resize cursor, so the pointer promised a drag
  over a control that ignores MouseDown. }
procedure TParityTest.SplitterDisabledShowsNoResizeCursor;
var
  S: TTySplitter;
begin
  S := TTySplitter.Create(nil);
  try
    S.Align := alLeft;
    AssertEquals('enabled: the resize cursor', Ord(crHSplit), Ord(S.Cursor));
    { CM_ENABLEDCHANGED re-derives it, so no hover is needed to observe the change. }
    S.Enabled := False;
    AssertEquals('disabled: no promise of a drag', Ord(crDefault), Ord(S.Cursor));
    S.Enabled := True;
    AssertEquals('and back', Ord(crHSplit), Ord(S.Cursor));
  finally
    S.Free;
  end;
end;

{ The five tree events and the two list events were CLAIMED by the shell controls'
  constructors. They are published, so an application that assigned any of them silently
  replaced the shell behaviour -- the tree stopped showing filenames, the list stopped
  navigating on double-click -- with nothing to indicate two uses were fighting over one
  slot. The behaviour lives in overridden virtuals now, so every slot starts nil. }
procedure TParityTest.ShellControlsLeaveTheirEventSlotsToTheApp;
var
  T: TTyShellTreeView;
  L: TTyShellListView;
begin
  T := TTyShellTreeView.Create(nil);
  try
    AssertTrue('OnGetText is the app''s', T.OnGetText = nil);
    AssertTrue('OnInitNode is the app''s', T.OnInitNode = nil);
    AssertTrue('OnExpanding is the app''s', T.OnExpanding = nil);
    AssertTrue('OnGetImageIndex is the app''s', T.OnGetImageIndex = nil);
    AssertTrue('OnChange is the app''s', T.OnChange = nil);
  finally
    T.Free;
  end;
  L := TTyShellListView.Create(nil);
  try
    AssertTrue('OnCompare is the app''s', L.OnCompare = nil);
    AssertTrue('OnItemActivate is the app''s', L.OnItemActivate = nil);
  finally
    L.Free;
  end;
end;

{ Refresh means "repaint now" on every other control in the LCL and in this library. The
  shell list was the one place where a routine repaint call hit the filesystem, and a caller
  who wanted an actual repaint had no way to ask. UpdateView is LCL's name for the re-read. }
procedure TParityTest.ShellListRefreshMeansRepaintAgain;
begin
  { A compile-level assertion: UpdateView must exist as the re-read, and Refresh must no
    longer be reintroduced on the shell list -- if either changes back, this stops building
    rather than failing quietly at run time. }
  AssertTrue('UpdateView is the re-read',
    @TTyShellListView.UpdateView <> nil);
  AssertTrue('Refresh is TControl''s again',
    TMethod(@TTyShellListView(nil).Refresh).Code = TMethod(@TControl(nil).Refresh).Code);
end;

procedure TParityTest.CountGetText(Sender: TTyTreeView; Node: PTyTreeNode;
  var AText: string);
begin
  Inc(FGetTextCalls);
end;

{ The behavioural half of the same finding, and the one that matters: an application
  handler on a slot the shell used to own must actually run. The shell fills its answer in
  first and calls inherited last, so both happen -- which is the whole point of moving the
  behaviour into a virtual rather than a handler. }
procedure TParityTest.ShellTreeAppHandlerActuallyRuns;
var
  T: TShellTreeProbe;
  n: PTyTreeNode;
  txt: string;
begin
  T := TShellTreeProbe.Create(nil);
  try
    FGetTextCalls := 0;
    T.OnGetText := @CountGetText;
    n := T.RootNode;
    if n <> nil then n := n^.FirstChild;
    if n = nil then Exit;          { no drives enumerated here -- nothing to ask about }
    txt := T.ProbeText(n);
    AssertTrue('the app''s OnGetText ran', FGetTextCalls > 0);
    AssertTrue('and the shell still supplied a name', txt <> '');
  finally
    T.Free;
  end;
end;

{ On LCL, Transparent means "honour the GRAPHIC's own mask" and is pushed into
  Picture.Graphic.Transparent. Here it only ever meant "skip the panel surface", so a
  bitmap with a real mask was drawn opaque however the property was set -- the one thing a
  reader of the LCL docs expects it to do. It now does both. }
procedure TParityTest.ImageTransparentReachesTheGraphicMask;
var
  I: TTyImage;
  B: TBitmap;
begin
  I := TTyImage.Create(nil);
  B := TBitmap.Create;
  try
    B.SetSize(4, 4);
    I.Transparent := False;
    I.Picture.Assign(B);
    AssertFalse('a freshly assigned graphic takes the current setting',
      I.Picture.Graphic.Transparent);
    I.Transparent := True;
    AssertTrue('and follows a later change', I.Picture.Graphic.Transparent);
  finally
    B.Free;
    I.Free;
  end;
end;

{ Three controls declared a field-backed Caption that SHADOWED TControl.Caption, so each
  had two captions: `P.Caption := 'x'` set theirs and left TControl.Text empty, while
  anything reading Text -- an action link, an accessibility query, generic code walking
  TControl -- saw ''. On LCL they are one string. }
procedure TParityTest.CaptionAndTextAreOneString;
var
  P: TPanelTextProbe;
  T: TTabTextProbe;
  D: TDividerTextProbe;
begin
  P := TPanelTextProbe.Create(nil);
  try
    P.Caption := 'panel';
    AssertEquals('panel: Caption reaches Text', 'panel', P.ProbeText);
    P.SetProbeText('via text');
    AssertEquals('panel: and Text reaches Caption', 'via text', P.Caption);
  finally
    P.Free;
  end;
  T := TTabTextProbe.Create(nil);
  try
    T.Caption := 'tab';
    AssertEquals('tabsheet: Caption reaches Text', 'tab', T.ProbeText);
  finally
    T.Free;
  end;
  D := TDividerTextProbe.Create(nil);
  try
    D.Caption := 'div';
    AssertEquals('divider: Caption reaches Text', 'div', D.ProbeText);
  finally
    D.Free;
  end;
end;

{ An instrument has no caption. Caption was published and grep found exactly one hit --
  that declaration -- so the Object Inspector offered a knob the control ignored. }
procedure TParityTest.GaugeDoesNotOfferACaptionItIgnores;
var
  G: TTyGauge;
begin
  AssertTrue('Caption must not be published on an instrument that never paints one',
    GetPropInfo(TTyGauge, 'Caption') = nil);
  G := TTyGauge.Create(nil);
  try
    AssertFalse('and it must not acquire its Name as invisible caption text',
      csSetCaption in G.ControlStyle);
  finally
    G.Free;
  end;
end;

procedure TParityTest.CountColourChange(Sender: TObject);
begin
  Inc(FColourChanges);
end;

{ Snapping straight to the opposite bound discards the overshoot, so a step bigger than 1
  turned a wrapping up-down from an adder into a reset. }
procedure TParityTest.UpDownWrapCarriesTheOvershoot;
begin
  AssertEquals('step of 1 still wraps to the bound', 0, TyUpDownClamp(11, 0, 10, True));
  AssertEquals('overshoot of 3 carries round', 2, TyUpDownClamp(13, 0, 10, True));
  AssertEquals('and downward too', 9, TyUpDownClamp(-2, 0, 10, True));
  AssertEquals('no wrap: still clamps', 10, TyUpDownClamp(13, 0, 10, False));
end;

{ Switching a 200x30 bar to vertical used to leave it 200 wide with a vertical track drawn
  inside -- a horizontal box containing a vertical control. }
procedure TParityTest.TrackBarOrientationSwapsTheAxis;
var
  T: TTyTrackBar;
begin
  T := TTyTrackBar.Create(nil);
  try
    T.SetBounds(0, 0, 200, 30);
    T.Orientation := toVertical;
    AssertEquals('vertical is taller than wide', 200, T.Height);
    AssertEquals('', 30, T.Width);
    T.Orientation := toHorizontal;
    AssertEquals('and back', 200, T.Width);
  finally
    T.Free;
  end;
end;

{ Three controls kept their headline property PUBLIC only, so the one thing each control is
  for could not be set in the designer or streamed to the .lfm. }
procedure TParityTest.HeadlinePropertiesArePublished;
begin
  AssertTrue('page control publishes ActivePage',
    GetPropInfo(TTyPageControl, 'ActivePage') <> nil);
  AssertTrue('colour box publishes Selected',
    GetPropInfo(TTyColorBox, 'Selected') <> nil);
  AssertTrue('colour list box publishes Selected',
    GetPropInfo(TTyColorListBox, 'Selected') <> nil);
end;

{ OnColorChange fired only for a DIALOG-driven change, so a handler keeping something in
  step with the colour worked when the user picked and silently did not when the app
  restored a saved value -- the case nobody tests. }
procedure TParityTest.ColorButtonFiresOnAnyColourChange;
var
  B: TTyColorButton;
begin
  B := TTyColorButton.Create(nil);
  try
    FColourChanges := 0;
    B.OnColorChange := @CountColourChange;
    B.SelectedColor := TyRGBA(1, 2, 3, 255);
    AssertEquals('a programmatic change fires it too', 1, FColourChanges);
    B.SelectedColor := TyRGBA(1, 2, 3, 255);
    AssertEquals('and an unchanged write does not', 1, FColourChanges);
  finally
    B.Free;
  end;
end;

{ Every child was a tab stop, so tabbing a form with a five-item radio group meant five
  stops inside ONE logical control -- and the arrow keys, which are what actually move a
  radio selection, had nothing to do. LCL keeps TabStop on the checked radio only. }
procedure TParityTest.RadioGroupIsOneTabStop;
var
  G: TTyRadioGroup;
  i, stops: Integer;
begin
  G := TTyRadioGroup.Create(nil);
  try
    G.Items.Add('a'); G.Items.Add('b'); G.Items.Add('c');
    G.ItemIndex := 1;
    stops := 0;
    for i := 0 to G.ControlCount - 1 do
      if (G.Controls[i] is TTyRadioButton) and TTyRadioButton(G.Controls[i]).TabStop then
        Inc(stops);
    AssertEquals('the group is one tab stop', 1, stops);
    AssertTrue('and it is the chosen one',
      (G.ControlCount > 1) and (G.Controls[1] is TTyRadioButton)
      and TTyRadioButton(G.Controls[1]).TabStop);
  finally
    G.Free;
  end;
end;

{ TCustomRadioGroup redeclares FOnClick and fires it on any selection change, so ported
  code hangs its logic there. TControl's OnClick fires when the control ITSELF is clicked,
  which on a group whose whole surface is covered by its children is never -- so the
  handler was simply dead. }
procedure TParityTest.RadioGroupOnClickFiresOnSelection;
var
  G: TTyRadioGroup;
begin
  G := TTyRadioGroup.Create(nil);
  try
    G.Items.Add('a'); G.Items.Add('b');
    FTopClicks := 0;
    G.OnClick := @CountTopClick;
    G.ItemIndex := 1;
    AssertEquals('OnClick reports the selection change', 1, FTopClicks);
  finally
    G.Free;
  end;
end;

{ TMenuItem.Hint was carried on the render row and read by nobody, so setting it in the
  designer did exactly nothing -- a status bar had no way to describe the command under the
  cursor. AutoCheck likewise: a toggleable item looked identical to a plain one until it had
  already been clicked once. Both are on the row now, which is what the paint and the
  highlight read. }
procedure TParityTest.MenuRowsCarryHintAndCheckability;
var
  M: TMainMenu;
  Root, A, B: TMenuItem;
  rows: TTyMenuRowArray;
begin
  M := TMainMenu.Create(nil);
  try
    Root := TMenuItem.Create(M);
    M.Items.Add(Root);
    A := TMenuItem.Create(M);
    A.Caption := 'Toolbar';
    A.Hint := 'Show or hide the toolbar';
    A.AutoCheck := True;
    Root.Add(A);
    B := TMenuItem.Create(M);
    B.Caption := 'Open';
    Root.Add(B);

    rows := TyBuildMenuRows(Root, False);
    AssertEquals('two rows', 2, Length(rows));
    AssertEquals('the hint reaches the row', 'Show or hide the toolbar', rows[0].Hint);
    AssertTrue('an AutoCheck item reserves its check slot', rows[0].AlwaysCheckable);
    AssertFalse('a plain command does not', rows[1].AlwaysCheckable);
  finally
    M.Free;
  end;
end;

{ Both operations already existed and were PROTECTED, so the one thing a caller most wants
  from a scrolling container -- "show me a bit further down" -- was reachable only by
  writing the scrollbar's Position and hoping. }
procedure TParityTest.ScrollBoxExposesTheViewScroll;
var
  B: TScrollBoxProbe;
  Tall: TTyPanel;
begin
  B := TScrollBoxProbe.Create(nil);
  try
    B.SetBounds(0, 0, 100, 100);
    { Real content, or there is no scrollable range and every offset legitimately clamps
      to 0 -- which would make this test pass for the wrong reason. }
    Tall := TTyPanel.Create(B);
    Tall.Parent := B.ProbeHost;
    Tall.SetBounds(0, 0, 80, 400);
    B.UpdateScrollRange;

    B.ScrollTo(0, 40);
    AssertEquals('ScrollTo moves the view', 40, B.ScrollY);
    B.ScrollByDelta(0, -15);
    AssertEquals('ScrollByDelta is relative', 25, B.ScrollY);
    B.ScrollTo(0, -5);
    AssertEquals('a negative offset clamps at the top', 0, B.ScrollY);
    B.ScrollTo(0, 99999);
    AssertTrue('and ScrollTo clamps at the end, like ScrollByDelta',
      B.ScrollY < 400);
  finally
    B.Free;
  end;
end;

{ TMenuItem.RightJustify is published, the designer offers it, and the bar read it nowhere:
  every cell packed left to right, so the classic right-aligned Help / Window menu could not
  be built at all. A right-justified top and everything after it measure from the RIGHT
  edge, which is what keeps the group glued there as the bar resizes. }
procedure TParityTest.MenuBarRightJustifiesFromTheRightEdge;
var
  B: TTyMenuBar;
  M: TMainMenu;
  Left0, Help: TMenuItem;
begin
  B := TTyMenuBar.Create(nil);
  M := TMainMenu.Create(B);
  try
    B.SetBounds(0, 0, 400, 24);
    Left0 := TMenuItem.Create(M); Left0.Caption := 'File'; M.Items.Add(Left0);
    Help := TMenuItem.Create(M);  Help.Caption := 'Help'; M.Items.Add(Help);
    B.Menu := M;
    AssertFalse('nothing is right-justified yet', B.TopRightJustifiedForTest(1));
    Help.RightJustify := True;
    AssertTrue('the bar now sees the flag', B.TopRightJustifiedForTest(1));
    AssertTrue('and Help sits in the right half of a 400px bar',
      B.TopLeftForTest(1, 96) > 200);
  finally
    B.Free;
  end;
end;

initialization
  RegisterTest(TParityTest);
end.
