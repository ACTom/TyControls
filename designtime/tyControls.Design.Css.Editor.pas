unit tyControls.Design.Css.Editor;
{$mode objfpc}{$H+}

{ Design-time StyleOverride editor: a SynEdit dialog with catalog-driven completion and a
  categorised reference list, so a tycss override is written with help instead of blind into a
  bare string box. Design-time ONLY -- the runtime library never sees SynEdit.

  Two levels, one editor: a CONTROL's StyleOverride is a bare declaration block (no selectors);
  the CONTROLLER's is full tycss WITH selectors. ASelectorMode / FSelectorMode carries which. }

interface

uses
  Classes, SysUtils, PropEdits;

type
  { paDialog editor for a StyleOverride string. '...' opens the tycss dialog. Registered for the
    control bases (no selectors) and TTyStyleController (selectors). }
  TTyStyleOverrideProperty = class(TStringPropertyEditor)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure Edit; override;
  end;

implementation

uses
  Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Graphics, Dialogs, TypInfo,
  SynEdit,
  tyControls.Types, tyControls.Base, tyControls.StyleModel,
  tyControls.Css.Values, tyControls.Css.Parser, tyControls.Css.Catalog,
  tyControls.Css.Complete, tyControls.Controller, tyControls.Dialogs,
  tyControls.Design.CssEditKit;

resourcestring
  rsCssEdTitle        = 'StyleOverride (tycss)';
  rsCssEdValidate     = 'Validate';
  rsCssEdFormat       = 'Format';
  rsCssEdCatProps     = 'Properties';
  rsCssEdCatFuncs     = 'Colour functions';
  rsCssEdCatTypeKeys  = 'Type keys';
  rsCssEdCatPseudo    = 'Pseudo-states';
  rsCssEdCatTokens    = 'Tokens';
  rsCssEdUnknownProps = 'Unknown properties (silently ignored at run time):';
  rsCssEdValid        = 'tycss is valid.';

{ ---- the dialog ----------------------------------------------------------- }

type
  TTyStyleOverrideDialog = class(TForm)
  private
    FEdit: TSynEdit;
    FKit: TTyCssEditKit;               // highlighter, completion, format-on-line-leave
    FList: TTreeView;
    FWarn: TLabel;
    FSelectorMode: Boolean;
    FController: TTyCustomStyleController;   // source of the theme's CURRENT value for an inserted prop
    FTypeKey: string;                 // the target control's typeKey ('' = controller level)
    procedure BuildRefList;
    procedure ListDblClick(Sender: TObject);
    procedure EditChange(Sender: TObject);
    procedure ValidateClick(Sender: TObject);
    procedure FormatClick(Sender: TObject);
    function DefaultValueFor(const AProp: string): string;
  public
    constructor CreateFor(AController: TTyCustomStyleController; const ATypeKey: string;
      ASelectorMode: Boolean); reintroduce;
    function Execute(var AText: string): Boolean;
  end;

constructor TTyStyleOverrideDialog.CreateFor(AController: TTyCustomStyleController;
  const ATypeKey: string; ASelectorMode: Boolean);
var
  panel: TPanel;
  ok, cancel, validate, format_: TButton;
begin
  inherited CreateNew(nil);
  FSelectorMode := ASelectorMode;
  FController := AController;
  FTypeKey := ATypeKey;
  Caption := rsCssEdTitle;
  Width := 720; Height := 460;
  Position := poScreenCenter;
  BorderStyle := bsSizeable;

  FList := TTreeView.Create(Self);
  FList.Parent := Self;
  FList.Align := alRight;
  FList.Width := 220;
  FList.ReadOnly := True;
  FList.OnDblClick := @ListDblClick;

  FWarn := TLabel.Create(Self);
  FWarn.Parent := Self;
  FWarn.Align := alBottom;
  FWarn.WordWrap := True;
  FWarn.Font.Color := clRed;
  FWarn.BorderSpacing.Around := 6;

  panel := TPanel.Create(Self);
  panel.Parent := Self;
  panel.Align := alBottom;
  panel.Height := 40;
  panel.BevelOuter := bvNone;

  validate := TButton.Create(Self);
  validate.Parent := panel; validate.Caption := rsCssEdValidate; validate.OnClick := @ValidateClick;
  validate.Width := 90; validate.Top := 6; validate.Left := 6;
  format_ := TButton.Create(Self);
  format_.Parent := panel; format_.Caption := rsCssEdFormat; format_.OnClick := @FormatClick;
  format_.Width := 90; format_.Top := 6; format_.Left := 102;

  ok := TButton.Create(Self);
  ok.Parent := panel; ok.Caption := 'OK'; ok.ModalResult := mrOK;
  ok.Width := 90; ok.Top := 6; ok.Left := panel.Width - 200; ok.Anchors := [akTop, akRight];
  cancel := TButton.Create(Self);
  cancel.Parent := panel; cancel.Caption := 'Cancel'; cancel.ModalResult := mrCancel;
  cancel.Width := 90; cancel.Top := 6; cancel.Left := panel.Width - 100; cancel.Anchors := [akTop, akRight];

  FEdit := TSynEdit.Create(Self);
  FEdit.Parent := Self;
  FEdit.Align := alClient;
  FEdit.Gutter.Visible := True;
  FEdit.OnChange := @EditChange;
  { The shared tycss setup (also the theme builder's): the CSS highlighter, catalog completion
    (Ctrl+Space and as an identifier is typed), the caret kept on real text, and the line the
    caret leaves tidied. It chains to the OnChange above. }
  FKit := TTyCssEditKit.Create(Self);
  FKit.Attach(FEdit, ASelectorMode);

  BuildRefList;
end;

procedure TTyStyleOverrideDialog.BuildRefList;
  function Cat(const ATitle: string; const AItems: array of string): TTreeNode;
  var s: string;
  begin
    Result := FList.Items.Add(nil, ATitle);
    for s in AItems do FList.Items.AddChild(Result, s);
  end;
var
  keysNode: TTreeNode;
  keys: TStringList;
  i: Integer;
begin
  FList.Items.BeginUpdate;
  try
    Cat(rsCssEdCatProps, TyKnownStyleProps);
    Cat(rsCssEdCatFuncs, TyKnownColorFns);
    if FSelectorMode then
    begin
      { #14: the catalogue's keys plus the ones a third-party package registered into a type
        key chain -- the very list the completion offers (TyCssSelectorTypeKeys). }
      keysNode := Cat(rsCssEdCatTypeKeys, []);
      keys := TStringList.Create;
      try
        TyCssSelectorTypeKeys(keys);
        for i := 0 to keys.Count - 1 do
          FList.Items.AddChild(keysNode, keys[i]);
      finally
        keys.Free;
      end;
      Cat(rsCssEdCatPseudo, TyKnownPseudoStates);
    end;
    Cat(rsCssEdCatTokens, TyCatalogTokens);
  finally
    FList.Items.EndUpdate;
  end;
end;

function TTyStyleOverrideDialog.DefaultValueFor(const AProp: string): string;
begin
  { The theme's CURRENT value for this property on the target control -- ResolveStyle's base layer
    IS the default theme, so "theme, then default theme" is already resolved. '' when the theme
    defines nothing usable there, or at controller level (no single typeKey). }
  Result := '';
  if (FController <> nil) and (FTypeKey <> '') then
    try
      Result := TyCssPropertyDefault(AProp, FController.Model.ResolveStyle(FTypeKey, '', []));
    except
      Result := '';   { a control that dislikes being resolved at design time falls back to a hint }
    end;
end;

procedure TTyStyleOverrideDialog.ListDblClick(Sender: TObject);
var
  s, ins, dv: string;
  i: Integer;
  isProp: Boolean;
begin
  if (FList.Selected = nil) or (FList.Selected.Parent = nil) then Exit;
  s := FList.Selected.Text;
  { A property inserts as a whole declaration; anything else (function, typeKey, token) as its
    bare text. The declaration is seeded with the theme's ACTUAL value if we can resolve one,
    otherwise the property's first value hint. }
  isProp := False;
  for i := 0 to High(TyKnownStyleProps) do
    if TyKnownStyleProps[i] = s then begin isProp := True; Break; end;
  if isProp then
  begin
    dv := DefaultValueFor(s);
    if dv <> '' then ins := s + ': ' + dv + ';'
    else ins := TyCssPropertyTemplate(s);
  end
  else
    ins := s;
  { On a NEW line below the caret, not mid-line: go to the current line's end, then break. }
  if (FEdit.CaretY >= 1) and (FEdit.CaretY <= FEdit.Lines.Count) then
    FEdit.CaretX := Length(FEdit.Lines[FEdit.CaretY - 1]) + 1;
  FEdit.InsertTextAtCaret(LineEnding + ins);
  FEdit.SetFocus;
end;

procedure TTyStyleOverrideDialog.ValidateClick(Sender: TObject);
var err: string;
begin
  err := TyCssValidate(FEdit.Text, FSelectorMode);
  if err = '' then
    TyMessageDlg(rsCssEdValid, mtInformation, [mbOK], 0)
  else
    TyMessageDlg(err, mtError, [mbOK], 0);
end;

procedure TTyStyleOverrideDialog.FormatClick(Sender: TObject);
begin
  FEdit.Text := TyCssFormat(FEdit.Text);
end;

procedure TTyStyleOverrideDialog.EditChange(Sender: TObject);
var
  u: string;
begin
  { the completion popping as an identifier is typed is the kit's; it calls this after }
  u := TyCssUnknownProps(FEdit.Text);
  if Trim(u) <> '' then
    FWarn.Caption := rsCssEdUnknownProps + LineEnding + u
  else
    FWarn.Caption := '';
end;

function TTyStyleOverrideDialog.Execute(var AText: string): Boolean;
begin
  FEdit.Text := AText;
  EditChange(nil);
  Result := ShowModal = mrOK;
  if Result then AText := FEdit.Text;
end;

{ ---- property editor ------------------------------------------------------ }

function TTyStyleOverrideProperty.GetAttributes: TPropertyAttributes;
begin
  Result := (inherited GetAttributes) + [paDialog, paRevertable];
end;

procedure TTyStyleOverrideProperty.Edit;
var
  dlg: TTyStyleOverrideDialog;
  comp: TPersistent;
  ctrl: TTyCustomStyleController;
  typeKey, s: string;
  selectorMode: Boolean;
  styleable: ITyStyleable;
begin
  comp := GetComponent(0);
  ctrl := nil; typeKey := ''; selectorMode := False;
  if comp is TTyCustomStyleController then   { any controller, a third party's too }
    selectorMode := True   { controller level: full tycss with selectors, no single typeKey }
  else if Supports(comp, ITyStyleable, styleable) then
  begin
    typeKey := styleable.GetStyleTypeKey;
    { the control's own controller (published), or the process-wide default -- either way a model
      whose base layer is the default theme, so DefaultValueFor resolves "theme, then default". }
    if comp is TTyGraphicControl then ctrl := TTyGraphicControl(comp).Controller
    else if comp is TTyCustomControl then ctrl := TTyCustomControl(comp).Controller;
    if ctrl = nil then ctrl := TyDefaultController;
  end;
  dlg := TTyStyleOverrideDialog.CreateFor(ctrl, typeKey, selectorMode);
  try
    s := GetStrValue;
    if dlg.Execute(s) then SetStrValue(s);
  finally
    dlg.Free;
  end;
end;

end.
