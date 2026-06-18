# TyControls 主题系统 v2 · 阶段2「分层加载 / 授权」设计

- **日期:** 2026-06-18 · 承总纲 §3.1/§3.6/§3.8 + §4-A6/A7/A8/A9 + B + C。Phase 0(merge-then-resolve)/Phase 1(分层令牌)已落地。
- **来源:** 4-lens 设计 workflow（parser / cascade / override / registry-bundles）+ 综合。完整设计存 workflow 输出;本文是落地 spec + commit 序列。

## 决策摘要

1. **`FVersion: Cardinal`(地基锚)** — TTyStyleModel 加版本号,`LoadInto` 提交 + `Clear` 时 bump。§3.8「切换=替换层1 + bump版本 + 失效缓存」的锚;A9 override 缓存键。无值缓存也正确(无缓存=无残留),但 FVersion 必加。
2. **apply-all-forward(`ResolveLayer` 改)** — `FindEntryIn`(取最后一个) → `ApplyAllMatching`(**正序**应用**所有**命中条目,后者按字段覆盖)。这样 additive/@import/级联里同一槽的多条目能**逐属性合并**。`TestDuplicateRuleLastWins` 仍过(两条都应用、后者覆盖字段=同结果);**金标准零变化**(三主题无同主题重复选择器)。**无条件改**(安全)。
3. **additive load(A6)** — `LoadInto(…; AReplace: Boolean=True)`:False=不清空、追加规则 + 合并 vars(新覆盖旧)。`Model.LoadFromCssAdditive` + `Controller.LoadThemeCssAdditive`。
4. **@import(A8)** — lexer 加 `ctkAtKeyword`(`@` 后读 ident);parser 顶层分发 at-rule,`@import "file";` → 收集到 `TTyCssStylesheet.Imports[]`(解析器**不做 IO**);`LoadInto` 递归 `ExpandSheet`:**先展开被导入文件**(其规则/vars 在前)→ 再追加本文件(importer 覆盖)。base-dir **栈**(嵌套相对解析)+ **环检测**(active-stack + done-set DFS,深度上限 32)。`@import` 必须在所有规则前。
5. **property cascade(A7)** — `Model.PropertyCascade: Boolean`(默认 **False**=今天的全有或全无,金标准不变)。True 时:`ResolveStyle` **无条件先应用 base 层**再 user 层(逐属性覆盖,省略=继承 base,D4);退役 `UserHasTypeKey` 门;**`MaxGlassBlur` 的 base-skip 必须同步去掉**(伴随编辑)。风险控件(§7-1)多自保:TyGroupBox 标题遮盖是**几何**非 Present 门、TyLabel `FTransparent` 默认不画框 → 安全。
6. **per-instance StyleOverride(A9)** — 两个基类各加 `published StyleOverride: string`(无共同祖先,镜像 `FStyleClass` 孪生)。`CurrentStyle` 末尾:`if FStyleOverride<>'' then TyMergeStyleSet(Result, Model.ResolveOverride(FStyleOverride))`(§3.1 层2)。`ResolveOverride`:把片段包成 `_ovr{…}` 走现有 parser 取 decls → 逐条 `TyApplyDeclaration(…, FMergedVars)`(故 `var(--…)` 按活动主题解析;**实例数据可用 var,不违反令牌铁律**)。**逐控件单槽缓存**键 `(text, Model.ThemeVersion)` → 切换自动重算(§3.8)。坏 override **不崩绘制**(parse 失败=空;逐 decl try/except 跳坏值)。**不支持** `:hover{}` 子选择器(v1 单块,留作扩展)。
7. **registry(B)** — 新单元 `tyControls.ThemeRegistry`(name→`ITyThemeSource` 大小写无关单例);`Controller.ThemeName` 走**替换层1 切换路径**(`AReplace=True` + bump FVersion + Changed)。内置 light/dark/showcase/green 自注册。**切换-非叠加回归测试**(A→B 后 B 未声明属性取 **base** 值而非 A,§7-6)。`ThemeName`/`ThemeFile` 互斥。
8. **bundles(C)** — `ITyThemeSource`(`RootCss`/`OpenAsset`/`Manifest`) + `TTyThemeDirSource`(把 `GThemeBaseDir` 全局重构成 source 携带的解析器);`TTyThemeZipSource`(FPC `TUnZipper` + `OnCreateStream` 内存读)。zip **图片资产**(painter 要文件路径)→ 解压到 temp + 改写 `ImagePath`(零 painter 改);CSS-only zip 无此问题。`theme.json`(name/extends/dualMode;dualMode 到 P3 才活)。**dir-vs-zip 金标准等价测试**。**若砍先砍 zip-图片资产 + 值缓存;FVersion/切换替换/切换回归测试不可砍。**

## Commit 序列(每步 tytests + 金标准绿)

`FVersion + apply-all-forward` → `additive load` → `@import`(lexer+parser+ExpandSheet) → `property cascade`(flag) → `StyleOverride` → `registry + ThemeName + 切换测试` → `bundles: ITyThemeSource + DirSource(资产解析重构,green 金标准守恒)` → `ZipSource + 等价测试` → `theme.json`。

## 需真机验证(headless 不可验)
本阶段基本可 headless 验(模型/解析/缓存)。zip-image-assets 的 temp-extract 路径在真 GUI 看图;registry 切换的重绘在真 GUI 看。其余靠 tytests + 金标准。
