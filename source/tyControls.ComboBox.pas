unit tyControls.ComboBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, LCLType, LCLIntf,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.ListBox;
type
  TTyComboBox = class(TTyCustomControl)
  private
    FItems: TStringList;
    FItemIndex: Integer;
    FText: string;
    FOnChange: TNotifyEvent;
    { Dropdown popup state }
    FPopup: TForm;           // lazy; created on first DropDown; freed in Destroy
    FPopupList: TTyListBox;  // owned by FPopup
    procedure SetItems(const AValue: TStringList);
    procedure SetItemIndex(const AValue: Integer);
    procedure SetText(const AValue: string);
    function ButtonWidthLogical: Integer;
    { Popup event handlers }
    procedure PopupListChange(Sender: TObject);
    procedure PopupDeactivate(Sender: TObject);
    procedure PopupKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  protected
    { Guard: tick at last CloseUp. Click reopens only if > 200ms have passed.
      This prevents the click-while-open reopen race where PopupDeactivate fires
      CloseUp BEFORE Click runs, so Click would see DroppedDown=False and reopen.
      Protected so test subclasses can manipulate it for headless logic tests. }
    FCloseUpTick: QWord;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure Click; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function GetStyleTypeKey: string; override;
    procedure SelectItem(AIndex: Integer);
    function DroppedDown: Boolean;
    procedure DropDown;
    procedure CloseUp;
    { Expose popup list for headless tests and internal use }
    function PopupList: TTyListBox;
  published
    property Items: TStringList read FItems write SetItems;
    property ItemIndex: Integer read FItemIndex write SetItemIndex;
    property Text: string read FText write SetText;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;
implementation
uses
  Math;

constructor TTyComboBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TStringList.Create;
  FItemIndex := -1;
  FText := '';
  FPopup := nil;
  FPopupList := nil;
  TabStop := True;
  Width := 145;
  Height := 26;
end;

destructor TTyComboBox.Destroy;
begin
  { Free popup (and its owned listbox) if it was ever created.
    We must detach the OnDeactivate handler first to avoid re-entering CloseUp
    from the TForm destruction path. }
  if FPopup <> nil then
  begin
    FPopup.OnDeactivate := nil;
    FreeAndNil(FPopup);
    FPopupList := nil;  // freed by FPopup (was owned by it)
  end;
  FItems.Free;
  inherited Destroy;
end;

function TTyComboBox.GetStyleTypeKey: string;
begin
  Result := 'TyComboBox';
end;

procedure TTyComboBox.SetItems(const AValue: TStringList);
begin
  FItems.Assign(AValue);
  Invalidate;
end;

procedure TTyComboBox.SetText(const AValue: string);
begin
  if FText = AValue then Exit;
  FText := AValue;
  Invalidate;
end;

procedure TTyComboBox.SetItemIndex(const AValue: Integer);
begin
  SelectItem(AValue);
end;

function TTyComboBox.ButtonWidthLogical: Integer;
begin
  Result := 18;
end;

procedure TTyComboBox.SelectItem(AIndex: Integer);
var
  NewIndex: Integer;
  NewText: string;
begin
  if (AIndex >= 0) and (AIndex < FItems.Count) then
  begin
    NewIndex := AIndex;
    NewText := FItems[AIndex];
  end
  else
  begin
    NewIndex := -1;
    NewText := '';
  end;
  if (NewIndex = FItemIndex) and (NewText = FText) then Exit;
  FItemIndex := NewIndex;
  FText := NewText;
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

function TTyComboBox.DroppedDown: Boolean;
begin
  Result := (FPopup <> nil) and FPopup.Visible;
end;

{ Ensure the popup form and its TTyListBox child exist.
  Called lazily on first DropDown. }
procedure TTyComboBox.DropDown;
var
  PopupH, PopupW, ScaledIH: Integer;
  P: TPoint;
  ParentForm: TCustomForm;
begin
  if FItems.Count = 0 then Exit;

  { Lazily create the popup form + listbox }
  if FPopup = nil then
  begin
    FPopup := TForm.CreateNew(nil);
    FPopup.BorderStyle := bsNone;
    FPopup.ShowInTaskBar := stNever;
    FPopup.FormStyle := fsStayOnTop;

    ParentForm := GetParentForm(Self);
    if ParentForm <> nil then
    begin
      FPopup.PopupParent := ParentForm;
      FPopup.PopupMode := pmExplicit;
    end;

    FPopup.KeyPreview := True;
    FPopup.OnDeactivate := @PopupDeactivate;
    FPopup.OnKeyDown := @PopupKeyDown;

    FPopupList := TTyListBox.Create(FPopup);
    FPopupList.Parent := FPopup;
    FPopupList.Align := alClient;
    FPopupList.Controller := Self.Controller;
    FPopupList.OnChange := @PopupListChange;
  end;

  { Sync items and selection — detach OnChange to prevent recursion }
  FPopupList.OnChange := nil;
  FPopupList.Items.Assign(FItems);
  { Use the private field path via SelectItem with temp guard:
    SelectItem won't fire our nil'd OnChange anyway }
  FPopupList.SelectItem(FItemIndex);
  FPopupList.OnChange := @PopupListChange;

  { Size: height = min(8, Items.Count) rows }
  ScaledIH := MulDiv(FPopupList.ItemHeight, Font.PixelsPerInch, 96);
  PopupH := Min(8, FItems.Count) * ScaledIH + 2;
  PopupW := Width;

  { Position below the combo }
  P := ControlToScreen(Point(0, Height));
  FPopup.SetBounds(P.X, P.Y, PopupW, PopupH);

  FPopup.Show;
end;

procedure TTyComboBox.CloseUp;
begin
  if (FPopup <> nil) and FPopup.Visible then
  begin
    { Detach deactivate to prevent re-entering CloseUp from Hide }
    FPopup.OnDeactivate := nil;
    FPopup.Hide;
    FPopup.OnDeactivate := @PopupDeactivate;
  end;
  FCloseUpTick := GetTickCount64;
  Invalidate;
end;

procedure TTyComboBox.Click;
begin
  inherited Click;
  { If dropped down, close. Otherwise open — but guard the reopen race:
    clicking the combo while it is open fires PopupDeactivate→CloseUp BEFORE
    this Click handler runs, so DroppedDown is already False here. We suppress
    reopen if CloseUp happened within the last 200 ms. }
  if DroppedDown then
    CloseUp
  else if GetTickCount64 - FCloseUpTick > 200 then
    DropDown;
end;

procedure TTyComboBox.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  if (Key = VK_ESCAPE) and DroppedDown then
  begin
    CloseUp;
    Key := 0;
  end;
end;

{ Popup event handlers }

procedure TTyComboBox.PopupListChange(Sender: TObject);
begin
  SelectItem(FPopupList.ItemIndex);
  CloseUp;
end;

procedure TTyComboBox.PopupDeactivate(Sender: TObject);
begin
  CloseUp;
end;

procedure TTyComboBox.PopupKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    CloseUp;
    Key := 0;
  end;
end;

{ Protected accessor for headless tests }
function TTyComboBox.PopupList: TTyListBox;
begin
  Result := FPopupList;
end;

procedure TTyComboBox.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R, TextR, BtnR: TRect;
  BtnW: Integer;
begin
  P := TTyPainter.Create;
  try
    R := ARect;
    P.BeginPaint(ACanvas, R, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    BtnW := P.Scale(ButtonWidthLogical);
    BtnR := Rect(R.Right - BtnW, R.Top, R.Right, R.Bottom);
    // Content honours the resolved Padding (consistent with Button/Edit/Panel);
    // the right edge stops at the chevron button zone.
    TextR := Rect(R.Left + P.Scale(S.Padding.Left), R.Top + P.Scale(S.Padding.Top),
      R.Right - BtnW, R.Bottom - P.Scale(S.Padding.Bottom));
    if FText <> '' then
      P.DrawText(TextR, FText, S.FontName, S.FontSize, S.FontWeight,
        S.TextColor, taLeftJustify, tlCenter, True);
    P.DrawGlyph(BtnR, tgChevronDown, S.TextColor, 2);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyComboBox.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
