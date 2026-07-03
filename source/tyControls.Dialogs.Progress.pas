unit tyControls.Dialogs.Progress;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Forms, LCLType, ExtCtrls,
  tyControls.Dialogs, tyControls.ProgressBar, tyControls.TyLabel,
  tyControls.Button, tyControls.StrConsts;

type
  TTyProgressDialog = class;

  { TTyProgressForm — the reusable modeless progress window owned by a
    TTyProgressDialog. Pure UI + the DoCancel seam. }
  TTyProgressForm = class(TTyDialog)
  private
    FDlg: TTyProgressDialog;
    FPane: TPanel;                // double-buffered windowed host for the graphic label+bar
    FBar: TTyProgressBar;
    FLabel: TTyLabel;
    FCancelBtn: TTyButton;        // nil unless cancelable
    procedure CancelClick(Sender: TObject);
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoShow; override;
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
    FOnShow: TNotifyEvent;
    FOnClose: TCloseEvent;
    FOnCanClose: TCloseQueryEvent;
    FForm: TTyProgressForm;
    FInPump: Boolean;
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
  published
    property Caption: string read FCaption write FCaption;
    property Text: string read FText write FText;
    property Min: Integer read FMin write FMin default 0;
    property Max: Integer read FMax write FMax default 100;
    property Position: Integer read FPosition write FPosition default 0;
    property Cancelable: Boolean read FCancelable write FCancelable default False;
    property OnCancel: TNotifyEvent read FOnCancel write FOnCancel;
    property OnShow: TNotifyEvent read FOnShow write FOnShow;
    property OnClose: TCloseEvent read FOnClose write FOnClose;
    property OnCanClose: TCloseQueryEvent read FOnCanClose write FOnCanClose;
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

  // The label and bar are GRAPHIC controls (they paint onto their parent's canvas).
  // Parenting them straight to the form means every SetProgress repaint goes through
  // the top-level window's WM_PAINT — erase, refill the surface, then redraw the bar,
  // all straight to screen — which flickers. Host them on a windowed, DOUBLE-BUFFERED
  // pane instead: their repaints composite offscreen and blit once (no flicker). The
  // pane is a CHILD window, so the form's Win10 DWM glass extend does not apply and
  // double buffering is safe; ParentColor keeps its opaque fill on the themed surface
  // and it is borderless (bvNone) so the dialog looks unchanged.
  FPane := TPanel.Create(Self);
  FPane.Parent := Self;
  FPane.BevelOuter := bvNone;
  FPane.BorderStyle := bsNone;
  FPane.Caption := '';
  FPane.ParentBackground := False;   // paint a solid Color, not the parent's themed bg
  FPane.ParentColor := True;         // Color follows the form's themed surface
  FPane.DoubleBuffered := True;
  FPane.SetBounds(x0, y, contentW, 48);

  FLabel := TTyLabel.Create(Self);
  FLabel.Parent := FPane;
  // Fixed-width status line: don't auto-resize/relayout (and repaint) on every text
  // change — that is a flicker source when SetProgress is called in a tight loop.
  FLabel.AutoSize := False;
  FLabel.SetBounds(0, 0, contentW, 20);

  FBar := TTyProgressBar.Create(Self);
  FBar.Parent := FPane;
  // The dialog is driven by discrete SetProgress calls (typically a tight loop that
  // pumps Application.ProcessMessages). The bar's 60fps tween timer, re-armed on
  // every call, just churns repaints against the loop — snap to each reported
  // position instead of animating.
  FBar.AnimationsEnabled := False;
  FBar.SetBounds(0, 28, contentW, 20);
  Inc(y, 56);

  if ACancelable then
  begin
    FCancelBtn := AddButton(rsMsgBtnCancel, mrNone);
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

procedure TTyProgressForm.DoShow;
begin
  inherited DoShow;   // TTyDialog.DoShow adopts the app theme first -> form Color = surface
  // The host pane is a plain (unthemed) windowed control. Give its opaque fill the
  // form's themed surface Color EXPLICITLY (ApplyChromeTheme set it) so it matches the
  // dialog instead of the LCL default (white/grey) — ParentColor did not track the
  // CreateNew dialog's DoShow-time colour set.
  if FPane <> nil then FPane.Color := Color;
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
  // Relay the LCL-parity events onto the modeless form (idempotent — safe each call).
  TyForwardDialogEvents(FForm, FOnShow, FOnClose, FOnCanClose);
  Result := FForm;
end;

procedure TTyProgressDialog.Show;
begin
  if csDesigning in ComponentState then Exit;
  FCancelled := False;
  BuildForm;
  FForm.Show;
end;

procedure TTyProgressDialog.PreviewInDesigner;
begin
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
