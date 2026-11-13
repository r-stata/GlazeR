# GlazeR · R / Python / Stata 文件转盘

<p align="center">
  <img src="build/icon.png" width="128" alt="GlazeR 图标" />
</p>

<p align="center">
  <strong>选中文件 → 按住快捷键（可加数字键选转盘）→ 转盘弹出 → 松手到扇区，用你的 R / Python / Stata 函数或代码处理这个文件</strong><br/>
  原生 SwiftUI 开发 · 本地执行 R / Python / Stata，数据不上传 · 转盘交互参考 <a href="https://github.com/r-stata/DataWheel">DataWheel</a> / <a href="https://github.com/KnifeLemon/Filee/">Filee</a>
</p>

<p align="center"><a href="README.md">← 返回项目首页（GitHub README）</a> · <a href="MANUAL.en.md">English guide</a></p>

---

GlazeR 把 DataWheel 的「一格一格式」扩展成「**一格一函数**」：每个扇区绑定一个 R 函数、Python 函数、Stata 命令或一段自定义代码，拖进去的文件路径会自动注入，连同预设的默认参数一起执行。R 扇区可写出 `.rds / .csv / .RData / .dta`；Python 扇区还能直接调用内置的 DataWheel 格式转换，把表格文件在 CSV / TSV / XLSX / DTA / RDS / Parquet / Feather / JSON / JSONL 之间互转；Stata 扇区走 `stata-mp -b do`，可 `use` / `describe` / `summarize` 并自动写出 `.dta` / `.csv`。

**最多可配置 10 套转盘**（数字键槽位 `0–9`），按住全局组合键加数字即可直接呼出对应转盘，例如 `⌥1` 是 R 函数转盘、`⌥2` 是格式转换转盘、`⌥3` 是 Python 函数转盘、`⌥4` 是 Stata 命令转盘；同一种引擎也可以准备多套。转盘数量、扇区数量、每个扇区的引擎 / 函数 / 默认参数，全部在图形界面里自由配置。

## ✨ 功能特性

### 五种呼出方式

| 方式 | 操作 |
|---|---|
| 🖱 窗口拖放 | 把文件拖进应用窗口任意位置，转盘在光标处弹出，松手到目标扇区执行 |
| ⌨️ 修饰键 + 拖动 | 在**任意应用**（Finder / 桌面）里，按住组合键拖动文件，转盘在光标处弹出，松手到扇区执行，无需打开主窗口 |
| ⌨️ 选中文件 + 长按 | 在 Finder 选中一个或多个文件后**长按组合键**（默认 0.45 秒），转盘在光标处弹出，点击扇区即执行；自动读取 Finder 选中项 |
| 🔢 组合键 + 数字 | 在 Finder 选中文件后按住 `⌥` + `0…9`，直接呼出该槽位的转盘；支持主键盘与小键盘数字键 |
| 📋 服务菜单 / Dock | 右键文件 → 服务 → 「用 GlazeR 处理」；或把文件拖到 Dock 图标 |

数字键选中后 60 秒内，后续拖文件也会沿用这套转盘。转盘锚定在弹出位置，不会跟着鼠标乱跑；修饰键提前松开、松手到空白处、`Esc`、点击别处都会关闭转盘。

### 可配置性

- **最多 10 套转盘**：新建 / 复制 / 删除 / 重命名；每套绑定一个 `0–9` 数字键槽位，设置页有槽位总览，重复 / 越界会自动去重与补位。
- **一键预设**：「新建…」里可选空白转盘、R 函数示例、Python 函数示例、**Stata 命令示例（6 扇区）**、DataWheel 格式转换（10 扇区）。
- **扇区数量 2–12**：每套转盘自由设定；减少数量时保留前 N 个配置。
- **组合键分流**：默认全局组合键（⌥ Option）之外，每套转盘可单独绑定 ⌘ ⌃ ⌥ ⇧ ⇪ 的任意组合；按住对应组合键即呼出对应转盘，最具体的组合优先命中。
- **三引擎**：每个扇区独立选择 **R** / **Python** / **Stata**；分别走 `engine/runner.R`、`engine/runner.py`、`engine/runner.do`，三者共用同一套超时 / 取消 / 阶段事件 / 结果回收逻辑。
- **每个扇区**可配置：显示名称、悬停说明、启用状态、引擎、函数 / 自定义代码、外部脚本（`.R` / `.py` / `.do`）、文件路径形参名、默认参数、多文件处理方式、结果写出方式、输出后缀、配色。
- **路径变量自动解析**（详见下表），自定义代码、默认参数表达式、`source()` / `exec` / Stata do 文件内联代码里都能直接引用。编辑器会根据当前扇区的引擎显示对应提示。
- **环境自检**：自动探测 `Rscript`、Python 解释器与 Stata 批处理可执行文件，检查 R 包与 Python 转换依赖（`pandas / pyarrow / pyreadstat / pyreadr / openpyxl / xlsxwriter / xlrd`）；仅当配置里存在 Stata 扇区时才在启动时检测 Stata，避免批处理启动拖慢冷启动。
- **独立 R 会话**：默认跳过用户 `~/.Rprofile`（设置页可开启），避免为 RStudio 交互会话写的字体 / 主题 / `source` 配置在 GUI 后台进程里报错或拖慢每次任务；`.Renviron` 与系统级 `Rprofile.site` 仍会加载。
- **任务反馈**：右下角通知卡片（进行中 / 成功 / 失败 + 输出 + 警告 + 打开输出）、最近运行记录、运行日志页、完整日志文件。
- **菜单栏常驻**、登录时自动启动、权限自检中心（辅助功能 / 输入监控 / 端到端监听自检）。

## 🚀 快速开始

### 环境要求

- macOS 13+（Apple Silicon / Intel）
- Swift 5 工具链（Xcode 或 Command Line Tools）
- R 4.x（应用会自动探测 `/usr/local/bin/Rscript`、Homebrew、R.framework；也可在设置里手动指定）
- Python 3.9+（仅 Python 扇区 / 格式转换需要；会依次探测 `GlazeR/.venv`、`DataWheel/.venv`、`/usr/local/bin/python3`、`/opt/homebrew/bin/python3`、`/usr/bin/python3`，也可在设置里手动指定）
- Stata 14+（仅 Stata 扇区需要；会依次探测 `/usr/local/bin/stata-mp` / `stata-se` / `stata` 与 `/Applications/StataNow`、`/Applications/Stata` 下的 `.app`，也可在设置里手动指定）

三个引擎**按需安装**：只用 R 就不需要 Python 与 Stata。格式转换依赖可用 `pip install pandas pyarrow pyreadstat pyreadr openpyxl xlsxwriter xlrd` 安装；设置页的「Python 环境检测」会逐项列出缺失包。Stata 使用批处理模式，不需要图形界面的额外配置。

### 构建

```bash
zsh native/build_native.sh     # → build/GlazeR.app
zsh native/build_dmg.sh        # → build/dist/GlazeR-arm64.dmg / GlazeR-x86_64.dmg
swift build/make_icons.swift   # 重新生成 App 图标 / 菜单栏图标 / .glazer 文档图标（可选）
```

构建脚本会用自签名证书 `GlazeR Dev`（或已有的 `DataWheel Dev`）签名；若都没有则回退 ad-hoc 签名，此时每次重编译后系统「辅助功能」授权需要重新授予。可以在「钥匙串访问 → 证书助理 → 创建证书」里新建一张名称为 `GlazeR Dev`、类型为**代码签名**的自签名证书，即可让授权跨重编译保留。

> 开发态若把 `.app` 放在 `~/Documents` 下，macOS 可能弹出「想访问文稿文件夹中的文件」（应用要读取自己包内的引擎脚本）。把应用复制到 `/Applications` 或 `/tmp` 运行即可避免。

### 首次使用

1. 打开应用 → 「设置」→「权限检测」，授予**辅助功能**与**输入监控**（全局快捷键需要；HID 层事件 tap 在应用隐藏/后台时也能收到拖拽事件）。
2. 确认所用引擎的「环境检测」都显示版本与依赖状态（R / Python / Stata 三组独立检测）。
3. 到「转盘编辑器」用「新建…」添加预设，或按自己的工作流配置扇区，并为每套转盘指定数字键槽位。
4. 在 Finder 里选中一个文件，按住 `⌥` 拖动（或长按 `⌥`、或按 `⌥` + 数字键），把文件松手到目标扇区。

## 🧩 扇区配置说明

| 字段 | 说明 |
|---|---|
| 显示名称 / 悬停说明 | 扇区上的文字；悬停时中心盘显示函数名与说明 |
| 启用 | 关闭后扇区变灰，拖入不执行 |
| **引擎** | **R**（默认）/ **Python** / **Stata**，决定用哪个解释器与变量命名 |
| 执行方式 | **调用函数 / 命令** 或 **自定义代码** |
| 函数 / 命令 | R：`readr::read_csv`、`haven::read_dta`；Python：`pandas.read_csv`、`os.path.getsize`；Stata：`describe`、`summarize`，或外部 do 文件里定义的 `program` |
| 自定义脚本 | 可选的执行前 `source()`（R）/ `exec()`（Python）/ 内联 do 代码（Stata）的脚本路径，适合放自己的函数库 |
| 文件路径形参 | 拖入的文件路径注入到哪个参数，例如 `readxl::read_excel` 填 `path`；留空表示不注入（此时用路径变量）；Stata 命令模式下作为第一个位置参数 |
| 默认参数 | `参数名 = 表达式`，R 用 `TRUE` / `c(1,2)`，Python 用 `True` / `[1,2]` / `"utf-8"`，Stata 用命令行片段（如 `replace` / `n(5)`） |
| 自定义代码 | 表达式模式的代码，最后一个值 / `result` 作为结果；Stata 为整段 do 代码 |
| 多文件处理 | **逐文件执行**（默认）/ **整批一次执行**（此时路径变量为向量 / 列表） |
| 结果处理 | 不写出 / 打印到日志 / `.rds` / `.csv` / `.RData` / `.dta` / 自定义写出代码；Python 扇区另有 `convert()` 自动输出，Stata 扇区支持 `.dta` / `.csv` / 自定义写出 |
| 输出后缀 | 追加到原文件名之后，默认 `_glazed` |
| 配色 | 12 色调色板 |

### 自动解析的路径变量

应用在每次任务里自动解析下列变量，**无需任何配置**；在自定义代码、默认参数表达式、`source()` / `exec` / Stata do 文件的代码里都可以直接用。编辑器会根据当前扇区的引擎显示对应提示。

| 含义 | R 扇区 | Python 扇区 | Stata 扇区 |
|---|---|---|---|
| 文件完整路径（含路径 + 文件名.后缀） | `.file` | `FILE`、`glazer.file` | `` `file'`` / `$file` |
| 文件名称.后缀 | `.filename` | `FILENAME`、`glazer.filename` | `` `filename'`` / `$filename` |
| 文件路径，不含文件名 | `.dir` | `DIR`、`glazer.dir` | `` `dir'`` / `$dir` |
| 纯名称，不含后缀 | `.filebasename` | `FILEBASENAME`、`glazer.filebasename` | `` `filebasename'`` / `$filebasename` |
| 全部文件路径 | `.files`（字符向量） | `FILES`（列表）、`glazer.files` | `` `file1' … `fileN'`` 与 `` `nfiles'`` |
| 建议输出**文件**路径（含扩展名，不是目录） | `.out` | `OUT` | `` `out'`` / `$out` |
| 输出目录（不含文件名） | — | — | `` `outdir'`` / `$outdir` |
| 函数返回值（写出代码里） | `.result` | `result` | — |
| 内置格式转换 | — | `convert(FILE, "xlsx")` | — |

单文件时 `.file` / `FILE` / `` `file'`` 是字符串，「整批一次执行」时是向量 / 列表；`.filename` / `.dir` / `.filebasename` 始终与文件数量等长。Stata 同时提供局部宏与同名全局宏，后者可在 `program` 内部直接引用。

> **Stata 注意**：`` `out'`` 是**一个完整输出文件路径**（如 `/…/data_glazed.csv`），不是目录。写 `` `out'/xxx.csv `` 会把文件路径当目录，Stata 报 `invalid file specification` / `could not be opened`（`r(603)`）。想自己拼文件名请用 `` `outdir'/xxx.csv ``，或直接写入 `` `out'``。

### 参数是怎么传进去的

以 `readxl::read_excel(path = 拖入的文件, sheet = 1, col_names = TRUE)` 为例：

- 引擎：R，函数：`readxl::read_excel`
- 文件路径形参：`path`
- 默认参数：`sheet = 1`、`col_names = TRUE`
- 结果处理：`保存为 .rds`，输出后缀 `_data`

应用生成任务脚本，`engine/runner.R` 用 `parse(text = )` 求值每个默认参数，再 `do.call(fn, args)` 调用；Python 侧 `engine/runner.py` 用 `eval()` 求值参数表达式后调用；Stata 侧 `engine/runner.do` 把文件名与默认参数按 Stata 命令行片段拼接后执行。参数值里可以直接引用路径变量，例如把某个参数设为 `paste0(.file, ".bak")` 或 `FILE + ".bak"`。

表达式模式示例（R）：

```r
d <- read.csv(.file, check.names = FALSE)
cat("读入行数:", nrow(d), "\n")
summary(d)
```

表达式模式示例（Python）：

```python
import pandas as pd
result = pd.read_csv(FILE).describe().to_string()
```

表达式模式示例（Stata）：

```stata
import delimited using `"`file'"', clear
describe
summarize
```

结果处理选择「打印结果到日志」，输出会出现在通知卡片与运行日志页。

### 输出规则

- 文件名 = `原文件名（去扩展名） + 输出后缀 + 扩展名`；同名文件不覆盖，自动追加 `(1)`、`(2)` …
- 输出目录：默认源文件所在目录，可在「设置」改为「每次询问」或「固定目录」。
- `.csv` 写出带 UTF-8 BOM，Excel 打开中文不乱码；`.dta` 需要 `haven` 包（R）、`pyreadstat`（Python）或 Stata 原生 `save`。
- 「自定义写出代码」R 用 `.result` / `.out` / `.file`，Python 用 `result` / `OUT` / `FILE`，Stata 用 `` `out'``。
- Python 扇区若返回已有文件路径字符串、或含 `output` 键的 `dict`（`convert()` 的返回值），会自动识别为本次输出文件，无需再配置写出方式。

### 配置示例（首次启动自动生成）

| 扇区 | 函数 / 代码 | 输出 |
|---|---|---|
| CSV→RDS | `readr::read_csv(show_col_types = FALSE)` | `.rds` |
| DTA→RDS | `haven::read_dta` | `.rds` |
| XLSX→RDS | `readxl::read_excel`（形参 `path`） | `.rds` |
| RDS→CSV | 表达式 `readRDS(.file)` | `.csv` |
| 数据概览 | 表达式 `summary(readr::read_csv(.file, ...))` | 打印到日志 |
| 转 DTA | 表达式读入 CSV | `.dta` |

`testdata/glazer_functions.R` 提供了自定义 R 函数示例（表格摘要、CSV 转 DTA、批量合并 CSV）。

## 📊 Stata 引擎

Stata 扇区通过 `stata-mp -b do job.do` 批处理执行。macOS 下 Stata 批处理**不写 stdout**，所有输出落在工作目录的 `job.log`，因此 `engine/runner.do` 会把结果写成 `key=value` 的 `result.txt`，Swift 侧读取后组装任务结果；用户代码用 `capture noisily { ... }` 包裹，执行出错会保留 `_rc` 并在卡片里显示 `r(xxx)`。

**完整执行过程不会丢**：无论成功或失败，`job.log` 都会并进任务结果，可在通知卡片「查看输出」与「运行日志 → 最近任务的输出」展开；失败时还会写入 `~/Library/Application Support/GlazeR/glazer.log`，并把 `job.do` / `job.log` / `result.txt` 另存到 `~/Library/Application Support/GlazeR/logs/Stata-<时间>-<扇区>/`，方便事后排查。失败卡片同时显示从日志里提取的具体报错行，而不只是 `r(xxx)`。

引擎自动注入的宏（同时提供同名全局宏）：

```stata
* 输入：完整路径、名称.后缀、所在目录、纯名称
local file          `"/path/to/data.dta"'
local filename      `"data.dta"'
local dir           `"/path/to"'
local filebasename  `"data"'
* 输出：`out' 是完整文件路径（不是目录），`outdir' 是输出目录
local out           `"/path/to/data_glazed.csv"'
local outdir        `"/path/to"'
* 多文件时依次为 file1 … fileN，另有 nfiles
local file1         `"/path/to/data.dta"'
local nfiles        1
* 同名全局宏，program 内部可直接引用
global file         `"`file'"'
global outdir       `"`outdir'"'
```

「新建… → Stata 命令示例」会生成 6 个扇区：数据描述、描述统计、转 DTA、转 CSV、前 10 行、自定义 Stata。设置页可指定 Stata 可执行文件绝对路径并单独「重新检测」。

> Stata 扇区的输出方式目前支持 `.dta`（自动 `save`）、`.csv`（自动 `export delimited`）与「自定义」（在自定义写出代码里用 `` `out'`` 写文件）。「不写出 / 打印到日志」只执行代码；此时若用户代码自行写出了 `` `out'``，引擎也会把它识别为输出，卡片显示「打开 / 在 Finder 中显示」。打印 / 自定义模式下 `` `out'`` 的扩展名会按代码里的 `export delimited` / `save` 自动推断。

### 自定义写出：正确写法与 `r(603)`

想把 `.dta` 自己导出为 CSV，推荐直接用预设里的「转 CSV」扇区；若要自定义代码，两种写法都可用：

```stata
* 写法一：写入引擎给出的完整输出路径（推荐，卡片可直接打开结果）
use `"`file'"', clear
export delimited using `"`out'"', replace
```

```stata
* 写法二：用输出目录自己拼文件名
use `"`file'"', clear
export delimited using `"`outdir'/`filebasename'.csv"', replace
```

**错误写法**（把 `` `out'`` 当目录）会得到 `invalid file specification` / `file … could not be opened`（`r(603)`）：

```stata
export delimited using `"`out'/`filebasename'.csv"', replace
```

应用在执行前也会检测这种 `` `out'/ `` 用法，并在任务卡片与 `glazer.log` 里给出提示。

## 🐍 Python 引擎与 DataWheel 格式转换

`engine/glazer_formats.py` 移植了 DataWheel 的读写逻辑，Python 扇区里可直接调用 `convert(FILE, "xlsx")`。「新建… → DataWheel 格式转换」会一键生成 10 个对应扇区。

| 目标格式 | 说明 | 目标格式 | 说明 |
|---|---|---|---|
| `csv` | 逗号分隔文本（带 BOM） | `tsv` / `txt` | 制表符文本 / 智能分列文本 |
| `xlsx` | Excel；超过单表上限自动拆分为多个文件 | `dta` | Stata，变量名自动规范化 |
| `rds` | R 数据文件（经 `Rscript(arrow)` 兜底写出） | `parquet` / `feather` | Arrow 列式存储 |
| `json` / `jsonl` | 记录数组 / 逐行 JSON | | |

读取侧除上述格式外还兼容 `.xls`、`.RData`、`.pq`、`.arrow`、`.ndjson`。转换结果默认写在**源文件所在目录**（可传 `outdir=DIR` / `out_dir=DIR`、`suffix="_clean"` 调整），返回 `dict` 会被引擎自动识别为输出文件。

Python `call` 模式还支持默认参数表达式，例如函数 `pandas.read_csv`、形参 `filepath_or_buffer`、参数 `nrows = 2`、`encoding = "utf-8"`。

## 🔢 多转盘与数字键槽位

- 「转盘编辑器」里每套转盘都有一个「数字键槽位」下拉（`0–9` 或「无」），最多 10 套。
- 「设置 → 转盘数字键槽位」显示总览，重复槽位会在保存时自动去重、空槽位自动补位。
- 在 Finder 选中文件后按住 `⌥1`，直接呼出槽位 1 的转盘并带入 Finder 选中项；`⌥0` 对应槽位 0。
- 同一槽位只绑定一套转盘；同一种引擎的转盘可以有任意多套，只要分配不同槽位即可。

## 📄 `.glazer` 转盘配置文件

`.glazer` 是 GlazeR 注册的**专属文档类型**（UTI `com.rstata.glazer.wheel`，遵循 `public.utf8-plain-text`），有专属文件图标。安装到 `/Applications` 后，应用启动时会确保它是 `.glazer` 的默认打开方式；也可在「设置 → .glazer 默认打开方式」里手动设置与查看当前状态。

### 双击打开：可编辑文本 + 语法高亮

双击 `.glazer` 会在 GlazeR 的**独立文档窗口**里打开，而不是直接进入导入：

- 用 `NSTextView` 显示**可编辑富文本**（着色只用于显示，保存始终为纯文本 UTF-8）。
- 顶部工具条：文件名、状态、未保存标记、高亮开关、**浅色 / 深色**主题切换、保存（`⌘S`）、另存为、更多菜单（应用到转盘 / 重新加载 / 格式说明 / 关闭）。
- 底部图例栏：行数、字符数、颜色图例与高亮状态。
- 语法高亮按内容分类着色：注释、段落标记（`【转盘】` / `【扇区】`）、键名、分隔符、枚举值、颜色值本身、数字、**三引号代码块**，以及块内的 R / Python / Stata 关键字、字符串、注释与路径变量（含 Stata 局部宏 `` `file'`` 与全局宏 `$file`、行首 `*` 注释）。
- 三引号代码块识别覆盖三种写法：导出的 `自定义代码 = """` 起始行、手工编辑时独立成行的 `"""` / `'''`、以及单行 `"""code"""`。块内看起来像 `# 注释` / `【扇区】` / `键 = 值` 的行一律按代码着色，不会被误判为配置字段；结束行之后立即恢复正常字段解析。
- 「应用到转盘…」会先保存，再把文件交给主窗口的**导入预览**（替换同名 / 全部新增 / 清空后导入）。

### 导出与导入

在「转盘编辑器」右上角用「导出…」把转盘设置保存为 **`.glazer` 纯文本文件**（也可复制到剪贴板）：

- 可导出**当前转盘**或**全部转盘**；每套转盘一个 `【转盘】` 段，其后每个扇区一个 `【扇区】` 段。
- 文件头部带完整中文说明（**格式 v3**）；字段写成 `键 = 值`，多行 R / Python / Stata 代码用三引号块，默认参数写成可重复的 `参数.名称 = 表达式`（`停用参数.名称` 表示不启用）。
- 转盘级 `槽位 = 0…9 | 无`；扇区级 `引擎 = R | Python | Stata`（默认 R，大小写与 `PY` / `STATA` / `do` 等别名均可）。也可用英文段落标记 `[[wheel]]` / `[[slice]]` 与英文键名。
- 解析器对注释、空行、全角冒号、中英文键名与别名、BOM、字段笔误都做了容错，不确定之处会在导入预览里逐条列出，不会因为一处笔误丢掉整份配置。

| 导入方式 | 行为 |
|---|---|
| 替换同名转盘 | 按 `编号`（未写则按名称）匹配并覆盖现有转盘；文件里多出来的转盘追加为新增。保留原编号，当前转盘引用不会失效 |
| 全部作为新增 | 每套转盘生成新编号追加到末尾，现有转盘保持不变 |
| 清空后导入 | 删除现有全部转盘，只保留文件中的内容 |

格式细节见 `examples/wheels.glazer`（**5 套示例转盘、25 个扇区**：9 个 R、13 个 Python、3 个 Stata，槽位 `1–5`，覆盖 R 数据处理 / Python 函数 / DataWheel 格式转换 / 常用工作流 / Stata 命令）。

> `编号 = ...` 用于匹配替换，一般不要修改；删掉该行就退化为按转盘名称匹配。
>
> 每次执行导入前，当前配置会自动备份到 `~/Library/Application Support/GlazeR/config.before-import.json`，需要时可据此手动还原。

## ⏱ 长任务、超时与取消

R / Python / Stata 任务在后台执行，通知卡片会实时显示当前阶段与已耗时（`R 正在执行：xxx` / `Python 正在执行：xxx` / `Stata 正在执行：xxx` → `正在写出结果…`），不会因为渲染 / 转换耗时较长而看起来「卡死」。

- **超时**：默认 300 秒，可在「设置 → 任务超时」调整为 30～1800 秒。超时会终止子进程并给出明确提示。
- **取消**：进行中的卡片右上角有「取消」按钮，会真正终止对应的 R / Python / Stata 进程；同一批次中尚未启动的任务也会跳过。
- **阶段事件**：`runner.R` / `runner.py` 通过 stdout 逐行回传 `{"event":"stage","message":"..."}`，Swift 端实时更新卡片状态；Stata 批处理不写 stdout，改由 `job.log` 与 `result.txt` 回收，失败时日志尾部会直接显示在错误信息里。

## 📁 文件与配置

| 路径 | 用途 |
|---|---|
| `~/Library/Application Support/GlazeR/config.json` | 全部转盘组、扇区、参数、槽位、全局设置（可直接手工编辑，字段缺失会自动回退默认值） |
| `~/Library/Application Support/GlazeR/recents.json` | 最近 50 条运行记录 |
| `~/Library/Application Support/GlazeR/glazer.log` | 完整运行日志（Stata 失败时还会写入整段 `job.log`） |
| `~/Library/Application Support/GlazeR/logs/Stata-<时间>-<扇区>/` | 失败任务的 `job.do` / `job.log` / `result.txt` 诊断快照 |
| `~/Library/Application Support/GlazeR/hotkey.log` | 全局事件监听诊断日志 |
| `engine/runner.R` | R 执行引擎，**仅依赖 base R**，不引入 jsonlite |
| `engine/runner.py` | Python 执行引擎，标准库为主 |
| `engine/glazer_formats.py` | DataWheel 格式转换读写逻辑 |
| `engine/runner.do` | Stata 批处理引擎模板（`key=value` 结果回传） |
| `build/glazer-doc.icns` | `.glazer` 专属文档图标 |
| `examples/wheels.glazer` | 完整配置示例（格式 v3） |

Swift 端只需生成一份临时的 `job.R` / `job.py` / `job.do`（把路径、函数、参数写成字面量），再由对应 runner 执行并回传结果，因此引擎侧不需要安装任何额外 Swift 依赖。

## 🔐 权限说明

| 权限 | 是否必需 | 用途 |
|---|---|---|
| 辅助功能 | ✅ 必需 | `CGEventTap` 全局监听「修饰键 + 拖动」「修饰键 + 数字键」手势 |
| 输入监控 | 强烈建议 | 把 tap 挂在 HID 层（`HID+defaultTap`），应用在后台/被隐藏时依然能收到拖拽事件，且不会被系统反复禁用 |

「设置 → 权限检测」每 2 秒刷新一次状态，并提供**监听自检**（移动鼠标即可验证事件流是否真正到达），不依赖可能误报的系统 API。

## 🛠 开发态调试与独立验证

```bash
defaults write com.rstata.glazer gzOpenPageOnLaunch -string editor   # home | editor | logs | settings
defaults write com.rstata.glazer gzShowWheelOnLaunch -bool YES        # 启动时在屏幕中心展示转盘
defaults write com.rstata.glazer gzRunOnLaunch -string "/path/to/f.csv"  # 用第 1 个扇区跑一次
```

单独验证引擎（不需要启动 App）：

```bash
Rscript engine/runner.R --check "haven,readr,readxl"
Rscript engine/runner.R testdata/demo_job.R
Rscript engine/runner.R testdata/demo_job_expr.R
python3 engine/runner.py --check
```

重新生成配置示例、跑文本格式 round-trip、高亮与 Stata 引擎测试：

```bash
swiftc -swift-version 5 -disable-sandbox -parse-as-library \
  native/Sources/Models.swift native/Sources/WheelTextCodec.swift \
  native/Tests/gen_example.swift -o build/tmp/gen_example
build/tmp/gen_example > examples/wheels.glazer

swiftc -swift-version 5 -disable-sandbox -parse-as-library \
  native/Sources/Models.swift native/Sources/WheelTextCodec.swift \
  native/Tests/textcodec_roundtrip.swift -o build/tmp/glazer_roundtrip
build/tmp/glazer_roundtrip examples/wheels.glazer        # 78 项

swiftc -swift-version 5 -disable-sandbox -parse-as-library \
  native/Sources/GlazerSyntaxHighlighter.swift \
  native/Tests/syntax_highlight_test.swift -o build/tmp/syntax_highlight_test
build/tmp/syntax_highlight_test                          # 22 项

swiftc -swift-version 5 -disable-sandbox -parse-as-library \
  native/Sources/Models.swift native/Sources/REngine.swift \
  native/Sources/PythonEngine.swift native/Sources/StataEngine.swift \
  native/Tests/stata_engine_test.swift -o build/tmp/stata_engine_test
build/tmp/stata_engine_test                              # 环境检测 + 真实 .dta 写出

swiftc -swift-version 5 -disable-sandbox -parse-as-library \
  native/Sources/Models.swift native/Sources/REngine.swift \
  native/Sources/PythonEngine.swift native/Sources/StataEngine.swift \
  native/Tests/stata_path_log_test.swift -o build/tmp/stata_path_log_test
build/tmp/stata_path_log_test                            # `out'/`outdir' 语义 + 失败日志回传（11 项）
```

## ❓ 常见问题

- **转盘不出现**：检查「权限检测」里的监听自检；确认没有被其他应用占用同一个组合键；确认应用没有被系统隐藏（`NSApp.isHidden` 会自动恢复）。
- **按 `⌥1` 没反应**：确认该槽位在设置页已分配给某套转盘（槽位 `0–9` 一一对应），且当前 Finder 有选中文件或随后直接拖文件。
- **提示找不到 Rscript / Python / Stata**：在「设置」里填可执行文件绝对路径（可用 `which Rscript` / `which python3` / `which stata-mp` 查询）。Stata 也可直接填 `/Applications/StataNow/StataMP.app/Contents/MacOS/stata-mp`。
- **「R 环境不可用」，报错来自 `~/.Rprofile` 的 `font_add()` / `source()`，但 RStudio 正常**：`Rscript` 默认会执行用户级 `.Rprofile`，而它通常是为 RStudio 交互会话配置的（加载 `ggplot2` / `tidymodels`、注册 `/Users/ac/Documents/font/*.ttf` 字体、`source` 自定义脚本）。macOS 的「文稿」目录 TCC 授权是**按应用**授予的：RStudio 已获授权，GlazeR 从后台启动的 Rscript 却没有，于是读字体失败并污染 `--check` 的 JSON 输出。应用默认在「设置 → R 解释器 → 跳过用户 ~/.Rprofile」里跳过它（通过 `R_PROFILE_USER=/dev/null`，只跳过用户级 profile，`.Renviron` 与系统级 `Rprofile.site` 仍加载）。若确实需要 `.Rprofile` 里的自定义函数，请关闭该开关，或更推荐在扇区的「自定义脚本」里显式 `source()` 对应脚本。
- **Python 环境检测报 `PermissionError: ... .venv/pyvenv.cfg` 或 60 秒超时**：同一 TCC 原因——虚拟环境放在 `~/Documents` 下且应用未获授权时，`python` 可启动但读不到 `pyvenv.cfg`，会直接 `Fatal Python error: init_import_site`。应用会自动跳过不可读的 venv、回退到系统 Python；此时格式转换依赖可能不全，可在「设置 → Python 解释器」里指定一个可访问且已装好依赖的解释器，或为 GlazeR 授予「文稿」目录访问权限。
- **提示缺少 R 包 / Python 依赖**：R 在控制台执行设置页「复制安装命令」给出的 `install.packages(...)`；Python 用 `pip install pandas pyarrow pyreadstat pyreadr openpyxl xlsxwriter xlrd`，然后「重新检测」。
- **Stata 扇区报 `r(603)` / `invalid file specification` / `file … could not be opened`**：几乎都是把 `` `out'`` 当成目录拼了子文件名（如 `` `out'/`filebasename'.csv ``）。`` `out'`` 是完整输出文件路径，改用 `` `outdir'/`filebasename'.csv `` 或直接 `` export delimited using `"`out'"', replace ``，详见「自定义写出：正确写法与 `r(603)`」。失败时通知卡片与运行日志页可展开完整 `job.log`，诊断文件另存于 `~/Library/Application Support/GlazeR/logs/`。
- **Stata 扇区报 `invalid syntax r(198)` 或直接失败**：错误信息里会附带 `job.log` 尾部，先看报错行。最常见的是 do 文件里手写路径时没用复合引号，应写 `` use `"`file'"', clear ``；另外 `runner.do` 的占位标记只能单独成行，不要在注释里写占位符。
- **GUI 里能用的包，应用里找不到**：GUI 启动的进程 PATH / `R_LIBS_USER` / 虚拟环境可能不同，可在设置里指定解释器路径与工作目录，并检查设置页显示的库路径。
- **权限每次重编译都失效**：创建 `GlazeR Dev` 自签名代码签名证书，或把应用安装到 `/Applications` 后不再重编译。
- **`.glazer` 双击被别的编辑器打开**：在「设置 → .glazer 默认打开方式」点「设为默认」，或在 Finder 的「显示简介 → 打开方式」里选择 GlazeR 并「全部更改」。
- **任务一直转圈、没有任何产物**：最常见的原因是脚本里调用了 `servr::httd()`。它在 RStudio 交互会话里以守护进程方式启动并立即返回，但在 `Rscript` 非交互会话（`interactive() == FALSE`）中会阻塞式常驻，脚本永远停在那一行。引擎已设置 `options(servr.daemon = TRUE)` 兜底；而 `pagedown::chrome_print()` 直接打印本地 HTML 文件并不需要本地 HTTP 服务，建议直接删掉 `httd()`。
- **报 `Chrome crashed` / `Failed to generate output`**：非交互会话里 headless Chrome 的 sandbox 无法初始化，而 `pagedown` 只在 Windows 自动追加 `--no-sandbox`。引擎已做兼容包装，会自动为 `pagedown::chrome_print()` 追加 `--no-sandbox` 与 `--disable-dev-shm-usage`；自己的脚本里也可显式写 `extra_args = c("--disable-gpu", "--disable-dev-shm-usage", "--no-sandbox")`。如需关闭该兼容层，在 `.Rprofile` 里写 `options(glazer.chrome.compat = FALSE)`。
- **任务卡住后如何止损**：点卡片「取消」，或等超时自动终止；随后通过卡片的「查看日志」与 `glazer.log` 定位脚本卡在哪一步。

## 🙏 致谢

- 转盘交互与全局监听思路参考 [r-stata/DataWheel](https://github.com/r-stata/DataWheel)，其灵感来自 [KnifeLemon/Filee](https://github.com/KnifeLemon/Filee/)。
- 开发：微信公众号 RStata · 完全本地执行，数据不上传。
