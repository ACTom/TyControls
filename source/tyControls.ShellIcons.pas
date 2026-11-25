unit tyControls.ShellIcons;

{ #246. The pictures the places of a file dialog are listed with: a folder, a drive, the home
  folder and the six common folders (Desktop, Documents, Downloads, Pictures, Music, Videos).

  Drawn here, as 128 px BGRA masters a TTyVirtualImageList renders down from -- no image
  file, no icon font. Like the folder / drive / file glyphs of the shell tree and list they
  are CONTENT pictures in a fixed palette, not theme chrome: mid-tone, so they read on a
  light surface and on a dark one alike. An application that wants its own gives the places
  view or the folder box another image list. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  BGRABitmap, BGRABitmapTypes,
  tyControls.ImageCollection, tyControls.FileSystem;

{ The name AIcon's picture has in a collection TyAddPlaceIcons filled ('place-home', ...).
  fpiByKind has none: ''. }
function TyPlaceIconName(AIcon: TTyFsPlaceIcon): string;

{ Adds the nine pictures -- fpiFolder to fpiVideos, in the order of the type -- to
  ACollection under their TyPlaceIconName, and appends those names to ANames (the Names of
  the image list that shows the collection), so the picture of AIcon is the image
  TyPlaceIconIndex(AIcon, <ANames.Count before the call>). }
procedure TyAddPlaceIcons(ACollection: TTyCustomImageCollection; ANames: TStrings);

{ Where AIcon's picture is in an image list whose first place picture is image ABase.
  fpiByKind is drawn as a folder. }
function TyPlaceIconIndex(AIcon: TTyFsPlaceIcon; ABase: Integer = 0): Integer;

implementation

const
  G = 128;   // the master's edge

function TyPlaceIconName(AIcon: TTyFsPlaceIcon): string;
const
  cNames: array[TTyFsPlaceIcon] of string = ('', 'place-folder', 'place-drive', 'place-home',
    'place-desktop', 'place-documents', 'place-downloads', 'place-pictures', 'place-music',
    'place-videos');
begin
  Result := cNames[AIcon];
end;

function TyPlaceIconIndex(AIcon: TTyFsPlaceIcon; ABase: Integer): Integer;
begin
  if AIcon = fpiByKind then AIcon := fpiFolder;
  Result := ABase + Ord(AIcon) - Ord(fpiFolder);
end;

function Shade(const C: TBGRAPixel; AFactor: Single): TBGRAPixel;
begin
  Result := BGRA(Round(C.red * AFactor), Round(C.green * AFactor), Round(C.blue * AFactor),
    C.alpha);
end;

procedure DrawFolder(B: TBGRABitmap);
var
  body: TBGRAPixel;
begin
  body := BGRA(226, 176, 66);                                        // warm amber
  B.FillRoundRectAntialias(8, 20, 60, 46, 6, 6, Shade(body, 0.82));  // tab
  B.FillRoundRectAntialias(8, 34, 120, 112, 8, 8, body);             // body
  B.FillRectAntialias(8, 34, 120, 42, BGRA(255, 255, 255, 40));      // top lip
end;

procedure DrawDrive(B: TBGRABitmap);
var
  body: TBGRAPixel;
begin
  body := BGRA(96, 116, 150);                                           // steel blue
  B.FillRoundRectAntialias(14, 40, 114, 100, 10, 10, body);             // chassis
  B.FillRectAntialias(14, 40, 114, 66, BGRA(255, 255, 255, 30));        // top band
  B.FillRoundRectAntialias(26, 78, 90, 86, 3, 3, Shade(body, 0.45));    // media slot
  B.FillEllipseAntialias(100, 82, 5, 5, BGRA(120, 220, 140, 255));      // activity light
end;

procedure DrawHome(B: TBGRABitmap);
var
  wall: TBGRAPixel;
begin
  wall := BGRA(92, 148, 206);                                            // sky blue
  B.FillRoundRectAntialias(26, 58, 102, 114, 6, 6, wall);                // walls
  B.FillPolyAntialias([PointF(64, 12), PointF(122, 66), PointF(6, 66)],
    Shade(wall, 0.72));                                                  // roof
  B.FillRoundRectAntialias(54, 78, 74, 114, 3, 3, Shade(wall, 0.45));    // door
end;

procedure DrawDesktop(B: TBGRABitmap);
var
  frame: TBGRAPixel;
begin
  frame := BGRA(70, 96, 136);
  B.FillRoundRectAntialias(8, 18, 120, 92, 9, 9, frame);                 // bezel
  B.FillRoundRectAntialias(17, 27, 111, 83, 3, 3, BGRA(104, 178, 238));  // screen
  B.FillRectAntialias(56, 92, 72, 104, Shade(frame, 0.85));              // neck
  B.FillRoundRectAntialias(36, 102, 92, 113, 4, 4, frame);               // foot
end;

procedure DrawDocuments(B: TBGRABitmap);
var
  sheet, ink: TBGRAPixel;
begin
  sheet := BGRA(116, 150, 200);
  ink := BGRA(255, 255, 255, 225);
  B.FillRoundRectAntialias(24, 8, 104, 120, 9, 9, sheet);                // the sheet
  B.FillRoundRectAntialias(40, 34, 88, 43, 3, 3, ink);                   // three lines
  B.FillRoundRectAntialias(40, 58, 88, 67, 3, 3, ink);
  B.FillRoundRectAntialias(40, 82, 72, 91, 3, 3, ink);
end;

procedure DrawDownloads(B: TBGRABitmap);
var
  c: TBGRAPixel;
begin
  c := BGRA(74, 168, 110);                                               // green
  B.FillRectAntialias(53, 12, 75, 58, c);                                // shaft
  B.FillPolyAntialias([PointF(26, 52), PointF(102, 52), PointF(64, 92)], c);   // head
  B.FillRoundRectAntialias(16, 102, 112, 116, 5, 5, Shade(c, 0.8));      // the tray it lands on
end;

procedure DrawPictures(B: TBGRABitmap);
var
  sky: TBGRAPixel;
begin
  sky := BGRA(66, 150, 192);
  B.FillRoundRectAntialias(8, 20, 120, 108, 10, 10, sky);                // the picture
  B.FillEllipseAntialias(40, 46, 10, 10, BGRA(250, 214, 92));            // sun
  B.FillPolyAntialias([PointF(18, 98), PointF(50, 60), PointF(70, 82), PointF(86, 66),
    PointF(110, 98)], BGRA(255, 255, 255, 230));                         // hills
end;

procedure DrawMusic(B: TBGRABitmap);
var
  c: TBGRAPixel;
begin
  c := BGRA(212, 86, 130);                                               // pink
  B.FillPolyAntialias([PointF(44, 30), PointF(108, 14), PointF(108, 36), PointF(44, 52)], c);  // beam
  B.FillRectAntialias(44, 30, 55, 96, c);                                // two stems
  B.FillRectAntialias(97, 16, 108, 82, c);
  B.FillEllipseAntialias(38, 96, 17, 13, c);                             // two heads
  B.FillEllipseAntialias(91, 82, 17, 13, c);
end;

procedure DrawVideos(B: TBGRABitmap);
begin
  B.FillRoundRectAntialias(8, 24, 120, 104, 12, 12, BGRA(138, 106, 206));   // the screen, purple
  B.FillPolyAntialias([PointF(52, 44), PointF(52, 84), PointF(86, 64)],
    BGRA(255, 255, 255, 235));                                              // play
end;

procedure TyAddPlaceIcons(ACollection: TTyCustomImageCollection; ANames: TStrings);
var
  icon: TTyFsPlaceIcon;
  bmp: TBGRABitmap;
begin
  for icon := fpiFolder to High(TTyFsPlaceIcon) do
  begin
    bmp := TBGRABitmap.Create(G, G, BGRAPixelTransparent);
    try
      case icon of
        fpiFolder:    DrawFolder(bmp);
        fpiDrive:     DrawDrive(bmp);
        fpiHome:      DrawHome(bmp);
        fpiDesktop:   DrawDesktop(bmp);
        fpiDocuments: DrawDocuments(bmp);
        fpiDownloads: DrawDownloads(bmp);
        fpiPictures:  DrawPictures(bmp);
        fpiMusic:     DrawMusic(bmp);
      else
        DrawVideos(bmp);
      end;
      ACollection.AddBitmap(TyPlaceIconName(icon), bmp);
    finally
      bmp.Free;
    end;
    if ANames <> nil then ANames.Add(TyPlaceIconName(icon));
  end;
end;

end.
