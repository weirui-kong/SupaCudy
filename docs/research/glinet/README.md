# GL.iNet 管理界面拆解

本目录记录对 GL.iNet 4.x 管理界面的观察：页面结构、交互方式和功能清单，作为 SupaCudy 产品设计的参考。这里只描述"它做了什么、怎么组织的"，SupaCudy 的实现不复用其任何代码、图标、图片或原文案（见 [产品规则](../../rules/product.md)）。

## 观察环境

| 项目 | 值 |
|---|---|
| 设备 | GL-MT300N-V2（MT7628AN，2.4GHz 单频，16MB 闪存） |
| 固件 | 4.3.25 release2，编译于 2025-03-18 |
| 底座 | OpenWrt 22.03.4，内核 5.10.176 |
| 访问方式 | GoodCloud 远程 Web 访问 |
| 当时的上网方式 | 中继（2.4G） |
| 观察日期 | 2026-10-17 |

这台设备是低端单频机型，闪存只剩约 1.3MB，所以 5GHz、AdGuard Home、Tailscale 等高端机型才有的功能在这里看不到。凡是本目录提到但没在这台设备上实际看到的功能，都会标注"未在本机观察"。

## 文档索引

| 文件 | 内容 |
|---|---|
| [information-architecture.md](information-architecture.md) | 信息架构：菜单树、全部路由、全局布局、主题、语言、移动端 |
| [ui-patterns.md](ui-patterns.md) | 反复出现的交互模式和视觉规律 |
| [features/internet.md](features/internet.md) | 互联网：拓扑总览、以太网、中继、热点共享、蜂窝网络 |
| [features/wireless.md](features/wireless.md) | 无线：主 WiFi、访客 WiFi |
| [features/clients.md](features/clients.md) | 客户端：列表、改名、限速、断网 |
| [features/vpn.md](features/vpn.md) | VPN：仪表盘、代理模式、WireGuard / OpenVPN 客户端和服务端 |
| [features/applications.md](features/applications.md) | 应用：软件包、动态 DNS、GoodCloud |
| [features/network.md](features/network.md) | 网络：防火墙、多 WAN、LAN、DNS、工作模式、IPv6、MAC、旁路由、IGMP |
| [features/system.md](features/system.md) | 系统：概要、升级、定时任务、密码、时区、按键、日志、重置、LuCI |
| [supacudy-mapping.md](supacudy-mapping.md) | 对照 SupaCudy：优先级、OpenWrt 实现方式、我们打算做得不一样的地方 |

调研时截取的界面截图版权属于 GL.iNet，不放进本仓库。

## 方法和隐私处理

- 只做浏览和打开操作：切换页面、标签页、下拉框、弹窗、提示气泡，读完即用"取消"或关闭按钮退出，不点任何"应用""保存""生成"类按钮。
- 截图前用页面内的遮罩层盖住：所有 IP、MAC、SSID、WiFi 密码、设备 ID、序列号、DDNS 域名、绑定账号、客户端名称、远程访问域名。日志页整块模糊处理。截图不含 EXIF。
- 原始页面文本只在分析过程中使用，没有存进仓库。

## 观察过程中对设备的改动

| 改动 | 原因 | 状态 |
|---|---|---|
| WireGuard 客户端下新增了一个空的提供商分组 "New Provider" | 点击"手动添加"会直接创建分组并立即保存（这本身也是一个交互发现，见 [vpn.md](features/vpn.md)） | 已按用户确认删除（删除前有"确定要删除吗"二次确认），复查后只剩内置的提供商 |
| 界面语言在英文和简体中文之间切换过，最后切回简体中文 | 对比中英文界面，以及删除上面的分组（中文界面下 VPN 页面不可访问）；语言设置保存在路由器上 | 已恢复为开始时的简体中文 |
| 主题在默认 / 暗色 / 经典之间切换过 | 截取主题对比图；主题只存在浏览器本地 | 已恢复为默认 |

## 刻意没有做的操作

以下操作可能导致断网或改动配置，本次没有执行，相关细节留待以后在不影响使用的设备上补充：

- "切换网络"（会触发 WiFi 扫描并可能切换上游）、"禁用"中继
- 以太网口"切换至 LAN 口"
- 任何"应用"、WireGuard / OpenVPN 服务端"生成配置"、客户端"删除全部"、"清除流量统计"
- 重启、退出登录、恢复出厂、固件升级
- 打开 LuCI
