# macOS 中文绘图配置 · R / Python / Stata

> 一键部署中文字体与高清出图环境 | 彻底解决 macOS 上画图中文变豆腐块（□□□）

[![Platform: macOS](https://img.shields.io/badge/Platform-macOS-000000.svg?logo=apple)](https://www.apple.com/macos/)
[![R](https://img.shields.io/badge/R-4.6-276DC3.svg?logo=r)](https://www.r-project.org/)
[![Python](https://img.shields.io/badge/Python-3.x-3776AB.svg?logo=python)](https://www.python.org/)
[![Stata](https://img.shields.io/badge/Stata-18-1A5276.svg)](https://www.stata.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

**[📖 在线文档](https://wpc6666.github.io/plot-cjk-config/)**

---

## 📑 目录

- [为什么需要这个项目](#-为什么需要这个项目)
- [快速开始](#-快速开始)
- [核心特性](#-核心特性)
- [十条铁律](#-十条铁律违反必出方框)
- [实测依据](#-实测依据为什么是这些结论)
- [踩过的坑](#-踩过的坑不报错但静默失效)
- [文件说明](#-文件说明)
- [验证](#-验证)
- [常见问题](#-常见问题)
- [许可证](#-许可证)

---

## 🤔 为什么需要这个项目

macOS 上画中文图，默认配置会出方框（□□□）。原因不是"没装字体"，而是三套工具链各有各的坑：

| 工具 | 默认行为 | 结果 |
|---|---|---|
| R `pdf()` | 不嵌中文字体，只塞 Helvetica | 中文全丢，报 `conversion failure in 'mbcsToSbcs'` |
| R `cairo_pdf()` | 按 `family` 精确匹配，**不做字形回退** | 基座是英文字体时，含中文的元素全变 □ |
| Python matplotlib | 字体缓存在 `~/.matplotlib/fontlist-*.json`，过期就不认新字体 | 悄悄回退到 DejaVu Sans → □ |
| Stata `graph export` | 只设 `fontface` 一项，另外 4 项仍是 Helvetica | 刻度、注释回退 → □ |

**这个项目把三套工具链一次性配好，并且用真实渲染验证过每一种输出格式。**

---

## 🚀 快速开始

```bash
# 1. 下载脚本
curl -O https://raw.githubusercontent.com/wpc6666/plot-cjk-config/main/setup_plot.sh
chmod +x setup_plot.sh

# 2. 部署（交互菜单）
bash setup_plot.sh

# 3. 体检（推荐每次改完配置都跑）
bash setup_plot.sh check
```

`check` 会真实出图并检查 PNG / PDF 里的中文墨迹，**全绿才算过**：

```
R 自检: PASS
  png            OK
  pdf            OK
  svg            OK
  base           OK
  ggsave_png     OK
  ggsave_pdf     OK
Python 自检: PASS
  [mpl_setup] check_cn: 字体=PingFang SC 缺字警告=0
Stata 自检: PASS
[OK] 全部通过：三套工具链中文均无豆腐块
```

### 其他命令

```bash
bash setup_plot.sh check       # 环境体检 + 出图自检
bash setup_plot.sh deps        # 查看缺哪些依赖，给安装命令
bash setup_plot.sh dry-run     # 预览，不落盘
bash setup_plot.sh uninstall   # 卸载（保留配置和备份）
bash setup_plot.sh purge       # 彻底清理（先自动备份到外部）
```

---

## ✨ 核心特性

- **零配置**：装完直接在 R / Python / Stata 里画图就是中文，不用每次手动设字体
- **高清**：默认 **300 DPI**（R 9×6in → 2700×1800，Python 9×6in → 2734×1834）
- **统一字体**：三套工具链默认同为 `Arial Unicode MS`（中文 + 全部数学符号都覆盖），文件互相对得上
- **自包含**：`setup_plot.sh` 是 1936 行单文件，把 6 个配置都内嵌了，拷到任何 Mac 上都能重建
- **可回滚**：改动前自动备份，`purge` 前先备份到配置目录**外部**，避免自杀式删除
- **能自检**：`check` 用真实渲染验证，不靠"看起来对"

### 装完就有的东西

| 功能 | R | Python | Stata |
|---|---|---|---|
| 中文字体 | `Arial Unicode MS` | `Arial Unicode MS` | `Arial Unicode MS` |
| 输出目录 | `<项目根>/figures/` | `<项目根>/figures/` | `$PLOT_OUTDIR` |
| 文件命名 | `fig_001.png` 递增 | 自定义 | `fig_001.png` 递增 |
| 一键存图 | `sp(p, "fig1", format="pdf")` | `mp.save(fig, "fig1")` | `gsp g1, out(fig1)` |
| 自检 | `check_cn_plot()` | `mp.check_cn()` | — |

---

## 🐚 它还会优化你的 `~/.zshrc`

v15.0 起，脚本不再只往 `.zshrc` 里塞两个绘图变量，
而是**接管整个开发环境段**
（`# >>> 开发环境配置 v2.0 >>>` 到 `# <<< 开发环境配置 v2.0 <<<`）。

### 为什么必须接管

原版手写 `.zshrc` 有 4 个静默 bug，只塞变量修不掉：

| # | Bug | 实测证据 | 后果 |
|---|---|---|---|
| 1 | `compinit` 缓存判断写反 | `${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24)` 里的 `.mh+24` 是"修改时间**早于** 24 小时"，条件永远为 false | `-C` 快速分支永远走不到，每次启动全量扫描 |
| 2 | `pip()` 整个失效 | 本机只有 `pip3`，没有 `pip`；`command pip` 报 `command not found` | 镜像回退机制形同虚设 |
| 3 | `PATH` / `PYTHONPATH` 膨胀 | 连续 source 3 次后 `~/.local/bin` 出现 **5 次**，`PYTHONPATH` 重复 **5 段** | 改一次 `.zshrc` 就多几十段 |
| 4 | 镜像无回退 | 清华地址硬编码，抽风时 `brew install` 直接失败 | 需要手动改文件 |

### v2.0 做了什么

| 能力 | 说明 |
|---|---|
| **镜像自动降级** | 启动时探测清华镜像（结果缓存 24h 到 `~/.cache/zsh-mirror.state`），连不上就**完全不设**镜像变量，工具自动走官方源 |
| **`mirror` 命令** | `mirror status` / `test` / `on` / `off` 手动切换，无需改文件 |
| **幂等 PATH** | `path_prepend` / `path_append` / `pythonpath_prepend` 先删后加，重复 source 不膨胀（实测 10 次后 `path` 长度不变） |
| **`pip` / `pip3` 双通道** | 自动找可用的那个（`_pip_bin`），`install` 失败时切官方 PyPI 重试一次。**用函数不用 alias**——`alias pip=pip3` 会让重新 source 时报 `defining function based on alias` |
| **快速补全** | `.zcompdump` 在 24h 内用 `compinit -C` 跳过安全扫描；过期才全量重建 |
| **macOS 按键修复** | `Ctrl+←/→` 按词跳转、`Home`/`End`、`Ctrl+R` 增量搜索 |
| **实用函数** | `mkcd`（建目录并进入）、`extract`（万能解压，7 种格式）、`proxy`（代理开关，带连通性检查） |
| **别名扩展** | `lt` `..` `...` `glog` `gbr` `ports` `flushdns` `ip` 等 |

### 会覆盖你手写的配置吗

分两种情况：

- **已是 v2.0 格式**（含 `# >>> 开发环境配置 v2.0 >>>` 标记）
  → 只做**增量替换**：删掉三个标记块重新写入，
  标记块外的内容（你的自定义）**全部保留**。
- **旧版手写格式**（含 `macOS 通用开发环境配置（优化版）` 等特征且无 v2.0 标记）
  → 备份为 `.zshrc.legacy.<时间戳>` 后**整份重写**，
  但会**原样保留** Docker Desktop 等第三方代管段
  （`# The following lines have been added by Docker Desktop` 到 `# End of Docker CLI completions`）。

重复执行 `install` 是幂等的：实测连跑 5 次，`.zshrc` 行数稳定不变、标记块各 1 份。

### 想改自己的配置放哪

标记块**外面**。比如在文件末尾追加：

```zsh
# 我自己的配置
export MY_VAR=123
alias mycmd='echo hi'
```

下次 `install` 不会动它。

---

## 🚨 十条铁律（违反必出方框）

| # | 规则 | 违反后果 |
|---|---|---|
| 1 | R 出 PDF 写 `pdf(...)`，**不要**写 `grDevices::pdf(...)` | 绕过 cairo 重定向 → 中文全框 |
| 2 | R 出 PNG 写 `png()`；**不要**给 `ragg::agg_png()` 传 `system_fonts=` | ragg 1.5.2 没这参数 → 直接报错，图都出不来 |
| 3 | ggplot 的 `base_family` 必须是中文字体 | cairo 不做回退 → 轴标题全框 |
| 4 | `ggsave()` 存 PDF 必须传 `device = .ggsave_pdf_device` | `grDevices::pdf` 报 `invalid font type` |
| 5 | Python 绘图要 `import mpl_setup` | 没有真粗体，字体可能落到 DejaVu |
| 6 | matplotlib **不要**设 `pdf.fonttype = 42` | PingFang 是 CFF 轮廓，生成畸形 PDF |
| 7 | **不要**写字体名 `Source Han Sans SC` | 本机无此字体 → 假命中 Helvetica → 出框且**不报错** |
| 8 | Stata 矢量图用 **PDF**，**不要**用 EPS | PostScript 8-bit 编码限制，中文必变 `??` |
| 9 | Stata **不要**导出 TIF | 本机未装转换器，`translator Graph2tif not found` |
| 10 | Stata 设字体要设满 5 个子项：`fontface` / `fontfacesans` / `fontfaceserif` / `fontfacemono` / `fontfacesymbol` | 少写 `face` **不报错但静默失效** |

---

## 🔬 实测依据（为什么是这些结论）

这些结论都来自真实渲染验证，不是查文档抄来的。下表是同一个中文标题在 PDF 里的墨迹像素数（越接近 0 越说明字没画出来）：

### matplotlib `pdf.fonttype=42` 下各字体表现

| 字体 | 墨迹像素 | 轮廓格式 | 结论 |
|---|---:|---|---|
| **PingFang SC** | **0** ❌ | CFF | 文字层正确但**视觉全空**，最阴的一类 bug |
| Songti SC | 1195 ✅ | TrueType | 正常 |
| Heiti SC | 1344 ✅ | TrueType | 正常 |
| Arial Unicode MS | 1378 ✅ | TrueType | 正常 |
| Noto Sans SC | 748 ✅ | TrueType | 偏细（只有 weight 100） |

> 所以本项目**保持 `pdf.fonttype` 为默认 3**。设 42 时 Ghostscript / pymupdf / LaTeX 链路会丢字，只有 macOS 原生 Quartz 渲染正常。

### 为什么 PNG 用 PingFang，PDF 路径要特别小心

- **ragg（PNG）** 有自动字形回退，基座是英文字体也能正常渲染中文 → PNG 天然安全
- **cairo（PDF）** 精确匹配字体，缺字就画框 → PDF 是重灾区
- **PingFang SC 没有真 Bold**（最粗 600），标题粗体会退到 600，视觉可接受但不是 700

### 字体在 macOS 上的真实位置（踩坑记录）

`PingFang.ttc` 不在 `/System/Library/Fonts`，而在：

```
/System/Library/AssetsV2/com_apple_MobileAsset_Font8/<hash>/AssetData/PingFang.ttc
```

- **R 走 fontconfig**，能自动扫到 → 没问题
- **matplotlib 只扫固定几个目录 + 缓存文件**，扫不到 → 必须 `fm.fontManager.addfont()` 手动注册

### 为什么默认字体从 PingFang 改成了 Arial Unicode MS（v15.0）

**PingFang SC 没有收录数学符号。** R 的 Quartz / cairo 设备**不做逐字形回退**——一段文字用哪个 family，
该字体缺的字符就直接画成空心方框，不会自动换字体补。实测（`type="quartz"` 的 `png()` 设备，
同一串 `ρ √ → ∞ ≤ ≥ ± × ≈ ∂ ∈ ∪ ∩ 中文`）：

| 字体 | 中文 | ρ √ → ∞ ≤ ≥ ± × ≈ Σ Π ∫ α β θ Ω | ∂ ∆ ⇒ ⇔ ∈ ∉ ⊂ ⊃ ∪ ∩ ∀ ∃ |
|---|:---:|:---:|:---:|
| PingFang SC | ✅ | ❌ 全方框 | ❌ |
| Heiti SC / Songti SC | ✅ | ❌ | ❌ |
| Hiragino Sans GB | ✅ | ✅ | ❌ 全方框 |
| **Arial Unicode MS** | ✅ | ✅ | ✅ |

统计 / 计量图的标题里 `ρ`（rho）、`√`、`→`、`∞`、`∂`（偏导）、`∈`（属于）、`∪ ∩`（集合）是高频符号，
所以 **Arial Unicode MS 必须首选**；PingFang 降级为「纯中文、不含数学符号」场景的可选项
（`use_theme()` 后可手动切换）。

> 这一条不是偏好，是实测结论。用 PingFang 画 `main = "误差 e(ρ) → 0"` 时，
> 中文正常但 `ρ` 和 `→` 全部变方框——这正是 v14.0 遗留的真实 bug。

这就是为什么本项目在 `mpl_setup.py` 里加了强制注册逻辑。

---

## 🕳️ 踩过的坑（不报错但静默失效）

这些是最难查的一类，因为**程序一声不吭，图就是错的**：

1. **`Source Han Sans SC` 假命中**
   `systemfonts::match_fonts("Source Han Sans SC")` 返回 `/System/Library/Fonts/Helvetica.ttc` —— 不存在的字体名被"宽容"匹配到了英文字体。图出来全是 □，但零报错。

2. **matplotlib 字体缓存过期**
   `~/.matplotlib/fontlist-v3.11.0.json` 是 10 月 3 日的，之后装的字体它不认识。删缓存重建才行。

3. **`register_font()` 对 cairo 无效**
   ```r
   systemfonts::register_font(name = "sans", plain = "...")  # 看似成功
   grDevices::cairo_pdf()   # 实际还是 Helvetica
   ```
   cairo 设备根本不读 systemfonts 的注册表，必须显式传 `family=`。

4. **`.Renviron` 里的 `R_PROFILE_USER` 会盖掉 shell 的 export**
   测试新 profile 必须用 `Rscript --no-environ`，否则加载的还是旧的那个。

5. **Stata `gsp` 裸调用报 r(100)**
   原来用 `syntax namelist(max=1)`，不传参数就报错。改成 `syntax [anything(name=which)]` 才支持裸调。

6. **`graph set pdf` 在 Stata 18 是空操作**
   只有 `window` / `ps` / `eps` / `svg` 四个有效目标，PDF 导出实际走 `ps`。

7. **`clear all` 会连自定义命令一起清掉**（v14.1 修复）
   `gsp` / `set_plot_dir` / `freemem` 原先用 do-file 里的 `program define` 定义，
   而 Stata 的 `clear all` 会清空所有内存中的 program —— 所以 do-file 开头只要写一句
   `clear all`（极常见），`gsp` 就消失了，报 `command gsp is unrecognized`。
   修复：把三个命令改写成 **ado 文件**装进 `~/Documents/Stata/ado/personal/`，
   编译加载，`clear all` 之后依然可用。

8. **`gsp` 导出失败却返回 0**（v14.1 修复）
   图形名不存在时，Stata 只往日志里写 `rc=693`，命令本身仍返回 0，
   调用脚本会误判为成功。修复：导出前先 `graph describe` 校验，失败则 `exit 111`。

9. **`sp()` 传绝对路径会拼成怪路径**（v14.1 修复）
   `file.path(PLOT_OUTDIR, "/tmp/a.pdf")` 会得到 `<outdir>//tmp/a.pdf`，
   父目录不存在就报 `unable to start device 'cairo_pdf'`，而错误信息完全不提目录。

10. **`pdf(family = ...)` 参数冲突**（v14.1 修复）
    `pdf()` 覆盖函数若把 `family` 只放在 `...` 里，用户显式传 `family=` 会撞车：
    `formal argument "family" matched by multiple actual arguments`。
    必须把 `family` 写成正式形参。

11. **macOS 的 `head` 不支持 `-n -5`**（v14.1 修复）
    BSD head 是 GNU 之外的实现，`head -n -N` 报 `illegal line count`，
    静默导致旧备份清理失效。改用 `tail -n +N` 计算。

12. **测试时改 `HOME` 会污染真实 conda 环境**（v14.1 修复）
    脚本写 `site-packages/plot_config.pth` 时，即使用 `HOME=/tmp/xxx` 跑测试，
    也会往**真实**的 conda 里写一条指向临时目录的路径。
    修复：`HOME` 指向 `/tmp`、`/var/folders` 时拒绝写入。

---

## 📂 文件说明

```
plot-cjk-config/
├── setup_plot.sh              # 一键部署脚本（自包含，1936 行）
├── R/
│   └── .Rprofile              # R 绘图 + 性能配置（软链到 ~/.Rprofile）
├── matplotlib/
│   └── matplotlibrc           # matplotlib 全局配置（软链到 ~/.matplotlib/matplotlibrc）
├── python/
│   └── mpl_setup.py           # Python 绘图辅助（字体注册 + 输出目录）
└── Stata/
    ├── plot_stata.do          # Stata 字体配置（5 个子项 × 4 个目标）
    └── profile_main.do        # Stata 性能配置 + gsp 存图命令
```

部署后实际的软链接：

```
~/.Rprofile              -> ~/Documents/plot-config/R/.Rprofile
~/.matplotlib/matplotlibrc -> ~/Documents/plot-config/matplotlib/matplotlibrc
~/Documents/Stata/profile.do -> 桥接到 plot-config/Stata/*.do
```

### 用法示例

```r
# R
library(ggplot2)
p <- ggplot(mtcars, aes(wt, mpg)) + geom_point() +
     labs(title = "汽车重量与油耗", x = "重量", y = "油耗") +
     theme_academic

sp(p, "fig1", format = "pdf")   # -> <项目根>/figures/fig1.pdf
check_cn_plot()                  # 自检
```

```python
# Python
import mpl_setup as mp           # 必须在 pyplot 之前
import matplotlib.pyplot as plt

fig, ax = mp.new()
ax.plot([1, 2, 3], [1, 2, 3])
ax.set_title("中文标题：增速（%）")
mp.save(fig, "fig1", fmts=("png", "pdf"))
print(mp.check_cn())             # True 才算过
```

```stata
* Stata（profile.do 自动加载）
sysuse auto, clear
scatter price mpg, title("汽车价格与油耗") name(g1, replace)
gsp g1, out(myfig)               // 默认出 png + pdf
```

---

## ✅ 验证

本项目所有结论都在 **macOS (Apple Silicon) + R 4.6.1 + Python 3.13(matplotlib 3.11) + Stata 18 MP** 上实测：

| 项目 | 方法 | 结果 |
|---|---|---|
| R 六条输出路径 | `check_cn_plot()` | png/pdf/svg/base/ggsave_png/ggsave_pdf 全 OK |
| PDF 中文是否真画出 | pymupdf 渲染后统计非白像素 | 标题区墨迹 1934–5095，汉字可提取 |
| matplotlib | `check_cn()` 抓 Glyph 警告 | 缺字警告 = 0 |
| Stata | `graph export` 后 pymupdf 提取文字 | PNG/PDF 均含中文 |
| 新机器模拟 | 全新 `HOME` 跑 install + check | 通过 |
| 卸载回归 | purge | 目录已删、外部备份保留、无报错 |
| **全量清除后重建**（v14.1） | 删光四类配置再从零 install | 14 项 OK，无残留 |
| **R 边界回归**（v14.1） | 12 种写法（绝对路径/多格式/中文名/pdf family=） | 全 OK |
| **Python 边界回归**（v14.1） | 空名/绝对路径/重复后缀/中文名 | 全 OK，空名正确报错 |
| **Stata 边界回归**（v14.1） | `clear all` 后调用、图形名不存在、EPS/TIF | `clear all` 后可用；不存在图形返回 111 |

---

## ❓ 常见问题

**Q: 装完后 RStudio 里还是方框？**
重启 RStudio。`.Rprofile` 只在启动时读一次。

**Q: Jupyter 里字体不对？**
确认 `import mpl_setup` 在 `import matplotlib.pyplot` **之前**。`mpl_setup` 会在导入时强制刷新 `rcParams`。

**Q: 论文要 600 DPI 怎么办？**
```r
sp(p, "fig1", dpi = 600)              # R
```
```python
mp.save(fig, "fig1", dpi=600)          # Python
```
```stata
gsp g1, width(4800)                    # Stata，宽度翻倍
```

**Q: 装了新字体，matplotlib 不认？**
```bash
rm -rf ~/.matplotlib/fontlist-*.json
```
或直接 `import mpl_setup`（它会主动扫描并注册）。

**Q: 为什么不用思源黑体 / 更纱黑体？**
装了也能用，但本项目的默认选择是**系统自带、零安装**。
思源黑体可变字体只有 weight 250，Noto Sans SC 只有 100，都会让标题异常纤细。
PingFang 覆盖 100–600 最稳。

**Q: Linux / Windows 能用吗？**
不能。脚本开头有平台检查，只支持 macOS。Linux 需要改字体名（Noto Sans CJK）并装 `fontconfig`。

---

## 📄 许可证

[MIT](https://opensource.org/licenses/MIT) © 白澤 程

---

<div align="center">

**[⬆ 回到顶部](#macos-中文绘图配置--r--python--stata)** · **[🏠 主页](https://wpc6666.github.io/)**

</div>
