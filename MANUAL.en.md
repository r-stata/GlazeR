# GlazeR · The R / Python / Stata Wheel

<p align="center">
  <img src="build/icon.png" width="128" alt="GlazeR icon" />
</p>

<p align="center">
  <strong>Select a file → hold a hotkey (add a digit to pick a wheel) → release onto a slice to run your R / Python / Stata function or code</strong><br/>
  Native SwiftUI · 100% local, R / Python / Stata run on your machine · Wheel interaction inspired by
  <a href="https://github.com/r-stata/DataWheel">DataWheel</a> / <a href="https://github.com/KnifeLemon/Filee/">Filee</a>
</p>

<p align="center"><em>Full English guide</em> · <a href="README.md">Project home (中文)</a> · <a href="README.zh-CN.md">完整中文手册</a></p>

---

GlazeR generalises DataWheel's "one slice, one output format" into "**one slice, one function**". Each slice is bound to an R function, a Python function, a Stata command, or a snippet of custom code. The dropped file's path is injected automatically, together with your saved default arguments. R slices can write `.rds / .csv / .RData / .dta`; Python slices can also call the built-in DataWheel converter to move tabular data between CSV / TSV / TXT / XLSX / DTA / RDS / Parquet / Feather / JSON / JSONL; Stata slices run through `stata-mp -b do`, so you can `use` / `describe` / `summarize` and write `.dta` / `.csv` automatically.

**Up to 10 wheels** can be configured (digit slots `0–9`). Hold the global modifier combo plus a digit to summon that wheel directly — e.g. `⌥1` for an R-function wheel, `⌥2` for format conversion, `⌥3` for a Python wheel, `⌥4` for a Stata command wheel. You can keep several wheels using the same engine. The number of wheels and slices, the engine behind each slice, and each function's default arguments are all configurable from the UI.

## Features

### Five ways to invoke the wheel

| Method | How |
|---|---|
| Window drop | Drag files anywhere onto the app window; the wheel appears at the cursor |
| Modifier + drag | From **any app** (Finder, Desktop…), hold the modifier combo and drag a file; release onto a slice |
| Select + hold | Select files in Finder, hold the combo (default 0.45 s); the wheel appears and you click a slice. Finder selection is read automatically |
| Modifier + digit | With files selected in Finder, hold `⌥` + `0…9` to summon the wheel assigned to that slot (main keyboard and keypad both work) |
| Services / Dock | Right-click a file → Services → *Process with GlazeR*, or drop onto the Dock icon |

A wheel chosen by a digit stays pinned for 60 seconds so subsequent drags reuse it. The wheel stays anchored where it appeared. Releasing modifiers, dropping outside, `Esc`, or clicking elsewhere dismisses it.

### Configurability

- **Up to 10 wheels**: create / duplicate / delete / rename; each gets a `0–9` digit slot. Settings shows a slot overview and duplicate/out-of-range slots are de-duplicated and auto-assigned on save.
- **One-click presets**: blank wheel, R demo, Python demo, **Stata command demo (6 slices)**, and DataWheel 10-format conversion wheel.
- **2–12 slices** per wheel; shrinking keeps the first N configurations.
- **Per-wheel hotkey combos**: any combination of ⌘ ⌃ ⌥ ⇧ ⇪; the most specific match wins.
- **Three engines**: each slice is independently **R**, **Python** or **Stata**, backed by `engine/runner.R`, `engine/runner.py` and `engine/runner.do`. All three share the same timeout / cancellation / stage-event / result-collection layer.
- **Per-slice settings**: label, description, enabled state, engine, function or custom code, external `.R` / `.py` / `.do` script, the parameter receiving the file path, default arguments, multi-file batching, output mode, filename suffix, and color.
- **Automatic path variables** (see table below), available inside custom code, default-argument expressions, and functions defined in sourced/executed scripts or inlined do code. The editor shows the hint for the current engine.
- **Environment self-check**: detects `Rscript`, a Python interpreter and a Stata batch executable; checks referenced R packages and Python conversion dependencies (`pandas / pyarrow / pyreadstat / pyreadr / openpyxl / xlsxwriter / xlrd`). Stata is probed at launch only when at least one Stata slice exists, so batch startup never slows cold launch.
- **Isolated R session**: skips the user `~/.Rprofile` by default (toggleable in Settings) so fonts / themes / `source` calls written for interactive RStudio sessions cannot break or slow down background jobs. `.Renviron` and the site-level `Rprofile.site` are still loaded.
- **Feedback**: notification cards with output / warnings, recent runs, a log page, and a full log file.
- **Menu bar resident**, launch at login, and a permission self-check center (Accessibility / Input Monitoring / end-to-end event-flow probe).

## Quick start

Requires macOS 13+ and a Swift 5 toolchain. Install **only the engines you use**:

- R 4.x — auto-detected at `/usr/local/bin/Rscript`, Homebrew, or R.framework; an absolute path can be set in Settings.
- Python 3.9+ — only for Python slices / format conversion. Detection order: `GlazeR/.venv`, `DataWheel/.venv`, `/usr/local/bin/python3`, `/opt/homebrew/bin/python3`, `/usr/bin/python3`; an absolute path can be set in Settings.
- Stata 14+ — only for Stata slices. Detection order: `/usr/local/bin/stata-mp` / `stata-se` / `stata`, then `.app` bundles under `/Applications/StataNow` and `/Applications/Stata`; an absolute path can be set in Settings.

```bash
zsh native/build_native.sh     # → build/GlazeR.app
zsh native/build_dmg.sh        # → build/dist/GlazeR-arm64.dmg / GlazeR-x86_64.dmg
swift build/make_icons.swift   # optional: regenerate app / menu bar / .glazer document icons
```

Conversion dependencies: `pip install pandas pyarrow pyreadstat pyreadr openpyxl xlsxwriter xlrd`. Stata runs in batch mode and needs no extra GUI configuration.

The build script signs with a stable self-signed `GlazeR Dev` (or existing `DataWheel Dev`) identity and falls back to ad-hoc signing. With ad-hoc signing, macOS Accessibility grants are lost on every rebuild — create a self-signed **Code Signing** certificate named `GlazeR Dev` in Keychain Access to keep them.

On first launch, open **Settings → Permission Check** and grant Accessibility (required) and Input Monitoring (strongly recommended, enables the HID-level event tap), then confirm the environment checks for the engines you use (R / Python / Stata are checked independently).

> If you run the `.app` from `~/Documents` during development, macOS may ask for access to the Documents folder because the app reads its bundled engines. Copy it to `/Applications` or `/tmp` to avoid that.

## Configuring a slice

| Field | Meaning |
|---|---|
| Label / Description | Text on the slice; the center hub shows the function name on hover |
| Enabled | Disabled slices are dimmed and ignore drops |
| **Engine** | **R** (default), **Python** or **Stata** — decides the interpreter and variable naming |
| Mode | **Call function / command** or **Custom code** |
| Function / command | R: `readr::read_csv`, `haven::read_dta`; Python: `pandas.read_csv`, or a function defined in your external script; Stata: `describe`, `summarize`, or a `program` defined in your do file |
| Script | Optional `.R` sourced / `.py` executed / `.do` inlined before the call |
| File argument | Parameter receiving the dropped path (`file`, `path`, …); empty means no injection (use path variables instead). In Stata call mode it becomes the first positional argument |
| Default arguments | `name = expression`; R uses `TRUE` / `c(1,2)`, Python uses `True` / `[1,2]` / `"utf-8"`, Stata uses command-line fragments such as `replace` / `n(5)` |
| Custom code | Code in expression mode; the last value / `result` becomes the result (for Stata, a whole do-file body) |
| Batch mode | **One run per file** (default) or **one run for all files** (vector / list of paths) |
| Output | None / print / `.rds` / `.csv` / `.RData` / `.dta` / custom writer; Python also has automatic `convert()` output, Stata supports `.dta` / `.csv` / custom writer |
| Suffix | Appended to the input stem, default `_glazed` |
| Color | 12-color palette |

### Automatic path variables

| Meaning | R slice | Python slice | Stata slice |
|---|---|---|---|
| Full path (dir + name.ext) | `.file` | `FILE`, `glazer.file` | `` `file'`` / `$file` |
| Name.ext | `.filename` | `FILENAME`, `glazer.filename` | `` `filename'`` / `$filename` |
| Directory only | `.dir` | `DIR`, `glazer.dir` | `` `dir'`` / `$dir` |
| Stem without extension | `.filebasename` | `FILEBASENAME`, `glazer.filebasename` | `` `filebasename'`` / `$filebasename` |
| All input paths | `.files` (character vector) | `FILES` (list), `glazer.files` | `` `file1' … `fileN'`` plus `` `nfiles'`` |
| Suggested output **file** path (with extension, not a directory) | `.out` | `OUT` | `` `out'`` / `$out` |
| Output directory (no filename) | — | — | `` `outdir'`` / `$outdir` |
| Return value in writer code | `.result` | `result` | — |
| Built-in conversion | — | `convert(FILE, "xlsx")` | — |

With a single file, `.file` / `FILE` / `` `file'`` is a string; in "one run for all files" mode it is a vector / list. `.filename`, `.dir`, `.filebasename` always match the number of files. Stata exposes both local macros and same-named globals, the latter usable inside a `program`.

> **Stata caveat**: `` `out'`` is a **complete output file path** (e.g. `/…/data_glazed.csv`), not a directory. Writing `` `out'/xxx.csv `` treats a file as a directory and Stata fails with `invalid file specification` / `could not be opened` (`r(603)`). To build your own filename use `` `outdir'/xxx.csv ``, or write directly to `` `out'``.

Example — `readxl::read_excel(path = dropped_file, sheet = 1, col_names = TRUE)`:

- Engine `R`, function `readxl::read_excel`, file argument `path`
- Default arguments `sheet = 1`, `col_names = TRUE`
- Output `Save as .rds`, suffix `_data`

Swift generates a temporary `job.R` / `job.py` / `job.do`. `runner.R` evaluates each argument with `parse(text = )` and calls `do.call(fn, args)`; `runner.py` uses `eval()` and calls the resolved callable; `runner.do` concatenates the command name and default-argument fragments into a Stata command line. Default arguments can reference path variables, e.g. `paste0(.file, ".bak")` or `FILE + ".bak"`.

Expression-mode examples:

```r
d <- read.csv(.file, check.names = FALSE)
cat("rows:", nrow(d), "\n")
summary(d)
```

```python
import pandas as pd
result = pd.read_csv(FILE).describe().to_string()
```

```stata
import delimited using `"`file'"', clear
describe
summarize
```

Choose "Print result to log" and the output appears in the notification card and the log page.

Output files are named `stem + suffix + ext`; existing files are never overwritten (auto `(1)`, `(2)` …). CSV output carries a UTF-8 BOM so Chinese text opens correctly in Excel. `.dta` output requires `haven` (R), `pyreadstat` (Python) or Stata's native `save`. Custom writers can use `.result` / `.out` / `.file` (R), `result` / `OUT` / `FILE` (Python) or `` `out'`` (Stata). A Python slice returning an existing path string, or a `dict` with an `output` key (what `convert()` returns), is automatically treated as the output file.

`testdata/glazer_functions.R` contains sample user-defined R functions.

## Stata engine

Stata slices run through `stata-mp -b do job.do`. On macOS **Stata batch mode writes nothing to stdout** — everything lands in `job.log` inside the working directory. `engine/runner.do` therefore writes a `key=value` `result.txt` that Swift reads to assemble the run result. User code is wrapped in `capture noisily { ... }`, so failures keep `_rc` and surface as `r(xxx)`.

**The full run is never lost**: on success and failure alike, `job.log` is attached to the result and can be expanded from the toast's *View output* button or **Run log → Recent job output**. On failure it is also appended to `~/Library/Application Support/GlazeR/glazer.log`, and `job.do` / `job.log` / `result.txt` are saved to `~/Library/Application Support/GlazeR/logs/Stata-<time>-<slice>/` for post-mortem debugging. The failure card also quotes the concrete error line from the log instead of just `r(xxx)`.

Macros injected automatically (with same-named globals):

```stata
* input: full path, name.ext, directory, stem
local file          `"/path/to/data.dta"'
local filename      `"data.dta"'
local dir           `"/path/to"'
local filebasename  `"data"'
* output: `out' is a complete FILE path (not a directory), `outdir' is the directory
local out           `"/path/to/data_glazed.csv"'
local outdir        `"/path/to"'
* with multiple files: file1 … fileN, plus nfiles
local file1         `"/path/to/data.dta"'
local nfiles        1
* same-named globals, usable inside a program
global file         `"`file'"'
global outdir       `"`outdir'"'
```

**New… → Stata command demo** creates 6 slices: describe, summary statistics, to DTA, to CSV, first 10 rows, and custom Stata. Settings lets you pin an absolute path to the Stata executable and re-check it independently.

> Stata output modes support `.dta` (automatic `save`), `.csv` (automatic `export delimited`) and **Custom** (write to `` `out'`` in your output code). "None / print to log" only executes the code; if your code writes `` `out'`` anyway, the engine detects the file and offers *Open / Reveal in Finder*. In print / custom modes the extension of `` `out'`` is inferred from `export delimited` / `save` in your code.

### Custom writes and the `r(603)` trap

To export a `.dta` to CSV, the simplest option is the preset **to CSV** slice. If you prefer custom code, both forms work:

```stata
* Option 1: write to the complete output path (recommended — the card can open the result)
use `"`file'"', clear
export delimited using `"`out'"', replace
```

```stata
* Option 2: build your own filename from the output directory
use `"`file'"', clear
export delimited using `"`outdir'/`filebasename'.csv"', replace
```

**Wrong** (treating `` `out'`` as a directory) produces `invalid file specification` / `file … could not be opened` (`r(603)`):

```stata
export delimited using `"`out'/`filebasename'.csv"', replace
```

GlazeR detects this `` `out'/ `` pattern before execution and warns in the job card and `glazer.log`.

## Python engine and DataWheel format conversion

`engine/glazer_formats.py` ports DataWheel's read/write logic. Inside a Python slice you can call `convert(FILE, "xlsx")`; **New… → DataWheel format conversion** creates the 10-slice wheel for you.

| Target | Notes | Target | Notes |
|---|---|---|---|
| `csv` | comma-separated (with BOM) | `tsv` / `txt` | tab-separated / smart-delimiter text |
| `xlsx` | Excel; automatically split when a sheet would exceed the row limit | `dta` | Stata, variable names normalised |
| `rds` | R data file (written via an `Rscript(arrow)` fallback) | `parquet` / `feather` | Arrow columnar formats |
| `json` / `jsonl` | record array / line-delimited JSON | | |

Reading also accepts `.xls`, `.RData`, `.pq`, `.arrow`, and `.ndjson`. Conversion writes next to the source file by default (override with `outdir=DIR` / `out_dir=DIR`, `suffix="_clean"`). Python `call` mode supports default-argument expressions too: e.g. function `pandas.read_csv`, argument `filepath_or_buffer`, params `nrows = 2`, `encoding = "utf-8"`.

## Multiple wheels and digit slots

- Each wheel has a "digit slot" picker in the editor (`0–9` or none); at most 10 wheels.
- **Settings → Wheel digit slots** shows the overview; duplicates are de-duplicated and empty slots auto-assigned on save.
- With files selected in Finder, `⌥1` summons the wheel in slot 1 with those files already attached; `⌥0` maps to slot 0.
- One slot binds exactly one wheel; you can keep several wheels of the same engine as long as they use different slots.

## The `.glazer` document

`.glazer` is a **registered document type** (UTI `com.rstata.glazer.wheel`, conforming to `public.utf8-plain-text`) with its own icon. When installed in `/Applications`, the app makes itself the default handler at launch; you can also set or inspect it under **Settings → .glazer default app**.

### Double-click: editable text with syntax highlighting

Double-clicking a `.glazer` file opens a **standalone document window** in GlazeR instead of importing immediately:

- An `NSTextView` renders **editable rich text** purely for display; saving always writes plain UTF-8.
- Toolbar: filename, status, unsaved marker, highlight toggle, **light / dark** theme, Save (`⌘S`), Save As, and a More menu (Apply to wheels / Reload / Format guide / Close).
- Bottom legend: line and character counts, color legend, highlight state.
- Highlighting covers comments, section markers (`【转盘】` / `【扇区】`), keys, separators, enum values, color values (drawn in their own color), numbers, **triple-quoted code blocks**, and R / Python / Stata keywords, strings, comments and path variables inside those blocks — including Stata local macros (`` `file'``), globals (`$file`) and leading-`*` line comments.
- Triple-quote detection covers all three forms: the exported `自定义代码 = """` opener, stand-alone `"""` / `'''` lines (hand editing), and single-line `"""code"""`. Lines inside a block that look like `# comments`, `【扇区】` or `key = value` are always colored as code, never mistaken for config fields; parsing resumes immediately after the closing delimiter.
- **Apply to wheels…** saves first, then hands the file to the main window's **import preview** (replace matching / append all / replace all).

### Export and import

Use **Export…** in the top-right of the wheel editor to save a human-readable **`.glazer`** text file (or copy it to the clipboard):

- Export the **current wheel** or **all wheels**. Each wheel is a `【转盘】` block followed by one `【扇区】` block per slice (English `[[wheel]]` / `[[slice]]` markers and key aliases are accepted).
- The file starts with a full commented guide in Chinese (**format v3**). Fields are `key = value`, multi-line R / Python / Stata code uses triple-quoted blocks, and default arguments use repeatable `参数.name = <expression>` lines (`停用参数.name` keeps an argument disabled).
- Wheel-level `槽位 = 0…9 | 无` sets the digit slot; slice-level `引擎 = R | Python | Stata` sets the engine (default R; case-insensitive, with `PY` / `STATA` / `do` aliases).
- The parser tolerates comments, blank lines, full-width colons, Chinese/English key aliases, BOMs and typos, and surfaces anything ambiguous in the preview instead of discarding the file.

| Import mode | Behaviour |
|---|---|
| Replace matching | Match by `编号` (id), falling back to name, and overwrite; unmatched wheels are appended. Original ids are kept so the active wheel reference stays valid |
| Append all | Every wheel in the file gets a new id and is appended; existing wheels are untouched |
| Replace all | Remove all existing wheels and keep only the file's contents |

See `examples/wheels.glazer` for a complete sample — **5 wheels, 25 slices** (9 R, 13 Python, 3 Stata; slots `1–5`) covering R data processing, Python functions, DataWheel conversion, common workflows and Stata commands. Before every import the current configuration is backed up to `~/Library/Application Support/GlazeR/config.before-import.json`.

## Long-running jobs, timeouts and cancellation

R / Python / Stata jobs run in the background. The notification card shows the live stage and elapsed time (`R is running: …` / `Python is running: …` / `Stata is running: …` → `Writing output…`), so slow rendering or conversion jobs never look frozen.

- **Timeout**: 300 s by default; adjustable from 30 to 1800 s in Settings → Job timeout. On expiry the child process is terminated with an explicit error.
- **Cancel**: the button on an in-progress card terminates the actual R / Python / Stata process; remaining queued batches are skipped.
- **Stage events**: `runner.R` / `runner.py` stream `{"event":"stage","message":"..."}` lines over stdout, which Swift renders immediately. Stata batch mode has no stdout, so results come from `job.log` / `result.txt`. **On success and failure alike** the complete `job.log` is attached to the result (expandable from the toast and the Run log page); failures additionally quote the concrete Stata error line in the card, append the log to `glazer.log`, and save a diagnostic snapshot under `logs/`.

## Files

| Path | Purpose |
|---|---|
| `~/Library/Application Support/GlazeR/config.json` | All wheels, slices, parameters, slots and global settings (hand-editable; missing fields fall back to defaults) |
| `~/Library/Application Support/GlazeR/recents.json` | Last 50 runs |
| `~/Library/Application Support/GlazeR/glazer.log` | Full run log (failed Stata runs append the whole `job.log`) |
| `~/Library/Application Support/GlazeR/logs/Stata-<time>-<slice>/` | Diagnostic snapshot of a failed Stata job: `job.do`, `job.log`, `result.txt` |
| `~/Library/Application Support/GlazeR/hotkey.log` | Event-tap diagnostics |
| `engine/runner.R` | Base-R-only execution engine |
| `engine/runner.py` | Python execution engine (standard library first) |
| `engine/glazer_formats.py` | DataWheel-compatible reader / writer |
| `engine/runner.do` | Stata batch engine template (`key=value` result hand-off) |
| `build/glazer-doc.icns` | Dedicated `.glazer` document icon |
| `examples/wheels.glazer` | Full configuration sample (format v3) |

Swift only generates a temporary `job.R` / `job.py` / `job.do` with string literals; the corresponding runner executes it and returns the result. No extra Swift-side dependencies are needed.

## Permissions

| Permission | Required? | Why |
|---|---|---|
| Accessibility | ✅ Yes | Global `CGEventTap` for "modifier + drag" and "modifier + digit" gestures |
| Input Monitoring | Strongly recommended | Mounts the tap at the HID layer so drags still arrive while the app is hidden/backgrounded |

## Development hooks and standalone checks

```bash
defaults write com.rstata.glazer gzOpenPageOnLaunch -string editor   # home | editor | logs | settings
defaults write com.rstata.glazer gzShowWheelOnLaunch -bool YES
defaults write com.rstata.glazer gzRunOnLaunch -string "/path/to/f.csv"
```

Test the engines standalone:

```bash
Rscript engine/runner.R --check "haven,readr,readxl"
Rscript engine/runner.R testdata/demo_job.R
Rscript engine/runner.R testdata/demo_job_expr.R
python3 engine/runner.py --check
```

Regenerate the configuration sample and run the standalone suites:

```bash
swiftc -swift-version 5 -disable-sandbox -parse-as-library \
  native/Sources/Models.swift native/Sources/WheelTextCodec.swift \
  native/Tests/gen_example.swift -o build/tmp/gen_example
build/tmp/gen_example > examples/wheels.glazer

swiftc -swift-version 5 -disable-sandbox -parse-as-library \
  native/Sources/Models.swift native/Sources/WheelTextCodec.swift \
  native/Tests/textcodec_roundtrip.swift -o build/tmp/glazer_roundtrip
build/tmp/glazer_roundtrip examples/wheels.glazer        # 78 checks

swiftc -swift-version 5 -disable-sandbox -parse-as-library \
  native/Sources/GlazerSyntaxHighlighter.swift \
  native/Tests/syntax_highlight_test.swift -o build/tmp/syntax_highlight_test
build/tmp/syntax_highlight_test                          # 22 checks

swiftc -swift-version 5 -disable-sandbox -parse-as-library \
  native/Sources/Models.swift native/Sources/REngine.swift \
  native/Sources/PythonEngine.swift native/Sources/StataEngine.swift \
  native/Tests/stata_engine_test.swift -o build/tmp/stata_engine_test
build/tmp/stata_engine_test                              # env check + real .dta write

swiftc -swift-version 5 -disable-sandbox -parse-as-library \
  native/Sources/Models.swift native/Sources/REngine.swift \
  native/Sources/PythonEngine.swift native/Sources/StataEngine.swift \
  native/Tests/stata_path_log_test.swift -o build/tmp/stata_path_log_test
build/tmp/stata_path_log_test                            # `out'/`outdir' semantics + failure log (11 checks)
```

## Troubleshooting

- **Job spins forever with no output**: usually a script calls `servr::httd()`. It starts as a daemon in an interactive RStudio session but blocks indefinitely under `Rscript` (`interactive() == FALSE`). The engine sets `options(servr.daemon = TRUE)` as a safety net; `pagedown::chrome_print()` prints a local HTML file directly and does not need an HTTP server, so removing `httd()` is the cleanest fix.
- **`Chrome crashed` / `Failed to generate output`**: headless Chrome cannot initialise its sandbox in a non-interactive session, and `pagedown` only adds `--no-sandbox` automatically on Windows. The engine patches `pagedown::chrome_print()` to append `--no-sandbox` and `--disable-dev-shm-usage`. You may also pass `extra_args = c("--disable-gpu", "--disable-dev-shm-usage", "--no-sandbox")` explicitly. Disable the patch with `options(glazer.chrome.compat = FALSE)` in `.Rprofile`.
- **Stata slice fails with `r(603)` / `invalid file specification` / `file … could not be opened`**: you almost certainly used `` `out'`` as a directory (e.g. `` `out'/`filebasename'.csv ``). `` `out'`` is a complete output file path; use `` `outdir'/`filebasename'.csv `` or write straight to `` export delimited using `"`out'"', replace ``. See *Custom writes and the `r(603)` trap*. Failed runs expose the full `job.log` in the toast and Run log, and save diagnostics under `~/Library/Application Support/GlazeR/logs/`.
- **Stata slice fails with `invalid syntax r(198)`**: the error message includes the `job.log` tail — read the failing line first. The usual cause is a hand-written path without compound quotes; write `` use `"`file'"', clear ``. Also note the placeholders in `runner.do` must be on their own line; never put a placeholder inside a comment.
- **Wheel does not appear**: check the listener self-test in Settings → Permissions, make sure no other app owns the same modifier combo.
- **`⌥1` does nothing**: verify slot 1 is assigned to a wheel in Settings and that Finder has a selection (or simply drag a file afterwards).
- **Interpreter not found**: set an absolute path in Settings (`which Rscript` / `which python3` / `which stata-mp`). For Stata you can also point directly at `/Applications/StataNow/StataMP.app/Contents/MacOS/stata-mp`.
- **"R environment unavailable" with an error from `font_add()` / `source()` in `~/.Rprofile`, while RStudio works fine**: `Rscript` runs the user-level `.Rprofile` by default, which is usually written for an interactive RStudio session (loading `ggplot2` / `tidymodels`, registering fonts under `~/Documents/font`, sourcing custom scripts). macOS grants Documents-folder (TCC) access **per application**: RStudio is already authorised, but the `Rscript` child spawned by GlazeR is not, so the font read fails and pollutes the `--check` JSON. GlazeR skips it by default via **Settings → R interpreter → Skip user ~/.Rprofile** (`R_PROFILE_USER=/dev/null`, which keeps `.Renviron` and the site-level `Rprofile.site`). If you do need functions defined in `.Rprofile`, turn the toggle off — or, preferably, `source()` the script explicitly in the slice's *Custom script* field.
- **Python check fails with `PermissionError: ... .venv/pyvenv.cfg` or times out**: the same TCC cause — when a virtualenv lives under `~/Documents` and the app is not authorised, `python` starts but cannot read `pyvenv.cfg` (`Fatal Python error: init_import_site`). GlazeR skips unreadable venvs and falls back to a system Python; conversion dependencies may then be missing, so set an accessible, fully provisioned interpreter under **Settings → Python interpreter**, or grant GlazeR Documents-folder access.
- **Packages / virtualenv available in a terminal but not in GlazeR**: GUI-launched processes have a narrower `PATH` / `R_LIBS_USER`; set an absolute interpreter path in Settings and inspect the reported library paths.
- **`.glazer` opens in another editor**: use **Settings → .glazer default app → Set as default**, or Finder → Get Info → Open with → GlazeR → Change All.
- **Permission grants lost after every rebuild**: create the `GlazeR Dev` self-signed code-signing certificate, or install once to `/Applications`.

## Credits

Wheel interaction and global monitoring are adapted from [r-stata/DataWheel](https://github.com/r-stata/DataWheel), itself inspired by [KnifeLemon/Filee](https://github.com/KnifeLemon/Filee/). Built by 微信公众号 RStata. Everything runs locally.
