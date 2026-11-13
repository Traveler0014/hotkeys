; ============================================================================
;  Config.ahk  --  内置默认配置（面向 Windows 10 / 11 通用工具，可直接分享）
;
;  本机个性化配置请写 hotkeys.ini（由「热键设置」窗口自动生成，无需手写）：
;    优先级：hotkeys.ini  >  本文件的默认值
;    删掉 hotkeys.ini 就回到这里定义的默认配置。
; ============================================================================

global CFG := {
    ; --- 通用 ---
    Home:              A_MyDocuments,  ; 启动器的默认工作目录
    TopMostTitlePrefix: '',            ; 置顶时给窗口标题加的前缀，'' = 不改标题

    ; --- 上线闹钟 ---
    AlarmInterval:     5000,           ; 每个目标的探测间隔（毫秒）
    AlarmPingTimeout:  800,            ; 单次 ping 超时（毫秒）
    AlarmBeeps:        3,              ; 命中后蜂鸣次数（0 = 静音，只弹托盘提示）
    AlarmPopup:        false,          ; 命中后是否额外弹窗（弹窗会阻塞脚本，慎开）

    ; --- 日志 ---
    LogEnabled:        true,           ; 是否写 logs\ 下的运行日志
}

; ----------------------------------------------------------------------------
;  默认启动器表（Windows 10/11 自带工具，任何机器都能用）
;
;    key               热键：^=Ctrl  !=Alt  +=Shift  #=Win
;    label             说明文字，出现在日志和提示里
;    exe               程序路径；带路径分隔符时会检查是否存在，
;                      裸文件名（如 wt.exe）交给系统 PATH / 应用别名解析
;    args              启动参数，'' = 无
;    workdir           工作目录，'' = 用 CFG.Home
;    activateIfRunning 已在运行时改为激活窗口（单实例程序建议 true）
; ----------------------------------------------------------------------------
global APPS_DEFAULT := [
    {
        key: '^!t', label: '终端 (Windows Terminal)',
        exe: 'wt.exe', args: '', workdir: '', activateIfRunning: false,
    },
    {
        key: '#e', label: '资源管理器',
        exe: A_WinDir . '\explorer.exe',
        args: '', workdir: '', activateIfRunning: false,
    },
    {
        key: '^!p', label: '任务管理器',
        exe: A_WinDir . '\System32\taskmgr.exe',
        args: '', workdir: '', activateIfRunning: true,
    },
    {
        key: '^!e', label: '记事本',
        exe: A_WinDir . '\System32\notepad.exe',
        args: '', workdir: '', activateIfRunning: false,
    },
]

; 运行期实际使用的启动器表（由 Settings_Load() 依据 hotkeys.ini 填充/覆盖）
global APPS := []
