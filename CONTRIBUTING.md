# 贡献指南

欢迎提交 issue 和 pull request。

## 提交 issue

- 问题：说明固件版本（概览页的 SupaCudy 版本）、操作步骤、看到的结果和期望的结果；有日志时附上「日志」页导出的内容，并删掉其中的密码、公网地址等个人信息。
- 新功能：说明使用场景。SupaCudy 覆盖常用操作，不打算包含 OpenWrt 的全部选项，少用的设置请用 LuCI。

## 提交代码

1. 开发环境和常用命令见 [开发指南](docs/development.md)。
2. 先读 [项目规则](docs/rules/)：产品、编码、测试和协作规则都适用于所有提交。
3. 每个改动都带测试，按类别放在对应目录（见 [测试规则](docs/rules/testing.md)）。修复问题时先写能复现它的测试。
4. 界面文字同时提供简体中文和英文，页面在手机和桌面、浅色和深色下都要可用。
5. 提交信息用英文，遵循 Conventional Commits，例如 `feat(rpcd): add repeater_scan`、`fix(ui): ...`。
6. 启用 pre-push 钩子（`git config core.hooksPath .githooks`），`scripts/test.sh` 全部通过后再推送。

只能在真机上验证的改动（无线、网口、USB、按键等），请在提交信息里写明测过 [硬件检查清单](docs/hardware/) 里的哪些项。

## 许可证

提交的代码以 [Apache-2.0](LICENSE) 授权，源文件开头带 `SPDX-License-Identifier: Apache-2.0`。
