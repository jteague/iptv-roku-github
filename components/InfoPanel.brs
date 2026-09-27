sub init()
    m.bg        = m.top.findNode("bg")
    m.chanName  = m.top.findNode("chanName")
    m.progTitle = m.top.findNode("progTitle")
    m.timeRange = m.top.findNode("timeRange")
    m.progDesc  = m.top.findNode("progDesc")
    m.descClip  = m.top.findNode("descClip")
    m.descAnim  = m.top.findNode("descAnim")
    m.descInterp = m.top.findNode("descInterp")
    m.DESC_SCROLL_PX_PER_SEC = 18
    m.DESC_PAUSE_SEC         = 3
    ' Don't animate a hidden panel (NowPlayingPanel is hidden most of the time).
    m.top.observeField("visible", "onVisibleChange")

    ' Badges (rating, episode, genres...) sit on the time-range line. Nodes are
    ' pooled; at most MAX_BADGES are ever created.
    m.MAX_BADGES = 7   ' rating, NEW, episode, year, 3 genres
    m.BADGE_H    = 28
    m.badgePool  = []

    ' Padding and the initial size come from the XML so this script serves both
    ' InfoPanel (resizable) and NowPlayingPanel (fixed 1920x210).
    m.padX = m.chanName.translation[0]
    m.padY = m.chanName.translation[1]

    ' NowPlayingPanel has a countdown ring in the top-right corner; the channel
    ' name and title stop short of it.
    m.titleRight = invalid
    countdown = m.top.findNode("countdown")
    if countdown <> invalid then m.titleRight = countdown.translation[0] - 24

    ' Programme artwork on the left; text shifts right while it is shown.
    ' Created here (not in XML) so both panels get it without duplicating markup.
    m.poster = m.top.createChild("Poster")
    m.poster.loadDisplayMode = "scaleToFit"
    m.poster.visible = false
    m.poster.observeField("loadStatus", "onPosterLoadStatus")
    m.posterUri = ""

    applyLayout(m.bg.width, m.bg.height)
end sub

' The text column only moves once the image is actually ready, so dead or
' slow artwork URLs never make the panel jump. A failed load clears the uri.
sub onPosterLoadStatus()
    status = m.poster.loadStatus
    if status = "ready"
        applyLayout(m.panelW, m.panelH)
    else if status = "failed"
        if m.posterUri <> ""
            m.posterUri = ""
            applyLayout(m.panelW, m.panelH)
        end if
    end if
end sub

' Only InfoPanel declares panelSize; NowPlayingPanel keeps its XML size.
sub onPanelSizeChange()
    sz = m.top.panelSize
    if sz = invalid then return
    applyLayout(sz.width, sz.height)
end sub

sub applyLayout(w as integer, h as integer)
    m.panelW = w
    m.panelH = h
    m.bg.width  = w
    m.bg.height = h

    ' Poster: 2:3, as tall as the panel allows, but never more than about a
    ' third of the text width so the description keeps room.
    textX = m.padX
    if m.posterUri <> "" and m.poster.uri <> m.posterUri
        ' New artwork: start loading; the "ready" callback re-runs this layout.
        m.poster.visible = false
        m.poster.uri = m.posterUri
    end if
    if m.posterUri <> "" and m.poster.loadStatus = "ready"
        posterH = h - 2 * m.padY
        posterW = Int(posterH * 2 / 3)
        maxW = Int((w - 2 * m.padX) * 0.35)
        if posterW > maxW
            posterW = maxW
            posterH = Int(posterW * 3 / 2)
        end if
        m.poster.width       = posterW
        m.poster.height      = posterH
        m.poster.loadWidth   = posterW
        m.poster.loadHeight  = posterH
        m.poster.translation = [m.padX, m.padY]
        m.poster.visible = true
        textX = m.padX + posterW + 20
    else
        m.poster.visible = false
        if m.posterUri = "" and m.poster.uri <> "" then m.poster.uri = ""
    end if
    m.textX = textX

    textW = w - textX - m.padX
    titleW = textW
    if m.titleRight <> invalid and m.titleRight - textX < titleW then titleW = m.titleRight - textX
    m.chanName.width  = titleW
    m.progTitle.maxWidth = titleW  ' ScrollingLabel marquees when text is wider
    m.timeRange.width = 0          ' auto-size so badges can follow the text
    m.progDesc.width  = textW
    m.chanName.translation  = [textX, m.chanName.translation[1]]
    m.progTitle.translation = [textX, m.progTitle.translation[1]]
    m.timeRange.translation = [textX, m.timeRange.translation[1]]
    m.descClip.translation  = [textX, m.descClip.translation[1]]

    ' Description gets whatever height is left below the time line. The Label
    ' lays out all its lines (numLines=0, no height); the group clips it and
    ' startDescScroll scrolls it when it overflows.
    descTop = m.descClip.translation[1]
    descH   = h - descTop - 10
    if descH < 0 then descH = 0
    m.descH = descH
    m.descClip.clippingRect = [0, 0, textW, descH]
    m.descClip.visible = (descH >= 26)

    layoutBadges()
    startDescScroll()
end sub

' Scroll the description when it is taller than its clip: hold at the top,
' glide to the bottom, hold, then loop back to the top.
sub startDescScroll()
    m.descAnim.control = "stop"
    m.progDesc.translation = [0, 0]
    if not m.descClip.visible or not m.top.visible or m.progDesc.text = "" then return
    overflow = m.progDesc.boundingRect().height - m.descH
    if overflow <= 0 then return

    scrollSec = overflow / m.DESC_SCROLL_PX_PER_SEC
    total     = m.DESC_PAUSE_SEC * 2 + scrollSec
    k1 = m.DESC_PAUSE_SEC / total
    k2 = (m.DESC_PAUSE_SEC + scrollSec) / total
    m.descInterp.key      = [0.0, k1, k2, 1.0]
    m.descInterp.keyValue = [[0, 0], [0, 0], [0, -overflow], [0, -overflow]]
    m.descAnim.duration   = total
    m.descAnim.control    = "start"
end sub

sub onVisibleChange()
    if m.top.visible
        startDescScroll()
    else
        m.descAnim.control = "stop"
    end if
end sub

sub onDataChange()
    fp = m.top.focusedProgram
    if fp = invalid then return

    ch   = fp.channel
    prog = fp.program

    m.chanName.text = ""
    if ch <> invalid then m.chanName.text = ch.name

    if prog = invalid
        m.progTitle.text = "No EPG data"
        m.timeRange.text = ""
        m.progDesc.text  = ""
        m.badges = []
        m.posterUri = ""
        applyLayout(m.panelW, m.panelH)
        return
    end if

    title = prog.title
    if progText(prog, "subtitle") <> "" then title = title + "  –  " + prog.subtitle
    m.progTitle.text = title
    m.progDesc.text  = prog.desc

    startStr = epochToTimeStr(prog.start)
    stopStr  = epochToTimeStr(prog.stop)
    m.timeRange.text = startStr + " – " + stopStr

    m.badges = badgesFor(prog)
    ' Poster presence moves the text column, so run the full layout.
    m.posterUri = progText(prog, "poster")
    applyLayout(m.panelW, m.panelH)
end sub

' Programme fields are optional; treat a missing key as "".
function progText(prog as object, key as string) as string
    if prog.doesExist(key)
        if prog[key] <> invalid then return prog[key]
    end if
    return ""
end function

' Ordered list of { text, color } for a programme; empty when the feed has none.
function badgesFor(prog as object) as object
    badges = []
    ' color = badge background, textColor = its label (dark on light badges).
    BEIGE = "0xF2E3BCFF"
    CHARCOAL = "0x414535FF"
    ' Dispatcharr is recording this one (MainScene markRecordings).
    if GetInterface(prog.rec, "ifBoolean") <> invalid and prog.rec then badges.push({ text: "REC", color: "0xD0463BFF", textColor: BEIGE })
    ' A reminder is set for it (MainScene markReminders).
    if GetInterface(prog.remind, "ifBoolean") <> invalid and prog.remind then badges.push({ text: "REMINDER", color: "0xC19875FF", textColor: CHARCOAL })
    if progText(prog, "rating") <> "" then badges.push({ text: prog.rating, color: "0xC19875FF", textColor: CHARCOAL })
    if prog.doesExist("isNew")
        if prog.isNew = true then badges.push({ text: "NEW", color: "0x618985FF", textColor: BEIGE })
    end if
    if progText(prog, "episode") <> "" then badges.push({ text: prog.episode, color: "0x4A4F3DFF", textColor: BEIGE })
    if progText(prog, "year") <> "" then badges.push({ text: prog.year, color: "0x4A4F3DFF", textColor: BEIGE })
    if prog.doesExist("genres")
        if prog.genres <> invalid
            for each g in prog.genres
                badges.push({ text: g, color: "0x96BBBBFF", textColor: CHARCOAL })
            end for
        end if
    end if
    return badges
end function

' Place badges after the time text, dropping any that would not fit the panel.
sub layoutBadges()
    if m.badges = invalid then m.badges = []
    x = m.textX
    if m.timeRange.text <> "" then x = x + m.timeRange.boundingRect().width + 16
    y = m.timeRange.translation[1] - 2
    used = 0
    for each badge in m.badges
        if used >= m.MAX_BADGES then exit for
        cell = badgeCell(used)
        cell.lbl.text  = badge.text
        cell.lbl.color = badge.textColor
        w = cell.lbl.boundingRect().width + 20
        if x + w > m.panelW - m.padX then exit for
        cell.bg.color       = badge.color
        cell.bg.width       = w
        cell.bg.translation = [x, y]
        cell.bg.visible     = true
        x = x + w + 8
        used = used + 1
    end for
    for i = used to m.badgePool.count() - 1
        m.badgePool[i].bg.visible = false
    end for
end sub

function badgeCell(i as integer) as object
    if i < m.badgePool.count() then return m.badgePool[i]
    bg = m.top.createChild("Rectangle")
    bg.height  = m.BADGE_H
    bg.visible = false
    lbl = bg.createChild("Label")
    lbl.font        = "font:SmallestBoldSystemFont"
    lbl.height      = m.BADGE_H
    lbl.vertAlign   = "center"
    lbl.translation = [10, 3]   ' nudged down: system fonts sit high in a centred 28px box
    cell = { bg: bg, lbl: lbl }
    m.badgePool.push(cell)
    return cell
end function
