unit tyControls.Dialogs;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Dialogs, Forms,
  tyControls.Types, tyControls.Form, tyControls.Button, tyControls.Panel;

{ Right-aligns caption buttons in a bar: index 0 is the RIGHTMOST (primary), each successive
  button sits to its left, ASpacing apart, AMargin from the right edge. Pure. }
function TyDialogButtonBar(const ASizes: array of TSize; ABarWidth, AMargin, ASpacing: Integer): TTyRectArray;

type
  TMsgDlgBtnArray = array of TMsgDlgBtn;

function TyMsgButtonCaption(ABtn: TMsgDlgBtn): string;
function TyMsgButtonResult(ABtn: TMsgDlgBtn): TModalResult;
function TyMsgOrderedButtons(AButtons: TMsgDlgButtons): TMsgDlgBtnArray;
function TyMsgTypeSymbol(ADlgType: TMsgDlgType): string;

type
  TTyDialog = class(TTyForm)
  private
    FButtonBar: TTyPanel;          // strip host for the buttons (transparent)
    FButtons: array of TTyButton;
    FDefaultResult, FCancelResult: TModalResult;
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
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
    mbYes:     Result := 'Yes';
    mbNo:      Result := 'No';
    mbOK:      Result := 'OK';
    mbCancel:  Result := 'Cancel';
    mbAbort:   Result := 'Abort';
    mbRetry:   Result := 'Retry';
    mbIgnore:  Result := 'Ignore';
    mbAll:     Result := 'All';
    mbNoToAll: Result := 'No to All';
    mbYesToAll:Result := 'Yes to All';
    mbHelp:    Result := 'Help';
    mbClose:   Result := 'Close';
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

end.
