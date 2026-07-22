unit tyControls.GridCell;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, LCLType,
  tyControls.Base;
type
  { One cell of a TTyGridPanel. A transparent, windowed container: it paints
    NOTHING (no themed background/border) and only positions + clips + pads its
    dropped children. Col/Row are its grid coordinates (set by the grid, streamed
    so a loaded form re-seats it). Padding insets its content on all sides.
    Mirrors TTyTabSheet's designer-container ControlStyle so the IDE treats it as
    a fixed-bounds, droppable design surface — but stays VISIBLE (all cells show
    at once, unlike a tab page). }
  TTyGridCell = class(TTyCustomControl)
  private
    FPadding: Integer;
    FCol: Integer;
    FRow: Integer;
    FProvisional: Boolean;
    procedure SetPadding(AValue: Integer);
  protected
    procedure SetParent(AParent: TWinControl); override;
    function GetStyleTypeKey: string; override;
    procedure AdjustClientRect(var ARect: TRect); override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    { Transient (NON-published, never streamed): True on a cell the owning grid seeded
      as a constructor default. A streamed load discards these once real cells arrive
      (see TTyGridPanel.Loaded); a designer drop / code path keeps them. }
    property Provisional: Boolean read FProvisional write FProvisional;
  published
    { Set by the owning grid; published so a streamed form re-seats the cell. }
    property Col: Integer read FCol write FCol;
    property Row: Integer read FRow write FRow;
    property Padding: Integer read FPadding write SetPadding default 0;
    property Align;
    property Anchors;
    property BorderSpacing;
    property Visible;
    property Constraints;
  end;

implementation

uses
  tyControls.GridPanel;   // for TTyGridPanel in SetParent (one-way: impl only)

constructor TTyGridCell.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls, csDesignFixedBounds, csNoFocus];
  FPadding := 0;
  FCol := -1;
  FRow := -1;
end;

function TTyGridCell.GetStyleTypeKey: string;
begin
  Result := 'TyGridCell';   // has no themed rule today; transparent by design
end;

procedure TTyGridCell.SetPadding(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FPadding = AValue then Exit;
  FPadding := AValue;
  Realign;       // re-lay aligned children into the new padded rect
  Invalidate;
end;

procedure TTyGridCell.AdjustClientRect(var ARect: TRect);
var pad: Integer;
begin
  inherited AdjustClientRect(ARect);
  pad := MulDiv(FPadding, Font.PixelsPerInch, 96);
  Inc(ARect.Left, pad);
  Inc(ARect.Top, pad);
  Dec(ARect.Right, pad);
  Dec(ARect.Bottom, pad);
  if ARect.Right < ARect.Left then ARect.Right := ARect.Left;
  if ARect.Bottom < ARect.Top then ARect.Bottom := ARect.Top;
end;

procedure TTyGridCell.SetParent(AParent: TWinControl);
begin
  inherited SetParent(AParent);
  { Self-register with the hosting grid. Fires for grid-created cells, a designer
    drop, and a streamed load when Parent is applied — so the grid's cell list is
    rebuilt uniformly in all paths. Idempotent on the grid side. }
  if (AParent <> nil) and (AParent is TTyGridPanel) then
    TTyGridPanel(AParent).RegisterCell(Self);
end;

procedure TTyGridCell.Paint;
begin
  // Transparent: draw nothing at runtime. (Design-time grid lines are painted by
  // the parent TTyGridPanel, not per-cell.)
end;

initialization
  RegisterClass(TTyGridCell);
end.
