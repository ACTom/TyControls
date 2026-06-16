unit test.eventfiring;
{ EXHAUSTIVE event-firing matrix (branch verify-event-firing).

  GOAL: prove that EVERY standard LCL event published on EVERY tyControls control
  actually FIRES when its dispatch method is invoked. An event fires iff the
  control's override of the corresponding protected/virtual dispatch method calls
  `inherited` (which is what runs the user-assigned handler). If any control's
  override "eats" an event by not calling inherited, the matching test FAILS and
  exposes a real gap.

  HEADLESS: the dispatch methods (MouseDown/KeyDown/...) are synchronous and need
  no window handle, so we drive them directly on a per-type ACCESS subclass that
  re-exposes the protected method. Because the access subclass derives from the
  CONCRETE control type, invoking e.g. MouseDown runs THAT control's override
  first, which (if correct) calls inherited -> fires OnMouseDown. The few internal
  `SetFocus` calls inside overrides are wrapped in try/except in the sources, so
  they are inert here.

  ENABLED PATH: many input overrides guard `if not Enabled then Exit` BEFORE
  inherited (by design: disabled controls ignore input). We set Enabled := True so
  we test the path where the event SHOULD fire.

  NEUTRAL STIMULI: mbLeft at (1,1) and key VK_F1 are used so no override hits an
  early non-inherited Exit before its `inherited` call. (Every audited override
  calls inherited near the top, before any branch that could Exit.)

  Matrix covered here:
   - ALL 16 controls: MouseDown, MouseUp, MouseMove, MouseEnter, MouseLeave, Click.
   - 14 windowed (TTyCustomControl) controls: + KeyDown, KeyUp.
   - 4 text controls (Edit/Memo/SpinEdit/ComboBox): + UTF8KeyPress.
  (TyLabel + ProgressBar are TTyGraphicControl: mouse + Click only, no key.) }

{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Controls, LCLType, fpcunit, testregistry,
  tyControls.TyLabel, tyControls.ProgressBar,
  tyControls.Button, tyControls.Edit, tyControls.Memo, tyControls.SpinEdit,
  tyControls.ComboBox, tyControls.CheckBox, tyControls.ListBox,
  tyControls.TabControl, tyControls.GroupBox, tyControls.Panel,
  tyControls.ScrollBar, tyControls.TrackBar, tyControls.ToggleSwitch;

type
  { Each access subclass re-exposes ONLY the protected dispatch methods we fire,
    public, so the test can invoke them directly. Click is already public on
    TControl, so it is called without an access wrapper. KeyUp is never overridden
    by any tyControls control, but we still drive it through the access subclass so
    the inherited TWinControl.KeyUp dispatch (which fires OnKeyUp) is exercised on
    the concrete type. }

  TLblAcc = class(TTyLabel)
  public
    procedure FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseMove(S: TShiftState; X, Y: Integer);
    procedure FMouseEnter;
    procedure FMouseLeave;
  end;

  TPbAcc = class(TTyProgressBar)
  public
    procedure FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseMove(S: TShiftState; X, Y: Integer);
    procedure FMouseEnter;
    procedure FMouseLeave;
  end;

  TBtnAcc = class(TTyButton)
  public
    procedure FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseMove(S: TShiftState; X, Y: Integer);
    procedure FMouseEnter;
    procedure FMouseLeave;
    procedure FKeyDown(var K: Word; S: TShiftState);
    procedure FKeyUp(var K: Word; S: TShiftState);
  end;

  TEdAcc = class(TTyEdit)
  public
    procedure FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseMove(S: TShiftState; X, Y: Integer);
    procedure FMouseEnter;
    procedure FMouseLeave;
    procedure FKeyDown(var K: Word; S: TShiftState);
    procedure FKeyUp(var K: Word; S: TShiftState);
    procedure FUTF8(var U: TUTF8Char);
  end;

  TMemoAcc = class(TTyMemo)
  public
    procedure FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseMove(S: TShiftState; X, Y: Integer);
    procedure FMouseEnter;
    procedure FMouseLeave;
    procedure FKeyDown(var K: Word; S: TShiftState);
    procedure FKeyUp(var K: Word; S: TShiftState);
    procedure FUTF8(var U: TUTF8Char);
  end;

  TSpinAcc = class(TTySpinEdit)
  public
    procedure FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseMove(S: TShiftState; X, Y: Integer);
    procedure FMouseEnter;
    procedure FMouseLeave;
    procedure FKeyDown(var K: Word; S: TShiftState);
    procedure FKeyUp(var K: Word; S: TShiftState);
    procedure FUTF8(var U: TUTF8Char);
  end;

  TCmbAcc = class(TTyComboBox)
  public
    procedure FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseMove(S: TShiftState; X, Y: Integer);
    procedure FMouseEnter;
    procedure FMouseLeave;
    procedure FKeyDown(var K: Word; S: TShiftState);
    procedure FKeyUp(var K: Word; S: TShiftState);
    procedure FUTF8(var U: TUTF8Char);
  end;

  TChkAcc = class(TTyCheckBox)
  public
    procedure FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseMove(S: TShiftState; X, Y: Integer);
    procedure FMouseEnter;
    procedure FMouseLeave;
    procedure FKeyDown(var K: Word; S: TShiftState);
    procedure FKeyUp(var K: Word; S: TShiftState);
  end;

  TRadAcc = class(TTyRadioButton)
  public
    procedure FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseMove(S: TShiftState; X, Y: Integer);
    procedure FMouseEnter;
    procedure FMouseLeave;
    procedure FKeyDown(var K: Word; S: TShiftState);
    procedure FKeyUp(var K: Word; S: TShiftState);
  end;

  TLstAcc = class(TTyListBox)
  public
    procedure FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseMove(S: TShiftState; X, Y: Integer);
    procedure FMouseEnter;
    procedure FMouseLeave;
    procedure FKeyDown(var K: Word; S: TShiftState);
    procedure FKeyUp(var K: Word; S: TShiftState);
  end;

  TTabAcc = class(TTyTabControl)
  public
    procedure FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseMove(S: TShiftState; X, Y: Integer);
    procedure FMouseEnter;
    procedure FMouseLeave;
    procedure FKeyDown(var K: Word; S: TShiftState);
    procedure FKeyUp(var K: Word; S: TShiftState);
  end;

  TGrpAcc = class(TTyGroupBox)
  public
    procedure FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseMove(S: TShiftState; X, Y: Integer);
    procedure FMouseEnter;
    procedure FMouseLeave;
    procedure FKeyDown(var K: Word; S: TShiftState);
    procedure FKeyUp(var K: Word; S: TShiftState);
  end;

  TPnlAcc = class(TTyPanel)
  public
    procedure FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseMove(S: TShiftState; X, Y: Integer);
    procedure FMouseEnter;
    procedure FMouseLeave;
    procedure FKeyDown(var K: Word; S: TShiftState);
    procedure FKeyUp(var K: Word; S: TShiftState);
  end;

  TSbAcc = class(TTyScrollBar)
  public
    procedure FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseMove(S: TShiftState; X, Y: Integer);
    procedure FMouseEnter;
    procedure FMouseLeave;
    procedure FKeyDown(var K: Word; S: TShiftState);
    procedure FKeyUp(var K: Word; S: TShiftState);
  end;

  TTbAcc = class(TTyTrackBar)
  public
    procedure FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseMove(S: TShiftState; X, Y: Integer);
    procedure FMouseEnter;
    procedure FMouseLeave;
    procedure FKeyDown(var K: Word; S: TShiftState);
    procedure FKeyUp(var K: Word; S: TShiftState);
  end;

  TTglAcc = class(TTyToggleSwitch)
  public
    procedure FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer);
    procedure FMouseMove(S: TShiftState; X, Y: Integer);
    procedure FMouseEnter;
    procedure FMouseLeave;
    procedure FKeyDown(var K: Word; S: TShiftState);
    procedure FKeyUp(var K: Word; S: TShiftState);
  end;

  { One test class. Each published method fires exactly one (control,event) cell
    and asserts the corresponding flag flipped. A shared bank of handlers flips
    per-event flags so a single helper-per-stimulus stays small. }
  TEventFiringMatrixTest = class(TTestCase)
  private
    FDown, FUp, FMove, FEnter, FLeave, FClick, FKeyDown, FKeyUp, FUTF8: Boolean;
    procedure Reset;
    procedure HMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure HMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure HMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure HEnter(Sender: TObject);
    procedure HLeave(Sender: TObject);
    procedure HClick(Sender: TObject);
    procedure HKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure HKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure HUTF8(Sender: TObject; var UTF8Key: TUTF8Char);
  published
    procedure Label_Mouse;
    procedure ProgressBar_Mouse;
    procedure Button_All;
    procedure Edit_All;
    procedure Memo_All;
    procedure SpinEdit_All;
    procedure ComboBox_All;
    procedure CheckBox_All;
    procedure RadioButton_All;
    procedure ListBox_All;
    procedure TabControl_All;
    procedure GroupBox_All;
    procedure Panel_All;
    procedure ScrollBar_All;
    procedure TrackBar_All;
    procedure ToggleSwitch_All;
  end;

implementation

const
  P11X = 1;
  P11Y = 1;

{ ---- access wrappers (forwarders) ---- }

procedure TLblAcc.FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseDown(B, S, X, Y); end;
procedure TLblAcc.FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseUp(B, S, X, Y); end;
procedure TLblAcc.FMouseMove(S: TShiftState; X, Y: Integer); begin MouseMove(S, X, Y); end;
procedure TLblAcc.FMouseEnter; begin MouseEnter; end;
procedure TLblAcc.FMouseLeave; begin MouseLeave; end;

procedure TPbAcc.FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseDown(B, S, X, Y); end;
procedure TPbAcc.FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseUp(B, S, X, Y); end;
procedure TPbAcc.FMouseMove(S: TShiftState; X, Y: Integer); begin MouseMove(S, X, Y); end;
procedure TPbAcc.FMouseEnter; begin MouseEnter; end;
procedure TPbAcc.FMouseLeave; begin MouseLeave; end;

procedure TBtnAcc.FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseDown(B, S, X, Y); end;
procedure TBtnAcc.FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseUp(B, S, X, Y); end;
procedure TBtnAcc.FMouseMove(S: TShiftState; X, Y: Integer); begin MouseMove(S, X, Y); end;
procedure TBtnAcc.FMouseEnter; begin MouseEnter; end;
procedure TBtnAcc.FMouseLeave; begin MouseLeave; end;
procedure TBtnAcc.FKeyDown(var K: Word; S: TShiftState); begin KeyDown(K, S); end;
procedure TBtnAcc.FKeyUp(var K: Word; S: TShiftState); begin KeyUp(K, S); end;

procedure TEdAcc.FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseDown(B, S, X, Y); end;
procedure TEdAcc.FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseUp(B, S, X, Y); end;
procedure TEdAcc.FMouseMove(S: TShiftState; X, Y: Integer); begin MouseMove(S, X, Y); end;
procedure TEdAcc.FMouseEnter; begin MouseEnter; end;
procedure TEdAcc.FMouseLeave; begin MouseLeave; end;
procedure TEdAcc.FKeyDown(var K: Word; S: TShiftState); begin KeyDown(K, S); end;
procedure TEdAcc.FKeyUp(var K: Word; S: TShiftState); begin KeyUp(K, S); end;
procedure TEdAcc.FUTF8(var U: TUTF8Char); begin UTF8KeyPress(U); end;

procedure TMemoAcc.FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseDown(B, S, X, Y); end;
procedure TMemoAcc.FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseUp(B, S, X, Y); end;
procedure TMemoAcc.FMouseMove(S: TShiftState; X, Y: Integer); begin MouseMove(S, X, Y); end;
procedure TMemoAcc.FMouseEnter; begin MouseEnter; end;
procedure TMemoAcc.FMouseLeave; begin MouseLeave; end;
procedure TMemoAcc.FKeyDown(var K: Word; S: TShiftState); begin KeyDown(K, S); end;
procedure TMemoAcc.FKeyUp(var K: Word; S: TShiftState); begin KeyUp(K, S); end;
procedure TMemoAcc.FUTF8(var U: TUTF8Char); begin UTF8KeyPress(U); end;

procedure TSpinAcc.FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseDown(B, S, X, Y); end;
procedure TSpinAcc.FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseUp(B, S, X, Y); end;
procedure TSpinAcc.FMouseMove(S: TShiftState; X, Y: Integer); begin MouseMove(S, X, Y); end;
procedure TSpinAcc.FMouseEnter; begin MouseEnter; end;
procedure TSpinAcc.FMouseLeave; begin MouseLeave; end;
procedure TSpinAcc.FKeyDown(var K: Word; S: TShiftState); begin KeyDown(K, S); end;
procedure TSpinAcc.FKeyUp(var K: Word; S: TShiftState); begin KeyUp(K, S); end;
procedure TSpinAcc.FUTF8(var U: TUTF8Char); begin UTF8KeyPress(U); end;

procedure TCmbAcc.FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseDown(B, S, X, Y); end;
procedure TCmbAcc.FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseUp(B, S, X, Y); end;
procedure TCmbAcc.FMouseMove(S: TShiftState; X, Y: Integer); begin MouseMove(S, X, Y); end;
procedure TCmbAcc.FMouseEnter; begin MouseEnter; end;
procedure TCmbAcc.FMouseLeave; begin MouseLeave; end;
procedure TCmbAcc.FKeyDown(var K: Word; S: TShiftState); begin KeyDown(K, S); end;
procedure TCmbAcc.FKeyUp(var K: Word; S: TShiftState); begin KeyUp(K, S); end;
procedure TCmbAcc.FUTF8(var U: TUTF8Char); begin UTF8KeyPress(U); end;

procedure TChkAcc.FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseDown(B, S, X, Y); end;
procedure TChkAcc.FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseUp(B, S, X, Y); end;
procedure TChkAcc.FMouseMove(S: TShiftState; X, Y: Integer); begin MouseMove(S, X, Y); end;
procedure TChkAcc.FMouseEnter; begin MouseEnter; end;
procedure TChkAcc.FMouseLeave; begin MouseLeave; end;
procedure TChkAcc.FKeyDown(var K: Word; S: TShiftState); begin KeyDown(K, S); end;
procedure TChkAcc.FKeyUp(var K: Word; S: TShiftState); begin KeyUp(K, S); end;

procedure TRadAcc.FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseDown(B, S, X, Y); end;
procedure TRadAcc.FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseUp(B, S, X, Y); end;
procedure TRadAcc.FMouseMove(S: TShiftState; X, Y: Integer); begin MouseMove(S, X, Y); end;
procedure TRadAcc.FMouseEnter; begin MouseEnter; end;
procedure TRadAcc.FMouseLeave; begin MouseLeave; end;
procedure TRadAcc.FKeyDown(var K: Word; S: TShiftState); begin KeyDown(K, S); end;
procedure TRadAcc.FKeyUp(var K: Word; S: TShiftState); begin KeyUp(K, S); end;

procedure TLstAcc.FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseDown(B, S, X, Y); end;
procedure TLstAcc.FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseUp(B, S, X, Y); end;
procedure TLstAcc.FMouseMove(S: TShiftState; X, Y: Integer); begin MouseMove(S, X, Y); end;
procedure TLstAcc.FMouseEnter; begin MouseEnter; end;
procedure TLstAcc.FMouseLeave; begin MouseLeave; end;
procedure TLstAcc.FKeyDown(var K: Word; S: TShiftState); begin KeyDown(K, S); end;
procedure TLstAcc.FKeyUp(var K: Word; S: TShiftState); begin KeyUp(K, S); end;

procedure TTabAcc.FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseDown(B, S, X, Y); end;
procedure TTabAcc.FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseUp(B, S, X, Y); end;
procedure TTabAcc.FMouseMove(S: TShiftState; X, Y: Integer); begin MouseMove(S, X, Y); end;
procedure TTabAcc.FMouseEnter; begin MouseEnter; end;
procedure TTabAcc.FMouseLeave; begin MouseLeave; end;
procedure TTabAcc.FKeyDown(var K: Word; S: TShiftState); begin KeyDown(K, S); end;
procedure TTabAcc.FKeyUp(var K: Word; S: TShiftState); begin KeyUp(K, S); end;

procedure TGrpAcc.FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseDown(B, S, X, Y); end;
procedure TGrpAcc.FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseUp(B, S, X, Y); end;
procedure TGrpAcc.FMouseMove(S: TShiftState; X, Y: Integer); begin MouseMove(S, X, Y); end;
procedure TGrpAcc.FMouseEnter; begin MouseEnter; end;
procedure TGrpAcc.FMouseLeave; begin MouseLeave; end;
procedure TGrpAcc.FKeyDown(var K: Word; S: TShiftState); begin KeyDown(K, S); end;
procedure TGrpAcc.FKeyUp(var K: Word; S: TShiftState); begin KeyUp(K, S); end;

procedure TPnlAcc.FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseDown(B, S, X, Y); end;
procedure TPnlAcc.FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseUp(B, S, X, Y); end;
procedure TPnlAcc.FMouseMove(S: TShiftState; X, Y: Integer); begin MouseMove(S, X, Y); end;
procedure TPnlAcc.FMouseEnter; begin MouseEnter; end;
procedure TPnlAcc.FMouseLeave; begin MouseLeave; end;
procedure TPnlAcc.FKeyDown(var K: Word; S: TShiftState); begin KeyDown(K, S); end;
procedure TPnlAcc.FKeyUp(var K: Word; S: TShiftState); begin KeyUp(K, S); end;

procedure TSbAcc.FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseDown(B, S, X, Y); end;
procedure TSbAcc.FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseUp(B, S, X, Y); end;
procedure TSbAcc.FMouseMove(S: TShiftState; X, Y: Integer); begin MouseMove(S, X, Y); end;
procedure TSbAcc.FMouseEnter; begin MouseEnter; end;
procedure TSbAcc.FMouseLeave; begin MouseLeave; end;
procedure TSbAcc.FKeyDown(var K: Word; S: TShiftState); begin KeyDown(K, S); end;
procedure TSbAcc.FKeyUp(var K: Word; S: TShiftState); begin KeyUp(K, S); end;

procedure TTbAcc.FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseDown(B, S, X, Y); end;
procedure TTbAcc.FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseUp(B, S, X, Y); end;
procedure TTbAcc.FMouseMove(S: TShiftState; X, Y: Integer); begin MouseMove(S, X, Y); end;
procedure TTbAcc.FMouseEnter; begin MouseEnter; end;
procedure TTbAcc.FMouseLeave; begin MouseLeave; end;
procedure TTbAcc.FKeyDown(var K: Word; S: TShiftState); begin KeyDown(K, S); end;
procedure TTbAcc.FKeyUp(var K: Word; S: TShiftState); begin KeyUp(K, S); end;

procedure TTglAcc.FMouseDown(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseDown(B, S, X, Y); end;
procedure TTglAcc.FMouseUp(B: TMouseButton; S: TShiftState; X, Y: Integer); begin MouseUp(B, S, X, Y); end;
procedure TTglAcc.FMouseMove(S: TShiftState; X, Y: Integer); begin MouseMove(S, X, Y); end;
procedure TTglAcc.FMouseEnter; begin MouseEnter; end;
procedure TTglAcc.FMouseLeave; begin MouseLeave; end;
procedure TTglAcc.FKeyDown(var K: Word; S: TShiftState); begin KeyDown(K, S); end;
procedure TTglAcc.FKeyUp(var K: Word; S: TShiftState); begin KeyUp(K, S); end;

{ ---- handlers ---- }

procedure TEventFiringMatrixTest.Reset;
begin
  FDown := False; FUp := False; FMove := False; FEnter := False; FLeave := False;
  FClick := False; FKeyDown := False; FKeyUp := False; FUTF8 := False;
end;

procedure TEventFiringMatrixTest.HMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer); begin FDown := True; end;
procedure TEventFiringMatrixTest.HMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer); begin FUp := True; end;
procedure TEventFiringMatrixTest.HMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer); begin FMove := True; end;
procedure TEventFiringMatrixTest.HEnter(Sender: TObject); begin FEnter := True; end;
procedure TEventFiringMatrixTest.HLeave(Sender: TObject); begin FLeave := True; end;
procedure TEventFiringMatrixTest.HClick(Sender: TObject); begin FClick := True; end;
procedure TEventFiringMatrixTest.HKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState); begin FKeyDown := True; end;
procedure TEventFiringMatrixTest.HKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState); begin FKeyUp := True; end;
procedure TEventFiringMatrixTest.HUTF8(Sender: TObject; var UTF8Key: TUTF8Char); begin FUTF8 := True; end;

{ ---- per-control tests ---- }

procedure TEventFiringMatrixTest.Label_Mouse;
var C: TLblAcc;
begin
  C := TLblAcc.Create(nil);
  try
    C.Enabled := True;
    Reset;
    C.OnMouseDown := @HMouseDown; C.OnMouseUp := @HMouseUp; C.OnMouseMove := @HMouseMove;
    C.OnMouseEnter := @HEnter; C.OnMouseLeave := @HLeave; C.OnClick := @HClick;
    C.FMouseDown(mbLeft, [], P11X, P11Y); AssertTrue('Label OnMouseDown', FDown);
    C.FMouseUp(mbLeft, [], P11X, P11Y);   AssertTrue('Label OnMouseUp', FUp);
    C.FMouseMove([], P11X, P11Y);         AssertTrue('Label OnMouseMove', FMove);
    C.FMouseEnter;                        AssertTrue('Label OnMouseEnter', FEnter);
    C.FMouseLeave;                        AssertTrue('Label OnMouseLeave', FLeave);
    C.Click;                              AssertTrue('Label OnClick', FClick);
  finally
    C.Free;
  end;
end;

procedure TEventFiringMatrixTest.ProgressBar_Mouse;
var C: TPbAcc;
begin
  C := TPbAcc.Create(nil);
  try
    C.Enabled := True;
    Reset;
    C.OnMouseDown := @HMouseDown; C.OnMouseUp := @HMouseUp; C.OnMouseMove := @HMouseMove;
    C.OnMouseEnter := @HEnter; C.OnMouseLeave := @HLeave; C.OnClick := @HClick;
    C.FMouseDown(mbLeft, [], P11X, P11Y); AssertTrue('ProgressBar OnMouseDown', FDown);
    C.FMouseUp(mbLeft, [], P11X, P11Y);   AssertTrue('ProgressBar OnMouseUp', FUp);
    C.FMouseMove([], P11X, P11Y);         AssertTrue('ProgressBar OnMouseMove', FMove);
    C.FMouseEnter;                        AssertTrue('ProgressBar OnMouseEnter', FEnter);
    C.FMouseLeave;                        AssertTrue('ProgressBar OnMouseLeave', FLeave);
    C.Click;                              AssertTrue('ProgressBar OnClick', FClick);
  finally
    C.Free;
  end;
end;

procedure TEventFiringMatrixTest.Button_All;
var C: TBtnAcc; K: Word;
begin
  C := TBtnAcc.Create(nil);
  try
    C.Enabled := True;
    Reset;
    C.OnMouseDown := @HMouseDown; C.OnMouseUp := @HMouseUp; C.OnMouseMove := @HMouseMove;
    C.OnMouseEnter := @HEnter; C.OnMouseLeave := @HLeave; C.OnClick := @HClick;
    C.OnKeyDown := @HKeyDown; C.OnKeyUp := @HKeyUp;
    C.FMouseDown(mbLeft, [], P11X, P11Y); AssertTrue('Button OnMouseDown', FDown);
    C.FMouseUp(mbLeft, [], P11X, P11Y);   AssertTrue('Button OnMouseUp', FUp);
    C.FMouseMove([], P11X, P11Y);         AssertTrue('Button OnMouseMove', FMove);
    C.FMouseEnter;                        AssertTrue('Button OnMouseEnter', FEnter);
    C.FMouseLeave;                        AssertTrue('Button OnMouseLeave', FLeave);
    C.Click;                              AssertTrue('Button OnClick', FClick);
    K := VK_F1; C.FKeyDown(K, []);        AssertTrue('Button OnKeyDown', FKeyDown);
    K := VK_F1; C.FKeyUp(K, []);          AssertTrue('Button OnKeyUp', FKeyUp);
  finally
    C.Free;
  end;
end;

procedure TEventFiringMatrixTest.Edit_All;
var C: TEdAcc; K: Word; U: TUTF8Char;
begin
  C := TEdAcc.Create(nil);
  try
    C.Enabled := True;
    Reset;
    C.OnMouseDown := @HMouseDown; C.OnMouseUp := @HMouseUp; C.OnMouseMove := @HMouseMove;
    C.OnMouseEnter := @HEnter; C.OnMouseLeave := @HLeave; C.OnClick := @HClick;
    C.OnKeyDown := @HKeyDown; C.OnKeyUp := @HKeyUp; C.OnUTF8KeyPress := @HUTF8;
    C.FMouseDown(mbLeft, [], P11X, P11Y); AssertTrue('Edit OnMouseDown', FDown);
    C.FMouseUp(mbLeft, [], P11X, P11Y);   AssertTrue('Edit OnMouseUp', FUp);
    C.FMouseMove([], P11X, P11Y);         AssertTrue('Edit OnMouseMove', FMove);
    C.FMouseEnter;                        AssertTrue('Edit OnMouseEnter', FEnter);
    C.FMouseLeave;                        AssertTrue('Edit OnMouseLeave', FLeave);
    C.Click;                              AssertTrue('Edit OnClick', FClick);
    K := VK_F1; C.FKeyDown(K, []);        AssertTrue('Edit OnKeyDown', FKeyDown);
    K := VK_F1; C.FKeyUp(K, []);          AssertTrue('Edit OnKeyUp', FKeyUp);
    U := 'a'; C.FUTF8(U);                 AssertTrue('Edit OnUTF8KeyPress', FUTF8);
  finally
    C.Free;
  end;
end;

procedure TEventFiringMatrixTest.Memo_All;
var C: TMemoAcc; K: Word; U: TUTF8Char;
begin
  C := TMemoAcc.Create(nil);
  try
    C.Enabled := True;
    C.ReadOnly := False; // Memo.UTF8KeyPress guards `if FReadOnly then Exit` BEFORE inherited
    Reset;
    C.OnMouseDown := @HMouseDown; C.OnMouseUp := @HMouseUp; C.OnMouseMove := @HMouseMove;
    C.OnMouseEnter := @HEnter; C.OnMouseLeave := @HLeave; C.OnClick := @HClick;
    C.OnKeyDown := @HKeyDown; C.OnKeyUp := @HKeyUp; C.OnUTF8KeyPress := @HUTF8;
    C.FMouseDown(mbLeft, [], P11X, P11Y); AssertTrue('Memo OnMouseDown', FDown);
    C.FMouseUp(mbLeft, [], P11X, P11Y);   AssertTrue('Memo OnMouseUp', FUp);
    C.FMouseMove([], P11X, P11Y);         AssertTrue('Memo OnMouseMove', FMove);
    C.FMouseEnter;                        AssertTrue('Memo OnMouseEnter', FEnter);
    C.FMouseLeave;                        AssertTrue('Memo OnMouseLeave', FLeave);
    C.Click;                              AssertTrue('Memo OnClick', FClick);
    K := VK_F1; C.FKeyDown(K, []);        AssertTrue('Memo OnKeyDown', FKeyDown);
    K := VK_F1; C.FKeyUp(K, []);          AssertTrue('Memo OnKeyUp', FKeyUp);
    U := 'a'; C.FUTF8(U);                 AssertTrue('Memo OnUTF8KeyPress', FUTF8);
  finally
    C.Free;
  end;
end;

procedure TEventFiringMatrixTest.SpinEdit_All;
var C: TSpinAcc; K: Word; U: TUTF8Char;
begin
  C := TSpinAcc.Create(nil);
  try
    C.Enabled := True;
    Reset;
    C.OnMouseDown := @HMouseDown; C.OnMouseUp := @HMouseUp; C.OnMouseMove := @HMouseMove;
    C.OnMouseEnter := @HEnter; C.OnMouseLeave := @HLeave; C.OnClick := @HClick;
    C.OnKeyDown := @HKeyDown; C.OnKeyUp := @HKeyUp; C.OnUTF8KeyPress := @HUTF8;
    C.FMouseDown(mbLeft, [], P11X, P11Y); AssertTrue('SpinEdit OnMouseDown', FDown);
    C.FMouseUp(mbLeft, [], P11X, P11Y);   AssertTrue('SpinEdit OnMouseUp', FUp);
    C.FMouseMove([], P11X, P11Y);         AssertTrue('SpinEdit OnMouseMove', FMove);
    C.FMouseEnter;                        AssertTrue('SpinEdit OnMouseEnter', FEnter);
    C.FMouseLeave;                        AssertTrue('SpinEdit OnMouseLeave', FLeave);
    C.Click;                              AssertTrue('SpinEdit OnClick', FClick);
    K := VK_F1; C.FKeyDown(K, []);        AssertTrue('SpinEdit OnKeyDown', FKeyDown);
    K := VK_F1; C.FKeyUp(K, []);          AssertTrue('SpinEdit OnKeyUp', FKeyUp);
    U := '1'; C.FUTF8(U);                 AssertTrue('SpinEdit OnUTF8KeyPress', FUTF8);
  finally
    C.Free;
  end;
end;

procedure TEventFiringMatrixTest.ComboBox_All;
var C: TCmbAcc; K: Word; U: TUTF8Char;
begin
  C := TCmbAcc.Create(nil);
  try
    C.Enabled := True;
    Reset;
    C.OnMouseDown := @HMouseDown; C.OnMouseUp := @HMouseUp; C.OnMouseMove := @HMouseMove;
    C.OnMouseEnter := @HEnter; C.OnMouseLeave := @HLeave; C.OnClick := @HClick;
    C.OnKeyDown := @HKeyDown; C.OnKeyUp := @HKeyUp; C.OnUTF8KeyPress := @HUTF8;
    C.FMouseDown(mbLeft, [], P11X, P11Y); AssertTrue('ComboBox OnMouseDown', FDown);
    C.FMouseUp(mbLeft, [], P11X, P11Y);   AssertTrue('ComboBox OnMouseUp', FUp);
    C.FMouseMove([], P11X, P11Y);         AssertTrue('ComboBox OnMouseMove', FMove);
    C.FMouseEnter;                        AssertTrue('ComboBox OnMouseEnter', FEnter);
    C.FMouseLeave;                        AssertTrue('ComboBox OnMouseLeave', FLeave);
    C.Click;                              AssertTrue('ComboBox OnClick', FClick);
    K := VK_F1; C.FKeyDown(K, []);        AssertTrue('ComboBox OnKeyDown', FKeyDown);
    K := VK_F1; C.FKeyUp(K, []);          AssertTrue('ComboBox OnKeyUp', FKeyUp);
    U := 'a'; C.FUTF8(U);                 AssertTrue('ComboBox OnUTF8KeyPress', FUTF8);
  finally
    C.Free;
  end;
end;

procedure TEventFiringMatrixTest.CheckBox_All;
var C: TChkAcc; K: Word;
begin
  C := TChkAcc.Create(nil);
  try
    C.Enabled := True;
    Reset;
    C.OnMouseDown := @HMouseDown; C.OnMouseUp := @HMouseUp; C.OnMouseMove := @HMouseMove;
    C.OnMouseEnter := @HEnter; C.OnMouseLeave := @HLeave; C.OnClick := @HClick;
    C.OnKeyDown := @HKeyDown; C.OnKeyUp := @HKeyUp;
    C.FMouseDown(mbLeft, [], P11X, P11Y); AssertTrue('CheckBox OnMouseDown', FDown);
    C.FMouseUp(mbLeft, [], P11X, P11Y);   AssertTrue('CheckBox OnMouseUp', FUp);
    C.FMouseMove([], P11X, P11Y);         AssertTrue('CheckBox OnMouseMove', FMove);
    C.FMouseEnter;                        AssertTrue('CheckBox OnMouseEnter', FEnter);
    C.FMouseLeave;                        AssertTrue('CheckBox OnMouseLeave', FLeave);
    C.Click;                              AssertTrue('CheckBox OnClick', FClick);
    K := VK_F1; C.FKeyDown(K, []);        AssertTrue('CheckBox OnKeyDown', FKeyDown);
    K := VK_F1; C.FKeyUp(K, []);          AssertTrue('CheckBox OnKeyUp', FKeyUp);
  finally
    C.Free;
  end;
end;

procedure TEventFiringMatrixTest.RadioButton_All;
var C: TRadAcc; K: Word;
begin
  C := TRadAcc.Create(nil);
  try
    C.Enabled := True;
    Reset;
    C.OnMouseDown := @HMouseDown; C.OnMouseUp := @HMouseUp; C.OnMouseMove := @HMouseMove;
    C.OnMouseEnter := @HEnter; C.OnMouseLeave := @HLeave; C.OnClick := @HClick;
    C.OnKeyDown := @HKeyDown; C.OnKeyUp := @HKeyUp;
    C.FMouseDown(mbLeft, [], P11X, P11Y); AssertTrue('RadioButton OnMouseDown', FDown);
    C.FMouseUp(mbLeft, [], P11X, P11Y);   AssertTrue('RadioButton OnMouseUp', FUp);
    C.FMouseMove([], P11X, P11Y);         AssertTrue('RadioButton OnMouseMove', FMove);
    C.FMouseEnter;                        AssertTrue('RadioButton OnMouseEnter', FEnter);
    C.FMouseLeave;                        AssertTrue('RadioButton OnMouseLeave', FLeave);
    C.Click;                              AssertTrue('RadioButton OnClick', FClick);
    K := VK_F1; C.FKeyDown(K, []);        AssertTrue('RadioButton OnKeyDown', FKeyDown);
    K := VK_F1; C.FKeyUp(K, []);          AssertTrue('RadioButton OnKeyUp', FKeyUp);
  finally
    C.Free;
  end;
end;

procedure TEventFiringMatrixTest.ListBox_All;
var C: TLstAcc; K: Word;
begin
  C := TLstAcc.Create(nil);
  try
    C.Enabled := True;
    Reset;
    C.OnMouseDown := @HMouseDown; C.OnMouseUp := @HMouseUp; C.OnMouseMove := @HMouseMove;
    C.OnMouseEnter := @HEnter; C.OnMouseLeave := @HLeave; C.OnClick := @HClick;
    C.OnKeyDown := @HKeyDown; C.OnKeyUp := @HKeyUp;
    C.FMouseDown(mbLeft, [], P11X, P11Y); AssertTrue('ListBox OnMouseDown', FDown);
    C.FMouseUp(mbLeft, [], P11X, P11Y);   AssertTrue('ListBox OnMouseUp', FUp);
    C.FMouseMove([], P11X, P11Y);         AssertTrue('ListBox OnMouseMove', FMove);
    C.FMouseEnter;                        AssertTrue('ListBox OnMouseEnter', FEnter);
    C.FMouseLeave;                        AssertTrue('ListBox OnMouseLeave', FLeave);
    C.Click;                              AssertTrue('ListBox OnClick', FClick);
    K := VK_F1; C.FKeyDown(K, []);        AssertTrue('ListBox OnKeyDown', FKeyDown);
    K := VK_F1; C.FKeyUp(K, []);          AssertTrue('ListBox OnKeyUp', FKeyUp);
  finally
    C.Free;
  end;
end;

procedure TEventFiringMatrixTest.TabControl_All;
var C: TTabAcc; K: Word;
begin
  C := TTabAcc.Create(nil);
  try
    C.Enabled := True;
    Reset;
    C.OnMouseDown := @HMouseDown; C.OnMouseUp := @HMouseUp; C.OnMouseMove := @HMouseMove;
    C.OnMouseEnter := @HEnter; C.OnMouseLeave := @HLeave; C.OnClick := @HClick;
    C.OnKeyDown := @HKeyDown; C.OnKeyUp := @HKeyUp;
    C.FMouseDown(mbLeft, [], P11X, P11Y); AssertTrue('TabControl OnMouseDown', FDown);
    C.FMouseUp(mbLeft, [], P11X, P11Y);   AssertTrue('TabControl OnMouseUp', FUp);
    C.FMouseMove([], P11X, P11Y);         AssertTrue('TabControl OnMouseMove', FMove);
    C.FMouseEnter;                        AssertTrue('TabControl OnMouseEnter', FEnter);
    C.FMouseLeave;                        AssertTrue('TabControl OnMouseLeave', FLeave);
    C.Click;                              AssertTrue('TabControl OnClick', FClick);
    K := VK_F1; C.FKeyDown(K, []);        AssertTrue('TabControl OnKeyDown', FKeyDown);
    K := VK_F1; C.FKeyUp(K, []);          AssertTrue('TabControl OnKeyUp', FKeyUp);
  finally
    C.Free;
  end;
end;

procedure TEventFiringMatrixTest.GroupBox_All;
var C: TGrpAcc; K: Word;
begin
  C := TGrpAcc.Create(nil);
  try
    C.Enabled := True;
    Reset;
    C.OnMouseDown := @HMouseDown; C.OnMouseUp := @HMouseUp; C.OnMouseMove := @HMouseMove;
    C.OnMouseEnter := @HEnter; C.OnMouseLeave := @HLeave; C.OnClick := @HClick;
    C.OnKeyDown := @HKeyDown; C.OnKeyUp := @HKeyUp;
    C.FMouseDown(mbLeft, [], P11X, P11Y); AssertTrue('GroupBox OnMouseDown', FDown);
    C.FMouseUp(mbLeft, [], P11X, P11Y);   AssertTrue('GroupBox OnMouseUp', FUp);
    C.FMouseMove([], P11X, P11Y);         AssertTrue('GroupBox OnMouseMove', FMove);
    C.FMouseEnter;                        AssertTrue('GroupBox OnMouseEnter', FEnter);
    C.FMouseLeave;                        AssertTrue('GroupBox OnMouseLeave', FLeave);
    C.Click;                              AssertTrue('GroupBox OnClick', FClick);
    K := VK_F1; C.FKeyDown(K, []);        AssertTrue('GroupBox OnKeyDown', FKeyDown);
    K := VK_F1; C.FKeyUp(K, []);          AssertTrue('GroupBox OnKeyUp', FKeyUp);
  finally
    C.Free;
  end;
end;

procedure TEventFiringMatrixTest.Panel_All;
var C: TPnlAcc; K: Word;
begin
  C := TPnlAcc.Create(nil);
  try
    C.Enabled := True;
    Reset;
    C.OnMouseDown := @HMouseDown; C.OnMouseUp := @HMouseUp; C.OnMouseMove := @HMouseMove;
    C.OnMouseEnter := @HEnter; C.OnMouseLeave := @HLeave; C.OnClick := @HClick;
    C.OnKeyDown := @HKeyDown; C.OnKeyUp := @HKeyUp;
    C.FMouseDown(mbLeft, [], P11X, P11Y); AssertTrue('Panel OnMouseDown', FDown);
    C.FMouseUp(mbLeft, [], P11X, P11Y);   AssertTrue('Panel OnMouseUp', FUp);
    C.FMouseMove([], P11X, P11Y);         AssertTrue('Panel OnMouseMove', FMove);
    C.FMouseEnter;                        AssertTrue('Panel OnMouseEnter', FEnter);
    C.FMouseLeave;                        AssertTrue('Panel OnMouseLeave', FLeave);
    C.Click;                              AssertTrue('Panel OnClick', FClick);
    K := VK_F1; C.FKeyDown(K, []);        AssertTrue('Panel OnKeyDown', FKeyDown);
    K := VK_F1; C.FKeyUp(K, []);          AssertTrue('Panel OnKeyUp', FKeyUp);
  finally
    C.Free;
  end;
end;

procedure TEventFiringMatrixTest.ScrollBar_All;
var C: TSbAcc; K: Word;
begin
  C := TSbAcc.Create(nil);
  try
    C.Enabled := True;
    Reset;
    C.OnMouseDown := @HMouseDown; C.OnMouseUp := @HMouseUp; C.OnMouseMove := @HMouseMove;
    C.OnMouseEnter := @HEnter; C.OnMouseLeave := @HLeave; C.OnClick := @HClick;
    C.OnKeyDown := @HKeyDown; C.OnKeyUp := @HKeyUp;
    C.FMouseDown(mbLeft, [], P11X, P11Y); AssertTrue('ScrollBar OnMouseDown', FDown);
    C.FMouseUp(mbLeft, [], P11X, P11Y);   AssertTrue('ScrollBar OnMouseUp', FUp);
    C.FMouseMove([], P11X, P11Y);         AssertTrue('ScrollBar OnMouseMove', FMove);
    C.FMouseEnter;                        AssertTrue('ScrollBar OnMouseEnter', FEnter);
    C.FMouseLeave;                        AssertTrue('ScrollBar OnMouseLeave', FLeave);
    C.Click;                              AssertTrue('ScrollBar OnClick', FClick);
    K := VK_F1; C.FKeyDown(K, []);        AssertTrue('ScrollBar OnKeyDown', FKeyDown);
    K := VK_F1; C.FKeyUp(K, []);          AssertTrue('ScrollBar OnKeyUp', FKeyUp);
  finally
    C.Free;
  end;
end;

procedure TEventFiringMatrixTest.TrackBar_All;
var C: TTbAcc; K: Word;
begin
  C := TTbAcc.Create(nil);
  try
    C.Enabled := True;
    Reset;
    C.OnMouseDown := @HMouseDown; C.OnMouseUp := @HMouseUp; C.OnMouseMove := @HMouseMove;
    C.OnMouseEnter := @HEnter; C.OnMouseLeave := @HLeave; C.OnClick := @HClick;
    C.OnKeyDown := @HKeyDown; C.OnKeyUp := @HKeyUp;
    C.FMouseDown(mbLeft, [], P11X, P11Y); AssertTrue('TrackBar OnMouseDown', FDown);
    C.FMouseUp(mbLeft, [], P11X, P11Y);   AssertTrue('TrackBar OnMouseUp', FUp);
    C.FMouseMove([], P11X, P11Y);         AssertTrue('TrackBar OnMouseMove', FMove);
    C.FMouseEnter;                        AssertTrue('TrackBar OnMouseEnter', FEnter);
    C.FMouseLeave;                        AssertTrue('TrackBar OnMouseLeave', FLeave);
    C.Click;                              AssertTrue('TrackBar OnClick', FClick);
    K := VK_F1; C.FKeyDown(K, []);        AssertTrue('TrackBar OnKeyDown', FKeyDown);
    K := VK_F1; C.FKeyUp(K, []);          AssertTrue('TrackBar OnKeyUp', FKeyUp);
  finally
    C.Free;
  end;
end;

procedure TEventFiringMatrixTest.ToggleSwitch_All;
var C: TTglAcc; K: Word;
begin
  C := TTglAcc.Create(nil);
  try
    C.Enabled := True;
    Reset;
    C.OnMouseDown := @HMouseDown; C.OnMouseUp := @HMouseUp; C.OnMouseMove := @HMouseMove;
    C.OnMouseEnter := @HEnter; C.OnMouseLeave := @HLeave; C.OnClick := @HClick;
    C.OnKeyDown := @HKeyDown; C.OnKeyUp := @HKeyUp;
    C.FMouseDown(mbLeft, [], P11X, P11Y); AssertTrue('ToggleSwitch OnMouseDown', FDown);
    C.FMouseUp(mbLeft, [], P11X, P11Y);   AssertTrue('ToggleSwitch OnMouseUp', FUp);
    C.FMouseMove([], P11X, P11Y);         AssertTrue('ToggleSwitch OnMouseMove', FMove);
    C.FMouseEnter;                        AssertTrue('ToggleSwitch OnMouseEnter', FEnter);
    C.FMouseLeave;                        AssertTrue('ToggleSwitch OnMouseLeave', FLeave);
    C.Click;                              AssertTrue('ToggleSwitch OnClick', FClick);
    K := VK_F1; C.FKeyDown(K, []);        AssertTrue('ToggleSwitch OnKeyDown', FKeyDown);
    K := VK_F1; C.FKeyUp(K, []);          AssertTrue('ToggleSwitch OnKeyUp', FKeyUp);
  finally
    C.Free;
  end;
end;

initialization
  RegisterTest(TEventFiringMatrixTest);
end.
