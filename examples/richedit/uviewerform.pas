unit uviewerform;

{ The picture viewer: a picture of the document (or a block that shows one, an equation) at its
  own size in pixels - the window as large as the picture, never larger than the screen's work
  area; a larger picture is moved by dragging and zoomed with the wheel (TTyImageView). Esc
  closes it. Opened by a double click on a picture (the rich edit's OnObjectDblClick). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Forms, Controls, Graphics, LCLType, tyControls.Controller,
  tyControls.Form, tyControls.FormSurface, tyControls.ImageView;

type
  TViewerForm = class(TTyForm)
    Surface: TTyFormSurface;
    Bar: TTyTitleBar;
    View: TTyImageView;
    procedure FormCreate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  end;

{ The viewer for APicture (an object of the document that hands itself to a TPicture:
  TTyRichPicture, a kept block that shows a picture), sized to it, not shown; nil when it shows
  no picture (a metafile the control draws as a frame, an empty picture). The caller frees it. }
function MakeViewer(APicture: TPersistent; const ACaption: string): TViewerForm;
{ MakeViewer's form shown modal and freed. False: no picture - nothing shown. }
function ViewPicture(APicture: TPersistent; const ACaption: string): Boolean;

implementation

{$R *.lfm}

function ViewPicture(APicture: TPersistent; const ACaption: string): Boolean;
var
  f: TViewerForm;
begin
  f := MakeViewer(APicture, ACaption);
  Result := f <> nil;
  if f = nil then Exit;
  try
    f.ShowModal;
  finally
    f.Free;
  end;
end;

function MakeViewer(APicture: TPersistent; const ACaption: string): TViewerForm;
var
  f: TViewerForm;
  pic: TPicture;
  wa: TRect;
  w, h, chromeW, chromeH, ppi: Integer;
begin
  Result := nil;
  pic := TPicture.Create;
  try
    try
      // the object makes its image's bytes for this call and keeps none of them
      pic.Assign(APicture);
    except
      on EInvalidGraphic do Exit;
      on EConvertError do Exit;
    end;
    if (pic.Graphic = nil) or pic.Graphic.Empty then Exit;
    f := TViewerForm.Create(Application);
    try
      f.Caption := ACaption;
      f.Bar.Caption := Format('%s - %d x %d', [ACaption, pic.Width, pic.Height]);
      f.View.AutoFit := False;
      f.View.AnimationDuration := 0;
      f.View.Picture := pic;
      // the window: the picture's own size and the title bar (the view's frame a few pixels),
      // inside the work area - not smaller than a title bar's buttons need
      ppi := Screen.PixelsPerInch;
      chromeW := MulDiv(8, ppi, 96);
      chromeH := f.Bar.Height + chromeW;
      wa := Screen.WorkAreaRect;
      w := Min(Max(pic.Width + chromeW, MulDiv(320, ppi, 96)), wa.Right - wa.Left);
      h := Min(Max(pic.Height + chromeH, MulDiv(200, ppi, 96)), wa.Bottom - wa.Top);
      f.SetBounds(wa.Left + (wa.Right - wa.Left - w) div 2, wa.Top + (wa.Bottom - wa.Top - h) div 2,
        w, h);
      f.View.ZoomToActual;
      Result := f;
    except
      f.Free;
      raise;
    end;
  finally
    pic.Free;
  end;
end;

procedure TViewerForm.FormCreate(Sender: TObject);
begin
  ApplyChromeTheme(TyDefaultController);
end;

procedure TViewerForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Key := 0;
    Close;
  end;
end;

end.
