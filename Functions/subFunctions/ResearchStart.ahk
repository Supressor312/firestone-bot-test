; ResearchStart_UPDATED.ahk
;
; v8 update - CRITICAL FIX for v7's "nothing happens" bug.
;
; ROOT CAUSE (confirmed via the v7 debug log): FullTreeScrollTicks,
; PageStepTicks and MaxResearchAttempts were declared as top-level
; "global X := value" statements outside any function. Top-level code like
; that only runs as part of the script's auto-execute section - and
; Gui.ahk (included BEFORE this file, via Research.ahk) ends with a
; top-level "Return", which terminates the auto-execute section right
; there. Everything textually after that point (including these
; assignments, since this file is #Included later) never runs. The
; variables stayed permanently empty, so "Loop, %FullTreeScrollTicks%"
; became "Loop, %blank%" - zero iterations, hence zero scrolling, zero
; scanning, immediate "attempt cap (blank) reached" exit. This is why the
; log showed blank values everywhere a number was expected.
;
; FIX: these three values are no longer global at all - they're declared
; as plain local variables at the very top of ResearchStart(), so they are
; guaranteed to be (re-)assigned every single time the function runs,
; regardless of include order or auto-execute section quirks.
;
; Everything else is unchanged from v7 (full logging to ResearchDebug.log,
; rightmost-column-always-wins scan logic, camera walk, attempt cap,
; row-priority rotation). See ResearchStart_Algorithm_v6.md for the full
; plain-language description of the core algorithm.

#Include Functions\subFunctions\ResearchClicks.ahk

; Writes a single timestamped line to ResearchDebug.log in the bot's working
; directory. Never blocks, never disappears - just open the file afterward.
LogMsg(Text){
    FormatTime, TimeStamp,, yyyy-MM-dd HH:mm:ss
    FileAppend, %TimeStamp% - %Text%`n, ResearchDebug.log
}

ResearchStart() {
    ; --- Local constants (NOT global - see the v8 fix note above) ---
    FullTreeScrollTicks := 60   ; total wheel ticks to cover the whole tree width
    PageStepTicks := 5          ; wheel ticks per camera-walk step
    MaxResearchAttempts := 10   ; hard safety cap on clicks per call

    LogMsg("=== ResearchStart() called ===")
    LogMsg("Config: FullTreeScrollTicks=" . FullTreeScrollTicks . " PageStepTicks=" . PageStepTicks . " MaxResearchAttempts=" . MaxResearchAttempts)
    LogMsg("Slot1InProcess at entry: " . Slot1InProcess . " | Slot2InProcess at entry: " . Slot2InProcess)

    MouseMove, 1429, 944

    If (Slot2InProcess = 1)
    {
        LogMsg("EXIT: Slot2InProcess = 1 at entry, both slots already busy - nothing to do.")
        Return
    }

    Sleep, 1000

    ; --- Row priority: rotates Top -> Middle -> Bottom -> Top every call ---
    priorityFile := "ResearchPriority.ini"
    IniRead, RowStart, %priorityFile%, State, RowStart, Top
    RowOrder := BuildRowOrder(RowStart)
    NextRowStart := NextRow(RowStart)
    IniWrite, %NextRowStart%, %priorityFile%, State, RowStart
    LogMsg("Row priority this call: [" . RowStart . "] -> next call will be [" . NextRowStart . "]")

    ; --- Column scan direction: Left (default) or Right ---
    IniRead, ColDirection, settings.ini, QoL/RareOptions, ResearchDirection, Left
    LogMsg("ColDirection read as: [" . ColDirection . "] (length=" . StrLen(ColDirection) . ")")

    AttemptCount := 0

    If (ColDirection = "Right")
    {
        LogMsg("Entering RIGHT branch. Scrolling " . FullTreeScrollTicks . " ticks right (WheelDown) before any scan.")

        Loop, %FullTreeScrollTicks%
        {
            Send, {WheelDown}
            Sleep, 200
        }
        LogMsg("Finished initial scroll-right. Beginning camera walk back to the left.")

        CurrentPos := FullTreeScrollTicks

        Loop
        {
            If (CurrentPos = 0)
            {
                Width := 50
            }
            Else
            {
                Width := 100
            }
            LogMsg("Scanning at CurrentPos=" . CurrentPos . " (Width=" . Width . ")")

            DrainCurrentScreen(RowOrder, Width, AttemptCount, MaxResearchAttempts)

            LogMsg("After DrainCurrentScreen: AttemptCount=" . AttemptCount . " Slot1=" . Slot1InProcess . " Slot2=" . Slot2InProcess)

            If (AttemptCount >= MaxResearchAttempts)
            {
                LogMsg("STOP: attempt cap (" . MaxResearchAttempts . ") reached.")
                Break
            }
            If (Slot2InProcess = 1)
            {
                LogMsg("STOP: both slots now full.")
                Break
            }
            If (CurrentPos = 0)
            {
                LogMsg("STOP: reached the true default page, nothing left anywhere.")
                Break
            }

            If (CurrentPos < PageStepTicks)
            {
                StepTicks := CurrentPos
            }
            Else
            {
                StepTicks := PageStepTicks
            }
            LogMsg("Stepping left by " . StepTicks . " ticks (WheelUp).")
            Loop, %StepTicks%
            {
                Send, {WheelUp}
                Sleep, 200
            }
            CurrentPos -= StepTicks
        }

        If (CurrentPos > 0)
        {
            LogMsg("Restoring view: scrolling " . CurrentPos . " ticks back up (WheelUp) to reach the default page.")
            Loop, %CurrentPos%
            {
                Send, {WheelUp}
                Sleep, 200
            }
        }
    }
    Else
    {
        LogMsg("Entering LEFT branch. Starting scan on the default (unscrolled) page - no initial scroll.")

        CurrentPos := 0

        Loop
        {
            If (CurrentPos = 0)
            {
                Width := 50
            }
            Else
            {
                Width := 100
            }
            LogMsg("Scanning at CurrentPos=" . CurrentPos . " (Width=" . Width . ")")

            DrainCurrentScreen(RowOrder, Width, AttemptCount, MaxResearchAttempts)

            LogMsg("After DrainCurrentScreen: AttemptCount=" . AttemptCount . " Slot1=" . Slot1InProcess . " Slot2=" . Slot2InProcess)

            If (AttemptCount >= MaxResearchAttempts)
            {
                LogMsg("STOP: attempt cap (" . MaxResearchAttempts . ") reached.")
                Break
            }
            If (Slot2InProcess = 1)
            {
                LogMsg("STOP: both slots now full.")
                Break
            }
            If (CurrentPos = FullTreeScrollTicks)
            {
                LogMsg("STOP: reached the far-right edge, nothing left anywhere.")
                Break
            }

            RemainingToEdge := FullTreeScrollTicks - CurrentPos
            If (RemainingToEdge < PageStepTicks)
            {
                StepTicks := RemainingToEdge
            }
            Else
            {
                StepTicks := PageStepTicks
            }
            LogMsg("Stepping right by " . StepTicks . " ticks (WheelDown).")
            Loop, %StepTicks%
            {
                Send, {WheelDown}
                Sleep, 200
            }
            CurrentPos += StepTicks
        }

        If (CurrentPos > 0)
        {
            LogMsg("Restoring view: scrolling " . CurrentPos . " ticks back up (WheelUp) to reach the default page.")
            Loop, %CurrentPos%
            {
                Send, {WheelUp}
                Sleep, 200
            }
        }
    }

    LogMsg("=== ResearchStart() finished ===")
}

; Repeatedly re-scans the CURRENT screen from scratch (right to left) and
; clicks the single best (rightmost) available match each time, until either
; the attempt cap is reached, both slots are full, or a fresh scan finds
; nothing left at all.
DrainCurrentScreen(RowOrder, Width, ByRef AttemptCount, MaxAttempts){
    Loop
    {
        If (AttemptCount >= MaxAttempts)
        {
            Return
        }
        If (Slot2InProcess = 1)
        {
            Return
        }
        Found := ScanScreenFully(RowOrder, Width)
        If (Found = 0)
        {
            LogMsg("  ScanScreenFully found nothing on this screen.")
            Return
        }
        LogMsg("  ScanScreenFully found and clicked a candidate. Calling ResearchClicks().")
        ResearchClicks()
        AttemptCount += 1
    }
}

; Scans the entire visible screen once, column by column, strictly right to
; left. Returns 1 and stops as soon as ONE match is clicked, or 0 if nothing
; is found anywhere.
ScanScreenFully(RowOrder, WidthOffset){
    Loop
    {
        XCheck := 1700 - ((A_Index - 1) * 100)
        if (XCheck < 100)
            break
        Found := SearchColumnRows(XCheck, XCheck + WidthOffset, RowOrder)
        If (Found = 1)
        {
            Return 1
        }
    }
    Return 0
}

; Builds a 3-element row order starting at StartRow, cycle Top->Middle->Bottom->Top.
BuildRowOrder(StartRow){
    Cycle := ["Top","Middle","Bottom"]
    StartIndex := 1
    For i, v in Cycle
    {
        If (v = StartRow)
        {
            StartIndex := i
            Break
        }
    }
    Order := []
    Loop, 3
    {
        idx := Mod(StartIndex - 1 + A_Index - 1, 3) + 1
        Order.Insert(Cycle[idx])
    }
    Return Order
}

; Returns the next row in the fixed cycle Top -> Middle -> Bottom -> Top.
NextRow(CurrentRow){
    If (CurrentRow = "Top")
        Return "Middle"
    Else If (CurrentRow = "Middle")
        Return "Bottom"
    Else
        Return "Top"
}

; Searches one column (X1..X2) split into Top/Middle/Bottom row bands, in the
; order given by RowOrder. Clicks the first matching pixel found and returns
; 1, or 0 if nothing found in that column.
SearchColumnRows(X1, X2, RowOrder){
    TopY1 := 140, TopY2 := 380
    MidY1 := 350, MidY2 := 620
    BotY1 := 590, BotY2 := 900

    For index, RowName in RowOrder
    {
        If (RowName = "Top")
        {
            Y1 := TopY1, Y2 := TopY2
        }
        Else If (RowName = "Middle")
        {
            Y1 := MidY1, Y2 := MidY2
        }
        Else
        {
            Y1 := BotY1, Y2 := BotY2
        }
        PixelSearch, X, Y, X1, Y1, X2, Y2, 0x0D49DE, 0, Fast RGB
        If (ErrorLevel = 0)
        {
            MouseClick, Left, X, Y, 1, 0
            Sleep, 500
            Return 1
        }
    }
    Return 0
}