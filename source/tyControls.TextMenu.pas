unit tyControls.TextMenu;
{$mode objfpc}{$H+}
{ Shared right-click context menu + multi-click helpers for the text-editing controls.

  TTyEdit and TTyMemo expose the SAME public text-editing API but do not share a base
  class (one is single-line and prefix-sum based, the other is a multi-line line model),
  so anything they both need has to live somewhere neutral or be written twice. The default
  themed context menu is exactly that: identical items, identical enable/disable rules,
  identical show path. ITyTextEditActions is the narrow seam both controls implement, and
  TTyTextEditMenu builds/enables/shows the menu against it ONCE, here, rather than in each.

  The menu is a themed TTyPopupMenu (tyControls.Menu) -- NOT a raw LCL TPopupMenu -- so the
  default matches the rest of the library's chrome and the app's active theme. }
interface
uses
  Classes, SysUtils, Types, Controls, Menus, Clipbrd, LCLType,
  tyControls.Menu, tyControls.Controller, tyControls.StrConsts;

type
  { The text-editing actions + state a default context menu needs. Both TTyEdit and
    TTyMemo implement it; the method names are prefixed 'Te' so they never collide with,
    nor depend on the visibility of, the controls' own like-named members (TTyMemo's
    HasSelection is protected, TTyEdit's is public -- an interface must not care). Each
    control's implementation is a one-line delegate to the real method it already has. }
  ITyTextEditActions = interface
    ['{5B7F0C2E-7E42-4B9A-9C4D-2A1F6E3B8D71}']
    // The control the menu belongs to -- for ClientToScreen and PopupComponent.
    function TeControl: TControl;
    // The themed controller the popup resolves its .tycss tokens through (nil safe).
    function TeController: TTyStyleController;
    // Actions (each maps to the control's existing public method).
    procedure TeUndo;
    procedure TeRedo;
    procedure TeCut;
    procedure TeCopy;
    procedure TePaste;
    procedure TeSelectAll;
    // State queries, evaluated right before the menu shows.
    function TeCanUndo: Boolean;
    function TeCanRedo: Boolean;
    function TeHasSelection: Boolean;
    function TeCanPaste: Boolean;    // the clipboard currently holds insertable text
    function TeHasText: Boolean;     // the control has any content (Select All is moot on empty)
    function TeIsReadOnly: Boolean;
  end;

  { The extra seam the macOS IME handler (tyControls.CocoaWS) drives while a CJK composition is in
    progress: show the intermediate (marked) text INLINE at the caret and hand back the caret rect
    for the candidate window. Same pattern as ITyTextEditActions -- both TTyEdit and TTyMemo
    implement it as one-line delegates to members they already have. Only the Cocoa handler consumes
    it; on every other widgetset it is an unused (but harmless) interface. See tyControls.CocoaWS. }
  ITyImeEditable = interface
    ['{A6F1E9C4-2B7D-4E3A-8F51-9C0D6B8A2E13}']
    function  ImeTargetControl: TWinControl;   // the control, for ClientToScreen
    function  ImeIsReadOnly: Boolean;
    function  ImeCaretBoundClient: TRect;      // caret rect, client device px (empty rect if unfocused)
    function  ImeCaretIndex: Integer;          // flat codepoint index of the caret
    procedure ImeSessionBegin;                 // open ONE undo step, then suspend per-keystroke undo
    procedure ImeSessionEnd;                   // release the suspend + fire OnChange once
    procedure ImeReplace(AStart, ALen: Integer; const AText: string);  // delete [AStart,+ALen), insert AText at AStart
  end;

  { Owns and REUSES one themed TTyPopupMenu for a text control's default right-click menu.
    Held by the control (created lazily on first context-popup, freed in the control's
    destructor). The menu is built once; the item Enabled flags are refreshed on every
    popup from the live control state. }
  TTyTextEditMenu = class(TObject)
  private
    FActions: ITyTextEditActions;
    FMenu: TTyPopupMenu;
    FItemUndo, FItemRedo, FItemCut, FItemCopy, FItemPaste, FItemSelectAll: TMenuItem;
    procedure BuildMenu;
    procedure UpdateEnabled;
    procedure ClickUndo(Sender: TObject);
    procedure ClickRedo(Sender: TObject);
    procedure ClickCut(Sender: TObject);
    procedure ClickCopy(Sender: TObject);
    procedure ClickPaste(Sender: TObject);
    procedure ClickSelectAll(Sender: TObject);
  public
    constructor Create(const AActions: ITyTextEditActions);
    destructor Destroy; override;
    { Show the default themed menu at AMousePos (the control's CLIENT coordinates, as
      DoContextPopup delivers them; (-1,-1) means the keyboard menu key). Builds the menu
      on first use, then refreshes the enable states and pops it up at the click point. }
    procedure Popup(AMousePos: TPoint);
  end;

{ Whether the clipboard currently carries text that could be pasted. The production
  equivalent of each control's virtual ReadClipboardText (which returns Clipboard.AsText),
  exported so callers outside the controls can ask the same question consistently. The
  controls themselves route TeCanPaste through ReadClipboardText so headless tests can stub
  the clipboard; this reaches the real one. }
function TyClipboardHasText: Boolean;

const
  { Multi-click sequence window. A press within this many ms of the previous one AND within
    the pixel tolerance below continues the sequence (2 -> word, 3 -> line); otherwise it
    restarts at 1. 500 ms is the common system double-click default and is portable. }
  TyMultiClickTimeMs   = 500;
  TyMultiClickTolerPx  = 4;   // a few px of slop, per LCL's own drag-threshold order of magnitude

{ The multi-click count for a press at (AX, AY). ADouble is `ssDouble in Shift` -- LCL's
  reliable marker for the 2nd press of a real double-click -- which is what makes this a
  DOUBLE, not a raw press-timer. A press just AFTER a double (close in time+position, ADouble
  False) is the TRIPLE, since no widgetset marks the third. Returns 1 = plain, 2 = word,
  3 = line. The four tracking vars are owned by the control (one set each). Keying the double
  off ssDouble (not time alone) means a lone press -- or a rapid same-spot sequence that is
  NOT a real double -- stays a plain click, which is what the hit-test tests rely on. }
function TyMultiClickCount(ADouble: Boolean; AX, AY: Integer; var ALastX, ALastY: Integer;
  var ALastTick: QWord; var ACount: Integer): Integer;

implementation

function TyClipboardHasText: Boolean;
begin
  // HasFormat is cheap and does not fetch the payload; the AsText fallback covers widgetsets
  // that expose text under a synonym format but still answer AsText.
  Result := Clipboard.HasFormat(CF_TEXT) or (Clipboard.AsText <> '');
end;

function TyMultiClickCount(ADouble: Boolean; AX, AY: Integer; var ALastX, ALastY: Integer;
  var ALastTick: QWord; var ACount: Integer): Integer;
var
  now: QWord;
begin
  now := TThread.GetTickCount64;
  if ADouble then
  begin
    // LCL delivers the 2nd press of a double with ssDouble set -- the authoritative signal.
    ACount := 2;
    ALastTick := now; ALastX := AX; ALastY := AY;
  end
  else if (ACount = 2) and (ALastTick <> 0)
      and (now - ALastTick <= TyMultiClickTimeMs)
      and (Abs(AX - ALastX) <= TyMultiClickTolerPx)
      and (Abs(AY - ALastY) <= TyMultiClickTolerPx) then
  begin
    // The press right after a double, close in time+position, is the triple.
    ACount := 3;
    ALastTick := 0;   // consume: a further press restarts the sequence at a plain click
  end
  else
    ACount := 1;
  Result := ACount;
end;

{ TTyTextEditMenu }

constructor TTyTextEditMenu.Create(const AActions: ITyTextEditActions);
begin
  inherited Create;
  FActions := AActions;
end;

destructor TTyTextEditMenu.Destroy;
begin
  // FMenu is created with no owner, so free it explicitly (its items are owned by it).
  FreeAndNil(FMenu);
  FActions := nil;
  inherited Destroy;
end;

procedure TTyTextEditMenu.BuildMenu;

  function AddItem(const ACaption: string; AOnClick: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(FMenu);
    Result.Caption := ACaption;
    Result.OnClick := AOnClick;
    FMenu.Items.Add(Result);
  end;

  procedure AddSeparator;
  var
    sep: TMenuItem;
  begin
    sep := TMenuItem.Create(FMenu);
    sep.Caption := '-';   // TMenuItem.IsLine -> the renderer draws a separator row
    FMenu.Items.Add(sep);
  end;

begin
  if FMenu <> nil then Exit;
  // No owner: this helper frees the menu in its own destructor (which the control drives).
  FMenu := TTyPopupMenu.Create(nil);
  // Captions are resourcestrings resolved at build time; a language switch is a design-time
  // concern here (the menu is built once per control lifetime, which is the norm).
  FItemUndo      := AddItem(rsTextMenuUndo,      @ClickUndo);
  FItemRedo      := AddItem(rsTextMenuRedo,      @ClickRedo);
  AddSeparator;
  FItemCut       := AddItem(rsTextMenuCut,       @ClickCut);
  FItemCopy      := AddItem(rsTextMenuCopy,      @ClickCopy);
  FItemPaste     := AddItem(rsTextMenuPaste,     @ClickPaste);
  AddSeparator;
  FItemSelectAll := AddItem(rsTextMenuSelectAll, @ClickSelectAll);
end;

procedure TTyTextEditMenu.UpdateEnabled;
var
  ro: Boolean;
begin
  ro := FActions.TeIsReadOnly;
  FItemUndo.Enabled      := FActions.TeCanUndo and not ro;
  FItemRedo.Enabled      := FActions.TeCanRedo and not ro;
  FItemCut.Enabled       := FActions.TeHasSelection and not ro;
  FItemCopy.Enabled      := FActions.TeHasSelection;
  FItemPaste.Enabled     := FActions.TeCanPaste and not ro;
  FItemSelectAll.Enabled := FActions.TeHasText;
end;

procedure TTyTextEditMenu.ClickUndo(Sender: TObject);      begin FActions.TeUndo; end;
procedure TTyTextEditMenu.ClickRedo(Sender: TObject);      begin FActions.TeRedo; end;
procedure TTyTextEditMenu.ClickCut(Sender: TObject);       begin FActions.TeCut; end;
procedure TTyTextEditMenu.ClickCopy(Sender: TObject);      begin FActions.TeCopy; end;
procedure TTyTextEditMenu.ClickPaste(Sender: TObject);     begin FActions.TePaste; end;
procedure TTyTextEditMenu.ClickSelectAll(Sender: TObject); begin FActions.TeSelectAll; end;

procedure TTyTextEditMenu.Popup(AMousePos: TPoint);
var
  ctl: TControl;
  scr: TPoint;
begin
  ctl := FActions.TeControl;
  BuildMenu;
  FMenu.Controller := FActions.TeController;   // match the control's active theme
  FMenu.PopupComponent := ctl;                 // so the popup resolves RightToLeft from it
  UpdateEnabled;
  // A keyboard menu-key press arrives as (-1,-1); anchor it at the control origin (the same
  // fallback LCL's WMContextMenu uses). Otherwise map the client click to a screen point.
  if AMousePos.X = -1 then AMousePos := Point(0, 0);
  scr := ctl.ClientToScreen(AMousePos);
  FMenu.PopUp(scr.X, scr.Y);
end;

end.
