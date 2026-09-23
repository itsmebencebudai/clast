# >>> COPYLAST BEGIN >>>

# =====================================================================
# CopyLast v5
#
# Codex-style copy of the previous PowerShell command + visible output.
#
# Commands:
#
#   clast
#   copylast
#   copylast-show
#   copylast-reset
#
# v5 intentionally does NOT replace PowerShell's prompt.
#
# Native command output is flushed by briefly stopping Start-Transcript
# when CopyLast is invoked.
# =====================================================================

$global:CopyLastVersion = "5.0.0"


# ---------------------------------------------------------------------
# Strip OSC / ANSI / terminal control sequences
# ---------------------------------------------------------------------

function global:Remove-CopyLastEscapes {

    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )

    if ($null -eq $Text) {
        return ""
    }


    $esc = [char]27
    $bel = [char]7


    # OSC
    #
    # ESC ] ... BEL
    # ESC ] ... ESC \
    #
    # Includes Windows Terminal / VS Code OSC 633 sequences.

    $oscPattern =
        [regex]::Escape("$esc]") +
        '.*?(?:' +
        [regex]::Escape([string]$bel) +
        '|' +
        [regex]::Escape("$esc\") +
        ')'


    $Text = [regex]::Replace(
        $Text,
        $oscPattern,
        '',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )


    # CSI / ANSI colors and formatting

    $csiPattern =
        [regex]::Escape("$esc[") +
        '[0-?]*[ -/]*[@-~]'


    $Text = [regex]::Replace(
        $Text,
        $csiPattern,
        ''
    )


    # Other simple ESC sequences

    $Text = [regex]::Replace(
        $Text,
        [regex]::Escape([string]$esc) + '[@-_]',
        ''
    )


    # Remove remaining control characters except:
    # TAB / LF / CR

    $Text = [regex]::Replace(
        $Text,
        '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]',
        ''
    )


    return $Text
}


# ---------------------------------------------------------------------
# Start our transcript
# ---------------------------------------------------------------------

function global:Start-CopyLastTranscript {

    $state = $global:CopyLastState


    try {

        Start-Transcript `
            -Path $state.Transcript `
            -Append `
            -Force `
            -ErrorAction Stop |
            Out-Null


        $state.TranscriptRunning = $true

        return $true
    }
    catch {

        $state.TranscriptRunning = $false

        return $false
    }
}


# ---------------------------------------------------------------------
# Stop transcript and force everything to disk
# ---------------------------------------------------------------------

function global:Stop-CopyLastTranscript {

    $state = $global:CopyLastState


    if (-not $state.TranscriptRunning) {
        return
    }


    try {

        Stop-Transcript `
            -ErrorAction Stop |
            Out-Null
    }
    catch {
    }
    finally {

        $state.TranscriptRunning = $false
    }
}


# ---------------------------------------------------------------------
# Is this one of our own helper commands?
# ---------------------------------------------------------------------

function global:Test-CopyLastHelperCommand {

    param(
        [AllowEmptyString()]
        [string]$Command
    )


    if ([string]::IsNullOrWhiteSpace($Command)) {
        return $false
    }


    return (
        $Command -match
        '^\s*(clast|copylast|copylast-show|copylast-reset)(\s|$)'
    )
}


# ---------------------------------------------------------------------
# Find previous real command
# ---------------------------------------------------------------------

function global:Get-CopyLastHistoryCommand {

    $items =
        @(
            Get-History `
                -ErrorAction SilentlyContinue |
            Sort-Object Id -Descending
        )


    foreach ($item in $items) {

        $command = [string]$item.CommandLine


        if (
            -not (
                Test-CopyLastHelperCommand `
                    -Command $command
            )
        ) {
            return $item
        }
    }


    return $null
}


# ---------------------------------------------------------------------
# Convert fully flushed transcript into:
#
# PS C:\Repo> git status
# On branch ...
# ...
# ---------------------------------------------------------------------

function global:ConvertFrom-CopyLastTranscript {

    param(
        [Parameter(Mandatory)]
        [string]$RawTranscript,

        [Parameter(Mandatory)]
        [string]$Command
    )


    $text =
        Remove-CopyLastEscapes `
            -Text $RawTranscript


    $text = $text -replace "`r`n", "`n"
    $text = $text -replace "`r", "`n"


    $Command = $Command -replace "`r`n", "`n"
    $Command = $Command -replace "`r", "`n"


    $lines =
        @($text -split "`n")


    $commandLines =
        @($Command -split "`n")


    if ($commandLines.Count -eq 0) {
        return $null
    }


    $firstCommandLine =
        $commandLines[0].Trim()


    # -------------------------------------------------------------
    # Find the LAST transcript occurrence of the target command.
    # -------------------------------------------------------------

    $commandIndex = -1
    $commandStyle = ""
    $header = $null


    for (
        $i = $lines.Count - 1
        $i -ge 0
        $i--
    ) {

        $line = $lines[$i]


        # PowerShell transcript style:
        #
        # PS>git status
        # PS> git status

        if ($line -match '^\s*PS>\s?(.*)$') {

            $candidate =
                $Matches[1].Trim()


            if ($candidate -eq $firstCommandLine) {

                $commandIndex = $i
                $commandStyle = "PSGreater"

                break
            }
        }


        # Normal terminal-style command:
        #
        # PS D:\Repo> git status

        if ($line -match '^\s*(PS\s+.+?>)\s*(.*)$') {

            $promptPart =
                $Matches[1].Trim()

            $candidate =
                $Matches[2].Trim()


            if ($candidate -eq $firstCommandLine) {

                $commandIndex = $i
                $commandStyle = "FullPrompt"

                $header =
                    "$promptPart $Command"

                break
            }
        }
    }


    if ($commandIndex -lt 0) {
        return $null
    }


    # -------------------------------------------------------------
    # If transcript used:
    #
    # PS D:\Repo>
    # PS>git status
    #
    # recover the real prompt from before PS>git status.
    # -------------------------------------------------------------

    if ($commandStyle -eq "PSGreater") {

        $promptPrefix = $null


        for (
            $j = $commandIndex - 1
            $j -ge 0
            $j--
        ) {

            $candidateLine =
                $lines[$j].Trim()


            if (
                $candidateLine -match
                '^PS\s+.+?>\s*$'
            ) {

                $promptPrefix =
                    $candidateLine.TrimEnd()

                break
            }


            # Don't scan through an old transcript section forever.
            if ($candidateLine -match '^\*{10,}$') {
                break
            }
        }


        if ($promptPrefix) {

            if ($commandLines.Count -eq 1) {

                $header =
                    "$promptPrefix $Command"
            }
            else {

                $headerParts =
                    [System.Collections.Generic.List[string]]::new()


                $headerParts.Add(
                    "$promptPrefix $($commandLines[0])"
                )


                for (
                    $n = 1
                    $n -lt $commandLines.Count
                    $n++
                ) {

                    $headerParts.Add(
                        ">> $($commandLines[$n])"
                    )
                }


                $header =
                    $headerParts -join "`r`n"
            }
        }
        else {

            $header =
                "PS> $Command"
        }
    }


    # -------------------------------------------------------------
    # Skip transcripted continuation command lines for multiline
    # PowerShell commands.
    # -------------------------------------------------------------

    $outputStart =
        $commandIndex + 1


    if ($commandLines.Count -gt 1) {

        for (
            $n = 1
            $n -lt $commandLines.Count
            $n++
        ) {

            if ($outputStart -ge $lines.Count) {
                break
            }


            $line =
                $lines[$outputStart]


            if ($line -match '^\s*>>\s?(.*)$') {

                if (
                    $Matches[1].Trim() -eq
                    $commandLines[$n].Trim()
                ) {

                    $outputStart++
                }
            }
        }
    }


    # -------------------------------------------------------------
    # Find the helper command that caused us to flush the transcript.
    #
    # That gives us an exact end point for the output.
    # -------------------------------------------------------------

    $outputEnd =
        $lines.Count


    for (
        $i = $outputStart
        $i -lt $lines.Count
        $i++
    ) {

        $line =
            $lines[$i]


        # PS>clast

        if (
            $line -match
            '^\s*PS>\s*(clast|copylast|copylast-show|copylast-reset)(\s|$)'
        ) {

            $outputEnd = $i
            break
        }


        # PS C:\Repo> clast

        if (
            $line -match
            '^\s*PS\s+.+?>\s*(clast|copylast|copylast-show|copylast-reset)(\s|$)'
        ) {

            $outputEnd = $i
            break
        }
    }


    # -------------------------------------------------------------
    # If no helper boundary was detected, stop at transcript footer.
    # -------------------------------------------------------------

    if ($outputEnd -eq $lines.Count) {

        for (
            $i = $outputStart
            $i -lt $lines.Count
            $i++
        ) {

            if (
                $lines[$i].Trim() -match
                '^\*{10,}$'
            ) {

                $outputEnd = $i
                break
            }
        }
    }


    # -------------------------------------------------------------
    # Collect output
    # -------------------------------------------------------------

    $output =
        [System.Collections.Generic.List[string]]::new()


    for (
        $i = $outputStart
        $i -lt $outputEnd
        $i++
    ) {

        $output.Add(
            $lines[$i]
        )
    }


    # -------------------------------------------------------------
    # Remove trailing prompt-only lines.
    #
    # Example:
    #
    # PS D:\Repo>
    #
    # just before:
    #
    # PS>clast
    # -------------------------------------------------------------

    while ($output.Count -gt 0) {

        $last =
            $output[$output.Count - 1]


        if ([string]::IsNullOrWhiteSpace($last)) {

            $output.RemoveAt(
                $output.Count - 1
            )

            continue
        }


        if (
            $last.Trim() -match
            '^PS\s+.+?>\s*$'
        ) {

            $output.RemoveAt(
                $output.Count - 1
            )

            continue
        }


        if (
            $last.Trim() -eq "PS>"
        ) {

            $output.RemoveAt(
                $output.Count - 1
            )

            continue
        }


        break
    }


    # Remove blank lines before output begins.

    while (
        $output.Count -gt 0 -and
        [string]::IsNullOrWhiteSpace(
            $output[0]
        )
    ) {

        $output.RemoveAt(0)
    }


    # -------------------------------------------------------------
    # Build result
    # -------------------------------------------------------------

    if ($output.Count -eq 0) {
        return $header.TrimEnd()
    }


    $outputText =
        ($output -join "`r`n").TrimEnd()


    return (
        $header.TrimEnd() +
        "`r`n" +
        $outputText
    )
}


# ---------------------------------------------------------------------
# Flush transcript + extract latest command/output
# ---------------------------------------------------------------------

function global:Get-CopyLastBlock {

    $state =
        $global:CopyLastState


    $historyItem =
        Get-CopyLastHistoryCommand


    if (-not $historyItem) {
        return $null
    }


    $command =
        [string]$historyItem.CommandLine


    # -------------------------------------------------------------
    # THIS IS THE IMPORTANT V5 CHANGE:
    #
    # Stop-Transcript forces native output such as git.exe,
    # dotnet.exe, npm.exe, etc. to actually reach the file.
    # -------------------------------------------------------------

    Stop-CopyLastTranscript


    try {

        if (
            -not (
                Test-Path `
                    -LiteralPath $state.Transcript
            )
        ) {

            return $null
        }


        $raw =
            Get-Content `
                -LiteralPath $state.Transcript `
                -Raw `
                -ErrorAction Stop


        $result =
            ConvertFrom-CopyLastTranscript `
                -RawTranscript $raw `
                -Command $command


        return $result
    }
    finally {

        # Immediately resume capturing future commands.

        $null =
            Start-CopyLastTranscript
    }
}


# ---------------------------------------------------------------------
# copylast / clast
# ---------------------------------------------------------------------

function global:copylast {

    $text =
        Get-CopyLastBlock


    if ([string]::IsNullOrWhiteSpace($text)) {

        Write-Warning @"
CopyLast could not find a complete previous command.

Run a normal command first, for example:

    git status

Then run:

    clast
"@

        return
    }


    $global:CopyLastState.LastBlock =
        $text


    Set-Clipboard `
        -Value $text


    Write-Host `
        "Copied previous command + output to clipboard." `
        -ForegroundColor Green
}


# ---------------------------------------------------------------------
# Preview without changing clipboard
# ---------------------------------------------------------------------

function global:copylast-show {

    $text =
        Get-CopyLastBlock


    if ([string]::IsNullOrWhiteSpace($text)) {

        Write-Warning `
            "CopyLast could not find a complete previous command."

        return
    }


    $global:CopyLastState.LastBlock =
        $text


    Write-Host ""
    Write-Host "----- COPYLAST PREVIEW -----"
    Write-Host ""

    Write-Host $text

    Write-Host ""
    Write-Host "----------------------------"
}


# ---------------------------------------------------------------------
# Reset
# ---------------------------------------------------------------------

function global:copylast-reset {

    Stop-CopyLastTranscript


    try {

        Clear-Content `
            -LiteralPath $global:CopyLastState.Transcript `
            -ErrorAction SilentlyContinue


        $global:CopyLastState.LastBlock =
            $null
    }
    finally {

        $null =
            Start-CopyLastTranscript
    }


    Write-Host `
        "CopyLast transcript reset." `
        -ForegroundColor Yellow
}


# ---------------------------------------------------------------------
# Initialize
# ---------------------------------------------------------------------

$oldCopyLastState = $null


if (
    Get-Variable `
        -Name CopyLastState `
        -Scope Global `
        -ErrorAction SilentlyContinue
) {

    $oldCopyLastState =
        $global:CopyLastState


    try {

        if (
            $oldCopyLastState.TranscriptRunning
        ) {

            Stop-Transcript `
                -ErrorAction SilentlyContinue |
                Out-Null
        }
    }
    catch {
    }
}


$transcriptPath =
    Join-Path `
        $env:TEMP `
        "pwsh-copylast-$PID.log"


$global:CopyLastState =
    [pscustomobject]@{

        Version           = $global:CopyLastVersion

        Transcript        = $transcriptPath

        TranscriptRunning = $false

        LastBlock         = $null
    }


$null =
    Start-CopyLastTranscript


Set-Alias `
    -Name clast `
    -Value copylast `
    -Scope Global `
    -Force


Write-Host `
    "CopyLast v5.0.0 loaded - use 'clast'." `
    -ForegroundColor DarkGray

# <<< COPYLAST END <<<
