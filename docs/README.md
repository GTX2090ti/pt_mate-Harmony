# PT-Mate 文档索引

本目录是 PT-Mate 的文档中心。按用途分组列出全部文档，每项附一句话说明。项目概览请先看仓库根目录的 [README](../README.md)。

## 快速上手

- [使用指南](./USER_GUIDE.md)：面向最终用户的操作说明（搜索、左滑手势、日志诊断、搜索分类参数、NexusPHP Web 登录）。
- [支持网站清单](./SUPPORTED_SITES.md)：当前 `assets/sites/*.json` 中已适配站点的分类清单（由配置自动统计，适配新站点后需更新）。

## 开发与测试

- [开发指南](./DEVELOPMENT_GUIDE.md)：项目结构、技术栈、环境搭建、构建命令与新站点适配流程。
- [Git Hook 机制说明](./GIT_HOOKS.md)：`.githooks/pre-commit` 的行为、启用方式、风险与现状复核（实测记录）。
- [Android 安全存储真机验收](./ANDROID_SECURE_STORAGE_DEVICE_TEST.md)：安全存储两阶段发布开关、隔离测试包构建与真机验收流程。

## 站点配置

- [网站配置文件编写指南](./SITE_CONFIGURATION_GUIDE.md)：站点 JSON 的字段说明、`infoFinder`/`request` 等提取与请求规则、各站点类型差异与适配步骤。适配 NexusPHPWeb 站点时可参考项目内置的 `nexusphpweb-site-config` 技能。

## API

- [Gazelle API](./api/Gazelle_API.md)：Gazelle 站点 JSON API（认证、`ajax.php?action=*` 各端点与响应结构）。
- [ROUSI API V1](./api/ROUSI_API_V1.md)：RousiPro 站点公开 API v1（Passkey 认证、用户/种子/分类端点、错误码与调用示例）。

## 版本记录与专题

- [修改记录（2026-09）](./pt_mate_修改记录_2026-09.md)：2026 年 9 月功能新增与修复汇总（同名 `.docx` 为其导出副本，内容以本 `.md` 为准）。
- [ohos-v1.2.1 备份导出修复](./ohos-v1.2.1-备份导出修复.md)：鸿蒙平台导出备份失败的根因链与修复说明（提交 `4db2f43`）。

## 归档

- [旧版英文介绍（归档）](./README-EN-archived.md)：历史根 README 英文版快照，站点清单等数据已过时，仅供查阅。
- [旧版中文介绍（归档）](./README-zh-CN-archived.md)：历史根 README 中文版快照，站点清单等数据已过时，仅供查阅。

> 归档文件保留在 `docs/` 根目录而未移入子目录，因为仓库根 [README](../README.md) 仍直接链接它们；移动前需先更新根 README 的引用。

## 文档维护

- [docs 整理报告](./DOCS_MAINTENANCE_REPORT.md)：2026-11 文档整理的改动清单、理由、遗留问题与后续建议。
