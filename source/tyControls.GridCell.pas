unit tyControls.GridCell;
{$mode objfpc}{$H+}

{ Compatibility re-export. TTyGridCell now lives in tyControls.GridPanel (same unit as
  TTyGridPanel) so the Lazarus designer, which adds the dropped grid's unit to the form's
  uses, brings the cell type along too — a separate unit made an IDE-dropped grid's
  auto-generated cell fields fail to compile. This unit stays only so existing code that
  `uses tyControls.GridCell` keeps working; new code can just use tyControls.GridPanel. }

interface

uses
  tyControls.GridPanel;

type
  TTyGridCell = tyControls.GridPanel.TTyGridCell;

implementation

end.
