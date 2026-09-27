sub init()
    ' Fixed row geometry lives in GuideRow.xml (58px rows, 40px logo). The time
    ' window is a placeholder here: GuideGrid sets the layout field right after
    ' creating the row and before any rowData arrives.
    m.PROGRAM_AREA_W = 1720
    m.ROW_HEIGHT     = 58
    m.WINDOW_MINUTES = 240
    m.PX_PER_MIN     = m.PROGRAM_AREA_W / m.WINDOW_MINUTES
    m.CELL_FONT      = "font:SmallSystemFont"
    m.PROGRAM_COLOR  = "0x4A4F3DFF"
    m.EMPTY_COLOR    = "0x2F3227FF"
    m.SELECTED_COLOR = "0x618985FF"
    m.REC_COLOR      = "0xD0463BFF"   ' DVR red, the one colour outside the palette

    m.cellContainer = m.top.findNode("cellContainer")
    m.logo          = m.top.findNode("logo")
    m.chanName      = m.top.findNode("chanName")

    ' Cell nodes are pooled and reused across rebuilds. Creating nodes is the
    ' expensive part on Roku; updating fields on existing ones is cheap.
    m.cellPool  = []
    m.cellsUsed = 0
    m.selCell   = invalid
end sub

sub onLayoutChange()
    lay = m.top.layout
    if lay = invalid then return
    m.WINDOW_MINUTES = lay.windowMinutes
    m.PX_PER_MIN     = lay.pxPerMin
end sub

sub onRowDataChange()
    data = m.top.rowData
    if data = invalid or data.channel = invalid then return

    m.logo.uri      = data.channel.logoUrl
    m.chanName.text = data.channel.name

    buildCells(data.programs, data.windowStart)
    onSelTimeChange()
end sub

' Highlight the cell (programme or gap) whose time span contains selTime.
sub onSelTimeChange()
    if m.selCell <> invalid
        m.selCell.bg.color = m.selCell.baseColor
        m.selCell = invalid
    end if
    t = m.top.selTime
    if t < 0 then return
    for i = 0 to m.cellsUsed - 1
        cell = m.cellPool[i]
        if cell.tStart <= t and t < cell.tStop
            cell.bg.color = m.SELECTED_COLOR
            m.selCell = cell
            return
        end if
    end for
end sub

sub buildCells(programs as object, windowStart as integer)
    m.cellsUsed = 0
    m.selCell   = invalid
    windowEnd = windowStart + m.WINDOW_MINUTES * 60

    ' programs are sorted by start (see XmltvParser); keep only those that
    ' overlap the window so nothing is laid out off-screen.
    inWindow = []
    if programs <> invalid
        for each prog in programs
            if prog.start >= windowEnd then exit for
            if prog.stop > windowStart then inWindow.push(prog)
        end for
    end if

    if inWindow.count() = 0
        placeEmptyCell(0, m.PROGRAM_AREA_W, windowStart, windowEnd)
        hideUnusedCells()
        return
    end if

    cursor = windowStart
    for each prog in collapseShortPrograms(inWindow)
        pStart = prog.start
        pStop  = prog.stop
        if pStart < windowStart then pStart = windowStart
        if pStop  > windowEnd   then pStop  = windowEnd

        if pStart > cursor
            gapW = Int((pStart - cursor) / 60 * m.PX_PER_MIN)
            if gapW > 0 then placeEmptyCell(Int((cursor - windowStart) / 60 * m.PX_PER_MIN), gapW, cursor, pStart)
        end if

        if pStop > pStart
            xPos = Int((pStart - windowStart) / 60 * m.PX_PER_MIN)
            w    = Int((pStop  - pStart)       / 60 * m.PX_PER_MIN)
            if w < 2 then w = 2
            placeProgramCell(xPos, w, prog.title, pStart, pStop, isRecorded(prog))
        end if

        cursor = pStop
    end for

    if cursor < windowEnd
        xPos = Int((cursor - windowStart) / 60 * m.PX_PER_MIN)
        w    = m.PROGRAM_AREA_W - xPos
        if w > 0 then placeEmptyCell(xPos, w, cursor, windowEnd)
    end if

    hideUnusedCells()
end sub

' Return the next pooled cell, creating one if the pool is exhausted.
function nextCell() as object
    if m.cellsUsed < m.cellPool.count()
        cell = m.cellPool[m.cellsUsed]
    else
        bg = m.cellContainer.createChild("Rectangle")
        bg.height = m.ROW_HEIGHT - 2

        lbl = bg.createChild("Label")
        lbl.color       = "0xF2E3BCFF"
        lbl.font        = m.CELL_FONT
        lbl.height      = m.ROW_HEIGHT - 2
        lbl.vertAlign   = "center"
        lbl.translation = [4, 0]

        ' Recording dot (white image tinted red), left of the title.
        dot = bg.createChild("Poster")
        dot.uri         = "pkg:/images/rec_dot.png"
        dot.width       = 16
        dot.height      = 16
        dot.blendColor  = m.REC_COLOR
        dot.translation = [8, Int((m.ROW_HEIGHT - 2 - 16) / 2)]
        dot.visible     = false

        cell = { bg: bg, lbl: lbl, dot: dot, tStart: 0, tStop: 0, baseColor: m.EMPTY_COLOR }
        m.cellPool.push(cell)
    end if
    m.cellsUsed = m.cellsUsed + 1
    cell.bg.visible = true
    return cell
end function

' tStart/tStop: the cell's time span (clamped to the window), for selTime lookups.
' rec: a Dispatcharr recording covers it (red dot, when the cell is wide enough).
sub placeProgramCell(x as integer, w as integer, title as string, tStart as integer, tStop as integer, rec as boolean)
    cell = nextCell()
    cell.tStart    = tStart
    cell.tStop     = tStop
    cell.baseColor = m.PROGRAM_COLOR
    cell.bg.color       = m.PROGRAM_COLOR
    cell.bg.width       = w - 2
    cell.bg.translation = [x + 1, 1]
    textX = 4
    cell.dot.visible = rec and w >= 40
    if cell.dot.visible then textX = 30
    cell.lbl.text         = title
    cell.lbl.translation  = [textX, 0]
    cell.lbl.width        = w - textX - 4
    cell.lbl.clippingRect = [0, 0, w - textX - 4, m.ROW_HEIGHT - 2]
    cell.lbl.visible      = true
end sub

sub placeEmptyCell(x as integer, w as integer, tStart as integer, tStop as integer)
    cell = nextCell()
    cell.tStart    = tStart
    cell.tStop     = tStop
    cell.baseColor = m.EMPTY_COLOR
    cell.bg.color       = m.EMPTY_COLOR
    cell.bg.width       = w - 1
    cell.bg.translation = [x, 1]
    cell.lbl.visible    = false
    cell.dot.visible    = false
end sub

sub hideUnusedCells()
    for i = m.cellsUsed to m.cellPool.count() - 1
        m.cellPool[i].bg.visible = false
    end for
end sub

' Merge runs of very short programmes (e.g. interstitials) into one cell so the
' row does not fill with unreadable slivers. Input must be sorted by start.
function collapseShortPrograms(sorted as object) as object
    COLLAPSE_SECS = 420
    result = []
    i = 0
    while i < sorted.count()
        prog = sorted[i]
        if (prog.stop - prog.start) < COLLAPSE_SECS
            groupStart = prog.start
            groupStop  = prog.stop
            groupTitle = prog.title
            j = i + 1
            while j < sorted.count()
                nxt = sorted[j]
                if (nxt.stop - nxt.start) < COLLAPSE_SECS and nxt.start <= groupStop
                    groupStop = nxt.stop
                    j = j + 1
                else
                    exit while
                end if
            end while
            result.push({start: groupStart, stop: groupStop, title: groupTitle, rec: isRecorded(prog)})
            i = j
        else
            result.push(prog)
            i = i + 1
        end if
    end while
    return result
end function

' prog.rec is set by MainScene (markRecordings) only on programmes a recording
' touched, so it may be missing.
function isRecorded(prog as object) as boolean
    return GetInterface(prog.rec, "ifBoolean") <> invalid and prog.rec
end function
