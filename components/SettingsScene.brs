sub init()
    m.nameInput     = m.top.findNode("nameInput")
    m.m3uInput      = m.top.findNode("m3uInput")
    m.epgInput      = m.top.findNode("epgInput")
    m.apiKeyInput   = m.top.findNode("apiKeyInput")
    m.intervalInput = m.top.findNode("intervalInput")
    m.errorLabel    = m.top.findNode("errorLabel")

    ' Left nav pages. Each page lists its focusable rows top to bottom; a row is
    ' a list of items left to right. The IPTV Sources rows are built from the
    ' source list and the Hidden Channels rows from the hidden list (currentRows).
    ' The footer row (Save / Refresh Now) is shared and
    ' appended after the page rows.
    m.pages = [
        { group: "pageSources", rows: [] },
        { group: "pageGuide",   rows: [["guideHoursChooser"], ["guideRowsChooser"]] },
        { group: "pageOptions", rows: [["intervalInput"], ["launchChooser"]] },
        { group: "pageRemote",  rows: [] },
        { group: "pageHidden",  rows: [] },
        { group: "pageAbout",   rows: [] }
    ]
    m.footerRow = ["saveBtn", "refreshBtn"]
    m.editorRows = [["nameInput"], ["m3uInput"], ["epgInput"], ["apiKeyInput"], ["enabledChooser"], ["tsChooser"], ["doneBtn", "removeBtn"]]

    ' Choosers: Left/Right/OK change the value among `values`.
    '   pills:   { ring, pill: id prefix of <prefix>N / <prefix>LabelN, values, idx }
    '   stepper: { ring, valueLabel: id, suffix, decLabel, incLabel, values, idx }
    rowValues = []
    for n = 5 to 15
        rowValues.push(n.toStr())
    end for
    m.choosers = {
        guideHoursChooser: { ring: "guideHoursRing", pill: "guideHoursPill", values: ["2", "3", "4"], idx: 2 },
        guideRowsChooser:  { ring: "guideRowsRing", valueLabel: "guideRowsValue", suffix: " rows", decLabel: "guideRowsDec", incLabel: "guideRowsInc", values: rowValues, idx: 8 },
        enabledChooser:    { ring: "enabledRing", pill: "enabledPill", values: ["on", "off"], idx: 0 },
        tsChooser:         { ring: "tsRing", pill: "tsPill", values: ["off", "on"], idx: 0 },
        launchChooser:     { ring: "launchRing", pill: "launchPill", values: ["guide", "resume"], idx: 0 }
    }

    ' Text inputs: name -> border rect that lights up on focus.
    m.inputBoxes = {
        nameInput: "nameBox", m3uInput: "m3uBox", epgInput: "epgBox", apiKeyInput: "apiKeyBox",
        intervalInput: "intervalBox"
    }
    ' Titles shown on the keyboard dialog when editing each input.
    m.inputTitles = {
        nameInput:     "Source name",
        m3uInput:      "M3U playlist URL",
        epgInput:      "XMLTV EPG URL",
        apiKeyInput:   "Dispatcharr API key",
        intervalInput: "Refresh interval (minutes)"
    }
    m.kbDialog = invalid
    m.kbTarget = ""
    m.unsavedDlg    = invalid   ' Back with edits pending: Save / Discard / Keep Editing
    m.unsavedChoice = -1
    ' Buttons: name -> [normal bg, focused bg, normal text, focused text].
    ' Focused is always Ash Grey with charcoal text; normal varies by role.
    m.buttonColors = {
        saveBtn:    ["0x618985FF", "0x96BBBBFF", "0xF2E3BCFF", "0x414535FF"],
        refreshBtn: ["0x414535FF", "0x96BBBBFF", "0xF2E3BCFF", "0x414535FF"],
        unhideAllBtn: ["0xC19875FF", "0x96BBBBFF", "0x414535FF", "0x414535FF"],
        addBtn:     ["0x414535FF", "0x96BBBBFF", "0xF2E3BCFF", "0x414535FF"],
        doneBtn:    ["0x414535FF", "0x96BBBBFF", "0xF2E3BCFF", "0x414535FF"],
        removeBtn:  ["0xC19875FF", "0x96BBBBFF", "0x414535FF", "0x414535FF"]
    }

    m.pageIdx = 0
    m.area    = "nav"   ' "nav" | "content"
    m.rowIdx  = 0
    m.colIdx  = 0

    settings = readSettings()
    ' Working copy of the source list; written to the registry only on Save.
    m.sources      = settings.sources
    m.nextSourceId = settings.nextSourceId
    m.editIdx      = -1      ' source open in the editor, -1 = showing the list
    m.editIsNew    = false   ' just added: Back with no M3U URL discards it
    m.listTop      = 0       ' first source shown (the list scrolls)
    m.maxListRows  = 6
    m.sourceSlots  = []      ' pooled row nodes, see sourceSlot()

    ' Hidden channels ({ id, name, num, kind, daysLeft }, hiddenChannelList).
    ' Unlike the rest of Settings these apply to the registry at once, not on Save;
    ' MainScene refilters its channels whenever Settings closes.
    m.hidden        = hiddenChannelList()
    m.hiddenTop     = 0
    m.maxHiddenRows = 7
    m.hiddenSlots   = []
    ' Retry of a codec-hidden channel (openRetry): { id, idx, url, attempts, done }.
    m.retry         = invalid
    m.retryVideo    = m.top.findNode("retryVideo")
    m.retryTimer    = m.top.findNode("retryTimer")
    m.retryVideo.observeField("state", "onRetryVideoState")
    m.retryTimer.observeField("fire", "onRetryTimer")

    m.intervalInput.text = settings.refreshIntervalMin.toStr()
    setChooserValue("guideHoursChooser", settings.guideHours.toStr())
    setChooserValue("guideRowsChooser", settings.guideRows.toStr())
    setChooserValue("launchChooser", settings.onLaunch)

    renderRemote()
    showPage(0)
    focusNav()
end sub

' Remote page: fixed key / action rows. Keep in step with the key handlers in
' GuideScene, GuideGrid, PlayerScene, ChannelMenu and FilterPicker.
sub renderRemote()
    addKeyRows("remoteGuide", [
        ["Up / Down", "Move between channels"],
        ["Left / Right", "Previous / next show"],
        ["Rewind / Fwd", "Page up / page down"],
        ["OK", "Watch fullscreen"],
        ["Hold OK", "Channel menu"],
        ["Replay", "Filter the guide"],
        ["*", "Settings"],
        ["Back", "Exit or keep watching"]
    ])
    addKeyRows("remotePlayer", [
        ["Up", "What's on now"],
        ["Down", "Previous channel"],
        ["Back", "Back to the guide"],
        ["*", "Roku captions and audio"]
    ])
    addKeyRows("remoteMenus", [
        ["OK", "Choose"],
        ["Back", "Close or go back"]
    ])
end sub

sub addKeyRows(groupId as string, rows as object)
    group = m.top.findNode(groupId)
    for i = 0 to rows.count() - 1
        keyLabel = group.createChild("Label")
        keyLabel.font = "font:SmallBoldSystemFont"
        keyLabel.color = "0xF2E3BCFF"
        keyLabel.width = 210
        keyLabel.translation = [0, i * 46]
        keyLabel.text = rows[i][0]
        actionLabel = group.createChild("Label")
        actionLabel.font = "font:SmallSystemFont"
        actionLabel.color = "0x96BBBBFF"
        actionLabel.width = 400
        actionLabel.translation = [220, i * 46]
        actionLabel.text = rows[i][1]
    end for
end sub

' ── Nav / page switching ─────────────────────────────────────────────────────

sub showPage(idx as integer)
    m.pageIdx = idx
    for i = 0 to m.pages.count() - 1
        m.top.findNode(m.pages[i].group).visible = (i = idx)
    end for
    ' The source editor stands in for the source list while it is open.
    if idx = 0 and m.editIdx >= 0
        m.top.findNode("pageSources").visible = false
        m.top.findNode("pageSourceEdit").visible = true
    else
        m.top.findNode("pageSourceEdit").visible = false
    end if
    if idx = 0 and m.editIdx < 0 then renderSourceList()
    if idx = 4 then renderHiddenList()
    if idx = 5 then renderAbout()
    styleNav()
end sub

sub styleNav()
    for i = 0 to m.pages.count() - 1
        bg    = m.top.findNode("navBg" + i.toStr())
        bar   = m.top.findNode("navBar" + i.toStr())
        label = m.top.findNode("navLabel" + i.toStr())
        if i = m.pageIdx
            if m.area = "nav"
                bg.color = "0x618985FF"
                bar.visible = false
            else
                bg.color = "0x414535FF"
                bar.visible = true
            end if
            label.color = "0xF2E3BCFF"
        else
            bg.color = "0x00000000"
            bar.visible = false
            label.color = "0x96BBBBFF"
        end if
    end for
end sub

sub focusNav()
    m.area = "nav"
    clearItemStyle()
    renderSourceList()
    renderHiddenList()
    m.top.setFocus(true)
    styleNav()
end sub

' Rows focusable on the current page, top to bottom: page rows then footer.
function currentRows() as object
    rows = []
    if m.pageIdx = 0 and m.editIdx >= 0
        rows.append(m.editorRows)
    else if m.pageIdx = 0
        for i = 0 to m.sources.count() - 1
            rows.push(["src", "srcUp", "srcDown"])
        end for
        rows.push(["addBtn"])
    else if m.pageIdx = 4
        for each e in m.hidden
            if e.kind = "codec"
                rows.push(["hidUnhide", "hidRetry", "hidPerm"])
            else
                rows.push(["hidUnhide"])
            end if
        end for
        if m.hidden.count() > 0 then rows.push(["unhideAllBtn"])
    else
        rows.append(m.pages[m.pageIdx].rows)
    end if
    rows.push(m.footerRow)
    return rows
end function

' True when the focused row is a source in the list; rowIdx is its index.
function onSourceRow() as boolean
    return m.area = "content" and m.pageIdx = 0 and m.editIdx < 0 and m.rowIdx < m.sources.count()
end function

' True when the focused row is a hidden channel; rowIdx is its index in m.hidden.
function onHiddenRow() as boolean
    return m.area = "content" and m.pageIdx = 4 and m.rowIdx < m.hidden.count()
end function

' ── Content focus ────────────────────────────────────────────────────────────

sub focusItem(rowIdx as integer, colIdx as integer)
    rows = currentRows()
    if rowIdx < 0 then rowIdx = 0
    if rowIdx >= rows.count() then rowIdx = rows.count() - 1
    if colIdx >= rows[rowIdx].count() then colIdx = rows[rowIdx].count() - 1
    if colIdx < 0 then colIdx = 0
    m.area   = "content"
    m.rowIdx = rowIdx
    m.colIdx = colIdx
    clearItemStyle()
    name = rows[rowIdx][colIdx]
    if onSourceRow() or onHiddenRow()
        ' styled by renderSourceList / renderHiddenList
    else if m.inputBoxes[name] <> invalid
        m.top.findNode(m.inputBoxes[name]).color = "0x96BBBBFF"
    else if m.choosers[name] <> invalid
        m.top.findNode(m.choosers[name].ring).color = "0x96BBBBFF"
    else
        m.top.findNode(name).color = m.buttonColors[name][1]
        m.top.findNode(name + "Label").color = m.buttonColors[name][3]
    end if
    if m.pageIdx = 0 and m.editIdx < 0
        ' Keep the focused source (or, on Add, the end of the list) on screen.
        target = rowIdx
        if target > m.sources.count() - 1 then target = m.sources.count() - 1
        if target < m.listTop then m.listTop = target
        if target >= m.listTop + m.maxListRows then m.listTop = target - m.maxListRows + 1
        renderSourceList()
    else if m.pageIdx = 4
        target = rowIdx
        if target > m.hidden.count() - 1 then target = m.hidden.count() - 1
        if target < m.hiddenTop then m.hiddenTop = target
        if target >= m.hiddenTop + m.maxHiddenRows then m.hiddenTop = target - m.maxHiddenRows + 1
        renderHiddenList()
    end if
    ' Focus stays on the scene. A focused TextEditBox swallows the direction
    ' keys (Down clears its text, Left/Right move its cursor) so the scene
    ' never sees them; the border highlight is the focus indicator instead.
    m.top.setFocus(true)
    styleNav()
end sub

sub clearItemStyle()
    for each name in m.inputBoxes
        m.top.findNode(m.inputBoxes[name]).color = "0x414535FF"
    end for
    for each name in m.buttonColors
        m.top.findNode(name).color = m.buttonColors[name][0]
        m.top.findNode(name + "Label").color = m.buttonColors[name][2]
    end for
    for each name in m.choosers
        m.top.findNode(m.choosers[name].ring).color = "0x00000000"
    end for
end sub

' ── Source list ──────────────────────────────────────────────────────────────

' Pooled row nodes for the visible part of the source list, created on demand.
function sourceSlot(i as integer) as object
    while m.sourceSlots.count() <= i
        list = m.top.findNode("sourceList")
        y = 190 + m.sourceSlots.count() * 96
        slot = {
            ring:  list.createChild("Rectangle"),
            card:  list.createChild("Rectangle"),
            order: list.createChild("Label"),
            name:  list.createChild("Label"),
            url:   list.createChild("Label"),
            status: list.createChild("Label"),
            up:    list.createChild("Rectangle"),
            upLabel: list.createChild("Label"),
            down:  list.createChild("Rectangle"),
            downLabel: list.createChild("Label")
        }
        slot.ring.setFields({ width: 1112, height: 96, translation: [494, y - 6], color: "0x00000000" })
        slot.card.setFields({ width: 1100, height: 84, translation: [500, y], color: "0x2F3227FF" })
        slot.order.setFields({ width: 50, height: 84, translation: [516, y], vertAlign: "center", horizAlign: "center", color: "0x96BBBBFF", font: "font:MediumBoldSystemFont" })
        slot.name.setFields({ width: 780, translation: [580, y + 8], color: "0xF2E3BCFF", font: "font:MediumBoldSystemFont" })
        slot.url.setFields({ width: 990, translation: [580, y + 48], color: "0x96BBBBAA", font: "font:SmallestSystemFont" })
        slot.status.setFields({ width: 200, height: 44, translation: [1380, y + 4], horizAlign: "right", vertAlign: "center", color: "0xC19875FF", font: "font:SmallBoldSystemFont" })
        slot.up.setFields({ width: 116, height: 84, translation: [1616, y] })
        slot.upLabel.setFields({ text: "Up", width: 116, height: 84, translation: [1616, y], horizAlign: "center", vertAlign: "center", font: "font:SmallBoldSystemFont" })
        slot.down.setFields({ width: 116, height: 84, translation: [1744, y] })
        slot.downLabel.setFields({ text: "Down", width: 116, height: 84, translation: [1744, y], horizAlign: "center", vertAlign: "center", font: "font:SmallBoldSystemFont" })
        m.sourceSlots.push(slot)
    end while
    return m.sourceSlots[i]
end function

' Draw the visible window of the source list, including focus styling.
sub renderSourceList()
    count = m.sources.count()
    if m.listTop > count - m.maxListRows then m.listTop = count - m.maxListRows
    if m.listTop < 0 then m.listTop = 0
    visible = count - m.listTop
    if visible > m.maxListRows then visible = m.maxListRows

    focusIdx = -1
    if onSourceRow() then focusIdx = m.rowIdx
    for i = 0 to visible - 1
        slot = sourceSlot(i)
        idx = m.listTop + i
        src = m.sources[idx]
        slot.order.text = (idx + 1).toStr()
        slot.name.text  = sourceDisplayName(src)
        urlText = src.m3uUrl
        if src.epgUrl = "" then urlText = urlText + "   (no guide data)"
        slot.url.text = urlText
        if src.enabled
            slot.status.text = ""
        else
            slot.status.text = "Off"
        end if
        if idx = focusIdx and m.colIdx = 0
            slot.ring.color = "0x96BBBBFF"
        else
            slot.ring.color = "0x00000000"
        end if
        styleMoveButton(slot.up, slot.upLabel, idx = focusIdx and m.colIdx = 1, idx > 0)
        styleMoveButton(slot.down, slot.downLabel, idx = focusIdx and m.colIdx = 2, idx < count - 1)
    end for
    for i = 0 to m.sourceSlots.count() - 1
        for each key in m.sourceSlots[i]
            m.sourceSlots[i][key].visible = (i < visible)
        end for
    end for

    y = 190 + visible * 96
    m.top.findNode("addBtn").translation = [500, y]
    m.top.findNode("addBtnLabel").translation = [500, y]
    hint = m.top.findNode("sourceListHint")
    hint.translation = [1260, y]
    if count = 0
        hint.text = "No sources yet."
    else if count > m.maxListRows
        hint.text = "Showing " + (m.listTop + 1).toStr() + "-" + (m.listTop + visible).toStr() + " of " + count.toStr()
    else
        hint.text = ""
    end if
end sub

sub styleMoveButton(bg as object, label as object, focused as boolean, canMove as boolean)
    if focused
        bg.color = "0x96BBBBFF"
        label.color = "0x414535FF"
    else
        bg.color = "0x414535FF"
        if canMove
            label.color = "0xF2E3BCFF"
        else
            label.color = "0x96BBBB66"
        end if
    end if
end sub

sub moveSource(idx as integer, delta as integer)
    target = idx + delta
    if target < 0 or target >= m.sources.count() then return
    src = m.sources[idx]
    m.sources[idx] = m.sources[target]
    m.sources[target] = src
    ' Focus follows the moved source, so repeated presses keep moving it.
    focusItem(target, m.colIdx)
end sub

sub addSource()
    m.sources.push({ id: "p" + m.nextSourceId.toStr(), name: "", m3uUrl: "", epgUrl: "", apiKey: "", enabled: true, tsToHls: false })
    m.nextSourceId = m.nextSourceId + 1
    openEditor(m.sources.count() - 1, true)
end sub

' ── Hidden channels ──────────────────────────────────────────────────────────

' Pooled row nodes for the visible part of the hidden list, created on demand.
function hiddenSlot(i as integer) as object
    while m.hiddenSlots.count() <= i
        list = m.top.findNode("hiddenList")
        y = 190 + m.hiddenSlots.count() * 84
        slot = {
            ring:   list.createChild("Rectangle"),
            card:   list.createChild("Rectangle"),
            strip:  list.createChild("Rectangle"),
            name:   list.createChild("Label"),
            detail: list.createChild("Label"),
            status: list.createChild("Label"),
            unhide: list.createChild("Rectangle"),
            unhideLabel: list.createChild("Label"),
            retry:  list.createChild("Rectangle"),
            retryLabel: list.createChild("Label"),
            perm:   list.createChild("Rectangle"),
            permLabel: list.createChild("Label")
        }
        slot.ring.setFields({ width: 822, height: 84, translation: [494, y - 6], color: "0x00000000" })
        slot.card.setFields({ width: 810, height: 72, translation: [500, y], color: "0x2F3227FF" })
        ' Which kind of hidden: Deep Teal = by the user, Camel = unsupported codec.
        slot.strip.setFields({ width: 6, height: 72, translation: [500, y] })
        slot.name.setFields({ width: 460, translation: [526, y + 4], color: "0xF2E3BCFF", font: "font:MediumBoldSystemFont" })
        slot.detail.setFields({ width: 460, translation: [526, y + 44], color: "0x96BBBBAA", font: "font:SmallestSystemFont" })
        slot.status.setFields({ width: 300, height: 72, translation: [994, y], horizAlign: "right", vertAlign: "center", font: "font:SmallBoldSystemFont" })
        slot.unhide.setFields({ width: 150, height: 72, translation: [1322, y] })
        slot.unhideLabel.setFields({ text: "Unhide", width: 150, height: 72, translation: [1322, y], horizAlign: "center", vertAlign: "center", font: "font:SmallBoldSystemFont" })
        slot.retry.setFields({ width: 130, height: 72, translation: [1484, y] })
        slot.retryLabel.setFields({ text: "Retry", width: 130, height: 72, translation: [1484, y], horizAlign: "center", vertAlign: "center", font: "font:SmallBoldSystemFont" })
        slot.perm.setFields({ width: 236, height: 72, translation: [1624, y] })
        slot.permLabel.setFields({ text: "Hide Permanently", width: 236, height: 72, translation: [1624, y], horizAlign: "center", vertAlign: "center", font: "font:SmallBoldSystemFont" })
        m.hiddenSlots.push(slot)
    end while
    return m.hiddenSlots[i]
end function

' Draw the visible window of the hidden list, including focus styling.
sub renderHiddenList()
    count = m.hidden.count()
    if m.hiddenTop > count - m.maxHiddenRows then m.hiddenTop = count - m.maxHiddenRows
    if m.hiddenTop < 0 then m.hiddenTop = 0
    visible = count - m.hiddenTop
    if visible > m.maxHiddenRows then visible = m.maxHiddenRows

    sourceNames = {}
    for each src in m.sources
        sourceNames[sourcePrefix(src)] = sourceDisplayName(src)
    end for

    focusIdx = -1
    if onHiddenRow() then focusIdx = m.rowIdx
    for i = 0 to visible - 1
        slot = hiddenSlot(i)
        e = m.hidden[m.hiddenTop + i]
        focused = (m.hiddenTop + i = focusIdx)
        if e.name <> ""
            slot.name.text = e.name
        else
            slot.name.text = "Unknown channel"
        end if
        detail = sourceNames[idPrefixOf(e.id)]
        if detail = invalid then detail = "Removed source"
        if e.num <> "" then detail = detail + "  ·  Ch " + e.num
        if e.name = "" then detail = detail + "  ·  " + e.id
        slot.detail.text = detail
        if e.kind = "codec"
            slot.strip.color  = "0xC19875FF"
            slot.status.color = "0xC19875FF"
            days = " days"
            if e.daysLeft = 1 then days = " day"
            slot.status.text = "Unsupported, " + e.daysLeft.toStr() + days + " left"
        else
            slot.strip.color  = "0x618985FF"
            slot.status.color = "0x96BBBBFF"
            slot.status.text  = "Hidden by you"
        end if
        if focused
            slot.ring.color = "0x96BBBBFF"
        else
            slot.ring.color = "0x00000000"
        end if
        styleMoveButton(slot.unhide, slot.unhideLabel, focused and m.colIdx = 0, true)
        styleMoveButton(slot.retry, slot.retryLabel, focused and m.colIdx = 1, true)
        styleMoveButton(slot.perm, slot.permLabel, focused and m.colIdx = 2, true)
    end for
    for i = 0 to m.hiddenSlots.count() - 1
        slot = m.hiddenSlots[i]
        for each key in slot
            slot[key].visible = (i < visible)
        end for
        if i < visible and m.hidden[m.hiddenTop + i].kind <> "codec"
            slot.retry.visible = false
            slot.retryLabel.visible = false
            slot.perm.visible = false
            slot.permLabel.visible = false
        end if
    end for

    y = 190 + visible * 84
    m.top.findNode("unhideAllBtn").translation = [500, y]
    m.top.findNode("unhideAllBtnLabel").translation = [500, y]
    m.top.findNode("unhideAllBtn").visible = (count > 0)
    m.top.findNode("unhideAllBtnLabel").visible = (count > 0)
    hint = m.top.findNode("hiddenListHint")
    hint.translation = [1260, y]
    if count = 0
        hint.text = "No channels are hidden."
        hint.horizAlign = "left"
        hint.translation = [500, y]
    else
        hint.horizAlign = "right"
        if count > m.maxHiddenRows
            hint.text = "Showing " + (m.hiddenTop + 1).toStr() + "-" + (m.hiddenTop + visible).toStr() + " of " + count.toStr()
        else
            hint.text = ""
        end if
    end if
end sub

sub unhideAt(idx as integer)
    unhideChannel(m.hidden[idx].id)
    m.hidden.delete(idx)
    focusItem(idx, 0)   ' the next channel, or Unhide All / Save when it was the last
end sub

' Unsupported codec → hidden for good. The list is re-read (the entry moves to
' the "hidden by you" group) and focus follows the channel.
sub hidePermanentlyAt(idx as integer)
    id = m.hidden[idx].id
    hideChannelPermanently(m.hidden[idx])
    m.hidden = hiddenChannelList()
    for i = 0 to m.hidden.count() - 1
        if m.hidden[i].id = id then idx = i
    end for
    focusItem(idx, 0)
end sub

sub unhideAll()
    clearHiddenChannels()
    m.hidden = []
    focusItem(0, 0)   ' Save
end sub

' ── Retry an unsupported channel ─────────────────────────────────────────────
' Plays the stream in a preview over the page; nothing else is playing while
' Settings is open, so the decoder is free. Playing → unhidden (back in the
' guide when Settings closes). An error on both attempts, or no picture within
' retryTimer, → it stays hidden. streamUrls comes from MainScene's loaded channels.

sub openRetry(idx as integer)
    e = m.hidden[idx]
    url = invalid
    if m.top.streamUrls <> invalid then url = m.top.streamUrls[e.id]
    m.retry = { id: e.id, idx: idx, url: url, attempts: 0, done: false }
    name = e.name
    if name = "" then name = e.id
    m.top.findNode("retryTitle").text = "Retrying " + name
    m.top.findNode("retryOverlay").visible = true
    if url = invalid or url = ""
        retryResult("This channel isn't loaded right now (its source is off or failed to load), so it can't be tested.", false)
        return
    end if
    retryPlay()
end sub

sub retryPlay()
    m.retry.attempts = m.retry.attempts + 1
    print "[SettingsScene] retry " + m.retry.id + " attempt " + m.retry.attempts.toStr()
    m.top.findNode("retryResult").text = ""
    m.top.findNode("retryHint").text = "Back to cancel"
    m.top.findNode("retrySpinner").visible = true
    content = CreateObject("roSGNode", "ContentNode")
    content.url = m.retry.url
    if Instr(LCase(m.retry.url), ".m3u8") > 0
        content.streamFormat = "hls"
    else
        content.streamFormat = "ts"
    end if
    m.retryVideo.content = content
    m.retryVideo.control = "play"
    m.retryTimer.control = "stop"
    m.retryTimer.control = "start"
end sub

sub onRetryVideoState()
    if m.retry = invalid or m.retry.done then return
    state = m.retryVideo.state
    if state = "playing"
        unhideChannel(m.retry.id)
        for i = 0 to m.hidden.count() - 1
            if m.hidden[i].id = m.retry.id
                m.hidden.delete(i)
                exit for
            end if
        end for
        retryResult("It plays now. The channel is back in the guide.", true)
    else if state = "error" or state = "finished"
        code = m.retryVideo.errorCode
        m.retryVideo.control = "stop"
        if m.retry.attempts < 2
            ' A proxy's error stream (Dispatcharr) also reads as -5; try once more.
            retryPlay()
        else if code = -5
            retryResult("Still doesn't work: this device can't play the stream's codec (error -5). It stays hidden.", false)
        else
            retryResult("Still doesn't work: the stream failed (error " + code.toStr() + "). It stays hidden.", false)
        end if
    end if
end sub

sub onRetryTimer()
    if m.retry = invalid or m.retry.done then return
    m.retryVideo.control = "stop"
    retryResult("Still doesn't work: no picture after " + Int(m.retryTimer.duration).toStr() + " seconds. It stays hidden.", false)
end sub

' ok: the channel plays (the preview keeps playing until the overlay closes).
sub retryResult(msg as string, ok as boolean)
    m.retry.done = true
    m.retryTimer.control = "stop"
    m.top.findNode("retrySpinner").visible = false
    result = m.top.findNode("retryResult")
    result.text = msg
    if ok
        result.color = "0x96BBBBFF"
    else
        result.color = "0xC19875FF"
    end if
    m.top.findNode("retryHint").text = "OK or Back to close"
end sub

sub closeRetry()
    m.retryVideo.control = "stop"
    m.retryTimer.control = "stop"
    m.top.findNode("retryOverlay").visible = false
    idx = m.retry.idx
    col = m.colIdx
    ' Unhidden: the row is gone, focus the channel that took its place.
    if idx >= m.hidden.count() or m.hidden[idx].id <> m.retry.id then col = 0
    m.retry = invalid
    focusItem(idx, col)
end sub

' ── Source editor ────────────────────────────────────────────────────────────

sub openEditor(idx as integer, isNew as boolean)
    src = m.sources[idx]
    m.editIdx   = idx
    m.editIsNew = isNew
    m.nameInput.text = src.name
    m.m3uInput.text  = src.m3uUrl
    m.epgInput.text  = src.epgUrl
    m.apiKeyInput.text = src.apiKey
    if src.enabled
        setChooserValue("enabledChooser", "on")
    else
        setChooserValue("enabledChooser", "off")
    end if
    if src.tsToHls
        setChooserValue("tsChooser", "on")
    else
        setChooserValue("tsChooser", "off")
    end if
    if isNew
        m.top.findNode("editTitle").text = "New Source"
        showPage(0)
        focusItem(1, 0)   ' the M3U URL, the one field it needs
    else
        m.top.findNode("editTitle").text = "Edit Source " + (idx + 1).toStr() + " of " + m.sources.count().toStr()
        showPage(0)
        focusItem(0, 0)
    end if
end sub

' Copy the editor fields into the working source list.
sub commitEditor()
    if m.editIdx < 0 then return
    src = m.sources[m.editIdx]
    src.name    = m.nameInput.text.trim()
    src.m3uUrl  = m.m3uInput.text.trim()
    src.epgUrl  = m.epgInput.text.trim()
    src.apiKey  = m.apiKeyInput.text.trim()
    src.enabled = (chooserValue("enabledChooser") = "on")
    src.tsToHls = (chooserValue("tsChooser") = "on")
end sub

' Done / Back: return to the list with the source focused. A new source with no
' playlist URL is discarded; an existing one must get a URL or be removed.
sub closeEditor()
    commitEditor()
    idx = m.editIdx
    if m.sources[idx].m3uUrl = ""
        if not m.editIsNew
            m.errorLabel.text = "A source needs an M3U playlist URL. Use Remove Source to delete it."
            focusItem(1, 0)
            return
        end if
        m.sources.delete(idx)
    end if
    m.editIdx = -1
    m.errorLabel.text = ""
    showPage(0)
    focusItem(idx, 0)
end sub

sub removeSource()
    idx = m.editIdx
    m.sources.delete(idx)
    m.editIdx = -1
    m.errorLabel.text = ""
    showPage(0)
    focusItem(idx, 0)   ' the next source, or Add when it was the last
end sub

' ── Choosers ─────────────────────────────────────────────────────────────────

sub setChooserValue(name as string, value as string)
    ch = m.choosers[name]
    for i = 0 to ch.values.count() - 1
        if ch.values[i] = value then setChooserIdx(name, i)
    end for
end sub

sub setChooserIdx(name as string, idx as integer)
    ch = m.choosers[name]
    if idx < 0 then idx = 0
    if idx > ch.values.count() - 1 then idx = ch.values.count() - 1
    ch.idx = idx
    if ch.valueLabel <> invalid
        m.top.findNode(ch.valueLabel).text = ch.values[idx] + ch.suffix
        ' Dim the arrow that can't go further.
        if idx = 0
            m.top.findNode(ch.decLabel).color = "0x96BBBB66"
        else
            m.top.findNode(ch.decLabel).color = "0xF2E3BCFF"
        end if
        if idx = ch.values.count() - 1
            m.top.findNode(ch.incLabel).color = "0x96BBBB66"
        else
            m.top.findNode(ch.incLabel).color = "0xF2E3BCFF"
        end if
        return
    end if
    for i = 0 to ch.values.count() - 1
        pill  = m.top.findNode(ch.pill + i.toStr())
        label = m.top.findNode(ch.pill + "Label" + i.toStr())
        if i = idx
            pill.color  = "0x618985FF"
            label.color = "0xF2E3BCFF"
        else
            pill.color  = "0x414535FF"
            label.color = "0x96BBBBFF"
        end if
    end for
end sub

function chooserValue(name as string) as string
    ch = m.choosers[name]
    return ch.values[ch.idx]
end function

' ── Keys ─────────────────────────────────────────────────────────────────────

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.retry <> invalid
        ' The retry overlay is modal: Back cancels / closes, OK closes once it is done.
        if key = "back" or (key = "OK" and m.retry.done) then closeRetry()
        return true
    end if

    if m.area = "nav"
        if key = "down"
            if m.pageIdx < m.pages.count() - 1 then showPage(m.pageIdx + 1)
            return true
        else if key = "up"
            if m.pageIdx > 0 then showPage(m.pageIdx - 1)
            return true
        else if key = "right" or key = "OK"
            focusItem(0, 0)
            return true
        else if key = "back"
            if hasUnsavedChanges()
                promptUnsaved()
            else
                m.top.action = "cancelled"
            end if
            return true
        end if
        return false
    end if

    ' content area
    rows = currentRows()
    row  = rows[m.rowIdx]
    name = row[m.colIdx]

    if key = "down"
        if m.rowIdx < rows.count() - 1 then focusItem(m.rowIdx + 1, m.colIdx)
        return true
    else if key = "up"
        if m.rowIdx > 0 then focusItem(m.rowIdx - 1, m.colIdx)
        return true
    else if key = "right"
        if m.choosers[name] <> invalid
            setChooserIdx(name, m.choosers[name].idx + 1)
        else if m.colIdx < row.count() - 1
            focusItem(m.rowIdx, m.colIdx + 1)
        end if
        return true
    else if key = "left"
        if m.choosers[name] <> invalid
            setChooserIdx(name, m.choosers[name].idx - 1)
        else if m.colIdx > 0
            focusItem(m.rowIdx, m.colIdx - 1)
        else if m.pageIdx = 0 and m.editIdx >= 0
            ' Leaving the editor via Left must close it like Back does, not just
            ' switch to nav mode: focusNav() never clears m.editIdx, so showPage(0)
            ' would redisplay this same stale editor instead of the source list.
            closeEditor()
        else
            focusNav()
        end if
        return true
    else if key = "back"
        if m.pageIdx = 0 and m.editIdx >= 0
            closeEditor()
        else
            focusNav()
        end if
        return true
    else if key = "OK" or key = "play"
        if m.inputBoxes[name] <> invalid
            openKeyboard(name)
        else if m.choosers[name] <> invalid
            ' OK steps to the next option, wrapping around.
            nextIdx = m.choosers[name].idx + 1
            if nextIdx >= m.choosers[name].values.count() then nextIdx = 0
            setChooserIdx(name, nextIdx)
        else if name = "src"
            openEditor(m.rowIdx, false)
        else if name = "srcUp"
            moveSource(m.rowIdx, -1)
        else if name = "srcDown"
            moveSource(m.rowIdx, 1)
        else if name = "addBtn"
            addSource()
        else if name = "doneBtn"
            closeEditor()
        else if name = "removeBtn"
            removeSource()
        else if name = "refreshBtn"
            m.top.action = "refresh"
        else if name = "saveBtn"
            trySave()
        else if name = "hidUnhide"
            unhideAt(m.rowIdx)
        else if name = "hidRetry"
            openRetry(m.rowIdx)
        else if name = "hidPerm"
            hidePermanentlyAt(m.rowIdx)
        else if name = "unhideAllBtn"
            unhideAll()
        end if
        return true
    end if
    return false
end function

' ── Keyboard dialog ──────────────────────────────────────────────────────────

sub openKeyboard(name as string)
    input = m.top.findNode(name)
    dlg = CreateObject("roSGNode", "KeyboardDialog")
    dlg.title   = m.inputTitles[name]
    dlg.text    = input.text
    dlg.buttons = ["OK", "Cancel"]
    dlg.keyboard.textEditBox.maxTextLength = input.maxTextLength
    dlg.observeField("buttonSelected", "onKeyboardButton")
    dlg.observeField("wasClosed", "onKeyboardClosed")
    m.kbTarget = name
    m.kbDialog = dlg
    m.top.getScene().dialog = dlg
end sub

sub onKeyboardButton()
    if m.kbDialog.buttonSelected = 0
        m.top.findNode(m.kbTarget).text = m.kbDialog.text.trim()
        m.errorLabel.text = ""
    end if
    m.kbDialog.close = true
end sub

sub onKeyboardClosed()
    m.kbDialog = invalid
    m.kbTarget = ""
    m.top.setFocus(true)
end sub

' ── Unsaved changes ──────────────────────────────────────────────────────────

' True when Save would write something different from the registry. Hidden
' channel changes don't count: they are written as they are made.
function hasUnsavedChanges() as boolean
    if m.editIdx >= 0 then commitEditor()
    old = readSettings()
    if sourcesChanged(old.sources, m.sources) then return true
    if m.intervalInput.text.trim() <> old.refreshIntervalMin.toStr() then return true
    if chooserValue("guideHoursChooser") <> old.guideHours.toStr() then return true
    if chooserValue("guideRowsChooser") <> old.guideRows.toStr() then return true
    if chooserValue("launchChooser") <> old.onLaunch then return true
    return false
end function

sub promptUnsaved()
    dlg = CreateObject("roSGNode", "Dialog")
    dlg.title   = "Unsaved changes"
    dlg.message = "Save your changes before leaving Settings?"
    dlg.buttons = ["Save", "Discard Changes", "Keep Editing"]
    dlg.observeField("buttonSelected", "onUnsavedButton")
    dlg.observeField("wasClosed", "onUnsavedClosed")
    m.unsavedDlg    = dlg
    m.unsavedChoice = -1
    m.top.getScene().dialog = dlg
end sub

sub onUnsavedButton()
    m.unsavedChoice = m.unsavedDlg.buttonSelected
    m.unsavedDlg.close = true
end sub

' Acts once the dialog is gone, so Settings is never closed under it. Back on
' the dialog (choice -1) is the same as Keep Editing.
sub onUnsavedClosed()
    choice = m.unsavedChoice
    m.unsavedDlg    = invalid
    m.unsavedChoice = -1
    m.top.setFocus(true)
    if choice = 0
        trySave()   ' a validation error leaves Settings open on the bad field
    else if choice = 1
        m.top.action = "cancelled"
    end if
end sub

' ── About ────────────────────────────────────────────────────────────────────

sub renderAbout()
    app = CreateObject("roAppInfo")
    di  = CreateObject("roDeviceInfo")

    version = app.GetTitle() + " " + app.GetVersion()
    if app.IsDev() then version = version + "  (sideloaded)"
    setAboutText("aboutVersion", version)

    device = di.GetModelDisplayName() + " (" + di.GetModel() + ")"
    friendly = di.GetFriendlyName()
    if friendly <> "" then device = device + "  ·  " + friendly
    setAboutText("aboutDevice", device)

    os = di.GetOSVersion()
    setAboutText("aboutOs", os.major + "." + os.minor + "." + os.revision + "  build " + os.build)

    ui = di.GetUIResolution()
    setAboutText("aboutUi", UCase(ui.name) + "  " + ui.width.toStr() + " x " + ui.height.toStr())
    setAboutText("aboutDisplay", di.GetVideoMode() + "  ·  " + di.GetDisplayType())

    ips = di.GetIPAddrs()
    ipText = ""
    for each iface in ips
        if ipText <> "" then ipText = ipText + ", "
        ipText = ipText + ips[iface]
    end for
    if ipText = "" then ipText = "Not connected"
    conn = di.GetConnectionType()
    if conn = "WiFiConnection"
        ipText = ipText + "  ·  Wi-Fi"
    else if conn = "WiredConnection"
        ipText = ipText + "  ·  Wired"
    end if
    setAboutText("aboutIp", ipText)

    ' roAppMemoryMonitor needs a newer Roku OS than the manifest minimum.
    memText = ""
    try
        mon = CreateObject("roAppMemoryMonitor")
        if mon <> invalid
            memText = Int(mon.GetChannelAvailableMemory() / 1024).toStr() + " MB available to the app  ·  "
        end if
    catch e
        memText = ""
    end try
    setAboutText("aboutMemory", memText + "memory level " + di.GetGeneralMemoryLevel())

    info = m.top.epgInfo
    if info = invalid or info.channels = invalid or (info.channels = 0 and info.hidden = 0)
        setAboutText("aboutChannels", "Nothing loaded yet")
        setAboutText("aboutGuide", "")
        setAboutText("aboutEpg", "")
        return
    end if
    setAboutText("aboutChannels", info.channels.toStr() + " in the guide  ·  " + info.hidden.toStr() + " hidden")
    setAboutText("aboutGuide", info.programs.toStr() + " programmes  ·  listings for " + info.withGuide.toStr() + " of " + info.channels.toStr() + " channels")
    if info.programs = 0
        setAboutText("aboutEpg", "No guide data")
    else
        range = epochToDateStr(info.first) + " " + epochToTimeStr(info.first) + "  to  " + epochToDateStr(info.last) + " " + epochToTimeStr(info.last)
        if info.last <= nowEpoch() then range = range + "  (run out)"
        setAboutText("aboutEpg", range)
    end if
end sub

sub setAboutText(id as string, text as string)
    m.top.findNode(id).text = text
end sub

' ── Actions ──────────────────────────────────────────────────────────────────

sub trySave()
    intStr      = m.intervalInput.text.trim()
    intervalMin = intStr.toInt()

    if m.editIdx >= 0
        commitEditor()
        if m.sources[m.editIdx].m3uUrl = ""
            showError("The M3U playlist URL is required.", 0)
            return
        end if
    end if
    if enabledSources({ sources: m.sources }).count() = 0
        showError("Add or turn on at least one source.", 0)
        return
    end if
    if intervalMin < 15
        m.intervalInput.text = "15"
        showError("Minimum refresh interval is 15 minutes.", 2)
        return
    end if

    m.errorLabel.text = ""
    old = readSettings()
    settings = {
        sources:      m.sources,
        nextSourceId: m.nextSourceId,
        refreshIntervalMin: intervalMin,
        guideHours:   chooserValue("guideHoursChooser").toInt(),
        guideRows:    chooserValue("guideRowsChooser").toInt(),
        onLaunch:     chooserValue("launchChooser")
    }
    writeSettings(settings)

    if sourcesChanged(old.sources, m.sources)
        m.top.action = "saved"
    else
        m.top.action = "savedLocal"
    end if
end sub

' Any add, remove, reorder or field change means the guide must be re-fetched.
function sourcesChanged(a as object, b as object) as boolean
    if a.count() <> b.count() then return true
    for i = 0 to a.count() - 1
        for each key in ["id", "name", "m3uUrl", "epgUrl", "apiKey", "enabled", "tsToHls"]
            if a[i][key] <> b[i][key] then return true
        end for
    end for
    return false
end function

' Show a validation message and switch to the page that owns the bad field.
sub showError(msg as string, pageIdx as integer)
    m.errorLabel.text = msg
    if pageIdx <> m.pageIdx
        showPage(pageIdx)
        focusItem(currentRows().count() - 1, 0)   ' land on Save
    end if
end sub
