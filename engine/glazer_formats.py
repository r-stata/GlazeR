#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""GlazeR 文件格式转换库 —— 移植自 DataWheel 的 engine.py（微信公众号 RStata）。

提供给 .glazer 文件中 Python 扇区直接使用的 convert() / read_any() / write_any()。
支持：csv / tsv / txt / xlsx / xls / dta / rds / rdata / parquet / feather / json / jsonl

依赖（可选，按需导入）：pandas、pyarrow、pyreadstat、pyreadr、openpyxl、xlsxwriter、xlrd
"""
import os
import re
import subprocess
import tempfile

try:
    import pandas as pd
except ImportError:
    pd = None

REQUIRED_PACKAGES = [
    "pandas", "pyarrow", "pyreadstat", "pyreadr", "openpyxl", "xlsxwriter", "xlrd",
]

READ_EXTS = {
    ".csv": "csv", ".tsv": "tsv", ".txt": "txt",
    ".xlsx": "xlsx", ".xls": "xls",
    ".dta": "dta",
    ".rds": "rds", ".rdata": "rdata",
    ".parquet": "parquet", ".pq": "parquet",
    ".feather": "feather", ".arrow": "feather",
    ".json": "json", ".jsonl": "jsonl", ".ndjson": "jsonl",
}

WRITE_EXTS = {
    "csv": ".csv", "tsv": ".tsv", "txt": ".txt", "xlsx": ".xlsx",
    "dta": ".dta", "rds": ".rds",
    "parquet": ".parquet", "feather": ".feather",
    "json": ".json", "jsonl": ".jsonl",
}

EXCEL_SPLIT_LIMIT = 1048575  # xlsx 单表最多 1048576 行，留一行表头


def check_packages():
    """返回 {name: installed} 字典"""
    out = {}
    for name in REQUIRED_PACKAGES:
        try:
            __import__(name)
            out[name] = True
        except Exception:
            out[name] = False
    return out


def _need_pandas():
    if pd is None:
        raise RuntimeError(
            "格式转换需要 pandas；请在 GlazeR「设置 → Python 解释器」中选择已安装依赖的环境，"
            "或执行 pip install pandas pyarrow pyreadstat pyreadr openpyxl xlsxwriter xlrd"
        )


# ------------------------------------------------------------------ 读取

def read_csv_smart(path, sep=","):
    for enc in ("utf-8-sig", "gbk", "utf-8", "latin1"):
        try:
            return pd.read_csv(path, sep=sep, encoding=enc)
        except (UnicodeDecodeError, pd.errors.ParserError):
            continue
    return pd.read_csv(path, sep=sep, encoding="latin1")


def read_table(path, fmt):
    return read_csv_smart(path, "," if fmt == "csv" else "\t")


def read_txt(path):
    """txt 智能分列：嗅探分隔符（\\t , ; |），失败按制表符/逗号/空白兜底"""
    import csv as _csv
    sample, enc_used = "", "utf-8-sig"
    for enc in ("utf-8-sig", "gbk", "utf-8", "latin1"):
        try:
            with open(path, "r", encoding=enc) as f:
                sample = "".join(f.readline() for _ in range(30))
            enc_used = enc
            break
        except (UnicodeDecodeError, LookupError):
            continue
    sep = None
    try:
        sep = _csv.Sniffer().sniff(sample, delimiters="\t,;|").delimiter
    except Exception:
        if "\t" in sample:
            sep = "\t"
        elif "," in sample:
            sep = ","
        elif re.search(r"\S\s+\S", sample):
            sep = r"\s+"
    try:
        return pd.read_csv(path, sep=sep, encoding=enc_used, engine="python")
    except Exception:
        return pd.read_csv(path, sep=r"\s+", encoding="latin1", engine="python")


def read_excel(path, sheet=None):
    xl = pd.ExcelFile(path)
    names = xl.sheet_names
    if sheet is None:
        target = names[0]
    elif isinstance(sheet, str) and not sheet.isdigit():
        target = sheet
    else:
        target = names[int(sheet)]
    df = xl.parse(target)
    others = [n for n in names if n != target]
    warn = ("工作簿包含多个工作表，已转换「%s」；其余：%s" % (target, ", ".join(others))) if others else None
    return df, warn


def read_dta(path):
    import pyreadstat
    df, meta = pyreadstat.read_dta(path)
    return df, None


def read_r(path):
    import pyreadr
    res = pyreadr.read_r(path)
    for _k, v in res.items():
        if isinstance(v, pd.DataFrame):
            return v, None
    raise RuntimeError("R 数据文件中未找到数据框（data.frame）")


def read_json_any(path, fmt):
    if fmt == "jsonl":
        return pd.read_json(path, lines=True), None
    try:
        return pd.read_json(path, orient="records"), None
    except ValueError:
        return pd.read_json(path, lines=True), None


def read_any(path, fmt, sheet=None):
    _need_pandas()
    if fmt in ("csv", "tsv"):
        return read_table(path, fmt), None
    if fmt == "txt":
        return read_txt(path), None
    if fmt in ("xlsx", "xls"):
        return read_excel(path, sheet)
    if fmt == "dta":
        return read_dta(path)
    if fmt in ("rds", "rdata"):
        return read_r(path)
    if fmt == "parquet":
        return pd.read_parquet(path), None
    if fmt == "feather":
        return pd.read_feather(path), None
    if fmt in ("json", "jsonl"):
        return read_json_any(path, fmt)
    raise RuntimeError("不支持的读取格式：%s" % fmt)


# ------------------------------------------------------------------ 写出

def _clean_columns_for_stata(cols):
    out, seen, changed = [], set(), False
    for c in cols:
        s = str(c)
        s = re.sub(r"[^\w]", "_", s, flags=re.UNICODE)
        s = re.sub(r"_+", "_", s).strip("_")
        if not s:
            s = "var"
        if re.match(r"^\d", s):
            s = "v" + s
        if s != str(c):
            changed = True
        s = s[:32]
        base, i = s, 1
        while s in seen:
            suffix = "_" + str(i)
            s = base[:32 - len(suffix)] + suffix
            i += 1
        seen.add(s)
        out.append(s)
    return out, changed


def _prep_dta(df):
    df = df.copy()
    df.columns, changed = _clean_columns_for_stata(df.columns)
    for c in df.columns:
        col = df[c]
        if isinstance(col.dtype, pd.CategoricalDtype):
            df[c] = col.astype(str).replace("nan", None)
        elif pd.api.types.is_datetime64_any_dtype(col):
            df[c] = col.dt.tz_localize(None) if col.dt.tz is not None else col
        elif col.dtype == object:
            df[c] = col.map(lambda x: None if x is None else (str(x) if not isinstance(x, str) else x))
    return df, changed


def write_dta(df, path, label=None):
    import pyreadstat
    df2, changed = _prep_dta(df)
    pyreadstat.write_dta(df2, path, file_label=label or "数据处理：微信公众号 RStata")
    return "已将变量名规范化以符合 Stata 命名规则" if changed else None


def write_rds(df, path):
    """pyreadr 不支持写 rds，用临时 parquet + Rscript(arrow) 兜底"""
    tmp = tempfile.NamedTemporaryFile(suffix=".parquet", delete=False)
    tmp.close()
    try:
        df.to_parquet(tmp.name, index=False)
        r_code = ('df <- arrow::read_parquet("%s"); saveRDS(df, "%s", version = 2)'
                  % (tmp.name.replace('"', '\\"'), path.replace('"', '\\"')))
        r = subprocess.run(["Rscript", "-e", r_code], capture_output=True, text=True, timeout=600)
        if r.returncode != 0:
            raise RuntimeError("写出 rds 失败（Rscript）：" + (r.stderr or "").strip()[-500:])
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass
    return None


def write_json(df, path, lines=False):
    with open(path, "w", encoding="utf-8") as f:
        df.to_json(f, orient="records", lines=lines, force_ascii=False,
                   indent=None if lines else 2, date_format="iso")


def write_any(df, path, fmt, label=None):
    _need_pandas()
    if fmt == "csv":
        df.to_csv(path, index=False, encoding="utf-8-sig")  # 带 BOM，Excel 打开中文不乱码
    elif fmt in ("tsv", "txt"):
        df.to_csv(path, index=False, sep="\t", encoding="utf-8")
    elif fmt == "xlsx":
        with pd.ExcelWriter(path, engine="xlsxwriter") as w:
            df.to_excel(w, index=False, sheet_name="data")
    elif fmt == "dta":
        return write_dta(df, path, label)
    elif fmt == "rds":
        return write_rds(df, path)
    elif fmt == "parquet":
        df.to_parquet(path, index=False)
    elif fmt == "feather":
        df.to_feather(path)
    elif fmt == "json":
        write_json(df, path, lines=False)
    elif fmt == "jsonl":
        write_json(df, path, lines=True)
    else:
        raise RuntimeError("不支持的写出格式：%s" % fmt)
    return None


def unique_path(path):
    """同名文件不覆盖，自动追加 (1)、(2)…"""
    if not os.path.exists(path):
        return path
    root, ext = os.path.splitext(path)
    i = 1
    while os.path.exists("%s(%d)%s" % (root, i, ext)):
        i += 1
    return "%s(%d)%s" % (root, i, ext)


# ------------------------------------------------------------------ 转换入口

def convert(path, target, outdir=None, sheet=None, label=None, suffix="", out_dir=None):
    """把文件转换为目标格式，返回 dict（含 output 路径）。

    在 .glazer 的 Python 扇区里可直接写：convert(FILE, "xlsx")
    也可写 glazer.file / glazer.dir 等，或传 outdir=DIR / out_dir=DIR、suffix="_clean"。
    """
    _need_pandas()
    outdir = outdir or out_dir
    if not path or not os.path.exists(path):
        raise RuntimeError("文件不存在：%s" % path)
    ext = os.path.splitext(path)[1].lower()
    fmt = READ_EXTS.get(ext)
    if not fmt:
        raise RuntimeError("无法识别的输入文件类型：%s" % ext)
    if target not in WRITE_EXTS:
        raise RuntimeError("不支持的输出格式：%s（可用：%s）"
                           % (target, ", ".join(sorted(WRITE_EXTS))))

    df, warn = read_any(path, fmt, sheet=sheet)
    base = os.path.splitext(os.path.basename(path))[0] + (suffix or "")
    outdir = outdir or os.path.dirname(path) or "."
    os.makedirs(outdir, exist_ok=True)
    out_path = unique_path(os.path.join(outdir, base + WRITE_EXTS[target]))

    note = None
    outputs = [out_path]
    if target == "xlsx" and len(df) > EXCEL_SPLIT_LIMIT:
        root, ext2 = os.path.splitext(out_path)
        nparts = (len(df) + EXCEL_SPLIT_LIMIT - 1) // EXCEL_SPLIT_LIMIT
        outputs = []
        for i in range(nparts):
            p = unique_path("%s_part%d%s" % (root, i + 1, ext2))
            write_any(df.iloc[i * EXCEL_SPLIT_LIMIT:(i + 1) * EXCEL_SPLIT_LIMIT], p, target)
            outputs.append(p)
        out_path = outputs[0]
        note = "共 %d 行，超出 Excel 单表上限，已自动拆分为 %d 个文件" % (len(df), nparts)
    else:
        note = write_any(df, out_path, target, label=label)

    return {
        "ok": True,
        "input": path,
        "output": out_path,
        "outputs": outputs,
        "rows": int(len(df)),
        "cols": int(df.shape[1]),
        "warning": warn or note,
        "summary": "%d 行 × %d 列" % (len(df), df.shape[1]),
    }
