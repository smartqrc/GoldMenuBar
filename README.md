# 黄金价格 GoldMenuBar

一款极简的 macOS 菜单栏黄金价格监视器。小金元宝常驻菜单栏，点开即看三项黄金核心数据，支持价格预警与持仓收益追踪。

![platform](https://img.shields.io/badge/platform-macOS%2011%2B-black) ![license](https://img.shields.io/badge/license-Apache%202.0-green) ![lang](https://img.shields.io/badge/lang-Swift%20%2B%20SwiftUI-orange)

## 功能

- 🌍 **国际金价**：COMEX 纽约金，美元/盎司，实时涨跌幅
- 🇨🇳 **国内金价**：上海金交所 Au(T+D)，人民币/克
- 💰 **ETF 净值**：易方达黄金 ETF 联接 C（002963）官方净值 + 盘中估算净值
- 🔔 **价格预警**：为国际/国内金价设定目标价（高于/低于），触发后系统通知提醒，菜单栏图标亮红点
- 📈 **持仓收益**：输入持有份额与成本净值，自动计算盈亏金额与收益率（数据仅存本机）
- 🔄 每 5 分钟自动刷新，支持手动刷新；深浅色模式自适应

## 安装

从 [Releases](../../releases) 下载 `黄金价格.zip`，解压后拖入「应用程序」文件夹，双击打开即可。

> 首次打开如提示无法验证开发者：右键点击 App →「打开」。
> 首次设置价格预警时请允许系统通知权限。

## 数据来源

均为公开接口，无需任何 API Key：

| 数据 | 来源 |
|---|---|
| 纽约金 / 上海金 | 新浪财经行情（GBK 编码） |
| 基金净值 | 天天基金 f10 接口 |

## 从源码构建

无需 Xcode IDE，仅需 Command Line Tools：

```bash
mkdir -p "黄金价格.app/Contents/MacOS"
xcrun swiftc -O main.swift PriceStore.swift PanelView.swift \
  -o "黄金价格.app/Contents/MacOS/GoldPrice"
```

`Info.plist` 与应用图标位于仓库对应目录，组装即可。

## 项目结构

```
main.swift        # 菜单栏入口（NSStatusItem + Popover）、元宝图标绘制
PriceStore.swift  # 数据拉取（新浪/东财）、预警逻辑、本地持久化
PanelView.swift   # SwiftUI 面板 UI（价格卡片 / 预警 / 持仓）
```

## License

[Apache License 2.0](LICENSE)
