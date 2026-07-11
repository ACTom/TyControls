unit tyControls.PreviewBox;
{$mode objfpc}{$H+}

{ Phase 7 batch 5b -- a reusable content-preview control.

  TTyPreviewBox is a windowed themed container that shows one of three things,
  switching by content:
    * an image  (an internal TTyImage, Proportional + Center),
    * text      (an internal read-only TTyMemo),
    * a centred placeholder message (drawn in Paint when neither child shows).
  It also offers a low-level owner-draw escape hatch (ShowCustom + OnPaintPreview,
  the same TTyPaintSurfaceEvent as TTyPaintPanel) for callers that want to render
  an unrecognised format themselves.

  The file dialogs (tyControls.Dialogs.FileDialog) use it for their preview pane;
  picture variants set AllowText=False so only images preview.

  typeKey is 'TyPanel' (REUSED -- no new .tycss token). The placeholder text +
  the custom-paint path resolve their style via ActiveController (nil-safe).

  The ONLY headless-testable seam is the pure classifier TyPreviewClassify: the
  windowed control (and the dialog form) cannot be instantiated under the console
  test runner (no win32 handle), so the file/child-switch behaviour is real-machine
  verified, and only the extension classification is factored out for a unit test. }

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, StdCtrls, LazFileUtils,
  BGRABitmap,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller,
  tyControls.Image, tyControls.Memo, tyControls.PaintPanel;

type
  { What kind of preview a file's extension implies. }
  TTyPreviewKind = (pkImage, pkText, pkOther);

{ Pure extension classifier -- the single headless-testable seam.
    pkImage : .png .jpg .jpeg .bmp .gif .ico .tif .tiff
    pkText  : .txt .md .json .log .ini .xml .csv .yml .yaml .html .htm .js .css
              .pas .lpr .inc .pp .lfm .sh .bat
    pkOther : anything else (case-insensitive; empty / no extension -> pkOther). }
function TyPreviewClassify(const AFileName: string): TTyPreviewKind;

type
  { ===================================================================
    TTyPreviewBox -- the reusable preview container.
    =================================================================== }
  TTyPreviewBox = class(TTyCustomControl)
  private
    { Both children are owned by the box (freed with it) and Align=alClient; at most
      one is Visible at a time (LCL aligns only visible controls, so the visible one
      always fills the client -- two simultaneous alClient children would starve one). }
    FImage:   TTyImage;
    FMemo:    TTyMemo;
    FMessage: string;    { placeholder text, drawn centred when no child shows }
    FAllowText: Boolean; { False (picture variants) -> PreviewFile never tries text }
    FCustom:  Boolean;   { custom-paint mode -> Paint fires FOnPaintPreview }
    FOnPaintPreview: TTyPaintSurfaceEvent;
    { Hide both children + leave custom mode (a common prelude to every Show*). }
    procedure HideChildren;
  protected
    function  GetStyleTypeKey: string; override;   { 'TyPanel' -- reuse, no new token }
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    { Push a per-instance controller down to the embedded panes so a standalone box
      with its own Controller themes the previewed image/text too (not just the frame). }
    procedure SetController(AValue: TTyStyleController); override;
  public
    constructor Create(AOwner: TComponent); override;
    { Built-in image load: shows FImage on success, else False (caller may fall back). }
    function  ShowImageFile(const APath: string): Boolean;
    { Read the first ~64 KB of APath into FMemo + show it; False on read error. }
    function  ShowTextFile(const APath: string): Boolean;
    { A caller-supplied bitmap -> FImage (bridged through a TBitmap; BGRA 3.2.2 has
      no Create(TGraphic)). nil clears. }
    procedure ShowImage(ABitmap: TBGRABitmap);
    { Caller-supplied text -> FMemo. }
    procedure ShowText(const AText: string);
    { Hide the children; draw AMsg centred (e.g. "cannot preview"). }
    procedure ShowMessage(const AMsg: string);
    { Hide the children; enter custom-paint mode so Paint calls OnPaintPreview. }
    procedure ShowCustom;
    { Hide everything; blank. }
    procedure Clear;
    { Built-in dispatch on TyPreviewClassify: image -> ShowImageFile; text ->
      (AllowText) ShowTextFile else a placeholder; else a placeholder. A failed
      built-in load falls back to the placeholder, so every path ends visible. }
    procedure PreviewFile(const APath: string);
  published
    property AllowText: Boolean read FAllowText write FAllowText default True;
    { Low-level owner-draw hook (same signature as TTyPaintPanel.OnPaintSurface).
      Fires only in custom-paint mode (ShowCustom), with the content rect. }
    property OnPaintPreview: TTyPaintSurfaceEvent read FOnPaintPreview write FOnPaintPreview;
    property Align;
    property Anchors;
    property Visible;
    property Enabled;
    property StyleClass;
    property Controller;
  end;

implementation

resourcestring
  { Local (not centralised in tyControls.StrConsts) -- see the FileDialog note; still
    translatable via this unit's own .po. }
  rsPvCannotPreview = 'Cannot preview this file';

const
  PreviewHeadBytes = 64 * 1024;   { how much of a text file the preview reads }

{ ---------------------------------------------------------------------------
  TyPreviewClassify -- the pure, headless-testable classifier
  --------------------------------------------------------------------------- }

function TyPreviewClassify(const AFileName: string): TTyPreviewKind;
var
  ext: string;
begin
  ext := LowerCase(ExtractFileExt(AFileName));
  if (ext = '.png') or (ext = '.jpg') or (ext = '.jpeg') or (ext = '.bmp')
     or (ext = '.gif') or (ext = '.ico') or (ext = '.tif') or (ext = '.tiff') then
    Result := pkImage
  else if (ext = '.txt') or (ext = '.md') or (ext = '.json') or (ext = '.log')
     or (ext = '.ini') or (ext = '.xml') or (ext = '.csv') or (ext = '.yml')
     or (ext = '.yaml') or (ext = '.html') or (ext = '.htm') or (ext = '.js')
     or (ext = '.css') or (ext = '.pas') or (ext = '.lpr') or (ext = '.inc')
     or (ext = '.pp') or (ext = '.lfm') or (ext = '.sh') or (ext = '.bat') then
    Result := pkText
  else
    Result := pkOther;
end;

{ Read the first AMaxBytes of APath as a raw byte string (UTF-8 file bytes flow
  straight into the memo). Crash-safe callers wrap this in try/except. }
function TyReadHeadText(const APath: string; AMaxBytes: Integer): string;
var
  fs: TFileStream;
  n: Int64;
begin
  Result := '';
  fs := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    n := fs.Size;
    if n > AMaxBytes then n := AMaxBytes;
    if n > 0 then
    begin
      SetLength(Result, n);
      fs.ReadBuffer(Result[1], n);
    end;
  finally
    fs.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  TTyPreviewBox
  --------------------------------------------------------------------------- }

constructor TTyPreviewBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  SetBounds(0, 0, 220, 200);   { sensible default drop size }
  FAllowText := True;
  FCustom := False;
  FMessage := '';

  { Image child: contain-fit, centred; hidden until an image is shown. csNoDesignVisible
    keeps this internal pane from leaking into the IDE designer once the box is on the
    palette (the embedded-subcontrol footgun). }
  FImage := TTyImage.Create(Self);
  FImage.Parent := Self;
  FImage.ControlStyle := FImage.ControlStyle + [csNoDesignVisible];
  FImage.Align := alClient;
  FImage.Proportional := True;
  FImage.Center := True;
  FImage.Visible := False;

  { Text child: read-only, vertical scrollbar on overflow, no wrap; hidden until
    text is shown. }
  FMemo := TTyMemo.Create(Self);
  FMemo.Parent := Self;
  FMemo.ControlStyle := FMemo.ControlStyle + [csNoDesignVisible];
  FMemo.Align := alClient;
  FMemo.ReadOnly := True;
  FMemo.ScrollBars := ssAutoVertical;
  FMemo.WordWrap := False;
  FMemo.Visible := False;
end;

function TTyPreviewBox.GetStyleTypeKey: string;
begin
  Result := 'TyPanel';   { reuse the panel surface -- no new .tycss rule }
end;

procedure TTyPreviewBox.SetController(AValue: TTyStyleController);
begin
  inherited SetController(AValue);
  if FImage <> nil then FImage.Controller := AValue;
  if FMemo <> nil then FMemo.Controller := AValue;
end;

procedure TTyPreviewBox.HideChildren;
begin
  FImage.Visible := False;
  FMemo.Visible := False;
  FCustom := False;
end;

procedure TTyPreviewBox.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  FrameR, ContentR: TRect;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    FrameR := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    DrawFrame(P, FrameR, S);
    { Padding-inset content rect (same scaling as TTyPaintPanel). }
    ContentR := Rect(
      FrameR.Left   + P.Scale(S.Padding.Left),
      FrameR.Top    + P.Scale(S.Padding.Top),
      FrameR.Right  - P.Scale(S.Padding.Right),
      FrameR.Bottom - P.Scale(S.Padding.Bottom));
    if FCustom then
    begin
      { Owner-draw: hand the live painter + content rect to the app. }
      if Assigned(FOnPaintPreview) then
        FOnPaintPreview(Self, P, ContentR);
    end
    else if (not FImage.Visible) and (not FMemo.Visible) and (FMessage <> '') then
      { Placeholder message, centred, in the theme text colour. }
      P.DrawText(ContentR, FMessage, S.FontName, ResolveFontSize(S), S.FontWeight,
        S.TextColor, taCenter, tlCenter, True);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyPreviewBox.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

function TTyPreviewBox.ShowImageFile(const APath: string): Boolean;
begin
  Result := False;
  if not FileExistsUTF8(APath) then Exit;
  { A corrupt / unsupported image must not crash the box -- fail to False. }
  try
    FImage.Picture.LoadFromFile(APath);
  except
    FImage.Picture.Clear;
    Exit;
  end;
  HideChildren;
  FMessage := '';
  FImage.Visible := True;
  Invalidate;
  Result := True;
end;

function TTyPreviewBox.ShowTextFile(const APath: string): Boolean;
var
  s: string;
begin
  Result := False;
  if not FileExistsUTF8(APath) then Exit;
  try
    s := TyReadHeadText(APath, PreviewHeadBytes);
  except
    Exit;
  end;
  ShowText(s);
  Result := True;
end;

procedure TTyPreviewBox.ShowImage(ABitmap: TBGRABitmap);
var
  tmp: TBitmap;
begin
  if ABitmap = nil then
  begin
    Clear;
    Exit;
  end;
  { Bridge BGRA -> TPicture through a TBitmap (BGRA 3.2.2 has no Create(TGraphic)
    and TPicture takes a TGraphic). MakeBitmapCopy flattens alpha onto white. }
  tmp := ABitmap.MakeBitmapCopy(clWhite);
  try
    FImage.Picture.Bitmap.Assign(tmp);
  finally
    tmp.Free;
  end;
  HideChildren;
  FMessage := '';
  FImage.Visible := True;
  Invalidate;
end;

procedure TTyPreviewBox.ShowText(const AText: string);
begin
  HideChildren;
  FMessage := '';
  { Use the Text SETTER, not FMemo.Lines.Text: TTyMemo.GetLines exposes the raw FLines
    with no change hook, so a direct Lines.Text mutation skips the memo's invalidation
    (stale visual rows + widest-width across a reused preview). SetText funnels through
    AfterEdit -> InvalidateVisualRows, so each file re-lays out correctly + fast. }
  FMemo.Text := AText;
  FMemo.Visible := True;
  Invalidate;
end;

procedure TTyPreviewBox.ShowMessage(const AMsg: string);
begin
  HideChildren;
  FMessage := AMsg;
  Invalidate;
end;

procedure TTyPreviewBox.ShowCustom;
begin
  FImage.Visible := False;
  FMemo.Visible := False;
  FMessage := '';
  FCustom := True;   { HideChildren clears FCustom, so set it directly here }
  Invalidate;
end;

procedure TTyPreviewBox.Clear;
begin
  HideChildren;
  FMessage := '';
  FImage.Picture.Clear;
  FMemo.Lines.Clear;
  Invalidate;
end;

procedure TTyPreviewBox.PreviewFile(const APath: string);
begin
  case TyPreviewClassify(APath) of
    pkImage:
      if not ShowImageFile(APath) then ShowMessage(rsPvCannotPreview);
    pkText:
      if FAllowText then
      begin
        if not ShowTextFile(APath) then ShowMessage(rsPvCannotPreview);
      end
      else
        ShowMessage(rsPvCannotPreview);
  else
    ShowMessage(rsPvCannotPreview);
  end;
end;

initialization
  { So a .lfm that streams a TTyPreviewBox resolves the class. }
  RegisterClass(TTyPreviewBox);

end.
