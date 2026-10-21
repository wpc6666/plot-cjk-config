* ==============================================================
*  plot_stata.do — Stata 中文字体配置  v15.0
*  由 v15.0 生成，备份在 ~/Documents/plot-config/backup/
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

local cnfont "Arial Unicode MS"

foreach tgt in ps eps svg window {
    foreach sub in fontface fontfacesans fontfaceserif fontfacemono fontfacesymbol {
        capture graph set `tgt' `sub' "`cnfont'"
    }
}

display as text "[plot_stata] 中文字体 = `cnfont'"
display as text "[plot_stata] 已设置 ps / eps / svg / window，每个目标 5 项全覆盖"
display as text "[plot_stata] 出图命令 gsp 见 profile_main.do"
