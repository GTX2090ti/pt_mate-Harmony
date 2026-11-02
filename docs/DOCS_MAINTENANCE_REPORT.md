# docs 整理报告

整理时间：2026-11-02。范围仅限 `docs/` 目录；未修改任何代码、`assets/`、根 README 等 docs 以外文件，未执行任何 Git 操作。

## 一、各文档定位评估

| 文档 | 定位 | 状态 |
| --- | --- | --- |
| [README.md](./README.md) | 文档目录 | 原来只有 8 行简单列表，本次重写为分组索引 |
| [USER_GUIDE.md](./USER_GUIDE.md) | 用户操作手册 | 现行有效，无需改动 |
| [DEVELOPMENT_GUIDE.md](./DEVELOPMENT_GUIDE.md) | 开发者指南 | 基本有效；hook 描述与 `.githooks/` 现状不一致，已修正 |
| [GIT_HOOKS.md](./GIT_HOOKS.md) | 专题实测记录 | 有效且严谨；全部内链指向旧机器绝对路径 `file:///D:/PT-MATE/`，已修复 |
| [SITE_CONFIGURATION_GUIDE.md](./SITE_CONFIGURATION_GUIDE.md) | 站点配置规范 | 有效；两处过时/错误描述，已修正 |
| [SUPPORTED_SITES.md](./SUPPORTED_SITES.md) | 站点清单快照 | 与 `assets/sites/*.json`（41 个）一致，未改动；属手工维护、易漂移 |
| [ANDROID_SECURE_STORAGE_DEVICE_TEST.md](./ANDROID_SECURE_STORAGE_DEVICE_TEST.md) | 安全存储真机验收流程 | 有效，未改动；内容绑定具体构建号（+183/+184），随时间会过时 |
| [ohos-v1.2.1-备份导出修复.md](./ohos-v1.2.1-备份导出修复.md) | 版本修复专题记录 | 有效，未改动 |
| [pt_mate_修改记录_2026-09.md](./pt_mate_修改记录_2026-09.md) | 2026-09 修改记录 | 已规范化，并补入 docx 独有内容（见下） |
| [pt_mate_修改记录_2026-09.docx](./pt_mate_修改记录_2026-09.docx) | 同名 .md 的导出副本 | 保留原文件；正文以 .md 为准 |
| [README-EN-archived.md](./README-EN-archived.md) | 旧版根 README 快照 | 已加归档标注、修复内链；未移动位置（见问题 1） |
| [README-zh-CN-archived.md](./README-zh-CN-archived.md) | 旧版根 README 快照 | 同上 |
| [api/Gazelle_API.md](./api/Gazelle_API.md) | Gazelle JSON API 参考 | 有效，未改动 |
| [api/ROUSI_API_V1.md](./api/ROUSI_API_V1.md) | RousiPro API v1 参考 | 有效，未改动 |

## 二、改动清单与理由

1. **重写 [docs/README.md](./README.md)**
   - 原文件只是平铺列表且缺半数文档（归档 README、修改记录、验收文档等）。
   - 现按用途分组（快速上手 / 开发与测试 / 站点配置 / API / 版本记录与专题 / 归档 / 文档维护），每项一句话说明 + 相对链接，并注明 docx 为导出副本、归档文件未移入子目录的原因。

2. **规范化 [pt_mate_修改记录_2026-09.md](./pt_mate_修改记录_2026-09.md)**
   - 清理条目间的多余空行，统一条目编号、标点与分隔符（`添加/修复` → `一、添加 / 二、修复`）。
   - **补入 docx 独有内容**：解析 docx（标准 OOXML，可解析）后发现其比 .md 多两条信息——「修复 #4 设置入口重复」与鸿蒙适配条目中的「签名使用 HoKit 工具」。按「不删内容、优先保留」原则合并进 .md，并加注说明 .md 为规范版本。
   - docx 原样保留，不删除。

3. **修复 [GIT_HOOKS.md](./GIT_HOOKS.md) 内链**
   - 全部链接原为 `file:///D:/PT-MATE/...` 绝对路径（旧机器布局，当前仓库在 `d:\DSHX\PT-MATE`，全部失效），统一改为相对链接（`../.githooks/pre-commit`、`../AGENTS.md`、`./README-zh-CN-archived.md` 等）。正文内容未改。

4. **修正 [SITE_CONFIGURATION_GUIDE.md](./SITE_CONFIGURATION_GUIDE.md) 过时描述**
   - 「更新网站清单」一步原写为手动编辑 `assets/sites_manifest.json` 并给出错误的手写清单示例；实际清单由 `generate_sites_manifest.sh` 自动生成（与 GIT_HOOKS.md、根 README 的说法一致），已改为运行脚本。
   - 目录结构一节中「详见 readme.md」指向含混，改为指向 [GIT_HOOKS.md](./GIT_HOOKS.md)。
   - 删除文末多余的孤立 `---`。

5. **修正 [DEVELOPMENT_GUIDE.md](./DEVELOPMENT_GUIDE.md) hook 描述**
   - 原文「可选：在 `.git/hooks/pre-commit` 添加自动更新脚本」与仓库实际采用的 `.githooks/` + `core.hooksPath` 机制是两套做法（GIT_HOOKS.md §6 已指出该漂移），改为指向 [GIT_HOOKS.md](./GIT_HOOKS.md) 的准确说法。

6. **归档 README 加标注、修内链**
   - 两份 `*-archived.md` 顶部新增归档说明（快照、不再维护、数据过时），并互指对方为语言切换链接（原 `[English](./README.md)`、`[简体中文](./README.zh-CN.md)` 均为失效链接）。
   - 修复归档后失效的相对链接：`./docs/...` → `./...`、`./LICENSE` → `../LICENSE`、`screenshots/` → `../screenshots/`。正文快照内容未删改。

7. **新增 [DOCS_MAINTENANCE_REPORT.md](./DOCS_MAINTENANCE_REPORT.md)**（本文件），并在索引中登记。

## 三、发现但未处理的问题

1. **归档 README 未移入 `docs/archive/`**：根目录 `README.md`（docs 范围之外，本次不可修改）第 84-85 行仍直接链接 `./docs/README-*archived.md`，移动会立刻产生两处死链。建议后续在根 README 改链后再移动，或同时修改根 README。
2. **[SUPPORTED_SITES.md](./SUPPORTED_SITES.md) 为手工快照**：站点数（41）目前与 `assets/sites/*.json` 一致，但每次增删站点都需手改，极易漂移。建议由脚本生成（如扩展 `generate_sites_manifest.sh` 或单独脚本）。
3. **[ANDROID_SECURE_STORAGE_DEVICE_TEST.md](./ANDROID_SECURE_STORAGE_DEVICE_TEST.md) 强绑定具体构建号**（`+183`/`+184`、33 个站点、20 个 Cookie 等验收基线）：是一份「某一轮验收」的记录而非可长期复用的流程文档，随版本演进会过时。建议后续拆分为通用流程 + 每轮验收记录。
4. **[DEVELOPMENT_GUIDE.md](./DEVELOPMENT_GUIDE.md) 部分内容与现状偏浅**：项目结构树未包含 `tool/`、`server/`、`packages/`（鸿蒙插件副本）等目录；技术栈未列鸿蒙相关内容。未擅自扩写，建议按 AGENTS.md 的结构约定补充。
5. **[Gazelle_API.md](./api/Gazelle_API.md) 认证一节的示例 URL** 为 `http://<your-site>.cd/login.php` 占位写法且用 http，与如今普遍 https 不符；属上游文档快照，未改动。
6. **pt_mate_修改记录_2026-09.docx 与 .md 并存**：docx 已保留为导出副本并在 .md 与索引中注明以 .md 为准，但仓库没有机制阻止二者再次分叉。
7. **[ohos-v1.2.1-备份导出修复.md](./ohos-v1.2.1-备份导出修复.md) 文件名**为 `ohos-v1.2.1-备份导出修复.md`（小写前缀 + 中文），与其他大写英文命名风格不一致；因根 README 第 83 行直接引用该路径，且改动收益有限，本次未重命名。

## 四、后续建议补充的文档

1. **下载器（qBittorrent / Transmission）配置指南**：DEVELOPMENT_GUIDE 与 USER_GUIDE 各提了一句，但多下载器实例、本地中转下载模式均无专门文档。
2. **WebDAV 备份与 Cookie Cloud 使用及安全说明**：归档 README 中的 Cookie Cloud 安全警示非常完整，现行 USER_GUIDE 却没有对应章节，建议迁移/恢复到现行文档。
3. **server/（Go 后端）说明**：仓库包含 Go API 服务（`server/`），docs/ 中完全没有部署、接口与配置说明。
4. **鸿蒙（OHOS）适配总览**：目前只有单点修复记录（ohos-v1.2.1），缺少构建、签名（HoKit）、HAP 出包与 `packages/*_ohos` 插件的总体说明。
5. **CHANGELOG 机制**：修改记录（2026-09）为一次性文档，建议约定按月/按版本的记录文件命名规则并纳入索引分组。
