# 第三方组件声明（Third-Party Notices）

本项目在遵循各自许可证的前提下使用了以下第三方组件。

## TagLib

- **版本**：2.1.1（预编译动态库，位于 `ReTagger/Support/TagLib/`）
- **主页**：<https://taglib.org>
- **源码**：<https://github.com/taglib/taglib>
- **许可证**：GNU Lesser General Public License v2.1（LGPL-2.1）与 Mozilla Public License 1.1（MPL-1.1）双许可
- **许可证全文**：见 [`ReTagger/Support/TagLib/Licenses/COPYING.LGPL`](ReTagger/Support/TagLib/Licenses/COPYING.LGPL) 与 [`ReTagger/Support/TagLib/Licenses/COPYING.MPL`](ReTagger/Support/TagLib/Licenses/COPYING.MPL)

TagLib 以动态链接方式集成（`libtag` / `libtag_c` dylib 随 App 打包），本项目未修改其源码。
依照 LGPL-2.1，你可以自行编译或替换同版本接口兼容的 TagLib 动态库；
从源码构建的方法见 TagLib 官方仓库的构建说明。

Copyright (C) 2002 - 2023 by the TagLib authors.

## Google 标识

`Assets.xcassets/GoogleLogo.imageset` 与 `assets/icon/Google__G__logo.svg` 中的
Google "G" 徽标是 Google LLC 的商标，仅按照
[Google 品牌规范](https://developers.google.com/identity/branding-guidelines)
用于"使用 Google 登录"按钮的展示，不表示 Google 对本项目的赞助或背书。
