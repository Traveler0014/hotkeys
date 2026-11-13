; ============================================================================
;  Launcher.ahk  --  应用启动热键（热键与程序都来自 Config.ahk 的 APPS 表）
;
;  说明：这里用 Hotkey() 动态注册，而不是 ^!t:: 这种写法。
;  好处：可执行文件缺失的热键不会注册（并在日志里留痕），
;        热键表集中在 Config.ahk，加一个启动器只需加一条记录。
; ============================================================================

Launcher_Register() {
    for spec in APPS {
        if (Util_ResolveExe(spec.exe) = '') {
            Util_Log('跳过热键（程序不存在）: ' . spec.key . ' -> ' . spec.label)
            continue
        }
        try {
            Hotkey(spec.key, Launcher_OnHotkey.Bind(spec))
            Util_Log('注册热键 ' . spec.key . ' -> ' . spec.label)
        } catch as e {
            Util_Log('热键注册失败 ' . spec.key . ': ' . e.Message)
        }
    }
}

Launcher_OnHotkey(spec, *) {
    Util_Launch(spec)
}
