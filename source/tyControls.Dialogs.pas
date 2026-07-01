unit tyControls.Dialogs;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Controls, Dialogs, Forms,
  tyControls.Types, tyControls.Form, tyControls.Button, tyControls.Panel,
  tyControls.TyLabel, tyControls.Edit, tyControls.Memo, tyControls.Painter,
  tyControls.ListBox, tyControls.StrConsts;

{ Right-aligns caption buttons in a bar: index 0 is the RIGHTMOST (primary), each successive
  button sits to its left, ASpacing apart, AMargin from the right edge. Pure. }
function TyDialogButtonBar(const ASizes: array of TSize; ABarWidth, AMargin, ASpacing: Integer): TTyRectArray;

type
  TMsgDlgBtnArray = array of TMsgDlgBtn;

function TyMsgButtonCaption(ABtn: TMsgDlgBtn): string;
function TyMsgButtonResult(ABtn: TMsgDlgBtn): TModalResult;
function TyMsgOrderedButtons(AButtons: TMsgDlgButtons): TMsgDlgBtnArray;
function TyMsgTypeSymbol(ADlgType: TMsgDlgType): string;
function TyMsgTypeCaption(ADlgType: TMsgDlgType): string;

type
  TTyDialog = class(TTyForm)
  private
    FButtonBar: TTyPanel;          // strip host for the buttons (transparent)
    FButtons: array of TTyButton;
    FDefaultResult, FCancelResult: TModalResult;
    FMsgSymbol: string;            // '' = no message icon (a plain TTyDialog draws nothing)
    FMsgType: TMsgDlgType;
    // Draw the message icon (semantic circle + centred symbol) in the icon column.
    // Guarded: no-op unless FMsgSymbol <> '' and the canvas is ready. GUI-only.
    procedure DrawMessageIcon;
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure Paint; override;
    procedure LayoutContent; virtual;
    procedure Resize; override;
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    function AddButton(const ACaption: string; AResult: TModalResult;
      ADefault: Boolean = False; ACancel: Boolean = False): TTyButton;
    procedure LayoutButtonBar;
    function ContentRect: TRect;
    procedure AutoSizeToContent(AContentW, AContentH: Integer);
    // Esc / programmatic cancel -> FCancelResult. (The title-bar X closes the
    // modal and returns mrCancel via LCL's default; it does not call this.)
    procedure CancelDialog;
    // Store the message-icon symbol + semantic type so Paint can draw it.
    procedure SetMessageIcon(const ASymbol: string; AType: TMsgDlgType);
    // Test/introspection seam onto the built buttons.
    function GetButtonCount: Integer;
    function GetButton(AIndex: Integer): TTyButton;
    property ButtonCount: Integer read GetButtonCount;
    property Buttons[AIndex: Integer]: TTyButton read GetButton;
  end;

{ Test/introspection helpers (construct-only seam). }
function TyDialogButtonCount(ADlg: TTyDialog): Integer;
function TyDialogButton(ADlg: TTyDialog; AIndex: Integer): TTyButton;
{ Build a message dialog WITHOUT showing it (the show is TyMessageDlg).
  ATitle overrides the type-derived window caption when non-empty. }
function TyBuildMessageDialog(const AMsg: string; ADlgType: TMsgDlgType; AButtons: TMsgDlgButtons; const ATitle: string = ''): TTyDialog;
{ Globals — the primary API. }
procedure TyShowMessage(const AMsg: string);
function TyMessageDlg(const AMsg: string; ADlgType: TMsgDlgType; AButtons: TMsgDlgButtons; AHelpCtx: Longint = 0): TModalResult;
function TyMessageDlgPos(const AMsg: string; ADlgType: TMsgDlgType; AButtons: TMsgDlgButtons; AHelpCtx: Longint; X, Y: Integer): TModalResult;

type
  TTyMessage = class(TComponent)
  private
    FTitle, FMsg: string;
    FDlgType: TMsgDlgType;
    FButtons: TMsgDlgButtons;
  public
    constructor Create(AOwner: TComponent); override;
    function Execute: TModalResult;
  published
    property Title: string read FTitle write FTitle;
    property Msg: string read FMsg write FMsg;
    property DlgType: TMsgDlgType read FDlgType write FDlgType default mtInformation;
    property Buttons: TMsgDlgButtons read FButtons write FButtons default [mbOK];
  end;

{ Input dialog — construct-only builder returns the dialog + its edit (out param). }
function TyBuildInputDialog(const ACaption, APrompt, ADefault: string; out AEdit: TTyEdit): TTyDialog;
function TyInputResult(AEdit: TTyEdit; const ADefault: string; AResult: TModalResult): string;
function TyInputQuery(const ACaption, APrompt: string; var AValue: string): Boolean;
function TyInputBox(const ACaption, APrompt, ADefault: string): string;

type
  TTyInputDialog = class(TComponent)
  private
    FCaption, FPrompt, FValue: string;
  public
    function Execute: Boolean;
  published
    property Caption: string read FCaption write FCaption;
    property Prompt: string read FPrompt write FPrompt;
    property Value: string read FValue write FValue;
  end;

{ Password dialog — masked-edit delta on Input }
const TyDefaultPasswordChar = '●';
function TyBuildPasswordDialog(const ACaption, APrompt, APasswordChar: string; out AEdit: TTyEdit): TTyDialog;
function TyPasswordBox(const ACaption, APrompt: string): string;
function TyPasswordQuery(const ACaption, APrompt: string; var AValue: string): Boolean;

type
  TTyPasswordDialog = class(TComponent)
  private
    FCaption, FPrompt, FValue, FPasswordChar: string;
  public
    constructor Create(AOwner: TComponent); override;
    function Execute: Boolean;
  published
    property Caption: string read FCaption write FCaption;
    property Prompt: string read FPrompt write FPrompt;
    property Value: string read FValue write FValue;
    property PasswordChar: string read FPasswordChar write FPasswordChar;
  end;

{ Text dialog — resizable multi-line memo input }

type
  TTyTextDialogForm = class(TTyDialog)
  private
    FMemo: TTyMemo;
    FPromptBottom: Integer;   // y where the memo starts (below the prompt)
  protected
    procedure LayoutContent; override;
  public
    property Memo: TTyMemo read FMemo;
  end;

function TyBuildTextDialog(const ACaption, APrompt, ADefault: string; out AMemo: TTyMemo): TTyTextDialogForm;
function TyTextQuery(const ACaption, APrompt: string; var AValue: string): Boolean;

type
  TTyTextDialog = class(TComponent)
  private
    FCaption, FPrompt, FValue: string;
  public
    function Execute: Boolean;
  published
    property Caption: string read FCaption write FCaption;
    property Prompt: string read FPrompt write FPrompt;
    property Value: string read FValue write FValue;
  end;

{ Shared layout constants — exported so sub-units (e.g. SelectPath) can
  reference them without hard-coding the same literals. }
const
  TyDlgPad   = 16;   // content padding
  TyDlgEditW = 320;  // default single-line input width
  TyDlgEditH = 30;

{ Select-value dialog — single-select listbox; double-click a row confirms. }
function TyBuildSelectValueDialog(const ACaption, APrompt: string; AItems: TStrings;
  AInitialIndex: Integer; out AList: TTyListBox): TTyDialog;
function TySelectValueResult(AList: TTyListBox; AInitialIndex: Integer;
  AResult: TModalResult): Integer;
function TySelectValue(const ACaption, APrompt: string; AItems: TStrings;
  var AIndex: Integer): Boolean;

{ TTySelectValueForm is the concrete form used by TyBuildSelectValueDialog.
  It is declared in the interface only so the dbl-click method can be a proper
  method pointer (TNotifyEvent requires "of object"). Callers hold a TTyDialog. }
type
  TTySelectValueForm = class(TTyDialog)
  private
    procedure ListDblClick(Sender: TObject);
  end;

type
  TTySelectValueDialog = class(TComponent)
  private
    FCaption, FPrompt: string;
    FItems: TStrings;
    FItemIndex: Integer;
    procedure SetItems(AValue: TStrings);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Execute: Boolean;
    function SelectedText: string;
  published
    property Caption: string read FCaption write FCaption;
    property Prompt: string read FPrompt write FPrompt;
    property Items: TStrings read FItems write SetItems;
    property ItemIndex: Integer read FItemIndex write FItemIndex default -1;
  end;

implementation

function TyDialogButtonBar(const ASizes: array of TSize; ABarWidth, AMargin, ASpacing: Integer): TTyRectArray;
var
  i, x: Integer;
begin
  SetLength(Result, Length(ASizes));
  x := ABarWidth - AMargin;                 // right edge of the next (rightmost-first) button
  for i := 0 to High(ASizes) do
  begin
    Result[i].Right := x;
    Result[i].Left := x - ASizes[i].cx;
    Result[i].Top := 0;
    Result[i].Bottom := ASizes[i].cy;
    x := Result[i].Left - ASpacing;
  end;
end;


function TyMsgButtonCaption(ABtn: TMsgDlgBtn): string;
begin
  case ABtn of
    mbYes:     Result := rsMsgBtnYes;
    mbNo:      Result := rsMsgBtnNo;
    mbOK:      Result := rsMsgBtnOK;
    mbCancel:  Result := rsMsgBtnCancel;
    mbAbort:   Result := rsMsgBtnAbort;
    mbRetry:   Result := rsMsgBtnRetry;
    mbIgnore:  Result := rsMsgBtnIgnore;
    mbAll:     Result := rsMsgBtnAll;
    mbNoToAll: Result := rsMsgBtnNoToAll;
    mbYesToAll:Result := rsMsgBtnYesToAll;
    mbHelp:    Result := rsMsgBtnHelp;
    mbClose:   Result := rsMsgBtnClose;
  else Result := '';
  end;
end;

function TyMsgButtonResult(ABtn: TMsgDlgBtn): TModalResult;
begin
  case ABtn of
    mbYes:     Result := mrYes;
    mbNo:      Result := mrNo;
    mbOK:      Result := mrOK;
    mbCancel:  Result := mrCancel;
    mbAbort:   Result := mrAbort;
    mbRetry:   Result := mrRetry;
    mbIgnore:  Result := mrIgnore;
    mbAll:     Result := mrAll;
    mbNoToAll: Result := mrNoToAll;
    mbYesToAll:Result := mrYesToAll;
    mbClose:   Result := mrClose;
    mbHelp:    Result := 0;
  else Result := mrNone;
  end;
end;

function TyMsgOrderedButtons(AButtons: TMsgDlgButtons): TMsgDlgBtnArray;
const
  ORDER: array[0..11] of TMsgDlgBtn = (
    mbYes, mbYesToAll, mbNo, mbNoToAll, mbAll, mbOK,
    mbRetry, mbIgnore, mbAbort, mbCancel, mbClose, mbHelp);
var
  b: TMsgDlgBtn;
  n: Integer;
begin
  if AButtons = [] then
  begin
    SetLength(Result, 1);
    Result[0] := mbOK;
    Exit;
  end;
  SetLength(Result, 0);
  n := 0;
  for b in ORDER do
    if b in AButtons then
    begin
      SetLength(Result, n + 1);
      Result[n] := b;
      Inc(n);
    end;
end;

function TyMsgTypeSymbol(ADlgType: TMsgDlgType): string;
begin
  case ADlgType of
    mtWarning:      Result := '!';
    mtError:        Result := #$C3#$97; // × (U+00D7, UTF-8 bytes C3 97)
    mtConfirmation: Result := '?';
    mtInformation:  Result := 'i';
  else Result := '';
  end;
end;

function TyMsgTypeCaption(ADlgType: TMsgDlgType): string;
begin
  case ADlgType of
    mtWarning:      Result := rsMsgTypeWarning;
    mtError:        Result := rsMsgTypeError;
    mtConfirmation: Result := rsMsgTypeConfirm;
    mtInformation:  Result := rsMsgTypeInformation;
  else Result := '';
  end;
end;

{ TTyDialog }

constructor TTyDialog.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  BorderIcons := [biSystemMenu];      // close only (P1 chrome)
  Resizable := False;
  Position := poMainFormCenter;
  KeyPreview := True;
  FDefaultResult := mrNone; FCancelResult := mrCancel;
  FButtonBar := TTyPanel.Create(Self);
  FButtonBar.Parent := Self;
  FButtonBar.Align := alBottom;
  FButtonBar.Height := 44;
  FButtonBar.StyleClass := 'ghost';   // transparent-ish; refine in theming
end;

function TTyDialog.AddButton(const ACaption: string; AResult: TModalResult;
  ADefault, ACancel: Boolean): TTyButton;
begin
  Result := TTyButton.Create(Self);
  Result.Parent := FButtonBar;
  Result.Caption := ACaption;
  // TTyButton.Click sets the host form's ModalResult via GetParentForm (a pure
  // Parent-chain walk, no handle needed) — reuse it instead of a Tag+OnClick shim.
  Result.ModalResult := AResult;
  SetLength(FButtons, Length(FButtons) + 1); FButtons[High(FButtons)] := Result;
  if ADefault then FDefaultResult := AResult;
  if ACancel then FCancelResult := AResult;
  LayoutButtonBar;
end;

procedure TTyDialog.LayoutButtonBar;
var sizes: array of TSize; rects: TTyRectArray; i, y: Integer;
begin
  if Length(FButtons) = 0 then Exit;
  sizes := nil;
  SetLength(sizes, Length(FButtons));
  for i := 0 to High(FButtons) do sizes[i] := Size(88, 30);   // fixed dialog-button size
  rects := TyDialogButtonBar(sizes, FButtonBar.ClientWidth, 12, 8);
  y := (FButtonBar.ClientHeight - 30) div 2;
  for i := 0 to High(FButtons) do
    FButtons[i].SetBounds(rects[i].Left, y, 88, 30);
end;

function TTyDialog.ContentRect: TRect;
begin
  Result := ClientRect;
  Inc(Result.Top, TitleHeight);
  Dec(Result.Bottom, FButtonBar.Height);
end;

procedure TTyDialog.AutoSizeToContent(AContentW, AContentH: Integer);
var totalBtn, i, w: Integer;
begin
  totalBtn := 12; for i := 0 to High(FButtons) do totalBtn := totalBtn + 88 + 8;
  w := AContentW; if totalBtn > w then w := totalBtn;
  ClientWidth := w + 32;
  ClientHeight := TitleHeight + AContentH + FButtonBar.Height + 16;
  LayoutButtonBar;
end;

procedure TTyDialog.CancelDialog;
begin
  // Esc / programmatic cancel -> FCancelResult. (The title-bar X closes the modal
  // and returns mrCancel via LCL's default; it does not route through here.)
  ModalResult := FCancelResult;
end;

procedure TTyDialog.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if (Key = 13) and (FDefaultResult <> mrNone) then begin ModalResult := FDefaultResult; Key := 0; Exit; end;
  if Key = 27 then begin CancelDialog; Key := 0; Exit; end;
  inherited KeyDown(Key, Shift);
end;

function TTyDialog.GetButtonCount: Integer;
begin Result := Length(FButtons); end;

function TTyDialog.GetButton(AIndex: Integer): TTyButton;
begin
  if (AIndex < 0) or (AIndex > High(FButtons)) then
    raise EListError.CreateFmt('TTyDialog.Buttons index out of range: %d', [AIndex]);
  Result := FButtons[AIndex];
end;

procedure TTyDialog.SetMessageIcon(const ASymbol: string; AType: TMsgDlgType);
begin
  FMsgSymbol := ASymbol;
  FMsgType := AType;
end;

procedure TTyDialog.DrawMessageIcon;
{ Semantic circle + centred symbol in the icon column (left of the message label).
  Guarded: no-op unless a symbol is set and a canvas is available. Fixed semantic
  colours are sanctioned for S1 (a --error/--warning/--info token pass is deferred). }
var
  P: TTyPainter;
  fill: TTyFill;
  d, cx, cy: Integer;
  circle: TRect;
begin
  if FMsgSymbol = '' then Exit;                 // plain dialog -> nothing to draw
  if (Canvas = nil) or (not HandleAllocated) then Exit;   // crash-safe: no canvas yet
  fill := Default(TTyFill);
  fill.Kind := tfkSolid;
  case FMsgType of
    mtError:   fill.Color := TyRGB(229, 57, 53);    // #E53935 red
    mtWarning: fill.Color := TyRGB(255, 140, 0);    // #FF8C00 amber
  else
    fill.Color := TyRGB(0, 112, 192);               // #0070C0 blue (info / confirm)
  end;
  d := 28;                                          // ~28px circle
  cx := 14;                                         // icon column left
  cy := TitleHeight + 12;                           // aligns with the label top
  circle := Rect(cx, cy, cx + d, cy + d);
  P := TTyPainter.Create;
  try
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    // Circle = square with a half-side radius.
    P.FillBackground(circle, fill, TyUniformCorners(d div 2));
    // Symbol centred in white (contrast against every semantic colour above).
    P.DrawText(circle, FMsgSymbol, Font.Name, 14, 700, TyRGB(255, 255, 255),
      taCenter, tlCenter, False, 0, False);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyDialog.Paint;
begin
  inherited Paint;
  DrawMessageIcon;
end;

procedure TTyDialog.LayoutContent;
begin
  // default: fixed-size dialogs position content once at build time; nothing to reflow.
end;

procedure TTyDialog.Resize;
begin
  inherited Resize;
  if FButtonBar <> nil then LayoutButtonBar;
  LayoutContent;
end;

{ Free functions / globals }

function TyDialogButtonCount(ADlg: TTyDialog): Integer;
begin Result := ADlg.ButtonCount; end;

function TyDialogButton(ADlg: TTyDialog; AIndex: Integer): TTyButton;
begin Result := ADlg.Buttons[AIndex]; end;

function TyBuildMessageDialog(const AMsg: string; ADlgType: TMsgDlgType; AButtons: TMsgDlgButtons; const ATitle: string): TTyDialog;
var lbl: TTyLabel; ordered: TMsgDlgBtnArray; i: Integer; def: TMsgDlgBtn;
begin
  Result := TTyDialog.CreateNew(Application);
  // Explicit title wins; otherwise the human-readable type caption (i18n in Task 6).
  if ATitle <> '' then Result.Caption := ATitle
  else Result.Caption := TyMsgTypeCaption(ADlgType);
  ordered := TyMsgOrderedButtons(AButtons);
  lbl := TTyLabel.Create(Result);
  lbl.Parent := Result;
  lbl.Caption := AMsg;
  lbl.WordWrap := True;
  lbl.SetBounds(56, Result.TitleHeight + 12, 260, 40);   // right of the icon column
  def := ordered[0];
  // Esc / title-bar X both dismiss the message dialog to mrCancel (FCancelResult stays
  // the CreateNew default); ACancel is left for custom TTyDialog subclasses to use.
  for i := 0 to High(ordered) do
    Result.AddButton(TyMsgButtonCaption(ordered[i]), TyMsgButtonResult(ordered[i]),
      ordered[i] = def, False);
  // store the message-icon symbol + semantic colour so Paint can draw it
  Result.SetMessageIcon(TyMsgTypeSymbol(ADlgType), ADlgType);
  Result.AutoSizeToContent(320, 56);
end;

// Show a built dialog modally and free it (leak-safe). Shared by the globals + the component.
function RunDialogModal(ADlg: TTyDialog): TModalResult;
begin
  try Result := ADlg.ShowModal; finally ADlg.Free; end;
end;

function TyMessageDlg(const AMsg: string; ADlgType: TMsgDlgType; AButtons: TMsgDlgButtons; AHelpCtx: Longint): TModalResult;
var d: TTyDialog;
begin
  d := TyBuildMessageDialog(AMsg, ADlgType, AButtons);
  d.HelpContext := AHelpCtx;   // reserved for a future help-context wiring (LCL-API parity)
  Result := RunDialogModal(d);
end;

function TyMessageDlgPos(const AMsg: string; ADlgType: TMsgDlgType; AButtons: TMsgDlgButtons; AHelpCtx: Longint; X, Y: Integer): TModalResult;
var d: TTyDialog;
begin
  d := TyBuildMessageDialog(AMsg, ADlgType, AButtons);
  d.HelpContext := AHelpCtx;   // reserved for a future help-context wiring (LCL-API parity)
  d.Position := poDesigned; d.Left := X; d.Top := Y;
  Result := RunDialogModal(d);
end;

procedure TyShowMessage(const AMsg: string);
begin TyMessageDlg(AMsg, mtInformation, [mbOK]); end;

{ TTyMessage }

constructor TTyMessage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDlgType := mtInformation;
  FButtons := [mbOK];
end;

function TTyMessage.Execute: TModalResult;
var d: TTyDialog;
begin
  d := TyBuildMessageDialog(FMsg, FDlgType, FButtons, FTitle);
  Result := RunDialogModal(d);
end;

{ Input dialog }

// Places a wrapped prompt label at the top of the content area (parented to ADlg).
// Returns the y (in dialog client coords) just below the prompt.
function TyPlacePrompt(ADlg: TTyDialog; const APrompt: string; AWidth: Integer): Integer;
var lbl: TTyLabel; r: TRect;
begin
  r := ADlg.ContentRect;
  lbl := TTyLabel.Create(ADlg);
  lbl.Parent := ADlg;
  lbl.WordWrap := True;
  lbl.Caption := APrompt;
  lbl.SetBounds(r.Left + TyDlgPad, r.Top + TyDlgPad, AWidth, 20);
  Result := r.Top + TyDlgPad + 26;
end;

function TyBuildInputDialog(const ACaption, APrompt, ADefault: string; out AEdit: TTyEdit): TTyDialog;
var y: Integer;
begin
  Result := TTyDialog.CreateNew(Application);
  Result.Caption := ACaption;
  y := TyPlacePrompt(Result, APrompt, TyDlgEditW);
  AEdit := TTyEdit.Create(Result);
  AEdit.Parent := Result;
  AEdit.Text := ADefault;
  AEdit.SetBounds(Result.ContentRect.Left + TyDlgPad, y, TyDlgEditW, TyDlgEditH);
  Result.AddButton(rsMsgBtnOK, mrOK, True, False);
  Result.AddButton(rsMsgBtnCancel, mrCancel, False, True);
  Result.AutoSizeToContent(TyDlgEditW + TyDlgPad, y + TyDlgEditH + TyDlgPad - Result.ContentRect.Top);
end;

function TyInputResult(AEdit: TTyEdit; const ADefault: string; AResult: TModalResult): string;
begin
  if AResult = mrOK then Result := AEdit.Text else Result := ADefault;
end;

function TyInputBox(const ACaption, APrompt, ADefault: string): string;
var d: TTyDialog; e: TTyEdit;
begin
  d := TyBuildInputDialog(ACaption, APrompt, ADefault, e);
  try Result := TyInputResult(e, ADefault, d.ShowModal); finally d.Free; end;
end;

function TyInputQuery(const ACaption, APrompt: string; var AValue: string): Boolean;
var d: TTyDialog; e: TTyEdit; mr: TModalResult;
begin
  d := TyBuildInputDialog(ACaption, APrompt, AValue, e);
  try
    mr := d.ShowModal;
    Result := (mr = mrOK);
    if Result then AValue := e.Text;
  finally d.Free; end;
end;

{ TTyInputDialog }

function TTyInputDialog.Execute: Boolean;
begin Result := TyInputQuery(FCaption, FPrompt, FValue); end;

{ Password dialog }

function TyBuildPasswordDialog(const ACaption, APrompt, APasswordChar: string; out AEdit: TTyEdit): TTyDialog;
var y: Integer;
begin
  Result := TTyDialog.CreateNew(Application);
  Result.Caption := ACaption;
  y := TyPlacePrompt(Result, APrompt, TyDlgEditW);
  AEdit := TTyEdit.Create(Result);
  AEdit.Parent := Result;
  AEdit.PasswordChar := APasswordChar;
  AEdit.SetBounds(Result.ContentRect.Left + TyDlgPad, y, TyDlgEditW, TyDlgEditH);
  Result.AddButton(rsMsgBtnOK, mrOK, True, False);
  Result.AddButton(rsMsgBtnCancel, mrCancel, False, True);
  Result.AutoSizeToContent(TyDlgEditW + TyDlgPad, y + TyDlgEditH + TyDlgPad - Result.ContentRect.Top);
end;

function TyPasswordBox(const ACaption, APrompt: string): string;
var d: TTyDialog; e: TTyEdit;
begin
  d := TyBuildPasswordDialog(ACaption, APrompt, TyDefaultPasswordChar, e);
  try
    if d.ShowModal = mrOK then Result := e.Text else Result := '';
  finally d.Free; end;
end;

function TyPasswordQuery(const ACaption, APrompt: string; var AValue: string): Boolean;
var d: TTyDialog; e: TTyEdit;
begin
  d := TyBuildPasswordDialog(ACaption, APrompt, TyDefaultPasswordChar, e);
  try
    Result := (d.ShowModal = mrOK);
    if Result then AValue := e.Text;
  finally d.Free; end;
end;

{ TTyPasswordDialog }

constructor TTyPasswordDialog.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPasswordChar := TyDefaultPasswordChar;
end;

function TTyPasswordDialog.Execute: Boolean;
var d: TTyDialog; e: TTyEdit;
begin
  d := TyBuildPasswordDialog(FCaption, FPrompt, FPasswordChar, e);
  try
    Result := (d.ShowModal = mrOK);
    if Result then FValue := e.Text;
  finally d.Free; end;
end;

{ TTyTextDialogForm }

procedure TTyTextDialogForm.LayoutContent;
var r: TRect;
begin
  if FMemo = nil then Exit;
  r := ContentRect;
  FMemo.SetBounds(r.Left + TyDlgPad, FPromptBottom,
    (r.Right - r.Left) - 2*TyDlgPad, r.Bottom - FPromptBottom - TyDlgPad);
end;

{ Text dialog free functions }

function TyBuildTextDialog(const ACaption, APrompt, ADefault: string; out AMemo: TTyMemo): TTyTextDialogForm;
var y: Integer;
begin
  Result := TTyTextDialogForm.CreateNew(Application);
  Result.Resizable := True;
  Result.Caption := ACaption;
  Result.Constraints.MinWidth := 320;
  Result.Constraints.MinHeight := 220;
  y := TyPlacePrompt(Result, APrompt, 380);
  Result.FPromptBottom := y;
  AMemo := TTyMemo.Create(Result);
  AMemo.Parent := Result;
  AMemo.Text := ADefault;
  Result.FMemo := AMemo;
  Result.AddButton(rsMsgBtnOK, mrOK, True, False);
  Result.AddButton(rsMsgBtnCancel, mrCancel, False, True);
  Result.AutoSizeToContent(420, 260 - Result.ContentRect.Top);  // roomy default
  Result.LayoutContent;   // place the memo into the content area
end;

function TyTextQuery(const ACaption, APrompt: string; var AValue: string): Boolean;
var d: TTyTextDialogForm; m: TTyMemo;
begin
  d := TyBuildTextDialog(ACaption, APrompt, AValue, m);
  try
    Result := (d.ShowModal = mrOK);
    if Result then AValue := m.Text;
  finally d.Free; end;
end;

{ TTyTextDialog }

function TTyTextDialog.Execute: Boolean;
begin Result := TyTextQuery(FCaption, FPrompt, FValue); end;

{ TTySelectValueForm }

// Double-clicking a row with a valid selection confirms the dialog.
// Must be a method (TNotifyEvent = "of object") — plain procedures cannot be assigned.
procedure TTySelectValueForm.ListDblClick(Sender: TObject);
begin
  if TTyListBox(Sender).ItemIndex >= 0 then ModalResult := mrOK;
end;

{ Select-value dialog }

function TyBuildSelectValueDialog(const ACaption, APrompt: string; AItems: TStrings;
  AInitialIndex: Integer; out AList: TTyListBox): TTyDialog;
var f: TTySelectValueForm; y, listH: Integer;
begin
  f := TTySelectValueForm.CreateNew(Application);
  Result := f;
  Result.Caption := ACaption;
  y := TyPlacePrompt(Result, APrompt, TyDlgEditW);
  AList := TTyListBox.Create(Result);
  AList.Parent := Result;
  if AItems <> nil then AList.Items.Assign(AItems);
  if (AInitialIndex >= 0) and (AInitialIndex < AList.Items.Count) then
    AList.ItemIndex := AInitialIndex;
  listH := 160;
  AList.SetBounds(Result.ContentRect.Left + TyDlgPad, y, TyDlgEditW, listH);
  AList.OnDblClick := @f.ListDblClick;   // double-click a row confirms
  Result.AddButton(rsMsgBtnOK, mrOK, True, False);
  Result.AddButton(rsMsgBtnCancel, mrCancel, False, True);
  Result.AutoSizeToContent(TyDlgEditW + TyDlgPad, y + listH + TyDlgPad - Result.ContentRect.Top);
end;

function TySelectValueResult(AList: TTyListBox; AInitialIndex: Integer;
  AResult: TModalResult): Integer;
begin
  if AResult = mrOK then Result := AList.ItemIndex else Result := AInitialIndex;
end;

function TySelectValue(const ACaption, APrompt: string; AItems: TStrings;
  var AIndex: Integer): Boolean;
var d: TTyDialog; lb: TTyListBox;
begin
  d := TyBuildSelectValueDialog(ACaption, APrompt, AItems, AIndex, lb);
  try
    Result := (d.ShowModal = mrOK);
    if Result then AIndex := lb.ItemIndex;
  finally d.Free; end;
end;

{ TTySelectValueDialog }

constructor TTySelectValueDialog.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TStringList.Create;
  FItemIndex := -1;
end;

destructor TTySelectValueDialog.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TTySelectValueDialog.SetItems(AValue: TStrings);
begin
  FItems.Assign(AValue);
end;

function TTySelectValueDialog.SelectedText: string;
begin
  if (FItemIndex >= 0) and (FItemIndex < FItems.Count) then
    Result := FItems[FItemIndex]
  else
    Result := '';
end;

function TTySelectValueDialog.Execute: Boolean;
begin
  Result := TySelectValue(FCaption, FPrompt, FItems, FItemIndex);
end;

end.
