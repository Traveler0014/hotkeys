; ============================================================================
;  Util.ahk  --  通用工具：日志、托盘提示、程序定位与启动、错误兜底
; ============================================================================

; 写一行日志到 logs\yyyyMMdd.log（LogEnabled 为 false 时静默）
Util_Log(text) {
    global CFG
    if !CFG.LogEnabled
        return
    dir := A_ScriptDir . '\logs'
    if !DirExist(dir)
        DirCreate(dir)
    line := FormatTime(A_Now, 'yyyy-MM-dd HH:mm:ss') . '  ' . text . "`n"
    try FileAppend(line, dir . '\' . FormatTime(A_Now, 'yyyyMMdd') . '.log', 'UTF-8')
}

; 气泡提示（不阻塞）
Util_Notify(title, text := '') {
    try TrayTip(text = '' ? title : text, title, 1)
}

; 托盘图标的悬浮说明
Util_SetTrayTip(text) {
    try A_IconTip := text
}

; 用记事本打开文本文件（在默认编辑器里编辑脚本/配置）
Util_EditFile(path) {
    if !FileExist(path) {
        Util_Notify('打开失败', '文件不存在: ' . path)
        return
    }
    try Run('notepad.exe "' . path . '"')
    catch as e
        Util_Notify('打开失败', e.Message)
}

Util_OpenLogDir() {
    dir := A_ScriptDir . '\logs'
    if !DirExist(dir)
        DirCreate(dir)
    try Run('"' . dir . '"')
}

; 校验程序路径：带路径分隔符的必须真实存在；裸文件名交给 PATH / 应用别名
Util_ResolveExe(path) {
    path := Trim(path . '')
    if (path = '')
        return ''
    if !RegExMatch(path, '[\\/]')
        return path
    return FileExist(path) ? path : ''
}

; 按 App 配置启动程序（缺失提示 / 单实例激活 / 失败提示）
Util_Launch(spec) {
    global CFG
    exe := Util_ResolveExe(spec.exe)
    if (exe = '') {
        Util_Log('未启动（程序不存在）: ' . spec.label . ' -> ' . spec.exe)
        Util_Notify('启动失败', '找不到 ' . spec.label . "`n请在托盘菜单「热键设置」里修正程序路径")
        return
    }

    if (spec.HasProp('activateIfRunning') && spec.activateIfRunning) {
        SplitPath(exe, &exeName)
        if (hwnd := WinExist('ahk_exe ' . exeName)) {
            try {
                if (WinGetMinMax('ahk_id ' . hwnd) = -1)
                    WinRestore('ahk_id ' . hwnd)
                WinActivate('ahk_id ' . hwnd)
                Util_Log('激活已运行的 ' . spec.label)
                return
            }
        }
    }

    workdir := (spec.HasProp('workdir') && spec.workdir != '') ? spec.workdir : CFG.Home
    cmd := '"' . exe . '"'
    if (spec.HasProp('args') && spec.args != '')
        cmd .= ' ' . spec.args

    try {
        Run(cmd, workdir)
        Util_Log('启动 ' . spec.label . ' -> ' . exe)
    } catch as e {
        Util_Log('启动失败 ' . spec.label . ': ' . e.Message)
        Util_Notify('启动失败', spec.label . "`n" . e.Message)
    }
}

; 全局错误兜底：写日志 + 托盘提示，抑制默认错误对话框
Util_OnError(err, mode) {
    try Util_Log('未捕获错误 [' . mode . '] ' . err.Message
        . ' @ ' . err.File . ':' . err.Line . "`n" . err.Stack)
    try Util_Notify('脚本出错', err.Message . "`n" . err.File . ':' . err.Line)
    return true
}
