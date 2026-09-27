sub init()
    ' Window length and row count come from settings. GuideScene (and so this
    ' grid) is recreated by MainScene whenever the guide is opened after a
    ' settings save, so reading them once here is enough. GuideScene positions
    ' this grid using the same guideGeometry() numbers.
    settings = readSettings()
    geo = guideGeometry(settings)

    m.CHANNEL_COL_W  = 200
    m.PROGRAM_AREA_W = 1720
    m.WINDOW_MINUTES = settings.guideHours * 60
    m.PX_PER_MIN     = m.PROGRAM_AREA_W / m.WINDOW_MINUTES
    m.ROW_HEIGHT     = geo.rowHeight
    m.VISIBLE_ROWS   = geo.rows
    ' Row geometry (58px, logo, fonts) is fixed in GuideRow.xml; rows only need
    ' the time window to lay out their cells.
    m.rowLayout = { windowMinutes: m.WINDOW_MINUTES, pxPerMin: m.PX_PER_MIN }

    m.rowContainer = m.top.findNode("rowContainer")
    m.timeHeader   = m.top.findNode("timeHeader")
    m.nowLine      = m.top.findNode("nowLine")
    m.clock        = m.top.findNode("clock")
    m.tickTimer    = m.top.findNode("tickTimer")
    m.rowContainer.translation = [0, geo.headerH]
    m.nowLine.translation      = [m.CHANNEL_COL_W, geo.headerH]
    m.nowLine.height           = geo.guideH - geo.headerH

    m.topRowIdx   = 0
    m.focusedRow  = 0
    m.channels    = []
    m.programs    = {}
    m.windowStart = 0
    m.clockText   = ""
    m.firedProgStart = -1

    ' The cursor is a time position (anchor, epoch seconds) on the focused row:
    ' the selected show is the one covering it. Up/Down keep the anchor so the
    ' cursor stays in the same time column; Left/Right move it to the start of
    ' the previous/next show. followNow keeps the anchor on the current time
    ' (so the selection moves on when a show ends) until Left/Right picks a show
    ' that is not on now.
    m.anchor    = nowEpoch()
    m.followNow = true
    ' Window start moveSelection is setting, so onWindowChange can tell its own
    ' moves from outside sets (which reset the cursor to now). -1 = none.
    m.internalWindow = -1

    ' rowKeys[i] records what rowPool[i] currently shows ("<channelId>|<windowStart>")
    ' so updateRows can skip rows whose content has not changed.
    m.rowPool = []
    m.rowKeys = []
    for i = 0 to m.VISIBLE_ROWS - 1
        row = m.rowContainer.createChild("GuideRow")
        row.layout      = m.rowLayout
        row.translation = [0, i * m.ROW_HEIGHT]
        m.rowPool.push(row)
        m.rowKeys.push("")
    end for

    ' Time header labels are created once and retexted on window change. The
    ' window always starts on a half hour, so there is a label every 30 minutes.
    ' The label that would sit at the window's end is off-canvas, so it is not
    ' created.
    m.LABEL_INTERVAL_MIN = 30
    m.headerLabels = []
    labelWidthPx = Int(m.LABEL_INTERVAL_MIN * m.PX_PER_MIN)
    for i = 0 to (m.WINDOW_MINUTES / m.LABEL_INTERVAL_MIN) - 1
        lbl = m.timeHeader.createChild("Label")
        lbl.color       = "0x96BBBBFF"
        lbl.font        = "font:SmallSystemFont"
        lbl.translation = [Int(i * m.LABEL_INTERVAL_MIN * m.PX_PER_MIN), 0]
        lbl.width       = labelWidthPx
        m.headerLabels.push(lbl)
    end for

    ' Clock and now line tick every 5 s: at 4h the now line moves about one
    ' pixel every 8 s, so this keeps it visibly creeping. The window itself
    ' stays put while the guide is open; MainScene resets it to the current
    ' half hour whenever the guide is (re)opened.
    m.tickTimer.observeField("fire", "onTick")
    onTick()
    m.tickTimer.control = "start"
end sub

sub onDataChange()
    data = m.top.guideData
    if data = invalid then return

    ' Keep the cursor on the same channel across data refreshes.
    prevId = ""
    prev = getFocusedChannel()
    if prev <> invalid then prevId = prev.id

    if data.channels <> invalid then m.channels = data.channels
    if data.programs <> invalid then m.programs = data.programs
    invalidateRows()

    if not focusChannelId(prevId) then clampCursor()
    updateRows()
    fireFocusedProgram()
end sub

sub onScrollToChannelId()
    if focusChannelId(m.top.scrollToChannelId)
        updateRows()
        fireFocusedProgram()
    end if
end sub

' Move the cursor to the channel with the given id. If the channel is already on
' screen the viewport stays put; otherwise it scrolls so the channel is visible.
' Returns false (cursor untouched) when the id is empty or not in the list.
function focusChannelId(id as string) as boolean
    if id = "" then return false
    for i = 0 to m.channels.count() - 1
        if m.channels[i].id = id
            if i < m.topRowIdx or i >= m.topRowIdx + m.VISIBLE_ROWS
                m.topRowIdx = i
            end if
            clampCursor()
            m.focusedRow = i - m.topRowIdx
            return true
        end if
    end for
    return false
end function

' Pull topRowIdx / focusedRow back into range after the channel list changed.
sub clampCursor()
    maxTop = m.channels.count() - m.VISIBLE_ROWS
    if maxTop < 0 then maxTop = 0
    if m.topRowIdx > maxTop then m.topRowIdx = maxTop
    maxFocused = m.channels.count() - m.topRowIdx - 1
    if maxFocused < 0 then maxFocused = 0
    if maxFocused > m.VISIBLE_ROWS - 1 then maxFocused = m.VISIBLE_ROWS - 1
    if m.focusedRow > maxFocused then m.focusedRow = maxFocused
end sub

sub onWindowChange()
    external = (m.top.windowStart <> m.internalWindow)
    m.internalWindow = -1
    m.windowStart = m.top.windowStart
    if external
        ' Set by GuideScene/MainScene (guide opened, back from the player), not
        ' by moveSelection: the cursor goes back to following now.
        m.followNow   = true
        m.anchor      = clampToWindow(nowEpoch())
    end if
    buildTimeHeader()
    updateNowLine()
    updateRows()
    if external then fireFocusedProgram()
end sub

function clampToWindow(t as integer) as integer
    if t < m.windowStart then return m.windowStart
    windowEnd = m.windowStart + m.WINDOW_MINUTES * 60
    if t >= windowEnd then return windowEnd - 1
    return t
end function

sub buildTimeHeader()
    for i = 0 to m.headerLabels.count() - 1
        m.headerLabels[i].text = epochToTimeStr(m.windowStart + i * m.LABEL_INTERVAL_MIN * 60)
    end for
end sub

sub onRunningChange()
    if m.top.running
        onTick()
        m.tickTimer.control = "start"
    else
        m.tickTimer.control = "stop"
    end if
end sub

sub onTick()
    updateNowLine()
    if m.followNow
        nowSec = nowEpoch()
        if nowSec >= m.windowStart and nowSec < m.windowStart + m.WINDOW_MINUTES * 60
            m.anchor = nowSec
            if m.focusedRow < m.rowPool.count() then m.rowPool[m.focusedRow].selTime = m.anchor
        end if
    end if
    txt = epochToTimeStr(nowEpoch())
    if txt <> m.clockText
        m.clockText  = txt
        m.clock.text = txt
    end if
    ' When the anchor follows now and the show under it ends, the info panel
    ' moves on to the next one without the user having to nudge the cursor.
    prog = getFocusedProgram()
    progStart = -1
    if prog <> invalid then progStart = prog.start
    if progStart <> m.firedProgStart then fireFocusedProgram()
end sub

sub updateNowLine()
    nowSec = nowEpoch()
    offsetMin = (nowSec - m.windowStart) / 60
    if offsetMin < 0 or offsetMin > m.WINDOW_MINUTES
        m.nowLine.visible = false
    else
        x = m.CHANNEL_COL_W + Int(offsetMin * m.PX_PER_MIN)
        m.nowLine.translation = [x, m.nowLine.translation[1]]
        m.nowLine.visible = true
    end if
end sub

' Bind rows to channels. Only rows whose channel or window changed are rebuilt.
sub updateRows()
    for i = 0 to m.VISIBLE_ROWS - 1
        chanIdx = m.topRowIdx + i
        row = m.rowPool[i]
        if chanIdx < m.channels.count()
            ch = m.channels[chanIdx]
            key = ch.id + "|" + m.windowStart.toStr()
            if m.rowKeys[i] <> key
                progs = invalid
                if m.programs.doesExist(ch.id) then progs = m.programs[ch.id]
                row.rowData = { channel: ch, programs: progs, windowStart: m.windowStart }
                m.rowKeys[i] = key
            end if
            if i = m.focusedRow then row.selTime = m.anchor else row.selTime = -1
            row.visible = true
        else
            m.rowKeys[i] = ""
            row.visible = false
        end if
    end for
end sub

' Force every row to rebuild on the next updateRows (data changed under the same keys).
sub invalidateRows()
    for i = 0 to m.rowKeys.count() - 1
        m.rowKeys[i] = ""
    end for
end sub

' Shift the row pool by one so a single-step scroll rebinds one row instead of all.
' direction > 0: top row moves to the bottom; < 0: bottom row moves to the top.
sub rotateRows(direction as integer)
    if direction > 0
        m.rowPool.push(m.rowPool.shift())
        m.rowKeys.push(m.rowKeys.shift())
    else
        m.rowPool.unshift(m.rowPool.pop())
        m.rowKeys.unshift(m.rowKeys.pop())
    end if
    for i = 0 to m.rowPool.count() - 1
        m.rowPool[i].translation = [0, i * m.ROW_HEIGHT]
    end for
end sub

' Keys are forwarded from GuideScene (which holds focus) via the keyEvent field.
sub onKeyEventField()
    key = m.top.keyEvent.key
    if key = "down"
        scrollDown()
    else if key = "up"
        scrollUp()
    else if key = "fastforward"
        pageDown()
    else if key = "rewind"
        pageUp()
    else if key = "right"
        moveSelection(1)
    else if key = "left"
        moveSelection(-1)
    else if key = "OK" or key = "play"
        ch = getFocusedChannel()
        if ch <> invalid then m.top.selectedChannel = ch
    end if
end sub

sub scrollDown()
    maxTop = m.channels.count() - m.VISIBLE_ROWS
    if maxTop < 0 then maxTop = 0
    if m.focusedRow < m.VISIBLE_ROWS - 1 and (m.topRowIdx + m.focusedRow + 1) < m.channels.count()
        m.rowPool[m.focusedRow].selTime = -1
        m.focusedRow = m.focusedRow + 1
        m.rowPool[m.focusedRow].selTime = m.anchor
    else if m.topRowIdx < maxTop
        m.topRowIdx = m.topRowIdx + 1
        rotateRows(1)
        updateRows()
    end if
    fireFocusedProgram()
end sub

sub scrollUp()
    if m.focusedRow > 0
        m.rowPool[m.focusedRow].selTime = -1
        m.focusedRow = m.focusedRow - 1
        m.rowPool[m.focusedRow].selTime = m.anchor
    else if m.topRowIdx > 0
        m.topRowIdx = m.topRowIdx - 1
        rotateRows(-1)
        updateRows()
    end if
    fireFocusedProgram()
end sub

sub pageDown()
    maxTop = m.channels.count() - m.VISIBLE_ROWS
    if maxTop < 0 then maxTop = 0
    m.topRowIdx = m.topRowIdx + m.VISIBLE_ROWS
    if m.topRowIdx > maxTop then m.topRowIdx = maxTop
    m.focusedRow = 0
    updateRows()
    fireFocusedProgram()
end sub

sub pageUp()
    m.topRowIdx = m.topRowIdx - m.VISIBLE_ROWS
    if m.topRowIdx < 0 then m.topRowIdx = 0
    m.focusedRow = 0
    updateRows()
    fireFocusedProgram()
end sub

' Select the previous (-1) or next (+1) show on the focused row. When it lies
' outside the window the window moves: forward so the show starts in the first
' half hour, back so it ends in the last one.
sub moveSelection(direction as integer)
    progs = focusedPrograms()
    if progs = invalid then return
    cur = showAt(progs, m.anchor)
    target = invalid
    if direction > 0
        ' From a gap, the first show starting after the anchor.
        ref = m.anchor + 1
        if cur <> invalid then ref = cur.stop
        i = 0
        while i < progs.count()
            j = showEnd(progs, i)
            if progs[i].start >= ref
                target = { start: progs[i].start, stop: progs[j - 1].stop, prog: progs[i] }
                exit while
            end if
            i = j
        end while
    else
        ref = m.anchor
        if cur <> invalid then ref = cur.start
        i = 0
        while i < progs.count()
            if progs[i].start >= ref then exit while
            j = showEnd(progs, i)
            if progs[j - 1].stop <= ref then target = { start: progs[i].start, stop: progs[j - 1].stop, prog: progs[i] }
            i = j
        end while
    end if
    if target = invalid then return

    windowSec = m.WINDOW_MINUTES * 60
    newStart = m.windowStart
    if target.start >= m.windowStart + windowSec
        newStart = Int(target.start / 1800) * 1800
    else if target.stop <= m.windowStart
        newStart = Int((target.stop - 1) / 1800) * 1800 + 1800 - windowSec
    end if

    ' Anchor on the show's first visible second so Up/Down line up with it.
    m.anchor = target.start
    if m.anchor < newStart then m.anchor = newStart
    nowSec = nowEpoch()
    m.followNow = (target.start <= nowSec and nowSec < target.stop and nowSec >= newStart and nowSec < newStart + windowSec)
    if m.followNow then m.anchor = nowSec

    if newStart <> m.windowStart
        ' onWindowChange rebuilds the rows (with the new selTime) and, seeing
        ' its own move, leaves the anchor alone.
        m.internalWindow = newStart
        m.top.windowStart = newStart
    else
        m.rowPool[m.focusedRow].selTime = m.anchor
    end if
    fireFocusedProgram()
end sub

function focusedPrograms() as object
    ch = getFocusedChannel()
    if ch = invalid then return invalid
    if not m.programs.doesExist(ch.id) then return invalid
    return m.programs[ch.id]
end function

' Exclusive end index of the show starting at progs[i]. A run of short
' programmes is one cell in the guide (GuideRow's collapseShortPrograms, same
' 7-minute rule), so the cursor treats it as one show headed by its first entry.
function showEnd(progs as object, i as integer) as integer
    COLLAPSE_SECS = 420
    if (progs[i].stop - progs[i].start) >= COLLAPSE_SECS then return i + 1
    groupStop = progs[i].stop
    j = i + 1
    while j < progs.count()
        nxt = progs[j]
        if (nxt.stop - nxt.start) < COLLAPSE_SECS and nxt.start <= groupStop
            groupStop = nxt.stop
            j = j + 1
        else
            exit while
        end if
    end while
    return j
end function

' The show covering time t: { start, stop, prog }, or invalid for a gap.
function showAt(progs as object, t as integer) as object
    i = 0
    while i < progs.count()
        if progs[i].start > t then return invalid
        j = showEnd(progs, i)
        if t < progs[j - 1].stop then return { start: progs[i].start, stop: progs[j - 1].stop, prog: progs[i] }
        i = j
    end while
    return invalid
end function

function getFocusedChannel() as object
    chanIdx = m.topRowIdx + m.focusedRow
    if chanIdx < m.channels.count() then return m.channels[chanIdx]
    return invalid
end function

' The selected show's programme (the first one of a collapsed run), or invalid.
function getFocusedProgram() as object
    progs = focusedPrograms()
    if progs = invalid then return invalid
    show = showAt(progs, m.anchor)
    if show = invalid then return invalid
    return show.prog
end function

sub fireFocusedProgram()
    ch   = getFocusedChannel()
    prog = getFocusedProgram()
    if ch <> invalid
        m.firedProgStart = -1
        if prog <> invalid then m.firedProgStart = prog.start
        m.top.focusedProgram = {
            channel: ch,
            program: prog
        }
    end if
end sub
