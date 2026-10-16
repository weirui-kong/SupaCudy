# 模拟器

在本机用 QEMU 跑一台完整的 OpenWrt 虚拟机，装着 SupaCudy，周围用虚拟网卡和网络命名空间搭出"上游热点、手机、笔记本、NAS"，用来在没有真机的情况下开发和测试网络功能。

```bash
scripts/emulator.sh build          # 打包并构建模拟器镜像（第一次或改了代码后）
scripts/emulator.sh start          # 启动；--fresh 恢复成全新磁盘
scripts/emulator.sh stop
scripts/emulator.sh ssh            # 进入虚拟机的 shell
scripts/emulator.sh console        # 看串口启动日志
```

启动后打开 <http://127.0.0.1:8088/supacudy/>，密码 `supacudy-test`。LuCI 在 <http://127.0.0.1:8088/>。

需要：Docker（构建镜像）和 QEMU（`brew install qemu`）。Apple Silicon 上用 HVF 硬件加速，启动约 10 秒。

## 不影响宿主机网络

- 只用 QEMU 的用户态网络（slirp）：NAT、DHCP 都在 QEMU 进程里完成，不创建任何虚拟网卡、不改路由、不需要 root。
- 端口转发只监听 `127.0.0.1`，局域网里的其他设备访问不到。
- 管理口开了 `restrict=on`，虚拟机不能通过它访问外部。
- 下面所有网段都只存在于虚拟机内部，并且避开了 192.168.0.x–192.168.102.x。

## 网络拓扑

```
            宿主机 127.0.0.1:8088 / :2222
                         │ （QEMU 端口转发）
                    eth1 mgmt 10.250.3.15
                         │
  QEMU NAT ── eth0 WAN ──┤ SupaCudy 路由器 ├── br-lan 192.168.200.1/24
  10.250.2.0/24          │                 │      ├── laptop（有线，Work-Laptop）
  （可上网）              │                 │      └── nas（有线，Home-NAS）
                         │                 │
                    phy0 2.4G AP "SupaCudy-Emu" ──── phone（WiFi 客户端，Pixel-Phone）
                    phy1 5G  AP "SupaCudy-Emu-5G"
                         │
                    veth-uplink 10.250.10.1/30
                         │
                    upstream（"酒店"）
                      phy3: "Hotel-WiFi"（WPA2，密码 hotel-guest）10.250.11.0/24
                            "Cafe-Free"（开放）                10.250.12.0/24
                      经 uplink 走路由器的 WAN 上网
```

| 网段 | 用途 |
|---|---|
| 192.168.200.0/24 | 路由器 LAN（真机默认是 192.168.1.0/24，这里刻意改开） |
| 10.250.2.0/24 | WAN，QEMU 的 NAT 网络，DNS 在 10.250.2.3 |
| 10.250.3.0/24 | 管理口，只用于宿主机访问 |
| 10.250.10.0/30 | 上游热点的出口（veth） |
| 10.250.11.0/24、10.250.12.0/24 | 上游两个热点给连上来的设备（包括中继时的路由器）分配的地址 |

## 虚拟 WiFi

内核模块 `mac80211_hwsim` 虚拟出 4 块无线网卡，它们共享一个"空气"，彼此真的能扫描、关联、传数据：

| 射频 | 归属 | 角色 |
|---|---|---|
| phy0 | 路由器 | 2.4GHz，信道 6，主 WiFi "SupaCudy-Emu"（密码 `supacudy-wifi`）；中继时也用它 |
| phy1 | 路由器 | 5GHz，信道 36，"SupaCudy-Emu-5G" |
| phy2 | phone 命名空间 | 连接路由器 2.4GHz 的手机 |
| phy3 | upstream 命名空间 | 两个上游热点，供中继功能扫描和连接 |

## 能测和不能测的

| 能测 | 不能测（需要 TR3000 真机） |
|---|---|
| 有线 WAN 的 DHCP / 静态 IP、上网检测 | MT7981 / MT7976 驱动的具体行为、WPA3 兼容性 |
| 中继：扫描、连接、断开、自动切换 | 2.5G 网口、交换芯片 |
| 无线设置、访客网络 | 按键、LED |
| 客户端列表、速度、流量、禁止上网、限速 | 硬件加速 |
| LAN 网段、DHCP 保留、防火墙 | 闪存分区、真实的固件升级 |
| 配置保存、服务重启、恢复出厂 | USB 手机共享 |

## 构建方式

`profiles/emulator.conf` 用 OpenWrt 的 armsr/armv8 目标（通用 arm64 虚拟机）构建，加上 hwsim、完整版 wpad、iw、ip-full、veth 等软件包，以及 `emulator/files/` 里的覆盖文件：

| 文件 | 作用 |
|---|---|
| `etc/uci-defaults/95-supacudy-emulator` | 首次启动时设置网口、网段、防火墙区域、主机名和测试密码 |
| `etc/modules.d/mac80211-hwsim` | 让 hwsim 创建 4 块射频 |
| `etc/init.d/supacudy-emulator` | 每次启动时搭建上游热点、手机和有线客户端 |
| `usr/libexec/supacudy-emulator/` | 模拟客户端用的 DHCP 脚本、背景流量、热点地址维护 |

这些文件只进模拟器镜像，不会进 TR3000 固件。
