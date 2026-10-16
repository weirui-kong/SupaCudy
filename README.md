# SupaCudy

基于官方 OpenWrt 的路由器固件，目标是给 Cudy TR3000 这类小型路由器提供一套**手机优先、开箱即用**的管理界面：中继、手机共享网络、VPN、广告过滤这些常用操作，几下点击就能完成。

SupaCudy 不是任何厂商固件的移植或修改版。底层是原版 OpenWrt，上面只加我们自己写的三个软件包；LuCI 原样保留，作为"高级设置"入口。

> 状态：**骨架阶段**。目前只有打包流程和一个用于验证链路的占位页面，还不能日常使用。路线图见 [docs/roadmap.md](docs/roadmap.md)。

## 支持的设备

| 设备 | 构建配置 | OpenWrt 底座 |
|---|---|---|
| Cudy TR3000 v1（128MB 闪存） | `cudy-tr3000-v1` | 24.10.8 |
| Cudy TR3000 v1（256MB 闪存） | `cudy-tr3000-256mb-v1` | 24.10.8 |

刷机前务必先读 [docs/hardware/cudy-tr3000.md](docs/hardware/cudy-tr3000.md)，确认你的闪存版本和批次。

## 快速开始

需要 Docker（macOS 上用 Docker Desktop 即可）。

```bash
# 1. 用官方 OpenWrt SDK 把 packages/ 打成 .ipk
scripts/build-packages.sh

# 2. 在 OpenWrt 容器里装上这些包，验证登录和 API（不需要路由器）
scripts/smoke-test.sh

# 3. 用官方 ImageBuilder 打出固件，产物在 out/images/<配置名>/
scripts/build-image.sh cudy-tr3000-v1
```

刷入后，LuCI 仍在 `http://192.168.1.1/`，SupaCudy 界面在 `http://192.168.1.1/supacudy/`。

开发时不用每次刷机，可以直接把改动推到路由器上：

```bash
scripts/deploy-dev.sh root@192.168.1.1
```

详见 [docs/development.md](docs/development.md)。

## 目录结构

```
config/openwrt.env    OpenWrt 底座版本（唯一需要改的地方）
profiles/             每种设备一个构建配置，common.conf 是公共软件包清单
packages/             OpenWrt feed，三个软件包：
  supacudy-base/        首次启动配置、版本信息、各功能的胶水脚本
  supacudy-rpcd/        ucode 写的 rpcd 插件和权限配置，对前端提供 API
  supacudy-ui/          编译好的前端静态文件，安装到 /www/supacudy
web/                  前端源码（待建，编译产物输出到 packages/supacudy-ui/htdocs）
patches/              预留：万一要改 OpenWrt 本身，以补丁形式放这里
scripts/              Docker 打包脚本和开发部署脚本
docs/                 架构、路线图、硬件说明
```

架构说明见 [docs/architecture.md](docs/architecture.md)。

## 声明

SupaCudy 是独立的社区项目，与 Cudy、GL.iNet 及 OpenWrt 项目均无关联，也未获得其认可。相关名称和商标归各自所有者。刷写第三方固件可能导致设备无法启动或失去保修，风险自负。

## 许可证

[Apache-2.0](LICENSE)。打进固件的 OpenWrt 组件遵循它们各自的许可证。
