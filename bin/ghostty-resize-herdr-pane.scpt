#!/usr/bin/osascript

-- Resize the Herdr pane in the frontmost Ghostty window to a fixed width.
-- Change this value to adjust the target width in pixels.
property herdrWidth : 700

on run
    if herdrWidth is less than or equal to 0 then error "herdrWidth must be greater than zero"

    set herdrPane to missing value

    with timeout of 5 seconds
        tell application "Ghostty"
            if not running then error "Ghostty is not running"

            set workspaceWindow to front window
            repeat with candidatePane in terminals of workspaceWindow
                if name of candidatePane contains "herdr" then
                    set herdrPane to candidatePane
                    exit repeat
                end if
            end repeat

            if herdrPane is missing value then error "No Herdr pane found in the frontmost Ghostty window"
            focus herdrPane
        end tell
    end timeout

    delay 0.05

    tell application "System Events"
        tell process "Ghostty"
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
    if widthDelta is 0 then return "Herdr pane width is already " & herdrWidth & "px"

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
        tell application "Ghostty"
            perform action ("resize_split:" & resizeDirection & "," & resizeAmount) on herdrPane
            focus herdrPane
        end tell
    end timeout

    return "Herdr pane width: " & currentWidth & "px -> " & herdrWidth & "px"
end run
