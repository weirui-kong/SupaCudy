# SupaCudy

简体中文 | [English](README.en.md)

![SupaCudy 概览页，运行在 Cudy TR3000 上](docs/images/overview.webp)

SupaCudy 是基于 OpenWrt 24.10 的 Cudy TR3000 固件，提供简洁易用的管理页面，同时保留 LuCI。

## 功能

- 上网：有线 WAN、无线中继（含企业级 Wi-Fi）、USB 手机共享网络、多出口自动切换
- Wi-Fi：主网络和访客网络、双频合一、二维码分享
- 客户端：设备列表、限速、禁止上网、固定 IP、家长控制
- VPN 客户端：WireGuard、OpenVPN，按设备或网站分流
- DNS：加密 DNS，AdGuard Home 广告过滤
- 远程访问：Tailscale
- 安全：统一管理密码、登录保护、WAN 访问控制
- 系统：温度显示、CPU 限制、定时任务、端口转发、DDNS、救援模式、固件升级
- 界面：适配手机和桌面，中文和英文，浅色和深色主题

## 状态

可以刷机使用，但还在快速开发中，接口和默认值可能变化。

- 每次提交都会跑单元、界面、软件包和整机模拟器测试。
- 已在 TR3000 真机上运行，部分只能在真机上验证的项目（如企业级 Wi-Fi、USB 手机共享）尚未逐项测试。

## 支持的设备

| 设备 | 构建配置 | OpenWrt |
|---|---|---|
| Cudy TR3000 v1（256MB 闪存） | `cudy-tr3000-256mb-v1` | 24.10.8 |

128MB 闪存的版本不支持，两者的固件不能混刷。

## 刷机

完整步骤、备份和救砖方法见 [docs/hardware/flashing-tr3000.md](docs/hardware/flashing-tr3000.md)。简要流程：原厂固件 → Cudy 提供的 OpenWrt 过渡固件 → 备份分区 → 刷入 SupaCudy（不保留配置）。

刷完后：

- 连接无密码的 Wi-Fi「SupaCudy」，或用网线连 LAN 口。
- 打开 <http://192.168.200.1/>，用 `root` / `supacudy` 登录，按向导设置新的管理密码和 Wi-Fi。
- 原版 LuCI 在 <http://192.168.200.1/cgi-bin/luci/>。

刷写第三方固件有让设备变砖或失去保修的风险，请先读完刷机文档。

## 文档

- [刷机和救砖](docs/hardware/flashing-tr3000.md)
- [开发指南](docs/development.md)：从源码构建固件、模拟器、测试和调试
- [架构](docs/architecture.md)
- [路线图](docs/roadmap.md)
- [贡献指南](CONTRIBUTING.md)

## 声明

- 刷写第三方固件存在风险，请在操作前自行备份重要数据。因使用本项目造成的任何后果，包括但不限于数据丢失、设备损坏或无法启动、失去保修，均由使用者自行承担，项目作者和贡献者不承担任何责任。
- 本项目仅供技术交流和学习使用，禁止用于任何违法用途。使用者须遵守所在地的法律法规，包括无线电管理、网络安全和数据保护等方面的规定。
- SupaCudy 是独立的社区项目，与 Cudy、GL.iNet 及 OpenWrt 项目均无关联，也未获得其认可。相关名称和商标归各自所有者。

## 许可证

[Apache-2.0](LICENSE)。固件里的 OpenWrt 及其软件包遵循各自的许可证。
