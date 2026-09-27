sub init()
    m.guideGrid  = m.top.findNode("guideGrid")
    m.infoPanel  = m.top.findNode("infoPanel")
    m.pipVideo   = m.top.findNode("pipVideo")
    m.toastBg    = m.top.findNode("toastBg")
    m.toastLabel = m.top.findNode("toastLabel")
    m.toastTimer = invalid

    m.guideGrid.observeField("focusedProgram",  "onFocusedProgram")
    m.guideGrid.observeField("selectedChannel", "onSelectedChannel")

    ' The guide is anchored to the bottom of the canvas; its height comes from
    ' the row-count setting. The info panel and PIP share the space above it.
    ' All numbers come from guideGeometry() so GuideGrid and this scene agree.
    geo = guideGeometry(readSettings())
    m.guideGrid.translation = [0, geo.topH]
    m.pipVideo.width        = geo.pipW
    m.pipVideo.height       = geo.pipH
    m.pipVideo.translation  = [geo.pipX, geo.pipY]
    m.infoPanel.panelSize   = { width: geo.infoW, height: geo.topH }
    m.infoW = geo.infoW

    ' Programme filters ("what's on now", ProgramFilters.brs). guideData always
    ' carries every channel; the grid gets only the channels whose current show
    ' matches the active filter. MainScene keeps the choice in filterKey across
    ' guide rebuilds ("" = all channels). filterTimer re-checks once a minute so
    ' the list follows shows starting and ending.
    m.filterPill      = m.top.findNode("filterPill")
    m.filterPillLabel = m.top.findNode("filterPillLabel")
    m.filterPicker    = m.top.findNode("filterPicker")
    m.filterPicker.translation = [0, geo.topH]
    m.filterPicker.layout = { rows: geo.rows, rowHeight: geo.rowHeight, headerH: geo.headerH, width: 560 }
    m.filterPicker.observeField("chosen", "onFilterChosen")
    m.filterTimer = m.top.findNode("filterTimer")
    m.filterTimer.observeField("fire", "onFilterTick")
    m.filterTimer.control = "start"
    m.filters     = compileProgramFilters()
    m.skipRe      = placeholderRegex()
    m.allChannels = []
    m.programs    = {}
    m.shownIds    = ""

    m.guideGrid.windowStart = currentHalfHour()

    ' Long-press OK opens the channel menu, so OK selects on release instead of
    ' on press: okTimer fires while the button is still down for a long press.
    m.channelMenu = m.top.findNode("channelMenu")
    m.channelMenu.observeField("chosen", "onMenuChosen")
    m.okTimer = m.top.findNode("okTimer")
    m.okTimer.observeField("fire", "onOkHeld")
    m.okDown = false
    m.okLong = false
    m.menuChannel = invalid
    m.menuProgram = invalid
    m.dvrPrefixes = ""   ' "|p4_|": sources with a Dispatcharr API key (guideData.dvr)
    m.favIds      = "|"  ' "|p4_12|…": favorite channel ids (guideData.favs)

    ' The grid's clock / now-line timer only needs to run while the guide is
    ' on screen; MainScene toggles visible when the player takes over.
    m.top.observeField("visible", "onVisibleChange")
end sub

sub onVisibleChange()
    m.guideGrid.running = m.top.visible
    if m.top.visible
        ' Back from the player: shows may have ended while it was up.
        onFilterTick()
        m.filterTimer.control = "start"
    else
        m.filterTimer.control = "stop"
        m.filterPicker.visible = false
        m.channelMenu.visible = false
        m.okTimer.control = "stop"
        m.okDown = false
    end if
end sub

' Key events arrive via onKeyEvent below (MainScene focuses this scene) and are
' forwarded to the grid through its keyEvent field.
sub onDataChange()
    data = m.top.guideData
    if data = invalid then return
    if data.channels <> invalid then m.allChannels = data.channels
    if data.programs <> invalid then m.programs = data.programs
    if data.dvr <> invalid then m.dvrPrefixes = data.dvr
    if data.favs <> invalid then m.favIds = data.favs
    applyFilter(true)
end sub

' ── Programme filters ────────────────────────────────────────────────────────

function currentProgram(ch as object, nowSec as integer) as dynamic
    if not m.programs.doesExist(ch.id) then return invalid
    for each prog in m.programs[ch.id]
        if prog.start > nowSec then return invalid
        if nowSec < prog.stop then return prog
    end for
    return invalid
end function

' "favorites" is not a programme filter: it keeps the favorite channels
' whatever is on (filterByKey returns invalid for it).
function isFavorite(ch as object) as boolean
    return Instr(1, m.favIds, "|" + ch.id + "|") > 0
end function

function favoriteChannels() as object
    result = []
    for each ch in m.allChannels
        if isFavorite(ch) then result.push(ch)
    end for
    return result
end function

' Channels the filter key keeps; invalid for "" (every channel) or an unknown key.
function channelsForKey(key as string) as dynamic
    if key = "favorites" then return favoriteChannels()
    f = filterByKey(key)
    if f = invalid then return invalid
    return matchingChannels(f, currentPrograms())
end function

function filterLabel(key as string) as string
    if key = "favorites" then return "Favorites"
    f = filterByKey(key)
    if f = invalid then return ""
    return f.label
end function

function filterByKey(key as string) as dynamic
    for each f in m.filters
        if f.key = key then return f
    end for
    return invalid
end function

' Each channel's show on now (invalid for none), in m.allChannels order. Found
' once and shared when several filters are checked (the picker counts them all).
function currentPrograms() as object
    nowSec = nowEpoch()
    result = []
    for each ch in m.allChannels
        result.push(currentProgram(ch, nowSec))
    end for
    return result
end function

function matchingChannels(f as object, current as object) as object
    result = []
    for i = 0 to m.allChannels.count() - 1
        ch = m.allChannels[i]
        if programMatchesFilter(f, ch, current[i], m.skipRe) then result.push(ch)
    end for
    return result
end function

' Hand the grid the active filter's channels. force: push even when the channel
' list is unchanged (new guide data); the minute tick only pushes on a change.
' When nothing matches any more (the game ended) the guide goes back to every
' channel and the filter is dropped.
sub applyFilter(force as boolean)
    channels = m.allChannels
    key = m.top.filterKey
    if key <> ""
        matched = channelsForKey(key)
        if matched <> invalid and matched.count() > 0
            channels = matched
        else
            if key = "favorites"
                showToast("No favorites left. Showing all channels.")
            else if matched <> invalid
                showToast("No " + filterLabel(key) + " on now. Showing all channels.")
            end if
            m.top.filterKey = ""
        end if
    end if
    ids = ""
    for each ch in channels
        ids = ids + ch.id + "|"
    end for
    if force or ids <> m.shownIds
        m.shownIds = ids
        m.guideGrid.guideData = { channels: channels, programs: m.programs }
    end if
    updateFilterPill()
end sub

sub onFilterTick()
    if m.top.filterKey <> "" then applyFilter(false)
end sub

sub updateFilterPill()
    key = m.top.filterKey
    label = "All channels"
    if key = "favorites"
        label = "Favorites"
    else if filterByKey(key) <> invalid
        label = filterLabel(key) + " on now"
    end if
    m.filterPillLabel.text  = label
    m.filterPillLabel.width = 0
    textW = Int(m.filterPillLabel.boundingRect().width)
    if textW > 400 then textW = 400
    m.filterPillLabel.width = textW
    pillW = textW + 32
    x = m.infoW - pillW - 16
    m.filterPill.width = pillW
    m.filterPill.translation      = [x, 12]
    m.filterPillLabel.translation = [x + 16, 12]
end sub

' Counts are what matches right now, so an empty filter shows 0 before it is picked.
sub openFilterPicker()
    items = [{ key: "", label: "All channels", count: m.allChannels.count() }]
    items.push({ key: "favorites", label: "Favorites", count: favoriteChannels().count() })
    current = currentPrograms()
    for each f in m.filters
        items.push({ key: f.key, label: f.label, count: matchingChannels(f, current).count() })
    end for
    m.filterPicker.data = { items: items, active: m.top.filterKey }
    m.filterPicker.visible = true
end sub

sub onFilterChosen()
    key = m.filterPicker.chosen
    matched = channelsForKey(key)
    if matched <> invalid and matched.count() = 0
        if key = "favorites"
            showToast("No favorites yet. Hold OK on a channel to add one.")
        else
            showToast("No " + filterLabel(key) + " on right now.")
        end if
        return
    end if

    prevId = ""
    fp = m.guideGrid.focusedProgram
    if fp <> invalid and fp.channel <> invalid then prevId = fp.channel.id
    m.top.filterKey = key
    applyFilter(true)
    ' The grid keeps the focused channel when it is still listed; otherwise
    ' start at the top rather than at a clamped row index.
    if prevId = "" or Instr(1, "|" + m.shownIds, "|" + prevId + "|") > 0 then return
    firstId = Left(m.shownIds, Instr(1, m.shownIds, "|") - 1)
    if firstId <> "" then m.guideGrid.scrollToChannelId = firstId
end sub

' ── Long-press channel menu ──────────────────────────────────────────────────

sub onOkHeld()
    if not m.okDown then return
    m.okLong = true
    openChannelMenu()
end sub

sub openChannelMenu()
    fp = m.guideGrid.focusedProgram
    if fp = invalid or fp.channel = invalid then return
    ch = fp.channel
    m.menuChannel = ch
    m.menuProgram = fp.program
    subtitle = ""
    if ch.number <> "" then subtitle = "Ch " + ch.number
    if fp.program <> invalid
        if subtitle <> "" then subtitle = subtitle + "  ·  "
        subtitle = subtitle + fp.program.title
    end if
    items = []
    if canRecord(ch, fp.program) then items.push({ key: "record", label: "Record…" })
    ' Reminders are for shows that haven't started yet.
    if fp.program <> invalid and fp.program.start > nowEpoch()
        if isReminded(fp.program)
            items.push({ key: "remind_cancel", label: "Cancel Reminder" })
        else
            items.push({ key: "remind_set", label: "Set Reminder" })
        end if
    end if
    if isFavorite(ch)
        items.push({ key: "fav_remove", label: "Remove from Favorites" })
    else
        items.push({ key: "fav_add", label: "Add to Favorites" })
    end if
    items.push({ key: "hide", label: "Hide Channel" })
    items.push({ key: "filter", label: "Filter…" })
    showChannelMenu(ch.name, subtitle, items)
end sub

' A show that hasn't ended, on a source whose Dispatcharr API key is set.
function canRecord(ch as object, prog as dynamic) as boolean
    if prog = invalid or prog.stop <= nowEpoch() then return false
    return Instr(1, m.dvrPrefixes, "|" + idPrefixOf(ch.id) + "|") > 0
end function

' prog.remind is set by MainScene (markReminders).
function isReminded(prog as object) as boolean
    return GetInterface(prog.remind, "ifBoolean") <> invalid and prog.remind
end function

' Second menu after "Record…": this airing, or a series rule.
sub openRecordMenu()
    prog = m.menuProgram
    subtitle = m.menuChannel.name + "  ·  " + epochToDateStr(prog.start) + " " + epochToTimeStr(prog.start)
    items = [
        { key: "record_once", label: "Record This Episode" },
        { key: "record_all",  label: "Record Series: All Episodes" },
        { key: "record_new",  label: "Record Series: New Episodes" }
    ]
    showChannelMenu(prog.title, subtitle, items)
end sub

sub showChannelMenu(title as string, subtitle as string, items as object)
    m.channelMenu.data = { title: title, subtitle: subtitle, items: items }
    height = 108 + items.count() * 64 + 16
    m.channelMenu.translation = [640, Int((1080 - height) / 2)]
    m.channelMenu.visible = true
end sub

sub onMenuChosen()
    ch = m.menuChannel
    if ch = invalid then return
    action = m.channelMenu.chosen
    if action = "record"
        openRecordMenu()
        return
    end if
    m.menuChannel = invalid
    ' Filter… is the D-pad-only route to the picker (Replay is the shortcut).
    if action = "filter"
        m.menuProgram = invalid
        openFilterPicker()
        return
    end if
    m.top.menuAction = { action: action, channel: ch, program: m.menuProgram }
    m.menuProgram = invalid
end sub

sub onWindowStartChange()
    if m.top.windowStart > 0
        m.guideGrid.windowStart = m.top.windowStart
    end if
end sub

sub onCurrentChannelChange()
    ch = m.top.currentChannel
    if ch = invalid or ch.streamUrl = ""
        m.pipVideo.control = "stop"
        m.pipVideo.visible = false
    else
        startPip(ch.streamUrl)
    end if
end sub

sub startPip(streamUrl as string)
    content = CreateObject("roSGNode", "ContentNode")
    content.url = streamUrl
    if Instr(LCase(streamUrl), ".m3u8") > 0
        content.streamFormat = "hls"
    else
        ' Live IPTV/tuner streams that aren't HLS (e.g. HDHomeRun's raw tuner
        ' output) are MPEG-TS, not an MP4 container.
        content.streamFormat = "ts"
    end if
    m.pipVideo.content = content
    m.pipVideo.control = "play"
    m.pipVideo.visible = true
end sub

sub onScrollToChannelId()
    m.guideGrid.scrollToChannelId = m.top.scrollToChannelId
end sub

sub onFocusedProgram()
    m.infoPanel.focusedProgram = m.guideGrid.focusedProgram
end sub

sub onSelectedChannel()
    ch = m.guideGrid.selectedChannel
    if ch <> invalid then m.top.selectedChannel = ch
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    ' OK down started okTimer; OK up before it fired is a normal select. Repeats
    ' while held are swallowed. A missed OK up is cleared by the next other key.
    if key = "OK" and m.okDown
        if not press
            m.okDown = false
            m.okTimer.control = "stop"
            if not m.okLong then m.guideGrid.keyEvent = { key: "OK" }
        end if
        return true
    end if
    if not press then return false
    m.okDown = false
    if m.channelMenu.visible
        m.channelMenu.keyEvent = { key: key }
        return true
    end if
    if m.filterPicker.visible
        m.filterPicker.keyEvent = { key: key }
        return true
    end if
    if key = "replay"
        openFilterPicker()
        return true
    end if
    if key = "back"
        if m.top.currentChannel <> invalid and m.top.currentChannel.streamUrl <> ""
            m.top.action = "backToPlayer"
            return true
        end if
        return false
    end if
    if key = "options"
        m.top.action = "openSettings"
        return true
    end if
    if key = "OK"
        m.okDown = true
        m.okLong = false
        m.okTimer.control = "start"
        return true
    end if
    if key = "up" or key = "down" or key = "left" or key = "right" or key = "play" or key = "fastforward" or key = "rewind"
        m.guideGrid.keyEvent = { key: key }
        return true
    end if
    return false
end function

sub showToast(msg as string)
    m.toastLabel.text  = msg
    m.toastBg.visible  = true
    m.toastLabel.visible = true
    ' Auto-hide after 4 seconds using a one-shot timer.
    if m.toastTimer <> invalid
        m.toastTimer.control = "stop"
        m.top.removeChild(m.toastTimer)
        m.toastTimer = invalid
    end if
    m.toastTimer = m.top.createChild("Timer")
    m.toastTimer.duration = 4
    m.toastTimer.repeat = false
    m.toastTimer.observeField("fire", "hideToast")
    m.toastTimer.control = "start"
end sub

sub hideToast()
    m.toastBg.visible    = false
    m.toastLabel.visible = false
end sub
