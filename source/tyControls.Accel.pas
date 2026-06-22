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
uses Forms, LCLType, LCLIntf, LCLProc;

type
  { A method-of-object host for Application.AddOnUserInputHandler (which needs an of-object event). }
  TTyAccelWatcher = class
    procedure Input(Sender: TObject; Msg: Cardinal);
  end;

var
  GShowing: Boolean = False;
  GRegistry: TFPList = nil;
  GWatcher: TTyAccelWatcher = nil;
  GHooked: Boolean = False;

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

procedure TTyAccelWatcher.Input(Sender: TObject; Msg: Cardinal);
var alt: Boolean; i: Integer;
begin
  // GetKeyState high bit (negative) = key down. Fires on Alt press/release + mouse input.
  alt := GetKeyState(VK_MENU) < 0;
  if alt = GShowing then Exit;
  GShowing := alt;
  if GRegistry <> nil then
    for i := 0 to GRegistry.Count - 1 do
      TControl(GRegistry[i]).Invalidate;
end;

procedure TyAccelRegister(AControl: TControl);
begin
  if AControl = nil then Exit;
  if GRegistry = nil then GRegistry := TFPList.Create;
  if GRegistry.IndexOf(AControl) < 0 then GRegistry.Add(AControl);
  if not GHooked then
  begin
    if GWatcher = nil then GWatcher := TTyAccelWatcher.Create;
    Application.AddOnUserInputHandler(@GWatcher.Input);
    GHooked := True;
  end;
end;

procedure TyAccelUnregister(AControl: TControl);
begin
  if GRegistry <> nil then GRegistry.Remove(AControl);
  if GHooked and ((GRegistry = nil) or (GRegistry.Count = 0)) then
  begin
    Application.RemoveOnUserInputHandler(@GWatcher.Input);
    GHooked := False;
  end;
end;

function TyIsAccelKey(const Message: TLMKey; const ACaption: string): Boolean;
begin
  Result := (KeyDataToShiftState(Message.KeyData) * [ssShift, ssCtrl, ssAlt] = [ssAlt])
            and IsAccel(Message.CharCode, ACaption);
end;

finalization
  if GHooked and (GWatcher <> nil) then Application.RemoveOnUserInputHandler(@GWatcher.Input);
  GWatcher.Free;
  GRegistry.Free;
end.
