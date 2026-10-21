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
