unit tyControls.Component;
{$mode objfpc}{$H+}

{ Shared ancestor for the library's NON-VISUAL components (dialog wrappers, image
  lists, hint/popover managers, the native styler...).

  Its only job is to carry the read-only `Version` property that the design-time
  editor turns into the About button in the Object Inspector. The two visual bases
  (TTyGraphicControl / TTyCustomControl in tyControls.Base) already publish it, so
  every dragged CONTROL had it; components descending straight from TComponent did
  not, and copying the same three lines into ~25 declarations is exactly the kind of
  duplication that goes stale one class at a time. One ancestor, one registration.

  It lives in its own unit rather than in tyControls.Types (a leaf types/consts unit
  that must stay dependency-free) or tyControls.Base (which is about VISUAL controls
  and pulls in Controls/Graphics/BGRABitmap — far too much weight for a component
  that only wants a version string).

  `Version` is READ-ONLY on purpose: TWriter skips properties with no setter, so
  reparenting an existing component to this class streams nothing extra and changes
  no .lfm. }

interface

uses
  Classes, tyControls.Types;

type
  TTyComponent = class(TComponent)
  public
    function GetVersion: string;
  published
    { Read-only library version (TyVersion); the design-time editor for this property
      opens the About dialog. }
    property Version: string read GetVersion;
  end;

implementation

function TTyComponent.GetVersion: string;
begin
  Result := TyVersion;
end;

end.
