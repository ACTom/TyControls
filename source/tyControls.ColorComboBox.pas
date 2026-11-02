unit tyControls.ColorComboBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.ListBox, tyControls.ComboBox, tyControls.ColorBox, tyControls.Dialogs.Color, LCLType;

const
  { The "more…" row's value in Objects[], here and in the value list editor's colour
    drop-down: no colour LCL defines (those are $00BBGGRR, the system colours from $80000000,
    clNone $1FFFFFFF and clDefault $20000000), so a palette's own clNone row (cbIncludeNone)
    is never taken for it (#121). }
  TyColorMoreMarker = TColor($7FFFFFFF);

type
  { The drop-down list for TTyColorComboBox: TTyColorPopupList -- so the swatches take the
    combo's ColorRectWidth / ColorRectOffset and pseudo-row colours (#121) -- but the "more…"
    row is drawn as plain text instead of a swatch. }
  TTyColorMorePopupList = class(TTyColorPopupList)
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
  end;

  { TTyColorBox + a trailing "more…" row that opens the themed colour dialog; the picked
    colour is inserted before "more" and selected. The "more…" item is marked by a colour
    value of its own in Objects[] (TyColorMoreMarker), so it renders as plain text and is
    detected without a side flag -- not by clNone, which is a colour the palette may carry
    (cbIncludeNone, #121). Kept last, so appended custom colours slot in above it. }
  TTyColorComboBox = class(TTyColorBox)
  private
    FMoreCaption: string;
    procedure SetMoreCaption(const AValue: TTranslateString);
    function IsMoreIndex(AIndex: Integer): Boolean;
    procedure RebuildMoreItem;
    procedure MorePicked(Data: PtrInt);
  protected
    function CreatePopupList: TTyListBox; override;
    procedure PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet); override;
    { #163: "more…" is a command, not a value. Picking it asks for a colour, and the selection
      changes once, to that colour, or not at all on Cancel -- it changed to the row's marker
      first, with an OnChange, and back or on with another. The closed field's keys step over
      it: an arrow key does not open a dialog. }
    procedure DoPopupPick(AIndex: Integer); override;
    procedure FieldKeySelect(AIndex: Integer); override;
    { The colour "more…" asks for, starting at AColor: the themed colour dialog. Virtual, so a
      host can put its own picker there. False = cancelled. }
    function AskMoreColor(var AColor: TColor): Boolean; virtual;
    { Every rebuild of the palette -- a form file's Loaded, a Style change -- ends with the
      "more…" row, not just the constructor's (#121). }
    procedure SetColorList; override;
  public
    constructor Create(AOwner: TComponent); override;
    { The "more" row's text: MoreCaption, or the translated default when it is empty. }
    function MoreText: string;
  published
    { '' (the default) = the library's translated "More…" (rsColorComboMore). }
    property MoreCaption: TTranslateString read FMoreCaption write SetMoreCaption;
  end;

implementation

uses tyControls.StrConsts;

{ TTyColorMorePopupList }

procedure TTyColorMorePopupList.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
begin
  if TyColorOfItem(Items, AIndex) <> TyColorMoreMarker then
  begin
    inherited PaintItemContent(P, ARowRect, AIndex, AStyle);   // a colour: the swatch row
    Exit;
  end;
  { The "more…" row: plain text, no swatch. Owner-draw first, as the swatch row does. }
  if TyComboCollectRowOwnerDraw(Self, ARowRect, AIndex) then Exit;
  P.DrawText(
    Rect(ARowRect.Left + P.Scale(AStyle.Padding.Left), ARowRect.Top,
         ARowRect.Right - P.Scale(AStyle.Padding.Right), ARowRect.Bottom),
    Items[AIndex], AStyle.FontName, ResolveFontSize(AStyle), AStyle.FontWeight,
    AStyle.TextColor, taLeftJustify, tlCenter, True);
end;

{ TTyColorComboBox }

constructor TTyColorComboBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);        // fills the 16-colour palette + selects index 0
  { Empty, not 'More…': a literal here was English in every language. MoreText supplies
    the translated default. }
  FMoreCaption := '';
end;

procedure TTyColorComboBox.SetColorList;
begin
  inherited SetColorList;
  RebuildMoreItem;
end;

procedure TTyColorComboBox.RebuildMoreItem;
var i: Integer;
begin
  // Drop any existing "more…" row, then append a fresh one at the end.
  for i := Items.Count - 1 downto 0 do
    if TyColorOfItem(Items, i) = TyColorMoreMarker then Items.Delete(i);
  TyAddColorItem(Items, MoreText, TyColorMoreMarker);
end;

procedure TTyColorComboBox.SetMoreCaption(const AValue: TTranslateString);
begin
  if FMoreCaption = AValue then Exit;
  FMoreCaption := AValue;
  RebuildMoreItem;
end;

function TTyColorComboBox.MoreText: string;
begin
  if FMoreCaption <> '' then
    Result := FMoreCaption
  else
    Result := rsColorComboMore;
end;

function TTyColorComboBox.IsMoreIndex(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < Items.Count) and (ColorAt(AIndex) = TyColorMoreMarker);
end;

function TTyColorComboBox.CreatePopupList: TTyListBox;
begin
  Result := TTyColorMorePopupList.Create(Self);
end;

procedure TTyColorComboBox.PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet);
begin
  { A colour row is TTyColorBox's swatch, with its ColorRectWidth / ColorRectOffset and
    pseudo-row colours (#121); "more…", picked for the moment its dialog is open, is text. }
  if IsMoreIndex(ItemIndex) then
    P.DrawText(ATextRect, Items[ItemIndex], AStyle.FontName, ResolveFontSize(AStyle),
      AStyle.FontWeight, AStyle.TextColor, taLeftJustify, tlCenter, True)
  else
    inherited PaintFieldContent(P, ATextRect, AStyle);
end;

procedure TTyColorComboBox.DoPopupPick(AIndex: Integer);
begin
  if not IsMoreIndex(AIndex) then
  begin
    inherited DoPopupPick(AIndex);
    Exit;
  end;
  { After the list's own click: the dialog is modal, and the list closes first -- closing it
    from inside that click is the trap TTyComboBox.DoPopupPick defers around. }
  Application.QueueAsyncCall(@MorePicked, 0);
end;

procedure TTyColorComboBox.FieldKeySelect(AIndex: Integer);
begin
  if IsMoreIndex(AIndex) then Exit;
  inherited FieldKeySelect(AIndex);
end;

function TTyColorComboBox.AskMoreColor(var AColor: TColor): Boolean;
var a: Byte;
begin
  a := 255;
  Result := TySelectColor(MoreText, AColor, a);
end;

procedure TTyColorComboBox.MorePicked(Data: PtrInt);
var
  c: TColor;
  i, moreIdx: Integer;
begin
  CloseUp;
  moreIdx := -1;
  for i := Items.Count - 1 downto 0 do
    if IsMoreIndex(i) then
    begin
      moreIdx := i;
      Break;
    end;
  if moreIdx < 0 then Exit;
  if IsMoreIndex(ItemIndex) then c := clNone else c := ColorAt(ItemIndex);
  if c = clNone then c := clBlack;
  if not AskMoreColor(c) then Exit;   // cancelled: nothing was picked, nothing changes
  // The picked colour goes in just above "more…", and is the user's pick: OnChange and
  // OnSelect, once.
  Items.InsertObject(moreIdx, Format('#%.2x%.2x%.2x',
    [Red(ColorToRGB(c)), Green(ColorToRGB(c)), Blue(ColorToRGB(c))]), TObject(PtrInt(c)));
  inherited FieldKeySelect(moreIdx);
end;

end.
