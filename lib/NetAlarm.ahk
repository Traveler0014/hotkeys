; ============================================================================
;  NetAlarm.ahk  --  Alt+N：服务器上线闹钟（多任务 / 可取消 / 非阻塞）
;
;  设计要点（对比旧版）：
;    * 每个目标一个独立定时器，用 Map 管理，互不影响；
;      旧版每次按 Alt+N 都在全局叠加一个 SetTimer，且 SetTimer(,0) 会误杀全部定时器。
;    * ping 用 Run() 异步发起，由一个 250ms 的收集器轮询结果文件来判断通断，
;      主线程完全不被阻塞，热键始终灵敏（旧版 RunWait 会卡住整个脚本约 1 秒）。
;    * 不用 PID 跟踪进程（某些环境下 Run() 拿不到 PID，不可靠），
;      改由 ping 命令自己写"成功/失败"标记文件，脚本只轮询文件是否存在。
;    * 任务可随时停止；GUI 与托盘都能看到还有几个在监控。
;    * 目标做字符白名单校验，避免拼进命令行时被注入。
; ============================================================================

global ALARM_TASKS     := Map()    ; id -> task
global ALARM_NEXT_ID   := 0
global ALARM_COLLECTOR := false    ; 收集器定时器是否在运行
global ALARM_TMP       := A_Temp . '\ahk_hotkeys_alarm'

global ALARM_GUI       := ''       ; Gui 对象
global ALARM_LV        := ''       ; ListView 控件
global ALARM_ED_TARGET := ''       ; 目标输入框
global ALARM_ED_NOTE   := ''       ; 备注输入框

NetAlarm_Register() {
    try {
        Hotkey('!n', NetAlarm_ShowGui)
        Util_Log('注册热键 !n -> 服务器上线闹钟')
    } catch as e {
        Util_Log('热键注册失败 !n: ' . e.Message)
    }
    OnExit(NetAlarm_Cleanup)
}

NetAlarm_Cleanup(*) {
    global ALARM_TMP
    if DirExist(ALARM_TMP)
        try DirDelete(ALARM_TMP, true)
}

; ---------------------------------------------------------------- GUI ------
NetAlarm_ShowGui(*) {
    global ALARM_GUI, ALARM_LV, ALARM_ED_TARGET, ALARM_ED_NOTE

    if IsObject(ALARM_GUI) {
        ALARM_GUI.Show()
        NetAlarm_Refresh()
        ALARM_ED_TARGET.Focus()
        return
    }

    g := Gui('+AlwaysOnTop', '服务器上线闹钟')
    g.SetFont('s9')
    g.MarginX := 12
    g.MarginY := 10

    g.Add('Text', 'xm', '目标 IP / 域名（多个用空格或逗号分隔）')
    ALARM_ED_TARGET := g.Add('Edit', 'xm w420')

    g.Add('Text', 'xm y+8', '备注（命中提示里会显示）')
    ALARM_ED_NOTE := g.Add('Edit', 'xm w420', '服务器已上线')

    btnAdd := g.Add('Button', 'xm y+10 w120 Default', '开始监控')
    btnStop := g.Add('Button', 'x+8 w100', '停止选中')
    btnStopAll := g.Add('Button', 'x+8 w100', '停止全部')

    ALARM_LV := g.Add('ListView', 'xm y+10 w470 h150', ['目标', '备注', '状态', '探测', '#id'])
    ALARM_LV.ModifyCol(1, 150)
    ALARM_LV.ModifyCol(2, 140)
    ALARM_LV.ModifyCol(3, 80)
    ALARM_LV.ModifyCol(4, 50)
    ALARM_LV.ModifyCol(5, 0)          ; 隐藏列，存任务 id

    btnAdd.OnEvent('Click', (*) => NetAlarm_AddFromGui())
    btnStop.OnEvent('Click', (*) => NetAlarm_StopSelected())
    btnStopAll.OnEvent('Click', (*) => NetAlarm_StopAll())
    g.OnEvent('Close', (*) => NetAlarm_HideGui())
    g.OnEvent('Escape', (*) => NetAlarm_HideGui())

    ALARM_GUI := g
    NetAlarm_Refresh()
    g.Show()
    ALARM_ED_TARGET.Focus()
}

NetAlarm_HideGui(*) {
    global ALARM_GUI
    if IsObject(ALARM_GUI)
        ALARM_GUI.Hide()
}

NetAlarm_AddFromGui(*) {
    global ALARM_ED_TARGET, ALARM_ED_NOTE
    note := Trim(ALARM_ED_NOTE.Value)
    if (NetAlarm_Add(ALARM_ED_TARGET.Value, note) > 0)
        ALARM_ED_TARGET.Value := ''
    ALARM_ED_TARGET.Focus()
}

; ------------------------------------------------------------ 任务管理 ------
; 返回值：成功加入的目标个数
NetAlarm_Add(targetsText, note) {
    global ALARM_TASKS, ALARM_NEXT_ID, CFG

    note := Trim(note . '')
    added := 0
    for target in NetAlarm_SplitTargets(targetsText) {
        target := Trim(target)
        if (target = '')
            continue
        if !RegExMatch(target, '^[A-Za-z0-9._:\-]+$') {
            Util_Log('闹钟忽略非法目标: ' . target)
            Util_Notify('目标无效', '已忽略: ' . target)
            continue
        }
        if NetAlarm_FindByTarget(target)
            continue

        ALARM_NEXT_ID += 1
        task := {
            id:       ALARM_NEXT_ID,
            target:   target,
            note:     note,
            state:    '等待中',
            attempts: 0,
            probe:    '',
            running:  true,
            timer:    '',
        }
        task.timer := NetAlarm_Tick.Bind(task.id)
        ALARM_TASKS[task.id] := task
        SetTimer(task.timer, CFG.AlarmInterval)
        added += 1
        Util_Log('闹钟开始监控 ' . target . (note = '' ? '' : '（备注: ' . note . '）'))
        NetAlarm_Probe(task)          ; 立即探一次，不用等第一个间隔
    }

    if (added = 0 && Trim(targetsText . '') = '')
        Util_Notify('上线闹钟', '请先填写目标 IP 或域名')

    NetAlarm_Refresh()
    return added
}

; 把 "1.2.3.4 5.6.7.8,9.9.9.9" 拆成目标列表
; 注意：不用 StrSplit 的多字符分隔集，改用正则归一化后按单空格切分，兼容性更好
NetAlarm_SplitTargets(text) {
    out := []
    normalized := RegExReplace(Trim(text . ''), '[\s,;]+', ' ')
    if (normalized = '')
        return out
    for token in StrSplit(normalized, ' ') {
        if (token != '')
            out.Push(token)
    }
    return out
}

NetAlarm_FindByTarget(target) {
    global ALARM_TASKS
    for id, task in ALARM_TASKS {
        if (task.target = target)
            return task
    }
    return ''
}

; 每个目标的定时器回调：上一次探测还没结果就等结果，不叠加
NetAlarm_Tick(id, *) {
    global ALARM_TASKS
    if !ALARM_TASKS.Has(id)
        return
    task := ALARM_TASKS[id]
    if IsObject(task.probe)
        return
    NetAlarm_Probe(task)
}

; 异步发起一次 ping：ping 自己写成功/失败标记文件，脚本只等文件
NetAlarm_Probe(task) {
    global CFG, ALARM_TMP

    if !DirExist(ALARM_TMP)
        DirCreate(ALARM_TMP)
    okFile := ALARM_TMP . '\p' . task.id . '_ok'
    failFile := ALARM_TMP . '\p' . task.id . '_fail'
    for f in [okFile, failFile] {
        if FileExist(f)
            try FileDelete(f)
    }

    task.attempts += 1
    task.state := '探测中'
    task.probe := { ok: okFile, fail: failFile, started: A_TickCount }

    cmd := A_ComSpec . ' /c ping -n 1 -w ' . CFG.AlarmPingTimeout . ' "' . task.target . '" >nul 2>&1'
        . ' && type nul >"' . okFile . '" || type nul >"' . failFile . '"'
    try {
        Run(cmd, , 'Hide')
    } catch as e {
        task.probe := ''
        Util_Log('ping 启动失败 ' . task.target . ': ' . e.Message)
    }

    NetAlarm_EnsureCollector()
    NetAlarm_Refresh()
}

; 250ms 收集器：检查探测结果文件
NetAlarm_Collect(*) {
    global ALARM_TASKS
    for id, task in ALARM_TASKS {
        if IsObject(task.probe)
            NetAlarm_CheckProbe(task)
    }
    NetAlarm_EnsureCollector()
}

NetAlarm_CheckProbe(task) {
    p := task.probe
    if FileExist(p.ok) {
        NetAlarm_ClearProbe(task)
        task.state := '已上线'
        NetAlarm_Alarm(task)
        NetAlarm_Halt(task)                     ; 停止该任务，保留结果行
        NetAlarm_Refresh()
        return
    }
    if FileExist(p.fail) {
        NetAlarm_ClearProbe(task)
        task.state := '未上线'
        NetAlarm_Refresh()
        return
    }
    if (A_TickCount - p.started > 20000) {       ; 20 秒没有结果，当作失败
        NetAlarm_ClearProbe(task)
        task.state := '未上线'
        Util_Log('探测超时 ' . task.target)
        NetAlarm_Refresh()
    }
}

NetAlarm_ClearProbe(task) {
    if !IsObject(task.probe)
        return
    for f in [task.probe.ok, task.probe.fail] {
        if FileExist(f)
            try FileDelete(f)
    }
    task.probe := ''
}

NetAlarm_EnsureCollector() {
    global ALARM_TASKS, ALARM_COLLECTOR
    pending := false
    for id, task in ALARM_TASKS {
        if IsObject(task.probe) {
            pending := true
            break
        }
    }
    if (pending && !ALARM_COLLECTOR) {
        SetTimer(NetAlarm_Collect, 250)
        ALARM_COLLECTOR := true
    } else if (!pending && ALARM_COLLECTOR) {
        SetTimer(NetAlarm_Collect, 0)
        ALARM_COLLECTOR := false
    }
}

; 命中：托盘提示 + 蜂鸣（+ 可选弹窗）
NetAlarm_Alarm(task) {
    global CFG
    Util_Log('闹钟命中 ' . task.target . (task.note = '' ? '' : '（备注: ' . task.note . '）'))
    Util_Notify('目标已上线', task.target . (task.note = '' ? '' : "`n" . task.note))
    Loop CFG.AlarmBeeps {
        try SoundBeep(750, 300)
        Sleep(120)
    }
    if CFG.AlarmPopup
        try MsgBox(task.target . ' 已上线！' . (task.note = '' ? '' : "`n`n" . task.note), '上线闹钟', 'Iconi 4096')
}

; 只停定时器，任务行保留（用于"已上线"）
NetAlarm_Halt(task) {
    task.running := false
    if IsObject(task.timer)
        try SetTimer(task.timer, 0)
}

; 停止并移除
NetAlarm_Stop(id) {
    global ALARM_TASKS
    if !ALARM_TASKS.Has(id)
        return
    task := ALARM_TASKS[id]
    NetAlarm_Halt(task)
    NetAlarm_ClearProbe(task)
    ALARM_TASKS.Delete(id)
    Util_Log('闹钟停止 ' . task.target)
    NetAlarm_EnsureCollector()
    NetAlarm_Refresh()
}

NetAlarm_StopSelected(*) {
    global ALARM_LV
    if !IsObject(ALARM_LV)
        return
    ids := []
    row := 0
    while (row := ALARM_LV.GetNext(row, 'F'))
        ids.Push(ALARM_LV.GetText(row, 5) + 0)
    for id in ids
        NetAlarm_Stop(id)
}

NetAlarm_StopAll(*) {
    global ALARM_TASKS
    ids := []
    for id, task in ALARM_TASKS
        ids.Push(id)
    for id in ids
        NetAlarm_Stop(id)
    Util_Log('闹钟全部停止')
}

; 刷新列表与托盘提示
NetAlarm_Refresh() {
    global ALARM_TASKS, ALARM_LV
    if IsObject(ALARM_LV) {
        ALARM_LV.Delete()
        for id, task in ALARM_TASKS
            ALARM_LV.Add('', task.target, task.note, task.state, task.attempts, task.id)
    }
    n := 0
    for id, task in ALARM_TASKS {
        if task.running
            n += 1
    }
    Util_SetTrayTip(n > 0 ? '热键脚本 · 监控中 ' . n . ' 个' : '热键脚本 · 已就绪')
}
