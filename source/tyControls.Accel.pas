unit tyControls.Accel;
{$mode objfpc}{$H+}

{ Shared accelerator (mnemonic) facility, used by both the menu and the caption controls:
  - TyParseMnemonic: strip a caption's '&', report the mnemonic char + position.
  - A single app-wide Alt-state watcher: TyAccelShowing is true while Alt is held; controls
    register to be repainted when it flips, so the mnemonic underline appears/disappears live.
  - TyIsAccelKey: the LCL DialogChar match (Alt-only gate + char compare). }

interface
uses Classes, Controls, LMessages;

{ Parse a caption mnemonic. A single '&' marks the NEXT char and is removed from the display;
  '&&' -> literal '&'; the first single '&' wins; the mnemonic char is returned upper-cased
  (#0 = none); AMnemonicPos is its 1-based index in ADisplay (0 = none). }
function TyParseMnemonic(const ACaption: string; out ADisplay: string; out AMnemonicPos: Integer): Char;

{ True while Alt is currently held (the "show access keys" cue). }
function TyAccelShowing: Boolean;

{ AMnemonicPos when TyAccelShowing, else 0 — pass to TTyPainter.DrawText to gate the underline. }
function TyAccelGatePos(AMnemonicPos: Integer): Integer;

{ Register/unregister a control to be Invalidate()d when the Alt-held state flips. The single
  Application input hook is installed on the first registration, removed when the registry empties. }
procedure TyAccelRegister(AControl: TControl);
procedure TyAccelUnregister(AControl: TControl);

{ True iff Message is Alt+<the caption's mnemonic> (Alt-only modifier gate + LCL IsAccel, which
  treats CharCode as the translated character — the correctness the menu's DialogChar fix established). }
function TyIsAccelKey(const Message: TLMKey; const ACaption: string): Boolean;

implementation
uses SysUtils, Forms, ExtCtrls, LCLType, LCLIntf, LCLProc;   // Forms: IsAccel + KeyDataToShiftState

type
  { Host for the poll timer's OnTimer. We POLL Alt (not Application.AddOnUserInputHandler) because
    TOnUserInputEvent's signature varies by Lazarus version (Msg: Cardinal vs var Msg: TLMessage),
    which breaks cross-version builds; a TTimer's OnTimer is a plain TNotifyEvent, stable everywhere. }
  TTyAccelWatcher = class
    procedure Tick(Sender: TObject);
  end;

const
  TyAccelPollMs = 75;   // Alt-state poll interval (ms): responsive cue without busy-waiting

var
  GShowing: Boolean = False;
  GFinalized: Boolean = False;
  GRegistry: TFPList = nil;
  GWatcher: TTyAccelWatcher = nil;
  GTimer: TTimer = nil;

function TyParseMnemonic(const ACaption: string; out ADisplay: string; out AMnemonicPos: Integer): Char;
var i, n: Integer;
begin
  Result := #0; AMnemonicPos := 0; ADisplay := '';
  n := Length(ACaption); i := 1;
  while i <= n do
  begin
    if ACaption[i] = '&' then
    begin
      if (i < n) and (ACaption[i + 1] = '&') then
        begin ADisplay := ADisplay + '&'; Inc(i, 2); Continue; end
      else if i < n then
      begin
        if Result = #0 then
          begin Result := UpCase(ACaption[i + 1]); AMnemonicPos := Length(ADisplay) + 1; end;
        Inc(i); Continue;
      end
      else Break;
    end;
    ADisplay := ADisplay + ACaption[i]; Inc(i);
  end;
end;

function TyAccelShowing: Boolean;
begin Result := GShowing; end;

function TyAccelGatePos(AMnemonicPos: Integer): Integer;
begin if GShowing then Result := AMnemonicPos else Result := 0; end;

procedure TTyAccelWatcher.Tick(Sender: TObject);
var alt: Boolean; i: Integer;
begin
  // Poll the Alt key (GetKeyState high bit = down). Repaint registered controls only when it flips.
  alt := GetKeyState(VK_MENU) < 0;
  if alt = GShowing then Exit;
  GShowing := alt;
  if GRegistry <> nil then
    for i := 0 to GRegistry.Count - 1 do
      TControl(GRegistry[i]).Invalidate;
end;

procedure TyAccelRegister(AControl: TControl);
begin
  if (AControl = nil) or GFinalized then Exit;
  if csDesigning in AControl.ComponentState then Exit;   // never hook the IDE design surface
  if GRegistry = nil then GRegistry := TFPList.Create;
  if GRegistry.IndexOf(AControl) < 0 then GRegistry.Add(AControl);
  if GTimer = nil then
  begin
    GWatcher := TTyAccelWatcher.Create;
    GTimer := TTimer.Create(nil);
    GTimer.Interval := TyAccelPollMs;
    GTimer.OnTimer := @GWatcher.Tick;
  end;
  GTimer.Enabled := True;   // (re)start polling while at least one control is registered
end;

procedure TyAccelUnregister(AControl: TControl);
begin
  if GFinalized or (GRegistry = nil) then Exit;
  GRegistry.Remove(AControl);
  if (GTimer <> nil) and (GRegistry.Count = 0) then
    GTimer.Enabled := False;   // pause polling when no controls remain
end;

function TyIsAccelKey(const Message: TLMKey; const ACaption: string): Boolean;
begin
  Result := (KeyDataToShiftState(Message.KeyData) * [ssShift, ssCtrl, ssAlt] = [ssAlt])
            and IsAccel(Message.CharCode, ACaption);
end;

finalization
  // Mark finalized FIRST: control destructors run AFTER this unit (we use Forms, so the widgetset
  // finalizes LATER) and call TyAccelUnregister — GFinalized makes that a safe no-op rather than
  // a use-after-free on the freed GRegistry.
  GFinalized := True;
  FreeAndNil(GTimer);     // safe: this unit finalizes while the widgetset is still up
  FreeAndNil(GWatcher);
  FreeAndNil(GRegistry);
end.
