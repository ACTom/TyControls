{ Real-machine verification probe — destroying a FOCUSED TTyEdit descendant.

  Same road as gridverify / scrollverify / radiofocusverify: a real window, real handles,
  the real message path, an exit code. It exists because the defect it pins is invisible
  to the headless unit suite in TWO different ways, and one of them is worse than invisible.

  THE DEFECT (fixed; this probe is the regression witness).

    Freeing an edit that currently HOLDS FOCUS is not a passive teardown. TWinControl.Destroy
    calls RemoveFocus, the widgetset hands focus on, and the WM_KILLFOCUS that comes back is
    dispatched SYNCHRONOUSLY -- CM_EXIT -> DoExit -> OnExit -- from inside `inherited
    Destroy`. So ordinary code runs on the object while its own destructor is part-way
    through: TTyNumericEdit reformats the field on blur, and an application's OnExit handler
    that commits with `Edit.Text := ...` is the most obvious line anyone would write.

    tyControls.Edit.pas used to free the undo stack and the measuring bitmap BEFORE that
    inherited call, so the write landed in SetTextInternal -> BeginUndoStep ->
    FUndoStack.Push on freed memory: EAccessViolation.

  WHY IT NEEDS A PROBE OF ITS OWN.

    1. It only happens with REAL FOCUS. On a form that was never shown CanFocus is False,
       nothing ever holds focus, RemoveFocus has nothing to remove, and the whole path is
       skipped -- every assertion about it passes vacuously.

    2. The AV is raised inside the widgetset's WindowProc. It does NOT propagate back to
       whoever called Free, so no `try ... except` at the call site can see it. LCL's
       TApplication.HandleException catches it and calls ShowException -> a MODAL dialog.
       On a desktop the user gets an access-violation box while closing a form. In a
       console run there is nobody to dismiss it and the process blocks in ShowModal
       FOREVER, CPU flat, one thread. That is how TTyCurrencyEdit wedged the unit suite:
       it was the only edit whose DEFAULT value reaches the bug, because its currency
       symbol makes the grouped display differ from the raw edit form even at 0, where a
       plain TTyNumericEdit's `FText = AValue` short-circuit steps over it.

    tests/test.focus.tabstop.pas covers the same ground inside the unit suite, but it has
    to install an Application.OnException trap to do it -- otherwise a regression would
    wedge the runner instead of failing it. That trap is exactly what this probe does NOT
    install (use -trap to compare): run untrapped and a regression reproduces the USER'S
    symptom, a process that never comes back. So run this one under an external timeout.

  Usage: editteardownverify.exe [-trap]     exit code 0 = every check passed.
         A regression WITHOUT -trap does not return; treat a timeout as a failure. }
program editteardownverify;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, Controls, Classes, SysUtils, LCLType, LMessages,
  tyControls.Base, tyControls.Edit, tyControls.NumericEdit, tyControls.CurrencyEdit,
  tyControls.CalcEdit, tyControls.CalcCurrencyEdit, tyControls.TrackEdit;

type
  TEditClass = class of TTyEdit;

var
  Form: TForm;
  Park: TTyEdit;
  Checks: Integer = 0;
  Failures: Integer = 0;
  Trapped: string = '';
  Trap: Boolean = False;

procedure Say(const AMsg: string);
begin
  WriteLn(AMsg);
  Flush(Output);
end;

procedure Check(const AWhat: string; ACond: Boolean; const ADetail: string = '');
begin
  Inc(Checks);
  if ACond then
    Say('  PASS  ' + AWhat)
  else
  begin
    Inc(Failures);
    if ADetail <> '' then Say('  FAIL  ' + AWhat + '   [' + ADetail + ']')
    else Say('  FAIL  ' + AWhat);
  end;
end;

type
  THandlers = class
    procedure OnEx(Sender: TObject; E: Exception);
    procedure CommitOnExit(Sender: TObject);
  end;

procedure THandlers.OnEx(Sender: TObject; E: Exception);
begin
  if Trapped = '' then Trapped := E.ClassName + ': ' + E.Message;
end;

{ The ordinary application handler: commit the field on the way out. }
procedure THandlers.CommitOnExit(Sender: TObject);
begin
  TTyEdit(Sender).Text := 'committed on exit';
end;

var
  H: THandlers;

{ The lParam the widgetset packs a click position into. }
function MousePos(X, Y: Integer): PtrInt;
begin
  Result := PtrInt((Y shl 16) or (X and $FFFF));
end;

{ Build AClass on the visible form, optionally seed a value / an OnExit handler, focus it
  the way a user does (a real LM_LBUTTONDOWN), then FREE it while it still holds focus.
  AValue <> 0 seeds a grouped number, which is what makes the blur reformat actually
  CHANGE the string -- an unchanged write short-circuits and proves nothing. }
procedure Probe(AClass: TEditClass; const AWhat: string; AValue: Double; AHookExit: Boolean);
var
  e: TTyEdit;
  focused: Boolean;
begin
  Say('--- ' + AWhat + ' (' + AClass.ClassName + ') ---');
  Trapped := '';
  e := AClass.Create(Form);
  try
    e.Parent := Form;
    e.SetBounds(220, 60, 260, 28);
    if (AValue <> 0) and (e is TTyNumericEdit) then TTyNumericEdit(e).Value := AValue;
    if AHookExit then e.OnExit := @H.CommitOnExit;
    e.Visible := True;
    e.HandleNeeded;
    Application.ProcessMessages;

    if Park.CanFocus then Park.SetFocus;
    Application.ProcessMessages;

    Say('    text before click: "' + e.Text + '"');
    e.Perform(LM_LBUTTONDOWN, MK_LBUTTON, MousePos(e.Width div 4, e.Height div 2));
    Application.ProcessMessages;
    Say('    text after  click: "' + e.Text + '"');

    { The teardown path under test only runs for a control that REALLY holds focus. Assert
      it, or a regression could hide behind a probe that quietly never focused anything. }
    focused := Form.ActiveControl = e;
    Check(AWhat + ': the click focuses the edit (precondition for the teardown path)',
      focused, 'ActiveControl=' + Form.ActiveControl.ClassName);
  finally
    e.Free;          { <-- the whole point: freeing it FOCUSED }
  end;
  Application.ProcessMessages;
  Check(AWhat + ': freeing it while focused raises nothing',
    Trapped = '', Trapped);
end;

var
  i: Integer;
begin
  H := THandlers.Create;
  for i := 1 to ParamCount do
    if ParamStr(i) = '-trap' then Trap := True;

  Application.Initialize;
  if Trap then Application.OnException := @H.OnEx
  else Say('NOTE: running WITHOUT an exception trap -- a regression will HANG, not fail. '
         + 'Run under an external timeout.');

  Form := TForm.CreateNew(Application);
  { Off-screen but genuinely shown: CanFocus needs Visible all the way up. }
  Form.SetBounds(-4000, -4000, 640, 480);
  Form.Visible := True;
  Form.HandleNeeded;
  Park := TTyEdit.Create(Form);
  Park.Parent := Form;
  Park.SetBounds(8, 8, 160, 26);
  Park.HandleNeeded;
  Application.ProcessMessages;

  try
    { The general case FIRST -- it is the root, and it needs no numeric subclass at all. }
    Probe(TTyEdit, 'plain edit + OnExit that writes Text', 0, True);
    { The control the defect was reported on: no handler, no seeded value. Its currency
      symbol alone makes the blur reformat change the string. }
    Probe(TTyCurrencyEdit, 'currency edit at its DEFAULT value', 0, False);
    Probe(TTyCalcCurrencyEdit, 'calc-currency edit at its DEFAULT value', 0, False);
    { The rest of the family only reaches it holding a value whose grouped form differs
      from its raw form -- which is every realistic value above 999. }
    Probe(TTyNumericEdit, 'numeric edit holding a grouped value', 1234567.25, False);
    Probe(TTyCalcEdit, 'calc edit holding a grouped value', 1234567.25, False);
    Probe(TTyTrackEdit, 'track edit holding a value', 75, False);
    { And the same edits with an application handler on top. }
    Probe(TTyCurrencyEdit, 'currency edit + OnExit that writes Text', 1234.5, True);
  except
    on E: Exception do
    begin
      Inc(Failures);
      Say('  FAIL  exception escaped to the probe: ' + E.ClassName + ': ' + E.Message);
    end;
  end;

  Say('');
  Say(Format('%d checks, %d failures', [Checks, Failures]));
  if Failures = 0 then Halt(0) else Halt(1);
end.
