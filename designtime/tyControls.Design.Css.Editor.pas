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
  Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Graphics,
  SynEdit, SynCompletion,
  tyControls.StyleModel, tyControls.Css.Values, tyControls.Css.Parser, tyControls.Css.Catalog,
  tyControls.Css.Complete, tyControls.Controller;

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
  public
    constructor CreateFor(ASelectorMode: Boolean); reintroduce;
    function Execute(var AText: string): Boolean;
  end;

constructor TTyStyleOverrideDialog.CreateFor(ASelectorMode: Boolean);
var
  panel: TPanel;
  ok, cancel: TButton;
begin
  inherited CreateNew(nil);
  FSelectorMode := ASelectorMode;
  Caption := 'StyleOverride (tycss)';
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
    Cat('Properties', TyKnownStyleProps);
    Cat('Colour functions', TyKnownColorFns);
    if FSelectorMode then
    begin
      Cat('Type keys', TyCatalogTypeKeys);
      Cat('Pseudo-states', TyKnownPseudoStates);
    end;
    Cat('Tokens', TyCatalogTokens);
  finally
    FList.Items.EndUpdate;
  end;
end;

procedure TTyStyleOverrideDialog.ListDblClick(Sender: TObject);
begin
  if (FList.Selected <> nil) and (FList.Selected.Parent <> nil) then
    FEdit.InsertTextAtCaret(FList.Selected.Text);
end;

procedure TTyStyleOverrideDialog.EditChange(Sender: TObject);
var u: string;
begin
  u := TyCssUnknownProps(FEdit.Text);
  if Trim(u) <> '' then
    FWarn.Caption := 'Unknown properties (silently ignored at run time):' + LineEnding + u
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
