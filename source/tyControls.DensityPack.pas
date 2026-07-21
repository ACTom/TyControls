unit tyControls.DensityPack;

{ 现代密度包(密度尺度第四期)。**只覆盖几何令牌,一个颜色都没有** ——
  所以它对任何皮肤都成立(经典皮肤 + 现代密度 = 那个皮肤的观感、Web 的疏密)。
  由 TTyStyleController.Density := tdModern 追加叠加到当前主题之上。

  经典 = 什么都不叠(各皮肤/light.tycss 的现值即经典)。这里只有现代那一份。

  取值是**首版**,按类别定(不是等比放大):字号定层级、内距走 4px 尺度、
  高度 ×1.4、图标槽 ×1.25、大布局宽 ×1.2。真机观感需要人眼再调 ——
  这正是把不确定性集中到这一层的原因。 }

{$mode objfpc}{$H+}

interface

function TyDensityModernCss: string;

implementation

uses
  SysUtils;

function TyDensityModernCss: string;
begin
  Result :=
    ':root {' + LineEnding +
    '  --row-height: 32px;' + LineEnding +
    '  --header-height: 36px;' + LineEnding +
    '  --item-height: 32px;' + LineEnding +
    '  --icon-size: 20px;' + LineEnding +
    '  --radius: 8px;' + LineEnding +
    '  --radius-pill: 12px;' + LineEnding +
    '  --radius-round: 16px;' + LineEnding +
    '  --radius-scroll: 6px;' + LineEnding +
    '  --alert-close-gap: 12px;' + LineEnding +
    '  --alert-close-size: 18px;' + LineEnding +
    '  --alert-icon-gap: 10px;' + LineEnding +
    '  --alert-icon-size: 20px;' + LineEnding +
    '  --alert-text-gap: 4px;' + LineEnding +
    '  --backstage-back-height: 67px;' + LineEnding +
    '  --backstage-icon-size: 22px;' + LineEnding +
    '  --backstage-icon-x: 18px;' + LineEnding +
    '  --backstage-row-height: 59px;' + LineEnding +
    '  --backstage-sidebar-width: 228px;' + LineEnding +
    '  --backstage-text-inset: 64px;' + LineEnding +
    '  --badge-dot-size: 10px;' + LineEnding +
    '  --badge-inset: 4px;' + LineEnding +
    '  --breadcrumb-separator-gap: 4px;' + LineEnding +
    '  --breadcrumb-separator-size: 18px;' + LineEnding +
    '  --caption-button-width: 64px;' + LineEnding +
    '  --card-actions-height: 62px;' + LineEnding +
    '  --card-header-height: 50px;' + LineEnding +
    '  --cascader-column-width: 144px;' + LineEnding +
    '  --cascader-expand-gap: 6px;' + LineEnding +
    '  --cascader-expand-size: 16px;' + LineEnding +
    '  --cascader-row-height: 34px;' + LineEnding +
    '  --chart-tooltip-gap: 16px;' + LineEnding +
    '  --chart-tooltip-swatch-gap: 7px;' + LineEnding +
    '  --chart-tooltip-swatch: 10px;' + LineEnding +
    '  --checkbox-gap: 8px;' + LineEnding +
    '  --checkbox-size: 20px;' + LineEnding +
    '  --control-height: 38px;' + LineEnding +
    '  --dialog-edit-width: 384px;' + LineEnding +
    '  --dialog-padding: 26px;' + LineEnding +
    '  --drop-arrow-width: 25px;' + LineEnding +
    '  --empty-action-height: 45px;' + LineEnding +
    '  --empty-gap: 12px;' + LineEnding +
    '  --empty-image-size: 67px;' + LineEnding +
    '  --expander-header-height: 36px;' + LineEnding +
    '  --field-button-width: 25px;' + LineEnding +
    '  --font-size-base: 14px;' + LineEnding +
    '  --font-size-title: 16px;' + LineEnding +
    '  --font-size-sm: 12px;' + LineEnding +
    '  --gallery-arrow-width: 25px;' + LineEnding +
    '  --gallery-cell-width: 78px;' + LineEnding +
    '  --gallery-glyph-pad: 6px;' + LineEnding +
    '  --gallery-grid-cell-height: 62px;' + LineEnding +
    '  --glyph-button-gap: 8px;' + LineEnding +
    '  --grid-comment-mark-size: 9px;' + LineEnding +
    '  --header-control-height: 36px;' + LineEnding +
    '  --header-section-width: 120px;' + LineEnding +
    '  --input-border-width: 1px;' + LineEnding +
    '  --listgroup-chevron-size: 18px;' + LineEnding +
    '  --listgroup-header-height: 40px;' + LineEnding +
    '  --listgroup-icon-gap: 8px;' + LineEnding +
    '  --listgroup-icon-size: 20px;' + LineEnding +
    '  --listgroup-item-height: 42px;' + LineEnding +
    '  --listgroup-item-indent: 22px;' + LineEnding +
    '  --listgroup-item-inset: 4px;' + LineEnding +
    '  --listview-cell-padding: 4px;' + LineEnding +
    '  --listview-check-size: 18px;' + LineEnding +
    '  --listview-group-header-height: 31px;' + LineEnding +
    '  --listview-hgap: 16px;' + LineEnding +
    '  --listview-icon-label-width: 110px;' + LineEnding +
    '  --listview-label-height: 22px;' + LineEnding +
    '  --listview-large-icon-size: 60px;' + LineEnding +
    '  --listview-small-icon-size: 20px;' + LineEnding +
    '  --listview-small-label-width: 180px;' + LineEnding +
    '  --listview-text-margin: 6px;' + LineEnding +
    '  --listview-tile-label-width: 180px;' + LineEnding +
    '  --listview-vgap: 12px;' + LineEnding +
    '  --menu-arrow-slot: 20px;' + LineEnding +
    '  --menu-check-slot: 22px;' + LineEnding +
    '  --menu-separator-height: 10px;' + LineEnding +
    '  --menu-shortcut-gap: 38px;' + LineEnding +
    '  --notification-close-size: 18px;' + LineEnding +
    '  --notification-gap: 12px;' + LineEnding +
    '  --notification-icon-size: 30px;' + LineEnding +
    '  --notification-margin: 26px;' + LineEnding +
    '  --notification-stack-gap: 12px;' + LineEnding +
    '  --notification-width: 408px;' + LineEnding +
    '  --pad-alert: 16px 20px;' + LineEnding +
    '  --pad-badge: 2px 8px;' + LineEnding +
    '  --pad-breadcrumb-item: 2px 8px;' + LineEnding +
    '  --pad-breadcrumb: 4px 8px;' + LineEnding +
    '  --pad-button: 10px;' + LineEnding +
    '  --pad-card: 20px;' + LineEnding +
    '  --pad-cell: 4px 12px;' + LineEnding +
    '  --pad-chip: 4px 12px;' + LineEnding +
    '  --pad-container: 16px;' + LineEnding +
    '  --pad-control: 8px;' + LineEnding +
    '  --pad-datetime: 8px 12px;' + LineEnding +
    '  --pad-empty: 32px;' + LineEnding +
    '  --pad-group-header: 4px 20px;' + LineEnding +
    '  --pad-groupbox: 12px 20px;' + LineEnding +
    '  --pad-none: 0px;' + LineEnding +
    '  --pad-notification: 16px 20px;' + LineEnding +
    '  --pad-segmented: 8px 16px;' + LineEnding +
    '  --pad-tight: 4px;' + LineEnding +
    '  --pad-tooltip: 8px 12px;' + LineEnding +
    '  --pagination-gap: 6px;' + LineEnding +
    '  --pagination-glyph-size: 16px;' + LineEnding +
    '  --popover-arrow-size: 10px;' + LineEnding +
    '  --popover-offset: 6px;' + LineEnding +
    '  --popover-title-gap: 10px;' + LineEnding +
    '  --qat-height: 36px;' + LineEnding +
    '  --qat-width: 144px;' + LineEnding +
    '  --radius-sm: 4px;' + LineEnding +
    '  --ribbon-appmenu-height: 36px;' + LineEnding +
    '  --ribbon-appmenu-width: 90px;' + LineEnding +
    '  --ribbon-caption-band-height: 25px;' + LineEnding +
    '  --scrollbar-size: 17px;' + LineEnding +
    '  --segmented-pad: 4px;' + LineEnding +
    '  --steps-connector-gap: 12px;' + LineEnding +
    '  --steps-connector-length: 45px;' + LineEnding +
    '  --steps-gap: 12px;' + LineEnding +
    '  --steps-marker-size: 30px;' + LineEnding +
    '  --tab-arrow-band: 22px;' + LineEnding +
    '  --tab-close-size: 18px;' + LineEnding +
    '  --tab-gap: 10px;' + LineEnding +
    '  --tab-margin: 10px;' + LineEnding +
    '  --tab-min-width: 67px;' + LineEnding +
    '  --tab-padding: 20px;' + LineEnding +
    '  --tag-close-size: 18px;' + LineEnding +
    '  --tag-gap: 6px;' + LineEnding +
    '  --titlebar-padding: 12px;' + LineEnding +
    '  --transfer-arrow-margin: 4px;' + LineEnding +
    '  --transfer-arrow-size: 16px;' + LineEnding +
    '  --transfer-button-gap: 10px;' + LineEnding +
    '  --transfer-button-height: 36px;' + LineEnding +
    '  --transfer-button-width: 45px;' + LineEnding +
    '  --transfer-rail-width: 78px;' + LineEnding +
    '  --transfer-title-height: 36px;' + LineEnding +
    '  --treeselect-drop-height: 308px;' + LineEnding +
    '}';
end;

end.
