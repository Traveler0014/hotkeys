; ============================================================================
;  Settings.ahk  --  配置读写（hotkeys.ini）与「热键设置」窗口
;
;  配置分层：
;    1. lib\Config.ahk  内置默认值（分享给同事的就是这份，人人可用）
;    2. hotkeys.ini     本机覆盖（由本窗口生成，已在 .gitignore 中）
;  设置窗口可增删改启动器、改通用参数，保存后自动重载脚本。
; ============================================================================

global SETTINGS_INI  := A_ScriptDir . '\hotkeys.ini'

global SET_GUI       := ''      ; 设置窗口对象
global SET_LV        := ''      ; 启动器列表控件
global SET_CTRL      := ''      ; 设置窗口里的输入控件
global SET_EDITING   := ''      ; 编辑单个启动器时的上下文
global SET_WORKSET   := []      ; 设置窗口内的副本（取消即丢弃）

; ------------------------------------------------------------- INI 读写 ----
; 自己实现 UTF-8 INI 读写：不用 IniRead/IniWrite（它们对 UTF-16 有依赖，
; 手改文件或分享给别人时容易乱码），也让配置文件保持纯文本、可 diff。

Settings_IniRead(file) {
    data := Map()
    if !FileExist(file)
        return data
    section := 'general'
    content := FileRead(file, 'UTF-8')
    Loop Parse content, "`n", "`r" {
        line := Trim(A_LoopField)
        if (line = '')
            continue
        if (SubStr(line, 1, 1) = ';')
            continue
        if (SubStr(line, 1, 1) = '[') {
            section := Trim(SubStr(line, 2, -1))
            continue
        }
        eq := InStr(line, '=')
        if !eq
            continue
        key := Trim(SubStr(line, 1, eq - 1))
        value := Trim(SubStr(line, eq + 1))
        if (key = '')
            continue
        data[section . '.' . key] := value
    }
    return data
}

Settings_IniGet(data, section, key, fallback := '') {
    full := section . '.' . key
    return data.Has(full) ? data[full] : fallback
}

Settings_IniWrite(file, lines) {
    if FileExist(file)
        FileDelete(file)
    text := ''
    for line in lines
        text .= line . "`n"
    FileAppend(text, file, 'UTF-8')
}

; ------------------------------------------------------------------ 加载 ----
Settings_Load() {
    global CFG, APPS, SETTINGS_INI

    APPS := Settings_CopyApps(APPS_DEFAULT)

    if !FileExist(SETTINGS_INI) {
        Util_Log('未找到 hotkeys.ini，使用内置默认配置（' . APPS.Length . ' 个启动器）')
        return
    }

    kv := Settings_IniRead(SETTINGS_INI)

    home := Settings_IniGet(kv, 'general', 'home', '')
    if (home != '')
        CFG.Home := home
    CFG.TopMostTitlePrefix := Settings_IniGet(kv, 'general', 'topmostPrefix', CFG.TopMostTitlePrefix)
    CFG.AlarmInterval      := Settings_ToInt(Settings_IniGet(kv, 'general', 'alarmInterval', CFG.AlarmInterval), CFG.AlarmInterval)
    CFG.AlarmPingTimeout   := Settings_ToInt(Settings_IniGet(kv, 'general', 'alarmPingTimeout', CFG.AlarmPingTimeout), CFG.AlarmPingTimeout)
    CFG.AlarmBeeps         := Settings_ToInt(Settings_IniGet(kv, 'general', 'alarmBeeps', CFG.AlarmBeeps), CFG.AlarmBeeps)
    CFG.AlarmPopup         := Settings_ToInt(Settings_IniGet(kv, 'general', 'alarmPopup', 0), 0) ? true : false
    CFG.LogEnabled         := Settings_ToInt(Settings_IniGet(kv, 'general', 'logEnabled', 1), 1) ? true : false

    count := Settings_ToInt(Settings_IniGet(kv, 'apps', 'count', 0), 0)
    if (count > 0) {
        APPS := []
        Loop count {
            sec := 'app' . A_Index
            key := Trim(Settings_IniGet(kv, sec, 'key', ''))
            exe := Trim(Settings_IniGet(kv, sec, 'exe', ''))
            if (key = '' || exe = '')
                continue
            APPS.Push({
                key: key,
                label: Settings_IniGet(kv, sec, 'label', key),
                exe: exe,
                args: Settings_IniGet(kv, sec, 'args', ''),
                workdir: Settings_IniGet(kv, sec, 'workdir', ''),
                activateIfRunning: Settings_ToInt(Settings_IniGet(kv, sec, 'activateIfRunning', 0), 0) ? true : false,
            })
        }
    }
    Util_Log('已加载 hotkeys.ini（' . APPS.Length . ' 个启动器）')
}

; ------------------------------------------------------------------ 保存 ----
Settings_Save() {
    global CFG, APPS, SETTINGS_INI

    lines := []
    lines.Push('; 本文件由托盘菜单「热键设置」自动生成；删除它即回到内置默认配置')
    lines.Push('; 编码 UTF-8，以分号开头的行是注释')
    lines.Push('')
    lines.Push('[general]')
    lines.Push('home=' . CFG.Home)
    lines.Push('topmostPrefix=' . CFG.TopMostTitlePrefix)
    lines.Push('alarmInterval=' . CFG.AlarmInterval)
    lines.Push('alarmPingTimeout=' . CFG.AlarmPingTimeout)
    lines.Push('alarmBeeps=' . CFG.AlarmBeeps)
    lines.Push('alarmPopup=' . (CFG.AlarmPopup ? 1 : 0))
    lines.Push('logEnabled=' . (CFG.LogEnabled ? 1 : 0))
    lines.Push('')
    lines.Push('[apps]')
    lines.Push('count=' . APPS.Length)
    for i, app in APPS {
        lines.Push('')
        lines.Push('[app' . i . ']')
        lines.Push('key=' . app.key)
        lines.Push('label=' . app.label)
        lines.Push('exe=' . app.exe)
        lines.Push('args=' . app.args)
        lines.Push('workdir=' . app.workdir)
        lines.Push('activateIfRunning=' . (app.activateIfRunning ? 1 : 0))
    }
    Settings_IniWrite(SETTINGS_INI, lines)
    Util_Log('已保存 hotkeys.ini（' . APPS.Length . ' 个启动器）')
}

; --------------------------------------------------------------- 小工具 ----
Settings_ToInt(value, fallback) {
    value := Trim(value . '')
    return (value ~= '^-?\d+$') ? Integer(value) : fallback
}

Settings_CopyApps(source) {
    copy := []
    for app in source {
        copy.Push({
            key: app.key, label: app.label, exe: app.exe,
            args: app.args, workdir: app.workdir,
            activateIfRunning: app.activateIfRunning,
        })
    }
    return copy
}

; 热键写法校验，返回空字符串表示合法
Settings_ValidateHotkey(key) {
    key := Trim(key . '')
    if (key = '')
        return '热键不能为空。'
    pattern := '^[~$*<>]?[\^!#+]*([A-Za-z0-9]|F([1-9]|1[0-9]|2[0-4])'
        . '|Space|Tab|Enter|Esc(ape)?|Backspace|Delete|Insert|Home|End|PgUp|PgDn'
        . '|Up|Down|Left|Right|Numpad[0-9]|NumpadDot|NumpadEnter)$'
    if !RegExMatch(key, pattern)
        return '无法识别的热键写法。示例：^!t 表示 Ctrl+Alt+T，#e 表示 Win+E，!F2 表示 Alt+F2。'
    return ''
}

Settings_FindAppByKey(key, exceptIndex) {
    global SET_WORKSET
    for i, app in SET_WORKSET {
        if (i = exceptIndex)
            continue
        if (app.key = key)
            return app
    }
    return ''
}

; ------------------------------------------------------------- 设置窗口 ----
Settings_ShowGui(*) {
    global SET_GUI, SET_LV, SET_CTRL, SET_WORKSET, CFG

    SET_WORKSET := Settings_CopyApps(APPS)

    if IsObject(SET_GUI) {
        Settings_SyncCtrlToCurrent()
        Settings_RefreshList()
        SET_GUI.Show()
        return
    }

    g := Gui('+AlwaysOnTop', '热键设置')
    g.SetFont('s9')
    g.MarginX := 12
    g.MarginY := 10

    g.Add('Text', 'xm', '启动器（热键 → 程序）')
    SET_LV := g.Add('ListView', 'xm w540 h150', ['热键', '说明', '程序'])
    SET_LV.ModifyCol(1, 90)
    SET_LV.ModifyCol(2, 170)
    SET_LV.ModifyCol(3, 270)
    SET_LV.OnEvent('DoubleClick', (*) => Settings_EditSelected())

    g.Add('Button', 'xm w70', '添加').OnEvent('Click', (*) => Settings_EditApp(0))
    g.Add('Button', 'x+6 w70', '编辑').OnEvent('Click', (*) => Settings_EditSelected())
    g.Add('Button', 'x+6 w70', '删除').OnEvent('Click', (*) => Settings_DeleteSelected())
    g.Add('Button', 'x+6 w70', '上移').OnEvent('Click', (*) => Settings_MoveSelected(-1))
    g.Add('Button', 'x+6 w70', '下移').OnEvent('Click', (*) => Settings_MoveSelected(1))
    g.Add('Button', 'x+6 w100', '恢复默认').OnEvent('Click', (*) => Settings_ResetDefaults())

    g.Add('Text', 'xm y+14', '通用设置')
    g.Add('Text', 'xm y+6 w90', '工作目录')
    cHome := g.Add('Edit', 'x+6 w300', CFG.Home)
    g.Add('Button', 'x+6 w70', '浏览…').OnEvent('Click', (*) => Settings_PickFolder(cHome))

    g.Add('Text', 'xm y+8 w90', '置顶标题前缀')
    cPrefix := g.Add('Edit', 'x+6 w70', CFG.TopMostTitlePrefix)
    g.Add('Text', 'x+8 yp+3', '（留空 = 不改标题，仅置顶）')

    g.Add('Text', 'xm y+10 w90', '探测间隔(ms)')
    cInterval := g.Add('Edit', 'x+6 w70 Number', CFG.AlarmInterval)
    g.Add('Text', 'x+10 yp+3', '单次超时(ms)')
    cTimeout := g.Add('Edit', 'x+6 w70 Number', CFG.AlarmPingTimeout)
    g.Add('Text', 'x+10 yp+3', '蜂鸣次数')
    cBeeps := g.Add('Edit', 'x+6 w50 Number', CFG.AlarmBeeps)

    cPopup := g.Add('Checkbox', 'xm y+12', '闹钟命中后额外弹窗（会阻塞脚本，慎选）')
    cPopup.Value := CFG.AlarmPopup ? 1 : 0

    g.Add('Button', 'xm y+14 w130 Default', '保存并重载').OnEvent('Click', (*) => Settings_SaveFromGui())
    g.Add('Button', 'x+8 w90', '取消').OnEvent('Click', (*) => Settings_CloseGui())
    g.OnEvent('Close', (*) => Settings_CloseGui())
    g.OnEvent('Escape', (*) => Settings_CloseGui())

    SET_GUI := g
    SET_CTRL := { home: cHome, prefix: cPrefix, interval: cInterval
                , timeout: cTimeout, beeps: cBeeps, popup: cPopup }

    Settings_RefreshList()
    g.Show()
}

; 重新打开窗口时把控件同步成当前生效配置
Settings_SyncCtrlToCurrent() {
    global SET_CTRL, CFG
    SET_CTRL.home.Value := CFG.Home
    SET_CTRL.prefix.Value := CFG.TopMostTitlePrefix
    SET_CTRL.interval.Value := CFG.AlarmInterval
    SET_CTRL.timeout.Value := CFG.AlarmPingTimeout
    SET_CTRL.beeps.Value := CFG.AlarmBeeps
    SET_CTRL.popup.Value := CFG.AlarmPopup ? 1 : 0
}

Settings_CloseGui(*) {
    global SET_GUI
    if IsObject(SET_GUI)
        SET_GUI.Hide()
}

Settings_PickFolder(ctrl) {
    dir := DirSelect('', 3, '选择工作目录')
    if (dir != '')
        ctrl.Value := dir
}

Settings_RefreshList() {
    global SET_LV, SET_WORKSET
    if !IsObject(SET_LV)
        return
    SET_LV.Delete()
    for i, app in SET_WORKSET
        SET_LV.Add('', app.key, app.label, app.exe)
}

Settings_SelectedIndex() {
    global SET_LV
    if !IsObject(SET_LV)
        return 0
    row := SET_LV.GetNext(0, 'F')
    return row ? row : 0
}

Settings_EditSelected(*) {
    index := Settings_SelectedIndex()
    if (index = 0)
        Util_Notify('热键设置', '请先在列表中选中一项')
    else
        Settings_EditApp(index)
}

Settings_DeleteSelected(*) {
    global SET_WORKSET
    index := Settings_SelectedIndex()
    if (index = 0) {
        Util_Notify('热键设置', '请先在列表中选中一项')
        return
    }
    SET_WORKSET.RemoveAt(index)
    Settings_RefreshList()
}

Settings_MoveSelected(delta) {
    global SET_LV, SET_WORKSET
    index := Settings_SelectedIndex()
    target := index + delta
    if (index = 0 || target < 1 || target > SET_WORKSET.Length) {
        Util_Notify('热键设置', '请先选中可移动的项')
        return
    }
    item := SET_WORKSET.RemoveAt(index)
    SET_WORKSET.InsertAt(target, item)
    Settings_RefreshList()
    SET_LV.Modify(0, 'Select Focus', target)
}

Settings_ResetDefaults() {
    global SET_WORKSET
    if (MsgBox('用内置默认启动器列表覆盖当前列表？', '恢复默认', 'YesNo Icon?') = 'Yes') {
        SET_WORKSET := Settings_CopyApps(APPS_DEFAULT)
        Settings_RefreshList()
    }
}

; ------------------------------------------- 单个启动器的编辑小窗口 -------
Settings_EditApp(index) {
    global SET_EDITING, SET_WORKSET

    if (index = 0)
        app := { key: '', label: '', exe: '', args: '', workdir: '', activateIfRunning: false }
    else
        app := {
            key: SET_WORKSET[index].key, label: SET_WORKSET[index].label,
            exe: SET_WORKSET[index].exe,
            args: SET_WORKSET[index].args, workdir: SET_WORKSET[index].workdir,
            activateIfRunning: SET_WORKSET[index].activateIfRunning,
        }

    e := Gui('+AlwaysOnTop', index = 0 ? '添加快捷键' : '编辑快捷键')
    e.SetFont('s9')
    e.MarginX := 12
    e.MarginY := 10

    e.Add('Text', 'xm', '热键（例：^!t 表示 Ctrl+Alt+T，#e 表示 Win+E，!F2 表示 Alt+F2）')
    edKey := e.Add('Edit', 'xm w160', app.key)
    e.Add('Text', 'xm y+8', '说明')
    edLabel := e.Add('Edit', 'xm w440', app.label)
    e.Add('Text', 'xm y+8', '程序路径（可写裸文件名让系统按 PATH 查找）')
    edExe := e.Add('Edit', 'xm w350', app.exe)
    e.Add('Button', 'x+6 w80', '浏览…').OnEvent('Click', (*) => Settings_PickExe(edExe))
    e.Add('Text', 'xm y+8', '启动参数')
    edArgs := e.Add('Edit', 'xm w440', app.args)
    e.Add('Text', 'xm y+8', '工作目录（留空 = 通用工作目录）')
    edWork := e.Add('Edit', 'xm w440', app.workdir)
    cbActivate := e.Add('Checkbox', 'xm y+10', '已在运行时激活窗口，而不是再开一个')
    cbActivate.Value := app.activateIfRunning ? 1 : 0

    e.Add('Button', 'xm y+14 w90 Default', '确定').OnEvent('Click', (*) => Settings_EditAppOk())
    e.Add('Button', 'x+8 w90', '取消').OnEvent('Click', (*) => e.Hide())
    e.OnEvent('Escape', (*) => e.Hide())

    SET_EDITING := {
        gui: e, index: index,
        key: edKey, label: edLabel, exe: edExe, args: edArgs, work: edWork, activate: cbActivate,
    }
    e.Show()
}

Settings_PickExe(ctrl) {
    ; v2 的 Filter 只写一个过滤器描述（如 '程序 (*.exe)'），
    ; 不要再拼 v1 那种 "描述|通配符" 的多段写法——v2 取第一个 '(' 到最后一个 ')' 之间
    ; 的内容作为通配符，管道符会污染 pattern 导致筛选失效；
    ; "所有文件 (*.*)" 由系统对话框自动提供。
    path := FileSelect('3', '', '选择程序', '程序 (*.exe)')
    if (path != '')
        ctrl.Value := path
}

Settings_EditAppOk(*) {
    global SET_EDITING, SET_WORKSET

    ctx := SET_EDITING
    key := Trim(ctx.key.Value)
    problem := Settings_ValidateHotkey(key)
    if (problem != '') {
        MsgBox(problem, '热键无效', 'Icon!')
        return
    }
    if (other := Settings_FindAppByKey(key, ctx.index)) {
        MsgBox('热键 ' . key . ' 已被「' . other.label . '」占用。', '热键重复', 'Icon!')
        return
    }
    exe := Trim(ctx.exe.Value)
    if (exe = '') {
        MsgBox('请填写程序路径。', '缺少程序', 'Icon!')
        return
    }

    app := {
        key: key,
        label: Trim(ctx.label.Value),
        exe: exe,
        args: Trim(ctx.args.Value),
        workdir: Trim(ctx.work.Value),
        activateIfRunning: ctx.activate.Value ? true : false,
    }
    if (app.label = '')
        app.label := key

    if (ctx.index = 0)
        SET_WORKSET.Push(app)
    else
        SET_WORKSET[ctx.index] := app

    Settings_RefreshList()
    ctx.gui.Hide()
}

; --------------------------------------------------------------- 保存 ------
Settings_SaveFromGui(*) {
    global SET_GUI, SET_CTRL, SET_WORKSET, CFG, APPS

    if (SET_WORKSET.Length = 0) {
        MsgBox('至少要保留一个启动器。', '无法保存', 'Icon!')
        return
    }

    CFG.Home               := Trim(SET_CTRL.home.Value)
    CFG.TopMostTitlePrefix := SET_CTRL.prefix.Value
    CFG.AlarmInterval      := Settings_ToInt(SET_CTRL.interval.Value, CFG.AlarmInterval)
    CFG.AlarmPingTimeout   := Settings_ToInt(SET_CTRL.timeout.Value, CFG.AlarmPingTimeout)
    CFG.AlarmBeeps         := Settings_ToInt(SET_CTRL.beeps.Value, CFG.AlarmBeeps)
    CFG.AlarmPopup         := SET_CTRL.popup.Value ? true : false

    APPS := SET_WORKSET
    Settings_Save()
    SET_GUI.Hide()
    Util_Notify('热键设置', '已保存到 hotkeys.ini，正在重载脚本…')
    SetTimer(() => Reload(), -600)
}
