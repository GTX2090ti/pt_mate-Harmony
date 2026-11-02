# Git Hook 机制说明（本仓库现状）

> 实测时间：2026-06-17 引入、2026-10-17 复核。环境：Windows 10 + Git 2.55.0.windows.2，仓库 `D:\PT-MATE`，分支 `master`，HEAD `4db2f43`。
> 文中所有事实均来自当场的命令输出；每条结论后面标了复核命令。

## 1. 结论速览

| 问题 | 答案 |
| --- | --- |
| 仓库里有几个版本化 hook | **1 个**：[.githooks/pre-commit](../.githooks/pre-commit)（无 `pre-push`、无 `commit-msg`、无 `pre-commit` 之外的任何脚本） |
| hook 是什么时候「推送」进来的 | 由上游提交 `fcffadb chore: add versioned pre-commit hook`（作者/提交者 liyuzhe，**2026-06-17 11:01:32 +0800**）引入，同一提交还改了 `README.md` 与 `README.zh-CN.md`（各 +8 行）。此后**没有任何提交再改动过这个文件**。它在 `origin/master` 和 `upstream/master` 上都存在，属于上游就带来的资产，不是本 fork 新写的 |
| 它现在生效吗 | **不生效**。`core.hooksPath` 在 local/global/system 三个作用域都没配置，而 `.git/hooks/` 目录下只有 Git 自带的 `*.sample` 文件 —— 也就是说这台机器上一次 `git commit` 都没跑过这个 hook |
| 启用方式 | `git config core.hooksPath .githooks`（克隆后每人执行一次，Git 不会自动接管版本库里的 hook 目录） |
| 启用前的最大风险 | hook 会对**本次暂存的每个 `.dart` 文件**执行 `dart format` 并重新 `git add`。本仓库在 HEAD 上并不是 format-clean 的（见 §5.1），启用后会刷出大片无关 diff |

## 2. hook 干了什么

脚本只有两个相互独立的触发块，整体 `exit 0` 收尾；任何一块失败都 `exit 1` 并**取消本次提交**（`pre-commit` 的非零退出码会让 `git commit` 中止，提交不会发生）。

### 2.1 Dart 格式化块

[.githooks/pre-commit:3-14](../.githooks/pre-commit#L3-L14)

```sh
if git diff --cached --name-only --diff-filter=ACMR -- '*.dart' | grep -q .; then
    git diff --cached --name-only --diff-filter=ACMR -z -- '*.dart' | xargs -0 dart format
    ...
    git diff --cached --name-only --diff-filter=ACMR -z -- '*.dart' | xargs -0 git add
fi
```

- `--diff-filter=ACMR` = 只看**新增 / 复制 / 修改 / 重命名**的 `.dart`，被删除的文件不会进入格式化列表（否则 `dart format` 会因文件不存在而报错）。
- 判定用 `grep -q .` 先探一次非空，避免空列表时 `xargs -0 dart format` 不带参数、变成「格式化当前目录」或直接报错。
- 第二次 `git add` 是把格式化结果并入**本次**提交，所以提交内容 = 格式化后的代码，而不是你原本写的版本。

### 2.2 站点清单再生成块

[.githooks/pre-commit:17-34](../.githooks/pre-commit#L17-L34)

```sh
if git diff --cached --name-only | grep -q ^assets/; then
    ./generate_sites_manifest.sh
    ...
    git add assets/sites_manifest.json
fi
```

- 触发条件是「暂存区里有任何 `assets/` 开头的路径」，**不限于 `assets/sites/`**。改一张图标、动一个 i18n json 同样会触发清单再生成。
- 这里没用 `--diff-filter`，所以删除 `assets/` 下文件时也会跑一次脚本。
- [generate_sites_manifest.sh](../generate_sites_manifest.sh) 本身 `set -e`，扫描 `assets/sites/*.json` 产出 `assets/sites_manifest.json`；脚本末尾的 JSON 格式校验只是可选增强（`command -v python3` / `node`，都没有就打印提示跳过），不是必需依赖。

## 3. 触发时机（「什么时候跑」）

- `pre-commit` 由 **`git commit`** 调用（含 `git commit --amend`），发生在提交对象写入之前、`commit-msg` 之前。
- **`git push` 不会触发它。** push 阶段对应的是 `pre-push` hook，本仓库 `.githooks/` 里没有这个文件，`.git/hooks/pre-push.sample` 只是 Git 安装时自带的样例、从未启用。
- 跳过方式两种：单次 `git commit --no-verify`（同时跳过 `pre-commit` 和 `commit-msg`）；永久 `git config --unset core.hooksPath`。
- 版本化目录不会自动生效：Git 读取的是 `core.hooksPath`（≥2.9 才有该配置项），仓库里放 `.githooks/` 只是把脚本纳入版本管理，**每台机器、每个 worktree 都要各自配置一次**。

复核命令：

```bash
git config --get core.hooksPath          # 空 = 未启用
ls .git/hooks                            # 只有 *.sample = 无生效 hook
git config --list --show-origin | grep -i hooks   # 查所有作用域
```

## 4. 溯源信息

```bash
git log --format='%h %ad %an %s' --date=iso -- .githooks
# fcffadb 2026-06-17 11:01:32 +0800 liyuzhe chore: add versioned pre-commit hook

git show --stat --format='' fcffadb
#  .githooks/pre-commit | 36 ++++
#  README.md            |  8 ++++++++
#  README.zh-CN.md      |  8 ++++++++

git branch -a --contains fcffadb
# master、sync/upstream-v2.29.3、remotes/origin/master、remotes/upstream/master

git ls-tree HEAD .githooks/pre-commit
# 100755 blob a399d51... —— 可执行位是随提交保存的，克隆后无需再 chmod
```

一句话回答「hook 是什么时候推送的」：**2026-06-17 由上游 `fcffadb` 提交并推送到 `upstream/master`，本 fork 通过同步上游拿到；Git 本身不记录 push 动作的时间戳，能查到的只有提交的 author/commit 时间。**

## 5. 启用前必须知道的三件事

### 5.1 本仓库不是 format-clean 的（实测）

用仓库移植鸿蒙所用的 Dart SDK 直接检测（`--output=none` 只报告、不改文件）：

```bash
DART=D:/HarmonyDev/flutter_flutter_341/bin/cache/dart-sdk/bin/dart.exe
"$DART" --version                              # Dart SDK version: 3.11.5 (stable)
"$DART" format --output=none --set-exit-if-changed lib
# Formatted 112 files (51 changed) in 1.15 seconds.
```

**112 个 lib 文件里 51 个不满足 `dart format`**。因此 hook 一旦启用，你只是改三行逻辑，提交里就会混进整个文件的排版重排。[AGENTS.md](../AGENTS.md) 与项目记忆里的既有约定是「手工保持 80 列风格、不跑 `dart format`」，与本 hook 的行为直接冲突。

> 如果要启用，建议先做一次独立的 `dart format .` 全量提交把基线拉平，再开 hook；否则保持 `core.hooksPath` 不设置，改由提交前手工执行 `./generate_sites_manifest.sh`。

### 5.2 `git add` 会把未暂存的改动一起卷进本次提交

这是 `git add <file>` 这种「按文件重新入暂存」写法的固有问题：如果你对某个 `.dart` 文件做了**部分暂存**（`git add -p` 只选了其中几个 hunk，工作区还留着其余未提交的修改），hook 格式化后的 `git add` 会把该文件**全部**工作区内容写入暂存区。结果是本次提交包含了你并不打算提交的改动，而本次不会有任何报错提示。

### 5.3 `dart` / `flutter` 必须在执行提交的那个 shell 的 PATH 里

hook 用的是裸命令 `dart format`。在本次复核所在的 Qoder Bash 会话里，`command -v dart` 和 `command -v flutter` 都为空（鸿蒙工具链是通过 `D:\tmp\ohenv.sh` 这类 env 包装脚本临时挂 PATH 的，不是全局配置）。在这种环境下如果启用了 hook，任何一次改 `.dart` 的提交都会走到 §2.1 的非零分支 → `dart format 执行失败，提交已取消`。

## 6. 文档漂移现状

同一个 hook，仓库里现在有三套互相不一致的说法：

| 位置 | 内容 | 状态 |
| --- | --- | --- |
| [docs/README-zh-CN-archived.md:86-90](./README-zh-CN-archived.md#L86-L90)、[docs/README-EN-archived.md:88-92](./README-EN-archived.md#L88-L92) | 「本仓库使用版本化的 Git hook…克隆后执行一次 `git config core.hooksPath .githooks`」 | 由 `fcffadb` 写入，但所在 README 已被归档到 `docs/*-archived.md`，实际不再出现在主文档路径上 |
| `README.md`（仓库根） | `grep -i hook` 无任何命中 | **当前根 README 完全没提 hook** |
| [docs/DEVELOPMENT_GUIDE.md:44](./DEVELOPMENT_GUIDE.md#L44) | 「可选：在 `.git/hooks/pre-commit` 添加自动更新脚本」 | 指的是把脚本直接放进 `.git/hooks/`（本地、不版本化），与 `.githooks/` + `core.hooksPath` 是两套不同做法 |

另外：该 hook 只做了 `dart format` 和站点清单再生成，**不跑** `flutter analyze`、**不跑** `flutter test`，也不是 CI。验收基线仍以 [AGENTS.md](../AGENTS.md) 的构建/测试命令为准。

## 7. 常用操作

```bash
# 启用
git config core.hooksPath .githooks

# 停用（保留文件，只是不再执行）
git config --unset core.hooksPath

# 确认 Git 实际会去哪个目录找 hook
git config --get core.hooksPath && ls -l "$(git rev-parse --show-toplevel)/.githooks"

# 单次绕过
git commit --no-verify -m "..."

# 只看 hook 会挑中哪些文件（不执行格式化）
git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
git diff --cached --name-only | grep '^assets/' || echo '(不触发清单生成)'
```
