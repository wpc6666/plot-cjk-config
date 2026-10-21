"""matplotlib 中文绘图助手  ${SCRIPT_VERSION}

用法（建议在 import matplotlib.pyplot 之前 import 本模块）：

    import mpl_setup as mp
    fig, ax = mp.new()
    ax.plot([1, 2, 3], [1, 2, 3])
    ax.set_title("中文标题")
    mp.save(fig, "demo", fmts=("png", "pdf"))   # -> <项目>/figures/demo.{png,pdf}

为什么需要这个模块：
    matplotlibrc 里的字体链只是「默认值」。一旦代码里写了
    plt.rcParams["font.sans-serif"] = [...] 或用了会重置 rcParams 的
    样式，中文就会掉字。本模块在 import 时无条件重设一遍，幂等。

    更关键的是：macOS 把 PingFang.ttc 放在
    /System/Library/AssetsV2/.../<hash>.asset/AssetData/ 这种目录里，
    而 matplotlib 自己扫字体表时【不递归这个目录】——实测即使删掉
    ~/.matplotlib/fontlist-v*.json 强制重建缓存，也依然找不到
    PingFang SC（重建后 1004 个字体里没有它）。
    fontconfig 反而能匹配，所以 R 侧用它没问题。
    本模块用 fm.fontManager.addfont() 把它显式补进字体表。
    不做这一步不会报错，只会静默降级到 Heiti SC
    （仍是中文字体、不出框，但没有真正的粗体）。
"""

from __future__ import annotations

import os
from pathlib import Path

import matplotlib

matplotlib.use(os.environ.get("MPL_BACKEND", "Agg"))

import matplotlib.pyplot as plt  # noqa: E402

# ── 中文字体链（按字重完整性排序）──────────────────────────────
# PingFang SC      weight 100-600，粗体真的生效        ← 首选
# Heiti SC         weight 300,400，真 glyf 轮廓
# Songti SC        weight 300-900，唯一有真 bold 的衬线体
# Arial Unicode MS 23MB 全 CJK，最后兜底
# Noto Sans SC     本机只有 weight 100（Thin）→ 标题发虚、bold 失效
# Source Han Sans VF 本机只有 weight 250（ExtraLight）→ 同上
# 「Source Han Sans SC」本机不存在，fc-match 会假命中 Helvetica.ttc，
# 一旦写进链里中文直接出框，绝对不要加。
# 【v15.0 改法】Arial Unicode MS 排第一，理由与 R 侧完全相同（见 Rprofile 注释）：
#   统计/计量图里 ρ √ → ∞ ≤ ≥ ∂ ∈ ∪ ∩ 是高频符号，PingFang SC 缺其中一部分，
#   缺字形就会渲染成方框。Arial Unicode MS 对这些符号覆盖最全，是 macOS 常驻字体。
#   实测：R 侧把这条改到第一位后，你的原脚本从全方块变成完全正常。
#   matplotlib 自带字形回退（missing glyph → 自动找下一个），所以 Python 侧
#   风险本来较低，但为两边一致、便于排查，这里同步同一顺序。
CN_FONTS = [
    "Arial Unicode MS",
    "PingFang SC",
    "Heiti SC",
    "Songti SC",
    "Noto Sans SC",
    "Source Han Sans VF",
]

DPI = int(os.environ.get("PLOT_DPI", "300"))

# ── 字体文件兜底 ───────────────────────────────────────────────
_FONT_GLOBS = [
    "/System/Library/AssetsV2/com_apple_MobileAsset_Font*/"
    "[0-9a-f]*.asset/AssetData/PingFang.ttc",
    "~/Library/Fonts/NotoSansSC*.ttf",
    "~/Library/Fonts/SourceHanSans*.ttc",
]


def _register_font_files() -> list[str]:
    """把上面这些字体文件补进 matplotlib 字体表，返回成功注册的路径。"""
    import glob as _glob
    from matplotlib import font_manager as fm

    done: list[str] = []
    known = {f.fname for f in fm.fontManager.ttflist}
    for pattern in _FONT_GLOBS:
        # 必须用 glob.glob：pattern 里可能有多级通配（AssetsV2 那层是 hash 目录），
        # pathlib 的 .parent.glob() 只展开最后一段，匹配不到。
        for hit in sorted(_glob.glob(os.path.expanduser(pattern))):
            p = Path(hit)
            if not p.is_file() or str(p) in known:
                continue
            try:
                fm.fontManager.addfont(str(p))
                done.append(str(p))
                known.add(str(p))
            except Exception:
                pass
    return done


def _apply_fonts() -> str:
    """把中文字体链写进 rcParams，返回实际生效的第一个字体名。"""
    _register_font_files()

    available = {f.name for f in matplotlib.font_manager.fontManager.ttflist}
    chosen = next((n for n in CN_FONTS if n in available), None)
    plt.rcParams["font.sans-serif"] = list(CN_FONTS) + ["DejaVu Sans", "sans-serif"]
    plt.rcParams["font.family"] = "sans-serif"
    plt.rcParams["axes.unicode_minus"] = False
    plt.rcParams.setdefault("svg.fonttype", "none")

    # PingFang SC 最粗只到 600(Semibold)，matplotlib 找 weight=700 时会刷
    # "Failed to find font weight bold for PingFang SC, now using 600."
    # 回落结果本身是对的（600 就是想要的粗体），这里只降噪。
    if os.environ.get("MPL_QUIET", "") != "1":
        import logging
        logging.getLogger("matplotlib.font_manager").setLevel(logging.ERROR)

    return chosen or "Arial Unicode MS"


CN_FONT = _apply_fonts()


# ── 输出目录（与 R 侧 .resolve_outdir 同一套语义）───────────────
_MARKS = (".git", "pyproject.toml", "setup.py", "setup.cfg",
          "environment.yml", "Pipfile", ".project-root")


def _find_project_root(start: Path | None = None) -> Path:
    p = (start or Path.cwd()).resolve()
    for _ in range(20):
        if any((p / m).exists() for m in _MARKS):
            return p
        if p.parent == p:
            break
        p = p.parent
    return Path.cwd().resolve()


def _resolve_outdir() -> Path:
    explicit = os.environ.get("PLOT_OUTDIR", "").strip()
    if explicit:
        return Path(explicit).expanduser()
    mode = os.environ.get("PLOT_OUTDIR_MODE", "project").strip().lower()
    if mode == "fixed":
        root = Path.home()
    elif mode == "cwd":
        root = Path.cwd().resolve()
    else:
        root = _find_project_root()
    return root / "figures"


OUTDIR = _resolve_outdir()
OUTDIR.mkdir(parents=True, exist_ok=True)


def set_plot_dir(path: str | os.PathLike) -> Path:
    global OUTDIR
    OUTDIR = Path(path).expanduser().resolve()
    OUTDIR.mkdir(parents=True, exist_ok=True)
    print(f"[mpl_setup] out={OUTDIR}")
    return OUTDIR


def new(nrows: int = 1, ncols: int = 1, *, figsize=(9, 6), dpi: int = 150, **kwargs):
    """建一张带中文字体的图，返回 (fig, ax)。"""
    kwargs.setdefault("layout", "constrained")
    return plt.subplots(nrows, ncols, figsize=figsize, dpi=dpi, **kwargs)


def save(fig, name: str, *, dpi: int | None = None, close: bool = True,
         show: bool = False, fmts=("png",)) -> list[Path]:
    """按名字存图到 OUTDIR。

    name 可以不带到后缀；已带同名后缀时不会再叠加（避免 a.pdf 变 a.pdf.pdf）。
    name 若是绝对路径或以 ~ 开头，则尊重该路径，自动建父目录。
    """
    if isinstance(fmts, str):
        fmts = (fmts,)
    if not str(name).strip():
        raise ValueError("save() 的 name 不能为空（空名字会生成 .png 这种隐藏文件）")

    name = str(name)
    is_abs = name.startswith(("/", "~")) or os.sep in name
    paths = []
    for ext in fmts:
        ext = ext.lstrip(".")
        # 已带同名后缀就不再追加
        stem = name if name.lower().endswith("." + ext.lower()) else f"{name}.{ext}"
        p = Path(stem).expanduser() if is_abs else (OUTDIR / stem)
        p.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(p, dpi=dpi or DPI, bbox_inches="tight", facecolor="white")
        print(f"[mpl_setup] {p}")
        paths.append(p)
    if show:
        plt.show()
    if close:
        plt.close(fig)
    return paths


def show_all() -> None:
    plt.show()


def close_all() -> None:
    plt.close("all")


def check_cn() -> bool:
    """自检：画一张含中文的图，抓 Glyph missing 警告。True 表示无缺字。"""
    import warnings

    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        fig, ax = plt.subplots(figsize=(6, 3))
        ax.plot([1, 2, 3], [1, 2, 3])
        ax.set_title("中文标题：经济增速（%）", fontweight="bold")
        ax.set_xlabel("年份（年）")
        ax.set_ylabel("增速（%）")
        ax.annotate("注释 −1.5", (2, 1.5))
        tmp = OUTDIR / "_cn_check.png"
        fig.savefig(tmp, dpi=120)
        plt.close(fig)
        tmp.unlink(missing_ok=True)

    missing = [str(w.message) for w in caught
               if "missing from font" in str(w.message).lower()
               or "Glyph" in str(w.message)]
    print(f"[mpl_setup] check_cn: 字体={CN_FONT} 缺字警告={len(missing)}")
    for m in missing:
        print("   ", m)
    return not missing


if os.environ.get("MPL_QUIET", "") != "1":
    print(f"[mpl_setup] font={CN_FONT} out={OUTDIR} dpi={DPI}")
