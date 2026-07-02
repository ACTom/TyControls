unit tyControls.Dialogs.Find;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Dialogs, LCLType,
  tyControls.Dialogs, tyControls.Edit, tyControls.CheckBox, tyControls.Button,
  tyControls.TyLabel, tyControls.StrConsts;

type
  TTyFindChecks = record
    MatchCase, WholeWord, SearchUp: Boolean;
  end;

function TyFindOptionsToChecks(AOpts: TFindOptions): TTyFindChecks;
function TyChecksToFindOptions(const AChecks: TTyFindChecks; ABase: TFindOptions): TFindOptions;

type
  TTyFindDialog = class;

  { TTyFindForm — the reusable modeless form owned by a TTyFindDialog. Built in
    Find mode (Build(False)) or Find+Replace mode (Build(True)). All state lives on
    the owning component (FDlg); the form is pure UI + the Do* action seams. }
  TTyFindForm = class(TTyDialog)
  private
    FDlg: TTyFindDialog;
    FWithReplace: Boolean;
    FFindEdit: TTyEdit;
    FReplaceEdit: TTyEdit;        // nil unless FWithReplace
    FMatchCase, FWholeWord, FSearchUp: TTyCheckBox;
    procedure FindNextClick(Sender: TObject);
    procedure ReplaceClick(Sender: TObject);
    procedure ReplaceAllClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure WriteBack;
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    procedure Build(AWithReplace: Boolean);
    procedure SyncFrom(const AFindText, AReplaceText: string; AOptions: TFindOptions);
    procedure DoFindNext;
    procedure DoReplace;
    procedure DoReplaceAll;
    // test seams:
    function FindEdit: TTyEdit;
    function ReplaceEdit: TTyEdit;
    function MatchCaseCheck: TTyCheckBox;
    function WholeWordCheck: TTyCheckBox;
    function SearchUpCheck: TTyCheckBox;
    property WithReplace: Boolean read FWithReplace;
  end;

  { TTyFindDialog — non-visual, modeless. Owns a TTyFindForm; fires OnFind when the
    user clicks Find Next (or presses Enter). LCL TFindDialog parity. }
  TTyFindDialog = class(TComponent)
  private
    FFindText: string;
    FReplaceText: string;        // populated by TTyReplaceDialog
    FOptions: TFindOptions;
    FPosition: TPosition;
    FOnFind: TNotifyEvent;
    FOnReplace: TNotifyEvent;    // used by TTyReplaceDialog
    FForm: TTyFindForm;
  protected
    function WantReplace: Boolean; virtual;
  public
    constructor Create(AOwner: TComponent); override;
    function BuildForm: TTyFindForm;   // test seam: lazy build + sync, NO Show
    function Execute: Boolean;
    procedure CloseDialog;
  published
    property FindText: string read FFindText write FFindText;
    property Options: TFindOptions read FOptions write FOptions default [frDown];
    property Position: TPosition read FPosition write FPosition default poScreenCenter;
    property OnFind: TNotifyEvent read FOnFind write FOnFind;
  end;

implementation

function TyFindOptionsToChecks(AOpts: TFindOptions): TTyFindChecks;
begin
  Result.MatchCase := frMatchCase in AOpts;
  Result.WholeWord := frWholeWord in AOpts;
  Result.SearchUp  := not (frDown in AOpts);
end;

function TyChecksToFindOptions(const AChecks: TTyFindChecks; ABase: TFindOptions): TFindOptions;
begin
  Result := ABase;
  if AChecks.MatchCase then Include(Result, frMatchCase) else Exclude(Result, frMatchCase);
  if AChecks.WholeWord then Include(Result, frWholeWord) else Exclude(Result, frWholeWord);
  if AChecks.SearchUp  then Exclude(Result, frDown)      else Include(Result, frDown);
end;

{ TTyFindForm }

procedure TTyFindForm.Build(AWithReplace: Boolean);
var
  r: TRect;
  x0, y, editX, editW: Integer;
  b: TTyButton;

  function MkLabel(const ACaption: string; ALeft, ATop, AWidth: Integer): TTyLabel;
  begin
    Result := TTyLabel.Create(Self);
    Result.Parent := Self;
    Result.Caption := ACaption;
    Result.SetBounds(ALeft, ATop, AWidth, 20);
  end;

  function MkCheck(const ACaption: string; ALeft, ATop: Integer): TTyCheckBox;
  begin
    Result := TTyCheckBox.Create(Self);
    Result.Parent := Self;
    Result.Caption := ACaption;
    Result.SetBounds(ALeft, ATop, 160, 22);
  end;

begin
  FWithReplace := AWithReplace;
  r := ContentRect;
  x0 := r.Left + TyDlgPad;
  y := r.Top + TyDlgPad;
  editX := x0 + 100;
  editW := TyDlgEditW;

  MkLabel(rsDlgFindWhat, x0, y + 4, 96);
  FFindEdit := TTyEdit.Create(Self);
  FFindEdit.Parent := Self;
  FFindEdit.SetBounds(editX, y, editW, TyDlgEditH);
  Inc(y, TyDlgEditH + 8);

  if AWithReplace then
  begin
    MkLabel(rsDlgReplaceWith, x0, y + 4, 96);
    FReplaceEdit := TTyEdit.Create(Self);
    FReplaceEdit.Parent := Self;
    FReplaceEdit.SetBounds(editX, y, editW, TyDlgEditH);
    Inc(y, TyDlgEditH + 8);
  end;

  FMatchCase := MkCheck(rsDlgMatchCase, x0, y); Inc(y, 26);
  FWholeWord := MkCheck(rsDlgWholeWord, x0, y); Inc(y, 26);
  FSearchUp  := MkCheck(rsDlgSearchUp,  x0, y); Inc(y, 26);

  // Action buttons: AddButton(caption, mrNone) is non-closing (mrNone never sets
  // Form.ModalResult) yet still lands on the auto-laid-out button bar. OnClick
  // forwards to the public Do* seams.
  b := AddButton(rsDlgFindNext, mrNone); b.OnClick := @FindNextClick;
  if AWithReplace then
  begin
    b := AddButton(rsDlgReplace, mrNone);    b.OnClick := @ReplaceClick;
    b := AddButton(rsDlgReplaceAll, mrNone); b.OnClick := @ReplaceAllClick;
  end;
  b := AddButton(rsDlgFindClose, mrNone); b.OnClick := @CloseClick;

  AutoSizeToContent((editX - r.Left) + editW + TyDlgPad, (y - r.Top) + TyDlgPad);
end;

procedure TTyFindForm.SyncFrom(const AFindText, AReplaceText: string; AOptions: TFindOptions);
var ch: TTyFindChecks;
begin
  if FFindEdit = nil then Exit;
  FFindEdit.Text := AFindText;
  if FWithReplace and (FReplaceEdit <> nil) then FReplaceEdit.Text := AReplaceText;
  ch := TyFindOptionsToChecks(AOptions);
  FMatchCase.Checked := ch.MatchCase;
  FWholeWord.Checked := ch.WholeWord;
  FSearchUp.Checked  := ch.SearchUp;
end;

procedure TTyFindForm.WriteBack;
var ch: TTyFindChecks;
begin
  if FDlg = nil then Exit;
  FDlg.FFindText := FFindEdit.Text;
  if FWithReplace and (FReplaceEdit <> nil) then FDlg.FReplaceText := FReplaceEdit.Text;
  ch.MatchCase := FMatchCase.Checked;
  ch.WholeWord := FWholeWord.Checked;
  ch.SearchUp  := FSearchUp.Checked;
  FDlg.FOptions := TyChecksToFindOptions(ch, FDlg.FOptions);
end;

procedure TTyFindForm.DoFindNext;
begin
  WriteBack;
  if FDlg = nil then Exit;
  FDlg.FOptions := FDlg.FOptions - [frReplace, frReplaceAll] + [frFindNext];
  if Assigned(FDlg.FOnFind) then FDlg.FOnFind(FDlg);
end;

procedure TTyFindForm.DoReplace;
begin
  WriteBack;
  if FDlg = nil then Exit;
  FDlg.FOptions := FDlg.FOptions + [frReplace] - [frReplaceAll, frFindNext];
  if Assigned(FDlg.FOnReplace) then FDlg.FOnReplace(FDlg);
end;

procedure TTyFindForm.DoReplaceAll;
begin
  WriteBack;
  if FDlg = nil then Exit;
  FDlg.FOptions := FDlg.FOptions + [frReplaceAll] - [frFindNext, frReplace];
  if Assigned(FDlg.FOnReplace) then FDlg.FOnReplace(FDlg);
end;

procedure TTyFindForm.FindNextClick(Sender: TObject);   begin DoFindNext; end;
procedure TTyFindForm.ReplaceClick(Sender: TObject);    begin DoReplace; end;
procedure TTyFindForm.ReplaceAllClick(Sender: TObject); begin DoReplaceAll; end;
procedure TTyFindForm.CloseClick(Sender: TObject);      begin Hide; end;

procedure TTyFindForm.KeyDown(var Key: Word; Shift: TShiftState);
begin
  // The inherited (modal) Enter/Esc path sets ModalResult, which is inert on a
  // modeless form. Handle Enter/Esc here instead.
  if Key = VK_RETURN then
  begin
    if FWithReplace then DoReplace else DoFindNext;
    Key := 0; Exit;
  end;
  if Key = VK_ESCAPE then
  begin
    Hide;
    Key := 0; Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

function TTyFindForm.FindEdit: TTyEdit;         begin Result := FFindEdit; end;
function TTyFindForm.ReplaceEdit: TTyEdit;      begin Result := FReplaceEdit; end;
function TTyFindForm.MatchCaseCheck: TTyCheckBox; begin Result := FMatchCase; end;
function TTyFindForm.WholeWordCheck: TTyCheckBox; begin Result := FWholeWord; end;
function TTyFindForm.SearchUpCheck: TTyCheckBox;  begin Result := FSearchUp; end;

{ TTyFindDialog }

constructor TTyFindDialog.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FOptions := [frDown];
  FPosition := poScreenCenter;
end;

function TTyFindDialog.WantReplace: Boolean;
begin
  Result := False;
end;

function TTyFindDialog.BuildForm: TTyFindForm;
begin
  if FForm = nil then
  begin
    FForm := TTyFindForm.CreateNew(Self, 0);   // Owner = Self -> freed with the component
    FForm.FDlg := Self;
    FForm.Build(WantReplace);
  end;
  FForm.SyncFrom(FFindText, FReplaceText, FOptions);
  Result := FForm;
end;

function TTyFindDialog.Execute: Boolean;
begin
  if csDesigning in ComponentState then Exit(False);
  BuildForm;
  FForm.Position := FPosition;
  FForm.Show;
  Result := True;
end;

procedure TTyFindDialog.CloseDialog;
begin
  if FForm <> nil then FForm.Hide;
end;

end.
