# 开发指南

## 需要的工具

- Docker（macOS 上用 Docker Desktop）。OpenWrt 官方的 SDK 和 ImageBuilder 镜像只有 amd64 版本，在 Apple Silicon 上会通过模拟运行，速度慢一些，但能用。
- 一台运行 OpenWrt 24.10 的 TR3000，或者以后加上的 QEMU 虚拟机，用来调试。

## 第一次克隆后

```bash
git config core.hooksPath .githooks   # 启用 pre-push 钩子：push 前自动跑全部测试
brew install shellcheck               # lint 测试需要（Linux 上用 apt install shellcheck）
```

项目规则（产品、编码、测试、协作）见 [CLAUDE.md](../CLAUDE.md) 和 [docs/rules/](rules/)。

## 测试

```bash
scripts/test.sh
```

依次运行 lint → 打包 → build → api（以及前端建好后的 web-unit、web-e2e），最后输出汇总。任何一项失败都不能 push。分类和要求见 [docs/rules/testing.md](rules/testing.md)，每一项的完整日志在 `out/test-logs/`。

## 打包

```bash
scripts/build-packages.sh               # packages/ → out/packages/*.ipk
scripts/build-image.sh cudy-tr3000-v1   # → out/images/cudy-tr3000-v1/
```

- `build-packages.sh` 在官方 SDK 镜像里只编译 `supacudy` feed 下的包。
- `build-image.sh` 把 `out/packages/` 里的包放进 ImageBuilder，和 `profiles/common.conf` 加设备配置里列出的官方包一起打成固件。
- 升级 OpenWrt 底座：改 `config/openwrt.env` 里的版本号，重新跑上面两条命令。

## 在容器里验证（不需要路由器）

```bash
scripts/smoke-test.sh          # 跑完检查后删除容器
scripts/smoke-test.sh --keep   # 保留容器，浏览器打开 http://localhost:8080/supacudy/
```

它会启动同版本的官方 OpenWrt rootfs 容器（Apple Silicon 上用 arm64 版，原生运行；x86 机器和 CI 上用 x86-64 版），装上 `out/packages/` 里的包，手动拉起 ubusd、rpcd、uhttpd，然后检查：

- `/supacudy/` 页面能访问；
- 错误密码登录被拒绝，正确密码能拿到会话；
- `supacudy.info` 返回正确的版本信息；
- 未登录调用 `supacudy.info` 被拒绝。

`--keep` 模式下的登录密码是 `supacudy-test`。容器里没有 procd，所以 `system.*` 这类由 procd 提供的接口不可用，页面上的运行时间和内存会显示"—"；无线、网口这些硬件相关的功能也只能在真机上测。

## 不刷机调试

```bash
scripts/deploy-dev.sh root@192.168.1.1
```

它会把三个包的文件直接拷到路由器上并重启 rpcd，几秒钟生效。注意：

- 用的是 ssh 加 tar 传输，不依赖路由器上的 sftp。
- 只覆盖文件，不会删除你在仓库里已经删掉的旧文件。需要彻底干净时，刷一次完整固件。
- `/etc/uci-defaults/` 里的脚本只在首次启动时执行，部署脚本会把它们拷过去但不执行。需要时可以 ssh 上去手动运行。

## 调试 API

在路由器上可以直接用 ubus 调用：

```sh
ubus call supacudy info
```

改了 rpcd 插件后报错，可以停掉 rpcd 服务后在前台运行它，看输出：

```sh
/etc/init.d/rpcd stop
rpcd
```

## 前端

前端源码将放在 `web/`，编译产物输出到 `packages/supacudy-ui/htdocs/`。在那之前，`htdocs/` 里是一个手写的占位页面，用来验证"登录 → 调用 supacudy.info"这条链路。
