#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""GlazeR Python 执行引擎 —— 标准库为主，格式转换按需依赖第三方包。

用法：
  python3 runner.py --check                检查 Python 版本与转换依赖
  python3 runner.py <job.py>              执行 GlazeR 生成的任务脚本

结果：stdout 最后一行输出单行 JSON（字段与 runner.R 一致）：
  {"ok":true,"message":"...","output":"...","elapsed":0.12,
   "summary":"...","log":"...","warnings":"..."}

job.py 由 Swift 端生成，定义以下变量（均为 Python 字面量）：
  GZ_MODE / GZ_FUNCTION / GZ_SOURCE / GZ_CODE / GZ_FILE_ARG
  GZ_FILES / GZ_PARAM_KEYS / GZ_PARAM_EXPRS
  GZ_OUTPUT_MODE / GZ_OUTPUT_DIR / GZ_OUTPUT_SUFFIX / GZ_OUTPUT_CODE
  GZ_OUT_BASE / GZ_WORKDIR

执行时注入的变量（表达式、默认参数、自定义函数都能直接使用）：
  FILE          完整路径（单文件为字符串；整批为列表）
  FILENAME      文件名（含后缀）
  DIR           文件所在目录（不含文件名）
  FILEBASENAME  纯文件名（不含后缀）
  FILES         全部输入路径（始终为列表）
  glazer        上述变量的对象形式：glazer.file / glazer.dir / ...
  OUT           自动去重后的建议输出路径
  convert()     内置格式转换，等价于 glazer_formats.convert
"""
import builtins
import contextlib
import importlib
import io
import json
import os
import sys
import time
import traceback
import warnings

REAL_STDOUT = sys.stdout
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)


def jstr(x):
    return json.dumps("" if x is None else str(x), ensure_ascii=False)


def emit(obj):
    REAL_STDOUT.write(json.dumps(obj, ensure_ascii=False, default=str) + "\n")
    REAL_STDOUT.flush()


def clip(text, n=12000):
    text = str(text)
    return text[:n] + "\n…（日志已截断）" if len(text) > n else text


def emit_result(ok, message, output="", elapsed=0, summary="", log="", warn=""):
    emit({
        "ok": bool(ok), "message": message, "output": output,
        "elapsed": round(float(elapsed), 3), "summary": summary,
        "log": clip(log), "warnings": clip(warn),
    })


def stage(msg):
    emit({"ok": True, "event": "stage", "message": msg})


def fail(msg, log="", warn="", elapsed=0):
    emit_result(False, msg, log=log, warn=warn, elapsed=elapsed)
    sys.exit(1)


# ------------------------------------------------------------------ check

def do_check():
    import glazer_formats
    pkgs = glazer_formats.check_packages()
    emit({
        "ok": True,
        "python": sys.executable,
        "version": "%d.%d.%d" % sys.version_info[:3],
        "packages": pkgs,
        "missing": [k for k, v in pkgs.items() if not v],
    })


if len(sys.argv) >= 2 and sys.argv[1] == "--check":
    do_check()
    sys.exit(0)

if len(sys.argv) < 2:
    fail("用法：python3 runner.py <job.py> 或 --check")

JOB_FILE = sys.argv[1]
if not os.path.exists(JOB_FILE):
    fail("找不到任务文件：%s" % JOB_FILE)

START = time.time()

job = {"__name__": "__glazer_job__"}
try:
    with open(JOB_FILE, "r", encoding="utf-8") as f:
        exec(compile(f.read(), JOB_FILE, "exec"), job)
except Exception as e:
    fail("任务脚本解析失败：%s" % e)


def gz(name, default=""):
    v = job.get(name, default)
    return default if v is None else v


FILES = list(gz("GZ_FILES", []))
if not FILES:
    fail("任务中没有输入文件")

WORKDIR = str(gz("GZ_WORKDIR", ""))
if WORKDIR and os.path.isdir(WORKDIR):
    try:
        os.chdir(WORKDIR)
    except OSError:
        pass


def _as_path_list(xs):
    """单文件返回字符串，多文件返回列表"""
    return xs[0] if len(xs) == 1 else list(xs)


PATH_VALUE = _as_path_list(FILES)


class GlazerPaths:
    """glazer.file / glazer.filename / glazer.dir / glazer.filebasename / glazer.files"""

    def __init__(self, files):
        self.files = list(files)
        self.file = PATH_VALUE
        self.filename = _as_path_list([os.path.basename(p) for p in files])
        self.dir = _as_path_list([os.path.dirname(p) or "." for p in files])
        self.filebasename = _as_path_list(
            [os.path.splitext(os.path.basename(p))[0] for p in files])

    def __repr__(self):
        return "<glazer paths: %s>" % (self.file if isinstance(self.file, str)
                                       else "%d files" % len(self.files))


glazer = GlazerPaths(FILES)

# 建议输出路径（不覆盖同名文件）
OUT_DIR = str(gz("GZ_OUTPUT_DIR", "")) or str(glazer.dir if isinstance(glazer.dir, str) else glazer.dir[0])
OUT_BASE = str(gz("GZ_OUT_BASE", "")) or str(os.path.splitext(os.path.basename(FILES[0]))[0])
OUT_SUFFIX = str(gz("GZ_OUTPUT_SUFFIX", "_glazed"))
OUT_MODE = str(gz("GZ_OUTPUT_MODE", "none")).lower()
OUT_EXTS = {
    "none": "", "print": "", "csv": ".csv", "rds": ".rds", "rdata": ".RData",
    "dta": ".dta", "custom": "",
}


def unique_path(path):
    if not os.path.exists(path):
        return path
    root, ext = os.path.splitext(path)
    i = 1
    while os.path.exists("%s(%d)%s" % (root, i, ext)):
        i += 1
    return "%s(%d)%s" % (root, i, ext)


OUT = unique_path(os.path.join(OUT_DIR, OUT_BASE + OUT_SUFFIX + OUT_EXTS.get(OUT_MODE, "")))

ns = {
    "__name__": "__glazer_user__",
    "__builtins__": builtins,
    "FILE": PATH_VALUE,
    "FILENAME": glazer.filename,
    "DIR": glazer.dir,
    "FILEBASENAME": glazer.filebasename,
    "FILES": FILES,
    "OUT": OUT,
    "WORKDIR": WORKDIR,
    "glazer": glazer,
    "os": os,
    "sys": sys,
}

# 内置转换函数：convert(FILE, "xlsx") / convert(glazer.file, "dta", suffix="_clean")
try:
    import glazer_formats
    ns["glazer_formats"] = glazer_formats

    def convert(path=None, target="csv", **kwargs):
        """格式转换，返回 dict（含 output 路径）；默认写到源文件所在目录"""
        path = path or PATH_VALUE
        kwargs.setdefault("out_dir", None)
        return glazer_formats.convert(path, target, **kwargs)

    ns["convert"] = convert
    ns["glazer_convert"] = convert
except Exception as e:      # 转换库不可用时，普通 Python 扇区仍可运行
    ns["glazer_formats"] = None


# ------------------------------------------------------------------ 准备

logs = io.StringIO()
warns = []


def resolve_function(name):
    if not name:
        raise RuntimeError("未配置 Python 函数")
    if name in ns and callable(ns[name]):
        return ns[name]
    if hasattr(builtins, name) and callable(getattr(builtins, name)):
        return getattr(builtins, name)
    parts = name.split(".")
    obj = ns.get(parts[0])
    if obj is None:
        try:
            obj = importlib.import_module(parts[0])
        except ImportError:
            raise RuntimeError("找不到函数或模块：%s" % name)
    for p in parts[1:]:
        obj = getattr(obj, p, None)
        if obj is None:
            raise RuntimeError("找不到函数：%s" % name)
    if not callable(obj):
        raise RuntimeError("%s 不是可调用对象" % name)
    return obj


try:
    src = str(gz("GZ_SOURCE", ""))
    if src:
        if not os.path.exists(src):
            raise RuntimeError("找不到 Python 脚本：%s" % src)
        with open(src, "r", encoding="utf-8") as f:
            exec(compile(f.read(), src, "exec"), ns)

    keys = list(gz("GZ_PARAM_KEYS", []))
    exprs = list(gz("GZ_PARAM_EXPRS", []))
    kwargs = {}
    for i, k in enumerate(keys):
        k = str(k).strip()
        if not k:
            continue
        expr = str(exprs[i]) if i < len(exprs) else "None"
        try:
            v = eval(expr, ns)
        except Exception as e:
            raise RuntimeError("参数 %s 的表达式「%s」求值失败：%s（Python 扇区的参数要写 Python 表达式，R 的 TRUE / c(...) 不适用）" % (k, expr, e))
        kwargs[k] = v
        ns[k] = v

    fa = str(gz("GZ_FILE_ARG", "file")).strip()
    if fa:
        kwargs[fa] = PATH_VALUE
        ns[fa] = PATH_VALUE
except Exception as e:
    fail("参数准备失败：%s" % e, elapsed=time.time() - START)


# ------------------------------------------------------------------ 执行

mode = str(gz("GZ_MODE", "call")).lower()
stage("Python 正在执行：%s" % ("自定义 Python 代码" if mode == "expr"
                              else str(gz("GZ_FUNCTION", ""))))
result = None
err = None
try:
    with contextlib.redirect_stdout(logs):
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            if mode == "expr":
                code = str(gz("GZ_CODE", ""))
                if not code.strip():
                    raise RuntimeError("未配置自定义 Python 代码")
                try:
                    result = eval(compile(code, "<glazer code>", "eval"), ns)
                except SyntaxError:
                    exec(compile(code, "<glazer code>", "exec"), ns)
                    result = ns.get("result")
            else:
                fn = resolve_function(str(gz("GZ_FUNCTION", "")))
                result = fn(**kwargs)
            for w in caught:
                warns.append(str(w.message))
except Exception:
    err = traceback.format_exc(limit=8).strip()

if err:
    fail(err.splitlines()[-1], log=logs.getvalue() + "\n" + err,
         warn="\n".join(warns), elapsed=time.time() - START)


# ------------------------------------------------------------------ 输出

stage("正在写出结果…")
output = ""
summary = ""

# 约定：返回已有文件路径 / 含 output 的 dict，直接作为本次输出（格式转换预设用）
if isinstance(result, str) and os.path.exists(result):
    output = result
elif isinstance(result, dict) and result.get("output") and os.path.isfile(str(result["output"])):
    output = str(result["output"])
    if result.get("warning"):
        warns.append(str(result["warning"]))
    summary = str(result.get("summary", ""))

if not summary:
    try:
        import pandas as pd
        if isinstance(result, pd.DataFrame):
            summary = "%d 行 × %d 列" % (len(result), result.shape[1])
    except ImportError:
        pass
    if not summary:
        if result is None:
            summary = "返回 None"
        elif hasattr(result, "__len__"):
            summary = "%s[%d]" % (type(result).__name__, len(result))
        else:
            summary = type(result).__name__

try:
    if not output and OUT_MODE not in ("none", "print"):
        os.makedirs(OUT_DIR, exist_ok=True)
        if OUT_MODE == "custom":
            ns["result"] = result
            ns["OUT"] = OUT
            ocode = str(gz("GZ_OUTPUT_CODE", ""))
            if not ocode.strip():
                raise RuntimeError("未配置自定义写出代码")
            with contextlib.redirect_stdout(logs):
                exec(compile(ocode, "<glazer output>", "exec"), ns)
            output = OUT if os.path.exists(OUT) else ""
        elif OUT_MODE in ("csv", "rds", "dta", "rdata"):
            import glazer_formats
            df = result
            if OUT_MODE == "rdata":
                raise RuntimeError("Python 引擎暂不支持 .RData 写出，请改用 R 扇区或 convert()")
            if not hasattr(df, "to_csv"):
                raise RuntimeError("写出 %s 需要返回 pandas DataFrame；当前返回 %s" % (OUT_MODE, type(result).__name__))
            note = glazer_formats.write_any(df, OUT, OUT_MODE)
            if note:
                warns.append(note)
            output = OUT
        else:
            raise RuntimeError("Python 引擎不支持输出方式「%s」，请用 convert() 或自定义写出代码" % OUT_MODE)
    elif OUT_MODE == "print":
        logs.write(repr(result) + "\n")
except Exception as e:
    fail("结果写出失败：%s" % e, log=logs.getvalue(),
         warn="\n".join(warns), elapsed=time.time() - START)

msg = "处理完成，已写出结果" if output else "处理完成"
if summary:
    msg += "（%s）" % summary
emit_result(True, msg, output=output, elapsed=time.time() - START,
            summary=summary, log=logs.getvalue(), warn="\n".join(warns))
