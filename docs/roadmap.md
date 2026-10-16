# 路线图

## 阶段 0：打包链路（当前）

- [x] 仓库骨架、Apache-2.0 协议
- [x] 用官方 SDK 和 ImageBuilder 在 Docker 里打包
- [x] 三个软件包的空壳，加一个能登录并读出设备信息的占位页面
- [x] 容器冒烟测试（`scripts/smoke-test.sh`），CI 里每次提交自动跑
- [ ] 在 TR3000 真机上刷入，确认无线、网口、USB、按键都正常

## 阶段 1：MVP（旅行路由器核心）

- [ ] 前端框架（Svelte），手机优先布局，中英文
- [ ] 登录、首次设置向导（语言、管理密码、WiFi 名称和密码）
- [ ] 仪表盘：上网状态、客户端数、负载
- [ ] 上网：有线 WAN（DHCP / PPPoE / 静态）、**中继**（扫描后一键连接、记住已连接过的网络）
- [ ] 无线：2.4G / 5G 开关、名称、密码、访客网络
- [ ] 客户端：列表、改名、拉黑
- [ ] 系统：固件升级、恢复出厂、时间、日志、修改密码

## 阶段 2：VPN 和上网方式

- [ ] WireGuard 客户端：导入配置、开关、Kill Switch
- [ ] OpenVPN 客户端
- [ ] WireGuard 服务端：生成客户端配置和二维码
- [ ] 按设备分流（基于 pbr）
- [ ] USB 手机共享网络（Android RNDIS、iPhone）
- [ ] AdGuard Home

## 阶段 3：其余功能

- [ ] 多 WAN 优先级和自动切换（mwan3）
- [ ] 侧边拨动开关绑定功能（如一键开关 VPN）
- [ ] 工作模式：路由 / AP / 中继
- [ ] 端口转发、DNS、IPv6
- [ ] Tailscale、ZeroTier、DDNS
- [ ] 家长控制（按时间段断网）
- [ ] LED 控制、硬件加速开关

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
