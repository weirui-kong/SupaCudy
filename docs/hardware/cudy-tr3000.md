# Cudy TR3000

## 硬件

| 项目 | 规格 |
|---|---|
| SoC | MediaTek MT7981B |
| 内存 | 512MB |
| 闪存 | 128MB 或 256MB SPI NAND（两个版本，镜像不通用）；**SupaCudy 只支持 256MB 版** |
| 无线 | MT7976CN，2.4G + 5G |
| 网口 | 1 × 2.5G（RTL8221B），1 × 1G |
| USB | 1 × USB 3.0 |

## 对应的构建配置

OpenWrt 24.10.8 里有三个 TR3000 的 profile：

| OpenWrt profile | SupaCudy 配置 | 说明 |
|---|---|---|
| `cudy_tr3000-v1` | 不支持 | 128MB 版 |
| `cudy_tr3000-256mb-v1` | `cudy-tr3000-256mb-v1` | 256MB 版，沿用 Cudy 原厂 U-Boot |
| `cudy_tr3000-v1-ubootmod` | 不支持 | 128MB 版，需要先换成 OpenWrt 的 U-Boot 和分区布局 |

**128MB 和 256MB 的镜像不能混刷，SupaCudy 只提供 256MB 版镜像。** 确认闪存容量的办法：在原厂固件的状态页或 OpenWrt 的 `cat /proc/mtd` 里看分区大小。

## 刷机前必看

1. **新批次闪存。** Cudy 公告说，2025 年 11 月起生产的 TR3000 v1 换成了 F50L1G41LC 闪存，装这颗闪存的机器不能降级到 2.3.x 及更早的原厂固件，旧版 OpenWrt 过渡固件和旧版 OpenWrt 也无法启动。如果你的机器是这个批次，刷之前先确认我们使用的 OpenWrt 版本已经支持它。
2. **先备份 factory 分区。** 里面是无线校准数据和 MAC 地址，丢了无线就废了，每台机器的数据都不一样，无法从别处补回。刷 OpenWrt 后执行：

   ```sh
   cat /proc/mtd                      # 找到 factory 分区，例如 mtd2
   cat /dev/mtd2 > /tmp/factory.bin   # 按实际编号替换
   ```

   然后把 `/tmp/factory.bin` 拷到电脑上保存。
3. **刷机路径。** 首次从原厂固件切换到 OpenWrt，按 [OpenWrt 的 TR3000 设备页](https://openwrt.org/toh/cudy/tr3000) 和 Cudy 官方提供的 OpenWrt 过渡固件操作。已经运行 OpenWrt 之后，就可以直接用 SupaCudy 的 `*-squashfs-sysupgrade.bin` 升级。
4. **准备救砖手段。** 建议备一个 USB 转 TTL 串口，出问题时可以看启动日志，必要时通过 UART 恢复。
