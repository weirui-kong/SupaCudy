# 给 Cudy TR3000（256MB）刷入 SupaCudy

离线可读的刷机步骤。刷机过程中电脑多半上不了网，请先把这份文档和下面"准备"里的文件都放在电脑本地。

> 只适用于 **TR3000 v1 256MB 闪存版**。128MB 版的镜像不通用，SupaCudy 也不支持。刷错型号的固件会被拒绝，不会变砖。

## 总览

| 阶段 | 路由器上运行的系统 | 地址 | 登录 |
|---|---|---|---|
| 开始 | Cudy 原厂系统 | http://192.168.10.1 | 默认密码 `admin`（或你设置过的密码） |
| 第 2 步之后 | OpenWrt 过渡固件（Cudy 提供） | http://192.168.1.1 | 用户 `root`，无密码 |
| 第 4 步之后 | SupaCudy | http://192.168.200.1 | 用户 `root`，密码 `supacudy` |

顺序：确认型号和批次 → 准备救砖包 → 刷过渡固件 → **备份分区** → 刷 SupaCudy。

## 第 0 步：确认型号和批次

1. **闪存容量**：看包装盒或机身标签，必须是 256MB 版。
2. **批次**：看序列号（SN）前 4 位。Cudy 说从 `2543` 起（下载页另写为 `2544`，即 2025 年第 44 周起）换用了新闪存 F50L1G41LC。
   - OpenWrt 从 24.10.5 起支持这颗闪存；SupaCudy 基于 24.10.8，没有问题。
   - 但旧版的 OpenWrt 过渡固件和旧版 OpenWrt 在新批次机器上**无法启动**。新批次只能用 2025-11-18 及之后的过渡固件。
3. **不要先升级原厂固件。** 有 256MB 版用户把原厂固件升级到 2.5.21（2026-07）后再刷过渡固件，结果变砖。保持现有原厂版本直接进行下一步。如果你的机器已经是很新的原厂版本且属于新批次，先向 Cudy 客服确认过渡固件适用。

## 第 1 步：准备（全部下载到电脑本地）

| 文件 / 工具 | 用途 | 来源 |
|---|---|---|
| **TR3000 256MB 原厂固件**，复制一份改名为 `recovery.bin` | 出问题时用 TFTP 恢复原厂 | Cudy 下载中心，TR3000-256MB 1.0 页面 |
| **256MB 版 OpenWrt 过渡固件** `cudy_tr3000-256mb-v1-sysupgrade.bin` | 从原厂切到 OpenWrt | Cudy "OpenWrt Software Download" 页面，**"TR3000 256 MB Flash V1"** 文件夹 |
| **SupaCudy 镜像** `openwrt-24.10.8-supacudy-mediatek-filogic-cudy_tr3000-256mb-v1-squashfs-sysupgrade.bin` | 最终系统 | 本仓库 `out/images/cudy-tr3000-256mb-v1/`（用 `scripts/build-image.sh cudy-tr3000-256mb-v1` 构建） |
| TFTP 服务器（Windows 用 Tftpd32/Tftpd64，macOS 可用自带 tftpd） | 原厂 TFTP 恢复 | — |
| 网线一根 | 刷机全程用有线 | — |
| （可选）USB 转 TTL 串口，3.3V | 严重变砖时救砖，需要拆机 | — |

核对 SupaCudy 镜像没有损坏（与同目录 `sha256sums` 里的值一致）：

```bash
cd out/images/cudy-tr3000-256mb-v1 && shasum -a 256 -c sha256sums
```

供电：使用 5V 3A 的 USB-C 电源，刷机过程中**不要断电**。

## 第 2 步：刷过渡固件（原厂 → OpenWrt）

1. 用网线连接电脑和路由器的 LAN 口，电脑设为自动获取 IP。
2. 浏览器打开 http://192.168.10.1 ，登录。
3. 进入"固件升级"（Upgrade Firmware），上传 `cudy_tr3000-256mb-v1-sysupgrade.bin`。
4. 等待约 2 分钟。原厂页面会一直显示升级中，**不用等它结束**。
5. 浏览器打开 http://192.168.1.1 ，能看到 OpenWrt 的 LuCI 页面就成功了。过渡固件默认**关闭 Wi-Fi**，必须用网线。

打不开 http://192.168.1.1 时，先拔插网线让电脑重新获取地址（应拿到 192.168.1.x），再等一两分钟。超过 5 分钟仍然不行，按下面"救砖"处理。

## 第 3 步：备份分区（最重要，不要跳过）

`factory` 分区里是这台机器独有的无线校准数据和 MAC 地址，`bdinfo` 也是本机专属，丢了无法从别处补回。在过渡固件里备份：

```bash
ssh root@192.168.1.1
```

在路由器上执行：

```bash
cat /proc/mtd
mkdir -p /tmp/bak
for n in $(sed -n 's/^\(mtd[0-9]*\):.*/\1/p' /proc/mtd); do cat /dev/$n > /tmp/bak/$n.bin; done
cat /proc/mtd > /tmp/bak/mtd-layout.txt
ls -l /tmp/bak
```

回到电脑上，把备份拷下来：

```bash
mkdir -p ~/tr3000-backup && scp -O 'root@192.168.1.1:/tmp/bak/*' ~/tr3000-backup/
```

确认 `~/tr3000-backup` 里有 `mtd-layout.txt` 和各分区文件（其中对应 `factory`、`bdinfo` 的文件不为空），把这个文件夹多存一份到别处（网盘或 U 盘）。

> **不要做** OpenWrt 网站上"换 U-Boot（ubootmod）"的步骤：那只针对 128MB 版。256MB 版保留原厂 U-Boot，才能继续使用原厂的 TFTP 恢复。

## 第 4 步：刷 SupaCudy

1. 在 http://192.168.1.1 的 LuCI 里打开"系统 → 备份/刷写固件"（System → Backup / Flash Firmware）。
2. 在"刷写新固件"处选择 SupaCudy 镜像，点"刷写镜像"。
3. 在确认页**取消勾选"保留配置"**（Keep settings），确认刷写。不保留配置，SupaCudy 的出厂默认值才会生效。
4. 等待约 3 分钟（首次启动要初始化 AdGuard Home 等组件），期间不要断电。

刷完后：

- 连接无密码的 Wi-Fi **SupaCudy**，或用网线连 LAN 口。
- 打开 http://192.168.200.1 ，用户名 `root`、密码 `supacudy` 登录。首次设置向导会要求设置新密码（不能用出厂密码），这个密码同时用于 SSH 和 AdGuard Home。
- 原生 OpenWrt（LuCI）在 http://192.168.200.1/cgi-bin/luci/ 。

以后升级 SupaCudy：在"维护"页上传新的 `*-squashfs-sysupgrade.bin` 即可。

## 救砖

按严重程度从轻到重：

### 能进系统，但设置出问题

- 在 SupaCudy 的"维护"页恢复出厂设置。
- 或进入 OpenWrt 的 failsafe 模式：开机时看到指示灯快闪的几秒内按一下 Reset 键，之后网线连接，电脑设为 192.168.1.2/24，`ssh root@192.168.1.1`，可执行 `firstboot -y && reboot` 清空配置。

### 进不了系统：用原厂 TFTP 恢复刷回原厂

这个方法只接受 **Cudy 签名的原厂固件**，不能直接刷 OpenWrt。恢复后重新从第 2 步开始。

1. 把 `recovery.bin`（256MB 原厂固件改名）放到 TFTP 服务器的目录里。
2. 电脑网线连路由器 **LAN 口**，电脑 IP 手动设为 `192.168.1.88`，子网掩码 `255.255.255.0`。
3. 启动 TFTP 服务器（Windows 需先关闭防火墙，否则会被拦截）。
4. 路由器断电。**按住 Reset 键不放**，接通电源。
5. 看到指示灯全部快闪，或 TFTP 服务器开始传输文件时，松开 Reset。
6. 指示灯变为慢闪，恢复完成。把电脑 IP 改回自动获取。

macOS 上开 TFTP 服务器的一种方式：

```bash
sudo mkdir -p /private/tftpboot && sudo cp recovery.bin /private/tftpboot/
sudo launchctl load -F /System/Library/LaunchDaemons/tftp.plist
```

恢复完关闭：`sudo launchctl unload -F /System/Library/LaunchDaemons/tftp.plist`。

### 完全没反应：串口救砖

只要串口还能看到启动日志，就能救回：

1. 拆机：撕下底部 4 个脚垫，拧下 4 颗螺丝，沿边缘撬开卡扣。
2. 串口参数 115200 8N1，3.3V。板子底面有两个测试点：网口朝左、指示灯朝右时，左边是 RX、右边是 TX。接法：串口的 TX 接路由器 RX，RX 接 TX，GND 接板上任意地。
3. 用 `mtk_uartboot` 加载内存版 BL2 和 FIP 启动，再按 OpenWrt 网站 TR3000 页面的说明恢复。这一步复杂，建议先在 OpenWrt 论坛对照你的启动日志求助。
4. 用第 3 步备份的 `factory` 等分区恢复本机专属数据。

## 刷完后的检查（建议）

- 两个网口：WAN（2.5G）接上级能上网，LAN（1G）接电脑能拿到 192.168.200.x 地址。
- Wi-Fi：2.4G 和 5G 都能连上并上网，信号正常（factory 数据有问题时 Wi-Fi 会异常）。
- 概览页：型号显示为 Cudy TR3000（256MB 版），内存约 512MB，存储数值正常。
- 广告过滤页：AdGuard Home 在运行。
- 中继：加入一个双频的上级 Wi-Fi，列表里同一名称只出现一次并显示两个频段；加入时能看到“连接中”，成功后显示获得的地址，输错密码时提示密码错误。
- 企业级 Wi-Fi（有条件时）：用 PEAP 或 TTLS 加入公司或学校网络，开启“验证服务器证书”并填写服务器域名后仍能连上。
- 设置 → 从 WAN 访问：在上级网络里的另一台设备上，网页界面默认能打开、SSH 默认连不上；分别拨动开关后结果随之变化。
- 拨动开关、Reset 键、指示灯的表现记录下来，用于后续开发。

## 参考

- OpenWrt Wiki：Cudy TR3000 — https://openwrt.org/toh/cudy/tr3000
- Cudy：从 OpenWrt 恢复到官方固件 — https://www.cudy.com/en-us/blogs/faq/how-to-recovery-the-cudy-router-from-openwrt-firmware-to-cudy-official-firmware
- Cudy：OpenWrt 软件下载（过渡固件）— https://www.cudy.com/en-us/blogs/faq/openwrt-software-download
- Cudy：TR3000 下载中心 — https://www.cudy.com/en-us/pages/download-center/tr3000-1-0
- OpenWrt 论坛：Cudy 新闪存支持 — https://forum.openwrt.org/t/cudy-started-using-a-new-flash-chip-in-their-ax3000-devices-its-currently-unsupported/243547
