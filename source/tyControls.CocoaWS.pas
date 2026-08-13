unit tyControls.CocoaWS;
{$mode objfpc}{$H+}

{ Cocoa-only: proper macOS IME (CJK composition) for the self-drawn text controls.

  LCL-Cocoa decides AT HANDLE-CREATION TIME whether a TCustomControl gets an IME-capable native view
  (TCocoaFullControlEdit) by sending the control LM_IM_COMPOSITION and reading back an
  ICocoaIMEControl handler pointer (cocoawscommon.pas: getControlIMEHandler / SendIMCompostionMessage).
  TTyEdit / TTyMemo answer that message with an instance of THIS handler, which then drives the control
  while a composition is in progress: it shows the intermediate (marked) pinyin INLINE at the caret and
  hands the caret rect back through IMEGetTextBound, so the candidate window follows the caret instead
  of LCL-Cocoa's hard-coded bottom-left corner (cocoacustomcontrol.pas firstRectForCharacterRange).

  The handler is a SEPARATE object (not the control): the contract is a CORBA interface and the controls
  are COM-interface classes, so they cannot also implement it -- the reference implementation (SynEdit's
  LazSynImeCocoa) splits it the same way. It drives the control through ITyImeEditable (tyControls.TextMenu).

  The whole unit is gated on {$IFDEF LCLCocoa}: off Cocoa it is an EMPTY unit, like the other WS units --
  listed in the package but referencing nothing off macOS. }

interface

{$IFDEF LCLCocoa}
{$modeswitch objectivec2}   // required to use CocoaFullControlEdit
{$interfaces corba}          // ICocoaIMEControl is a CORBA (non-refcounted, GUID) interface

uses
  Types, Controls,
  CocoaFullControlEdit,      // ICocoaIMEControl + TCocoaIMEParameters
  tyControls.TextMenu;       // ITyImeEditable

type
  { Bridges macOS NSTextInputClient composition (via TCocoaFullControlEdit) to a TTyEdit/TTyMemo.
    Created by the control in its constructor, returned from its LM_IM_COMPOSITION handler. }
  TTyCocoaImeHandler = class(TObject, ICocoaIMEControl)
  private
    FTarget: ITyImeEditable;   // the control it drives (COM field; the control's _AddRef is a no-op)
    FStart: Integer;           // flat codepoint index where the current composition began
    FLen: Integer;             // codepoint length currently occupying [FStart, FStart+FLen)
  public
    constructor Create(const ATarget: ITyImeEditable);
    procedure IMESessionBegin;
    procedure IMESessionEnd;
    procedure IMEUpdateIntermediateText(var params: TCocoaIMEParameters);
    procedure IMEInsertFinalText(var params: TCocoaIMEParameters);
    function  IMEGetTextBound(var params: TCocoaIMEParameters): TRect;
  end;
{$ENDIF}

implementation

{$IFDEF LCLCocoa}

constructor TTyCocoaImeHandler.Create(const ATarget: ITyImeEditable);
begin
  inherited Create;
  FTarget := ATarget;
end;

procedure TTyCocoaImeHandler.IMESessionBegin;
begin
  if (FTarget = nil) or FTarget.ImeIsReadOnly then Exit;
  FTarget.ImeSessionBegin;              // one undo step + suspend per-keystroke undo for the session
  FStart := FTarget.ImeCaretIndex;      // anchor the composition at the caret
  FLen := 0;
end;

procedure TTyCocoaImeHandler.IMESessionEnd;
begin
  FLen := 0;
  if FTarget <> nil then FTarget.ImeSessionEnd;   // release the suspend + OnChange
end;

procedure TTyCocoaImeHandler.IMEUpdateIntermediateText(var params: TCocoaIMEParameters);
begin
  if (FTarget = nil) or FTarget.ImeIsReadOnly then Exit;
  // Replace the span we put down last with the new marked text. Empty text = the IME cancelled the
  // composition (IMESessionEnd follows) -- which just removes the span.
  FTarget.ImeReplace(FStart, FLen, params.text);
  if params.textCharLength > 0 then FLen := params.textCharLength else FLen := 0;
end;

procedure TTyCocoaImeHandler.IMEInsertFinalText(var params: TCocoaIMEParameters);
begin
  if (FTarget = nil) or FTarget.ImeIsReadOnly then Exit;
  // Drop the intermediate span and insert the committed text in its place (IMESessionEnd follows).
  FTarget.ImeReplace(FStart, FLen, params.text);
  FLen := 0;
end;

function TTyCocoaImeHandler.IMEGetTextBound(var params: TCocoaIMEParameters): TRect;
var
  ctl: TWinControl;
  r: TRect;
  tl, br: TPoint;
begin
  Result := Rect(0, 0, 0, 0);
  if FTarget = nil then Exit;
  r := FTarget.ImeCaretBoundClient;              // client device px; (0,0,0,0) = unfocused -> decline
  if (r.Right = 0) and (r.Bottom = 0) then Exit;
  ctl := FTarget.ImeTargetControl;
  if ctl = nil then Exit;
  // ClientToScreen is point-based in LCL -> convert the two corners (LCL-Cocoa flips to NS coords).
  tl := ctl.ClientToScreen(r.TopLeft);
  br := ctl.ClientToScreen(r.BottomRight);
  Result := Rect(tl.x, tl.y, br.x, br.y);
end;
{$ENDIF}

end.
