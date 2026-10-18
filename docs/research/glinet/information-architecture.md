# 信息架构

## 菜单树

英文界面下的完整菜单（括号内是路由）。一级菜单 7 个，其中 3 个是直达页面，4 个是可展开的分组。

```
互联网 Internet            (#/internet)
无线 Wireless              (#/wireless)
客户端 Clients             (#/clients)
VPN                        ← 简体中文界面下整个隐藏
├─ VPN 仪表盘              (#/vpndashboard)
├─ OpenVPN 客户端          (#/ovpnclient)
├─ OpenVPN 服务端          (#/ovpnserver)
├─ WireGuard 客户端        (#/wgclient)
└─ WireGuard 服务端        (#/wgserver)
应用程序 Applications
├─ 软件包 Plug-ins         (#/plugins)
├─ 动态 DNS                (#/dynamicdns)   ← 简体中文界面下隐藏
└─ GoodCloud               (#/cloud)
网络 Network
├─ 防火墙                  (#/firewallview)
├─ 多线负载 Multi-WAN      (#/multiwan)
├─ 内部网络 LAN            (#/lanip)
├─ DNS                     (#/dnsview)
├─ 网络模式                (#/bridge)
├─ IPv6                    (#/ipv6)
├─ MAC 地址                (#/macclone)
├─ 旁路由 Drop-in Gateway  (#/edgerouter)
└─ IGMP Snooping           (#/igmp)
系统 System
├─ 概要 Overview           (#/overview)
├─ 升级                    (#/upgrade)
├─ 定时任务                (#/timedtask)
├─ 管理员密码              (#/adminpw)
├─ 时区                    (#/timezone)
├─ 按键设置 Toggle Button  (#/btnsettings)  ← 简体中文界面下隐藏
├─ 日志                    (#/logview)
├─ 重置固件                (#/reset)
└─ 高级设置（跳转 LuCI）   (#/advanced)
```

不在菜单里、但存在的路由：

| 路由 | 用途 |
|---|---|
| `#/login`、`#/welcome` | 登录、首次设置向导（未登录可访问） |
| `#/process` | 应用设置时的等待/进度页 |
| `#/modemmanage` | 蜂窝 Modem 管理（从互联网页的蜂窝卡片进入） |

前端是 Vue 2 + Element UI 的单页应用，用 hash 路由，共 35 条路由。

## 全局布局（桌面，≥ 1280px）

- **顶栏**：左侧 Logo + "管理面板" + 版本号；右侧依次是帮助（跳到在线文档）、重启、退出登录、主题切换、语言切换。
- **左侧深色导航栏**：图标 + 大写菜单名；分组展开后子项缩进显示，同一时间只展开一个分组。
- **内容区**：浅灰背景上的白色圆角卡片；页面标题在卡片上方，页面级操作按钮（如"编辑 Hosts""管理软件源"）放在标题右侧。
- **页脚**：版权信息，右下角。

## 移动端（390px 宽）

| 页面 | 观察 |
|---|---|
| 首页 | 拓扑图改成竖向的简化版：上网方式和客户端数变成两个圆形图标叠在左侧 |
| 导航抽屉 | 侧边栏收进汉堡菜单，从左侧滑出；顶栏的语言、主题、重启、退出也移到抽屉底部 |
| 客户端 | 表格只保留"名称 + IP"和"操作"两列，速度、流量、断网开关都收进了操作菜单 |
| 无线 | 表单保持左标签右控件的两列布局；标签页过多时左右滑动 |
| VPN | 协议名缩写成 OVPN / WG 以节省宽度 |

整体是把桌面布局等比压缩，没有为手机单独设计流程；主要操作仍在页面底部的居中按钮上。

## 主题

三套主题：默认（深蓝紫）、经典（墨绿）、暗色。只存在浏览器 `localStorage`，换浏览器会丢。没有"跟随系统"选项。

## 语言

- 8 种：English、简体中文、繁體中文、Deutsch、Español、Italiano、日本語、한국어。
- 语言设置保存在路由器上（不是浏览器），所有访问者看到同一种语言。
- **选择简体中文时，VPN 相关功能整体隐藏**：VPN 菜单、首页拓扑图上的 VPN 图标、动态 DNS、按键设置（它的选项只有 VPN 开关）都消失，直接访问 `#/vpndashboard` 返回 Not Found。这是按界面语言做的功能裁剪，与地区设置无关。

