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
  Classes, SysUtils, Types, Graphics, Controls, StdCtrls, fpcunit, testregistry,
  tyControls.Types, tyControls.Button, tyControls.GlyphButtons, tyControls.ListBox,
  tyControls.CheckGroup, tyControls.ToolBar, tyControls.StatusBar,
  tyControls.ColorBox, tyControls.SpinEdit, tyControls.CheckBox;

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

  TParityTest = class(TTestCase)
  private
    FItemEvents: Integer;
    procedure CountItemChange(Sender: TObject; AIndex: Integer);
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
  end;

implementation

procedure TToolBarProbe.ProbeApply(B: TTyButton);
begin
  ApplyToButton(B);
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

initialization
  RegisterTest(TParityTest);
end.
