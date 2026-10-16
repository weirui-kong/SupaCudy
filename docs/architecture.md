# 架构

```
浏览器（手机优先的单页应用）
   │  JSON-RPC over HTTP
uhttpd ── /ubus ── rpcd（会话、ACL 权限）
                     └─ supacudy.* 对象（ucode 插件，在 supacudy-rpcd 包里）
                          │
                    UCI 配置 + OpenWrt 原生服务
                    （netifd、wpad、firewall4、dnsmasq、wireguard、mwan3 ...）
```

## 原则

1. **不 fork OpenWrt。** 底座是官方发布版，版本号只在 `config/openwrt.env` 里写一次。我们的代码全部以 feed 的形式放在 `packages/`。
2. **配置的唯一来源是 UCI。** SupaCudy 不自己存一份配置，所有设置最终都写进 `/etc/config/*`，所以在 LuCI 里改和在 SupaCudy 里改，看到的是同一份数据。
3. **API 按任务设计，不按配置文件设计。** 前端调用的是"连接这个 WiFi 做中继""导入这份 WireGuard 配置"这样的高层操作；拆成哪些 UCI 改动、要重启哪些服务，由 rpcd 插件负责。
4. **软件包与 CPU 架构无关。** 只用前端静态文件、ucode 和 shell，打包为 `PKGARCH:=all`，不需要交叉编译，同版本 OpenWrt 的其他设备也能装。
5. **LuCI 始终保留。** SupaCudy 不覆盖的设置，用户随时可以去 LuCI 里改。

## 三个软件包

| 包 | 安装到 | 职责 |
|---|---|---|
| `supacudy-base` | `/etc/uci-defaults/`、`/etc/supacudy_version` | 首次启动时的默认配置、版本信息，以后还有按键脚本和各功能的胶水逻辑 |
| `supacudy-rpcd` | `/usr/share/rpcd/ucode/`、`/usr/share/rpcd/acl.d/` | 对前端暴露的 `supacudy` ubus 对象，以及允许前端调用哪些对象的 ACL |
| `supacudy-ui` | `/www/supacudy/` | 编译好的前端 |

## 认证

沿用 OpenWrt 的 rpcd 会话：前端用 `session.login` 登录，拿到 `ubus_rpc_session` 后带着它调用其他接口。权限由 `acl.d/supacudy.json` 声明，root 用户默认拥有全部 ACL 分组。

## API 约定

- 所有自有接口挂在 ubus 对象 `supacudy` 下，方法名用小写加下划线，例如 `supacudy.info`、`supacudy.repeater_scan`。
- 每个新方法都要在 ACL 里登记，读操作放 `read`，会改配置的放 `write`。
- 能直接用 OpenWrt 自带对象的（`system.info`、`network.interface.*` 等）就直接用，不重复封装。
