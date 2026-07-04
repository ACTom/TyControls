unit tyControls.Dialogs.About;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Controls, Forms, LCLIntf,
  tyControls.Types, tyControls.Base, tyControls.Painter, tyControls.Controller,
  tyControls.StyleModel, tyControls.Dialogs, tyControls.StrConsts;

type
  { About dialog form: an accent header band (app name + version, themed by reusing the
    primary-button style so the band tracks the theme's accent + on-accent text) over a body
    of OPTIONAL info rows — description (one row per line), copyright, license — and a clickable
    homepage link. Every empty field is simply omitted, so the dialog shrinks to exactly what it
    carries. Everything is drawn in Paint (TTyLabel is fully theme-driven and would ignore the
    per-row size/weight/colour this dialog needs); the homepage link is hit-tested in MouseDown. }
  TTyAboutForm = class(TTyDialog)
  private
    FAppName, FVersion, FDescription, FCopyright, FLicense, FHomepage: string;
    FRows: array of record Text: string; Size, Weight: Integer; Link: Boolean; end;
    FLinkRect: TRect;   // homepage hit-box, refreshed each Paint (empty when no homepage)
    procedure AddRow(const AText: string; ASize, AWeight: Integer; ALink: Boolean);
    procedure DoLayout;                       // (re)build FRows for the current fields + size the form
    function  BandHeight: Integer;
    function  EffectiveController: TTyStyleController;   // Controller, else the global default (nil-safe)
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    procedure SetInfo(const AAppName, AVersion, ADescription, ACopyright, ALicense, AHomepage: string);
    // Test/introspection seam: how many body rows the current fields produced (empty
    // fields contribute none — the "hide when empty" contract).
    function RowCount: Integer;
  end;

{ Construct + configure (no show). Caller shows / frees. ATitle '' keeps the default caption. }
function TyBuildAboutDialog(const ATitle, AAppName, AVersion, ADescription,
  ACopyright, ALicense, AHomepage: string): TTyAboutForm;
{ Build + ShowModal + free. }
procedure TyShowAbout(const ATitle, AAppName, AVersion, ADescription,
  ACopyright, ALicense, AHomepage: string);

type
  TTyAboutDialog = class(TComponent)
  private
    FTitle, FAppName, FVersion, FDescription, FCopyright, FLicense, FHomepage: string;
    FOnShow: TNotifyEvent;
    FOnClose: TCloseEvent;
    FOnCanClose: TCloseQueryEvent;
  public
    procedure Execute;
  published
    property Title: string read FTitle write FTitle;
    property AppName: string read FAppName write FAppName;
    property Version: string read FVersion write FVersion;
    property Description: string read FDescription write FDescription;
    property Copyright: string read FCopyright write FCopyright;
    property License: string read FLicense write FLicense;
    property Homepage: string read FHomepage write FHomepage;
    property OnShow: TNotifyEvent read FOnShow write FOnShow;
    property OnClose: TCloseEvent read FOnClose write FOnClose;
    property OnCanClose: TCloseQueryEvent read FOnCanClose write FOnCanClose;
  end;

implementation

const
  cAboutW   = 380;   // fixed content width (like the other dialogs' fixed geometry)
  cBandPadV = 14;    // band top/bottom padding
  cNameH    = 32;    // app-name line height inside the band
  cVerH     = 20;    // version line height inside the band
  cHeadGap  = 14;    // band -> first body row
  cRowH     = 22;    // body row height
  cBodyGap  = 6;     // gap between body rows
  cBotPad   = 16;    // content bottom padding (= TyDlgPad)
  cNameSz   = 20;    // app-name font size (logical)
  cVerSz    = 11;
  cDescSz   = 11;
  cMetaSz   = 10;    // copyright / license
  cLinkSz   = 11;

{ TTyAboutForm }

constructor TTyAboutForm.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  Caption := rsDlgAboutTitle;   // builders may override
  AddButton(rsMsgBtnClose, mrCancel, True, True);   // Close = default + cancel (Enter/Esc/X)
end;

function TTyAboutForm.EffectiveController: TTyStyleController;
begin
  Result := Controller;
  if Result = nil then Result := TyDefaultController;
end;

function TTyAboutForm.BandHeight: Integer;
begin
  Result := 2 * cBandPadV + cNameH;
  if FVersion <> '' then Inc(Result, cVerH);
end;

procedure TTyAboutForm.AddRow(const AText: string; ASize, AWeight: Integer; ALink: Boolean);
var n: Integer;
begin
  n := Length(FRows);
  SetLength(FRows, n + 1);
  FRows[n].Text := AText;
  FRows[n].Size := ASize;
  FRows[n].Weight := AWeight;
  FRows[n].Link := ALink;
end;

procedure TTyAboutForm.DoLayout;
var sl: TStringList; i, contentH: Integer;
begin
  SetLength(FRows, 0);
  { Description: one row per non-blank line (caller controls wrapping via line breaks). }
  if Trim(FDescription) <> '' then
  begin
    sl := TStringList.Create;
    try
      sl.Text := FDescription;
      for i := 0 to sl.Count - 1 do
        if Trim(sl[i]) <> '' then AddRow(sl[i], cDescSz, 400, False);
    finally
      sl.Free;
    end;
  end;
  if Trim(FCopyright) <> '' then AddRow(FCopyright, cMetaSz, 400, False);
  if Trim(FLicense) <> '' then AddRow(FLicense, cMetaSz, 400, False);
  if Trim(FHomepage) <> '' then AddRow(FHomepage, cLinkSz, 400, True);

  contentH := BandHeight;
  if Length(FRows) > 0 then
    contentH := contentH + cHeadGap + Length(FRows) * cRowH + (Length(FRows) - 1) * cBodyGap;
  contentH := contentH + cBotPad;
  AutoSizeToContent(cAboutW, contentH);
end;

function TTyAboutForm.RowCount: Integer;
begin
  Result := Length(FRows);
end;

procedure TTyAboutForm.SetInfo(const AAppName, AVersion, ADescription, ACopyright, ALicense, AHomepage: string);
begin
  FAppName := AAppName;
  FVersion := AVersion;
  FDescription := ADescription;
  FCopyright := ACopyright;
  FLicense := ALicense;
  FHomepage := AHomepage;
  DoLayout;
  Invalidate;
end;

procedure TTyAboutForm.Paint;
var
  P: TTyPainter;
  S: TTyStyleSet;
  fill: TTyFill;
  r, band, rowR: TRect;
  accent, onAccent, bodyCol: TTyColor;
  nm: string;
  i, y, tw, lx, uy: Integer;
begin
  inherited Paint;
  if (Canvas = nil) or (not HandleAllocated) then Exit;   // crash-safe: GUI-only

  { Colours from the active theme: the band reuses the primary-button style (accent fill +
    on-accent text); body text uses the label colour. Guarded so a resolve hiccup can never
    crash Paint. }
  accent   := TyRGB($3B, $82, $F6);   // default-theme accent (fallback)
  onAccent := TyRGB(255, 255, 255);
  bodyCol  := TyRGB($1F, $29, $37);
  try
    S := EffectiveController.Model.ResolveStyle('TyButton', 'primary', []);
    if S.Background.Kind = tfkSolid then accent := S.Background.Color;
    if TyAlphaOf(S.TextColor) > 0 then onAccent := S.TextColor;
    S := EffectiveController.Model.ResolveStyle('TyLabel', '', []);
    if TyAlphaOf(S.TextColor) > 0 then bodyCol := S.TextColor;
  except
    // keep the fallbacks
  end;

  r := ContentRect;
  P := TTyPainter.Create;
  try
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);

    { Header band. }
    band := Rect(r.Left, r.Top, r.Right, r.Top + BandHeight);
    fill := Default(TTyFill);
    fill.Kind := tfkSolid;
    fill.Color := accent;
    P.FillBackground(band, fill, TyUniformCorners(0));

    nm := FAppName;
    if nm = '' then nm := Caption;
    if FVersion <> '' then
    begin
      P.DrawText(Rect(band.Left, band.Top + cBandPadV, band.Right, band.Top + cBandPadV + cNameH),
        nm, Font.Name, cNameSz, 700, onAccent, taCenter, tlCenter, True);
      P.DrawText(Rect(band.Left, band.Bottom - cBandPadV - cVerH, band.Right, band.Bottom - cBandPadV),
        FVersion, Font.Name, cVerSz, 400, onAccent, taCenter, tlCenter, True);
    end
    else
      P.DrawText(band, nm, Font.Name, cNameSz, 700, onAccent, taCenter, tlCenter, True);

    { Body rows. }
    FLinkRect := Rect(0, 0, 0, 0);
    y := r.Top + BandHeight + cHeadGap;
    for i := 0 to High(FRows) do
    begin
      rowR := Rect(r.Left + cBotPad, y, r.Right - cBotPad, y + cRowH);
      if FRows[i].Link then
      begin
        P.DrawText(rowR, FRows[i].Text, Font.Name, FRows[i].Size, FRows[i].Weight,
          accent, taCenter, tlCenter, True);
        { manual underline (DrawText has no underline): a hairline under the centred text }
        tw := P.MeasureText(FRows[i].Text, Font.Name, FRows[i].Size, FRows[i].Weight).cx;
        if tw > (rowR.Right - rowR.Left) then tw := rowR.Right - rowR.Left;
        lx := (rowR.Left + rowR.Right - tw) div 2;
        uy := rowR.Bottom - 3;
        fill.Color := accent;
        P.FillBackground(Rect(lx, uy, lx + tw, uy + 1), fill, TyUniformCorners(0));
        FLinkRect := rowR;
      end
      else
        P.DrawText(rowR, FRows[i].Text, Font.Name, FRows[i].Size, FRows[i].Weight,
          bodyCol, taCenter, tlCenter, True);
      Inc(y, cRowH + cBodyGap);
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyAboutForm.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (Button = mbLeft) and (FHomepage <> '') and PtInRect(FLinkRect, Point(X, Y)) then
    OpenURL(FHomepage);
end;

procedure TTyAboutForm.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if (FHomepage <> '') and PtInRect(FLinkRect, Point(X, Y)) then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
end;

{ Globals }

function TyBuildAboutDialog(const ATitle, AAppName, AVersion, ADescription,
  ACopyright, ALicense, AHomepage: string): TTyAboutForm;
begin
  Result := TTyAboutForm.CreateNew(Application);
  if ATitle <> '' then Result.Caption := ATitle;
  Result.SetInfo(AAppName, AVersion, ADescription, ACopyright, ALicense, AHomepage);
end;

procedure TyShowAbout(const ATitle, AAppName, AVersion, ADescription,
  ACopyright, ALicense, AHomepage: string);
var d: TTyAboutForm;
begin
  d := TyBuildAboutDialog(ATitle, AAppName, AVersion, ADescription, ACopyright, ALicense, AHomepage);
  try
    d.ShowModal;
  finally
    d.Free;
  end;
end;

{ TTyAboutDialog }

procedure TTyAboutDialog.Execute;
var d: TTyAboutForm;
begin
  d := TyBuildAboutDialog(FTitle, FAppName, FVersion, FDescription, FCopyright, FLicense, FHomepage);
  try
    TyForwardDialogEvents(d, FOnShow, FOnClose, FOnCanClose);
    d.ShowModal;
  finally
    d.Free;
  end;
end;

end.
