unit tyControls.Dialogs.Font;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Controls, Forms,
  tyControls.Dialogs, tyControls.ListBox, tyControls.SpinEdit,
  tyControls.CheckBox, tyControls.Button, tyControls.TyLabel,
  tyControls.Painter, tyControls.ColorMath,
  tyControls.Dialogs.Color, tyControls.StrConsts;
type
  TTyFontChecks = record Bold, Italic, Underline, Strikeout: Boolean; end;
function TyFontStyleToChecks(AStyle: TFontStyles): TTyFontChecks;
function TyChecksToFontStyle(const AChecks: TTyFontChecks): TFontStyles;

type
  { TTyFontForm — family list + size spin + 4 style checks + a color button
    (reuses the S3 color picker via TySelectColor) + a live preview strip.
    Seed a TFont with SeedFrom; write the chosen values back with WriteTo. }
  TTyFontForm = class(TTyDialog)
  private
    FList: TTyListBox; FSize: TTySpinEdit;
    FBold, FItalic, FUnderline, FStrike: TTyCheckBox;
    FColorBtn: TTyButton; FColorValue: TColor;
    FPreviewRect: TRect;
    procedure ColorBtnClick(Sender: TObject);
  protected
    procedure LayoutContent; override;
    procedure Paint; override;             // preview
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    procedure SeedFrom(AFont: TFont; AFamilies: TStrings);
    procedure WriteTo(AFont: TFont);
    // test seams:
    function SizeValue: Integer;
    function BoldChecked: Boolean; function ItalicChecked: Boolean;
    function UnderlineChecked: Boolean; function StrikeChecked: Boolean;
    function FamilyCount: Integer; function SelectedFamily: string;
  end;

function TyBuildFontDialog(const ACaption: string; AFont: TFont; AFamilies: TStrings): TTyFontForm;
function TyFontDialog(AFont: TFont): Boolean;

type
  TTyFontDialog = class(TComponent)
  private
    FFont: TFont; FCaption: string;
    procedure SetFont(AValue: TFont);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Execute: Boolean;
  published
    property Caption: string read FCaption write FCaption;
    property Font: TFont read FFont write SetFont;
  end;

implementation

uses Math;

function TyFontStyleToChecks(AStyle: TFontStyles): TTyFontChecks;
begin
  Result.Bold := fsBold in AStyle;
  Result.Italic := fsItalic in AStyle;
  Result.Underline := fsUnderline in AStyle;
  Result.Strikeout := fsStrikeOut in AStyle;
end;
function TyChecksToFontStyle(const AChecks: TTyFontChecks): TFontStyles;
begin
  Result := [];
  if AChecks.Bold then Include(Result, fsBold);
  if AChecks.Italic then Include(Result, fsItalic);
  if AChecks.Underline then Include(Result, fsUnderline);
  if AChecks.Strikeout then Include(Result, fsStrikeOut);
end;

{ TTyFontForm }

constructor TTyFontForm.CreateNew(AOwner: TComponent; Num: Integer);
var
  r: TRect;
  x0, y0, listW, listH, colX, rowH, y: Integer;

  function MkLabel(const ACaption: string; ALeft, ATop, AWidth: Integer): TTyLabel;
  begin
    Result := TTyLabel.Create(Self);
    Result.Parent := Self;
    Result.Caption := ACaption;
    Result.SetBounds(ALeft, ATop, AWidth, 20);
  end;

  function MkCheck(const ACaption: string; ALeft, ATop: Integer): TTyCheckBox;
  begin
    Result := TTyCheckBox.Create(Self);
    Result.Parent := Self;
    Result.Caption := ACaption;
    Result.SetBounds(ALeft, ATop, 130, 22);
  end;

begin
  inherited CreateNew(AOwner, Num);
  Resizable := True;
  Constraints.MinWidth := 420;
  Constraints.MinHeight := 320;
  FColorValue := clWindowText;

  r := ContentRect;
  x0 := r.Left + TyDlgPad;
  y0 := r.Top + TyDlgPad;
  listW := 200; listH := 200; rowH := 32;

  // Left: family label + list.
  MkLabel(rsDlgFontFamily, x0, y0, listW);
  FList := TTyListBox.Create(Self);
  FList.Parent := Self;
  FList.SetBounds(x0, y0 + 24, listW, listH);

  // Right column: size spin + style checks + color button.
  colX := x0 + listW + 16;
  y := y0;
  MkLabel(rsDlgFontSize, colX, y, 60);
  FSize := TTySpinEdit.Create(Self);
  FSize.Parent := Self;
  FSize.MinValue := 1;
  FSize.MaxValue := 999;
  FSize.SetBounds(colX + 64, y - 4, 70, TyDlgEditH);

  Inc(y, rowH);
  FBold := MkCheck(rsDlgFontBold, colX, y);
  Inc(y, 26);
  FItalic := MkCheck(rsDlgFontItalic, colX, y);
  Inc(y, 26);
  FUnderline := MkCheck(rsDlgFontUnderline, colX, y);
  Inc(y, 26);
  FStrike := MkCheck(rsDlgFontStrike, colX, y);

  Inc(y, rowH);
  FColorBtn := TTyButton.Create(Self);
  FColorBtn.Parent := Self;
  FColorBtn.Caption := rsDlgFontColor;
  FColorBtn.SetBounds(colX, y, 130, 30);
  FColorBtn.OnClick := @ColorBtnClick;

  // Preview strip along the bottom of the content area.
  FPreviewRect := Rect(x0, y0 + listH + 24 + 12, r.Right - TyDlgPad, y0 + listH + 24 + 12 + 48);

  AddButton(rsMsgBtnOK, mrOK, True, False);
  AddButton(rsMsgBtnCancel, mrCancel, False, True);
  AutoSizeToContent(listW + 16 + 200 + TyDlgPad,
    (y0 + listH + 24 + 12 + 48 + TyDlgPad) - r.Top);
  LayoutContent;
end;

procedure TTyFontForm.SeedFrom(AFont: TFont; AFamilies: TStrings);
var ch: TTyFontChecks;
begin
  if AFamilies <> nil then FList.Items.Assign(AFamilies);
  FList.ItemIndex := FList.Items.IndexOf(AFont.Name);
  FSize.Value := Max(1, Min(999, AFont.Size));
  ch := TyFontStyleToChecks(AFont.Style);
  FBold.Checked := ch.Bold;
  FItalic.Checked := ch.Italic;
  FUnderline.Checked := ch.Underline;
  FStrike.Checked := ch.Strikeout;
  FColorValue := AFont.Color;
  Invalidate;
end;

procedure TTyFontForm.WriteTo(AFont: TFont);
var ch: TTyFontChecks;
begin
  if SelectedFamily <> '' then AFont.Name := SelectedFamily;
  AFont.Size := FSize.Value;
  ch.Bold := FBold.Checked;
  ch.Italic := FItalic.Checked;
  ch.Underline := FUnderline.Checked;
  ch.Strikeout := FStrike.Checked;
  AFont.Style := TyChecksToFontStyle(ch);
  AFont.Color := FColorValue;
end;

procedure TTyFontForm.ColorBtnClick(Sender: TObject);
var a: Byte; c: TColor;
begin
  a := 255; c := FColorValue;
  if TySelectColor(rsDlgFontColor, c, a) then
  begin
    FColorValue := c;
    Invalidate;
  end;
end;

procedure TTyFontForm.LayoutContent;
var r: TRect;
begin
  if FList = nil then Exit;
  r := ContentRect;
  // Stretch the family list down to just above the preview strip; anchor the
  // preview to the bottom of the content area on resize.
  FPreviewRect := Rect(r.Left + TyDlgPad, r.Bottom - TyDlgPad - 48,
    r.Right - TyDlgPad, r.Bottom - TyDlgPad);
  FList.SetBounds(r.Left + TyDlgPad, r.Top + TyDlgPad + 24,
    200, FPreviewRect.Top - (r.Top + TyDlgPad + 24) - 12);
end;

procedure TTyFontForm.Paint;
{ Preview strip: TyConfigureTextFont seeds family+size+bold, then the bitmap's
  FontStyle is extended with italic/underline/strikeout (DrawText only honors
  bold, so the sample text is drawn straight onto the BGRA bitmap). GUI-only;
  guarded crash-safe. }
var
  P: TTyPainter;
  style: TTextStyle;
  extra: TFontStyles;
begin
  inherited Paint;
  if (Canvas = nil) or (not HandleAllocated) then Exit;   // crash-safe: GUI-only
  if FPreviewRect.Right <= FPreviewRect.Left then Exit;
  P := TTyPainter.Create;
  try
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    TyConfigureTextFont(P.Bitmap, Font.Name, FSize.Value,
      IfThen(FBold.Checked, 700, 400), Font.PixelsPerInch);
    extra := [];
    if FItalic.Checked then Include(extra, fsItalic);
    if FUnderline.Checked then Include(extra, fsUnderline);
    if FStrike.Checked then Include(extra, fsStrikeOut);
    P.Bitmap.FontStyle := P.Bitmap.FontStyle + extra;
    style := Default(TTextStyle);
    style.Alignment := taLeftJustify;
    style.Layout := tlTop;
    style.SingleLine := True;
    style.Clipping := True;
    P.Bitmap.TextRect(FPreviewRect, FPreviewRect.Left + 4, FPreviewRect.Top + 4,
      rsDlgFontSample, style, TyColorToBGRA(TyColorFromLCL(FColorValue, 255)));
    P.EndPaint;
  finally P.Free; end;
end;

function TTyFontForm.SizeValue: Integer;
begin Result := FSize.Value; end;

function TTyFontForm.BoldChecked: Boolean;
begin Result := FBold.Checked; end;

function TTyFontForm.ItalicChecked: Boolean;
begin Result := FItalic.Checked; end;

function TTyFontForm.UnderlineChecked: Boolean;
begin Result := FUnderline.Checked; end;

function TTyFontForm.StrikeChecked: Boolean;
begin Result := FStrike.Checked; end;

function TTyFontForm.FamilyCount: Integer;
begin Result := FList.Items.Count; end;

function TTyFontForm.SelectedFamily: string;
begin
  if (FList.ItemIndex >= 0) and (FList.ItemIndex < FList.Items.Count) then
    Result := FList.Items[FList.ItemIndex]
  else
    Result := '';
end;

{ Font-dialog globals }

function TyBuildFontDialog(const ACaption: string; AFont: TFont; AFamilies: TStrings): TTyFontForm;
begin
  Result := TTyFontForm.CreateNew(Application);
  Result.Caption := ACaption;
  Result.SeedFrom(AFont, AFamilies);
end;

function TyFontDialog(AFont: TFont): Boolean;
var d: TTyFontForm;
begin
  d := TyBuildFontDialog('', AFont, Screen.Fonts);
  try
    if d.ShowModal = mrOK then
    begin
      d.WriteTo(AFont);
      Result := True;
    end
    else
      Result := False;
  finally d.Free; end;
end;

{ TTyFontDialog }

constructor TTyFontDialog.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFont := TFont.Create;
end;

destructor TTyFontDialog.Destroy;
begin
  FFont.Free;
  inherited Destroy;
end;

procedure TTyFontDialog.SetFont(AValue: TFont);
begin
  FFont.Assign(AValue);
end;

function TTyFontDialog.Execute: Boolean;
begin
  Result := TyFontDialog(FFont);
end;

end.
