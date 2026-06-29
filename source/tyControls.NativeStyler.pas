unit tyControls.NativeStyler;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, tyControls.Controller;

type
  { Fired for each candidate control before styling. Set AHandled := True to skip it (opt-out) or
    after applying your own custom styling (override). }
  TTyStyleControlEvent = procedure(Sender: TObject; AControl: TControl; var AHandled: Boolean) of object;

  { Non-visual: drop on a form, point Controller at the theme. On theme change it re-styles every
    eligible NON-Ty control under Root, borrowing the closest Ty token (TEdit->TyEdit, ..., else
    TyPanel). RTTI-generic: any control exposing a published Color/Font is themed (third-party
    included); OS-drawn classes in the deny-list keep their font but skip the background. Never
    runs at design time (would bake theme colors into the .lfm). }
  TTyNativeStyler = class(TComponent)
  private
    FController: TTyStyleController;
    FRoot: TWinControl;
    FEnabled: Boolean;
    FApplyFontName: Boolean;
    FApplyFontSize: Boolean;
    FOnStyleControl: TTyStyleControlEvent;
    procedure SetController(AValue: TTyStyleController);
    procedure ControllerChanged(Sender: TObject);
    function EffectiveRoot: TWinControl;
    procedure WalkAndStyle(AParent: TWinControl);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { (Re)style the whole Root subtree now. Idempotent. No-op at design time / disabled / no controller. }
    procedure Apply;
    { Apply the theme to ONE control per the rules (resolve token, RTTI set font/background). Public
      so a host can style a control it just created at runtime, and for testing. }
    procedure StyleControl(AControl: TControl);
    { Add a class whose BACKGROUND must never be set (OS-draws it). Affects all stylers. }
    class procedure RegisterDeny(AClass: TControlClass);
    class function IsDenied(AControl: TControl): Boolean;
  published
    property Controller: TTyStyleController read FController write SetController;
    property Root: TWinControl read FRoot write FRoot;
    property Enabled: Boolean read FEnabled write FEnabled default True;
    property ApplyFontName: Boolean read FApplyFontName write FApplyFontName default False;
    property ApplyFontSize: Boolean read FApplyFontSize write FApplyFontSize default False;
    property OnStyleControl: TTyStyleControlEvent read FOnStyleControl write FOnStyleControl;
  end;

implementation

uses
  Graphics, TypInfo, StdCtrls, ExtCtrls, Buttons,
  tyControls.Types, tyControls.Base, tyControls.StyleModel;

var
  GDeny: array of TControlClass;   // background-deny classes (OS-drawn): set up in initialization

class procedure TTyNativeStyler.RegisterDeny(AClass: TControlClass);
begin
  SetLength(GDeny, Length(GDeny) + 1);
  GDeny[High(GDeny)] := AClass;
end;

class function TTyNativeStyler.IsDenied(AControl: TControl): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(GDeny) do
    if AControl.InheritsFrom(GDeny[i]) then Exit(True);
end;

{ Map a native control to the closest Ty token; unmapped -> 'TyPanel' (a neutral surface present in
  every theme). Memo/combo/listbox are checked before edit in case of shared ancestry; the map is a
  refinement only — an unmatched control still gets TyPanel, so it is always themed. }
function NativeTypeKey(AControl: TControl): string;
begin
  if AControl is TCustomMemo then Result := 'TyMemo'
  else if AControl is TCustomComboBox then Result := 'TyComboBox'
  else if AControl is TCustomListBox then Result := 'TyListBox'
  else if AControl is TCustomEdit then Result := 'TyEdit'
  else if AControl is TRadioButton then Result := 'TyRadioButton'
  else if AControl is TCustomCheckBox then Result := 'TyCheckBox'
  else if AControl is TCustomButton then Result := 'TyButton'      // font only (denied bg)
  else if AControl is TCustomGroupBox then Result := 'TyGroupBox'
  else if (AControl is TCustomLabel) or (AControl is TCustomStaticText) then Result := 'TyLabel'
  else if AControl is TCustomPanel then Result := 'TyPanel'
  else Result := 'TyPanel';
end;

constructor TTyNativeStyler.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEnabled := True;
end;

destructor TTyNativeStyler.Destroy;
begin
  if FController <> nil then FController.RemoveChangeListener(@ControllerChanged);
  inherited Destroy;
end;

procedure TTyNativeStyler.SetController(AValue: TTyStyleController);
begin
  if FController = AValue then Exit;
  if FController <> nil then
  begin
    FController.RemoveChangeListener(@ControllerChanged);
    RemoveFreeNotification(FController);
  end;
  FController := AValue;
  if AValue <> nil then
  begin
    FreeNotification(AValue);
    AValue.AddChangeListener(@ControllerChanged);
  end;
  if not (csLoading in ComponentState) then Apply;
end;

procedure TTyNativeStyler.ControllerChanged(Sender: TObject);
begin
  Apply;
end;

procedure TTyNativeStyler.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) then
  begin
    if AComponent = FController then FController := nil
    else if AComponent = FRoot then FRoot := nil;
  end;
end;

procedure TTyNativeStyler.Loaded;
begin
  inherited Loaded;
  Apply;   // streamed Controller/Root now resolved; style once
end;

function TTyNativeStyler.EffectiveRoot: TWinControl;
begin
  if FRoot <> nil then Result := FRoot
  else if Owner is TWinControl then Result := TWinControl(Owner)
  else Result := nil;
end;

procedure TTyNativeStyler.Apply;
begin
  if (csDesigning in ComponentState) then Exit;   // never bake theme colors into the .lfm
  if (not FEnabled) or (FController = nil) then Exit;
  if EffectiveRoot <> nil then WalkAndStyle(EffectiveRoot);
end;

procedure TTyNativeStyler.WalkAndStyle(AParent: TWinControl);
var
  i: Integer;
  c: TControl;
begin
  for i := 0 to AParent.ControlCount - 1 do
  begin
    c := AParent.Controls[i];
    StyleControl(c);
    if c is TWinControl then WalkAndStyle(TWinControl(c));
  end;
end;

procedure TTyNativeStyler.StyleControl(AControl: TControl);
var
  style, fb: TTyStyleSet;
  fnt: TFont;
  handled: Boolean;
begin
  if AControl = nil then Exit;
  if (AControl is TTyGraphicControl) or (AControl is TTyCustomControl) then Exit;  // self-theming
  if FController = nil then Exit;
  handled := False;
  if Assigned(FOnStyleControl) then FOnStyleControl(Self, AControl, handled);
  if handled then Exit;

  style := FController.Model.ResolveStyle(NativeTypeKey(AControl), '', []);

  // Font (low-risk, broad): text colour always; family/size opt-in.
  if IsPublishedProp(AControl, 'Font') then
  begin
    fnt := TFont(GetObjectProp(AControl, 'Font'));
    if fnt <> nil then
    begin
      if tpTextColor in style.Present then
        fnt.Color := TyColorToLCL(style.TextColor)
      else
      begin
        { Mapped style has no explicit text colour (e.g. anything → TyPanel, which
          only sets a background). Fall back to the theme foreground (TyLabel's
          on-surface) so native text stays readable on dark themes instead of
          keeping its design-time black. }
        fb := FController.Model.ResolveStyle('TyLabel', '', []);
        if tpTextColor in fb.Present then fnt.Color := TyColorToLCL(fb.TextColor);
      end;
      if FApplyFontName and (tpFontName in style.Present) and (style.FontName <> '') then
        fnt.Name := style.FontName;
      if FApplyFontSize and (tpFontSize in style.Present) and (style.FontSize > 0) then
        fnt.Size := style.FontSize;
      if IsPublishedProp(AControl, 'ParentFont') then SetOrdProp(AControl, 'ParentFont', Ord(False));
    end;
  end;

  // Background (risky): only a solid bg, and only if the class is not a known OS-drawn type.
  if IsPublishedProp(AControl, 'Color') and (tpBackground in style.Present)
     and (style.Background.Kind = tfkSolid) and (not IsDenied(AControl)) then
  begin
    SetOrdProp(AControl, 'Color', TyColorToLCL(style.Background.Color));
    if IsPublishedProp(AControl, 'ParentColor') then SetOrdProp(AControl, 'ParentColor', Ord(False));
  end;
end;

initialization
  // OS-drawn controls: setting their background is ineffective/ugly -> deny the bg (font still applies).
  TTyNativeStyler.RegisterDeny(TCustomButton);   // TButton, TBitBtn, ...
  TTyNativeStyler.RegisterDeny(TSpeedButton);
  TTyNativeStyler.RegisterDeny(TCustomCheckBox); // TCheckBox + TRadioButton (TRadioButton descends from it)
end.
