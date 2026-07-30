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
  Classes, SysUtils, TypInfo, Types, Graphics, Controls, StdCtrls, Menus, fpcunit, testregistry,
  tyControls.Types, tyControls.Button, tyControls.GlyphButtons, tyControls.ListBox,
  tyControls.CheckGroup, tyControls.ToolBar, tyControls.StatusBar,
  tyControls.ColorBox, tyControls.SpinEdit, tyControls.CheckBox, tyControls.Menu,
  tyControls.UpDown, tyControls.TrackBar, tyControls.Base, tyControls.Panel,
  tyControls.MaskEdit, tyControls.Calendar, tyControls.ColorButton,
  tyControls.HeaderControl, tyControls.ComboBox, tyControls.Edit, tyControls.Memo;

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
  end;

implementation

procedure TToolBarProbe.ProbeApply(B: TTyButton);
begin
  ApplyToButton(B);
end;

procedure TMaskProbe.ProbePaste(const S: string);
begin
  InjectStringAt(S);
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

initialization
  RegisterTest(TParityTest);
end.
