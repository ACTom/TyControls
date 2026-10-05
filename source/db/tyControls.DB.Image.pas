unit tyControls.DB.Image;
{$mode objfpc}{$H+}
{ The data-aware image (issue #34): LCL's TDBImage on the library's TTyCustomImage, split like
  the rest -- TTyCustomDBImage holds the data link and all the code, TTyDBImage publishes the
  base control's list unchanged and the data properties after it, in LCL's order.

  WHAT IS IN THE BLOB. A picture is stored as the graphic's own file format (PNG, BMP, JPEG...).
  By default the format's extension goes first, written the way LCL's TDBImage writes it --
  TStream.WriteAnsiString: a four-byte length and the characters -- so a blob written by either
  control reads in the other. WriteHeader False leaves the extension out; OnDBImageWrite puts the
  application's own header there instead. Reading takes the extension header when there is one
  (OnDBImageRead reads the application's header instead and names the format), and otherwise
  tells the format from the data itself: a blob written with any of these settings, or by a
  program that knows nothing of headers, reads back.

  The header is checked before it is believed: its length must be a short extension's and its
  characters an extension's, and a graphic class must exist for it. The first four bytes of a
  PNG, or of a memo's text, read as a length of hundreds of megabytes; LCL's ReadAnsiString would
  try to allocate that much before failing.

  WHAT IS AN EDIT. The picture changing outside a load -- the program assigning, loading or
  clearing it for the user, typically from an Open or Paste command -- is the user's edit. It is
  written into the record at once, as a choice is: an image takes no focus, so it gets neither
  EditingDone nor a focus loss to wait for. When the dataset cannot be edited (ReadOnly, a
  read-only field, AutoEdit off with nobody editing) the picture goes back to the field's. A
  cleared picture writes NULL. Changing Transparent re-masks the graphic, which the picture
  reports as a change; that is the program's doing, not an edit.

  AutoDisplay False leaves the picture empty after a load until LoadPicture (or AutoDisplay
  True) reads it -- for a form that shows many records and large pictures. QuickDraw is
  published for form compatibility with LCL's TDBImage, where it has no effect either. The
  Picture is not stored in a form file: the field is where it lives. }
interface

uses
  Classes, SysUtils, Controls, Graphics, LCLType, LMessages, DB, DBCtrls,
  tyControls.Image, tyControls.DB.Common;

type
  { The two hooks take LCL's event types (DBCtrls declares them for TDBImage), so a handler
    written for TDBImage fits as it is. }
  TTyCustomDBImage = class(TTyCustomImage)
  private
    FDataLink: TFieldDataLink;
    FLoading: Boolean;
    FInUserEdit: Boolean;
    FAutoDisplay: Boolean;
    FQuickDraw: Boolean;
    FWriteHeader: Boolean;
    { The picture shows the field (or the field's NULL); False after a load AutoDisplay left
      undone. LCL's PictureLoaded. }
    FPictureLoaded: Boolean;
    FOnDBImageRead: TOnDBImageRead;
    FOnDBImageWrite: TOnDBImageWrite;
    function GetDataField: string;
    function GetDataSource: TDataSource;
    function GetField: TField;
    function GetReadOnly: Boolean;
    function GetTransparent: Boolean;
    procedure SetDataField(const AValue: string);
    procedure SetDataSource(AValue: TDataSource);
    procedure SetReadOnly(AValue: Boolean);
    procedure SetAutoDisplay(AValue: Boolean);
    procedure SetTransparent(AValue: Boolean);
    { Fill the picture from AStream, positioned at the start of the blob. }
    procedure ReadPicture(AStream: TStream);
    procedure DataChange(Sender: TObject);
    procedure UpdateData(Sender: TObject);
    procedure CMGetDataLink(var Message: TLMessage); message CM_GETDATALINK;
  protected
    function GetStyleTypeKey: string; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure DoPictureChanged; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Read the field into the picture, if a load has not already (AutoDisplay False). }
    procedure LoadPicture; virtual;
    function ExecuteAction(AAction: TBasicAction): Boolean; override;
    function UpdateAction(AAction: TBasicAction): Boolean; override;
    property Field: TField read GetField;
    property DataField: string read GetDataField write SetDataField;
    property DataSource: TDataSource read GetDataSource write SetDataSource;
    property ReadOnly: Boolean read GetReadOnly write SetReadOnly default False;
    property AutoDisplay: Boolean read FAutoDisplay write SetAutoDisplay default True;
    { No effect, as in LCL; kept so a form written for TDBImage reads. }
    property QuickDraw: Boolean read FQuickDraw write FQuickDraw default True;
    { Put the graphic's extension in front of the data (LCL's format). }
    property WriteHeader: Boolean read FWriteHeader write FWriteHeader default True;
    property PictureLoaded: Boolean read FPictureLoaded;
    { The application reads its own header from the stream and names the graphic's format
      (an extension, e.g. 'png'); a name no graphic class answers to leaves the format to be
      told from the data that follows. }
    property OnDBImageRead: TOnDBImageRead read FOnDBImageRead write FOnDBImageRead;
    { The application writes its own header in place of the extension; the graphic follows. }
    property OnDBImageWrite: TOnDBImageWrite read FOnDBImageWrite write FOnDBImageWrite;
    { As the base control's; set from code it is not an edit of the picture. }
    property Transparent: Boolean read GetTransparent write SetTransparent default False;
    property Picture stored False;
  end;

  { TTyDBImage publishes TTyCustomDBImage's properties; everything lives in TTyCustomDBImage. }
  TTyDBImage = class(TTyCustomDBImage)
  published
    property Version;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseWheel;
    property OnMouseWheelUp;
    property OnMouseWheelDown;
    property OnContextPopup;
    property OnResize;
    property OnChangeBounds;
    property AutoSize;
    property DragMode;
    property DragKind;
    property DragCursor;
    property OnDragOver;
    property OnDragDrop;
    property OnStartDrag;
    property OnEndDrag;
    property OnMouseWheelHorz;
    property OnMouseWheelLeft;
    property OnMouseWheelRight;
    property OnShowHint;
    property PopupMenu;
    property Constraints;
    property BorderSpacing;
    property ParentShowHint;
    property Action;
    property OnPaint;
    property StyleClass;
    property StyleOverride;
    property Controller;
    property Picture;
    property Stretch;
    property Proportional;
    property Center;
    property Transparent;
    property StretchOutEnabled;
    property StretchInEnabled;
    property KeepOriginXWhenClipped;
    property KeepOriginYWhenClipped;
    property AntialiasingMode;
    property Images;
    property ImageName;
    property ImageIndex;
    property ImageWidth;
    property OnPictureChanged;
    property Align;
    property Anchors;
    property AutoDisplay;
    property DataField;
    property DataSource;
    property QuickDraw;
    property ReadOnly;
    property WriteHeader;
    property OnDBImageRead;
    property OnDBImageWrite;
  end;

implementation

uses
  tyControls.StyleModel;

const
  { Longer than any graphic file extension; a "length" past it is the data, not a header. }
  CMaxExtLength = 16;

{ The extension header LCL's TDBImage writes (TStream.WriteAnsiString), if AStream holds one at
  its position: AStream is left after it. Otherwise '' and AStream is where it was. }
function ReadExtHeader(AStream: TStream): string;
var
  start: Int64;
  len: LongInt;
  i: Integer;
begin
  Result := '';
  start := AStream.Position;
  len := 0;
  if AStream.Size - start > SizeOf(len) then
  begin
    AStream.ReadBuffer(len, SizeOf(len));
    if (len >= 1) and (len <= CMaxExtLength) and (len <= AStream.Size - AStream.Position) then
    begin
      SetLength(Result, len);
      AStream.ReadBuffer(Result[1], len);
      for i := 1 to len do
        if not (Result[i] in ['a'..'z', 'A'..'Z', '0'..'9']) then
        begin
          Result := '';
          Break;
        end;
      if (Result <> '') and (GetGraphicClassForFileExtension(Result) = nil) then Result := '';
    end;
  end;
  if Result = '' then AStream.Position := start;
end;

{ ====================================================================== TTyCustomDBImage == }

constructor TTyCustomDBImage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csReplicatable];
  FAutoDisplay := True;
  FQuickDraw := True;
  FWriteHeader := True;
  FDataLink := TFieldDataLink.Create;
  FDataLink.Control := Self;
  FDataLink.OnDataChange := @DataChange;
  FDataLink.OnUpdateData := @UpdateData;
end;

destructor TTyCustomDBImage.Destroy;
begin
  FDataLink.OnDataChange := nil;
  FDataLink.OnUpdateData := nil;
  FreeAndNil(FDataLink);
  inherited Destroy;
end;

function TTyCustomDBImage.GetStyleTypeKey: string;
begin
  Result := 'TyDBImage';
end;

function TTyCustomDBImage.GetDataField: string;
begin
  Result := FDataLink.FieldName;
end;

function TTyCustomDBImage.GetDataSource: TDataSource;
begin
  Result := FDataLink.DataSource;
end;

function TTyCustomDBImage.GetField: TField;
begin
  Result := FDataLink.Field;
end;

function TTyCustomDBImage.GetReadOnly: Boolean;
begin
  Result := FDataLink.ReadOnly;
end;

function TTyCustomDBImage.GetTransparent: Boolean;
begin
  Result := TTyCustomImage(Self).Transparent;
end;

procedure TTyCustomDBImage.SetDataField(const AValue: string);
begin
  FDataLink.FieldName := AValue;
end;

procedure TTyCustomDBImage.SetDataSource(AValue: TDataSource);
begin
  ChangeDataSource(Self, FDataLink, AValue);
end;

procedure TTyCustomDBImage.SetReadOnly(AValue: Boolean);
begin
  FDataLink.ReadOnly := AValue;
end;

procedure TTyCustomDBImage.SetAutoDisplay(AValue: Boolean);
begin
  if FAutoDisplay = AValue then Exit;
  FAutoDisplay := AValue;
  if FAutoDisplay then LoadPicture;
end;

{ The base control pushes Transparent into the graphic's mask, and the graphic reports that
  as a change of the picture. }
procedure TTyCustomDBImage.SetTransparent(AValue: Boolean);
var
  was: Boolean;
begin
  was := FLoading;
  FLoading := True;
  try
    TTyCustomImage(Self).Transparent := AValue;
  finally
    FLoading := was;
  end;
end;

procedure TTyCustomDBImage.ReadPicture(AStream: TStream);
var
  ext: string;
  gc: TGraphicClass;
  g: TGraphic;
  dataPos: Int64;
begin
  ext := '';
  if Assigned(FOnDBImageRead) then
    FOnDBImageRead(Self, AStream, ext)
  else
    ext := ReadExtHeader(AStream);
  gc := nil;
  if ext <> '' then gc := GetGraphicClassForFileExtension(ext);
  dataPos := AStream.Position;
  if gc <> nil then
  begin
    g := gc.Create;
    try
      try
        g.LoadFromStream(AStream);
        Picture.Assign(g);
        Exit;
      except
        on Exception do
          AStream.Position := dataPos;   // the header named the wrong format: ask the data
      end;
    finally
      g.Free;
    end;
  end;
  try
    Picture.LoadFromStream(AStream);
  except
    on Exception do
      Picture.Clear;   // not a picture this program can read
  end;
end;

procedure TTyCustomDBImage.LoadPicture;
var
  f: TField;
  s: TStream;
  was: Boolean;
begin
  if FPictureLoaded then Exit;
  was := FLoading;
  FLoading := True;
  try
    f := FDataLink.Field;
    if (f is TBlobField) and not f.IsNull then
    begin
      s := f.DataSet.CreateBlobStream(f, bmRead);
      try
        if (s = nil) or (s.Size = 0) then
          Picture.Clear
        else
          ReadPicture(s);
      finally
        s.Free;
      end;
    end
    else
      Picture.Clear;
    FPictureLoaded := True;
  finally
    FLoading := was;
  end;
end;

procedure TTyCustomDBImage.DataChange(Sender: TObject);
var
  was: Boolean;
begin
  if FInUserEdit then Exit;   // the dataset entering dsEdit for the user's picture: keep it
  FPictureLoaded := False;
  if FAutoDisplay then
    LoadPicture
  else
  begin
    was := FLoading;
    FLoading := True;
    try
      Picture.Clear;
    finally
      FLoading := was;
    end;
  end;
end;

procedure TTyCustomDBImage.UpdateData(Sender: TObject);
var
  f: TField;
  s: TStream;
  ext: string;
  p: Integer;
begin
  f := FDataLink.Field;
  if (Picture.Graphic = nil) or Picture.Graphic.Empty then
  begin
    f.Clear;
    Exit;
  end;
  ext := Picture.Graphic.GetFileExtensions;   // e.g. 'jpg;jpeg;jpe;jfif': the first one
  p := Pos(';', ext);
  if p > 0 then ext := Copy(ext, 1, p - 1);
  s := f.DataSet.CreateBlobStream(f, bmWrite);
  try
    if Assigned(FOnDBImageWrite) then
      FOnDBImageWrite(Self, s, ext)
    else if FWriteHeader then
      s.WriteAnsiString(ext);
    Picture.Graphic.SaveToStream(s);
  finally
    s.Free;
  end;
end;

procedure TTyCustomDBImage.DoPictureChanged;
begin
  inherited DoPictureChanged;
  if FLoading or FInUserEdit or (FDataLink = nil) or (FDataLink.Field = nil)
    or (csLoading in ComponentState) or (csDestroying in ComponentState) then Exit;
  if not (FDataLink.Field is TBlobField) then
  begin
    FDataLink.Reset;   // a picture has nowhere to go in this field: show the field again
    Exit;
  end;
  FPictureLoaded := True;   // the picture is the user's now, and what the record will hold
  TyDBChoiceChanged(FDataLink, FInUserEdit);
end;

procedure TTyCustomDBImage.CMGetDataLink(var Message: TLMessage);
begin
  Message.Result := PtrUInt(FDataLink);
end;

procedure TTyCustomDBImage.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FDataLink <> nil) and (AComponent = DataSource) then
    DataSource := nil;
end;

function TTyCustomDBImage.ExecuteAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited ExecuteAction(AAction)
    or ((FDataLink <> nil) and FDataLink.ExecuteAction(AAction));
end;

function TTyCustomDBImage.UpdateAction(AAction: TBasicAction): Boolean;
begin
  Result := inherited UpdateAction(AAction)
    or ((FDataLink <> nil) and FDataLink.UpdateAction(AAction));
end;

initialization
  TyTryRegisterTypeKeyParent('TyDBImage', 'TyImage');

finalization
  TyUnregisterTypeKeyParent('TyDBImage');

end.
