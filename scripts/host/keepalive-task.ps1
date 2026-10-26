<#
.SYNOPSIS
Register, inspect, start, or stop the Windows login task that keeps the Nidrew
Debian server running.

.DESCRIPTION
Runs as the invoking Windows user; administrator rights are not required. The
task belongs to that user, runs only while the user is logged on, starts at
the user's logon, and runs
    wsl.exe --distribution <Distribution> --user <LinuxUser> --exec sleep infinity
through conhost.exe --headless so no console window opens. The sleep keeps the
WSL instance, and with it systemd, Nix, and Harmonia, running after
interactive shells close.

Settings: no execution time limit, a second start is ignored while the first
runs, no restart on failure (an explicit wsl.exe --shutdown stays in effect
until the next logon or -Action Start), runs on battery, no idle conditions,
and never wakes the computer.

Actions:
  Register  Create the task, or update a task this script created. Any other
            task with the same name is kept and reported. Changes nothing
            when the task already matches.
  Status    Report the task definition and whether the keepalive is running.
            Changes nothing.
  Start     Start the task unless the keepalive is already running.
  Stop      Stop the task and its wsl.exe processes, ending the sleep. WSL may
            then stop Debian once no other client uses it.

Task Scheduler tracks only conhost.exe: stopping the task alone leaves
wsl.exe and the sleep running, so Status and Stop look at the processes.

Exit status: 0 on success, 1 on a conflict, a mismatch, or a failed check.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File scripts\host\keepalive-task.ps1 -Action Register
#>
[CmdletBinding()]
param(
    [ValidateSet('Register', 'Status', 'Start', 'Stop')]
    [string]$Action = 'Status',
    # WSL distribution that hosts the Nidrew server.
    [string]$Distribution = 'Debian',
    # Linux account that runs the sleep; the unprivileged operational account.
    [string]$LinuxUser = 'nidrew',
    # Task name in the Task Scheduler root folder.
    [string]$TaskName = ''
)

# Identifies tasks this script manages; a task without it is never changed.
$KeepaliveMarker = 'Nidrew Debian keepalive; managed by scripts/host/keepalive-task.ps1'

function Get-KeepaliveTail([string]$Distribution, [string]$LinuxUser) {
    "--distribution $Distribution --user $LinuxUser --exec sleep infinity"
}

function New-KeepaliveTask([string]$Distribution, [string]$LinuxUser, [string]$UserId) {
    foreach ($name in $Distribution, $LinuxUser) {
        if ($name -notmatch '^[A-Za-z0-9._-]+$') { throw "Unsupported name: '$name'" }
    }
    $wsl = "$env:SystemRoot\System32\wsl.exe"
    $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\conhost.exe" `
        -Argument "--headless $wsl $(Get-KeepaliveTail $Distribution $LinuxUser)"
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $UserId
    $principal = New-ScheduledTaskPrincipal -UserId $UserId -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -DontStopOnIdleEnd
    $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings
    $task.Description = $KeepaliveMarker
    $task
}

function ConvertTo-Sid([string]$Account) {
    if (-not $Account) { return '' }
    if ($Account -match '^S-1-') { return $Account }
    try {
        (New-Object Security.Principal.NTAccount $Account).Translate([Security.Principal.SecurityIdentifier]).Value
    } catch {
        $Account
    }
}

# Reduces a task, registered or built in memory, to the fields this script
# manages, so both compare the same way.
function ConvertTo-KeepaliveSummary($Task) {
    $actions = @($Task.Actions)
    $triggers = @($Task.Triggers)
    $settings = $Task.Settings
    [ordered]@{
        Description                = [string]$Task.Description
        ActionCount                = $actions.Count
        Execute                    = [string]$actions[0].Execute
        Arguments                  = [string]$actions[0].Arguments
        TriggerCount               = $triggers.Count
        TriggerType                = [string]$triggers[0].CimClass.CimClassName
        TriggerUser                = ConvertTo-Sid $triggers[0].UserId
        TriggerEnabled             = [bool]$triggers[0].Enabled
        UserId                     = ConvertTo-Sid $Task.Principal.UserId
        LogonType                  = [string]$Task.Principal.LogonType
        RunLevel                   = [string]$Task.Principal.RunLevel
        ExecutionTimeLimit         = [string]$settings.ExecutionTimeLimit
        MultipleInstances          = [string]$settings.MultipleInstances
        DisallowStartIfOnBatteries = [bool]$settings.DisallowStartIfOnBatteries
        StopIfGoingOnBatteries     = [bool]$settings.StopIfGoingOnBatteries
        RunOnlyIfIdle              = [bool]$settings.RunOnlyIfIdle
        StopOnIdleEnd              = [bool]$settings.IdleSettings.StopOnIdleEnd
        WakeToRun                  = [bool]$settings.WakeToRun
        RestartCount               = [int]$settings.RestartCount
        Enabled                    = [bool]$settings.Enabled
    }
}

# missing, matching, outdated (a managed task with other settings), or
# conflict (another task, or one owned by another user).
function Get-KeepaliveTaskState($Task, $Desired) {
    if (-not $Task) { return @{ State = 'missing'; Differences = @() } }
    $actual = ConvertTo-KeepaliveSummary $Task
    if ($actual.Description -ne $KeepaliveMarker) {
        return @{ State = 'conflict'; Differences = @('Description') }
    }
    if ($actual.UserId -ne $Desired.UserId) {
        return @{ State = 'conflict'; Differences = @('UserId') }
    }
    $differences = @($Desired.Keys | Where-Object { $Desired[$_] -ne $actual[$_] })
    if ($differences.Count -eq 0) { return @{ State = 'matching'; Differences = @() } }
    @{ State = 'outdated'; Differences = $differences }
}

function Test-KeepaliveProcess([string]$Name, [string]$CommandLine, [string]$Distribution, [string]$LinuxUser) {
    if ($Name -notin 'conhost.exe', 'wsl.exe' -or -not $CommandLine) { return $false }
    $CommandLine.TrimEnd().EndsWith(" $(Get-KeepaliveTail $Distribution $LinuxUser)")
}

function Get-KeepaliveProcess([string]$Distribution, [string]$LinuxUser) {
    @(Get-CimInstance Win32_Process -Filter "Name='conhost.exe' or Name='wsl.exe'" |
        Where-Object { Test-KeepaliveProcess $_.Name $_.CommandLine $Distribution $LinuxUser })
}

# Dot-sourcing loads the functions for tests without running an action.
if ($MyInvocation.InvocationName -eq '.') { return }

# wsl.exe writes UTF-16 for its own messages unless WSL_UTF8 is set.
$env:WSL_UTF8 = '1'
if (-not $TaskName) { $TaskName = "Nidrew Keepalive $Distribution" }
$userId = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$desiredTask = New-KeepaliveTask $Distribution $LinuxUser $userId
$desired = ConvertTo-KeepaliveSummary $desiredTask
$task = Get-ScheduledTask -TaskPath '\' -TaskName $TaskName -ErrorAction SilentlyContinue
$state = Get-KeepaliveTaskState $task $desired

function Write-Conflict {
    Write-Output "[FAIL] task: '\$TaskName' exists and was not created by this script for $userId; it is kept unchanged."
    Write-Output "       Inspect it in Task Scheduler. Delete it there if it is an older keepalive, or pass -TaskName to use another name."
}

switch ($Action) {
    'Register' {
        if ($state.State -eq 'conflict') { Write-Conflict; exit 1 }
        if ($state.State -eq 'matching') {
            Write-Output "[ ok ] task: '\$TaskName' unchanged"
            exit 0
        }
        & wsl.exe --distribution $Distribution --user $LinuxUser --exec true
        if ($LASTEXITCODE -ne 0) {
            Write-Output "[FAIL] wsl: cannot run a command as $LinuxUser in $Distribution; run scripts\host\check-prerequisites.ps1 and the account provisioning first."
            exit 1
        }
        $verb = if ($state.State -eq 'missing') { 'created' } else { 'updated ' + ($state.Differences -join ', ') }
        Register-ScheduledTask -TaskPath '\' -TaskName $TaskName -InputObject $desiredTask -Force -ErrorAction Stop | Out-Null
        Write-Output "[ ok ] task: '\$TaskName' $verb; it starts at your next logon or with -Action Start"
        exit 0
    }
    'Status' {
        $failed = $false
        switch ($state.State) {
            'missing' { Write-Output "[FAIL] task: '\$TaskName' is not registered; run -Action Register"; $failed = $true }
            'conflict' { Write-Conflict; $failed = $true }
            'outdated' { Write-Output "[FAIL] task: '\$TaskName' differs in $($state.Differences -join ', '); run -Action Register"; $failed = $true }
            'matching' {
                $info = Get-ScheduledTaskInfo -TaskPath '\' -TaskName $TaskName
                Write-Output ("[ ok ] task: '\{0}' as {1}, at logon, {2}" -f $TaskName, $userId, $desired.Arguments)
                Write-Output ("[ ok ] task state: {0}; last run {1}, result 0x{2:X}" -f $task.State, $info.LastRunTime, $info.LastTaskResult)
            }
        }
        $processes = Get-KeepaliveProcess $Distribution $LinuxUser
        $wslCount = @($processes | Where-Object Name -eq 'wsl.exe').Count
        if ($wslCount -gt 0) {
            Write-Output "[ ok ] processes: $wslCount wsl.exe running the keepalive"
        } else {
            Write-Output "[FAIL] processes: no keepalive wsl.exe is running; run -Action Start"
            $failed = $true
        }
        $sleeps = & wsl.exe --distribution $Distribution --exec pgrep -c -x -u $LinuxUser -f 'sleep infinity'
        if ($LASTEXITCODE -eq 0) {
            Write-Output "[ ok ] debian: $sleeps 'sleep infinity' process(es) as $LinuxUser"
        } else {
            Write-Output "[FAIL] debian: no 'sleep infinity' process as $LinuxUser in $Distribution"
            $failed = $true
        }
        if ($failed) { exit 1 }
        exit 0
    }
    'Start' {
        if ($state.State -ne 'matching') {
            Write-Output "[FAIL] task: '\$TaskName' is $($state.State); run -Action Status"
            exit 1
        }
        if (@(Get-KeepaliveProcess $Distribution $LinuxUser | Where-Object Name -eq 'wsl.exe').Count -gt 0) {
            Write-Output "[ ok ] keepalive is already running"
            exit 0
        }
        Start-ScheduledTask -TaskPath '\' -TaskName $TaskName -ErrorAction Stop
        foreach ($i in 1..20) {
            Start-Sleep -Milliseconds 500
            if (@(Get-KeepaliveProcess $Distribution $LinuxUser | Where-Object Name -eq 'wsl.exe').Count -gt 0) {
                Write-Output "[ ok ] keepalive started"
                exit 0
            }
        }
        Write-Output "[FAIL] keepalive did not start; see the task's history in Task Scheduler"
        exit 1
    }
    'Stop' {
        if ($state.State -eq 'conflict') { Write-Conflict; exit 1 }
        if ($task) { Stop-ScheduledTask -TaskPath '\' -TaskName $TaskName }
        $processes = Get-KeepaliveProcess $Distribution $LinuxUser
        foreach ($process in $processes) {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        }
        Write-Output "[ ok ] keepalive stopped ($($processes.Count) process(es))"
        exit 0
    }
}
