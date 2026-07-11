# Transitions（tyControls.Transitions）

## 概述

一个**过渡动画工具单元**(不是控件、无调色板组件):给控件/表单播放出现动画,基于 `TTyAnimator` 缓动内核 +
惰性 timer。**不改 `tyControls.Form.pas`**。跨平台:**滑入**动位置(全平台);**淡入**用 `AlphaBlendValue`
(仅 Windows,其它平台/非表单降级为直接显示)。

## 用法

```pascal
uses tyControls.Transitions;

procedure TForm1.FormShow(Sender: TObject);
begin
  TySlideIn(Self, ttSlideUp);   // 从下方滑入
  // 或 TyFadeIn(Self);          // 淡入(Windows;其它平台直接显示)
end;
```

## API

```pascal
type TTyTransitionKind = (ttNone, ttFade, ttSlideUp, ttSlideDown, ttSlideLeft, ttSlideRight);

procedure TyPlayTransition(AControl: TControl; AKind: TTyTransitionKind; ADurationMs: Integer = 200);
procedure TyFadeIn(AControl: TControl; ADurationMs: Integer = 200);
procedure TySlideIn(AControl: TControl; AKind: TTyTransitionKind; ADurationMs: Integer = 200);
{ 纯函数:某方向滑入的起始偏移(相对目标,t=0 在偏移处、t=1 在 0)}
procedure TyTransitionStartOffset(AKind: TTyTransitionKind; AW, AH: Integer; out ADX, ADY: Integer);
```

| 方向 | 起点 | 偏移 |
|---|---|---|
| `ttSlideUp` | 目标下方 | `DX=0, DY=+AH` |
| `ttSlideDown` | 目标上方 | `DX=0, DY=−AH` |
| `ttSlideLeft` | 目标右侧 | `DX=+AW, DY=0` |
| `ttSlideRight` | 目标左侧 | `DX=−AW, DY=0` |
| `ttFade` / `ttNone` | — | `0, 0` |

## 关键设计

- **驱动器归控件所有**:每次过渡建一个隐藏的 `TTyTransitionDriver`(`Create(AControl)` → 控件析构时一并释放),
  它拥有自己的 `TTimer`。所以**动画中控件被释放,不会留下悬空 timer**;正常结束用 `Application.ReleaseComponent`
  延迟释放(不在自己的 OnTimer 里 `Self.Free`)。同一控件重复调用先 `CancelExisting` 释放旧驱动,不叠加。
- **淡入 AlphaBlend 复位在析构里**(不只在正常完成的 `Finish`),所以淡入被打断(`CancelExisting` / owner-free)
  也不会把表单永久留成半透明;`csDestroying` 守卫避免碰将死控件的句柄。
- **跨平台**:滑入 `SetBounds`(可移植);淡入 `{$IFDEF MSWINDOWS}` `AlphaBlendValue`,非 Windows / 非表单降级为
  即时显示。`ttNone` / nil 控件 = no-op。
- 可无头测:`TyTransitionStartOffset` + `TTyAnimator` 插值;窗口/timer 行为真机。

## 关联

见 `docs/superpowers/plans/2026-07-12-phase9-finish.md`。动画内核见 `tyControls.Animation`(`TTyAnimator`)。
