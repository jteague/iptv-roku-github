sub Main(args as dynamic)
    screen = CreateObject("roSGScreen")
    m.port = CreateObject("roMessagePort")
    screen.setMessagePort(m.port)
    scene = screen.CreateScene("MainScene")
    screen.show()
    scene.observeField("exitApp", m.port)

    ' Deep link at launch, and later ones while running (roInput).
    if args <> invalid and args.contentId <> invalid
        scene.deepLink = { contentId: args.contentId, mediaType: args.mediaType }
    end if
    input = CreateObject("roInput")
    input.setMessagePort(m.port)
    startMemoryMonitor(m.port)

    while true
        msg = wait(0, m.port)
        msgType = type(msg)
        if msgType = "roSGScreenEvent"
            if msg.isScreenClosed() then return
        else if msgType = "roSGNodeEvent"
            if msg.getField() = "exitApp" then return
        else if msgType = "roInputEvent"
            if msg.isInput()
                info = msg.getInfo()
                if info.contentId <> invalid
                    scene.deepLink = { contentId: info.contentId, mediaType: info.mediaType }
                end if
            end if
        else if msgType = "roAppMemoryNotificationEvent"
            print "Memory warning: "; FormatJson(msg.getInfo())
        else if msgType = "roDeviceInfoEvent"
            info = msg.getInfo()
            if info.generalMemoryLevel <> invalid then print "Device memory level: "; info.generalMemoryLevel
        end if
    end while
end sub

' Logs the app's memory limit and low-memory warnings: roAppMemoryMonitor for
' this app's own limit, roDeviceInfo for the device's general memory level.
' Some of these calls need a newer Roku OS than the manifest minimum.
sub startMemoryMonitor(port as object)
    try
        mon = CreateObject("roAppMemoryMonitor")
        if mon <> invalid
            mon.setMessagePort(port)
            mon.EnableMemoryWarningEvent(true)
            m.memMonitor = mon
            limit = mon.GetChannelMemoryLimit()
            print "Memory: limit "; Int(limit.maxForegroundMemory / 1024); " MB, "; mon.GetMemoryLimitPercent(); "% used"
        end if
        di = CreateObject("roDeviceInfo")
        di.setMessagePort(port)
        di.EnableLowGeneralMemoryEvent(true)
        m.memDeviceInfo = di
    catch e
        print "Memory monitor unavailable: "; e.message
    end try
end sub
