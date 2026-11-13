; ============================================================================
;  hotkeys.ahk  --  入口脚本（AutoHotkey v2）
;
;  结构：
;    lib\Config.ahk       内置默认配置（Windows 10/11 通用工具）  <- 分享用
;    hotkeys.ini          本机覆盖配置（设置窗口生成，已 gitignore）
;    lib\Settings.ahk     配置读写 + 设置窗口
;    lib\Util.ahk         日志 / 托盘提示 / 启动进程 / 错误兜底
;    lib\Launcher.ahk     应用启动热键
;    lib\WindowTools.ahk  Alt+T 窗口置顶
;    lib\NetAlarm.ahk     Alt+N 服务器上线闹钟
;
;  热键全部通过 Hotkey() 在各模块的 *_Register() 中动态注册，
;  本文件不写 ^!t:: 这类热键块，因此自动执行段可以放在末尾。
; ============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

#Include lib\Config.ahk
#Include lib\Util.ahk
#Include lib\Settings.ahk
#Include lib\Launcher.ahk
#Include lib\WindowTools.ahk
#Include lib\NetAlarm.ahk

; ---------------------------------------------------------------------------
;  全局默认设置
; ---------------------------------------------------------------------------
SendMode('Input')
SetWorkingDir(A_ScriptDir)
CoordMode('Mouse', 'Screen')
CoordMode('Pixel', 'Screen')
CoordMode('ToolTip', 'Screen')
OnError(Util_OnError)

; ---------------------------------------------------------------------------
;  自动执行段
; ---------------------------------------------------------------------------
Hotkeys_Boot()

Hotkeys_Boot() {
    Util_Log('===== 启动 ' . A_ScriptName . ' (v' . A_AhkVersion . ') =====')

    Settings_Load()                        ; 默认配置 -> hotkeys.ini 覆盖
    Hotkeys_BuildTrayMenu()

    Launcher_Register()
    WindowTools_Register()
    NetAlarm_Register()

    NetAlarm_Refresh()                     ; 初始化托盘提示
    Util_Log('启动完成，热键已就绪')
    Util_Notify('热键脚本已加载', 'Alt+N 上线闹钟' . "`n" . '右键托盘图标：热键设置 / 暂停 / 停止监控')
}

; 托盘右键菜单
Hotkeys_BuildTrayMenu() {
    m := A_TrayMenu
    m.Delete()
    m.Add('热键设置…(&T)', (*) => Settings_ShowGui())
    m.Add('上线闹钟…(&N)', (*) => NetAlarm_ShowGui())
    m.Add('停止全部监控', (*) => NetAlarm_StopAll())
    m.Add()
    m.Add('暂停所有热键(&P)', Hotkeys_ToggleSuspend)
    m.Add('重新加载脚本(&R)', (*) => Reload())
    m.Add('编辑脚本(&E)', (*) => Util_EditFile(A_ScriptDir . '\hotkeys.ahk'))
    m.Add('编辑默认配置(&C)', (*) => Util_EditFile(A_ScriptDir . '\lib\Config.ahk'))
    m.Add('打开日志目录(&L)', (*) => Util_OpenLogDir())
    m.Add()
    m.Add('退出(&X)', (*) => ExitApp())
    m.Default := '上线闹钟…(&N)'
}

Hotkeys_ToggleSuspend(*) {
    if A_IsSuspended
        Suspend(false)
    else
        Suspend(true)
    try A_TrayMenu.ToggleCheck('暂停所有热键(&P)')
    Util_Log('热键挂起状态: ' . (A_IsSuspended ? '已暂停' : '已启用'))
    Util_SetTrayTip(A_IsSuspended ? '热键脚本 · 已暂停' : '热键脚本 · 已就绪')
    Util_Notify('热键脚本', A_IsSuspended ? '已暂停所有热键' : '已恢复所有热键')
}
