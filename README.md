# chn-mod — ToME4 汉化补充插件

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

《ToME4 - Tales of Maj'Eyal》1.7.6 的中文本地化补充插件（Modified Chinese Translation）。

## 内容

| 部分 | 说明 |
|---|---|
| 核心 tome 译文 | 3,348 条覆盖/新增条目（相对官方中文 locale） |
| 官方 DLC 译文 | Ashes of Urh'Rok、Cults of Entropy、Embers of Rage 共 5,426 条 |
| Nullpackreloaded 支持 | 464 条译文 + 特殊物品运行时挂钩 |
| 运行时挂钩 | 角色面板、技能、出生描述、游戏选项等文本翻译注入 |

译文由 `tome4-chinese-translation-review-fixes` 工具链确定性构建（`tools/i18n publish`），
每次发布同步此仓库的 `data/locales/zh_hans.lua`。

## 安装

1. 下载本仓库（或 [Release](https://github.com/yutio8888/tome4-chn-mod/releases) 包）
2. 将 `chn-mod` 目录复制到游戏 `game/addons/` 下
3. 启动游戏，在 addons 菜单勾选 chn-mod
4. 游戏语言需选择简体中文（zh_hans）

## 许可

本插件是 ToME4 及其官方 DLC（Copyright (C) 2009-2019 Nicolas Casalini "DarkGod"，
GPL v3 or later）的中文本地化衍生作品，按 **GNU GPL v3（或任何更新版本）** 发布，
详见 `init.lua` 头部声明。译文版权归各自译者所有，按相同许可授权。
