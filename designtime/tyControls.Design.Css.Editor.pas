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
  SynEdit, SynEditTypes, SynCompletion, SynHighlighterCss,
  tyControls.Types, tyControls.Base, tyControls.StyleModel,
  tyControls.Css.Values, tyControls.Css.Parser, tyControls.Css.Catalog,
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
    FController: TTyStyleController;   // source of the theme's CURRENT value for an inserted prop
    FTypeKey: string;                 // the target control's typeKey ('' = controller level)
    FLastLine: Integer;               // for format-on-line-leave
    FFormatting: Boolean;             // reentrancy guard for the in-place line format
    FWantComplete: Boolean;           // an ident key was typed -> pop completion after the insert
    procedure BuildRefList;
    procedure ListDblClick(Sender: TObject);
    procedure EditChange(Sender: TObject);
    procedure EditStatusChange(Sender: TObject; Changes: TSynStatusChanges);
    procedure EditKeyPress(Sender: TObject; var Key: char);
    procedure CompletionExecute(Sender: TObject);
    procedure ValidateClick(Sender: TObject);
    procedure FormatClick(Sender: TObject);
    function DefaultValueFor(const AProp: string): string;
  public
    constructor CreateFor(AController: TTyStyleController; const ATypeKey: string;
      ASelectorMode: Boolean); reintroduce;
    function Execute(var AText: string): Boolean;
  end;

constructor TTyStyleOverrideDialog.CreateFor(AController: TTyStyleController;
  const ATypeKey: string; ASelectorMode: Boolean);
var
  panel: TPanel;
  ok, cancel, validate, format_: TButton;
begin
  inherited CreateNew(nil);
  FSelectorMode := ASelectorMode;
  FController := AController;
  FTypeKey := ATypeKey;
  FLastLine := 1;
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
  FEdit.OnStatusChange := @EditStatusChange;   // format the line the caret just left
  FEdit.OnKeyPress := @EditKeyPress;            // pop completion as an identifier is typed
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
  { Typing any of these closes the popup (finished the token). Esc and selecting are built in. }
  FComplete.EndOfTokenChr := '{}()[]:;,+*/\ ''"=<>!%';

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

procedure TTyStyleOverrideDialog.EditStatusChange(Sender: TObject; Changes: TSynStatusChanges);
var
  formatted: string;
begin
  { Format only the line the caret just LEFT -- replace that one line, never reflow the document
    (which would flicker the whole editor). }
  if FFormatting or not (scCaretY in Changes) then Exit;
  if (FEdit.CaretY <> FLastLine) and (FLastLine >= 1) and (FLastLine <= FEdit.Lines.Count) then
  begin
    formatted := TyCssFormatLine(FEdit.Lines[FLastLine - 1]);
    if formatted <> FEdit.Lines[FLastLine - 1] then
    begin
      FFormatting := True;
      try
        FEdit.Lines[FLastLine - 1] := formatted;
      finally
        FFormatting := False;
      end;
    end;
  end;
  FLastLine := FEdit.CaretY;
end;

procedure TTyStyleOverrideDialog.EditKeyPress(Sender: TObject; var Key: char);
begin
  { An identifier keystroke should pop the completion after it lands (done in EditChange, which
    fires post-insert). A '-' also matters -- it starts a --token. }
  FWantComplete := (Key in ['a'..'z', 'A'..'Z', '-']);
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
  u, before, word: string;
  i: Integer;
  p: TPoint;
begin
  u := TyCssUnknownProps(FEdit.Text);
  if Trim(u) <> '' then
    FWarn.Caption := rsCssEdUnknownProps + LineEnding + u
  else
    FWarn.Caption := '';

  { Auto-pop completion when an identifier was just typed (and it is not our own line-format edit,
    nor already showing). The popup filters itself as typing continues, closes on Esc / a token-end
    char (EndOfTokenChr) / selection. }
  if FWantComplete and not FFormatting and (FComplete <> nil) and not FComplete.IsActive then
  begin
    FWantComplete := False;
    { the identifier run ending at the caret -- the popup opens pre-filtered by it }
    before := Copy(FEdit.LineText, 1, FEdit.CaretX - 1);
    i := Length(before);
    while (i >= 1) and (before[i] in ['a'..'z', 'A'..'Z', '0'..'9', '-', '_']) do Dec(i);
    word := Copy(before, i + 1, MaxInt);
    if word <> '' then
    begin
      { one row below the caret, in screen coords }
      p := FEdit.ClientToScreen(FEdit.RowColumnToPixels(Point(FEdit.CaretX, FEdit.CaretY + 1)));
      FComplete.Execute(word, p.X, p.Y);
    end;
  end;
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
  comp: TPersistent;
  ctrl: TTyStyleController;
  typeKey, s: string;
  selectorMode: Boolean;
  styleable: ITyStyleable;
begin
  comp := GetComponent(0);
  ctrl := nil; typeKey := ''; selectorMode := False;
  if comp is TTyStyleController then
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
