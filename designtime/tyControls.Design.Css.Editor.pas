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
  Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Graphics, Dialogs,
  SynEdit, SynEditTypes, SynCompletion, SynHighlighterCss,
  tyControls.StyleModel, tyControls.Css.Values, tyControls.Css.Parser, tyControls.Css.Catalog,
  tyControls.Css.Complete, tyControls.Controller, tyControls.Dialogs;

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
    FComplete: TSynCompletion;
    FList: TTreeView;
    FWarn: TLabel;
    FSelectorMode: Boolean;
    procedure BuildRefList;
    procedure ListDblClick(Sender: TObject);
    procedure EditChange(Sender: TObject);
    procedure CompletionExecute(Sender: TObject);
    procedure ValidateClick(Sender: TObject);
    procedure FormatClick(Sender: TObject);
  public
    constructor CreateFor(ASelectorMode: Boolean); reintroduce;
    function Execute(var AText: string): Boolean;
  end;

constructor TTyStyleOverrideDialog.CreateFor(ASelectorMode: Boolean);
var
  panel: TPanel;
  ok, cancel, validate, format_: TButton;
begin
  inherited CreateNew(nil);
  FSelectorMode := ASelectorMode;
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
  { Clamp the caret to real text: clicking past a line's end puts it AT the last character, not in
    virtual space past it (removing eoScrollPastEol). }
  FEdit.Options := FEdit.Options - [eoScrollPastEol];
  { tycss is a CSS dialect, so the stock CSS highlighter colours it well enough -- comments,
    selectors, properties, values, braces, hex. The tycss-only bits (--tokens, darken()) fall
    back to CSS's generic identifier/function colouring, which is fine. No custom highlighter
    to write or keep in step with the grammar. }
  FEdit.Highlighter := TSynCssSyn.Create(Self);

  FComplete := TSynCompletion.Create(Self);
  FComplete.Editor := FEdit;
  FComplete.OnExecute := @CompletionExecute;
  FComplete.ShortCut := 16416;   { Ctrl+Space }

  BuildRefList;
end;

procedure TTyStyleOverrideDialog.BuildRefList;
  procedure Cat(const ATitle: string; const AItems: array of string);
  var node: TTreeNode; s: string;
  begin
    node := FList.Items.Add(nil, ATitle);
    for s in AItems do FList.Items.AddChild(node, s);
  end;
begin
  FList.Items.BeginUpdate;
  try
    Cat(rsCssEdCatProps, TyKnownStyleProps);
    Cat(rsCssEdCatFuncs, TyKnownColorFns);
    if FSelectorMode then
    begin
      Cat(rsCssEdCatTypeKeys, TyCatalogTypeKeys);
      Cat(rsCssEdCatPseudo, TyKnownPseudoStates);
    end;
    Cat(rsCssEdCatTokens, TyCatalogTokens);
  finally
    FList.Items.EndUpdate;
  end;
end;

procedure TTyStyleOverrideDialog.ListDblClick(Sender: TObject);
var
  s, ins: string;
  i: Integer;
  isProp: Boolean;
begin
  if (FList.Selected = nil) or (FList.Selected.Parent = nil) then Exit;
  s := FList.Selected.Text;
  { A property inserts as a whole declaration with a default value; anything else (a function,
    typeKey or token) inserts as its bare text. }
  isProp := False;
  for i := 0 to High(TyKnownStyleProps) do
    if TyKnownStyleProps[i] = s then begin isProp := True; Break; end;
  if isProp then ins := TyCssPropertyTemplate(s) else ins := s;
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
var u: string;
begin
  u := TyCssUnknownProps(FEdit.Text);
  if Trim(u) <> '' then
    FWarn.Caption := rsCssEdUnknownProps + LineEnding + u
  else
    FWarn.Caption := '';
end;

procedure TTyStyleOverrideDialog.CompletionExecute(Sender: TObject);
var
  before: string;
begin
  { Text of the doc up to the caret -- lines before, plus the current line's prefix. }
  before := FEdit.Lines.Text;   { whole doc; good enough for brace-depth + boundary context }
  FComplete.ItemList.Clear;
  TyCssCompletionItems(before, FSelectorMode, FComplete.ItemList);
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
  s: string;
begin
  dlg := TTyStyleOverrideDialog.CreateFor(GetComponent(0) is TTyStyleController);
  try
    s := GetStrValue;
    if dlg.Execute(s) then SetStrValue(s);
  finally
    dlg.Free;
  end;
end;

end.
