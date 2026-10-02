sub init()
    m.MAX_RETRIES = 2
    m.video     = m.top.findNode("video")
    m.spinnerBg = m.top.findNode("spinnerBg")
    m.spinner   = m.top.findNode("spinner")
    m.errBg     = m.top.findNode("errBg")
    m.errLabel  = m.top.findNode("errLabel")
    m.panel     = m.top.findNode("nowPlayingPanel")
    m.panelTimer = m.top.findNode("panelTimer")
    m.countdown  = m.panel.findNode("countdown")
    m.countdown.duration = m.panelTimer.duration

    m.retryCount = 0
    m.codecError = false
    m.codecRetried = false
    m.video.observeField("state", "onVideoState")
    m.panelTimer.observeField("fire", "onPanelTimer")
end sub

sub onChannelChange()
    ch = m.top.channel
    if ch = invalid then return
    m.retryCount = 0
    m.codecRetried = false
    m.top.action = ""
    ' Only the built-in sample (a film, not a live channel) loops.
    m.video.loop = ch.doesExist("loop")
    playChannel(ch.streamUrl)
end sub

sub onRefreshUrl()
    url = m.top.refreshUrl
    if url = "" then return
    m.top.action = ""
    playChannel(url)
end sub

sub playChannel(streamUrl as string)
    print "[PlayerScene] loading stream: " + streamUrl
    m.codecError = false
    hideError()
    showSpinner()
    content = CreateObject("roSGNode", "ContentNode")
    content.url = streamUrl
    if Instr(LCase(streamUrl), ".m3u8") > 0
        content.streamFormat = "hls"
    else
        ' Live IPTV/tuner streams that aren't HLS (e.g. HDHomeRun's raw tuner
        ' output) are MPEG-TS, not an MP4 container.
        content.streamFormat = "ts"
    end if
    m.video.content = content
    m.video.control = "play"
    m.video.setFocus(true)
end sub

sub onVideoState()
    state = m.video.state
    if state = "buffering"
        showSpinner()
    else if state = "playing"
        hideSpinner()
        m.retryCount = 0
    else if state = "error"
        hideSpinner()
        errCode = m.video.errorCode
        errMsg  = m.video.errorMsg
        print "[PlayerScene] error code=" + errCode.toStr() + " msg=" + errMsg
        if errCode = -5
            m.codecError = true
            m.video.control = "stop"
            if not m.codecRetried
                ' -5 is also what a proxy's error stream looks like (Dispatcharr
                ' sends one TS packet of error text when the upstream fails), so
                ' re-fetch and try once more before hiding the channel.
                m.codecRetried = true
                showSpinner()
                m.top.action = "tokenExpired"
            else
                showError("Codec not compatible with this device. Channel will be excluded for 14 days.")
                m.top.action = "channelUnsupported"
            end if
        else
            retryOrShowNoSignal()
        end if
    else if state = "finished"
        ' A live channel has no legitimate "end"; reaching this state with
        ' nothing played (e.g. a tuner returning an empty response) is a
        ' failure just like "error", not a graceful stop.
        hideSpinner()
        if not m.codecError then retryOrShowNoSignal()
    end if
end sub

sub retryOrShowNoSignal()
    if m.retryCount < m.MAX_RETRIES
        m.retryCount = m.retryCount + 1
        m.top.action = "tokenExpired"
    else
        showError("No signal on this channel right now. Try another channel.")
    end if
end sub

' Only feed the panel while it is visible: it downloads the poster and lays out
' badges on every set, and it may never be shown.
sub onFocusedProgramChange()
    if m.panel.visible then m.panel.focusedProgram = m.top.focusedProgram
end sub

sub onPanelTimer()
    hidePanel()
end sub

sub hidePanel()
    m.panel.visible = false
    m.panelTimer.control = "stop"
    m.countdown.control  = "stop"
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "up"
        if m.panel.visible
            hidePanel()
        else
            m.panel.visible = true
            m.panelTimer.control = "start"
            m.countdown.control  = "start"
            ' Ask MainScene for the programme airing now; it answers by setting
            ' focusedProgram, which onFocusedProgramChange forwards to the panel.
            m.top.action = "refreshNowPlaying"
        end if
        return true
    end if
    if key = "back"
        if m.panel.visible
            hidePanel()
        else
            m.video.control = "stop"
            m.top.action = "backToGuide"
        end if
        return true
    end if
    if key = "down"
        m.top.action = "lastChannel"
        return true
    end if
    return false
end function

sub showSpinner()
    m.spinnerBg.visible = true
    m.spinner.visible   = true
end sub

sub hideSpinner()
    m.spinnerBg.visible = false
    m.spinner.visible   = false
end sub

sub showError(msg as string)
    m.errLabel.text   = msg
    m.errBg.visible   = true
    m.errLabel.visible = true
end sub

sub hideError()
    m.errBg.visible    = false
    m.errLabel.visible = false
end sub
