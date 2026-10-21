#!/usr/bin/env bash
# ==============================================================
#  macOS 中文绘图 + 性能配置 + 终端环境 · 一键部署  v15.0
#
#  目标：① R / Python / Stata 任何输出格式都不出现中文豆腐块
#        ② 默认 300 DPI 高清输出
#        ③ ~/.zshrc 通用开发环境（镜像降级 / PATH 幂等 / 别名函数）
#
#  本脚本完全自包含，不依赖任何外部文件，单文件即可部署到新机器。
#
#  用法：
#    bash setup_plot.sh            交互菜单
#    bash setup_plot.sh install    直接部署（会先备份）
#    bash setup_plot.sh check      环境体检 + 出图自检
#    bash setup_plot.sh deps       查看缺失依赖的安装命令
#    bash setup_plot.sh dry-run    只打印将要做什么，不落盘
#    bash setup_plot.sh uninstall  卸载（保留配置目录与备份）
#    bash setup_plot.sh purge      彻底清理（删除配置目录）
#    bash setup_plot.sh version    版本号
#    bash setup_plot.sh help       帮助
#
#  环境变量（可选）：
#    PLOT_FONT     指定中文字体名，跳过自动检测
#    PLOT_DPI      默认输出 DPI，默认 300
#    PLOT_THREADS  BLAS/OpenMP 线程数，默认物理核数 - 1
# ==============================================================
set -euo pipefail

readonly SCRIPT_VERSION="v15.0"
# 配置目录：默认 ~/Documents/plot-config。
# 允许用 PLOT_CFG 覆盖——DevConfig 仓库用它把「配置源」直接指向仓库本身，
# 这样新电脑 clone 后部署的是仓库里的配置，而不是凭空生成一份。
readonly CFG="${PLOT_CFG:-${HOME}/Documents/plot-config}"
readonly MPL_DIR="${CFG}/matplotlib"
readonly R_DIR="${CFG}/R"
readonly PY_DIR="${CFG}/python"
readonly ST_DIR="${CFG}/Stata"
readonly BAK="${CFG}/backup"
readonly LOG="${CFG}/logs/setup.log"

readonly MPL_RC="${MPL_DIR}/matplotlibrc"
readonly R_PROF="${R_DIR}/.Rprofile"
readonly PY_MOD="${PY_DIR}/mpl_setup.py"
readonly ST_MAIN="${ST_DIR}/profile_main.do"
readonly ST_PLOT="${ST_DIR}/plot_stata.do"
readonly ST_BRIDGE="${HOME}/Documents/Stata/profile.do"
readonly RENV="${HOME}/.Renviron"

MODE="menu"
TS="$(date '+%Y%m%d_%H%M%S')"
SNAP="${BAK}/${SCRIPT_VERSION}_${TS}"   # 跟随 SCRIPT_VERSION，不再硬编码版本号
KEEP_BAK=5

if [[ -t 1 ]] && command -v tput &>/dev/null; then
  C_I="$(tput setaf 7)"; C_K="$(tput setaf 2)"; C_W="$(tput setaf 3)"
  C_E="$(tput setaf 1)"; C_R="$(tput sgr0)"
else
  C_I=""; C_K=""; C_W=""; C_E=""; C_R=""
fi

NO_FILELOG=0   # purge 删掉配置目录后置 1，避免往已删除的路径写日志

# 临时目录登记与退出清理：do_check 里会用 mktemp -d 建 Stata 体检目录，
# 正常路径末尾有 rm -rf，但中途 Ctrl+C / 报错退出就会残留在 /var/folders。
# 这里统一登记 + trap，保证异常退出也清干净。
_TMP_DIRS=()
_cleanup_tmp() {
  local d
  for d in "${_TMP_DIRS[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
  return 0
}
trap '_cleanup_tmp' EXIT INT TERM

log()  { local lv="$1"; shift; local c=""
         case "$lv" in OK) c="$C_K";; WARN) c="$C_W";; ERROR) c="$C_E";; *) c="$C_I";; esac
         printf '%s[%s] %s%s\n' "$c" "$lv" "$*" "$C_R"
         if [[ $NO_FILELOG -eq 0 ]]; then
           case "$MODE" in
             install|uninstall|purge)
               printf '[%s] [%s] %s\n' "$(date '+%H:%M:%S')" "$lv" "$*" >>"$LOG" 2>/dev/null || true ;;
           esac
         fi; }
info() { log INFO  "$@"; }
ok()   { log OK    "$@"; }
warn() { log WARN  "$@"; }
err()  { log ERROR "$@" >&2; }

# --------------------------------------------------------------
# 环境探测
# --------------------------------------------------------------
case "${SHELL:-}" in
  */zsh)  RC="${HOME}/.zshrc" ;;
  */bash) RC="${HOME}/.bash_profile" ;;
  *)      RC="${HOME}/.profile" ;;
esac

export PLOT_DPI="${PLOT_DPI:-300}"
export PLOT_THREADS="${PLOT_THREADS:-$(sysctl -n hw.physicalcpu 2>/dev/null || echo 4)}"
[[ "$PLOT_THREADS" -gt 1 ]] && PLOT_THREADS=$((PLOT_THREADS - 1)) || PLOT_THREADS=1

# 中文字体探测 —— v15.0 重排：符号全量字优先
#
# 【为什么不再优先 PingFang（实测结论）】
# PingFang SC 不含 ρ √ → ∞ ≤ ≥ ± × ∂ ∈ ∪ ∩ 等数学符号，
# 而 R 的 Quartz / cairo 设备【不做逐字形回退】，缺字直接画空心方框。
# 实测同一串 "ρ √ → ∞ ≤ ≥ ± × ≈ 中文"：
#   PingFang SC      中文正常，符号全方框
#   Hiragino Sans GB 基础符号正常，∂∆⇒∈∪∩ 全方框
#   Arial Unicode MS 中文 + 全部符号正常  ← 首选
# 统计图标题里这些符号是高频的，所以全量字必须优先。
detect_font() {
  [[ -n "${PLOT_FONT:-}" ]] && { echo "$PLOT_FONT"; return; }

  # 1) 符号全量字优先：Arial Unicode MS（23MB 全 CJK + 全数学符号）
  local u
  for u in \
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf" \
    "/Library/Fonts/Arial Unicode.ttf"
  do
    [[ -f "$u" ]] && { echo "Arial Unicode MS"; return; }
  done

  # 2) 次选：Hiragino Sans GB（基础数学符号 OK，字形清秀）
  for u in \
    "/System/Library/Fonts/Hiragino Sans GB.ttc" \
    "/System/Library/Fonts/Supplemental/Hiragino Sans GB.ttc"
  do
    [[ -f "$u" ]] && { echo "Hiragino Sans GB"; return; }
  done

  # 3) PingFang（纯中文场景可用，含数学符号的图表不要用）。
  #    注意：新版 macOS 把它放在 AssetsV2 的 hash 目录里，不在 /System/Library/Fonts。
  local pf
  for pf in \
    "/System/Library/Fonts/PingFang.ttc" \
    "/System/Library/Fonts/Supplemental/PingFang.ttc" \
    "/System/Library/AssetsV2/com_apple_MobileAsset_Font"*/*.asset/AssetData/PingFang.ttc
  do
    [[ -f "$pf" ]] && { echo "PingFang SC"; return; }
  done

  # 2) 其它系统自带中文字体，按字重完整性排序
  local cands=(
    "STHeiti Medium.ttc|Heiti SC"
    "Songti.ttc|Songti SC"
    "Arial Unicode.ttf|Arial Unicode MS"
  )
  local dirs=(
    "/System/Library/Fonts"
    "/System/Library/Fonts/Supplemental"
    "/Library/Fonts"
    "${HOME}/Library/Fonts"
  )
  local d f name
  for f in "${cands[@]}"; do
    name="${f##*|}"
    for d in "${dirs[@]}"; do
      [[ -f "${d}/${f%%|*}" ]] && { echo "$name"; return; }
    done
  done

  # 3) 用户自装的思源/Noto
  local u
  for u in "${HOME}/Library/Fonts/SourceHanSans"* "${HOME}/Library/Fonts/NotoSansSC"*; do
    [[ -f "$u" ]] && { echo "Source Han Sans VF"; return; }
  done

  echo "Arial Unicode MS"
}

find_python() {
  # 【v15.0 改法】原来按固定顺序试，第一个候选是 envs/it —— 但那个环境
  # 可能被重建过（实测：it 存在但没有 matplotlib），于是白试一轮才落到别的。
  # 现在改为「遍历所有候选，只认真正能 import matplotlib 的那个」，
  # 并把 conda base 也纳入候选（实测本机 base 有完整科学栈：
  # numpy 2.4 / pandas 3.0 / scipy 1.18 / matplotlib 3.11）。
  #
  # 优先级说明：conda 环境排在 Homebrew 之前，因为 conda 通常带完整科学栈；
  # 但最终判据是「能不能 import matplotlib」，不是路径长短。
  local c
  for c in \
    "${PLOT_PYTHON:-}" \
    "/opt/homebrew/anaconda3/envs/it/bin/python" \
    "/opt/homebrew/anaconda3/bin/python3" \
    "${HOME}/anaconda3/bin/python3" \
    "${HOME}/miniconda3/bin/python3" \
    "/opt/homebrew/bin/python3" \
    "/usr/local/bin/python3" \
    "$(command -v python3 2>/dev/null || true)"
  do
    [[ -n "$c" && -x "$c" ]] || continue
    # python 括号版本要排除掉（-config / -doc 之类不是解释器）
    case "$c" in *-config|*-doc) continue ;; esac
    if "$c" -c "import matplotlib" &>/dev/null; then echo "$c"; return; fi
  done
  command -v python3 2>/dev/null || echo ""
}

find_stata() {
  local roots=("/Applications/Stata" "/Applications" "/Applications/Stata18"
               "/Applications/Stata18/Stata" "/Applications/StataNow" "${HOME}/Applications")
  local apps=(StataMP StataSE StataBE Stata)
  local exes=(stata-mp stata-se stata-be stata StataMP StataSE StataBE Stata)
  local r a e p
  for r in "${roots[@]}"; do
    [[ -d "$r" ]] || continue
    for a in "${apps[@]}"; do
      [[ -d "$r/${a}.app" ]] || continue
      for e in "${exes[@]}"; do
        p="$r/${a}.app/Contents/MacOS/$e"
        [[ -x "$p" ]] && { echo "$p"; return; }
      done
    done
  done
  local c
  for c in stata-mp stata-se stata-be stata; do
    command -v "$c" &>/dev/null && { command -v "$c"; return; }
  done
  echo ""
}

CN_FONT="$(detect_font)"
PYTHON="$(find_python)"
PLOT_PY="${PYTHON}"   # 钉给 .zshrc 用：保证裸敲 python3 落到装了 matplotlib 的解释器
STATA="$(find_stata)"
RSCRIPT="$(command -v Rscript 2>/dev/null || echo '')"

# --------------------------------------------------------------
# 文件写入
# --------------------------------------------------------------
ensure_dirs() {
  [[ "$MODE" == dry-run ]] && { info "[DRY] mkdir -p ${CFG}/{matplotlib,R,python,Stata,backup,logs}"; return; }
  mkdir -p "$MPL_DIR" "$R_DIR" "$PY_DIR" "$ST_DIR" "$BAK" "${CFG}/logs"
  mkdir -p "$(dirname "$ST_BRIDGE")"
  mkdir -p "${HOME}/.matplotlib"
}

snapshot() {
  [[ "$MODE" == dry-run ]] && { info "[DRY] 备份 -> ${SNAP}"; return; }
  mkdir -p "$SNAP"
  local f
  for f in "$MPL_RC" "$R_PROF" "$PY_MOD" "$ST_MAIN" "$ST_PLOT" "$RENV"; do
    [[ -f "$f" ]] && cp -p "$f" "${SNAP}/" 2>/dev/null || true
  done
  [[ -f "$ST_BRIDGE" ]] && cp -p "$ST_BRIDGE" "${SNAP}/profile.do" 2>/dev/null || true
  [[ -f "$RC" ]] && cp -p "$RC" "${SNAP}/$(basename "$RC")" 2>/dev/null || true
  # 【删除守卫】这里原本会自动 rm -rf 掉超过 KEEP_BAK 份的旧备份。
  # 按用户 AGENTS.md 的「严禁自主推断并执行永久删除」，改为【只提示不删除】：
  # 备份是安全网，安全网不该自己动手剪。要清理由用户手动确认后执行。
  # 注意：macOS 是 BSD head，不支持 `head -n -N`（GNU 写法会报 illegal line count）。
  local old n
  old="$(ls -1td "${BAK}"/v*_* 2>/dev/null || true)"
  n="$(printf '%s\n' "$old" | grep -c . 2>/dev/null || true)"
  if [[ "${n:-0}" -gt "$KEEP_BAK" ]]; then
    warn "备份已有 ${n} 份（保留上限 ${KEEP_BAK}），以下旧备份未自动删除，请自行确认后清理："
    printf '%s\n' "$old" | tail -n +$((KEEP_BAK + 1)) | sed 's/^/        /'
    info "手动清理命令示例：rm -rf <上面列出的路径>"
  fi
  ok "已备份到 ${SNAP}"
}

w() { # w <目标路径> <标注>
  [[ "$MODE" == dry-run ]] && { info "[DRY] 写入 ${1}"; cat >/dev/null; return; }
  mkdir -p "$(dirname "$1")"
  cat > "$1"
  ok "写入 ${1}"
}

# --------------------------------------------------------------
# 1. matplotlib
# --------------------------------------------------------------
write_matplotlibrc() {
  w "$MPL_RC" <<EOF
# matplotlibrc — 中文绘图配置 ${SCRIPT_VERSION}（$(date '+%Y-%m-%d') 生成）
# 由 setup_plot.sh 管理，手工改动会被下次部署覆盖。
# 备份在 ~/Documents/plot-config/backup/

# ── 字体 ─────────────────────────────────────────────────────
font.family        : sans-serif
# 【v15.0】排序依据改为「符号覆盖率」，不再按字重：
#   Arial Unicode MS        中文 + ρ√→∞≤≥±×≈∂∈∪∩ 全符号覆盖  ← 首选
#   Hiragino Sans GB        中文正常、基础符号正常，生僻符号出框
#   PingFang SC             weight 100-600 粗体真生效，但数学符号全缺
#   Heiti SC                weight 300,400，真 glyf 轮廓
#   Songti SC               weight 300-900，唯一有真 bold 的衬线体
#   Noto Sans SC            本机只有 weight 100（Thin）→ 标题发虚、bold 失效
#   Source Han Sans VF      本机只有 weight 250（ExtraLight）→ 同上
# matplotlib 不做逐字形回退，只按首位取字。统计图标题里 ρ √ → ∞ 是
# 高频符号，所以「不缺字」优先于「字形好看」。
# 注意：不要写 "Source Han Sans SC"，本机无此字体，
#       fc-match 会假命中 Helvetica.ttc，中文直接出框。
font.sans-serif    : ${CN_FONT}, Hiragino Sans GB, PingFang SC, Heiti SC, Songti SC, Arial Unicode MS, Noto Sans SC, Source Han Sans VF, DejaVu Sans, sans-serif

# 负号：False 才会显示 U+2212 而不是方块
axes.unicode_minus : False

# ── 尺寸与分辨率 ─────────────────────────────────────────────
figure.dpi         : 150      # 屏幕预览
savefig.dpi        : ${PLOT_DPI}       # 保存文件（高清）
figure.figsize     : 9, 6
savefig.bbox       : tight
savefig.pad_inches : 0.1
savefig.facecolor  : white

# ── 排版 ─────────────────────────────────────────────────────
figure.autolayout  : False
figure.subplot.left   : 0.12
figure.subplot.right  : 0.95
figure.subplot.bottom : 0.12
figure.subplot.top    : 0.92

font.size          : 11
axes.titlesize     : 13
axes.titleweight   : bold
axes.labelsize     : 11
xtick.labelsize    : 10
ytick.labelsize    : 10
legend.fontsize    : 10

# ── 输出格式 ─────────────────────────────────────────────────
# pdf.fonttype 保持默认 3，不要设 42：
#   PingFang SC 是 CFF 轮廓，写 42 会生成「名义 Type42、实际 CFF」的畸形
#   PDF，MuPDF 系渲染器（pymupdf / 部分在线阅读器 / 部分投稿系统）里
#   中文整段消失，但 Preview 和 Ghostscript 却正常，极难排查。
# svg.fonttype=none 保留 <text>，否则文字全转曲，搜不到也改不了字体。
svg.fonttype       : none
EOF
}

# --------------------------------------------------------------
# 2. R .Rprofile
# --------------------------------------------------------------
write_rprofile() {
  w "$R_PROF" <<'RPROF_EOF'
# ==============================================================
#  R .Rprofile — 中文绘图 + 性能配置  v15.0
#  由 setup_plot.sh 生成。备份在 ~/Documents/plot-config/backup/
#
#  四条核心修复（全部是实测出来的 bug，不是猜测）：
#   1. 不用 ragg::agg_png(..., system_fonts=) —— ragg ≥1.3 无此参数，
#      任何 png() 调用报 "unused argument (system_fonts = ...)" 直接失败。
#      ragg 本身对缺失字形会自动回退，不需要手动指定字体链。
#   2. pdf() 重定向到 cairo_pdf(family=cn_font)。默认 pdf() 只嵌 Helvetica，
#      中文全部变豆腐块，且报 "conversion failure ... in 'mbcsToSbcs'"。
#   3. 中文字体优先 PingFang SC。Noto Sans SC 实测 weight=100（Thin）、
#      Source Han Sans VF 实测 weight=250（ExtraLight），放首位会发烧、
#      且粗体完全失效。PingFang SC 覆盖 100-600，粗细正常。
#   4. 【v15.0】PingFang SC 没有收录 ρ √ → ∞ ≤ ≥ ± × 等数学符号！
#      而 R 的 Quartz/cairo 设备【不做逐字形回退】——一段文字用哪个
#      family，该字体缺的字就直接画空心方框，不会自动换字体补。
#      经实测（type="quartz" 设备，同一串 "ρ √ → ∞ ≤ ≥ ± × ≈ 中文"）：
#        PingFang SC      中文正常，但 ρ√→∞≤≥±×≈ 全方框
#        Heiti SC/Songti  同上
#        Hiragino Sans GB 基础数学符号正常，但 ∂∆⇒⇔∈∉⊂⊃∪∩∀∃ 全方框
#        Arial Unicode MS 中文 + 全部符号正常（覆盖最全）
#      统计图标题里 ρ、√、→、∞、≤、≥、∂、∈ 是高频符号，
#      所以 Arial Unicode MS 必须是首选，PingFang 降为「纯中文场景」备选。
#
#  补充：R 走 fontconfig（fc-match），能正常匹配 PingFang SC。
#        这与 matplotlib 不同（matplotlib 自己扫目录，看不见 AssetsV2
#        里的 PingFang），所以 R 侧不需要额外注册字体文件。
# ==============================================================

options(encoding = "UTF-8")
invisible(try(Sys.setlocale("LC_ALL", "zh_CN.UTF-8"), silent = TRUE))
options(scipen = 999)

# ---------------- 线程 ----------------
.n_threads <- local({
  v <- suppressWarnings(as.integer(Sys.getenv("PLOT_THREADS", "")))
  if (!is.na(v) && v >= 1) return(v)
  nc <- tryCatch(as.integer(system2("sysctl", c("-n", "hw.physicalcpu"),
                                    stdout = TRUE, stderr = FALSE)),
                 error = function(e) NA_integer_)
  if (is.na(nc) || nc < 1) nc <- parallel::detectCores(logical = FALSE)
  if (is.na(nc) || nc < 1) nc <- 4L
  max(1L, nc - 1L)
})
options(Ncpus = .n_threads)

if (requireNamespace("data.table", quietly = TRUE)) {
  data.table::setDTthreads(threads = .n_threads)
  options(datatable.optimize = Inf)
}

# ---------------- 字体检测 ----------------
.has_font <- function(name) {
  if (!requireNamespace("systemfonts", quietly = TRUE)) return(FALSE)
  r <- tryCatch(systemfonts::match_fonts(name), error = function(e) NULL)
  !is.null(r) && nrow(r) > 0 && !is.na(r$path[1])
}

.detect_mode <- function() {
  m <- Sys.getenv("THEME_MODE", "auto")
  if (m %in% c("thesis", "sci")) return(m)
  if (.has_font("PingFang SC") || .has_font("Heiti SC")) return("thesis")
  if (.has_font("Songti SC") || .has_font("Arial Unicode MS")) return("sci")
  "fallback"
}

# 中文字体池 —— v15.0 重排：把「符号全量字」提到最前
#
# 【为什么必须换顺序（实测结论，不是偏好）】
# 在 Quartz/cairo 设备下 R 不做逐字形回退：一段文字用哪个 family，
# 该字体缺的字符就直接画空心方框，不会自动换字体补。
# 实测（type="quartz" 的 png 设备，同一段 "ρ √ → ∞ ≤ ≥ ± × ≈ 中文"）：
#   PingFang SC       -> 中文正常，但 ρ√→∞≤≥±×≈ 全部方框
#   Heiti SC / Songti -> 同上
#   Hiragino Sans GB  -> 中文 + 基础数学符号正常（ρ√→∞≤≥±×ΣΠ∫αβθΩ✓★●○■）
#                        但 ∂∆⇒⇔∈∉⊂⊃∪∩∀∃ 全部方框
#   Arial Unicode MS  -> 中文 + 上面两组的全部符号正常（覆盖最全）
# 经济统计/计量类图表里 ∂（偏导）、∈（属于）、∪∩（集合）、⇒（蕴含）是高频符号，
# 因此 Arial Unicode MS 必须是首选；Hiragino 作次选（字形更清秀，
# 但只在你确定标题里不含 ∂∆⇒∈∪∩ 时手动 use_theme() 切换）。
.pick_cn <- function(m) {
  pool <- switch(m,
    thesis  = c("Arial Unicode MS", "Hiragino Sans GB",
                "PingFang SC", "Heiti SC", "Songti SC",
                "Noto Sans SC", "Source Han Sans VF"),
    sci     = c("Songti SC", "Arial Unicode MS", "Hiragino Sans GB",
                "PingFang SC", "Heiti SC",
                "Noto Sans SC", "Source Han Sans VF"),
    fallback= c("Arial Unicode MS", "Hiragino Sans GB", "PingFang SC", "Heiti SC")
  )
  for (f in pool) if (.has_font(f)) return(f)
  "Arial Unicode MS"
}

# 英文/数字字体：必须自己带 CJK 字形，或者干脆和中文用同一字体。
# Liberation Sans / DejaVu Sans 没有 CJK，cairo_pdf 下会出豆腐块，
# 所以 PDF 路径统一走 cn_font。
.pick_en <- function(m) {
  if (m == "sci") {
    if (.has_font("Liberation Sans")) return("Liberation Sans")
    if (.has_font("DejaVu Sans")) return("DejaVu Sans")
  }
  .pick_cn(m)
}

.rc_mode  <- .detect_mode()
cn_font   <- .pick_cn(.rc_mode)
en_font   <- .pick_en(.rc_mode)
math_font <- if (.has_font("DejaVu Sans")) "DejaVu Sans" else en_font

# ---------------- 输出目录 ----------------
.get_project_root <- function() {
  if (requireNamespace("here", quietly = TRUE)) {
    p <- tryCatch(here::here(), error = function(e) NULL)
    if (!is.null(p) && nzchar(p)) return(normalizePath(p, mustWork = FALSE))
  }
  d <- normalizePath(getwd(), mustWork = FALSE)
  markers <- c(".git", ".Rproj.user", "DESCRIPTION", "renv.lock",
               ".project-root", "pyproject.toml")
  for (i in 1:20) {
    if (any(file.exists(file.path(d, markers))) ||
        length(list.files(d, pattern = "\\.Rproj$")) > 0) return(d)
    parent <- dirname(d)
    if (parent == d) break
    d <- parent
  }
  normalizePath(getwd(), mustWork = FALSE)
}

.resolve_outdir <- function() {
  explicit <- Sys.getenv("PLOT_OUTDIR", "")
  if (nzchar(explicit)) return(explicit)
  mode <- tolower(Sys.getenv("PLOT_OUTDIR_MODE", "project"))
  root <- switch(mode,
    fixed   = file.path(Sys.getenv("HOME"), "figures"),
    cwd     = normalizePath(getwd(), mustWork = FALSE),
    project = .get_project_root(),
    .get_project_root()
  )
  file.path(root, "figures")
}

PLOT_OUTDIR <- .resolve_outdir()
if (!dir.exists(PLOT_OUTDIR)) dir.create(PLOT_OUTDIR, recursive = TRUE)
PLOT_DPI <- as.numeric(Sys.getenv("PLOT_DPI", "300"))

set_plot_dir <- function(path = NULL) {
  if (is.null(path)) path <- .resolve_outdir()
  if (!dir.exists(path)) dir.create(path, recursive = TRUE)
  assign("PLOT_OUTDIR", path, envir = .GlobalEnv)
  cat(sprintf("[set_plot_dir] %s\n", path))
  invisible(path)
}

.plot_n <- new.env(); .plot_n$n <- 0
.next_id <- function() {
  .plot_n$n <- .plot_n$n + 1
  sprintf("fig_%03d", .plot_n$n)
}

# 建父目录：设备启动前父目录不存在会直接 "unable to start device"，
# 而且报错信息完全不提目录，很难查。
.ensure_parent <- function(path) {
  d <- dirname(path)
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  invisible(path)
}

# ---------------- 全局默认字体（v15.0 核心修复） ----------------
# 【为什么必须加这一段】
# 前面把 pdf() 重定向到 cairo_pdf(family=cn_font) 只解决了「显式开设备」的情况。
# 但 RStudio 的看图窗口走 Quartz 设备，plot() 默认 par(family="")，
# 底层落到 Helvetica —— 该字体没有 CJK 字形，中文全部渲染成方框。
# 实测（Rscript + type="quartz" 的 png 设备）：
#   不加 options -> 标题 "误差本身 e(ρ) → 0" 全部变方框（已截图确认）
# 所以必须把 family 写进设备默认值，而不是每次调用手动传。
.set_cn_par <- function() {
  ok <- FALSE
  for (d in dev.list()) {
    try({
      # 只改 family 与中文字体相关项，不动用户自己的 par 设置
      par(family = cn_font)
      ok <- TRUE
    }, silent = TRUE)
  }
  invisible(ok)
}

# 每张新图开始前补一次（RStudio 图形窗口同理生效）
setHook("before.plot.new", function(...) .set_cn_par(), "replace")
setHook("plot.new",        function(...) .set_cn_par(), "replace")

# ---------------- 设备重定向（核心） ----------------
if (capabilities("cairo")) {
  .cairo_pdf_orig <- grDevices::cairo_pdf
  .png_orig       <- grDevices::png

  # cairo_pdf：显式 family=cn_font（cairo 不做字形回退，必须指定）
  assign("cairo_pdf", function(filename = "Rplots.pdf", width = 9, height = 6,
                               family = cn_font, ...) {
    .cairo_pdf_orig(filename = filename, width = width, height = height,
                    family = family, ...)
  }, envir = .GlobalEnv)

  # pdf()：改成 cairo_pdf 实现，否则中文出框。
  # family 必须写成正式形参：否则用户调 pdf(family="x") 时，
  # 实参 family 会同时匹配形参和 ...，报 "matched by multiple actual arguments"。
  assign("pdf", function(file = "Rplots.pdf", width = 9, height = 6,
                         family = cn_font, ...) {
    .cairo_pdf_orig(filename = file, width = width, height = height,
                    family = family, ...)
  }, envir = .GlobalEnv)
}

if (requireNamespace("ragg", quietly = TRUE)) {
  # png()：走 ragg（对缺失字形自动回退，中英混排也不出框）
  #
  # 【v15.0】must accept type= / bg= / pointsize= 等 grDevices::png 的形参。
  # 直接把 ... 透传给 ragg::agg_png 时，写 png(..., type="quartz") 会报
  #   "unused argument (type = \"quartz\")"
  # ——用户按老习惯写 type= 就炸，而且报错完全不提是重定向导致的。
  # 这里把 grDevices 独有的参数显式吃掉（bg 映射到 background），
  # 其余仍透传，行为与原生 png() 对齐。
  assign("png", function(filename = "Rplot%03d.png",
                         width = 9, height = 6,
                         units = "in", res = PLOT_DPI,
                         type = NULL, bg = "white",
                         pointsize = 12, ...) {
    ragg::agg_png(filename = filename, width = width, height = height,
                  units = units, res = res, background = bg, ...)
  }, envir = .GlobalEnv)
} else if (capabilities("cairo")) {
  assign("png", function(filename = "Rplot%03d.png",
                         width = 9, height = 6,
                         units = "in", res = PLOT_DPI, ...) {
    .png_orig(filename = filename, width = width, height = height,
              units = units, res = res, type = "cairo", ...)
  }, envir = .GlobalEnv)
}

# ---------------- 快速存图 ----------------
sp <- function(x, name = NULL, width = 9, height = 6,
               dpi = PLOT_DPI, open_window = FALSE,
               format = "png", ...) {
  if (is.null(name)) name <- .next_id()
  format <- tolower(format)
  is_gg <- inherits(x, "ggplot") || inherits(x, "gg")

  if (open_window) {
    if (capabilities("aqua")) {
      grDevices::quartz(width = width, height = height, title = name)
      par(family = cn_font)
    } else {
      grDevices::dev.new(width = width, height = height, noRStudioGD = TRUE)
    }
  }

  # 支持一次出多种格式：sp(p, "fig1", format = c("png", "pdf"))
  formats <- format
  out_paths <- character(0)

  for (fmt in formats) {
    # 名字已带同名扩展名时不再追加，避免 "dup.pdf" 变成 "dup.pdf.pdf"
    stem <- if (grepl(paste0("\\.", fmt, "$"), name, ignore.case = TRUE)) name
            else paste0(name, ".", fmt)
    path <- if (grepl("^(/|~)", name) || grepl(.Platform$file.sep, name, fixed = TRUE)) {
      path.expand(stem)
    } else {
      file.path(PLOT_OUTDIR, stem)
    }
    .ensure_parent(path)

    if (fmt == "pdf") {
      grDevices::cairo_pdf(path, width = width, height = height, family = cn_font)
    } else if (fmt == "svg") {
      grDevices::svg(path, width = width, height = height)
    } else if (requireNamespace("ragg", quietly = TRUE)) {
      ragg::agg_png(path, width = width, height = height, units = "in", res = dpi)
    } else {
      grDevices::png(path, width = width, height = height,
                     units = "in", res = dpi, type = "cairo")
    }

    if (is_gg) print(x)
    else if (is.function(x)) x()
    else if (inherits(x, "formula")) eval(x[[length(x)]])
    else print(x)

    grDevices::dev.off()
    message(sprintf("[sp] %s", path))
    out_paths <- c(out_paths, path)
  }

  invisible(out_paths)
}

# ---------------- ggplot 主题 ----------------
# ggsave(device=grDevices::pdf) 配中文字体会报 "invalid font type"，
# 必须用 cairo_pdf；base_family 也必须是 cn_font。
.ggsave_pdf_device <- function(filename, ...) {
  grDevices::cairo_pdf(filename = filename, family = cn_font, ...)
}

.rebuild_theme <- function() {
  if (!requireNamespace("ggplot2", quietly = TRUE)) return(invisible())
  theme_academic <<- ggplot2::theme_minimal(base_family = cn_font) +
    ggplot2::theme(
      plot.title    = ggplot2::element_text(family = cn_font, size = 14, hjust = 0.5),
      plot.subtitle = ggplot2::element_text(family = cn_font, size = 12),
      axis.title    = ggplot2::element_text(family = cn_font, size = 12),
      axis.text     = ggplot2::element_text(family = cn_font, size = 10),
      legend.text   = ggplot2::element_text(family = cn_font, size = 10),
      legend.title  = ggplot2::element_text(family = cn_font, size = 11),
      strip.text    = ggplot2::element_text(family = cn_font, size = 10),
      panel.grid.minor = ggplot2::element_blank()
    )
  ggplot2::theme_set(ggplot2::theme_grey(base_family = cn_font))
  invisible(theme_academic)
}
.rebuild_theme()

use_theme <- function(mode) {
  if (!mode %in% c("thesis", "sci", "auto")) stop("mode 需为 thesis/sci/auto")
  Sys.setenv(THEME_MODE = mode)
  m <- if (mode == "auto") .detect_mode() else mode
  assign(".rc_mode", m, envir = .GlobalEnv)
  assign("cn_font", .pick_cn(m), envir = .GlobalEnv)
  assign("en_font", .pick_en(m), envir = .GlobalEnv)
  .rebuild_theme()
  cat(sprintf("[use_theme] %s | cn=%s | en=%s\n", m, cn_font, en_font))
  invisible(m)
}

# ---------------- 自检 ----------------
check_cn_plot <- function() {
  res <- list()
  p <- if (requireNamespace("ggplot2", quietly = TRUE)) {
    ggplot2::ggplot(data.frame(x = 1:3, y = 1:3), ggplot2::aes(x, y)) +
      ggplot2::geom_line() +
      ggplot2::labs(title = "中文标题：增速", x = "年份（年）", y = "增速（%）") +
      theme_academic
  } else NULL

  tmp <- tempfile(); dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  try_dev <- function(tag, expr) {
    r <- tryCatch({ force(expr); "OK" },
                  error = function(e) paste("FAIL:", conditionMessage(e)))
    res[[tag]] <<- r
    cat(sprintf("  %-14s %s\n", tag, r))
  }

  cat("[check_cn_plot] 中文字体 =", cn_font, "\n")
  try_dev("png",  { png(file.path(tmp, "a.png"), 6, 3); print(p); dev.off() })
  try_dev("pdf",  { pdf(file.path(tmp, "a.pdf"), 6, 3); print(p); dev.off() })
  try_dev("svg",  { svg(file.path(tmp, "a.svg"), 6, 3); print(p); dev.off() })
  try_dev("base", { png(file.path(tmp, "b.png"), 6, 3)
                    plot(1:3, main = "中文标题", xlab = "年份（年）", ylab = "增速（%）")
                    dev.off() })
  if (requireNamespace("ggplot2", quietly = TRUE)) {
    try_dev("ggsave_png", { ggplot2::ggsave(file.path(tmp, "c.png"), p, width = 6, height = 3) })
    try_dev("ggsave_pdf", { ggplot2::ggsave(file.path(tmp, "c.pdf"), p, width = 6, height = 3,
                                            device = .ggsave_pdf_device) })
  }
  invisible(res)
}

local({
  ver  <- paste(R.version$major, R.version$minor, sep = ".")
  plat <- if (grepl("aarch64", R.version$platform)) "ARM64" else "x86_64"
  cat(sprintf("[R %s | %s | %s]\n", ver, plat, .rc_mode))
  cat(sprintf("  cn=%s | en=%s | threads=%d\n", cn_font, en_font, .n_threads))
  cat(sprintf("  out=%s\n", PLOT_OUTDIR))
})
RPROF_EOF
}

# --------------------------------------------------------------
# 3. Python mpl_setup.py
# --------------------------------------------------------------
write_pymod() {
  w "$PY_MOD" <<'PY_EOF'
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
PY_EOF
}

# --------------------------------------------------------------
# 4. Stata
# --------------------------------------------------------------
write_stata() {
  w "$ST_PLOT" <<EOF
* ==============================================================
*  plot_stata.do — Stata 中文字体配置  ${SCRIPT_VERSION}
*  由 ${SCRIPT_VERSION} 生成，备份在 ~/Documents/plot-config/backup/
* ==============================================================
*
* ── 为什么每个目标要设 5 项 ──────────────────────────────────
* graph set 的每个目标（ps / eps / svg / window）下都有五项：
*     fontface / fontfacesans / fontfaceserif / fontfacemono / fontfacesymbol
* 默认分别是 Helvetica / Times / Courier / Symbol —— 全都不含中文。
* 只设 fontface 时，走 sans 的元素（刻度、注释）会回退到 Helvetica，
* 中文照样出豆腐块。实测：只设 fontface 时 SVG 里 font-family 混杂；
* 5 项全设后 11 处 font-family 全部一致，中文正常。
*
* ── 各格式中文实测结论（Stata 18 MP / macOS ARM64）────────────
*   PNG  ✅ 正常
*   PDF  ✅ 正常。Stata 的 PDF 导出会把 CJK 强制嵌 ArialUnicodeMS，
*          不管 fontface 设什么都一样，所以 PDF 中文永远安全，
*          且文字可提取（可检索、可复制）。
*   SVG  ✅ 正常且认 fontface，但只写字体名不嵌字体 ——
*          拿到没装该字体的机器上会掉字，跨机器交付请用 PDF。
*   EPS  ❌ 中文必然变问号 ??。这是 PostScript 8-bit 编码限制，
*          换任何字体都救不了（Arial Unicode MS / Helvetica 实测都是 ??）。
*   TIF  ❌ 本机未装 Graph2tif 转换器，
*          graph export x.tif 报 "translator Graph2tif not found / r(111)"。
*
* ── 注意 ────────────────────────────────────────────────────
* "graph set pdf fontface" 在 Stata 18 是空操作（没有 pdf 目标），
* PDF 导出实际走 ps 目标。所以这里设 ps 而不是 pdf。
* "graph set window fontface" 在批处理（-b do）下会报
* "not available in non-GUI version"，属正常，GUI 里才生效。
* ==============================================================

local cnfont "${CN_FONT}"

foreach tgt in ps eps svg window {
    foreach sub in fontface fontfacesans fontfaceserif fontfacemono fontfacesymbol {
        capture graph set \`tgt' \`sub' "\`cnfont'"
    }
}

display as text "[plot_stata] 中文字体 = \`cnfont'"
display as text "[plot_stata] 已设置 ps / eps / svg / window，每个目标 5 项全覆盖"
display as text "[plot_stata] 出图命令 gsp 见 profile_main.do"
EOF

  w "$ST_MAIN" <<EOF
* ==============================================================
*  profile_main.do — Stata 性能 + 出图配置  ${SCRIPT_VERSION}
*  由 ${SCRIPT_VERSION} 生成，备份在 ~/Documents/plot-config/backup/
*  字体设置在 plot_stata.do（由 profile.do 在其后加载）
* ==============================================================

local stata_ver = c(stata_version)
capture local max_cores = c(max_processors)
if _rc != 0 local max_cores = c(processors)
display "[INFO] Stata \`stata_ver' | 可用核心 = \`max_cores'"

capture which gtools
local has_gtools = (_rc == 0)
capture which reghdfe
local has_reghdfe = (_rc == 0)

capture set processors \`max_cores'
if _rc != 0 capture set processors 2

if \`has_gtools' {
    capture gtools, set memory(lean)
    capture gtools, set maxthreads(\`max_cores')
    display "[OK] gtools 加速已启用"
}
else display "[WARN] 未装 gtools（ssc install gtools, replace）"

if \`has_reghdfe' display "[OK] 回归加速：优先 reghdfe"
else display "[WARN] 未装 reghdfe（ssc install reghdfe, replace）"

capture set maxvar 32767
if _rc != 0 capture set maxvar 10000
capture set matsize 11000
capture set linesize 255
capture set scrollbufsize 2000000
capture set more off
capture set niceness -5
capture set output proc

* ---- 出图命令已移到 ado 文件（clear all 不会清除） ----
* 原因：Stata 的 clear all 会连同所有 program 一起清掉，
* 而 do-file 开头写 clear all 又是最常见的习惯，导致 gsp 莫名消失。
* 解决：把 gsp / set_plot_dir / freemem 装成 ado 文件（编译加载，clear all 不生效）。

capture confirm global PLOT_OUTDIR
if _rc {
    global PLOT_OUTDIR "\`c(pwd)'/figures"
    capture mkdir "\$PLOT_OUTDIR"
}

display "[OK] profile_main.do 加载完成（${SCRIPT_VERSION}）"
display "[INFO] PLOT_OUTDIR = \$PLOT_OUTDIR"
EOF

  # ---- ado 文件：gsp / set_plot_dir / freemem ----
  # 为什么不写在 profile_main.do 里：Stata 的 `clear all` 会清掉所有 program，
  # 而 do-file 开头写 clear all 极常见 → gsp 会莫名消失（实测 r(199) command unrecognized）。
  # ado 文件由 Stata 编译缓存加载，不受 clear all 影响。
  local ado_dir
  ado_dir="${HOME}/Documents/Stata/ado/personal"
  if [[ "$MODE" == "dry-run" ]]; then
    info "[DRY] 写 ${ado_dir}/gsp.ado 等 3 个 ado"
  else
    mkdir -p "$ado_dir"

    w "${ado_dir}/freemem.ado" <<'ADO_FREEMEM'
*! freemem — 释放 Stata 内存（matrix / mata）
*! 由 plot-config 生成，装在 personal ado 目录，clear all 后依然可用。
program define freemem
    capture clear matrix
    capture clear mata
    display "[OK] 内存已释放（matrix / mata）"
end
ADO_FREEMEM

    w "${ado_dir}/set_plot_dir.ado" <<'ADO_SPD'
*! set_plot_dir — 设置当前会话的出图目录
*! 由 plot-config 生成。不传参数 = <当前目录>/figures
program define set_plot_dir
    syntax [anything(name=path)]
    if "`path'" == "" global PLOT_OUTDIR "`c(pwd)'/figures"
    else global PLOT_OUTDIR "`path'"
    capture mkdir "$PLOT_OUTDIR"
    display "[set_plot_dir] $PLOT_OUTDIR"
end
ADO_SPD

    w "${ado_dir}/gsp.ado" <<'ADO_GSP'
*! gsp — 快速导出当前图形（PNG + PDF）
*! 由 plot-config 生成，装在 personal ado 目录，clear all 后依然可用。
*!
*! 用法：
*!   gsp                        导出当前活动图 -> $PLOT_OUTDIR/fig_NNN
*!   gsp g1                     导出指定图形
*!   gsp g1, out(myfig)         指定文件名
*!   gsp g1, out(myfig) fmt("png")       只出 PNG
*!   gsp g1, dir("~/Desktop")   指定目录
*!
*! 注意：EPS 的中文在 PostScript 下必然变问号，TIF 本机无转换器，都不建议。
program define gsp
    syntax [anything(name=which)], [out(string) dir(string) width(integer 2400) fmt(string)]

    local which = trim(subinstr("`which'", char(34), "", .))

    if "`dir'" == "" local dir "$PLOT_OUTDIR"
    if "`dir'" == "" local dir "`c(pwd)'/figures"
    capture mkdir "`dir'"

    if "`out'" == "" {
        global GSP_N = cond("$GSP_N" == "", 1, $GSP_N + 1)
        local out "fig_`=string($GSP_N, "%03.0f")'"
    }
    if "`fmt'" == "" local fmt "png pdf"

    local namopt ""
    if "`which'" != "" local namopt "name(`which')"

    * 导出前先确认图形存在：否则 Stata 只打印 "rc=693" 到日志，
    * 命令本身返回 0，调用方会误以为成功（实测裸 gsp nosuchfig 的 rc=0）。
    if "`which'" != "" {
        capture graph describe `which'
        if _rc != 0 {
            display as error "[gsp] 图形 `which' 不存在，未导出任何文件"
            display as error "[gsp] 先画图并命名：twoway ... , name(`which')"
            exit 111
        }
    }

    local fail_cnt = 0
    foreach f of local fmt {
        local low = lower("`f'")
        if "`low'" == "eps" {
            display as error "[gsp] 警告：EPS 的中文在 PostScript 下必然变 ??（无解），建议改用 pdf"
        }
        if "`low'" == "tif" | "`low'" == "tiff" {
            display as error "[gsp] 本机不支持 tif 导出，请用 png"
            local fail_cnt = `fail_cnt' + 1
            continue
        }
        if "`low'" == "png" {
            capture graph export "`dir'/`out'.png", `namopt' replace width(`width')
        }
        else {
            capture graph export "`dir'/`out'.`low'", `namopt' replace
        }
        if _rc == 0 display "[gsp] saved: `dir'/`out'.`low'"
        else {
            display as error "[gsp] `low' 导出失败 rc=" _rc
            local fail_cnt = `fail_cnt' + 1
        }
    }

    if `fail_cnt' > 0 {
        display as error "[gsp] 有 `fail_cnt' 个格式导出失败"
        exit 111
    }
end
ADO_GSP

    ok "已写 3 个 ado：$(basename "$ado_dir")/{gsp,set_plot_dir,freemem}.ado"
  fi

  # 这里必须让 shell 展开路径：Stata 的 do 不认 "~"，必须是绝对路径
  w "$ST_BRIDGE" <<EOF
* Stata 启动桥接文件（${SCRIPT_VERSION} 生成）
do "${ST_MAIN}"
do "${ST_PLOT}"
EOF
}

# --------------------------------------------------------------
# 5. shell rc / .Renviron / 符号链接 / .pth
# --------------------------------------------------------------
DEV_S="# >>> 开发环境配置 v2.0 >>>"
DEV_E="# <<< 开发环境配置 v2.0 <<<"
MARK_S="# >>> 中文绘图配置 >>>"
MARK_E="# <<< 中文绘图配置 <<<"
PY_S="# >>> Python 性能配置 >>>"
PY_E="# <<< Python 性能配置 <<<"
RE_S="# >>> R 环境变量 >>>"
RE_E="# <<< R 环境变量 <<<"

strip_block() { # strip_block <file> <start> <end>
  #
  # 【安全约束】只删除「成对」的标记块。
  # 早期实现是 skip=1 一直保持到遇见结束标记，若结束标记缺失
  # （写到一半被打断、用户手误删掉），会把标记之后的所有内容全删光，
  # 而脚本仍然显示成功 —— 属于静默数据丢失。
  # 现在：先数开始/结束标记个数，
  #   · 成对  → 正常剥离
  #   · 不成对 → 不动这个文件，报警并让用户手动处理
  #   · 多余结束标记 → 也不动（无法确定边界）
  local f="$1" s="$2" e="$3"
  [[ -f "$f" ]] || return 0

  local ns ne
  ns="$(grep -cxF -- "$s" "$f" 2>/dev/null || true)"
  ne="$(grep -cxF -- "$e" "$f" 2>/dev/null || true)"
  ns="${ns:-0}"; ne="${ne:-0}"

  if [[ "$ns" != "$ne" ]]; then
    warn "${f} 的标记块不成对（开始 ${ns} 个 / 结束 ${ne} 个），为免误删已跳过。请手动修正该文件。"
    return 1
  fi
  (( ns == 0 )) && return 0

  local tmp; tmp="$(mktemp)"
  awk -v s="$s" -v e="$e" '
    $0 == s {skip=1; next}
    $0 == e {skip=0; next}
    !skip
  ' "$f" > "$tmp"
  cat "$tmp" > "$f"
  rm -f "$tmp"
}

# 旧版手写配置没有标记块，strip_block 删不掉 → 会和新配置叠加成两份。
# 这里的策略：检测到旧版特征且无新版标记时，备份后整份重写（保留 Docker 段）。
LEGACY_SIGS=(
  "# ~/.zshrc — macOS 通用开发环境配置（优化版）"
  "# 1. Homebrew（清华镜像 + 自动 shellenv）"
  "# 12. 中文绘图配置（由 setup_plot.sh 写入，勿手动编辑）"
)

rc_is_legacy() {
  local f="$1" sig
  [[ -f "$f" ]] || return 1
  grep -qF "$DEV_S" "$f" && return 1        # 已是新版，交给 strip_block 走增量
  for sig in "${LEGACY_SIGS[@]}"; do
    grep -qF "$sig" "$f" && return 0
  done
  return 1
}

# 提取第三方代管内容（Docker Desktop 等），重写时原样保留
rc_extract_foreign() {
  local f="$1" tmp="$2"
  awk '
    /^# The following lines have been added by Docker Desktop/ {keep=1}
    /^# End of Docker CLI completions/ {print; keep=0; next}
    keep {print}
  ' "$f" > "$tmp"
}

write_shell_rc() {
  [[ "$MODE" == dry-run ]] && { info "[DRY] 更新 ${RC}"; return; }
  touch "$RC"

  # 旧版整份重写（保留 Docker 段），避免新旧配置叠加
  if rc_is_legacy "$RC"; then
    local foreign; foreign="$(mktemp)"
    rc_extract_foreign "$RC" "$foreign"
    cp "$RC" "${RC}.legacy.$(date '+%Y%m%d_%H%M%S')"
    if [[ -s "$foreign" ]]; then
      printf '%s\n' "# ~/.zshrc — 由 setup_plot.sh ${SCRIPT_VERSION} 重建" > "$RC"
      printf '\n' >> "$RC"
      cat "$foreign" >> "$RC"
    else
      printf '%s\n' "# ~/.zshrc — 由 setup_plot.sh ${SCRIPT_VERSION} 重建" > "$RC"
    fi
    rm -f "$foreign"
    info "检测到旧版手写配置，已备份为 ${RC}.legacy.*，将整份重写"
  fi

  # 三组标记块都必须先干净剥掉，否则新块会追加在老块后面变成两份配置。
  # strip_block 在标记不成对时返回 1（宁可不动文件也不误删），
  # 这里必须显式检查：有任何一组剥不掉就放弃写 rc，不再往下追加。
  local _bad=0
  strip_block "$RC" "$DEV_S"  "$DEV_E"  || _bad=1
  strip_block "$RC" "$MARK_S" "$MARK_E" || _bad=1
  strip_block "$RC" "$PY_S"   "$PY_E"   || _bad=1
  if (( _bad )); then
    err "${RC} 存在不成对的标记块，已停止写入（避免配置重复叠加）。"
    err "请手动修正：把 # >>> ... >>> 与 # <<< ... <<< 配成对，或整段删掉后重跑。"
    return 1
  fi
  {
    echo ""
    echo "$DEV_S"
    cat <<'DEV_BODY'
# ------------------------------------------------------------
# 通用选项与历史
# ------------------------------------------------------------
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS HIST_VERIFY
setopt SHARE_HISTORY AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS
setopt INTERACTIVE_COMMENTS NO_BEEP EXTENDED_GLOB

for _e in code cursor subl nano vim; do
  if (( $+commands[$_e] )); then export EDITOR="$commands[$_e]"; break; fi
done
: ${EDITOR:=/usr/bin/vim}
export VISUAL="$EDITOR"
unset _e

# ------------------------------------------------------------
# 镜像可用性探测（结果缓存 24h，避免每次启动卡网络）
# ------------------------------------------------------------
_MIRROR_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/zsh-mirror.state"
_MIRROR_TTL=86400

_mirror_probe() {
  emulate -L zsh
  (( $+commands[curl] )) || return 0
  curl -s -o /dev/null -m 2 -I https://mirrors.tuna.tsinghua.edu.cn/ 2>/dev/null
}

_mirror_ok() {
  emulate -L zsh
  local now mtime age
  now=$(date +%s)
  if [[ -f "$_MIRROR_CACHE" ]]; then
    mtime=$(stat -f %m "$_MIRROR_CACHE" 2>/dev/null || echo 0)
    age=$(( now - mtime ))
    if (( age >= 0 && age < _MIRROR_TTL )); then
      [[ "$(<"$_MIRROR_CACHE")" == ok ]]
      return
    fi
  fi
  mkdir -p "${_MIRROR_CACHE:h}" 2>/dev/null
  if _mirror_probe; then
    print -r -- ok  >| "$_MIRROR_CACHE" 2>/dev/null
    return 0
  else
    print -r -- bad >| "$_MIRROR_CACHE" 2>/dev/null
    return 1
  fi
}

_mirror_apply() {
  emulate -L zsh
  export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
  export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"
  export HOMEBREW_API_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api"
  export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
  export NVM_NODEJS_ORG_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/nodejs-release/"
  export CARGO_REGISTRIES_CRATES_IO_INDEX="https://mirrors.tuna.tsinghua.edu.cn/git/crates.io-index.git"
  export GOPROXY="https://mirrors.tuna.tsinghua.edu.cn/goproxy/,direct"
  export GOSUMDB="sum.golang.google.cn"
  export PUB_HOSTED_URL="https://mirrors.tuna.tsinghua.edu.cn/dart-pub"
  export FLUTTER_STORAGE_BASE_URL="https://mirrors.tuna.tsinghua.edu.cn/flutter"
  export JULIA_PKG_SERVER="https://mirrors.tuna.tsinghua.edu.cn/julia"
  export PIP_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"
  export npm_config_registry="https://registry.npmmirror.com"
  export ZSH_MIRROR="tuna"
}

_mirror_clear() {
  emulate -L zsh
  unset HOMEBREW_BREW_GIT_REMOTE HOMEBREW_CORE_GIT_REMOTE \
        HOMEBREW_API_DOMAIN HOMEBREW_BOTTLE_DOMAIN \
        NVM_NODEJS_ORG_MIRROR CARGO_REGISTRIES_CRATES_IO_INDEX \
        GOPROXY GOSUMDB PUB_HOSTED_URL FLUTTER_STORAGE_BASE_URL \
        JULIA_PKG_SERVER PIP_INDEX_URL npm_config_registry 2>/dev/null
  export ZSH_MIRROR="official"
}

if _mirror_ok; then _mirror_apply; else _mirror_clear; fi

mirror() {
  emulate -L zsh
  case "${1:-status}" in
    status)
      if [[ "${ZSH_MIRROR:-}" == tuna ]]; then
        print -r -- "当前：清华镜像（缓存 ${_MIRROR_CACHE}）"
      else
        print -r -- "当前：官方源"
      fi ;;
    test)
      rm -f "$_MIRROR_CACHE"
      if _mirror_ok; then print -r -- "清华镜像可达"; else print -r -- "清华镜像不可达，保持官方源"; fi ;;
    on)  _mirror_apply; print -r -- "本次会话：已切清华镜像" ;;
    off) _mirror_clear; print -r -- "本次会话：已切官方源" ;;
    *)   print -r -- "用法: mirror [status|test|on|off]" ;;
  esac
}

# ------------------------------------------------------------
# Homebrew（只执行一次，重复 source 不膨胀 PATH）
# ------------------------------------------------------------
if [[ -z "${_BREW_ENV_LOADED:-}" ]]; then
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"; _BREW_ENV_LOADED=1
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"; _BREW_ENV_LOADED=1
  fi
fi
export HOMEBREW_NO_ANALYTICS=1

# ------------------------------------------------------------
# PATH 工具函数（幂等：重复 source 不会膨胀）
# ------------------------------------------------------------
path_prepend() {
  emulate -L zsh
  local d="${1:A}"
  [[ -d "$d" ]] || return 0
  path=("$d" ${path:#$d})
}
path_append() {
  emulate -L zsh
  local d="${1:A}"
  [[ -d "$d" ]] || return 0
  path=(${path:#$d} "$d")
}
pythonpath_prepend() {
  emulate -L zsh
  local d="${1:A}"
  [[ -d "$d" ]] || return 0
  local -a parts=(${(s.:.)PYTHONPATH})
  # 按解析后的真实路径去重：软链与其指向的目录算同一个
  local -a kept=()
  local p
  for p in $parts; do
    [[ -n "$p" ]] || continue
    [[ "${p:A}" == "$d" ]] && continue
    kept+=("$p")
  done
  export PYTHONPATH="${(j.:.)kept}$([[ ${#kept[@]} -gt 0 ]] && echo :)$d"
}

path_prepend "$HOME/.local/bin"
path_prepend "$HOME/bin"

# ------------------------------------------------------------
# pip / pip3 回退（镜像失败自动切官方源）
# 注意：用函数而非 alias，避免重复 source 时 "defining function based on alias"
# ------------------------------------------------------------
_pip_bin() {
  emulate -L zsh
  if (( $+commands[pip3] )); then print -r -- pip3
  elif (( $+commands[pip] )); then print -r -- pip
  else print -r -- ""
  fi
}

_pip_run() {
  emulate -L zsh
  local bin="$1"; shift
  [[ -z "$bin" ]] && { print -u2 "pip: 未找到 pip/pip3，请先安装 Python"; return 127; }
  command "$bin" "$@"
}

pip() {
  emulate -L zsh
  local bin; bin="$(_pip_bin)"
  _pip_run "$bin" "$@"
  local rc=$?
  if (( rc != 0 )) && [[ "$1" == install* ]] && [[ "${ZSH_MIRROR:-}" == tuna ]]; then
    print -u2 "⚠️  pip 失败（rc=${rc}），切官方 PyPI 重试…"
    PIP_INDEX_URL="https://pypi.org/simple" PIP_TRUSTED_HOST="" _pip_run "$bin" "$@"
  else
    return $rc
  fi
}
pip3() { pip "$@" }

# ------------------------------------------------------------
# npm 回退
# ------------------------------------------------------------
npm() {
  emulate -L zsh
  (( $+commands[npm] )) || { print -u2 "npm: 未安装（brew install node 或装 nvm）"; return 127; }
  command npm "$@"
  local rc=$?
  if (( rc != 0 )) && [[ "$1" == (install|i|ci|add) ]] && [[ "${ZSH_MIRROR:-}" == tuna ]]; then
    print -u2 "⚠️  npm 镜像失败（rc=${rc}），切官方 registry 重试…"
    npm_config_registry="https://registry.npmjs.org/" command npm "$@"
  else
    return $rc
  fi
}

# ------------------------------------------------------------
# 补全（缓存 24h 内跳过安全扫描，秒开）
# ------------------------------------------------------------
autoload -Uz compinit
ZCOMPDUMP="${ZDOTDIR:-$HOME}/.zcompdump"
if [[ -s "$ZCOMPDUMP" ]] && [[ -z "$(find "$ZCOMPDUMP" -mmin +1440 2>/dev/null)" ]]; then
  compinit -C -d "$ZCOMPDUMP"
else
  compinit -d "$ZCOMPDUMP"
fi
zmodload -i zsh/complist 2>/dev/null
setopt COMPLETE_IN_WORD ALWAYS_TO_END
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*:descriptions' format '%F{yellow}%d%f'

# ------------------------------------------------------------
# 按键绑定（macOS 默认 Ctrl+方向 不可用）
# ------------------------------------------------------------
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word
bindkey '^[[1;3C' forward-word
bindkey '^[[1;3D' backward-word
bindkey '^[[H'   beginning-of-line
bindkey '^[[F'   end-of-line
bindkey '^[[3~'  delete-char
bindkey '^R'     history-incremental-search-backward

# ------------------------------------------------------------
# 别名
# ------------------------------------------------------------
alias ll='ls -alh'
alias la='ls -A'
alias l='ls -lh'
alias lt='ls -lhtr | head -20'
alias cls='clear'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias brewup='brew update && brew upgrade && brew cleanup'
alias pipup='pip install --upgrade pip'
alias gs='git status -sb'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias gco='git checkout'
alias gbr='git branch -vv'
alias glog='git log --oneline --graph --decorate -20'
alias df='df -h'
alias du='du -sh'
alias ports='lsof -nP -iTCP -sTCP:LISTEN'
alias flushdns='sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder'
alias ip='curl -s --max-time 3 https://myip.ipip.net || echo "查询失败"'

# ------------------------------------------------------------
# 函数
# ------------------------------------------------------------
mkcd() { mkdir -p "$1" && cd "$1"; }

extract() {
  emulate -L zsh
  [[ -f "$1" ]] || { print -u2 "extract: 文件不存在 $1"; return 1; }
  case "$1" in
    *.tar.gz|*.tgz)  tar -xzf "$1" ;;
    *.tar.bz2|*.tbz) tar -xjf "$1" ;;
    *.tar.xz)        tar -xJf "$1" ;;
    *.tar)           tar -xf  "$1" ;;
    *.zip)           unzip   "$1" ;;
    *.gz)            gunzip  "$1" ;;
    *.7z)            7z x    "$1" ;;
    *.rar)           unrar x "$1" ;;
    *) print -u2 "extract: 不认识的格式 $1"; return 1 ;;
  esac
}

proxy() {
  emulate -L zsh
  local host="${PROXY_HOST:-127.0.0.1}"
  local port="${PROXY_PORT:-7890}"
  case "${1:-status}" in
    on)
      export http_proxy="http://$host:$port"  https_proxy="http://$host:$port"
      export HTTP_PROXY="$http_proxy"         HTTPS_PROXY="$https_proxy"
      export ALL_PROXY="socks5://$host:$port"
      print -r -- "代理已开启 → $host:$port"
      if (( $+commands[curl] )) && ! curl -s -o /dev/null -m 3 -x "$http_proxy" https://www.google.com; then
        print -r -- "⚠️  连不通，检查端口或客户端是否已启动"
      fi ;;
    off)
      unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY 2>/dev/null
      print -r -- "代理已关闭" ;;
    status)
      [[ -n "${http_proxy:-}" ]] && print -r -- "当前：${http_proxy}" || print -r -- "当前：未开代理" ;;
    *) print -r -- "用法: proxy [on|off|status]（端口用 PROXY_PORT=7890 覆盖）" ;;
  esac
}

# conda 惰性加载（首次调用 conda 才初始化，不拖慢开终端）
# 背景：conda 未初始化时，交互 shell 里 python3 会落到 Homebrew 版（没装 matplotlib）
if [[ -f /opt/homebrew/anaconda3/etc/profile.d/conda.sh ]]; then
  conda() {
    unset -f conda
    source /opt/homebrew/anaconda3/etc/profile.d/conda.sh
    conda "$@"
  }
fi

export MANPAGER="less -R --use-color -Dd+r -Du+b"
export LESS="-R -F -X"
DEV_BODY
    echo "$DEV_E"
    echo ""
    echo "$MARK_S"
    echo "export MATPLOTLIBRC=\"${MPL_RC}\""
    echo "export R_PROFILE_USER=\"${R_PROF}\""
    echo "export PLOT_OUTDIR_MODE=\"\${PLOT_OUTDIR_MODE:-project}\""
    echo "export PLOT_DPI=\"\${PLOT_DPI:-${PLOT_DPI}}\""
    echo "export PLOT_THREADS=\"\${PLOT_THREADS:-${PLOT_THREADS}}\""
    echo "pythonpath_prepend \"${PY_DIR}\""
    # 把装了 matplotlib 的解释器钉进 PATH。
    # 实测不钉的话：裸敲 python3 会落到没装 matplotlib 的解释器上
    # （本机 conda envs/it 和 Homebrew 3.15 都缺 matplotlib），
    # import mpl_setup 直接失败，用户看到的是莫名 ModuleNotFoundError。
    if [[ -n "${PLOT_PY:-}" ]]; then
      echo "export PLOT_PYTHON=\"\${PLOT_PYTHON:-${PLOT_PY}}\""
      echo "if [[ -x \"\${PLOT_PYTHON}\" ]]; then"
      echo "  export PATH=\"\$(dirname \"\${PLOT_PYTHON}\"):\${PATH}\""
      echo "fi"
    fi
    echo "$MARK_E"
    echo ""
    echo "$PY_S"
    echo "export OMP_NUM_THREADS=\"\${OMP_NUM_THREADS:-${PLOT_THREADS}}\""
    echo "export MKL_NUM_THREADS=\"\${MKL_NUM_THREADS:-${PLOT_THREADS}}\""
    echo "export OPENBLAS_NUM_THREADS=\"\${OPENBLAS_NUM_THREADS:-${PLOT_THREADS}}\""
    echo "export VECLIB_MAXIMUM_THREADS=\"\${VECLIB_MAXIMUM_THREADS:-${PLOT_THREADS}}\""
    echo "export NUMEXPR_NUM_THREADS=\"\${NUMEXPR_NUM_THREADS:-${PLOT_THREADS}}\""
    echo "export PYTORCH_ENABLE_MPS_FALLBACK=1"
    echo "$PY_E"
  } >> "$RC"

  # 压缩连续空行（strip_block 只删标记行，块前 echo "" 的空行会累积）
  local tmp; tmp="$(mktemp)"
  awk 'BEGIN{blank=0}
       /^[[:space:]]*$/ {blank++; if(blank<=1) print; next}
       {blank=0; print}' "$RC" > "$tmp"
  cat "$tmp" > "$RC"; rm -f "$tmp"

  ok "已更新 ${RC}"
}

write_renviron() {
  [[ "$MODE" == dry-run ]] && { info "[DRY] 更新 ${RENV}"; return; }
  touch "$RENV"

  # 剥标记块失败就停手，免得新块和老块叠成两份
  strip_block "$RENV" "$RE_S" "$RE_E" || {
    err "${RENV} 标记块不成对，已停止写入（避免重复叠加）"
    return 1
  }

  # 顺手去掉历史遗留的裸行，避免和上面的块重复。
  # 【安全】grep 的退出码 1 表示"没有匹配行"（正常），>1 才是真错误（读不了文件）。
  # 早期写死 `|| true` 会连读失败一起吞掉，此时 tmp 是空的，
  # 紧接着的 cat 会把整个 .Renviron 清空 —— 属静默数据丢失。
  local tmp; tmp="$(mktemp)"
  local rc_grep=0
  grep -vE '^(R_PROFILE_USER|OMP_NUM_THREADS|MKL_NUM_THREADS|R_DATATABLE_NUM_PROCS_PERCENT)=' \
    "$RENV" > "$tmp" 2>/dev/null || rc_grep=$?
  if (( rc_grep > 1 )); then
    rm -f "$tmp"
    err "读取 ${RENV} 失败（grep 退出码 ${rc_grep}），已放弃写入，原文件未改动"
    return 1
  fi
  cat "$tmp" > "$RENV"; rm -f "$tmp"
  {
    echo "$RE_S"
    echo "R_PROFILE_USER=${R_PROF}"
    echo "OMP_NUM_THREADS=${PLOT_THREADS}"
    echo "MKL_NUM_THREADS=${PLOT_THREADS}"
    echo "R_DATATABLE_NUM_PROCS_PERCENT=100"
    echo "THEME_MODE=auto"
    echo "PLOT_OUTDIR_MODE=project"
    echo "PLOT_DPI=${PLOT_DPI}"
    echo "$RE_E"
  } >> "$RENV"
  ok "已更新 ${RENV}（已去重）"
}

link_file() { # link_file <目标> <链接>
  local tgt="$1" lnk="$2"
  [[ "$MODE" == dry-run ]] && { info "[DRY] 链接 ${lnk} -> ${tgt}"; return; }
  mkdir -p "$(dirname "$lnk")"
  # 若已是正确软链就跳过；若是实体文件先移走（snapshot 里已备份）
  if [[ -L "$lnk" ]]; then
    [[ "$(readlink "$lnk")" == "$tgt" ]] && return 0
    rm -f "$lnk"
  elif [[ -e "$lnk" ]]; then
    # 目标位置是用户自己的实体文件（不是我们建的软链）。
    # 不能删、不能覆盖 → 改名保留，并在输出里点名，否则用户永远找不到备份在哪。
    local keep="${lnk}.pre-${SCRIPT_VERSION}.${TS}"
    mv "$lnk" "$keep"
    warn "原文件已改名保留：${keep}"
    info "确认新配置没问题后，可自行删除该备份"
  fi
  ln -s "$tgt" "$lnk"
  ok "链接 ${lnk} -> ${tgt}"
}

write_pth() { # 把 python 目录注册进当前解释器的 site-packages
  local py="$1"
  [[ -z "$py" ]] && { warn "未找到带 matplotlib 的 python，跳过 .pth"; return; }
  [[ "$MODE" == dry-run ]] && { info "[DRY] 写 ${py} 的 site-packages/plot_config.pth"; return; }

  # 隔离保护：测试时若把 HOME 指向临时目录，绝不能往真实 conda 环境写 .pth，
  # 否则会留下指向临时路径的永久污染（历史上踩过：/tmp/fin/... 被写进真实 site-packages）。
  if [[ "${SKIP_PTH:-0}" == "1" ]]; then
    info "SKIP_PTH=1，跳过 .pth 注册"
    return 0
  fi

  local sp
  sp="$("$py" -c 'import sysconfig;print(sysconfig.get_paths()["purelib"])' 2>/dev/null || true)"
  [[ -z "$sp" || ! -d "$sp" ]] && { warn "定位 site-packages 失败，跳过 .pth"; return; }

  # 测试隔离判定：HOME 指向临时目录说明是模拟测试，禁止污染真实 conda 环境。
  # 注意不能用「site-packages 是否在 HOME 下」判断——真实 conda 常在 /opt/homebrew，
  # 那样会把正常部署也拦掉。
  case "${HOME%/}" in
    /tmp/*|/var/folders/*|/private/tmp/*|/private/var/folders/*)
      warn "HOME 指向临时目录（${HOME}），判定为测试隔离环境，跳过 .pth 注册"
      warn "避免往真实 site-packages（${sp}）写入临时路径；正式部署请用真实 HOME"
      return 0 ;;
  esac

  printf '%s\n' "$PY_DIR" > "${sp}/plot_config.pth"
  ok "已注册 ${sp}/plot_config.pth"
}

# --------------------------------------------------------------
# 部署主流程
# --------------------------------------------------------------
do_install() {
  MODE="${1:-install}"
  info "中文字体: ${CN_FONT} | DPI: ${PLOT_DPI} | 线程: ${PLOT_THREADS}"
  ensure_dirs
  snapshot

  write_matplotlibrc
  write_rprofile
  write_pymod
  write_stata

  link_file "$MPL_RC"   "${HOME}/.matplotlib/matplotlibrc"
  link_file "$R_PROF"   "${HOME}/.Rprofile"

  write_shell_rc
  write_renviron
  write_pth "$PYTHON"

  [[ "$MODE" == dry-run ]] && { info "DRY-RUN 结束，未做任何改动"; return; }

  cat <<SUMMARY

════════════════════════════════════════════════════════════
  部署完成  ${SCRIPT_VERSION}
════════════════════════════════════════════════════════════
  字体 ${CN_FONT}    DPI ${PLOT_DPI}    线程 ${PLOT_THREADS}
  备份 ${SNAP}

  matplotlib : ${MPL_RC}
  R          : ${R_PROF}
  Python     : ${PY_MOD}
  Stata      : ${ST_MAIN}
               ${ST_PLOT}
  Stata 桥接 : ${ST_BRIDGE}

════════════════════════════════════════════════════════════
  下一步
════════════════════════════════════════════════════════════
  1. source ${RC}
  2. 重启 RStudio / VS Code / Stata
  3. bash $0 check      # 验证是否还会出豆腐块

SUMMARY
}

# --------------------------------------------------------------
# 体检 + 出图自检
# --------------------------------------------------------------
do_check() {
  MODE="check"
  local fail=0
  echo ""
  echo "══════════ 环境 ══════════"
  echo "  macOS ${OSTYPE}  |  Shell ${SHELL##*/}  |  rc ${RC}"
  echo "  字体 ${CN_FONT}  |  DPI ${PLOT_DPI}  |  线程 ${PLOT_THREADS}"

  echo ""
  echo "══════════ R ══════════"
  if [[ -z "$RSCRIPT" ]]; then
    warn "  未找到 Rscript（跳过）"
  else
    echo "  ${RSCRIPT}"
    "$RSCRIPT" -e 'r<-check_cn_plot();cat(sprintf("R 自检: %s\n",if(all(unlist(r)=="OK"))"PASS"else"FAIL"))' 2>&1 \
      | grep -vE "Fontconfig|writable|cache" || true
    "$RSCRIPT" -e 'r<-check_cn_plot();if(!all(unlist(r)=="OK"))quit(status=1)' &>/dev/null || fail=1
  fi

  echo ""
  echo "══════════ Python ══════════"
  if [[ -z "$PYTHON" ]]; then
    warn "  未找到带 matplotlib 的 python（跳过）"
  else
    echo "  ${PYTHON}"
    "$PYTHON" -c 'import mpl_setup as mp
print("Python 自检:", "PASS" if mp.check_cn() else "FAIL")' 2>&1 \
      | grep -vE "Fontconfig|building|writable|^\[mpl_setup\] font" || true
    "$PYTHON" -c 'import mpl_setup as mp;raise SystemExit(0 if mp.check_cn() else 1)' &>/dev/null || fail=1
  fi

  echo ""
  echo "══════════ Stata ══════════"
  if [[ -z "$STATA" ]]; then
    warn "  未找到 Stata（跳过）"
  else
    echo "  ${STATA}"
    local td; td="$(mktemp -d)"; _TMP_DIRS+=("$td")
    # 注意：Stata 不展开 "~"，必须给绝对路径；所以这里用非引用 heredoc
    # 让 shell 展开 ${ST_BRIDGE}。Stata 代码里没有 $ 宏，不会被误伤。
    # 体检同样要覆盖 clear all 场景：ado 命令若退化成 do-file 内 program define，
    # 用户 do 文件开头一句 clear all 就会让 gsp 消失，而旧版体检因为不写 clear all 查不出来。
    cat > "${td}/t.do" <<EOD
set more off
capture log close
quietly log using "t.log", replace text
clear all
sysuse auto, clear
scatter price mpg, title("中文：汽车价格") ytitle("价格（元）") name(g1, replace)
gsp g1, out(_chk)
log close
EOD
    ( cd "$td" && "$STATA" -b do t.do >/dev/null 2>&1 || true )
    if [[ -f "${td}/figures/_chk.png" && -f "${td}/figures/_chk.pdf" ]]; then
      ok "  中文出图 PASS（PNG + PDF 均已生成，含 clear all 场景）"
    else
      warn "  中文出图 FAIL（看 ${td}/t.log）"
      grep -iE "unrecognized|r\([0-9]+\)" "${td}/t.log" 2>/dev/null | head -3 | sed 's/^/        /'
      fail=1
    fi
    rm -rf "$td"
    _TMP_DIRS=("${_TMP_DIRS[@]/$td}")   # 已清，从登记表移除
  fi

  echo ""
  if [[ $fail -eq 0 ]]; then
    ok "全部通过：三套工具链中文均无豆腐块"
  else
    err "有项目未通过，见上面输出"
    return 1
  fi
}

# --------------------------------------------------------------
# 依赖指引
# --------------------------------------------------------------
do_deps() {
  MODE="deps"
  echo ""
  echo "══════════════ 依赖安装指引 ══════════════"

  echo ""
  echo "【R】"
  if [[ -z "$RSCRIPT" ]]; then
    echo "  未装 R：brew install --cask r"
  else
    echo "  ${RSCRIPT}"
    local miss=()
    local p
    for p in ggplot2 ragg systemfonts data.table; do
      "$RSCRIPT" -e "q(status=!requireNamespace('${p}',quietly=TRUE))" &>/dev/null || miss+=("$p")
    done
    if [[ ${#miss[@]} -eq 0 ]]; then
      echo "  包齐全 ✓"
    else
      echo "  缺：${miss[*]}"
      echo "  安装："
      printf '    %s -e \x27install.packages(c(%s), repos="https://mirrors.tuna.tsinghua.edu.cn/CRAN/")\x27\n' \
        "$RSCRIPT" "$(printf '"%s",' "${miss[@]}" | sed 's/,$//')"
    fi
  fi

  echo ""
  echo "【Python】"
  if [[ -z "$PYTHON" ]]; then
    warn "  未找到带 matplotlib 的 python3"
    echo "  建议：brew install python@3.12 && pip3 install matplotlib"
  else
    echo "  ${PYTHON}"
    "$PYTHON" -c "import matplotlib" &>/dev/null && echo "  matplotlib ✓" \
      || echo "  缺 matplotlib：$PYTHON -m pip install matplotlib"
    "$PYTHON" -c "import numpy" &>/dev/null && echo "  numpy ✓" \
      || echo "  缺 numpy：$PYTHON -m pip install numpy"
  fi

  echo ""
  echo "【Stata】"
  if [[ -z "$STATA" ]]; then
    echo "  未找到 Stata（可选）"
  else
    echo "  ${STATA}"
    echo "  在 Stata 内依次执行（顺序不可颠倒）："
    echo "    ssc install ftools, replace"
    echo "    ssc install gtools, replace"
    echo "    ssc install reghdfe, replace"
    echo "    gtools, upgrade"
  fi

  echo ""
  echo "【中文字体】"
  echo "  当前：${CN_FONT}"
  if [[ "$CN_FONT" == "Arial Unicode MS" ]]; then
    echo "  未检测到 PingFang / Heiti，建议装思源黑体："
    echo "    brew install --cask font-source-han-sans-vf"
  fi
  echo ""
}

# --------------------------------------------------------------
# 卸载
# --------------------------------------------------------------
do_uninstall_common() {
  [[ "$MODE" == dry-run ]] && { info "[DRY] 清理 shell rc / .Renviron / 软链"; return; }
  strip_block "$RC" "$DEV_S"  "$DEV_E"  || warn "${RC} 的通用开发环境块未清理"
  strip_block "$RC" "$MARK_S" "$MARK_E" || warn "${RC} 的绘图配置块未清理"
  strip_block "$RC" "$PY_S"   "$PY_E"   || warn "${RC} 的 Python 块未清理"
  ok "已清理 ${RC}"

  strip_block "$RENV" "$RE_S" "$RE_E" || warn "${RENV} 标记块未清理"
  # 同 write_renviron：grep 退出码 >1 才是真错误，绝不能当成空结果去覆盖原文件
  local tmp rc_grep=0
  tmp="$(mktemp)"
  grep -vE '^(R_PROFILE_USER|OMP_NUM_THREADS|MKL_NUM_THREADS|R_DATATABLE_NUM_PROCS_PERCENT|THEME_MODE|PLOT_OUTDIR_MODE|PLOT_DPI)=' \
    "$RENV" > "$tmp" 2>/dev/null || rc_grep=$?
  if (( rc_grep > 1 )); then
    rm -f "$tmp"
    err "读取 ${RENV} 失败（grep 退出码 ${rc_grep}），已跳过清理，原文件未改动"
  else
    cat "$tmp" > "$RENV"; rm -f "$tmp"
    ok "已清理 ${RENV}"
  fi

  local l
  for l in "${HOME}/.matplotlib/matplotlibrc" "${HOME}/.Rprofile"; do
    [[ -L "$l" ]] && { rm -f "$l"; ok "已移除软链 ${l}"; }
  done

  local py="$PYTHON" sp
  if [[ -n "$py" ]]; then
    sp="$("$py" -c 'import sysconfig;print(sysconfig.get_paths()["purelib"])' 2>/dev/null || true)"
    [[ -n "$sp" && -f "${sp}/plot_config.pth" ]] && { rm -f "${sp}/plot_config.pth"; ok "已移除 .pth"; }
  fi

  # ado 文件装在 Stata 的 personal 目录，不属于配置目录，必须单独清
  local ado_dir="${HOME}/Documents/Stata/ado/personal"
  local a
  for a in gsp set_plot_dir freemem; do
    [[ -f "${ado_dir}/${a}.ado" ]] && { rm -f "${ado_dir}/${a}.ado"; ok "已移除 ado ${a}.ado"; }
  done
}

do_uninstall() {
  MODE="uninstall"
  snapshot
  do_uninstall_common
  ok "卸载完成（配置保留在 ${CFG}，备份在 ${SNAP}）"
}

do_purge() {
  MODE="purge"
  # 【删除守卫】purge 会 rm -rf 掉整个配置目录，属于不可逆操作。
  # 按用户 AGENTS.md 的要求，执行前必须让用户明确确认具体路径。
  # dry-run 不需要确认（反正不落盘）。
  if [[ "$MODE" != dry-run ]]; then
    warn "即将删除的目录：${CFG}"
    warn "此操作不可逆（会先备份到 ~/Documents/plot-config-backup-${TS}）"
    local _ans=""
    if ! read -rp "  确认删除请输入 yes（其它任意键取消）: " _ans; then echo; return 1; fi
    if [[ "$_ans" != "yes" ]]; then
      info "已取消，未删除任何文件"
      return 0
    fi
  fi
  # 备份必须放在 CFG 外面，否则下一步 rm -rf 把它一起删了
  if [[ "$MODE" != dry-run ]]; then
    local out="${HOME}/Documents/plot-config-backup-${TS}"
    [[ -d "$CFG" ]] && { cp -Rp "$CFG" "$out"; ok "已备份到 ${out}"; }
  fi
  do_uninstall_common
  if [[ "$MODE" == dry-run ]]; then info "[DRY] rm -rf ${CFG}"
  else
    NO_FILELOG=1                 # 目录即将消失，别再往里写日志
    rm -rf "$CFG"
    ok "已删除 ${CFG}"
  fi
  # 原始文件的 .pre-* 备份一并提示。
  # 这里刻意保留 pre-v14 的 glob：那是历史版本留下的后缀，
  # 改用通配 pre-v* 才能同时匹配老的和新的（v14 / v15 / 以后的版本）。
  local f
  for f in "${HOME}/.Rprofile.pre-v"* "${HOME}/.matplotlib/matplotlibrc.pre-v"*; do
    [[ -e "$f" ]] && info "遗留：${f}"
  done
  return 0
}

print_help() {
  cat <<'H'
macOS 中文绘图 + 性能配置 · 一键部署

用法:
  bash setup_plot.sh            交互菜单
  bash setup_plot.sh install    直接部署
  bash setup_plot.sh check      环境体检 + 出图自检
  bash setup_plot.sh deps       依赖安装指引
  bash setup_plot.sh dry-run    只预览，不落盘
  bash setup_plot.sh uninstall  卸载（保留配置与备份）
  bash setup_plot.sh purge      彻底清理
  bash setup_plot.sh version    版本号
  bash setup_plot.sh help       本帮助

环境变量:
  PLOT_FONT     指定中文字体名（默认自动检测）
  PLOT_DPI      输出 DPI（默认 300）
  PLOT_THREADS  BLAS/OpenMP 线程（默认物理核数-1）
  PLOT_OUTDIR   输出目录（覆盖 PLOT_OUTDIR_MODE）
  PLOT_OUTDIR_MODE  project | cwd | fixed
  THEME_MODE    thesis | sci | auto
H
}

print_menu() {
  # 用 ANSI 转义清屏，不用 `clear` 命令：
  # 实测本机 `clear` 是 tcsh 的包装，非 TTY 下会打印 "Usage: clear [options]"
  # 到 stdout，污染 dry-run / 重定向输出，`2>/dev/null` 拦不住。
  [[ -t 1 ]] && printf '\033[H\033[2J\033[3J'
  echo "════════════════════════════════════════════════════════════"
  echo "  macOS 中文绘图 + 性能配置 · 一键部署  ${SCRIPT_VERSION}"
  echo "════════════════════════════════════════════════════════════"
  echo "  系统   macOS ${OSTYPE}"
  echo "  Shell  ${SHELL##*/} -> ${RC}"
  echo "  字体   ${CN_FONT}    DPI ${PLOT_DPI}    线程 ${PLOT_THREADS}"
  echo "  R      ${RSCRIPT:-未找到}"
  echo "  Python ${PYTHON:-未找到}"
  echo "  Stata  ${STATA:-未找到}"
  echo ""
  echo "────────────────────────────────────────────────────────────"
  echo "  1) 部署 / 更新配置"
  echo "  2) 环境体检 + 出图自检"
  echo "  3) 依赖安装指引"
  echo "  4) 预览（dry-run，不落盘）"
  echo "  5) 卸载（保留配置与备份）"
  echo "  6) 彻底清理（删除配置目录）"
  echo "  0) 退出"
  echo "────────────────────────────────────────────────────────────"
}

show_menu() {
  while true; do
    print_menu
    local c
    if ! read -rp "  请输入编号 [0-6]: " c; then echo; exit 0; fi
    echo ""
    case "$c" in
      1) do_install install ;;
      2) do_check || true ;;
      3) do_deps ;;
      4) do_install dry-run ;;
      5) do_uninstall ;;
      6) do_purge ;;
      0|q|Q) echo "已退出。"; exit 0 ;;
      *) warn "无效输入: ${c}" ;;
    esac
    echo ""
    read -rp "  按回车返回菜单..." _ || exit 0
  done
}

# --------------------------------------------------------------
# 入口
# --------------------------------------------------------------
if [[ "${OSTYPE}" != darwin* ]]; then
  err "本脚本仅支持 macOS"
  exit 1
fi

case "${1:-}" in
  install)   do_install install ;;
  check)     do_check ;;
  deps)      do_deps ;;
  dry-run|dryrun) do_install dry-run ;;
  uninstall) do_uninstall ;;
  purge)     do_purge ;;
  version)   echo "setup_plot.sh ${SCRIPT_VERSION}" ;;
  help|-h|--help) print_help ;;
  "")        show_menu ;;
  *)         err "未知参数: ${1}"; print_help; exit 1 ;;
esac
