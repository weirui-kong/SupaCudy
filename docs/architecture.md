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
5. **LuCI 始终保留。** SupaCudy 不覆盖的设置，用户随时可以去 LuCI 里改。http://路由器/ 默认打开 SupaCudy（`supacudy-ui` 的 `93-supacudy-ui` 让 uhttpd 先找 `/www/supacudy-start.html`，LuCI 的 `/www/index.html` 不动）；侧边栏左下角和“更多”页有“原生 OpenWrt”入口，打开前提示那里的修改可能导致无法启动或网络异常、不在保证范围内。

## 三个软件包

| 包 | 安装到 | 职责 |
|---|---|---|
| `supacudy-base` | `/etc/uci-defaults/`、`/etc/supacudy_version` | 首次启动时的默认配置、版本信息，以后还有按键脚本和各功能的胶水逻辑 |
| `supacudy-rpcd` | `/usr/share/rpcd/ucode/`、`/usr/share/rpcd/acl.d/` | 对前端暴露的 `supacudy` ubus 对象，以及允许前端调用哪些对象的 ACL |
| `supacudy-ui` | `/www/supacudy/`、`/www/supacudy-start.html` | 编译好的前端，以及让根地址打开它的起始页 |

## 认证

沿用 OpenWrt 的 rpcd 会话：前端用 `session.login` 登录，拿到 `ubus_rpc_session` 后带着它调用其他接口。权限由 `acl.d/supacudy.json` 声明，root 用户默认拥有全部 ACL 分组。

## API 约定

- 所有自有接口挂在 ubus 对象 `supacudy` 下，方法名用小写加下划线，例如 `supacudy.info`、`supacudy.repeater_scan`。
- 每个新方法都要在 ACL 里登记，读操作放 `read`，会改配置的放 `write`。
- 能直接用 OpenWrt 自带对象的（`system.info`、`network.interface.*` 等）就直接用，不重复封装。

## 出厂默认和救援模式

- **出厂登录**：root 密码为空时设为 `supacudy`，并把生成的 shadow 记录存到 `/etc/supacudy/default-password`，用来判断出厂密码是否仍在使用（只在完成设置前通过 `setup_status.default_password` 告诉登录页）。`92-supacudy-adguard` 用预先算好的 bcrypt 哈希给 AdGuard Home 同样的登录。
- **出厂默认**（`supacudy-base` 的 `91-supacudy-defaults`）：LAN 为 192.168.200.1，所有射频开启名为 SupaCudy 的无密码 Wi-Fi，无线国家/地区为 CN。只作用于 OpenWrt 自己的出厂配置（LAN 仍是 192.168.1.1、Wi-Fi 未改过），保留设置升级时不会改动用户配置。
- **救援模式**（`/usr/libexec/supacudy/rescue.uc`，由 `supacudy-rescue` 服务每 30 秒调用一次）：
  - 路由器自己的 LAN DHCP 关闭（例如接入点模式）且连续两次探测不到其他 DHCP 服务器时，在 br-lan 上临时增加 192.168.200.1/24（被占用则顺延到 192.168.201.1 等）和一个只绑定 br-lan 的独立 dnsmasq，租期 2 分钟。
  - 开机两分钟后，连续三次检查都没有任何接入点在工作、LAN 口也没有网线时，在 2.4 GHz 射频上临时开启无密码的 SupaCudy-Rescue。
  - 状态指示灯改为快闪（设备树中的 led-running，没有则用第一个 LED）。
  - 所有改动都只在运行时：不写 /etc/config，重启后从用户的配置重新开始；连续两次检查都不再需要时自动退出。界面和登录页会显示救援模式横幅。

## AdGuard Home

- 链路：设备 → AdGuard Home（53 端口）→ dnsmasq（5353 端口）→ 上游。dnsmasq 照常负责本地主机名、DNS 页面的各种模式和 VPN 的 DNS。
- **AdGuard Home 自己的配置是唯一来源**，这是原则 2 的例外：UCI 里只存“是否作为路由器的 DNS”（`supacudy.adguard.enabled`）。防护开关、拦截列表、自定义规则和统计都通过它在 127.0.0.1:3000 的 API 实时读写（`curl`），在它自己的页面里做的修改会直接显示在 SupaCudy 里，也不会被覆盖。读不到时返回 null，界面不显示猜测的值。
- `/etc/adguardhome.yaml` 只在不存在时生成一次初始内容，之后归 AdGuard Home 管理。
- **统一密码**：AdGuard Home 的用户是 root，密码就是管理密码。每次在 SupaCudy 里改管理密码（`password_set`），浏览器同时用 bcryptjs 算出 bcrypt 哈希（路由器上没有可用的工具）一起发送；路由器改 root 密码后停掉 AdGuard Home，只按行改 YAML 里的 `users`，再启动。它的 API 也因此需要登录，所以明文密码另存在只有 root 可读的 `/etc/supacudy/adguard.curl`，供 `curl -K` 使用，不出现在命令行和日志里。同时记录当时 root 的 shadow 记录；之后发现不一致（在 `passwd` 或 LuCI 里改了密码），界面会请用户输入一次当前密码来同步。
- **打开它自己的页面**：只把 YAML 里的 `http.address` 在 127.0.0.1:3000 和 0.0.0.0:3000 之间切换。WAN 区默认拒绝入站，页面只在局域网可达。

## Tailscale

- `remote.uc`：开启后启动 tailscaled，并在后台执行 `tailscale up --reset --accept-dns=false --accept-routes=false --advertise-routes=<LAN 网段或空>`；它会一直等用户登录，登录链接从 `tailscale status --json` 的 AuthURL 读出，界面只显示 `https://login.tailscale.com/` 开头的链接。
- `tailscale0` 有自己的防火墙区域 `tailscale`：允许访问路由器本身；只有开启“共享我的网络”时才允许转发到 LAN（作为 subnet router，路由需在 Tailscale 管理后台批准）。
- 只做 Tailscale，不做 ZeroTier。

## IPv6 与 VPN

- IPv6 沿用 OpenWrt 默认（wan6 + odhcpd）。
- VPN 连接时，如果配置没有 IPv6 地址（WireGuard 的地址里没有 IPv6；OpenVPN 文件里没有 `ifconfig-ipv6` / `route-ipv6`），IPv6 会绕过隧道走普通线路，所以：全局模式下加一条 fw4 规则 `supacudy_vpn_no6` 拒绝 LAN→WAN 的 IPv6；按设备分流时由 policy.uc 丢弃被选设备不走隧道的 IPv6（分流用的路由表只有 IPv4）。配置有 IPv6 地址时 VPN 区域打开 `masq6`。

## 网络出口检测与切换

`supacudy-failover` 服务每 10 秒运行一次 `/usr/libexec/supacudy/failover.uc`，在已连接的出口（有线 `wan`/`wan6`、中继 `wwan`/`wwan6`、手机共享 `tethering`/`tethering6`）中，分别为 IPv4 和 IPv6 选出优先级最高、且能上网的那个。设置在 `supacudy.failover`（优先级 `order`、切换时断开旧连接 `reset_connections`、检测地址 `target4`/`target6`），状态写在 `/var/run/supacudy/failover.json`，界面通过 `uplinks_get`/`uplinks_set` 读写。

- **判定**：通过该出口 ping 检测地址（默认 223.5.5.5、1.1.1.1、8.8.8.8 和 2400:3200::1、2606:4700:4700::1111、2001:4860:4860::8888），任一回应即为可用。IPv4 按接口发出，IPv6 按该出口的源地址发出（netifd 的 IPv6 默认路由只匹配出口自己的源地址）。连续 3 次失败判定不可用，连续 5 次成功才恢复；新连上的出口按第一次检测结果判定。正在使用的出口每次都检测，备用出口每 3 次检测一次（节省手机流量），出问题或有更高优先级的出口待恢复时每次都检测。
- **切换**：不改配置、不重启接口，只加我们自己的默认路由（`proto 99`，度量值 5）。netifd 的基础度量值按优先级排列（有线 10、中继 20、手机共享 30），VPN 的默认路由（度量值 0）仍优先。所有出口都不通时，IPv4 保留在优先级最高的已连接出口上，不会没有默认路由。
- **局域网 IPv6**：跟着 IPv6 出口走。出口有委派前缀时，局域网只通告它的前缀（`lan.ip6class`），其他出口的前缀立即废弃；出口没有前缀时，局域网只用 ULA，并在该出口上做 NAT66（自有 nft 表 `ip6 supacudy_nat66`，只转换 ULA 源地址）；没有任何出口的 IPv6 可用时，路由通告的 router lifetime 设为 0（`dhcp.lan.ra_lifetime`），设备马上改用 IPv4。改过的这两项原值记在 `/etc/supacudy/failover-orig.json`，恢复正常或服务停止时还原。
- **切换后**：开启“切换时断开旧连接”（默认）时，用 `conntrack -D` 删除经旧出口出去的连接（按旧出口地址和它的委派前缀），设备立即从新出口重连；有 VPN 时重新拉起隧道，让它连到服务器的路由走新出口。
- 接入点模式下不工作。

## VPN 与 DNS

- 全局模式 + 自动 DNS 时，dnsmasq 只用 VPN 配置的 DNS（WireGuard 配置里的；OpenVPN 文件里的 `dhcp-option DNS`，以及服务器连上后下发的，由 `/etc/hotplug.d/openvpn/30-supacudy-dns` 交给 `vpn-dns.uc`）。AdGuard Home 仍在最前面过滤。
- VPN 服务器的域名（如果是域名）在隧道建立前就要解析，所以这一个域名交给出口的 DNS（`server=/域名/出口 DNS`），出口 DNS 变化时由 `/etc/hotplug.d/iface/30-supacudy-vpn-dns` 更新。
- 开启断网保护时，加一条 fw4 规则 `supacudy_vpn_dns`：路由器发往 VPN DNS 服务器的 53/853 端口只能走隧道，隧道不在时直接拒绝，不会从普通线路泄露查询的域名（和出口 DNS 相同的地址除外）。
- 按网站分流：dnsmasq 把网站的地址加入 `inet supacudy_vpnroute` 的 `vpn_dns` 集合；这个集合在规则重新加载时保留，只在网站列表变化时清空。连接、断开、修改 VPN 选项后都会清掉 AdGuard Home 的缓存，让查询重新经过 dnsmasq。
