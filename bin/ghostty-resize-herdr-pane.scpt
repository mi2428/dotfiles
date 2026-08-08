#!/usr/bin/osascript

-- Resize the Herdr pane in every Ghostty window to a fixed width.
-- Change this value to adjust the target width in pixels.
property herdrWidth : 700
property ghosttyApplicationPath : "/Applications/Ghostty.app"
property ghosttyBundleIdentifier : "com.mitchellh.ghostty"

on run
    if herdrWidth is less than or equal to 0 then error "herdrWidth must be greater than zero"

    tell application "System Events"
        set ghosttyProcess to missing value
        repeat with candidateProcess in (application processes whose bundle identifier is ghosttyBundleIdentifier)
            if POSIX path of application file of candidateProcess is ghosttyApplicationPath then
                set ghosttyProcess to contents of candidateProcess
                exit repeat
            end if
        end repeat
        if ghosttyProcess is missing value then error "Ghostty is not running from " & ghosttyApplicationPath
    end tell

    using terms from application "Ghostty"
        tell application ghosttyApplicationPath
            set workspaceWindows to every window
            if (count of workspaceWindows) is 0 then error "Ghostty has no windows"
            set originalFrontWindow to front window
        end tell
    end using terms from

    set resizedCount to 0
    set unchangedCount to 0
    set skippedCount to 0

    repeat with workspaceWindow in workspaceWindows
        set resizeResult to my resizeHerdrPane(workspaceWindow, ghosttyProcess)
        if resizeResult is "resized" then
            set resizedCount to resizedCount + 1
        else if resizeResult is "unchanged" then
            set unchangedCount to unchangedCount + 1
        else
            set skippedCount to skippedCount + 1
        end if
    end repeat

    using terms from application "Ghostty"
        tell application ghosttyApplicationPath to activate window originalFrontWindow
    end using terms from

    return "Herdr panes: " & resizedCount & " resized, " & unchangedCount & " unchanged, " & skippedCount & " skipped"
end run

on resizeHerdrPane(workspaceWindow, ghosttyProcess)
    set herdrPane to missing value

    with timeout of 5 seconds
        using terms from application "Ghostty"
            tell application ghosttyApplicationPath
                repeat with candidatePane in terminals of workspaceWindow
                    if name of candidatePane contains "herdr" then
                        set herdrPane to candidatePane
                        exit repeat
                    end if
                end repeat

                if herdrPane is missing value then return "skipped"
                activate window workspaceWindow
                focus herdrPane
            end tell
        end using terms from
    end timeout

    delay 0.05

    tell application "System Events"
        tell ghosttyProcess
            set ghosttyWindow to front window
            set windowPosition to position of ghosttyWindow
            set windowSize to size of ghosttyWindow
            set windowMidpoint to (item 1 of windowPosition) + ((item 1 of windowSize) / 2)

            set targetArea to missing value
            set splitGroup to group 1 of group 1 of ghosttyWindow
            repeat with paneGroup in groups of splitGroup
                try
                    set paneArea to text area 1 of scroll area 1 of paneGroup
                    if value of attribute "AXFocused" of paneArea then
                        set targetArea to paneArea
                        exit repeat
                    end if
                end try
            end repeat

            if targetArea is missing value then error "Could not identify the focused Herdr pane"

            set panePosition to position of targetArea
            set paneSize to size of targetArea
            set currentWidth to item 1 of paneSize
            set herdrIsLeftPane to (item 1 of panePosition) < windowMidpoint
        end tell
    end tell

    set widthDelta to herdrWidth - currentWidth
    if widthDelta is 0 then return "unchanged"

    if widthDelta is greater than 0 then
        set resizeAmount to widthDelta
        if herdrIsLeftPane then
            set resizeDirection to "right"
        else
            set resizeDirection to "left"
        end if
    else
        set resizeAmount to -widthDelta
        if herdrIsLeftPane then
            set resizeDirection to "left"
        else
            set resizeDirection to "right"
        end if
    end if

    with timeout of 5 seconds
        using terms from application "Ghostty"
            tell application ghosttyApplicationPath
                perform action ("resize_split:" & resizeDirection & "," & resizeAmount) on herdrPane
                focus herdrPane
            end tell
        end using terms from
    end timeout

    return "resized"
end resizeHerdrPane
