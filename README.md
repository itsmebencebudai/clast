# CopyLast

CopyLast is a small PowerShell helper that copies the most recent command and
its visible output to the clipboard. It uses PowerShell's transcript and does
not replace or wrap the prompt.

## Requirements

- Windows
- PowerShell 7 or later
- `Set-Clipboard` available in the current session

## Install

1. Clone this repository or save `CopyLast.ps1` in a permanent location.
2. Open your PowerShell profile:

   ```powershell
   notepad $PROFILE
   ```

3. Back up the profile. Remove any older inline CopyLast v4/v4.1/v5 blocks,
   then add a dot-source line pointing to the saved script. For example, if you
   cloned the repository to `C:\src\clast`, add:

   ```powershell
   . 'C:\src\clast\CopyLast.ps1'
   ```

4. Start a new PowerShell session. It should print:

   ```text
   CopyLast v5.0.0 loaded - use 'clast'.
   ```

To load it in the current session without restarting, run the same dot-source
line directly.

## Use

Run a command, then preview or copy it:

```powershell
git status
copylast-show
clast
```

- `copylast-show` previews the captured command and output without changing the
  clipboard.
- `clast` and `copylast` copy the captured block to the clipboard.
- `copylast-reset` clears the current session's transcript and starts a fresh
  one.

CopyLast skips its own helper commands when it selects the previous command.
Its transcript is stored in the Windows temporary directory as
`pwsh-copylast-<process-id>.log`.

## Privacy

The transcript contains commands and output from the current PowerShell
session. It stays in the local temporary directory, but may include secrets or
other sensitive text printed by a command. Avoid printing credentials in a
session using CopyLast, and run `copylast-reset` when you want to clear the
current transcript.

## How it works

CopyLast v5 briefly stops `Start-Transcript` when a helper command runs, reads
the flushed transcript, extracts the last non-CopyLast command and its output,
then restarts transcription. It strips terminal control sequences from the
captured text and formats the result with the original PowerShell prompt.

## License

MIT. See [LICENSE](LICENSE).
