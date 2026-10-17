# 路线图

## 阶段 0：打包链路（当前）

- [x] 仓库骨架、Apache-2.0 协议
- [x] 用官方 SDK 和 ImageBuilder 在 Docker 里打包
- [x] 三个软件包的空壳，加一个能登录并读出设备信息的占位页面
- [x] 容器冒烟测试（`scripts/smoke-test.sh`），CI 里每次提交自动跑
- [x] QEMU 模拟器：完整系统 + 虚拟 WiFi（hwsim）+ 虚拟上游热点和客户端，见 [docs/emulator.md](emulator.md)
- [ ] 在 TR3000 真机上刷入，确认无线、网口、USB、按键都正常

## 阶段 0.5：需求拆解

- [x] 拆解 GL.iNet 4.x 管理界面的信息架构、交互模式和功能清单，见 [docs/research/glinet/](research/glinet/README.md)
- [x] 逐项定优先级，见 [对照表](research/glinet/supacudy-mapping.md)
- [ ] 补充观察：中继扫描与连接流程、以太网设置、手机共享、首次向导和登录页、应用时的等待页

## 阶段 1：MVP（旅行路由器核心，P0）

- [x] 前端框架（Svelte），桌面和手机分别设计布局；中英文；系统 / 亮色 / 暗色主题
- [x] 通用组件第一批：卡片、说明横幅、ⓘ 提示气泡、数据行、进度条、分段选择
- [x] 通用组件第二批：表单控件、禁用原因提示、"改动后才能应用"、正在应用 → 成功 / 失败反馈、危险操作确认
- [x] 登录、会话过期处理、退出
- [x] 首次设置向导（语言、管理密码、WiFi 名称和密码、上网方式、时区）
- [x] 概览：设备信息、运行时间、负载、内存
- [x] 首页：上网方式 → 路由器 → 客户端的拓扑总览，接口状态卡片
- [x] 上网：有线 WAN（DHCP / 静态 / PPPoE）
- [x] 上网：**中继**（扫描、连接、显示上游信息、记住已连接网络并自动切换）
- [x] 无线：2.4G / 5G × 主 / 访客；开关、SSID、加密（含 WPA3）、密码、隐藏、发射功率、模式、带宽、信道；中继时锁定信道并说明原因
- [x] 客户端：在线 / 离线列表、实时速度和流量、改名和设备类型、禁止上网、一键固定 IP、随机 MAC 提示
- [x] LAN：网段和 DHCP 地址池、DHCP 保留
- [x] 系统：概要（CPU、内存、存储、系统信息）、本地固件升级、修改密码、时区、重启、恢复出厂、跳转 LuCI

## 阶段 2：VPN 和常用扩展（P1）

- [x] WireGuard 客户端：导入配置文件、手动添加（先填后存）、开关
- [x] OpenVPN 客户端（拒绝会执行脚本的配置项）
- [x] 全局代理 + Kill Switch（阻止非 VPN 流量）、允许访问上级局域网
- [x] 按设备分流（自有 nftables 标记 + 策略路由，未用 pbr）
- ~~WireGuard 服务端~~（不做：只提供 VPN 客户端，2026-10-17 决定）
- [x] USB 手机共享网络（Android RNDIS、iPhone；iPhone 未在真机验证）
- [x] 中继选项：2.4G 强制 20MHz；以太网 WAN 口改作 LAN 口
- [x] DNS：自动 / 手动 / 加密 DNS
- [x] MAC 地址：克隆 / 手动 / 随机
- [x] 客户端限速
- [x] WiFi 二维码分享、双频合一选项
- [x] AdGuard Home（默认安装，作为默认 DNS；设置以它自己的配置为准，可打开它自己的页面）
- [x] 日志查看和导出

## 阶段 3：其余功能（P2）

- [x] 救援模式：路由器无法分配地址或无法连接时临时开启接入方式和指示灯（仅运行时，不改用户配置）
- [x] 出厂默认：LAN 192.168.200.1、无密码 Wi-Fi「SupaCudy」、登录 root / supacudy
- [x] 统一密码：SSH、网页界面、AdGuard Home 共用管理密码
- [x] 根地址默认打开 SupaCudy，左下角可跳转原生 OpenWrt（先提示风险）

- [x] 按域名 / IP 分流
- ~~OpenVPN 服务端、VPN 级联~~（不做：只提供 VPN 客户端）
- ~~多 WAN 故障转移和检测设置~~（不做；保留按链路断开的度量值切换）
- [x] 端口转发、路由器开放端口、DMZ
- [x] DNS 重绑定保护、编辑 Hosts
- [x] 网络模式：路由 / AP（中继见阶段 1；切换前的断网警告和恢复办法）
- [x] IPv6（OpenWrt 默认开启；VPN 配置没有 IPv6 地址时阻止 IPv6 绕过隧道）
- [x] DDNS（第三方服务）
- [x] Tailscale 客户端（不做 ZeroTier；用真实账号登录待验证，见 decisions-pending.md）
- [x] 定时任务：WiFi 定时开关、定时重启
- [ ] LED 定时（需真机）
- [ ] 侧边拨动开关绑定功能（视 TR3000 硬件而定）
- [x] 家长控制（按时间段断网）、硬件加速开关

## 功能和 OpenWrt 组件对照

| 功能 | 依赖的 OpenWrt 组件 |
|---|---|
| 中继 | wpad、netifd（sta 接口 + wwan） |
| USB 手机共享 | kmod-usb-net-rndis、kmod-usb-net-cdc-ether、kmod-usb-net-ipheth |
| WireGuard | wireguard-tools、kmod-wireguard |
| OpenVPN | openvpn-mbedtls |
| 分流 | pbr |
| 多 WAN | mwan3 |
| 广告过滤 | adguardhome |
| 客户端限速 / 拉黑 | firewall4（nftables） |
| 硬件加速 | flow offloading（MT7981 的 PPE / WED） |
