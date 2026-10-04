unit tyControls.Dialogs.Find;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Dialogs, LCLType,
  tyControls.Dialogs, tyControls.Edit, tyControls.CheckBox, tyControls.Button,
  tyControls.TyLabel, tyControls.Component, tyControls.StrConsts;

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
    FHelpBtn: TTyButton;
    { Where the check boxes start, and the content box the form is sized to -- kept from Build
      so LayoutChecks can re-stack the boxes that are showing. }
    FChecksLeft, FChecksTop, FContentTop, FContentW: Integer;
    procedure FindNextClick(Sender: TObject);
    procedure ReplaceClick(Sender: TObject);
    procedure ReplaceAllClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure HelpClick(Sender: TObject);
    procedure WriteBack;
    { Stack the visible check boxes from FChecksTop, a hidden one leaving no gap, and size the
      form to the last one. }
    procedure LayoutChecks;
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    procedure Build(AWithReplace: Boolean);
    procedure SyncFrom(const AFindText, AReplaceText: string; AOptions: TFindOptions);
    { The options' share of SyncFrom: check states, the frHide* / frDisable* gates, the Help
      button -- without touching the text the user may have typed. }
    procedure ApplyOptions(AOptions: TFindOptions);
    procedure DoFindNext;
    procedure DoReplace;
    procedure DoReplaceAll;
    // test seams:
    function FindEdit: TTyEdit;
    function ReplaceEdit: TTyEdit;
    function MatchCaseCheck: TTyCheckBox;
    function WholeWordCheck: TTyCheckBox;
    function SearchUpCheck: TTyCheckBox;
    function HelpButton: TTyButton;
    property WithReplace: Boolean read FWithReplace;
  end;

  { TTyFindDialog — non-visual, modeless. Owns a TTyFindForm; fires OnFind when the
    user clicks Find Next (or presses Enter). LCL TFindDialog parity. }
  TTyFindDialog = class(TTyComponent)
  private
    FFindText: string;
    FReplaceText: string;        // populated by TTyReplaceDialog
    FOptions: TFindOptions;
    FPosition: TPosition;
    FOnFind: TNotifyEvent;
    FOnReplace: TNotifyEvent;    // used by TTyReplaceDialog
    FOnShow: TNotifyEvent;
    FOnClose: TCloseEvent;
    FOnCanClose: TCloseQueryEvent;
    FOnHelpClicked: TNotifyEvent;
    FForm: TTyFindForm;
    procedure SetOptions(AValue: TFindOptions);
  protected
    function WantReplace: Boolean; virtual;
    procedure DoHelpClicked;
  public
    constructor Create(AOwner: TComponent); override;
    function BuildForm: TTyFindForm;   // test seam: lazy build + sync, NO Show
    function Execute: Boolean;
    procedure PreviewInDesigner;       // guard-free Execute body, for the component editor
    procedure CloseDialog;
  published
    property FindText: string read FFindText write FFindText;
    { LCL's TFindOptions. The ones 3.0 acts on besides frMatchCase / frWholeWord / frDown are
      the gates of LCL's SetFormValues: frHide* hide a box, frDisable* grey it, frShowHelp
      shows a Help button. Writing Options while the window is open updates the window. }
    property Options: TFindOptions read FOptions write SetOptions default [frDown];
    property Position: TPosition read FPosition write FPosition default poScreenCenter;
    property OnFind: TNotifyEvent read FOnFind write FOnFind;
    property OnShow: TNotifyEvent read FOnShow write FOnShow;
    property OnClose: TCloseEvent read FOnClose write FOnClose;
    property OnCanClose: TCloseQueryEvent read FOnCanClose write FOnCanClose;
    { The Help button (shown with frShowHelp) was clicked. Sender is this component. }
    property OnHelpClicked: TNotifyEvent read FOnHelpClicked write FOnHelpClicked;
  end;

  { TTyReplaceDialog — adds the Replace row + Replace/Replace All buttons. Replace
    and Replace All both fire OnReplace; the app distinguishes them via
    (frReplaceAll in Options). }
  TTyReplaceDialog = class(TTyFindDialog)
  protected
    function WantReplace: Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ReplaceText: string read FReplaceText write FReplaceText;
    property OnReplace: TNotifyEvent read FOnReplace write FOnReplace;
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
    Result.SetBounds(ALeft, ATop, AWidth, Px(20));
  end;

  function MkCheck(const ACaption: string; ALeft, ATop: Integer): TTyCheckBox;
  begin
    Result := TTyCheckBox.Create(Self);
    Result.Parent := Self;
    Result.Caption := ACaption;
    Result.SetBounds(ALeft, ATop, Px(160), Px(22));
  end;

begin
  FWithReplace := AWithReplace;
  if AWithReplace then Caption := rsDlgReplaceTitle
  else Caption := rsDlgFindTitle;
  { Every number below is a 96-PPI design number and goes through Px: see TTyDialog.Px. }
  r := ContentRect;
  x0 := r.Left + Px(TyDlgPad);
  y := r.Top + Px(TyDlgPad);
  editX := x0 + Px(100);
  editW := Px(TyDlgEditW);

  MkLabel(rsDlgFindWhat, x0, y + Px(4), Px(96));
  FFindEdit := TTyEdit.Create(Self);
  FFindEdit.Parent := Self;
  FFindEdit.SetBounds(editX, y, editW, Px(TyDlgEditH));
  y := FFindEdit.Top + FFindEdit.Height + Px(8);

  if AWithReplace then
  begin
    MkLabel(rsDlgReplaceWith, x0, y + Px(4), Px(96));
    FReplaceEdit := TTyEdit.Create(Self);
    FReplaceEdit.Parent := Self;
    FReplaceEdit.SetBounds(editX, y, editW, Px(TyDlgEditH));
    y := FReplaceEdit.Top + FReplaceEdit.Height + Px(8);
  end;

  { The stride is the box's own height + 4, not a literal 26: TTyCheckBox floors its height on
    the theme's font, padding and --checkbox-size, LCL enforces that floor inside SetBounds, and
    at modern density the boxes outgrow 26 and eat each other. }
  FChecksLeft := x0;
  FChecksTop := y;
  FMatchCase := MkCheck(rsDlgMatchCase, x0, y); y := FMatchCase.Top + FMatchCase.Height + Px(4);
  FWholeWord := MkCheck(rsDlgWholeWord, x0, y); y := FWholeWord.Top + FWholeWord.Height + Px(4);
  FSearchUp  := MkCheck(rsDlgSearchUp,  x0, y); y := FSearchUp.Top + FSearchUp.Height + Px(4);

  // Action buttons: AddButton(caption, mrNone) is non-closing (mrNone never sets
  // Form.ModalResult) yet still lands on the auto-laid-out button bar. OnClick
  // forwards to the public Do* seams.
  b := AddButton(rsDlgFindNext, mrNone); b.OnClick := @FindNextClick;
  if AWithReplace then
  begin
    b := AddButton(rsDlgReplace, mrNone);    b.OnClick := @ReplaceClick;
    b := AddButton(rsDlgReplaceAll, mrNone); b.OnClick := @ReplaceAllClick;
  end;
  b := AddButton(rsMsgBtnClose, mrNone); b.OnClick := @CloseClick;
  { Help (frShowHelp) is built once and shown or hidden per Options; the bar gives a hidden
    button no slot. }
  FHelpBtn := AddButton(rsMsgBtnHelp, mrNone);
  FHelpBtn.OnClick := @HelpClick;
  FHelpBtn.Visible := False;

  FContentTop := r.Top;
  FContentW := (editX - r.Left) + editW + Px(TyDlgPad);
  AutoSizeToContent(FContentW, (y - r.Top) + Px(TyDlgPad));
end;

procedure TTyFindForm.LayoutChecks;
var
  boxes: array[0..2] of TTyCheckBox;
  i, y: Integer;
begin
  if FMatchCase = nil then Exit;
  boxes[0] := FMatchCase;
  boxes[1] := FWholeWord;
  boxes[2] := FSearchUp;
  y := FChecksTop;
  for i := 0 to High(boxes) do
    if boxes[i].Visible then
    begin
      boxes[i].SetBounds(FChecksLeft, y, Px(160), Px(22));
      y := boxes[i].Top + boxes[i].Height + Px(4);
    end;
  AutoSizeToContent(FContentW, (y - FContentTop) + Px(TyDlgPad));
end;

procedure TTyFindForm.ApplyOptions(AOptions: TFindOptions);
var ch: TTyFindChecks;
begin
  if FMatchCase = nil then Exit;
  ch := TyFindOptionsToChecks(AOptions);
  FMatchCase.Checked := ch.MatchCase;
  FWholeWord.Checked := ch.WholeWord;
  FSearchUp.Checked  := ch.SearchUp;
  { LCL's SetFormValues, gate for gate: hiding takes the box out of the layout, disabling only
    greys it. 3.0.0 accepted these and ignored them. }
  FMatchCase.Visible := not (frHideMatchCase in AOptions);
  FWholeWord.Visible := not (frHideWholeWord in AOptions);
  FSearchUp.Visible  := not (frHideUpDown in AOptions);
  FMatchCase.Enabled := not (frDisableMatchCase in AOptions);
  FWholeWord.Enabled := not (frDisableWholeWord in AOptions);
  FSearchUp.Enabled  := not (frDisableUpDown in AOptions);
  FHelpBtn.Visible := frShowHelp in AOptions;
  LayoutChecks;   // re-stacks the boxes, re-sizes the form and re-lays the button bar
end;

procedure TTyFindForm.SyncFrom(const AFindText, AReplaceText: string; AOptions: TFindOptions);
begin
  if FFindEdit = nil then Exit;
  FFindEdit.Text := AFindText;
  if FWithReplace and (FReplaceEdit <> nil) then FReplaceEdit.Text := AReplaceText;
  ApplyOptions(AOptions);
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
procedure TTyFindForm.HelpClick(Sender: TObject);
begin
  if FDlg <> nil then FDlg.DoHelpClicked;
end;

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
function TTyFindForm.HelpButton: TTyButton;       begin Result := FHelpBtn; end;

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

procedure TTyFindDialog.SetOptions(AValue: TFindOptions);
begin
  if FOptions = AValue then Exit;
  FOptions := AValue;
  { As LCL's TFindDialog.SetOptions: an open window follows. Only the option-driven part --
    the find text the user is typing is not reset from FFindText here. }
  if FForm <> nil then FForm.ApplyOptions(FOptions);
end;

procedure TTyFindDialog.DoHelpClicked;
begin
  if Assigned(FOnHelpClicked) then FOnHelpClicked(Self);
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
  // Relay the LCL-parity events onto the modeless form (idempotent — safe each call).
  TyForwardDialogEvents(FForm, FOnShow, FOnClose, FOnCanClose);
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

procedure TTyFindDialog.PreviewInDesigner;
begin
  BuildForm;
  FForm.Position := FPosition;
  FForm.Show;
end;

procedure TTyFindDialog.CloseDialog;
begin
  if FForm <> nil then FForm.Hide;
end;

{ TTyReplaceDialog }

constructor TTyReplaceDialog.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FOptions := FOptions + [frReplace, frReplaceAll];   // LCL Replace defaults
end;

function TTyReplaceDialog.WantReplace: Boolean;
begin
  Result := True;
end;

end.
