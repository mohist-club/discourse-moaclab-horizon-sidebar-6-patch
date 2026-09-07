# Moaclab Horizon Sidebar 6 Patch

Moaclab 的 Discourse 主题组件，用于补充 Horizon Sidebar 6 和 Right Sidebar Blocks 的站点级样式与交互。

## 当前功能

- 游客点击受保护附件时保留原生登录提示，避免继续跳转到 404。
- 可隐藏左侧栏的 Tags 区块。
- 可关闭移动端类别介绍区域的吸顶效果。
- 优化右侧热门话题、近期活动及后续模块的排版与吸顶行为。
- 可为指定类别启用独占的“子类别 Logo 网格”。默认类别是键盘（ID `13`）：
  - 该类别右侧只显示子类别模块；
  - 自动读取 Discourse 服务器上的类别 Logo；
  - 窄侧栏使用 2 列，常规及宽侧栏使用设置中的列数（默认 3 列）；
  - 工作室模块随页面滚动，并保持在首次显示时的原始纵向位置；
  - 其他类别继续使用原有右侧模块。
- 在键帽库（ID `8`）和资源（ID `9`）右侧仅显示“最新问答”模块：
  - 直接复用 Right Sidebar Blocks 自带的 `category-topics` 区块，不再由本组件调用任何类别 JSON 接口；
  - 数据请求、路由切换和缓存全部交给 Discourse 原生数据层；
  - 模块保持原始纵向位置吸顶。

## Right Sidebar Blocks 配置

在 **Right Sidebar Blocks → blocks** 中添加一个区块：

- `name`: `category-topics`
- 参数 `id`: `4`
- 参数 `count`: `5`

本组件在键帽库和资源页面只显示这个原生区块，并负责“最新问答”标题、列表样式和吸顶。请删除旧的自定义“最新问答”区块；从 `1.7.0` 起，本组件不会再请求 `/c/faq/4.json`。

## 安装或更新

在 Discourse 后台打开：

**管理 → 自定义 → 主题 → 安装 → 从 Git 仓库安装**

使用仓库地址：

```text
https://github.com/mohist-club/discourse-moaclab-horizon-sidebar-6-patch.git
```

安装后将组件添加到当前使用的主题。后续版本可以直接在该组件页面点击“检查更新”或“更新到最新版本”。

## 主要设置

- `enable_exclusive_subcategory_grid`：启用指定类别的独占子类别网格。
- `exclusive_subcategory_grid_categories`：选择使用该布局的类别。
- `subcategory_grid_heading`：设置网格标题，默认显示“工作室”。
- `subcategory_grid_columns`：宽侧栏中的最大列数。
- `hide_tags_sidebar_section`：隐藏左侧 Tags 区块。
- `enable_right_sidebar_sticky_stack`：启用右侧后续模块吸顶组。
- `enable_exclusive_faq_latest`：启用指定类别的独占“最新问答”模块。
- `exclusive_faq_latest_categories`：选择显示该模块的类别，默认键帽库和资源。
- `faq_latest_heading`：模块标题，默认“最新问答”。

版本：`1.7.0`
