; ============================================================================
;  WindowTools.ahk  --  Alt+T：切换当前窗口「始终置顶」
;
;  与旧版的区别：
;    * 全部使用 v2 函数式写法（WinSetAlwaysOnTop / WinSetTitle）
;    * 置顶状态以窗口自身的 WS_EX_TOPMOST 样式为准，不靠标题猜测
;    * 标题前缀是可选功能：CFG.TopMostTitlePrefix 为空时完全不改标题；
;      非空时先记录原标题，取消置顶时精确还原，不会出现 "! ! 标题"
; ============================================================================

global TOPMOST_ORIG_TITLE := Map()   ; hwnd -> 加前缀之前的原标题

WindowTools_Register() {
    try {
        Hotkey('!t', WindowTools_ToggleTopMost)
        Util_Log('注册热键 !t -> 切换窗口置顶')
    } catch as e {
        Util_Log('热键注册失败 !t: ' . e.Message)
    }
}

WindowTools_ToggleTopMost(*) {
    global CFG, TOPMOST_ORIG_TITLE

    hwnd := WinExist('A')
    if !hwnd
        return
    win := 'ahk_id ' . hwnd

    if (WinGetExStyle(win) & 0x8) {                 ; 0x8 = WS_EX_TOPMOST
        WinSetAlwaysOnTop(false, win)
        if (CFG.TopMostTitlePrefix != '' && TOPMOST_ORIG_TITLE.Has(hwnd)) {
            try WinSetTitle(TOPMOST_ORIG_TITLE[hwnd], win)
            TOPMOST_ORIG_TITLE.Delete(hwnd)
        }
    } else {
        if (CFG.TopMostTitlePrefix != '') {
            title := WinGetTitle(win)
            if (title != '') {
                TOPMOST_ORIG_TITLE[hwnd] := title
                try WinSetTitle(CFG.TopMostTitlePrefix . title, win)
            }
        }
        WinSetAlwaysOnTop(true, win)
    }
}
