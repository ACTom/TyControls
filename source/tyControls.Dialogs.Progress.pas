unit tyControls.Dialogs.Progress;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Forms, LCLType,
  tyControls.Dialogs, tyControls.ProgressBar, tyControls.TyLabel,
  tyControls.Button, tyControls.StrConsts;

type
  TTyProgressDialog = class;

  { TTyProgressForm — the reusable modeless progress window owned by a
    TTyProgressDialog. Pure UI + the DoCancel seam. }
  TTyProgressForm = class(TTyDialog)
  private
    FDlg: TTyProgressDialog;
    FBar: TTyProgressBar;
    FLabel: TTyLabel;
    FCancelBtn: TTyButton;        // nil unless cancelable
    procedure CancelClick(Sender: TObject);
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    procedure Build(ACancelable: Boolean);
    procedure UpdateView(APos, AMin, AMax: Integer; const AText: string);
    // test seams:
    function Bar: TTyProgressBar;
    function StatusLabel: TTyLabel;
  end;

  { TTyProgressDialog — stateful, app-driven, modeless. The app updates it in a
    loop and calls SetProgress; SetProgress pumps the message loop so the bar
    repaints and a Cancel click is seen. OnCancel MUST NOT Free this component. }
  TTyProgressDialog = class(TComponent)
  private
    FCaption: string;
    FText: string;
    FMin, FMax, FPosition: Integer;
    FCancelable, FCancelled: Boolean;
    FOnCancel: TNotifyEvent;
    FForm: TTyProgressForm;
    FInPump: Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    function BuildForm: TTyProgressForm;   // test seam: lazy build, NO Show
    procedure Show;
    procedure SetProgress(APos: Integer; const AText: string = '');
    procedure Step(ADelta: Integer = 1);
    procedure Close;
    procedure DoCancel;                    // seam: fired by the Cancel button / Esc
    property Cancelled: Boolean read FCancelled;
  published
    property Caption: string read FCaption write FCaption;
    property Text: string read FText write FText;
    property Min: Integer read FMin write FMin default 0;
    property Max: Integer read FMax write FMax default 100;
    property Position: Integer read FPosition write FPosition default 0;
    property Cancelable: Boolean read FCancelable write FCancelable default False;
    property OnCancel: TNotifyEvent read FOnCancel write FOnCancel;
  end;

implementation

{ TTyProgressForm }

procedure TTyProgressForm.Build(ACancelable: Boolean);
var r: TRect; x0, y, contentW: Integer;
begin
  r := ContentRect;
  x0 := r.Left + TyDlgPad;
  y := r.Top + TyDlgPad;
  contentW := 360;

  FLabel := TTyLabel.Create(Self);
  FLabel.Parent := Self;
  FLabel.SetBounds(x0, y, contentW, 20);
  Inc(y, 28);

  FBar := TTyProgressBar.Create(Self);
  FBar.Parent := Self;
  FBar.SetBounds(x0, y, contentW, 20);
  Inc(y, 28);

  if ACancelable then
  begin
    FCancelBtn := AddButton(rsDlgProgressCancel, mrNone);
    FCancelBtn.OnClick := @CancelClick;
  end;

  AutoSizeToContent(contentW + TyDlgPad, (y - r.Top) + TyDlgPad);
end;

procedure TTyProgressForm.UpdateView(APos, AMin, AMax: Integer; const AText: string);
begin
  if FBar = nil then Exit;
  FBar.Min := AMin;
  FBar.Max := AMax;
  FBar.Position := APos;
  FLabel.Caption := AText;
end;

procedure TTyProgressForm.CancelClick(Sender: TObject);
begin
  if FDlg <> nil then FDlg.DoCancel;
end;

procedure TTyProgressForm.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    if (FDlg <> nil) and FDlg.Cancelable then FDlg.DoCancel;
    Key := 0; Exit;                 // never let Esc close a progress dialog
  end;
  if Key = VK_RETURN then begin Key := 0; Exit; end;   // ignore Enter
  inherited KeyDown(Key, Shift);
end;

function TTyProgressForm.Bar: TTyProgressBar; begin Result := FBar; end;
function TTyProgressForm.StatusLabel: TTyLabel; begin Result := FLabel; end;

{ TTyProgressDialog }

constructor TTyProgressDialog.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMin := 0;
  FMax := 100;
  FPosition := 0;
end;

function TTyProgressDialog.BuildForm: TTyProgressForm;
begin
  if FForm = nil then
  begin
    FForm := TTyProgressForm.CreateNew(Self, 0);   // Owner = Self
    FForm.FDlg := Self;
    FForm.Build(FCancelable);
  end;
  FForm.Caption := FCaption;
  FForm.UpdateView(FPosition, FMin, FMax, FText);
  Result := FForm;
end;

procedure TTyProgressDialog.Show;
begin
  if csDesigning in ComponentState then Exit;
  FCancelled := False;
  BuildForm;
  FForm.Show;
end;

procedure TTyProgressDialog.SetProgress(APos: Integer; const AText: string);
begin
  if APos < FMin then APos := FMin;
  if APos > FMax then APos := FMax;
  FPosition := APos;
  if AText <> '' then FText := AText;
  // Only touch the view + pump when the form actually exists and is on screen —
  // headless (unshown) callers just clamp state, so tests never pump.
  if (FForm <> nil) and FForm.Visible then
  begin
    FForm.UpdateView(FPosition, FMin, FMax, FText);
    if not FInPump then
    begin
      FInPump := True;
      try
        Application.ProcessMessages;
      finally
        FInPump := False;
      end;
    end;
  end;
end;

procedure TTyProgressDialog.Step(ADelta: Integer);
begin
  SetProgress(FPosition + ADelta);
end;

procedure TTyProgressDialog.Close;
begin
  FCancelled := False;
  if FForm <> nil then FForm.Hide;
end;

procedure TTyProgressDialog.DoCancel;
begin
  FCancelled := True;
  if Assigned(FOnCancel) then FOnCancel(Self);
end;

end.
