unit tyControls.Dialogs.Progress;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Forms, LCLType,
  tyControls.Dialogs, tyControls.ProgressBar, tyControls.TyLabel,
  tyControls.Button, tyControls.Component, tyControls.StrConsts;

type
  TTyProgressDialog = class;
  TTyCustomProgressDialog = class;

  { TTyProgressForm — the reusable modeless progress window owned by a
    TTyProgressDialog. Pure UI + the DoCancel seam. }
  TTyProgressForm = class(TTyDialog)
  private
    FDlg: TTyCustomProgressDialog;
    FBar: TTyProgressBar;
    FLabel: TTyLabel;
    FCancelBtn: TTyButton;        // built always, shown while cancelable (#179)
    procedure CancelClick(Sender: TObject);
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    { #179: the title bar's X is the user cancelling, as the Cancel button is -- Cancelled and
      OnCancel, the window kept until the application, seeing them, closes it. Only the
      dialog's own Close goes on to OnCanClose and OnClose. }
    function CloseQuery: Boolean; override;
    { The window is the dialog's, shown again by the next Show: a close only hides it. }
    procedure DoClose(var CloseAction: TCloseAction); override;
  public
    procedure Build(ACancelable: Boolean);
    { The Cancel button and the title bar's X, there while ACancelable (#179). }
    procedure ApplyCancelable(ACancelable: Boolean);
    procedure UpdateView(APos, AMin, AMax: Integer; const AText: string);
    // test seams:
    function Bar: TTyProgressBar;
    function StatusLabel: TTyLabel;
  end;

  { TTyProgressDialog — stateful, app-driven, modeless. The app updates it in a
    loop and calls SetProgress; SetProgress pumps the message loop so the bar
    repaints and a Cancel click is seen. OnCancel MUST NOT Free this component. }
  TTyCustomProgressDialog = class(TTyComponent)
  private
    FCaption: TCaption;
    FText: TCaption;
    FMin, FMax, FPosition: Integer;
    FCancelable, FCancelled: Boolean;
    FOnCancel: TNotifyEvent;
    FOnShow: TNotifyEvent;
    FOnClose: TCloseEvent;
    FOnCanClose: TCloseQueryEvent;
    FForm: TTyProgressForm;
    FInPump: Boolean;
    FClosing: Boolean;      // inside Close: the window's close is the application's (#179)
    FLastViewTick: QWord;   // last time the view was actually repainted (refresh throttle)
    procedure SetCaption(const AValue: TCaption);
    procedure SetText(const AValue: TCaption);
    procedure SetMin(AValue: Integer);
    procedure SetMax(AValue: Integer);
    procedure SetPosition(AValue: Integer);
    procedure SetCancelable(AValue: Boolean);
    { Position inside Min..Max, and an open window showing what the properties say (#179). }
    procedure ClampPosition;
    procedure RefreshView;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    function BuildForm: TTyProgressForm;   // test seam: lazy build, NO Show
    procedure Show;
    procedure PreviewInDesigner;           // guard-free Show body, for the component editor
    procedure SetProgress(APos: Integer; const AText: string = '');
    procedure Step(ADelta: Integer = 1);
    procedure Close;
    procedure DoCancel;                    // seam: fired by the Cancel button / Esc
    property Cancelled: Boolean read FCancelled;
    property Caption: TCaption read FCaption write SetCaption;
    property Text: TCaption read FText write SetText;
    property Min: Integer read FMin write SetMin default 0;
    property Max: Integer read FMax write SetMax default 100;
    property Position: Integer read FPosition write SetPosition default 0;
    property Cancelable: Boolean read FCancelable write SetCancelable default False;
    property OnCancel: TNotifyEvent read FOnCancel write FOnCancel;
    property OnShow: TNotifyEvent read FOnShow write FOnShow;
    property OnClose: TCloseEvent read FOnClose write FOnClose;
    property OnCanClose: TCloseQueryEvent read FOnCanClose write FOnCanClose;
  end;

  { TTyProgressDialog publishes TTyCustomProgressDialog's properties; everything lives in TTyCustomProgressDialog. }
  TTyProgressDialog = class(TTyCustomProgressDialog)
  published
    property Version;
    property Caption;
    property Text;
    property Min;
    property Max;
    property Position;
    property Cancelable;
    property OnCancel;
    property OnShow;
    property OnClose;
    property OnCanClose;
  end;

implementation

{ TTyProgressForm }

procedure TTyProgressForm.Build(ACancelable: Boolean);
var r: TRect; x0, y, contentW: Integer;
begin
  { Every number below is a 96-PPI design number and goes through Px: see TTyDialog.Px. }
  r := ContentRect;
  x0 := r.Left + Px(TyDlgPad);
  y := r.Top + Px(TyDlgPad);
  contentW := Px(360);

  FLabel := TTyLabel.Create(Self);
  FLabel.Parent := Self;
  // Fixed-width status line: don't auto-resize/relayout (and repaint) on every text
  // change — that is a flicker source when SetProgress is called in a tight loop.
  FLabel.AutoSize := False;
  FLabel.SetBounds(x0, y, contentW, Px(20));
  Inc(y, Px(28));

  FBar := TTyProgressBar.Create(Self);
  FBar.Parent := Self;
  // The dialog is driven by discrete SetProgress calls (typically a tight loop that
  // pumps Application.ProcessMessages). The bar's 60fps tween timer, re-armed on
  // every call, just churns repaints of this graphic control against the loop —
  // seen as the text/bar "flicker". Snap directly to each reported position instead.
  FBar.AnimationsEnabled := False;
  FBar.SetBounds(x0, y, contentW, Px(20));
  Inc(y, Px(28));

  { Built whether or not the dialog is cancelable, so a Cancelable changed after the first Show
    can still show it (#179). }
  FCancelBtn := AddButton(rsMsgBtnCancel, mrNone);
  FCancelBtn.OnClick := @CancelClick;
  AutoSizeToContent(contentW + Px(TyDlgPad), (y - r.Top) + Px(TyDlgPad));
  ApplyCancelable(ACancelable);
end;

procedure TTyProgressForm.ApplyCancelable(ACancelable: Boolean);
begin
  if FCancelBtn = nil then Exit;
  FCancelBtn.Visible := ACancelable;
  if ACancelable then BorderIcons := [biSystemMenu] else BorderIcons := [];
  LayoutButtonBar;
end;

function TTyProgressForm.CloseQuery: Boolean;
begin
  if (FDlg <> nil) and not FDlg.FClosing then
  begin
    if FDlg.Cancelable then FDlg.DoCancel;
    Exit(False);
  end;
  Result := inherited CloseQuery;
end;

procedure TTyProgressForm.DoClose(var CloseAction: TCloseAction);
begin
  inherited DoClose(CloseAction);
  CloseAction := caHide;
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

{ TTyCustomProgressDialog }

constructor TTyCustomProgressDialog.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMin := 0;
  FMax := 100;
  FPosition := 0;
end;

function TTyCustomProgressDialog.BuildForm: TTyProgressForm;
begin
  if FForm = nil then
  begin
    FForm := TTyProgressForm.CreateNew(Self, 0);   // Owner = Self
    FForm.FDlg := Self;
    FForm.Build(FCancelable);
  end;
  FForm.ApplyCancelable(FCancelable);
  FForm.Caption := FCaption;
  FForm.UpdateView(FPosition, FMin, FMax, FText);
  // Relay the LCL-parity events onto the modeless form (idempotent — safe each call).
  TyForwardDialogEvents(Self, FForm, FOnShow, FOnClose, FOnCanClose);
  Result := FForm;
end;

procedure TTyCustomProgressDialog.Show;
begin
  if csDesigning in ComponentState then Exit;
  FCancelled := False;
  BuildForm;
  FForm.Show;
end;

procedure TTyCustomProgressDialog.PreviewInDesigner;
begin
  FCancelled := False;
  BuildForm;
  FForm.Show;
end;

const
  { The bar + label are graphic controls: each repaint erases and redraws them
    against the form, which flickers when the app drives SetProgress in a tight
    loop. Coalesce the VISUAL refresh to ~20fps — the newest state is always kept
    (FPosition/FText), a skipped call only defers its repaint to the next tick, and
    completion always flushes so 100% is shown. This caps the repaint frequency
    (the flicker) without changing the reported progress. }
  cProgressRefreshMs = 50;

procedure TTyCustomProgressDialog.SetProgress(APos: Integer; const AText: string);
var nowTick: QWord;
begin
  if APos < FMin then APos := FMin;
  if APos > FMax then APos := FMax;
  FPosition := APos;
  if AText <> '' then FText := AText;
  // Only touch the view + pump when the form actually exists and is on screen —
  // headless (unshown) callers just clamp state, so tests never pump.
  if (FForm <> nil) and FForm.Visible then
  begin
    nowTick := GetTickCount64;
    // Throttle: repaint at most every cProgressRefreshMs, but always at completion.
    if (FPosition < FMax) and (nowTick - FLastViewTick < cProgressRefreshMs) then Exit;
    FLastViewTick := nowTick;
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

procedure TTyCustomProgressDialog.Step(ADelta: Integer);
begin
  SetProgress(FPosition + ADelta);
end;

procedure TTyCustomProgressDialog.Close;
begin
  { Cancelled stays as it was (#179): the loop that ends with Close reads it afterwards. Show
    starts the next run afresh. A close of the window's own, so OnCanClose and OnClose hear. }
  if FForm = nil then Exit;
  FClosing := True;
  try
    FForm.Close;
  finally
    FClosing := False;
  end;
end;

procedure TTyCustomProgressDialog.SetCaption(const AValue: TCaption);
begin
  FCaption := AValue;
  if FForm <> nil then FForm.Caption := AValue;
end;

procedure TTyCustomProgressDialog.SetText(const AValue: TCaption);
begin
  FText := AValue;
  RefreshView;
end;

procedure TTyCustomProgressDialog.SetMin(AValue: Integer);
begin
  FMin := AValue;
  ClampPosition;
  RefreshView;
end;

procedure TTyCustomProgressDialog.SetMax(AValue: Integer);
begin
  FMax := AValue;
  ClampPosition;
  RefreshView;
end;

procedure TTyCustomProgressDialog.SetPosition(AValue: Integer);
begin
  FPosition := AValue;
  ClampPosition;
  RefreshView;
end;

procedure TTyCustomProgressDialog.SetCancelable(AValue: Boolean);
begin
  FCancelable := AValue;
  if FForm <> nil then FForm.ApplyCancelable(AValue);
end;

procedure TTyCustomProgressDialog.ClampPosition;
begin
  // Not while the form is read: Min, Max and Position arrive one at a time (Loaded clamps).
  if (csLoading in ComponentState) or (FMax < FMin) then Exit;
  if FPosition < FMin then FPosition := FMin;
  if FPosition > FMax then FPosition := FMax;
end;

procedure TTyCustomProgressDialog.RefreshView;
begin
  if FForm <> nil then FForm.UpdateView(FPosition, FMin, FMax, FText);
end;

procedure TTyCustomProgressDialog.Loaded;
begin
  inherited Loaded;
  ClampPosition;
end;

procedure TTyCustomProgressDialog.DoCancel;
begin
  FCancelled := True;
  if Assigned(FOnCancel) then FOnCancel(Self);
end;

end.
