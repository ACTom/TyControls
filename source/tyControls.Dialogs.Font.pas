unit tyControls.Dialogs.Font;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Controls, Forms,
  tyControls.Dialogs, tyControls.ListBox, tyControls.FontListBox, tyControls.SpinEdit,
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
    FList: TTyFontListBox; FSize: TTySpinEdit;   // WYSIWYG: each family in its own typeface
    FBold, FItalic, FUnderline, FStrike: TTyCheckBox;
    FColorBtn: TTyButton; FColorValue: TColor;
    FPreviewRect: TRect;
    FSeedDisplay: Integer;   // display value shown in the spin at seed time
    FSeedSize: Integer;      // caller's original Size (may be <= 0 for "default")
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
    FOnShow: TNotifyEvent;
    FOnClose: TCloseEvent;
    FOnCanClose: TCloseQueryEvent;
    procedure SetFont(AValue: TFont);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Execute: Boolean;
  published
    property Caption: string read FCaption write FCaption;
    property Font: TFont read FFont write SetFont;
    property OnShow: TNotifyEvent read FOnShow write FOnShow;
    property OnClose: TCloseEvent read FOnClose write FOnClose;
    property OnCanClose: TCloseQueryEvent read FOnCanClose write FOnCanClose;
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

const
  // Shared layout metrics — used by both CreateNew (initial geometry) and
  // LayoutContent (resize re-flow) so the two never drift apart.
  cListW      = 200;   // family list width (left column)
  cColGap     = 20;    // gap between the list column and the right column
  cColW       = 210;   // right column width (checks + color button)
  cLabelH     = 20;    // caption-label height
  cLabelGap   = 4;     // gap under a label before its control
  cCheckH     = 24;    // style-checkbox height
  cCheckStep  = 28;    // vertical stride between style checkboxes
  cSizeLblW   = 44;    // "Size" label width
  cSizeSpinW  = 74;    // size spin-edit width
  cBtnH       = 30;    // color-button height
  cSectionGap = 16;    // gap between logical groups in the right column
  cPreviewH   = 52;    // preview strip height
  cListMinH   = 180;   // minimum family-list height

constructor TTyFontForm.CreateNew(AOwner: TComponent; Num: Integer);
var
  r: TRect;
  x0, y0, colX, y, contentW, contentH: Integer;

  function MkLabel(const ACaption: string; ALeft, ATop, AWidth: Integer): TTyLabel;
  begin
    Result := TTyLabel.Create(Self);
    Result.Parent := Self;
    Result.Caption := ACaption;
    Result.SetBounds(ALeft, ATop, AWidth, cLabelH);
  end;

  function MkCheck(const ACaption: string; ALeft, ATop: Integer): TTyCheckBox;
  begin
    Result := TTyCheckBox.Create(Self);
    Result.Parent := Self;
    Result.Caption := ACaption;
    Result.SetBounds(ALeft, ATop, cColW, cCheckH);
  end;

begin
  inherited CreateNew(AOwner, Num);
  Resizable := True;
  Constraints.MinWidth := 460;
  Constraints.MinHeight := 360;
  FColorValue := clWindowText;

  r := ContentRect;
  x0 := r.Left + TyDlgPad;
  y0 := r.Top + TyDlgPad;
  colX := x0 + cListW + cColGap;

  // Left column: family label + list. Height is finalized in LayoutContent so it
  // stretches to just above the preview strip; seed a reasonable initial height.
  MkLabel(rsDlgFontFamily, x0, y0, cListW);
  FList := TTyFontListBox.Create(Self);
  FList.Parent := Self;
  FList.SetBounds(x0, y0 + cLabelH + cLabelGap, cListW, cListMinH);

  // Right column, top group: "Size" label + spin on one baseline-aligned row.
  y := y0;
  MkLabel(rsDlgFontSize, colX, y + ((TyDlgEditH - cLabelH) div 2), cSizeLblW);
  FSize := TTySpinEdit.Create(Self);
  FSize.Parent := Self;
  FSize.MinValue := 1;
  FSize.MaxValue := 999;
  FSize.SetBounds(colX + cSizeLblW + 8, y, cSizeSpinW, TyDlgEditH);

  // Right column, style group: four checks with an even vertical rhythm.
  Inc(y, TyDlgEditH + cSectionGap);
  FBold := MkCheck(rsDlgFontBold, colX, y);
  Inc(y, cCheckStep);
  FItalic := MkCheck(rsDlgFontItalic, colX, y);
  Inc(y, cCheckStep);
  FUnderline := MkCheck(rsDlgFontUnderline, colX, y);
  Inc(y, cCheckStep);
  FStrike := MkCheck(rsDlgFontStrike, colX, y);

  // Right column, color group.
  Inc(y, cCheckH + cSectionGap);
  FColorBtn := TTyButton.Create(Self);
  FColorBtn.Parent := Self;
  FColorBtn.Caption := rsDlgFontColor;
  FColorBtn.SetBounds(colX, y, cColW, cBtnH);
  FColorBtn.OnClick := @ColorBtnClick;

  // Preview strip spans the full content width along the bottom (finalized by
  // LayoutContent); seed it here so AutoSizeToContent can size the form.
  FPreviewRect := Rect(x0, y0 + cLabelH + cLabelGap + cListMinH + cSectionGap,
    r.Right - TyDlgPad,
    y0 + cLabelH + cLabelGap + cListMinH + cSectionGap + cPreviewH);

  AddButton(rsMsgBtnOK, mrOK, True, False);
  AddButton(rsMsgBtnCancel, mrCancel, False, True);

  // Content extents: left list column + gap + right column vs. the preview strip
  // running the full width; whichever is taller/wider drives the form size.
  contentW := cListW + cColGap + cColW;
  contentH := (FPreviewRect.Bottom - y0) + TyDlgPad;
  AutoSizeToContent(contentW, contentH);
  LayoutContent;
end;

procedure TTyFontForm.SeedFrom(AFont: TFont; AFamilies: TStrings);
var ch: TTyFontChecks;
begin
  if AFamilies <> nil then FList.Items.Assign(AFamilies);
  FList.ItemIndex := FList.Items.IndexOf(AFont.Name);
  if AFont.Size >= 1 then FSize.Value := Min(999, AFont.Size)
  else FSize.Value := 9;          // display a sane default for a "use default" (Size<=0) font
  FSeedDisplay := FSize.Value;     // what the user sees
  FSeedSize := AFont.Size;         // the caller's original (may be <= 0)
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
  if FSize.Value = FSeedDisplay then AFont.Size := FSeedSize  // untouched → restore original (0 stays 0)
  else AFont.Size := FSize.Value;                             // user changed the size → apply it
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
var r: TRect; listTop: Integer;
begin
  if FList = nil then Exit;
  r := ContentRect;
  // Anchor the preview strip to the bottom of the content area and stretch the
  // family list down to sit just above it, keeping a clear separating gap.
  FPreviewRect := Rect(r.Left + TyDlgPad, r.Bottom - TyDlgPad - cPreviewH,
    r.Right - TyDlgPad, r.Bottom - TyDlgPad);
  listTop := r.Top + TyDlgPad + cLabelH + cLabelGap;
  FList.SetBounds(r.Left + TyDlgPad, listTop,
    cListW, Max(cListMinH, FPreviewRect.Top - listTop - cSectionGap));
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
  // A TTyDialog derives its title-bar text from the form Caption; fall back to the
  // localized dialog title when the caller passes no caption so the bar isn't blank.
  if ACaption <> '' then Result.Caption := ACaption
  else Result.Caption := rsDlgFontTitle;
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
var d: TTyFontForm;
begin
  // Inline the build/show (rather than call TyFontDialog) so the wrapper's
  // OnShow/OnClose/OnCanClose forward onto the form before ShowModal, and so the
  // component's Caption is honoured.
  d := TyBuildFontDialog(FCaption, FFont, Screen.Fonts);
  try
    TyForwardDialogEvents(d, FOnShow, FOnClose, FOnCanClose);
    Result := (d.ShowModal = mrOK);
    if Result then d.WriteTo(FFont);
  finally d.Free; end;
end;

end.
