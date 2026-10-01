sub init()
    m.loadingBg      = m.top.findNode("loadingBg")
    m.loadingTitle   = m.top.findNode("loadingTitle")
    m.loadingSpinner = m.top.findNode("loadingSpinner")
    m.loadingMsg     = m.top.findNode("loadingMsg")
    m.loadingBarTrack = m.top.findNode("loadingBarTrack")
    m.loadingBarFill  = m.top.findNode("loadingBarFill")
    m.errorBg        = m.top.findNode("errorBg")
    m.errorMsg       = m.top.findNode("errorMsg")
    m.retryBtn       = m.top.findNode("retryBtn")
    m.retryBtnLabel  = m.top.findNode("retryBtnLabel")
    m.errorHint      = m.top.findNode("errorHint")

    m.guideScene    = invalid
    m.playerScene   = invalid
    m.settingsScene = invalid
    m.refreshTask   = invalid
    m.currentChannel  = invalid
    m.previousChannel = invalid
    m.allChannels     = []   ' every fetched channel, hidden ones included
    m.channels        = []   ' what the guide shows: allChannels minus hidden (filterHiddenChannels)
    m.programs        = {}
    m.afterDialogAction = ""
    m.pendingErrorMsg   = ""
    m.guideFocusId = ""   ' channel the next openGuide puts the cursor on
    m.launched = false    ' the first guide open applies the "on launch" setting
    m.guideFilter = ""   ' guide "on now" filter key, kept across GuideScene rebuilds
    m.launchSignalled = false   ' AppLaunchComplete beacon sent (launchComplete)
    m.pendingLink = invalid     ' deep link waiting for channels (applyDeepLink)
    m.exitDialog  = invalid
    ' Dispatcharr recordings (RecordingsTask): { "<source prefix><channel uuid>": [ { start, stop } ] }.
    ' markRecordings sets rec = true on the programmes they cover; recMarked lists them for clearing.
    m.recordings = {}
    m.recMarked  = []
    m.recTask    = invalid
    m.dvrTask    = invalid
    ' Series rules are evaluated on Dispatcharr's side after the POST returns, so
    ' look again shortly after a record request.
    m.recSoonTimer = m.top.createChild("Timer")
    m.recSoonTimer.repeat   = false
    m.recSoonTimer.duration = 10
    m.recSoonTimer.observeField("fire", "fetchRecordings")
    m.recTimer = m.top.createChild("Timer")
    m.recTimer.repeat   = true
    m.recTimer.duration = 300
    m.recTimer.observeField("fire", "fetchRecordings")
    m.recTimer.control  = "start"

    m.favIds = favoriteIds()   ' "|id|id|", handed to the guide for the Favorites filter
    ' Reminders (long-press menu): { "<channel id>@<start>": { id, start, stop, title, name, num } }.
    ' markReminders sets remind = true on those programmes; remindTimer pops a
    ' dialog when one is about to start.
    m.reminders    = readReminders()
    m.remindMarked = []
    m.remindDialog = invalid
    m.remindCh     = invalid   ' channel the open reminder dialog would tune to
    m.remindTimer = m.top.createChild("Timer")
    m.remindTimer.repeat   = true
    m.remindTimer.duration = 15
    m.remindTimer.observeField("fire", "checkReminders")
    m.remindTimer.control  = "start"

    showSplash()
    checkSettingsAndStart()
end sub

' ── Splash / Loading ──────────────────────────────────────────────────────────

sub showSplash()
    m.loadingBg.visible      = true
    m.loadingTitle.visible   = true
    m.loadingSpinner.visible = false
    m.loadingMsg.text        = ""
    m.loadingMsg.visible     = true
end sub

sub showLoading(msg as string)
    m.loadingBg.visible      = true
    m.loadingTitle.visible   = true
    m.loadingSpinner.visible = true
    m.loadingMsg.text        = msg
    m.loadingMsg.visible     = true
    setLoadingProgress(0)
    m.loadingBarTrack.visible = true
    m.loadingBarFill.visible  = true
    hideError()
    if m.guideScene <> invalid
        m.guideScene.currentChannel = invalid
        m.guideScene.visible = false
    end if
    if m.playerScene <> invalid then m.playerScene.visible = false
end sub

sub hideLoading()
    m.loadingBg.visible      = false
    m.loadingTitle.visible   = false
    m.loadingSpinner.visible = false
    m.loadingMsg.visible     = false
    m.loadingBarTrack.visible = false
    m.loadingBarFill.visible  = false
end sub

sub setLoadingProgress(fraction as float)
    if fraction < 0 then fraction = 0
    if fraction > 1 then fraction = 1
    m.loadingBarFill.width = m.loadingBarTrack.width * fraction
end sub

sub onFetchProgress()
    if m.activeFetch = invalid then return
    p = m.activeFetch.progress
    if p = invalid or p.fraction = invalid then return
    setLoadingProgress(p.fraction)
    if p.msg <> "" then m.loadingMsg.text = p.msg
end sub

' ── Error screen ─────────────────────────────────────────────────────────────

sub showInitialError(msg as string)
    hideLoading()
    m.errorBg.visible       = true
    m.errorMsg.text         = msg
    m.errorMsg.visible      = true
    m.retryBtn.visible      = true
    m.retryBtnLabel.visible = true
    m.errorHint.visible     = true
    m.top.setFocus(true)
    launchComplete()
end sub

sub hideError()
    m.errorBg.visible       = false
    m.errorMsg.visible      = false
    m.retryBtn.visible      = false
    m.retryBtnLabel.visible = false
    m.errorHint.visible     = false
end sub

' First interactive screen (guide, Settings or the error screen) is up: tell
' Roku the launch is over. Certification times launch to this beacon (15s max).
sub launchComplete()
    if m.launchSignalled then return
    m.launchSignalled = true
    m.top.signalBeacon("AppLaunchComplete")
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if not m.retryBtn.visible then return false
    ' Error screen: OK retries (or opens Settings if no source is enabled any more),
    ' options opens Settings so a bad URL can be fixed without a working fetch.
    if key = "OK" or key = "play"
        hideError()
        checkSettingsAndStart()
        return true
    else if key = "options"
        openSettings()
        return true
    end if
    return false
end function

' ── Startup flow ─────────────────────────────────────────────────────────────

sub checkSettingsAndStart()
    if enabledSources(readSettings()).count() = 0
        openSettings()
    else
        triggerFetch(false)
    end if
end sub

' ── Settings ─────────────────────────────────────────────────────────────────

sub openSettings()
    if m.settingsScene <> invalid
        m.top.removeChild(m.settingsScene)
    end if
    m.settingsScene = m.top.createChild("SettingsScene")
    m.settingsScene.epgInfo = epgInfo()
    m.settingsScene.streamUrls = codecHiddenStreamUrls()
    m.settingsScene.observeField("action", "onSettingsAction")
    m.settingsScene.setFocus(true)
    if m.guideScene  <> invalid
        m.guideScene.currentChannel = invalid
        m.guideScene.visible = false
    end if
    if m.playerScene <> invalid then m.playerScene.visible = false
    hideLoading()
    hideError()
    launchComplete()
end sub

sub onSettingsAction()
    action = m.settingsScene.action
    m.top.removeChild(m.settingsScene)
    m.settingsScene = invalid
    ' Settings may have unhidden (or permanently hidden) channels.
    m.channels = filterHiddenChannels(m.allChannels)

    if action = "saved"
        updateRefreshTaskSettings()
        triggerFetch(false)
    else if action = "savedLocal"
        ' Only guide/refresh options changed: no need to re-download anything.
        ' openGuide recreates GuideScene so the grid picks up the new layout.
        updateRefreshTaskSettings()
        if m.channels.count() = 0
            triggerFetch(false)
        else
            openGuide()
        end if
    else if action = "refresh"
        triggerFetch(false)
    else
        ' Cancelled with no data yet: back to the error screen, the only way on
        ' from there (Retry or Settings again).
        if m.channels.count() = 0
            msg = m.pendingErrorMsg
            if msg = "" then msg = "No channels loaded."
            showInitialError(msg)
        else
            openGuide()
        end if
    end if
end sub

' ── Data fetch ───────────────────────────────────────────────────────────────

sub triggerFetch(m3uOnly as boolean)
    if m.activeFetch <> invalid
        m.top.removeChild(m.activeFetch)
        m.activeFetch = invalid
    end if
    showLoading("Loading channels…")
    m.activeFetch = startFetchTask(m3uOnly, "onFetchComplete")
    m.activeFetch.observeField("progress", "onFetchProgress")
end sub

function startFetchTask(m3uOnly as boolean, onDone as string) as object
    fetchTask = m.top.createChild("FetchDataTask")
    fetchTask.sources = enabledSources(readSettings())
    fetchTask.m3uOnly = m3uOnly
    fetchTask.observeField("state", onDone)
    fetchTask.control = "RUN"
    return fetchTask
end function

sub onFetchComplete()
    task = m.activeFetch
    if task = invalid then return
    if task.state = "run" or task.state = "init" then return
    print "[MainScene] fetch done, error=" + task.error + " channels=" + task.channels.count().toStr()

    errMsg = task.error
    hasNewChannels = task.channels.count() > 0

    if hasNewChannels
        merged = mergeFetchResult(task)
        m.allChannels = merged.channels
        m.channels = filterHiddenChannels(m.allChannels)
        m.programs = merged.programs
        markRecordings()
        markReminders()
        fetchRecordings()
    end if

    m.top.removeChild(task)
    m.activeFetch = invalid

    if errMsg <> ""
        m.pendingErrorMsg = errMsg
        if hasNewChannels or m.channels.count() > 0
            m.afterDialogAction = "openGuide"
        else
            m.afterDialogAction = "showError"
        end if
        showErrorDialog(errMsg)
        return
    end if

    finishFetch()
end sub

sub finishFetch()
    if m.playerScene <> invalid and m.playerScene.action = "tokenExpired"
        hideLoading()
        m.playerScene.visible = true
        m.playerScene.setFocus(true)
        updatePlayerWithFreshUrl()
        return
    end if
    hideLoading()
    if not m.launched
        m.launched = true
        resumeLastChannel()
    end if
    openGuide()
    if m.refreshTask = invalid
        startRefreshTimer()
    end if
    applyDeepLink()
end sub

' Combine a completed FetchDataTask with the data already loaded. A source whose
' fetch failed (or was skipped) keeps its previous channels / programs, in its
' place in the source order, instead of disappearing until the next successful
' refresh. Sources that were removed or disabled drop out.
function mergeFetchResult(task as object) as object
    newByPrefix = channelsByPrefix(task.channels)
    oldByPrefix = channelsByPrefix(m.allChannels)
    failed   = task.failed
    channels = []
    programs = task.programs
    keepPrograms = {}

    for each src in task.sources
        prefix = sourcePrefix(src)
        f = failed[src.id]
        if f = invalid then f = { m3u: true, epg: true }
        byPrefix = newByPrefix
        if f.m3u then byPrefix = oldByPrefix
        if byPrefix.doesExist(prefix) then channels.append(byPrefix[prefix])
        if f.m3u or f.epg then keepPrograms[prefix] = true
    end for

    if keepPrograms.count() > 0
        for each key in m.programs
            if keepPrograms.doesExist(idPrefixOf(key)) then programs[key] = m.programs[key]
        end for
    end if

    return { channels: channels, programs: programs }
end function

function channelsByPrefix(channels as object) as object
    result = {}
    for each ch in channels
        prefix = idPrefixOf(ch.id)
        if not result.doesExist(prefix) then result[prefix] = []
        result[prefix].push(ch)
    end for
    return result
end function

' "On launch: resume last channel": the channel last opened in the player plays
' in the PIP (not fullscreen) with the guide cursor on it. Nothing happens when
' it is gone or hidden.
sub resumeLastChannel()
    if readSettings().onLaunch <> "resume" then return
    id = lastChannelId()
    if id = "" then return
    for each ch in m.channels
        if ch.id = id
            m.currentChannel = ch
            m.guideFocusId = id
            print "[MainScene] resuming " + ch.name + " in PIP"
            return
        end if
    end for
end sub

' Stream URLs of the loaded codec-hidden channels, for Settings' Retry button.
function codecHiddenStreamUrls() as object
    skip = CreateObject("roRegistrySection", "iptv_skip")
    urls = {}
    for each ch in m.allChannels
        if skip.Exists(ch.id) then urls[ch.id] = ch.streamUrl
    end for
    return urls
end function

' Loaded-data summary for Settings > About: counts and the span the EPG covers.
function epgInfo() as object
    info = { channels: m.channels.count(), hidden: m.allChannels.count() - m.channels.count(), programs: 0, withGuide: 0, first: 0, last: 0 }
    for each ch in m.channels
        if m.programs.doesExist(ch.id) and m.programs[ch.id].count() > 0 then info.withGuide = info.withGuide + 1
    end for
    for each key in m.programs
        list = m.programs[key]
        if list.count() > 0
            info.programs = info.programs + list.count()
            ' Lists are sorted by start.
            if info.first = 0 or list[0].start < info.first then info.first = list[0].start
            if list[list.count() - 1].stop > info.last then info.last = list[list.count() - 1].stop
        end if
    end for
    return info
end function

function guideData() as object
    return { channels: m.channels, programs: m.programs, dvr: dvrPrefixes(), favs: m.favIds }
end function

' "|p4_|…": prefixes of enabled sources with a Dispatcharr API key (can record).
function dvrPrefixes() as string
    result = "|"
    for each src in enabledSources(readSettings())
        if src.apiKey <> "" then result = result + sourcePrefix(src) + "|"
    end for
    return result
end function

' ── Recordings (Dispatcharr DVR) ─────────────────────────────────────────────

' Runs every 5 minutes (recTimer) and after each fetch, for every enabled source
' with a Dispatcharr API key.
sub fetchRecordings()
    if m.recTask <> invalid then return
    sources = []
    for each src in enabledSources(readSettings())
        if src.apiKey <> "" then sources.push(src)
    end for
    if sources.count() = 0
        if m.recordings.count() > 0 then applyRecordings({})
        return
    end if
    m.recTask = m.top.createChild("RecordingsTask")
    m.recTask.sources = sources
    m.recTask.observeField("state", "onRecordingsDone")
    m.recTask.control = "RUN"
end sub

sub onRecordingsDone()
    task = m.recTask
    if task = invalid then return
    if task.state = "run" or task.state = "init" then return
    res = task.result
    m.top.removeChild(task)
    m.recTask = invalid
    ' A failed request keeps the last good list rather than wiping the dots.
    if res = invalid or res.ok <> true then return
    if FormatJson(res.recs) <> FormatJson(m.recordings) then applyRecordings(res.recs)
end sub

' Long-press menu Record: send it to the channel's Dispatcharr (DvrTask).
sub startDvrRequest(kind as string, ch as object, prog as object)
    if m.dvrTask <> invalid
        m.guideScene.callFunc("showToast", "Still sending the last recording request.")
        return
    end if
    source = invalid
    for each src in enabledSources(readSettings())
        if sourcePrefix(src) = idPrefixOf(ch.id) then source = src
    end for
    if source = invalid or source.apiKey = "" then return
    request = { base: urlOrigin(source.m3uUrl), apiKey: source.apiKey, uuid: streamUuid(ch.streamUrl), kind: kind }
    request.program = { title: prog.title, start: prog.start, stop: prog.stop, desc: prog.desc }
    if prog.subtitle <> invalid and prog.subtitle <> "" then request.program.subtitle = prog.subtitle
    m.dvrTask = m.top.createChild("DvrTask")
    m.dvrTask.request = request
    m.dvrTask.observeField("state", "onDvrDone")
    m.dvrTask.control = "RUN"
end sub

sub onDvrDone()
    task = m.dvrTask
    if task = invalid then return
    if task.state = "run" or task.state = "init" then return
    res = task.result
    m.top.removeChild(task)
    m.dvrTask = invalid
    if res = invalid then res = { ok: false, msg: "Recording request failed." }
    if m.guideScene <> invalid then m.guideScene.callFunc("showToast", res.msg)
    if res.ok
        fetchRecordings()
        m.recSoonTimer.control = "start"
    end if
end sub

sub applyRecordings(recs as object)
    m.recordings = recs
    markRecordings()
    if m.guideScene <> invalid then m.guideScene.guideData = guideData()
end sub

' Flag each programme a recording covers (at least half of it, so the padding
' around a recording never marks its neighbours). Channels are matched by the
' uuid at the end of their Dispatcharr stream URL.
sub markRecordings()
    for each prog in m.recMarked
        prog.rec = false
    end for
    m.recMarked = []
    if m.recordings.count() = 0 then return
    for each ch in m.allChannels
        spans = m.recordings[idPrefixOf(ch.id) + streamUuid(ch.streamUrl)]
        progs = m.programs[ch.id]
        if spans <> invalid and progs <> invalid
            for each span in spans
                for each prog in progs
                    if prog.start >= span.stop then exit for
                    if prog.stop > span.start
                        s = prog.start
                        if span.start > s then s = span.start
                        e = prog.stop
                        if span.stop < e then e = span.stop
                        if (e - s) * 2 >= prog.stop - prog.start
                            prog.rec = true
                            m.recMarked.push(prog)
                        end if
                    end if
                end for
            end for
        end if
    end for
end sub

' Last path part of a stream URL, without the query string.
function streamUuid(url as string) as string
    q = Instr(1, url, "?")
    if q > 0 then url = Left(url, q - 1)
    parts = url.split("/")
    return parts[parts.count() - 1]
end function

' ── Reminders ────────────────────────────────────────────────────────────────

' Flag the programmes a reminder is set for (InfoPanel badge, "Cancel Reminder"
' in the long-press menu).
sub markReminders()
    for each prog in m.remindMarked
        prog.remind = false
    end for
    m.remindMarked = []
    for each key in m.reminders
        r = m.reminders[key]
        progs = m.programs[r.id]
        if progs <> invalid
            for each prog in progs
                if prog.start > r.start then exit for
                if prog.start = r.start
                    prog.remind = true
                    m.remindMarked.push(prog)
                    exit for
                end if
            end for
        end if
    end for
end sub

' remindTimer, every 15s. A reminder fires a minute before its show starts, as a
' dialog over the guide or the player; it waits while Settings, the loading or
' error screen, or another dialog is up. Firing deletes it.
sub checkReminders()
    if m.reminders.count() = 0 then return
    if m.top.dialog <> invalid or m.settingsScene <> invalid then return
    guideUp  = m.guideScene <> invalid and m.guideScene.visible
    playerUp = m.playerScene <> invalid and m.playerScene.visible
    if not guideUp and not playerUp then return
    nowSec = nowEpoch()
    due = ""
    for each key in m.reminders
        if m.reminders[key].start - 60 <= nowSec
            due = key
            exit for
        end if
    end for
    if due = "" then return

    r = m.reminders[due]
    deleteReminder(due)
    m.reminders = readReminders()
    markReminders()
    if m.guideScene <> invalid then m.guideScene.guideData = guideData()
    ' Ended while it waited, or already on in the player: nothing to say.
    if r.stop <= nowSec then return
    if playerUp and m.currentChannel <> invalid and m.currentChannel.id = r.id then return

    ch = invalid
    for each c in m.channels
        if c.id = r.id
            ch = c
            exit for
        end if
    end for
    chLabel = r.name
    if r.num <> invalid and r.num <> "" then chLabel = chLabel + " (Ch " + r.num + ")"
    timeText = "starts at " + epochToTimeStr(r.start)
    if r.start <= nowSec then timeText = "has started"

    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title   = "Reminder"
    dialog.message = r.title + " " + timeText + " on " + chLabel + "."
    if ch <> invalid
        dialog.buttons = ["Watch Now", "Dismiss"]
    else
        ' Hidden or no longer loaded: nothing to tune to.
        dialog.buttons = ["OK"]
    end if
    m.remindCh = ch
    m.remindDialog = dialog
    dialog.observeField("buttonSelected", "onReminderButton")
    dialog.observeField("wasClosed", "closeReminderDialog")
    m.top.dialog = dialog
end sub

sub onReminderButton()
    dialog = m.remindDialog
    if dialog = invalid then return
    ch = m.remindCh
    watch = ch <> invalid and dialog.buttonSelected = 0
    closeReminderDialog()
    if watch then openPlayer(ch)
end sub

' Back, Dismiss or OK: close and give focus back to whichever scene is up.
sub closeReminderDialog()
    dialog = m.remindDialog
    if dialog = invalid then return
    m.remindDialog = invalid
    m.remindCh = invalid
    dialog.unobserveField("buttonSelected")
    dialog.unobserveField("wasClosed")
    m.top.dialog = invalid
    if m.playerScene <> invalid and m.playerScene.visible
        m.playerScene.setFocus(true)
    else if m.guideScene <> invalid and m.guideScene.visible
        m.guideScene.setFocus(true)
    end if
end sub

sub showErrorDialog(msg as string)
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = "Connection Error"
    dialog.message = msg
    dialog.buttons = ["OK"]
    dialog.observeField("buttonSelected", "onErrorDialogClose")
    ' A dialog before the launch beacon has to be bracketed by these two.
    if not m.launchSignalled then m.top.signalBeacon("AppDialogInitiate")
    m.top.dialog = dialog
end sub

sub onErrorDialogClose()
    m.top.dialog = invalid
    if not m.launchSignalled then m.top.signalBeacon("AppDialogComplete")
    action = m.afterDialogAction
    m.afterDialogAction = ""
    if action = "openGuide"
        finishFetch()
    else if action = "showError"
        showInitialError(m.pendingErrorMsg)
    end if
end sub

' ── Guide ─────────────────────────────────────────────────────────────────────

sub openGuide()
    if m.guideScene <> invalid
        m.top.removeChild(m.guideScene)
        m.guideScene = invalid
    end if
    m.guideScene = m.top.createChild("GuideScene")
    m.guideScene.observeField("action",          "onGuideAction")
    m.guideScene.observeField("selectedChannel", "onGuideSelectedChannel")
    m.guideScene.observeField("menuAction",      "onGuideMenuAction")
    m.guideScene.filterKey      = m.guideFilter
    m.guideScene.observeField("filterKey",       "onGuideFilterKey")
    m.guideScene.guideData      = guideData()
    m.guideScene.currentChannel = m.currentChannel
    m.guideScene.windowStart    = currentHalfHour()
    m.guideScene.visible        = true
    m.guideScene.setFocus(true)
    if m.guideFocusId <> ""
        m.guideScene.scrollToChannelId = m.guideFocusId
        m.guideFocusId = ""
    end if
    if m.playerScene <> invalid then m.playerScene.visible = false
    hideLoading()
    hideError()
    launchComplete()
end sub

sub onGuideAction()
    action = m.guideScene.action
    if action = "openSettings"
        openSettings()
    else if action = "back"
        showExitDialog()
    end if
end sub

' Back in the guide. The guide is the home screen, so Back offers to exit
' (certification 4.6: Back must lead out of the app, never loop guide <-> player).
' With a channel in the PIP the first button goes back to it fullscreen.
sub showExitDialog()
    if m.top.dialog <> invalid then return
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = "Exit GuideBox?"
    if m.currentChannel <> invalid
        dialog.buttons = ["Watch " + m.currentChannel.name, "Exit"]
    else
        dialog.buttons = ["Exit", "Cancel"]
    end if
    m.exitDialog = dialog
    dialog.observeField("buttonSelected", "onExitButton")
    dialog.observeField("wasClosed", "closeExitDialog")
    m.top.dialog = dialog
end sub

sub onExitButton()
    dialog = m.exitDialog
    if dialog = invalid then return
    label = dialog.buttons[dialog.buttonSelected]
    closeExitDialog()
    if label = "Exit"
        m.top.exitApp = true
    else if label <> "Cancel" and m.currentChannel <> invalid
        ' The player stopped its video when it handed off to the guide (only one
        ' decoder is available and PIP needs it), so playback must be restarted.
        showPlayer(m.currentChannel)
    end if
end sub

' Back on the dialog is the same as Cancel.
sub closeExitDialog()
    dialog = m.exitDialog
    if dialog = invalid then return
    m.exitDialog = invalid
    dialog.unobserveField("buttonSelected")
    dialog.unobserveField("wasClosed")
    m.top.dialog = invalid
    if m.guideScene <> invalid and m.guideScene.visible then m.guideScene.setFocus(true)
end sub

' ── Deep linking ─────────────────────────────────────────────────────────────

' Launch args or roInput (main.brs). contentId is a channel id, with or without
' its "<source>_" prefix, so a playlist's own tvg-id works (e.g. "dw-english").
sub onDeepLink()
    link = m.top.deepLink
    if link = invalid or link.contentId = invalid then return
    print "[MainScene] deep link " + link.contentId.toStr()
    m.pendingLink = link
    ' Mid-fetch or first launch: finishFetch applies it once channels are in.
    if m.activeFetch = invalid and m.channels.count() > 0 then applyDeepLink()
end sub

' Plays the linked channel fullscreen over the guide, so Back lands on the guide.
' An unknown id just leaves the guide up.
sub applyDeepLink()
    link = m.pendingLink
    if link = invalid then return
    m.pendingLink = invalid
    id = link.contentId.toStr()
    ch = invalid
    for each c in m.channels
        if c.id = id or Mid(c.id, Instr(1, c.id, "_") + 1) = id
            ch = c
            exit for
        end if
    end for
    if ch = invalid
        print "[MainScene] deep link: no channel " + id
        return
    end if
    if m.settingsScene <> invalid
        m.top.removeChild(m.settingsScene)
        m.settingsScene = invalid
    end if
    closeExitDialog()
    if m.guideScene = invalid or not m.guideScene.visible then openGuide()
    openPlayer(ch)
end sub

' Long-press OK menu in the guide: { action, channel }.
sub onGuideMenuAction()
    req = m.guideScene.menuAction
    if req = invalid or req.channel = invalid then return
    if req.action = "hide"
        ch = req.channel
        hideChannel(ch)
        ' No scroll: the grid keeps the cursor row, so the next channel lands on it.
        removeFromGuide(ch.id, false)
        m.guideScene.callFunc("showToast", "Hidden. Settings > Hidden Channels to undo.")
    else if req.action = "fav_add" or req.action = "fav_remove"
        isFav = (req.action = "fav_add")
        setFavorite(req.channel, isFav)
        m.favIds = favoriteIds()
        ' Toast first: removing the last favorite under the Favorites filter
        ' makes the guide toast that it is back to all channels.
        if isFav
            m.guideScene.callFunc("showToast", "Added to Favorites.")
        else
            m.guideScene.callFunc("showToast", "Removed from Favorites.")
        end if
        m.guideScene.guideData = guideData()
    else if (req.action = "remind_set" or req.action = "remind_cancel") and req.program <> invalid
        prog = req.program
        if req.action = "remind_set"
            setReminder(req.channel, prog)
            m.guideScene.callFunc("showToast", "Reminder set for " + epochToTimeStr(prog.start) + ".")
        else
            deleteReminder(reminderKey(req.channel.id, prog.start))
            m.guideScene.callFunc("showToast", "Reminder cancelled.")
        end if
        m.reminders = readReminders()
        markReminders()
        m.guideScene.guideData = guideData()
    else if Left(req.action, 7) = "record_" and req.program <> invalid
        startDvrRequest(Mid(req.action, 8), req.channel, req.program)
    end if
end sub

' Refilter after a channel was hidden (menu or unsupported codec) and push the
' result to the guide. focusAbove: put the cursor on the channel above it (the
' player hands back to a guide that has lost the channel it came from). A
' hidden current / previous channel is forgotten, so PIP, Back and last-channel
' never tune to it.
sub removeFromGuide(chId as string, focusAbove as boolean)
    focusId = ""
    if focusAbove
        for i = 0 to m.channels.count() - 1
            if m.channels[i].id = chId
                if i > 0 then focusId = m.channels[i - 1].id
                exit for
            end if
        end for
    end if
    m.channels = filterHiddenChannels(m.allChannels)
    if m.previousChannel <> invalid and m.previousChannel.id = chId then m.previousChannel = invalid
    if m.currentChannel <> invalid and m.currentChannel.id = chId
        m.currentChannel = invalid
        if m.guideScene <> invalid then m.guideScene.currentChannel = invalid
    end if
    m.guideFocusId = focusId
    if m.guideScene <> invalid
        m.guideScene.guideData = guideData()
        if focusId <> "" then m.guideScene.scrollToChannelId = focusId
    end if
end sub

sub onGuideFilterKey()
    m.guideFilter = m.guideScene.filterKey
end sub

sub onGuideSelectedChannel()
    ch = m.guideScene.selectedChannel
    if ch = invalid then return
    openPlayer(ch)
end sub

' ── Player ───────────────────────────────────────────────────────────────────

sub openPlayer(ch as object)
    m.previousChannel = m.currentChannel
    m.currentChannel  = ch
    saveLastChannelId(ch.id)
    showPlayer(ch)
end sub

' Show the fullscreen player and (re)start playback of ch. Stops PIP first.
sub showPlayer(ch as object)
    if m.guideScene <> invalid
        m.guideScene.currentChannel = invalid
        m.guideScene.visible = false
    end if

    if m.playerScene = invalid
        m.playerScene = m.top.createChild("PlayerScene")
        m.playerScene.observeField("action", "onPlayerAction")
    end if
    m.playerScene.visible = true
    m.playerScene.focusedProgram = buildFocusedProgram(ch)
    m.playerScene.channel = ch
    m.playerScene.setFocus(true)
end sub

function buildFocusedProgram(ch as object) as object
    fp = { channel: ch, program: invalid }
    if ch = invalid then return fp
    if not m.programs.doesExist(ch.id) then return fp
    nowSec = nowEpoch()
    for each prog in m.programs[ch.id]
        if prog.start <= nowSec and prog.stop > nowSec
            fp.program = prog
            return fp
        end if
    end for
    return fp
end function

sub onPlayerAction()
    action = m.playerScene.action
    if action = "refreshNowPlaying"
        if m.currentChannel <> invalid then m.playerScene.focusedProgram = buildFocusedProgram(m.currentChannel)
    else if action = "backToGuide"
        if m.guideScene = invalid
            openGuide()
        else
            ' The guide may have been hidden for hours; bring its window back
            ' to the current half hour before it is shown again.
            m.guideScene.windowStart    = currentHalfHour()
            m.guideScene.currentChannel = m.currentChannel
            m.guideScene.visible        = true
            m.guideScene.setFocus(true)
            m.playerScene.visible       = false
        end if
    else if action = "channelUnsupported"
        if m.currentChannel <> invalid
            blacklistChannel(m.currentChannel)
            removeFromGuide(m.currentChannel.id, true)
        end if
    else if action = "lastChannel"
        if m.previousChannel <> invalid
            openPlayer(m.previousChannel)
        end if
    else if action = "tokenExpired"
        ' Re-fetch M3U only; onFetchComplete will call updatePlayerWithFreshUrl.
        triggerFetch(true)
    end if
end sub

sub updatePlayerWithFreshUrl()
    if m.currentChannel = invalid or m.playerScene = invalid then return
    for each ch in m.channels
        if ch.id = m.currentChannel.id
            m.currentChannel = ch
            ' Use refreshUrl to avoid resetting retryCount in onChannelChange.
            m.playerScene.refreshUrl = ch.streamUrl
            return
        end if
    end for
    m.playerScene.callFunc("showError", "Channel no longer available.")
end sub

' ── Background refresh ────────────────────────────────────────────────────────

sub startRefreshTimer()
    settings = readSettings()
    m.refreshTask = m.top.createChild("RefreshTimerTask")
    m.refreshTask.intervalMin = settings.refreshIntervalMin
    m.refreshTask.observeField("tick", "onRefreshTick")
    m.refreshTask.control = "RUN"
end sub

sub onRefreshTick()
    ' Don't show loading UI for background refresh.
    if m.bgFetch <> invalid
        m.top.removeChild(m.bgFetch)
        m.bgFetch = invalid
    end if
    m.bgFetch = startFetchTask(false, "onBackgroundFetchComplete")
end sub

sub onBackgroundFetchComplete()
    task = m.bgFetch
    if task = invalid then return
    if task.state = "run" or task.state = "init" then return

    hasChannels = task.channels.count() > 0

    if not hasChannels
        if m.guideScene <> invalid
            m.guideScene.callFunc("showToast", "Background refresh failed.")
        end if
        m.top.removeChild(task)
        m.bgFetch = invalid
        return
    end if

    merged = mergeFetchResult(task)
    m.allChannels = merged.channels
    m.channels = filterHiddenChannels(m.allChannels)
    m.programs = merged.programs
    markRecordings()
    markReminders()
    fetchRecordings()

    if m.guideScene <> invalid
        m.guideScene.guideData = guideData()
        if task.error <> ""
            m.guideScene.callFunc("showToast", "One source failed to refresh.")
        end if
    end if

    if m.currentChannel <> invalid
        for each ch in m.channels
            if ch.id = m.currentChannel.id
                m.currentChannel = ch
                exit for
            end if
        end for
    end if

    m.top.removeChild(task)
    m.bgFetch = invalid
end sub

sub updateRefreshTaskSettings()
    if m.refreshTask = invalid then return
    settings = readSettings()
    m.refreshTask.intervalMin = settings.refreshIntervalMin
end sub
