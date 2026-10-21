* ==============================================================
*  profile_main.do — Stata 性能 + 出图配置  v15.0
*  由 v15.0 生成，备份在 ~/Documents/plot-config/backup/
*  字体设置在 plot_stata.do（由 profile.do 在其后加载）
* ==============================================================

local stata_ver = c(stata_version)
capture local max_cores = c(max_processors)
if _rc != 0 local max_cores = c(processors)
display "[INFO] Stata `stata_ver' | 可用核心 = `max_cores'"

capture which gtools
local has_gtools = (_rc == 0)
capture which reghdfe
local has_reghdfe = (_rc == 0)

capture set processors `max_cores'
if _rc != 0 capture set processors 2

if `has_gtools' {
    capture gtools, set memory(lean)
    capture gtools, set maxthreads(`max_cores')
    display "[OK] gtools 加速已启用"
}
else display "[WARN] 未装 gtools（ssc install gtools, replace）"

if `has_reghdfe' display "[OK] 回归加速：优先 reghdfe"
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
    global PLOT_OUTDIR "`c(pwd)'/figures"
    capture mkdir "$PLOT_OUTDIR"
}

display "[OK] profile_main.do 加载完成（v15.0）"
display "[INFO] PLOT_OUTDIR = $PLOT_OUTDIR"
