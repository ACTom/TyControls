unit tbpick;
{ Ctrl+click in the preview: which control was clicked, by typeKey and variant, so the editor
  can go to its rule.

  Why WindowProc: every mouse message a control gets ends in its WindowProc -- a windowed
  control's from the widgetset, a graphic control's from its parent, which forwards it with
  Perform (TWinControl.IsControlMouseMsg), and Perform calls WindowProc. So one hook per
  control catches them all, without an event on every control and without touching the
  library. The hook takes a left press (or double click) made with Ctrl held -- Command on a
  Mac, where Ctrl+click is the context-menu gesture -- and the release that follows it; the
  control never sees either: no press, no focus, no click, no checkbox ticked. Everything
  else is handed on untouched. A swallowed press captures no mouse, so its release may go
  to a control that is not hooked (the editor) and never come: the next press of a hooked
  control's own stops waiting for it. The second press of a Ctrl+double click is the same
  gesture as the first: swallowed, and not picked twice.

  Who was clicked: the control the message came to, or, when that is a container, the
  deepest control under the point -- disabled ones included (a disabled graphic control
  gets no message of its own: its parent does) -- then up to the nearest control with a
  typeKey (a control inside a composite is answered by its nearest Ty ancestor, which may
  be the inner Ty control itself: it has a typeKey of its own). Sub-parts drawn inside a
  control (a tab, a scroll thumb) are the whole control's typeKey.

  Unhooking: a hook puts the old WindowProc back only while the control still has ours (if
  something hooked it after us, it is left alone). A control freed before its hook (the
  sample window) tells the hook through FreeNotification, and the hook then forgets it. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, LMessages, LCLType, LCLIntf, Forms;

type
  TTbPickEvent = procedure(Sender: TObject; const ATypeKey, AStyleClass: string) of object;

  TTbPicker = class(TComponent)
  private
    FHooks: TFPList;
    FSwallowUp: Boolean;           { a pick's press was swallowed: so is the release after it }
    FLastPressPicked: Boolean;     { the last left press on a hooked control was a pick }
    FOnPick: TTbPickEvent;
    procedure HookOne(AControl: TControl);
    procedure Pick(AControl: TControl; const APos: TPoint);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure HookTree(ARoot: TWinControl);   { ARoot and every control under it, once each }
    procedure UnhookAll;
    function HookCount: Integer;              { FOR THE TESTS }
    property OnPick: TTbPickEvent read FOnPick write FOnPick;
  end;

{ a left press made to go to a rule: Ctrl held (Command too on a Mac) }
function TbIsPickMessage(const AMsg: TLMessage): Boolean;
{ the deepest control at APos (AControl's client coordinates), disabled ones too, then up to
  the nearest one with a typeKey; nil when none }
function TbPickTarget(AControl: TControl; const APos: TPoint): TControl;

implementation

uses
  tyControls.Base;

type
  TTbPickHook = class(TComponent)
  private
    FControl: TControl;
    FOld: TWndMethod;
    FMine: TWndMethod;
    FPicker: TTbPicker;
    procedure WndProc(var AMsg: TLMessage);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

function TbIsPickMessage(const AMsg: TLMessage): Boolean;
begin
  Result := (TLMMouse(AMsg).Keys and MK_CONTROL) <> 0;
  {$IFDEF DARWIN}
  { Ctrl+click is the context-menu gesture on a Mac; Command+click is what reads as "go to" }
  if not Result then
    Result := ssMeta in GetKeyShiftState;
  {$ENDIF}
end;

function TbPickTarget(AControl: TControl; const APos: TPoint): TControl;
var
  sub: TControl;
begin
  Result := AControl;
  if AControl is TWinControl then
  begin
    { a disabled graphic child gets no mouse message of its own: its parent does }
    sub := TWinControl(AControl).ControlAtPos(APos,
      [capfAllowDisabled, capfAllowWinControls, capfRecursive]);
    if sub <> nil then
      Result := sub;
  end;
  while (Result <> nil) and not Supports(Result, ITyStyleable) do
    Result := Result.Parent;
end;

{ ---- TTbPickHook ---- }

procedure TTbPickHook.WndProc(var AMsg: TLMessage);
begin
  if (AMsg.Msg = LM_LBUTTONDOWN) or (AMsg.Msg = LM_LBUTTONDBLCLK) then
  begin
    if TbIsPickMessage(AMsg) then
    begin
      FPicker.FSwallowUp := True;
      { the second press of a double click whose first one was a pick is the same gesture:
        swallowed, not picked again (it would go to the next rule) }
      if (AMsg.Msg = LM_LBUTTONDOWN) or not FPicker.FLastPressPicked then
        FPicker.Pick(FControl, Point(TLMMouse(AMsg).XPos, TLMMouse(AMsg).YPos));
      FPicker.FLastPressPicked := True;
      AMsg.Result := 0;
      Exit;                      { the control never sees it: no press, no focus, no click }
    end;
    { A press of the control's own. The release of a pick that went elsewhere -- over the
      editor, outside the window (a swallowed press captures nothing, so the release goes
      wherever the mouse is) -- never came, and must not be waited for any more: this
      press's release is this press's. }
    FPicker.FSwallowUp := False;
    FPicker.FLastPressPicked := False;
  end;
  if (AMsg.Msg = LM_LBUTTONUP) and FPicker.FSwallowUp then
  begin
    FPicker.FSwallowUp := False;
    AMsg.Result := 0;
    Exit;
  end;
  FOld(AMsg);
end;

procedure TTbPickHook.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  { the control goes first (the sample window): forget it, never touch it again }
  if (Operation = opRemove) and (AComponent = FControl) then
    FControl := nil;
end;

{ ---- TTbPicker ---- }

constructor TTbPicker.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHooks := TFPList.Create;
end;

destructor TTbPicker.Destroy;
begin
  UnhookAll;
  FreeAndNil(FHooks);
  inherited Destroy;
end;

procedure TTbPicker.HookOne(AControl: TControl);
var
  i: Integer;
  hook: TTbPickHook;
begin
  for i := 0 to FHooks.Count - 1 do
    if TTbPickHook(FHooks[i]).FControl = AControl then
      Exit;
  hook := TTbPickHook.Create(nil);
  hook.FPicker := Self;
  hook.FControl := AControl;
  hook.FOld := AControl.WindowProc;
  hook.FMine := @hook.WndProc;
  AControl.WindowProc := hook.FMine;
  AControl.FreeNotification(hook);
  FHooks.Add(hook);
end;

procedure TTbPicker.HookTree(ARoot: TWinControl);

  procedure Walk(AParent: TWinControl);
  var
    i: Integer;
  begin
    for i := 0 to AParent.ControlCount - 1 do
    begin
      HookOne(AParent.Controls[i]);
      if AParent.Controls[i] is TWinControl then
        Walk(TWinControl(AParent.Controls[i]));
    end;
  end;

begin
  if ARoot = nil then Exit;
  HookOne(ARoot);
  Walk(ARoot);
end;

procedure TTbPicker.UnhookAll;
var
  i: Integer;
  hook: TTbPickHook;
  cur: TWndMethod;
begin
  if FHooks = nil then Exit;
  for i := FHooks.Count - 1 downto 0 do
  begin
    hook := TTbPickHook(FHooks[i]);
    if hook.FControl <> nil then
    begin
      cur := hook.FControl.WindowProc;
      { put the old one back only while it is still ours: someone who hooked it after us
        keeps theirs }
      if (TMethod(cur).Code = TMethod(hook.FMine).Code)
         and (TMethod(cur).Data = TMethod(hook.FMine).Data) then
        hook.FControl.WindowProc := hook.FOld;
      hook.FControl.RemoveFreeNotification(hook);
      hook.FControl := nil;
    end;
    hook.Free;
  end;
  FHooks.Clear;
  FSwallowUp := False;
  FLastPressPicked := False;
end;

function TTbPicker.HookCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to FHooks.Count - 1 do
    if TTbPickHook(FHooks[i]).FControl <> nil then
      Inc(Result);
end;

procedure TTbPicker.Pick(AControl: TControl; const APos: TPoint);
var
  t: TControl;
  key, cls: string;
begin
  if AControl = nil then Exit;
  t := TbPickTarget(AControl, APos);
  if (t = nil) or not Assigned(FOnPick) then Exit;
  key := (t as ITyStyleable).GetStyleTypeKey;
  if t is TTyCustomControl then
    cls := TTyCustomControl(t).StyleClass
  else if t is TTyGraphicControl then
    cls := TTyGraphicControl(t).StyleClass
  else
    cls := '';
  FOnPick(Self, key, cls);
end;

end.
