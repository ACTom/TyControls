unit tyControls.MultiTrackBar;
{$mode objfpc}{$H+}

{ Track bars with more than one thumb (#36): the ordered thumb model shared by TTyRangeTrackBar
  (one or more ranges) and TTyMultiTrackBar (several values).

  TTyMultiTrackBarBase sits BESIDE TTyCustomTrackBar rather than under it: that class is built
  around a single Position. What the two share is the geometry (TyTrackThumbOffset /
  TyTrackPosFromOffset, TyTrackThumbLen, TyTrackSlideRect, TyTrackGrooveRect) and the tick band
  (TyLayoutTrackTicks / TyDrawTrackTicks), all unit-level in tyControls.TrackBar -- so a
  multi-thumb bar with one thumb at V draws exactly what a TTyTrackBar at Position V draws.

  The classes. TTyMultiTrackBarBase is the shared intermediate (as TTyGlyphButtonBase is for the
  glyph buttons): the model, the picture and the interaction, nothing published. Each final
  class has its custom class on it -- TTyCustomRangeTrackBar / TTyRangeTrackBar and
  TTyCustomMultiTrackBar / TTyMultiTrackBar -- which maps a collection onto the thumbs. }

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LCLIntf, LMessages,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller,
  tyControls.TrackBar;

const
  { The theme keys of the parts a multi-thumb bar draws on top of TTyTrackBar's groove and
    thumb. A range's span is LCL's selection range, so it is #37's key; a styled stretch
    between two thumbs of TTyMultiTrackBar is resolved as TyTrackSegment.<its StyleClass>. }
  TyTrackSelectionKey = 'TyTrackSelection';
  TyTrackSegmentKey = 'TyTrackSegment';

type
  { A thumb moved, or was selected; AIndex is its place in ThumbValues (-1 = none selected). }
  TTyTrackThumbEvent = procedure(Sender: TObject; AIndex: Integer) of object;

  { THE MODEL. The thumbs are an ordered array of integers, FValues, that always holds:

      ascending, FValues[i+1] - FValues[i] >= MinGap, every value within Min..Max.

    SetThumbValue is the one way a single thumb moves, from code, the mouse or the keyboard: it
    clamps the value between its neighbours (each +/- MinGap) and Min..Max, and fires
    OnThumbChange(Self, AIndex) and OnChange only when the value actually changed.

    Normalize puts an arbitrary array back into that shape -- sorted, then pushed apart left to
    right and, where that runs past Max, back from the right. It runs when Min, Max or MinGap
    change and when a form has been read (Loaded); while a form is being read nothing is
    clamped and no event fires, so the order the .lfm lists the values in does not matter.

    A MinGap the range cannot hold -- (ThumbCount - 1) * MinGap > Max - Min -- does not raise and
    is not rewritten: the thumbs are placed with (Max - Min) div (ThumbCount - 1) between them
    instead, and MinGap keeps the value it was given, so widening the range later brings the
    full gap back.

    THE PICTURE. Back to front: the groove (TyTrackGroove), the segments -- the stretches of
    groove between two thumbs that SegmentStyle names a theme key for -- then the thumbs
    (TyTrackThumb, each with its own hover / active state, StyleClass and Color), then the
    ticks and their labels. Segment I runs from the centre of thumb I - 1 to the centre of thumb
    I; segment 0 starts at the Min end of the groove and segment ThumbCount ends at its Max end.

    What each thumb and segment looks like, and whether a thumb takes part in the interaction,
    is the final class's data (its collection items): the protected virtual Thumb* and
    SegmentStyle functions below are where it hands that over. Here every thumb is enabled,
    follows the theme and has no hint, and no segment is drawn.

    THE INTERACTION (only enabled thumbs take part). A left press on a thumb selects it and
    drags it from where it was grabbed; a press on the groove brings the nearest thumb there
    (the lower value on a tie) and drags it on. A drag goes through SetThumbValue, so it stops
    MinGap short of a neighbour. The keyboard drives the selected thumb (none selected: the
    first enabled one), Tab / Shift+Tab step through the thumbs before leaving the control, and
    the hint over a thumb is that thumb's. Coming in from the keyboard starts at the near end:
    the first enabled thumb when entered forwards, the last when entered with Shift+Tab, so
    every thumb is one Tab away; entered by a click, the press picks the thumb. The wheel steps
    the thumb the keyboard drives by LineSize, up increasing, as TTyTrackBar's.

    No right-to-left mirroring, as TTyTrackBar: the value axis runs by Orientation and Reversed
    only. }
  TTyMultiTrackBarBase = class(TTyCustomControl)
  private
    FValues: array of Integer;
    FMin, FMax, FMinGap: Integer;
    FSelectedThumb: Integer;
    FOrientation: TTyTrackOrientation;
    FReversed: Boolean;
    FTickMarks: TTyTrackTickMark;
    FTickStyle: TTyTrackTickStyle;
    FManualTicks: array of Integer;
    FFrequency: Integer;
    FTickLabels: Boolean;
    FLineSize, FPageSize: Integer;
    { Where on the dragged thumb it was pressed, main-axis px from its centre. }
    FGrab: Integer;
    { The label strip's thickness on one tick side, measured at paint time and cached for
      CalculatePreferredSize (as TTyTrackBar does). }
    FTickLabelPx: Integer;
    FOnFormatTickLabel: TTyTrackTickLabelEvent;
    FOnThumbChange: TTyTrackThumbEvent;
    FOnThumbSelect: TTyTrackThumbEvent;
    FOnChange: TNotifyEvent;
    function GetThumbCount: Integer;
    function GetThumbValue(AIndex: Integer): Integer;
    procedure SetMin(const AValue: Integer);
    procedure SetMax(const AValue: Integer);
    procedure SetMinGap(const AValue: Integer);
    procedure SetSelectedThumb(AValue: Integer);
    procedure SetOrientation(const AValue: TTyTrackOrientation);
    procedure SetReversed(const AValue: Boolean);
    procedure SetTickMarks(const AValue: TTyTrackTickMark);
    procedure SetTickStyle(const AValue: TTyTrackTickStyle);
    procedure SetFrequency(const AValue: Integer);
    procedure SetTickLabels(const AValue: Boolean);
    procedure SetOnFormatTickLabel(const AValue: TTyTrackTickLabelEvent);
    procedure SetLineSize(const AValue: Integer);
    procedure SetPageSize(const AValue: Integer);
    procedure CheckIndex(AIndex: Integer);
  protected
    { The thumb under a press (drawn active) and under the pointer (drawn hover); -1 = none. }
    FDragThumb: Integer;
    FHoverThumb: Integer;
    function GetStyleTypeKey: string; override;
    { The gap the thumbs are actually placed with: MinGap, or the most the range can hold. }
    function EffectiveGap: Integer;
    { Bring FValues back to the invariant. AFire: report each thumb that moved
      (OnThumbChange) and then OnChange once; False while settling a freshly read form. }
    procedure Normalize(AFire: Boolean);
    { Replace the whole set of thumbs (the final classes' collections). Stored as given while the
      form is being read; otherwise normalized at once, and OnChange fires if the result differs
      from what was there. }
    procedure SetThumbValues(const AValues: array of Integer);
    { Called whenever the values may have changed -- a thumb moved, Normalize ran (a set was
      replaced, a form was read, Min / Max / MinGap changed) -- after FValues holds the new
      values and before any event fires: a final class copies them back into its collection
      items here, so the items always read what the thumbs show, from the event handlers too. }
    procedure ValuesChanged; virtual;
    procedure DoThumbChange(AIndex: Integer); virtual;
    procedure DoThumbSelect(AIndex: Integer); virtual;
    procedure DoChange; virtual;
    procedure Loaded; override;

    { ---- The final classes' data, per thumb and per segment. ---- }
    { False: the thumb is drawn as usual but cannot be pressed, dragged, selected or moved from
      the keyboard -- a press on it does nothing at all. }
    function ThumbEnabled(AIndex: Integer): Boolean; virtual;
    { clDefault = the theme's colour. Anything else replaces the background the theme resolves
      for that thumb (in every state): a thumb's colour is data, like a colour picker's value. }
    function ThumbColor(AIndex: Integer): TColor; virtual;
    { Resolved as TyTrackThumb.<class>; '' = plain TyTrackThumb. }
    function ThumbStyleClass(AIndex: Integer): string; virtual;
    { What the control's hint says while the pointer is over this thumb; '' = the control's own. }
    function ThumbHint(AIndex: Integer): string; virtual;
    { Segment AIndex (0..ThumbCount, see the class comment) is filled when this returns True,
      with the background ATypeKey.AStyleClass resolves to. }
    function SegmentStyle(AIndex: Integer; out ATypeKey, AStyleClass: string): Boolean; virtual;

    { The value axis runs the other way: vertical (Max at the top, as TTyTrackBar) xor Reversed. }
    function Inverted: Boolean;
    { Device px of the track along the main axis -- what TyTrackThumbOffset calls AMainLen. }
    function MainLen: Integer;
    { Where thumb AIndex's thumb starts along the track, device px from the track's start. }
    function ThumbOffset(AIndex: Integer): Integer;
    { The thumb's centre along the track, device px from the track's start. }
    function ThumbCentre(AIndex: Integer): Integer;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    { ---- Mouse and keyboard. ---- }
    { The thumb whose hit rectangle holds (X, Y) -- the nearest centre where two overlap, the
      lower value on a tie -- enabled or not; -1 = none. }
    function ThumbAt(X, Y: Integer): Integer;
    { The value under main-axis position APos (client px), as the thumb's centre would have it. }
    function ValueAt(APos: Integer): Integer;
    { The enabled thumb whose value is nearest AValue, the lower value on a tie; -1 = none. }
    function NearestEnabledThumb(AValue: Integer): Integer;
    { The thumb the keyboard drives: the selected one if it is enabled, else the first enabled
      thumb; -1 = none. }
    function KeyThumb: Integer;
    { The next enabled thumb after AFrom (before it, AForward = False); -1 = none. }
    function NextEnabledThumb(AFrom: Integer; AForward: Boolean): Integer;
    { The modifier keys and mouse buttons held now. CM_WANTSPECIALKEY and CM_ENTER carry none,
      so Shift+Tab is told from Tab, and a click from a key, by asking the keyboard and the
      mouse; virtual so a test can hold them without either. }
    function KeyShiftState: TShiftState; virtual;
    { Entered from the keyboard: the first enabled thumb (Shift held: the last) is selected,
      whatever was selected before -- a forward Tab that landed on the last thumb would
      otherwise leave again at once. Entered with a mouse button down: left to the press. }
    procedure DoEnter; override;
    { The wheel steps the thumb the keyboard drives (selecting it) by LineSize, wheel-up
      increasing, as TTyTrackBar's; an OnMouseWheel* handler that handles it stops the step. }
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    { Tab / Shift+Tab move between the enabled thumbs; the bar asks for the key only while
      there is a thumb to move to, so after the last (before the first) the form's own Tab
      handling takes the focus on. }
    procedure CMWantSpecialKey(var Message: TLMKey); message CM_WANTSPECIALKEY;
    { Over a thumb that has a hint, the hint is that thumb's; anywhere else the control's own. }
    procedure CMHintShow(var Message: TLMessage); message CM_HINTSHOW;
    { Cross axis only, as TTyTrackBar: the thumb, the ticks and their labels. }
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    { Move one thumb; see the class comment. Out-of-range AIndex raises EListError. }
    procedure SetThumbValue(AIndex, AValue: Integer);
    { Thumb AIndex's HIT rectangle in client coordinates: its length along the track, the whole
      control across it -- the same rectangle TTyTrackBar.ThumbRect gives at Position = its
      value, so a pointer anywhere in the thumb's column grabs it. }
    function ThumbRect(AIndex: Integer): TRect;
    { Segment AIndex's span along the track at APPI, in client coordinates of the main axis
      (low..high whichever way the bar runs). False for an index outside 0..ThumbCount. Says
      nothing about whether the segment is drawn -- that is SegmentStyle's call. }
    function SegmentSpan(AIndex, APPI: Integer; out ALow, AHigh: Integer): Boolean;
    { Place / drop hand-placed ticks, drawn while TickStyle = ttsManual; as TTyTrackBar. }
    procedure SetTick(AValue: Integer);
    procedure ClearTicks;
    function TickCount: Integer;
    property ThumbCount: Integer read GetThumbCount;
    { Read-only here: a thumb moves through SetThumbValue or the final class's collection. }
    property ThumbValues[AIndex: Integer]: Integer read GetThumbValue;
    { The thumb the keyboard acts on; -1 = none. Kept within 0..ThumbCount - 1. A change fires
      OnThumbSelect. }
    property SelectedThumb: Integer read FSelectedThumb write SetSelectedThumb default -1;
    property MinGap: Integer read FMinGap write SetMinGap default 0;
    property Min: Integer read FMin write SetMin default 0;
    property Max: Integer read FMax write SetMax default 100;
    property Orientation: TTyTrackOrientation read FOrientation write SetOrientation default toHorizontal;
    property Reversed: Boolean read FReversed write SetReversed default False;
    property TickMarks: TTyTrackTickMark read FTickMarks write SetTickMarks default ttmBottomRight;
    property TickStyle: TTyTrackTickStyle read FTickStyle write SetTickStyle default ttsAuto;
    property Frequency: Integer read FFrequency write SetFrequency default 1;
    property TickLabels: Boolean read FTickLabels write SetTickLabels default False;
    { The keyboard's steps, as TTyTrackBar's: arrows by LineSize, PageUp / PageDown by PageSize. }
    property LineSize: Integer read FLineSize write SetLineSize default 1;
    property PageSize: Integer read FPageSize write SetPageSize default 10;
    property OnFormatTickLabel: TTyTrackTickLabelEvent read FOnFormatTickLabel write SetOnFormatTickLabel;
    property TabStop default True;
    property OnThumbChange: TTyTrackThumbEvent read FOnThumbChange write FOnThumbChange;
    property OnThumbSelect: TTyTrackThumbEvent read FOnThumbSelect write FOnThumbSelect;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  TTyCustomRangeTrackBar = class;

  { One range of TTyRangeTrackBar: its two thumbs. Low and High read what the thumbs show; set
    them and the thumb moves through SetThumbValue -- the path a drag takes -- so it stops
    MinGap short of its neighbours and inside Min..Max, and OnThumbChange / OnChange fire.
    Between Ranges.BeginUpdate and EndUpdate, and while a form is read, the values are kept as
    given and the whole set is sorted out at EndUpdate / Loaded. A range added at the end takes
    the stretch after the last one, up to Max (Min..Max for the first). }
  TTyTrackRange = class(TCollectionItem)
  private
    FLow, FHigh: Integer;
    function Bar: TTyCustomRangeTrackBar;
    procedure SetLow(AValue: Integer);
    procedure SetHigh(AValue: Integer);
  public
    constructor Create(ACollection: TCollection); override;
    procedure Assign(Source: TPersistent); override;
  published
    property Low: Integer read FLow write SetLow;
    property High: Integer read FHigh write SetHigh;
  end;

  TTyTrackRanges = class(TOwnedCollection)
  private
    function GetItem(AIndex: Integer): TTyTrackRange;
    procedure SetItem(AIndex: Integer; AValue: TTyTrackRange);
  protected
    procedure Update(Item: TCollectionItem); override;
  public
    constructor Create(AOwner: TTyCustomRangeTrackBar);
    function Add: TTyTrackRange;
    property Items[AIndex: Integer]: TTyTrackRange read GetItem write SetItem; default;
  end;

  { One or more ranges on one track (#36). Each range is two thumbs, so the thumbs run
    [Low0, High0, Low1, High1, ...]: the ranges never overlap, and MinGap holds inside a range
    and between two of them alike. A form whose ranges are out of order, overlap or have
    Low > High is sorted when it has been read: the values are sorted as one list and paired
    off again. The span of each range is drawn as TTyTrackBar draws its selection
    (TyTrackSelection, centre of the Low thumb to centre of the High thumb); between two ranges
    the bare groove shows.

    A new bar has one range, 25..75, so a bar dropped on a form shows one. A bar whose ranges
    were all removed says so in its form file (NoRanges), or reading it back would bring that
    default range back: the reader adds to a collection without emptying it when the list it
    reads is empty. }
  TTyCustomRangeTrackBar = class(TTyMultiTrackBarBase)
  private
    FRanges: TTyTrackRanges;
    procedure SetRanges(AValue: TTyTrackRanges);
    function GetLowValue: Integer;
    procedure SetLowValue(AValue: Integer);
    function GetHighValue: Integer;
    procedure SetHighValue(AValue: Integer);
    procedure ReadNoRanges(Reader: TReader);
    procedure WriteNoRanges(Writer: TWriter);
  protected
    function GetStyleTypeKey: string; override;
    { True while a range's value is kept as given rather than moved through SetThumbValue: a
      form being read, Ranges between BeginUpdate and EndUpdate, the thumbs not (yet) the
      ranges' -- see TTyTrackRange. }
    function RangesHeldRaw: Boolean;
    { The collection changed shape (a range added, removed, moved, assigned): the thumbs are
      rebuilt from the ranges' values and normalized. }
    procedure RangesChanged;
    procedure ValuesChanged; override;
    procedure Loaded; override;
    procedure DefineProperties(Filer: TFiler); override;
    { The odd segments -- Low to High of each range -- in the selection's colour. }
    function SegmentStyle(AIndex: Integer; out ATypeKey, AStyleClass: string): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Ranges: TTyTrackRanges read FRanges write SetRanges;
    { The first range's ends. With no range they read 0, and setting one adds a range first. }
    property LowValue: Integer read GetLowValue write SetLowValue;
    property HighValue: Integer read GetHighValue write SetHighValue;
  end;

  TTyRangeTrackBar = class(TTyCustomRangeTrackBar)
  published
    property Version;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
    property TabOrder;
    property TabStop;
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
    property BorderWidth;
    property ChildSizing;
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
    property OnKeyDown;
    property OnKeyUp;
    property OnKeyPress;
    property OnUTF8KeyPress;
    property OnEnter;
    property OnExit;
    property OnEditingDone;
    property StyleClass;
    property StyleOverride;
    property Controller;
    property Min;
    property Max;
    property Orientation;
    property Reversed;
    property TickMarks;
    property TickStyle;
    property Frequency;
    property LineSize;
    property PageSize;
    property OnChange;
    property Align;
    property Anchors;
    property TickLabels;
    property OnFormatTickLabel;
    property MinGap;
    property Ranges;
    property OnThumbChange;
    property OnThumbSelect;
  end;

  TTyCustomMultiTrackBar = class;

  { One thumb of TTyMultiTrackBar. Value reads where the thumb is; set it and the thumb moves
    through SetThumbValue -- the path a drag takes -- so it stops MinGap short of its neighbours
    and inside Min..Max, and OnThumbChange / OnChange fire. Between Thumbs.BeginUpdate and
    EndUpdate, and while a form is read, values are kept as given; at EndUpdate / Loaded the
    thumbs are put in order by value, each keeping its Color, Hint, Enabled and StyleClass. A
    thumb added at the end starts at Max.

    Color: clDefault follows the theme; any other colour is the thumb's own (data, like a colour
    picker's value) and replaces the background the theme resolves for it in every state.
    Enabled False: drawn as usual, but it cannot be pressed, dragged, selected or moved from the
    keyboard. StyleClass: resolved as TyTrackThumb.<class>. Hint: the control's hint while the
    pointer is over this thumb. }
  TTyTrackThumbItem = class(TCollectionItem)
  private
    FValue: Integer;
    FColor: TColor;
    FHint: string;
    FEnabled: Boolean;
    FStyleClass: string;
    function Bar: TTyCustomMultiTrackBar;
    procedure SetValue(AValue: Integer);
    procedure SetColor(AValue: TColor);
    procedure SetHint(const AValue: string);
    procedure SetEnabled(AValue: Boolean);
    procedure SetStyleClass(const AValue: string);
  public
    constructor Create(ACollection: TCollection); override;
    procedure Assign(Source: TPersistent); override;
  published
    property Value: Integer read FValue write SetValue;
    property Color: TColor read FColor write SetColor default clDefault;
    property Hint: string read FHint write SetHint;
    property Enabled: Boolean read FEnabled write SetEnabled default True;
    property StyleClass: string read FStyleClass write SetStyleClass;
  end;

  TTyTrackThumbs = class(TOwnedCollection)
  private
    function GetItem(AIndex: Integer): TTyTrackThumbItem;
    procedure SetItem(AIndex: Integer; AValue: TTyTrackThumbItem);
  protected
    procedure Update(Item: TCollectionItem); override;
  public
    constructor Create(AOwner: TTyCustomMultiTrackBar);
    function Add: TTyTrackThumbItem;
    property Items[AIndex: Integer]: TTyTrackThumbItem read GetItem write SetItem; default;
  end;

  { How one stretch of groove between two thumbs is drawn: segment I runs from thumb I - 1 to
    thumb I (segment 0 from the Min end to the first thumb, the last one from the last thumb to
    the Max end). A StyleClass fills it with the background TyTrackSegment.<class> resolves to;
    '' -- or no item for that segment -- leaves the bare groove. }
  TTyTrackSegmentItem = class(TCollectionItem)
  private
    FStyleClass: string;
    procedure SetStyleClass(const AValue: string);
  public
    procedure Assign(Source: TPersistent); override;
  published
    property StyleClass: string read FStyleClass write SetStyleClass;
  end;

  TTyTrackSegments = class(TOwnedCollection)
  private
    function GetItem(AIndex: Integer): TTyTrackSegmentItem;
    procedure SetItem(AIndex: Integer; AValue: TTyTrackSegmentItem);
  protected
    procedure Update(Item: TCollectionItem); override;
  public
    constructor Create(AOwner: TTyCustomMultiTrackBar);
    function Add: TTyTrackSegmentItem;
    property Items[AIndex: Integer]: TTyTrackSegmentItem read GetItem write SetItem; default;
  end;

  { Several values on one track (#36), each thumb with its own colour, hint, enabled state and
    style class (Thumbs), and the stretches between them styled per segment (Segments). The
    items are the thumbs in order: Thumbs[i] is ThumbValues[i].

    A new bar has three thumbs, 25, 50 and 75, and no segment style. A bar whose thumbs were all
    removed says so in its form file (NoThumbs), or reading it back would bring the three back:
    the reader adds to a collection without emptying it when the list it reads is empty. }
  TTyCustomMultiTrackBar = class(TTyMultiTrackBarBase)
  private
    FThumbs: TTyTrackThumbs;
    FSegments: TTyTrackSegments;
    { Set while the items are being put in order and handed to the thumbs: the moves that makes
      report back through the collection and must not start it over. }
    FSyncing: Boolean;
    procedure SetThumbs(AValue: TTyTrackThumbs);
    procedure SetSegments(AValue: TTyTrackSegments);
    procedure ReadNoThumbs(Reader: TReader);
    procedure WriteNoThumbs(Writer: TWriter);
    { Stable insertion sort of the items by value. }
    procedure SortThumbItems;
    procedure PushThumbItems;
  protected
    function GetStyleTypeKey: string; override;
    { True while an item's value is kept as given rather than moved through SetThumbValue: a
      form being read, Thumbs between BeginUpdate and EndUpdate, the thumbs not (yet) the
      items' -- see TTyTrackThumbItem. }
    function ThumbsHeldRaw: Boolean;
    { The collection changed shape (a thumb added, removed, moved, assigned): the items are put
      in order by value and the thumbs rebuilt from them. }
    procedure ThumbsChanged;
    procedure ValuesChanged; override;
    procedure Loaded; override;
    procedure DefineProperties(Filer: TFiler); override;
    function ThumbEnabled(AIndex: Integer): Boolean; override;
    function ThumbColor(AIndex: Integer): TColor; override;
    function ThumbStyleClass(AIndex: Integer): string; override;
    function ThumbHint(AIndex: Integer): string; override;
    function SegmentStyle(AIndex: Integer; out ATypeKey, AStyleClass: string): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Thumbs: TTyTrackThumbs read FThumbs write SetThumbs;
    property Segments: TTyTrackSegments read FSegments write SetSegments;
  end;

  TTyMultiTrackBar = class(TTyCustomMultiTrackBar)
  published
    property Version;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
    property TabOrder;
    property TabStop;
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
    property BorderWidth;
    property ChildSizing;
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
    property OnKeyDown;
    property OnKeyUp;
    property OnKeyPress;
    property OnUTF8KeyPress;
    property OnEnter;
    property OnExit;
    property OnEditingDone;
    property StyleClass;
    property StyleOverride;
    property Controller;
    property Min;
    property Max;
    property Orientation;
    property Reversed;
    property TickMarks;
    property TickStyle;
    property Frequency;
    property LineSize;
    property PageSize;
    property OnChange;
    property Align;
    property Anchors;
    property TickLabels;
    property OnFormatTickLabel;
    property MinGap;
    property Thumbs;
    property Segments;
    property OnThumbChange;
    property OnThumbSelect;
  end;

implementation

uses
  tyControls.StyleModel;

{ TTyMultiTrackBarBase }

constructor TTyMultiTrackBarBase.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  FMin := 0;
  FMax := 100;
  FMinGap := 0;
  FSelectedThumb := -1;
  FDragThumb := -1;
  FHoverThumb := -1;
  FOrientation := toHorizontal;
  FTickMarks := ttmBottomRight;
  FTickStyle := ttsAuto;
  FFrequency := 1;
  FLineSize := 1;
  FPageSize := 10;
  Width := 160;
  Height := TyDensityHeight(ActiveController, 24);
end;

function TTyMultiTrackBarBase.GetStyleTypeKey: string;
begin
  { The final classes get keys of their own, parented to this one. }
  Result := 'TyTrackBar';
end;

function TTyMultiTrackBarBase.GetThumbCount: Integer;
begin
  Result := Length(FValues);
end;

procedure TTyMultiTrackBarBase.CheckIndex(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= Length(FValues)) then
    raise EListError.CreateFmt('%s: thumb index %d out of bounds (%d thumbs)',
      [ClassName, AIndex, Length(FValues)]);
end;

function TTyMultiTrackBarBase.GetThumbValue(AIndex: Integer): Integer;
begin
  CheckIndex(AIndex);
  Result := FValues[AIndex];
end;

function TTyMultiTrackBarBase.EffectiveGap: Integer;
var
  n: Integer;
  span: Int64;
begin
  Result := FMinGap;
  n := Length(FValues);
  if n < 2 then Exit;
  span := Int64(FMax) - FMin;
  if span < 0 then span := 0;
  if Int64(n - 1) * FMinGap > span then
    Result := span div (n - 1);
end;

procedure TTyMultiTrackBarBase.Normalize(AFire: Boolean);
var
  v, old: array of Integer;
  n, i, j, k, gap, lo, hi: Integer;
  moved: Boolean;
begin
  n := Length(FValues);
  if n = 0 then Exit;
  old := Copy(FValues);
  v := Copy(FValues);
  lo := FMin;
  hi := FMax;
  if hi < lo then hi := lo;       // a range set inside out holds every thumb at Min
  { Sorted: insertion sort, stable, linear on what is already in order. }
  for i := 1 to n - 1 do
  begin
    k := v[i];
    j := i - 1;
    while (j >= 0) and (v[j] > k) do
    begin
      v[j + 1] := v[j];
      Dec(j);
    end;
    v[j + 1] := k;
  end;
  gap := EffectiveGap;
  for i := 0 to n - 1 do
  begin
    if v[i] < lo then v[i] := lo;
    if v[i] > hi then v[i] := hi;
  end;
  { Pushed apart left to right ... }
  for i := 1 to n - 1 do
    if v[i] < v[i - 1] + gap then v[i] := v[i - 1] + gap;
  { ... and back from Max where that ran past it. (n - 1) * gap <= hi - lo, so the first thumb
    cannot be pushed below Min. }
  if v[n - 1] > hi then v[n - 1] := hi;
  for i := n - 2 downto 0 do
    if v[i] > v[i + 1] - gap then v[i] := v[i + 1] - gap;
  FValues := v;
  ValuesChanged;
  if not AFire then Exit;
  moved := False;
  for i := 0 to n - 1 do
    if v[i] <> old[i] then
    begin
      moved := True;
      DoThumbChange(i);
    end;
  if moved then
  begin
    Invalidate;
    DoChange;
  end;
end;

procedure TTyMultiTrackBarBase.SetThumbValues(const AValues: array of Integer);
var
  old: array of Integer;
  i: Integer;
  same: Boolean;
begin
  old := Copy(FValues);
  SetLength(FValues, Length(AValues));
  for i := 0 to High(AValues) do
    FValues[i] := AValues[i];
  if FDragThumb >= Length(FValues) then FDragThumb := -1;
  if FHoverThumb >= Length(FValues) then FHoverThumb := -1;
  if FSelectedThumb >= Length(FValues) then
  begin
    if csLoading in ComponentState then FSelectedThumb := -1
    else SetSelectedThumb(-1);
  end;
  if csLoading in ComponentState then Exit;
  Normalize(False);
  same := Length(old) = Length(FValues);
  if same then
    for i := 0 to High(old) do
      if old[i] <> FValues[i] then
      begin
        same := False;
        Break;
      end;
  if same then Exit;
  Invalidate;
  DoChange;
end;

procedure TTyMultiTrackBarBase.SetThumbValue(AIndex, AValue: Integer);
var
  lo, hi, gap, n: Integer;
begin
  CheckIndex(AIndex);
  { Reading a form: keep the value as listed; Loaded sorts it out. }
  if csLoading in ComponentState then
  begin
    FValues[AIndex] := AValue;
    Exit;
  end;
  n := Length(FValues);
  gap := EffectiveGap;
  lo := FMin;
  hi := FMax;
  if hi < lo then hi := lo;
  { Between both neighbours, each kept MinGap away. }
  if (AIndex > 0) and (FValues[AIndex - 1] + gap > lo) then lo := FValues[AIndex - 1] + gap;
  if (AIndex < n - 1) and (FValues[AIndex + 1] - gap < hi) then hi := FValues[AIndex + 1] - gap;
  if AValue > hi then AValue := hi;
  if AValue < lo then AValue := lo;
  if FValues[AIndex] = AValue then Exit;
  FValues[AIndex] := AValue;
  ValuesChanged;
  Invalidate;
  DoThumbChange(AIndex);
  DoChange;
end;

procedure TTyMultiTrackBarBase.ValuesChanged;
begin
end;

procedure TTyMultiTrackBarBase.DoThumbChange(AIndex: Integer);
begin
  if Assigned(FOnThumbChange) then FOnThumbChange(Self, AIndex);
end;

procedure TTyMultiTrackBarBase.DoThumbSelect(AIndex: Integer);
begin
  if Assigned(FOnThumbSelect) then FOnThumbSelect(Self, AIndex);
end;

procedure TTyMultiTrackBarBase.DoChange;
begin
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyMultiTrackBarBase.SetMin(const AValue: Integer);
begin
  if FMin = AValue then Exit;
  FMin := AValue;
  if csLoading in ComponentState then Exit;
  Normalize(True);
  Invalidate;
end;

procedure TTyMultiTrackBarBase.SetMax(const AValue: Integer);
begin
  if FMax = AValue then Exit;
  FMax := AValue;
  if csLoading in ComponentState then Exit;
  Normalize(True);
  Invalidate;
end;

procedure TTyMultiTrackBarBase.SetMinGap(const AValue: Integer);
var
  g: Integer;
begin
  if AValue < 0 then g := 0 else g := AValue;
  if FMinGap = g then Exit;
  FMinGap := g;
  if csLoading in ComponentState then Exit;
  Normalize(True);
  Invalidate;
end;

procedure TTyMultiTrackBarBase.SetSelectedThumb(AValue: Integer);
begin
  if (AValue < 0) or (AValue >= Length(FValues)) then AValue := -1;
  if FSelectedThumb = AValue then Exit;
  FSelectedThumb := AValue;
  Invalidate;
  if not (csLoading in ComponentState) then DoThumbSelect(AValue);
end;

procedure TTyMultiTrackBarBase.SetOrientation(const AValue: TTyTrackOrientation);
var
  w, h: Integer;
begin
  if FOrientation = AValue then Exit;
  FOrientation := AValue;
  { Swap the axis with the orientation, as TTyTrackBar (and LCL) do; not while reading a form,
    whose explicit bounds must win. }
  if not (csLoading in ComponentState) then
  begin
    w := Width; h := Height;
    if ((AValue = toVertical) and (w > h)) or ((AValue = toHorizontal) and (h > w)) then
      SetBounds(Left, Top, h, w);
  end;
  Invalidate;
end;

procedure TTyMultiTrackBarBase.SetReversed(const AValue: Boolean);
begin
  if FReversed = AValue then Exit;
  FReversed := AValue;
  Invalidate;
end;

procedure TTyMultiTrackBarBase.SetTickMarks(const AValue: TTyTrackTickMark);
begin
  if FTickMarks = AValue then Exit;
  FTickMarks := AValue;
  Invalidate;
end;

procedure TTyMultiTrackBarBase.SetTickStyle(const AValue: TTyTrackTickStyle);
begin
  if FTickStyle = AValue then Exit;
  FTickStyle := AValue;
  Invalidate;
end;

procedure TTyMultiTrackBarBase.SetFrequency(const AValue: Integer);
var
  f: Integer;
begin
  if AValue < 0 then f := 0 else f := AValue;
  if FFrequency = f then Exit;
  FFrequency := f;
  Invalidate;
end;

procedure TTyMultiTrackBarBase.SetTickLabels(const AValue: Boolean);
begin
  if FTickLabels = AValue then Exit;
  FTickLabels := AValue;
  if not FTickLabels then FTickLabelPx := 0;
  Invalidate;
end;

procedure TTyMultiTrackBarBase.SetOnFormatTickLabel(const AValue: TTyTrackTickLabelEvent);
begin
  FOnFormatTickLabel := AValue;
  if FTickLabels then Invalidate;
end;

procedure TTyMultiTrackBarBase.SetTick(AValue: Integer);
var
  i: Integer;
begin
  if (AValue < FMin) or (AValue > FMax) then Exit;
  for i := 0 to High(FManualTicks) do
    if FManualTicks[i] = AValue then Exit;
  SetLength(FManualTicks, Length(FManualTicks) + 1);
  FManualTicks[High(FManualTicks)] := AValue;
  if FTickStyle = ttsManual then Invalidate;
end;

procedure TTyMultiTrackBarBase.ClearTicks;
begin
  if Length(FManualTicks) = 0 then Exit;
  SetLength(FManualTicks, 0);
  if FTickStyle = ttsManual then Invalidate;
end;

function TTyMultiTrackBarBase.TickCount: Integer;
begin
  Result := Length(FManualTicks);
end;

procedure TTyMultiTrackBarBase.Loaded;
begin
  inherited Loaded;
  { The values arrive in whatever order the form file lists them, possibly before Min and Max:
    settle them now, silently -- reading a form is not the user moving a thumb. }
  Normalize(False);
  if FSelectedThumb >= Length(FValues) then FSelectedThumb := -1;
  Invalidate;
end;

function TTyMultiTrackBarBase.ThumbEnabled(AIndex: Integer): Boolean;
begin
  Result := True;
end;

function TTyMultiTrackBarBase.ThumbColor(AIndex: Integer): TColor;
begin
  Result := clDefault;
end;

function TTyMultiTrackBarBase.ThumbStyleClass(AIndex: Integer): string;
begin
  Result := '';
end;

function TTyMultiTrackBarBase.ThumbHint(AIndex: Integer): string;
begin
  Result := '';
end;

function TTyMultiTrackBarBase.SegmentStyle(AIndex: Integer; out ATypeKey,
  AStyleClass: string): Boolean;
begin
  ATypeKey := '';
  AStyleClass := '';
  Result := False;
end;

function TTyMultiTrackBarBase.Inverted: Boolean;
begin
  Result := (FOrientation = toVertical) xor FReversed;
end;

function TTyMultiTrackBarBase.MainLen: Integer;
begin
  if FOrientation = toVertical then Result := ClientHeight
  else Result := ClientWidth;
  if Result < 1 then Result := 1;
end;

function TTyMultiTrackBarBase.ThumbOffset(AIndex: Integer): Integer;
begin
  CheckIndex(AIndex);
  Result := TyTrackThumbOffset(MainLen, TyTrackThumbLen(Font.PixelsPerInch), FMin, FMax,
    FValues[AIndex], Inverted);
end;

function TTyMultiTrackBarBase.ThumbCentre(AIndex: Integer): Integer;
begin
  Result := ThumbOffset(AIndex) + TyTrackThumbLen(Font.PixelsPerInch) div 2;
end;

function TTyMultiTrackBarBase.ThumbRect(AIndex: Integer): TRect;
var
  TW, Off: Integer;
begin
  TW := TyTrackThumbLen(Font.PixelsPerInch);
  Off := ThumbOffset(AIndex);
  if FOrientation = toVertical then
    Result := Rect(0, Off, ClientWidth, Off + TW)
  else
    Result := Rect(Off, 0, Off + TW, ClientHeight);
end;

function TTyMultiTrackBarBase.SegmentSpan(AIndex, APPI: Integer; out ALow,
  AHigh: Integer): Boolean;
var
  TW, MLen, a, b, n: Integer;
begin
  ALow := 0;
  AHigh := 0;
  n := Length(FValues);
  Result := (AIndex >= 0) and (AIndex <= n);
  if not Result then Exit;
  TW := TyTrackThumbLen(APPI);
  MLen := MainLen;
  { Each end is a thumb's centre; segment 0 starts and segment n ends at the groove's end on
    the Min / Max side, whichever end of the control that is. }
  if AIndex = 0 then
  begin
    if Inverted then a := MLen else a := 0;
  end
  else
    a := TyTrackThumbOffset(MLen, TW, FMin, FMax, FValues[AIndex - 1], Inverted) + TW div 2;
  if AIndex = n then
  begin
    if Inverted then b := 0 else b := MLen;
  end
  else
    b := TyTrackThumbOffset(MLen, TW, FMin, FMax, FValues[AIndex], Inverted) + TW div 2;
  if a <= b then begin ALow := a; AHigh := b; end
  else begin ALow := b; AHigh := a; end;
end;

procedure TTyMultiTrackBarBase.CalculatePreferredSize(var PreferredWidth,
  PreferredHeight: Integer; WithThemeSpace: Boolean);
var
  S: TTyStyleSet;
  ppi, cross: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  { TTyTrackBar's sum, term by term: thumb, tick, label strip(s), padding. }
  cross := TyTrackThumbLen(ppi) + MulDiv(4, ppi, 96);
  if FTickLabels and (FTickLabelPx > 0) then
    if FTickMarks = ttmBoth then Inc(cross, 2 * FTickLabelPx)
    else Inc(cross, FTickLabelPx);
  Inc(cross, MulDiv(S.Padding.Top + S.Padding.Bottom, ppi, 96));
  if cross < 1 then cross := 1;
  if FOrientation = toVertical then
  begin
    PreferredWidth := cross;
    PreferredHeight := 0;
  end
  else
  begin
    PreferredWidth := 0;
    PreferredHeight := cross;
  end;
end;

procedure TTyMultiTrackBarBase.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, St: TTyStyleSet;
  R, SlideR, GrooveR, SegR, ThumbR: TRect;
  Ticks: TTyTrackTicks;
  TW, MLen, Off, i, n, lo, hi, topIdx: Integer;
  key, cls: string;
  c: TColor;

  procedure DrawThumb(AIndex: Integer);
  var
    States: TTyStateSet;
  begin
    Off := TyTrackThumbOffset(MLen, TW, FMin, FMax, FValues[AIndex], Inverted);
    if FOrientation = toVertical then
      ThumbR := Rect(SlideR.Left, SlideR.Top + Off, SlideR.Right, SlideR.Top + Off + TW)
    else
      ThumbR := Rect(SlideR.Left + Off, SlideR.Top, SlideR.Left + Off + TW, SlideR.Bottom);
    States := [];
    if AIndex = FDragThumb then Include(States, tysActive)
    else if AIndex = FHoverThumb then Include(States, tysHover)
    else Include(States, tysNormal);
    { The thumb the keyboard drives, while the control has the focus: a theme can mark it. }
    if Focused and (AIndex = FSelectedThumb) then Include(States, tysFocused);
    St := ActiveController.Model.ResolveStyle('TyTrackThumb', ThumbStyleClass(AIndex), States);
    c := ThumbColor(AIndex);
    if c <> clDefault then
    begin
      c := ColorToRGB(c);
      St.Background := Default(TTyFill);
      St.Background.Kind := tfkSolid;
      St.Background.Color := TyRGB(Red(c), Green(c), Blue(c));
      Include(St.Present, tpBackground);
    end;
    if tpBackground in St.Present then
      P.FillBackground(ThumbR, St.Background, St.BorderRadius);
  end;

begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);

    TW := TyTrackThumbLen(APPI);
    if FOrientation = toVertical then MLen := R.Bottom - R.Top
    else MLen := R.Right - R.Left;
    if MLen < 1 then MLen := 1;

    { The tick band: the same inputs TTyTrackBar hands the shared layout. }
    Ticks := Default(TTyTrackTicks);
    Ticks.Orientation := FOrientation;
    Ticks.TickMarks := FTickMarks;
    Ticks.TickStyle := FTickStyle;
    Ticks.Frequency := FFrequency;
    Ticks.Manual := FManualTicks;
    Ticks.Min := FMin;
    Ticks.Max := FMax;
    Ticks.Invert := Inverted;
    Ticks.MainLen := MLen;
    Ticks.ThumbLen := TW;
    Ticks.Labels := FTickLabels;
    Ticks.FontName := S.FontName;
    Ticks.FontSize := ResolveFontSize(S);
    Ticks.FontWeight := S.FontWeight;
    Ticks.Color := S.TextColor;
    Ticks.Sender := Self;
    Ticks.OnFormatLabel := FOnFormatTickLabel;
    TyLayoutTrackTicks(P, Ticks);
    FTickLabelPx := Ticks.LabelBand;
    SlideR := TyTrackSlideRect(R, FOrientation, FTickMarks, Ticks.TickBand + Ticks.LabelBand, 0);

    St := ActiveController.Model.ResolveStyle('TyTrackGroove', '', []);
    GrooveR := TyTrackGrooveRect(SlideR, FOrientation, MLen,
      TyTrackGrooveThickness(P, ActiveController));
    if tpBackground in St.Present then
      P.FillBackground(GrooveR, St.Background, St.BorderRadius);

    { The segments the final class names a style for, groove-thick, centre to centre. }
    n := Length(FValues);
    for i := 0 to n do
    begin
      if not SegmentStyle(i, key, cls) or (key = '') then Continue;
      SegmentSpan(i, APPI, lo, hi);
      if hi <= lo then Continue;
      St := ActiveController.Model.ResolveStyle(key, cls, []);
      if not (tpBackground in St.Present) then Continue;
      if FOrientation = toVertical then
        SegR := Rect(GrooveR.Left, SlideR.Top + lo, GrooveR.Right, SlideR.Top + hi)
      else
        SegR := Rect(SlideR.Left + lo, GrooveR.Top, SlideR.Left + hi, GrooveR.Bottom);
      P.FillBackground(SegR, St.Background, St.BorderRadius);
    end;

    { The thumbs in order, the one being dragged (else the selected one) last so it stays on
      top where two overlap. }
    topIdx := FDragThumb;
    if (topIdx < 0) or (topIdx >= n) then topIdx := FSelectedThumb;
    if topIdx >= n then topIdx := -1;
    for i := 0 to n - 1 do
      if i <> topIdx then DrawThumb(i);
    if topIdx >= 0 then DrawThumb(topIdx);

    TyDrawTrackTicks(P, R, Ticks);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyMultiTrackBarBase.SetLineSize(const AValue: Integer);
begin
  if AValue < 1 then FLineSize := 1 else FLineSize := AValue;
end;

procedure TTyMultiTrackBarBase.SetPageSize(const AValue: Integer);
begin
  if AValue < 1 then FPageSize := 1 else FPageSize := AValue;
end;

function TTyMultiTrackBarBase.ThumbAt(X, Y: Integer): Integer;
var
  i, pos, d, best: Integer;
  r: TRect;
begin
  Result := -1;
  best := High(Integer);
  if FOrientation = toVertical then pos := Y else pos := X;
  for i := 0 to High(FValues) do
  begin
    r := ThumbRect(i);
    if (X < r.Left) or (X >= r.Right) or (Y < r.Top) or (Y >= r.Bottom) then Continue;
    d := Abs(pos - ThumbCentre(i));
    if d < best then
    begin
      best := d;
      Result := i;
    end;
  end;
end;

function TTyMultiTrackBarBase.ValueAt(APos: Integer): Integer;
var
  TW: Integer;
begin
  TW := TyTrackThumbLen(Font.PixelsPerInch);
  Result := TyTrackPosFromOffset(MainLen, TW, FMin, FMax, APos - TW div 2, Inverted);
end;

function TTyMultiTrackBarBase.NearestEnabledThumb(AValue: Integer): Integer;
var
  i: Integer;
  d, best: Int64;
begin
  Result := -1;
  best := High(Int64);
  { Ascending values, a strict "<": on a tie the lower value -- met first -- keeps it. }
  for i := 0 to High(FValues) do
  begin
    if not ThumbEnabled(i) then Continue;
    d := Abs(Int64(FValues[i]) - AValue);
    if d < best then
    begin
      best := d;
      Result := i;
    end;
  end;
end;

function TTyMultiTrackBarBase.NextEnabledThumb(AFrom: Integer; AForward: Boolean): Integer;
var
  j: Integer;
begin
  Result := -1;
  if AFrom < 0 then Exit;
  j := AFrom;
  repeat
    if AForward then Inc(j) else Dec(j);
    if (j < 0) or (j > High(FValues)) then Exit;
  until ThumbEnabled(j);
  Result := j;
end;

function TTyMultiTrackBarBase.KeyThumb: Integer;
var
  i: Integer;
begin
  if (FSelectedThumb >= 0) and (FSelectedThumb < Length(FValues))
    and ThumbEnabled(FSelectedThumb) then
    Exit(FSelectedThumb);
  for i := 0 to High(FValues) do
    if ThumbEnabled(i) then Exit(i);
  Result := -1;
end;

function TTyMultiTrackBarBase.KeyShiftState: TShiftState;
begin
  Result := GetKeyShiftState;
  if GetKeyState(VK_LBUTTON) < 0 then Include(Result, ssLeft);
  if GetKeyState(VK_RBUTTON) < 0 then Include(Result, ssRight);
  if GetKeyState(VK_MBUTTON) < 0 then Include(Result, ssMiddle);
end;

procedure TTyMultiTrackBarBase.DoEnter;
var
  sh: TShiftState;
  i: Integer;
begin
  sh := KeyShiftState;
  if sh * [ssLeft, ssRight, ssMiddle] = [] then
  begin
    { The near end for the direction the focus came from: the last enabled thumb for
      Shift+Tab, else the first. }
    if ssShift in sh then
    begin
      i := High(FValues);
      while (i >= 0) and not ThumbEnabled(i) do Dec(i);
    end
    else
    begin
      i := 0;
      while (i <= High(FValues)) and not ThumbEnabled(i) do Inc(i);
      if i > High(FValues) then i := -1;
    end;
    if i >= 0 then SelectedThumb := i;
  end;
  inherited DoEnter;
end;

function TTyMultiTrackBarBase.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  i: Integer;
  v: Int64;
begin
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result or not Enabled then Exit;
  i := KeyThumb;
  if i < 0 then Exit;
  v := FValues[i];
  if WheelDelta > 0 then Inc(v, FLineSize)
  else if WheelDelta < 0 then Dec(v, FLineSize);
  if v > High(Integer) then v := High(Integer);
  if v < Low(Integer) then v := Low(Integer);
  SelectedThumb := i;
  SetThumbValue(i, v);
  Result := True;
end;

procedure TTyMultiTrackBarBase.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  idx, pos: Integer;
  onThumb: Boolean;
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  if FOrientation = toVertical then pos := Y else pos := X;
  idx := ThumbAt(X, Y);
  { A disabled thumb is inert: pressing it neither moves it nor picks another thumb. }
  if (idx >= 0) and not ThumbEnabled(idx) then Exit;
  onThumb := idx >= 0;
  if onThumb then
    { Grabbed where it was pressed: a press that does not move does not move the thumb. }
    FGrab := pos - ThumbCentre(idx)
  else
  begin
    { On the groove: the nearest enabled thumb comes to the pointer. }
    idx := NearestEnabledThumb(ValueAt(pos));
    if idx < 0 then Exit;
    FGrab := 0;
  end;
  FDragThumb := idx;
  FHoverThumb := -1;
  SelectedThumb := idx;
  if not onThumb then SetThumbValue(idx, ValueAt(pos));
  Invalidate;
end;

procedure TTyMultiTrackBarBase.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  pos, v, i, j, h: Integer;
begin
  if not Enabled then Exit;
  inherited MouseMove(Shift, X, Y);
  if FDragThumb >= 0 then
  begin
    if FOrientation = toVertical then pos := Y else pos := X;
    v := ValueAt(pos - FGrab);
    i := FDragThumb;
    { Thumbs on the same value (MinGap 0) are told apart by the direction of the drag: the one
      that can go that way takes over, or a pile at Min / Max could never be pulled apart. }
    j := i;
    if v > FValues[i] then
      while (j < High(FValues)) and (FValues[j + 1] = FValues[i]) and ThumbEnabled(j + 1) do Inc(j)
    else if v < FValues[i] then
      while (j > 0) and (FValues[j - 1] = FValues[i]) and ThumbEnabled(j - 1) do Dec(j);
    if j <> i then
    begin
      FDragThumb := j;
      SelectedThumb := j;
    end;
    SetThumbValue(FDragThumb, v);
    Invalidate;
  end
  else
  begin
    h := ThumbAt(X, Y);
    if (h >= 0) and not ThumbEnabled(h) then h := -1;
    if h <> FHoverThumb then
    begin
      FHoverThumb := h;
      Invalidate;
    end;
  end;
end;

procedure TTyMultiTrackBarBase.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDragThumb := -1;
    Invalidate;
  end;
end;

procedure TTyMultiTrackBarBase.MouseLeave;
begin
  inherited MouseLeave;
  { A drag goes on until the button is released, as TTyTrackBar's. }
  FHoverThumb := -1;
  Invalidate;
end;

procedure TTyMultiTrackBarBase.KeyDown(var Key: Word; Shift: TShiftState);
var
  i, nxt: Integer;
  v: Int64;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  if (Key = VK_TAB) and (Shift - [ssShift] = []) then
  begin
    nxt := NextEnabledThumb(KeyThumb, not (ssShift in Shift));
    if nxt >= 0 then
    begin
      SelectedThumb := nxt;
      Key := 0;
    end;
    Exit;
  end;
  i := KeyThumb;
  if i < 0 then Exit;
  { Value keys, as TTyTrackBar's: up / right increase whichever way the bar runs, so on a
    vertical bar "up increases"; Home / End go as far as the neighbours let. }
  case Key of
    VK_RIGHT, VK_UP: v := Int64(FValues[i]) + FLineSize;
    VK_LEFT, VK_DOWN: v := Int64(FValues[i]) - FLineSize;
    VK_PRIOR: v := Int64(FValues[i]) + FPageSize;
    VK_NEXT: v := Int64(FValues[i]) - FPageSize;
    VK_HOME: v := FMin;
    VK_END: v := FMax;
  else
    Exit;
  end;
  Key := 0;
  if v > High(Integer) then v := High(Integer);
  if v < Low(Integer) then v := Low(Integer);
  SelectedThumb := i;
  SetThumbValue(i, v);
end;

procedure TTyMultiTrackBarBase.CMWantSpecialKey(var Message: TLMKey);
var
  sh: TShiftState;
begin
  if (Message.CharCode = VK_TAB) and Enabled then
  begin
    sh := KeyShiftState;
    if (sh * [ssCtrl, ssAlt, ssMeta] = []) and (NextEnabledThumb(KeyThumb, not (ssShift in sh)) >= 0) then
    begin
      Message.Result := 1;
      Exit;
    end;
  end;
  inherited;
end;

procedure TTyMultiTrackBarBase.CMHintShow(var Message: TLMessage);
var
  info: PHintInfo;
  i, idx, pos, lo, hi, s, e: Integer;
  any: Boolean;
  r: TRect;
begin
  info := PHintInfo(Message.LParam);
  any := False;
  for i := 0 to High(FValues) do
    if ThumbHint(i) <> '' then
    begin
      any := True;
      Break;
    end;
  if (info = nil) or not any then
  begin
    inherited;
    Exit;
  end;
  idx := ThumbAt(info^.CursorPos.X, info^.CursorPos.Y);
  if idx >= 0 then
  begin
    if ThumbHint(idx) <> '' then info^.HintStr := ThumbHint(idx);
    { Leaving the thumb asks again. }
    info^.CursorRect := ThumbRect(idx);
  end
  else
  begin
    { Between two thumbs: the gap, so reaching either thumb asks again. }
    if FOrientation = toVertical then pos := info^.CursorPos.Y else pos := info^.CursorPos.X;
    lo := 0;
    hi := MainLen;
    for i := 0 to High(FValues) do
    begin
      r := ThumbRect(i);
      if FOrientation = toVertical then begin s := r.Top; e := r.Bottom; end
      else begin s := r.Left; e := r.Right; end;
      if (e <= pos) and (e > lo) then lo := e;
      if (s > pos) and (s < hi) then hi := s;
    end;
    if FOrientation = toVertical then info^.CursorRect := Rect(0, lo, ClientWidth, hi)
    else info^.CursorRect := Rect(lo, 0, hi, ClientHeight);
  end;
  inherited;
end;

procedure TTyMultiTrackBarBase.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

{ TTyTrackRange }

constructor TTyTrackRange.Create(ACollection: TCollection);
var
  b: TTyCustomRangeTrackBar;
begin
  { Before inherited: adding the item tells the bar, which reads the new range's values. A
    range added at the end takes the stretch after the last range: from its High (from Min
    for the first range) to Max, so either end can then be set where it is wanted. }
  if (ACollection is TTyTrackRanges)
     and (TTyTrackRanges(ACollection).Owner is TTyCustomRangeTrackBar) then
  begin
    b := TTyCustomRangeTrackBar(TTyTrackRanges(ACollection).Owner);
    if ACollection.Count > 0 then FLow := TTyTrackRanges(ACollection)[ACollection.Count - 1].FHigh
    else FLow := b.Min;
    FHigh := b.Max;
  end;
  inherited Create(ACollection);
end;

function TTyTrackRange.Bar: TTyCustomRangeTrackBar;
begin
  Result := nil;
  if (Collection is TTyTrackRanges) and (TTyTrackRanges(Collection).Owner is TTyCustomRangeTrackBar) then
    Result := TTyCustomRangeTrackBar(TTyTrackRanges(Collection).Owner);
end;

procedure TTyTrackRange.SetLow(AValue: Integer);
var
  b: TTyCustomRangeTrackBar;
begin
  b := Bar;
  if (b = nil) or b.RangesHeldRaw then FLow := AValue
  else b.SetThumbValue(2 * Index, AValue);       // ValuesChanged writes FLow back
end;

procedure TTyTrackRange.SetHigh(AValue: Integer);
var
  b: TTyCustomRangeTrackBar;
begin
  b := Bar;
  if (b = nil) or b.RangesHeldRaw then FHigh := AValue
  else b.SetThumbValue(2 * Index + 1, AValue);
end;

procedure TTyTrackRange.Assign(Source: TPersistent);
begin
  if Source is TTyTrackRange then
  begin
    FLow := TTyTrackRange(Source).FLow;
    FHigh := TTyTrackRange(Source).FHigh;
    Changed(True);
  end
  else
    inherited Assign(Source);
end;

{ TTyTrackRanges }

constructor TTyTrackRanges.Create(AOwner: TTyCustomRangeTrackBar);
begin
  inherited Create(AOwner, TTyTrackRange);
end;

function TTyTrackRanges.GetItem(AIndex: Integer): TTyTrackRange;
begin
  Result := TTyTrackRange(inherited Items[AIndex]);
end;

procedure TTyTrackRanges.SetItem(AIndex: Integer; AValue: TTyTrackRange);
begin
  inherited Items[AIndex] := AValue;
end;

function TTyTrackRanges.Add: TTyTrackRange;
begin
  Result := TTyTrackRange(inherited Add);
end;

procedure TTyTrackRanges.Update(Item: TCollectionItem);
begin
  inherited Update(Item);
  if Owner is TTyCustomRangeTrackBar then
    TTyCustomRangeTrackBar(Owner).RangesChanged;
end;

{ TTyCustomRangeTrackBar }

constructor TTyCustomRangeTrackBar.Create(AOwner: TComponent);
var
  r: TTyTrackRange;
begin
  inherited Create(AOwner);
  FRanges := TTyTrackRanges.Create(Self);
  FRanges.BeginUpdate;
  try
    r := FRanges.Add;
    r.FLow := 25;
    r.FHigh := 75;
  finally
    FRanges.EndUpdate;
  end;
end;

destructor TTyCustomRangeTrackBar.Destroy;
begin
  FreeAndNil(FRanges);
  inherited Destroy;
end;

function TTyCustomRangeTrackBar.GetStyleTypeKey: string;
begin
  Result := 'TyRangeTrackBar';
end;

procedure TTyCustomRangeTrackBar.SetRanges(AValue: TTyTrackRanges);
begin
  FRanges.Assign(AValue);
end;

function TTyCustomRangeTrackBar.RangesHeldRaw: Boolean;
begin
  Result := (csLoading in ComponentState) or (FRanges = nil) or (FRanges.UpdateCount > 0)
    or (ThumbCount <> 2 * FRanges.Count);
end;

procedure TTyCustomRangeTrackBar.RangesChanged;
var
  v: array of Integer;
  i: Integer;
begin
  if (FRanges = nil) or (csLoading in ComponentState) or (csDestroying in ComponentState) then
    Exit;
  v := nil;
  SetLength(v, 2 * FRanges.Count);
  for i := 0 to FRanges.Count - 1 do
  begin
    v[2 * i] := FRanges[i].FLow;
    v[2 * i + 1] := FRanges[i].FHigh;
  end;
  SetThumbValues(v);
end;

procedure TTyCustomRangeTrackBar.ValuesChanged;
var
  i: Integer;
begin
  inherited ValuesChanged;
  if (FRanges = nil) or (ThumbCount <> 2 * FRanges.Count) then Exit;
  for i := 0 to FRanges.Count - 1 do
  begin
    FRanges[i].FLow := ThumbValues[2 * i];
    FRanges[i].FHigh := ThumbValues[2 * i + 1];
  end;
end;

procedure TTyCustomRangeTrackBar.Loaded;
var
  v: array of Integer;
  i: Integer;
begin
  { Still loading: the ranges' values are handed over as read; inherited Loaded sorts them. }
  v := nil;
  SetLength(v, 2 * FRanges.Count);
  for i := 0 to FRanges.Count - 1 do
  begin
    v[2 * i] := FRanges[i].FLow;
    v[2 * i + 1] := FRanges[i].FHigh;
  end;
  SetThumbValues(v);
  inherited Loaded;
end;

procedure TTyCustomRangeTrackBar.ReadNoRanges(Reader: TReader);
begin
  if Reader.ReadBoolean then FRanges.Clear;
end;

procedure TTyCustomRangeTrackBar.WriteNoRanges(Writer: TWriter);
begin
  Writer.WriteBoolean(True);
end;

procedure TTyCustomRangeTrackBar.DefineProperties(Filer: TFiler);

  function NoneLeft: Boolean;
  begin
    Result := FRanges.Count = 0;
    { An inherited form: only when the ancestor still had ranges. }
    if Result and (Filer.Ancestor is TTyCustomRangeTrackBar) then
      Result := TTyCustomRangeTrackBar(Filer.Ancestor).FRanges.Count > 0;
  end;

begin
  inherited DefineProperties(Filer);
  Filer.DefineProperty('NoRanges', @ReadNoRanges, @WriteNoRanges, NoneLeft);
end;

function TTyCustomRangeTrackBar.SegmentStyle(AIndex: Integer; out ATypeKey,
  AStyleClass: string): Boolean;
begin
  Result := inherited SegmentStyle(AIndex, ATypeKey, AStyleClass);
  if Odd(AIndex) and (AIndex < ThumbCount) then
  begin
    ATypeKey := TyTrackSelectionKey;
    AStyleClass := '';
    Result := True;
  end;
end;

function TTyCustomRangeTrackBar.GetLowValue: Integer;
begin
  if FRanges.Count = 0 then Result := 0
  else Result := FRanges[0].Low;
end;

procedure TTyCustomRangeTrackBar.SetLowValue(AValue: Integer);
begin
  if FRanges.Count = 0 then FRanges.Add;
  FRanges[0].Low := AValue;
end;

function TTyCustomRangeTrackBar.GetHighValue: Integer;
begin
  if FRanges.Count = 0 then Result := 0
  else Result := FRanges[0].High;
end;

procedure TTyCustomRangeTrackBar.SetHighValue(AValue: Integer);
begin
  if FRanges.Count = 0 then FRanges.Add;
  FRanges[0].High := AValue;
end;

{ TTyTrackThumbItem }

constructor TTyTrackThumbItem.Create(ACollection: TCollection);
begin
  { Before inherited: adding the item tells the bar, which reads the new thumb's value. A thumb
    added at the end starts at Max, after every thumb there is. }
  FColor := clDefault;
  FEnabled := True;
  if (ACollection is TTyTrackThumbs)
     and (TTyTrackThumbs(ACollection).Owner is TTyCustomMultiTrackBar) then
    FValue := TTyCustomMultiTrackBar(TTyTrackThumbs(ACollection).Owner).Max;
  inherited Create(ACollection);
end;

function TTyTrackThumbItem.Bar: TTyCustomMultiTrackBar;
begin
  Result := nil;
  if (Collection is TTyTrackThumbs) and (TTyTrackThumbs(Collection).Owner is TTyCustomMultiTrackBar) then
    Result := TTyCustomMultiTrackBar(TTyTrackThumbs(Collection).Owner);
end;

procedure TTyTrackThumbItem.SetValue(AValue: Integer);
var
  b: TTyCustomMultiTrackBar;
begin
  b := Bar;
  if (b = nil) or b.ThumbsHeldRaw then FValue := AValue
  else b.SetThumbValue(Index, AValue);           // ValuesChanged writes FValue back
end;

procedure TTyTrackThumbItem.SetColor(AValue: TColor);
begin
  if FColor = AValue then Exit;
  FColor := AValue;
  Changed(False);
end;

procedure TTyTrackThumbItem.SetHint(const AValue: string);
begin
  if FHint = AValue then Exit;
  FHint := AValue;
  Changed(False);
end;

procedure TTyTrackThumbItem.SetEnabled(AValue: Boolean);
begin
  if FEnabled = AValue then Exit;
  FEnabled := AValue;
  Changed(False);
end;

procedure TTyTrackThumbItem.SetStyleClass(const AValue: string);
begin
  if FStyleClass = AValue then Exit;
  FStyleClass := AValue;
  Changed(False);
end;

procedure TTyTrackThumbItem.Assign(Source: TPersistent);
var
  src: TTyTrackThumbItem;
begin
  if Source is TTyTrackThumbItem then
  begin
    src := TTyTrackThumbItem(Source);
    FValue := src.FValue;
    FColor := src.FColor;
    FHint := src.FHint;
    FEnabled := src.FEnabled;
    FStyleClass := src.FStyleClass;
    Changed(True);
  end
  else
    inherited Assign(Source);
end;

{ TTyTrackThumbs }

constructor TTyTrackThumbs.Create(AOwner: TTyCustomMultiTrackBar);
begin
  inherited Create(AOwner, TTyTrackThumbItem);
end;

function TTyTrackThumbs.GetItem(AIndex: Integer): TTyTrackThumbItem;
begin
  Result := TTyTrackThumbItem(inherited Items[AIndex]);
end;

procedure TTyTrackThumbs.SetItem(AIndex: Integer; AValue: TTyTrackThumbItem);
begin
  inherited Items[AIndex] := AValue;
end;

function TTyTrackThumbs.Add: TTyTrackThumbItem;
begin
  Result := TTyTrackThumbItem(inherited Add);
end;

procedure TTyTrackThumbs.Update(Item: TCollectionItem);
begin
  inherited Update(Item);
  if not (Owner is TTyCustomMultiTrackBar) then Exit;
  { One item's look changed: repaint. The collection changed shape: rebuild the thumbs. }
  if Item <> nil then TTyCustomMultiTrackBar(Owner).Invalidate
  else TTyCustomMultiTrackBar(Owner).ThumbsChanged;
end;

{ TTyTrackSegmentItem }

procedure TTyTrackSegmentItem.SetStyleClass(const AValue: string);
begin
  if FStyleClass = AValue then Exit;
  FStyleClass := AValue;
  Changed(False);
end;

procedure TTyTrackSegmentItem.Assign(Source: TPersistent);
begin
  if Source is TTyTrackSegmentItem then
  begin
    FStyleClass := TTyTrackSegmentItem(Source).FStyleClass;
    Changed(False);
  end
  else
    inherited Assign(Source);
end;

{ TTyTrackSegments }

constructor TTyTrackSegments.Create(AOwner: TTyCustomMultiTrackBar);
begin
  inherited Create(AOwner, TTyTrackSegmentItem);
end;

function TTyTrackSegments.GetItem(AIndex: Integer): TTyTrackSegmentItem;
begin
  Result := TTyTrackSegmentItem(inherited Items[AIndex]);
end;

procedure TTyTrackSegments.SetItem(AIndex: Integer; AValue: TTyTrackSegmentItem);
begin
  inherited Items[AIndex] := AValue;
end;

function TTyTrackSegments.Add: TTyTrackSegmentItem;
begin
  Result := TTyTrackSegmentItem(inherited Add);
end;

procedure TTyTrackSegments.Update(Item: TCollectionItem);
begin
  inherited Update(Item);
  if Owner is TTyCustomMultiTrackBar then
    TTyCustomMultiTrackBar(Owner).Invalidate;
end;

{ TTyCustomMultiTrackBar }

constructor TTyCustomMultiTrackBar.Create(AOwner: TComponent);
const
  CDefaults: array[0..2] of Integer = (25, 50, 75);
var
  i: Integer;
begin
  inherited Create(AOwner);
  FSegments := TTyTrackSegments.Create(Self);
  FThumbs := TTyTrackThumbs.Create(Self);
  FThumbs.BeginUpdate;
  try
    for i := 0 to High(CDefaults) do
      FThumbs.Add.FValue := CDefaults[i];
  finally
    FThumbs.EndUpdate;
  end;
end;

destructor TTyCustomMultiTrackBar.Destroy;
begin
  FreeAndNil(FThumbs);
  FreeAndNil(FSegments);
  inherited Destroy;
end;

function TTyCustomMultiTrackBar.GetStyleTypeKey: string;
begin
  Result := 'TyMultiTrackBar';
end;

procedure TTyCustomMultiTrackBar.SetThumbs(AValue: TTyTrackThumbs);
begin
  FThumbs.Assign(AValue);
end;

procedure TTyCustomMultiTrackBar.SetSegments(AValue: TTyTrackSegments);
begin
  FSegments.Assign(AValue);
end;

function TTyCustomMultiTrackBar.ThumbsHeldRaw: Boolean;
begin
  Result := (csLoading in ComponentState) or (FThumbs = nil) or (FThumbs.UpdateCount > 0)
    or FSyncing or (ThumbCount <> FThumbs.Count);
end;

procedure TTyCustomMultiTrackBar.SortThumbItems;
var
  i, j: Integer;
  it: TTyTrackThumbItem;
begin
  for i := 1 to FThumbs.Count - 1 do
  begin
    it := FThumbs[i];
    j := i;
    while (j > 0) and (FThumbs[j - 1].FValue > it.FValue) do Dec(j);
    if j <> i then it.Index := j;
  end;
end;

procedure TTyCustomMultiTrackBar.PushThumbItems;
var
  v: array of Integer;
  i: Integer;
begin
  v := nil;
  SetLength(v, FThumbs.Count);
  for i := 0 to FThumbs.Count - 1 do
    v[i] := FThumbs[i].FValue;
  SetThumbValues(v);
end;

procedure TTyCustomMultiTrackBar.ThumbsChanged;
begin
  if (FThumbs = nil) or FSyncing or (csLoading in ComponentState)
     or (csDestroying in ComponentState) then
    Exit;
  FSyncing := True;
  try
    { In order first, so each thumb's colour, hint and class stay with its value. }
    SortThumbItems;
    PushThumbItems;
  finally
    FSyncing := False;
  end;
end;

procedure TTyCustomMultiTrackBar.ValuesChanged;
var
  i: Integer;
begin
  inherited ValuesChanged;
  if (FThumbs = nil) or (ThumbCount <> FThumbs.Count) then Exit;
  for i := 0 to FThumbs.Count - 1 do
    FThumbs[i].FValue := ThumbValues[i];
end;

procedure TTyCustomMultiTrackBar.Loaded;
begin
  { Still loading: the items as read, put in order, are handed over; inherited Loaded settles
    the values. }
  FSyncing := True;
  try
    SortThumbItems;
    PushThumbItems;
  finally
    FSyncing := False;
  end;
  inherited Loaded;
end;

procedure TTyCustomMultiTrackBar.ReadNoThumbs(Reader: TReader);
begin
  if Reader.ReadBoolean then FThumbs.Clear;
end;

procedure TTyCustomMultiTrackBar.WriteNoThumbs(Writer: TWriter);
begin
  Writer.WriteBoolean(True);
end;

procedure TTyCustomMultiTrackBar.DefineProperties(Filer: TFiler);

  function NoneLeft: Boolean;
  begin
    Result := FThumbs.Count = 0;
    { An inherited form: only when the ancestor still had thumbs. }
    if Result and (Filer.Ancestor is TTyCustomMultiTrackBar) then
      Result := TTyCustomMultiTrackBar(Filer.Ancestor).FThumbs.Count > 0;
  end;

begin
  inherited DefineProperties(Filer);
  Filer.DefineProperty('NoThumbs', @ReadNoThumbs, @WriteNoThumbs, NoneLeft);
end;

function TTyCustomMultiTrackBar.ThumbEnabled(AIndex: Integer): Boolean;
begin
  if (FThumbs <> nil) and (AIndex >= 0) and (AIndex < FThumbs.Count) then
    Result := FThumbs[AIndex].Enabled
  else
    Result := inherited ThumbEnabled(AIndex);
end;

function TTyCustomMultiTrackBar.ThumbColor(AIndex: Integer): TColor;
begin
  if (FThumbs <> nil) and (AIndex >= 0) and (AIndex < FThumbs.Count) then
    Result := FThumbs[AIndex].Color
  else
    Result := inherited ThumbColor(AIndex);
end;

function TTyCustomMultiTrackBar.ThumbStyleClass(AIndex: Integer): string;
begin
  if (FThumbs <> nil) and (AIndex >= 0) and (AIndex < FThumbs.Count) then
    Result := FThumbs[AIndex].StyleClass
  else
    Result := inherited ThumbStyleClass(AIndex);
end;

function TTyCustomMultiTrackBar.ThumbHint(AIndex: Integer): string;
begin
  if (FThumbs <> nil) and (AIndex >= 0) and (AIndex < FThumbs.Count) then
    Result := FThumbs[AIndex].Hint
  else
    Result := inherited ThumbHint(AIndex);
end;

function TTyCustomMultiTrackBar.SegmentStyle(AIndex: Integer; out ATypeKey,
  AStyleClass: string): Boolean;
begin
  Result := inherited SegmentStyle(AIndex, ATypeKey, AStyleClass);
  if (FSegments <> nil) and (AIndex >= 0) and (AIndex < FSegments.Count)
     and (FSegments[AIndex].StyleClass <> '') then
  begin
    ATypeKey := TyTrackSegmentKey;
    AStyleClass := FSegments[AIndex].StyleClass;
    Result := True;
  end;
end;

initialization
  { The final classes' keys fall back to the track bar's, so every theme styles them as it
    styles TTyTrackBar until it says otherwise. }
  TyTryRegisterTypeKeyParent('TyRangeTrackBar', 'TyTrackBar');
  TyTryRegisterTypeKeyParent('TyMultiTrackBar', 'TyTrackBar');

finalization
  TyUnregisterTypeKeyParent('TyRangeTrackBar');
  TyUnregisterTypeKeyParent('TyMultiTrackBar');

end.
