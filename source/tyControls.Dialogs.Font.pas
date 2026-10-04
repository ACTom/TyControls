unit tyControls.Dialogs.Font;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Controls, Forms, StdCtrls, Dialogs,
  tyControls.Dialogs, tyControls.ListBox, tyControls.FontListBox, tyControls.SpinEdit,
  tyControls.CheckBox, tyControls.Button, tyControls.TyLabel,
  tyControls.Painter, tyControls.ColorMath,
  tyControls.Dialogs.Color, tyControls.Component, tyControls.StrConsts;
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
    FFamilyLabel: TTyLabel;   // kept so LayoutContent can start the list under its REAL bottom
    FBold, FItalic, FUnderline, FStrike: TTyCheckBox;
    FColorBtn: TTyButton; FColorValue: TColor;
    FPreviewRect: TRect;
    FSeedDisplay: Integer;   // display value shown in the spin at seed time
    FSeedSize: Integer;      // caller's original Size (may be <= 0 for "default")
    FSeedClamped: Boolean;   // fdLimitSize moved the seed display (Configure)
    FSeedName: string;       // caller's family; the preview falls back to it (see PreviewFamily)
    FPreviewChanges: Integer;  // test seam, see PreviewChangeCount
    FSeedStyle: TFontStyles;   // the caller's styles: what a grey (untouched) box stands for
    FOptions: TFontDialogOptions;   // [fdEffects] until Configure says otherwise
    FPreviewText: string;
    FApplyBtn: TTyButton;
    FOnApply: TNotifyEvent;
    procedure ColorBtnClick(Sender: TObject);
    procedure ApplyClick(Sender: TObject);
    procedure PreviewChanged(Sender: TObject);
    { The style a box stands for: its own state, or -- grey, under fdNoStyleSel, never touched --
      the caller's. }
    function EffectiveStyle(ABox: TTyCheckBox; AStyle: TFontStyle): Boolean;
    function PreviewSize: Integer;
  protected
    procedure LayoutContent; override;
    procedure Paint; override;             // preview
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    procedure SeedFrom(AFont: TFont; AFamilies: TStrings);
    { LCL's TFontDialog options, applied after SeedFrom (the no-preselection ones undo what
      SeedFrom selected). AMinSize / AMaxSize count only under fdLimitSize, and only when > 0.
      APreviewText replaces the sample when not empty. Without a call the form behaves as with
      [fdEffects], LCL's default. }
    procedure Configure(AOptions: TFontDialogOptions; AMinSize, AMaxSize: Integer;
      const APreviewText: string);
    { Writes the choice into AFont. Whatever the user could not see or did not touch stays as
      AFont has it: the family when none is selected, the size when the box is blank, a grey
      style box, and -- without fdEffects -- underline, strikeout and colour. Under fdLimitSize
      the size written is always inside the limits. }
    procedure WriteTo(AFont: TFont);
    { The Apply button (fdApplyButton): fires OnApply; the dialog stays open. }
    procedure DoApply;
    property OnApply: TNotifyEvent read FOnApply write FOnApply;
    { The text the preview strip shows: PreviewText, or the built-in sample. }
    function SampleText: string;
    // test seams:
    function SizeValue: Integer;
    function BoldChecked: Boolean; function ItalicChecked: Boolean;
    function UnderlineChecked: Boolean; function StrikeChecked: Boolean;
    function FamilyCount: Integer; function SelectedFamily: string;
    function PreviewFamily: string;
    function PreviewChangeCount: Integer;
  end;

function TyBuildFontDialog(const ACaption: string; AFont: TFont; AFamilies: TStrings): TTyFontForm;
function TyFontDialog(AFont: TFont): Boolean;

type
  TTyFontDialog = class(TTyComponent)
  private
    FFont: TFont; FCaption: TCaption;
    FOnShow: TNotifyEvent;
    FOnClose: TCloseEvent;
    FOnCanClose: TCloseQueryEvent;
    FOptions: TFontDialogOptions;
    FMinFontSize, FMaxFontSize: Integer;
    FPreviewText: string;
    FOnApplyClicked: TNotifyEvent;
    procedure SetFont(AValue: TFont);
    procedure FormApply(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Builds the dialog Execute would show -- families, seed, options, the Apply wiring and the
      three forwarded events -- without showing it. The caller frees it. }
    function BuildForm: TTyFontForm;
    function Execute: Boolean;
    { The Apply button was clicked: Font already holds the current choice. Fires
      OnApplyClicked; LCL's TFontDialog.ApplyClicked. }
    procedure ApplyClicked; virtual;
  published
    { The universal properties the base classes stopped publishing in 4.0 (LCL visibility);
      RTTI order is the 3.0 order. }
    property Version;
    property Caption: TCaption read FCaption write FCaption;
    property Font: TFont read FFont write SetFont;
    property OnShow: TNotifyEvent read FOnShow write FOnShow;
    property OnClose: TCloseEvent read FOnClose write FOnClose;
    property OnCanClose: TCloseQueryEvent read FOnCanClose write FOnCanClose;
    { LCL's TFontDialogOptions. fdEffects (underline, strikeout, colour), fdFixedPitchOnly,
      fdScalableOnly, fdLimitSize, fdNoFaceSel, fdNoSizeSel, fdNoStyleSel and fdApplyButton do
      what they say; the Windows ChooseFont leftovers (fdAnsiOnly, fdTrueTypeOnly, fdNoOEMFonts,
      fdNoSimulations, fdNoVectorFonts, fdWysiwyg, fdShowHelp, fdForceFontExist) are accepted
      and have no effect -- see docs/controls/dialogs.md. }
    property Options: TFontDialogOptions read FOptions write FOptions default [fdEffects];
    { The size range under fdLimitSize; 0 = no limit on that side. }
    property MinFontSize: Integer read FMinFontSize write FMinFontSize default 0;
    property MaxFontSize: Integer read FMaxFontSize write FMaxFontSize default 0;
    { The preview strip's text; empty = the built-in sample. }
    property PreviewText: string read FPreviewText write FPreviewText;
    property OnApplyClicked: TNotifyEvent read FOnApplyClicked write FOnApplyClicked;
  end;

implementation

uses Math, tyControls.FontFamilies;

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
    Result.SetBounds(ALeft, ATop, AWidth, Px(cLabelH));
  end;

  { The y under ALabel -- its real bottom plus the gap, never tighter than the designed
    cLabelH + cLabelGap, so a lean theme keeps the original spacing exactly. }
  function LabelBottom(ALabel: TTyLabel; ATop: Integer): Integer;
  begin
    Result := ATop + Px(cLabelH) + Px(cLabelGap);
    if (ALabel <> nil) and (ALabel.Top + ALabel.Height + Px(cLabelGap) > Result) then
      Result := ALabel.Top + ALabel.Height + Px(cLabelGap);
  end;

  function MkCheck(const ACaption: string; ALeft, ATop: Integer): TTyCheckBox;
  begin
    Result := TTyCheckBox.Create(Self);
    Result.Parent := Self;
    Result.Caption := ACaption;
    Result.SetBounds(ALeft, ATop, Px(cColW), Px(cCheckH));
  end;

  { Where the row after AControl starts: its real bottom, but never tighter than the
    designed stride, so a lean theme keeps the original spacing exactly. }
  function NextRow(AControl: TControl; ACurrentY: Integer): Integer;
  begin
    Result := AControl.Top + AControl.Height + (Px(cCheckStep) - Px(cCheckH));
    if Result < ACurrentY + Px(cCheckStep) then Result := ACurrentY + Px(cCheckStep);
  end;

begin
  inherited CreateNew(AOwner, Num);
  Resizable := True;
  { Every layout number in this form is a 96-PPI design number and goes through Px: see
    TTyDialog.Px. }
  Constraints.MinWidth := Px(460);
  Constraints.MinHeight := Px(360);
  FColorValue := clWindowText;
  FOptions := [fdEffects];   // LCL's default; Configure replaces it

  r := ContentRect;
  x0 := r.Left + Px(TyDlgPad);
  y0 := r.Top + Px(TyDlgPad);
  colX := x0 + Px(cListW) + Px(cColGap);

  // Left column: family label + list. Height is finalized in LayoutContent so it
  // stretches to just above the preview strip; seed a reasonable initial height.
  FFamilyLabel := MkLabel(rsDlgFontFamily, x0, y0, Px(cListW));
  FList := TTyFontListBox.Create(Self);
  FList.Parent := Self;
  { The list starts under the label the same way -- read back, floored at the designed gap. }
  FList.SetBounds(x0, LabelBottom(FFamilyLabel, y0), Px(cListW), Px(cListMinH));

  // Right column, top group: "Size" label + spin on one baseline-aligned row.
  y := y0;
  MkLabel(rsDlgFontSize, colX, y + ((Px(TyDlgEditH) - Px(cLabelH)) div 2), Px(cSizeLblW));
  FSize := TTySpinEdit.Create(Self);
  FSize.Parent := Self;
  FSize.MinValue := 1;
  FSize.MaxValue := 999;
  FSize.SetBounds(colX + Px(cSizeLblW) + Px(8), y, Px(cSizeSpinW), Px(TyDlgEditH));

  // Right column, style group: four checks with an even vertical rhythm.
  Inc(y, Px(TyDlgEditH) + Px(cSectionGap));
  { cCheckStep is a MINIMUM stride, not the stride: TTyCheckBox floors its height on the
    theme's font, padding and --checkbox-size, LCL enforces that floor inside SetBounds, and a
    box taller than 28 would land under the next one. Step by whatever the box actually is. }
  FBold := MkCheck(rsDlgFontBold, colX, y);
  y := NextRow(FBold, y);
  FItalic := MkCheck(rsDlgFontItalic, colX, y);
  y := NextRow(FItalic, y);
  FUnderline := MkCheck(rsDlgFontUnderline, colX, y);
  y := NextRow(FUnderline, y);
  FStrike := MkCheck(rsDlgFontStrike, colX, y);

  // Right column, color group.
  Inc(y, Px(cCheckH) + Px(cSectionGap));
  FColorBtn := TTyButton.Create(Self);
  FColorBtn.Parent := Self;
  FColorBtn.Caption := rsDlgFontColor;
  FColorBtn.SetBounds(colX, y, Px(cColW), Px(cBtnH));
  FColorBtn.OnClick := @ColorBtnClick;

  // Preview strip spans the full content width along the bottom (finalized by
  // LayoutContent); seed it here so AutoSizeToContent can size the form.
  FPreviewRect := Rect(x0, y0 + Px(cLabelH) + Px(cLabelGap) + Px(cListMinH) + Px(cSectionGap),
    r.Right - Px(TyDlgPad),
    y0 + Px(cLabelH) + Px(cLabelGap) + Px(cListMinH) + Px(cSectionGap) + Px(cPreviewH));

  // The sample text is drawn by the FORM's Paint, so a child control invalidating
  // itself repaints none of it — every input that feeds the sample has to ask the
  // form for the repaint. Miss one and that control silently does nothing on screen
  // (the colour button used to be the only one wired, so the preview never changed
  // family, size or style while the user picked them).
  FList.OnChange := @PreviewChanged;
  FSize.OnChange := @PreviewChanged;
  FBold.OnChange := @PreviewChanged;
  FItalic.OnChange := @PreviewChanged;
  FUnderline.OnChange := @PreviewChanged;
  FStrike.OnChange := @PreviewChanged;

  AddButton(rsMsgBtnOK, mrOK, True, False);
  AddButton(rsMsgBtnCancel, mrCancel, False, True);

  // Content extents: left list column + gap + right column vs. the preview strip
  // running the full width; whichever is taller/wider drives the form size.
  contentW := Px(cListW) + Px(cColGap) + Px(cColW);
  contentH := (FPreviewRect.Bottom - y0) + Px(TyDlgPad);
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
  FSeedName := AFont.Name;         // survives a family that isn't installed (list stays unselected)
  FSeedStyle := AFont.Style;
  ch := TyFontStyleToChecks(AFont.Style);
  FBold.Checked := ch.Bold;
  FItalic.Checked := ch.Italic;
  FUnderline.Checked := ch.Underline;
  FStrike.Checked := ch.Strikeout;
  FColorValue := AFont.Color;
  Invalidate;
end;

procedure TTyFontForm.Configure(AOptions: TFontDialogOptions; AMinSize, AMaxSize: Integer;
  const APreviewText: string);
var shown: Integer;
begin
  FOptions := AOptions;
  FPreviewText := APreviewText;
  if fdLimitSize in AOptions then
  begin
    { The spin re-clamps its value on each range write; the clamped value is what the user
      sees, so it is the new "untouched" mark. }
    shown := FSize.Value;
    if AMaxSize > 0 then FSize.MaxValue := AMaxSize;
    if AMinSize > 0 then FSize.MinValue := AMinSize;
    FSeedDisplay := FSize.Value;
    FSeedClamped := FSeedDisplay <> shown;
  end;
  if fdNoFaceSel in AOptions then FList.ItemIndex := -1;
  if fdNoSizeSel in AOptions then FSize.ValueEmpty := True;
  if fdNoStyleSel in AOptions then
  begin
    { ChooseFont's style list is weight + slant; underline and strikeout are effects. }
    FBold.State := cbGrayed;
    FItalic.State := cbGrayed;
  end;
  if not (fdEffects in AOptions) then
  begin
    FUnderline.Visible := False;
    FStrike.Visible := False;
    FColorBtn.Visible := False;
  end;
  if (fdApplyButton in AOptions) and (FApplyBtn = nil) then
  begin
    FApplyBtn := AddButton(rsDlgFontApply, mrNone);   // mrNone: the dialog stays open
    FApplyBtn.OnClick := @ApplyClick;
  end;
  Invalidate;
end;

procedure TTyFontForm.WriteTo(AFont: TFont);
var
  st: TFontStyles;
  restore: Boolean;

  procedure Put(ABox: TTyCheckBox; AStyle: TFontStyle);
  begin
    case ABox.State of
      cbChecked:   Include(st, AStyle);
      cbUnchecked: Exclude(st, AStyle);
    else
      ;   // grey: never touched under fdNoStyleSel -> the caller's bit stays
    end;
  end;

begin
  if SelectedFamily <> '' then AFont.Name := SelectedFamily;
  if not FSize.ValueEmpty then   // blank (fdNoSizeSel, untouched) -> the caller's size stays
  begin
    { Untouched -> the caller's original (0 stays 0) -- unless fdLimitSize clamped it, in
      which case the clamped value is the answer. A "default" size (<= 0) is shown as 9; it
      stays 0 only when the limits left that 9 alone, otherwise the size written would be
      outside them. }
    restore := (FSize.Value = FSeedDisplay)
      and (not (fdLimitSize in FOptions) or ((FSeedSize <= 0) and not FSeedClamped)
           or (FSeedSize = FSeedDisplay));
    if restore then AFont.Size := FSeedSize
    else AFont.Size := FSize.Value;
  end;
  st := AFont.Style;
  Put(FBold, fsBold);
  Put(FItalic, fsItalic);
  if fdEffects in FOptions then
  begin
    Put(FUnderline, fsUnderline);
    Put(FStrike, fsStrikeOut);
  end;
  AFont.Style := st;
  if fdEffects in FOptions then AFont.Color := FColorValue;
end;

procedure TTyFontForm.ApplyClick(Sender: TObject);
begin
  DoApply;
end;

procedure TTyFontForm.DoApply;
begin
  if Assigned(FOnApply) then FOnApply(Self);
end;

function TTyFontForm.SampleText: string;
begin
  if FPreviewText <> '' then Result := FPreviewText
  else Result := rsDlgFontSample;
end;

function TTyFontForm.EffectiveStyle(ABox: TTyCheckBox; AStyle: TFontStyle): Boolean;
begin
  case ABox.State of
    cbChecked: Result := True;
    cbUnchecked: Result := False;
  else
    Result := AStyle in FSeedStyle;
  end;
  { Without fdEffects the boxes are hidden: the caller's underline / strikeout is what
    WriteTo keeps, so it is what the sample shows. }
  if (not (fdEffects in FOptions)) and (AStyle in [fsUnderline, fsStrikeOut]) then
    Result := AStyle in FSeedStyle;
end;

function TTyFontForm.PreviewSize: Integer;
begin
  if FSize.ValueEmpty then Result := FSeedDisplay   // blank box: the caller's size
  else Result := FSize.Value;
end;

procedure TTyFontForm.ColorBtnClick(Sender: TObject);
var a: Byte; c: TColor;
begin
  a := 255; c := FColorValue;
  if TySelectColor(rsDlgFontColor, c, a) then
  begin
    FColorValue := c;
    PreviewChanged(Sender);   // same funnel as every other input
  end;
end;

{ Single repaint funnel for every input the sample text depends on — family, size, the
  four styles, colour. It only has to invalidate: Paint re-reads each control, so there
  is no derived state to keep in step. FPreviewChanges exists because the repaint itself
  is observable only on a GUI, and this wiring is exactly what was missing once already. }
procedure TTyFontForm.PreviewChanged(Sender: TObject);
begin
  Inc(FPreviewChanges);
  Invalidate;
end;

procedure TTyFontForm.LayoutContent;
var r: TRect; listTop: Integer;
begin
  if FList = nil then Exit;
  r := ContentRect;
  // Anchor the preview strip to the bottom of the content area and stretch the
  // family list down to sit just above it, keeping a clear separating gap.
  FPreviewRect := Rect(r.Left + Px(TyDlgPad), r.Bottom - Px(TyDlgPad) - Px(cPreviewH),
    r.Right - Px(TyDlgPad), r.Bottom - Px(TyDlgPad));
  { The runtime relayout has to honour the same read-back rule the constructor does, or it
    quietly puts the literal stride back and drops the list onto its own label. }
  listTop := r.Top + Px(TyDlgPad) + Px(cLabelH) + Px(cLabelGap);
  if (FFamilyLabel <> nil)
     and (FFamilyLabel.Top + FFamilyLabel.Height + Px(cLabelGap) > listTop) then
    listTop := FFamilyLabel.Top + FFamilyLabel.Height + Px(cLabelGap);
  FList.SetBounds(r.Left + Px(TyDlgPad), listTop,
    Px(cListW), Max(Px(cListMinH), FPreviewRect.Top - listTop - Px(cSectionGap)));
end;

procedure TTyFontForm.Paint;
{ Preview strip: TyConfigureTextFont seeds family+size+bold, then the bitmap's
  FontStyle is extended with italic/underline/strikeout (DrawText only honors
  bold, so the sample text is drawn straight onto the BGRA bitmap). The family is
  PreviewFamily — the user's pick — NOT this form's own Font.Name, which would show
  every family as the dialog's own face. GUI-only; guarded crash-safe. }
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
    TyConfigureTextFont(P.Bitmap, PreviewFamily, PreviewSize,
      IfThen(EffectiveStyle(FBold, fsBold), 700, 400), Font.PixelsPerInch);
    extra := [];
    if EffectiveStyle(FItalic, fsItalic) then Include(extra, fsItalic);
    if EffectiveStyle(FUnderline, fsUnderline) then Include(extra, fsUnderline);
    if EffectiveStyle(FStrike, fsStrikeOut) then Include(extra, fsStrikeOut);
    P.Bitmap.FontStyle := P.Bitmap.FontStyle + extra;
    style := Default(TTextStyle);
    style.Alignment := taLeftJustify;
    style.Layout := tlTop;
    style.SingleLine := True;
    style.Clipping := True;
    P.Bitmap.TextRect(FPreviewRect, FPreviewRect.Left + Px(4), FPreviewRect.Top + Px(4),
      SampleText, style, TyColorToBGRA(TyColorFromLCL(FColorValue, 255)));
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

{ The family the sample text is drawn in — deliberately the same answer WriteTo gives,
  so the preview can never advertise a face the dialog won't return. The list selection
  wins; with nothing selected (a seeded family that isn't installed leaves ItemIndex at
  -1) it is the caller's own family, which is precisely what WriteTo then leaves alone.
  The form font is a last resort for a font seeded with no name at all. }
function TTyFontForm.PreviewFamily: string;
begin
  Result := SelectedFamily;
  if Result = '' then Result := FSeedName;
  if Result = '' then Result := Font.Name;
end;

{ How many times a family/size/style change has asked the preview to repaint. }
function TTyFontForm.PreviewChangeCount: Integer;
begin Result := FPreviewChanges; end;

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
var d: TTyFontForm; fams: TStringList;
begin
  fams := TStringList.Create;
  try
    TyGetFontFamilies(fams, False);   // Screen.Fonts without the vertical "@" variants
    d := TyBuildFontDialog('', AFont, fams);
  finally fams.Free; end;
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
  FOptions := [fdEffects];
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

function TTyFontDialog.BuildForm: TTyFontForm;
var fams: TStringList;
begin
  { The families are read on each build, so a font installed since the last one shows up.
    The same list the font combo box shows: Screen.Fonts without the vertical "@" variants,
    filtered further when an option asks. }
  fams := TStringList.Create;
  try
    TyGetFontFamilies(fams, fdFixedPitchOnly in FOptions, fdScalableOnly in FOptions);
    Result := TyBuildFontDialog(FCaption, FFont, fams);
  finally
    fams.Free;
  end;
  Result.Configure(FOptions, FMinFontSize, FMaxFontSize, FPreviewText);
  Result.OnApply := @FormApply;
  // The wrapper's OnShow/OnClose/OnCanClose forward onto the form before it shows.
  TyForwardDialogEvents(Result, FOnShow, FOnClose, FOnCanClose);
end;

function TTyFontDialog.Execute: Boolean;
var d: TTyFontForm;
begin
  d := BuildForm;
  try
    Result := (d.ShowModal = mrOK);
    if Result then d.WriteTo(FFont);
  finally d.Free; end;
end;

procedure TTyFontDialog.FormApply(Sender: TObject);
begin
  (Sender as TTyFontForm).WriteTo(FFont);
  ApplyClicked;
end;

procedure TTyFontDialog.ApplyClicked;
begin
  if Assigned(FOnApplyClicked) then FOnApplyClicked(Self);
end;

end.
