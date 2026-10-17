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

## 加速和本机配置

- **镜像源**：在 `config/local.env`（不入库）里设置 `OPENWRT_MIRROR`，ImageBuilder 和测试容器会从这里下载官方软件包。国内推荐：

  ```bash
  echo 'OPENWRT_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/openwrt' > config/local.env
  ```

  软件包签名仍按 OpenWrt 的公钥校验，换源不影响安全性。
- **下载缓存**：ImageBuilder 下载过的软件包保存在 Docker 卷 `supacudy-imagebuilder-dl-*` 中，下次直接复用（`docker volume rm` 可清空）。
- **跳过没变的构建**：`build-packages.sh` 和 `build-image.sh` 会对输入内容算哈希，没变就跳过 SDK / ImageBuilder。需要强制重建时加 `FORCE=1`。模拟器镜像（`HOT_DEPLOY=1`）只看软件包的 Makefile、profile 和脚本：测试开机后会把工作区的文件部署进虚拟机，所以只改文件内容时不用重做镜像。
- **api 依赖缓存**：`smoke-test.sh` 第一次把依赖（AdGuard Home、Tailscale 等）装进本地镜像 `supacudy-smoke-deps:<依赖哈希>`，之后只装我们自己的包，几秒跑完。依赖变了会自动重建；`docker image rm` 可清理旧的。
- **并行测试**：`scripts/test.sh` 先构建一次前端，然后三条链同时跑：打包 → build → api；web-e2e；模拟器（镜像是新的就马上开始，否则等打包完成再出镜像）。模拟器测试分两组在两台虚拟机上同时跑。它们各用各的容器、端口和日志（api 18081，e2e 18080，模拟器 18088–18089 / 12222–12223 / 13000–13001，都只监听 127.0.0.1）。
- **只跑部分模拟器测试**：开发时用 `tests/emulator/run.sh internet`（可列多个套件，`--keep` 保留虚拟机），几分钟内看到结果；push 前仍要跑完整的 `scripts/test.sh`。

## 测试

```bash
scripts/test.sh
```

运行 lint → web-unit → 前端构建，再并行运行打包 → build → api、web-e2e 和模拟器，最后输出汇总。任何一项失败都不能 push。分类和要求见 [docs/rules/testing.md](rules/testing.md)，每一项的完整日志在 `out/test-logs/`。

## 打包

```bash
scripts/build-packages.sh               # packages/ → out/packages/*.ipk
scripts/build-image.sh cudy-tr3000-256mb-v1   # → out/images/cudy-tr3000-256mb-v1/
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

源码在 `web/`：Svelte 5 + TypeScript，Vite 构建，编译产物输出到 `packages/supacudy-ui/htdocs/`（不入库，`build-packages.sh` 会先构建它）。

```bash
cd web
npm ci                     # 第一次
npm run dev                # 开发服务器，/ubus 代理到 http://localhost:8080
npm test                   # svelte-check 类型检查 + 单元测试
npm run build              # 只构建前端
```

开发服务器默认把 API 请求代理到 `scripts/smoke-test.sh --keep` 启动的容器（登录密码 `supacudy-test`）。要连真机，设置 `SUPACUDY_TARGET=http://192.168.1.1 npm run dev`。

目录约定：

| 路径 | 内容 |
|---|---|
| `src/lib/api.ts` | 唯一和路由器通信的模块：会话、错误映射、每个接口的类型化封装 |
| `src/lib/i18n/` | `en.ts` 是词条的唯一来源，`zh-CN.ts` 必须同形（类型保证），`t()` 取词条 |
| `src/lib/theme.svelte.ts` | 系统 / 亮色 / 暗色偏好，存在 localStorage |
| `src/lib/router.svelte.ts` | hash 路由和导航项 |
| `src/styles/tokens.css` | 设计令牌（颜色、间距、圆角、字号），亮暗两套 |
| `src/components/` | 通用组件：Card、Banner、InfoTip、DataRow、Meter、Segmented、Icon |
| `src/layout/Shell.svelte` | 桌面侧边栏 / 手机底部导航 |
| `src/pages/` | 每个页面一个组件 |
| `tests/unit/` | Vitest 单元测试 |
| `tests/e2e/` | Playwright 测试，由 `scripts/test-e2e.sh` 对着容器运行 |

新增一个页面：在 `router.svelte.ts` 的 `ROUTES` 加一项，在 `App.svelte` 里挂上组件，en / zh-CN 两边加词条，补单元测试和 e2e 测试（e2e 至少调用一次 `expectPageQuality()`）。
